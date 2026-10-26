-- =====================================================================================================
-- Canopy OS · migración 0012 · Compras: número de pedido, entregas parciales y factura del proveedor
-- Pegar TODO en Supabase → SQL Editor → New query → Run.  Requiere: 0011.
--
-- Qué hace
--   * Cada orden de compra tiene número (purchase_orders.po_number), fecha esperada y nota.
--   * Recibir por entregas: cada entrega guarda lo que llegó, el número y la fecha de la factura del proveedor
--     y quién la recibió (public.purchase_receipts). La orden queda "recibida en parte" hasta que llega todo,
--     o hasta que se indica que no llegará más.
--   * La misma factura del mismo proveedor no se puede registrar dos veces; tocar dos veces "Recibir" no
--     duplica (identificador de entrega).
-- Qué cambia para el personal: "Recibir" pide el número de factura y permite recibir solo una parte.
-- Reversión: drop function po_receive_delivery. Las columnas y la tabla nuevas pueden quedarse.
-- =====================================================================================================
select canopy.migration_begin(12, 'purchasing');

-- the order can now be partly received
do $c$
declare n text;
begin
  for n in select conname from pg_constraint where conrelid = 'public.purchase_orders'::regclass and contype = 'c'
             and pg_get_constraintdef(oid) ilike '%status%' loop
    execute format('alter table public.purchase_orders drop constraint %I', n);
  end loop;
end $c$;
alter table public.purchase_orders add constraint purchase_orders_status_check
  check (status in ('draft', 'sent', 'partially_received', 'received', 'cancelled'));

create sequence if not exists canopy.po_seq;
alter table public.purchase_orders add column if not exists po_number bigint;
alter table public.purchase_orders add column if not exists expected_on date;
-- the orders already made get their numbers in the order they were created (no money involved)
update public.purchase_orders p set po_number = s.n
  from (select id, nextval('canopy.po_seq') as n from (select id from public.purchase_orders where po_number is null order by created_at, id) q) s
 where p.id = s.id;
create unique index if not exists purchase_orders_number_idx on public.purchase_orders (po_number) where po_number is not null;
create or replace function public._po_number()
returns trigger language plpgsql security definer set search_path = public, canopy as $$
begin
  new.po_number := nextval('canopy.po_seq');
  return new;
end $$;
drop trigger if exists po_number on public.purchase_orders;
create trigger po_number before insert on public.purchase_orders for each row execute function public._po_number();

-- the pages may close a partly received order only by receiving (the function), never by editing it
create or replace function public._purchase_order_status()
returns trigger language plpgsql set search_path = public as $$
begin
  if current_user in ('authenticated', 'anon') and new.status is distinct from old.status then
    if not ((old.status = 'draft' and new.status in ('sent', 'cancelled')) or (old.status = 'sent' and new.status = 'cancelled')) then
      raise exception 'po_status: no se puede pasar de % a % desde la página', old.status, new.status using errcode = 'P0001';
    end if;
  end if;
  if current_user in ('authenticated', 'anon') then new.po_number := old.po_number; end if;
  return new;
end $$;

-- every delivery, with the supplier's invoice
create table if not exists public.purchase_receipts (
  id           uuid primary key,                 -- the page's request id: a delivery sent twice is saved once
  po_id        uuid not null references public.purchase_orders(id),
  vendor_id    uuid references public.vendors(id),
  invoice_no   text,
  invoice_date date,
  received_at  timestamptz not null default now(),
  by_name      text,
  lines        int not null default 0,
  total_crc    numeric not null default 0,
  final        boolean not null default false
);
create unique index if not exists purchase_receipts_invoice_once on public.purchase_receipts (vendor_id, lower(invoice_no))
  where invoice_no is not null;
alter table public.purchase_receipts enable row level security;
revoke all on public.purchase_receipts from anon, authenticated;
grant select on public.purchase_receipts to authenticated;
drop policy if exists "receipts read" on public.purchase_receipts;
create policy "receipts read" on public.purchase_receipts for select to authenticated using ((select public.inventory_open()));
alter table public.stock_moves add column if not exists receipt_id uuid;

create or replace function public.po_receive_delivery(p_po_id uuid, p_lines jsonb, p_receipt_id uuid,
                                                      p_invoice_no text default null, p_invoice_date date default null,
                                                      p_final boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare po public.purchase_orders; l jsonb; ln public.purchase_lines; it public.stock_items; got numeric; cost numeric; exp date;
        n int := 0; total numeric := 0; inv text; done boolean; st text;
begin
  if not public.inventory_open() then return jsonb_build_object('ok', false, 'error', 'locked'); end if;
  if p_receipt_id is null then return jsonb_build_object('ok', false, 'error', 'bad_request'); end if;
  select * into po from public.purchase_orders where id = p_po_id for update;
  if po.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if exists (select 1 from public.purchase_receipts where id = p_receipt_id) then
    return jsonb_build_object('ok', true, 'repeat', true, 'status', po.status);
  end if;
  if po.status = 'received' then return jsonb_build_object('ok', false, 'error', 'already_received'); end if;
  if po.status = 'cancelled' then return jsonb_build_object('ok', false, 'error', 'cancelled'); end if;
  inv := nullif(left(trim(coalesce(p_invoice_no, '')), 40), '');
  if inv is not null and exists (select 1 from public.purchase_receipts r where r.vendor_id is not distinct from po.vendor_id and lower(r.invoice_no) = lower(inv)) then
    return jsonb_build_object('ok', false, 'error', 'duplicate_invoice');
  end if;
  if jsonb_typeof(coalesce(p_lines, '[]'::jsonb)) <> 'array' then return jsonb_build_object('ok', false, 'error', 'bad_qty'); end if;
  for l in select * from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) loop
    if coalesce((l->>'qty')::numeric, 0) < 0 or coalesce((l->>'unit_cost')::numeric, 0) < 0 then
      return jsonb_build_object('ok', false, 'error', 'bad_qty'); end if;
    if not exists (select 1 from public.purchase_lines where id = (l->>'line_id')::uuid and po_id = po.id) then
      return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  end loop;
  for l in select * from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) order by (l->>'line_id') loop
    select * into ln from public.purchase_lines where id = (l->>'line_id')::uuid for update;
    got := coalesce((l->>'qty')::numeric, 0);
    cost := coalesce(nullif((l->>'unit_cost')::numeric, 0), ln.unit_cost);
    exp := coalesce((l->>'expires_on')::date, ln.expires_on);
    select * into it from public.stock_items where id = ln.item_id;
    if exp is null and it.shelf_life_days is not null then exp := current_date + it.shelf_life_days; end if;
    update public.purchase_lines set received_qty = coalesce(received_qty, 0) + got, unit_cost = cost, expires_on = exp where id = ln.id;
    if got > 0 then
      insert into public.stock_moves (item_id, kind, qty, unit_cost, po_id, expires_on, note, by_name, receipt_id)
        values (ln.item_id, 'purchase', got, cost, po.id, exp, coalesce('factura ' || inv, 'received'), public._inv_actor(), p_receipt_id);
      if cost is not null and cost > 0 then update public.stock_items set cost_per_pack = cost * pack_qty where id = ln.item_id; end if;
      n := n + 1; total := total + got * coalesce(cost, 0);
    end if;
  end loop;
  done := coalesce(p_final, false) or not exists (select 1 from public.purchase_lines where po_id = po.id and coalesce(received_qty, 0) < qty);
  st := case when done then 'received' else 'partially_received' end;
  update public.purchase_orders set status = st, received_at = case when done then now() else received_at end where id = po.id;
  insert into public.purchase_receipts (id, po_id, vendor_id, invoice_no, invoice_date, by_name, lines, total_crc, final)
    values (p_receipt_id, po.id, po.vendor_id, inv, p_invoice_date, public._inv_actor(), n, round(total, 2), done);
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('stock_receive', null, public._inv_actor(), po.id::text,
            'pedido ' || coalesce(po.po_number::text, '') || ': entrega' || coalesce(' · factura ' || inv, '') || case when done then ' · completo' else ' · parcial' end,
            jsonb_build_object('lines', n, 'total_crc', round(total, 2), 'receipt_id', p_receipt_id, 'invoice_no', inv, 'final', done));
  return jsonb_build_object('ok', true, 'status', st, 'lines', n, 'total_crc', round(total, 2));
end $$;
revoke all on function public.po_receive_delivery(uuid, jsonb, uuid, text, date, boolean) from public, anon;
grant execute on function public.po_receive_delivery(uuid, jsonb, uuid, text, date, boolean) to authenticated;

-- the one-step receive of earlier pages stays for orders not yet partly received
create or replace function public.po_receive(p_po_id uuid, p_lines jsonb default '[]'::jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare po public.purchase_orders; ln record; l jsonb; got numeric; cost numeric; exp date; n int := 0; it public.stock_items;
begin
  if not public.inventory_open() then return jsonb_build_object('ok', false, 'error', 'locked'); end if;
  select * into po from public.purchase_orders where id = p_po_id for update;
  if po.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if po.status = 'received' then return jsonb_build_object('ok', false, 'error', 'already_received'); end if;
  if po.status = 'cancelled' then return jsonb_build_object('ok', false, 'error', 'cancelled'); end if;
  if po.status = 'partially_received' then return jsonb_build_object('ok', false, 'error', 'use_delivery'); end if;
  for l in select * from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) loop
    if coalesce((l ->> 'received_qty')::numeric, 0) < 0 or coalesce((l ->> 'unit_cost')::numeric, 0) < 0 then
      return jsonb_build_object('ok', false, 'error', 'bad_qty');
    end if;
  end loop;
  for ln in select * from public.purchase_lines where po_id = p_po_id order by item_id loop
    got := ln.qty; cost := ln.unit_cost; exp := ln.expires_on;
    for l in select * from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) loop
      if (l ->> 'line_id')::uuid = ln.id then
        got := coalesce((l ->> 'received_qty')::numeric, got);
        cost := coalesce((l ->> 'unit_cost')::numeric, cost);
        exp := coalesce((l ->> 'expires_on')::date, exp);
      end if;
    end loop;
    select * into it from public.stock_items where id = ln.item_id;
    if exp is null and it.shelf_life_days is not null then exp := current_date + it.shelf_life_days; end if;
    update public.purchase_lines set received_qty = got, unit_cost = cost, expires_on = exp where id = ln.id;
    if got > 0 then
      insert into public.stock_moves (item_id, kind, qty, unit_cost, po_id, expires_on, note, by_name)
        values (ln.item_id, 'purchase', got, cost, p_po_id, exp, 'received', public._inv_actor());
      if cost is not null and cost > 0 then
        update public.stock_items set cost_per_pack = cost * pack_qty where id = ln.item_id;
      end if;
      n := n + 1;
    end if;
  end loop;
  update public.purchase_orders set status = 'received', received_at = now() where id = p_po_id;
  insert into public.audit_log (action, manager_name, target_id, summary, details)
    values ('stock_receive', public._inv_actor(), p_po_id::text, 'received a purchase order', jsonb_build_object('lines', n));
  return jsonb_build_object('ok', true, 'lines', n);
end $$;

select canopy.migration_end(12, 'purchasing');
notify pgrst, 'reload schema';
