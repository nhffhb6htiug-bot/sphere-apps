begin;
-- Prevent clients from forging screenshot receipt or paid/waived verification state.
create or replace function public.sp_editor_free_proof_guard()
returns trigger language plpgsql set search_path='' as $$
begin
  if current_user in ('authenticated','anon') then
    if new.proof_screenshot_path is distinct from old.proof_screenshot_path
       or new.proof_screenshot_at is distinct from old.proof_screenshot_at then
      raise exception 'Please submit your screenshot through the verification form';
    end if;
    if new.verification_fee_status is distinct from old.verification_fee_status
       and new.verification_fee_status in ('waived','confirmed') then
      raise exception 'Only Sphere can confirm or waive verification fees';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists a6_sp_editor_free_proof_guard on public.profiles;
create trigger a6_sp_editor_free_proof_guard
before update on public.profiles for each row execute function public.sp_editor_free_proof_guard();
revoke all on function public.sp_editor_free_proof_guard() from public,anon,authenticated;

-- Stop new payment orders and UTR attempts created against pre-offer pending fees.
create or replace function public.sp_editor_free_payment_guard()
returns trigger language plpgsql set search_path='' as $$
begin
  if new.kind='verification' and new.status='pending'
     and exists(select 1 from public.sp_editor_offer_slots where editor_id=new.user_id)
     and (tg_op='INSERT'
          or new.order_id is distinct from old.order_id
          or new.utr is distinct from old.utr) then
    raise exception 'This editor is in the first 50: verification is FREE; do not create a paid order';
  end if;
  return new;
end $$;
drop trigger if exists a6_sp_editor_free_payment_guard on public.sp_fee_payments;
create trigger a6_sp_editor_free_payment_guard
before insert or update of order_id, utr on public.sp_fee_payments
for each row execute function public.sp_editor_free_payment_guard();
revoke all on function public.sp_editor_free_payment_guard() from public,anon,authenticated;
insert into public.sp_schema_versions(version,name)
values('offer50_v3','Secure free verification proofs and block legacy payment orders')
on conflict (version) do update set applied_at=now();
commit;