# Decision log (Canopy OS)

Major technical decisions, newest last. Each one says what was decided, why, and what was rejected.

## D-001 · 2026-10-12 · Production publishes only by hand from a release tag
- **Decision:** `.github/workflows/pages.yml` runs only on `workflow_dispatch`, only from a `v*` tag, only
  after typing PUBLICAR, in the `production` environment.
- **Why:** before this, 48 pushes to working branches published straight to the live café site. The AI
  agent's GitHub credential has admin rights, so in-repository gates cannot separate the agent from the
  owner. The rule in `CLAUDE.md` forbids agents from running the workflow or creating tags.
- **Recommended next step (owner):** move production publishing to a separate owner-only repository
  (docs/PUBLICAR.md, "Opción fuerte").
- **Rejected:** publishing on merge to `main` (no `main` exists; a merge is still an agent-reachable action).

## D-002 · 2026-10-12 · Migrations are numbered SQL files with a ledger, pasted by the owner
- **Decision:** `supabase/migrations/NNNN_name.sql`. Each file calls `canopy.migration_begin/end`, refuses
  repeats and out-of-order runs, and runs as one transaction. The 18 historical scripts carry a guard that
  stops them once the ledger exists.
- **Why:** the owner keeps control of production with no database credential shared with the agent.
  Replaying the historical scripts silently reverted security fixes (e.g. `kitchen-rooms.sql`).
- **Rejected:** Supabase CLI `db push` from CI (needs a production credential in GitHub); Supabase
  Branching (paid, beta).

## D-003 · 2026-10-12 · Test database = Supabase look-alike + historical scripts + migrations
- **Decision:** `tests/build-db.sh` rebuilds the schema exactly as production received it. Base tables are
  reconstructed until the production schema export arrives. SQL tests use a small assertion library
  (`tests/sql/_helpers.sql`). Browser tests run the real pages against PostgREST and a local auth
  stand-in (`tests/e2e`). Any request to the real Supabase fails the test.
- **Rejected:** pgTAP / Supabase CLI local stack (Docker-heavy, not available offline here).

## D-004 · 2026-10-12 · Backups: cloud producer + owner-computer collector, age encryption
- **Decision:**
  - A nightly GitHub Actions job in an owner-only PRIVATE repository dumps the database with a read-only
    `canopy_backup` account.
  - It restore-tests every dump, encrypts with age to two public keys (owner + offline recovery), and
    uploads to deletion-locked object storage.
  - The owner's computer pulls the encrypted files hourly and at log-in, so it catches up after being off.
  - Monthly USB copy.
  - The status feeds the owner's Home tile.
- **Why:** meets "computer may be off" plus a "separately protected copy". Unattended jobs never hold a
  decryption key. A stolen backup credential cannot write, and a stolen storage key cannot delete locked
  copies.
- **Rejected:**
  - computer-only backups (gaps while off);
  - artifacts in the public repo (readable by anyone signed in);
  - restic in the cloud job (needs a symmetric password on the runner);
  - Supabase PITR (~US$100+/month).

## D-005 · 2026-10-12 · One configuration file chooses the environment by web address
- **Decision:** `website/config.js` maps `hanginggardencafe.com` → production, `staging.hanginggardencafe.com`
  → staging, `127.0.0.1` → local tests. Staff pages refuse unknown addresses; public pages fall back to
  production.
- **Why:** staging must be a different web origin. Devices keep the offline sales queue in browser storage
  per origin, so a staging page on the production origin could move real sales into the test database.

## D-006 · 2026-10-12 · Security fix shipped first as migration 0001
- **Decision:** room-order functions, `room_new_code` and `quick_items` get authorization checks.
  `place_room_order` finds `gen_random_bytes` in the `extensions` schema.
- **Why:** verified on a test copy that any signed-in account could cancel or mark paid a guest's order.
  Reported to the owner immediately with the files to apply.

## D-007 · 2026-10-12 · Inventory history is kept; cost travels with every movement
- **Decision:** items and vendors with history are deactivated, never deleted. Only movements change stock.
  Every movement stores its unit cost; purchases keep a weighted-average cost (`stock_items.avg_cost`).
  Counts, waste and receipts carry a request id so a retry counts once.
- **Why:** deleting an item erased its sales and purchase history (cascade), and costs were overwritten by
  each purchase, so the cost of goods sold could not be rebuilt for the accountant.
- **Pending:** the accountant confirms weighted average as the valuation method (A-07).

## D-008 · 2026-10-12 · A counted day is never changed: voids while open, refunds after
- **Decision:** a paid sale can be voided only while its register day is still open. After the register is
  closed (or for an earlier day with no register), the manager records a refund: a negative sale dated today,
  same payment method by default, optional restock, PIN and reason, linked to the original sale.
- **Why:** voiding an old sale silently changed totals of a day already counted and closed, so the register
  record, the sales report and (later) the ledger would disagree.
- **Limits for now:** whole-sale refunds only; partial refunds and bills paid in parts come with the order
  history search (Phase 1). Today the refund is reachable from the POS orders list (today's sales); the
  history search will reach earlier days.

## D-009 · 2026-10-12 · Settings with compliance locks
- **Decision:** owner decisions live in `public.settings`, validated against `canopy.setting_defs`. A
  regulated setting (tax-exclusive prices, e-invoicing, payroll rates) has a *guard*: it cannot leave its
  default until `compliance_confirm` records who confirmed the rule and with which document. Every change
  and confirmation is in the approvals log. Only the owner login with the phone code can change settings.
- **Why:** the owner directive forbids activating unverified tax or payroll rules. A lock in the database
  holds even if a page or a person makes a mistake.

## D-010 · 2026-10-12 · Who rang each sale: a PIN session per device, the sale carries its own operator
- **Decision:** the cashier signs in on the POS with a PIN (`pos_operator_start`); the device sends the
  session token in the `x-hg-operator` header, so every order and bill payment records `operator_id`. A sale
  waiting offline carries the token of the person who rang it, so a later upload never re-assigns it. With no
  internet the cashier picks their name without a PIN check; those sales are marked `operator_unverified`.
  Modes: `off` (default, nothing changes), `record` (marks sales of someone not clocked in), `enforce`
  (must be clocked in; the POS offers "Clock in and start").
- **Why:** accountability per employee without ever refusing a sale that was already charged.

## D-011 · 2026-10-12 · Prices are stored with IVA; "tax-exclusive" is a display and price-entry mode
- **Decision:** `menu_items.price_crc` and every sale line keep the final price (IVA included). The server
  works out each line's IVA from the product's rate at the moment of sale (`order_items.tax_crc`, `net_crc`,
  `discount_alloc_crc`). The owner's tax-exclusive choice (`price_mode = exclusive`, locked behind
  `price_display_rules`) only changes what the POS buttons and the Menu Manager show and accept
  (₡1 000 + IVA = ₡1 130 charged and stored); the website, TV board and QR menu always show final prices.
- **Why:** one storage convention keeps every existing total, bill, split and register check correct; final
  prices on public displays follow the MEIC rule reported in A-03; switching the mode never rewrites history.
- **Rates:** only the general 13 % (Ley 9635) is built in. Any other rate is added by the owner with who
  confirmed it and the document; a rate used on sales can never be changed (a new code is added instead).

## D-012 · 2026-10-12 · Cash is recorded as it is received; the drawer is counted in two currencies
- **Decision:** every cash payment can carry its tender (`cash_tenders`: colones in, dollars in, change in
  colones, the rate the cashier used and the official one). The register expects colones = float + colones
  in − change, and dollars = dollar float + dollars in. Payments without tender (older pages, room orders
  charged at the window) count in colones as before. Rates: a daily row in `fx_rates` from Hacienda's
  public API (free, no key) when the owner enables the extensions, or typed by a manager (never over an
  official rate). The owner chooses buy or sell (`fx_rate_kind`, default buy, pending A-06).
- **Why:** "Cash $" kept only a colón amount, and the close expected those dollars as colones.

## D-013 · 2026-10-12 · The ledger posts each day from the register, as differences
- **Decision:** the books live in schema `acct` (not exposed). Each closed day gets one entry computed from
  the sales, payments, tenders, register count and stock moves of that day; posting again compares the
  computed day with what is already posted and records only the difference (a late sale, a re-close). A
  closed month is never touched: a difference for it is dated in the open month with a note. Entries balance
  at commit, are never edited or deleted (reversals), and automatic ones are keyed so they never repeat.
- **Why:** sales keep arriving after a close (offline devices, bills paid later); recomputing and posting
  deltas keeps the books equal to the operational records without ever rewriting history.
- **Bills paid in parts:** money received before the bill is fully paid waits in "Anticipos de clientes"; the
  sale (and its IVA) is recognized the day the bill is paid in full — revenue timing to confirm (A-07).
- **Pending:** the accountant approves the chart and the mappings (A-07) before automatic posting is switched on.

## D-014 · 2026-10-12 · Supplier invoices settle deliveries already owed; differences never touch the inventory account
- **Decision:** a delivery received in Inventory is owed at its cost from the day it arrives (the day's
  entry: inventory against accounts payable). The supplier's invoice, entered later in Accounting →
  Suppliers and linked to its deliveries, posts only what the delivery did not: the creditable IVA and any
  price difference (to 5103 "Ajustes de inventario", not to inventory, so the inventory account keeps
  matching the stock valued at average cost). An invoice without deliveries (a repair, equipment) names the
  account it goes to. Payments go to the chosen invoice first, then the oldest due; never more than owed.
  Invoices and payments are voided by reversal; an invoice with payments is not voided until they are.
- **Why:** one cost per delivery (what Inventory received) keeps COGS and the stock valuation consistent;
  the invoice is the document for IVA and for what is owed.
- **Tie-out:** accounts payable in the books = open invoices + received not invoiced + expenses on credit;
  the Suppliers screen shows any difference (days not posted, entries by hand).

## D-015 · 2026-10-12 · The period's IVA is a draft built from the documents, checked against the books
- **Decision:** `iva_report` adds the IVA stamped on each sale line (by rate), the IVA given back by refunds,
  and the creditable IVA of every expense and supplier invoice (each document listed), and shows the same
  period in the ledger (2110, 1140) with the days still unposted. It is labelled a draft: the accountant
  applies the proportional credit if any sales are exempt or at other rates, completes the return and files
  it. Sales recorded before the tax engine (0009) are listed apart, never estimated into the totals.
- **Why:** the café's regime and the return's exact layout are pending (A-01); the data the accountant needs
  is complete and traceable without the system pretending to file.

## D-016 · 2026-10-12 · Electronic invoicing: a document register now, the provider connector later
- **Decision:** `e_documents` holds one document per sale (ticket), per refund (credit note linked to the
  sale's document) and, when a customer gives their ID, an invoice. The only modes are `off` (default) and
  `shadow` (record and show what is missing, e.g. CABYS; send nothing). No XML, signature, numbering key
  or sending is built: the key (clave) and consecutive number are stored only as returned by a provider.
  States move forward only through `canopy.einvoice_mark`, callable by the service role (the future
  connector), never by a page. A sale is never stopped by this register (errors go to the audit log).
- **Why:** the provider, credentials and the format version (A-02, A-10) are not chosen; building the
  register now lets the owner see readiness (CABYS per product, volumes) at zero cost and with no risk.

## D-017 · 2026-10-12 · Money taken from the drawer is recorded at the moment; its invoice comes later
- **Decision:** a manager records every cash in/out of the drawer on the POS (PIN and reason): to the bank,
  change from the bank, petty cash, a purchase paid from the drawer ("payout"), or the owner. The drawer's
  expected cash counts them, so the close is not falsely short. In the books each goes against its
  counterpart; a payout goes to 1104 "Pagos de caja por documentar" until the accountant files its invoice as
  an expense or supplier payment "paid with money taken from the register", which clears 1104. The old
  "The register (colones)" choice on expenses became "Cash from the safe (not the register drawer)".
- **Why:** previously a purchase paid from the drawer showed as a shortage at the close *and* as an
  expense paid in cash: the same colones were taken out of the books twice.
- **Also fixed:** the day's dollar rate could not be typed anywhere (only the automatic job, still OFF);
  Home → System settings now has the owner/manager field (never over an official rate).

## D-018 · 2026-10-12 · Bank statements are imported from the bank's own CSV; no bank connection
- **Decision:** the accountant downloads the movements from the bank's website and imports the CSV; the
  page reads it (separator, decimal style and date order chosen or guessed, columns picked once per account)
  and the server keeps each movement once, by a fingerprint of date, amount, text, reference and its
  repetition within the file. Movements are matched to ledger lines of the bank's account (same amount,
  within days), or posted when the books lack them (one or two parts: a card deposit is the card sales
  less the fee), or ignored with a note. Undoing a posted movement reverses its entry.
- **Why:** Costa Rican banks' formats differ and direct connections need paid aggregators or bank
  agreements (no subscriptions without approval); a CSV works with every bank at no cost.

## D-019 · 2026-10-12 · Payroll is prepared from approved hours; no legal rate is built in
- **Decision:** the owner approves each pay period's hours (a copy is kept and the period's shifts are
  locked). The payroll multiplies approved hours by each person's rate (or a fixed amount per period) and
  applies only the deduction and employer-charge percentages entered with who confirmed them; income-tax
  withholding and advances are typed per person with a note. The accountant marks it reviewed; only then is
  it posted (gross and employer charges against salaries, charges and withholdings payable) and paid.
- **Why:** CCSS, INS and income-tax rules (A-08) are not confirmed; the system must not invent them.

## D-020 · 2026-10-12 · Insights are computed from the operational records, labelled estimate or final
- **Decision:** the owner's numbers (today, months, patterns, products, suppliers, stock forecast) come from
  read-only functions over the sales, stock moves, receipts, invoices and shifts — not from the ledger — so
  they work before the accountant switches the books on. Today is an "estimate" while the register is open
  (tablets may still send sales, bills may be unpaid) and "final" once it is closed. Sales without IVA use
  each line's stamped IVA; older sales are estimated at 13 % and labelled so. Labor needs the pay rates, so
  only the owner (with the phone code) and the accountant see it.
- **Charts:** plain SVG, no library; one hue for magnitude (sales bars, the busy-hours heatmap), three
  fixed, checked colors for the cost percentages (food #A07629, labor #1E4B33, prime #3B6EA8: each pair
  ≥ 16 OKLab ΔE under protan/deutan/tritan simulation, each ≥ 3.6:1 on the page), legend + labels, tooltips,
  and the numbers in a table and CSV.

## D-021 · 2026-10-12 · One café today; the data is ready for a second one
- **Decision:** `locations` holds today's café; the main tables carry `location_id` with today's café as the
  default, so nothing changes for the pages. A second location will need (as a later, separate migration):
  one register per location per day (today `register_days.business_date` is unique), stock per location,
  each device saying its location, and reports filtered by it.
- **Why:** adding the column now, with a default, is cheap and safe; the larger changes depend on how a
  second location would actually run.

## D-022 · 2026-10-12 · Pre-release security review: what changed (migration 0025 and the pages)
- **How:** four independent read-only reviews, by area: Phase 1 migrations, books and IVA, cash/bank/payroll/insights,
  and the pages. Each finding was confirmed against the code (most by running the attack on a test database),
  fixed, and is now an automated test (`tests/sql/250_security_hardening`, browser 170 and 210).
- **The owner's phone code, not the owner's PIN, opens the books.** The owner's PIN typed on the café tablet
  still opens the owner areas it always did (Menu, Sales, Inventory, team), but the books, payroll, pay rates,
  the bank, legal confirmations, switches, tax rates and accountant access need the owner's own login with the
  phone code. The accountant always signs in with the phone code too; Accounting offers to turn it on.
- **Sales numbers need the sales permission.** Insights, profit by product, the period's IVA, cash by day and
  the history of earlier days follow the same rule as the Sales page; a manager without it can still find one
  receipt by its number to refund it.
- **Money is a number.** NaN and infinity are refused in every money and quantity column (they had passed every
  check and made the books unreadable for good).
- **Integrity:**
  - nothing is dated into a month before one already closed;
  - a supplier's invoices and payments are saved one at a time (no overpaying with two clicks);
  - a bank movement posted again after an undo gets its own entry;
  - payroll is reviewed and posted only if it was prepared from the hours as approved now, and no net pay is
    below zero;
  - wrong-PIN tries sent at the same moment are counted one by one;
  - an exchange rate typed by hand stays between 100 and 2 000, and within 5 % of the last rate unless the
    owner with the code types it;
  - an "opening balance" never rewrites the cost of an item with history;
  - received purchase lines can't be edited;
  - a receipt file can only go into the folder of an expense without one;
  - the tablet sees earlier days' cash only with the sales permission;
  - an invoice request (customer ID) is written once, for a sale of today;
  - dollar bank accounts wait until their movements are valued in colones.
- **Pages:**
  - an inventory unit can no longer carry HTML;
  - every CSV export neutralizes cells that would start a spreadsheet formula;
  - the manager PIN never stays in the cash in/out form;
  - the publish workflow reads its inputs as variables, and only a tag `vAAAA.MM.DD-N` publishes;
  - translations never treat `$` in user text as a pattern.
- **Accepted (low, documented):**
  - the till's internal tender function stays callable by the café login (a wrong tender is flagged as a mismatch);
  - inventory cost-edit log rows can be written by an unlocked manager (attributed to them).

## D-023 · 2026-10-12 · Before production: verify read-only, back up first, rehearse on a copy of today's schema
- **Verified (read-only):** the live site is the `gh-pages` branch at `8950054`, an exact copy of development
  commit `ac8298a`'s `website/` (plus CNAME), published automatically on 2026-10-09 by the old workflow. Since the
  manual-only workflow (`c754fc4`), 27 pushes (20 touching `website/`) published nothing. The database could not
  be read from here (and must not be): `supabase/tools/production-snapshot.sql` reports it, read-only.
- **Order:** snapshot → logins review and sign-ups off (no data change, reversible, no page depends on sign-ups)
  → verified backup (works before 0000: `supabase/tools/backup-account.sql`) → 0000, 0001, 0002 → rehearsal with
  the real data in staging → the 0003–0025 window.
- **Rehearsal** (`tests/run.sh rehearsal`, also in CI): the historical scripts plus ~4 months of café history,
  migrations applied as a non-superuser account like Supabase's SQL Editor, then every original column of every
  original table and 27 business checks compared (identical), the live pages run against the result, an offline
  sale queued before the window uploaded after it, 30 days of old history booked (balanced, tied to sales), backup
  and restore before and after.
- **It found and fixed (all in migrations not yet applied):**
  - 0001 also closes three more ways a self-made login could act: rename/recolor menu categories (the legacy
    "categories color for signed-in" rule covered every column on Supabase), guess PINs on the time clock, and
    on voids; the old pages' Menu Manager keeps working through the owner rule;
  - 0002 failed on PostgreSQL 16+ when the backup account already existed (it altered a role it did not own);
    it now alters only when needed and has a table-by-table fallback if `pg_read_all_data` cannot be granted;
  - 0003's backfill looked up each order's lines one by one (no index on `order_items.order_id`): 42 s on 14 500
    orders, minutes on a larger history and the 300 s limit; now one pass plus that index: 0.3 s, same result
    (checked row by row).
- **Why:** the user asked for verified state, a restorable backup and a rehearsal before any production change.

## D-024 · 2026-10-12 · Restoring a backup keeps who may run what
- **Found by the staging rehearsal:** Supabase grants every new function and table in `public` to visitors and
  logins. A dump records each object's rights only as a difference from PostgreSQL's own default, so a plain
  restore opened ~50 functions, `make_owner` included, to anonymous visitors.
- **Decision:** every restore (nightly test, disaster `restore.sh`, staging copy) switches those default grants off
  while loading and back on afterwards, and compares a fingerprint of all rights, row-security switches and rules
  with the source; a difference fails the restore. The backup manifest carries that fingerprint.

## D-025 · 2026-10-12 · Staging: a separate free project, an anonymized copy, a separate site
- **Decision:** staging is its own Supabase project and its own GitHub Pages site
  (`jeanpaulcocaleca-create.github.io/canopy-pruebas`). The copy is made by the owner's private repository with
  the read-only account, anonymized in a throw-away database (names, guests, suppliers, PINs, logins), then loaded
  into staging, where the migrations are rehearsed. `config.js` and the staging publisher refuse production's
  address or key, and any key that is not the public anon key.
- **Why:** a rehearsal on the real data shape without real personal data, and no path from the staging site to
  production. Public-repository SQL reaches staging only through `psql -c` (no psql or shell commands run).

## D-026 · 2026-10-12 · The owner's pricing policy is kept, switched off
- **Policy (owner, 2026-10-12):** menu prices exclude IVA; the applicable tax is added at checkout.
- **Built:** `price_mode = exclusive` (POS shows prices before IVA and adds it; the Menu Manager takes prices before
  IVA). It stays OFF in production behind the `price_display_rules` confirmation until the legal treatment and the
  customer-facing prices are verified (A-03). The rehearsal checks it is off after the window.
- **Activation question (not a code change):** prices are stored as charged. Switching the mode alone does not
  change what customers pay. If today's prices are meant to be before IVA, each must be re-entered as a
  before-IVA price (customers then pay 13 % more): an owner and accountant decision.
