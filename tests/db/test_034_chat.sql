grant update (read_at, reply_to) on public.sp_messages to authenticated;
create or replace function pg_temp.as_user(u uuid) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub', u::text, false); execute 'set role authenticated'; end $$;
create or replace function pg_temp.reset_user() returns void language plpgsql as $$ begin execute 'reset role'; perform set_config('request.jwt.claim.sub', '', false); end $$;
do $$ declare A uuid := '00000000-0000-0000-0000-00000000000a'; B uuid := '00000000-0000-0000-0000-00000000000b'; D uuid := '00000000-0000-0000-0000-00000000000d';
  m1 uuid; m2 uuid; md uuid; ok boolean; v jsonb; r uuid;
begin
  insert into public.sp_messages (sender_id, receiver_id, text) values (A, B, 'hello') returning id into m1;
  insert into public.sp_messages (sender_id, receiver_id, text) values (A, D, 'other chat') returning id into md;
  -- R1 reply inside the same chat works (as the other person)
  perform pg_temp.as_user(B); insert into public.sp_messages (sender_id, receiver_id, text, reply_to) values (B, A, 'reply', m1) returning id into m2; perform pg_temp.reset_user();
  if m2 is null then raise exception 'R1 FAIL'; end if; raise notice 'PASS R1 reply to a message of the same chat is saved';
  -- R2 reply to a message from ANOTHER chat is refused
  ok := false; perform pg_temp.as_user(B);
  begin insert into public.sp_messages (sender_id, receiver_id, text, reply_to) values (B, A, 'sneaky', md); exception when others then ok := sqlerrm ilike '%only reply to a message in this chat%'; end;
  perform pg_temp.reset_user(); if not ok then raise exception 'R2 FAIL'; end if; raise notice 'PASS R2 replying to a message from another chat is refused';
  -- R3 a reply cannot be changed later (even by the receiver who may mark it read)
  ok := false; perform pg_temp.as_user(A);
  begin update public.sp_messages set reply_to = null where id = m2; exception when others then ok := sqlerrm ilike '%cannot be changed%'; end;
  perform pg_temp.reset_user(); if not ok then raise exception 'R3 FAIL'; end if; raise notice 'PASS R3 a reply cannot be changed afterwards';
  -- R4 marking read still works (other columns untouched by the guard)
  perform pg_temp.as_user(A); update public.sp_messages set read_at = now() where id = m2; perform pg_temp.reset_user();
  if (select read_at from public.sp_messages where id = m2) is null then raise exception 'R4 FAIL'; end if; raise notice 'PASS R4 read receipts still work';
  -- L1 nobody can read the presence table directly
  ok := false; perform pg_temp.as_user(A); begin perform * from public.sp_presence; exception when others then ok := true; end; perform pg_temp.reset_user();
  if not ok then raise exception 'L1 FAIL'; end if; raise notice 'PASS L1 sp_presence is not readable directly';
  -- L2 last seen visible between two people who chat, both sharing
  perform pg_temp.as_user(B); perform public.sp_seen_ping(); perform pg_temp.reset_user();
  perform pg_temp.as_user(A); v := public.sp_last_seen(B); perform pg_temp.reset_user();
  if not (v->>'visible')::boolean or v->>'last_seen_at' is null then raise exception 'L2 FAIL %', v; end if; raise notice 'PASS L2 chat partner sees last seen';
  -- L3 a stranger (no chat) cannot see it
  perform pg_temp.as_user(D); v := public.sp_last_seen(B); perform pg_temp.reset_user();
  if (v->>'visible')::boolean then raise exception 'L3 FAIL'; end if; raise notice 'PASS L3 a stranger cannot see last seen';
  -- L4 B hides last seen → A cannot see it; and B hiding means B cannot see A either (reciprocal)
  perform pg_temp.as_user(A); perform public.sp_seen_ping(); perform pg_temp.reset_user();
  perform pg_temp.as_user(B); perform public.sp_set_show_last_seen(false); v := public.sp_last_seen(A); perform pg_temp.reset_user();
  if (v->>'visible')::boolean then raise exception 'L4 FAIL reciprocal'; end if;
  perform pg_temp.as_user(A); v := public.sp_last_seen(B); perform pg_temp.reset_user();
  if (v->>'visible')::boolean then raise exception 'L4 FAIL'; end if; raise notice 'PASS L4 hiding last seen works both ways';
  -- L5 a block hides last seen
  perform pg_temp.as_user(B); perform public.sp_set_show_last_seen(true); perform pg_temp.reset_user();
  insert into public.sp_blocks values (B, A);
  perform pg_temp.as_user(A); v := public.sp_last_seen(B); perform pg_temp.reset_user();
  if (v->>'visible')::boolean then raise exception 'L5 FAIL'; end if; raise notice 'PASS L5 blocked → last seen hidden';
  -- P1 visitors cannot call the functions
  if has_function_privilege('anon', 'public.sp_last_seen(uuid)', 'execute') or has_function_privilege('anon', 'public.sp_seen_ping()', 'execute') then raise exception 'P1 FAIL'; end if;
  raise notice 'PASS P1 visitors cannot call presence functions';
end $$;
