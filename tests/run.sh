#!/usr/bin/env bash
# Canopy OS · run every automated test: SQL tests, backup pipeline, migration rehearsal, browser (end-to-end) tests,
# and the «no tocar» check of the customer screens.
# Usage: tests/run.sh [lint|sql|backup|rehearsal|e2e|pantallas]   (no argument = everything)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
what="${1:-all}"
status=0
if [ "$what" = "all" ] || [ "$what" = "lint" ]; then echo "Lint";     bash "$HERE/lint.sh" || status=1; fi
if [ "$what" = "all" ] || [ "$what" = "sql" ]; then echo "SQL tests"; bash "$HERE/run-sql.sh" || status=1; fi
if [ "$what" = "all" ] || [ "$what" = "backup" ]; then echo "Backups"; bash "$HERE/backup/test-backup-pipeline.sh" || status=1; fi
if [ "$what" = "all" ] || [ "$what" = "rehearsal" ]; then
  echo "Migration rehearsal (production as it is today -> every migration -> the live pages; the one-time reset -> the pages on the empty café)"
  bash "$HERE/rehearsal/run.sh" || status=1
  if [ "$status" -eq 0 ] && [ -f "$HERE/e2e/run.js" ]; then bash "$HERE/rehearsal/live-pages.sh" || status=1; fi
  if [ "$status" -eq 0 ] && [ -f "$HERE/e2e/run.js" ]; then bash "$HERE/rehearsal/reset-pages.sh" || status=1; fi
fi
if [ "$what" = "all" ] || [ "$what" = "e2e" ]; then
  if [ -f "$HERE/e2e/run.js" ]; then echo "Browser tests"; node "$HERE/e2e/run.js" || status=1; fi
fi
if [ "$what" = "all" ] || [ "$what" = "pantallas" ]; then
  # the customer screens only add their own files: the café's pages, migrations and pages.yml equal the published
  # release (the screens' browser tests are in e2e/specs and run with the browser tests)
  echo "No tocar (website/, migrations and pages.yml equal the published release; only the screens' new files are added)"
  bash "$HERE/pantallas/no-tocar.sh" || status=1
fi
[ "$status" -eq 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit "$status"
