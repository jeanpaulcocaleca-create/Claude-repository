-- Migration 0040 (Proveedores, D-067): invoices and payments. A payment by SINPE (its confirmation number mandatory, one
-- transfer once across every supplier, formatting variants included) or by card (reference optional, a near duplicate
-- asked about) goes to 1160 «Anticipos a proveedores» first and is applied to invoices (Dr 2101 / Cr 1160) only by the
-- explicit calls; before or after receiving and the invoice, partial or full: Pendiente / Parcialmente pagado / Pagado.
-- More than the balance only at owner level with a reason. The published page's receive-and-pay still works while a
-- supplier has a payment not applied; its drawer payouts are documented by the invoice and counted as paid. Voids reverse
-- entries and delete nothing; the ledger stays balanced and ties out (2101, 1160). A payment never moves stock; with a
-- register open, receiving, paying, invoicing and correcting leave the register and its drawer movements as they were;
-- consistency-check.sql counts a correction or a payment that points at nothing.
begin;
insert into public.vendors (id, name, credit_days) values ('5b000000-0000-4000-8000-000000051401', 'Lácteos Monteverde', 15),
                                                          ('5b000000-0000-4000-8000-000000051402', 'Verduras del Valle', null);
insert into public.stock_items (id, name, unit, pack_qty, cost_per_pack) values ('5a000000-0000-4000-8000-000000051401', 'Leche', 'unit', 1, 1000);
insert into public.vendor_items (id, vendor_id, item_id, pack_label, pack_qty, usual_price) values
  ('5c000000-0000-4000-8000-000000051401', '5b000000-0000-4000-8000-000000051401', '5a000000-0000-4000-8000-000000051401', 'caja de 12', 12, 12000),
  ('5c000000-0000-4000-8000-000000051402', '5b000000-0000-4000-8000-000000051402', '5a000000-0000-4000-8000-000000051401', 'unidad', 1, 1000);
create function test.v514(o text) returns int language sql security definer as $$ select version from public.purchase_orders where id = o::uuid $$;
create function test.line514(o text) returns text language sql security definer as $$ select id::text from public.purchase_lines where po_id = o::uuid order by pos limit 1 $$;
create function test.money514(o text) returns jsonb language sql security definer as $$ select public._prov_dinero(o::uuid) $$;
create function test.st514(o text) returns text language sql security definer as $$
  select (m ->> 'status') || ' ' || (m ->> 'due') || ' ' || (m ->> 'paid') from public._prov_dinero(o::uuid) m $$;
-- an order of n boxes of milk, made and (when asked) received in full by Ana
create function test.order514(o text, n int, receive boolean) returns text language plpgsql as $$
begin
  perform public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051401', jsonb_build_array(jsonb_build_object('vendor_item_id', '5c000000-0000-4000-8000-000000051401', 'packs', n)),
                                        null, o::uuid);
  if receive then
    perform public.proveedor_recibir(o::uuid, gen_random_uuid(), test.v514(o), jsonb_build_array(jsonb_build_object('line_id', test.line514(o), 'rest', true)));
  end if;
  return (select status from public.purchase_orders where id = o::uuid);
end $$;
create function test.pay514(p jsonb, id uuid, pin text default '4826', who text default 'ana') returns jsonb language sql as $$
  select public.proveedor_pago_registrar(p, id, test.staff(who), pin) $$;
-- the stock as a whole: units on hand of every item, and how many stock moves there are
create function test.stock514() returns text language sql security definer as $$
  select (select coalesce(sum(on_hand), 0) from public.stock_items) || ' ' || (select count(*) from public.stock_moves) $$;
-- the books as a whole: the trial balance (debits − credits over every line) and 1160's balance minus the Proveedores
-- payments not applied yet; '0.00 0.00' when the ledger is balanced and 1160 holds exactly what is not applied
create function test.libros514() returns text language sql security definer as $$
  select round((select coalesce(sum(debit) - sum(credit), 0) from acct.lines), 2) || ' '
         || round((select coalesce(sum(debit - credit), 0) from acct.lines where account = '1160')
                  - (select coalesce(sum(public._prov_unapplied(id)), 0) from public.supplier_advances), 2) $$;
select code as exp_acct from acct.accounts where type = 'expense' and active and not cash and public._ap_target(code) order by code limit 1 \gset
select test.login('cafe'); select test.session('dev-514'); set role authenticated;
select test.eq(public.proveedor_pago_registrar('{"vendor_id":"5b000000-0000-4000-8000-000000051401","amount":1,"method":"card_debit"}', gen_random_uuid()) ->> 'error', 'locked',
               '0 a café device without the owner areas registers no payment');
select test.unlock(test.staff('ana'), '4826');
select test.eq(test.order514('9a000000-0000-4000-8000-000000051401', 10, false), 'sent', '0 (an order of 10 boxes: ₡120 000 without IVA)');

-- 1) a SINPE payment before anything arrives ---------------------------------------------------------------------------------
select test.eq(test.pay514('{"vendor_id":"5b000000-0000-4000-8000-000000051401","po_id":"9a000000-0000-4000-8000-000000051401","amount":135600,"method":"sinpe"}',
                 '5d000000-0000-4000-8000-000000051401') ->> 'error', 'needs_reference', '1 SINPE without its confirmation number is refused');
select test.eq(test.pay514('{"vendor_id":"5b000000-0000-4000-8000-000000051401","po_id":"9a000000-0000-4000-8000-000000051401","amount":135600,"method":"sinpe","reference":"ab1"}',
                 '5d000000-0000-4000-8000-000000051401') ->> 'error', 'bad_reference', '1 a confirmation of 4 to 40 letters and digits');
select test.eq(test.pay514('{"vendor_id":"5b000000-0000-4000-8000-000000051401","po_id":"9a000000-0000-4000-8000-000000051401","amount":135600,"method":"sinpe","reference":"--12345"}',
                 '5d000000-0000-4000-8000-000000051401') ->> 'error', 'bad_reference', '1 starting with a letter or a digit');
select test.eq(test.pay514('{"vendor_id":"5b000000-0000-4000-8000-000000051401","po_id":"9a000000-0000-4000-8000-000000051401","amount":135600,"method":"sinpe","reference":"2026-1105-8841"}',
                 '5d000000-0000-4000-8000-000000051401', '0000') ->> 'error', 'bad_pin', '1 the PIN of who registers it (a manager): a wrong one is refused');
reset role;
select test.eq((select failed_pins from public.staff where id = test.staff('ana')), 1, '1 and counted');
set role authenticated;
select test.stock514() as stock514a \gset
select test.pay514('{"vendor_id":"5b000000-0000-4000-8000-000000051401","po_id":"9a000000-0000-4000-8000-000000051401","amount":135600,"method":"sinpe","reference":" 2026-1105-8841 "}',
                   '5d000000-0000-4000-8000-000000051401') as p1 \gset
select test.eq((:'p1'::jsonb) ->> 'ok' || ' ' || ((:'p1'::jsonb) ->> 'applied_crc') || ' ' || ((:'p1'::jsonb) ->> 'unapplied_crc') || ' ' || ((:'p1'::jsonb) #>> '{money,status}')
               || ' ' || ((:'p1'::jsonb) #>> '{money,credit}'), 'true 0.00 135600.00 paid 0.00',
               '1 ₡135 600 (with IVA) before the goods: registered, nothing to apply yet; the order shows «Pagado», no credit (IVA allowance before the invoice)');
select test.eq(test.stock514(), :'stock514a', '1 a payment before the goods moves no stock: the units on hand and the stock moves are as they were');
select test.eq(test.pay514('{"vendor_id":"5b000000-0000-4000-8000-000000051401","amount":1,"method":"sinpe","reference":"x"}', '5d000000-0000-4000-8000-000000051401', '0000'),
               '{"ok":true,"repeat":true,"id":"5d000000-0000-4000-8000-000000051401"}'::jsonb, '1 the same request again (a lost answer) is a repeat, before any PIN');
select test.eq(test.pay514('{"vendor_id":"5b000000-0000-4000-8000-000000051402","amount":1000,"method":"sinpe","reference":"202611058841"}', '5d000000-0000-4000-8000-000000051402'),
               jsonb_build_object('ok', false, 'error', 'duplicate_reference', 'vendor_name', 'Lácteos Monteverde', 'date', public.cr_today(), 'amount', 135600.00),
               '1 the same confirmation written another way, for another supplier: «Ese número de SINPE ya está registrado» (who, when, how much)');
reset role;
select test.eq((select reference || ' ' || ref_key || ' ' || method || ' ' || (staff_id = test.staff('ana')) || ' ' || created_by from public.supplier_advances
                 where id = '5d000000-0000-4000-8000-000000051401'), '2026-1105-8841 202611058841 sinpe true Ana (manager)', '1 the payment: its reference, its key, who');
select test.eq((select string_agg(l.account || ':' || l.debit || ':' || l.credit, ' ' order by l.account) from acct.lines l join acct.entries e on e.id = l.entry_id
                 where e.source_key = 'supadv:5d000000-0000-4000-8000-000000051401'), '1110:0.00:135600.00 1160:135600.00:0.00',
               '1 one entry on the payment''s date: Dr 1160 «Anticipos a proveedores» / Cr 1110 Bancos');
-- a reference already used by a bank payment in Contabilidad (any supplier)
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.supplier_invoice_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000051402', 'number', 'V-1', 'date', public.cr_today(), 'net_crc', 5000,
                 'account', :'exp_acct'), '5e000000-0000-4000-8000-000000051409') ->> 'ok', 'true', '1 (Contabilidad saves invoice V-1 of the other supplier)');
select test.eq(public.supplier_payment_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000051402', 'date', public.cr_today(), 'amount_crc', 5000,
                 'paid_from', 'bank', 'reference', 'BN 7777.1234'), '5f000000-0000-4000-8000-000000051409') ->> 'ok', 'true', '1 (Contabilidad pays V-1 by bank, reference «BN 7777.1234»)');
select test.eq(public.proveedor_pago_registrar('{"vendor_id":"5b000000-0000-4000-8000-000000051401","amount":1000,"method":"sinpe","reference":"bn 7777 1234"}', gen_random_uuid()) ->> 'error',
               'duplicate_reference', '1 that transfer cannot be registered again as a SINPE in Proveedores');

-- 2) received, then the invoice: the payment is applied --------------------------------------------------------------------
select test.login('cafe'); select test.session('dev-514'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051401', '7e000000-0000-4000-8000-000000051401', test.v514('9a000000-0000-4000-8000-000000051401'),
                 jsonb_build_array(jsonb_build_object('line_id', test.line514('9a000000-0000-4000-8000-000000051401'), 'rest', true)), null, false, 'F-501') ->> 'status', 'received',
               '2 the 10 boxes arrive');
select test.eq(test.st514('9a000000-0000-4000-8000-000000051401'), 'paid 120000.00 135600.00', '2 still «Pagado» (the invoice, with its IVA, is missing)');
reset role;
select test.eq(public._prov_unapplied('5d000000-0000-4000-8000-000000051401'), 135600.00, '2 the payment waits for the order''s invoice');
set role authenticated;
select public.proveedor_factura_registrar('5b000000-0000-4000-8000-000000051401', array['7e000000-0000-4000-8000-000000051401']::uuid[],
         jsonb_build_object('date', public.cr_today(), 'net', 120000, 'iva', 15600), '5e000000-0000-4000-8000-000000051401') as f1 \gset
select test.eq((:'f1'::jsonb) - 'entry_id', '{"ok":true,"invoice_id":"5e000000-0000-4000-8000-000000051401","total_crc":135600.00,"payout_crc":0,"applied_crc":135600.00,"open_crc":0.00}'::jsonb,
               '2 the invoice (number from the delivery) is registered and the payment applied: nothing open');
select test.eq(public.proveedor_factura_registrar('5b000000-0000-4000-8000-000000051401', array['7e000000-0000-4000-8000-000000051401']::uuid[], '{}',
                 '5e000000-0000-4000-8000-000000051401'), '{"ok":true,"repeat":true,"invoice_id":"5e000000-0000-4000-8000-000000051401"}'::jsonb,
               '2 the same request again: a repeat (before checking the deliveries)');
reset role;
select test.eq((select number || ' ' || due_date || ' ' || received_crc from public.supplier_invoices where id = '5e000000-0000-4000-8000-000000051401'),
               'F-501 ' || (public.cr_today() + 15) || ' 120000.00', '2 F-501, due in the supplier''s 15 credit days, against the ₡120 000 received');
select test.eq((select paid_from || ' ' || method || ' ' || reference || ' ' || amount_crc || ' ' || (advance_id = '5d000000-0000-4000-8000-000000051401') || ' ' || (po_id = '9a000000-0000-4000-8000-000000051401')
                  from public.supplier_payments where advance_id is not null), 'advance sinpe SINPE 2026-1105-8841 135600.00 true true',
               '2 the application: a supplier payment «advance» every existing read sees (Contabilidad, ap_aging, po_pending)');
select test.eq((select string_agg(l.account || ':' || l.debit || ':' || l.credit, ' ' order by l.account) from acct.lines l join acct.entries e on e.id = l.entry_id
                 join public.supplier_payments p on e.source_key = 'suppay:' || p.id where p.advance_id = '5d000000-0000-4000-8000-000000051401'),
               '1160:0.00:135600.00 2101:135600.00:0.00', '2 its entry: Dr 2101 / Cr 1160');
select test.eq((select invoice_status from public.purchase_receipts where id = '7e000000-0000-4000-8000-000000051401'), 'confirmed', '2 the delivery is invoiced');
select test.eq(test.st514('9a000000-0000-4000-8000-000000051401'), 'paid 135600.00 135600.00', '2 the order: due ₡135 600, paid ₡135 600');

-- 3) after the invoice: partial, then full, by card ------------------------------------------------------------------------
set role authenticated;
select test.eq(test.order514('9a000000-0000-4000-8000-000000051402', 5, true), 'received', '3 (5 boxes received: ₡60 000)');
select test.eq(public.proveedor_factura_registrar('5b000000-0000-4000-8000-000000051401', array['7e000000-0000-4000-8000-000000051401']::uuid[],
                 jsonb_build_object('date', public.cr_today(), 'net', 1), gen_random_uuid()) ->> 'error', 'bad_receipts', '3 a delivery already invoiced is refused');
select public.proveedor_factura_registrar('5b000000-0000-4000-8000-000000051401',
         array(select id from public.purchase_receipts where po_id = '9a000000-0000-4000-8000-000000051402'),
         jsonb_build_object('number', 'F-502', 'date', public.cr_today(), 'net', 60000, 'iva', 7800), '5e000000-0000-4000-8000-000000051402') as f2 \gset
select test.eq((:'f2'::jsonb) ->> 'open_crc' || ' ' || test.st514('9a000000-0000-4000-8000-000000051402'), '67800.00 pending 67800.00 0.00', '3 invoiced, nothing paid: «Pago pendiente»');
select test.stock514() as stock514b \gset
select test.eq(test.pay514('{"vendor_id":"5b000000-0000-4000-8000-000000051401","po_id":"9a000000-0000-4000-8000-000000051402","amount":10000,"method":"card_debit"}',
                 '5d000000-0000-4000-8000-000000051403') ->> 'applied_crc', '10000.00', '3 ₡10 000 by debit card (no reference): applied at once to its invoice');
select test.eq(test.st514('9a000000-0000-4000-8000-000000051402'), 'partial 67800.00 10000.00', '3 «Parcialmente pagado»');
select test.eq(test.pay514('{"vendor_id":"5b000000-0000-4000-8000-000000051401","po_id":"9a000000-0000-4000-8000-000000051402","amount":10000,"method":"card_debit"}',
                 '5d000000-0000-4000-8000-000000051404') ->> 'error', 'possible_duplicate', '3 the same card payment again a moment later: «¿Es otro pago distinto?»');
select test.eq(test.pay514('{"vendor_id":"5b000000-0000-4000-8000-000000051401","po_id":"9a000000-0000-4000-8000-000000051402","amount":10000,"method":"card_debit","duplicate_ok":true}',
                 '5d000000-0000-4000-8000-000000051404') ->> 'ok', 'true', '3 yes, another one');
select test.eq(test.pay514('{"vendor_id":"5b000000-0000-4000-8000-000000051401","po_id":"9a000000-0000-4000-8000-000000051402","amount":47800,"method":"card_credit","reference":"VISA 4417"}',
                 '5d000000-0000-4000-8000-000000051405') #>> '{money,status}', 'paid', '3 the rest by credit card: «Pagado»');
select test.eq(test.stock514(), :'stock514b', '3 card payments after the goods move no stock either (units on hand, stock moves)');
reset role;
select test.eq((select string_agg(l.account || ':' || l.credit, ' ') from acct.lines l join acct.entries e on e.id = l.entry_id
                 where e.source_key = 'supadv:5d000000-0000-4000-8000-000000051405' and l.credit > 0), '2160:47800.00', '3 a credit card payment is owed to the card (2160)');
select test.eq(public._invoice_open('5e000000-0000-4000-8000-000000051402'), 0.00, '3 F-502 paid');

-- 4) amounts, dates, methods; more than owed ------------------------------------------------------------------------------
set role authenticated;
select test.eq(test.pay514('{"vendor_id":"5b000000-0000-4000-8000-000000051401","amount":0,"method":"card_debit"}', gen_random_uuid()) ->> 'error', 'bad_amount', '4 an amount above 0');
select test.eq(test.pay514('{"vendor_id":"5b000000-0000-4000-8000-000000051401","amount":10.555,"method":"card_debit"}', gen_random_uuid()) ->> 'error', 'bad_amount', '4 at most 2 decimals');
select test.eq(test.pay514('{"vendor_id":"5b000000-0000-4000-8000-000000051401","amount":"100","method":"card_debit"}', gen_random_uuid()) ->> 'error', 'bad_request', '4 a number only as a number');
select test.eq(test.pay514('{"vendor_id":"5b000000-0000-4000-8000-000000051401","amount":100,"method":"cash"}', gen_random_uuid()) ->> 'error', 'bad_request', '4 SINPE or card only');
select test.eq(test.pay514(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000051401', 'amount', 100, 'method', 'card_debit', 'date', public.cr_today() + 1), gen_random_uuid()) ->> 'error',
               'future_date', '4 not dated in the future');
select test.eq(test.pay514(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000051401', 'amount', 100, 'method', 'card_debit', 'date', public.cr_today() - 367), gen_random_uuid()) ->> 'error',
               'bad_date', '4 nor more than a year back');
select test.eq(test.order514('9a000000-0000-4000-8000-000000051403', 1, false), 'sent', '4 (an order of one box: ₡12 000, ₡13 560 with IVA)');
select test.pay514('{"vendor_id":"5b000000-0000-4000-8000-000000051401","po_id":"9a000000-0000-4000-8000-000000051403","amount":20000,"method":"card_debit"}', gen_random_uuid()) as ob \gset
select test.eq((:'ob'::jsonb), '{"ok":false,"error":"over_balance","saldo":13560.00}'::jsonb, '4 more than the order''s balance: refused, with the balance');
select test.eq(test.pay514('{"vendor_id":"5b000000-0000-4000-8000-000000051401","po_id":"9a000000-0000-4000-8000-000000051403","amount":20000,"method":"card_debit","excess_ok":true,"excess_reason":"x"}',
                 gen_random_uuid()) ->> 'error', 'needs_reason', '4 «Es un pago de más» needs a reason');
select test.eq(test.pay514('{"vendor_id":"5b000000-0000-4000-8000-000000051401","po_id":"9a000000-0000-4000-8000-000000051403","amount":20000,"method":"card_debit","excess_ok":true,"excess_reason":"Adelanto de la semana"}',
                 gen_random_uuid()) ->> 'error', 'needs_owner', '4 and the owner level: a manager cannot');
select test.login('cafe'); select test.session('dev-514-d'); select test.unlock(test.staff('dueno'), '7391'); set role authenticated;
select test.eq(test.pay514('{"vendor_id":"5b000000-0000-4000-8000-000000051401","po_id":"9a000000-0000-4000-8000-000000051403","amount":20000,"method":"card_debit","excess_ok":true,"excess_reason":"Adelanto de la semana"}',
                 '5d000000-0000-4000-8000-000000051406', '4826', 'ana') ->> 'error', 'needs_owner', '4 the owner''s unlock with a manager''s PIN in the call: still not');
select test.eq(test.pay514('{"vendor_id":"5b000000-0000-4000-8000-000000051401","po_id":"9a000000-0000-4000-8000-000000051403","amount":20000,"method":"card_debit","excess_ok":true,"excess_reason":"Adelanto de la semana"}',
                 '5d000000-0000-4000-8000-000000051406', '7391', 'dueno') ->> 'ok', 'true', '4 the owner level with the owner''s PIN: allowed');
reset role;
select test.eq((select excess_reason from public.supplier_advances where id = '5d000000-0000-4000-8000-000000051406'), 'Adelanto de la semana', '4 with its reason');
select test.eq((test.money514('9a000000-0000-4000-8000-000000051403') ->> 'credit')::numeric, 20000 - 13560::numeric, '4 the order shows the money beyond the balance as «Saldo a favor»');
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.proveedor_pago_registrar('{"vendor_id":"5b000000-0000-4000-8000-000000051402","amount":20000,"method":"sinpe","reference":"FT-99887766","excess_ok":true,"excess_reason":"Prepago del mes"}',
                 '5d000000-0000-4000-8000-000000051407') ->> 'ok', 'true', '4 the owner with the phone code needs no PIN (a payment ahead for the other supplier, no order)');

-- 5) applied only by the explicit calls ---------------------------------------------------------------------------------------
-- Contabilidad saves an invoice of the second supplier (no deliveries): the payment ahead is NOT applied by itself
select test.eq(public.supplier_invoice_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000051402', 'number', 'V-2', 'date', public.cr_today(), 'net_crc', 15000,
                 'account', :'exp_acct'),
                 '5e000000-0000-4000-8000-000000051403') ->> 'ok', 'true', '5 (Contabilidad saves invoice V-2 of ₡15 000)');
reset role;
select test.eq(public._invoice_open('5e000000-0000-4000-8000-000000051403'), 15000.00, '5 it stays open: no trigger applies a payment to it');
set role authenticated;
select public.proveedor_anticipos_aplicar('5b000000-0000-4000-8000-000000051402') as ap \gset
reset role;
select test.eq((:'ap'::jsonb) ->> 'applied_crc' || ' ' || public._invoice_open('5e000000-0000-4000-8000-000000051403'), '15000.00 0.00',
               '5 «Aplicar a facturas abiertas» applies it');
select test.eq(public._prov_unapplied('5d000000-0000-4000-8000-000000051407'), 5000.00, '5 ₡5 000 stays as credit');
-- the published page's receive-and-pay while the supplier has a payment not applied (₡6 440 of the order above)
select test.login('cafe'); select test.session('dev-514'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
insert into public.purchase_orders (id, vendor_id, status) values ('9a000000-0000-4000-8000-000000051404', '5b000000-0000-4000-8000-000000051401', 'sent'),
                                                                 ('9a000000-0000-4000-8000-000000051405', '5b000000-0000-4000-8000-000000051401', 'sent');
insert into public.purchase_lines (id, po_id, item_id, packs, qty, unit_cost) values
  ('9b000000-0000-4000-8000-000000051404', '9a000000-0000-4000-8000-000000051404', '5a000000-0000-4000-8000-000000051401', 2, 24, 1000),
  ('9b000000-0000-4000-8000-000000051405', '9a000000-0000-4000-8000-000000051405', '5a000000-0000-4000-8000-000000051401', 1, 12, 1000);
select public.po_receive_and_settle('9a000000-0000-4000-8000-000000051404', '[{"line_id":"9b000000-0000-4000-8000-000000051404","qty":24}]', '7e000000-0000-4000-8000-000000051404', false,
         jsonb_build_object('mode', 'confirm', 'number', 'F-504', 'date', public.cr_today(), 'currency', 'CRC', 'net', 24000, 'iva', 3120),
         '[{"method":"bank","amount_crc":27120,"reference":"BN 555"}]', test.staff('ana'), '4826') as old1 \gset
select test.eq((:'old1'::jsonb) ->> 'ok' || ' ' || ((:'old1'::jsonb) ->> 'paid_crc') || ' ' || ((:'old1'::jsonb) ->> 'open_crc'), 'true 27120.00 0.00',
               '5 the published page receives, invoices and pays in one call as before (the payment not applied does not get in the way)');
reset role;
select test.eq(public._prov_unapplied('5d000000-0000-4000-8000-000000051406'), 20000.00, '5 and the Proveedores payment is still not applied');

-- 6) the published page's drawer payout, documented by the invoice ------------------------------------------------------------
select test.login('cafe'); select test.session('dev-514'); set role authenticated;
select test.eq(public.register_open(test.staff('ana'), '4826', 50000, 0) ->> 'ok', 'true', '6 (the register opens)');
select test.unlock(test.staff('ana'), '4826');
select test.eq(public.po_receive_and_settle('9a000000-0000-4000-8000-000000051405', '[{"line_id":"9b000000-0000-4000-8000-000000051405","qty":12}]', '7e000000-0000-4000-8000-000000051405', false,
                 '{"mode":"pending"}', '[{"method":"register","amount_crc":13560}]', test.staff('ana'), '4826') ->> 'invoice_status', 'pending',
               '6 the published page: received and paid ₡13 560 from the drawer, the invoice to come');
select test.eq(test.st514('9a000000-0000-4000-8000-000000051405'), 'paid 12000.00 13560.00', '6 Proveedores counts that drawer money as paid («Pagado en efectivo de la caja · falta la factura»)');
select test.eq((test.money514('9a000000-0000-4000-8000-000000051405') ->> 'payout_crc')::numeric, 13560.00, '6 shown as the payout');
select test.eq(public.proveedor_factura_registrar('5b000000-0000-4000-8000-000000051401', array['7e000000-0000-4000-8000-000000051405']::uuid[],
                 jsonb_build_object('date', public.cr_today(), 'net', 10000), gen_random_uuid()),
               '{"ok":false,"error":"payout_exceeds","payout_crc":13560.00,"total_crc":10000.00}'::jsonb, '6 an invoice smaller than the drawer payout is refused');
select public.proveedor_factura_registrar('5b000000-0000-4000-8000-000000051401', array['7e000000-0000-4000-8000-000000051405']::uuid[],
         jsonb_build_object('date', public.cr_today(), 'net', 12000, 'iva', 1560), '5e000000-0000-4000-8000-000000051405') as f5 \gset
select test.eq((:'f5'::jsonb) ->> 'payout_crc' || ' ' || ((:'f5'::jsonb) ->> 'open_crc') || ' ' || test.st514('9a000000-0000-4000-8000-000000051405'),
               '13560.00 0.00 paid 13560.00 13560.00', '6 the invoice documents the payout: nothing open, «Pagado»');
reset role;
select test.eq((select p.paid_from || ' ' || p.amount_crc || ' ' || (p.payout_id = (select payout_id from public.purchase_receipts where id = '7e000000-0000-4000-8000-000000051405'))
                  from public.supplier_payments p join public.supplier_payment_allocations a on a.payment_id = p.id where a.invoice_id = '5e000000-0000-4000-8000-000000051405'),
               'payout 13560.00 true', '6 documented as the drawer payout (0029''s way), so 1104 is cleared');
select test.eq((select number from public.supplier_invoices where id = '5e000000-0000-4000-8000-000000051405') ~ '^S/N-\d{8}-5e000000$', true,
               '6 an invoice without a number gets «S/N-<fecha>-…»');
select test.eq((select invoice_no from public.purchase_receipts where id = '7e000000-0000-4000-8000-000000051405') = (select number from public.supplier_invoices where id = '5e000000-0000-4000-8000-000000051405'),
               true, '6 written on the delivery');
-- «No modificar cajas abiertas»: with today's register open, an employee's delivery, a SINPE and a card payment, the
-- invoice and a correction leave the register's day and every drawer movement exactly as they were
select test.eq((select count(*)::int from public.register_days where business_date = public.cr_today() and closed_at is null), 1, '6 (today''s register is open)');
select (select md5(r::text) from public.register_days r where r.business_date = public.cr_today()) as reg514,
       (select count(*) || ':' || md5(coalesce(string_agg(c::text, '|' order by c.id), '')) from public.cash_movements c) as cash514 \gset
select test.login('cafe'); select test.session('dev-514'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select test.eq(test.order514('9a000000-0000-4000-8000-000000051461', 3, false), 'sent', '6 (an order of 3 boxes: ₡36 000)');
select test.turno(test.staff('luis'), '5284', 'Bodega') as tok514 \gset
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051461', '7e000000-0000-4000-8000-000000051461', test.v514('9a000000-0000-4000-8000-000000051461'),
                 jsonb_build_array(jsonb_build_object('line_id', test.line514('9a000000-0000-4000-8000-000000051461'), 'packs', 3)), :'tok514') ->> 'status', 'received',
               '6 Luis, on shift, receives the 3 boxes');
select test.eq(test.pay514('{"vendor_id":"5b000000-0000-4000-8000-000000051401","po_id":"9a000000-0000-4000-8000-000000051461","amount":20000,"method":"sinpe","reference":"FT-51466001"}',
                 '5d000000-0000-4000-8000-000000051461') ->> 'unapplied_crc', '20000.00', '6 ₡20 000 by SINPE (waits for the invoice)');
select test.eq(test.pay514('{"vendor_id":"5b000000-0000-4000-8000-000000051401","po_id":"9a000000-0000-4000-8000-000000051461","amount":7120,"method":"card_debit","reference":"VISA 6602"}',
                 '5d000000-0000-4000-8000-000000051462') ->> 'unapplied_crc', '7120.00', '6 ₡7 120 by debit card');
select test.eq(public.proveedor_recepcion_corregir('7e000000-0000-4000-8000-000000051461', '7e000000-0000-4000-8000-000000051462',
                 jsonb_build_array(jsonb_build_object('line_id', test.line514('9a000000-0000-4000-8000-000000051461'), 'packs_delta', -1)), 'Eran 2 cajas, no 3') ->> 'status',
               'partially_received', '6 a correction: 2 boxes came, not 3');
select public.proveedor_factura_registrar('5b000000-0000-4000-8000-000000051401', array['7e000000-0000-4000-8000-000000051461']::uuid[],
         jsonb_build_object('number', 'F-561', 'date', public.cr_today(), 'net', 24000, 'iva', 3120), '5e000000-0000-4000-8000-000000051461') as f61 \gset
select test.eq((:'f61'::jsonb) ->> 'total_crc' || ' ' || ((:'f61'::jsonb) ->> 'applied_crc') || ' ' || ((:'f61'::jsonb) ->> 'open_crc'), '27120.00 27120.00 0.00',
               '6 the invoice of the 2 boxes (the correction with it) takes both payments');
reset role;
select test.eq((select count(*)::int from public.purchase_receipts where po_id = '9a000000-0000-4000-8000-000000051461') || ' '
               || (select count(*) from public.supplier_advances where id in ('5d000000-0000-4000-8000-000000051461', '5d000000-0000-4000-8000-000000051462')),
               '2 2', '6 (the delivery, its correction and the two payments are recorded)');
select test.eq((select md5(r::text) from public.register_days r where r.business_date = public.cr_today()), :'reg514',
               '6 «No modificar cajas abiertas»: today''s register row is exactly as it was');
select test.eq((select count(*) || ':' || md5(coalesce(string_agg(c::text, '|' order by c.id), '')) from public.cash_movements c), :'cash514',
               '6 and so is every drawer movement (amounts, voids, everything)');
select test.eq((select count(*)::int from public.register_days where business_date = public.cr_today() and closed_at is null), 1, '6 the register is still open');

-- 7) a dollar invoice -----------------------------------------------------------------------------------------------------------
select test.login('cafe'); select test.session('dev-514'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select test.eq(test.order514('9a000000-0000-4000-8000-000000051406', 4, true), 'received', '7 (4 boxes received: ₡48 000)');
select test.eq(public.proveedor_factura_registrar('5b000000-0000-4000-8000-000000051401', array(select id from public.purchase_receipts where po_id = '9a000000-0000-4000-8000-000000051406'),
                 jsonb_build_object('date', public.cr_today(), 'currency', 'USD', 'fx_rate', 50, 'net', 96), gen_random_uuid()) ->> 'error', 'bad_rate', '7 a dollar rate between 100 and 2000');
select test.eq(public.proveedor_factura_registrar('5b000000-0000-4000-8000-000000051401', array(select id from public.purchase_receipts where po_id = '9a000000-0000-4000-8000-000000051406'),
                 jsonb_build_object('number', 'US-7', 'date', public.cr_today(), 'currency', 'USD', 'fx_rate', 500, 'net', 96, 'iva', 12.48), '5e000000-0000-4000-8000-000000051406') ->> 'total_crc',
               '54240.00', '7 US$ 108.48 at 500: ₡54 240');
reset role;
select test.eq((select currency || ' ' || fx_rate || ' ' || net_fx || ' ' || iva_fx || ' ' || net_crc || ' ' || iva_crc from public.supplier_invoices where id = '5e000000-0000-4000-8000-000000051406'),
               'USD 500.00 96.00 12.48 48000.00 6240.00', '7 kept in dollars and in colones');

-- 8) voids: entries reversed, nothing deleted ----------------------------------------------------------------------------------
create temp table rows514 as select (select count(*) from public.supplier_payments) as sp, (select count(*) from public.supplier_advances) as sa,
                                    (select count(*) from public.supplier_payment_allocations) as al, (select count(*) from public.supplier_invoices) as si;
select test.login('cafe'); select test.session('dev-514'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select test.eq(public.proveedor_pago_anular('5d000000-0000-4000-8000-000000051401', 'Se registró en el pedido equivocado') ->> 'error', 'locked', '8 a manager cannot void a payment');
select test.login('cafe'); select test.session('dev-514-d'); select test.unlock(test.staff('dueno'), '7391'); set role authenticated;
select test.eq(public.proveedor_pago_anular('5d000000-0000-4000-8000-000000051401', 'Se registró en el pedido equivocado', test.staff('ana'), '4826') ->> 'error', 'not_owner',
               '8 the owner level with a manager''s PIN: not an owner');
select test.eq(public.proveedor_pago_anular('5d000000-0000-4000-8000-000000051401', 'mal', test.staff('dueno'), '7391') ->> 'error', 'needs_reason', '8 a reason of 5 or more');
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.proveedor_pago_anular('5d000000-0000-4000-8000-000000051401', 'Se registró en el pedido equivocado'), '{"ok":true}'::jsonb, '8 the accountant voids the SINPE payment');
select test.eq(public.proveedor_pago_anular('5d000000-0000-4000-8000-000000051401', 'Se registró en el pedido equivocado'), '{"ok":true,"repeat":true}'::jsonb, '8 twice: nothing more');
reset role;
select test.eq(public._invoice_open('5e000000-0000-4000-8000-000000051401') || ' ' || test.st514('9a000000-0000-4000-8000-000000051401'), '135600.00 pending 135600.00 0.00',
               '8 F-501 is open again, the order «Pago pendiente»');
select test.eq((select count(*)::int from acct.entries e where e.source = 'reversal' and e.reverses in (select entry_id from public.supplier_payments where advance_id = '5d000000-0000-4000-8000-000000051401')
                  ) || ' ' || (select count(*) from acct.entries e where e.reverses = (select entry_id from public.supplier_advances where id = '5d000000-0000-4000-8000-000000051401')),
               '1 1', '8 its application and its payment entry are reversed');
select test.eq((select voided_by || ' ' || void_reason from public.supplier_advances where id = '5d000000-0000-4000-8000-000000051401'),
               'contador · contador@test.local Se registró en el pedido equivocado', '8 who and why');
select test.login('cafe'); select test.session('dev-514'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select test.eq(public.proveedor_anticipos_aplicar('5b000000-0000-4000-8000-000000051401') ->> 'applied_crc', '0',
               '8 «Aplicar» now: the payment ahead for the order of one box waits for that order (still open), never F-501 meanwhile');
select test.eq(public.proveedor_pedido_cancelar('9a000000-0000-4000-8000-000000051403', test.v514('9a000000-0000-4000-8000-000000051403'), 'No hacía falta') ->> 'status', 'cancelled',
               '8 (that order is cancelled: nothing of it will be invoiced)');
select test.eq(public.proveedor_anticipos_aplicar('5b000000-0000-4000-8000-000000051401') ->> 'applied_crc', '20000.00',
               '8 then «Aplicar» takes the payment to the supplier''s other open invoice, the oldest first');
reset role;
select test.eq(public._invoice_open('5e000000-0000-4000-8000-000000051401'), 115600.00, '8 F-501: 135 600 − 20 000');
select test.login('cafe'); select test.session('dev-514'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
reset role;
-- the accountant voids F-502 (paid by the three card payments): their applications first, the payments become credit
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.proveedor_factura_anular('5e000000-0000-4000-8000-000000051402', 'Factura con el monto equivocado'), '{"ok":true}'::jsonb, '8 the accountant voids F-502');
reset role;
select test.eq((select voided_at is not null from public.supplier_invoices where id = '5e000000-0000-4000-8000-000000051402')
               || ' ' || (select invoice_status from public.purchase_receipts where po_id = '9a000000-0000-4000-8000-000000051402'), 'true review', '8 voided, its delivery back to «por revisar»');
select test.eq((select sum(public._prov_unapplied(id)) from public.supplier_advances where id in ('5d000000-0000-4000-8000-000000051403', '5d000000-0000-4000-8000-000000051404', '5d000000-0000-4000-8000-000000051405')),
               67800.00, '8 the three card payments are credit again');
select test.login('cafe'); select test.session('dev-514'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select public.proveedor_factura_registrar('5b000000-0000-4000-8000-000000051401', array(select id from public.purchase_receipts where po_id = '9a000000-0000-4000-8000-000000051402'),
         jsonb_build_object('number', 'F-502B', 'date', public.cr_today(), 'net', 60000, 'iva', 7800), '5e000000-0000-4000-8000-000000051407') as f6 \gset
select test.eq((:'f6'::jsonb) ->> 'applied_crc' || ' ' || ((:'f6'::jsonb) ->> 'open_crc'), '67800.00 0.00', '8 the corrected invoice takes them (never again the voided one)');
reset role;
select test.eq((select count(*)::int from public.supplier_payment_allocations a join public.supplier_payments p on p.id = a.payment_id
                 where a.invoice_id = '5e000000-0000-4000-8000-000000051402' and p.voided_at is null), 0, '8 nothing live on the voided invoice');
select test.ok((select count(*) from public.supplier_payments) >= (select sp from rows514) and (select count(*) from public.supplier_advances) = (select sa from rows514)
               and (select count(*) from public.supplier_payment_allocations) >= (select al from rows514) and (select count(*) from public.supplier_invoices) >= (select si from rows514),
               '8 no payment, allocation, invoice or payment row was deleted');

-- 9) the books: balanced, accounts payable ties out, 1160 = what is not applied --------------------------------------------------
select acct.post_day(public.cr_today(), 'prueba') ->> 'ok' as pd \gset
select test.eq(:'pd'::text, 'true', '9 (the day''s receipts posted, as the register close does)');
select test.eq((select count(*)::int from (select entry_id from acct.lines group by entry_id having sum(debit) <> sum(credit)) u), 0, '9 every entry balanced');
select test.login('owner', 'aal2'); set role authenticated;
select public.ap_aging() -> 'ledger' as led \gset
reset role;
select test.eq(((:'led'::jsonb) ->> 'ap_balance')::numeric,
               ((:'led'::jsonb) ->> 'invoices_open')::numeric + ((:'led'::jsonb) ->> 'received_not_invoiced')::numeric + ((:'led'::jsonb) ->> 'expenses_on_credit')::numeric,
               '9 ap_aging: 2101 = open invoices + received not invoiced + credit expenses');
select test.eq((select coalesce(sum(l.debit - l.credit), 0) from acct.lines l join acct.entries e on e.id = l.entry_id
                 where l.account = '1160' and (e.source_key like 'supadv:%' or e.source_key like 'suppay:%'
                        or e.reverses in (select x.id from acct.entries x where x.source_key like 'supadv:%' or x.source_key like 'suppay:%'))),
               (select coalesce(sum(public._prov_unapplied(id)), 0) from public.supplier_advances),
               '9 1160''s Proveedores movements = the payments not applied yet');
select test.eq((select name || ' · ' || type || ' · ' || active || ' · ' || cash from acct.accounts where code = '1160'), 'Anticipos a proveedores · asset · true · false',
               '9 1160 is an active asset account, «Anticipos a proveedores», not a cash account');
select test.eq((select string_agg(key, ' ' order by key) from acct.mappings where account = '1160'), 'from_advance supplier_advance',
               '9 the two 0040 mappings point at it (a payment in Proveedores, an invoice paid with one)');
select test.login('owner', 'aal2'); set role authenticated;
select public.ap_aging() -> 'accounts' as agacc \gset
reset role;
select test.eq((select count(*)::int from jsonb_array_elements(:'agacc'::jsonb) x where x ->> 'code' = '1160') || ' of ' || jsonb_array_length(:'agacc'::jsonb), '0 of ' || jsonb_array_length(:'agacc'::jsonb),
               '9 1160 is not among the accounts ap_aging offers for an invoice without deliveries (an automatic account, never a target)');
select test.ok(jsonb_array_length(:'agacc'::jsonb) > 0, '9 (that list is not empty)');
select test.eq(test.libros514(), '0.00 0.00', '9 the trial balance ties (debits = credits over every line) and 1160''s balance = the Proveedores payments not applied');
\pset format unaligned
\pset tuples_only on
\set tmp514 `mktemp`
\o :tmp514
\ir ../../supabase/tools/consistency-check.sql
\o
\set cons514 `cat :'tmp514'`
\pset tuples_only off
\pset format aligned
select test.eq((select string_agg(key || '=' || value, ' ' order by key collate "C") from jsonb_each_text((:'cons514'::jsonb) -> 'after')
                 where key in ('receipts_total_vs_moves', 'sinpe_payments_without_reference', 'payments_applied_above_amount', 'advances_ledger_vs_unapplied',
                               'vendors_unapplied_with_open_invoices', 'advances_unapplied_over_30_days', 'purchase_moves_at_zero_cost', 'posted_days_with_purchases_not_posted',
                               'proveedores_dangling_references')),
               'advances_ledger_vs_unapplied=0 advances_unapplied_over_30_days=0 payments_applied_above_amount=0 posted_days_with_purchases_not_posted=0 '
               || 'proveedores_dangling_references=0 purchase_moves_at_zero_cost=0 receipts_total_vs_moves=0 sinpe_payments_without_reference=0 vendors_unapplied_with_open_invoices=0',
               '9 consistency-check.sql: every Proveedores check is 0');
-- proveedores_dangling_references counts what has no foreign key to hold it: in a savepoint (rolled back at once, the
-- results kept in psql variables), a correction pointing at no delivery, then also a payment pointing at no order
select (select corrects::text from public.purchase_receipts where id = '7e000000-0000-4000-8000-000000051462') as corr514,
       (select id::text || ' ' || po_id::text from public.supplier_payments where advance_id = '5d000000-0000-4000-8000-000000051461') as sppo514 \gset
savepoint dangling514;
update public.purchase_receipts set corrects = gen_random_uuid() where id = '7e000000-0000-4000-8000-000000051462';
\pset format unaligned
\pset tuples_only on
\o :tmp514
\ir ../../supabase/tools/consistency-check.sql
\o
\set dang514a `cat :'tmp514'`
update public.supplier_payments set po_id = gen_random_uuid() where advance_id = '5d000000-0000-4000-8000-000000051461';
\o :tmp514
\ir ../../supabase/tools/consistency-check.sql
\o
\set dang514b `cat :'tmp514'`
\pset tuples_only off
\pset format aligned
rollback to savepoint dangling514;
release savepoint dangling514;
select test.eq((:'dang514a'::jsonb) #>> '{after,proveedores_dangling_references}', '1',
               '9 consistency-check.sql: a correction whose delivery does not exist is counted (proveedores_dangling_references = 1)');
select test.eq((:'dang514b'::jsonb) #>> '{after,proveedores_dangling_references}', '2', '9 and a payment whose order does not exist too (= 2)');
select test.eq((select corrects::text from public.purchase_receipts where id = '7e000000-0000-4000-8000-000000051462') || ' '
               || (select id::text || ' ' || po_id::text from public.supplier_payments where advance_id = '5d000000-0000-4000-8000-000000051461'),
               :'corr514' || ' ' || :'sppo514', '9 (rolled back: the correction and the payment point where they did)');
select test.eq(:'corr514' || ' ' || split_part(:'sppo514', ' ', 2), '7e000000-0000-4000-8000-000000051461 9a000000-0000-4000-8000-000000051461',
               '9 (the correction of Luis''s delivery, the payment of its order)');
-- a delivery after the day was posted, with the automatic posting off: the check names that day
select test.login('cafe'); select test.session('dev-514'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select test.eq(test.order514('9a000000-0000-4000-8000-000000051408', 1, true), 'received', '9 (one more box received after the day was posted, automatic posting off)');
reset role;
\pset format unaligned
\pset tuples_only on
\o :tmp514
\ir ../../supabase/tools/consistency-check.sql
\o
\set cons514 `cat :'tmp514'`
\pset tuples_only off
\pset format aligned
select test.eq((:'cons514'::jsonb) #>> '{after,posted_days_with_purchases_not_posted}', '1', '9 consistency-check.sql: one posted day has purchases not posted yet');
select test.eq((:'cons514'::jsonb) #>> '{after,proveedores_dangling_references}', '0', '9 consistency-check.sql: no dangling reference again after the savepoint');

-- 10) every route that pays, guarded on the server (owner, 2026-11-07): Contabilidad's «Registrar pago», the published
--     Inventario page (po_receive_and_settle → po_receipt_settle → supplier_payment_save), a bank expense payment and a
--     direct write never pay again what a Proveedores SINPE or card paid, nor register the same transfer twice ------------
reset role;
insert into public.vendors (id, name) values ('5b000000-0000-4000-8000-000000051470', 'Panadería Cerro Plano');
insert into public.vendor_items (id, vendor_id, item_id, pack_label, pack_qty, usual_price) values
  ('5c000000-0000-4000-8000-000000051470', '5b000000-0000-4000-8000-000000051470', '5a000000-0000-4000-8000-000000051401', 'caja de 12', 12, 12000);
-- an order of n boxes of milk from that supplier, received in full with that delivery id (by whoever is signed in)
create function test.order514b(o text, n int, receipt text) returns text language plpgsql as $$
begin
  perform public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051470', jsonb_build_array(jsonb_build_object('vendor_item_id', '5c000000-0000-4000-8000-000000051470', 'packs', n)),
                                        null, o::uuid);
  perform public.proveedor_recibir(o::uuid, receipt::uuid, test.v514(o), jsonb_build_array(jsonb_build_object('line_id', test.line514(o), 'rest', true)));
  return (select status from public.purchase_orders where id = o::uuid);
end $$;
-- Contabilidad's «Registrar pago» for that supplier, dated today, as contabilidad.js sends it
create function test.cpay514(amount numeric, src text, ref text, id text) returns jsonb language sql as $$
  select public.supplier_payment_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000051470', 'date', public.cr_today(), 'amount_crc', amount, 'paid_from', src,
                                                         'reference', ref), id::uuid) $$;
create function test.open514(i text) returns numeric language sql security definer as $$ select public._invoice_open(i::uuid) $$;
create function test.unap514(a text) returns numeric language sql security definer as $$ select public._prov_unapplied(a::uuid) $$;
create function test.bank514() returns text language sql security definer as $$
  select count(*) || ' ' || coalesce(sum(amount_crc), 0) from public.supplier_payments where vendor_id = '5b000000-0000-4000-8000-000000051470' and paid_from = 'bank' and voided_at is null $$;

-- 10.1) Contabilidad's «Registrar pago» after a Proveedores SINPE, the invoice saved by SQL (nothing applied it yet) ----------
select test.login('cafe'); select test.session('dev-514'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select test.eq(test.order514b('9a000000-0000-4000-8000-000000051471', 1, '7e000000-0000-4000-8000-000000051471'), 'received', '10 (a box of ₡12 000 ordered and received)');
select test.eq(test.pay514('{"vendor_id":"5b000000-0000-4000-8000-000000051470","po_id":"9a000000-0000-4000-8000-000000051471","amount":5000,"method":"sinpe","reference":"FT 5147 1001"}',
                 '5d000000-0000-4000-8000-000000051471') ->> 'unapplied_crc', '5000.00', '10 ₡5 000 by SINPE in Proveedores (the invoice is missing: waits)');
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.supplier_invoice_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000051470', 'number', 'F-514-71', 'date', public.cr_today(), 'net_crc', 12000, 'iva_crc', 1560,
                 'receipt_ids', jsonb_build_array('7e000000-0000-4000-8000-000000051471')), '5e000000-0000-4000-8000-000000051471') ->> 'ok', 'true',
               '10 (Contabilidad saves its invoice F-514-71 of ₡13 560, the old way)');
select test.eq(test.open514('5e000000-0000-4000-8000-000000051471') || ' ' || test.unap514('5d000000-0000-4000-8000-000000051471'), '13560.00 5000.00',
               '10 the invoice open in full, the SINPE still not applied (no trigger applies it)');
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(test.cpay514(13560, 'bank', 'BN 5147-1', '5f000000-0000-4000-8000-000000051471'), '{"ok":false,"error":"more_than_owed","owed":8560.00,"applied_crc":5000.00}'::jsonb,
               '10 the owner pays the whole invoice by bank in Contabilidad: «more than owed», the SINPE applied first (₡5 000), ₡8 560 owed');
reset role;
select test.eq(test.unap514('5d000000-0000-4000-8000-000000051471') || ' ' || test.open514('5e000000-0000-4000-8000-000000051471'), '0.00 8560.00',
               '10 the SINPE is applied now (kept although the payment was refused), the invoice owes the rest');
select test.eq((select count(*)::int from public.supplier_payments where id = '5f000000-0000-4000-8000-000000051471') || ' ' || test.bank514(), '0 0 0',
               '10 no bank payment was registered');
select test.eq((select string_agg(l.account || ':' || l.debit || ':' || l.credit, ' ' order by l.account) from acct.lines l join acct.entries e on e.id = l.entry_id
                 join public.supplier_payments p on e.source_key = 'suppay:' || p.id where p.advance_id = '5d000000-0000-4000-8000-000000051471'),
               '1160:0.00:5000.00 2101:5000.00:0.00', '10 its application: Dr 2101 / Cr 1160');
select test.eq(test.libros514(), '0.00 0.00', '10 the ledger balanced, 1160 = what is not applied');
select test.login('accountant', 'aal2'); set role authenticated;
select test.cpay514(8560, 'bank', 'BN 5147-1', '5f000000-0000-4000-8000-000000051471') as c1 \gset
select test.eq((:'c1'::jsonb) ->> 'ok' || ' ' || ((:'c1'::jsonb) ->> 'applied_crc'), 'true 0', '10 the remainder by bank (the accountant): registered, nothing more to apply');
select test.eq(test.cpay514(8560, 'bank', 'BN 5147-1', '5f000000-0000-4000-8000-000000051471'), '{"ok":true,"repeat":true}'::jsonb, '10 the same request again: a repeat');
reset role;
select test.eq(test.bank514() || ' ' || test.open514('5e000000-0000-4000-8000-000000051471') || ' ' || test.st514('9a000000-0000-4000-8000-000000051471'), '1 8560.00 0.00 paid 13560.00 13560.00',
               '10 one bank payment of ₡8 560, the invoice paid (₡5 000 + ₡8 560, never ₡5 000 + ₡13 560), the order «Pagado»');

-- 10.2) a bank payment in Contabilidad with a live Proveedores SINPE number is the same transfer, however it is written ------
select test.login('cafe'); select test.session('dev-514'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select test.eq(test.order514b('9a000000-0000-4000-8000-000000051472', 10, '7e000000-0000-4000-8000-000000051472'), 'received', '10 (10 boxes received: ₡120 000)');
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.supplier_invoice_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000051470', 'number', 'F-514-72', 'date', public.cr_today(), 'net_crc', 120000, 'iva_crc', 15600,
                 'receipt_ids', jsonb_build_array('7e000000-0000-4000-8000-000000051472')), '5e000000-0000-4000-8000-000000051472') ->> 'ok', 'true',
               '10 (its invoice F-514-72 of ₡135 600, saved by SQL)');
select test.login('cafe'); select test.session('dev-514'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select test.eq(test.pay514('{"vendor_id":"5b000000-0000-4000-8000-000000051470","po_id":"9a000000-0000-4000-8000-000000051472","amount":10000,"method":"sinpe","reference":"FT 2026 1107 4471"}',
                 '5d000000-0000-4000-8000-000000051472') ->> 'applied_crc', '10000.00', '10 ₡10 000 by SINPE «FT 2026 1107 4471» in Proveedores, applied to it');
select test.eq(test.pay514('{"vendor_id":"5b000000-0000-4000-8000-000000051470","po_id":"9a000000-0000-4000-8000-000000051472","amount":1000,"method":"sinpe","reference":"Transferencia"}',
                 '5d000000-0000-4000-8000-000000051473') ->> 'ok', 'true', '10 (₡1 000 by SINPE whose reference is the word «Transferencia», without a digit)');
select test.eq(test.pay514('{"vendor_id":"5b000000-0000-4000-8000-000000051470","po_id":"9a000000-0000-4000-8000-000000051472","amount":1000,"method":"sinpe","reference":"FT 7474 0001"}',
                 '5d000000-0000-4000-8000-000000051474') ->> 'ok', 'true', '10 (and ₡1 000 by SINPE «FT 7474 0001»)');
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.proveedor_pago_anular('5d000000-0000-4000-8000-000000051474', 'Número de SINPE equivocado'), '{"ok":true}'::jsonb, '10 (that one voided by the accountant)');
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(test.cpay514(10000, 'bank', 'ft-2026-1107-4471', '5f000000-0000-4000-8000-000000051472'),
               jsonb_build_object('ok', false, 'error', 'duplicate_reference', 'vendor_name', 'Panadería Cerro Plano', 'date', public.cr_today(), 'amount', 10000.00),
               '10 Contabilidad, by bank, the same number with dashes in lower case: «Ese número de SINPE ya está registrado en Proveedores» (who, when, how much)');
select test.eq(test.cpay514(10000, 'bank', '  FT.2026.1107.4471  ', '5f000000-0000-4000-8000-000000051473') ->> 'error', 'duplicate_reference', '10 with dots and spaces around: the same');
select test.eq(test.cpay514(1000, 'bank', 'transferencia', '5f000000-0000-4000-8000-000000051474') ->> 'ok', 'true',
               '10 a reference without a digit («transferencia», a SINPE in Proveedores says the same) is no SINPE number: not refused');
select test.eq(test.cpay514(1000, 'bank', 'FT-7474-0001', '5f000000-0000-4000-8000-000000051476') ->> 'ok', 'true', '10 the number of the voided SINPE: not refused');
select test.eq(test.cpay514(1000, 'card_debit', 'FT-2026-1107-4471', '5f000000-0000-4000-8000-000000051477') ->> 'ok', 'true',
               '10 a card payment with the live number: not refused (a SINPE number is looked up on bank payments only)');
reset role;
-- a key shorter than 4 characters is never looked up (no SINPE registered through Proveedores can have one: a row made to
-- hold one, in a savepoint rolled back at once, the answer kept in a psql variable)
savepoint corta514;
update public.supplier_advances set ref_key = 'ab1' where id = '5d000000-0000-4000-8000-000000051473';
select test.login('owner', 'aal2'); set role authenticated;
select test.cpay514(1000, 'bank', 'A-B-1', '5f000000-0000-4000-8000-000000051475') ->> 'ok' as corta514 \gset
reset role;
rollback to savepoint corta514; release savepoint corta514;
select test.eq(:'corta514'::text, 'true', '10 a reference whose key is shorter than 4 characters («A-B-1», a SINPE row holds that key): not refused');
select test.eq((select count(*)::int from public.supplier_payments where id in ('5f000000-0000-4000-8000-000000051472', '5f000000-0000-4000-8000-000000051473', '5f000000-0000-4000-8000-000000051475'))
               || ' ' || (select ref_key from public.supplier_advances where id = '5d000000-0000-4000-8000-000000051473'), '0 transferencia',
               '10 nothing registered for the refused ones, the savepoint rolled back (the SINPE keeps its key)');
select test.eq(test.open514('5e000000-0000-4000-8000-000000051472') || ' ' || test.bank514(), '121600.00 3 10560.00',
               '10 F-514-72 owes 135 600 − 10 000 − 1 000 (SINPE) − 1 000 (bank «transferencia») − 1 000 (bank, the voided number) − 1 000 (card); three bank payments in all');

-- 10.3) a bank payment of a credit expense with that SINPE number ------------------------------------------------------------------
insert into public.expenses (id, date, description, account, amount_crc, paid_from, created_by) values
  ('6e000000-0000-4000-8000-000000051481', public.cr_today(), 'Gas para la cocina 514', :'exp_acct', 8000, 'credit', 'prueba 514');
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.expense_pay(jsonb_build_object('expense_id', '6e000000-0000-4000-8000-000000051481', 'amount_crc', 8000, 'paid_from', 'bank', 'date', public.cr_today(),
                 'reference', 'ft 2026-1107-4471'), '6f000000-0000-4000-8000-000000051481'),
               jsonb_build_object('ok', false, 'error', 'duplicate_reference', 'vendor_name', 'Panadería Cerro Plano', 'date', public.cr_today(), 'amount', 10000.00),
               '10 the accountant pays a credit expense by bank with the live SINPE number: refused, the same words');
select public.expense_pay(jsonb_build_object('expense_id', '6e000000-0000-4000-8000-000000051481', 'amount_crc', 8000, 'paid_from', 'bank', 'date', public.cr_today(),
         'reference', 'BCR 5148 0001'), '6f000000-0000-4000-8000-000000051482') as ep \gset
select test.eq((:'ep'::jsonb) ->> 'ok' || ' ' || ((:'ep'::jsonb) ->> 'open_crc'), 'true 0.00', '10 with another reference: paid, nothing open');
reset role;
select test.eq((select string_agg(right(id::text, 2) || ':' || amount_crc, ' ' order by id) from public.expense_payments where expense_id = '6e000000-0000-4000-8000-000000051481'), '82:8000.00',
               '10 one expense payment, the refused one left nothing');

-- 10.4) the published page's route (po_receive_and_settle → po_receipt_settle → supplier_payment_save) with a SINPE ahead ------
-- a supplier that owes nothing else: the bank payment of the whole invoice is refused and nothing is saved
reset role;
insert into public.vendors (id, name) values ('5b000000-0000-4000-8000-000000051475', 'Café de Altura 514');
insert into public.vendor_items (id, vendor_id, item_id, pack_label, pack_qty, usual_price) values
  ('5c000000-0000-4000-8000-000000051475', '5b000000-0000-4000-8000-000000051475', '5a000000-0000-4000-8000-000000051401', 'caja de 12', 12, 12000);
select test.login('cafe'); select test.session('dev-514'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select test.eq(public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051475', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051475","packs":1}]', null,
                 '9a000000-0000-4000-8000-000000051477') ->> 'ok', 'true', '10 (an order of one box from a supplier that owes nothing else)');
select test.eq(test.pay514('{"vendor_id":"5b000000-0000-4000-8000-000000051475","po_id":"9a000000-0000-4000-8000-000000051477","amount":5000,"method":"sinpe","reference":"FT 7777 0005"}',
                 '5d000000-0000-4000-8000-000000051477') ->> 'unapplied_crc', '5000.00', '10 ₡5 000 by SINPE ahead of it');
reset role;
select test.stock514() as stock514c, (select count(*) from public.supplier_payments) as sp514c \gset
set role authenticated;
select test.eq(public.po_receive_and_settle('9a000000-0000-4000-8000-000000051477', jsonb_build_array(jsonb_build_object('line_id', test.line514('9a000000-0000-4000-8000-000000051477'), 'qty', 12)),
                 '7e000000-0000-4000-8000-000000051477', false, jsonb_build_object('mode', 'confirm', 'number', 'F-514-77', 'date', public.cr_today(), 'currency', 'CRC', 'net', 12000, 'iva', 1560),
                 '[{"method":"bank","amount_crc":13560,"reference":"BN 7777"}]', test.staff('ana'), '4826'),
               '{"ok":false,"error":"more_than_owed","step":"payment"}'::jsonb,
               '10 the published page receives, invoices and pays the whole invoice by bank in one call: «more than owed» at the payment step');
reset role;
select test.eq((select count(*)::int from public.purchase_receipts where po_id = '9a000000-0000-4000-8000-000000051477') || ' '
               || (select count(*) from public.supplier_invoices where vendor_id = '5b000000-0000-4000-8000-000000051475') || ' '
               || (select count(*) from public.supplier_payments where vendor_id = '5b000000-0000-4000-8000-000000051475') || ' ' || ((select count(*) from public.supplier_payments) = :sp514c) || ' '
               || test.unap514('5d000000-0000-4000-8000-000000051477') || ' ' || (select status from public.purchase_orders where id = '9a000000-0000-4000-8000-000000051477') || ' '
               || (test.stock514() = :'stock514c'),
               '0 0 0 true 5000.00 sent true',
               '10 and nothing is saved: no delivery, no invoice, no payment anywhere, the SINPE not applied, the order and the stock as they were');
set role authenticated;
select public.po_receive_and_settle('9a000000-0000-4000-8000-000000051477', jsonb_build_array(jsonb_build_object('line_id', test.line514('9a000000-0000-4000-8000-000000051477'), 'qty', 12)),
         '7e000000-0000-4000-8000-000000051477', false, jsonb_build_object('mode', 'confirm', 'number', 'F-514-77', 'date', public.cr_today(), 'currency', 'CRC', 'net', 12000, 'iva', 1560),
         '[{"method":"bank","amount_crc":8560,"reference":"BN 7777"}]', test.staff('ana'), '4826') as old2 \gset
-- (the answer's paid_crc/open_crc count this call's own payments, 0029's way: ₡8 560 paid, «₡5 000 open» although the
-- invoice is paid in full once the SINPE is applied; the books below are what counts)
select test.eq((:'old2'::jsonb) ->> 'ok' || ' ' || ((:'old2'::jsonb) ->> 'invoice_status') || ' ' || ((:'old2'::jsonb) ->> 'paid_crc'), 'true confirmed 8560.00',
               '10 with the remainder: received, invoiced and paid in one call');
reset role;
select test.eq(test.unap514('5d000000-0000-4000-8000-000000051477') || ' ' || test.open514((:'old2'::jsonb) ->> 'invoice_id') || ' '
               || (select count(*) || ' ' || sum(amount_crc) from public.supplier_payments where vendor_id = '5b000000-0000-4000-8000-000000051475' and paid_from = 'bank')
               || ' ' || (select invoice_status from public.purchase_receipts where id = '7e000000-0000-4000-8000-000000051477') || ' ' || test.st514('9a000000-0000-4000-8000-000000051477'),
               '0.00 0.00 1 8560.00 confirmed paid 13560.00 13560.00', '10 the SINPE applied, one bank payment of ₡8 560, the invoice paid, the delivery confirmed, the order «Pagado»');
-- the first supplier, with F-514-72 still open (₡121 600): the same call is accepted, as 0029 allocates (the invoice named
-- first, then the oldest due), but F-514-75 is paid once: the SINPE and ₡8 560 of the bank payment; the other ₡5 000 go to F-514-72
select test.login('cafe'); select test.session('dev-514'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select test.eq(public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051470', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051470","packs":1}]', null,
                 '9a000000-0000-4000-8000-000000051475') ->> 'ok', 'true', '10 (an order of one box from the first supplier, F-514-72 still open)');
select test.eq(test.pay514('{"vendor_id":"5b000000-0000-4000-8000-000000051470","po_id":"9a000000-0000-4000-8000-000000051475","amount":5000,"method":"sinpe","reference":"FT 7575 0005"}',
                 '5d000000-0000-4000-8000-000000051475') ->> 'unapplied_crc', '5000.00', '10 ₡5 000 by SINPE ahead of it');
select public.po_receive_and_settle('9a000000-0000-4000-8000-000000051475', jsonb_build_array(jsonb_build_object('line_id', test.line514('9a000000-0000-4000-8000-000000051475'), 'qty', 12)),
         '7e000000-0000-4000-8000-000000051475', false, jsonb_build_object('mode', 'confirm', 'number', 'F-514-75', 'date', public.cr_today(), 'currency', 'CRC', 'net', 12000, 'iva', 1560),
         '[{"method":"bank","amount_crc":13560,"reference":"BN 7575"}]', test.staff('ana'), '4826') as old3 \gset
select test.eq((:'old3'::jsonb) ->> 'ok' || ' ' || ((:'old3'::jsonb) ->> 'paid_crc') || ' ' || ((:'old3'::jsonb) ->> 'open_crc'), 'true 13560.00 0.00',
               '10 the whole invoice by bank while another invoice is open: accepted (the supplier is owed it)');
reset role;
select test.eq((select string_agg(p.paid_from || ':' || a.amount_crc, ' ' order by p.paid_from) from public.supplier_payment_allocations a join public.supplier_payments p on p.id = a.payment_id
                 where a.invoice_id = ((:'old3'::jsonb) ->> 'invoice_id')::uuid and p.voided_at is null) || ' | ' || test.open514((:'old3'::jsonb) ->> 'invoice_id') || ' | '
               || test.open514('5e000000-0000-4000-8000-000000051472') || ' | ' || test.unap514('5d000000-0000-4000-8000-000000051475'),
               'advance:5000.00 bank:8560.00 | 0.00 | 116600.00 | 0.00',
               '10 F-514-75 is paid once (the SINPE ₡5 000 + ₡8 560 of the bank payment), never above its total; the other ₡5 000 went to F-514-72, the SINPE applied');

-- 10.5) the two triggers, the last guard whatever writes: direct rows as the test superuser, in a savepoint rolled back at once
--       (the answers kept in psql variables); the invoice of ₡1 000 and the card payment of ₡1 000 are the savepoint's own ----
reset role;
savepoint guardas514;
insert into public.supplier_invoices (id, vendor_id, number, date, net_crc, iva_crc, created_by) values
  ('5e000000-0000-4000-8000-000000051476', '5b000000-0000-4000-8000-000000051470', 'F-514-76', public.cr_today(), 1000, 0, 'prueba 514');
insert into public.supplier_payments (id, vendor_id, date, amount_crc, paid_from, created_by) values
  ('5f000000-0000-4000-8000-000000051478', '5b000000-0000-4000-8000-000000051470', public.cr_today(), 1500, 'bank', 'prueba 514'),
  ('5f000000-0000-4000-8000-000000051479', '5b000000-0000-4000-8000-000000051470', public.cr_today(), 1500, 'bank', 'prueba 514');
insert into public.supplier_advances (id, vendor_id, date, amount_crc, method, created_by) values
  ('5d000000-0000-4000-8000-000000051476', '5b000000-0000-4000-8000-000000051470', public.cr_today(), 1000, 'card_debit', 'prueba 514');
select test.throws($q$insert into public.supplier_payment_allocations (payment_id, invoice_id, amount_crc) values ('5f000000-0000-4000-8000-000000051478', '5e000000-0000-4000-8000-000000051476', 1000.01)$q$,
                   'prov:over_allocated', 'x') as g1 \gset
select test.lives($q$insert into public.supplier_payment_allocations (payment_id, invoice_id, amount_crc) values ('5f000000-0000-4000-8000-000000051478', '5e000000-0000-4000-8000-000000051476', 600)$q$, 'x') as g2 \gset
select test.throws($q$insert into public.supplier_payment_allocations (payment_id, invoice_id, amount_crc) values ('5f000000-0000-4000-8000-000000051479', '5e000000-0000-4000-8000-000000051476', 400.01)$q$,
                   'prov:over_allocated', 'x') as g3 \gset
select test.lives($q$insert into public.supplier_payment_allocations (payment_id, invoice_id, amount_crc) values ('5f000000-0000-4000-8000-000000051479', '5e000000-0000-4000-8000-000000051476', 400)$q$, 'x') as g4 \gset
select test.throws($q$update public.supplier_payment_allocations set amount_crc = 400.01 where payment_id = '5f000000-0000-4000-8000-000000051479' and invoice_id = '5e000000-0000-4000-8000-000000051476'$q$,
                   'prov:over_allocated', 'x') as g5 \gset
select test.lives($q$update public.supplier_payments set voided_at = now(), void_reason = 'prueba' where id = '5f000000-0000-4000-8000-000000051478';
                     update public.supplier_payment_allocations set amount_crc = 1000 where payment_id = '5f000000-0000-4000-8000-000000051479' and invoice_id = '5e000000-0000-4000-8000-000000051476'$q$, 'x') as g6 \gset
select test.throws($q$insert into public.supplier_payments (id, vendor_id, date, amount_crc, paid_from, created_by, advance_id) values
                     ('5f000000-0000-4000-8000-00000005147a', '5b000000-0000-4000-8000-000000051470', public.cr_today(), 1000.01, 'advance', 'prueba 514', '5d000000-0000-4000-8000-000000051476')$q$,
                   'prov:over_applied', 'x') as g7 \gset
select test.lives($q$insert into public.supplier_payments (id, vendor_id, date, amount_crc, paid_from, created_by, advance_id) values
                     ('5f000000-0000-4000-8000-00000005147a', '5b000000-0000-4000-8000-000000051470', public.cr_today(), 600, 'advance', 'prueba 514', '5d000000-0000-4000-8000-000000051476')$q$, 'x') as g8 \gset
select test.throws($q$insert into public.supplier_payments (id, vendor_id, date, amount_crc, paid_from, created_by, advance_id) values
                     ('5f000000-0000-4000-8000-00000005147b', '5b000000-0000-4000-8000-000000051470', public.cr_today(), 400.01, 'advance', 'prueba 514', '5d000000-0000-4000-8000-000000051476')$q$,
                   'prov:over_applied', 'x') as g9 \gset
select test.lives($q$insert into public.supplier_payments (id, vendor_id, date, amount_crc, paid_from, created_by, advance_id) values
                     ('5f000000-0000-4000-8000-00000005147b', '5b000000-0000-4000-8000-000000051470', public.cr_today(), 400, 'advance', 'prueba 514', '5d000000-0000-4000-8000-000000051476')$q$, 'x') as g10 \gset
select test.throws($q$update public.supplier_payments set amount_crc = 400.01 where id = '5f000000-0000-4000-8000-00000005147b'$q$, 'prov:over_applied', 'x') as g11 \gset
select test.throws($q$update public.supplier_payments set advance_id = '5d000000-0000-4000-8000-000000051476' where id = '5f000000-0000-4000-8000-000000051479'$q$, 'prov:over_applied', 'x') as g12 \gset
select test.lives($q$update public.supplier_payments set voided_at = now(), void_reason = 'prueba' where id = '5f000000-0000-4000-8000-00000005147a';
                     insert into public.supplier_payments (id, vendor_id, date, amount_crc, paid_from, created_by, advance_id) values
                       ('5f000000-0000-4000-8000-00000005147c', '5b000000-0000-4000-8000-000000051470', public.cr_today(), 600, 'advance', 'prueba 514', '5d000000-0000-4000-8000-000000051476')$q$, 'x') as g13 \gset
select (select count(*) from public.supplier_payment_allocations where invoice_id = '5e000000-0000-4000-8000-000000051476') || ' '
       || (select count(*) from public.supplier_payments where advance_id = '5d000000-0000-4000-8000-000000051476') as g14 \gset
rollback to savepoint guardas514; release savepoint guardas514;
select test.ok(:'g1'::boolean, '10 a direct allocation beyond the invoice''s total (₡1 000.01 on ₡1 000) raises prov:over_allocated');
select test.ok(:'g2'::boolean, '10 one within it (₡600) is accepted');
select test.ok(:'g3'::boolean, '10 a second one that would pass the total (₡400.01 after ₡600) raises prov:over_allocated');
select test.ok(:'g4'::boolean, '10 one that fills it exactly (₡400) is accepted');
select test.ok(:'g5'::boolean, '10 an update of an allocation that would pass the total raises too');
select test.ok(:'g6'::boolean, '10 a voided payment''s allocation no longer counts: the other may grow to the total');
select test.ok(:'g7'::boolean, '10 a direct application beyond the Proveedores payment''s amount (₡1 000.01 of ₡1 000) raises prov:over_applied');
select test.ok(:'g8'::boolean, '10 one within it (₡600) is accepted');
select test.ok(:'g9'::boolean, '10 a second one that would pass the amount (₡400.01 after ₡600) raises prov:over_applied');
select test.ok(:'g10'::boolean, '10 one that fills it exactly (₡400) is accepted');
select test.ok(:'g11'::boolean, '10 an update of an application''s amount that would pass it raises too');
select test.ok(:'g12'::boolean, '10 and so does pointing a ₡1 500 payment at that Proveedores payment');
select test.ok(:'g13'::boolean, '10 a voided application no longer counts: its room may be applied again');
select test.eq(:'g14'::text, '2 3', '10 (what the savepoint held: two allocations, three applications)');
select test.eq((select count(*)::int from public.supplier_invoices where id = '5e000000-0000-4000-8000-000000051476') + (select count(*)::int from public.supplier_advances where id = '5d000000-0000-4000-8000-000000051476')
               + (select count(*)::int from public.supplier_payments where id in ('5f000000-0000-4000-8000-000000051478', '5f000000-0000-4000-8000-000000051479')), 0,
               '10 rolled back: none of the direct rows stays');
select test.eq(test.libros514(), '0.00 0.00', '10 after every payment and application of the file: the ledger balanced, 1160 = the Proveedores payments not applied');

select test.done();
rollback;
