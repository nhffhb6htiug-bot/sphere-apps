create or replace function pg_temp.as_user(u uuid) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub', u::text, false); execute 'set role authenticated'; end $$;
create or replace function pg_temp.reset_user() returns void language plpgsql as $$ begin execute 'reset role'; perform set_config('request.jwt.claim.sub', '', false); end $$;
do $$ declare A uuid := '00000000-0000-0000-0000-0000000000a1'; B uuid := '00000000-0000-0000-0000-0000000000b1';
  ep text := 'https://fcm.googleapis.com/fcm/send/abcDEF123-test-endpoint'; k text := 'BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4'; au text := 'BTBZMqHH6r4Tts7J_aSIgg';
  ok boolean; n int; c record; i int;
begin
  -- S1 bad push host refused
  ok := false; perform pg_temp.as_user(A); begin perform public.sp_push_subscribe('https://evil.example.com/x/aaaaaaaaaaaaaaaaa', k, au, 'ua'); exception when others then ok := sqlerrm ilike '%not supported%'; end; perform pg_temp.reset_user();
  if not ok then raise exception 'S1 FAIL'; end if; raise notice 'PASS S1 only real push services are accepted (no arbitrary URLs)';
  -- S2 subscribe saves the device and turns push on
  perform pg_temp.as_user(A); perform public.sp_push_subscribe(ep, k, au, 'Samsung Chrome'); perform pg_temp.reset_user();
  if (select count(*) from public.sp_push_subs where user_id = A) <> 1 or not (select (prefs->>'push')::boolean from public.sp_notification_prefs where user_id = A) then raise exception 'S2 FAIL'; end if;
  raise notice 'PASS S2 allowing saves this phone and turns phone push on';
  -- S3 users cannot read devices or the server keys directly
  ok := false; perform pg_temp.as_user(A); begin perform * from public.sp_push_subs; exception when others then ok := true; end; perform pg_temp.reset_user();
  if not ok then raise exception 'S3 FAIL subs readable'; end if;
  ok := false; perform pg_temp.as_user(A); begin perform public.sp_push_internal_config(); exception when others then ok := true; end; perform pg_temp.reset_user();
  if not ok then raise exception 'S3 FAIL config callable'; end if;
  raise notice 'PASS S3 devices and server keys are not readable by users (only the push function)';
  -- K1 a pending notification asks the function to deliver it, with the secret and only the id
  delete from net.calls;
  insert into public.sp_notifications (user_id, title, body, category) values (A, 'New message', 'Final cut?', 'messages');
  select * into c from net.calls limit 1;
  if c is null or c.body->>'id' is null or c.headers->>'x-sphere-push' is null or length(c.headers->>'x-sphere-push') <> 64 or c.url !~ '/functions/v1/sphere-push$' or c.body ? 'body' then raise exception 'K1 FAIL %', c; end if;
  raise notice 'PASS K1 a new notification calls the push function (id + secret only, no message text)';
  -- K2 no push allowed → no call
  delete from net.calls; insert into public.sp_notifications (user_id, title, category) values (B, 'New bid', 'bids');
  if (select count(*) from net.calls) <> 0 then raise exception 'K2 FAIL'; end if; raise notice 'PASS K2 people who did not allow push → nothing is sent';
  -- K3 the network failing never blocks the notification
  update net.cfg set fail = true; insert into public.sp_notifications (user_id, title, category) values (A, 'Payment received', 'payment'); update net.cfg set fail = false;
  if not exists (select 1 from public.sp_notifications where title = 'Payment received' and push_status = 'pending') then raise exception 'K3 FAIL'; end if;
  raise notice 'PASS K3 if the push call fails, the notification is still saved (and stays pending for the retry)';
  -- K4 the sweep retries what is still pending (and un-sticks old "sending")
  update public.sp_notifications set created_at = now() - interval '6 minutes' where title = 'Payment received';
  insert into public.sp_notifications (user_id, title, push_status, created_at) values (A, 'stuck', 'none', now() - interval '6 minutes'); update public.sp_notifications set push_status = 'sending' where title = 'stuck';
  delete from net.calls; perform sphere_private.sp_push_sweep();
  if (select count(*) from net.calls where body->>'sweep' = 'true') <> 1 or (select push_status from public.sp_notifications where title = 'stuck') <> 'pending' then raise exception 'K4 FAIL'; end if;
  raise notice 'PASS K4 the 2-minute sweep retries pending notifications and un-sticks old ones';
  -- S4 the same phone logging in as another person moves to that person
  perform pg_temp.as_user(B); perform public.sp_push_subscribe(ep, k, au, 'Samsung Chrome'); perform pg_temp.reset_user();
  if (select user_id from public.sp_push_subs where endpoint = ep) <> B then raise exception 'S4 FAIL'; end if; raise notice 'PASS S4 one phone belongs to the person logged in on it (no cross-account alerts)';
  -- S5 max 10 devices per person
  perform pg_temp.as_user(A); for i in 1..12 loop perform public.sp_push_subscribe('https://fcm.googleapis.com/fcm/send/dev-' || i || '-xxxxxxxx', k, au, 'ua'); perform pg_sleep(0.001); end loop; perform pg_temp.reset_user();
  if (select count(*) from public.sp_push_subs where user_id = A) <> 10 then raise exception 'S5 FAIL'; end if; raise notice 'PASS S5 at most 10 devices per person (oldest removed)';
  -- S6 unsubscribing all devices turns push off
  perform pg_temp.as_user(A); for i in 1..12 loop perform public.sp_push_unsubscribe('https://fcm.googleapis.com/fcm/send/dev-' || i || '-xxxxxxxx'); end loop; perform pg_temp.reset_user();
  if exists (select 1 from public.sp_push_subs where user_id = A) or (select (prefs->>'push')::boolean from public.sp_notification_prefs where user_id = A) then raise exception 'S6 FAIL'; end if;
  raise notice 'PASS S6 removing the last device turns phone push off';
  -- T1 test notification + rate limit
  perform pg_temp.as_user(B); perform public.sp_push_test(); ok := false; begin perform public.sp_push_test(); exception when others then ok := sqlerrm ilike '%wait%'; end; perform pg_temp.reset_user();
  if not ok or (select count(*) from public.sp_notifications where user_id = B and title = '🔔 Sphere test') <> 1 then raise exception 'T1 FAIL'; end if;
  raise notice 'PASS T1 "Send test" creates one test notification (and cannot be spammed)';
  if has_function_privilege('anon', 'public.sp_push_subscribe(text,text,text,text)', 'execute') or has_function_privilege('anon', 'public.sp_push_test()', 'execute') or has_function_privilege('authenticated', 'public.sp_push_internal_set_keys(text,jsonb)', 'execute') then raise exception 'P1 FAIL'; end if;
  raise notice 'PASS P1 visitors cannot call push functions; users cannot set server keys';
end $$;
