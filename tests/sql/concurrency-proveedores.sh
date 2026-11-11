#!/usr/bin/env bash
# Canopy OS · two-connection checks of Proveedores (migrations 0039/0040, D-067). They need committed rows and two
# connections at the same moment, so they run on a database of their own, built fresh (tests/build-db.sh) and dropped at
# the end. tests/run-sql.sh runs this after the SQL files when it is given no pattern.
# Usage: tests/sql/concurrency-proveedores.sh [base database name]
#  1) two devices receive half of the same order at once with the same version: one delivery is booked, the other
#     answers «changed» (it waited for the order and saw its new version); the stock rises once;
#  2) the same payment request sent twice at once: one payment, the other answers «repeat»;
#  3) two payments with the same SINPE confirmation at once, for two suppliers: one payment, the other
#     «duplicate_reference» (the unique index is the final guard);
#  4) a payment and a delivery of the same order at once, in both orders: both finish, no deadlock (the payment takes
#     the order before the supplier, as a delivery does);
#  5) a delivery and a sale of the same items at once, in both orders: both finish, no deadlock (both take the items in
#     item order);
#  6) an invoice and a correction of the same delivery, in both orders: the correction is refused «invoiced», or it goes
#     into the invoice with its delivery (the invoice takes the delivery's order first);
#  7) a third connection holds an item: a delivery of it gives way at once («busy», nothing booked) and a sale of it waits
#     and goes through (a delivery takes its items up front with a short wait, so a sale is never the deadlock's victim).
#  8) Contabilidad's «Registrar pago» (the owner, by bank, the whole invoice) and a Proveedores SINPE for that order at
#     the same moment, the invoice saved by SQL: both finish, no deadlock; the supplier's row serialises them, so one pays
#     and the other is refused («more than owed» or «over balance»); the invoice is never allocated above its total and the
#     supplier is never paid twice (0040's guards, owner 2026-11-07).
# Test PINs only (tests/db/90_seed.sql).
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "$HERE/pg.sh"
BASE="${1:-${CANOPY_TEST_DB:-canopy_test}}"
DB="${BASE}_conc39"
TMP="$(mktemp -d)"
ANA=a1000000-0000-4000-8000-000000000001
V1=5b000000-0000-4000-8000-0000000c3901; V2=5b000000-0000-4000-8000-0000000c3902
MILK=5a000000-0000-4000-8000-0000000c3901; CHEESE=5a000000-0000-4000-8000-0000000c3902
PO1=9a000000-0000-4000-8000-0000000c3901; PO2=9a000000-0000-4000-8000-0000000c3902
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
# a manager's device: the café login on one sign-in with Ana's unlock, as the page (role authenticated)
mgr() { printf "select test.login('cafe'); select test.session('%s'); select test.unlock('$ANA', '4826');\nset role authenticated;\n%s\n" "$1" "$2"; }
r() { grep '^R:' | sed 's/^R://' || true; }
ok() {  # label, got, want
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "  FAIL  $1 — got '$2', want '$3'"; fi
}
until_t() { local i; for i in $(seq 1 200); do [ "$(q -c "$1" 2>/dev/null || true)" = "t" ] && return 0; sleep 0.1; done; return 1; }
# is that connection waiting for a lock (an advisory lock by default; a row lock with "row")
waiting() {
  local ev="= 'advisory'"; [ "${2:-}" = row ] && ev="in ('transactionid', 'tuple')"
  echo "select exists (select 1 from pg_stat_activity where datname = '$DB' and application_name = '$1' and wait_event_type = 'Lock' and wait_event $ev)"
}
gate_close() {
  ( PGAPPNAME="gate-$1" psql -X -q -d "$DB" -c "select pg_advisory_lock(hashtextextended('conc39.$1', 0)); select pg_sleep(120);" >/dev/null 2>&1 || true ) &
  until_t "select exists (select 1 from pg_locks l join pg_stat_activity a using (pid) where a.datname = '$DB' and a.application_name = 'gate-$1' and l.locktype = 'advisory' and l.granted)" \
    || { echo "  FAIL  gate $1 could not be closed"; fail=$((fail + 1)); }
}
gate_open() { q -c "select pg_terminate_backend(pid) from pg_stat_activity where datname = '$DB' and application_name = 'gate-$1'" >/dev/null; }
gate_sql() { echo "select pg_advisory_xact_lock_shared(hashtextextended('conc39.$1', 0));"; }
start() { ( PGAPPNAME="$1" psql -X -q -At -d "$DB" -v ON_ERROR_STOP=1 -f "$TMP/$1.sql" > "$TMP/$1.out" 2>&1 || true ) & bg=$!; }
finish() {
  local p i; for p in "$@"; do for i in $(seq 1 300); do kill -0 "$p" 2>/dev/null || break; sleep 0.1; done; done
  for p in "$@"; do if kill -0 "$p" 2>/dev/null; then echo "  FAIL  a connection never finished"; fail=$((fail + 1)); kill "$p" 2>/dev/null || true; fi; done
  wait "$@" 2>/dev/null || true
}
outcome() { if grep -q 'ERROR' "$TMP/$1.out"; then grep -m1 -o 'ERROR:.*' "$TMP/$1.out"; else r < "$TMP/$1.out" | tail -1; fi; }
ver() { q -c "select version from public.purchase_orders where id = '$1'"; }
lines() { q -c "select jsonb_agg(jsonb_build_object('line_id', id, 'packs', $2)) from public.purchase_lines where po_id = '$1'"; }
# a transaction file for a manager's device: waits at gate $3 (before, or after with "after"), then runs $2
txn() {  # name, sql, gate, [after]
  if [ "${4:-}" = after ]; then
    printf "select test.login('cafe'); select test.session('%s'); select test.unlock('$ANA', '4826');\nbegin;\nset local role authenticated;\n%s\nreset role;\n%s\ncommit;\n" "$1" "$2" "$(gate_sql "$3")" > "$TMP/$1.sql"
  else
    printf "select test.login('cafe'); select test.session('%s'); select test.unlock('$ANA', '4826');\nbegin;\n%s\nset local role authenticated;\n%s\ncommit;\n" "$1" "$(gate_sql "$3")" "$2" > "$TMP/$1.sql"
  fi
}

# fixture (committed): two suppliers, milk and cheese, an order of 10 boxes and 4 blocks, a latte that uses both
q >/dev/null <<SQL
insert into public.vendors (id, name) values ('$V1', 'Lácteos C39'), ('$V2', 'Verduras C39');
insert into public.stock_items (id, name, unit, pack_qty, cost_per_pack, vendor_id) values ('$MILK', 'Leche C39', 'unit', 12, 12000, '$V1'),
                                                                                       ('$CHEESE', 'Queso C39', 'g', 2000, 7000, '$V1');
insert into public.menu_items (id, category_id, name, price_crc) values ('1b000000-0000-4000-8000-0000000c3901', 'a0000000-0000-4000-8000-000000000003', 'Latte C39', 2500);
insert into public.recipes (menu_item_id, stock_item_id, qty) values ('1b000000-0000-4000-8000-0000000c3901', '$MILK', 1), ('1b000000-0000-4000-8000-0000000c3901', '$CHEESE', 10);
SQL
VM="$(q -c "select id from public.vendor_items where item_id = '$MILK'")"; VC="$(q -c "select id from public.vendor_items where item_id = '$CHEESE'")"
mk() { mgr conc-m "select 'R:' || (public.proveedor_pedido_crear('$V1', '[{\"vendor_item_id\":\"$VM\",\"packs\":$2},{\"vendor_item_id\":\"$VC\",\"packs\":$3}]', null, '$1') ->> 'ok');" | q | r; }
ok "0) (two orders of milk and cheese)" "$(mk "$PO1" 10 4)$(mk "$PO2" 5 2)" "truetrue"

# 1) two devices, the same version, at the same moment ----------------------------------------------------------------
V="$(ver "$PO1")"; L="$(q -c "select jsonb_agg(jsonb_build_object('line_id', id, 'packs', packs / 2)) from public.purchase_lines where po_id = '$PO1'")"
gate_close g1
txn conc-a "select 'R:' || coalesce(public.proveedor_recibir('$PO1', '7e000000-0000-4000-8000-0000000c3901', $V, '$L') ->> 'error', 'ok');" g1; start conc-a; A=$bg
txn conc-b "select 'R:' || coalesce(public.proveedor_recibir('$PO1', '7e000000-0000-4000-8000-0000000c3902', $V, '$L') ->> 'error', 'ok');" g1; start conc-b; B=$bg
until_t "$(waiting conc-a)" && until_t "$(waiting conc-b)" || { echo "  FAIL  the two deliveries never met at the gate"; fail=$((fail + 1)); }
gate_open g1; finish "$A" "$B"
ok "1) two deliveries of one order at once with the same version: one booked, one «changed»" "$(printf '%s\n%s\n' "$(outcome conc-a)" "$(outcome conc-b)" | sort | tr '\n' ' ')" "changed ok "
ok "1) ... the stock rose once (half of each line: 5 boxes of 12, 2 blocks of 2 000 g)" "$(q -c "select string_agg(on_hand::text, ' ' order by name) from public.stock_items where id in ('$MILK', '$CHEESE')")" "60.0000 4000.0000"
ok "1) ... one delivery row, one move per item" "$(q -c "select (select count(*) from public.purchase_receipts where po_id = '$PO1') || ' ' || (select count(*) from public.stock_moves where po_id = '$PO1')")" "1 2"

# 2) the same payment request twice at once -------------------------------------------------------------------------------
PAY="{\"vendor_id\":\"$V1\",\"po_id\":\"$PO2\",\"amount\":10000,\"method\":\"card_debit\"}"
gate_close g2
for n in conc-p1 conc-p2; do
  txn "$n" "select 'R:' || coalesce(case when (public.proveedor_pago_registrar('$PAY', '5d000000-0000-4000-8000-0000000c3901', '$ANA', '4826') ->> 'repeat') = 'true' then 'repeat' end, 'ok');" g2
done
start conc-p1; P1=$bg; start conc-p2; P2=$bg
until_t "$(waiting conc-p1)" && until_t "$(waiting conc-p2)" || { echo "  FAIL  the two payments never met at the gate"; fail=$((fail + 1)); }
gate_open g2; finish "$P1" "$P2"
ok "2) the same payment request twice at once: one payment, the other «repeat»" "$(printf '%s\n%s\n' "$(outcome conc-p1)" "$(outcome conc-p2)" | sort | tr '\n' ' ')" "ok repeat "
ok "2) ... one row, one entry" "$(q -c "select (select count(*) from public.supplier_advances) || ' ' || (select count(*) from acct.entries where source_key like 'supadv:%')")" "1 1"

# 3) one SINPE confirmation, two suppliers, at once (the owner with the phone code: no PIN, a payment ahead allowed) -------
own() { printf "select test.login('owner', 'aal2');\nbegin;\n%s\nset local role authenticated;\n%s\ncommit;\n" "$(gate_sql "$2")" "$3" > "$TMP/$1.sql"; }
gate_close g3b
own conc-o1 g3b "select 'R:' || coalesce(public.proveedor_pago_registrar('{\"vendor_id\":\"$V1\",\"amount\":5000,\"method\":\"sinpe\",\"reference\":\"FT-C39-8888\",\"excess_ok\":true,\"excess_reason\":\"Prueba de concurrencia\"}', '5d000000-0000-4000-8000-0000000c3904') ->> 'error', 'ok');"
own conc-o2 g3b "select 'R:' || coalesce(public.proveedor_pago_registrar('{\"vendor_id\":\"$V2\",\"amount\":5000,\"method\":\"sinpe\",\"reference\":\"ft.c39.8888\",\"excess_ok\":true,\"excess_reason\":\"Prueba de concurrencia\"}', '5d000000-0000-4000-8000-0000000c3905') ->> 'error', 'ok');"
start conc-o1; O1=$bg; start conc-o2; O2=$bg
until_t "$(waiting conc-o1)" && until_t "$(waiting conc-o2)" || { echo "  FAIL  the owner's two payments never met at the gate"; fail=$((fail + 1)); }
gate_open g3b; finish "$O1" "$O2"
ok "3) the same SINPE confirmation (written two ways) for two suppliers at once: one payment, one «duplicate_reference»" \
   "$(printf '%s\n%s\n' "$(outcome conc-o1)" "$(outcome conc-o2)" | sort | tr '\n' ' ')" "duplicate_reference ok "
ok "3) ... one row with that confirmation" "$(q -c "select count(*) from public.supplier_advances where ref_key = 'ftc398888'")" "1"

# 4) a payment and a delivery of the same order, in both orders ---------------------------------------------------------------
V="$(ver "$PO2")"
gate_close g4
txn conc-r4 "select 'R:' || coalesce(public.proveedor_recibir('$PO2', '7e000000-0000-4000-8000-0000000c3904', $V, '$(lines "$PO2" 1)') ->> 'error', 'ok');" g4 after
start conc-r4; R4=$bg
until_t "$(waiting conc-r4)" || { echo "  FAIL  the delivery never reached its gate"; fail=$((fail + 1)); }
mgr conc-p4 "select 'R:' || coalesce(public.proveedor_pago_registrar('{\"vendor_id\":\"$V1\",\"po_id\":\"$PO2\",\"amount\":10000,\"method\":\"card_credit\"}', '5d000000-0000-4000-8000-0000000c3906', '$ANA', '4826') ->> 'error', 'ok');" > "$TMP/conc-p4.sql"
start conc-p4; P4=$bg
until_t "$(waiting conc-p4 row)" || { echo "  FAIL  the payment did not wait for the order held by the delivery"; fail=$((fail + 1)); }
gate_open g4; finish "$R4" "$P4"
ok "4) a delivery holding the order, then a payment of it: both finish" "$(outcome conc-r4) $(outcome conc-p4)" "ok ok"
V="$(ver "$PO2")"
gate_close g4b
txn conc-p4b "select 'R:' || coalesce(public.proveedor_pago_registrar('{\"vendor_id\":\"$V1\",\"po_id\":\"$PO2\",\"amount\":10000,\"method\":\"card_credit\",\"duplicate_ok\":true}', '5d000000-0000-4000-8000-0000000c3907', '$ANA', '4826') ->> 'error', 'ok');" g4b after
start conc-p4b; P4B=$bg
until_t "$(waiting conc-p4b)" || { echo "  FAIL  the payment never reached its gate"; fail=$((fail + 1)); }
mgr conc-r4b "select 'R:' || coalesce(public.proveedor_recibir('$PO2', '7e000000-0000-4000-8000-0000000c3905', $V, '$(lines "$PO2" 1)') ->> 'error', 'ok');" > "$TMP/conc-r4b.sql"
start conc-r4b; R4B=$bg
until_t "$(waiting conc-r4b row)" || { echo "  FAIL  the delivery did not wait for the order held by the payment"; fail=$((fail + 1)); }
gate_open g4b; finish "$P4B" "$R4B"
ok "4) a payment holding the order and its supplier, then a delivery: both finish, no deadlock" "$(outcome conc-p4b) $(outcome conc-r4b)" "ok ok"

# 5) a delivery and a sale of the same items, in both orders ---------------------------------------------------------------------
sale() { printf "select test.login('cafe'); select test.session('conc-pos');\nbegin;\nset local role authenticated;\nselect 'R:' || (public.pos_record_sale(jsonb_build_object('id', '%s', 'created_at', now(), 'total_crc', 2500, 'payment_method', 'cash_crc', 'paid', true, 'status', 'done', 'station', 'Caja C39', 'guest_name', 'C39', 'items', jsonb_build_array(jsonb_build_object('item_name', 'Latte C39', 'price_crc', 2500, 'qty', 1)))) ->> 'ok');\n%s\ncommit;\n" "$1" "${2:-}"; }
V="$(ver "$PO2")"
gate_close g5
sale 0c390000-0000-4000-8000-000000000001 "reset role; $(gate_sql g5)" > "$TMP/conc-sale.sql"; start conc-sale; SL=$bg
until_t "$(waiting conc-sale)" || { echo "  FAIL  the sale never reached its gate"; fail=$((fail + 1)); }
mgr conc-r5 "select 'R:' || coalesce(public.proveedor_recibir('$PO2', '7e000000-0000-4000-8000-0000000c3906', $V, '[{\"line_id\":\"$(q -c "select id from public.purchase_lines where po_id = '$PO2' and item_id = '$MILK'")\",\"packs\":1},{\"line_id\":\"$(q -c "select id from public.purchase_lines where po_id = '$PO2' and item_id = '$CHEESE'")\",\"packs\":0}]', null, false, null, null, true) ->> 'error', 'ok');" > "$TMP/conc-r5.sql"
start conc-r5; R5=$bg
until_t "$(waiting conc-r5 row)" || { echo "  FAIL  the delivery did not wait for the items held by the sale"; fail=$((fail + 1)); }
gate_open g5; finish "$SL" "$R5"
ok "5) a sale holding the items, then a delivery of them: both finish" "$(outcome conc-sale) $(outcome conc-r5)" "true ok"
V="$(ver "$PO2")"
gate_close g5b
txn conc-r5b "select 'R:' || coalesce(public.proveedor_recibir('$PO2', '7e000000-0000-4000-8000-0000000c3907', $V, '[{\"line_id\":\"$(q -c "select id from public.purchase_lines where po_id = '$PO2' and item_id = '$MILK'")\",\"packs\":1},{\"line_id\":\"$(q -c "select id from public.purchase_lines where po_id = '$PO2' and item_id = '$CHEESE'")\",\"packs\":1}]', null, false, null, null, true) ->> 'error', 'ok');" g5b after
start conc-r5b; R5B=$bg
until_t "$(waiting conc-r5b)" || { echo "  FAIL  the delivery never reached its gate"; fail=$((fail + 1)); }
sale 0c390000-0000-4000-8000-000000000002 > "$TMP/conc-sale2.sql"; start conc-sale2; SL2=$bg
until_t "$(waiting conc-sale2 row)" || { echo "  FAIL  the sale did not wait for the items held by the delivery"; fail=$((fail + 1)); }
gate_open g5b; finish "$R5B" "$SL2"
ok "5) a delivery holding the items, then a sale of them: both finish, no deadlock" "$(outcome conc-r5b) $(outcome conc-sale2)" "ok true"
ok "5) ... the stock as booked: every move counted once" \
   "$(q -c "select count(*) from public.stock_items s left join (select item_id, sum(qty) q from public.stock_moves group by 1) m on m.item_id = s.id where round(s.on_hand, 3) <> round(coalesce(m.q, 0), 3)")" "0"
ok "5) ... no deadlock anywhere" "$(grep -l 'deadlock' "$TMP"/*.out 2>/dev/null | wc -l | tr -d ' ')" "0"

# 6) an invoice and a correction of the same delivery, in both orders ------------------------------------------------------
PO3=9a000000-0000-4000-8000-0000000c3903; PO4=9a000000-0000-4000-8000-0000000c3904; PO5=9a000000-0000-4000-8000-0000000c3905
ok "6) (two more orders)" "$(mk "$PO3" 2 1)$(mk "$PO4" 2 1)$(mk "$PO5" 2 1)" "truetruetrue"
rest() { q -c "select jsonb_agg(jsonb_build_object('line_id', id, 'rest', true)) from public.purchase_lines where po_id = '$1'"; }
for P in "$PO3" "$PO4"; do
  N="${P: -1}"
  ok "6) (order $N received)" "$(mgr conc-m "select 'R:' || coalesce(public.proveedor_recibir('$P', '7e000000-0000-4000-8000-0000000c391$N', $(ver "$P"), '$(rest "$P")') ->> 'error', 'ok');" | q | r)" "ok"
done
ML3="$(q -c "select id from public.purchase_lines where po_id = '$PO3' and item_id = '$MILK'")"; ML4="$(q -c "select id from public.purchase_lines where po_id = '$PO4' and item_id = '$MILK'")"
inv() {  # name, receipt, invoice id, number, gate
  printf "select test.login('owner', 'aal2');\nbegin;\nset local role authenticated;\nselect 'R:' || coalesce(public.proveedor_factura_registrar('$V1', array['%s']::uuid[], '{\"number\":\"%s\",\"date\":\"%s\",\"net\":30000,\"iva\":3900}', '%s') ->> 'error', 'ok');\nreset role;\n%s\ncommit;\n" \
    "$2" "$4" "$(q -c "select public.cr_today()")" "$3" "${5:+$(gate_sql "$5")}" > "$TMP/$1.sql"
}
fix() {  # name, receipt, line, request id
  mgr "$1" "select 'R:' || coalesce(public.proveedor_recepcion_corregir('$2', '$4', '[{\"line_id\":\"$3\",\"packs_delta\":-1}]', 'Una caja venía vacía') ->> 'error', 'ok');"
}
gate_close g6
inv conc-i6 7e000000-0000-4000-8000-0000000c3913 5e000000-0000-4000-8000-0000000c3906 C39-F6 g6; start conc-i6; I6=$bg
until_t "$(waiting conc-i6)" || { echo "  FAIL  the invoice never reached its gate"; fail=$((fail + 1)); }
fix conc-f6 7e000000-0000-4000-8000-0000000c3913 "$ML3" 7e000000-0000-4000-8000-0000000c3923 > "$TMP/conc-f6.sql"; start conc-f6; F6=$bg
until_t "$(waiting conc-f6 row)" || { echo "  FAIL  the correction did not wait for the order held by the invoice"; fail=$((fail + 1)); }
gate_open g6; finish "$I6" "$F6"
ok "6) an invoice holding the delivery's order, then a correction of it: the invoice ok, the correction «invoiced»" "$(outcome conc-i6) $(outcome conc-f6)" "ok invoiced"
ok "6) ... no correction left outside the invoice" "$(q -c "select count(*) from public.purchase_receipts where po_id = '$PO3' and invoice_id is null")" "0"
gate_close g6b
printf "select test.login('cafe'); select test.session('conc-f6b'); select test.unlock('$ANA', '4826');\nbegin;\nset local role authenticated;\nselect 'R:' || coalesce(public.proveedor_recepcion_corregir('7e000000-0000-4000-8000-0000000c3914', '7e000000-0000-4000-8000-0000000c3924', '[{\"line_id\":\"$ML4\",\"packs_delta\":-1}]', 'Una caja venía vacía') ->> 'error', 'ok');\nreset role;\n%s\ncommit;\n" "$(gate_sql g6b)" > "$TMP/conc-f6b.sql"
start conc-f6b; F6B=$bg
until_t "$(waiting conc-f6b)" || { echo "  FAIL  the correction never reached its gate"; fail=$((fail + 1)); }
inv conc-i6b 7e000000-0000-4000-8000-0000000c3914 5e000000-0000-4000-8000-0000000c3907 C39-F6B; start conc-i6b; I6B=$bg
until_t "$(waiting conc-i6b row)" || { echo "  FAIL  the invoice did not wait for the order held by the correction"; fail=$((fail + 1)); }
gate_open g6b; finish "$F6B" "$I6B"
ok "6) a correction holding the order, then an invoice of that delivery: both ok" "$(outcome conc-f6b) $(outcome conc-i6b)" "ok ok"
ok "6) ... the correction went into the invoice with its delivery" \
   "$(q -c "select count(*) from public.purchase_receipts where po_id = '$PO4' and invoice_id = '5e000000-0000-4000-8000-0000000c3907'")" "2"

# 7) a delivery and a sale while a third connection holds the item: the delivery gives way («busy»), the sale goes through --
gate_close g7
printf "begin;\nselect 1 from public.stock_items where id = '$MILK' for update;\n%s\ncommit;\n" "$(gate_sql g7)" > "$TMP/conc-h7.sql"; start conc-h7; H7=$bg
until_t "$(waiting conc-h7)" || { echo "  FAIL  the holder never reached its gate"; fail=$((fail + 1)); }
mgr conc-r7 "select 'R:' || coalesce(public.proveedor_recibir('$PO5', '7e000000-0000-4000-8000-0000000c3917', $(ver "$PO5"), '$(rest "$PO5")') ->> 'error', 'ok');" > "$TMP/conc-r7.sql"
start conc-r7; R7=$bg; finish "$R7"
sale 0c390000-0000-4000-8000-000000000007 > "$TMP/conc-sale7.sql"; start conc-sale7; SL7=$bg
until_t "$(waiting conc-sale7 row)" || { echo "  FAIL  the sale did not wait for the item held"; fail=$((fail + 1)); }
gate_open g7; finish "$H7" "$SL7"
ok "7) the item held elsewhere: the delivery gives way at once («busy», nothing booked), the sale waits and goes through" "$(outcome conc-r7) $(outcome conc-sale7)" "busy true"
ok "7) ... the delivery booked nothing" "$(q -c "select count(*) from public.purchase_receipts where po_id = '$PO5'")" "0"
ok "7) ... and goes through when tried again" "$(mgr conc-m "select 'R:' || coalesce(public.proveedor_recibir('$PO5', '7e000000-0000-4000-8000-0000000c3917', $(ver "$PO5"), '$(rest "$PO5")') ->> 'error', 'ok');" | q | r)" "ok"
ok "7) ... the stock as booked, no deadlock anywhere" \
   "$(q -c "select count(*) from public.stock_items s left join (select item_id, sum(qty) q from public.stock_moves group by 1) m on m.item_id = s.id where round(s.on_hand, 3) <> round(coalesce(m.q, 0), 3)") $(grep -l 'deadlock' "$TMP"/*.out 2>/dev/null | wc -l | tr -d ' ')" "0 0"

# 8) Contabilidad's bank payment of the whole invoice and a Proveedores SINPE for its order, at once ---------------------------
V3=5b000000-0000-4000-8000-0000000c3908; PO6=9a000000-0000-4000-8000-0000000c3906; R8=7e000000-0000-4000-8000-0000000c3908; INV8=5e000000-0000-4000-8000-0000000c3908
q >/dev/null <<SQL
insert into public.vendors (id, name) values ('$V3', 'Panadería C39');
insert into public.vendor_items (id, vendor_id, item_id, pack_label, pack_qty, usual_price) values ('5c000000-0000-4000-8000-0000000c3908', '$V3', '$MILK', 'caja de 12', 12, 12000);
SQL
own1() { printf "select test.login('owner', 'aal2');\nset role authenticated;\n%s\n" "$1" | q | r; }   # the owner with the phone code, one call
ok "8) (an order of one box of milk from a third supplier, received)" \
   "$(mgr conc-m "select 'R:' || (public.proveedor_pedido_crear('$V3', '[{\"vendor_item_id\":\"5c000000-0000-4000-8000-0000000c3908\",\"packs\":1}]', null, '$PO6') ->> 'ok');" | q | r) $(mgr conc-m "select 'R:' || coalesce(public.proveedor_recibir('$PO6', '$R8', $(ver "$PO6"), '$(rest "$PO6")') ->> 'error', 'ok');" | q | r)" "true ok"
ok "8) (its invoice of ₡13 560 saved by SQL, as Contabilidad does: open in full, nothing applied, nothing paid)" \
   "$(own1 "select 'R:' || (public.supplier_invoice_save(jsonb_build_object('vendor_id', '$V3', 'number', 'C39-F8', 'date', public.cr_today(), 'net_crc', 12000, 'iva_crc', 1560, 'receipt_ids', jsonb_build_array('$R8')), '$INV8') ->> 'ok');") $(q -c "select public._invoice_open('$INV8') || ' ' || (select count(*) from public.supplier_payments where vendor_id = '$V3') || ' ' || (select count(*) from public.supplier_advances where vendor_id = '$V3')")" "true 13560.00 0 0"
gate_close g8
own conc-b8 g8 "select 'R:' || coalesce(public.supplier_payment_save(jsonb_build_object('vendor_id', '$V3', 'date', public.cr_today(), 'amount_crc', 13560, 'paid_from', 'bank', 'reference', 'BN C39-8', 'invoice_ids', jsonb_build_array('$INV8')), '5f000000-0000-4000-8000-0000000c3908') ->> 'error', 'ok');"
txn conc-s8 "select 'R:' || coalesce(public.proveedor_pago_registrar('{\"vendor_id\":\"$V3\",\"po_id\":\"$PO6\",\"amount\":13560,\"method\":\"sinpe\",\"reference\":\"FT-C39-0008\"}', '5d000000-0000-4000-8000-0000000c3908', '$ANA', '4826') ->> 'error', 'ok');" g8
start conc-b8; B8=$bg; start conc-s8; S8=$bg
until_t "$(waiting conc-b8)" && until_t "$(waiting conc-s8)" || { echo "  FAIL  the bank payment and the SINPE never met at the gate"; fail=$((fail + 1)); }
gate_open g8; finish "$B8" "$S8"
O8="$(outcome conc-b8) $(outcome conc-s8)"
case "$O8" in "ok over_balance"|"more_than_owed ok") N8="one pays, the other is refused";; *) N8="$O8";; esac
ok "8) Contabilidad's bank payment of the whole invoice and a Proveedores SINPE for its order at once: one pays, the other is refused («more than owed» / «over balance»), both finish" "$N8" "one pays, the other is refused"
ok "8) ... the invoice holds ₡13 560 of live allocations (its total), the supplier was paid ₡13 560 in all (never twice), nothing left to apply" \
   "$(q -c "select round((select coalesce(sum(a.amount_crc), 0) from public.supplier_payment_allocations a join public.supplier_payments p on p.id = a.payment_id where a.invoice_id = '$INV8' and p.voided_at is null), 2) || ' ' || round((select coalesce(sum(amount_crc), 0) from public.supplier_payments where vendor_id = '$V3' and voided_at is null and paid_from <> 'advance') + (select coalesce(sum(amount_crc), 0) from public.supplier_advances where vendor_id = '$V3' and voided_at is null), 2) || ' ' || (select total_crc from public.supplier_invoices where id = '$INV8') || ' ' || round((select coalesce(sum(public._prov_unapplied(id)), 0) from public.supplier_advances where vendor_id = '$V3'), 2)")" "13560.00 13560.00 13560.00 0.00"
ok "8) ... the ledger balanced, no deadlock anywhere" \
   "$(q -c "select count(*) from (select entry_id from acct.lines group by entry_id having sum(debit) <> sum(credit)) u") $(grep -l 'deadlock' "$TMP"/*.out 2>/dev/null | wc -l | tr -d ' ')" "0 0"

echo "concurrency-proveedores: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
