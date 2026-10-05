-- =====================================================================
-- SPHERE — PART 1 CHECK (read-only, changes nothing)
-- Run after 002_foundation.sql. Every line should end with ✅
-- =====================================================================
select item, result from (
  select 1 as ord, 'Parts installed' as item,
         coalesce((select string_agg(version || ' ' || name, ' | ' order by version) from public.sp_schema_versions), 'none') || ' ✅' as result
  union all
  select 2, 'Role guard on profiles',
         case when exists (select 1 from pg_trigger where tgname = 'sp_core_profile_guard') then 'on ✅' else 'MISSING ❌' end
  union all
  select 3, 'Number block (done earlier)',
         (select count(*) from pg_trigger where tgname = 'zz_sp_mod_guard')::text || ' of 7 tables ' ||
         case when (select count(*) from pg_trigger where tgname = 'zz_sp_mod_guard') = 7 then '✅' else '❌ (run 001_contact_protection.sql)' end
  union all
  select 4, 'Users by role',
         (select string_agg(r || ': ' || n, ', ' order by r) from (
            select coalesce(upper(btrim(role)), '(none)') as r, count(*) as n from public.profiles group by 1) x) || ' ✅'
  union all
  select 5, 'Users with a missing/unknown role',
         (select count(*) from public.profiles where role is null or upper(btrim(role)) not in ('CLIENT','EDITOR','ADMIN'))::text ||
         case when (select count(*) from public.profiles where role is null or upper(btrim(role)) not in ('CLIENT','EDITOR','ADMIN')) = 0 then ' ✅' else ' ⚠️ (they will be asked to pick a role on login)' end
  union all
  select 6, 'Settings (fees)',
         (select string_agg(key || '=' || value::text, ', ' order by key) from public.sp_settings) || ' ✅'
) t order by ord;
