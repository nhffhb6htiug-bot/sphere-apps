-- =====================================================================
-- SPHERE — PART 9 CHECK (read-only, changes nothing)
-- Run after 009_chat_moderation.sql. Every line should end with ✅
-- =====================================================================
select item, result from (
  select 1 as ord, 'Parts installed' as item,
         (select string_agg(version, ', ' order by version) from public.sp_schema_versions) ||
         case when exists (select 1 from public.sp_schema_versions where version = '009') then ' ✅' else ' ❌ (run 009_chat_moderation.sql)' end as result
  union all
  select 2, 'Project chat (messages linked to projects)',
         case when exists (select 1 from information_schema.columns where table_name = 'sp_messages' and column_name = 'job_id')
               and exists (select 1 from pg_trigger where tgname = 'sp_chat_project_guard') then 'on ✅' else 'MISSING ❌' end
  union all
  select 3, 'Hold suspicious messages',
         case when exists (select 1 from pg_trigger where tgname = 'zzz_sp_chat_hold') then 'on ✅' else 'MISSING ❌' end
  union all
  select 4, 'UPI / bank details hidden',
         case when (select (public.sp_mod_mask('pay me at rahul@okaxis')).hard) and (select (public.sp_mod_mask('acc 123456789012')).hard)
              then 'yes ✅' else 'old checker ⚠️ (run 009 again)' end
  union all
  select 5, '"Instagram reel" still allowed',
         case when not (select (public.sp_mod_mask('Edit a 60 sec Instagram reel')).soft) then 'yes ✅' else 'no ⚠️' end
  union all
  select 6, 'Messages waiting for admin',
         (select count(*) from public.sp_msg_holds where status = 'pending')::text ||
         case when (select count(*) from public.sp_msg_holds where status = 'pending') = 0 then ' ✅' else ' ⚠️ open Admin Panel' end
  union all
  select 7, 'Checked by AI so far',
         (select count(*) from public.sp_msg_holds where ai_checked_at is not null)::text || ' ✅'
) t order by ord;
