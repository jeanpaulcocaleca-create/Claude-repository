#!/usr/bin/env bash
# Canopy OS · end-to-end test of the backup system on local test databases:
#   build a "production" copy → nightly backup (dump, restore test, age encryption, upload) → restore into an
#   empty database with the OFFLINE recovery key → compare every table → owner-computer sync and verification.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/tests/pg.sh"
command -v age >/dev/null || { echo "  skip  backup pipeline (age not installed)"; exit 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
URL_BASE="postgresql://postgres@${PGHOST}:${PGPORT}"
[ -n "${PGPASSWORD:-}" ] && URL_BASE="postgresql://postgres:${PGPASSWORD}@${PGHOST}:${PGPORT}"

"$ROOT/tests/build-db.sh" canopy_prodsim >/dev/null
psql -X -q -d canopy_prodsim -v ON_ERROR_STOP=1 <<'SQL'
alter role canopy_backup login password 'test-only-backup';
insert into public.orders (id, total_crc, payment_method, paid, status)
  select gen_random_uuid(), 1000 * g, 'cash_crc', true, 'done' from generate_series(1, 40) g;
insert into public.order_items (order_id, item_name, price_crc, qty) select id, 'Latte', total_crc, 1 from public.orders;
SQL
age-keygen -o "$T/owner.key" 2>/dev/null; age-keygen -o "$T/recovery.key" 2>/dev/null
RECIPIENTS="$(age-keygen -y "$T/owner.key") $(age-keygen -y "$T/recovery.key")"
DBURL="postgresql://canopy_backup:test-only-backup@${PGHOST}:${PGPORT}/canopy_prodsim"

# 1) nightly backup
CANOPY_DB_URL="$DBURL" AGE_RECIPIENTS="$RECIPIENTS" RESTORE_TEST_URL="$URL_BASE/postgres" UPLOAD_DIR="$T/offsite" \
  BACKUP_SOURCE=cloud bash "$ROOT/ops/backup/backup.sh" > "$T/backup.log" 2>&1 || { cat "$T/backup.log"; echo "  FAIL  backup run"; exit 1; }
F="$(find "$T/offsite" -name '*.tar.age' | head -1)"
[ -n "$F" ] || { echo "  FAIL  no encrypted backup uploaded"; exit 1; }
grep -q 'restauración: passed' "$T/backup.log" || { cat "$T/backup.log"; echo "  FAIL  restore test did not pass"; exit 1; }
if tar -tf "$F" >/dev/null 2>&1 || grep -qa 'CREATE TABLE\|orders' "$F"; then echo "  FAIL  backup is readable without the key"; exit 1; fi
[ "$(psql -X -At -d canopy_prodsim -c "select status || '/' || restore_test from canopy.backup_runs order by id desc limit 1")" = "ok/passed" ] \
  || { echo "  FAIL  backup run not recorded"; exit 1; }

# 2) restore with the recovery key into an empty database
psql -X -q -d postgres -c "drop database if exists canopy_restored with (force)" -c "create database canopy_restored"
psql -X -q -d canopy_restored -f "$ROOT/ops/backup/restore-stub.sql" >/dev/null
bash "$ROOT/ops/backup/restore.sh" "$F" "$T/recovery.key" "$URL_BASE/canopy_restored" --yes > "$T/restore.log" 2>&1 \
  || { cat "$T/restore.log"; echo "  FAIL  restore"; exit 1; }
grep -q 'OK: ' "$T/restore.log" || { cat "$T/restore.log"; echo "  FAIL  restored rows differ"; exit 1; }
[ "$(psql -X -At -d canopy_restored -c 'select count(*) from public.orders')" = "40" ] || { echo "  FAIL  orders missing after restore"; exit 1; }
# the restored copy still enforces its security rules
psql -X -At -d canopy_restored -c "select relrowsecurity from pg_class where oid = 'public.orders'::regclass" | grep -q t \
  || { echo "  FAIL  row level security lost in restore"; exit 1; }
# refuses to restore over a database that has data
if bash "$ROOT/ops/backup/restore.sh" "$F" "$T/owner.key" "$URL_BASE/canopy_restored" --yes > /dev/null 2>&1; then
  echo "  FAIL  restore overwrote a non-empty database"; exit 1; fi

# 3) owner computer: catch up, verify checksums, status
CANOPY_CONF=/dev/null SOURCE_DIR="$T/offsite" DEST="$T/computer" bash "$ROOT/ops/backup/computer/sincronizar-respaldos.sh" > /dev/null \
  || { cat "$T/computer/ESTADO.txt"; echo "  FAIL  computer sync"; exit 1; }
grep -q 'Estado: BIEN' "$T/computer/ESTADO.txt" || { cat "$T/computer/ESTADO.txt"; echo "  FAIL  computer status"; exit 1; }
cmp -s "$F" "$T/computer/archivo/$(basename "$F")" || { echo "  FAIL  computer copy differs"; exit 1; }

# 4) the private-repository copies of the scripts are identical to the reviewed ones
for f in backup.sh restore-stub.sql; do
  cmp -s "$ROOT/ops/backup/$f" "$ROOT/ops/backup/repositorio-respaldos/$f" || { echo "  FAIL  repositorio-respaldos/$f is out of date"; exit 1; }
done
psql -X -q -d postgres -c "drop database if exists canopy_restored with (force)" -c "drop database if exists canopy_prodsim with (force)" >/dev/null
echo "  ok    backup pipeline (backup, restore test, encryption, offline-key restore, computer sync)"
