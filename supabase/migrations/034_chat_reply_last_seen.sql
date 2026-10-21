-- =====================================================================
-- SPHERE — CHAT: reply to a message + "last seen" (Chat upgrade, part 1)
-- Run in: Supabase → SQL Editor → + → paste → Run.  Safe to run again. Deletes NO data.
--
-- 1) sp_messages.reply_to — a reply can only point to a message between the SAME two people,
--    and it can never be changed afterwards.
-- 2) sp_presence — when each person was last active + their "show my last seen" choice.
--    Nobody can read or write the table directly. Last seen is shown only to someone you already
--    chat with, never while either has blocked the other, and only if BOTH share it (like WhatsApp).
-- =====================================================================
begin;

alter table public.sp_messages add column if not exists reply_to uuid references public.sp_messages(id) on delete set null;

create or replace function public.sp_messages_reply_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare r record;
begin
  if TG_OP = 'UPDATE' then
    if NEW.reply_to is distinct from OLD.reply_to then raise exception 'A reply cannot be changed.'; end if;
    return NEW;
  end if;
  if NEW.reply_to is null then return NEW; end if;
  select sender_id, receiver_id into r from public.sp_messages where id = NEW.reply_to;
  if not found or not ((r.sender_id = NEW.sender_id and r.receiver_id = NEW.receiver_id)
                    or (r.sender_id = NEW.receiver_id and r.receiver_id = NEW.sender_id)) then
    raise exception 'You can only reply to a message in this chat.';
  end if;
  return NEW;
end $$;
revoke all on function public.sp_messages_reply_guard() from public, anon, authenticated;
drop trigger if exists a0_sp_messages_reply_guard on public.sp_messages;
create trigger a0_sp_messages_reply_guard before insert or update of reply_to on public.sp_messages
for each row execute function public.sp_messages_reply_guard();

create table if not exists public.sp_presence (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  last_seen_at timestamptz,
  show_last_seen boolean not null default true
);
alter table public.sp_presence enable row level security;
revoke all on public.sp_presence from anon, authenticated;

create or replace function public.sp_seen_ping()
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return; end if;
  insert into public.sp_presence (user_id, last_seen_at) values (auth.uid(), now())
  on conflict (user_id) do update set last_seen_at = now()
    where public.sp_presence.last_seen_at is null or public.sp_presence.last_seen_at < now() - interval '45 seconds';
end $$;

create or replace function public.sp_set_show_last_seen(p_show boolean)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Please log in.'; end if;
  insert into public.sp_presence (user_id, show_last_seen) values (auth.uid(), coalesce(p_show, true))
  on conflict (user_id) do update set show_last_seen = coalesce(p_show, true);
  return coalesce(p_show, true);
end $$;

create or replace function public.sp_my_show_last_seen()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select show_last_seen from public.sp_presence where user_id = auth.uid()), true);
$$;

create or replace function public.sp_last_seen(p_other uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare me uuid := auth.uid(); mine boolean; theirs boolean; t timestamptz;
begin
  if me is null or p_other is null or p_other = me then return jsonb_build_object('visible', false); end if;
  if not exists (select 1 from public.sp_messages where (sender_id = me and receiver_id = p_other) or (sender_id = p_other and receiver_id = me)) then
    return jsonb_build_object('visible', false);
  end if;
  if public.sp_is_blocked_pair(me, p_other) then return jsonb_build_object('visible', false); end if;
  select coalesce((select show_last_seen from public.sp_presence where user_id = me), true) into mine;
  select coalesce(show_last_seen, true), last_seen_at into theirs, t from public.sp_presence where user_id = p_other;
  if not mine or not coalesce(theirs, true) or t is null then return jsonb_build_object('visible', false); end if;
  return jsonb_build_object('visible', true, 'last_seen_at', t);
end $$;

revoke all on function public.sp_seen_ping(), public.sp_set_show_last_seen(boolean), public.sp_my_show_last_seen(), public.sp_last_seen(uuid) from public, anon;
grant execute on function public.sp_seen_ping(), public.sp_set_show_last_seen(boolean), public.sp_my_show_last_seen(), public.sp_last_seen(uuid) to authenticated;

insert into public.sp_schema_versions (version, name)
values ('034', 'Chat: reply to a message (same chat only) + private last seen')
on conflict (version) do update set applied_at = now();
commit;
