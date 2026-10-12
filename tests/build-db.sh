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
run "$HERE/db/01_base_tables.sql" "base tables"
while read -r f; do
  f="${f%%#*}"; f="$(echo "$f" | xargs)"; [ -z "$f" ] && continue
  run "$ROOT/supabase/$f" "legacy $f"
done < "$HERE/db/legacy-order.txt"
if [ -d "$ROOT/supabase/migrations" ]; then
  for m in $(ls "$ROOT/supabase/migrations"/*.sql 2>/dev/null | sort); do
    # one transaction per file, like a paste into the Supabase SQL Editor
    run "$m" "migration $(basename "$m")" --single-transaction
  done
fi
[ -f "$HERE/db/90_seed.sql" ] && run "$HERE/db/90_seed.sql" "test seed"
echo "built $DB"
