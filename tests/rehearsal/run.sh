#!/usr/bin/env bash
# =====================================================================================================
# Canopy OS · migration rehearsal on a representative copy of production as it is BEFORE migration 0000.
#   1. builds the schema production has (the historical scripts) and fills it with ~4 months of café history
#      (tests/rehearsal/seed-legacy.sql)
#   2. read-only snapshot + consistency check (the same files the owner runs in production)
#   3. a backup with its restore test (content fingerprints), like the owner's first backup
#   4. applies every migration, one transaction per file, as a NON-superuser account like Supabase's SQL Editor,
#      timing each one
#   5. snapshot + consistency again: nothing that existed may change; structure and security as expected
#   6. today's work after the window: the old pages' way of saving a sale (and an offline sale queued before the
#      window) and the new pages' way, then the checks again
#   7. the accountant books 30 days of the old history: balanced and tied to the sales, colón for colón
#   8. a backup + restore of the migrated copy
#   9. the staging copy as the owner's "Ensayo en pruebas" makes it: anonymized, permissions identical, migrated
# Usage: tests/rehearsal/run.sh            (local/CI test server only; prints a summary, keeps files in $OUT)
# =====================================================================================================
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/tests/pg.sh"
DB="${REHEARSAL_DB:-canopy_rehearsal}"
OUT="${REHEARSAL_OUT:-$(mktemp -d)}"; mkdir -p "$OUT"
q() { psql -X -q -At -v ON_ERROR_STOP=1 -d "$DB" "$@"; }
step() { echo "  · $*"; }
die() { echo "  FAIL  rehearsal: $*"; exit 1; }

step "legacy schema + representative history"
CANOPY_LEGACY_ONLY=1 "$ROOT/tests/build-db.sh" "$DB" >/dev/null
t0=$(date +%s)
q -f "$HERE/seed-legacy.sql" > "$OUT/seed.log" 2>&1 || { cat "$OUT/seed.log"; die "seed"; }
q -f "$HERE/as-supabase.sql" > /dev/null
echo "    seeded in $(( $(date +%s) - t0 ))s: $(q -c "select count(*) || ' orders, ' || (select count(*) from public.order_items) || ' items, ' || (select count(*) from public.stock_moves) || ' stock moves, ' || (select count(*) from public.time_entries) || ' shifts' from public.orders")"

# a frozen copy of "production before the window", for the staging-copy rehearsal at the end
psql -X -q -d postgres -c "drop database if exists ${DB}_src with (force)" -c "create database ${DB}_src template $DB" >/dev/null

step "snapshot and consistency BEFORE"
q -f "$ROOT/supabase/tools/production-snapshot.sql" > "$OUT/snapshot-before.json"
q -f "$ROOT/supabase/tools/consistency-check.sql" > "$OUT/consistency-before.json"
python3 - "$OUT/snapshot-before.json" <<'PY' || die "the snapshot does not recognise the legacy schema"
import json, sys
s = json.load(open(sys.argv[1]))
assert s['migrations_applied'] == 'none: 0000 not applied', s['migrations_applied']
sc = s['schema']
for k in ('functions_unknown', 'functions_changed', 'functions_missing_legacy', 'tables_missing', 'live_pages_rpc_missing'):
    assert sc[k] == [], (k, sc[k])
assert sc['tables_columns_differ'] == {}, sc['tables_columns_differ']
assert sc['functions_by_version'] == {'legacy': sc['functions_total']}, sc['functions_by_version']
assert any('categories color for signed-in' in p for p in s['security']['policies_without_account_check']), 'the open menu rule should exist before 0001'
PY

if command -v age >/dev/null; then
  step "backup BEFORE the migrations (account from supabase/tools/backup-account.sql, restore test)"
  # as the owner does it: in the SQL Editor (not a superuser)
  PGPASSWORD=rehearsal-only psql -X -q -At -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -U rehearsal_editor -d "$DB" \
    -f "$ROOT/supabase/tools/backup-account.sql" -c "alter role canopy_backup login password 'test-only-backup'" > "$OUT/account.log" 2>&1 \
    || { cat "$OUT/account.log"; die "backup account as the SQL Editor account"; }
  grep -q '^lista' "$OUT/account.log" || { cat "$OUT/account.log"; die "backup account not ready"; }
  age-keygen -o "$OUT/k" 2>/dev/null
  URL_BASE="postgresql://postgres@${PGHOST}:${PGPORT}"; [ -n "${PGPASSWORD:-}" ] && URL_BASE="postgresql://postgres:${PGPASSWORD}@${PGHOST}:${PGPORT}"
  t0=$(date +%s)
  CANOPY_DB_URL="postgresql://canopy_backup:test-only-backup@${PGHOST}:${PGPORT}/$DB" AGE_RECIPIENTS="$(age-keygen -y "$OUT/k")" \
    RESTORE_TEST_URL="$URL_BASE/postgres" UPLOAD_DIR="$OUT/backup-before" BACKUP_SOURCE=manual \
    bash "$ROOT/ops/backup/backup.sh" > "$OUT/backup-before.log" 2>&1 || { cat "$OUT/backup-before.log"; die "backup before"; }
  grep -q 'restauración: passed' "$OUT/backup-before.log" || die "restore test before"
  echo "    $(grep -o 'restauración verificada[^;]*; contenido idéntico en [0-9]* tablas' "$OUT/backup-before.log") ($(( $(date +%s) - t0 ))s)"
fi

step "migrations 0000-$(ls "$ROOT/supabase/migrations"/*.sql | tail -1 | xargs basename | cut -c1-4), each in one transaction, as the SQL Editor account (not a superuser)"
: > "$OUT/timings.txt"
for m in $(ls "$ROOT/supabase/migrations"/*.sql | sort); do
  s=$(date +%s%N)
  if ! PGPASSWORD=rehearsal-only psql -X -q -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -U rehearsal_editor -d "$DB" --single-transaction -f "$m" > "$OUT/m.log" 2>&1; then
    cat "$OUT/m.log"; die "$(basename "$m") failed"
  fi
  printf '%s %s ms\n' "$(basename "$m" .sql)" "$(( ($(date +%s%N) - s) / 1000000 ))" >> "$OUT/timings.txt"
done
echo "    applied $(wc -l < "$OUT/timings.txt") migrations in $(awk '{s+=$2} END {printf "%.1f", s/1000}' "$OUT/timings.txt")s; slowest: $(sort -k2 -n -r "$OUT/timings.txt" | head -3 | awk '{printf "%s %s ms; ", $1, $2}')"

step "snapshot and consistency AFTER"
q -f "$ROOT/supabase/tools/production-snapshot.sql" > "$OUT/snapshot-after.json"
q -f "$ROOT/supabase/tools/consistency-check.sql" > "$OUT/consistency-after.json"
q -f "$ROOT/supabase/tools/release-check.sql" > "$OUT/release-check.json"
python3 "$HERE/compare.py" "$OUT" after || die "differences after the migrations (see above)"

step "the day after the window: old pages, a sale queued offline before the window, new pages"
q -f "$HERE/after-window.sql" > "$OUT/after-window.log" 2>&1 || { cat "$OUT/after-window.log"; die "work after the window"; }
q -f "$ROOT/supabase/tools/consistency-check.sql" > "$OUT/consistency-day-after.json"
python3 "$HERE/compare.py" "$OUT" day-after || die "checks after a day of work"

step "the accountant books the last 30 days of the old history (no tax stamps): balanced, tied to the sales"
q -f "$HERE/books.sql" > "$OUT/books.log" 2>&1 || { cat "$OUT/books.log"; die "books"; }
echo "    $(grep -o 'books: .*' "$OUT/books.log" | head -1)"

if command -v age >/dev/null; then
  step "backup + restore test of the migrated copy (the backup account still reads everything)"
  CANOPY_DB_URL="postgresql://canopy_backup:test-only-backup@${PGHOST}:${PGPORT}/$DB" AGE_RECIPIENTS="$(age-keygen -y "$OUT/k")" \
    RESTORE_TEST_URL="$URL_BASE/postgres" UPLOAD_DIR="$OUT/backup-after" BACKUP_SOURCE=manual \
    bash "$ROOT/ops/backup/backup.sh" > "$OUT/backup-after.log" 2>&1 || { cat "$OUT/backup-after.log"; die "backup after"; }
  grep -q 'restauración: passed' "$OUT/backup-after.log" || die "restore test after"
  [ "$(q -c "select status || '/' || restore_test from canopy.backup_runs order by id desc limit 1")" = "ok/passed" ] || die "backup run not recorded after 0002"
  echo "    $(grep -o 'restauración verificada[^;]*; contenido idéntico en [0-9]* tablas' "$OUT/backup-after.log")"
fi
step "staging copy: production (read-only account) -> anonymized -> an empty Supabase-like project -> migrations there"
psql -X -q -d postgres -c "drop database if exists ${DB}_staging with (force)" -c "create database ${DB}_staging" >/dev/null
psql -X -q -d "${DB}_staging" -f "$ROOT/ops/backup/restore-stub.sql" >/dev/null
q -c "alter role canopy_backup login password 'test-only-backup'" > /dev/null
URL_BASE="postgresql://postgres@${PGHOST}:${PGPORT}"; [ -n "${PGPASSWORD:-}" ] && URL_BASE="postgresql://postgres:${PGPASSWORD}@${PGHOST}:${PGPORT}"
CANOPY_DB_URL="postgresql://canopy_backup:test-only-backup@${PGHOST}:${PGPORT}/${DB}_src" STAGING_DB_URL="$URL_BASE/${DB}_staging" \
  STAGING_PIN=2468 PROD_URL="https://nbvczarfweanoxvdqplk.supabase.co" SCRATCH_URL="$URL_BASE/postgres" PUBLIC_DIR="$ROOT" OUT="$OUT/staging" \
  bash "$ROOT/ops/backup/repositorio-respaldos/ensayo.sh" > "$OUT/staging.log" 2>&1 || { cat "$OUT/staging.log"; die "staging copy"; }
python3 "$HERE/compare.py" "$OUT/staging" after || die "staging copy: differences after the migrations"
[ "$(psql -X -At -d "${DB}_staging" -c "select count(*) from public.staff where name !~ '^Persona [0-9]+$'")" = "0" ] || die "staging copy: names not anonymized"
[ "$(psql -X -At -d "${DB}_staging" -c "select count(*) from public.orders where guest_phone is not null")" = "0" ] || die "staging copy: guest phones kept"
psql -X -q -d postgres -c "drop database if exists ${DB}_src with (force)" -c "drop database if exists ${DB}_staging with (force)" >/dev/null
echo "  ok    migration rehearsal (files in $OUT)"
