-- =====================================================================================================
-- Canopy OS · migración 0038 · Descuentos de Caja: cuatro categorías con código, cajas registradas para
-- descuentos y el interruptor de la ventana de descuento anterior
-- Pegar TODO en Supabase → SQL Editor → New query → Run. Requiere: 0037. Una sola transacción.
--
-- Qué hace (D-065; propuesta aprobada por el dueño el 2026-11-03 con sus cinco ajustes)
--   * Cuatro descuentos con la tasa fijada por el servidor (la página nunca manda un porcentaje): Empleado 30 %,
--     Local 10 %, Huésped 10 % y Guía Turista 100 % (cortesía). Cada uno queda en discount_approvals con su categoría,
--     el empleado que lo recibe o la empresa del guía, el día de Costa Rica, quién lo autorizó y con qué papel. Una
--     regla de la tabla hace imposible guardar otra tasa, otro monto, un autodescuento o una Guía sin el dueño.
--   * Se autoriza solo con el código (sin lista de nombres): el de un encargado o del dueño; para Empleado también el
--     código del empleado, los dos en una sola llamada (descuento_autorizar). Un encargado nunca se autoriza a sí mismo.
--     Guía Turista solo con el código del dueño (ajuste 1 del dueño: ese código NO abre las áreas del dueño, no crea
--     ninguna apertura y no toca el contador de PIN de nadie).
--   * Guía Turista nace APAGADA (ajuste 4): el ajuste pos_discount_guia queda en «off» hasta que el contador confirme el
--     IVA de las cortesías (A-13) y el dueño lo registre (compliance_confirm 'courtesy_iva_confirmed') y lo encienda
--     con el código del teléfono. Mientras está apagada, el servidor rechaza Guía antes de probar cualquier código.
--   * Un descuento de Empleado por empleado y por día. El cupo se devuelve solo con una anulación válida (un encargado
--     que no es el beneficiado, sin partes pagadas) o con «Devolver el cupo del día» (descuento_cupo_devolver: el PIN
--     propio de un encargado, nunca el beneficiado, o el dueño con el código del teléfono; queda anotado). Una
--     autorización sin usar vence a los 30 minutos o la suelta la página (ajuste 3).
--   * Siempre el pedido entero y nunca dos descuentos. En una cuenta abierta, solo antes de cualquier pago; quitarlo
--     después de un pago necesita el PIN de un encargado (descuento_quitar_cuenta).
--   * Control de códigos equivocados sin pausa para todo el café (ajuste 2, «cajas registradas en puestos»): solo una
--     caja que un encargado registró en ese mismo aparato (Reloj de marcas → Bitácora de aprobaciones) prueba códigos.
--     Hay 3 puestos y cada uno lleva su propia cuenta: los 2 primeros errores en una hora no cuestan nada; el 3.º hace
--     esperar 30 segundos a esa caja, el 4.º 1 minuto, el 5.º 5 minutos, desde el 6.º 10 minutos; 12 errores en 24
--     horas detienen esa caja (las demás siguen). Un encargado la reanuda con su PIN (una vez por puesto y dos por café
--     en 24 horas). El aparato registrado guarda una llave: al volver a iniciar sesión regresa solo a su puesto.
--     Nunca se escribe un PIN, un código ni una llave en la base: solo la huella sha256 de la llave.
--   * La ventana de descuento anterior (approve_discount) queda detrás del ajuste pos_free_discount, ENCENDIDO por
--     omisión: las cajas que todavía no se recargaron y las ventas guardadas sin internet funcionan como hoy. El dueño
--     lo apaga al final de la activación (no es parte de esta migración). Con el ajuste encendido o apagado, ese motivo
--     libre ya no puede decir lo mismo que una categoría (por ejemplo «Otro · Local»): contesta «Elija el motivo».
--   * Las ventas con un descuento de categoría nunca se rechazan por él: si algo no cuadra, la venta queda con lo que se
--     cobró y una marca para el gerente (discount_not_verified, discount_late, discount_daily_twice).
--   * Un informe (descuentos_informe) por categoría, empleado, autorizador y empresa, con lo cobrado y los productos;
--     también lo lee el contador.
-- Qué NO cambia: ningún registro existente (las aprobaciones viejas quedan con categoría vacía), los impuestos, las
--   tarifas, la contabilidad, ninguna otra función. Ninguna regla fiscal se activa.
-- Qué cambia para el personal: nada hasta que se publiquen las páginas nuevas. Con la página anterior, un motivo libre
--   que diga una categoría («Otro · Local», «Empleado»…) contesta «Elija el motivo del descuento»; y un descuento de
--   categoría en una cuenta con un pago ya hecho no se quita con la × anterior.
-- Cuándo: fuera del horario de atención, después de la 0037. No bloquea ventas.
-- Reversión: supabase/tools/reversion-0038.sql (vuelve approve_discount, tab_set_discount y _order_discount_check a su
--   texto anterior y quita las funciones nuevas; las columnas, la tabla de cajas, los índices y los ajustes quedan).
-- =====================================================================================================
select canopy.migration_begin(38, 'descuentos_caja');
set local lock_timeout = '8s';

-- Lock order (api-0038 §9): A canopy.discount_request:<id> (descuento_autorizar, descuento_liberar) → B
-- canopy.discount_tills, café-wide (registrar, volver, quitar, reanudar, the owner's tools; NEVER descuento_autorizar) →
-- C canopy.discount_slot:<1..3> (descuento_autorizar on its own place after the lock-free checks 6a-6c; the functions
-- above for the place they change; the tools in slot order) → 1 ONE staff row (the window: the authorizer only, the
-- employee read without a lock and no foreign key to it; resume, remove, give-back, take-off: the picked person) → 2
-- the order or bill → 3 the per-employee lock E (canopy.discount_employee:<staff id>) → 4 approval rows → 5 stock rows
-- (a sale takes E before its lines move stock; a void or a cancel takes E in order_zz_discount_lock, before
-- order_stock_return). A discount_tills row is written only under its place's C, or B for an insert into a free place;
-- no path takes B or C after a staff row; descuento_estado, descuento_cajas and 6a-6c take no lock. Free-text arguments
-- are cut to a fixed length before any work. Not ruled out: tab_remove_item (0031) takes the bill before the PIN's
-- staff row, so it can deadlock with a discount on the same bill and the same manager's PIN; PostgreSQL ends one call
-- (40P01), it rolls back whole and is retried (concurrency-descuentos.sh 4). Lock errors in the day's update triggers
-- are raised again (the void or cancel is retried); the sale's insert check never refuses money taken.

-- 1) settings (0008's mechanism) ---
insert into canopy.setting_defs (key, kind, choices, default_value, guard, description) values
  ('pos_free_discount', 'choice', '{on,off}', '"on"', null,
   'Ventana de descuento libre de la Caja anterior (porcentaje o monto con el PIN de un encargado). on = sigue '
   'funcionando para las cajas que todavía no se recargaron, como hoy; off = solo los cuatro descuentos nuevos. '
   'Se apaga al final de la activación (docs/ACTIVACION-DESCUENTOS.md §4).'),
  ('pos_discount_guia', 'choice', '{off,on}', '"off"', 'courtesy_iva_confirmed',
   'Cortesía Guía Turista 100 %: apagada hasta que el contador confirme el tratamiento del IVA (A-13) y el dueño lo '
   'registre con compliance_confirm(''courtesy_iva_confirmed'', …); luego el dueño la enciende con el código del teléfono.')
on conflict (key) do update set kind = excluded.kind, choices = excluded.choices, default_value = excluded.default_value,
                                guard = excluded.guard, description = excluded.description;

-- 2) discount_approvals: what a category approval records (nullable; old rows keep null = before 0038) ---
alter table public.discount_approvals
  add column if not exists category         text,
  add column if not exists beneficiary_id   uuid,
  add column if not exists beneficiary_name text,
  add column if not exists company          text,
  add column if not exists cr_day           date,
  add column if not exists approver_role    text,
  add column if not exists bill_id          uuid,
  add column if not exists login_id         uuid,
  add column if not exists session_id       text,
  add column if not exists request_id       uuid,
  add column if not exists freed_at         timestamptz,
  add column if not exists freed_how        text;
-- beneficiary_id has NO foreign key to staff: its check would lock the employee's row while the authorizer's is held,
-- a deadlock against 0033's pin_lock_clear (the window locks ONE staff row). Dropped here too for a re-run
alter table public.discount_approvals drop constraint if exists discount_approvals_beneficiary_id_fkey;
alter table public.discount_approvals drop constraint if exists discount_approvals_category_check;
alter table public.discount_approvals add constraint discount_approvals_category_check
  check (category is null or category in ('empleado', 'local', 'huesped', 'guia'));
alter table public.discount_approvals drop constraint if exists discount_approvals_approver_role_check;
alter table public.discount_approvals add constraint discount_approvals_approver_role_check
  check (approver_role is null or approver_role in ('manager', 'owner'));
alter table public.discount_approvals drop constraint if exists discount_approvals_freed_how_check;
alter table public.discount_approvals add constraint discount_approvals_freed_how_check
  check (freed_how is null or freed_how in ('released', 'expired', 'void', 'bill_removed', 'bill_cancelled'));
-- the rate is the category's and the amount is that rate of the list value; nobody authorizes their own Empleado; only
-- the owner gives Guía, always with a company (written inline: restoring a copy never depends on a function)
alter table public.discount_approvals drop constraint if exists discount_approvals_categoria;
alter table public.discount_approvals add constraint discount_approvals_categoria check (category is null or (
  kind = 'percent'
  and value = case category when 'empleado' then 30 when 'guia' then 100 else 10 end
  and subtotal_crc is not null and amount_crc is not null
  and subtotal_crc > 0 and amount_crc = round(subtotal_crc * value / 100.0)::int
  and cr_day is not null and approver_role is not null
  and (category = 'empleado' or (beneficiary_id is null and beneficiary_name is null))
  and (category <> 'empleado' or (beneficiary_name is not null
       and (beneficiary_id is null or approved_by is null or beneficiary_id <> approved_by)))
  and (category = 'guia') = (company is not null)
  and (category <> 'guia' or (approver_role = 'owner' and char_length(company) between 2 and 80))));
-- one Empleado per employee per Costa Rica day, in the database itself (any number of devices)
create unique index if not exists discount_employee_once on public.discount_approvals (beneficiary_id, cr_day)
  where category = 'empleado' and freed_at is null;
create unique index if not exists discount_approvals_request on public.discount_approvals (request_id) where request_id is not null;
create index if not exists discount_approvals_day on public.discount_approvals (cr_day) where category is not null;

-- 3) the registered tills (security state, not a business record: rows are never deleted) ---
create table if not exists public.discount_tills (
  id               uuid primary key default gen_random_uuid(),
  slot             smallint not null check (slot between 1 and 3),
  session_id       text not null check (char_length(session_id) between 1 and 64),   -- _jwt_session() of the sign-in
  login_id         uuid not null,                                                     -- auth.uid()
  station          text check (station is null or char_length(station) <= 24),        -- page-reported, display only
  enrolled_at      timestamptz not null default now(),
  enrolled_by      uuid references public.staff(id) on delete set null,
  enrolled_by_name text not null,
  last_used_at     timestamptz,                                                       -- every tested call
  key_hash         text check (key_hash is null or key_hash ~ '^[0-9a-f]{64}$'),     -- sha256 of the device key; null = spent
  rebound_from     uuid references public.discount_tills(id),                         -- the row a rebind by key replaced
  prev_key_hash    text check (prev_key_hash is null or prev_key_hash ~ '^[0-9a-f]{64}$'),  -- the key that rebound it
  ended_at         timestamptz,
  ended_by         uuid references public.staff(id) on delete set null,
  ended_by_name    text,
  ended_how        text check (ended_how in ('manager', 'owner', 'replaced', 'signed_out', 'rebound', 'sql_editor')),
  constraint discount_tills_ended check ((ended_at is null) = (ended_how is null))
);
alter table public.discount_tills add column if not exists prev_key_hash text
  check (prev_key_hash is null or prev_key_hash ~ '^[0-9a-f]{64}$');
create unique index if not exists discount_tills_live_session on public.discount_tills (session_id) where ended_at is null;
create unique index if not exists discount_tills_live_slot    on public.discount_tills (slot)       where ended_at is null;
create unique index if not exists discount_tills_key          on public.discount_tills (key_hash)   where key_hash is not null;
create index        if not exists discount_tills_session      on public.discount_tills (session_id);
alter table public.discount_tills enable row level security;            -- no policies: functions only
revoke all on public.discount_tills from public, anon, authenticated;
-- who shares a code (pin_duplicate): owner-only (descuento_cajas), never in audit_log, which managers read
create table if not exists public.discount_pin_shared (audit_id bigint primary key, staff_ids uuid[] not null);
alter table public.discount_pin_shared enable row level security;
revoke all on public.discount_pin_shared from public, anon, authenticated;

alter table public.discount_approvals add column if not exists till_id uuid references public.discount_tills(id) on delete set null;

-- the counts the window reads (per place, café-wide, the approvals log)
create index if not exists audit_log_discount_slot  on public.audit_log ((details ->> 'slot'), id)
  where action in ('discount_code_wrong', 'discount_till_resumed');
create index if not exists audit_log_discount_wrong on public.audit_log (at desc) where action = 'discount_code_wrong';
create index if not exists audit_log_discount_admin on public.audit_log (at desc)
  where action in ('discount_till_resumed', 'discount_till_ended', 'discount_till_enrolled', 'discount_till_rebound',
                   'discount_till_unknown', 'discount_alert');
-- discount_removed_paid by approval (the report, once per approval; the give-back)
create index if not exists audit_log_discount_removed_paid on public.audit_log ((details ->> 'approval'), id)
  where action = 'discount_removed_paid';

-- 4) rates, labels and typed text ---
create or replace function public._discount_rate(p_category text)
returns int language sql immutable set search_path = public as $$
  select case p_category when 'empleado' then 30 when 'local' then 10 when 'huesped' then 10 when 'guia' then 100 end;
$$;
-- English source strings (lang.js shows Empleado, Local, Huésped, Guía Turista)
create or replace function public._discount_label(p_category text)
returns text language sql immutable set search_path = public as $$
  select case p_category when 'empleado' then 'Employee' when 'local' then 'Local' when 'huesped' then 'Hotel guest'
                         when 'guia' then 'Tour guide' end;
$$;
-- typed text, cleaned: every blank (those JavaScript's \s matches) becomes one space; control, soft-hyphen, zero-width
-- and bidi format characters go; NFKC; runs of spaces collapse; the ends are trimmed. Written with \uXXXX escapes (lint 14)
create or replace function public._discount_clean(p_raw text)
returns text language sql immutable set search_path = public as $$
  select btrim(regexp_replace(regexp_replace(
           normalize(regexp_replace(regexp_replace(p_raw,
             '[[:space:]\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]', ' ', 'g'),
             '[[:cntrl:]\u00ad\u200b-\u200f\u202a-\u202e\u2060-\u2064\u2066-\u2069\ufeff]', '', 'g'), NFKC),
           '[[:cntrl:]\u00ad\u200b-\u200f\u202a-\u202e\u2060-\u2064\u2066-\u2069\ufeff]', '', 'g'),
         '[[:space:]\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]+', ' ', 'g'), ' ');
$$;
-- the guide's company: cleaned, 2 to 80 characters, at least one letter or digit; stored as typed after cleaning
create or replace function public._discount_company(p_raw text)
returns text language plpgsql immutable set search_path = public as $$
declare c text := public._discount_clean(p_raw);
begin
  if c is null or char_length(c) not between 2 and 80
     or not (c ~ '[0-9A-Za-z\u00aa\u00b5\u00ba\u00c0-\u00d6\u00d8-\u00f6\u00f8-\u024f]' or c ~ '[[:alnum:]]') then
    return null;
  end if;
  return c;
end $$;
-- would this free reason read as one of the four categories in Orders or Sales? lang.js tr() collapses blanks and
-- translates each « · » part on its own, so every part is checked, cleaned, without case or accents
create or replace function public._discount_reserved(p_reason text)
returns boolean language sql immutable set search_path = public as $$
  select coalesce(bool_or(btrim(regexp_replace(btrim(seg), '(:|\u2026|\.\.\.)$', '')) = any (array[
           'employee', 'local', 'hotel guest', 'tour guide',
           'employee discount', 'local discount', 'hotel guest discount', 'tour guide courtesy',
           'empleado', 'huesped', 'guia turista', 'descuento empleado', 'descuento local', 'descuento huesped',
           'cortesia guia turista'])), false)
    from regexp_split_to_table(translate(lower(coalesce(public._discount_clean(p_reason), '')),
                                         'áéíóúüÁÉÍÓÚÜ', 'aeiouuaeiouu'), '\u00b7') seg;
$$;
revoke all on function public._discount_rate(text), public._discount_label(text), public._discount_clean(text),
  public._discount_company(text), public._discount_reserved(text) from public, anon, authenticated;

-- 5) codes: who typed them ---
-- ONE bcrypt pass over every active PIN, the same work for every answer. n = matches; sid..locked only for one; ids = all
drop function if exists public._staff_by_code(text);
create or replace function public._staff_by_code(p_pin text, out n int, out sid uuid, out sname text, out srole text,
                                                 out locked boolean, out ids uuid[])
language plpgsql stable security definer set search_path = public, extensions as $$
declare names text[]; roles text[]; locks boolean[];
begin
  n := 0; locked := false; ids := '{}';
  if coalesce(trim(p_pin), '') = '' then return; end if;
  select count(*)::int, coalesce(array_agg(s.id order by s.id), '{}'), array_agg(s.name order by s.id),
         array_agg(s.role order by s.id), array_agg(coalesce(s.locked_until > now(), false) order by s.id)
    into n, ids, names, roles, locks
    from public.staff s where s.active and s.pin_hash is not null and s.pin_hash = crypt(p_pin, s.pin_hash);
  if n = 1 then sid := ids[1]; sname := names[1]; srole := roles[1]; locked := locks[1]; end if;
end $$;
revoke all on function public._staff_by_code(text) from public, anon, authenticated;

-- 6) the registered tills: constants and helpers (mecanismo §3, §5.1) ---
-- changing a constant needs a migration
drop function if exists public._discount_till_limits();
create or replace function public._discount_till_limits(
    out slots int, out hour_win interval, out wait3 interval, out wait4 interval, out wait5 interval, out wait6 interval,
    out day_max int, out day_win interval, out resume_slot int, out resume_cafe int, out places_person int,
    out ends_person int, out enrolls_person int, out rebind_h int, out alert_n int, out unknown_cafe_h int)
language sql immutable set search_path = public as $$
  select 3, interval '60 minutes', interval '30 seconds', interval '1 minute', interval '5 minutes', interval '10 minutes',
         12, interval '24 hours', 1, 2, 2, 3, 6, 6, 10, 20;
$$;
-- this sign-in's id (the JWT session_id, kept across refreshes); null without one: never a shared bucket
create or replace function public._discount_session() returns text
language sql stable set search_path = public as $$ select left(public._jwt_session(), 64) $$;
-- the only form of a sign-in id that ever reaches audit_log
create or replace function public._discount_tag(p_session text) returns text
language sql immutable set search_path = public as $$
  select 's' || left(encode(extensions.digest(coalesce(p_session, ''), 'sha256'), 'hex'), 7)
$$;
-- a page-reported station: at most 64 characters cleaned
create or replace function public._discount_station(p_raw text) returns text
language sql immutable set search_path = public as $$ select nullif(btrim(left(public._discount_clean(left(p_raw, 64)), 24)), '') $$;
create or replace function public._discount_key_hash(p_key text) returns text
language sql immutable set search_path = public as $$ select encode(extensions.digest(p_key, 'sha256'), 'hex') $$;
-- a new device key: 32 random bytes as hex (returned once, to that device) and its sha256 (the only thing stored)
create or replace function public._discount_new_key(out key text, out hash text)
language plpgsql volatile set search_path = public as $$
begin
  key := encode(extensions.gen_random_bytes(32), 'hex');
  hash := public._discount_key_hash(key);
end $$;
-- this sign-in's live registration (none when the token carries no session_id)
create or replace function public._discount_till_mine() returns public.discount_tills
language sql stable security definer set search_path = public as $$
  select t.* from public.discount_tills t
   where t.session_id = public._discount_session() and t.login_id = auth.uid() and t.ended_at is null
   limit 1;
$$;
-- the whole decision for one place: counts after its last resume (by audit_log.id), rolling windows, wait_s by the server
create or replace function public._discount_slot_state(p_slot int,
    out since_id bigint, out hour_n int, out day_n int, out last_at timestamptz, out state text, out until timestamptz,
    out wait text, out wait_s int, out warn text, out resumes_24h int, out vacated_at timestamptz)
language plpgsql stable security definer set search_path = public, extensions as $$
declare l record; w interval; wait_until timestamptz; stop_until timestamptz;
begin
  select * into l from public._discount_till_limits();
  select coalesce(max(a.id), 0) into since_id from public.audit_log a
   where a.action = 'discount_till_resumed' and a.details ->> 'slot' = p_slot::text;
  select count(*) filter (where a.at > now() - l.hour_win)::int, count(*)::int, max(a.at) into hour_n, day_n, last_at
    from public.audit_log a
   where a.action = 'discount_code_wrong' and a.details ->> 'slot' = p_slot::text
     and a.at > now() - l.day_win and a.id > since_id;
  w := case when hour_n >= 6 then l.wait6 when hour_n = 5 then l.wait5 when hour_n = 4 then l.wait4 when hour_n = 3 then l.wait3 end;
  wait_until := case when w is not null then last_at + w end;
  if day_n >= l.day_max then
    select a.at + l.day_win into stop_until from public.audit_log a
     where a.action = 'discount_code_wrong' and a.details ->> 'slot' = p_slot::text
       and a.at > now() - l.day_win and a.id > since_id
     order by a.at desc, a.id desc offset l.day_max - 1 limit 1;
  end if;
  state := case when stop_until > now() then 'stopped' when wait_until > now() then 'wait' else 'ok' end;
  until := case state when 'stopped' then stop_until when 'wait' then wait_until end;
  wait := case state when 'stopped' then 'stop'
                     when 'wait' then case when hour_n >= 6 then '10m' when hour_n = 5 then '5m' when hour_n = 4 then '1m' else '30s' end end;
  wait_s := case when state <> 'ok' then greatest(1, ceil(extract(epoch from until - clock_timestamp())))::int end;
  -- what the NEXT wrong code would cost once any wait is over (no warning for the 30-second one)
  warn := case when state = 'stopped' then null
               when day_n + 1 >= l.day_max then 'stop'
               when hour_n + 1 >= 6 then 'wait_10m'
               when hour_n + 1 = 5 then 'wait_5m'
               when hour_n + 1 = 4 then 'wait_1m' end;
  select count(*)::int into resumes_24h from public.audit_log a
   where a.action = 'discount_till_resumed' and a.details ->> 'slot' = p_slot::text and a.at > now() - l.day_win
     and coalesce(a.details ->> 'how', '') <> 'sql_editor';                -- the owner's SQL tool counts toward no cap
  if not exists (select 1 from public.discount_tills d where d.slot = p_slot and d.ended_at is null) then
    select max(d.ended_at) into vacated_at from public.discount_tills d where d.slot = p_slot;
  end if;
end $$;
-- the authorizer's row, locked (level 1, the window's only one); writes NOTHING (no 0033 counter); locked = accepted
create or replace function public._discount_take_staff(p_sid uuid, out ok boolean, out locked boolean)
language plpgsql security definer set search_path = public, extensions as $$
declare a boolean; lu timestamptz;
begin
  select s.active, s.locked_until into a, lu from public.staff s where s.id = p_sid for update;
  ok := coalesce(a, false);
  locked := coalesce(lu > now(), false);
end $$;
-- the same read for the employee, without a row lock and without any write
create or replace function public._discount_staff_state(p_sid uuid, out ok boolean, out locked boolean)
language plpgsql stable security definer set search_path = public, extensions as $$
declare a boolean; lu timestamptz;
begin
  select s.active, s.locked_until into a, lu from public.staff s where s.id = p_sid;
  ok := coalesce(a, false);
  locked := coalesce(lu > now(), false);
end $$;
-- a person's live places, and their endings and registrations in the last 24 hours (the per-person caps)
create or replace function public._discount_person(p_staff uuid, out places int, out ends_24h int, out enrolls_24h int)
language sql stable security definer set search_path = public as $$
  select (select count(*)::int from public.discount_tills t where t.ended_at is null and t.enrolled_by = p_staff),
         (select count(*)::int from public.audit_log a where a.action = 'discount_till_ended' and a.manager_id = p_staff
             and a.at > now() - interval '24 hours' and a.details ->> 'how' in ('manager', 'replaced')),
         (select count(*)::int from public.audit_log a where a.action = 'discount_till_enrolled' and a.manager_id = p_staff
             and a.at > now() - interval '24 hours');
$$;
-- the live places (the panel's «Reemplazar» list), mine = registered by that person
create or replace function public._discount_places(p_by uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('slot', t.slot, 'till', t.id, 'station', t.station, 'by', t.enrolled_by_name,
                                               'since', t.enrolled_at, 'last_used', t.last_used_at,
                                               'mine', coalesce(p_by is not null and t.enrolled_by = p_by, false)) order by t.slot), '[]')
    from public.discount_tills t where t.ended_at is null;
$$;
-- one counted wrong code at a registered till (called under that place's lock C). Writes the discount_code_wrong row,
-- discount_till_stopped when this code stopped the place, discount_alert when the café reaches 10 in 24 h (at most one
-- per 24 h; it pauses nothing). Returns only {warn, blocked, until, wait, wait_s}. p_station comes cleaned: nothing is
-- cleaned here, so a wrong code costs what a right one does (no timeout tells them apart or undoes the count)
create or replace function public._discount_wrong(p_till public.discount_tills, p_step text, p_why text, p_category text,
                                                  p_station text, p_auth_id uuid default null, p_auth_name text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare l record; g0 record; g1 record; cafe int; st text := nullif(btrim(left(p_station, 24)), '');
begin
  select * into l from public._discount_till_limits();
  select * into g0 from public._discount_slot_state(p_till.slot);
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('discount_code_wrong', p_auth_id, p_auth_name, p_till.id::text, 'wrong discount code (' || p_step || ')',
            jsonb_build_object('till', p_till.id, 'slot', p_till.slot, 'session_tag', public._discount_tag(p_till.session_id),
                               'station', st, 'till_station', p_till.station, 'step', p_step, 'why', p_why,
                               'category', p_category, 'authorizer', p_auth_id, 'by_login', auth.uid(),
                               'account', public.account_kind(), 'hour_n', g0.hour_n + 1, 'day_n', g0.day_n + 1));
  select * into g1 from public._discount_slot_state(p_till.slot);
  if g1.state = 'stopped' and g0.state <> 'stopped' then
    insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
      values ('discount_till_stopped', null, null, p_till.id::text, 'discounts stopped on one till: 12 wrong codes in 24 hours',
              jsonb_build_object('till', p_till.id, 'slot', p_till.slot, 'till_station', p_till.station, 'station', st,
                                 'until', g1.until, 'day_n', g1.day_n, 'by_login', auth.uid()));
  end if;
  select count(*)::int into cafe from public.audit_log a where a.action = 'discount_code_wrong' and a.at > now() - l.day_win;
  if cafe >= l.alert_n and not exists (select 1 from public.audit_log a where a.action = 'discount_alert' and a.at > now() - l.day_win) then
    insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
      values ('discount_alert', null, null, null, 'many wrong discount codes across the café in 24 hours',
              jsonb_build_object('cafe_24h', cafe, 'by_login', auth.uid()));
  end if;
  return jsonb_build_object('warn', g1.warn, 'blocked', case when g1.state <> 'ok' then g1.state end,
                            'until', g1.until, 'wait', g1.wait, 'wait_s', g1.wait_s);
end $$;
-- a code typed on a sign-in that is not a registered till: at most one row per sign-in per hour and 20 an hour
-- café-wide (checked without a lock: approximate). p_station comes cleaned
create or replace function public._discount_till_unknown(p_session text, p_station text)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare l record; tag text := public._discount_tag(p_session); st text := nullif(btrim(left(p_station, 24)), '');
begin
  select * into l from public._discount_till_limits();
  if exists (select 1 from public.audit_log a where a.action = 'discount_till_unknown' and a.at > now() - interval '1 hour'
               and a.details ->> 'session_tag' = tag) then return; end if;
  if (select count(*) from public.audit_log a where a.action = 'discount_till_unknown' and a.at > now() - interval '1 hour')
     >= l.unknown_cafe_h then return; end if;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('discount_till_unknown', null, null, null, 'a discount code was typed on a device not registered for discounts',
            jsonb_build_object('session_tag', tag, 'station', st, 'by_login', auth.uid(), 'account', public.account_kind()));
end $$;
revoke all on function public._discount_till_limits(), public._discount_session(), public._discount_tag(text),
  public._discount_station(text), public._discount_key_hash(text), public._discount_new_key(), public._discount_till_mine(),
  public._discount_slot_state(int), public._discount_take_staff(uuid), public._discount_staff_state(uuid),
  public._discount_person(uuid), public._discount_places(uuid),
  public._discount_wrong(public.discount_tills, text, text, text, text, uuid, text),
  public._discount_till_unknown(text, text) from public, anon, authenticated;

-- 7) approvals: helpers ---
-- the answer of an approval (the same for the first call and for a replay of its request id); a bill's current total
create or replace function public._discount_answer(r public.discount_approvals) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('ok', true, 'id', r.id, 'request_id', r.request_id, 'category', r.category, 'amount', r.amount_crc,
           'subtotal', r.subtotal_crc, 'reason', r.reason, 'name', r.approved_name, 'role', r.approver_role,
           'beneficiary', r.beneficiary_name, 'company', r.company, 'at', r.created_at,
           'prior', (select jsonb_build_object('how', 'void', 'by', coalesce(s.name, o.voided_by::text))
                       from public.discount_approvals x join public.orders o on o.id = x.order_id
                       left join public.staff s on s.id = o.voided_by
                      where r.category = 'empleado' and x.category = 'empleado' and x.beneficiary_id = r.beneficiary_id
                        and x.cr_day = r.cr_day and x.freed_how = 'void' and x.id <> r.id and x.created_at <= r.created_at
                      order by x.created_at desc limit 1))
      || coalesce((select jsonb_build_object('order_id', o.id, 'total', o.total_crc, 'discount', o.discount_crc)
                     from public.orders o where o.id = r.bill_id), '{}'::jsonb);
$$;
-- whether a bill can take a category discount now (before the codes without a lock, after them under it)
create or replace function public._discount_bill_problem(p_order_id uuid, p_subtotal int, p_expect int, p_lock boolean)
returns text language plpgsql security definer set search_path = public as $$
declare o public.orders; items int; paidq boolean; combo boolean;
begin
  if p_lock then select * into o from public.orders where id = p_order_id for update;
  else select * into o from public.orders where id = p_order_id; end if;
  if o.id is null or o.part_of is not null then return 'not_found'; end if;
  if o.voided_at is not null or o.status = 'cancelled' then return 'cancelled'; end if;
  if o.paid then return 'already_paid'; end if;
  select coalesce(sum(i.qty * i.price_crc), 0)::int, coalesce(bool_or(i.paid_qty > 0), false), coalesce(bool_or(i.price_crc < 0), false)
    into items, paidq, combo from public.order_items i where i.order_id = o.id;
  if coalesce(o.parts_crc, 0) > 0 or paidq then return 'has_parts'; end if;
  if combo then return 'combo_first'; end if;
  if o.discount_id is not null or coalesce(o.discount_crc, 0) > 0 or 'discount_not_verified' = any (coalesce(o.flags, '{}'))
     or coalesce(o.notes, '') ilike '%not verified%' or coalesce(o.total_crc, 0) + coalesce(o.parts_crc, 0) <> items then
    return 'already_discounted';
  end if;
  if p_expect is null or p_expect <> o.total_crc or p_subtotal is distinct from items then return 'changed'; end if;
  return null;
end $$;
-- a freed Empleado day goes to a freed approval of that day on a live sale (the discount_daily_twice case), if any
create or replace function public._discount_retake_day(p_ben uuid, p_day date) returns void
language plpgsql security definer set search_path = public as $$
declare x uuid;
begin
  if p_ben is null then return; end if;
  select a.id into x from public.discount_approvals a join public.orders o on o.id = a.order_id
   where a.category = 'empleado' and a.beneficiary_id = p_ben and a.cr_day = p_day and a.freed_at is not null
     and a.freed_how in ('released', 'expired') and o.voided_at is null and o.status <> 'cancelled'
   order by a.created_at limit 1;
  if x is null then return; end if;
  begin
    update public.discount_approvals set freed_at = null, freed_how = null where id = x;
  exception when unique_violation then null;    -- another live approval already holds the day
  end;
end $$;
revoke all on function public._discount_answer(public.discount_approvals), public._discount_bill_problem(uuid, int, int, boolean),
  public._discount_retake_day(uuid, date) from public, anon, authenticated;

-- 8) the window's state (reads only, tests no code, writes nothing) ---
create or replace function public.descuento_estado(p_station text default null)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare s text; t public.discount_tills; g record; ended boolean; base jsonb;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  s := public._discount_session();
  base := jsonb_build_object('ok', true,
    'owner_ready', exists (select 1 from public.staff where active and role = 'owner' and pin_hash is not null),
    'guia_enabled', coalesce(public.setting('pos_discount_guia') #>> '{}', 'off') = 'on',
    'session', s is not null);
  t := public._discount_till_mine();
  if t.id is null then
    ended := s is not null and exists (select 1 from public.discount_tills d where d.session_id = s and d.login_id = auth.uid());
    return base || jsonb_build_object('till', jsonb_build_object('registered', false, 'ended', ended));
  end if;
  select * into g from public._discount_slot_state(t.slot);
  return base || jsonb_build_object('till', jsonb_build_object('registered', true, 'slot', t.slot, 'station', t.station,
           'by', t.enrolled_by_name, 'since', t.enrolled_at, 'state', g.state, 'until', g.until, 'wait', g.wait,
           'wait_s', g.wait_s, 'warn', g.warn));
end $$;
revoke all on function public.descuento_estado(text) from public, anon;
grant execute on function public.descuento_estado(text) to authenticated;

-- 9) authorize a discount: both codes in one call ---
create or replace function public.descuento_autorizar(p_category text, p_pin text, p_subtotal int,
    p_employee_pin text default null, p_company text default null, p_order_id uuid default null,
    p_expect int default null, p_request_id uuid default null, p_station text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  -- every free-text argument cut before any work (no answer may cost more for a longer one); the station cleaned once
  cat text := case when char_length(p_category) <= 32 then lower(btrim(p_category)) else '' end;
  pin text := left(p_pin, 64); epin text := left(p_employee_pin, 64);
  comp text; st text := nullif(left(coalesce(public._discount_clean(left(p_station, 64)), ''), 40), '');
  r public.discount_approvals; live public.discount_approvals; s text; t public.discount_tills; g record;
  a record; k record; e record; es record; w jsonb; need text; why text; err text; cname text; res jsonb;
  ben_id uuid; ben_name text; e_locked boolean := false; rate int; amt int; pr jsonb; arole text;
begin
  -- 1) the account
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  -- 2) the same attempt sent again (a lost reply): the request lock first (a retry waits for a first call still running)
  if p_request_id is not null then
    perform pg_advisory_xact_lock(hashtextextended('canopy.discount_request:' || p_request_id::text, 0));  -- A
    select * into r from public.discount_approvals where request_id = p_request_id;
    if r.id is not null then
      if r.login_id is distinct from auth.uid() then return jsonb_build_object('ok', false, 'error', 'bad_request'); end if;
      if r.created_at > now() - interval '30 minutes' then return public._discount_answer(r) || jsonb_build_object('replay', true); end if;
    end if;
  end if;
  -- an empty code tests nothing and costs nothing (how the page replays a bill-mode attempt with its codes wiped)
  if coalesce(btrim(pin), '') = '' then return jsonb_build_object('ok', false, 'error', 'no_request'); end if;
  -- 3) the request itself
  if cat not in ('empleado', 'local', 'huesped', 'guia') then return jsonb_build_object('ok', false, 'error', 'bad_discount'); end if;
  if p_subtotal is null or p_subtotal <= 0 then return jsonb_build_object('ok', false, 'error', 'empty'); end if;
  if cat = 'empleado' and coalesce(btrim(epin), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'missing_employee'); end if;
  if cat = 'guia' then
    comp := case when char_length(p_company) <= 320 then public._discount_company(p_company) end;
    if comp is null then return jsonb_build_object('ok', false, 'error', 'missing_company'); end if;
    -- the owner's adjustment 4: Guía Turista is off until the accountant confirms the IVA treatment (A-13)
    if coalesce(public.setting('pos_discount_guia') #>> '{}', 'off') <> 'on' then
      return jsonb_build_object('ok', false, 'error', 'guia_off'); end if;
    -- 4) Guía without an owner who has a PIN
    if not exists (select 1 from public.staff where active and role = 'owner' and pin_hash is not null) then
      return jsonb_build_object('ok', false, 'error', 'no_owner'); end if;
  end if;
  -- 5) a bill, first look, without a lock: refused before any code is tested, so a right and a wrong code get the same answer
  if p_order_id is not null then
    err := public._discount_bill_problem(p_order_id, p_subtotal, p_expect, false);
    if err is not null then return jsonb_build_object('ok', false, 'error', err); end if;
  end if;
  -- 6a) the sign-in: a token without session_id is never counted and never shares a bucket
  s := public._discount_session();
  if s is null then return jsonb_build_object('ok', false, 'error', 'no_session'); end if;
  -- 6b) only a registered till tests codes; anything else: no bcrypt, no count, no lock
  t := public._discount_till_mine();
  if t.id is null then
    perform public._discount_till_unknown(s, st);
    return jsonb_build_object('ok', false, 'error',
      case when exists (select 1 from public.discount_tills d where d.session_id = s and d.login_id = auth.uid())
           then 'till_ended' else 'till_not_enrolled' end);
  end if;
  -- 6c) a waiting or stopped till is answered before any lock
  select * into g from public._discount_slot_state(t.slot);
  if g.state <> 'ok' then
    return jsonb_build_object('ok', false, 'error', 'till_' || g.state, 'until', g.until, 'wait', g.wait, 'wait_s', g.wait_s);
  end if;
  -- 6d) this place's lock, then everything again
  perform pg_advisory_xact_lock(hashtextextended('canopy.discount_slot:' || t.slot::text, 0));  -- C
  select * into t from public.discount_tills where id = t.id;
  if t.ended_at is not null then return jsonb_build_object('ok', false, 'error', 'till_ended'); end if;
  select * into g from public._discount_slot_state(t.slot);
  if g.state <> 'ok' then
    return jsonb_build_object('ok', false, 'error', 'till_' || g.state, 'until', g.until, 'wait', g.wait, 'wait_s', g.wait_s);
  end if;
  update public.discount_tills set last_used_at = now() where id = t.id;
  -- 6e) the authorizing code: a manager's (or the owner's), the owner's only for Guía
  need := case when cat = 'guia' then 'owner' else 'manager' end;
  select * into a from public._staff_by_code(pin);
  if a.n <> 1 or (need = 'owner' and a.srole <> 'owner') or (need = 'manager' and a.srole not in ('manager', 'owner')) then
    if a.n > 1 then
      with x as (insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
        values ('pin_duplicate', null, null, t.id::text, 'a code typed at the discount window belongs to more than one active person',
                jsonb_build_object('step', need, 'till', t.id, 'by_login', auth.uid())) returning id)
      insert into public.discount_pin_shared (audit_id, staff_ids) select id, a.ids from x;
    end if;
    w := public._discount_wrong(t, need, case when a.n > 1 then 'ambiguous' when a.n = 1 then 'not_allowed' else 'no_match' end,
                                cat, st);
    return jsonb_build_object('ok', false, 'error', 'bad_pin', 'step', need) || w;
  end if;
  select * into k from public._discount_take_staff(a.sid);  -- level 1
  if not k.ok then
    w := public._discount_wrong(t, need, 'inactive', cat, st);
    return jsonb_build_object('ok', false, 'error', 'bad_pin', 'step', need) || w;
  end if;
  arole := case when a.srole = 'owner' then 'owner' else 'manager' end;
  -- 6f) the employee code (Empleado), tested only after a valid authorizing code
  if cat = 'empleado' then
    select * into e from public._staff_by_code(epin);
    if e.n = 1 and e.sid = a.sid then
      insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
        values ('discount_self_refused', a.sid, a.sname, t.id::text, 'a manager tried an employee discount for themselves',
                jsonb_build_object('category', cat, 'till', t.id, 'slot', t.slot, 'station', st, 'by_login', auth.uid()));
      return jsonb_build_object('ok', false, 'error', 'not_self');
    end if;
    if e.n <> 1 or e.srole = 'owner' then
      if e.n > 1 then
        with x as (insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
          values ('pin_duplicate', null, null, t.id::text, 'a code typed at the discount window belongs to more than one active person',
                  jsonb_build_object('step', 'employee', 'till', t.id, 'by_login', auth.uid())) returning id)
        insert into public.discount_pin_shared (audit_id, staff_ids) select id, e.ids from x;
      end if;
      w := public._discount_wrong(t, 'employee', case when e.n > 1 then 'ambiguous' when e.n = 1 then 'owner_beneficiary' else 'no_match' end,
                                  cat, st, a.sid, a.sname);
      return jsonb_build_object('ok', false, 'error', 'bad_employee', 'step', 'employee') || w;
    end if;
    select * into es from public._discount_staff_state(e.sid);                                           -- no lock
    if not es.ok then
      w := public._discount_wrong(t, 'employee', 'inactive', cat, st, a.sid, a.sname);
      return jsonb_build_object('ok', false, 'error', 'bad_employee', 'step', 'employee') || w;
    end if;
    ben_id := e.sid; ben_name := e.sname; e_locked := es.locked;
  end if;
  -- 7) a bill under its lock (after the staff row), checked again: another device may have changed it
  if p_order_id is not null then
    err := public._discount_bill_problem(p_order_id, p_subtotal, p_expect, true);  -- level 2
    if err is not null then
      insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
        values ('discount_refused', a.sid, a.sname, p_order_id::text, 'discount refused after a valid code: ' || err,
                jsonb_build_object('why', err, 'category', cat, 'authorizer', a.sname, 'role', arole, 'beneficiary', ben_name,
                                   'bill', p_order_id, 'till', t.id, 'slot', t.slot, 'by_login', auth.uid(),
                                   'session_tag', public._discount_tag(s), 'station', st));
      return jsonb_build_object('ok', false, 'error', err);
    end if;
  end if;
  -- 8) Empleado: one a day. The per-employee lock; unused approvals of today older than 30 minutes expire first, then a
  --    discount_daily_twice sale of that day takes the day back (an expired approval never opens a second discount)
  if cat = 'empleado' then
    perform pg_advisory_xact_lock(hashtextextended('canopy.discount_employee:' || ben_id::text, 0));  -- level 3
    update public.discount_approvals set freed_at = now(), freed_how = 'expired'
     where category = 'empleado' and beneficiary_id = ben_id and cr_day = public.cr_today() and freed_at is null
       and order_id is null and used_at is null and created_at <= now() - interval '30 minutes';
    perform public._discount_retake_day(ben_id, public.cr_today());  -- level 4
    select * into live from public.discount_approvals
     where category = 'empleado' and beneficiary_id = ben_id and cr_day = public.cr_today() and freed_at is null
     order by created_at limit 1;
    if live.id is not null then
      insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
        values ('discount_daily_refused', a.sid, a.sname, live.id::text, 'employee discount already used today: ' || ben_name,
                jsonb_build_object('beneficiary_name', ben_name, 'beneficiary', ben_id, 'approval', live.id,
                                   'pending', live.order_id is null, 'category', cat, 'till', t.id, 'by_login', auth.uid(),
                                   'station', st));
      return jsonb_build_object('ok', false, 'error', 'daily_used', 'beneficiary', ben_name, 'pending', live.order_id is null)
             || case when live.order_id is null
                     then jsonb_build_object('station', live.station, 'until', live.created_at + interval '30 minutes')
                     else '{}'::jsonb end;
    end if;
  end if;
  -- 9) and 10) the approval, its log row and, for a bill, its application together (a refusal rolls back the three)
  rate := public._discount_rate(cat);
  amt := round(p_subtotal * rate / 100.0)::int;
  begin
    insert into public.discount_approvals (approved_by, approved_name, kind, value, reason, station, subtotal_crc, amount_crc,
                                           category, beneficiary_id, beneficiary_name, company, cr_day, approver_role, bill_id,
                                           login_id, session_id, request_id, till_id)
      values (a.sid, a.sname, 'percent', rate, public._discount_label(cat), st, p_subtotal, amt,
              cat, ben_id, ben_name, comp, public.cr_today(), arole, p_order_id,
              auth.uid(), left(public._jwt_session(), 64), p_request_id, t.id)
      returning * into r;
    pr := public._discount_answer(r) -> 'prior';
    insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
      values ('discount_approved', a.sid, a.sname, r.id::text, r.reason,
              jsonb_build_object('kind', 'percent', 'value', rate, 'subtotal_crc', p_subtotal, 'discount_crc', amt, 'station', st,
                                 'category', cat, 'beneficiary_name', ben_name, 'company', comp, 'approver_role', arole,
                                 'bill', p_order_id, 'prior', pr, 'till', t.id, 'slot', t.slot,
                                 'person_locked', k.locked, 'employee_locked', e_locked, 'by_login', auth.uid()));
    if p_order_id is not null then
      perform set_config('canopy.discount_call', p_order_id::text, true);
      res := public.tab_set_discount(p_order_id, r.id, p_expect, left(p_station, 64));
      perform set_config('canopy.discount_call', '', true);
      if not coalesce((res ->> 'ok')::boolean, false) then
        raise exception using errcode = 'P0001', message = 'discount_apply:' || coalesce(res ->> 'error', 'failed');
      end if;
    end if;
  exception
    when unique_violation then
      get stacked diagnostics cname = constraint_name;
      if cname = 'discount_employee_once' then
        insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
          values ('discount_daily_refused', a.sid, a.sname, coalesce(p_order_id::text, t.id::text), 'employee discount already used today: ' || ben_name,
                  jsonb_build_object('beneficiary_name', ben_name, 'beneficiary', ben_id, 'category', cat, 'till', t.id,
                                     'by_login', auth.uid(), 'station', st, 'backstop', true));
        return jsonb_build_object('ok', false, 'error', 'daily_used', 'beneficiary', ben_name);
      elsif cname = 'discount_approvals_request' then
        select * into r from public.discount_approvals where request_id = p_request_id;
        if r.id is not null and r.login_id = auth.uid() and r.created_at > now() - interval '30 minutes' then
          return public._discount_answer(r) || jsonb_build_object('replay', true);
        end if;
        insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
          values ('discount_refused', a.sid, a.sname, coalesce(p_order_id::text, t.id::text), 'discount refused after a valid code: bad_request',
                  jsonb_build_object('why', 'bad_request', 'category', cat, 'authorizer', a.sname, 'role', arole,
                                     'beneficiary', ben_name, 'bill', p_order_id, 'till', t.id, 'slot', t.slot,
                                     'by_login', auth.uid(), 'session_tag', public._discount_tag(s), 'station', st));
        return jsonb_build_object('ok', false, 'error', 'bad_request');
      end if;
      raise;
    when sqlstate 'P0001' then
      get stacked diagnostics err = message_text;
      if err like 'discount_apply:%' then
        why := substr(err, 16);
        insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
          values ('discount_refused', a.sid, a.sname, p_order_id::text, 'discount refused after a valid code: ' || why,
                  jsonb_build_object('why', why, 'category', cat, 'authorizer', a.sname, 'role', arole, 'beneficiary', ben_name,
                                     'bill', p_order_id, 'till', t.id, 'slot', t.slot, 'by_login', auth.uid(),
                                     'session_tag', public._discount_tag(s), 'station', st));
        return jsonb_build_object('ok', false, 'error', why);
      end if;
      raise;
  end;
  -- 11) the answer
  return public._discount_answer(r);
end $$;
revoke all on function public.descuento_autorizar(text, text, int, text, text, uuid, int, uuid, text) from public, anon;
grant execute on function public.descuento_autorizar(text, text, int, text, text, uuid, int, uuid, text) to authenticated;

-- 10) let an unused approval go (the page: ×, «Limpiar pedido», the 25-minute expiry, a late answer, a lost reply) ---
create or replace function public.descuento_liberar(p_id uuid default null, p_request_id uuid default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare r public.discount_approvals;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  if p_request_id is not null then
    perform pg_advisory_xact_lock(hashtextextended('canopy.discount_request:' || p_request_id::text, 0));  -- A
    select * into r from public.discount_approvals
     where request_id = p_request_id and login_id = auth.uid() and category is not null;
  elsif p_id is not null then
    select * into r from public.discount_approvals where id = p_id and login_id = auth.uid() and category is not null;
  end if;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if r.category = 'empleado' and r.beneficiary_id is not null then
    perform pg_advisory_xact_lock(hashtextextended('canopy.discount_employee:' || r.beneficiary_id::text, 0));  -- 3
  end if;
  select * into r from public.discount_approvals where id = r.id for update;  -- 4
  if r.order_id is not null then return jsonb_build_object('ok', false, 'error', 'discount_used', 'id', r.id); end if;
  if r.freed_at is not null then return jsonb_build_object('ok', true, 'already', true, 'id', r.id); end if;
  update public.discount_approvals set freed_at = now(), freed_how = 'released' where id = r.id;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('discount_released', null, null, r.id::text, 'discount let go before any sale: ' || r.reason,
            jsonb_build_object('approval', r.id, 'category', r.category, 'beneficiary_name', r.beneficiary_name,
                               'authorizer', r.approved_name, 'station', r.station, 'by_login', auth.uid()));
  -- a discount_daily_twice sale of that day takes the day back (letting go never opens a second discount)
  if r.category = 'empleado' then perform public._discount_retake_day(r.beneficiary_id, r.cr_day); end if;  -- 4
  return jsonb_build_object('ok', true, 'id', r.id);
end $$;
revoke all on function public.descuento_liberar(uuid, uuid) from public, anon;
grant execute on function public.descuento_liberar(uuid, uuid) to authenticated;

-- 11) take a category discount off a bill: no PIN with nothing paid; after a payment a manager's PIN and a reason.
-- p_discount_id (a late answer taken back): only while the bill carries it
drop function if exists public.descuento_quitar_cuenta(uuid, int, text, uuid, text, text);
create or replace function public.descuento_quitar_cuenta(p_order_id uuid, p_expect int, p_station text default null,
    p_manager_id uuid default null, p_manager_pin text default null, p_reason text default null, p_discount_id uuid default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v record; vsid uuid; vsname text; o public.orders; a public.discount_approvals; was_paid boolean; r jsonb; why text;
        st text := nullif(left(coalesce(public._discount_clean(left(p_station, 64)), ''), 40), '');
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  if p_expect is null then return jsonb_build_object('ok', false, 'error', 'changed'); end if;
  -- the PIN first, when one was sent (it locks that staff row: the lock order of manager_void_order)
  if p_manager_id is not null or coalesce(p_manager_pin, '') <> '' then
    select * into v from public._verify_pin(p_manager_id, p_manager_pin, true);
    if v.err is not null then return jsonb_build_object('ok', false, 'error', v.err); end if;
    vsid := v.sid; vsname := v.sname;
  end if;
  select * into o from public.orders where id = p_order_id for update;
  if o.id is null or o.part_of is not null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if o.voided_at is not null or o.status = 'cancelled' then return jsonb_build_object('ok', false, 'error', 'cancelled'); end if;
  if o.paid then return jsonb_build_object('ok', false, 'error', 'already_paid'); end if;
  if o.discount_id is distinct from coalesce(p_discount_id, o.discount_id) then return jsonb_build_object('ok', false, 'error', 'not_on_bill'); end if;
  if p_expect <> o.total_crc then return jsonb_build_object('ok', false, 'error', 'changed'); end if;
  select * into a from public.discount_approvals where id = o.discount_id;
  if a.id is null or a.category is null then return jsonb_build_object('ok', false, 'error', 'not_category'); end if;
  was_paid := coalesce(o.parts_crc, 0) > 0 or exists (select 1 from public.order_items i where i.order_id = o.id and i.paid_qty > 0);
  why := nullif(left(btrim(coalesce(left(p_reason, 1000), '')), 160), '');
  if was_paid then
    if vsid is null then return jsonb_build_object('ok', false, 'error', 'needs_pin'); end if;
    if why is null then return jsonb_build_object('ok', false, 'error', 'missing_reason'); end if;
  end if;
  perform set_config('canopy.discount_call', o.id::text, true);
  r := public.tab_set_discount(o.id, null, p_expect, left(p_station, 64));
  perform set_config('canopy.discount_call', '', true);
  if not coalesce((r ->> 'ok')::boolean, false) then return r; end if;
  if was_paid then
    insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
      values ('discount_removed_paid', vsid, vsname, o.id::text, why,
              jsonb_build_object('approval', a.id, 'category', a.category, 'beneficiary_name', a.beneficiary_name,
                                 'reason', why, 'discount_kept', r -> 'discount', 'total_crc', r -> 'total',
                                 'bill', public._tab_label(o), 'station', st, 'by_login', auth.uid()));
  end if;
  return r || jsonb_build_object('paid', was_paid)
           || case when a.category = 'empleado' then jsonb_build_object('beneficiary', a.beneficiary_name, 'counts', true) else '{}'::jsonb end;
end $$;
revoke all on function public.descuento_quitar_cuenta(uuid, int, text, uuid, text, text, uuid) from public, anon;
grant execute on function public.descuento_quitar_cuenta(uuid, int, text, uuid, text, text, uuid) to authenticated;

-- 12) give an employee's day back after a discount that took no money: a manager's own PIN (never the beneficiary)
create or replace function public.descuento_cupo_devolver(p_approval_id uuid, p_manager_id uuid default null,
    p_manager_pin text default null, p_station text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare a public.discount_approvals; o public.orders; v record; code boolean; by_id uuid; by_name text; how text;
        st text := nullif(left(coalesce(public._discount_clean(left(p_station, 64)), ''), 40), '');
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  if public.access_level() is null then return jsonb_build_object('ok', false, 'error', 'owner_only'); end if;
  code := public.owner_with_code();
  select * into a from public.discount_approvals where id = p_approval_id;
  if a.id is null or a.category is distinct from 'empleado' or a.freed_at is not null then
    return jsonb_build_object('ok', false, 'error', 'not_freeable'); end if;
  if a.cr_day <> public.cr_today() then return jsonb_build_object('ok', false, 'error', 'day_over'); end if;
  how := public._discount_freeable(a);
  if how is null then return jsonb_build_object('ok', false, 'error', 'not_freeable'); end if;
  if code then
    by_id := null; by_name := public._owner_label();
  else
    if p_manager_id is not null and p_manager_id = a.beneficiary_id then
      return jsonb_build_object('ok', false, 'error', 'not_self'); end if;
    if p_manager_id is null or coalesce(btrim(p_manager_pin), '') = '' then
      return jsonb_build_object('ok', false, 'error', 'unknown_staff'); end if;
    select * into v from public._verify_pin(p_manager_id, p_manager_pin, true);  -- level 1
    if v.err is not null then return jsonb_build_object('ok', false, 'error', v.err); end if;
    by_id := v.sid; by_name := v.sname;
  end if;
  -- under the locks, everything again
  select * into o from public.orders where id = a.order_id for update;  -- level 2
  if a.beneficiary_id is not null then
    perform pg_advisory_xact_lock(hashtextextended('canopy.discount_employee:' || a.beneficiary_id::text, 0));  -- 3
  end if;
  select * into a from public.discount_approvals where id = p_approval_id for update;  -- 4
  if a.freed_at is not null then return jsonb_build_object('ok', false, 'error', 'not_freeable'); end if;
  how := public._discount_freeable(a);
  if how is null then return jsonb_build_object('ok', false, 'error', 'not_freeable'); end if;
  update public.discount_approvals set freed_at = now(), freed_how = how where id = a.id;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('discount_freed', by_id, by_name, a.id::text, 'employee day given back: ' || coalesce(a.beneficiary_name, ''),
            jsonb_build_object('how', how, 'approval', a.id, 'order', a.order_id, 'beneficiary_name', a.beneficiary_name,
                               'by_login', auth.uid(), 'station', st, 'phone_code', code));
  perform public._discount_retake_day(a.beneficiary_id, a.cr_day);
  return jsonb_build_object('ok', true, 'how', how, 'approval', a.id, 'beneficiary', a.beneficiary_name);
end $$;
-- how an Empleado approval took no money: 'bill_cancelled' (its order cancelled with nothing paid), 'bill_removed' (taken
-- off its bill with nothing paid, whatever the bill did afterwards), or null
create or replace function public._discount_freeable(a public.discount_approvals) returns text
language sql stable security definer set search_path = public as $$
  select case
    when o.id is null then null
    when o.status = 'cancelled' and o.discount_id is not distinct from a.id
         and not exists (select 1 from public.order_items i where i.order_id = o.id and i.paid_qty > 0)
         and not exists (select 1 from public.orders p where p.part_of = o.id and p.paid and p.voided_at is null
                           and p.given_back_at is null and p.total_crc > 0)
      then 'bill_cancelled'
    when o.discount_id is distinct from a.id
         and not exists (select 1 from public.audit_log x where x.action = 'discount_removed_paid' and x.details ->> 'approval' = a.id::text)
      then 'bill_removed'
  end
  from (select 1) d left join public.orders o on o.id = a.order_id;
$$;
revoke all on function public._discount_freeable(public.discount_approvals) from public, anon, authenticated;
revoke all on function public.descuento_cupo_devolver(uuid, uuid, text, text) from public, anon;
grant execute on function public.descuento_cupo_devolver(uuid, uuid, text, text) to authenticated;

-- 13) the registered tills: register this device, come back by key, the approvals log's list, resume, remove ---
-- register THIS sign-in as a till: the owner areas open on THIS sign-in (0033 binds an unlock to it), or the owner with
-- the phone code. No PIN tested here. A full café never replaces a till by itself: a manager picks one (p_replace)
create or replace function public.descuento_caja_registrar(p_station text default null, p_replace uuid default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare l record; s text; st text; u record; code boolean; by_id uuid; by_name text; who text; t public.discount_tills;
        pp record; target int; victim public.discount_tills; g record; k record; nid uuid;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  s := public._discount_session();
  if s is null then return jsonb_build_object('ok', false, 'error', 'no_session'); end if;
  if public.access_level() is null then return jsonb_build_object('ok', false, 'error', 'owner_only'); end if;
  code := public.owner_with_code();
  if code then
    by_id := null; by_name := 'Dueño'; who := public._owner_label();
  else
    select * into u from public._unlock_staff();
    if u.staff_id is null then return jsonb_build_object('ok', false, 'error', 'owner_only'); end if;
    by_id := u.staff_id; by_name := u.staff_name; who := u.staff_name;
  end if;
  select * into l from public._discount_till_limits();
  st := public._discount_station(p_station);
  perform pg_advisory_xact_lock(hashtextextended('canopy.discount_tills', 0));  -- B
  select * into t from public.discount_tills where session_id = s and ended_at is null;
  if t.id is not null then
    -- already registered (a lost reply, or a second tap): the owner areas are open here, so a new key is sent
    perform pg_advisory_xact_lock(hashtextextended('canopy.discount_slot:' || t.slot::text, 0));  -- C
    select * into k from public._discount_new_key();
    update public.discount_tills set key_hash = k.hash where id = t.id;
    return jsonb_build_object('ok', true, 'already', true, 'key', k.key, 'station', t.station, 'slot', t.slot);
  end if;
  select * into pp from public._discount_person(by_id);
  if not code and pp.enrolls_24h >= l.enrolls_person then
    return jsonb_build_object('ok', false, 'error', 'enroll_limit'); end if;
  if p_replace is not null then
    select * into victim from public.discount_tills where id = p_replace and ended_at is null;
    if victim.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
    if exists (select 1 from generate_series(1, l.slots) x(n)
                where not exists (select 1 from public.discount_tills d where d.slot = x.n and d.ended_at is null))
       and (code or pp.places < l.places_person) then
      return jsonb_build_object('ok', false, 'error', 'place_free'); end if;
    if not code and pp.places >= l.places_person and victim.enrolled_by is distinct from by_id then
      return jsonb_build_object('ok', false, 'error', 'person_limit', 'mine',
        (select coalesce(jsonb_agg(x order by (x ->> 'slot')::int), '[]') from jsonb_array_elements(public._discount_places(by_id)) x
          where (x ->> 'mine')::boolean));
    end if;
    if not code and pp.ends_24h >= l.ends_person then return jsonb_build_object('ok', false, 'error', 'end_limit'); end if;
    perform pg_advisory_xact_lock(hashtextextended('canopy.discount_slot:' || victim.slot::text, 0));  -- C
    update public.discount_tills set ended_at = now(), ended_by = by_id, ended_by_name = who, ended_how = 'replaced', key_hash = null
     where id = victim.id;
    insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
      values ('discount_till_ended', by_id, who, victim.id::text, 'a till stopped being registered for discounts (replaced)',
              jsonb_build_object('till', victim.id, 'slot', victim.slot, 'till_station', victim.station, 'how', 'replaced',
                                 'station', st, 'by_login', auth.uid(), 'account', public.account_kind()));
    target := victim.slot;
  else
    if not code and pp.places >= l.places_person then
      return jsonb_build_object('ok', false, 'error', 'person_limit', 'mine',
        (select coalesce(jsonb_agg(x order by (x ->> 'slot')::int), '[]') from jsonb_array_elements(public._discount_places(by_id)) x
          where (x ->> 'mine')::boolean));
    end if;
    -- a free place, the most used first: a new registration never gives a fresh budget while a used place is free
    select x.n into target from generate_series(1, l.slots) x(n) cross join lateral public._discount_slot_state(x.n) z
     where not exists (select 1 from public.discount_tills d where d.slot = x.n and d.ended_at is null)
     order by (z.state = 'stopped') desc, z.day_n desc, z.vacated_at desc nulls last, x.n
     limit 1;
    if target is null then
      return jsonb_build_object('ok', false, 'error', 'till_full', 'places', public._discount_places(by_id)); end if;
    perform pg_advisory_xact_lock(hashtextextended('canopy.discount_slot:' || target::text, 0));  -- C
  end if;
  select * into k from public._discount_new_key();
  update public.discount_tills set key_hash = null where slot = target and key_hash is not null;   -- earlier keys of this place
  insert into public.discount_tills (slot, session_id, login_id, station, enrolled_by, enrolled_by_name, key_hash)
    values (target, s, auth.uid(), st, by_id, by_name, k.hash) returning id into nid;
  select * into g from public._discount_slot_state(target);
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('discount_till_enrolled', by_id, who, nid::text, 'a till was registered for discounts',
            jsonb_build_object('till', nid, 'slot', target, 'till_station', st, 'session_tag', public._discount_tag(s),
                               'replaced', victim.id, 'replaced_station', victim.station, 'state', g.state,
                               'by_login', auth.uid(), 'account', public.account_kind()));
  return jsonb_build_object('ok', true, 'key', k.key, 'station', st, 'slot', target, 'by', by_name,
                            'replaced', victim.station, 'state', g.state, 'until', g.until, 'wait', g.wait, 'wait_s', g.wait_s);
end $$;
revoke all on function public.descuento_caja_registrar(text, uuid) from public, anon;
grant execute on function public.descuento_caja_registrar(text, uuid) to authenticated;

-- the device key brings a registered tablet back to ITS OWN place after any new sign-in: no PIN, no count, no cap
create or replace function public.descuento_caja_volver(p_key text, p_station text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare l record; s text; t public.discount_tills; r public.discount_tills; n int; first_at timestamptz; k record; nid uuid;
        g record; st text := public._discount_station(p_station);
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  s := public._discount_session();
  if s is null then return jsonb_build_object('ok', false, 'error', 'no_session'); end if;
  if coalesce(p_key, '') !~ '^[0-9a-f]{64}$' then return jsonb_build_object('ok', false, 'error', 'key_invalid'); end if;
  select * into l from public._discount_till_limits();
  perform pg_advisory_xact_lock(hashtextextended('canopy.discount_tills', 0));  -- B
  select * into t from public.discount_tills where session_id = s and ended_at is null;
  if t.id is not null then
    -- already here: the key that brought this sign-in here (its reply was lost) gets a new key; any other, nothing
    if t.login_id = auth.uid() and t.prev_key_hash = public._discount_key_hash(p_key) then
      perform pg_advisory_xact_lock(hashtextextended('canopy.discount_slot:' || t.slot::text, 0));  -- C
      select * into k from public._discount_new_key();
      update public.discount_tills set key_hash = k.hash where id = t.id;
      select * into g from public._discount_slot_state(t.slot);
      return jsonb_build_object('ok', true, 'already', true, 'key', k.key, 'station', t.station, 'slot', t.slot,
                                'state', g.state, 'until', g.until, 'wait', g.wait, 'wait_s', g.wait_s);
    end if;
    return jsonb_build_object('ok', true, 'already', true, 'station', t.station, 'slot', t.slot);
  end if;
  select * into r from public.discount_tills
   where key_hash = public._discount_key_hash(p_key) and login_id = auth.uid() and (ended_at is null or ended_how = 'signed_out');
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'key_invalid'); end if;
  -- a signed-out row's key works only while nobody else holds its place
  if r.ended_at is not null and exists (select 1 from public.discount_tills d where d.slot = r.slot and d.ended_at is null) then
    return jsonb_build_object('ok', false, 'error', 'key_invalid'); end if;
  select count(*)::int, min(a.at) into n, first_at from public.audit_log a
   where a.action = 'discount_till_rebound' and a.details ->> 'slot' = r.slot::text and a.at > now() - interval '1 hour';
  if n >= l.rebind_h then
    return jsonb_build_object('ok', false, 'error', 'rebind_limit', 'until', first_at + interval '1 hour'); end if;
  perform pg_advisory_xact_lock(hashtextextended('canopy.discount_slot:' || r.slot::text, 0));  -- C
  if r.ended_at is null then
    update public.discount_tills set ended_at = now(), ended_by_name = 'rebind', ended_how = 'rebound', key_hash = null where id = r.id;
  else
    update public.discount_tills set key_hash = null where id = r.id;
  end if;
  st := coalesce(st, r.station);
  select * into k from public._discount_new_key();
  insert into public.discount_tills (slot, session_id, login_id, station, enrolled_at, enrolled_by, enrolled_by_name, key_hash,
                                     rebound_from, prev_key_hash)
    values (r.slot, s, auth.uid(), st, r.enrolled_at, r.enrolled_by, r.enrolled_by_name, k.hash, r.id,
            public._discount_key_hash(p_key)) returning id into nid;
  select * into g from public._discount_slot_state(r.slot);
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('discount_till_rebound', null, null, nid::text, 'a registered till came back to its place with its device key',
            jsonb_build_object('till', nid, 'old_till', r.id, 'slot', r.slot, 'till_station', st,
                               'session_tag', public._discount_tag(s), 'how', case when r.ended_at is null then 'live' else 'signed_out' end,
                               'by_login', auth.uid(), 'account', public.account_kind()));
  return jsonb_build_object('ok', true, 'key', k.key, 'station', st, 'slot', r.slot, 'state', g.state, 'until', g.until,
                            'wait', g.wait, 'wait_s', g.wait_s);
end $$;
revoke all on function public.descuento_caja_volver(text, text) from public, anon;
grant execute on function public.descuento_caja_volver(text, text) to authenticated;

-- the approvals log's block «Cajas para descuentos»: the 3 places, free ones too. No session id, tag or key leaves the server
create or replace function public.descuento_cajas()
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare l record; s text; code boolean; u record; pp record; places jsonb; dup jsonb;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  if public.access_level() is null then return jsonb_build_object('ok', false, 'error', 'owner_only'); end if;
  select * into l from public._discount_till_limits();
  s := public._discount_session();
  code := public.owner_with_code();
  select coalesce(jsonb_agg(jsonb_build_object('slot', x.n, 'state', g.state, 'until', g.until, 'wait', g.wait,
           'wrong_24h', (select count(*)::int from public.audit_log a where a.action = 'discount_code_wrong'
                          and a.details ->> 'slot' = x.n::text and a.at > now() - l.day_win),
           'counted', g.day_n, 'resumes_24h', g.resumes_24h,
           'till', (select jsonb_build_object('id', t.id, 'station', t.station, 'by', t.enrolled_by_name, 'since', t.enrolled_at,
                                              'last_used', t.last_used_at, 'this_device', s is not null and t.session_id = s)
                      from public.discount_tills t where t.slot = x.n and t.ended_at is null))
           order by x.n), '[]')
    into places from generate_series(1, l.slots) x(n) cross join lateral public._discount_slot_state(x.n) g;
  if exists (select 1 from public.audit_log a where a.action = 'pin_duplicate' and a.at > now() - interval '7 days') then
    if public.access_level() = 'owner' then
      select coalesce(jsonb_agg(distinct st.name), '[]') into dup
        from public.audit_log a join public.discount_pin_shared d on d.audit_id = a.id cross join unnest(d.staff_ids) x(id)
        join public.staff st on st.id = x.id where a.action = 'pin_duplicate' and a.at > now() - interval '7 days';
    else
      dup := 'true'::jsonb;
    end if;
  end if;
  select * into u from public._unlock_staff();
  select * into pp from public._discount_person(case when code then null else u.staff_id end);
  return jsonb_build_object('ok', true, 'places', places,
    'resumes_cafe_24h', (select count(*)::int from public.audit_log a where a.action = 'discount_till_resumed'
                           and a.at > now() - l.day_win and coalesce(a.details ->> 'how', '') <> 'sql_editor'),
    'cafe_wrong_24h', (select count(*)::int from public.audit_log a where a.action = 'discount_code_wrong' and a.at > now() - l.day_win),
    'unknown_24h', (select count(*)::int from public.audit_log a where a.action = 'discount_till_unknown' and a.at > now() - l.day_win),
    'alert', (select jsonb_build_object('at', a.at, 'cafe_24h', a.details -> 'cafe_24h') from public.audit_log a
               where a.action = 'discount_alert' and a.at > now() - l.day_win order by a.id desc limit 1),
    'me', case when code then null else jsonb_build_object('places', pp.places, 'ends_24h', pp.ends_24h, 'enrolls_24h', pp.enrolls_24h) end,
    'shared_code', dup,
    'limits', jsonb_build_object('resume_cafe', l.resume_cafe, 'resume_slot', l.resume_slot, 'places_person', l.places_person,
                                 'ends_person', l.ends_person, 'enrolls_person', l.enrolls_person));
end $$;
revoke all on function public.descuento_cajas() from public, anon;
grant execute on function public.descuento_cajas() to authenticated;

-- resume a STOPPED place (held or free): owner areas + a manager's own PIN, or the phone code; caps before any PIN
create or replace function public.descuento_caja_reanudar(p_slot int, p_manager_id uuid default null,
    p_manager_pin text default null, p_station text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare l record; t public.discount_tills; g record; v record; by_id uuid; by_name text; cafe int; how text;
        st text := public._discount_station(p_station);
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  if public.access_level() is null then return jsonb_build_object('ok', false, 'error', 'owner_only'); end if;
  select * into l from public._discount_till_limits();
  if p_slot is null or p_slot not between 1 and l.slots then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  perform pg_advisory_xact_lock(hashtextextended('canopy.discount_tills', 0));  -- B
  perform pg_advisory_xact_lock(hashtextextended('canopy.discount_slot:' || p_slot::text, 0));  -- C
  select * into g from public._discount_slot_state(p_slot);
  if g.state <> 'stopped' then return jsonb_build_object('ok', false, 'error', 'not_stopped'); end if;
  select count(*)::int into cafe from public.audit_log a
   where a.action = 'discount_till_resumed' and a.at > now() - l.day_win and coalesce(a.details ->> 'how', '') <> 'sql_editor';
  if g.resumes_24h >= l.resume_slot or cafe >= l.resume_cafe then
    return jsonb_build_object('ok', false, 'error', 'resume_limit', 'until', g.until); end if;
  if public.owner_with_code() then
    by_id := null; by_name := public._owner_label(); how := 'owner_code';
  else
    if p_manager_id is null or coalesce(btrim(p_manager_pin), '') = '' then
      return jsonb_build_object('ok', false, 'error', 'unknown_staff'); end if;
    select * into v from public._verify_pin(p_manager_id, p_manager_pin, true);  -- level 1
    if v.err is not null then return jsonb_build_object('ok', false, 'error', v.err); end if;
    by_id := v.sid; by_name := v.sname; how := 'manager';
  end if;
  select * into t from public.discount_tills where slot = p_slot and ended_at is null;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('discount_till_resumed', by_id, by_name, p_slot::text, 'discounts resumed on one place',
            jsonb_build_object('slot', p_slot, 'till', t.id, 'till_station', t.station, 'how', how, 'day_n', g.day_n,
                               'until', g.until, 'station', st, 'by_login', auth.uid(), 'account', public.account_kind()));
  return jsonb_build_object('ok', true, 'slot', p_slot, 'station', t.station);
end $$;
revoke all on function public.descuento_caja_reanudar(int, uuid, text, text) from public, anon;
grant execute on function public.descuento_caja_reanudar(int, uuid, text, text) to authenticated;

-- remove a till's registration: its key spent, the row stays, the place keeps its count (3 a manager in 24 h)
create or replace function public.descuento_caja_quitar(p_till_id uuid, p_manager_id uuid default null,
    p_manager_pin text default null, p_station text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare l record; t public.discount_tills; v record; pp record; by_id uuid; by_name text; how text;
        st text := public._discount_station(p_station);
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  if public.access_level() is null then return jsonb_build_object('ok', false, 'error', 'owner_only'); end if;
  select * into l from public._discount_till_limits();
  perform pg_advisory_xact_lock(hashtextextended('canopy.discount_tills', 0));  -- B
  select * into t from public.discount_tills where id = p_till_id and ended_at is null;
  if t.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  perform pg_advisory_xact_lock(hashtextextended('canopy.discount_slot:' || t.slot::text, 0));  -- C
  if public.owner_with_code() then
    by_id := null; by_name := public._owner_label(); how := 'owner';
  else
    if p_manager_id is null or coalesce(btrim(p_manager_pin), '') = '' then
      return jsonb_build_object('ok', false, 'error', 'unknown_staff'); end if;
    select * into pp from public._discount_person(p_manager_id);
    if pp.ends_24h >= l.ends_person then return jsonb_build_object('ok', false, 'error', 'end_limit'); end if;
    select * into v from public._verify_pin(p_manager_id, p_manager_pin, true);  -- level 1
    if v.err is not null then return jsonb_build_object('ok', false, 'error', v.err); end if;
    by_id := v.sid; by_name := v.sname; how := 'manager';
  end if;
  update public.discount_tills set ended_at = now(), ended_by = by_id, ended_by_name = by_name, ended_how = how, key_hash = null
   where id = t.id;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('discount_till_ended', by_id, by_name, t.id::text, 'a till stopped being registered for discounts',
            jsonb_build_object('till', t.id, 'slot', t.slot, 'till_station', t.station, 'how', how,
                               'station', st, 'by_login', auth.uid(), 'account', public.account_kind()));
  return jsonb_build_object('ok', true, 'station', t.station, 'slot', t.slot);
end $$;
revoke all on function public.descuento_caja_quitar(uuid, uuid, text, text) from public, anon;
grant execute on function public.descuento_caja_quitar(uuid, uuid, text, text) to authenticated;

-- 14) the owner's SQL Editor tools (outside every cap; internal, revoked from everyone) ---
-- the read-only summary each tool ends with: every place, free ones too (computed after the tool's own writes)
create or replace function public._discount_places_summary() returns jsonb
language sql stable security definer set search_path = public, extensions as $$
  select coalesce(jsonb_agg(jsonb_build_object('slot', x.n, 'state', g.state, 'until', g.until,
           'wrong_24h', (select count(*)::int from public.audit_log a where a.action = 'discount_code_wrong'
                          and a.details ->> 'slot' = x.n::text and a.at > now() - interval '24 hours'),
           'station', t.station, 'enrolled_by_name', t.enrolled_by_name, 'held', t.id is not null) order by x.n), '[]')
    from generate_series(1, 3) x(n) cross join lateral public._discount_slot_state(x.n) g
    left join public.discount_tills t on t.slot = x.n and t.ended_at is null;
$$;
-- every place whose state is not ok (waiting or stopped), held or free, resumed
create or replace function public._discount_tills_resume_all(p_by text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare l record; g record; t public.discount_tills; n int := 0; i int;
begin
  select * into l from public._discount_till_limits();
  perform pg_advisory_xact_lock(hashtextextended('canopy.discount_tills', 0));  -- B
  for i in 1 .. l.slots loop
    perform pg_advisory_xact_lock(hashtextextended('canopy.discount_slot:' || i::text, 0));  -- C, in slot order
    select * into g from public._discount_slot_state(i);
    if g.state <> 'ok' then
      select * into t from public.discount_tills where slot = i and ended_at is null;
      insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
        values ('discount_till_resumed', null, p_by, i::text, 'discounts resumed on one place (SQL Editor)',
                jsonb_build_object('slot', i, 'till', t.id, 'till_station', t.station, 'how', 'sql_editor',
                                   'day_n', g.day_n, 'until', g.until));
      n := n + 1;
    end if;
  end loop;
  return jsonb_build_object('ok', true, 'resumed', n, 'places', public._discount_places_summary());
end $$;
-- every live till ended and EVERY key spent (signed-out rows' keys too): every tablet then needs a manager's «Registrar»
create or replace function public._discount_tills_end_all(p_by text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare l record; t public.discount_tills; n int := 0; m int; kn int := 0; i int;
begin
  select * into l from public._discount_till_limits();
  perform pg_advisory_xact_lock(hashtextextended('canopy.discount_tills', 0));  -- B
  for i in 1 .. l.slots loop
    perform pg_advisory_xact_lock(hashtextextended('canopy.discount_slot:' || i::text, 0));  -- C, in slot order
    for t in select * from public.discount_tills where slot = i and ended_at is null loop
      if t.key_hash is not null then kn := kn + 1; end if;
      update public.discount_tills set ended_at = now(), ended_by_name = p_by, ended_how = 'sql_editor', key_hash = null where id = t.id;
      insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
        values ('discount_till_ended', null, p_by, t.id::text, 'a till stopped being registered for discounts (SQL Editor)',
                jsonb_build_object('till', t.id, 'slot', t.slot, 'till_station', t.station, 'how', 'sql_editor'));
      n := n + 1;
    end loop;
  end loop;
  update public.discount_tills set key_hash = null where key_hash is not null;
  get diagnostics m = row_count;
  return jsonb_build_object('ok', true, 'ended', n, 'keys_spent', kn + m, 'places', public._discount_places_summary());
end $$;
-- every 0033 PIN lock off at once (someone keeps every manager locked at the name-picked boxes; runbook E-lock)
create or replace function public._pin_locks_clear_all(p_by text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare s public.staff; n int := 0;
begin
  for s in select * from public.staff where locked_until is not null and locked_until > now() order by id for update loop
    update public.staff set failed_pins = 0, locked_until = null where id = s.id;
    insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
      values ('pin_lock_cleared', null, p_by, s.id::text, 'removed the PIN lock of ' || s.name || ' (SQL Editor)',
              jsonb_build_object('staff_name', s.name, 'how', 'sql_editor'));
    n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'cleared', n,
    'still_locked', (select count(*)::int from public.staff where locked_until is not null and locked_until > now()),
    'places', public._discount_places_summary());
end $$;
revoke all on function public._discount_places_summary(), public._discount_tills_resume_all(text),
  public._discount_tills_end_all(text), public._pin_locks_clear_all(text) from public, anon, authenticated;

-- 15) the report: by category, employee, authorizer and company, with what was charged and the products covered ---
-- No is_cafe(): the accountant reads it too (_insights_allowed = sales permission or the books)
create or replace function public.descuentos_informe(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare d0 date := coalesce(p_from, public.cr_today()); d1 date; m38 timestamptz; rpt jsonb; anomalies jsonb; wrong jsonb;
begin
  if not public._insights_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  d1 := coalesce(p_to, d0);
  if d1 < d0 or d1 - d0 > 400 then return jsonb_build_object('ok', false, 'error', 'bad_range'); end if;
  select applied_at into m38 from canopy.migrations where version = 38;
  with ap as (
    select a.*, o.id as o_id, o.discount_id as o_discount_id, o.status as o_status, o.voided_at as o_voided_at, o.paid as o_paid,
           o.total_crc as o_total, o.discount_crc as o_discount, o.flags as o_flags, o.receipt_no as o_receipt,
           o.refunded_at as o_refunded_at, k.kept
      from public.discount_approvals a left join public.orders o on o.id = a.order_id
      -- taken off after a payment: the discount the paid items kept (its discount_removed_paid row)
      left join lateral (select coalesce((x.details ->> 'discount_kept')::int, 0) as kept from public.audit_log x
                          where x.action = 'discount_removed_paid' and x.details ->> 'approval' = a.id::text
                          order by x.id desc limit 1) k on true
     where (a.category is not null and a.cr_day between d0 and d1)
        or (a.category is null and (a.created_at at time zone 'America/Costa_Rica')::date between d0 and d1)
  ), st as (
    select ap.*,
      case
        when ap.category is null then case when m38 is not null and ap.created_at > m38 then 'free_old_after_0038' else 'free_old' end
        when ap.order_id is null and ap.freed_at is null and ap.created_at > now() - interval '30 minutes' then 'pending'
        when ap.order_id is null and ap.freed_how = 'released' then 'released'
        when ap.order_id is null then 'expired'
        when ap.kept is not null then 'removed_paid'
        when ap.o_discount_id is distinct from ap.id and (ap.category <> 'empleado' or ap.freed_how = 'bill_removed') then 'removed'
        when ap.o_discount_id is distinct from ap.id then 'removed_counts'
        when ap.o_status = 'cancelled' and (ap.category <> 'empleado' or ap.freed_at is not null) then 'bill_cancelled'
        when ap.o_status = 'cancelled' then 'bill_cancelled_counts'
        when ap.o_voided_at is not null and ap.category = 'empleado' and ap.freed_how = 'void' then 'voided_freed'
        when ap.o_voided_at is not null and ap.category = 'empleado' then 'voided_counts'
        when ap.o_voided_at is not null then 'voided'
        when ap.o_refunded_at is not null or exists (select 1 from public.orders x where x.refund_of = ap.order_id and x.voided_at is null)
          then 'refunded'
        when not coalesce(ap.o_paid, true) then 'open_bill'
        when 'discount_not_verified' = any (coalesce(ap.o_flags, '{}')) then 'used_unverified'
        else 'used'
      end as status
      from ap
  ), rw as (
    select st.*,
      coalesce(st.status in ('used', 'used_unverified', 'open_bill', 'refunded')
        or (st.status like 'free_old%' and st.o_id is not null and st.o_discount_id = st.id
            and st.o_voided_at is null and st.o_status <> 'cancelled')
        -- taken off after a payment: the part the paid items kept was given (as the books and Sales count it)
        or (st.status = 'removed_paid' and st.o_voided_at is null and st.o_status <> 'cancelled'), false) as given,
      case when st.status = 'removed_paid' then st.kept
           when st.o_id is not null and st.o_discount_id = st.id then st.o_discount else st.amount_crc end as disc,
      -- o's covered lines now while it carries it (a line taken off lowers it)
      case when st.o_discount_id = st.id then (select coalesce(sum(i.qty * i.price_crc), 0)::int from public.order_items i
                where i.order_id = st.o_id and i.added_at <= coalesce(st.used_at, now())) else st.subtotal_crc end as lv,
      case when st.o_id is null then null else
        (case when st.o_paid and st.o_voided_at is null and st.o_status <> 'cancelled' then st.o_total else 0 end)
        + coalesce((select sum(p.total_crc) from public.orders p where p.part_of = st.o_id and p.paid and p.voided_at is null), 0)::int
      end as charged,
      (select coalesce(-sum(x.total_crc), 0)::int from public.orders x where x.refund_of = st.o_id and x.voided_at is null) as refunded,
      (select coalesce(jsonb_agg(jsonb_build_object('name', i.item_name, 'qty', i.qty, 'price', i.price_crc, 'tax_rate', i.tax_rate)
                                 order by i.added_at, i.id), '[]')
         from public.order_items i where i.order_id = st.o_id and i.added_at <= coalesce(st.used_at, now())) as products,
      (select coalesce(jsonb_agg(jsonb_build_object('name', i.item_name, 'qty', i.qty, 'price', i.price_crc, 'tax_rate', i.tax_rate)
                                 order by i.added_at, i.id), '[]')
         from public.order_items i where i.order_id = st.o_id and i.added_at > coalesce(st.used_at, now())) as added_after
      from st
  )
  select jsonb_build_object(
    'rows', coalesce(jsonb_agg(jsonb_build_object(
        'id', rw.id, 'at', rw.created_at, 'day', coalesce(rw.cr_day, (rw.created_at at time zone 'America/Costa_Rica')::date),
        'category', rw.category, 'status', rw.status, 'given', rw.given, 'kind', rw.kind, 'value', rw.value, 'reason', rw.reason,
        'beneficiary', rw.beneficiary_name, 'company', rw.company, 'authorizer', rw.approved_name, 'role', rw.approver_role,
        'station', rw.station, 'order_id', rw.order_id, 'bill_id', rw.bill_id, 'receipt_no', rw.o_receipt,
        'list_value', rw.lv, 'approved_value', rw.subtotal_crc, 'discount', rw.disc, 'charged', rw.charged, 'refunded', rw.refunded,
        'products', rw.products, 'added_after', rw.added_after, 'partial', jsonb_array_length(rw.added_after) > 0,
        'freed_how', rw.freed_how, 'flags', to_jsonb(coalesce(rw.o_flags, '{}'::text[])))
      order by rw.created_at, rw.id), '[]'),
    'totals', jsonb_build_object(
      'by_category', (select coalesce(jsonb_agg(x order by x ->> 'category' nulls first), '[]') from (
          select jsonb_build_object('category', category, 'rows', count(*), 'given', count(*) filter (where given),
                   'discount', coalesce(sum(disc) filter (where given), 0), 'list_value', coalesce(sum(lv) filter (where given), 0)) x
            from rw group by category) q),
      'by_employee', (select coalesce(jsonb_agg(x order by x ->> 'beneficiary'), '[]') from (
          select jsonb_build_object('beneficiary', beneficiary_name, 'rows', count(*), 'given', count(*) filter (where given),
                   'discount', coalesce(sum(disc) filter (where given), 0), 'list_value', coalesce(sum(lv) filter (where given), 0)) x
            from rw where category = 'empleado' group by beneficiary_name) q),
      'by_authorizer', (select coalesce(jsonb_agg(x order by x ->> 'name', x ->> 'role'), '[]') from (
          select jsonb_build_object('name', approved_name, 'role', approver_role, 'rows', count(*), 'given', count(*) filter (where given),
                   'discount', coalesce(sum(disc) filter (where given), 0), 'list_value', coalesce(sum(lv) filter (where given), 0)) x
            from rw group by approved_name, approver_role) q),
      'by_company', (select coalesce(jsonb_agg(x order by x ->> 'company'), '[]') from (
          select jsonb_build_object('company', company, 'rows', count(*), 'given', count(*) filter (where given),
                   'discount', coalesce(sum(disc) filter (where given), 0), 'list_value', coalesce(sum(lv) filter (where given), 0)) x
            from rw where category = 'guia' group by company) q)),
    -- information only (A-13): the list value of the courtesies' covered lines by their stamped tax rate; no tax computed
    'courtesies', (select coalesce(jsonb_agg(jsonb_build_object('tax_rate', tr, 'list_value', lv) order by tr nulls first), '[]') from (
          select (p ->> 'tax_rate')::numeric as tr, sum((p ->> 'qty')::int * (p ->> 'price')::int)::int as lv
            from rw cross join lateral jsonb_array_elements(rw.products) p
           where rw.category = 'guia' and rw.given group by 1) q))
    into rpt from rw;
  -- sales with an approval another order had already used (their discount_not_verified row): own products, claimed who
  select coalesce(jsonb_agg(jsonb_build_object('order_id', o.id, 'approval', x.details ->> 'approval', 'category', a.category,
           'authorizer', a.approved_name, 'role', a.approver_role, 'beneficiary', a.beneficiary_name, 'company', a.company,
           -- the rows' ladder, and charged / refunded as the rows count them
           'status', case when o.status = 'cancelled' then 'bill_cancelled' when o.voided_at is not null then 'voided'
                          when o.refunded_at is not null or rf.n > 0 then 'refunded' when not o.paid then 'open_bill' else 'used_unverified' end,
           'at', o.created_at, 'station', o.station, 'receipt_no', o.receipt_no, 'subtotal', o.subtotal_crc,
           'discount', o.discount_crc, 'total', o.total_crc, 'refunded', rf.crc, 'reason', o.discount_reason, 'flags', to_jsonb(o.flags),
           'charged', (case when o.paid and o.voided_at is null and o.status <> 'cancelled' then o.total_crc else 0 end)
             + coalesce((select sum(p.total_crc) from public.orders p where p.part_of = o.id and p.paid and p.voided_at is null), 0)::int,
           'products', (select coalesce(jsonb_agg(jsonb_build_object('name', i.item_name, 'qty', i.qty, 'price', i.price_crc,
                                                                      'tax_rate', i.tax_rate) order by i.added_at, i.id), '[]')
                          from public.order_items i where i.order_id = o.id))
           order by x.id), '[]')
    into anomalies
    from public.audit_log x join public.orders o on o.id::text = x.target_id
    left join public.discount_approvals a on a.id::text = x.details ->> 'approval'
    cross join lateral (select count(*) n, coalesce(-sum(r.total_crc), 0)::int crc from public.orders r
                         where r.refund_of = o.id and r.voided_at is null) rf
   where x.action = 'discount_not_verified' and x.details ->> 'why' = 'used_by_other'
     and (x.at at time zone 'America/Costa_Rica')::date between d0 and d1;
  -- the wrong-code block, per Costa Rica day
  with ev as (
    select a.*, (a.at at time zone 'America/Costa_Rica')::date as day from public.audit_log a
     where a.action in ('discount_code_wrong', 'discount_till_stopped', 'discount_till_resumed', 'discount_till_enrolled',
                        'discount_till_ended', 'discount_till_signed_out', 'discount_till_rebound', 'discount_till_unknown',
                        'discount_alert', 'pin_duplicate', 'discount_refused', 'discount_approved')
       and a.at >= public.cr_day_start(d0) and a.at < public.cr_day_start(d1 + 1)
  ), days as (select distinct day from ev where action <> 'discount_approved' or details ->> 'person_locked' = 'true')
  select coalesce(jsonb_agg(jsonb_build_object(
      'day', dd.day,
      'wrong', (select count(*) from ev where ev.day = dd.day and action = 'discount_code_wrong'),
      'by_step', (select coalesce(jsonb_object_agg(k, n), '{}') from (select coalesce(details ->> 'step', '?') k, count(*) n from ev
                   where ev.day = dd.day and action = 'discount_code_wrong' group by 1) q),
      'by_why', (select coalesce(jsonb_object_agg(k, n), '{}') from (select coalesce(details ->> 'why', '?') k, count(*) n from ev
                  where ev.day = dd.day and action = 'discount_code_wrong' group by 1) q),
      'refused', (select count(*) from ev where ev.day = dd.day and action = 'discount_refused'),
      'places', (select coalesce(jsonb_agg(jsonb_build_object('slot', sl,
                    'stations', (select coalesce(jsonb_agg(distinct details ->> 'till_station') filter (where details ->> 'till_station' is not null), '[]')
                                   from ev where ev.day = dd.day and action = 'discount_code_wrong' and details ->> 'slot' = sl),
                    'wrong', (select count(*) from ev where ev.day = dd.day and action = 'discount_code_wrong' and details ->> 'slot' = sl),
                    -- waits started: the 3rd or later wrong code in an hour, unless it was the one that stopped the place
                    -- (the stop wins: day_n reached day_max, _discount_slot_state)
                    'waits', (select count(*) from ev where ev.day = dd.day and action = 'discount_code_wrong' and details ->> 'slot' = sl
                                and coalesce((details ->> 'hour_n')::int, 0) >= 3
                                and coalesce((details ->> 'day_n')::int, 0) < (select l.day_max from public._discount_till_limits() l)),
                    'stops', (select count(*) from ev where ev.day = dd.day and action = 'discount_till_stopped' and details ->> 'slot' = sl),
                    'resumes', (select coalesce(jsonb_agg(jsonb_build_object('at', at, 'how', details ->> 'how', 'by', manager_name) order by id), '[]')
                                  from ev where ev.day = dd.day and action = 'discount_till_resumed' and details ->> 'slot' = sl),
                    'signed_out', (select count(*) from ev where ev.day = dd.day and action = 'discount_till_signed_out' and details ->> 'slot' = sl),
                    'rebound', (select count(*) from ev where ev.day = dd.day and action = 'discount_till_rebound' and details ->> 'slot' = sl))
                    order by sl::int), '[]')
                  from (select distinct details ->> 'slot' as sl from ev where ev.day = dd.day and details ? 'slot'
                          and action in ('discount_code_wrong', 'discount_till_stopped', 'discount_till_resumed',
                                         'discount_till_signed_out', 'discount_till_rebound')) s),
      'enrolled', (select coalesce(jsonb_agg(jsonb_build_object('at', at, 'slot', details -> 'slot', 'by', manager_name,
                      'station', details ->> 'till_station', 'replaced_station', details ->> 'replaced_station') order by id), '[]')
                     from ev where ev.day = dd.day and action = 'discount_till_enrolled'),
      'ended', (select coalesce(jsonb_agg(jsonb_build_object('at', at, 'slot', details -> 'slot', 'by', manager_name,
                   'how', details ->> 'how', 'station', details ->> 'till_station') order by id), '[]')
                  from ev where ev.day = dd.day and action = 'discount_till_ended'),
      'shared', (select count(*) from ev where ev.day = dd.day and action = 'pin_duplicate'),
      'unknown', (select count(*) from ev where ev.day = dd.day and action = 'discount_till_unknown'),
      'unknown_stations', (select coalesce(jsonb_agg(distinct details ->> 'station') filter (where details ->> 'station' is not null), '[]')
                             from ev where ev.day = dd.day and action = 'discount_till_unknown'),
      'alerts', (select coalesce(jsonb_agg(jsonb_build_object('at', at, 'cafe_24h', details -> 'cafe_24h') order by id), '[]')
                   from ev where ev.day = dd.day and action = 'discount_alert'),
      'person_locked', (select count(*) from ev where ev.day = dd.day and action = 'discount_approved'
                          and details ->> 'person_locked' = 'true'))
    order by dd.day), '[]')
    into wrong from days dd;
  return jsonb_build_object('ok', true, 'from', d0, 'to', d1, 'applied_0038', m38) || rpt
         || jsonb_build_object('anomalies', anomalies, 'wrong_codes', wrong);
end $$;
revoke all on function public.descuentos_informe(date, date) from public, anon;
grant execute on function public.descuentos_informe(date, date) to authenticated;

-- 16) the legacy functions, replaced in place (same names, signatures and grants) ---
-- a) approve_discount (supabase/pos-stations.sql), plus the switch pos_free_discount and the reserved reasons
create or replace function public.approve_discount(p_staff_id uuid, p_pin text, p_kind text, p_value int,
                                                   p_subtotal int, p_reason text, p_station text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v record; a public.discount_approvals; amt int; why text;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  -- 0038: the old free window is retired by the owner's switch (on by default: older pages work as today)
  if public.setting('pos_free_discount') #>> '{}' = 'off' then
    raise exception 'approve_discount_off' using errcode = 'P0001';
  end if;
  why := left(trim(coalesce(p_reason, '')), 160);
  if why = '' then return jsonb_build_object('ok', false, 'error', 'missing_reason'); end if;
  -- 0038: a reason that would read as one of the four categories comes only from a category approval
  if public._discount_reserved(why) then return jsonb_build_object('ok', false, 'error', 'missing_reason'); end if;
  if p_kind not in ('percent', 'amount') or p_value is null or p_value <= 0
     or (p_kind = 'percent' and p_value > 100) then
    return jsonb_build_object('ok', false, 'error', 'bad_discount'); end if;
  if p_subtotal is null or p_subtotal <= 0 then return jsonb_build_object('ok', false, 'error', 'empty'); end if;
  if p_kind = 'amount' and p_value > p_subtotal then return jsonb_build_object('ok', false, 'error', 'too_big'); end if;
  select * into v from public._verify_pin(p_staff_id, p_pin, true);
  if v.err is not null then return jsonb_build_object('ok', false, 'error', v.err); end if;
  amt := case when p_kind = 'percent' then round(p_subtotal * p_value / 100.0)::int else p_value end;
  insert into public.discount_approvals (approved_by, approved_name, kind, value, reason, station, subtotal_crc, amount_crc)
    values (v.sid, v.sname, p_kind, p_value, why, nullif(left(trim(coalesce(p_station, '')), 40), ''), p_subtotal, amt)
    returning * into a;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('discount_approved', v.sid, v.sname, a.id::text, why,
            jsonb_build_object('kind', p_kind, 'value', p_value, 'subtotal_crc', p_subtotal, 'discount_crc', amt,
                               'station', a.station));
  return jsonb_build_object('ok', true, 'id', a.id, 'amount', amt, 'name', v.sname, 'reason', why, 'at', a.created_at);
end $$;

-- b) tab_set_discount (pos-tabs.sql) + one guard: a category approval goes on and comes off paid only via 0038's calls
create or replace function public.tab_set_discount(p_order_id uuid, p_discount_id uuid, p_expect int default null,
                                                   p_station text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o public.orders; a public.discount_approvals; s int; paid_value int; open_value int; used int; d int; t int;
        st text := nullif(left(trim(coalesce(p_station, '')), 40), '');
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  select * into o from public.orders where id = p_order_id for update;
  if o.id is null or o.part_of is not null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if o.voided_at is not null or o.status = 'cancelled' then return jsonb_build_object('ok', false, 'error', 'cancelled'); end if;
  if o.paid then return jsonb_build_object('ok', false, 'error', 'already_paid'); end if;
  if p_expect is not null and p_expect <> o.total_crc then return jsonb_build_object('ok', false, 'error', 'changed'); end if;
  -- 0038: a category approval is put on a bill only by descuento_autorizar; a category discount is taken off after a
  -- payment only by descuento_quitar_cuenta (a manager's PIN); with nothing paid any page takes it off, as today
  if coalesce(current_setting('canopy.discount_call', true), '') is distinct from o.id::text
     and (exists (select 1 from public.discount_approvals where id = p_discount_id and category is not null)
          or (exists (select 1 from public.discount_approvals where id = o.discount_id and category is not null)
              and (p_discount_id is not null
                   or coalesce(o.parts_crc, 0) > 0
                   or exists (select 1 from public.order_items where order_id = o.id and paid_qty > 0)))) then
    raise exception 'tab_set_discount_category' using errcode = 'P0001';
  end if;
  select coalesce(sum(qty * price_crc), 0)::int, coalesce(sum(paid_qty * price_crc), 0)::int
    into s, paid_value from public.order_items where order_id = o.id;
  open_value := s - paid_value;
  used := greatest(0, paid_value - o.parts_items_crc);
  -- the bill's value from its own books (a sale whose discount could not be verified keeps what it charged)
  s := coalesce(o.subtotal_crc, o.total_crc + o.parts_crc);
  if p_discount_id is null then
    d := case when o.subtotal_crc is null then 0 else used end;
    t := s - d - o.parts_crc;
    if t < 0 then return jsonb_build_object('ok', false, 'error', 'refund_first'); end if;
    update public.orders set subtotal_crc = case when d > 0 then s else null end, discount_crc = d, discount_id = null,
                             discount_reason = case when d > 0 then discount_reason else null end,
                             discount_by = case when d > 0 then discount_by else null end, total_crc = t
      where id = o.id;
    insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
      values ('tab_discount_removed', null, coalesce(st, o.station, 'POS'), o.id::text, public._tab_label(o),
              jsonb_build_object('discount_crc', coalesce(o.discount_crc, 0) - d, 'total_crc', t, 'bill', public._tab_label(o),
                                 'reason', o.discount_reason, 'station', st));
    return jsonb_build_object('ok', true, 'total', t, 'discount', d);
  end if;
  select * into a from public.discount_approvals where id = p_discount_id for update;
  if a.id is null then return jsonb_build_object('ok', false, 'error', 'discount_not_approved'); end if;
  if a.order_id is not null and a.order_id <> o.id then return jsonb_build_object('ok', false, 'error', 'discount_used'); end if;
  if now() > a.created_at + interval '30 minutes' then return jsonb_build_object('ok', false, 'error', 'discount_expired'); end if;
  -- it covers the items not paid yet: those paid by item keep their value and the discount they got
  update public.discount_approvals set base_crc = paid_value, base_used_crc = used where id = a.id;
  o.subtotal_crc := s; o.discount_id := a.id; o.discount_crc := 0;
  d := public._tab_discount(o, s, used, open_value);
  t := s - d - o.parts_crc;
  if t < 0 then
    update public.discount_approvals set base_crc = a.base_crc, base_used_crc = a.base_used_crc where id = a.id;
    return jsonb_build_object('ok', false, 'error', 'refund_first');
  end if;
  update public.orders set subtotal_crc = s, discount_crc = d, discount_id = a.id, discount_reason = a.reason,
                           discount_by = a.approved_name, total_crc = t
    where id = o.id;
  update public.discount_approvals set used_at = now(), order_id = o.id where id = a.id;
  return jsonb_build_object('ok', true, 'total', t, 'discount', d);
end $$;

-- c) _order_discount_check (pos-stations.sql). Old kind: as today. Category: today's two refusals of a malformed sale;
--    else the money as charged, flagged, never refused (D5), the flags through canopy.discount_flags
create or replace function public._order_discount_check()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare a public.discount_approvals; allowed int; cat text; ben uuid; lbl text; fl text[] := '{}'; ok_link boolean;
begin
  if coalesce(new.discount_crc, 0) < 0 then raise exception 'discount_not_approved' using errcode = 'P0001'; end if;
  if coalesce(new.discount_crc, 0) = 0 then
    -- no discount: a subtotal, when sent, must be the total
    if new.subtotal_crc is not null and new.total_crc <> new.subtotal_crc then
      raise exception 'discount_not_approved' using errcode = 'P0001'; end if;
    new.discount_crc := 0; new.discount_id := null; new.discount_reason := null; new.discount_by := null;
    return new;
  end if;
  if new.discount_id is null then raise exception 'discount_not_approved' using errcode = 'P0001'; end if;
  select x.category, x.beneficiary_id into cat, ben from public.discount_approvals x where x.id = new.discount_id;
  if cat is null then
    -- an old-kind approval (or none): as before 0038
    select * into a from public.discount_approvals where id = new.discount_id for update;
    if a.id is null then raise exception 'discount_not_approved' using errcode = 'P0001'; end if;
    if a.order_id is not null and a.order_id <> new.id then raise exception 'discount_used' using errcode = '23505'; end if;
    -- the sale must be rung within 30 minutes of the approval (the order's own time, so an offline sale still counts)
    if new.created_at > a.created_at + interval '30 minutes' or new.created_at < a.created_at - interval '10 minutes' then
      raise exception 'discount_expired' using errcode = 'P0001'; end if;
    if new.subtotal_crc is null or new.subtotal_crc <= 0 then raise exception 'discount_no_subtotal' using errcode = 'P0001'; end if;
    -- never more than the manager saw: a percentage follows the order down, not up
    allowed := case when a.kind = 'percent' then round(new.subtotal_crc * a.value / 100.0)::int
                    else least(a.value, new.subtotal_crc) end;
    if a.amount_crc is not null then allowed := least(allowed, a.amount_crc); end if;
    if new.discount_crc > allowed + (case when a.kind = 'percent' then 1 else 0 end)
       or new.discount_crc > new.subtotal_crc then raise exception 'discount_too_big' using errcode = 'P0001'; end if;
    if new.total_crc <> new.subtotal_crc - new.discount_crc or new.total_crc < 0 then
      raise exception 'discount_total' using errcode = 'P0001'; end if;
    new.discount_reason := a.reason;
    new.discount_by := a.approved_name;
    update public.discount_approvals set used_at = now(), order_id = new.id where id = a.id;
    return new;
  end if;
  -- a category approval: a malformed sale is refused as today (the page re-sends it without the discount)
  if new.subtotal_crc is null or new.subtotal_crc <= 0 then raise exception 'discount_no_subtotal' using errcode = 'P0001'; end if;
  if new.total_crc <> new.subtotal_crc - new.discount_crc or new.total_crc < 0 then
    raise exception 'discount_total' using errcode = 'P0001'; end if;
  lbl := public._discount_label(cat);
  begin
    if cat = 'empleado' and ben is not null then
      perform pg_advisory_xact_lock(hashtextextended('canopy.discount_employee:' || ben::text, 0));        -- level 3
    end if;
    select * into a from public.discount_approvals where id = new.discount_id for update;                   -- level 4
    if a.order_id is not null and a.order_id <> new.id then
      -- already used by another order: the money as charged, unlinked (no clash with orders_discount_once)
      new.discount_id := null; new.discount_reason := lbl || ' · not verified'; new.discount_by := null;
      fl := fl || 'discount_not_verified'::text;
      insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
        values ('discount_not_verified', null, coalesce(new.station, 'POS'), new.id::text, lbl || ' · approval already used',
                jsonb_build_object('order', new.id, 'approval', a.id, 'category', cat, 'why', 'used_by_other',
                                   'subtotal_crc', new.subtotal_crc, 'discount_crc', new.discount_crc));
    else
      -- consumed by this sale, whether it matches or not
      if a.freed_at is not null then
        begin
          update public.discount_approvals set freed_at = null, freed_how = null where id = a.id;
          insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
            values ('discount_used_after_release', null, coalesce(new.station, 'POS'), a.id::text, lbl || ' · used after it was let go',
                    jsonb_build_object('order', new.id, 'approval', a.id, 'category', cat, 'freed_how', a.freed_how,
                                       'beneficiary_name', a.beneficiary_name, 'day_taken', true));
        exception when unique_violation then
          -- the employee already holds another live approval that day: this one stays freed, the sale is flagged
          fl := fl || 'discount_daily_twice'::text;
          insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
            values ('discount_used_after_release', null, coalesce(new.station, 'POS'), a.id::text, lbl || ' · used after it was let go',
                    jsonb_build_object('order', new.id, 'approval', a.id, 'category', cat, 'freed_how', a.freed_how,
                                       'beneficiary_name', a.beneficiary_name, 'day_taken', false));
        end;
      end if;
      update public.discount_approvals set used_at = now(), order_id = new.id where id = a.id;
      ok_link := new.subtotal_crc = a.subtotal_crc and new.discount_crc = a.amount_crc;
      if ok_link then
        new.discount_reason := lbl; new.discount_by := a.approved_name;
      else
        new.discount_reason := lbl || ' · not verified'; new.discount_by := null;
        fl := fl || 'discount_not_verified'::text;
        insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
          values ('discount_not_verified', null, coalesce(new.station, 'POS'), new.id::text, lbl || ' · not the approved amount',
                  jsonb_build_object('order', new.id, 'approval', a.id, 'category', cat, 'why', 'mismatch',
                                     'subtotal_crc', new.subtotal_crc, 'discount_crc', new.discount_crc,
                                     'approved_subtotal', a.subtotal_crc, 'approved_discount', a.amount_crc));
      end if;
      -- rung outside 10 minutes before to 30 minutes after the approval (D-045's clock case): flagged, never refused
      if new.created_at > a.created_at + interval '30 minutes' or new.created_at < a.created_at - interval '10 minutes' then
        fl := fl || 'discount_late'::text;
      end if;
    end if;
  exception when others then
    -- never refuse the money: the sale is recorded as charged and unverified, the error logged (sqlstate only)
    new.discount_id := null; new.discount_reason := coalesce(lbl, 'Discount') || ' · not verified'; new.discount_by := null;
    fl := array['discount_not_verified'];
    begin
      insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
        values ('discount_check_error', null, coalesce(new.station, 'POS'), new.id::text, 'discount check failed, sale kept',
                jsonb_build_object('order', new.id, 'sqlstate', sqlstate));
    exception when others then null;
    end;
  end;
  if cardinality(fl) > 0 then
    perform set_config('canopy.discount_flags', new.id::text || '|' || array_to_string(fl, ','), true);
  end if;
  return new;
end $$;

-- 17) triggers ---
-- the flags of a category sale, appended after order_times_ins has reset the till's flags; it can never stop a sale
create or replace function public._order_discount_flags()
returns trigger language plpgsql security definer set search_path = public as $$
declare v text;
begin
  begin
    v := coalesce(current_setting('canopy.discount_flags', true), '');
    if v <> '' and split_part(v, '|', 1) = new.id::text then
      new.flags := coalesce(new.flags, '{}') || array(select f from unnest(string_to_array(split_part(v, '|', 2), ',')) f
                                                        where f <> '' and not (f = any (coalesce(new.flags, '{}'))));
      perform set_config('canopy.discount_flags', '', true);
    end if;
  exception when others then return new;
  end;
  return new;
end $$;
drop trigger if exists order_zz_discount on public.orders;
create trigger order_zz_discount before insert on public.orders for each row execute function public._order_discount_flags();

-- when an Empleado day stops counting, on a void, a cancel or a removal: a void by a non-beneficiary manager with no
-- paid parts left frees it; a cancel or a removal with nothing paid waits for a give-back (Q3). BEFORE only takes E
-- (ahead of order_stock_return); AFTER decides. A lock error is raised again; any other is logged, the change stands
create or replace function public._order_discount_after()
returns trigger language plpgsql security definer set search_path = public as $$
declare a public.discount_approvals; cat text; ben uuid; parts boolean; vname text;
begin
  if tg_when = 'BEFORE' then
    begin
      select x.category, x.beneficiary_id into cat, ben from public.discount_approvals x where x.id = old.discount_id;
      if cat = 'empleado' and ben is not null then
        perform pg_advisory_xact_lock(hashtextextended('canopy.discount_employee:' || ben::text, 0));  -- level 3
      end if;
    exception
      when deadlock_detected or lock_not_available or query_canceled then raise;
      when others then null;
    end;
    return new;
  end if;
  begin
    select x.category, x.beneficiary_id into cat, ben from public.discount_approvals x where x.id = old.discount_id;
    if cat is distinct from 'empleado' then return null; end if;
    if ben is not null then
      perform pg_advisory_xact_lock(hashtextextended('canopy.discount_employee:' || ben::text, 0));  -- level 3
    end if;
    select * into a from public.discount_approvals where id = old.discount_id for update;  -- level 4
    if a.id is null or a.freed_at is not null then return null; end if;
    if old.voided_at is null and new.voided_at is not null then
      select s.name into vname from public.staff s where s.id = new.voided_by;
      parts := exists (select 1 from public.orders p where p.part_of = new.id and p.paid and p.voided_at is null
                         and p.given_back_at is null and p.total_crc > 0);
      if a.beneficiary_id is not null and new.voided_by is not distinct from a.beneficiary_id then
        insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
          values ('discount_self_void', new.voided_by, vname, a.id::text, 'own discounted sale voided: the day stays used',
                  jsonb_build_object('approval', a.id, 'order', new.id, 'beneficiary_name', a.beneficiary_name, 'by_login', auth.uid()));
      elsif parts then
        insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
          values ('discount_not_freed', new.voided_by, vname, a.id::text, 'employee discount still counts: paid parts remain',
                  jsonb_build_object('why', 'parts', 'how', 'void', 'approval', a.id, 'order', new.id,
                                     'beneficiary_name', a.beneficiary_name, 'by_login', auth.uid()));
      else
        update public.discount_approvals set freed_at = now(), freed_how = 'void' where id = a.id;
        insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
          values ('discount_freed', new.voided_by, vname, a.id::text, 'employee day freed by a void: ' || coalesce(a.beneficiary_name, ''),
                  jsonb_build_object('how', 'void', 'approval', a.id, 'order', new.id, 'beneficiary_name', a.beneficiary_name,
                                     'by', vname, 'by_login', auth.uid()));
        perform public._discount_retake_day(a.beneficiary_id, a.cr_day);
      end if;
    elsif new.status = 'cancelled' and old.status is distinct from 'cancelled' then
      parts := exists (select 1 from public.order_items i where i.order_id = new.id and i.paid_qty > 0)
               or exists (select 1 from public.orders p where p.part_of = new.id and p.paid and p.voided_at is null
                            and p.given_back_at is null and p.total_crc > 0);
      insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
        values ('discount_not_freed', null, coalesce(new.station, 'POS'), a.id::text,
                case when parts then 'employee discount still counts: money was paid on the cancelled bill'
                     else 'employee discount still counts until a manager gives the day back' end,
                jsonb_build_object('why', case when parts then 'parts' else 'needs_manager' end, 'how', 'bill_cancelled',
                                   'approval', a.id, 'order', new.id, 'beneficiary_name', a.beneficiary_name, 'by_login', auth.uid()));
    elsif new.discount_id is distinct from old.discount_id then
      parts := coalesce(new.parts_crc, 0) > 0 or exists (select 1 from public.order_items i where i.order_id = new.id and i.paid_qty > 0);
      insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
        values ('discount_not_freed', null, coalesce(new.station, 'POS'), a.id::text,
                case when parts then 'employee discount still counts: taken off after a payment'
                     else 'employee discount still counts until a manager gives the day back' end,
                jsonb_build_object('why', case when parts then 'paid' else 'needs_manager' end, 'how', 'bill_removed',
                                   'approval', a.id, 'order', new.id, 'beneficiary_name', a.beneficiary_name, 'by_login', auth.uid()));
    end if;
  exception
    when deadlock_detected or lock_not_available or query_canceled then raise;
    when others then
    begin
      insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
        values ('discount_trigger_error', null, null, new.id::text, 'employee discount day check failed, the change was kept',
                jsonb_build_object('order', new.id, 'approval', old.discount_id, 'sqlstate', sqlstate));
    exception when others then null;
    end;
  end;
  return null;
end $$;
drop trigger if exists order_zz_discount_lock on public.orders;
create trigger order_zz_discount_lock before update of voided_at, status, discount_id on public.orders
  for each row
  when (old.discount_id is not null and (
          (old.voided_at is null and new.voided_at is not null)
       or (old.status is distinct from 'cancelled' and new.status = 'cancelled')
       or (new.discount_id is distinct from old.discount_id)))
  execute function public._order_discount_after();
drop trigger if exists order_zz_discount_after on public.orders;
create trigger order_zz_discount_after after update of voided_at, status, discount_id on public.orders
  for each row
  when (old.discount_id is not null and (
          (old.voided_at is null and new.voided_at is not null)
       or (old.status is distinct from 'cancelled' and new.status = 'cancelled')
       or (new.discount_id is distinct from old.discount_id)))
  execute function public._order_discount_after();
revoke all on function public._order_discount_flags(), public._order_discount_after() from public, anon, authenticated;

select canopy.migration_end(38, 'descuentos_caja');
notify pgrst, 'reload schema';
