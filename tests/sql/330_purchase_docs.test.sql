-- Migration 0030: the invoice file of a delivery in the private bucket purchase-invoices; who may upload and see it.
begin;
insert into public.vendors (id, name) values ('5b000000-0000-4000-8000-000000003301', 'Panadería Sol');
insert into public.stock_items (id, name, unit, pack_qty, cost_per_pack) values ('5a000000-0000-4000-8000-000000003301', 'Pan', 'unit', 10, 3000);
insert into public.purchase_orders (id, vendor_id, status) values ('9a000000-0000-4000-8000-000000003301', '5b000000-0000-4000-8000-000000003301', 'sent');
insert into public.purchase_lines (id, po_id, item_id, packs, qty, unit_cost) values ('9b000000-0000-4000-8000-000000003301', '9a000000-0000-4000-8000-000000003301', '5a000000-0000-4000-8000-000000003301', 2, 20, 300);

select test.eq((select public from storage.buckets where id = 'purchase-invoices'), false, 'the bucket is private');
select test.eq((select file_size_limit from storage.buckets where id = 'purchase-invoices'), 10485760::bigint, '10 MB per file');
select test.ok((select 'application/pdf' = any(allowed_mime_types) and 'image/jpeg' = any(allowed_mime_types) and not ('text/html' = any(allowed_mime_types))
                  from storage.buckets where id = 'purchase-invoices'), 'only images, PDF and XML');
select test.eq((select count(*)::int from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname like 'purchase invoices%'), 2, 'a read rule and an add rule');
select test.eq((select count(*)::int from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname like 'purchase invoices%' and cmd in ('UPDATE', 'DELETE')), 0,
               'no rule replaces or deletes a filed invoice');

-- a café device with a manager PIN receives a delivery
select test.login('cafe'); set role authenticated; select test.unlock(test.staff('ana'), '4826');
select test.eq(public.po_receive_and_settle('9a000000-0000-4000-8000-000000003301', '[{"line_id":"9b000000-0000-4000-8000-000000003301","qty":20}]',
               '7e000000-0000-4000-8000-000000003301')->>'ok', 'true', 'delivery received');
-- Storage never sees the PIN header: the rule reads the login's live unlock instead
select set_config('request.headers', '{}', false);
select test.eq(public._login_unlocked(), true, 'the café login with a live manager unlock may handle the files, header or not');
select test.lives($$insert into storage.objects (bucket_id, name) values ('purchase-invoices', '7e000000-0000-4000-8000-000000003301/factura-1.jpg')$$, 'the first photo goes up');
-- registered on the delivery (the page's calls carry the PIN header again)
select test.unlock(test.staff('ana'), '4826');
select test.eq(public.purchase_doc_attach('7e000000-0000-4000-8000-000000003301', '7e000000-0000-4000-8000-000000003301/factura-1.jpg')->>'kind', 'image', 'the photo is registered');
select test.eq(public.purchase_doc_attach('7e000000-0000-4000-8000-000000003301', '7e000000-0000-4000-8000-000000003301/factura-1.jpg')->>'repeat', 'true', 'registering it again changes nothing');
select set_config('request.headers', '{}', false);
select test.lives($$insert into storage.objects (bucket_id, name) values ('purchase-invoices', '7e000000-0000-4000-8000-000000003301/factura-2.jpg')$$, 'the second page too');
select test.lives($$insert into storage.objects (bucket_id, name) values ('purchase-invoices', '7e000000-0000-4000-8000-000000003301/factura-3.pdf')$$, 'and a third file');
select test.throws($$insert into storage.objects (bucket_id, name) values ('purchase-invoices', '7e000000-0000-4000-8000-000000003301/factura-4.jpg')$$, 'row-level security',
                   'a fourth file is refused');
select test.throws($$insert into storage.objects (bucket_id, name) values ('purchase-invoices', '7e000000-0000-4000-8000-000000003399/x.jpg')$$, 'row-level security',
                   'no upload into the folder of a delivery that does not exist');
select test.throws($$insert into storage.objects (bucket_id, name) values ('purchase-invoices', 'suelto.jpg')$$, 'row-level security', 'nor outside a delivery folder');
select test.throws($$insert into storage.objects (bucket_id, name) values ('expense-receipts', '7e000000-0000-4000-8000-000000003301/factura-1.jpg')$$, 'row-level security',
                   'the expenses bucket keeps its own rule');
select test.eq((select count(*)::int from storage.objects where bucket_id = 'purchase-invoices'), 3, 'the device sees the three files');
-- the second page reached Storage but its registration was lost (weak connection): registering the third registers it too
select test.unlock(test.staff('ana'), '4826');
select public.purchase_doc_attach('7e000000-0000-4000-8000-000000003301', '7e000000-0000-4000-8000-000000003301/factura-3.pdf') as a3 \gset
select test.eq(((:'a3'::jsonb)->>'kind') || '|' || (((:'a3'::jsonb)->>'files')), 'pdf|3', 'the PDF is registered, and the orphan page with it');
select test.eq(public.purchase_doc_attach('7e000000-0000-4000-8000-000000003301', '7e000000-0000-4000-8000-000000003301/factura-2.jpg')->>'repeat', 'true', 'the orphan page is already registered');
reset role;
select test.eq((select string_agg(kind, ',' order by path) from public.purchase_receipt_files where receipt_id = '7e000000-0000-4000-8000-000000003301'), 'image,image,pdf', 'three files, in order');
select test.login('cafe'); set role authenticated; select test.unlock(test.staff('ana'), '4826');
select test.eq(public.purchase_doc_attach('7e000000-0000-4000-8000-000000003301', '7e000000-0000-4000-8000-000000003301/factura-4.jpg')->>'error', 'too_many', 'three is the limit');
select test.eq(public.purchase_doc_attach('7e000000-0000-4000-8000-000000003301', 'otra/factura.jpg')->>'error', 'bad_path', 'only a file in the delivery''s own folder');
select test.eq(public.purchase_doc_attach('7e000000-0000-4000-8000-000000003399', '7e000000-0000-4000-8000-000000003399/x.jpg')->>'error', 'not_found', 'a delivery that does not exist');
select test.eq(jsonb_array_length(public.po_history('9a000000-0000-4000-8000-000000003301')->'receipts'->0->'files'), 3, 'the history lists the three files');
-- a filed invoice is never changed or deleted from a page (no rule: zero rows touched)
update storage.objects set name = 'x' where bucket_id = 'purchase-invoices';
delete from storage.objects where bucket_id = 'purchase-invoices';
select test.eq((select count(*)::int from storage.objects where bucket_id = 'purchase-invoices' and name like '7e000000-0000-4000-8000-000000003301/%'), 3, 'the files stay as they were');
reset role;
-- the same café login once its unlock is gone sees nothing and uploads nothing
delete from public.access_unlocks;
select test.login('cafe'); set role authenticated;
select test.eq(public._login_unlocked(), false, 'a café login without a live unlock may not');
select test.eq((select count(*)::int from storage.objects where bucket_id = 'purchase-invoices'), 0, 'a locked café device sees no invoice file');
select test.throws($$insert into storage.objects (bucket_id, name) values ('purchase-invoices', '7e000000-0000-4000-8000-000000003301/factura-4.jpg')$$, 'row-level security', 'nor uploads one');
select test.eq(public.purchase_doc_attach('7e000000-0000-4000-8000-000000003301', '7e000000-0000-4000-8000-000000003301/factura-4.jpg')->>'error', 'not_allowed', 'nor registers one');
reset role;
-- the owner with the phone code and the accountant see them
select test.login('owner', 'aal2'); set role authenticated;
select test.eq((select count(*)::int from storage.objects where bucket_id = 'purchase-invoices'), 3, 'the owner with the phone code sees the files');
reset role;
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq((select count(*)::int from storage.objects where bucket_id = 'purchase-invoices'), 3, 'the accountant sees the files');
reset role;
select test.login('anon'); set role anon;
select test.eq((select count(*)::int from storage.objects where bucket_id = 'purchase-invoices'), 0, 'visitors see nothing');
reset role;
select test.done();
rollback;
