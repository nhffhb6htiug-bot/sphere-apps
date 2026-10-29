-- Sphere security audit: reject notification sender impersonation from public clients.
-- Signed-in browsers / APKs may create user-facing notifications but must not
-- impersonate another user or mark them as privileged/administrative.
-- The trusted service role / server-side functions retain existing behavior.
CREATE OR REPLACE FUNCTION public.sp_notif_before()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  r public.sp_notifications;
  from_app boolean := current_user IN ('authenticated','anon');
BEGIN
  IF from_app THEN
    NEW.sender_id := auth.uid();
    NEW.audience := 'user';
    NEW.important := false;
    NEW.link := NULL;
    NEW.dedupe_key := NULL;
    NEW.is_read := false;
    NEW.read_at := NULL;
    NEW.push_status := 'none';
    NEW.email_status := 'none';
    NEW.title := left(coalesce(NEW.title,''), 80);
    NEW.body := left(coalesce(NEW.body,''), 300);
    IF NEW.category IN ('admin','security') THEN NEW.category := NULL; END IF;
  END IF;

  -- Preserve old best-effort behavior for notification processing errors,
  -- but privileged user-supplied fields have already been sanitized.
  BEGIN
    r := sphere_private.sp_notif_process(NEW, from_app);
  EXCEPTION WHEN OTHERS THEN
    RETURN NEW;
  END;
  RETURN r;
END
$function$;
