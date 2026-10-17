# Canopy OS · hand-back report (Phases 0–5)

Date: 2026-10-12 · Branch `claude/hanging-garden-coffee-proposal-1m8zd4` · PR #1 (draft) · Nothing has been
published to production and the production database has not been touched.

> **For going to production, read `docs/PRODUCTION-READINESS.md`** (later the same day): verified production
> status, the backup-first order, the rehearsal results, new findings fixed in 0001–0003 and in restores, and the
> exact deployment sequence. Where the two differ, that report is current.

Status vocabulary used throughout:
- **Implemented and tested**: built, covered by automated tests, ready to apply.
- **Awaiting external verification**: built and tested, but switched OFF until an owner/accountant/official
  confirmation listed in `docs/DEPENDENCIES.md`.
- **Not implemented**: not built (reason given).
- **Ready for production**: may go into the release package (still needs your approval).
- **Blocked**: cannot proceed without you (none of the development is blocked; activation is).

## 1. Executive summary

All five phases are built on the development branch:
- 33 database migrations (`supabase/migrations/0000`–`0032`; 0000–0029 are applied in production, 0029 on 2026-10-15; 0030 (recipes stage 1A) and 0031-0032 (stage 1B) wait for the owner, E-29/E-30, `docs/ACTIVACION-RECETAS.md`);
- the existing pages, extended;
- two new pages (Accounting, Insights);
- a test suite that rebuilds a Supabase look-alike database from scratch and exercises the database and the
  pages in a real browser.

A four-part independent security review found 3 high and about 25 medium/low issues. All confirmed findings
are fixed (migration 0025, page fixes) and covered by tests; two low findings are accepted and documented (D-022).

**The system is not "complete" in the regulated sense**, and several items are built but OFF on purpose:
- tax-exclusive prices;
- automatic ledger posting;
- payroll deductions and charges;
- e-invoicing;
- the automatic exchange rate.

These are waiting on your accountant, your provider choice or official confirmation. Electronic invoicing *sending*
(provider connection, XML, signature) is **not implemented**: only the document register is.

Production readiness depends on three things you have to do first:
- backups installed (E-03);
- the owner's dress rehearsal on the real anonymized copy in a temporary database (`Ensayo en pruebas`, destino `desechable`, reinicio `si`; no staging project: E-13/E-14 withdrawn, D-039): run once on 2026-10-14, when the reset and the migrations passed on the real copy and the comparison's fixture-only check was fixed (D-039 addendum); to repeat on the fixed version (E-23);
- the two urgent security items E-01/E-02 (they apply to the live system today).

## 2. Completed checklist

Full table with tests and commits: `docs/CHECKLIST.md`.

| Phase | Implemented and tested | Awaiting external verification (built, OFF) | Not implemented |
|---|---|---|---|
| 0 Safety foundation | Manual-only publishing; migration ledger; legacy guards; security fix 0001; backups (scripts, encrypted, restore test, Home card); CI; config per environment; device version check; PIN hygiene; atomic idempotent sales; protected stock history | Staging values (E-13/E-14); exact production base schema (E-11) | — |
| 1 POS and operations | PIN/amount keypad, text keyboard; who rings each sale (off/record/enforce); per-product IVA with CABYS fields; CRC+USD with cash window, change, denominations, mixed currency; register counted in ₡ and $; manual exchange rate; receipt numbers, history search, reprint COPIA, refunds of closed days; purchase orders with numbers, PDF/print, WhatsApp/email, partial deliveries with supplier invoice; Spanish everywhere; who took the money on a bill paid later, "End my turn" clocks out, sales by cashier (0027) | Tax-exclusive pricing (A-03/A-04); automatic exchange rate (E-16, A-06) | — |
| 2 Accounting | Double-entry ledger (balanced, immutable, reversals); periods open/closed/locked; expenses with creditable IVA and invoice photo; accountant login; trial balance, income statement, balance sheet, cash flow; CSV and monthly ZIP package | Chart of accounts and automatic daily posting (A-07) | — |
| 3 CR tax and suppliers | Supplier invoices linked to deliveries, AP, payments, aging; the period's IVA draft with every document and tie-out; inventory valuation; weighted-average COGS; profit by product | CABYS per product (A-04); e-invoice document register in record-only mode (A-02/A-10); costing method (A-07) | E-invoice provider connection, XML, signing, sending, contingency; POS "invoice with ID" button; filing the IVA return |
| 4 Cash, bank, payroll | Register cash in/out with manager PIN; payouts documented later; ₡/$ cash reconciliation; bank accounts, CSV statement import, matching, posting, undo; pay periods, timesheet approval and lock; pay rates; payroll prepare → accountant review → post → pay; labor cost | Payroll deductions/charges (A-08: none built in, gross only until confirmed); Costa Rican payroll: CCSS/INS categories, income-tax table and withholding, aguinaldo provision and run, vacations, settlement estimate, the month for the CCSS and the INS (A-08, 0026) | Dollar bank accounts (A-06); CCSS/INS/Hacienda filing files (the month's report and CSV are the input) |
| 5 Insights | Today estimate vs final on Home and Insights; months (sales, food cost %, labor %, prime cost %); weekday × hour heatmap; products; categories; suppliers (delivery days, price changes); stock forecast; leaks; multi-location-ready columns | — | Operating a second location (registers and stock per location) |
| Release | Security review and hardening (0025); wave plan; read-only release check; rollback per migration; training plan | The repeat of the owner's real-data rehearsal in the temporary database (E-23; run #2 of 2026-10-14 passed the reset and 0000–0028, red only in the since-fixed comparison check); E-13/E-14 withdrawn | — |

## 3. Remaining external dependencies

From `docs/DEPENDENCIES.md`.

**Urgent (today's live system):**
- **E-01:** apply 0000 and 0001; this closes a verified room-order security gap.
- **E-02:** turn off public sign-ups.
- **E-03:** install backups.

**Before release:**
- **E-10:** Supabase plan and version.
- **E-11 (optional):** export the production schema (the two differences are explained, D-031).
- **E-12:** owner computer OS for the backup installer.
- **E-13, E-14:** withdrawn (D-039): no second Supabase project; the real-data rehearsal runs in a temporary database inside the private repository's job.
- **E-15:** front-register hardware.
- **E-16:** http and pg_cron extensions for the automatic exchange rate.
- **E-17:** Storage S3 keys for backing up invoice photos.
- **E-18:** the accountant's login. The accountant turns on the phone code at first sign-in.

**Accountant / lawyer confirmations** (features stay OFF until then):
- **A-01:** regime and proportional credit.
- **A-02, A-10:** e-invoicing tool and provider.
- **A-03:** tax-exclusive display.
- **A-04:** IVA and CABYS per product.
- **A-05:** service charge.
- **A-06:** USD rate and exchange differences.
- **A-07:** chart of accounts, costing and revenue timing.
- **A-08:** payroll rules.
- **A-09:** retention.

## 4. Test results

Everything is rebuilt from scratch on every run (`tests/run.sh`).
- **Last full run (local, 2026-10-16, before the stage 1A commit):** ALL TESTS PASSED.
  - **SQL:** 34 files, 1 177 assertions, one transaction each. Every migration is tested, plus the security attack
    suite (`250_security_hardening`), the release check (`240`), which pins down anonymous access, row
    security and fixed search paths, the Costa Rican payroll (`290`, 143), who took the money (`300`), the
    review fixes (`310`), receiving with the invoice (`320`, 127), the recipes of stage 1A (`330`, 105) and the
    rollback of 0030 (`340`, 13).
  - **Browser:** 113 tests passed (31 spec files, one of them on a 390 px phone), plus the 6 live-page checks of the
    rehearsal on the migrated copy (the pages published today, v2026.10.15-1, including their recipe editor on 0030),
    the same 6 on the copy that went through the one-time reset, and the 2 checks of the new pages on the empty café
    and its first day.
  - **Backup pipeline:** passed. **Migration rehearsal** 0000 → 0030 on the production-shaped copy: passed, including the
    one-time reset pass (six refusals, the reset, the migrations after it) and the owner's staging rehearsal with `reinicio = si`.
- **What the browser tests cover:** Playwright with real supabase-js against PostgREST; staff screens in English
  and Spanish; phone, tablet and desktop sizes; offline and two-device cases.
- **What the backup pipeline test covers:** backup, restore test, encryption, offline-key restore, computer sync.
- **CI:** the same suite on every push (GitHub Actions "tests"). One intermittent browser failure (070 Q-f, a
  page navigation) was seen once on 9ecc79a. It did not reproduce locally in 3 runs or on other commits. A
  navigation logger was added so a recurrence names its cause.
- **Visual checks:** phone (390 px) and desktop screenshots of the new screens. No page scrolls sideways; chart
  colors are checked for color-blind separation and contrast (D-020).

## 5. Migration inventory

| # | What | Staff impact | Reversal |
|---|---|---|---|
| 0000 | Migration ledger; legacy scripts refuse to run | none | not needed |
| 0001 | Security fix: room orders, room codes, quick items | none | not needed |
| 0002 | Backup role (reads the café's tables, never the logins) and backup log | none | `supabase/tools/backup-account-rollback.sql` (keep `canopy.backup_runs`) |
| 0003 | Sale times: rung, paid, business day | none | drop triggers |
| 0004 | Save a whole sale at once; lines linked to products | none | drop function (POS falls back) |
| 0005 | Inventory history protected; cost on every move | "delete" an item with history → deactivate | drop triggers |
| 0006 | Voids only while the day is open; refunds dated today | "Refund" instead of "Void" on closed days | previous function |
| 0007 | Retire hours_report (unlimited PIN guessing) | none | regrant (not advised) |
| 0008 | Settings with legal locks; who rings each sale | none until switched on | setting off |
| 0009 | IVA per product, CABYS, tax stored per line | receipt shows IVA by rate | drop triggers |
| 0010 | Exchange rate, cash window, register in ₡ and $ | cash window when paying cash | optional params |
| 0011 | Receipt numbers, search, reprint COPIA | "Search earlier sales" | drop functions |
| 0012 | Purchasing: PO numbers, partial deliveries | "Receive" asks invoice Nº | drop function |
| 0013 | Ledger, chart, periods, daily posting (OFF), accountant role | none | auto-post off |
| 0014 | Expenses with IVA credit | none | drop functions |
| 0015 | Invoice photos (private bucket), IVA summary for the accountant | none | drop policies |
| 0016 | Supplier invoices, AP, payments | none | drop functions |
| 0017 | IVA of the period, inventory valuation, profit by product | none | drop functions |
| 0018 | E-invoice document register (OFF) | none | mode off, drop trigger |
| 0019 | Register cash in/out; payouts; cash reconciliation | new POS button | drop functions |
| 0020 | Bank accounts, statement import, reconciliation | none | drop functions |
| 0021 | Pay periods, timesheet approval, approved hours locked | approved shifts can't be edited | drop trigger |
| 0022 | Payroll preparation, labor cost | none | drop functions |
| 0023 | Insights (read-only) | none | drop functions |
| 0024 | Locations (one today) | none | not needed |
| 0025 | Security hardening (D-022) | owner uses own login with phone code for the books | previous functions |
| 0026 | Costa Rican payroll: CCSS/INS categories, employee profile, income-tax table, extra pay, payslip, aguinaldo, vacations, settlement estimate, the month for the CCSS and the INS (all OFF behind `payroll_cr_rules`) | none | drop the new functions; previous payroll functions |
| 0027 | Who took the money on a bill paid later; the till cannot rewrite who rang or who took the money; "End my turn" can clock out | the POS asks about the clock when a turn ends | drop trigger; previous `tab_pay` and `pos_operator_end` |
| 0028 | Review fixes (D-037): the till never records a negative total; a room order paid later counts on the day the money came in; days with sales and no register are listed and posted; the journal reverses only its own entries; a PIN in use is refused and the owner role needs the phone code; visitors' questions capped | a repeated PIN is refused when adding someone; the owner role needs the phone code | drop the two triggers; previous functions |
| 0029 | Receive a delivery with the supplier invoice and the payment (D-041, D-042): invoice pending / review / confirmed, draft kept as data, dollars with the rate, debit and credit card methods (account 2160), payouts from the register documented at confirmation, `po_receive_and_settle`, `po_receipt_settle`, `po_receipt_pay`, `po_history`, `po_pending` | the receive window gains the invoice and payment section | drop the five functions and the trigger; previous `supplier_payment_save`; the new columns stay |
| 0030 | Recipes stage 1A (D-043): `recipe_versions` (unchangeable history, today's recipes as the starting version), `recipe_save` and `recipes_autolink_pin` with a manager or owner PIN, history triggers for direct writes, unit and delete guards on stock items in use, one cost rule (`_stock_unit_cost`), food cost at the stamped cost against sales without IVA | Recipes asks for a PIN to save and shows the history; quantities in g/ml; counting and receiving in bags | `supabase/tools/reversion-0030.sql`: drops the functions and triggers, restores the three changed functions exactly, keeps the history |
| 0031 | Recipes stage 1B (D-044): each sale line takes the recipe and the cost of its moment (offline sales included) and records its version and time; each movement names its line; an item taken off a bill gives back exactly what it took; a bill paid in part and voided leaves out exactly what was eaten; items added offline keep the recipe of when they were added; cost history; a missing ingredient never refuses a sale | none (the new POS also sends the time of an item added offline, optional) | `supabase/tools/reversion-0031.sql`: restores the eight changed functions exactly; columns and cost history stay |
| 0032 | Recipes only with the PIN (D-044): no page writes recipes directly; the PIN-less autolink is closed | an older Inventory page cannot save recipes (the till is not affected) | `supabase/tools/reversion-0032.sql`: the rights of before |

Each file states its purpose, staff impact and reversal in Spanish at the top. Every migration is one
transaction and only adds; nothing deletes business records.

## 6. Security review

Four independent reviews (Phase-1 migrations; books/IVA; cash/bank/payroll/insights; pages and workflows).

**High findings, all fixed:**
1. "NaN" amounts accepted, permanently corrupting the books.
2. The owner's PIN typed on the café tablet counted as the owner's phone-code login for the books, payroll,
   bank, legal switches and accountant access.
3. Re-posting a bank movement after undoing it silently did nothing.

**Medium findings, all fixed:**
- managers without sales permission could read sales numbers (history, insights, IVA, cash by day);
- the accountant needed no phone code;
- backdating into a month before a closed or locked one;
- payables races (overpaying, double-linking deliveries);
- payroll reviewed or posted from stale hours;
- dollar bank accounts mixed into colones;
- an unbounded manual exchange rate (change-theft path);
- stored XSS via an inventory unit;
- spreadsheet formula injection in every CSV export.

**Low findings, fixed:**
- opening stock rewriting costs;
- received purchase lines editable;
- the tablet seeing past cash tenders;
- the PIN lockout bypassable with parallel requests;
- receipt files attachable to others' expenses;
- the invoice-request overwrite;
- the PIN left in the cash form;
- shell input in the publish workflow;
- the timesheet approval race;
- a NULL accountant check.

**Accepted (low, documented in D-022):**
- the till's internal tender function stays callable by the café login (a wrong tender is flagged);
- unlocked managers can write cost-edit log rows attributed to themselves.

**Permanent checks:**
- `tests/sql/250_security_hardening` runs each attack.
- `tests/sql/240_release_check` and `supabase/tools/release-check.sql` verify, on the test DB and in production:
  - only the menu and room-order functions run without sign-in;
  - every table has row security;
  - every owner-rights function fixes its search path;
  - the expense-receipt bucket and its rules exist, and the upload rule is 0025's (D-027).

**Secrets:** none in the repository or its history. The two anon keys are public by design; the test passwords
are for the local test database only.

## 7. Backup / recovery verification

- **Built and tested:** nightly encrypted backup to external storage with deletion lock, an automatic restore
  test, offline-key restore, computer sync, and the green/amber/red Home card. All of it is exercised in CI by
  the backup pipeline test.
- **Not verified in production:** backups are not installed yet (E-03). No production backup exists today.
  - This is the first thing to do.
  - No migration after 0002 should be applied before a verified backup.
  - The quarterly restore drill and the disaster runbook are in `docs/RESPALDOS.md`.
- **Gap:** invoice photo files are backed up only once the S3 keys exist (E-17).

## 8. Accounting validation

**Tested invariants:**
- every entry balances at commit, and the trial balance always nets to zero;
- the balance sheet balances;
- the cash-flow closing equals cash and bank;
- entries are never edited or deleted, only reversed, and a reversal happens once;
- automatic entries are keyed so they never repeat;
- late sales post only the difference;
- a closed month is never touched;
- NaN/infinity are refused.

**Tie-outs shown on screen:**
- AP (books = open invoices + received not invoiced + expenses on credit);
- IVA of the period against 2110/1140;
- inventory valuation against 1150;
- bank statement against the books;
- cash by day.

**Not yet validated by a professional:**
- the chart of accounts, mappings, costing method and revenue timing (A-07);
- automatic posting stays OFF until your accountant approves the chart in the Accounting page.

## 9. Costa Rica compliance readiness

| Area | Ready | Waiting on |
|---|---|---|
| IVA per product, stored per sale line (13 % built in, other rates only with a confirmation) | yes | A-04: rate and CABYS per product |
| Prices on menus | final prices as today | A-03: whether tax-exclusive display is lawful (built, OFF) |
| Period IVA | draft with every document | A-01: regime and proportionality; the accountant files |
| Electronic invoicing | document register only (OFF / record-only) | A-02, A-10: provider, credentials, format version. Sending is **not implemented** |
| Payroll | gross from approved hours; review and posting flow; CCSS and INS by category, income-tax table, extra pay, payslip, aguinaldo, vacations, settlement estimate, the month for the CCSS and the INS (0026) | A-08: the percentages, the year's tax table and the vacation/severance rules confirmed by the accountant; the owner records `payroll_cr_rules`. Nothing is withheld, provisioned or posted before that; no filing files are produced |
| Record retention | backups keep yearly copies indefinitely | A-09: confirm 10 years |

No Costa Rican tax or payroll rule was invented. Anything regulated is either a confirmed rate entered with
who confirmed it and the document, or OFF.

## 10. Operating costs

| Item | Cost |
|---|---|
| GitHub Pages, GitHub Actions (tests, backups) | US$0 |
| Supabase Free plan | US$0. Pro (US$25/month) is optional: more space, Supabase's own daily backups, no pausing |
| Backup storage (Cloudflare R2, within the free 10 GB) | US$0 |
| Exchange rate (Hacienda public API) | US$0 |
| E-invoicing provider | **unknown until chosen (A-10)**. A paid service is needed; it will be presented with its cost before anything is activated |

Nothing paid was activated.

## 11. Production deployment plan

See `docs/LANZAMIENTO.md` (Spanish).

**Update 2026-10-14 (D-038):** the owner chose a single coordinated release with a one-time operational reset of the
test period before migration 0000 (`supabase/tools/reinicio-operativo.sql`, after a verified backup and the
accountant's summary; inventory restarts at zero after a physical count; regulated features stay OFF). The operative
runbook is `docs/LANZAMIENTO-UNICO.md` (Spanish): preparation, the 45-minute window, the first day, the way back and
the owner's approvals. The order below remains the activation and training plan.

**Update 2026-10-14, evening (D-039):** no second Supabase project and no staging site: the production project (URL,
project ref, `anon` key) and the GitHub Pages site stay; the real-data rehearsal runs in a temporary database inside
the private repository's job («Ensayo en pruebas» → destino = `desechable`, reinicio = `si`). E-13 and E-14 are
withdrawn; the first verified backup is done (E-03). `docs/LANZAMIENTO-UNICO.md` §3 says what local PostgreSQL
verifies and what only Supabase can, with the mitigation for each; §4 has the preflight and §6 the post-release checks.

**Recommended order:**
1. **Wave 0 now:** E-01, E-02, E-03.
2. **Dress rehearsal** of the whole set on the real anonymized data, in the temporary database (D-039).
3. **One evening maintenance window:**
   - verified backup;
   - migrations 0003–0028;
   - publish the release tag (you run the workflow);
   - `release-check.sql`.
4. **Switch-on waves:** one area per week, with training and checks:
   - sales integrity;
   - accounting;
   - IVA and suppliers;
   - cash, bank and payroll;
   - insights.

## 12. Rollback procedure

In order of preference:
1. Turn the feature's switch off.
2. Publish the previous tag (pages).
3. A corrective migration (the next number; nothing is deleted).
4. Restore a backup (only with your explicit approval; loses changes after the backup).

Each migration's reversal is listed in `docs/LANZAMIENTO.md`.

## 13. Training recommendations

| Who | Time | What |
|---|---|---|
| Cashiers | 20 min | Cash window, receipts, reprint, offline |
| Managers | 45 min | Voids/refunds, money in or out of the drawer, opening/closing in ₡ and $, partial deliveries |
| Owner | 90 min | Settings and confirmations, exchange rate, Insights, approving hours, pay rates, publishing and rollback, backups |
| Accountant | 2 h | Chart approval, expenses, suppliers, IVA, bank, payroll review, monthly package |

Details: `docs/LANZAMIENTO.md`.

## 14. Final production approval request

**Launched 2026-10-15** (UTC early hours; the night of 2026-10-14 in Monteverde; D-040): backup #4, the one-time reset
(`reinicio hecho`), migrations 0000–0028, release check clean, `v2026.10.14-1` published at 04:33 UTC from commit
3c7e020, regulated features OFF. Still owed: the physical count before opening, the age private keys (E-24, done 2026-10-17), the
accountant's answer (A-11), the café login conversion and the phone codes (deferred by the owner).

**Not ready / not requested:**
- activation of tax-exclusive pricing, automatic ledger posting, payroll deductions and e-invoicing;
- the automatic exchange rate before E-16;
- dollar bank accounts.

**Done on launch night (2026-10-15 UTC):** Wave 0, the rehearsal with the real data (run #3, green), the window
(backup #4, reset, 0000–0028, release check) and the publish of `v2026.10.14-1`. **First day:** the nightly backup ran
by itself (run #5, 2026-10-15 13:24 UTC, green: 62 tables, restore test passed, result in `canopy.backup_runs`, so the
Home card has its first row); on 2026-10-17 the owner decrypted backup #9 with both private keys and restored it in full on a throw-away PostgreSQL (E-24 DONE, D-046). **Still asked of you:**
1. E-24: done on 2026-10-17 (both keys decrypt; full restore verified, D-046). Repeat the drill every three months,
   once a year with the printed key (docs/RESPALDOS.md → Prueba de restauración).
2. The morning of 2026-10-15 before opening: `release-check.sql`, `consistency-check.sql` (`orders_before_reset` = 0),
   the physical count in Inventario → Existencias → Contar, the register opened with the counted float, the exchange rate.
3. A-11 (the accountant's retention answer) and, another night, approvals 5 and 6 (`cafe-login.sql`, phone codes).
