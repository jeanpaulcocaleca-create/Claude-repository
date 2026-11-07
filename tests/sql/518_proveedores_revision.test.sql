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

select test.done();
rollback;
