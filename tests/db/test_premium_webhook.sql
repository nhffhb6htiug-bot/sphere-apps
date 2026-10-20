-- Premium status (production rule, copied verbatim) + webhook duplicate protection. Isolated fixture, synthetic data.
create table public.profiles (id uuid primary key, role text);
create table public.sp_subscriptions (user_id uuid, plan text, status text, started_at timestamptz, current_period_end timestamptz, last_fee_id uuid, updated_at timestamptz);
create table public.sp_webhook_events (event_id text primary key, provider text default 'razorpay', event_type text, received_at timestamptz default now(), processed_at timestamptz, status text default 'received', note text);
-- production definition of sp_is_premium_client (Part 34 read-only copy)
create or replace function public.sp_is_premium_client(p_user uuid) returns boolean language sql stable security definer set search_path to 'public' as $function$
  select exists (select 1 from public.sp_subscriptions s join public.profiles p on p.id = s.user_id
                  where s.user_id = p_user and s.plan = 'client_premium' and s.status = 'active' and s.current_period_end > now()
                    and upper(btrim(coalesce(p.role, ''))) = 'CLIENT');
$function$;
insert into public.profiles values ('00000000-0000-0000-0000-000000000001','CLIENT'),('00000000-0000-0000-0000-000000000002','CLIENT'),
  ('00000000-0000-0000-0000-000000000003','CLIENT'),('00000000-0000-0000-0000-000000000004','EDITOR'),('00000000-0000-0000-0000-000000000005','CLIENT');
insert into public.sp_subscriptions (user_id, plan, status, current_period_end) values
  ('00000000-0000-0000-0000-000000000001','client_premium','active', now() + interval '10 days'),
  ('00000000-0000-0000-0000-000000000002','client_premium','active', now() - interval '1 minute'),
  ('00000000-0000-0000-0000-000000000003','client_premium','cancelled', now() + interval '10 days'),
  ('00000000-0000-0000-0000-000000000004','client_premium','active', now() + interval '10 days'),
  ('00000000-0000-0000-0000-000000000005','pro','active', now() + interval '10 days');
do $$ declare ok boolean;
begin
  if not public.sp_is_premium_client('00000000-0000-0000-0000-000000000001') then raise exception 'P1 FAIL'; end if; raise notice 'PASS P1 active Premium client → premium';
  if public.sp_is_premium_client('00000000-0000-0000-0000-000000000002') then raise exception 'P2 FAIL'; end if; raise notice 'PASS P2 expired 1 minute ago → not premium (badge disappears)';
  if public.sp_is_premium_client('00000000-0000-0000-0000-000000000003') then raise exception 'P3 FAIL'; end if; raise notice 'PASS P3 cancelled → not premium';
  if public.sp_is_premium_client('00000000-0000-0000-0000-000000000004') then raise exception 'P4 FAIL'; end if; raise notice 'PASS P4 an editor with a client_premium row → not premium';
  if public.sp_is_premium_client('00000000-0000-0000-0000-000000000005') then raise exception 'P5 FAIL'; end if; raise notice 'PASS P5 Sphere Pro (editor plan) is not Client Premium';
  insert into public.sp_webhook_events (event_id, event_type) values ('evt_test_1', 'payment.captured');
  ok := false; begin insert into public.sp_webhook_events (event_id, event_type) values ('evt_test_1', 'payment.captured'); exception when unique_violation then ok := true; end;
  if not ok then raise exception 'W1 FAIL duplicate event accepted'; end if; raise notice 'PASS W1 the same webhook event id is refused the second time (23505 → duplicate, nothing processed twice)';
end $$;
