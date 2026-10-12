# Canopy OS · Production Readiness Report

Date: 2026-10-12 · Branch `claude/hanging-garden-coffee-proposal-1m8zd4` · PR #1 (draft)

Nothing was published, no production setting was changed, and the production database was not connected to,
queried or changed. Every "production" fact below is either read from GitHub (read-only) or marked
**not verified** with the read-only step that verifies it.

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
| Migrations installed | **Not verified.** Expected: none (the repository's history and the live pages pre-date migration 0000) | `supabase/tools/production-snapshot.sql` reports it (read-only) |
| Security configuration (sign-ups, anonymous sign-ins, rules, grants, logins) | **Not verified.** Sign-ups are on by default on Supabase | Snapshot reports rules, grants, functions callable without an account check, and the logins (emails masked); sign-ups are a dashboard setting |
| Supabase backups / PITR | **Not verified.** Depends on the plan (Free: no downloadable backups; Pro: 7 daily; PITR is a paid add-on). Our own backup does not depend on it | Owner: Database → Backups page; the snapshot shows WAL archiving hints |
| Schema matches what the repository expects | **Not verified.** Four base tables were reconstructed from the code | The snapshot compares every function body (md5, by version), every original table's columns and indexes with the repository |

## 2. Backup and restore evidence

No production backup exists yet (E-03). What is ready and proven on test copies:

- **Works before any migration:** `supabase/tools/backup-account.sql` creates the read-only `canopy_backup`
  account on today's schema (no migration needed). It is what migration 0002 does, so 0002 changes nothing later.
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
| S-1 | Anyone can create a login with the public key (Supabase default) | High (entry point for S-2…S-4) | Turn off "Allow new users to sign up". No page uses sign-up. Existing logins, sessions, password reset, phone code and "Add user" keep working. First review the snapshot's login list | Ready (owner) |
| S-2 | A self-made login can cancel or mark paid any unpaid room order, change a room's QR code, read sales by product | High | Migration 0001 | Ready, rehearsed |
| S-3 | **New:** a self-made login can rename, reorder or recolor menu categories and change which go to the kitchen. These show on the QR menu and the TV. Cause: the legacy rule meant for "color" covered every column | Medium | 0001 drops that rule; the owner rule still covers the Menu Manager (live page tested) | Ready, rehearsed |
| S-4 | **New:** the time clock and void functions accept PIN tries from any login (5 tries per 10 min lockout); a stranger could guess PINs or lock staff out | Medium | 0001: café or owner login only | Ready, rehearsed |
| S-5 | Guest room ordering likely fails today (`gen_random_bytes` not on the search path) | Functional | 0001 | Ready, rehearsed |
| S-6 | **New:** a restore from backup opened owner functions to visitors | High (only after a restore) | Section 2 | Fixed, tested |
| S-7 | **New:** migration 0002 failed on PostgreSQL 16+ when the backup account already existed | Blocks backup reporting | Fixed in 0002 | Rehearsed |
| S-8 | **New:** 0003's backfill scanned all lines for each order: 42 s at 14 500 orders, could exceed its 300 s limit on a larger history | Release risk | Same result in one pass + index (0.3 s) | Rehearsed, equality checked |
| S-9 | Findings of the earlier review (D-022) | – | 0025 | Rehearsed |
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
- **Staging copy flow:** read-only copy → anonymized (names, guests, suppliers, PINs, logins) → empty
  Supabase-like project → migrations. Rights identical to the source, data checks identical.
- **The owner's real-data staging rehearsal is not done:** it needs the staging project (E-13).
  It is one button in the private repository ("Ensayo en pruebas").

**Full automated run after the rehearsal** (`tests/run.sh`, also in CI on every push), all passed:

| Stage | Result |
|---|---|
| Lint (no secrets, release rules, plain-SQL migrations, environments incl. "staging never on production") | ok |
| SQL tests | 25 files, 604 assertions (incl. the 0001 additions: stranger cannot edit categories, punch, guess or void) |
| Backup pipeline (before 0000 and after; content, rights, photos, encryption, offline-key restore, computer sync) | ok |
| Migration rehearsal (sections 4 and 5, with the staging-copy flow) | ok |
| Live pages on the migrated copy | 5/5 |
| Browser tests of the new pages | 90/90 (incl. the supplier XML import in English and Spanish) |
| Database consistency and security checks | inside the rehearsal: identical "kept" values, no new problems, reviewed rules only, ledger balanced |
| Backup restoration | before and after the migrations: rows, content and rights identical |

## 5. Migration results (rehearsal)

- **0000 → 0025**, each file as one transaction, applied as a non-superuser account like Supabase's SQL Editor:
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

**A. Verify and protect (any time, nothing changes in the data)**

1. Snapshot → paste the result to me. I compare it with the rehearsal: migrations, drift, rules, logins.
2. Review the logins in the snapshot. Then Authentication → turn off "Allow new users to sign up" and check
   anonymous sign-ins are off. Check: the tablet is still signed in; the owner can sign in; "forgot password"
   still sends the email.
3. Verified backup (docs/RESPALDOS.md):
   - `backup-account.sql`, then its password (delete the saved query afterwards);
   - private repository `canopy-respaldos` with the files of `ops/backup/repositorio-respaldos/`;
   - age keys; secrets `CANOPY_DB_URL` and `AGE_RECIPIENTS`; variable `SUPABASE_URL`;
   - Run workflow → green → download `respaldo-cifrado`.
4. Save today's site: release `sitio-2026-10-09` targeting `gh-pages`. Also set environment `production`:
   required reviewer = owner, tags `v*`.

**B. Wave 0 (after closing, about 10 minutes)**

5. Run the backup again (green).
6. In the SQL Editor, paste each migration whole, one per query: **0000**, then **0001**, then **0002**.
   Each answers success or stops with nothing applied.
7. Snapshot → paste. I confirm 0–2 applied, the rules closed, the data fingerprints unchanged.
8. Checks: a room order from a phone; a sale on the tablet; a category color in the Menu Manager.

**C. Staging rehearsal with the real data (docs/PRUEBAS.md)**

9. Staging Supabase project; secrets `STAGING_DB_URL`, `STAGING_PIN`; "Ensayo en pruebas" → green.
10. Staging logins + `staging-logins.sql`; staging site repository → publish → the launch checklist on
    staging.

**D. The window (after closing, no pending sales on any tablet, about 30 minutes)**

11. Backup (green) + download. Snapshot and `consistency-check.sql` → save both results.
12. Paste **0003 … 0025** one by one (each under a second in the rehearsal). Stop at the first error and send it
    to me; that file applied nothing.
13. `release-check.sql` + `consistency-check.sql` → paste. The "kept" values must equal step 11's.
14. Release: tag `vAAAA.MM.DD-1` on the approved commit → Actions → Publish website → PUBLICAR → approve →
    `hanginggardencafe.com/version.json` shows the tag.
15. The 12-point check of docs/LANZAMIENTO.md. Observe 1–3 days, then activation waves. Regulated switches stay
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

- **Now:** steps 1–4 of section 8. Never paste passwords, keys or connection strings in a chat: they go only into
  Supabase and GitHub settings.
- **Settings only the owner can see or change:**
  - Supabase plan and Backups page (E-10);
  - Pages source;
  - environment `production` rules (E-20);
  - the `sitio-2026-10-09` release (E-19).
- **Wave 0 and the window:** steps 5–15 (the owner applies migrations and publishes; I prepare and check).
- **Accountant / lawyer:** A-01 … A-09, especially A-03 (and whether today's prices become before-IVA prices),
  A-07 before automatic books, A-08 before any payroll deduction.
- **Optional:** offsite backup storage and computer sync (E-03 rest), invoice-photo S3 keys (E-17), the accountant's
  login (E-18), extensions for the exchange rate (E-16).
