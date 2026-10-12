#!/usr/bin/env bash
# Canopy OS · run every automated test: SQL tests, backup pipeline, migration rehearsal, browser (end-to-end) tests.
# Usage: tests/run.sh [lint|sql|backup|rehearsal|e2e]   (no argument = everything)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
what="${1:-all}"
status=0
if [ "$what" = "all" ] || [ "$what" = "lint" ]; then echo "Lint";     bash "$HERE/lint.sh" || status=1; fi
if [ "$what" = "all" ] || [ "$what" = "sql" ]; then echo "SQL tests"; bash "$HERE/run-sql.sh" || status=1; fi
if [ "$what" = "all" ] || [ "$what" = "backup" ]; then echo "Backups"; bash "$HERE/backup/test-backup-pipeline.sh" || status=1; fi
if [ "$what" = "all" ] || [ "$what" = "rehearsal" ]; then
  echo "Migration rehearsal (production as it is today -> every migration -> the live pages)"
  bash "$HERE/rehearsal/run.sh" || status=1
  if [ "$status" -eq 0 ] && [ -f "$HERE/e2e/run.js" ]; then bash "$HERE/rehearsal/live-pages.sh" || status=1; fi
fi
if [ "$what" = "all" ] || [ "$what" = "e2e" ]; then
  if [ -f "$HERE/e2e/run.js" ]; then echo "Browser tests"; node "$HERE/e2e/run.js" || status=1; fi
fi
[ "$status" -eq 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit "$status"
