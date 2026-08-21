-- =============================================================
-- 三人五子棋 · Supabase 初始化迁移 (0001_init.sql)
-- 建表 + 触发器 + RPC + RLS + Realtime
-- 在 Supabase 控制台 SQL Editor 中整体执行一次即可
-- =============================================================

-- ---------- 表 ----------
create table if not exists public.rooms (
  id         uuid primary key default gen_random_uuid(),
  code       text unique not null,                 -- 6 位大写房间号
  host_id    uuid not null,                        -- 房主 uid
  member_ids uuid[] not null default '{}',         -- 房间成员 uid（用于 RLS）
  players    jsonb not null default '[]',          -- 3 个座位 [{slot,name,is_ai,uid,connected}]
  board      text  not null default repeat('0', 361), -- 361 字符, 索引 row*19+col
  turn       int   not null default 0,             -- 当前回合座位 0/1/2, -1=结束
  status     text  not null default 'waiting',     -- waiting | playing | finished
  winner     int,                                  -- 胜者 slot; null=未定或和棋
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------- 自动更新 updated_at ----------
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists rooms_touch on public.rooms;
create trigger rooms_touch before update on public.rooms
  for each row execute function public.touch_updated_at();

-- ---------- RLS ----------
alter table public.rooms enable row level security;

drop policy if exists "members_can_select_room" on public.rooms;
create policy "members_can_select_room" on public.rooms
  for select
  using (auth.uid() = any(member_ids));

-- 写操作一律走 SECURITY DEFINER 的 RPC，不开放直接 INSERT/UPDATE

-- ---------- 工具：生成唯一 6 位房间号 ----------
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

-- ---------- 工具：五子连线判定 ----------
-- 返回连成五子的座位号(0/1/2)，否则 null
create or replace function public.check_win(board text, r int, c int)
returns int language plpgsql immutable as $$
declare
  p text := substr(board, r*19 + c + 1, 1);
  cnt int; i int;
begin
  if p = '0' then return null; end if;
  -- 横
  cnt := 1; i := 1;
  while c+i <= 18 and substr(board, r*19 + (c+i) + 1, 1) = p loop cnt := cnt+1; i := i+1; end loop;
  i := 1;
  while c-i >= 0  and substr(board, r*19 + (c-i) + 1, 1) = p loop cnt := cnt+1; i := i+1; end loop;
  if cnt >= 5 then return ascii(p) - 49; end if;
  -- 竖
  cnt := 1; i := 1;
  while r+i <= 18 and substr(board, (r+i)*19 + c + 1, 1) = p loop cnt := cnt+1; i := i+1; end loop;
  i := 1;
  while r-i >= 0  and substr(board, (r-i)*19 + c + 1, 1) = p loop cnt := cnt+1; i := i+1; end loop;
  if cnt >= 5 then return ascii(p) - 49; end if;
  -- 主斜 (右下/左上)
  cnt := 1; i := 1;
  while r+i <= 18 and c+i <= 18 and substr(board, (r+i)*19 + (c+i) + 1, 1) = p loop cnt := cnt+1; i := i+1; end loop;
  i := 1;
  while r-i >= 0  and c-i >= 0  and substr(board, (r-i)*19 + (c-i) + 1, 1) = p loop cnt := cnt+1; i := i+1; end loop;
  if cnt >= 5 then return ascii(p) - 49; end if;
  -- 副斜 (右上/左下)
  cnt := 1; i := 1;
  while r+i <= 18 and c-i >= 0  and substr(board, (r+i)*19 + (c-i) + 1, 1) = p loop cnt := cnt+1; i := i+1; end loop;
  i := 1;
  while r-i >= 0  and c+i <= 18 and substr(board, (r-i)*19 + (c+i) + 1, 1) = p loop cnt := cnt+1; i := i+1; end loop;
  if cnt >= 5 then return ascii(p) - 49; end if;
  return null;
end $$;

-- ---------- RPC：建房 ----------
-- 房主固定 slot 0；ai_count(0/1/2) 表示高位槽由 AI 顶替（1→slot2, 2→slot1,2）
create or replace function public.create_room(player_name text, ai_count int)
returns public.rooms language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  r public.rooms;
  pl jsonb;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if ai_count < 0 or ai_count > 2 then raise exception 'invalid ai_count'; end if;

  pl := jsonb_build_array(
    jsonb_build_object('slot',0,'name',player_name,'is_ai',false,'uid',uid,'connected',true),
    jsonb_build_object('slot',1),
    jsonb_build_object('slot',2)
  );
  if ai_count >= 1 then
    pl := jsonb_set(pl, '{2}', jsonb_build_object('slot',2,'name','AI','is_ai',true,'uid',null,'connected',true));
  end if;
  if ai_count = 2 then
    pl := jsonb_set(pl, '{1}', jsonb_build_object('slot',1,'name','AI','is_ai',true,'uid',null,'connected',true));
  end if;

  insert into public.rooms (code, host_id, member_ids, players, status)
  values (public.gen_room_code(), uid, array[uid], pl,
          case when ai_count = 2 then 'playing' else 'waiting' end)
  returning * into r;
  return r;
end $$;

-- ---------- RPC：加入房间 ----------
create or replace function public.join_room(p_code text, player_name text)
returns public.rooms language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  r public.rooms;
  empty_slot int := -1;
  empty_cnt int := 0;
  i int;
  new_status text;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into r from public.rooms where code = upper(trim(p_code));
  if r.id is null then raise exception 'room not found'; end if;
  if uid = any(r.member_ids) then return r; end if;      -- 重复加入/重连直接返回
  if r.status <> 'waiting' then raise exception 'room already started'; end if;

  -- 找空位
  for i in 0..2 loop
    if (r.players->i->>'is_ai') is null and (r.players->i->>'uid') is null then
      empty_slot := i; exit;
    end if;
  end loop;
  if empty_slot < 0 then raise exception 'room full'; end if;

  -- 空位数（用于自动开局）
  select count(*) into empty_cnt from jsonb_array_elements(r.players) e
   where (e->>'is_ai') is null and (e->>'uid') is null;
  new_status := case when empty_cnt = 1 then 'playing' else 'waiting' end;

  update public.rooms set
    players = jsonb_set(players, array[empty_slot::text],
      jsonb_build_object('slot',empty_slot,'name',player_name,'is_ai',false,'uid',uid,'connected',true)),
    member_ids = array_append(member_ids, uid),
    status = new_status
  where id = r.id
  returning * into r;
  return r;
end $$;

-- ---------- RPC：落子 ----------
create or replace function public.submit_move(room_id uuid, slot int, rrow int, ccol int)
returns public.rooms language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  r public.rooms;
  p jsonb;
  is_ai bool;
  idx int;
  cell text;
  winner_slot int;
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
  -- 真人只能下自己的座位；AI 座位任何成员可代下（房主掉线后其余人接管）
  if not is_ai and (p->>'uid')::uuid <> uid then raise exception 'not your seat'; end if;

  idx := rrow*19 + ccol;
  cell := substr(r.board, idx+1, 1);
  if cell <> '0' then raise exception 'cell occupied'; end if;

  r.board := overlay(r.board placing (slot+1)::text from idx+1 for 1);
  winner_slot := public.check_win(r.board, rrow, ccol);

  if winner_slot is not null then
    r.status := 'finished'; r.winner := winner_slot; r.turn := -1;
  elsif position('0' in r.board) = 0 then
    r.status := 'finished'; r.winner := null; r.turn := -1;   -- 和棋
  else
    r.turn := (slot + 1) % 3;
  end if;

  update public.rooms set board = r.board, turn = r.turn, status = r.status, winner = r.winner
  where id = r.id;
  select * into r from public.rooms where id = r.id;
  return r;
end $$;

-- ---------- RPC：更新连接状态（心跳/重连） ----------
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
      exit;
    end if;
  end loop;
  update public.rooms set players = r.players where id = r.id returning * into r;
  return r;
end $$;

-- ---------- RPC：离开房间 ----------
-- waiting：腾出座位；playing：座位转为 AI 托管
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
      else
        r.players := jsonb_set(r.players, array[i::text],
          jsonb_build_object('slot', i, 'name', 'AI', 'is_ai', true, 'uid', null, 'connected', true));
      end if;
      r.member_ids := array_remove(r.member_ids, uid);
      exit;
    end if;
  end loop;
  update public.rooms set players = r.players, member_ids = r.member_ids where id = r.id returning * into r;
  return r;
end $$;

-- ---------- 授权 ----------
grant execute on function public.create_room(text,int) to authenticated;
grant execute on function public.join_room(text,text) to authenticated;
grant execute on function public.submit_move(uuid,int,int,int) to authenticated;
grant execute on function public.set_connected(uuid,bool) to authenticated;
grant execute on function public.leave_room(uuid) to authenticated;

-- ---------- Realtime ----------
do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'rooms') then
    alter publication supabase_realtime add table public.rooms;
  end if;
end $$;
