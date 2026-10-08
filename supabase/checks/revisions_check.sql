-- =====================================================================
-- SPHERE — PART 11 CHECK (read-only, changes nothing)
-- Run after 011_revisions_changes.sql. Every line should end with ✅
-- =====================================================================
select item, result from (
  select 1 as ord, 'Parts installed' as item,
         (select string_agg(version, ', ' order by version) from public.sp_schema_versions) ||
         case when exists (select 1 from public.sp_schema_versions where version = '011') then ' ✅' else ' ❌ (run 011_revisions_changes.sql)' end as result
  union all
  select 2, 'Revision rule',
         public.sp_setting_int('free_revisions', 3) || ' free, then ₹' || public.sp_setting_int('revision_fee', 50) ||
         ' each (100% to the editor), ' || public.sp_setting_int('revision_hours', 24) || ' h per revision ✅'
  union all
  select 3, 'Tables (revisions, change requests, extra payments)',
         (select count(*) from pg_class where relname in ('sp_revisions','sp_change_requests','sp_extra_payments','sp_extra_splits') and relrowsecurity)::text || ' of 4 ' ||
         case when (select count(*) from pg_class where relname in ('sp_revisions','sp_change_requests','sp_extra_payments','sp_extra_splits') and relrowsecurity) = 4 then '✅' else '❌' end
  union all
  select 4, 'Next preview closes a revision',
         case when exists (select 1 from pg_trigger where tgname = 'sp_rev_on_preview') then 'on ✅' else 'MISSING ❌' end
  union all
  select 5, 'Revisions',
         coalesce((select string_agg(status || ': ' || n, ', ' order by status) from (select status, count(*) n from public.sp_revisions group by 1) x), 'none yet') || ' ✅'
  union all
  select 6, 'Change requests',
         coalesce((select string_agg(status || ': ' || n, ', ' order by status) from (select status, count(*) n from public.sp_change_requests group by 1) x), 'none yet') || ' ✅'
  union all
  select 7, 'UPI payments waiting for an admin',
         (select count(*) from public.sp_extra_payments where status = 'pending' and utr is not null)::text ||
         case when (select count(*) from public.sp_extra_payments where status = 'pending' and utr is not null) = 0 then ' ✅' else ' ⚠️ Admin Panel → Extra payments' end
) t order by ord;
