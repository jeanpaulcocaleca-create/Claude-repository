-- Migration 0016: supplier invoices linked to deliveries, payments, aging, voids.
begin;
-- two suppliers; three deliveries already received (owed at their cost)
insert into public.vendors (id, name) values ('5b000000-0000-4000-8000-000000001701', 'Café de Altura'),
                                             ('5b000000-0000-4000-8000-000000001702', 'Panadería Sol');
insert into public.purchase_orders (id, vendor_id, status) values ('9a000000-0000-4000-8000-000000001701', '5b000000-0000-4000-8000-000000001701', 'received'),
                                                                 ('9a000000-0000-4000-8000-000000001702', '5b000000-0000-4000-8000-000000001702', 'received');
insert into public.purchase_receipts (id, po_id, vendor_id, invoice_no, total_crc, final) values
  ('7e000000-0000-4000-8000-000000001701', '9a000000-0000-4000-8000-000000001701', '5b000000-0000-4000-8000-000000001701', 'A-1', 10000, false),
  ('7e000000-0000-4000-8000-000000001702', '9a000000-0000-4000-8000-000000001701', '5b000000-0000-4000-8000-000000001701', 'A-2', 5000, true),
  ('7e000000-0000-4000-8000-000000001703', '9a000000-0000-4000-8000-000000001702', '5b000000-0000-4000-8000-000000001702', null, 3000, true);

select test.login('cafe'); set role authenticated;
select test.eq(public.supplier_invoice_save('{"vendor_id":"5b000000-0000-4000-8000-000000001701","number":"x","net_crc":1,"date":"2026-10-01"}', gen_random_uuid())->>'error',
               'not_allowed', 'a locked café device cannot enter supplier invoices');
select test.eq(public.ap_aging()->>'error', 'not_allowed', 'nor see what is owed');
select test.unlock(test.staff('ana'), '4826');
-- invoice A-1: the delivery cost 10 000, the invoice says 10 500 + IVA 1 365
select public.supplier_invoice_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000001701', 'number', 'A-1', 'date', public.cr_today(),
       'due_date', public.cr_today() + 30, 'net_crc', 10500, 'iva_crc', 1365, 'receipt_ids', jsonb_build_array('7e000000-0000-4000-8000-000000001701')),
       '7e000000-0000-4000-8000-000000001711') as i1 \gset
select test.eq((:'i1'::jsonb)->>'ok', 'true', 'a manager with a PIN enters an invoice linked to its delivery');
select test.eq(((:'i1'::jsonb)->>'difference')::numeric, 500::numeric, 'it reports the difference against what was received');
select test.eq(public.supplier_invoice_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000001701', 'number', 'A-1', 'date', public.cr_today(),
       'net_crc', 10500, 'iva_crc', 1365, 'receipt_ids', jsonb_build_array('7e000000-0000-4000-8000-000000001701')), '7e000000-0000-4000-8000-000000001711')->>'repeat',
       'true', 'sending it again changes nothing');
select test.eq(public.supplier_invoice_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000001701', 'number', 'a-1', 'date', public.cr_today(),
       'net_crc', 10, 'account', '6299'), gen_random_uuid())->>'error', 'duplicate_invoice', 'the same invoice number of the same supplier is refused');
select test.eq(public.supplier_invoice_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000001701', 'number', 'A-9', 'date', public.cr_today(),
       'net_crc', 3000, 'receipt_ids', jsonb_build_array('7e000000-0000-4000-8000-000000001703')), gen_random_uuid())->>'error', 'bad_receipts',
       'a delivery of another supplier cannot be linked');
select test.eq(public.supplier_invoice_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000001701', 'number', 'A-9', 'date', public.cr_today(),
       'net_crc', 3000, 'receipt_ids', jsonb_build_array('7e000000-0000-4000-8000-000000001701')), gen_random_uuid())->>'error', 'bad_receipts',
       'a delivery already invoiced cannot be linked again');
select test.eq(public.supplier_invoice_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000001701', 'number', 'A-9', 'date', public.cr_today() + 1,
       'net_crc', 3000, 'account', '6299'), gen_random_uuid())->>'error', 'future_date', 'no invoices dated in the future');
select test.eq(public.supplier_invoice_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000001701', 'number', 'A-9', 'date', public.cr_today(),
       'net_crc', 3000), gen_random_uuid())->>'error', 'bad_account', 'an invoice without deliveries says what it was for');
select test.eq(public.supplier_invoice_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000001701', 'number', 'A-9', 'date', public.cr_today(),
       'net_crc', 3000, 'account', '1101'), gen_random_uuid())->>'error', 'bad_account', 'never against a cash account');
select test.eq(public.supplier_invoice_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000001701', 'number', 'A-9', 'date', public.cr_today(),
       'due_date', public.cr_today() - 1, 'net_crc', 3000, 'account', '6299'), gen_random_uuid())->>'error', 'bad_value', 'due date not before the invoice date');
-- invoice A-2: exactly what was received, no IVA: nothing more to post
select public.supplier_invoice_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000001701', 'number', 'A-2', 'date', public.cr_today() - 5,
       'net_crc', 5000, 'receipt_ids', jsonb_build_array('7e000000-0000-4000-8000-000000001702')), '7e000000-0000-4000-8000-000000001712') as i2 \gset
select test.ok((:'i2'::jsonb)->>'ok' = 'true' and (:'i2'::jsonb)->>'entry_id' is null, 'an invoice equal to the delivery, without IVA, posts nothing more');
-- an old repair invoice without a delivery, 70 days ago, due in 5 days
select test.eq(public.supplier_invoice_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000001701', 'number', 'S-77', 'date', public.cr_today() - 70,
       'due_date', public.cr_today() - 65, 'net_crc', 2000, 'iva_crc', 260, 'account', '6206'), '7e000000-0000-4000-8000-000000001713')->>'ok', 'true',
       'an invoice for a service goes to the account it names');
reset role;
set constraints all immediate; set constraints all deferred;
select test.eq((select string_agg(l.account || ':' || (l.debit - l.credit), ',' order by l.account) from acct.lines l join acct.entries e on e.id = l.entry_id
                 where e.source_key = 'supinv:7e000000-0000-4000-8000-000000001711'),
               '1140:1365.00,2101:-1865.00,5103:500.00', 'posted: IVA credit and the price difference, owed to the supplier');
select test.eq((select string_agg(l.account || ':' || (l.debit - l.credit), ',' order by l.account) from acct.lines l join acct.entries e on e.id = l.entry_id
                 where e.source_key = 'supinv:7e000000-0000-4000-8000-000000001713'),
               '1140:260.00,2101:-2260.00,6206:2000.00', 'a service: expense + IVA credit, owed to the supplier');
select test.eq((select string_agg(coalesce(invoice_id::text, '-'), ',' order by id) from public.purchase_receipts),
               '7e000000-0000-4000-8000-000000001711,7e000000-0000-4000-8000-000000001712,-', 'deliveries point to their invoice');

-- aging: S-77 (2 260) is 65 days late; A-1 (11 865) and A-2 (5 000, due in 25 days by default) are current
select test.login('accountant', 'aal2'); set role authenticated;
select public.ap_aging() as ag \gset
select test.eq((:'ag'::jsonb)#>>'{vendors,0,name}', 'Café de Altura', 'the supplier with open invoices');
select test.eq(((:'ag'::jsonb)#>>'{vendors,0,current}')::numeric, 16865::numeric, 'current: A-1 + A-2');
select test.eq(((:'ag'::jsonb)#>>'{vendors,0,older}')::numeric, 2260::numeric, 'more than 60 days late: S-77');
select test.eq(((:'ag'::jsonb)#>>'{vendors,0,total}')::numeric, 19125::numeric, 'total owed');
select test.eq(jsonb_array_length((:'ag'::jsonb)->'uninvoiced'), 1, 'the bakery delivery is still waiting for its invoice');
select test.eq(((:'ag'::jsonb)#>>'{ledger,received_not_invoiced}')::numeric, 3000::numeric, 'the tie-out shows what was received and not invoiced');

-- payments: more than owed is refused; otherwise the oldest due goes first
select test.eq(public.supplier_payment_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000001701', 'amount_crc', 19125.01, 'paid_from', 'bank',
       'date', public.cr_today()), gen_random_uuid())->>'error', 'more_than_owed', 'never pays more than is owed');
select test.eq(public.supplier_payment_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000001701', 'amount_crc', 3000, 'paid_from', 'credit',
       'date', public.cr_today()), gen_random_uuid())->>'error', 'bad_value', 'a payment leaves from cash, petty cash or the bank');
select test.eq(public.supplier_payment_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000001701', 'amount_crc', 3000, 'paid_from', 'bank',
       'date', public.cr_today(), 'reference', 'TRF 4455'), '7e000000-0000-4000-8000-000000001721')->>'ok', 'true', 'the accountant records a bank transfer');
select test.eq(public.supplier_payment_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000001701', 'amount_crc', 3000, 'paid_from', 'bank',
       'date', public.cr_today()), '7e000000-0000-4000-8000-000000001721')->>'repeat', 'true', 'sending it again changes nothing');
reset role;
select test.eq((select string_agg(i.number || ':' || a.amount_crc, ',' order by i.number) from public.supplier_payment_allocations a join public.supplier_invoices i on i.id = a.invoice_id
                 where a.payment_id = '7e000000-0000-4000-8000-000000001721'), 'A-2:740.00,S-77:2260.00', 'the oldest due is paid first, then the next');
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.supplier_payment_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000001701', 'amount_crc', 5000, 'paid_from', 'cash',
       'date', public.cr_today(), 'invoice_ids', jsonb_build_array('7e000000-0000-4000-8000-000000001711')), '7e000000-0000-4000-8000-000000001722')->>'ok', 'true',
       'the owner pays a chosen invoice');
reset role;
select test.eq((select string_agg(i.number || ':' || a.amount_crc, ',' order by i.number) from public.supplier_payment_allocations a join public.supplier_invoices i on i.id = a.invoice_id
                 where a.payment_id = '7e000000-0000-4000-8000-000000001722'), 'A-1:5000.00', 'the chosen invoice is paid first');
set constraints all immediate; set constraints all deferred;
select test.eq((select string_agg(l.account || ':' || (l.debit - l.credit), ',' order by l.account) from acct.lines l join acct.entries e on e.id = l.entry_id
                 where e.source_key = 'suppay:7e000000-0000-4000-8000-000000001722'), '1101:-5000.00,2101:5000.00', 'posted: payable against the cash drawer');

-- voids: a paid invoice cannot be voided; a payment can, and what it paid is owed again
select test.login('cafe'); set role authenticated;
select test.unlock(test.staff('ana'), '4826');
select test.eq(public.supplier_payment_void('7e000000-0000-4000-8000-000000001721', 'error')->>'error', 'not_allowed', 'a manager cannot void a payment');
reset role;
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.supplier_invoice_void('7e000000-0000-4000-8000-000000001713', 'duplicada')->>'error', 'has_payments', 'a paid invoice is not voided');
select test.eq(public.supplier_payment_void('7e000000-0000-4000-8000-000000001721', '')->>'error', 'missing_reason', 'a void needs a reason');
select test.eq(public.supplier_payment_void('7e000000-0000-4000-8000-000000001721', 'transferencia rechazada')->>'ok', 'true', 'the accountant voids a payment');
select test.eq(((public.ap_aging())#>>'{vendors,0,total}')::numeric, 14125::numeric, 'what it paid is owed again (19 125 − 5 000)');
select test.eq(public.supplier_invoice_void('7e000000-0000-4000-8000-000000001713', 'era de otro proveedor')->>'ok', 'true', 'now the invoice can be voided');
select test.eq(public.supplier_invoice_void('7e000000-0000-4000-8000-000000001712', 'número equivocado')->>'ok', 'true', 'an invoice that posted nothing is voided too');
reset role;
select test.eq((select count(*)::int from public.purchase_receipts where invoice_id is null), 2, 'its delivery can be invoiced again');
set constraints all immediate; set constraints all deferred;
select test.eq((select sum(l.debit - l.credit) from acct.lines l where l.account in ('6206')), 0::numeric, 'the voided service invoice nets to zero');
select test.ok((select bool_and(entry_id is not null and void_entry_id is not null) from public.supplier_payments where voided_at is not null), 'the void keeps both entries');
select test.done();
rollback;
