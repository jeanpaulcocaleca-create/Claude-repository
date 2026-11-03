-- =====================================================================================================
-- Canopy OS · migración 0007 · Retirar hours_report (permitía probar PINs sin límite)
-- Pegar TODO en Supabase → SQL Editor → New query → Run.  Requiere: 0006.
--
-- Por qué
--   * hours_report revisa un PIN pero está marcada como "solo lectura": la base no puede guardar el intento
--     fallido, así que nunca bloquea después de 5 PINs equivocados. Con la sesión de la tableta se podían
--     probar los 10 000 PINs de 4 dígitos.
--   * La página de horas usa hours_for desde la actualización de manager-mode.sql; hours_report solo quedaba
--     para páginas viejas.
-- Qué hace: quita el permiso de usar hours_report (la función queda, sin acceso).
-- Qué cambia para el personal: nada.
-- Reversión: grant execute on function public.hours_report(uuid, text, timestamptz, timestamptz) to authenticated;
-- =====================================================================================================
select canopy.migration_begin(7, 'retire_hours_report');

revoke all on function public.hours_report(uuid, text, timestamptz, timestamptz) from public, anon, authenticated;

select canopy.migration_end(7, 'retire_hours_report');
notify pgrst, 'reload schema';
