# External dependencies: owner / accountant actions

Things the development cannot do by itself. Each item says what it blocks and what happens meanwhile.
Status: **OPEN** (waiting), **DONE**.

## Urgent (production safety)

| # | Action (who) | Why | Blocks | Status |
|---|---|---|---|---|
| E-00 | Run the read-only `supabase/tools/production-snapshot.sql` and paste the result (owner) | Confirms which migrations, functions, rules, logins and data production really has before anything is applied (2026-10-12 directive) | Everything below waits for it | OPEN |
| E-02 | Supabase → Authentication → turn off "Allow new users to sign up"; check anonymous sign-ins are off (owner). Before: review the logins listed by the snapshot; unknown ones are reported, not deleted, until checked | If it is on (Supabase's default; not verifiable from here), anyone can create a login with the public key. Disabling does not affect existing logins, password reset, the phone code, or "Add user" (checked against every page) | Nothing | OPEN |
| E-03 | First verified backup BEFORE any migration: `supabase/tools/backup-account.sql`, the account's password, the private `canopy-respaldos` repository, age keys, Run workflow, download the encrypted file (owner, ~45 min, docs/RESPALDOS.md). Offsite storage and computer sync can follow. | No backup of the business data exists today | 0000/0001 wait for it | OPEN |
| E-01 | Apply migrations **0000**, **0001** and **0002**, one at a time, snapshot before and after (owner) | 0001 closes: room orders cancelled/marked paid by any login; room QR codes changed; sales by product read; **menu categories renamed or recolored by any login** (seen on the QR menu and TV); **PINs guessed** on the time clock and voids from any login. Repairs guest room ordering. Rehearsed (D-023) | Nothing else | OPEN |

## Information needed (no blocker for development, but needed before release)

| # | Information (who) | Used for | Status |
|---|---|---|---|
| E-10 | Supabase plan (Free/Pro) and `select version();` (owner) | Backup client version, Free-plan pausing, staging slot | OPEN |
| E-11 | Run `supabase/tools/catalog-export.sql`, save as `supabase/baseline/production-schema.sql` (owner). Only if the snapshot (E-00) shows `functions_changed`, `functions_unknown` or `tables_columns_differ` | Exact production structure where it differs from the repository's reconstruction | OPEN |
| E-12 | Owner computer: Windows or macOS? | Which backup installer to use | OPEN |
| E-13 | Staging (docs/PRUEBAS.md): free Supabase project `canopy-pruebas`; secrets `STAGING_DB_URL`, `STAGING_PIN` in the private repository; "Ensayo en pruebas"; staging logins (owner). Values go into GitHub settings, never into chat | Rehearsal on an anonymized copy of the real data | OPEN |
| E-14 | Staging site: public repository `canopy-pruebas` with `ops/staging/repositorio-pruebas/`, variables `STAGING_SUPABASE_URL` / `STAGING_SUPABASE_ANON_KEY`, Pages from `gh-pages` (owner). No DNS needed | Click-through test of a version before it reaches the café | OPEN |
| E-19 | Save today's live site as release `sitio-2026-10-09` targeting the `gh-pages` branch (owner, docs/PUBLICAR.md) | The only way back to today's pages after the first release | OPEN |
| E-20 | Settings → Environments → production: Required reviewers = owner; deployment tags `v*` (owner) | Every publication waits for the owner's click, whoever starts it | OPEN (recommended) |
| E-15 | Front-register hardware (touch PC or iPad; physical keyboard?) (owner) | Default for the on-screen keyboard | OPEN (default: auto) |
| E-16 | Supabase → Database → Extensions: turn on **http** and **pg_cron**, then run `supabase/tools/fx-job.sql` (owner) | Daily exchange rate from Hacienda's free public API (no key). The answer's format could not be checked from the development environment; the first run is checked in `canopy.fx_fetch_log`. Until then a manager types the rate. | OPEN |
| E-17 | Supabase → Storage → S3 Connection → New access key; add STORAGE_S3_KEY_ID / STORAGE_S3_SECRET (secrets) and STORAGE_S3_ENDPOINT / STORAGE_S3_REGION (variables) to the private backup repository (owner) | Nightly copy of the expense invoice files (private bucket). Without it the database is backed up but the invoice files are not. | OPEN |
| E-18 | Create the accountant's login in Supabase → Authentication → Add user, then Home → Owner login → Accountant login → Give access (owner) | The accountant's own access to the books | OPEN |

## Accountant / lawyer confirmations (regulated features stay disabled until then)

| # | Question | Blocks activation of | Status |
|---|---|---|---|
| A-01 | Tax regime (traditional vs simplified), persona física/jurídica; whether proportional IVA credit applies | IVA return layout (the period's IVA draft is built, 0017), e-invoicing obligation | OPEN |
| A-02 | Does the café issue electronic tiquetes today? With which tool? | E-invoicing priority and provider | OPEN |
| A-03 | The owner's confirmed policy (2026-10-12): menu prices exclude IVA and the tax is added at checkout. To verify before activation: whether showing prices before IVA is lawful (MEIC requires final IVA-inclusive prices on menus, press reports Feb 2026), what the website, TV and QR menu show, and whether today's prices become the before-IVA prices (customers would pay 13 % more) or stay the final prices (D-026) | Activation of tax-exclusive pricing (built, OFF, rehearsal checks it stays off) | OPEN |
| A-04 | IVA rate and CABYS code for each product | Per-product tax configuration (built, defaults pending) | OPEN |
| A-05 | 10% service charge: any table service? | A service charge is **not built** (not in the approved scope); built only if table service is confirmed | OPEN |
| A-06 | USD: which rate (BCCR buy, sell, house rate) and accounting of exchange differences | FX policy setting | OPEN |
| A-07 | Chart of accounts, inventory costing method (weighted average proposed), revenue timing for pay-later bills | Ledger activation | OPEN |
| A-08 | Payroll: pay frequency, contracts, CCSS/INS/income-tax rates and rules, who runs payroll | Payroll: periods, approval, rates and the review/post flow are built (0021, 0022); each deduction/charge is entered with who confirmed it; until then the payroll computes gross pay only | OPEN |
| A-09 | Record retention period (plan: 10 years) | Retention policy | OPEN |
| A-10 | E-invoicing provider choice (written confirmation of offline/contingency support and the v4.4 2026-11-01 update), Hacienda credentials | E-invoicing: the document register is built (0018, record-only mode); the connector, sending, and the POS "invoice with ID" button are built after this choice. Provider cost to be presented before activation. | OPEN |
