-- Migrations 0039/0040 (Proveedores, D-067): money in our favour with a supplier is owner level. A payment against an
-- open order may be made by a manager up to the order's estimate (IVA allowance included); shrinking that order
-- afterwards (cancel, lower a line, close what is pending, a negative correction) would turn the payment into a credit,
-- so a manager is refused (credit_needs_owner, with the amount) and nothing of the change is kept; the owner level does
-- it and the log says how much credit it left. Measured at supplier level: a cancelled prepaid order whose payment
-- another open invoice absorbs is not refused (514, case 8). Each case has its own supplier.
begin;
insert into public.stock_items (id, name, unit, pack_qty, cost_per_pack) values ('5a000000-0000-4000-8000-000000051701', 'Leche', 'unit', 1, 1000);
insert into public.vendors (id, name) select ('5b000000-0000-4000-8000-00000005170' || k)::uuid, 'Proveedor 517-' || k from generate_series(1, 5) k;
insert into public.vendor_items (id, vendor_id, item_id, pack_label, pack_qty, usual_price)
  select ('5c000000-0000-4000-8000-00000005170' || k)::uuid, ('5b000000-0000-4000-8000-00000005170' || k)::uuid, '5a000000-0000-4000-8000-000000051701', 'caja de 12', 12, 12000
    from generate_series(1, 5) k;
create function test.v517(o text) returns int language sql security definer as $$ select version from public.purchase_orders where id = o::uuid $$;
create function test.line517(o text) returns text language sql security definer as $$ select id::text from public.purchase_lines where po_id = o::uuid order by pos limit 1 $$;
create function test.st517(p text) returns text language sql security definer as $$
  select x.status || ' ' || (select string_agg(l.packs::text || '@' || coalesce(l.unit_cost, l.ordered_unit_cost)::text, ',' order by l.pos) from public.purchase_lines l
                             where l.po_id = x.id and l.removed_at is null) from public.purchase_orders x where x.id = p::uuid $$;
create function test.vendor517(k int) returns uuid language sql as $$ select ('5b000000-0000-4000-8000-00000005170' || k)::uuid $$;
-- an order to supplier k: n boxes at a typed price per box
create function test.order517(k int, o text, n int, price numeric) returns jsonb language sql as $$
  select public.proveedor_pedido_crear(test.vendor517(k),
           jsonb_build_array(jsonb_build_object('vendor_item_id', '5c000000-0000-4000-8000-00000005170' || k, 'packs', n, 'pack_price', price)), null, o::uuid) $$;
create function test.pay517(k int, o text, amount numeric, ref text, id text) returns jsonb language sql as $$
  select public.proveedor_pago_registrar(jsonb_build_object('vendor_id', test.vendor517(k), 'po_id', o, 'amount', amount, 'method', 'sinpe', 'reference', ref),
                                         id::uuid, test.staff('ana'), '4826') $$;
create function test.x517(k int) returns numeric language sql security definer as $$ select public._prov_excess(test.vendor517(k)) $$;

select test.login('cafe'); select test.session('dev-517'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
-- 1) cancel: an order typed at ₡1 000 000 a box, paid, then cancelled ---------------------------------------------------------
select test.eq(test.order517(1, '9a000000-0000-4000-8000-000000051701', 10, 1000000) ->> 'ok', 'true', '1 (Ana orders 10 boxes typed at ₡1 000 000)');
select test.eq(test.pay517(1, '9a000000-0000-4000-8000-000000051701', 11000000, 'SINPE-517-01', '5d000000-0000-4000-8000-000000051701') ->> 'ok', 'true',
               '1 a payment up to the order''s estimate is a manager''s');
select test.eq(public.proveedor_pedido_cancelar('9a000000-0000-4000-8000-000000051701', test.v517('9a000000-0000-4000-8000-000000051701'), 'Ya no hace falta'),
               '{"ok":false,"error":"credit_needs_owner","credit_crc":11000000.00}'::jsonb, '1 cancelling it would leave ₡11 000 000 in our favour: refused for a manager');
reset role;
select test.eq(test.st517('9a000000-0000-4000-8000-000000051701'), 'sent 10@83333.333333', '1 the order stays as it was');
select test.eq((select count(*)::int from public.audit_log where action = 'po_cancel'), 0, '1 nothing logged');
-- the owner level (an owner-role unlock) does it, and the log says the credit it left
select test.login('cafe'); select test.session('dev-517-o'); select test.unlock(test.staff('dueno'), '7391'); set role authenticated;
select test.eq(public.proveedor_pedido_cancelar('9a000000-0000-4000-8000-000000051701', test.v517('9a000000-0000-4000-8000-000000051701'), 'Ya no hace falta') ->> 'status',
               'cancelled', '1 the owner level cancels it');
reset role;
select test.eq((select (details ->> 'credit_crc') from public.audit_log where action = 'po_cancel'), '11000000.00', '1 the log keeps the credit it left');
select test.eq((public._prov_vendor_money(test.vendor517(1))) ->> 'credit_crc', '11000000.00', '1 the supplier shows it in our favour');

-- 2) edit: paid, then lowered to 1 box at the catalog price -------------------------------------------------------------------
select test.login('cafe'); select test.session('dev-517'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select test.eq(test.order517(2, '9a000000-0000-4000-8000-000000051702', 10, 1000000) ->> 'ok', 'true', '2 (10 boxes at ₡1 000 000 to another supplier)');
select test.eq(test.pay517(2, '9a000000-0000-4000-8000-000000051702', 11000000, 'SINPE-517-02', '5d000000-0000-4000-8000-000000051702') ->> 'ok', 'true', '2 (paid)');
select test.eq(public.proveedor_pedido_editar('9a000000-0000-4000-8000-000000051702', test.v517('9a000000-0000-4000-8000-000000051702'),
                 jsonb_build_array(jsonb_build_object('line_id', test.line517('9a000000-0000-4000-8000-000000051702'), 'packs', 1, 'pack_price', 12000))) ->> 'error',
               'credit_needs_owner', '2 lowering the line under what was paid: refused for a manager');
select test.eq(public.proveedor_pedido_editar('9a000000-0000-4000-8000-000000051702', test.v517('9a000000-0000-4000-8000-000000051702'), null, 'Entregar antes de las 9') ->> 'ok',
               'true', '2 a note needs no owner');
reset role;
select test.eq(test.st517('9a000000-0000-4000-8000-000000051702'), 'sent 10@83333.333333', '2 the lines stay as they were');
set role authenticated;
select test.eq(public.proveedor_pedido_editar('9a000000-0000-4000-8000-000000051702', test.v517('9a000000-0000-4000-8000-000000051702'),
                 jsonb_build_array(jsonb_build_object('line_id', test.line517('9a000000-0000-4000-8000-000000051702'), 'packs', 11, 'pack_price', 1000000))) ->> 'ok',
               'true', '2 raising the order needs no owner (nothing goes in our favour)');

-- 3) close what is pending: a normal order paid in full, one box arrives, the rest is closed ---------------------------------
select test.eq(test.order517(3, '9a000000-0000-4000-8000-000000051703', 10, 12000) ->> 'ok', 'true', '3 (10 boxes at ₡12 000)');
select test.eq(test.pay517(3, '9a000000-0000-4000-8000-000000051703', 135600, 'SINPE-517-03', '5d000000-0000-4000-8000-000000051703') ->> 'ok', 'true',
               '3 (paid ₡135 600 with IVA, before the goods)');
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051703', '7e000000-0000-4000-8000-000000051703', test.v517('9a000000-0000-4000-8000-000000051703'),
                 jsonb_build_array(jsonb_build_object('line_id', test.line517('9a000000-0000-4000-8000-000000051703'), 'packs', 1))) ->> 'status',
               'partially_received', '3 one box arrives');
reset role;
select test.eq(test.x517(3), 0.00, '3 (nothing in our favour yet: the nine boxes pending absorb the payment)');
set role authenticated;
select test.eq(public.proveedor_pedido_cerrar('9a000000-0000-4000-8000-000000051703', test.v517('9a000000-0000-4000-8000-000000051703'), 'El resto no viene') ->> 'error',
               'credit_needs_owner', '3 closing the rest would leave the prepaid nine boxes in our favour: refused for a manager');
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051703', '7e000000-0000-4000-8000-000000051704', test.v517('9a000000-0000-4000-8000-000000051703'),
                 jsonb_build_array(jsonb_build_object('line_id', test.line517('9a000000-0000-4000-8000-000000051703'), 'packs', 1)), null, true) ->> 'error',
               'credit_needs_owner', '3 the same when a delivery is received with «close what is pending»');
reset role;
select test.eq(test.st517('9a000000-0000-4000-8000-000000051703') || ' ' || (select count(*) from public.purchase_receipts where po_id = '9a000000-0000-4000-8000-000000051703'),
               'partially_received 10@1000.000000 1', '3 still open, the refused delivery not kept');
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.proveedor_pedido_cerrar('9a000000-0000-4000-8000-000000051703', test.v517('9a000000-0000-4000-8000-000000051703'), 'El resto no viene') ->> 'status',
               'received', '3 the owner with the phone code closes it');
reset role;
select test.eq((select details ->> 'credit_crc' from public.audit_log where action = 'po_close' and target_id = '9a000000-0000-4000-8000-000000051703'), '122040.00',
               '3 the log keeps the credit it left (₡135 600 − one box with IVA)');

-- 4) a negative correction: on an open line the box is pending again (nothing in our favour yet); on an order already
--    closed it stays closed, so the paid box would become a credit: owner level -----------------------------------------
select test.login('cafe'); select test.session('dev-517'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select test.eq(test.order517(4, '9a000000-0000-4000-8000-000000051704', 2, 12000) ->> 'ok', 'true', '4 (2 boxes at ₡12 000)');
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051704', '7e000000-0000-4000-8000-000000051705', test.v517('9a000000-0000-4000-8000-000000051704'),
                 jsonb_build_array(jsonb_build_object('line_id', test.line517('9a000000-0000-4000-8000-000000051704'), 'rest', true))) ->> 'status', 'received', '4 (both arrive)');
select test.eq(test.pay517(4, '9a000000-0000-4000-8000-000000051704', 27120, 'SINPE-517-04', '5d000000-0000-4000-8000-000000051704') ->> 'ok', 'true', '4 (paid in full with IVA)');
select test.eq(public.proveedor_recepcion_corregir('7e000000-0000-4000-8000-000000051705', '7e000000-0000-4000-8000-000000051706',
                 jsonb_build_array(jsonb_build_object('line_id', test.line517('9a000000-0000-4000-8000-000000051704'), 'packs_delta', -1)), 'Una caja venía vacía') ->> 'status',
               'partially_received', '4 a box taken back from a complete delivery is pending again: a manager''s');
reset role;
select test.eq(test.x517(4), 0.00, '4 nothing in our favour (the box may still come)');
select test.login('cafe'); select test.session('dev-517'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select test.eq(test.order517(4, '9a000000-0000-4000-8000-000000051706', 2, 12000) ->> 'ok', 'true', '4 (another order of 2 boxes)');
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051706', '7e000000-0000-4000-8000-000000051707', test.v517('9a000000-0000-4000-8000-000000051706'),
                 jsonb_build_array(jsonb_build_object('line_id', test.line517('9a000000-0000-4000-8000-000000051706'), 'packs', 1)), null, true) ->> 'status',
               'received', '4 one box arrives and the rest is closed (unpaid: a manager''s)');
reset role;
select test.eq(test.x517(4), 0.00, '4 (still nothing in our favour)');
set role authenticated;
select test.eq(public.proveedor_recepcion_corregir('7e000000-0000-4000-8000-000000051707', '7e000000-0000-4000-8000-000000051708',
                 jsonb_build_array(jsonb_build_object('line_id', test.line517('9a000000-0000-4000-8000-000000051706'), 'packs_delta', -1)), 'La caja venía vacía') ->> 'status',
               'received', '4 (that box taken back too: the closed order stays closed, the first order''s pending box absorbs the payment)');
select test.eq(public.proveedor_recepcion_corregir('7e000000-0000-4000-8000-000000051705', '7e000000-0000-4000-8000-000000051709',
                 jsonb_build_array(jsonb_build_object('line_id', test.line517('9a000000-0000-4000-8000-000000051704'), 'packs_delta', -1)), 'Otra caja vacía') ->> 'status',
               'partially_received', '4 (the first order: a second box pending again)');
select test.eq(public.proveedor_pedido_cerrar('9a000000-0000-4000-8000-000000051704', test.v517('9a000000-0000-4000-8000-000000051704'), 'No las reponen') ->> 'error',
               'credit_needs_owner', '4 closing what the corrections made pending would leave the paid boxes in our favour: refused for a manager');
reset role;
select test.eq((select status from public.purchase_orders where id = '9a000000-0000-4000-8000-000000051704'), 'partially_received', '4 still open');
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.proveedor_pedido_cerrar('9a000000-0000-4000-8000-000000051704', test.v517('9a000000-0000-4000-8000-000000051704'), 'No las reponen') ->> 'status',
               'received', '4 the owner with the phone code closes it');
reset role;
select test.eq((select details ->> 'credit_crc' from public.audit_log where action = 'po_close' and target_id = '9a000000-0000-4000-8000-000000051704'), '27120.00',
               '4 the log keeps the credit (the two paid boxes with IVA)');

-- 5) what a manager still does freely ------------------------------------------------------------------------------------------
select test.login('cafe'); select test.session('dev-517'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select test.eq(test.order517(5, '9a000000-0000-4000-8000-000000051705', 3, 12000) ->> 'ok', 'true', '5 (an unpaid order)');
select test.eq(public.proveedor_pedido_cancelar('9a000000-0000-4000-8000-000000051705', test.v517('9a000000-0000-4000-8000-000000051705'), 'Duplicado') ->> 'status', 'cancelled',
               '5 cancelling an unpaid order needs no owner');
reset role;
select test.eq((select details ? 'credit_crc' from public.audit_log where action = 'po_cancel' and target_id = '9a000000-0000-4000-8000-000000051705'), false,
               '5 and logs no credit');
select test.eq((select count(*)::int from acct.entries e where (select coalesce(sum(l.debit), 0) - coalesce(sum(l.credit), 0) from acct.lines l where l.entry_id = e.id) <> 0), 0,
               '5 the ledger stays balanced');

select test.done();
rollback;
