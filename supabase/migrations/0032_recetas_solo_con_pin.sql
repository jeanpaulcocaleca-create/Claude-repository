-- =====================================================================================================
-- Canopy OS · migración 0032 · recetas, etapa 1B: solo se cambian con el PIN de un encargado o del dueño
-- Pegar TODO en Supabase → SQL Editor → New query → Run. Requiere: 0031. Una sola transacción.
--
-- Qué hace
--   * Ninguna página puede escribir la tabla de recetas directamente: ni las versiones anteriores del Inventario que
--     un aparato tenga guardadas, ni una consulta directa con la sesión del café o del dueño. La única forma de
--     cambiar una receta es el editor nuevo, con el PIN de un encargado o del dueño (recipe_save y
--     recipes_autolink_pin, 0030), que deja cada cambio en el historial.
--   * «Enlazar por nombre» sin PIN (recipes_autolink, de supabase/inventory.sql) deja de estar disponible para las
--     páginas; el editor nuevo usa la versión con PIN.
--   * Leer recetas sigue igual (Inventario, Menú). Borrar un producto del menú sigue borrando su receta (queda la
--     versión «producto borrado» en el historial).
-- Qué NO cambia: la Caja y la cocina nunca escriben recetas: siguen igual, también sin internet.
-- Qué ve una página anterior del Inventario: al guardar una receta, «No se pudo guardar la receta» y la receta queda
--   como estaba (al recargar, el aparato toma la página nueva).
-- Cuándo: en la misma ventana que 0030 y 0031, antes o justo después de publicar las páginas nuevas.
-- Reversión: supabase/tools/reversion-0032.sql (devuelve los permisos de antes).
-- =====================================================================================================
select canopy.migration_begin(32, 'recetas_solo_con_pin');

revoke insert, update, delete, truncate, references, trigger on public.recipes from anon, authenticated;
grant select on public.recipes to authenticated;
revoke execute on function public.recipes_autolink() from public, anon, authenticated;

select canopy.migration_end(32, 'recetas_solo_con_pin');
notify pgrst, 'reload schema';
