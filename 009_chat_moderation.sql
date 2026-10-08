-- =====================================================================
-- SPHERE — PART 9: CHAT + AI MODERATION
-- Run in: Supabase → SQL Editor → + → paste → Run.  Safe to run again.
-- Needs 001, 002, 008 first. Adds columns/tables/functions; deletes nothing.
--
--   sp_messages    + job_id (project chat), mod_status (ok / held / released / removed)
--   sp_msg_holds   messages held for review: original text, reason, AI verdict
--                  (admins only — the receiver never sees a held message)
--   Contact check now also hides UPI IDs, bank account / card numbers, IFSC codes,
--   and holds messages with warning words (WhatsApp, Telegram, UPI, "call me",
--   Zoom, "pay outside" …) until AI or an admin checks them.
--   sp_chat_review     admin: release / remove a held message (Admin PIN)
--   sp_chat_ai_verdict the sphere-moderate Edge Function (or an admin) stores the AI result;
--                      "safe" from the server releases the message automatically
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1) Messages belong to a project (optional) + moderation status
-- ---------------------------------------------------------------------
alter table public.sp_messages add column if not exists job_id uuid;
alter table public.sp_messages add column if not exists mod_status text default 'ok';
alter table public.sp_messages add column if not exists mod_reason text;
alter table public.sp_messages alter column mod_status set default 'ok';
alter table public.sp_messages drop constraint if exists sp_msg_mod_chk;
-- (no check constraint on purpose: older rows may carry other values and must stay editable)
create index if not exists sp_messages_job_idx on public.sp_messages (job_id, created_at) where job_id is not null;

create table if not exists public.sp_msg_holds (
  id             uuid primary key default gen_random_uuid(),
  message_id     text not null,
  job_id         uuid,
  sender_id      uuid not null,
  receiver_id    uuid,
  original_text  text not null,
  reason         text,
  status         text not null default 'pending',     -- pending / released / removed
  ai_verdict     text,                                 -- safe / off_platform / unsure
  ai_confidence  numeric(4,3),
  ai_reason      text,
  ai_checked_at  timestamptz,
  reviewed_by    uuid,
  reviewed_at    timestamptz,
  created_at     timestamptz not null default now()
);
create unique index if not exists sp_msg_holds_msg_uq on public.sp_msg_holds (message_id);
create index if not exists sp_msg_holds_pending_idx on public.sp_msg_holds (created_at) where status = 'pending';
alter table public.sp_msg_holds drop constraint if exists sp_msg_holds_chk;
alter table public.sp_msg_holds add  constraint sp_msg_holds_chk check (status in ('pending', 'released', 'removed'));
alter table public.sp_msg_holds enable row level security;
drop policy if exists sp_msg_holds_admin on public.sp_msg_holds;
create policy sp_msg_holds_admin on public.sp_msg_holds for select to authenticated using (public.sp_core_has_role('ADMIN'));
revoke insert, update, delete on public.sp_msg_holds from anon, authenticated;
grant select on public.sp_msg_holds to authenticated;

-- ---------------------------------------------------------------------
-- 2) Contact checker v3: + UPI IDs, account / card numbers, IFSC, more warning words
-- ---------------------------------------------------------------------
do $do$
begin
  execute $fn$
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
  soft_re   text := '\m(whats ?app|watsapp|whatsap|wtsp|insta id|insta pe|insta par|insta handle|instagram id|instagram pe|instagram par|instagram handle|dm me|dm karo|telegram|snapchat|signal app|discord|skype|zoom call|zoom pe|google meet|gmeet|imo|g ?pay|google pay|paytm|phone ?pe|upi id|upi pe|upi number|upi kar|account number|acc no|a/c no|ifsc|bank details|bank account|pay outside|outside payment|direct payment|direct pay|direct paisa|paisa direct|pay cash|cash payment|cash dena|cash de|call me|call kar|call karo|call karna|number do|number de|number bhej|number bhejo|mera number|mera no|apna number|apna no|contact number|personal number|mobile number|mail me|email me|my mail|contact me outside|outside the app|outside sphere|bahar deal|bahar baat)\M';
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

  -- UPI IDs (name@okaxis, 98xxxxxxxx@ybl …) — before phone numbers so the whole ID goes
  if t ~ '[A-Za-z0-9._-]{2,}@[A-Za-z]{2,20}\M' then t := regexp_replace(t, '[A-Za-z0-9._-]{2,}@[A-Za-z]{2,20}\M', '📵', 'g'); hard := true; end if;

  -- phone numbers (10 digits starting 6-9, any spacing, digits or words)
  if t ~* phone_re then t := regexp_replace(t, phone_re, '📵', 'gi'); hard := true; end if;

  -- bank account / card numbers, IFSC codes
  if t ~ '\m[0-9]{4}([ -][0-9]{4}){3}\M' then t := regexp_replace(t, '\m[0-9]{4}([ -][0-9]{4}){3}\M', '📵', 'g'); hard := true; end if;
  if t ~ '\m[0-9]{11,18}\M' then t := regexp_replace(t, '\m[0-9]{11,18}\M', '📵', 'g'); hard := true; end if;
  if t ~ '\m[A-Z]{4}0[A-Z0-9]{6}\M' then t := regexp_replace(t, '\m[A-Z]{4}0[A-Z0-9]{6}\M', '📵', 'g'); hard := true; end if;

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
$fn$;
end $do$;

-- ---------------------------------------------------------------------
-- 3) Project chat: only the client and the chosen editor of that project
-- ---------------------------------------------------------------------
create or replace function public.sp_chat_project_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare jp record;
begin
  if NEW.job_id is null then return NEW; end if;
  select client_id, assigned_editor into jp from public.sp_jobs where id::text = NEW.job_id::text;
  if jp.client_id is null
     or not ((NEW.sender_id = jp.client_id and NEW.receiver_id = jp.assigned_editor)
          or (NEW.sender_id = jp.assigned_editor and NEW.receiver_id = jp.client_id)) then
    raise exception 'This chat belongs to another project.';
  end if;
  return NEW;
end $$;
drop trigger if exists sp_chat_project_guard on public.sp_messages;
create trigger sp_chat_project_guard before insert on public.sp_messages
  for each row execute function public.sp_chat_project_guard();

-- ---------------------------------------------------------------------
-- 4) Hold suspicious messages (runs after the number-hiding trigger zz_sp_mod_guard)
-- ---------------------------------------------------------------------
create or replace function public.sp_chat_hold()
returns trigger language plpgsql security definer set search_path = public as $$
declare r record; skip_admin boolean;
begin
  if NEW."text" is null or btrim(NEW."text") = '' then return NEW; end if;
  if current_setting('sphere.no_strike', true) = '1' then return NEW; end if;
  skip_admin := public.sp_mod_is_admin(NEW.sender_id) and public.sp_setting_int('mod_skip_admins', 0) = 1;
  if skip_admin then return NEW; end if;
  select * into r from public.sp_mod_mask(NEW."text");
  if r.soft then
    insert into public.sp_msg_holds (message_id, job_id, sender_id, receiver_id, original_text, reason)
    values (NEW.id::text, NEW.job_id, NEW.sender_id, NEW.receiver_id, NEW."text", 'Warning words (possible outside contact or payment)')
    on conflict (message_id) do nothing;
    NEW."text" := '⏳ This message is being checked by Sphere';
    NEW.mod_status := 'held';
    NEW.mod_reason := 'Possible outside contact or payment';
  end if;
  return NEW;
end $$;
drop trigger if exists zzz_sp_chat_hold on public.sp_messages;
create trigger zzz_sp_chat_hold before insert on public.sp_messages
  for each row execute function public.sp_chat_hold();

-- tell admins (once per message)
create or replace function public.sp_chat_hold_after()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if NEW.mod_status = 'held' then
    insert into public.sp_notifications (user_id, title, body)
    select id, 'Message held for review 🛡️', 'A chat message is waiting in Admin Panel → Messages to review.'
    from public.profiles where upper(btrim(role)) = 'ADMIN'
      and not exists (select 1 from public.sp_msg_holds h where h.status = 'pending' and h.created_at > now() - interval '30 minutes' and h.message_id <> NEW.id::text);
  end if;
  return null;
end $$;
drop trigger if exists sp_chat_hold_after on public.sp_messages;
create trigger sp_chat_hold_after after insert on public.sp_messages
  for each row execute function public.sp_chat_hold_after();

-- ---------------------------------------------------------------------
-- 5) Release / remove a held message
-- ---------------------------------------------------------------------
drop function if exists public.sp_chat_apply(uuid, text, uuid);
drop function if exists public.sp_chat_review(uuid, text, text);
drop function if exists public.sp_chat_ai_verdict(uuid, text, numeric, text);
create or replace function public.sp_chat_apply(p_hold uuid, p_action text, p_by uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare h record;
begin
  select * into h from public.sp_msg_holds where id = p_hold for update;
  if h.id is null then raise exception 'Not found.'; end if;
  if h.status <> 'pending' then return jsonb_build_object('status', h.status); end if;
  perform set_config('sphere.no_strike', '1', true);     -- releasing must not add a new strike
  if p_action = 'release' then
    update public.sp_messages set "text" = h.original_text, mod_status = 'released', mod_reason = null where id::text = h.message_id;
    update public.sp_msg_holds set status = 'released', reviewed_by = p_by, reviewed_at = now() where id = h.id;
    -- it was innocent: take back the warning-word strike for this message
    update public.sp_mod_strikes set cleared = true
     where id = (select id from public.sp_mod_strikes where user_id = h.sender_id and source = 'chat' and kind = 'keyword'
                   and not cleared and original_text = h.original_text order by created_at desc limit 1);
    if found then
      update public.sp_mod_flags set strike_count = greatest(0, strike_count - 1), updated_at = now() where user_id = h.sender_id;
    end if;
  elsif p_action = 'remove' then
    update public.sp_messages set "text" = '🚫 Message removed by Sphere — sharing contact or payment details is not allowed', mod_status = 'removed'
     where id::text = h.message_id;
    update public.sp_msg_holds set status = 'removed', reviewed_by = p_by, reviewed_at = now() where id = h.id;
    insert into public.sp_notifications (user_id, title, body) values (h.sender_id, 'Message removed ⚠️',
      'Your message was removed because it tried to move the talk or payment outside Sphere. Repeating this can get your account suspended or deleted.');
  else
    raise exception 'Unknown action.';
  end if;
  perform set_config('sphere.no_strike', '', true);
  return jsonb_build_object('status', case when p_action = 'release' then 'released' else 'removed' end);
end $$;
revoke all on function public.sp_chat_apply(uuid, text, uuid) from public, anon, authenticated;

create or replace function public.sp_chat_review(p_hold uuid, p_action text, p_pin text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.sp_core_has_role('ADMIN') then raise exception 'Admins only'; end if;
  perform public.sp_admin_check_pin(p_pin := p_pin);
  return public.sp_chat_apply(p_hold, p_action, auth.uid());
end $$;
revoke all on function public.sp_chat_review(uuid, text, text) from public, anon;
grant execute on function public.sp_chat_review(uuid, text, text) to authenticated;

-- AI result: from the sphere-moderate Edge Function (service role) or an admin.
-- Only the server may auto-release ("safe" with confidence ≥ 0.8).
create or replace function public.sp_chat_ai_verdict(p_hold uuid, p_verdict text, p_confidence numeric, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  claims jsonb := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb);
  is_server boolean := coalesce(claims->>'role', current_setting('request.jwt.claim.role', true), '') = 'service_role';
  v text := lower(coalesce(p_verdict, 'unsure'));
  h record;
begin
  if not is_server and not public.sp_core_has_role('ADMIN') then raise exception 'Not allowed.'; end if;
  if v not in ('safe', 'off_platform', 'unsure') then v := 'unsure'; end if;
  select * into h from public.sp_msg_holds where id = p_hold for update;
  if h.id is null then raise exception 'Not found.'; end if;
  update public.sp_msg_holds set ai_verdict = v, ai_confidence = least(1, greatest(0, coalesce(p_confidence, 0))),
         ai_reason = left(p_reason, 300), ai_checked_at = now() where id = h.id;
  if is_server and h.status = 'pending' and v = 'safe' and coalesce(p_confidence, 0) >= 0.8 then
    perform public.sp_chat_apply(h.id, 'release', null);
    return jsonb_build_object('released', true);
  end if;
  return jsonb_build_object('released', false);
end $$;
revoke all on function public.sp_chat_ai_verdict(uuid, text, numeric, text) from public, anon;
grant execute on function public.sp_chat_ai_verdict(uuid, text, numeric, text) to authenticated, service_role;

insert into public.sp_schema_versions (version, name)
values ('009', 'Chat + AI moderation (project chat, held messages, UPI / bank details, admin review)')
on conflict (version) do update set applied_at = now();

commit;

-- Done. You should see "Success. No rows returned".
-- Optional: deploy the sphere-moderate Edge Function so AI checks held messages automatically.
