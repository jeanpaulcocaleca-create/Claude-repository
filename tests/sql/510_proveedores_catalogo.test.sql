-- Migrations 0039/0040 (Proveedores, D-067): the suppliers and each supplier's own catalog (vendor_items). A supplier
-- chosen for an item, also by the published Inventario page writing stock_items directly, always gets a catalog row and
-- the save never fails because of it; proveedor_guardar edits a supplier partially with before/after in the log, refuses a
-- second active supplier with the same name, keeps SINPE apart from vendors (owner level or the books' door, logged);
-- proveedor_producto_guardar is the one way to change a catalog price (the stock item's own price stays), creates a stock
-- item with its first supplier, sets or clears the preferred supplier, refuses repeats; numbers only as JSON numbers.
begin;
insert into public.vendors (id, name, phone) values ('5b000000-0000-4000-8000-000000051001', 'Lácteos Monteverde', '2645-0000'),
                                                   ('5b000000-0000-4000-8000-000000051002', 'Verduras del Valle', null);
create function test.vi510(v text, i text) returns int language sql as $$
  select count(*)::int from public.vendor_items where vendor_id = v::uuid and item_id = i::uuid $$;

-- 1) the published Inventario page (a manager unlock, direct writes) ----------------------------------------------------
select test.login('cafe'); select test.session('dev-510'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
insert into public.stock_items (id, name, unit, pack_label, pack_qty, cost_per_pack, vendor_id)
  values ('5a000000-0000-4000-8000-000000051001', 'Leche entera', 'ml', 'caja de 12', 11352, 12000, '5b000000-0000-4000-8000-000000051001');
update public.stock_items set name = 'Leche entera 946', vendor_id = '5b000000-0000-4000-8000-000000051001' where id = '5a000000-0000-4000-8000-000000051001';
select test.throws($$select count(*) from public.vendor_items$$, 'permission denied', '1 a page cannot read the catalog table directly');
select test.throws($$insert into public.vendor_items (vendor_id, item_id, pack_qty) values ('5b000000-0000-4000-8000-000000051001', '5a000000-0000-4000-8000-000000051001', 1)$$,
                   'permission denied', '1 nor write it');
select test.throws($$select * from public.work_sessions$$, 'permission denied', '1 nor the work sessions');
select test.throws($$select * from public.vendor_pay_info$$, 'permission denied', '1 nor how a supplier is paid');
reset role;
select test.eq((select pack_label || ' ' || pack_qty || ' ' || usual_price || ' ' || active || ' ' || created_by from public.vendor_items
                 where item_id = '5a000000-0000-4000-8000-000000051001'), 'caja de 12 11352 12000.00 true inventario',
               '1 the item saved with a supplier has that supplier''s catalog row (its presentation and price)');
select test.eq(test.vi510('5b000000-0000-4000-8000-000000051001', '5a000000-0000-4000-8000-000000051001'), 1,
               '1 saving the item again with the same supplier adds nothing');
set role authenticated;
update public.stock_items set vendor_id = '5b000000-0000-4000-8000-000000051002' where id = '5a000000-0000-4000-8000-000000051001';
update public.stock_items set vendor_id = '5b000000-0000-4000-8000-000000051001' where id = '5a000000-0000-4000-8000-000000051001';
insert into public.stock_items (id, name, unit, pack_qty, cost_per_pack, vendor_id)
  values ('5a000000-0000-4000-8000-000000051002', 'Harina rara', 'g', 2000000000, 300000000, '5b000000-0000-4000-8000-000000051002');
reset role;
select test.eq(test.vi510('5b000000-0000-4000-8000-000000051002', '5a000000-0000-4000-8000-000000051001') || ' '
               || test.vi510('5b000000-0000-4000-8000-000000051001', '5a000000-0000-4000-8000-000000051001'), '1 1',
               '1 another supplier chosen gets its own row; going back adds nothing (the live row is there)');
select test.eq((select count(*)::int from public.stock_items where id = '5a000000-0000-4000-8000-000000051002')
               || ' ' || test.vi510('5b000000-0000-4000-8000-000000051002', '5a000000-0000-4000-8000-000000051002'), '1 0',
               '1 an item whose presentation the catalog cannot hold is still saved (the catalog row is skipped, never the save)');
select test.eq((select count(*)::int from public.purchase_lines), 0, '1 (nothing ordered yet)');

-- 2) proveedor_guardar ---------------------------------------------------------------------------------------------------
select test.login('cafe'); select test.session('dev-510'); set role authenticated;
select test.eq(public.proveedor_guardar('{"id":"5b000000-0000-4000-8000-000000051003","name":"Panadería Sol"}') ->> 'error', 'locked',
               '2 a café device without the owner areas open cannot save a supplier');
select test.unlock(test.staff('ana'), '4826');
select public.proveedor_guardar('{"id":"5b000000-0000-4000-8000-000000051003","name":" Panadería Sol ","phone":"8888-1111","lead_days":1,"credit_days":15}') as g1 \gset
select public.proveedor_guardar('{"id":"5b000000-0000-4000-8000-000000051003","name":"Panadería Sol","phone":"8888-1111","lead_days":1,"credit_days":15}') as g2 \gset
select test.eq((:'g1'::jsonb) ->> 'ok' || ' ' || coalesce((:'g1'::jsonb) ->> 'repeat', '-') || ' ' || ((:'g2'::jsonb) ->> 'repeat'), 'true - true',
               '2 a new supplier is saved by its request id; the same request again is a repeat');
select test.eq(public.proveedor_guardar('{"id":"5b000000-0000-4000-8000-000000051004","name":"lácteos monteverde"}'),
               '{"ok":false,"error":"duplicate_name","id":"5b000000-0000-4000-8000-000000051001"}'::jsonb,
               '2 a second active supplier with the same name (any case, any spaces) is refused with the first one''s id');
select test.eq(public.proveedor_guardar('{"id":"5b000000-0000-4000-8000-000000051003","phone":"8888-2222","notes":"Pan todos los días"}') ->> 'ok', 'true',
               '2 a partial edit changes only the keys sent');
select test.eq(public.proveedor_guardar('{"id":"5b000000-0000-4000-8000-000000051003","lead_days":"3"}') ->> 'error', 'bad_request', '2 a number sent as text is refused');
select test.eq(public.proveedor_guardar('{"id":"5b000000-0000-4000-8000-000000051003","lead_days":61}') ->> 'error', 'bad_request', '2 lead days stay within 0..60');
select test.eq(public.proveedor_guardar('{"id":"5b000000-0000-4000-8000-000000051003","credit_days":181}') ->> 'error', 'bad_request', '2 credit days within 0..180');
select test.eq(public.proveedor_guardar('{"id":"5b000000-0000-4000-8000-000000051003","tax_id":"3-101"}') ->> 'error', 'bad_request', '2 a key it does not know is refused');
select test.eq(public.proveedor_guardar('{"id":"no-es-un-id","name":"X"}') ->> 'error', 'bad_request', '2 an id that is not a uuid is refused');
select test.eq(public.proveedor_guardar('{"id":"5b000000-0000-4000-8000-000000051005","name":"   "}') ->> 'error', 'bad_request', '2 a new supplier needs a name');
select test.eq(public.proveedor_guardar('{"id":"5b000000-0000-4000-8000-000000051005","name":"Otro","email":123}') ->> 'error', 'bad_request', '2 text only as text');
reset role;
select test.eq((select name || ' ' || phone || ' ' || lead_days || ' ' || credit_days || ' ' || notes from public.vendors where id = '5b000000-0000-4000-8000-000000051003'),
               'Panadería Sol 8888-2222 1 15 Pan todos los días', '2 the supplier as saved (name trimmed)');
select test.eq((select string_agg(action || ':' || (details -> 'before' ->> 'phone') || '>' || (details -> 'after' ->> 'phone'), ' ' order by id) from public.audit_log
                 where action = 'vendor_save' and target_id = '5b000000-0000-4000-8000-000000051003' and details -> 'before' ? 'phone' and details -> 'before' ->> 'phone' is not null),
               'vendor_save:8888-1111>8888-2222', '2 the edit is logged with the phone before and after');
select test.eq((select count(*)::int from public.audit_log where action = 'vendor_save' and target_id = '5b000000-0000-4000-8000-000000051003'), 2,
               '2 two log lines (the creation and the edit; the repeat writes none)');
-- deactivating a supplier with an open order is allowed and says how many are open
insert into public.purchase_orders (id, vendor_id, status) values ('9a000000-0000-4000-8000-000000051001', '5b000000-0000-4000-8000-000000051003', 'sent');
set role authenticated;
select test.eq(public.proveedor_guardar('{"id":"5b000000-0000-4000-8000-000000051003","active":false}'),
               '{"ok":true,"id":"5b000000-0000-4000-8000-000000051003","open_orders":1}'::jsonb, '2 deactivating with one open order: allowed, open_orders 1');
-- SINPE: never on vendors; a manager may not change it
select test.eq(public.proveedor_guardar('{"id":"5b000000-0000-4000-8000-000000051001","sinpe":"8888-0000 (Ana Pérez)"}') ->> 'error', 'needs_owner',
               '2 a manager cannot change how a supplier is paid (SINPE)');
select test.eq(public.proveedor_guardar('{"id":"5b000000-0000-4000-8000-000000051001","phone":"2645-1111","sinpe":"8888-0000"}') ->> 'error', 'needs_owner',
               '2 nor together with another change (nothing of it is saved)');
reset role;
select test.eq((select phone from public.vendors where id = '5b000000-0000-4000-8000-000000051001') || ' ' || (select count(*) from public.vendor_pay_info),
               '2645-0000 0', '2 the refused save changed nothing');
-- the owner level (an owner-role PIN unlock) may
select test.login('cafe'); select test.session('dev-510-d'); select test.unlock(test.staff('dueno'), '7391'); set role authenticated;
select test.eq(public.proveedor_guardar('{"id":"5b000000-0000-4000-8000-000000051001","sinpe":"8888-0000"}') ->> 'ok', 'true', '2 the owner level changes the SINPE');
select test.eq(public.proveedor_guardar('{"id":"5b000000-0000-4000-8000-000000051001","sinpe":"8888-0000"}') ->> 'repeat', 'true', '2 the same SINPE again changes nothing');
reset role;
select test.eq((select sinpe || ' ' || updated_by from public.vendor_pay_info where vendor_id = '5b000000-0000-4000-8000-000000051001'), '8888-0000 Dueño (owner)',
               '2 stored apart from vendors, with who changed it');
select test.eq((select string_agg(coalesce(details ->> 'before', 'null') || '>' || (details ->> 'after'), ' ') from public.audit_log where action = 'vendor_sinpe'),
               'null>8888-0000', '2 logged once with before and after');
-- the books' door (the accountant): only the SINPE
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.proveedor_guardar('{"id":"5b000000-0000-4000-8000-000000051001","sinpe":"7777-0000"}') ->> 'ok', 'true', '2 the accountant changes the SINPE');
select test.eq(public.proveedor_guardar('{"id":"5b000000-0000-4000-8000-000000051001","name":"Otro nombre"}') ->> 'error', 'locked', '2 but nothing else of the supplier');
select test.eq(public.proveedor_guardar('{"id":"5b000000-0000-4000-8000-000000051009","sinpe":"7777-0000"}') ->> 'error', 'not_found', '2 and creates no supplier');
reset role;
select test.eq((select string_agg(coalesce(details ->> 'before', 'null') || '>' || (details ->> 'after'), ' ' order by id) from public.audit_log where action = 'vendor_sinpe'),
               'null>8888-0000 8888-0000>7777-0000', '2 both changes in the log');

-- 3) proveedor_producto_guardar ------------------------------------------------------------------------------------------
select test.login('cafe'); select test.session('dev-510'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select test.eq(public.proveedor_producto_guardar('{"id":"5c000000-0000-4000-8000-000000051001","vendor_id":"5b000000-0000-4000-8000-000000051002",
                 "item_id":"5a000000-0000-4000-8000-000000051001","vendor_code":"LE-12","label":"Leche Dos Pinos","pack_label":"paquete de 10","pack_qty":9460,
                 "usual_price":9900,"usual_qty":2}'),
               '{"ok":true,"id":"5c000000-0000-4000-8000-000000051001","item_id":"5a000000-0000-4000-8000-000000051001"}'::jsonb,
               '3 a second supplier of the same item, with its own presentation and price');
select test.eq(public.proveedor_producto_guardar('{"id":"5c000000-0000-4000-8000-000000051002","vendor_id":"5b000000-0000-4000-8000-000000051002",
                 "item_id":"5a000000-0000-4000-8000-000000051001","pack_qty":9460}'),
               '{"ok":false,"error":"duplicate_product","id":"5c000000-0000-4000-8000-000000051001"}'::jsonb,
               '3 the same supplier, item and presentation twice is refused with the existing row');
select test.eq(public.proveedor_producto_guardar('{"id":"5c000000-0000-4000-8000-000000051002","vendor_id":"5b000000-0000-4000-8000-000000051002",
                 "item_id":"5a000000-0000-4000-8000-000000051001"}') ->> 'error', 'bad_qty', '3 a new row needs its units per presentation');
select test.eq(public.proveedor_producto_guardar('{"id":"5c000000-0000-4000-8000-000000051002","vendor_id":"5b000000-0000-4000-8000-000000051002",
                 "item_id":"5a000000-0000-4000-8000-000000051001","pack_qty":0}') ->> 'error', 'bad_qty', '3 units per presentation above 0');
select test.eq(public.proveedor_producto_guardar('{"id":"5c000000-0000-4000-8000-000000051002","vendor_id":"5b000000-0000-4000-8000-000000051002",
                 "item_id":"5a000000-0000-4000-8000-000000051001","pack_qty":1000,"usual_price":-1}') ->> 'error', 'bad_price', '3 no negative price');
select test.eq(public.proveedor_producto_guardar('{"id":"5c000000-0000-4000-8000-000000051002","vendor_id":"5b000000-0000-4000-8000-000000051002",
                 "item_id":"5a000000-0000-4000-8000-000000051001","pack_qty":1000,"usual_price":100000001}') ->> 'error', 'bad_price', '3 no price above 100 000 000');
select test.eq(public.proveedor_producto_guardar('{"id":"5c000000-0000-4000-8000-000000051002","vendor_id":"5b000000-0000-4000-8000-000000051002",
                 "item_id":"5a000000-0000-4000-8000-000000051001","pack_qty":"NaN"}') ->> 'error', 'bad_request', '3 a number written as text («NaN») is refused');
-- a new stock item from the supplier's file
select public.proveedor_producto_guardar('{"id":"5c000000-0000-4000-8000-000000051003","vendor_id":"5b000000-0000-4000-8000-000000051002",
         "new_item":{"name":"Queso turrialba","unit":"g","category":"dairy","reorder_point":1000,"par_level":4000},
         "pack_label":"bloque de 2 kg","pack_qty":2000,"usual_price":7000}') as ni \gset
select test.eq(public.proveedor_producto_guardar('{"id":"5c000000-0000-4000-8000-000000051004","vendor_id":"5b000000-0000-4000-8000-000000051001",
                 "new_item":{"name":" queso TURRIALBA ","unit":"g"},"pack_qty":500}'),
               jsonb_build_object('ok', false, 'error', 'duplicate_item', 'item_id', (:'ni'::jsonb) ->> 'item_id'),
               '3 a new item with the name of an active one is refused with that item''s id («Usar este»)');
select test.eq(public.proveedor_producto_guardar('{"id":"5c000000-0000-4000-8000-000000051004","vendor_id":"5b000000-0000-4000-8000-000000051001",
                 "new_item":{"name":"Otro","unit":"lb"},"pack_qty":500}') ->> 'error', 'bad_request', '3 the item''s unit is one of unit, g, kg, ml, L');
reset role;
select test.eq((select name || ' ' || unit || ' ' || category || ' ' || pack_label || ' ' || pack_qty || ' ' || cost_per_pack || ' ' || avg_cost || ' ' || on_hand
                       || ' ' || reorder_point || ' ' || par_level || ' ' || (vendor_id = '5b000000-0000-4000-8000-000000051002')
                  from public.stock_items where id = ((:'ni'::jsonb) ->> 'item_id')::uuid),
               'Queso turrialba g dairy bloque de 2 kg 2000 7000.00 3.5000 0 1000 4000 true',
               '3 the new stock item: its unit, presentation and price, nothing on hand, this supplier preferred');
select test.eq((select count(*)::int from public.vendor_items where item_id = ((:'ni'::jsonb) ->> 'item_id')::uuid), 1,
               '3 with exactly one catalog row (the request id), not a second one from the item''s supplier');
select test.eq((select count(*)::int from public.audit_log where action = 'stock_item_create' and target_id = (:'ni'::jsonb) ->> 'item_id'), 1, '3 the new item is logged');
update public.stock_items set active = false where id = '5a000000-0000-4000-8000-000000051002';
set role authenticated;
select test.eq(public.proveedor_producto_guardar('{"id":"5c000000-0000-4000-8000-000000051005","vendor_id":"5b000000-0000-4000-8000-000000051001",
                 "item_id":"5a000000-0000-4000-8000-000000051002","pack_qty":1000}') ->> 'error', 'item_inactive', '3 an inactive item cannot be added');
-- the catalog price changes only here, and the item's own price stays
select test.eq(public.proveedor_producto_guardar('{"id":"5c000000-0000-4000-8000-000000051001","usual_price":10500}') ->> 'ok', 'true', '3 a new usual price');
select test.eq(public.proveedor_producto_guardar('{"id":"5c000000-0000-4000-8000-000000051001","item_id":"5a000000-0000-4000-8000-000000051002"}') ->> 'error', 'bad_request',
               '3 a row never changes its item');
-- preferred supplier: stock_items.vendor_id
select test.eq(public.proveedor_producto_guardar('{"id":"5c000000-0000-4000-8000-000000051001","preferred":true}') ->> 'ok', 'true', '3 preferred: yes');
reset role;
select test.eq((select vendor_id::text || ' ' || cost_per_pack from public.stock_items where id = '5a000000-0000-4000-8000-000000051001'),
               '5b000000-0000-4000-8000-000000051002 12000', '3 the item''s supplier is now this one; its own price stays 12000');
select test.eq((select usual_price from public.vendor_items where id = '5c000000-0000-4000-8000-000000051001'), 10500.00, '3 the catalog row has the new price');
select test.eq((select (details -> 'before' ->> 'usual_price') || '>' || (details -> 'after' ->> 'usual_price') from public.audit_log
                 where action = 'vendor_item_save' and target_id = '5c000000-0000-4000-8000-000000051001' and details -> 'before' is not null and jsonb_typeof(details -> 'before') = 'object'
                 order by id limit 1), '9900.00>10500.00', '3 the price change is logged with before and after');
select test.eq((select string_agg(coalesce(details ->> 'before', 'null') || '>' || coalesce(details ->> 'after', 'null'), ' ' order by id) from public.audit_log
                 where action = 'preferred_vendor' and target_id = '5a000000-0000-4000-8000-000000051001'),
               '5b000000-0000-4000-8000-000000051001>5b000000-0000-4000-8000-000000051002', '3 the change of preferred supplier is logged');
set role authenticated;
select test.eq(public.proveedor_producto_guardar('{"id":"5c000000-0000-4000-8000-000000051001","preferred":false}') ->> 'ok', 'true', '3 preferred: no');
select test.eq(public.proveedor_producto_guardar('{"id":"5c000000-0000-4000-8000-000000051001","active":false,"preferred":true}') ->> 'error', 'bad_request',
               '3 a retired row cannot be the preferred one');
select test.eq(public.proveedor_producto_guardar('{"id":"5c000000-0000-4000-8000-000000051001","active":false}') ->> 'ok', 'true', '3 «Retirar»: the row is retired, never deleted');
select test.eq(public.proveedor_producto_guardar('{"id":"5c000000-0000-4000-8000-000000051006","vendor_id":"5b000000-0000-4000-8000-000000051002",
                 "item_id":"5a000000-0000-4000-8000-000000051001","pack_qty":9460,"usual_price":9800}') ->> 'ok', 'true',
               '3 a retired row frees its presentation for a new one');
reset role;
select test.eq((select vendor_id from public.stock_items where id = '5a000000-0000-4000-8000-000000051001'), null::uuid, '3 the item has no preferred supplier now');
select test.eq((select count(*)::int || ' ' || count(*) filter (where active) from public.vendor_items where item_id = '5a000000-0000-4000-8000-000000051001'), '4 3',
               '3 four rows of that item (one retired), none deleted');
-- the accountant reads but does not keep the catalog; a café device without the owner areas, nothing
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.proveedor_producto_guardar('{"id":"5c000000-0000-4000-8000-000000051007","vendor_id":"5b000000-0000-4000-8000-000000051002",
                 "item_id":"5a000000-0000-4000-8000-000000051001","pack_qty":1}') ->> 'error', 'locked', '3 the accountant does not keep the catalog');
select test.login('cafe'); select test.session('dev-510-x'); set role authenticated;
select test.eq(public.proveedor_producto_guardar('{"id":"5c000000-0000-4000-8000-000000051007"}') ->> 'error', 'locked', '3 nor a café device without the owner areas');
reset role;

select test.done();
rollback;
