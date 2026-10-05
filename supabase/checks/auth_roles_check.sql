-- =====================================================================
-- SPHERE — PART 2 CHECK (read-only, changes nothing)
-- Run after 003_auth_roles.sql. Every line should end with ✅
-- =====================================================================
select item, result from (
  select 1 as ord, 'Parts installed' as item,
         (select string_agg(version, ', ' order by version) from public.sp_schema_versions) ||
         case when exists (select 1 from public.sp_schema_versions where version = '003') then ' ✅' else ' ❌ (run 003_auth_roles.sql)' end as result
  union all
  select 2, 'Role guard on profiles (Part 1)',
         case when exists (select 1 from pg_trigger where tgname = 'sp_core_profile_guard') then 'on ✅' else 'MISSING ❌ (run 002_foundation.sql)' end
  union all
  select 3, 'Role checks: bids, portfolio, reviews',
         (select count(*) from pg_trigger where tgname = 'sp_core_role_guard')::text || ' of 3 ' ||
         case when (select count(*) from pg_trigger where tgname = 'sp_core_role_guard') = 3 then '✅' else '❌' end
  union all
  select 4, 'Users by role',
         (select string_agg(r || ': ' || n, ', ' order by r) from (
            select coalesce(upper(btrim(role)), '(none)') as r, count(*) as n from public.profiles group by 1) x) || ' ✅'
  union all
  select 5, 'Bids placed by non-editors (old data)',
         (select count(*) from public.sp_applications a join public.profiles p on p.id = a.editor_id
           where upper(btrim(p.role)) not in ('EDITOR', 'ADMIN'))::text ||
         case when (select count(*) from public.sp_applications a join public.profiles p on p.id = a.editor_id
           where upper(btrim(p.role)) not in ('EDITOR', 'ADMIN')) = 0 then ' ✅' else ' ⚠️ (old rows, nothing breaks)' end
) t order by ord;
