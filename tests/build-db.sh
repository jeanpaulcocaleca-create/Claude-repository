#!/usr/bin/env bash
# Canopy OS tests · build a fresh test database the way production was built:
#   Supabase look-alike -> reconstructed base tables -> the 18 historical scripts (legacy-order.txt)
#   -> every migration in supabase/migrations (in order) -> test seed data.
# Usage: tests/build-db.sh [dbname]        (default: canopy_test)
# Never point this at a real Supabase project: it drops and recreates the database.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=/dev/null
source "$HERE/pg.sh"
DB="${1:-canopy_test}"

case "$PGHOST" in
  127.0.0.1|localhost|/*|postgres) ;;
  *) echo "Refusing to build a test database on $PGHOST (only local/CI servers)"; exit 2;;
esac

psql -q -X -d postgres -v ON_ERROR_STOP=1 -c "drop database if exists \"$DB\" with (force)" -c "create database \"$DB\""
run() {  # file, label, [extra psql flags]
  if ! psql -q -X -d "$DB" -v ON_ERROR_STOP=1 ${3:-} -f "$1" > /tmp/canopy-build.log 2>&1; then
    echo "FAILED while applying $2"; cat /tmp/canopy-build.log; exit 1
  fi
}
run "$HERE/db/00_supabase_stub.sql" "supabase stub"
# roles are shared by every database of a test server: older runs (backup-account.sql version 1, the old 0002) left
# the shared backup account a member of pg_read_all_data. Neither does that any more (D-033); take it away here, as
# the superuser, so a reused local server tests what production gets (a fresh CI server never has it)
psql -q -X -d "$DB" -v ON_ERROR_STOP=1 -c "do \$\$ declare g text; begin
  for g in select grantor::regrole::text from pg_auth_members where member = to_regrole('canopy_backup') and roleid = 'pg_read_all_data'::regrole loop
    execute format('revoke pg_read_all_data from canopy_backup granted by %s', g);
  end loop; end \$\$;" >/dev/null
run "$HERE/db/01_base_tables.sql" "base tables"
while read -r f; do
  f="${f%%#*}"; f="$(echo "$f" | xargs)"; [ -z "$f" ] && continue
  run "$ROOT/supabase/$f" "legacy $f"
done < "$HERE/db/legacy-order.txt"
# CANOPY_LEGACY_ONLY=1: stop after the historical scripts (production as it is before migration 0000)
if [ -n "${CANOPY_LEGACY_ONLY:-}" ]; then echo "built $DB (legacy only)"; exit 0; fi
if [ -d "$ROOT/supabase/migrations" ]; then
  for m in $(ls "$ROOT/supabase/migrations"/*.sql 2>/dev/null | sort); do
    # one transaction per file, like a paste into the Supabase SQL Editor
    run "$m" "migration $(basename "$m")" --single-transaction
  done
fi
[ -f "$HERE/db/90_seed.sql" ] && run "$HERE/db/90_seed.sql" "test seed"
echo "built $DB"
