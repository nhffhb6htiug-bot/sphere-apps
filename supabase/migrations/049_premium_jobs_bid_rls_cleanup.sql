-- 2026-10-28 security audit: remove obsolete permissive RLS policies.
-- sp17_jobs_read and sp17r_jobs_read still grant parties/admins access
-- and allow open work only to the correct editor audience.
-- The sp_jobs_select policy below otherwise bypassed premium audience filtering.
DROP POLICY IF EXISTS sp_jobs_select ON public.sp_jobs;

-- The legacy ALL + DELETE policies allowed an editor to remove a selected bid,
-- defeating the newer sp204r_apps_delete restriction. Preserve newer
-- specific SELECT/INSERT/UPDATE policies and sp204r_apps_delete for removals.
DROP POLICY IF EXISTS sp17_apps_write ON public.sp_applications;
DROP POLICY IF EXISTS sp17r_apps_delete ON public.sp_applications;
DROP POLICY IF EXISTS sp_applications_delete ON public.sp_applications;
