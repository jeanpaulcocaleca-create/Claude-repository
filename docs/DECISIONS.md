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
