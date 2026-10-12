# Canopy OS · master development checklist

Legend:
- **Status:** ✅ implemented and tested · 🟡 in progress · ⏳ pending · 🔒 implemented, waiting on an external
  confirmation (feature OFF) · ⛔ blocked.
- **Prod:** production readiness. **R** = ready for the release package · **–** = not yet.

Last updated: 2026-10-12.

## Phase 0 · Safety and foundations

| Feature | Status | Depends on | Tests | Known issues | Commit | Prod |
|---|---|---|---|---|---|---|
| Stop automatic publishing; manual tag-only release with PUBLICAR | ✅ | – | lint (no push trigger) | Owner should also adopt the owner-only production repo (D-001) | c754fc4 | R |
| Test database (Supabase look-alike + 18 legacy scripts + migrations) | ✅ | E-11 for exact base tables | 010_legacy_baseline (27) | Base tables reconstructed until E-11 | 8c6ef4d | – |
| Migration ledger 0000 + legacy script guards | ✅ | – | 020 (ledger part) | – | 8c6ef4d | R |
| Security fix 0001 (room orders, room codes, quick items, room ordering search path) | ✅ | – | 020 (16) | Urgent: E-01 | 8c6ef4d | R |
| Production schema export tool | ✅ | – | manual run on test DB | – | 8c6ef4d | R |
| Backups: 0002 account/log/status, backup.sh, restore.sh, private-repo workflow, computer sync (Win/Mac), runbook | ✅ | E-03, E-12 | 030 (11), backup pipeline e2e | PowerShell scripts not executable in this environment; verify on the owner PC at install | 4767760 | R |
| Backup health card on owner Home (green/amber/red, Spanish) | ✅ | 0002 | e2e 060 (2) | – | 4538178 | R |
| CI workflow (lint, SQL, backup pipeline, browser tests) | ✅ | – | runs on push | – | 4767760 | – |
| Central config.js (production/staging/local) | ✅ | E-13/E-14 for staging values | e2e smoke (3) | Staging entry empty until E-13 | 5e9ca83 | R |
| Browser test harness (gateway, PostgREST, Playwright) | ✅ | – | e2e smoke | – | 5e9ca83 | – |
| Earlier browser suites ported (bills/tabs, open orders on the device, QR menu, kitchen) | ✅ | – | e2e 070–100 (34) | – | 2d457e9 | – |
| Device version check + safe reload (version.js, build stamp in pages.yml) | ✅ | – | e2e 050 (2) | Verify on the first real release (staging) | 4538178 | R |
| PIN hygiene: register PINs trimmed and cleared, void PIN cleared, hours PIN never kept; hours_report retired (0007) | ✅ | – | 080_pin_hygiene (4), e2e 050 (1) | – | 4538178 | R |
| Integrity: rung_at/paid_at/business_date (0003) | ✅ | – | 040_order_times (18) | Reports still read created_at until Phase 2 switches them | 165a027 | R |
| Integrity: atomic idempotent pos_record_sale (0004) | ✅ | – | 050_sales_save (19), e2e 020 (3) | – | 165a027 | R |
| Integrity: menu_item_id on sale lines (0004) | ✅ | – | 050_sales_save | Older lines matched by name (best effort) | 165a027 | R |
| Integrity: stock history protected; items/vendors with history are deactivated, not deleted (0005) | ✅ | – | 060_inventory_integrity (40), e2e 030 (3) | – | bd7126e | R |
| Integrity: cost stamped on every stock move; weighted-average avg_cost (0005) | ✅ | A-07 confirms the method | 060 | Stock value tile still uses last price until Phase 3 | bd7126e | R |
| Integrity: receiving guards + request ids (0005) | ✅ | – | 060, e2e 030 | – | bd7126e | R |
| Integrity: void limited to open day + refund dated today (0006, D-008) | ✅ | – | 070_voids_refunds (27), e2e 040 | Whole-sale refunds only; earlier days reachable once history search ships (Phase 1) | 6ffb899 | R |
| Integrity: sales reports without the 1000-row cap | ✅ | – | e2e 040 (fails on the old page) | Single-day lists (Home, POS) keep one request: a day stays far below 1000 sales | 6ffb899 | R |
| Release / rollback runbook (docs/PUBLICAR.md) | 🟡 | – | – | – | – | – |

## Release readiness

| Feature | Status | Depends on | Tests | Known issues | Commit | Prod |
|---|---|---|---|---|---|---|
| Independent security review (4 areas) and hardening (0025): books/payroll/bank need the owner's phone code or the accountant with code; sales numbers need the sales permission; NaN/infinity refused; payables, bank, payroll, PIN, FX, inventory and storage fixes; CSV, XSS, PIN and workflow fixes in the pages (D-022) | ✅ | – | 250_security_hardening (39), 240_release_check (4), e2e 170, 210 | Two accepted low findings (D-022) | e476844 | R |
| Release package: wave plan, read-only release check, rollback by migration, training (docs/LANZAMIENTO.md, supabase/tools/release-check.sql) | ✅ | E-13/E-14 (staging) for the dress rehearsal | 240_release_check | Staging rehearsal not done (no staging project yet) | 9ecc79a | R |

## Phase 1 · POS and operations

| Feature | Status | Depends on | Tests | Known issues | Commit | Prod |
|---|---|---|---|---|---|---|
| On-screen numeric PIN keypad (all PIN fields) | ✅ | – | e2e 110 (3) | – | b02dfbe | R |
| Amount and quantity pads; optional on-screen text keyboard | ✅ | – | e2e 110 | Text keyboard is opt-in per device (HG_KEYPAD.setText) | b02dfbe | R |
| Settings framework with compliance locks; operator sessions, clock-in requirement, sale attribution, offline claims (0008) | ✅ | – | 090_settings_operators (27), e2e 120 (5) | Mode starts 'off' in production; owner switches it on Home | aeca1d1 | R |
| Tax engine: rates with confirmation, per-item rate + CABYS, per-line IVA/net/discount share stored by the server, refunds carry IVA back, tax_summary (0009); POS ticket and receipt by rate; Menu Manager fields | ✅ | A-04 (each item's rate and CABYS) | 100_tax_engine (21), e2e 130 (3) | Every item starts at 13 % (as today) until the accountant assigns codes | f84231c | R |
| Tax-exclusive pricing: POS shows prices before IVA and adds it; Menu Manager takes prices before IVA; website/TV/QR keep final prices | 🔒 | A-03, A-04 | 100 (lock), e2e 130 (display) | Locked by the `price_display_rules` confirmation | f84231c | – |
| CRC + USD totals; daily rate (Hacienda API job, manual entry by a manager, buy/sell setting); rate kept with every dollar payment (0010) | 🟡 | A-06, E-16 | 110_fx_cash (21), e2e 140 | Automatic fetch needs the http + pg_cron extensions and a first live check of the API answer (E-16); manual rate works now | f9f0ab1 | R (manual) |
| Cash window: notes and coins, typed amount, exact, change, dollars and mixed; tender kept per payment (new sales and bills) | ✅ | – | e2e 140 (2), 070 | Charging an open order from the list (data-lpay) and room orders at the window (data-rpay) still record no tender: counted as before | f9f0ab1 | R |
| Two-currency register: float and count in ₡ and $, expected from the tenders, day's rate kept | ✅ | – | 110, e2e 140 | Payments without tender detail count in colones as before | f9f0ab1 | R |
| Server receipt numbers; sales search (day, Nº, item, name, cashier, amount); reprint marked COPIA with change and IVA as stored, logged; void (open day) / refund (closed day) from the search (0011) | ✅ | – | 120_history_receipts (16), e2e 150 (2) | Older sales have no number (shown by time); earlier days need a manager PIN | 64548dc | R |
| Inventory → create every vendor's order in one tap (suggestions by vendor already existed); PO numbers (0012) | ✅ | – | 130_purchasing, e2e 160 | – | 1fdfb9c | R |
| PO document (print / save as PDF), WhatsApp, email, share sheet or copy text | ✅ | – | e2e 160 | PDF is the browser's "Save as PDF" (no paid service) | 1fdfb9c | R |
| Deliveries in parts with supplier invoice Nº/date, duplicate-invoice guard, repeat-safe, "nothing more is coming" (0012) | ✅ | – | 130_purchasing (16), e2e 160 | – | 1fdfb9c | R |
| Spanish-first staff screens: default Spanish, every new message translated, sweep of all staff pages done (outdated setup messages replaced), lint refuses conflicting translations | ✅ | – | e2e 110, 060; lint | Menu item names and descriptions are the owner's own text (Spanish columns for the QR menu) | e2c406d | R |

## Phase 2 · Accounting foundation

| Feature | Status | Depends on | Tests | Known issues | Commit | Prod |
|---|---|---|---|---|---|---|
| Chart of accounts (proposed, accountant-editable) + mappings of the automatic lines (0013) | 🔒 | A-07 | 140_ledger, e2e 170 | Automatic posting waits for the accountant's approval (chart_of_accounts_approved) | e2c406d | R |
| Double-entry ledger: balanced at commit, never edited (reversals), idempotent source keys (0013) | ✅ | – | 140_ledger (48), e2e 170 | – | e2c406d | R |
| Monthly periods open → closed → locked, in order (0013) | ✅ | – | 140, e2e 170 | – | e2c406d | R |
| Automated posting of each day at the register close: sales net of IVA, IVA, money by method and currency, open-bill advances, cash over/short, COGS, waste, counts, purchases; late sales post the difference (0013) | 🔒 | A-07 | 140, e2e 170 | Off until approved; bills count on the day paid in full (revenue timing pending A-07); card fees/withholdings come with bank reconciliation (Phase 4) | e2c406d | R |
| Expenses with creditable IVA (cash, petty cash, bank, on credit), duplicate-invoice guard, voids by reversal, invoice photo/PDF in a private bucket (0014, 0015) | ✅ | E-17 for backing up the invoice files | 150_expenses (13), 160_receipts (10), e2e 170 | Petty-cash top-ups are journal entries until Phase 4 | e2c406d | R |
| Accountant login kind (phone code), granted by the owner on Home; no POS/inventory access (0013) | ✅ | – | 140, e2e 170 | The owner creates the login in Supabase Auth first | e2c406d | R |
| Trial balance, income statement, balance sheet (checks it balances), cash flow (direct) | ✅ | – | 140, e2e 170 | – | e2c406d | R |
| Exports: CSV of every report, journal and expenses; print to PDF; month's package (ZIP of 7 CSVs incl. sales IVA by rate) | ✅ | – | e2e 170 | CSV opens in Excel (UTF-8 with BOM) | e2c406d | R |
| Accounting page (accounting.html) + tile on Home, Spanish | ✅ | – | e2e 170 (5) | – | e2c406d | R |

## Phase 3 · Costa Rican tax and supplier accounting

| Feature | Status | Depends on | Tests | Known issues | Commit | Prod |
|---|---|---|---|---|---|---|
| IVA accounting (sales IVA per line at sale time, creditable IVA on expenses and supplier invoices, ledger 2110/1140) and the period's IVA draft for the accountant: sales by rate, refunds, every purchase document, net, tie-out to the books; in the month's package (0009, 0013, 0014, 0016, 0017) | ✅ | A-01 (regime, proportional credit) | 100_tax, 180_iva_costing (24), e2e 190 | A draft, not the return: the accountant applies proportionality and files; sales before 0009 have no IVA detail and are shown apart | bd8d370 | R |
| CABYS per product (13 digits, Admin → Menu) and the list of products on sale still without one (0009, 0018) | 🔒 | A-04 (each product's code) | 100_tax, 190_einvoice, e2e 200 | Codes are typed by the owner/accountant; none are guessed | bd8d370 | R |
| E-invoice document tracking: one document per sale (ticket), per refund (credit note linked to the sale's), invoice with the customer's ID; statuses forward-only through a service-only function; "record only" mode, nothing sent; Accounting → E-invoices (0018) | 🔒 | A-02, A-10 (provider, credentials, format version) | 190_einvoice (26), e2e 200 (2) | No provider connector, no XML, no signing, no sending (built after A-10); the POS has no "invoice with ID" button yet (function ready) | bd8d370 | R |
| Supplier invoices linked to deliveries (IVA credit, price difference to 5103), invoices for services to their account, AP, supplier payments (oldest first or chosen invoice), aging 0/30/60/60+, AP tie-out to the ledger, voids by reversal (0016) | ✅ | – | 170_payables (41), e2e 180 (2) | Supplier e-invoice XML import not built (typed by hand) | c264eb2 | R |
| Weighted-average cost per item, cost stamped on every stock move, COGS at the day's entry, inventory valuation report with tie-out to 1150 (0005, 0013, 0017) | 🔒 | A-07 (costing method) | 060_inventory, 140_ledger, 180_iva_costing, e2e 190 | Method proposed (weighted average) until the accountant confirms | bd8d370 | R |
| Profit by product: units, sales net of IVA and discounts, actual cost at the moment of sale, margin, food cost %; recipe cost and margin per unit at today's price; products without recipe counted (0017) | ✅ | – | 180_iva_costing, e2e 190 | Products are matched by name, as the stock deduction does | bd8d370 | R |

## Phase 4 · Cash, banking, payroll

| Feature | Status | Depends on | Tests | Known issues | Commit | Prod |
|---|---|---|---|---|---|---|
| Register cash in/out with a manager's PIN (bank deposits, change from the bank, petty cash, payouts for purchases, owner), in ₡ or $; the drawer's expected cash and the day's entry follow them; payouts wait in 1104 until their invoice is filed as an expense or supplier payment (0019) | ✅ | – | 200_cash_movements (30), e2e 210 (3) | Petty cash is an account (1103) fed from the drawer or the bank; spending from it is filed as expenses "paid from petty cash" | 89ab3e1 | R |
| CRC and USD cash reconciliation by day: float, cash sales, money in/out, expected, counted, difference, each currency; CSV (0019) | ✅ | A-06 (exchange differences on dollars held) | 200_cash_movements, e2e 210 | Dollars are valued at the day's rate; revaluing dollars held over days is a manual entry for now | 89ab3e1 | R |
| Bank accounts (last 4 digits only), statement import from the bank's CSV with column mapping (any separator, d/m/y, 1.234,56), no duplicates across overlapping files, automatic and suggested matching, posting what the books lack (fees, card deposits less the fee), ignore with a note, undo by reversal, books vs statement summary (0020) | ✅ | – | 210_bank (26), e2e 220 | No direct bank connection (no bank API, no paid aggregator); USD accounts are matched in their own currency against a colón ledger account only if the accountant keeps one per currency | 95c137d | R |
| Pay periods (no frequency assumed), timesheet review (open shifts, over 12 h, overlaps, edited by hand), owner approval with a copy of the approved hours, approved hours locked against punches, edits and deletes (even with a manager PIN), reopen with a reason until the payroll is posted (0021) | ✅ | – | 220_timesheets_payroll (39), e2e 230 | – | 95c137d | R |
| Pay rates (hourly or fixed per period, with history), deduction/charge rules only with who confirmed them (none built in), payroll from approved hours, other deductions with a note, accountant review, posting (6101/6102 vs 2130/2131/2132), payment; labor cost and labor % by day (0022) | 🔒 | A-08 (CCSS/INS/income-tax rules and amounts, frequency) | 220_timesheets_payroll, e2e 230 | Gross pay only until the accountant enters the confirmed rules; income-tax withholding is typed by the accountant as another deduction; no CCSS/Hacienda filing files | 95c137d | R |

## Phase 5 · Business intelligence and growth

| Feature | Status | Depends on | Tests | Known issues | Commit | Prod |
|---|---|---|---|---|---|---|
| Owner dashboard: today's sales with and without IVA, orders, average, payment mix, voids and unpaid bills, same weekday last week up to the same hour; "estimate" while the register is open, "final" once closed; on Home and on the new Insights page (0023) | ✅ | – | 230_insights (23), e2e 240 (2) | – | 83accba | R |
| Sales patterns (by day, weekday × hour heatmap, categories), money that leaks (discounts, voids, refunds), product profit and food cost % with products lacking recipes flagged, inventory valuation (0017, 0023) | ✅ | – | 180_iva_costing, 230_insights, e2e 190, 240 | Products are matched by name, as the stock deduction does | 83accba | R |
| Supplier insights (received, deliveries, days to deliver vs usual, late, owed, price changes per item); stock forecast (use per day weighted to the last week, what is on its way, delivery days → order now / within 3 days, packs to order) (0023) | ✅ | – | 230_insights, e2e 240 | The forecast follows recorded use: items without recipes are not deducted by sales | 83accba | R |
| Month by month: sales without IVA, orders, average, cost of sales, food cost %, waste, purchases, expenses, labor and labor %, prime cost %; CSV; labor only for the owner and the accountant (0022, 0023) | ✅ | A-08 for exact labor cost (charges) | 220, 230_insights, e2e 230, 240 | Labor is hours × rate (charges not included until A-08) | 83accba | R |
| Multi-location ready: locations table with today's café, location_id (default: today's café) on sales, registers, cash movements, stock moves, shifts, purchase orders, bank accounts, expenses and ledger entries (0024) | ✅ | – | 230_insights | A second location still needs registers and stock per location and devices that say their location (D-021) | 83accba | R |
