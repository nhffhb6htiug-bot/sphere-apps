-- =====================================================================
-- SPHERE — PART 4 CHECK (read-only, changes nothing)
-- Run after 004_editor_profile.sql. Every line should end with ✅
-- =====================================================================
select item, result from (
  select 1 as ord, 'Parts installed' as item,
         (select string_agg(version, ', ' order by version) from public.sp_schema_versions) ||
         case when exists (select 1 from public.sp_schema_versions where version = '004') then ' ✅' else ' ❌ (run 004_editor_profile.sql)' end as result
  union all
  select 2, 'New editor columns',
         (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'profiles'
            and column_name in ('bio','availability','verification_status','verification_fee_status','verification_fee_ref','verification_fee_at','verification_reviewed_at'))::text
         || ' of 7 ' || case when (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'profiles'
            and column_name in ('bio','availability','verification_status','verification_fee_status','verification_fee_ref','verification_fee_at','verification_reviewed_at')) = 7 then '✅' else '❌' end
  union all
  select 3, 'Verification triggers',
         (select count(*) from pg_trigger where tgname in ('sp_ed_profile_sync','sp_ed_profile_after'))::text || ' of 2 ' ||
         case when (select count(*) from pg_trigger where tgname in ('sp_ed_profile_sync','sp_ed_profile_after')) = 2 then '✅' else '❌' end
  union all
  select 4, 'Editors by verification state',
         coalesce((select string_agg(s || ': ' || n, ', ' order by s) from (
            select coalesce(verification_status, '(none)') as s, count(*) as n from public.profiles
            where upper(btrim(role)) = 'EDITOR' group by 1) x), 'no editors yet') || ' ✅'
  union all
  select 5, 'Fees waiting for a check',
         (select count(*) from public.profiles where verification_fee_status = 'submitted')::text || ' ✅'
  union all
  select 6, 'Verified tick and status agree',
         (select count(*) from public.profiles where upper(btrim(role)) = 'EDITOR'
            and (is_verified is true) <> (verification_status = 'approved'))::text ||
         case when (select count(*) from public.profiles where upper(btrim(role)) = 'EDITOR'
            and (is_verified is true) <> (verification_status = 'approved')) = 0 then ' mismatches ✅' else ' mismatches ⚠️' end
) t order by ord;
