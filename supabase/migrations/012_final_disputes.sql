-- =====================================================================
-- SPHERE — PART 12: FINAL APPROVAL + DISPUTES + REFUNDS
-- Run in: Supabase → SQL Editor → + → paste → Run.  Safe to run again.
-- Needs 002, 007, 008, 009, 010, 011 first. Adds tables/columns/functions; deletes nothing.
-- The existing Edge Functions release-payout and refund-payment keep doing the money part.
--
--   Editor  "Submit for final approval": final watermarked preview + the clean final
--           file link (hidden from the client until payment is released)
--           → job "delivered", review_state awaiting_client, 10-hour window.
--   Client  Release payment (existing release-payout) → project closed for complaints,
--           final file unlocked, editor payout starts (+ extras payout item)
--      or   I am not satisfied (reason required) → dispute with a full case file.
--   No answer in 10 hours → review_state team_review (Sphere team decides).
--   Sphere team: release to editor / full refund / send back to editor — never AI alone.
--   sp_disputes  one case per review: reason, AI note (advice only), decision, case snapshot
--   sp_refunds   approved → processing → refunded / failed (full refunds)
--   sp_payout_items  editor money still to pay after release (extras from Part 11)
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1) Settings + columns
-- ---------------------------------------------------------------------
insert into public.sp_settings (key, value) select 'final_review_hours', '10' where not exists (select 1 from public.sp_settings where key = 'final_review_hours');

alter table public.sp_jobs add column if not exists review_state text not null default 'none';
alter table public.sp_jobs add column if not exists final_submitted_at timestamptz;
alter table public.sp_jobs add column if not exists decision_due_at timestamptz;
-- (no check constraint: values are set only by the functions below)

-- ---------------------------------------------------------------------
-- 2) Tables
-- ---------------------------------------------------------------------
create table if not exists public.sp_final_files (
  job_id          uuid primary key,
  preview_file_id uuid,
  preview_version int,
  final_link      text not null,
  note            text,
  submitted_by    uuid not null,
  submitted_at    timestamptz not null default now()
);

create table if not exists public.sp_disputes (
  id             uuid primary key default gen_random_uuid(),
  job_id         uuid not null,
  kind           text not null,                 -- dispute (client not satisfied) | no_response (10 h passed)
  opened_by      uuid,
  category       text,                          -- quality | not_as_asked | not_delivered | late | missing | other
  details        text,
  status         text not null default 'open',  -- open | resolved_release | resolved_refund | resolved_redo | withdrawn
  ai_category    text,
  ai_summary     text,
  ai_checked_at  timestamptz,
  decision_note  text,
  decided_by     uuid,
  decided_at     timestamptz,
  snapshot       jsonb not null default '{}'::jsonb,
  created_at     timestamptz not null default now()
);
alter table public.sp_disputes drop constraint if exists sp_disputes_chk;
alter table public.sp_disputes add  constraint sp_disputes_chk check (kind in ('dispute', 'no_response')
  and status in ('open', 'resolved_release', 'resolved_refund', 'resolved_redo', 'withdrawn')
  and (details is null or char_length(details) <= 2000));
create unique index if not exists sp_disputes_one_open on public.sp_disputes (job_id) where status = 'open';

create table if not exists public.sp_refunds (
  id          uuid primary key default gen_random_uuid(),
  job_id      uuid not null,
  dispute_id  uuid,
  amount      numeric(12,2) not null,
  kind        text not null default 'full',
  status      text not null default 'approved',   -- approved | processing | refunded | failed | rejected
  reason      text,
  decided_by  uuid,
  error       text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
alter table public.sp_refunds drop constraint if exists sp_refunds_chk;
alter table public.sp_refunds add  constraint sp_refunds_chk check (kind in ('full') and status in ('approved', 'processing', 'refunded', 'failed', 'rejected'));
create unique index if not exists sp_refunds_one_active on public.sp_refunds (job_id) where status in ('approved', 'processing', 'refunded');

create table if not exists public.sp_payout_items (
  id          uuid primary key default gen_random_uuid(),
  job_id      uuid not null,
  editor_id   uuid not null,
  kind        text not null,                    -- extras (paid revisions / changes)
  amount      numeric(12,2) not null,
  status      text not null default 'pending',  -- pending | paid
  paid_at     timestamptz,
  note        text,
  created_at  timestamptz not null default now()
);
create unique index if not exists sp_payout_items_uq on public.sp_payout_items (job_id, kind);

-- read rules
alter table public.sp_final_files  enable row level security;
alter table public.sp_disputes     enable row level security;
alter table public.sp_refunds      enable row level security;
alter table public.sp_payout_items enable row level security;
drop policy if exists sp_final_read on public.sp_final_files;
create policy sp_final_read on public.sp_final_files for select to authenticated using (
  public.sp_core_has_role('ADMIN')
  or exists (select 1 from public.sp_jobs j where j.id = job_id and
             (j.assigned_editor = auth.uid() or (j.client_id = auth.uid() and j.status in ('approved', 'closed')))));
drop policy if exists sp_disputes_read on public.sp_disputes;
create policy sp_disputes_read on public.sp_disputes for select to authenticated using (public.sp_files_party(job_id::text));
drop policy if exists sp_refunds_read on public.sp_refunds;
create policy sp_refunds_read on public.sp_refunds for select to authenticated using (public.sp_files_party(job_id::text));
drop policy if exists sp_payout_items_read on public.sp_payout_items;
create policy sp_payout_items_read on public.sp_payout_items for select to authenticated using (editor_id = auth.uid() or public.sp_core_has_role('ADMIN'));
revoke insert, update, delete on public.sp_final_files, public.sp_disputes, public.sp_refunds, public.sp_payout_items from anon, authenticated;
grant select on public.sp_final_files, public.sp_disputes, public.sp_refunds, public.sp_payout_items to authenticated;

-- ---------------------------------------------------------------------
-- 3) Case file: everything about a project in one place (kept on the dispute)
-- ---------------------------------------------------------------------
create or replace function public.sp_case_snapshot(p_job uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'taken_at', now(),
    'job', (select jsonb_build_object('title', j.title, 'category', j.category, 'description', j.description, 'style', j.style_notes,
              'references', j.reference_links, 'length', j.video_length, 'format', j.video_format, 'revisions_expected', j.revisions_expected,
              'accepted_changes', j.extra_requirements, 'budget', j.budget, 'price_paid', j.locked_amount, 'extra_paid', j.extra_amount,
              'posted', j.created_at, 'status', j.status, 'client_id', j.client_id, 'editor_id', j.assigned_editor)
            from public.sp_jobs j where j.id = p_job),
    'work', (select to_jsonb(w) - 'reminded_at' - 'due_notified_at' - 'late_notified_at' from public.sp_project_work w where w.job_id = p_job),
    'final', (select jsonb_build_object('preview_version', f.preview_version, 'note', f.note, 'submitted_at', f.submitted_at) from public.sp_final_files f where f.job_id = p_job),
    'files', coalesce((select jsonb_agg(jsonb_build_object('kind', f.kind, 'name', f.file_name, 'source', f.source, 'version', f.version,
              'size', f.size_bytes, 'status', f.status, 'link', f.external_url, 'path', f.storage_path, 'note', f.note, 'at', f.created_at) order by f.created_at)
              from public.sp_project_files f where f.job_id = p_job), '[]'::jsonb),
    'revisions', coalesce((select jsonb_agg(to_jsonb(r) order by r.number) from public.sp_revisions r where r.job_id = p_job), '[]'::jsonb),
    'changes', coalesce((select jsonb_agg(to_jsonb(c) order by c.created_at) from public.sp_change_requests c where c.job_id = p_job), '[]'::jsonb),
    'extras', coalesce((select jsonb_agg(jsonb_build_object('kind', x.kind, 'amount', x.amount, 'status', x.status, 'paid_at', x.paid_at) order by x.created_at)
              from public.sp_extra_payments x where x.job_id = p_job), '[]'::jsonb),
    'payment', (select jsonb_build_object('amount', p.amount, 'status', p.status, 'paid_at', p.paid_at) from public.sp_payments p where p.job_id = p_job),
    'timeline', coalesce((select jsonb_agg(jsonb_build_object('at', e.at, 'kind', e.kind, 'title', e.title, 'details', e.details) order by e.at)
              from public.sp_project_events e where e.job_id = p_job), '[]'::jsonb),
    'chat', coalesce((select jsonb_agg(x.obj order by x.at) from (
              select m.created_at as at,
                     jsonb_build_object('at', m.created_at, 'from', case when m.sender_id = j.client_id then 'client' else 'editor' end,
                                        'text', m."text", 'media', m.media_type, 'moderation', m.mod_status) as obj
              from public.sp_messages m join public.sp_jobs j on j.id = p_job
              where (m.sender_id = j.client_id and m.receiver_id = j.assigned_editor) or (m.sender_id = j.assigned_editor and m.receiver_id = j.client_id)
              order by m.created_at desc limit 300) x), '[]'::jsonb)
  );
$$;
revoke all on function public.sp_case_snapshot(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 4) Money moves come from the Edge Functions → follow them here
-- ---------------------------------------------------------------------
create or replace function public.sp_final_job_before()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if NEW.status is distinct from OLD.status then
    if NEW.status = 'approved' then
      NEW.review_state := 'released';
      NEW.delivery_link := coalesce(NEW.delivery_link, (select final_link from public.sp_final_files where job_id = NEW.id));
    elsif NEW.status = 'refunded' then
      NEW.review_state := 'refunded';
    end if;
  end if;
  return NEW;
end $$;
drop trigger if exists sp_final_job_before on public.sp_jobs;
create trigger sp_final_job_before before update of status on public.sp_jobs
  for each row execute function public.sp_final_job_before();

create or replace function public.sp_final_job_after()
returns trigger language plpgsql security definer set search_path = public as $$
declare extras numeric;
begin
  if NEW.status is not distinct from OLD.status then return null; end if;
  if NEW.status = 'approved' then
    update public.sp_disputes set status = case when kind = 'dispute' and decided_by is null then 'withdrawn' else 'resolved_release' end,
           decided_at = coalesce(decided_at, now()) where job_id = NEW.id and status = 'open';
    select coalesce(sum(s.editor_share), 0) into extras
      from public.sp_extra_payments x join public.sp_extra_splits s on s.extra_id = x.id where x.job_id = NEW.id and x.status = 'paid';
    if extras > 0 then
      insert into public.sp_payout_items (job_id, editor_id, kind, amount, note)
      values (NEW.id, NEW.assigned_editor, 'extras', extras, 'Paid revisions / change requests')
      on conflict (job_id, kind) do nothing;
    end if;
    perform public.sp_work_event(NEW.id, auth.uid(), 'released', 'Payment released — project complete', null);
    perform public.sp_work_notify(NEW.assigned_editor, 'Payment released 🎉', '"' || public.sp_work_label(NEW.id) || '" is approved. Your payout has started.');
  elsif NEW.status = 'refunded' then
    update public.sp_refunds set status = 'refunded', updated_at = now() where job_id = NEW.id and status in ('approved', 'processing');
    update public.sp_disputes set status = 'resolved_refund', decided_at = coalesce(decided_at, now()) where job_id = NEW.id and status = 'open';
    perform public.sp_work_event(NEW.id, auth.uid(), 'refund_done', 'Full refund sent to the client', null);
    perform public.sp_work_notify(NEW.client_id, 'Refund sent 💸', 'Your payment for "' || public.sp_work_label(NEW.id) || '" is refunded. It reaches your account in 5–7 working days.');
    perform public.sp_work_notify(NEW.assigned_editor, 'Project refunded', '"' || public.sp_work_label(NEW.id) || '" was refunded to the client by the Sphere team.');
  end if;
  return null;
end $$;
drop trigger if exists sp_final_job_after on public.sp_jobs;
create trigger sp_final_job_after after update of status on public.sp_jobs
  for each row execute function public.sp_final_job_after();

-- after release, complaints about that project are closed
create or replace function public.sp_final_report_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if NEW.job_id is not null and exists (select 1 from public.sp_jobs j where j.id = NEW.job_id and j.status in ('approved', 'closed')) then
    raise exception 'Payment for this project was released, so complaints are closed. For help, contact Sphere support.';
  end if;
  return NEW;
end $$;
drop trigger if exists sp_final_report_guard on public.sp_reports;
create trigger sp_final_report_guard before insert on public.sp_reports
  for each row execute function public.sp_final_report_guard();

-- ---------------------------------------------------------------------
-- 5) Editor: submit for final approval
-- ---------------------------------------------------------------------
create or replace function public.sp_final_submit(p_job uuid, p_preview uuid, p_final_link text, p_note text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare j record; f record; link text := btrim(coalesce(p_final_link, '')); hrs int := greatest(1, public.sp_setting_int('final_review_hours', 10)); due timestamptz;
begin
  select * into j from public.sp_jobs where id = p_job for update;
  if j.id is null then raise exception 'Project not found.'; end if;
  if auth.uid() is distinct from j.assigned_editor then raise exception 'Only the editor of this project can submit it.'; end if;
  if j.status is distinct from 'in-progress' then raise exception 'Only a project in progress can be submitted.'; end if;
  if exists (select 1 from public.sp_revisions where job_id = p_job and status in ('open', 'awaiting_payment')) then
    raise exception 'A revision is still open. Send its preview first.';
  end if;
  if exists (select 1 from public.sp_change_requests where job_id = p_job and status in ('pending', 'accepted_awaiting_payment')) then
    raise exception 'A change request is still waiting.';
  end if;
  select * into f from public.sp_project_files where id = p_preview and job_id = p_job and kind = 'preview' and status = 'ready';
  if f.id is null then raise exception 'Choose the final preview (send a watermarked preview first).'; end if;
  if link !~* '^https://\S+$' or char_length(link) > 500 or (select (public.sp_mod_mask(link)).hard) then
    raise exception 'Add the clean final video as a Google Drive, Dropbox, WeTransfer, OneDrive or Mega link.';
  end if;
  insert into public.sp_final_files (job_id, preview_file_id, preview_version, final_link, note, submitted_by)
  values (p_job, f.id, f.version, link, public.sp_clean_text(p_note, 500), auth.uid())
  on conflict (job_id) do update set preview_file_id = excluded.preview_file_id, preview_version = excluded.preview_version,
     final_link = excluded.final_link, note = excluded.note, submitted_at = now();
  due := now() + make_interval(hours => hrs);
  update public.sp_jobs set status = 'delivered', review_state = 'awaiting_client', final_submitted_at = now(), decision_due_at = due where id = p_job;
  perform public.sp_work_event(p_job, auth.uid(), 'final_submitted', 'Final preview v' || f.version || ' submitted for approval', 'Client decides by ' || public.sp_ist(due));
  perform public.sp_work_notify(j.client_id, 'Final video ready — your decision 🎬',
    'Watch the final preview of "' || public.sp_work_label(p_job) || '" and choose Release payment or Not satisfied within ' || hrs || ' hours.');
  return jsonb_build_object('decision_due_at', due, 'version', f.version);
end $$;

-- ---------------------------------------------------------------------
-- 6) Client: not satisfied → dispute (also: editor never delivered)
-- ---------------------------------------------------------------------
create or replace function public.sp_dispute_open(p_job uuid, p_category text, p_details text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare j record; w record; details text; did uuid; cat text := lower(coalesce(p_category, 'other'));
begin
  select * into j from public.sp_jobs where id = p_job for update;
  if j.id is null then raise exception 'Project not found.'; end if;
  if auth.uid() is distinct from j.client_id then raise exception 'Only the client of this project can open a dispute.'; end if;
  if j.status in ('approved', 'closed') then raise exception 'You already released the payment, so this project is closed.'; end if;
  if j.status = 'refunded' then raise exception 'This project was refunded.'; end if;
  if cat not in ('quality', 'not_as_asked', 'not_delivered', 'late', 'missing', 'other') then cat := 'other'; end if;
  if j.status = 'in-progress' then
    select * into w from public.sp_project_work where job_id = p_job;
    if not (w.job_id is not null and w.phase = 'active' and w.is_late and w.preview_at is null) then
      raise exception 'You can do this after the final preview — or if the editor is late and sent nothing.';
    end if;
    cat := 'not_delivered';
  elsif j.status is distinct from 'delivered' then
    raise exception 'This project is not waiting for your decision.';
  end if;
  if exists (select 1 from public.sp_disputes where job_id = p_job and status = 'open' and kind = 'dispute') then
    raise exception 'A dispute is already open. The Sphere team is reviewing it.';
  end if;
  details := public.sp_clean_text(p_details, 2000);
  if details is null or char_length(details) < 20 then raise exception 'Please explain the problem (at least 20 letters).'; end if;
  -- a "no response" review becomes this dispute
  update public.sp_disputes set status = 'withdrawn' where job_id = p_job and status = 'open' and kind = 'no_response';
  insert into public.sp_disputes (job_id, kind, opened_by, category, details, snapshot)
  values (p_job, 'dispute', auth.uid(), cat, details, public.sp_case_snapshot(p_job))
  returning id into did;
  update public.sp_jobs set review_state = 'disputed' where id = p_job;
  perform public.sp_work_event(p_job, auth.uid(), 'dispute_opened', 'Client is not satisfied — dispute opened', cat || ': ' || left(details, 160));
  perform public.sp_work_notify(j.assigned_editor, 'Client opened a dispute ⚖️',
    'The client is not satisfied with "' || public.sp_work_label(p_job) || '". The Sphere team will review the case and contact you.');
  insert into public.sp_notifications (user_id, title, body)
  select id, 'New dispute ⚖️', 'Project "' || public.sp_work_label(p_job) || '" — ' || cat || '. Open Admin Panel → Reviews & disputes.'
  from public.profiles where upper(btrim(role)) = 'ADMIN';
  return jsonb_build_object('id', did);
end $$;

-- ---------------------------------------------------------------------
-- 7) 10-hour window → Sphere team review
-- ---------------------------------------------------------------------
create or replace function public.sp_final_tick()
returns int language plpgsql security definer set search_path = public as $$
declare j record; n int := 0;
begin
  for j in select * from public.sp_jobs
           where status = 'delivered' and review_state = 'awaiting_client' and decision_due_at is not null and decision_due_at <= now()
           for update skip locked loop
    update public.sp_jobs set review_state = 'team_review' where id = j.id;
    insert into public.sp_disputes (job_id, kind, category, details, snapshot)
    values (j.id, 'no_response', 'other', 'The client did not decide within the review window.', public.sp_case_snapshot(j.id))
    on conflict do nothing;
    perform public.sp_work_event(j.id, null, 'team_review', 'No answer in time — sent to the Sphere team', null);
    perform public.sp_work_notify(j.client_id, 'Sphere team is reviewing ⏳',
      'You did not decide on "' || public.sp_work_label(j.id) || '" in time, so the Sphere team will review it. You can still release the payment or tell us what is wrong.');
    perform public.sp_work_notify(j.assigned_editor, 'Sent to Sphere review', 'The client did not answer in time for "' || public.sp_work_label(j.id) || '". The Sphere team is reviewing it.');
    insert into public.sp_notifications (user_id, title, body)
    select id, 'Project needs review ⏳', '"' || public.sp_work_label(j.id) || '" — the client did not answer in time. Admin Panel → Reviews & disputes.'
    from public.profiles where upper(btrim(role)) = 'ADMIN';
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.sp_final_tick() from public, anon;
grant execute on function public.sp_final_tick() to authenticated;

-- ---------------------------------------------------------------------
-- 8) Sphere team decisions (Admin PIN). Money moves through the Edge Functions.
-- ---------------------------------------------------------------------
create or replace function public.sp_case_decide(p_dispute uuid, p_decision text, p_note text, p_pin text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare d record; j record; note text := btrim(coalesce(p_note, '')); rid uuid; hrs int := greatest(1, public.sp_setting_int('revision_hours', 24));
begin
  if not public.sp_core_has_role('ADMIN') then raise exception 'Admins only'; end if;
  perform public.sp_admin_check_pin(p_pin := p_pin);
  select * into d from public.sp_disputes where id = p_dispute for update;
  if d.id is null then raise exception 'Case not found.'; end if;
  if d.status <> 'open' then raise exception 'This case is already closed.'; end if;
  if char_length(note) < 5 then raise exception 'Write a short decision note.'; end if;
  select * into j from public.sp_jobs where id = d.job_id for update;
  update public.sp_disputes set decision_note = left(note, 1000), decided_by = auth.uid(), decided_at = now() where id = d.id;

  if p_decision = 'release' then
    perform public.sp_work_event(j.id, auth.uid(), 'decision', 'Sphere team: release to the editor', note);
    return jsonb_build_object('next', 'release-payout', 'job_id', j.id);
  elsif p_decision = 'refund' then
    if j.status in ('approved', 'closed', 'refunded') then raise exception 'This project cannot be refunded now.'; end if;
    if not exists (select 1 from public.sp_payments where job_id = j.id and status = 'paid') then raise exception 'There is no paid payment to refund.'; end if;
    insert into public.sp_refunds (job_id, dispute_id, amount, reason, decided_by, status)
    values (j.id, d.id, (select amount from public.sp_payments where job_id = j.id), left(note, 500), auth.uid(), 'approved')
    returning id into rid;
    perform public.sp_work_event(j.id, auth.uid(), 'refund_approved', 'Sphere team approved a full refund', note);
    perform public.sp_work_notify(j.client_id, 'Refund approved ✅', 'The Sphere team approved a full refund for "' || public.sp_work_label(j.id) || '". It is being processed.');
    return jsonb_build_object('next', 'refund-payment', 'job_id', j.id, 'refund_id', rid);
  elsif p_decision = 'redo' then
    update public.sp_jobs set status = 'in-progress', review_state = 'redo', decision_due_at = null where id = j.id;
    update public.sp_project_work set phase = 'active', completed_at = null, due_at = now() + make_interval(hours => hrs),
           is_late = false, late_since = null, reminded_at = null, due_notified_at = null, late_notified_at = null, updated_at = now()
     where job_id = j.id;
    update public.sp_disputes set status = 'resolved_redo' where id = d.id;
    perform public.sp_work_event(j.id, auth.uid(), 'decision', 'Sphere team: editor must fix and resubmit', note);
    perform public.sp_work_notify(j.assigned_editor, 'Fix needed 🔧', 'Sphere team: ' || left(note, 160) || ' — resubmit "' || public.sp_work_label(j.id) || '" within ' || hrs || ' hours.');
    perform public.sp_work_notify(j.client_id, 'Sphere team decision', 'The editor will fix "' || public.sp_work_label(j.id) || '" and send it again.');
    return jsonb_build_object('next', null);
  end if;
  raise exception 'Unknown decision.';
end $$;

-- the refund call to Razorpay started / failed (admin)
create or replace function public.sp_refund_mark(p_refund uuid, p_status text, p_error text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.sp_core_has_role('ADMIN') then raise exception 'Admins only'; end if;
  if p_status not in ('processing', 'failed') then raise exception 'Bad status.'; end if;
  update public.sp_refunds set status = p_status, error = left(p_error, 300), updated_at = now()
   where id = p_refund and status in ('approved', 'processing', 'failed');
end $$;

-- AI may help sort a case; the decision always stays with the Sphere team
create or replace function public.sp_case_ai_note(p_dispute uuid, p_category text, p_summary text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.sp_core_has_role('ADMIN') then raise exception 'Admins only'; end if;
  update public.sp_disputes set ai_category = left(p_category, 40), ai_summary = left(p_summary, 1500), ai_checked_at = now() where id = p_dispute;
end $$;

-- editor extras paid by hand (admin)
create or replace function public.sp_payout_item_paid(p_item uuid, p_note text, p_pin text)
returns void language plpgsql security definer set search_path = public as $$
declare it record;
begin
  if not public.sp_core_has_role('ADMIN') then raise exception 'Admins only'; end if;
  perform public.sp_admin_check_pin(p_pin := p_pin);
  update public.sp_payout_items set status = 'paid', paid_at = now(), note = coalesce(nullif(btrim(p_note), ''), note) where id = p_item and status = 'pending'
  returning * into it;
  if it.id is not null then
    perform public.sp_work_notify(it.editor_id, 'Extra payout sent 💸', '₹' || it.amount || ' for paid revisions / changes on "' || public.sp_work_label(it.job_id) || '" was sent to you.');
  end if;
end $$;

-- can this project be fully refunded right now? (shown to the Sphere team)
create or replace function public.sp_refund_eligibility(p_job uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare j record; p record; reasons text[] := '{}';
begin
  if not public.sp_core_has_role('ADMIN') then raise exception 'Admins only'; end if;
  select * into j from public.sp_jobs where id = p_job;
  select * into p from public.sp_payments where job_id = p_job;
  if p.status is distinct from 'paid' then reasons := reasons || 'Payment is not in "paid" state'; end if;
  if j.status in ('approved', 'closed') then reasons := reasons || 'Payment was already released to the editor'; end if;
  if j.status = 'refunded' then reasons := reasons || 'Already refunded'; end if;
  return jsonb_build_object('eligible', cardinality(reasons) = 0, 'reasons', reasons, 'amount', p.amount);
end $$;

revoke all on function public.sp_final_submit(uuid, uuid, text, text), public.sp_dispute_open(uuid, text, text),
              public.sp_case_decide(uuid, text, text, text), public.sp_refund_mark(uuid, text, text), public.sp_case_ai_note(uuid, text, text),
              public.sp_payout_item_paid(uuid, text, text), public.sp_refund_eligibility(uuid) from public, anon;
grant execute on function public.sp_final_submit(uuid, uuid, text, text), public.sp_dispute_open(uuid, text, text),
              public.sp_case_decide(uuid, text, text, text), public.sp_refund_mark(uuid, text, text), public.sp_case_ai_note(uuid, text, text),
              public.sp_payout_item_paid(uuid, text, text), public.sp_refund_eligibility(uuid) to authenticated;

insert into public.sp_schema_versions (version, name)
values ('012', 'Final approval + disputes + refunds (10-hour window, case files, team decisions)')
on conflict (version) do update set applied_at = now();

commit;

-- every 10 minutes together with the deadline check (if pg_cron is available)
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    begin perform cron.unschedule('sphere-final-review'); exception when others then null; end;
    perform cron.schedule('sphere-final-review', '*/10 * * * *', 'select public.sp_final_tick()');
  end if;
exception when others then
  raise notice 'Could not schedule the final review check: % — the app checks on open.', sqlerrm;
end $$;

-- Done. You should see "Success. No rows returned".
