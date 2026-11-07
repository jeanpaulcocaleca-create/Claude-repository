-- Migrations 0039/0040 (Proveedores, D-067): who may call what, and what each one reads. Every new function is owner-
-- rights with a fixed search path, runnable by a signed-in page and never by a visitor or PUBLIC; the internal ones by
-- nobody; the new tables are closed (row security, no rule, no right). A café device without the owner areas, a work
-- session's holder against management, and the accountant against orders and the catalog get «locked». What an employee
-- on shift reads has exactly the keys it needs to receive (no money, no contact, no SINPE); management reads money, the
-- SINPE (the payment notes only at the books' door) and the order's history.
begin;
insert into public.vendors (id, name, phone, email, payment_notes) values ('5b000000-0000-4000-8000-000000051601', 'Lácteos Monteverde', '2645-0000', 'ventas@lacteos.test', 'Cuenta IBAN de prueba');
insert into public.vendor_pay_info (vendor_id, sinpe, updated_by) values ('5b000000-0000-4000-8000-000000051601', '8888-0000', 'Dueño (owner)');
insert into public.stock_items (id, name, unit, pack_qty, cost_per_pack, vendor_id) values
  ('5a000000-0000-4000-8000-000000051601', 'Leche', 'unit', 12, 12000, '5b000000-0000-4000-8000-000000051601');
create temp table fn516 (sig text, public_fn boolean);
insert into fn516 select p.oid::regprocedure::text, p.proname !~ '^_' from pg_proc p
 where p.pronamespace = 'public'::regnamespace and (p.proname ~ '^(proveedor|proveedores|turno)_' or p.proname ~ '^_prov_');
create function test.keys516(j jsonb) returns text language sql immutable as $$
  select string_agg(k, ' ' order by k collate "C") from jsonb_object_keys(j) k $$;

-- 1) rights ---------------------------------------------------------------------------------------------------------------
select test.eq((select count(*)::int || ' ' || count(*) filter (where public_fn) from fn516), '72 27', '1 72 new functions: 27 a page calls, 45 internal');
select test.eq((select coalesce(string_agg(f.sig, ' '), '') from fn516 f join pg_proc p on p.oid = f.sig::regprocedure
                 where not p.prosecdef and (f.public_fn or p.prorettype <> 'trigger'::regtype)
                   and f.sig not in ('_prov_fail(text,jsonb)', '_prov_caught(text,text,text,text)', '_prov_uuid(text)', '_prov_num(jsonb)', '_prov_txt(jsonb,integer)',
                                     '_prov_bool(jsonb)', '_prov_id(jsonb)', '_prov_packs(jsonb,boolean,text)', '_prov_price(jsonb)', '_prov_pqe(numeric,numeric,numeric,numeric)',
                                     '_prov_station(text)', '_prov_date(jsonb)', '_prov_draft_json(purchase_drafts)')), '',
               '1 every function that reads or writes is owner-rights (the pure helpers need none)');
select test.eq((select coalesce(string_agg(f.sig, ' '), '') from fn516 f join pg_proc p on p.oid = f.sig::regprocedure
                 where p.prosecdef and not exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%')), '', '1 each owner-rights one pins its search path');
select test.eq((select coalesce(string_agg(f.sig, ' '), '') from fn516 f join pg_proc p on p.oid = f.sig::regprocedure
                 where f.public_fn and (has_function_privilege('anon', p.oid, 'execute') or not has_function_privilege('authenticated', p.oid, 'execute')
                                        or coalesce(p.proacl::text, '') ~ '(^|[{,])=X')), '',
               '1 a page may call the 27, a visitor and PUBLIC none (the backup account included)');
select test.eq((select coalesce(string_agg(f.sig, ' '), '') from fn516 f join pg_proc p on p.oid = f.sig::regprocedure
                 where not f.public_fn and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute')
                                            or coalesce(p.proacl::text, '') ~ '(^|[{,])=X')), '', '1 nobody may call the 45 internal ones directly');
select test.eq((select coalesce(string_agg(f.sig, ' '), '') from fn516 f join pg_proc p on p.oid = f.sig::regprocedure
                 where p.provolatile <> 'v' and f.sig ~ '^(turno_|proveedor_recibir|proveedores_lista|proveedores_por_recibir|proveedor_ficha|proveedor_pedido\(|proveedor_pago_)'), '',
               '1 every function that takes a work-session token or a PIN is volatile (a PIN try is never lost)');
select test.eq((select string_agg(c.relname || ':' || c.relrowsecurity || ':' || has_table_privilege('authenticated', c.oid, 'select,insert,update,delete')
                                  || ':' || has_table_privilege('anon', c.oid, 'select') || ':' || has_table_privilege('canopy_backup', c.oid, 'select')
                                  || ':' || (select count(*) from pg_policies x where x.tablename = c.relname), ' ' order by c.relname collate "C")
                  from pg_class c where c.relnamespace = 'public'::regnamespace and c.relname in ('vendor_items', 'purchase_drafts', 'purchase_receipt_lines',
                    'supplier_advances', 'vendor_pay_info', 'work_sessions')),
               'purchase_drafts:true:false:false:true:0 purchase_receipt_lines:true:false:false:true:0 supplier_advances:true:false:false:true:0 '
               || 'vendor_items:true:false:false:true:0 vendor_pay_info:true:false:false:true:0 work_sessions:true:false:false:true:0',
               '1 the six new tables: row security on, no rule, no right for a page or a visitor, read by the backup account');
select test.eq((select string_agg(conname, ' ' order by conname collate "C") from pg_constraint where conname like '%\_finite' and conrelid in
                 ('public.vendor_items'::regclass, 'public.purchase_receipt_lines'::regclass, 'public.supplier_advances'::regclass, 'public.purchase_lines'::regclass)
                 and conname ~ '(vendor_items|receipt_lines|advances|pack_qty_finite|ordered_unit_cost)'),
               'purchase_lines_ordered_unit_cost_finite purchase_lines_pack_qty_finite purchase_receipt_lines_expected_pack_price_finite purchase_receipt_lines_extra_reported_packs_finite '
               || 'purchase_receipt_lines_observed_pack_price_finite purchase_receipt_lines_pack_price_finite purchase_receipt_lines_pack_qty_finite purchase_receipt_lines_packs_finite '
               || 'purchase_receipt_lines_qty_finite purchase_receipt_lines_unit_cost_finite supplier_advances_amount_crc_finite vendor_items_pack_qty_finite '
               || 'vendor_items_usual_price_finite vendor_items_usual_qty_finite', '1 every new number has its finite check');
select test.login('anon'); set role anon;
select test.throws($$select public.proveedores_lista()$$, 'permission denied', '1 a visitor (anon) cannot call them');
select test.throws($$select public.turno_aqui('a1000000-0000-4000-8000-000000000002', '0000')$$, 'permission denied', '1 nor start a work session');
reset role;
select test.login('cafe'); select test.session('dev-516'); set role authenticated;
select test.throws($$select public._prov_dinero(gen_random_uuid())$$, 'permission denied', '1 a page cannot call an internal one');
select test.throws($$select public._prov_turno('x')$$, 'permission denied', '1 nor test a token by itself');

-- 2) the state: an order to receive (one delivery made), an order without supplier, an old draft order --------------------
select test.unlock(test.staff('ana'), '4826');
reset role;
select (select id::text from public.vendor_items where item_id = '5a000000-0000-4000-8000-000000051601') as vi \gset
set role authenticated;
select public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051601', jsonb_build_array(jsonb_build_object('vendor_item_id', :'vi', 'packs', 3)), 'Nota interna',
                                     '9a000000-0000-4000-8000-000000051601') ->> 'ok' as c1 \gset
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051601', '7e000000-0000-4000-8000-000000051601',
                 (public.proveedor_pedido('9a000000-0000-4000-8000-000000051601') #>> '{order,version}')::int,
                 (select jsonb_agg(jsonb_build_object('line_id', id, 'packs', 1)) from public.purchase_lines where po_id = '9a000000-0000-4000-8000-000000051601'), null, false, 'F-9')
                 ->> 'status', 'partially_received', '2 (one of three boxes received)');
reset role;
insert into public.purchase_orders (id, vendor_id, status, created_at) values ('9a000000-0000-4000-8000-000000051602', null, 'sent', now() - interval '1 day'),
                                                                 ('9a000000-0000-4000-8000-000000051603', '5b000000-0000-4000-8000-000000051601', 'draft', now() - interval '1 day');
insert into public.purchase_lines (po_id, item_id, packs, qty, unit_cost) values ('9a000000-0000-4000-8000-000000051602', '5a000000-0000-4000-8000-000000051601', 1, 12, 1000),
                                                                                ('9a000000-0000-4000-8000-000000051603', '5a000000-0000-4000-8000-000000051601', 1, 12, 1000);
-- 3) a café device without the owner areas, and with Luis's work session ---------------------------------------------------
select test.login('cafe'); select test.session('dev-516-r'); set role authenticated;
select test.eq(public.proveedores_lista(), '{"ok":false,"error":"locked"}'::jsonb, '3 no session, no owner areas: «locked»');
select test.eq(public.proveedores_lista('no-es-un-token'), '{"ok":false,"error":"no_session","why":"unknown"}'::jsonb, '3 a token that is no session: «no_session»');
select test.turno(test.staff('luis'), '5284') as tok \gset
select test.eq((select string_agg(coalesce(r ->> 'error', 'ok:' || (r ->> 'ok')), ' ') from (values
                  (public.proveedor_guardar('{"id":"5b000000-0000-4000-8000-000000051609","name":"X"}')),
                  (public.proveedor_producto_guardar(jsonb_build_object('id', :'vi', 'usual_price', 1))),
                  (public.proveedor_borrador_guardar('5b000000-0000-4000-8000-000000051601', '[]', null, 0)),
                  (public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051601', '[]', null, gen_random_uuid())),
                  (public.proveedor_pedido_editar('9a000000-0000-4000-8000-000000051601', 1, null, 'x')),
                  (public.proveedor_pedido_cancelar('9a000000-0000-4000-8000-000000051601', 1)),
                  (public.proveedor_pedido_cerrar('9a000000-0000-4000-8000-000000051601', 1)),
                  (public.proveedor_pedido_confirmar('9a000000-0000-4000-8000-000000051603', 1)),
                  (public.proveedor_pedido_asignar('9a000000-0000-4000-8000-000000051602', 1, '5b000000-0000-4000-8000-000000051601')),
                  (public.proveedor_recepcion_corregir('7e000000-0000-4000-8000-000000051601', gen_random_uuid(), '[]', 'algo mal')),
                  (public.proveedor_factura_registrar('5b000000-0000-4000-8000-000000051601', array['7e000000-0000-4000-8000-000000051601']::uuid[], '{}', gen_random_uuid())),
                  (public.proveedor_factura_anular(gen_random_uuid(), 'algo mal')),
                  (public.proveedor_anticipos_aplicar('5b000000-0000-4000-8000-000000051601')),
                  (public.proveedor_pago_registrar('{"vendor_id":"5b000000-0000-4000-8000-000000051601","amount":1,"method":"card_debit"}', gen_random_uuid())),
                  (public.proveedor_pago_anular(gen_random_uuid(), 'algo mal')),
                  (public.proveedores_alertas()),
                  (public.proveedor_historial('5b000000-0000-4000-8000-000000051601'))) v(r)),
               'locked locked locked locked locked locked locked locked locked locked locked locked locked locked locked locked locked',
               '3 with a work session but no owner areas: every management function answers «locked»');
-- what Luis reads: exactly these keys
select public.proveedores_lista(:'tok') as l1 \gset
select test.eq(test.keys516(:'l1'::jsonb) || ' | ' || test.keys516((:'l1'::jsonb) -> 'staff') || ' | ' || test.keys516((:'l1'::jsonb) #> '{vendors,0}'),
               'mode ok staff vendors | id name | id name to_receive', '3 the supplier list in receive mode');
select test.eq((:'l1'::jsonb) -> 'vendors', '[{"id":"5b000000-0000-4000-8000-000000051601","name":"Lácteos Monteverde","to_receive":1}]'::jsonb,
               '3 the suppliers with something to receive (sent or partly received; never a draft)');
select public.proveedores_por_recibir(:'tok') as l2 \gset
select test.eq(test.keys516(:'l2'::jsonb) || ' | ' || test.keys516((:'l2'::jsonb) #> '{orders,0}') || ' | ' || jsonb_array_length((:'l2'::jsonb) -> 'orders'),
               'ok orders | expected_on id lines pending_lines po_number sent_at status vendor_id vendor_name | 1',
               '3 the orders to receive: these keys; the order without supplier is for management only');
select public.proveedor_ficha('5b000000-0000-4000-8000-000000051601', :'tok') as l3 \gset
select test.eq(test.keys516(:'l3'::jsonb) || ' | ' || test.keys516((:'l3'::jsonb) -> 'vendor') || ' | ' || test.keys516((:'l3'::jsonb) #> '{orders,0}'),
               'mode ok orders vendor | id name | expected_on id lines pending_lines po_number sent_at status vendor_id vendor_name',
               '3 the supplier''s file in receive mode: no contact, no SINPE, no money');
select public.proveedor_pedido('9a000000-0000-4000-8000-000000051601', :'tok') as l4 \gset
select test.eq(test.keys516(:'l4'::jsonb) || ' | ' || test.keys516((:'l4'::jsonb) -> 'order') || ' | ' || test.keys516((:'l4'::jsonb) #> '{lines,0}')
               || ' | ' || test.keys516((:'l4'::jsonb) #> '{receipts,0}') || ' | ' || test.keys516((:'l4'::jsonb) #> '{receipts,0,lines,0}'),
               'lines mode ok order receipts | expected_on id po_number sent_at status vendor_name version | expected_pack_price id item_name label pack_label pack_qty packs '
               || 'pending_packs pos received_packs removed unit vendor_code | by_name id lines received_at | line_id packs',
               '3 the order in receive mode: no totals, no money, no contact, no note');
select test.eq(public.proveedor_pedido('9a000000-0000-4000-8000-000000051603', :'tok') ->> 'error', 'not_found', '3 a draft order does not exist for him');
select test.eq(public.proveedor_pedido('9a000000-0000-4000-8000-000000051602', :'tok') ->> 'error', 'not_found', '3 nor an order without supplier');
select test.eq(test.keys516(public.turno_estado(array[:'tok']) #> '{sessions,0}'), 'expires_at i ok staff_id staff_name', '3 turno_estado: whose, until when');

-- 4) management reads ----------------------------------------------------------------------------------------------------------
select test.login('cafe'); select test.session('dev-516'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select public.proveedores_lista() as m1 \gset
select test.eq(test.keys516(:'m1'::jsonb) || ' | ' || test.keys516((:'m1'::jsonb) #> '{vendors,0}'),
               'alerts can_manage can_owner can_pay mode no_vendor_orders ok vendors | active contact_name credit_crc credit_days drafts email id last_order_at lead_days '
               || 'name notes order_days owed_crc partial phone products stale_advances to_receive whatsapp', '3 the hub: no SINPE in the list');
select test.eq((:'m1'::jsonb) ->> 'no_vendor_orders' || ' ' || ((:'m1'::jsonb) ->> 'can_owner') || ' ' || ((:'m1'::jsonb) #>> '{vendors,0,owed_crc}'), '1 false 12000.00',
               '4 one order without supplier; a manager is not owner level; ₡12 000 received and not invoiced is owed');
select test.eq(jsonb_array_length(public.proveedores_por_recibir() -> 'orders'), 2, '4 management also sees the order without supplier («Sin proveedor · Asignar»)');
select public.proveedor_ficha('5b000000-0000-4000-8000-000000051601') as m2 \gset
select test.eq(test.keys516((:'m2'::jsonb) -> 'vendor'), 'active contact_name credit_days email id lead_days name notes order_days phone sinpe sinpe_changed_at sinpe_changed_by whatsapp',
               '4 a manager sees the SINPE (and who changed it, within 30 days), never the books'' payment notes');
select test.eq((:'m2'::jsonb) #>> '{vendor,sinpe}' || ' ' || ((:'m2'::jsonb) #>> '{vendor,sinpe_changed_by}'), '8888-0000 Dueño (owner)', '4 the SINPE and who changed it');
select test.eq(test.keys516((:'m2'::jsonb) #> '{products,0}'),
               'active id item_active item_id item_name label last_ordered_at last_pack_price last_packs on_hand on_order pack_label pack_qty par_level preferred preferred_vendor_name '
               || 'reorder_point stock_status times_ordered unit usual_price usual_qty vendor_code', '4 the products of the file');
select test.eq((:'m2'::jsonb) #>> '{products,0,times_ordered}' || ' ' || ((:'m2'::jsonb) #>> '{products,0,last_packs}') || ' ' || ((:'m2'::jsonb) #>> '{products,0,last_pack_price}')
               || ' ' || ((:'m2'::jsonb) #>> '{products,0,on_order}') || ' ' || ((:'m2'::jsonb) #>> '{products,0,preferred}'), '2 3 12000.00 36.0000 true',
               '4 «habitual»: ordered twice (the old draft order included), last 3 boxes at ₡12 000, 36 units on order (24 here, 12 without supplier), preferred');
select test.eq(test.keys516((:'m2'::jsonb) -> 'money'), 'advances credit_crc open_invoices other_payments owed_crc saldo stale_advances unapplied_crc uninvoiced',
               '4 the money of the file');
select test.eq(test.keys516((:'m2'::jsonb) #> '{orders,0}') || ' | ' || test.keys516((:'m2'::jsonb) #> '{orders,0,money}'),
               'close_requested created_at est_total expected_on id lines money pending_lines po_number received_at received_total sent_at status | due estimate invoice_missing paid status',
               '4 each order with its money');
select public.proveedor_pedido('9a000000-0000-4000-8000-000000051601') as m3 \gset
select test.eq(test.keys516(:'m3'::jsonb) || ' | ' || test.keys516((:'m3'::jsonb) -> 'money'),
               'can_manage can_pay history lines mode money ok order receipts totals | advances credit due due_iva estimate invoice_missing invoices paid payout_crc saldo status',
               '4 the order document for management');
select test.eq((:'m3'::jsonb) #>> '{order,note}' || ' ' || ((:'m3'::jsonb) #>> '{order,vendor_phone}') || ' ' || ((:'m3'::jsonb) #>> '{totals,estimated}') || ' '
               || ((:'m3'::jsonb) #>> '{totals,received_value}') || ' ' || ((:'m3'::jsonb) #>> '{money,saldo}'), 'Nota interna 2645-0000 36000.00 12000.00 40680.00',
               '4 its note, the supplier''s phone, ₡36 000 estimated, ₡12 000 received, ₡40 680 to pay with IVA');
select test.eq((select string_agg(h.v ->> 'action', ' ' order by h.n) from jsonb_array_elements((:'m3'::jsonb) -> 'history') with ordinality h(v, n)), 'po_create stock_receive',
               '4 its history');
select test.eq(public.proveedor_historial('5b000000-0000-4000-8000-000000051601', null, 0) ->> 'error', 'bad_request', '4 the history''s page size is 1..100');
select test.eq(public.proveedor_historial('5b000000-0000-4000-8000-000000051601', null, 101) ->> 'error', 'bad_request', '4 at most 100');
select test.eq(public.proveedor_historial('5b000000-0000-4000-8000-000000051601') -> 'orders', '[]'::jsonb, '4 no closed order yet');
-- the books' door: reads, the payment notes; not orders or the catalog
select test.login('accountant', 'aal2'); set role authenticated;
select public.proveedor_ficha('5b000000-0000-4000-8000-000000051601') as a1 \gset
select test.eq((:'a1'::jsonb) ->> 'mode' || ' ' || ((:'a1'::jsonb) ->> 'can_manage') || ' ' || ((:'a1'::jsonb) ->> 'can_pay') || ' ' || ((:'a1'::jsonb) ->> 'can_owner')
               || ' ' || ((:'a1'::jsonb) #>> '{vendor,payment_notes}'), 'manage false true true Cuenta IBAN de prueba',
               '4 the accountant reads the file with the payment notes, pays and voids, but does not keep orders');
select test.eq(public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051601', jsonb_build_array(jsonb_build_object('vendor_item_id', :'vi', 'packs', 1)), null, gen_random_uuid())
                 ->> 'error', 'locked', '4 the accountant creates no order');
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051601', gen_random_uuid(), 1, '[]') ->> 'error', 'locked', '4 nor receives');
select test.eq(public.turno_aqui(test.staff('luis'), '5284') ->> 'error', 'no_account', '4 nor starts a work session');
reset role;
select test.eq((select count(*)::int from public.purchase_orders) || ' ' || (select count(*) from public.purchase_receipts) || ' ' || (select count(*) from public.stock_moves),
               '3 1 1', '4 reads change nothing');

select test.done();
rollback;
