-- Isolated test fixture (NOT production data). Only the tables/helpers that migrations 031 + 032 need.
-- sp_contact_check / sp_contact_free_left are simplified stand-ins of the production helpers.
create extension if not exists pgcrypto;
do $$ begin create role authenticated nologin; exception when duplicate_object then null; end $$;
do $$ begin create role anon nologin; exception when duplicate_object then null; end $$;
create schema if not exists auth;
create or replace function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant usage on schema auth to authenticated, anon; grant execute on function auth.uid() to authenticated, anon;
create table public.profiles (id uuid primary key, role text, phone text);
create table public.sp_blocks (blocker_id uuid not null references public.profiles(id) on delete cascade, blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(), primary key (blocker_id, blocked_id), check (blocker_id <> blocked_id));
create table public.sp_messages (id bigserial primary key, sender_id uuid, receiver_id uuid, text text, created_at timestamptz default now());
create table public.sp_contact_grants (viewer_id uuid, target_id uuid, source text, created_at timestamptz default now(), primary key (viewer_id, target_id));
create table public.sp_fee_payments (id uuid primary key default gen_random_uuid(), user_id uuid, kind text, amount numeric, target_user uuid, status text default 'pending', utr text);
create table public.sp_monetization_config (key text primary key, value jsonb);
insert into public.sp_monetization_config values ('contact_access', '{"free": 7, "price": 5}');
create table public.sp_schema_versions (version text primary key, name text, applied_at timestamptz default now());
create or replace function public.sp_mon_cfg(k text) returns jsonb language sql stable as $$ select value from public.sp_monetization_config where key = k $$;
create or replace function public.sp_contact_free_left(me uuid) returns int language sql stable security definer set search_path = public as $$
  select greatest(0, 7 - (select count(*)::int from public.sp_contact_grants where viewer_id = me and source = 'free')) $$;
create or replace function public.sp_contact_check(me uuid, t uuid) returns text language sql stable security definer set search_path = public as $$
  select case when me = t then 'That is you.' when not exists (select 1 from public.profiles where id = t) then 'Not found.' end $$;
grant select, insert, delete on public.sp_blocks to authenticated;
grant select, insert on public.sp_messages to authenticated; grant usage on sequence public.sp_messages_id_seq to authenticated;
insert into public.profiles values
  ('00000000-0000-0000-0000-00000000000a', 'CLIENT', '+910000000001'),   -- viewer (client)
  ('00000000-0000-0000-0000-00000000000b', 'EDITOR', '+910000000002'),   -- target (editor)
  ('00000000-0000-0000-0000-00000000000c', 'ADMIN',  '+910000000003');   -- Sphere team
