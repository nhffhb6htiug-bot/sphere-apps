-- =====================================================================
-- SPHERE — PART 2: AUTH + USER ROLES (database side)
-- Run in: Supabase → SQL Editor → + → paste → Run.  Safe to run again.
-- Needs 002_foundation.sql first. Changes no data.
--
-- The app hides screens by role; this file makes the DATABASE refuse the
-- same actions, so nobody can skip the app and do them through the API:
--   • Bids (sp_applications)  → only EDITOR accounts (or ADMIN), only for themselves
--   • Portfolio (sp_portfolio) → only EDITOR accounts (or ADMIN), only their own
--   • Reviews (sp_ratings)     → only the client who owns that job, for that job's editor
-- =====================================================================

begin;

-- who is in a job (readable by the guard even when the user can't read the job row)
create or replace function public.sp_core_job_parties(p_job uuid, out client_id uuid, out assigned_editor uuid)
language sql stable security definer set search_path = public as $$
  select j.client_id, j.assigned_editor from public.sp_jobs j where j.id = p_job;
$$;
revoke all on function public.sp_core_job_parties(uuid) from public, anon;
grant execute on function public.sp_core_job_parties(uuid) to authenticated;

-- one guard for the three tables (SECURITY INVOKER on purpose: current_user tells us
-- whether the change came from the app/API or from an admin tool / Edge Function)
create or replace function public.sp_core_role_guard()
returns trigger language plpgsql set search_path = public as $$
declare
  me    uuid := auth.uid();
  role_ text;
  jp    record;
begin
  if current_user not in ('authenticated', 'anon') then return NEW; end if;   -- SQL Editor, Edge Functions, admin RPCs
  if me is null then raise exception 'Please log in first.'; end if;
  role_ := public.sp_core_role(me);
  if role_ = 'ADMIN' then return NEW; end if;

  if TG_TABLE_NAME = 'sp_applications' then
    if role_ is distinct from 'EDITOR' then raise exception 'Only editors can place bids.'; end if;
    if NEW.editor_id is distinct from me then raise exception 'You can only bid for yourself.'; end if;

  elsif TG_TABLE_NAME = 'sp_portfolio' then
    if role_ is distinct from 'EDITOR' then raise exception 'Only editors have a portfolio.'; end if;
    if NEW.editor_id is distinct from me then raise exception 'You can only change your own portfolio.'; end if;

  elsif TG_TABLE_NAME = 'sp_ratings' then
    select * into jp from public.sp_core_job_parties(NEW.job_id);
    if jp.client_id is null or jp.client_id is distinct from me or NEW.client_id is distinct from me then
      raise exception 'Only the client of this project can review it.';
    end if;
    if NEW.editor_id is distinct from jp.assigned_editor then
      raise exception 'You can only review the editor who did this project.';
    end if;
  end if;

  return NEW;
end $$;

drop trigger if exists sp_core_role_guard on public.sp_applications;
-- (insert only: the client updates a bid's status when choosing an editor)
create trigger sp_core_role_guard before insert on public.sp_applications
  for each row execute function public.sp_core_role_guard();

drop trigger if exists sp_core_role_guard on public.sp_portfolio;
create trigger sp_core_role_guard before insert or update on public.sp_portfolio
  for each row execute function public.sp_core_role_guard();

drop trigger if exists sp_core_role_guard on public.sp_ratings;
create trigger sp_core_role_guard before insert on public.sp_ratings
  for each row execute function public.sp_core_role_guard();

-- the app asks "who am I?" in one call (role, verified, suspended)
create or replace function public.sp_core_whoami()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', p.id,
    'role', upper(btrim(p.role)),
    'verified', coalesce(p.is_verified, false),
    'suspended', coalesce((select f.is_suspended from public.sp_mod_flags f where f.user_id = p.id), false)
  )
  from public.profiles p where p.id = auth.uid();
$$;
revoke all on function public.sp_core_whoami() from public, anon;
grant execute on function public.sp_core_whoami() to authenticated;

insert into public.sp_schema_versions (version, name)
values ('003', 'Auth + user roles (role checks for bids, portfolio, reviews)')
on conflict (version) do update set applied_at = now();

commit;

-- Done. You should see "Success. No rows returned".
