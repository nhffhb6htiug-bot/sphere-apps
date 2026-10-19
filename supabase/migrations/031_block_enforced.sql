-- =====================================================================
-- SPHERE — BLOCK IS ENFORCED BY THE SERVER (Part 21)
-- Run in: Supabase → SQL Editor → + → paste → Run.  Safe to run again. Deletes NO data.
--
-- Until now a block only hid the message box in the app; a blocked person could still send a
-- message through the API. Now the database refuses any new message between two people when
-- either has blocked the other. Messages from the Sphere team (admins) are not stopped, so
-- support, disputes and refunds keep working. Old messages are not touched.
-- =====================================================================
begin;

create or replace function public.sp_messages_block_check()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if NEW.sender_id is null or NEW.receiver_id is null then return NEW; end if;
  if exists (select 1 from public.profiles p where p.id = NEW.sender_id and upper(btrim(coalesce(p.role, ''))) = 'ADMIN') then
    return NEW;   -- Sphere team
  end if;
  if exists (select 1 from public.sp_blocks b
             where (b.blocker_id = NEW.sender_id and b.blocked_id = NEW.receiver_id)
                or (b.blocker_id = NEW.receiver_id and b.blocked_id = NEW.sender_id)) then
    raise exception 'Message not sent: one of you has blocked the other.' using errcode = 'P0001';
  end if;
  return NEW;
end $$;
revoke all on function public.sp_messages_block_check() from public, anon, authenticated;

drop trigger if exists a0_sp_messages_block_check on public.sp_messages;
create trigger a0_sp_messages_block_check before insert on public.sp_messages
for each row execute function public.sp_messages_block_check();

insert into public.sp_schema_versions (version, name)
values ('031', 'Blocking enforced by the server: no new messages between blocked users (Sphere team exempt)')
on conflict (version) do update set applied_at = now();

commit;
-- Done. You should see "Success. No rows returned".
