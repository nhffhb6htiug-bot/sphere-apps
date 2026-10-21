create or replace function pg_temp.as_user(u uuid) returns void language plpgsql as $$ begin perform set_config('request.jwt.claim.sub', u::text, false); execute 'set role authenticated'; end $$;
create or replace function pg_temp.reset_user() returns void language plpgsql as $$ begin execute 'reset role'; perform set_config('request.jwt.claim.sub', '', false); end $$;
do $$ declare A uuid := '00000000-0000-0000-0000-00000000000a'; B uuid := '00000000-0000-0000-0000-00000000000b'; D uuid := '00000000-0000-0000-0000-00000000000d';
  m uuid; ok boolean; n int;
begin
  insert into public.sp_messages (sender_id, receiver_id, text) values (A, B, 'to hide') returning id into m;
  perform pg_temp.as_user(B); insert into public.sp_msg_hidden (user_id, message_id) values (B, m); select count(*) into n from public.sp_msg_hidden; perform pg_temp.reset_user();
  if n <> 1 then raise exception 'H1 FAIL'; end if; raise notice 'PASS H1 a person in the chat can hide a message for themselves';
  if not exists (select 1 from public.sp_messages where id = m) then raise exception 'H2 FAIL'; end if; raise notice 'PASS H2 the message itself is not deleted (still there for the other person and the team)';
  perform pg_temp.as_user(A); select count(*) into n from public.sp_msg_hidden; perform pg_temp.reset_user();
  if n <> 0 then raise exception 'H3 FAIL'; end if; raise notice 'PASS H3 the other person cannot see what was hidden by someone else';
  ok := false; perform pg_temp.as_user(D); begin insert into public.sp_msg_hidden (user_id, message_id) values (D, m); exception when others then ok := true; end; perform pg_temp.reset_user();
  if not ok then raise exception 'H4 FAIL'; end if; raise notice 'PASS H4 someone outside the chat cannot use it';
  ok := false; perform pg_temp.as_user(A); begin insert into public.sp_msg_hidden (user_id, message_id) values (B, m); exception when others then ok := true; end; perform pg_temp.reset_user();
  if not ok then raise exception 'H5 FAIL'; end if; raise notice 'PASS H5 nobody can hide messages on someone else''s behalf';
  perform pg_temp.as_user(B); delete from public.sp_msg_hidden where message_id = m; perform pg_temp.reset_user();
  if exists (select 1 from public.sp_msg_hidden) then raise exception 'H6 FAIL'; end if; raise notice 'PASS H6 hiding can be undone by the same person';
  if has_table_privilege('anon', 'public.sp_msg_hidden', 'select') then raise exception 'H7 FAIL'; end if; raise notice 'PASS H7 visitors have no access';
end $$;
