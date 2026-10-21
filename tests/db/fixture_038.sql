create schema if not exists auth;
create or replace function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
create table public.profiles (id uuid primary key, role text, is_verified boolean, verification_status text, availability text, categories jsonb);
create table public.sp_mod_flags (user_id uuid, is_suspended boolean);
create table public.sp_jobs (id uuid primary key, client_id uuid, status text, deadline date, assigned_editor uuid);
create table public.sp_settings (key text primary key, value text);
create table public.sp_schema_versions (version text primary key, name text, applied_at timestamptz default now());
create or replace function public.sp_setting_int(k text, d int) returns int language sql stable as $$ select coalesce((select value::int from public.sp_settings where key = k), d) $$;
insert into public.profiles values
 ('00000000-0000-0000-0000-000000000001','EDITOR',false,'not_applied','available',null),   -- never filled the application
 ('00000000-0000-0000-0000-000000000002','EDITOR',false,'rejected','available','["Reels"]'),
 ('00000000-0000-0000-0000-000000000003','EDITOR',false,'pending','available','["Reels"]'),  -- 5 paid works, not verified
 ('00000000-0000-0000-0000-000000000004','EDITOR',true,'approved','available','["Reels"]'),
 ('00000000-0000-0000-0000-000000000005','EDITOR',false,'not_applied','away',null),
 ('00000000-0000-0000-0000-000000000006','EDITOR',false,'not_applied','available',null),  -- suspended
 ('00000000-0000-0000-0000-0000000000c1','CLIENT',null,null,null,null);
insert into public.sp_mod_flags values ('00000000-0000-0000-0000-000000000006', true);
insert into public.sp_jobs (id, client_id, status, deadline) values
 ('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-0000000000c1','open', current_date + 3),
 ('10000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-0000000000c1','open', current_date - 3),
 ('10000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000001','open', current_date + 3);
insert into public.sp_jobs (id, client_id, status, deadline, assigned_editor) select gen_random_uuid(), '00000000-0000-0000-0000-0000000000c1', 'approved', current_date, '00000000-0000-0000-0000-000000000003' from generate_series(1, 5);
