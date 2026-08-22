-- =============================================================
-- 三人五子棋 · 0006_undo.sql
-- 悔棋：moves 落子历史 + 其他真人座位全员同意撤销
-- 在 0001~0005 之后执行（create or replace，可重复执行）
-- =============================================================

-- ---------- 1) moves 表（落子历史；复盘也用它） ----------
create table if not exists public.moves (
  id         bigint generated always as identity primary key,
  room_id    uuid not null references public.rooms(id) on delete cascade,
  slot       int  not null,                -- 落子座位 0/1/2
  idx        int  not null,                -- row*19+col
  created_at timestamptz not null default now()
);
create index if not exists moves_room_id_idx on public.moves (room_id, id);

alter table public.moves enable row level security;
drop policy if exists "members_can_select_moves" on public.moves;
create policy "members_can_select_moves" on public.moves
  for select using (exists (
    select 1 from public.rooms r
    where r.id = room_id and auth.uid() = any(r.member_ids)
  ));

-- ---------- 2) rooms 加列 ----------
alter table public.rooms add column if not exists last_move_slot int;       -- 最后一步的座位（悔棋按钮可见性）
alter table public.rooms add column if not exists undo_slot int;            -- 待同意悔棋的发起座位
alter table public.rooms add column if not exists undo_accepts uuid[];      -- 已同意悔棋的成员
alter table public.rooms add column if not exists undo_expires_at timestamptz; -- 同意期限

-- ---------- 3) 重建棋盘（从 moves 重放） ----------
create or replace function public.board_from_moves(p_room uuid)
returns text language plpgsql as $$
declare
  b text := repeat('0', 361);
  m record;
begin
  for m in select slot, idx from public.moves where room_id = p_room order by id loop
    b := overlay(b placing (m.slot + 1)::text from m.idx + 1 for 1);
  end loop;
  return b;
end $$;

-- ---------- 4) do_undo：执行撤销（内部公共函数，不对外授权） ----------
create or replace function public.do_undo(p_room uuid)
returns public.rooms language plpgsql security definer set search_path = public as $$
declare
  r public.rooms;
  m record;
begin
  select * into r from public.rooms where id = p_room;
  if r.id is null then raise exception 'room not found'; end if;

  select slot into m from public.moves
   where room_id = p_room order by id desc limit 1;
  if m.slot is null then raise exception 'no moves to undo'; end if;

  delete from public.moves where room_id = p_room and id = (
    select max(id) from public.moves where room_id = p_room
  );

  update public.rooms set
    board = public.board_from_moves(p_room),
    turn  = m.slot,
    status = 'playing',
    winner = null,
    last_move_slot = (select slot from public.moves
                      where room_id = p_room order by id desc limit 1),
    undo_slot = null,
    undo_accepts = null,
    undo_expires_at = null
  where id = p_room returning * into r;

  r.move_deadline := public.compute_deadline(r);
  update public.rooms set move_deadline = r.move_deadline where id = p_room;
  select * into r from public.rooms where id = p_room;
  return r;
end $$;

-- ---------- 5) submit_move：记录落子 + pending 拦截 + 过期清理 ----------
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

  -- 悔棋 pending：未过期拦截；过期则清理继续
  if r.undo_expires_at is not null then
    if r.undo_expires_at > now() then
      raise exception 'undo pending';
    else
      r.undo_slot := null; r.undo_accepts := null; r.undo_expires_at := null;
    end if;
  end if;

  p := (r.players->slot);
  if p is null then raise exception 'invalid slot'; end if;
  is_ai := coalesce((p->>'is_ai')::bool, false);

  if as_timeout_ai then
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
      r.winner := null;
    end if;
  else
    r.turn := (slot + 1) % 3;
  end if;

  insert into public.moves (room_id, slot, idx) values (room_id, slot, idx);
  r.move_deadline := public.compute_deadline(r);

  update public.rooms set
    board = r.board, turn = r.turn, status = r.status, winner = r.winner,
    move_deadline = r.move_deadline, last_move_slot = slot,
    undo_slot = r.undo_slot, undo_accepts = r.undo_accepts, undo_expires_at = r.undo_expires_at
  where id = r.id;
  select * into r from public.rooms where id = r.id;
  return r;
end $$;

-- ---------- 6) request_undo：最后落子者发起 ----------
create or replace function public.request_undo(room_id uuid)
returns public.rooms language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  r public.rooms;
  last_m record;
  voters int := 0;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into r from public.rooms where id = room_id;
  if r.id is null then raise exception 'room not found'; end if;
  if not (uid = any(r.member_ids)) then raise exception 'not a member'; end if;
  if r.status <> 'playing' then raise exception 'not playing'; end if;

  -- 过期 pending 先清
  if r.undo_expires_at is not null and r.undo_expires_at <= now() then
    update public.rooms set undo_slot = null, undo_accepts = null, undo_expires_at = null
     where id = room_id;
    r.undo_slot := null; r.undo_accepts := null; r.undo_expires_at := null;
  end if;
  if r.undo_slot is not null then raise exception 'undo pending'; end if;

  select slot into last_m from public.moves
   where room_id = room_id order by id desc limit 1;
  if last_m.slot is null then raise exception 'no moves to undo'; end if;

  -- 必须是最后一步座位的原主人（含被 AI 代下的座位）
  if (r.players->last_m.slot->>'uid')::uuid <> uid then
    raise exception 'not your last move';
  end if;

  -- 其他真人座位投票者
  select count(*) into voters
    from jsonb_array_elements(r.players) p
   where (p->>'is_ai')::bool = false
     and (p->>'uid') is not null
     and (p->>'slot')::int <> last_m.slot;

  if voters = 0 then
    return public.do_undo(room_id); -- 无人需要同意，直接撤销
  end if;

  update public.rooms set
    undo_slot = last_m.slot,
    undo_accepts = '{}',
    undo_expires_at = now() + interval '30 seconds'
  where id = room_id returning * into r;
  return r;
end $$;

-- ---------- 7) respond_undo：同意/拒绝 ----------
create or replace function public.respond_undo(room_id uuid, accept bool)
returns public.rooms language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  r public.rooms;
  i int;
  my_slot int := -1;
  needed uuid[];
  covered bool;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into r from public.rooms where id = room_id;
  if r.id is null then raise exception 'room not found'; end if;
  if not (uid = any(r.member_ids)) then raise exception 'not a member'; end if;
  if r.undo_slot is null then raise exception 'no undo pending'; end if;
  if r.undo_expires_at is not null and r.undo_expires_at <= now() then
    raise exception 'undo expired';
  end if;
  if r.status <> 'playing' then raise exception 'not playing'; end if;

  for i in 0..2 loop
    if (r.players->i->>'uid')::uuid = uid then my_slot := i; exit; end if;
  end loop;
  if my_slot < 0 then raise exception 'not a member'; end if;
  if my_slot = r.undo_slot then raise exception 'cannot respond to own undo'; end if;
  if coalesce((r.players->my_slot->>'is_ai')::bool, false) then
    raise exception 'ai seat cannot respond';
  end if;

  if not accept then
    update public.rooms set undo_slot = null, undo_accepts = null, undo_expires_at = null
     where id = room_id returning * into r;
    return r;
  end if;

  -- 追加同意（幂等）
  if not (uid = any(coalesce(r.undo_accepts, '{}'))) then
    update public.rooms set undo_accepts = array_append(coalesce(undo_accepts, '{}'), uid)
     where id = room_id returning * into r;
  end if;

  -- 当前需要同意的其他真人座位 uid 集合（实时计算：离开/托管者不计）
  select array_agg((p->>'uid')::uuid order by (p->>'slot')::int) into needed
    from jsonb_array_elements(r.players) p
   where (p->>'is_ai')::bool = false
     and (p->>'uid') is not null
     and (p->>'slot')::int <> r.undo_slot;

  covered := needed is null or (
    select bool_and(x = any(coalesce(r.undo_accepts, '{}'))) from unnest(needed) x
  );
  if covered then
    return public.do_undo(room_id);
  end if;
  return r;
end $$;

-- ---------- 8) cancel_undo：发起者取消 ----------
create or replace function public.cancel_undo(room_id uuid)
returns public.rooms language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  r public.rooms;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into r from public.rooms where id = room_id;
  if r.id is null then raise exception 'room not found'; end if;
  if r.undo_slot is null then raise exception 'no undo pending'; end if;
  if (r.players->r.undo_slot->>'uid')::uuid <> uid then
    raise exception 'not your undo request';
  end if;
  update public.rooms set undo_slot = null, undo_accepts = null, undo_expires_at = null
   where id = room_id returning * into r;
  return r;
end $$;

-- ---------- 9) reset_room：清历史与悔棋状态 ----------
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

  delete from public.moves where room_id = room_id;

  update public.rooms set
    board = repeat('0',361), turn = 0, status = 'playing', winner = null,
    last_move_slot = null, undo_slot = null, undo_accepts = null, undo_expires_at = null
  where id = r.id returning * into r;
  r.move_deadline := public.compute_deadline(r);
  update public.rooms set move_deadline = r.move_deadline where id = r.id;
  select * into r from public.rooms where id = r.id;
  return r;
end $$;

-- ---------- 10) 昵称长度限制（顺手加固） ----------
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
  player_name := trim(player_name);
  if length(player_name) < 1 or length(player_name) > 20 then raise exception 'invalid name'; end if;
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
  player_name := trim(player_name);
  if length(player_name) < 1 or length(player_name) > 20 then raise exception 'invalid name'; end if;
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

-- ---------- 11) 授权 ----------
grant execute on function public.request_undo(uuid) to authenticated;
grant execute on function public.respond_undo(uuid,bool) to authenticated;
grant execute on function public.cancel_undo(uuid) to authenticated;
grant execute on function public.submit_move(uuid,int,int,int,bool) to authenticated;
grant execute on function public.create_room(text,int,text,int) to authenticated;
grant execute on function public.join_room(text,text) to authenticated;
