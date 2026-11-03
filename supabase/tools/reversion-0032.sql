-- =====================================================================================================
-- Canopy OS · REVERSIÓN DE LA MIGRACIÓN 0032 (recetas solo con PIN)
-- Supabase → SQL Editor → New query → pegar TODO → Run. Es una sola transacción: si algo falla, no cambia nada.
-- Úsela solo si la 0032 causa un problema y así lo decide el dueño.
--
-- Qué hace: devuelve a las páginas los permisos de antes sobre la tabla de recetas (las páginas anteriores del
--   Inventario vuelven a poder guardar recetas sin PIN; el historial lo anota como «cambio directo») y «Enlazar por
--   nombre» sin PIN. Quita la 0032 del registro de migraciones (la base vuelve a la versión 31).
-- Qué NO hace: no cambia ninguna receta ni el historial.
-- =====================================================================================================
do $$ begin
  if not exists (select 1 from canopy.migrations where version = 32) then
    raise exception 'La migración 0032 no está aplicada: no hay nada que revertir. No se cambió nada.';
  end if;
  if exists (select 1 from canopy.migrations where version > 32) then
    raise exception 'Hay migraciones posteriores a la 0032: revierta primero esas. No se cambió nada.';
  end if;
end $$;
set local lock_timeout = '8s';

-- supabase/inventory.sql
grant select, insert, update, delete on public.recipes to authenticated;
grant execute on function public.recipes_autolink() to authenticated;

delete from canopy.migrations where version = 32;
notify pgrst, 'reload schema';
select 'listo: la 0032 se revirtió; las recetas vuelven a aceptar cambios directos (anotados en el historial)' as resultado;
