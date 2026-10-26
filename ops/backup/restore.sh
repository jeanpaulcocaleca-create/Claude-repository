#!/usr/bin/env bash
# =====================================================================================================
# Canopy OS · restore a backup
#   ops/backup/restore.sh <canopy-respaldo-....tar.age> <age-identity-file> <target-database-url> [--yes]
#
# The target must be an EMPTY database: a new Supabase project (disaster), or a clean PostgreSQL such as a Docker
# container on the owner's computer (drill, docs/RESPALDOS.md). A clean PostgreSQL has none of what Supabase provides
# (the API roles, the auth and storage schemas that the policies and functions name, the extensions schema): the
# script gives it that shape itself with restore-stub.sql, kept next to it, the same way the nightly restore test and
# the rehearsal do (D-046). On a Supabase project nothing of that is touched. The script refuses a database that
# already has café data. It never touches the production database unless you point it there yourself, and even then
# it refuses because production is not empty.
# The logins (auth) are not in the backup: create them again by hand (docs/RESPALDOS.md → Cuentas de acceso).
#   --yes    do not ask for the typed confirmation (for the automated drill only)
# =====================================================================================================
set -euo pipefail
umask 077
export PGTZ=UTC   # fingerprints compare text: the same time zone as the backup
ARCHIVE="${1:?Uso: restore.sh <archivo.tar.age> <llave-age> <url-de-la-base-destino> [--yes]}"
IDENTITY="${2:?Falta el archivo de la llave privada age}"
TARGET="${3:?Falta la URL de la base de destino}"
shift 3
ASSUME_YES=0
for a in "$@"; do case "$a" in --yes) ASSUME_YES=1;;
  --auth) echo "Las cuentas de acceso no van en el respaldo: créelas a mano (docs/RESPALDOS.md → Cuentas de acceso).";; esac; done
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

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

echo "1/6 Verificando la suma de control…"
# the .sha256 file is in sha256sum's format; macOS has no sha256sum unless coreutils is installed, but shasum reads it
sum_check() { if command -v sha256sum >/dev/null 2>&1; then sha256sum -c "$1"; else shasum -a 256 -c "$1"; fi; }
if [ -f "$ARCHIVE.sha256" ]; then
  command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1 || { echo "Falta sha256sum (coreutils) o shasum para verificar la suma de control. No se cambió nada."; exit 1; }
  ( cd "$(dirname "$ARCHIVE")" && sum_check "$(basename "$ARCHIVE").sha256" ) >/dev/null || { echo "La suma de control NO coincide: archivo dañado."; exit 1; }
else
  echo "   (no hay archivo .sha256 al lado; se sigue con la verificación interna)"
fi

echo "2/6 Descifrando (necesita la llave privada)…"
age -d -i "$IDENTITY" -o "$WORK/respaldo.tar" "$ARCHIVE" 2>/dev/null || { echo "No se pudo descifrar: la llave no corresponde a este respaldo o el archivo está dañado."; exit 1; }
tar -C "$WORK" -xf "$WORK/respaldo.tar" && rm -f "$WORK/respaldo.tar"
PACK="$(find "$WORK" -mindepth 1 -maxdepth 1 -type d | head -1)"
python3 - "$PACK" <<'PY'
import hashlib, json, os, sys
pack = sys.argv[1]; m = json.load(open(os.path.join(pack, 'manifest.json')))
bad = [f for f, h in m['files'].items() if hashlib.sha256(open(os.path.join(pack, f), 'rb').read()).hexdigest() != h]
if bad: print('Archivos dañados dentro del respaldo:', bad); sys.exit(1)
rc = m['row_counts']
print(f"   Respaldo del {m['started_at']} · servidor {m['server_version']} · prueba de restauración: {m['restore_test']}")
for t in ('public.orders', 'public.order_items', 'public.stock_moves', 'public.time_entries', 'public.register_days'):
    if t in rc: print(f"   {t}: {rc[t]} filas")
PY

echo "3/6 Revisando que la base de destino esté vacía…"
HAS="$(psql -X -At "$TARGET" -c "select count(*) from information_schema.tables where table_schema in ('public','canopy','acct')")"
if [ "$HAS" != "0" ]; then
  echo "La base de destino YA tiene $HAS tablas. Por seguridad no se restaura encima."
  echo "Use un proyecto nuevo o una base desechable vacía (docs/RESPALDOS.md → Prueba de restauración)."
  exit 1
fi
# A clean PostgreSQL (a Docker container for a drill) has none of what Supabase provides and the dump names: the API
# roles in its GRANTs, auth.uid()/auth.jwt() in the policies (37 at backup #9), the extensions schema in column defaults. restore-stub.sql
# gives it that shape, as the nightly restore test and the rehearsal do before loading. A Supabase project is known by
# its auth schema (and its supabase_admin role): there nothing of this runs. The kind is decided before the typed
# confirmation, so the prompt says it and a missing stub is found before anything happens.
IS_SUPABASE="$(psql -X -At "$TARGET" -c "select exists (select 1 from pg_namespace where nspname = 'auth') or exists (select 1 from pg_roles where rolname = 'supabase_admin')")"
if [ "$IS_SUPABASE" = "f" ]; then
  [ -f "$HERE/restore-stub.sql" ] || { echo "El destino es un PostgreSQL limpio (no es Supabase) y falta $HERE/restore-stub.sql, que le da la forma de Supabase. Copie restore-stub.sql junto a restore.sh. No se cambió nada."; exit 1; }
  KIND="un PostgreSQL limpio: se le dará la forma de Supabase con restore-stub.sql"
else
  # a Supabase project, or a base already given the shape: all of it must be there (a stub interrupted halfway is not)
  ROLES="$(psql -X -At "$TARGET" -c "select count(*) from pg_roles where rolname in ('anon','authenticated','service_role')")"
  SHAPE="$(psql -X -At "$TARGET" -c "select count(*) from pg_namespace where nspname = any (array['auth', 'storage', 'extensions'])")"
  if [ "$ROLES" != "3" ] || [ "$SHAPE" != "3" ]; then
    echo "El destino tiene solo parte de la forma de Supabase (roles de la API: $ROLES de 3; esquemas auth, storage y extensions: $SHAPE de 3): no es un proyecto Supabase ni un PostgreSQL limpio (por ejemplo, una preparación interrumpida). Use una base nueva. No se cambió nada."
    exit 1
  fi
  KIND="un proyecto Supabase o una base ya preparada (no se cambia nada de su forma)"
fi
echo "   Destino: $KIND"
if [ "$ASSUME_YES" != "1" ]; then
  read -r -p "Escriba RESTAURAR para cargar este respaldo en la base de destino: " ok
  [ "$ok" = "RESTAURAR" ] || { echo "Cancelado. No se cambió nada."; exit 1; }
fi

if [ "$IS_SUPABASE" = "f" ]; then
  echo "   Dando al destino la forma de Supabase (roles, auth, storage, extensions) con restore-stub.sql, en una sola transacción…"
  echo "   Aviso: el stub crea el ingreso 'authenticator' con la contraseña pública de los entornos de prueba: esta base debe escuchar solo en 127.0.0.1 y borrarse al terminar."
  PGOPTIONS='-c client_min_messages=warning' psql -X -q -v ON_ERROR_STOP=1 --single-transaction "$TARGET" -f "$HERE/restore-stub.sql" >/dev/null \
    || { echo "No se pudo preparar el destino con restore-stub.sql; nada quedó a medias. No se restauró nada."; exit 1; }
fi

echo "4/6 Cargando la estructura y los datos…"
psql -X -q "$TARGET" -c "do \$\$ begin if not exists (select 1 from pg_roles where rolname = 'canopy_backup') then create role canopy_backup nologin; end if; end \$\$;" >/dev/null
# Supabase keeps default rights for its own admin role in public (ALTER DEFAULT PRIVILEGES FOR ROLE
# supabase_admin): that role is not on a throw-away server and postgres may not act for it on Supabase, so only
# postgres's own default rights are restored
pg_restore -l "$PACK/app.dump" | grep -v -E 'SCHEMA - public |COMMENT - SCHEMA public ' | awk '!(/ DEFAULT ACL / && $NF != "postgres")' > "$WORK/toc.list"
psql -X -q -v ON_ERROR_STOP=1 "$TARGET" -c "$DEFAULTS_OFF" >/dev/null
pg_restore --no-owner --exit-on-error --single-transaction -L "$WORK/toc.list" -d "$TARGET" "$PACK/app.dump"
psql -X -q -v ON_ERROR_STOP=1 "$TARGET" -c "$DEFAULTS_ON" >/dev/null

echo "5/6 Comparando filas y contenido…"
COUNT_SQL="select coalesce(jsonb_object_agg(t, n), '{}'::jsonb) from (
  select format('%s.%s', schemaname, relname) as t,
         (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I', schemaname, relname), false, true, '')))[1]::text::bigint as n
    from pg_stat_user_tables where schemaname in ('public','canopy','acct')) s"
FP_SQL="select coalesce(jsonb_object_agg(t, f), '{}'::jsonb) from (
  select format('%s.%s', schemaname, relname) as t,
         (xpath('/row/f/text()', query_to_xml(format('select count(*)::text || '':'' || coalesce(md5(string_agg(x::text, E''\\n'' order by x::text collate \"C\")), ''-'') as f from %I.%I x', schemaname, relname), false, true, '')))[1]::text as f
    from pg_stat_user_tables where schemaname in ('public','canopy','acct')) s"
psql -X -At "$TARGET" -c "$COUNT_SQL" > "$WORK/restored.json"
psql -X -At "$TARGET" -c "$FP_SQL" > "$WORK/restored-fp.json"
psql -X -At "$TARGET" -c "$PRIV_SQL" > "$WORK/restored-priv.md5"
python3 - "$PACK/manifest.json" "$WORK/restored.json" "$WORK/restored-fp.json" "$WORK/restored-priv.md5" <<'PY'
import json, sys
m = json.load(open(sys.argv[1])); got = json.load(open(sys.argv[2])); fp = json.load(open(sys.argv[3]))
priv = open(sys.argv[4]).read().strip()
if m.get('privileges_md5') and m['privileges_md5'] != priv:
    print('   Los PERMISOS restaurados no son los del respaldo (quién puede ejecutar o leer qué). No use esta base: avise.'); sys.exit(1)
want = m['row_counts']
bad = {t: (n, got.get(t)) for t, n in want.items() if got.get(t) != n}
if bad: print('   NO coinciden:', bad); sys.exit(1)
# older backups have no fingerprints: rows only
diff = [t for t, f in m.get('fingerprints', {}).items() if fp.get(t) != f]
if diff: print('   El contenido NO coincide en:', ', '.join(diff[:20])); sys.exit(1)
print(f'   OK: {len(got)} tablas y {sum(got.values())} filas iguales al respaldo; contenido idéntico en {len(m.get("fingerprints", {}))} tablas')
PY

# the temporary folder is deleted when this script ends: the photos are copied next to the backup file first
PHOTOS="${KEEP_STORAGE_TO:-$(cd "$(dirname "$ARCHIVE")" && pwd)/fotos-restauradas-$(date -u +%Y%m%d-%H%M%SZ)}"
if [ -d "$PACK/storage" ] && [ -n "$(find "$PACK/storage" -type f | head -1)" ]; then
  mkdir -p "$PHOTOS" && cp -R "$PACK/storage/." "$PHOTOS/"
  echo "6/6 Fotos del menú ($(find "$PHOTOS" -type f | wc -l | tr -d ' ') archivos, ya comprobados en el paso 2) copiadas a: $PHOTOS"
  echo "    Esa carpeta NO está cifrada (puede traer facturas de gastos): bórrela cuando haya subido las fotos, y antes de"
  echo "    copiar la carpeta de respaldos a la memoria USB."
else
  echo "6/6 Este respaldo no trae fotos del menú."
fi
cat <<'TXT'

Restauración terminada. Falta, a mano (docs/RESPALDOS.md → "Después de restaurar"):
  · Subir las fotos del menú (la carpeta menu-photos dentro de la carpeta de fotos de arriba) al bucket menu-photos.
  · Volver a poner los secretos de Vault (token del BCCR y otros), que nunca van en el respaldo.
  · Revisar Authentication → URL Configuration y volver a inscribir el código del teléfono (2FA).
  · Si el proyecto es nuevo: cambiar la dirección en website/config.js y publicar con aprobación del dueño.
TXT
