-- =====================================================================
-- SPHERE 044 — details checked on the verification call are locked; changes only via a ₹29 update request
-- • Admin (PIN) sets experience, price, categories, languages, skills, Mobile/PC: sp_admin_set_editor_details
-- • A verified editor (or one whose details the admin set while the review is pending) cannot change them.
--   Exception: Mobile/PC may be chosen once if it was never set.
-- • Update request: the editor writes what to change (sp_detail_request_draft) and pays ₹29 (fee kind
--   'details_update'); the request appears in Admin → Verification; the admin calls and sets the details.
-- Safe to run again. Deletes NO data.
-- =====================================================================
begin;
alter table public.profiles add column if not exists details_locked_at timestamptz;

do $$ declare c text; begin
  for c in select conname from pg_constraint where conrelid = 'public.sp_fee_payments'::regclass and contype = 'c' and pg_get_constraintdef(oid) ilike '%kind%' loop
    execute format('alter table public.sp_fee_payments drop constraint %I', c);
  end loop;
end $$;
alter table public.sp_fee_payments add constraint sp_fee_payments_kind_status_check check (
  kind = any (array['verification', 'pro', 'client_premium', 'contact_unlock', 'details_update'])
  and status = any (array['pending', 'paid', 'failed', 'cancelled']) and amount > 0);

create table if not exists public.sp_detail_requests (
  id uuid primary key default gen_random_uuid(),
  editor_id uuid not null references public.profiles(id) on delete cascade,
  fee_id uuid references public.sp_fee_payments(id),
  note text,
  status text not null default 'open' check (status in ('open', 'done', 'cancelled')),
  created_at timestamptz not null default now(), done_at timestamptz, done_by uuid);
create unique index if not exists sp_detail_requests_fee on public.sp_detail_requests (fee_id) where fee_id is not null;
create index if not exists sp_detail_requests_open on public.sp_detail_requests (status, created_at);
alter table public.sp_detail_requests enable row level security;
revoke all on public.sp_detail_requests from anon, authenticated;
grant select on public.sp_detail_requests to authenticated;
drop policy if exists sp_detail_requests_own on public.sp_detail_requests;
create policy sp_detail_requests_own on public.sp_detail_requests for select to authenticated using (editor_id = auth.uid());

create table if not exists sphere_private.detail_request_drafts (user_id uuid primary key, note text not null, at timestamptz not null default now());
revoke all on sphere_private.detail_request_drafts from public, anon, authenticated;

create or replace function public.sp_detail_request_draft(p_note text) returns boolean
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); n text := left(btrim(coalesce(p_note, '')), 500);
begin
  if me is null then raise exception 'Please log in.'; end if;
  if not exists (select 1 from public.profiles where id = me and upper(btrim(role)) = 'EDITOR' and coalesce(is_verified, false)) then
    raise exception 'Update requests are for verified editors.';
  end if;
  if length(n) < 5 then raise exception 'Please write what you want to change.'; end if;
  insert into sphere_private.detail_request_drafts (user_id, note, at) values (me, n, now())
  on conflict (user_id) do update set note = excluded.note, at = now();
  return true;
end $$;
revoke all on function public.sp_detail_request_draft(text) from public, anon;
grant execute on function public.sp_detail_request_draft(text) to authenticated;

-- the lock (runs after the other profile guards)
create or replace function sphere_private.sp_editor_details_lock() returns trigger
language plpgsql set search_path = public as $$
begin
  if current_user not in ('authenticated', 'anon') then return new; end if;     -- server functions / SQL editor
  if (coalesce(old.is_verified, false) or (old.details_locked_at is not null and old.verification_status = 'pending')) and (
       new.experience_years is distinct from old.experience_years or new.price_range is distinct from old.price_range
    or new.categories is distinct from old.categories or new.languages is distinct from old.languages
    or new.skills is distinct from old.skills
    or (new.edit_device is distinct from old.edit_device and old.edit_device is not null)) then
    raise exception 'These details were checked by Sphere and are locked. To change them, send an update request (₹29) from your Editor Application page.';
  end if;
  return new;
end $$;
drop trigger if exists zz_sp_editor_details_lock on public.profiles;
create trigger zz_sp_editor_details_lock before update on public.profiles for each row execute function sphere_private.sp_editor_details_lock();

-- admin sets the checked details (PIN, audit, editor notified, request closed)
create or replace function public.sp_admin_set_editor_details(p_user uuid, p_details jsonb, p_pin text, p_request uuid default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o record; e int; pr text; c text[]; l text[]; sk text[]; d text;
begin
  perform public.sp_admin_only();
  perform public.sp_admin_check_pin(p_pin);
  select * into o from public.profiles where id = p_user for update;
  if not found or upper(btrim(coalesce(o.role, ''))) <> 'EDITOR' then raise exception 'Editor not found.'; end if;
  e  := case when p_details ? 'experience_years' then nullif(p_details->>'experience_years', '')::int else o.experience_years end;
  if e is not null and (e < 0 or e > 50) then raise exception 'Experience must be between 0 and 50 years.'; end if;
  pr := case when p_details ? 'price_range' then nullif(left(btrim(p_details->>'price_range'), 40), '') else o.price_range end;
  c  := case when p_details ? 'categories' then array(select left(btrim(x), 40) from jsonb_array_elements_text(p_details->'categories') x where btrim(x) <> '') else o.categories end;
  l  := case when p_details ? 'languages' then array(select left(btrim(x), 30) from jsonb_array_elements_text(p_details->'languages') x where btrim(x) <> '') else o.languages end;
  sk := case when p_details ? 'skills' then array(select left(btrim(x), 40) from jsonb_array_elements_text(p_details->'skills') x where btrim(x) <> '' limit 20) else o.skills end;
  d  := case when p_details ? 'edit_device' then nullif(p_details->>'edit_device', '') else o.edit_device end;
  if coalesce(array_length(c, 1), 0) = 0 then raise exception 'Choose at least one category.'; end if;
  if coalesce(array_length(l, 1), 0) = 0 then raise exception 'Choose at least one language.'; end if;
  if d is not null and d not in ('mobile', 'pc', 'both') then raise exception 'Device must be Mobile, PC or Both.'; end if;
  update public.profiles set experience_years = e, price_range = pr, categories = c, languages = l, skills = sk, edit_device = d, details_locked_at = now()
   where id = p_user;
  perform public.sp_audit_write('editor_details', 'user', p_user::text, null, p_user, null, null, 'Details checked by Sphere',
    jsonb_build_object('old', jsonb_build_object('experience_years', o.experience_years, 'price_range', o.price_range, 'categories', o.categories, 'languages', o.languages, 'skills', o.skills, 'edit_device', o.edit_device),
                       'new', jsonb_build_object('experience_years', e, 'price_range', pr, 'categories', c, 'languages', l, 'skills', sk, 'edit_device', d)));
  if p_request is not null then
    update public.sp_detail_requests set status = 'done', done_at = now(), done_by = auth.uid() where id = p_request and editor_id = p_user and status = 'open';
  end if;
  insert into public.sp_notifications (user_id, title, body, category)
  values (p_user, 'Your profile details were updated ✏️', 'The Sphere team checked and updated your experience / price / categories. You can see them in your Editor Application.', 'verification');
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.sp_admin_set_editor_details(uuid, jsonb, text, uuid) from public, anon;
grant execute on function public.sp_admin_set_editor_details(uuid, jsonb, text, uuid) to authenticated;

create or replace function public.sp_admin_detail_requests() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform public.sp_admin_only();
  return coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'editor_id', r.editor_id, 'name', p.full_name, 'note', r.note, 'at', r.created_at) order by r.created_at)
    from public.sp_detail_requests r join public.profiles p on p.id = r.editor_id where r.status = 'open'), '[]'::jsonb);
end $$;
revoke all on function public.sp_admin_detail_requests() from public, anon;
grant execute on function public.sp_admin_detail_requests() to authenticated;

-- fee: add the 'details_update' kind to sp_fee_start and sp_fee_apply (inserted before their final branches; checked)
do $$
declare src text; nsrc text;
begin
  src := pg_get_functiondef('public.sp_fee_start(text)'::regprocedure);
  if position('details_update' in src) = 0 then
    nsrc := regexp_replace(src, '(\s)else(\s+)raise exception ''Unknown payment\.'';',
      E'\\1elsif p_kind = ''details_update'' then\n    if not coalesce(p.is_verified, false) then raise exception ''Update requests are for verified editors. Before verification you can still edit your application.''; end if;\n    if exists (select 1 from public.sp_detail_requests where editor_id = me and status = ''open'') then raise exception ''You already have an update request with the Sphere team. They will call you.''; end if;\n    if not exists (select 1 from sphere_private.detail_request_drafts where user_id = me) then raise exception ''Please write what you want to change first.''; end if;\n    price := coalesce((public.sp_mon_cfg(''verification'')->>''price'')::numeric, 29);\n  else\\2raise exception ''Unknown payment.'';');
    if nsrc = src then raise exception '044: could not extend sp_fee_start'; end if;
    execute nsrc;
  end if;
  src := pg_get_functiondef('public.sp_fee_apply(uuid)'::regprocedure);
  if position('details_update' in src) = 0 then
    nsrc := regexp_replace(src, 'elsif f\.kind = ''contact_unlock'' then',
      E'elsif f.kind = ''details_update'' then\ninsert into public.sp_detail_requests (editor_id, fee_id, note)\nselect f.user_id, f.id, (select note from sphere_private.detail_request_drafts where user_id = f.user_id)\nwhere not exists (select 1 from public.sp_detail_requests where fee_id = f.id);\ndelete from sphere_private.detail_request_drafts where user_id = f.user_id;\nperform public.sp_ed_notify_admins(''Details update request ✏️'',\ncoalesce(nullif((select full_name from public.profiles where id = f.user_id), ''''), ''An editor'') || '' paid ₹'' || f.amount || '' to update their checked details. Admin Panel → Verification → Update requests.'');\ninsert into public.sp_notifications (user_id, title, body) values (f.user_id, ''Update request received ✅'',\n''The Sphere team will call you, check the changes and update your details.'');\nelsif f.kind = ''contact_unlock'' then');
    if nsrc = src then raise exception '044: could not extend sp_fee_apply'; end if;
    execute nsrc;
  end if;
end $$;

insert into public.sp_schema_versions (version, name) values ('044', 'Checked editor details are locked; admin edits them; ₹29 update requests')
on conflict (version) do update set applied_at = now();
commit;
