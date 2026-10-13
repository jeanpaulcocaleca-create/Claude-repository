#!/usr/bin/env bash
# =====================================================================================================
# Canopy OS · ENSAYO EN PRUEBAS: copia anonimizada de producción → proyecto de PRUEBAS → migraciones.
#   1. copia producción con la cuenta de SOLO LECTURA (canopy_backup); es el único paso que la usa
#   2. la carga en una base desechable del trabajo y la ANONIMIZA (anonimizar.sql)
#   3. vacía el proyecto de PRUEBAS (solo si se pidió) y carga la copia anonimizada
#   4. foto + consistencia ANTES, aplica las migraciones del repositorio público, foto + consistencia DESPUÉS
# Nunca escribe en producción: se niega si la cuenta de producción podría escribir o si la dirección de pruebas es
# la de producción, y anonimiza solo en el Postgres desechable del trabajo. Los archivos SQL del repositorio público
# se envían con "psql -c" (el servidor ejecuta solo SQL; ningún comando de psql ni de la terminal escrito en esos
# archivos se ejecuta aquí). El registro muestra solo pasos, cantidades y tiempos: ni datos, ni el PIN, ni contraseñas.
#
# Variables: CANOPY_DB_URL (producción, solo lectura) · STAGING_DB_URL (pruebas) · STAGING_PIN · PROD_URL
#            (https://<proyecto>.supabase.co de producción) · SCRATCH_URL (Postgres desechable del trabajo)
#            PUBLIC_DIR (el repositorio público en la versión a ensayar) · OUT (carpeta de resultados)
#            EMPTY_STAGING=si para vaciar pruebas antes de cargar · SCRATCH_DB (opcional; canopy_ensayo)
# =====================================================================================================
set -euo pipefail
umask 077
export PGTZ=UTC
: "${CANOPY_DB_URL:?}" "${STAGING_DB_URL:?}" "${STAGING_PIN:?}" "${PROD_URL:?}" "${SCRATCH_URL:?}" "${PUBLIC_DIR:?}" "${OUT:?}"
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$OUT"
log() { echo "[$(date -u +%H:%M:%S)] $*"; }
die() { echo "::error::$*"; exit 1; }
SCRATCH_DB="${SCRATCH_DB:-canopy_ensayo}"   # the throw-away database on SCRATCH_URL (tests give each run its own)
# a malformed address would make psql quote it, password included, in its error: check the shape first, never echo it.
# The password may hold letters, digits and - . _ ~ ! $ & ( ) * + , ; = or %XX escapes (a raw @ / ? # % breaks the address)
URL_RE='^postgres(ql)?://[A-Za-z0-9._-]+(:([A-Za-z0-9._~!$&()*+,;=-]|%(0[1-9A-Fa-f]|[1-9A-Fa-f][0-9A-Fa-f]))+)?@[A-Za-z0-9.-]+(:[0-9]+)?/[A-Za-z0-9_]+(\?[A-Za-z0-9_=&.-]*)?$'
for v in CANOPY_DB_URL STAGING_DB_URL SCRATCH_URL; do
  [[ "${!v}" =~ $URL_RE ]] || die "$v no es una dirección postgresql://usuario:contraseña@servidor:puerto/base de una sola línea (en la contraseña: letras, números o %XX). No se hizo nada."
done
[[ "$STAGING_PIN" =~ ^[0-9]{4,8}$ ]] || die "STAGING_PIN debe tener de 4 a 8 dígitos. No se hizo nada."
PROD_REF="$(printf '%s' "$PROD_URL" | sed -E 's#https://([a-z0-9]+)\.supabase\.co.*#\1#')"
[ -n "$PROD_REF" ] && [ "$PROD_REF" != "$PROD_URL" ] || die "PROD_URL no parece una dirección de Supabase"
case "$STAGING_DB_URL" in *"$PROD_REF"*) die "La dirección de PRUEBAS contiene el proyecto de PRODUCCIÓN ($PROD_REF). No se hizo nada.";; esac
[ "$STAGING_DB_URL" != "$CANOPY_DB_URL" ] || die "PRUEBAS y producción son la misma dirección. No se hizo nada."
# the copy is anonymized (and its database dropped and created) only on the job's own throw-away server
case "$SCRATCH_URL" in *supabase*) die "SCRATCH_URL debe ser la base desechable del trabajo, nunca un proyecto de Supabase. No se hizo nada.";; esac
# copies with real data never outlive the job's step, also when a step fails
trap 'rm -f "$OUT/produccion.dump" "$OUT/anonimizada.dump" "$OUT/toc.list"' EXIT
# public SQL goes to the server as-is: refuse a file that would start with a psql command
run_public() {  # url file [extra psql flags]
  local url="$1" f="$2"; shift 2
  [ "$(grep -v '^\s*--' "$f" | grep -v '^\s*$' | head -c 1)" != '\' ] || die "$(basename "$f") empieza con un comando de psql; no se ejecuta"
  psql -X -q -At -v ON_ERROR_STOP=1 "$url" "$@" -c "$(cat "$f")"
}

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

# pg_restore's errors carry the server's DETAIL/CONTEXT lines, which can quote a whole row ("Failing row contains",
# "COPY orders, line 3: …"): keep only its own one-line messages in the log
restore_quiet() { pg_restore "$@" 2> >(grep --line-buffered '^pg_restore:' >&2 || true); }

# staging must be empty, or emptied on request: known before production is read
HAS="$(psql -X -At "$STAGING_DB_URL" -c "select count(*) from information_schema.tables where table_schema in ('public','canopy','acct')")"
if [ "$HAS" != "0" ]; then
  case "${EMPTY_STAGING:-no}" in si|sí|Si|Sí|SI|SÍ) ;; *) die "PRUEBAS ya tiene $HAS tablas. Corra otra vez con «vaciar pruebas» = si.";; esac
fi

log "1/4 copiando producción (solo lectura)…"
# production is read only with the backup account: refuse an account that could change it (the owner's, for example)
[ "$(psql -X -At "$CANOPY_DB_URL" -c "select not (r.rolsuper or coalesce(has_table_privilege('public.orders', 'insert') or has_table_privilege('public.orders', 'update')
          or has_table_privilege('public.orders', 'delete'), false)) from pg_roles r where r.rolname = current_user")" = "t" ] \
  || die "No se pudo comprobar que CANOPY_DB_URL sea la cuenta de solo lectura canopy_backup. No se copió nada."
SCHEMAS="$(psql -X -At "$CANOPY_DB_URL" -c "select string_agg('--schema=' || nspname, ' ') from pg_namespace where nspname in ('public','canopy','acct')")"
# shellcheck disable=SC2086
pg_dump "$CANOPY_DB_URL" --format=custom --no-owner $SCHEMAS --file="$OUT/produccion.dump"
PROD_PRIV="$(psql -X -At "$CANOPY_DB_URL" -c "$PRIV_SQL")"
unset CANOPY_DB_URL

log "2/4 anonimizando en una base desechable…"
psql -X -q "$SCRATCH_URL" -c "drop database if exists $SCRATCH_DB" -c "create database $SCRATCH_DB" >/dev/null
TMP_URL="$(python3 - "$SCRATCH_URL" "$SCRATCH_DB" <<'PY'
import sys, urllib.parse as u
p = u.urlsplit(sys.argv[1]); print(u.urlunsplit(p._replace(path='/' + sys.argv[2])))
PY
)"
psql -X -q -v ON_ERROR_STOP=1 "$TMP_URL" -f "$HERE/restore-stub.sql" >/dev/null
# Supabase keeps default rights for its own admin role in public (ALTER DEFAULT PRIVILEGES FOR ROLE
# supabase_admin): that role is not on a throw-away server and postgres may not act for it on Supabase, so only
# postgres's own default rights are restored
pg_restore -l "$OUT/produccion.dump" | grep -v -E 'SCHEMA - public |COMMENT - SCHEMA public ' | awk '!(/ DEFAULT ACL / && $NF != "postgres")' > "$OUT/toc.list"
psql -X -q -v ON_ERROR_STOP=1 "$TMP_URL" -c "$DEFAULTS_OFF" >/dev/null
restore_quiet --no-owner --exit-on-error -L "$OUT/toc.list" -d "$TMP_URL" "$OUT/produccion.dump"
psql -X -q -v ON_ERROR_STOP=1 "$TMP_URL" -c "$DEFAULTS_ON" >/dev/null
[ "$(psql -X -At "$TMP_URL" -c "$PRIV_SQL")" = "$PROD_PRIV" ] || die "la copia desechable no tiene los permisos de producción"
rm -f "$OUT/produccion.dump"
# terse: if a step fails, the error must not print the row it was working on (production data) into the log
psql -X -q -At -v ON_ERROR_STOP=1 -v VERBOSITY=terse -v pin="$STAGING_PIN" "$TMP_URL" -f "$HERE/anonimizar.sql" | tail -1
pg_dump "$TMP_URL" --format=custom --no-owner $SCHEMAS --file="$OUT/anonimizada.dump"
psql -X -q "$SCRATCH_URL" -c "drop database if exists $SCRATCH_DB" >/dev/null

log "3/4 cargando la copia anonimizada en PRUEBAS…"
if [ "$HAS" != "0" ]; then
  # staging only: drop what the café's schema put there, keep the public schema itself (and Supabase's grants on it)
  psql -X -q -v ON_ERROR_STOP=1 "$STAGING_DB_URL" <<'SQL'
do $$
declare r record;
begin
  -- the receipt rules on storage.objects call public functions: drop them by name first, the same way 0015 does
  -- (Supabase lets the SQL Editor's account manage policies there), so no cascade has to reach Storage's table
  drop policy if exists "expense receipts read" on storage.objects;
  drop policy if exists "expense receipts add" on storage.objects;
  drop schema if exists canopy cascade;
  drop schema if exists acct cascade;
  for r in select format('%I.%I', schemaname, tablename) as t from pg_tables where schemaname = 'public' loop
    execute 'drop table if exists ' || r.t || ' cascade'; end loop;
  for r in select p.oid::regprocedure as f from pg_proc p where p.pronamespace = 'public'::regnamespace
              and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e') loop
    execute 'drop function if exists ' || r.f || ' cascade'; end loop;
  for r in select format('%I.%I', n.nspname, t.typname) as ty from pg_type t join pg_namespace n on n.oid = t.typnamespace
            where n.nspname = 'public' and t.typtype in ('e', 'd', 'c') and not exists (select 1 from pg_class c where c.reltype = t.oid) loop
    execute 'drop type if exists ' || r.ty || ' cascade'; end loop;
  -- Supabase Storage refuses direct deletes from its tables unless this is set (storage-api migration 0055; its
  -- trigger fires even when no row matches). Only the rows go: the staging receipt files stay orphaned in staging Storage.
  perform set_config('storage.allow_delete_query', 'true', true);
  delete from storage.objects where bucket_id = 'expense-receipts';
end $$;
SQL
fi
# Supabase keeps default rights for its own admin role in public (ALTER DEFAULT PRIVILEGES FOR ROLE
# supabase_admin): that role is not on a throw-away server and postgres may not act for it on Supabase, so only
# postgres's own default rights are restored
pg_restore -l "$OUT/anonimizada.dump" | grep -v -E 'SCHEMA - public |COMMENT - SCHEMA public ' | awk '!(/ DEFAULT ACL / && $NF != "postgres")' > "$OUT/toc.list"
# production's rights mention the backup account: it must exist in staging too (never able to log in there)
psql -X -q -v ON_ERROR_STOP=1 "$STAGING_DB_URL" -c "do \$\$ begin if not exists (select 1 from pg_roles where rolname = 'canopy_backup') then create role canopy_backup nologin; end if; end \$\$;" >/dev/null
psql -X -q -v ON_ERROR_STOP=1 "$STAGING_DB_URL" -c "$DEFAULTS_OFF" >/dev/null
restore_quiet --no-owner --exit-on-error -L "$OUT/toc.list" -d "$STAGING_DB_URL" "$OUT/anonimizada.dump"
psql -X -q -v ON_ERROR_STOP=1 "$STAGING_DB_URL" -c "$DEFAULTS_ON" >/dev/null
[ "$(psql -X -At "$STAGING_DB_URL" -c "$PRIV_SQL")" = "$PROD_PRIV" ] || die "PRUEBAS quedó con permisos distintos de producción (revise antes de usarla)"
rm -f "$OUT/anonimizada.dump" "$OUT/toc.list"

log "4/4 ensayo de las migraciones en PRUEBAS…"
run_public "$STAGING_DB_URL" "$PUBLIC_DIR/supabase/tools/production-snapshot.sql" > "$OUT/snapshot-before.json"
run_public "$STAGING_DB_URL" "$PUBLIC_DIR/supabase/tools/consistency-check.sql" > "$OUT/consistency-before.json"
LAST=-1
if [ "$(psql -X -At "$STAGING_DB_URL" -c "select to_regclass('canopy.migrations') is not null")" = "t" ]; then
  LAST="$(psql -X -At "$STAGING_DB_URL" -c "select coalesce(max(version), -1) from canopy.migrations")"
fi
: > "$OUT/timings.txt"
for m in $(ls "$PUBLIC_DIR/supabase/migrations"/*.sql | sort); do
  v=$((10#$(basename "$m" | cut -c1-4)))
  [ "$v" -le "$LAST" ] && continue
  s=$(date +%s%N)
  run_public "$STAGING_DB_URL" "$m" > /dev/null || die "la migración $(basename "$m") falló en PRUEBAS (nada se aplicó de ese archivo)"
  printf '%s %s ms\n' "$(basename "$m" .sql)" "$(( ($(date +%s%N) - s) / 1000000 ))" | tee -a "$OUT/timings.txt"
done
run_public "$STAGING_DB_URL" "$PUBLIC_DIR/supabase/tools/production-snapshot.sql" > "$OUT/snapshot-after.json"
run_public "$STAGING_DB_URL" "$PUBLIC_DIR/supabase/tools/consistency-check.sql" > "$OUT/consistency-after.json"
run_public "$STAGING_DB_URL" "$PUBLIC_DIR/supabase/tools/release-check.sql" > "$OUT/release-check.json"
log "listo: resultados en $OUT (la comparación corre en el paso siguiente, sin contraseñas)"
