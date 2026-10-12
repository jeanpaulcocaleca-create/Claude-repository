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
-- 6) Luis clocks out (his shift began before the window)
select public.clock_punch('a1000000-0000-4000-8000-000000000002', '5284');
reset role;

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
  -- the sales made after the window are recorded in full, nothing is lost or invented
  if (select count(*) from public.orders where id in ('0d000000-0000-4000-8000-0000000000c1', '0d000000-0000-4000-8000-0000000000c2', '0d000000-0000-4000-8000-0000000000c3')) <> 3 then
    raise exception 'after: a sale is missing'; end if;
  raise warning 'after the window: all checks passed';
end $$;
