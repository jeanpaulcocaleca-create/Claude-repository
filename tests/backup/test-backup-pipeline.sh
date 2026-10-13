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
# the paste checks itself before it keeps anything: an owner-rights function any login may run (a way around every
# rule with a faked app login) stops it, and it creates and changes nothing (D-033)
ACL_SQL="select count(*) from pg_shdepend where refclassid = 'pg_authid'::regclass and refobjid = coalesce(to_regrole('canopy_backup')::oid, 0)
           and dbid in (0, (select oid from pg_database where datname = current_database()))"
# who may run each function of public (the paste takes PUBLIC's right to run the café's owner-rights trigger functions)
FN_SQL="select md5(string_agg(p.oid::regprocedure::text || ' ' || coalesce(p.proacl::text, '-'), ',' order by p.oid)) from pg_proc p
          where p.pronamespace = 'public'::regnamespace"
psql -X -q -d canopy_legacysim -v ON_ERROR_STOP=1 -c "create function public.canopy_test_evil() returns void language sql security definer as 'select 1'"
# an owner-rights trigger function given to the account by name: it could attach it to a temporary table of its own,
# and EXECUTE is not checked again when the trigger fires
psql -X -q -d canopy_legacysim -v ON_ERROR_STOP=1 \
  -c "create function public.canopy_test_evil_trg() returns trigger language plpgsql security definer as 'begin return new; end'" \
  -c "grant execute on function public.canopy_test_evil_trg() to canopy_backup"
acl_before="$(psql -X -At -d canopy_legacysim -c "$ACL_SQL")"; fn_before="$(psql -X -At -d canopy_legacysim -c "$FN_SQL")"
if psql -X -q -d canopy_legacysim -v ON_ERROR_STOP=1 -f "$ROOT/supabase/tools/backup-account.sql" > "$T/account-refused.log" 2>&1; then
  cat "$T/account-refused.log"; echo "  FAIL  the backup account paste accepted an owner-rights function any login can run"; exit 1; fi
grep -q 'NO SE CREÓ NI SE CAMBIÓ NADA' "$T/account-refused.log" && grep -qF 'canopy_test_evil()' "$T/account-refused.log" \
  && grep -qF 'canopy_test_evil_trg()' "$T/account-refused.log" \
  || { cat "$T/account-refused.log"; echo "  FAIL  the refused paste does not say why (owner-rights function, or trigger function given by name)"; exit 1; }
[ "$(psql -X -At -d canopy_legacysim -c "$FN_SQL")" = "$fn_before" ] \
  || { echo "  FAIL  the refused paste changed who may run a function"; exit 1; }
# run statement by statement (no stop on error), its result row must not say "lista" either
psql -X -q -At -d canopy_legacysim -f "$ROOT/supabase/tools/backup-account.sql" > "$T/account-refused2.log" 2>&1 || true
grep -q '^REVISAR: la revisión de arriba no terminó bien' "$T/account-refused2.log" && ! grep -q '^lista' "$T/account-refused2.log" \
  || { cat "$T/account-refused2.log"; echo "  FAIL  a refused paste still reported the account ready"; exit 1; }
[ "$(psql -X -At -d canopy_legacysim -c "$ACL_SQL")" = "$acl_before" ] \
  || { echo "  FAIL  the refused paste left permissions for the backup account"; exit 1; }
psql -X -q -d canopy_legacysim -v ON_ERROR_STOP=1 -c "drop function public.canopy_test_evil(), public.canopy_test_evil_trg()"
psql -X -q -d canopy_legacysim -v ON_ERROR_STOP=1 -f "$ROOT/supabase/tools/backup-account.sql" > "$T/account.log"
grep -q 'lista: la cuenta canopy_backup' "$T/account.log" || { cat "$T/account.log"; echo "  FAIL  backup account (before 0000)"; exit 1; }
# it reads the café's tables and the photo list, never the logins
[ "$(psql -X -At -d canopy_legacysim -c "select has_table_privilege('canopy_backup', 'public.orders', 'select') and has_table_privilege('canopy_backup', 'storage.objects', 'select')
       and not has_table_privilege('canopy_backup', 'auth.users', 'select') and not pg_has_role('canopy_backup', 'pg_read_all_data', 'member')")" = "t" ] \
  || { echo "  FAIL  the backup account does not read exactly the café's tables and the photo list"; exit 1; }
# ...and can no longer attach the café's owner-rights trigger functions (today 3 run by every login) to a table of its own
[ "$(psql -X -At -d canopy_legacysim -c "select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosecdef
       and p.prorettype = 'trigger'::regtype and has_function_privilege('canopy_backup', p.oid, 'execute')")" = "0" ] \
  && [ "$(psql -X -At -d canopy_legacysim -c "select has_function_privilege('authenticated', 'public._order_tab_voided()', 'execute')")" = "t" ] \
  || { echo "  FAIL  the paste left the café's trigger functions to every login, or took a right from another account"; exit 1; }
psql -X -q -d canopy_legacysim -v ON_ERROR_STOP=1 <<'SQL'
alter role canopy_backup login password 'test-only-backup';
insert into public.orders (id, total_crc, payment_method, paid, status)
  select gen_random_uuid(), 500 * g, 'card', true, 'done' from generate_series(1, 25) g;
insert into public.order_items (order_id, item_name, price_crc, qty) select id, 'Café', total_crc, 1 from public.orders;
insert into storage.objects (bucket_id, name, metadata) values
  ('menu-photos', 'desayunos/gallo-pinto.jpg', '{"size": 11}'), ('menu-photos', 'latte.png', '{"size": 5}');
SQL
# like Supabase's supabase_admin: default rights in public held by a role that the server restored into does not
# have (it is dropped below, before the restore): only postgres's own default rights may be restored
psql -X -q -d postgres -c "drop role if exists canopy_test_dacl" -c "create role canopy_test_dacl nologin" >/dev/null
psql -X -q -d canopy_legacysim -v ON_ERROR_STOP=1 -c "alter default privileges for role canopy_test_dacl in schema public grant select on tables to anon" >/dev/null
PHOTOS="$T/www/storage/v1/object/public/menu-photos"; mkdir -p "$PHOTOS/desayunos"
printf 'gallo pinto' > "$PHOTOS/desayunos/gallo-pinto.jpg"; printf 'latte' > "$PHOTOS/latte.png"
WWW_PORT=18431
python3 -m http.server "$WWW_PORT" --bind 127.0.0.1 --directory "$T/www" >/dev/null 2>&1 & WWW_PID=$!
trap 'kill "$WWW_PID" 2>/dev/null || true; rm -rf "$T"' EXIT
for _ in $(seq 1 50); do curl -fsS -o /dev/null "http://127.0.0.1:$WWW_PORT/storage/v1/object/public/menu-photos/latte.png" 2>/dev/null && break; sleep 0.1; done
LEGACY_URL="postgresql://canopy_backup:test-only-backup@${PGHOST}:${PGPORT}/canopy_legacysim"
mkdir -p "$T/work0"
CANOPY_DB_URL="$LEGACY_URL" AGE_RECIPIENTS="$RECIPIENTS" RESTORE_TEST_URL="$URL_BASE/postgres" UPLOAD_DIR="$T/offsite0" WORK_DIR="$T/work0" \
  SUPABASE_URL="http://127.0.0.1:$WWW_PORT" BACKUP_SOURCE=manual bash "$ROOT/ops/backup/backup.sh" > "$T/backup0.log" 2>&1 \
  || { cat "$T/backup0.log"; echo "  FAIL  backup before migration 0000"; exit 1; }
# the nightly restore test restored postgres's own default rights and none of the other role's
grep -q ' DEFAULT ACL public DEFAULT PRIVILEGES FOR TABLES postgres$' "$T/work0/toc.list" && ! grep -q ' DEFAULT ACL .* canopy_test_dacl$' "$T/work0/toc.list" \
  || { grep 'DEFAULT ACL' "$T/work0/toc.list"; echo "  FAIL  the nightly restore test keeps default rights of other roles or drops postgres's own"; exit 1; }
grep -q 'restauración: passed' "$T/backup0.log" && grep -q 'contenido idéntico en' "$T/backup0.log" && grep -q '2 archivos verificados' "$T/backup0.log" \
  || { cat "$T/backup0.log"; echo "  FAIL  backup before 0000: restore, content or photos not verified"; exit 1; }
F0="$(find "$T/offsite0" -name '*.tar.age' | head -1)"
psql -X -q -d canopy_legacysim -c "alter default privileges for role canopy_test_dacl in schema public revoke select on tables from anon" >/dev/null
psql -X -q -d postgres -c "drop role canopy_test_dacl" >/dev/null
[ "$(psql -X -At -d postgres -c "select count(*) from pg_roles where rolname = 'canopy_test_dacl'")" = "0" ] || { echo "  FAIL  test setup: the default-rights role is still there"; exit 1; }
psql -X -q -d postgres -c "drop database if exists canopy_restored0 with (force)" -c "create database canopy_restored0"
psql -X -q -d canopy_restored0 -f "$ROOT/ops/backup/restore-stub.sql" >/dev/null
KEEP_STORAGE_TO="$T/photos0" bash "$ROOT/ops/backup/restore.sh" "$F0" "$T/recovery.key" "$URL_BASE/canopy_restored0" --yes > "$T/restore0.log" 2>&1 \
  || { cat "$T/restore0.log"; echo "  FAIL  restore of the backup taken before 0000"; exit 1; }
grep -q 'contenido idéntico en' "$T/restore0.log" || { cat "$T/restore0.log"; echo "  FAIL  restored content not compared"; exit 1; }
cmp -s "$T/photos0/menu-photos/desayunos/gallo-pinto.jpg" "$PHOTOS/desayunos/gallo-pinto.jpg" || { echo "  FAIL  photo missing from the backup"; exit 1; }
# the logins are not in the backup (the account cannot read them): no auth file in the archive
age -d -i "$T/owner.key" "$F0" | tar -tf - > "$T/archive0.txt"
grep -q '/app.dump$' "$T/archive0.txt" && ! grep -qi 'auth' "$T/archive0.txt" \
  || { cat "$T/archive0.txt"; echo "  FAIL  the archive holds a copy of the logins (auth) or no database dump"; exit 1; }
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

# 2) restore with the recovery key into an empty database that sorts text like most servers (glibc en_US, the
#    postgres image's default): the row and rights fingerprints must not depend on the server's language
psql -X -q -d postgres -c "drop database if exists canopy_restored with (force)" \
  -c "create database canopy_restored template template0 locale_provider icu icu_locale 'en-US-u-ka-shifted' locale 'C.UTF-8'"
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

# 2b) a busy backup: a sale is saved while the copy is made (right after pg_dump, before the rows are counted again).
#     The copy holds the rows of its own moment; restore.sh must compare with what the copy holds, not with the
#     count taken after it
mkdir -p "$T/busybin"
cat > "$T/busybin/pg_dump" <<SH
#!/usr/bin/env bash
"$(command -v pg_dump)" "\$@" || exit \$?
case " \$* " in *" --format=custom "*)
  psql -X -q -d canopy_prodsim -v ON_ERROR_STOP=1 -c "insert into public.orders (id, total_crc, payment_method, paid, status) values (gen_random_uuid(), 777, 'card', true, 'done')" >/dev/null;;
esac
SH
chmod +x "$T/busybin/pg_dump"
PATH="$T/busybin:$PATH" CANOPY_DB_URL="$DBURL" AGE_RECIPIENTS="$RECIPIENTS" RESTORE_TEST_URL="$URL_BASE/postgres" UPLOAD_DIR="$T/offsite-busy" \
  BACKUP_SOURCE=manual bash "$ROOT/ops/backup/backup.sh" > "$T/backup-busy.log" 2>&1 || { cat "$T/backup-busy.log"; echo "  FAIL  busy backup run"; exit 1; }
grep -q 'restauración: passed' "$T/backup-busy.log" && grep -q 'con movimiento durante la copia' "$T/backup-busy.log" \
  || { cat "$T/backup-busy.log"; echo "  FAIL  busy backup: no sale saved during the copy, or the restore test failed"; exit 1; }
[ "$(psql -X -At -d canopy_prodsim -c 'select count(*) from public.orders')" = "41" ] || { echo "  FAIL  busy backup: the sale during the copy is missing"; exit 1; }
FB="$(find "$T/offsite-busy" -name '*.tar.age' | head -1)"
psql -X -q -d postgres -c "drop database if exists canopy_restored_busy with (force)" -c "create database canopy_restored_busy"
psql -X -q -d canopy_restored_busy -f "$ROOT/ops/backup/restore-stub.sql" >/dev/null
bash "$ROOT/ops/backup/restore.sh" "$FB" "$T/recovery.key" "$URL_BASE/canopy_restored_busy" --yes > "$T/restore-busy.log" 2>&1 \
  || { cat "$T/restore-busy.log"; echo "  FAIL  restore of a backup taken while a sale was saved"; exit 1; }
grep -q 'OK: ' "$T/restore-busy.log" || { cat "$T/restore-busy.log"; echo "  FAIL  busy backup: restored rows differ"; exit 1; }
[ "$(psql -X -At -d canopy_restored_busy -c 'select count(*) from public.orders')" = "40" ] || { echo "  FAIL  busy backup: the copy is not the dump's moment"; exit 1; }

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
  -c "drop database if exists canopy_restored0 with (force)" -c "drop database if exists canopy_legacysim with (force)" \
  -c "drop database if exists canopy_restored_busy with (force)" >/dev/null
echo "  ok    backup pipeline (before 0000 and after: account self-check (trigger functions too), backup, content fingerprints, photos, no logins, encryption, offline-key restore into an en_US-sorting database, a busy backup, computer sync)"
