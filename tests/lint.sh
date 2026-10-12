#!/usr/bin/env bash
# Canopy OS · static checks that keep secrets out of this PUBLIC repository and keep the release rules intact.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
fail=0
bad() { echo "  FAIL  $*"; fail=1; }
# 1) no service-role keys, private keys, connection strings with passwords or age secret keys anywhere
if git grep -nIE 'service_role"?\s*[:=]\s*"?eyJ|AGE-SECRET-KEY-1|-----BEGIN [A-Z ]*PRIVATE KEY|postgres(ql)?://[^ :@/]+:[^ @/]{6,}@[^ ]*supabase' -- ':!tests/lint.sh' >/dev/null; then
  bad "possible secret committed:"; git grep -nIE 'service_role"?\s*[:=]\s*"?eyJ|AGE-SECRET-KEY-1|-----BEGIN [A-Z ]*PRIVATE KEY|postgres(ql)?://[^ :@/]+:[^ @/]{6,}@[^ ]*supabase' -- ':!tests/lint.sh' | head
fi
# 2) the production workflow can only be started by hand
grep -qE '^\s+push:' .github/workflows/pages.yml && bad "pages.yml must not publish on push"
grep -q 'PUBLICAR' .github/workflows/pages.yml || bad "pages.yml lost its PUBLICAR confirmation"
# 3) every migration is numbered, registers itself, and its number matches its file name
for m in supabase/migrations/*.sql; do
  n="$(basename "$m" | grep -Eo '^[0-9]{4}' | sed 's/^0*//')"; n="${n:-0}"
  grep -q "migration_begin($n," "$m" || bad "$(basename "$m") must call canopy.migration_begin($n, ...)"
  grep -q "migration_end($n," "$m" || bad "$(basename "$m") must call canopy.migration_end($n, ...)"
done
# 4) the historical scripts keep their guard
while read -r f; do f="${f%%#*}"; f="$(echo "$f" | xargs)"; [ -z "$f" ] && continue
  head -8 "supabase/$f" | grep -q 'ARCHIVO HISTÓRICO' || bad "supabase/$f lost its 'do not run' guard"
done < tests/db/legacy-order.txt
# 5) the private backup repository copies match the reviewed scripts
for f in backup.sh restore-stub.sql; do cmp -s "ops/backup/$f" "ops/backup/repositorio-respaldos/$f" || bad "ops/backup/repositorio-respaldos/$f is out of date"; done
[ "$fail" -eq 0 ] && echo "  ok    lint"
exit "$fail"
