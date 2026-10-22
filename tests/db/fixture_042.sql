create schema if not exists extensions; create extension if not exists pgcrypto with schema extensions;
do $$ begin create role authenticated nologin; exception when duplicate_object then null; end $$;
do $$ begin create role anon nologin; exception when duplicate_object then null; end $$;
do $$ begin create role service_role nologin; exception when duplicate_object then null; end $$;
create table public.sp_settings (key text primary key, value text, updated_at timestamptz, updated_by uuid);
create table public.sp_schema_versions (version text primary key, name text, applied_at timestamptz default now());
