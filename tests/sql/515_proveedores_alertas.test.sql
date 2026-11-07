-- Migration 0039 (Proveedores, D-067): the low-stock alerts (proveedores_alertas). They reuse inventory_stats(30)'s own
-- rule and levels (out, low, soon; reorder point, par level, use over the lead days), point to the preferred supplier's
-- live catalog row of the item (the smallest presentation), and never suggest ordering again what is already on order
-- with any supplier; «Ya pedido» lists those orders. Only for management. The legacy inventory_alerts is unchanged.
begin;
insert into public.vendors (id, name, lead_days) values ('5b000000-0000-4000-8000-000000051501', 'Lácteos Monteverde', 2),
                                                        ('5b000000-0000-4000-8000-000000051502', 'Verduras del Valle', 2),
                                                        ('5b000000-0000-4000-8000-000000051503', 'Cerrado SA', 2);
insert into public.stock_items (id, name, unit, pack_qty, cost_per_pack, on_hand, reorder_point, par_level, vendor_id, active) values
  ('5a000000-0000-4000-8000-000000051501', 'A Leche', 'unit', 12, 12000, 0, 12, 48, '5b000000-0000-4000-8000-000000051501', true),
  ('5a000000-0000-4000-8000-000000051502', 'B Queso', 'g', 500, 1750, 1000, 2000, 4000, '5b000000-0000-4000-8000-000000051501', true),
  ('5a000000-0000-4000-8000-000000051503', 'C Azúcar', 'kg', 1, 800, 5, 5, 5, '5b000000-0000-4000-8000-000000051502', true),
  ('5a000000-0000-4000-8000-000000051504', 'D Crema', 'ml', 1000, 2000, 0, 0, 2000, '5b000000-0000-4000-8000-000000051503', true),
  ('5a000000-0000-4000-8000-000000051505', 'E Pan', 'unit', 10, 3000, 0, 0, 20, '5b000000-0000-4000-8000-000000051502', true),
  ('5a000000-0000-4000-8000-000000051506', 'F Café', 'kg', 1, 9000, 50, 5, 20, '5b000000-0000-4000-8000-000000051502', true),
  ('5a000000-0000-4000-8000-000000051507', 'G Viejo', 'unit', 1, 100, 0, 5, 10, '5b000000-0000-4000-8000-000000051502', false);
-- (the trigger gave each its supplier's row; more presentations, and one retired)
insert into public.vendor_items (id, vendor_id, item_id, pack_label, pack_qty, usual_price, usual_qty) values
  ('5c000000-0000-4000-8000-000000051511', '5b000000-0000-4000-8000-000000051501', '5a000000-0000-4000-8000-000000051501', 'media caja', 6, 6000, 3),
  ('5c000000-0000-4000-8000-000000051512', '5b000000-0000-4000-8000-000000051502', '5a000000-0000-4000-8000-000000051502', 'bloque de 2 kg', 2000, 7500, null),
  ('5c000000-0000-4000-8000-000000051515', '5b000000-0000-4000-8000-000000051502', '5a000000-0000-4000-8000-000000051505', 'bolsa de 5', 5, 1500, null);
update public.vendor_items set active = false where item_id = '5a000000-0000-4000-8000-000000051503';
update public.vendors set active = false where id = '5b000000-0000-4000-8000-000000051503';
-- bread: 33 bought, 30 sold over the month (1 a day): 3 left, 3 days for a 2-day lead time → «Por acabarse»
insert into public.stock_moves (item_id, kind, qty, unit_cost, at) values ('5a000000-0000-4000-8000-000000051505', 'purchase', 33, 300, now() - interval '25 days');
insert into public.stock_moves (item_id, kind, qty, at) select '5a000000-0000-4000-8000-000000051505', 'sale', -1, now() - make_interval(days => g) from generate_series(1, 30) g;
-- cheese already on order elsewhere: 2 blocks of 2 kg sent to the second supplier (4 000 g pending)
insert into public.purchase_orders (id, vendor_id, status) values ('9a000000-0000-4000-8000-000000051501', '5b000000-0000-4000-8000-000000051502', 'sent'),
                                                                 ('9a000000-0000-4000-8000-000000051502', '5b000000-0000-4000-8000-000000051502', 'draft');
insert into public.purchase_lines (po_id, item_id, packs, qty, unit_cost) values
  ('9a000000-0000-4000-8000-000000051501', '5a000000-0000-4000-8000-000000051502', 2, 4000, 3.75),
  ('9a000000-0000-4000-8000-000000051502', '5a000000-0000-4000-8000-000000051503', 10, 10, 800);
-- milk in an open draft
insert into public.purchase_drafts (vendor_id, lines) values ('5b000000-0000-4000-8000-000000051501', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051511","packs":2}]');
select (select po_number from public.purchase_orders where id = '9a000000-0000-4000-8000-000000051501') as po1 \gset

select test.login('cafe'); select test.session('dev-515'); set role authenticated;
select test.eq(public.proveedores_alertas(), '{"ok":false,"error":"locked"}'::jsonb, '0 a café device without the owner areas: no alerts');
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.proveedores_alertas() ->> 'error', 'locked', '0 nor the accountant (ordering is management''s)');
select test.login('cafe'); select test.session('dev-515'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select public.proveedores_alertas() as al \gset
select public.inventory_alerts() as legacy \gset
reset role;
create temp table al515 as select x from jsonb_array_elements((:'al'::jsonb) -> 'items') x;
select test.eq((select string_agg(x.v ->> 'name' || ':' || (x.v ->> 'status'), ' ' order by x.n) from jsonb_array_elements((:'al'::jsonb) -> 'items') with ordinality x(v, n)),
               'A Leche:out D Crema:out B Queso:low C Azúcar:low E Pan:soon', '1 out, then low, then soon (by days left, then name); the café and an inactive item are not alerts');
select test.eq((:'al'::jsonb) ->> 'count', '5', '1 count');
select test.eq((select x ->> 'vendor_item_id' || ' ' || (x ->> 'pack_label') || ' ' || (x ->> 'pack_qty') || ' ' || (x ->> 'suggest_packs') || ' ' || (x ->> 'in_draft')
                  from al515 where x ->> 'name' = 'A Leche'),
               '5c000000-0000-4000-8000-000000051511 media caja 6 8 true', '1 milk: the preferred supplier''s smallest presentation, 48 units to the par level = 8 half boxes; already in a draft');
select test.eq((select (x ->> 'on_order') || ' ' || (x -> 'on_order_po_numbers')::text || ' ' || (x ->> 'suggest_packs') from al515 where x ->> 'name' = 'B Queso'),
               '4000 [' || :po1 || '] 0', '1 cheese is on order with another supplier: «Ya pedido» (that order), nothing suggested again');
select test.eq((select coalesce(x ->> 'vendor_item_id', '-') || ' ' || (x ->> 'on_order') || ' ' || (x ->> 'suggest_packs') from al515 where x ->> 'name' = 'C Azúcar'),
               '- 0 1', '1 sugar: its supplier has no live row (the page offers «Asociar proveedor»); a draft order is not «on order»; at least 1');
select test.eq((select (x ->> 'vendor_active') || ' ' || (x ->> 'vendor_name') from al515 where x ->> 'name' = 'D Crema'), 'false Cerrado SA',
               '1 cream''s supplier is inactive (the page asks to choose another)');
-- who carries each item (their smallest live presentation), for «Asociar proveedor» without reading every supplier's file
select test.eq((select string_agg((s ->> 'vendor_name') || ':' || (s ->> 'pack_qty') || ':' || (s ->> 'vendor_active'), ' ' order by q.n) from al515,
                  jsonb_array_elements(x -> 'suppliers') with ordinality q(s, n) where x ->> 'name' = 'B Queso'),
               'Lácteos Monteverde:500:true Verduras del Valle:2000:true', '1 cheese: both suppliers that carry it, each with its presentation');
select test.eq((select (x -> 'suppliers' -> 0 ->> 'vendor_item_id') || ' ' || jsonb_array_length(x -> 'suppliers') from al515 where x ->> 'name' = 'A Leche'),
               '5c000000-0000-4000-8000-000000051511 1', '1 milk: one supplier, its smallest presentation');
select test.eq((select (x -> 'suppliers')::text from al515 where x ->> 'name' = 'C Azúcar'), '[]', '1 sugar: nobody carries it now (a retired row is not shown)');
select test.eq((select (x -> 'suppliers' -> 0 ->> 'vendor_active') from al515 where x ->> 'name' = 'D Crema'), 'false', '1 cream: an inactive supplier is marked so');
select test.eq((select (x ->> 'days_left') || ' ' || (x ->> 'suggest_packs') || ' ' || (x ->> 'pack_label') from al515 where x ->> 'name' = 'E Pan'), '3.0 4 bolsa de 5',
               '1 bread: 3 days left; par 20 − 3 + 2 days of use = 19 units → 4 bags of 5 (inventory_stats''s own quantity)');
-- an order sent for the milk (from the supplier's open draft, as the page does): it is no longer suggested, and the
-- legacy card is the same as before
select version as dv515 from public.purchase_drafts where vendor_id = '5b000000-0000-4000-8000-000000051501' and status = 'open' \gset
set role authenticated;
select test.eq(public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051501', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051511","packs":8}]', null,
                 '9a000000-0000-4000-8000-000000051503', :dv515) ->> 'ok', 'true', '2 (8 half boxes of milk are ordered)');
select test.eq((select x ->> 'suggest_packs' || ' ' || (x ->> 'on_order') from jsonb_array_elements(public.proveedores_alertas() -> 'items') x where x ->> 'name' = 'A Leche'), '0 48.0000',
               '2 milk is still out, but on order: nothing suggested again');
select test.eq(public.proveedores_lista() -> 'alerts', public.proveedores_alertas() -> 'items', '2 the supplier list carries the same alerts for the hub');
select test.eq(public.inventory_alerts(), :'legacy'::jsonb, '2 Home''s legacy inventory_alerts answers as before (the order does not change it)');
reset role;

select test.done();
rollback;
