#!/usr/bin/env bash
# Canopy OS rehearsal · the pages live on the café's site today, in a real browser, against the migrated copy
# built by tests/rehearsal/run.sh (database canopy_rehearsal, or REHEARSAL_DB: reset-pages.sh runs this against the
# reset copy). Their production address and public key are swapped for the local test stand-in, so nothing here can
# reach the real Supabase (the browser also blocks *.supabase.co). The stand-in answers on the site port + 1000
# (tests/e2e/gateway.js): E2E_SITE_PORT / E2E_PGRST_PORT / E2E_SUFFIX pick other ports and database names.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
# LIVE_PAGES_SHA: another published build (e.g. the latest gh-pages commit) instead of the one named in LIVE_PAGES
SHA="${LIVE_PAGES_SHA:-$(grep -E '^[0-9a-f]{40}$' "$HERE/LIVE_PAGES")}"
git -C "$ROOT" cat-file -e "$SHA^{commit}" 2>/dev/null || git -C "$ROOT" fetch -q --depth=1 origin "$SHA"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/site"; git -C "$ROOT" archive "$SHA" | tar -x -C "$T/site"
PROD_URL="$(node -e "const s=require('fs').readFileSync('$ROOT/website/config.js','utf8');console.log(s.match(/production: \{ url: '([^']+)'/)[1])")"
PROD_KEY="$(node -e "const s=require('fs').readFileSync('$ROOT/website/config.js','utf8');console.log(s.match(/production: \{ url: '[^']+',\s*key: '([^']+)'/)[1])")"
TEST_KEY="$(node -e "const s=require('fs').readFileSync('$ROOT/website/config.js','utf8');console.log(s.match(/local: \{[^}]*key: '([^']+)'/)[1])")"
API_URL="http://127.0.0.1:$(( ${E2E_SITE_PORT:-8090} + 1000 ))"
grep -rl "$PROD_URL" "$T/site" | xargs sed -i "s#$PROD_URL#$API_URL#g; s#$PROD_KEY#$TEST_KEY#g"
if grep -rq "supabase\.co" "$T/site" --include='*.html' --include='*.js'; then echo "  FAIL  a live page still points at Supabase"; exit 1; fi
E2E_TEMPLATE_DB="${REHEARSAL_DB:-canopy_rehearsal}" E2E_SITE_ROOT="$T/site" E2E_SPECS_DIR="$HERE/live-pages" node "$ROOT/tests/e2e/run.js"
