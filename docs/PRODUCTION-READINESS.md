# Canopy OS · Production Readiness Report

Date: 2026-10-12, updated 2026-10-13 · Branch `claude/hanging-garden-coffee-proposal-1m8zd4` · PR #1 (draft)

Nothing was published, no production setting was changed, and the production database was not connected to,
queried or changed from here. Every "production" fact below is either read from GitHub (read-only), read from the
owner's paste of the read-only snapshot (2026-10-12 21:48 UTC, D-027) and of the read-only follow-up query
(2026-10-13 10:49 UTC, D-031), or marked **not verified** with the read-only step that verifies it.

## 1. Verified production status

| Item | Status | Evidence |
|---|---|---|
| What the live site serves | **Verified.** GitHub Pages serves the `gh-pages` branch at `8950054`, an exact copy of development commit `ac8298a`'s `website/` folder (+ CNAME `hanginggardencafe.com`) | `gh-pages` tree compared with `ac8298a:website` (only CNAME differs); 44 `pages-build-deployment` runs, all from `gh-pages` |
| How it got there | **Verified.** The old "Publish website" workflow published on every push to the development branch (48 runs, all `push` events on that branch, last 2026-10-09 23:02 UTC). It was not an approved release | Actions run history |
| Live site isolated from development commits | **Verified for pushes.** Since the manual-only workflow (`c754fc4`, 2026-10-12 16:22 UTC), 27 commits were pushed (20 touching `website/`) and no publish ran. Remaining paths need deliberate action by someone with write access (section 3, R-1) | Run history; workflow triggers; `tests/tools/live-site-check.sh` now fails CI if `gh-pages` is ever not an approved release |
| Default branch | `claude/festive-galileo-0twc1p` (one commit, no workflows) | GitHub API |
| Release tags, releases | None exist | GitHub API |
| Pages / environment / branch-protection settings | **Not verifiable from here** (the GitHub proxy refuses those API paths). Inferred: Pages source = `gh-pages` branch. Environment `production` protection unknown | Owner checks: section 10 |
| Live site reachable | **Not verifiable from here** (the domain is blocked by this environment's network policy) | – |
| Database server | **Verified.** PostgreSQL 17.6, 13 MB; the SQL Editor's account is not a superuser (as rehearsed) and holds `pg_read_all_data` with admin (the backup account no longer uses it: D-033) | Snapshot |
| Migrations installed | **Verified: none.** `canopy.migrations` does not exist; every function the live pages call exists | Snapshot |
| Security configuration (rules, grants, logins) | **Verified.** Rules and grants are as rebuilt from the 18 historical scripts (the same functions without an account check, the same visitor functions); no table without row security; `make_owner` not callable from the pages. The menu-category hole (S-3) is **not** present. **Logins:** 3, all owner kind, none with a phone code, none self-made (every login has an app account); one has never signed in | Snapshot; section 3 |
| Sign-ups, anonymous sign-ins | **Off** (turned off by the owner on 2026-10-12; a dashboard setting, not visible from SQL). No self-made login existed | Owner: E-02 |
| Supabase backups / PITR | **Partly verified.** WAL archiving is on and working (no failures), so Supabase keeps its own copies; whether the owner can restore or download them depends on the plan. Our own backup does not depend on it | Snapshot; owner: Database → Backups page (E-10) |
| Storage | **Verified.** One public bucket, `menu-photos` (8 files, 3.5 MB, fingerprinted); the storage tables belong to Supabase's storage account. The SQL Editor's account (`postgres`) can insert buckets, is not a member of the storage owner and has `policy_grants` on `storage.objects` (privileged role `supabase_privileged_role`): 0015's and 0025's storage statements will run | Snapshot; follow-up (D-031) |
| Schema matches what the repository expects | **Verified; both differences explained.** `audit_menu()` is `supabase/accounts.sql`'s body without one inline comment (same code by three hashes, same trigger and settings): accepted as a known legacy text, no migration. `orders.note` (column 5, text, nullable, no default, never written) is mirrored in the test base tables. With both, the snapshot reports every function `legacy` and no column difference. Triggers on the original tables are identical to the legacy build's 12; indexes and every other original column match (D-027, D-031) | Snapshot; follow-up |

## 2. Backup and restore evidence

No production backup exists yet (E-03). What is ready and proven on test copies:

- **Works before any migration:** `supabase/tools/backup-account.sql` creates the `canopy_backup` account on
  today's schema (no migration needed). It reads the café's tables and the photo list, never the logins (`auth`) or
  the database's passwords, and cannot change the café's data; the paste checks itself and changes nothing on an
  error (D-033). Migration 0002 keeps it that narrow and lets it read the tables later migrations add (0013 for
  `acct`). Logins are not in the backup: they are created again by hand.
- **What each backup proves** (it fails, red in GitHub, otherwise):
  - the dump is restored into a throw-away database;
  - every table has the same rows **and the same content** (md5 of every row);
  - the **rights** are identical (who may run each function, read each table; row security; rules);
  - **every stored photo** was copied with its recorded size.
- **Encrypted** with the owner's two public keys before it leaves the job.
  - Kept as a downloadable run file (14 days), so the first backup needs no paid storage.
  - Offsite storage (R2, free tier) remains recommended for the nightly backups.
- **Test results:**
  - Backup pipeline, before 0000 (legacy schema with photos):
    - dump, restore test, encryption;
    - restore with the offline recovery key;
    - content and photos identical;
    - a missing photo fails the backup.
  - Backup pipeline, after 0025: the same, plus the Home card record and the owner-computer sync.
  - Rehearsal, before the migrations: 115 649 rows, 26 tables, content identical.
  - Rehearsal, after the migrations: 116 004 rows, 58 tables, content identical.
- **Found and fixed (D-024):** a plain restore into a Supabase-like project granted ~50 functions to anonymous
  visitors, including `make_owner` (turns any login into the owner). This is because of Supabase's default
  grants. It affected the disaster-restore path too.
  - Every restore now switches those grants off while loading, then back on.
  - It then compares the rights fingerprint; a difference fails the restore.

## 3. Security findings and remediation

| # | Finding (production today, if sign-ups are on) | Severity | Remediation | Status |
|---|---|---|---|---|
| S-1 | Anyone could create a login with the public key (Supabase default) | High (entry point for S-2 and S-4) | "Allow new users to sign up" and anonymous sign-ins turned off. No page uses sign-up; existing logins, password reset, phone code and "Add user" keep working. No self-made login existed | **Closed 2026-10-12** (owner) |
| S-2 | A self-made login can cancel or mark paid any unpaid room order, change a room's QR code, read sales by product | High | Migration 0001 | Ready, rehearsed |
| S-3 | A self-made login could rename, reorder or recolor menu categories where the legacy "color" rule exists | – | **Not present in production** (the snapshot shows only the owner rule). 0001 still drops it where it exists | Not live |
| S-4 | **New:** the time clock and void functions accept PIN tries from any login (5 tries per 10 min lockout); a stranger could guess PINs or lock staff out | Medium | 0001: café or owner login only | Ready, rehearsed |
| S-5 | Guest room ordering likely fails today (`gen_random_bytes` not on the search path) | Functional | 0001 | Ready, rehearsed |
| S-6 | **New:** a restore from backup opened owner functions to visitors | High (only after a restore) | Section 2 | Fixed, tested |
| S-7 | **New:** migration 0002 failed on PostgreSQL 16+ when the backup account already existed | Blocks backup reporting | Fixed in 0002 | Rehearsed |
| S-8 | **New:** 0003's backfill scanned all lines for each order: 42 s at 14 500 orders, could exceed its 300 s limit on a larger history | Release risk | Same result in one pass + index (0.3 s) | Rehearsed, equality checked |
| S-9 | Findings of the earlier review (D-022) | – | 0025 | Rehearsed |
| L-1 | **New (snapshot):** the café devices use an owner-kind login without a phone code. It behaves like a café login until a PIN is typed (tested), but whoever turns on its phone code becomes the full owner; with no owner-role team member a manager PIN can create one; and Supabase signs out every device on a login without the code each time its code is typed | Medium | Café devices move to a café login (`cafe-login.sql`, E-05) before the new pages are published; the phone code only on the owner's personal login (E-06); both pages that offer the code now warn and ask to confirm | **Identified (follow-up, D-031): case B**, the café devices use a login the owner also uses on a computer; no owner-role team member exists yet. Tool ready and tested; owner (E-05) |
| L-2 | **New (snapshot):** one login has never signed in. Whoever controls that mailbox can set a password through "forgot password" | Medium until identified | The owner says whose it is (E-04); if it is nobody's, `cafe-login.sql` Part 2 revokes its grant (audited). Never on an owner's personal login | **Likely the co-owner's (D-031):** the owner says the co-owner signs in with an existing login; it then stays an owner. Confirmed when the follow-up shows a session on it |
| ST-1 | 0015 and 0025 create storage rules as the SQL Editor's account; production relies on Supabase's `policy_grants` for that | Release risk (low) | Kept strict: a failure applies nothing and the window stops at 0014, where the live pages work (tested). Rights shown by the follow-up query before the window; `release-check.sql` checks the receipt bucket and rules; a lint guard refuses any other storage DDL | Ready; **rights confirmed** by the follow-up (2026-10-13, D-031): can insert buckets, `policy_grants` on `storage.objects` |
| ST-2 | Staging re-runs that empty staging failed on current Supabase (direct deletes from storage tables are refused) | Staging only | The staging reset allows that one delete; rehearsed against an emulation of Supabase's guard | Fixed, rehearsed |
| B-1 | **New (2026-10-13):** the first real backup would have failed its restore test. Supabase's default rights for its own `supabase_admin` in `public` are in the dump, and the throw-away test server has no such role (restore on Supabase and the staging copy too) | Blocked E-03 | Every restore keeps only `postgres`'s own default rights; the backup pipeline test reproduces it (fails before, passes after) (D-029) | Fixed, tested |
| B-2 | **New:** typing the backup account's password in the SQL Editor would leave it in clear in Supabase's logs (DDL is logged) | Secret exposure | The database generates the password and shows it once (`supabase/tools/backup-password.sql`, RESPALDOS 3.4) (D-029); the tool refuses, changing nothing, if the database would record it (`pg_stat_statements.track = all`, `pgaudit.log` all/role, `log_min_messages` debug, a pg_tle passcheck function) or the account is missing; a failed `ALTER ROLE` is re-raised without the statement that carried the password, and a lock wait gives up before the server would log it (D-033 addendum) | Fixed, tested locally |
| B-3 | **New (2026-10-13, before the first paste):** the backup account (`backup-account.sql` version 1 and the old 0002, `pg_read_all_data`) could read every login table (sessions, refresh tokens, recovery links, MFA secrets) and the database's password hashes: a leaked backup password could have signed in as an owner | Secret exposure (high) | Version 2: SELECT on the café's tables and the photo list only, a self-check that changes nothing on a problem, a rollback tool; 0002/0013 keep it narrow; logins no longer copied; the café's owner-rights trigger functions no longer run for every login (the account could otherwise change a bill through a trigger on a temporary table; the paste and 0025) (D-033) | Fixed, tested; not yet pasted (E-03) |
| B-4 | **New:** the restore checks sorted rows by the server's language (a restore database sorting like glibc `en_US` failed the nightly test), and a backup taken while a sale was saved failed `restore.sh` (the archive held the count after the copy) | Could block E-03 / a restore | `collate "C"` in every fingerprint; the archive keeps the counts and fingerprints of the restored dump (D-033) | Fixed, tested (each case fails on the old code) |
| P-1 | **New:** the new POS (not yet published) lost a sale rung on a login with no café grant (`no_account` answered with HTTP 200 was taken as saved) | High, before publishing | The sale stays on the device and goes in once the login is connected; e2e test fails without the fix (D-030) | Fixed, tested |
| PR-1 | **New:** the staging copy kept free text in several columns (order notes, void and discount reasons, room codes, device names; after the migrations also "who did it" emails and bank descriptions) | Privacy (staging) | Every text/json/network column classified; an unknown one stops the copy; seeded scan finds nothing (D-028) | Fixed, tested |
| R-1 | Residual release risk: older workflow files in history publish on push to `main`, `claude/festive-galileo-0twc1p` or the development branch. `gh-pages` accepts direct pushes. None of this happens through normal development | Low | Environment reviewers (E-20), save today's site (E-19), CI tripwire (added) | Owner settings |
| R-2 | Accepted lows from D-022 (`_tender_insert`, `_stock_cost_edit_log`) and helper functions that need an order's UUID | Low | Documented | Accepted |

The snapshot lists every rule without an account check and every function a login can call without one. The
rehearsal compares them with the reviewed list after the migrations.

## 4. Staging test results

- **Local rehearsal standing in for staging** (every CI run, `tests/run.sh rehearsal`):
  - production's schema as rebuilt from the 18 historical scripts;
  - about 4 months of café history: 14 534 sales, 38 280 lines, 60 548 stock moves, 250 part payments,
    208 voids, 420 discounts, 291 room orders, 121 register days, 482 shifts, 74 bills paid on a later day.
- **Live pages:** the pages live today (`8950054`), run in a real browser against the migrated copy:
  - every page loads with no script error and no refused API call (café, owner with and without the phone code,
    visitor);
  - a sale; an offline sale uploaded after reconnecting; a time-clock punch;
  - the Menu Manager recolors a category and moves it to the kitchen;
  - nothing reaches the real Supabase. 5/5 passed.
- **Staging copy flow:** read-only copy → anonymized (names, guests, suppliers, PINs, logins, `orders.note`) →
  empty Supabase-like project → migrations. Rights identical to the source, data checks identical. Then loaded a
  second time into the same project, emptied first, under an emulation of Supabase Storage's delete guard
  (storage-api 0055): passes (D-027). A failed copy or anonymization prints no data row and no PIN to the log.
- **The owner's real-data staging rehearsal is not done:** it needs the staging project (E-13).
  It is one button in the private repository ("Ensayo en pruebas").

**Full automated run** (`tests/run.sh`, 2026-10-13, also in CI on every push), all passed:

| Stage | Result |
|---|---|
| Lint (no secrets, release rules, plain-SQL migrations, environments incl. "staging never on production", no storage DDL beyond bucket inserts and storage policies) | ok |
| SQL tests | 27 files (incl. the 0001 additions: stranger cannot edit categories, punch, guess or void; the release check's storage keys; `cafe-login.sql` run as shipped, both parts and every refusal; the follow-up query read-only, its devices section and what it never shows) |
| Backup pipeline (before 0000 and after; content, rights, photos, encryption, offline-key restore, computer sync) | ok |
| Migration rehearsal (sections 4 and 5, with the staging-copy flow) | ok |
| Live pages on the migrated copy | 5/5 |
| Browser tests of the new pages | 93/93 (incl. the supplier XML import, the phone-code warning in English and Spanish, and a sale on a login without café grant kept on the device) |
| Database consistency and security checks | inside the rehearsal: identical "kept" values, no new problems, reviewed rules only, ledger balanced |
| Backup restoration | before and after the migrations: rows, content and rights identical |

## 5. Migration results (rehearsal)

- **0000 → 0028**, each file as one transaction, applied as a non-superuser account like Supabase's SQL Editor:
  - **2.1 s in total**; the slowest is 0004 (0.5 s);
  - no file failed after the fixes above.
- **Nothing that existed changed.** All 26 original tables (every original column, md5) and 27 business checks
  are identical before and after:
  - sales by day and by method, lines, part payments, discounts, voids;
  - register days, stock on hand and moves, shifts, staff, logins, audit log, menu.
- **The structure after the window:**
  - every function body is a known version;
  - no table without row security;
  - only the four public functions run for visitors;
  - only the reviewed rules lack an account check;
  - the ledger is balanced; receipt numbers unique; every paid sale has its business day and location.
- **Regulated switches arrive OFF** (checked): prices as today, automatic books, e-invoices, cashier
  attribution; no confirmation recorded.
- **The day after the window:**
  - an offline sale from before the window is saved on its own day and flagged for the manager (never refused);
  - old-page and new-page sales, the open bill, the void, the room order, the old inventory calls and the old
    register close all work.
- **Books on old history:** 30 days posted, debits = credits, and revenue + IVA = sales (₡26 765 300) colón for
  colón. Cash, card, SINPE and other each tie to their accounts.

## 6. Outstanding regulatory dependencies

None of these is claimed complete. They stay OFF or unbuilt until the owner, the accountant or an official
source confirms them (docs/DEPENDENCIES.md):

- **A-01** regime and proportional credit (IVA return layout).
- **A-02 / A-10** e-invoicing tool and provider: **electronic invoicing is NOT implemented.** The document
  register is record-only and off. The provider connection, XML signing, sending and contingency need a
  provider and Hacienda credentials.
- **A-03** price display. **Tax-exclusive pricing** (the owner's policy: prices before IVA, tax added at checkout)
  is built and **OFF** (D-026).
- **A-04** IVA and CABYS per product.
- **A-05** service charge (not built).
- **A-06** USD rate policy. **The automatic exchange rate is NOT complete:** it needs the `http` and `pg_cron`
  extensions (E-16) and a first live check of Hacienda's answer. A manager types the rate meanwhile.
- **A-07** chart of accounts, costing and revenue timing (automatic posting OFF).
- **A-08** payroll: **payroll compliance is NOT implemented.** No CCSS, INS or income-tax rate is built in;
  payroll computes gross pay only until each rule is confirmed with its source.
- **A-09** retention.

## 7. Remaining incomplete features

Finished in this round (no regulator, credentials or paid service needed):

- the supplier's electronic invoice (Hacienda XML 4.3/4.4) fills in the supplier invoice form (tested in English
  and Spanish);
- the release runbook, with a way back to today's site after the first release;
- the backup, staging and rehearsal tooling above.

Not done, and why:

| Feature | Why not |
|---|---|
| E-invoice sending, signing, contingency; POS "invoice with ID" sending; the IVA return filing | Provider, credentials and Hacienda rules (A-02, A-10, A-01) |
| CCSS/INS files, aguinaldo and vacation accruals, income-tax withholding | Payroll rules unconfirmed (A-08) |
| Dollar bank accounts | Exchange-difference policy (A-06) |
| Storing the 50-digit key of imported supplier invoices | Needs a schema change; kept out of the rehearsed release set. Can be the first migration after the window |
| Operating a second location (registers and stock per location) | No second location; the data model is ready (D-021) |
| Automatic exchange rate | E-16 and a live check (A-06) |

## 8. Exact production deployment sequence

Each step is the owner's. I give them one at a time and check each result before the next. "Snapshot" means
`supabase/tools/production-snapshot.sql`; it is read-only.

**A. Verify and protect (any time; only step 6 changes access rows, and may add an owner's new login)**

1. ~~Snapshot → paste.~~ **Done 2026-10-12** (section 1, D-027).
2. ~~Authentication → turn off "Allow new users to sign up"; anonymous sign-ins off.~~ **Done 2026-10-12** (owner).
3. ~~Follow-up query `production-followup.sql` (read-only) → paste the cell.~~ **Done 2026-10-13** (D-031): case B;
   storage rights confirmed; both schema differences explained. The owner decided the account structure (D-031):
   two owners on their own personal logins, the shared login restricted to the café devices, staff on PINs.
4. **Next:** verified backup (docs/RESPALDOS.md):
   - ~~`backup-account.sql`~~ **Done 2026-10-13** (version 2, D-033): production returned the expected row `lista: la
     cuenta canopy_backup puede leer 26 tablas del café y la lista de fotos; no puede cambiar los datos del café ni
     leer las cuentas de acceso (aún no puede entrar: paso 3.4)`. The first attempt stopped on a false alarm and kept
     nothing (D-033);
   - the account's password is generated by the database (`supabase/tools/backup-password.sql`, RESPALDOS 3.4) while
     building the `CANOPY_DB_URL` secret, so it never appears in a saved query or in the Postgres log (Supabase logs
     DDL); the tool refuses, changing nothing, if the database would record it, and any ERROR changed nothing and
     carries no password;
   - private repository `canopy-respaldos` with the files of `ops/backup/repositorio-respaldos/`;
   - age keys; secrets `CANOPY_DB_URL` and `AGE_RECIPIENTS`; variable `SUPABASE_URL`;
   - Run workflow → green; the run summary shows `restauración verificada: … tablas`, `8 archivos verificados`,
     `listo: … restauración: passed` → download `respaldo-cifrado` and check it opens with the owner key (RESPALDOS
     3.6).
5. Save today's site: release `sitio-2026-10-09` targeting `gh-pages`. Also set environment `production`:
   required reviewer = owner, tags `v*`.
6. Separate the café devices' login from the owners' (`docs/INGRESOS.md`, E-05): **case B** (D-031), after step 4.
   Each owner confirms their own personal login in a private window (the owner's older owner login; the co-owner's
   existing login; a new `+dueno` only if one cannot sign in) and signs out of the shared login on their own
   computers and phones (top «Cerrar sesión», local); then the shared login becomes the café login in place, with
   the owner's approval. Both personal logins stay owners. No device is touched. Part 2 of `cafe-login.sql` only for
   a login nobody owns. Check: the tablet keeps its session and sells; the time clock punches; owner areas ask for a
   PIN.
7. Optional: catalog export (E-11), read-only, for the base tables' exact definitions (the two differences are
   already explained, D-031).

**B. Wave 0 (after closing, about 10 minutes)**

8. Run the backup again (green).
9. In the SQL Editor, paste each migration whole, one per query: **0000**, then **0001**, then **0002**.
   Each answers success or stops with nothing applied.
10. Snapshot → paste. I confirm 0–2 applied, the rules closed, the data fingerprints unchanged.
11. Checks: a room order from a phone; a sale on the tablet; a category color in the Menu Manager.

**C. Staging rehearsal with the real data (docs/PRUEBAS.md)**

12. Staging Supabase project; secrets `STAGING_DB_URL`, `STAGING_PIN`; "Ensayo en pruebas" → green.
13. Staging logins + `staging-logins.sql`; staging site repository → publish → the launch checklist on
    staging.

**D. The window (after closing, no pending sales on any tablet, about 30 minutes)**

14. Backup (green) + download. Snapshot and `consistency-check.sql` → save both results.
15. Paste **0003 … 0028** one by one (each under a second in the rehearsal). Stop at the first error and send it
    to me; that file applied nothing.
16. `release-check.sql` + `consistency-check.sql` → paste. The "kept" values must equal step 14's.
17. Release: tag `vAAAA.MM.DD-1` on the approved commit → Actions → Publish website → PUBLICAR → approve →
    `hanginggardencafe.com/version.json` shows the tag.
18. The 12-point check of docs/LANZAMIENTO.md. Observe 1–3 days, then activation waves. Regulated switches stay
    OFF until their confirmations.

## 9. Rollback procedure

In order of preference (docs/LANZAMIENTO.md, docs/PUBLICAR.md):

1. **Switch it off:** settings on Home (prices, cashier attribution, e-invoices, automatic books).
2. **Pages:** publish the previous tag, or `restaurar = sitio-2026-10-09` for today's site. The old pages work
   on the migrated database (tested).
3. **Database:** never by deleting. A correction migration (the next number), or the per-migration reversal
   (table in docs/LANZAMIENTO.md). Wave 0 needs none (it only adds checks).
4. **Restore a backup:** only into a NEW or staging project, never over production, and only with the owner's
   explicit authorization. The restore keeps rights identical and is checked (section 2). Sales taken after the
   backup would be lost; this is why every step starts with a fresh backup.
5. **Sign-ups:** can be switched back on instantly (not recommended).

## 10. Actions the owner must perform personally

- **Now:** steps 4–7 of section 8, one at a time (step 4 next; step 7 is optional). Never paste passwords, keys or
  connection strings in a chat: they go only into Supabase and GitHub settings.
- **Logins (D-027, D-031):** the phone code only on each owner's own personal login, from their own phone; never on
  a login a café device uses (E-06).
- **New employee from 2026-10-15 (D-032, E-21):** a manager creates the profile and PIN on today's pages
  (`docs/PERSONAL-NUEVO.md`); "who rings each sale" waits for the full window and the phone code.
- **Settings only the owner can see or change:**
  - Supabase plan and Backups page (E-10);
  - Pages source;
  - environment `production` rules (E-20);
  - the `sitio-2026-10-09` release (E-19).
- **Wave 0, staging and the window:** steps 8–18 (the owner applies migrations and publishes; I prepare and check).
- **Accountant / lawyer:** A-01 … A-09, especially A-03 (and whether today's prices become before-IVA prices),
  A-07 before automatic books, A-08 before any payroll deduction.
- **Optional:** offsite backup storage and computer sync (E-03 rest), invoice-photo S3 keys (E-17), the accountant's
  login (E-18), extensions for the exchange rate (E-16).
