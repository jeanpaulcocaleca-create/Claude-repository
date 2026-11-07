-- =====================================================================================================
-- Canopy OS · migración 0040 · Proveedores: lo que lee la página nueva, facturas, pagos por SINPE o tarjeta y
-- anticipos a proveedores
-- Pegar TODO en Supabase → SQL Editor → New query → Run. Requiere: 0039. Una sola transacción.
--
-- Qué hace (D-067)
--   * Lo que la página Proveedores lee: la lista, la ficha de cada proveedor, el pedido, lo que falta por recibir y el
--     historial; a quien está en turno solo lo que necesita para recibir (sin montos, sin contactos, sin SINPE).
--   * Facturas desde Proveedores (proveedor_factura_registrar, por supplier_invoice_save como siempre); los retiros de
--     caja que la página anterior hizo al recibir quedan documentados con su factura.
--   * Pagos por SINPE (número de confirmación obligatorio y único, de cualquier proveedor) o tarjeta, antes o después
--     de recibir y de la factura: primero a la cuenta 1160 «Anticipos a proveedores» (Dr 1160 / Cr Bancos o la
--     tarjeta) y luego aplicados a las facturas (Dr 2101 / Cr 1160) solo por estas funciones, nunca por un disparador.
--   * Estado de pago por pedido: Pendiente / Parcialmente pagado / Pagado.
-- Qué NO cambia: ninguna función, regla ni registro existente; la página de Inventario publicada sigue pagando como hoy.
--   La regla supplier_payments_paid_from_check acepta además 'advance' (los pagos aplicados).
-- Qué cambia para el personal: nada hasta que se publique proveedores.html.
-- Cuándo: fuera del horario de atención, justo después de la 0039.
-- Reversión: supabase/tools/reversion-0040.sql (quita las funciones nuevas; cuentas, mapeos, tablas y pagos quedan).
-- =====================================================================================================
select canopy.migration_begin(40, 'proveedores_pagos');
set local lock_timeout = '8s';

-- 1) account 1160 (already in the approved chart since 0013) and two mappings ---
do $$ begin
  if exists (select 1 from acct.accounts where code = '1160' and (name <> 'Anticipos a proveedores' or type <> 'asset')) then
    raise exception 'La cuenta 1160 ya existe con otro nombre o tipo: revisar el plan de cuentas antes de aplicar la 0040. No se cambió nada.'; end if;
  if exists (select 1 from acct.accounts where code = '1160' and not active) then
    raise exception 'La cuenta 1160 «Anticipos a proveedores» está inactiva: el contador debe activarla antes de aplicar la 0040. No se cambió nada.'; end if;
end $$;
insert into acct.accounts (code, name, type, cash, system) values ('1160', 'Anticipos a proveedores', 'asset', false, false) on conflict (code) do nothing;
insert into acct.mappings (key, account, label) values
  ('supplier_advance', '1160', 'Pago a proveedor antes de aplicarlo a su factura (Proveedores)'),
  ('from_advance', '1160', 'Factura pagada con un pago registrado en Proveedores')
on conflict (key) do nothing;
alter table public.supplier_payments drop constraint if exists supplier_payments_paid_from_check;
alter table public.supplier_payments add constraint supplier_payments_paid_from_check
  check (paid_from in ('cash', 'petty', 'bank', 'payout', 'card_debit', 'card_credit', 'advance'));

-- 2) money per order and per supplier (read only) ---
-- due = the invoices' share of this order + deliveries not invoiced + what is still to come; paid = this order's
-- payments applied to its invoices + the other payments of those invoices × share + what of its payments is not applied
-- yet + drawer payouts of its deliveries still without an invoice. Before an invoice exists the IVA is not known: the
-- payment ceiling and «saldo a favor» allow coalesce(vendors.default_iva_rate, 0.13) on that part (a tolerance)
create or replace function public._prov_dinero(p_po_id uuid) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare po public.purchase_orders; rids uuid[]; inv jsonb; ish numeric; a1 numeric; a2 numeric; unv numeric; est numeric := 0; a3 numeric; a4 numeric;
        due numeric; paid numeric; rate numeric; allow numeric; miss boolean; advs jsonb;
begin
  select * into po from public.purchase_orders where id = p_po_id;
  if po.id is null then return null; end if;
  select coalesce(array_agg(id), '{}'), coalesce(sum(total_crc) filter (where invoice_id is null), 0),
         coalesce(bool_or(invoice_id is null and total_crc <> 0), false), coalesce(sum(public._prov_payout_open(payout_id)) filter (where payout_id is not null), 0)
    into rids, unv, miss, a4 from public.purchase_receipts where po_id = po.id;
  with i as (select x.*, (select coalesce(sum(r.total_crc) filter (where r.po_id = po.id), 0) from public.purchase_receipts r where r.id = any(x.receipt_ids)) as mine,
                         (select coalesce(sum(r.total_crc), 0) from public.purchase_receipts r where r.id = any(x.receipt_ids)) as alls,
                         (select count(*) filter (where r.po_id = po.id) from public.purchase_receipts r where r.id = any(x.receipt_ids)) as nmine
               from public.supplier_invoices x where x.voided_at is null and x.receipt_ids && rids),
       s as (select i.*, case when i.alls <> 0 then i.mine / i.alls else i.nmine::numeric / greatest(cardinality(i.receipt_ids), 1) end as share,
                    (select coalesce(sum(a.amount_crc), 0) from public.supplier_payment_allocations a join public.supplier_payments p on p.id = a.payment_id
                       join public.supplier_advances v on v.id = p.advance_id where a.invoice_id = i.id and p.voided_at is null and v.po_id = po.id) as own,
                    (select coalesce(sum(a.amount_crc), 0) from public.supplier_payment_allocations a join public.supplier_payments p on p.id = a.payment_id
                       where a.invoice_id = i.id and p.voided_at is null) as allp from i)
  select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'number', s.number, 'date', s.date, 'total_crc', s.total_crc,
                                               'open_crc', public._invoice_open(s.id), 'share', round(s.share, 4), 'currency', s.currency,
                                               'fx_rate', s.fx_rate, 'total_fx', case when s.currency = 'USD' then s.net_fx + s.iva_fx end) order by s.date, s.id), '[]'),
         coalesce(sum(s.total_crc * s.share), 0), coalesce(sum(s.own), 0), coalesce(sum((s.allp - s.own) * s.share), 0)
    into inv, ish, a1, a2 from s;
  if po.status in ('draft', 'sent', 'partially_received') then
    select coalesce(sum(greatest(l.qty - coalesce(l.received_qty, 0), 0) * coalesce(l.unit_cost, l.ordered_unit_cost, 0)), 0) into est
      from public.purchase_lines l where l.po_id = po.id and l.removed_at is null;
  end if;
  select coalesce(sum(public._prov_unapplied(a.id)), 0),
         coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'date', a.date, 'amount_crc', a.amount_crc, 'method', a.method, 'reference', a.reference,
                                               'applied_crc', case when a.voided_at is null then a.amount_crc - public._prov_unapplied(a.id) else 0 end,
                                               'voided_at', a.voided_at) order by a.created_at, a.id), '[]')
    into a3, advs from public.supplier_advances a where a.po_id = po.id;
  select coalesce(default_iva_rate, 0.13) into rate from public.vendors where id = po.vendor_id;
  rate := coalesce(rate, 0.13);
  due := ish + unv + est; paid := a1 + a2 + a3 + a4; allow := (unv + est) * rate;
  return jsonb_build_object('due', round(due, 2), 'paid', round(paid, 2),
    'status', case when due <= 0.5 and paid <= 0.5 then 'none' when paid <= 0.5 then 'pending' when paid >= due - 1 then 'paid' else 'partial' end,
    'invoice_missing', miss, 'estimate', round(est, 2), 'credit', round(greatest(paid - due - allow, 0), 2), 'payout_crc', round(a4, 2),
    'due_iva', round(due + allow, 2), 'saldo', round(greatest(due + allow - paid, 0), 2), 'invoices', inv, 'advances', advs);
end $$;
-- a supplier: owed (open invoices + deliveries not invoiced − undocumented drawer payouts − payments not applied yet)
create or replace function public._prov_vendor_money(p_vendor_id uuid) returns jsonb language sql stable security definer set search_path = public as $$
  with m as (select
     (select coalesce(sum(public._invoice_open(i.id)), 0) from public.supplier_invoices i where i.vendor_id = p_vendor_id and i.voided_at is null) as inv,
     (select coalesce(sum(r.total_crc), 0) from public.purchase_receipts r where r.vendor_id = p_vendor_id and r.invoice_id is null) as unv,
     (select coalesce(sum(public._prov_payout_open(r.payout_id)), 0) from public.purchase_receipts r where r.vendor_id = p_vendor_id and r.payout_id is not null) as pay,
     (select coalesce(sum(public._prov_unapplied(a.id)), 0) from public.supplier_advances a where a.vendor_id = p_vendor_id and a.voided_at is null) as adv,
     (select count(*) from public.supplier_advances a where a.vendor_id = p_vendor_id and a.voided_at is null and a.created_at < now() - interval '30 days'
         and public._prov_unapplied(a.id) > 0) as stale,
     (select coalesce(sum(greatest(l.qty - coalesce(l.received_qty, 0), 0) * coalesce(l.unit_cost, l.ordered_unit_cost, 0)), 0)
        from public.purchase_lines l join public.purchase_orders o on o.id = l.po_id
       where o.vendor_id = p_vendor_id and o.status in ('draft', 'sent', 'partially_received') and l.removed_at is null) as est,
     (select coalesce(v.default_iva_rate, 0.13) from public.vendors v where v.id = p_vendor_id) as rate)
  select jsonb_build_object('owed_crc', round(greatest(inv + unv - pay - adv, 0), 2), 'credit_crc', round(greatest(adv + pay - inv - unv, 0), 2),
                            'unapplied_crc', round(adv, 2), 'stale_advances', stale,
                            'saldo', round(greatest(inv + (unv + est) * (1 + coalesce(rate, 0.13)) - adv - pay, 0), 2))
    from m $$;
-- an order in a list: the «por recibir» shape (p_full false) or the supplier file's (with its money)
create or replace function public._prov_po_brief(p_id uuid, p_full boolean) returns jsonb language sql stable security definer set search_path = public as $$
  select case when not p_full then
           jsonb_build_object('id', o.id, 'po_number', o.po_number, 'vendor_id', o.vendor_id, 'vendor_name', v.name, 'status', o.status, 'sent_at', o.sent_at,
                              'expected_on', o.expected_on, 'lines', c.n, 'pending_lines', c.p)
         else jsonb_build_object('id', o.id, 'po_number', o.po_number, 'status', o.status, 'created_at', o.created_at, 'sent_at', o.sent_at,
                              'received_at', o.received_at, 'expected_on', o.expected_on, 'lines', c.n, 'pending_lines', c.p, 'est_total', c.est,
                              'received_total', (select coalesce(sum(r.total_crc), 0) from public.purchase_receipts r where r.po_id = o.id),
                              'close_requested', o.status = 'partially_received' and exists (select 1 from public.purchase_receipts r where r.po_id = o.id and r.close_requested),
                              'money', (select jsonb_build_object('due', m->'due', 'paid', m->'paid', 'status', m->'status', 'invoice_missing', m->'invoice_missing',
                                                                  'estimate', m->'estimate') from public._prov_dinero(o.id) m)) end
    from public.purchase_orders o left join public.vendors v on v.id = o.vendor_id
   cross join lateral (select count(*) filter (where l.removed_at is null) as n,
                              count(*) filter (where l.removed_at is null and coalesce(l.received_qty, 0) < l.qty) as p,
                              round(coalesce(sum(l.qty * coalesce(l.unit_cost, l.ordered_unit_cost, 0)) filter (where l.removed_at is null), 0), 2) as est
                         from public.purchase_lines l where l.po_id = o.id) c
   where o.id = p_id $$;

-- 3) reads: a valid p_token → what the employee on shift may see; else management (or the books' door); else locked ---
-- the mode of a read: 'receive' (with the session), 'manage', or the refusal
create or replace function public._prov_mode(p_token text, out mode text, out sid uuid, out sname text, out err jsonb)
language plpgsql volatile security definer set search_path = public, extensions as $$
declare t record;
begin
  select * into t from public._prov_turno(p_token);
  if p_token is not null and t.why is null then mode := 'receive'; sid := t.sid; sname := t.sname; return; end if;
  if public._prov_books() then mode := 'manage'; return; end if;
  err := case when p_token is not null then jsonb_build_object('ok', false, 'error', 'no_session', 'why', t.why) else '{"ok":false,"error":"locked"}'::jsonb end;
end $$;
create or replace function public._prov_can() returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object('can_manage', public._prov_manage(), 'can_pay', public._prov_books(), 'can_owner', public.is_true_owner() or acct.can_read()) $$;

create or replace function public.proveedores_lista(p_token text default null, p_inactivos boolean default false)
returns jsonb language plpgsql volatile security definer set search_path = public, extensions as $$
declare m record;
begin
  select * into m from public._prov_mode(p_token);
  if m.err is not null then return m.err; end if;
  if m.mode = 'receive' then
    return jsonb_build_object('ok', true, 'mode', 'receive', 'staff', jsonb_build_object('id', m.sid, 'name', m.sname),
      'vendors', (select coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'name', v.name, 'to_receive', c.n) order by v.name, v.id), '[]')
                    from public.vendors v cross join lateral (select count(*) as n from public.purchase_orders o where o.vendor_id = v.id
                                                                and o.status in ('sent', 'partially_received')) c where c.n > 0));
  end if;
  return jsonb_build_object('ok', true, 'mode', 'manage') || public._prov_can() || jsonb_build_object(
    'vendors', (select coalesce(jsonb_agg(jsonb_build_object('id', v.id, 'name', v.name, 'contact_name', v.contact_name, 'phone', v.phone,
                  'whatsapp', v.whatsapp, 'email', v.email, 'notes', v.notes, 'active', v.active, 'lead_days', v.lead_days, 'order_days', v.order_days,
                  'credit_days', v.credit_days,
                  'products', (select count(*) from public.vendor_items z where z.vendor_id = v.id and z.active),
                  'to_receive', (select count(*) from public.purchase_orders o where o.vendor_id = v.id and o.status in ('sent', 'partially_received')),
                  'partial', (select count(*) from public.purchase_orders o where o.vendor_id = v.id and o.status = 'partially_received'),
                  'drafts', (select count(*) from public.purchase_drafts d where d.vendor_id = v.id and d.status = 'open'),
                  'last_order_at', (select max(o.created_at) from public.purchase_orders o where o.vendor_id = v.id and o.status <> 'cancelled'),
                  'owed_crc', mm->'owed_crc', 'credit_crc', mm->'credit_crc', 'stale_advances', mm->'stale_advances') order by v.name, v.id), '[]')
                  from public.vendors v cross join lateral public._prov_vendor_money(v.id) mm where v.active or coalesce(p_inactivos, false)),
    'alerts', case when public._prov_manage() then public.proveedores_alertas()->'items' else '[]'::jsonb end,
    'no_vendor_orders', (select count(*) from public.purchase_orders o where o.vendor_id is null and o.status in ('sent', 'partially_received')));
end $$;

create or replace function public.proveedores_por_recibir(p_token text default null)
returns jsonb language plpgsql volatile security definer set search_path = public, extensions as $$
declare m record;
begin
  select * into m from public._prov_mode(p_token);
  if m.err is not null then return m.err; end if;
  return jsonb_build_object('ok', true, 'orders', (select coalesce(jsonb_agg(public._prov_po_brief(o.id, false) order by o.created_at, o.id), '[]')
           from public.purchase_orders o where o.status in ('sent', 'partially_received') and (o.vendor_id is not null or m.mode = 'manage')));
end $$;

create or replace function public.proveedor_ficha(p_vendor_id uuid, p_token text default null)
returns jsonb language plpgsql volatile security definer set search_path = public, extensions as $$
declare m record; v public.vendors; pi public.vendor_pay_info; books boolean := acct.can_read(); d public.purchase_drafts; mm jsonb;
begin
  select * into m from public._prov_mode(p_token);
  if m.err is not null then return m.err; end if;
  select * into v from public.vendors where id = p_vendor_id;
  if v.id is null then return '{"ok":false,"error":"not_found"}'::jsonb; end if;
  if m.mode = 'receive' then
    return jsonb_build_object('ok', true, 'mode', 'receive', 'vendor', jsonb_build_object('id', v.id, 'name', v.name),
      'orders', (select coalesce(jsonb_agg(public._prov_po_brief(o.id, false) order by o.created_at, o.id), '[]') from public.purchase_orders o
                  where o.vendor_id = v.id and o.status in ('sent', 'partially_received')));
  end if;
  select * into pi from public.vendor_pay_info where vendor_id = v.id;
  select * into d from public.purchase_drafts where vendor_id = v.id and status = 'open';
  mm := public._prov_vendor_money(v.id);
  return jsonb_build_object('ok', true, 'mode', 'manage') || public._prov_can() || jsonb_build_object(
    'vendor', jsonb_build_object('id', v.id, 'name', v.name, 'contact_name', v.contact_name, 'phone', v.phone, 'whatsapp', v.whatsapp, 'email', v.email,
                'notes', v.notes, 'lead_days', v.lead_days, 'order_days', v.order_days, 'credit_days', v.credit_days, 'active', v.active, 'sinpe', pi.sinpe,
                'sinpe_changed_at', case when pi.updated_at > now() - interval '30 days' then pi.updated_at end,
                'sinpe_changed_by', case when pi.updated_at > now() - interval '30 days' then pi.updated_by end)
              || case when books then jsonb_build_object('payment_notes', v.payment_notes) else '{}'::jsonb end,
    'products', (select coalesce(jsonb_agg(jsonb_build_object('id', vi.id, 'item_id', i.id, 'item_name', i.name, 'label', vi.label, 'vendor_code', vi.vendor_code,
                    'pack_label', vi.pack_label, 'pack_qty', vi.pack_qty, 'unit', i.unit, 'usual_price', vi.usual_price, 'usual_qty', vi.usual_qty,
                    'active', vi.active, 'preferred', i.vendor_id is not distinct from vi.vendor_id,
                    'preferred_vendor_name', case when i.vendor_id <> vi.vendor_id then pv.name end, 'item_active', i.active, 'on_hand', i.on_hand,
                    'reorder_point', i.reorder_point, 'par_level', i.par_level,
                    'stock_status', case when i.on_hand <= 0 then 'out' when i.on_hand <= i.reorder_point then 'low' else 'ok' end,
                    'times_ordered', h.n, 'last_packs', h.last_packs, 'last_ordered_at', h.last_at, 'last_pack_price', h.last_price, 'on_order', oo.q)
                  order by i.name, vi.pack_qty, vi.id), '[]')
       from public.vendor_items vi join public.stock_items i on i.id = vi.item_id left join public.vendors pv on pv.id = i.vendor_id
       cross join lateral (
         select count(distinct o.id) filter (where o.created_at > now() - interval '120 days') as n, max(o.created_at) as last_at,
                (array_agg(l.packs order by o.created_at desc, l.id))[1] as last_packs,
                (select x.pack_price from public.purchase_receipt_lines x join public.purchase_receipts r on r.id = x.receipt_id
                  where x.line_id = any(array_agg(l.id)) and x.qty > 0 and coalesce(r.origin, '') <> 'correccion' order by r.received_at desc limit 1) as last_price
           from public.purchase_lines l join public.purchase_orders o on o.id = l.po_id join public.stock_items li on li.id = l.item_id
          where o.vendor_id = vi.vendor_id and o.status <> 'cancelled' and l.removed_at is null and l.item_id = vi.item_id
            and coalesce(l.vendor_item_id, public._prov_vi_match(o.vendor_id, l.item_id, public._prov_pqe(l.pack_qty, l.packs, l.qty, li.pack_qty))) = vi.id
            and public._prov_pqe(l.pack_qty, l.packs, l.qty, li.pack_qty) = vi.pack_qty) h
       cross join lateral (select coalesce(sum(greatest(l.qty - coalesce(l.received_qty, 0), 0)), 0) as q from public.purchase_lines l
                            join public.purchase_orders o on o.id = l.po_id where l.item_id = i.id and l.removed_at is null
                             and o.status in ('sent', 'partially_received')) oo
      where vi.vendor_id = v.id),
    'draft', public._prov_draft_json(d),
    'orders', (select coalesce(jsonb_agg(public._prov_po_brief(q.id, true) order by q.k, q.created_at desc, q.id), '[]') from (
                 (select o.id, 0 as k, o.created_at from public.purchase_orders o where o.vendor_id = v.id and o.status in ('draft', 'sent', 'partially_received'))
                 union all
                 (select o.id, 1, o.created_at from public.purchase_orders o where o.vendor_id = v.id and o.status in ('received', 'cancelled')
                   order by o.created_at desc, o.id limit 30)) q),
    'money', jsonb_build_object('owed_crc', mm->'owed_crc', 'credit_crc', mm->'credit_crc', 'unapplied_crc', mm->'unapplied_crc', 'saldo', mm->'saldo',
      'stale_advances', mm->'stale_advances',
      'open_invoices', (select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'number', i.number, 'date', i.date, 'due_date', i.due_date,
                           'total_crc', i.total_crc, 'open_crc', public._invoice_open(i.id)) order by i.date, i.id), '[]')
                          from public.supplier_invoices i where i.vendor_id = v.id and i.voided_at is null and public._invoice_open(i.id) > 0),
      'uninvoiced', (select coalesce(jsonb_agg(jsonb_build_object('receipt_id', r.id, 'po_id', r.po_id, 'po_number', o.po_number, 'received_at', r.received_at,
                        'total_crc', r.total_crc, 'invoice_no', r.invoice_no, 'invoice_status', r.invoice_status, 'invoice_draft', r.invoice_draft,
                        'payout_crc', case when r.payout_id is not null then public._prov_payout_open(r.payout_id) else 0 end, 'origin', r.origin)
                        order by r.received_at, r.id), '[]')
                       from public.purchase_receipts r join public.purchase_orders o on o.id = r.po_id where r.vendor_id = v.id and r.invoice_id is null),
      'advances', (select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'date', a.date, 'amount_crc', a.amount_crc, 'method', a.method,
                      'reference', a.reference, 'po_id', a.po_id, 'po_number', o.po_number,
                      'applied_crc', case when a.voided_at is null then a.amount_crc - public._prov_unapplied(a.id) else 0 end, 'voided_at', a.voided_at)
                      order by a.created_at desc, a.id), '[]')
                     from public.supplier_advances a left join public.purchase_orders o on o.id = a.po_id where a.vendor_id = v.id),
      'other_payments', (select coalesce(jsonb_agg(jsonb_build_object('id', q.id, 'date', q.date, 'amount_crc', q.amount_crc, 'paid_from', q.paid_from,
                            'reference', q.reference, 'voided_at', q.voided_at) order by q.date desc, q.created_at desc), '[]')
                           from (select p.* from public.supplier_payments p where p.vendor_id = v.id and p.paid_from <> 'advance'
                                  order by p.date desc, p.created_at desc limit 50) q)));
end $$;

create or replace function public.proveedor_pedido(p_po_id uuid, p_token text default null)
returns jsonb language plpgsql volatile security definer set search_path = public, extensions as $$
declare m record; po public.purchase_orders; v public.vendors; rids text[];
begin
  select * into m from public._prov_mode(p_token);
  if m.err is not null then return m.err; end if;
  select * into po from public.purchase_orders where id = p_po_id;
  if po.id is null or (m.mode = 'receive' and (po.status not in ('sent', 'partially_received') or po.vendor_id is null)) then
    return '{"ok":false,"error":"not_found"}'::jsonb; end if;
  select * into v from public.vendors where id = po.vendor_id;
  if m.mode = 'receive' then
    return jsonb_build_object('ok', true, 'mode', 'receive',
      'order', jsonb_build_object('id', po.id, 'po_number', po.po_number, 'vendor_name', v.name, 'status', po.status, 'sent_at', po.sent_at,
                                  'expected_on', po.expected_on, 'version', po.version),
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'pos', l.pos, 'item_name', l.item_name, 'label', l.label, 'vendor_code', l.vendor_code,
                   'pack_label', l.pack_label, 'pack_qty', l.pack_qty, 'unit', l.unit, 'packs', l.packs, 'received_packs', l.received_packs,
                   'pending_packs', l.pending_packs, 'expected_pack_price', l.expected_pack_price, 'removed', l.removed)
                   order by coalesce(l.pos, 1000000), l.item_name, l.id), '[]') from public._prov_lines(po.id) l),
      -- an owner who received without a PIN unlock is recorded as their login («owner login · email», as every module
      -- records it): the employee on shift reads «Dueño», never the email
      'receipts', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'received_at', r.received_at,
                      'by_name', case when r.by_name like 'owner login%' then 'Dueño' else r.by_name end,
                      'lines', (select coalesce(jsonb_agg(jsonb_build_object('line_id', x.line_id, 'packs', x.packs) order by x.line_id), '[]')
                                  from public.purchase_receipt_lines x where x.receipt_id = r.id))
                      order by r.received_at, r.id), '[]') from public.purchase_receipts r where r.po_id = po.id));
  end if;
  select coalesce(array_agg(r.id::text), '{}') into rids from public.purchase_receipts r where r.po_id = po.id;
  return jsonb_build_object('ok', true, 'mode', 'manage', 'can_manage', public._prov_manage(), 'can_pay', public._prov_books(),
    'order', jsonb_build_object('id', po.id, 'po_number', po.po_number, 'vendor_id', po.vendor_id, 'vendor_name', v.name, 'vendor_phone', v.phone,
               'vendor_email', v.email, 'vendor_contact', v.contact_name, 'status', po.status, 'created_at', po.created_at, 'sent_at', po.sent_at,
               'received_at', po.received_at, 'expected_on', po.expected_on, 'note', po.note, 'by_name', po.by_name, 'version', po.version,
               'close_requested', po.status = 'partially_received' and exists (select 1 from public.purchase_receipts r where r.po_id = po.id and r.close_requested)),
    'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'pos', l.pos, 'vendor_item_id', l.vendor_item_id, 'item_id', l.item_id,
                 'item_name', l.item_name, 'label', l.label, 'vendor_code', l.vendor_code, 'pack_label', l.pack_label, 'pack_qty', l.pack_qty, 'unit', l.unit,
                 'packs', l.packs, 'qty', l.qty, 'received_qty', l.received_qty, 'pending_qty', l.pending_qty, 'received_packs', l.received_packs,
                 'pending_packs', l.pending_packs, 'expected_pack_price', l.expected_pack_price, 'line_total_est', l.line_total_est,
                 'received_value', l.received_value, 'removed', l.removed) order by coalesce(l.pos, 1000000), l.item_name, l.id), '[]')
                from public._prov_lines(po.id) l),
    'totals', jsonb_build_object('estimated', (select coalesce(sum(l.line_total_est) filter (where not l.removed), 0) from public._prov_lines(po.id) l),
                                 'received_value', (select coalesce(round(sum(r.total_crc), 2), 0) from public.purchase_receipts r where r.po_id = po.id)),
    'receipts', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'received_at', r.received_at, 'by_name', r.by_name, 'note', r.note,
                    'invoice_no', r.invoice_no, 'invoice_status', r.invoice_status, 'total_crc', r.total_crc, 'final', r.final, 'origin', r.origin,
                    'corrects', r.corrects, 'close_requested', r.close_requested,
                    'lines', (select coalesce(jsonb_agg(z.j order by z.k), '[]') from (
                       select jsonb_build_object('line_id', x.line_id, 'item_name', i.name, 'packs', x.packs, 'qty', x.qty, 'pack_price', x.pack_price,
                                'expected_pack_price', x.expected_pack_price, 'observed_pack_price', x.observed_pack_price,
                                'extra_reported_packs', x.extra_reported_packs) as j, i.name || x.line_id::text as k
                         from public.purchase_receipt_lines x join public.stock_items i on i.id = x.item_id where x.receipt_id = r.id
                       union all   -- deliveries of the old page the copy could not tie to one line: their stock moves
                       select jsonb_build_object('line_id', null, 'item_name', i.name, 'packs', null, 'qty', mv.qty, 'pack_price', null,
                                'unit_cost', mv.unit_cost), i.name || mv.id::text
                         from public.stock_moves mv join public.stock_items i on i.id = mv.item_id
                        where mv.receipt_id = r.id and mv.kind = 'purchase'
                          and not exists (select 1 from public.purchase_receipt_lines x where x.receipt_id = r.id and x.item_id = mv.item_id)) z))
                    order by r.received_at, r.id), '[]') from public.purchase_receipts r where r.po_id = po.id),
    'money', public._prov_dinero(po.id),
    'history', (select coalesce(jsonb_agg(jsonb_build_object('at', a.at, 'action', a.action, 'by', a.manager_name, 'summary', a.summary) order by a.at, a.id), '[]')
                  from (select * from public.audit_log a where a.target_id = po.id::text or a.target_id = any(rids) order by a.at desc, a.id desc limit 100) a));
end $$;

create or replace function public.proveedor_historial(p_vendor_id uuid, p_before timestamptz default null, p_limit int default 50)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not public._prov_books() then return '{"ok":false,"error":"locked"}'::jsonb; end if;
  if p_limit is null or p_limit < 1 or p_limit > 100 then return '{"ok":false,"error":"bad_request"}'::jsonb; end if;
  return jsonb_build_object('ok', true, 'orders', (select coalesce(jsonb_agg(public._prov_po_brief(q.id, true) order by q.created_at desc, q.id), '[]')
    from (select o.id, o.created_at from public.purchase_orders o where o.vendor_id = p_vendor_id and o.status in ('received', 'cancelled')
             and o.created_at < coalesce(p_before, 'infinity') order by o.created_at desc, o.id limit p_limit) q));
end $$;


-- 4) applying payments to invoices (internal; the caller holds the vendor's row) ---
create or replace function public._prov_date(p jsonb) returns date language plpgsql immutable set search_path = public as $$
begin
  if p is null or jsonb_typeof(p) = 'null' then return null; end if;
  if jsonb_typeof(p) <> 'string' or (p #>> '{}') !~ '^\d{4}-\d{2}-\d{2}$' then perform public._prov_fail('bad_date'); end if;
  return (p #>> '{}')::date;
exception when invalid_datetime_format or datetime_field_overflow then
  perform public._prov_fail('bad_date'); return null;
end $$;
-- the mirror image of an entry, dated today (acct_entry_reverse's own rule, for the gates of these functions)
create or replace function public._prov_reverse(p_entry bigint, p_memo text, p_by text) returns bigint
language plpgsql volatile security definer set search_path = acct, public as $$
declare e acct.entries; ls jsonb; eid bigint;
begin
  if p_entry is null then return null; end if;
  select id into eid from acct.entries where reverses = p_entry;
  if eid is not null then return eid; end if;
  select * into e from acct.entries where id = p_entry;
  select jsonb_agg(jsonb_build_object('account', account, 'debit', credit, 'credit', debit, 'memo', memo)) into ls from acct.lines where entry_id = e.id;
  return acct.post(public.cr_today(), 'Reversión del asiento ' || e.entry_no || ': ' || coalesce(nullif(btrim(p_memo), ''), e.memo),
                   'reversal', 'reverse:' || e.id, ls, e.id, p_by);
end $$;
-- a payment voided: its entry reversed, the row kept (its allocation is then ignored, as supplier_payment_void does)
create or replace function public._prov_void_payment(p_id uuid, p_reason text, p_by text) returns void
language plpgsql volatile security definer set search_path = public, acct as $$
declare x public.supplier_payments;
begin
  select * into x from public.supplier_payments where id = p_id for update;
  if x.id is null or x.voided_at is not null then return; end if;
  update public.supplier_payments set voided_at = now(), void_reason = left(p_reason, 200),
         void_entry_id = public._prov_reverse(x.entry_id, p_reason, p_by) where id = x.id;
end $$;
-- each live payment with something not applied, oldest first: (1) to the open invoices of its order, oldest first;
-- (2) it waits while that order is open or has deliveries without an invoice; (3) otherwise (or without an order) to
-- the supplier's other open invoices, oldest due first. Never again to an invoice where an application of it was voided.
-- Each application is a supplier_payments row (paid_from 'advance') + its allocation + Dr 2101 / Cr 1160. One that
-- cannot be posted (a closed month) is skipped
create or replace function public._prov_aplicar(p_vendor_id uuid) returns numeric
language plpgsql volatile security definer set search_path = public, acct as $$
declare a public.supplier_advances; v public.vendors; po public.purchase_orders; inv record; rest numeric; amt numeric; k int; pid uuid; eid bigint;
        hold boolean; total numeric := 0; who text := public._prov_actor();
begin
  select * into v from public.vendors where id = p_vendor_id;
  for a in select * from public.supplier_advances x where x.vendor_id = p_vendor_id and x.voided_at is null order by x.created_at, x.id loop
    rest := public._prov_unapplied(a.id);
    continue when rest <= 0;
    hold := false;
    if a.po_id is not null then
      select * into po from public.purchase_orders where id = a.po_id;
      hold := po.status in ('draft', 'sent', 'partially_received')
              or exists (select 1 from public.purchase_receipts r where r.po_id = a.po_id and r.invoice_id is null and r.total_crc <> 0);
    end if;
    for inv in select i.id, i.number, case when a.po_id is not null and exists (select 1 from public.purchase_receipts r where r.id = any(i.receipt_ids)
                                                                                  and r.po_id = a.po_id) then 0 else 1 end as grp
                 from public.supplier_invoices i
                where i.vendor_id = p_vendor_id and i.voided_at is null and public._invoice_open(i.id) > 0
                  and not exists (select 1 from public.supplier_payments p join public.supplier_payment_allocations x on x.payment_id = p.id
                                   where p.advance_id = a.id and x.invoice_id = i.id and p.voided_at is not null)
                order by 3, coalesce(i.due_date, i.date), i.date, i.created_at, i.id loop
      exit when rest <= 0 or (inv.grp = 1 and hold);
      amt := least(rest, public._invoice_open(inv.id));
      select count(*) into k from public.supplier_payments p join public.supplier_payment_allocations x on x.payment_id = p.id
       where p.advance_id = a.id and x.invoice_id = inv.id;
      pid := md5(a.id || ':' || inv.id || ':' || k)::uuid;
      begin
        eid := acct.post(public.cr_today(), 'Pago a ' || v.name || ' aplicado a la factura ' || inv.number, 'ap', 'suppay:' || pid,
                 jsonb_build_array(jsonb_build_object('account', acct.map('ap'), 'debit', amt, 'memo', v.name),
                                   jsonb_build_object('account', acct.map('from_advance'), 'credit', amt)), null, who);
        insert into public.supplier_payments (id, vendor_id, date, amount_crc, paid_from, reference, entry_id, created_by, method, advance_id, po_id)
          values (pid, p_vendor_id, public.cr_today(), amt, 'advance',
                  left(btrim(case a.method when 'sinpe' then 'SINPE ' else 'Tarjeta ' end || coalesce(a.reference, '')), 80), eid, who, a.method, a.id, a.po_id);
        insert into public.supplier_payment_allocations (payment_id, invoice_id, amount_crc) values (pid, inv.id, amt);
        rest := rest - amt; total := total + amt;
      exception when deadlock_detected or lock_not_available or query_canceled then raise;
        when others then null;
      end;
    end loop;
  end loop;
  return total;
end $$;

-- 5) invoices from Proveedores (the books' door or the owner areas) ---
create or replace function public.proveedor_factura_registrar(p_vendor_id uuid, p_receipt_ids uuid[], p_invoice jsonb, p_request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = public, acct, extensions as $$
declare vd public.vendors; i jsonb := p_invoice; rids uuid[]; num text; d date; due date; cur text; rate numeric; net numeric; iva numeric; nc numeric;
        ic numeric; tot numeric; pays numeric; res jsonb; eid bigint; rr record; k int := 0; applied numeric; who text := public._prov_actor();
        e1 text; e2 text; e3 text; e4 text; r jsonb;
begin
  if not public._prov_books() then return '{"ok":false,"error":"locked"}'::jsonb; end if;
  if p_request_id is null then return '{"ok":false,"error":"bad_request"}'::jsonb; end if;
  if exists (select 1 from public.supplier_invoices where id = p_request_id) then
    return jsonb_build_object('ok', true, 'repeat', true, 'invoice_id', p_request_id); end if;
  begin
    select * into vd from public.vendors where id = p_vendor_id;
    if vd.id is null then perform public._prov_fail('not_found'); end if;
    if jsonb_typeof(i) is distinct from 'object'
       or exists (select 1 from jsonb_object_keys(i) x where x not in ('number', 'date', 'due_date', 'currency', 'fx_rate', 'net', 'iva')) then
      perform public._prov_fail('bad_request'); end if;
    if coalesce(cardinality(p_receipt_ids), 0) not between 1 and 50
       or exists (select 1 from unnest(p_receipt_ids) x left join public.purchase_receipts pr on pr.id = x
                   where pr.id is null or pr.vendor_id is distinct from vd.id or pr.invoice_id is not null) then
      perform public._prov_fail('bad_receipts'); end if;
    -- the corrections of those orders still without an invoice go with them
    select array_agg(distinct pr.id order by pr.id) into rids from public.purchase_receipts pr
     where pr.id = any(p_receipt_ids) or (pr.origin = 'correccion' and pr.invoice_id is null and pr.vendor_id = vd.id
                                          and pr.po_id in (select z.po_id from public.purchase_receipts z where z.id = any(p_receipt_ids)));
    cur := coalesce(public._prov_txt(i->'currency', 3), 'CRC');
    if cur not in ('CRC', 'USD') then perform public._prov_fail('bad_request'); end if;
    d := public._prov_date(i->'date'); due := public._prov_date(i->'due_date');
    if d is null then perform public._prov_fail('bad_date'); end if;
    net := public._prov_num(i->'net'); iva := coalesce(public._prov_num(i->'iva'), 0);
    if net is null or net < 0 or iva < 0 or net + iva = 0 or net > 100000000 or iva > 100000000 then perform public._prov_fail('bad_amount'); end if;
    if cur = 'USD' then
      rate := public._prov_num(i->'fx_rate');
      if rate is null or rate < 100 or rate > 2000 then perform public._prov_fail('bad_rate'); end if;
      nc := round(net * rate, 2); ic := round(iva * rate, 2);
    else nc := round(net, 2); ic := round(iva, 2);
    end if;
    tot := nc + ic;
    num := public._prov_txt(i->'number', 50);
    if num is null then
      select min(pr.invoice_no) into num from public.purchase_receipts pr where pr.id = any(rids) and pr.invoice_no is not null
      having count(distinct lower(pr.invoice_no)) = 1;
      num := coalesce(num, 'S/N-' || to_char(d, 'YYYYMMDD') || '-' || left(replace(p_request_id::text, '-', ''), 8));
    end if;
    due := coalesce(due, d + coalesce(vd.credit_days, 30));
    -- money the old page took from the drawer for these deliveries is documented with this invoice
    select coalesce(sum(public._prov_payout_open(pr.payout_id)), 0) into pays from public.purchase_receipts pr where pr.id = any(rids) and pr.payout_id is not null;
    if pays > tot + 0.99 then perform public._prov_fail('payout_exceeds', jsonb_build_object('payout_crc', pays, 'total_crc', tot)); end if;
    res := public.supplier_invoice_save(jsonb_build_object('vendor_id', vd.id, 'number', num, 'date', d, 'due_date', due, 'net_crc', nc, 'iva_crc', ic,
                                                           'receipt_ids', to_jsonb(rids)), p_request_id);
    if not coalesce((res->>'ok')::boolean, false) then
      perform public._prov_fail(case res->>'error' when 'not_allowed' then 'locked' when 'bad_value' then 'bad_amount' when 'no_vendor' then 'not_found'
                                                   else coalesce(res->>'error', 'bad_request') end);
    end if;
    eid := (res->>'entry_id')::bigint;
    if cur = 'USD' then
      update public.supplier_invoices set currency = 'USD', fx_rate = rate, net_fx = round(net, 2), iva_fx = round(iva, 2) where id = p_request_id;
    end if;
    for rr in select pr.payout_id, o.po_number, public._prov_payout_open(pr.payout_id) as amt from public.purchase_receipts pr
                join public.purchase_orders o on o.id = pr.po_id where pr.id = any(rids) and pr.payout_id is not null order by pr.received_at, pr.id loop
      continue when rr.amt <= 0;
      res := public.supplier_payment_save(jsonb_build_object('vendor_id', vd.id, 'date', public.cr_today(), 'amount_crc', rr.amt, 'paid_from', 'payout',
               'payout_id', rr.payout_id, 'invoice_ids', jsonb_build_array(p_request_id), 'reference', 'Pedido Nº ' || rr.po_number || ' · retiro de caja'),
               public._settle_uuid(p_request_id, 'payout-doc', k));
      if not coalesce((res->>'ok')::boolean, false) then perform public._prov_fail(coalesce(res->>'error', 'bad_request')); end if;
      k := k + 1;
    end loop;
    -- the number on the deliveries that have none (unless this supplier already uses it on another delivery)
    for rr in select pr.id from public.purchase_receipts pr where pr.id = any(rids) and pr.invoice_no is null order by pr.received_at, pr.id loop
      update public.purchase_receipts pr set invoice_no = num where pr.id = rr.id
         and not exists (select 1 from public.purchase_receipts x where x.vendor_id = vd.id and lower(x.invoice_no) = lower(num));
    end loop;
    applied := public._prov_aplicar(vd.id);
    perform public._prov_log('po_invoice', null, who, p_request_id::text, 'Factura ' || num || ' · ' || vd.name || ' · ' || tot,
      jsonb_build_object('vendor_id', vd.id, 'receipt_ids', to_jsonb(rids), 'total_crc', tot, 'currency', cur, 'fx_rate', rate, 'payout_crc', pays,
                         'applied_crc', applied));
    return jsonb_build_object('ok', true, 'invoice_id', p_request_id, 'total_crc', tot, 'payout_crc', pays, 'entry_id', eid,
      'applied_crc', (select coalesce(sum(a.amount_crc), 0) from public.supplier_payment_allocations a join public.supplier_payments p on p.id = a.payment_id
                       where a.invoice_id = p_request_id and p.paid_from = 'advance' and p.voided_at is null),
      'open_crc', public._invoice_open(p_request_id));
  exception when others then
    get stacked diagnostics e1 = returned_sqlstate, e2 = message_text, e3 = pg_exception_detail, e4 = constraint_name;
    r := public._prov_caught(e1, e2, e3, e4); if r is null then raise; end if; return r;
  end;
end $$;
-- the books' door voids a Proveedores invoice: its applications first (the payments become unapplied, never again to it)
create or replace function public.proveedor_factura_anular(p_invoice_id uuid, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = public, acct, extensions as $$
declare x public.supplier_invoices; sp record; res jsonb; why text := nullif(btrim(coalesce(p_reason, '')), ''); who text; e1 text; e2 text; e3 text; e4 text; r jsonb;
begin
  if not acct.can_read() then return '{"ok":false,"error":"locked"}'::jsonb; end if;
  who := public._prov_actor();
  begin
    if why is null or char_length(why) < 5 then perform public._prov_fail('needs_reason'); end if;
    if char_length(why) > 200 then perform public._prov_fail('bad_request'); end if;
    select * into x from public.supplier_invoices where id = p_invoice_id;
    if x.id is null then perform public._prov_fail('not_found'); end if;
    perform 1 from public.vendors where id = x.vendor_id for update;
    select * into x from public.supplier_invoices where id = p_invoice_id;
    if x.voided_at is not null then return '{"ok":true,"repeat":true}'::jsonb; end if;
    for sp in select p.id from public.supplier_payments p join public.supplier_payment_allocations a on a.payment_id = p.id
               where a.invoice_id = x.id and p.paid_from = 'advance' and p.voided_at is null order by p.id loop
      perform public._prov_void_payment(sp.id, 'factura anulada: ' || why, who);
    end loop;
    res := public.supplier_invoice_void(x.id, why);
    if not coalesce((res->>'ok')::boolean, false) then
      perform public._prov_fail(case res->>'error' when 'not_allowed' then 'locked' when 'missing_reason' then 'needs_reason' else coalesce(res->>'error', 'bad_request') end);
    end if;
    perform public._prov_log('po_invoice_void', null, who, x.id::text, 'Factura ' || x.number || ' anulada: ' || why, jsonb_build_object('vendor_id', x.vendor_id));
    return '{"ok":true}'::jsonb;
  exception when others then
    get stacked diagnostics e1 = returned_sqlstate, e2 = message_text, e3 = pg_exception_detail, e4 = constraint_name;
    r := public._prov_caught(e1, e2, e3, e4); if r is null then raise; end if; return r;
  end;
end $$;
-- «Aplicar a facturas abiertas»: for invoices saved elsewhere (Contabilidad, the old page)
create or replace function public.proveedor_anticipos_aplicar(p_vendor_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = public, acct, extensions as $$
declare applied numeric; who text := public._prov_actor();
begin
  if not public._prov_books() then return '{"ok":false,"error":"locked"}'::jsonb; end if;
  perform 1 from public.vendors where id = p_vendor_id for update;
  if not found then return '{"ok":false,"error":"not_found"}'::jsonb; end if;
  applied := public._prov_aplicar(p_vendor_id);
  if applied > 0 then
    perform public._prov_log('supplier_advance_apply', null, who, p_vendor_id::text, 'Pagos aplicados a facturas abiertas: ' || applied,
      jsonb_build_object('vendor_id', p_vendor_id, 'applied_crc', applied));
  end if;
  return jsonb_build_object('ok', true, 'applied_crc', applied, 'money', public._prov_vendor_money(p_vendor_id));
end $$;

-- 6) payments: SINPE (confirmation number required, one transfer once) or card; with a PIN unless the owner with the
-- phone code or the accountant ---
create or replace function public.proveedor_pago_registrar(p_payment jsonb, p_request_id uuid, p_staff_id uuid default null, p_pin text default null)
returns jsonb language plpgsql volatile security definer set search_path = public, acct, extensions as $$
declare p jsonb := p_payment; free boolean := public.owner_with_code() or acct.can_read(); perr text; psid uuid; pname text; prole text; vid uuid;
        poid uuid; po public.purchase_orders; vd public.vendors; amt numeric; d date; meth text; ref text; rk text; xok boolean; xr text; dupok boolean;
        saldo numeric; dup record; eid bigint; who text := public._prov_actor(); applied numeric; e1 text; e2 text; e3 text; e4 text; r jsonb;
begin
  if not public._prov_books() then return '{"ok":false,"error":"locked"}'::jsonb; end if;
  if p_request_id is null or jsonb_typeof(p) is distinct from 'object' then return '{"ok":false,"error":"bad_request"}'::jsonb; end if;
  if exists (select 1 from public.supplier_advances where id = p_request_id) then return jsonb_build_object('ok', true, 'repeat', true, 'id', p_request_id); end if;
  if not free then
    select err, sid, sname into perr, psid, pname from public._verify_pin(p_staff_id, p_pin, true);   -- a wrong try stays counted
    if perr is not null then return jsonb_build_object('ok', false, 'error', case perr when 'locked' then 'pin_locked' else perr end); end if;
    select role into prole from public.staff where id = psid;
  end if;
  begin
    if exists (select 1 from jsonb_object_keys(p) x where x not in ('vendor_id', 'po_id', 'date', 'amount', 'method', 'reference', 'excess_ok',
                                                                   'excess_reason', 'duplicate_ok')) then perform public._prov_fail('bad_request'); end if;
    vid := public._prov_id(p->'vendor_id'); poid := public._prov_id(p->'po_id');
    if vid is null then perform public._prov_fail('bad_request'); end if;
    if poid is not null then
      select * into po from public.purchase_orders where id = poid for share;     -- the order before the vendor (as receiving)
      if po.id is null or po.vendor_id is distinct from vid then perform public._prov_fail('not_found'); end if;
    end if;
    select * into vd from public.vendors where id = vid for update;
    if vd.id is null then perform public._prov_fail('not_found'); end if;
    if exists (select 1 from public.supplier_advances where id = p_request_id) then return jsonb_build_object('ok', true, 'repeat', true, 'id', p_request_id); end if;
    amt := public._prov_num(p->'amount');
    if amt is null or amt <= 0 or amt > 100000000 or amt <> round(amt, 2) then perform public._prov_fail('bad_amount'); end if;
    d := coalesce(public._prov_date(p->'date'), public.cr_today());
    if d > public.cr_today() then perform public._prov_fail('future_date'); end if;
    if d < public.cr_today() - 366 then perform public._prov_fail('bad_date'); end if;
    meth := public._prov_txt(p->'method', 20);
    if meth is null or meth not in ('sinpe', 'card_debit', 'card_credit') then perform public._prov_fail('bad_request'); end if;
    ref := nullif(regexp_replace(coalesce(public._prov_txt(p->'reference', 200), ''), '\s+', ' ', 'g'), '');
    rk := nullif(regexp_replace(lower(coalesce(ref, '')), '[^a-z0-9]', '', 'g'), '');
    if meth = 'sinpe' then
      if ref is null then perform public._prov_fail('needs_reference'); end if;
      if char_length(ref) not between 4 and 40 or ref !~ '^[A-Za-z0-9][A-Za-z0-9 ./-]*$' or char_length(rk) < 4 then perform public._prov_fail('bad_reference'); end if;
    elsif char_length(ref) > 80 then perform public._prov_fail('bad_reference');
    end if;
    if poid is not null and po.status = 'cancelled' and not exists (select 1 from public.purchase_receipts x where x.po_id = poid) then
      perform public._prov_fail('cancelled'); end if;
    xok := coalesce(public._prov_bool(p->'excess_ok'), false); xr := public._prov_txt(p->'excess_reason', 200);
    dupok := coalesce(public._prov_bool(p->'duplicate_ok'), false);
    -- the same transfer twice (any supplier, any page), or the same card payment a moment ago
    if meth = 'sinpe' then
      select x.name as vendor_name, a.date, a.amount_crc as amount into dup from public.supplier_advances a join public.vendors x on x.id = a.vendor_id
       where a.method = 'sinpe' and a.voided_at is null and a.ref_key = rk limit 1;
      if dup.vendor_name is null then
        select x.name as vendor_name, s.date, s.amount_crc as amount into dup from public.supplier_payments s join public.vendors x on x.id = s.vendor_id
         where s.paid_from = 'bank' and s.voided_at is null and regexp_replace(lower(coalesce(s.reference, '')), '[^a-z0-9]', '', 'g') = rk limit 1;
      end if;
      if dup.vendor_name is null then
        select coalesce(x.name, e.vendor_name, e.description) as vendor_name, s.date, s.amount_crc as amount into dup
          from public.expense_payments s join public.expenses e on e.id = s.expense_id left join public.vendors x on x.id = e.vendor_id
         where s.paid_from = 'bank' and s.voided_at is null and regexp_replace(lower(coalesce(s.reference, '')), '[^a-z0-9]', '', 'g') = rk limit 1;
      end if;
      if dup.vendor_name is not null then perform public._prov_fail('duplicate_reference', to_jsonb(dup)); end if;
    elsif not dupok then
      select a.id, a.date, a.amount_crc, a.method, a.reference, a.created_by, a.created_at into dup from public.supplier_advances a
       where a.vendor_id = vid and a.po_id is not distinct from poid and a.amount_crc = amt and a.method = meth and a.date = d and a.voided_at is null
         and a.created_at > now() - interval '10 minutes' order by a.created_at desc limit 1;
      if dup.id is not null then perform public._prov_fail('possible_duplicate', jsonb_build_object('payment', to_jsonb(dup))); end if;
    end if;
    -- what is still owed (before an invoice exists, with an IVA allowance); more needs a reason and the owner level
    saldo := case when poid is not null then (public._prov_dinero(poid)->>'saldo')::numeric else (public._prov_vendor_money(vid)->>'saldo')::numeric end;
    if amt > saldo + 1 then
      if not xok then perform public._prov_fail('over_balance', jsonb_build_object('saldo', saldo)); end if;
      if xr is null or char_length(xr) < 5 then perform public._prov_fail('needs_reason', jsonb_build_object('saldo', saldo)); end if;
      if not (free or (public.is_true_owner() and prole = 'owner')) then perform public._prov_fail('needs_owner', jsonb_build_object('saldo', saldo)); end if;
    end if;
    eid := acct.post(d, 'Pago a ' || vd.name || case meth when 'sinpe' then ' · SINPE ' || ref else ' · Tarjeta' || coalesce(' ' || ref, '') end
                        || coalesce(' · pedido Nº ' || po.po_number, ''), 'ap', 'supadv:' || p_request_id,
             jsonb_build_array(jsonb_build_object('account', acct.map('supplier_advance'), 'debit', amt, 'memo', vd.name),
                               jsonb_build_object('account', acct.map(case meth when 'sinpe' then 'from_bank' when 'card_debit' then 'from_card_debit'
                                                                              else 'from_card_credit' end), 'credit', amt)), null, who);
    insert into public.supplier_advances (id, vendor_id, po_id, date, amount_crc, method, reference, ref_key, excess_reason, entry_id, created_by, staff_id)
      values (p_request_id, vid, poid, d, amt, meth, ref, rk, case when amt > saldo + 1 then xr end, eid, who, psid);
    applied := public._prov_aplicar(vid);
    perform public._prov_log('supplier_advance', psid, coalesce(pname, who), p_request_id::text,
      'Pago a ' || vd.name || ' · ' || amt || case meth when 'sinpe' then ' · SINPE' else ' · tarjeta' end || coalesce(' · pedido Nº ' || po.po_number, ''),
      jsonb_build_object('vendor_id', vid, 'po_id', poid, 'amount_crc', amt, 'method', meth, 'date', d, 'saldo', saldo, 'excess', amt > saldo + 1,
                         'applied_crc', applied, 'by', who));
    return jsonb_build_object('ok', true, 'id', p_request_id, 'applied_crc', amt - public._prov_unapplied(p_request_id),
      'unapplied_crc', public._prov_unapplied(p_request_id),
      'money', case when poid is not null then public._prov_dinero(poid) else public._prov_vendor_money(vid) end);
  exception when others then
    get stacked diagnostics e1 = returned_sqlstate, e2 = message_text, e3 = pg_exception_detail, e4 = constraint_name;
    r := public._prov_caught(e1, e2, e3, e4); if r is null then raise; end if; return r;
  end;
end $$;
-- a wrong Proveedores payment: the accountant (or the owner with the code) without a PIN, or the owner level with an
-- owner's PIN; its applications and its entry are reversed, nothing is deleted
create or replace function public.proveedor_pago_anular(p_id uuid, p_reason text, p_staff_id uuid default null, p_pin text default null)
returns jsonb language plpgsql volatile security definer set search_path = public, acct, extensions as $$
declare a public.supplier_advances; perr text; psid uuid; pname text; prole text; sp record; eid bigint; who text;
        why text := nullif(btrim(coalesce(p_reason, '')), ''); e1 text; e2 text; e3 text; e4 text; r jsonb;
begin
  if not acct.can_read() then
    if not public.is_true_owner() then return '{"ok":false,"error":"locked"}'::jsonb; end if;
    select err, sid, sname into perr, psid, pname from public._verify_pin(p_staff_id, p_pin, true);
    if perr is not null then return jsonb_build_object('ok', false, 'error', case perr when 'locked' then 'pin_locked' else perr end); end if;
    select role into prole from public.staff where id = psid;
    if prole is distinct from 'owner' then return '{"ok":false,"error":"not_owner"}'::jsonb; end if;
  end if;
  who := public._prov_actor();
  begin
    if why is null or char_length(why) < 5 then perform public._prov_fail('needs_reason'); end if;
    if char_length(why) > 200 then perform public._prov_fail('bad_request'); end if;
    select * into a from public.supplier_advances where id = p_id;
    if a.id is null then perform public._prov_fail('not_found'); end if;
    perform 1 from public.vendors where id = a.vendor_id for update;
    select * into a from public.supplier_advances where id = p_id for update;
    if a.voided_at is not null then return '{"ok":true,"repeat":true}'::jsonb; end if;
    for sp in select x.id from public.supplier_payments x where x.advance_id = a.id and x.voided_at is null order by x.id loop
      perform public._prov_void_payment(sp.id, 'pago anulado en Proveedores: ' || why, who);
    end loop;
    eid := public._prov_reverse(a.entry_id, 'pago a proveedor anulado: ' || why, who);
    update public.supplier_advances set voided_at = now(), void_reason = why, voided_by = who, void_entry_id = eid where id = a.id;
    perform public._prov_log('supplier_advance_void', psid, coalesce(pname, who), a.id::text, 'Pago anulado: ' || a.amount_crc || ' · ' || why,
      jsonb_build_object('vendor_id', a.vendor_id, 'po_id', a.po_id, 'amount_crc', a.amount_crc, 'reason', why, 'by', who));
    return '{"ok":true}'::jsonb;
  exception when others then
    get stacked diagnostics e1 = returned_sqlstate, e2 = message_text, e3 = pg_exception_detail, e4 = constraint_name;
    r := public._prov_caught(e1, e2, e3, e4); if r is null then raise; end if; return r;
  end;
end $$;

-- 7) rights ---
revoke all on function public._prov_dinero(uuid), public._prov_vendor_money(uuid), public._prov_po_brief(uuid, boolean), public._prov_mode(text),
  public._prov_can(), public._prov_date(jsonb), public._prov_reverse(bigint, text, text), public._prov_void_payment(uuid, text, text),
  public._prov_aplicar(uuid) from public, anon, authenticated;
do $$ declare f text; begin
  foreach f in array array['proveedores_lista(text, boolean)', 'proveedores_por_recibir(text)', 'proveedor_ficha(uuid, text)', 'proveedor_pedido(uuid, text)',
    'proveedor_historial(uuid, timestamptz, int)', 'proveedor_factura_registrar(uuid, uuid[], jsonb, uuid)', 'proveedor_factura_anular(uuid, text)',
    'proveedor_anticipos_aplicar(uuid)', 'proveedor_pago_registrar(jsonb, uuid, uuid, text)', 'proveedor_pago_anular(uuid, text, uuid, text)'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

select canopy.migration_end(40, 'proveedores_pagos');
notify pgrst, 'reload schema';
