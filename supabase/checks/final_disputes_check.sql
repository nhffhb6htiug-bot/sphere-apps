-- =====================================================================
-- SPHERE — PART 12 CHECK (read-only, changes nothing)
-- Run after 012_final_disputes.sql. Every line should end with ✅
-- =====================================================================
select item, result from (
  select 1 as ord, 'Parts installed' as item,
         (select string_agg(version, ', ' order by version) from public.sp_schema_versions) ||
         case when exists (select 1 from public.sp_schema_versions where version = '012') then ' ✅' else ' ❌ (run 012_final_disputes.sql)' end as result
  union all
  select 2, 'Client decision window',
         public.sp_setting_int('final_review_hours', 10) || ' hours, then the Sphere team reviews ✅'
  union all
  select 3, 'Tables (final files, disputes, refunds, payouts)',
         (select count(*) from pg_class where relname in ('sp_final_files','sp_disputes','sp_refunds','sp_payout_items') and relrowsecurity)::text || ' of 4 ' ||
         case when (select count(*) from pg_class where relname in ('sp_final_files','sp_disputes','sp_refunds','sp_payout_items') and relrowsecurity) = 4 then '✅' else '❌' end
  union all
  select 4, 'Release / refund follow the payment functions',
         case when (select count(*) from pg_trigger where tgname in ('sp_final_job_before','sp_final_job_after')) = 2 then 'on ✅' else 'MISSING ❌' end
  union all
  select 5, 'Complaints closed after release',
         case when exists (select 1 from pg_trigger where tgname = 'sp_final_report_guard') then 'on ✅' else 'MISSING ❌' end
  union all
  select 6, 'Automatic 10-hour check',
         case when exists (select 1 from pg_extension where extname = 'pg_cron') then 'every 10 min (pg_cron) ✅' else 'when someone opens the app ✅' end
  union all
  select 7, 'Projects waiting for the client',
         (select count(*) from public.sp_jobs where status = 'delivered' and review_state = 'awaiting_client')::text || ' ✅'
  union all
  select 8, 'Open cases for the Sphere team',
         (select count(*) from public.sp_disputes where status = 'open')::text ||
         case when (select count(*) from public.sp_disputes where status = 'open') = 0 then ' ✅' else ' ⚠️ Admin Panel → Reviews & disputes' end
  union all
  select 9, 'Refunds not finished',
         (select count(*) from public.sp_refunds where status in ('approved', 'processing', 'failed'))::text ||
         case when (select count(*) from public.sp_refunds where status in ('approved', 'processing', 'failed')) = 0 then ' ✅' else ' ⚠️' end
  union all
  select 10, 'Editor extra payouts to send',
         (select count(*) from public.sp_payout_items where status = 'pending')::text ||
         case when (select count(*) from public.sp_payout_items where status = 'pending') = 0 then ' ✅' else ' ⚠️ Admin Panel → Extra payouts' end
) t order by ord;
