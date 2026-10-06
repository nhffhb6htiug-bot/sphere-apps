-- =====================================================================
-- SPHERE — PART 4: EDITOR PROFILE + VERIFICATION
-- Run in: Supabase → SQL Editor → + → paste → Run.  Safe to run again.
-- Needs 002 + 003 first. Adds columns; does not delete anything.
--
-- Adds to profiles:
--   bio, availability (available / busy / away)
--   verification_status      not_applied / pending / approved / rejected
--   verification_fee_status  unpaid / submitted / confirmed   (+ fee_ref = UPI transaction id)
-- Keeps working exactly as before:
--   • sp_verify_editor (✔ tick + code)  → status becomes "approved" automatically
--   • sp_unverify_editor (remove tick)   → status becomes "pending" (re-check)
-- New for admins: sp_ed_review  → confirm fee / fee not found / reject / re-open
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1) New profile columns
-- ---------------------------------------------------------------------
alter table public.profiles add column if not exists bio text;
alter table public.profiles add column if not exists availability text not null default 'available';
alter table public.profiles add column if not exists verification_status text;
alter table public.profiles add column if not exists verification_fee_status text;
alter table public.profiles add column if not exists verification_fee_ref text;
alter table public.profiles add column if not exists verification_fee_at timestamptz;
alter table public.profiles add column if not exists verification_reviewed_at timestamptz;

alter table public.profiles drop constraint if exists sp_ed_availability_chk;
alter table public.profiles add  constraint sp_ed_availability_chk check (availability in ('available', 'busy', 'away'));
alter table public.profiles drop constraint if exists sp_ed_vstatus_chk;
alter table public.profiles add  constraint sp_ed_vstatus_chk check (verification_status is null or verification_status in ('not_applied', 'pending', 'approved', 'rejected'));
alter table public.profiles drop constraint if exists sp_ed_fee_chk;
alter table public.profiles add  constraint sp_ed_fee_chk check (verification_fee_status is null or verification_fee_status in ('unpaid', 'submitted', 'confirmed'));
alter table public.profiles drop constraint if exists sp_ed_bio_chk;
alter table public.profiles add  constraint sp_ed_bio_chk check (bio is null or char_length(bio) <= 300);

-- existing editors get a status that matches today's data
update public.profiles
set verification_status = case
      when is_verified is true then 'approved'
      when coalesce(categories::text, '') not in ('', '{}', '[]', 'null') then 'pending'
      else 'not_applied' end
where verification_status is null and upper(btrim(role)) = 'EDITOR';

-- ---------------------------------------------------------------------
-- 2) Keep status in step with the ✔ tick + stop editors approving themselves
--    (SECURITY INVOKER on purpose: current_user tells app/API from admin tools)
-- ---------------------------------------------------------------------
create or replace function public.sp_ed_profile_sync()
returns trigger language plpgsql set search_path = public as $$
declare
  from_api     boolean := current_user in ('authenticated', 'anon');
  caller_admin boolean := auth.uid() is not null and public.sp_core_has_role('ADMIN');
begin
  -- the ✔ tick decides the final state
  if NEW.is_verified is true and OLD.is_verified is not true then
    NEW.verification_status := 'approved';
    NEW.verification_reviewed_at := now();
  elsif NEW.is_verified is not true and OLD.is_verified is true then
    if NEW.verification_status is null or NEW.verification_status = 'approved' then
      NEW.verification_status := 'pending';     -- tick removed → needs a new check
    end if;
  end if;

  if from_api and not caller_admin then
    if NEW.verification_status is distinct from OLD.verification_status
       and NEW.verification_status is distinct from 'pending' then
      raise exception 'Only Sphere can approve or reject a verification.';
    end if;
    if NEW.verification_fee_status is distinct from OLD.verification_fee_status
       and NEW.verification_fee_status is distinct from 'submitted' then
      raise exception 'Only Sphere can confirm the verification fee.';
    end if;
    if NEW.verification_fee_status = 'submitted' and OLD.verification_fee_status is distinct from 'submitted' then
      NEW.verification_fee_at := now();
    end if;
    NEW.verification_reviewed_at := OLD.verification_reviewed_at;
  end if;
  return NEW;
end $$;

drop trigger if exists sp_ed_profile_sync on public.profiles;
create trigger sp_ed_profile_sync before update on public.profiles
  for each row execute function public.sp_ed_profile_sync();

-- ---------------------------------------------------------------------
-- 3) Tell admins when an editor applies or says "I paid ₹29"
-- ---------------------------------------------------------------------
create or replace function public.sp_ed_notify_admins(p_title text, p_body text)
returns void language sql security definer set search_path = public as $$
  insert into public.sp_notifications (user_id, title, body)
  select id, p_title, p_body from public.profiles where upper(btrim(role)) = 'ADMIN';
$$;
revoke all on function public.sp_ed_notify_admins(text, text) from public, anon, authenticated;

create or replace function public.sp_ed_profile_after()
returns trigger language plpgsql security definer set search_path = public as $$
declare who text := coalesce(nullif(NEW.full_name, ''), 'An editor');
begin
  if auth.uid() is distinct from NEW.id then return null; end if;   -- only when the editor does it themselves
  if NEW.verification_fee_status = 'submitted' and OLD.verification_fee_status is distinct from 'submitted' then
    perform public.sp_ed_notify_admins('Verification fee submitted 💳',
      who || ' says they paid the verification fee. Open Admin Panel → Pending Verification to check it.');
  end if;
  if NEW.verification_status = 'pending' and OLD.verification_status is distinct from 'pending'
     and NEW.is_verified is not true and upper(btrim(NEW.role)) = 'EDITOR' then
    perform public.sp_ed_notify_admins('Editor waiting for verification 🎬',
      who || ' applied for verification. Open Admin Panel → Pending Verification.');
  end if;
  return null;
end $$;

drop trigger if exists sp_ed_profile_after on public.profiles;
create trigger sp_ed_profile_after after update on public.profiles
  for each row execute function public.sp_ed_profile_after();

-- ---------------------------------------------------------------------
-- 4) Admin actions (Admin PIN): confirm fee, fee not found, reject, re-open
--    Approving is still the existing "✔ Verify after call" (sp_verify_editor).
-- ---------------------------------------------------------------------
create or replace function public.sp_ed_review(p_editor uuid, p_action text, p_note text, p_pin text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.sp_core_has_role('ADMIN') then raise exception 'Admins only'; end if;
  perform public.sp_admin_check_pin(p_pin := p_pin);

  if p_action = 'confirm_fee' then
    update public.profiles set verification_fee_status = 'confirmed' where id = p_editor;
    insert into public.sp_notifications (user_id, title, body) values (p_editor, 'Verification fee received ✅',
      'We received your verification fee. Our team will call you for the verification.');
  elsif p_action = 'reject_fee' then
    update public.profiles set verification_fee_status = 'unpaid', verification_fee_ref = null, verification_fee_at = null where id = p_editor;
    insert into public.sp_notifications (user_id, title, body) values (p_editor, 'Payment not found ⚠️',
      coalesce(nullif(btrim(p_note), ''), 'We could not find your verification payment. Please check the transaction ID and submit it again.'));
  elsif p_action = 'reject' then
    if coalesce(btrim(p_note), '') = '' then raise exception 'Please write a reason.'; end if;
    update public.profiles set verification_status = 'rejected', is_verified = false,
           verification_note = btrim(p_note), verification_reviewed_at = now() where id = p_editor;
    insert into public.sp_notifications (user_id, title, body) values (p_editor, 'Verification not approved',
      'Reason: ' || btrim(p_note) || ' — You can update your profile and apply again.');
  elsif p_action = 'reopen' then
    update public.profiles set verification_status = 'pending' where id = p_editor;
  else
    raise exception 'Unknown action: %', p_action;
  end if;
end $$;
revoke all on function public.sp_ed_review(uuid, text, text, text) from public, anon;
grant execute on function public.sp_ed_review(uuid, text, text, text) to authenticated;

-- ---------------------------------------------------------------------
-- 5) Public extra details for editor pages (bio + availability only)
-- ---------------------------------------------------------------------
create or replace view public.sp_editor_public_extra as
  select id, bio, availability from public.profiles where upper(btrim(role)) in ('EDITOR', 'ADMIN');
grant select on public.sp_editor_public_extra to anon, authenticated;

-- ---------------------------------------------------------------------
-- 6) Contact protection also checks the bio (if number block is installed)
-- ---------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_proc where proname = 'sp_mod_guard') then
    execute 'drop trigger if exists zz_sp_mod_guard on public.profiles';
    execute 'create trigger zz_sp_mod_guard before insert or update of full_name, price_range, bio on public.profiles
             for each row execute function public.sp_mod_guard(''full_name,price_range,bio'', ''profile'', ''id'')';
  end if;
end $$;

insert into public.sp_schema_versions (version, name)
values ('004', 'Editor profile + verification (bio, availability, states, ₹29 fee tracking)')
on conflict (version) do update set applied_at = now();

commit;

-- Done. You should see "Success. No rows returned".
