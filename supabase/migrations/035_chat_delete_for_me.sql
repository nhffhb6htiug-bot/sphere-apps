-- =====================================================================
-- SPHERE — CHAT: "Delete for me" (hide a message only on your own screen)
-- Safe to run again. Deletes NO data: the message stays for the other person and for the Sphere team
-- (chats are evidence in disputes), it is only hidden for the person who chose "Delete for me".
-- =====================================================================
begin;
create table if not exists public.sp_msg_hidden (
  user_id uuid not null references public.profiles(id) on delete cascade,
  message_id uuid not null references public.sp_messages(id) on delete cascade,
  hidden_at timestamptz not null default now(),
  primary key (user_id, message_id)
);
alter table public.sp_msg_hidden enable row level security;
revoke all on public.sp_msg_hidden from anon, authenticated;
grant select, insert, delete on public.sp_msg_hidden to authenticated;
drop policy if exists sp_msg_hidden_own_select on public.sp_msg_hidden;
drop policy if exists sp_msg_hidden_own_insert on public.sp_msg_hidden;
drop policy if exists sp_msg_hidden_own_delete on public.sp_msg_hidden;
create policy sp_msg_hidden_own_select on public.sp_msg_hidden for select to authenticated using (user_id = auth.uid());
create policy sp_msg_hidden_own_insert on public.sp_msg_hidden for insert to authenticated
  with check (user_id = auth.uid() and exists (select 1 from public.sp_messages m where m.id = message_id and (m.sender_id = auth.uid() or m.receiver_id = auth.uid())));
create policy sp_msg_hidden_own_delete on public.sp_msg_hidden for delete to authenticated using (user_id = auth.uid());
insert into public.sp_schema_versions (version, name) values ('035', 'Chat: delete a message for me (hide on my screen only)')
on conflict (version) do update set applied_at = now();
commit;
