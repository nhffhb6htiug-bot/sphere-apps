begin;
-- First 50 editor signups keep their number, even after the public banner closes.
create table if not exists public.sp_editor_offer_slots (
  editor_id uuid primary key references public.profiles(id) on delete cascade,
  slot integer not null unique check (slot between 1 and 50),
  assigned_at timestamptz not null default now()
);
create table if not exists public.sp_editor_offer_state (
  singleton boolean primary key default true check (singleton),
  slots_claimed integer not null default 0 check (slots_claimed between 0 and 50)
);
insert into public.sp_editor_offer_state(singleton, slots_claimed) values(true,0)
on conflict(singleton) do nothing;
-- Deterministic registration order for existing editors. Historical paid transactions stay unchanged.
with ranked as (
  select id, row_number() over(order by created_at asc, id asc) as rn
  from public.profiles where upper(btrim(role)) = 'EDITOR'
)
insert into public.sp_editor_offer_slots(editor_id,slot)
select id,rn from ranked where rn <= 50
on conflict(editor_id) do nothing;
update public.sp_editor_offer_state
set slots_claimed = greatest(slots_claimed, (select coalesce(max(slot),0) from public.sp_editor_offer_slots))
where singleton;

revoke all on public.sp_editor_offer_slots, public.sp_editor_offer_state from public,anon,authenticated;
alter table public.sp_editor_offer_slots enable row level security;
alter table public.sp_editor_offer_state enable row level security;

create or replace function public.sp_editor_offer_assign()
returns trigger language plpgsql security definer set search_path='' as $offer$
declare newslot integer;
begin
  if upper(btrim(coalesce(new.role,''))) <> 'EDITOR' then return new; end if;
  if exists (select 1 from public.sp_editor_offer_slots where editor_id=new.id) then return new; end if;
  update public.sp_editor_offer_state set slots_claimed=slots_claimed+1
     where singleton and slots_claimed < 50
     returning slots_claimed into newslot;
  if newslot is not null then
    insert into public.sp_editor_offer_slots(editor_id,slot) values(new.id,newslot)
    on conflict (editor_id) do nothing;
  end if;
  return new;
end $offer$;
drop trigger if exists sp_editor_offer_signup on public.profiles;
create trigger sp_editor_offer_signup after insert or update of role on public.profiles
for each row execute function public.sp_editor_offer_assign();

alter table public.profiles add column if not exists proof_screenshot_path text;
alter table public.profiles add column if not exists proof_screenshot_at timestamptz;

-- Private screenshots (not accessible to other editors).
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('sphere-editor-proof','sphere-editor-proof',false,4194304,array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public=false,file_size_limit=4194304,allowed_mime_types=array['image/jpeg','image/png','image/webp'];
drop policy if exists sp_editor_proof_insert_guard on storage.objects;
create policy sp_editor_proof_insert_guard on storage.objects as restrictive for insert to authenticated
with check (
  bucket_id <> 'sphere-editor-proof'
  or ((storage.foldername(name))[1] = (select auth.uid())::text
      and exists (select 1 from public.profiles p where p.id=auth.uid() and upper(btrim(p.role))='EDITOR'))
);
drop policy if exists sp_editor_proof_read_guard on storage.objects;
create policy sp_editor_proof_read_guard on storage.objects as restrictive for select to authenticated
using (
  bucket_id <> 'sphere-editor-proof'
  or ((storage.foldername(name))[1] = (select auth.uid())::text or public.is_admin())
);
drop policy if exists sp_editor_proof_delete_guard on storage.objects;
create policy sp_editor_proof_delete_guard on storage.objects as restrictive for delete to authenticated
using (bucket_id <> 'sphere-editor-proof' or (storage.foldername(name))[1] = (select auth.uid())::text);

create or replace function public.sp_editor_offer_status()
returns jsonb language plpgsql stable security definer set search_path='' as $offer$
declare me uuid:=auth.uid(); r integer; cnt integer; roleval text;
begin
  if me is null then return jsonb_build_object('is_editor',false,'is_free',false,'show_banner',false); end if;
  select upper(btrim(role)) into roleval from public.profiles where id=me;
  select slot into r from public.sp_editor_offer_slots where editor_id=me;
  select slots_claimed into cnt from public.sp_editor_offer_state where singleton;
  cnt:=coalesce(cnt,50);
  return jsonb_build_object(
    'is_editor',roleval='EDITOR','editor_rank',r,'is_free',roleval='EDITOR' and r is not null,
    'show_banner',roleval='EDITOR' and cnt<50,
    'limit',50,'claimed',cnt,'remaining',greatest(50-cnt,0)
  );
end $offer$;
revoke all on function public.sp_editor_offer_status() from public,anon;
grant execute on function public.sp_editor_offer_status() to authenticated;

create or replace function public.sp_submit_proof_screenshot(p_path text)
returns timestamptz language plpgsql security definer set search_path='' as $offer$
declare me uuid:=auth.uid(); t timestamptz:=now(); v text:=btrim(coalesce(p_path,''));
begin
  if me is null then raise exception 'Please sign in'; end if;
  if not exists(select 1 from public.sp_editor_offer_slots where editor_id=me) then
    raise exception 'Free screenshot submission is reserved for the first 50 editors';
  end if;
  if length(v)>260 or v !~ ('^'||me::text||'/[a-zA-Z0-9_.-]+\\.(png|jpg|jpeg|webp)$') then
    raise exception 'Invalid screenshot path';
  end if;
  if not exists(select 1 from storage.objects where bucket_id='sphere-editor-proof' and name=v) then
    raise exception 'Upload the screenshot first';
  end if;
  update public.profiles set proof_screenshot_path=v, proof_screenshot_at=t where id=me;
  return t;
end $offer$;
revoke all on function public.sp_submit_proof_screenshot(text) from public,anon;
grant execute on function public.sp_submit_proof_screenshot(text) to authenticated;

create or replace function public.sp_claim_free_verification()
returns jsonb language plpgsql security definer set search_path='' as $offer$
declare me uuid:=auth.uid(); p record; r integer;
begin
  if me is null then raise exception 'Please log in'; end if;
  select slot into r from public.sp_editor_offer_slots where editor_id=me;
  if r is null then return jsonb_build_object('free',false); end if;
  select * into p from public.profiles where id=me for update;
  if p.is_verified then return jsonb_build_object('free',true,'verified',true,'rank',r); end if;
  if coalesce(p.proof_video_url,'')='' or coalesce(p.proof_screenshot_path,'')='' then
    return jsonb_build_object('free',true,'ready',false,'rank',r);
  end if;
  if p.verification_fee_status='confirmed'
    or exists(select 1 from public.sp_fee_payments where user_id=me and kind='verification' and status='paid')
  then return jsonb_build_object('free',true,'already_paid',true,'rank',r); end if;
  if p.verification_fee_status is distinct from 'waived' then
    update public.profiles set verification_fee_status='waived',verification_fee_at=now(),
      verification_status='pending' where id=me;
    insert into public.sp_notifications (user_id,title,body)
    values (me,'First 50 verification is FREE 🎉','Promo video and screenshot submitted. No ₹29 payment is needed; our team will review your application.');
  end if;
  return jsonb_build_object('free',true,'ready',true,'rank',r);
end $offer$;
revoke all on function public.sp_claim_free_verification() from public,anon;
grant execute on function public.sp_claim_free_verification() to authenticated;

-- Existing payments for others remain unchanged. Eligible editors cannot be charged even using an outdated app.
CREATE OR REPLACE FUNCTION public.sp_fee_start(p_kind text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare me uuid := auth.uid(); p record; s record; f record; price numeric; renew int; fid uuid;
begin
  if me is null then raise exception 'Please log in.'; end if;
  if p_kind = 'verification' and exists (select 1 from public.sp_editor_offer_slots where editor_id = me) then
    raise exception 'Your first-50 editor verification is FREE. Send your promo video and timeline screenshot in Verification status instead of paying.';
  end if;
  select * into p from public.profiles where id = me;
  if p_kind = 'client_premium' then
    if upper(btrim(coalesce(p.role, ''))) <> 'CLIENT' then raise exception 'Sphere Premium is for client accounts.'; end if;
  elsif upper(btrim(coalesce(p.role, ''))) <> 'EDITOR' then
    raise exception 'Only editor accounts can buy this. Clients are never charged for it.';
  end if;
  if p_kind = 'client_premium' then
    select * into s from public.sp_subscriptions where user_id = me;
    renew := coalesce((public.sp_mon_cfg('client_premium')->>'renew_days')::int, 3);
    if s.plan = 'client_premium' and s.status = 'active' and s.current_period_end > now() + make_interval(days => renew) then
      raise exception 'Premium is already active until %. You can renew in the last % days.', to_char(s.current_period_end at time zone 'Asia/Kolkata', 'DD Mon YYYY'), renew;
    end if;
    price := coalesce((public.sp_mon_cfg('client_premium')->>'price')::numeric, 199);
  elsif p_kind = 'verification' then
    if coalesce(p.is_verified, false) then raise exception 'You are already verified.'; end if;
    if exists (select 1 from public.sp_fee_payments where user_id = me and kind = 'verification' and status = 'paid')
       or p.verification_fee_status = 'confirmed' then
      raise exception 'You already paid the verification fee — it is one-time. The Sphere team will review you.';
    end if;
    price := coalesce((public.sp_mon_cfg('verification')->>'price')::numeric, 29);
  elsif p_kind = 'pro' then
    select * into s from public.sp_subscriptions where user_id = me;
    renew := coalesce((public.sp_mon_cfg('pro')->>'renew_days')::int, 3);
    if s.status = 'active' and s.current_period_end > now() + make_interval(days => renew) then
      raise exception 'Pro is already active until %. You can renew in the last % days.', to_char(s.current_period_end at time zone 'Asia/Kolkata', 'DD Mon YYYY'), renew;
    end if;
    price := coalesce((public.sp_mon_cfg('pro')->>'price')::numeric, 199);
  elsif p_kind = 'details_update' then
    if not coalesce(p.is_verified, false) then raise exception 'Update requests are for verified editors. Before verification you can still edit your application.'; end if;
    if exists (select 1 from public.sp_detail_requests where editor_id = me and status = 'open') then raise exception 'You already have an update request with the Sphere team. They will call you.'; end if;
    if not exists (select 1 from sphere_private.detail_request_drafts where user_id = me) then raise exception 'Please write what you want to change first.'; end if;
    price := coalesce((public.sp_mon_cfg('verification')->>'price')::numeric, 29);
  else
    raise exception 'Unknown payment.';
  end if;
  select * into f from public.sp_fee_payments where user_id = me and kind = p_kind and status = 'pending';
  if f.id is not null then
    update public.sp_fee_payments set amount = price where id = f.id and utr is null and order_id is null;
    fid := f.id;
  else
    insert into public.sp_fee_payments (user_id, kind, amount) values (me, p_kind, price) returning id into fid;
  end if;
  if p_kind = 'client_premium' then
    insert into public.sp_subscriptions (user_id, plan, status) values (me, 'client_premium', 'pending')
    on conflict (user_id) do update set plan = 'client_premium',
      status = case when public.sp_subscriptions.status = 'active' and public.sp_subscriptions.current_period_end > now() then 'active' else 'pending' end, updated_at = now();
  end if;
  if p_kind = 'pro' then
    insert into public.sp_subscriptions (user_id, status) values (me, 'pending')
    on conflict (user_id) do update set status = case when public.sp_subscriptions.status = 'active' and public.sp_subscriptions.current_period_end > now()
                                                      then 'active' else 'pending' end, updated_at = now();
  end if;
  return jsonb_build_object('id', fid, 'amount', price, 'kind', p_kind);
end $function$;

-- Manual approval still checks the submitted material.
CREATE OR REPLACE FUNCTION public.sp_verify_editor(p_editor uuid, p_category text, p_pin text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare v_code text; tries int := 0;
begin
if not public.is_admin() then raise exception 'Only admin can verify editors'; end if;
perform public.sp_admin_check_pin(p_pin);
if not exists (select 1 from public.profiles where id = p_editor and upper(role) = 'EDITOR') then raise exception 'Editor not found'; end if;
if exists (select 1 from public.sp_editor_offer_slots where editor_id = p_editor)
   and not exists (
      select 1 from public.profiles
      where id = p_editor and nullif(btrim(coalesce(proof_screenshot_path, '')), '') is not null
   ) then
  raise exception 'This first-50 editor must submit a timeline screenshot before verification.';
end if;
if coalesce((select proof_video_url from public.profiles where id = p_editor), '') = '' then
  raise exception 'This editor has not sent the Sphere promo video yet — it is required before verification.';
end if;
loop
v_code := 'SF-EDT-' || (floor(random() * 9000) + 1000)::int::text;
exit when not exists (select 1 from public.profiles where verification_code = v_code);
tries := tries + 1; if tries > 20 then raise exception 'Could not create a code, try again'; end if;
end loop;
update public.profiles set is_verified = true, verification_code = v_code,
categories = case when coalesce(p_category, '') = '' then categories else array[p_category] end,
verified_by = auth.uid(), verified_at = now(), verification_note = null
where id = p_editor;
insert into public.sp_notifications (user_id, title, body)
values (p_editor, 'You are verified ✅', 'Congratulations! Your Sphere editor code is ' || v_code || '. You can now bid on jobs.');
return v_code;
end $function$;

-- Admin sees free rank and screenshot beside the promo video.
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
        'proof_at', p.proof_video_at, 'proof_screenshot', p.proof_screenshot_path, 'proof_screenshot_at', p.proof_screenshot_at, 'free_offer_rank', (select slot from public.sp_editor_offer_slots where editor_id = p.id), 'joined', p.created_at,
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

insert into public.sp_schema_versions(version,name)
values ('052','First 50 editors free verification and private screenshot proof')
on conflict(version) do update set applied_at=now();
commit;
