-- Migration ledger and the 0001 security fixes.
begin;

-- ledger ------------------------------------------------------------------------------------------
select test.ok(public.canopy_schema_version() >= 1, 'schema version is reported');
select test.throws($$select canopy.migration_begin(0, 'canopy_ledger')$$, 'ya estaba aplicada', 'a migration refuses to run twice');
select test.throws($$select canopy.migration_begin(public.canopy_schema_version() + 2, 'skips one')$$, 'Falta aplicar antes',
                   'a migration refuses to run out of order');
select test.login('anon'); set role anon;
select test.ok(public.canopy_schema_version() >= 1, 'anonymous pages can read the schema version');
select test.throws($$select * from canopy.migrations$$, 'permission denied', 'the ledger itself is not readable from the API');
reset role;

-- legacy scripts refuse to run once the ledger exists
select test.throws($t$do $g$ begin if to_regclass('canopy.migrations') is not null then raise exception 'Archivo histórico'; end if; end $g$$t$,
                   'Archivo histórico', 'the legacy guard fires when the ledger exists');

-- room orders: a stranger's login cannot touch them ------------------------------------------------
insert into public.orders (id, total_crc, payment_method, source, status, paid, room_id, guest_name, guest_phone)
  values ('0d000000-0000-4000-8000-0000000000aa', 2000, 'pending', 'room', 'new', false, (select id from public.rooms limit 1), 'Guest', '88887777');
select test.login('99999999-0000-4000-8000-00000000abcd'); set role authenticated;
select test.eq(public.cancel_room_order('0d000000-0000-4000-8000-0000000000aa')->>'error', 'no_account',
               'a login that is not the café cannot cancel a room order');
select test.eq(public.finish_room_order('0d000000-0000-4000-8000-0000000000aa', 'cash_crc')->>'error', 'no_account',
               'a login that is not the café cannot mark a room order paid');
select test.eq((select count(*)::int from public.quick_items(30, 12)), 0, 'a stranger reads no sales from quick_items');
reset role;
select test.eq((select status from public.orders where id = '0d000000-0000-4000-8000-0000000000aa'), 'new', 'the room order is untouched');
select test.login('99999999-0000-4000-8000-00000000abcd'); set role authenticated;
select test.eq(public.room_new_code((select id from public.rooms limit 1))->>'error', 'not_owner',
               'a stranger cannot change a room QR code');
-- menu categories, PINs (0001, amended before it reached production)
update public.menu_categories set name = 'hacked', kitchen = not kitchen, color = '#000000';
select test.eq(public.clock_punch(test.staff('luis'), '5284')->>'error', 'no_account', 'a stranger cannot punch the clock with a PIN');
select test.eq(public.clock_punch(test.staff('luis'), '0000')->>'error', 'no_account', 'nor guess PINs');
select test.eq(public.manager_void_order(test.staff('ana'), '4826', '0d000000-0000-4000-8000-0000000000aa', 'x')->>'error', 'no_account',
               'nor void an order with a manager PIN');
reset role;
select test.eq((select count(*)::int from public.menu_categories where name = 'hacked' or color = '#000000'), 0,
               'a stranger cannot rename or recolor the menu categories');
select test.eq((select failed_pins from public.staff where id = test.staff('luis')), 0, 'no PIN was tried, nobody is locked out');
select test.eq((select count(*)::int from public.time_entries where staff_id = test.staff('luis')), 0, 'no punch was recorded');
-- the owner areas still edit categories (Menu Manager), with the owner login or a manager PIN on the tablet
select test.login('owner', 'aal2'); set role authenticated;
update public.menu_categories set color = '#3B6EA8' where sort = (select min(sort) from public.menu_categories);
reset role;
select test.eq((select count(*)::int from public.menu_categories where color = '#3B6EA8'), 1, 'the owner recolors a category');
select test.login('cafe'); set role authenticated;
update public.menu_categories set color = '#111111';
reset role;
select test.eq((select count(*)::int from public.menu_categories where color = '#111111'), 0, 'the café login alone does not edit the menu');
select test.login('cafe', 'aal1', test.unlock(test.staff('ana'), '4826')); set role authenticated;
update public.menu_categories set color = '#A07629' where sort = (select min(sort) from public.menu_categories);
reset role;
select test.eq((select count(*)::int from public.menu_categories where color = '#A07629'), 1, 'a manager PIN on the tablet opens Menu Manager edits');

-- the café tablet still can
select test.login('cafe'); set role authenticated;
select test.eq(public.room_new_code((select id from public.rooms limit 1))->>'error', 'not_owner',
               'the café tablet cannot change room QR codes (owner only)');
select test.eq(public.finish_room_order('0d000000-0000-4000-8000-0000000000aa', 'card')->>'ok', 'true',
               'the café tablet records the room payment');
select test.eq(public.finish_room_order('0d000000-0000-4000-8000-0000000000aa', 'card')->>'error', 'not_room_order',
               'a room order cannot be paid twice');
reset role;
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.room_new_code((select id from public.rooms limit 1))->>'ok', 'true', 'the owner (with phone code) can change a room QR code');
reset role;

-- guests can order from their room again (gen_random_bytes is found) ------------------------------
update public.app_settings set room_open = '00:00', room_close = '23:59', room_orders_enabled = true where id = 1;
select code as rcode from public.rooms where active order by number offset 1 limit 1 \gset
select test.login('anon'); set role anon;
select test.eq(public.place_room_order(:'rcode', 'Ana Turista', '+506 8888 7777', 'es', null,
         jsonb_build_array(jsonb_build_object('id', (select id from public.menu_items where available and price_crc > 0 order by name limit 1), 'qty', 2)))->>'ok',
               'true', 'a guest places a room order from the public page');
reset role;

select test.done();
rollback;
