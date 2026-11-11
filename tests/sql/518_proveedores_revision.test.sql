-- Migrations 0039/0040 (Proveedores, D-067), the independent review's corrections on receiving:
--   (1) the employee on shift never reads the owner's sign-in (an owner who received without a PIN unlock is recorded
--       as «owner login · email», as every module records it): the receive view says «Dueño», and lists receipt ids;
--   (2) a line shows a catalog row's presentation (and offers its price) only when the row has the line's own size: an
--       old page's line matched to another size, or a row whose size was edited since, shows the line's units;
--   (3) a receipt id already spent on a delivery, sent again with the order's current version (the page reused it for
--       a new delivery after a lost answer), is refused «changed» with receipt_used, never a silent «repeat» that books
--       nothing; the real retry (the version from before that delivery) is still a repeat.
begin;
insert into public.vendors (id, name) values ('5b000000-0000-4000-8000-000000051801', 'Lácteos Monteverde');
insert into public.stock_items (id, name, unit, pack_label, pack_qty, cost_per_pack) values
  ('5a000000-0000-4000-8000-000000051801', 'Agua A', 'unit', 'caja de 12', 12, 12000),
  ('5a000000-0000-4000-8000-000000051802', 'Agua B', 'unit', null, 12, 12000);
insert into public.vendor_items (id, vendor_id, item_id, pack_label, pack_qty, usual_price) values
  ('5c000000-0000-4000-8000-000000051801', '5b000000-0000-4000-8000-000000051801', '5a000000-0000-4000-8000-000000051801', null, 12, 12000),
  ('5c000000-0000-4000-8000-000000051802', '5b000000-0000-4000-8000-000000051801', '5a000000-0000-4000-8000-000000051802', null, 12, 12000);
create function test.v518(o text) returns int language sql security definer as $$ select version from public.purchase_orders where id = o::uuid $$;
create function test.line518(o text, i text) returns text language sql security definer as $$
  select id::text from public.purchase_lines where po_id = o::uuid and item_id = i::uuid and removed_at is null $$;
insert into public.time_entries (staff_id, clock_in) values (test.staff('luis'), now() - interval '1 hour');

-- (1) the owner's sign-in never reaches the employee ---------------------------------------------------------------------------
select test.login('owner', 'aal2'); set role authenticated;
select (public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051801',
          '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051801","packs":4}]', null, '9a000000-0000-4000-8000-000000051801')) ->> 'ok' as c1 \gset
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051801', '7e000000-0000-4000-8000-000000051801', test.v518('9a000000-0000-4000-8000-000000051801'),
                 jsonb_build_array(jsonb_build_object('line_id', test.line518('9a000000-0000-4000-8000-000000051801', '5a000000-0000-4000-8000-000000051801'), 'packs', 1))) ->> 'status',
               'partially_received', '1 the owner with the phone code (no PIN unlock) receives one box');
reset role;
select test.ok((select by_name like 'owner login%@%' from public.purchase_receipts where id = '7e000000-0000-4000-8000-000000051801'),
               '1 (recorded as the owner''s login, as every module does)');
select test.login('cafe'); select test.session('dev-518'); set role authenticated;
select test.turno(test.staff('luis'), '5284') as tok \gset
select public.proveedor_pedido('9a000000-0000-4000-8000-000000051801', :'tok') as pe \gset
select test.eq((:'pe'::jsonb) ->> 'mode', 'receive', '1 (Luis on shift reads the order to receive it)');
select test.eq(position('@' in (:'pe'::jsonb)::text), 0, '1 no email anywhere in what the employee reads');
select test.eq((:'pe'::jsonb) #>> '{receipts,0,by_name}', 'Dueño', '1 the delivery reads «Dueño»');
select test.eq((:'pe'::jsonb) #>> '{receipts,0,id}', '7e000000-0000-4000-8000-000000051801', '1 and carries its id (the page knows its delivery was saved)');

-- (3) a spent receipt id reused for a new delivery -------------------------------------------------------------------------------
select test.v518('9a000000-0000-4000-8000-000000051801') as v_now \gset
select public.proveedor_recibir('9a000000-0000-4000-8000-000000051801', '7e000000-0000-4000-8000-000000051801', :v_now,
         jsonb_build_array(jsonb_build_object('line_id', test.line518('9a000000-0000-4000-8000-000000051801', '5a000000-0000-4000-8000-000000051801'), 'rest', true)), :'tok') as re \gset
select test.eq((:'re'::jsonb) ->> 'error' || ' ' || ((:'re'::jsonb) ->> 'receipt_used') || ' ' || ((:'re'::jsonb) #>> '{order,version}'),
               'changed true ' || :v_now, '3 the spent id with the current version (a new delivery): refused «changed», receipt_used, the order''s state');
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051801', '7e000000-0000-4000-8000-000000051801', :v_now - 1,
                 jsonb_build_array(jsonb_build_object('line_id', test.line518('9a000000-0000-4000-8000-000000051801', '5a000000-0000-4000-8000-000000051801'), 'rest', true)), :'tok') ->> 'repeat',
               'true', '3 the same id with the version from before that delivery (a real retry): a repeat');
reset role;
select test.eq((select count(*)::int || ' ' || sum(qty) from public.stock_moves where po_id = '9a000000-0000-4000-8000-000000051801'), '1 12.0000',
               '3 one delivery booked, never twice, nothing lost behind a «repeat»');
set role authenticated;
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051801', '7e000000-0000-4000-8000-000000051802', :v_now,
                 jsonb_build_array(jsonb_build_object('line_id', test.line518('9a000000-0000-4000-8000-000000051801', '5a000000-0000-4000-8000-000000051801'), 'rest', true)), :'tok') ->> 'status',
               'received', '3 the new delivery with a new id is booked');
reset role;
select test.eq((select sum(qty) from public.stock_moves where po_id = '9a000000-0000-4000-8000-000000051801'), 48.0000, '3 4 boxes of 12 in all');

-- (2) a catalog row whose size was edited since the order ----------------------------------------------------------------------
select test.login('owner', 'aal2'); set role authenticated;
select (public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051801',
          '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051802","packs":2}]', null, '9a000000-0000-4000-8000-000000051802')) ->> 'ok' as c2 \gset
reset role;
-- the published page's line (no catalog row on the line) for Agua A, 2 boxes of 12
insert into public.purchase_lines (id, po_id, item_id, packs, qty, unit_cost) values
  ('9b000000-0000-4000-8000-000000051802', '9a000000-0000-4000-8000-000000051802', '5a000000-0000-4000-8000-000000051801', 2, 24, 1000);
set role authenticated;
select test.eq(public.proveedor_producto_guardar('{"id":"5c000000-0000-4000-8000-000000051801","pack_label":"caja de 24","pack_qty":24,"usual_price":20000}') ->> 'ok', 'true',
               '2 (the owner edits Agua A''s row to boxes of 24)');
select test.eq(public.proveedor_producto_guardar('{"id":"5c000000-0000-4000-8000-000000051802","pack_label":"caja de 24","pack_qty":24,"usual_price":20000}') ->> 'ok', 'true',
               '2 (and Agua B''s row, which a line already ordered by 12)');
select public.proveedor_pedido('9a000000-0000-4000-8000-000000051802') as pd \gset
select test.eq((select string_agg(coalesce(x ->> 'pack_label', '-') || ' ' || (x ->> 'pack_qty') || ' ' || coalesce(x ->> 'vendor_item_id', 'null'), ' | ' order by x ->> 'item_name')
                  from jsonb_array_elements((:'pd'::jsonb) -> 'lines') x),
               'caja de 12 12 null | - 12 null', '2 neither line shows «caja de 24» nor points at the edited row (the units are the line''s own)');
reset role;
select test.login('cafe'); select test.session('dev-518'); set role authenticated;
select public.proveedor_pedido('9a000000-0000-4000-8000-000000051802', :'tok') as pr \gset
select test.eq((select string_agg(coalesce(x ->> 'pack_label', '-'), ' | ' order by x ->> 'item_name') from jsonb_array_elements((:'pr'::jsonb) -> 'lines') x),
               'caja de 12 | -', '2 the employee reads the same presentations');
-- the supplier file's per-row history no longer counts boxes of 12 on the row of 24
select test.login('owner', 'aal2'); set role authenticated;
select test.eq((select x ->> 'times_ordered' from jsonb_array_elements(public.proveedor_ficha('5b000000-0000-4000-8000-000000051801') -> 'products') x
                 where x ->> 'id' = '5c000000-0000-4000-8000-000000051802'), '0', '2 the row of 24 has no order history of boxes of 12');

-- (4) an order id kept from a lost answer, then a new draft: never a «repeat» that leaves the new ticks unordered ----------
select test.login('cafe'); select test.session('dev-518-m'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select public.proveedor_borrador_guardar('5b000000-0000-4000-8000-000000051801', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051801","packs":1}]', null, 0) ->> 'version' as dva \gset
select test.eq(public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051801', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051801","packs":1}]', null, '9a000000-0000-4000-8000-000000051803', :dva) ->> 'ok', 'true',
               '4 (an order from the draft; say its answer is lost)');
select test.eq(public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051801', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051801","packs":1}]', null, '9a000000-0000-4000-8000-000000051803', :dva) ->> 'repeat', 'true',
               '4 the real retry (the draft it used is no longer open): a repeat');
select public.proveedor_borrador_guardar('5b000000-0000-4000-8000-000000051801', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051802","packs":3}]', null, 0) ->> 'version' as dvb \gset
select public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051801', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051802","packs":3}]', null, '9a000000-0000-4000-8000-000000051803', :dvb) as st \gset
select test.eq((:'st'::jsonb) ->> 'error' || ' ' || ((:'st'::jsonb) ->> 'stale_request') || ' ' || ((:'st'::jsonb) ->> 'po_id'),
               'draft_changed true 9a000000-0000-4000-8000-000000051803', '4 the same id with a new open draft: refused, it names the order already made');
select test.eq(public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051801', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051802","packs":3}]', null, '9a000000-0000-4000-8000-000000051804', :dvb) ->> 'ok', 'true',
               '4 with a new id: the new order');
reset role;
select test.eq((select count(*)::int from public.purchase_orders where vendor_id = '5b000000-0000-4000-8000-000000051801' and id in ('9a000000-0000-4000-8000-000000051803', '9a000000-0000-4000-8000-000000051804')), 2,
               '4 two orders, one per draft');
-- (5) no draft version while the supplier has an open draft: that draft first, it stays open
set role authenticated;
select public.proveedor_borrador_guardar('5b000000-0000-4000-8000-000000051801', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051801","packs":2}]', null, 0) ->> 'version' as dvc \gset
select public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051801', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051802","packs":1}]', null, '9a000000-0000-4000-8000-000000051805') as nv \gset
select test.eq((:'nv'::jsonb) ->> 'error' || ' ' || ((:'nv'::jsonb) #>> '{draft,version}'), 'draft_changed ' || :dvc,
               '5 an order without the draft''s version while a draft is open (another device''s, or one in conflict): refused, with that draft');
reset role;
select test.eq((select count(*) from public.purchase_drafts where vendor_id = '5b000000-0000-4000-8000-000000051801' and status = 'open' and version = :dvc) || ' '
               || (select count(*) from public.purchase_orders where id = '9a000000-0000-4000-8000-000000051805'), '1 0', '5 the draft stays open, no order beside it');
set role authenticated;
select test.eq(public.proveedor_borrador_descartar('5b000000-0000-4000-8000-000000051801', :dvc) ->> 'ok', 'true', '5 (that draft discarded)');

-- (6) an old page's delivery without receipt lines can be corrected, and a correction down is capped by what it brought --
select test.eq(public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051801', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051802","packs":2}]', null, '9a000000-0000-4000-8000-000000051806') ->> 'ok', 'true',
               '6 (2 boxes of 24 of Agua B)');
select test.line518('9a000000-0000-4000-8000-000000051806', '5a000000-0000-4000-8000-000000051802') as l6 \gset
select test.eq(public.po_receive_delivery('9a000000-0000-4000-8000-000000051806', jsonb_build_array(jsonb_build_object('line_id', :'l6', 'qty', 24)),
                 '7e000000-0000-4000-8000-000000051810') ->> 'status', 'partially_received', '6 the published page receives one box (24 units)');
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051806', '7e000000-0000-4000-8000-000000051811', test.v518('9a000000-0000-4000-8000-000000051806'),
                 jsonb_build_array(jsonb_build_object('line_id', :'l6', 'rest', true))) ->> 'status', 'received', '6 then Proveedores the other');
reset role;
select test.eq((select count(*)::int from public.purchase_receipt_lines where receipt_id = '7e000000-0000-4000-8000-000000051810'), 0, '6 (the old page''s delivery has no receipt lines)');
set role authenticated;
select test.eq((select x ->> 'line_id' from jsonb_array_elements(public.proveedor_pedido('9a000000-0000-4000-8000-000000051806') -> 'receipts') r,
                       jsonb_array_elements(r -> 'lines') x where r ->> 'id' = '7e000000-0000-4000-8000-000000051810'), :'l6',
               '6 its line is named (the order''s one line of that item), so the page offers it');
select test.eq((select (x ->> 'packs') || ' ' || (x ->> 'qty') from jsonb_array_elements(public.proveedor_pedido('9a000000-0000-4000-8000-000000051806') -> 'receipts') r,
                       jsonb_array_elements(r -> 'lines') x where r ->> 'id' = '7e000000-0000-4000-8000-000000051810'), '1.0000 24',
               '6 and in that line''s presentations (1 box of 24, as the correction counts), never «24» read as boxes');
select test.eq(public.proveedor_recepcion_corregir('7e000000-0000-4000-8000-000000051810', '7e000000-0000-4000-8000-000000051812',
                 jsonb_build_array(jsonb_build_object('line_id', :'l6', 'packs_delta', -2)), 'Contamos de más') ->> 'error' || ' '
               || (public.proveedor_recepcion_corregir('7e000000-0000-4000-8000-000000051810', '7e000000-0000-4000-8000-000000051812',
                 jsonb_build_array(jsonb_build_object('line_id', :'l6', 'packs_delta', -2)), 'Contamos de más') ->> 'max_packs'),
               'bad_qty 1.0000', '6 taking back 2 boxes from a delivery that brought 1: refused (at most 1)');
select test.eq(public.proveedor_recepcion_corregir('7e000000-0000-4000-8000-000000051810', '7e000000-0000-4000-8000-000000051812',
                 jsonb_build_array(jsonb_build_object('line_id', :'l6', 'packs_delta', -1)), 'Contamos de más') ->> 'ok', 'true', '6 one box back: corrected');
reset role;
select test.ok((select c.qty = -o.qty and c.unit_cost = o.unit_cost from public.stock_moves c, public.stock_moves o
                 where c.receipt_id = '7e000000-0000-4000-8000-000000051812' and o.receipt_id = '7e000000-0000-4000-8000-000000051810'),
               '6 the same 24 units back, at the cost that delivery booked');
set role authenticated;
select test.eq(public.proveedor_recepcion_corregir('7e000000-0000-4000-8000-000000051810', '7e000000-0000-4000-8000-000000051813',
                 jsonb_build_array(jsonb_build_object('line_id', :'l6', 'packs_delta', -1)), 'Otra vez') ->> 'error', 'bad_qty',
               '6 and nothing more from it (its corrections count)');
reset role;

-- (7) an invoice saved in Contabilidad (supplier_invoice_save) takes the delivery's corrections with it; a payment made
--     in Proveedores is applied by «Aplicar» from the books' door ----------------------------------------------------------
select test.login('cafe'); select test.session('dev-518-m'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select test.eq(public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051801', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051802","packs":2,"pack_price":24000}]', null, '9a000000-0000-4000-8000-000000051807') ->> 'ok', 'true',
               '7 (2 boxes of 24 at ₡24 000)');
select test.line518('9a000000-0000-4000-8000-000000051807', '5a000000-0000-4000-8000-000000051802') as l7 \gset
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051807', '7e000000-0000-4000-8000-000000051820', test.v518('9a000000-0000-4000-8000-000000051807'),
                 jsonb_build_array(jsonb_build_object('line_id', :'l7', 'rest', true))) ->> 'status', 'received', '7 (both arrive)');
select test.eq(public.proveedor_recepcion_corregir('7e000000-0000-4000-8000-000000051820', '7e000000-0000-4000-8000-000000051821',
                 jsonb_build_array(jsonb_build_object('line_id', :'l7', 'packs_delta', -1)), 'Una caja venía vacía') ->> 'ok', 'true', '7 (one box taken back by a correction)');
select test.eq(public.proveedor_pedido_cerrar('9a000000-0000-4000-8000-000000051807', test.v518('9a000000-0000-4000-8000-000000051807'), 'No la reponen') ->> 'status',
               'received', '7 (the rest closed: unpaid, a manager''s)');
select test.eq(public.proveedor_pago_registrar(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000051801', 'po_id', '9a000000-0000-4000-8000-000000051807', 'amount', 27120, 'method', 'sinpe',
                 'reference', 'SINPE-518-07'), '5d000000-0000-4000-8000-000000051807', test.staff('ana'), '4826') ->> 'ok', 'true', '7 (₡27 120 paid by SINPE in Proveedores)');
select test.login('accountant', 'aal2'); set role authenticated;
select public.supplier_invoice_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000051801', 'number', 'F-518-7', 'date', public.cr_today(), 'net_crc', 24000, 'iva_crc', 3120,
         'receipt_ids', jsonb_build_array('7e000000-0000-4000-8000-000000051820')), '5e000000-0000-4000-8000-000000051807') as inv7 \gset
select test.eq((:'inv7'::jsonb) ->> 'ok' || ' ' || ((:'inv7'::jsonb) ->> 'difference'), 'true 0.00',
               '7 the invoice of one box, saved with only the delivery (as Contabilidad sends it): no difference, the correction went with it');
reset role;
select test.eq((select string_agg(origin || ':' || coalesce(invoice_id::text, '-'), ' ' order by origin) from public.purchase_receipts where po_id = '9a000000-0000-4000-8000-000000051807'),
               'correccion:5e000000-0000-4000-8000-000000051807 proveedores:5e000000-0000-4000-8000-000000051807', '7 both deliveries carry the invoice');
select test.eq((select count(*)::int from acct.lines l join acct.entries e on e.id = l.entry_id where e.source_key = 'supinv:5e000000-0000-4000-8000-000000051807'
                  and l.account = acct.map('price_variance')), 0, '7 no price difference posted (5103 shows no false gain)');
select test.eq(public._invoice_open('5e000000-0000-4000-8000-000000051807'), 27120.00, '7 (the invoice is open: the Proveedores payment is not applied by itself)');
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.proveedor_anticipos_aplicar('5b000000-0000-4000-8000-000000051801') ->> 'applied_crc', '27120.00', '7 «Aplicar» (what Contabilidad now calls after an invoice): the payment goes to it');
reset role;
select test.eq(public._invoice_open('5e000000-0000-4000-8000-000000051807'), 0.00, '7 the invoice is paid, never twice');

-- (8) Contabilidad's audit sees Proveedores' money and SINPE events (the accountant), never the café login -----------------
select test.login('accountant', 'aal2'); set role authenticated;
select public.proveedores_bitacora(public.cr_today() - 1, public.cr_today()) as bit \gset
select test.eq((select string_agg(distinct x ->> 'action', ' ' order by x ->> 'action') from jsonb_array_elements((:'bit'::jsonb) -> 'rows') x),
               'supplier_advance supplier_advance_apply', '8 the accountant reads the payment and its application of this test (the invoice was saved through supplier_invoice_save: Contabilidad''s own list has it)');
select test.eq(public.proveedores_bitacora(public.cr_today(), public.cr_today() - 1) ->> 'error', 'bad_range', '8 a range backwards is refused');
select test.login('cafe'); select test.session('dev-518-m'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select test.eq(public.proveedores_bitacora(public.cr_today() - 1, public.cr_today()) ->> 'error', 'not_allowed', '8 not the café login (a manager unlock)');
reset role;

-- (9) consistency-check: a payment ahead for an order still open is not a problem; one that could go to an open invoice of
--     its own order (saved elsewhere, nothing applied it) is ------------------------------------------------------------------
\set tmp518 `mktemp`
select test.login('cafe'); select test.session('dev-518-m'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select test.eq(public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051801', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051802","packs":1,"pack_price":24000}]', null, '9a000000-0000-4000-8000-000000051809') ->> 'ok', 'true',
               '9 (an order of one box, still open)');
select test.eq(public.proveedor_pago_registrar(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000051801', 'po_id', '9a000000-0000-4000-8000-000000051809', 'amount', 27120, 'method', 'sinpe',
                 'reference', 'SINPE-518-09'), '5d000000-0000-4000-8000-000000051809', test.staff('ana'), '4826') ->> 'ok', 'true', '9 (paid ahead)');
reset role;
-- another order, received, its invoice saved the old way (as Contabilidad does) and left open
set role authenticated;
select test.eq(public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051801', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051802","packs":1,"pack_price":24000}]', null, '9a000000-0000-4000-8000-000000051810') ->> 'ok', 'true',
               '9 (another order)');
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051810', '7e000000-0000-4000-8000-000000051831', test.v518('9a000000-0000-4000-8000-000000051810'),
                 jsonb_build_array(jsonb_build_object('line_id', test.line518('9a000000-0000-4000-8000-000000051810', '5a000000-0000-4000-8000-000000051802'), 'rest', true))) ->> 'status',
               'received', '9 (it arrives)');
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.supplier_invoice_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000051801', 'number', 'F-518-10', 'date', public.cr_today(), 'net_crc', 24000, 'iva_crc', 3120,
                 'receipt_ids', jsonb_build_array('7e000000-0000-4000-8000-000000051831')), '5e000000-0000-4000-8000-000000051810') ->> 'ok', 'true', '9 (its invoice, open)');
reset role;
\pset format unaligned
\pset tuples_only on
\o :tmp518
\ir ../../supabase/tools/consistency-check.sql
\o
\pset tuples_only off
\pset format aligned
\set j518 `cat :'tmp518'`
select test.eq((:'j518'::jsonb) #>> '{after,vendors_unapplied_with_open_invoices}', '0',
               '9 consistency-check: a payment ahead for an order still open, beside an open invoice of another order, counts 0 (it waits for its own)');
-- the order arrives and its invoice is saved the old way (supplier_invoice_save, which applies nothing)
select test.login('cafe'); select test.session('dev-518-m'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051809', '7e000000-0000-4000-8000-000000051830', test.v518('9a000000-0000-4000-8000-000000051809'),
                 jsonb_build_array(jsonb_build_object('line_id', test.line518('9a000000-0000-4000-8000-000000051809', '5a000000-0000-4000-8000-000000051802'), 'rest', true))) ->> 'status',
               'received', '9 (the paid order arrives)');
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.supplier_invoice_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000051801', 'number', 'F-518-9', 'date', public.cr_today(), 'net_crc', 24000, 'iva_crc', 3120,
                 'receipt_ids', jsonb_build_array('7e000000-0000-4000-8000-000000051830')), '5e000000-0000-4000-8000-000000051809') ->> 'ok', 'true', '9 (its invoice, the old way)');
reset role;
\pset format unaligned
\pset tuples_only on
\o :tmp518
\ir ../../supabase/tools/consistency-check.sql
\o
\pset tuples_only off
\pset format aligned
\set j518 `cat :'tmp518'`
select test.eq((:'j518'::jsonb) #>> '{after,vendors_unapplied_with_open_invoices}', '1',
               '9 consistency-check: the payment could go to its own order''s open invoice and nothing applied it: counted');

-- (10) the money of each order when one invoice covers several, the supplier's «in favour», dollars, a drawer payout -----------
insert into public.vendors (id, name) values ('5b000000-0000-4000-8000-000000051802', 'Verduras 518');
insert into public.vendor_items (id, vendor_id, item_id, pack_label, pack_qty, usual_price) values ('5c000000-0000-4000-8000-000000051803', '5b000000-0000-4000-8000-000000051802', '5a000000-0000-4000-8000-000000051801', null, 12, 12000);
create function test.pay518(o text, amount numeric, ref text, id text) returns jsonb language sql as $$
  select public.proveedor_pago_registrar(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000051802', 'po_id', o, 'amount', amount, 'method', 'sinpe', 'reference', ref),
                                         id::uuid, test.staff('ana'), '4826') $$;
create function test.m518(o text) returns text language sql security definer as $$
  select (m ->> 'status') || ' ' || (m ->> 'paid') || ' ' || (m ->> 'credit') || ' ' || (m ->> 'saldo') from public._prov_dinero(o::uuid) m $$;
select test.login('cafe'); select test.session('dev-518-m'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select count(*) from (select public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051802', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051803","packs":1}]', null, x::uuid) from unnest(array['9a000000-0000-4000-8000-000000051811', '9a000000-0000-4000-8000-000000051812', '9a000000-0000-4000-8000-000000051813', '9a000000-0000-4000-8000-000000051814', '9a000000-0000-4000-8000-000000051815']) x) z;
select test.eq((test.pay518('9a000000-0000-4000-8000-000000051811', 13560, 'SINPE-518-11', '5d000000-0000-4000-8000-000000051811') ->> 'ok') || (test.pay518('9a000000-0000-4000-8000-000000051812', 13560, 'SINPE-518-12', '5d000000-0000-4000-8000-000000051812') ->> 'ok'),
               'truetrue', '10 (two orders paid ahead, ₡13 560 each)');
reset role;
select test.eq((public._prov_vendor_money('5b000000-0000-4000-8000-000000051802')) ->> 'credit_crc', '0.00', '10 two orders paid ahead and not delivered: nothing in our favour (each payment waits for its order)');
set role authenticated;
select count(*) from (select public.proveedor_recibir(x::uuid, ('7e000000-0000-4000-8000-0000000519' || right(x, 2))::uuid, test.v518(x), jsonb_build_array(jsonb_build_object('line_id', test.line518(x, '5a000000-0000-4000-8000-000000051801'), 'rest', true)))
                        from unnest(array['9a000000-0000-4000-8000-000000051811', '9a000000-0000-4000-8000-000000051812', '9a000000-0000-4000-8000-000000051813', '9a000000-0000-4000-8000-000000051814', '9a000000-0000-4000-8000-000000051815']) x) z;
select test.eq(test.pay518('9a000000-0000-4000-8000-000000051813', 13560, 'SINPE-518-13', '5d000000-0000-4000-8000-000000051813') ->> 'ok', 'true', '10 (a third order paid, after it arrived)');
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.proveedor_factura_registrar('5b000000-0000-4000-8000-000000051802', array['7e000000-0000-4000-8000-000000051911', '7e000000-0000-4000-8000-000000051912']::uuid[],
                 jsonb_build_object('number', 'F-518-AB', 'date', public.cr_today(), 'net', 24000, 'iva', 3120), '5e000000-0000-4000-8000-000000051811') ->> 'open_crc', '0.00',
               '10 one invoice for the two prepaid orders: both payments go to it');
select test.eq(public.proveedor_factura_registrar('5b000000-0000-4000-8000-000000051802', array['7e000000-0000-4000-8000-000000051913', '7e000000-0000-4000-8000-000000051914']::uuid[],
                 jsonb_build_object('number', 'F-518-CD', 'date', public.cr_today(), 'net', 24000, 'iva', 3120), '5e000000-0000-4000-8000-000000051813') ->> 'open_crc', '13560.00',
               '10 one invoice for a paid order and an unpaid one: half of it open');
reset role;
select test.eq(test.m518('9a000000-0000-4000-8000-000000051811') || ' | ' || test.m518('9a000000-0000-4000-8000-000000051812'), 'paid 13560.00 0.00 0.00 | paid 13560.00 0.00 0.00',
               '10 each order counts its own payment once: paid, nothing «in favour» that does not exist');
select test.eq(test.m518('9a000000-0000-4000-8000-000000051813') || ' | ' || test.m518('9a000000-0000-4000-8000-000000051814'), 'paid 13560.00 0.00 0.00 | pending 0.00 0.00 13560.00',
               '10 the paid order is paid; the unpaid one owes its real amount');
select test.login('cafe'); select test.session('dev-518-m'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select test.eq(test.pay518('9a000000-0000-4000-8000-000000051814', 13560, 'SINPE-518-14', '5d000000-0000-4000-8000-000000051814') ->> 'ok', 'true', '10 and its payment of that amount is a manager''s (not «more than owed»)');
reset role;
select test.eq(public._invoice_open('5e000000-0000-4000-8000-000000051813'), 0.00, '10 the invoice is paid');
-- the published page's drawer payout ₡0.50 above the invoice, with no other invoice open: the page''s own words
insert into public.purchase_orders (id, vendor_id, status) values ('9a000000-0000-4000-8000-000000051816', '5b000000-0000-4000-8000-000000051802', 'sent');
insert into public.purchase_lines (id, po_id, item_id, packs, qty, unit_cost) values ('9b000000-0000-4000-8000-000000051816', '9a000000-0000-4000-8000-000000051816', '5a000000-0000-4000-8000-000000051801', 1, 12, 1000);
select test.login('cafe'); select test.session('dev-518-m'); set role authenticated;
select test.eq(public.register_open(test.staff('ana'), '4826', 50000, 0) ->> 'ok', 'true', '10 (the register opens)');
select test.unlock(test.staff('ana'), '4826');
select test.eq(public.po_receive_and_settle('9a000000-0000-4000-8000-000000051816', '[{"line_id":"9b000000-0000-4000-8000-000000051816","qty":12}]', '7e000000-0000-4000-8000-000000051916', false,
                 '{"mode":"pending"}', '[{"method":"register","amount_crc":13560}]', test.staff('ana'), '4826') ->> 'invoice_status', 'pending',
               '10 (the published page received and paid ₡13 560 from the drawer)');
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.proveedor_factura_registrar('5b000000-0000-4000-8000-000000051802', array['7e000000-0000-4000-8000-000000051916']::uuid[], jsonb_build_object('number', 'F-518-16', 'date', public.cr_today(), 'net', 11999.50, 'iva', 1560),
                 gen_random_uuid()) ->> 'error', 'payout_exceeds', '10 an invoice ₡0.50 under the payout, nothing else open: «payout_exceeds», never a generic error');
reset role;

-- dollars: the amounts and the rate to 2 decimals before the colones (as po_receipt_settle)
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.proveedor_factura_registrar('5b000000-0000-4000-8000-000000051802', array['7e000000-0000-4000-8000-000000051915']::uuid[],
                 jsonb_build_object('number', 'US-518', 'date', public.cr_today(), 'currency', 'USD', 'fx_rate', 512.345, 'net', 23.455, 'iva', 3.0495),
                 '5e000000-0000-4000-8000-000000051815') ->> 'ok', 'true', '10 (a dollar invoice with long decimals)');
reset role;
select test.eq((select fx_rate || ' ' || net_fx || ' ' || iva_fx || ' ' || net_crc || ' ' || iva_crc from public.supplier_invoices where id = '5e000000-0000-4000-8000-000000051815'),
               '512.35 23.46 3.05 12019.73 1562.67', '10 stored rounded first: the dollars times the rate give the colones');

-- (11) a SINPE already registered as an expense payment in Contabilidad (any supplier, any page) --------------------------------
reset role;
insert into public.expenses (id, date, description, account, amount_crc, paid_from, created_by) values
  ('5e000000-0000-4000-8000-000000051890', public.cr_today(), 'Gas para la cocina', '5201', 8000, 'bank', 'prueba 518');
insert into public.expense_payments (id, expense_id, date, amount_crc, paid_from, reference, created_by) values
  ('5e000000-0000-4000-8000-000000051891', '5e000000-0000-4000-8000-000000051890', public.cr_today(), 8000, 'bank', 'BCR 4455-9911', 'prueba 518');
select test.login('owner', 'aal2'); set role authenticated;
select public.proveedor_pago_registrar('{"vendor_id":"5b000000-0000-4000-8000-000000051801","amount":1000,"method":"sinpe","reference":"bcr 44559911"}',
         '5d000000-0000-4000-8000-000000051890') as dx \gset
select test.eq((:'dx'::jsonb) ->> 'error' || ' · ' || ((:'dx'::jsonb) ->> 'vendor_name') || ' · ' || ((:'dx'::jsonb) ->> 'amount'),
               'duplicate_reference · Gas para la cocina · 8000.00', '11 the transfer already paid an expense: «Ese número de SINPE ya está registrado» (what, how much)');
reset role;
select test.eq((select count(*)::int from public.supplier_advances where id = '5d000000-0000-4000-8000-000000051890'), 0, '11 nothing registered');

-- (12) a correction goes with the delivery it corrects, never with another delivery of the same order ---------------------------
reset role;
insert into public.vendors (id, name) values ('5b000000-0000-4000-8000-000000051812', 'Familia 518');
insert into public.stock_items (id, name, unit, pack_label, pack_qty, cost_per_pack) values ('5a000000-0000-4000-8000-000000051812', 'Agua F', 'unit', null, 12, 12000);
insert into public.vendor_items (id, vendor_id, item_id, pack_label, pack_qty, usual_price) values
  ('5c000000-0000-4000-8000-000000051812', '5b000000-0000-4000-8000-000000051812', '5a000000-0000-4000-8000-000000051812', null, 12, 12000);
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051812', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051812","packs":10}]', null,
                 '9a000000-0000-4000-8000-000000051a12') ->> 'ok', 'true', '12 (10 boxes at ₡12 000)');
select test.line518('9a000000-0000-4000-8000-000000051a12', '5a000000-0000-4000-8000-000000051812') as l12 \gset
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051a12', '7e000000-0000-4000-8000-000000051a01', test.v518('9a000000-0000-4000-8000-000000051a12'),
                 jsonb_build_array(jsonb_build_object('line_id', :'l12', 'packs', 4))) ->> 'status', 'partially_received', '12 (R1: 4 boxes)');
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051a12', '7e000000-0000-4000-8000-000000051a02', test.v518('9a000000-0000-4000-8000-000000051a12'),
                 jsonb_build_array(jsonb_build_object('line_id', :'l12', 'packs', 6))) ->> 'status', 'received', '12 (R2: 6 boxes)');
reset role;
update public.purchase_receipts set received_at = now() - interval '3 hours' where id = '7e000000-0000-4000-8000-000000051a01';
update public.purchase_receipts set received_at = now() - interval '2 hours' where id = '7e000000-0000-4000-8000-000000051a02';
set role authenticated;
select test.eq(public.proveedor_recepcion_corregir('7e000000-0000-4000-8000-000000051a02', '7e000000-0000-4000-8000-000000051a03',
                 jsonb_build_array(jsonb_build_object('line_id', :'l12', 'packs_delta', -1)), 'Llegaron 5, no 6') ->> 'ok', 'true', '12 (C2 corrects R2 by one box)');
reset role;
update public.purchase_receipts set received_at = now() - interval '1 hour' where id = '7e000000-0000-4000-8000-000000051a03';
select test.login('accountant', 'aal2'); set role authenticated;
select public.supplier_invoice_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000051812', 'number', 'F-12-1', 'date', public.cr_today(), 'net_crc', 48000, 'iva_crc', 6240,
         'receipt_ids', jsonb_build_array('7e000000-0000-4000-8000-000000051a01')), '5e000000-0000-4000-8000-000000051a01') as f121 \gset
reset role;
select test.eq((:'f121'::jsonb) ->> 'difference' || ' ' || (select receipt_ids::text from public.supplier_invoices where id = '5e000000-0000-4000-8000-000000051a01'),
               '0.00 {7e000000-0000-4000-8000-000000051a01}', '12 Contabilidad''s invoice of R1 covers R1 only: R2''s correction is not R1''s (no false 5103)');
select test.eq((select count(*)::int from acct.lines l join acct.entries e on e.id = l.entry_id where e.source_key = 'supinv:5e000000-0000-4000-8000-000000051a01'
                 and l.account = acct.map('price_variance')), 0, '12 (nothing to price variance)');
select test.eq((public._prov_dinero('9a000000-0000-4000-8000-000000051a12') ->> 'due') || ' ' || (public._prov_dinero('9a000000-0000-4000-8000-000000051a12') ->> 'saldo'),
               '126240.00 135600.00', '12 the order owes F-1, R2 net of its correction (60 000) and the box it reopened (12 000), with the IVA allowance on what has no invoice, never ₡12 000 more');
set role authenticated;
savepoint s12;
select test.eq(coalesce(public.proveedor_recepcion_corregir('7e000000-0000-4000-8000-000000051a02', '7e000000-0000-4000-8000-000000051a04',
                 jsonb_build_array(jsonb_build_object('line_id', :'l12', 'packs_delta', -1)), 'Otra caja rota') ->> 'error', 'ok'), 'ok',
               '12 R2 (no invoice) can still be corrected');
rollback to savepoint s12;
select test.eq(public.proveedor_factura_registrar('5b000000-0000-4000-8000-000000051812', array['7e000000-0000-4000-8000-000000051a02']::uuid[],
                 jsonb_build_object('number', 'F-12-2', 'date', public.cr_today(), 'net', 60000, 'iva', 7800), '5e000000-0000-4000-8000-000000051a02') ->> 'ok', 'true',
               '12 (Proveedores registers R2''s invoice: 5 boxes)');
reset role;
select test.eq((select receipt_ids::text || ' ' || received_crc from public.supplier_invoices where id = '5e000000-0000-4000-8000-000000051a02'),
               '{7e000000-0000-4000-8000-000000051a02,7e000000-0000-4000-8000-000000051a03} 60000.00', '12 R2''s invoice takes its own correction: received 60 000');
select test.eq((select count(*)::int from acct.lines l join acct.entries e on e.id = l.entry_id where e.source_key like 'supinv:5e000000-0000-4000-8000-000000051a0%'
                 and l.account = acct.map('price_variance')), 0, '12 no price difference on either invoice');
select test.eq(public._prov_dinero('9a000000-0000-4000-8000-000000051a12') ->> 'due', '134040.00', '12 the order owes the two invoices exactly (54 240 + 67 800) and the box still to come');

-- (13) one invoice over two orders: each order's own payment counts up to its share, the rest goes to the one still owing ---
insert into public.vendors (id, name) values ('5b000000-0000-4000-8000-000000051813', 'Dos pedidos 518');
insert into public.stock_items (id, name, unit, pack_label, pack_qty, cost_per_pack) values ('5a000000-0000-4000-8000-000000051813', 'Agua G', 'unit', null, 12, 12000);
insert into public.vendor_items (id, vendor_id, item_id, pack_label, pack_qty, usual_price) values
  ('5c000000-0000-4000-8000-000000051813', '5b000000-0000-4000-8000-000000051813', '5a000000-0000-4000-8000-000000051813', null, 12, 12000);
create function test.m518b(o text) returns text language sql security definer as $$
  select (m ->> 'status') || ' paid=' || (m ->> 'paid') || ' credit=' || (m ->> 'credit') || ' saldo=' || (m ->> 'saldo') from public._prov_dinero(o::uuid) m $$;
select test.login('cafe'); select test.session('dev-518b'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select test.eq(public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051813', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051813","packs":1}]', null,
                 '9a000000-0000-4000-8000-000000051a31') ->> 'ok', 'true', '13 (order X, 1 box)');
select test.eq(public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051813', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051813","packs":1}]', null,
                 '9a000000-0000-4000-8000-000000051a32') ->> 'ok', 'true', '13 (order Y, 1 box)');
select test.eq(public.proveedor_pago_registrar(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000051813', 'po_id', '9a000000-0000-4000-8000-000000051a31', 'amount', 13560,
                 'method', 'sinpe', 'reference', 'SINPE-518-13X'), '5d000000-0000-4000-8000-000000051a31', test.staff('ana'), '4826') ->> 'ok', 'true', '13 (X paid ahead by SINPE, ₡13 560)');
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051a31', '7e000000-0000-4000-8000-000000051a31', test.v518('9a000000-0000-4000-8000-000000051a31'),
                 jsonb_build_array(jsonb_build_object('line_id', test.line518('9a000000-0000-4000-8000-000000051a31', '5a000000-0000-4000-8000-000000051813'), 'rest', true))) ->> 'status',
               'received', '13 (X arrives)');
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051a32', '7e000000-0000-4000-8000-000000051a32', test.v518('9a000000-0000-4000-8000-000000051a32'),
                 jsonb_build_array(jsonb_build_object('line_id', test.line518('9a000000-0000-4000-8000-000000051a32', '5a000000-0000-4000-8000-000000051813'), 'rest', true))) ->> 'status',
               'received', '13 (Y arrives)');
reset role;
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.supplier_invoice_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000051813', 'number', 'F-13', 'date', public.cr_today(), 'net_crc', 24000, 'iva_crc', 3120,
                 'receipt_ids', jsonb_build_array('7e000000-0000-4000-8000-000000051a31', '7e000000-0000-4000-8000-000000051a32')), '5e000000-0000-4000-8000-000000051a13') ->> 'ok', 'true',
               '13 (Contabilidad: one invoice of ₡27 120 for both deliveries)');
select test.eq(public.proveedor_anticipos_aplicar('5b000000-0000-4000-8000-000000051813') ->> 'applied_crc', '13560.00', '13 (X''s SINPE applied to it)');
select test.eq(public.supplier_payment_save(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000051813', 'amount_crc', 13560, 'paid_from', 'bank', 'date', public.cr_today(),
                 'reference', 'BCR 518-13', 'invoice_ids', jsonb_build_array('5e000000-0000-4000-8000-000000051a13')), '5f000000-0000-4000-8000-000000051a13') ->> 'ok', 'true',
               '13 (the accountant pays the rest by bank)');
reset role;
select test.eq(test.m518b('9a000000-0000-4000-8000-000000051a31') || ' | ' || test.m518b('9a000000-0000-4000-8000-000000051a32'),
               'paid paid=13560.00 credit=0.00 saldo=0.00 | paid paid=13560.00 credit=0.00 saldo=0.00',
               '13 the invoice is paid: both orders read paid, no phantom credit on X, no phantom balance on Y');
select test.login('cafe'); select test.session('dev-518b'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select test.eq(public.proveedor_pago_registrar(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000051813', 'po_id', '9a000000-0000-4000-8000-000000051a32', 'amount', 6780,
                 'method', 'sinpe', 'reference', 'SINPE-518-13Y'), '5d000000-0000-4000-8000-000000051a32', test.staff('ana'), '4826') ->> 'error', 'over_balance',
               '13 a manager paying Y again is told it is more than owed (only the owner could leave it in our favour)');
-- X's prepayment larger than its share pays a shared invoice in full: the other order reads paid too
select test.eq(public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051813', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051813","packs":2}]', null,
                 '9a000000-0000-4000-8000-000000051a33') ->> 'ok', 'true', '13 (order Z, 2 boxes)');
select test.eq(public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051813', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051813","packs":1}]', null,
                 '9a000000-0000-4000-8000-000000051a34') ->> 'ok', 'true', '13 (order W, 1 box)');
select test.eq(public.proveedor_pago_registrar(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000051813', 'po_id', '9a000000-0000-4000-8000-000000051a33', 'amount', 27120,
                 'method', 'sinpe', 'reference', 'SINPE-518-13Z'), '5d000000-0000-4000-8000-000000051a33', test.staff('ana'), '4826') ->> 'ok', 'true', '13 (Z paid ahead, ₡27 120)');
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051a33', '7e000000-0000-4000-8000-000000051a33', test.v518('9a000000-0000-4000-8000-000000051a33'),
                 jsonb_build_array(jsonb_build_object('line_id', test.line518('9a000000-0000-4000-8000-000000051a33', '5a000000-0000-4000-8000-000000051813'), 'packs', 1))) ->> 'status',
               'partially_received', '13 (one box of Z arrives)');
select test.eq(public.proveedor_pedido_cerrar('9a000000-0000-4000-8000-000000051a33', test.v518('9a000000-0000-4000-8000-000000051a33'), 'No traen la otra') ->> 'ok', 'true', '13 (the rest of Z closed)');
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051a34', '7e000000-0000-4000-8000-000000051a34', test.v518('9a000000-0000-4000-8000-000000051a34'),
                 jsonb_build_array(jsonb_build_object('line_id', test.line518('9a000000-0000-4000-8000-000000051a34', '5a000000-0000-4000-8000-000000051813'), 'rest', true))) ->> 'status',
               'received', '13 (W arrives)');
reset role;
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.proveedor_factura_registrar('5b000000-0000-4000-8000-000000051813', array['7e000000-0000-4000-8000-000000051a33', '7e000000-0000-4000-8000-000000051a34']::uuid[],
                 jsonb_build_object('number', 'F-13B', 'date', public.cr_today(), 'net', 24000, 'iva', 3120), '5e000000-0000-4000-8000-000000051a14') ->> 'open_crc', '0.00',
               '13 (one invoice for Z''s box and W: Z''s prepayment pays it in full)');
reset role;
select test.eq(test.m518b('9a000000-0000-4000-8000-000000051a33') || ' | ' || test.m518b('9a000000-0000-4000-8000-000000051a34'),
               'paid paid=13560.00 credit=0.00 saldo=0.00 | paid paid=13560.00 credit=0.00 saldo=0.00',
               '13 both read paid: Z''s payment beyond its share pays W''s part');
select test.login('cafe'); select test.session('dev-518b'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select test.eq(public.proveedor_pago_registrar(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000051813', 'po_id', '9a000000-0000-4000-8000-000000051a34', 'amount', 13560,
                 'method', 'sinpe', 'reference', 'SINPE-518-13W'), '5d000000-0000-4000-8000-000000051a34', test.staff('ana'), '4826') ->> 'error', 'over_balance',
               '13 and W cannot be paid again by a manager');
reset role;
select test.eq(public._prov_excess('5b000000-0000-4000-8000-000000051813'), 0.00, '13 nothing in our favour with this supplier');

select test.done();
rollback;
