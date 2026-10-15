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
grep -qE '^\s+environment: production' .github/workflows/pages.yml || bad "pages.yml must run in the production environment"
grep -qF 'v[0-9]{4}' .github/workflows/pages.yml || bad "pages.yml must refuse anything that is not a release tag"
grep -qE '^\s+(pull_request|schedule|workflow_run|repository_dispatch|release|create):' .github/workflows/pages.yml && bad "pages.yml may only be started by hand"
# only pages.yml may write the branch the live site is served from; every other workflow reads only
for w in .github/workflows/*.yml; do
  [ "$w" = .github/workflows/pages.yml ] && continue
  grep -qE 'gh-pages|deploy-pages|contents: write|pages: write' "$w" && bad "$w must not be able to publish the live site"
done
# the backup repository's upload action is the one CI runs (so its pinned version is known to work)
a1="$(grep -ho 'actions/upload-artifact@[0-9a-f]*' .github/workflows/ci.yml | head -1)"
a2="$(grep -ho 'actions/upload-artifact@[0-9a-f]*' ops/backup/repositorio-respaldos/.github/workflows/respaldo.yml | head -1)"
[ -n "$a1" ] && [ "$a1" = "$a2" ] || bad "respaldo.yml and ci.yml must pin the same upload-artifact version"
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
# 6) what the owner pastes in the SQL Editor (and the staging rehearsal sends with psql -c) is plain SQL: no psql commands
for f in supabase/migrations/*.sql supabase/tools/*.sql; do
  grep -qE '^\s*\\' "$f" && bad "$f contains a psql command (the SQL Editor cannot run it)"
done
# 7) which database each address uses; staging can never be pointed at production
node "$(dirname "$0")/tools/config-check.js" || bad "website/config.js environments"
# the Spanish dictionary never gives one English text two translations
node "$(dirname "$0")/tools/lang-check.js" || bad "website/lang.js has conflicting translations"
# 8) Storage tables are not ours. On Supabase the SQL Editor account (postgres) does not own storage.objects or
#    storage.buckets: supautils (policy_grants) only lets it create and drop POLICIES on them, and storage-api's grants
#    let it read and write their rows. Other DDL there (alter table, create trigger or index, grant, drop) fails in
#    production, while the local rehearsal, which makes the editor a member of the Storage owner
#    (tests/rehearsal/as-supabase.sql), would not notice. So a migration line that mentions storage. must be a
#    one-line "insert into storage.buckets ... on conflict ...", "drop policy if exists ... on storage.objects;",
#    "create policy ... on storage.objects ...", a comment, or read Storage inside a rule or function
#    (storage.foldername/filename/extension(...), from/join storage.objects|buckets); direct deletes are refused too
#    (Storage's own trigger stops them).
storage_ddl() {  # files... -> prints the offending lines, fails if any
  awk '
    { t = " " tolower($0) " "; sub(/--.*/, " ", t); gsub(/"storage"\./, "storage.", t) }
    t !~ /[^a-z0-9_]storage\./ { next }
    t ~ /^ [ \t]*insert into storage\.buckets[ (][^;]* on conflict [^;]*;?[ \t]*$/ { next }
    t ~ /^ [ \t]*drop policy if exists [^;]* on storage\.objects[ \t]*;[ \t]*$/ { next }
    t ~ /^ [ \t]*create policy [^;]* on storage\.objects [^;]*;?[ \t]*$/ { next }
    {
      if (t !~ /delete[ \t]+from[ \t]+storage\./) {
        gsub(/[^a-z0-9_]storage\.(foldername|filename|extension)[ \t]*\(/, " (", t)
        gsub(/[^a-z0-9_](from|join)[ \t]+storage\.(objects|buckets)[^a-z0-9_.]/, " ", t)
      }
      if (t ~ /[^a-z0-9_]storage\./) { print FILENAME ":" FNR ": " $0; bad = 1 }
    }
    END { exit bad }' "$@"
}
if ! out="$(storage_ddl supabase/migrations/*.sql)"; then
  bad "a migration changes the Storage tables beyond what production allows (only policies on storage.objects and a bucket insert):"
  echo "$out" | sed 's/^/        /'
fi
# 9) every restore keeps only postgres's own default rights: Supabase's supabase_admin ones are in a dump of public,
#    and neither the throw-away test server nor postgres on Supabase can restore them (D-029)
for f in ops/backup/*.sh ops/backup/repositorio-respaldos/*.sh; do
  grep -n 'pg_restore -l' "$f" | grep -v "DEFAULT ACL" | sed "s#^#$f:#" | while read -r l; do echo "$l"; done
done > /tmp/canopy-lint-toc.$$
if [ -s /tmp/canopy-lint-toc.$$ ]; then
  bad "a restore keeps every default right from the dump (filter ' DEFAULT ACL ' entries not owned by postgres):"
  sed 's/^/        /' /tmp/canopy-lint-toc.$$
fi
rm -f /tmp/canopy-lint-toc.$$
# 10) the backup account reads the café's tables, never the logins (D-033): nothing hands it (or anyone)
#     pg_read_all_data, which reads auth (sessions, tokens) and the database's passwords, and no backup copies auth
#     Whole statements, not lines: comments removed, lines joined, quotes dropped, any case (a grant split over two
#     lines, a role list, "pg_read_all_data", execute format('grant %I ...', 'pg_read_all_data'); pg_dump or copy of
#     auth on a continued line, -nauth, --table=auth.users, auth in the schema list)
prad=""; for f in supabase/migrations/*.sql supabase/tools/*.sql; do
  awk '{ sub(/--.*/, ""); printf "%s ", tolower($0) }' "$f" | tr -d '"' \
    | grep -qE "(^|[^a-z_])grant[[:space:]][^;]*(pg_read_all_data[^;]*[[:space:]]to[[:space:]]|[[:space:]]to[[:space:]][^;]*pg_read_all_data)|(^|[^a-z_])create[[:space:]]+(role|user|group)[[:space:]][^;]*[[:space:]]in[[:space:]]+(role|group)[[:space:]][^;]*pg_read_all_data|(^|[^a-z_])alter[[:space:]]+group[[:space:]]+pg_read_all_data[[:space:]]+add[[:space:]]+user" && prad="$prad $f"
done
[ -n "$prad" ] && bad "pg_read_all_data is granted (it reads the logins; give SELECT on the café's tables instead):$prad"
adump=""; for f in ops/backup/*.sh ops/backup/repositorio-respaldos/*.sh; do
  sed -e 's/^[[:space:]]*#.*//' "$f" | sed -e ':a' -e '/\\$/N; s/\\\n/ /; ta' \
    | grep -qiE "(pg_dump|copy)[^|;&]*([^a-z_]auth\.|schema[= ]+['\"]?auth([^a-z_]|$)|-n *['\"]?auth([^a-z_]|$))|nspname in \([^)]*'auth'" && adump="$adump $f"
done
[ -n "$adump" ] && bad "a backup script copies the logins (auth); they are created again by hand (docs/RESPALDOS.md):$adump"
# 11) the rights fingerprint is computed the same way by the nightly backup, restore.sh and the staging copy (a
#     sort that depends on the server's language once made a restore fail): the three PRIV_SQL blocks are identical
priv_sql() { awk '/^PRIV_SQL="/ { f = 1 } f { print } f && /q"$/ { exit }' "$1" | md5sum; }
[ "$(priv_sql ops/backup/backup.sh)" = "$(priv_sql ops/backup/restore.sh)" ] \
  && [ "$(priv_sql ops/backup/backup.sh)" = "$(priv_sql ops/backup/repositorio-respaldos/ensayo.sh)" ] \
  && grep -q 'order by x collate \\"C\\"' ops/backup/backup.sh \
  || bad "PRIV_SQL differs between backup.sh, restore.sh and repositorio-respaldos/ensayo.sh, or does not sort with collate \"C\""
# 12) GitHub Actions workflows: every ${{ … }} uses only the contexts GitHub allows at that place. GitHub checks this
#     only when the file is pushed to a .github/workflows folder, which the private backup repository's files never
#     are from here (2026-10-13: a job-level env with runner.temp was rejected when the owner uploaded it)
python3 "$(dirname "$0")/tools/workflow-contexts.py" .github/workflows/*.yml ops/backup/repositorio-respaldos/.github/workflows/*.yml \
  || bad "a workflow uses a context where GitHub does not allow it (see above)"
# 13) scripts from the internet: only these libraries, pinned to one version, from these CDNs (the pages keep working
#     when one does not load: supabase-js is required, the invoice readers are loaded only on demand and degrade to typing)
ALLOWED_SCRIPTS='^https://(cdn\.jsdelivr\.net/npm/@supabase/supabase-js@2\.49\.1/dist/umd/supabase\.min\.js|cdnjs\.cloudflare\.com/ajax/libs/qrcode-generator/1\.4\.4/qrcode\.min\.js|cdn\.jsdelivr\.net/npm/pdfjs-dist@3\.11\.174/build/pdf(\.worker)?\.min\.js|cdn\.jsdelivr\.net/npm/tesseract\.js@5\.1\.1/dist/tesseract\.min\.js)$'
for u in $(grep -hoE "https://(cdn\.jsdelivr\.net|cdnjs\.cloudflare\.com|unpkg\.com)/[^\"' <>]+" website/*.html website/*.js | sort -u); do
  echo "$u" | grep -Eq "$ALLOWED_SCRIPTS" || bad "a script from the internet is not in the pinned allowlist (tests/lint.sh 13): $u"
done
[ "$fail" -eq 0 ] && echo "  ok    lint"
exit "$fail"
