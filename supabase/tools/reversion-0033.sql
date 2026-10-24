-- =====================================================================================================
-- Canopy OS · REVERSIÓN DE LA MIGRACIÓN 0033 (PIN más seguros)
-- Supabase → SQL Editor → New query → pegar TODO → Run. Es una sola transacción: si algo falla, no cambia nada.
-- Úsela solo si la 0033 causa un problema y así lo decide el dueño, fuera del horario de atención.
--
-- Qué hace
--   * Deja exactamente como estaban antes de la 0033 (misma huella en la foto de producción): la comprobación de PIN
--     (0025), el editor del equipo (0028) y las aperturas de las áreas de dueño (supabase/manager-mode.sql).
--   * Quita las funciones nuevas: quitar un bloqueo de PIN (pin_lock_clear), cerrar todas las aperturas de una cuenta
--     (access_lock_all) y la sesión del token (_jwt_session).
--   * Quita la 0033 del registro de migraciones (la base vuelve a la versión 32).
-- Qué NO hace: no borra la columna session_id de las aperturas (queda sin uso) ni ninguna fila del registro.
-- Aviso: vuelven los problemas que la 0033 corrigió (D-053): el editor del equipo deja averiguar PIN, un PIN vacío
--   cuenta como intento, los bloqueos no quedan anotados, se puede volver a activar a alguien con su PIN viejo aunque
--   otra persona activa ya lo use, y una apertura en un aparato deja cambiar las fotos del menú desde cualquier otro
--   aparato de la misma cuenta.
-- Después: las páginas nuevas siguen funcionando; «Quitar bloqueo del PIN» contesta que falta la función.
-- =====================================================================================================
do $$ begin
  if not exists (select 1 from canopy.migrations where version = 33) then
    raise exception 'La migración 0033 no está aplicada: no hay nada que revertir. No se cambió nada.';
  end if;
  if exists (select 1 from canopy.migrations where version > 33) then
    raise exception 'Hay migraciones posteriores a la 0033: revierta primero esas. No se cambió nada.';
  end if;
end $$;
set local lock_timeout = '8s';

drop function if exists public.pin_lock_clear(uuid, uuid, text);
drop function if exists public.access_lock_all();

-- 0025
create or replace function public._verify_pin(p_staff_id uuid, p_pin text, p_need_manager boolean,
                                              out err text, out sid uuid, out sname text)
language plpgsql security definer set search_path = public, extensions as $$
declare s public.staff;
begin
  select * into s from public.staff where id = p_staff_id for update;   -- tries sent at the same moment are counted one by one
  if s.id is null then err := 'unknown_staff'; return; end if;
  if not s.active then err := 'inactive'; return; end if;
  if p_need_manager and s.role not in ('manager', 'owner') then err := 'not_manager'; return; end if;
  if s.locked_until is not null and s.locked_until > now() then err := 'locked'; return; end if;
  if s.pin_hash is null or crypt(coalesce(p_pin, ''), s.pin_hash) <> s.pin_hash then
    update public.staff
      set failed_pins = failed_pins + 1,
          locked_until = case when failed_pins + 1 >= 5 then now() + interval '10 minutes' else locked_until end
      where id = s.id;
    err := 'bad_pin'; return;
  end if;
  update public.staff set failed_pins = 0, locked_until = null where id = s.id;
  sid := s.id; sname := s.name; err := null;
end $$;
revoke all on function public._verify_pin(uuid, text, boolean) from public, anon, authenticated;

-- 0028
create or replace function public.manager_save_staff(p_manager_id uuid, p_manager_pin text,
    p_id uuid, p_name text, p_pin text, p_active boolean, p_role text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v record; u record; lvl text; bootstrap boolean; nid uuid; role_final text;
        old public.staff; managers_left int; msid uuid; msname text; strip_sales boolean;
begin
  lvl := public.access_level();
  bootstrap := not exists (select 1 from public.staff where active and role in ('manager', 'owner'));
  if bootstrap then
    if lvl is null and public.account_kind() is distinct from 'owner' then
      return jsonb_build_object('ok', false, 'error', 'owner_only'); end if;
    msid := null; msname := 'first setup';
  elsif lvl is null then
    return jsonb_build_object('ok', false, 'error', 'owner_only');
  elsif p_manager_id is not null or coalesce(p_manager_pin, '') <> '' then
    select * into v from public._verify_pin(p_manager_id, p_manager_pin, true);   -- an extra approval, if given
    if v.err is not null then return jsonb_build_object('ok', false, 'error', v.err); end if;
    msid := v.sid; msname := v.sname;
  else
    select * into u from public._unlock_staff();
    msid := u.staff_id; msname := public._owner_label();
  end if;
  if coalesce(trim(p_name), '') = '' then return jsonb_build_object('ok', false, 'error', 'missing_name'); end if;
  if p_pin is not null and p_pin <> '' then
    if p_pin !~ '^[0-9]{4,8}$' then return jsonb_build_object('ok', false, 'error', 'bad_pin_format'); end if;
    if public._weak_pin(p_pin) then return jsonb_build_object('ok', false, 'error', 'weak_pin'); end if;
    -- two people never share a PIN: the clock and the till could not tell them apart
    if exists (select 1 from public.staff s where s.active and s.id is distinct from p_id and s.pin_hash = crypt(p_pin, s.pin_hash)) then
      return jsonb_build_object('ok', false, 'error', 'pin_in_use'); end if;
  end if;
  role_final := case when p_role in ('owner', 'manager') then p_role else 'staff' end;
  if bootstrap and role_final = 'staff' then role_final := 'manager'; end if;
  if p_id is not null then
    select * into old from public.staff where id = p_id;
    if old.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  end if;
  -- the owner role: only the owner with the phone code (D-027: the first-owner exception on a login without a code is closed)
  if (role_final = 'owner' or old.role = 'owner') and not (bootstrap or public.owner_with_code()) then
    return jsonb_build_object('ok', false, 'error', 'owner_role_only');
  end if;
  -- Another manager's PIN, role or active state: only an owner. Otherwise a GM could set a colleague's PIN
  -- and then open sales or approve voids and discounts in that colleague's name. Before the team has an
  -- owner, managers may still do it, but a PIN set by someone else switches "may open sales" off.
  strip_sales := false;
  if old.id is not null and old.role = 'manager' and old.id is distinct from msid and lvl is distinct from 'owner'
     and not bootstrap
     and ((p_pin is not null and p_pin <> '') or role_final <> old.role or coalesce(p_active, old.active) <> old.active) then
    if exists (select 1 from public.staff where active and role = 'owner') then return jsonb_build_object('ok', false, 'error', 'manager_needs_owner'); end if;
    strip_sales := p_pin is not null and p_pin <> '';
  end if;

  if p_id is null then
    if p_pin is null or p_pin = '' then return jsonb_build_object('ok', false, 'error', 'missing_pin'); end if;
    insert into public.staff (name, pin_hash, active, role)
      values (trim(p_name), crypt(p_pin, gen_salt('bf')), coalesce(p_active, true), role_final)
      returning id into nid;
  else
    if old.role in ('manager', 'owner') and old.active and (role_final = 'staff' or not coalesce(p_active, true)) then
      select count(*) into managers_left from public.staff
        where active and role in ('manager', 'owner') and id <> old.id;
      if managers_left = 0 then return jsonb_build_object('ok', false, 'error', 'last_manager'); end if;
    end if;
    update public.staff set
      name = trim(p_name),
      pin_hash = case when p_pin is not null and p_pin <> '' then crypt(p_pin, gen_salt('bf')) else pin_hash end,
      failed_pins = case when p_pin is not null and p_pin <> '' then 0 else failed_pins end,
      locked_until = case when p_pin is not null and p_pin <> '' then null else locked_until end,
      active = coalesce(p_active, active),
      role = role_final,
      can_see_sales = case when role_final = 'manager' and not strip_sales then can_see_sales else false end
      where id = p_id;
    nid := p_id;
  end if;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('staff_save', msid, msname, nid::text,
      case when p_id is null then 'added ' else 'updated ' end || trim(p_name),
      jsonb_build_object('name', trim(p_name), 'active', coalesce(p_active, true), 'role', role_final,
                         'pin_changed', (p_pin is not null and p_pin <> ''), 'first_setup', bootstrap));
  return jsonb_build_object('ok', true, 'id', nid, 'role', role_final, 'first_setup', bootstrap);
end $$;
revoke all on function public.manager_save_staff(uuid, text, uuid, text, text, boolean, text) from public, anon;
grant execute on function public.manager_save_staff(uuid, text, uuid, text, text, boolean, text) to authenticated;

-- supabase/manager-mode.sql
-- the unlock this device holds right now, with the unlocking person's current role
create or replace function public._unlock_staff(out staff_id uuid, out staff_name text, out staff_role text,
                                                out expires_at timestamptz, out can_see_sales boolean)
language sql stable security definer set search_path = public, extensions as $$
  select s.id, s.name, s.role, u.expires_at, s.can_see_sales
    from public.access_unlocks u join public.staff s on s.id = u.staff_id
   where u.token_hash = public._unlock_token_hash() and u.user_id = auth.uid() and u.expires_at > now()
     and s.active and s.role in ('manager', 'owner')
   limit 1;
$$;

create or replace function public.access_unlock(p_staff_id uuid, p_pin text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v record; s public.staff; tok text; until timestamptz;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  select * into v from public._verify_pin(p_staff_id, p_pin, true);
  if v.err is not null then return jsonb_build_object('ok', false, 'error', v.err); end if;
  select * into s from public.staff where id = v.sid;
  delete from public.access_unlocks where expires_at < now() - interval '1 day';
  delete from public.access_unlocks where token_hash = public._unlock_token_hash();
  tok := encode(gen_random_bytes(24), 'hex');
  until := now() + interval '15 minutes';
  insert into public.access_unlocks (token_hash, user_id, staff_id, staff_name, staff_role, expires_at)
    values (encode(digest(tok, 'sha256'), 'hex'), auth.uid(), s.id, s.name, s.role, until);
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('access_open', s.id, s.name, auth.uid()::text, 'opened the owner areas',
            jsonb_build_object('role', s.role, 'until', until, 'account', public.account_kind()));
  return jsonb_build_object('ok', true, 'token', tok, 'until', until, 'name', s.name, 'role', s.role,
                            'sales', s.role = 'owner' or s.can_see_sales);
end $$;

create or replace function public.access_lock()
returns void language sql security definer set search_path = public, extensions as $$
  delete from public.access_unlocks where token_hash = public._unlock_token_hash() and user_id = auth.uid();
$$;
revoke all on function public.access_unlock(uuid, text), public.access_lock() from public, anon;
grant execute on function public.access_unlock(uuid, text), public.access_lock() to authenticated;

create or replace function public._unlocked_any_device()
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from public.access_unlocks u join public.staff s on s.id = u.staff_id
                  where u.user_id = auth.uid() and u.expires_at > now() and s.active and s.role in ('manager', 'owner'));
$$;
revoke all on function public._unlocked_any_device() from public, anon;
grant execute on function public._unlocked_any_device() to authenticated;

drop function if exists public._jwt_session();

delete from canopy.migrations where version = 33;
notify pgrst, 'reload schema';
select 'listo: la 0033 se revirtió; las funciones de PIN y de aperturas vuelven a ser las de antes' as resultado;
