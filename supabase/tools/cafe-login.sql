-- =====================================================================================================
-- Canopy OS · INGRESO DEL CAFÉ: el correo con el que entran la caja, el iPad y la pantalla de cocina pasa a ser un
-- ingreso de tipo café ("cafe"). Para el SQL Editor de PRODUCCIÓN.
-- Supabase → SQL Editor → New query → pegar TODO → en la línea "▶ PARTE 1" (al final) cambie correo@ejemplo.com por
-- ese correo → Run. Resultado: una celda, por ejemplo "ca***@gmail.com → cafe".
--
-- Por qué: hoy esos aparatos entran con un ingreso de tipo dueño ("owner") sin código del teléfono. Mientras nadie
-- escriba un PIN, eso funciona igual que un ingreso del café (probado: mismas reglas, mismas pantallas), pero deja
-- abierto lo que un ingreso del café no permite:
--   * El código del teléfono: quien tenga la sesión de la tableta, o la contraseña, puede activarle un código, y
--     desde ese momento ese aparato es el dueño completo, sin PIN. Además, cada vez que se escribe el código de un
--     ingreso, Supabase cierra todas las demás sesiones de ese ingreso que entraron sin código: la caja y la cocina
--     se salen en pleno servicio, y al volver a entrar el Reloj, Inicio, Menú, Ventas e Inventario piden un código
--     que solo tiene quien lo activó.
--   * El primer dueño: si nadie del equipo tiene el rol "dueño", un PIN de encargado en un ingreso de tipo dueño
--     puede crear o ascender a un dueño. En un ingreso del café no.
--   * Se sale solo tras 30 minutos sin uso en Reloj, Inicio, Menú, Ventas e Inventario, e Inicio ofrece "cerrar la
--     sesión en todos lados".
-- Un ingreso del café nunca llega a dueño, ni con código. En la tableta las áreas del dueño se siguen abriendo con
-- un PIN de encargado o del dueño (15 minutos); lo único nuevo es que el Reloj pide ese PIN al corregir un turno.
-- Los aparatos no se salen ni hay que volver a entrar: es el mismo ingreso con otro tipo. Hágalo antes de publicar
-- las páginas nuevas. Nunca active el código del teléfono en un ingreso que use un aparato del café: actívelo solo
-- en su ingreso personal, desde su teléfono.
--
-- Se niega y no cambia nada si: falta escribir el correo; no hay ningún ingreso con ese correo; ese ingreso tiene el
-- código del teléfono activado (es el ingreso personal de alguien); es el ingreso del contador; o no quedaría ningún
-- otro ingreso de tipo dueño. Si ya era del café, no cambia nada. Si cambia, deja una línea en el registro de
-- aprobaciones ("login_kind_change", por "SQL Editor", con el tipo anterior y el nuevo).
-- Sirve antes de la migración 0000 y después de la 0025. Las dos funciones de abajo existen solo mientras corre esta
-- consulta (pg_temp): no quedan en la base, y la de la parte 2 no hace nada si nadie la llama.
-- Reversión: select public.make_owner('el correo');
--
-- PARTE 2 · SOLO SI ESE CORREO NO ES SUYO (la última línea, desactivada con --): quita el acceso de dueño de un
-- correo que no es suyo, por ejemplo uno que nunca entró. Borra solo ese permiso (public.app_accounts) y deja una
-- línea "login_access_revoked" en el registro; el ingreso mismo (Authentication → Users) no se toca. Se niega si es
-- el último ingreso de tipo dueño. Para usarla: ponga -- delante de la línea de la PARTE 1, quite el -- del comienzo
-- de la línea de la PARTE 2, escriba el correo y Run. Reversión: select public.make_owner('el correo');
-- =====================================================================================================
create or replace function pg_temp.canopy_cafe_login(p_email text)
returns text language plpgsql as $$
declare
  em text := lower(btrim(coalesce(p_email, '')));
  masked text := left(split_part(em, '@', 1), 2) || '***@' || split_part(em, '@', 2);
  uid uuid; n int; old_kind text; has_code boolean := false;
begin
  if em in ('', 'correo@ejemplo.com') then
    raise exception 'Falta el correo: en la línea ▶ PARTE 1 cambie correo@ejemplo.com por el correo de los aparatos del café. No se cambió nada.';
  end if;
  select count(*), (array_agg(u.id))[1] into n, uid from auth.users u where lower(u.email) = em;
  if n = 0 then raise exception 'No hay ningún ingreso con el correo % (Authentication → Users). No se cambió nada.', masked; end if;
  if n > 1 then raise exception 'Hay % ingresos con el correo %. No se cambió nada.', n, masked; end if;
  if to_regclass('auth.mfa_factors') is not null then
    begin
      select exists (select 1 from auth.mfa_factors f where f.user_id = uid and f.status::text = 'verified') into has_code;
    exception when others then
      raise exception 'No se pudo revisar el código del teléfono de % (%). No se cambió nada.', masked, sqlerrm;
    end;
  end if;
  if has_code then
    raise exception '% tiene el código del teléfono activado: es el ingreso personal de alguien, no el de los aparatos del café. No se cambió nada.', masked;
  end if;
  select a.kind into old_kind from public.app_accounts a where a.user_id = uid;
  if old_kind = 'cafe' then return masked || ' ya era del café: no se cambió nada'; end if;
  if old_kind = 'accountant' then raise exception '% es el ingreso del contador: no se cambia aquí. No se cambió nada.', masked; end if;
  if not exists (select 1 from public.app_accounts a join auth.users u on u.id = a.user_id where a.kind = 'owner' and a.user_id <> uid) then
    raise exception 'No quedaría ningún otro ingreso de tipo dueño: primero dé acceso de dueño a su ingreso personal (select public.make_owner(''su correo'');). No se cambió nada.';
  end if;
  insert into public.app_accounts (user_id, kind, label) values (uid, 'cafe', em)
    on conflict (user_id) do update set kind = excluded.kind;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('login_kind_change', null, 'SQL Editor', uid::text, 'ingreso de los aparatos del café: ' || masked,
            jsonb_build_object('login', masked, 'old_kind', old_kind, 'new_kind', 'cafe'));
  return masked || ' → cafe';
end $$;

create or replace function pg_temp.canopy_revoke_login(p_email text)
returns text language plpgsql as $$
declare
  em text := lower(btrim(coalesce(p_email, '')));
  masked text := left(split_part(em, '@', 1), 2) || '***@' || split_part(em, '@', 2);
  uid uuid; n int; old_kind text;
begin
  if em in ('', 'correo@ejemplo.com') then
    raise exception 'Falta el correo: en la línea ▶ PARTE 2 cambie correo@ejemplo.com por el correo que no es suyo. No se cambió nada.';
  end if;
  select count(*), (array_agg(u.id))[1] into n, uid from auth.users u where lower(u.email) = em;
  if n = 0 then raise exception 'No hay ningún ingreso con el correo % (Authentication → Users). No se cambió nada.', masked; end if;
  if n > 1 then raise exception 'Hay % ingresos con el correo %. No se cambió nada.', n, masked; end if;
  select a.kind into old_kind from public.app_accounts a where a.user_id = uid;
  if old_kind is distinct from 'owner' then
    raise exception '% no tiene acceso de dueño (tipo: %): aquí no se quita. No se cambió nada.', masked, coalesce(old_kind, 'ninguno');
  end if;
  if not exists (select 1 from public.app_accounts a join auth.users u on u.id = a.user_id where a.kind = 'owner' and a.user_id <> uid) then
    raise exception 'Es el último ingreso de tipo dueño: no se quita. No se cambió nada.';
  end if;
  with gone as (delete from public.app_accounts where user_id = uid and kind = 'owner' returning kind, created_at)
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    select 'login_access_revoked', null, 'SQL Editor', uid::text, 'quitó el acceso de dueño de ' || masked,
           jsonb_build_object('login', masked, 'old_kind', gone.kind, 'granted_at', gone.created_at)
      from gone;
  return masked || ' → sin acceso de dueño';
end $$;

-- ▶ PARTE 1 · escriba entre las comillas el correo con el que entran los aparatos del café:
select pg_temp.canopy_cafe_login('correo@ejemplo.com') as ingreso_del_cafe;

-- ▶ PARTE 2 · SOLO SI ESE CORREO NO ES SUYO (lea arriba):
-- select pg_temp.canopy_revoke_login('correo@ejemplo.com') as acceso_quitado;
