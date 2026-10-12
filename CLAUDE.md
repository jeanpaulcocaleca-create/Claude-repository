# Canopy OS — rules for AI agents working in this repository

The Hanging Garden Café (Monteverde, Costa Rica) runs its real business on this code:
POS, kitchen screen, TV menu board, QR menu, inventory, time clock, accounting.
The owner's directives (2026-10-12) are binding. In short:

## Never
- Never publish to production. Do not run the "Publish website (PRODUCTION · manual only)"
  workflow, never create or move `v*` release tags, never approve deployments, never change
  GitHub Pages, branch-protection, environment or secret settings.
- Never connect to, query or change the production Supabase database. All database work
  happens in local test databases or the staging project. Production migrations are
  prepared as files in `supabase/migrations/` and applied by the owner.
- Never ask for, print, commit or store passwords, PINs, service-role keys, database
  connection strings, Hacienda credentials or API tokens. The public anon key in
  `website/config.js` is public by design; nothing else secret belongs in this public repo.
- Never activate unverified tax, e-invoicing or payroll rules. Regulated features ship
  disabled behind owner/accountant-controlled settings.
- Never delete or rewrite business records (orders, payments, stock moves, time entries,
  journal entries, audit log). Corrections are new records (reversals, refunds, adjustments).
- Never run the files in `supabase/` root (the 18 historical scripts). They are history.

## Always
- Read `docs/CHECKLIST.md` (master checklist), `docs/DECISIONS.md` (decision log) and
  `docs/DEPENDENCIES.md` (owner/accountant blockers) before starting work, and keep them
  current.
- New database changes go in a new numbered file in `supabase/migrations/` using the
  template in `docs/MIGRACIONES.md`. Migrations are additive first (expand), tightening
  later (contract), and must keep older pages and offline-queued sales working.
- Run `tests/run.sh` (SQL + browser tests) before every commit. Do not commit failing work.
- Preserve the existing design (colors, layout, navigation). Staff-facing text is Spanish
  first; add English source strings to `website/lang.js` like the rest of the site.
- The POS must keep working offline. The server never refuses money already taken: it
  records it and flags problems for a manager.
