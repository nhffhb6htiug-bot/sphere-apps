do $$ begin create role authenticated nologin; exception when duplicate_object then null; end $$;
do $$ begin create role anon nologin; exception when duplicate_object then null; end $$;
create schema if not exists auth;
create or replace function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant usage on schema auth to authenticated, anon; grant execute on function auth.uid() to authenticated, anon;
create table public.profiles (id uuid primary key, role text, phone text, full_name text, is_verified boolean default false, verification_code text, razorpay_account_id text, verified_by uuid, verified_at timestamptz, verification_note text);
create table public.sp_notifications (id bigserial primary key, user_id uuid, title text, body text, category text);
create table public.sp_admin_audit (id bigserial primary key, actor_id uuid, action text, target_type text, target_id text, old_status text, new_status text);
create table public.sp_schema_versions (version text primary key, name text, applied_at timestamptz default now());
create or replace function public.sp_core_has_role(r text) returns boolean language sql stable security definer set search_path = public as $$ select exists (select 1 from public.profiles where id = auth.uid() and upper(role) = upper(r)) $$;
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path = public as $$ select public.sp_core_has_role('ADMIN') $$;
create or replace function public.sp_admin_only() returns void language plpgsql stable security definer set search_path = public as $$ begin if not public.is_admin() then raise exception 'Admins only'; end if; end $$;
create or replace function public.sp_admin_check_pin(p text) returns boolean language plpgsql security definer as $$ begin if coalesce(p,'') <> 'good-pin' then raise exception 'Wrong or expired Admin PIN'; end if; return true; end $$;
create or replace function public.sp_audit_write(p_action text, p_type text, p_target text, p_job uuid, p_user uuid, p_old text, p_new text, p_reason text, p_details jsonb) returns void language sql security definer set search_path = public as $$
  insert into public.sp_admin_audit (actor_id, action, target_type, target_id, old_status, new_status) values (auth.uid(), p_action, p_type, p_target, p_old, p_new) $$;
-- production's other profile guard, copied (it runs together with sp_protect_profile)
create or replace function public.sp_core_profile_guard() returns trigger language plpgsql set search_path to 'public' as $function$
declare from_api boolean := current_user in ('authenticated', 'anon'); caller_admin boolean := auth.uid() is not null and public.sp_core_has_role('ADMIN');
begin
  if NEW.role is not null then NEW.role := upper(btrim(NEW.role)); end if;
  if not from_api or caller_admin then return NEW; end if;
  if TG_OP = 'INSERT' then if NEW.role = 'ADMIN' then NEW.role := 'CLIENT'; end if; if NEW.is_verified is true then NEW.is_verified := false; end if;
  else if NEW.role = 'ADMIN' and OLD.role is distinct from 'ADMIN' then raise exception 'Only an admin can make someone an admin.'; end if;
       if NEW.is_verified is true and OLD.is_verified is not true then raise exception 'Only Syahi Films can give the verified tick.'; end if; end if;
  return NEW;
end $function$;
create trigger sp_core_profile_guard before insert or update on public.profiles for each row execute function public.sp_core_profile_guard();
grant select, insert, update on public.profiles to authenticated;
insert into public.profiles (id, role, phone, full_name) values
 ('00000000-0000-0000-0000-0000000000a1', 'ADMIN', '+919812345678', 'Nitesh'),
 ('00000000-0000-0000-0000-0000000000c1', 'CLIENT', '+919812345671', 'Client One'),
 ('00000000-0000-0000-0000-0000000000e1', 'EDITOR', '+919812345672', 'Editor One'),
 ('00000000-0000-0000-0000-0000000000f1', null, null, 'New Person');
