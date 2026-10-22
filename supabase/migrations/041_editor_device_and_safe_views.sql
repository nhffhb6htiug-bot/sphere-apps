-- =====================================================================
-- SPHERE — (a) SECURITY: public views are read-only; (b) editors say where they edit (Mobile / PC / Both)
-- (a) The public views are owned by postgres, so writing through them skipped row security: before this
--     fix a logged-in user could DELETE another verified editor's profile through sp_public_profiles.
-- (b) profiles.edit_device: the editor fills it in the application; "Verified PC" lists only PC editors.
-- Safe to run again. Deletes NO data.
-- =====================================================================
begin;
revoke insert, update, delete, truncate, references, trigger on public.sp_public_profiles from anon, authenticated;
revoke insert, update, delete, truncate, references, trigger on public.sp_editor_public_extra from anon, authenticated;
revoke insert, update, delete, truncate, references, trigger on public.sp_editor_ratings_public from anon, authenticated;
revoke insert, update, delete, truncate, references, trigger on public.sp_pro_public from anon, authenticated;

alter table public.profiles add column if not exists edit_device text check (edit_device in ('mobile', 'pc', 'both'));
grant select (edit_device), update (edit_device) on public.profiles to authenticated;

create or replace view public.sp_public_profiles as
 select id, role, full_name, skills, categories, experience_years, price_range, sample_video_url, verification_code,
        is_verified, created_at, portfolio_url, avatar_url, verified_by, verified_at, languages, bio, availability,
        edit_device
   from public.profiles p
  where upper(btrim(coalesce(role, ''::text))) = 'EDITOR'::text and coalesce(is_verified, false);
revoke insert, update, delete, truncate, references, trigger on public.sp_public_profiles from anon, authenticated;

insert into public.sp_schema_versions (version, name) values ('041', 'Read-only public views; editors choose Mobile / PC / Both; Verified PC = PC editors')
on conflict (version) do update set applied_at = now();
commit;
