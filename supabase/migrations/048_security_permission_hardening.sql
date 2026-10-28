-- Cross-platform audit 2026-10-28: restrict dangerous PostgreSQL grants.
-- These privileges bypass or undermine row-level protection. No app client needs
-- TRUNCATE, TRIGGER, REFERENCES or MAINTAIN on user-facing tables.
-- Preserve normal SELECT/INSERT/UPDATE/DELETE and service_role access.
DO $$
DECLARE t record;
BEGIN
  FOR t IN
    SELECT n.nspname, c.relname
      FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='public' AND c.relkind IN ('r','p')
  LOOP
    EXECUTE format(
      'REVOKE TRUNCATE, TRIGGER, REFERENCES, MAINTAIN ON TABLE %I.%I FROM anon, authenticated',
      t.nspname, t.relname
    );
  END LOOP;
END $$;

-- The old policy gave every logged-in user unrestricted access to every
-- profile row (including phone/email). RLS already has sphere_profiles_read
-- covering own profile, admins and project/chat participants, plus an explicit
-- sanitized sp_public_profiles view for the editor directory.
DROP POLICY IF EXISTS sp17_prof_read ON public.profiles;
