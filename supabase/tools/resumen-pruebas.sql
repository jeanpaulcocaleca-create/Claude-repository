-- =====================================================================================================
-- Canopy OS · RESUMEN DEL PERIODO DE PRUEBA PARA EL CONTADOR (SOLO LECTURA: no cambia nada)
-- Supabase → SQL Editor → New query → pegar TODO → Run. Resultado: UNA celda ("resumen"). Guárdela en un archivo junto
-- con el respaldo cifrado ANTES del reinicio operativo (docs/LANZAMIENTO-UNICO.md): es la cuenta del periodo que se
-- borra. Trae cantidades y totales por día, el dinero recibido por medio de pago tal como lo suma la caja (una cuenta
-- pagada en partes cuenta cada pago por su medio; una devolución resta), el cuadre con los cierres de caja (debe dar 0),
-- anulaciones, descuentos, partes de cuentas, pedidos de habitación, días de caja y sus diferencias, turnos y horas,
-- compras e inventario valorado. Nunca nombres, notas, teléfonos ni PINs.
-- Sirve antes de la migración 0000 (la base de hoy); en una base migrada muestra lo mismo.
-- "huella" es la huella (md5) de las cifras: el reinicio guarda la misma huella en la bitácora ("resumen_md5"), así se
-- comprueba que lo que el contador recibió es lo que se borró. (Las preguntas de visitantes quedan fuera de la huella:
-- un visitante puede preguntar entre una consulta y la otra.)
-- =====================================================================================================
with d as (select (o.created_at at time zone 'America/Costa_Rica')::date as dia, o.* from public.orders o),
     ventas as (select * from d where paid and voided_at is null and part_of is null),            -- the bills closed: counts and discounts
     -- the money as the register adds it up: every paid, not-voided row; a bill paid whole, the LAST payment of a bill paid in
     -- parts (it stays on the bill's row, parts_crc > 0), each earlier part by its own method, a give-back as its negative twin
     cobros as (select * from d where paid and voided_at is null),
     partes as (select * from d where part_of is not null and voided_at is null),                 -- the parts, for information
     caja as (select business_date from public.register_days where closed_at is not null),
     cifras as (select jsonb_build_object(
  'periodo', jsonb_build_object('desde', (select min(dia) from d), 'hasta', (select max(dia) from d), 'dias_con_ventas', (select count(distinct dia) from ventas)),
  'ventas_pagadas', jsonb_build_object('cantidad', (select count(*) from ventas), 'total_crc', (select coalesce(sum(total_crc), 0) from cobros),
                                      'descuentos_crc', (select coalesce(sum(discount_crc), 0) from ventas), 'pagadas_en_partes', (select count(*) from ventas where coalesce(parts_crc, 0) > 0)),
  'por_dia', (select coalesce(jsonb_agg(jsonb_build_object('dia', dia, 'ventas', n, 'total_crc', t) order by dia), '[]') from
               (select dia, count(*) filter (where part_of is null) n, sum(total_crc) t from cobros group by dia) q),
  'dinero_recibido', jsonb_build_object('total_crc', (select coalesce(sum(total_crc), 0) from cobros),
    'por_medio_de_pago', (select coalesce(jsonb_agg(jsonb_build_object('medio', payment_method, 'pagos', n, 'total_crc', t) order by payment_method), '[]') from
                           (select payment_method, count(*) n, sum(total_crc) t from cobros group by payment_method) q)),
  -- the same money the register closings added up: the difference must be 0 on the days with a closed register
  'cuadre_con_caja', jsonb_build_object(
    'diferencia_crc', (select coalesce(sum(total_crc), 0) from cobros where dia in (select business_date from caja)) - (select coalesce(sum(sales_total_crc), 0) from public.register_days where closed_at is not null),
    'ventas_sin_caja_cerrada_crc', (select coalesce(sum(total_crc), 0) from cobros where dia not in (select business_date from caja))),
  'partes_de_cuentas', jsonb_build_object('vigentes', (select count(*) from partes where given_back_at is null and total_crc > 0), 'total_crc', (select coalesce(sum(total_crc), 0) from partes),
                                         'anuladas', (select count(*) from d where part_of is not null and voided_at is not null),
                                         'devueltas', (select count(*) from partes where given_back_at is not null),
                                         'devueltas_crc', (select coalesce(sum(total_crc), 0) from partes where given_back_at is not null)),
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
  'descuentos_aprobados', (select count(*) from public.discount_approvals)) as v)
select jsonb_pretty(cifras.v || jsonb_build_object(
  'generado', now(),
  'huella', md5(cifras.v::text),
  'preguntas_de_visitantes', (select count(*) from public.chat_questions),
  'conservado', jsonb_build_object('platos', (select count(*) from public.menu_items), 'categorias', (select count(*) from public.menu_categories), 'recetas', (select count(*) from public.recipes),
                                  'insumos', (select count(*) from public.stock_items), 'proveedores', (select count(*) from public.vendors), 'personal', (select count(*) from public.staff),
                                  'ingresos', (select count(*) from public.app_accounts), 'habitaciones', (select count(*) from public.rooms), 'ajustes', (select count(*) from public.app_settings),
                                  'pizarra', (select count(*) from public.board_settings), 'diapositivas', (select count(*) from public.board_group_slides), 'bitacora', (select count(*) from public.audit_log))))
  as resumen from cifras;
