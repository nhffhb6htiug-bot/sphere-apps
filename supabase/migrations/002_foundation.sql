-- =====================================================================
-- SPHERE — PART 1: FOUNDATION
-- Run in: Supabase Dashboard → SQL Editor → + (new query) → paste → Run
-- Safe to run again. Does NOT delete or change any of your data.
--
-- Adds:
--   1) sp_schema_versions  — a list of which Sphere parts are installed
--   2) sp_core_role / sp_core_has_role — one place to ask "what is this user's role?"
--   3) sp_core_profile_guard — stops a normal user from making themselves ADMIN
--      or giving themselves the verified ✔ tick through the API
--   4) sp_core_status — numbers for the Admin Panel "System status" card
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1) Which parts are installed
-- ---------------------------------------------------------------------
create table if not exists public.sp_schema_versions (
  version    text primary key,          -- '001', '002', ...
  name       text not null,
  applied_at timestamptz not null default now()
);
alter table public.sp_schema_versions enable row level security;
drop policy if exists sp_schema_versions_read on public.sp_schema_versions;
create policy sp_schema_versions_read on public.sp_schema_versions for select to authenticated using (true);
revoke insert, update, delete on public.sp_schema_versions from anon, authenticated;
grant select on public.sp_schema_versions to authenticated;

-- ---------------------------------------------------------------------
-- 2) Roles. The database stores CLIENT / EDITOR / ADMIN (capital letters).
-- ---------------------------------------------------------------------
create or replace function public.sp_core_role(p_user uuid default auth.uid())
returns text language sql stable security definer set search_path = public as $$
  select upper(btrim(role)) from public.profiles where id = p_user;
$$;

create or replace function public.sp_core_has_role(p_role text, p_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.sp_core_role(p_user) = upper(btrim(p_role)), false);
$$;

revoke all on function public.sp_core_role(uuid) from public, anon;
revoke all on function public.sp_core_has_role(text, uuid) from public, anon;
grant execute on function public.sp_core_role(uuid) to authenticated;
grant execute on function public.sp_core_has_role(text, uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 3) Role + verification guard on profiles
--    Only blocks privilege escalation from the app/API. Everything that
--    works today keeps working:
--      • sign up as Client or Editor, Client → Editor switch  ✔
--      • editor saving details (sets is_verified = false)       ✔
--      • admin RPCs (verify editor, make/remove admin)           ✔
--      • SQL Editor / Edge Functions                             ✔
-- ---------------------------------------------------------------------
create or replace function public.sp_core_profile_guard()
returns trigger language plpgsql set search_path = public as $$   -- SECURITY INVOKER on purpose
declare
  from_api     boolean := current_user in ('authenticated', 'anon');
  caller_admin boolean := auth.uid() is not null and public.sp_core_has_role('ADMIN');
begin
  -- keep role spelling consistent: CLIENT / EDITOR / ADMIN
  if NEW.role is not null then NEW.role := upper(btrim(NEW.role)); end if;

  if not from_api or caller_admin then
    return NEW;
  end if;

  if TG_OP = 'INSERT' then
    if NEW.role = 'ADMIN' then NEW.role := 'CLIENT'; end if;
    if NEW.is_verified is true then NEW.is_verified := false; end if;
  else
    if NEW.role = 'ADMIN' and OLD.role is distinct from 'ADMIN' then
      raise exception 'Only an admin can make someone an admin.';
    end if;
    if NEW.is_verified is true and OLD.is_verified is not true then
      raise exception 'Only Syahi Films can give the verified tick.';
    end if;
  end if;

  return NEW;
end $$;

drop trigger if exists sp_core_profile_guard on public.profiles;
create trigger sp_core_profile_guard before insert or update on public.profiles
  for each row execute function public.sp_core_profile_guard();

-- ---------------------------------------------------------------------
-- 4) Admin Panel → System status (admins only)
-- ---------------------------------------------------------------------
create or replace function public.sp_core_status()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.sp_core_has_role('ADMIN') then
    raise exception 'Admins only';
  end if;
  return jsonb_build_object(
    'clients',          (select count(*) from public.profiles where upper(btrim(role)) = 'CLIENT'),
    'editors',          (select count(*) from public.profiles where upper(btrim(role)) = 'EDITOR'),
    'verified_editors', (select count(*) from public.profiles where upper(btrim(role)) = 'EDITOR' and is_verified is true),
    'admins',           (select count(*) from public.profiles where upper(btrim(role)) = 'ADMIN'),
    'no_role',          (select count(*) from public.profiles where role is null or upper(btrim(role)) not in ('CLIENT', 'EDITOR', 'ADMIN')),
    'jobs',             (select count(*) from public.sp_jobs),
    'messages',         (select count(*) from public.sp_messages),
    'parts',            coalesce((select jsonb_agg(jsonb_build_object('version', v.version, 'name', v.name, 'at', v.applied_at) order by v.version)
                                  from public.sp_schema_versions v), '[]'::jsonb),
    'db_time',          now()
  );
end $$;

revoke all on function public.sp_core_status() from public, anon;
grant execute on function public.sp_core_status() to authenticated;

-- ---------------------------------------------------------------------
-- 5) Record installed parts
-- ---------------------------------------------------------------------
insert into public.sp_schema_versions (version, name)
select '001', 'Contact protection (number block, strikes, suspicious users)'
where exists (select 1 from pg_proc where proname = 'sp_mod_guard')
on conflict (version) do nothing;

insert into public.sp_schema_versions (version, name)
values ('002', 'Foundation (roles, guard, system status)')
on conflict (version) do update set applied_at = now();

commit;

-- Done. You should see "Success. No rows returned".
-- Then run supabase/checks/foundation_check.sql to see the result.
