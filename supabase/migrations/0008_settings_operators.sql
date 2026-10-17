-- =====================================================================================================
-- Canopy OS · migración 0008 · Ajustes del sistema y "quién está cobrando" en cada venta
-- Pegar TODO en Supabase → SQL Editor → New query → Run.  Requiere: 0007.
--
-- Qué hace
--   1) Ajustes del sistema (public.settings): un lugar para las decisiones del dueño, con valores permitidos,
--      registro en la bitácora y, para los ajustes regulados (impuestos, planilla, factura electrónica),
--      un CANDADO: no se pueden activar sin una confirmación registrada (quién confirmó y con qué documento).
--   2) Operador de caja: la persona que cobra se identifica con su PIN al empezar (sesión de operador).
--      Cada venta y cada pago queda a su nombre. Si no marcó entrada en el reloj, la venta se marca para el
--      gerente; con el ajuste en "exigir", no puede empezar sin marcar entrada (puede marcar ahí mismo).
--      Sin internet la caja sigue vendiendo: la venta queda a nombre de quien eligió, marcada "sin verificar".
-- Qué cambia para el personal: NADA hasta que el dueño cambie "operator_mode" (empieza en 'off').
-- Reversión: update public.settings set value = '"off"' where key = 'operator_mode';
-- =====================================================================================================
select canopy.migration_begin(8, 'settings_operators');

-- 1) settings ---------------------------------------------------------------------------------------------
create table if not exists canopy.setting_defs (
  key           text primary key,
  kind          text not null check (kind in ('choice', 'number', 'boolean', 'text')),
  choices       text[],
  default_value jsonb not null,
  guard         text,               -- a value other than the default needs this confirmation on record
  description   text not null
);
revoke all on canopy.setting_defs from public;

create table if not exists public.settings (
  key        text primary key references canopy.setting_defs(key),
  value      jsonb not null,
  updated_at timestamptz not null default now(),
  updated_by text
);
alter table public.settings enable row level security;
revoke all on public.settings from anon, authenticated;

-- confirmations of regulated rules (by the accountant or an official source), required before activation
create table if not exists public.compliance_confirmations (
  key          text primary key,
  confirmed_at timestamptz not null default now(),
  confirmed_by text not null,
  reference    text not null,
  note         text
);
alter table public.compliance_confirmations enable row level security;
revoke all on public.compliance_confirmations from anon, authenticated;

insert into canopy.setting_defs (key, kind, choices, default_value, guard, description) values
  ('operator_mode', 'choice', '{off,record,enforce}', '"off"', null,
   'Quién cobra: off = como antes; record = la caja pide el PIN de quien cobra y marca las ventas de quien no marcó entrada; enforce = no se puede cobrar sin marcar entrada.')
on conflict (key) do update set kind = excluded.kind, choices = excluded.choices, default_value = excluded.default_value,
                                guard = excluded.guard, description = excluded.description;

create or replace function public.setting(p_key text)
returns jsonb language sql stable security definer set search_path = public, canopy as $$
  select coalesce((select value from public.settings where key = p_key),
                  (select default_value from canopy.setting_defs where key = p_key));
$$;
revoke all on function public.setting(text) from public, anon;
grant execute on function public.setting(text) to authenticated;

-- every setting with its value, allowed values and whether it is locked behind a confirmation
create or replace function public.settings_get()
returns jsonb language sql stable security definer set search_path = public, canopy as $$
  select case when public.is_cafe() then coalesce(jsonb_agg(jsonb_build_object(
      'key', d.key, 'kind', d.kind, 'choices', to_jsonb(d.choices), 'value', public.setting(d.key), 'default', d.default_value,
      'description', d.description, 'guard', d.guard,
      'locked', d.guard is not null and not exists (select 1 from public.compliance_confirmations c where c.key = d.guard))
      order by d.key), '[]'::jsonb) end
    from canopy.setting_defs d;
$$;
revoke all on function public.settings_get() from public, anon;
grant execute on function public.settings_get() to authenticated;

create or replace function public.setting_set(p_key text, p_value jsonb)
returns jsonb language plpgsql security definer set search_path = public, canopy as $$
declare d canopy.setting_defs; before jsonb;
begin
  if public.access_level() is distinct from 'owner' then return jsonb_build_object('ok', false, 'error', 'owner_only'); end if;
  select * into d from canopy.setting_defs where key = p_key;
  if d.key is null then return jsonb_build_object('ok', false, 'error', 'unknown_setting'); end if;
  if p_value is null
     or (d.kind = 'choice' and (jsonb_typeof(p_value) <> 'string' or not (p_value #>> '{}') = any(d.choices)))
     or (d.kind = 'number' and jsonb_typeof(p_value) <> 'number')
     or (d.kind = 'boolean' and jsonb_typeof(p_value) <> 'boolean')
     or (d.kind = 'text' and jsonb_typeof(p_value) <> 'string') then
    return jsonb_build_object('ok', false, 'error', 'bad_value');
  end if;
  if d.guard is not null and p_value <> d.default_value
     and not exists (select 1 from public.compliance_confirmations where key = d.guard) then
    return jsonb_build_object('ok', false, 'error', 'needs_confirmation', 'guard', d.guard);
  end if;
  before := public.setting(p_key);
  insert into public.settings (key, value, updated_at, updated_by) values (p_key, p_value, now(), public._owner_label())
    on conflict (key) do update set value = excluded.value, updated_at = now(), updated_by = excluded.updated_by;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('setting_change', null, public._owner_label(), p_key, p_key || ': ' || (before #>> '{}') || ' → ' || (p_value #>> '{}'),
            jsonb_build_object('before', before, 'after', p_value));
  return jsonb_build_object('ok', true, 'value', p_value);
end $$;
revoke all on function public.setting_set(text, jsonb) from public, anon;
grant execute on function public.setting_set(text, jsonb) to authenticated;

-- the owner records that a regulated rule was confirmed (who, which document); never automatic
create or replace function public.compliance_confirm(p_key text, p_confirmed_by text, p_reference text, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public, canopy as $$
begin
  if public.access_level() is distinct from 'owner' then return jsonb_build_object('ok', false, 'error', 'owner_only'); end if;
  if not exists (select 1 from canopy.setting_defs where guard = p_key) then return jsonb_build_object('ok', false, 'error', 'unknown_key'); end if;
  if coalesce(trim(p_confirmed_by), '') = '' or coalesce(trim(p_reference), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'missing_reference');
  end if;
  insert into public.compliance_confirmations (key, confirmed_by, reference, note)
    values (p_key, trim(p_confirmed_by), trim(p_reference), nullif(trim(coalesce(p_note, '')), ''))
    on conflict (key) do update set confirmed_at = now(), confirmed_by = excluded.confirmed_by, reference = excluded.reference, note = excluded.note;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('compliance_confirm', null, public._owner_label(), p_key, 'confirmado por ' || trim(p_confirmed_by) || ' · ' || trim(p_reference),
            jsonb_build_object('confirmed_by', trim(p_confirmed_by), 'reference', trim(p_reference), 'note', p_note));
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.compliance_confirm(text, text, text, text) from public, anon;
grant execute on function public.compliance_confirm(text, text, text, text) to authenticated;

-- 2) operator sessions ---------------------------------------------------------------------------------------
create table if not exists public.operator_sessions (
  id          uuid primary key default gen_random_uuid(),
  token_hash  text not null unique,
  staff_id    uuid not null references public.staff(id),
  staff_name  text not null,
  user_id     uuid,
  station     text,
  started_at  timestamptz not null default now(),
  expires_at  timestamptz not null,
  ended_at    timestamptz,
  clocked_in  boolean not null
);
create index if not exists operator_sessions_staff_idx on public.operator_sessions (staff_id, started_at desc);
alter table public.operator_sessions enable row level security;
revoke all on public.operator_sessions from anon, authenticated;

alter table public.orders add column if not exists operator_id uuid;          -- who rang or took the payment
alter table public.orders add column if not exists operator_name text;
alter table public.orders add column if not exists operator_session uuid;
create index if not exists orders_operator_idx on public.orders (operator_id, business_date) where operator_id is not null;

create or replace function public._on_the_clock(p_staff uuid, p_at timestamptz)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.time_entries t where t.staff_id = p_staff
                   and t.clock_in <= p_at + interval '5 minutes' and (t.clock_out is null or t.clock_out >= p_at - interval '5 minutes'));
$$;
revoke all on function public._on_the_clock(uuid, timestamptz) from public, anon, authenticated;

create or replace function public.pos_operator_start(p_staff_id uuid, p_pin text, p_station text default null, p_clock_in boolean default false)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v record; mode text; clocked boolean; tok text; s public.operator_sessions; role text;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  mode := public.setting('operator_mode') #>> '{}';
  select * into v from public._verify_pin(p_staff_id, trim(coalesce(p_pin, '')), false);
  if v.err is not null then return jsonb_build_object('ok', false, 'error', v.err); end if;
  clocked := public._on_the_clock(v.sid, now());
  if not clocked and coalesce(p_clock_in, false) then
    insert into public.time_entries (staff_id, clock_in) values (v.sid, now());
    clocked := true;
  end if;
  if not clocked and mode = 'enforce' then
    return jsonb_build_object('ok', false, 'error', 'not_clocked_in', 'name', v.sname);
  end if;
  tok := encode(gen_random_bytes(24), 'hex');
  insert into public.operator_sessions (token_hash, staff_id, staff_name, user_id, station, expires_at, clocked_in)
    values (encode(digest(tok, 'sha256'), 'hex'), v.sid, v.sname, auth.uid(), nullif(left(trim(coalesce(p_station, '')), 40), ''),
            now() + interval '14 hours', clocked)
    returning * into s;
  select st.role into role from public.staff st where st.id = v.sid;
  return jsonb_build_object('ok', true, 'token', tok, 'staff_id', v.sid, 'name', v.sname, 'role', role,
                            'clocked_in', clocked, 'expires_at', s.expires_at, 'mode', mode);
end $$;

create or replace function public.pos_operator_end(p_token text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  update public.operator_sessions set ended_at = now()
   where token_hash = encode(digest(coalesce(p_token, ''), 'sha256'), 'hex') and ended_at is null;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.pos_operator_start(uuid, text, text, boolean), public.pos_operator_end(text) from public, anon;
grant execute on function public.pos_operator_start(uuid, text, text, boolean), public.pos_operator_end(text) to authenticated;

-- who is behind this insert: the sale's own operator (sent with an offline sale), else this request's header
create or replace function public._operator_resolve(p_at timestamptz,
    out staff_id uuid, out staff_name text, out session_id uuid, out verified boolean, out on_clock boolean)
language plpgsql stable security definer set search_path = public, extensions as $$
declare tok text; claim text; h text; s public.operator_sessions; cid uuid;
begin
  verified := false;
  tok := nullif(current_setting('canopy.operator_token', true), '');
  claim := nullif(current_setting('canopy.operator_claim', true), '');
  if tok = 'none' then return; end if;                     -- a sale rung with nobody signed in
  if tok is null then
    h := nullif(current_setting('request.headers', true), '');
    begin tok := nullif(trim(h::json ->> 'x-hg-operator'), ''); exception when others then tok := null; end;
  end if;
  if tok is not null then
    select * into s from public.operator_sessions o
     where o.token_hash = encode(digest(tok, 'sha256'), 'hex')
       and p_at >= o.started_at - interval '2 minutes'
       and p_at <= coalesce(o.ended_at, o.expires_at) + interval '2 minutes';
  end if;
  begin cid := nullif(claim, '')::uuid; exception when others then cid := null; end;
  if s.id is not null and (cid is null or cid = s.staff_id) then
    staff_id := s.staff_id; staff_name := s.staff_name; session_id := s.id; verified := true;
  elsif cid is not null then
    select st.id, st.name into staff_id, staff_name from public.staff st where st.id = cid and st.active;
  end if;
  if staff_id is not null then on_clock := public._on_the_clock(staff_id, p_at); end if;
end $$;
revoke all on function public._operator_resolve(timestamptz) from public, anon;
grant execute on function public._operator_resolve(timestamptz) to authenticated;   -- the order trigger runs as the till

-- every new order or payment carries its operator; the till cannot write these columns itself
create or replace function public._order_operator()
returns trigger language plpgsql set search_path = public as $$
declare r record; mode text;
begin
  if current_user in ('authenticated', 'anon') then
    new.operator_id := null; new.operator_name := null; new.operator_session := null;
  end if;
  if new.operator_id is not null then return new; end if;   -- a server function already decided
  select * into r from public._operator_resolve(coalesce(new.rung_at, new.created_at, now()));
  mode := public.setting('operator_mode') #>> '{}';
  if r.staff_id is not null then
    new.operator_id := r.staff_id; new.operator_name := r.staff_name; new.operator_session := r.session_id;
    if not r.verified then new.flags := array_append(coalesce(new.flags, '{}'), 'operator_unverified'); end if;
    if mode <> 'off' and not coalesce(r.on_clock, false) then new.flags := array_append(coalesce(new.flags, '{}'), 'operator_not_clocked_in'); end if;
  elsif mode <> 'off' and new.source is distinct from 'room' then
    new.flags := array_append(coalesce(new.flags, '{}'), 'no_operator');
  end if;
  return new;
end $$;
-- named to run after order_times_ins (which resets the till's flags)
drop trigger if exists order_zz_operator on public.orders;
create trigger order_zz_operator before insert on public.orders for each row execute function public._order_operator();

-- 3) the one-call sale save carries the operator of an offline sale -------------------------------------------
create or replace function public.pos_record_sale(p_order jsonb)
returns jsonb language plpgsql set search_path = public as $$
declare oid uuid; existing boolean := false; c text; other boolean := false; op jsonb;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  oid := nullif(p_order->>'id', '')::uuid;
  if oid is null or jsonb_typeof(coalesce(p_order->'items', '[]'::jsonb)) <> 'array' then
    raise exception 'bad_payload' using errcode = 'P0001';
  end if;
  -- the person who rang this sale (it may arrive hours later, after another person signed in)
  op := p_order->'operator';
  if op is not null and jsonb_typeof(op) = 'object' then
    perform set_config('canopy.operator_token', coalesce(nullif(op->>'token', ''), 'claim'), true);
    perform set_config('canopy.operator_claim', coalesce(op->>'staff_id', ''), true);
  elsif p_order ? 'operator' then
    perform set_config('canopy.operator_token', 'none', true);
  end if;
  begin
    insert into public.orders (id, created_at, total_crc, payment_method, paid, status, source, needs_kitchen, accepted_at,
                               pickup_number, guest_name, station, subtotal_crc, discount_crc, discount_id, notes)
    values (oid,
            coalesce((p_order->>'created_at')::timestamptz, now()),
            (p_order->>'total_crc')::int,
            coalesce(p_order->>'payment_method', 'cash_crc'),
            coalesce((p_order->>'paid')::boolean, true),
            coalesce(p_order->>'status', 'done'),
            coalesce(p_order->>'source', 'front'),
            coalesce((p_order->>'needs_kitchen')::boolean, false),
            (p_order->>'accepted_at')::timestamptz,
            (p_order->>'pickup_number')::int,
            nullif(left(p_order->>'guest_name', 60), ''),
            nullif(left(p_order->>'station', 40), ''),
            (p_order->>'subtotal_crc')::int,
            coalesce((p_order->>'discount_crc')::int, 0),
            (p_order->>'discount_id')::uuid,
            nullif(left(p_order->>'notes', 200), ''));
  exception when unique_violation then
    get stacked diagnostics c = constraint_name;
    if c = 'orders_pkey' then existing := true; else raise; end if;
  end;
  begin
    insert into public.order_items (id, order_id, item_name, price_crc, qty, menu_item_id)
      select coalesce(nullif(l->>'id', '')::uuid, gen_random_uuid()), oid, l->>'item_name', (l->>'price_crc')::int, (l->>'qty')::int,
             nullif(l->>'menu_item_id', '')::uuid
        from jsonb_array_elements(coalesce(p_order->'items', '[]'::jsonb)) l;
  exception
    when unique_violation then
      if not existing then raise; end if;
    when others then
      if existing and sqlerrm ~ 'order_has_lines' then other := true; else raise; end if;
  end;
  -- this sale's operator applies to this sale only
  perform set_config('canopy.operator_token', '', true);
  perform set_config('canopy.operator_claim', '', true);
  return jsonb_build_object('ok', true, 'already', existing, 'other_lines', other);
end $$;
revoke all on function public.pos_record_sale(jsonb) from public, anon;
grant execute on function public.pos_record_sale(jsonb) to authenticated;

select canopy.migration_end(8, 'settings_operators');
notify pgrst, 'reload schema';
