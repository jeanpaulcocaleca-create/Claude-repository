-- =====================================================================================================
-- Canopy OS · migración 0010 · Tipo de cambio del día, efectivo recibido y vuelto, caja en colones y dólares
-- Pegar TODO en Supabase → SQL Editor → New query → Run.  Requiere: 0009.
--
-- Por qué
--   * "Efectivo $" guardaba solo el monto en colones, sin tipo de cambio, y el cierre contaba esos dólares como
--     si fueran colones en la gaveta.
-- Qué hace
--   * public.fx_rates: tipo de cambio de cada día (compra y venta). Lo trae solo, dos veces al día, del API
--     público de Hacienda (sin costo, sin claves) SI el dueño activa las extensiones "http" y "pg_cron"
--     (Supabase → Database → Extensions) y vuelve a correr el bloque del final (docs/MIGRACIONES.md). Mientras
--     tanto, o si el API falla, un encargado lo escribe a mano (queda en la bitácora).
--   * El ajuste fx_rate_kind elige qué tipo usa la caja para recibir dólares: 'buy' (compra, por defecto) o 'sell'.
--   * public.cash_tenders: por cada pago en efectivo, cuántos colones y cuántos dólares entraron, el vuelto
--     (en colones) y el tipo de cambio usado. Se marca si no cuadra con el total o si el tipo difiere del oficial.
--   * Cierre de caja en dos monedas: fondo y conteo en colones y en dólares por separado. Los pagos viejos sin
--     ese detalle se cuentan como antes (en colones).
-- Qué cambia para el personal: al cobrar en efectivo aparece la ventana de efectivo (billetes, vuelto).
-- Reversión: la caja vieja sigue funcionando con estas funciones (los parámetros nuevos son opcionales).
-- =====================================================================================================
select canopy.migration_begin(10, 'fx_cash');

-- 1) exchange rates --------------------------------------------------------------------------------------------
create table if not exists public.fx_rates (
  day        date primary key,
  buy        numeric(10,2) not null check (buy > 0),
  sell       numeric(10,2) not null check (sell > 0),
  source     text not null check (source in ('hacienda', 'bccr', 'manual')),
  fetched_at timestamptz not null default now(),
  entered_by text
);
alter table public.fx_rates enable row level security;
revoke all on public.fx_rates from anon, authenticated;
grant select on public.fx_rates to authenticated;
drop policy if exists "fx read" on public.fx_rates;
create policy "fx read" on public.fx_rates for select to authenticated using ((select public.is_cafe()));

create table if not exists canopy.fx_fetch_log (
  id bigint generated always as identity primary key, at timestamptz not null default now(), ok boolean not null, detail text);
revoke all on canopy.fx_fetch_log from public;

insert into canopy.setting_defs (key, kind, choices, default_value, guard, description) values
  ('fx_rate_kind', 'choice', '{buy,sell}', '"buy"', null,
   'Tipo de cambio para recibir dólares en la caja: buy = compra del día (por defecto), sell = venta del día. Lo confirma el contador (A-06).')
on conflict (key) do update set kind = excluded.kind, choices = excluded.choices, default_value = excluded.default_value,
                                guard = excluded.guard, description = excluded.description;

-- the rate a day uses: that day's, else the latest before it
create or replace function public._fx_for(p_day date, out day date, out buy numeric, out sell numeric, out source text, out rate numeric)
language sql stable security definer set search_path = public as $$
  select f.day, f.buy, f.sell, f.source,
         case when (public.setting('fx_rate_kind') #>> '{}') = 'sell' then f.sell else f.buy end
    from public.fx_rates f where f.day <= p_day order by f.day desc limit 1;
$$;
revoke all on function public._fx_for(date) from public, anon, authenticated;

create or replace function public.fx_today()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare f record;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  select * into f from public._fx_for(public.cr_today());
  if f.day is null then return jsonb_build_object('ok', true, 'rate', null, 'stale', true); end if;
  return jsonb_build_object('ok', true, 'day', f.day, 'rate', f.rate, 'buy', f.buy, 'sell', f.sell, 'source', f.source,
                            'kind', public.setting('fx_rate_kind') #>> '{}', 'stale', f.day < public.cr_today() - 3);
end $$;
revoke all on function public.fx_today() from public, anon;
grant execute on function public.fx_today() to authenticated;

-- a manager types the day's rate when the official one is missing; never over an official rate
create or replace function public.fx_rate_set(p_day date, p_buy numeric, p_sell numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare cur public.fx_rates;
begin
  if not public.is_owner() then return jsonb_build_object('ok', false, 'error', 'owner_only'); end if;
  if p_day is null or p_day > public.cr_today() + 1 or p_buy is null or p_sell is null or p_buy <= 0 or p_sell <= 0
     or p_buy > p_sell * 1.1 or p_sell > p_buy * 1.2 then
    return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  select * into cur from public.fx_rates where day = p_day;
  if cur.day is not null and cur.source <> 'manual' then return jsonb_build_object('ok', false, 'error', 'official_exists'); end if;
  insert into public.fx_rates (day, buy, sell, source, entered_by) values (p_day, p_buy, p_sell, 'manual', public._owner_label())
    on conflict (day) do update set buy = excluded.buy, sell = excluded.sell, fetched_at = now(), entered_by = excluded.entered_by;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('fx_rate_set', null, public._owner_label(), p_day::text, 'tipo de cambio manual ' || p_buy || ' / ' || p_sell,
            jsonb_build_object('before', to_jsonb(cur), 'buy', p_buy, 'sell', p_sell));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.fx_rate_set(date, numeric, numeric) from public, anon;
grant execute on function public.fx_rate_set(date, numeric, numeric) to authenticated;

-- the official rate, from Hacienda's public API (https://api.hacienda.go.cr/indicadores/tc/dolar)
-- answer: {"venta": {"fecha": "YYYY-MM-DD", "valor": 0.0}, "compra": {"fecha": "...", "valor": 0.0}} (also accepted inside "dolar")
create or replace function canopy.fx_record_hacienda(p_body jsonb)
returns date language plpgsql security definer set search_path = public, canopy as $$
declare b jsonb; d date; buy numeric; sell numeric;
begin
  b := coalesce(p_body->'dolar', p_body);
  buy := nullif(b #>> '{compra,valor}', '')::numeric;
  sell := nullif(b #>> '{venta,valor}', '')::numeric;
  d := coalesce(nullif(left(b #>> '{venta,fecha}', 10), '')::date, public.cr_today());
  if buy is null or sell is null or buy < 100 or sell < 100 or buy > 2000 or sell > 2000 or sell < buy then
    raise exception 'fx_bad_answer: %', left(p_body::text, 200);
  end if;
  insert into public.fx_rates (day, buy, sell, source) values (d, round(buy, 2), round(sell, 2), 'hacienda')
    on conflict (day) do update set buy = excluded.buy, sell = excluded.sell, source = 'hacienda', fetched_at = now(), entered_by = null;
  insert into canopy.fx_fetch_log (ok, detail) values (true, d || ' ' || buy || '/' || sell);
  return d;
end $$;
revoke all on function canopy.fx_record_hacienda(jsonb) from public;

-- the automatic fetch exists only where the "http" extension is on; the schedule only where "pg_cron" is on
do $fx$
begin
  if exists (select 1 from pg_extension where extname = 'http') then
    execute $f$
      create or replace function canopy.fx_fetch()
      returns void language plpgsql security definer set search_path = public, canopy, extensions as $b$
      declare r record;
      begin
        select status, content into r from http_get('https://api.hacienda.go.cr/indicadores/tc/dolar');
        if r.status <> 200 then raise exception 'fx_http_%', r.status; end if;
        perform canopy.fx_record_hacienda(r.content::jsonb);
      exception when others then
        insert into canopy.fx_fetch_log (ok, detail) values (false, left(sqlerrm, 300));
      end $b$;
    $f$;
    execute 'revoke all on function canopy.fx_fetch() from public';
  end if;
  if exists (select 1 from pg_extension where extname = 'pg_cron') and to_regprocedure('canopy.fx_fetch()') is not null then
    perform cron.schedule('canopy-fx-morning', '10 12 * * *', 'select canopy.fx_fetch()');   -- 06:10 Costa Rica
    perform cron.schedule('canopy-fx-evening', '40 23 * * *', 'select canopy.fx_fetch()');   -- 17:40 Costa Rica
  end if;
end $fx$;

-- 2) cash received and change ---------------------------------------------------------------------------------
create table if not exists public.cash_tenders (
  order_id      uuid primary key references public.orders(id),
  crc_in        int not null default 0 check (crc_in >= 0),
  usd_in        numeric(10,2) not null default 0 check (usd_in >= 0),
  change_crc    int not null default 0 check (change_crc >= 0),
  fx_rate       numeric(10,2) check (fx_rate is null or fx_rate > 0),   -- the rate the cashier used
  official_rate numeric(10,2),                                          -- the day's rate on the server
  flags         text[] not null default '{}',
  recorded_at   timestamptz not null default now()
);
alter table public.cash_tenders enable row level security;
revoke all on public.cash_tenders from anon, authenticated;
grant select on public.cash_tenders to authenticated;
drop policy if exists "tenders read" on public.cash_tenders;
create policy "tenders read" on public.cash_tenders for select to authenticated using ((select public.is_cafe()));

create or replace function public._tender_insert(p_order_id uuid, p_tender jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o public.orders; crc int; usd numeric; chg int; fx numeric; off numeric; fl text[] := '{}'; got int;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  select * into o from public.orders where id = p_order_id;
  if o.id is null or o.created_at < now() - interval '14 days' then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if o.payment_method not in ('cash_crc', 'cash_usd') or not coalesce(o.paid, true) then
    return jsonb_build_object('ok', false, 'error', 'not_cash'); end if;
  crc := coalesce(nullif(p_tender->>'crc_in', '')::int, 0);
  usd := round(coalesce(nullif(p_tender->>'usd_in', '')::numeric, 0), 2);
  chg := coalesce(nullif(p_tender->>'change_crc', '')::int, 0);
  fx := nullif(p_tender->>'fx_rate', '')::numeric;
  if crc < 0 or usd < 0 or chg < 0 or (usd > 0 and fx is null) then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  select rate into off from public._fx_for(coalesce(o.business_date, public.cr_today()));
  got := crc + round(usd * coalesce(fx, 0))::int - chg;
  if abs(got - o.total_crc) > 1 then fl := array_append(fl, 'mismatch'); end if;
  if usd > 0 and off is not null and abs(fx - off) > off * 0.01 then fl := array_append(fl, 'rate_differs'); end if;
  if usd > 0 and off is null then fl := array_append(fl, 'no_official_rate'); end if;
  insert into public.cash_tenders (order_id, crc_in, usd_in, change_crc, fx_rate, official_rate, flags)
    values (o.id, crc, usd, chg, case when usd > 0 then fx end, off, fl)
    on conflict (order_id) do nothing;
  if not found then return jsonb_build_object('ok', true, 'already', true); end if;
  return jsonb_build_object('ok', true, 'flags', to_jsonb(fl));
end $$;
revoke all on function public._tender_insert(uuid, jsonb) from public, anon;
grant execute on function public._tender_insert(uuid, jsonb) to authenticated;   -- called by pos_record_sale (runs as the till)

-- a payment made through a bill function: the till records what came in right after
create or replace function public.pos_record_tender(p_order_id uuid, p_tender jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  if not exists (select 1 from public.orders where id = p_order_id and created_at > now() - interval '2 days') then
    return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  return public._tender_insert(p_order_id, p_tender);
end $$;
revoke all on function public.pos_record_tender(uuid, jsonb) from public, anon;
grant execute on function public.pos_record_tender(uuid, jsonb) to authenticated;

-- 3) the sale save takes the tender with it (offline sales too) -------------------------------------------------
create or replace function public.pos_record_sale(p_order jsonb)
returns jsonb language plpgsql set search_path = public as $$
declare oid uuid; existing boolean := false; c text; other boolean := false; op jsonb;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  oid := nullif(p_order->>'id', '')::uuid;
  if oid is null or jsonb_typeof(coalesce(p_order->'items', '[]'::jsonb)) <> 'array' then
    raise exception 'bad_payload' using errcode = 'P0001';
  end if;
  op := p_order->'operator';
  if op is not null and jsonb_typeof(op) = 'object' then
    perform set_config('canopy.operator_token', coalesce(nullif(op->>'token', ''), 'claim'), true);
    perform set_config('canopy.operator_claim', coalesce(op->>'staff_id', ''), true);
  elsif p_order ? 'operator' then
    perform set_config('canopy.operator_token', 'none', true);
  end if;
  begin
    insert into public.orders (id, created_at, total_crc, payment_method, paid, status, source, needs_kitchen, accepted_at,
                               pickup_number, guest_name, station, subtotal_crc, discount_crc, discount_id, notes)
    values (oid,
            coalesce((p_order->>'created_at')::timestamptz, now()),
            (p_order->>'total_crc')::int,
            coalesce(p_order->>'payment_method', 'cash_crc'),
            coalesce((p_order->>'paid')::boolean, true),
            coalesce(p_order->>'status', 'done'),
            coalesce(p_order->>'source', 'front'),
            coalesce((p_order->>'needs_kitchen')::boolean, false),
            (p_order->>'accepted_at')::timestamptz,
            (p_order->>'pickup_number')::int,
            nullif(left(p_order->>'guest_name', 60), ''),
            nullif(left(p_order->>'station', 40), ''),
            (p_order->>'subtotal_crc')::int,
            coalesce((p_order->>'discount_crc')::int, 0),
            (p_order->>'discount_id')::uuid,
            nullif(left(p_order->>'notes', 200), ''));
  exception when unique_violation then
    get stacked diagnostics c = constraint_name;
    if c = 'orders_pkey' then existing := true; else raise; end if;
  end;
  begin
    insert into public.order_items (id, order_id, item_name, price_crc, qty, menu_item_id)
      select coalesce(nullif(l->>'id', '')::uuid, gen_random_uuid()), oid, l->>'item_name', (l->>'price_crc')::int, (l->>'qty')::int,
             nullif(l->>'menu_item_id', '')::uuid
        from jsonb_array_elements(coalesce(p_order->'items', '[]'::jsonb)) l;
  exception
    when unique_violation then
      if not existing then raise; end if;
    when others then
      if existing and sqlerrm ~ 'order_has_lines' then other := true; else raise; end if;
  end;
  -- cash received and change; a repeated send keeps the first
  if jsonb_typeof(p_order->'tender') = 'object' then perform public._tender_insert(oid, p_order->'tender'); end if;
  perform set_config('canopy.operator_token', '', true);
  perform set_config('canopy.operator_claim', '', true);
  return jsonb_build_object('ok', true, 'already', existing, 'other_lines', other);
end $$;
revoke all on function public.pos_record_sale(jsonb) from public, anon;
grant execute on function public.pos_record_sale(jsonb) to authenticated;

-- 4) the register in two currencies ---------------------------------------------------------------------------
alter table public.register_days add column if not exists float_usd numeric(10,2) not null default 0;
alter table public.register_days add column if not exists usd_in numeric(10,2);              -- dollars received in cash
alter table public.register_days add column if not exists cash_counted_usd numeric(10,2);
alter table public.register_days add column if not exists expected_cash_usd numeric(10,2);
alter table public.register_days add column if not exists cash_diff_usd numeric(10,2);
alter table public.register_days add column if not exists fx_rate numeric(10,2);             -- the day's rate, to value the dollars

-- what the drawer should hold: colones from the tender of each cash payment (change already out), else the
-- payment's total as before; dollars from the tenders
create or replace function public._register_expected(p_day date, out cash_crc bigint, out usd numeric)
language sql stable security definer set search_path = public as $$
  select coalesce(sum(case when t.order_id is not null then t.crc_in - t.change_crc
                           when o.payment_method in ('cash_crc', 'cash_usd') then o.total_crc else 0 end), 0),
         coalesce(sum(t.usd_in), 0)
    from public.orders o left join public.cash_tenders t on t.order_id = o.id
   where o.created_at >= public.cr_day_start(p_day) and o.created_at < public.cr_day_start(p_day + 1)
     and o.voided_at is null and coalesce(o.paid, true);
$$;
revoke all on function public._register_expected(date) from public, anon, authenticated;

-- the counter screen shows what the drawer should hold, in each currency
create or replace function public.register_expected()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare r public.register_days; e record;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  select * into r from public.register_days where closed_at is null or business_date = public.cr_today()
   order by (closed_at is null) desc, business_date limit 1;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'not_open'); end if;
  select * into e from public._register_expected(r.business_date);
  return jsonb_build_object('ok', true, 'business_date', r.business_date,
                            'expected_crc', r.float_crc + e.cash_crc, 'expected_usd', r.float_usd + e.usd, 'usd_in', e.usd);
end $$;
revoke all on function public.register_expected() from public, anon;
grant execute on function public.register_expected() to authenticated;

drop function if exists public.register_open(uuid, text, int);
create or replace function public.register_open(p_staff_id uuid, p_pin text, p_float_crc int, p_float_usd numeric default 0)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v record; r public.register_days;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  select * into v from public._verify_pin(p_staff_id, p_pin, false);
  if v.err is not null then return jsonb_build_object('ok', false, 'error', v.err); end if;
  if p_float_crc is null or p_float_crc < 0 or coalesce(p_float_usd, 0) < 0 then return jsonb_build_object('ok', false, 'error', 'bad_float'); end if;
  select * into r from public.register_days where closed_at is null order by business_date limit 1;
  if r.id is not null and r.business_date < public.cr_today() then
    return jsonb_build_object('ok', false, 'error', 'previous_open', 'business_date', r.business_date);
  end if;
  if r.id is not null then return jsonb_build_object('ok', false, 'error', 'already_open'); end if;
  select * into r from public.register_days where business_date = public.cr_today();
  if r.id is not null then return jsonb_build_object('ok', false, 'error', 'already_closed'); end if;
  insert into public.register_days (business_date, opened_by, opened_by_name, float_crc, float_usd)
    values (public.cr_today(), v.sid, v.sname, p_float_crc, round(coalesce(p_float_usd, 0), 2)) returning * into r;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('register_open', v.sid, v.sname, r.id::text,
            'opened the register with ' || p_float_crc || ' colones' || case when coalesce(p_float_usd, 0) > 0 then ' and ' || p_float_usd || ' dollars' else '' end,
            jsonb_build_object('business_date', r.business_date, 'float_crc', p_float_crc, 'float_usd', coalesce(p_float_usd, 0)));
  return jsonb_build_object('ok', true, 'register', to_jsonb(r));
end $$;

drop function if exists public.register_close(uuid, text, int, int, text);
create or replace function public.register_close(p_staff_id uuid, p_pin text, p_terminal_crc int, p_cash_counted_crc int, p_notes text,
                                                 p_cash_counted_usd numeric default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v record; r public.register_days; prev public.register_days; s record; e record; reclose boolean := false;
        d0 timestamptz; d1 timestamptz; fx numeric;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  select * into v from public._verify_pin(p_staff_id, p_pin, false);
  if v.err is not null then return jsonb_build_object('ok', false, 'error', v.err); end if;
  if p_terminal_crc is null or p_terminal_crc < 0 or p_cash_counted_crc is null or p_cash_counted_crc < 0
     or coalesce(p_cash_counted_usd, 0) < 0 then
    return jsonb_build_object('ok', false, 'error', 'bad_amounts');
  end if;
  select * into r from public.register_days where closed_at is null order by business_date limit 1 for update;
  if r.id is null then
    select * into r from public.register_days where business_date = public.cr_today() for update;
    if r.id is null then return jsonb_build_object('ok', false, 'error', 'not_open'); end if;
    reclose := true; prev := r;
  end if;
  d0 := public.cr_day_start(r.business_date);
  d1 := public.cr_day_start(r.business_date + 1);
  select count(*)::int as n,
         coalesce(sum(case when o.payment_method = 'cash_crc' then o.total_crc end), 0)::int as cash,
         coalesce(sum(case when o.payment_method = 'cash_usd' then o.total_crc end), 0)::int as usd,
         coalesce(sum(case when o.payment_method = 'card'     then o.total_crc end), 0)::int as card,
         coalesce(sum(case when o.payment_method = 'sinpe'    then o.total_crc end), 0)::int as sinpe,
         coalesce(sum(case when o.payment_method not in ('cash_crc','cash_usd','card','sinpe') then o.total_crc end), 0)::int as other,
         coalesce(sum(o.total_crc), 0)::int as total
    into s
    from public.orders o
    where o.created_at >= d0 and o.created_at < d1 and o.voided_at is null and coalesce(o.paid, true);
  select * into e from public._register_expected(r.business_date);
  select rate into fx from public._fx_for(r.business_date);
  update public.register_days set
      closed_at = now(), closed_by = v.sid, closed_by_name = v.sname,
      orders_count = s.n, sales_cash_crc = s.cash, sales_cash_usd_crc = s.usd, sales_card_crc = s.card,
      sales_sinpe_crc = s.sinpe, sales_other_crc = s.other, sales_total_crc = s.total,
      terminal_crc = p_terminal_crc, cash_counted_crc = p_cash_counted_crc,
      expected_cash_crc = float_crc + e.cash_crc,
      cash_diff_crc = p_cash_counted_crc - (float_crc + e.cash_crc),
      card_diff_crc = p_terminal_crc - s.card,
      usd_in = e.usd, expected_cash_usd = float_usd + e.usd,
      cash_counted_usd = case when p_cash_counted_usd is not null then round(p_cash_counted_usd, 2) end,
      cash_diff_usd = case when p_cash_counted_usd is not null then round(p_cash_counted_usd, 2) - (float_usd + e.usd) end,
      fx_rate = fx,
      notes = nullif(trim(coalesce(p_notes, '')), '')
    where id = r.id returning * into r;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values (case when reclose then 'register_reclose' else 'register_close' end, v.sid, v.sname, r.id::text,
            (case when reclose then 'closed the register again: ' else 'closed the register: ' end) ||
            'cash ' || (case when r.cash_diff_crc >= 0 then '+' else '' end) || r.cash_diff_crc ||
            case when r.cash_diff_usd is not null then ', dollars ' || (case when r.cash_diff_usd >= 0 then '+' else '' end) || r.cash_diff_usd else '' end ||
            ', card ' || (case when r.card_diff_crc >= 0 then '+' else '' end) || r.card_diff_crc,
            case when reclose then to_jsonb(r) || jsonb_build_object('previous', to_jsonb(prev)) else to_jsonb(r) end);
  return jsonb_build_object('ok', true, 'reclosed', reclose, 'register', to_jsonb(r) || jsonb_build_object('today', public.cr_today()));
end $$;
revoke all on function public.register_open(uuid, text, int, numeric), public.register_close(uuid, text, int, int, text, numeric) from public, anon;
grant execute on function public.register_open(uuid, text, int, numeric), public.register_close(uuid, text, int, int, text, numeric) to authenticated;

select canopy.migration_end(10, 'fx_cash');
notify pgrst, 'reload schema';
