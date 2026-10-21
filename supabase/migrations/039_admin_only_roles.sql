-- =====================================================================
-- SPHERE — ONE ROLE PER ACCOUNT: users cannot switch Client ↔ Editor themselves; only an admin can
-- Owner decision (21 Oct 2026). Choosing the role the first time (sign-up) still works.
-- • sp_protect_profile: the "Client → Become an Editor" path is removed.
-- • sp_admin_set_role(user, role, pin): admin + Admin PIN, Client or Editor only, never your own role and
--   never an admin's; written to the audit log; the person gets a notification.
-- Safe to run again. Deletes NO data.
-- =====================================================================
begin;
create or replace function public.sp_protect_profile()
returns trigger language plpgsql set search_path to 'public' as $function$
begin
  -- SQL Editor / server functions: no restriction
  if current_user not in ('authenticated', 'anon') then return new; end if;
  if public.is_admin() then
    -- admins change verification and roles only through the PIN functions (sp_verify_editor, sp_admin_set_role)
    if tg_op = 'UPDATE' then
      new.role := old.role; new.verification_note := old.verification_note; new.is_verified := old.is_verified;
      new.verification_code := old.verification_code; new.verified_by := old.verified_by; new.verified_at := old.verified_at;
    end if;
    return new;
  end if;
  if tg_op = 'INSERT' then
    if upper(coalesce(new.role, '')) not in ('CLIENT', 'EDITOR') then raise exception 'Invalid role'; end if;
    new.role := upper(new.role); new.is_verified := false; new.verification_code := null; new.razorpay_account_id := null;
    new.verified_by := null; new.verified_at := null; new.verification_note := null;
    return new;
  end if;
  new.id := old.id; new.razorpay_account_id := old.razorpay_account_id;
  if (coalesce(old.role, '') = '' or coalesce(old.phone, '') = '') and upper(coalesce(new.role, '')) in ('CLIENT', 'EDITOR') then
    new.role := upper(new.role);              -- choosing the role the first time (sign-up)
  else
    new.role := old.role;                     -- afterwards only an admin can change it (sp_admin_set_role)
  end if;
  new.is_verified := old.is_verified; new.verification_code := old.verification_code; new.verified_by := old.verified_by;
  new.verified_at := old.verified_at; new.verification_note := old.verification_note;
  return new;
end $function$;

create or replace function public.sp_admin_set_role(p_user uuid, p_role text, p_pin text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r text := upper(btrim(coalesce(p_role, ''))); cur text;
begin
  perform public.sp_admin_only();
  perform public.sp_admin_check_pin(p_pin);
  if r not in ('CLIENT', 'EDITOR') then raise exception 'Role must be Client or Editor.'; end if;
  if p_user = auth.uid() then raise exception 'You cannot change your own role.'; end if;
  select upper(btrim(coalesce(role, ''))) into cur from public.profiles where id = p_user for update;
  if not found then raise exception 'User not found'; end if;
  if cur = 'ADMIN' then raise exception 'An admin''s role can only be changed by the Sphere team in the database.'; end if;
  if cur = r then return jsonb_build_object('role', r, 'changed', false); end if;
  update public.profiles set role = r where id = p_user;
  perform public.sp_audit_write('role', 'user', p_user::text, null, p_user, cur, r, null, '{}'::jsonb);
  insert into public.sp_notifications (user_id, title, body, category)
  values (p_user, 'Your account type changed', 'The Sphere team changed your account to ' || initcap(r) || '. Open Sphere again to see the new screens.', 'admin');
  return jsonb_build_object('role', r, 'changed', true);
end $$;
revoke all on function public.sp_admin_set_role(uuid, text, text) from public, anon;
grant execute on function public.sp_admin_set_role(uuid, text, text) to authenticated;
insert into public.sp_schema_versions (version, name) values ('039', 'One role per account: only an admin can switch Client / Editor')
on conflict (version) do update set applied_at = now();
commit;
