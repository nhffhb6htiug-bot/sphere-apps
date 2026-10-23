# Sphere — database backup & restore

**What:** every night at 03:00 (India) GitHub Actions copies the Sphere database (schemas public, sphere_private,
auth, storage — users, logins, jobs, chats, payments, settings), checks it, encrypts it with AES-256 and keeps it
for 30 days under **Actions → Nightly database backup → (a run) → Artifacts**. A failed backup sends you an email.
Files in Supabase Storage (preview / raw videos) are not in this backup.

**Setup (once, from the phone):** see the steps Claude sent — two secrets: `SUPABASE_DB_URL`, `BACKUP_PASSPHRASE`.
Write the passphrase down somewhere safe (not in the repo): without it a backup cannot be opened.

**Backup now:** Actions → Nightly database backup → Run workflow.

**Restore (needs a computer, or ask Claude):**
1. Download the artifact zip and unzip it (`sphere-db-YYYY-MM-DD.dump.gpg` + `.sha256`).
2. `sha256sum -c sphere-db-YYYY-MM-DD.sha256`
3. `gpg -d sphere-db-YYYY-MM-DD.dump.gpg > sphere.dump` (asks for the passphrase)
4. Restore into a **new, empty** Supabase project (never over the live one):
   `pg_restore --no-owner --dbname="<new project's session pooler URI>" sphere.dump`
5. Re-deploy the Edge Functions and secrets to the new project and point the app at it.

Rehearsed on 23 Oct 2026: dump → encrypt → decrypt → restore into an empty database, every table's row count matched;
a wrong passphrase cannot open the file.
