-- isolated fixture shaped like production; the admin / PIN / audit helpers are simple stand-ins
create extension if not exists pgcrypto;
do $$ begin create role authenticated nologin; exception when duplicate_object then null; end $$;
do $$ begin create role anon nologin; exception when duplicate_object then null; end $$;
create schema if not exists auth;
create or replace function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant usage on schema auth to authenticated, anon; grant execute on function auth.uid() to authenticated, anon;
create table public.profiles (id uuid primary key, full_name text, role text, is_verified boolean, verification_status text, verified_at timestamptz, verified_by uuid, verification_note text);
create table public.sp_admin_audit (id bigserial primary key, at timestamptz default now(), actor_id uuid, action text, target_type text, target_id text, job_id uuid, user_id uuid, old_status text, new_status text, reason text, details jsonb);
create table public.sp_schema_versions (version text primary key, name text, applied_at timestamptz default now());
create or replace function public.sp_admin_only() returns void language plpgsql stable security definer set search_path = public as $$
begin if not exists (select 1 from public.profiles where id = auth.uid() and upper(role) = 'ADMIN') then raise exception 'Admins only'; end if; end $$;
create or replace function public.sp_admin_check_pin(p text) returns boolean language plpgsql security definer as $$
begin if coalesce(p, '') <> 'good-pin' then raise exception 'Wrong or expired Admin PIN'; end if; return true; end $$;
create or replace function public.sp_audit_write(p_action text, p_type text, p_target text, p_job uuid, p_user uuid, p_old text, p_new text, p_reason text, p_details jsonb)
returns void language sql security definer set search_path = public as $$
  insert into public.sp_admin_audit (actor_id, action, target_type, target_id, job_id, user_id, old_status, new_status, reason, details) values (auth.uid(), p_action, p_type, p_target, p_job, p_user, p_old, p_new, p_reason, p_details) $$;
insert into public.profiles values
 ('00000000-0000-0000-0000-0000000000a1', 'Nitesh (admin)', 'ADMIN', null, null, null, null, null),
 ('00000000-0000-0000-0000-0000000000a2', 'Harshit (admin)', 'ADMIN', null, null, null, null, null),
 ('00000000-0000-0000-0000-0000000000e1', 'Editor One', 'EDITOR', true, 'approved', now() - interval '2 days', '00000000-0000-0000-0000-0000000000a1', null),
 ('00000000-0000-0000-0000-0000000000e2', 'Editor Two', 'EDITOR', false, 'rejected', null, null, 'Sample video missing'),
 ('00000000-0000-0000-0000-0000000000c1', 'A Client', 'CLIENT', null, null, null, null, null);
insert into public.sp_admin_audit (at, actor_id, action, target_type, target_id, new_status, reason) values
 (now() - interval '5 days', '00000000-0000-0000-0000-0000000000a2', 'verification', 'user', '00000000-0000-0000-0000-0000000000e1', 'rejected', 'Low quality sample'),
 (now() - interval '2 days', '00000000-0000-0000-0000-0000000000a1', 'verification', 'user', '00000000-0000-0000-0000-0000000000e1', 'approved', null),
 (now() - interval '1 day',  '00000000-0000-0000-0000-0000000000a2', 'verification', 'user', '00000000-0000-0000-0000-0000000000e2', 'rejected', 'Sample video missing');
