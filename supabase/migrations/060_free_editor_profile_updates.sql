-- Sphere 060: verified editors may update their own profile details for free.
-- Keep admin-only verification and fee approval protections unchanged.
begin;
create or replace function sphere_private.sp_editor_details_lock() returns trigger
language plpgsql set search_path = public as $$
begin
  -- Profile details are editable by their owner under existing RLS policies.
  -- Verification status, fee state, and admin-only fields remain guarded elsewhere.
  return new;
end $$;
insert into public.sp_schema_versions(version,name)
values ('060','Free editor profile updates; no repeat verification fee')
on conflict(version) do update set applied_at=now();
commit;
