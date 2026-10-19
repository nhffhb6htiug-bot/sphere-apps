-- =====================================================================
-- SPHERE — BLOCK ALSO PROTECTS THE PHONE NUMBER (Part 22)
-- Run in: Supabase → SQL Editor → + → paste → Run.  Safe to run again. Deletes NO data.
--
-- Before: a person who was blocked could still unlock (free or ₹5) and see the blocker's phone
-- number, and a number unlocked earlier stayed visible after a block. Now, while either person
-- has blocked the other: the number is not shown, cannot be unlocked, and no ₹5 payment can
-- start (nothing is charged, no free access is used). Unblocking restores the normal rules.
-- Grants and payments already in the database are NOT changed.
-- =====================================================================
begin;

create or replace function public.sp_is_blocked_pair(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.sp_blocks
                 where (blocker_id = a and blocked_id = b) or (blocker_id = b and blocked_id = a));
$$;
revoke all on function public.sp_is_blocked_pair(uuid, uuid) from public, anon, authenticated;

create or replace function public.sp_contact_status(p_target uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare me uuid := auth.uid(); why text; ok boolean; pend record;
begin
  if me is null then raise exception 'Please log in.'; end if;
  if public.sp_is_blocked_pair(me, p_target) then        -- Part 22: a block hides the number, even if it was unlocked before
    return jsonb_build_object('eligible', false, 'reason', 'This contact is not available.', 'unlocked', false, 'phone', null, 'blocked', true,
      'free_total', coalesce((public.sp_mon_cfg('contact_access')->>'free')::int, 7), 'free_left', public.sp_contact_free_left(me),
      'price', coalesce((public.sp_mon_cfg('contact_access')->>'price')::numeric, 5), 'pending_fee', null);
  end if;
  why := public.sp_contact_check(me, p_target);
  ok := exists (select 1 from public.sp_contact_grants where viewer_id = me and target_id = p_target);
  select id, status, utr into pend from public.sp_fee_payments where user_id = me and target_user = p_target and kind = 'contact_unlock' and status = 'pending' limit 1;
  return jsonb_build_object(
    'eligible', why is null, 'reason', why, 'unlocked', ok,
    'phone', case when ok then (select phone from public.profiles where id = p_target) end,
    'free_total', coalesce((public.sp_mon_cfg('contact_access')->>'free')::int, 7),
    'free_left', public.sp_contact_free_left(me),
    'price', coalesce((public.sp_mon_cfg('contact_access')->>'price')::numeric, 5),
    'pending_fee', case when pend.id is null then null else jsonb_build_object('id', pend.id, 'utr', pend.utr) end);
end $$;

create or replace function public.sp_contact_unlock(p_target uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); why text; left_n int;
begin
  if me is null then raise exception 'Please log in.'; end if;
  if public.sp_is_blocked_pair(me, p_target) then raise exception 'This contact is not available.'; end if;   -- Part 22: blocked → no unlock, nothing charged
  perform pg_advisory_xact_lock(hashtext('sp_contact:' || me::text));      -- one unlock at a time per user
  if exists (select 1 from public.sp_contact_grants where viewer_id = me and target_id = p_target) then
    return jsonb_build_object('unlocked', true, 'consumed', false, 'phone', (select phone from public.profiles where id = p_target), 'free_left', public.sp_contact_free_left(me));
  end if;
  why := public.sp_contact_check(me, p_target);
  if why is not null then raise exception '%', why; end if;
  left_n := public.sp_contact_free_left(me);
  if left_n <= 0 then
    return jsonb_build_object('unlocked', false, 'needs_payment', true, 'free_left', 0,
                              'price', coalesce((public.sp_mon_cfg('contact_access')->>'price')::numeric, 5));
  end if;
  insert into public.sp_contact_grants (viewer_id, target_id, source) values (me, p_target, 'free') on conflict do nothing;
  return jsonb_build_object('unlocked', true, 'consumed', true, 'source', 'free', 'phone', (select phone from public.profiles where id = p_target), 'free_left', left_n - 1);
end $$;

create or replace function public.sp_contact_pay_start(p_target uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); why text; fid uuid; price numeric := coalesce((public.sp_mon_cfg('contact_access')->>'price')::numeric, 5);
begin
  if me is null then raise exception 'Please log in.'; end if;
  if public.sp_is_blocked_pair(me, p_target) then raise exception 'This contact is not available.'; end if;   -- Part 22: blocked → no unlock, nothing charged
  perform pg_advisory_xact_lock(hashtext('sp_contact:' || me::text));
  if exists (select 1 from public.sp_contact_grants where viewer_id = me and target_id = p_target) then raise exception 'This contact is already unlocked.'; end if;
  why := public.sp_contact_check(me, p_target);
  if why is not null then raise exception '%', why; end if;
  if public.sp_contact_free_left(me) > 0 then raise exception 'You still have free contact accesses — no payment needed.'; end if;
  select id into fid from public.sp_fee_payments where user_id = me and target_user = p_target and kind = 'contact_unlock' and status = 'pending';
  if fid is null then
    insert into public.sp_fee_payments (user_id, kind, amount, target_user) values (me, 'contact_unlock', price, p_target) returning id into fid;
  end if;
  return jsonb_build_object('id', fid, 'amount', price, 'kind', 'contact_unlock');
end $$;

revoke all on function public.sp_contact_status(uuid), public.sp_contact_unlock(uuid), public.sp_contact_pay_start(uuid) from public, anon;
grant execute on function public.sp_contact_status(uuid), public.sp_contact_unlock(uuid), public.sp_contact_pay_start(uuid) to authenticated;

insert into public.sp_schema_versions (version, name)
values ('032', 'Block also protects the phone number: no contact unlock or display between blocked users')
on conflict (version) do update set applied_at = now();

commit;
-- Done. You should see "Success. No rows returned".
