-- =====================================================================
-- SPHERE — PART 6 CHECK (read-only, changes nothing)
-- Run after 006_bidding.sql. Every line should end with ✅
-- =====================================================================
select item, result from (
  select 1 as ord, 'Parts installed' as item,
         (select string_agg(version, ', ' order by version) from public.sp_schema_versions) ||
         case when exists (select 1 from public.sp_schema_versions where version = '006') then ' ✅' else ' ❌ (run 006_bidding.sql)' end as result
  union all
  select 2, 'Delivery time on bids',
         case when exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'sp_applications' and column_name = 'delivery_days') then 'ready ✅' else 'MISSING ❌' end
  union all
  select 3, 'One bid per editor per job',
         case when exists (select 1 from pg_indexes where indexname = 'sp_app_job_editor_uq')
                or exists (select 1 from pg_constraint c join pg_class t on t.oid = c.conrelid where t.relname = 'sp_applications' and c.contype = 'u')
              then 'on ✅' else 'old duplicates found ⚠️ (ask Claude)' end
  union all
  select 4, 'Bid rules (eligibility + guard)',
         case when exists (select 1 from pg_trigger where tgname = 'sp_bid_guard') and exists (select 1 from pg_proc where proname = 'sp_bid_eligibility') then 'on ✅' else 'MISSING ❌' end
  union all
  select 5, 'Choose-editor function',
         case when exists (select 1 from pg_proc where proname = 'sp_bid_select') then 'ready ✅' else 'MISSING ❌' end
  union all
  select 6, 'Bidding rule',
         case when public.sp_setting_int('bids_verified_only', 0) = 1 then 'only verified ✔ editors ✅'
              else 'verified ✔ + applied editors (first ' || public.sp_setting_int('free_works', 3) || ' paid works) ✅' end
  union all
  select 7, 'Bids by status',
         coalesce((select string_agg(s || ': ' || n, ', ' order by s) from (select coalesce(status, 'pending') as s, count(*) as n from public.sp_applications group by 1) x), 'no bids yet') || ' ✅'
) t order by ord;
