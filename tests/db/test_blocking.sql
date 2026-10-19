-- Contact privacy + chat blocking (migrations 031 + 032). Each check raises an error if it fails.
create or replace function pg_temp.as_user(u uuid) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', u::text, false); execute 'set role authenticated'; end $$;
create or replace function pg_temp.reset_user() returns void language plpgsql as $$ begin execute 'reset role'; perform set_config('request.jwt.claim.sub', '', false); end $$;
\set V '''00000000-0000-0000-0000-00000000000a'''
\set T '''00000000-0000-0000-0000-00000000000b'''
\set A '''00000000-0000-0000-0000-00000000000c'''
do $$ declare V uuid := '00000000-0000-0000-0000-00000000000a'; T uuid := '00000000-0000-0000-0000-00000000000b'; A uuid := '00000000-0000-0000-0000-00000000000c';
  s jsonb; r jsonb; ok boolean; n0 int; n1 int;
begin
  -- C1: no block → free unlock works and shows the number
  perform pg_temp.as_user(V); r := public.sp_contact_unlock(T); s := public.sp_contact_status(T); perform pg_temp.reset_user();
  if not ((r->>'unlocked')::boolean and s->>'phone' is not null) then raise exception 'C1 FAIL %', s; end if;
  raise notice 'PASS C1 no block: unlock works and the number is shown';
  -- C2: target blocks viewer → number hidden, unlock + ₹5 start refused, no free access used
  insert into public.sp_blocks values (T, V);
  select count(*) into n0 from public.sp_contact_grants;
  perform pg_temp.as_user(V); s := public.sp_contact_status(T);
  ok := false; begin perform public.sp_contact_unlock(T); exception when others then ok := sqlerrm ilike '%not available%'; end;
  if not ok then perform pg_temp.reset_user(); raise exception 'C2 FAIL unlock not refused'; end if;
  ok := false; begin perform public.sp_contact_pay_start(T); exception when others then ok := sqlerrm ilike '%not available%'; end;
  perform pg_temp.reset_user();
  select count(*) into n1 from public.sp_contact_grants;
  if not (ok and s->>'phone' is null and (s->>'blocked')::boolean and n0 = n1) then raise exception 'C2 FAIL %', s; end if;
  raise notice 'PASS C2 blocked: number hidden (even though unlocked before), unlock + ₹5 refused, nothing used';
  -- C3: unblock → the earlier unlock shows the number again (no new grant)
  delete from public.sp_blocks;
  perform pg_temp.as_user(V); s := public.sp_contact_status(T); perform pg_temp.reset_user();
  select count(*) into n1 from public.sp_contact_grants;
  if not (s->>'phone' is not null and n0 = n1) then raise exception 'C3 FAIL %', s; end if;
  raise notice 'PASS C3 unblocked: number shown again, no second charge';
  -- C4: viewer blocks target → also hidden (both directions)
  insert into public.sp_blocks values (V, T);
  perform pg_temp.as_user(V); s := public.sp_contact_status(T); perform pg_temp.reset_user();
  if s->>'phone' is not null then raise exception 'C4 FAIL'; end if;
  raise notice 'PASS C4 block works in both directions';
  -- M1: blocked → no messages either way (server-side, not just the screen)
  ok := false; perform pg_temp.as_user(T);
  begin insert into public.sp_messages (sender_id, receiver_id, text) values (T, V, 'hi'); exception when others then ok := sqlerrm ilike '%blocked%'; end;
  perform pg_temp.reset_user(); if not ok then raise exception 'M1 FAIL blocked person could send'; end if;
  ok := false; perform pg_temp.as_user(V);
  begin insert into public.sp_messages (sender_id, receiver_id, text) values (V, T, 'hi'); exception when others then ok := sqlerrm ilike '%blocked%'; end;
  perform pg_temp.reset_user(); if not ok then raise exception 'M1 FAIL blocker could send'; end if;
  raise notice 'PASS M1 messages refused in both directions while blocked';
  -- M2: Sphere team (admin) can still message
  perform pg_temp.as_user(A); insert into public.sp_messages (sender_id, receiver_id, text) values (A, V, 'support'); perform pg_temp.reset_user();
  raise notice 'PASS M2 Sphere team message goes through';
  -- M3: unblock → messages allowed again
  delete from public.sp_blocks;
  perform pg_temp.as_user(T); insert into public.sp_messages (sender_id, receiver_id, text) values (T, V, 'hello again'); perform pg_temp.reset_user();
  raise notice 'PASS M3 after unblock messages are allowed';
  -- P1: helper is not callable by users; contact functions not callable by visitors
  if has_function_privilege('authenticated', 'public.sp_is_blocked_pair(uuid,uuid)', 'execute') or has_function_privilege('anon', 'public.sp_contact_status(uuid)', 'execute') then raise exception 'P1 FAIL privileges'; end if;
  raise notice 'PASS P1 privileges: helper private, contact functions not open to visitors';
end $$;
