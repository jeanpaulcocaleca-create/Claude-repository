-- Canopy OS rehearsal · the first hours after the migration window, on the migrated copy.
-- The pages still open on the tablets are the OLD ones until the new ones are published, and a tablet may
-- upload a sale it took offline before the window. Everything below must work; checked at the end.
\set ON_ERROR_STOP on
-- room orders open all day for the rehearsal (the café sets its own hours)
update public.app_settings set room_orders_enabled = true, room_open = '00:00', room_close = '23:59' where id = 1;

select set_config('request.jwt.claims', '{"sub":"c0000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1"}', false);
set role authenticated;
-- 1) a sale taken OFFLINE last night on an old page, uploaded now the old two-step way (order, then lines)
insert into public.orders (id, created_at, total_crc, payment_method, station, source, status)
  values ('0d000000-0000-4000-8000-0000000000c1', public.cr_day_start(public.cr_today()) - interval '4 hours', 3600, 'cash_crc', 'iPad', 'front', 'done');
insert into public.order_items (order_id, item_name, qty, price_crc)
  values ('0d000000-0000-4000-8000-0000000000c1', 'Café de la casa', 2, 1800);
-- 2) a sale on an old page today
insert into public.orders (id, total_crc, payment_method, station, source, status)
  values ('0d000000-0000-4000-8000-0000000000c2', 2200, 'card', 'Caja', 'front', 'done');
insert into public.order_items (order_id, item_name, qty, price_crc) values ('0d000000-0000-4000-8000-0000000000c2', 'Prueba vieja', 1, 2200);
-- 3) a sale on a new page (one call, with its product)
select public.pos_record_sale(jsonb_build_object(
  'id', '0d000000-0000-4000-8000-0000000000c3', 'created_at', now(), 'total_crc', m.price_crc * 2, 'payment_method', 'cash_crc',
  'paid', true, 'status', 'done', 'station', 'Caja',
  'items', jsonb_build_array(jsonb_build_object('id', '1e000000-0000-4000-8000-0000000000c3', 'item_name', m.name,
                                                'price_crc', m.price_crc, 'qty', 2, 'menu_item_id', m.id))))
  from (select id, name, price_crc from public.menu_items where price_crc > 0 order by name limit 1) m;
-- 4) the bill left open before the window is paid in full
select public.tab_pay('0d000000-0000-4000-8000-0000000000b2', 'cash_crc', null, null, 'Caja');
-- 5) a manager voids the old-page sale
select public.manager_void_order('a1000000-0000-4000-8000-000000000001', '4826', '0d000000-0000-4000-8000-0000000000c2', 'tarjeta rechazada');
reset role;

-- 5b) Proveedores (0039/0040, D-067). The old inventory page stays on the tablets until proveedores.html is published:
--     it writes its orders directly and receives them with po_receive_and_settle (also while the supplier has a payment
--     registered in Proveedores and not applied yet), and its drawer payouts are then documented by Proveedores' invoice.
--     The new path: a catalog row, an order of 2 boxes of 12, received by the person on shift through «Recibe en este
--     aparato» (no PIN in the receiving call) -> +24, the invoice, the SINPE payment -> «Pagado». Checked at the end.
--     The answers are kept (as the superuser) in a temporary table for the final check; the work-session token is not.
create temporary table ensayo_prov (k text primary key, v jsonb);
-- the owner with the phone code: Proveedores' management and books door, no PIN for a payment
select set_config('request.jwt.claims', '{"sub":"0e000000-0000-4000-8000-000000000002","role":"authenticated","aal":"aal2"}', false);
set role authenticated;
-- a payment ahead to Lácteos Monteverde (no order and nothing owed: more than the balance, with a reason): it stays unapplied
select public.proveedor_pago_registrar(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000000002', 'amount', 50000, 'method', 'sinpe',
         'reference', 'ENSAYO 0040-0001', 'excess_ok', true, 'excess_reason', 'Prepago de la semana'), '5d390000-0000-4000-8000-0000000000a1') as prov_adv \gset
-- the old page's order to that supplier, written directly as its createPo() does (a draft, then its line) ...
select 2 * pack_qty as old_qty, cost_per_pack / pack_qty as old_uc, round(2 * cost_per_pack, 2) as old_net, round(2 * cost_per_pack * 0.13, 2) as old_iva,
       round(2 * cost_per_pack, 2) + round(2 * cost_per_pack * 0.13, 2) as old_total
  from public.stock_items where id = '5e000000-0000-4000-8000-000000000006' \gset
insert into public.purchase_orders (id, vendor_id, status, by_name) values ('9a390000-0000-4000-8000-0000000000a1', '5b000000-0000-4000-8000-000000000002', 'draft', 'owner');
insert into public.purchase_lines (id, po_id, item_id, packs, qty, unit_cost)
  values ('9b390000-0000-4000-8000-0000000000a1', '9a390000-0000-4000-8000-0000000000a1', '5e000000-0000-4000-8000-000000000006', 2, :old_qty, :old_uc);
-- ... received, its invoice confirmed and paid by bank in one call with a manager's PIN (its «Confirm reception»)
select public.po_receive_and_settle('9a390000-0000-4000-8000-0000000000a1',
         jsonb_build_array(jsonb_build_object('line_id', '9b390000-0000-4000-8000-0000000000a1', 'qty', :old_qty, 'unit_cost', :old_uc, 'expires_on', public.cr_today() + 7)),
         '7e390000-0000-4000-8000-0000000000a1', false,
         jsonb_build_object('mode', 'confirm', 'number', 'LM-0039', 'date', public.cr_today(), 'currency', 'CRC', 'net', :old_net, 'iva', :old_iva),
         jsonb_build_array(jsonb_build_object('method', 'bank', 'amount_crc', :old_total, 'reference', 'BN ensayo 0039')),
         'a1000000-0000-4000-8000-000000000001', '4826') as prov_old \gset
-- the old page's order to Verduras Santa Elena, received with the invoice to come and paid in cash from the open register ...
select 4 * pack_qty as pay_qty, cost_per_pack / pack_qty as pay_uc, round(4 * cost_per_pack, 2) as pay_net, round(4 * cost_per_pack * 0.13, 2) as pay_iva,
       round(4 * cost_per_pack, 2) + round(4 * cost_per_pack * 0.13, 2) as pay_total
  from public.stock_items where id = '5e000000-0000-4000-8000-000000000008' \gset
insert into public.purchase_orders (id, vendor_id, status, by_name) values ('9a390000-0000-4000-8000-0000000000a2', '5b000000-0000-4000-8000-000000000004', 'draft', 'owner');
insert into public.purchase_lines (id, po_id, item_id, packs, qty, unit_cost)
  values ('9b390000-0000-4000-8000-0000000000a2', '9a390000-0000-4000-8000-0000000000a2', '5e000000-0000-4000-8000-000000000008', 4, :pay_qty, :pay_uc);
select public.po_receive_and_settle('9a390000-0000-4000-8000-0000000000a2',
         jsonb_build_array(jsonb_build_object('line_id', '9b390000-0000-4000-8000-0000000000a2', 'qty', :pay_qty, 'unit_cost', :pay_uc, 'expires_on', public.cr_today() + 7)),
         '7e390000-0000-4000-8000-0000000000a2', false, '{"mode":"pending"}'::jsonb,
         jsonb_build_array(jsonb_build_object('method', 'register', 'amount_crc', :pay_total)),
         'a1000000-0000-4000-8000-000000000001', '4826') as prov_payout \gset
-- ... and that drawer payout documented by the invoice registered in Proveedores (no number on the paper: S/N-…)
select public.proveedor_factura_registrar('5b000000-0000-4000-8000-000000000004', array['7e390000-0000-4000-8000-0000000000a2']::uuid[],
         jsonb_build_object('date', public.cr_today(), 'net', :pay_net, 'iva', :pay_iva), 'f1390000-0000-4000-8000-0000000000a2') as prov_doc \gset
-- the new page: Distribuidora Central also sells Insumo 7, by the box of 12 (a second supplier for that item), and it is ordered
select public.proveedor_producto_guardar(jsonb_build_object('id', 'c1390000-0000-4000-8000-0000000000a3', 'vendor_id', '5b000000-0000-4000-8000-000000000005',
         'item_id', '5e000000-0000-4000-8000-000000000007', 'vendor_code', 'DC-12', 'pack_label', 'caja de 12', 'pack_qty', 12, 'usual_price', 9000)) as prov_cat \gset
select public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000000005',
         '[{"vendor_item_id":"c1390000-0000-4000-8000-0000000000a3","packs":2}]'::jsonb, 'Entregar por la mañana', '9a390000-0000-4000-8000-0000000000a3') as prov_po \gset
reset role;
select on_hand as prov_before from public.stock_items where id = '5e000000-0000-4000-8000-000000000007' \gset
-- Luis, on shift since this morning, on the café tablet (its own sign-in): «Recibe en este aparato» with his PIN once, then
-- the delivery with «Todo recibido correctamente» and only the session's token
select set_config('request.jwt.claims', '{"sub":"c0000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1","session_id":"ensayo-bodega-1"}', false);
set role authenticated;
select public.turno_aqui('a1000000-0000-4000-8000-000000000002', '5284', 'Bodega') as prov_turno \gset
-- (a refusal leaves no token: the calls below then answer no_session, reported by the final check)
select coalesce((:'prov_turno'::jsonb) ->> 'token', '') as prov_tok \gset
select public.proveedores_por_recibir(:'prov_tok') as prov_list \gset
select public.proveedor_pedido('9a390000-0000-4000-8000-0000000000a3', :'prov_tok') as prov_doc_recv \gset
select public.proveedor_recibir('9a390000-0000-4000-8000-0000000000a3', '7e390000-0000-4000-8000-0000000000a3', ((:'prov_doc_recv'::jsonb) #>> '{order,version}')::int,
         jsonb_build_array(jsonb_build_object('line_id', (:'prov_doc_recv'::jsonb) #>> '{lines,0,id}', 'rest', true)), :'prov_tok') as prov_recv \gset
reset role;
select on_hand - :prov_before as prov_delta from public.stock_items where id = '5e000000-0000-4000-8000-000000000007' \gset
-- the owner with the code: the supplier's invoice of that delivery, then the SINPE payment of the order
select set_config('request.jwt.claims', '{"sub":"0e000000-0000-4000-8000-000000000002","role":"authenticated","aal":"aal2"}', false);
set role authenticated;
select public.proveedor_factura_registrar('5b000000-0000-4000-8000-000000000005', array['7e390000-0000-4000-8000-0000000000a3']::uuid[],
         jsonb_build_object('number', 'DC-0039', 'date', public.cr_today(), 'net', 18000, 'iva', 2340), 'f1390000-0000-4000-8000-0000000000a3') as prov_inv \gset
select public.proveedor_pago_registrar(jsonb_build_object('vendor_id', '5b000000-0000-4000-8000-000000000005', 'po_id', '9a390000-0000-4000-8000-0000000000a3',
         'amount', 20340, 'method', 'sinpe', 'reference', 'ENSAYO 0040-0002'), '5d390000-0000-4000-8000-0000000000a3') as prov_pay \gset
reset role;
insert into ensayo_prov (k, v) values ('adv', :'prov_adv'), ('old', :'prov_old'), ('payout', :'prov_payout'), ('doc', :'prov_doc'), ('cat', :'prov_cat'),
  ('po', :'prov_po'), ('turno', (:'prov_turno'::jsonb) - 'token'), ('list', :'prov_list'), ('recv_doc', :'prov_doc_recv'), ('recv', :'prov_recv'),
  ('delta', to_jsonb(:prov_delta::numeric)), ('inv', :'prov_inv'), ('pay', :'prov_pay');

select set_config('request.jwt.claims', '{"sub":"c0000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1"}', false);
set role authenticated;
-- 6) Luis clocks out (his shift began before the window): his «Recibe en este aparato» of 5b ends with it
select public.clock_punch('a1000000-0000-4000-8000-000000000002', '5284');
reset role;

-- 6b) discounts after 0038 (D-065). The old page's free window, with the switch pos_free_discount on (its default): an
--     approval and its sale, the old two-step way; a second approval whose sale waits in the tablet's offline queue
select set_config('request.jwt.claims', '{"sub":"c0000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1"}', false);
set role authenticated;
select public.approve_discount('a1000000-0000-4000-8000-000000000001', '4826', 'percent', 10, 3600, 'Regular customer', 'Caja') ->> 'id' as old_disc \gset
insert into public.orders (id, total_crc, payment_method, station, source, status, subtotal_crc, discount_crc, discount_id)
  values ('0d000000-0000-4000-8000-0000000000c4', 3240, 'cash_crc', 'Caja', 'front', 'done', 3600, 360, :'old_disc');
insert into public.order_items (order_id, item_name, qty, price_crc) values ('0d000000-0000-4000-8000-0000000000c4', 'Café de la casa', 2, 1800);
select public.approve_discount('a1000000-0000-4000-8000-000000000001', '4826', 'amount', 500, 2200, 'Promotion', 'iPad') ->> 'id' as queued_disc \gset
-- a reason that reads as a category is refused whether the switch is on or off (W2)
do $$ begin
  if public.approve_discount('a1000000-0000-4000-8000-000000000001', '4826', 'percent', 10, 2200, 'Other · Local', 'Caja') ->> 'error' <> 'missing_reason' then
    raise exception 'after: a free reason that reads as a category was approved'; end if;
end $$;
reset role;
-- the owner turns the old window off (the last step of the activation), with the SQL Editor tool
\ir ../../supabase/tools/descuento-libre-apagar.sql
select set_config('request.jwt.claims', '{"sub":"c0000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1"}', false);
set role authenticated;
do $$ begin
  begin
    perform public.approve_discount('a1000000-0000-4000-8000-000000000001', '4826', 'percent', 10, 2200, 'Promotion', 'Caja');
    raise exception 'after: the old window still approves with the switch off';
  exception when others then
    if sqlerrm <> 'approve_discount_off' then raise; end if;
  end;
end $$;
-- the queued sale with the old approval arrives after the switch is off: recorded as today
select public.pos_record_sale(jsonb_build_object(
  'id', '0d000000-0000-4000-8000-0000000000c5', 'created_at', now(), 'total_crc', 1700, 'payment_method', 'card', 'paid', true,
  'status', 'done', 'station', 'iPad', 'subtotal_crc', 2200, 'discount_crc', 500, 'discount_id', :'queued_disc',
  'items', jsonb_build_array(jsonb_build_object('item_name', 'Prueba vieja', 'price_crc', 2200, 'qty', 1))));
reset role;
-- the new window on a till a manager registered (Reloj de marcas → Bitácora): a Local discount whose sale is rung late
-- (the tablet's clock, D-045) is linked and flagged, never refused
select set_config('request.jwt.claims', '{"sub":"c0000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1","session_id":"ensayo-caja-1"}', false);
set role authenticated;
select public.access_unlock('a1000000-0000-4000-8000-000000000001', '4826') ->> 'token' as unlock_token \gset
select set_config('request.headers', jsonb_build_object('x-hg-unlock', :'unlock_token')::text, false);
select public.descuento_caja_registrar('Caja') ->> 'slot' as till_slot \gset
select set_config('request.headers', '{}', false);
select public.descuento_autorizar('local', '4826', 4000, p_station => 'Caja') ->> 'id' as cat_disc \gset
reset role;
update public.discount_approvals set created_at = created_at - interval '2 hours' where id = :'cat_disc';
select set_config('request.jwt.claims', '{"sub":"c0000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1","session_id":"ensayo-caja-1"}', false);
set role authenticated;
select public.pos_record_sale(jsonb_build_object(
  'id', '0d000000-0000-4000-8000-0000000000c6', 'created_at', now(), 'total_crc', 3600, 'payment_method', 'cash_crc', 'paid', true,
  'status', 'done', 'station', 'Caja', 'subtotal_crc', 4000, 'discount_crc', 400, 'discount_id', :'cat_disc',
  'items', jsonb_build_array(jsonb_build_object('item_name', 'Prueba nueva', 'price_crc', 2000, 'qty', 2))));
select public.access_lock();
reset role;
-- the old window back on for the rest of the rehearsal (the way back of docs/ACTIVACION-DESCUENTOS.md §6)
\ir ../../supabase/tools/descuento-libre-encender.sql

-- 7) a guest orders from the room (works again after 0001)
-- (the guest's phone has the room code from the QR card and the menu from the public menu)
select code as room_code from public.rooms where active order by number limit 1 offset 2 \gset
select jsonb_agg(jsonb_build_object('id', id, 'qty', 1))::text as room_items from (select id from public.menu_items where price_crc > 0 and available order by name limit 1) m \gset
select set_config('request.jwt.claims', '{"role":"anon"}', false);
set role anon;
select public.place_room_order(:'room_code', 'Huésped Mañana', '88886666', 'es', '', :'room_items'::jsonb);
reset role;

-- 8) the owner receives, counts and throws away stock with the calls the OLD inventory page makes
select set_config('request.jwt.claims', '{"sub":"0e000000-0000-4000-8000-000000000002","role":"authenticated","aal":"aal2"}', false);
set role authenticated;
select public.stock_receive(p_item_id => '5e000000-0000-4000-8000-000000000001', p_qty => 1000, p_unit_cost => 1.5, p_expires_on => null, p_note => 'entrega');
select public.stock_count(p_item_id => '5e000000-0000-4000-8000-000000000002', p_counted => 1234, p_note => 'conteo');
select public.stock_waste(p_item_id => '5e000000-0000-4000-8000-000000000003', p_qty => 10, p_note => 'derramado');
reset role;

-- 9) the register is closed with the OLD page's call
select set_config('request.jwt.claims', '{"sub":"c0000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1"}', false);
set role authenticated;
select public.register_close(p_staff_id => 'a1000000-0000-4000-8000-000000000001', p_pin => '4826', p_terminal_crc => 0, p_cash_counted_crc => 60000, p_notes => 'cierre');
reset role;
select set_config('request.jwt.claims', '', false);

do $$
declare n int;
begin
  if (select count(*) from public.order_items where order_id = '0d000000-0000-4000-8000-0000000000c1') <> 1 then
    raise exception 'after: the offline sale queued before the window was not saved'; end if;
  if (select business_date from public.orders where id = '0d000000-0000-4000-8000-0000000000c1') <> public.cr_today() - 1 then
    raise exception 'after: the offline sale does not belong to the day it was taken'; end if;
  if (select voided_at from public.orders where id = '0d000000-0000-4000-8000-0000000000c2') is null then raise exception 'after: void on an old-page sale'; end if;
  if (select count(*) from public.order_items where order_id = '0d000000-0000-4000-8000-0000000000c3' and menu_item_id is not null) <> 1 then
    raise exception 'after: new-page sale'; end if;
  if not (select paid from public.orders where id = '0d000000-0000-4000-8000-0000000000b2') then raise exception 'after: open bill not closed'; end if;
  if exists (select 1 from public.time_entries where staff_id = 'a1000000-0000-4000-8000-000000000002' and clock_out is null) then
    raise exception 'after: Luis still clocked in'; end if;
  if not exists (select 1 from public.orders where source = 'room' and guest_name = 'Huésped Mañana') then raise exception 'after: room order'; end if;
  select count(*) into n from public.stock_moves where at > now() - interval '10 minutes' and kind in ('purchase', 'count', 'waste');
  if n < 3 then raise exception 'after: stock calls of the old inventory page (% moves)', n; end if;
  if (select closed_at from public.register_days where business_date = public.cr_today()) is null then raise exception 'after: register close'; end if;
  -- 0038: the old window's sale, the queued old-kind sale after the switch was turned off, the late category sale
  if (select discount_id::text || '|' || discount_crc || '|' || discount_reason from public.orders where id = '0d000000-0000-4000-8000-0000000000c4')
     is distinct from (select id::text || '|360|Regular customer' from public.discount_approvals
                        where order_id = '0d000000-0000-4000-8000-0000000000c4') then
    raise exception 'after: the old window''s discounted sale'; end if;
  if (select discount_crc || '|' || coalesce(discount_by, '-') from public.orders where id = '0d000000-0000-4000-8000-0000000000c5') <> '500|Ana' then
    raise exception 'after: the queued old-kind sale was not recorded as today with the switch off'; end if;
  if (select discount_reason || '|' || discount_by || '|' || ('discount_late' = any (flags))::text || '|' || (discount_id is not null)::text
        from public.orders where id = '0d000000-0000-4000-8000-0000000000c6') <> 'Local|Ana|true|true' then
    raise exception 'after: the late category sale is not linked and flagged discount_late: %',
      (select discount_reason || '|' || coalesce(discount_by, '-') || '|' || array_to_string(flags, ',') from public.orders where id = '0d000000-0000-4000-8000-0000000000c6'); end if;
  if (select category || '|' || approver_role || '|' || (order_id is not null)::text || '|' || (till_id is not null)::text
        from public.discount_approvals where order_id = '0d000000-0000-4000-8000-0000000000c6') <> 'local|manager|true|true' then
    raise exception 'after: the category approval'; end if;
  if (select count(*) from public.audit_log where action = 'setting_change' and target_id = 'pos_free_discount') <> 2 then
    raise exception 'after: the two switch changes are not logged'; end if;
  if public.setting('pos_free_discount') #>> '{}' <> 'on' then raise exception 'after: the switch is not back on'; end if;
  if exists (select 1 from public.access_unlocks where session_id = 'ensayo-caja-1') then
    raise exception 'after: the owner areas stayed open on the registered till'; end if;
  -- 0039/0040 (5b): every item with a supplier got its catalog row from the migration (new table only)
  if exists (select 1 from public.stock_items s where s.vendor_id is not null
              and not exists (select 1 from public.vendor_items v where v.vendor_id = s.vendor_id and v.item_id = s.id)) then
    raise exception 'after: 0039 left an item with a supplier without its catalog row'; end if;
  -- the payment ahead, registered in Proveedores, waits unapplied (nothing owed to that supplier yet)
  if (select v ->> 'ok' || '|' || (v ->> 'unapplied_crc')::numeric from ensayo_prov where k = 'adv') is distinct from 'true|50000.00' then
    raise exception 'after: the payment ahead in Proveedores: %', (select v from ensayo_prov where k = 'adv'); end if;
  -- the old page's direct order, received, invoiced and paid by bank in one call while that payment is unapplied
  if (select (v ->> 'ok') || '|' || (v ->> 'invoice_status') || '|' || (v ->> 'open_crc')::numeric || '|' || ((v ->> 'paid_crc')::numeric = (v ->> 'total_crc')::numeric)
        from ensayo_prov where k = 'old') is distinct from 'true|confirmed|0.00|true' then
    raise exception 'after: the old page''s receive-and-settle with a Proveedores payment unapplied: %', (select v from ensayo_prov where k = 'old'); end if;
  if public._prov_unapplied('5d390000-0000-4000-8000-0000000000a1') <> 50000 then
    raise exception 'after: the old page''s payment took the Proveedores payment: % unapplied', public._prov_unapplied('5d390000-0000-4000-8000-0000000000a1'); end if;
  if (select status || '|' || (po_number is not null) || '|' || (version > 0) from public.purchase_orders where id = '9a390000-0000-4000-8000-0000000000a1') <> 'received|true|true'
     or (select (vendor_item_id is null and pack_qty is null and ordered_unit_cost is null and pos is null and removed_at is null)::text || '|' || received_qty
           from public.purchase_lines where id = '9b390000-0000-4000-8000-0000000000a1')
        is distinct from 'true|' || (select qty from public.purchase_lines where id = '9b390000-0000-4000-8000-0000000000a1') then
    raise exception 'after: the old page''s order, as Proveedores keeps it'; end if;
  if (public._prov_dinero('9a390000-0000-4000-8000-0000000000a1') ->> 'status') <> 'paid' then
    raise exception 'after: Proveedores does not read the old page''s paid order as «Pagado»: %', public._prov_dinero('9a390000-0000-4000-8000-0000000000a1'); end if;
  -- the old page's drawer payout, documented by Proveedores' invoice: nothing open, «Pagado»
  if (select (v ->> 'ok') || '|' || (v ->> 'invoice_status') || '|' || ((select payout_id from public.purchase_receipts where id = '7e390000-0000-4000-8000-0000000000a2') is not null)
        from ensayo_prov where k = 'payout') is distinct from 'true|pending|true' then
    raise exception 'after: the old page''s drawer payout: %', (select v from ensayo_prov where k = 'payout'); end if;
  if (select (v ->> 'ok') || '|' || ((v ->> 'payout_crc')::numeric = (v ->> 'total_crc')::numeric) || '|' || (v ->> 'open_crc')::numeric from ensayo_prov where k = 'doc')
       is distinct from 'true|true|0.00'
     or (select count(*) from public.supplier_payments p join public.supplier_payment_allocations a on a.payment_id = p.id
          where a.invoice_id = 'f1390000-0000-4000-8000-0000000000a2' and p.paid_from = 'payout' and p.voided_at is null
            and p.payout_id = (select payout_id from public.purchase_receipts where id = '7e390000-0000-4000-8000-0000000000a2')) <> 1
     or (public._prov_dinero('9a390000-0000-4000-8000-0000000000a2') ->> 'status') <> 'paid' then
    raise exception 'after: the drawer payout documented by proveedor_factura_registrar: % · %', (select v from ensayo_prov where k = 'doc'),
      public._prov_dinero('9a390000-0000-4000-8000-0000000000a2'); end if;
  -- the new path: the catalog row, 2 boxes of 12 ordered = 24 units, received by Luis's work session: +24, no money shown to him
  if (select string_agg(v ->> 'ok', '|' order by k) from ensayo_prov where k in ('cat', 'po', 'turno', 'list', 'recv_doc', 'recv')) <> 'true|true|true|true|true|true' then
    raise exception 'after: the new page''s path: %', (select jsonb_object_agg(k, v) from ensayo_prov where k in ('cat', 'po', 'turno', 'list', 'recv_doc', 'recv')); end if;
  if (select string_agg(packs || ' × ' || pack_qty || ' = ' || qty || ' @ ' || ordered_unit_cost, ', ') from public.purchase_lines where po_id = '9a390000-0000-4000-8000-0000000000a3')
       is distinct from '2 × 12 = 24.0000 @ 750.000000' then
    raise exception 'after: the order of 2 boxes of 12: %', (select string_agg(packs || ' × ' || pack_qty || ' = ' || qty || ' @ ' || ordered_unit_cost, ', ')
                                                             from public.purchase_lines where po_id = '9a390000-0000-4000-8000-0000000000a3'); end if;
  if not exists (select 1 from ensayo_prov, jsonb_array_elements(v -> 'orders') o where k = 'list' and o ->> 'id' = '9a390000-0000-4000-8000-0000000000a3')
     or (select v ->> 'mode' || '|' || (v ? 'money') || '|' || (v -> 'order' ? 'note') from ensayo_prov where k = 'recv_doc') <> 'receive|false|false' then
    raise exception 'after: the person on shift does not see the order to receive, or sees money: % · %', (select v from ensayo_prov where k = 'list'),
      (select v from ensayo_prov where k = 'recv_doc'); end if;
  if (select v ->> 'status' || '|' || not (v ? 'total_crc') from ensayo_prov where k = 'recv') <> 'received|true'
     or (select v #>> '{}' from ensayo_prov where k = 'delta')::numeric <> 24 then
    raise exception 'after: received by the work session: % · stock %', (select v from ensayo_prov where k = 'recv'), (select v from ensayo_prov where k = 'delta'); end if;
  if (select r.by_name || '|' || (r.staff_id = 'a1000000-0000-4000-8000-000000000002') || '|' || (r.work_session_id = w.id) || '|' || r.total_crc || '|'
             || (select sum(m.qty) || '@' || min(m.unit_cost) from public.stock_moves m where m.receipt_id = r.id and m.kind = 'purchase')
        from public.purchase_receipts r join public.work_sessions w on w.staff_id = r.staff_id and w.session_id = 'ensayo-bodega-1'
       where r.id = '7e390000-0000-4000-8000-0000000000a3') is distinct from 'Luis (en turno)|true|true|18000.00|24.0000@750.000000' then
    raise exception 'after: the delivery as booked: %', (select to_jsonb(r) from public.purchase_receipts r where r.id = '7e390000-0000-4000-8000-0000000000a3'); end if;
  -- his clock-out (step 6) ended that session
  if (select string_agg(coalesce(ended_how, 'live'), ',') from public.work_sessions where session_id = 'ensayo-bodega-1') is distinct from 'clock_out' then
    raise exception 'after: Luis''s work session after his clock-out: %', (select string_agg(coalesce(ended_how, 'live'), ',') from public.work_sessions where session_id = 'ensayo-bodega-1'); end if;
  -- the invoice, then the SINPE payment of the order: applied at once, nothing open, «Pagado»
  if (select (v ->> 'ok') || '|' || (v ->> 'total_crc')::numeric || '|' || (v ->> 'open_crc')::numeric from ensayo_prov where k = 'inv') is distinct from 'true|20340.00|20340.00'
     or (select (v ->> 'ok') || '|' || (v ->> 'applied_crc')::numeric || '|' || (v #>> '{money,status}') from ensayo_prov where k = 'pay') is distinct from 'true|20340.00|paid'
     or public._invoice_open('f1390000-0000-4000-8000-0000000000a3') <> 0
     or (public._prov_dinero('9a390000-0000-4000-8000-0000000000a3') ->> 'status') <> 'paid' then
    raise exception 'after: the new path''s invoice and payment: % · %', (select v from ensayo_prov where k = 'inv'), (select v from ensayo_prov where k = 'pay'); end if;
  -- the books: every entry balanced, and 1160 «Anticipos a proveedores» holds exactly what is not applied yet
  if exists (select 1 from acct.lines group by entry_id having sum(debit) <> sum(credit)) or (select sum(debit) - sum(credit) from acct.lines) <> 0 then
    raise exception 'after: the ledger is not balanced'; end if;
  if (select coalesce(sum(l.debit - l.credit), 0) from acct.lines l where l.account = '1160')
     <> (select coalesce(sum(public._prov_unapplied(a.id)), 0) from public.supplier_advances a where a.voided_at is null) then
    raise exception 'after: 1160 holds % but the unapplied payments are %', (select coalesce(sum(l.debit - l.credit), 0) from acct.lines l where l.account = '1160'),
      (select coalesce(sum(public._prov_unapplied(a.id)), 0) from public.supplier_advances a where a.voided_at is null); end if;
  -- the sales made after the window are recorded in full, nothing is lost or invented
  if (select count(*) from public.orders where id in ('0d000000-0000-4000-8000-0000000000c1', '0d000000-0000-4000-8000-0000000000c2', '0d000000-0000-4000-8000-0000000000c3',
                                                     '0d000000-0000-4000-8000-0000000000c4', '0d000000-0000-4000-8000-0000000000c5', '0d000000-0000-4000-8000-0000000000c6')) <> 6 then
    raise exception 'after: a sale is missing'; end if;
  raise warning 'after the window: all checks passed';
end $$;
