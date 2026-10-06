-- =====================================================================
-- SPHERE — PART 5 CHECK (read-only, changes nothing)
-- Run after 005_job_posting.sql. Every line should end with ✅
-- =====================================================================
select item, result from (
  select 1 as ord, 'Parts installed' as item,
         (select string_agg(version, ', ' order by version) from public.sp_schema_versions) ||
         case when exists (select 1 from public.sp_schema_versions where version = '005') then ' ✅' else ' ❌ (run 005_job_posting.sql)' end as result
  union all
  select 2, 'New job columns',
         (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'sp_jobs'
            and column_name in ('title','video_length','video_format','style_notes','reference_links','revisions_expected','ai_assisted'))::text || ' of 7 ' ||
         case when (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'sp_jobs'
            and column_name in ('title','video_length','video_format','style_notes','reference_links','revisions_expected','ai_assisted')) = 7 then '✅' else '❌' end
  union all
  select 3, 'Drafts table (private)',
         case when exists (select 1 from pg_class where relname = 'sp_job_drafts' and relrowsecurity) then 'ready, private ✅' else 'MISSING ❌' end
  union all
  select 4, 'Contact check on job title / style / references',
         case when exists (select 1 from pg_trigger t join pg_class c on c.oid = t.tgrelid where c.relname = 'sp_jobs' and t.tgname = 'zz_sp_mod_guard'
                           and pg_get_triggerdef(t.oid) like '%title%') then 'on ✅' else 'old version ⚠️ (run 005 again)' end
  union all
  select 5, '"Instagram reel" no longer a warning word',
         case when (select (public.sp_mod_mask('Edit a 60 sec Instagram reel')).soft) = false then 'fixed ✅' else 'still warns ⚠️' end
  union all
  select 6, 'Jobs posted with Sphere AI',
         (select count(*) from public.sp_jobs where ai_assisted)::text || ' ✅'
  union all
  select 7, 'Drafts saved',
         (select count(*) from public.sp_job_drafts)::text || ' ✅'
) t order by ord;
