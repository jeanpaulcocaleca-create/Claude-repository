#!/usr/bin/env bash
# Canopy OS · «no tocar» v2 (docs/PANTALLAS.md, the owner's condition 2 of 2026-10-31). The café's pages (website/:
# Caja, Cocina, Contabilidad, menú QR, TV actual, …), the database migrations and the publishing workflow stay byte for
# byte those of the last release the owner published (tests/pantallas/BASE); the customer screens only ADD the files in
# NEW below. It proves:
#   1) the release tag names the BASE commit: the local tag when there is one, and origin's (git ls-remote) when origin
#      answers; a tag that names another commit fails;
#   2) every file of BASE under website/ and supabase/migrations/, and .github/workflows/pages.yml, has BASE's exact
#      bytes in the working tree (hashed without filters, so no line-ending rule and no assume-unchanged flag hides a
#      change) and in the index (same blob, same mode); none is deleted, renamed or turned into a link;
#   3) every other file there, in the index or new in the working tree (ignored files aside: they never reach a
#      commit), is one of NEW.
# Read-only: it writes no file of the checkout, no index, no ref and no tag. Only when the BASE commit is missing from
# the object store (CI's shallow checkout) it fetches that commit's objects by SHA (--depth=1 only in a clone that is
# already shallow) without writing FETCH_HEAD. GIT_DIR and GIT_WORK_TREE (absolute paths) point it at another checkout.
# Usage: bash tests/pantallas/no-tocar.sh
set -euo pipefail
export LC_ALL=C GIT_OPTIONAL_LOCKS=0 GIT_TERMINAL_PROMPT=0
HERE="$(cd "$(dirname "$0")" && pwd)"
# the only new files the screens may add (the owner's plan of 2026-10-31); pantallas.js only if the page uses one
NEW=(website/pantalla-menu.html website/pantalla-promos.html website/pantallas.html website/pantallas.js
     supabase/migrations/0036_pantallas.sql)
PATHS=(website supabase/migrations .github/workflows/pages.yml)
fail() { echo "  FAIL  no tocar: $*"; exit 1; }

TOP="$(cd "$HERE/../.." && git rev-parse --show-toplevel 2>/dev/null)" || fail "no es un repositorio git · not a git repository"
g() { git -C "$TOP" -c core.quotePath=false "$@"; }
TAG="$(awk '$1 == "tag" { print $2 }' "$HERE/BASE" 2>/dev/null || true)"
BASE="$(awk '$1 == "commit" { print $2 }' "$HERE/BASE" 2>/dev/null || true)"
[[ "$TAG" =~ ^v[0-9]{4}\.[0-9]{2}\.[0-9]{2}-[0-9]+$ && "$BASE" =~ ^[0-9a-f]{40}$ ]] \
  || fail "tests/pantallas/BASE necesita una línea «tag v…» y una «commit <sha>» · BASE needs one 'tag' and one 'commit' line"
B7="${BASE:0:7}"

# 1) the tag names BASE (read only: the local ref, and origin's list of refs)
loc="$(g rev-parse -q --verify "refs/tags/$TAG^{commit}" 2>/dev/null || true)"
[ -z "$loc" ] || [ "$loc" = "$BASE" ] \
  || fail "la etiqueta local $TAG apunta a ${loc:0:7}, no a $B7 de tests/pantallas/BASE · the local tag $TAG names ${loc:0:7}, not BASE $B7"
TO=(); command -v timeout >/dev/null 2>&1 && TO=(timeout 60)
if out="$(${TO[@]+"${TO[@]}"} git -C "$TOP" ls-remote origin "refs/tags/$TAG" "refs/tags/$TAG^{}" 2>/dev/null)"; then
  rem="$(printf '%s\n' "$out" | awk -v t="refs/tags/$TAG" '$2 == t "^{}" { p = $1 } $2 == t { d = $1 } END { print (p != "" ? p : d) }')"
  if [ -z "$rem" ]; then tag_es="etiqueta no encontrada en origin"; tag_en="tag not found on origin"
  elif [ "$rem" != "$BASE" ]; then
    fail "la etiqueta $TAG de origin apunta a ${rem:0:7}, no a $B7 de tests/pantallas/BASE · origin's tag $TAG names ${rem:0:7}, not BASE $B7"
  else tag_es="etiqueta comprobada en origin"; tag_en="tag checked on origin"; fi
elif [ -n "$loc" ]; then tag_es="etiqueta local comprobada, origin no respondió"; tag_en="local tag checked, origin did not answer"
else tag_es="etiqueta sin comprobar, origin no respondió"; tag_en="tag not checked, origin did not answer"; fi

# the BASE commit's objects (a shallow CI checkout lacks them): fetched by SHA, no ref, no tag, no FETCH_HEAD
if ! g cat-file -e "$BASE^{commit}" 2>/dev/null; then
  { if [ "$(g rev-parse --is-shallow-repository)" = true ]; then g fetch -q --no-tags --no-write-fetch-head --depth=1 origin "$BASE"
    else g fetch -q --no-tags --no-write-fetch-head origin "$BASE"; fi; } \
    && g cat-file -e "$BASE^{commit}" 2>/dev/null \
    || fail "no se pudo leer el commit $B7 de la versión publicada · the published commit $B7 could not be read"
fi

# 2) and 3) BASE, the index and the working tree, side by side
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
g ls-tree -r --full-tree "$BASE" -- "${PATHS[@]}" > "$W/base"                     # mode type sha<TAB>path
g ls-files -s -- "${PATHS[@]}" > "$W/index"                                       # mode sha stage<TAB>path
g ls-files --others --exclude-standard -- "${PATHS[@]}" > "$W/others"              # path
printf '%s\n' "${NEW[@]}" > "$W/allowed"
cut -f2- "$W/base" > "$W/paths"; cut -f2- "$W/index" >> "$W/paths"; cat "$W/others" >> "$W/paths"
: > "$W/state"; : > "$W/tohash"
sort -u "$W/paths" | while IFS= read -r p; do
  if [ -L "$TOP/$p" ]; then printf '%s\tlink\n' "$p" >> "$W/state"
  elif [ -f "$TOP/$p" ]; then printf '%s\n' "$p" >> "$W/tohash"
  else printf '%s\tmissing\n' "$p" >> "$W/state"; fi
done
# a folder of the checked paths replaced by a link would make the working tree read another place
for d in website supabase supabase/migrations .github .github/workflows; do
  if [ -L "$TOP/$d" ]; then printf '%s/\tlink\n' "$d" >> "$W/state"; fi
done
# the bytes as they are on disk (hash-object without -w stores nothing)
if [ -s "$W/tohash" ]; then g hash-object --no-filters --stdin-paths < "$W/tohash" | paste "$W/tohash" - >> "$W/state"; fi

set +e
awk -F'\t' -v counts="$W/counts" '
  FILENAME == ARGV[1] { split($1, m, " "); bmode[$2] = m[1]; bsha[$2] = m[3]; order[++nb] = $2; next }
  FILENAME == ARGV[2] { split($1, m, " "); inidx[$2] = 1; if (m[3] != "0") conflict[$2] = 1; else { imode[$2] = m[1]; isha[$2] = m[2] } next }
  FILENAME == ARGV[3] { other[$1] = 1; next }
  FILENAME == ARGV[4] { st[$1] = $2; next }
  FILENAME == ARGV[5] { ok[$1] = 1; next }
  function bad(p, why) { print p ": " why; nbad++ }
  END {
    for (p in inidx) if (!(p in bsha)) newf[p] = 1
    for (p in other) if (!(p in bsha)) newf[p] = 1
    # a new file with the bytes of a missing one: probably that one renamed
    for (p in newf) for (k = 1; k <= 2; k++) {
      h = (k == 1) ? st[p] : ((p in isha) ? isha[p] : "")
      if (h ~ /^[0-9a-f]+$/ && !((h, p) in seen)) { seen[h, p] = 1; to[h] = to[h] " " p }
    }
    for (i = 1; i <= nb; i++) {
      p = order[i]; s = bsha[p]
      if (p ~ /^website\//) ns++; else if (p ~ /^supabase\/migrations\//) nm++; else np++
      hint = (s in to) ? " (¿renombrado a" to[s] "? · renamed to" to[s] "?)" : ""
      gi = !(p in inidx); gw = (st[p] == "missing")
      if (gi && gw) { bad(p, "borrado o renombrado · deleted or renamed" hint); continue }
      if (gi) bad(p, "quitado del índice · removed from the index" hint)
      else if (p in conflict) bad(p, "en conflicto en el índice · conflicted in the index")
      else if (isha[p] != s) bad(p, "cambiado en el índice · changed in the index")
      else if (imode[p] != bmode[p]) bad(p, "modo cambiado en el índice (" bmode[p] " -> " imode[p] ") · mode changed in the index")
      if (gw) bad(p, "borrado del árbol de trabajo · deleted from the working tree" hint)
      else if (st[p] == "link") bad(p, "convertido en enlace en el árbol de trabajo · turned into a link in the working tree")
      else if (st[p] != s) bad(p, "cambiado en el árbol de trabajo · changed in the working tree")
    }
    for (p in newf) {
      if (!(p in ok)) bad(p, "nuevo y fuera de la lista de las pantallas · new and not on the screens list")
      else if (st[p] == "link") bad(p, "es un enlace · is a link")
      else nn++
    }
    for (p in st) if (st[p] == "link" && p ~ /\/$/) bad(p, "la carpeta es un enlace · the folder is a link")
    printf "%d %d %d %d\n", ns, nm, np, nn > counts
    exit (nbad > 0)
  }' "$W/base" "$W/index" "$W/others" "$W/state" "$W/allowed" | sort > "$W/bad"
rc="${PIPESTATUS[0]}"
set -e
read -r ns nm np nn < "$W/counts" || fail "no se pudo comparar · the comparison did not run"
if [ "$rc" -ne 0 ] || [ -s "$W/bad" ] || [ "$np" -ne 1 ]; then
  [ "$np" -eq 1 ] || echo ".github/workflows/pages.yml: no está en $B7 · not in $B7" >> "$W/bad"
  n="$(wc -l < "$W/bad" | tr -d ' ')"
  echo "  FAIL  no tocar: $n diferencia(s) con la versión publicada $TAG ($B7, tests/pantallas/BASE) · $n difference(s) from the published release:"
  sed 's/^/        /' "$W/bad"
  exit 1
fi
echo "  ok    no tocar: website/ ($ns archivos), supabase/migrations/ ($nm) y pages.yml idénticos byte a byte a la versión publicada $TAG ($B7, $tag_es) en el árbol y en el índice; $nn archivo(s) nuevo(s), todos de la lista de las pantallas · website/ ($ns files), supabase/migrations/ ($nm) and pages.yml byte for byte the published release $TAG ($B7, $tag_en) in the working tree and the index; $nn new file(s), all on the screens list"
