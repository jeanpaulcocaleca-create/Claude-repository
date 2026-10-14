#!/usr/bin/env bash
# Canopy OS rehearsal · the pages on the copy that went through the one-time reset and then every migration
# (database ${REHEARSAL_DB:-canopy_rehearsal}_reset, left by tests/rehearsal/run.sh step 10): first the pages LIVE on the
# café's site today (tests/rehearsal/live-pages.sh, the same checks as on the main copy), then the NEW pages in website/
# on the empty café and its first real day (tests/rehearsal/reset-pages/*.spec.js). Drops the copy when everything passed.
# Usage: tests/rehearsal/reset-pages.sh      (after run.sh; local/CI test server only)
#        E2E_SITE_PORT / E2E_PGRST_PORT / E2E_SUFFIX pick other ports and database names (another run on the same machine)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/tests/pg.sh"
DB="${REHEARSAL_DB:-canopy_rehearsal}_reset"
[ "$(psql -X -At -d postgres -c "select count(*) from pg_database where datname = '$DB'")" = "1" ] \
  || { echo "  FAIL  $DB does not exist: run tests/rehearsal/run.sh first"; exit 1; }
[ "$(psql -X -At -d "$DB" -c "select count(*) from public.orders")" = "0" ] || { echo "  FAIL  $DB is not the reset copy (it has sales)"; exit 1; }
echo "  · the live pages on the reset copy (empty café, migrated)"
t0=$(date +%s)
REHEARSAL_DB="$DB" bash "$HERE/live-pages.sh"
echo "  · the new pages on the empty café and its first day"
E2E_TEMPLATE_DB="$DB" E2E_SITE_ROOT="$ROOT/website" E2E_SPECS_DIR="$HERE/reset-pages" node "$ROOT/tests/e2e/run.js"
psql -X -q -d postgres -c "drop database if exists \"$DB\" with (force)" >/dev/null
echo "  ok    pages on the reset copy ($(( $(date +%s) - t0 ))s; $DB dropped)"
