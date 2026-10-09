-- =====================================================================
-- SPHERE — PART 15 CHECK (read-only, changes nothing)
-- Run after 015_monetization.sql. Every line should end with ✅
-- =====================================================================
select item, result from (
  select 1 as ord, 'Parts installed' as item,
         (select string_agg(version, ', ' order by version) from public.sp_schema_versions) ||
         case when exists (select 1 from public.sp_schema_versions where version = '015') then ' ✅' else ' ❌ (run 015_monetization.sql)' end as result
  union all
  select 2, 'Prices',
         'verification ₹' || coalesce(public.sp_mon_cfg('verification')->>'price', '?') || ' · Pro ₹' || coalesce(public.sp_mon_cfg('pro')->>'price', '?') ||
         ' / ' || coalesce(public.sp_mon_cfg('pro')->>'days', '?') || ' days ✅'
  union all
  select 3, 'Tables (payments, subscriptions, config, sponsored)',
         (select count(*) from pg_class where relname in ('sp_fee_payments','sp_subscriptions','sp_monetization_config','sp_sponsored_items') and relrowsecurity)::text || ' of 4 ' ||
         case when (select count(*) from pg_class where relname in ('sp_fee_payments','sp_subscriptions','sp_monetization_config','sp_sponsored_items') and relrowsecurity) = 4 then '✅' else '❌' end
  union all
  select 4, 'Payments can be marked paid only by the server / admins',
         case when not has_function_privilege('anon', 'public.sp_fee_mark_paid(uuid, text, text, text)', 'execute') then 'yes ✅' else 'open ⚠️' end
  union all
  select 5, 'No double charging (one open attempt, unique payment / UPI IDs)',
         case when (select count(*) from pg_indexes where indexname in ('sp_fee_one_pending', 'sp_fee_payment_uq', 'sp_fee_utr_uq')) = 3 then 'on ✅' else 'MISSING ❌' end
  union all
  select 6, 'Sponsored placements',
         case when coalesce((public.sp_mon_cfg('sponsored')->>'enabled')::boolean, false) then 'ON · ' else 'off · ' end ||
         (select count(*) from public.sp_sponsored_items where active)::text || ' active cards ✅'
  union all
  select 7, 'Pro editors active now',
         (select count(*) from public.sp_subscriptions where status = 'active' and current_period_end > now())::text || ' ✅'
  union all
  select 8, 'Payments paid (₹29 / Pro)',
         '₹' || (select coalesce(sum(amount), 0) from public.sp_fee_payments where kind = 'verification' and status = 'paid') || ' / ₹' ||
         (select coalesce(sum(amount), 0) from public.sp_fee_payments where kind = 'pro' and status = 'paid') || ' ✅'
  union all
  select 9, 'UPI payments waiting for an admin',
         (select count(*) from public.sp_fee_payments where status = 'pending' and utr is not null)::text ||
         case when (select count(*) from public.sp_fee_payments where status = 'pending' and utr is not null) = 0 then ' ✅' else ' ⚠️ Admin → Monetization' end
) t order by ord;
