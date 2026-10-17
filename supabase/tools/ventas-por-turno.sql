-- =====================================================================================================
-- Canopy OS · VENTAS POR TURNO (SOLO LECTURA: no cambia nada)
-- Supabase → SQL Editor → New query → pegar TODO → Run. Resultado: una tabla, primero los resúmenes y después
-- una fila por venta. Es para el dueño mientras la caja no anota quién cobra cada venta («Quién cobra», 0008).
--
-- Qué muestra, en hora de Costa Rica, de los días elegidos (por defecto hoy y los 6 días anteriores):
--   * "RESUMEN PERSONA", una fila por día y persona con entrada marcada en el Reloj: "ventas" y "total_crc" son
--     las ventas hechas mientras esa persona estaba A SOLAS en turno; "detalle" dice además cuántas se hicieron con
--     otras personas en turno (compartidas: no se reparten). "(nadie con entrada)": ventas sin nadie en turno.
--   * "RESUMEN ESTACIÓN", una fila por día y estación (el nombre del aparato que tomó la venta: el botón de arriba
--     en la Caja). Si el dueño pidió que cada cajero ponga su nombre al aparato al empezar ("Caja · nombre"), es
--     la fila de cada cajero. Los pedidos de habitación van en su propia fila. Usa las reglas del cierre de caja:
--     las filas de un día suman lo que el cierre cuenta para ese día (una venta sin internet que subió después del
--     cierre está aquí y no en el cierre).
--   * "venta", una por venta: hora, estación, monto, qué es ("detalle"), forma de pago, quién tenía la entrada
--     marcada ("en_turno", con 5 minutos de margen) y "atribucion": el nombre si había UNA sola persona;
--     "compartida (n)" si había n; "nadie con entrada" si nadie había marcado; "huésped (habitación)" en un pedido
--     de habitación.
-- Solo cuentan las ventas que cuenta el cierre de caja: ni anuladas ni pendientes de pago (estas dicen
-- "· no cuenta" en "detalle" y no entran en los resúmenes).
--
-- Límites (léalos antes de sacar conclusiones):
--   * NO dice quién cobró: el Reloj no sabe en qué aparato está cada persona. Con dos o más en turno la venta es
--     "compartida" y no se puede repartir. Sirve para ver cómo va cada turno, no para cobrarle a nadie una
--     diferencia.
--   * Una cuenta abierta pagada de una vez cuenta a la hora en que se marcó en la caja, con su estación (o a la hora
--     del pago, si se pagó otro día). Cada pago por partes cuenta a su propia hora, con la estación del aparato que
--     lo cobró.
--   * La hora es la del aparato que tomó la venta (una venta sin internet guarda su hora y sube después).
--   * Una entrada sin salida, o un turno de más de 16 horas (una salida olvidada que se cerró al marcar al día
--     siguiente), cuenta como máximo 16 horas y sale con "(sin salida)" o "(más de 16 h)" en "en_turno".
--   * Los pedidos de habitación los hace el huésped: no se atribuyen a nadie.
--   * Dos personas del equipo con el mismo nombre salen como dos filas con ese nombre en el resumen.
-- No muestra PINs, correos ni claves: solo nombres del equipo, montos, estaciones y quién aprobó un descuento.
-- Lee solo los pedidos, las marcas del Reloj y los nombres del equipo (orders, time_entries, staff), que
-- producción ya tiene. Sirve antes y después de las migraciones.
-- Para ver otros días: cambie las dos líneas marcadas con ▶ más abajo, y nada más.
-- =====================================================================================================
-- Primero: la base misma rechaza cualquier cambio dentro de esta consulta (todo lo pegado corre como una sola
-- transacción de solo lectura).
set transaction read only;
with p as (
  -- DÍAS DEL REPORTE (hora de Costa Rica), del primero al último, ambos incluidos. Por defecto: hoy y los 6 días
  -- anteriores. Para otros días cambie las dos líneas ▶ así (fechas AAAA-MM-DD):
  --   select date '2026-10-15' as desde,
  --          date '2026-10-21' as hasta
  select (now() at time zone 'America/Costa_Rica')::date - 6 as desde,   -- ▶ primer día
         (now() at time zone 'America/Costa_Rica')::date     as hasta    -- ▶ último día
),
-- the report's limits as instants: midnight in Costa Rica, whatever the session's time zone
r as (
  select p.desde::timestamp at time zone 'America/Costa_Rica' as t0,
         (p.hasta + 1)::timestamp at time zone 'America/Costa_Rica' as t1
    from p
),
-- shifts that touch the report's days; a shift with no clock-out, or longer than 16 hours (a forgotten clock-out
-- closed by the next day's punch: the Reloj's card is a toggle), counts at most 16 hours (never past now) and is flagged
turnos as (
  select t.staff_id, s.name as persona, t.clock_in,
         least(coalesce(t.clock_out, now()), t.clock_in + interval '16 hours') as fin,
         case when t.clock_out is null then ' (sin salida)'
              when t.clock_out > t.clock_in + interval '16 hours' then ' (más de 16 h)'
              else '' end as aviso
    from public.time_entries t
    join public.staff s on s.id = t.staff_id
    cross join r
   where t.clock_in < r.t1 + interval '5 minutes'
     and least(coalesce(t.clock_out, t.clock_in + interval '16 hours'), t.clock_in + interval '16 hours')
         > r.t0 - interval '5 minutes'
),
ventas as (
  select o.id, o.created_at,
         (o.created_at at time zone 'America/Costa_Rica')::date as dia,
         to_char(o.created_at at time zone 'America/Costa_Rica', 'HH24:MI') as hora,
         coalesce(o.source, '') = 'room' as habitacion,
         coalesce(nullif(trim(o.station), ''),
                  case when coalesce(o.source, '') = 'room' then '(habitación)' else '(sin estación)' end) as estacion,
         o.total_crc, o.payment_method,
         case when o.voided_at is not null then 'anulada'
              when o.status = 'cancelled' then 'cancelada'
              when o.paid = false then 'cuenta abierta, sin pagar'
              when o.part_of is not null then 'pago parcial de una cuenta'
              when o.total_crc < 0 then 'devolución'
              when coalesce(o.source, '') = 'room' then 'pedido de habitación'
              else 'venta' end as estado,
         -- what the register close counts (supabase/register.sql, migration 0010): not voided, not waiting for payment
         o.voided_at is null and coalesce(o.paid, true) as cuenta,
         nullif(trim(o.discount_by), '') as descuento_aprobado_por
    from public.orders o
    cross join r
   where o.created_at >= r.t0 and o.created_at < r.t1
),
-- who was clocked in at each sale (5 minutes of margin); a person with two shifts at once counts once
quien as (
  select v.id, t.staff_id, t.persona, max(t.aviso) as aviso
    from ventas v
    join turnos t on t.clock_in <= v.created_at + interval '5 minutes' and t.fin >= v.created_at - interval '5 minutes'
   group by v.id, t.staff_id, t.persona
),
en_turno as (
  select id, count(*) as n, min(persona) as unico,
         string_agg(persona || aviso, ', ' order by persona, staff_id) as nombres
    from quien
   group by id
),
detalle as (
  select v.*, coalesce(e.n, 0) as n_en_turno, coalesce(e.nombres, '') as en_turno,
         case when v.habitacion then 'huésped (habitación)'
              when e.n is null then 'nadie con entrada'
              when e.n = 1 then e.unico
              else 'compartida (' || e.n || ')' end as atribucion
    from ventas v
    left join en_turno e on e.id = v.id
),
-- summaries: only what the register close counts; room orders are nobody's
por_persona as (
  select d.dia, q.staff_id, q.persona,
         count(*) filter (where d.n_en_turno = 1) as ventas_a_solas,
         coalesce(sum(d.total_crc) filter (where d.n_en_turno = 1), 0) as crc_a_solas,
         count(*) filter (where d.n_en_turno > 1) as ventas_compartidas,
         coalesce(sum(d.total_crc) filter (where d.n_en_turno > 1), 0) as crc_compartidas,
         string_agg(distinct d.estacion, ', ') as estaciones
    from detalle d
    join quien q on q.id = d.id
   where d.cuenta and not d.habitacion
   group by d.dia, q.staff_id, q.persona
),
nadie as (
  select d.dia, count(*) as ventas, coalesce(sum(d.total_crc), 0) as crc, string_agg(distinct d.estacion, ', ') as estaciones
    from detalle d
   where d.cuenta and not d.habitacion and d.n_en_turno = 0
   group by d.dia
),
por_estacion as (
  select d.dia, case when d.habitacion then '(pedidos de habitación)' else d.estacion end as estacion,
         count(*) as ventas, coalesce(sum(d.total_crc), 0) as crc
    from detalle d
   where d.cuenta
   group by 1, 2
)
select fila, dia, hora, atribucion, estacion, ventas, total_crc, detalle, pago, en_turno, descuento_aprobado_por
  from (
    select 'RESUMEN PERSONA' as fila, dia, '' as hora, persona as atribucion, estaciones as estacion,
           ventas_a_solas as ventas, crc_a_solas as total_crc,
           'a solas en turno: ' || ventas_a_solas || ' · compartidas: ' || ventas_compartidas || ' (₡' || crc_compartidas || ')' as detalle,
           '' as pago, '' as en_turno, null::text as descuento_aprobado_por,
           1 as orden, persona as clave, null::timestamptz as cuando
      from por_persona
    union all
    select 'RESUMEN PERSONA', dia, '', '(nadie con entrada)', estaciones, ventas, crc, 'nadie había marcado entrada',
           '', '', null, 2, '', null
      from nadie
    union all
    select 'RESUMEN ESTACIÓN', dia, '', '', estacion, ventas, crc, '', '', '', null, 3, estacion, null
      from por_estacion
    union all
    select 'venta', dia, hora, atribucion, estacion, null, total_crc,
           estado || case when cuenta then '' else ' · no cuenta' end, payment_method, en_turno, descuento_aprobado_por,
           4, '', created_at
      from detalle
  ) x
 order by orden = 4, dia, orden, clave, cuando;
