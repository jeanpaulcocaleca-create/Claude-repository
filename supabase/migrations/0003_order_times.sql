-- =====================================================================================================
-- Canopy OS · migración 0003 · Las fechas de cada venta (hora en que se marcó, hora del pago, día de caja)
-- Pegar TODO en Supabase → SQL Editor → New query → Run.  Requiere: 0002.
--
-- Por qué
--   Cuando una cuenta abierta se paga otro día, el sistema cambia su fecha (created_at) al día del pago para
--   que el cierre de caja la cuente ese día. Eso está bien para la caja, pero se perdía la hora original.
-- Qué hace (solo agrega; nada de lo que ya funciona cambia)
--   * orders.rung_at       hora en que se marcó la venta en la caja. Nunca cambia.
--   * orders.paid_at       hora en que entró el dinero.
--   * orders.business_date día de caja (Costa Rica) en que cuenta ese dinero.
--   * orders.received_at   hora en que la venta llegó al servidor (ventas hechas sin internet llegan después).
--   * orders.flags         avisos para el gerente: 'late_sync' (llegó tarde), 'clock_ahead' (reloj de la
--                          tableta adelantado), 'after_close' (llegó después del cierre de caja de su día).
--   * Rellena rung_at / paid_at / business_date de las ventas anteriores (sin cambiar ningún otro dato).
--   * Las tabletas no pueden escribir ni cambiar estas columnas: las pone el servidor.
-- Qué cambia para el personal: nada.
-- Reversión: drop trigger order_times_ins/order_times_upd (las columnas pueden quedarse).
-- =====================================================================================================
select canopy.migration_begin(3, 'order_times');

alter table public.orders add column if not exists rung_at timestamptz;
alter table public.orders add column if not exists paid_at timestamptz;
alter table public.orders add column if not exists business_date date;
alter table public.orders add column if not exists received_at timestamptz;
alter table public.orders add column if not exists flags text[] not null default '{}';

-- earlier sales: fill the new columns once (nothing else is touched). For a bill whose created_at was moved to
-- the payment day, the oldest line written by the till still carries the original time (pos-tabs.sql).
-- (the lines of an order are found by order_id everywhere: kitchen, bills, sales; this index was missing)
create index if not exists order_items_order_idx on public.order_items (order_id);
create or replace function canopy.backfill_order_times()
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  -- one pass over the lines (the per-order lookup took minutes on a large history; same result, rehearsal 2026-10-12)
  update public.orders o set
      rung_at = least(o.created_at, coalesce(f.first_at, o.created_at)),
      paid_at = case when coalesce(o.paid, true) then o.created_at end,
      business_date = case when coalesce(o.paid, true) then (o.created_at at time zone 'America/Costa_Rica')::date end,
      flags = case when f.first_at < o.created_at - interval '1 minute' then array_append(o.flags, 'rung_at_from_lines') else o.flags end
    from public.orders o2
    left join (select order_id, min(added_at) as first_at from public.order_items group by order_id) f on f.order_id = o2.id
   where o2.id = o.id and o.rung_at is null;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function canopy.backfill_order_times() from public;
select canopy.backfill_order_times();

-- is that Costa Rica day's register already closed? (the café login cannot read older closings itself)
create or replace function public._register_closed(p_day date)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.register_days where business_date = p_day and closed_at is not null);
$$;
revoke all on function public._register_closed(date) from public, anon;
grant execute on function public._register_closed(date) to authenticated;

create or replace function public._order_times()
returns trigger language plpgsql set search_path = public as $$
declare client boolean := current_user in ('authenticated', 'anon');
begin
  if tg_op = 'INSERT' then
    new.received_at := now();
    new.rung_at := coalesce(case when client then null else new.rung_at end, new.created_at, now());
    if client then new.flags := '{}'; else new.flags := coalesce(new.flags, '{}'); end if;
    if coalesce(new.paid, true) then
      new.paid_at := coalesce(case when client then null else new.paid_at end, new.created_at, now());
      new.business_date := (new.paid_at at time zone 'America/Costa_Rica')::date;
    else
      new.paid_at := null; new.business_date := null;
    end if;
    if new.created_at > now() + interval '10 minutes' then new.flags := array_append(new.flags, 'clock_ahead'); end if;
    if new.created_at < now() - interval '12 hours' then new.flags := array_append(new.flags, 'late_sync'); end if;
    if new.business_date is not null and new.business_date < public.cr_today() and public._register_closed(new.business_date) then
      new.flags := array_append(new.flags, 'after_close');
    end if;
  else
    new.rung_at := coalesce(old.rung_at, new.rung_at);
    new.received_at := coalesce(old.received_at, new.received_at);
    if not coalesce(old.paid, true) and coalesce(new.paid, false) then
      new.paid_at := now();
      new.business_date := public.cr_today();
    else
      new.paid_at := coalesce(old.paid_at, new.paid_at);
      new.business_date := coalesce(old.business_date, new.business_date);
    end if;
    if client then new.flags := old.flags; end if;
  end if;
  return new;
end $$;
drop trigger if exists order_times_ins on public.orders;
create trigger order_times_ins before insert on public.orders for each row execute function public._order_times();
drop trigger if exists order_times_upd on public.orders;
create trigger order_times_upd before update on public.orders for each row execute function public._order_times();

-- a sale that reached the server after its day was closed shows up in the approvals log
create or replace function public._order_after_close_log()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if 'after_close' = any(new.flags) then
    insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
      values ('late_sale_after_close', null, coalesce(new.station, 'POS'), new.id::text,
              'venta del ' || to_char(new.business_date, 'DD/MM') || ' llegó después del cierre de caja',
              jsonb_build_object('total_crc', new.total_crc, 'payment_method', new.payment_method,
                                 'business_date', new.business_date, 'rung_at', new.rung_at, 'received_at', new.received_at));
  end if;
  return null;
end $$;
drop trigger if exists order_after_close_log on public.orders;
create trigger order_after_close_log after insert on public.orders for each row
  when ('after_close' = any(new.flags)) execute function public._order_after_close_log();

create index if not exists orders_business_date_idx on public.orders (business_date) where voided_at is null;
create index if not exists orders_rung_at_idx on public.orders (rung_at);

select canopy.migration_end(3, 'order_times');
notify pgrst, 'reload schema';
