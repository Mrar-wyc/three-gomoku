-- =============================================================
-- 三人五子棋 · 0004_chat.sql
-- 房间聊天：messages 表 + RLS + send_message RPC + Realtime
-- 在 0001/0002/0003 之后执行（create or replace，可重复执行）
-- =============================================================

-- ---------- 1) messages 表 ----------
create table if not exists public.messages (
  id          bigint generated always as identity primary key,
  room_id     uuid not null references public.rooms(id) on delete cascade,
  sender_slot int  not null,                -- 发言者座位 0/1/2
  sender_name text not null,                -- 发言时昵称快照
  body        text not null,                -- 内容（≤200 字）
  created_at  timestamptz not null default now()
);

create index if not exists messages_room_id_idx on public.messages (room_id, id desc);

-- ---------- 2) RLS：仅本房成员可读；写入只走 RPC ----------
alter table public.messages enable row level security;

drop policy if exists "members_can_select_messages" on public.messages;
create policy "members_can_select_messages" on public.messages
  for select
  using (exists (
    select 1 from public.rooms r
    where r.id = room_id and auth.uid() = any(r.member_ids)
  ));

-- ---------- 3) RPC：发消息 ----------
create or replace function public.send_message(room_id uuid, body text)
returns void language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  r public.rooms;
  slot int;
  pname text;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  body := trim(body);
  if body = '' then return; end if;
  if length(body) > 200 then raise exception 'message too long'; end if;

  select * into r from public.rooms where id = room_id;
  if r.id is null then raise exception 'room not found'; end if;
  if not (uid = any(r.member_ids)) then raise exception 'not a member'; end if;

  -- 按调用者 uid 找座位（即使已被托管也以原座位身份发言）
  select i, coalesce((r.players->i->>'name'), '玩家')
    into slot, pname
    from generate_series(0, 2) i
   where (r.players->i->>'uid')::uuid = uid
   limit 1;
  if slot is null then raise exception 'not a member'; end if;

  insert into public.messages (room_id, sender_slot, sender_name, body)
  values (room_id, slot, pname, body);
end $$;

-- ---------- 4) Realtime ----------
do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime'
                   and schemaname = 'public'
                   and tablename = 'messages') then
    alter publication supabase_realtime add table public.messages;
  end if;
end $$;

-- ---------- 5) 授权 ----------
grant execute on function public.send_message(uuid,text) to authenticated;
