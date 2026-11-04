-- =====================================================================================================
-- Canopy OS · REANUDAR los descuentos de todos los puestos detenidos o en espera · SQL Editor de PRODUCCIÓN
-- Supabase → SQL Editor → New query → pegar TODO → Run. Una sola transacción: si algo falla, no cambia nada.
--
-- Qué hace: cada puesto de caja para descuentos (1, 2 y 3, con caja registrada o libre) que esté detenido (12 códigos
--   equivocados en 24 horas) o esperando, vuelve a empezar su cuenta, como «Reanudar descuentos» en la bitácora, pero
--   sin PIN y fuera del tope (1 por puesto y 2 por café en 24 horas): queda una línea «discount_till_resumed» por
--   puesto, a nombre de «owner (SQL Editor)». Nada más cambia: ni los registros de las cajas ni ningún PIN.
-- Cuándo: SOLO el dueño, mientras E-06 no esté resuelto (sin código del teléfono), cuando una caja quedó detenida y ya
--   no quedan reanudaciones con PIN en la bitácora. Antes, mire en la bitácora quién y desde dónde escribió los códigos.
-- Se niega si la 0038 no está aplicada.
-- Resultado: una celda: cuántos puestos se reanudaron y, por puesto, su estado, los códigos equivocados en 24 horas y
--   la caja que lo ocupa (nombre y quién la registró), también los puestos libres.
-- =====================================================================================================
do $$ begin
  if not exists (select 1 from canopy.migrations where version = 38) then
    raise exception 'La migración 0038 no está aplicada: no hay cajas de descuento que reanudar. No se cambió nada.';
  end if;
end $$;
select jsonb_pretty(public._discount_tills_resume_all('owner (SQL Editor)')) as resultado;
