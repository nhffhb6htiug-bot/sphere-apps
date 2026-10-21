-- isolated fixture (synthetic data). pg_net is replaced by a stub that records calls and can be told to fail.
create schema if not exists extensions; create extension if not exists pgcrypto with schema extensions;
do $$ begin create role authenticated nologin; exception when duplicate_object then null; end $$;
do $$ begin create role anon nologin; exception when duplicate_object then null; end $$;
do $$ begin create role service_role nologin; exception when duplicate_object then null; end $$;
create schema if not exists auth;
create or replace function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant usage on schema auth to authenticated, anon; grant execute on function auth.uid() to authenticated, anon;
create schema net; create table net.calls (id serial, url text, body jsonb, headers jsonb); create table net.cfg (fail boolean default false); insert into net.cfg values (false);
create or replace function net.http_post(url text, body jsonb, headers jsonb, timeout_milliseconds int default 1000) returns bigint language plpgsql as $$
begin if (select fail from net.cfg) then raise exception 'network down'; end if; insert into net.calls (url, body, headers) values (url, body, headers); return 1; end $$;
create table public.profiles (id uuid primary key, role text);
create table public.sp_notification_prefs (user_id uuid primary key, prefs jsonb default '{}'::jsonb, updated_at timestamptz default now());
create table public.sp_notifications (id uuid primary key default gen_random_uuid(), user_id uuid, title text, body text, category text, push_status text default 'none', created_at timestamptz default now());
-- stand-in for sp_notif_before: production marks 'pending' when the person allowed push (prefs.push = true)
create or replace function public.fx_mark_pending() returns trigger language plpgsql as $$
begin if coalesce((select (prefs->>'push')::boolean from public.sp_notification_prefs where user_id = NEW.user_id), false) then NEW.push_status := 'pending'; end if; return NEW; end $$;
create trigger sp_notif_before before insert on public.sp_notifications for each row execute function public.fx_mark_pending();
create table public.sp_schema_versions (version text primary key, name text, applied_at timestamptz default now());
grant select on public.sp_notifications to authenticated;
insert into public.profiles values ('00000000-0000-0000-0000-0000000000a1','CLIENT'),('00000000-0000-0000-0000-0000000000b1','EDITOR');
