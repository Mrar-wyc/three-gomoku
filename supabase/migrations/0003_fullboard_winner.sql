-- =============================================================
-- 三人五子棋 · 0003_fullboard_winner.sql
-- 满盘按「最长连子」判胜 + 困难难度校验
-- 在 0001 / 0002 之后执行（create or replace，可重复执行）
-- =============================================================

-- ---------- 1) longest_line：某方最长连续同色子（四方向，封顶 5） ----------
create or replace function public.longest_line(board text, stone text)
returns int language plpgsql immutable as $$
declare
  best int := 0;
  r int; c int; cnt int; i int;
begin
  for r in 0..18 loop
    for c in 0..18 loop
      if substr(board, r*19 + c + 1, 1) = stone then
        cnt := 1; i := 1;
        while c+i <= 18 and substr(board, r*19 + c + i + 1, 1) = stone loop
          cnt := cnt + 1; i := i + 1;
        end loop;
        if cnt >= 5 then return 5; end if;
        if cnt > best then best := cnt; end if;

        cnt := 1; i := 1;
        while r+i <= 18 and substr(board, (r+i)*19 + c + 1, 1) = stone loop
          cnt := cnt + 1; i := i + 1;
        end loop;
        if cnt >= 5 then return 5; end if;
        if cnt > best then best := cnt; end if;

        cnt := 1; i := 1;
        while r+i <= 18 and c+i <= 18 and substr(board, (r+i)*19 + c + i + 1, 1) = stone loop
          cnt := cnt + 1; i := i + 1;
        end loop;
        if cnt >= 5 then return 5; end if;
        if cnt > best then best := cnt; end if;

        cnt := 1; i := 1;
        while r+i <= 18 and c-i >= 0 and substr(board, (r+i)*19 + c - i + 1, 1) = stone loop
          cnt := cnt + 1; i := i + 1;
        end loop;
        if cnt >= 5 then return 5; end if;
        if cnt > best then best := cnt; end if;
      end if;
    end loop;
  end loop;
  return best;
end $$;

-- ---------- 2) submit_move：满盘改为按最长连子判胜 ----------
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
  if not is_ai and (p->>'uid')::uuid <> uid then raise exception 'not your seat'; end if;

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

  update public.rooms set board = r.board, turn = r.turn, status = r.status, winner = r.winner
  where id = r.id;
  select * into r from public.rooms where id = r.id;
  return r;
end $$;

-- ---------- 3) create_room：难度校验加入 'hard' ----------
create or replace function public.create_room(player_name text, ai_count int, ai_difficulty text default 'medium')
returns public.rooms language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  r public.rooms;
  pl jsonb;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if ai_count < 0 or ai_count > 2 then raise exception 'invalid ai_count'; end if;
  if ai_difficulty not in ('easy', 'medium', 'hard') then ai_difficulty := 'medium'; end if;

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

-- ---------- 授权 ----------
grant execute on function public.submit_move(uuid,int,int,int) to authenticated;
grant execute on function public.create_room(text,int,text) to authenticated;
