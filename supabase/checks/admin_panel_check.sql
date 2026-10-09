-- =====================================================================
-- SPHERE — PART 14 CHECK (read-only, changes nothing)
-- Run after 014_admin_panel.sql. Every line should end with ✅
-- =====================================================================
select item, result from (
  select 1 as ord, 'Parts installed' as item,
         (select string_agg(version, ', ' order by version) from public.sp_schema_versions) ||
         case when exists (select 1 from public.sp_schema_versions where version = '014') then ' ✅' else ' ❌ (run 014_admin_panel.sql)' end as result
  union all
  select 2, 'Audit log table (admins only)',
         case when exists (select 1 from pg_class where relname = 'sp_admin_audit' and relrowsecurity) then 'ready ✅' else 'MISSING ❌' end
  union all
  select 3, 'Automatic audit on admin tables',
         (select count(*) from pg_trigger where tgname = 'zz_sp_audit')::text || ' of 10 ' ||
         case when (select count(*) from pg_trigger where tgname = 'zz_sp_audit') = 10 then '✅' else '❌' end
  union all
  select 4, 'Admin functions (server-checked)',
         (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in
           ('sp_admin_overview','sp_admin_projects','sp_admin_project_detail','sp_admin_project_action','sp_admin_users','sp_admin_user_detail',
            'sp_admin_user_action','sp_admin_verifications','sp_admin_moderation','sp_admin_reveal','sp_admin_payments','sp_admin_audit_list'))::text || ' of 12 ' ||
         case when (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in
           ('sp_admin_overview','sp_admin_projects','sp_admin_project_detail','sp_admin_project_action','sp_admin_users','sp_admin_user_detail',
            'sp_admin_user_action','sp_admin_verifications','sp_admin_moderation','sp_admin_reveal','sp_admin_payments','sp_admin_audit_list')) = 12 then '✅' else '❌' end
  union all
  select 5, 'Not callable without login',
         case when not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                                where n.nspname = 'public' and p.proname like 'sp_admin_%' and has_function_privilege('anon', p.oid, 'execute'))
              then 'yes ✅' else 'some are open to anon ⚠️' end
  union all
  select 6, 'Admins',
         (select count(*) from public.profiles where upper(btrim(role)) = 'ADMIN')::text || ' ✅'
  union all
  select 7, 'Projects flagged suspicious by an admin',
         (select count(*) from public.sp_jobs where admin_flag = 'suspicious')::text || ' ✅'
  union all
  select 8, 'Audit entries so far',
         (select count(*) from public.sp_admin_audit)::text || ' ✅'
) t order by ord;
