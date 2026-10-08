-- =====================================================================
-- SPHERE — PART 8: PROJECT WORKFLOW + DEADLINES
-- Run in: Supabase → SQL Editor → + → paste → Run.  Safe to run again.
-- Needs 001, 002, 006, 007 first. Adds tables/functions; deletes nothing.
--
--   sp_project_work        the work clock of a paid project: start, deadline,
--                          4-hour grace, late flag, preview, extensions
--   sp_project_extensions  "more time" requests (editor asks, client answers)
--   sp_project_events      full timeline of every project (who did what, when)
--   Deadline = 24 hours per delivery day the editor promised in the bid
--   (no bid days → 24 hours). Grace = 4 hours. Both are settings.
--   sp_work_tick() sends reminders / "deadline passed" / "late" once each.
--   It runs every 10 minutes if pg_cron is available, and also whenever
--   someone opens the app.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1) Settings (only added if missing)
-- ---------------------------------------------------------------------
insert into public.sp_settings (key, value) select 'work_default_hours', '24' where not exists (select 1 from public.sp_settings where key = 'work_default_hours');
insert into public.sp_settings (key, value) select 'work_grace_hours', '4'    where not exists (select 1 from public.sp_settings where key = 'work_grace_hours');
insert into public.sp_settings (key, value) select 'work_fixed_hours', '0'    where not exists (select 1 from public.sp_settings where key = 'work_fixed_hours');
insert into public.sp_settings (key, value) select 'work_reminder_hours', '4' where not exists (select 1 from public.sp_settings where key = 'work_reminder_hours');

-- ---------------------------------------------------------------------
-- 2) Tables
-- ---------------------------------------------------------------------
create table if not exists public.sp_project_work (
  job_id                  uuid primary key,
  client_id               uuid not null,
  editor_id               uuid not null,
  phase                   text not null default 'active',     -- active | preview | completed | cancelled
  started_at              timestamptz not null default now(),
  hours                   int not null,
  due_at                  timestamptz not null,
  grace_hours             int not null default 4,
  extended_hours          int not null default 0,
  pending_extension_hours int,
  preview_link            text,
  preview_note            text,
  preview_at              timestamptz,
  preview_on_time         boolean,
  is_late                 boolean not null default false,
  late_since              timestamptz,
  reminded_at             timestamptz,
  due_notified_at         timestamptz,
  late_notified_at        timestamptz,
  completed_at            timestamptz,
  updated_at              timestamptz not null default now()
);
alter table public.sp_project_work drop constraint if exists sp_work_phase_chk;
alter table public.sp_project_work add  constraint sp_work_phase_chk check (phase in ('active', 'preview', 'completed', 'cancelled'));

create table if not exists public.sp_project_extensions (
  id           uuid primary key default gen_random_uuid(),
  job_id       uuid not null,
  requested_by uuid,
  hours        int not null,
  reason       text,
  status       text not null default 'pending',
  created_at   timestamptz not null default now(),
  decided_at   timestamptz,
  decided_by   uuid
);
alter table public.sp_project_extensions drop constraint if exists sp_ext_chk;
alter table public.sp_project_extensions add  constraint sp_ext_chk check (hours between 1 and 168 and status in ('pending', 'approved', 'declined')
                                                                         and (reason is null or char_length(reason) <= 300));
create unique index if not exists sp_ext_one_pending on public.sp_project_extensions (job_id) where status = 'pending';

create table if not exists public.sp_project_events (
  id       bigserial primary key,
  job_id   uuid not null,
  at       timestamptz not null default now(),
  actor_id uuid,
  kind     text not null,
  title    text not null,
  details  text
);
create index if not exists sp_events_job_idx on public.sp_project_events (job_id, at);

-- only the two people in the project (and admins) can read; nobody writes from the app
alter table public.sp_project_work       enable row level security;
alter table public.sp_project_extensions enable row level security;
alter table public.sp_project_events     enable row level security;
drop policy if exists sp_work_read on public.sp_project_work;
create policy sp_work_read on public.sp_project_work for select to authenticated
  using (client_id = auth.uid() or editor_id = auth.uid() or public.sp_core_has_role('ADMIN'));
drop policy if exists sp_ext_read on public.sp_project_extensions;
create policy sp_ext_read on public.sp_project_extensions for select to authenticated
  using (exists (select 1 from public.sp_jobs j where j.id = job_id and (j.client_id = auth.uid() or j.assigned_editor = auth.uid())) or public.sp_core_has_role('ADMIN'));
drop policy if exists sp_events_read on public.sp_project_events;
create policy sp_events_read on public.sp_project_events for select to authenticated
  using (exists (select 1 from public.sp_jobs j where j.id = job_id and (j.client_id = auth.uid() or j.assigned_editor = auth.uid())) or public.sp_core_has_role('ADMIN'));
revoke insert, update, delete on public.sp_project_work, public.sp_project_extensions, public.sp_project_events from anon, authenticated;
grant select on public.sp_project_work, public.sp_project_extensions, public.sp_project_events to authenticated;

-- ---------------------------------------------------------------------
-- 3) Small helpers
-- ---------------------------------------------------------------------
create or replace function public.sp_ist(p timestamptz)
returns text language sql immutable as $$
  select to_char(p at time zone 'Asia/Kolkata', 'DD Mon, HH12:MI AM');
$$;

create or replace function public.sp_work_event(p_job uuid, p_actor uuid, p_kind text, p_title text, p_details text default null)
returns void language sql security definer set search_path = public as $$
  insert into public.sp_project_events (job_id, actor_id, kind, title, details) values (p_job, p_actor, p_kind, p_title, p_details);
$$;

create or replace function public.sp_work_notify(p_user uuid, p_title text, p_body text)
returns void language sql security definer set search_path = public as $$
  insert into public.sp_notifications (user_id, title, body) select p_user, p_title, p_body where p_user is not null;
$$;

create or replace function public.sp_work_label(p_job uuid)
returns text language sql stable security definer set search_path = public as $$
  select coalesce(nullif(title, ''), category, 'project') from public.sp_jobs where id = p_job;
$$;

-- deadline hours for a project: setting override → editor's bid days × 24 → default 24
create or replace function public.sp_work_hours(p_job uuid, p_editor uuid)
returns int language plpgsql stable security definer set search_path = public as $$
declare fixed int := public.sp_setting_int('work_fixed_hours', 0); d int;
begin
  if fixed > 0 then return fixed; end if;
  select delivery_days into d from public.sp_applications
   where job_id = p_job and editor_id = p_editor order by (status = 'selected') desc limit 1;
  if coalesce(d, 0) > 0 then return d * 24; end if;
  return greatest(1, public.sp_setting_int('work_default_hours', 24));
end $$;

-- start the work clock (used when a project is paid)
create or replace function public.sp_work_start(p_job uuid, p_notify boolean)
returns void language plpgsql security definer set search_path = public as $$
declare j record; hrs int; due timestamptz; label text;
begin
  select * into j from public.sp_jobs where id = p_job;
  if j.id is null or j.assigned_editor is null then return; end if;
  if exists (select 1 from public.sp_project_work where job_id = p_job) then return; end if;
  hrs := public.sp_work_hours(p_job, j.assigned_editor);
  due := now() + make_interval(hours => hrs);
  insert into public.sp_project_work (job_id, client_id, editor_id, started_at, hours, due_at, grace_hours)
  values (p_job, j.client_id, j.assigned_editor, now(), hrs, due, public.sp_setting_int('work_grace_hours', 4));
  label := coalesce(nullif(j.title, ''), j.category, 'project');
  perform public.sp_work_event(p_job, null, 'started', 'Work started', 'Deadline: ' || public.sp_ist(due) || ' (' || hrs || ' hours)');
  if p_notify then
    perform public.sp_work_notify(j.assigned_editor, 'Start now — project is paid ▶️',
      '"' || label || '" is paid. Deadline: ' || public.sp_ist(due) || ' (' || hrs || ' hours). Send the preview before then.');
    perform public.sp_work_notify(j.client_id, 'Your project has started ▶️',
      'The editor is working on "' || label || '". Preview expected by ' || public.sp_ist(due) || '.');
  end if;
end $$;

-- change the deadline (extension approved / time given)
create or replace function public.sp_work_apply_extension(p_job uuid, p_hours int)
returns timestamptz language plpgsql security definer set search_path = public as $$
declare w record; base timestamptz; newdue timestamptz;
begin
  select * into w from public.sp_project_work where job_id = p_job for update;
  base := greatest(w.due_at, now());
  newdue := base + make_interval(hours => p_hours);
  update public.sp_project_work
     set due_at = newdue, extended_hours = extended_hours + p_hours, pending_extension_hours = null,
         is_late = false, late_since = null, reminded_at = null, due_notified_at = null, late_notified_at = null,
         updated_at = now()
   where job_id = p_job;
  return newdue;
end $$;

-- ---------------------------------------------------------------------
-- 4) Timeline + work clock follow the project status (works with the existing app + Edge Functions)
-- ---------------------------------------------------------------------
create or replace function public.sp_work_job_trigger()
returns trigger language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if TG_OP = 'INSERT' then
    perform public.sp_work_event(NEW.id, NEW.client_id, 'posted', case when NEW.status = 'negotiating' then 'Direct hire sent to an editor' else 'Job posted' end, null);
    return null;
  end if;
  if NEW.status is not distinct from OLD.status then return null; end if;

  if NEW.status = 'negotiating' then
    perform public.sp_work_event(NEW.id, me, 'editor_chosen', 'Editor chosen', null);
  elsif NEW.status = 'payment-pending' then
    perform public.sp_work_event(NEW.id, me, 'price_locked', 'Price locked', '₹' || coalesce(NEW.locked_amount, NEW.budget));
  elsif NEW.status = 'in-progress' then
    perform public.sp_work_start(NEW.id, true);
  elsif NEW.status = 'delivered' then
    update public.sp_project_work set phase = 'completed', completed_at = now(), updated_at = now() where job_id = NEW.id and phase in ('active', 'preview');
    perform public.sp_work_event(NEW.id, me, 'delivered', 'Final video delivered', null);
  elsif NEW.status = 'approved' then
    perform public.sp_work_event(NEW.id, me, 'approved', 'Client approved the work', null);
  elsif NEW.status = 'closed' then
    perform public.sp_work_event(NEW.id, me, 'closed', 'Project completed', null);
  elsif NEW.status = 'refunded' then
    update public.sp_project_work set phase = 'cancelled', updated_at = now() where job_id = NEW.id and phase <> 'completed';
    perform public.sp_work_event(NEW.id, me, 'refunded', 'Project refunded', null);
  elsif NEW.status = 'open' then
    perform public.sp_work_event(NEW.id, me, 'reopened', 'Job open for bids again', null);
  end if;
  return null;
end $$;
drop trigger if exists sp_work_job_trigger on public.sp_jobs;
create trigger sp_work_job_trigger after insert or update of status on public.sp_jobs
  for each row execute function public.sp_work_job_trigger();

create or replace function public.sp_work_pay_trigger()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if NEW.status is not distinct from OLD.status then return null; end if;
  if NEW.status = 'paid' then
    perform public.sp_work_event(NEW.job_id, NEW.client_id, 'paid', 'Payment received — held safely by Sphere', null);
  elsif NEW.status = 'failed' then
    perform public.sp_work_event(NEW.job_id, NEW.client_id, 'payment_failed', 'Payment attempt failed', NEW.failure_reason);
  end if;
  return null;
end $$;
drop trigger if exists sp_work_pay_trigger on public.sp_payments;
create trigger sp_work_pay_trigger after update of status on public.sp_payments
  for each row execute function public.sp_work_pay_trigger();

-- ---------------------------------------------------------------------
-- 5) Reminders, "deadline passed", "late" — each sent once per deadline
-- ---------------------------------------------------------------------
create or replace function public.sp_work_tick()
returns int language plpgsql security definer set search_path = public as $$
declare w record; rem int := public.sp_setting_int('work_reminder_hours', 4); grace_end timestamptz; label text; n int := 0;
begin
  for w in select * from public.sp_project_work where phase = 'active' for update skip locked loop
    grace_end := w.due_at + make_interval(hours => w.grace_hours);
    label := public.sp_work_label(w.job_id);

    if w.reminded_at is null and w.hours > rem and now() >= w.due_at - make_interval(hours => rem) and now() < w.due_at then
      perform public.sp_work_notify(w.editor_id, 'Deadline in ' || rem || ' hours ⏰', 'Send the preview for "' || label || '" before ' || public.sp_ist(w.due_at) || '.');
      perform public.sp_work_event(w.job_id, null, 'reminder', 'Reminder sent to the editor', rem || ' hours left');
      update public.sp_project_work set reminded_at = now() where job_id = w.job_id;
      n := n + 1;
    end if;

    if w.due_notified_at is null and now() >= w.due_at then
      perform public.sp_work_notify(w.editor_id, 'Deadline reached ⚠️',
        'The deadline for "' || label || '" has passed. You have a ' || w.grace_hours || '-hour grace period — send the preview before ' || public.sp_ist(grace_end) || '.');
      perform public.sp_work_notify(w.client_id, 'Deadline passed',
        'The editor of "' || label || '" has a ' || w.grace_hours || '-hour grace period (until ' || public.sp_ist(grace_end) || '). You can also give more time.');
      perform public.sp_work_event(w.job_id, null, 'deadline_passed', 'Deadline passed — grace period started', 'Grace until ' || public.sp_ist(grace_end));
      update public.sp_project_work set due_notified_at = now(), reminded_at = coalesce(reminded_at, now()) where job_id = w.job_id;
      n := n + 1;
    end if;

    if not w.is_late and now() >= grace_end then
      update public.sp_project_work set is_late = true, late_since = grace_end, late_notified_at = now(),
             due_notified_at = coalesce(due_notified_at, now()), reminded_at = coalesce(reminded_at, now()) where job_id = w.job_id;
      perform public.sp_work_notify(w.editor_id, 'Project is late 🔴', '"' || label || '" is late. Send the preview as soon as possible, or ask the client for more time.');
      perform public.sp_work_notify(w.client_id, 'Project is late 🔴', 'The editor missed the deadline for "' || label || '". You can give more time from the project page.');
      perform public.sp_work_event(w.job_id, null, 'late', 'Marked late — grace period over', null);
      n := n + 1;
    end if;
  end loop;
  return n;
end $$;
revoke all on function public.sp_work_tick() from public, anon;
grant execute on function public.sp_work_tick() to authenticated;

-- ---------------------------------------------------------------------
-- 6) Actions (only the right person, only at the right time)
-- ---------------------------------------------------------------------
-- editor: work is ready for preview
create or replace function public.sp_work_submit_preview(p_job uuid, p_link text, p_note text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare j record; w record; link text := btrim(coalesce(p_link, '')); note text; grace_end timestamptz; first boolean;
begin
  select * into j from public.sp_jobs where id = p_job;
  if j.id is null then raise exception 'Project not found.'; end if;
  if auth.uid() is distinct from j.assigned_editor then raise exception 'Only the editor of this project can send the preview.'; end if;
  if j.status is distinct from 'in-progress' then raise exception 'The preview can be sent while the project is in progress.'; end if;
  perform public.sp_work_start(p_job, false);
  select * into w from public.sp_project_work where job_id = p_job for update;
  if link !~* '^https?://\S+$' or char_length(link) > 500 then raise exception 'Please paste a full link that starts with https://'; end if;
  if (select (public.sp_mod_mask(link)).hard) then
    raise exception 'Please share the preview through Google Drive, YouTube (unlisted), WeTransfer or Dropbox.';
  end if;
  note := nullif(left((select (public.sp_mod_mask(btrim(coalesce(p_note, '')))).masked), 500), '');
  grace_end := w.due_at + make_interval(hours => w.grace_hours);
  first := w.preview_at is null;
  update public.sp_project_work
     set preview_link = link, preview_note = note, preview_at = now(), phase = 'preview',
         preview_on_time = case when first then now() <= grace_end else preview_on_time end,
         pending_extension_hours = null, updated_at = now()
   where job_id = p_job;
  update public.sp_project_extensions set status = 'declined', decided_at = now() where job_id = p_job and status = 'pending';
  perform public.sp_work_event(p_job, auth.uid(), case when first then 'preview' else 'preview_updated' end,
    case when first then 'Preview ready' || case when now() <= grace_end then '' else ' (late)' end else 'Preview updated' end, note);
  perform public.sp_work_notify(j.client_id, case when first then 'Preview ready 👀' else 'Preview updated 👀' end,
    'Your editor shared a ' || case when first then '' else 'new ' end || 'preview for "' || public.sp_work_label(p_job) || '". Open the project to watch it.');
  return jsonb_build_object('on_time', now() <= grace_end);
end $$;

-- editor: ask for more time
create or replace function public.sp_work_request_extension(p_job uuid, p_hours int, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare j record; w record; reason text;
begin
  select * into j from public.sp_jobs where id = p_job;
  if auth.uid() is distinct from j.assigned_editor then raise exception 'Only the editor of this project can ask for more time.'; end if;
  select * into w from public.sp_project_work where job_id = p_job for update;
  if w.job_id is null or w.phase <> 'active' then raise exception 'More time can be asked only while the work is in progress.'; end if;
  if p_hours is null or p_hours < 1 or p_hours > 72 then raise exception 'Choose between 1 and 72 hours.'; end if;
  if exists (select 1 from public.sp_project_extensions where job_id = p_job and status = 'pending') then raise exception 'You already asked for more time. Wait for the client to answer.'; end if;
  reason := nullif(left((select (public.sp_mod_mask(btrim(coalesce(p_reason, '')))).masked), 300), '');
  insert into public.sp_project_extensions (job_id, requested_by, hours, reason) values (p_job, auth.uid(), p_hours, reason);
  update public.sp_project_work set pending_extension_hours = p_hours, updated_at = now() where job_id = p_job;
  perform public.sp_work_event(p_job, auth.uid(), 'extension_requested', 'Editor asked for ' || p_hours || ' more hours', reason);
  perform public.sp_work_notify(j.client_id, 'Editor asked for more time ⏳',
    'The editor of "' || public.sp_work_label(p_job) || '" asked for ' || p_hours || ' more hours' || coalesce(': ' || reason, '') || '. Open the project to answer.');
end $$;

-- client: answer the editor's request
create or replace function public.sp_work_answer_extension(p_job uuid, p_approve boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare j record; x record; newdue timestamptz;
begin
  select * into j from public.sp_jobs where id = p_job;
  if auth.uid() is distinct from j.client_id then raise exception 'Only the client of this project can answer.'; end if;
  select * into x from public.sp_project_extensions where job_id = p_job and status = 'pending' for update;
  if x.id is null then raise exception 'There is no request waiting.'; end if;
  update public.sp_project_extensions set status = case when p_approve then 'approved' else 'declined' end,
         decided_at = now(), decided_by = auth.uid() where id = x.id;
  if p_approve then
    newdue := public.sp_work_apply_extension(p_job, x.hours);
    perform public.sp_work_event(p_job, auth.uid(), 'extension_approved', 'Client gave ' || x.hours || ' more hours', 'New deadline: ' || public.sp_ist(newdue));
    perform public.sp_work_notify(x.requested_by, 'More time approved ✅', 'New deadline for "' || public.sp_work_label(p_job) || '": ' || public.sp_ist(newdue) || '.');
  else
    update public.sp_project_work set pending_extension_hours = null, updated_at = now() where job_id = p_job;
    perform public.sp_work_event(p_job, auth.uid(), 'extension_declined', 'Client said no to more time', null);
    perform public.sp_work_notify(x.requested_by, 'More time not approved', 'Please send the preview for "' || public.sp_work_label(p_job) || '" as soon as possible.');
  end if;
  return jsonb_build_object('approved', p_approve, 'due_at', newdue);
end $$;

-- client: give more time without being asked
create or replace function public.sp_work_give_time(p_job uuid, p_hours int, p_note text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare j record; w record; newdue timestamptz; note text;
begin
  select * into j from public.sp_jobs where id = p_job;
  if auth.uid() is distinct from j.client_id then raise exception 'Only the client of this project can give more time.'; end if;
  select * into w from public.sp_project_work where job_id = p_job for update;
  if w.job_id is null or w.phase <> 'active' then raise exception 'More time can be given only while the editor is working.'; end if;
  if p_hours is null or p_hours < 1 or p_hours > 168 then raise exception 'Choose between 1 and 168 hours.'; end if;
  note := nullif(left((select (public.sp_mod_mask(btrim(coalesce(p_note, '')))).masked), 300), '');
  update public.sp_project_extensions set status = 'approved', decided_at = now(), decided_by = auth.uid() where job_id = p_job and status = 'pending';
  newdue := public.sp_work_apply_extension(p_job, p_hours);
  perform public.sp_work_event(p_job, auth.uid(), 'extension_given', 'Client gave ' || p_hours || ' more hours', 'New deadline: ' || public.sp_ist(newdue) || coalesce(' — ' || note, ''));
  perform public.sp_work_notify(j.assigned_editor, 'You got more time ⏳', 'New deadline for "' || public.sp_work_label(p_job) || '": ' || public.sp_ist(newdue) || coalesce('. Note: ' || note, '') || '.');
  return jsonb_build_object('due_at', newdue);
end $$;

revoke all on function public.sp_work_submit_preview(uuid, text, text), public.sp_work_request_extension(uuid, int, text),
              public.sp_work_answer_extension(uuid, boolean), public.sp_work_give_time(uuid, int, text) from public, anon;
grant execute on function public.sp_work_submit_preview(uuid, text, text), public.sp_work_request_extension(uuid, int, text),
              public.sp_work_answer_extension(uuid, boolean), public.sp_work_give_time(uuid, int, text) to authenticated;
revoke all on function public.sp_work_start(uuid, boolean), public.sp_work_apply_extension(uuid, int),
              public.sp_work_event(uuid, uuid, text, text, text), public.sp_work_notify(uuid, text, text) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 7) Existing projects
--    • every job gets a "Job posted" line in its timeline
--    • projects already in progress start their clock NOW (not from an old date,
--      so nobody is marked late by surprise). No notifications are sent.
-- ---------------------------------------------------------------------
insert into public.sp_project_events (job_id, at, actor_id, kind, title)
select j.id, coalesce(j.created_at, now()), j.client_id, 'posted', 'Job posted'
from public.sp_jobs j
where not exists (select 1 from public.sp_project_events e where e.job_id = j.id);

do $$
declare r record;
begin
  for r in select id from public.sp_jobs where status = 'in-progress' and assigned_editor is not null
           and not exists (select 1 from public.sp_project_work w where w.job_id = sp_jobs.id) loop
    perform public.sp_work_start(r.id, false);
  end loop;
end $$;

insert into public.sp_schema_versions (version, name)
values ('008', 'Project workflow + deadlines (clock, grace, late, extensions, preview, timeline)')
on conflict (version) do update set applied_at = now();

commit;

-- ---------------------------------------------------------------------
-- 8) Every 10 minutes (optional — needs pg_cron; the app also checks on open)
-- ---------------------------------------------------------------------
do $$
begin
  begin
    create extension if not exists pg_cron with schema pg_catalog;
  exception when others then
    raise notice 'pg_cron is not available — deadlines are checked whenever someone opens the app.';
  end;
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    begin
      perform cron.unschedule('sphere-deadlines');
    exception when others then null;
    end;
    perform cron.schedule('sphere-deadlines', '*/10 * * * *', 'select public.sp_work_tick()');
  end if;
exception when others then
  raise notice 'Could not schedule the deadline check: % — the app will still check on open.', sqlerrm;
end $$;

-- Done. You should see "Success. No rows returned".
