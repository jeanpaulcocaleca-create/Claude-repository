#!/usr/bin/env bash
# Canopy OS · two-connection checks of the registered tills for discounts (migration 0038, D-065; mecanismo-intentos.md
# §6-§7 and §13.2). They need committed rows and two or more connections at the same moment, so they run on a database
# of their own, built fresh (tests/build-db.sh) and dropped at the end. tests/run-sql.sh runs this after the SQL files
# when it is given no pattern. Usage: tests/sql/concurrency-descuentos.sh [base database name]
#  1) 10 wrong codes sent at the same moment from one registered till: exactly 3 are tested, 7 answer till_wait;
#  2) while another connection holds the places' locks, a stopped till and an unregistered sign-in still answer (proved
#     with lock_timeout, never with wall-clock thresholds), an open till's call waits, a till in another place answers;
#  3) no staff-row cycle: pin_lock_clear and _pin_locks_clear_all against an Empleado approval, in both orders, and two
#     tills where two managers give each other the Empleado discount at once: every call finishes, no deadlock (40P01);
#  4) the one cycle 0038 cannot rule out, tab_remove_item (0031: the bill, then the PIN's staff row) against a discount
#     on the same bill with the same manager's code (the staff row, then the bill), started in both orders: PostgreSQL
#     ends one call with 40P01, that call's transaction rolls back whole (no approval, nothing counted, nothing taken
#     off), the other finishes, and the retry works; 0038's lock-order comment names it;
#  5) a void of an Empleado sale takes the per-employee lock before any stock row (the order a sale takes them in), and
#     a lock error inside the day's triggers fails the void instead of leaving the day used: the retry frees it;
#  6) a revocation that commits while a code is being checked (the owner saves the person in Equipo; before that
#     commits, a till sends the person's code: the window's code lookup still sees the old row, then waits for the row
#     lock): a new PIN, a role lowered (manager → staff; owner → manager, for Guía) and a deactivation are refused as the
#     same code a moment later is (counted bad_pin, why no_match / not_allowed / inactive), with no approval; an owner
#     lowered to manager still approves Local, stored as a manager (the role read under the lock).
# Test PINs only (tests/db/90_seed.sql, and Bea 3917, Rita 3961, Sami 3962, Oli 3963, Dani 3964, Ivo 3965 added here).
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "$HERE/pg.sh"
BASE="${1:-${CANOPY_TEST_DB:-canopy_test}}"
DB="${BASE}_conc485"
TMP="$(mktemp -d)"
ANA=a1000000-0000-4000-8000-000000000001
BEA=0b485000-0000-4000-8000-000000000001   # sorts before Ana: _pin_locks_clear_all locks Bea's row first
pass=0; fail=0
cleanup() {
  psql -X -q -d postgres -c "select pg_terminate_backend(pid) from pg_stat_activity where datname = '$DB' and pid <> pg_backend_pid()" >/dev/null 2>&1 || true
  psql -X -q -d postgres -c "drop database if exists \"$DB\" with (force)" >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT
"$HERE/build-db.sh" "$DB" >/dev/null
psql -X -q -d "$DB" -v ON_ERROR_STOP=1 -f "$HERE/sql/_helpers.sql" >/dev/null

q() { psql -X -q -At -d "$DB" -v ON_ERROR_STOP=1 "$@"; }
# the SQL a café device sends: the café login on one sign-in (session id), as the page (role authenticated)
dev() { printf "select test.login('cafe'); select test.session('%s');\nset role authenticated;\n%s\n" "$1" "$2"; }
r() { grep '^R:' | sed 's/^R://' || true; }
ok() {  # label, got, want
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "  FAIL  $1 — got '$2', want '$3'"; fi
}
# polls (at most 20 s) until the query answers t
until_t() { local i; for i in $(seq 1 200); do [ "$(q -c "$1" 2>/dev/null || true)" = "t" ] && return 0; sleep 0.1; done; return 1; }
# is that connection waiting for a lock (an advisory lock by default; a row lock with "row")
waiting() {
  local ev="= 'advisory'"; [ "${2:-}" = row ] && ev="in ('transactionid', 'tuple')"
  echo "select exists (select 1 from pg_stat_activity where datname = '$DB' and application_name = '$1' and wait_event_type = 'Lock' and wait_event $ev)"
}
gone() { echo "select not exists (select 1 from pg_stat_activity where datname = '$DB' and application_name = '$1')"; }
# a gate: a background connection holds an advisory lock until gate_open; a transaction waits at it with gate_sql
gate_close() {
  ( PGAPPNAME="gate-$1" psql -X -q -d "$DB" -c "select pg_advisory_lock(hashtextextended('conc485.$1', 0)); select pg_sleep(120);" >/dev/null 2>&1 || true ) &
  until_t "select exists (select 1 from pg_locks l join pg_stat_activity a using (pid) where a.datname = '$DB' and a.application_name = 'gate-$1' and l.locktype = 'advisory' and l.granted)" \
    || { echo "  FAIL  gate $1 could not be closed"; fail=$((fail + 1)); }
}
gate_open() { q -c "select pg_terminate_backend(pid) from pg_stat_activity where datname = '$DB' and application_name = 'gate-$1'" >/dev/null; }
gate_sql() { echo "select pg_advisory_xact_lock_shared(hashtextextended('conc485.$1', 0));"; }
# runs a SQL file in the background as a named connection; its pid goes to $bg
start() { ( PGAPPNAME="$1" psql -X -q -At -d "$DB" -v ON_ERROR_STOP=1 -f "$TMP/$1.sql" > "$TMP/$1.out" 2>&1 || true ) & bg=$!; }
finish() {  # waits (at most 30 s) for those background pids
  local p i; for p in "$@"; do for i in $(seq 1 300); do kill -0 "$p" 2>/dev/null || break; sleep 0.1; done; done
  for p in "$@"; do if kill -0 "$p" 2>/dev/null; then echo "  FAIL  a connection never finished"; fail=$((fail + 1)); kill "$p" 2>/dev/null || true; fi; done
  wait "$@" 2>/dev/null || true
}
outcome() { if grep -q 'ERROR' "$TMP/$1.out"; then grep -m1 -o 'ERROR:.*' "$TMP/$1.out"; else r < "$TMP/$1.out" | tail -1; fi; }

# fixture (committed): Bea, a second manager; three tills registered through descuento_caja_registrar
q >/dev/null <<SQL
insert into public.staff (id, name, role, active, pin_hash)
  values ('$BEA', 'Bea', 'manager', true, extensions.crypt('3917', extensions.gen_salt('bf', 4)));
SQL
reg() { dev "$1" "select test.unlock('$2', '$3'); select 'R:' || (public.descuento_caja_registrar('$1') ->> 'slot');" | q | r; }
SA="$(reg conc-a "$ANA" 4826)"; SB="$(reg conc-b "$ANA" 4826)"; SC="$(reg conc-c "$BEA" 3917)"
ok "0) three tills registered (places 1, 2 and 3)" "$SA$SB$SC" "123"

# 1) a script on a copy of one till's session: 10 wrong codes at the same moment -----------------------------------
pids=()
for i in $(seq 1 10); do
  ( dev conc-a "select 'R:' || (public.descuento_autorizar('local', '$((1000 + i))', 1000) ->> 'error');" | q | r > "$TMP/par.$i" ) &
  pids+=($!)
done
wait "${pids[@]}"
ok "1) 10 wrong codes at the same moment from one till: 3 tested (bad_pin), 7 refused untested (till_wait)" \
   "$(cat "$TMP"/par.* | sort | uniq -c | awk '{print $2 "=" $1}' | tr '\n' ' ' | sed 's/ $//')" "bad_pin=3 till_wait=7"
ok "1) ... 3 wrong-code rows for that place" "$(q -c "select count(*) from public.audit_log where action = 'discount_code_wrong' and details ->> 'slot' = '$SA'")" 3
ok "1) ... none for any other place" "$(q -c "select count(*) from public.audit_log where action = 'discount_code_wrong' and details ->> 'slot' <> '$SA'")" 0

# 2) refused calls never wait for a lock -----------------------------------------------------------------------------
# place A stopped: 9 more wrong codes, each moved back past its wait (committed, as the SQL tests move rows)
q -c "update public.audit_log set at = at - interval '2 hours' where action like 'discount%'" >/dev/null
for i in $(seq 1 9); do
  dev conc-a "select public.descuento_autorizar('local', '$((2000 + i))', 1000);" | q >/dev/null
  q -c "update public.audit_log set at = at - interval '11 minutes' where action like 'discount%'" >/dev/null
done
ok "2) (place A stopped by 12 wrong codes)" "$(q -c "select state from public._discount_slot_state($SA)")" stopped
# another connection holds the café-wide registration lock B and the place locks C of places A and B
( PGAPPNAME=conc-hold psql -X -q -d "$DB" -c "begin; select pg_advisory_xact_lock(hashtextextended('canopy.discount_tills', 0)), pg_advisory_xact_lock(hashtextextended('canopy.discount_slot:$SA', 0)), pg_advisory_xact_lock(hashtextextended('canopy.discount_slot:$SB', 0)); select pg_sleep(120); commit;" >/dev/null 2>&1 || true ) &
until_t "select count(*) = 3 from pg_locks l join pg_stat_activity a using (pid) where a.datname = '$DB' and a.application_name = 'conc-hold' and l.locktype = 'advisory' and l.granted" \
  || { echo "  FAIL  the lock holder never got its locks"; fail=$((fail + 1)); }
lt() {  # session, sql: under lock_timeout 200ms, the R: answer or the error
  dev "$1" "set lock_timeout = '200ms';
$2" | q 2>&1 | grep -E '^R:|ERROR' | head -1 | sed -E 's/^R://; s/.*ERROR: +//' || true
}
ok "2) a stopped till answers while its place's lock is held: till_stopped" \
   "$(lt conc-a "select 'R:' || (public.descuento_autorizar('local', '4826', 1000) ->> 'error');")" till_stopped
ok "2) an unregistered sign-in answers at once too: till_not_enrolled (it takes no lock)" \
   "$(lt conc-mint "select 'R:' || (public.descuento_autorizar('local', '4826', 1000) ->> 'error');")" till_not_enrolled
ok "2) an open till's call waits for its place's lock (here it times out)" \
   "$(lt conc-b "select 'R:' || (public.descuento_autorizar('local', '4826', 1000) ->> 'ok');")" "canceling statement due to lock timeout"
ok "2) a till in another place answers at once" \
   "$(lt conc-c "select 'R:' || (public.descuento_autorizar('local', '4826', 1000) ->> 'ok');")" true
ok "2) descuento_estado takes no lock" "$(lt conc-b "select 'R:' || (public.descuento_estado() #>> '{till,state}');")" ok
ok "2) descuento_cajas takes no lock" \
   "$(lt conc-c "select test.unlock('$BEA', '3917'); select 'R:' || (public.descuento_cajas() ->> 'ok');")" true
ok "2) a malformed device key is refused before the registration lock" \
   "$(lt conc-mint "select 'R:' || (public.descuento_caja_volver('not-a-key') ->> 'error');")" key_invalid
q -c "select pg_terminate_backend(pid) from pg_stat_activity where datname = '$DB' and application_name = 'conc-hold'" >/dev/null
ok "2) once the lock is free, the open till's call goes through" \
   "$(dev conc-b "select 'R:' || (public.descuento_autorizar('local', '4826', 1000) ->> 'ok');" | q | r)" true

# 3) no staff-row cycle -------------------------------------------------------------------------------------------
lock_pin() { dev conc-evil "select count(*) from (select public.access_unlock('$1', '0000') from generate_series(1, 5)) q;" | q >/dev/null; }
free_emp() {  # the page lets the day's unused Empleado approvals go (descuento_liberar), so the next run is not daily_used
  local id; for id in $(q -c "select id from public.discount_approvals where category = 'empleado' and freed_at is null and order_id is null"); do
    dev conc-b "select public.descuento_liberar('$id');" | q >/dev/null; done
}
# till B: Ana authorizes an Empleado discount for Bea; Ana's row is taken (as _discount_take_staff does) before the gate
cat > "$TMP/conc-t2.sql" <<SQL
select test.login('cafe'); select test.session('conc-b');
begin;
select 1 from public.staff where id = '$ANA' for update;
$(gate_sql g2)
set local role authenticated;
select 'R:' || coalesce(public.descuento_autorizar('empleado', '4826', 1000, '3917') ->> 'beneficiary', 'none');
commit;
SQL
# till C: Bea opens the owner areas (her row is taken by her PIN check) and, after the gate, clears Ana's 0033 lock
cat > "$TMP/conc-t1.sql" <<SQL
select test.login('cafe'); select test.session('conc-c');
begin;
set local role authenticated;
select test.unlock('$BEA', '3917');
$(gate_sql g1)
select 'R:' || public.pin_lock_clear('$ANA', '$BEA', '3917')::text;
commit;
SQL
for order in clear_first approval_first; do
  lock_pin "$ANA"
  ok "3) ($order) Ana locked at the name-picked boxes" "$(q -c "select locked_until > now() from public.staff where id = '$ANA'")" t
  gate_close g1; gate_close g2
  start conc-t1; p1=$bg; start conc-t2; p2=$bg
  until_t "$(waiting conc-t1)" && until_t "$(waiting conc-t2)" || { echo "  FAIL  3) ($order) the two connections never reached the gate"; fail=$((fail + 1)); }
  if [ "$order" = clear_first ]; then
    gate_open g1   # pin_lock_clear: Bea's row (held), then Ana's: it waits for till B
    until_t "$(waiting conc-t1 row)" || { echo "  FAIL  3) ($order) pin_lock_clear never waited for Ana's row"; fail=$((fail + 1)); }
    gate_open g2
  else
    gate_open g2   # the approval goes first: it must not wait for Bea's row, which till C holds
    until_t "select ($(gone conc-t2)) or ($(waiting conc-t2 row))" || true
    gate_open g1
  fi
  finish "$p1" "$p2"
  ok "3) ($order) pin_lock_clear (Bea's row, then Ana's) finishes" "$(outcome conc-t1)" '{"ok": true, "name": "Ana"}'
  ok "3) ($order) Ana's Empleado discount for Bea (Ana's row only, Bea's read without a lock) finishes" "$(outcome conc-t2)" Bea
  free_emp
done
# the owner's SQL tool clears every lock in id order (Bea's row, then Ana's) against the same approval
lock_pin "$ANA"; lock_pin "$BEA"
ok "3) (tool) Ana and Bea locked" "$(q -c "select count(*) from public.staff where locked_until > now()")" 2
cat > "$TMP/conc-t3.sql" <<SQL
select 'R:' || (public._pin_locks_clear_all('owner (SQL Editor)') ->> 'cleared');
SQL
gate_close g2
start conc-t2; p2=$bg
until_t "$(waiting conc-t2)" || { echo "  FAIL  3) (tool) the approval never reached the gate"; fail=$((fail + 1)); }
start conc-t3; p3=$bg
until_t "$(waiting conc-t3 row)" || { echo "  FAIL  3) (tool) _pin_locks_clear_all never waited for Ana's row"; fail=$((fail + 1)); }
gate_open g2
finish "$p2" "$p3"
ok "3) (tool) _pin_locks_clear_all finishes" "$(outcome conc-t3)" 2
ok "3) (tool) ... and the approval for Bea too" "$(outcome conc-t2)" Bea
free_emp
# two tills at once: Ana gives Bea the Empleado discount at till B while Bea gives it to Ana at till C
cat > "$TMP/conc-ta.sql" <<SQL
select test.login('cafe'); select test.session('conc-b');
begin;
select 1 from public.staff where id = '$ANA' for update;
$(gate_sql g3)
set local role authenticated;
select 'R:' || coalesce(public.descuento_autorizar('empleado', '4826', 1000, '3917') ->> 'beneficiary', 'none');
commit;
SQL
cat > "$TMP/conc-tb.sql" <<SQL
select test.login('cafe'); select test.session('conc-c');
begin;
select 1 from public.staff where id = '$BEA' for update;
$(gate_sql g3)
set local role authenticated;
select 'R:' || coalesce(public.descuento_autorizar('empleado', '3917', 1000, '4826') ->> 'beneficiary', 'none');
commit;
SQL
gate_close g3
start conc-ta; pa=$bg; start conc-tb; pb=$bg
until_t "$(waiting conc-ta)" && until_t "$(waiting conc-tb)" || { echo "  FAIL  3) (each other) the two tills never reached the gate"; fail=$((fail + 1)); }
gate_open g3
finish "$pa" "$pb"
ok "3) (each other) Ana's discount for Bea at till B finishes" "$(outcome conc-ta)" Bea
ok "3) (each other) Bea's discount for Ana at till C finishes" "$(outcome conc-tb)" Ana
ok "3) no connection hit a deadlock (40P01)" "$(cat "$TMP"/*.out | grep -ci 'deadlock' || true)" 0

# 4) tab_remove_item against a discount on the same bill, the same manager's code at two tills --------------------------
ROOT="$(cd "$HERE/.." && pwd)"
ok "4) 0038's lock-order comment names tab_remove_item's order (the bill before the staff row)" \
   "$(sed -n '/^-- Lock order/,/^-- 1) settings/p' "$ROOT/supabase/migrations/0038_descuentos_caja.sql" | grep -q 'tab_remove_item' && echo yes || echo no)" yes
# two delivered «Pay later» bills, their lines 20 minutes old (removing a line needs a manager's PIN): a fixture state
bill() {  # bill id, line id prefix
  dev conc-a "select public.pos_record_sale(jsonb_build_object('id', '$1', 'created_at', now(), 'total_crc', 10000,
    'payment_method', 'pending', 'paid', false, 'status', 'ready', 'station', 'Caja A', 'source', 'front', 'guest_name', 'Mesa',
    'items', jsonb_build_array(jsonb_build_object('id', '${2}1', 'item_name', 'Latte', 'price_crc', 4000, 'qty', 1),
                               jsonb_build_object('id', '${2}2', 'item_name', 'Ham & Cheese', 'price_crc', 6000, 'qty', 1)))) ->> 'ok';" | q >/dev/null
  q -c "update public.order_items set added_at = now() - interval '20 minutes' where order_id = '$1';
        update public.orders set status = 'done', done_at = now() - interval '15 minutes' where id = '$1';" >/dev/null
}
q -c "select test.back(interval '25 hours')" >/dev/null   # every place calm again
nwrong() { q -c "select count(*) from public.audit_log where action = 'discount_code_wrong'"; }
w0="$(nwrong)"; fp0="$(q -c "select failed_pins from public.staff where id = '$ANA'")"
# one run: $1 = which call takes its first lock early and waits at the gate (remove: till C holds the bill, as
# tab_remove_item's first lock does; discount: till B holds Ana's row, as _discount_take_staff does). Whichever call
# PostgreSQL ends (in practice the one that waited first), the other must finish, the ended one must leave nothing, and
# the staff's retry must work
run4() {
  local first="$1" X="$2" L="$3" gate="$4" holdc holdb
  holdc=""; holdb=""
  [ "$first" = remove ] && holdc="select 1 from public.orders where id = '$X' for update;
$(gate_sql "$gate")"
  [ "$first" = discount ] && holdb="select 1 from public.staff where id = '$ANA' for update;
$(gate_sql "$gate")"
  cat > "$TMP/c4-$first-rm.sql" <<SQL
select test.login('cafe'); select test.session('conc-c');
begin;
$holdc
set local role authenticated;
select 'R:' || (public.tab_remove_item('${L}2', 1, 'se equivocó de plato', 'Caja C', '$ANA', '4826', 10000) ->> 'ok');
commit;
SQL
  cat > "$TMP/c4-$first-ds.sql" <<SQL
select test.login('cafe'); select test.session('conc-b');
begin;
$holdb
set local role authenticated;
select 'R:' || (public.descuento_autorizar('local', '4826', 10000, null, null, '$X', 10000, null, 'Caja B') ->> 'total');
commit;
SQL
  local p1 p2 a b
  gate_close "$gate"
  if [ "$first" = remove ]; then a="c4-$first-rm"; b="c4-$first-ds"; else a="c4-$first-ds"; b="c4-$first-rm"; fi
  start "$a"; p1=$bg
  until_t "$(waiting "$a")" || { echo "  FAIL  4 ($first) the first call never reached the gate"; fail=$((fail + 1)); }
  start "$b"; p2=$bg
  until_t "$(waiting "$b" row)" || { echo "  FAIL  4 ($first) the second call never waited for the first one's row"; fail=$((fail + 1)); }
  gate_open "$gate"
  finish "$p1" "$p2"
  local drm dds
  drm="$(grep -c 'deadlock detected' "$TMP/c4-$first-rm.out" || true)"; dds="$(grep -c 'deadlock detected' "$TMP/c4-$first-ds.out" || true)"
  ok "4 ($first first) PostgreSQL ends exactly one of the two calls: deadlock detected (40P01)" "$((drm + dds))" 1
  if [ "$dds" = 1 ]; then
    ok "4 ($first first) ... tab_remove_item finishes" "$(outcome "c4-$first-rm")" true
    ok "4 ($first first) ... the discount's transaction rolled back whole: no approval for the bill, nothing counted, no discount on it" \
       "$(q -c "select (select count(*) from public.discount_approvals where bill_id = '$X') || '|' || (select count(*) from public.audit_log where action = 'discount_code_wrong') || '|' || total_crc || '|' || coalesce(discount_id::text, '-') from public.orders where id = '$X'")" \
       "0|$w0|4000|-"
    ok "4 ($first first) ... the staff tries again: the discount goes on the bill as it is now" \
       "$(dev conc-b "select 'R:' || (public.descuento_autorizar('local', '4826', 4000, null, null, '$X', 4000, null, 'Caja B') ->> 'total');" | q | r)" 3600
  else
    ok "4 ($first first) ... the discount finishes" "$(outcome "c4-$first-ds")" 9000
    ok "4 ($first first) ... tab_remove_item's transaction rolled back whole: both lines still on the bill" \
       "$(q -c "select count(*) from public.order_items where order_id = '$X'")" 2
    ok "4 ($first first) ... the staff tries again: the line comes off, the discount follows" \
       "$(dev conc-c "select 'R:' || (public.tab_remove_item('${L}2', 1, 'se equivocó de plato', 'Caja C', '$ANA', '4826', 9000) ->> 'ok');" | q | r)" true
  fi
}
X1=d4850000-0000-4000-8000-0000000000c1; L1=d4850000-0000-4000-8000-0000000000e
X2=d4850000-0000-4000-8000-0000000000c2; L2=d4850000-0000-4000-8000-0000000000f
bill "$X1" "$L1"; bill "$X2" "$L2"
run4 remove "$X1" "$L1" g4
run4 discount "$X2" "$L2" g5
ok "4) nothing was counted as a wrong code, and Ana's 0033 counter did not move" \
   "$(nwrong)|$(q -c "select failed_pins from public.staff where id = '$ANA'")" "$w0|$fp0"

# 5) a void of an Empleado sale: the per-employee lock before any stock row; a lock error fails the void --------------
LUIS=a1000000-0000-4000-8000-000000000002
MILK=d4850000-0000-4000-8000-0000000000a1
O1=d4850000-0000-4000-8000-0000000000d1; O2=d4850000-0000-4000-8000-0000000000d2
EKEY="hashtextextended('canopy.discount_employee:$LUIS', 0)"
q >/dev/null <<SQL
insert into public.stock_items (id, name, unit, on_hand) values ('$MILK', 'Leche 485', 'ml', 100000);
insert into public.recipes (menu_item_id, stock_item_id, qty) select id, '$MILK', 200 from public.menu_items where name = 'Latte';
SQL
emp_sale() {  # order id: Ana's code gives Luis an Empleado at till B, and a Latte ticket uses it at once
  local j; j="$(dev conc-b "select 'R:' || public.descuento_autorizar('empleado', '4826', 10000, '5284', null, null, null, null, 'Caja B')::text;" | q | r)"
  local id amt; id="$(echo "$j" | python3 -c 'import json,sys; print(json.load(sys.stdin)["id"])')"
  amt="$(echo "$j" | python3 -c 'import json,sys; print(json.load(sys.stdin)["amount"])')"
  dev conc-b "select public.pos_record_sale(jsonb_build_object('id', '$1', 'created_at', now(), 'total_crc', 10000 - $amt,
    'payment_method', 'cash_crc', 'paid', true, 'status', 'done', 'needs_kitchen', false, 'station', 'Caja B', 'guest_name', 'Luis',
    'subtotal_crc', 10000, 'discount_crc', $amt, 'discount_id', '$id',
    'items', jsonb_build_array(jsonb_build_object('item_name', 'Latte', 'price_crc', 10000, 'qty', 1)))) ->> 'ok';" | q >/dev/null
  echo "$id"
}
day() { q -c "select coalesce(freed_how, 'counts') from public.discount_approvals where id = '$1'"; }
A0="$(emp_sale "$O1")"
ok "5) (Luis's Empleado sale, with a Latte that takes milk from stock)" "$(day "$A0")|$(q -c "select count(*) > 0 from public.stock_moves where order_id = '$O1' and item_id = '$MILK'")" "counts|t"
# a) another connection holds Luis's per-employee lock: Ana's void of the sale must wait for it before any stock row
( PGAPPNAME=c5-hold psql -X -q -d "$DB" -c "begin; select pg_advisory_xact_lock($EKEY); select pg_sleep(120); commit;" >/dev/null 2>&1 || true ) &
until_t "select exists (select 1 from pg_locks l join pg_stat_activity a using (pid) where a.datname = '$DB' and a.application_name = 'c5-hold' and l.locktype = 'advisory' and l.granted)" \
  || { echo "  FAIL  5a) the lock holder never got Luis's lock"; fail=$((fail + 1)); }
dev conc-b "select 'R:' || public.manager_void_order('$ANA', '4826', '$O1', 'prueba 5')::text;" > "$TMP/c5-void.sql"
start c5-void; pv=$bg
until_t "$(waiting c5-void)" || { echo "  FAIL  5a) the void never waited for the per-employee lock"; fail=$((fail + 1)); }
ok "5a) while the void waits for Luis's lock it holds no stock row (the milk can be locked at once)" \
   "$(q -c "select 'R:' || count(*) from (select 1 from public.stock_items where id = '$MILK' for update nowait) x" 2>&1 | grep -oE 'R:[0-9]+|could not obtain lock' | head -1)" "R:1"
q -c "select pg_terminate_backend(pid) from pg_stat_activity where datname = '$DB' and application_name = 'c5-hold'" >/dev/null
finish "$pv"
ok "5a) ... once the lock is free the void finishes and gives Luis's day back" "$(outcome c5-void)|$(day "$A0")" '{"ok": true}|void'
# b) another connection holds Luis's approval row: the void's day check times out; the void must fail, not stand
A1="$(emp_sale "$O2")"
te0="$(q -c "select count(*) from public.audit_log where action = 'discount_trigger_error'")"
( PGAPPNAME=c5-hold2 psql -X -q -d "$DB" -c "begin; select 1 from public.discount_approvals where id = '$A1' for update; select pg_sleep(120); commit;" >/dev/null 2>&1 || true ) &
until_t "select exists (select 1 from pg_stat_activity where datname = '$DB' and application_name = 'c5-hold2' and wait_event = 'PgSleep')" \
  || { echo "  FAIL  5b) the row holder never started"; fail=$((fail + 1)); }
ok "5b) a lock timeout inside the day's trigger fails the void (raised again, never swallowed)" \
   "$(dev conc-b "set lock_timeout = '200ms'; select 'R:' || public.manager_void_order('$ANA', '4826', '$O2', 'prueba 5b')::text;" | q 2>&1 | grep -E '^R:|ERROR' | head -1 | sed -E 's/^R://; s/.*ERROR: +//')" \
   "canceling statement due to lock timeout"
ok "5b) ... nothing stands: the sale is not voided, Luis's day still counts, no discount_trigger_error row" \
   "$(q -c "select (voided_at is null)::text from public.orders where id = '$O2'")|$(day "$A1")|$(q -c "select count(*) from public.audit_log where action = 'discount_trigger_error'")" \
   "true|counts|$te0"
q -c "select pg_terminate_backend(pid) from pg_stat_activity where datname = '$DB' and application_name = 'c5-hold2'" >/dev/null
ok "5b) ... the manager tries again: voided, and the day comes back" \
   "$(dev conc-b "select 'R:' || (public.manager_void_order('$ANA', '4826', '$O2', 'prueba 5b') ->> 'ok');" | q | r)|$(day "$A1")" "true|void"

# 6) a revocation committed while the person's code is being checked --------------------------------------------------
RITA=0b485000-0000-4000-8000-000000000061; SAMI=0b485000-0000-4000-8000-000000000062
OLI=0b485000-0000-4000-8000-000000000063; DANI=0b485000-0000-4000-8000-000000000064; IVO=0b485000-0000-4000-8000-000000000065
q >/dev/null <<SQL
insert into public.staff (id, name, role, active, pin_hash) values
  ('$RITA', 'Rita', 'manager', true, extensions.crypt('3961', extensions.gen_salt('bf', 4))),
  ('$SAMI', 'Sami', 'manager', true, extensions.crypt('3962', extensions.gen_salt('bf', 4))),
  ('$OLI',  'Oli',  'owner',   true, extensions.crypt('3963', extensions.gen_salt('bf', 4))),
  ('$DANI', 'Dani', 'manager', true, extensions.crypt('3964', extensions.gen_salt('bf', 4))),
  ('$IVO',  'Ivo',  'owner',   true, extensions.crypt('3965', extensions.gen_salt('bf', 4)));
insert into public.compliance_confirmations (key, confirmed_by, reference) values ('courtesy_iva_confirmed', 'test', 'test');
insert into public.settings (key, value) values ('pos_discount_guia', '"on"')
  on conflict (key) do update set value = excluded.value;
SQL
# one run: $1 label, $2 id, $3 name, $4 new PIN (or null), $5 active, $6 role (the owner's save), $7 category and $8 the
# code the till sends; leaves "ok/error-or-role why:step-or-stored-role approvals-by-that-person" in R6
race6() {
  local id="$2" pin="$4"; [ "$pin" = null ] || pin="'$pin'"
  local comp=null; [ "$7" = guia ] && comp="'Tours Monteverde'"
  q -c "select test.back(interval '25 hours')" >/dev/null   # a calm place: this call is judged like any first one
  cat > "$TMP/c6-eq.sql" <<SQL
select test.login('owner', 'aal2');
begin;
set local role authenticated;
select 'R:' || (public.manager_save_staff(null, null, '$id', '$3', $pin, $5, '$6') ->> 'ok');
$(gate_sql g6)
commit;
SQL
  cat > "$TMP/c6-win.sql" <<SQL
select test.login('cafe'); select test.session('conc-a');
set role authenticated;
select 'R:' || (r ->> 'ok') || '/' || coalesce(r ->> 'error', r ->> 'role')
  from (select public.descuento_autorizar('$7', '$8', 1000, null, $comp, null, null, null, 'Caja A') r) x;
SQL
  local pe pw w0; w0="$(q -c "select coalesce(max(id), 0) from public.audit_log")"
  gate_close g6
  start c6-eq; pe=$bg
  until_t "$(waiting c6-eq)" || { echo "  FAIL  6) ($1) the owner's save never reached the gate"; fail=$((fail + 1)); }
  start c6-win; pw=$bg
  until_t "$(waiting c6-win row)" || { echo "  FAIL  6) ($1) the window call never waited for $3's row"; fail=$((fail + 1)); }
  gate_open g6
  finish "$pe" "$pw"
  ok "6) ($1) the owner's save in Equipo committed" "$(outcome c6-eq)" true
  R6="$(outcome c6-win) $(q -c "select coalesce((select (details ->> 'why') || ':' || (details ->> 'step') from public.audit_log
                                    where action = 'discount_code_wrong' and id > $w0 order by id desc limit 1),
                                   (select approver_role from public.discount_approvals where approved_by = '$id' order by created_at desc limit 1), '-')
                                 || ' ' || (select count(*) from public.discount_approvals where approved_by = '$id')")"
}
race6 'new PIN' "$RITA" Rita 3971 true manager local 3961
ok "6) a new PIN given while the old one is being checked: refused as no_match, no approval" "$R6" "false/bad_pin no_match:manager 0"
race6 'manager to staff' "$SAMI" Sami null true staff local 3962
ok "6) a manager lowered to staff while their code is being checked: refused as not_allowed, no approval" "$R6" "false/bad_pin not_allowed:manager 0"
race6 'owner to manager, Guía' "$OLI" Oli null true manager guia 3963
ok "6) an owner lowered to manager while their code is being checked for Guía: refused at the owner step, no approval" "$R6" "false/bad_pin not_allowed:owner 0"
race6 'deactivated' "$DANI" Dani null false manager local 3964
ok "6) a manager deactivated while their code is being checked: refused as inactive, no approval" "$R6" "false/bad_pin inactive:manager 0"
race6 'owner to manager, Local' "$IVO" Ivo null true manager local 3965
ok "6) an owner lowered to manager while their code is being checked for Local: approved, stored as a manager" "$R6" "true/manager manager 1"
ok "6) the revoked codes stay refused afterwards (Rita's old code, Sami's, Dani's)" \
   "$(q -c "select test.back(interval '25 hours')" >/dev/null; for c in 3961 3962 3964; do dev conc-a "select 'R:' || (public.descuento_autorizar('local', '$c', 1000) ->> 'error');" | q | r; q -c "select test.back(interval '25 hours')" >/dev/null; done | tr '\n' ' ' | sed 's/ $//')" \
   "bad_pin bad_pin bad_pin"
ok "6) ... and Rita's new code approves" \
   "$(dev conc-a "select 'R:' || (public.descuento_autorizar('local', '3971', 1000) ->> 'name');" | q | r)" Rita

if [ "$fail" -gt 0 ]; then echo "$fail of $((pass + fail)) checks failed"; exit 1; fi
echo "$pass passed"
