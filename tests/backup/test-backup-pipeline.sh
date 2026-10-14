#!/usr/bin/env bash
# Canopy OS · end-to-end test of the backup system on local test databases:
#   build a "production" copy → nightly backup (dump, restore test, age encryption, upload) → restore into an
#   empty database with the OFFLINE recovery key → compare every table → owner-computer sync and verification.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/tests/pg.sh"
command -v age >/dev/null || { echo "  skip  backup pipeline (age not installed)"; exit 0; }
T="$(mktemp -d)"
# check 6i's cases below store key-like settings on canopy_legacysim; 6i reads every database's settings, so a run that
# stops early must not leave them behind (every later paste on this server would stop on them)
reset_6i() { psql -X -q -d postgres -c "alter database canopy_legacysim reset app.settings.jwt_secret" \
               -c "alter database canopy_legacysim reset pgtle.enable_password_check" >/dev/null 2>&1 || true; }
trap 'reset_6i; rm -rf "$T"' EXIT
URL_BASE="postgresql://postgres@${PGHOST}:${PGPORT}"
[ -n "${PGPASSWORD:-}" ] && URL_BASE="postgresql://postgres:${PGPASSWORD}@${PGHOST}:${PGPORT}"

age-keygen -o "$T/owner.key" 2>/dev/null; age-keygen -o "$T/recovery.key" 2>/dev/null
RECIPIENTS="$(age-keygen -y "$T/owner.key") $(age-keygen -y "$T/recovery.key")"

# 0) production as it is today, before migration 0000: the account from supabase/tools/backup-account.sql,
#    menu photos served the way Supabase's public Storage serves them; every table and every file is checked
CANOPY_LEGACY_ONLY=1 "$ROOT/tests/build-db.sh" canopy_legacysim >/dev/null
# the paste checks itself before it keeps anything: an owner-rights function any login may run (a way around every
# rule with a faked app login) stops it, and it creates and changes nothing (D-033)
ACL_SQL="select count(*) from pg_shdepend where refclassid = 'pg_authid'::regclass and refobjid = coalesce(to_regrole('canopy_backup')::oid, 0)
           and dbid in (0, (select oid from pg_database where datname = current_database()))"
# who may run each function of public (the paste takes PUBLIC's right to run the café's owner-rights trigger functions)
FN_SQL="select md5(string_agg(p.oid::regprocedure::text || ' ' || coalesce(p.proacl::text, '-'), ',' order by p.oid)) from pg_proc p
          where p.pronamespace = 'public'::regnamespace"
psql -X -q -d canopy_legacysim -v ON_ERROR_STOP=1 -c "create function public.canopy_test_evil() returns void language sql security definer as 'select 1'"
# an owner-rights trigger function given to the account by name: it could attach it to a temporary table of its own,
# and EXECUTE is not checked again when the trigger fires
psql -X -q -d canopy_legacysim -v ON_ERROR_STOP=1 \
  -c "create function public.canopy_test_evil_trg() returns trigger language plpgsql security definer as 'begin return new; end'" \
  -c "grant execute on function public.canopy_test_evil_trg() to canopy_backup"
acl_before="$(psql -X -At -d canopy_legacysim -c "$ACL_SQL")"; fn_before="$(psql -X -At -d canopy_legacysim -c "$FN_SQL")"
if psql -X -q -d canopy_legacysim -v ON_ERROR_STOP=1 -f "$ROOT/supabase/tools/backup-account.sql" > "$T/account-refused.log" 2>&1; then
  cat "$T/account-refused.log"; echo "  FAIL  the backup account paste accepted an owner-rights function any login can run"; exit 1; fi
grep -q 'NO SE CREÓ NI SE CAMBIÓ NADA' "$T/account-refused.log" && grep -qF 'canopy_test_evil()' "$T/account-refused.log" \
  && grep -qF 'canopy_test_evil_trg()' "$T/account-refused.log" \
  || { cat "$T/account-refused.log"; echo "  FAIL  the refused paste does not say why (owner-rights function, or trigger function given by name)"; exit 1; }
[ "$(psql -X -At -d canopy_legacysim -c "$FN_SQL")" = "$fn_before" ] \
  || { echo "  FAIL  the refused paste changed who may run a function"; exit 1; }
# run statement by statement (no stop on error), its result row must not say "lista" either
psql -X -q -At -d canopy_legacysim -f "$ROOT/supabase/tools/backup-account.sql" > "$T/account-refused2.log" 2>&1 || true
grep -q '^REVISAR: la revisión de arriba no terminó bien' "$T/account-refused2.log" && ! grep -q '^lista' "$T/account-refused2.log" \
  || { cat "$T/account-refused2.log"; echo "  FAIL  a refused paste still reported the account ready"; exit 1; }
[ "$(psql -X -At -d canopy_legacysim -c "$ACL_SQL")" = "$acl_before" ] \
  || { echo "  FAIL  the refused paste left permissions for the backup account"; exit 1; }
psql -X -q -d canopy_legacysim -v ON_ERROR_STOP=1 -c "drop function public.canopy_test_evil(), public.canopy_test_evil_trg()"
# check 6i: a key kept in a setting every login can read stops the paste and is named, never shown; a setting the server
# does not know is text, so it is always judged; an empty one holds nothing
acl_before="$(psql -X -At -d canopy_legacysim -c "$ACL_SQL")"; fn_before="$(psql -X -At -d canopy_legacysim -c "$FN_SQL")"
psql -X -q -d postgres -v ON_ERROR_STOP=1 -c "alter database canopy_legacysim set app.settings.jwt_secret = 'test-only-not-a-key'"
if psql -X -q -d canopy_legacysim -v ON_ERROR_STOP=1 -f "$ROOT/supabase/tools/backup-account.sql" > "$T/account-key.log" 2>&1; then
  cat "$T/account-key.log"; echo "  FAIL  the backup account paste accepted a key-like setting every login can read"; exit 1; fi
grep -q 'NO SE CREÓ NI SE CAMBIÓ NADA' "$T/account-key.log" && grep -qF 'parece una clave: app.settings.jwt_secret' "$T/account-key.log" \
  && ! grep -qF 'test-only-not-a-key' "$T/account-key.log" \
  || { cat "$T/account-key.log"; echo "  FAIL  the refused paste does not name the key-like setting, or shows its value"; exit 1; }
[ "$(psql -X -At -d canopy_legacysim -c "$ACL_SQL")" = "$acl_before" ] && [ "$(psql -X -At -d canopy_legacysim -c "$FN_SQL")" = "$fn_before" ] \
  || { echo "  FAIL  the paste refused for a key-like setting changed permissions"; exit 1; }
psql -X -q -d postgres -v ON_ERROR_STOP=1 -c "alter database canopy_legacysim set app.settings.jwt_secret = ''"
psql -X -q -d canopy_legacysim -v ON_ERROR_STOP=1 -f "$ROOT/supabase/tools/backup-account.sql" > "$T/account-key-empty.log" 2>&1 \
  && grep -q '^ *lista: la cuenta canopy_backup' "$T/account-key-empty.log" \
  || { cat "$T/account-key-empty.log"; echo "  FAIL  an empty key-like setting stopped the paste"; exit 1; }
psql -X -q -d postgres -v ON_ERROR_STOP=1 -c "alter database canopy_legacysim reset app.settings.jwt_secret"
# ...but a switch, a number or a choice from a list cannot hold a key, whatever its name. On Supabase pg_tle defines
# pgtle.enable_password_check (on/off/require): the owner's first paste stopped on it (2026-10-13). pg_tle is not
# installed here, so a copy of the paste reads a stand-in for pg_catalog.pg_settings with that setting as pg_tle defines
# it; only check 6i's two "pg_catalog.pg_settings ps" are swapped, and a text setting with a value still stops the copy
[ "$(grep -c 'pg_catalog\.pg_settings ps' "$ROOT/supabase/tools/backup-account.sql")" = "2" ] \
  || { echo "  FAIL  check 6i no longer reads pg_catalog.pg_settings in exactly two places (update this test)"; exit 1; }
sed 's/pg_catalog\.pg_settings ps/canopy_test_guc.pg_settings ps/g' "$ROOT/supabase/tools/backup-account.sql" > "$T/account-guc.sql"
psql -X -q -d canopy_legacysim -v ON_ERROR_STOP=1 -c "create schema canopy_test_guc" -c "create view canopy_test_guc.pg_settings as
  select name, vartype, setting, enumvals from pg_catalog.pg_settings where name <> 'pgtle.enable_password_check'
  union all select 'pgtle.enable_password_check', 'enum', 'on', '{on,off,require}'::text[]"
psql -X -q -d postgres -v ON_ERROR_STOP=1 -c "alter database canopy_legacysim set pgtle.enable_password_check = 'on'"
psql -X -q -d canopy_legacysim -v ON_ERROR_STOP=1 -f "$T/account-guc.sql" > "$T/account-guc.log" 2>&1 \
  && grep -q '^ *lista: la cuenta canopy_backup' "$T/account-guc.log" \
  || { cat "$T/account-guc.log"; echo "  FAIL  pg_tle's on/off setting pgtle.enable_password_check stopped the paste"; exit 1; }
# a database-level value under that name that is not one of its choices could only be text a superuser stored while
# pg_tle was not loaded: it is judged, named, and its value never shown
psql -X -q -d postgres -v ON_ERROR_STOP=1 -c "alter database canopy_legacysim set pgtle.enable_password_check = 'test-only-not-a-choice'"
if psql -X -q -d canopy_legacysim -v ON_ERROR_STOP=1 -f "$T/account-guc.sql" > "$T/account-guc1.log" 2>&1 \
   || ! grep -qF 'parece una clave: pgtle.enable_password_check' "$T/account-guc1.log" || grep -qF 'test-only-not-a-choice' "$T/account-guc1.log"; then
  cat "$T/account-guc1.log"; echo "  FAIL  a stored value that is not one of the setting's choices did not stop the paste, or was shown"; exit 1; fi
psql -X -q -d postgres -v ON_ERROR_STOP=1 -c "alter database canopy_legacysim set pgtle.enable_password_check = 'on'"
# without pg_tle the same name is text the server does not know: the shipped paste judges it and stops
if psql -X -q -d canopy_legacysim -v ON_ERROR_STOP=1 -f "$ROOT/supabase/tools/backup-account.sql" > "$T/account-guc2.log" 2>&1 \
   || ! grep -qF 'parece una clave: pgtle.enable_password_check' "$T/account-guc2.log"; then
  cat "$T/account-guc2.log"; echo "  FAIL  a setting nothing defines (text) named like a key did not stop the paste"; exit 1; fi
psql -X -q -d postgres -v ON_ERROR_STOP=1 -c "alter database canopy_legacysim reset pgtle.enable_password_check"
psql -X -q -d canopy_legacysim -v ON_ERROR_STOP=1 -c "create or replace view canopy_test_guc.pg_settings as
  select name, vartype, setting, enumvals from pg_catalog.pg_settings
  union all select 'pgtle.enable_password_check', 'enum', 'on', '{on,off,require}'::text[]
  union all select 'pgtle.example_token', 'string', 'not-empty', null"
if psql -X -q -d canopy_legacysim -v ON_ERROR_STOP=1 -f "$T/account-guc.sql" > "$T/account-guc3.log" 2>&1 \
   || ! grep -qF 'el servidor tiene, a la vista de toda cuenta, un ajuste que parece una clave: pgtle.example_token' "$T/account-guc3.log" \
   || grep -qF 'pgtle.enable_password_check' "$T/account-guc3.log"; then
  cat "$T/account-guc3.log"; echo "  FAIL  check 6i: a key-like text setting with a value must stop the paste, the on/off one must not"; exit 1; fi
psql -X -q -d canopy_legacysim -v ON_ERROR_STOP=1 -c "drop schema canopy_test_guc cascade"
psql -X -q -d canopy_legacysim -v ON_ERROR_STOP=1 -f "$ROOT/supabase/tools/backup-account.sql" > "$T/account.log"
grep -q 'lista: la cuenta canopy_backup' "$T/account.log" || { cat "$T/account.log"; echo "  FAIL  backup account (before 0000)"; exit 1; }
# it reads the café's tables and the photo list, never the logins
[ "$(psql -X -At -d canopy_legacysim -c "select has_table_privilege('canopy_backup', 'public.orders', 'select') and has_table_privilege('canopy_backup', 'storage.objects', 'select')
       and not has_table_privilege('canopy_backup', 'auth.users', 'select') and not pg_has_role('canopy_backup', 'pg_read_all_data', 'member')")" = "t" ] \
  || { echo "  FAIL  the backup account does not read exactly the café's tables and the photo list"; exit 1; }
# ...and can no longer attach the café's owner-rights trigger functions (today 3 run by every login) to a table of its own
[ "$(psql -X -At -d canopy_legacysim -c "select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosecdef
       and p.prorettype = 'trigger'::regtype and has_function_privilege('canopy_backup', p.oid, 'execute')")" = "0" ] \
  && [ "$(psql -X -At -d canopy_legacysim -c "select has_function_privilege('authenticated', 'public._order_tab_voided()', 'execute')")" = "t" ] \
  || { echo "  FAIL  the paste left the café's trigger functions to every login, or took a right from another account"; exit 1; }
# the password tool (supabase/tools/backup-password.sql, RESPALDOS 3.4), sent as ONE query string the way Supabase's
# SQL Editor sends a paste (psql -c: one implicit transaction, the result is the last statement's row). It may change
# only LOGIN and the password of canopy_backup, and the password may reach nothing but the result row
PW_SQL="$(cat "$ROOT/supabase/tools/backup-password.sql")"
HEX64='^[0-9a-f]{64}$'
AUTHID_SQL="select rolcanlogin || ' ' || md5(coalesce(rolpassword, '')) from pg_authid where rolname = 'canopy_backup'"
ATTRS_SQL="select rolsuper, rolinherit, rolcreaterole, rolcreatedb, rolreplication, rolbypassrls, rolconnlimit, rolvaliduntil,
             (select count(*) from pg_auth_members where member = a.oid) from pg_authid a where rolname = 'canopy_backup'"
# the placeholder setting of case (a) and the scratch editor of case (d) must not outlive a run that stops early
reset_pw() { psql -X -q -d postgres -c "alter database canopy_legacysim reset pgaudit.log" -c "alter database canopy_legacysim reset log_lock_waits" \
               -c "alter database canopy_legacysim reset deadlock_timeout" -c "drop role if exists canopy_test_editor" \
               -c "drop role if exists canopy_test_ident" >/dev/null 2>&1 || true
             # case (a2)'s stand-in for pg_tle, dropped only when it is the test's own (its comment says so)
             psql -X -q -d canopy_legacysim -c "do \$\$ begin if obj_description(to_regnamespace('pgtle'), 'pg_namespace') = 'canopy test stand-in'
               then drop schema pgtle cascade; end if; end \$\$" >/dev/null 2>&1 || true; }
trap 'reset_6i; reset_pw; rm -rf "$T"' EXIT
login_as_backup() { PGPASSWORD="$1" psql -X -At -h "$PGHOST" -p "$PGPORT" -U canopy_backup -d canopy_legacysim -c 'select 1' 2>/dev/null; }
scram_ok() {  # verifier password -> true when the stored SCRAM-SHA-256 verifier is this password's (RFC 7677)
  python3 -I - "$1" "$2" <<'PY'
import base64, hashlib, hmac, sys
v, pw = sys.argv[1], sys.argv[2]
sys.exit(1) if not v.startswith('SCRAM-SHA-256$') else None
params, keys = v[len('SCRAM-SHA-256$'):].split('$')
iters, salt = params.split(':'); stored, server = keys.split(':')
salted = hashlib.pbkdf2_hmac('sha256', pw.encode(), base64.b64decode(salt), int(iters))
ok = hashlib.sha256(hmac.new(salted, b'Client Key', hashlib.sha256).digest()).digest() == base64.b64decode(stored) \
     and hmac.new(salted, b'Server Key', hashlib.sha256).digest() == base64.b64decode(server)
sys.exit(0 if ok else 1)
PY
}
verifier() { psql -X -At -d canopy_legacysim -c "select rolpassword from pg_authid where rolname = 'canopy_backup'"; }
# a local test server's log is readable: no run below may write a 64-hex string into it (CI's server has none)
SERVER_LOG="${CANOPY_PG_DIR:-/tmp/canopy-test-pg}/server.log"
[ -r "$SERVER_LOG" ] && log_mark="$(wc -l < "$SERVER_LOG")" || log_mark=""
# a) a setting that would record the nested statement (pgaudit.log = role; pgaudit is not loaded here, so a
#    database-level placeholder stands in for it) stops the tool, and the account's login and password stay as they are
psql -X -q -d postgres -v ON_ERROR_STOP=1 -c "alter database canopy_legacysim set pgaudit.log = 'role'"
authid_before="$(psql -X -At -d canopy_legacysim -c "$AUTHID_SQL")"
if psql -X -q -At -d canopy_legacysim -c "$PW_SQL" > "$T/password-refused.log" 2>&1; then
  cat "$T/password-refused.log"; echo "  FAIL  the password tool ran while the database would record the password (pgaudit.log = role)"; exit 1; fi
grep -q 'NO SE CAMBIÓ NADA' "$T/password-refused.log" && grep -q 'pgaudit.log = role' "$T/password-refused.log" && ! grep -qE '[0-9a-f]{64}' "$T/password-refused.log" \
  || { cat "$T/password-refused.log"; echo "  FAIL  the refused password tool does not say why (or shows a value)"; exit 1; }
[ "$(psql -X -At -d canopy_legacysim -c "$AUTHID_SQL")" = "$authid_before" ] \
  || { echo "  FAIL  the refused password tool changed the account's login or password"; exit 1; }
psql -X -q -d postgres -v ON_ERROR_STOP=1 -c "alter database canopy_legacysim reset pgaudit.log"
# a2) a password checker (pg_tle "passcheck") would receive the new password. pg_tle is not installed here: a
#     database-level placeholder stands in for its switch and a table for its list of registered functions. The tool
#     refuses and says why, the account's login and password stay as they are, and the check tool predicts the refusal
[ "$(psql -X -At -d canopy_legacysim -c "select to_regnamespace('pgtle') is null")" = "t" ] \
  || { echo "  FAIL  the test database has a pgtle schema (pg_tle installed?): update case (a2)"; exit 1; }
psql -X -q -d postgres -v ON_ERROR_STOP=1 -c "alter database canopy_legacysim set pgtle.enable_password_check = 'on'"
psql -X -q -d canopy_legacysim -v ON_ERROR_STOP=1 -c "create schema pgtle" -c "comment on schema pgtle is 'canopy test stand-in'" \
  -c "create table pgtle.feature_info (feature text, proname text)" -c "insert into pgtle.feature_info values ('passcheck', 'test_only_checker')"
if psql -X -q -At -d canopy_legacysim -c "$PW_SQL" > "$T/password-passcheck.log" 2>&1; then
  sed -E 's/[0-9a-f]{64}/<64-hex>/g' "$T/password-passcheck.log"; echo "  FAIL  the password tool ran while a pg_tle passcheck function would receive the password"; exit 1; fi
grep -q 'NO SE CAMBIÓ NADA' "$T/password-passcheck.log" && grep -q 'pg_tle passcheck' "$T/password-passcheck.log" && ! grep -qE '[0-9a-f]{64}' "$T/password-passcheck.log" \
  || { cat "$T/password-passcheck.log"; echo "  FAIL  the password tool's pg_tle refusal does not say why (or shows a value)"; exit 1; }
[ "$(psql -X -At -d canopy_legacysim -c "$AUTHID_SQL")" = "$authid_before" ] \
  || { echo "  FAIL  the password tool's pg_tle refusal changed the account's login or password"; exit 1; }
[ "$(psql -X -q -At -d canopy_legacysim -c "$(cat "$ROOT/supabase/tools/backup-account-check.sql")" \
     | python3 -I -c 'import json, sys; d = json.load(sys.stdin)["logging"]; print(d["pgtle_passcheck_functions"], d["backup_password_would_refuse"])')" = "1 True" ] \
  || { echo "  FAIL  backup-account-check.sql does not count the pg_tle checker or does not predict the refusal"; exit 1; }
psql -X -q -d canopy_legacysim -v ON_ERROR_STOP=1 -c "drop schema pgtle cascade"
psql -X -q -d postgres -v ON_ERROR_STOP=1 -c "alter database canopy_legacysim reset pgtle.enable_password_check"
# a3) the account does not exist (step 2 not done): the tool refuses, names step 2 and creates nothing. canopy_backup
#     exists by now, so a copy of the tool names an account that does not
ABSENT=canopy_backup_absent_test
[ "$(psql -X -At -d postgres -c "select count(*) from pg_roles where rolname = '$ABSENT'")" = "0" ] \
  || { echo "  FAIL  the test server has a role $ABSENT: case (a3) needs an account that does not exist"; exit 1; }
if psql -X -q -At -d canopy_legacysim -c "${PW_SQL//canopy_backup/$ABSENT}" > "$T/password-absent.log" 2>&1; then
  sed -E 's/[0-9a-f]{64}/<64-hex>/g' "$T/password-absent.log"; echo "  FAIL  the password tool ran without the account"; exit 1; fi
grep -q "NO SE CAMBIÓ NADA: la cuenta $ABSENT no existe; primero el paso 2" "$T/password-absent.log" && ! grep -qE '[0-9a-f]{64}' "$T/password-absent.log" \
  || { cat "$T/password-absent.log"; echo "  FAIL  without the account the password tool does not say so (or shows a value)"; exit 1; }
[ "$(psql -X -At -d postgres -c "select count(*) from pg_roles where rolname = '$ABSENT'")" = "0" ] \
  && [ "$(psql -X -At -d canopy_legacysim -c "$AUTHID_SQL")" = "$authid_before" ] \
  || { echo "  FAIL  without the account the password tool created one, or changed canopy_backup"; exit 1; }
# b) the normal run: one row of 64 hexadecimal characters, stored as the SCRAM verifier of exactly that value, and the
#    account logs in with it; a second run replaces it (the first no longer matches, and no longer logs in where the
#    server checks passwords: a local test server trusts local connections, CI's checks them)
attrs_before="$(psql -X -At -d canopy_legacysim -c "$ATTRS_SQL")"
pw1="$(psql -X -q -At -v ON_ERROR_STOP=1 -d canopy_legacysim -c "$PW_SQL" 2> "$T/password1.err")" \
  || { cat "$T/password1.err"; echo "  FAIL  the password tool failed"; exit 1; }
[[ "$pw1" =~ $HEX64 ]] || { echo "$pw1" | sed -E 's/[0-9a-f]{64}/<64-hex>/g' | head -3; echo "  FAIL  the password tool did not answer one row of 64 hexadecimal characters"; exit 1; }
[ "$(psql -X -At -d canopy_legacysim -c "select rolcanlogin from pg_roles where rolname = 'canopy_backup'")" = "t" ] \
  || { echo "  FAIL  the password tool did not let the account log in"; exit 1; }
scram_ok "$(verifier)" "$pw1" || { echo "  FAIL  the stored SCRAM verifier is not the shown password's"; exit 1; }
[ "$(login_as_backup "$pw1")" = "1" ] || { echo "  FAIL  the backup account cannot log in with the generated password"; exit 1; }
[ "$(psql -X -At -d canopy_legacysim -c "$ATTRS_SQL")" = "$attrs_before" ] \
  || { echo "  FAIL  the password tool changed something other than LOGIN and the password"; exit 1; }
pw2="$(psql -X -q -At -v ON_ERROR_STOP=1 -d canopy_legacysim -c "$PW_SQL" 2> "$T/password2.err")" \
  || { cat "$T/password2.err"; echo "  FAIL  the password tool failed on a second run"; exit 1; }
[[ "$pw2" =~ $HEX64 ]] && [ "$pw2" != "$pw1" ] || { echo "  FAIL  a second run did not give a different 64-hex password"; exit 1; }
scram_ok "$(verifier)" "$pw2" && ! scram_ok "$(verifier)" "$pw1" || { echo "  FAIL  a second run did not replace the password"; exit 1; }
[ "$(login_as_backup "$pw2")" = "1" ] || { echo "  FAIL  the backup account cannot log in with the second password"; exit 1; }
if [ "$(login_as_backup 'test-only-wrong')" != "1" ]; then   # the server checks passwords
  [ "$(login_as_backup "$pw1")" != "1" ] || { echo "  FAIL  the first password still logs in after a second run"; exit 1; }
fi
# c) statement by statement (psql -f, not one transaction): the password is set but never shown; the row says REVISAR
psql -X -q -At -d canopy_legacysim -f "$ROOT/supabase/tools/backup-password.sql" > "$T/password-f.log" 2>&1 || true
grep -q '^REVISAR: la contraseña no llegó a esta fila' "$T/password-f.log" && ! grep -qE '[0-9a-f]{64}' "$T/password-f.log" \
  || { cat "$T/password-f.log"; echo "  FAIL  run statement by statement, the password tool did not say REVISAR (or showed a value)"; exit 1; }
# d) when the inner ALTER ROLE fails (here: an editor with CREATEROLE but no ADMIN on the account; PostgreSQL 16+
#    refuses that), the error names the cause and carries no password: PostgreSQL would otherwise put the nested
#    statement, password included, in the error's CONTEXT line (shown by the SQL Editor and written to the server log)
psql -X -q -d postgres -v ON_ERROR_STOP=1 -c "drop role if exists canopy_test_editor" \
  -c "create role canopy_test_editor login password 'test-only-editor' nosuperuser createrole nobypassrls"
as_editor() { PGPASSWORD=test-only-editor psql -X -q -At -h "$PGHOST" -p "$PGPORT" -U canopy_test_editor -d canopy_legacysim "$@"; }
if [ "$(psql -X -At -c "select current_setting('server_version_num')::int >= 160000")" = "t" ]; then
  authid_before="$(psql -X -At -d canopy_legacysim -c "$AUTHID_SQL")"
  if as_editor -c "$PW_SQL" > "$T/password-noadmin.log" 2>&1; then
    cat "$T/password-noadmin.log"; echo "  FAIL  an editor without ADMIN on the account set its password"; exit 1; fi
  grep -q 'NO SE CAMBIÓ NADA: no se pudo poner la contraseña a canopy_backup' "$T/password-noadmin.log" && ! grep -qE '[0-9a-f]{64}' "$T/password-noadmin.log" \
    || { sed -E 's/[0-9a-f]{64}/<64-hex>/g' "$T/password-noadmin.log"; echo "  FAIL  the failed password tool does not name the cause, or its error carries the password"; exit 1; }
  [ "$(psql -X -At -d canopy_legacysim -c "$AUTHID_SQL")" = "$authid_before" ] || { echo "  FAIL  the failed password tool changed the account"; exit 1; }
else
  echo "  skip  password tool failure path (PostgreSQL 16+ only)"
fi
# d2) another session holds the account's catalog row while log_lock_waits is on and deadlock_timeout is below the 900 ms
#     the tool used to wait: with those settings the server logs a wait that reaches deadlock_timeout, and that LOG line
#     carries the nested statement, password included. The tool must give up first (lock_timeout under deadlock_timeout),
#     name the lock timeout without the password and change nothing. Both are superuser settings (Supabase: off and 1 s)
psql -X -q -d postgres -v ON_ERROR_STOP=1 -c "alter database canopy_legacysim set log_lock_waits = on" -c "alter database canopy_legacysim set deadlock_timeout = '200ms'"
authid_before="$(psql -X -At -d canopy_legacysim -c "$AUTHID_SQL")"
PGAPPNAME=canopy_test_lock psql -X -q -d canopy_legacysim -c "begin; alter role canopy_backup connection limit -1; select pg_sleep(20); rollback" >/dev/null 2>&1 & LOCK_PID=$!
for _ in $(seq 1 100); do   # until that session holds its lock on pg_authid
  [ "$(psql -X -At -d canopy_legacysim -c "select count(*) from pg_locks l join pg_stat_activity a on a.pid = l.pid where a.application_name = 'canopy_test_lock'
         and l.locktype = 'relation' and l.relation = 'pg_catalog.pg_authid'::regclass and l.mode = 'RowExclusiveLock' and l.granted")" = "1" ] && break; sleep 0.1; done
if psql -X -q -At -d canopy_legacysim -c "$PW_SQL" > "$T/password-locked.log" 2>&1; then
  sed -E 's/[0-9a-f]{64}/<64-hex>/g' "$T/password-locked.log"; echo "  FAIL  the password tool set the password through a lock another session held"; exit 1; fi
psql -X -q -d canopy_legacysim -c "select pg_cancel_backend(pid) from pg_stat_activity where application_name = 'canopy_test_lock'" >/dev/null; wait "$LOCK_PID" 2>/dev/null || true
psql -X -q -d postgres -v ON_ERROR_STOP=1 -c "alter database canopy_legacysim reset log_lock_waits" -c "alter database canopy_legacysim reset deadlock_timeout"
grep -q 'NO SE CAMBIÓ NADA: no se pudo poner la contraseña a canopy_backup (55P03' "$T/password-locked.log" && ! grep -qE '[0-9a-f]{64}' "$T/password-locked.log" \
  || { sed -E 's/[0-9a-f]{64}/<64-hex>/g' "$T/password-locked.log"; echo "  FAIL  behind a lock, the password tool did not give up with the lock timeout, or its error carries the password"; exit 1; }
[ "$(psql -X -At -d canopy_legacysim -c "$AUTHID_SQL")" = "$authid_before" ] || { echo "  FAIL  the password tool changed the account while giving up on a lock"; exit 1; }
if [ -n "$log_mark" ] && tail -n +"$((log_mark + 1))" "$SERVER_LOG" | grep -qE '[0-9a-f]{64}'; then
  echo "  FAIL  a run of the password tool wrote a 64-hex string into the server log"; exit 1; fi
# e) the read-only check (supabase/tools/backup-account-check.sql) as the superuser and as a non-superuser editor:
#    the same answer, with what the owner must see after the paste and the password
CHECK_SQL="$(cat "$ROOT/supabase/tools/backup-account-check.sql")"
psql -X -q -At -v ON_ERROR_STOP=1 -d canopy_legacysim -c "$CHECK_SQL" > "$T/check.json" || { cat "$T/check.json"; echo "  FAIL  backup-account-check.sql"; exit 1; }
as_editor -v ON_ERROR_STOP=1 -c "$CHECK_SQL" > "$T/check-editor.json" || { cat "$T/check-editor.json"; echo "  FAIL  backup-account-check.sql as a non-superuser editor"; exit 1; }
python3 -I - "$T/check.json" "$T/check-editor.json" <<'PY' || { cat "$T/check.json"; echo "  FAIL  backup-account-check.sql does not show the account as it must be"; exit 1; }
import json, sys
j, e = (json.load(open(f)) for f in sys.argv[1:3])
want = {'account': {'exists': True, 'can_login': True, 'bypassrls': True, 'superuser': False, 'memberships': 0, 'pg_read_all_data_member': False, 'owns_objects': 0},
        'reads': {'app_tables_readable': 26, 'app_tables_total': 26, 'app_tables_not_readable': [], 'storage_objects_readable': True},
        'must_not': {'writable_relations': 0, 'writable_names': [], 'auth_schema_usage': False, 'auth_relations_readable': 0,
                     'can_read_pg_authid_rolpassword': False, 'owner_rights_functions_executable': [], 'set_role_targets': []},
        'logging': {'backup_password_would_refuse': False}}
bad = {(s, k): j[s][k] for s in want for k in want[s] if j[s][k] != want[s][k]}
assert not bad, bad
for s in ('account', 'reads', 'must_not', 'logging'):
    assert j[s] == e[s], (s, j[s], e[s])
assert '@' not in json.dumps(j), 'an email in the check'
PY
grep -qE '[0-9a-f]{64}' "$T/check.json" "$T/check-editor.json" && { echo "  FAIL  the check shows a password"; exit 1; }
psql -X -q -d postgres -c "drop role canopy_test_editor" >/dev/null
# the test's own password for the steps below
psql -X -q -d canopy_legacysim -v ON_ERROR_STOP=1 <<'SQL'
alter role canopy_backup login password 'test-only-backup';
insert into public.orders (id, total_crc, payment_method, paid, status)
  select gen_random_uuid(), 500 * g, 'card', true, 'done' from generate_series(1, 25) g;
insert into public.order_items (order_id, item_name, price_crc, qty) select id, 'Café', total_crc, 1 from public.orders;
insert into storage.objects (bucket_id, name, metadata) values
  ('menu-photos', 'desayunos/gallo-pinto.jpg', '{"size": 11}'), ('menu-photos', 'latte.png', '{"size": 5}');
SQL
# like Supabase's supabase_admin: default rights in public held by a role that the server restored into does not
# have (it is dropped below, before the restore): only postgres's own default rights may be restored
psql -X -q -d postgres -c "drop role if exists canopy_test_dacl" -c "create role canopy_test_dacl nologin" >/dev/null
psql -X -q -d canopy_legacysim -v ON_ERROR_STOP=1 -c "alter default privileges for role canopy_test_dacl in schema public grant select on tables to anon" >/dev/null
PHOTOS="$T/www/storage/v1/object/public/menu-photos"; mkdir -p "$PHOTOS/desayunos"
printf 'gallo pinto' > "$PHOTOS/desayunos/gallo-pinto.jpg"; printf 'latte' > "$PHOTOS/latte.png"
WWW_PORT=18431
python3 -m http.server "$WWW_PORT" --bind 127.0.0.1 --directory "$T/www" >/dev/null 2>&1 & WWW_PID=$!
trap 'kill "$WWW_PID" 2>/dev/null || true; reset_6i; reset_pw; rm -rf "$T"' EXIT
for _ in $(seq 1 50); do curl -fsS -o /dev/null "http://127.0.0.1:$WWW_PORT/storage/v1/object/public/menu-photos/latte.png" 2>/dev/null && break; sleep 0.1; done
LEGACY_URL="postgresql://canopy_backup:test-only-backup@${PGHOST}:${PGPORT}/canopy_legacysim"
mkdir -p "$T/work0"
CANOPY_DB_URL="$LEGACY_URL" AGE_RECIPIENTS="$RECIPIENTS" RESTORE_TEST_URL="$URL_BASE/postgres" UPLOAD_DIR="$T/offsite0" WORK_DIR="$T/work0" \
  SUPABASE_URL="http://127.0.0.1:$WWW_PORT" BACKUP_SOURCE=manual bash "$ROOT/ops/backup/backup.sh" > "$T/backup0.log" 2>&1 \
  || { cat "$T/backup0.log"; echo "  FAIL  backup before migration 0000"; exit 1; }
# the nightly restore test restored postgres's own default rights and none of the other role's
grep -q ' DEFAULT ACL public DEFAULT PRIVILEGES FOR TABLES postgres$' "$T/work0/toc.list" && ! grep -q ' DEFAULT ACL .* canopy_test_dacl$' "$T/work0/toc.list" \
  || { grep 'DEFAULT ACL' "$T/work0/toc.list"; echo "  FAIL  the nightly restore test keeps default rights of other roles or drops postgres's own"; exit 1; }
grep -q 'restauración: passed' "$T/backup0.log" && grep -q 'contenido idéntico en' "$T/backup0.log" && grep -q '2 archivos verificados' "$T/backup0.log" \
  || { cat "$T/backup0.log"; echo "  FAIL  backup before 0000: restore, content or photos not verified"; exit 1; }
F0="$(find "$T/offsite0" -name '*.tar.age' | head -1)"
psql -X -q -d canopy_legacysim -c "alter default privileges for role canopy_test_dacl in schema public revoke select on tables from anon" >/dev/null
psql -X -q -d postgres -c "drop role canopy_test_dacl" >/dev/null
[ "$(psql -X -At -d postgres -c "select count(*) from pg_roles where rolname = 'canopy_test_dacl'")" = "0" ] || { echo "  FAIL  test setup: the default-rights role is still there"; exit 1; }
psql -X -q -d postgres -c "drop database if exists canopy_restored0 with (force)" -c "create database canopy_restored0"
psql -X -q -d canopy_restored0 -f "$ROOT/ops/backup/restore-stub.sql" >/dev/null
KEEP_STORAGE_TO="$T/photos0" bash "$ROOT/ops/backup/restore.sh" "$F0" "$T/recovery.key" "$URL_BASE/canopy_restored0" --yes > "$T/restore0.log" 2>&1 \
  || { cat "$T/restore0.log"; echo "  FAIL  restore of the backup taken before 0000"; exit 1; }
grep -q 'contenido idéntico en' "$T/restore0.log" || { cat "$T/restore0.log"; echo "  FAIL  restored content not compared"; exit 1; }
cmp -s "$T/photos0/menu-photos/desayunos/gallo-pinto.jpg" "$PHOTOS/desayunos/gallo-pinto.jpg" || { echo "  FAIL  photo missing from the backup"; exit 1; }
# the logins are not in the backup (the account cannot read them): no auth file in the archive
age -d -i "$T/owner.key" "$F0" | tar -tf - > "$T/archive0.txt"
grep -q '/app.dump$' "$T/archive0.txt" && ! grep -qi 'auth' "$T/archive0.txt" \
  || { cat "$T/archive0.txt"; echo "  FAIL  the archive holds a copy of the logins (auth) or no database dump"; exit 1; }
# a photo that cannot be copied fails the backup (it is never reported as complete)
rm "$PHOTOS/latte.png"
if CANOPY_DB_URL="$LEGACY_URL" AGE_RECIPIENTS="$RECIPIENTS" UPLOAD_DIR="$T/offsite0b" SUPABASE_URL="http://127.0.0.1:$WWW_PORT" \
     BACKUP_SOURCE=manual bash "$ROOT/ops/backup/backup.sh" > "$T/backup0b.log" 2>&1; then
  cat "$T/backup0b.log"; echo "  FAIL  a backup with a missing photo was reported complete"; exit 1; fi
grep -q 'faltan 1 ' "$T/backup0b.log" || { cat "$T/backup0b.log"; echo "  FAIL  missing photo not named"; exit 1; }
kill "$WWW_PID" 2>/dev/null || true

"$ROOT/tests/build-db.sh" canopy_prodsim >/dev/null
# after every migration the read-only check still reads the account's rights (0002 and 0013 give it the new tables)
psql -X -q -At -v ON_ERROR_STOP=1 -d canopy_prodsim -c "$(cat "$ROOT/supabase/tools/backup-account-check.sql")" > "$T/check-migrated.json" \
  || { cat "$T/check-migrated.json"; echo "  FAIL  backup-account-check.sql after the migrations"; exit 1; }
python3 -I - "$T/check-migrated.json" <<'PY' || { cat "$T/check-migrated.json"; echo "  FAIL  after the migrations the check does not show every table of the café readable, or something it must not"; exit 1; }
import json, sys
j = json.load(open(sys.argv[1]))
assert j['reads']['app_tables_readable'] == j['reads']['app_tables_total'] > 26 and j['reads']['app_tables_not_readable'] == [], j['reads']
assert j['must_not']['backup_report_executable'] is True and j['must_not']['owner_rights_functions_executable'] == [], j['must_not']
assert j['must_not']['writable_relations'] == 0 and j['must_not']['auth_relations_readable'] == 0 and j['account']['memberships'] == 0, j['must_not']
PY
psql -X -q -d canopy_prodsim -v ON_ERROR_STOP=1 <<'SQL'
alter role canopy_backup login password 'test-only-backup';
insert into public.orders (id, total_crc, payment_method, paid, status)
  select gen_random_uuid(), 1000 * g, 'cash_crc', true, 'done' from generate_series(1, 40) g;
insert into public.order_items (order_id, item_name, price_crc, qty) select id, 'Latte', total_crc, 1 from public.orders;
SQL
DBURL="postgresql://canopy_backup:test-only-backup@${PGHOST}:${PGPORT}/canopy_prodsim"

# 0) the secrets are checked before any connection (BACKUP_CHECK_ONLY=url stops right after): the owner's postgres
#    account (the first production run, 2026-10-13: "password authentication failed for user postgres"), brackets, the
#    transaction port, the direct host, a missing project or sslmode, another project, a password that is not the
#    64-hex one, a line break, a parameter after the "?" that could replace the account (libpq lets ?user= win), a
#    private age key. A refused run connects to nothing (not even to record the failure),
#    and no message shows the password or the key
PW64=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
THROWAWAY_KEY="$(age-keygen 2>/dev/null | grep -E '^AGE-SECRET')"   # a private key made for this check only
POOL=aws-0-us-east-2.pooler.supabase.com; TREF=abcdefghijklmnopqrst; GOOD="postgresql://canopy_backup.$TREF:$PW64@$POOL:5432/postgres?sslmode=require"
url_case() {  # what the message must say, the address, [recipients]
  local out
  if out="$(CANOPY_DB_URL="$2" AGE_RECIPIENTS="${3:-$RECIPIENTS}" SUPABASE_URL="https://$TREF.supabase.co" BACKUP_CHECK_ONLY=url \
              bash "$ROOT/ops/backup/backup.sh" 2>&1)"; then
    echo "$out" | sed "s/$PW64/<64-hex>/g"; echo "  FAIL  a wrong secret passed the check (expected: $1)"; exit 1; fi
  echo "$out" | grep -qF "$1" && ! echo "$out" | grep -qE "$PW64|${THROWAWAY_KEY: -20}|psql:|no se pudo anotar" \
    || { echo "$out" | sed "s/$PW64/<64-hex>/g"; echo "  FAIL  a refused secret: wrong message, a connection was tried, or a value was shown (expected: $1)"; exit 1; }
}
url_case 'la cuenta es postgres, la del dueño' "postgresql://postgres.$TREF:$PW64@$POOL:5432/postgres?sslmode=require"
url_case 'la cuenta es postgres, la del dueño' "postgresql://postgres.$TREF:$PW64@$POOL:5432/canopy_backup.?sslmode=require"
url_case 'la cuenta es postgres, la del dueño' "postgresql://postgres:test-only@127.0.0.1:1/canopy_prodsim"
url_case 'la cuenta no es canopy_backup (no se muestra' "postgresql://$PW64@$POOL:5432/postgres?sslmode=require"
url_case 'quedó entre corchetes' "postgresql://canopy_backup.$TREF:[YOUR-PASSWORD]@$POOL:5432/postgres?sslmode=require"
url_case 'quedó entre corchetes' "postgresql://canopy_backup.$TREF:[$PW64]@$POOL:5432/postgres?sslmode=require"
url_case 'el puerto es 6543' "postgresql://canopy_backup.$TREF:$PW64@$POOL:6543/postgres?sslmode=require"
url_case 'es la conexión directa' "postgresql://canopy_backup.$TREF:$PW64@db.$TREF.supabase.co:5432/postgres?sslmode=require"
url_case 'le falta el proyecto' "postgresql://canopy_backup:$PW64@$POOL:5432/postgres?sslmode=require"
url_case 'de otro proyecto que el de SUPABASE_URL' "postgresql://canopy_backup.zyxwvutsrqponmlkjihg:$PW64@$POOL:5432/postgres?sslmode=require"
url_case 'no es la de 64 caracteres' "postgresql://canopy_backup.$TREF:${PW64:0:60}@$POOL:5432/postgres?sslmode=require"
url_case 'falta ?sslmode=require' "postgresql://canopy_backup.$TREF:$PW64@$POOL:5432/postgres"
url_case 'solo puede ir sslmode=require' "$GOOD&user=postgres.$TREF"
url_case 'el puerto es 6543' "postgresql://canopy_backup.$TREF:$PW64@${POOL^^}.:6543/postgres?sslmode=require"   # the host in upper case with a trailing dot is still the pooler
url_case 'solo puede ir sslmode=require' "postgresql://canopy_backup.$TREF:$PW64@$POOL:5432/postgres?options=-c%20role%3Dpostgres&sslmode=require"
url_case 'solo puede ir sslmode=require' "postgresql://canopy_backup:test-only-backup@127.0.0.1:1/canopy_prodsim?user=postgres"
url_case 'un espacio o un salto de línea' "$GOOD
"
url_case 'trae una llave PRIVADA' "$GOOD" "$RECIPIENTS $THROWAWAY_KEY"
url_case 'no es una pública age1' "$GOOD" "$RECIPIENTS age1short"
CANOPY_DB_URL="$GOOD" AGE_RECIPIENTS="$RECIPIENTS" SUPABASE_URL="https://$TREF.supabase.co" BACKUP_CHECK_ONLY=url \
  bash "$ROOT/ops/backup/backup.sh" > "$T/url-ok.log" 2>&1 && grep -q 'secretos en orden' "$T/url-ok.log" && ! grep -q "$PW64" "$T/url-ok.log" \
  || { sed "s/$PW64/<64-hex>/g" "$T/url-ok.log"; echo "  FAIL  the right secrets did not pass the check"; exit 1; }
# the connection check (BACKUP_CHECK_ONLY=1, the private repository's "Comprobar la conexión"): logs in as
# canopy_backup, reads its rights and stops; nothing copied, uploaded or recorded in canopy.backup_runs
runs_before="$(psql -X -At -d canopy_prodsim -c "select count(*) from canopy.backup_runs")"
CANOPY_DB_URL="$DBURL" AGE_RECIPIENTS="$RECIPIENTS" UPLOAD_DIR="$T/offsite-check" BACKUP_SOURCE=cloud BACKUP_CHECK_ONLY=1 \
  bash "$ROOT/ops/backup/backup.sh" > "$T/check-only.log" 2>&1 \
  && grep -q 'conexión verificada: entró canopy_backup' "$T/check-only.log" && grep -qE 'lee ([0-9]+) de \1 tablas del café y no puede cambiar ninguna' "$T/check-only.log" \
  && [ ! -e "$T/offsite-check" ] && [ "$(psql -X -At -d canopy_prodsim -c "select count(*) from canopy.backup_runs")" = "$runs_before" ] \
  || { cat "$T/check-only.log"; echo "  FAIL  the connection check did not verify the account, or copied or recorded something"; exit 1; }
# ...a connection check never records anything, not even a failure between the login and its own checks (here: an
# older pg_dump than the server, through a fake pg_dump on PATH)
mkdir -p "$T/oldbin"; printf '#!/bin/sh\necho "pg_dump (PostgreSQL) 9.0"\n' > "$T/oldbin/pg_dump"; chmod +x "$T/oldbin/pg_dump"
if PATH="$T/oldbin:$PATH" CANOPY_DB_URL="$DBURL" AGE_RECIPIENTS="$RECIPIENTS" BACKUP_SOURCE=cloud BACKUP_CHECK_ONLY=1 bash "$ROOT/ops/backup/backup.sh" > "$T/check-oldpg.log" 2>&1 \
   || ! grep -q 'es más viejo que el servidor' "$T/check-oldpg.log" \
   || [ "$(psql -X -At -d canopy_prodsim -c "select count(*) from canopy.backup_runs")" != "$runs_before" ]; then
  cat "$T/check-oldpg.log"; echo "  FAIL  the connection check did not stop on an old pg_dump, or recorded that failure"; exit 1; fi
# ...a refused first connection says why in the step line (the summary shows it), without the password, and records
# nothing (a closed port here: the message is libpq's)
if CANOPY_DB_URL="postgresql://canopy_backup:$PW64@127.0.0.1:1/canopy_prodsim" AGE_RECIPIENTS="$RECIPIENTS" BACKUP_SOURCE=cloud bash "$ROOT/ops/backup/backup.sh" > "$T/refused.log" 2>&1 \
   || ! grep -qE 'ERROR en el paso: conectar con la base: .*(refused|rechaz).*No se copió nada' "$T/refused.log" \
   || grep -q "$PW64" "$T/refused.log" || grep -q 'no se pudo anotar' "$T/refused.log"; then
  sed "s/$PW64/<64-hex>/g" "$T/refused.log"; echo "  FAIL  a refused first connection: no cause in the step line, the password shown, or a second login tried"; exit 1; fi
# ...and it refuses an account that can change the café's data (and records nothing)
psql -X -q -d canopy_prodsim -c "grant insert on public.orders to canopy_backup" >/dev/null
if CANOPY_DB_URL="$DBURL" AGE_RECIPIENTS="$RECIPIENTS" BACKUP_SOURCE=cloud BACKUP_CHECK_ONLY=1 bash "$ROOT/ops/backup/backup.sh" > "$T/check-write.log" 2>&1 \
   || ! grep -q 'canopy_backup puede cambiar 1 tablas' "$T/check-write.log" \
   || [ "$(psql -X -At -d canopy_prodsim -c "select count(*) from canopy.backup_runs")" != "$runs_before" ]; then
  psql -X -q -d canopy_prodsim -c "revoke insert on public.orders from canopy_backup" >/dev/null
  cat "$T/check-write.log"; echo "  FAIL  the connection check passed an account that can change an order, or recorded the failure"; exit 1; fi
psql -X -q -d canopy_prodsim -v ON_ERROR_STOP=1 -c "revoke insert on public.orders from canopy_backup" >/dev/null
# a login that is not canopy_backup is refused after connecting too (here: the right address, but a role switched in
# through the connection options), before anything is read or recorded
psql -X -q -d postgres -c "drop role if exists canopy_test_ident" -c "create role canopy_test_ident nologin" -c "grant canopy_test_ident to canopy_backup" >/dev/null
if PGOPTIONS='-c role=canopy_test_ident' CANOPY_DB_URL="$DBURL" AGE_RECIPIENTS="$RECIPIENTS" BACKUP_SOURCE=cloud bash "$ROOT/ops/backup/backup.sh" > "$T/ident.log" 2>&1 \
   || ! grep -q 'entró la cuenta canopy_test_ident, no canopy_backup' "$T/ident.log" \
   || [ "$(psql -X -At -d canopy_prodsim -c "select count(*) from canopy.backup_runs")" != "$runs_before" ]; then
  psql -X -q -d postgres -c "drop role if exists canopy_test_ident" >/dev/null
  cat "$T/ident.log"; echo "  FAIL  a run that logged in as another role was not refused, or recorded something"; exit 1; fi
psql -X -q -d postgres -v ON_ERROR_STOP=1 -c "drop role canopy_test_ident" >/dev/null

# 1) nightly backup
CANOPY_DB_URL="$DBURL" AGE_RECIPIENTS="$RECIPIENTS" RESTORE_TEST_URL="$URL_BASE/postgres" UPLOAD_DIR="$T/offsite" \
  BACKUP_SOURCE=cloud bash "$ROOT/ops/backup/backup.sh" > "$T/backup.log" 2>&1 || { cat "$T/backup.log"; echo "  FAIL  backup run"; exit 1; }
F="$(find "$T/offsite" -name '*.tar.age' | head -1)"
[ -n "$F" ] || { echo "  FAIL  no encrypted backup uploaded"; exit 1; }
grep -q 'restauración: passed' "$T/backup.log" || { cat "$T/backup.log"; echo "  FAIL  restore test did not pass"; exit 1; }
if tar -tf "$F" >/dev/null 2>&1 || grep -qa 'CREATE TABLE\|orders' "$F"; then echo "  FAIL  backup is readable without the key"; exit 1; fi
[ "$(psql -X -At -d canopy_prodsim -c "select status || '/' || restore_test from canopy.backup_runs order by id desc limit 1")" = "ok/passed" ] \
  || { echo "  FAIL  backup run not recorded"; exit 1; }

# 2) restore with the recovery key into an empty database that sorts text like most servers (glibc en_US, the
#    postgres image's default): the row and rights fingerprints must not depend on the server's language
psql -X -q -d postgres -c "drop database if exists canopy_restored with (force)" \
  -c "create database canopy_restored template template0 locale_provider icu icu_locale 'en-US-u-ka-shifted' locale 'C.UTF-8'"
psql -X -q -d canopy_restored -f "$ROOT/ops/backup/restore-stub.sql" >/dev/null
bash "$ROOT/ops/backup/restore.sh" "$F" "$T/recovery.key" "$URL_BASE/canopy_restored" --yes > "$T/restore.log" 2>&1 \
  || { cat "$T/restore.log"; echo "  FAIL  restore"; exit 1; }
grep -q 'OK: ' "$T/restore.log" || { cat "$T/restore.log"; echo "  FAIL  restored rows differ"; exit 1; }
[ "$(psql -X -At -d canopy_restored -c 'select count(*) from public.orders')" = "40" ] || { echo "  FAIL  orders missing after restore"; exit 1; }
# the restored copy still enforces its security rules
psql -X -At -d canopy_restored -c "select relrowsecurity from pg_class where oid = 'public.orders'::regclass" | grep -q t \
  || { echo "  FAIL  row level security lost in restore"; exit 1; }
# ...and keeps who may run what: Supabase's default grants must not open the owner's functions to visitors
[ "$(psql -X -At -d canopy_restored -c "select has_function_privilege('anon', 'public.make_owner(text)', 'execute') or has_function_privilege('anon', 'public.manager_save_staff(uuid, text, uuid, text, text, boolean, text)', 'execute')")" = "f" ] \
  || { echo "  FAIL  the restore opened owner functions to anonymous visitors"; exit 1; }
# refuses to restore over a database that has data
if bash "$ROOT/ops/backup/restore.sh" "$F" "$T/owner.key" "$URL_BASE/canopy_restored" --yes > /dev/null 2>&1; then
  echo "  FAIL  restore overwrote a non-empty database"; exit 1; fi

# 2b) a busy backup: a sale is saved while the copy is made (right after pg_dump, before the rows are counted again).
#     The copy holds the rows of its own moment; restore.sh must compare with what the copy holds, not with the
#     count taken after it
mkdir -p "$T/busybin"
cat > "$T/busybin/pg_dump" <<SH
#!/usr/bin/env bash
"$(command -v pg_dump)" "\$@" || exit \$?
case " \$* " in *" --format=custom "*)
  psql -X -q -d canopy_prodsim -v ON_ERROR_STOP=1 -c "insert into public.orders (id, total_crc, payment_method, paid, status) values (gen_random_uuid(), 777, 'card', true, 'done')" >/dev/null;;
esac
SH
chmod +x "$T/busybin/pg_dump"
PATH="$T/busybin:$PATH" CANOPY_DB_URL="$DBURL" AGE_RECIPIENTS="$RECIPIENTS" RESTORE_TEST_URL="$URL_BASE/postgres" UPLOAD_DIR="$T/offsite-busy" \
  BACKUP_SOURCE=manual bash "$ROOT/ops/backup/backup.sh" > "$T/backup-busy.log" 2>&1 || { cat "$T/backup-busy.log"; echo "  FAIL  busy backup run"; exit 1; }
grep -q 'restauración: passed' "$T/backup-busy.log" && grep -q 'con movimiento durante la copia' "$T/backup-busy.log" \
  || { cat "$T/backup-busy.log"; echo "  FAIL  busy backup: no sale saved during the copy, or the restore test failed"; exit 1; }
[ "$(psql -X -At -d canopy_prodsim -c 'select count(*) from public.orders')" = "41" ] || { echo "  FAIL  busy backup: the sale during the copy is missing"; exit 1; }
FB="$(find "$T/offsite-busy" -name '*.tar.age' | head -1)"
psql -X -q -d postgres -c "drop database if exists canopy_restored_busy with (force)" -c "create database canopy_restored_busy"
psql -X -q -d canopy_restored_busy -f "$ROOT/ops/backup/restore-stub.sql" >/dev/null
bash "$ROOT/ops/backup/restore.sh" "$FB" "$T/recovery.key" "$URL_BASE/canopy_restored_busy" --yes > "$T/restore-busy.log" 2>&1 \
  || { cat "$T/restore-busy.log"; echo "  FAIL  restore of a backup taken while a sale was saved"; exit 1; }
grep -q 'OK: ' "$T/restore-busy.log" || { cat "$T/restore-busy.log"; echo "  FAIL  busy backup: restored rows differ"; exit 1; }
[ "$(psql -X -At -d canopy_restored_busy -c 'select count(*) from public.orders')" = "40" ] || { echo "  FAIL  busy backup: the copy is not the dump's moment"; exit 1; }

# 3) owner computer: catch up, verify checksums, status
CANOPY_CONF=/dev/null SOURCE_DIR="$T/offsite" DEST="$T/computer" bash "$ROOT/ops/backup/computer/sincronizar-respaldos.sh" > /dev/null \
  || { cat "$T/computer/ESTADO.txt"; echo "  FAIL  computer sync"; exit 1; }
grep -q 'Estado: BIEN' "$T/computer/ESTADO.txt" || { cat "$T/computer/ESTADO.txt"; echo "  FAIL  computer status"; exit 1; }
cmp -s "$F" "$T/computer/archivo/$(basename "$F")" || { echo "  FAIL  computer copy differs"; exit 1; }

# 4) the private-repository copies of the scripts are identical to the reviewed ones
for f in backup.sh restore-stub.sql; do
  cmp -s "$ROOT/ops/backup/$f" "$ROOT/ops/backup/repositorio-respaldos/$f" || { echo "  FAIL  repositorio-respaldos/$f is out of date"; exit 1; }
done
psql -X -q -d postgres -c "drop database if exists canopy_restored with (force)" -c "drop database if exists canopy_prodsim with (force)" \
  -c "drop database if exists canopy_restored0 with (force)" -c "drop database if exists canopy_legacysim with (force)" \
  -c "drop database if exists canopy_restored_busy with (force)" >/dev/null
echo "  ok    backup pipeline (before 0000 and after: account self-check (trigger functions too), password tool (refused with nothing changed: a setting that would record it, a pg_tle checker, no account; 64-hex row and login, replaced on a second run, REVISAR statement by statement, a failure carries no password, gives up on a lock before the server would log it) and read-only check, the secrets checked before connecting (the owner's postgres account refused), the connection check, backup, content fingerprints, photos, no logins, encryption, offline-key restore into an en_US-sorting database, a busy backup, computer sync)"
