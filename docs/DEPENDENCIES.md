# External dependencies: owner / accountant actions

Things the development cannot do by itself. Each item says what it blocks and what happens meanwhile.
Status: **OPEN** (waiting), **DONE**.

## Urgent (production safety)

| # | Action (who) | Why | Blocks | Status |
|---|---|---|---|---|
| E-01 | Apply migrations **0000** and **0001** in Supabase SQL Editor (owner) | Closes a verified security gap: any signed-in account could cancel or mark paid a room order. Also repairs guest room ordering. | Nothing else. Safe to do now. | OPEN |
| E-02 | Supabase → Authentication → turn off "Allow new users to sign up" (owner) | Strangers should not be able to create logins with the public key. | Nothing | OPEN |
| E-03 | Install backups: storage account, age keys, migration 0002, `canopy_backup` password, private `canopy-respaldos` repository, computer sync (owner, about 1 h, docs/RESPALDOS.md) | No backup of the business data exists today. | Any production migration after 0002 should wait for a verified backup. | OPEN |

## Information needed (no blocker for development, but needed before release)

| # | Information (who) | Used for | Status |
|---|---|---|---|
| E-10 | Supabase plan (Free/Pro) and `select version();` (owner) | Backup client version, Free-plan pausing, staging slot | OPEN |
| E-11 | Run `supabase/tools/catalog-export.sql`, save as `supabase/baseline/production-schema.sql` (owner) | Exact production structure for tests and the reconciliation migration | OPEN |
| E-12 | Owner computer: Windows or macOS? | Which backup installer to use | OPEN |
| E-13 | Create the free staging Supabase project; give its URL and **anon** key (public values, owner) | Staging environment (`website/config.js` "staging" entry) | OPEN |
| E-14 | DNS: `staging.hanginggardencafe.com` → GitHub Pages of the staging repository (owner) | Staging site on its own address | OPEN |
| E-15 | Front-register hardware (touch PC or iPad; physical keyboard?) (owner) | Default for the on-screen keyboard | OPEN (default: auto) |
| E-16 | Supabase → Database → Extensions: turn on **http** and **pg_cron**, then run `supabase/tools/fx-job.sql` (owner) | Daily exchange rate from Hacienda's free public API (no key). The answer's format could not be checked from the development environment; the first run is checked in `canopy.fx_fetch_log`. Until then a manager types the rate. | OPEN |
| E-17 | Supabase → Storage → S3 Connection → New access key; add STORAGE_S3_KEY_ID / STORAGE_S3_SECRET (secrets) and STORAGE_S3_ENDPOINT / STORAGE_S3_REGION (variables) to the private backup repository (owner) | Nightly copy of the expense invoice files (private bucket). Without it the database is backed up but the invoice files are not. | OPEN |
| E-18 | Create the accountant's login in Supabase → Authentication → Add user, then Home → Owner login → Accountant login → Give access (owner) | The accountant's own access to the books | OPEN |

## Accountant / lawyer confirmations (regulated features stay disabled until then)

| # | Question | Blocks activation of | Status |
|---|---|---|---|
| A-01 | Tax regime (traditional vs simplified), persona física/jurídica | IVA return layout, e-invoicing obligation | OPEN |
| A-02 | Does the café issue electronic tiquetes today? With which tool? | E-invoicing priority and provider | OPEN |
| A-03 | Price display: MEIC requires final IVA-inclusive prices on menus (press reports, Feb 2026). Confirm whether tax-exclusive menu display is lawful. | Activation of tax-exclusive pricing (built, OFF) | OPEN |
| A-04 | IVA rate and CABYS code for each product | Per-product tax configuration (built, defaults pending) | OPEN |
| A-05 | 10% service charge: any table service? | Service-charge setting (default OFF) | OPEN |
| A-06 | USD: which rate (BCCR buy, sell, house rate) and accounting of exchange differences | FX policy setting | OPEN |
| A-07 | Chart of accounts, inventory costing method (weighted average proposed), revenue timing for pay-later bills | Ledger activation | OPEN |
| A-08 | Payroll: pay frequency, contracts, CCSS/INS/income-tax rates and rules, who runs payroll | Payroll calculation settings (built, require confirmation) | OPEN |
| A-09 | Record retention period (plan: 10 years) | Retention policy | OPEN |
| A-10 | E-invoicing provider choice (written confirmation of offline/contingency support and the v4.4 2026-11-01 update), Hacienda credentials | E-invoicing activation (built as disabled module) | OPEN |
