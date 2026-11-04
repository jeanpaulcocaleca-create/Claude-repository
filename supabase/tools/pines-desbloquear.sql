-- =====================================================================================================
-- Canopy OS · QUITAR TODOS LOS BLOQUEOS DE PIN a la vez · SQL Editor de PRODUCCIÓN
-- Supabase → SQL Editor → New query → pegar TODO → Run. Una sola transacción: si algo falla, no cambia nada.
--
-- Qué hace: a cada persona del equipo con el PIN bloqueado ahora (5 intentos equivocados en las casillas con lista de
--   nombres: abrir las áreas del dueño, anular, la ventana de descuento anterior…) le quita el bloqueo y pone su cuenta
--   de intentos en cero, con una línea «pin_lock_cleared» por persona a nombre de «owner (SQL Editor)». No cambia ningún
--   PIN ni ningún otro dato.
-- Cuándo: SOLO el dueño, en el procedimiento E-lock (alguien mantiene bloqueados a los encargados con la contraseña del
--   café; guía de activación de descuentos, sección 8): 1) cambiar la contraseña del ingreso del café («¿Olvidó su
--   contraseña?»); 2) en un aparato del café, Inicio → «Ingreso del propietario» → «Cerrar sesión en todos lados»;
--   3) este archivo; 4) volver a entrar en las tabletas con la contraseña nueva (las cajas registradas vuelven solas a
--   su puesto); 5) este archivo otra vez una hora después (un acceso ya emitido dura hasta 1 hora). Solo, sin los
--   pasos 1 y 2, los próximos 15 intentos lo deshacen.
-- Se niega si la 0038 no está aplicada.
-- Resultado: una celda: cuántos bloqueos se quitaron, cuántas personas siguen bloqueadas (debe ser 0) y, por puesto de
--   caja para descuentos, su estado, los códigos equivocados en 24 horas y la caja que lo ocupa.
-- =====================================================================================================
do $$ begin
  if not exists (select 1 from canopy.migrations where version = 38) then
    raise exception 'La migración 0038 no está aplicada: esta herramienta llega con ella. No se cambió nada.';
  end if;
end $$;
select jsonb_pretty(public._pin_locks_clear_all('owner (SQL Editor)')) as resultado;
