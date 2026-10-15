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
#  10. the one-time operational reset of the test period (supabase/tools/reinicio-operativo.sql, D-038) on a second
#      copy of "production before the window": every refusal stops it and changes nothing (migrated database, café
#      still working, register open, the paste as shipped, the wrong word, a second run); the real run as ONE query
#      like the SQL Editor sends it, after supabase/tools/resumen-pruebas.sql; what it clears is empty, the stock at
#      zero, what it keeps identical (snapshot fingerprints), one log line with the accountant's summary; then every
#      migration on that copy and the checks of 5 (compare.py reset fixture: every one of the 14 cleared tables had a
#      row to clear; compare-selftest.py: the comparison's branches on crafted copies of these files). The copy
#      ${DB}_reset stays for tests/rehearsal/reset-pages.sh (the live pages and the new pages on the empty café), which drops it
# Usage: tests/rehearsal/run.sh            (local/CI test server only; prints a summary, keeps files in $OUT)
#        REHEARSAL_DB / REHEARSAL_OUT pick the database name (default canopy_rehearsal) and the folder for the files
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

LAST_MIGRATION="$(ls "$ROOT/supabase/migrations"/*.sql | tail -1 | xargs basename | cut -c1-4)"
migrate() {  # database, timings file: every migration, one transaction per file, as the SQL Editor account, timing each one
  : > "$2"
  local m s
  for m in $(ls "$ROOT/supabase/migrations"/*.sql | sort); do
    s=$(date +%s%N)
    if ! PGPASSWORD=rehearsal-only psql -X -q -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -U rehearsal_editor -d "$1" --single-transaction -f "$m" > "$OUT/m.log" 2>&1; then
      cat "$OUT/m.log"; die "$(basename "$m") failed on $1"
    fi
    printf '%s %s ms\n' "$(basename "$m" .sql)" "$(( ($(date +%s%N) - s) / 1000000 ))" >> "$2"
  done
  echo "    applied $(wc -l < "$2") migrations in $(awk '{s+=$2} END {printf "%.1f", s/1000}' "$2")s; slowest: $(sort -k2 -n -r "$2" | head -3 | awk '{printf "%s %s ms; ", $1, $2}')"
}
step "migrations 0000-$LAST_MIGRATION, each in one transaction, as the SQL Editor account (not a superuser)"
migrate "$DB" "$OUT/timings.txt"
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
  step "backup + restore test of the migrated copy (the backup account reads the tables 0002-0028 added too)"
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

step "the owner's staging rehearsal with the reset (Ensayo en pruebas, vaciar = si, reinicio = si)"
ensayo "$OUT/staging-reset" EMPTY_STAGING=si REINICIO=si > "$OUT/staging-reset.log" 2>&1 || { cat "$OUT/staging-reset.log"; die "staging copy with the reset"; }
head -1 "$OUT/staging-reset/reinicio.txt" | grep -q '^reinicio hecho' || { cat "$OUT/staging-reset.log"; die "staging copy with the reset: the reset did not answer 'reinicio hecho'"; }
[ -s "$OUT/staging-reset/resumen.json" ] || die "staging copy with the reset: no summary for the accountant"
python3 "$HERE/compare.py" "$OUT/staging-reset" reset | tee "$OUT/staging-reset-compare.txt" || die "staging copy with the reset: differences (see above)"
# as in the owner's run: the three unlock tables are empty because anonimizar.sql empties them, and the comparison says so by name
grep -q 'access_unlocks, inventory_unlocks, sales_unlocks: unlock tokens, emptied by anonimizar.sql' "$OUT/staging-reset-compare.txt" \
  || die "staging copy with the reset: the comparison does not name the tables the anonymizer empties"

step "one-time operational reset before the window (supabase/tools/reinicio-operativo.sql, D-038) on a second copy of today's production"
# the owner's window as docs/LANZAMIENTO-UNICO.md orders it: verified backup -> summary for the accountant -> the reset,
# ONE paste -> the migrations. Rehearsed on its own copy of the frozen "production before the window" (the backup account
# included), as the SQL Editor account; the migrated main copy proves the first refusal
RDB="${DB}_reset"
psql -X -q -d postgres -c "drop database if exists $RDB with (force)" -c "create database $RDB template ${DB}_src" >/dev/null
# a database made from a template does not inherit the template's own grants: the SQL Editor account gets create again (as-supabase.sql)
psql -X -q -d postgres -c "grant create on database $RDB to rehearsal_editor" >/dev/null
rq() { psql -X -q -At -v ON_ERROR_STOP=1 -d "$RDB" "$@"; }
editor() { PGPASSWORD=rehearsal-only psql -X -q -At -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -U rehearsal_editor "$@"; }
RESET="$ROOT/supabase/tools/reinicio-operativo.sql"; REF="ensayo $(date -u '+%Y-%m-%d %H:%M') UTC"
reset_paste() {  # [backup reference] [confirmation word] -> the paste as the owner sends it (as shipped when both are missing)
  sed "s/RESPALDO-AAAA-MM-DD HH:MM/${1:-RESPALDO-AAAA-MM-DD HH:MM}/; s/escriba BORRAR PRUEBAS/${2:-escriba BORRAR PRUEBAS}/" "$RESET"
}
# the whole paste as ONE query string, as the SQL Editor sends it: one implicit transaction, the pg_temp functions live only in it
run_paste() { editor -d "$1" -c "$(reset_paste "${@:2}")"; }
state() { psql -X -At -d "$1" -c "select count(*) || ' orders, ' || (select count(*) from public.audit_log) || ' log lines, stock ' || (select coalesce(sum(on_hand), 0) from public.stock_items) from public.orders"; }
refused() {  # database, expected message, what, [reference] [word]: the paste must stop with that message and change nothing
  local db="$1" want="$2" what="$3" before; before=$(state "$db")
  if run_paste "$db" "${@:4}" > "$OUT/reset-refusal.log" 2>&1; then cat "$OUT/reset-refusal.log"; die "reset: $what was not refused"; fi
  grep -q "$want" "$OUT/reset-refusal.log" || { cat "$OUT/reset-refusal.log"; die "reset: $what was refused for another reason (expected '$want')"; }
  [ "$(state "$db")" = "$before" ] || die "reset: the refusal ($what) changed something: $before -> $(state "$db")"
}
refused "$DB" 'ya tiene migraciones' "the migrated database" "$REF" "BORRAR PRUEBAS"
# the café is still working: a sale minutes ago (the seed rang today's at seed time: make one 5 minutes old) and the register open
rq -c "update public.orders set created_at = now() - interval '5 minutes' where id = '0d000000-0000-4000-8000-0000000000b1'" >/dev/null
refused "$RDB" 'de los últimos 60 minutos' "the café still open (a sale 5 minutes ago)" "$REF" "BORRAR PRUEBAS"
rq -c "update public.orders set created_at = created_at - interval '2 hours' where created_at > now() - interval '60 minutes'" >/dev/null
refused "$RDB" 'marcó en el reloj' "a punch minutes ago (the seed's open shift)" "$REF" "BORRAR PRUEBAS"
rq -c "update public.time_entries set clock_in = clock_in - interval '2 hours', clock_out = clock_out - interval '2 hours' where clock_in > now() - interval '60 minutes' or clock_out > now() - interval '60 minutes'" >/dev/null
refused "$RDB" 'caja abierta' "the register still open" "$REF" "BORRAR PRUEBAS"
# the café closed: the register counted half an hour ago
rq -c "update public.register_days set closed_at = now() - interval '30 minutes' where closed_at is null" >/dev/null
refused "$RDB" 'Falta la referencia' "the paste as shipped (placeholders)"
refused "$RDB" 'palabra de confirmación' "the wrong confirmation word" "$REF" "BORRAR TODO"
# every one of the 14 tables the reset clears has rows in this copy (seed-legacy.sql): the rehearsal proves that each one
# is cleared, not only the busy ones (compare.py reset fixture checks the same from the snapshots)
CLEARED="order_part_lines tab_adds order_items orders discount_approvals register_days time_entries stock_moves purchase_lines purchase_orders access_unlocks sales_unlocks inventory_unlocks chat_questions"
for t in $CLEARED; do n=$(rq -c "select count(*) from public.$t"); [ "$n" -gt 0 ] || die "seed: $t has no row for the reset to clear"; done
# the summary for the accountant (read-only), saved with the backup before the reset; the state before the reset
editor -d "$RDB" -f "$ROOT/supabase/tools/resumen-pruebas.sql" > "$OUT/resumen.json"
rq -f "$ROOT/supabase/tools/production-snapshot.sql" > "$OUT/reset-snapshot-before.json"
rq -f "$ROOT/supabase/tools/consistency-check.sql" > "$OUT/reset-consistency-before.json"
t0=$(date +%s%N)
run_paste "$RDB" "$REF" "BORRAR PRUEBAS" > "$OUT/reset.log" 2>&1 || { cat "$OUT/reset.log"; die "the reset failed"; }
reset_ms=$(( ($(date +%s%N) - t0) / 1000000 ))
head -1 "$OUT/reset.log" | grep -q "^reinicio hecho · respaldo $REF\$" || { cat "$OUT/reset.log"; die "the reset did not answer 'reinicio hecho · respaldo $REF'"; }
for t in $CLEARED; do n=$(rq -c "select count(*) from public.$t"); [ "$n" = 0 ] || die "reset: $t still has $n rows"; done
[ "$(rq -c "select count(*) from public.stock_items where on_hand <> 0")" = 0 ] || die "reset: a stock item is not at zero"
[ "$(rq -c "select count(*) from public.audit_log where action = 'reinicio_operativo'")" = 1 ] || die "reset: expected exactly one 'reinicio_operativo' line in the log"
# the log keeps the fingerprint of the summary (the figures stay in the cell the owner saves): it must be the one of the
# accountant's summary taken before (resumen-pruebas.sql, 'huella'), and the cell must carry the figures themselves
python3 - "$OUT/resumen.json" "$(rq -c "select details->>'resumen_md5' from public.audit_log where action = 'reinicio_operativo'")" "$OUT/reset.log" <<'PYCHK' || die "the summary's fingerprint in the log differs from supabase/tools/resumen-pruebas.sql"
import json, sys
saved, logged_md5 = json.load(open(sys.argv[1])), sys.argv[2]
assert saved['ventas_pagadas']['cantidad'] > 0 and saved['ventas_pagadas']['total_crc'] > 0, 'nothing was summarised'
assert saved['huella'] == logged_md5, ('huella', saved['huella'], logged_md5)
cell = open(sys.argv[3]).read()
assert 'huella del resumen: ' + logged_md5 in cell and '"ventas_pagadas"' in cell and str(saved['ventas_pagadas']['total_crc']) in cell, 'the cell does not carry the figures'
PYCHK
[ "$(rq -c "select count(*) from public.staff where coalesce(failed_pins, 0) <> 0 or locked_until is not null")" = 0 ] || die "reset: a PIN lockout survived"
[ "$(rq -c "select details ? 'resumen' from public.audit_log where action = 'reinicio_operativo'")" = f ] || die "reset: the log carries the period's figures (readable by every manager)"
refused "$RDB" 'ya se hizo' "a second run" "$REF" "BORRAR PRUEBAS"
rq -f "$ROOT/supabase/tools/production-snapshot.sql" > "$OUT/reset-snapshot-after-reset.json"
rq -f "$ROOT/supabase/tools/consistency-check.sql" > "$OUT/reset-consistency-after-reset.json"
echo "    $(sed -n 2p "$OUT/reset.log" | cut -c1-120)… in ${reset_ms} ms; six refusals, each changed nothing; the log's summary = the accountant's"

step "migrations 0000-$LAST_MIGRATION on the reset copy, each in one transaction, as the SQL Editor account"
audit_menu_reset=$(rq -c "$AUDIT_MENU")
[ "$audit_menu_reset" = "$audit_menu_before" ] || die "reset copy: audit_menu() is not production's before the migrations: $audit_menu_reset"
migrate "$RDB" "$OUT/reset-timings.txt"
[ "$(rq -c "$AUDIT_MENU")" = "$audit_menu_before" ] || die "reset copy: a migration changed audit_menu() (production's, D-031)"
rq -f "$ROOT/supabase/tools/production-snapshot.sql" > "$OUT/reset-snapshot-after.json"
rq -f "$ROOT/supabase/tools/consistency-check.sql" > "$OUT/reset-consistency-after.json"
rq -f "$ROOT/supabase/tools/release-check.sql" > "$OUT/reset-release-check.json"
python3 "$HERE/compare.py" "$OUT" reset fixture || die "reset copy: differences after the reset or the migrations (see above)"
# the comparison's own branches, on crafted copies of these files: a table production never wrote to is reported, not a
# difference (the first real-data rehearsal, 2026-10-14); the seeded copy must exercise every table; what must fail, fails
python3 "$HERE/compare-selftest.py" "$OUT" || die "compare.py self-test (see above)"

psql -X -q -d postgres -c "drop database if exists ${DB}_src with (force)" -c "drop database if exists ${DB}_staging with (force)" >/dev/null
echo "  ok    migration rehearsal (files in $OUT; $DB and $RDB kept for live-pages.sh and reset-pages.sh)"
