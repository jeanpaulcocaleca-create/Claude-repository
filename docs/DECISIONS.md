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
