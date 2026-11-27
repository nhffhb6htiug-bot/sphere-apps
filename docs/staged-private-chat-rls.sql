-- STAGING ONLY: review and run on a disposable Supabase project before production.
-- Existing web public channels remain untouched. New topic uses a distinct name and private=true.
begin;
create or replace function public.sp_private_chat_topic_allowed(p_topic text)
returns boolean language plpgsql stable security invoker set search_path = '' as $$
declare me uuid := auth.uid(); a uuid; b uuid; peer uuid; visibility jsonb;
begin
  if me is null or p_topic is null or p_topic !~ '^sphere-private-chat-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then return false; end if;
  a := split_part(substr(p_topic,length('sphere-private-chat-')+1),':',1)::uuid;
  b := split_part(substr(p_topic,length('sphere-private-chat-')+1),':',2)::uuid;
  if a >= b or me not in (a,b) then return false; end if;
  peer := case when me=a then b else a end;
  -- Existing RPC verifies conversation membership, both visibility settings, and block status.
  visibility := public.sp_last_seen(peer);
  return coalesce((visibility->>'visible')::boolean,false);
end;
$$;
revoke all on function public.sp_private_chat_topic_allowed(text) from public,anon;
grant execute on function public.sp_private_chat_topic_allowed(text) to authenticated;
drop policy if exists sphere_private_chat_broadcast_read on realtime.messages;
create policy sphere_private_chat_broadcast_read on realtime.messages for select to authenticated
using (extension='broadcast' and public.sp_private_chat_topic_allowed(realtime.topic()));
drop policy if exists sphere_private_chat_broadcast_write on realtime.messages;
create policy sphere_private_chat_broadcast_write on realtime.messages for insert to authenticated
with check (extension='broadcast' and public.sp_private_chat_topic_allowed(realtime.topic()));
commit;
-- Verify with two authorized test accounts, an unrelated account, blocked users, and privacy disabled.
-- Permissions are cached at join. Native closes/rejoins every 45s; do not claim immediate revocation.
-- Web interoperability and tenant-wide disabling public channels require separate coordinated migration.
