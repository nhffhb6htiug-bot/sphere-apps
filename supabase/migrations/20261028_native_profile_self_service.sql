-- Sphere native client: strictly owner-only writes. Never grant SELECT on private profiles.
-- Pre-existing sp_profiles_public(p_ids uuid[]) provides privacy-filtered reads.
create or replace function public.sp_native_profile_save(p_data jsonb)
returns jsonb language plpgsql security definer
set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_old public.profiles%rowtype;
  v_exists boolean := false;
  v_role text;
  v_requested_role text;
  v_name text;
  v_phone text;
  v_email text;
  v_key text;
  v_years integer;
begin
  if v_uid is null then
    raise exception 'Please log in first.' using errcode = '28000';
  end if;
  if p_data is null or pg_catalog.jsonb_typeof(p_data) <> 'object' then
    raise exception 'Invalid profile update.' using errcode = '22023';
  end if;
  -- No role escalation, KYC edits, verification flags, admin or financial fields.
  for v_key in select pg_catalog.jsonb_object_keys(p_data) loop
    if v_key not in ('role','full_name','phone','categories','languages','skills',
      'experience_years','price_range','portfolio_url','sample_video_url') then
      raise exception 'Profile field is not editable: %', v_key using errcode = '42501';
    end if;
  end loop;
  select * into v_old from public.profiles where id = v_uid for update;
  v_exists := found;
  v_role := case when v_exists then upper(pg_catalog.btrim(v_old.role)) else null end;
  if p_data ? 'role' then
    v_requested_role := upper(pg_catalog.btrim(p_data->>'role'));
    if v_requested_role not in ('CLIENT','EDITOR') then
      raise exception 'Role is not permitted.' using errcode = '42501';
    end if;
    if v_role = 'ADMIN' or (v_role = 'EDITOR' and v_requested_role = 'CLIENT') then
      raise exception 'Only Sphere administrators can change this account role.' using errcode = '42501';
    end if;
    v_role := v_requested_role;
  end if;
  if v_role is null or v_role not in ('CLIENT','EDITOR','ADMIN') then
    raise exception 'Choose Client or Editor to continue.' using errcode = '22023';
  end if;
  v_name := case when p_data ? 'full_name' then pg_catalog.btrim(p_data->>'full_name')
    else v_old.full_name end;
  if v_name is null or length(v_name) < 1 or length(v_name) > 100 then
    raise exception 'Enter a valid name.' using errcode = '22023';
  end if;
  v_phone := case when p_data ? 'phone' then pg_catalog.btrim(p_data->>'phone')
    else v_old.phone end;
  if v_phone ~ '^[6-9][0-9]{9}$' then v_phone := '+91' || v_phone; end if;
  if v_phone is null or v_phone !~ '^\+91[6-9][0-9]{9}$' then
    raise exception 'Enter a valid Indian mobile number.' using errcode = '22023';
  end if;
  if p_data ? 'experience_years' and p_data->>'experience_years' is not null then
    v_years := (p_data->>'experience_years')::integer;
    if v_years < 0 or v_years > 80 then
      raise exception 'Experience is outside the supported range.' using errcode = '22023';
    end if;
  end if;
  foreach v_key in array array['categories','languages','skills'] loop
    if p_data ? v_key then
      if pg_catalog.jsonb_typeof(p_data->v_key) <> 'array' or
        pg_catalog.jsonb_array_length(p_data->v_key) > 35 then
        raise exception 'Invalid list field: %',v_key using errcode = '22023';
      end if;
    end if;
  end loop;
  foreach v_key in array array['price_range','portfolio_url','sample_video_url'] loop
    if p_data ? v_key and length(coalesce(p_data->>v_key,'')) > 2048 then
      raise exception 'Field is too long: %',v_key using errcode = '22023';
    end if;
  end loop;
  select email into v_email from auth.users where id = v_uid;
  if not v_exists then
    insert into public.profiles(id,role,full_name,phone,email)
      values(v_uid,v_role,v_name,v_phone,v_email);
  else
    update public.profiles
    set role = v_role,
        full_name = v_name,
        phone = v_phone,
        categories = case when p_data ? 'categories'
          then array(select pg_catalog.jsonb_array_elements_text(p_data->'categories'))
          else categories end,
        languages = case when p_data ? 'languages'
          then array(select pg_catalog.jsonb_array_elements_text(p_data->'languages'))
          else languages end,
        skills = case when p_data ? 'skills'
          then array(select pg_catalog.jsonb_array_elements_text(p_data->'skills'))
          else skills end,
        experience_years = case when p_data ? 'experience_years'
          then v_years else experience_years end,
        price_range = case when p_data ? 'price_range'
          then p_data->>'price_range' else price_range end,
        portfolio_url = case when p_data ? 'portfolio_url'
          then p_data->>'portfolio_url' else portfolio_url end,
        sample_video_url = case when p_data ? 'sample_video_url'
          then p_data->>'sample_video_url' else sample_video_url end,
        phone_verified_at = case when phone is distinct from v_phone
          then null else phone_verified_at end,
        phone_verified_num = case when phone is distinct from v_phone
          then null else phone_verified_num end
    where id = v_uid;
  end if;
  return pg_catalog.jsonb_build_object('ok',true);
end
$function$;

revoke all on function public.sp_native_profile_save(jsonb) from public, anon;
grant execute on function public.sp_native_profile_save(jsonb) to authenticated;
