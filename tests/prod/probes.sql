-- =====================================================================
-- SPHERE — production safety probes (read-only in effect: everything is ROLLED BACK at the end).
-- Run in Supabase → SQL Editor. The result is one line "PROBES …" with true/false only — no user data.
-- Needs at least one CLIENT, one unverified EDITOR and one contact grant in the database.
-- =====================================================================
do $$
declare
  c uuid; e uuid; g record; s jsonb; t text;
  r1 boolean; r2 boolean; r3 int := 0; r3n int := 0; r4 int; r5 int; r6 boolean := false; r7 boolean := false; r8 boolean := false; r9 int; r10 boolean; r10b boolean := false;
  fn record;
  procedure_as text;
begin
  select id into c from public.profiles where upper(btrim(role)) = 'CLIENT' order by created_at limit 1;
  select id into e from public.profiles where upper(btrim(role)) = 'EDITOR' and not coalesce(is_verified, false) limit 1;
  -- act as the client
  perform set_config('request.jwt.claims', json_build_object('sub', c, 'role', 'authenticated')::text, true);
  perform set_config('request.jwt.claim.sub', c::text, true);
  execute 'set local role authenticated';
  begin update public.profiles set role = 'ADMIN' where id = c; exception when others then null; end;
  execute 'reset role'; select upper(role) <> 'ADMIN' into r1 from public.profiles where id = c;
  -- R3: every admin function refuses a non-admin
  for fn in select p.proname, p.pronargs from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.prokind = 'f' and has_function_privilege('authenticated', p.oid, 'execute')
              and (p.proname ~ '^sp_admin_' or p.proname in ('sp_fee_admin','sp_verify_editor','sp_unverify_editor','sp_payout_item_paid','sp_refund_mark','sp_refund_eligibility','sp_mod_admin_action'))
              and p.proname not in ('sp_admin_check_pin','sp_admin_unlock','sp_admin_pin_status') loop
    r3n := r3n + 1;
    begin
      execute 'set local role authenticated';
      execute format('select %I(%s)', fn.proname, (select coalesce(string_agg('null', ','), '') from generate_series(1, fn.pronargs)));
      execute 'reset role';
    exception when others then execute 'reset role'; r3 := r3 + 1; end;
  end loop;
  execute 'set local role authenticated';
  -- R4: messages between two OTHER people are invisible
  select count(*) into r4 from public.sp_messages where sender_id <> c and receiver_id <> c;
  -- R5: other people's fee payments are invisible
  select count(*) into r5 from public.sp_fee_payments where user_id <> c;
  -- R6: cannot give yourself a subscription
  begin insert into public.sp_subscriptions (user_id, plan, status, current_period_end) values (c, 'client_premium', 'active', now() + interval '30 days'); exception when others then r6 := true; end;
  -- R7: phone column is not readable
  begin perform phone from public.profiles limit 1; exception when others then r7 := true; end;
  -- R8: audit log cannot be written
  begin insert into public.sp_admin_audit (action) values ('probe'); exception when others then r8 := true; end;
  -- R9: webhook events are invisible to users
  select count(*) into r9 from public.sp_webhook_events;
  execute 'reset role';
  -- R2: an unverified editor cannot verify himself
  r2 := true;
  if e is not null then
    perform set_config('request.jwt.claims', json_build_object('sub', e, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', e::text, true);
    execute 'set local role authenticated';
    begin update public.profiles set is_verified = true, verification_status = 'approved' where id = e; exception when others then null; end;
    execute 'reset role'; select not coalesce(is_verified, false) into r2 from public.profiles where id = e;
  end if;
  -- R10: a block hides an already-unlocked number and refuses unlock
  select viewer_id, target_id into g from public.sp_contact_grants limit 1;
  r10 := null;
  if g.viewer_id is not null then
    insert into public.sp_blocks (blocker_id, blocked_id) values (g.target_id, g.viewer_id) on conflict do nothing;
    perform set_config('request.jwt.claims', json_build_object('sub', g.viewer_id, 'role', 'authenticated')::text, true);
    perform set_config('request.jwt.claim.sub', g.viewer_id::text, true);
    execute 'set local role authenticated';
    s := public.sp_contact_status(g.target_id);
    begin perform public.sp_contact_unlock(g.target_id); exception when others then r10b := sqlerrm ilike '%not available%'; end;
    execute 'reset role';
    r10 := (s->>'phone') is null and r10b;
  end if;
  raise exception 'PROBES (rolled back): R1_no_self_admin=% R2_no_self_verify=% R3_admin_fns_refused=%/% R4_foreign_messages_visible=% R5_foreign_fees_visible=% R6_self_subscription_refused=% R7_phone_unreadable=% R8_audit_unwritable=% R9_webhook_events_visible=% R10_block_hides_number=%',
    r1, r2, r3, r3n, r4, r5, r6, r7, r8, r9, r10;
end $$;
