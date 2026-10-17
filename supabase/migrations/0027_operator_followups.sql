-- =====================================================================================================
-- Canopy OS · migración 0027 · Quién cobra una cuenta abierta, «Terminar mi turno» marca la salida, columnas
--                              de quién cobró protegidas en las actualizaciones
-- Pegar TODO en Supabase → SQL Editor → New query → Run.  Requiere: 0026.
--
-- Qué hace (los tres pendientes de la 0008 anotados en D-032)
--   * Una cuenta abierta (mesa, cuenta por pagar) que se cierra en un solo pago guardaba quién la abrió, no quién
--     cobró. Ahora la venta guarda además quién cobró (orders.paid_operator_*): la persona con sesión en la caja
--     en el momento del pago (tab_pay). Los pagos parciales ya eran ventas propias de quien cobró.
--   * La caja no puede escribir ni cambiar esas columnas (ni las de quién marcó la venta) al actualizar una
--     venta: solo las funciones del servidor.
--   * pos_operator_end acepta p_clock_out: «Terminar mi turno» en la caja puede marcar también la salida en el
--     reloj de la persona de esa sesión (sin volver a pedir el PIN: la sesión se abrió con él). La página vieja,
--     que llama solo con el token, sigue funcionando.
-- Qué cambia para el personal: al terminar el turno la caja pregunta si marca también la salida.
-- Reversión: drop trigger order_zz_operator_upd; volver a crear tab_pay de supabase/pos-tabs.sql y
--   pos_operator_end de la 0008 (las columnas quedan).
-- =====================================================================================================
select canopy.migration_begin(27, 'operator_followups');

alter table public.orders add column if not exists paid_operator_id uuid;          -- who took the money on a bill paid later
alter table public.orders add column if not exists paid_operator_name text;
alter table public.orders add column if not exists paid_operator_session uuid;

-- the till never writes who rang or who took the money: on an update those columns stay as the server set them
create or replace function public._order_operator_upd()
returns trigger language plpgsql set search_path = public as $$
begin
  if current_user in ('authenticated', 'anon') then
    new.operator_id := old.operator_id; new.operator_name := old.operator_name; new.operator_session := old.operator_session;
    new.paid_operator_id := old.paid_operator_id; new.paid_operator_name := old.paid_operator_name; new.paid_operator_session := old.paid_operator_session;
  end if;
  return new;
end $$;
drop trigger if exists order_zz_operator_upd on public.orders;
create trigger order_zz_operator_upd before update on public.orders for each row execute function public._order_operator_upd();

-- tab_pay (supabase/pos-tabs.sql) with one addition: the last payment records who took the money
create or replace function public.tab_pay(p_order_id uuid, p_method text, p_lines jsonb, p_amount int, p_station text,
                                          p_expect int default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o public.orders; open_value int; val int := 0; amt int; ln jsonb; li record; part uuid; what text := ''; onacc int; r record; mode text;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  if p_method not in ('cash_crc', 'cash_usd', 'card', 'sinpe', 'other') then
    return jsonb_build_object('ok', false, 'error', 'bad_method'); end if;
  select * into o from public.orders where id = p_order_id for update;
  if o.id is null or o.part_of is not null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if o.voided_at is not null or o.status = 'cancelled' then return jsonb_build_object('ok', false, 'error', 'cancelled'); end if;
  if o.paid then return jsonb_build_object('ok', false, 'error', 'already_paid'); end if;
  if p_expect is not null and p_expect <> o.total_crc then return jsonb_build_object('ok', false, 'error', 'changed'); end if;
  -- a bill at 0 (a courtesy) is closed as a whole
  if o.total_crc <= 0 and (p_lines is not null or p_amount is not null) then
    return jsonb_build_object('ok', false, 'error', 'nothing_due'); end if;
  select coalesce(sum((qty - paid_qty) * price_crc), 0)::int into open_value from public.order_items where order_id = o.id;

  if p_lines is not null and jsonb_typeof(p_lines) = 'array' and jsonb_array_length(p_lines) > 0 then
    for ln in select * from jsonb_array_elements(p_lines) loop
      if coalesce(ln->>'qty', '') !~ '^[0-9]{1,3}$' or coalesce(ln->>'item_id', '') !~* '^[0-9a-f-]{36}$' then
        return jsonb_build_object('ok', false, 'error', 'changed'); end if;
    end loop;
    for li in select i.id, i.item_name, i.price_crc, i.qty - i.paid_qty as open_qty, p.qty as pick
                from public._tab_pick(p_lines) p left join public.order_items i on i.id = p.item_id and i.order_id = o.id
               order by i.round, i.added_at, i.item_name loop
      if li.id is null or li.pick > li.open_qty then return jsonb_build_object('ok', false, 'error', 'changed'); end if;
      val := val + li.price_crc * li.pick;
      what := what || case when what = '' then '' else ', ' end || li.pick || '× ' || li.item_name;
    end loop;
    if val <= 0 then return jsonb_build_object('ok', false, 'error', 'nothing_due'); end if;
    -- this person pays their items less their share of the discount still unused (what is left to pay for the
    -- open items, counting what was paid on account, spread over them); whoever pays the last items pays what is left
    onacc := greatest(0, o.parts_crc - o.parts_items_crc);
    amt := case when val >= open_value then o.total_crc
                else least(o.total_crc, round(val::numeric * (o.total_crc + onacc) / open_value)::int) end;
  elsif p_amount is not null then
    if p_amount < 1 or p_amount > o.total_crc then return jsonb_build_object('ok', false, 'error', 'bad_amount'); end if;
    amt := p_amount;
  else
    amt := o.total_crc;
  end if;
  if amt < 1 and o.total_crc > 0 then return jsonb_build_object('ok', false, 'error', 'nothing_due'); end if;

  if amt >= o.total_crc then
    -- the last payment closes the bill on the bill itself
    update public.order_items set paid_qty = qty where order_id = o.id;
    if o.source = 'room' and o.status not in ('new', 'preparing') then
      update public.orders set paid = true, payment_method = p_method, status = 'done', done_at = now(), guest_phone = null
        where id = o.id;
    else
      update public.orders set paid = true, payment_method = p_method where id = o.id;
    end if;
    -- who took the money: the person signed in on this device now (the header the POS sends), kept apart from who rang it
    select * into r from public._operator_resolve(now());
    mode := public.setting('operator_mode') #>> '{}';
    if r.staff_id is not null then
      update public.orders set paid_operator_id = r.staff_id, paid_operator_name = r.staff_name, paid_operator_session = r.session_id,
             flags = case when r.verified then flags else array_append(coalesce(flags, '{}'), 'paid_operator_unverified') end
       where id = o.id;
    elsif mode <> 'off' and o.source is distinct from 'room' then
      update public.orders set flags = array_append(coalesce(flags, '{}'), 'no_paid_operator') where id = o.id;
    end if;
    -- left unpaid past closing and paid on a later day: it belongs to the day the money came in
    if (o.created_at at time zone 'America/Costa_Rica')::date < (now() at time zone 'America/Costa_Rica')::date then
      update public.orders set created_at = now(),
             -- a kitchen ticket left over from an earlier day is not brought back to the kitchen screen
             status = case when status in ('new', 'preparing', 'ready') and coalesce(accepted_at, created_at) < public.cr_today_start()
                           then 'done' else status end,
             done_at = case when status in ('new', 'preparing', 'ready') and coalesce(accepted_at, created_at) < public.cr_today_start()
                            then coalesce(done_at, now()) else done_at end
        where id = o.id;
    end if;
    return jsonb_build_object('ok', true, 'closed', true, 'amount', o.total_crc, 'left', 0, 'order_id', o.id);
  end if;

  -- a payment for part of the bill is a sale of its own, with its own payment method (and its own operator: the insert trigger)
  part := gen_random_uuid();
  insert into public.orders (id, created_at, total_crc, payment_method, paid, status, done_at, source, needs_kitchen,
                             pickup_number, station, guest_name, part_of, notes)
    values (part, now(), amt, p_method, true, 'done', now(), 'front', false,
            o.pickup_number, coalesce(nullif(left(trim(coalesce(p_station, '')), 40), ''), o.station), o.guest_name, o.id,
            left('Part of ' || public._tab_label(o) || case when what <> '' then ': ' || what else '' end, 200));
  if val > 0 then
    insert into public.order_part_lines (part_id, item_id, qty) select part, p.item_id, p.qty from public._tab_pick(p_lines) p;
    update public.order_items i set paid_qty = i.paid_qty + p.qty
      from public._tab_pick(p_lines) p where p.item_id = i.id and i.order_id = o.id;
  end if;
  update public.orders set total_crc = total_crc - amt, parts_crc = parts_crc + amt,
                           parts_items_crc = parts_items_crc + case when val > 0 then amt else 0 end where id = o.id;
  return jsonb_build_object('ok', true, 'closed', false, 'amount', amt, 'left', o.total_crc - amt, 'part_id', part, 'order_id', o.id);
end $$;
revoke all on function public.tab_pay(uuid, text, jsonb, int, text, int) from public, anon;
grant execute on function public.tab_pay(uuid, text, jsonb, int, text, int) to authenticated;

-- «Terminar mi turno»: ends the device session and, if asked, clocks the same person out
drop function if exists public.pos_operator_end(text);
create or replace function public.pos_operator_end(p_token text, p_clock_out boolean default false)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare s public.operator_sessions; n int := 0;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  update public.operator_sessions set ended_at = now()
   where token_hash = encode(digest(coalesce(p_token, ''), 'sha256'), 'hex') and ended_at is null
   returning * into s;
  if s.id is not null and coalesce(p_clock_out, false) then
    begin
      update public.time_entries set clock_out = now()
       where staff_id = s.staff_id and clock_out is null and clock_in > now() - interval '20 hours';
      get diagnostics n = row_count;
    exception when others then
      if sqlerrm ~ 'period_locked' then return jsonb_build_object('ok', true, 'clocked_out', false, 'error', 'period_locked'); end if;
      raise;
    end;
  end if;
  return jsonb_build_object('ok', true, 'ended', s.id is not null, 'clocked_out', n > 0);
end $$;
revoke all on function public.pos_operator_end(text, boolean) from public, anon;
grant execute on function public.pos_operator_end(text, boolean) to authenticated;

select canopy.migration_end(27, 'operator_followups');
notify pgrst, 'reload schema';
