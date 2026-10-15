#!/usr/bin/env bash
# =====================================================================================================
# Canopy OS · nightly backup pipeline
#   1. counts rows + fingerprints (before)   4. restores the dump into a throw-away database and checks every
#   2. dumps the database                       table: same rows AND same content (md5 fingerprint)
#   3. counts rows + fingerprints (after)    5. downloads Storage files and checks every one arrived, same size
#   6. packs + ENCRYPTS with age (public keys only) + checksums
#   7. uploads the encrypted file            8. records the result in canopy.backup_runs (owner's Home tile)
# Works before migration 0000 too (account from supabase/tools/backup-account.sql). Until migration 0002 exists
# nothing is recorded in the database: the GitHub run is the record.
# The logins (auth: emails, password hashes, sessions) are NOT copied: the backup account cannot read them, so a
# stolen backup password or file can never sign anyone in. After a disaster they are created again by hand
# (docs/RESPALDOS.md → Cuentas de acceso).
# Nothing unencrypted is ever uploaded or kept. The script can encrypt but can never decrypt a backup.
#
# Settings (environment variables; in GitHub they come from the PRIVATE backup repository's secrets):
#   CANOPY_DB_URL      postgresql://canopy_backup.<ref>:<password>@<session-pooler-host>:5432/postgres?sslmode=require
#   AGE_RECIPIENTS     the owner's age PUBLIC keys (age1...), separated by spaces or new lines (2 recommended)
#   SUPABASE_URL       https://<ref>.supabase.co (public; used to download public Storage files)
#   STORAGE_BUCKETS    public buckets to copy (default: menu-photos)
#   PRIVATE_BUCKETS    private buckets to copy with Storage's S3 access (default: expense-receipts)
#   STORAGE_S3_ENDPOINT, STORAGE_S3_REGION, STORAGE_S3_KEY_ID, STORAGE_S3_SECRET
#                      Supabase → Storage → S3 access keys (they open every bucket, read and write: keep them only
#                      in the private repository); without them private buckets are skipped
#   RESTORE_TEST_URL   optional: a THROW-AWAY Postgres server (never Supabase) for the nightly restore test
#   RCLONE_REMOTE      optional: rclone destination, e.g. offsite:canopy-respaldos   (or)
#   UPLOAD_DIR         optional: copy the encrypted file to this folder instead
#   BACKUP_SOURCE      cloud | computer | manual (default cloud)
#   WORK_DIR           scratch folder (default: a new temp folder, deleted at the end)
#   BACKUP_CHECK_ONLY  1: check the secrets, log in as canopy_backup and check its rights, then stop (no copy, no
#                      upload, nothing recorded); url: check the secrets only, without connecting
# =====================================================================================================
set -euo pipefail
umask 077
export PGTZ=UTC   # fingerprints compare text: the same time zone everywhere

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
REPORT_OK=0   # report() writes to the database only once this run has logged in as canopy_backup

log() { echo "[$(date -u +%H:%M:%S)] $*"; }
sql() { psql -X -q -At -v ON_ERROR_STOP=1 "$CANOPY_DB_URL" "$@"; }

report() {  # status detail size file
  [ "$REPORT_OK" = 1 ] || return 0   # a refused or failed login is never tried a second time just to report it
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

# Before any connection: CANOPY_DB_URL must be the backup account's (canopy_backup), never the owner's postgres or
# another login, and AGE_RECIPIENTS only public keys. A wrong secret stops the run here, before it connects, with a
# message that names the wrong part. No message shows anything taken from a secret: GitHub hides only a WHOLE
# secret in its logs, never a piece of one.
url_problem() {   # what is wrong with the connection address (nothing when it is right)
  local u="$1" re user pass host port db query
  case "$u" in *[[:space:]]*) echo "tiene un espacio o un salto de línea: péguela otra vez, en una sola línea"; return 0 ;; esac
  re='^postgres(ql)?://([^:@/?#]*)(:([^@/?#]*))?@([^:/?#]+)(:([0-9]+))?/([^?#]*)(\?([^#]*))?$'
  if ! [[ "$u" =~ $re ]]; then
    echo "no tiene la forma postgresql://canopy_backup.‹proyecto›:‹contraseña›@‹servidor›:5432/postgres?sslmode=require"; return 0
  fi
  user="${BASH_REMATCH[2]}"; pass="${BASH_REMATCH[4]}"; host="${BASH_REMATCH[5],,}"; host="${host%.}"; port="${BASH_REMATCH[7]:-5432}"
  db="${BASH_REMATCH[8]}"; query="${BASH_REMATCH[10]}"
  if ! [[ "$user" =~ ^canopy_backup(\.[a-z0-9]+)?$ ]]; then
    if [[ "$user" =~ ^postgres(\.[a-z0-9]+)?$ ]]; then
      echo "la cuenta es postgres, la del dueño, no la de respaldo: cambie «postgres.» (justo después de «postgresql://») por «canopy_backup.»"
    elif [ -z "$user" ]; then
      echo "no trae la cuenta: debe empezar con postgresql://canopy_backup.‹proyecto›:"
    else
      echo "la cuenta no es canopy_backup (no se muestra: podría traer parte de la contraseña): debe empezar con postgresql://canopy_backup.‹proyecto›:"
    fi
    return 0
  fi
  # libpq lets a parameter after the "?" replace the account, password, server, base or role written before it
  local kv
  for kv in ${query//&/ }; do
    case "${kv%%=*}" in
      sslmode) ;;
      *) echo "después del «?» solo puede ir sslmode=require (otro ajuste podría cambiar la cuenta o el servidor)"; return 0 ;;
    esac
  done
  [ -n "$pass" ] || { echo "no trae la contraseña (va entre «canopy_backup.‹proyecto›:» y «@»)"; return 0; }
  case "$pass" in *'['*|*']'*) echo "la contraseña quedó entre corchetes: reemplace [YOUR-PASSWORD] completo, sin dejar ningún corchete"; return 0 ;; esac
  case "$host" in
    *.supabase.co|*.supabase.com) ;;
    *) return 0 ;;   # a local or test server: only the account is checked
  esac
  if [[ "$host" =~ ^db\..*\.supabase\.co$ ]]; then
    echo "es la conexión directa (db.‹proyecto›.supabase.co: solo IPv6, los servidores de GitHub no llegan): use la del Session pooler"; return 0
  fi
  [[ "$host" =~ ^aws-[0-9]+-[a-z0-9-]+\.pooler\.supabase\.com$ ]] \
    || { echo "el servidor no es el del Session pooler (aws-…pooler.supabase.com): cópiela otra vez de Connect, Method: Session pooler"; return 0; }
  [ "$port" = 5432 ] || { echo "el puerto es $port: el del Session pooler es 5432 (6543 es el modo Transaction, que no sirve para respaldos)"; return 0; }
  [[ "$user" =~ ^canopy_backup\.([a-z0-9]{20})$ ]] \
    || { echo "a la cuenta le falta el proyecto: debe ser canopy_backup.‹proyecto›, con el punto"; return 0; }
  local uref="${BASH_REMATCH[1]}"
  if [[ "${SUPABASE_URL:-}" =~ ^https://([a-z0-9]{20})\.supabase\.co/?$ ]] && [ "$uref" != "${BASH_REMATCH[1]}" ]; then
    echo "la cuenta es de otro proyecto que el de SUPABASE_URL (${BASH_REMATCH[1]}): copie la dirección de ese proyecto"; return 0
  fi
  [ "$db" = postgres ] || { echo "al final, antes del «?», debe decir /postgres"; return 0; }
  [[ "$pass" =~ ^[0-9a-f]{64}$ ]] \
    || { echo "la contraseña no es la de 64 caracteres (cifras 0-9 y letras a-f) que muestra supabase/tools/backup-password.sql: cópiela completa otra vez"; return 0; }
  [[ "&$query&" =~ \&sslmode=(require|verify-ca|verify-full)\& ]] || { echo "falta ?sslmode=require al final"; return 0; }
  return 0
}
keys_problem() {   # what is wrong with AGE_RECIPIENTS (nothing when it is right)
  local k n=0
  case "$AGE_RECIPIENTS" in *AGE-SECRET-KEY*) echo "trae una llave PRIVADA (AGE-SECRET-KEY-…): bórrela de este secreto ya; solo van las públicas age1…"; return 0 ;; esac
  for k in $AGE_RECIPIENTS; do
    [[ "$k" =~ ^age1[0-9a-z]{58}$ ]] || { echo "una de las llaves no es una pública age1… de 62 caracteres (no se muestra)"; return 0; }
    n=$((n + 1))
  done
  [ "$n" -ge 1 ] || echo "no trae ninguna llave pública age1…"
  return 0
}
STEP="revisar CANOPY_DB_URL"
PROBLEM="$(url_problem "$CANOPY_DB_URL")"
if [ -n "$PROBLEM" ]; then STEP="revisar el secreto CANOPY_DB_URL: $PROBLEM. No se conectó"; false; fi
STEP="revisar AGE_RECIPIENTS"
PROBLEM="$(keys_problem)"
if [ -n "$PROBLEM" ]; then STEP="revisar el secreto AGE_RECIPIENTS: $PROBLEM. No se conectó"; false; fi
KEYS=0; for k in $AGE_RECIPIENTS; do KEYS=$((KEYS + 1)); done
[ "$KEYS" -ge 2 ] || log "aviso: AGE_RECIPIENTS trae una sola llave pública; se recomiendan dos (la del dueño y la de recuperación)"
if [ "${BACKUP_CHECK_ONLY:-}" = url ]; then
  log "secretos en orden: CANOPY_DB_URL con la cuenta canopy_backup, AGE_RECIPIENTS con $KEYS llave(s) pública(s) (sin conectar)"
  [ -z "${WORK_DIR:-}" ] && rm -rf "$WORK"
  exit 0
fi

APP_SCHEMAS_SQL="select string_agg(quote_literal(nspname), ',') from pg_namespace where nspname in ('public','canopy','acct')"
COUNT_SQL="select coalesce(jsonb_object_agg(t, n), '{}'::jsonb) from (
  select format('%s.%s', schemaname, relname) as t,
         (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I', schemaname, relname), false, true, '')))[1]::text::bigint as n
    from pg_stat_user_tables where schemaname in ('public','canopy','acct')) s"

# per table: "rows:md5 of every row" (the content itself never leaves the database in this check)
FP_SQL="select coalesce(jsonb_object_agg(t, f), '{}'::jsonb) from (
  select format('%s.%s', schemaname, relname) as t,
         (xpath('/row/f/text()', query_to_xml(format('select count(*)::text || '':'' || coalesce(md5(string_agg(x::text, E''\\n'' order by x::text collate \"C\")), ''-'') as f from %I.%I x', schemaname, relname), false, true, '')))[1]::text as f
    from pg_stat_user_tables where schemaname in ('public','canopy','acct')) s"

# Supabase gives anonymous visitors and logins every new table and function in "public" (default privileges). A dump
# only records how each object differs from PostgreSQL's own default, so restoring it with those defaults on would
# open every function (make_owner included) to anonymous visitors. They are switched off while restoring, back on after.
DEFAULTS_OFF="alter default privileges in schema public revoke all on tables from anon, authenticated, service_role;
alter default privileges in schema public revoke all on functions from anon, authenticated, service_role;
alter default privileges in schema public revoke all on sequences from anon, authenticated, service_role;"
DEFAULTS_ON="alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;"
# what visitors, logins, the service and the backup account may run, read or write; row security; rules (md5)
PRIV_SQL="select md5(coalesce(string_agg(x, E'\n' order by x collate \"C\"), '')) from (
  select 'f|' || n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')|' || coalesce(g.rolname, 'PUBLIC') || '|' || a.privilege_type || '|' || p.prosecdef as x
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a left join pg_roles g on g.oid = a.grantee
   where n.nspname in ('public', 'canopy', 'acct') and coalesce(g.rolname, 'PUBLIC') in ('PUBLIC', 'anon', 'authenticated', 'service_role', 'canopy_backup')
     and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
  union all
  select 't|' || n.nspname || '.' || c.relname || '|' || coalesce(g.rolname, 'PUBLIC') || '|' || a.privilege_type
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a left join pg_roles g on g.oid = a.grantee
   where n.nspname in ('public', 'canopy', 'acct') and c.relkind in ('r', 'p', 'v', 'm') and coalesce(g.rolname, 'PUBLIC') in ('PUBLIC', 'anon', 'authenticated', 'service_role', 'canopy_backup')
  union all
  select 's|' || n.nspname || '.' || c.relname || '|' || coalesce(g.rolname, 'PUBLIC') || '|' || a.privilege_type
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
    cross join lateral aclexplode(coalesce(c.relacl, acldefault('s', c.relowner))) a left join pg_roles g on g.oid = a.grantee
   where n.nspname in ('public', 'canopy', 'acct') and c.relkind = 'S' and coalesce(g.rolname, 'PUBLIC') in ('PUBLIC', 'anon', 'authenticated', 'service_role', 'canopy_backup')
  union all
  select 'rls|' || n.nspname || '.' || c.relname || '|' || c.relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname in ('public', 'canopy', 'acct') and c.relkind in ('r', 'p')
  union all
  select 'pol|' || schemaname || '.' || tablename || '|' || policyname || '|' || cmd || '|' || array_to_string(roles, ',') || '|' || permissive
    from pg_policies where schemaname in ('public', 'canopy', 'acct')) q"

STEP="conectar con la base"
log "conectando ($SOURCE)…"
# the first connection: its error (the server's or libpq's own) goes into the step line the summary shows, without the
# password (removed by value, and any 64-hex run with it) and with the usual pooler answers explained
if ! SERVER_VERSION="$(sql -c 'show server_version' 2> "$WORK/conectar.err")"; then
  PW_IN_URL=""; [[ "$CANOPY_DB_URL" =~ ^postgres(ql)?://[^:@/?#]*:([^@/?#]*)@ ]] && PW_IN_URL="${BASH_REMATCH[2]}"
  CAUSE="$(grep -E 'FATAL|error|ERROR' "$WORK/conectar.err" | tail -1 | sed -E 's/^psql: error: //; s/^connection to server at //')"
  [ -n "$PW_IN_URL" ] && CAUSE="${CAUSE//"$PW_IN_URL"/‹contraseña›}"
  CAUSE="$(printf '%s' "$CAUSE" | sed -E 's/[0-9a-f]{64}/‹contraseña›/g' | cut -c1-300)"
  case "$CAUSE" in
    *'password authentication failed for user "canopy_backup"'*)
      HINT="la contraseña del secreto no es la de canopy_backup (o el pooler aún tiene la anterior: hasta un día): docs/RESPALDOS.md, paso 3.4, punto 3, y arme el secreto otra vez" ;;
    *'password authentication failed for user'*)
      HINT="el secreto entra con otra cuenta: debe empezar con postgresql://canopy_backup." ;;
    *'user not found in the database'*|*'rolcanlogin'*)
      HINT="la cuenta canopy_backup no existe o aún no puede entrar: paso 2 (backup-account.sql) y paso 3.4 (backup-password.sql)" ;;
    *'Tenant or user not found'*|*'ENOTFOUND'*|*'ENOIDENTIFIER'*)
      HINT="el proyecto de la cuenta (lo que sigue a canopy_backup.) no es el de este servidor: copie la dirección de Connect otra vez" ;;
    *'too many authentication failures'*|*'ECIRCUITBREAKER'*)
      HINT="el pooler bloqueó este servidor de GitHub unos minutos por intentos fallidos: corrija el secreto y espere 5 minutos" ;;
    *) HINT="" ;;
  esac
  STEP="conectar con la base: ${CAUSE:-sin detalle}${HINT:+. $HINT}. No se copió nada"; rm -f "$WORK/conectar.err"; false
fi
rm -f "$WORK/conectar.err"
WHO="$(sql -c 'select current_user')"
if [ "$WHO" != canopy_backup ]; then STEP="conectar con la base: entró la cuenta $WHO, no canopy_backup. No se copió nada"; false; fi
[ "${BACKUP_CHECK_ONLY:-}" = 1 ] || REPORT_OK=1   # the connection check records nothing, not even a failure
CLIENT_MAJOR="$(pg_dump --version | grep -Eo '[0-9]+' | head -1)"
SERVER_MAJOR="${SERVER_VERSION%%.*}"
if [ "$CLIENT_MAJOR" -lt "$SERVER_MAJOR" ]; then
  STEP="pg_dump $CLIENT_MAJOR es más viejo que el servidor $SERVER_MAJOR: actualice postgresql-client"; false
fi
SCHEMAS="$(sql -c "select string_agg(nspname, ' ') from pg_namespace where nspname in ('public','canopy','acct')")"
# the old account (supabase/tools/backup-account.sql version 1) could read the logins too: say so, keep going
[ "$(sql -c "select pg_has_role('pg_read_all_data', 'member')
                     or coalesce((select has_schema_privilege(n.oid, 'usage') and has_table_privilege(c.oid, 'select')
                                    from pg_class c join pg_namespace n on n.oid = c.relnamespace
                                   where n.nspname = 'auth' and c.relname = 'users'), false)")" = "f" ] \
  || log "aviso: la cuenta de respaldo todavía puede leer las cuentas de acceso: ejecute otra vez supabase/tools/backup-account.sql"

if [ "${BACKUP_CHECK_ONLY:-}" = 1 ]; then   # the connection check: the account's rights, then stop (nothing copied or recorded)
  STEP="revisar los permisos de canopy_backup"
  RIGHTS="$(sql -c "select (select rolsuper from pg_roles where rolname = current_user)
      || '|' || count(*) filter (where has_table_privilege(c.oid, 'select'))
      || '|' || count(*)
      || '|' || count(*) filter (where has_table_privilege(c.oid, 'insert, update, delete, truncate'))
      || '|' || coalesce((select has_table_privilege(x.oid, 'select') from pg_class x join pg_namespace y on y.oid = x.relnamespace
                           where y.nspname = 'storage' and x.relname = 'objects'), false)
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname in ('public', 'canopy', 'acct') and c.relkind in ('r', 'p')")"
  IFS='|' read -r R_SUPER R_READ R_TOTAL R_WRITE R_PHOTOS <<< "$RIGHTS"
  if [ "$R_SUPER" != false ] || [ "$R_WRITE" != 0 ]; then
    STEP="revisar los permisos: canopy_backup puede cambiar $R_WRITE tablas del café (o es superusuario); ejecute otra vez supabase/tools/backup-account.sql"; false
  fi
  if [ "$R_READ" != "$R_TOTAL" ]; then
    STEP="revisar los permisos: canopy_backup lee $R_READ de $R_TOTAL tablas del café; ejecute otra vez supabase/tools/backup-account.sql"; false
  fi
  [ "$R_PHOTOS" = true ] || log "aviso: canopy_backup no puede leer la lista de fotos (storage.objects): ejecute otra vez supabase/tools/backup-account.sql"
  log "conexión verificada: entró canopy_backup (PostgreSQL $SERVER_VERSION); lee $R_READ de $R_TOTAL tablas del café y no puede cambiar ninguna. No se copió nada"
  [ -z "${WORK_DIR:-}" ] && rm -rf "$WORK"
  exit 0
fi

STEP="contar filas (antes)"
sql -c "$COUNT_SQL" > "$PACK/counts-before.json"
sql -c "$FP_SQL" > "$PACK/fingerprints-before.json"

STEP="volcar la base (pg_dump)"
log "volcando esquemas: $SCHEMAS"
SCHEMA_ARGS=(); for s in $SCHEMAS; do SCHEMA_ARGS+=(--schema="$s"); done
pg_dump "$CANOPY_DB_URL" --format=custom --no-owner --compress=6 "${SCHEMA_ARGS[@]}" --file="$PACK/app.dump"
pg_dump "$CANOPY_DB_URL" --schema-only --no-owner "${SCHEMA_ARGS[@]}" --file="$PACK/schema.sql"

STEP="contar filas (después)"
sql -c "$COUNT_SQL" > "$PACK/counts-after.json"
sql -c "$FP_SQL" > "$PACK/fingerprints-after.json"
sql -c "$PRIV_SQL" > "$PACK/privileges.md5"
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
  # Supabase keeps default rights for its own admin role in public (ALTER DEFAULT PRIVILEGES FOR ROLE
  # supabase_admin): that role is not on a throw-away server and postgres may not act for it on Supabase, so only
  # postgres's own default rights are restored
  pg_restore -l "$PACK/app.dump" | grep -v -E 'SCHEMA - public |COMMENT - SCHEMA public ' | awk '!(/ DEFAULT ACL / && $NF != "postgres")' > "$WORK/toc.list"
  psql -X -q -v ON_ERROR_STOP=1 "$TURL" -c "$DEFAULTS_OFF" >/dev/null
  pg_restore --no-owner --exit-on-error -L "$WORK/toc.list" -d "$TURL" "$PACK/app.dump"
  psql -X -q -v ON_ERROR_STOP=1 "$TURL" -c "$DEFAULTS_ON" >/dev/null
  psql -X -q -At "$TURL" -c "$COUNT_SQL" > "$PACK/counts-restored.json"
  if [ "$(psql -X -q -At "$TURL" -c "$PRIV_SQL")" != "$(cat "$PACK/privileges.md5")" ]; then
    psql -X -q "$RESTORE_TEST_URL" -c "drop database if exists $TESTDB" >/dev/null || true
    STEP="prueba de restauración: los permisos restaurados no son los de la base"; false
  fi
  psql -X -q -At "$TURL" -c "$FP_SQL" > "$PACK/fingerprints-restored.json"
  if python3 - "$PACK/counts-before.json" "$PACK/counts-after.json" "$PACK/counts-restored.json" \
               "$PACK/fingerprints-before.json" "$PACK/fingerprints-after.json" "$PACK/fingerprints-restored.json" <<'PY'
import json, sys
b, a, r, fb, fa, fr = (json.load(open(f)) for f in sys.argv[1:7])
bad = [t for t in a if not (min(b.get(t, 0), a[t]) <= r.get(t, -1) <= max(b.get(t, 0), a[t]))]
missing = [t for t in a if t not in r]
# a table nobody wrote to during the copy must come back with exactly the same content
quiet = [t for t in fa if fb.get(t) == fa[t]]
changed = [t for t in quiet if fr.get(t) != fa[t]]
busy = sorted(set(fa) - set(quiet))
if bad or missing or changed:
    print('tablas que no coinciden:', ', '.join(sorted(set(bad + missing + changed))[:20])); sys.exit(1)
print(f'restauración verificada: {len(r)} tablas, {sum(r.values())} filas; contenido idéntico en {len(quiet)} tablas'
      + (f'; {len(busy)} con movimiento durante la copia (filas dentro del rango): {", ".join(busy[:10])}' if busy else ''))
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
    # every listed file must be here, with the size Storage recorded
    STEP="verificar los archivos de $b"
    sql -c "select name || '|' || coalesce(metadata ->> 'size', '') from storage.objects where bucket_id = '$b' and name not like '%/.emptyFolderPlaceholder'" > "$WORK/sizes-$b.txt"
    python3 - "$PACK/storage/$b" "$WORK/sizes-$b.txt" "$PACK/storage-check-$b.json" <<'PY'
import json, os, sys
root, listing, out = sys.argv[1:4]
want = dict(l.rstrip('\n').rsplit('|', 1) for l in open(listing, encoding='utf-8') if l.strip())
missing = [n for n in want if not os.path.isfile(os.path.join(root, n))]
wrong = [n for n, s in want.items() if n not in missing and s and os.path.getsize(os.path.join(root, n)) != int(s)]
json.dump({'listed': len(want), 'copied': len(want) - len(missing), 'size_mismatch': wrong[:50], 'missing': missing[:50]}, open(out, 'w'))
if missing or wrong:
    print(f'faltan {len(missing)} y difieren {len(wrong)} de {len(want)} archivos:', ', '.join((missing + wrong)[:10])); sys.exit(1)
print(f'{len(want)} archivos verificados')
PY
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
load = lambda n: json.load(open(os.path.join(pack, n)))
if restore == 'passed':
    # what the dump holds, measured on its restored copy: every table's rows and content, also a table that was
    # written to during the copy (its count after the copy is not the dump's)
    counts, fps = load('counts-restored.json'), load('fingerprints-restored.json')
else:
    # no restore test: the rows after the copy, and the content of the tables nobody wrote to during it
    fb, fa = load('fingerprints-before.json'), load('fingerprints-after.json')
    counts, fps = load('counts-after.json'), {t: f for t, f in fa.items() if fb.get(t) == f}
json.dump({'started_at': started, 'server_version': server, 'pg_dump': client, 'restore_test': restore,
           'source': source, 'row_counts': counts,
           'fingerprints': fps,
           'privileges_md5': open(os.path.join(pack, 'privileges.md5')).read().strip(),
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
fi
if [ -n "${UPLOAD_DIR:-}" ]; then   # also (or only) a folder: e.g. the GitHub run keeps it as a downloadable file
  mkdir -p "$UPLOAD_DIR/$YEAR/$MONTH"
  cp "$WORK/$NAME.tar.age" "$WORK/$NAME.tar.age.sha256" "$UPLOAD_DIR/$YEAR/$MONTH/"
fi
if [ -z "${RCLONE_REMOTE:-}" ] && [ -z "${UPLOAD_DIR:-}" ]; then
  log "sin destino (RCLONE_REMOTE/UPLOAD_DIR): la copia queda en $WORK"
fi

STEP="anotar el resultado"
trap - ERR
report ok "respaldo completo" "$SIZE" "$NAME.tar.age"
log "listo: $NAME.tar.age ($SIZE bytes, restauración: $RESTORE_RESULT)"
[ -z "${WORK_DIR:-}" ] && rm -rf "$WORK"
exit 0
