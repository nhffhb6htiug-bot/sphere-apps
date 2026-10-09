-- =====================================================================
-- SPHERE — PART 15: MONETIZATION (₹29 verification · ₹199 Pro · Sponsored)
-- Run in: Supabase → SQL Editor → + → paste → Run.  Safe to run again.
-- Needs 001–014 first. Adds tables/functions; deletes nothing.
--
--   sp_fee_payments       every ₹29 verification / ₹199 Pro payment (one row per attempt)
--                         pending → paid / failed / cancelled. Marked PAID only by the server
--                         (sphere-extra-payment Edge Function after Razorpay's signature check)
--                         or by an admin confirming a UPI transaction ID.
--   ₹29 verification      paid → fee confirmed + a verification request for the admins.
--                         It never approves anyone. One-time: a paid editor is never charged again.
--   sp_subscriptions      Editor Pro: inactive / pending / active / expired / failed + expiry.
--                         Editors only. ₹199 for 30 days; renewal only in the last 3 days
--                         (adds 30 days to the current end) — no double active plans.
--   sp_monetization_config prices, Pro benefits and Sponsored slots (admins change them)
--   sp_sponsored_items    small "Sponsored" cards per slot; real clicks counted, nothing faked
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1) Config (readable by logged-in users, changed only by admins)
-- ---------------------------------------------------------------------
create table if not exists public.sp_monetization_config (
  key        text primary key,
  value      jsonb not null,
  updated_at timestamptz not null default now()
);
insert into public.sp_monetization_config (key, value) values
  ('verification', '{"price": 29}'::jsonb),
  ('pro', '{"price": 199, "days": 30, "renew_days": 3,
            "benefits": {"badge": true, "boost": true, "analytics": true, "priority_alerts": true, "free_open_bids": 0},
            "labels": {"badge": "PRO badge on your profile", "boost": "Shown first in editor lists", "analytics": "Earnings & performance analytics",
                       "priority_alerts": "Instant alerts for new jobs in your categories", "free_open_bids": "Unlimited open bids"}}'::jsonb),
  ('sponsored', '{"enabled": false, "slots": {"client_home": true, "editor_jobs": true, "editor_list": true}, "provider": "house"}'::jsonb)
on conflict (key) do nothing;
alter table public.sp_monetization_config enable row level security;
drop policy if exists sp_mon_config_read on public.sp_monetization_config;
create policy sp_mon_config_read on public.sp_monetization_config for select to authenticated using (true);
revoke insert, update, delete on public.sp_monetization_config from anon, authenticated;
grant select on public.sp_monetization_config to authenticated;

create or replace function public.sp_mon_cfg(p_key text)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce((select value from public.sp_monetization_config where key = p_key), '{}'::jsonb);
$$;

-- ---------------------------------------------------------------------
-- 2) Payments + subscriptions
-- ---------------------------------------------------------------------
create table if not exists public.sp_fee_payments (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null,
  kind           text not null,                  -- verification | pro
  amount         numeric(10,2) not null,
  status         text not null default 'pending', -- pending | paid | failed | cancelled
  method         text,                           -- razorpay | upi
  order_id       text,
  payment_id     text,
  utr            text,
  failure_reason text,
  period_start   timestamptz,
  period_end     timestamptz,
  created_at     timestamptz not null default now(),
  paid_at        timestamptz
);
alter table public.sp_fee_payments drop constraint if exists sp_fee_chk;
alter table public.sp_fee_payments add  constraint sp_fee_chk check (kind in ('verification', 'pro') and status in ('pending', 'paid', 'failed', 'cancelled') and amount > 0);
create unique index if not exists sp_fee_one_pending on public.sp_fee_payments (user_id, kind) where status = 'pending';
create unique index if not exists sp_fee_payment_uq on public.sp_fee_payments (payment_id) where payment_id is not null;
create unique index if not exists sp_fee_utr_uq on public.sp_fee_payments (utr) where utr is not null and status <> 'failed';
create index if not exists sp_fee_user_idx on public.sp_fee_payments (user_id, created_at desc);

create table if not exists public.sp_subscriptions (
  user_id            uuid primary key,
  plan               text not null default 'pro',
  status             text not null default 'inactive',   -- inactive | pending | active | expired | failed
  started_at         timestamptz,
  current_period_end timestamptz,
  last_fee_id        uuid,
  updated_at         timestamptz not null default now()
);
-- (works even if an older experimental sp_subscriptions table exists)
alter table public.sp_subscriptions add column if not exists plan text not null default 'pro';
alter table public.sp_subscriptions add column if not exists status text not null default 'inactive';
alter table public.sp_subscriptions add column if not exists started_at timestamptz;
alter table public.sp_subscriptions add column if not exists current_period_end timestamptz;
alter table public.sp_subscriptions add column if not exists last_fee_id uuid;
alter table public.sp_subscriptions add column if not exists updated_at timestamptz not null default now();
do $$ begin
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'sp_subscriptions' and column_name = 'expires_at') then
    execute 'update public.sp_subscriptions set current_period_end = expires_at where current_period_end is null';
  end if;
end $$;
alter table public.sp_subscriptions drop constraint if exists sp_sub_chk;
alter table public.sp_subscriptions add  constraint sp_sub_chk check (status in ('inactive', 'pending', 'active', 'expired', 'failed')) not valid;

alter table public.sp_fee_payments  enable row level security;
alter table public.sp_subscriptions enable row level security;
drop policy if exists sp_fee_read on public.sp_fee_payments;
create policy sp_fee_read on public.sp_fee_payments for select to authenticated using (user_id = auth.uid() or public.sp_core_has_role('ADMIN'));
drop policy if exists sp_sub_read on public.sp_subscriptions;
create policy sp_sub_read on public.sp_subscriptions for select to authenticated using (user_id = auth.uid() or public.sp_core_has_role('ADMIN'));
revoke insert, update, delete on public.sp_fee_payments, public.sp_subscriptions from anon, authenticated;
grant select on public.sp_fee_payments, public.sp_subscriptions to authenticated;

-- who is Pro right now (for the badge and list order) — no payment details
create or replace view public.sp_pro_public as
  select user_id as editor_id, current_period_end from public.sp_subscriptions where status = 'active' and current_period_end > now();
grant select on public.sp_pro_public to authenticated;

create or replace function public.sp_is_pro(p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.sp_subscriptions where user_id = p_user and status = 'active' and current_period_end > now());
$$;

-- ---------------------------------------------------------------------
-- 3) Sponsored items
-- ---------------------------------------------------------------------
create table if not exists public.sp_sponsored_items (
  id          uuid primary key default gen_random_uuid(),
  slot        text not null,                  -- client_home | editor_jobs | editor_list
  title       text not null,
  body        text,
  cta         text,
  link_url    text,
  image_url   text,
  advertiser  text,
  active      boolean not null default true,
  starts_at   timestamptz,
  ends_at     timestamptz,
  clicks      int not null default 0,
  created_by  uuid,
  created_at  timestamptz not null default now()
);
alter table public.sp_sponsored_items drop constraint if exists sp_ad_chk;
alter table public.sp_sponsored_items add  constraint sp_ad_chk check (slot in ('client_home', 'editor_jobs', 'editor_list')
  and char_length(title) between 3 and 80 and (body is null or char_length(body) <= 160) and (cta is null or char_length(cta) <= 30)
  and (link_url is null or link_url ~* '^https://') and (image_url is null or image_url ~* '^https://'));
alter table public.sp_sponsored_items enable row level security;
drop policy if exists sp_ad_admin_read on public.sp_sponsored_items;
create policy sp_ad_admin_read on public.sp_sponsored_items for select to authenticated using (public.sp_core_has_role('ADMIN'));
revoke insert, update, delete on public.sp_sponsored_items from anon, authenticated;
grant select on public.sp_sponsored_items to authenticated;

-- what a slot shows right now (empty when Sponsored is off — nothing is faked)
create or replace function public.sp_sponsored_for(p_slot text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare c jsonb := public.sp_mon_cfg('sponsored');
begin
  if not coalesce((c->>'enabled')::boolean, false) or not coalesce((c->'slots'->>p_slot)::boolean, false) then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', i.id, 'title', i.title, 'body', i.body, 'cta', i.cta, 'link', i.link_url,
                   'image', i.image_url, 'advertiser', i.advertiser))
         from (select * from public.sp_sponsored_items where slot = p_slot and active
                 and (starts_at is null or starts_at <= now()) and (ends_at is null or ends_at > now())
               order by random() limit 1) i), '[]'::jsonb);
end $$;

create or replace function public.sp_ad_click(p_item uuid)
returns void language sql security definer set search_path = public as $$
  update public.sp_sponsored_items set clicks = clicks + 1 where id = p_item and active;
$$;

-- ---------------------------------------------------------------------
-- 4) Effects of a PAID fee (internal — reached only through the server or an admin)
-- ---------------------------------------------------------------------
create or replace function public.sp_fee_apply(p_fee uuid)
returns void language plpgsql security definer set search_path = public as $$
declare f record; s record; days int := greatest(1, coalesce((public.sp_mon_cfg('pro')->>'days')::int, 30)); st timestamptz; en timestamptz;
begin
  select * into f from public.sp_fee_payments where id = p_fee;
  if f.kind = 'verification' then
    update public.profiles
       set verification_fee_status = 'confirmed', verification_fee_ref = coalesce(f.payment_id, f.utr, verification_fee_ref),
           verification_fee_at = coalesce(verification_fee_at, now()),
           verification_status = case when coalesce(is_verified, false) then verification_status else 'pending' end
     where id = f.user_id;
    perform public.sp_ed_notify_admins('Verification request 💳',
      'An editor paid the ₹' || f.amount || ' verification fee. Review them in Admin Panel → Verification.');
    insert into public.sp_notifications (user_id, title, body) values (f.user_id, 'Payment received ✅',
      'Thank you! Your verification request is with the Sphere team. You get the ✔ tick only after they approve it.');
  elsif f.kind = 'pro' then
    select * into s from public.sp_subscriptions where user_id = f.user_id for update;
    st := case when s.status = 'active' and s.current_period_end > now() then s.current_period_end else now() end;
    en := st + make_interval(days => days);
    insert into public.sp_subscriptions (user_id, status, started_at, current_period_end, last_fee_id, updated_at)
    values (f.user_id, 'active', now(), en, f.id, now())
    on conflict (user_id) do update set status = 'active', started_at = coalesce(public.sp_subscriptions.started_at, now()),
      current_period_end = en, last_fee_id = f.id, updated_at = now();
    update public.sp_fee_payments set period_start = st, period_end = en where id = f.id;
    insert into public.sp_notifications (user_id, title, body) values (f.user_id, 'Sphere Pro is active ⭐',
      'Your Pro plan runs until ' || to_char(en at time zone 'Asia/Kolkata', 'DD Mon YYYY') || '.');
  end if;
end $$;
revoke all on function public.sp_fee_apply(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- 5) Start a payment (the editor) — amount always from the config
-- ---------------------------------------------------------------------
create or replace function public.sp_fee_start(p_kind text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); p record; s record; f record; price numeric; renew int; fid uuid;
begin
  if me is null then raise exception 'Please log in.'; end if;
  select * into p from public.profiles where id = me;
  if upper(btrim(coalesce(p.role, ''))) <> 'EDITOR' then raise exception 'Only editor accounts can buy this. Clients are never charged for it.'; end if;
  if p_kind = 'verification' then
    if coalesce(p.is_verified, false) then raise exception 'You are already verified.'; end if;
    if exists (select 1 from public.sp_fee_payments where user_id = me and kind = 'verification' and status = 'paid')
       or p.verification_fee_status = 'confirmed' then
      raise exception 'You already paid the verification fee — it is one-time. The Sphere team will review you.';
    end if;
    price := coalesce((public.sp_mon_cfg('verification')->>'price')::numeric, 29);
  elsif p_kind = 'pro' then
    select * into s from public.sp_subscriptions where user_id = me;
    renew := coalesce((public.sp_mon_cfg('pro')->>'renew_days')::int, 3);
    if s.status = 'active' and s.current_period_end > now() + make_interval(days => renew) then
      raise exception 'Pro is already active until %. You can renew in the last % days.', to_char(s.current_period_end at time zone 'Asia/Kolkata', 'DD Mon YYYY'), renew;
    end if;
    price := coalesce((public.sp_mon_cfg('pro')->>'price')::numeric, 199);
  else
    raise exception 'Unknown payment.';
  end if;
  select * into f from public.sp_fee_payments where user_id = me and kind = p_kind and status = 'pending';
  if f.id is not null then
    update public.sp_fee_payments set amount = price where id = f.id and utr is null and order_id is null;
    fid := f.id;
  else
    insert into public.sp_fee_payments (user_id, kind, amount) values (me, p_kind, price) returning id into fid;
  end if;
  if p_kind = 'pro' then
    insert into public.sp_subscriptions (user_id, status) values (me, 'pending')
    on conflict (user_id) do update set status = case when public.sp_subscriptions.status = 'active' and public.sp_subscriptions.current_period_end > now()
                                                      then 'active' else 'pending' end, updated_at = now();
  end if;
  return jsonb_build_object('id', fid, 'amount', price, 'kind', p_kind);
end $$;

-- the payment window failed / was closed (owner) — only an unpaid attempt can be marked failed
create or replace function public.sp_fee_failed(p_fee uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare f record;
begin
  select * into f from public.sp_fee_payments where id = p_fee for update;
  if f.id is null or (f.user_id is distinct from auth.uid() and not public.sp_core_has_role('ADMIN')) then raise exception 'Not your payment.'; end if;
  if f.status <> 'pending' or f.utr is not null then return; end if;
  update public.sp_fee_payments set status = 'failed', failure_reason = left(p_reason, 200) where id = f.id;
  if f.kind = 'pro' then
    update public.sp_subscriptions set status = 'failed', updated_at = now()
     where user_id = f.user_id and not (status = 'active' and current_period_end > now());
  end if;
end $$;

-- UPI fallback: the editor types the transaction ID; an admin confirms it
create or replace function public.sp_fee_submit_utr(p_fee uuid, p_utr text)
returns void language plpgsql security definer set search_path = public as $$
declare f record; v_utr text := upper(regexp_replace(coalesce(p_utr, ''), '\s', '', 'g'));
begin
  select * into f from public.sp_fee_payments where id = p_fee for update;
  if f.id is null or f.user_id is distinct from auth.uid() then raise exception 'Not your payment.'; end if;
  if f.status <> 'pending' then raise exception 'This payment is already %.', f.status; end if;
  if v_utr !~ '^[A-Z0-9]{10,22}$' then raise exception 'Enter the UPI transaction ID (usually 12 digits).'; end if;
  if exists (select 1 from public.sp_fee_payments where utr = v_utr and id <> f.id and status <> 'failed') then raise exception 'This transaction ID was already used.'; end if;
  update public.sp_fee_payments set utr = v_utr, method = 'upi' where id = f.id;
  if f.kind = 'verification' then
    update public.profiles set verification_fee_status = 'submitted', verification_fee_ref = v_utr, verification_fee_at = now()
     where id = f.user_id and coalesce(verification_fee_status, 'unpaid') <> 'confirmed';
  else
    perform public.sp_ed_notify_admins('Pro payment to check 💳', 'An editor paid ₹' || f.amount || ' for Sphere Pro by UPI. Admin Panel → Monetization.');
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 6) Mark paid — ONLY the server (Razorpay function, service role) or an admin
-- ---------------------------------------------------------------------
create or replace function public.sp_fee_mark_paid(p_fee uuid, p_method text, p_payment text, p_order text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  claims jsonb := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb);
  is_server boolean := coalesce(claims->>'role', current_setting('request.jwt.claim.role', true), '') = 'service_role';
  f record;
begin
  if not is_server and not public.sp_core_has_role('ADMIN') then raise exception 'Not allowed.'; end if;
  select * into f from public.sp_fee_payments where id = p_fee for update;
  if f.id is null then raise exception 'Payment not found.'; end if;
  if f.status = 'paid' then return jsonb_build_object('status', 'paid', 'already', true); end if;   -- no double processing
  if f.status = 'cancelled' then raise exception 'This payment was cancelled.'; end if;
  if p_payment is not null and exists (select 1 from public.sp_fee_payments where payment_id = p_payment and id <> f.id) then
    raise exception 'This Razorpay payment was already used.';
  end if;
  update public.sp_fee_payments set status = 'paid', paid_at = now(), method = coalesce(p_method, method),
         payment_id = coalesce(left(p_payment, 80), payment_id), order_id = coalesce(left(p_order, 80), order_id), failure_reason = null
   where id = f.id;
  perform public.sp_fee_apply(f.id);
  return jsonb_build_object('status', 'paid');
end $$;

create or replace function public.sp_fee_admin(p_fee uuid, p_action text, p_reason text, p_pin text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare f record;
begin
  perform public.sp_admin_with_pin(p_pin, p_reason, p_action = 'reject');
  select * into f from public.sp_fee_payments where id = p_fee;
  if f.id is null then raise exception 'Payment not found.'; end if;
  if p_action = 'confirm' then
    return public.sp_fee_mark_paid(p_fee, coalesce(f.method, 'upi'), null, null);
  elsif p_action = 'reject' then
    update public.sp_fee_payments set status = 'failed', failure_reason = left(btrim(p_reason), 200) where id = p_fee and status = 'pending';
    if f.kind = 'verification' then
      update public.profiles set verification_fee_status = 'unpaid', verification_fee_ref = null where id = f.user_id and verification_fee_status = 'submitted';
    else
      update public.sp_subscriptions set status = 'failed', updated_at = now() where user_id = f.user_id and not (status = 'active' and current_period_end > now());
    end if;
    insert into public.sp_notifications (user_id, title, body) values (f.user_id, 'Payment not found ⚠️',
      'We could not find your UPI payment of ₹' || f.amount || '. ' || left(btrim(p_reason), 160));
    return jsonb_build_object('status', 'failed');
  end if;
  raise exception 'Unknown action.';
end $$;

-- the older admin button "Fee received" (Part 4 / 14) keeps the payment record in step
create or replace function public.sp_fee_profile_sync()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if NEW.verification_fee_status = 'confirmed' and OLD.verification_fee_status is distinct from 'confirmed' then
    update public.sp_fee_payments set status = 'paid', paid_at = now(), method = coalesce(method, 'upi')
     where user_id = NEW.id and kind = 'verification' and status = 'pending';
  end if;
  return null;
end $$;
drop trigger if exists sp_fee_profile_sync on public.profiles;
create trigger sp_fee_profile_sync after update of verification_fee_status on public.profiles
  for each row execute function public.sp_fee_profile_sync();

-- ---------------------------------------------------------------------
-- 7) Expiry, Pro benefits
-- ---------------------------------------------------------------------
create or replace function public.sp_sub_tick()
returns int language plpgsql security definer set search_path = public as $$
declare r record; n int := 0;
begin
  for r in select * from public.sp_subscriptions where status = 'active' and current_period_end <= now() for update skip locked loop
    update public.sp_subscriptions set status = 'expired', updated_at = now() where user_id = r.user_id;
    insert into public.sp_notifications (user_id, title, body) values (r.user_id, 'Sphere Pro expired', 'Renew Pro from your dashboard to keep the benefits.');
    n := n + 1;
  end loop;
  return n;
end $$;

-- limit open bids for free editors only when the admin sets free_open_bids > 0 (default 0 = off)
create or replace function public.sp_pro_bid_limit()
returns trigger language plpgsql security definer set search_path = public as $$
declare lim int := coalesce((public.sp_mon_cfg('pro')->'benefits'->>'free_open_bids')::int, 0);
begin
  if lim > 0 and not public.sp_is_pro(NEW.editor_id)
     and (select count(*) from public.sp_applications a join public.sp_jobs j on j.id = a.job_id
          where a.editor_id = NEW.editor_id and coalesce(a.status, 'pending') = 'pending' and j.status = 'open') >= lim then
    raise exception 'Free editors can have % open bids at a time. Sphere Pro gives unlimited bids.', lim;
  end if;
  return NEW;
end $$;
drop trigger if exists sp_pro_bid_limit on public.sp_applications;
create trigger sp_pro_bid_limit before insert on public.sp_applications
  for each row execute function public.sp_pro_bid_limit();

-- priority job alerts for Pro editors (new open job in their categories)
create or replace function public.sp_pro_job_alert()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if NEW.status = 'open' and coalesce((public.sp_mon_cfg('pro')->'benefits'->>'priority_alerts')::boolean, false) then
    insert into public.sp_notifications (user_id, title, body)
    select p.id, '⭐ New job for you', '"' || coalesce(nullif(NEW.title, ''), NEW.category, 'New job') || '" — ₹' || coalesce(NEW.budget, 0) || '. Bid early!'
    from public.profiles p join public.sp_subscriptions s on s.user_id = p.id and s.status = 'active' and s.current_period_end > now()
    where p.id <> NEW.client_id and (NEW.category = any(coalesce(p.categories, '{}')) or p.category = NEW.category)
    limit 100;
  end if;
  return null;
end $$;
drop trigger if exists sp_pro_job_alert on public.sp_jobs;
create trigger sp_pro_job_alert after insert on public.sp_jobs
  for each row execute function public.sp_pro_job_alert();

-- Pro analytics (own numbers only)
create or replace function public.sp_pro_analytics()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if not public.sp_is_pro(me) or not coalesce((public.sp_mon_cfg('pro')->'benefits'->>'analytics')::boolean, true) then
    raise exception 'Analytics are part of Sphere Pro.';
  end if;
  return jsonb_build_object(
    'bids_90d', (select count(*) from public.sp_applications where editor_id = me and created_at > now() - interval '90 days'),
    'won_90d',  (select count(*) from public.sp_applications where editor_id = me and status = 'selected' and created_at > now() - interval '90 days'),
    'earned_30d', (select coalesce(sum(editor_base + bonus_awarded - late_deduction), 0) from public.sp_settlements s join public.sp_jobs j on j.id = s.job_id
                    where s.editor_id = me and coalesce(j.released_at, s.computed_at) > now() - interval '30 days'),
    'earned_90d', (select coalesce(sum(editor_base + bonus_awarded - late_deduction), 0) from public.sp_settlements s join public.sp_jobs j on j.id = s.job_id
                    where s.editor_id = me and coalesce(j.released_at, s.computed_at) > now() - interval '90 days'),
    'avg_rating', (select round(avg(score), 1) from public.sp_project_ratings where editor_id = me),
    'on_time_pct', (select round(100.0 * count(*) filter (where late_hours = 0) / nullif(count(*), 0)) from public.sp_delivery_checks d
                     join public.sp_jobs j on j.id = d.job_id where j.assigned_editor = me),
    'bonus_total', (select coalesce(sum(bonus_awarded), 0) from public.sp_settlements where editor_id = me),
    'completed', (select count(*) from public.sp_jobs where assigned_editor = me and status in ('approved', 'closed')));
end $$;

-- everything the editor's monetization screens need (own data only)
create or replace function public.sp_my_monetization()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then return null; end if;
  return jsonb_build_object(
    'verification', (select to_jsonb(f) - 'order_id' from public.sp_fee_payments f where f.user_id = me and f.kind = 'verification' order by created_at desc limit 1),
    'verification_paid', exists (select 1 from public.sp_fee_payments where user_id = me and kind = 'verification' and status = 'paid'),
    'subscription', (select to_jsonb(s) from public.sp_subscriptions s where s.user_id = me),
    'pro_active', public.sp_is_pro(me),
    'pro_payments', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'amount', f.amount, 'status', f.status, 'method', f.method, 'utr', f.utr,
                     'period_end', f.period_end, 'created_at', f.created_at, 'paid_at', f.paid_at) order by f.created_at desc)
                     from (select * from public.sp_fee_payments where user_id = me and kind = 'pro' order by created_at desc limit 12) f), '[]'::jsonb),
    'config', jsonb_build_object('verification', public.sp_mon_cfg('verification'), 'pro', public.sp_mon_cfg('pro')));
end $$;

-- ---------------------------------------------------------------------
-- 8) Admin: monetization view + controls (ADMIN, changes with PIN + reason)
-- ---------------------------------------------------------------------
create or replace function public.sp_mon_admin()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  perform public.sp_admin_only();
  return jsonb_build_object(
    'config', (select jsonb_object_agg(key, value) from public.sp_monetization_config),
    'to_check', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'kind', f.kind, 'amount', f.amount, 'utr', f.utr, 'name', p.full_name, 'created_at', f.created_at) order by f.created_at)
                  from public.sp_fee_payments f left join public.profiles p on p.id = f.user_id where f.status = 'pending' and f.utr is not null), '[]'::jsonb),
    'verification_payments', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'name', p.full_name, 'amount', f.amount, 'status', f.status, 'method', f.method,
                  'paid_at', f.paid_at, 'created_at', f.created_at, 'verification', coalesce(p.verification_status, 'pending'), 'verified', p.is_verified) order by f.created_at desc)
                  from (select * from public.sp_fee_payments where kind = 'verification' order by created_at desc limit 60) f left join public.profiles p on p.id = f.user_id), '[]'::jsonb),
    'subscriptions', coalesce((select jsonb_agg(jsonb_build_object('user_id', s.user_id, 'name', p.full_name, 'status',
                  case when s.status = 'active' and s.current_period_end <= now() then 'expired' else s.status end,
                  'expires', s.current_period_end, 'started', s.started_at,
                  'paid_total', (select coalesce(sum(amount), 0) from public.sp_fee_payments where user_id = s.user_id and kind = 'pro' and status = 'paid')) order by s.updated_at desc)
                  from public.sp_subscriptions s left join public.profiles p on p.id = s.user_id), '[]'::jsonb),
    'sponsored', coalesce((select jsonb_agg(to_jsonb(i) order by i.created_at desc) from public.sp_sponsored_items i), '[]'::jsonb),
    'totals', jsonb_build_object(
       'verification', (select coalesce(sum(amount), 0) from public.sp_fee_payments where kind = 'verification' and status = 'paid'),
       'pro', (select coalesce(sum(amount), 0) from public.sp_fee_payments where kind = 'pro' and status = 'paid'),
       'pro_active', (select count(*) from public.sp_subscriptions where status = 'active' and current_period_end > now()),
       'ad_clicks', (select coalesce(sum(clicks), 0) from public.sp_sponsored_items)));
end $$;

create or replace function public.sp_mon_config_set(p_key text, p_value jsonb, p_reason text, p_pin text)
returns void language plpgsql security definer set search_path = public as $$
declare old jsonb;
begin
  perform public.sp_admin_with_pin(p_pin, p_reason, false);
  if p_key not in ('verification', 'pro', 'sponsored') then raise exception 'Unknown setting.'; end if;
  if p_key = 'verification' and coalesce((p_value->>'price')::numeric, 0) <= 0 then raise exception 'Price must be above 0.'; end if;
  if p_key = 'pro' and (coalesce((p_value->>'price')::numeric, 0) <= 0 or coalesce((p_value->>'days')::int, 0) < 1) then raise exception 'Check price and days.'; end if;
  select value into old from public.sp_monetization_config where key = p_key;
  insert into public.sp_monetization_config (key, value, updated_at) values (p_key, p_value, now())
  on conflict (key) do update set value = excluded.value, updated_at = now();
  perform public.sp_audit_write('monetization_setting', 'setting', p_key, null, null, left(old::text, 300), left(p_value::text, 300), p_reason, '{}');
end $$;

create or replace function public.sp_sponsored_save(p_item jsonb, p_pin text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid := nullif(p_item->>'id', '')::uuid; old_active boolean;
begin
  perform public.sp_admin_with_pin(p_pin, null, false);
  if v_id is null then
    insert into public.sp_sponsored_items (slot, title, body, cta, link_url, image_url, advertiser, active, starts_at, ends_at, created_by)
    values (p_item->>'slot', btrim(p_item->>'title'), nullif(btrim(p_item->>'body'), ''), nullif(btrim(p_item->>'cta'), ''), nullif(btrim(p_item->>'link'), ''),
            nullif(btrim(p_item->>'image'), ''), nullif(btrim(p_item->>'advertiser'), ''), coalesce((p_item->>'active')::boolean, true),
            nullif(p_item->>'starts_at', '')::timestamptz, nullif(p_item->>'ends_at', '')::timestamptz, auth.uid())
    returning id into v_id;
    perform public.sp_audit_write('sponsored_add', 'setting', v_id::text, null, null, null, p_item->>'slot', p_item->>'title', '{}');
  else
    select active into old_active from public.sp_sponsored_items where id = v_id;
    update public.sp_sponsored_items set active = coalesce((p_item->>'active')::boolean, active) where id = v_id;
    perform public.sp_audit_write('sponsored_toggle', 'setting', v_id::text, null, null, old_active::text, (p_item->>'active'), null, '{}');
  end if;
  return v_id;
end $$;

-- audit for the new tables (admin / system changes only)
create or replace function public.sp_audit_trigger_mon()
returns trigger language plpgsql security definer set search_path = public as $$
declare who text := public.sp_audit_actor(); o jsonb := case when TG_OP = 'UPDATE' then to_jsonb(OLD) else '{}'::jsonb end; n jsonb := to_jsonb(NEW);
begin
  if who = 'user' then return null; end if;
  if TG_TABLE_NAME = 'sp_fee_payments' and (o->>'status') is distinct from (n->>'status') then
    perform public.sp_audit_write('fee_payment', 'payment', n->>'id', null, (n->>'user_id')::uuid, o->>'status', n->>'status', n->>'failure_reason',
      jsonb_build_object('kind', n->>'kind', 'amount', n->>'amount', 'method', n->>'method'));
  elsif TG_TABLE_NAME = 'sp_subscriptions' and ((o->>'status') is distinct from (n->>'status') or (o->>'current_period_end') is distinct from (n->>'current_period_end')) then
    perform public.sp_audit_write('subscription', 'user', n->>'user_id', null, (n->>'user_id')::uuid, o->>'status', n->>'status', null,
      jsonb_build_object('expires', n->>'current_period_end'));
  end if;
  return null;
end $$;
drop trigger if exists zz_sp_audit on public.sp_fee_payments;
create trigger zz_sp_audit after insert or update on public.sp_fee_payments for each row execute function public.sp_audit_trigger_mon();
drop trigger if exists zz_sp_audit on public.sp_subscriptions;
create trigger zz_sp_audit after insert or update on public.sp_subscriptions for each row execute function public.sp_audit_trigger_mon();

-- revenue on the Overview now includes ₹29 records and Pro
create or replace function public.sp_admin_overview()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare pct numeric; vfee numeric := public.sp_setting_int('verify_fee', 29); proj numeric; extras numeric; vcount int; vpaid numeric; pro numeric; r jsonb;
begin
  perform public.sp_admin_only();
  pct := coalesce((select nullif(regexp_replace(value::text, '[^0-9.]', '', 'g'), '')::numeric from public.sp_settings where key = 'platform_fee_percent'), 5);
  select coalesce(sum(coalesce(s.sphere_total, ps.platform_fee, round(coalesce(j.locked_amount, 0) * pct / 100, 2))), 0) into proj
    from public.sp_jobs j left join public.sp_settlements s on s.job_id = j.id left join public.sp_payment_splits ps on ps.job_id = j.id
   where j.status in ('approved', 'closed');
  select coalesce(sum(x.sphere_share), 0) into extras from public.sp_extra_splits x join public.sp_extra_payments e on e.id = x.extra_id where e.status = 'paid';
  -- ₹29 fees: paid fee records + older confirmations that have no record
  select coalesce(sum(amount), 0) into vpaid from public.sp_fee_payments where kind = 'verification' and status = 'paid';
  select count(*) into vcount from public.profiles p where p.verification_fee_status = 'confirmed'
     and not exists (select 1 from public.sp_fee_payments f where f.user_id = p.id and f.kind = 'verification' and f.status = 'paid');
  select coalesce(sum(amount), 0) into pro from public.sp_fee_payments where kind = 'pro' and status = 'paid';
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
    'revenue',          jsonb_build_object('projects', proj, 'extras', extras, 'verification', vpaid + vcount * vfee, 'pro', pro, 'total', proj + extras + vpaid + vcount * vfee + pro),
    'pro_active',       (select count(*) from public.sp_subscriptions where status = 'active' and current_period_end > now()),
    'pending', jsonb_build_object(
       'disputes',      (select count(*) from public.sp_disputes where status = 'open'),
       'held_messages', (select count(*) from public.sp_msg_holds where status = 'pending'),
       'verifications', (select count(*) from public.profiles where upper(btrim(role)) = 'EDITOR' and not coalesce(is_verified, false)
                           and (verification_status = 'pending' or verification_fee_status = 'submitted')),
       'upi_extras',    (select count(*) from public.sp_extra_payments where status = 'pending' and utr is not null),
       'fees',          (select count(*) from public.sp_fee_payments where status = 'pending' and utr is not null),
       'payouts',       (select count(*) from public.sp_payout_items where status = 'pending')
                      + (select count(*) from public.sp_jobs where status in ('approved', 'closed') and payout_status in ('manual', 'failed')),
       'refunds',       (select count(*) from public.sp_refunds where status in ('approved', 'failed')),
       'reports',       (select count(*) from public.sp_reports where status = 'open'),
       'suspicious_users', (select count(*) from public.sp_mod_flags where strike_count >= public.sp_setting_int('strike_limit', 3) and not is_suspended))
  );
  return r;
end $$;

-- ---------------------------------------------------------------------
-- 9) Access
-- ---------------------------------------------------------------------
revoke all on function public.sp_mon_cfg(text), public.sp_is_pro(uuid), public.sp_sponsored_for(text), public.sp_ad_click(uuid),
              public.sp_fee_start(text), public.sp_fee_failed(uuid, text), public.sp_fee_submit_utr(uuid, text),
              public.sp_fee_mark_paid(uuid, text, text, text), public.sp_fee_admin(uuid, text, text, text), public.sp_sub_tick(),
              public.sp_pro_analytics(), public.sp_my_monetization(), public.sp_mon_admin(), public.sp_mon_config_set(text, jsonb, text, text),
              public.sp_sponsored_save(jsonb, text), public.sp_admin_overview() from public, anon;
grant execute on function public.sp_is_pro(uuid), public.sp_sponsored_for(text), public.sp_ad_click(uuid),
              public.sp_fee_start(text), public.sp_fee_failed(uuid, text), public.sp_fee_submit_utr(uuid, text),
              public.sp_fee_mark_paid(uuid, text, text, text), public.sp_fee_admin(uuid, text, text, text), public.sp_sub_tick(),
              public.sp_pro_analytics(), public.sp_my_monetization(), public.sp_mon_admin(), public.sp_mon_config_set(text, jsonb, text, text),
              public.sp_sponsored_save(jsonb, text), public.sp_admin_overview() to authenticated;
grant execute on function public.sp_fee_mark_paid(uuid, text, text, text) to service_role;

insert into public.sp_schema_versions (version, name)
values ('015', 'Monetization (₹29 verification payments, ₹199 Pro, Sponsored placements)')
on conflict (version) do update set applied_at = now();

commit;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    begin perform cron.unschedule('sphere-subscriptions'); exception when others then null; end;
    perform cron.schedule('sphere-subscriptions', '23 * * * *', 'select public.sp_sub_tick()');
  end if;
exception when others then
  raise notice 'Could not schedule the subscription check: % — the app checks on open.', sqlerrm;
end $$;

-- Done. You should see "Success. No rows returned".
-- For Razorpay: deploy the updated sphere-extra-payment function (it now also handles ₹29 and Pro).
