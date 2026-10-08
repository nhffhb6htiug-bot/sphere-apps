-- =====================================================================
-- SPHERE — PART 8 CHECK (read-only, changes nothing)
-- Run after 008_project_workflow.sql. Every line should end with ✅
-- =====================================================================
select item, result from (
  select 1 as ord, 'Parts installed' as item,
         (select string_agg(version, ', ' order by version) from public.sp_schema_versions) ||
         case when exists (select 1 from public.sp_schema_versions where version = '008') then ' ✅' else ' ❌ (run 008_project_workflow.sql)' end as result
  union all
  select 2, 'Work clock, extensions, timeline tables',
         (select count(*) from pg_class where relname in ('sp_project_work','sp_project_extensions','sp_project_events') and relrowsecurity)::text || ' of 3 ' ||
         case when (select count(*) from pg_class where relname in ('sp_project_work','sp_project_extensions','sp_project_events') and relrowsecurity) = 3 then '✅' else '❌' end
  union all
  select 3, 'Deadline rule',
         case when public.sp_setting_int('work_fixed_hours', 0) > 0 then public.sp_setting_int('work_fixed_hours', 0) || ' hours for every project'
              else '24 h per delivery day from the bid (default ' || public.sp_setting_int('work_default_hours', 24) || ' h)' end
         || ' + ' || public.sp_setting_int('work_grace_hours', 4) || ' h grace ✅'
  union all
  select 4, 'Automatic check every 10 minutes',
         case when exists (select 1 from pg_extension where extname = 'pg_cron') then 'on (pg_cron) ✅'
              else 'off — checked when someone opens the app ✅' end
  union all
  select 5, 'Projects in progress (clock running)',
         (select count(*) from public.sp_project_work where phase = 'active')::text || ' ✅'
  union all
  select 6, 'Previews waiting for the client',
         (select count(*) from public.sp_project_work where phase = 'preview')::text || ' ✅'
  union all
  select 7, 'Late projects',
         (select count(*) from public.sp_project_work where phase = 'active' and is_late)::text ||
         case when (select count(*) from public.sp_project_work where phase = 'active' and is_late) = 0 then ' ✅' else ' ⚠️' end
  union all
  select 8, 'Time requests waiting for the client',
         (select count(*) from public.sp_project_extensions where status = 'pending')::text || ' ✅'
  union all
  select 9, 'Timeline entries',
         (select count(*) from public.sp_project_events)::text || ' ✅'
) t order by ord;
