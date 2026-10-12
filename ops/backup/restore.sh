#!/usr/bin/env bash
# =====================================================================================================
# Canopy OS · restore a backup
#   ops/backup/restore.sh <canopy-respaldo-....tar.age> <age-identity-file> <target-database-url> [--auth] [--yes]
#
# The target must be an EMPTY project: a new Supabase project (disaster) or the staging project after it
# was emptied (drill, docs/RESPALDOS.md). The script refuses a database that already has café data.
# It never touches the production database unless you point it there yourself, and even then it refuses
# because production is not empty.
#   --auth   also restores the logins (emails + password hashes) into auth.users (best effort)
#   --yes    do not ask for the typed confirmation (for the automated drill only)
# =====================================================================================================
set -euo pipefail
umask 077
ARCHIVE="${1:?Uso: restore.sh <archivo.tar.age> <llave-age> <url-de-la-base-destino> [--auth] [--yes]}"
IDENTITY="${2:?Falta el archivo de la llave privada age}"
TARGET="${3:?Falta la URL de la base de destino}"
shift 3
WITH_AUTH=0; ASSUME_YES=0
for a in "$@"; do case "$a" in --auth) WITH_AUTH=1;; --yes) ASSUME_YES=1;; esac; done
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

echo "1/6 Verificando la suma de control…"
if [ -f "$ARCHIVE.sha256" ]; then
  ( cd "$(dirname "$ARCHIVE")" && sha256sum -c "$(basename "$ARCHIVE").sha256" ) >/dev/null || { echo "La suma de control NO coincide: archivo dañado."; exit 1; }
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
  echo "Use un proyecto nuevo, o vacíe el proyecto de PRUEBAS como dice docs/RESPALDOS.md."
  exit 1
fi
if [ "$ASSUME_YES" != "1" ]; then
  read -r -p "Escriba RESTAURAR para cargar este respaldo en la base de destino: " ok
  [ "$ok" = "RESTAURAR" ] || { echo "Cancelado. No se cambió nada."; exit 1; }
fi

echo "4/6 Cargando la estructura y los datos…"
psql -X -q "$TARGET" -c "do \$\$ begin if not exists (select 1 from pg_roles where rolname = 'canopy_backup') then create role canopy_backup nologin; end if; end \$\$;" >/dev/null
pg_restore -l "$PACK/app.dump" | grep -v -E 'SCHEMA - public |COMMENT - SCHEMA public ' > "$WORK/toc.list"
pg_restore --no-owner --exit-on-error --single-transaction -L "$WORK/toc.list" -d "$TARGET" "$PACK/app.dump"

if [ "$WITH_AUTH" = "1" ] && [ -f "$PACK/auth-users.dump" ]; then
  echo "   Restaurando las cuentas de acceso…"
  pg_restore --data-only --no-owner -d "$TARGET" "$PACK/auth-users.dump" || echo "   Aviso: las cuentas no se pudieron cargar; créelas a mano (docs/RESPALDOS.md → Cuentas)."
fi

echo "5/6 Comparando filas…"
COUNT_SQL="select coalesce(jsonb_object_agg(t, n), '{}'::jsonb) from (
  select format('%s.%s', schemaname, relname) as t,
         (xpath('/row/c/text()', query_to_xml(format('select count(*) as c from %I.%I', schemaname, relname), false, true, '')))[1]::text::bigint as n
    from pg_stat_user_tables where schemaname in ('public','canopy','acct')) s"
psql -X -At "$TARGET" -c "$COUNT_SQL" > "$WORK/restored.json"
python3 - "$PACK/manifest.json" "$WORK/restored.json" <<'PY'
import json, sys
want = json.load(open(sys.argv[1]))['row_counts']; got = json.load(open(sys.argv[2]))
bad = {t: (n, got.get(t)) for t, n in want.items() if got.get(t) != n}
if bad: print('   NO coinciden:', bad); sys.exit(1)
print(f'   OK: {len(got)} tablas y {sum(got.values())} filas iguales al respaldo')
PY

echo "6/6 Fotos del menú: están en $PACK/storage (copie la carpeta si va a subirlas)."
if [ -d "$PACK/storage" ] && [ -n "${KEEP_STORAGE_TO:-}" ]; then cp -R "$PACK/storage" "$KEEP_STORAGE_TO"; fi
cat <<'TXT'

Restauración terminada. Falta, a mano (docs/RESPALDOS.md → "Después de restaurar"):
  · Subir las fotos del menú (carpeta storage/menu-photos) al bucket menu-photos.
  · Volver a poner los secretos de Vault (token del BCCR y otros), que nunca van en el respaldo.
  · Revisar Authentication → URL Configuration y volver a inscribir el código del teléfono (2FA).
  · Si el proyecto es nuevo: cambiar la dirección en website/config.js y publicar con aprobación del dueño.
TXT
