#!/usr/bin/env bash
# =====================================================================================================
# Canopy OS · migration rehearsal on a representative copy of production as it is BEFORE migration 0000.
#   1. builds the schema production has (the historical scripts, plus production's own audit_menu() text:
#      tests/rehearsal/production-drift.sql) and fills it with ~4 months of café history
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
#   9. the staging copy as the owner's "Ensayo en pruebas" makes it: anonymized, permissions identical, migrated;
#      then again into the same project, emptied first under Supabase Storage's delete guard
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
q -f "$HERE/production-drift.sql" > "$OUT/drift.log" 2>&1 || { cat "$OUT/drift.log"; die "production's audit_menu text"; }
t0=$(date +%s)
q -f "$HERE/seed-legacy.sql" > "$OUT/seed.log" 2>&1 || { cat "$OUT/seed.log"; die "seed"; }
q -f "$HERE/as-supabase.sql" > /dev/null
echo "    seeded in $(( $(date +%s) - t0 ))s: $(q -c "select count(*) || ' orders, ' || (select count(*) from public.order_items) || ' items, ' || (select count(*) from public.stock_moves) || ' stock moves, ' || (select count(*) from public.time_entries) || ' shifts' from public.orders")"

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
assert sc['triggers_differ'] == {}, sc['triggers_differ']
assert sc['functions_by_version'] == {'legacy': sc['functions_total']}, sc['functions_by_version']
assert any('categories color for signed-in' in p for p in s['security']['policies_without_account_check']), 'the open menu rule should exist before 0001'
PY

step "backup account (supabase/tools/backup-account.sql) as the SQL Editor account (not a superuser)"
# as the owner does it, once, before the window; it reads only what it was given in THIS database (D-033)
PGPASSWORD=rehearsal-only psql -X -q -At -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -U rehearsal_editor -d "$DB" \
  -f "$ROOT/supabase/tools/backup-account.sql" -c "alter role canopy_backup login password 'test-only-backup'" > "$OUT/account.log" 2>&1 \
  || { cat "$OUT/account.log"; die "backup account as the SQL Editor account"; }
grep -q '^lista: la cuenta canopy_backup' "$OUT/account.log" || { cat "$OUT/account.log"; die "backup account not ready"; }
echo "    $(grep '^lista' "$OUT/account.log")"
# a frozen copy of "production before the window" (backup account included), for the staging-copy rehearsal at the end
psql -X -q -d postgres -c "drop database if exists ${DB}_src with (force)" -c "create database ${DB}_src template $DB" >/dev/null

if command -v age >/dev/null; then
  step "backup BEFORE the migrations (restore test)"
  age-keygen -o "$OUT/k" 2>/dev/null
  URL_BASE="postgresql://postgres@${PGHOST}:${PGPORT}"; [ -n "${PGPASSWORD:-}" ] && URL_BASE="postgresql://postgres:${PGPASSWORD}@${PGHOST}:${PGPORT}"
  t0=$(date +%s)
  CANOPY_DB_URL="postgresql://canopy_backup:test-only-backup@${PGHOST}:${PGPORT}/$DB" AGE_RECIPIENTS="$(age-keygen -y "$OUT/k")" \
    RESTORE_TEST_URL="$URL_BASE/postgres" UPLOAD_DIR="$OUT/backup-before" BACKUP_SOURCE=manual \
    bash "$ROOT/ops/backup/backup.sh" > "$OUT/backup-before.log" 2>&1 || { cat "$OUT/backup-before.log"; die "backup before"; }
  grep -q 'restauración: passed' "$OUT/backup-before.log" || die "restore test before"
  echo "    $(grep -o 'restauración verificada[^;]*; contenido idéntico en [0-9]* tablas' "$OUT/backup-before.log") ($(( $(date +%s) - t0 ))s)"
fi

# production's audit_menu() (D-031): accepted as it is, so no migration may touch its text, settings or owner. The
# snapshot cannot see that (a rewrite to another known body would still read 'legacy'): compared here
AUDIT_MENU="select md5(prosrc) || ' definer=' || prosecdef || ' ' || coalesce(array_to_string(proconfig, ','), '-') || ' owner=' || pg_get_userbyid(proowner) from pg_proc where oid = 'public.audit_menu()'::regprocedure"
audit_menu_before=$(q -c "$AUDIT_MENU")
[[ "$audit_menu_before" == "4807ea7301cd2ae6fe56052d3a165352 definer=true search_path=public owner="* ]] \
  || die "audit_menu() before the migrations is not production's: $audit_menu_before"

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
audit_menu_after=$(q -c "$AUDIT_MENU")
[ "$audit_menu_after" = "$audit_menu_before" ] || die "a migration changed audit_menu() (production's, D-031): $audit_menu_before -> $audit_menu_after"

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
  step "backup + restore test of the migrated copy (the backup account reads the tables 0002-0027 added too)"
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
# a staging project has no menu-photos bucket: only the café's schemas are copied, never Storage
psql -X -q -d "${DB}_staging" -c "delete from storage.buckets where id = 'menu-photos'" >/dev/null
q -c "alter role canopy_backup login password 'test-only-backup'" > /dev/null
URL_BASE="postgresql://postgres@${PGHOST}:${PGPORT}"; [ -n "${PGPASSWORD:-}" ] && URL_BASE="postgresql://postgres:${PGPASSWORD}@${PGHOST}:${PGPORT}"
ensayo() {  # out-dir [extra variables]
  env CANOPY_DB_URL="postgresql://canopy_backup:test-only-backup@${PGHOST}:${PGPORT}/${DB}_src" STAGING_DB_URL="$URL_BASE/${DB}_staging" \
    STAGING_PIN=2468 PROD_URL="https://nbvczarfweanoxvdqplk.supabase.co" SCRATCH_URL="$URL_BASE/postgres" SCRATCH_DB="${DB}_ensayo" \
    PUBLIC_DIR="$ROOT" OUT="$1" "${@:2}" bash "$ROOT/ops/backup/repositorio-respaldos/ensayo.sh"
}
ensayo "$OUT/staging" > "$OUT/staging.log" 2>&1 || { cat "$OUT/staging.log"; die "staging copy"; }
python3 "$HERE/compare.py" "$OUT/staging" after || die "staging copy: differences after the migrations"
[ "$(psql -X -At -d "${DB}_staging" -c "select count(*) from public.staff where name !~ '^Persona [0-9]+$'")" = "0" ] || die "staging copy: names not anonymized"
[ "$(psql -X -At -d "${DB}_staging" -c "select count(*) from public.orders where guest_phone is not null")" = "0" ] || die "staging copy: guest phones kept"
[ "$(psql -X -At -d "${DB}_staging" -c "select count(nullif(btrim(note), '')) from public.orders")" = "0" ] || die "staging copy: order notes (orders.note) kept"
# a migration that adds a text column must classify it in anonimizar.sql (which refuses an unknown one): run it on a
# copy of the migrated database, which has every table of the window
psql -X -q -d postgres -c "drop database if exists ${DB}_anon with (force)" -c "create database ${DB}_anon template $DB" >/dev/null
psql -X -q -At -v ON_ERROR_STOP=1 -v VERBOSITY=terse -v pin=2468 -d "${DB}_anon" -f "$ROOT/ops/backup/repositorio-respaldos/anonimizar.sql" > "$OUT/anon-migrated.log" 2>&1 \
  || { cat "$OUT/anon-migrated.log"; die "anonimizar.sql does not know every text column after the migrations"; }
[ "$(psql -X -At -d "${DB}_anon" -c "select count(*) from acct.entries where created_by ~ '@'")" = "0" ] || die "anonymized migrated copy: emails kept"
psql -X -q -d postgres -c "drop database if exists ${DB}_anon with (force)" >/dev/null

step "staging copy again into the same project (emptied first), under Supabase Storage's delete guard"
# storage-api migration 0055: a statement-level trigger refuses any direct delete from the Storage tables, even one
# that matches no row, unless storage.allow_delete_query is 'true'
psql -X -q -v ON_ERROR_STOP=1 -d "${DB}_staging" >/dev/null <<'SQL'
create function storage.protect_delete() returns trigger language plpgsql as $$
begin
  if coalesce(current_setting('storage.allow_delete_query', true), 'false') <> 'true' then
    raise exception 'Direct deletion from storage tables is not allowed. Use the Storage API instead.' using errcode = '42501';
  end if;
  return null;
end $$;
create trigger protect_objects_delete before delete on storage.objects for each statement execute function storage.protect_delete();
create trigger protect_buckets_delete before delete on storage.buckets for each statement execute function storage.protect_delete();
SQL
{ psql -X -q -d "${DB}_staging" -c "delete from storage.objects where false" 2>&1 || true; } | grep -q 'Direct deletion from storage tables is not allowed' \
  || die "the Storage delete guard is not in place"
ensayo "$OUT/staging-again" EMPTY_STAGING=si > "$OUT/staging-again.log" 2>&1 || { cat "$OUT/staging-again.log"; die "staging copy again (emptied first)"; }
[ "$(wc -l < "$OUT/staging-again/timings.txt")" = "$(ls "$ROOT/supabase/migrations"/*.sql | wc -l)" ] || die "staging copy again: not every migration ran again"
python3 "$HERE/compare.py" "$OUT/staging-again" after || die "staging copy again: differences after the migrations"
psql -X -q -d postgres -c "drop database if exists ${DB}_src with (force)" -c "drop database if exists ${DB}_staging with (force)" >/dev/null
echo "  ok    migration rehearsal (files in $OUT)"
