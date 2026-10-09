-- =====================================================================
-- SPHERE — PART 14: ADMIN PANEL (backend)
-- Run in: Supabase → SQL Editor → + → paste → Run.  Safe to run again.
-- Needs 001–013 first. Adds an audit log, admin-only functions and two job columns.
--
--   sp_admin_audit     who did what, to which project / user, when, old → new, reason.
--                      Filled AUTOMATICALLY by triggers on the tables admins change
--                      (verification, suspensions, disputes, refunds, held messages,
--                      extra payments, payouts, project status / flags, settings, reports),
--                      so every existing admin button is logged too.
--   sp_admin_*         read functions for the panel — every one checks ADMIN on the server.
--   sp_admin_*_action  changes — ADMIN + Admin PIN + reason, then audited.
--   sp_jobs.admin_flag none | suspicious | cleared  (+ admin_note)
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1) Audit log
-- ---------------------------------------------------------------------
create table if not exists public.sp_admin_audit (
  id           bigserial primary key,
  at           timestamptz not null default now(),
  actor_id     uuid,                    -- the admin (null = system / payment function)
  action       text not null,
  target_type  text not null,           -- user | project | dispute | refund | message | payment | payout | setting | report
  target_id    text,
  job_id       uuid,
  user_id      uuid,
  old_status   text,
  new_status   text,
  reason       text,
  details      jsonb not null default '{}'::jsonb
);
create index if not exists sp_admin_audit_at_idx on public.sp_admin_audit (at desc);
create index if not exists sp_admin_audit_job_idx on public.sp_admin_audit (job_id, at desc);
create index if not exists sp_admin_audit_user_idx on public.sp_admin_audit (user_id, at desc);
alter table public.sp_admin_audit enable row level security;
drop policy if exists sp_admin_audit_read on public.sp_admin_audit;
create policy sp_admin_audit_read on public.sp_admin_audit for select to authenticated using (public.sp_core_has_role('ADMIN'));
revoke insert, update, delete on public.sp_admin_audit from anon, authenticated;
grant select on public.sp_admin_audit to authenticated;

alter table public.sp_jobs add column if not exists admin_flag text not null default 'none';
alter table public.sp_jobs add column if not exists admin_note text;

-- admin review cases opened by hand
alter table public.sp_disputes drop constraint if exists sp_disputes_chk;
alter table public.sp_disputes add  constraint sp_disputes_chk check (kind in ('dispute', 'no_response', 'admin_review')
  and status in ('open', 'resolved_release', 'resolved_refund', 'resolved_redo', 'withdrawn')
  and (details is null or char_length(details) <= 2000));

-- who is acting right now: an admin, the system (Edge Functions / SQL Editor), or a normal user
create or replace function public.sp_audit_actor()
returns text language sql stable security definer set search_path = public as $$
  select case when auth.uid() is not null and public.sp_core_has_role('ADMIN') then 'admin'
              when auth.uid() is null then 'system' else 'user' end;
$$;

create or replace function public.sp_audit_write(p_action text, p_type text, p_target text, p_job uuid, p_user uuid,
                                                 p_old text, p_new text, p_reason text, p_details jsonb)
returns void language sql security definer set search_path = public as $$
  insert into public.sp_admin_audit (actor_id, action, target_type, target_id, job_id, user_id, old_status, new_status, reason, details)
  values (auth.uid(), p_action, p_type, p_target, p_job, p_user, p_old, p_new,
          left(coalesce(nullif(p_reason, ''), nullif(current_setting('sphere.audit_reason', true), '')), 1000), coalesce(p_details, '{}'::jsonb));
$$;
revoke all on function public.sp_audit_actor(), public.sp_audit_write(text, text, text, uuid, uuid, text, text, text, jsonb) from public, anon, authenticated;

-- one trigger function for every table admins change; logs only admin / system changes
create or replace function public.sp_audit_trigger()
returns trigger language plpgsql security definer set search_path = public as $$
declare who text := public.sp_audit_actor(); o jsonb := case when TG_OP = 'UPDATE' then to_jsonb(OLD) else '{}'::jsonb end; n jsonb := to_jsonb(NEW);
begin
  if who = 'user' then return null; end if;
  if TG_TABLE_NAME = 'profiles' then
    if (o->>'is_verified') is distinct from (n->>'is_verified') or (o->>'verification_status') is distinct from (n->>'verification_status') then
      perform public.sp_audit_write('verification', 'user', n->>'id', null, (n->>'id')::uuid,
        coalesce(o->>'verification_status', o->>'is_verified'), coalesce(n->>'verification_status', n->>'is_verified'), n->>'verification_note', '{}');
    end if;
    if (o->>'verification_fee_status') is distinct from (n->>'verification_fee_status') then
      perform public.sp_audit_write('verification_fee', 'user', n->>'id', null, (n->>'id')::uuid, o->>'verification_fee_status', n->>'verification_fee_status', null, '{}');
    end if;
    if (o->>'role') is distinct from (n->>'role') and TG_OP = 'UPDATE' then
      perform public.sp_audit_write('role', 'user', n->>'id', null, (n->>'id')::uuid, o->>'role', n->>'role', null, '{}');
    end if;
  elsif TG_TABLE_NAME = 'sp_mod_flags' then
    if (o->>'is_suspended') is distinct from (n->>'is_suspended') then
      perform public.sp_audit_write(case when (n->>'is_suspended')::boolean then 'suspend' else 'reactivate' end, 'user', n->>'user_id', null, (n->>'user_id')::uuid,
        case when coalesce((o->>'is_suspended')::boolean, false) then 'suspended' else 'active' end, case when (n->>'is_suspended')::boolean then 'suspended' else 'active' end, null, '{}');
    end if;
    if (o->>'strike_count') is distinct from (n->>'strike_count') and (n->>'strike_count')::int = 0 and who = 'admin' then
      perform public.sp_audit_write('clear_strikes', 'user', n->>'user_id', null, (n->>'user_id')::uuid, o->>'strike_count', '0', null, '{}');
    end if;
    if (o->>'warned_at') is distinct from (n->>'warned_at') and n->>'warned_at' is not null then
      perform public.sp_audit_write('warn', 'user', n->>'user_id', null, (n->>'user_id')::uuid, null, 'warned', null, '{}');
    end if;
  elsif TG_TABLE_NAME = 'sp_disputes' then
    if TG_OP = 'INSERT' or (o->>'status') is distinct from (n->>'status') or (o->>'decision_note') is distinct from (n->>'decision_note') then
      perform public.sp_audit_write(case when TG_OP = 'INSERT' then 'case_opened' else 'case_decision' end, 'dispute', n->>'id', (n->>'job_id')::uuid, null,
        o->>'status', n->>'status', coalesce(n->>'decision_note', n->>'details'), jsonb_build_object('kind', n->>'kind'));
    end if;
  elsif TG_TABLE_NAME = 'sp_refunds' then
    if TG_OP = 'INSERT' or (o->>'status') is distinct from (n->>'status') then
      perform public.sp_audit_write('refund', 'refund', n->>'id', (n->>'job_id')::uuid, null, o->>'status', n->>'status', coalesce(n->>'error', n->>'reason'), jsonb_build_object('amount', n->>'amount'));
    end if;
  elsif TG_TABLE_NAME = 'sp_msg_holds' then
    if (o->>'status') is distinct from (n->>'status') and TG_OP = 'UPDATE' then
      perform public.sp_audit_write('message_review', 'message', n->>'message_id', (n->>'job_id')::uuid, (n->>'sender_id')::uuid,
        o->>'status', n->>'status', null, jsonb_build_object('ai_verdict', n->>'ai_verdict', 'by_ai', n->>'reviewed_by' is null));
    end if;
  elsif TG_TABLE_NAME = 'sp_extra_payments' then
    if (o->>'status') is distinct from (n->>'status') and TG_OP = 'UPDATE' then
      perform public.sp_audit_write('extra_payment', 'payment', n->>'id', (n->>'job_id')::uuid, (n->>'client_id')::uuid,
        o->>'status', n->>'status', null, jsonb_build_object('amount', n->>'amount', 'method', n->>'method', 'kind', n->>'kind'));
    end if;
  elsif TG_TABLE_NAME = 'sp_payout_items' then
    if (o->>'status') is distinct from (n->>'status') and TG_OP = 'UPDATE' then
      perform public.sp_audit_write('payout', 'payout', n->>'id', (n->>'job_id')::uuid, (n->>'editor_id')::uuid,
        o->>'status', n->>'status', n->>'note', jsonb_build_object('amount', n->>'amount', 'kind', n->>'kind'));
    end if;
  elsif TG_TABLE_NAME = 'sp_jobs' then
    if (o->>'status') is distinct from (n->>'status') and TG_OP = 'UPDATE' then
      perform public.sp_audit_write('project_status', 'project', n->>'id', (n->>'id')::uuid, null, o->>'status', n->>'status', null,
        jsonb_build_object('payout_status', n->>'payout_status'));
    end if;
    if (o->>'admin_flag') is distinct from (n->>'admin_flag') and TG_OP = 'UPDATE' then
      perform public.sp_audit_write('project_flag', 'project', n->>'id', (n->>'id')::uuid, null, o->>'admin_flag', n->>'admin_flag', n->>'admin_note', '{}');
    end if;
    if (o->>'payout_status') is distinct from (n->>'payout_status') and TG_OP = 'UPDATE' then
      perform public.sp_audit_write('project_payout', 'project', n->>'id', (n->>'id')::uuid, (n->>'assigned_editor')::uuid, o->>'payout_status', n->>'payout_status', null, '{}');
    end if;
  elsif TG_TABLE_NAME = 'sp_settings' then
    if (o->>'value') is distinct from (n->>'value') then
      perform public.sp_audit_write('setting', 'setting', n->>'key', null, null, o->>'value', n->>'value', null, '{}');
    end if;
  elsif TG_TABLE_NAME = 'sp_reports' then
    if (o->>'status') is distinct from (n->>'status') and TG_OP = 'UPDATE' then
      perform public.sp_audit_write('report', 'report', n->>'id', (n->>'job_id')::uuid, (n->>'reporter_id')::uuid, o->>'status', n->>'status', n->>'admin_note', '{}');
    end if;
  end if;
  return null;
end $$;

do $$
declare t text;
begin
  foreach t in array array['profiles', 'sp_mod_flags', 'sp_disputes', 'sp_refunds', 'sp_msg_holds', 'sp_extra_payments', 'sp_payout_items', 'sp_jobs', 'sp_settings', 'sp_reports'] loop
    execute format('drop trigger if exists zz_sp_audit on public.%I', t);
    execute format('create trigger zz_sp_audit after insert or update on public.%I for each row execute function public.sp_audit_trigger()', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 2) Guards
-- ---------------------------------------------------------------------
create or replace function public.sp_admin_only()
returns void language plpgsql stable security definer set search_path = public as $$
begin
  if not public.sp_core_has_role('ADMIN') then raise exception 'Admins only'; end if;
end $$;

create or replace function public.sp_admin_with_pin(p_pin text, p_reason text, p_need_reason boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.sp_admin_only();
  perform public.sp_admin_check_pin(p_pin := p_pin);
  if p_need_reason and char_length(btrim(coalesce(p_reason, ''))) < 5 then raise exception 'Write a reason (at least 5 letters).'; end if;
  perform set_config('sphere.audit_reason', left(btrim(coalesce(p_reason, '')), 1000), true);
end $$;
revoke all on function public.sp_admin_only(), public.sp_admin_with_pin(text, text, boolean) from public, anon, authenticated;

-- project health: dispute 🔴 / suspicious ⚠️ / normal ✅ (+ why)
create or replace function public.sp_admin_health(p_job uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare j record; reasons text[] := '{}'; lim int := public.sp_setting_int('strike_limit', 3); kind text := 'normal';
begin
  select * into j from public.sp_jobs where id = p_job;
  if exists (select 1 from public.sp_disputes where job_id = p_job and status = 'open') or j.review_state in ('disputed', 'team_review')
     or exists (select 1 from public.sp_refunds where job_id = p_job and status in ('approved', 'processing', 'failed')) then
    kind := 'dispute'; reasons := array_append(reasons, 'Open case / refund'::text);
  end if;
  if j.admin_flag = 'suspicious' then reasons := array_append(reasons, 'Flagged by an admin'::text); end if;
  if exists (select 1 from public.sp_msg_holds where job_id = p_job and status in ('pending', 'removed')) then reasons := array_append(reasons, 'Held / removed chat messages'::text); end if;
  if exists (select 1 from public.sp_messages where job_id = p_job and "text" like '%📵%') then reasons := array_append(reasons, 'Contact details hidden in chat'::text); end if;
  if exists (select 1 from public.sp_mod_flags f where f.user_id in (j.client_id, j.assigned_editor) and (f.is_suspended or f.strike_count >= lim)) then
    reasons := array_append(reasons, 'A person in this project has strikes / is suspended'::text);
  end if;
  if exists (select 1 from public.sp_reports r where r.job_id = p_job and r.status = 'open') then reasons := array_append(reasons, 'Open report'::text); end if;
  if kind <> 'dispute' and cardinality(reasons) > 0 and coalesce(j.admin_flag, 'none') <> 'cleared' then kind := 'suspicious'; end if;
  if kind <> 'dispute' and j.admin_flag = 'suspicious' then kind := 'suspicious'; end if;
  return jsonb_build_object('kind', kind, 'reasons', reasons);
end $$;
revoke all on function public.sp_admin_health(uuid) from public, anon, authenticated;

-- fix from Part 12: refund eligibility reasons (text array append)
create or replace function public.sp_refund_eligibility(p_job uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare j record; p record; reasons text[] := '{}';
begin
  if not public.sp_core_has_role('ADMIN') then raise exception 'Admins only'; end if;
  select * into j from public.sp_jobs where id = p_job;
  select * into p from public.sp_payments where job_id = p_job;
  if p.status is distinct from 'paid' then reasons := array_append(reasons, 'Payment is not in "paid" state'::text); end if;
  if j.status in ('approved', 'closed') then reasons := array_append(reasons, 'Payment was already released to the editor'::text); end if;
  if j.status = 'refunded' then reasons := array_append(reasons, 'Already refunded'::text); end if;
  return jsonb_build_object('eligible', cardinality(reasons) = 0, 'reasons', reasons, 'amount', p.amount);
end $$;

-- ---------------------------------------------------------------------
-- 3) Overview
-- ---------------------------------------------------------------------
create or replace function public.sp_admin_overview()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare pct numeric; vfee numeric := public.sp_setting_int('verify_fee', 29); proj numeric; extras numeric; vcount int; r jsonb;
begin
  perform public.sp_admin_only();
  pct := coalesce((select nullif(regexp_replace(value::text, '[^0-9.]', '', 'g'), '')::numeric from public.sp_settings where key = 'platform_fee_percent'), 5);
  select coalesce(sum(coalesce(s.sphere_total, ps.platform_fee, round(coalesce(j.locked_amount, 0) * pct / 100, 2))), 0) into proj
    from public.sp_jobs j left join public.sp_settlements s on s.job_id = j.id left join public.sp_payment_splits ps on ps.job_id = j.id
   where j.status in ('approved', 'closed');
  select coalesce(sum(x.sphere_share), 0) into extras from public.sp_extra_splits x join public.sp_extra_payments e on e.id = x.extra_id where e.status = 'paid';
  select count(*) into vcount from public.profiles where verification_fee_status = 'confirmed';
  r := jsonb_build_object(
    'users',            (select count(*) from public.profiles),
    'clients',          (select count(*) from public.profiles where upper(btrim(role)) = 'CLIENT'),
    'editors',          (select count(*) from public.profiles where upper(btrim(role)) = 'EDITOR'),
    'verified_editors', (select count(*) from public.profiles where upper(btrim(role)) = 'EDITOR' and is_verified),
    'admins',           (select count(*) from public.profiles where upper(btrim(role)) = 'ADMIN'),
    'suspended',        (select count(*) from public.sp_mod_flags where is_suspended),
    'open_jobs',        (select count(*) from public.sp_jobs where status = 'open'),
    'active_projects',  (select count(*) from public.sp_jobs where status in ('negotiating', 'payment-pending', 'in-progress', 'delivered')),
    'completed',        (select count(*) from public.sp_jobs where status in ('approved', 'closed')),
    'refunded_projects',(select count(*) from public.sp_jobs where status = 'refunded'),
    'pending_payments', (select count(*) from public.sp_jobs where status = 'payment-pending'),
    'pending_refunds',  (select count(*) from public.sp_refunds where status in ('approved', 'processing', 'failed')),
    'paid_volume',      (select coalesce(sum(amount), 0) from public.sp_payments where status = 'paid'),
    'revenue',          jsonb_build_object('projects', proj, 'extras', extras, 'verification', vcount * vfee, 'total', proj + extras + vcount * vfee),
    'pending', jsonb_build_object(
       'disputes',      (select count(*) from public.sp_disputes where status = 'open'),
       'held_messages', (select count(*) from public.sp_msg_holds where status = 'pending'),
       'verifications', (select count(*) from public.profiles where upper(btrim(role)) = 'EDITOR' and not coalesce(is_verified, false)
                           and (verification_status = 'pending' or verification_fee_status = 'submitted')),
       'upi_extras',    (select count(*) from public.sp_extra_payments where status = 'pending' and utr is not null),
       'payouts',       (select count(*) from public.sp_payout_items where status = 'pending')
                      + (select count(*) from public.sp_jobs where status in ('approved', 'closed') and payout_status in ('manual', 'failed')),
       'refunds',       (select count(*) from public.sp_refunds where status in ('approved', 'failed')),
       'reports',       (select count(*) from public.sp_reports where status = 'open'),
       'suspicious_users', (select count(*) from public.sp_mod_flags where strike_count >= public.sp_setting_int('strike_limit', 3) and not is_suspended))
  );
  return r;
end $$;

-- ---------------------------------------------------------------------
-- 4) Projects
-- ---------------------------------------------------------------------
create or replace function public.sp_admin_projects(p_filter text, p_search text, p_limit int, p_offset int)
returns table (id uuid, title text, category text, status text, review_state text, client_name text, editor_name text,
               amount numeric, payment_status text, created_at timestamptz, health text, reasons text[])
language plpgsql stable security definer set search_path = public as $$
declare q text := '%' || lower(btrim(coalesce(p_search, ''))) || '%';
begin
  perform public.sp_admin_only();
  return query
  select x.id, x.title, x.category, x.status, x.review_state, x.client_name, x.editor_name, x.amount, x.payment_status, x.created_at,
         x.h->>'kind', array(select jsonb_array_elements_text(x.h->'reasons'))
  from (
    select j.id, coalesce(nullif(j.title, ''), j.category) as title, j.category, j.status, j.review_state,
           c.full_name as client_name, e.full_name as editor_name, coalesce(j.locked_amount, j.budget) as amount,
           p.status as payment_status, j.created_at, public.sp_admin_health(j.id) as h
    from public.sp_jobs j
    left join public.profiles c on c.id = j.client_id
    left join public.profiles e on e.id = j.assigned_editor
    left join public.sp_payments p on p.job_id = j.id
    where p_search is null or btrim(p_search) = ''
       or lower(coalesce(j.title, '') || ' ' || coalesce(j.category, '') || ' ' || coalesce(j.description, '') || ' ' ||
                coalesce(c.full_name, '') || ' ' || coalesce(e.full_name, '') || ' ' || replace(j.id::text, '-', '')) like q
  ) x
  where coalesce(p_filter, 'all') = 'all' or x.h->>'kind' = p_filter
  order by x.created_at desc
  limit least(greatest(coalesce(p_limit, 30), 1), 100) offset greatest(coalesce(p_offset, 0), 0);
end $$;

create or replace function public.sp_admin_project_detail(p_job uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare j record;
begin
  perform public.sp_admin_only();
  select * into j from public.sp_jobs where id = p_job;
  if j.id is null then raise exception 'Project not found.'; end if;
  return jsonb_build_object(
    'case', public.sp_case_snapshot(p_job),
    'health', public.sp_admin_health(p_job),
    'job', jsonb_build_object('id', j.id, 'status', j.status, 'review_state', j.review_state, 'admin_flag', j.admin_flag, 'admin_note', j.admin_note,
             'payout_status', j.payout_status, 'decision_due_at', j.decision_due_at, 'released_at', j.released_at, 'deadline', j.deadline),
    'people', (select jsonb_object_agg(p.id, jsonb_build_object('name', p.full_name, 'role', p.role, 'verified', p.is_verified))
                 from public.profiles p where p.id in (j.client_id, j.assigned_editor)),
    'final', (select to_jsonb(f) from public.sp_final_files f where f.job_id = p_job),
    'rating', (select to_jsonb(r) from public.sp_project_ratings r where r.job_id = p_job),
    'settlement', (select to_jsonb(s) from public.sp_settlements s where s.job_id = p_job),
    'split', (select to_jsonb(s) from public.sp_payment_splits s where s.job_id = p_job),
    'deliveries', coalesce((select jsonb_agg(to_jsonb(d) order by d.delivered_at) from public.sp_delivery_checks d where d.job_id = p_job), '[]'::jsonb),
    'extensions', coalesce((select jsonb_agg(to_jsonb(x) order by x.created_at) from public.sp_project_extensions x where x.job_id = p_job), '[]'::jsonb),
    'disputes', coalesce((select jsonb_agg(jsonb_build_object('id', d.id, 'kind', d.kind, 'category', d.category, 'details', d.details, 'status', d.status,
                  'decision_note', d.decision_note, 'created_at', d.created_at, 'decided_at', d.decided_at, 'ai_summary', d.ai_summary) order by d.created_at)
                  from public.sp_disputes d where d.job_id = p_job), '[]'::jsonb),
    'refunds', coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at) from public.sp_refunds r where r.job_id = p_job), '[]'::jsonb),
    'payouts', coalesce((select jsonb_agg(to_jsonb(p) order by p.created_at) from public.sp_payout_items p where p.job_id = p_job), '[]'::jsonb),
    'holds', coalesce((select jsonb_agg(jsonb_build_object('status', h.status, 'reason', h.reason, 'ai_verdict', h.ai_verdict, 'created_at', h.created_at) order by h.created_at)
                  from public.sp_msg_holds h where h.job_id = p_job), '[]'::jsonb),
    'audit', coalesce((select jsonb_agg(jsonb_build_object('at', a.at, 'action', a.action, 'old', a.old_status, 'new', a.new_status, 'reason', a.reason,
                  'by', coalesce((select full_name from public.profiles where id = a.actor_id), 'System')) order by a.at desc)
                  from (select * from public.sp_admin_audit where job_id = p_job order by at desc limit 50) a), '[]'::jsonb)
  );
end $$;

create or replace function public.sp_admin_project_action(p_job uuid, p_action text, p_reason text, p_hours int, p_pin text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare j record; did uuid; newdue timestamptz;
begin
  perform public.sp_admin_with_pin(p_pin, p_reason, true);
  select * into j from public.sp_jobs where id = p_job for update;
  if j.id is null then raise exception 'Project not found.'; end if;
  if p_action = 'flag' then
    update public.sp_jobs set admin_flag = 'suspicious', admin_note = left(btrim(p_reason), 500) where id = p_job;
  elsif p_action = 'clear' then
    update public.sp_jobs set admin_flag = 'cleared', admin_note = left(btrim(p_reason), 500) where id = p_job;
  elsif p_action = 'open_review' then
    if exists (select 1 from public.sp_disputes where job_id = p_job and status = 'open') then raise exception 'A case is already open for this project.'; end if;
    if j.status not in ('in-progress', 'delivered') then raise exception 'Only a paid project in progress or delivered can get a review case.'; end if;
    insert into public.sp_disputes (job_id, kind, opened_by, category, details, snapshot)
    values (p_job, 'admin_review', auth.uid(), 'other', left(btrim(p_reason), 2000), public.sp_case_snapshot(p_job)) returning id into did;
    update public.sp_jobs set review_state = 'team_review' where id = p_job and status = 'delivered';
    perform public.sp_work_event(p_job, auth.uid(), 'team_review', 'Sphere team opened a review', left(btrim(p_reason), 200));
    return jsonb_build_object('dispute_id', did);
  elsif p_action = 'add_time' then
    if coalesce(p_hours, 0) < 1 or p_hours > 168 then raise exception 'Choose 1–168 hours.'; end if;
    if not exists (select 1 from public.sp_project_work where job_id = p_job and phase = 'active') then raise exception 'The editor is not working on this project right now.'; end if;
    newdue := public.sp_work_apply_extension(p_job, p_hours);
    perform public.sp_audit_write('add_time', 'project', p_job::text, p_job, j.assigned_editor, null, public.sp_ist(newdue), p_reason, jsonb_build_object('hours', p_hours));
    perform public.sp_work_event(p_job, auth.uid(), 'extension_given', 'Sphere team gave ' || p_hours || ' more hours', 'New deadline: ' || public.sp_ist(newdue));
    perform public.sp_work_notify(j.assigned_editor, 'More time from Sphere ⏳', 'New deadline for "' || public.sp_work_label(p_job) || '": ' || public.sp_ist(newdue) || '.');
    return jsonb_build_object('due_at', newdue);
  elsif p_action = 'close_unpaid' then
    if j.status not in ('open', 'negotiating', 'payment-pending') then raise exception 'Only a project that is not paid yet can be closed.'; end if;
    if exists (select 1 from public.sp_payments where job_id = p_job and status = 'paid') then raise exception 'This project has a payment.'; end if;
    update public.sp_jobs set status = 'closed', admin_note = left(btrim(p_reason), 500) where id = p_job;
    perform public.sp_work_notify(j.client_id, 'Job closed by Sphere', '"' || public.sp_work_label(p_job) || '" was closed by the Sphere team: ' || left(btrim(p_reason), 160));
  else
    raise exception 'Unknown action.';
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 5) Users
-- ---------------------------------------------------------------------
create or replace function public.sp_admin_users(p_search text, p_role text, p_limit int)
returns table (id uuid, name text, email text, phone text, role text, verified boolean, verification_status text,
               suspended boolean, strikes int, projects bigint, rating_avg numeric, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare q text := '%' || lower(btrim(coalesce(p_search, ''))) || '%';
begin
  perform public.sp_admin_only();
  return query
  select p.id, p.full_name, p.email, p.phone, upper(btrim(p.role)), coalesce(p.is_verified, false), p.verification_status,
         coalesce(f.is_suspended, false), coalesce(f.strike_count, 0),
         (select count(*) from public.sp_jobs j where j.client_id = p.id or j.assigned_editor = p.id),
         (select round(avg(r.score), 1) from public.sp_project_ratings r where r.editor_id = p.id),
         (to_jsonb(p)->>'created_at')::timestamptz
  from public.profiles p left join public.sp_mod_flags f on f.user_id = p.id
  where (coalesce(p_role, 'all') = 'all' or upper(btrim(p.role)) = upper(p_role))
    and (btrim(coalesce(p_search, '')) = '' or lower(coalesce(p.full_name, '') || ' ' || coalesce(p.email, '') || ' ' || coalesce(p.phone, '')) like q)
  order by coalesce(f.is_suspended, false) desc, coalesce(f.strike_count, 0) desc, p.full_name
  limit least(greatest(coalesce(p_limit, 50), 1), 200);
end $$;

create or replace function public.sp_admin_user_detail(p_user uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare p record;
begin
  perform public.sp_admin_only();
  select * into p from public.profiles where id = p_user;
  if p.id is null then raise exception 'User not found.'; end if;
  return jsonb_build_object(
    'profile', jsonb_build_object('id', p.id, 'name', p.full_name, 'email', p.email, 'phone', p.phone, 'role', upper(btrim(p.role)),
                 'verified', p.is_verified, 'verification_status', p.verification_status, 'verification_note', p.verification_note,
                 'verification_code', p.verification_code, 'categories', p.categories, 'availability', p.availability, 'created_at', to_jsonb(p)->>'created_at'),
    'flags', (select to_jsonb(f) from public.sp_mod_flags f where f.user_id = p_user),
    'strikes', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'at', s.created_at, 'source', s.source, 'kind', s.kind, 'cleared', s.cleared,
                 'text', (select (public.sp_mod_mask(s.original_text)).masked)) order by s.created_at desc)
                 from (select * from public.sp_mod_strikes where user_id = p_user order by created_at desc limit 20) s), '[]'::jsonb),
    'projects', coalesce((select jsonb_agg(jsonb_build_object('id', j.id, 'title', coalesce(nullif(j.title, ''), j.category), 'status', j.status,
                 'as', case when j.client_id = p_user then 'client' else 'editor' end, 'amount', coalesce(j.locked_amount, j.budget), 'created_at', j.created_at) order by j.created_at desc)
                 from (select * from public.sp_jobs where client_id = p_user or assigned_editor = p_user order by created_at desc limit 50) j), '[]'::jsonb),
    'ratings_received', coalesce((select jsonb_agg(jsonb_build_object('score', r.score, 'feedback', r.feedback, 'at', r.created_at) order by r.created_at desc)
                 from public.sp_project_ratings r where r.editor_id = p_user), '[]'::jsonb),
    'ratings_given', coalesce((select jsonb_agg(jsonb_build_object('score', r.score, 'at', r.created_at) order by r.created_at desc)
                 from public.sp_project_ratings r where r.client_id = p_user), '[]'::jsonb),
    'earnings', (select jsonb_build_object('projects', count(*), 'base', coalesce(sum(editor_base), 0), 'bonus', coalesce(sum(bonus_awarded), 0),
                 'deductions', coalesce(sum(late_deduction), 0)) from public.sp_settlements where editor_id = p_user),
    'spent', (select coalesce(sum(amount), 0) from public.sp_payments where client_id = p_user and status = 'paid'),
    'audit', coalesce((select jsonb_agg(jsonb_build_object('at', a.at, 'action', a.action, 'old', a.old_status, 'new', a.new_status, 'reason', a.reason,
                 'by', coalesce((select full_name from public.profiles where id = a.actor_id), 'System')) order by a.at desc)
                 from (select * from public.sp_admin_audit where user_id = p_user order by at desc limit 30) a), '[]'::jsonb)
  );
end $$;

create or replace function public.sp_admin_user_action(p_user uuid, p_action text, p_reason text, p_pin text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  perform public.sp_admin_with_pin(p_pin, p_reason, p_action in ('suspend', 'reactivate', 'warn'));
  if p_user = auth.uid() then raise exception 'You cannot change your own account here.'; end if;
  insert into public.sp_mod_flags (user_id) values (p_user) on conflict (user_id) do nothing;
  if p_action = 'suspend' then
    update public.sp_mod_flags set is_suspended = true, updated_at = now() where user_id = p_user;
    insert into public.sp_notifications (user_id, title, body) values (p_user, 'Account suspended ⛔', 'Reason: ' || left(btrim(p_reason), 200) || '. Contact Sphere support to talk about it.');
  elsif p_action = 'reactivate' then
    update public.sp_mod_flags set is_suspended = false, updated_at = now() where user_id = p_user;
    insert into public.sp_notifications (user_id, title, body) values (p_user, 'Account active again ✅', 'Your Sphere account is active again.');
  elsif p_action = 'warn' then
    update public.sp_mod_flags set warned_at = now(), updated_at = now() where user_id = p_user;
    insert into public.sp_notifications (user_id, title, body) values (p_user, 'Warning from Sphere ⚠️', left(btrim(p_reason), 300));
  elsif p_action = 'clear_strikes' then
    update public.sp_mod_flags set strike_count = 0, updated_at = now() where user_id = p_user;
    update public.sp_mod_strikes set cleared = true where user_id = p_user and not cleared;
  else
    raise exception 'Unknown action.';
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 6) Verification, moderation, payments, audit (read)
-- ---------------------------------------------------------------------
create or replace function public.sp_admin_verifications()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.sp_admin_only();
  return coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.full_name, 'phone', p.phone, 'email', p.email,
           'categories', p.categories, 'languages', p.languages, 'skills', p.skills, 'experience', p.experience_years, 'price', p.price_range,
           'sample', p.sample_video_url, 'portfolio', p.portfolio_url, 'bio', p.bio,
           'status', coalesce(p.verification_status, 'pending'), 'note', p.verification_note,
           'fee_status', coalesce(p.verification_fee_status, 'unpaid'), 'fee_ref', p.verification_fee_ref, 'fee_at', p.verification_fee_at,
           'works', (select count(*) from public.sp_jobs j where j.assigned_editor = p.id and j.status in ('in-progress', 'delivered', 'approved', 'closed')))
         order by (p.verification_fee_status = 'submitted') desc, p.verification_fee_at nulls last)
         from public.profiles p
         where upper(btrim(p.role)) = 'EDITOR' and not coalesce(p.is_verified, false)
           and coalesce(p.verification_status, 'pending') in ('pending', 'rejected')), '[]'::jsonb);
end $$;

create or replace function public.sp_admin_moderation()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.sp_admin_only();
  return jsonb_build_object(
    'hidden', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'user_id', s.user_id, 'name', p.full_name, 'source', s.source, 'kind', s.kind, 'at', s.created_at,
                  'text', (select (public.sp_mod_mask(s.original_text)).masked)) order by s.created_at desc)
                  from (select * from public.sp_mod_strikes order by created_at desc limit 40) s left join public.profiles p on p.id = s.user_id), '[]'::jsonb),
    'reviewed', coalesce((select jsonb_agg(jsonb_build_object('status', h.status, 'at', h.reviewed_at, 'by_ai', h.reviewed_by is null, 'ai_verdict', h.ai_verdict,
                  'name', p.full_name, 'text', left(h.original_text, 160)) order by h.reviewed_at desc)
                  from (select * from public.sp_msg_holds where status <> 'pending' order by reviewed_at desc nulls last limit 30) h left join public.profiles p on p.id = h.sender_id), '[]'::jsonb),
    'flagged_users', coalesce((select jsonb_agg(jsonb_build_object('id', f.user_id, 'name', p.full_name, 'role', p.role, 'strikes', f.strike_count, 'suspended', f.is_suspended,
                  'warned_at', f.warned_at) order by f.is_suspended desc, f.strike_count desc)
                  from public.sp_mod_flags f join public.profiles p on p.id = f.user_id where f.strike_count > 0 or f.is_suspended), '[]'::jsonb));
end $$;

-- show the original of one hidden message (logged)
create or replace function public.sp_admin_reveal(p_strike bigint, p_reason text, p_pin text)
returns text language plpgsql security definer set search_path = public as $$
declare s record;
begin
  perform public.sp_admin_with_pin(p_pin, p_reason, true);
  select * into s from public.sp_mod_strikes where id = p_strike;
  if s.id is null then raise exception 'Not found.'; end if;
  perform public.sp_audit_write('reveal_hidden_text', 'message', p_strike::text, null, s.user_id, null, null, p_reason, '{}');
  return s.original_text;
end $$;

create or replace function public.sp_admin_payments()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.sp_admin_only();
  return jsonb_build_object(
    'by_status', coalesce((select jsonb_object_agg(status, n) from (select status, count(*) n from public.sp_payments group by 1) x), '{}'::jsonb),
    'payments', coalesce((select jsonb_agg(jsonb_build_object('job_id', p.job_id, 'title', coalesce(nullif(j.title, ''), j.category), 'amount', p.amount, 'status', p.status,
                  'paid_at', p.paid_at, 'job_status', j.status, 'payout_status', j.payout_status) order by p.updated_at desc)
                  from (select * from public.sp_payments order by updated_at desc limit 40) p left join public.sp_jobs j on j.id = p.job_id), '[]'::jsonb),
    'manual_payouts', coalesce((select jsonb_agg(jsonb_build_object('job_id', j.id, 'title', coalesce(nullif(j.title, ''), j.category), 'editor', e.full_name,
                  'amount', coalesce(j.editor_amount, s.editor_payout), 'payout_status', j.payout_status) order by j.created_at)
                  from public.sp_jobs j left join public.profiles e on e.id = j.assigned_editor left join public.sp_payment_splits s on s.job_id = j.id
                  where j.status in ('approved', 'closed') and j.payout_status in ('manual', 'failed')), '[]'::jsonb),
    'payout_items', coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'job_id', i.job_id, 'kind', i.kind, 'amount', i.amount, 'status', i.status, 'note', i.note,
                  'editor', e.full_name, 'created_at', i.created_at) order by i.created_at desc)
                  from (select * from public.sp_payout_items order by created_at desc limit 50) i left join public.profiles e on e.id = i.editor_id), '[]'::jsonb),
    'refunds', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'job_id', r.job_id, 'title', coalesce(nullif(j.title, ''), j.category), 'amount', r.amount,
                  'status', r.status, 'reason', r.reason, 'error', r.error, 'created_at', r.created_at) order by r.created_at desc)
                  from public.sp_refunds r left join public.sp_jobs j on j.id = r.job_id), '[]'::jsonb),
    'settlements', coalesce((select jsonb_agg(jsonb_build_object('job_id', s.job_id, 'title', coalesce(nullif(j.title, ''), j.category), 'editor', e.full_name,
                  'paid', s.client_paid, 'base', s.editor_base, 'pool', s.pool, 'sphere', s.sphere_total, 'bonus', s.bonus_awarded, 'met', s.conditions_met,
                  'late_hours', s.late_hours, 'deduction', s.late_deduction, 'status', s.status) order by s.computed_at desc)
                  from (select * from public.sp_settlements order by computed_at desc limit 40) s left join public.sp_jobs j on j.id = s.job_id
                  left join public.profiles e on e.id = s.editor_id), '[]'::jsonb),
    'totals', (select jsonb_build_object('bonus', coalesce(sum(bonus_awarded), 0), 'deductions', coalesce(sum(late_deduction), 0),
                  'sphere', coalesce(sum(sphere_total), 0), 'base', coalesce(sum(editor_base), 0)) from public.sp_settlements));
end $$;

create or replace function public.sp_admin_audit_list(p_limit int, p_action text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.sp_admin_only();
  return coalesce((select jsonb_agg(jsonb_build_object('at', a.at, 'by', coalesce(p.full_name, 'System'), 'action', a.action, 'type', a.target_type,
           'job_id', a.job_id, 'project', coalesce(nullif(j.title, ''), j.category), 'user', u.full_name, 'old', a.old_status, 'new', a.new_status,
           'reason', a.reason) order by a.at desc)
         from (select * from public.sp_admin_audit where coalesce(p_action, '') = '' or action = p_action order by at desc limit least(greatest(coalesce(p_limit, 100), 1), 300)) a
         left join public.profiles p on p.id = a.actor_id left join public.sp_jobs j on j.id = a.job_id left join public.profiles u on u.id = a.user_id), '[]'::jsonb);
end $$;

revoke all on function public.sp_admin_overview(), public.sp_admin_projects(text, text, int, int), public.sp_admin_project_detail(uuid),
              public.sp_admin_project_action(uuid, text, text, int, text), public.sp_admin_users(text, text, int), public.sp_admin_user_detail(uuid),
              public.sp_admin_user_action(uuid, text, text, text), public.sp_admin_verifications(), public.sp_admin_moderation(),
              public.sp_admin_reveal(bigint, text, text), public.sp_admin_payments(), public.sp_admin_audit_list(int, text) from public, anon;
grant execute on function public.sp_admin_overview(), public.sp_admin_projects(text, text, int, int), public.sp_admin_project_detail(uuid),
              public.sp_admin_project_action(uuid, text, text, int, text), public.sp_admin_users(text, text, int), public.sp_admin_user_detail(uuid),
              public.sp_admin_user_action(uuid, text, text, text), public.sp_admin_verifications(), public.sp_admin_moderation(),
              public.sp_admin_reveal(bigint, text, text), public.sp_admin_payments(), public.sp_admin_audit_list(int, text) to authenticated;

-- every sp_admin_* function (also older ones like sp_admin_check_pin): never callable without login
do $$
declare r record; auth_ok boolean;
begin
  for r in select p.oid, p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname like 'sp_admin_%' loop
    auth_ok := has_function_privilege('authenticated', r.oid, 'execute');
    execute format('revoke execute on function %s from public, anon', r.sig);
    if auth_ok then execute format('grant execute on function %s to authenticated', r.sig); end if;
  end loop;
end $$;

insert into public.sp_schema_versions (version, name)
values ('014', 'Admin panel (audit log, admin-only overview / projects / users / payments / moderation)')
on conflict (version) do update set applied_at = now();

commit;

-- Done. You should see "Success. No rows returned".
