-- =============================================================
-- 三人五子棋 · 0002_online_features.sql
-- 心跳掉线检测 / AI 托管 / 断线重连 / 再来一局 / AI 难度 / 房间清理
-- 在 0001_init.sql 之后执行（create or replace，可重复执行）
-- =============================================================

-- ---------- 0) 修复 gen_room_code：变量与 rooms.code 列撞名导致 ambiguous ----------
create or replace function public.gen_room_code()
returns text language plpgsql as $$
declare
  chars constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; -- 去掉 I/O/0/1 易混淆
  v_code text;
begin
  loop
    v_code := '';
    for i in 1..6 loop
      v_code := v_code || substr(chars, 1 + floor(random() * length(chars))::int, 1);
    end loop;
    exit when not exists (select 1 from public.rooms r where r.code = v_code);
  end loop;
  return v_code;
end $$;

-- ---------- 1) rooms 增加难度列 ----------
alter table public.rooms add column if not exists ai_difficulty text not null default 'medium';

-- ---------- 2) create_room：增加难度参数；座位带 last_seen/taken_over；懒清理 ----------
create or replace function public.create_room(player_name text, ai_count int, ai_difficulty text default 'medium')
returns public.rooms language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  r public.rooms;
  pl jsonb;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if ai_count < 0 or ai_count > 2 then raise exception 'invalid ai_count'; end if;
  if ai_difficulty not in ('easy', 'medium') then ai_difficulty := 'medium'; end if;

  -- 懒清理过期房间
  perform public.cleanup_stale_rooms();

  pl := jsonb_build_array(
    jsonb_build_object('slot',0,'name',player_name,'is_ai',false,'uid',uid,'connected',true,'last_seen',now(),'taken_over',false),
    jsonb_build_object('slot',1),
    jsonb_build_object('slot',2)
  );
  if ai_count >= 1 then
    pl := jsonb_set(pl, '{2}', jsonb_build_object('slot',2,'name','AI','is_ai',true,'uid',null,'connected',true,'last_seen',now(),'taken_over',false));
  end if;
  if ai_count = 2 then
    pl := jsonb_set(pl, '{1}', jsonb_build_object('slot',1,'name','AI','is_ai',true,'uid',null,'connected',true,'last_seen',now(),'taken_over',false));
  end if;

  insert into public.rooms (code, host_id, member_ids, players, status, ai_difficulty)
  values (public.gen_room_code(), uid, array[uid], pl,
          case when ai_count = 2 then 'playing' else 'waiting' end, ai_difficulty)
  returning * into r;
  return r;
end $$;

-- ---------- 3) join_room：支持恢复被托管座位（断线重连） ----------
create or replace function public.join_room(p_code text, player_name text)
returns public.rooms language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  r public.rooms;
  i int;
  empty_slot int := -1;
  empty_cnt int := 0;
  new_status text;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into r from public.rooms where code = upper(trim(p_code));
  if r.id is null then raise exception 'room not found'; end if;

  -- 已是成员：若座位被 AI 托管，则恢复控制权
  if uid = any(r.member_ids) then
    for i in 0..2 loop
      if (r.players->i->>'uid')::uuid = uid
         and coalesce((r.players->i->>'taken_over')::bool, false) then
        r.players := jsonb_set(r.players, array[i::text, 'is_ai'], 'false'::jsonb);
        r.players := jsonb_set(r.players, array[i::text, 'connected'], 'true'::jsonb);
        r.players := jsonb_set(r.players, array[i::text, 'taken_over'], 'false'::jsonb);
        r.players := jsonb_set(r.players, array[i::text, 'last_seen'], to_jsonb(now()));
        update public.rooms set players = r.players where id = r.id returning * into r;
        exit;
      end if;
    end loop;
    return r;
  end if;

  if r.status <> 'waiting' then raise exception 'room already started'; end if;

  for i in 0..2 loop
    if (r.players->i->>'is_ai') is null and (r.players->i->>'uid') is null then
      empty_slot := i; exit;
    end if;
  end loop;
  if empty_slot < 0 then raise exception 'room full'; end if;

  select count(*) into empty_cnt from jsonb_array_elements(r.players) e
   where (e->>'is_ai') is null and (e->>'uid') is null;
  new_status := case when empty_cnt = 1 then 'playing' else 'waiting' end;

  update public.rooms set
    players = jsonb_set(players, array[empty_slot::text],
      jsonb_build_object('slot',empty_slot,'name',player_name,'is_ai',false,'uid',uid,'connected',true,'last_seen',now(),'taken_over',false)),
    member_ids = array_append(member_ids, uid),
    status = new_status
  where id = r.id
  returning * into r;
  return r;
end $$;

-- ---------- 4) leave_room：对局中离开转托管但保留 uid（供重连恢复） ----------
create or replace function public.leave_room(room_id uuid)
returns public.rooms language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  r public.rooms;
  i int;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into r from public.rooms where id = room_id;
  if r.id is null then raise exception 'room not found'; end if;
  for i in 0..2 loop
    if (r.players->i->>'uid')::uuid = uid then
      if r.status = 'waiting' then
        r.players := jsonb_set(r.players, array[i::text], jsonb_build_object('slot', i));
        r.member_ids := array_remove(r.member_ids, uid);
      else
        r.players := jsonb_set(r.players, array[i::text],
          jsonb_build_object('slot', i, 'name', 'AI(托管)', 'is_ai', true, 'uid', uid,
                             'connected', false, 'last_seen', now(), 'taken_over', true));
      end if;
      exit;
    end if;
  end loop;
  update public.rooms set players = r.players, member_ids = r.member_ids where id = r.id returning * into r;
  return r;
end $$;

-- ---------- 5) set_connected：更新 last_seen 心跳 ----------
create or replace function public.set_connected(room_id uuid, connected bool)
returns public.rooms language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  r public.rooms;
  i int;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into r from public.rooms where id = room_id;
  if r.id is null then raise exception 'room not found'; end if;
  for i in 0..2 loop
    if (r.players->i->>'uid')::uuid = uid then
      r.players := jsonb_set(r.players, array[i::text, 'connected'], to_jsonb(connected));
      r.players := jsonb_set(r.players, array[i::text, 'last_seen'], to_jsonb(now()));
      exit;
    end if;
  end loop;
  update public.rooms set players = r.players where id = r.id returning * into r;
  return r;
end $$;

-- ---------- 6) take_over：掉线座位转 AI 托管（服务端原子校验，幂等） ----------
create or replace function public.take_over(room_id uuid, slot int)
returns public.rooms language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  r public.rooms;
  p jsonb;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into r from public.rooms where id = room_id;
  if r.id is null then raise exception 'room not found'; end if;
  if not (uid = any(r.member_ids)) then raise exception 'not a member'; end if;
  if r.status <> 'playing' then raise exception 'not playing'; end if;
  if slot < 0 or slot > 2 then raise exception 'invalid slot'; end if;
  p := (r.players->slot);
  if p is null then raise exception 'invalid slot'; end if;
  if coalesce((p->>'is_ai')::bool, false) then return r; end if; -- 已托管，幂等
  if (p->>'uid')::uuid = uid then raise exception 'cannot take over yourself'; end if;
  if (p->>'last_seen') is not null
     and (p->>'last_seen')::timestamptz > now() - interval '90 seconds' then
    raise exception 'player still online';
  end if;
  r.players := jsonb_set(r.players, array[slot::text],
    jsonb_build_object('slot', slot, 'name', 'AI(托管)', 'is_ai', true, 'uid', (p->>'uid'),
                       'connected', false, 'last_seen', now(), 'taken_over', true));
  update public.rooms set players = r.players where id = r.id returning * into r;
  return r;
end $$;

-- ---------- 7) reset_room：再来一局 ----------
create or replace function public.reset_room(room_id uuid)
returns public.rooms language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  r public.rooms;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into r from public.rooms where id = room_id;
  if r.id is null then raise exception 'room not found'; end if;
  if not (uid = any(r.member_ids)) then raise exception 'not a member'; end if;
  if r.status <> 'finished' then raise exception 'game not finished'; end if;
  update public.rooms set board = repeat('0',361), turn = 0, status = 'playing', winner = null
  where id = r.id returning * into r;
  return r;
end $$;

-- ---------- 8) cleanup_stale_rooms：过期房间清理 ----------
create or replace function public.cleanup_stale_rooms()
returns int language plpgsql security definer set search_path = public as $$
declare
  n int;
begin
  delete from public.rooms
   where (status = 'finished' and updated_at < now() - interval '24 hours')
      or (status = 'waiting'  and updated_at < now() - interval '1 hour')
      or (status = 'playing'  and updated_at < now() - interval '7 days');
  get diagnostics n = row_count;
  return n;
end $$;

-- ---------- 9) pg_cron 定时清理（可选：未装 pg_cron 则跳过，懒清理兜底） ----------
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('cleanup-rooms', '0 * * * *', 'select public.cleanup_stale_rooms()');
  end if;
end $$;

-- ---------- 授权 ----------
grant execute on function public.create_room(text,int,text) to authenticated;
grant execute on function public.join_room(text,text) to authenticated;
grant execute on function public.set_connected(uuid,bool) to authenticated;
grant execute on function public.leave_room(uuid) to authenticated;
grant execute on function public.take_over(uuid,int) to authenticated;
grant execute on function public.reset_room(uuid) to authenticated;
grant execute on function public.cleanup_stale_rooms() to authenticated;
