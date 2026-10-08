-- =====================================================================
-- SPHERE — PART 13 CHECK (read-only, changes nothing)
-- Run after 013_ratings_bonus.sql. Every line should end with ✅
-- =====================================================================
select item, result from (
  select 1 as ord, 'Parts installed' as item,
         (select string_agg(version, ', ' order by version) from public.sp_schema_versions) ||
         case when exists (select 1 from public.sp_schema_versions where version = '013') then ' ✅' else ' ❌ (run 013_ratings_bonus.sql)' end as result
  union all
  select 2, 'Rules',
         'bonus: delivered ≥ ' || public.sp_setting_int('bonus_early_hours', 5) || ' h early · late: ₹' || public.sp_setting_int('late_fee_per_hour', 10) ||
         '/hour after grace · rate within ' || public.sp_setting_int('rating_window_days', 7) || ' days ✅'
  union all
  select 3, 'Tables (ratings, delivery checks, settlements)',
         (select count(*) from pg_class where relname in ('sp_project_ratings','sp_delivery_checks','sp_settlements') and relrowsecurity)::text || ' of 3 ' ||
         case when (select count(*) from pg_class where relname in ('sp_project_ratings','sp_delivery_checks','sp_settlements') and relrowsecurity) = 3 then '✅' else '❌' end
  union all
  select 4, 'One rating per project',
         case when exists (select 1 from pg_indexes where indexname = 'sp_project_ratings_job_uq') then 'on ✅' else 'MISSING ❌' end
  union all
  select 5, 'Delivery checks on every preview',
         case when exists (select 1 from pg_trigger where tgname = 'sp_delivery_check_trigger') then 'on ✅' else 'MISSING ❌' end
  union all
  select 6, 'Ratings so far',
         coalesce((select count(*) || ' (average ' || round(avg(score), 1) || ')' from public.sp_project_ratings having count(*) > 0), 'none yet') || ' ✅'
  union all
  select 7, 'Settlements',
         coalesce((select string_agg(status || ': ' || n, ', ') from (select status, count(*) n from public.sp_settlements group by 1) x), 'none yet') || ' ✅'
  union all
  select 8, 'Bonus paid out / to pay',
         '₹' || coalesce((select sum(bonus_awarded) from public.sp_settlements where status = 'final'), 0) || ' earned, ' ||
         (select count(*) from public.sp_payout_items where kind = 'bonus' and status = 'pending') || ' to pay ✅'
  union all
  select 9, 'Late deductions to recover',
         (select count(*) from public.sp_payout_items where kind = 'deduction' and status = 'pending')::text || ' ✅'
  union all
  select 10, 'Totals add up (pool = Sphere + bonus)',
         case when not exists (select 1 from public.sp_settlements where abs(pool - (sphere_total + bonus_awarded)) > 0.01) then 'yes ✅' else 'mismatch ⚠️' end
) t order by ord;
