#!/usr/bin/env bash
# Sphere nightly backup: dump → check → encrypt. Never prints data or secrets.
set -euo pipefail
: "${DB_URL:?SUPABASE_DB_URL missing}"; : "${PASS:?BACKUP_PASSPHRASE missing}"
PGDUMP="${PGDUMP:-pg_dump}"; PGRESTORE="${PGRESTORE:-pg_restore}"
STAMP="${STAMP:-$(date -u +%Y-%m-%d)}"
"$PGDUMP" "$DB_URL" --format=custom --no-owner --no-privileges \
  --schema=public --schema=sphere_private --schema=auth --schema=storage --file=sphere.dump
"$PGRESTORE" --list sphere.dump > toc.txt
for t in "public sp_jobs" "public profiles" "public sp_messages" "public sp_payments" "auth users"; do
  grep -q "TABLE DATA $t " toc.txt || { echo "::error::backup check failed: table $t missing"; exit 1; }
done
SIZE=$(stat -c%s sphere.dump); [ "$SIZE" -gt "${MIN_BYTES:-50000}" ] || { echo "::error::backup too small ($SIZE bytes)"; exit 1; }
gpg --batch --yes --quiet --pinentry-mode loopback --passphrase "$PASS" --symmetric --cipher-algo AES256 --output "sphere-db-$STAMP.dump.gpg" sphere.dump
sha256sum "sphere-db-$STAMP.dump.gpg" > "sphere-db-$STAMP.sha256"
shred -u sphere.dump; rm -f toc.txt
echo "Backup OK: sphere-db-$STAMP.dump.gpg ($(stat -c%s "sphere-db-$STAMP.dump.gpg") bytes, $(grep -c . "sphere-db-$STAMP.sha256") checksum)"
