-- =============================================================
-- 三人五子棋 · 0008_fix_ambiguous2.sql
-- 真正的根因：PostgreSQL(9.6+) 对「列与 PL/pgSQL 变量同名」直接报 42702，
--   而非文档所说的"列优先"。SQL 语句中的裸列引用只要与函数参数同名即报错。
-- 0007 的 p_room 方案消除了"变量=列"的左侧歧义，但漏了"参数名=列名"的裸引用：
--   request_undo(room_id) 中 where room_id = p_room → room_id 是列也是参数 → 42702
--   reset_room(room_id)   中 delete ... where room_id = p_room → 同上（终局后触发）
-- 修复：给 moves 加表别名 m，列引用全部限定为 m.room_id / m.id。
-- 签名不变 → 无需重新 grant；create or replace 可重复执行。
-- =============================================================

-- ---------- 1) request_undo：moves 查询加表别名 ----------
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

  select slot into last_m from public.moves m
   where m.room_id = p_room order by m.id desc limit 1;
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

-- ---------- 2) reset_room：moves 删除加表别名 ----------
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

  delete from public.moves m where m.room_id = p_room;

  update public.rooms set
    board = repeat('0',361), turn = 0, status = 'playing', winner = null,
    last_move_slot = null, undo_slot = null, undo_accepts = null, undo_expires_at = null
  where id = r.id returning * into r;
  r.move_deadline := public.compute_deadline(r);
  update public.rooms set move_deadline = r.move_deadline where id = r.id;
  select * into r from public.rooms where id = r.id;
  return r;
end $$;
