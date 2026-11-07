-- Migration 0039 (Proveedores, D-067): drafts and orders. One open draft per supplier, saved with its version (a second
-- device never saves over the first: «changed» with the newer draft), its lines kept rebuilt as [{vendor_item_id, packs}].
-- An order is created from ticked catalog rows: the server counts the base units (2 boxes of 12 → 24) and keeps the price
-- per base unit twice (the expected one and the one at order time), marks the draft used in the same transaction, and a
-- repeat or a stale draft never makes a second order. Orders are edited before and after receiving with their version and
-- before/after in the log; cancelled, closed short, confirmed or given a supplier; the published page's direct writes still
-- work, move the version, and can never set the new columns.
begin;
insert into public.vendors (id, name) values ('5b000000-0000-4000-8000-000000051101', 'Lácteos Monteverde'),
                                             ('5b000000-0000-4000-8000-000000051102', 'Verduras del Valle'),
                                             ('5b000000-0000-4000-8000-000000051103', 'Cerrado SA');
insert into public.stock_items (id, name, unit, pack_qty, cost_per_pack) values
  ('5a000000-0000-4000-8000-000000051101', 'Leche', 'unit', 1, 1000),
  ('5a000000-0000-4000-8000-000000051102', 'Queso', 'g', 500, 3000),
  ('5a000000-0000-4000-8000-000000051103', 'Mantequilla', 'g', 250, 1500),
  ('5a000000-0000-4000-8000-000000051104', 'Crema', 'ml', 1000, 2000);
insert into public.vendor_items (id, vendor_id, item_id, pack_label, pack_qty, usual_price, usual_qty) values
  ('5c000000-0000-4000-8000-000000051101', '5b000000-0000-4000-8000-000000051101', '5a000000-0000-4000-8000-000000051101', 'caja de 12', 12, 12000, 2),
  ('5c000000-0000-4000-8000-000000051102', '5b000000-0000-4000-8000-000000051101', '5a000000-0000-4000-8000-000000051102', 'bloque de 2 kg', 2000, 7000, null),
  ('5c000000-0000-4000-8000-000000051103', '5b000000-0000-4000-8000-000000051101', '5a000000-0000-4000-8000-000000051103', 'caja de 20', 5000, 30000, null),
  ('5c000000-0000-4000-8000-000000051104', '5b000000-0000-4000-8000-000000051101', '5a000000-0000-4000-8000-000000051104', 'litro', 1000, null, null),
  ('5c000000-0000-4000-8000-000000051105', '5b000000-0000-4000-8000-000000051102', '5a000000-0000-4000-8000-000000051101', 'unidad', 1, 1100, null),
  ('5c000000-0000-4000-8000-000000051106', '5b000000-0000-4000-8000-000000051103', '5a000000-0000-4000-8000-000000051101', 'unidad', 1, 900, null);
update public.vendors set active = false where id = '5b000000-0000-4000-8000-000000051103';
create function test.l511(a text) returns jsonb language sql as $$ select a::jsonb $$;
select test.login('cafe'); select test.session('dev-511'); set role authenticated;
select test.eq(public.proveedor_borrador_guardar('5b000000-0000-4000-8000-000000051101', '[]', 'x', 0) ->> 'error', 'locked', '0 a café device without the owner areas keeps no draft');
select test.eq(public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051101', '[]', null, gen_random_uuid()) ->> 'error', 'locked', '0 and creates no order');
select test.unlock(test.staff('ana'), '4826');

-- 1) drafts --------------------------------------------------------------------------------------------------------------
select public.proveedor_borrador_guardar('5b000000-0000-4000-8000-000000051101',
         '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051101","packs":2,"name":"ignored"},{"vendor_item_id":"5c000000-0000-4000-8000-000000051102","packs":1.5}]',
         'Entregar antes de las 9', 0) as d1 \gset
select test.eq((:'d1'::jsonb) ->> 'ok' || ' ' || ((:'d1'::jsonb) ->> 'version'), 'true 1', '1 a new draft: version 1');
select public.proveedor_borrador_guardar('5b000000-0000-4000-8000-000000051101',
         '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051101","packs":2},{"vendor_item_id":"5c000000-0000-4000-8000-000000051102","packs":1.5},
           {"vendor_item_id":"5c000000-0000-4000-8000-000000051103","packs":1}]', 'Entregar antes de las 9', 1) as d2 \gset
select test.eq((:'d2'::jsonb) ->> 'version', '2', '1 saved again from its version: version 2');
-- a second device still on version 1
select public.proveedor_borrador_guardar('5b000000-0000-4000-8000-000000051101', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051101","packs":5}]', null, 1) as d3 \gset
select test.eq((:'d3'::jsonb) ->> 'error' || ' ' || ((:'d3'::jsonb) #>> '{draft,version}') || ' ' || jsonb_array_length((:'d3'::jsonb) #> '{draft,lines}'), 'changed 2 3',
               '1 a device with an older version is refused («changed») and gets the newer draft');
select test.eq(public.proveedor_borrador_guardar('5b000000-0000-4000-8000-000000051101', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051101","packs":"2"}]', null, 2) ->> 'error',
               'bad_request', '1 packs only as a number');
select test.eq(public.proveedor_borrador_guardar('5b000000-0000-4000-8000-000000051101', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051101","packs":0}]', null, 2) ->> 'error',
               'bad_qty', '1 packs above 0');
select test.eq(public.proveedor_borrador_guardar('5b000000-0000-4000-8000-000000051101', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051101","packs":1.2345}]', null, 2) ->> 'error',
               'bad_qty', '1 at most 3 decimals');
select test.eq(public.proveedor_borrador_guardar('5b000000-0000-4000-8000-000000051101', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051101","packs":100001}]', null, 2) ->> 'error',
               'bad_qty', '1 at most 100 000 presentations');
select test.eq(public.proveedor_borrador_guardar('5b000000-0000-4000-8000-000000051101',
                 '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051101","packs":1},{"vendor_item_id":"5c000000-0000-4000-8000-000000051101","packs":2}]', null, 2) ->> 'error',
               'duplicate_line', '1 the same row twice is refused');
select test.eq(public.proveedor_borrador_guardar('5b000000-0000-4000-8000-000000051101', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051105","packs":1}]', null, 2) ->> 'error',
               'not_found', '1 a row of another supplier is refused');
select test.eq(public.proveedor_borrador_guardar('5b000000-0000-4000-8000-000000051101',
                 (select jsonb_agg(jsonb_build_object('vendor_item_id', '5c000000-0000-4000-8000-000000051101', 'packs', g)) from generate_series(1, 201) g), null, 2) ->> 'error',
               'bad_request', '1 at most 200 lines');
reset role;
select test.eq((select lines::text || ' ' || version || ' ' || status from public.purchase_drafts where vendor_id = '5b000000-0000-4000-8000-000000051101'),
               '[{"packs": 2, "vendor_item_id": "5c000000-0000-4000-8000-000000051101"}, {"packs": 1.5, "vendor_item_id": "5c000000-0000-4000-8000-000000051102"}, '
               || '{"packs": 1, "vendor_item_id": "5c000000-0000-4000-8000-000000051103"}] 2 open', '1 the draft as stored: only the row and the packs, version 2');
set role authenticated;
-- the other supplier's draft: emptied → discarded
select test.eq(public.proveedor_borrador_guardar('5b000000-0000-4000-8000-000000051102', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051105","packs":3}]', null, 0) ->> 'version',
               '1', '1 a draft for the second supplier');
select test.eq(public.proveedor_borrador_guardar('5b000000-0000-4000-8000-000000051102', '[]', '  ', 1), '{"ok":true,"discarded":true}'::jsonb,
               '1 no lines and no note: the draft is discarded');
select test.eq(public.proveedor_borrador_guardar('5b000000-0000-4000-8000-000000051102', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051105","packs":1}]', null, 0) ->> 'version',
               '1', '1 a new one starts again at version 1');
select test.eq(public.proveedor_borrador_descartar('5b000000-0000-4000-8000-000000051102', 7) ->> 'error', 'changed', '1 «Descartar» with an older version is refused');
select test.eq(public.proveedor_borrador_descartar('5b000000-0000-4000-8000-000000051102', 1), '{"ok":true,"discarded":true}'::jsonb, '1 «Descartar» from its version');
reset role;
select test.eq((select string_agg(status, ' ' order by created_at, id) from public.purchase_drafts where vendor_id = '5b000000-0000-4000-8000-000000051102'),
               'discarded discarded', '1 both drafts kept as discarded (never deleted)');

-- 2) creating an order from the ticked rows -------------------------------------------------------------------------------
set role authenticated;
select test.eq(public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051101',
                 '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051101","packs":2}]', null, '9a000000-0000-4000-8000-000000051101', 1) ->> 'error',
               'draft_changed', '2 from an older draft version: refused («draft_changed»), no order');
select public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051101',
         '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051101","packs":2},{"vendor_item_id":"5c000000-0000-4000-8000-000000051102","packs":1.5,"pack_price":7500}]',
         ' Entregar antes de las 9 ', '9a000000-0000-4000-8000-000000051101', 2, current_date + 2) as c1 \gset
select test.eq((:'c1'::jsonb) ->> 'ok' || ' ' || ((:'c1'::jsonb) ->> 'version') || ' ' || ((:'c1'::jsonb) ->> 'po_number' ~ '^\d+$')::text, 'true 2 true',
               '2 the order is created with its number, at version 2 (one per line)');
select test.eq(public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051101', '[]', null, '9a000000-0000-4000-8000-000000051101', 2),
               jsonb_build_object('ok', true, 'repeat', true, 'id', '9a000000-0000-4000-8000-000000051101', 'po_number', ((:'c1'::jsonb) ->> 'po_number')::int, 'version', 2),
               '2 the same request again (a lost answer, a double tap) answers the same order: never two');
select test.eq(public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051101', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051101","packs":1}]', null,
                 '9a000000-0000-4000-8000-000000051102', 2),
               '{"ok":false,"error":"draft_used","po_id":"9a000000-0000-4000-8000-000000051101"}'::jsonb, '2 the draft used by another device: «draft_used» with that order');
select test.eq(public.proveedor_borrador_guardar('5b000000-0000-4000-8000-000000051101', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051101","packs":1}]', null, 3),
               '{"ok":false,"error":"draft_used","po_id":"9a000000-0000-4000-8000-000000051101"}'::jsonb, '2 and an autosave of that draft says so too');
reset role;
select test.eq((select status || ' ' || (sent_at is not null) || ' ' || note || ' ' || by_name || ' ' || (expected_on = current_date + 2) from public.purchase_orders
                 where id = '9a000000-0000-4000-8000-000000051101'), 'sent true Entregar antes de las 9 Ana (manager) true', '2 sent, with its note, who and when');
select test.eq((select string_agg(pos || ':' || packs || 'x' || pack_qty || '=' || qty || ' @' || unit_cost || '/' || ordered_unit_cost || ' ' || pack_label, ' | ' order by pos)
                  from public.purchase_lines where po_id = '9a000000-0000-4000-8000-000000051101'),
               '1:2x12=24.0000 @1000.000000/1000.000000 caja de 12 | 2:1.5x2000=3000.0000 @3.750000/3.750000 bloque de 2 kg',
               '2 2 boxes of 12 → 24 units at 1000 each (12000 per box); the typed price 7500 per block → 3.75 per gram');
select test.eq((select status || ' ' || (po_id = '9a000000-0000-4000-8000-000000051101') from public.purchase_drafts where vendor_id = '5b000000-0000-4000-8000-000000051101'),
               'used true', '2 the draft is marked used with the order');
select test.eq((select count(*)::int from public.audit_log where action = 'po_create' and target_id = '9a000000-0000-4000-8000-000000051101'), 1, '2 one log line');
set role authenticated;
select test.eq(public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051101', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051104","packs":1}]', null, gen_random_uuid()),
               '{"ok":false,"error":"needs_price","vendor_item_id":"5c000000-0000-4000-8000-000000051104"}'::jsonb, '2 a row without a usual price needs a price');
select test.eq(public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051101', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051104","packs":1,"pack_price":0}]', null, gen_random_uuid()) ->> 'error',
               'needs_price', '2 ₡0 is not a price');
select test.eq(public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051101', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051104","packs":1,"pack_price":0,"free":true}]',
                 null, '9a000000-0000-4000-8000-000000051103') ->> 'ok', 'true', '2 unless it is marked free (a gift from the supplier)');
select test.eq(public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051103', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051106","packs":1}]', null, gen_random_uuid()) ->> 'error',
               'vendor_inactive', '2 not to an inactive supplier');
select test.eq(public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051101', '[]', null, gen_random_uuid()) ->> 'error', 'empty', '2 not with no lines');
select test.eq(public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051101', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051105","packs":1}]', null, gen_random_uuid()) ->> 'error',
               'not_found', '2 not with a row of another supplier');
select test.eq(public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051101',
                 '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051101","packs":1},{"vendor_item_id":"5c000000-0000-4000-8000-000000051101","packs":1}]', null, gen_random_uuid()) ->> 'error',
               'duplicate_line', '2 not the same row twice');
select test.eq(public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051101', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051101","packs":1,"pack_price":"9000"}]', null,
                 gen_random_uuid()) ->> 'error', 'bad_request', '2 a price only as a number');
reset role;
select test.eq((select count(*)::int from public.purchase_orders where vendor_id = '5b000000-0000-4000-8000-000000051101'), 2, '2 only the two good orders exist');
select test.eq((select qty || ' ' || unit_cost from public.purchase_lines where po_id = '9a000000-0000-4000-8000-000000051103'), '1000.0000 0.000000', '2 the free line: 1 litre at ₡0');

-- 3) editing --------------------------------------------------------------------------------------------------------------
select (select id::text from public.purchase_lines where po_id = '9a000000-0000-4000-8000-000000051101' and pos = 1) as lmilk,
       (select id::text from public.purchase_lines where po_id = '9a000000-0000-4000-8000-000000051101' and pos = 2) as lcheese \gset
set role authenticated;
select test.eq(public.proveedor_pedido_editar('9a000000-0000-4000-8000-000000051101', 1, '[]') #>> '{error}', 'changed', '3 an older version is refused («changed»)');
select test.eq(public.proveedor_pedido_editar('9a000000-0000-4000-8000-000000051101', 1, '[]') #>> '{order,version}', '2', '3 with the order''s current version');
select public.proveedor_pedido_editar('9a000000-0000-4000-8000-000000051101', 2,
         jsonb_build_array(jsonb_build_object('line_id', :'lmilk', 'packs', 3), jsonb_build_object('vendor_item_id', '5c000000-0000-4000-8000-000000051103', 'packs', 1)),
         'Entregar antes de las 8') as e1 \gset
select test.eq((:'e1'::jsonb) ->> 'ok' || ' ' || ((:'e1'::jsonb) ->> 'status'), 'true sent', '3 milk 2 → 3 boxes, butter added, cheese left out (removed), a new note');
reset role;
select test.eq((select string_agg(coalesce(pos::text, '-') || ':' || packs || '=' || qty || ':' || (removed_at is not null), ' ' order by pos)
                  from public.purchase_lines where po_id = '9a000000-0000-4000-8000-000000051101'),
               '1:3=36.0000:false 2:0=0:true 3:1=5000.0000:false', '3 the removed line is kept (packs 0, removed), never deleted');
select test.eq((select note from public.purchase_orders where id = '9a000000-0000-4000-8000-000000051101'), 'Entregar antes de las 8', '3 the note changed');
select test.eq((select jsonb_array_length(details -> 'changes') || ' ' || (details #>> '{changes,0,after}') from public.audit_log
                 where action = 'po_edit' and target_id = '9a000000-0000-4000-8000-000000051101'), '4 removed',
               '3 one log line with the four changes, before and after');
select test.eq((select summary from public.audit_log where action = 'po_edit' and target_id = '9a000000-0000-4000-8000-000000051101'),
               'pedido Nº ' || (select po_number from public.purchase_orders where id = '9a000000-0000-4000-8000-000000051101')
               || ': ' || (select string_agg(x, '; ') from (select (select name from public.stock_items where id = l.item_id) || case when l.removed_at is not null then ' quitado'
                                                                    when l.pos = 1 then ' 2 → 3' else ' agregado (1)' end as x
                                                               from public.purchase_lines l where l.po_id = '9a000000-0000-4000-8000-000000051101' order by case when l.removed_at is not null then 0 when l.pos = 1 then 1 else 2 end) q)
               || '; nota cambiada', '3 the history reads what changed (the Proveedores page shows this line)');
select (select version from public.purchase_orders where id = '9a000000-0000-4000-8000-000000051101') as v3 \gset
set role authenticated;
select test.eq(public.proveedor_pedido_editar('9a000000-0000-4000-8000-000000051101', :v3,
                 jsonb_build_array(jsonb_build_object('line_id', :'lmilk', 'packs', 3), jsonb_build_object('vendor_item_id', '5c000000-0000-4000-8000-000000051101', 'packs', 1))) ->> 'error',
               'duplicate_line', '3 a row that already has a live line is not added twice');
select test.eq(public.proveedor_pedido_editar('9a000000-0000-4000-8000-000000051101', :v3, '[]') ->> 'error', 'empty', '3 an order keeps at least one line');
-- a delivery of one box, then the line cannot go below it and cannot be removed
select (select id::text from public.purchase_lines where po_id = '9a000000-0000-4000-8000-000000051101' and pos = 3) as lbutter \gset
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051101', '7e000000-0000-4000-8000-000000051101', :v3,
                 jsonb_build_array(jsonb_build_object('line_id', :'lmilk', 'packs', 1))) ->> 'status', 'partially_received', '3 (one box of milk arrives)');
select (select version from public.purchase_orders where id = '9a000000-0000-4000-8000-000000051101') as v4 \gset
select test.eq(public.proveedor_pedido_editar('9a000000-0000-4000-8000-000000051101', :v4,
                 jsonb_build_array(jsonb_build_object('line_id', :'lmilk', 'packs', 0.5), jsonb_build_object('line_id', :'lbutter', 'packs', 1))),
               jsonb_build_object('ok', false, 'error', 'below_received', 'line_id', :'lmilk', 'received_packs', 1.0000), '3 after receiving: never below what arrived');
select test.eq(public.proveedor_pedido_editar('9a000000-0000-4000-8000-000000051101', :v4, jsonb_build_array(jsonb_build_object('line_id', :'lbutter', 'packs', 1))),
               jsonb_build_object('ok', false, 'error', 'has_receipts', 'line_id', :'lmilk'), '3 and a line with something received cannot be removed');
select public.proveedor_pedido_editar('9a000000-0000-4000-8000-000000051101', :v4,
         jsonb_build_array(jsonb_build_object('line_id', :'lmilk', 'packs', 1, 'pack_price', 12500), jsonb_build_object('line_id', :'lbutter', 'packs', 1))) as e2 \gset
select test.eq((:'e2'::jsonb) ->> 'ok' || ' ' || ((:'e2'::jsonb) ->> 'status'), 'true partially_received', '3 milk reduced to the one box that came (and a new price): butter still pending');
reset role;
select test.eq((select qty || ' ' || received_qty || ' ' || unit_cost || ' ' || ordered_unit_cost from public.purchase_lines where id = :'lmilk'::uuid),
               '12.0000 12.0000 1041.666667 1041.666667', '3 the line: 12 ordered, 12 received, the new price per unit');
select (select version from public.purchase_orders where id = '9a000000-0000-4000-8000-000000051101') as v5 \gset
set role authenticated;
select test.eq(public.proveedor_pedido_editar('9a000000-0000-4000-8000-000000051101', :v5, jsonb_build_array(jsonb_build_object('line_id', :'lmilk', 'packs', 1))) ->> 'status',
               'received', '3 the butter left out: every live line complete, the order is received');
select (select version from public.purchase_orders where id = '9a000000-0000-4000-8000-000000051101') as v6 \gset
select test.eq(public.proveedor_pedido_editar('9a000000-0000-4000-8000-000000051101', :v6, jsonb_build_array(jsonb_build_object('line_id', :'lmilk', 'packs', 1))) ->> 'error',
               'closed', '3 a received order''s lines no longer change');
select test.eq(public.proveedor_pedido_editar('9a000000-0000-4000-8000-000000051101', :v6, null, 'Llegó todo bien', current_date) ->> 'ok', 'true',
               '3 but its note and expected date may');
reset role;
select test.eq((select count(*)::int from public.audit_log where action = 'po_edit' and target_id = '9a000000-0000-4000-8000-000000051101'), 4,
               '3 every edit is in the log (before and after receiving)');
select test.eq((select received_at is not null from public.purchase_orders where id = '9a000000-0000-4000-8000-000000051101'), true, '3 with its received time');

-- 4) cancel, close short, confirm, assign a supplier ------------------------------------------------------------------------
set role authenticated;
select (select version from public.purchase_orders where id = '9a000000-0000-4000-8000-000000051103') as v7 \gset
select test.eq(public.proveedor_pedido_cancelar('9a000000-0000-4000-8000-000000051103', :v7, 'Ya no se necesita') ->> 'status', 'cancelled', '4 an order without deliveries is cancelled');
select test.eq(public.proveedor_pedido_cancelar('9a000000-0000-4000-8000-000000051103', :v7 + 1, null) ->> 'error', 'cancelled', '4 a cancelled order says so');
select test.eq(public.proveedor_pedido_cancelar('9a000000-0000-4000-8000-000000051101', (select version from public.purchase_orders where id = '9a000000-0000-4000-8000-000000051101'), null) ->> 'error',
               'closed', '4 a received one cannot be cancelled');
select public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051101', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051101","packs":10}]', null,
                                     '9a000000-0000-4000-8000-000000051104') as c4 \gset
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051104', '7e000000-0000-4000-8000-000000051104', ((:'c4'::jsonb) ->> 'version')::int,
                 (select jsonb_agg(jsonb_build_object('line_id', id, 'packs', 6)) from public.purchase_lines where po_id = '9a000000-0000-4000-8000-000000051104')) ->> 'status',
               'partially_received', '4 (6 of 10 boxes arrive)');
select (select version from public.purchase_orders where id = '9a000000-0000-4000-8000-000000051104') as v8 \gset
select test.eq(public.proveedor_pedido_cancelar('9a000000-0000-4000-8000-000000051104', :v8, null) ->> 'error', 'has_receipts', '4 an order with deliveries cannot be cancelled');
select test.eq(public.proveedor_pedido_cerrar('9a000000-0000-4000-8000-000000051104', :v8, 'El resto no llega') ->> 'status', 'received', '4 «Cerrar lo pendiente»: received');
select test.eq(public.proveedor_pedido_cerrar('9a000000-0000-4000-8000-000000051104', :v8 + 1, null) ->> 'error', 'already_received', '4 twice: already received');
select public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051101', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051101","packs":1}]', null,
                                     '9a000000-0000-4000-8000-000000051105') as c5 \gset
select test.eq(public.proveedor_pedido_cerrar('9a000000-0000-4000-8000-000000051105', ((:'c5'::jsonb) ->> 'version')::int, null) ->> 'error', 'no_receipts',
               '4 nothing to close without a delivery');
reset role;
select test.eq((select (details #>> '{missing,0,pending_packs}') || ' ' || (details ->> 'reason') from public.audit_log where action = 'po_close'
                 and target_id = '9a000000-0000-4000-8000-000000051104'), '4.0000 El resto no llega', '4 the log keeps what was missing (4 boxes) and why');
-- the published page: an order made as a draft and one without a supplier, received the old way
set role authenticated;
insert into public.purchase_orders (id, vendor_id, status) values ('9a000000-0000-4000-8000-000000051106', '5b000000-0000-4000-8000-000000051101', 'draft'),
                                                                 ('9a000000-0000-4000-8000-000000051107', null, 'sent');
insert into public.purchase_lines (id, po_id, item_id, packs, qty, unit_cost, vendor_item_id, pack_qty, ordered_unit_cost, pos, removed_at)
  values ('9b000000-0000-4000-8000-000000051106', '9a000000-0000-4000-8000-000000051106', '5a000000-0000-4000-8000-000000051101', 2, 24, 1000,
          '5c000000-0000-4000-8000-000000051101', 999, 5, 7, now()),
         ('9b000000-0000-4000-8000-000000051107', '9a000000-0000-4000-8000-000000051107', '5a000000-0000-4000-8000-000000051102', 1, 2000, 3, null, null, null, null, null);
update public.purchase_lines set packs = 3, qty = 36, pack_qty = 1, ordered_unit_cost = 1, removed_at = now() where id = '9b000000-0000-4000-8000-000000051106';
reset role;
select test.eq((select packs || ' ' || qty || ' ' || coalesce(vendor_item_id::text, '-') || ' ' || coalesce(pack_qty::text, '-') || ' ' || coalesce(ordered_unit_cost::text, '-')
                       || ' ' || coalesce(pos::text, '-') || ' ' || coalesce(removed_at::text, '-') from public.purchase_lines where id = '9b000000-0000-4000-8000-000000051106'),
               '3 36 - - - - -', '4 a page writing a line directly keeps its own columns, never the six new ones (null on insert, unchanged on update)');
select test.eq((select version from public.purchase_orders where id = '9a000000-0000-4000-8000-000000051106'), 2, '4 each direct change of a line moves the order''s version');
set role authenticated;
select test.eq(public.po_receive_delivery('9a000000-0000-4000-8000-000000051107', '[{"line_id":"9b000000-0000-4000-8000-000000051107","qty":2000}]',
                 '7e000000-0000-4000-8000-000000051107', 'F-511') ->> 'status', 'received', '4 (the old page receives the order without supplier)');
select test.eq(public.proveedor_pedido_confirmar('9a000000-0000-4000-8000-000000051106', 2) ->> 'status', 'sent', '4 the old draft order is sent («Confirmar»)');
select test.eq(public.proveedor_pedido_confirmar('9a000000-0000-4000-8000-000000051106', 3) ->> 'repeat', 'true', '4 twice: nothing more');
select (select version from public.purchase_orders where id = '9a000000-0000-4000-8000-000000051107') as v9 \gset
select test.eq(public.proveedor_pedido_asignar('9a000000-0000-4000-8000-000000051107', :v9, '5b000000-0000-4000-8000-000000051103') ->> 'error', 'vendor_inactive',
               '4 not an inactive supplier');
select test.eq(public.proveedor_pedido_asignar('9a000000-0000-4000-8000-000000051107', :v9, '5b000000-0000-4000-8000-000000051102') ->> 'ok', 'true',
               '4 «Sin proveedor · Asignar»: the order gets one');
reset role;
select test.eq((select (o.vendor_id = '5b000000-0000-4000-8000-000000051102')::text || ' ' || (r.vendor_id = '5b000000-0000-4000-8000-000000051102')::text
                  from public.purchase_orders o join public.purchase_receipts r on r.po_id = o.id where o.id = '9a000000-0000-4000-8000-000000051107'),
               'true true', '4 and so does its delivery (it can now be invoiced and paid)');
select test.eq((select count(*)::int from public.audit_log where action in ('po_cancel', 'po_close', 'po_confirm', 'po_vendor_set')), 4, '4 each one in the log');
select test.eq((select count(*)::int from public.purchase_orders), 6, '4 no order was deleted (the six made here)');

select test.done();
rollback;
