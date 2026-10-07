-- =====================================================================
-- SPHERE — PART 7: EDITOR SELECTION + PAYMENT
-- Run in: Supabase → SQL Editor → + → paste → Run.  Safe to run again.
-- Needs 002, 003, 006 first. Adds tables/functions; deletes nothing.
-- The existing Razorpay Edge Functions keep working unchanged.
--
--   sp_payments        one payment record per project (job): pending / paid /
--                      failed / refunded. Client + editor can read their own,
--                      nobody can write it from the app.
--   sp_payment_splits  Sphere's internal split (editor share, Sphere fee, bonus
--                      pool). Admins only — never shown to clients.
--   sp_pay_lock_price  accept the other side's price → "payment-pending"
--   sp_pay_start       before Razorpay opens: is this project ready to pay? not paid already?
--   sp_pay_record      after Razorpay: remember order/payment IDs or the failure
--   Paid / refunded only come from the server side (Edge Functions → job row).
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1) Tables
-- ---------------------------------------------------------------------
create table if not exists public.sp_payments (
  id              uuid primary key default gen_random_uuid(),
  job_id          uuid not null,
  client_id       uuid not null,
  editor_id       uuid,
  amount          numeric(12,2) not null,
  currency        text not null default 'INR',
  status          text not null default 'pending',
  provider        text not null default 'razorpay',
  order_id        text,
  payment_id      text,
  attempts        int not null default 0,
  failure_reason  text,
  duplicate_refs  text[] not null default '{}',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  paid_at         timestamptz,
  refunded_at     timestamptz
);
create unique index if not exists sp_payments_job_uq on public.sp_payments (job_id);   -- one payment per project
alter table public.sp_payments drop constraint if exists sp_payments_status_chk;
alter table public.sp_payments add  constraint sp_payments_status_chk check (status in ('pending', 'paid', 'failed', 'refunded'));

create table if not exists public.sp_payment_splits (
  job_id               uuid primary key,
  editor_base          numeric(12,2) not null,
  platform_fee_percent numeric(5,2)  not null,
  platform_fee         numeric(12,2) not null,
  bonus_pool           numeric(12,2) not null default 0,
  editor_payout        numeric(12,2) not null,
  updated_at           timestamptz not null default now()
);

alter table public.sp_payments       enable row level security;
alter table public.sp_payment_splits enable row level security;
drop policy if exists sp_payments_read on public.sp_payments;
create policy sp_payments_read on public.sp_payments for select to authenticated
  using (client_id = auth.uid() or editor_id = auth.uid() or public.sp_core_has_role('ADMIN'));
drop policy if exists sp_payment_splits_admin on public.sp_payment_splits;
create policy sp_payment_splits_admin on public.sp_payment_splits for select to authenticated
  using (public.sp_core_has_role('ADMIN'));
revoke insert, update, delete on public.sp_payments, public.sp_payment_splits from anon, authenticated;
revoke all on public.sp_payment_splits from anon;
grant select on public.sp_payments, public.sp_payment_splits to authenticated;

-- ---------------------------------------------------------------------
-- 2) What the job row says about payment
-- ---------------------------------------------------------------------
create or replace function public.sp_pay_status_of(p_status text, p_payment text)
returns text language sql immutable as $$
  select case
    when p_status = 'refunded' or coalesce(p_payment, '') ilike '%refund%' then 'refunded'
    when coalesce(p_payment, '') in ('escrow-held', 'paid', 'captured', 'held')
      or p_status in ('in-progress', 'delivered', 'approved', 'closed') then 'paid'
    when p_status = 'payment-pending' then 'pending'
    else null end;
$$;

-- keep sp_payments in step with the job (works with the existing Edge Functions)
create or replace function public.sp_pay_sync_job()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  st text := public.sp_pay_status_of(NEW.status, NEW.payment_status);
  amt numeric := coalesce(NEW.locked_amount, NEW.budget);
  j jsonb := to_jsonb(NEW);
  oid text := coalesce(j->>'razorpay_order_id', j->>'order_id');
  pid text := coalesce(j->>'razorpay_payment_id', j->>'payment_id');
  pct numeric;
begin
  if st is null or amt is null then return null; end if;

  insert into public.sp_payments as p (job_id, client_id, editor_id, amount, status, order_id, payment_id, paid_at, refunded_at)
  values (NEW.id, NEW.client_id, NEW.assigned_editor, amt, st, oid, pid,
          case when st = 'paid' then now() end, case when st = 'refunded' then now() end)
  on conflict (job_id) do update set
    editor_id   = excluded.editor_id,
    amount      = case when p.status in ('pending', 'failed') then excluded.amount else p.amount end,
    status      = case
                    when excluded.status = 'refunded' then 'refunded'
                    when excluded.status = 'paid' and p.status <> 'refunded' then 'paid'
                    else p.status end,          -- "pending" never overwrites failed/paid
    order_id    = coalesce(p.order_id, excluded.order_id),
    payment_id  = coalesce(p.payment_id, excluded.payment_id),
    paid_at     = case when excluded.status = 'paid' and p.paid_at is null then now() else p.paid_at end,
    refunded_at = case when excluded.status = 'refunded' and p.refunded_at is null then now() else p.refunded_at end,
    updated_at  = now();

  -- Sphere's internal split, fixed once the price is locked (admins only)
  if st = 'pending' or not exists (select 1 from public.sp_payment_splits where job_id = NEW.id) then
    pct := coalesce((select nullif(regexp_replace(value::text, '[^0-9.]', '', 'g'), '')::numeric
                       from public.sp_settings where key = 'platform_fee_percent'), 5);
    insert into public.sp_payment_splits as s (job_id, editor_base, platform_fee_percent, platform_fee, editor_payout)
    values (NEW.id, amt, pct, round(amt * pct / 100, 2), amt - round(amt * pct / 100, 2))
    on conflict (job_id) do update set
      editor_base = excluded.editor_base, platform_fee_percent = excluded.platform_fee_percent,
      platform_fee = excluded.platform_fee, editor_payout = excluded.editor_payout, updated_at = now()
    where not exists (select 1 from public.sp_payments x where x.job_id = NEW.id and x.status in ('paid', 'refunded'));
  end if;
  return null;
end $$;

drop trigger if exists sp_pay_sync_job on public.sp_jobs;
create trigger sp_pay_sync_job after insert or update of status, payment_status, locked_amount, assigned_editor on public.sp_jobs
  for each row execute function public.sp_pay_sync_job();

-- existing projects get their payment record (no change to the jobs themselves)
insert into public.sp_payments (job_id, client_id, editor_id, amount, status, paid_at, refunded_at)
select id, client_id, assigned_editor, coalesce(locked_amount, budget),
       public.sp_pay_status_of(status, payment_status),
       case when public.sp_pay_status_of(status, payment_status) = 'paid' then now() end,
       case when public.sp_pay_status_of(status, payment_status) = 'refunded' then now() end
from public.sp_jobs
where public.sp_pay_status_of(status, payment_status) is not null and coalesce(locked_amount, budget) is not null
on conflict (job_id) do nothing;

-- ---------------------------------------------------------------------
-- 3) Accept the other side's price → lock it → "payment-pending"
-- ---------------------------------------------------------------------
create or replace function public.sp_pay_lock_price(p_job uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare j record; me uuid := auth.uid(); label text;
begin
  select * into j from public.sp_jobs where id = p_job for update;
  if j.id is null then raise exception 'Project not found.'; end if;
  if me is distinct from j.client_id and me is distinct from j.assigned_editor then raise exception 'This is not your project.'; end if;
  if j.status is distinct from 'negotiating' or j.assigned_editor is null then raise exception 'The price for this project is already decided.'; end if;
  if j.proposed_amount is null or j.proposed_amount <= 0 then raise exception 'No price has been proposed yet.'; end if;
  if j.proposed_by = me then raise exception 'Waiting for the other side to accept your price.'; end if;

  update public.sp_jobs set locked_amount = j.proposed_amount, budget = j.proposed_amount, status = 'payment-pending' where id = j.id;

  label := coalesce(nullif(j.title, ''), j.category, 'project');
  insert into public.sp_notifications (user_id, title, body) values
    (j.client_id, 'Price locked 🔒', 'Final amount ₹' || j.proposed_amount || ' for "' || label || '" is locked. Please make the payment to start the work.'),
    (j.assigned_editor, 'Price locked 🔒', 'Final amount ₹' || j.proposed_amount || ' for "' || label || '" is locked. Waiting for the client''s payment.');
  return jsonb_build_object('job_id', j.id, 'amount', j.proposed_amount);
end $$;
revoke all on function public.sp_pay_lock_price(uuid) from public, anon;
grant execute on function public.sp_pay_lock_price(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 4) Before Razorpay opens: ready to pay? not paid already?
-- ---------------------------------------------------------------------
create or replace function public.sp_pay_start(p_job uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare j record; p record; me uuid := auth.uid();
begin
  select * into j from public.sp_jobs where id = p_job for update;
  if j.id is null then return jsonb_build_object('ok', false, 'code', 'no_job', 'message', 'Project not found.'); end if;
  if me is distinct from j.client_id then return jsonb_build_object('ok', false, 'code', 'not_client', 'message', 'Only the client of this project can pay.'); end if;
  select * into p from public.sp_payments where job_id = j.id;
  if p.status = 'paid' or public.sp_pay_status_of(j.status, j.payment_status) = 'paid' then
    return jsonb_build_object('ok', false, 'code', 'paid', 'message', 'This project is already paid ✅');
  end if;
  if p.status = 'refunded' or j.status = 'refunded' then
    return jsonb_build_object('ok', false, 'code', 'refunded', 'message', 'This project was refunded.');
  end if;
  if j.status is distinct from 'payment-pending' or j.locked_amount is null then
    return jsonb_build_object('ok', false, 'code', 'not_ready', 'message', 'The price must be agreed and locked before paying.');
  end if;
  update public.sp_payments set status = 'pending', attempts = attempts + 1, failure_reason = null, updated_at = now()
   where job_id = j.id;
  return jsonb_build_object('ok', true, 'amount', j.locked_amount, 'currency', 'INR');
end $$;
revoke all on function public.sp_pay_start(uuid) from public, anon;
grant execute on function public.sp_pay_start(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 5) After Razorpay: remember the IDs, or why it failed. Never marks "paid".
-- ---------------------------------------------------------------------
create or replace function public.sp_pay_record(p_job uuid, p_result text, p_order text, p_payment text, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare p record; me uuid := auth.uid(); label text;
begin
  select * into p from public.sp_payments where job_id = p_job for update;
  if p.id is null then return; end if;
  if me is distinct from p.client_id then raise exception 'Not your payment.'; end if;
  p_order := left(nullif(btrim(p_order), ''), 80);
  p_payment := left(nullif(btrim(p_payment), ''), 80);

  if p_result = 'failed' then
    if p.status in ('pending', 'failed') then
      update public.sp_payments set status = 'failed', failure_reason = left(coalesce(p_reason, 'Payment failed'), 300),
             order_id = coalesce(p_order, order_id), updated_at = now() where id = p.id;
    end if;
  elsif p_result = 'success' then
    if p.status = 'paid' and p.payment_id is not null and p_payment is not null and p.payment_id <> p_payment then
      -- a second payment for the same project: keep it on record and tell the admins to refund it
      update public.sp_payments set duplicate_refs = array_append(duplicate_refs, p_payment), updated_at = now() where id = p.id;
      select coalesce(nullif(title, ''), category, 'project') into label from public.sp_jobs where id = p_job;
      insert into public.sp_notifications (user_id, title, body)
      select id, 'Duplicate payment ⚠️', 'Project "' || label || '" was paid twice. Refund the extra payment in Razorpay (ID ' || p_payment || ').'
        from public.profiles where upper(btrim(role)) = 'ADMIN';
    else
      update public.sp_payments set order_id = coalesce(p_order, order_id), payment_id = coalesce(payment_id, p_payment), updated_at = now() where id = p.id;
    end if;
  end if;
end $$;
revoke all on function public.sp_pay_record(uuid, text, text, text, text) from public, anon;
grant execute on function public.sp_pay_record(uuid, text, text, text, text) to authenticated;

insert into public.sp_schema_versions (version, name)
values ('007', 'Editor selection + payment (payment records, private split, price lock, duplicate protection)')
on conflict (version) do update set applied_at = now();

commit;

-- Done. You should see "Success. No rows returned".
