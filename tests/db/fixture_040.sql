do $$ begin create role authenticated nologin; exception when duplicate_object then null; end $$;
do $$ begin create role anon nologin; exception when duplicate_object then null; end $$;
create schema if not exists auth;
create or replace function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant usage on schema auth to authenticated, anon; grant execute on function auth.uid() to authenticated, anon;
create table public.sp_jobs (id uuid primary key, client_id uuid, status text, title text, category text, assigned_editor uuid, razorpay_payment_id text);
create table public.sp_applications (job_id uuid, editor_id uuid);
create table public.sp_notifications (id bigserial primary key, user_id uuid, title text, body text, category text, job_id uuid);
create table public.sp_schema_versions (version text primary key, name text, applied_at timestamptz default now());
insert into public.sp_jobs values
 ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000c1','open','Reel',null,null,null),
 ('10000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-0000000000c1','negotiating','Vlog',null,'00000000-0000-0000-0000-0000000000e1',null),
 ('10000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-0000000000c1','in-progress','Paid',null,'00000000-0000-0000-0000-0000000000e1','pay_123'),
 ('10000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-0000000000c1','payment-pending','Paid already',null,'00000000-0000-0000-0000-0000000000e1','pay_456');
insert into public.sp_applications values ('10000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-0000000000e1'),('10000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-0000000000e2'),('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000e2');
