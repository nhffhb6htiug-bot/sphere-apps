-- =====================================================================
-- SPHERE — PART 10 CHECK (read-only, changes nothing)
-- Run after 010_project_files.sql. Every line should end with ✅
-- =====================================================================
select item, result from (
  select 1 as ord, 'Parts installed' as item,
         (select string_agg(version, ', ' order by version) from public.sp_schema_versions) ||
         case when exists (select 1 from public.sp_schema_versions where version = '010') then ' ✅' else ' ❌ (run 010_project_files.sql)' end as result
  union all
  select 2, 'Private bucket sphere-project',
         case when exists (select 1 from storage.buckets where id = 'sphere-project' and public = false) then 'private ✅' else 'MISSING or public ❌' end
  union all
  select 3, 'Storage rules (read / upload / delete)',
         (select count(*) from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname like 'sp_project_files_%')::text || ' of 3 ' ||
         case when (select count(*) from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname like 'sp_project_files_%') = 3 then '✅' else '❌' end
  union all
  select 4, 'File list (private)',
         case when exists (select 1 from pg_class where relname = 'sp_project_files' and relrowsecurity) then 'ready ✅' else 'MISSING ❌' end
  union all
  select 5, 'Upload limit per file',
         least(public.sp_setting_int('file_max_mb', 50), 50) || ' MB (bigger → link) ✅'
  union all
  select 6, 'Files shared',
         (select count(*) from public.sp_project_files where kind = 'client_file' and status = 'ready')::text || ' (' ||
         (select count(*) from public.sp_project_files where kind = 'client_file' and source = 'link' and status = 'ready')::text || ' links) ✅'
  union all
  select 7, 'Previews sent',
         (select count(*) from public.sp_project_files where kind = 'preview' and status = 'ready')::text || ' ✅'
  union all
  select 8, 'Uploads stuck (older than 6 h)',
         (select count(*) from public.sp_project_files where status = 'uploading' and created_at < now() - interval '6 hours')::text ||
         case when (select count(*) from public.sp_project_files where status = 'uploading' and created_at < now() - interval '6 hours') = 0 then ' ✅' else ' ⚠️ (they were never finished)' end
) t order by ord;
