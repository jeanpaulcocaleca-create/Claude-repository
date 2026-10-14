-- =====================================================================================================
-- Canopy OS · REINICIO OPERATIVO (una sola vez, decisión del dueño del 2026-10-14, D-038): borra las transacciones del
-- periodo de prueba y deja el café listo para empezar de cero. Para el SQL Editor de PRODUCCIÓN, ANTES de la migración
-- 0000, en la ventana de lanzamiento (docs/LANZAMIENTO-UNICO.md), SOLO después del respaldo cifrado verificado y de
-- guardar el resumen para el contador (supabase/tools/resumen-pruebas.sql).
--
-- Supabase → SQL Editor → New query → pegar TODO una sola vez → en la ÚLTIMA línea, entre las comillas, escriba la
-- referencia del respaldo (la fecha y hora del trabajo "Respaldo" en verde, por ejemplo 2026-10-16 03:12 UTC) en lugar
-- de RESPALDO-AAAA-MM-DD HH:MM, y BORRAR PRUEBAS (dos palabras, mayúsculas) en lugar de "escriba BORRAR PRUEBAS" → Run.
-- Resultado: UNA celda con lo borrado (cantidades), lo conservado (huellas iguales) y el resumen del periodo (cantidades y
-- totales, sin nombres). Guarde esa celda con el respaldo.
--
-- Todo o nada: si una sola revisión falla, no cambia NADA (una sola transacción). Se niega si:
--   · la base ya tiene migraciones (canopy.migrations existe): este reinicio es solo para la base de hoy, antes de 0000;
--   · ya se hizo una vez (la bitácora tiene la línea "reinicio_operativo");
--   · falta la referencia del respaldo o la palabra de confirmación no es exactamente BORRAR PRUEBAS;
--   · hay una venta de los últimos 60 minutos (o con fecha futura), alguien marcó en el reloj hace menos de una hora, o hay
--     una caja abierta: el café sigue trabajando, no es la ventana;
--   · alguna tabla conservada cambiaría (huella antes ≠ huella después);
--   · alguna tabla que debe quedar vacía no queda vacía, o algún inventario no queda en cero.
-- Mientras corre (segundos) nadie puede anotar ventas, preguntas ni marcas: quedan en espera y entran después, al café limpio.
--
-- SE BORRA (es historia de prueba; el respaldo cifrado la conserva): ventas y sus líneas, partes de cuentas y sus líneas,
-- adiciones a cuentas abiertas, descuentos aprobados, anulaciones (son ventas), pedidos de habitación (son ventas),
-- días de caja, turnos del reloj, movimientos de inventario (las existencias quedan en 0: se cargan tras el conteo
-- físico), pedidos a proveedores y sus líneas, sesiones de PIN (caja, ventas, inventario), las preguntas de visitantes y
-- los bloqueos de PIN por intentos fallidos (el PIN de cada persona sigue igual).
-- SE CONSERVA, idéntico: categorías y platos del menú (precios, fotos, textos), recetas, insumos (nombre, empaque, costo,
-- proveedor, nivel deseado, punto de pedido), proveedores, personal (nombres, puestos, PINs), ingresos y permisos
-- (los dos dueños), ajustes del café, pizarra (TV) y sus diapositivas, habitaciones y sus códigos QR, y la bitácora,
-- que recibe UNA línea "reinicio_operativo" con las cantidades, la huella del resumen y la referencia del respaldo.
-- Los aparatos del café no se salen: las sesiones no se tocan. Una venta que una tableta tuviera guardada sin internet
-- desde antes del reinicio entra después marcada "before_reset" para que el encargado la anule.
-- Reversión: solo restaurando el respaldo en un proyecto nuevo (docs/RESPALDOS.md). Las dos funciones de abajo existen
-- solo mientras corre esta consulta (pg_temp): no quedan en la base.
-- =====================================================================================================

-- the archive summary: counts and totals by day and by payment method, never a name, a note or a phone. The same
-- figures as supabase/tools/resumen-pruebas.sql; its 'huella' (md5) is what the log keeps, so the two can be matched
create or replace function pg_temp.canopy_resumen_pruebas()
returns jsonb language sql stable as $$
  with d as (select (o.created_at at time zone 'America/Costa_Rica')::date as dia, o.* from public.orders o),
       ventas as (select * from d where paid and voided_at is null and part_of is null),                        -- bills paid, not voided
       partes as (select * from d where part_of is not null and voided_at is null and given_back_at is null),  -- part payments that stand
       -- the money as it was taken: a bill paid whole by its method, a bill paid in parts by each part's method
       dinero as (select payment_method, total_crc from ventas where coalesce(parts_crc, 0) = 0 union all select payment_method, total_crc from partes)
  select jsonb_build_object(
    'periodo', jsonb_build_object('desde', (select min(dia) from d), 'hasta', (select max(dia) from d), 'dias_con_ventas', (select count(distinct dia) from ventas)),
    'ventas_pagadas', jsonb_build_object('cantidad', (select count(*) from ventas), 'total_crc', (select coalesce(sum(total_crc), 0) from ventas),
                                        'descuentos_crc', (select coalesce(sum(discount_crc), 0) from ventas), 'pagadas_en_partes', (select count(*) from ventas where coalesce(parts_crc, 0) > 0)),
    'por_dia', (select coalesce(jsonb_agg(jsonb_build_object('dia', dia, 'ventas', n, 'total_crc', t) order by dia), '[]') from
                 (select dia, count(*) n, sum(total_crc) t from ventas group by dia) q),
    'dinero_recibido', jsonb_build_object('total_crc', (select coalesce(sum(total_crc), 0) from dinero),
      'por_medio_de_pago', (select coalesce(jsonb_agg(jsonb_build_object('medio', payment_method, 'pagos', n, 'total_crc', t) order by payment_method), '[]') from
                             (select payment_method, count(*) n, sum(total_crc) t from dinero group by payment_method) q)),
    'partes_de_cuentas', jsonb_build_object('vigentes', (select count(*) from partes), 'total_crc', (select coalesce(sum(total_crc), 0) from partes),
                                           'anuladas', (select count(*) from d where part_of is not null and voided_at is not null),
                                           'devueltas', (select count(*) from d where part_of is not null and voided_at is null and given_back_at is not null)),
    'anulaciones', jsonb_build_object('cantidad', (select count(*) from d where voided_at is not null and part_of is null), 'total_crc', (select coalesce(sum(total_crc), 0) from d where voided_at is not null and part_of is null)),
    'pedidos_de_habitacion', (select count(*) from d where room_id is not null),
    'cuentas_abiertas_sin_pagar', (select count(*) from d where not paid and voided_at is null and part_of is null and coalesce(status, '') <> 'cancelled'),
    'pedidos_cancelados', (select count(*) from d where coalesce(status, '') = 'cancelled'),
    'dias_de_caja', jsonb_build_object('cantidad', (select count(*) from public.register_days), 'cerrados', (select count(*) from public.register_days where closed_at is not null),
                                      'ventas_segun_caja_crc', (select coalesce(sum(sales_total_crc), 0) from public.register_days),
                                      'diferencias_efectivo_crc', (select coalesce(sum(cash_diff_crc), 0) from public.register_days)),
    'turnos', jsonb_build_object('cantidad', (select count(*) from public.time_entries), 'personas', (select count(distinct staff_id) from public.time_entries),
                                'horas', (select coalesce(round(sum(extract(epoch from (coalesce(clock_out, clock_in) - clock_in)) / 3600)::numeric, 2), 0) from public.time_entries),
                                'abiertos', (select count(*) from public.time_entries where clock_out is null)),
    'inventario', jsonb_build_object('insumos', (select count(*) from public.stock_items), 'movimientos', (select count(*) from public.stock_moves),
                                    'compras_recibidas_crc', (select coalesce(round(sum(qty * coalesce(unit_cost, 0))::numeric, 2), 0) from public.stock_moves where kind = 'purchase'),
                                    'existencias_valoradas_crc', (select coalesce(round(sum(greatest(on_hand, 0) * cost_per_pack / nullif(pack_qty, 0))::numeric, 2), 0) from public.stock_items),
                                    'insumos_en_negativo', (select count(*) from public.stock_items where on_hand < 0)),
    'pedidos_a_proveedores', (select count(*) from public.purchase_orders),
    'descuentos_aprobados', (select count(*) from public.discount_approvals));
$$;

create or replace function pg_temp.canopy_reinicio(p_respaldo text, p_confirmacion text)
returns text language plpgsql as $$
declare
  resp text := btrim(coalesce(p_respaldo, ''));
  -- the fingerprints of everything that must stay: every column of every preserved table, except the columns this reset
  -- itself changes (stock_items.on_hand/updated_at: the stock goes to zero; staff.failed_pins/locked_until: the PIN lockouts
  -- of the test period are cleared), which are compared apart
  huella_sql constant text := $h$ select jsonb_build_object(
    'menu_categories', (select md5(coalesce(string_agg(t::text, ',' order by id), '')) from public.menu_categories t),
    'menu_items',      (select md5(coalesce(string_agg(t::text, ',' order by id), '')) from public.menu_items t),
    'recipes',         (select md5(coalesce(string_agg(t::text, ',' order by id), '')) from public.recipes t),
    'stock_items',     (select md5(coalesce(string_agg(id || ':' || name || ':' || coalesce(category, '') || ':' || coalesce(unit, '') || ':' || coalesce(pack_label, '') || ':' || pack_qty || ':' ||
                                            coalesce(cost_per_pack::text, '') || ':' || coalesce(vendor_id::text, '') || ':' || par_level || ':' || coalesce(reorder_point::text, '') || ':' ||
                                            coalesce(shelf_life_days::text, '') || ':' || coalesce(notes, '') || ':' || active || ':' || created_at, ',' order by id), '')) from public.stock_items),
    'vendors',         (select md5(coalesce(string_agg(t::text, ',' order by id), '')) from public.vendors t),
    'staff',           (select md5(coalesce(string_agg(id || ':' || name || ':' || active || ':' || created_at || ':' || role || ':' || coalesce(pin_hash, '') || ':' || can_see_sales, ',' order by id), '')) from public.staff),
    'app_accounts',    (select md5(coalesce(string_agg(t::text, ',' order by user_id), '')) from public.app_accounts t),
    'app_settings',    (select md5(coalesce(string_agg(t::text, ',' order by id), '')) from public.app_settings t),
    'board_settings',  (select md5(coalesce(string_agg(t::text, ',' order by id), '')) from public.board_settings t),
    'board_group_slides', (select md5(coalesce(string_agg(t::text, ',' order by id), '')) from public.board_group_slides t),
    'rooms',           (select md5(coalesce(string_agg(t::text, ',' order by id), '')) from public.rooms t),
    'audit_log_before', (select md5(coalesce(string_agg(t::text, ',' order by id), '')) from public.audit_log t where t.action <> 'reinicio_operativo'),
    'logins_auth',     (select md5(coalesce(string_agg(id::text, ',' order by id), '')) from auth.users)) $h$;
  limpiar constant text[] := array['order_part_lines', 'tab_adds', 'order_items', 'orders', 'discount_approvals', 'register_days', 'time_entries',
                                   'stock_moves', 'purchase_lines', 'purchase_orders', 'access_unlocks', 'sales_unlocks', 'inventory_unlocks', 'chat_questions'];
  antes jsonb; despues jsonb; resumen jsonb; borrado jsonb := '{}'; k text; n bigint; v_now timestamptz := clock_timestamp(); hecho timestamptz;
begin
  -- 0) nobody writes while this runs (seconds): a sale, a question or a punch arriving now waits and lands in the clean café;
  --    a second copy of this paste running at the same time waits here and then refuses
  lock table public.audit_log, public.orders, public.order_items, public.chat_questions, public.time_entries, public.register_days in share row exclusive mode;
  -- 1) only the database as it is today, before any migration: after 0000 the new tables and guards exist, and this
  --    reset was neither written nor rehearsed for them
  if to_regclass('canopy.migrations') is not null then
    raise exception 'Esta base ya tiene migraciones aplicadas: el reinicio es solo para la base de hoy, ANTES de la 0000. No se cambió nada.';
  end if;
  -- 1b) once: a second run would only add a second line to the log
  select max(at) into hecho from public.audit_log where action = 'reinicio_operativo';
  if hecho is not null then
    raise exception 'El reinicio operativo ya se hizo (%): es una sola vez. (Si pegó el texto dos veces en la misma consulta, nada cambió: péguelo una sola vez.) No se cambió nada.',
      to_char(hecho at time zone 'America/Costa_Rica', 'YYYY-MM-DD HH24:MI');
  end if;
  -- 2) the backup reference and the confirmation word, typed on purpose. (The placeholder text itself appears only in the
  --    header and in the last line, so a rehearsal that substitutes it by text replacement does not alter this check.)
  if resp = '' or resp ~ 'AAAA|HH:MM' or length(resp) < 8 then
    raise exception 'Falta la referencia del respaldo verificado: en la última línea, entre las primeras comillas, escriba la fecha y hora del trabajo "Respaldo" en verde (por ejemplo 2026-10-16 03:12 UTC). No se cambió nada.';
  end if;
  if coalesce(btrim(p_confirmacion), '') <> 'BORRAR PRUEBAS' then
    raise exception 'La palabra de confirmación debe ser exactamente BORRAR PRUEBAS (entre las segundas comillas de la última línea). No se cambió nada.';
  end if;
  -- 3) the café must be closed: no sale in the last 60 minutes (nor one dated in the future by a device's clock), no punch
  --    in the last 60 minutes, no register day open
  select count(*) into n from public.orders where created_at > v_now - interval '60 minutes';
  if n > 0 then
    raise exception 'Hay % venta(s) de los últimos 60 minutos (o con fecha futura): el café sigue trabajando. Hágalo después del cierre. No se cambió nada.', n;
  end if;
  select count(*) into n from public.time_entries where clock_in > v_now - interval '60 minutes' or clock_out > v_now - interval '60 minutes';
  if n > 0 then
    raise exception 'Alguien marcó en el reloj hace menos de una hora (% marca(s)): el café sigue trabajando. Hágalo después del cierre. No se cambió nada.', n;
  end if;
  select count(*) into n from public.register_days where closed_at is null;
  if n > 0 then
    raise exception 'Hay una caja abierta: ciérrela en la caja antes del reinicio. No se cambió nada.';
  end if;
  -- 4) what must stay, before; the summary of what goes
  execute huella_sql into antes;
  resumen := pg_temp.canopy_resumen_pruebas();
  -- 5) the clearing, in dependency order (children before parents; the stock trigger only fires on insert)
  foreach k in array limpiar loop
    execute format('delete from public.%I', k);
    get diagnostics n = row_count;
    borrado := borrado || jsonb_build_object(k, n);
  end loop;
  -- the stock starts at zero: the quantities are entered after the physical count (the owner's instruction)
  update public.stock_items set on_hand = 0, updated_at = v_now where on_hand <> 0;
  get diagnostics n = row_count;
  borrado := borrado || jsonb_build_object('stock_items_a_cero', n);
  -- PIN lockouts of the test period: nobody starts day one locked out (the PINs themselves do not change)
  update public.staff set failed_pins = 0, locked_until = null where coalesce(failed_pins, 0) <> 0 or locked_until is not null;
  get diagnostics n = row_count;
  borrado := borrado || jsonb_build_object('bloqueos_de_pin', n);
  -- 6) nothing else changed; everything cleared is empty; every stock at zero
  execute huella_sql into despues;
  if antes <> despues then
    raise exception 'Una tabla conservada cambiaría (%): se detuvo y no se cambió nada.',
      (select string_agg(key, ', ') from jsonb_each(antes) a where despues->a.key <> a.value);
  end if;
  foreach k in array limpiar loop
    execute format('select count(*) from public.%I', k) into n;
    if n <> 0 then raise exception 'La tabla % no quedó vacía (% filas): se detuvo y no se cambió nada.', k, n; end if;
  end loop;
  if exists (select 1 from public.stock_items where on_hand <> 0) then
    raise exception 'Un inventario no quedó en cero: se detuvo y no se cambió nada.';
  end if;
  -- 7) one line in the log: what was removed (counts), the fingerprint of the summary (the figures themselves stay in the
  --    cell the owner saves with the backup: the café log is readable by every manager) and the backup that keeps it all
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('reinicio_operativo', null, 'SQL Editor', null,
            'Reinicio operativo (D-038): ' || (borrado->>'orders') || ' ventas, ' || (borrado->>'register_days') || ' días de caja, ' || (borrado->>'time_entries') ||
            ' turnos, ' || (borrado->>'stock_moves') || ' movimientos de inventario y ' || (borrado->>'purchase_orders') || ' pedidos borrados; inventario en cero; respaldo ' || resp,
            jsonb_build_object('respaldo', resp, 'borrado', borrado, 'periodo', resumen->'periodo', 'resumen_md5', md5(resumen::text), 'conservado_huellas', despues, 'fecha', v_now));
  return 'reinicio hecho · respaldo ' || resp || E'\n' ||
         'borrado: ' || (select string_agg(key || ' ' || value, ', ' order by key) from jsonb_each_text(borrado)) || E'\n' ||
         'conservado idéntico: ' || (select string_agg(key, ', ' order by key) from jsonb_object_keys(antes) key) || E'\n' ||
         'huella del resumen: ' || md5(resumen::text) || ' (debe ser la "huella" de resumen-pruebas.sql guardado antes)' || E'\n' ||
         'resumen del periodo (guárdelo con el respaldo): ' || resumen::text;
end $$;

-- ▶ Escriba aquí, entre las comillas, la referencia del respaldo verificado y la palabra de confirmación, luego Run:
select pg_temp.canopy_reinicio('RESPALDO-AAAA-MM-DD HH:MM', 'escriba BORRAR PRUEBAS');
