-- =====================================================================================================
-- Canopy OS · INGRESOS DEL PROYECTO DE PRUEBAS (solo en PRUEBAS; en producción se niega)
-- Antes: en el proyecto de PRUEBAS → Authentication → Users → Add user → Create new user, con "Auto Confirm User":
--   cafe.pruebas@hanginggardencafe.com     (la tableta de pruebas)
--   dueno.pruebas@hanginggardencafe.com    (el dueño en pruebas)
-- (las contraseñas las inventa usted y no las comparte con nadie)
-- Después: SQL Editor del proyecto de PRUEBAS → pegar TODO → Run.
-- La copia de pruebas viene anonimizada (todas las personas se llaman "Persona N" y no trae ingresos); si esta base
-- tiene nombres reales o ingresos que no son estos dos, es producción y el script no hace nada.
-- =====================================================================================================
do $$
begin
  if exists (select 1 from public.staff where name !~ '^Persona [0-9]+$') then
    raise exception 'Esta base tiene nombres reales del personal: parece PRODUCCIÓN. No se hizo nada.';
  end if;
  if exists (select 1 from public.app_accounts a left join auth.users u on u.id = a.user_id
              where lower(coalesce(u.email, '')) not in ('cafe.pruebas@hanginggardencafe.com', 'dueno.pruebas@hanginggardencafe.com')) then
    raise exception 'Esta base tiene ingresos que no son los de pruebas: parece PRODUCCIÓN. No se hizo nada.';
  end if;
end $$;
insert into public.app_accounts (user_id, kind, label)
select u.id, x.kind, u.email
  from (values ('cafe.pruebas@hanginggardencafe.com', 'cafe'), ('dueno.pruebas@hanginggardencafe.com', 'owner')) x(email, kind)
  join auth.users u on lower(u.email) = x.email
on conflict (user_id) do update set kind = excluded.kind, label = excluded.label;
select coalesce(string_agg(label || ' → ' || kind, ' · ' order by kind), 'Todavía no existen los ingresos de pruebas: créelos primero en Authentication')
       as ingresos_de_pruebas
  from public.app_accounts
 where lower(label) in ('cafe.pruebas@hanginggardencafe.com', 'dueno.pruebas@hanginggardencafe.com');
