-- First-50 editor screenshot uploads need a PERMISSIVE policy as well as the
-- existing restrictive rules; without this all INSERTs are denied by RLS.
-- Scope new permissions solely to the private screenshot-proof bucket.
BEGIN;

DROP POLICY IF EXISTS sp_editor_proof_insert_allow ON storage.objects;
CREATE POLICY sp_editor_proof_insert_allow ON storage.objects
AS PERMISSIVE FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'sphere-editor-proof'
  AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
  AND coalesce((public.sp_editor_offer_status()->>'is_free')::boolean, false)
);

DROP POLICY IF EXISTS sp_editor_proof_read_allow ON storage.objects;
CREATE POLICY sp_editor_proof_read_allow ON storage.objects
AS PERMISSIVE FOR SELECT TO authenticated
USING (
  bucket_id = 'sphere-editor-proof'
  AND (
    (storage.foldername(name))[1] = (SELECT auth.uid())::text
    OR public.is_admin()
  )
);

DROP POLICY IF EXISTS sp_editor_proof_delete_allow ON storage.objects;
CREATE POLICY sp_editor_proof_delete_allow ON storage.objects
AS PERMISSIVE FOR DELETE TO authenticated
USING (
  bucket_id = 'sphere-editor-proof'
  AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
);
COMMIT;
