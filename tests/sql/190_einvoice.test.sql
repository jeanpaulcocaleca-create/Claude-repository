-- Migration 0018: electronic documents are recorded (shadow), never sent; off by default.
begin;
select id as latte from public.menu_items where name = 'Latte' \gset
-- off (the default): a sale records nothing
select test.eq(public.setting('einvoice_mode') #>> '{}', 'off', 'off by default');
select test.login('cafe'); set role authenticated;
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000001901', 'total_crc', 2200, 'payment_method', 'card',
       'items', jsonb_build_array(jsonb_build_object('item_name', 'Latte', 'price_crc', 2200, 'qty', 1, 'menu_item_id', :'latte'))));
reset role;
select test.eq((select count(*)::int from public.e_documents), 0, 'with the mode off, nothing is recorded');

-- shadow: each sale records a tiquete with what it lacks (CABYS)
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.setting_set('einvoice_mode', '"live"')->>'error', 'bad_value', 'there is no live sending to switch on');
select test.eq(public.setting_set('einvoice_mode', '"shadow"')->>'ok', 'true', 'the owner switches on the shadow record');
reset role;
-- yesterday's sale (its day had no register: it can only be refunded now)
insert into public.orders (id, created_at, total_crc, payment_method, paid, status)
  values ('0d000000-0000-4000-8000-000000001902', now() - interval '1 day', 4400, 'card', true, 'done');
insert into public.order_items (order_id, item_name, price_crc, qty) values ('0d000000-0000-4000-8000-000000001902', 'Latte', 2200, 2);
select test.eq((select kind || ':' || status || ':' || total_crc || ':' || tax_crc from public.e_documents where order_id = '0d000000-0000-4000-8000-000000001902'),
               'TE:pending:4400.00:506.00', 'a tiquete waits, with the sale''s total and IVA');
select test.eq((select missing::text from public.e_documents where order_id = '0d000000-0000-4000-8000-000000001902'), '{cabys:Latte}', 'it says the product has no CABYS');
update public.menu_items set cabys = '2399999009900' where id = :'latte';
select test.login('cafe'); set role authenticated;
select public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000001903', 'total_crc', 2200, 'payment_method', 'cash_crc',
       'items', jsonb_build_array(jsonb_build_object('item_name', 'Latte', 'price_crc', 2200, 'qty', 1, 'menu_item_id', :'latte'))));
-- the customer asks for an invoice with their ID
select test.eq(public.einvoice_request_fe('0d000000-0000-4000-8000-000000001903', '{"name":"","id_type":"fisica","id_number":"112340567"}')->>'error',
               'bad_value', 'a name and an ID are needed');
select test.eq(public.einvoice_request_fe('0d000000-0000-4000-8000-000000001903', '{"name":"X","id_type":"pasaporte","id_number":"112340567"}')->>'error',
               'bad_value', 'only the listed ID types');
select test.eq(public.einvoice_request_fe('0d000000-0000-4000-8000-000000001903', '{"name":"Ana Mora","id_type":"fisica","id_number":"1-1234-0567","email":"ana@example.com"}')->>'ok',
               'true', 'the cashier writes down who asked for an invoice');
select test.eq(public.einvoice_request_fe('0d000000-0000-4000-8000-000000001903', '{"name":"Otra","id_type":"fisica","id_number":"999999999"}')->>'error',
               'too_late', 'once written, the cashier cannot overwrite it');
reset role;
select test.eq((select kind || ':' || (receiver->>'id_number') || ':' || coalesce(array_length(missing, 1), 0) from public.e_documents
                 where order_id = '0d000000-0000-4000-8000-000000001903'), 'FE:112340567:0', 'an invoice with the ID, nothing missing once the product has its CABYS');

-- a refund gets a credit note pointing to the sale's document; a void cancels a pending one
select test.login('cafe'); set role authenticated;
select public.manager_refund_order(test.staff('ana'), '4826', '0d000000-0000-4000-8000-000000001902', 'cliente insatisfecho') as rf \gset
select test.eq((:'rf'::jsonb)->>'ok', 'true', 'a refund of yesterday''s shadow sale');
reset role;
select test.eq((select n.kind || ':' || (n.reference_id = s.id)::text || ':' || n.total_crc || ':' || n.tax_crc
                  from public.e_documents n join public.orders o on o.id = n.order_id join public.e_documents s on s.order_id = o.refund_of
                 where o.refund_of = '0d000000-0000-4000-8000-000000001902'), 'NC:true:-4400.00:-506.00', 'credit note linked to the tiquete, with the IVA given back');
select test.login('cafe'); set role authenticated;
select test.eq(public.manager_void_order(test.staff('ana'), '4826', '0d000000-0000-4000-8000-000000001903', 'error de cobro')->>'ok', 'true', 'today''s sale voided');
reset role;
select test.eq((select status from public.e_documents where order_id = '0d000000-0000-4000-8000-000000001903'), 'cancelled', 'a voided sale cancels its pending document');

-- the page can never change a document's state; the connector moves it forward only
select test.login('owner', 'aal2'); set role authenticated;
select test.throws($$update public.e_documents set status = 'accepted'$$, 'permission denied', 'no direct changes from the page');
select test.throws($$select canopy.einvoice_mark(gen_random_uuid(), 'sent')$$, 'permission denied', 'the state function is not for the page');
select public.einvoice_list(public.cr_today(), public.cr_today()) as el \gset
select test.eq((:'el'::jsonb)->>'mode', 'shadow', 'the owner sees the mode');
select test.eq(jsonb_array_length((:'el'::jsonb)->'documents'), 3, 'and every document');
select test.eq(((:'el'::jsonb)#>>'{counts,pending}')::int, 2, 'counted by status');
reset role;
select id as te from public.e_documents where order_id = '0d000000-0000-4000-8000-000000001902' \gset
select test.eq(canopy.einvoice_mark(:'te', 'accepted')->>'error', 'bad_transition', 'a pending document is never marked accepted directly');
select test.eq(canopy.einvoice_mark(:'te', 'queued')->>'ok', 'true', 'pending → queued');
select test.eq(canopy.einvoice_mark(:'te', 'sent', 'proveedor-x', 'ref-1', repeat('5', 50), '00100001040000000001')->>'ok', 'true', 'queued → sent, with the provider''s key');
select test.eq(canopy.einvoice_mark(:'te', 'accepted')->>'ok', 'true', 'sent → accepted');
select test.eq(canopy.einvoice_mark(:'te', 'queued')->>'error', 'bad_transition', 'an accepted document never goes back');
select test.eq((select attempts || ':' || length(clave) from public.e_documents where id = :'te'), '1:50', 'kept what the provider returned');
select test.login('cafe'); set role authenticated;
select test.eq(public.einvoice_list(public.cr_today(), public.cr_today())->>'error', 'not_allowed', 'the café device does not list documents');
reset role;
select test.done();
rollback;
