-- =====================================================================
-- SPHERE — PART 1: UNDO (only if something goes wrong)
-- Removes the checker. Keeps strike history and your data.
-- =====================================================================
drop trigger if exists zz_sp_mod_guard on public.sp_messages;
drop trigger if exists zz_sp_mod_guard on public.sp_jobs;
drop trigger if exists zz_sp_mod_guard on public.sp_applications;
drop trigger if exists zz_sp_mod_guard on public.profiles;
drop trigger if exists zz_sp_mod_guard on public.sp_portfolio;
drop trigger if exists zz_sp_mod_guard on public.sp_ratings;
drop trigger if exists zz_sp_mod_guard on public.sp_notifications;
-- Old content can be restored from sphere_backup.*_p1 if ever needed (ask Claude for the exact command).
