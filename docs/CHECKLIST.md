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
| Earlier browser suites ported (bills/tabs, open orders on the device, QR menu, kitchen) | ✅ | – | e2e 070–100 (34) | – | (this commit) | – |
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

## Phase 1 · POS and operations

| Feature | Status | Depends on | Tests | Known issues | Commit | Prod |
|---|---|---|---|---|---|---|
| On-screen numeric PIN keypad (all PIN fields) | ⏳ | – | – | – | – | – |
| Amount and quantity pads; optional on-screen text keyboard | ⏳ | – | – | – | – | – |
| Operator sessions, clock-in requirement, sale attribution (offline-safe) | ⏳ | – | – | – | – | – |
| Tax engine: tax codes, CABYS, per-line IVA stored | ⏳ | – | – | – | – | – |
| Tax-exclusive pricing (activation OFF until A-03/A-04) | ⏳ | A-03, A-04 | – | – | – | – |
| CRC + USD totals, exchange-rate fetch, rate snapshots | ⏳ | A-06 (policy) | – | – | – | – |
| Cash window: denominations, change, mixed currency | ⏳ | – | – | – | – | – |
| Two-currency register close | ⏳ | – | – | – | – | – |
| Order history search + receipt reprint (COPIA) | ⏳ | – | – | – | – | – |
| Inventario → Crear Pedido (multi-supplier) | ⏳ | – | – | – | – | – |
| PO document (print/PDF), text, WhatsApp, share, email | ⏳ | – | – | – | – | – |
| Partial deliveries, supplier invoice refs, duplicate guard | ⏳ | – | – | – | – | – |
| Spanish-first staff screens | ⏳ | – | – | – | – | – |

## Phase 2 · Accounting foundation

| Feature | Status | Depends on | Tests | Known issues | Commit | Prod |
|---|---|---|---|---|---|---|
| Chart of accounts (default, accountant-editable) | ⏳ | A-07 | – | – | – | – |
| Double-entry ledger (balanced, immutable, idempotent) | ⏳ | – | – | – | – | – |
| Fiscal periods, closing and locking | ⏳ | – | – | – | – | – |
| Automated posting (daily sales, refunds, cash, COGS) | ⏳ | – | – | – | – | – |
| Expenses, petty cash, receipt photos | ⏳ | – | – | – | – | – |
| Accountant role and login | ⏳ | – | – | – | – | – |
| Trial balance, P&L, balance sheet, cash flow | ⏳ | – | – | – | – | – |
| Accountant exports (CSV/Excel/PDF, monthly package) | ⏳ | – | – | – | – | – |
| Accounting section in owner dashboard | ⏳ | – | – | – | – | – |

## Phase 3 · Costa Rican tax and supplier accounting

| Feature | Status | Depends on | Tests | Known issues | Commit | Prod |
|---|---|---|---|---|---|---|
| IVA accounting and monthly IVA summary | ⏳ | A-01 | – | – | – | – |
| CABYS support | ⏳ | A-04 | – | – | – | – |
| E-invoice document tracking + credit notes (provider integration OFF) | ⏳ | A-02, A-10 | – | – | – | – |
| Supplier invoices, AP, supplier payments | ⏳ | – | – | – | – | – |
| Weighted-average costing, inventory valuation, COGS | ⏳ | A-07 | – | – | – | – |
| Recipe profitability | ⏳ | – | – | – | – | – |

## Phase 4 · Cash, banking, payroll

| Feature | Status | Depends on | Tests | Known issues | Commit | Prod |
|---|---|---|---|---|---|---|
| Petty cash, register withdrawals, deposits | ⏳ | – | – | – | – | – |
| CRC and USD reconciliation | ⏳ | – | – | – | – | – |
| Bank accounts, statement import, reconciliation | ⏳ | – | – | – | – | – |
| Pay periods, timesheet approval and locking | ⏳ | – | – | – | – | – |
| Payroll preparation, labor cost, accountant-reviewed posting (rates OFF until A-08) | ⏳ | A-08 | – | – | – | – |

## Phase 5 · Business intelligence and growth

| Feature | Status | Depends on | Tests | Known issues | Commit | Prod |
|---|---|---|---|---|---|---|
| Improved owner dashboard (estimated vs final) | ⏳ | – | – | – | – | – |
| Sales and profitability analysis, inventory profitability | ⏳ | – | – | – | – | – |
| Supplier purchasing insights, low-stock forecasting | ⏳ | – | – | – | – | – |
| Labor cost %, financial trends | ⏳ | – | – | – | – | – |
| Multi-location-ready architecture (location ids) | ⏳ | – | – | – | – | – |
