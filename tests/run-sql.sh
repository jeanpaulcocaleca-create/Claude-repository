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
# 0038's two-connection checks (committed rows, several connections at once): on a database of their own, built and
# dropped by the script; after the SQL files when no pattern is given (or when the pattern names them)
c="concurrency-descuentos"
if [ -z "${1:-}" ] || [[ "$c" == *"$1"* ]]; then
  if out=$(bash "$HERE/sql/$c.sh" "$DB" 2>&1); then
    n=$(echo "$out" | grep -Eo '[0-9]+ passed' | tail -1 || true)
    echo "  ok    $c ${n:+($n)}"; pass=$((pass+1))
  else
    echo "  FAIL  $c"; echo "$out" | grep -E 'FAIL|ERROR|failed' | sed 's/^/        /' | head -40
    fail=$((fail+1)); failed+=("$c")
  fi
fi
# 0039/0040's two-connection checks (Proveedores: two deliveries or payments at once, never twice, no deadlock): the same way
c="concurrency-proveedores"
if [ -z "${1:-}" ] || [[ "$c" == *"$1"* ]]; then
  if out=$(bash "$HERE/sql/$c.sh" "$DB" 2>&1); then
    n=$(echo "$out" | grep -Eo '[0-9]+ passed' | tail -1 || true)
    echo "  ok    $c ${n:+($n)}"; pass=$((pass+1))
  else
    echo "  FAIL  $c"; echo "$out" | grep -E 'FAIL|ERROR|failed' | sed 's/^/        /' | head -40
    fail=$((fail+1)); failed+=("$c")
  fi
fi
echo "SQL tests: $pass passed, $fail failed${failed:+ (${failed[*]})}"
[ "$fail" -eq 0 ]
