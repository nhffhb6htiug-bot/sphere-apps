-- SPHERE 043 — a suspended client has no Premium benefits or badge while suspended (subscription dates unchanged)
begin;
create or replace function public.sp_is_premium_client(p_user uuid)
returns boolean language sql stable security definer set search_path to 'public' as $function$
  select exists (select 1 from public.sp_subscriptions s join public.profiles p on p.id = s.user_id
                  where s.user_id = p_user and s.plan = 'client_premium' and s.status = 'active' and s.current_period_end > now()
                    and upper(btrim(coalesce(p.role, ''))) = 'CLIENT')
     and not exists (select 1 from public.sp_mod_flags f where f.user_id = p_user and f.is_suspended);
$function$;
insert into public.sp_schema_versions (version, name) values ('043', 'Premium is paused while a client is suspended')
on conflict (version) do update set applied_at = now();
commit;
