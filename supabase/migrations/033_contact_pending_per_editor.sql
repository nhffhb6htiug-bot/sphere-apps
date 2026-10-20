-- =====================================================================
-- SPHERE — FIX: a pending ₹5 for one editor blocked ₹5 for every other editor (Part 33)
-- Run in: Supabase → SQL Editor → + → paste → Run.  Safe to run again. Deletes NO data.
--
-- "sp_fee_one_pending" allowed only ONE pending fee per user and kind. For contact access (₹5 per
-- profile) that meant: one unfinished ₹5 payment stopped the user from paying for any other profile.
-- Contact access already has its own rule "one pending per user + profile" (sp_fee_contact_one_pending).
-- This keeps the one-pending rule for all other fees (₹29, ₹199, Pro) and lets each profile have its own.
-- =====================================================================
begin;
drop index if exists public.sp_fee_one_pending;
create unique index sp_fee_one_pending on public.sp_fee_payments (user_id, kind)
  where status = 'pending' and kind <> 'contact_unlock';
insert into public.sp_schema_versions (version, name)
values ('033', 'One pending ₹5 contact payment per profile (not per user)')
on conflict (version) do update set applied_at = now();
commit;
