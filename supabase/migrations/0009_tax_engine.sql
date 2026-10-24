-- =====================================================================================================
-- Canopy OS · migración 0009 · IVA por producto, CABYS, y el impuesto guardado en cada línea vendida
-- Pegar TODO en Supabase → SQL Editor → New query → Run.  Requiere: 0008.
--
-- Qué hace
--   * Tarifas de IVA (public.tax_rates). Viene solo la tarifa general del 13 %, la que la caja ya usa hoy.
--     Otras tarifas (reducidas, exento) las agrega el dueño con el nombre de quien las confirmó y el documento.
--   * Cada producto del menú tiene su tarifa (tax_code, por defecto la general) y su código CABYS (13 dígitos).
--   * Cada línea vendida guarda, al momento de la venta: tarifa, IVA y monto sin IVA, ya repartido el descuento.
--     Cada venta guarda su IVA total (orders.tax_crc). Las ventas anteriores NO se modifican.
--   * Precios sin IVA en el menú ("₡1 000 + IVA = ₡1 130"): el ajuste price_mode existe pero tiene CANDADO.
--     No se puede activar hasta registrar la confirmación 'price_display_rules' (reglas de MEIC/Hacienda sobre
--     cómo mostrar precios). Aun activado, el sitio web, la TV y el menú QR siguen mostrando el precio final.
-- Qué cambia para el personal: nada visible; el recibo y la caja muestran el IVA por tarifa.
-- Reversión: drop trigger order_items_tax_ins/_upd/_del, order_tax_discount, order_item_tax_stamp, order_refund_tax.
-- =====================================================================================================
select canopy.migration_begin(9, 'tax_engine');

-- 1) rates and per-product codes -------------------------------------------------------------------------------
create table if not exists public.tax_rates (
  code         text primary key check (code ~ '^[A-Z0-9_]{2,16}$'),
  name         text not null,
  rate         numeric(6,4) not null check (rate >= 0 and rate < 1),
  active       boolean not null default true,
  confirmed_by text not null,
  reference    text not null,
  created_at   timestamptz not null default now()
);
insert into public.tax_rates (code, name, rate, confirmed_by, reference)
  values ('IVA13', 'IVA tarifa general 13 %', 0.13, 'Ley 9635 (Ley de Fortalecimiento de las Finanzas Públicas)', 'Ley 9635, art. 10 · tarifa general')
  on conflict (code) do nothing;
alter table public.tax_rates enable row level security;
revoke all on public.tax_rates from anon, authenticated;
grant select on public.tax_rates to authenticated;
drop policy if exists "tax rates read" on public.tax_rates;
create policy "tax rates read" on public.tax_rates for select to authenticated using (true);

alter table public.menu_items add column if not exists tax_code text not null default 'IVA13' references public.tax_rates(code);
alter table public.menu_items add column if not exists cabys text check (cabys is null or cabys ~ '^[0-9]{13}$');

-- the owner adds a rate, always saying who confirmed it and with which document
create or replace function public.tax_rate_save(p_code text, p_name text, p_rate numeric, p_confirmed_by text, p_reference text,
                                                p_active boolean default true)
returns jsonb language plpgsql security definer set search_path = public as $$
declare before public.tax_rates;
begin
  if public.access_level() is distinct from 'owner' then return jsonb_build_object('ok', false, 'error', 'owner_only'); end if;
  if coalesce(trim(p_confirmed_by), '') = '' or coalesce(trim(p_reference), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'missing_reference'); end if;
  if p_rate is null or p_rate < 0 or p_rate >= 1 or coalesce(trim(p_name), '') = '' or upper(coalesce(p_code, '')) !~ '^[A-Z0-9_]{2,16}$' then
    return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  select * into before from public.tax_rates where code = upper(p_code);
  -- a rate already used on sales is never rewritten: add a new code instead
  if before.code is not null and before.rate <> p_rate
     and exists (select 1 from public.order_items where tax_code = before.code) then
    return jsonb_build_object('ok', false, 'error', 'rate_in_use'); end if;
  insert into public.tax_rates (code, name, rate, active, confirmed_by, reference)
    values (upper(p_code), trim(p_name), p_rate, coalesce(p_active, true), trim(p_confirmed_by), trim(p_reference))
    on conflict (code) do update set name = excluded.name, rate = excluded.rate, active = excluded.active,
                                     confirmed_by = excluded.confirmed_by, reference = excluded.reference;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('tax_rate_save', null, public._owner_label(), upper(p_code), trim(p_name) || ' · ' || (p_rate * 100)::text || ' %',
            jsonb_build_object('before', to_jsonb(before), 'rate', p_rate, 'confirmed_by', trim(p_confirmed_by), 'reference', trim(p_reference)));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.tax_rate_save(text, text, numeric, text, text, boolean) from public, anon;
grant execute on function public.tax_rate_save(text, text, numeric, text, text, boolean) to authenticated;

-- 2) the tax of every line sold, computed by the server ---------------------------------------------------------
alter table public.order_items add column if not exists tax_code text;
alter table public.order_items add column if not exists tax_rate numeric(6,4);
alter table public.order_items add column if not exists discount_alloc_crc int;
alter table public.order_items add column if not exists tax_crc int;
alter table public.order_items add column if not exists net_crc int;
alter table public.orders add column if not exists tax_crc int;

-- the rate of a new line comes from its product at the moment of the sale (the till cannot choose it)
create or replace function public._order_item_tax_stamp()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  select m.tax_code, t.rate into new.tax_code, new.tax_rate
    from public.menu_items m join public.tax_rates t on t.code = m.tax_code where m.id = new.menu_item_id;
  if new.tax_code is null then
    select t.code, t.rate into new.tax_code, new.tax_rate from public.tax_rates t where t.code = 'IVA13';
  end if;
  new.discount_alloc_crc := null; new.tax_crc := null; new.net_crc := null;
  return new;
end $$;
-- after order_item_menu_id (which finds the product)
drop trigger if exists order_item_tax_stamp on public.order_items;
create trigger order_item_tax_stamp before insert on public.order_items for each row execute function public._order_item_tax_stamp();

-- prices include IVA: each line's share of the bill discount comes off first, then IVA = amount × r / (1 + r)
create or replace function public._order_tax(p_orders uuid[])
returns void language plpgsql security definer set search_path = public as $$
declare o record; l record; gross bigint; disc int; left_disc int; alloc int; amt int; tx int; n int; i int; total_tax int;
begin
  for o in select id, coalesce(discount_crc, 0) as discount_crc from public.orders
            where id = any(p_orders) and part_of is null and refund_of is null order by id for update loop
    select coalesce(sum(price_crc::bigint * qty), 0), count(*) into gross, n from public.order_items where order_id = o.id;
    disc := least(greatest(o.discount_crc, 0), greatest(gross, 0))::int;
    left_disc := disc; i := 0; total_tax := 0;
    for l in select id, price_crc, qty, tax_rate from public.order_items where order_id = o.id
              order by price_crc::bigint * qty desc, id loop
      i := i + 1;
      amt := l.price_crc * l.qty;
      -- the last (smallest) line takes the rounding rest, so the shares add up to the discount exactly
      alloc := case when gross <= 0 then 0 when i = n then left_disc else least(left_disc, floor(disc::numeric * amt / gross)::int) end;
      left_disc := left_disc - alloc;
      tx := round((amt - alloc) * coalesce(l.tax_rate, 0) / (1 + coalesce(l.tax_rate, 0)))::int;
      update public.order_items set discount_alloc_crc = alloc, tax_crc = tx, net_crc = amt - alloc - tx where id = l.id;
      total_tax := total_tax + tx;
    end loop;
    update public.orders set tax_crc = total_tax where id = o.id and tax_crc is distinct from total_tax;
  end loop;
end $$;
revoke all on function public._order_tax(uuid[]) from public, anon, authenticated;

create or replace function public._order_items_tax()
returns trigger language plpgsql security definer set search_path = public as $$
declare ids uuid[];
begin
  if tg_op = 'DELETE' then select array_agg(distinct order_id) into ids from old_lines;
  else select array_agg(distinct order_id) into ids from new_lines; end if;
  perform public._order_tax(ids);
  return null;
end $$;
drop trigger if exists order_items_tax_ins on public.order_items;
create trigger order_items_tax_ins after insert on public.order_items referencing new table as new_lines
  for each statement execute function public._order_items_tax();
drop trigger if exists order_items_tax_upd on public.order_items;
create trigger order_items_tax_upd after update on public.order_items referencing new table as new_lines
  for each statement when (pg_trigger_depth() < 1) execute function public._order_items_tax();
drop trigger if exists order_items_tax_del on public.order_items;
create trigger order_items_tax_del after delete on public.order_items referencing old table as old_lines
  for each statement execute function public._order_items_tax();

-- a discount set or taken off a bill later moves the tax too
create or replace function public._order_tax_discount()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform public._order_tax(array[new.id]);
  return null;
end $$;
drop trigger if exists order_tax_discount on public.orders;
create trigger order_tax_discount after update of discount_crc on public.orders
  for each row when (old.discount_crc is distinct from new.discount_crc) execute function public._order_tax_discount();

-- the till cannot write the tax; a refund gives back the tax of the sale it refunds
create or replace function public._order_refund_tax()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.tax_crc := case when new.refund_of is not null then -(select o.tax_crc from public.orders o where o.id = new.refund_of) end;
  return new;
end $$;
drop trigger if exists order_refund_tax on public.orders;
create trigger order_refund_tax before insert on public.orders for each row execute function public._order_refund_tax();

-- 3) tax-exclusive prices: built, locked until the display rules are confirmed ------------------------------------
insert into canopy.setting_defs (key, kind, choices, default_value, guard, description) values
  ('price_mode', 'choice', '{inclusive,exclusive}', '"inclusive"', 'price_display_rules',
   'Precios en la caja: inclusive = el precio del menú ya incluye el IVA (como hoy); exclusive = la caja muestra el precio sin IVA y suma el IVA al cobrar. El sitio, la TV y el menú QR siempre muestran el precio final. Requiere confirmar las reglas de MEIC y Hacienda sobre la exhibición de precios.')
on conflict (key) do update set kind = excluded.kind, choices = excluded.choices, default_value = excluded.default_value,
                                guard = excluded.guard, description = excluded.description;

-- the IVA of a period, by rate (the base for the accountant; sales recorded before this migration are counted apart)
create or replace function public.tax_summary(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare by_rate jsonb; untaxed jsonb;
begin
  if not (public.is_owner() or public.sales_open()) then return jsonb_build_object('ok', false, 'error', 'locked'); end if;
  select coalesce(jsonb_agg(x order by x->>'code'), '[]'::jsonb) into by_rate from (
    select jsonb_build_object('code', i.tax_code, 'rate', i.tax_rate, 'lines', count(*),
                              'gross_crc', sum(i.price_crc * i.qty - coalesce(i.discount_alloc_crc, 0)),
                              'net_crc', sum(i.net_crc), 'tax_crc', sum(i.tax_crc)) as x
      from public.order_items i join public.orders o on o.id = i.order_id
     where o.business_date between p_from and p_to and o.voided_at is null and coalesce(o.paid, true)
       and o.part_of is null and i.tax_crc is not null
     group by i.tax_code, i.tax_rate) q;
  select jsonb_build_object('orders', count(*), 'total_crc', coalesce(sum(o.total_crc), 0)) into untaxed
    from public.orders o
   where o.business_date between p_from and p_to and o.voided_at is null and coalesce(o.paid, true) and o.part_of is null
     and o.refund_of is null and o.tax_crc is null and o.total_crc > 0;
  return jsonb_build_object('ok', true, 'from', p_from, 'to', p_to, 'by_rate', by_rate,
    'refunds_tax_crc', (select coalesce(sum(tax_crc), 0) from public.orders where refund_of is not null and voided_at is null
                          and business_date between p_from and p_to),
    'without_tax_detail', untaxed);
end $$;
revoke all on function public.tax_summary(date, date) from public, anon;
grant execute on function public.tax_summary(date, date) to authenticated;

select canopy.migration_end(9, 'tax_engine');
notify pgrst, 'reload schema';
