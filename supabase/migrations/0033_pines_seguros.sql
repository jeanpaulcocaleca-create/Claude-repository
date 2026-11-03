-- =====================================================================================================
-- Canopy OS · migración 0033 · PIN más seguros: sin averiguarlos, bloqueos anotados, aperturas atadas a su sesión
-- Pegar TODO en Supabase → SQL Editor → New query → Run. Requiere: 0032. Una sola transacción.
--
-- Qué hace (revisión de seguridad del 2026-10-24, D-053)
--   * Nadie puede averiguar los PIN del equipo con el editor del equipo. Hasta ahora, con las áreas de dueño abiertas,
--     manager_save_staff contestaba «ese PIN ya lo usa alguien» antes de cualquier otra negativa, sin contar nada:
--     un script podía probar todos los PIN en minutos. Ahora esa respuesta llega solo después de todas las demás
--     comprobaciones, cada «ya lo usa alguien» queda en el registro, y cada cuenta (la del café, la del dueño) puede
--     poner o probar como mucho 10 PIN por hora, aunque mande muchos a la vez: todas las tabletas de una cuenta juntas,
--     y los PIN puestos con éxito también cuentan (dicen que ese PIN estaba libre).
--   * Volver a activar a alguien pide un PIN nuevo: mientras no estaba, su PIN pudo pasar a otra persona, y dos personas
--     activas nunca comparten PIN (antes se reactivaba con el PIN viejo sin comprobarlo).
--   * Bloqueos por PIN equivocados (5 intentos → 10 minutos, igual que antes):
--       - un PIN vacío ya no cuenta como intento (una casilla vacía, o borrada por la página, no bloquea a nadie);
--       - al terminar un bloqueo, un intento equivocado más vuelve a bloquear (igual que antes);
--       - cada bloqueo queda en el registro: a quién y desde qué cuenta (café o dueño);
--       - otro encargado, con su propio PIN, puede quitar el bloqueo de un miembro del equipo o de otro encargado
--         (como mucho 2 veces al día por persona); el bloqueo de un dueño solo lo quita el dueño con el código del
--         teléfono. Queda en el registro.
--   * Cada apertura de las áreas de dueño queda atada a la sesión (el inicio de sesión del aparato) que la hizo:
--       - otro aparato de la misma cuenta ya no puede usarla para nada, tampoco para cambiar las fotos del menú;
--       - «Bloquear» y cerrar la sesión la terminan también en el servidor (las páginas nuevas avisan al servidor antes
--         de cerrar la sesión; «Cerrar sesión en todas partes» termina todas las de esa cuenta).
-- Qué cambia para el personal: nada al escribir su PIN. En «Equipo» aparece «Quitar bloqueo del PIN» (páginas nuevas).
-- Qué NO cambia: los PIN, quién puede abrir qué, los 15 minutos, los 5 intentos y los 10 minutos de bloqueo, la caja sin
--   internet. Ningún registro existente se cambia: solo se agrega una columna (session_id en access_unlocks).
-- Qué ve una página anterior: lo mismo que hoy. Si una persona prueba más de 10 PIN en una hora en el editor del equipo,
--   la página anterior muestra «No se pudo guardar»; al reactivar a alguien sin PIN nuevo, «Una persona nueva necesita
--   un PIN». Su bitácora de aprobaciones muestra las anotaciones nuevas con su código (pin_locked, pin_in_use,
--   pin_lock_cleared) y «approved by» con la persona bloqueada o quien probó el PIN: no es una aprobación; la explicación
--   va en la línea de abajo. Las páginas nuevas las muestran con su nombre. Una apertura hecha antes de aplicar esta migración sigue sirviendo
--   en su aparato, pero para cambiar una foto del menú hay que volver a escribir el PIN (como mucho 15 minutos).
-- Cuándo: fuera del horario de atención, antes o después de publicar las páginas nuevas (funcionan con y sin ella).
-- Después de aplicarla: en una tableta, abrir las áreas de dueño con un PIN y cambiar una foto del menú. Si la foto se
--   cambia, la atadura a la sesión funciona en Supabase; si no, avisar (las demás funciones siguen bien).
-- Reversión: supabase/tools/reversion-0033.sql (vuelve a las funciones de antes; la columna nueva queda, sin uso).
--   Revertir las recetas (0030–0032) obliga a revertir antes esta, y con eso vuelven los problemas que corrige.
-- =====================================================================================================
select canopy.migration_begin(33, 'pines_seguros');

-- 1) la sesión que abrió cada apertura ------------------------------------------------------------------------------
-- Supabase pone en cada token el identificador de la sesión (session_id): el mismo en las consultas a la base y a las
-- fotos (Storage) de ese aparato, distinto en cualquier otro aparato o al volver a iniciar sesión.
alter table public.access_unlocks add column if not exists session_id text;

create or replace function public._jwt_session()
returns text language sql stable set search_path = public as $$
  select nullif(coalesce(auth.jwt() ->> 'session_id', ''), '');
$$;
revoke all on function public._jwt_session() from public, anon, authenticated;

-- 2) los intentos de PIN: un PIN vacío no cuenta y cada bloqueo queda en el registro ------------------------------
create or replace function public._verify_pin(p_staff_id uuid, p_pin text, p_need_manager boolean,
                                              out err text, out sid uuid, out sname text)
language plpgsql security definer set search_path = public, extensions as $$
declare s public.staff; tries int;
begin
  select * into s from public.staff where id = p_staff_id for update;   -- tries sent at the same moment are counted one by one
  if s.id is null then err := 'unknown_staff'; return; end if;
  if not s.active then err := 'inactive'; return; end if;
  if p_need_manager and s.role not in ('manager', 'owner') then err := 'not_manager'; return; end if;
  if s.locked_until is not null and s.locked_until > now() then err := 'locked'; return; end if;
  if s.pin_hash is null or crypt(coalesce(p_pin, ''), s.pin_hash) <> s.pin_hash then
    -- an empty PIN is not a try: an empty or wiped box never counts toward a lock
    if coalesce(trim(p_pin), '') = '' then err := 'bad_pin'; return; end if;
    -- as before 0033: 5 wrong tries lock for 10 minutes, and once a lock has ended one more wrong try locks again
    -- (2 tries there would double how fast a PIN can be guessed); a manager can now take a lock off (pin_lock_clear)
    tries := s.failed_pins + 1;
    update public.staff
      set failed_pins = tries,
          locked_until = case when tries >= 5 then now() + interval '10 minutes' else locked_until end
      where id = s.id;
    if tries >= 5 then
      insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
        values ('pin_locked', s.id, s.name, auth.uid()::text,
                case when s.locked_until is not null then 'PIN locked again for 10 minutes: a wrong try after the last lock ended'
                     else 'PIN locked for 10 minutes after 5 wrong tries' end,
                jsonb_build_object('staff_name', s.name, 'role', s.role, 'until', now() + interval '10 minutes',
                                   'tries', tries, 'relock', s.locked_until is not null,
                                   'by_login', auth.uid(), 'account', public.account_kind()));
    end if;
    err := 'bad_pin'; return;
  end if;
  update public.staff set failed_pins = 0, locked_until = null where id = s.id;
  sid := s.id; sname := s.name; err := null;
end $$;
revoke all on function public._verify_pin(uuid, text, boolean) from public, anon, authenticated;

-- 3) el editor del equipo: si un PIN está libre se sabe solo al final, como mucho 10 veces por hora y por cuenta ------
create or replace function public.manager_save_staff(p_manager_id uuid, p_manager_pin text,
    p_id uuid, p_name text, p_pin text, p_active boolean, p_role text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v record; u record; lvl text; bootstrap boolean; nid uuid; role_final text; new_pin boolean; tries int;
        old public.staff; managers_left int; msid uuid; msname text; strip_sales boolean;
begin
  -- one PIN save at a time (0033): requests sent together would otherwise all read the same hourly count, and two saves
  -- at the same moment could give one free PIN to two people. Taken first, before any row lock, so it cannot deadlock
  if coalesce(p_pin, '') <> '' then perform pg_advisory_xact_lock(hashtextextended('canopy.staff_pin', 0)); end if;
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
  new_pin := p_pin is not null and p_pin <> '';
  if new_pin then
    if p_pin !~ '^[0-9]{4,8}$' then return jsonb_build_object('ok', false, 'error', 'bad_pin_format'); end if;
    if public._weak_pin(p_pin) then return jsonb_build_object('ok', false, 'error', 'weak_pin'); end if;
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
     and (new_pin or role_final <> old.role or coalesce(p_active, old.active) <> old.active) then
    if exists (select 1 from public.staff where active and role = 'owner') then return jsonb_build_object('ok', false, 'error', 'manager_needs_owner'); end if;
    strip_sales := new_pin;
  end if;
  if p_id is null and not new_pin then return jsonb_build_object('ok', false, 'error', 'missing_pin'); end if;
  -- bringing someone back needs a new PIN: while they were away their old one may have gone to someone else, and two
  -- active people never share a PIN (0033; before, a person brought back kept the old one unchecked)
  if old.id is not null and not old.active and coalesce(p_active, old.active) and not new_pin then
    return jsonb_build_object('ok', false, 'error', 'missing_pin');
  end if;
  if old.id is not null and old.role in ('manager', 'owner') and old.active and (role_final = 'staff' or not coalesce(p_active, true)) then
    select count(*) into managers_left from public.staff
      where active and role in ('manager', 'owner') and id <> old.id;
    if managers_left = 0 then return jsonb_build_object('ok', false, 'error', 'last_manager'); end if;
  end if;
  -- the PIN itself, last (0033): whether a PIN is free tells something, so it is asked only once every other check
  -- passed, at most 10 PINs an hour per login, and every "already in use" answer is written to the log
  if new_pin then
    select count(*) into tries from public.audit_log
      where at > now() - interval '1 hour' and details ->> 'by_login' = auth.uid()::text
        and (action = 'pin_in_use' or (action = 'staff_save' and details ->> 'pin_changed' = 'true'));
    if tries >= 10 then return jsonb_build_object('ok', false, 'error', 'pin_tries'); end if;
    -- two people never share a PIN: the clock and the till could not tell them apart
    if exists (select 1 from public.staff s where s.active and s.id is distinct from p_id and s.pin_hash = crypt(p_pin, s.pin_hash)) then
      insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
        values ('pin_in_use', msid, msname, coalesce(p_id::text, ''), 'tried a PIN that someone else already uses',
                jsonb_build_object('staff_name', coalesce(old.name, trim(p_name)), 'by_login', auth.uid(), 'account', public.account_kind()));
      return jsonb_build_object('ok', false, 'error', 'pin_in_use');
    end if;
  end if;

  if p_id is null then
    insert into public.staff (name, pin_hash, active, role)
      values (trim(p_name), crypt(p_pin, gen_salt('bf')), coalesce(p_active, true), role_final)
      returning id into nid;
  else
    update public.staff set
      name = trim(p_name),
      pin_hash = case when new_pin then crypt(p_pin, gen_salt('bf')) else pin_hash end,
      failed_pins = case when new_pin then 0 else failed_pins end,
      locked_until = case when new_pin then null else locked_until end,
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
                         'pin_changed', new_pin, 'first_setup', bootstrap, 'by_login', auth.uid()));
  return jsonb_build_object('ok', true, 'id', nid, 'role', role_final, 'first_setup', bootstrap);
end $$;
revoke all on function public.manager_save_staff(uuid, text, uuid, text, text, boolean, text) from public, anon;
grant execute on function public.manager_save_staff(uuid, text, uuid, text, text, boolean, text) to authenticated;

-- 4) quitar un bloqueo de PIN: otro encargado con su PIN (2 veces al día por persona), o el dueño con el código ------
create or replace function public.pin_lock_clear(p_staff_id uuid, p_manager_id uuid default null, p_manager_pin text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare s public.staff; v record; code boolean; n int; by_id uuid; by_name text;
begin
  if public.access_level() is null then return jsonb_build_object('ok', false, 'error', 'owner_only'); end if;
  code := public.owner_with_code();
  select * into s from public.staff where id = p_staff_id;
  if s.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if s.locked_until is null or s.locked_until <= now() then return jsonb_build_object('ok', false, 'error', 'not_locked'); end if;
  if code then
    by_id := null; by_name := public._owner_label();
  else
    -- an owner's PIN is the strongest one on the tablet: only the owner, from their own login with the code
    if s.role = 'owner' then return jsonb_build_object('ok', false, 'error', 'owner_lock_needs_code'); end if;
    if p_manager_id is null or coalesce(trim(p_manager_pin), '') = '' then return jsonb_build_object('ok', false, 'error', 'unknown_staff'); end if;
    if p_manager_id = p_staff_id then return jsonb_build_object('ok', false, 'error', 'not_self'); end if;
    -- each unlock gives 5 more tries at that person's PIN: at most 2 a day without the owner's code
    select count(*) into n from public.audit_log
      where action = 'pin_lock_cleared' and target_id = p_staff_id::text and at > now() - interval '1 day';
    if n >= 2 then return jsonb_build_object('ok', false, 'error', 'clear_limit'); end if;
    select * into v from public._verify_pin(p_manager_id, p_manager_pin, true);
    if v.err is not null then return jsonb_build_object('ok', false, 'error', v.err); end if;
    by_id := v.sid; by_name := v.sname;
  end if;
  -- the approver's row was locked first (by _verify_pin), the person's now: the order manager_save_staff uses, so the
  -- two never wait for each other in a circle; and a lock removed meanwhile on another tablet is not removed twice
  select * into s from public.staff where id = p_staff_id for update;
  if s.locked_until is null or s.locked_until <= now() then return jsonb_build_object('ok', false, 'error', 'not_locked'); end if;
  update public.staff set failed_pins = 0, locked_until = null where id = s.id;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('pin_lock_cleared', by_id, by_name, s.id::text, 'removed the PIN lock of ' || s.name,
            jsonb_build_object('staff_name', s.name, 'by_login', auth.uid(), 'account', public.account_kind()));
  return jsonb_build_object('ok', true, 'name', s.name);
end $$;
revoke all on function public.pin_lock_clear(uuid, uuid, text) from public, anon;
grant execute on function public.pin_lock_clear(uuid, uuid, text) to authenticated;

-- 5) cada apertura, atada a la sesión que la hizo --------------------------------------------------------------------
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
  insert into public.access_unlocks (token_hash, user_id, staff_id, staff_name, staff_role, expires_at, session_id)
    values (encode(digest(tok, 'sha256'), 'hex'), auth.uid(), s.id, s.name, s.role, until, public._jwt_session());
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('access_open', s.id, s.name, auth.uid()::text, 'opened the owner areas',
            jsonb_build_object('role', s.role, 'until', until, 'account', public.account_kind(),
                               'session_bound', public._jwt_session() is not null));
  return jsonb_build_object('ok', true, 'token', tok, 'until', until, 'name', s.name, 'role', s.role,
                            'sales', s.role = 'owner' or s.can_see_sales);
end $$;

-- the unlock this device holds right now: its token, its login and (0033) the same sign-in that made it
create or replace function public._unlock_staff(out staff_id uuid, out staff_name text, out staff_role text,
                                                out expires_at timestamptz, out can_see_sales boolean)
language sql stable security definer set search_path = public, extensions as $$
  select s.id, s.name, s.role, u.expires_at, s.can_see_sales
    from public.access_unlocks u join public.staff s on s.id = u.staff_id
   where u.token_hash = public._unlock_token_hash() and u.user_id = auth.uid() and u.expires_at > now()
     and (u.session_id is null or u.session_id = public._jwt_session())
     and s.active and s.role in ('manager', 'owner')
   limit 1;
$$;

-- «Bloquear» and signing out: this device's token, and (0033) every unlock of this sign-in, even without its token
create or replace function public.access_lock()
returns void language sql security definer set search_path = public, extensions as $$
  delete from public.access_unlocks
   where user_id = auth.uid()
     and (token_hash = public._unlock_token_hash() or (session_id is not null and session_id = public._jwt_session()));
$$;

-- «Cerrar sesión en todas partes»: every unlock of this login, on every device
create or replace function public.access_lock_all()
returns void language sql security definer set search_path = public, extensions as $$
  delete from public.access_unlocks where user_id = auth.uid();
$$;
revoke all on function public.access_unlock(uuid, text), public.access_lock(), public.access_lock_all() from public, anon;
grant execute on function public.access_unlock(uuid, text), public.access_lock(), public.access_lock_all() to authenticated;
revoke all on function public._unlock_staff() from public, anon, authenticated;

-- 6) fotos del menú: Storage no recibe el comprobante del aparato, pero sí su sesión. Antes bastaba una apertura en
--    CUALQUIER aparato de la cuenta; ahora solo la del mismo inicio de sesión (el nombre se mantiene: lo usa la regla
--    «menu photos owner write»). Una apertura sin sesión (de antes de la 0033) no sirve para las fotos.
create or replace function public._unlocked_any_device()
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from public.access_unlocks u join public.staff s on s.id = u.staff_id
                  where u.user_id = auth.uid() and u.expires_at > now() and s.active and s.role in ('manager', 'owner')
                    and u.session_id is not null and u.session_id = public._jwt_session());
$$;
revoke all on function public._unlocked_any_device() from public, anon;
grant execute on function public._unlocked_any_device() to authenticated;

select canopy.migration_end(33, 'pines_seguros');
notify pgrst, 'reload schema';
