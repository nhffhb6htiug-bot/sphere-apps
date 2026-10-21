-- Migration 034 on an isolated fixture shaped like production (uuid message ids). Synthetic data only.
create extension if not exists pgcrypto;
do $$ begin create role authenticated nologin; exception when duplicate_object then null; end $$;
do $$ begin create role anon nologin; exception when duplicate_object then null; end $$;
create schema if not exists auth;
create or replace function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant usage on schema auth to authenticated, anon; grant execute on function auth.uid() to authenticated, anon;
create table public.profiles (id uuid primary key, role text);
create table public.sp_blocks (blocker_id uuid, blocked_id uuid, primary key (blocker_id, blocked_id));
create table public.sp_messages (id uuid primary key default gen_random_uuid(), sender_id uuid, receiver_id uuid, text text, created_at timestamptz default now(), read_at timestamptz);
create table public.sp_schema_versions (version text primary key, name text, applied_at timestamptz default now());
create or replace function public.sp_is_blocked_pair(a uuid, b uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.sp_blocks where (blocker_id = a and blocked_id = b) or (blocker_id = b and blocked_id = a)) $$;
grant select, insert on public.sp_messages to authenticated;
insert into public.profiles values ('00000000-0000-0000-0000-00000000000a','CLIENT'),('00000000-0000-0000-0000-00000000000b','EDITOR'),('00000000-0000-0000-0000-00000000000d','CLIENT');
