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
    it now alters only when needed and has a table-by-table fallback if `pg_read_all_data` cannot be granted
    (*superseded by D-033: 0002 no longer grants `pg_read_all_data`*);
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

## D-027 · 2026-10-12 · What the production snapshot showed, and what follows from it
- **Snapshot (read-only, run by the owner on 2026-10-12):**
  - PostgreSQL 17.6, 13 MB, no migration applied;
  - 86 functions: 85 are the legacy versions, and only `audit_menu()` differs;
  - `orders` has one extra column, `note` (text), that no page, function or migration uses;
  - indexes and table rights are as rebuilt; no table without row security; `make_owner` cannot be called from
    the pages;
  - WAL archiving is active with no failures (Supabase's own backups; whether they can be restored depends on the
    plan, E-10).
- **Drift is accepted, and the rehearsal checks it is left alone.** No migration touches `audit_menu`, its
  trigger, `menu_change` rows or `orders.note`, and none writes `menu_items`. This was checked with probe triggers
  across 0000–0025, and with `note` nullable and NOT NULL with a default, at either column position.
  - The cause is unknown: `audit_menu` has had one text in the repository since 2026-09-16, and the base tables
    were created before the repository kept SQL.
  - E-11 (the read-only catalog export) is now required. It does not block 0000–0025, but it blocks reconciling
    `audit_menu` and `orders.note`. If the exported body matches the repository's apart from spaces or comments
    (hashes `aa2499233cf7` / `559f340e7bbd`), it is accepted as is. Otherwise a new expand migration decides
    which logic stays, and whether IVA-code and CABYS changes in the Menu Manager are logged; with the
    repository's body they are not.
  - `orders.note` is kept untouched; dropping or changing it needs the owner. Staging copies set it to its default.
- **Menu categories (S-3) were never open in production.** The legacy "categories color for signed-in" rule is
  absent there (only the owner rule exists). 0001 still drops it where it exists, and the rehearsal keeps covering
  that case.
- **Logins.** There are three logins, all of the owner kind and none with a phone code; every login has an app
  account, so nobody has signed themselves up. One has never signed in.
  - Tested: an owner-kind login without a phone code behaves like a café login until a PIN is typed, on today's
    schema and after 0025.
  - It still carries three exposures on a café device:
    - anyone holding the session or the password can turn on a phone code and become the full owner;
    - with no active owner-role team member, a manager PIN can create one;
    - the 30-minute idle sign-out and "Sign out everywhere".
  - Supabase Auth deletes every session of a login that has no code each time that login's code is typed
    (auth `mfa.go`, `InvalidateSessionsWithAALLessThan`). A phone code on a login shared with café devices
    therefore signs the POS and kitchen out.
  - **Decision:**
    - café devices move to a café-kind login (`supabase/tools/cafe-login.sql`, one row, audited, works before
      0000) before the new pages are published;
    - the phone code goes only on the owner's personal login, used by no café device;
    - a grant on a mailbox that is not the owner's is revoked by the same tool (audited; `auth.users` is never
      touched).
  - Both pages that offer the phone code now warn about this and ask to confirm first.
  - Tightening who may enroll (Security card only at owner level, and 0026: `manager_save_staff`'s first-owner
    exception requires `owner_with_code()`) waits until the owner's own code is verified or an active owner-role
    team member exists. Otherwise the owner could be locked out of enrolling.
  - Correction to earlier notes: after 0025, `pay_period_save` needs `acct.can_read` (the phone code), not only
    an owner PIN.
- **Storage stays strict.** 0015 and 0025 create storage rules as the SQL Editor's account; there is no fallback.
  - Production's account is not the storage owner and needs Supabase's supautils `policy_grants` for this. Every
    Supabase configuration since 2024-06 lists `storage.objects` and `storage.buckets` for it; the legacy scripts
    already created rules there; storage-api grants it ALL on both tables.
  - If it still failed, that file applies nothing, and the window stops at 0014, where the live pages were tested
    working (docs/MIGRACIONES.md).
  - The follow-up query and the snapshot now show these rights. `release-check.sql` checks the expense-receipt
    bucket, its rules and the current upload rule.
  - A lint guard refuses any other storage DDL in a migration, which the local rehearsal could not catch.
  - The staging reset sets `storage.allow_delete_query` (storage-api 0055 forbids direct deletes otherwise).

## D-028 · 2026-10-13 · The staging copy carries no personal text, and stops on a column it does not know
- **Decision:** `anonimizar.sql` classifies every text, json, binary and network column of `public`, `canopy` and
  `acct`: today's legacy schema with production's `orders.note`, and after 0025. Each column is one of:
  - **replaced:** people and suppliers, "who did it", device names → `Aparato N`, free text → `texto`, the e-invoice
    receiver, bank last digits, invoice file names, who confirmed each payroll rule;
  - **regenerated:** order-tracking links, room QR codes, bank-line hashes;
  - **emptied:** logins, unlock tokens;
  - **kept as business data:** menu, stock, chart of accounts, settings, codes and statuses.

  A column in no list stops the script before anything changes. It runs only where its account is a superuser, so
  never on Supabase. Visitor questions keep their language and answer code only when they look like codes. The
  rehearsal runs it on the migrated copy, so a migration that adds an unclassified column fails CI.
- **Evidence:** personal-looking text was seeded into every such column of a legacy copy and of a copy with every
  migration and every table filled.
  - Afterwards, a scan of every text, json and array column found none outside the kept business columns.
  - Amounts, quantities, dates and ids were identical in every table.
  - The whole pipeline into a staging-like database found none either.
- **`ensayo.sh`:**
  - reads production only with an account that cannot write;
  - refuses a malformed address before using it, because psql would quote it, password included; the password may
    hold letters, digits, `-._~!$&()*+,;=` or `%XX`;
  - checks the staging PIN first;
  - never anonymizes on Supabase, and deletes its dumps on any exit;
  - a failed restore prints no data row.

  The workflow's comparison step now fails the run (pipefail). The staging site's anon key is a secret, masked in
  the public log. Each staging copy arrives without logins, so `staging-logins.sql` runs after every copy, and after
  a quarterly restore test, which puts real data in staging.

## D-029 · 2026-10-13 · The first backup, checked against production
- **Blocking defect found and fixed:**
  - Supabase stores default rights for its own `supabase_admin` in `public`, and a dump of `public` carries them.
    The nightly restore test runs on a throw-away server that has no such role. On Supabase, postgres may not act
    for that role.
  - The first real backup would therefore have failed its restore test, and so would `restore.sh` and the staging
    copy.
  - Every restore (backup test, `restore.sh`, both steps of `ensayo.sh`) now keeps only `postgres`'s own default
    rights.
  - The backup pipeline test reproduces it: default rights held by a role that is gone when the backup is restored.
    `restore.sh` failed before the fix and passes after. The test also checks the list the nightly restore test
    restores (postgres's own default rights kept, the other role's dropped). The two `ensayo.sh` steps use the same
    filter line, enforced by lint check 9.
- **Restore stubs:** they now also have `uuid-ossp` in `extensions`, as production does.
- **Backup account password:** generated inside the database (a DO block, shown once). Supabase logs DDL
  (`log_statement = 'ddl'`), so a typed `ALTER ROLE … PASSWORD` would sit in clear in the project's logs; tested
  locally.
- **That password is owner-level:** `canopy_backup` reads everything, the `auth` schema included (refresh tokens).
  It lives only in the private repository's secret. Narrowing it needs a later contract migration.
  *Superseded by D-033: the account no longer reads `auth` or the database's passwords.*
- **Logins in the backup:** `auth.users` and `auth.identities` are in it as a separate file that the nightly test
  does not check. Phone codes and sessions are not. *Superseded by D-033: logins are no longer copied.*
- **Storage after a restore:** the `menu-photos` bucket and its rules are not in the dump. RESPALDOS has the SQL to
  recreate them, and to repoint photo addresses at a new project.
- **Run summary:** it lists what was verified.

## D-030 · 2026-10-13 · Separating the café devices' login from the owner's
- **Identify first (read-only):** `production-followup.sql` now starts with `set transaction read only`, so the
  database refuses any change inside it. It also shows, per login, its sessions by device kind and browser, its last
  use (Costa Rica time) and the PINs typed on it. It never shows an IP, the full device text, a session id or a
  token.
  - Masks keep a `+label`, and the creation date tells apart two logins whose masks look the same.
  - Studio sends a paste as one implicit transaction and shows the last result (postgres-meta source).
- **Recommended path:** `docs/INGRESOS.md`.
  - Case A (the login is used only by café devices): `cafe-login.sql` converts it in place. Nothing on the devices
    changes; tested on the live and the new pages, including a sale queued offline before the change.
  - Case B (the café devices use the owner's own login): the owner gets a new personal login (`+dueno`,
    `make_owner`), and the shared login becomes the café login in place. No device is touched, no café-device
    session ends, and no email is needed.
- **Why not switch devices to a new login:** it has to be done after closing, device by device. A password change
  ends that login's other sessions (`LogoutAllExceptMe`). Supabase's dashboard has no per-user sign-out, and «Cerrar
  sesión» does nothing offline.
- **Found by testing that path:** the new POS (not yet published) lost a sale rung on a login with no café grant.
  `pos_record_sale` answers `{ok:false, error:'no_account'}` with HTTP 200, and the page took that as saved. Fixed:
  the sale stays on the device, the queue window says why, and it goes in once the login is connected. The e2e test
  fails without the fix. The live pages already kept such a sale.
- **`cafe-login.sql`:** it now requires the follow-up's creation date next to the email and refuses, changing
  nothing, when the date is another login's. Without that check, typing the other look-alike email converted the
  wrong login. Its confirmations show the creation date and any `+label`.

## D-031 · 2026-10-13 · What the follow-up showed
- **Follow-up:** read-only `production-followup.sql`, run by the owner on 2026-10-13.
- **The café devices' login is identified: case B** (`docs/INGRESOS.md`). The café devices use an owner-kind login
  with no phone code. Manager PINs are typed on it, and its sessions are several Android tablets plus a Windows PC
  and a Mac that were in use while the owner ran the query. The owner's older owner-kind login has no sessions and
  no PINs. The never-used login still has none.
  - **Account structure decided by the owner (2026-10-13):** two owners, each with a personal login that no café
    device uses, and both stay owners: the owner's older owner-kind login and the co-owner's existing login. The
    shared login becomes the restricted café login in place (`cafe-login.sql` Part 1); the POS and tablets are for
    employees only, each with an individual staff profile and PIN. No device is touched and no café-device session
    ends.
  - **Order:** the verified backup first (E-03); then each owner's sign-in test in a private window, and each
    owner signs out of the shared login on their own computers and phones (the top «Cerrar sesión», which is
    local; never «en todos lados»); then the conversion, with the owner's approval. A new `+dueno` login is only the
    fallback for an owner who cannot sign in to their own.
  - **The never-used login:** the owner says the co-owner signs in with an existing login. If it is this one, it
    stays an owner and Part 2 of `cafe-login.sql` is never used on it; the follow-up shows a session on it once the
    co-owner has signed in (E-04).
  - **No owner-role team member exists** (2 managers, 1 inactive staff). Today a manager PIN on the café devices
    can create one, which is another reason to convert soon (E-05).
- **`audit_menu()` is accepted as is; no migration.** Production's body is `supabase/accounts.sql`'s without the
  inline comment after `return new;`. The proof is three hashes, all checked on a scratch copy built from the
  pasted definition:
  - `h` `4807ea7301cd`: the exact text, now known to the snapshot;
  - `h_ws` `1670eab5ce1f`: spaces normalized, still different, because the comment is still there;
  - `h_code` `559f340e7bbd`: comments removed, the same as the repository's.

  The trigger, `security definer`, `search_path` and owner are also the same, so its behaviour is identical.
  `tests/tools/snapshot-known.sh` lists the text under `ACCEPTED` (full md5, label `legacy`, date, reason), and the
  snapshot no longer reports it in `functions_changed`. Proven on scratch legacy builds with and without
  production's body: `functions_changed` `[]`, every function `legacy`. A body changed in code is still reported.
  The rehearsal now starts from production's text (`tests/rehearsal/production-drift.sql`), so CI checks on every
  run that the text stays accepted (BEFORE) and that no migration changes its text, settings or owner (compared
  right after the migrations).
- **`orders.note` is mirrored.** It is column 5 (`text`, nullable, no default, no constraint), and none of the 32
  orders has text in it. `tests/db/01_base_tables.sql` now has it, so production's `tables_columns_differ` is `{}`
  by construction (`orders` signature `219567007705…`, the one production computes). The rehearsal seeds a name and
  a phone in it, and checks that the staging copy carries none.
- **Triggers on the original tables:** identical to the legacy build's 12.
- **Storage rights confirmed:** `postgres` can insert buckets, is not a member of the storage owner, and has
  `policy_grants` on `storage.objects`; the privileged role is `supabase_privileged_role`. 0015's and 0025's storage
  statements will run.

## D-032 · 2026-10-13 · A new employee on today's pages; "who rings each sale" waits for the window
- **Proven on the live pages** (gh-pages `8950054` in a browser, against a copy shaped like production: no
  migration, managers but no owner-role staff, every login owner kind without a phone code; again after
  `cafe-login.sql` Part 1): a manager creates the profile and PIN with their own PIN (Time clock → Hours and team →
  Team), and the person clocks in and out with that PIN. No login can add a person without a manager's PIN today,
  the owners' personal logins included (owner level needs the phone code). The conversion changes none of this.
- **Today a sale records the device, not the person** (`orders.station`, free text per device). Per-person
  attribution is migration 0008 with the new pages: the earliest is the full window (0003-0025; a 0000-0008-only
  window breaks the register's dollar float and dollar close), and switching it on needs the owner's phone code
  (E-06). It is not reachable by 2026-10-15 without skipping a safety step, so it waits. It must not be switched on
  while the old POS is live: every old-POS sale would be flagged `no_operator`.
- **Interim (no migration, no publish):** `docs/PERSONAL-NUEVO.md`, the staff guide, and
  `supabase/tools/ventas-por-turno.sql`, a read-only report of each sale with who was clocked in. Optionally, one
  cashier per device per shift with the device named after them (the owner decides, E-21).
- **Risks found and kept in view:** on today's owner-kind login a manager PIN can create an owner (the café-login
  conversion closes it on café devices; the guide says «Miembro del equipo» only); PINs are not checked for
  uniqueness; an owner page left open in another tab of the POS browser signs the POS out after 30 idle minutes
  until the conversion.
- **0008 follow-ups (before the window):** a pay-later bill closed in one payment keeps who rang it, not who took the
  money; no page lists sales by cashier; «Terminar mi turno» does not clock out (the guide says so).

## D-033 · 2026-10-13 · The backup account reads the business, not the logins
- **Found in review, before the first paste:** version 1 of `supabase/tools/backup-account.sql` (and migration 0002)
  gave `canopy_backup` `pg_read_all_data`. On a test copy the account read every `auth` table (refresh tokens,
  sessions, pending recovery and magic-link token hashes, MFA secrets) and every role's password hash
  (`pg_authid`). Supabase Auth accepts a refresh token or a stored token hash to start a session
  (supabase/auth `internal/api/token_refresh.go`, `verify.go`), so a leaked backup password could have signed in as
  the owner, Jorge or the café login (all owner kind, none with a phone code). The backup needs none of it.
- **Version 2 (one paste, all or nothing):**
  - BYPASSRLS stays: it is required. Without it `pg_dump` stops on row security, and with
    `--enable-row-security` it silently dumps 0 of 14 534 orders. It grants no access by itself.
  - SELECT on the café's base tables and sequences (`public`; `canopy` and `acct` once they exist), USAGE on
    `storage` and SELECT on `storage.objects` (the photo list). No membership, nothing in `auth`, not
    `storage.buckets`. Today that is 1 role (no login, no password) and 30 grants. The account's dump of `public` is
    byte-identical to a superuser's.
  - If a version 1 account exists, it takes `pg_read_all_data` away. After 0002 it also grants `backup_report` and
    the default SELECT privileges, so an account made again after a rollback reads the tables later migrations add.
  - It ends with a self-check and raises (nothing is kept) if the account could write, create, run an owner-rights
    function other than `canopy.backup_report` (by name, a trigger function included, or through an aggregate,
    operator, cast or view), belong to a role, own an object, read `auth`, a view on it at any depth or
    `pg_authid.rolpassword`, read through a view of the café something it cannot read itself (system catalogs found
    by name: they are never in `pg_depend`), read anything else PUBLIC cannot, hold an unexpected grant, or lacks
    anything the backup copies; also if a secret-like setting that can hold text and is not empty is visible to every
    login (a database or account setting no extension defines is text, so it is always judged; a switch, number or
    list choice is not, unless its stored value is not a valid one:
    the owner's first paste, 2026-10-13, stopped on Supabase's `pgtle.enable_password_check`, pg_tle's on/off
    setting, and nothing was kept; the backup pipeline test covers both sides). A view of the café is an
    expected grant (0002's default privileges give it one). The result row says `lista` only when that block
    finished (`REVISAR` under `psql -f` after an error).
  - Re-run it after each migration window as a check.
  - It touches no login, no `app_accounts` row and no device: the owner and Jorge stay owners.
  - Its one change outside the account: it takes PUBLIC's EXECUTE on the café's owner-rights trigger functions
    (3 today: `audit_menu()`, `_order_discount_check()`, `_order_tab_voided()`; `authenticated` keeps its named
    grant). PostgreSQL checks EXECUTE only when a trigger is created, never when it fires, so the café's triggers
    work as before. With it, any SQL login (this account included) could attach one to a temporary table of its own
    and run it with its owner's rights: in review, through `_order_tab_voided()` the account raised an open bill's
    total from 13 500 to 1 013 500 and cleared its parts, and through `audit_menu()` it wrote an `audit_log` row
    under a name it chose, while direct writes were denied. The rollback does not give the permission back.
- **Migrations (not applied in production yet, so changed in place):** 0002 no longer grants `pg_read_all_data`
  (production's postgres holds it with admin, so the old 0002 would have widened the account again): SELECT on what
  exists plus default privileges in `public` and `canopy`, and its rollback line points to the rollback tool. 0013
  does the same for `acct` and revokes PUBLIC EXECUTE on `acct.actor()` and `acct.can_read()`: both run with their
  owner's rights, and any SQL login can fake the app's login claims. 0025 revokes PUBLIC EXECUTE on every
  owner-rights trigger function in `public`, `canopy` and `acct` it owns (24 after 0025, 13 of them open to every
  login without it; the ones 0003-0024 add are also closed by re-running the paste after each window).
- **Rollback:** `supabase/tools/backup-account-rollback.sql`: no login and no password, ends the account's
  sessions, revokes every grant, membership and default privilege, then drops the role. It never uses DROP OWNED or
  CASCADE and keeps `canopy.backup_runs` and `backup_status()`. `drop role canopy_backup` alone fails once the
  account has grants and leaves open sessions running. When the account is already gone it still ends sessions a
  deleted account left open, found without `backend_type` (the SQL Editor's account, not a superuser, sees it empty
  on another account's sessions), and says `REVISAR`, not `listo`, while any remain. Order: disable both workflows,
  paste it, delete `CANOPY_DB_URL`; never delete an encrypted copy or the age keys.
- **Logins are not copied:** `backup.sh` no longer dumps `auth.users` and `auth.identities`; `restore.sh --auth`
  only says they are created by hand (RESPALDOS → Cuentas de acceso: both owners with `make_owner`, the café login
  with `cafe-login.sql`, in the new project only; today's café login is never touched). Staff PINs are in
  `public.staff` and travel. `backup.sh` warns (`aviso`, the run goes on) if the account can still read the logins
  (`pg_read_all_data`, or USAGE on `auth` and SELECT on `auth.users`).
- **Fixed in the same review:**
  - Collation: the row and rights fingerprints now sort with `collate "C"` (`backup.sh`, `restore.sh`, `ensayo.sh`).
    A restore database that sorts like glibc `en_US` failed with `public.audit_log, public.stock_moves`.
  - The archive describes the dump: when the nightly restore test ran, its row counts and fingerprints are the ones
    measured on the restored dump, for every table. Before, a table written to during the copy carried the count
    after the copy, and `restore.sh` failed on that backup.
  - `restore.sh` keeps the photos in `fotos-restauradas-<fecha>` next to the archive (its temporary folder, where it
    said they were, was deleted on exit). That folder is not encrypted and may hold expense receipts: `restore.sh`
    says so, and the drill and disaster steps say to delete it (otherwise it could go to the monthly USB copy).
  - Step 3.4 (the password): the block refuses, changing nothing, when `pg_stat_statements.track = all` (nested
    statements are then recorded, the one with the password included; measured in review) or when `pgaudit.log`
    covers roles. The owner copies the message into the chat and changes no setting.
- **What the account can still do:** read all business data (sales, staff and their PIN hashes, guest phones), and
  what every login can: temporary objects and large objects (disk space), NOTIFY, advisory locks while connected,
  change its own password or settings. After 0002 it can record a fake "ok" run, so the Home tile is what the backup
  says about itself; the proof is the GitHub run summary or the owner's own restore.
- **Rejected:** keeping `pg_read_all_data` (Supabase's troubleshooting recipe); copying `auth.users` through a column
  or table grant (pending recovery and magic-link token hashes are live credentials); `default_transaction_read_only`
  (`BEGIN READ WRITE` undoes it and it breaks `backup_report`); `statement_timeout` (`pg_dump` resets it);
  `CONNECTION LIMIT` (the pooler can make a legitimate run fail); `VALID UNTIL` (optional later: a forgotten renewal
  silently stops the backups); Supabase's own backups as the off-site copy (Free has none; Pro's are physical, not
  downloadable, without Storage files, restored in place).
- **Tests:** 030 (22 assertions; 6 fail on the old migrations; the trigger-function one fails without 0025's
  revoke). Backup pipeline: the paste refuses an owner-rights function and a trigger function given to the account
  by name, leaves no grant and changes no function's rights, closes the café's trigger functions to every login
  (not to `authenticated`), its row says `REVISAR` under `psql -f`, the archive holds no `auth` file, the restore
  goes into an ICU `en-US` database, a sale saved during the copy; each case fails on the old code. Rehearsal: the
  paste as the non-superuser editor before 0000 (`lista`), the backup after 0025 (58 tables), the staging copy.
  Lint, by whole statement (comments removed, lines joined): no grant of `pg_read_all_data` in migrations or tools,
  no `pg_dump` or `copy` of `auth` in `ops/backup`; the three rights fingerprints identical. Scratch (not in CI): the
  account's temporary-table trigger attack fails after the paste and the café's trigger still fires; a view on a
  view on `auth`, a café view on `storage.buckets`, `pg_authid` or `pg_statistic` are refused, a café view on its
  own tables or on `pg_roles` is accepted (all as the emulated non-superuser editor, with the review's 20 injected
  risks still refused and nothing changed); the rollback of an already-deleted account with a session left open
  says `REVISAR` without `pg_signal_backend` and `listo` with it. Shared local test servers: `tests/build-db.sh`
  takes `pg_read_all_data` away from the shared `canopy_backup` that older runs left.
- **Not proven:** the final version ran on PostgreSQL 16.13 (an earlier one on 17.6); Supabase's SQL Editor,
  supautils and the pooler were read in source, not emulated; ending sessions in the rollback needs postgres to
  hold `pg_signal_backend` (likely, not observed). If production's Storage has an owner-rights trigger function
  every login may run, the paste refuses and names it (nothing changed): the paste cannot take that right from a
  function Storage owns.
- **Addendum 2026-10-13 · step 3.4 reviewed; the password block ships as `supabase/tools/backup-password.sql`:**
  two independent reviews of the block that gives `canopy_backup` LOGIN and a database-generated password, measured
  on PostgreSQL 16 and 17.6 as a non-superuser editor with `log_statement = ddl` and `pg_stat_statements.track = top`
  (production's settings).
  - **The success path leaks nothing:** the password is in no server log line, not in `pg_stat_statements` (only
    the `DO` text and `select current_setting($1)`), not in Studio's saved query (text only), not in
    `pg_stat_activity`; the transaction-local `set_config` hand-off dies with the paste. `gen_random_uuid()` is core
    PostgreSQL fed by the OS CSPRNG: two UUIDs without dashes are 64 hexadecimal characters (digits 0-9 and letters
    a-f, about 244 random bits), not "números y letras"; nothing in it needs URL-encoding.
  - **Found and fixed:** if the inner `ALTER ROLE` fails (no ADMIN on the role, a missing role, a lock wait, any
    error) PL/pgSQL adds `CONTEXT: SQL statement "alter role … password '…'"`, which PostgreSQL writes to the server
    log (`log_min_error_statement = error`, the default) and postgres-meta returns in the error Studio shows. A
    `log_lock_waits` message or a `debug_print_*` dump during the nested statement carries the same CONTEXT line.
    The hardened block catches the exception and re-raises only `sqlstate` and `sqlerrm` (the value replaced if it
    appeared), refuses up front when the role does not exist, turns `debug_print_*` off and sets `lock_timeout` for
    the paste to less than `deadlock_timeout` (100 ms under it, at most 900 ms, never 0: with `log_lock_waits` on the
    server logs a wait that reaches `deadlock_timeout`, with the same CONTEXT line; a fixed 900 ms leaked it when
    `deadlock_timeout` was 200 ms. Both are superuser settings; Supabase's defaults are off and 1 s), and stores the
    password with `password_encryption = scram-sha-256` (Supavisor rejects an MD5 secret). Measured: the failure
    without ADMIN with `debug_print_parse` on, and a 4 s row lock on `pg_authid`, write 0 hex strings (the original
    block: 2 and 3); the row lock with `log_lock_waits` on and `deadlock_timeout` 200 ms: 0 (the fixed 900 ms: 1).
  - **Refusals kept and widened:** `pg_stat_statements.track = all` stores the nested statement verbatim on 16 and
    17 (the refusal is necessary); pgaudit itself redacts everything after `password` and classifies `ALTER ROLE`
    as ROLE, not DDL (measured with REL_16_STABLE), so the `all`/`role` refusal is belt and braces; also refused:
    `log_min_messages = debug*` (every DEBUG line would carry the CONTEXT) and a registered pg_tle `passcheck`
    function (`pgtle.enable_password_check` on with a row in `pgtle.feature_info`: the function receives the
    plaintext; pg_tle grants USAGE on `pgtle` and SELECT on that table to PUBLIC, so the check runs as postgres).
  - **Not one transaction:** if Studio ran the paste in parts (a selection), the `ALTER` committed, the cell came
    back empty and a password nobody saw was set. The row now says `REVISAR …` and the steps say to run it again
    whole (a partial run may also have set nothing, as when only the final `select` runs: the steps say "puede que",
    not that a password was set).
  - **Any ERROR changed nothing:** the paste is one transaction and the `DO` block is atomic even statement by
    statement, so the steps say so for every ERROR, not only those starting with `NO SE CAMBIÓ NADA` (a `pgtle`
    schema the editor cannot use makes 1b raise `permission denied for schema pgtle`, nothing changed; pg_tle grants
    USAGE to PUBLIC, so this is theoretical and the tool keeps failing closed there).
  - **Rotation:** Supavisor caches a role's secret for about a day and refreshes it on a wrong-password attempt,
    and an upstream connection already open survives a password change. A suspicious password is handled with the
    rollback (ends the sessions, drops the account), then step 2 and the password tool again.
  - **Shipped:** `supabase/tools/backup-password.sql` (the reviewed block verbatim under a Spanish header: what it
    changes, what it refuses, the expected row, ERROR and REVISAR, clipboard hygiene) and
    `supabase/tools/backup-account-check.sql` (read-only, `set transaction read only` first: the account's
    attributes and memberships, what it reads and what it must not, the logging settings the password tool looks
    at plus `log_lock_waits` and `deadlock_timeout` as information; names only; before and after the password the only difference is `can_login false → true`; works before
    0000, after 0025 and with the account absent, and needs no USAGE on `storage` or `pgtle`, its lookups go through
    the catalogs). RESPALDOS 3.4 points to the tool; CHECKLIST and DEPENDENCIES updated.
  - **Tests:** backup pipeline, the tool sent as one query string like Studio: refused with a placeholder
    `pgaudit.log = role` and `rolcanlogin`/`rolpassword` unchanged; a 64-hex row whose SCRAM verifier is checked in
    Python (RFC 7677) and that logs in, with every other attribute unchanged; a second run replaces it (the first no
    longer matches, and no longer logs in where the server checks passwords); `REVISAR` under `psql -f`; a
    CREATEROLE editor without ADMIN gets `no se pudo poner la contraseña` with no 64-hex string in the error (the
    block without its handler fails this case with the CONTEXT line; the original block fails the `REVISAR` case);
    another session holding the account's `pg_authid` row with `log_lock_waits` on and `deadlock_timeout` 200 ms:
    refused with `55P03` in about 100 ms, no 64-hex string in the error (the fixed 900 ms writes one to the server
    log); no 64-hex string added to a local server's log; the check's JSON as the superuser and as that editor (26 tables
    readable, 0 writable, 0 in `auth`, `rolpassword` false, the photo list, 0 memberships) and after the migrations
    (every table, `backup_report`). Scratch: both tools as the non-superuser editor on a production-like legacy copy
    with 14 534 orders (`lista`; the check before; the 64-hex row; the check after differing only in `can_login`; a
    login with it reads the orders and is denied an insert, `auth` and `pg_authid`; the ERROR, REVISAR and failure
    cases; the account absent; after 0025: 58/58 tables).
  - **Not proven:** Supabase Studio itself (`psql -c` emulates its single-string paste; postgres-meta read in
    source), its result persistence and the platform's logging of response bodies; the pooler's cache in practice;
    pgaudit measured on 16 only; production's settings (the tool refuses or neutralises each one it depends on).

## D-034 · 2026-10-14 · The first backup run logged in as postgres: the secret is checked before connecting
- **What happened (2026-10-13 22:45 UTC, `canopy-respaldos` run 38479782418):** the first manual "Respaldo nocturno"
  stopped at its first connection with `FATAL: password authentication failed for user "postgres"` from
  `aws-0-us-east-2.pooler.supabase.com:5432`. Nothing was copied, uploaded or recorded; the café was not affected.
- **Cause: the `CANOPY_DB_URL` secret kept Supabase's default user `postgres.<ref>`** instead of
  `canopy_backup.<ref>` (RESPALDOS 3.4, point 2). Evidence: the private repository's 7 files are byte-identical to
  the tested copies; `respaldo.yml` passes the secret unchanged and `backup.sh` hands it to `psql` as is (no `PGUSER`,
  no rewriting; a user in the URI wins over `PGUSER` in libpq). Supavisor splits the startup user at the last dot and
  names the parsed role in that error (`WrongPasswordError`, `user: context.db_user`), so the role sent was exactly
  `postgres`; a bare `postgres` or an unknown project would have given a tenant error, and `canopy_backup` with a
  wrong password would have named `canopy_backup`. The password in the secret was not postgres's (it failed). The
  `***` over the restore-test address in the log is GitHub's automatic connection-string redaction and says nothing
  about the secret. A GitHub secret cannot be read back, so the fix is a whole new value, with the password.
- **Decision:** `backup.sh` now checks both secrets before any connection and stops with a message that names the
  wrong part (the owner's `postgres` account, brackets left, the transaction port 6543, the direct IPv6 host, a
  missing project or `sslmode`, another project than `SUPABASE_URL`, a password that is not the 64-hex one, a space
  or line break, a private age key) without printing anything taken from a secret (GitHub hides only a whole secret).
  After connecting it requires `current_user = canopy_backup`. A refused or failed login is no longer tried a second
  time just to record the failure. New workflow "Comprobar la conexión (sin respaldo)" (`comprobar-conexion.yml`,
  `BACKUP_CHECK_ONLY=1`) logs in, checks the account's rights and stops: the owner verifies a corrected secret
  without running a backup. From the independent review: a parameter after the `?` (libpq lets `?user=` replace the
  account written before it) is refused, only `sslmode` may follow; the host is compared in lower case; a refused
  first connection puts the server's answer, without the password, into the step line the summary shows, with
  what to do (a wrong `canopy_backup` password, an account that cannot log in, a wrong project, the pooler's
  temporary block); the check records nothing even when it fails between the login and its own checks; the
  messages avoid `<…>` placeholders, which GitHub's summary drops as HTML tags.
- **Proof:** backup pipeline test (19 wrong secrets refused with the right message, no connection attempt and no
  value shown; the right one passes; the connection check verifies the account and copies and records nothing; an
  account with a write grant, and a role switched in through the connection options, are refused); each fails on
  the previous `backup.sh`; actionlint and lint check 12 on the new workflow.
- **Not proven:** the run against production itself (it waits for the owner's corrected secret and go-ahead).

## D-035 · 2026-10-14 · Costa Rican payroll: the arithmetic is built, the law is entered and confirmed
- **Decision:** migration 0026 separates what is arithmetic from what the law sets. Arithmetic always runs: hours × rate,
  gross + extra pay, a percentage of the pay, salaries ÷ 12, averages over the posted payrolls. What the law sets
  (the CCSS and INS percentages, the income-tax brackets and credits, the vacation days per month, the notice and
  severance table) is never assumed: the accountant enters each with their name and the document, and the owner
  records the confirmation `payroll_cr_rules` in Home → Settings. Until then nothing is withheld, provisioned or
  posted, and every aguinaldo, vacation and settlement figure is labelled an estimate that is not confirmed.
- **What is built (all OFF):** rule categories `ccss | ins | other` (the INS policy posts apart, 6105 against 2133;
  CCSS stays 6102/2131); `staff_profile` (ID number, hire and end dates, contract, children, spouse) for the tax
  credits, the CCSS report and the balances; `payroll_params` (`renta`, `vacation`, `severance`), saved only with a
  confirmation, the last two seeded with the text of the law and `confirmed_by = null`; income-tax withholding to 2140
  behind the setting `payroll_renta_withhold`, with the monthly table taken to the period (pay × 30 ÷ days, taxed,
  tax × days ÷ 30: the usual employer practice, flagged on the line and to be confirmed); the aguinaldo provision
  (1/12 of the pay, 6103 against 2150) behind `payroll_accrue_aguinaldo`; extra pay per line under the same rules;
  the payslip in Spanish, printed from the page; the aguinaldo run (salaries posted from 1 December to 30 November
  over twelve; prepared, reviewed by the accountant, posted for what the provisions did not cover, paid); vacation
  records with voids by reason, the balance from the hire date (or the first payroll or punch) and the average daily
  pay of the last 50 weeks of posted payrolls; the settlement estimate by reason (notice and severance only in a
  dismissal without cause, proportional aguinaldo and unused vacations always); the month for the CCSS and the INS
  by person and by rule, with the people without an ID number flagged.
- **Why this shape:** the directive forbids activating unverified payroll rules; the accountant needs the inputs
  the CCSS and INS forms ask for (salary, days, hours, ID number) and a payslip the staff can keep; the business
  needs the aguinaldo and vacation liabilities visible before December. Filing files are not produced: the CCSS and
  INS portals take the figures by hand, and a file format guessed today would be wrong in a way the owner could not
  see.
- **From the independent review (fixed before the commit):** the log of a profile change names the fields that
  changed and the hire and end dates, never the ID number, the family or the notes (any manager with a PIN reads the
  café log); a vacation record's note stays out of the log too; `NaN` and infinity are refused in the tables and the
  new money columns carry the 0025 finite check; the extra pay and another deduction are logged with before and
  after and lock the run against a review happening at the same time; a draft prepared before the settings, the
  confirmation or the tax table changed is prepared again before the review (`prepare_again`); extra pay and other
  deductions typed on a draft survive a new preparation; a profile sent with one field changes only that field; a
  period of 28 to 31 days is a month for the tax table (only a shorter period is taken to a month); the aguinaldo is
  posted before 30 November only with a written reason kept on the run, never while a period of the year has no
  posted payroll, and a run posted early leaves the rest to a later complementary run that discounts what was paid.
- **Proof:** `tests/sql/290_payroll_cr.test.sql` (143 assertions: categories, the profile and its log, the table
  validation with NaN and infinity, the withholding off → no table → on, the prorated tax and the calendar month,
  extra pay and its log, a stale draft, extras kept on re-prepare, the split entry, the payslip, the month, the
  aguinaldo run blocked without the confirmation and without a reason before 30 November, nothing left after it,
  vacations, the settlement by reason, the CCSS floor, a pay-out without a reason, a settlement without a total);
  `tests/e2e/specs/260_payroll_cr.spec.js` (the accountant's screens, the
  owner's profile form, the review refused without a table); the 0022/0025 payroll test unchanged (44). The
  rehearsal checks that both settings arrive OFF and that the staging copy anonymizes the ID numbers.
- **From the second review of 0026 (fixed the same day, before the push):** the CCSS contribution has a minimum base:
  the accountant enters it (`payroll_params` key `ccss`, `min_base_crc`, with their name and the document) and each
  CCSS line is computed on the greater of the pay and the minimum taken to the period's days (× days ÷ 30, 30 days or
  more is the full base); the line keeps the base and whether the floor applied, the month's report counts the lines
  at the floor, and without the parameter nothing is floored; the review of a draft prepared before the settings
  changed asks for a new preparation before it complains about a missing tax table; the aguinaldo lines and the
  month's report group by the person and not by the name (a renamed person or a renamed rule no longer appears
  twice) and show the current name; the severance bands follow the law's wording (three to six months, six months to
  a year, by years with the fraction of the year from the dates, not from the posted months); a settlement whose
  applicable amount cannot be computed (no posted payroll in the window) has no total instead of a short one, and the
  page prints a dash; the settlement's proportional aguinaldo comes from the same window and runs as the aguinaldo
  itself; paying vacation days instead of giving them is the exception of Código de Trabajo art. 156 and needs a
  written reason; the aguinaldo card opens on the current year. Overtime, paid holidays (feriados) and the minimum
  wage by occupation are not modelled: the hours come from the time clock at one rate, and a holiday worked is paid
  as extra pay typed by the manager; A-08 lists them for the accountant.
- **From the third review (the round-3 diff itself):** a period of 28 to 31 days takes the whole monthly minimum base,
  as the tax table already treats it as a month (a shorter or longer period takes its days over 30); a minimum base
  above someone's pay for the period (a few hours) makes the review answer `floor_over_pay` instead of a bare
  negative net, and the page says what to do: ask the accountant how a part-time worker is reported and, to prepare
  that payroll meanwhile, save the base as 0 (which means "no minimum base" and is shown as such, never as a
  confirmed base); an empty amount is refused on the page and on the server; the "CCSS minimum base" tag also appears
  when only the employer's rules were floored, and the payslip prints the base the CCSS contributions were taken on;
  at exactly one year of service the notice is fifteen days (art. 28: "up to a year") while the severance takes the
  table's first year (art. 29).
- **The worker's quota below the minimum base (the one finding that review confirmed after the fixes):** a worker is
  never deducted more than their own pay bears. By default the worker's CCSS quota is taken on the pay, and the quota
  on the difference up to the base is the business's own entry on the line ("diferencia asumida por el patrono",
  flagged, posted with the employer's charges to 6102/2131, shown on the payslip and in the month by rule), so the
  CCSS receives both quotas on the base and no net goes below zero. The accountant can choose the other reading in
  the same form ("deducted from the worker", `worker_share = on_base`); then a pay too small for the quota answers
  `floor_over_pay` and the page says what to do. A-08 item 7 asks the accountant which reading applies. Chosen
  because a wrong default costs the business a small amount it can deduct later, while the other wrong default takes
  money from a worker.
- **Not proven:** the real percentages, brackets, minimum base and tables (they come from the accountant, A-08); the
  prorating method against Hacienda's practice; a browser print of the payslip (checked by hand in a screenshot only).

## D-036 · 2026-10-14 · The three attribution gaps of D-032 are closed (migration 0027)
- **Decision:** (1) a bill paid later records who took the money in its own columns (`orders.paid_operator_*`), set by
  `tab_pay` from the session signed in on the device at the moment of the last payment, apart from who rang it; a part
  payment was already its own sale of whoever took it. With `operator_mode` on, a bill closed with nobody signed in is
  flagged `no_paid_operator`, and one closed under an unverified (offline) name `paid_operator_unverified`. (2) A trigger
  keeps both names as the server set them on any update from the till (the till has no update right on sales since
  0025; the trigger is the second lock). (3) `pos_operator_end(p_token, p_clock_out)` ends the device session and, when
  asked, closes the same person's open shift through the session (no second PIN: the session was opened with it); the
  old call with the token alone keeps working. The POS asks «¿Marcar también la salida en el reloj?» when a turn ends.
  (4) Sales → "Sales by cashier": the money by the person who took it.
- **Why:** the guide told staff that ending the turn did not clock out, the sales page could not show cashiers, and a
  bill closed by a different person was credited to whoever opened it: three things the owner asked for in the
  attribution work and that a payroll from approved hours makes matter.
- **Proof:** `tests/sql/300_operator_followups.test.sql` (19), `tests/e2e/specs/270_operator_followups.spec.js` (2:
  clock-in from the POS, end of turn with the clock-out accepted and declined, the sales card), the 0008 tests
  unchanged (27 and 5).
- **Not proven:** nothing changes on today's site until `operator_mode` is switched on after the window (E-06).

## D-037 · 2026-10-14 · The independent review of the whole build: what was fixed now, what waits for its wave
- **Method:** ten reviewers, one per area (POS, staff and payroll, inventory and suppliers, cash and bank, accounting,
  dashboard and insights, the tax rule, test coverage and scenarios, security and launch readiness, requirements
  against the documents), each reading the code and running the area's tests on a fresh build; their findings are
  kept in the session's review file and summarized here.
- **Fixed in migration 0028 and the pages (this commit):** the till can no longer record a sale with a negative
  total (the live menu holds a negative-priced "combo discount" item: the POS hides negative prices from the grid and
  refuses a negative ticket; the discount feature is the way to discount); an unknown payment method or status from an
  older page is flagged, never refused; a room order paid at the window on a later day moves to that day like a bill
  does, so the register and the books count it once; Cash by day and the ledger's pending days list the days that had
  sales but no register; the journal reverses only manual and opening entries (a document is undone from its own
  screen, so document and ledger never separate); posting a range of days answers `period_closed`; only an asset
  account can be marked cash; a record-only e-document follows a bill cancelled by status; labor cost no longer counts
  an old hourly rate after a switch to a fixed pay; a PIN already used by an active person is refused; the owner role
  is given or taken only by the owner with the phone code (the first-owner exception on a login without a code, kept
  open in D-027 for today's shared login, is closed: the café devices get their own login first, E-05, and the owner
  enrols the code, E-06); visitors' questions are capped (500 characters, 20 per visit per hour); the accountant
  reaches Insights; the owner's Home no longer scrolls sideways on a phone; the Home revenue tiles come from the same
  figures as Insights; the Menu Manager in tax-exclusive mode keeps an untouched price and prices a new item correctly;
  the receipt in that mode prints before-IVA lines and the ticket's lines add up to its "Before IVA" row; a payroll
  with every line at zero is not reviewed; Home → Settings now shows the boolean switches (the two payroll ones with
  labels, so the `payroll_cr_rules` confirmation can be recorded there as the pages say); the page reverses a journal
  entry through `acct_journal_reverse` (manual and opening entries only) while the documents keep the unrestricted
  function the page can no longer call; books pages sign out when idle; CI runs once per commit.
- **Not fixed now, with its place:** before `ledger_auto_post` (A-07): walk-in receipts (`stock_receive`) owe the
  supplier in the books with no receipt row to invoice, and an invoice "without deliveries" may be posted to inventory
  or cost accounts (the accountant's choice of accounts is the control until then); before the 2027 books: year-end
  closing entries and a trial balance that foots across years; expenses on credit cannot be paid from their screen
  (a manual entry settles them); the Sales and Home pages group by the sale's clock time while Insights and the books
  use the business day (after-midnight sales); the Inventory page's stock value is at the last price while the books
  value at average cost; reprints of a bill paid in parts print the last part's total; the static `/menu` pages carry
  typed prices; dollar bank accounts and exchange differences (A-06); fixed assets, budgets, recurring entries; a
  general ledger with running balances; a read-only accountant; the 10 % service charge (A-05); tips; order notes and
  modifiers; change given in dollars; a second location's registers and stock.
- **Proof:** `tests/sql/310_review_fixes.test.sql` (37), the 260 test updated for the owner role, e2e 130 and the new
  135 (Menu Manager in exclusive mode), the whole suite green; the known-functions inventory refreshed.

## D-038 · 2026-10-14 · One coordinated release with a one-time operational reset of the test period
- **Decision:** the owner chose one production release instead of waves: before migration 0000, a one-time operational
  reset clears the test period's transactions from the legacy database (`supabase/tools/reinicio-operativo.sql`, pasted
  whole in the SQL Editor by the owner, in the launch window, only after a verified encrypted backup and after saving
  the accountant's summary); then 0000–0028, the café login (E-05), the owners' phone codes (E-06) and the approved tag
  follow in the same window. Inventory starts at zero (the owner's clarification: the quantities of the testing period
  are not carried forward; the real stock is entered after a physical count the morning after; products, recipes,
  costs, suppliers and the inventory configuration are kept). Regulated features stay OFF (`price_mode` inclusive,
  `ledger_auto_post` false, `einvoice_mode` off, `operator_mode` off, the payroll settings false, no compliance
  confirmation). The owner approved the preparation only; nothing in production has been touched.
- **What is built:** the reset is one transaction (two `pg_temp` functions and a final `select`). It refuses, changing
  nothing, when `canopy.migrations` exists (a migrated database), when the log already has a `reinicio_operativo` row
  (done once), when the backup reference is blank or the placeholder, when the confirmation word is not exactly
  `BORRAR PRUEBAS`, when any sale is younger than 60 minutes (or dated in the future by a device's clock), when anyone
  punched the time clock in the last 60 minutes, or when a register day is open (the café is still working),
  when a preserved table's fingerprint would change, when a cleared table is not empty afterwards or a stock item is
  not at zero. It clears `order_part_lines`, `tab_adds`, `order_items`, `orders`, `discount_approvals`,
  `register_days`, `time_entries`, `stock_moves`, `purchase_lines`, `purchase_orders`, `access_unlocks`,
  `sales_unlocks`, `inventory_unlocks` and `chat_questions`, sets `stock_items.on_hand` to 0 and clears the PIN
  lockouts of the test period (`staff.failed_pins`, `locked_until`; the PINs do not change). It locks the tables
  visitors and devices write to for the seconds it runs, so a sale, a question or a punch arriving then waits and lands
  in the clean café, and a second copy of the paste running at the same time waits and then refuses. It preserves
  byte-identical `menu_categories`, `menu_items`, `recipes`, `stock_items` (every column but `on_hand` and
  `updated_at`), `vendors`, `staff` (but the two lockout columns), `app_accounts`, `app_settings`, `board_settings`,
  `board_group_slides`, `rooms`, `auth.users` and `audit_log`, and appends one audit row (`reinicio_operativo`, by
  `SQL Editor`) with the counts per table, the period's dates, the md5 of the summary, the preserved fingerprints and
  the backup reference; the figures themselves go only to the returned text cell, which the owner saves with the
  backup (the café log is readable by every manager). After the window, a sale a tablet kept offline from before the
  reset is recorded and flagged `before_reset` by the till guard of 0028 (counted by the consistency check as
  `orders_before_reset`) for the manager to void: the runbook requires no tablet with pending sales at the start.
  `supabase/tools/resumen-pruebas.sql` is the same summary, read-only and pretty-printed (counts and totals by day and
  by payment method, voids, discounts, bill parts, room orders, register days and cash differences, shifts and hours,
  purchases and valued stock; never a name, a note or a phone): the owner saves it with the backup before the reset,
  for the accountant; its `huella` (md5 of the figures, visitors' questions left out) must equal the `resumen_md5` the
  reset writes in the log. After the independent review of the script (three lenses, 25 findings, 5 upheld after
  refutation): the money is counted the way the register closings count it (every paid, not-voided row: a bill paid
  whole, the last payment of a bill paid in parts, each earlier part by its own method, a give-back as its negative
  twin), the by-day and by-method figures come from that same set, and `cuadre_con_caja` shows the difference against
  the closed register days (0 on the rehearsal's 120 closed days) and the money of days without a closed register; the
  bills' count and discounts still come from the closed bills; a second paste running at the same moment waits on an
  advisory lock and is then refused, and a run that finds nothing to clear is refused (the café was already empty). The runbook is `docs/LANZAMIENTO-UNICO.md`
  (Spanish): the decision, what is kept and deleted, what is kept by legal duty, the preparation list, the 45-minute
  window minute by minute with every refusal message explained, the first day's operating test, the way back and the
  owner's eight approvals. `CLAUDE.md` records the one-time exception to "never delete business records";
  `docs/DEPENDENCIES.md` gets A-11 (the accountant's retention answer) and E-22 (the window and the count date).
- **Why:** the test period's records are not the café's business history: carrying them into the new books, insights
  and inventory would start every report from fictitious figures, and the first physical count would have to correct
  months of test movements. One window instead of waves leaves no period with a security fix pending (0025 depends on
  everything before it). The reset lives in the launch window, after a verified backup, because that backup is the
  archive of the deleted period; it runs only before 0000 because it was written and rehearsed for the legacy schema,
  not for the guards of the migrated one. The exception to the "never delete" rule is written down so that no later
  agent treats it as precedent: once, by the owner, in the window. Rejected: deleting from the migrated database (the
  new triggers and guards were not part of the rehearsal); keeping the test stock quantities (the owner's instruction
  is a physical count); a summary with names (the accountant needs figures, the backup keeps the detail).
- **Proof:** the rehearsal reset pass (`tests/run.sh rehearsal`, step 10, added with this decision by the rehearsal
  work: on a second copy of production-before-the-window, as the SQL Editor's non-superuser account, six refusals each
  change nothing; the real run as one query answers `reinicio hecho`; the cleared tables are empty, every stock at
  zero, the preserved fingerprints identical, exactly one log row whose summary equals `resumen-pruebas.sql` figure
  for figure; a second run refused; then 0000–0028 on that copy and `compare.py reset`),
  `tests/rehearsal/reset-pages.sh` (today's live pages and the new pages on the empty, migrated café), and the staging
  `reinicio` option (`ensayo.sh`,
  "Ensayo en pruebas" with `reinicio = si`, docs/PRUEBAS.md), which runs the same file on the anonymized copy of the
  real data before the window. On the seeded legacy copy the reset cleared 14 534 orders with every preserved
  fingerprint identical and the repeat refused.
- **Not proven:** the real production data (the reset has run only on seeded and anonymized copies; the owner's staging
  run with `reinicio = si` waits for E-13); the owner's own window; the accountant's answer on retention and on whether
  any test-period sale was real (A-11); whether the real shifts since 2026-10-15 need more than the backup and the
  manager's note of hours per person before the reset.
- **Addendum 2026-10-14 (night) · the reset ran on the real anonymized copy:** «Ensayo en pruebas» run #2 (D-039
  addendum): `reinicio hecho` on the copy of production (35 sales), the 13 preserved tables identical, 0000–0028 after
  it; the run stopped only in `compare.py`'s fixture-coverage check, fixed that night. The window still waits for the
  repeat on the fixed version (E-23), A-11 and E-22.

## D-039 · 2026-10-14 · No second Supabase project: the real-data rehearsal runs in a temporary database; the production project and site stay
- **Decision:** the owner's revision of D-038, the same evening: keep the existing Supabase production project (URL,
  project ref and the public `anon` key in `website/config.js` unchanged) and the existing GitHub Pages site
  (`hanginggardencafe.com`); create no other permanent Supabase project and migrate nothing to another database. E-13
  (staging project) and E-14 (staging site) are withdrawn. The one-time reset and migrations 0000–0028 run inside the
  production database in the launch window, after that night's backup; the first encrypted backup exists and the
  owner's recovery key decrypts it (E-03 done 2026-10-14). The rehearsal with the real data runs in a temporary
  PostgreSQL database inside the private repository's GitHub Actions job («Ensayo en pruebas» → destino =
  `desechable`, reinicio = `si`), which disappears with the job. Regulated features stay OFF; nothing in production
  changes and nothing is published without the owner's explicit approval. No new development phase was started.
- **What is built:** `docs/LANZAMIENTO-UNICO.md` rewritten for this plan: the decision (same project, same site, no
  second project); what is kept and cleared (unchanged); the two rehearsal layers (CI's synthetic realistic copy, steps
  1–10 of `tests/rehearsal/run.sh` including the reset pass and the pages on the empty café; the owner's one-button
  rehearsal on the real anonymized copy in the throwaway database, with what its summary must show) and the table of
  what local PostgreSQL verifies against what only Supabase can, each Supabase-only item with its mitigation in the
  window; the preparation list without the staging items, plus a preflight checklist for the night itself; the window
  in the fixed order backup → three cells → reset → snapshot → migrations → release check → café login → phone codes →
  publish → devices, with the refusal table; an explicit post-release verification (that night, the morning after
  with `orders_before_reset = 0`, the first day); the way back with no second project, the disaster restore named as
  the last resort the plan is designed never to need; seven approvals (the staging row removed, the decision and the
  first backup marked done). `docs/DEPENDENCIES.md`: E-03 DONE, E-13/E-14 WITHDRAWN, E-22 reworded; `docs/CHECKLIST.md`,
  `docs/PRODUCTION-READINESS.md` §2/§4/§8/§9/§10, `docs/HANDBACK.md` §11 and `docs/LANZAMIENTO.md` follow. The private
  workflow's `destino = desechable` default and `docs/PRUEBAS.md` are the other agent's work of the same evening.
- **Why:** the owner's experience with Project NORA: switching databases and environments is where the problems came
  from; one project, one site and one window remove that class of error (a page pointed at the wrong project, a copy
  mistaken for production, secrets and logins for two projects, a free-plan slot that pauses). For the database part a
  second project added nothing the throwaway database does not give: `ops/backup/restore-stub.sql` already makes an
  empty PostgreSQL look like a Supabase project (roles `anon`/`authenticated`/`service_role`, schemas `auth`,
  `storage`, `extensions`, the default privileges), `ensayo.sh` already anonymizes on the job's scratch server and
  loads into any empty PostgreSQL, and CI already proves exactly that path (`run.sh`'s `ensayo()` helper, twice, then
  with `REINICIO=si`). What a real staging project would have added (GoTrue, storage-api, PostgREST, the real SQL
  Editor account) is written down as Supabase-only and covered in the window by read-only checks (`release-check.sql`,
  `consistency-check.sql`, `version.json`) and by stop points where today's pages are known to work (0014, 0025), not
  by a second project. Rejected: a temporary Supabase project created only for the rehearsal (the switching the owner
  wants to avoid; its Auth and Storage would still not carry production's account history); a staging site (no base
  to point it at; the pages run in CI on the empty café and the owner sees them with the real data in the window and
  on the first day); loosening the one-release plan (D-038 stands).
- **Proof:** `tests/run.sh rehearsal` (CI, every push), unchanged by this decision: the synthetic realistic copy, the
  migrations as a non-superuser with Supabase-like roles, the staging copy through `ensayo.sh` into an empty local
  database (the throwaway destination), again emptied, again with `REINICIO=si`, the reset pass and
  `tests/rehearsal/reset-pages.sh`. The private workflow's `desechable` destination is verified locally by the other
  agent. What stays Supabase-only is listed in the runbook §3 with its mitigation: GoTrue (code enrolment signing out
  the login's other sessions, reset mail, the real device sessions), Storage internals (storage-api, supautils
  `policy_grants`; locally `rehearsal_storage_admin` allows more than production, so 0015/0025 are the residual risk;
  the follow-up query of 2026-10-13 confirmed `can_insert_buckets` and `policy_grants`), PostgREST version and cache
  reload (`notify pgrst` in all 29 migrations; the pages' version gate), the SQL Editor's execution model and timeout
  (each paste small; a failed paste applies nothing), `supabase_admin`'s default privileges (release check after 0028),
  Pages/CDN (`version.json`; old pages say "needs an update"), PostgreSQL 17.6 against 17 in CI and the job.
- **Not proven:** the real production data under the reset (the owner's throwaway run is still to be made, and it needs
  the re-uploaded private-repository files); the owner's own window; every Supabase-only item above, until the window
  itself; A-11 and E-22 (open). `docs/RESPALDOS.md`'s quarterly restore test still names the PRUEBAS project as its
  destination: it needs a temporary project or a local database instead (follow-up; not changed here).
- **Addendum 2026-10-14 (night) · the first real-data rehearsal and what it changed:** run #2 of «Ensayo en pruebas»
  (23:29 UTC; destino `desechable`, vaciar `no`, reinicio `si`; version `claude/hanging-garden-coffee-proposal-1m8zd4`
  at 9c5c5a8). The copy of production (35 sales, 85 lines, 3 register days, 5 shifts, 3 stock moves, 5 purchase orders,
  15 discount approvals, 15 visitor questions, 3 staff; the restored copy's rights identical to production's) was
  anonymized and loaded; "closing the café" in the copy changed nothing (no sale or punch of the last hour, no open
  register); the summary was saved; `reinicio-operativo.sql`, sent as is, answered `reinicio hecho` with
  `borrado: … order_items 85, order_part_lines 0, orders 35, … tab_adds 0, time_entries 5` and the 13 preserved names
  identical, in well under a second; 0000–0028 ran after it in under 2 s. The run went red only at `compare.py reset`:
  `DIFFERENCE: order_part_lines had nothing to clear in the rehearsal: 0:-`. **Diagnosis:** a test expectation, not a
  reset defect and not a defect of the copy. The check demanded rows before the reset in every cleared table but four,
  which is a coverage requirement for the seeded CI copy (so the rehearsal proves the clearing of each table), wrongly
  applied to production's history: the legacy `tab_pay` writes `order_part_lines` only when a bill is split by item,
  and no bill of the test period was; the dump cannot lose a table's rows (pg_dump copies whole tables or fails, the
  restore ran with `--exit-on-error`, the rights fingerprint matched production's) and `anonimizar.sql` empties only
  the logins and the three unlock tables. **Fix (this commit):** the coverage requirement is explicit, `compare.py …
  reset fixture`, used by run.sh step 10, where `seed-legacy.sql` now gives every one of the 14 cleared tables a row
  (yesterday's expired PIN unlocks in `access_unlocks`, `sales_unlocks`, `inventory_unlocks`; the open bill's add sent
  with its request id into `tab_adds`) and run.sh checks it before the reset: CI's coverage went from 10 of the 14
  tables to 14 of 14. The owner's run (and run.sh's own run of `ensayo.sh`) keeps every integrity check, the 14
  cleared tables empty afterwards, the 10 preserved identical, stock at zero, one log line, the migrations changing
  nothing; it still fails on a copy with nothing to clear at all (the reset's own guard) and now reports by name the
  tables with no rows in the copy of production and the three the anonymizer empties.
  `tests/rehearsal/compare-selftest.py` (run.sh step 10) runs ten crafted cases: the report line, the two kinds of
  empty table, the fixture coverage, and six differences that must still be caught. The independent review of this
  fix (four lenses, three refuters per finding) added: the comparison validates its arguments (a misspelled mode or
  flag stops with the usage instead of running the lenient branch), a snapshot without one of the 26 tables stops
  with that difference printed instead of a traceback, and run.sh's pre-reset row check dies on a failing psql
  instead of passing on empty output. `ensayo.sh`: the first-character
  check of each public SQL file is one awk call (the pipe into `head` printed `grep: write error: Broken pipe` for
  every file) and the notices of the anonymization scratch database are silenced (the migrations' own `NOTICE: … does
  not exist, skipping` lines remain: `drop … if exists` on a fresh copy; PGOPTIONS stays off the destination, which with
  `proyecto-pruebas` would be a Supabase pooler); `PRIV_SQL` and every refusal unchanged. **What the
  owner does (E-23):** upload `ensayo.sh` again (the comparison comes from the public repository at the chosen version)
  and repeat the rehearsal; for the data of 2026-10-14 the expected line is `reset: 14 tables cleared (9 had rows;
  order_part_lines, tab_adds: no rows in the copy of production, nothing to clear; access_unlocks, inventory_unlocks,
  sales_unlocks: unlock tokens, emptied by anonimizar.sql before the copy left the job), 10 kept byte for byte, 3 stock
  items at zero, N log lines (one new); then the migrations:` followed by the `unchanged: …` line. Nothing in production
  was touched by the run (read-only account) or by this fix.

## D-040 · 2026-10-15 · Launch night: the one coordinated release went live (reset, 0000–0028, v2026.10.14-1)
- **What happened (UTC; the night of 2026-10-14 in Monteverde):** the owner ran «Respaldo nocturno» #4 (02:50, restore
  test passed), then in the SQL Editor the three read-only cells, `reinicio-operativo.sql` (`reinicio hecho`), the
  snapshot after, 0000–0028 one by one and `release-check.sql` (no missing migrations, functions, RLS tables or Storage
  policies). The publish workflow showed no «Run workflow» button: GitHub offers manual dispatch only for workflows that
  exist on the default branch, and `claude/festive-galileo-0twc1p` had no `.github/workflows/` folder at all (GitHub
  listed "Publish website" only from the 2026-10-09 runs). With the owner's explicit approval (option 2, instead of
  merging PR #1 that night) `pages.yml`, byte-identical to the tag's file, was pushed there as `c1ffbf1`; the push ran
  nothing (the file triggers on manual dispatch only). The run from tag `v2026.10.14-1` (3c7e020) succeeded at 04:33 and
  `gh-pages` is `ab97d44`, "Publish website v2026.10.14-1 3c7e020…". Approvals 5 (café login conversion) and 6 (phone
  codes) were deferred by the owner: both Owner accounts and the café devices keep their logins and permissions.
- **Found on the way:** (1) the owner's notes held only the public keys `age1…`: `age-keygen` prints the public key on
  screen and writes the private line `AGE-SECRET-KEY-…` only into the file, which the guide said to keep in the
  password manager and to print; before the window the private keys were not found. The owner was given a search plan
  (the Terminal's folder, Spotlight by name and by content, the Trash, iCloud Drive's Recently Deleted, Time Machine,
  the printout, Notes' Recently Deleted; verification by `grep -c`, `age-keygen -y` and a decrypt to `/dev/null`, never
  showing the key) and a new-keys plan, and proceeded with backup #4; whether a private key exists is E-24, urgent:
  without one no backup is readable. (2) The CI tripwire `tests/tools/live-site-check.sh` refused the first real release
  message: `peaceiris/actions-gh-pages` appends the SHA of the commit the workflow ran from, which the pattern did not
  allow, so the next CI run would have gone red with "NOT published by an approved release". Fixed in this commit: the
  appended SHA is accepted only when it equals the release tag's commit (fetched by name); a hand-written message, a
  wrong SHA or a tag that does not exist still fail; the old format and the restore format (`· sitio-…`) still pass.
  Verified against the live `gh-pages` and with crafted messages.
- **First day (2026-10-15):** the nightly backup ran by itself for the first time on the live café: «Respaldo nocturno» #5
  at 13:24 UTC (schemas `acct`, `canopy`, `public`: 62 tables, 371 rows, content identical in all 62 after the restore,
  8 photos verified, 5.0 MB encrypted, kept 14 days as a run file; #4 before the reset held `public` only: 26 tables,
  401 rows). Its result reached `canopy.backup_runs` for the first time (0002 exists now; #4 had logged "no se pudo
  anotar el resultado", as expected before it), so the owner's Home card has data. GitHub started the run about five
  hours after the `17 8 * * *` cron (08:17 UTC), as it had on 2026-10-14 (#2 at 13:43 UTC): GitHub documents that
  scheduled runs are delayed at busy times. Harmless (the account only reads, the restore test uses a disposable
  database, and the copy then holds the whole previous day) and nothing to change; `docs/RESPALDOS.md` now says so.
  Every copy is still readable only with a private age key (E-24).
- **Still owed:** the physical count the morning of 2026-10-15 before opening (stock at zero until then), that morning's
  `release-check.sql` and `consistency-check.sql` (`orders_before_reset` = 0), E-24, A-11, approvals 5 and 6 another
  night, and a `docs/RESPALDOS.md` follow-up: store the whole key file and verify a decrypt from the stored copy before
  deleting the original.

## D-041 · 2026-10-15 · Receive a delivery with the supplier invoice and the payment (0029, 0030, the Orders tab)
- **Approved by the owner (2026-10-15)** on the audited proposal `docs/RECIBIR-PEDIDO.md`, with five decisions:
  payments are recorded by an authorized manager with their PIN; debit card and credit card are separate methods;
  invoices in colones or dollars, with the exchange rate typed and kept; the invoice can be photographed from any
  authorized phone or iPad; Hacienda's XML is accepted when available, never required. A delivery may stay with its
  invoice pending (not here yet) or to review (captured, not confirmed) without losing the goods received; nothing
  reaches the books, the IVA credit or the payables until the invoice is confirmed. The five order options and the
  page's design stay; no other module changed beyond the connections listed below.
- **What this commit adds.** *Migration 0029 (`recibir_pago`, adds only):* account `2160 Tarjeta de crédito por pagar`
  (a free code: 2120 is already «Anticipos de clientes» since 0013; the file refuses to run if 2160 exists with another name)
  and the mappings `from_card_debit` → 1110, `from_card_credit` → 2160 (the accountant confirms them before 0029 is applied: A-12);
  `supplier_payments.paid_from` accepts `card_debit` / `card_credit` and `supplier_payment_save` posts them;
  `supplier_invoices` gains `currency`, `fx_rate`, `net_fx`, `iva_fx` (a dollar invoice is valued in colones at the
  typed rate, 100–2000, and the books stay in colones); `purchase_receipts` gains `invoice_status`
  (pending / review / confirmed; existing receipts with an invoice are backfilled as confirmed), `invoice_draft`
  (what was captured, as data, never posted), `payout_id`, `settled_at`, `settled_by`; table
  `purchase_receipt_files`; functions `po_receive_and_settle` (the delivery plus the invoice and the payments in ONE
  transaction, keyed by the receipt id: a double tap or a retry never doubles anything; any refusal — register not
  open, wrong PIN, more paid than invoiced, a duplicate invoice — rolls the whole delivery back), `po_receipt_settle`
  (the invoice and payments of a delivery already saved; `pending` and `review` allow at most one cash payout from the
  register, documented later at confirmation), `po_receipt_pay` (more payments on a confirmed invoice),
  `po_history` and `po_pending`. Confirming reuses `supplier_invoice_save` (IVA to 1140, price variance to 5103,
  AP 2101) and `supplier_payment_save`; cash from the register reuses `register_cash_move` (a `payout` on the open
  register, PIN-checked), so the drawer count and the POS cash movements see it as before. *Migration 0030
  (`facturas_archivo`, optional, Storage):* private bucket `purchase-invoices` (3 files per delivery, 10 MB, image /
  PDF / XML, never replaced or deleted), rules for the owner with the phone code, the accountant and a café login with
  a live manager unlock (`_login_unlocked`: Storage never receives the PIN header), `purchase_doc_attach`. It is a
  separate file because it touches Storage's tables, which the SQL Editor account may not own: if it fails, everything
  of 0029 works except attaching the file. *Page:* `website/inventory.html` only — the receive window gains the
  «Factura y pago» section (status, photo / file / XML, read with correction, currency and rate, subtotal and IVA with
  the received cost and the difference, one or more payments, manager and PIN), a «Pendiente con proveedores» card
  (deliveries waiting for their invoice, open invoices with due dates, what is owed), «Detalles» on received orders
  (deliveries, invoice, payments, payout, files with a signed link, attach, register the invoice, record a payment) and
  a vendor / month search of received orders. `website/accounting.html` only labels the two card methods;
  `website/lang.js` gets the Spanish strings and lets a line with an English date go through the part-by-part rules.
  Reading: the XML exactly as data (the same reader as Contabilidad); a PDF with text through pdf.js and a photo
  through tesseract.js (Spanish), both loaded only when «Leer la factura» is tapped, from jsDelivr like supabase-js
  (lint rule 13 pins the versions); every read value is a suggestion the person checks and confirms.
- **Tests:** `320_receive_settle` (127), `330_purchase_docs` (32), `240_release_check` extended (0030 optional, bucket
  and rules), browser `290_receive` (5: a café device with a manager PIN reading the XML and paying from the register
  then by bank, a pending invoice registered later with a double tap, three refusals that save nothing, a dollar
  invoice with its photo shown from the history and the page's answer when the reader library cannot load, and the
  page without 0030); the
  rehearsal applies 0029 and 0030 after 0028 (`compare.py`: no optional migration missing, the upload rule current);
  `anonimizar.sql` knows the new columns (the draft's names and notes, the file paths); the nightly backup copies the
  new bucket (`PRIVATE_BUCKETS`) once the Storage keys of E-17 exist (until then no private bucket is copied: the
  invoice files are not backed up); `ensayo.sh` clears it in the staging copy.
- **Limits, stated:** the reader versions (`pdfjs-dist@3.11.174`, `tesseract.js@5.1.1`) were pinned without reaching
  the CDN from the development environment (E-27 checks the two addresses once; a missing one only disables reading,
  the page says so and typing works); the photo reader fetches its worker and core from jsDelivr and its Spanish model (a few MB) from tessdata.projectnaptha.com
  the first time on each device (neither pinned by lint rule 13, which sees only the two script addresses); a dollar invoice is paid in colones at the invoice's rate (no exchange difference until A-06); confirming an
  invoice posts it as 0016 always did, whatever the daily auto-post setting says, and the invoice's IVA goes to 1140
  on confirmation; a delivery or a confirmed invoice is not voided from this page (reversals from Contabilidad, as
  before); a payout taken before the invoice shows as pending until the invoice is confirmed or the payout is voided
  at the POS.
- **Not done, by the owner's instruction:** 0029 and 0030 are files only (E-25); the site is not published; no
  accounting setting changed (the new account and mappings are additions that go live when 0029 is applied, so A-12
  comes before E-25).
- **Reviewed (three independent readers, 2026-10-15) and fixed in the follow-up commit:** a wrong PIN was counted inside
  the transaction block and rolled back with it (unlimited guessing): the PIN is now checked before the block in the
  three functions; the credit-card account code collided with 0013's customer advances (2160 now, with a guard); a
  register payout could be documented twice when the accountant had already documented it (checked now, also in
  `po_history`); a voided payout blocked a new one (the id follows the void); a Contabilidad-made or voided invoice
  left `invoice_status` behind (a trigger on `invoice_id` keeps it, and a re-confirmation takes a fresh invoice id); an
  invoice over several deliveries hit the unique index on the number (only the first delivery carries it); a dollar
  invoice rounded differently on the page and the server; whole-colón payments could never close an invoice with cents
  (under one colón over pays it in full, on both sides; the pads accept cents); a request id kept per order could report
  a second delivery as saved when the server answered «repeat» (the id follows the order's state, and a repeat is told
  as such); a slow read could fill another order's window (generation guard); orphan uploads (`purchase_doc_attach`
  registers them); file types from the kind, HEIC refused; the XML's own exchange rate; the page hides the file
  buttons when 0030 is not applied; a failed `po_pending` no longer reads as «nothing owed»; «locked» offers the PIN
  screen over the window.

## D-042 · 2026-10-15 · Recibir pedido approved for publication with two adjustments: no files or readers; no accountant gate
- **The owner's decision (same day, after reading the result of D-041):** the implementation is approved as built with
  two changes only. (1) No photographs, attachments or automatic reading of invoices (OCR, PDF, XML): the invoice's
  number and amounts are typed by hand. (2) The accountant needs no access to the system and approves nothing for
  this section to be used: Canopy OS is the café's internal administration; the financial information stays available
  to consult, and any accounting automation not yet enabled stays off. Everything else of D-041 stands unchanged:
  the five order options and the design, pending / review / confirmed invoices, colones and dollars with the rate,
  the payment methods (register cash with a manager PIN, SINPE/bank, debit card, credit card), partial and combined
  payments, what is owed, the order's history, and the one-transaction save with its repeat protection.
- **What changed in this commit.** Migration 0030 (the Storage bucket, its rules, `purchase_doc_attach`) is deleted;
  0029 loses the `purchase_receipt_files` table and the `files` entries of `po_history`/`po_pending`; the page loses
  the photo/file buttons, the readers (pdf.js, tesseract.js), the XML reader, the file list, uploads, «Adjuntar
  factura», «Ver archivo» and the file preview; the release check, the rehearsal comparison, the backup kit
  (`backup.sh`, `ensayo.sh`, `anonimizar.sql`), the Storage stubs and lint rule 13 go back to what they were, minus
  the two reader libraries; test `330_purchase_docs` and the browser scenarios about files are gone. Nothing else of
  the flow or its tests changed. The accountant's confirmation of the card accounts (A-12) is no longer a condition
  for anything: the account `2160` and the two mappings are part of 0029 as approved; the accountant may review them
  whenever the owner shares the information. `ledger_auto_post` and every regulated setting stay off as before; the
  entry an invoice or a payment writes in the internal books is the one Contabilidad has written since 0016, not a
  fiscal record.
- **Tests:** SQL 32 files (`320_receive_settle` 127, `240_release_check` 17), browser `290_receive` (4), the full
  suite green; the rehearsal applies 0000–0029.
- **Addendum, the owner's first «Ensayo en pruebas» after the launch (2026-10-15 22:09 UTC, run 38815097544):** the
  copy, the anonymization and 0029 passed; only the comparison failed, on four checks written for the launch-night copy
  (production before 0000): `operator_mode` should be `off` (production has `record`, the owner's choice of
  2026-10-15), and the bucket `expense-receipts`, its two rules and the 0025 upload rule missing (Storage lives in the
  `storage` schema, which the copy of `public`, `canopy` and `acct` never carries; at the launch 0015 and 0025 created
  them in the throwaway database itself). Nothing of 0029 was involved. `compare.py` now applies those four checks only
  to a copy from before the launch; on a copy that already had migrations the regulated switches are still checked OFF
  and production's own `release-check.sql` (publication step 4) judges its Storage. `compare-selftest.py` proves both
  kinds of copy (14 cases). The pages and 0029 are byte-identical to 29e4ba3.

## D-043 · 2026-10-16 · Recipes, stage 1A: saved with a manager or owner PIN, with history, kitchen units and one cost (0030)
- **The owner's decisions (2026-10-16), after the drink catalog («Recetario», version 2) and the stage plan:**
  (1) fruit is bought fresh to freeze at the café or bought frozen; usable grams and preparation losses are recorded
  separately (stage 3); (2) baristas may report waste, only a manager or the owner approves inventory adjustments
  (stage 3); (3) every recipe change is authorized with a PIN (1A); (4) a sale taken without internet keeps the recipe
  and the customizations in force when it was rung, even if it reaches the server later (1B/1C); (5) room orders use the
  standard recipe at first (1C). Order of work: 1A the recipe editor's security, history, units and consistent costs;
  1B exact deductions and returns; 1C customizations at the register and on the preparation ticket; 2 automatic
  printing of the preparation ticket; 3 waste and smart reorder alerts. The quantities of the catalog are still
  proposals: nothing of it is loaded.
- **What 1A builds (development and test environment only; the owner authorized code and tests, not production):**
  - Migration `0030_recetas_seguras` (additive). `recipe_versions`: one row per saved version of a product's recipe
    (lines with name, unit and quantity, cost at the average cost, the cost before, the price without IVA, who, when,
    why, how), readable by whoever may open the inventory, unchangeable even from the SQL Editor (update, delete and
    truncate refused). Every recipe that exists when 0030 is applied becomes its «starting version». `recipe_save`
    saves a whole recipe in one transaction: inventory open on that device, the PIN of a manager or an owner (checked
    first, so wrong PINs count and lock after five, as everywhere since 0025), the version the page showed (a second
    device that saved meanwhile is reported, never overwritten), a request id (a lost answer retried is saved once),
    every line checked (up to 30, no duplicates, a known and active item, a positive number, g/kg on mass items, ml/L
    on volume items, units on unit items, at most 10 kg or 10 L or 500 units per serving), quantities typed in grams or
    millilitres converted to the item's own unit, a reason required to leave a product without ingredients, an
    unchanged recipe answered without a version. It writes the version and an approvals-log row (`recipe_change`).
    `recipes_autolink_pin` is «link same-name items» with the same PIN. The PIN is never stored.
  - Pages still open on a device with the old editor (and the café's SQL) keep writing `recipes` directly: three
    statement triggers record those writes as «direct change» versions (the old page's delete-then-insert shows as two:
    the recipe emptied, then the new one); a product deleted from the menu leaves a last «product deleted» version. A
    contract migration (0031) will take direct writes away once every device has the new page (E-30).
  - Guards: the unit of a stock item that has movements or is in a recipe cannot change (`unit_locked`: a new item is
    the way to count it differently, so no recipe or history changes meaning); an item in a recipe cannot be deleted
    (`stock_item_in_recipe`).
  - One cost everywhere: the average cost, or the last price per unit when there is no average yet
    (`_stock_unit_cost`, the rule sales already stamp on their movements). An ingredient created without a price has
    no average (not ₡0), and one priced on the page but never received takes that price as its average, so its sales
    are stamped at a real cost and Recipes, Insights and the books agree; 0030 gives that price once to the existing
    items in that state; the first delivery sets the average as always. The Inventory food cost now values what was
    used at the cost stamped on each movement (a movement stamped without a cost, from before, at today's cost, as
    before) and compares it with sales without IVA (`revenue_net_crc`; `revenue` stays what was charged). The
    function's `stock_value` follows the same rule; the Inventory «Stock value» tile still uses the last price (a
    known gap, CHECKLIST row 31).
  - Inventory → Recipes: every line editable (ingredient, quantity, unit: g or kg, ml or L, units), add, remove and
    substitute (the quantity stays when the new item is in the same family), the cost per line and in total at the
    average cost and as a percentage of the price without IVA, the cost at the last purchase price when it differs,
    the items without a cost named; «Save recipe» opens the PIN window (who authorizes: managers and owners only, the
    person who unlocked the device proposed; the reason); the history of the product with who, when, why and what
    changed (added, removed, from → to) and the cost before → after; an unsaved draft survives a reload of the page
    (never its PIN) and is dropped when someone saved a newer version. A database without 0030 keeps the old save.
  - Frozen fruit and other things bought in bags: counting in closed bags plus loose grams (the total is filled in), the
    delivery in bags or grams (each fills the other), and a hint on what «units per pack» means (a 1 kg bag of frozen
    fruit = 1000 g). Menu Manager warns before deleting a product that has a recipe (Sold out keeps it); the approvals
    log names recipe, cost and stock-item changes.
- **Rollback:** `supabase/tools/reversion-0030.sql` removes the functions and triggers, restores the three changed
  functions byte for byte (the production snapshot's fingerprints), and keeps the history (still unchangeable).
- **Not in 1A (later stages):** a sale still takes the recipe in force when its line reaches the server, so a sale
  synced late uses the recipe of that moment (decision 4 is 1B/1C); returns of exactly what a sale took (1B); the
  customizations (1C); waste reports and approvals, fruit losses (3). A sale's movement of an item whose average cost is
  0 is stamped at 0 (`_stock_move_cost`, unchanged; 1B).
- **The phone (the owner's added requirement, 2026-10-16):** the recipe editor works completely from a phone. On screens
  up to 720 px each ingredient is a touch card (ingredient on top, quantity and unit side by side, the line's cost and
  «Quitar» below), every control is at least 44 px high with 16 px text (no zoom-in on iOS), «+ Ingrediente» and
  «Guardar receta» are two wide buttons, the PIN window fits the screen with full-width fields and buttons, and a
  product finder («Buscar un producto») filters the menu list by name or category. Nothing scrolls sideways. After a
  save, a green line stays on screen («Receta guardada · versión N · quién»); errors stay in the PIN window or under the
  editor. The browser test opens the editor at 390 px and checks every control's size and position, the horizontal
  scroll, the finder, add/remove/substitute, the costs, a wrong PIN, the save, the confirmation, the history and a
  refused quantity.
- **Independent review (five lenses, each finding re-checked adversarially; all confirmed ones fixed before the commit):**
  security: the page treated any failed database-version call as «old database» and fell back to the save without PIN
  (now only «function not found» does; any other error leaves the version unknown and saving waits); the whole history
  table was read to find each product's version (Supabase answers 1 000 rows at most, so past that some products could
  never be saved: now one read per product); `_stock_item_in_use` was callable from the API (now only from its trigger).
  Integrity: a recipe saved in grams while the owner changed the item to grams could end up 1 000× off (the save now
  holds the ingredients, in id order, for its few milliseconds); the history trigger swallowed a deadlock as a warning
  (now it fails the write visibly); «link by name» could add a line to a recipe being saved (it now takes each product's
  lock); the baseline ran before the triggers were in place and did not record changes made during a rollback (now
  after them, and a second apply records those changes as direct); the cost before of a direct version was the stamped
  one (now the previous recipe at today's costs). Page: the lines were read before the version (now after, and nothing
  is editable until both are read; a failed read says so and the product is tapped again); a new request id was made
  each time the PIN window opened (now the draft keeps its id, so a save whose answer was lost is retried as the same
  save, and a changed draft is a new one); the Spanish of «% del precio sin IVA» was half translated (the specific
  entry now precedes the general one); costs could be stale after a delivery in another tab (opening a product reads
  today's costs). Compatibility with the page published today: the delete guard's code carries «history», so that page
  shows its «it is kept; untick Active» advice; the food cost keeps `revenue` as what was charged (that page's «Sales»)
  and adds `revenue_net_crc`, which the new page shows as «Sales without IVA»; only the unit guard still gets that
  page's generic «try again» until the new page is published.
- **Tests:** SQL `330_recetas_seguras` (99), `340_reversion_0030` (13), `240_release_check` (0030 and its two functions
  required); browser `300_recipes` (7, one on a phone); the rehearsal's live pages (the three builds published so far:
  8950054, v2026.10.14-1 and v2026.10.15-1) save a recipe with the editor published today and the history records it.
  Nothing was applied to production, nothing published, nothing merged (the owner's instruction).

## D-045 · 2026-10-17 · Final review before production: device clocks and devices offline for days (no server-side clock correction; flags visible; three small fixes)
- **The owner's request:** a last review of two risks before authorizing production: (1) a simple protection against
  large differences between a device's clock and the server's, without complicating the system or blocking sales;
  (2) a device offline for several days while recipes change and 0030–0032 are activated must sync without losing
  sales or deducting wrong ingredients. Fix only real defects, in code and tests; otherwise document the evidence.
- **How it was reviewed:** three independent lenses (clocks; the multi-day chain on a throwaway database built through
  0029, then 0030 → recipe changes → 0031 → 0032 → register day closed → sync exactly as the pages do; the page and
  session a device comes back with), each finding attacked by a verifier. Scripts in the session scratchpad.
- **Clocks — existing mechanism judged sufficient:** `login.js` measures the skew from every new token and warns at
  > 2 min; 0003 flags `clock_ahead`/`late_sync`/`after_close` (with an audit row); 0031 treats a clock ahead as now.
  A server-side correction (send-time skew applied to ring-time stamps) was prototyped and **rejected**: it rewrites
  correct timestamps whenever the clock changed between ringing and sending (a reset clock threw a sale 26 years
  ahead; a clock set ahead by hand moved a correct sale back and took the previous recipe). A client-side correction
  from the stored skew is worse (stale after any clock change). Decision: no correction; make the existing flags
  visible in Sales (and its CSV) so a manager sees a device whose clock is off.
- **Clocks — one small fix:** a line whose product has a recipe today but had none at the line's time deducted nothing
  with no flag (a device clock behind looks exactly like that); it is now flagged `stock_not_taken`.
- **Offline for days — mechanism judged sufficient:** every sale saved and never refused; lines take the `baseline`
  version (the recipe at activation, the only one known) and the first known cost; flags and the audit row as 0003;
  operator attribution from a session expired days earlier holds (the window is on the sale's time); the discount
  approval holds; adds to a bill paid or cancelled meanwhile answer a final code the POS reports once. The queue
  (`hg-pos-queue`) survives the version gate (which never reloads over a non-empty queue), a refused token refresh and
  a forced sign-in. Two small fixes: the `tab_adds` idempotency rows now live 30 days (an add whose reply was lost,
  re-sent after 2+ days offline, was accepted as a second add); a product renamed before its first version (only
  possible in the activation window) now keeps its deduction through the menu log's old name.
- **Residual risks (accepted, stated in docs/ACTIVACION-RECETAS.md):** a clock behind takes the recipe and cost of the
  time it marks (wrong only if a recipe changed inside the skew); a clock > 10 min behind or > 30 min ahead records an
  online discount as not verified (pre-existing); a clock off by a day moves that device's cash to another register
  day (flagged, now visible); a POS tab closed and reopened while still offline asks to sign in until the connection
  returns (nothing lost); sales from before the activation are valued at the activation's recipe and first cost.
- **Tests:** 350 (the chai case now asserts the flag; a product renamed before its first version; an add re-sent after
  three days), browser 310 (the Sales notices), and the rehearsal's live pages (the published POS uploads a sale it
  kept for three days across 0030–0032: starting recipe, first cost, `late_sync`/`after_close`, audit row).

## D-044 · 2026-10-17 · Recipes, stage 1B: every sale keeps the recipe and the cost of its moment; returns give back exactly what went out; recipes only with the PIN (0031, 0032)
- **The owner's instruction (2026-10-16/17):** stage 1A is satisfactory to keep developing, but neither 0030 nor the
  publication is authorized yet. Develop stage 1B in code and tests only: (1) every sale keeps the ingredients,
  quantities, customizations and costs of the moment it was rung, also when it is synced after working without
  internet; (2) taking a product off, changing a bill or voiding a sale returns exactly the original movements, never
  recalculated, never twice; (3) once the new system is on, no earlier page version can change recipes without the
  required authorization, with a transition that never interrupts the till; (4) compatibility with existing devices,
  open bills and sales waiting to sync; (5) tests with several devices, simultaneous changes, connection loss, recipes
  changed in between and partial voids; (6) the phone recipe editor keeps working. No customizations (stage 1C).
- **How it was decided:** five readers mapped the code (deduction, reversals, the POS queue, access, tests); three
  independent critics attacked the first design and found three high problems, all designed out before writing code:
  the version would have been resolved at sync time (the menu-link trigger fires before the line's time is set); a
  per-move return rule would have returned twice the bills that already had an item taken off the old way; a version
  naming a since-deleted ingredient would have refused the sale with a foreign-key error.
- **What 0031 does (additive):**
  - Every sale line records the recipe version it took (`order_items.recipe_version_id`) and the moment whose recipe
    and cost it took (`stock_time`): the till's time for a sale (also one kept on the device and sent later), the time
    an item was added to a bill, and "now" for a sale of now. If the recipe did not change since that moment (the
    normal case), today's recipe is used exactly as before; if it changed, the version in force then; a sale rung
    before the history began takes the starting version; a product whose first recipe came after the sale takes
    nothing. Each movement names its line and units (`stock_moves.order_item_id`, `line_qty`).
  - Costs have a history (`canopy.stock_cost_history`, the effective cost: average, else last price; seeded at the
    migration, appended on every change) so a late sale is valued at the cost of its moment; an average of 0 with a
    price is valued at the price, not at ₡0 (the gap D-043 left for 1B).
  - Taking an item off a bill (`tab_remove_item`, same signature and behaviour otherwise) gives back, per ingredient,
    the share of what that line still has out, at the cost it went out with; the last unit gives back exactly what is
    left (no residue, never twice). The rows stay positive 'sale' rows named after the product (so a later void of the
    bill nets them as 0005 always did, product profitability nets them, and a rollback of 0031 keeps every bill
    exact). A line from before 0031 shares what is still out under its name in that bill (old take-offs included).
  - A bill paid in part by item and then voided puts out again exactly what the eaten units took, at their cost
    (`_order_tab_voided`); a line from before 0031 puts out again the eaten units' share of what is still out under its
    name in that bill, at the weighted cost it went out with (never today's recipe).
  - Whole-order voids, cancellations and refunds with restock already returned exactly what went out (0005, 0006):
    not changed.
  - A product renamed or deleted from the menu while a till was offline still takes its recipe (its history has the
    name, and the product still existed when the sale was rung or no product has that name today); a product deleted
    and made again under the same name is the new one for what is rung after that (as in 0004); an id that never had
    that name still falls back to the name as in 0004.
  - Items added on the device to an order before it reached the system take the recipe and cost of when they were
    added, whether they go up with the order (`pos_record_sale`) or after it (`tab_add_items`): the new POS sends each
    item's time (`"at"`, optional, read safely; older pages do not send it and nothing changes for them); the server
    keeps it between the order's time and now (the till already chooses the order's time, so this gives it nothing new).
  - The live recipe and the latest version are read in one snapshot, so a recipe saved on another device at the same
    instant is either fully in a sale or fully out of it, and the line names the version it really took.
  - The deduction never refuses a sale: a missing ingredient is skipped and the order flagged `recipe_item_missing`;
    any other error flags `stock_not_taken` (deadlocks and timeouts still go back to the till, which retries).
  - An ingredient named in the recipe history cannot be deleted (it is deactivated), so old versions stay readable.
  - `canopy.recipe_baseline()` runs again so any recipe changed without a version is recorded before sales read the
    history.
- **What 0032 does (contract, at activation):** no page can write `recipes` directly (insert/update/delete revoked from
  the signed-in role; reads unchanged) and the PIN-less `recipes_autolink()` is no longer callable. The only way is the
  1A editor with a PIN. The POS never writes recipes, so the till is not affected; an older Inventory page that tries to
  save sees «could not save» and nothing changes. Deleting a product still removes its recipe (the cascade runs as the
  table owner) and the history records it. This replaces E-30's "wait a week": nothing on the till depends on it.
- **Rollbacks:** `reversion-0032.sql`, then `reversion-0031.sql`, then `reversion-0030.sql`; each refuses the wrong
  order and restores every changed function byte for byte (`_order_item_stock` and `_order_item_menu_id` of 0004,
  `pos_record_sale` of 0010, `tab_add_items`, `tab_remove_item` and `_order_tab_voided` of supabase/pos-tabs.sql,
  `_stock_item_in_use` and `_stock_item_history_guard` of 0030); the new columns and the cost history stay. Applying 0031 again after its rollback is done with the open bills
  closed (a bill open under the first 0031 with items taken off during the rollback could give back too much).
- **Independent review (after the first implementation):** found a regression (a product deleted and made again with
  the same name: a till with the old menu would have taken nothing) and that items added offline to an order not yet
  confirmed took the recipe of when they arrived; both fixed with tests (350, 310). The version stamp of a sale saved at
  the same instant as a recipe change is now read in the same snapshot as the recipe.
- **Second independent review (four lenses, each finding attacked by a verifier):** one confirmed medium (the
  activation guide's test sale could not be voided in the evening window: the register is closed, so it would have
  left a sale and a refund on a closed day; the window now creates no sale) and lows, all fixed with tests: a sale
  rung before the cost history began was valued at today's cost (the first known cost now); an ingredient only in an
  old recipe could change its unit (now locked, and a late sale skips and flags a line whose unit changed); applying
  0031 again after its rollback now records costs that changed meanwhile; a bill from before 0031 paid in part and
  voided re-deducted its eaten units with today's recipe (now its share of what went out, at its cost); a line whose
  stock could not be taken keeps its link (nothing went out, nothing comes back); items added offline that go up with
  their order keep their own time; flagged sales are now shown in Sales; a real concurrency test (two sessions) was
  added. Checked and sound: exact returns in every combination, the single snapshot under simultaneous saves, no new
  deadlock cycle, privileges, 0032 has no bypass, the rollbacks are byte-exact.
- **Verification of those fixes (three lenses, each finding attacked):** two lows in the new add-time rule, fixed with
  tests: the product of an item added on the device was decided at the order's time while its recipe was taken at the
  add's time (a product deleted and made again in between took nothing); an add with the device clock ahead fell back
  to the order's time instead of now. Also: a test for the re-apply re-seed (370 applies 0031 again after its rollback),
  the two-session test scoped to its own database, and wording (Sales says "left out", which also covers a changed
  unit; this entry and the guide). 22 odd values of "at" (infinity, epoch, objects, a 1 MB string, unknown zones) all
  keep the sale and land between the order's time and now; pos_record_sale is the 0010 body plus the one column.
- **Known limits (stated in docs/ACTIVACION-RECETAS.md):** the time is the device's clock; the stock movements of a
  late sale are dated when they arrive (as before), while their quantities and costs are those of the sale's moment; a
  bill opened before 0031 shares its returns (and the eaten part of a void) by product name at the weighted cost.
- **Tests:** SQL `350_ventas_exactas` (70), `360_recetas_solo_con_pin` (22), `370_reversion_0031` (17, the re-apply after the rollback included); 330 and 340
  adapted (the old-page section runs in the window between 0030 and 0032; the 0030 rollback first reverts 0032 and
  0031); browser `310_recipes_sales` (6: a sale offline while another device changes the recipe; two devices on one
  bill with a take-off, a stale device refused, a part payment and a void; an item added on the device to an order not
  confirmed yet, and to one never sent, the recipe changed before it is sent; two sessions at the same instant on one
  bill, and a sale rung while a recipe save is still open; flagged sales in Sales) and `300_recipes` (7, the phone included);
  the rehearsal's live pages expect the old editor to be refused from 0032 on and the POS to keep selling and syncing.
  Nothing was applied to production, nothing published, nothing merged.

## D-046 · 2026-10-17 · Backup #9 decrypted and restored for real with the owner's keys; the restore drill works on a clean PostgreSQL (E-24 closed)
- **The owner's request:** before activating 0030–0032, prove that an encrypted backup can really be recovered, in a
  throw-away environment, without sharing keys through the chat, GitHub or run logs, and without touching production.
- **What happened:** the owner's notes were first believed to hold only the public keys (D-040); the private key files
  were found and each of the two (the owner's and the printed recovery one) decrypts «Respaldo nocturno» #9
  (2026-10-17 15:36 UTC, SHA-256 verified). The restore on a bare PostgreSQL 17 in Docker then failed twice: first on the
  API roles (`anon`, `authenticated`, `service_role`) that the dump's GRANTs name, then on the missing `auth` schema (37
  policies call `auth.uid()` or `auth.jwt()`, and PostgreSQL validates a policy's expression when it is created). Both
  times `--single-transaction` left the database with 0 tables. Root cause: `restore.sh` assumed a Supabase-shaped
  target and the guide's drill used the PRUEBAS project, gone since D-039; the nightly restore test, the rehearsal and
  the CI test always run `restore-stub.sql` first, which gives a bare server exactly that shape. With the stub the
  restore passed: `OK: 62 tablas y 464 filas iguales al respaldo; contenido idéntico en 62 tablas`, rights fingerprint
  equal to production's, 8 photos verified, migrations 0–29 present, `anon` refused on `public.orders`, a login's query
  accepted (the policies decide the rows); the container was deleted.
- **Changes (code and docs only; nothing in production):** `ops/backup/restore.sh` gives a clean PostgreSQL the Supabase
  shape itself with the `restore-stub.sql` kept next to it (target without an `auth` schema and without a
  `supabase_admin` role; a half-prepared target with `auth` but no API roles is refused; a Supabase project is never
  touched) and verifies the checksum with macOS `shasum` when `sha256sum` is missing; the backup pipeline test restores
  the same file into a clean database with the second key, checks that a target already in shape is not stubbed again,
  and checks on the restored copy that `anon` is refused and a login sees the same rows as in the source; `docs/RESPALDOS.md` rewrites
  the quarterly drill for Docker on Mac or WSL with every verification kept (decrypt with each key first, checksum,
  internal hashes, rows, content, rights, photos, the `set role` checks, release-check against the copy, cleanup of
  the unencrypted photos folder); `docs/DEPENDENCIES.md` E-24 and E-28 DONE; `docs/LANZAMIENTO.md` rollback rows
  0029–0032; `docs/PRUEBAS.md` reinicio = `no` on a migrated copy; `docs/ACTIVACION-RECETAS.md` adds the device checks
  (POS chip, open bills, kitchen, clocks, one tab per page), the read-only snapshots before and after, the fresh
  backup right before 0030, the tag's Target, version.json before touching devices, the stop rule, the owner's
  recorded decisions and the rule that the window waits for the café to close.
- **Also noted:** the job's «restauración verificada» restores the plaintext dump before encrypting and the job never
  holds a private key, so only the owner's drill proves key custody: now every three months, once a year with the
  printed key. The kitchen and POS pages keep polling `orders` every few seconds after a session ends (401 as `anon`,
  nothing exposed; pre-existing since 2026-09-08, identical in the live tag): a one-line timer fix with a browser test
  is planned for the first release after the activation; nothing grants anything to `anon`.
- **Activation readiness:** unchanged, LISTO (D-045). An independent readiness review of 9b33273 (four lenses:
  migrations and reversibility, site/database compatibility both ways, the documented procedure, interruption points;
  every blocking or owner-decision finding attacked by two verifiers) found no blocker; the surviving owner decisions
  (the one-time `avg_cost` fill of 0030, the key custody now settled, who holds the manager PIN for the no-op save) are
  recorded in the guide. Nothing was applied to production, nothing published, nothing merged.

## D-047 · 2026-10-18 · Recipes stage 1A+1B live (0030–0032, v2026.10.17-1) and the first drink recipes loaded as data by the owner through `recipe_save`
- **Activation facts (the owner's report):** 0030, 0031 and 0032 applied in production on the night of 2026-10-17 in Monteverde (early
  2026-10-18 UTC); `release-check.sql` clean (`migrations_missing` = `[]`, `functions_missing` = `[]`); in the «after»
  `production-snapshot.sql` the five `functions_missing_legacy` signatures are the pre-launch versions dropped by 0005/0010,
  expected; tag `v2026.10.17-1`
  (= `671fc0e`); «Publish website (PRODUCTION · manual only)» run #51 at 02:08 UTC; `gh-pages` `1daae6f` = `website/` of
  `671fc0e` plus the build stamp, the cache-buster, CNAME, version.json and the film and photos listed in `website/ASSETS.md`; version.json confirmed on the domain by the owner.
  E-29 and E-30 DONE. Step 2.11 of the guide (the no-op save with a manager PIN) is superseded by this day's import, which
  exercised `recipe_save` with a manager PIN seven times in production; the café-device checks (step 2.10) wait for the
  owner's report.
- **The request:** load the café's 27 standardized drink recipes (coffee grams and cold-milk millilitres; the espresso
  yield is a preparation spec, never deducted) without typing them one by one, under twelve rules: grams deducted, yield
  not an ingredient, milk is cold milk in ml and never the cup's volume, no invented quantities for chocolate, cocoa,
  matcha, chai, syrups, caramel, condensed milk or ice, flavoured drinks stay incomplete until defined, no product or
  stock item is assumed or created, a range (10–15 ml) is a pending decision and never a chosen value, no existing recipe
  is overwritten without the difference reviewed and recorded, the PIN, versions, audit, costs and deductions of 0030–0032
  are preserved, past sales never recompute, no test sales. The owner's question «data or code?» was answered: data.
- **Decision:** a data load through the existing `recipe_save`, nothing else. No migration, no release, no page change.
  A small generator (read-only export → correspondence between standards and real products → owner's decisions → preview
  and batch with deterministic request ids) and a browser-console script that the owner pastes on the live Inventory page,
  which sends each recipe to `recipe_save` with the manager PIN, the expected version re-read live, a reason, a request id,
  and stops at the first error of any kind. Each imported recipe is therefore a normal `editor` version: editable later
  from the page with the PIN, with the previous recipe kept in the history, a cost of the moment and an audit row.
- **Rejected:** direct SQL on `recipes` (bypasses the PIN and is recorded as a `direct` change: exactly what 0032 closes);
  choosing a value inside the 10–15 ml range of the espresso macchiato; applying the Americano recipe to «Iced Americano»
  or the Cappuccino recipe to «Cappuchino Large»; adding a misspelling alias so that a product matches a standard; a
  migration or a release for what is only data; asking the owner to edit code (two ready files, PREVIA and IMPORTAR, differ
  in one line).
- **The real data (read-only export, 2026-10-18 17:43 UTC, schema 32):** 43 products, 25 stock items, 5 recipe lines in 4
  products (Espresso 20 g, Americano 19 g, Macchiato 19 g + 50 ml, Rollo De Canela 1 unit; all v1). Coffee: `Cafe en grano`
  (kg). Milk: two whole-milk items, `Leche entera` (counted by unit) and `Leche entera 2` (ml, box of 946 ml); the owner
  stated they are not interchangeable, so only the ml item can take millilitre lines (a ml line on the
  unit item is refused by `recipe_save` with `bad_unit`) and that choice was confirmed by the owner, not assumed.
- **The owner's authorization (2026-10-18, eleven conditions):** import every possible recipe with the standards as
  initial values; coffee `Cafe en grano`, milk `Leche entera 2`; for a product with several sizes but one menu entry, pick
  the most appropriate size provisionally and document it, never creating products or variants; Espresso, Americano and
  Macchiato may be replaced with the history preserved; Rollo De Canela and everything outside the drinks untouched;
  unknown quantities or missing ingredients marked pending, never presented as recipes; no prices, purchases, stock,
  movements or past sales changed; no migration or deploy; a final preview with exact quantities, costs and expected
  versions, and a check that nothing changed after the export; `recipe_save` with manager PIN, version validation, history
  and immediate stop on any error; the owner runs it, the AI writes nothing to production.
- **Provisional choices (condition 3), to be confirmed on the first manual review:** «Espresso» → Espresso double (18 g;
  it was already prepared with 20 g, a double dose; the single of 9 g stays unassigned). «Latte» (one size) → Café
  latte 8 oz (190 ml; priced between the Cappuccino and the Cappuchino Large on the menu; the regular size is the
  consistent one, and a wrong guess under-deducts rather than over-deducts; the 12 oz of 280 ml stays unassigned).
  «Iced Latte» → Iced latte 12 oz (180 ml; same price as the regular Latte and similar milk; 16 oz stays unassigned).
- **The batch `bebidas-2026-10-18` (7 recipes), imported by the owner, authorized by Jorge with his manager PIN, verified by
  the owner with the read-only post-check (7 × «ok: importada»; Macchiato and Rollo De Canela «ok: intacto»; expected
  versions; 7 audit rows; no missing cost):**

  | Product | Before (v1) | Loaded | Stored as | Version | request_id |
  |---|---|---|---|---|---|
  | Espresso | Cafe en grano 20 g | 18 g coffee | 0.018 kg | v2 | 82e692b0-642c-5c43-aa19-f59a3b861a11 |
  | Americano | Cafe en grano 19 g | 18 g coffee | 0.018 kg | v2 | 00c77646-b77c-57ad-bfb3-9692bdec6e19 |
  | Cortado | no recipe | 18 g + 40 ml | 0.018 kg + 40 ml | v1 | 36862a75-5c72-5fbd-b011-5b1286c44a79 |
  | Flat White | no recipe | 18 g + 120 ml | 0.018 kg + 120 ml | v1 | 70811573-bc4a-51da-a22e-4128c7eec134 |
  | Cappuccino | no recipe | 18 g + 120 ml | 0.018 kg + 120 ml | v1 | 0ad428ad-be37-5db3-a099-bac10cf12c2a |
  | Latte | no recipe | 18 g + 190 ml | 0.018 kg + 190 ml | v1 | 188faa0c-82c7-5cd3-bcba-5b04a590de8a |
  | Iced Latte | no recipe | 18 g + 180 ml | 0.018 kg + 180 ml | v1 | 0371757c-4850-573c-a644-600237fa9de6 |

  Each version keeps the cost of its moment (not repeated here). The exact moment of each save, the authorizer, the
  cost and the reason («Estándar bebidas 2026-10 · …», with «reemplaza: … → …» on the two replacements) are in
  `recipe_versions` and `audit_log` (`recipe_change`), which are the authoritative record.
- **Not loaded, recorded as pending (E-31 to E-34):** Macchiato keeps 19 g + 50 ml of `Leche entera 2` because the standard
  fixes the milk as a range (10–15 ml) and a range is a pending decision, not a value; until the owner decides, every
  Macchiato sold deducts 50 ml, three to five times the standard. Mocha, Iced Mocha and Costa Rican Hot Chocolate wait for
  the chocolate quantity (`Chocolate en polvo` exists in kg with no cost). Vanilla, caramel and Spanish lattes, chai and
  matcha have neither a product nor a stock item. Café con Leche, Canela Cloud, Iced Americano, Cappuchino Large, Tea and
  Sweet Cane Drink have no standard and inherit nothing. Seven standards have no product (Espresso single, Ristretto
  double, Lungo double, Piccolo latte, Café latte 12 oz, Iced latte 16 oz, Filter coffee 250 ml). From the first sale
  after the load, milk is deducted from `Leche entera 2`: milk must be received and counted under that item, or its stock
  goes below zero while `Leche entera` grows (E-34).
- **The owner's milk decision (2026-10-18, after the load):** whole milk is bought in packages of 10 boxes of 946 ml each
  (one box = 946 ml; one package = 9 460 ml); the desired reorder point is 9 460 ml on hand; recipes keep deducting
  millilitres. Purchases and recipe deductions must use one and the same stock item, `Leche entera 2` (ml), with no
  duplicate between `Leche entera` and `Leche entera 2`. The reorder point, the pack and that single-item rule are NOT
  assumed configured in production: E-34 lists them as pending implementation by the owner (Inventario → Existencias,
  no code or migration: every stock item already has the fields «Punto de reorden (alerta en)», which alerts at or below
  its value, and «Nivel par»; their current values on `Leche entera 2` are not known) and as pending verification with a read-only check of purchases, open order lines, recipes and stock of both milk items.
- **How it was checked before the hand-over (never against production):** the correspondence table and then the batch were
  rederived independently from the export and the standards and matched line by line; two adversarial review rounds
  (twelve readers in all) whose findings were applied: exact decimal costs, the current recipe shown on partial matches,
  mutually exclusive size choices made explicit, the second milk and the discarded coffee item explained, a stop on any
  unexpected reply from the server, a PIN dialog that is not a form (so the browser never offers to save it), re-runs that
  recognize what the batch already saved, two ready files instead of a hand edit, instructions for both logins and for the
  page's own 15-minute and 30-minute reloads; the console script in a simulated Inventory page with the real data in 13
  scenarios; the seven exact `recipe_save` calls on a disposable copy of the local test database seeded with the same ids
  (versions 2/2/1/1/1/1/1, 0.018 kg and exact ml, the same costs, 7 audit rows, zero stock moves, zero sales; `repeat`,
  `unchanged`, `changed` and `bad_unit` as designed); the two read-only SQL checks on that copy before and after.
- **Where the tooling is:** in the session's working folder only (export SQL, standards, generator, console script,
  read-only checks, instructions, batch); nothing of it is in the repository yet, and the real export and batch carry
  product ids and costs that do not belong in a public repository. Proposed for the owner's decision: add the tooling
  without data under `supabase/tools/recetas-bebidas/` in a later commit, so the next batches (Macchiato, the chocolate
  drinks) follow the same path.
- **Repository side of this entry:** docs only, plus `tests/rehearsal/LIVE_PAGES` pointing at the published `gh-pages`
  `1daae6f` (as the activation guide asked) and the live-pages rehearsal test taught to recognize the PIN editor it now
  exercises (a manager's PIN saves one `editor` version; the pre-1A editor's branches are kept). Nothing in this entry was
  pushed, merged or published by the AI; the import was executed by the owner from Canopy OS.

## D-048 · 2026-10-19 · Review section on the home page: Google and Tripadvisor as plain links to each platform's review page
- **Request (owner, 2026-10-19):** a premium, garden-style review section near the bottom of the home page with the
  heading «Loved Your Visit?», the owner's text, and two buttons, «⭐ Review Us on Google» and «🌿 Review Us on
  Tripadvisor», in the site's own button style; no redesign, no pop-ups, no large third-party widget, no form on our site,
  no fabricated ratings or review schema, no incentives; external links in a new tab with `rel="noopener noreferrer"`,
  accessible names and visible keyboard focus; not deployed without the owner's approval.
- **Decision:** a new last section of `website/index.html` (`#reviews`, right before the footer), built from what the page
  already has: the page's light panel (the same panel colour, 24 px radius, 12vh padding and soft shadow as the «Hold to
  brew» card), the existing kicker, heading and lede styles, the watercolour sprig, the `.rev`/`.part` entrance and the
  standard `.btn` (same height and the same hover: a 2 px lift and the darker green). Each button carries the owner's star
  or leaf as the site's own SVG icon (the shapes of the table menu's star and section leaf) instead of the emoji, so it
  renders the same on every device; when the buttons wrap they take one width with the icons lined up. The button text
  is the owner's wording; Spanish through `website/lang.js` like the rest of the page; the new-tab notice is visually
  hidden text inside each link, so the accessible name begins with the visible label. CSS lives in the page's own style
  block next to `.btn-rev`; no script, package or outside request was added.
- **Google:** `https://g.page/r/CfHitxq6bJ3AEBM/review`, exactly as the owner gave it (the same link the visit section and
  the footer already use).
- **Tripadvisor:** the owner's widget (`cdswritereviewlg`, location 34058072, `lang=es`, `display_version=2`) is a script
  from `www.jscache.com` that replaces a static link to the restaurant listing (`Restaurant_Review-g951347-d34058072-…`)
  with Tripadvisor's own small «write a review» form (rating bubbles, a review title and «Continue»). Public copies of
  that widget as rendered on other sites send the guest to `UserReview-g<geo>-d<location>-<Name>-m12097.html`, and the
  Content API's documented `write_review` link uses the same `UserReview-…` page; Tripadvisor's own «Write a review»
  button on listing pages has used `UserReviewEdit-g…-d…`. Tripadvisor documents neither as a public linking format. The
  button uses the widget's and the API's path for this location, without the widget's tracking code:
  `https://www.tripadvisor.com/UserReview-g951347-d34058072-The_hanging_garden_cafe-Monteverde_Province_of_Puntarenas.html`.
  It **could not be verified** from the development environment: its network policy refuses `www.tripadvisor.com`,
  `www.jscache.com` and `static.tacdn.com`, and the web tools cannot resolve them, so neither the widget's script nor the
  page could be opened here. **Verified by the owner on 2026-10-19:** the owner opened the link and confirmed it opens
  Tripadvisor's «Write a review» page for Hanging Garden Café, and approved the URL (E-35 DONE). If Tripadvisor ever
  changes it, the listing-button form `UserReviewEdit-…` is the first fallback and the address Tripadvisor shows after
  «Write a review» the last. The listing page was **not** substituted.
- **Rejected:** embedding the widget (it is itself a review form, which the owner ruled out; a third-party script with its
  own styling and a request to Tripadvisor on every visit); the listing URL behind the button (owner: not the listing);
  the official platform logos (they cannot be fetched here, and hand-drawn copies would break the platforms' brand
  rules); Review or AggregateRating schema (no fabricated ratings); a rotating icon on hover (the page's hover vocabulary
  is a small lift and a darker colour).
- **Checked:** e2e `320_home_reviews` (both destinations; accessible names including the new-tab notice; a new tab with no
  opener and no referrer; no form, widget, outside script or review schema; the standard button height; Tab order and
  the gold focus ring; Enter opens the page; a 375 px phone in Spanish: stacked, 44 px or taller, one width, nothing
  sideways); a mutation (the Tripadvisor link without `noreferrer`) makes it fail. The nav and the menu, story,
  gallery, visit, FAQ, guides and ask sections were screenshotted before and after at 1280, 820 and 390 px in English and
  Spanish, with motion reduced, the fixed layers (ambient background, drip thread, chat button) hidden and the nav
  un-fixed: 42 of 48 identical; the six «ask» shots differ only in a 17 px strip along their bottom edge, where the new
  card's soft shadow (the brew card's) reaches into the gap, and the footer only by its half-pixel position; with those
  layers shown, the gallery (desktop) and the menu and ask sections (phone) also differ where the drip thread's drawn
  length and the fixed layers follow the longer page. The hero, the brew cup and the canopy interlude were not screenshotted on their own (nothing
  above the new section changed in the markup or CSS).
- **Seen, not changed (site-wide, owner's call):** the site's gold focus ring (#B98A35) is 2.93:1 on the panel colour and
  2.76:1 on the page background, just under the 3:1 WCAG asks of a focus indicator; changing it would change the site's
  colours everywhere.
- **Repository side:** `website/index.html`, `website/lang.js`, `tests/e2e/specs/320_home_reviews.spec.js`, these docs;
  committed and pushed with the owner's authorization of 2026-10-19 (these six files only). Nothing merged, tagged or
  published: the site goes live only through the owner's tag and the manual publish workflow, after the owner's approval.

## D-049 · 2026-10-20 · Review section live (v2026.10.20-1)
- **Approval and preparation (2026-10-19):** the owner approved the review section (D-048) for production and asked for
  the release to be prepared under `docs/PUBLICAR.md` without bypassing any safeguard. Read-only checks before the
  release: candidate `f9cfdef` (PR #1 head, CI green, merges cleanly); no merge (every earlier `v*` tag is on the
  development branch and none was merged), no migration (`supabase/`, `.github/`, `tools/` unchanged since
  `v2026.10.17-1`); `pages.yml` identical on the default branch, the last tag and the candidate. The workflow's own stamp
  step, run on a copy, reproduced the live `gh-pages` `1daae6f` byte for byte from `v2026.10.17-1` (apart from the fetched
  photos, CNAME and the build time); on `f9cfdef` it differed from live in 22 files: the build stamp in 20 pages, the
  review section and its CSS in `index.html`, the six `lang.js` entries (used by no other page) and `version.json`,
  nothing else. Every stamped page (20; the five `es/` guide pages carry none) gets the new build, so every open device
  updates once.
- **The release (owner):** tag `v2026.10.20-1` → `f9cfdef`, created through Releases with the development branch as
  target and published 2026-10-20 13:13 UTC; «Tests» #139 on the tag green (13:13–13:22 UTC); «Publish website
  (PRODUCTION · manual only)» run #52 from the tag at 13:25 UTC, success, the «restaurar» step skipped; `gh-pages`
  `2ade5f6` "Publish website v2026.10.20-1 f9cfdef…"; `pages build and deployment` #48 green at 13:26 UTC. No
  environment approval was recorded for the run (E-20 still open).
- **Verified here, read-only:** the tag's commit; `gh-pages` `version.json` = `v2026.10.20-1`, build `f9cfdefe0a17`;
  the 20 stamped pages carry that build; the section, both exact links and the Spanish entries present; CNAME
  `hanginggardencafe.com`; `tests/tools/live-site-check.sh` before the pointer below moved: «approved release
  (v2026.10.20-1, built from f9cfdef)» (with `LIVE_PAGES` = `2ade5f6` it reports the same build as the known one, as after
  D-047). The live-pages rehearsal on `2ade5f6` passed on the production-shaped copy migrated to 0032 and on the reset
  copy (7 + 7).
  The owner's checks on the domain and on the café devices, and the checklist items done outside this repository
  (Ensayo, backup card), were not reported at the time of writing.
- **Timing:** published at 07:25 in Monteverde, after the café opened; `docs/PUBLICAR.md` asks for after the register
  close or before 6:00. The devices update by design between sales. A gap seen while preparing (older than this
  release, since the version check of 2026-10-12): the Caja's reload guard ignores an open «Hoy en el mostrador», so
  cash counts typed in its open, close or cash-move forms can be lost if the screen is left untouched; no money record
  is affected. A fix (no reload while those forms are open) is proposed, not made.
- **Way back:** «Publish website» from `v2026.10.17-1` with PUBLICAR and «restaurar» empty; no database step.
- **Seen while testing this record (not changed):** the browser test `310_recipes_sales` «… is shown in Sales for a
  manager (in Spanish)» failed in the full run and in 1 of 3 runs on its own, on code this record does not touch. Sales
  draws its list more than once on start-up (the first load and each sign-in event call `load()`), and the test reads the
  page once after its first Spanish notice, so it can catch a redraw before `lang.js` translates it on the next frame.
  Proposed fix, test only: wait until all five notices are on the page. Not made here (outside this records commit).
- **Records:** `tests/rehearsal/LIVE_PAGES` → `2ade5f6`; `docs/PUBLICAR.md` item 2 without the withdrawn staging site
  (D-039) and item 6 with the Caja's real connection texts and «Hoy en el mostrador» closed (the old «pendiente de
  enviar» text does not exist on any page); E-19 DONE (release `sitio-2026-10-09` published 2026-10-15 00:52 UTC);
  E-35 live; CHECKLIST and PRODUCTION-READINESS. Committed with the owner's authorization of 2026-10-20.

## D-050 · 2026-10-21 · The real mural at the end of the film, and a true quetzal in the story section
- **Request (owner):** on 2026-09-29 the film's ending was built as a separate photo (`assets/hero-ending.jpg`) so the
  real building could replace it once the mural was finished, without touching the film. On 2026-10-20 the owner sent
  that photo and asked for a preview without changing the video, chose the close framing «B cercana» (the mural's
  quetzal in the middle of a phone screen), and asked to finish it with that photo («es lo que hay»), edited with
  Higgsfield. The owner also asked to replace the bird of «Una montaña verde, una taza de paz», which did not look like a
  quetzal (pale hooked bill, black mask, turquoise throat), with a realistic one, and chose candidate B of two.
- **Ending photo:** the owner's photo (1600×1200, the only copy; uploaded by the owner through Higgsfield, media
  a2e41807) cropped to 16:9 at its own resolution (rows 25–925), enlarged to 1920×1080 (Lanczos, light unsharp), JPEG
  q85, 499 044 bytes, Higgsfield media f38d622c. **Higgsfield's AI upscaler was tried and rejected:** at 2K it rewrote the
  café's lettering (the logo's «MONTEVERDE / COSTA RICA» became «MONTEVERÉE / CSTÉ AILA», «RECEPTION» became «RECERTIOI»,
  the logo inside the window became «MONT CLOSE», the menu board got invented text); the 4K attempt failed on its side.
  A photo of the real business must not change its signs, so the final file is a plain enlargement in which every sign
  and logo reads as painted (checked). The same file is the page's share image (`og:image`) and the image in its
  structured data.
- **Framing:** wide screens keep the centred framing; upright screens (phones, a tablet held upright) show the photo
  30 % from the left, so the mural's quetzal, the café logo and the order window stay in view:
  `@media (max-aspect-ratio:1/1){.hero .still{background-position:30% center}}` in `website/index.html`. The title over
  the ending reads on the dark order window on every phone size tried.
- **Story quetzal:** gpt_image_2_5 (job c7e02149, 3:4, 2K), checked before use: rounded green crest, small yellow bill,
  crimson breast and belly, green back and wings, white undertail, two long green tail streamers, normal feet, no text or
  artefacts. Web copy 1000×1339 JPEG, 221 480 bytes, Higgsfield media fdf1aaa7 (the 5.6 MB PNG never ships). The image's
  alt text already describes a resplendent quetzal; the small watercolour quetzal (`deco-quetzal.png`) is accurate and
  stays.
- **Not changed:** the film. Its last shot still lands on the mural as it was completed digitally for film v4, then the
  real photo fades in (another viewpoint and time of day). Regenerating that last leg from the real photo is an option for
  the owner (Higgsfield credits), not part of this change.
- **How it was checked:** both files fetched back from the CDN with the same SHA-256 as the files made (b04f3a79…,
  723610c3…), and the copies used for the previews are those same bytes; `website/ASSETS.md` still parses to 14 rows with
  the pages workflow's own expression; e2e `330_home_ending` (upright phones and tablet at 30 %, sideways tablet and
  computer centred, cover, the ending file; it fails without the rule); previews of the ending on four screen sizes and of
  the story section on a phone and a computer, served locally with every outside request blocked.
- **Cost:** Higgsfield credits: 2.75 for the two quetzal candidates, 2 for the 2K upscale that was not used (the failed 4K
  attempt aside).
- **Repository side:** `website/index.html` (one CSS rule), `website/ASSETS.md` (two rows and a note),
  `tests/e2e/specs/330_home_ending.spec.js`, these docs. Goes live only with the owner's next release.

## D-051 · 2026-10-22 · The real mural and the true quetzal live (v2026.10.21-1)
- **Authorization (owner, 2026-10-21):** the owner confirmed the café was ready and authorized the release of
  `v2026.10.21-1` = `c1d9fb5` (D-050) under `docs/PUBLICAR.md`: check the commit and its tests, the pre-release checks,
  the tag on that exact commit, no change to code, video, database or other files, no merge of PR #1, stop and report
  on any error. The owner kept the final «Publish website» run (PUBLICAR) for themself.
- **Read-only checks before the tag:** `c1d9fb5` was the PR #1 head, «Tests» #142 green on it, PR #1 open and unmerged;
  since `v2026.10.20-1` (`f9cfdef`) two commits (`1e2e803`, the D-049 records; `c1d9fb5`, D-050) and no change under
  `supabase/`, `.github/` or `tools/` (no migration); `pages.yml` identical (blob `9b8defe`) on the default branch,
  `v2026.10.20-1` and `c1d9fb5`. The «Ensayo en pruebas» and the backup (checklist items 2 and 3) live in the owner's
  private `canopy-respaldos`, which this environment cannot reach; they were left to the owner, with the exact inputs
  (`v2026.10.21-1`, `desechable`, `no`, `no`). Their results were not reported here.
- **The tag:** `CLAUDE.md` forbids agents to create `v*` tags; the owner authorized it for this release. GitHub
  refused to create the release from this session ("Creating, editing, or deleting releases is not permitted for this
  session type", HTTP 403); nothing was created, the refusal was reported to the owner and no other route was tried.
  The owner then created the release through Releases: tag `v2026.10.21-1` → `c1d9fb5`, target the development branch,
  published 2026-10-21 13:21:22 UTC. Checked read-only: the tag's commit is exactly
  `c1d9fb5099ad5aad504cfb8122067ca96783d88f`; «Tests» #144 on the tag green (13:21–13:31 UTC).
- **The release (owner):** «Publish website (PRODUCTION · manual only)» run #53 from the tag, 13:35 UTC, success, the
  «restaurar» step skipped; `gh-pages` `0ad8c88` "Publish website v2026.10.21-1 c1d9fb5…" (`version.json`:
  `v2026.10.21-1`, build `c1d9fb5099ad`, built 13:35:34 UTC); `pages build and deployment` #49 green at 13:36 UTC.
- **Verified here, read-only:** `gh-pages` `0ad8c88` against the previous `2ade5f6`, file by file (56 files each): 24
  differ, as expected: the two photos, `index.html` (the build stamp and the D-050 framing rule, nothing else), the
  build stamp in the other 19 stamped pages, `version.json` and the published copy of `ASSETS.md` (the two rows and the
  note). `assets/hero-film.mp4`, `assets/hero-film-mobile.mp4` and `assets/hero-poster.jpg` are byte-identical (the
  film did not change); `es/` and CNAME (`hanginggardencafe.com`) unchanged. The two published photos are the approved
  files byte for byte: `hero-ending.jpg` 499 044 bytes, SHA-256 `723610c3…`; `quetzal.jpg` 221 480 bytes, `b04f3a79…`.
- **The public site (2026-10-22):** the domain is blocked from this environment, so it was read from an outside
  connection (the Higgsfield sandbox): `https://hanginggardencafe.com/version.json` = `v2026.10.21-1` from `c1d9fb5`;
  both photos served with HTTP 200, `image/jpeg`, the same sizes and SHA-256 as above; the home page carries the
  framing rule and its share image (`og:image`) is `assets/hero-ending.jpg`.
- **The owner's visual review:** the owner confirmed the visual review of the public site on 2026-10-22.
- **Timing:** the tag at 07:21 and the publication at 07:35 in Monteverde, after 6:00; `docs/PUBLICAR.md` asks for
  after the register close or before 6:00. The owner confirmed the café was ready. The devices update by design
  between sales.
- **Way back:** «Publish website» from `v2026.10.20-1` with PUBLICAR and «restaurar» empty; no database step.
- **Not changed:** `tests/rehearsal/LIVE_PAGES` still names `2ade5f6` (the owner limited this commit to
  documentation). It is still fetchable from a fresh clone, so the live-pages rehearsal keeps working, and
  `tests/tools/live-site-check.sh` accepts `0ad8c88` as an approved release. Moving it to `0ad8c88` is a one-line
  change for a later authorized commit. The hourly PR checks were stopped at the owner's request.
- **Seen while testing this record (not changed):** the first full run failed one browser test, `300_recipes`
  «café device in Spanish…», at its last check «no PIN kept on the device». Code this record does not touch; the
  same test passed in the run of 2026-10-21, in «Tests» #142 and #144, and 7 times in a row afterwards (a scratch copy that only adds logging). The
  check looks for each 4-digit test PIN as plain text anywhere in the device's storage, which holds numbers that change
  with time and at random: the unlock record's expiry in milliseconds (`access.js`, `localUntil`), the session's expiry
  in seconds, tokens and ids (seen: `1792688861403`, `1792691566`, `73234184`…). A PIN inside one of them fails the
  check without any PIN being kept (at 16:43:11 UTC, for example, the time in seconds ended in `7391`, the test owner's
  PIN). What the pages keep is the unlock record (token, expiry, name, role), the unlocking person's id, the station,
  the language, the session and the recipe draft, never a PIN. A test-only fix (match a PIN only as a whole number, not
  inside a longer one) is proposed, not made: this commit is documentation only.
- **Records:** this entry, the D-050 row of `docs/CHECKLIST.md` (commit `c1d9fb5`, live), the release runbook row,
  and `docs/PRODUCTION-READINESS.md` (live site `0ad8c88`, releases, public check). Documentation only, committed with
  the owner's authorization of 2026-10-22. Nothing merged, tagged or published from here.

## D-052 · 2026-10-23 · PIN boxes are not password boxes, and an unlock never outlives its login

- **Why:** the new café login (`+cafe`), tried in a private window on the owner's computer, showed «Áreas de dueños
  abiertas · Jorge · hasta las 13:23». The log (the owner's read-only query) holds a real opening: Jorge, manager
  role, on the café login, 11:09 → 11:24 Costa Rica time. The owner typed only the email and the password. Code review
  and local tests: nothing opens unless the right PIN is sent from that browser, and an unlock only counts for the
  login that made it (`_unlock_staff`: `user_id = auth.uid()`). So the PIN was sent from that browser profile. The
  most likely cause is inferred, not proven. Every PIN box was `type="password"`, which browsers and password managers
  take for a password (they ignore `autocomplete="off"` there). The team editor's name + PIN + repeat looks like a
  sign-up form, so a PIN saved from it could be filled into the PIN screen and sent by an Enter, a click or «fill and
  send». «Jorge» was preselected because the browser kept the last person who opened (`hg-unlock-who`) across logins.
  The 13:23: the notice uses the device's clock and time zone, and that device was 2 hours ahead of Costa Rica (for
  example US Eastern time); reproduced locally.
- **Change (pages only, no database change):**
  - **The 19 PIN boxes are plain boxes drawn as dots:** POS 8, Inventory 3, Sales 1, the time clock 6 (the team editor
    included) and the PIN screen of `access.js`. They use `type="text"`, `data-pin`, `-webkit-text-security: disc` (in
    `keypad.js`, `access.js` and each page's own CSS) and `autocomplete="off"`. They also carry the opt-outs of the
    common password managers (`data-1p-ignore`, `data-lpignore`, `data-bwignore`, `data-form-type="other"`). Browsers
    no longer offer to save a PIN or fill one in. A browser that cannot draw the dots keeps a password box
    (`keypad.js`, via `CSS.supports`), still guarded as below. A PIN cannot be copied, cut or dragged out of its box,
    as from a password box.
  - **Only a PIN a person enters counts (`keypad.js`).**
    - What counts: a real key, a phone keyboard, Backspace, paste, drop or undo, seen as a trusted `beforeinput`
      followed by exactly that change (same box and kind; a typed key also with the same text). The person's taps on
      the on-screen keys also count: `keypad.js`'s own keys, and the time clock's own keys through
      `HG_KEYPAD.pinTyped`.
    - What is wiped at once: an "input" with no key (autofill, `execCommand`, an extension), a value with no event,
      `:autofill`, a key typed on top of such a value, a key mark left by a key that changed nothing (a 9th digit),
      and on-screen keys pressed by a script.
    - A box the page has emptied keeps nothing typed before.
  - **What does not go (`keypad.js`).** A form does not go while one of its PIN boxes holds a PIN nobody typed: not by
    Enter, a click or the on-screen ✓ (`requestSubmit`). The same holds for a button that reads the PIN itself: the
    box's own button (`data-keypad-ok`), a cash move's Void, or a shift's Delete. A click in the PIN box's window is
    stopped too. So such a PIN, or even an empty one (a wrong try), never reaches the database.
  - **An unlock belongs to its login (`access.js`, `pos.html`).**
    - `hg-unlock-login` (new) names the login signed in on this device. The unlock and the people remembered (who
      opened the owner areas last, who opened or closed the register last: `hg-pos-reg-staff`) belong to it.
    - Signing out (SIGNED_OUT), or any other login, takes the notice down at once with no reload, and forgets the
      unlock and the people remembered. This also holds in another tab of the same browser, and when the other tab
      forgot first.
    - The remembered person is offered first only to the login that kept it (`HG_ACCESS.who()`, also used by
      Inventory).
    - The POS fills its register lists again after a change of login on the same page.
    - A late "what is open here" answer for the login just gone is never shown, and the notice also goes whenever the
      database says no PIN unlock is open.
- **Unchanged:**
  - the database and the PIN rules (5 tries → 10 minutes, 15 minutes open, who may open);
  - the POS offline;
  - typing the PIN on the keyboard, the on-screen keys or a phone keyboard;
  - no new text on screen.
  - With an owner-role PIN (an owner's own staff PIN) the tablet still opens the owner areas and Sales for 15 minutes,
    as decided in D-022. The planned owner PIN on personal logins (not authorized yet) is what will keep owner PINs off
    shared tablets.
- **Known limits (accepted):**
  - **Typing tools that set the text in one go** (Android Voice Access «type 1234», switch access) are wiped like any
    other fill. Nobody at the café is known to use them; allowing them would weaken the guard, and that choice is the
    owner's.
  - **Anything the browser reports as a real key counts as a person:** an operating-system tool that types keystrokes
    (KeePass auto-type), or a remote-control session.
  - **A sign-out on a page that never checks the owner areas** (the kitchen screen, Accounting, the password reset page)
    only takes effect on the next staff page. With the same login, an unlock still open (at most 15 minutes) is kept; with another login, it is
    forgotten there.
  - **The first requests a page sends before its first check** can still carry another login's unlock token. The
    database ignores it for any other login (SQL 380, section 2), and from that check on nothing carries it.
  - Only Chromium was tested here. Safari draws the dots the same way; Firefox gets the password-box fallback if it
    cannot. Check one PIN on each café tablet after publishing.
- **Seen, not changed (older behaviour):** the POS operator who rings the sales (`hg-pos-operator`) is also kept across
  logins on a device, and the database does not tie it to a login. It names who rang a sale and opens nothing.
- **Once, after publishing:** an unlock or remembered person saved by the older pages has no login attached, so it is
  forgotten on the first load. An open unlock (at most 15 minutes) needs its PIN again, and the lists start at the top
  once.
- **For the owner, on the device that showed the opening:**
  - remove any saved password for hanginggardencafe.com other than the login;
  - give Jorge a new PIN.
  - The tablet transition (E-05) stays paused until these pages are published.
- **Reviews:** an independent review and then a four-lens review (bypass, legitimate use, login binding, test
  validity), each serious finding checked by a separate skeptic. Fixed from them:
  - the buttons that read a PIN themselves;
  - the leftover key mark;
  - a key on top of a fill;
  - paste with a line break, and digits dropped while composing;
  - script-pressed on-screen keys;
  - the emptied box;
  - the late answer after sign-out;
  - the other tab;
  - the POS register person (stored and on screen).
  No bypass by a browser fill or a password manager was found.
- **Tests:**
  - **SQL `380_cafe_never_owner` (27):** the café login alone, with a phone code, with another login's unlock (both
    ways), with a manager PIN and with an owner-role PIN never gets `owner_with_code`, the books, the bank, pay rates,
    settings, tax rates or accountant access. A manager PIN gives the manager level only, and an owner-role PIN the
    tablet's owner areas only. The log names who and which login; Lock closes it.
  - **Browser `340_pin_autofill` (14):** each protection above, and each way a person enters a PIN (keys, the touch
    pad and ✓, the time clock's keys, a phone keyboard, Backspace and undo, paste).
  - **How the tests were checked:**
    - The first tests failed on the pages before this change.
    - Each protection, taken out of a copy of the pages one at a time, makes at least one test fail (mutation check, 14
      cases).
    - The three checks against a leftover key mark overlap: the key's release, the next tick, and the exact match.
      Taking out the release together with either of the others makes a test fail.
    - The full `tests/run.sh` passes.
- **Records:** this entry and the checklist row. Prepared and tested locally on 2026-10-23; not committed, not
  published. Waiting on the owner's authorization.
