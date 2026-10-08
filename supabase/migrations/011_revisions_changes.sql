-- =====================================================================
-- SPHERE — PART 11: REVISIONS + CHANGE REQUESTS
-- Run in: Supabase → SQL Editor → + → paste → Run.  Safe to run again.
-- Needs 001, 002, 007, 008, 010 first. Adds tables/columns/functions; deletes nothing.
--
--   sp_revisions        every revision of a project (#1, #2 …): notes, free / paid,
--                       status awaiting_payment → open → delivered (next preview)
--   sp_change_requests  client asks for new work: details, extra price, extra time,
--                       files/link → editor accepts / rejects → (pays) → applied.
--                       Old deadline / old price are kept on the request.
--   sp_extra_payments   extra money in a project (paid revision, change price).
--                       Paid only by the server (Razorpay Edge Function) or by an
--                       admin confirming a UPI payment. Split is admins-only:
--                       revision fee → 100 % to the editor.
--   sp_project_work     + original_due_at (first deadline) — current deadline stays in due_at
--   sp_jobs             + extra_requirements (accepted changes), extra_amount (paid extras)
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1) Settings + new columns
-- ---------------------------------------------------------------------
insert into public.sp_settings (key, value) select 'revision_hours', '24' where not exists (select 1 from public.sp_settings where key = 'revision_hours');

alter table public.sp_project_work add column if not exists original_due_at timestamptz;
update public.sp_project_work set original_due_at = due_at - make_interval(hours => extended_hours) where original_due_at is null;

alter table public.sp_jobs add column if not exists extra_requirements text;
alter table public.sp_jobs add column if not exists extra_amount numeric(12,2) not null default 0;

-- ---------------------------------------------------------------------
-- 2) Tables
-- ---------------------------------------------------------------------
create table if not exists public.sp_extra_payments (
  id          uuid primary key default gen_random_uuid(),
  job_id      uuid not null,
  client_id   uuid not null,
  editor_id   uuid not null,
  kind        text not null,                 -- revision | change
  ref_id      uuid not null,                 -- sp_revisions.id or sp_change_requests.id
  amount      numeric(12,2) not null,
  status      text not null default 'pending',   -- pending | paid | failed | cancelled
  method      text,                          -- razorpay | upi
  order_id    text,
  payment_id  text,
  utr         text,
  created_at  timestamptz not null default now(),
  paid_at     timestamptz
);
alter table public.sp_extra_payments drop constraint if exists sp_extra_chk;
alter table public.sp_extra_payments add  constraint sp_extra_chk check (kind in ('revision', 'change') and status in ('pending', 'paid', 'failed', 'cancelled') and amount > 0);
create unique index if not exists sp_extra_ref_uq on public.sp_extra_payments (kind, ref_id);

create table if not exists public.sp_extra_splits (
  extra_id      uuid primary key,
  editor_share  numeric(12,2) not null,
  sphere_share  numeric(12,2) not null,
  created_at    timestamptz not null default now()
);

create table if not exists public.sp_revisions (
  id               uuid primary key default gen_random_uuid(),
  job_id           uuid not null,
  number           int not null,
  requested_by     uuid not null,
  notes            text not null,
  preview_version  int,
  is_paid          boolean not null default false,
  fee              numeric(12,2) not null default 0,
  status           text not null default 'open',   -- awaiting_payment | open | delivered | cancelled
  old_due_at       timestamptz,
  new_due_at       timestamptz,
  delivered_version int,
  created_at       timestamptz not null default now(),
  opened_at        timestamptz,
  delivered_at     timestamptz
);
alter table public.sp_revisions drop constraint if exists sp_rev_chk;
alter table public.sp_revisions add  constraint sp_rev_chk check (status in ('awaiting_payment', 'open', 'delivered', 'cancelled') and char_length(notes) between 5 and 2000);
create unique index if not exists sp_rev_num_uq on public.sp_revisions (job_id, number);

create table if not exists public.sp_change_requests (
  id               uuid primary key default gen_random_uuid(),
  job_id           uuid not null,
  requested_by     uuid not null,
  details          text not null,
  extra_price      numeric(12,2) not null default 0,
  extra_hours      int not null default 0,
  link             text,
  file_ids         uuid[] not null default '{}',
  status           text not null default 'pending',  -- pending | rejected | accepted_awaiting_payment | applied | cancelled
  editor_note      text,
  old_due_at       timestamptz,
  new_due_at       timestamptz,
  old_extra_amount numeric(12,2),
  new_extra_amount numeric(12,2),
  old_requirements text,
  created_at       timestamptz not null default now(),
  decided_at       timestamptz,
  applied_at       timestamptz
);
alter table public.sp_change_requests drop constraint if exists sp_cr_chk;
alter table public.sp_change_requests add  constraint sp_cr_chk check (
  status in ('pending', 'rejected', 'accepted_awaiting_payment', 'applied', 'cancelled')
  and extra_price >= 0 and extra_price <= 1000000 and extra_hours between 0 and 336
  and char_length(details) between 10 and 1500 and (link is null or char_length(link) <= 500));

-- read rules: only the two people in the project + admins; nobody writes from the app
alter table public.sp_extra_payments  enable row level security;
alter table public.sp_extra_splits    enable row level security;
alter table public.sp_revisions       enable row level security;
alter table public.sp_change_requests enable row level security;
drop policy if exists sp_extra_read on public.sp_extra_payments;
create policy sp_extra_read on public.sp_extra_payments for select to authenticated using (public.sp_files_party(job_id::text));
drop policy if exists sp_extra_splits_admin on public.sp_extra_splits;
create policy sp_extra_splits_admin on public.sp_extra_splits for select to authenticated using (public.sp_core_has_role('ADMIN'));
drop policy if exists sp_rev_read on public.sp_revisions;
create policy sp_rev_read on public.sp_revisions for select to authenticated using (public.sp_files_party(job_id::text));
drop policy if exists sp_cr_read on public.sp_change_requests;
create policy sp_cr_read on public.sp_change_requests for select to authenticated using (public.sp_files_party(job_id::text));
revoke insert, update, delete on public.sp_extra_payments, public.sp_extra_splits, public.sp_revisions, public.sp_change_requests from anon, authenticated;
grant select on public.sp_extra_payments, public.sp_extra_splits, public.sp_revisions, public.sp_change_requests to authenticated;

-- ---------------------------------------------------------------------
-- 3) Internal helpers
-- ---------------------------------------------------------------------
create or replace function public.sp_clean_text(p text, p_max int)
returns text language sql stable security definer set search_path = public as $$
  select nullif(left((select (public.sp_mod_mask(btrim(coalesce(p, '')))).masked), p_max), '');
$$;

-- move the work clock to a new deadline and put the project back to "editor working"
create or replace function public.sp_work_set_due(p_job uuid, p_due timestamptz)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.sp_work_start(p_job, false);
  update public.sp_project_work
     set original_due_at = coalesce(original_due_at, due_at), due_at = p_due, phase = 'active',
         is_late = false, late_since = null, reminded_at = null, due_notified_at = null, late_notified_at = null,
         pending_extension_hours = null, updated_at = now()
   where job_id = p_job and phase in ('active', 'preview');
end $$;

-- a revision becomes active: editor gets revision_hours to send the next preview
create or replace function public.sp_rev_open(p_rev uuid)
returns void language plpgsql security definer set search_path = public as $$
declare r record; j record; olddue timestamptz; newdue timestamptz; hrs int := greatest(1, public.sp_setting_int('revision_hours', 24));
begin
  select * into r from public.sp_revisions where id = p_rev for update;
  select * into j from public.sp_jobs where id = r.job_id;
  select due_at into olddue from public.sp_project_work where job_id = r.job_id;
  newdue := now() + make_interval(hours => hrs);
  perform public.sp_work_set_due(r.job_id, newdue);
  update public.sp_revisions set status = 'open', opened_at = now(), old_due_at = olddue, new_due_at = newdue where id = r.id;
  perform public.sp_work_event(r.job_id, r.requested_by, 'revision_open', 'Revision #' || r.number || ' started', 'Next preview due ' || public.sp_ist(newdue));
  perform public.sp_work_notify(j.assigned_editor, 'Revision #' || r.number || ' requested 🔁',
    'The client wants changes in "' || public.sp_work_label(r.job_id) || '": ' || left(r.notes, 140) || ' — send the new preview by ' || public.sp_ist(newdue) || '.');
end $$;

-- an accepted change request takes effect (old values kept on the request)
create or replace function public.sp_cr_apply(p_cr uuid)
returns void language plpgsql security definer set search_path = public as $$
declare c record; j record; w record; newdue timestamptz; stamp text;
begin
  select * into c from public.sp_change_requests where id = p_cr for update;
  select * into j from public.sp_jobs where id = c.job_id for update;
  perform public.sp_work_start(c.job_id, false);
  select * into w from public.sp_project_work where job_id = c.job_id;
  stamp := to_char(now() at time zone 'Asia/Kolkata', 'DD Mon YYYY');
  update public.sp_jobs
     set extra_requirements = concat_ws(E'\n\n', nullif(extra_requirements, ''), '[' || stamp || '] ' || c.details),
         extra_amount = coalesce(extra_amount, 0) + c.extra_price
   where id = c.job_id;
  if c.extra_hours > 0 then
    newdue := greatest(w.due_at, now()) + make_interval(hours => c.extra_hours);
  else
    newdue := w.due_at;
  end if;
  perform public.sp_work_set_due(c.job_id, newdue);
  update public.sp_change_requests
     set status = 'applied', applied_at = now(), old_due_at = w.due_at, new_due_at = newdue,
         old_extra_amount = coalesce(j.extra_amount, 0), new_extra_amount = coalesce(j.extra_amount, 0) + c.extra_price,
         old_requirements = j.extra_requirements
   where id = c.id;
  perform public.sp_work_event(c.job_id, null, 'change_applied', 'Change request applied',
    'Deadline ' || public.sp_ist(w.due_at) || ' → ' || public.sp_ist(newdue) || case when c.extra_price > 0 then ' · +₹' || c.extra_price else '' end);
  perform public.sp_work_notify(j.client_id, 'Change applied ✅', 'Your change for "' || public.sp_work_label(c.job_id) || '" is now part of the project. New deadline: ' || public.sp_ist(newdue) || '.');
  perform public.sp_work_notify(j.assigned_editor, 'Change applied ✅', 'Start the new work for "' || public.sp_work_label(c.job_id) || '". New deadline: ' || public.sp_ist(newdue) || '.');
end $$;

-- create the extra payment the client has to make (split stored for admins only)
create or replace function public.sp_extra_create(p_job uuid, p_kind text, p_ref uuid, p_amount numeric)
returns uuid language plpgsql security definer set search_path = public as $$
declare j record; xid uuid; pct numeric; ed numeric;
begin
  select * into j from public.sp_jobs where id = p_job;
  insert into public.sp_extra_payments (job_id, client_id, editor_id, kind, ref_id, amount)
  values (p_job, j.client_id, j.assigned_editor, p_kind, p_ref, p_amount)
  on conflict (kind, ref_id) do update set amount = excluded.amount
  returning id into xid;
  if p_kind = 'revision' then
    ed := p_amount;                                   -- the full revision fee goes to the editor
  else
    pct := coalesce((select nullif(regexp_replace(value::text, '[^0-9.]', '', 'g'), '')::numeric from public.sp_settings where key = 'platform_fee_percent'), 5);
    ed := p_amount - round(p_amount * pct / 100, 2);
  end if;
  insert into public.sp_extra_splits (extra_id, editor_share, sphere_share) values (xid, ed, p_amount - ed)
  on conflict (extra_id) do update set editor_share = excluded.editor_share, sphere_share = excluded.sphere_share;
  return xid;
end $$;

-- the trigger: when a new preview arrives, the open revision is delivered
create or replace function public.sp_rev_on_preview()
returns trigger language plpgsql security definer set search_path = public as $$
declare v int;
begin
  if NEW.phase = 'preview' and (OLD.phase is distinct from 'preview' or NEW.preview_at is distinct from OLD.preview_at) then
    select max(version) into v from public.sp_project_files where job_id = NEW.job_id and kind = 'preview' and status = 'ready';
    update public.sp_revisions set status = 'delivered', delivered_at = now(), delivered_version = v
     where job_id = NEW.job_id and status = 'open';
    if found then
      perform public.sp_work_event(NEW.job_id, NEW.editor_id, 'revision_delivered', 'Revision delivered' || coalesce(' as preview v' || v, ''), null);
    end if;
  end if;
  return null;
end $$;
drop trigger if exists sp_rev_on_preview on public.sp_project_work;
create trigger sp_rev_on_preview after update of phase, preview_at on public.sp_project_work
  for each row execute function public.sp_rev_on_preview();

revoke all on function public.sp_clean_text(text, int), public.sp_work_set_due(uuid, timestamptz), public.sp_rev_open(uuid),
              public.sp_cr_apply(uuid), public.sp_extra_create(uuid, text, uuid, numeric) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 4) Revisions (client)
-- ---------------------------------------------------------------------
create or replace function public.sp_rev_request(p_job uuid, p_notes text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare j record; w record; n int; free int := public.sp_setting_int('free_revisions', 3);
        fee numeric := greatest(1, public.sp_setting_int('revision_fee', 50)); notes text; rid uuid; pv int; xid uuid;
begin
  select * into j from public.sp_jobs where id = p_job for update;
  if j.id is null then raise exception 'Project not found.'; end if;
  if auth.uid() is distinct from j.client_id then raise exception 'Only the client of this project can ask for a revision.'; end if;
  if j.status is distinct from 'in-progress' then raise exception 'Revisions can be asked while the project is in progress.'; end if;
  select * into w from public.sp_project_work where job_id = p_job;
  if w.job_id is null or w.phase <> 'preview' then raise exception 'Ask for a revision after the editor sends a preview.'; end if;
  if exists (select 1 from public.sp_revisions where job_id = p_job and status in ('open', 'awaiting_payment')) then
    raise exception 'A revision is already waiting. Wait for the next preview first.';
  end if;
  notes := public.sp_clean_text(p_notes, 2000);
  if notes is null or char_length(notes) < 5 then raise exception 'Write what should be changed.'; end if;
  select coalesce(max(number), 0) + 1 into n from public.sp_revisions where job_id = p_job and status <> 'cancelled';
  select max(version) into pv from public.sp_project_files where job_id = p_job and kind = 'preview' and status = 'ready';
  insert into public.sp_revisions (job_id, number, requested_by, notes, preview_version, is_paid, fee, status)
  values (p_job, n, auth.uid(), notes, pv, n > free, case when n > free then fee else 0 end,
          case when n > free then 'awaiting_payment' else 'open' end)
  returning id into rid;
  if n > free then
    xid := public.sp_extra_create(p_job, 'revision', rid, fee);
    perform public.sp_work_event(p_job, auth.uid(), 'revision_requested', 'Revision #' || n || ' asked — ₹' || fee || ' to pay', left(notes, 200));
    return jsonb_build_object('id', rid, 'number', n, 'needs_payment', true, 'amount', fee, 'extra_id', xid);
  end if;
  perform public.sp_work_event(p_job, auth.uid(), 'revision_requested', 'Revision #' || n || ' asked (free)', left(notes, 200));
  perform public.sp_rev_open(rid);
  return jsonb_build_object('id', rid, 'number', n, 'needs_payment', false, 'free_left', greatest(0, free - n));
end $$;

create or replace function public.sp_rev_cancel(p_rev uuid)
returns void language plpgsql security definer set search_path = public as $$
declare r record;
begin
  select * into r from public.sp_revisions where id = p_rev for update;
  if r.id is null or r.requested_by is distinct from auth.uid() then raise exception 'Not your revision.'; end if;
  if r.status <> 'awaiting_payment' then raise exception 'Only an unpaid revision can be cancelled.'; end if;
  update public.sp_revisions set status = 'cancelled' where id = r.id;
  update public.sp_extra_payments set status = 'cancelled' where kind = 'revision' and ref_id = r.id and status in ('pending', 'failed');
  perform public.sp_work_event(r.job_id, auth.uid(), 'revision_cancelled', 'Paid revision #' || r.number || ' cancelled', null);
end $$;

-- ---------------------------------------------------------------------
-- 5) Change requests
-- ---------------------------------------------------------------------
create or replace function public.sp_cr_create(p_job uuid, p_details text, p_extra_price numeric, p_extra_hours int, p_link text, p_file_ids uuid[])
returns jsonb language plpgsql security definer set search_path = public as $$
declare j record; details text; link text := nullif(btrim(coalesce(p_link, '')), ''); cid uuid; files uuid[];
begin
  select * into j from public.sp_jobs where id = p_job;
  if j.id is null then raise exception 'Project not found.'; end if;
  if auth.uid() is distinct from j.client_id then raise exception 'Only the client of this project can ask for a change.'; end if;
  if j.status is distinct from 'in-progress' then raise exception 'Changes can be asked while the project is in progress.'; end if;
  if exists (select 1 from public.sp_change_requests where job_id = p_job and status in ('pending', 'accepted_awaiting_payment')) then
    raise exception 'A change request is already waiting. Wait for it to finish first.';
  end if;
  details := public.sp_clean_text(p_details, 1500);
  if details is null or char_length(details) < 10 then raise exception 'Describe the change (at least 10 letters).'; end if;
  if coalesce(p_extra_price, 0) < 0 or coalesce(p_extra_price, 0) > 1000000 then raise exception 'Check the extra price.'; end if;
  if coalesce(p_extra_hours, 0) < 0 or coalesce(p_extra_hours, 0) > 336 then raise exception 'Extra time must be 0–336 hours.'; end if;
  if link is not null and (link !~* '^https://\S+$' or (select (public.sp_mod_mask(link)).hard)) then
    raise exception 'Use a Google Drive, Dropbox, WeTransfer, OneDrive or YouTube link.';
  end if;
  select coalesce(array_agg(id), '{}') into files from public.sp_project_files
   where id = any(coalesce(p_file_ids, '{}')) and job_id = p_job and kind = 'client_file' and status = 'ready';
  insert into public.sp_change_requests (job_id, requested_by, details, extra_price, extra_hours, link, file_ids)
  values (p_job, auth.uid(), details, round(coalesce(p_extra_price, 0), 2), coalesce(p_extra_hours, 0), link, files)
  returning id into cid;
  perform public.sp_work_event(p_job, auth.uid(), 'change_requested', 'Change request sent',
    left(details, 160) || case when p_extra_price > 0 then ' · +₹' || round(p_extra_price, 2) else '' end || case when p_extra_hours > 0 then ' · +' || p_extra_hours || ' h' else '' end);
  perform public.sp_work_notify(j.assigned_editor, 'Change request 📝', 'The client asked for a change in "' || public.sp_work_label(p_job) || '"'
    || case when p_extra_price > 0 then ' and offers ₹' || round(p_extra_price, 2) || ' extra' else '' end || '. Open the project to accept or reject.');
  return jsonb_build_object('id', cid);
end $$;

create or replace function public.sp_cr_answer(p_cr uuid, p_accept boolean, p_note text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c record; j record; note text; xid uuid;
begin
  select * into c from public.sp_change_requests where id = p_cr for update;
  if c.id is null then raise exception 'Not found.'; end if;
  select * into j from public.sp_jobs where id = c.job_id;
  if auth.uid() is distinct from j.assigned_editor then raise exception 'Only the editor of this project can answer.'; end if;
  if c.status <> 'pending' then raise exception 'This request was already answered.'; end if;
  note := public.sp_clean_text(p_note, 300);
  if not p_accept then
    update public.sp_change_requests set status = 'rejected', editor_note = note, decided_at = now() where id = c.id;
    perform public.sp_work_event(c.job_id, auth.uid(), 'change_rejected', 'Editor rejected the change', note);
    perform public.sp_work_notify(j.client_id, 'Change request rejected', 'The editor could not take the change for "' || public.sp_work_label(c.job_id) || '"' || coalesce(': ' || note, '.'));
    return jsonb_build_object('status', 'rejected');
  end if;
  update public.sp_change_requests set editor_note = note, decided_at = now() where id = c.id;
  perform public.sp_work_event(c.job_id, auth.uid(), 'change_accepted', 'Editor accepted the change', note);
  if c.extra_price > 0 then
    update public.sp_change_requests set status = 'accepted_awaiting_payment' where id = c.id;
    xid := public.sp_extra_create(c.job_id, 'change', c.id, c.extra_price);
    perform public.sp_work_notify(j.client_id, 'Change accepted — pay ₹' || c.extra_price || ' 💳',
      'The editor accepted your change for "' || public.sp_work_label(c.job_id) || '". Pay ₹' || c.extra_price || ' to start it.');
    return jsonb_build_object('status', 'accepted_awaiting_payment', 'extra_id', xid);
  end if;
  perform public.sp_cr_apply(c.id);
  return jsonb_build_object('status', 'applied');
end $$;

create or replace function public.sp_cr_cancel(p_cr uuid)
returns void language plpgsql security definer set search_path = public as $$
declare c record;
begin
  select * into c from public.sp_change_requests where id = p_cr for update;
  if c.id is null or c.requested_by is distinct from auth.uid() then raise exception 'Not your request.'; end if;
  if c.status not in ('pending', 'accepted_awaiting_payment') then raise exception 'This request can no longer be cancelled.'; end if;
  update public.sp_change_requests set status = 'cancelled', decided_at = coalesce(decided_at, now()) where id = c.id;
  update public.sp_extra_payments set status = 'cancelled' where kind = 'change' and ref_id = c.id and status in ('pending', 'failed');
  perform public.sp_work_event(c.job_id, auth.uid(), 'change_cancelled', 'Client cancelled the change request', null);
end $$;

-- ---------------------------------------------------------------------
-- 6) Extra payments: paid only by the server (Razorpay) or an admin (UPI)
-- ---------------------------------------------------------------------
create or replace function public.sp_extra_mark_paid(p_extra uuid, p_method text, p_payment text, p_order text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  claims jsonb := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb);
  is_server boolean := coalesce(claims->>'role', current_setting('request.jwt.claim.role', true), '') = 'service_role';
  x record;
begin
  if not is_server and not public.sp_core_has_role('ADMIN') then raise exception 'Not allowed.'; end if;
  select * into x from public.sp_extra_payments where id = p_extra for update;
  if x.id is null then raise exception 'Payment not found.'; end if;
  if x.status = 'paid' then return jsonb_build_object('status', 'paid', 'already', true); end if;
  if x.status = 'cancelled' then raise exception 'This payment was cancelled.'; end if;
  update public.sp_extra_payments set status = 'paid', paid_at = now(), method = coalesce(p_method, method),
         payment_id = coalesce(left(p_payment, 80), payment_id), order_id = coalesce(left(p_order, 80), order_id) where id = x.id;
  perform public.sp_work_event(x.job_id, x.client_id, 'extra_paid', 'Paid ₹' || x.amount || case when x.kind = 'revision' then ' for a revision' else ' for a change' end, null);
  if x.kind = 'revision' then
    perform public.sp_rev_open(x.ref_id);
  else
    perform public.sp_cr_apply(x.ref_id);
  end if;
  return jsonb_build_object('status', 'paid');
end $$;

-- UPI fallback: the client types the UPI transaction ID, an admin confirms it
create or replace function public.sp_extra_submit_utr(p_extra uuid, p_utr text)
returns void language plpgsql security definer set search_path = public as $$
declare x record; v_utr text := upper(regexp_replace(coalesce(p_utr, ''), '\s', '', 'g'));
begin
  select * into x from public.sp_extra_payments where id = p_extra for update;
  if x.id is null or x.client_id is distinct from auth.uid() then raise exception 'Not your payment.'; end if;
  if x.status not in ('pending', 'failed') then raise exception 'This payment is already %.', x.status; end if;
  if v_utr !~ '^[A-Z0-9]{10,22}$' then raise exception 'Enter the UPI transaction ID (usually 12 digits).'; end if;
  update public.sp_extra_payments set utr = v_utr, method = 'upi', status = 'pending' where id = x.id;
  insert into public.sp_notifications (user_id, title, body)
  select id, 'Extra payment to check 💳', 'A client says they paid ₹' || x.amount || ' by UPI. Open Admin Panel → Extra payments.'
  from public.profiles where upper(btrim(role)) = 'ADMIN';
end $$;

create or replace function public.sp_extra_admin(p_extra uuid, p_action text, p_pin text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare x record;
begin
  if not public.sp_core_has_role('ADMIN') then raise exception 'Admins only'; end if;
  perform public.sp_admin_check_pin(p_pin := p_pin);
  select * into x from public.sp_extra_payments where id = p_extra;
  if p_action = 'confirm' then
    return public.sp_extra_mark_paid(p_extra, 'upi', x.utr, null);
  elsif p_action = 'reject' then
    update public.sp_extra_payments set status = 'failed', utr = null where id = p_extra and status = 'pending';
    insert into public.sp_notifications (user_id, title, body) values (x.client_id, 'Payment not found ⚠️',
      'We could not find your UPI payment of ₹' || x.amount || '. Please check the transaction ID and try again.');
    return jsonb_build_object('status', 'failed');
  end if;
  raise exception 'Unknown action.';
end $$;

revoke all on function public.sp_rev_request(uuid, text), public.sp_rev_cancel(uuid),
              public.sp_cr_create(uuid, text, numeric, int, text, uuid[]), public.sp_cr_answer(uuid, boolean, text), public.sp_cr_cancel(uuid),
              public.sp_extra_mark_paid(uuid, text, text, text), public.sp_extra_submit_utr(uuid, text), public.sp_extra_admin(uuid, text, text) from public, anon;
grant execute on function public.sp_rev_request(uuid, text), public.sp_rev_cancel(uuid),
              public.sp_cr_create(uuid, text, numeric, int, text, uuid[]), public.sp_cr_answer(uuid, boolean, text), public.sp_cr_cancel(uuid),
              public.sp_extra_mark_paid(uuid, text, text, text), public.sp_extra_submit_utr(uuid, text), public.sp_extra_admin(uuid, text, text) to authenticated;
grant execute on function public.sp_extra_mark_paid(uuid, text, text, text) to service_role;

insert into public.sp_schema_versions (version, name)
values ('011', 'Revisions + change requests (3 free, paid revisions, change requests, extra payments, deadline history)')
on conflict (version) do update set applied_at = now();

commit;

-- Done. You should see "Success. No rows returned".
-- Optional: deploy the Edge Function sphere-extra-payment so clients can pay ₹50 / extras by Razorpay.
