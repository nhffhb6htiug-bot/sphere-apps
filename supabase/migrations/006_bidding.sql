-- =====================================================================
-- SPHERE — PART 6: JOB DISCOVERY + EDITOR BIDDING
-- Run in: Supabase → SQL Editor → + → paste → Run.  Safe to run again.
-- Needs 002, 003, 004 first. Adds columns/functions; deletes nothing.
--
--   sp_applications  + delivery_days (estimated completion), updated_at,
--                      status pending / selected / rejected
--   One bid per editor per job (unique), edits only while the job is open.
--   sp_bid_eligibility  — who may bid (same rules for app + database)
--   sp_bid_select       — client picks one bid: job → that editor, other bids → rejected
--   sp_bid_editor_stats, sp_bid_counts — public numbers for comparing bids
-- Settings: free_works (3, as today), bids_verified_only (0 = keep today's rule)
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1) Settings (only added if missing)
-- ---------------------------------------------------------------------
insert into public.sp_settings (key, value) select 'free_works', '3'         where not exists (select 1 from public.sp_settings where key = 'free_works');
insert into public.sp_settings (key, value) select 'bids_verified_only', '0' where not exists (select 1 from public.sp_settings where key = 'bids_verified_only');

create or replace function public.sp_setting_int(p_key text, p_default int)
returns int language sql stable security definer set search_path = public as $$
  select coalesce((select nullif(regexp_replace(value::text, '[^0-9]', '', 'g'), '')::int from public.sp_settings where key = p_key), p_default);
$$;

-- ---------------------------------------------------------------------
-- 2) Bid columns
-- ---------------------------------------------------------------------
alter table public.sp_applications add column if not exists delivery_days int;
alter table public.sp_applications add column if not exists updated_at timestamptz;
alter table public.sp_applications alter column status set default 'pending';
update public.sp_applications set status = 'pending' where status is null;

alter table public.sp_applications drop constraint if exists sp_app_days_chk;
alter table public.sp_applications add  constraint sp_app_days_chk check (delivery_days is null or delivery_days between 1 and 90);
alter table public.sp_applications drop constraint if exists sp_app_amount_chk;
alter table public.sp_applications add  constraint sp_app_amount_chk check (bid_amount is null or (bid_amount > 0 and bid_amount <= 10000000)) not valid;
alter table public.sp_applications drop constraint if exists sp_app_msg_chk;
alter table public.sp_applications add  constraint sp_app_msg_chk check (message is null or char_length(message) <= 600) not valid;

-- one bid per editor per job (only created if old data has no duplicates)
do $$
begin
  if not exists (select 1 from public.sp_applications group by job_id, editor_id having count(*) > 1) then
    execute 'create unique index if not exists sp_app_job_editor_uq on public.sp_applications (job_id, editor_id)';
  else
    raise notice 'Duplicate bids exist in old data — unique index skipped. Ask Claude to clean them up.';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 3) Who may bid (used by the app to explain, and by the database to enforce)
-- ---------------------------------------------------------------------
create or replace function public.sp_bid_eligibility(p_editor uuid default auth.uid(), p_job uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  p record; j record;
  works int; free_works int := public.sp_setting_int('free_works', 3);
  ok_json jsonb;
begin
  select id, upper(btrim(role)) as role, is_verified, verification_status, availability, categories
    into p from public.profiles where id = p_editor;
  if p.id is null then return jsonb_build_object('ok', false, 'code', 'no_profile', 'message', 'Please log in again.'); end if;
  if p.role not in ('EDITOR', 'ADMIN') then
    return jsonb_build_object('ok', false, 'code', 'not_editor', 'message', 'Only editors can place bids.');
  end if;
  if exists (select 1 from public.sp_mod_flags f where f.user_id = p_editor and f.is_suspended) then
    return jsonb_build_object('ok', false, 'code', 'suspended', 'message', 'Your account is suspended. Contact Sphere support.');
  end if;

  if p_job is not null then
    select id, client_id, status, deadline into j from public.sp_jobs where id = p_job;
    if j.id is null then return jsonb_build_object('ok', false, 'code', 'no_job', 'message', 'This job does not exist any more.'); end if;
    if j.client_id = p_editor then return jsonb_build_object('ok', false, 'code', 'own_job', 'message', 'You cannot bid on your own job.'); end if;
    if j.status is distinct from 'open' then return jsonb_build_object('ok', false, 'code', 'closed', 'message', 'This job is no longer taking bids.'); end if;
    if j.deadline is not null and j.deadline::date < (now() at time zone 'Asia/Kolkata')::date then
      return jsonb_build_object('ok', false, 'code', 'expired', 'message', 'This job has expired.');
    end if;
  end if;

  if p.role = 'ADMIN' then return jsonb_build_object('ok', true, 'code', 'admin', 'verified', true); end if;

  if coalesce(p.availability, 'available') = 'away' then
    return jsonb_build_object('ok', false, 'code', 'away', 'message', 'Your status is "Away". Switch to Available on Home to place bids.');
  end if;
  if p.is_verified is true then return jsonb_build_object('ok', true, 'code', 'verified', 'verified', true); end if;

  if p.verification_status = 'rejected' then
    return jsonb_build_object('ok', false, 'code', 'rejected', 'message', 'Your verification was not approved. Fix the reason and apply again to place bids.');
  end if;
  if coalesce(p.verification_status, 'not_applied') = 'not_applied'
     and coalesce(p.categories::text, '') in ('', '{}', '[]', 'null') then
    return jsonb_build_object('ok', false, 'code', 'not_applied', 'message', 'Fill your editor application first (Profile → Verification status).');
  end if;
  if public.sp_setting_int('bids_verified_only', 0) = 1 then
    return jsonb_build_object('ok', false, 'code', 'verified_only', 'message', 'Only verified ✔ editors can bid right now. Get verified to start bidding.');
  end if;

  select count(*) into works from public.sp_jobs
   where assigned_editor = p_editor and status in ('in-progress', 'delivered', 'approved', 'closed');
  if works >= free_works then
    return jsonb_build_object('ok', false, 'code', 'need_verification', 'message',
      'You have finished ' || free_works || ' paid works. Get verified (✔ tick) to keep getting new work.');
  end if;
  return jsonb_build_object('ok', true, 'code', 'free_works', 'verified', false, 'works_used', works, 'free_works', free_works);
end $$;
revoke all on function public.sp_bid_eligibility(uuid, uuid) from public, anon;
grant execute on function public.sp_bid_eligibility(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 4) Guard on bids (SECURITY INVOKER: current_user tells app/API from admin tools)
-- ---------------------------------------------------------------------
create or replace function public.sp_bid_guard()
returns trigger language plpgsql set search_path = public as $$
declare
  me uuid := auth.uid();
  e jsonb;
  jp record;
  jstatus text;
begin
  if current_user not in ('authenticated', 'anon') then return NEW; end if;   -- admin tools, Edge Functions, RPCs
  if me is not null and public.sp_core_has_role('ADMIN') and NEW.editor_id is distinct from me then return NEW; end if;

  if TG_OP = 'INSERT' then
    e := public.sp_bid_eligibility(NEW.editor_id, NEW.job_id);
    if not coalesce((e->>'ok')::boolean, false) then raise exception '%', e->>'message'; end if;
    NEW.status := 'pending';
    NEW.updated_at := now();
    return NEW;
  end if;

  -- UPDATE
  select * into jp from public.sp_core_job_parties(NEW.job_id);
  if me = jp.client_id then
    -- the client only changes the status (older app versions select this way)
    if NEW.bid_amount is distinct from OLD.bid_amount or NEW.message is distinct from OLD.message
       or NEW.delivery_days is distinct from OLD.delivery_days or NEW.editor_id is distinct from OLD.editor_id then
      raise exception 'Only the editor can change their bid.';
    end if;
    return NEW;
  end if;
  if me = OLD.editor_id then
    select status into jstatus from public.sp_jobs where id = NEW.job_id;
    if NEW.status is distinct from OLD.status then raise exception 'You cannot change the status of your bid.'; end if;
    if coalesce(OLD.status, 'pending') <> 'pending' or jstatus is distinct from 'open' then
      raise exception 'This bid can no longer be changed.';
    end if;
    if NEW.job_id is distinct from OLD.job_id or NEW.editor_id is distinct from OLD.editor_id then
      raise exception 'Not allowed.';
    end if;
    NEW.updated_at := now();
    return NEW;
  end if;
  raise exception 'Not allowed.';
end $$;

drop trigger if exists sp_bid_guard on public.sp_applications;
create trigger sp_bid_guard before insert or update on public.sp_applications
  for each row execute function public.sp_bid_guard();

-- ---------------------------------------------------------------------
-- 5) Client selects one bid (all in one step)
--    Same result as before for the chosen editor: job → "negotiating" with the
--    bid as the editor's price, so the client can lock it and pay.
--    New: every other bid becomes "rejected" and those editors are told.
-- ---------------------------------------------------------------------
create or replace function public.sp_bid_select(p_application uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  a record; j record;
  me uuid := auth.uid();
  label text;
begin
  select * into a from public.sp_applications where id = p_application;
  if a.id is null then raise exception 'This bid does not exist any more.'; end if;
  select * into j from public.sp_jobs where id = a.job_id for update;
  if j.client_id is distinct from me and not public.sp_core_has_role('ADMIN') then
    raise exception 'Only the client of this job can choose an editor.';
  end if;
  if j.status is distinct from 'open' or j.assigned_editor is not null then
    raise exception 'An editor has already been chosen for this job.';
  end if;
  if coalesce(a.status, 'pending') <> 'pending' then raise exception 'This bid is no longer available.'; end if;
  if exists (select 1 from public.sp_mod_flags f where f.user_id = a.editor_id and f.is_suspended) then
    raise exception 'This editor is not available right now. Please choose another bid.';
  end if;

  update public.sp_jobs
     set assigned_editor = a.editor_id, status = 'negotiating',
         proposed_amount = a.bid_amount, proposed_by = a.editor_id
   where id = j.id;
  update public.sp_applications set status = 'selected', updated_at = now() where id = a.id;
  update public.sp_applications set status = 'rejected', updated_at = now()
   where job_id = j.id and id <> a.id and coalesce(status, 'pending') = 'pending';

  label := coalesce(nullif(j.title, ''), j.category, 'project');
  insert into public.sp_notifications (user_id, title, body)
  values (a.editor_id, 'You got selected! 🎉', 'The client chose your bid for "' || label || '". Open the project to confirm the final price.');
  insert into public.sp_notifications (user_id, title, body)
  select editor_id, 'Bid not selected', 'The client chose another editor for "' || label || '". Keep bidding — new jobs come every day.'
    from public.sp_applications where job_id = j.id and id <> a.id and status = 'rejected' and updated_at > now() - interval '1 minute';

  return jsonb_build_object('job_id', j.id, 'editor_id', a.editor_id, 'amount', a.bid_amount);
end $$;
revoke all on function public.sp_bid_select(uuid) from public, anon;
grant execute on function public.sp_bid_select(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 6) Numbers for comparing bids / browsing jobs (no private data)
-- ---------------------------------------------------------------------
create or replace function public.sp_bid_editor_stats(p_editors uuid[])
returns table (editor_id uuid, completed int, active int, rating numeric, reviews int)
language sql stable security definer set search_path = public as $$
  select e.id,
         (select count(*) from public.sp_jobs j where j.assigned_editor = e.id and j.status in ('approved', 'closed'))::int,
         (select count(*) from public.sp_jobs j where j.assigned_editor = e.id and j.status in ('negotiating', 'payment-pending', 'in-progress', 'delivered'))::int,
         (select round(avg(r.stars)::numeric, 1) from public.sp_ratings r where r.editor_id = e.id),
         (select count(*) from public.sp_ratings r where r.editor_id = e.id)::int
  from unnest(p_editors) as e(id)
  where array_length(p_editors, 1) <= 100;
$$;
revoke all on function public.sp_bid_editor_stats(uuid[]) from public, anon;
grant execute on function public.sp_bid_editor_stats(uuid[]) to authenticated;

create or replace function public.sp_bid_counts(p_jobs uuid[])
returns table (job_id uuid, bids int)
language sql stable security definer set search_path = public as $$
  select j.id, (select count(*) from public.sp_applications a where a.job_id = j.id)::int
  from public.sp_jobs j
  where j.id = any(p_jobs) and j.status = 'open' and array_length(p_jobs, 1) <= 300;
$$;
revoke all on function public.sp_bid_counts(uuid[]) from public, anon;
grant execute on function public.sp_bid_counts(uuid[]) to authenticated;

insert into public.sp_schema_versions (version, name)
values ('006', 'Job discovery + bidding (delivery time, one bid per job, eligibility, select + close other bids)')
on conflict (version) do update set applied_at = now();

commit;

-- Done. You should see "Success. No rows returned".
