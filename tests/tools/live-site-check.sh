#!/usr/bin/env bash
# Canopy OS · is what GitHub Pages serves an APPROVED release? (read-only)
# GitHub Pages serves the gh-pages branch. Its newest commit must be either
#   * a release published by the manual workflow: "Publish website vYYYY.MM.DD-N", or
#   * the build that was live before the release rules existed (tests/rehearsal/LIVE_PAGES).
# Anything else means something published outside the release process: CI turns red with this message.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
if ! git -C "$ROOT" fetch -q --depth=1 origin gh-pages 2>/dev/null; then echo "  skip  live site check (no connection to GitHub)"; exit 0; fi
SHA="$(git -C "$ROOT" rev-parse FETCH_HEAD)"
MSG="$(git -C "$ROOT" log -1 --format=%s FETCH_HEAD)"
KNOWN="$(grep -E '^[0-9a-f]{40}$' "$ROOT/tests/rehearsal/LIVE_PAGES")"
if [ "$SHA" = "$KNOWN" ]; then
  echo "  ok    live site: the build live before the release rules (${SHA:0:7}); no release published since"
elif [[ "$MSG" =~ ^Publish\ website\ v[0-9]{4}\.[0-9]{2}\.[0-9]{2}-[0-9]+(\ ·\ sitio-[0-9]{4}-[0-9]{2}-[0-9]{2})?$ ]]; then
  echo "  ok    live site: approved release (${MSG#Publish website })"
else
  echo "  FAIL  the live café site (gh-pages ${SHA:0:7}: \"$MSG\") was NOT published by an approved release."
  echo "        Tell the owner. docs/PUBLICAR.md → \"Volver a la versión anterior\" explains how to put a release back."
  exit 1
fi
