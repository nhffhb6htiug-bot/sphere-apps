-- fixture: the production table shape + both production indexes (as they are today)
create extension if not exists pgcrypto;
create table public.sp_schema_versions (version text primary key, name text, applied_at timestamptz default now());
create table public.sp_fee_payments (id uuid primary key default gen_random_uuid(), user_id uuid, kind text, amount numeric, target_user uuid, status text default 'pending');
create unique index sp_fee_one_pending on public.sp_fee_payments (user_id, kind) where status = 'pending';
create unique index sp_fee_contact_one_pending on public.sp_fee_payments (user_id, target_user) where kind = 'contact_unlock' and status = 'pending';
do $$ declare ok boolean;
begin
  insert into public.sp_fee_payments (user_id, kind, amount, target_user) values ('00000000-0000-0000-0000-0000000000a1', 'contact_unlock', 5, '00000000-0000-0000-0000-0000000000b1');
  ok := true; begin insert into public.sp_fee_payments (user_id, kind, amount, target_user) values ('00000000-0000-0000-0000-0000000000a1', 'contact_unlock', 5, '00000000-0000-0000-0000-0000000000b2'); exception when unique_violation then ok := false; end;
  if ok then raise exception 'R0 could not reproduce the bug'; end if;
  raise notice 'PASS R0 bug reproduced: second editor refused before the fix';
end $$;
\i supabase/migrations/033_contact_pending_per_editor.sql
do $$ declare ok boolean;
begin
  insert into public.sp_fee_payments (user_id, kind, amount, target_user) values ('00000000-0000-0000-0000-0000000000a1', 'contact_unlock', 5, '00000000-0000-0000-0000-0000000000b2');
  raise notice 'PASS F1 after the fix: pending ₹5 for a second editor is allowed';
  ok := true; begin insert into public.sp_fee_payments (user_id, kind, amount, target_user) values ('00000000-0000-0000-0000-0000000000a1', 'contact_unlock', 5, '00000000-0000-0000-0000-0000000000b2'); exception when unique_violation then ok := false; end;
  if ok then raise exception 'F2 FAIL same editor twice allowed'; end if; raise notice 'PASS F2 the same editor still allows only one pending ₹5';
  insert into public.sp_fee_payments (user_id, kind, amount) values ('00000000-0000-0000-0000-0000000000a1', 'verification', 29);
  ok := true; begin insert into public.sp_fee_payments (user_id, kind, amount) values ('00000000-0000-0000-0000-0000000000a1', 'verification', 29); exception when unique_violation then ok := false; end;
  if ok then raise exception 'F3 FAIL two pending ₹29'; end if; raise notice 'PASS F3 ₹29 still one pending per user (unchanged)';
  insert into public.sp_fee_payments (user_id, kind, amount) values ('00000000-0000-0000-0000-0000000000a1', 'client_premium', 199);
  ok := true; begin insert into public.sp_fee_payments (user_id, kind, amount) values ('00000000-0000-0000-0000-0000000000a1', 'client_premium', 199); exception when unique_violation then ok := false; end;
  if ok then raise exception 'F4 FAIL two pending ₹199'; end if; raise notice 'PASS F4 ₹199 Premium still one pending per user (unchanged)';
end $$;
