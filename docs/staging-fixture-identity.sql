-- Applied to sphere-staging only, not production.
create or replace function public.sp_core_whoami() returns jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('id',id,'role',role,'suspended',suspended,'qa_fixture',
 id in ('40000000-0000-4000-8000-000000000001'::uuid,'40000000-0000-4000-8000-000000000002'::uuid,'40000000-0000-4000-8000-000000000003'::uuid,'40000000-0000-4000-8000-000000000004'::uuid))
 from public.profiles where id=auth.uid()
$$;
revoke all on function public.sp_core_whoami() from public,anon;
grant execute on function public.sp_core_whoami() to authenticated;
