-- =====================================================================
-- SPHERE — PHONE OTP LOGIN (prepared, OFF until the WhatsApp / SMS provider is ready)
-- • sp_settings.otp_login = '0'  → the app keeps today's login. Set '1' on launch day.
-- • Supabase makes the OTP; the sphere-otp function (Supabase "Send SMS" hook) delivers it:
--   WhatsApp first, SMS if the person asks ("Send by SMS") or WhatsApp fails.
-- • Numbers are stored only as SHA-256 hashes here. Max 5 OTPs per number per hour.
-- Safe to run again. Deletes NO data.
-- =====================================================================
begin;
insert into public.sp_settings (key, value) values ('otp_login', '0') on conflict (key) do nothing;
create schema if not exists sphere_private;
create table if not exists sphere_private.otp_prefs (phone_hash text primary key, channel text not null check (channel in ('sms', 'whatsapp')), until timestamptz not null);
create table if not exists sphere_private.otp_log (id bigserial primary key, phone_hash text not null, channel text, ok boolean, at timestamptz not null default now());
create index if not exists otp_log_phone_at on sphere_private.otp_log (phone_hash, at);
revoke all on sphere_private.otp_prefs, sphere_private.otp_log from public, anon, authenticated;

create or replace function sphere_private.sp_phone_hash(p_phone text) returns text language sql immutable set search_path = public as $$
  select encode(extensions.digest(right(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g'), 10), 'sha256'), 'hex') $$;

-- the app (before login) asks for the next OTP by SMS instead of WhatsApp
create or replace function public.sp_otp_prefer(p_phone text, p_channel text) returns boolean
language plpgsql security definer set search_path = public as $$
declare d text := right(regexp_replace(coalesce(p_phone, ''), '\D', '', 'g'), 10);
begin
  if d !~ '^[6-9][0-9]{9}$' then raise exception 'Enter a valid 10-digit Indian mobile number.'; end if;
  if p_channel not in ('sms', 'whatsapp') then raise exception 'Unknown channel'; end if;
  insert into sphere_private.otp_prefs (phone_hash, channel, until) values (sphere_private.sp_phone_hash(d), p_channel, now() + interval '3 minutes')
  on conflict (phone_hash) do update set channel = excluded.channel, until = excluded.until;
  return true;
end $$;
revoke all on function public.sp_otp_prefer(text, text) from public;
grant execute on function public.sp_otp_prefer(text, text) to anon, authenticated;

-- for the sphere-otp function only: may we send, and on which channel?
create or replace function public.sp_otp_hook_check(p_phone text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare h text := sphere_private.sp_phone_hash(p_phone); n int; ch text;
begin
  select count(*) into n from sphere_private.otp_log where phone_hash = h and at > now() - interval '1 hour';
  if n >= 5 then return jsonb_build_object('allowed', false, 'reason', 'Too many OTP requests for this number. Please try again in an hour.'); end if;
  select channel into ch from sphere_private.otp_prefs where phone_hash = h and until > now();
  return jsonb_build_object('allowed', true, 'channel', coalesce(ch, 'whatsapp'));
end $$;
create or replace function public.sp_otp_hook_log(p_phone text, p_channel text, p_ok boolean) returns void
language sql security definer set search_path = public as $$
  insert into sphere_private.otp_log (phone_hash, channel, ok) values (sphere_private.sp_phone_hash(p_phone), p_channel, p_ok) $$;
revoke all on function public.sp_otp_hook_check(text), public.sp_otp_hook_log(text, text, boolean) from public, anon, authenticated;
grant execute on function public.sp_otp_hook_check(text), public.sp_otp_hook_log(text, text, boolean) to service_role;

insert into public.sp_schema_versions (version, name) values ('042', 'Phone OTP login prepared (OFF): channel preference, rate limit, hashed log')
on conflict (version) do update set applied_at = now();
commit;
