-- =====================================================================
-- SPHERE — PART 1, STEP 1: Backup (run this FIRST)
-- Makes a copy of the tables Part 1 touches, inside the same database,
-- in a private "sphere_backup" area that the app/API cannot see.
-- =====================================================================
create schema if not exists sphere_backup;
revoke all on schema sphere_backup from public, anon, authenticated;

create table if not exists sphere_backup.profiles_p1         as table public.profiles;
create table if not exists sphere_backup.sp_messages_p1      as table public.sp_messages;
create table if not exists sphere_backup.sp_jobs_p1          as table public.sp_jobs;
create table if not exists sphere_backup.sp_applications_p1  as table public.sp_applications;
create table if not exists sphere_backup.sp_portfolio_p1     as table public.sp_portfolio;
create table if not exists sphere_backup.sp_ratings_p1       as table public.sp_ratings;
create table if not exists sphere_backup.sp_reports_p1       as table public.sp_reports;
create table if not exists sphere_backup.sp_settings_p1      as table public.sp_settings;
create table if not exists sphere_backup.sp_notifications_p1 as table public.sp_notifications;

-- Check: row counts of the copies
select 'profiles' as copy, count(*) from sphere_backup.profiles_p1
union all select 'messages', count(*) from sphere_backup.sp_messages_p1
union all select 'jobs', count(*) from sphere_backup.sp_jobs_p1
union all select 'bids', count(*) from sphere_backup.sp_applications_p1;
