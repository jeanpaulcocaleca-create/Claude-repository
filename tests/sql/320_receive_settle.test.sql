-- Migration 0029: receive a delivery with its supplier invoice and payments in one call; pending and review invoices;
-- more payments later; what the order holds; what is pending.
begin;
insert into public.fx_rates (day, buy, sell, source) values (public.cr_today(), 500, 510, 'hacienda') on conflict (day) do nothing;
insert into public.vendors (id, name) values ('5b000000-0000-4000-8000-000000003201', 'Lácteos Monteverde'),
                                             ('5b000000-0000-4000-8000-000000003202', 'Verduras del Valle');
insert into public.stock_items (id, name, unit, pack_qty, cost_per_pack) values ('5a000000-0000-4000-8000-000000003201', 'Leche', 'ml', 1000, 1000),
                                                                              ('5a000000-0000-4000-8000-000000003202', 'Queso', 'g', 500, 3000);
insert into public.purchase_orders (id, vendor_id, status) values ('9a000000-0000-4000-8000-000000003201', '5b000000-0000-4000-8000-000000003201', 'sent'),
                                                                 ('9a000000-0000-4000-8000-000000003202', '5b000000-0000-4000-8000-000000003201', 'sent'),
                                                                 ('9a000000-0000-4000-8000-000000003203', null, 'sent');
insert into public.purchase_lines (id, po_id, item_id, packs, qty, unit_cost) values
  ('9b000000-0000-4000-8000-000000003201', '9a000000-0000-4000-8000-000000003201', '5a000000-0000-4000-8000-000000003201', 10, 10000, 1),   -- ₡10 000
  ('9b000000-0000-4000-8000-000000003202', '9a000000-0000-4000-8000-000000003201', '5a000000-0000-4000-8000-000000003202', 2, 1000, 6),     -- ₡6 000
  ('9b000000-0000-4000-8000-000000003203', '9a000000-0000-4000-8000-000000003202', '5a000000-0000-4000-8000-000000003201', 5, 5000, 1),     -- ₡5 000
  ('9b000000-0000-4000-8000-000000003204', '9a000000-0000-4000-8000-000000003203', '5a000000-0000-4000-8000-000000003202', 1, 500, 6);      -- ₡3 000
select to_char(public.cr_today(), 'YYYY-MM-DD') as today \gset
select to_char(public.cr_today() + 15, 'YYYY-MM-DD') as due \gset

-- the new functions exist and are reachable from a page
select test.ok((select count(*) = 5 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'
                  and p.proname in ('po_receive_and_settle', 'po_receipt_settle', 'po_receipt_pay', 'po_history', 'po_pending')), 'the five functions exist');
select test.eq((select account from acct.mappings where key = 'from_card_credit'), '2160', 'credit card payments map to their own liability account');
select test.eq((select account from acct.mappings where key = 'from_card_debit'), '1110', 'debit card payments leave the bank account');

select test.login('cafe'); set role authenticated;
select test.eq(public.po_receive_and_settle('9a000000-0000-4000-8000-000000003201', '[]', gen_random_uuid())->>'error', 'locked', 'a locked café device cannot receive');
select test.eq(public.po_pending()->>'error', 'locked', 'nor see what is pending');
select test.unlock(test.staff('ana'), '4826');

-- a delivery with nothing in it is refused unless it closes the order
select test.eq(public.po_receive_and_settle('9a000000-0000-4000-8000-000000003201', '[{"line_id":"9b000000-0000-4000-8000-000000003201","qty":0}]',
               '7e000000-0000-4000-8000-000000003201')->>'error', 'empty', 'a delivery with nothing in it is refused');

-- cash from the register needs an open register day: nothing is saved, not even the delivery
select public.po_receive_and_settle('9a000000-0000-4000-8000-000000003201',
         '[{"line_id":"9b000000-0000-4000-8000-000000003201","qty":10000},{"line_id":"9b000000-0000-4000-8000-000000003202","qty":1000}]',
         '7e000000-0000-4000-8000-000000003201', false,
         jsonb_build_object('mode', 'confirm', 'number', 'F-500', 'date', :'today', 'due_date', :'due', 'currency', 'CRC', 'net', 16000, 'iva', 2080),
         '[{"method":"register","amount_crc":5000}]', test.staff('ana'), '4826') as r0 \gset
select test.eq(((:'r0'::jsonb)->>'error'), 'not_open', 'cash from the register needs an open register day');
select test.eq(((:'r0'::jsonb)->>'step'), 'register', 'and the answer says which step refused');
select test.eq((select count(*)::int from public.purchase_receipts where id = '7e000000-0000-4000-8000-000000003201'), 0, 'nothing was saved, not even the delivery');
select test.eq((select count(*)::int from public.stock_moves where receipt_id = '7e000000-0000-4000-8000-000000003201'), 0, 'no stock moved');
select test.eq(public.register_open(test.staff('ana'), '4826', 50000, 0)->>'ok', 'true', 'the register opens with ₡50 000');

-- a wrong PIN saves nothing
select test.eq(public.po_receive_and_settle('9a000000-0000-4000-8000-000000003201',
         '[{"line_id":"9b000000-0000-4000-8000-000000003201","qty":10000},{"line_id":"9b000000-0000-4000-8000-000000003202","qty":1000}]',
         '7e000000-0000-4000-8000-000000003201', false,
         jsonb_build_object('mode', 'confirm', 'number', 'F-500', 'date', :'today', 'currency', 'CRC', 'net', 16000, 'iva', 2080),
         '[{"method":"register","amount_crc":5000}]', test.staff('ana'), '0000')->>'error', 'bad_pin', 'a wrong PIN refuses the payment');
select test.eq((select count(*)::int from public.purchase_receipts), 0, 'and saves nothing');
-- a barista's PIN cannot pay
select test.eq(public.po_receive_and_settle('9a000000-0000-4000-8000-000000003201',
         '[{"line_id":"9b000000-0000-4000-8000-000000003201","qty":10000}]', '7e000000-0000-4000-8000-000000003201', false,
         jsonb_build_object('mode', 'confirm', 'number', 'F-500', 'date', :'today', 'currency', 'CRC', 'net', 16000, 'iva', 2080),
         '[{"method":"bank","amount_crc":5000}]', test.staff('luis'), '5284')->>'error', 'not_manager', 'a barista''s PIN does not pay');
-- paying more than the invoice is refused
select test.eq(public.po_receive_and_settle('9a000000-0000-4000-8000-000000003201',
         '[{"line_id":"9b000000-0000-4000-8000-000000003201","qty":10000}]', '7e000000-0000-4000-8000-000000003201', false,
         jsonb_build_object('mode', 'confirm', 'number', 'F-500', 'date', :'today', 'currency', 'CRC', 'net', 16000, 'iva', 2080),
         '[{"method":"bank","amount_crc":18081}]', test.staff('ana'), '4826')->>'error', 'over_invoice', 'more than the invoice is refused');
-- an unknown method, a future date, a zero invoice
select test.eq(public.po_receive_and_settle('9a000000-0000-4000-8000-000000003201',
         '[{"line_id":"9b000000-0000-4000-8000-000000003201","qty":10000}]', '7e000000-0000-4000-8000-000000003201', false,
         jsonb_build_object('mode', 'confirm', 'number', 'F-500', 'date', :'today', 'currency', 'CRC', 'net', 16000, 'iva', 2080),
         '[{"method":"bitcoin","amount_crc":10}]', test.staff('ana'), '4826')->>'error', 'bad_value', 'an unknown payment method is refused');
select test.eq(public.po_receive_and_settle('9a000000-0000-4000-8000-000000003201',
         '[{"line_id":"9b000000-0000-4000-8000-000000003201","qty":10000}]', '7e000000-0000-4000-8000-000000003201', false,
         jsonb_build_object('mode', 'confirm', 'number', 'F-500', 'date', to_char(public.cr_today() + 1, 'YYYY-MM-DD'), 'currency', 'CRC', 'net', 16000, 'iva', 2080),
         '[]')->>'error', 'future_date', 'an invoice dated tomorrow is refused');
select test.eq(public.po_receive_and_settle('9a000000-0000-4000-8000-000000003201',
         '[{"line_id":"9b000000-0000-4000-8000-000000003201","qty":10000}]', '7e000000-0000-4000-8000-000000003201', false,
         jsonb_build_object('mode', 'confirm', 'number', 'F-500', 'date', :'today', 'currency', 'CRC', 'net', 0, 'iva', 0), '[]')->>'error', 'bad_value',
         'an invoice of zero is refused');
select test.eq((select count(*)::int from public.purchase_receipts), 0, 'every refusal left the database untouched');

-- the real reception: the whole order, invoice F-500 (₡16 000 + IVA 2 080), ₡5 000 from the register and ₡3 080 by debit card, ₡10 000 on credit
select public.po_receive_and_settle('9a000000-0000-4000-8000-000000003201',
         '[{"line_id":"9b000000-0000-4000-8000-000000003201","qty":10000},{"line_id":"9b000000-0000-4000-8000-000000003202","qty":1000}]',
         '7e000000-0000-4000-8000-000000003201', false,
         jsonb_build_object('mode', 'confirm', 'number', 'F-500', 'date', :'today', 'due_date', :'due', 'currency', 'CRC', 'net', 16000, 'iva', 2080, 'source', 'xml'),
         '[{"method":"register","amount_crc":5000},{"method":"card_debit","amount_crc":3080,"reference":"****1234"}]', test.staff('ana'), '4826') as r1 \gset
select test.eq(((:'r1'::jsonb)->>'ok'), 'true', 'the delivery, the invoice and two payments are saved in one call');
select test.eq(((:'r1'::jsonb)->>'status'), 'received', 'the order is received');
select test.eq(((:'r1'::jsonb)->>'invoice_status'), 'confirmed', 'the invoice is confirmed');
select test.eq((((:'r1'::jsonb)->>'total_crc'))::numeric, 18080::numeric, 'invoice total 18 080');
select test.eq((((:'r1'::jsonb)->>'paid_crc'))::numeric, 8080::numeric, 'paid 8 080');
select test.eq((((:'r1'::jsonb)->>'open_crc'))::numeric, 10000::numeric, 'balance 10 000 on credit');
-- the same call again: nothing doubles
select public.po_receive_and_settle('9a000000-0000-4000-8000-000000003201',
         '[{"line_id":"9b000000-0000-4000-8000-000000003201","qty":10000},{"line_id":"9b000000-0000-4000-8000-000000003202","qty":1000}]',
         '7e000000-0000-4000-8000-000000003201', false,
         jsonb_build_object('mode', 'confirm', 'number', 'F-500', 'date', :'today', 'due_date', :'due', 'currency', 'CRC', 'net', 16000, 'iva', 2080),
         '[{"method":"register","amount_crc":5000},{"method":"card_debit","amount_crc":3080}]', test.staff('ana'), '4826') as r1b \gset
select test.eq(((:'r1b'::jsonb)->>'repeat'), 'true', 'the same confirmation sent twice is saved once');
select test.eq(((:'r1b'::jsonb)->>'ok'), 'true', 'and answers ok');
reset role;
select test.eq((select on_hand from public.stock_items where id = '5a000000-0000-4000-8000-000000003201'), 10000::numeric, 'milk in stock once');
select test.eq((select invoice_status || ':' || invoice_no || ':' || coalesce(invoice_id::text, '-') from public.purchase_receipts where id = '7e000000-0000-4000-8000-000000003201'),
               'confirmed:F-500:7e000000-0000-4000-8000-000000003201', 'the delivery carries the confirmed invoice, same id');
select test.eq((select net_crc || '|' || iva_crc || '|' || total_crc || '|' || currency || '|' || array_to_string(receipt_ids, ',') from public.supplier_invoices
                 where id = '7e000000-0000-4000-8000-000000003201'), '16000.00|2080.00|18080.00|CRC|7e000000-0000-4000-8000-000000003201',
               'the supplier invoice: net, IVA, total, in colones, linked to the delivery');
select test.eq((select count(*)::int from public.supplier_payments), 2, 'two payments, not four');
select test.eq((select string_agg(paid_from || ':' || amount_crc || ':' || (payout_id is not null), ',' order by amount_crc) from public.supplier_payments),
               'card_debit:3080.00:false,payout:5000.00:true', 'a register payout documented in the act, and a debit card payment');
select test.eq((select count(*)::int from public.cash_movements where purpose = 'payout' and voided_at is null), 1, 'one payout from the drawer');
select test.ok((select reason like 'Pedido Nº % · Lácteos Monteverde · factura F-500' from public.cash_movements where purpose = 'payout'), 'the payout says which order and invoice');
select test.eq((select sum(amount_crc) from public.supplier_payment_allocations where invoice_id = '7e000000-0000-4000-8000-000000003201'), 8080::numeric, 'both payments applied to this invoice');
select test.eq(public._invoice_open('7e000000-0000-4000-8000-000000003201'), 10000::numeric, 'the invoice is open for 10 000');
select test.eq((select cash_crc from public._register_expected(public.cr_today())), -5000::bigint, 'the drawer expects 5 000 less (the payout)');
set constraints all immediate; set constraints all deferred;
select test.eq((select string_agg(l.account || ':' || (l.debit - l.credit), ',' order by l.account) from acct.lines l join acct.entries e on e.id = l.entry_id
                 where e.source_key = 'supinv:7e000000-0000-4000-8000-000000003201'), '1140:2080.00,2101:-2080.00', 'the invoice posts only its IVA (net = received cost)');
select test.eq((select string_agg(l.account || ':' || (l.debit - l.credit), ',' order by e.id, l.account) from acct.lines l join acct.entries e on e.id = l.entry_id
                 where e.source like 'ap' and e.memo like 'Pago a Lácteos%'), '1104:-5000.00,2101:5000.00,1110:-3080.00,2101:3080.00',
               'the payout clears 1104 and the card leaves the bank; both lower what is owed');
select test.eq((select count(*)::int from public.audit_log where action = 'po_settle'), 1, 'one audit line for the settlement');

-- more payments later, from Inventario: ₡4 000 by SINPE
select test.login('cafe'); set role authenticated; select test.unlock(test.staff('ana'), '4826');
select test.eq(public.po_receipt_pay('7e000000-0000-4000-8000-000000003201', '[{"method":"bank","amount_crc":4000,"reference":"SINPE 1234"}]',
               '7e000000-0000-4000-8000-000000003211', test.staff('ana'), '4826')->>'open_crc', '6000.00', 'a later payment leaves 6 000 open');
select test.eq(public.po_receipt_pay('7e000000-0000-4000-8000-000000003201', '[{"method":"bank","amount_crc":4000}]',
               '7e000000-0000-4000-8000-000000003211', test.staff('ana'), '4826')->>'repeat', 'true', 'the same later payment twice is saved once');
select test.eq(public.po_receipt_pay('7e000000-0000-4000-8000-000000003201', '[{"method":"card_credit","amount_crc":7000}]',
               gen_random_uuid(), test.staff('ana'), '4826')->>'error', 'over_invoice', 'never more than what is open');
select test.eq(public.po_receipt_pay('7e000000-0000-4000-8000-000000003201', '[{"method":"card_credit","amount_crc":1000}]',
               gen_random_uuid(), test.staff('ana'), '1111')->>'error', 'bad_pin', 'a later payment also needs the PIN');
select test.eq(public.po_receipt_pay('7e000000-0000-4000-8000-000000003201', '[{"method":"card_credit","amount_crc":1000,"reference":"Visa"}]',
               '7e000000-0000-4000-8000-000000003212', test.staff('ana'), '4826')->>'open_crc', '5000.00', 'a credit card payment leaves 5 000');
-- the order's history
select public.po_history('9a000000-0000-4000-8000-000000003201') as h \gset
select test.eq((:'h'::jsonb)->'order'->>'vendor', 'Lácteos Monteverde', 'the history names the supplier');
select test.eq(jsonb_array_length((:'h'::jsonb)->'receipts'), 1, 'one delivery');
select test.eq((:'h'::jsonb)->'receipts'->0->'invoice'->>'open_crc', '5000.00', 'its invoice is open for 5 000');
select test.eq(jsonb_array_length((:'h'::jsonb)->'receipts'->0->'payments'), 4, 'four payments applied to it');
select test.eq((:'h'::jsonb)->'receipts'->0->'draft'->>'source', 'xml', 'the draft remembers where the data came from');
-- what is pending
select public.po_pending() as pend \gset
select test.eq(jsonb_array_length((:'pend'::jsonb)->'invoices'), 1, 'one open invoice');
select test.eq((:'pend'::jsonb)->'invoices'->0->>'open_crc', '5000.00', 'open for 5 000');
select test.eq((:'pend'::jsonb)->'vendors'->0->>'open_crc', '5000.00', 'owed to Lácteos: 5 000');
select test.eq(jsonb_array_length((:'pend'::jsonb)->'receipts'), 0, 'no delivery waits for its invoice yet');
reset role;
set constraints all immediate; set constraints all deferred;
select test.eq((select string_agg(l.account || ':' || (l.debit - l.credit), ',' order by l.account) from acct.lines l join acct.entries e on e.id = l.entry_id
                 where e.source_key = 'suppay:' || public._settle_uuid('7e000000-0000-4000-8000-000000003212', 'pay', 0)), '2101:1000.00,2160:-1000.00',
               'a credit card payment goes to the credit card liability');

-- a delivery whose invoice is still to be reviewed, with ₡2 000 taken from the drawer on the spot
select test.login('cafe'); set role authenticated; select test.unlock(test.staff('ana'), '4826');
select public.po_receive_and_settle('9a000000-0000-4000-8000-000000003202', '[{"line_id":"9b000000-0000-4000-8000-000000003203","qty":5000}]',
         '7e000000-0000-4000-8000-000000003202', false,
         jsonb_build_object('mode', 'review', 'number', 'F-9', 'date', :'today', 'currency', 'CRC', 'net', 5000, 'iva', 0, 'source', 'ocr'),
         '[{"method":"register","amount_crc":2000}]', test.staff('ana'), '4826') as r2 \gset
select test.eq(((:'r2'::jsonb)->>'ok'), 'true', 'received with the invoice in review');
select test.eq(((:'r2'::jsonb)->>'invoice_status'), 'review', 'status: review');
select test.ok(((:'r2'::jsonb)->>'payout_id') is not null, 'the money taken from the drawer is recorded');
reset role;
select test.eq((select count(*)::int from public.supplier_invoices where id = '7e000000-0000-4000-8000-000000003202'), 0, 'no supplier invoice yet: nothing posted, no IVA');
select test.eq((select invoice_draft->>'number' from public.purchase_receipts where id = '7e000000-0000-4000-8000-000000003202'), 'F-9', 'the captured number waits as a draft');
select test.eq((select invoice_no from public.purchase_receipts where id = '7e000000-0000-4000-8000-000000003202'), 'F-9', 'the delivery carries the number typed at reception, as before');
select test.login('cafe'); set role authenticated; select test.unlock(test.staff('ana'), '4826');
select test.eq(public.po_receipt_settle('7e000000-0000-4000-8000-000000003202', '{"mode":"review"}', '[{"method":"register","amount_crc":500}]',
               test.staff('ana'), '4826')->>'error', 'payout_exists', 'a second payout before the invoice is refused');
select test.eq(public.po_receipt_settle('7e000000-0000-4000-8000-000000003202', '{"mode":"review"}', '[{"method":"bank","amount_crc":500}]',
               test.staff('ana'), '4826')->>'error', 'needs_invoice', 'no bank or card payment without a confirmed invoice');
select test.eq(public.po_receipt_pay('7e000000-0000-4000-8000-000000003202', '[{"method":"bank","amount_crc":500}]', gen_random_uuid(), test.staff('ana'), '4826')->>'error',
               'not_confirmed', 'nor a later payment');
select public.po_pending() as pend2 \gset
select test.eq(jsonb_array_length((:'pend2'::jsonb)->'receipts'), 1, 'the pending list shows the delivery waiting for its invoice');
select test.eq((:'pend2'::jsonb)->'receipts'->0->>'payout_crc', '2000.00', 'with the 2 000 already taken from the drawer');
-- confirming it later: the supplier corrected the number, and the invoice is in dollars
select test.eq(public.po_receipt_settle('7e000000-0000-4000-8000-000000003202', jsonb_build_object('mode', 'confirm', 'number', 'F-10', 'date', :'today', 'currency', 'USD', 'net', 10, 'iva', 1.3),
               '[]', null, null)->>'error', 'bad_rate', 'a dollar invoice needs its exchange rate');
select public.po_receipt_settle('7e000000-0000-4000-8000-000000003202',
         jsonb_build_object('mode', 'confirm', 'number', 'F-10', 'date', :'today', 'currency', 'USD', 'fx_rate', 520, 'net', 10, 'iva', 1.3, 'source', 'manual'), '[]', null, null) as r3 \gset
select test.eq(((:'r3'::jsonb)->>'ok'), 'true', 'confirmed later, without typing a PIN (no new payment)');
select test.eq(((:'r3'::jsonb)->>'total_crc'), '5876.00', '$11.30 at 520 = ₡5 876');
select test.eq(((:'r3'::jsonb)->>'paid_crc'), '2000.00', 'the payout taken earlier is documented against it');
select test.eq(((:'r3'::jsonb)->>'open_crc'), '3876.00', 'balance 3 876');
reset role;
select test.eq((select currency || '|' || fx_rate || '|' || net_fx || '|' || iva_fx || '|' || net_crc || '|' || iva_crc from public.supplier_invoices where id = '7e000000-0000-4000-8000-000000003202'),
               'USD|520.00|10.00|1.30|5200.00|676.00', 'the dollar invoice keeps its rate and its dollar amounts; the books stay in colones');
select test.eq((select invoice_no || ':' || invoice_status from public.purchase_receipts where id = '7e000000-0000-4000-8000-000000003202'), 'F-10:confirmed',
               'the delivery now carries the confirmed number');
select test.eq((select p.paid_from || ':' || p.amount_crc || ':' || (p.payout_id = (select payout_id from public.purchase_receipts where id = '7e000000-0000-4000-8000-000000003202'))
                  from public.supplier_payments p join public.supplier_payment_allocations a on a.payment_id = p.id where a.invoice_id = '7e000000-0000-4000-8000-000000003202'),
               'payout:2000.00:true', 'the earlier payout is the payment that documents it');
select test.eq((select count(*)::int from public.cash_movements where purpose = 'payout' and voided_at is null), 2, 'two payouts in all, none doubled');

-- an order made without a supplier: received with the invoice pending; the supplier is chosen when the invoice is confirmed
select test.login('cafe'); set role authenticated; select test.unlock(test.staff('ana'), '4826');
select public.po_receive_and_settle('9a000000-0000-4000-8000-000000003203', '[{"line_id":"9b000000-0000-4000-8000-000000003204","qty":500}]',
         '7e000000-0000-4000-8000-000000003203') as r4 \gset
select test.eq(((:'r4'::jsonb)->>'ok') || ':' || (((:'r4'::jsonb)->>'invoice_status')), 'true:pending', 'received, invoice pending');
select test.eq(public.po_receipt_settle('7e000000-0000-4000-8000-000000003203', jsonb_build_object('mode', 'confirm', 'number', 'V-1', 'date', :'today', 'net', 3000, 'iva', 0),
               '[]')->>'error', 'no_vendor', 'confirming needs a supplier');
select test.eq(public.po_receipt_settle('7e000000-0000-4000-8000-000000003203',
               jsonb_build_object('mode', 'confirm', 'vendor_id', '5b000000-0000-4000-8000-000000003202', 'date', :'today', 'net', 3000, 'iva', 0), '[]')->>'ok', 'true',
               'with the supplier chosen, and no invoice number, it is confirmed');
reset role;
select test.eq((select vendor_id::text from public.purchase_orders where id = '9a000000-0000-4000-8000-000000003203'), '5b000000-0000-4000-8000-000000003202', 'the order now has its supplier');
select test.ok((select invoice_no like 'S/N-%' from public.purchase_receipts where id = '7e000000-0000-4000-8000-000000003203'), 'a receipt without a number gets a provisional one');
-- the same invoice number of the same supplier twice is refused, even from another delivery
select test.login('cafe'); set role authenticated; select test.unlock(test.staff('ana'), '4826');
insert into public.purchase_orders (id, vendor_id, status) values ('9a000000-0000-4000-8000-000000003204', '5b000000-0000-4000-8000-000000003201', 'sent');
insert into public.purchase_lines (id, po_id, item_id, packs, qty, unit_cost) values ('9b000000-0000-4000-8000-000000003205', '9a000000-0000-4000-8000-000000003204', '5a000000-0000-4000-8000-000000003201', 1, 1000, 1);
select test.eq(public.po_receive_and_settle('9a000000-0000-4000-8000-000000003204', '[{"line_id":"9b000000-0000-4000-8000-000000003205","qty":1000}]',
         '7e000000-0000-4000-8000-000000003204', false, jsonb_build_object('mode', 'confirm', 'number', 'f-500', 'date', :'today', 'net', 1000, 'iva', 0), '[]')->>'error',
         'duplicate_invoice', 'the same invoice number of the same supplier is refused');
select test.eq((select count(*)::int from public.purchase_receipts where id = '7e000000-0000-4000-8000-000000003204'), 0, 'and that delivery was not saved');
-- the owner's own login (phone code) may receive too
reset role; select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.po_receive_and_settle('9a000000-0000-4000-8000-000000003204', '[{"line_id":"9b000000-0000-4000-8000-000000003205","qty":1000}]',
         '7e000000-0000-4000-8000-000000003204', false, jsonb_build_object('mode', 'pending'), '[]')->>'ok', 'true', 'the owner with the phone code receives');

-- ---- follow-ups of the review (D-041): the PIN count, the account code, cents, voids, Contabilidad's own paths ----
reset role;
select test.eq((select name from acct.accounts where code = '2160'), 'Tarjeta de crédito por pagar', 'the credit card account has a code of its own');
select test.eq((select name from acct.accounts where code = '2120'), 'Anticipos de clientes (cuentas abiertas)', 'the customer advances account of 0013 is untouched');
insert into public.purchase_orders (id, vendor_id, status)
  select ('9a000000-0000-4000-8000-0000000032' || n)::uuid, case when n = '11' then '5b000000-0000-4000-8000-000000003202'::uuid when n = '12' then null else '5b000000-0000-4000-8000-000000003201'::uuid end, 'sent'
    from unnest(array['06', '07', '08', '09', '10', '11', '12', '13', '15', '16', '17']) n;
insert into public.purchase_lines (id, po_id, item_id, packs, qty, unit_cost)
  select ('9b000000-0000-4000-8000-0000000032' || n)::uuid, ('9a000000-0000-4000-8000-0000000032' || n)::uuid, '5a000000-0000-4000-8000-000000003201', 1, q, 1
    from unnest(array['06', '07', '08', '09', '10', '11', '12', '13', '15', '16', '17'], array[1000, 1234, 1000, 3000, 1000, 500, 700, 1000, 2000, 1500, 300]) as u(n, q);
select failed_pins as fp0 from public.staff where id = test.staff('ana') \gset
select test.login('cafe'); set role authenticated; select test.unlock(test.staff('ana'), '4826');
-- 1. a wrong PIN is counted even though the delivery is rolled back
select test.eq(public.po_receive_and_settle('9a000000-0000-4000-8000-000000003206', '[{"line_id":"9b000000-0000-4000-8000-000000003206","qty":1000}]', '7e000000-0000-4000-8000-000000003206', false,
         jsonb_build_object('mode', 'pending'), '[{"method":"register","amount_crc":500}]', test.staff('ana'), '0000')->>'step', 'pin', 'a wrong PIN with a register payout is refused');
reset role;
select test.eq((select failed_pins from public.staff where id = test.staff('ana')), :fp0 + 1, 'and the wrong try stays counted');
select test.eq((select count(*)::int from public.purchase_receipts where id = '7e000000-0000-4000-8000-000000003206'), 0, 'nothing of that delivery was saved');
select test.login('cafe'); set role authenticated; select test.unlock(test.staff('ana'), '4826');
select test.eq(public.po_receive_and_settle('9a000000-0000-4000-8000-000000003206', '[{"line_id":"9b000000-0000-4000-8000-000000003206","qty":1000}]', '7e000000-0000-4000-8000-000000003206', false,
         jsonb_build_object('mode', 'pending'), '[{"method":"register","amount_crc":500}]', test.staff('ana'), '4826')->>'ok', 'true', 'the right PIN saves it');
reset role;
select test.eq((select failed_pins from public.staff where id = test.staff('ana')), 0, 'and clears the count');
select test.login('cafe'); set role authenticated; select test.unlock(test.staff('ana'), '4826');
-- the same request again (a lost answer): nothing more leaves the drawer
select public.po_receive_and_settle('9a000000-0000-4000-8000-000000003206', '[{"line_id":"9b000000-0000-4000-8000-000000003206","qty":1000}]', '7e000000-0000-4000-8000-000000003206', false,
         jsonb_build_object('mode', 'pending'), '[{"method":"register","amount_crc":500}]', test.staff('ana'), '4826') as rr \gset
select test.eq(((:'rr'::jsonb)->>'ok') || '|' || ((:'rr'::jsonb)->>'repeat'), 'true|true', 'the retry is a repeat');
reset role;
select test.eq((select count(*)::int from public.cash_movements m join public.purchase_receipts r on r.payout_id = m.id where r.id = '7e000000-0000-4000-8000-000000003206'), 1, 'one withdrawal');
select test.eq((select count(*)::int from public.cash_movements where amount_crc = 500 and purpose = 'payout'), 1, 'and only one of 500');
select test.login('cafe'); set role authenticated; select test.unlock(test.staff('ana'), '4826');
-- 2. cents: whole-colón payments pay an invoice with cents in full; one colón or more over is refused
select public.po_receive_and_settle('9a000000-0000-4000-8000-000000003207', '[{"line_id":"9b000000-0000-4000-8000-000000003207","qty":1234}]', '7e000000-0000-4000-8000-000000003207', false,
         jsonb_build_object('mode', 'confirm', 'number', 'C-1', 'date', :'today', 'net', 1234, 'iva', 160.42), '[{"method":"bank","amount_crc":1395}]', test.staff('ana'), '4826') as rc \gset
select test.eq(((:'rc'::jsonb)->>'ok') || '|' || ((:'rc'::jsonb)->>'total_crc') || '|' || ((:'rc'::jsonb)->>'paid_crc') || '|' || ((:'rc'::jsonb)->>'open_crc'), 'true|1394.42|1394.42|0.00',
               '1 395 pays an invoice of 1 394,42 in full (cash has no cents)');
select test.eq(public.po_receive_and_settle('9a000000-0000-4000-8000-000000003208', '[{"line_id":"9b000000-0000-4000-8000-000000003208","qty":1000}]', '7e000000-0000-4000-8000-000000003208', false,
         jsonb_build_object('mode', 'confirm', 'number', 'C-2', 'date', :'today', 'net', 1000, 'iva', 0), '[{"method":"bank","amount_crc":1001}]', test.staff('ana'), '4826')->>'error', 'over_invoice',
         'one colón over is still too much');
select test.eq(public.po_receive_and_settle('9a000000-0000-4000-8000-000000003208', '[{"line_id":"9b000000-0000-4000-8000-000000003208","qty":1000}]', '7e000000-0000-4000-8000-000000003208', false,
         jsonb_build_object('mode', 'confirm', 'number', 'C-2', 'date', :'today', 'net', 1000, 'iva', 0), '[{"method":"bank","amount_crc":1000.99}]', test.staff('ana'), '4826')->>'paid_crc', '1000.00',
         '1 000,99 pays exactly 1 000');
-- 3. a voided withdrawal gives way to a new one; the confirmation documents the live one
select test.eq(public.po_receive_and_settle('9a000000-0000-4000-8000-000000003209', '[{"line_id":"9b000000-0000-4000-8000-000000003209","qty":3000}]', '7e000000-0000-4000-8000-000000003209', false,
         jsonb_build_object('mode', 'review', 'number', 'R-1', 'date', :'today', 'net', 3000, 'iva', 390), '[{"method":"register","amount_crc":2000}]', test.staff('ana'), '4826')->>'ok', 'true', 'review with 2 000 from the drawer');
select payout_id as p1 from public.purchase_receipts where id = '7e000000-0000-4000-8000-000000003209' \gset
select test.eq(public.register_cash_void(test.staff('ana'), '4826', :'p1', 'era otro monto')->>'ok', 'true', 'the withdrawal is voided at the POS');
select test.eq(public.po_receipt_settle('7e000000-0000-4000-8000-000000003209', jsonb_build_object('mode', 'review', 'number', 'R-1', 'date', :'today', 'net', 3000, 'iva', 390),
         '[{"method":"register","amount_crc":2500}]', test.staff('ana'), '4826')->>'ok', 'true', 'the right amount is taken again');
select payout_id as p2 from public.purchase_receipts where id = '7e000000-0000-4000-8000-000000003209' \gset
select test.ok(:'p2'::uuid <> :'p1'::uuid, 'a new withdrawal, not the voided one');
reset role;
select test.eq((select amount_crc::text || '|' || (voided_at is null) from public.cash_movements where id = :'p2'), '2500.00|true', 'of 2 500, live');
select test.login('cafe'); set role authenticated; select test.unlock(test.staff('ana'), '4826');
select public.po_receipt_settle('7e000000-0000-4000-8000-000000003209', jsonb_build_object('mode', 'confirm', 'number', 'R-1', 'date', :'today', 'net', 3000, 'iva', 390), '[]') as r9 \gset
select test.eq(((:'r9'::jsonb)->>'paid_crc') || '|' || ((:'r9'::jsonb)->>'open_crc'), '2500.00|890.00', 'the confirmation documents the live withdrawal only');
reset role;
select test.eq((select count(*)::int from public.supplier_payments where payout_id = :'p1'), 0, 'nothing documents the voided one');
select test.login('cafe'); set role authenticated; select test.unlock(test.staff('ana'), '4826');
-- 4. a withdrawal the accountant already documented is not documented twice
select test.eq(public.po_receive_and_settle('9a000000-0000-4000-8000-000000003210', '[{"line_id":"9b000000-0000-4000-8000-000000003210","qty":1000}]', '7e000000-0000-4000-8000-000000003210', false,
         jsonb_build_object('mode', 'pending'), '[{"method":"register","amount_crc":1000}]', test.staff('ana'), '4826')->>'ok', 'true', 'pending with 1 000 from the drawer');
select payout_id as p3 from public.purchase_receipts where id = '7e000000-0000-4000-8000-000000003210' \gset
reset role; select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.expense_save(jsonb_build_object('date', public.cr_today(), 'description', 'Lácteos, pagado de caja', 'vendor_name', 'Lácteos Monteverde', 'account', '6204', 'amount_crc', 1000,
         'iva_crc', 0, 'paid_from', 'payout', 'payout_id', :'p3'), gen_random_uuid())->>'ok', 'true', 'the accountant documents it as an expense');
reset role; select test.login('cafe'); set role authenticated; select test.unlock(test.staff('ana'), '4826');
select test.eq((public.po_history('9a000000-0000-4000-8000-000000003210')->'receipts'->0->'payout'->>'documented'), 'true', 'the history knows it is documented');
select public.po_receipt_settle('7e000000-0000-4000-8000-000000003210', jsonb_build_object('mode', 'confirm', 'number', 'P-1', 'date', :'today', 'net', 1000, 'iva', 0), '[]') as r10 \gset
select test.eq(((:'r10'::jsonb)->>'ok') || '|' || ((:'r10'::jsonb)->>'paid_crc'), 'true|0.00', 'the confirmation does not document it again');
reset role;
select test.eq((select count(*)::int from public.supplier_payments where payout_id = :'p3'), 0, 'no second record of that money');
select test.login('cafe'); set role authenticated; select test.unlock(test.staff('ana'), '4826');
-- 5. an invoice the accountant voids sends the delivery back to review; confirming again takes a fresh invoice id
select test.eq(public.po_receive_and_settle('9a000000-0000-4000-8000-000000003211', '[{"line_id":"9b000000-0000-4000-8000-000000003211","qty":500}]', '7e000000-0000-4000-8000-000000003211', false,
         jsonb_build_object('mode', 'confirm', 'number', 'V-1', 'date', :'today', 'net', 500, 'iva', 0), '[]')->>'invoice_id', '7e000000-0000-4000-8000-000000003211', 'the first invoice takes the delivery''s id');
reset role; select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.supplier_invoice_void('7e000000-0000-4000-8000-000000003211', 'número equivocado')->>'ok', 'true', 'the accountant voids it');
reset role;
select test.eq((select invoice_status || '|' || (invoice_id is null) from public.purchase_receipts where id = '7e000000-0000-4000-8000-000000003211'), 'review|true', 'the delivery waits for its invoice again');
select test.login('cafe'); set role authenticated; select test.unlock(test.staff('ana'), '4826');
select test.eq((select count(*) from jsonb_array_elements(public.po_pending()->'receipts') x where x->>'id' = '7e000000-0000-4000-8000-000000003211'), 1::bigint, 'and is listed as pending');
select public.po_receipt_settle('7e000000-0000-4000-8000-000000003211', jsonb_build_object('mode', 'confirm', 'number', 'V-2', 'date', :'today', 'net', 600, 'iva', 0), '[]') as r11 \gset
select test.eq(((:'r11'::jsonb)->>'ok') || '|' || (((:'r11'::jsonb)->>'invoice_id') <> '7e000000-0000-4000-8000-000000003211'), 'true|true', 'confirmed again with a fresh invoice id');
reset role;
select test.eq((select i.number || '|' || r.invoice_status from public.purchase_receipts r join public.supplier_invoices i on i.id = r.invoice_id where r.id = '7e000000-0000-4000-8000-000000003211'), 'V-2|confirmed', 'linked to the new invoice');
select test.login('cafe'); set role authenticated; select test.unlock(test.staff('ana'), '4826');
-- 6. an invoice saved from Contabilidad confirms the delivery too, and it leaves the pending list
select test.eq(public.po_receive_and_settle('9a000000-0000-4000-8000-000000003213', '[{"line_id":"9b000000-0000-4000-8000-000000003213","qty":1000}]', '7e000000-0000-4000-8000-000000003213', false,
         jsonb_build_object('mode', 'pending'), '[]')->>'ok', 'true', 'received, invoice pending');
reset role; select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.supplier_invoice_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000003201', 'number', 'A-1', 'date', :'today', 'net_crc', 1000, 'iva_crc', 0,
         'receipt_ids', jsonb_build_array('7e000000-0000-4000-8000-000000003213')), gen_random_uuid())->>'ok', 'true', 'the accountant records the invoice from Contabilidad');
reset role;
select test.eq((select invoice_status || '|' || (invoice_id is not null) from public.purchase_receipts where id = '7e000000-0000-4000-8000-000000003213'), 'confirmed|true', 'the delivery is confirmed by it');
select test.login('cafe'); set role authenticated; select test.unlock(test.staff('ana'), '4826');
select test.eq((select count(*) from jsonb_array_elements(public.po_pending()->'receipts') x where x->>'id' = '7e000000-0000-4000-8000-000000003213'), 0::bigint, 'and is no longer pending');
select test.eq(public.po_receipt_pay('7e000000-0000-4000-8000-000000003213', '[{"method":"bank","amount_crc":400}]', 'ab000000-0000-4000-8000-000000003213', test.staff('ana'), '4826')->>'open_crc', '600.00',
               'and takes payments from the page');
-- 7. one invoice over two deliveries: only the first carries the number; a delivery with live drawer money is settled on its own
select test.eq(public.po_receive_and_settle('9a000000-0000-4000-8000-000000003215', '[{"line_id":"9b000000-0000-4000-8000-000000003215","qty":2000}]', '7e000000-0000-4000-8000-000000003215', false, '{"mode":"pending"}', '[]')->>'ok', 'true', 'delivery A');
select test.eq(public.po_receive_and_settle('9a000000-0000-4000-8000-000000003216', '[{"line_id":"9b000000-0000-4000-8000-000000003216","qty":1500}]', '7e000000-0000-4000-8000-000000003216', false, '{"mode":"pending"}', '[]')->>'ok', 'true', 'delivery B');
select test.eq(public.po_receive_and_settle('9a000000-0000-4000-8000-000000003217', '[{"line_id":"9b000000-0000-4000-8000-000000003217","qty":300}]', '7e000000-0000-4000-8000-000000003217', false, '{"mode":"review"}',
         '[{"method":"register","amount_crc":300}]', test.staff('ana'), '4826')->>'ok', 'true', 'delivery C, paid from the drawer');
select test.eq(public.po_receipt_settle('7e000000-0000-4000-8000-000000003215', jsonb_build_object('mode', 'confirm', 'number', 'AB-1', 'date', :'today', 'net', 3500, 'iva', 0,
         'receipt_ids', jsonb_build_array('7e000000-0000-4000-8000-000000003217')), '[]')->>'error', 'bad_receipts', 'C''s drawer money is settled from C, not here');
select public.po_receipt_settle('7e000000-0000-4000-8000-000000003215', jsonb_build_object('mode', 'confirm', 'number', 'AB-1', 'date', :'today', 'net', 3500, 'iva', 0,
         'receipt_ids', jsonb_build_array('7e000000-0000-4000-8000-000000003216')), '[]') as rab \gset
select test.eq(((:'rab'::jsonb)->>'ok') || '|' || ((:'rab'::jsonb)->>'total_crc'), 'true|3500.00', 'one invoice for A and B');
reset role;
select test.eq((select string_agg(coalesce(invoice_no, '-') || ':' || invoice_status || ':' || (invoice_id = ((:'rab'::jsonb)->>'invoice_id')::uuid)::text, ',' order by id)
                  from public.purchase_receipts where id in ('7e000000-0000-4000-8000-000000003215', '7e000000-0000-4000-8000-000000003216')), 'AB-1:confirmed:true,-:confirmed:true',
               'A carries the number, B is linked by the invoice');
select test.login('cafe'); set role authenticated; select test.unlock(test.staff('ana'), '4826');
-- 8. an order without a supplier, received with a number that supplier already used: refused by name, not by a raw error
select test.eq(public.po_receive_and_settle('9a000000-0000-4000-8000-000000003212', '[{"line_id":"9b000000-0000-4000-8000-000000003212","qty":700}]', '7e000000-0000-4000-8000-000000003212', false,
         jsonb_build_object('mode', 'pending', 'number', 'c-1'), '[]')->>'ok', 'true', 'received without a supplier, number c-1 typed');
select test.eq(public.po_receipt_settle('7e000000-0000-4000-8000-000000003212', jsonb_build_object('mode', 'confirm', 'vendor_id', '5b000000-0000-4000-8000-000000003201', 'date', :'today', 'net', 700, 'iva', 0), '[]')->>'error',
               'duplicate_invoice', 'that supplier already has a C-1');
reset role;
select test.done();
rollback;
