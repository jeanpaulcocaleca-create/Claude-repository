#!/usr/bin/env bash
# Canopy OS · the private prototypes (prototipos/): pages no release publishes (pages.yml publishes website/ only).
#   1) «no tocar»: website/, the migrations and pages.yml equal the last published release (no-tocar.sh);
#   2) the prototypes' browser tests: each prototype is served next to a copy of website/ (so it loads the site's own
#      config.js, lang.js and version.js) against the throw-away test database, on ports of its own.
# Usage: tests/prototipos/run.sh [spec filter]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
bash "$HERE/no-tocar.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cp -R "$ROOT/website/." "$T/"
for f in "$ROOT"/prototipos/*/*.html; do
  n="$(basename "$f")"
  if [ -e "$T/$n" ]; then echo "  FAIL  prototipos: $n has the name of a page of the site"; exit 1; fi
  cp "$f" "$T/$n"
done
E2E_SITE_ROOT="$T" E2E_SPECS_DIR="$HERE/specs" E2E_SUFFIX="${E2E_SUFFIX:-_proto}" \
  E2E_SITE_PORT="${E2E_SITE_PORT:-8290}" E2E_PGRST_PORT="${E2E_PGRST_PORT:-3290}" node "$ROOT/tests/e2e/run.js" "${1:-}"
