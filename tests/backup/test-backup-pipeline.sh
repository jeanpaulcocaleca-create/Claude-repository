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

age-keygen -o "$T/owner.key" 2>/dev/null; age-keygen -o "$T/recovery.key" 2>/dev/null
RECIPIENTS="$(age-keygen -y "$T/owner.key") $(age-keygen -y "$T/recovery.key")"

# 0) production as it is today, before migration 0000: the account from supabase/tools/backup-account.sql,
#    menu photos served the way Supabase's public Storage serves them; every table and every file is checked
CANOPY_LEGACY_ONLY=1 "$ROOT/tests/build-db.sh" canopy_legacysim >/dev/null
psql -X -q -d canopy_legacysim -v ON_ERROR_STOP=1 -f "$ROOT/supabase/tools/backup-account.sql" > "$T/account.log"
grep -q 'lista: la cuenta canopy_backup' "$T/account.log" || { cat "$T/account.log"; echo "  FAIL  backup account (before 0000)"; exit 1; }
psql -X -q -d canopy_legacysim -v ON_ERROR_STOP=1 <<'SQL'
alter role canopy_backup login password 'test-only-backup';
insert into public.orders (id, total_crc, payment_method, paid, status)
  select gen_random_uuid(), 500 * g, 'card', true, 'done' from generate_series(1, 25) g;
insert into public.order_items (order_id, item_name, price_crc, qty) select id, 'Café', total_crc, 1 from public.orders;
insert into storage.objects (bucket_id, name, metadata) values
  ('menu-photos', 'desayunos/gallo-pinto.jpg', '{"size": 11}'), ('menu-photos', 'latte.png', '{"size": 5}');
SQL
PHOTOS="$T/www/storage/v1/object/public/menu-photos"; mkdir -p "$PHOTOS/desayunos"
printf 'gallo pinto' > "$PHOTOS/desayunos/gallo-pinto.jpg"; printf 'latte' > "$PHOTOS/latte.png"
WWW_PORT=18431
python3 -m http.server "$WWW_PORT" --bind 127.0.0.1 --directory "$T/www" >/dev/null 2>&1 & WWW_PID=$!
trap 'kill "$WWW_PID" 2>/dev/null || true; rm -rf "$T"' EXIT
for _ in $(seq 1 50); do curl -fsS -o /dev/null "http://127.0.0.1:$WWW_PORT/storage/v1/object/public/menu-photos/latte.png" 2>/dev/null && break; sleep 0.1; done
LEGACY_URL="postgresql://canopy_backup:test-only-backup@${PGHOST}:${PGPORT}/canopy_legacysim"
CANOPY_DB_URL="$LEGACY_URL" AGE_RECIPIENTS="$RECIPIENTS" RESTORE_TEST_URL="$URL_BASE/postgres" UPLOAD_DIR="$T/offsite0" \
  SUPABASE_URL="http://127.0.0.1:$WWW_PORT" BACKUP_SOURCE=manual bash "$ROOT/ops/backup/backup.sh" > "$T/backup0.log" 2>&1 \
  || { cat "$T/backup0.log"; echo "  FAIL  backup before migration 0000"; exit 1; }
grep -q 'restauración: passed' "$T/backup0.log" && grep -q 'contenido idéntico en' "$T/backup0.log" && grep -q '2 archivos verificados' "$T/backup0.log" \
  || { cat "$T/backup0.log"; echo "  FAIL  backup before 0000: restore, content or photos not verified"; exit 1; }
F0="$(find "$T/offsite0" -name '*.tar.age' | head -1)"
psql -X -q -d postgres -c "drop database if exists canopy_restored0 with (force)" -c "create database canopy_restored0"
psql -X -q -d canopy_restored0 -f "$ROOT/ops/backup/restore-stub.sql" >/dev/null
KEEP_STORAGE_TO="$T/photos0" bash "$ROOT/ops/backup/restore.sh" "$F0" "$T/recovery.key" "$URL_BASE/canopy_restored0" --yes > "$T/restore0.log" 2>&1 \
  || { cat "$T/restore0.log"; echo "  FAIL  restore of the backup taken before 0000"; exit 1; }
grep -q 'contenido idéntico en' "$T/restore0.log" || { cat "$T/restore0.log"; echo "  FAIL  restored content not compared"; exit 1; }
cmp -s "$T/photos0/menu-photos/desayunos/gallo-pinto.jpg" "$PHOTOS/desayunos/gallo-pinto.jpg" || { echo "  FAIL  photo missing from the backup"; exit 1; }
# a photo that cannot be copied fails the backup (it is never reported as complete)
rm "$PHOTOS/latte.png"
if CANOPY_DB_URL="$LEGACY_URL" AGE_RECIPIENTS="$RECIPIENTS" UPLOAD_DIR="$T/offsite0b" SUPABASE_URL="http://127.0.0.1:$WWW_PORT" \
     BACKUP_SOURCE=manual bash "$ROOT/ops/backup/backup.sh" > "$T/backup0b.log" 2>&1; then
  cat "$T/backup0b.log"; echo "  FAIL  a backup with a missing photo was reported complete"; exit 1; fi
grep -q 'faltan 1 ' "$T/backup0b.log" || { cat "$T/backup0b.log"; echo "  FAIL  missing photo not named"; exit 1; }
kill "$WWW_PID" 2>/dev/null || true

"$ROOT/tests/build-db.sh" canopy_prodsim >/dev/null
psql -X -q -d canopy_prodsim -v ON_ERROR_STOP=1 <<'SQL'
alter role canopy_backup login password 'test-only-backup';
insert into public.orders (id, total_crc, payment_method, paid, status)
  select gen_random_uuid(), 1000 * g, 'cash_crc', true, 'done' from generate_series(1, 40) g;
insert into public.order_items (order_id, item_name, price_crc, qty) select id, 'Latte', total_crc, 1 from public.orders;
SQL
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
# ...and keeps who may run what: Supabase's default grants must not open the owner's functions to visitors
[ "$(psql -X -At -d canopy_restored -c "select has_function_privilege('anon', 'public.make_owner(text)', 'execute') or has_function_privilege('anon', 'public.manager_save_staff(uuid, text, uuid, text, text, boolean, text)', 'execute')")" = "f" ] \
  || { echo "  FAIL  the restore opened owner functions to anonymous visitors"; exit 1; }
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
psql -X -q -d postgres -c "drop database if exists canopy_restored with (force)" -c "drop database if exists canopy_prodsim with (force)" \
  -c "drop database if exists canopy_restored0 with (force)" -c "drop database if exists canopy_legacysim with (force)" >/dev/null
echo "  ok    backup pipeline (before 0000 and after: backup, content fingerprints, photos, encryption, offline-key restore, computer sync)"
