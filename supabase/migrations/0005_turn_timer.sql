-- =============================================================
-- 三人五子棋 · 0005_turn_timer.sql
-- 回合计时 + 超时 AI 代下
-- 在 0001/0002/0003/0004 之后执行（create or replace，可重复执行）
-- =============================================================

-- ---------- 0) rooms 加列 ----------
alter table public.rooms add column if not exists turn_timeout_sec int;       -- null = 不限时
alter table public.rooms add column if not exists move_deadline timestamptz;  -- null = 不适用

-- ---------- 1) 辅助：计算下一手截止时间 ----------
-- playing 且当前回合座位是人（非 AI）且限时非空 → now() + 限时；否则 null
create or replace function public.compute_deadline(r public.rooms)
returns timestamptz language plpgsql as $$
declare
  p jsonb;
begin
  if r.status <> 'playing' or r.turn_timeout_sec is null
     or r.turn < 0 or r.turn > 2 then
    return null;
  end if;
  p := r.players->r.turn;
  if p is null or coalesce((p->>'is_ai')::bool, false) then
    return null;
  end if;
  return now() + make_interval(secs => r.turn_timeout_sec);
end $$;

-- ---------- 2) create_room：加限时参数 ----------
create or replace function public.create_room(
  player_name text, ai_count int, ai_difficulty text default 'medium',
  turn_timeout_sec int default null)
returns public.rooms language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  r public.rooms;
  pl jsonb;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if ai_count < 0 or ai_count > 2 then raise exception 'invalid ai_count'; end if;
  if ai_difficulty not in ('easy', 'medium', 'hard') then ai_difficulty := 'medium'; end if;
  if turn_timeout_sec is not null and (turn_timeout_sec < 15 or turn_timeout_sec > 600) then
    raise exception 'invalid turn_timeout_sec';
  end if;

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

  insert into public.rooms (code, host_id, member_ids, players, status, ai_difficulty, turn_timeout_sec)
  values (public.gen_room_code(), uid, array[uid], pl,
          case when ai_count = 2 then 'playing' else 'waiting' end, ai_difficulty, turn_timeout_sec)
  returning * into r;
  r.move_deadline := public.compute_deadline(r);
  update public.rooms set move_deadline = r.move_deadline where id = r.id;
  select * into r from public.rooms where id = r.id;
  return r;
end $$;

-- ---------- 3) join_room：末位加入转 playing 时设置截止时间 ----------
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
  r.move_deadline := public.compute_deadline(r);
  update public.rooms set move_deadline = r.move_deadline where id = r.id;
  select * into r from public.rooms where id = r.id;
  return r;
end $$;

-- ---------- 4) submit_move：超时校验 + 超时 AI 代下 + 刷新截止时间 ----------
create or replace function public.submit_move(
  room_id uuid, slot int, rrow int, ccol int, as_timeout_ai bool default false)
returns public.rooms language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  r public.rooms;
  p jsonb;
  is_ai bool;
  idx int;
  cell text;
  winner_slot int;
  l1 int; l2 int; l3 int;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into r from public.rooms where id = room_id;
  if r.id is null then raise exception 'room not found'; end if;
  if not (uid = any(r.member_ids)) then raise exception 'not a member'; end if;
  if r.status <> 'playing' then raise exception 'not playing'; end if;
  if r.turn <> slot then raise exception 'not your turn'; end if;
  if rrow < 0 or rrow > 18 or ccol < 0 or ccol > 18 then raise exception 'out of bounds'; end if;

  p := (r.players->slot);
  if p is null then raise exception 'invalid slot'; end if;
  is_ai := coalesce((p->>'is_ai')::bool, false);

  if as_timeout_ai then
    -- 超时代下：任何成员可在截止时间过后代该座落子（解锁卡局）
    if r.move_deadline is null or r.move_deadline >= now() then
      raise exception 'not timed out';
    end if;
  else
    if not is_ai and (p->>'uid')::uuid <> uid then raise exception 'not your seat'; end if;
    if not is_ai and r.move_deadline is not null and r.move_deadline < now() then
      raise exception 'move timed out';
    end if;
  end if;

  idx := rrow*19 + ccol;
  cell := substr(r.board, idx+1, 1);
  if cell <> '0' then raise exception 'cell occupied'; end if;

  r.board := overlay(r.board placing (slot+1)::text from idx+1 for 1);
  winner_slot := public.check_win(r.board, rrow, ccol);

  if winner_slot is not null then
    r.status := 'finished'; r.winner := winner_slot; r.turn := -1;
  elsif position('0' in r.board) = 0 then
    -- 满盘：按最长连子判胜
    l1 := public.longest_line(r.board, '1');
    l2 := public.longest_line(r.board, '2');
    l3 := public.longest_line(r.board, '3');
    r.status := 'finished'; r.turn := -1;
    if l1 > l2 and l1 > l3 then
      r.winner := 0;
    elsif l2 > l1 and l2 > l3 then
      r.winner := 1;
    elsif l3 > l1 and l3 > l2 then
      r.winner := 2;
    else
      r.winner := null; -- 并列 → 和棋
    end if;
  else
    r.turn := (slot + 1) % 3;
  end if;

  r.move_deadline := public.compute_deadline(r);

  update public.rooms set board = r.board, turn = r.turn, status = r.status,
                          winner = r.winner, move_deadline = r.move_deadline
  where id = r.id;
  select * into r from public.rooms where id = r.id;
  return r;
end $$;

-- ---------- 5) reset_room：再来一局时重置截止时间 ----------
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
  r.move_deadline := public.compute_deadline(r);
  update public.rooms set move_deadline = r.move_deadline where id = r.id;
  select * into r from public.rooms where id = r.id;
  return r;
end $$;

-- ---------- 6) leave_room / take_over：转 AI 托管后刷新截止时间 ----------
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
  r.move_deadline := public.compute_deadline(r);
  update public.rooms set move_deadline = r.move_deadline where id = r.id;
  select * into r from public.rooms where id = r.id;
  return r;
end $$;

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
  r.move_deadline := public.compute_deadline(r);
  update public.rooms set move_deadline = r.move_deadline where id = r.id;
  select * into r from public.rooms where id = r.id;
  return r;
end $$;

-- ---------- 7) 授权（新签名） ----------
grant execute on function public.create_room(text,int,text,int) to authenticated;
grant execute on function public.submit_move(uuid,int,int,int,bool) to authenticated;
