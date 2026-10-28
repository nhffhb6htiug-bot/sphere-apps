-- Sphere: WhatsApp inbound verification (opt-in pilot).
-- NO existing profiles are marked verified. Do not force verification until rollout is tested.
create table if not exists public.sp_wa_challenges (
  user_id uuid primary key references auth.users(id) on delete cascade,
  phone_e164 text not null check (phone_e164 ~ '^91[6-9][0-9]{9}$'),
  code_hash text not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  attempts integer not null default 0,
  confirmed_at timestamptz
);
create index if not exists sp_wa_challenges_phone_idx on public.sp_wa_challenges(phone_e164) where confirmed_at is null;
create table if not exists public.sp_wa_phone_claims (
  phone_e164 text primary key check (phone_e164 ~ '^91[6-9][0-9]{9}$'),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  verified_at timestamptz not null default now()
);
create table if not exists public.sp_wa_request_log (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists sp_wa_request_log_user_time_idx on public.sp_wa_request_log(user_id,created_at desc);
alter table public.sp_wa_challenges enable row level security;
alter table public.sp_wa_phone_claims enable row level security;
alter table public.sp_wa_request_log enable row level security;
revoke all on public.sp_wa_challenges,public.sp_wa_phone_claims,public.sp_wa_request_log from public,anon,authenticated;
grant all on public.sp_wa_challenges,public.sp_wa_phone_claims,public.sp_wa_request_log to service_role;
grant usage,select on sequence public.sp_wa_request_log_id_seq to service_role;

-- The webhook calls this using service_role only. Claim is atomic.
create or replace function public.sp_wa_complete(p_phone text,p_code_hash text)
returns boolean language plpgsql security definer set search_path=public,pg_temp as $$
declare v public.sp_wa_challenges%rowtype; owner_id uuid;
begin
  select * into v from public.sp_wa_challenges
   where phone_e164=p_phone and confirmed_at is null and expires_at>now()
   order by created_at desc limit 1 for update;
  if not found or v.attempts>=8 then return false; end if;
  if v.code_hash<>p_code_hash then
    update public.sp_wa_challenges set attempts=attempts+1 where user_id=v.user_id;
    return false;
  end if;
  insert into public.sp_wa_phone_claims(phone_e164,user_id)
    values (p_phone,v.user_id)
    on conflict do nothing;
  select user_id into owner_id from public.sp_wa_phone_claims where phone_e164=p_phone;
  if owner_id is distinct from v.user_id then return false; end if;
  update public.sp_wa_challenges set confirmed_at=now() where user_id=v.user_id;
  return true;
end;
$$;
revoke all on function public.sp_wa_complete(text,text) from public,anon,authenticated;
grant execute on function public.sp_wa_complete(text,text) to service_role;
