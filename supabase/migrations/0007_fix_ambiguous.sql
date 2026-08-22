-- =============================================================
-- 三人五子棋 · 0007_fix_ambiguous.sql
-- 修复 0006 的 PL/pgSQL 变量与列撞名（42702 ambiguous）
-- 根因：SQL 语句中裸标识符列名优先于函数参数，
--       "where room_id = room_id" 两侧都被解析为列 → ambiguous
-- 方案：函数参数名保持 room_id 不变（客户端按命名参数调用），
--       函数体内引入局部变量 p_room := room_id，SQL 内一律引用 p_room。
-- 签名全部不变 → 无需重新 grant；create or replace 可重复执行。
-- =============================================================

-- ---------- 1) submit_move：修复 insert 撞名隐患 ----------
create or replace function public.submit_move(
  room_id uuid, slot int, rrow int, ccol int, as_timeout_ai bool default false)
returns public.rooms language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  p_room uuid := room_id;
  r public.rooms;
  p jsonb;
  is_ai bool;
  idx int;
  cell text;
  winner_slot int;
  l1 int; l2 int; l3 int;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into r from public.rooms where id = p_room;
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

  insert into public.moves (room_id, slot, idx) values (p_room, slot, idx);
  r.move_deadline := public.compute_deadline(r);

  update public.rooms set
    board = r.board, turn = r.turn, status = r.status, winner = r.winner,
    move_deadline = r.move_deadline, last_move_slot = slot,
    undo_slot = r.undo_slot, undo_accepts = r.undo_accepts, undo_expires_at = r.undo_expires_at
  where id = r.id;
  select * into r from public.rooms where id = r.id;
  return r;
end $$;

-- ---------- 2) request_undo：修复 moves 查询撞名 ----------
create or replace function public.request_undo(room_id uuid)
returns public.rooms language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  p_room uuid := room_id;
  r public.rooms;
  last_m record;
  voters int := 0;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into r from public.rooms where id = p_room;
  if r.id is null then raise exception 'room not found'; end if;
  if not (uid = any(r.member_ids)) then raise exception 'not a member'; end if;
  if r.status <> 'playing' then raise exception 'not playing'; end if;

  -- 过期 pending 先清
  if r.undo_expires_at is not null and r.undo_expires_at <= now() then
    update public.rooms set undo_slot = null, undo_accepts = null, undo_expires_at = null
     where id = p_room;
    r.undo_slot := null; r.undo_accepts := null; r.undo_expires_at := null;
  end if;
  if r.undo_slot is not null then raise exception 'undo pending'; end if;

  select slot into last_m from public.moves
   where room_id = p_room order by id desc limit 1;
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
    return public.do_undo(p_room); -- 无人需要同意，直接撤销
  end if;

  update public.rooms set
    undo_slot = last_m.slot,
    undo_accepts = '{}',
    undo_expires_at = now() + interval '30 seconds'
  where id = p_room returning * into r;
  return r;
end $$;

-- ---------- 3) respond_undo：统一 p_room ----------
create or replace function public.respond_undo(room_id uuid, accept bool)
returns public.rooms language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  p_room uuid := room_id;
  r public.rooms;
  i int;
  my_slot int := -1;
  needed uuid[];
  covered bool;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into r from public.rooms where id = p_room;
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
     where id = p_room returning * into r;
    return r;
  end if;

  -- 追加同意（幂等）
  if not (uid = any(coalesce(r.undo_accepts, '{}'))) then
    update public.rooms set undo_accepts = array_append(coalesce(undo_accepts, '{}'), uid)
     where id = p_room returning * into r;
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
    return public.do_undo(p_room);
  end if;
  return r;
end $$;

-- ---------- 4) cancel_undo：统一 p_room ----------
create or replace function public.cancel_undo(room_id uuid)
returns public.rooms language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  p_room uuid := room_id;
  r public.rooms;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into r from public.rooms where id = p_room;
  if r.id is null then raise exception 'room not found'; end if;
  if r.undo_slot is null then raise exception 'no undo pending'; end if;
  if (r.players->r.undo_slot->>'uid')::uuid <> uid then
    raise exception 'not your undo request';
  end if;
  update public.rooms set undo_slot = null, undo_accepts = null, undo_expires_at = null
   where id = p_room returning * into r;
  return r;
end $$;

-- ---------- 5) reset_room：修复 delete 撞名 ----------
create or replace function public.reset_room(room_id uuid)
returns public.rooms language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  p_room uuid := room_id;
  r public.rooms;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into r from public.rooms where id = p_room;
  if r.id is null then raise exception 'room not found'; end if;
  if not (uid = any(r.member_ids)) then raise exception 'not a member'; end if;
  if r.status <> 'finished' then raise exception 'game not finished'; end if;

  delete from public.moves where room_id = p_room;

  update public.rooms set
    board = repeat('0',361), turn = 0, status = 'playing', winner = null,
    last_move_slot = null, undo_slot = null, undo_accepts = null, undo_expires_at = null
  where id = r.id returning * into r;
  r.move_deadline := public.compute_deadline(r);
  update public.rooms set move_deadline = r.move_deadline where id = r.id;
  select * into r from public.rooms where id = r.id;
  return r;
end $$;
