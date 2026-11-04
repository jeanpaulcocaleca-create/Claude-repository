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
  -- the sales made after the window are recorded in full, nothing is lost or invented
  if (select count(*) from public.orders where id in ('0d000000-0000-4000-8000-0000000000c1', '0d000000-0000-4000-8000-0000000000c2', '0d000000-0000-4000-8000-0000000000c3',
                                                     '0d000000-0000-4000-8000-0000000000c4', '0d000000-0000-4000-8000-0000000000c5', '0d000000-0000-4000-8000-0000000000c6')) <> 6 then
    raise exception 'after: a sale is missing'; end if;
  raise warning 'after the window: all checks passed';
end $$;
