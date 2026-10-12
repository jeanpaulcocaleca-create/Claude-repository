-- =====================================================================================================
-- Canopy OS · INGRESOS DEL PROYECTO DE PRUEBAS (solo en PRUEBAS; en producción se niega)
-- Antes: en el proyecto de PRUEBAS → Authentication → Users → Add user → Create new user, con "Auto Confirm User":
--   cafe.pruebas@hanginggardencafe.com     (la tableta de pruebas)
--   dueno.pruebas@hanginggardencafe.com    (el dueño en pruebas)
-- (las contraseñas las inventa usted y no las comparte con nadie)
-- Después: SQL Editor del proyecto de PRUEBAS → pegar TODO → Run.
-- La copia de pruebas viene anonimizada (todas las personas se llaman "Persona N"); si esta base tiene nombres reales,
-- es producción y el script no hace nada.
-- =====================================================================================================
do $$
begin
  if exists (select 1 from public.staff where name !~ '^Persona [0-9]+$') then
    raise exception 'Esta base tiene nombres reales del personal: parece PRODUCCIÓN. No se hizo nada.';
  end if;
end $$;
insert into public.app_accounts (user_id, kind, label)
select u.id, x.kind, u.email
  from (values ('cafe.pruebas@hanginggardencafe.com', 'cafe'), ('dueno.pruebas@hanginggardencafe.com', 'owner')) x(email, kind)
  join auth.users u on lower(u.email) = x.email
on conflict (user_id) do update set kind = excluded.kind, label = excluded.label;
select coalesce(string_agg(label || ' → ' || kind, ' · ' order by kind), 'Todavía no existen los ingresos de pruebas: créelos primero en Authentication')
       as ingresos_de_pruebas
  from public.app_accounts;
