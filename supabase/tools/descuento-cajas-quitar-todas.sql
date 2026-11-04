-- =====================================================================================================
-- Canopy OS · QUITAR EL REGISTRO de todas las cajas para descuentos y gastar todas sus llaves · SQL Editor de PRODUCCIÓN
-- Supabase → SQL Editor → New query → pegar TODO → Run. Una sola transacción: si algo falla, no cambia nada.
--
-- Qué hace: termina el registro de cada caja registrada para descuentos (queda una línea «discount_till_ended» por
--   caja, a nombre de «owner (SQL Editor)») y gasta TODAS las llaves de los aparatos, también las de cajas que cerraron
--   sesión. Después ninguna tableta da descuentos hasta que un encargado la registre otra vez en Reloj de marcas →
--   Bitácora de aprobaciones → «Registrar este dispositivo para descuentos» (los puestos quedan libres; cada uno
--   conserva su cuenta de códigos equivocados). La Caja sigue vendiendo, a precio completo. Ninguna fila se borra.
-- Cuándo: SOLO el dueño: una tableta perdida o robada, una sesión o una llave copiada, o una persona que abusa de los
--   registros (antes, en Equipo, cámbiele el PIN o desactívela). Si la contraseña del café pudo filtrarse, cámbiela.
-- Se niega si la 0038 no está aplicada.
-- Resultado: una celda: cuántas cajas se quitaron, cuántas llaves se gastaron y, por puesto, su estado, los códigos
--   equivocados en 24 horas y si quedó ocupado (debe quedar libre).
-- =====================================================================================================
do $$ begin
  if not exists (select 1 from canopy.migrations where version = 38) then
    raise exception 'La migración 0038 no está aplicada: no hay cajas de descuento que quitar. No se cambió nada.';
  end if;
end $$;
select jsonb_pretty(public._discount_tills_end_all('owner (SQL Editor)')) as resultado;
