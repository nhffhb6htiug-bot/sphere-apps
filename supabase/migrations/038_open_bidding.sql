-- =====================================================================
-- SPHERE — OPEN BIDDING: every editor can bid; clients see who is verified ✔ and who is not
-- Owner decision (21 Oct 2026): no limit of paid works before verification, and editors whose
-- verification was rejected can bid too. Still blocked: not an editor, suspended, "Away", own job,
-- closed / expired job. Premium jobs keep their own rule (verified Pro editors only, separate trigger).
-- The admin switch bids_verified_only (Settings) still works if the team ever needs it.
-- Safe to run again. Deletes NO data.
-- =====================================================================
begin;
create or replace function public.sp_bid_eligibility(p_editor uuid default auth.uid(), p_job uuid default null::uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $function$
declare p record; j record;
begin
  select id, upper(btrim(role)) as role, is_verified, verification_status, availability
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
  if public.sp_setting_int('bids_verified_only', 0) = 1 then
    return jsonb_build_object('ok', false, 'code', 'verified_only', 'message', 'Only verified ✔ editors can bid right now. Get verified to start bidding.');
  end if;
  return jsonb_build_object('ok', true, 'code', 'unverified', 'verified', false);   -- clients see "Not verified" on the bid
end $function$;
insert into public.sp_schema_versions (version, name) values ('038', 'Open bidding: every editor can bid; clients see verified / not verified')
on conflict (version) do update set applied_at = now();
commit;
