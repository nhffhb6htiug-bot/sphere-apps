# Sphere — minimal automated tests

Run everything: `bash tests/run_all.sh`

| Group | File | What it checks | Needs |
|---|---|---|---|
| Database | `tests/db/fixture.sql` + `tests/db/test_blocking.sql` | Migrations 031 + 032: a block hides the phone number, refuses unlock and the ₹5 payment start, uses no free access; unblocking restores it; messages refused both ways while blocked; Sphere team exempt; privileges | PostgreSQL 14+ (local), `createdb`, `psql` |
| Unit | `tests/unit/payment_signature.test.mjs` | Runs the real `sameText` / `hmacHex` from the deployed payment functions: correct signature accepted, changed / shorter refused, never `!==`; webhook refuses without its secret, records each event once, checks the amount; extra-payment takes the amount from the database, owner-only, reuses the open order | Node.js 18+ |
| Browser | `tests/browser/premium_badge_test.py` | 💎 badge from the server answer only: active → shown, free → hidden, cached 5 min, expired → removed, logout clears | Python 3 + `pip install playwright` + `playwright install chromium` |

Notes
- The database fixture is isolated test data, never production. `sp_contact_check` / `sp_contact_free_left` are simplified stand-ins.
- The browser test mocks the server answer (`sp_is_premium_client`); it does not touch Supabase.
- Nothing here makes real payments or uses secrets.
