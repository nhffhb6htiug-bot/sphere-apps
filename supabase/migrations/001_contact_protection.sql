-- =====================================================================
-- SPHERE — PART 1: Number block + strikes
-- Run in: Supabase Dashboard → SQL Editor → New query → paste → Run
-- Safe to run again (it replaces its own objects, never your data).
-- Run 1_backup.sql FIRST.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1) Prices / limits in one place (only added if missing)
-- ---------------------------------------------------------------------
insert into public.sp_settings (key, value) select 'strike_limit',   '3'   where not exists (select 1 from public.sp_settings where key = 'strike_limit');
insert into public.sp_settings (key, value) select 'verify_fee',     '29'  where not exists (select 1 from public.sp_settings where key = 'verify_fee');
insert into public.sp_settings (key, value) select 'revision_fee',   '50'  where not exists (select 1 from public.sp_settings where key = 'revision_fee');
insert into public.sp_settings (key, value) select 'free_revisions', '3'   where not exists (select 1 from public.sp_settings where key = 'free_revisions');
insert into public.sp_settings (key, value) select 'pro_fee',        '199' where not exists (select 1 from public.sp_settings where key = 'pro_fee');
-- 0 = admins are checked too (testing). Later, to skip admins: update public.sp_settings set value = '1' where key = 'mod_skip_admins';
insert into public.sp_settings (key, value) select 'mod_skip_admins', '0' where not exists (select 1 from public.sp_settings where key = 'mod_skip_admins');

-- ---------------------------------------------------------------------
-- 2) Tables: strike count per user + every strike (admin-only)
-- ---------------------------------------------------------------------
create table if not exists public.sp_mod_flags (
  user_id        uuid primary key references auth.users(id) on delete cascade,
  strike_count   int not null default 0,
  is_suspended   boolean not null default false,
  warned_at      timestamptz,
  last_strike_at timestamptz,
  updated_at     timestamptz not null default now()
);

create table if not exists public.sp_mod_strikes (
  id            bigserial primary key,
  user_id       uuid not null references auth.users(id) on delete cascade,
  source        text not null,   -- chat | job | bid | profile | portfolio | review | notification
  kind          text not null,   -- hidden (contact removed) | keyword (warning words)
  original_text text,
  cleared       boolean not null default false,
  created_at    timestamptz not null default now()
);
create index if not exists sp_mod_strikes_user_idx on public.sp_mod_strikes (user_id, created_at desc);

-- who is admin (own name so nothing existing gets replaced)
create or replace function public.sp_mod_is_admin(p_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = p_user and upper(role) = 'ADMIN');
$$;

alter table public.sp_mod_flags   enable row level security;
alter table public.sp_mod_strikes enable row level security;

drop policy if exists sp_mod_flags_read   on public.sp_mod_flags;
drop policy if exists sp_mod_strikes_read on public.sp_mod_strikes;
-- users can see only their own flag row; admins see all. Nobody can write directly.
create policy sp_mod_flags_read   on public.sp_mod_flags   for select to authenticated using (user_id = auth.uid() or public.sp_mod_is_admin());
create policy sp_mod_strikes_read on public.sp_mod_strikes for select to authenticated using (public.sp_mod_is_admin());

revoke insert, update, delete on public.sp_mod_flags, public.sp_mod_strikes from anon, authenticated;
grant select on public.sp_mod_flags, public.sp_mod_strikes to authenticated;

-- reports raised from a chat remember who was reported
alter table public.sp_reports add column if not exists chat_user_id uuid;

-- ---------------------------------------------------------------------
-- 3) The checker: hides numbers, emails, links, @IDs
-- ---------------------------------------------------------------------
-- what counts as one "digit": 0-9, Hindi digits, English / Hinglish / Hindi words, Roman numerals
create or replace function public.sp_mod_re(p_kind text)
returns text language sql immutable as $$
  select case p_kind
    when 'tok'  then '(?:[0-9०-९]|zero|one|two|three|four|five|six|seven|eight|nine|shunya|ek|do|teen|char|chaar|paanch|panch|chhe|chhah|saat|aath|nau|viii|vii|vi|iv|ix|iii|ii|i|v|o|शून्य|एक|दो|तीन|चार|पांच|पाँच|छह|छः|सात|आठ|नौ)'
    when 'tok6' then '(?:[6-9६-९]|six|seven|eight|nine|chhe|chhah|saat|aath|nau|viii|vii|vi|ix|छह|छः|सात|आठ|नौ)'
    when 'sep'  then '[[:space:].()_|+-]*'
  end;
$$;

-- true when a message is ONLY digits / digit-words (like "8956", "nine", "IX VIII")
create or replace function public.sp_mod_numeric_only(p_text text)
returns boolean language plpgsql immutable as $$
declare t text;
begin
  if p_text is null or btrim(p_text) = '' or p_text !~* public.sp_mod_re('tok') then return false; end if;
  t := regexp_replace(p_text, public.sp_mod_re('tok'), '', 'gi');
  t := regexp_replace(t, '[[:space:].()_|+-]', '', 'g');
  return t = '';
end $$;

drop function if exists public.sp_mod_mask(text);
create or replace function public.sp_mod_mask(p_text text, p_min int default 10, out masked text, out hard boolean, out soft boolean)
language plpgsql immutable set search_path = public as $$
declare
  t text := p_text;
  tok  text := public.sp_mod_re('tok');
  tok6 text := public.sp_mod_re('tok6');
  sep  text := public.sp_mod_re('sep');
  phone_re text;
  email_re  text := '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}';
  email2_re text := '[A-Za-z0-9._-]+([[:space:]]*@[[:space:]]*|[[:space:]]*(\[|\()[[:space:]]*at[[:space:]]*(\]|\))[[:space:]]*|[[:space:]]+at[[:space:]]+)[A-Za-z0-9-]+([[:space:]]*\.[[:space:]]*|[[:space:]]*(\[|\()[[:space:]]*dot[[:space:]]*(\]|\))[[:space:]]*|[[:space:]]+dot[[:space:]]+)(com|in|net|org|co)\M';
  link_re   text := '((https?://|www\.)[^[:space:]]+|([A-Za-z0-9-]+\.)+(com|in|net|org|me|io|co|xyz|app|link|site|online|store|info|ly|ee|gg|tv|page|dev)\M(/[^[:space:]]*)?)';
  allow_re  text := '^(https?://)?(www\.|m\.)?(drive\.google\.com|docs\.google\.com|youtube\.com|youtu\.be|wetransfer\.com|we\.tl|dropbox\.com|mega\.nz|1drv\.ms|onedrive\.live\.com|sphere-live\.onrender\.com)([/?#].*)?$';
  handle_re text := '(^|[^A-Za-z0-9_.@])@[A-Za-z0-9_.]*[A-Za-z][A-Za-z0-9_.]{1,29}';
  soft_re   text := '\m(whats ?app|watsapp|whatsap|wtsp|insta|instagram|telegram|snapchat|g ?pay|google pay|paytm|phone ?pe|call me|call kar|call karo|call karna|number do|number de|number bhej|number bhejo|mera number|mera no|apna number|apna no|contact number|personal number|direct pay|direct payment|outside the app|bahar deal)\M';
  soft_hi   text := '(व्हाट्सएप|व्हाट्सऐप|मेरा नंबर|अपना नंबर)';
  keep text[] := '{}';
  m text;
  i int;
  support text[] := array['7739363798','9468289750','8708712986'];
begin
  hard := false; soft := false;
  if t is null or btrim(t) = '' then masked := t; return; end if;
  phone_re := '(?:(?:\+|00)?91' || sep || '|0' || sep || ')?' || tok6 || '(?:' || sep || tok || '){' || (greatest(p_min, 2) - 1) || '}';

  -- Syahi Films support numbers are always allowed
  for i in 1 .. array_length(support, 1) loop
    t := replace(t, support[i], '‹S' || i || '›');
  end loop;

  -- emails
  if t ~* email_re then t := regexp_replace(t, email_re, '📵', 'gi'); hard := true; end if;
  if t ~* email2_re then t := regexp_replace(t, email2_re, '📵', 'gi'); hard := true; end if;

  -- links: footage / preview sites stay, everything else hidden
  for m in select (regexp_matches(t, link_re, 'gi'))[1] loop
    if m ~* allow_re then
      keep := keep || m;
      t := replace(t, m, '‹L' || array_length(keep, 1) || '›');
    else
      t := replace(t, m, '📵');
      hard := true;
    end if;
  end loop;

  -- @instagram style IDs
  if t ~ handle_re then t := regexp_replace(t, handle_re, '\1📵', 'g'); hard := true; end if;

  -- phone numbers (10 digits starting 6-9, any spacing, digits or words)
  if t ~* phone_re then t := regexp_replace(t, phone_re, '📵', 'gi'); hard := true; end if;

  -- put back allowed links and support numbers
  if array_length(keep, 1) is not null then
    for i in reverse array_length(keep, 1) .. 1 loop
      t := replace(t, '‹L' || i || '›', keep[i]);
    end loop;
  end if;
  for i in 1 .. array_length(support, 1) loop
    t := replace(t, '‹S' || i || '›', support[i]);
  end loop;

  -- warning words (message goes through, strike is recorded)
  if not hard and (t ~* soft_re or t ~ soft_hi) then soft := true; end if;

  masked := t;
end $$;

-- ---------------------------------------------------------------------
-- 4) One trigger function used by every table
--    args: 1) columns to check  2) source name  3) column holding the author
-- ---------------------------------------------------------------------
create or replace function public.sp_mod_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  cols    text[] := string_to_array(TG_ARGV[0], ',');
  src     text   := TG_ARGV[1];
  uid_col text   := TG_ARGV[2];
  newj    jsonb  := to_jsonb(NEW);
  oldj    jsonb;
  uid     uuid;
  c       text;
  v       text;
  r       record;
  changes jsonb := '{}'::jsonb;
  any_hard boolean := false;
  any_soft boolean := false;
  originals text := '';
  cnt int;
  lim int;
  pm record;
  chain text;
  piece_ids text[] := '{}';
begin
  -- system notifications (no logged-in user) are not filtered
  if src = 'notification' and auth.uid() is null then return NEW; end if;

  uid := nullif(newj ->> uid_col, '')::uuid;
  if uid is null then uid := auth.uid(); end if;

  -- suspended users cannot send messages, bids or post jobs
  if TG_OP = 'INSERT' and src in ('chat', 'bid', 'job')
     and exists (select 1 from public.sp_mod_flags f where f.user_id = uid and f.is_suspended) then
    raise exception 'Your Sphere account is suspended. Please contact Sphere support.';
  end if;

  -- admins (Syahi Films) are skipped only when setting mod_skip_admins = 1
  if uid is not null and public.sp_mod_is_admin(uid)
     and coalesce((select nullif(regexp_replace(s.value::text, '[^0-9]', '', 'g'), '')::int
                   from public.sp_settings s where s.key = 'mod_skip_admins'), 0) = 1 then
    return NEW;
  end if;

  if TG_OP = 'UPDATE' then oldj := to_jsonb(OLD); end if;

  foreach c in array cols loop
    v := newj ->> c;
    continue when v is null or v = '';
    continue when TG_OP = 'UPDATE' and v is not distinct from (oldj ->> c);
    select * into r from public.sp_mod_mask(v);
    if r.hard then
      changes  := changes || jsonb_build_object(c, r.masked);
      any_hard := true;
      originals := originals || v || E'\n';
    elsif r.soft then
      any_soft := true;
      originals := originals || v || E'\n';
    end if;
  end loop;

  if any_hard then
    NEW := jsonb_populate_record(NEW, changes);
  end if;

  -- number sent in pieces ("8956" ... "546545" ... "nine" ... "eight"):
  -- join this sender's number-only messages to the same person from the last 10 minutes
  -- (round amounts like 600 / 7000 / 15000 are prices, not number pieces)
  -- (nested IF: only chat rows have a "text" column)
  if TG_OP = 'INSERT' and src = 'chat' and not any_hard then
  if public.sp_mod_numeric_only(NEW."text") and NEW."text" !~ '^[[:space:]]*[0-9]{1,6}00[[:space:]]*$' then
    chain := '';
    for pm in
      select id::text as mid, "text" as tx from public.sp_messages
      where sender_id = NEW.sender_id and receiver_id = NEW.receiver_id
        and created_at > now() - interval '10 minutes'
      order by created_at desc limit 12
    loop
      if public.sp_mod_numeric_only(pm.tx) and pm.tx !~ '^[[:space:]]*[0-9]{1,6}00[[:space:]]*$' then
        chain := pm.tx || ' ' || chain;
        piece_ids := piece_ids || pm.mid;
      end if;
    end loop;
    chain := chain || NEW."text";
    if (select x.hard from public.sp_mod_mask(chain, 8) x) then
      NEW."text" := '📵';
      any_hard := true;
      originals := originals || 'Number sent in pieces: ' || chain || E'\n';
      if array_length(piece_ids, 1) is not null then
        update public.sp_messages set "text" = '📵' where id::text = any(piece_ids);
      end if;
    end if;
  end if;
  end if;

  -- notifications are only cleaned (the chat message itself already gave the strike)
  if (any_hard or any_soft) and uid is not null and src <> 'notification'
     and coalesce(current_setting('sphere.no_strike', true), '') <> '1' then

    insert into public.sp_mod_strikes (user_id, source, kind, original_text)
    values (uid, src, case when any_hard then 'hidden' else 'keyword' end, left(btrim(originals, E' \n'), 2000));

    insert into public.sp_mod_flags (user_id, strike_count, last_strike_at)
    values (uid, 1, now())
    on conflict (user_id) do update
      set strike_count = public.sp_mod_flags.strike_count + 1, last_strike_at = now(), updated_at = now()
    returning strike_count into cnt;

    select coalesce(nullif(regexp_replace(value::text, '[^0-9]', '', 'g'), '')::int, 3)
      into lim from public.sp_settings where key = 'strike_limit';
    lim := coalesce(lim, 3);

    -- tell every admin once, when the limit is reached
    if cnt = lim then
      insert into public.sp_notifications (user_id, title, body)
      select a.id, 'Suspicious user 🚨',
             coalesce(nullif((select full_name from public.profiles where id = uid), ''), 'A user')
             || ' has ' || cnt || ' strikes for sharing contact details. Open Admin Panel → Suspicious Users.'
      from public.profiles a where upper(a.role) = 'ADMIN';
    end if;
  end if;

  return NEW;
end $$;

-- ---------------------------------------------------------------------
-- 5) Attach the checker (zz_ name = runs after any existing triggers)
-- ---------------------------------------------------------------------
drop trigger if exists zz_sp_mod_guard on public.sp_messages;
create trigger zz_sp_mod_guard before insert or update of "text" on public.sp_messages
  for each row execute function public.sp_mod_guard('text', 'chat', 'sender_id');

drop trigger if exists zz_sp_mod_guard on public.sp_jobs;
create trigger zz_sp_mod_guard before insert or update of description on public.sp_jobs
  for each row execute function public.sp_mod_guard('description', 'job', 'client_id');

drop trigger if exists zz_sp_mod_guard on public.sp_applications;
create trigger zz_sp_mod_guard before insert or update of message on public.sp_applications
  for each row execute function public.sp_mod_guard('message', 'bid', 'editor_id');

drop trigger if exists zz_sp_mod_guard on public.profiles;
create trigger zz_sp_mod_guard before insert or update of full_name, price_range on public.profiles
  for each row execute function public.sp_mod_guard('full_name,price_range', 'profile', 'id');

drop trigger if exists zz_sp_mod_guard on public.sp_portfolio;
create trigger zz_sp_mod_guard before insert or update of title on public.sp_portfolio
  for each row execute function public.sp_mod_guard('title', 'portfolio', 'editor_id');

drop trigger if exists zz_sp_mod_guard on public.sp_ratings;
create trigger zz_sp_mod_guard before insert or update of review on public.sp_ratings
  for each row execute function public.sp_mod_guard('review', 'review', 'client_id');

drop trigger if exists zz_sp_mod_guard on public.sp_notifications;
create trigger zz_sp_mod_guard before insert on public.sp_notifications
  for each row execute function public.sp_mod_guard('title,body', 'notification', '-');

-- ---------------------------------------------------------------------
-- 6) Admin buttons: warn / suspend / unsuspend / clear  (needs Admin PIN)
-- ---------------------------------------------------------------------
create or replace function public.sp_mod_admin_action(p_user uuid, p_action text, p_pin text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.sp_mod_is_admin() then raise exception 'Admins only'; end if;
  perform public.sp_admin_check_pin(p_pin := p_pin);

  insert into public.sp_mod_flags (user_id) values (p_user) on conflict (user_id) do nothing;

  if p_action = 'warn' then
    update public.sp_mod_flags set warned_at = now(), updated_at = now() where user_id = p_user;
    insert into public.sp_notifications (user_id, title, body) values (p_user, 'Warning from Sphere ⚠️',
      'Sharing phone numbers, emails, social media IDs or asking for outside payment is not allowed on Sphere. If it happens again, your account can be suspended or deleted.');
  elsif p_action = 'suspend' then
    update public.sp_mod_flags set is_suspended = true, updated_at = now() where user_id = p_user;
    insert into public.sp_notifications (user_id, title, body) values (p_user, 'Account suspended ⛔',
      'Your Sphere account is suspended for breaking the contact-sharing rules. Contact Sphere support to talk about it.');
  elsif p_action = 'unsuspend' then
    update public.sp_mod_flags set is_suspended = false, updated_at = now() where user_id = p_user;
    insert into public.sp_notifications (user_id, title, body) values (p_user, 'Account active again ✅',
      'Your Sphere account is active again. Please keep all talks and payments inside Sphere.');
  elsif p_action = 'clear' then
    update public.sp_mod_flags set strike_count = 0, updated_at = now() where user_id = p_user;
    update public.sp_mod_strikes set cleared = true where user_id = p_user and not cleared;
  else
    raise exception 'Unknown action: %', p_action;
  end if;
end $$;

revoke all on function public.sp_mod_admin_action(uuid, text, text) from public, anon;
grant execute on function public.sp_mod_admin_action(uuid, text, text) to authenticated;
grant execute on function public.sp_mod_is_admin(uuid) to authenticated;

commit;

-- Done. You should see "Success. No rows returned".
