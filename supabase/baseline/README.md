# Production schema baseline

**Status: not exported yet.** The schema baseline must be exported directly from the database with
`pg_dump --schema-only` (tables, functions, triggers, RLS policies, grants — no data rows).
It could not be produced from inside the chat assistant, because the only access there is SQL query
output, and copying hundreds of functions and policies by hand would not be exact or verifiable.

How to create it: see `export_schema.sh` (one command on your computer). It refuses to finish if the
file contains data rows or secret-like text.

Why it matters: migrations 009 and 016–030 are not in this repository (they were applied to production
but their files were lost), so the migrations folder alone cannot rebuild the production database.
`schema.sql` closes that gap. Do not apply it to production.
