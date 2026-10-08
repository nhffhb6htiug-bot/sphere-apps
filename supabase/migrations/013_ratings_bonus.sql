-- =====================================================================
-- SPHERE — PART 13: RATINGS + PERFORMANCE BONUS + LATE DEDUCTION
-- Run in: Supabase → SQL Editor → + → paste → Run.  Safe to run again.
-- Needs 007, 008, 009, 010, 011, 012 first. Adds tables/functions; deletes nothing.
--
--   sp_project_ratings  client rates the editor −3 … +3 (+ optional feedback), once per project.
--                       Old 1–5 stars are still written (−3→1 … +3→5) so existing screens keep working.
--   sp_delivery_checks  every preview delivery vs the deadline valid at that moment
--                       (extensions + change requests included): hours early / hours late.
--   sp_settlements      one row per project, admins only:
--       pool            = client payment − editor base          (editor base = what the editor gets paid)
--       Sphere          = 50 % of the pool, always
--       bonus pool      = the other 50 %, in 4 equal parts — one part per condition met:
--         1) first delivery ≥ 5 h before the valid deadline
--         2) client rating +3
--         3) released by the client without a dispute, with ≤ 1 revision
--         4) clean outcome: every delivery inside its deadline, no team "fix" decision,
--            no refund, no blocked contact-sharing messages from the editor in this project
--       Late after the 4-hour grace → no bonus at all, and ₹10 per late hour is deducted
--       (late_fee_per_hour), at most the editor base.
--   Settlement is provisional at release and final after the rating (or after
--   rating_window_days without one). Final rows never change again.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1) Settings
-- ---------------------------------------------------------------------
insert into public.sp_settings (key, value) select 'late_fee_per_hour', '10'   where not exists (select 1 from public.sp_settings where key = 'late_fee_per_hour');
insert into public.sp_settings (key, value) select 'bonus_early_hours', '5'    where not exists (select 1 from public.sp_settings where key = 'bonus_early_hours');
insert into public.sp_settings (key, value) select 'rating_window_days', '7'   where not exists (select 1 from public.sp_settings where key = 'rating_window_days');

alter table public.sp_jobs add column if not exists released_at timestamptz;

-- ---------------------------------------------------------------------
-- 2) Tables
-- ---------------------------------------------------------------------
create table if not exists public.sp_project_ratings (
  id         uuid primary key default gen_random_uuid(),
  job_id     uuid not null,
  editor_id  uuid not null,
  client_id  uuid not null,
  score      int not null,
  feedback   text,
  created_at timestamptz not null default now()
);
create unique index if not exists sp_project_ratings_job_uq on public.sp_project_ratings (job_id);
alter table public.sp_project_ratings drop constraint if exists sp_project_ratings_chk;
alter table public.sp_project_ratings add  constraint sp_project_ratings_chk check (score between -3 and 3 and (feedback is null or char_length(feedback) <= 1000));

create table if not exists public.sp_delivery_checks (
  id           bigserial primary key,
  job_id       uuid not null,
  kind         text not null,              -- main (first preview) | followup (revision / change)
  due_at       timestamptz not null,       -- deadline valid at that moment
  grace_hours  int not null,
  delivered_at timestamptz not null,
  early_hours  numeric(8,2) not null,      -- negative = after the deadline
  late_hours   int not null default 0,     -- started hours after deadline + grace (5-minute tolerance)
  created_at   timestamptz not null default now()
);
alter table public.sp_delivery_checks add column if not exists late_minutes int not null default 0;
create unique index if not exists sp_delivery_checks_uq on public.sp_delivery_checks (job_id, delivered_at);

create table if not exists public.sp_settlements (
  job_id            uuid primary key,
  editor_id         uuid not null,
  client_paid       numeric(12,2) not null,
  editor_base       numeric(12,2) not null,
  pool              numeric(12,2) not null,
  sphere_guaranteed numeric(12,2) not null,
  bonus_pool        numeric(12,2) not null,
  part_value        numeric(12,2) not null,
  c_early           boolean not null default false,
  c_rating          boolean not null default false,
  c_revisions       boolean not null default false,
  c_quality         boolean not null default false,
  conditions_met    int not null default 0,
  late_hours        int not null default 0,
  late_deduction    numeric(12,2) not null default 0,
  bonus_awarded     numeric(12,2) not null default 0,
  sphere_total      numeric(12,2) not null,
  net_adjustment    numeric(12,2) not null default 0,   -- bonus − deduction for the editor
  status            text not null default 'provisional', -- provisional | final
  details           jsonb not null default '{}'::jsonb,
  computed_at       timestamptz not null default now(),
  finalized_at      timestamptz
);

-- read rules
alter table public.sp_project_ratings enable row level security;
alter table public.sp_delivery_checks enable row level security;
alter table public.sp_settlements     enable row level security;
drop policy if exists sp_project_ratings_read on public.sp_project_ratings;
create policy sp_project_ratings_read on public.sp_project_ratings for select to authenticated
  using (client_id = auth.uid() or editor_id = auth.uid() or public.sp_core_has_role('ADMIN'));
drop policy if exists sp_delivery_checks_read on public.sp_delivery_checks;
create policy sp_delivery_checks_read on public.sp_delivery_checks for select to authenticated using (public.sp_files_party(job_id::text));
drop policy if exists sp_settlements_admin on public.sp_settlements;
create policy sp_settlements_admin on public.sp_settlements for select to authenticated using (public.sp_core_has_role('ADMIN'));
revoke insert, update, delete on public.sp_project_ratings, public.sp_delivery_checks, public.sp_settlements from anon, authenticated;
grant select on public.sp_project_ratings, public.sp_delivery_checks, public.sp_settlements to authenticated;

-- public rating history for editor pages (no client names)
create or replace view public.sp_editor_ratings_public as
  select r.editor_id, r.score, r.feedback, r.created_at, j.category
  from public.sp_project_ratings r left join public.sp_jobs j on j.id = r.job_id;
grant select on public.sp_editor_ratings_public to authenticated;

-- (sp_payout_items from Part 12 also holds kind = bonus (to pay) and kind = deduction (to recover))

-- ---------------------------------------------------------------------
-- 3) Every preview = a delivery check against the deadline valid right then
-- ---------------------------------------------------------------------
create or replace function public.sp_delivery_check_trigger()
returns trigger language plpgsql security definer set search_path = public as $$
declare late_min int; late int;
begin
  if NEW.preview_at is null or NEW.preview_at is not distinct from OLD.preview_at then return null; end if;
  late_min := greatest(0, floor(extract(epoch from (NEW.preview_at - (NEW.due_at + make_interval(hours => NEW.grace_hours)))) / 60.0))::int;
  -- every started hour counts, with 5 minutes tolerance (2 h 3 min = 2 hours, 2 h 10 min = 3 hours)
  late := case when late_min <= 5 then 0 else ceil((late_min - 5) / 60.0)::int end;
  insert into public.sp_delivery_checks (job_id, kind, due_at, grace_hours, delivered_at, early_hours, late_hours, late_minutes)
  values (NEW.job_id,
          case when not exists (select 1 from public.sp_delivery_checks c where c.job_id = NEW.job_id) then 'main' else 'followup' end,
          NEW.due_at, NEW.grace_hours, NEW.preview_at,
          round(extract(epoch from (NEW.due_at - NEW.preview_at)) / 3600.0, 2), late, late_min)
  on conflict (job_id, delivered_at) do nothing;
  return null;
end $$;
drop trigger if exists sp_delivery_check_trigger on public.sp_project_work;
create trigger sp_delivery_check_trigger after update of preview_at on public.sp_project_work
  for each row execute function public.sp_delivery_check_trigger();

-- ---------------------------------------------------------------------
-- 4) The calculation (internal). Final rows are never recalculated.
-- ---------------------------------------------------------------------
create or replace function public.sp_bonus_compute(p_job uuid, p_finalize boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  j record; s record; pay numeric; base numeric; pool numeric; guaranteed numeric; bpool numeric; part numeric;
  pct numeric; fee_per_hour numeric := public.sp_setting_int('late_fee_per_hour', 10);
  early_need numeric := public.sp_setting_int('bonus_early_hours', 5);
  main_early numeric; late_h int; rating int; revs int; disputed boolean; redo boolean; refunded boolean; contact_flags int; any_after_deadline boolean;
  c1 boolean; c2 boolean; c3 boolean; c4 boolean; met int; bonus numeric; deduction numeric;
begin
  select * into s from public.sp_settlements where job_id = p_job;
  if s.job_id is not null and s.status = 'final' then return to_jsonb(s); end if;
  select * into j from public.sp_jobs where id = p_job;
  if j.id is null or j.assigned_editor is null then return null; end if;

  -- money: client payment vs what the editor is paid for the project
  select amount into pay from public.sp_payments where job_id = p_job and status in ('paid', 'refunded');
  pay := coalesce(pay, j.locked_amount, 0);
  pct := coalesce((select nullif(regexp_replace(value::text, '[^0-9.]', '', 'g'), '')::numeric from public.sp_settings where key = 'platform_fee_percent'), 5);
  base := coalesce(nullif(to_jsonb(j)->>'editor_amount', '')::numeric, round(pay * (100 - pct) / 100, 2));
  base := least(base, pay);
  pool := greatest(0, pay - base);
  guaranteed := round(pool / 2, 2);
  bpool := pool - guaranteed;
  part := round(bpool / 4, 2);

  -- delivery performance (deadline valid at each delivery: extensions + change requests included)
  select early_hours into main_early from public.sp_delivery_checks where job_id = p_job and kind = 'main' order by delivered_at limit 1;
  select coalesce(sum(late_hours), 0), coalesce(bool_or(early_hours < 0), false) into late_h, any_after_deadline
    from public.sp_delivery_checks where job_id = p_job;
  select score into rating from public.sp_project_ratings where job_id = p_job;
  select count(*) into revs from public.sp_revisions where job_id = p_job and status <> 'cancelled';
  disputed := exists (select 1 from public.sp_disputes where job_id = p_job and kind = 'dispute');
  redo := exists (select 1 from public.sp_disputes where job_id = p_job and status = 'resolved_redo');
  refunded := j.status = 'refunded';
  select count(*) into contact_flags from public.sp_messages m
   where m.job_id = p_job and m.sender_id = j.assigned_editor and (m.mod_status in ('removed') or m."text" like '%📵%');

  c1 := main_early is not null and main_early >= early_need;
  c2 := coalesce(rating, -99) >= 3;
  c3 := j.status in ('approved', 'closed') and not disputed and revs <= 1;
  c4 := not refunded and not redo and contact_flags = 0 and not any_after_deadline and main_early is not null;
  met := (c1)::int + (c2)::int + (c3)::int + (c4)::int;
  bonus := case when late_h > 0 or refunded then 0 else part * met end;
  deduction := case when refunded then 0 else least(base, late_h * fee_per_hour) end;

  insert into public.sp_settlements as t (job_id, editor_id, client_paid, editor_base, pool, sphere_guaranteed, bonus_pool, part_value,
         c_early, c_rating, c_revisions, c_quality, conditions_met, late_hours, late_deduction, bonus_awarded, sphere_total, net_adjustment,
         status, details, computed_at, finalized_at)
  values (p_job, j.assigned_editor, pay, base, pool, guaranteed, bpool, part, c1, c2, c3, c4, met, late_h, deduction, bonus,
          pool - bonus, bonus - deduction, case when p_finalize then 'final' else 'provisional' end,
          jsonb_build_object('first_delivery_hours_before_deadline', main_early, 'needed_hours_before', early_need, 'rating', rating,
                             'revisions', revs, 'dispute', disputed, 'team_fix', redo, 'refunded', refunded, 'contact_flags', contact_flags,
                             'any_delivery_after_deadline', any_after_deadline, 'late_fee_per_hour', fee_per_hour, 'platform_fee_percent', pct,
                             'late_rule', 'no bonus when late after the grace period'),
          now(), case when p_finalize then now() end)
  on conflict (job_id) do update set
    editor_id = excluded.editor_id, client_paid = excluded.client_paid, editor_base = excluded.editor_base, pool = excluded.pool,
    sphere_guaranteed = excluded.sphere_guaranteed, bonus_pool = excluded.bonus_pool, part_value = excluded.part_value,
    c_early = excluded.c_early, c_rating = excluded.c_rating, c_revisions = excluded.c_revisions, c_quality = excluded.c_quality,
    conditions_met = excluded.conditions_met, late_hours = excluded.late_hours, late_deduction = excluded.late_deduction,
    bonus_awarded = excluded.bonus_awarded, sphere_total = excluded.sphere_total, net_adjustment = excluded.net_adjustment,
    status = excluded.status, details = excluded.details, computed_at = now(), finalized_at = excluded.finalized_at
  where t.status = 'provisional';

  update public.sp_payment_splits set bonus_pool = bpool, updated_at = now() where job_id = p_job;

  if p_finalize then
    if bonus > 0 then
      insert into public.sp_payout_items (job_id, editor_id, kind, amount, note)
      values (p_job, j.assigned_editor, 'bonus', bonus, met || ' of 4 bonus conditions met') on conflict (job_id, kind) do nothing;
    end if;
    if deduction > 0 then
      insert into public.sp_payout_items (job_id, editor_id, kind, amount, note)
      values (p_job, j.assigned_editor, 'deduction', deduction, late_h || ' late hours × ₹' || fee_per_hour || ' — recover from the next payout') on conflict (job_id, kind) do nothing;
    end if;
    perform public.sp_work_event(p_job, null, 'settled',
      'Editor earnings settled: bonus ₹' || bonus || case when deduction > 0 then ', late deduction ₹' || deduction else '' end, null);
  end if;
  select * into s from public.sp_settlements where job_id = p_job;
  return to_jsonb(s);
end $$;
revoke all on function public.sp_bonus_compute(uuid, boolean) from public, anon, authenticated;

-- provisional numbers as soon as the payment is released
create or replace function public.sp_bonus_on_release()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if NEW.status is distinct from OLD.status and NEW.status = 'approved' then
    update public.sp_jobs set released_at = coalesce(released_at, now()) where id = NEW.id;
    perform public.sp_bonus_compute(NEW.id, false);
  end if;
  return null;
end $$;
drop trigger if exists sp_bonus_on_release on public.sp_jobs;
create trigger sp_bonus_on_release after update of status on public.sp_jobs
  for each row execute function public.sp_bonus_on_release();

-- ---------------------------------------------------------------------
-- 5) Client rating (−3 … +3), once, after release
-- ---------------------------------------------------------------------
create or replace function public.sp_rating_submit(p_job uuid, p_score int, p_feedback text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare j record; fb text; days int := greatest(1, public.sp_setting_int('rating_window_days', 7));
begin
  select * into j from public.sp_jobs where id = p_job for update;
  if j.id is null then raise exception 'Project not found.'; end if;
  if auth.uid() is distinct from j.client_id then raise exception 'Only the client of this project can rate it.'; end if;
  if j.status not in ('approved', 'closed') then raise exception 'You can rate after releasing the payment.'; end if;
  if p_score is null or p_score < -3 or p_score > 3 then raise exception 'Choose a rating from −3 to +3.'; end if;
  if exists (select 1 from public.sp_project_ratings where job_id = p_job) then raise exception 'You have already rated this project.'; end if;
  if coalesce(j.released_at, now()) < now() - make_interval(days => days) then raise exception 'The time to rate this project has ended.'; end if;
  fb := public.sp_clean_text(p_feedback, 1000);
  insert into public.sp_project_ratings (job_id, editor_id, client_id, score, feedback) values (p_job, j.assigned_editor, j.client_id, p_score, fb);
  -- keep the old 1–5 stars in step for existing screens (−3→1, 0→3, +3→5)
  if not exists (select 1 from public.sp_ratings where job_id = p_job) then
    insert into public.sp_ratings (job_id, editor_id, client_id, stars, review)
    values (p_job, j.assigned_editor, j.client_id, greatest(1, least(5, round((p_score + 3) * 4.0 / 6 + 1)::int)), fb);
  end if;
  update public.sp_jobs set status = 'closed' where id = p_job and status = 'approved';
  perform public.sp_work_event(p_job, auth.uid(), 'rated', 'Client rated the editor ' || case when p_score > 0 then '+' else '' end || p_score, fb);
  perform public.sp_bonus_compute(p_job, true);
  return jsonb_build_object('score', p_score);
end $$;
revoke all on function public.sp_rating_submit(uuid, int, text) from public, anon;
grant execute on function public.sp_rating_submit(uuid, int, text) to authenticated;

-- not rated in time → settle without the rating condition
create or replace function public.sp_bonus_tick()
returns int language plpgsql security definer set search_path = public as $$
declare r record; n int := 0; days int := greatest(1, public.sp_setting_int('rating_window_days', 7));
begin
  for r in select s.job_id from public.sp_settlements s join public.sp_jobs j on j.id = s.job_id
           where s.status = 'provisional' and coalesce(j.released_at, s.computed_at) < now() - make_interval(days => days) loop
    perform public.sp_bonus_compute(r.job_id, true);
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function public.sp_bonus_tick() from public, anon;
grant execute on function public.sp_bonus_tick() to authenticated;

-- ---------------------------------------------------------------------
-- 6) What the editor sees (never the Sphere side of the split)
-- ---------------------------------------------------------------------
create or replace function public.sp_settlement_mine(p_job uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare s record; x numeric;
begin
  select * into s from public.sp_settlements where job_id = p_job;
  if s.job_id is null then return null; end if;
  if s.editor_id is distinct from auth.uid() and not public.sp_core_has_role('ADMIN') then return null; end if;
  select coalesce(sum(sp.editor_share), 0) into x from public.sp_extra_payments e join public.sp_extra_splits sp on sp.extra_id = e.id
   where e.job_id = p_job and e.status = 'paid';
  return jsonb_build_object('status', s.status, 'base', s.editor_base, 'extras', x, 'bonus_max', s.bonus_pool, 'part', s.part_value,
    'early', s.c_early, 'rating', s.c_rating, 'revisions', s.c_revisions, 'quality', s.c_quality, 'met', s.conditions_met,
    'late_hours', s.late_hours, 'late_deduction', s.late_deduction, 'bonus', s.bonus_awarded,
    'total', s.editor_base + x + s.bonus_awarded - s.late_deduction, 'details', s.details - 'platform_fee_percent');
end $$;

create or replace function public.sp_editor_earnings_summary()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('projects', count(*), 'base', coalesce(sum(editor_base), 0), 'bonus', coalesce(sum(bonus_awarded), 0),
                            'deductions', coalesce(sum(late_deduction), 0), 'conditions_met', coalesce(sum(conditions_met), 0))
  from public.sp_settlements where editor_id = auth.uid();
$$;
revoke all on function public.sp_settlement_mine(uuid), public.sp_editor_earnings_summary() from public, anon;
grant execute on function public.sp_settlement_mine(uuid), public.sp_editor_earnings_summary() to authenticated;

insert into public.sp_schema_versions (version, name)
values ('013', 'Ratings −3…+3 + performance bonus + late deduction (auditable settlements)')
on conflict (version) do update set applied_at = now();

commit;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    begin perform cron.unschedule('sphere-bonus'); exception when others then null; end;
    perform cron.schedule('sphere-bonus', '17 * * * *', 'select public.sp_bonus_tick()');
  end if;
exception when others then
  raise notice 'Could not schedule the bonus check: % — the app checks on open.', sqlerrm;
end $$;

-- Done. You should see "Success. No rows returned".
