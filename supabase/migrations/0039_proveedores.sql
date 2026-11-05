-- =====================================================================================================
-- Canopy OS · migración 0039 · Proveedores: catálogo de cada proveedor, pedidos, recepción por el personal en turno
-- y alertas de inventario (la 0040 trae lo que lee la página, las facturas, los pagos y los anticipos)
-- Pegar TODO en Supabase → SQL Editor → New query → Run. Requiere: 0038. Una sola transacción.
--
-- Qué hace (D-067)
--   * El catálogo de cada proveedor (vendor_items): presentación, unidades por presentación, precio habitual sin IVA,
--     código; un producto puede venir de varios proveedores. El preferido sigue siendo stock_items.vendor_id. Se llena
--     con lo que ya existe (el proveedor de cada producto y los pedidos anteriores), solo en tablas nuevas.
--   * Borradores de pedido por proveedor, pedidos con número y versión, edición con bitácora, cancelar, cerrar lo
--     pendiente, asignar proveedor a un pedido viejo.
--   * Recepción: lo pedido, lo recibido y el precio real por línea (purchase_receipt_lines), entregas parciales, nunca
--     dos veces, más de lo pedido solo con un encargado, el precio del catálogo nunca cambia al recibir, correcciones
--     como entregas nuevas (nada se borra).
--   * «Recibe en este aparato» (work_sessions): quien está en turno recibe sin otro PIN; el servidor revisa en cada
--     llamada que esa persona marcó su PIN en este mismo aparato durante su turno abierto.
--   * Alertas de inventario bajo con la regla de siempre (inventory_stats), sin volver a pedir lo ya pedido.
-- Qué NO cambia: ninguna función, regla ni permiso existente; ningún registro existente; la página de Inventario
--   publicada sigue funcionando igual (sus pedidos y recepciones).
-- Qué cambia para el personal: nada hasta que se publique proveedores.html.
-- Cuándo: fuera del horario de atención, después de la 0038 y antes de la 0040.
-- Reversión: supabase/tools/reversion-0039.sql (quita funciones y disparadores nuevos; tablas, columnas y datos quedan).
-- =====================================================================================================
select canopy.migration_begin(39, 'proveedores');
set local lock_timeout = '8s';

-- Lock order: the order row (for update; a payment takes it for share) → its lines (id order) → stock items (inside
-- the move trigger, item order) → receipts → the vendor row (payments, invoices). A work session row is locked only by
-- turno_estado. A deadlock (40P01) inside a new function is answered «changed».

-- 1) tables and columns ---
create table if not exists public.vendor_items (
  id uuid primary key default gen_random_uuid(),
  vendor_id uuid not null references public.vendors(id) on delete cascade,
  item_id uuid not null references public.stock_items(id) on delete cascade,
  vendor_code text check (vendor_code is null or char_length(vendor_code) <= 40),
  label text check (label is null or char_length(label) <= 80),
  pack_label text check (pack_label is null or char_length(pack_label) <= 60),
  pack_qty numeric not null check (pack_qty > 0 and pack_qty < 1e9),          -- base units per presentation
  usual_price numeric(14,2) check (usual_price is null or (usual_price >= 0 and usual_price <= 100000000)), -- per presentation, sin IVA
  usual_qty numeric check (usual_qty is null or (usual_qty > 0 and usual_qty <= 100000)),
  active boolean not null default true,
  created_at timestamptz not null default now(), created_by text,
  updated_at timestamptz not null default now(), updated_by text,
  constraint vendor_items_pack_qty_finite check (pack_qty is null or abs(pack_qty) < 1e15),
  constraint vendor_items_usual_price_finite check (usual_price is null or abs(usual_price) < 1e15),
  constraint vendor_items_usual_qty_finite check (usual_qty is null or abs(usual_qty) < 1e15));
create unique index if not exists vendor_items_live on public.vendor_items (vendor_id, item_id, pack_qty) where active;
create index if not exists vendor_items_item on public.vendor_items (item_id);
create index if not exists vendor_items_vendor on public.vendor_items (vendor_id);

create table if not exists public.purchase_drafts (
  id uuid primary key default gen_random_uuid(),
  vendor_id uuid not null references public.vendors(id) on delete cascade,
  lines jsonb not null default '[]',
  note text check (note is null or char_length(note) <= 500),
  version int not null default 1,
  status text not null default 'open' check (status in ('open', 'used', 'discarded')),
  po_id uuid references public.purchase_orders(id),
  created_at timestamptz not null default now(), created_by text,
  updated_at timestamptz not null default now(), updated_by text);
create unique index if not exists purchase_drafts_open on public.purchase_drafts (vendor_id) where status = 'open';
create index if not exists purchase_drafts_vendor on public.purchase_drafts (vendor_id, updated_at desc);

alter table public.purchase_orders add column if not exists version int not null default 0;
alter table public.purchase_lines add column if not exists vendor_item_id uuid references public.vendor_items(id) on delete set null;
alter table public.purchase_lines add column if not exists pack_label text;
alter table public.purchase_lines add column if not exists pack_qty numeric;
alter table public.purchase_lines add column if not exists ordered_unit_cost numeric;
alter table public.purchase_lines add column if not exists pos int;
alter table public.purchase_lines add column if not exists removed_at timestamptz;
alter table public.purchase_lines drop constraint if exists purchase_lines_prov_check;
alter table public.purchase_lines add constraint purchase_lines_prov_check check ((pack_label is null or char_length(pack_label) <= 60)
  and (pack_qty is null or pack_qty > 0) and (ordered_unit_cost is null or ordered_unit_cost >= 0));
alter table public.purchase_lines drop constraint if exists purchase_lines_pack_qty_finite;
alter table public.purchase_lines add constraint purchase_lines_pack_qty_finite check (pack_qty is null or abs(pack_qty) < 1e15);
alter table public.purchase_lines drop constraint if exists purchase_lines_ordered_unit_cost_finite;
alter table public.purchase_lines add constraint purchase_lines_ordered_unit_cost_finite check (ordered_unit_cost is null or abs(ordered_unit_cost) < 1e15);
create index if not exists purchase_lines_vendor_item on public.purchase_lines (vendor_item_id) where vendor_item_id is not null;

alter table public.purchase_receipts add column if not exists staff_id uuid;
alter table public.purchase_receipts add column if not exists work_session_id uuid;
alter table public.purchase_receipts add column if not exists note text;
alter table public.purchase_receipts add column if not exists origin text;
alter table public.purchase_receipts add column if not exists close_requested boolean not null default false;
alter table public.purchase_receipts add column if not exists corrects uuid;
alter table public.purchase_receipts drop constraint if exists purchase_receipts_prov_check;
alter table public.purchase_receipts add constraint purchase_receipts_prov_check check ((note is null or char_length(note) <= 500)
  and (origin is null or origin in ('proveedores', 'correccion')));
create index if not exists purchase_receipts_po on public.purchase_receipts (po_id);
create index if not exists stock_moves_receipt on public.stock_moves (receipt_id) where receipt_id is not null;

create table if not exists public.purchase_receipt_lines (
  receipt_id uuid not null references public.purchase_receipts(id),
  line_id uuid not null references public.purchase_lines(id),
  item_id uuid not null references public.stock_items(id),
  packs numeric not null,                   -- presentations (negative only in a correction)
  qty numeric not null,                     -- base units (negative only in a correction)
  pack_qty numeric not null check (pack_qty > 0),
  unit_cost numeric check (unit_cost is null or unit_cost >= 0),   -- per base unit, as booked
  pack_price numeric(14,2),                 -- per presentation, as booked
  expected_pack_price numeric(14,2),
  observed_pack_price numeric(14,2),        -- what an employee saw (never booked)
  extra_reported_packs numeric,             -- what an employee reported beyond the pending amount (never booked)
  move_id bigint,
  primary key (receipt_id, line_id),
  constraint purchase_receipt_lines_packs_finite check (abs(packs) < 1e15),
  constraint purchase_receipt_lines_qty_finite check (abs(qty) < 1e15),
  constraint purchase_receipt_lines_pack_qty_finite check (abs(pack_qty) < 1e15),
  constraint purchase_receipt_lines_unit_cost_finite check (unit_cost is null or abs(unit_cost) < 1e15),
  constraint purchase_receipt_lines_pack_price_finite check (pack_price is null or abs(pack_price) < 1e15),
  constraint purchase_receipt_lines_expected_pack_price_finite check (expected_pack_price is null or abs(expected_pack_price) < 1e15),
  constraint purchase_receipt_lines_observed_pack_price_finite check (observed_pack_price is null or abs(observed_pack_price) < 1e15),
  constraint purchase_receipt_lines_extra_reported_packs_finite check (extra_reported_packs is null or abs(extra_reported_packs) < 1e15));
create index if not exists purchase_receipt_lines_line on public.purchase_receipt_lines (line_id);

-- every payment registered in Proveedores (SINPE or card); the 0040 functions write it
create table if not exists public.supplier_advances (
  id uuid primary key,                      -- the page's request id
  vendor_id uuid not null references public.vendors(id),
  po_id uuid references public.purchase_orders(id),
  date date not null,
  amount_crc numeric(14,2) not null check (amount_crc > 0 and amount_crc <= 100000000),
  method text not null check (method in ('sinpe', 'card_debit', 'card_credit')),
  reference text check (reference is null or char_length(reference) <= 80),
  ref_key text,                             -- lower case, letters and digits only
  excess_reason text check (excess_reason is null or char_length(excess_reason) <= 200),
  entry_id bigint, void_entry_id bigint, voided_at timestamptz, void_reason text, voided_by text,
  created_at timestamptz not null default now(), created_by text not null, staff_id uuid,
  constraint supplier_advances_amount_crc_finite check (abs(amount_crc) < 1e15));
create unique index if not exists supplier_advances_sinpe_once on public.supplier_advances (ref_key) where method = 'sinpe' and voided_at is null;
create index if not exists supplier_advances_vendor on public.supplier_advances (vendor_id, created_at);
create index if not exists supplier_advances_po on public.supplier_advances (po_id) where po_id is not null;
alter table public.supplier_payments add column if not exists method text;
alter table public.supplier_payments add column if not exists advance_id uuid references public.supplier_advances(id);
alter table public.supplier_payments add column if not exists po_id uuid;   -- no foreign key (lock order)
alter table public.supplier_payments drop constraint if exists supplier_payments_method_len;
alter table public.supplier_payments add constraint supplier_payments_method_len check (method is null or char_length(method) <= 20);
create index if not exists supplier_payments_advance on public.supplier_payments (advance_id) where advance_id is not null;

-- how a supplier is paid: never on vendors (whose «inventory all» rule lets a manager unlock write it directly)
create table if not exists public.vendor_pay_info (
  vendor_id uuid primary key references public.vendors(id) on delete cascade,
  sinpe text check (sinpe is null or char_length(sinpe) <= 120),
  updated_at timestamptz not null default now(), updated_by text);

-- «Recibe en este aparato»: security state, rows are never deleted
create table if not exists public.work_sessions (
  id uuid primary key default gen_random_uuid(),
  token_hash text not null unique,
  staff_id uuid not null references public.staff(id),
  staff_name text not null,
  time_entry_id uuid not null,              -- no foreign key (manager_delete_shift deletes entries)
  login_id uuid not null,
  session_id text not null,                 -- the JWT session_id it is bound to
  pin_fp text not null,                     -- sha256 of staff.pin_hash at issue
  station text check (station is null or char_length(station) <= 40),
  how text not null check (how in ('pin', 'caja')),
  started_at timestamptz not null default now(),
  expires_at timestamptz not null,
  last_used_at timestamptz,
  rebinds int not null default 0, last_rebind_at timestamptz,
  ended_at timestamptz,
  ended_how text check (ended_how is null or ended_how in ('clock_out', 'pin_changed', 'inactive', 'replaced', 'signed_out', 'moved')));
create unique index if not exists work_sessions_live_session on public.work_sessions (session_id) where ended_at is null;
create index if not exists work_sessions_staff on public.work_sessions (staff_id) where ended_at is null;
create index if not exists work_sessions_entry on public.work_sessions (time_entry_id) where ended_at is null;
create index if not exists work_sessions_login on public.work_sessions (login_id, started_at);

do $$ declare t text; begin
  foreach t in array array['vendor_items', 'purchase_drafts', 'purchase_receipt_lines', 'supplier_advances', 'vendor_pay_info', 'work_sessions'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from public, anon, authenticated', t);
    execute format('grant select on public.%I to canopy_backup', t);
  end loop;
end $$;

-- 2) what already exists, copied into the new tables only (idempotent) ---
create or replace function public._prov_pqe(p_pack numeric, p_packs numeric, p_qty numeric, p_item_pack numeric) returns numeric
language sql immutable set search_path = public as $$
  select coalesce(p_pack, case when p_packs > 0 and p_qty > 0 then trim_scale(p_qty / p_packs) end, nullif(p_item_pack, 0), 1) $$;
-- (a) each item's supplier
insert into public.vendor_items (vendor_id, item_id, pack_label, pack_qty, usual_price, active, created_by)
select i.vendor_id, i.id, left(i.pack_label, 60), i.pack_qty, case when i.cost_per_pack > 0 and i.cost_per_pack <= 100000000 then round(i.cost_per_pack, 2) end,
       i.active, 'migración 0039'
  from public.stock_items i
 where i.vendor_id is not null and i.pack_qty > 0 and i.pack_qty < 1e9
   and not exists (select 1 from public.vendor_items x where x.vendor_id = i.vendor_id and x.item_id = i.id and x.pack_qty = i.pack_qty);
-- (b) what was ordered from each supplier in another presentation (the latest price)
insert into public.vendor_items (vendor_id, item_id, pack_label, pack_qty, usual_price, active, created_by)
select distinct on (o.vendor_id, l.item_id, q.pqe) o.vendor_id, l.item_id, case when q.pqe = i.pack_qty then left(i.pack_label, 60) end, q.pqe,
       case when l.unit_cost * q.pqe between 0.01 and 100000000 then round(l.unit_cost * q.pqe, 2) end, i.active, 'migración 0039'
  from public.purchase_lines l join public.purchase_orders o on o.id = l.po_id join public.stock_items i on i.id = l.item_id
  cross join lateral (select public._prov_pqe(l.pack_qty, l.packs, l.qty, i.pack_qty) as pqe) q
 where o.vendor_id is not null and o.status <> 'cancelled' and q.pqe > 0 and q.pqe < 1e9
   and not exists (select 1 from public.vendor_items x where x.vendor_id = o.vendor_id and x.item_id = l.item_id and x.pack_qty = q.pqe)
 order by o.vendor_id, l.item_id, q.pqe, (l.unit_cost is null), o.created_at desc, l.id;
-- what each existing delivery brought per line, from its stock moves (one live line of that item; else skipped)
insert into public.purchase_receipt_lines (receipt_id, line_id, item_id, packs, qty, pack_qty, unit_cost, pack_price, move_id)
select m.receipt_id, l.id, m.item_id, round(m.qty / q.pqe, 4), m.qty, q.pqe, m.unit_cost,
       case when abs(m.unit_cost * q.pqe) < 1e12 then round(m.unit_cost * q.pqe, 2) end, m.id
  from public.stock_moves m join public.purchase_receipts r on r.id = m.receipt_id
  join public.purchase_lines l on l.po_id = r.po_id and l.item_id = m.item_id and l.removed_at is null
  join public.stock_items i on i.id = m.item_id
  cross join lateral (select public._prov_pqe(l.pack_qty, l.packs, l.qty, i.pack_qty) as pqe) q
 where m.kind = 'purchase' and m.qty > 0 and (m.unit_cost is null or m.unit_cost >= 0)
   and (select count(*) from public.purchase_lines z where z.po_id = r.po_id and z.item_id = m.item_id and z.removed_at is null) = 1
   and (select count(*) from public.stock_moves z where z.receipt_id = m.receipt_id and z.item_id = m.item_id and z.kind = 'purchase') = 1
   and not exists (select 1 from public.purchase_receipt_lines x where x.receipt_id = m.receipt_id and x.line_id = l.id);

-- 3) helpers (internal) ---
-- a refusal from anywhere inside a function's block: «prov:<code>», extra answer keys in the detail (jsonb)
create or replace function public._prov_fail(p_code text, p_extra jsonb default null) returns void
language plpgsql set search_path = public as $$
begin
  raise exception using errcode = 'P0001', message = 'prov:' || p_code, detail = coalesce(p_extra, '{}'::jsonb)::text;
end $$;
-- what the page gets for an error caught at the end of a block; null = raise it again
create or replace function public._prov_caught(p_state text, p_msg text, p_detail text, p_cons text) returns jsonb
language plpgsql immutable set search_path = public as $$
begin
  if p_msg like 'prov:%' then
    return jsonb_build_object('ok', false, 'error', substr(p_msg, 6)) || coalesce(nullif(p_detail, '')::jsonb, '{}'::jsonb);
  end if;
  return case when p_state = '40P01' then '{"ok":false,"error":"changed"}'::jsonb
              when p_msg ~ '^period_closed' then '{"ok":false,"error":"period_closed"}'::jsonb
              when p_msg ~ '^unknown_account' then '{"ok":false,"error":"unknown_account"}'::jsonb
              when p_msg ~ '^period_locked' then '{"ok":false,"error":"period_locked"}'::jsonb
              when p_state = '23505' and p_cons = 'supplier_advances_sinpe_once' then '{"ok":false,"error":"duplicate_reference"}'::jsonb
              when p_state = '23505' and p_cons = 'vendor_items_live' then '{"ok":false,"error":"duplicate_product"}'::jsonb
              when p_state = '23505' then '{"ok":false,"error":"changed"}'::jsonb end;
end $$;
create or replace function public._prov_uuid(p text) returns uuid language plpgsql immutable set search_path = public as $$
begin
  if p is null or p !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then return null; end if;
  return p::uuid;
end $$;
-- jsonb inputs: a number only as a JSON number (never a string, NaN or Infinity), text only as a string, else bad_request
create or replace function public._prov_num(p jsonb) returns numeric language plpgsql immutable set search_path = public as $$
begin
  if p is null or jsonb_typeof(p) = 'null' then return null; end if;
  if jsonb_typeof(p) <> 'number' then perform public._prov_fail('bad_request'); end if;
  return p::numeric;
end $$;
create or replace function public._prov_txt(p jsonb, p_max int) returns text language plpgsql immutable set search_path = public as $$
declare t text;
begin
  if p is null or jsonb_typeof(p) = 'null' then return null; end if;
  if jsonb_typeof(p) <> 'string' then perform public._prov_fail('bad_request'); end if;
  t := nullif(btrim(p #>> '{}'), '');
  if char_length(t) > p_max then perform public._prov_fail('bad_request'); end if;
  return t;
end $$;
create or replace function public._prov_bool(p jsonb) returns boolean language plpgsql immutable set search_path = public as $$
begin
  if p is null or jsonb_typeof(p) = 'null' then return null; end if;
  if jsonb_typeof(p) <> 'boolean' then perform public._prov_fail('bad_request'); end if;
  return p::boolean;
end $$;
-- an id inside a payload: a valid uuid string, else bad_request (absent → null)
create or replace function public._prov_id(p jsonb) returns uuid language plpgsql immutable set search_path = public as $$
declare u uuid;
begin
  if p is null or jsonb_typeof(p) = 'null' then return null; end if;
  u := case when jsonb_typeof(p) = 'string' then public._prov_uuid(p #>> '{}') end;
  if u is null then perform public._prov_fail('bad_request'); end if;
  return u;
end $$;
-- a quantity of presentations: > 0 (≥ 0 with p_zero), ≤ 100 000, at most 3 decimals; else p_err
create or replace function public._prov_packs(p jsonb, p_zero boolean, p_err text) returns numeric language plpgsql immutable set search_path = public as $$
declare n numeric := public._prov_num(p);
begin
  if n is null then return null; end if;
  if n < 0 or (n = 0 and not p_zero) or n > 100000 or n <> round(n, 3) then perform public._prov_fail(p_err); end if;
  return n;
end $$;
-- a price: ≥ 0, ≤ 100 000 000
create or replace function public._prov_price(p jsonb) returns numeric language plpgsql immutable set search_path = public as $$
declare n numeric := public._prov_num(p);
begin
  if n is not null and (n < 0 or n > 100000000) then perform public._prov_fail('bad_price'); end if;
  return n;
end $$;
create or replace function public._prov_manage() returns boolean language sql stable security definer set search_path = public, extensions as $$
  select coalesce(public.is_owner(), false) $$;
create or replace function public._prov_books() returns boolean language sql stable security definer set search_path = public, extensions as $$
  select coalesce(public.is_owner() or acct.can_read(), false) $$;
create or replace function public._prov_actor() returns text language sql stable security definer set search_path = public, extensions as $$
  select case when public.is_owner() then public._inv_actor() when acct.can_read() then acct.actor() else public._owner_label() end $$;
create or replace function public._prov_station(p text) returns text language sql immutable set search_path = public as $$
  select nullif(btrim(left(public._discount_clean(left(p, 80)), 40)), '') $$;
create or replace function public._prov_log(p_action text, p_mid uuid, p_by text, p_target text, p_summary text, p_details jsonb)
returns void language sql security definer set search_path = public as $$
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
  values (p_action, p_mid, p_by, p_target, left(p_summary, 300), p_details) $$;
-- the catalog row an order line belongs to: its own, else the supplier's row of that item (same presentation first)
create or replace function public._prov_vi_match(p_vendor uuid, p_item uuid, p_pqe numeric) returns uuid
language sql stable security definer set search_path = public as $$
  select v.id from public.vendor_items v where v.vendor_id = p_vendor and v.item_id = p_item
   order by (v.pack_qty = p_pqe) desc, v.active desc, v.pack_qty, v.created_at, v.id limit 1 $$;
-- a drawer payout that is live and still undocumented (0029's rule): its amount, else 0
create or replace function public._prov_payout_open(p_id uuid) returns numeric language sql stable security definer set search_path = public as $$
  select coalesce((select m.amount_crc from public.cash_movements m where m.id = p_id and m.voided_at is null
     and not exists (select 1 from public.supplier_payments sp where sp.payout_id = m.id and sp.voided_at is null)
     and not exists (select 1 from public.expenses e where e.payout_id = m.id and e.voided_at is null)
     and not exists (select 1 from public.expense_payments x where x.payout_id = m.id and x.voided_at is null)), 0) $$;
-- what of an advance is not applied yet (0 once voided)
create or replace function public._prov_unapplied(p_id uuid) returns numeric language sql stable security definer set search_path = public as $$
  select case when a.voided_at is not null then 0 else a.amount_crc - coalesce((select sum(p.amount_crc) from public.supplier_payments p
                where p.advance_id = a.id and p.voided_at is null), 0) end
    from public.supplier_advances a where a.id = p_id $$;

-- every line of an order, with what was received and what is pending, in presentations
create or replace function public._prov_lines(p_po_id uuid)
returns table (id uuid, pos int, vendor_item_id uuid, item_id uuid, item_name text, unit text, label text, vendor_code text, pack_label text,
               pack_qty numeric, packs numeric, qty numeric, received_qty numeric, pending_qty numeric, received_packs numeric,
               pending_packs numeric, exp_unit numeric, expected_pack_price numeric, line_total_est numeric, received_value numeric,
               removed boolean, shelf_life_days int)
language sql stable security definer set search_path = public as $$
  select l.id, l.pos, vi.id, l.item_id, i.name, i.unit, vi.label, vi.vendor_code,
         coalesce(l.pack_label, vi.pack_label, case when q.pqe = i.pack_qty then i.pack_label end), q.pqe, l.packs, l.qty,
         coalesce(l.received_qty, 0), greatest(l.qty - coalesce(l.received_qty, 0), 0),
         round(coalesce(l.received_qty, 0) / q.pqe, 4), round(greatest(l.qty - coalesce(l.received_qty, 0), 0) / q.pqe, 4),
         coalesce(l.unit_cost, l.ordered_unit_cost), round(coalesce(l.unit_cost, l.ordered_unit_cost) * q.pqe, 2),
         round(l.qty * coalesce(l.unit_cost, l.ordered_unit_cost, 0), 2),
         (select round(coalesce(sum(x.qty * coalesce(x.unit_cost, 0)), 0), 2) from public.purchase_receipt_lines x where x.line_id = l.id),
         l.removed_at is not null, i.shelf_life_days
    from public.purchase_lines l join public.purchase_orders o on o.id = l.po_id join public.stock_items i on i.id = l.item_id
   cross join lateral (select public._prov_pqe(l.pack_qty, l.packs, l.qty, i.pack_qty) as pqe) q
    left join public.vendor_items vi on vi.id = coalesce(l.vendor_item_id, public._prov_vi_match(o.vendor_id, l.item_id, q.pqe))
   where l.po_id = p_po_id
   order by coalesce(l.pos, 1000000), i.name, l.id $$;

-- 4) triggers ---
-- a supplier chosen for an item (also by the published Inventario page) always has a catalog row; never fails the save
create or replace function public._prov_item_vendor() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and old.vendor_id is not distinct from new.vendor_id then return null; end if;
  begin
    if not exists (select 1 from public.vendor_items x where x.vendor_id = new.vendor_id and x.item_id = new.id and x.active) then
      insert into public.vendor_items (vendor_id, item_id, pack_label, pack_qty, usual_price, active, created_by)
        values (new.vendor_id, new.id, left(new.pack_label, 60), new.pack_qty,
                case when new.cost_per_pack > 0 and new.cost_per_pack <= 100000000 then round(new.cost_per_pack, 2) end, new.active, 'inventario');
    end if;
  exception when deadlock_detected or lock_not_available or query_canceled then raise;
    when others then null;
  end;
  return null;
end $$;
drop trigger if exists stock_items_vendor_catalog on public.stock_items;
create trigger stock_items_vendor_catalog after insert or update of vendor_id on public.stock_items
  for each row when (new.vendor_id is not null) execute function public._prov_item_vendor();
-- a page writing purchase_lines directly never sets the six new columns
create or replace function public._prov_line_protect() returns trigger language plpgsql set search_path = public as $$
begin
  if current_user in ('authenticated', 'anon') then
    if tg_op = 'INSERT' then
      new.vendor_item_id := null; new.pack_label := null; new.pack_qty := null; new.ordered_unit_cost := null; new.pos := null; new.removed_at := null;
    else
      new.vendor_item_id := old.vendor_item_id; new.pack_label := old.pack_label; new.pack_qty := old.pack_qty;
      new.ordered_unit_cost := old.ordered_unit_cost; new.pos := old.pos; new.removed_at := old.removed_at;
    end if;
  end if;
  return new;
end $$;
drop trigger if exists purchase_lines_protect_new on public.purchase_lines;
create trigger purchase_lines_protect_new before insert or update on public.purchase_lines
  for each row execute function public._prov_line_protect();
-- every change of an order, its lines or its deliveries moves its version (two devices never save over each other)
create or replace function public._prov_po_version() returns trigger language plpgsql set search_path = public as $$
begin
  new.version := coalesce(old.version, 0) + 1;
  return new;
end $$;
drop trigger if exists purchase_orders_version on public.purchase_orders;
create trigger purchase_orders_version before update on public.purchase_orders for each row execute function public._prov_po_version();
create or replace function public._prov_po_bump() returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.purchase_orders set version = version where id = case when tg_op = 'DELETE' then old.po_id else new.po_id end;
  if tg_op = 'UPDATE' and new.po_id is distinct from old.po_id then
    update public.purchase_orders set version = version where id = old.po_id;
  end if;
  return null;
end $$;
drop trigger if exists purchase_lines_po_version on public.purchase_lines;
create trigger purchase_lines_po_version after insert or update or delete on public.purchase_lines
  for each row execute function public._prov_po_bump();
drop trigger if exists purchase_receipts_po_version on public.purchase_receipts;
create trigger purchase_receipts_po_version after insert on public.purchase_receipts
  for each row execute function public._prov_po_bump();
-- a clock-out (any page), a deleted shift, a new PIN or a deactivation ends the work sessions it carried; a punch or a
-- save never fails because of it
create or replace function public._prov_entry_end() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' and not (old.clock_out is null and new.clock_out is not null) then return null; end if;
  begin
    update public.work_sessions set ended_at = now(), ended_how = 'clock_out' where time_entry_id = old.id and ended_at is null;
  exception when others then null;
  end;
  return null;
end $$;
drop trigger if exists time_entries_work_session_end on public.time_entries;
create trigger time_entries_work_session_end after update of clock_out or delete on public.time_entries
  for each row execute function public._prov_entry_end();
create or replace function public._prov_staff_end() returns trigger language plpgsql security definer set search_path = public as $$
begin
  begin
    update public.work_sessions set ended_at = now(), ended_how = case when old.active and not new.active then 'inactive' else 'pin_changed' end
     where staff_id = new.id and ended_at is null;
  exception when others then null;
  end;
  return null;
end $$;
drop trigger if exists staff_work_session_end on public.staff;
create trigger staff_work_session_end after update of pin_hash, active on public.staff for each row
  when (old.pin_hash is distinct from new.pin_hash or (old.active and not new.active)) execute function public._prov_staff_end();
revoke all on function public._prov_pqe(numeric, numeric, numeric, numeric), public._prov_fail(text, jsonb), public._prov_caught(text, text, text, text),
  public._prov_uuid(text), public._prov_num(jsonb), public._prov_txt(jsonb, int), public._prov_bool(jsonb), public._prov_id(jsonb),
  public._prov_packs(jsonb, boolean, text), public._prov_price(jsonb), public._prov_manage(), public._prov_books(), public._prov_actor(),
  public._prov_station(text), public._prov_log(text, uuid, text, text, text, jsonb), public._prov_vi_match(uuid, uuid, numeric),
  public._prov_payout_open(uuid), public._prov_unapplied(uuid), public._prov_lines(uuid), public._prov_item_vendor(),
  public._prov_line_protect(), public._prov_po_version(), public._prov_po_bump(), public._prov_entry_end(), public._prov_staff_end()
  from public, anon, authenticated;

-- 5) «Recibe en este aparato»: work sessions ---
-- a session is good only while ALL hold (checked at every use): the token, not ended, not expired, this login (a café
-- login), this sign-in (else «moved»: turno_estado rebinds), the person active with the PIN of the day it was issued, the
-- shift it was issued for still open and under 16 hours
create or replace function public._prov_turno(p_token text, out why text, out wid uuid, out sid uuid, out sname text, out station text)
language plpgsql volatile security definer set search_path = public, extensions as $$
declare w public.work_sessions; s public.staff; e public.time_entries; js text := public._jwt_session();
begin
  if coalesce(p_token, '') = '' or char_length(p_token) > 200 then why := 'unknown'; return; end if;
  select * into w from public.work_sessions where token_hash = encode(digest(p_token, 'sha256'), 'hex');
  why := case when w.id is null then 'unknown' when w.ended_at is not null then 'ended' when w.expires_at <= now() then 'expired'
              when w.login_id is distinct from auth.uid() or not public.is_cafe() then 'other_login' when js is null then 'no_session' end;
  if why is null then
    select * into s from public.staff where id = w.staff_id;
    select * into e from public.time_entries where id = w.time_entry_id;
    why := case when not coalesce(s.active, false) then 'inactive'
                when s.pin_hash is null or encode(digest(s.pin_hash, 'sha256'), 'hex') <> w.pin_fp then 'pin_changed'
                when e.id is null or e.clock_out is not null or e.clock_in <= now() - interval '16 hours' then 'not_on_shift'
                when js <> w.session_id then 'moved' end;
  end if;
  wid := w.id; sid := w.staff_id; sname := w.staff_name; station := w.station;
  if why is null then update public.work_sessions set last_used_at = now() where id = w.id; end if;
end $$;
-- a new session on this sign-in for that person's open entry: whoever held this sign-in is replaced, and that person's
-- sessions on this login and station end (moved). Only the sha256 of the token is kept
create or replace function public._prov_mint(p_sid uuid, p_sname text, p_entry uuid, p_clock_in timestamptz, p_station text, p_how text,
                                              out token text, out expires_at timestamptz, out wid uuid)
language plpgsql volatile security definer set search_path = public, extensions as $$
declare js text := public._jwt_session(); fp text; r record; h text;
begin
  select encode(digest(pin_hash, 'sha256'), 'hex') into fp from public.staff where id = p_sid and pin_hash is not null;
  if fp is null then perform public._prov_fail('no_session', '{"why":"pin_changed"}'); end if;
  for r in select * from public.work_sessions w where w.ended_at is null and (w.session_id = js
           or (w.staff_id = p_sid and w.login_id = auth.uid() and w.station is not distinct from p_station)) order by w.id for update loop
    h := case when r.session_id = js then 'replaced' else 'moved' end;
    update public.work_sessions set ended_at = now(), ended_how = h where id = r.id;
    perform public._prov_log('work_session_end', r.staff_id, r.staff_name, r.id::text, 'Recibe en este aparato: ' || r.staff_name || ' · terminó',
      jsonb_build_object('how', h, 'by', p_sname, 'station', r.station, 'session_tag', public._discount_tag(r.session_id)));
  end loop;
  token := encode(gen_random_bytes(32), 'hex');
  insert into public.work_sessions (token_hash, staff_id, staff_name, time_entry_id, login_id, session_id, pin_fp, station, how, expires_at)
    values (encode(digest(token, 'sha256'), 'hex'), p_sid, p_sname, p_entry, auth.uid(), js, fp, p_station, p_how,
            least(p_clock_in, now()) + interval '16 hours')
    returning work_sessions.expires_at, work_sessions.id into expires_at, wid;
  perform public._prov_log('work_session_start', p_sid, p_sname, wid::text, 'Recibe en este aparato: ' || p_sname,
    jsonb_build_object('staff_id', p_sid, 'station', p_station, 'how', p_how, 'session_tag', public._discount_tag(js), 'time_entry_id', p_entry));
end $$;
-- «Estoy en turno aquí»: the person's own PIN, once per device and shift (and the clock-in when asked)
create or replace function public.turno_aqui(p_staff_id uuid, p_pin text, p_station text default null, p_clock_in boolean default false)
returns jsonb language plpgsql volatile security definer set search_path = public, extensions as $$
declare e public.time_entries; o public.time_entries; v record; m record; made boolean := false; e1 text; e2 text; e3 text; e4 text; r jsonb;
begin
  if not public.is_cafe() then return '{"ok":false,"error":"no_account"}'::jsonb; end if;
  if public._jwt_session() is null then return '{"ok":false,"error":"no_session","why":"no_session"}'::jsonb; end if;
  -- the shift before the PIN (a café login already reads the open entries)
  select * into e from public.time_entries t where t.staff_id = p_staff_id and t.clock_out is null
     and t.clock_in > now() - interval '16 hours' and t.clock_in <= now() + interval '5 minutes' order by t.clock_in desc limit 1;
  if e.id is null then
    select * into o from public.time_entries t where t.staff_id = p_staff_id and t.clock_out is null order by t.clock_in desc limit 1;
    if o.id is not null then return jsonb_build_object('ok', false, 'error', 'stale_shift', 'clock_in', o.clock_in); end if;
    if not coalesce(p_clock_in, false) then return '{"ok":false,"error":"not_clocked_in"}'::jsonb; end if;
  end if;
  select * into v from public._verify_pin(p_staff_id, p_pin, false);     -- a wrong try stays counted
  if v.err is not null then return jsonb_build_object('ok', false, 'error', case v.err when 'locked' then 'pin_locked' else v.err end); end if;
  begin
    if e.id is null then
      insert into public.time_entries (staff_id, clock_in) values (v.sid, now()) returning * into e;
      made := true;
    end if;
    select * into m from public._prov_mint(v.sid, v.sname, e.id, e.clock_in, public._prov_station(p_station), 'pin');
    return jsonb_build_object('ok', true, 'token', m.token, 'staff_id', v.sid, 'staff_name', v.sname, 'expires_at', m.expires_at, 'clocked_in', made);
  exception when others then
    get stacked diagnostics e1 = returned_sqlstate, e2 = message_text, e3 = pg_exception_detail, e4 = constraint_name;
    r := public._prov_caught(e1, e2, e3, e4); if r is null then raise; end if; return r;
  end;
end $$;
-- the POS's «¿Quién cobra?» on this same device and login: a session without typing anything
create or replace function public.turno_desde_caja(p_operator_token text, p_station text default null)
returns jsonb language plpgsql volatile security definer set search_path = public, extensions as $$
declare o public.operator_sessions; s public.staff; e public.time_entries; js text := public._jwt_session(); m record; why text;
        e1 text; e2 text; e3 text; e4 text; r jsonb;
begin
  if not public.is_cafe() then return '{"ok":false,"error":"no_account"}'::jsonb; end if;
  if js is null then why := 'no_session';
  else
    if coalesce(p_operator_token, '') <> '' and char_length(p_operator_token) <= 200 then
      select * into o from public.operator_sessions x where x.token_hash = encode(digest(p_operator_token, 'sha256'), 'hex')
         and x.ended_at is null and x.expires_at > now() and x.user_id is not null and x.user_id = auth.uid();
    end if;
    if o.id is null then why := 'unknown';
    else
      select * into s from public.staff where id = o.staff_id;
      select * into e from public.time_entries t where t.staff_id = o.staff_id and t.clock_out is null
         and t.clock_in > now() - interval '16 hours' and t.clock_in <= now() + interval '5 minutes' order by t.clock_in desc limit 1;
      why := case when not coalesce(s.active, false) then 'inactive' when s.pin_hash is null then 'pin_changed' when e.id is null then 'not_on_shift'
                  when exists (select 1 from public.work_sessions w where w.session_id = js and w.ended_at is null) then 'device_taken' end;
    end if;
  end if;
  if why is not null then return jsonb_build_object('ok', false, 'error', 'no_session', 'why', why); end if;
  begin
    select * into m from public._prov_mint(s.id, s.name, e.id, e.clock_in, public._prov_station(p_station), 'caja');
    return jsonb_build_object('ok', true, 'token', m.token, 'staff_id', s.id, 'staff_name', s.name, 'expires_at', m.expires_at, 'clocked_in', false);
  exception when others then
    get stacked diagnostics e1 = returned_sqlstate, e2 = message_text, e3 = pg_exception_detail, e4 = constraint_name;
    r := public._prov_caught(e1, e2, e3, e4); if r is null then raise; end if; return r;
  end;
end $$;
-- which of this device's tokens are good; the only place a session follows its login to a new sign-in, and then the
-- token rotates (a copy of the old one stops working). i = the token's place in p_tokens, from 0
create or replace function public.turno_estado(p_tokens text[])
returns jsonb language plpgsql volatile security definer set search_path = public, extensions as $$
declare t record; w public.work_sessions; i int; res jsonb := '[]'; tok text; js text := public._jwt_session(); why text;
begin
  if not public.is_cafe() then return '{"ok":false,"error":"no_account"}'::jsonb; end if;
  if coalesce(cardinality(p_tokens), 0) > 20 then return '{"ok":false,"error":"bad_request"}'::jsonb; end if;
  for i in 1 .. coalesce(cardinality(p_tokens), 0) loop
    select * into t from public._prov_turno(p_tokens[i]);
    tok := null; why := t.why;
    if why = 'moved' then
      select * into w from public.work_sessions where id = t.wid for update;
      why := case when w.ended_at is not null then 'ended'
                  when w.last_used_at > now() - interval '2 minutes' then 'in_use_elsewhere'
                  when (select count(*) from public.audit_log a where a.action = 'work_session_rebound' and a.target_id = w.id::text
                          and a.at > now() - interval '1 hour') >= 6 then 'too_many_rebinds'
                  when exists (select 1 from public.work_sessions x where x.session_id = js and x.ended_at is null) then 'device_taken' end;
      if why is null then
        begin
          tok := encode(gen_random_bytes(32), 'hex');
          update public.work_sessions set token_hash = encode(digest(tok, 'sha256'), 'hex'), session_id = js, rebinds = rebinds + 1,
                 last_rebind_at = now(), last_used_at = now() where id = w.id;
          perform public._prov_log('work_session_rebound', w.staff_id, w.staff_name, w.id::text,
            'Recibe en este aparato: ' || w.staff_name || ' · nuevo inicio de sesión',
            jsonb_build_object('from_tag', public._discount_tag(w.session_id), 'to_tag', public._discount_tag(js), 'station', w.station));
        exception when unique_violation then tok := null; why := 'device_taken';
        end;
      end if;
    end if;
    res := res || jsonb_build_array(jsonb_strip_nulls(jsonb_build_object('i', i - 1, 'ok', why is null,
             'staff_id', case when why is null then t.sid end, 'staff_name', case when why is null then t.sname end,
             'expires_at', case when why is null then (select x.expires_at from public.work_sessions x where x.id = t.wid) end,
             'why', why, 'token', tok)));
  end loop;
  return jsonb_build_object('ok', true, 'sessions', res);
end $$;
-- «Salir de este aparato»
create or replace function public.turno_terminar(p_token text)
returns jsonb language plpgsql volatile security definer set search_path = public, extensions as $$
declare w public.work_sessions;
begin
  if coalesce(p_token, '') = '' or char_length(p_token) > 200 then return '{"ok":true}'::jsonb; end if;
  select * into w from public.work_sessions where token_hash = encode(digest(p_token, 'sha256'), 'hex') for update;
  if w.id is null or w.ended_at is not null then return '{"ok":true}'::jsonb; end if;
  if w.login_id is distinct from auth.uid() then return '{"ok":false,"error":"locked"}'::jsonb; end if;
  update public.work_sessions set ended_at = now(), ended_how = 'signed_out' where id = w.id;
  perform public._prov_log('work_session_end', w.staff_id, w.staff_name, w.id::text, 'Recibe en este aparato: ' || w.staff_name || ' · salió de este aparato',
    jsonb_build_object('how', 'signed_out', 'station', w.station, 'session_tag', public._discount_tag(public._jwt_session())));
  return '{"ok":true}'::jsonb;
end $$;

-- 6) suppliers and their catalog (management) ---
-- partial update; SINPE only at owner level or the books' door; repeat create (same id, nothing new) → repeat
create or replace function public.proveedor_guardar(p_vendor jsonb)
returns jsonb language plpgsql volatile security definer set search_path = public, extensions as $$
declare p jsonb := p_vendor; vid uuid; v public.vendors; nv public.vendors; k text; n numeric; dup uuid; who text := public._prov_actor();
        s0 text; s1 text; ch boolean; res jsonb; e1 text; e2 text; e3 text; e4 text; r jsonb;
begin
  if jsonb_typeof(p) is distinct from 'object' then return '{"ok":false,"error":"bad_request"}'::jsonb; end if;
  if not (public._prov_manage() or (acct.can_read() and not exists (select 1 from jsonb_object_keys(p) x where x not in ('id', 'sinpe')))) then
    return '{"ok":false,"error":"locked"}'::jsonb; end if;
  begin
    for k in select jsonb_object_keys(p) loop
      if k not in ('id', 'name', 'contact_name', 'phone', 'whatsapp', 'email', 'notes', 'lead_days', 'order_days', 'credit_days', 'active', 'sinpe') then
        perform public._prov_fail('bad_request'); end if;
    end loop;
    vid := public._prov_id(p->'id');
    if vid is null then perform public._prov_fail('bad_request'); end if;
    select * into v from public.vendors where id = vid for update;
    if v.id is null and not public._prov_manage() then perform public._prov_fail('not_found'); end if;
    nv := v;
    if v.id is null then nv.id := vid; nv.lead_days := 2; nv.active := true; nv.created_at := now(); end if;
    if p ? 'name' then nv.name := public._prov_txt(p->'name', 80); end if;
    if nv.name is null then perform public._prov_fail('bad_request'); end if;
    if p ? 'contact_name' then nv.contact_name := public._prov_txt(p->'contact_name', 80); end if;
    if p ? 'phone' then nv.phone := public._prov_txt(p->'phone', 40); end if;
    if p ? 'whatsapp' then nv.whatsapp := public._prov_txt(p->'whatsapp', 40); end if;
    if p ? 'email' then nv.email := public._prov_txt(p->'email', 120); end if;
    if p ? 'notes' then nv.notes := public._prov_txt(p->'notes', 500); end if;
    if p ? 'order_days' then nv.order_days := public._prov_txt(p->'order_days', 60); end if;
    if p ? 'lead_days' then
      n := public._prov_num(p->'lead_days');
      if n is null or n <> trunc(n) or n < 0 or n > 60 then perform public._prov_fail('bad_request'); end if;
      nv.lead_days := n;
    end if;
    if p ? 'credit_days' then
      n := public._prov_num(p->'credit_days');
      if n is not null and (n <> trunc(n) or n < 0 or n > 180) then perform public._prov_fail('bad_request'); end if;
      nv.credit_days := n;
    end if;
    if p ? 'active' then
      nv.active := public._prov_bool(p->'active');
      if nv.active is null then perform public._prov_fail('bad_request'); end if;
    end if;
    if nv.active and (v.id is null or not v.active or lower(nv.name) <> lower(btrim(v.name))) then
      select x.id into dup from public.vendors x where x.id <> vid and x.active and lower(btrim(x.name)) = lower(nv.name) limit 1;
      if dup is not null then perform public._prov_fail('duplicate_name', jsonb_build_object('id', dup)); end if;
    end if;
    -- how the supplier is paid
    if p ? 'sinpe' then
      if not (public.is_true_owner() or acct.can_read()) then perform public._prov_fail('needs_owner'); end if;
      s1 := public._prov_txt(p->'sinpe', 120);
      select sinpe into s0 from public.vendor_pay_info where vendor_id = vid for update;
    end if;
    ch := v.id is null or to_jsonb(nv) is distinct from to_jsonb(v);
    if not ch and s0 is not distinct from s1 then return jsonb_build_object('ok', true, 'id', vid, 'repeat', true); end if;
    if v.id is null then
      insert into public.vendors (id, name, contact_name, phone, whatsapp, email, lead_days, order_days, notes, active, credit_days)
        values (vid, nv.name, nv.contact_name, nv.phone, nv.whatsapp, nv.email, nv.lead_days, nv.order_days, nv.notes, nv.active, nv.credit_days);
    elsif ch then
      update public.vendors set name = nv.name, contact_name = nv.contact_name, phone = nv.phone, whatsapp = nv.whatsapp, email = nv.email,
             lead_days = nv.lead_days, order_days = nv.order_days, notes = nv.notes, active = nv.active, credit_days = nv.credit_days where id = vid;
    end if;
    if ch then
      perform public._prov_log('vendor_save', null, who, vid::text, 'Proveedor ' || nv.name || case when v.id is null then ' · nuevo' else ' · cambios' end,
        jsonb_build_object('before', (select jsonb_object_agg(key, value) from jsonb_each(to_jsonb(v)) where to_jsonb(nv)->key is distinct from value),
                           'after', (select jsonb_object_agg(key, value) from jsonb_each(to_jsonb(nv)) where to_jsonb(v)->key is distinct from value)));
    end if;
    if p ? 'sinpe' and s0 is distinct from s1 then
      insert into public.vendor_pay_info (vendor_id, sinpe, updated_at, updated_by) values (vid, s1, now(), who)
        on conflict (vendor_id) do update set sinpe = excluded.sinpe, updated_at = now(), updated_by = excluded.updated_by;
      perform public._prov_log('vendor_sinpe', null, who, vid::text, 'SINPE de ' || nv.name || ' cambiado',
        jsonb_build_object('before', s0, 'after', s1));
    end if;
    res := jsonb_build_object('ok', true, 'id', vid);
    if v.id is not null and v.active and not nv.active then
      res := res || jsonb_build_object('open_orders', (select count(*) from public.purchase_orders o where o.vendor_id = vid
                                                         and o.status in ('draft', 'sent', 'partially_received')));
    end if;
    return res;
  exception when others then
    get stacked diagnostics e1 = returned_sqlstate, e2 = message_text, e3 = pg_exception_detail, e4 = constraint_name;
    r := public._prov_caught(e1, e2, e3, e4); if r is null then raise; end if; return r;
  end;
end $$;

-- a row of a supplier's catalog (or a new stock item with it); the authorized way to change a catalog price
create or replace function public.proveedor_producto_guardar(p_item jsonb)
returns jsonb language plpgsql volatile security definer set search_path = public, extensions as $$
declare p jsonb := p_item; ni jsonb; rid uuid; x public.vendor_items; nx public.vendor_items; it public.stock_items; nm text; un text; dup uuid; k text;
        n numeric; pref boolean; made boolean := false; rp numeric; par numeric; who text := public._prov_actor(); e1 text; e2 text; e3 text; e4 text; r jsonb;
begin
  if jsonb_typeof(p) is distinct from 'object' then return '{"ok":false,"error":"bad_request"}'::jsonb; end if;
  if not public._prov_manage() then return '{"ok":false,"error":"locked"}'::jsonb; end if;
  begin
    for k in select jsonb_object_keys(p) loop
      if k not in ('id', 'vendor_id', 'item_id', 'new_item', 'vendor_code', 'label', 'pack_label', 'pack_qty', 'usual_price', 'usual_qty', 'active', 'preferred') then
        perform public._prov_fail('bad_request'); end if;
    end loop;
    rid := public._prov_id(p->'id');
    if rid is null then perform public._prov_fail('bad_request'); end if;
    select * into x from public.vendor_items where id = rid for update;
    if x.id is not null then
      nx := x;
      if (p ? 'vendor_id' and public._prov_id(p->'vendor_id') is distinct from x.vendor_id)
         or (p ? 'item_id' and public._prov_id(p->'item_id') is distinct from x.item_id) or p ? 'new_item' then
        perform public._prov_fail('bad_request'); end if;
      select * into it from public.stock_items where id = x.item_id;
    else
      nx.id := rid; nx.vendor_id := public._prov_id(p->'vendor_id'); nx.active := true;
      if nx.vendor_id is null or (p ? 'item_id') = (p ? 'new_item') then perform public._prov_fail('bad_request'); end if;
      if not exists (select 1 from public.vendors where id = nx.vendor_id) then perform public._prov_fail('not_found'); end if;
      if p ? 'item_id' then
        select * into it from public.stock_items where id = public._prov_id(p->'item_id');
        if it.id is null then perform public._prov_fail('not_found'); end if;
        if not it.active then perform public._prov_fail('item_inactive'); end if;
      else
        ni := p->'new_item';
        if jsonb_typeof(ni) is distinct from 'object'
           or exists (select 1 from jsonb_object_keys(ni) y where y not in ('name', 'unit', 'category', 'reorder_point', 'par_level')) then
          perform public._prov_fail('bad_request'); end if;
        nm := public._prov_txt(ni->'name', 80);
        un := coalesce(public._prov_txt(ni->'unit', 10), 'unit');
        rp := coalesce(public._prov_num(ni->'reorder_point'), 0); par := coalesce(public._prov_num(ni->'par_level'), 0);
        if nm is null or un not in ('unit', 'g', 'kg', 'ml', 'L') then perform public._prov_fail('bad_request'); end if;
        if rp < 0 or par < 0 or rp > 1e9 or par > 1e9 then perform public._prov_fail('bad_qty'); end if;
        select y.id into dup from public.stock_items y where y.active and lower(btrim(y.name)) = lower(nm) order by y.created_at limit 1;
        if dup is not null then perform public._prov_fail('duplicate_item', jsonb_build_object('item_id', dup)); end if;
        made := true;
      end if;
    end if;
    if p ? 'vendor_code' then nx.vendor_code := public._prov_txt(p->'vendor_code', 40); end if;
    if p ? 'label' then nx.label := public._prov_txt(p->'label', 80); end if;
    if p ? 'pack_label' then nx.pack_label := public._prov_txt(p->'pack_label', 60); end if;
    if p ? 'pack_qty' then
      n := public._prov_num(p->'pack_qty');
      if n is null or n <= 0 or n >= 1e9 then perform public._prov_fail('bad_qty'); end if;
      nx.pack_qty := n;
    end if;
    if nx.pack_qty is null then perform public._prov_fail('bad_qty'); end if;
    if p ? 'usual_price' then nx.usual_price := round(public._prov_price(p->'usual_price'), 2); end if;
    if p ? 'usual_qty' then
      n := public._prov_num(p->'usual_qty');
      if n is not null and (n <= 0 or n > 100000) then perform public._prov_fail('bad_qty'); end if;
      nx.usual_qty := n;
    end if;
    if p ? 'active' then
      nx.active := public._prov_bool(p->'active');
      if nx.active is null then perform public._prov_fail('bad_request'); end if;
    end if;
    pref := public._prov_bool(p->'preferred');
    if pref and not nx.active then perform public._prov_fail('bad_request'); end if;
    if made then
      insert into public.stock_items (name, unit, category, pack_label, pack_qty, cost_per_pack, avg_cost, reorder_point, par_level, active)
        values (nm, un, coalesce(public._prov_txt(ni->'category', 40), 'other'), nx.pack_label, nx.pack_qty, coalesce(nx.usual_price, 0),
                nullif(round(coalesce(nx.usual_price, 0) / nx.pack_qty, 4), 0), rp, par, true)
        returning * into it;
      perform public._prov_log('stock_item_create', null, who, it.id::text, 'Producto nuevo desde Proveedores: ' || it.name,
        jsonb_build_object('name', it.name, 'unit', it.unit, 'pack_qty', it.pack_qty, 'cost_per_pack', it.cost_per_pack, 'vendor_id', nx.vendor_id));
    end if;
    nx.item_id := it.id;
    if nx.active then
      select z.id into dup from public.vendor_items z where z.vendor_id = nx.vendor_id and z.item_id = nx.item_id and z.pack_qty = nx.pack_qty
         and z.active and z.id <> nx.id;
      if dup is not null then perform public._prov_fail('duplicate_product', jsonb_build_object('id', dup)); end if;
    end if;
    if x.id is null then
      insert into public.vendor_items (id, vendor_id, item_id, vendor_code, label, pack_label, pack_qty, usual_price, usual_qty, active, created_by, updated_by)
        values (nx.id, nx.vendor_id, nx.item_id, nx.vendor_code, nx.label, nx.pack_label, nx.pack_qty, nx.usual_price, nx.usual_qty, nx.active, who, who);
    elsif to_jsonb(nx) is distinct from to_jsonb(x) then
      update public.vendor_items set vendor_code = nx.vendor_code, label = nx.label, pack_label = nx.pack_label, pack_qty = nx.pack_qty,
             usual_price = nx.usual_price, usual_qty = nx.usual_qty, active = nx.active, updated_at = now(), updated_by = who where id = nx.id;
    end if;
    if x.id is null or to_jsonb(nx) is distinct from to_jsonb(x) then
      perform public._prov_log('vendor_item_save', null, who, nx.id::text, it.name || coalesce(' · ' || nx.pack_label, '') || case when x.id is null then ' · nuevo en el catálogo' else ' · cambios' end,
        jsonb_build_object('vendor_id', nx.vendor_id, 'item_id', nx.item_id,
                           'before', case when x.id is not null then jsonb_build_object('usual_price', x.usual_price, 'pack_qty', x.pack_qty, 'active', x.active) end,
                           'after', jsonb_build_object('usual_price', nx.usual_price, 'pack_qty', nx.pack_qty, 'active', nx.active)));
    end if;
    -- the preferred supplier is the item's own (stock_items.vendor_id); a new item gets its first supplier
    if (pref or made) and it.vendor_id is distinct from nx.vendor_id then
      update public.stock_items set vendor_id = nx.vendor_id where id = it.id;
      perform public._prov_log('preferred_vendor', null, who, it.id::text, it.name || ': proveedor preferido',
        jsonb_build_object('before', it.vendor_id, 'after', nx.vendor_id));
    elsif pref is false and it.vendor_id = nx.vendor_id then
      update public.stock_items set vendor_id = null where id = it.id;
      perform public._prov_log('preferred_vendor', null, who, it.id::text, it.name || ': sin proveedor preferido',
        jsonb_build_object('before', it.vendor_id, 'after', null));
    end if;
    return jsonb_build_object('ok', true, 'id', nx.id, 'item_id', it.id);
  exception when others then
    get stacked diagnostics e1 = returned_sqlstate, e2 = message_text, e3 = pg_exception_detail, e4 = constraint_name;
    r := public._prov_caught(e1, e2, e3, e4); if r is null then raise; end if; return r;
  end;
end $$;

-- 7) drafts: one open draft per supplier, lines rebuilt as [{vendor_item_id, packs}] ---
create or replace function public._prov_draft_json(d public.purchase_drafts) returns jsonb language sql stable set search_path = public as $$
  select case when d.id is not null then jsonb_build_object('id', d.id, 'version', d.version, 'note', d.note, 'lines', d.lines,
                                                            'updated_at', d.updated_at, 'updated_by', d.updated_by) end $$;
-- the payload's lines, checked: this supplier's live rows, no repeats, 1..200 (p_min 0 for a draft)
create or replace function public._prov_draft_lines(p_vendor uuid, p_lines jsonb, p_min int) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare l jsonb; res jsonb := '[]'; u uuid; seen uuid[] := '{}'; n numeric;
begin
  if p_lines is null or jsonb_typeof(p_lines) = 'null' then p_lines := '[]'; end if;
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) > 200 then perform public._prov_fail('bad_request'); end if;
  if jsonb_array_length(p_lines) < p_min then perform public._prov_fail('empty'); end if;
  for l in select * from jsonb_array_elements(p_lines) loop
    if jsonb_typeof(l) <> 'object' then perform public._prov_fail('bad_request'); end if;
    u := public._prov_id(l->'vendor_item_id');
    n := public._prov_packs(l->'packs', false, 'bad_qty');
    if u is null or n is null then perform public._prov_fail('bad_request'); end if;
    if u = any(seen) then perform public._prov_fail('duplicate_line', jsonb_build_object('vendor_item_id', u)); end if;
    if not exists (select 1 from public.vendor_items v where v.id = u and v.vendor_id = p_vendor and v.active) then
      perform public._prov_fail('not_found', jsonb_build_object('vendor_item_id', u)); end if;
    seen := seen || u; res := res || jsonb_build_array(jsonb_build_object('vendor_item_id', u, 'packs', n));
  end loop;
  return res;
end $$;
create or replace function public.proveedor_borrador_guardar(p_vendor_id uuid, p_lines jsonb, p_note text, p_version int)
returns jsonb language plpgsql volatile security definer set search_path = public, extensions as $$
declare d public.purchase_drafts; u public.purchase_drafts; ls jsonb; nt text := nullif(btrim(coalesce(p_note, '')), ''); who text := public._prov_actor();
        e1 text; e2 text; e3 text; e4 text; r jsonb;
begin
  if not public._prov_manage() then return '{"ok":false,"error":"locked"}'::jsonb; end if;
  begin
    if not exists (select 1 from public.vendors where id = p_vendor_id) then perform public._prov_fail('not_found'); end if;
    if char_length(nt) > 500 then perform public._prov_fail('bad_request'); end if;
    ls := public._prov_draft_lines(p_vendor_id, p_lines, 0);
    select * into d from public.purchase_drafts where vendor_id = p_vendor_id and status = 'open' for update;
    if d.id is not null and d.version is distinct from p_version then
      perform public._prov_fail('changed', jsonb_build_object('draft', public._prov_draft_json(d))); end if;
    if d.id is null and coalesce(p_version, 0) > 0 then
      select * into u from public.purchase_drafts where vendor_id = p_vendor_id order by updated_at desc, id limit 1;
      if u.status = 'used' then perform public._prov_fail('draft_used', jsonb_build_object('po_id', u.po_id)); end if;
    end if;
    if jsonb_array_length(ls) = 0 and nt is null then
      if d.id is not null then
        update public.purchase_drafts set status = 'discarded', version = version + 1, updated_at = now(), updated_by = who where id = d.id;
      end if;
      return '{"ok":true,"discarded":true}'::jsonb;
    end if;
    if d.id is null then
      insert into public.purchase_drafts (vendor_id, lines, note, created_by, updated_by) values (p_vendor_id, ls, nt, who, who) returning * into d;
    else
      update public.purchase_drafts set lines = ls, note = nt, version = version + 1, updated_at = now(), updated_by = who where id = d.id returning * into d;
    end if;
    return jsonb_build_object('ok', true, 'id', d.id, 'version', d.version, 'updated_at', d.updated_at);
  exception when others then
    get stacked diagnostics e1 = returned_sqlstate, e2 = message_text, e3 = pg_exception_detail, e4 = constraint_name;
    r := public._prov_caught(e1, e2, e3, e4); if r is null then raise; end if;
    if e4 = 'purchase_drafts_open' then   -- another device created it a moment ago: the winner's draft
      r := r || jsonb_build_object('draft', (select public._prov_draft_json(x) from public.purchase_drafts x where x.vendor_id = p_vendor_id and x.status = 'open'));
    end if;
    return r;
  end;
end $$;
create or replace function public.proveedor_borrador_descartar(p_vendor_id uuid, p_version int)
returns jsonb language plpgsql volatile security definer set search_path = public, extensions as $$
declare d public.purchase_drafts;
begin
  if not public._prov_manage() then return '{"ok":false,"error":"locked"}'::jsonb; end if;
  select * into d from public.purchase_drafts where vendor_id = p_vendor_id and status = 'open' for update;
  if d.id is null then return '{"ok":true,"discarded":true}'::jsonb; end if;
  if d.version is distinct from p_version then return jsonb_build_object('ok', false, 'error', 'changed', 'draft', public._prov_draft_json(d)); end if;
  update public.purchase_drafts set status = 'discarded', version = version + 1, updated_at = now(), updated_by = public._prov_actor() where id = d.id;
  return '{"ok":true,"discarded":true}'::jsonb;
end $$;

-- 8) orders (management) ---
-- what the page needs after a refusal: the order's version, status and what is pending per line
create or replace function public._prov_po_state(p_po_id uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('version', o.version, 'status', o.status,
           'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'received_qty', l.received_qty, 'pending_packs', l.pending_packs)
                                              order by coalesce(l.pos, 1000000), l.id), '[]') from public._prov_lines(o.id) l))
    from public.purchase_orders o where o.id = p_po_id $$;
-- a new order line from a live catalog row of the order's supplier: base units counted on the server (2 boxes of 12 →
-- 24), the price per base unit kept twice (the expected one, which a delivery never changes, and the one at order time)
create or replace function public._prov_new_line(p_po public.purchase_orders, p_l jsonb, p_pos int) returns uuid
language plpgsql volatile security definer set search_path = public as $$
declare vi public.vendor_items; ok boolean; n numeric; pp numeric; lid uuid;
begin
  select * into vi from public.vendor_items where id = public._prov_id(p_l->'vendor_item_id') and vendor_id = p_po.vendor_id and active;
  if vi.id is null then perform public._prov_fail('not_found', jsonb_build_object('vendor_item_id', p_l->'vendor_item_id')); end if;
  select active into ok from public.stock_items where id = vi.item_id;
  if not ok then perform public._prov_fail('item_inactive', jsonb_build_object('vendor_item_id', vi.id)); end if;
  n := public._prov_packs(p_l->'packs', false, 'bad_qty');
  if n is null then perform public._prov_fail('bad_qty', jsonb_build_object('vendor_item_id', vi.id)); end if;
  pp := coalesce(public._prov_price(p_l->'pack_price'), vi.usual_price);
  if pp is null or (pp = 0 and not coalesce(public._prov_bool(p_l->'free'), false)) then
    perform public._prov_fail('needs_price', jsonb_build_object('vendor_item_id', vi.id)); end if;
  insert into public.purchase_lines (po_id, item_id, packs, qty, unit_cost, ordered_unit_cost, vendor_item_id, pack_label, pack_qty, pos)
    values (p_po.id, vi.item_id, n, round(n * vi.pack_qty, 4), round(pp / vi.pack_qty, 6), round(pp / vi.pack_qty, 6), vi.id, vi.pack_label, vi.pack_qty, p_pos)
    returning id into lid;
  return lid;
end $$;
create or replace function public.proveedor_pedido_crear(p_vendor_id uuid, p_lines jsonb, p_note text, p_request_id uuid,
                                                         p_draft_version int default null, p_expected_on date default null)
returns jsonb language plpgsql volatile security definer set search_path = public, extensions as $$
declare po public.purchase_orders; d public.purchase_drafts; v public.vendors; l jsonb; seen uuid[] := '{}'; u uuid; i int := 0;
        nt text := nullif(btrim(coalesce(p_note, '')), ''); who text := public._prov_actor(); e1 text; e2 text; e3 text; e4 text; r jsonb;
begin
  if not public._prov_manage() then return '{"ok":false,"error":"locked"}'::jsonb; end if;
  if p_request_id is null or p_vendor_id is null then return '{"ok":false,"error":"bad_request"}'::jsonb; end if;
  begin
    if p_draft_version is not null then
      select * into d from public.purchase_drafts where vendor_id = p_vendor_id and status = 'open' for update;   -- first: two devices never both use it
    end if;
    select * into po from public.purchase_orders where id = p_request_id;
    if po.id is not null then
      if po.vendor_id is distinct from p_vendor_id then perform public._prov_fail('bad_request'); end if;
      return jsonb_build_object('ok', true, 'repeat', true, 'id', po.id, 'po_number', po.po_number, 'version', po.version);
    end if;
    if p_draft_version is not null then
      if d.id is null then
        select * into d from public.purchase_drafts where vendor_id = p_vendor_id order by updated_at desc, id limit 1;
        if d.status = 'used' then perform public._prov_fail('draft_used', jsonb_build_object('po_id', d.po_id)); end if;
        perform public._prov_fail('draft_changed', jsonb_build_object('draft', null));
      end if;
      if d.version <> p_draft_version then perform public._prov_fail('draft_changed', jsonb_build_object('draft', public._prov_draft_json(d))); end if;
    end if;
    select * into v from public.vendors where id = p_vendor_id;
    if v.id is null then perform public._prov_fail('not_found'); end if;
    if not v.active then perform public._prov_fail('vendor_inactive'); end if;
    if char_length(nt) > 500 then perform public._prov_fail('bad_request'); end if;
    if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) > 200 then perform public._prov_fail('bad_request'); end if;
    if jsonb_array_length(p_lines) = 0 then perform public._prov_fail('empty'); end if;
    for l in select * from jsonb_array_elements(p_lines) loop
      if jsonb_typeof(l) <> 'object' then perform public._prov_fail('bad_request'); end if;
      u := public._prov_id(l->'vendor_item_id');
      if u is null then perform public._prov_fail('bad_request'); end if;
      if u = any(seen) then perform public._prov_fail('duplicate_line', jsonb_build_object('vendor_item_id', u)); end if;
      seen := seen || u;
    end loop;
    insert into public.purchase_orders (id, vendor_id, status, sent_at, note, by_name, expected_on)
      values (p_request_id, v.id, 'sent', now(), nt, who, p_expected_on) returning * into po;
    for l in select * from jsonb_array_elements(p_lines) loop
      i := i + 1; perform public._prov_new_line(po, l, i);
    end loop;
    if d.id is not null then
      update public.purchase_drafts set status = 'used', po_id = po.id, version = version + 1, updated_at = now(), updated_by = who where id = d.id;
    end if;
    select * into po from public.purchase_orders where id = po.id;
    perform public._prov_log('po_create', null, who, po.id::text, 'pedido Nº ' || po.po_number || ' · ' || v.name || ' · ' || i || ' líneas',
      jsonb_build_object('vendor_id', v.id, 'lines', i, 'draft_id', d.id, 'expected_on', p_expected_on));
    return jsonb_build_object('ok', true, 'id', po.id, 'po_number', po.po_number, 'version', po.version);
  exception when others then
    get stacked diagnostics e1 = returned_sqlstate, e2 = message_text, e3 = pg_exception_detail, e4 = constraint_name;
    if e4 = 'purchase_orders_pkey' then     -- the same request from another device a moment ago
      return (select jsonb_build_object('ok', true, 'repeat', true, 'id', x.id, 'po_number', x.po_number, 'version', x.version)
                from public.purchase_orders x where x.id = p_request_id);
    end if;
    r := public._prov_caught(e1, e2, e3, e4); if r is null then raise; end if; return r;
  end;
end $$;
-- p_lines (when given) = the whole list of live lines wanted: [{line_id?, vendor_item_id?, packs, pack_price?, free?}]
create or replace function public.proveedor_pedido_editar(p_po_id uuid, p_version int, p_lines jsonb default null, p_note text default null,
                                                          p_expected_on date default null)
returns jsonb language plpgsql volatile security definer set search_path = public, extensions as $$
declare po public.purchase_orders; ln record; l jsonb; lid uuid; keep uuid[] := '{}'; seen uuid[] := '{}'; u uuid; n numeric; q numeric; pp numeric;
        chg jsonb := '[]'; sm text[] := '{}'; i int; nt text; who text := public._prov_actor(); e1 text; e2 text; e3 text; e4 text; r jsonb;
begin
  if not public._prov_manage() then return '{"ok":false,"error":"locked"}'::jsonb; end if;
  begin
    select * into po from public.purchase_orders where id = p_po_id for update;
    if po.id is null then perform public._prov_fail('not_found'); end if;
    if po.version is distinct from p_version then perform public._prov_fail('changed', jsonb_build_object('order', public._prov_po_state(po.id))); end if;
    perform 1 from public.purchase_lines where po_id = po.id order by id for update;
    if p_lines is not null and jsonb_typeof(p_lines) <> 'null' then
      if po.status in ('received', 'cancelled') then perform public._prov_fail('closed'); end if;
      if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) > 200 then perform public._prov_fail('bad_request'); end if;
      for l in select * from jsonb_array_elements(p_lines) loop
        if jsonb_typeof(l) <> 'object' then perform public._prov_fail('bad_request'); end if;
        lid := public._prov_id(l->'line_id');
        if lid is not null then
          if lid = any(keep) then perform public._prov_fail('duplicate_line', jsonb_build_object('line_id', lid)); end if;
          keep := keep || lid;
        else
          u := public._prov_id(l->'vendor_item_id');
          if u is null then perform public._prov_fail('bad_request'); end if;
          if u = any(seen) then perform public._prov_fail('duplicate_line', jsonb_build_object('vendor_item_id', u)); end if;
          seen := seen || u;
        end if;
      end loop;
      if exists (select 1 from public._prov_lines(po.id) x where not x.removed and x.id = any(keep) and x.vendor_item_id = any(seen)) then
        perform public._prov_fail('duplicate_line'); end if;
      -- a live line left out is removed (never deleted); one with something received cannot be
      for ln in select * from public._prov_lines(po.id) x where not x.removed and x.id <> all(keep) loop
        if ln.received_qty > 0 then perform public._prov_fail('has_receipts', jsonb_build_object('line_id', ln.id)); end if;
        update public.purchase_lines set removed_at = now(), packs = 0, qty = 0 where id = ln.id;
        chg := chg || jsonb_build_array(jsonb_build_object('line_id', ln.id, 'item', ln.item_name, 'before', jsonb_build_object('packs', ln.packs, 'qty', ln.qty), 'after', 'removed'));
        sm := sm || (coalesce(ln.label, ln.item_name) || ' quitado');
      end loop;
      for l in select * from jsonb_array_elements(p_lines) e where public._prov_id(e->'line_id') is not null loop
        lid := public._prov_id(l->'line_id');
        select * into ln from public._prov_lines(po.id) x where x.id = lid;
        if ln.id is null then perform public._prov_fail('not_found', jsonb_build_object('line_id', lid)); end if;
        if ln.removed then perform public._prov_fail('removed_line', jsonb_build_object('line_id', lid)); end if;
        n := public._prov_packs(l->'packs', false, 'bad_qty');
        if n is null then perform public._prov_fail('bad_qty', jsonb_build_object('line_id', lid)); end if;
        q := round(n * ln.pack_qty, 4);
        if q < ln.received_qty then perform public._prov_fail('below_received', jsonb_build_object('line_id', lid, 'received_packs', ln.received_packs)); end if;
        pp := public._prov_price(l->'pack_price');
        if q <> ln.qty or n <> ln.packs or (pp is not null and round(pp / ln.pack_qty, 6) is distinct from ln.exp_unit) then
          update public.purchase_lines set packs = n, qty = q, unit_cost = coalesce(round(pp / ln.pack_qty, 6), unit_cost),
                 ordered_unit_cost = coalesce(round(pp / ln.pack_qty, 6), ordered_unit_cost) where id = lid;
          chg := chg || jsonb_build_array(jsonb_build_object('line_id', lid, 'item', ln.item_name,
                   'before', jsonb_build_object('packs', ln.packs, 'qty', ln.qty, 'pack_price', ln.expected_pack_price),
                   'after', jsonb_build_object('packs', n, 'qty', q, 'pack_price', coalesce(round(pp, 2), ln.expected_pack_price))));
          sm := sm || (coalesce(ln.label, ln.item_name) || case when n <> ln.packs then ' ' || trim_scale(ln.packs) || ' → ' || trim_scale(n) else '' end
                       || case when pp is not null and round(pp, 2) is distinct from ln.expected_pack_price
                               then ' precio ₡' || coalesce(trim_scale(ln.expected_pack_price)::text, '?') || ' → ₡' || trim_scale(round(pp, 2)) else '' end);
        end if;
      end loop;
      i := coalesce((select max(x.pos) from public.purchase_lines x where x.po_id = po.id), 0);
      for l in select * from jsonb_array_elements(p_lines) e where public._prov_id(e->'line_id') is null loop
        i := i + 1; lid := public._prov_new_line(po, l, i);
        chg := chg || jsonb_build_array(jsonb_build_object('line_id', lid, 'after', 'added', 'vendor_item_id', l->'vendor_item_id', 'packs', l->'packs'));
        sm := sm || (select coalesce(z.label, s.name) || ' agregado (' || trim_scale(x.packs) || ')' from public.purchase_lines x
                       join public.stock_items s on s.id = x.item_id left join public.vendor_items z on z.id = x.vendor_item_id where x.id = lid);
      end loop;
      if not exists (select 1 from public.purchase_lines x where x.po_id = po.id and x.removed_at is null) then perform public._prov_fail('empty'); end if;
      if po.status = 'partially_received' and not exists (select 1 from public.purchase_lines x where x.po_id = po.id and x.removed_at is null
                                                            and coalesce(x.received_qty, 0) < x.qty) then
        update public.purchase_orders set status = 'received', received_at = now() where id = po.id;
        chg := chg || jsonb_build_array(jsonb_build_object('status', jsonb_build_object('before', po.status, 'after', 'received')));
        sm := sm || 'completo'::text;
      end if;
    end if;
    if p_note is not null then
      nt := nullif(btrim(p_note), '');
      if char_length(nt) > 500 then perform public._prov_fail('bad_request'); end if;
      if nt is distinct from po.note then
        update public.purchase_orders set note = nt where id = po.id;
        chg := chg || jsonb_build_array(jsonb_build_object('note', jsonb_build_object('before', po.note, 'after', nt)));
        sm := sm || (case when nt is null then 'nota borrada' else 'nota cambiada' end);
      end if;
    end if;
    if p_expected_on is not null and p_expected_on is distinct from po.expected_on then
      update public.purchase_orders set expected_on = p_expected_on where id = po.id;
      chg := chg || jsonb_build_array(jsonb_build_object('expected_on', jsonb_build_object('before', po.expected_on, 'after', p_expected_on)));
      sm := sm || ('entrega ' || to_char(p_expected_on, 'DD/MM/YYYY'));
    end if;
    if jsonb_array_length(chg) > 0 then
      perform public._prov_log('po_edit', null, who, po.id::text, 'pedido Nº ' || po.po_number || ': ' || left(array_to_string(sm, '; '), 400),
        jsonb_build_object('changes', chg, 'status_before', po.status));
    end if;
    select * into po from public.purchase_orders where id = po.id;
    return jsonb_build_object('ok', true, 'version', po.version, 'status', po.status);
  exception when others then
    get stacked diagnostics e1 = returned_sqlstate, e2 = message_text, e3 = pg_exception_detail, e4 = constraint_name;
    r := public._prov_caught(e1, e2, e3, e4); if r is null then raise; end if; return r;
  end;
end $$;
-- the order row locked, at the version the page saw; else the refusal
create or replace function public._prov_po_lock(p_po_id uuid, p_version int) returns public.purchase_orders
language plpgsql volatile security definer set search_path = public as $$
declare po public.purchase_orders;
begin
  select * into po from public.purchase_orders where id = p_po_id for update;
  if po.id is null then perform public._prov_fail('not_found'); end if;
  if po.version is distinct from p_version then perform public._prov_fail('changed', jsonb_build_object('order', public._prov_po_state(po.id))); end if;
  return po;
end $$;
create or replace function public.proveedor_pedido_cancelar(p_po_id uuid, p_version int, p_reason text default null)
returns jsonb language plpgsql volatile security definer set search_path = public, extensions as $$
declare po public.purchase_orders; why text := nullif(btrim(coalesce(p_reason, '')), ''); e1 text; e2 text; e3 text; e4 text; r jsonb;
begin
  if not public._prov_manage() then return '{"ok":false,"error":"locked"}'::jsonb; end if;
  begin
    po := public._prov_po_lock(p_po_id, p_version);
    if char_length(why) > 200 then perform public._prov_fail('bad_request'); end if;
    if po.status = 'cancelled' then perform public._prov_fail('cancelled'); end if;
    if po.status = 'received' then perform public._prov_fail('closed'); end if;
    if po.status = 'partially_received' or exists (select 1 from public.purchase_receipts x where x.po_id = po.id) then
      perform public._prov_fail('has_receipts'); end if;
    update public.purchase_orders set status = 'cancelled' where id = po.id returning * into po;
    perform public._prov_log('po_cancel', null, public._prov_actor(), po.id::text, 'pedido Nº ' || po.po_number || ' cancelado' || coalesce(': ' || why, ''),
      jsonb_build_object('reason', why));
    return jsonb_build_object('ok', true, 'version', po.version, 'status', po.status);
  exception when others then
    get stacked diagnostics e1 = returned_sqlstate, e2 = message_text, e3 = pg_exception_detail, e4 = constraint_name;
    r := public._prov_caught(e1, e2, e3, e4); if r is null then raise; end if; return r;
  end;
end $$;
-- «Cerrar lo pendiente»: what did not come is not coming (the audit keeps what was missing per line)
create or replace function public._prov_close(p_po public.purchase_orders, p_reason text) returns public.purchase_orders
language plpgsql volatile security definer set search_path = public as $$
declare po public.purchase_orders;
begin
  if p_po.status = 'cancelled' then perform public._prov_fail('cancelled'); end if;
  if p_po.status = 'received' then perform public._prov_fail('already_received'); end if;
  if not exists (select 1 from public.purchase_receipts x where x.po_id = p_po.id) then perform public._prov_fail('no_receipts'); end if;
  update public.purchase_orders set status = 'received', received_at = now() where id = p_po.id returning * into po;
  perform public._prov_log('po_close', null, public._prov_actor(), po.id::text, 'pedido Nº ' || po.po_number || ': se cierra lo pendiente' || coalesce(': ' || p_reason, ''),
    jsonb_build_object('reason', p_reason, 'missing', (select coalesce(jsonb_agg(jsonb_build_object('line_id', l.id, 'item', l.item_name, 'pending_packs', l.pending_packs,
                                                                       'pending_qty', l.pending_qty)), '[]')
                                                         from public._prov_lines(po.id) l where not l.removed and l.pending_qty > 0)));
  return po;
end $$;
create or replace function public.proveedor_pedido_cerrar(p_po_id uuid, p_version int, p_reason text default null)
returns jsonb language plpgsql volatile security definer set search_path = public, extensions as $$
declare po public.purchase_orders; why text := nullif(btrim(coalesce(p_reason, '')), ''); e1 text; e2 text; e3 text; e4 text; r jsonb;
begin
  if not public._prov_manage() then return '{"ok":false,"error":"locked"}'::jsonb; end if;
  begin
    po := public._prov_po_lock(p_po_id, p_version);
    if char_length(why) > 200 then perform public._prov_fail('bad_request'); end if;
    po := public._prov_close(po, why);
    return jsonb_build_object('ok', true, 'version', po.version, 'status', po.status);
  exception when others then
    get stacked diagnostics e1 = returned_sqlstate, e2 = message_text, e3 = pg_exception_detail, e4 = constraint_name;
    r := public._prov_caught(e1, e2, e3, e4); if r is null then raise; end if; return r;
  end;
end $$;
-- an old page's draft order is sent
create or replace function public.proveedor_pedido_confirmar(p_po_id uuid, p_version int)
returns jsonb language plpgsql volatile security definer set search_path = public, extensions as $$
declare po public.purchase_orders; e1 text; e2 text; e3 text; e4 text; r jsonb;
begin
  if not public._prov_manage() then return '{"ok":false,"error":"locked"}'::jsonb; end if;
  begin
    po := public._prov_po_lock(p_po_id, p_version);
    if po.status = 'cancelled' then perform public._prov_fail('cancelled'); end if;
    if po.status <> 'draft' then return jsonb_build_object('ok', true, 'repeat', true, 'version', po.version, 'status', po.status); end if;
    if not exists (select 1 from public.purchase_lines x where x.po_id = po.id and x.removed_at is null and x.qty > 0) then perform public._prov_fail('empty'); end if;
    update public.purchase_orders set status = 'sent', sent_at = now() where id = po.id returning * into po;
    perform public._prov_log('po_confirm', null, public._prov_actor(), po.id::text, 'pedido Nº ' || po.po_number || ' creado (era un borrador)', '{}');
    return jsonb_build_object('ok', true, 'version', po.version, 'status', po.status);
  exception when others then
    get stacked diagnostics e1 = returned_sqlstate, e2 = message_text, e3 = pg_exception_detail, e4 = constraint_name;
    r := public._prov_caught(e1, e2, e3, e4); if r is null then raise; end if; return r;
  end;
end $$;
-- an order made without a supplier (old page) gets one, and so do its deliveries without one
create or replace function public.proveedor_pedido_asignar(p_po_id uuid, p_version int, p_vendor_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = public, extensions as $$
declare po public.purchase_orders; v public.vendors; e1 text; e2 text; e3 text; e4 text; r jsonb;
begin
  if not public._prov_manage() then return '{"ok":false,"error":"locked"}'::jsonb; end if;
  begin
    po := public._prov_po_lock(p_po_id, p_version);
    select * into v from public.vendors where id = p_vendor_id;
    if v.id is null then perform public._prov_fail('not_found'); end if;
    if po.vendor_id is not null then
      if po.vendor_id = v.id then return jsonb_build_object('ok', true, 'repeat', true, 'version', po.version, 'status', po.status); end if;
      perform public._prov_fail('bad_request');
    end if;
    if not v.active then perform public._prov_fail('vendor_inactive'); end if;
    if exists (select 1 from public.purchase_receipts r0 join public.purchase_receipts x on x.vendor_id = v.id and lower(x.invoice_no) = lower(r0.invoice_no)
                where r0.po_id = po.id and r0.vendor_id is null and r0.invoice_no is not null) then
      perform public._prov_fail('duplicate_invoice'); end if;
    update public.purchase_receipts set vendor_id = v.id where po_id = po.id and vendor_id is null;
    update public.purchase_orders set vendor_id = v.id where id = po.id returning * into po;
    perform public._prov_log('po_vendor_set', null, public._prov_actor(), po.id::text, 'pedido Nº ' || po.po_number || ': proveedor ' || v.name,
      jsonb_build_object('vendor_id', v.id));
    return jsonb_build_object('ok', true, 'version', po.version, 'status', po.status);
  exception when others then
    get stacked diagnostics e1 = returned_sqlstate, e2 = message_text, e3 = pg_exception_detail, e4 = constraint_name;
    r := public._prov_caught(e1, e2, e3, e4); if r is null then raise; end if; return r;
  end;
end $$;

-- 9) receiving: management, or the employee on shift on this device (no PIN in the call) ---
-- the day of a delivery that arrives after its register was closed is posted again (only the difference, as a re-close
-- does); never fails the delivery
create or replace function public._prov_late_post() returns void language plpgsql volatile security definer set search_path = acct, public as $$
declare s text;
begin
  if (public.setting('ledger_auto_post') #>> '{}') is distinct from 'true' then return; end if;
  begin
    s := nullif(public.setting('ledger_start_date') #>> '{}', '');
    if (s is null or public.cr_today() >= s::date)
       and exists (select 1 from public.register_days d where d.business_date = public.cr_today() and d.closed_at is not null) then
      perform acct.post_day(public.cr_today(), 'recepción después del cierre');
    end if;
  exception when others then
    insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
      values ('ledger_post_failed', null, 'sistema', public.cr_today()::text, left(sqlerrm, 200), '{}'::jsonb);
  end;
end $$;
create or replace function public.proveedor_recibir(p_po_id uuid, p_receipt_id uuid, p_version int, p_lines jsonb, p_token text default null,
    p_close boolean default false, p_invoice_no text default null, p_note text default null, p_extra_ok boolean default false,
    p_price_ok boolean default false)
returns jsonb language plpgsql volatile security definer set search_path = public, extensions as $$
declare t record; emp boolean; po public.purchase_orders; rc public.purchase_receipts; it public.stock_items; ln record; l jsonb; lid uuid;
        inv text := nullif(btrim(coalesce(p_invoice_no, '')), ''); nt text := nullif(btrim(coalesce(p_note, '')), ''); who text;
        seen uuid[] := '{}'; plan jsonb := '[]'; x jsonb; mv_id bigint; mv_uc numeric; n int := 0; total numeric := 0; done boolean; st text;
        xp numeric; pp numeric; uc numeric; q numeric; pk numeric; ex numeric; xr numeric; rest boolean; bp numeric; anyin boolean := false;
        diffs jsonb := '[]'; obs jsonb := '[]'; extra jsonb := '[]'; xrep jsonb := '[]'; miss jsonb := '[]'; det jsonb := '[]'; short jsonb;
        e1 text; e2 text; e3 text; e4 text; r jsonb;
begin
  select * into t from public._prov_turno(p_token);   -- (a null token: why «unknown»)
  emp := p_token is not null and t.why is null;
  if not emp and not public._prov_manage() then
    return case when p_token is not null then jsonb_build_object('ok', false, 'error', 'no_session', 'why', t.why) else '{"ok":false,"error":"locked"}'::jsonb end;
  end if;
  if p_receipt_id is null then return '{"ok":false,"error":"bad_request"}'::jsonb; end if;
  who := case when emp then t.sname || ' (en turno)' else public._prov_actor() end;
  begin
    select * into po from public.purchase_orders where id = p_po_id for update;
    if po.id is null then perform public._prov_fail('not_found'); end if;
    select * into rc from public.purchase_receipts where id = p_receipt_id;
    if rc.id is not null then
      if rc.po_id <> po.id then perform public._prov_fail('bad_request'); end if;
      return jsonb_build_object('ok', true, 'repeat', true, 'status', po.status, 'receipt_id', rc.id, 'version', po.version);
    end if;
    if po.status = 'cancelled' then perform public._prov_fail('cancelled'); end if;
    if po.status = 'received' then perform public._prov_fail('already_received'); end if;
    if emp and (po.status not in ('sent', 'partially_received') or po.vendor_id is null) then perform public._prov_fail('not_found'); end if;
    if po.version is distinct from p_version then perform public._prov_fail('changed', jsonb_build_object('order', public._prov_po_state(po.id))); end if;
    if char_length(inv) > 40 or char_length(nt) > 500 then perform public._prov_fail('bad_request'); end if;
    if inv is not null and exists (select 1 from public.purchase_receipts x where x.vendor_id is not distinct from po.vendor_id and lower(x.invoice_no) = lower(inv)) then
      perform public._prov_fail('duplicate_invoice'); end if;
    if p_lines is null or jsonb_typeof(p_lines) = 'null' then p_lines := '[]'; end if;
    if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) > 200 then perform public._prov_fail('bad_request'); end if;
    -- what each line brings, checked before anything is written
    for l in select * from jsonb_array_elements(p_lines) loop
      if jsonb_typeof(l) <> 'object' then perform public._prov_fail('bad_request'); end if;
      lid := public._prov_id(l->'line_id');
      if lid is null then perform public._prov_fail('bad_request'); end if;
      if lid = any(seen) then perform public._prov_fail('duplicate_line', jsonb_build_object('line_id', lid)); end if;
      seen := seen || lid;
      select * into ln from public._prov_lines(po.id) z where z.id = lid;
      if ln.id is null then perform public._prov_fail('not_found', jsonb_build_object('line_id', lid)); end if;
      rest := coalesce(public._prov_bool(l->'rest'), false);
      pk := public._prov_packs(l->'packs', true, 'bad_qty');
      ex := coalesce(public._prov_packs(l->'extra_packs', true, 'bad_qty'), 0);
      pp := public._prov_price(l->'pack_price');
      if ln.removed and (coalesce(pk, 0) > 0 or rest or ex > 0) then perform public._prov_fail('removed_line', jsonb_build_object('line_id', lid)); end if;
      q := case when rest then ln.pending_qty else round(coalesce(pk, 0) * ln.pack_qty, 4) end;
      if q > 0 and abs(q - ln.pending_qty) < 0.001 * ln.pack_qty then q := ln.pending_qty; end if;
      if not emp then q := q + round(ex * ln.pack_qty, 4); end if;
      xr := 0;
      if q > ln.pending_qty then
        if emp then xr := case when ex > 0 then ex else round((q - ln.pending_qty) / ln.pack_qty, 4) end; q := ln.pending_qty;
        elsif not coalesce(p_extra_ok, false) then
          perform public._prov_fail('over_pending', jsonb_build_object('line_id', lid, 'pending_packs', ln.pending_packs));
        else extra := extra || jsonb_build_array(jsonb_build_object('line_id', lid, 'item_name', ln.item_name, 'packs', round((q - ln.pending_qty) / ln.pack_qty, 4)));
        end if;
      elsif emp then xr := ex;
      end if;
      -- the price booked: management's typed price (checked against the expected one), else the expected one; an
      -- employee's typed price is only kept to be looked at
      xp := ln.expected_pack_price; uc := ln.exp_unit; bp := null;
      if pp is not null and not emp then
        if q > 0 and xp > 0 and (pp < xp / 3 or pp > xp * 3) and not coalesce(p_price_ok, false) then
          perform public._prov_fail('check_price', jsonb_build_object('line_id', lid, 'expected_pack_price', xp)); end if;
        uc := round(pp / ln.pack_qty, 6); bp := round(pp, 2);
      end if;
      if q > 0 and uc is null then
        select * into it from public.stock_items where id = ln.item_id;
        if not (coalesce(it.avg_cost, 0) > 0 or coalesce(it.cost_per_pack, 0) > 0) then
          if not emp then perform public._prov_fail('needs_price', jsonb_build_object('line_id', lid)); end if;
          miss := miss || jsonb_build_array(lid);
        end if;
      end if;
      if emp and pp is not null and round(pp, 2) is distinct from xp then
        obs := obs || jsonb_build_array(jsonb_build_object('line_id', lid, 'item_name', ln.item_name, 'expected_pack_price', xp, 'observed_pack_price', round(pp, 2)));
      end if;
      if xr > 0 then xrep := xrep || jsonb_build_array(jsonb_build_object('line_id', lid, 'item_name', ln.item_name, 'packs', xr)); end if;
      if q > 0 or xr > 0 or (emp and pp is not null) then
        plan := plan || jsonb_build_array(jsonb_build_object('line_id', lid, 'item_id', ln.item_id, 'item', ln.item_name, 'pqe', ln.pack_qty, 'qty', q,
                  'uc', uc, 'typed', bp is not null, 'xp', xp, 'obs', case when emp then round(pp, 2) end, 'xr', xr, 'ordered', ln.qty,
                  'before', ln.received_qty, 'shelf', ln.shelf_life_days));
      end if;
      anyin := anyin or q > 0;
    end loop;
    if not anyin and jsonb_array_length(xrep) = 0 then
      if not coalesce(p_close, false) then perform public._prov_fail('empty'); end if;
      if emp then perform public._prov_fail('locked'); end if;
      po := public._prov_close(po, nt);
      return jsonb_build_object('ok', true, 'status', po.status, 'closed', true, 'version', po.version);
    end if;
    -- the delivery row first, then the lines (id order), then each item's move in item order with its receipt line
    insert into public.purchase_receipts (id, po_id, vendor_id, invoice_no, by_name, lines, total_crc, final, staff_id, work_session_id, note, origin, close_requested)
      values (p_receipt_id, po.id, po.vendor_id, inv, who, 0, 0, false, case when emp then t.sid end, case when emp then t.wid end, nt, 'proveedores',
              emp and coalesce(p_close, false));
    perform 1 from public.purchase_lines where id = any(seen) order by id for update;
    for x in select e from jsonb_array_elements(plan) e order by e->>'item_id', e->>'line_id' loop
      q := (x->>'qty')::numeric; mv_id := null; mv_uc := null;
      if q > 0 then
        insert into public.stock_moves (item_id, kind, qty, unit_cost, po_id, expires_on, note, by_name, receipt_id)
          values ((x->>'item_id')::uuid, 'purchase', q, (x->>'uc')::numeric, po.id, current_date + (x->>'shelf')::int,
                  coalesce('factura ' || inv, 'pedido Nº ' || po.po_number), who, p_receipt_id)
          returning id, unit_cost into mv_id, mv_uc;     -- the cost as booked (a missing one becomes the average)
        update public.purchase_lines set received_qty = coalesce(received_qty, 0) + q where id = (x->>'line_id')::uuid;
        n := n + 1; total := total + q * coalesce(mv_uc, 0);
        if (x->>'typed')::boolean and mv_uc > 0 then
          update public.stock_items set cost_per_pack = mv_uc * pack_qty where id = (x->>'item_id')::uuid;
        end if;
        bp := round(mv_uc * (x->>'pqe')::numeric, 2);
        if not emp and bp is distinct from (x->>'xp')::numeric and (x->>'xp') is not null then
          diffs := diffs || jsonb_build_array(jsonb_build_object('line_id', x->'line_id', 'item_name', x->'item', 'expected_pack_price', x->'xp', 'pack_price', bp));
        end if;
      else bp := null;
      end if;
      insert into public.purchase_receipt_lines (receipt_id, line_id, item_id, packs, qty, pack_qty, unit_cost, pack_price, expected_pack_price,
                                                 observed_pack_price, extra_reported_packs, move_id)
        values (p_receipt_id, (x->>'line_id')::uuid, (x->>'item_id')::uuid, round(q / (x->>'pqe')::numeric, 4), q, (x->>'pqe')::numeric, mv_uc, bp,
                (x->>'xp')::numeric, (x->>'obs')::numeric, nullif((x->>'xr')::numeric, 0), mv_id);
      det := det || jsonb_build_array(jsonb_build_object('item', x->'item', 'ordered_qty', x->'ordered', 'received_before', x->'before', 'received_now', q,
               'pending_after', greatest((x->>'ordered')::numeric - (x->>'before')::numeric - q, 0), 'expected_pack_price', x->'xp', 'pack_price', bp,
               'observed_pack_price', x->'obs', 'extra_reported_packs', nullif((x->>'xr')::numeric, 0)));
    end loop;
    done := (not emp and coalesce(p_close, false))
            or not exists (select 1 from public.purchase_lines z where z.po_id = po.id and z.removed_at is null and coalesce(z.received_qty, 0) < z.qty);
    st := case when done then 'received' else 'partially_received' end;
    update public.purchase_receipts set lines = n, total_crc = round(total, 2), final = done where id = p_receipt_id;
    update public.purchase_orders set status = st, received_at = case when done then now() else received_at end where id = po.id returning * into po;
    perform public._prov_late_post();
    select coalesce(jsonb_agg(jsonb_build_object('line_id', z.id, 'item_name', z.item_name, 'pending_packs', z.pending_packs) order by coalesce(z.pos, 1000000), z.id), '[]')
      into short from public._prov_lines(po.id) z where not z.removed and z.pending_qty > 0;
    perform public._prov_log('stock_receive', case when emp then t.sid end, who, po.id::text,
      'pedido Nº ' || po.po_number || ': entrega · ' || case when done then 'completa' else 'parcial' end || ' · por ' || who || coalesce(' · factura ' || inv, ''),
      jsonb_build_object('receipt_id', p_receipt_id, 'lines', det, 'total_crc', round(total, 2), 'close', done, 'close_requested', emp and coalesce(p_close, false),
        'staff_id', case when emp then t.sid end, 'work_session_id', case when emp then t.wid end, 'session_tag', public._discount_tag(public._jwt_session()),
        'station', case when emp then t.station end, 'extra', extra, 'extra_reported', xrep, 'observed_diffs', obs, 'price_missing', miss,
        'shared_device', (select count(*) from public.work_sessions w where w.login_id = auth.uid() and w.ended_at is null
                            and w.started_at > now() - interval '16 hours') > 1));
    if emp then
      return jsonb_build_object('ok', true, 'status', po.status, 'receipt_id', p_receipt_id, 'version', po.version, 'lines', n, 'short', short,
                                'observed_diffs', obs, 'extra_reported', xrep, 'close_requested', coalesce(p_close, false));
    end if;
    return jsonb_build_object('ok', true, 'status', po.status, 'receipt_id', p_receipt_id, 'version', po.version, 'total_crc', round(total, 2),
                              'lines', n, 'price_diffs', diffs, 'short', short, 'extra', extra);
  exception when others then
    get stacked diagnostics e1 = returned_sqlstate, e2 = message_text, e3 = pg_exception_detail, e4 = constraint_name;
    if e4 = 'purchase_receipts_pkey' then   -- the same delivery from another device a moment ago
      return (select jsonb_build_object('ok', true, 'repeat', true, 'status', o.status, 'receipt_id', p_receipt_id, 'version', o.version)
                from public.purchase_orders o where o.id = p_po_id);
    end if;
    r := public._prov_caught(e1, e2, e3, e4); if r is null then raise; end if; return r;
  end;
end $$;
-- a wrong delivery is corrected by a new one (signed moves at the corrected line's booked cost); nothing is deleted
create or replace function public.proveedor_recepcion_corregir(p_receipt_id uuid, p_request_id uuid, p_lines jsonb, p_reason text)
returns jsonb language plpgsql volatile security definer set search_path = public, extensions as $$
declare rc public.purchase_receipts; po public.purchase_orders; ln record; l jsonb; lid uuid; d numeric; q numeric; uc numeric; seen uuid[] := '{}';
        plan jsonb := '[]'; x jsonb; mv record; total numeric := 0; n int := 0; short_before boolean; done boolean; st text; det jsonb := '[]';
        why text := nullif(btrim(coalesce(p_reason, '')), ''); who text := public._prov_actor(); e1 text; e2 text; e3 text; e4 text; r jsonb;
begin
  if not public._prov_manage() then return '{"ok":false,"error":"locked"}'::jsonb; end if;
  if p_request_id is null or p_receipt_id is null then return '{"ok":false,"error":"bad_request"}'::jsonb; end if;
  begin
    select * into rc from public.purchase_receipts where id = p_receipt_id;
    if rc.id is null then perform public._prov_fail('not_found'); end if;
    select * into po from public.purchase_orders where id = rc.po_id for update;
    if exists (select 1 from public.purchase_receipts z where z.id = p_request_id) then
      if exists (select 1 from public.purchase_receipts z where z.id = p_request_id and z.corrects = p_receipt_id) then
        return jsonb_build_object('ok', true, 'repeat', true, 'receipt_id', p_request_id, 'status', po.status, 'version', po.version); end if;
      perform public._prov_fail('bad_request');
    end if;
    if char_length(why) is null or char_length(why) < 5 then perform public._prov_fail('needs_reason'); end if;
    if char_length(why) > 500 then perform public._prov_fail('bad_request'); end if;
    if po.status = 'cancelled' then perform public._prov_fail('cancelled'); end if;
    if exists (select 1 from public.purchase_receipts z where z.po_id = po.id and z.received_at >= rc.received_at and z.invoice_id is not null) then
      perform public._prov_fail('invoiced'); end if;
    if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) > 200 then perform public._prov_fail('bad_request'); end if;
    if jsonb_array_length(p_lines) = 0 then perform public._prov_fail('empty'); end if;
    for l in select * from jsonb_array_elements(p_lines) loop
      if jsonb_typeof(l) <> 'object' then perform public._prov_fail('bad_request'); end if;
      lid := public._prov_id(l->'line_id');
      if lid is null then perform public._prov_fail('bad_request'); end if;
      if lid = any(seen) then perform public._prov_fail('duplicate_line', jsonb_build_object('line_id', lid)); end if;
      seen := seen || lid;
      select * into ln from public._prov_lines(po.id) z where z.id = lid;
      if ln.id is null then perform public._prov_fail('not_found', jsonb_build_object('line_id', lid)); end if;
      d := public._prov_num(l->'packs_delta');
      if d is null or d = 0 or abs(d) > 100000 or d <> round(d, 3) then perform public._prov_fail('bad_qty', jsonb_build_object('line_id', lid)); end if;
      q := round(d * ln.pack_qty, 4);
      if ln.received_qty + q < 0 then perform public._prov_fail('bad_qty', jsonb_build_object('line_id', lid)); end if;
      if q > ln.pending_qty and not coalesce(public._prov_bool(l->'extra_ok'), false) then
        perform public._prov_fail('over_pending', jsonb_build_object('line_id', lid, 'pending_packs', ln.pending_packs)); end if;
      select coalesce((select z.unit_cost from public.purchase_receipt_lines z where z.receipt_id = rc.id and z.line_id = lid),
                      (select z.unit_cost from public.stock_moves z where z.receipt_id = rc.id and z.item_id = ln.item_id and z.kind = 'purchase' order by z.id limit 1),
                      ln.exp_unit) into uc;
      plan := plan || jsonb_build_array(jsonb_build_object('line_id', lid, 'item_id', ln.item_id, 'item', ln.item_name, 'pqe', ln.pack_qty, 'qty', q, 'uc', uc,
                                                           'xp', ln.expected_pack_price, 'before', ln.received_qty));
    end loop;
    short_before := po.status = 'received' and exists (select 1 from public.purchase_lines z where z.po_id = po.id and z.removed_at is null
                                                          and coalesce(z.received_qty, 0) < z.qty);
    insert into public.purchase_receipts (id, po_id, vendor_id, by_name, lines, total_crc, final, note, origin, corrects)
      values (p_request_id, po.id, po.vendor_id, who, 0, 0, false, why, 'correccion', rc.id);
    perform 1 from public.purchase_lines where id = any(seen) order by id for update;
    for x in select e from jsonb_array_elements(plan) e order by e->>'item_id', e->>'line_id' loop
      q := (x->>'qty')::numeric;
      insert into public.stock_moves (item_id, kind, qty, unit_cost, po_id, note, by_name, receipt_id)
        values ((x->>'item_id')::uuid, 'purchase', q, (x->>'uc')::numeric, po.id, 'corrección pedido Nº ' || po.po_number, who, p_request_id)
        returning id, unit_cost into mv;
      update public.purchase_lines set received_qty = coalesce(received_qty, 0) + q where id = (x->>'line_id')::uuid;
      n := n + 1; total := total + q * coalesce(mv.unit_cost, 0);
      insert into public.purchase_receipt_lines (receipt_id, line_id, item_id, packs, qty, pack_qty, unit_cost, pack_price, expected_pack_price, move_id)
        values (p_request_id, (x->>'line_id')::uuid, (x->>'item_id')::uuid, round(q / (x->>'pqe')::numeric, 4), q, (x->>'pqe')::numeric, mv.unit_cost,
                round(mv.unit_cost * (x->>'pqe')::numeric, 2), (x->>'xp')::numeric, mv.id);
      det := det || jsonb_build_array(jsonb_build_object('item', x->'item', 'received_before', x->'before', 'delta', q, 'unit_cost', mv.unit_cost));
    end loop;
    done := short_before or not exists (select 1 from public.purchase_lines z where z.po_id = po.id and z.removed_at is null and coalesce(z.received_qty, 0) < z.qty);
    st := case when done then 'received' else 'partially_received' end;
    update public.purchase_receipts set lines = n, total_crc = round(total, 2) where id = p_request_id;
    update public.purchase_orders set status = st, received_at = case when not done then null when po.status = 'received' then received_at else now() end
     where id = po.id returning * into po;
    perform public._prov_late_post();
    perform public._prov_log('stock_receive_fix', null, who, po.id::text, 'pedido Nº ' || po.po_number || ': corrección de una entrega · ' || why,
      jsonb_build_object('receipt_id', p_request_id, 'corrects', rc.id, 'lines', det, 'total_crc', round(total, 2), 'reason', why,
                         'status_before', case when short_before then 'received' end));
    return jsonb_build_object('ok', true, 'receipt_id', p_request_id, 'status', po.status, 'version', po.version, 'total_crc', round(total, 2));
  exception when others then
    get stacked diagnostics e1 = returned_sqlstate, e2 = message_text, e3 = pg_exception_detail, e4 = constraint_name;
    r := public._prov_caught(e1, e2, e3, e4); if r is null then raise; end if; return r;
  end;
end $$;

-- 10) the low-stock alerts (management) ---
-- inventory_stats(30)'s own rule, the preferred supplier's catalog row, what is already on order
create or replace function public.proveedores_alertas()
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare res jsonb; n int;
begin
  if not public._prov_manage() then return '{"ok":false,"error":"locked"}'::jsonb; end if;
  with s as (select x.* from public.inventory_stats(30) x where x.active and x.status in ('out', 'low', 'soon')),
  oo as (select l.item_id, sum(greatest(l.qty - coalesce(l.received_qty, 0), 0)) as q, array_agg(distinct o.po_number) as nums
           from public.purchase_lines l join public.purchase_orders o on o.id = l.po_id
          where o.status in ('sent', 'partially_received') and l.removed_at is null and l.qty > coalesce(l.received_qty, 0) group by l.item_id),
  a as (select s.*, v.active as v_active, vi.id as vi_id, vi.pack_label as vi_label, vi.pack_qty as vi_qty, vi.usual_price as vi_price,
               vi.usual_qty as vi_usual, coalesce(oo.q, 0) as onq, oo.nums,
               exists (select 1 from public.purchase_drafts d cross join lateral jsonb_array_elements(d.lines) e
                        join public.vendor_items z on z.id = public._prov_uuid(e->>'vendor_item_id') where d.status = 'open' and z.item_id = s.id) as in_draft
          from s left join public.vendors v on v.id = s.vendor_id
          left join lateral (select z.* from public.vendor_items z where z.vendor_id = s.vendor_id and z.item_id = s.id and z.active
                              order by z.pack_qty, z.created_at limit 1) vi on true
          left join oo on oo.item_id = s.id),
  b as (select a.*, ceil(greatest(a.suggested_qty - a.onq, 0) / coalesce(a.vi_qty, nullif(a.pack_qty, 0), 1)) as sp from a)
  select coalesce(jsonb_agg(j order by k1, k2 nulls last, k3), '[]'), count(*) into res, n from (
    select jsonb_build_object('item_id', b.id, 'name', b.name, 'unit', b.unit, 'status', b.status, 'on_hand', b.on_hand, 'reorder_point', b.reorder_point,
             'par_level', b.par_level, 'days_left', b.days_left, 'vendor_id', b.vendor_id, 'vendor_name', b.vendor_name, 'vendor_active', b.v_active,
             'vendor_item_id', b.vi_id, 'pack_label', b.vi_label, 'pack_qty', b.vi_qty, 'usual_price', b.vi_price, 'on_order', b.onq,
             'on_order_po_numbers', to_jsonb(coalesce(b.nums, '{}')), 'in_draft', b.in_draft,
             'suggest_packs', case when b.sp = 0 and b.onq = 0 and b.status in ('out', 'low') then coalesce(b.vi_usual, 1) else b.sp end,
             -- who has it in their live catalog (smallest presentation each), for «Asociar proveedor» without a read per supplier
             'suppliers', (select coalesce(jsonb_agg(jsonb_build_object('vendor_id', c.vendor_id, 'vendor_name', c.vname, 'vendor_active', c.vactive,
                             'vendor_item_id', c.id, 'pack_label', c.pack_label, 'pack_qty', c.pack_qty, 'usual_price', c.usual_price) order by c.vname, c.vendor_id), '[]')
                             from (select distinct on (z.vendor_id) z.*, w.name as vname, w.active as vactive from public.vendor_items z
                                     join public.vendors w on w.id = z.vendor_id where z.item_id = b.id and z.active
                                    order by z.vendor_id, z.pack_qty, z.created_at) c)) as j,
           case b.status when 'out' then 0 when 'low' then 1 else 2 end as k1, b.days_left as k2, b.name as k3
      from b order by k1, k2 nulls last, k3 limit 100) q;
  return jsonb_build_object('ok', true, 'items', res,
                            'count', (select count(*) from public.inventory_stats(30) x where x.active and x.status in ('out', 'low', 'soon')));
end $$;


-- 11) rights ---
revoke all on function public._prov_turno(text), public._prov_mint(uuid, text, uuid, timestamptz, text, text), public._prov_draft_json(public.purchase_drafts),
  public._prov_draft_lines(uuid, jsonb, int), public._prov_po_state(uuid), public._prov_new_line(public.purchase_orders, jsonb, int),
  public._prov_po_lock(uuid, int), public._prov_close(public.purchase_orders, text), public._prov_late_post() from public, anon, authenticated;
do $$ declare f text; begin
  foreach f in array array['turno_aqui(uuid, text, text, boolean)', 'turno_desde_caja(text, text)', 'turno_estado(text[])', 'turno_terminar(text)',
    'proveedor_guardar(jsonb)', 'proveedor_producto_guardar(jsonb)', 'proveedor_borrador_guardar(uuid, jsonb, text, int)',
    'proveedor_borrador_descartar(uuid, int)', 'proveedor_pedido_crear(uuid, jsonb, text, uuid, int, date)',
    'proveedor_pedido_editar(uuid, int, jsonb, text, date)', 'proveedor_pedido_cancelar(uuid, int, text)', 'proveedor_pedido_cerrar(uuid, int, text)',
    'proveedor_pedido_confirmar(uuid, int)', 'proveedor_pedido_asignar(uuid, int, uuid)',
    'proveedor_recibir(uuid, uuid, int, jsonb, text, boolean, text, text, boolean, boolean)', 'proveedor_recepcion_corregir(uuid, uuid, jsonb, text)',
    'proveedores_alertas()'] loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

select canopy.migration_end(39, 'proveedores');
notify pgrst, 'reload schema';
