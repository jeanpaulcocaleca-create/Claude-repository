-- =====================================================================================================
-- Canopy OS · migración 0021 · Periodos de pago, revisión y aprobación de las horas, horas aprobadas fijas
-- Pegar TODO en Supabase → SQL Editor → New query → Run.  Requiere: 0020.
--
-- Qué hace
--   * public.pay_periods: los periodos de pago que el dueño o el contador crean (fechas de inicio y fin; la
--     frecuencia la decide el negocio, el sistema no supone ninguna). No se traslapan.
--   * timesheet: las horas de cada persona en el periodo, con lo que hay que revisar: turnos sin salida,
--     turnos de más de 12 horas, turnos que se cruzan y turnos cambiados a mano (con su motivo).
--   * timesheet_approve: el dueño aprueba el periodo ya terminado y sin turnos abiertos; queda una copia de
--     las horas aprobadas de cada persona. Desde ese momento las marcas de ese periodo no se pueden agregar,
--     cambiar ni borrar (ni con PIN de encargado). timesheet_reopen: el dueño lo reabre con un motivo,
--     mientras no esté pagado.
-- Qué cambia para el personal: nada al marcar. Un turno de un periodo aprobado ya no se puede editar.
-- Reversión: drop trigger time_entries_period_lock (los periodos quedan).
-- =====================================================================================================
select canopy.migration_begin(21, 'timesheets');

create table if not exists public.pay_periods (
  id           uuid primary key default gen_random_uuid(),
  starts_on    date not null,
  ends_on      date not null,
  status       text not null default 'open' check (status in ('open', 'approved', 'paid')),
  approved_by  text,
  approved_at  timestamptz,
  created_by   text not null,
  created_at   timestamptz not null default now(),
  check (ends_on >= starts_on and ends_on - starts_on <= 62)
);
create table if not exists public.pay_period_hours (            -- what was approved, person by person
  period_id    uuid not null references public.pay_periods(id),
  staff_id     uuid not null,
  staff_name   text not null,
  hours        numeric(8,2) not null,
  shifts       int not null,
  approved_at  timestamptz not null default now(),
  primary key (period_id, staff_id, approved_at)
);
alter table public.pay_periods enable row level security;
alter table public.pay_period_hours enable row level security;
revoke all on public.pay_periods, public.pay_period_hours from anon, authenticated;

-- a shift belongs to the period of the Costa Rica day it started
create or replace function public._shift_day(p_at timestamptz) returns date language sql immutable as $$
  select (p_at at time zone 'America/Costa_Rica')::date;
$$;

create or replace function public._pay_staff_allowed() returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.is_true_owner() or acct.can_read(), false);
$$;
revoke all on function public._pay_staff_allowed() from public, anon;
grant execute on function public._pay_staff_allowed() to authenticated;

-- approved hours stay as they were approved: no punch, edit or delete reaches them, whoever asks
create or replace function public._time_entries_period_lock()
returns trigger language plpgsql security definer set search_path = public as $$
declare d date;
begin
  for d in select public._shift_day(x) from unnest(array[case when tg_op <> 'INSERT' then old.clock_in end,
                                                         case when tg_op <> 'DELETE' then new.clock_in end]) x where x is not null loop
    if exists (select 1 from public.pay_periods p where d between p.starts_on and p.ends_on and p.status <> 'open') then
      raise exception 'period_locked: las horas del % ya están aprobadas', d using errcode = 'P0001';
    end if;
  end loop;
  return case when tg_op = 'DELETE' then old else new end;
end $$;
drop trigger if exists time_entries_period_lock on public.time_entries;
create trigger time_entries_period_lock before insert or update or delete on public.time_entries
  for each row execute function public._time_entries_period_lock();

create or replace function public.pay_period_save(p_starts date, p_ends date)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare pid uuid;
begin
  if not public._pay_staff_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if p_starts is null or p_ends is null or p_ends < p_starts or p_ends - p_starts > 62 then return jsonb_build_object('ok', false, 'error', 'bad_range'); end if;
  if exists (select 1 from public.pay_periods where daterange(starts_on, ends_on, '[]') && daterange(p_starts, p_ends, '[]')) then
    return jsonb_build_object('ok', false, 'error', 'overlaps'); end if;
  insert into public.pay_periods (starts_on, ends_on, created_by)
    values (p_starts, p_ends, case when acct.can_read() and not public.is_true_owner() then acct.actor() else public._owner_label() end)
    returning id into pid;
  return jsonb_build_object('ok', true, 'id', pid);
end $$;

-- the hours of a period, person by person, with what needs a look before approving
create or replace function public.timesheet(p_period_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public, acct as $$
declare p public.pay_periods;
begin
  if not (public._pay_staff_allowed() or public.is_owner()) then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if p_period_id is null then
    return jsonb_build_object('ok', true, 'periods', (select coalesce(jsonb_agg(to_jsonb(x) order by x.starts_on desc), '[]') from public.pay_periods x));
  end if;
  select * into p from public.pay_periods where id = p_period_id;
  if p.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  return jsonb_build_object('ok', true, 'period', to_jsonb(p),
    'periods', (select coalesce(jsonb_agg(to_jsonb(x) order by x.starts_on desc), '[]') from public.pay_periods x),
    'people', (
      with t as (
        select te.*, s.name, extract(epoch from (coalesce(te.clock_out, now()) - te.clock_in)) / 3600 as h
          from public.time_entries te join public.staff s on s.id = te.staff_id
         where public._shift_day(te.clock_in) between p.starts_on and p.ends_on)
      select coalesce(jsonb_agg(x order by x->>'name'), '[]') from (
        select jsonb_build_object('staff_id', t.staff_id, 'name', min(t.name),
                 'hours', round(sum(t.h) filter (where t.clock_out is not null)::numeric, 2),
                 'shifts', count(*),
                 'open', count(*) filter (where t.clock_out is null),
                 'long', count(*) filter (where t.h > 12),
                 'overlap', (select count(*) from t a join t b on a.staff_id = b.staff_id and a.id < b.id
                              where a.staff_id = t.staff_id and tstzrange(a.clock_in, coalesce(a.clock_out, now())) && tstzrange(b.clock_in, coalesce(b.clock_out, now()))),
                 'edited', (select count(*) from public.audit_log l where l.action in ('shift_edit', 'shift_add', 'shift_delete')
                              and l.details->>'staff_id' = t.staff_id::text
                              and coalesce(public._shift_day((l.details#>>'{after,clock_in}')::timestamptz), public._shift_day((l.details#>>'{before,clock_in}')::timestamptz))
                                  between p.starts_on and p.ends_on),
                 'entries', jsonb_agg(jsonb_build_object('id', t.id, 'clock_in', t.clock_in, 'clock_out', t.clock_out, 'hours', round(t.h::numeric, 2)) order by t.clock_in)) as x
          from t group by t.staff_id) q),
    'approved', (select coalesce(jsonb_agg(to_jsonb(h) order by h.staff_name), '[]') from public.pay_period_hours h
                  where h.period_id = p.id and h.approved_at = (select max(approved_at) from public.pay_period_hours where period_id = p.id)));
end $$;

create or replace function public.timesheet_approve(p_period_id uuid)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare p public.pay_periods; n int; v_at timestamptz := now();
begin
  if not public.is_true_owner() then return jsonb_build_object('ok', false, 'error', 'owner_only'); end if;
  select * into p from public.pay_periods where id = p_period_id for update;
  if p.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if p.status <> 'open' then return jsonb_build_object('ok', false, 'error', 'not_open'); end if;
  if p.ends_on >= public.cr_today() then return jsonb_build_object('ok', false, 'error', 'not_ended'); end if;
  select count(*) into n from public.time_entries where clock_out is null and public._shift_day(clock_in) between p.starts_on and p.ends_on;
  if n > 0 then return jsonb_build_object('ok', false, 'error', 'open_shifts', 'count', n); end if;
  insert into public.pay_period_hours (period_id, staff_id, staff_name, hours, shifts, approved_at)
    select p.id, te.staff_id, s.name, round(sum(extract(epoch from (te.clock_out - te.clock_in)) / 3600)::numeric, 2), count(*), v_at
      from public.time_entries te join public.staff s on s.id = te.staff_id
     where public._shift_day(te.clock_in) between p.starts_on and p.ends_on
     group by te.staff_id, s.name;
  update public.pay_periods set status = 'approved', approved_by = public._owner_label(), approved_at = v_at where id = p.id;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('timesheet_approve', null, public._owner_label(), p.id::text, 'aprobó las horas del ' || p.starts_on || ' al ' || p.ends_on,
            jsonb_build_object('starts_on', p.starts_on, 'ends_on', p.ends_on));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.timesheet_reopen(p_period_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare p public.pay_periods;
begin
  if not public.is_true_owner() then return jsonb_build_object('ok', false, 'error', 'owner_only'); end if;
  if coalesce(trim(p_reason), '') = '' then return jsonb_build_object('ok', false, 'error', 'missing_reason'); end if;
  select * into p from public.pay_periods where id = p_period_id for update;
  if p.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if p.status <> 'approved' then return jsonb_build_object('ok', false, 'error', 'not_approved'); end if;
  -- a period whose payroll was already posted stays as it is (0022 sets this table's column)
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'payroll_runs') then
    if exists (select 1 from public.payroll_runs where period_id = p.id and status in ('posted', 'paid')) then
      return jsonb_build_object('ok', false, 'error', 'payroll_posted'); end if;
  end if;
  update public.pay_periods set status = 'open' where id = p.id;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('timesheet_reopen', null, public._owner_label(), p.id::text, trim(p_reason), jsonb_build_object('starts_on', p.starts_on, 'ends_on', p.ends_on));
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.pay_period_save(date, date), public.timesheet(uuid), public.timesheet_approve(uuid), public.timesheet_reopen(uuid, text) from public, anon;
grant execute on function public.pay_period_save(date, date), public.timesheet(uuid), public.timesheet_approve(uuid), public.timesheet_reopen(uuid, text) to authenticated;
revoke all on function public._time_entries_period_lock() from public, anon, authenticated;

select canopy.migration_end(21, 'timesheets');
notify pgrst, 'reload schema';
