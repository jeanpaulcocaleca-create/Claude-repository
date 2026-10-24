#!/usr/bin/env bash
# Canopy OS · SQL tests. Builds a fresh test database, then runs every tests/sql/*.test.sql
# (each file in its own transaction, rolled back at the end).
# Usage: tests/run-sql.sh [pattern]     e.g. tests/run-sql.sh ledger
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "$HERE/pg.sh"
DB="${CANOPY_TEST_DB:-canopy_test}"
if [ -z "${SKIP_BUILD:-}" ]; then "$HERE/build-db.sh" "$DB" >/dev/null; fi
psql -q -X -d "$DB" -v ON_ERROR_STOP=1 -f "$HERE/sql/_helpers.sql" >/dev/null

pass=0; fail=0; failed=()
for t in $(ls "$HERE"/sql/*.test.sql | sort); do
  name="$(basename "$t" .test.sql)"
  if [ -n "${1:-}" ] && [[ "$name" != *"$1"* ]]; then continue; fi
  if out=$(psql -X -q -d "$DB" -v ON_ERROR_STOP=1 -c "truncate test.results restart identity" -f "$t" 2>&1); then
    n=$(echo "$out" | grep -Eo '[0-9]+ passed' | tail -1 || true)
    echo "  ok    $name ${n:+($n)}"; pass=$((pass+1))
  else
    echo "  FAIL  $name"; echo "$out" | grep -E 'FAIL|ERROR|failed' | sed 's/^/        /' | head -40
    fail=$((fail+1)); failed+=("$name")
  fi
done
echo "SQL tests: $pass passed, $fail failed${failed:+ (${failed[*]})}"
[ "$fail" -eq 0 ]
