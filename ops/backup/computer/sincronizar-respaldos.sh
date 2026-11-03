#!/usr/bin/env bash
# =====================================================================================================
# Canopy OS · copia los respaldos cifrados a esta computadora (macOS / Linux)
# Corre cada hora y al encender (launchd / cron). Si la computadora estuvo apagada, al encender trae
# TODOS los respaldos que faltan: la nube los siguió haciendo mientras tanto.
#
# Configuración: archivo ~/.canopy-respaldos.conf (vea docs/RESPALDOS.md), con por ejemplo:
#   REMOTE="offsite:canopy-respaldos"            # destino rclone de solo LECTURA (o)
#   SOURCE_DIR="/Volumes/USB/canopy-respaldos"   # una carpeta (USB o pruebas)
#   DEST="$HOME/Documents/HangingGarden-Respaldos"
# Guarda: todo lo de los últimos 14 días, uno por semana por 8 semanas, uno por mes por 24 meses y
# uno por año para siempre. Nunca borra nada de la nube. Escribe ESTADO.txt y avisa si algo anda mal.
# =====================================================================================================
set -uo pipefail
CONF="${CANOPY_CONF:-$HOME/.canopy-respaldos.conf}"
[ -f "$CONF" ] && . "$CONF"
DEST="${DEST:-$HOME/Documents/HangingGarden-Respaldos}"
LATE_HOURS="${LATE_HOURS:-36}"
NOW_EPOCH="${NOW_EPOCH:-$(date -u +%s)}"   # (pruebas pueden fijar la hora)
mkdir -p "$DEST/archivo"
LOG="$DEST/registro.txt"
problems=()

say() { echo "$(date '+%Y-%m-%d %H:%M') $*" | tee -a "$LOG"; }
notify() {
  if command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"$1\" with title \"Respaldos del café\"" >/dev/null 2>&1 || true
  elif command -v notify-send >/dev/null 2>&1; then notify-send "Respaldos del café" "$1" || true; fi
}
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

# 1) traer lo nuevo (nunca sobrescribe ni borra)
INBOX="$DEST/.entrada"; mkdir -p "$INBOX"
if [ -n "${REMOTE:-}" ]; then
  rclone copy "$REMOTE" "$INBOX" --include '*.tar.age' --include '*.tar.age.sha256' --immutable --max-age 400d >>"$LOG" 2>&1 \
    || problems+=("no se pudo conectar con la copia en la nube")
elif [ -n "${SOURCE_DIR:-}" ]; then
  find "$SOURCE_DIR" -type f \( -name '*.tar.age' -o -name '*.tar.age.sha256' \) -exec cp -n {} "$INBOX/" \; 2>>"$LOG" \
    || problems+=("no se pudo leer $SOURCE_DIR")
else
  problems+=("falta REMOTE o SOURCE_DIR en $CONF")
fi

# 2) verificar y archivar
find "$INBOX" -type f -name '*.tar.age' | while read -r f; do
  b="$(basename "$f")"
  [ -f "$DEST/archivo/$b" ] && { rm -f "$f" "$f.sha256"; continue; }
  sumfile="$(find "$INBOX" -name "$b.sha256" | head -1)"
  if [ -z "$sumfile" ]; then continue; fi        # todavía bajando: se completa en la próxima corrida
  if [ "$(sha "$f")" = "$(cut -d' ' -f1 < "$sumfile")" ]; then
    mv "$f" "$DEST/archivo/$b"; mv "$sumfile" "$DEST/archivo/$b.sha256"; say "guardado $b"
  else
    say "DAÑADO $b (la suma no coincide); se volverá a bajar"; rm -f "$f" "$sumfile"; echo bad > "$DEST/.damaged"
  fi
done
[ -f "$DEST/.damaged" ] && { problems+=("un respaldo llegó dañado y se volverá a bajar"); rm -f "$DEST/.damaged"; }

# 3) cuántos guardar (por la fecha en el nombre: canopy-respaldo-YYYYMMDD-HHMMZ.tar.age)
ls "$DEST/archivo" 2>/dev/null | grep -E '^canopy-respaldo-[0-9]{8}-[0-9]{4}Z\.tar\.age$' | sort | awk -v now="$NOW_EPOCH" '
  function days(y, m, d) { y -= (m <= 2); era = int((y >= 0 ? y : y - 399) / 400); yoe = y - era * 400;
                           doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1;
                           doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy; return era * 146097 + doe - 719468 }
  { s = substr($0, 17, 8); d = days(substr(s, 1, 4) + 0, substr(s, 5, 2) + 0, substr(s, 7, 2) + 0);
    age = int(now / 86400) - d; name[NR] = $0; dd[NR] = d; ag[NR] = age
    wk = int((d + 3) / 7); mo = substr(s, 1, 6); yr = substr(s, 1, 4)
    lastw[wk] = NR; lastm[mo] = NR; lasty[yr] = NR; w[NR] = wk; m[NR] = mo; yy[NR] = yr }
  END { for (i = 1; i <= NR; i++) {
          keep = (ag[i] <= 14) || (ag[i] <= 56 && lastw[w[i]] == i) || (ag[i] <= 731 && lastm[m[i]] == i) || (lasty[yy[i]] == i)
          if (!keep) print name[i] } }' | while read -r old; do
  rm -f "$DEST/archivo/$old" "$DEST/archivo/$old.sha256"; say "retirado (política de guardado) $old"
done

# 4) estado
newest="$(ls "$DEST/archivo" 2>/dev/null | grep -E '\.tar\.age$' | sort | tail -1)"
count="$(ls "$DEST/archivo" 2>/dev/null | grep -cE '\.tar\.age$')"
if [ -z "$newest" ]; then
  problems+=("todavía no hay ningún respaldo en esta computadora")
else
  s="${newest:16:13}"   # YYYYMMDD-HHMM
  ts="$(date -u -d "${s:0:8} ${s:9:2}:${s:11:2}" +%s 2>/dev/null || date -u -j -f '%Y%m%d %H%M' "${s:0:8} ${s:9:4}" +%s)"
  hours=$(( (NOW_EPOCH - ts) / 3600 ))
  [ "$hours" -gt "$LATE_HOURS" ] && problems+=("el respaldo más nuevo tiene $hours horas")
fi
{
  echo "Respaldos del café · revisado $(date '+%Y-%m-%d %H:%M')"
  echo "Respaldos guardados en esta computadora: $count"
  echo "Más nuevo: ${newest:-ninguno}"
  if [ ${#problems[@]} -eq 0 ]; then echo "Estado: BIEN"; else echo "Estado: ATENCIÓN"; printf ' - %s\n' "${problems[@]}"; fi
} > "$DEST/ESTADO.txt"
if [ ${#problems[@]} -gt 0 ]; then notify "${problems[0]}"; say "ATENCIÓN: ${problems[*]}"; exit 1; fi
exit 0
