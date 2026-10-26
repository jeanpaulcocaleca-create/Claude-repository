-- =====================================================================================================
-- Canopy OS · migración 0024 · Lista para más de un local (hoy: uno solo, nada cambia)
-- Pegar TODO en Supabase → SQL Editor → New query → Run.  Requiere: 0023.
--
-- Qué hace
--   * public.locations con el local de hoy ("Hanging Garden Café · Monteverde") con un identificador fijo.
--   * Una columna location_id en las ventas, cajas, entradas y salidas de dinero, movimientos de inventario,
--     marcas de horas, órdenes de compra, cuentas bancarias, gastos y asientos contables. Todo lo que existe y
--     todo lo nuevo queda en el local de hoy (valor por defecto), así que ninguna página cambia.
--   * Un segundo local necesitará después: cajas por local (hoy un día tiene una sola caja), inventario por
--     local, y que cada dispositivo diga su local. Eso es otra migración, cuando haga falta (DECISIONS D-021).
-- Qué cambia para el personal: nada.
-- Reversión: no hace falta; las columnas no se usan para nada todavía.
-- =====================================================================================================
select canopy.migration_begin(24, 'locations');

create table if not exists public.locations (
  id         uuid primary key,
  name       text not null,
  active     boolean not null default true,
  created_at timestamptz not null default now()
);
insert into public.locations (id, name) values ('10ca7100-0000-4000-8000-000000000001', 'Hanging Garden Café · Monteverde')
  on conflict (id) do nothing;
alter table public.locations enable row level security;
revoke all on public.locations from anon, authenticated;
grant select on public.locations to authenticated;
drop policy if exists "locations read" on public.locations;
create policy "locations read" on public.locations for select to authenticated using (true);

-- a constant default: adding the column does not rewrite the tables, and every row is in today's café
do $$
declare t text;
begin
  foreach t in array array['public.orders', 'public.register_days', 'public.cash_movements', 'public.stock_moves', 'public.time_entries',
                           'public.purchase_orders', 'public.bank_accounts', 'public.expenses', 'acct.entries'] loop
    execute format('alter table %s add column if not exists location_id uuid not null default %L references public.locations(id)',
                   t, '10ca7100-0000-4000-8000-000000000001');
  end loop;
end $$;

-- the café every device belongs to, until devices choose (one place to change later)
create or replace function public.current_location() returns uuid language sql stable as $$
  select '10ca7100-0000-4000-8000-000000000001'::uuid;
$$;
grant execute on function public.current_location() to authenticated;

select canopy.migration_end(24, 'locations');
notify pgrst, 'reload schema';
