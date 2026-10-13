-- Canopy OS rehearsal · a representative café history on the schema production has BEFORE migration 0000.
-- Fake data only (test logins and PINs from tests/db/90_seed.sql). Deterministic: the same rows every run.
--   * 120 days of sales (about 140 a day): cash ₡/$, card, SINPE, other; kitchen tickets; discounts approved by a
--     manager; voids with reason; bills paid in parts (with their part lines); room orders; register days
--     opened and closed; stock deliveries, counts, waste and recipe deductions; purchase orders; time clock
--   * today, through the real legacy functions as the café tablet does it: register opened, a sale, an open bill
--     paid in part, a manager void, a room order paid at the window, punches (one shift still open)
-- Used by tests/rehearsal/run.sh. Never run on a real Supabase project.
\set ON_ERROR_STOP on
select setseed(0.20261012);

-- logins and people -----------------------------------------------------------------------------------
insert into auth.users (id, email) values
  ('c0000000-0000-4000-8000-000000000001', 'cafe@test.local'),
  ('0e000000-0000-4000-8000-000000000002', 'owner@test.local');
insert into public.app_accounts (user_id, kind, label) values
  ('c0000000-0000-4000-8000-000000000001', 'cafe', 'cafe@test.local'),
  ('0e000000-0000-4000-8000-000000000002', 'owner', 'owner@test.local');
insert into public.staff (id, name, role, active, pin_hash, can_see_sales) values
  ('a1000000-0000-4000-8000-000000000001', 'Ana', 'manager', true, extensions.crypt('4826', extensions.gen_salt('bf')), true),
  ('a1000000-0000-4000-8000-000000000002', 'Luis', 'staff', true, extensions.crypt('5284', extensions.gen_salt('bf')), false),
  ('a1000000-0000-4000-8000-000000000003', 'Marta', 'staff', true, extensions.crypt('6173', extensions.gen_salt('bf')), false),
  ('a1000000-0000-4000-8000-000000000004', 'Dueño', 'owner', true, extensions.crypt('7391', extensions.gen_salt('bf')), false),
  ('a1000000-0000-4000-8000-000000000005', 'Sofía', 'staff', true, extensions.crypt('3917', extensions.gen_salt('bf')), false),
  ('a1000000-0000-4000-8000-000000000006', 'Diego', 'manager', true, extensions.crypt('8264', extensions.gen_salt('bf')), false),
  ('a1000000-0000-4000-8000-000000000007', 'Valeria', 'staff', false, extensions.crypt('5139', extensions.gen_salt('bf')), false);

-- suppliers, stock, recipes ---------------------------------------------------------------------------
insert into public.vendors (id, name, contact_name, phone, lead_days, order_days)
select ('5b000000-0000-4000-8000-00000000000' || g)::uuid, v, 'Contacto ' || g, '8800-00' || lpad(g::text, 2, '0'), 1 + g % 3, 'lunes, jueves'
  from unnest(array['Café de Altura', 'Lácteos Monteverde', 'Panadería La Esquina', 'Verduras Santa Elena', 'Distribuidora Central'])
       with ordinality as t(v, g);
insert into public.stock_items (id, name, category, unit, pack_label, pack_qty, cost_per_pack, vendor_id, par_level, reorder_point, shelf_life_days)
select ('5e000000-0000-4000-8000-' || lpad(g::text, 12, '0'))::uuid,
       'Insumo ' || g, (array['coffee', 'dairy', 'bakery', 'produce', 'dry'])[1 + g % 5], (array['g', 'ml', 'unit', 'g', 'g'])[1 + g % 5],
       'paquete', (array[1000, 1000, 12, 500, 2000])[1 + g % 5], 1500 + (g * 377) % 9000,
       ('5b000000-0000-4000-8000-00000000000' || (1 + g % 5))::uuid, 50 + g * 7, 20 + g * 3, case when g % 5 in (1, 3) then 7 end
  from generate_series(1, 30) g;
insert into public.recipes (menu_item_id, stock_item_id, qty)
select m.id, ('5e000000-0000-4000-8000-' || lpad((1 + (abs(hashtext(m.name || k)) % 30))::text, 12, '0'))::uuid, 5 + (abs(hashtext(m.name || k)) % 60)
  from public.menu_items m cross join generate_series(1, 2) k
 where abs(hashtext(m.name)) % 4 <> 0
on conflict do nothing;
-- opening stock and a delivery every week per item
insert into public.stock_moves (item_id, at, kind, qty, unit_cost, note, by_name)
select s.id, public.cr_day_start(public.cr_today() - 121) + interval '7 hours', 'count', 4000, s.cost_per_pack / s.pack_qty, 'conteo inicial', 'Ana'
  from public.stock_items s;
insert into public.stock_moves (item_id, at, kind, qty, unit_cost, note, by_name)
select s.id, public.cr_day_start(public.cr_today() - d) + interval '9 hours', 'purchase', s.pack_qty * (3 + (d % 4)),
       round((s.cost_per_pack / s.pack_qty) * (1 + (d % 9) / 100.0), 4), 'entrega semanal', 'Diego'
  from public.stock_items s cross join generate_series(1, 120) d where d % 7 = 0;

-- 120 days of sales -----------------------------------------------------------------------------------
create temporary table seed_orders as
select gen_random_uuid() as id, d, n,
       public.cr_day_start(public.cr_today() - d) + interval '7 hours' + (random() * interval '10 hours') as at,
       random() as r_pay, random() as r_kind, random() as r_items
  from generate_series(1, 120) d cross join lateral generate_series(1, 110 + (random() * 60)::int) n;
create temporary table seed_lines as
select o.id as order_id, gen_random_uuid() as id, m.name as item_name, m.price_crc, 1 + (random() < 0.2)::int as qty, o.at
  from seed_orders o
  cross join lateral (select name, price_crc from public.menu_items where price_crc > 0 and o.r_items >= 0
                       order by random() limit 1 + (o.r_items * 3.4)::int) m;

-- discounts: a manager approved them a minute before the sale (as approve_discount records it)
create temporary table seed_disc as
select o.id as order_id, gen_random_uuid() as approval, o.at,
       (select sum(price_crc * qty) from seed_lines l where l.order_id = o.id)::int as subtotal
  from seed_orders o where o.r_kind < 0.03;
insert into public.discount_approvals (id, created_at, approved_by, approved_name, kind, value, reason, station, subtotal_crc, base_crc)
select approval, at - interval '1 minute', 'a1000000-0000-4000-8000-000000000001', 'Ana', 'percent', 10, 'cliente frecuente', 'Caja', subtotal, subtotal
  from seed_disc;

insert into public.orders (id, created_at, total_crc, subtotal_crc, discount_crc, discount_id, payment_method, source, status, needs_kitchen,
                           pickup_number, paid, station, accepted_at, ready_at, done_at)
select o.id, o.at,
       t.sub - coalesce(round(t.sub * 0.10)::int, 0) * (sd.order_id is not null)::int,
       case when sd.order_id is not null then t.sub end,
       case when sd.order_id is not null then round(t.sub * 0.10)::int else 0 end,
       sd.approval,
       case when o.r_pay < 0.40 then 'cash_crc' when o.r_pay < 0.80 then 'card' when o.r_pay < 0.92 then 'sinpe'
            when o.r_pay < 0.97 then 'cash_usd' else 'other' end,
       'front', 'done', o.r_kind > 0.4, case when o.r_kind > 0.4 then 1 + o.n % 99 end, true,
       case when o.n % 4 = 0 then 'iPad' else 'Caja' end,
       case when o.r_kind > 0.4 then o.at + interval '1 minute' end,
       case when o.r_kind > 0.4 then o.at + interval '9 minutes' end,
       case when o.r_kind > 0.4 then o.at + interval '12 minutes' end
  from seed_orders o
  join (select order_id, sum(price_crc * qty)::int as sub from seed_lines group by order_id) t on t.order_id = o.id
  left join seed_disc sd on sd.order_id = o.id;
insert into public.order_items (id, order_id, item_name, qty, price_crc, added_at)
select id, order_id, item_name, qty, price_crc, at from seed_lines;

-- bills paid in two parts by item (the way tab_pay leaves them): one part on the bill, the rest on the bill itself
create temporary table seed_tabs as
select o.id, o.at, (array_agg(l.id order by l.id))[1] as first_line
  from seed_orders o join seed_lines l on l.order_id = o.id
 where o.r_kind between 0.03 and 0.05 and not exists (select 1 from seed_disc d where d.order_id = o.id)
 group by o.id, o.at having count(*) >= 2;
create temporary table seed_parts as
select t.id as bill, gen_random_uuid() as part, t.at, i.id as line, i.qty, (i.price_crc * i.qty)::int as amt
  from seed_tabs t join public.order_items i on i.id = t.first_line;
insert into public.orders (id, created_at, total_crc, payment_method, paid, status, done_at, source, needs_kitchen, station, part_of, notes)
select part, at + interval '40 minutes', amt, 'sinpe', true, 'done', at + interval '40 minutes', 'front', false, 'Caja', bill, 'Part of mesa: 1× pago parcial'
  from seed_parts;
insert into public.order_part_lines (part_id, item_id, qty) select part, line, qty from seed_parts;
update public.order_items i set paid_qty = i.qty from seed_parts p where p.line = i.id;
update public.order_items i set paid_qty = i.qty from seed_tabs t where i.order_id = t.id;
update public.orders o set total_crc = o.total_crc - p.amt, parts_crc = p.amt, parts_items_crc = p.amt, payment_method = 'card'
  from seed_parts p where p.bill = o.id;

-- room orders paid at the window
update public.orders o set source = 'room', room_id = (select id from public.rooms order by number limit 1 offset (s.n % 5)),
       guest_name = 'Huésped ' || s.n, guest_lang = 'en', track_token = md5(o.id::text), needs_kitchen = true, pickup_number = 1 + s.n % 99,
       accepted_at = o.created_at + interval '2 minutes', ready_at = o.created_at + interval '15 minutes', done_at = o.created_at + interval '25 minutes'
  from seed_orders s where s.id = o.id and s.r_kind between 0.05 and 0.07 and o.part_of is null and o.parts_crc = 0;

-- voids by a manager with a reason (the audit trail the legacy function writes)
update public.orders o set voided_at = o.created_at + interval '6 minutes', voided_by = 'a1000000-0000-4000-8000-000000000001',
       void_reason = 'cobrado dos veces'
  from seed_orders s where s.id = o.id and s.r_kind between 0.07 and 0.085 and o.part_of is null and o.parts_crc = 0;
insert into public.audit_log (at, action, manager_id, manager_name, target_id, summary, details)
select voided_at, 'order_void', voided_by, 'Ana', id::text, void_reason,
       jsonb_build_object('total_crc', total_crc, 'payment_method', payment_method, 'created_at', created_at)
  from public.orders where voided_at is not null;

-- bills left open past closing and paid the next day: the legacy tab_pay moved them to the payment day, their
-- lines keep the time they were rung (migration 0003 recovers it)
update public.orders o set created_at = o.created_at + interval '1 day', payment_method = 'cash_crc'
  from seed_orders s where s.id = o.id and s.r_kind between 0.085 and 0.09 and s.d > 1 and o.part_of is null and o.parts_crc = 0
   and o.voided_at is null and o.discount_crc = 0 and o.source = 'front';

-- orders.note: production's free-text column from before the repository (tests/db/01_base_tables.sql), empty there
-- today; here three orders carry what someone could type in it, a name and a phone, so the staging copy proves it
-- never takes them along
update public.orders o set note = x.note
  from (select s.id, (array['Rosa Méndez, tel. 8800-1201, recoge a las 3', 'para Tom Becker · +1 555 0142',
                            'llamar a Carlos Vargas 8800-1203'])[t.k] as note
          from unnest(array[2, 30, 90]) with ordinality as t(d, k) join seed_orders s on s.d = t.d and s.n = 1) x
 where x.id = o.id;

-- counts and waste
insert into public.stock_moves (item_id, at, kind, qty, note, by_name)
select s.id, public.cr_day_start(public.cr_today() - d) + interval '18 hours', 'waste', -(s.pack_qty * 0.05), 'vencido', 'Luis'
  from public.stock_items s cross join generate_series(3, 120, 15) d where s.shelf_life_days is not null;
insert into public.stock_moves (item_id, at, kind, qty, note, by_name)
select s.id, public.cr_day_start(public.cr_today() - d) + interval '18 hours 30 minutes', 'count', round((random() * 40 - 20)::numeric, 2), 'conteo mensual', 'Ana'
  from public.stock_items s cross join generate_series(10, 120, 30) d;

-- purchase orders, received
insert into public.purchase_orders (id, vendor_id, status, created_at, sent_at, received_at, note, by_name)
select gen_random_uuid(), v.id, 'received', public.cr_day_start(public.cr_today() - d) + interval '8 hours',
       public.cr_day_start(public.cr_today() - d) + interval '8 hours 10 minutes', public.cr_day_start(public.cr_today() - d + 2) + interval '9 hours',
       'pedido semanal', 'Diego'
  from public.vendors v cross join generate_series(9, 120, 7) d;
insert into public.purchase_lines (po_id, item_id, packs, qty, received_qty, unit_cost)
select p.id, s.id, 3, s.pack_qty * 3, s.pack_qty * 3, s.cost_per_pack / s.pack_qty
  from public.purchase_orders p join public.stock_items s on s.vendor_id = p.vendor_id;
insert into public.purchase_orders (vendor_id, status, note, by_name)
select id, 'draft', 'borrador', 'Diego' from public.vendors limit 2;

-- register days, closed with the figures the legacy close records
insert into public.register_days (business_date, opened_at, opened_by, opened_by_name, float_crc, closed_at, closed_by, closed_by_name,
                                  orders_count, sales_cash_crc, sales_cash_usd_crc, sales_card_crc, sales_sinpe_crc, sales_other_crc,
                                  sales_total_crc, terminal_crc, cash_counted_crc, expected_cash_crc, cash_diff_crc, card_diff_crc)
select d.day, public.cr_day_start(d.day) + interval '6 hours 30 minutes', 'a1000000-0000-4000-8000-000000000001', 'Ana', 50000,
       public.cr_day_start(d.day) + interval '17 hours 40 minutes', 'a1000000-0000-4000-8000-000000000006', 'Diego',
       s.n, s.cash, s.usd, s.card, s.sinpe, s.other, s.total, s.card + (case when d.i % 11 = 0 then -500 else 0 end),
       50000 + s.cash + s.usd + (case when d.i % 6 = 0 then -1000 else 0 end), 50000 + s.cash + s.usd,
       (case when d.i % 6 = 0 then -1000 else 0 end), (case when d.i % 11 = 0 then -500 else 0 end)
  from (select public.cr_today() - g as day, g as i from generate_series(1, 120) g) d
  cross join lateral (
    select count(*)::int as n,
           coalesce(sum(total_crc) filter (where payment_method = 'cash_crc'), 0)::int as cash,
           coalesce(sum(total_crc) filter (where payment_method = 'cash_usd'), 0)::int as usd,
           coalesce(sum(total_crc) filter (where payment_method = 'card'), 0)::int as card,
           coalesce(sum(total_crc) filter (where payment_method = 'sinpe'), 0)::int as sinpe,
           coalesce(sum(total_crc) filter (where payment_method = 'other'), 0)::int as other,
           coalesce(sum(total_crc), 0)::int as total
      from public.orders o
     where o.voided_at is null and o.paid and o.created_at >= public.cr_day_start(d.day) and o.created_at < public.cr_day_start(d.day + 1)) s;

-- shifts: four people a day
insert into public.time_entries (staff_id, clock_in, clock_out)
select ('a1000000-0000-4000-8000-00000000000' || (1 + (d + k) % 6))::uuid,
       public.cr_day_start(public.cr_today() - d) + interval '6 hours' + k * interval '1 hour',
       public.cr_day_start(public.cr_today() - d) + interval '14 hours' + k * interval '1 hour' + (d % 3) * interval '20 minutes'
  from generate_series(1, 120) d cross join generate_series(0, 3) k;

insert into public.chat_questions (message, lang, answered) select '¿A qué hora abren? ' || g, 'es', g % 2 = 0 from generate_series(1, 15) g;

-- today, through the legacy functions as the café tablet uses them --------------------------------------
select set_config('request.jwt.claims', '{"sub":"c0000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1"}', false);
set role authenticated;
select public.register_open('a1000000-0000-4000-8000-000000000001', '4826', 50000);
select public.clock_punch('a1000000-0000-4000-8000-000000000002', '5284');
select public.clock_punch('a1000000-0000-4000-8000-000000000003', '6173');
select public.clock_punch('a1000000-0000-4000-8000-000000000003', '6173');
-- a sale rung the way the POS saves it (order, then its lines)
insert into public.orders (id, total_crc, payment_method, station, source, status)
  values ('0d000000-0000-4000-8000-0000000000b1', 4400, 'cash_crc', 'Caja', 'front', 'done');
insert into public.order_items (order_id, item_name, qty, price_crc)
  select '0d000000-0000-4000-8000-0000000000b1', name, 1, 2200 from public.menu_items where price_crc > 0 order by name limit 2;
-- an open bill, one person pays their item
insert into public.orders (id, total_crc, payment_method, station, source, status, paid, guest_name, needs_kitchen, pickup_number)
  values ('0d000000-0000-4000-8000-0000000000b2', 0, 'pending', 'Caja', 'front', 'new', false, 'Mesa 4', true, 7);
select public.tab_add_items('0d000000-0000-4000-8000-0000000000b2',
  (select jsonb_agg(jsonb_build_object('menu_item_id', id, 'qty', 1)) from (select id from public.menu_items where price_crc > 0 order by name limit 3) m));
select public.tab_pay('0d000000-0000-4000-8000-0000000000b2', 'card',
  (select jsonb_build_array(jsonb_build_object('item_id', id, 'qty', 1)) from public.order_items where order_id = '0d000000-0000-4000-8000-0000000000b2' order by item_name limit 1),
  null, 'Caja');
-- a sale voided by a manager
insert into public.orders (id, total_crc, payment_method, station, source, status) values ('0d000000-0000-4000-8000-0000000000b3', 1800, 'card', 'iPad', 'front', 'done');
insert into public.order_items (order_id, item_name, qty, price_crc) values ('0d000000-0000-4000-8000-0000000000b3', 'Prueba anulada', 1, 1800);
select public.manager_void_order('a1000000-0000-4000-8000-000000000001', '4826', '0d000000-0000-4000-8000-0000000000b3', 'cliente se arrepintió');
reset role;
-- a guest's room order (placed from the phone; the legacy place_room_order cannot find gen_random_bytes, which
-- migration 0001 fixes, so it is written here the way that function writes it), paid at the window by the café
insert into public.orders (id, total_crc, payment_method, source, status, needs_kitchen, paid, room_id, guest_name, guest_phone, guest_lang, notes, track_token)
  values ('0d000000-0000-4000-8000-0000000000b4', 3600, 'pending', 'room', 'ready', true, false, (select id from public.rooms order by number limit 1),
          'Huésped Hoy', '88887777', 'en', 'sin azúcar', md5('room-today'));
insert into public.order_items (order_id, item_name, qty, price_crc) values ('0d000000-0000-4000-8000-0000000000b4', 'Café de la casa', 2, 1800);
select set_config('request.jwt.claims', '{"sub":"c0000000-0000-4000-8000-000000000001","role":"authenticated","aal":"aal1"}', false);
set role authenticated;
select public.finish_room_order('0d000000-0000-4000-8000-0000000000b4', 'cash_crc');
reset role;
select set_config('request.jwt.claims', '', false);
-- today's activity really went through (the legacy functions answer ok:false instead of failing)
do $$ begin
  if not exists (select 1 from public.register_days where business_date = public.cr_today() and closed_at is null) then raise exception 'seed: register not opened'; end if;
  if (select count(*) from public.orders where part_of = '0d000000-0000-4000-8000-0000000000b2') <> 1 then raise exception 'seed: open bill not paid in part'; end if;
  if (select voided_at from public.orders where id = '0d000000-0000-4000-8000-0000000000b3') is null then raise exception 'seed: void failed'; end if;
  if not (select paid from public.orders where id = '0d000000-0000-4000-8000-0000000000b4') then raise exception 'seed: room order not paid'; end if;
  if (select count(*) from public.time_entries where clock_in >= public.cr_today_start()) <> 2 then raise exception 'seed: punches missing'; end if;
  if (select count(nullif(btrim(note), '')) from public.orders) <> 3 then raise exception 'seed: order notes missing'; end if;
end $$;
analyze;
