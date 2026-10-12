#!/usr/bin/env bash
# =====================================================================================================
# Canopy OS · nightly backup pipeline
#   1. counts rows (before)          4. restores the dump into a throw-away database and checks every table
#   2. dumps the database            5. downloads Storage files (menu photos)
#   3. counts rows (after)           6. packs + ENCRYPTS with age (public keys only) + checksums
#   7. uploads the encrypted file    8. records the result in canopy.backup_runs (owner's Home tile)
# Nothing unencrypted is ever uploaded or kept. The script can encrypt but can never decrypt a backup.
#
# Settings (environment variables; in GitHub they come from the PRIVATE backup repository's secrets):
#   CANOPY_DB_URL      postgresql://canopy_backup.<ref>:<password>@<session-pooler-host>:5432/postgres?sslmode=require
#   AGE_RECIPIENTS     the owner's age PUBLIC keys (age1...), separated by spaces or new lines (2 recommended)
#   SUPABASE_URL       https://<ref>.supabase.co (public; used to download public Storage files)
#   STORAGE_BUCKETS    public buckets to copy (default: menu-photos)
#   PRIVATE_BUCKETS    private buckets to copy with Storage's S3 access (default: expense-receipts)
#   STORAGE_S3_ENDPOINT, STORAGE_S3_REGION, STORAGE_S3_KEY_ID, STORAGE_S3_SECRET
#                      Supabase → Storage → S3 access keys (read is enough); without them private buckets are skipped
#   RESTORE_TEST_URL   optional: a THROW-AWAY Postgres server (never Supabase) for the nightly restore test
#   RCLONE_REMOTE      optional: rclone destination, e.g. offsite:canopy-respaldos   (or)
#   UPLOAD_DIR         optional: copy the encrypted file to this folder instead
#   BACKUP_SOURCE      cloud | computer | manual (default cloud)
#   WORK_DIR           scratch folder (default: a new temp folder, deleted at the end)
# =====================================================================================================
set -euo pipefail
umask 077

: "${CANOPY_DB_URL:?Falta CANOPY_DB_URL}"
: "${AGE_RECIPIENTS:?Falta AGE_RECIPIENTS (llaves públicas age1...)}"
SOURCE="${BACKUP_SOURCE:-cloud}"
BUCKETS="${STORAGE_BUCKETS:-menu-photos}"
HERE="$(cd "$(dirname "$0")" && pwd)"
STARTED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
STAMP="$(date -u +%Y%m%d-%H%MZ)"
NAME="canopy-respaldo-$STAMP"
WORK="${WORK_DIR:-$(mktemp -d)}"
PACK="$WORK/$NAME"
mkdir -p "$PACK/storage"
STEP="inicio"
RESTORE_RESULT="skipped"
COUNTS_JSON='{}'

log() { echo "[$(date -u +%H:%M:%S)] $*"; }
sql() { psql -X -q -At -v ON_ERROR_STOP=1 "$CANOPY_DB_URL" "$@"; }

report() {  # status detail size file
  local esc_detail; esc_detail="$(printf '%s' "$2" | sed "s/'/''/g")"
  sql -c "select canopy.backup_report('$SOURCE', '$1', '$STARTED', ${3:-null}, '${4:-}', '$RESTORE_RESULT',
          '$(printf '%s' "$COUNTS_JSON" | sed "s/'/''/g")'::jsonb, '$esc_detail')" >/dev/null 2>&1 \
    || log "no se pudo anotar el resultado en la base (se intentará en la próxima corrida)"
}
fail() {
  log "ERROR en el paso: $STEP"
  report failed "falló en: $STEP" null "$NAME"
  [ -z "${WORK_DIR:-}" ] && rm -rf "$WORK"
  exit 1
}
trap fail ERR

APP_SCHEMAS_SQL="select string_agg(quote_literal(nspname), ',') from pg_namespace where nspname in ('public','canopy','acct')"
COUNT_SQL="select coalesce(jsonb_object_agg(t, n), '{}'::jsonb) from (
  select format('%s.%s', schemaname, relname) as t,
         (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I', schemaname, relname), false, true, '')))[1]::text::bigint as n
    from pg_stat_user_tables where schemaname in ('public','canopy','acct')) s"

STEP="conectar con la base"
log "conectando ($SOURCE)…"
SERVER_VERSION="$(sql -c 'show server_version')"
CLIENT_MAJOR="$(pg_dump --version | grep -Eo '[0-9]+' | head -1)"
SERVER_MAJOR="${SERVER_VERSION%%.*}"
if [ "$CLIENT_MAJOR" -lt "$SERVER_MAJOR" ]; then
  STEP="pg_dump $CLIENT_MAJOR es más viejo que el servidor $SERVER_MAJOR: actualice postgresql-client"; false
fi
SCHEMAS="$(sql -c "select string_agg(nspname, ' ') from pg_namespace where nspname in ('public','canopy','acct')")"

STEP="contar filas (antes)"
sql -c "$COUNT_SQL" > "$PACK/counts-before.json"

STEP="volcar la base (pg_dump)"
log "volcando esquemas: $SCHEMAS"
SCHEMA_ARGS=(); for s in $SCHEMAS; do SCHEMA_ARGS+=(--schema="$s"); done
pg_dump "$CANOPY_DB_URL" --format=custom --no-owner --compress=6 "${SCHEMA_ARGS[@]}" --file="$PACK/app.dump"
pg_dump "$CANOPY_DB_URL" --schema-only --no-owner "${SCHEMA_ARGS[@]}" --file="$PACK/schema.sql"
# logins (emails + password hashes) so the café/owner/accountant logins can be restored; best effort
pg_dump "$CANOPY_DB_URL" --format=custom --data-only --table='auth.users' --table='auth.identities' --file="$PACK/auth-users.dump" 2>/dev/null \
  || log "aviso: no se pudieron copiar las cuentas de acceso (auth); vea RESPALDOS.md → Cuentas"

STEP="contar filas (después)"
sql -c "$COUNT_SQL" > "$PACK/counts-after.json"
COUNTS_JSON="$(cat "$PACK/counts-after.json")"

if [ -n "${RESTORE_TEST_URL:-}" ]; then
  STEP="prueba de restauración"
  log "probando la restauración en una base desechable…"
  TESTDB="canopy_restore_test_$$"
  psql -X -q "$RESTORE_TEST_URL" -c "drop database if exists $TESTDB" -c "create database $TESTDB" >/dev/null
  TURL="$(python3 - "$RESTORE_TEST_URL" "$TESTDB" <<'PY'
import sys, urllib.parse as u
p = u.urlsplit(sys.argv[1]); print(u.urlunsplit(p._replace(path='/' + sys.argv[2])))
PY
)"
  psql -X -q -v ON_ERROR_STOP=1 "$TURL" -f "$HERE/restore-stub.sql" >/dev/null
  pg_restore -l "$PACK/app.dump" | grep -v -E 'SCHEMA - public |COMMENT - SCHEMA public ' > "$WORK/toc.list"
  pg_restore --no-owner --exit-on-error -L "$WORK/toc.list" -d "$TURL" "$PACK/app.dump"
  psql -X -q -At "$TURL" -c "$COUNT_SQL" > "$PACK/counts-restored.json"
  if python3 - "$PACK/counts-before.json" "$PACK/counts-after.json" "$PACK/counts-restored.json" <<'PY'
import json, sys
b, a, r = (json.load(open(f)) for f in sys.argv[1:4])
bad = [t for t in a if not (min(b.get(t, 0), a[t]) <= r.get(t, -1) <= max(b.get(t, 0), a[t]))]
missing = [t for t in a if t not in r]
if bad or missing:
    print('tablas que no coinciden:', ', '.join(sorted(set(bad + missing))[:20])); sys.exit(1)
print(f'restauración verificada: {len(r)} tablas, {sum(r.values())} filas')
PY
  then RESTORE_RESULT="passed"; else RESTORE_RESULT="failed"; fi
  psql -X -q "$RESTORE_TEST_URL" -c "drop database if exists $TESTDB" >/dev/null || true
  if [ "$RESTORE_RESULT" = "failed" ]; then STEP="prueba de restauración: las filas no coinciden"; false; fi
fi

STEP="copiar fotos (Storage)"
if [ -n "${SUPABASE_URL:-}" ]; then
  for b in $BUCKETS; do
    sql -c "select name from storage.objects where bucket_id = '$b' and name not like '%/.emptyFolderPlaceholder'" > "$WORK/objects-$b.txt" || true
    n=0
    while IFS= read -r obj; do
      [ -z "$obj" ] && continue
      mkdir -p "$PACK/storage/$b/$(dirname "$obj")"
      if curl -fsS --retry 3 -o "$PACK/storage/$b/$obj" "$SUPABASE_URL/storage/v1/object/public/$b/$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$obj")"; then
        n=$((n+1))
      else log "aviso: no se pudo descargar $b/$obj"; fi
    done < "$WORK/objects-$b.txt"
    log "fotos copiadas de $b: $n"
  done
fi

STEP="copiar facturas (Storage privado)"
PRIVATE="${PRIVATE_BUCKETS:-expense-receipts}"
if [ -n "${STORAGE_S3_KEY_ID:-}" ] && [ -n "${STORAGE_S3_SECRET:-}" ] && [ -n "${STORAGE_S3_ENDPOINT:-}" ]; then
  export RCLONE_CONFIG_SUPASTORE_TYPE=s3 RCLONE_CONFIG_SUPASTORE_PROVIDER=Other
  export RCLONE_CONFIG_SUPASTORE_ENDPOINT="$STORAGE_S3_ENDPOINT" RCLONE_CONFIG_SUPASTORE_REGION="${STORAGE_S3_REGION:-us-east-1}"
  export RCLONE_CONFIG_SUPASTORE_ACCESS_KEY_ID="$STORAGE_S3_KEY_ID" RCLONE_CONFIG_SUPASTORE_SECRET_ACCESS_KEY="$STORAGE_S3_SECRET"
  export RCLONE_CONFIG_SUPASTORE_FORCE_PATH_STYLE=true
  for b in $PRIVATE; do
    mkdir -p "$PACK/storage/$b"
    rclone copy "supastore:$b" "$PACK/storage/$b" --quiet
    log "archivos copiados de $b: $(find "$PACK/storage/$b" -type f | wc -l)"
  done
else
  for b in $PRIVATE; do
    n="$(sql -c "select count(*) from storage.objects where bucket_id = '$b'" 2>/dev/null || echo 0)"
    [ "${n:-0}" != "0" ] && log "aviso: $n archivos de $b NO se copiaron (faltan las llaves S3 de Storage, docs/RESPALDOS.md)"
  done
fi

STEP="empaquetar y cifrar"
python3 - "$PACK" "$STARTED" "$SERVER_VERSION" "$(pg_dump --version)" "$RESTORE_RESULT" "$SOURCE" <<'PY'
import hashlib, json, os, sys
pack, started, server, client, restore, source = sys.argv[1:7]
files = {}
for root, _, names in os.walk(pack):
    for n in names:
        p = os.path.join(root, n); rel = os.path.relpath(p, pack)
        files[rel] = hashlib.sha256(open(p, 'rb').read()).hexdigest()
json.dump({'started_at': started, 'server_version': server, 'pg_dump': client, 'restore_test': restore,
           'source': source, 'row_counts': json.load(open(os.path.join(pack, 'counts-after.json'))),
           'files': files}, open(os.path.join(pack, 'manifest.json'), 'w'), indent=1)
PY
RECIPS=(); for k in $AGE_RECIPIENTS; do RECIPS+=(-r "$k"); done
tar -C "$WORK" -cf - "$NAME" | age "${RECIPS[@]}" -o "$WORK/$NAME.tar.age"
rm -rf "$PACK"
( cd "$WORK" && sha256sum "$NAME.tar.age" > "$NAME.tar.age.sha256" )
SIZE="$(stat -c %s "$WORK/$NAME.tar.age" 2>/dev/null || stat -f %z "$WORK/$NAME.tar.age")"

STEP="subir la copia cifrada"
YEAR="${STAMP:0:4}"; MONTH="${STAMP:4:2}"
if [ -n "${RCLONE_REMOTE:-}" ]; then
  rclone copyto "$WORK/$NAME.tar.age" "$RCLONE_REMOTE/$YEAR/$MONTH/$NAME.tar.age"
  rclone copyto "$WORK/$NAME.tar.age.sha256" "$RCLONE_REMOTE/$YEAR/$MONTH/$NAME.tar.age.sha256"
elif [ -n "${UPLOAD_DIR:-}" ]; then
  mkdir -p "$UPLOAD_DIR/$YEAR/$MONTH"
  cp "$WORK/$NAME.tar.age" "$WORK/$NAME.tar.age.sha256" "$UPLOAD_DIR/$YEAR/$MONTH/"
else
  log "sin destino (RCLONE_REMOTE/UPLOAD_DIR): la copia queda en $WORK"
fi

STEP="anotar el resultado"
trap - ERR
report ok "respaldo completo" "$SIZE" "$NAME.tar.age"
log "listo: $NAME.tar.age ($SIZE bytes, restauración: $RESTORE_RESULT)"
[ -z "${WORK_DIR:-}" ] && rm -rf "$WORK"
exit 0
