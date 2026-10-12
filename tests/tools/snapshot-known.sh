#!/usr/bin/env bash
# Canopy OS · refresh what supabase/tools/production-snapshot.sql "knows":
#   * every function body (md5) as of the historical scripts and after each migration, labelled legacy/0000/0001/...;
#   * the columns of each original table (before any migration);
#   * the columns migrations add to those tables (left out of the data fingerprints);
#   * the triggers on those tables, with the version that creates each one and the one that removes it, if any.
# Run it after changing anything in supabase/migrations (the rehearsal, tests/rehearsal/run.sh, fails when the function
# or table lists are out of date).
# Local test cluster only (it rebuilds the throwaway database canopy_chain).
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
# shellcheck source=/dev/null
source "$HERE/pg.sh"
case "$PGHOST" in 127.0.0.1|localhost|/*|postgres) ;; *) echo "only on a local/CI test server"; exit 2;; esac
DB=canopy_chain
OUT="$(mktemp -d)"
psql -q -X -d postgres -v ON_ERROR_STOP=1 -c "drop database if exists $DB with (force)" -c "create database $DB"
run() { psql -q -X -d "$DB" -v ON_ERROR_STOP=1 ${2:-} -f "$1" > "$OUT/log" 2>&1 || { echo "FAILED: $1"; cat "$OUT/log"; exit 1; }; }
HASHES="select n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')', left(md5(p.prosrc), 12)
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname in ('public', 'canopy', 'acct') and p.prokind in ('f', 'p')
           and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')"
COLS="select c.relname, a.attname || ':' || format_type(a.atttypid, a.atttypmod)
        from pg_class c join pg_namespace n on n.oid = c.relnamespace
        join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
       where n.nspname = 'public' and c.relkind in ('r', 'p')"
TRIGS="select c.relname, c.relname || '.' || t.tgname || ':' || pn.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || '):' || t.tgenabled::text
         from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace
         join pg_proc p on p.oid = t.tgfoid join pg_namespace pn on pn.oid = p.pronamespace
        where n.nspname = 'public' and not t.tgisinternal"
run "$HERE/db/00_supabase_stub.sql"
run "$HERE/db/01_base_tables.sql"
while read -r f; do
  f="${f%%#*}"; f="$(echo "$f" | xargs)"; [ -z "$f" ] && continue
  run "$ROOT/supabase/$f"
done < "$HERE/db/legacy-order.txt"
psql -X -At -F'|' -d "$DB" -c "$HASHES" | sed 's/$/|legacy/' > "$OUT/fn"
psql -X -At -F'|' -d "$DB" -c "$COLS" > "$OUT/cols_legacy"
echo legacy > "$OUT/states"
psql -X -At -F'|' -d "$DB" -c "$TRIGS" | sed 's/^/legacy|/' > "$OUT/trig"
for m in $(ls "$ROOT/supabase/migrations"/*.sql | sort); do
  run "$m" --single-transaction
  v="$(basename "$m" | cut -c1-4)"
  psql -X -At -F'|' -d "$DB" -c "$HASHES" | sed "s/\$/|$v/" >> "$OUT/fn"
  echo "$v" >> "$OUT/states"
  psql -X -At -F'|' -d "$DB" -c "$TRIGS" | sed "s/^/$v|/" >> "$OUT/trig"
done
psql -X -At -F'|' -d "$DB" -c "$COLS" > "$OUT/cols_final"

python3 - "$ROOT/supabase/tools/production-snapshot.sql" "$OUT" <<'PY'
import sys, hashlib, collections
path, out = sys.argv[1], sys.argv[2]
seen, fn = set(), []
for line in open(out + '/fn', encoding='utf-8'):
    name, h, ver = line.rstrip('\n').split('|')
    if (name, h) not in seen:            # earliest version that produced this body
        seen.add((name, h)); fn.append((name, h, ver))
legacy = collections.defaultdict(list)
for line in open(out + '/cols_legacy', encoding='utf-8'):
    t, c = line.rstrip('\n').split('|', 1); legacy[t].append(c)
final = collections.defaultdict(set)
for line in open(out + '/cols_final', encoding='utf-8'):
    t, c = line.rstrip('\n').split('|', 1); final[t].add(c.split(':', 1)[0])
q = lambda s: "'" + s.replace("'", "''") + "'"
def sig(cols):  # same text the snapshot builds: name:type sorted by name, joined with commas
    return hashlib.md5(','.join(sorted(cols, key=lambda c: c.split(':', 1)[0])).encode()).hexdigest()
added = sorted((t, c) for t in legacy for c in final[t] - {x.split(':', 1)[0] for x in legacy[t]})
# triggers on the original tables: (table.trigger:function:enabled, version that creates it, version that removes it)
states = [l.strip() for l in open(out + '/states', encoding='utf-8') if l.strip()]
present = collections.defaultdict(set)
for line in open(out + '/trig', encoding='utf-8'):
    ver, t, key = line.rstrip('\n').split('|', 2)
    if t in legacy: present[ver].add(key)
trig, since = [], {}
for ver in states:
    for k in sorted(set(since) - present[ver]): trig.append((k, since.pop(k), ver))
    for k in sorted(present[ver] - set(since)): since[k] = ver
trig += [(k, v, None) for k, v in since.items()]
blocks = {
  'KNOWN FUNCTIONS': 'known_fn(fn, h, ver) as (values\n' + ',\n'.join(f'  ({q(a)}, {q(b)}, {q(c)})' for a, b, c in sorted(fn)) + '),',
  'KNOWN TABLES': 'known_tab(t, sig) as (values\n' + ',\n'.join(f'  ({q(t)}, {q(sig(legacy[t]))})' for t in sorted(legacy)) + '),',
  'ADDED COLUMNS': 'added_col(t, c) as (values\n' + ',\n'.join(f'  ({q(t)}, {q(c)})' for t, c in added) + '),',
  'KNOWN TRIGGERS': 'known_trig(t, since, till) as (values\n' + ',\n'.join(
      f'  ({q(k)}, {q(a)}, {q(b) if b else "null"})' for k, a, b in sorted(trig)) + '),',
}
src = open(path, encoding='utf-8').read()
for k, body in blocks.items():
    a, b = f'-- BEGIN {k}\n', f'-- END {k}\n'
    i, j = src.index(a) + len(a), src.index(b)
    src = src[:i] + body + '\n' + src[j:]
open(path, 'w', encoding='utf-8').write(src)
print(f'{len(fn)} function versions, {len(legacy)} original tables, {len(added)} added columns, {len(trig)} triggers on them')
PY
rm -rf "$OUT"
