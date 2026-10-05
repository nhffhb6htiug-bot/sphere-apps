# Sphere — Architecture

Sphere by Syahi Films connects clients with video editors. This file describes how the project is built **today** and the rules every new part follows.

## 1. The big picture

```
 Phone / browser                     Cloudflare Worker (proxy)              Supabase (backend)
 ┌──────────────────────┐           ┌───────────────────────────┐         ┌──────────────────────────┐
 │ Website (PWA)         │──HTTPS──▶│ sphere-api.niteshkumar... │──────▶ │ Auth (email + Google)     │
 │ sphere-live.onrender  │           │ .workers.dev              │         │ Postgres + RLS            │
 │ Android app (Kotlin)  │──HTTPS──▶│ (works where ISPs block    │         │ Storage (3 buckets)       │
 └──────────────────────┘           │  *.supabase.co)            │         │ Realtime (chat)           │
            │                        └───────────────────────────┘         │ Edge Functions (5)        │
            │ Razorpay Checkout                                              └───────────┬──────────────┘
            └──────────────────────▶ Razorpay (orders, escrow, Route payouts) ◀──────────┘
```

| Piece | Where | Notes |
|---|---|---|
| Website | `index.html.html` (one file, ~670 KB) | Render static site. Build command copies it to `index.html`. No build step. |
| Android app | `android-native/` (Kotlin, Jetpack Compose) | Built by GitHub Actions on every change in that folder → `builds/Sphere-native.apk` |
| Hosting | Render (free static site) | Auto-deploys on every commit to `main` |
| Backend | Supabase project `pwcchgjsgkwrsvbzqspp` (free plan) | Kept awake daily by `.github/workflows/keep-supabase-awake.yml` |
| Proxy | Cloudflare Worker `sphere-api.niteshkumarmatho37.workers.dev` | Both apps talk to Supabase only through this |
| Payments | Razorpay (test key `rzp_test_…`) | Order → verify → escrow → `release-payout` (Route) or `refund-payment` |
| AI | Edge Function `sphere-ai` (Google Gemini, free tier) | Key is a Supabase secret, never in the app |

## 2. Repository layout

```
/                         ← published as the website by Render
├── index.html.html       ← THE web app (Render copies it to index.html)
├── contact.html  privacy.html  refund.html  terms.html
├── manifest.json  sw.js  icons (*.png)  verify-fee-qr.png
├── android-native/       ← native Android app
├── builds/               ← APK + build report (written by GitHub Actions)
├── .github/workflows/    ← Android build, keep Supabase awake
├── docs/                 ← ARCHITECTURE.md, DATABASE.md, ROADMAP.md
└── supabase/
    ├── migrations/       ← database changes, numbered, run in order
    ├── checks/           ← read-only check queries (safe any time)
    └── functions/        ← Edge Function source (copy from the dashboard)
```

**Why the website stays one file:** `sw.js` serves same-origin files cache-first, so splitting the app into many `.js` files would let phones run a new `index.html` with old scripts. One file + network-first page loading avoids that, needs no build tool, and can be updated with GitHub's "Upload files" button.

## 3. Inside `index.html.html`

The script starts with a **map of headings**. Search for them:

| Heading | What it holds |
|---|---|
| `CONFIG` | `SPHERE_CONFIG`: app version, Supabase URL + publishable key, Razorpay key id, Google client id, `features` switches |
| `ROLES` | `ROLES`, `normRole()`, `dbRole()`, `isAdminUser()`, `isEditorAccount()`, `usingMode()` |
| `SETTINGS` | `loadSettings()` / `getSetting(key)` — admin values from `sp_settings` with safe defaults |
| `DATA HELPERS` | Supabase reads (`publicEditors`, `getProfilesByIds`, `mapJob` …) |
| Screens | `SCREENS.<name> = () => html` — `nav('<name>')` renders a screen into `#app` |
| `CHAT` | WhatsApp-style chat, realtime, media, voice notes |
| `PAYMENT` / `PROJECT STATUS` | Razorpay checkout, escrow, delivery, approve & release |
| `ADMIN` | Admin Panel (PIN unlock), verification, reports, payouts, suspicious users, system status |
| `CONTACT PROTECTION` | Warning popups for hidden contact details |

### Roles and modes
* Database `profiles.role`: `CLIENT`, `EDITOR`, `ADMIN` (capital letters; the guard trigger keeps it that way).
* App user object: `baseRole` = real role, `role` = current mode.
  * An **editor** can switch to **Client mode** (hire / post jobs).
  * An **admin** can switch to **Editor mode**.
* Only admins can create admins (`sp_make_admin`) or give the ✔ tick (`sp_verify_editor`). The `sp_core_profile_guard` trigger blocks anyone trying to do this directly through the API.

### Job lifecycle (today)
`open → negotiating → payment-pending → in-progress → delivered → approved → closed` (+ `refunded`)
Payout status: `awaiting · held · released · manual · failed · paid-manually`

## 4. Configuration and secrets

| Value | Lives in | Public? |
|---|---|---|
| Supabase URL (proxy), publishable key, project ref | `SPHERE_CONFIG` | Yes (safe) |
| Razorpay **key id** | `SPHERE_CONFIG.razorpayKeyId` | Yes (safe) |
| Google OAuth client id | `SPHERE_CONFIG.googleClientId` | Yes (safe) |
| Razorpay **secret**, Gemini API key, service-role key | Supabase → Edge Functions → Secrets | **Never in the app or GitHub** |
| Fees, limits (₹29, ₹50, ₹199, 5%, 3 strikes …) | `sp_settings` table (Admin Panel) | Read by the app |
| Android equivalents | `android-native/.../data/Config.kt` | Same rules |

The GitHub repo is **public**, so anything committed can be read by anyone.

## 5. How every new part is added (the rules)

1. **SQL** → `supabase/migrations/00N_<name>.sql`. It must be safe to run twice, must not delete data, and ends by inserting its row into `sp_schema_versions`.
2. **Web code** → a block `/* ============ PART N: <NAME> ============ */` near the end of the script. Existing features are not removed without discussing it first.
3. **Switch** → add/flip `SPHERE_CONFIG.features.<name>` so a part can be turned off quickly.
4. **Check** → add a read-only query to `supabase/checks/` and list the manual test steps in `docs/ROADMAP.md`.
5. **Version** → bump `SPHERE_CONFIG.appVersion`; Settings shows it, Admin → System status shows installed parts.
6. **Android** → ported in batches (Part 9). Database-side rules (like contact protection) already protect the Android app.

## 6. Deploying

| What | How |
|---|---|
| Website | GitHub → `sphere-apps` → Add file → Upload files → `index.html.html` (exact name) → Commit. Render publishes in 1–2 minutes. |
| Database | Supabase → SQL Editor → + → paste the migration → Run. Then run the matching check. |
| Android | Commit changes inside `android-native/` → GitHub Actions builds `builds/Sphere-native.apk`. |
| Undo website | GitHub → `index.html.html` → History → open the previous version → upload it again. |
