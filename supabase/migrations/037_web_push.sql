-- =====================================================================
-- SPHERE — PHONE PUSH NOTIFICATIONS (Web Push for the installed app / Chrome)
-- Safe to run again. Deletes NO data.
-- • sp_push_subs: one row per phone/browser that allowed notifications. Nobody reads or writes it directly.
-- • sphere_private.push_config: the server's VAPID keys (made by the sphere-push function, never sent to phones
--   except the PUBLIC key) and a random secret that only the database and the function know.
-- • After a notification is saved with push_status 'pending' (the person allowed push and the category is on),
--   the database asks the sphere-push function to deliver it. If that call fails, nothing else is affected,
--   and a sweep every 2 minutes retries what is still pending.
-- =====================================================================
begin;
create extension if not exists pg_net;

create table if not exists public.sp_push_subs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  endpoint text not null unique check (char_length(endpoint) between 20 and 1000),
  p256dh text not null check (char_length(p256dh) between 80 and 100),
  auth text not null check (char_length(auth) between 16 and 32),
  user_agent text,
  created_at timestamptz not null default now(),
  last_ok_at timestamptz
);
create index if not exists sp_push_subs_user_idx on public.sp_push_subs (user_id);
alter table public.sp_push_subs enable row level security;
revoke all on public.sp_push_subs from anon, authenticated;

create schema if not exists sphere_private;
create table if not exists sphere_private.push_config (
  id int primary key check (id = 1),
  vapid_public text,
  vapid_private jsonb,
  trigger_secret text not null,
  subject text not null default 'https://sphere-live.onrender.com'
);
insert into sphere_private.push_config (id, trigger_secret) values (1, encode(extensions.gen_random_bytes(32), 'hex')) on conflict (id) do nothing;
revoke all on sphere_private.push_config from public, anon, authenticated;

-- for the sphere-push function only (service role)
create or replace function public.sp_push_internal_config()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('vapid_public', vapid_public, 'vapid_private', vapid_private, 'trigger_secret', trigger_secret, 'subject', subject)
  from sphere_private.push_config where id = 1 $$;
create or replace function public.sp_push_internal_set_keys(p_public text, p_private jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  update sphere_private.push_config set vapid_public = p_public, vapid_private = p_private where id = 1 and vapid_public is null;   -- first one wins
  return public.sp_push_internal_config();
end $$;
revoke all on function public.sp_push_internal_config(), public.sp_push_internal_set_keys(text, jsonb) from public, anon, authenticated;
grant execute on function public.sp_push_internal_config(), public.sp_push_internal_set_keys(text, jsonb) to service_role;

-- for the app
create or replace function public.sp_push_public_key()
returns text language sql stable security definer set search_path = public as $$ select vapid_public from sphere_private.push_config where id = 1 $$;

create or replace function public.sp_push_subscribe(p_endpoint text, p_p256dh text, p_auth text, p_ua text)
returns boolean language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'Please log in.'; end if;
  if p_endpoint !~ '^https://(fcm\.googleapis\.com|[a-z0-9.-]+\.push\.services\.mozilla\.com|[a-z0-9.-]+\.notify\.windows\.com|web\.push\.apple\.com)/' then
    raise exception 'This browser''s push service is not supported.';
  end if;
  insert into public.sp_push_subs (user_id, endpoint, p256dh, auth, user_agent)
  values (me, p_endpoint, p_p256dh, p_auth, left(coalesce(p_ua, ''), 200))
  on conflict (endpoint) do update set user_id = me, p256dh = excluded.p256dh, auth = excluded.auth, user_agent = excluded.user_agent;
  delete from public.sp_push_subs where id in (select id from public.sp_push_subs where user_id = me order by created_at desc offset 10);   -- max 10 devices
  insert into public.sp_notification_prefs (user_id, prefs, updated_at) values (me, '{"push": true}'::jsonb, now())
  on conflict (user_id) do update set prefs = coalesce(public.sp_notification_prefs.prefs, '{}'::jsonb) || '{"push": true}'::jsonb, updated_at = now();
  return true;
end $$;

create or replace function public.sp_push_unsubscribe(p_endpoint text)
returns boolean language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then return false; end if;
  delete from public.sp_push_subs where endpoint = p_endpoint and user_id = me;
  if not exists (select 1 from public.sp_push_subs where user_id = me) then
    update public.sp_notification_prefs set prefs = coalesce(prefs, '{}'::jsonb) || '{"push": false}'::jsonb, updated_at = now() where user_id = me;
  end if;
  return true;
end $$;

create or replace function public.sp_push_test()
returns boolean language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'Please log in.'; end if;
  if exists (select 1 from public.sp_notifications where user_id = me and title = '🔔 Sphere test' and created_at > now() - interval '20 seconds') then
    raise exception 'Please wait a few seconds before sending another test.';
  end if;
  insert into public.sp_notifications (user_id, title, body, category)
  values (me, '🔔 Sphere test', 'Phone notifications work · ' || to_char(now() at time zone 'Asia/Kolkata', 'HH12:MI:SS AM'), 'general');
  return true;
end $$;

revoke all on function public.sp_push_public_key(), public.sp_push_subscribe(text, text, text, text), public.sp_push_unsubscribe(text), public.sp_push_test() from public, anon;
grant execute on function public.sp_push_public_key(), public.sp_push_subscribe(text, text, text, text), public.sp_push_unsubscribe(text), public.sp_push_test() to authenticated;

-- ask the function to deliver a pending notification (never blocks the notification itself)
create or replace function sphere_private.sp_push_kick()
returns trigger language plpgsql security definer set search_path = public as $$
declare s text;
begin
  if NEW.push_status = 'pending' then
    begin
      select trigger_secret into s from sphere_private.push_config where id = 1;
      perform net.http_post(
        url := 'https://pwcchgjsgkwrsvbzqspp.supabase.co/functions/v1/sphere-push',
        body := jsonb_build_object('id', NEW.id),
        headers := jsonb_build_object('Content-Type', 'application/json', 'x-sphere-push', s),
        timeout_milliseconds := 8000);
    exception when others then null;
    end;
  end if;
  return null;
end $$;
drop trigger if exists zz_sp_push_kick on public.sp_notifications;
create trigger zz_sp_push_kick after insert on public.sp_notifications for each row execute function sphere_private.sp_push_kick();

create or replace function sphere_private.sp_push_sweep()
returns void language plpgsql security definer set search_path = public as $$
declare s text;
begin
  if exists (select 1 from public.sp_notifications where push_status in ('pending', 'sending') and created_at < now() - interval '1 minute' and created_at > now() - interval '1 day') then
    -- a delivery that got stuck while "sending" for 5+ minutes is retried
    update public.sp_notifications set push_status = 'pending' where push_status = 'sending' and created_at < now() - interval '5 minutes' and created_at > now() - interval '1 day';
    select trigger_secret into s from sphere_private.push_config where id = 1;
    perform net.http_post(url := 'https://pwcchgjsgkwrsvbzqspp.supabase.co/functions/v1/sphere-push', body := '{"sweep": true}'::jsonb,
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-sphere-push', s), timeout_milliseconds := 20000);
  end if;
end $$;
revoke all on function sphere_private.sp_push_kick(), sphere_private.sp_push_sweep() from public, anon, authenticated;

do $$ begin
  if exists (select 1 from pg_namespace where nspname = 'cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'sphere-push-sweep';
    perform cron.schedule('sphere-push-sweep', '*/2 * * * *', 'select sphere_private.sp_push_sweep()');
  end if;
end $$;

insert into public.sp_schema_versions (version, name) values ('037', 'Phone push notifications (Web Push): devices, server keys, delivery trigger + retry')
on conflict (version) do update set applied_at = now();
commit;
