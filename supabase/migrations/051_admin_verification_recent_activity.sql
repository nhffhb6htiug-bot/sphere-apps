begin;
-- Mirror of the admin-only verification RPC deployed to Sphere on 2026-10-29.
CREATE OR REPLACE FUNCTION public.sp_admin_verifications()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform public.sp_admin_only();
  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id', p.id, 'name', p.full_name, 'phone', p.phone, 'email', p.email,
        'categories', p.categories, 'languages', p.languages, 'skills', p.skills,
        'experience', p.experience_years, 'price', p.price_range,
        'sample', p.sample_video_url, 'portfolio', p.portfolio_url, 'bio', p.bio,
        'status', coalesce(p.verification_status, 'pending'), 'note', p.verification_note,
        'fee_status', coalesce(p.verification_fee_status, 'unpaid'),
        'fee_ref', p.verification_fee_ref, 'fee_at', p.verification_fee_at,
        'avatar', p.avatar_url, 'proof_video', p.proof_video_url,
        'proof_at', p.proof_video_at, 'joined', p.created_at,
        'last_login', au.last_sign_in_at, 'last_seen', pres.last_seen_at,
        'last_activity', greatest(
          p.proof_video_at, p.verification_fee_at, au.last_sign_in_at,
          pres.last_seen_at, p.created_at
        ),
        'works', (select count(*) from public.sp_jobs j
                 where j.assigned_editor = p.id
                   and j.status in ('in-progress', 'delivered', 'approved', 'closed'))
      )
      order by greatest(
        p.proof_video_at, p.verification_fee_at, au.last_sign_in_at,
        pres.last_seen_at, p.created_at
      ) desc nulls last, p.id
    )
    from public.profiles p
    left join auth.users au on au.id = p.id
    left join public.sp_presence pres on pres.user_id = p.id
    where upper(btrim(p.role)) = 'EDITOR'
      and not coalesce(p.is_verified, false)
      and coalesce(p.verification_status, 'pending') in ('pending', 'rejected')
  ), '[]'::jsonb);
end $function$;

revoke all on function public.sp_admin_verifications() from public, anon;
grant execute on function public.sp_admin_verifications() to authenticated;
insert into public.sp_schema_versions(version,name)
values ('051','Admin verification queue: latest login, activity and video sorting')
on conflict (version) do update set applied_at = now();
commit;
