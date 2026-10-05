-- =====================================================================
-- SPHERE — DATABASE SNAPSHOT (read-only, changes nothing)
-- Lists every table + column, security rule, function, trigger and file bucket.
-- After Run: click "Export" (above the result) → "Download CSV" → send the file to Claude.
-- =====================================================================
select kind, name, detail from (
  select 1 as ord, 'TABLE' as kind, c.table_name as name,
         string_agg(c.column_name || ' ' || c.data_type || case when c.is_nullable = 'NO' then ' NOT NULL' else '' end, ', ' order by c.ordinal_position) as detail
  from information_schema.columns c where c.table_schema = 'public' group by c.table_name
  union all
  select 2, 'POLICY', tablename || '.' || policyname,
         cmd || ' to ' || array_to_string(roles, ',') || ' using(' || coalesce(qual, '') || ') check(' || coalesce(with_check, '') || ')'
  from pg_policies where schemaname = 'public'
  union all
  select 3, 'FUNCTION', p.proname,
         '(' || pg_get_function_identity_arguments(p.oid) || ')' || case when p.prosecdef then ' SECURITY DEFINER' else '' end
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'
  union all
  select 4, 'TRIGGER', event_object_table || '.' || trigger_name, string_agg(action_timing || ' ' || event_manipulation, ', ')
  from information_schema.triggers where trigger_schema = 'public' group by event_object_table, trigger_name, action_timing
  union all
  select 5, 'BUCKET', id, case when public then 'public' else 'private' end from storage.buckets
) x order by ord, name;
