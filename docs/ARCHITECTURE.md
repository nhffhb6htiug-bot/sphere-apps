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
| `PART 8: PROJECT WORKFLOW + DEADLINES` | `WORK_CACHE`, `workState()`, `workChip()`, `projectWorkSection()`, countdown timer, preview / more-time actions |
| `PART 7: SELECTION + PAYMENT` | `PAY_STATES`, `projectSummaryCard()`, `acceptAmount()`, `SCREENS.payment`, `payWithRazorpay()` |
| `PART 6: JOB DISCOVERY + BIDDING` | `jobFilter`, `renderAvailList()`, `SCREENS.jobBidScreen`, `submitBid()`, `SCREENS.applications`, `selectBid()` |
| `PART 5: JOB POSTING + AI` | `SCREENS.postJob`, `aiFillJob()`, `localJobParse()`, drafts, `submitJob()`, `jobRequirementsHtml()` |
| `PART 4: EDITOR PROFILE + VERIFICATION` | `AVAILABILITY`, `VERIFY_STATES`, `EDITOR_STATUS`, `loadEditorWork()`, editor dashboard, My Jobs tabs, `editorProfileEdit`, fee + reject flows, `profileUpdate()` |
| `PART 3: CLIENT PROFILE + DASHBOARD` | `CLIENT_STATUS`, `loadClientProjects()`, home dashboard, My Projects, Edit Profile |
| `PART 2: AUTH + ROLE ACCESS` | `ROUTE_ACCESS`, `routeGate()`, `clearSessionState()`, account status (suspended banner) |
| `CONTACT PROTECTION` | Warning popups for hidden contact details |

### Roles and modes
* Database `profiles.role`: `CLIENT`, `EDITOR`, `ADMIN` (capital letters; the guard trigger keeps it that way).
* App user object: `baseRole` = real role, `role` = current mode.
  * An **editor** can switch to **Client mode** (hire / post jobs).
  * An **admin** can switch to **Editor mode**.
* Only admins can create admins (`sp_make_admin`) or give the ✔ tick (`sp_verify_editor`). The `sp_core_profile_guard` trigger blocks anyone trying to do this directly through the API.

### Login, session and access (Part 2)
* **Register:** email + password (role Client or Editor, phone) or Google (then pick role + phone). Nobody can register as Admin — the database turns it into Client.
* **Login:** email/password or Google. Admins land on the Admin Panel, everyone else on Home.
* **Session:** kept in the browser (`sb-pwcchgjsgkwrsvbzqspp-auth-token`) and refreshed automatically. If the session ends (logout in another tab, expired login) the app clears everything and returns to the welcome screen.
* **Logout:** clears the user, chat connection, Admin PIN, open job/chat and AI history.
* **Every screen is checked** by `routeGate()` inside `nav()` using `ROUTE_ACCESS`:

| Access | Who | Screens |
|---|---|---|
| public | anyone | splash, onboard1-3, authLanding, login, signup, resetPassword |
| auth | logged in, profile not finished | chooseRole, addPhone |
| user | any finished account | home, editProfile, profile, settings, notifications, chats, support, reports, Sphere AI, categories, editors, editor profile, jobs, project, portfolio, escrow, vault |
| client | Client mode (client · editor switched to Client · admin in Admin mode) | postJob, applications, payment, savedList, ratings |
| editor | Editor mode (editor · admin switched to Editor) | jobBidScreen |
| editorAccount | Editor account (any mode) or admin in Editor mode | editorDetails, verificationStatus, editorProfileEdit |
| admin | Admin accounts | admin |

* **Job screens** also check the job: `applications`, `payment`, `ratings` → only the job's client (or an admin); `projectStatus` → client, assigned editor, admin, or anyone while the job is open.
* **The database enforces the same rules** (`sp_core_role_guard`): only editors bid (for themselves), only editors edit their own portfolio, only the job's client reviews that job's editor. Screen checks are for the user experience; database checks are the real security.

### Client side (Part 3)
* **Home (Client mode):** greeting + 3 counters (Active · Need you · Completed), "Needs your action" (bids to choose, price to answer, payment, video to review), recent projects, and an empty state with *Post a job* / *Browse editors*. It loads after Home appears, so Home stays fast.
* **Bottom bar for clients:** Home · Chat · **Projects** · Profile (editors keep Home · Chat · Portfolio · Profile).
* **My Projects** (`jobs` screen for Client mode): tabs **Active / History / All** with counts, friendly status chip, progress bar, "what you need to do" line, editor name, amount, dates. Editors still see the old Jobs list.
* **Friendly status names** (`CLIENT_STATUS`): open → Waiting for bids · negotiating → Agreeing on price · payment-pending → Payment needed · in-progress → Editor is working · delivered → Ready for review · approved → Approved · closed → Completed · refunded → Refunded · expired → Expired.
* **Project page:** clients see one line on top with the status and their next step.
* **Profile:** account type, member since, Projects / Completed / Paid via Sphere.
* **Edit Profile** (`editProfile`, every role): photo, full name, mobile number; email is read-only.

### Editor side (Part 4)
* **Editor Home:** verification card (Pending / Fee submitted / Not approved / Verified), greeting, **status for clients** (Available · Busy · Away), rating, active and completed counts, money earned, "Your active work" with the next step, then the existing Available Work list.
* **My Jobs** (`jobs` screen in Editor mode): tabs **Available / My work / History** with editor-friendly status names (`EDITOR_STATUS`).
* **Profile (Editor mode):** availability + verification chips, bio, rating / completed / active, latest reviews; menu **Edit editor profile** and **Verification status**.
* **Edit editor profile** (`editorProfileEdit`): bio (300 letters), status, categories, languages, skills, experience, price, portfolio + sample links. Changing **categories** on a verified account removes the ✔ tick until Sphere checks again; other fields keep the tick. The first application (`editorDetails`) still works as before.
* **Verification states** (`profiles.verification_status`): `not_applied → pending → approved` or `rejected` (with reason). The existing ✔ Verify (`sp_verify_editor`) and remove-tick (`sp_unverify_editor`) keep working and move the state automatically.
* **₹29 fee:** pay by UPI (QR / button, as before) → editor types the **UPI transaction ID** → `fee: submitted` → admin taps **Fee received** or **Fee not found**. WhatsApp screenshot still works too. The 3-free-works rule is unchanged.
* **Admin → Pending Verification:** state chip, fee line with UTR, buttons *Fee received · Fee not found · Reject (reason) · Re-open*, plus the existing *Verify after call*. Admins get a notification when an editor applies or submits a fee.
* **Public editor page:** status chip + bio (from the `sp_editor_public_extra` view).

### Job posting (Part 5)
* **Post a Job** (`postJob`) has 3 steps on one screen:
  1. **Describe** in your own words (Hindi / English / Hinglish) → **✨ Fill the form with AI**, or skip and fill it yourself.
  2. **Form**: title, category, details, budget, deadline, video length, format (9:16 / 16:9 / 1:1 / 4:5), language, style / special requirements, reference links, revisions expected, raw files (upload or link).
  3. **Review** → **Post job** (status `open`) or **Save as draft**.
* **AI fill:** sends the request to the existing `sphere-ai` function asking for a JSON form; if that fails it tries the existing `draft_job` action; if the AI is down a built-in reader (`localJobParse`) still picks up budget, deadline, length, format, language, category and style words. The client can change every field.
* **Drafts:** `sp_job_drafts` (only the client can see them; editors never do). My Projects → **Drafts** tab → Continue / Delete. Posting a draft creates a normal `open` job and removes the draft. Files are added when posting.
* **Direct hire** (Hire Now on an editor) uses the same form and still creates a `negotiating` job for that editor. The Sphere AI chat button "Turn this chat into a job post" opens the form already filled.
* **Job pages** (client project page + editor bid screen) show the structured requirements and a "Written with Sphere AI" tag.
* Contact protection also checks title, style and reference links. "Instagram reel" is no longer a warning word (only "insta id", "insta pe", "DM me" …).

### Job discovery + bidding (Part 6)
* **Editors → Jobs → Available:** search box, category (or "My categories"), deadline (within 3 / 7 / 14 / 30 days), min / max budget, sort (newest, budget, deadline, fewest bids). Each job shows budget, due date, length, format, number of bids, "Matches you" and **your own bid** (✓ You bid ₹… / selected / not selected). Expired jobs are hidden.
* **Bid screen** (`jobBidScreen`): job details + **price**, **delivery days**, **message** (20–600 letters, contact details hidden). Shows "you receive ₹… after the Sphere fee". One bid per job; a pending bid can be **changed** until the client chooses.
* **Who may bid** (`sp_bid_eligibility`, same rule in app and database): verified ✔ editors; editors who applied and are waiting for verification may do their first `free_works` (3) paid works (today's rule, unchanged). Not allowed: not-applied, rejected, suspended, status "Away", own job, closed or expired job. Setting `bids_verified_only = 1` makes it verified-only.
* **Client → Bids** (`applications`): sort Recommended / Lowest price / Fastest / Top rated, **Compare** table, badges (Lowest price, Fastest, Top rated), editor rating, jobs done, availability, verified tick.
* **Choose this editor** (`sp_bid_select`, one database step): job → that editor, status `negotiating` with the bid as the editor's price (same as before, the client then locks it); the chosen bid → `selected`; **all other bids → `rejected`**; everyone is notified. A second choice is refused.

### Selection + payment (Part 7)
* **Project = the job + its chosen editor.** Shown everywhere as **Project SPH-XXXXXX** (from the job id).
* **Project card** on the project page (client, editor, admin): project code, the other person, price, delivery days (from the chosen bid), deadline, **payment status chip**. Clients see only what they pay; editors see "You receive"; Sphere's fee is never shown to clients.
* **Accept the price** → `sp_pay_lock_price` (database checks it is the *other* side's price) → status `payment-pending` → the client goes straight to **Payment**. Counter-offers work as before.
* **Payment screen:** project, editor, delivery, total to pay ("includes everything"), what happens next, secure pay button (test-mode note when using `rzp_test_`). Paid / refunded / not-ready projects show a clear message instead of a pay button.
* **Checkout:** `sp_pay_start` (ready? already paid?) → existing `create-razorpay-order` (amount from the project, never from the app) → Razorpay → `sp_pay_record` (order/payment IDs, or the failure reason) → existing `verify-razorpay-payment` marks the project paid.
* **Payment record** `sp_payments` (one per project): `pending → paid` (or `failed`, then retry) → `refunded`. Paid / refunded only come from the server (job row updated by the Edge Functions → trigger). Client and editor can read their own; nobody can change it from the app.
* **Duplicate protection:** one record per project, `sp_pay_start` refuses a paid project, the pay button locks while paying; if Razorpay still reports a second payment it is kept in `duplicate_refs` and admins are told to refund it.
* **Sphere's split** (editor share, Sphere fee, bonus pool) is stored in `sp_payment_splits`, admins only.
* Note: the older `sp_jobs.editor_amount / platform_fee` columns are still filled by the Edge Functions; the app never shows them to clients. Hiding them at the database level needs the Edge Function code.

### Project workflow + deadlines (Part 8)
* **Work clock** (`sp_project_work`) starts automatically when a project is paid (status → `in-progress`). Projects already in progress when 008 was installed start their clock at that moment (no surprise "late").
* **Deadline** = 24 hours × the delivery days the editor promised in the bid (no days → 24 h). Then a **4-hour grace period**, then **late**. Settings: `work_default_hours` (24), `work_grace_hours` (4), `work_reminder_hours` (4), `work_fixed_hours` (0 = use the bid; e.g. 24 = every project 24 h).
* **States:** Not started → On track → Due soon (last 4 h) → Grace period → Late; Preview sent (on time / late); Completed (final video delivered); Cancelled (refunded).
* **Project page:** live countdown (hh:mm:ss), progress bar, start + deadline times (IST), grace explanation.
  * Editor: **Send preview** (watermarked link: Drive / YouTube unlisted / WeTransfer / Dropbox) → client is told; can update the preview link. **Ask for more time** (+2…72 h with a reason).
  * Client: **answer the request** (give / no) or **give more time** (+2…48 h) any time while the editor is working. An approved extension moves the deadline (from the old deadline, or from now if it already passed) and clears "late".
  * The existing final video submission stays below ("send after the client has seen your preview").
* **Timeline** (`sp_project_events`) on the project page: posted, editor chosen, price locked, paid, payment failed, work started, reminder, deadline passed, late, time asked / given / refused, preview sent / updated, delivered, approved, completed, refunded.
* **Notifications** (once each per deadline): project started (both), 4 hours left (editor), deadline passed + grace (both), late (both), preview ready (client), time asked (client), time given / refused (editor). `sp_work_tick()` checks every 10 minutes when pg_cron is available, and every time someone opens the app.
* **Lists:** My Projects and the editor's work show chips (⏳ due in…, ⚠️ grace, 🔴 late, 👀 preview) and "what to do next".

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
