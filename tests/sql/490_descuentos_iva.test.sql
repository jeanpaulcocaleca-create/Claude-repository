-- Migration 0038 (D-065): the IVA and the books of the four discounts (proposal §2.10, §2.6c and §5.1 «490»; the
-- owner's adjustment 4 and build plan L2 for Guía Turista, which ships off and which this test turns on locally through
-- the owner's own functions; api-0038 §4.2 and §5). No tax rule is activated (A-13): the 100 % courtesy is a sale at
-- ₡0 that keeps its list value in the lines, the subtotal and the discount. _order_tax gives each line its whole amount
-- as discount, so IVA 0 and net 0; the register adds ₡0 and one order; the books post revenue 0, IVA 0, advances 0 and
-- the cost of goods; the IVA reports count its lines at 0 and never in the untaxed bucket; a shadow e-document is at 0;
-- a same-day void gives the stock back and, after the close, a void says closed_day and a refund is_refund (today's rule
-- for ₡0 sales). On a bill the courtesy takes the whole bill to ₡0 and closes with tab_pay('other', null, null). A sale
-- whose discount could not be verified keeps its real discount, so the books post revenue = the money received and
-- nothing as an advance (no phantom IVA from the page's discount-less fallback). The IVA split of Empleado 30 % and
-- Local 10 % is the one the page prints (pos.html ivaGroups, transcribed below). And 0038 touches no tax, books or
-- e-invoice rule. Everything goes through the real functions as the café login (authenticated, with a session_id) on
-- a registered till; the readers run as the accountant or the owner where the page does.
begin;

-- 0) 0038 leaves every tax, books and e-invoice rule as it was (proposal §2.10 «0038 does not touch …») ----------------
select test.eq((select string_agg(code || ':' || rate, ',' order by code) from public.tax_rates), 'IVA13:0.1300',
               '0 tax_rates: still only the general 13 % (0038 adds no rate)');
select test.eq((select count(*)::int from public.menu_items where tax_code is distinct from 'IVA13'), 0,
               '0 menu_items.tax_code: every product keeps the general rate');
select test.eq((select kind || ' ' || choices::text || ' ' || default_value::text || ' ' || guard from canopy.setting_defs where key = 'price_mode'),
               'choice {inclusive,exclusive} "inclusive" price_display_rules', '0 price_mode: as 0009 left it (inclusive, locked by its confirmation)');
select test.eq((select kind || ' ' || choices::text || ' ' || default_value::text || ' ' || coalesce(guard, '-') from canopy.setting_defs where key = 'einvoice_mode'),
               'choice {off,shadow} "off" -', '0 einvoice_mode: as 0018 left it (off by default)');
select test.eq((select kind || ' ' || default_value::text || ' ' || guard from canopy.setting_defs where key = 'ledger_auto_post'),
               'boolean false chart_of_accounts_approved', '0 ledger_auto_post: as 0013 left it');
select test.eq((select count(*)::int from public.settings where key in ('price_mode', 'einvoice_mode', 'ledger_auto_post')), 0,
               '0 and 0038 stores no value for any of them');
select test.eq((select count(*)::int from public.compliance_confirmations), 0,
               '0 no compliance confirmation is recorded (courtesy_iva_confirmed, A-13, stays open)');
select test.eq((select count(*)::int from public.e_documents), 0, '0 no e-document exists');
-- the bodies of the tax, books, register, correction and e-invoice functions the courtesy goes through are the ones the
-- release snapshot knows from before 0038 (supabase/tools/production-snapshot.sql, known functions: 12 characters of
-- md5(prosrc)); 0038's header: «Qué NO cambia: … los impuestos, las tarifas, la contabilidad, ninguna otra función».
-- A later migration that changes one of them updates its row here, as it adds its version to the snapshot
select test.eq(left(md5(p.prosrc), 12), k.h, '0 ' || k.fn || ' keeps its body of ' || k.ver || ' (0038 does not touch it)')
  from (values ('public._order_tax(p_orders uuid[])', '8fc315d9a46c', '0009'),
               ('public._order_items_tax()', '4cc213922597', '0009'),
               ('public._order_tax_discount()', '0498a9d4ab2e', '0009'),
               ('public._order_item_tax_stamp()', '988362164190', '0009'),
               ('public._order_refund_tax()', '1d1038b8704a', '0009'),
               ('public.tax_rate_save(p_code text, p_name text, p_rate numeric, p_confirmed_by text, p_reference text, p_active boolean)', '95555a12f341', '0025'),
               ('public.tax_summary(p_from date, p_to date)', '0bca6590efc0', '0025'),
               ('public.iva_report(p_from date, p_to date)', '50afb4cf7e98', '0017'),
               ('acct.day_target(p_day date)', '1430e75384e4', '0019'),
               ('acct.post_day(p_day date, p_by text)', '26fd47c0a075', '0013'),
               ('acct._register_closed_post()', '236f3d6fea7c', '0013'),
               ('public._order_e_document()', 'e92a160abfca', '0018'),
               ('public._order_e_document_sync()', 'abdd67cb9717', '0028'),
               ('public._e_missing(p_order_id uuid)', '443a89d0839f', '0018'),
               ('public.einvoice_list(p_from date, p_to date)', 'f1efde698157', '0025'),
               ('public.einvoice_request_fe(p_order_id uuid, p_receiver jsonb)', 'e3c47f09397e', '0025'),
               ('public._register_expected(p_day date, OUT cash_crc bigint, OUT usd numeric)', 'b1bbb8b50341', '0019'),
               ('public.register_expected()', 'b517399a3492', '0010'),
               ('public.register_close(p_staff_id uuid, p_pin text, p_terminal_crc integer, p_cash_counted_crc integer, p_notes text, p_cash_counted_usd numeric)', '0b9c68794107', '0010'),
               ('public.pos_record_sale(p_order jsonb)', '7dbf0a726a66', '0031'),
               ('public._order_check_totals(p_orders uuid[])', 'edc7f03e754a', '0004'),
               ('public._order_receipt_no()', '7c9760b35285', '0011'),
               ('public.order_search(p_from date, p_to date, p_text text, p_receipt bigint, p_amount integer, p_method text, p_limit integer)', '68f26a140abb', '0025'),
               ('public.tab_pay(p_order_id uuid, p_method text, p_lines jsonb, p_amount integer, p_station text, p_expect integer)', '4226b23a71f8', '0027'),
               ('public._tab_discount(o orders, p_sub integer, p_used integer, p_open integer)', '37cd9f56070b', 'legacy'),
               ('public.manager_void_order(p_manager_id uuid, p_manager_pin text, p_order_id uuid, p_reason text)', '8360c271e724', '0006'),
               ('public.manager_refund_order(p_manager_id uuid, p_manager_pin text, p_order_id uuid, p_reason text, p_restock boolean, p_method text, p_station text)', '9b0eae3b2485', '0006'),
               ('public._order_stock_return()', '71225b9f3b63', '0005'),
               ('public._order_item_stock()', 'db8a2dc248ff', '0031')) k(fn, h, ver)
  left join (select n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' as fn, p.prosrc
               from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('public', 'acct')) p on p.fn = k.fn
 order by k.fn;
select test.eq((select string_agg(c.relname || '.' || t.tgname || '=' || p.proname || ':' || t.tgenabled::text, ' ' order by c.relname, t.tgname)
                  from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_proc p on p.oid = t.tgfoid
                 where not t.tgisinternal and t.tgname in ('order_items_tax_ins', 'order_items_tax_upd', 'order_items_tax_del', 'order_item_tax_stamp',
                         'order_items_totals', 'order_tax_discount', 'order_refund_tax', 'order_e_document', 'order_e_document_sync',
                         'order_stock_return', 'register_closed_post')),
               'order_items.order_item_tax_stamp=_order_item_tax_stamp:O order_items.order_items_tax_del=_order_items_tax:O '
               || 'order_items.order_items_tax_ins=_order_items_tax:O order_items.order_items_tax_upd=_order_items_tax:O '
               || 'order_items.order_items_totals=_order_items_totals:O orders.order_e_document=_order_e_document:O '
               || 'orders.order_e_document_sync=_order_e_document_sync:O orders.order_refund_tax=_order_refund_tax:O '
               || 'orders.order_stock_return=_order_stock_return:O orders.order_tax_discount=_order_tax_discount:O '
               || 'register_days.register_closed_post=_register_closed_post:O',
               '0 the tax, totals, stock-return, e-document and posting triggers are all in place, enabled, on their functions');

-- fixtures ------------------------------------------------------------------------------------------------------------
-- the owner (with the phone code) records the accountant's confirmation and turns Guía Turista on; sets the e-documents
-- to shadow and the automatic posting on (A-07: it is on in production) — all for this test only, rolled back
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.setting_set('pos_discount_guia', '"on"') ->> 'error', 'needs_confirmation',
               'fixture: Guía Turista cannot be turned on before the confirmation (L2)');
select test.eq(public.compliance_confirm('courtesy_iva_confirmed', 'Contador de prueba 490', 'Prueba local 490') ->> 'ok', 'true',
               'fixture: the owner records the accountant''s confirmation (test only)');
select test.eq(public.setting_set('pos_discount_guia', '"on"') ->> 'ok', 'true', 'fixture: then turns Guía Turista on');
select test.eq(public.setting_set('einvoice_mode', '"shadow"') ->> 'ok', 'true', 'fixture: e-documents in shadow mode (test only)');
select test.eq(public.compliance_confirm('chart_of_accounts_approved', 'Contador de prueba 490', 'Prueba local 490') ->> 'ok', 'true',
               'fixture: the chart of accounts approved (test only)');
select test.eq(public.setting_set('ledger_auto_post', 'true') ->> 'ok', 'true', 'fixture: automatic posting on, as in production (A-07)');
-- a second IVA rate, so every courtesy and split below has two rates: Tea and a test cookie at 4 %
select test.eq(public.tax_rate_save('T490', 'Tarifa de prueba 490 · 4 %', 0.04, 'Contador de prueba 490', 'Prueba local 490') ->> 'ok', 'true',
               'fixture: a second rate T490 at 4 % (test only)');
update public.menu_items set tax_code = 'T490' where name = 'Tea';
insert into public.menu_items (category_id, name, price_crc, tax_code)
  select category_id, 'Galleta 490', 1257, 'T490' from public.menu_items where name = 'Tea' limit 1;
reset role;
-- what goes out of stock: Latte 200 ml of milk (₡1 the ml), Tea one bag (₡60), the cookie 50 g of flour (₡2 the g);
-- bought three days ago, so today's stock moves are the sales' alone
insert into public.stock_items (id, name, unit, pack_qty, cost_per_pack) values
  ('5a490000-0000-4000-8000-000000000001', 'Leche 490', 'ml', 1000, 1000),
  ('5a490000-0000-4000-8000-000000000002', 'Té 490', 'unit', 1, 60),
  ('5a490000-0000-4000-8000-000000000003', 'Harina 490', 'g', 1000, 2000);
insert into public.stock_moves (item_id, kind, qty, unit_cost, note, at) values
  ('5a490000-0000-4000-8000-000000000001', 'purchase', 20000, 1, 'compra 490', now() - interval '3 days'),
  ('5a490000-0000-4000-8000-000000000002', 'purchase', 100, 60, 'compra 490', now() - interval '3 days'),
  ('5a490000-0000-4000-8000-000000000003', 'purchase', 5000, 2, 'compra 490', now() - interval '3 days');
insert into public.recipes (menu_item_id, stock_item_id, qty)
  select id, '5a490000-0000-4000-8000-000000000001'::uuid, 200 from public.menu_items where name = 'Latte'
  union all select id, '5a490000-0000-4000-8000-000000000002'::uuid, 1 from public.menu_items where name = 'Tea'
  union all select id, '5a490000-0000-4000-8000-000000000003'::uuid, 50 from public.menu_items where name = 'Galleta 490';

-- helpers (test schema; they read as the test superuser, between the café's calls)
create function test.o490(n int) returns uuid language sql immutable as $$ select ('d4900000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create function test.r490(n int) returns uuid language sql immutable as $$ select ('e4900000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid $$;
create function test.li490(p uuid, n int) returns uuid language sql immutable as $$ select md5(p::text || '-' || n)::uuid $$;
-- this file's café sign-in: the registered till «Caja 490» (test.login resets the claims)
create function test.cafe490() returns void language sql as $$ select test.login('cafe'); select test.session('till-490') $$;
-- the page's lines [[name, price, qty], …] → pos.html's items (the product's id, as the menu gives it)
create function test.items490(p uuid, spec jsonb) returns jsonb language sql stable as $$
  select jsonb_agg(jsonb_build_object('id', test.li490(p, o::int), 'item_name', e ->> 0, 'price_crc', (e ->> 1)::int, 'qty', (e ->> 2)::int,
                                      'menu_item_id', (select m.id from public.menu_items m where m.name = e ->> 0 order by m.available desc limit 1)) order by o)
    from jsonb_array_elements(spec) with ordinality x(e, o) $$;
create function test.sum490(spec jsonb) returns int language sql immutable as $$
  select coalesce(sum((e ->> 1)::int * (e ->> 2)::int), 0)::int from jsonb_array_elements(spec) e $$;
-- a paid ticket carrying an approval, as pos.html sends it (pos_record_sale): subtotal = the lines unless given
create function test.sale490(p uuid, spec jsonb, method text, disc_id text, disc int, sub int default null) returns jsonb language sql as $$
  select public.pos_record_sale(jsonb_build_object('id', p, 'created_at', now(), 'total_crc', coalesce(sub, test.sum490(spec)) - disc,
           'payment_method', method, 'paid', true, 'status', 'done', 'station', 'Caja 490', 'guest_name', 'Ticket 490',
           'subtotal_crc', coalesce(sub, test.sum490(spec)), 'discount_crc', disc, 'discount_id', disc_id,
           'items', test.items490(p, spec))) $$;
-- an open «Pay later» bill, as pos.html records it
create function test.bill490(p uuid, spec jsonb) returns jsonb language sql as $$
  select public.pos_record_sale(jsonb_build_object('id', p, 'created_at', now(), 'total_crc', test.sum490(spec),
           'payment_method', 'pending', 'paid', false, 'status', 'ready', 'station', 'Caja 490', 'source', 'front',
           'guest_name', 'Cuenta 490', 'items', test.items490(p, spec))) $$;
-- the window's call at this till, as pos.html sends it
create function test.a490(cat text, pin text, sub int, emp text default null, comp text default null, bill uuid default null,
                          expect int default null, req uuid default null) returns jsonb language sql as $$
  select public.descuento_autorizar(cat, pin, sub, emp, comp, bill, expect, req, 'Caja 490') $$;
-- readers
create function test.ord490(p uuid) returns jsonb language sql stable as $$
  select jsonb_build_object('total', total_crc, 'subtotal', subtotal_crc, 'discount', discount_crc, 'tax', tax_crc,
                            'reason', discount_reason, 'by', discount_by, 'method', payment_method, 'paid', paid,
                            'flags', to_jsonb(flags), 'parts', parts_crc, 'day', coalesce(business_date = public.cr_today(), false))
    from public.orders where id = p $$;
-- each line as stored: name qty×price, the stamped rate, its share of the discount, its IVA and its net
create function test.lns490(p uuid) returns text language sql stable as $$
  select string_agg(item_name || ' ' || qty || 'x' || price_crc || ' ' || tax_code || ' ' || tax_rate || ' alloc ' || discount_alloc_crc
                    || ' iva ' || tax_crc || ' net ' || net_crc, ' | ' order by price_crc * qty desc, item_name)
    from public.order_items where order_id = p $$;
-- a courtesy's lines: each one's whole amount is its discount share, IVA 0 and net 0
create function test.free490(p uuid) returns boolean language sql stable as $$
  select count(*) > 0 and bool_and(discount_alloc_crc = price_crc * qty and tax_crc = 0 and net_crc = 0)
    from public.order_items where order_id = p $$;
-- the server's IVA by stamped rate, and the page's (pos.html ivaGroups, the receipt's IVA rows): the lines sorted by
-- amount, the discount shared by floor(d × amount / gross) with the last line taking the rest, then
-- Math.round((amount − share) × r / (1 + r)) per line, summed by rate; r is the product's rate as the page reads it
-- from the menu (rateOf: taxOf[id] → TAX[code], else 13 %), the discount is the order's. Doubles, as JavaScript
create function test.iva_server490(p uuid) returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('rate', round(r, 4), 'tax', t) order by r desc), '[]')
    from (select tax_rate as r, sum(tax_crc)::numeric as t from public.order_items where order_id = p group by tax_rate) q $$;
create function test.iva_page490(p uuid) returns jsonb language plpgsql stable as $$
declare l record; gross float8; n int; d0 float8; lft float8; k int := 0; alloc float8; tx float8; by_rate jsonb := '{}';
begin
  select coalesce(sum(price_crc::float8 * qty), 0), count(*) into gross, n from public.order_items where order_id = p;
  select least(greatest(coalesce(discount_crc, 0), 0), greatest(gross, 0)) into lft from public.orders where id = p;
  d0 := lft;
  for l in select oi.price_crc::float8 * oi.qty as amt, coalesce(t.rate, 0.13)::float8 as rate
             from public.order_items oi left join public.menu_items m on m.id = oi.menu_item_id
             left join public.tax_rates t on t.code = coalesce(m.tax_code, 'IVA13')
            where oi.order_id = p order by oi.price_crc::float8 * oi.qty desc loop
    k := k + 1;
    alloc := case when gross <= 0 then 0 when k = n then lft else least(lft, floor(d0 * l.amt / gross)) end;
    lft := lft - alloc;
    tx := floor((l.amt - alloc) * l.rate / (1 + l.rate) + 0.5);
    by_rate := by_rate || jsonb_build_object(l.rate::text, coalesce((by_rate ->> l.rate::text)::float8, 0) + tx);
  end loop;
  return (select coalesce(jsonb_agg(jsonb_build_object('rate', round(e.rk::numeric, 4), 'tax', e.rv::numeric) order by e.rk::numeric desc), '[]')
            from jsonb_each_text(by_rate) e(rk, rv));
end $$;
-- the day's entry as acct.day_target computes it, kept under a tag; and what changed between two tags, by account
create table test.dt490 (tag text, account text, amount numeric);
create function test.snap490(tag text) returns int language sql as $$
  insert into test.dt490 select tag, account, amount from acct.day_target(public.cr_today());
  select count(*)::int from test.dt490 where dt490.tag = snap490.tag $$;
create function test.delta490(a text, b text) returns jsonb language sql stable as $$
  select coalesce(jsonb_object_agg(account, d order by account), '{}') from (
    select coalesce(y.account, x.account) as account, coalesce(y.amount, 0) - coalesce(x.amount, 0) as d
      from (select * from test.dt490 where tag = a) x full join (select * from test.dt490 where tag = b) y on y.account = x.account) q
   where d <> 0 $$;
create function test.acc490(k text) returns text language sql stable as $$ select acct.map(k) $$;
create function test.onhand490() returns text language sql stable as $$
  select string_agg(name || ' ' || trim_scale(on_hand), ', ' order by name) from public.stock_items where id::text like '5a490000-%' $$;

-- the till and the register: the café sign-in till-490 is the registered till of place 1; Ana opens the day with ₡50 000
select test.cafe490();
select test.eq(test.till('Caja 490'), 1, 'fixture: the café sign-in till-490 is the registered till of place 1');
set role authenticated;
select public.register_open(test.staff('ana'), '4826', 50000) ->> 'ok' as ro \gset
select public.descuento_estado() ->> 'guia_enabled' as ge \gset
reset role;
select test.eq(:'ro'::text, 'true', 'fixture: Ana opens the register with ₡50 000');
select test.eq(:'ge'::text, 'true', 'fixture: the window sees Guía Turista on');
select test.eq((select count(*)::int from public.orders), 0, 'fixture: no sale yet today');

-- 1) Guía Turista 100 % on a ticket: «Registrar cortesía», payment 'other', no tender (proposal §2.10, Q4) -----------------
select test.cafe490(); set role authenticated;
select public.register_expected() as re0 \gset
select test.a490('guia', '7391', 5400, null, '  Selvatura   Tours ', null, null, test.r490(1)) as g1 \gset
reset role;
select (:'g1'::jsonb) ->> 'id' as g1_id \gset
select test.snap490('before_g1');
select test.eq((:'g1'::jsonb) - 'id' - 'at',
               jsonb_build_object('ok', true, 'request_id', test.r490(1), 'category', 'guia', 'amount', 5400, 'subtotal', 5400,
                                  'reason', 'Tour guide', 'name', 'Dueño', 'role', 'owner', 'beneficiary', null,
                                  'company', 'Selvatura Tours', 'prior', null),
               '1 the owner''s code approves the courtesy: 100 %, amount = the list value ₡5 400, the company cleaned');
select test.cafe490(); set role authenticated;
select test.sale490(test.o490(1), '[["Latte", 2200, 2], ["Tea", 1000, 1]]', 'other', :'g1_id', 5400) as s1 \gset
select public.register_expected() as re1 \gset
reset role;
select test.eq(:'s1'::jsonb, '{"ok": true, "already": false, "other_lines": false}'::jsonb, '1 the courtesy is recorded (pos_record_sale), never refused');
select test.eq(test.ord490(test.o490(1)),
               '{"total": 0, "subtotal": 5400, "discount": 5400, "tax": 0, "reason": "Tour guide", "by": "Dueño", "method": "other", "paid": true, "flags": [], "parts": 0, "day": true}'::jsonb,
               '1 the sale: total ₡0, subtotal = discount = the list value ₡5 400, tax_crc 0, Tour guide by the owner, paid as ''other'', today, no flag');
select test.ok(test.free490(test.o490(1)), '1 each line: discount_alloc = its amount, IVA 0 and net 0 (_order_tax)');
select test.eq(test.lns490(test.o490(1)),
               'Latte 2x2200 IVA13 0.1300 alloc 4400 iva 0 net 0 | Tea 1x1000 T490 0.0400 alloc 1000 iva 0 net 0',
               '1 two different rates, each stamped from its product (13 % and 4 %); the list value stays in price × qty');
select test.eq((select tax_crc from public.orders where id = test.o490(1)) is not null, true,
               '1 its IVA is a real 0, not unknown (so it never falls in the untaxed bucket)');
select test.ok((select receipt_no is not null from public.orders where id = test.o490(1)), '1 it gets a receipt number from the server');
select test.eq((select count(*)::int from public.cash_tenders where order_id = test.o490(1)), 0, '1 no tender: no cash received and no change');
select test.eq((select count(*)::int from public.audit_log where target_id = test.o490(1)::text and action in ('discount_not_verified', 'discount_check_error')), 0,
               '1 nothing about it needs a manager (no discount_not_verified, no discount_check_error)');
select test.eq((select order_id = test.o490(1) and used_at is not null and freed_at is null from public.discount_approvals where id = :'g1_id'), true,
               '1 the approval is used by this sale');
select test.eq(test.iva_page490(test.o490(1)), '[{"rate": 0.1300, "tax": 0}, {"rate": 0.0400, "tax": 0}]'::jsonb,
               '1 the receipt''s IVA rows (the page''s ivaGroups) are ₡0 at both rates');
select test.eq(test.iva_server490(test.o490(1)), test.iva_page490(test.o490(1)), '1 and the server''s IVA by rate is the same');
-- the history and the reprint (what the page prints again: reason exactly "Tour guide", total 0, discount = subtotal)
select (select receipt_no from public.orders where id = test.o490(1)) as rn1 \gset
select test.cafe490(); set role authenticated;
select public.order_search(public.cr_today(), public.cr_today(), null, :rn1) as h1 \gset
select public.order_reprint(test.o490(1), 'Caja 490') ->> 'ok' as rp1 \gset
reset role;
select test.eq(jsonb_array_length((:'h1'::jsonb) -> 'orders'), 1, '1 the history finds the courtesy by its receipt number');
select test.eq(((:'h1'::jsonb) #> '{orders,0}') - 'id' - 'created_at' - 'receipt_no' - 'items' - 'day' - 'operator_name' - 'pickup_number',
               '{"total_crc": 0, "payment_method": "other", "paid": true, "status": "done", "voided_at": null, "void_reason": null,
                 "refunded_at": null, "refund_of": null, "guest_name": "Ticket 490", "station": "Caja 490", "subtotal_crc": 5400,
                 "discount_crc": 5400, "discount_reason": "Tour guide", "tax_crc": 0, "parts_crc": 0, "notes": null, "tender": null,
                 "parts": [], "can_void": true, "can_refund": false}'::jsonb,
               '1 the history shows it as the receipt prints it: ₡0, discount = subtotal, Tour guide, IVA ₡0, no tender; voidable today, nothing to refund');
select test.eq((select string_agg((x ->> 'name') || ' ' || (x ->> 'tax_rate') || ' ' || (x ->> 'tax'), ', ' order by x ->> 'name')
                  from jsonb_array_elements((:'h1'::jsonb) #> '{orders,0,items}') x), 'Latte 0.1300 0, Tea 0.0400 0',
               '1 and each line at its rate with IVA ₡0');
select test.eq(:'rp1'::text, 'true', '1 a reprint of the courtesy is allowed and logged (order_reprint)');
-- the register: ₡0 more in the drawer
select test.eq(:'re1'::jsonb, :'re0'::jsonb, '1 register_expected is unchanged by the courtesy (expected cash +₡0)');
select test.eq((:'re0'::jsonb) - 'business_date', '{"ok": true, "expected_crc": 50000, "expected_usd": 0, "usd_in": 0}'::jsonb,
               '1 (the drawer should hold the float alone, ₡50 000)');
-- the books (auto-posting on): only the cost of goods; revenue 0, IVA 0, advances 0 and no payment
select test.snap490('after_g1');
select test.delta490('before_g1', 'after_g1') as d1 \gset
select test.eq(coalesce(((:'d1'::jsonb) ->> test.acc490('revenue'))::numeric, 0), 0::numeric, '1 acct.day_target: revenue +₡0');
select test.eq(coalesce(((:'d1'::jsonb) ->> test.acc490('iva_out'))::numeric, 0), 0::numeric, '1 acct.day_target: IVA +₡0');
select test.eq(coalesce(((:'d1'::jsonb) ->> test.acc490('advances'))::numeric, 0), 0::numeric, '1 acct.day_target: advances +₡0');
select test.eq(coalesce(((:'d1'::jsonb) ->> test.acc490('pay_other'))::numeric, 0), 0::numeric, '1 acct.day_target: no money received (other +₡0)');
select test.eq(((:'d1'::jsonb) ->> test.acc490('cogs'))::numeric, 460::numeric,
               '1 acct.day_target: the cost of goods is posted (2 Latte × 200 ml at ₡1 + 1 tea bag at ₡60 = ₡460)');
select test.eq(:'d1'::jsonb, jsonb_build_object(test.acc490('inventory'), -460, test.acc490('cogs'), 460),
               '1 acct.day_target: the courtesy adds exactly that: cost of goods ₡460 against inventory, nothing else');
-- the IVA reports, as the accountant reads them: its lines at 0, never in the untaxed bucket
select test.login('accountant', 'aal2'); set role authenticated;
select public.tax_summary(public.cr_today(), public.cr_today()) as ts1 \gset
select public.iva_report(public.cr_today(), public.cr_today()) as ir1 \gset
select public.einvoice_list(public.cr_today(), public.cr_today()) as el1 \gset
reset role;
select test.eq((:'ts1'::jsonb) -> 'by_rate',
               '[{"code": "IVA13", "rate": 0.13, "lines": 1, "gross_crc": 0, "net_crc": 0, "tax_crc": 0},
                 {"code": "T490", "rate": 0.04, "lines": 1, "gross_crc": 0, "net_crc": 0, "tax_crc": 0}]'::jsonb,
               '1 tax_summary: the courtesy''s lines are counted at each rate, at ₡0 gross, net and IVA');
select test.eq((:'ts1'::jsonb) -> 'without_tax_detail', '{"orders": 0, "total_crc": 0}'::jsonb, '1 tax_summary: nothing in the untaxed bucket');
select test.eq(((:'ts1'::jsonb) ->> 'refunds_tax_crc')::int, 0, '1 tax_summary: no refunded IVA');
select test.eq((:'ir1'::jsonb) #> '{sales,by_rate}',
               '[{"code": "IVA13", "rate": 0.13, "lines": 1, "net_crc": 0, "tax_crc": 0}, {"code": "T490", "rate": 0.04, "lines": 1, "net_crc": 0, "tax_crc": 0}]'::jsonb,
               '1 iva_report: the courtesy''s lines at each rate at ₡0');
select test.eq((:'ir1'::jsonb) #> '{sales,without_tax_detail}', '{"orders": 0, "total_crc": 0}'::jsonb, '1 iva_report: nothing in the untaxed bucket');
select test.eq(((:'ir1'::jsonb) #>> '{sales,tax_crc}')::numeric || ' ' || ((:'ir1'::jsonb) ->> 'net_crc')::numeric, '0 0',
               '1 iva_report: sales IVA ₡0 and the period''s net IVA ₡0');
-- the e-document in shadow mode: a ticket at ₡0
select test.eq((select kind || ' ' || mode || ' ' || status || ' ' || total_crc || ' ' || tax_crc from public.e_documents where order_id = test.o490(1)),
               'TE shadow pending 0.00 0.00', '1 shadow e-document: a ticket (TE), pending, total ₡0 and IVA ₡0');
select test.eq((select (x ->> 'kind') || ' ' || (x ->> 'status') || ' ' || trim_scale((x ->> 'total_crc')::numeric) || ' ' || trim_scale((x ->> 'tax_crc')::numeric)
                  from jsonb_array_elements((:'el1'::jsonb) -> 'documents') x where (x ->> 'receipt_no')::bigint = :rn1),
               'TE pending 0 0', '1 einvoice_list (the accountant) shows it at ₡0, with its receipt number');

-- 2) a second courtesy voided the same day: the stock comes back (0005, §2.10 «Corrections») ----------------------------
select test.cafe490(); set role authenticated;
select test.a490('guia', '7391', 3200, null, 'Selvatura Tours', null, null, test.r490(2)) ->> 'id' as g2_id \gset
reset role;
select test.onhand490() as oh0 \gset
select test.cafe490(); set role authenticated;
select test.sale490(test.o490(2), '[["Latte", 2200, 1], ["Tea", 1000, 1]]', 'other', :'g2_id', 3200) ->> 'ok' as s2 \gset
reset role;
select test.onhand490() as oh1 \gset
select test.cafe490(); set role authenticated;
select public.manager_void_order(test.staff('ana'), '4826', test.o490(2), 'Cortesía repetida') as v2 \gset
select public.register_expected() as re2 \gset
reset role;
select test.onhand490() as oh2 \gset
select test.eq(:'s2'::text || ' ' || (test.ord490(test.o490(2)) ->> 'total'), 'true 0', '2 a second courtesy (Latte + Tea) is recorded at ₡0');
select test.eq(:'oh1'::text, 'Harina 490 5000, Leche 490 19400, Té 490 98',
               '2 it took its stock (200 ml of milk and one tea bag, after the first courtesy''s 400 ml and one bag)');
select test.eq(:'v2'::jsonb, '{"ok": true}'::jsonb, '2 Ana voids it the same day (manager_void_order): ok');
select test.eq(:'oh2'::text, :'oh0', '2 the void gives the stock back (on hand as before the sale)');
select test.eq((select string_agg(s.name || ' ' || trim_scale(m.qty) || ' at ' || trim_scale(m.unit_cost), ', ' order by s.name)
                  from public.stock_moves m join public.stock_items s on s.id = m.item_id where m.order_id = test.o490(2) and m.kind = 'void'),
               'Leche 490 200 at 1, Té 490 1 at 60', '2 as ''void'' moves at the cost the sale took it out with');
select test.eq((select status || ' ' || total_crc from public.e_documents where order_id = test.o490(2)), 'cancelled 0.00',
               '2 its shadow e-document is cancelled with the void');
select test.eq((select order_id = test.o490(2) and freed_at is null from public.discount_approvals where id = :'g2_id'), true,
               '2 Guía has no daily quota: the voided sale keeps its approval, nothing is freed');
select test.eq((select count(*)::int from public.audit_log where action in ('discount_freed', 'discount_not_freed', 'discount_self_void', 'discount_trigger_error')), 0,
               '2 and the day trigger writes nothing for it (Empleado only)');
select test.eq(:'re2'::jsonb, :'re0'::jsonb, '2 register_expected still unchanged');
select test.snap490('after_g2');
select test.eq(test.delta490('before_g1', 'after_g2'), jsonb_build_object(test.acc490('inventory'), -460, test.acc490('cogs'), 460),
               '2 the voided courtesy adds nothing to the day (its sale and its return cancel)');

-- 3) the register close and the books: one order more, every method at ₡0, revenue 0, IVA 0, advances 0 --------------
select test.cafe490(); set role authenticated;
select public.register_close(test.staff('ana'), '4826', 0, 50000, null) as rc \gset
reset role;
select test.eq((:'rc'::jsonb) ->> 'ok' || ' ' || ((:'rc'::jsonb) ->> 'reclosed'), 'true false', '3 Ana closes the register (register_close)');
select test.eq((select jsonb_build_object('orders', orders_count, 'cash', sales_cash_crc, 'usd', sales_cash_usd_crc, 'card', sales_card_crc,
                                          'sinpe', sales_sinpe_crc, 'other', sales_other_crc, 'total', sales_total_crc,
                                          'expected', expected_cash_crc, 'cash_diff', cash_diff_crc, 'card_diff', card_diff_crc, 'usd_in', usd_in)
                  from public.register_days where business_date = public.cr_today()),
               '{"orders": 1, "cash": 0, "usd": 0, "card": 0, "sinpe": 0, "other": 0, "total": 0, "expected": 50000, "cash_diff": 0, "card_diff": 0, "usd_in": 0}'::jsonb,
               '3 the close counts the courtesy as one order (+1; the voided one not) and every method at ₡0; the drawer = the float');
select test.eq((select count(*)::int from public.audit_log where action = 'ledger_post_failed'), 0, '3 the close posts the day without an error');
select test.lives('set constraints all immediate', '3 the posted day balances (the ledger''s own check, run now)');
set constraints all deferred;
select test.eq((select count(*)::int || ' ' || min(source_key) from acct.entries where source = 'day'), '1 day:' || public.cr_today() || ':1',
               '3 one day entry, posted by the close (automatic posting on)');
select test.eq((select jsonb_object_agg(account, amt order by account) from (
                  select l.account, sum(l.debit - l.credit) as amt from acct.lines l join acct.entries e on e.id = l.entry_id
                   where e.source = 'day' group by l.account) q),
               jsonb_build_object(test.acc490('inventory'), -460, test.acc490('cogs'), 460),
               '3 the entry: cost of goods ₡460 against inventory, and no revenue, IVA, advance or payment line');
select test.login('accountant', 'aal2'); set role authenticated;
select public.iva_report(public.cr_today(), public.cr_today()) as ir2 \gset
reset role;
select test.eq((:'ir2'::jsonb) -> 'ledger', '{"iva_out_crc": 0, "iva_in_crc": 0, "net_crc": 0, "pending_days": 0}'::jsonb,
               '3 iva_report: the books hold IVA ₡0 for the day, and the day is not pending');
-- after the close: a void answers closed_day and a refund refuses a total of ₡0 (today's rule, 0006)
select test.cafe490(); set role authenticated;
select public.order_search(public.cr_today(), public.cr_today(), null, :rn1) #> '{orders,0}' as h2 \gset
select public.manager_void_order(test.staff('ana'), '4826', test.o490(1), 'Error') as v1 \gset
select public.manager_refund_order(test.staff('ana'), '4826', test.o490(1), 'Devolver la cortesía') as f1 \gset
reset role;
select test.eq((:'h2'::jsonb) ->> 'can_void' || ' ' || ((:'h2'::jsonb) ->> 'can_refund'), 'false false',
               '3 after the close the history offers neither void nor refund for the courtesy');
select test.eq(:'v1'::jsonb, jsonb_build_object('ok', false, 'error', 'closed_day', 'business_date', public.cr_today()),
               '3 a void after the close: closed_day');
select test.eq(:'f1'::jsonb, '{"ok": false, "error": "is_refund"}'::jsonb, '3 a refund after the close: is_refund (a ₡0 sale has nothing to give back)');
select test.eq((select voided_at is null and refunded_at is null from public.orders where id = test.o490(1)), true, '3 the courtesy stands as it was closed');
select test.eq((select count(*)::int from public.orders where refund_of is not null), 0, '3 no refund row was written');
select test.eq((select count(*)::int from public.e_documents where kind = 'NC'), 0, '3 and no credit note');

-- 4) Guía Turista on a bill: the whole bill to ₡0, closed with tab_pay('other', null, null) (§2.10 «Bill») ---------------
select test.snap490('before_bill');
select test.cafe490(); set role authenticated;
select test.bill490(test.o490(3), '[["Latte", 2200, 1], ["Tea", 1000, 2]]') ->> 'ok' as b3 \gset
select test.a490('guia', '7391', 4200, null, 'Monteverde Explorer', test.o490(3), 4200, test.r490(3)) as g3 \gset
reset role;
select (:'g3'::jsonb) ->> 'id' as g3_id \gset
select test.eq(:'b3'::text, 'true', '4 (fixture) an open bill: Latte ₡2 200 + 2 Tea ₡2 000 = ₡4 200');
select test.eq(((:'g3'::jsonb) - 'id' - 'at' - 'request_id'),
               jsonb_build_object('ok', true, 'category', 'guia', 'amount', 4200, 'subtotal', 4200, 'reason', 'Tour guide', 'name', 'Dueño',
                                  'role', 'owner', 'beneficiary', null, 'company', 'Monteverde Explorer', 'prior', null,
                                  'order_id', test.o490(3), 'total', 0, 'discount', 4200),
               '4 the owner''s code puts the courtesy on the whole bill: total ₡0, discount ₡4 200');
select test.eq(test.ord490(test.o490(3)),
               '{"total": 0, "subtotal": 4200, "discount": 4200, "tax": 0, "reason": "Tour guide", "by": "Dueño", "method": "pending", "paid": false, "flags": [], "parts": 0, "day": false}'::jsonb,
               '4 the bill: ₡0, subtotal = discount = ₡4 200, IVA 0, not paid yet');
select test.ok(test.free490(test.o490(3)), '4 each bill line: its whole amount as discount, IVA 0, net 0');
select test.eq(test.lns490(test.o490(3)),
               'Latte 1x2200 IVA13 0.1300 alloc 2200 iva 0 net 0 | Tea 2x1000 T490 0.0400 alloc 2000 iva 0 net 0', '4 at two rates');
select test.eq(test.iva_server490(test.o490(3)), test.iva_page490(test.o490(3)), '4 the page''s IVA rows for the bill match the server''s (₡0 at both rates)');
select test.eq((select bill_id = test.o490(3) and order_id = test.o490(3) and used_at is not null from public.discount_approvals where id = :'g3_id'), true,
               '4 the approval names the bill and is used by it');
select test.cafe490(); set role authenticated;
select public.tab_pay(test.o490(3), 'cash_crc', jsonb_build_array(jsonb_build_object('item_id', test.li490(test.o490(3), 1), 'qty', 1)), null, 'Caja 490') as p3a \gset
select public.tab_pay(test.o490(3), 'other', null, 100, 'Caja 490') as p3b \gset
select public.tab_pay(test.o490(3), 'other', null, null, 'Caja 490') as p3 \gset
reset role;
select test.eq(:'p3a'::jsonb, '{"ok": false, "error": "nothing_due"}'::jsonb, '4 a ₡0 bill is never paid by item: nothing_due');
select test.eq(:'p3b'::jsonb, '{"ok": false, "error": "nothing_due"}'::jsonb, '4 nor by an amount: nothing_due');
select test.eq(:'p3'::jsonb, jsonb_build_object('ok', true, 'closed', true, 'amount', 0, 'left', 0, 'order_id', test.o490(3)),
               '4 tab_pay(''other'', null, null) closes it as a whole');
select test.eq(test.ord490(test.o490(3)),
               '{"total": 0, "subtotal": 4200, "discount": 4200, "tax": 0, "reason": "Tour guide", "by": "Dueño", "method": "other", "paid": true, "flags": [], "parts": 0, "day": true}'::jsonb,
               '4 the bill: paid as ''other'' today at ₡0, its IVA still 0');
select test.eq((select count(*)::int from public.orders where part_of = test.o490(3)), 0, '4 no payment part was written');
select test.eq((select bool_and(paid_qty = qty) from public.order_items where order_id = test.o490(3)), true, '4 every line is settled');
select test.eq((select total_crc || ' ' || tax_crc from public.e_documents where order_id = test.o490(3)), '0.00 0.00',
               '4 its shadow e-document followed the courtesy to ₡0 and IVA ₡0');
select test.snap490('after_bill');
select test.eq(test.delta490('before_bill', 'after_bill'), jsonb_build_object(test.acc490('inventory'), -320, test.acc490('cogs'), 320),
               '4 acct.day_target: the bill adds only its cost of goods (₡320): revenue 0, IVA 0, advances 0, no payment');

-- 5) the realistic cases keep the discount and a flag, so no phantom IVA (§2.10 «Phantom IVA removed», §2.6c) -------------
-- a) a late courtesy (the approval 31 minutes old when the sale is rung): recorded at ₡0, flagged discount_late
select test.cafe490(); set role authenticated;
select test.a490('guia', '7391', 2200, null, 'Selvatura Tours', null, null, test.r490(4)) ->> 'id' as g4_id \gset
reset role;
update public.discount_approvals set created_at = created_at - interval '31 minutes' where id = :'g4_id';
select test.snap490('before_late');
select test.cafe490(); set role authenticated;
select test.sale490(test.o490(4), '[["Latte", 2200, 1]]', 'other', :'g4_id', 2200) ->> 'ok' as s4 \gset
reset role;
select test.snap490('after_late');
select test.eq(:'s4'::text, 'true', '5a a late courtesy is recorded, not refused (no discount-less fallback)');
select test.eq(test.ord490(test.o490(4)),
               '{"total": 0, "subtotal": 2200, "discount": 2200, "tax": 0, "reason": "Tour guide", "by": "Dueño", "method": "other", "paid": true, "flags": ["discount_late"], "parts": 0, "day": true}'::jsonb,
               '5a it keeps its ₡2 200 discount and IVA 0, with the flag discount_late for a manager');
select test.ok(test.free490(test.o490(4)), '5a its line at IVA 0 and net 0');
select test.eq(test.delta490('before_late', 'after_late'), jsonb_build_object(test.acc490('inventory'), -200, test.acc490('cogs'), 200),
               '5a acct.day_target: no phantom revenue or IVA, only its cost of goods');
-- b) a courtesy let go (×), then rung anyway: it takes the approval back and stays at ₡0
select test.cafe490(); set role authenticated;
select test.a490('guia', '7391', 1000, null, 'Selvatura Tours', null, null, test.r490(5)) ->> 'id' as g5_id \gset
select public.descuento_liberar(:'g5_id') as l5 \gset
reset role;
select test.eq(:'l5'::jsonb, jsonb_build_object('ok', true, 'id', :'g5_id'::uuid), '5b the page lets the courtesy go (descuento_liberar)');
select test.snap490('before_released');
select test.cafe490(); set role authenticated;
select test.sale490(test.o490(5), '[["Tea", 1000, 1]]', 'other', :'g5_id', 1000) ->> 'ok' as s5 \gset
reset role;
select test.snap490('after_released');
select test.eq(:'s5'::text, 'true', '5b a sale on the released approval is recorded, not refused');
select test.eq(test.ord490(test.o490(5)),
               '{"total": 0, "subtotal": 1000, "discount": 1000, "tax": 0, "reason": "Tour guide", "by": "Dueño", "method": "other", "paid": true, "flags": [], "parts": 0, "day": true}'::jsonb,
               '5b at ₡0 with its whole discount, IVA 0, the label as approved and no flag');
select test.eq((select order_id = test.o490(5) and freed_at is null and freed_how is null from public.discount_approvals where id = :'g5_id'), true,
               '5b the sale takes the approval back (no longer released)');
select test.eq((select (details ->> 'day_taken') || ' ' || (details ->> 'freed_how') from public.audit_log
                 where action = 'discount_used_after_release' and target_id = :'g5_id'), 'true released',
               '5b and it is logged (discount_used_after_release)');
select test.eq(test.delta490('before_released', 'after_released'), jsonb_build_object(test.acc490('inventory'), -60, test.acc490('cogs'), 60),
               '5b acct.day_target: only its cost of goods');
-- c) a mismatch: a Huésped approval for ₡3 200 (₡320), and the sale rings ₡4 700 with that ₡320
select test.cafe490(); set role authenticated;
select test.a490('huesped', '4826', 3200, null, null, null, null, test.r490(6)) as h6 \gset
reset role;
select (:'h6'::jsonb) ->> 'id' as h6_id \gset
select test.eq((:'h6'::jsonb) ->> 'amount' || ' ' || ((:'h6'::jsonb) ->> 'reason'), '320 Hotel guest', '5c (fixture) a Huésped approval: ₡3 200 → ₡320');
select test.snap490('before_mismatch');
select test.cafe490(); set role authenticated;
select test.sale490(test.o490(6), '[["Latte", 2200, 1], ["Banana Bread", 1500, 1], ["Tea", 1000, 1]]', 'card', :'h6_id', 320) ->> 'ok' as s6 \gset
reset role;
select test.snap490('after_mismatch');
select test.delta490('before_mismatch', 'after_mismatch') as d6 \gset
select test.eq(:'s6'::text, 'true', '5c the sale whose subtotal is not the approved one is recorded, never refused');
select test.eq(test.ord490(test.o490(6)),
               '{"total": 4380, "subtotal": 4700, "discount": 320, "tax": 433, "reason": "Hotel guest · not verified", "by": null, "method": "card", "paid": true, "flags": ["discount_not_verified"], "parts": 0, "day": true}'::jsonb,
               '5c it keeps its real discount ₡320 and the money charged ₡4 380, flagged discount_not_verified (one flag: no total_mismatch)');
select test.eq((select discount_id from public.orders where id = test.o490(6)), :'h6_id'::uuid, '5c and stays linked to its approval');
select test.eq((select sum(net_crc + tax_crc)::int || ' ' || sum(discount_alloc_crc)::int from public.order_items where order_id = test.o490(6)), '4380 320',
               '5c its lines: net + IVA = the money received, the shares add up to the discount');
select test.eq(-(((:'d6'::jsonb) ->> test.acc490('revenue'))::numeric + ((:'d6'::jsonb) ->> test.acc490('iva_out'))::numeric), 4380::numeric,
               '5c acct.day_target: revenue + IVA = the money received ₡4 380');
select test.eq(((:'d6'::jsonb) ->> test.acc490('iva_out'))::numeric, -433::numeric, '5c acct.day_target: the IVA is the sale''s own (₡433)');
select test.eq(((:'d6'::jsonb) ->> test.acc490('pay_card'))::numeric, 4380::numeric, '5c acct.day_target: card +₡4 380');
select test.eq(coalesce(((:'d6'::jsonb) ->> test.acc490('advances'))::numeric, 0), 0::numeric, '5c acct.day_target: nothing as an advance');
select test.eq(:'d6'::jsonb, jsonb_build_object(test.acc490('pay_card'), 4380, test.acc490('inventory'), -260, test.acc490('iva_out'), -433,
                                               test.acc490('revenue'), -3947, test.acc490('cogs'), 260),
               '5c acct.day_target: exactly card ₡4 380, revenue ₡3 947, IVA ₡433 and its cost of goods ₡260');
-- d) the same approval rung again on a second sale (already used by another order): the money as charged, unlinked
select test.snap490('before_other');
select test.cafe490(); set role authenticated;
select test.sale490(test.o490(7), '[["Latte", 2200, 1], ["Tea", 1000, 1]]', 'card', :'h6_id', 320) ->> 'ok' as s7 \gset
reset role;
select test.snap490('after_other');
select test.delta490('before_other', 'after_other') as d7 \gset
select test.eq(:'s7'::text, 'true', '5d a second sale on an approval another sale already used is recorded, not refused');
select test.eq(test.ord490(test.o490(7)),
               '{"total": 2880, "subtotal": 3200, "discount": 320, "tax": 263, "reason": "Hotel guest · not verified", "by": null, "method": "card", "paid": true, "flags": ["discount_not_verified"], "parts": 0, "day": true}'::jsonb,
               '5d with its ₡320 discount and the money it charged, flagged discount_not_verified');
select test.eq((select discount_id is null from public.orders where id = test.o490(7)), true, '5d unlinked (the approval stays on the first sale)');
select test.eq(:'d7'::jsonb, jsonb_build_object(test.acc490('pay_card'), 2880, test.acc490('inventory'), -260, test.acc490('iva_out'), -263,
                                               test.acc490('revenue'), -2617, test.acc490('cogs'), 260),
               '5d acct.day_target: revenue ₡2 617 + IVA ₡263 = the money received ₡2 880, nothing as an advance');

-- 6) the report's courtesies: the list value by stamped rate, information only (A-13: no tax computed) ------------------
select test.login('accountant', 'aal2'); set role authenticated;
select public.descuentos_informe(public.cr_today(), public.cr_today()) -> 'courtesies' as cy \gset
reset role;
select test.eq(:'cy'::jsonb, '[{"tax_rate": 0.0400, "list_value": 4000}, {"tax_rate": 0.1300, "list_value": 8800}]'::jsonb,
               '6 courtesies by rate: the given courtesies'' lines (the voided one left out) at 13 % ₡8 800 and at 4 % ₡4 000');
select test.eq((select string_agg(distinct k, ' ' order by k) from jsonb_array_elements(:'cy'::jsonb) x, jsonb_object_keys(x) k), 'list_value tax_rate',
               '6 only the list value and the rate: no IVA amount is computed for a courtesy');

-- 7) the IVA split of Empleado 30 % and Local 10 % is the page's (pos.html ivaGroups) ------------------------------------
-- a) Empleado for Luis on a ticket: Latte ₡2 200, 2 Tea ₡2 000, a cookie ₡1 257 → ₡5 457, 30 % = ₡1 637
select test.cafe490(); set role authenticated;
select test.a490('empleado', '4826', 5457, '5284', null, null, null, test.r490(8)) as e8 \gset
reset role;
select test.eq((:'e8'::jsonb) ->> 'amount' || ' ' || ((:'e8'::jsonb) ->> 'beneficiary'), '1637 Luis', '7a (fixture) Ana''s and Luis''s codes: 30 % of ₡5 457 = ₡1 637');
select test.cafe490(); set role authenticated;
select test.sale490(test.o490(8), '[["Latte", 2200, 1], ["Tea", 1000, 2], ["Galleta 490", 1257, 1]]', 'card', (:'e8'::jsonb) ->> 'id', 1637) ->> 'ok' as s8 \gset
reset role;
select test.eq(:'s8'::text || ' ' || (test.ord490(test.o490(8)) ->> 'reason') || ' ' || (test.ord490(test.o490(8)) ->> 'flags'), 'true Employee []',
               '7a the sale matches its approval: Employee, no flag');
select test.eq(test.lns490(test.o490(8)),
               'Latte 1x2200 IVA13 0.1300 alloc 659 iva 177 net 1364 | Tea 2x1000 T490 0.0400 alloc 599 iva 54 net 1347 | Galleta 490 1x1257 T490 0.0400 alloc 379 iva 34 net 844',
               '7a the server''s lines: shares floor(1637 × amount / 5457), the last line the rest; IVA per line on what is left');
select test.eq(test.iva_page490(test.o490(8)), '[{"rate": 0.1300, "tax": 177}, {"rate": 0.0400, "tax": 88}]'::jsonb,
               '7a the page''s ivaGroups for this ticket: 13 % ₡177, 4 % ₡88');
select test.eq(test.iva_server490(test.o490(8)), test.iva_page490(test.o490(8)), '7a the server''s IVA by rate = the page''s');
select test.eq((select tax_crc from public.orders where id = test.o490(8)), 265, '7a the sale''s IVA = the sum of the page''s rows');
select test.eq((select sum(net_crc + tax_crc)::int || ' ' || sum(discount_alloc_crc)::int from public.order_items where order_id = test.o490(8)), '3820 1637',
               '7a net + IVA = the ₡3 820 charged; the shares add up to the discount');
-- b) Local on a ticket: Mocha ₡2 400, 3 cookies ₡3 771, Espresso ₡1 300 → ₡7 471, 10 % = ₡747
select test.cafe490(); set role authenticated;
select test.a490('local', '4826', 7471, null, null, null, null, test.r490(9)) as l9 \gset
select test.sale490(test.o490(9), '[["Mocha", 2400, 1], ["Galleta 490", 1257, 3], ["Espresso", 1300, 1]]', 'card', (:'l9'::jsonb) ->> 'id', 747) ->> 'ok' as s9 \gset
reset role;
select test.eq((:'l9'::jsonb) ->> 'amount' || ' ' || :'s9' || ' ' || (test.ord490(test.o490(9)) ->> 'reason') || ' ' || (test.ord490(test.o490(9)) ->> 'flags'),
               '747 true Local []', '7b (fixture) a Local approval of ₡747 and its sale: Local, no flag');
select test.eq(test.lns490(test.o490(9)),
               'Galleta 490 3x1257 T490 0.0400 alloc 377 iva 131 net 3263 | Mocha 1x2400 IVA13 0.1300 alloc 239 iva 249 net 1912 | Espresso 1x1300 IVA13 0.1300 alloc 131 iva 134 net 1035',
               '7b the server''s lines');
select test.eq(test.iva_page490(test.o490(9)), '[{"rate": 0.1300, "tax": 383}, {"rate": 0.0400, "tax": 131}]'::jsonb,
               '7b the page''s ivaGroups: 13 % ₡383, 4 % ₡131');
select test.eq(test.iva_server490(test.o490(9)), test.iva_page490(test.o490(9)), '7b the server''s IVA by rate = the page''s');
select test.eq((select tax_crc || ' ' || total_crc from public.orders where id = test.o490(9)), '514 6724', '7b the sale''s IVA ₡514 on ₡6 724 charged');
-- c) Empleado for Marta on a bill: Latte ₡2 200, a cookie ₡1 257, Tea ₡1 000 → ₡4 457, 30 % = ₡1 337
select test.cafe490(); set role authenticated;
select test.bill490(test.o490(10), '[["Latte", 2200, 1], ["Galleta 490", 1257, 1], ["Tea", 1000, 1]]') ->> 'ok' as b10 \gset
select test.a490('empleado', '4826', 4457, '6173', null, test.o490(10), 4457, test.r490(10)) as e10 \gset
reset role;
select test.eq(:'b10'::text || ' ' || ((:'e10'::jsonb) ->> 'beneficiary') || ' ' || ((:'e10'::jsonb) ->> 'discount') || ' ' || ((:'e10'::jsonb) ->> 'total'),
               'true Marta 1337 3120', '7c (fixture) an Empleado discount for Marta on a ₡4 457 bill: ₡1 337 off, ₡3 120 to pay');
select test.eq(test.lns490(test.o490(10)),
               'Latte 1x2200 IVA13 0.1300 alloc 659 iva 177 net 1364 | Galleta 490 1x1257 T490 0.0400 alloc 377 iva 34 net 846 | Tea 1x1000 T490 0.0400 alloc 301 iva 27 net 672',
               '7c the bill''s lines, the discount spread as on a ticket');
select test.eq(test.iva_page490(test.o490(10)), '[{"rate": 0.1300, "tax": 177}, {"rate": 0.0400, "tax": 61}]'::jsonb,
               '7c the page''s ivaGroups for the bill: 13 % ₡177, 4 % ₡61');
select test.eq(test.iva_server490(test.o490(10)), test.iva_page490(test.o490(10)), '7c the server''s IVA by rate = the page''s');
select test.cafe490(); set role authenticated;
select public.tab_pay(test.o490(10), 'card', null, null, 'Caja 490') ->> 'closed' as p10 \gset
reset role;
select test.eq(:'p10'::text || ' ' || (select tax_crc || ' ' || total_crc from public.orders where id = test.o490(10)), 'true 238 3120',
               '7c paid in full: the bill keeps its IVA ₡238 on ₡3 120');
-- d) Local on a bill: Mocha ₡2 400, 3 Tea ₡3 000 → ₡5 400, 10 % = ₡540
select test.cafe490(); set role authenticated;
select test.bill490(test.o490(11), '[["Mocha", 2400, 1], ["Tea", 1000, 3]]') ->> 'ok' as b11 \gset
select test.a490('local', '4826', 5400, null, null, test.o490(11), 5400, test.r490(11)) as l11 \gset
reset role;
select test.eq(:'b11'::text || ' ' || ((:'l11'::jsonb) ->> 'discount') || ' ' || ((:'l11'::jsonb) ->> 'total'), 'true 540 4860',
               '7d (fixture) a Local discount on a ₡5 400 bill: ₡540 off');
select test.eq(test.lns490(test.o490(11)),
               'Tea 3x1000 T490 0.0400 alloc 300 iva 104 net 2596 | Mocha 1x2400 IVA13 0.1300 alloc 240 iva 248 net 1912', '7d the bill''s lines');
select test.eq(test.iva_page490(test.o490(11)), '[{"rate": 0.1300, "tax": 248}, {"rate": 0.0400, "tax": 104}]'::jsonb,
               '7d the page''s ivaGroups for the bill: 13 % ₡248, 4 % ₡104');
select test.eq(test.iva_server490(test.o490(11)), test.iva_page490(test.o490(11)), '7d the server''s IVA by rate = the page''s');

-- 8) a courtesy bill that an older page adds to: the new item is charged in full; _order_tax spreads the one discount
--    over every line (a pre-existing rule of bills, §2.10; the new page refuses the add, §3.5) --------------------------
select test.cafe490(); set role authenticated;
select test.bill490(test.o490(12), '[["Latte", 2200, 1], ["Tea", 1000, 2]]') ->> 'ok' as b12 \gset
select test.a490('guia', '7391', 4200, null, 'Monteverde Explorer', test.o490(12), 4200, test.r490(12)) ->> 'total' as g12 \gset
select public.tab_add_items(test.o490(12), jsonb_build_array(jsonb_build_object('menu_item_id', (select id from public.menu_items where name = 'Espresso'), 'qty', 1))) as a12 \gset
reset role;
select test.eq(:'b12'::text || ' ' || :'g12', 'true 0', '8 (fixture) a ₡4 200 bill made a courtesy: ₡0');
select test.eq((:'a12'::jsonb) ->> 'ok' || ' ' || ((:'a12'::jsonb) ->> 'added') || ' ' || ((:'a12'::jsonb) ->> 'total'), 'true 1300 1300',
               '8 an older page adds an Espresso (tab_add_items): the bill now asks ₡1 300, the new item at full price');
select test.eq((select subtotal_crc || ' ' || discount_crc || ' ' || total_crc from public.orders where id = test.o490(12)), '5500 4200 1300',
               '8 the discount stays the approved ₡4 200 (the courtesy never grows to the new item)');
select test.eq((select sum(net_crc + tax_crc)::int || ' ' || sum(discount_alloc_crc)::int from public.order_items where order_id = test.o490(12)), '1300 4200',
               '8 _order_tax spreads the ₡4 200 over all three lines: net + IVA = the ₡1 300 charged');
select test.eq(test.iva_server490(test.o490(12)), test.iva_page490(test.o490(12)), '8 and the page''s rule gives the same IVA rows');
select test.snap490('before_pay12');
select test.cafe490(); set role authenticated;
select public.tab_pay(test.o490(12), 'card', null, null, 'Caja 490') ->> 'closed' as p12 \gset
reset role;
select test.snap490('after_pay12');
select test.eq(:'p12'::text, 'true', '8 the guest pays the ₡1 300');
select test.eq(-((test.delta490('before_pay12', 'after_pay12') ->> test.acc490('revenue'))::numeric
                 + (test.delta490('before_pay12', 'after_pay12') ->> test.acc490('iva_out'))::numeric), 1300::numeric,
               '8 acct.day_target: revenue + IVA = the ₡1 300 received');
select test.eq(coalesce((test.delta490('before_pay12', 'after_pay12') ->> test.acc490('advances'))::numeric, 0), 0::numeric,
               '8 acct.day_target: nothing as an advance');

-- 9) with e-documents off (their default) a courtesy records none (0018); and the day as a whole -----------------------
select test.login('owner', 'aal2'); set role authenticated;
select public.setting_set('einvoice_mode', '"off"') ->> 'ok' as eo \gset
reset role;
select test.cafe490(); set role authenticated;
select test.a490('guia', '7391', 2200, null, 'Selvatura Tours', null, null, test.r490(13)) ->> 'id' as g13_id \gset
select test.sale490(test.o490(13), '[["Latte", 2200, 1]]', 'other', :'g13_id', 2200) ->> 'ok' as s13 \gset
reset role;
select test.eq(:'eo'::text || ' ' || :'s13' || ' ' || (test.ord490(test.o490(13)) ->> 'total'), 'true true 0',
               '9 (fixture) e-documents back off; one more courtesy recorded at ₡0');
select test.eq((select count(*)::int from public.e_documents where order_id = test.o490(13)), 0,
               '9 with einvoice_mode off a courtesy records no e-document, like every sale');
-- the day's IVA, as the accountant reads it: only the discounted sales' own IVA; the courtesies' lines add ₡0
select test.login('accountant', 'aal2'); set role authenticated;
select public.tax_summary(public.cr_today(), public.cr_today()) as ts9 \gset
select public.iva_report(public.cr_today(), public.cr_today()) as ir9 \gset
reset role;
select test.eq((select sum(tax_crc)::int from public.orders where id in (test.o490(1), test.o490(3), test.o490(4), test.o490(5), test.o490(13))), 0,
               '9 the five courtesies that stand hold IVA ₡0');
select test.eq((select string_agg((x ->> 'code') || ' ' || (x ->> 'tax_crc'), ', ' order by x ->> 'code') from jsonb_array_elements((:'ts9'::jsonb) -> 'by_rate') x),
               'IVA13 1457, T490 369',
               '9 tax_summary for the day: the IVA of the paid discounted sales alone (13 %: 397 + 228 + 177 + 383 + 177 + 95; 4 %: 36 + 35 + 88 + 131 + 61 + 18)');
select test.eq((:'ts9'::jsonb) -> 'without_tax_detail', '{"orders": 0, "total_crc": 0}'::jsonb, '9 tax_summary: still nothing in the untaxed bucket');
select test.eq(((:'ir9'::jsonb) #>> '{sales,tax_crc}')::numeric, 1826::numeric, '9 iva_report: sales IVA ₡1 826 for the day');
select test.eq((select count(*)::int from acct.day_target(public.cr_today()) where account = test.acc490('advances')), 0,
               '9 acct.day_target for the whole day: nothing as an advance (courtesies, unverified sales and bills included)');

select test.done();
rollback;
