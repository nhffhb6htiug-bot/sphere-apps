-- =====================================================================
-- SPHERE — PART 7 CHECK (read-only, changes nothing)
-- Run after 007_payments.sql. Every line should end with ✅
-- =====================================================================
select item, result from (
  select 1 as ord, 'Parts installed' as item,
         (select string_agg(version, ', ' order by version) from public.sp_schema_versions) ||
         case when exists (select 1 from public.sp_schema_versions where version = '007') then ' ✅' else ' ❌ (run 007_payments.sql)' end as result
  union all
  select 2, 'Payment records (private)',
         case when exists (select 1 from pg_class where relname = 'sp_payments' and relrowsecurity) then 'ready ✅' else 'MISSING ❌' end
  union all
  select 3, 'Sphere split hidden from clients',
         case when exists (select 1 from pg_class where relname = 'sp_payment_splits' and relrowsecurity)
               and not has_table_privilege('anon', 'public.sp_payment_splits', 'select') then 'admins only ✅' else 'check ⚠️' end
  union all
  select 4, 'One payment per project',
         case when exists (select 1 from pg_indexes where indexname = 'sp_payments_job_uq') then 'on ✅' else 'MISSING ❌' end
  union all
  select 5, 'Synced with projects',
         case when exists (select 1 from pg_trigger where tgname = 'sp_pay_sync_job') then 'on ✅' else 'MISSING ❌' end
  union all
  select 6, 'Payments by status',
         coalesce((select string_agg(status || ': ' || n, ', ' order by status) from (select status, count(*) as n from public.sp_payments group by 1) x), 'none yet') || ' ✅'
  union all
  select 7, 'Projects waiting for payment',
         (select count(*) from public.sp_jobs where status = 'payment-pending')::text || ' ✅'
  union all
  select 8, 'Duplicate payments to refund',
         (select count(*) from public.sp_payments where cardinality(duplicate_refs) > 0)::text ||
         case when (select count(*) from public.sp_payments where cardinality(duplicate_refs) > 0) = 0 then ' ✅' else ' ⚠️ refund in Razorpay' end
) t order by ord;
