#!/usr/bin/env bash
# Canopy OS · «no tocar» (docs/PANTALLAS.md, the owner's condition 2 of 2026-10-31). While the customer screens are
# prototypes, the café's pages (website/: Caja, Cocina, Contabilidad, menú QR, TV actual, …), the database migrations
# and the publishing workflow are byte for byte those of the last published release (tests/prototipos/BASE).
# Compares the working tree, new and deleted files included. Read-only.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
BASE="$(grep -E '^[0-9a-f]{40}$' "$HERE/BASE")"
git -C "$ROOT" cat-file -e "$BASE^{commit}" 2>/dev/null || git -C "$ROOT" fetch -q --depth=1 origin "$BASE"
PATHS=(website supabase/migrations .github/workflows/pages.yml)
changed="$(git -C "$ROOT" diff --name-status "$BASE" -- "${PATHS[@]}")"
added="$(git -C "$ROOT" ls-files --others --exclude-standard -- "${PATHS[@]}" | sed 's/^/A\t/')"
if [ -n "$changed$added" ]; then
  echo "  FAIL  no tocar: these files differ from the published release ${BASE:0:7} (tests/prototipos/BASE):"
  printf '%s\n%s\n' "$changed" "$added" | sed '/^$/d; s/^/        /'
  exit 1
fi
n_site="$(git -C "$ROOT" ls-tree -r --name-only "$BASE" -- website | wc -l | tr -d ' ')"
n_mig="$(git -C "$ROOT" ls-tree -r --name-only "$BASE" -- supabase/migrations | wc -l | tr -d ' ')"
echo "  ok    no tocar: website/ ($n_site files), supabase/migrations/ ($n_mig) and pages.yml equal the published release ${BASE:0:7}"
