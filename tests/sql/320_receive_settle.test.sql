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
select test.eq((select account from acct.mappings where key = 'from_card_credit'), '2120', 'credit card payments map to their own liability account');
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
select test.eq((:'r0'::jsonb)->>'error', 'not_open', 'cash from the register needs an open register day');
select test.eq((:'r0'::jsonb)->>'step', 'register', 'and the answer says which step refused');
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
select test.eq((:'r1'::jsonb)->>'ok', 'true', 'the delivery, the invoice and two payments are saved in one call');
select test.eq((:'r1'::jsonb)->>'status', 'received', 'the order is received');
select test.eq((:'r1'::jsonb)->>'invoice_status', 'confirmed', 'the invoice is confirmed');
select test.eq(((:'r1'::jsonb)->>'total_crc')::numeric, 18080::numeric, 'invoice total 18 080');
select test.eq(((:'r1'::jsonb)->>'paid_crc')::numeric, 8080::numeric, 'paid 8 080');
select test.eq(((:'r1'::jsonb)->>'open_crc')::numeric, 10000::numeric, 'balance 10 000 on credit');
-- the same call again: nothing doubles
select public.po_receive_and_settle('9a000000-0000-4000-8000-000000003201',
         '[{"line_id":"9b000000-0000-4000-8000-000000003201","qty":10000},{"line_id":"9b000000-0000-4000-8000-000000003202","qty":1000}]',
         '7e000000-0000-4000-8000-000000003201', false,
         jsonb_build_object('mode', 'confirm', 'number', 'F-500', 'date', :'today', 'due_date', :'due', 'currency', 'CRC', 'net', 16000, 'iva', 2080),
         '[{"method":"register","amount_crc":5000},{"method":"card_debit","amount_crc":3080}]', test.staff('ana'), '4826') as r1b \gset
select test.eq((:'r1b'::jsonb)->>'repeat', 'true', 'the same confirmation sent twice is saved once');
select test.eq((:'r1b'::jsonb)->>'ok', 'true', 'and answers ok');
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
                 where e.source_key = 'suppay:' || public._settle_uuid('7e000000-0000-4000-8000-000000003212', 'pay', 0)), '2101:1000.00,2120:-1000.00',
               'a credit card payment goes to the credit card liability');

-- a delivery whose invoice is still to be reviewed, with ₡2 000 taken from the drawer on the spot
select test.login('cafe'); set role authenticated; select test.unlock(test.staff('ana'), '4826');
select public.po_receive_and_settle('9a000000-0000-4000-8000-000000003202', '[{"line_id":"9b000000-0000-4000-8000-000000003203","qty":5000}]',
         '7e000000-0000-4000-8000-000000003202', false,
         jsonb_build_object('mode', 'review', 'number', 'F-9', 'date', :'today', 'currency', 'CRC', 'net', 5000, 'iva', 0, 'source', 'ocr'),
         '[{"method":"register","amount_crc":2000}]', test.staff('ana'), '4826') as r2 \gset
select test.eq((:'r2'::jsonb)->>'ok', 'true', 'received with the invoice in review');
select test.eq((:'r2'::jsonb)->>'invoice_status', 'review', 'status: review');
select test.ok((:'r2'::jsonb)->>'payout_id' is not null, 'the money taken from the drawer is recorded');
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
select test.eq((:'r3'::jsonb)->>'ok', 'true', 'confirmed later, without typing a PIN (no new payment)');
select test.eq((:'r3'::jsonb)->>'total_crc', '5876.00', '$11.30 at 520 = ₡5 876');
select test.eq((:'r3'::jsonb)->>'paid_crc', '2000.00', 'the payout taken earlier is documented against it');
select test.eq((:'r3'::jsonb)->>'open_crc', '3876.00', 'balance 3 876');
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
select test.eq((:'r4'::jsonb)->>'ok' || ':' || ((:'r4'::jsonb)->>'invoice_status'), 'true:pending', 'received, invoice pending');
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
reset role;
select test.done();
rollback;
