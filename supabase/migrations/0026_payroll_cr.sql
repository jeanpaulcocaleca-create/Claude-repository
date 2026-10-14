-- =====================================================================================================
-- Canopy OS · migración 0026 · Planilla de Costa Rica: CCSS e INS por categoría, retención de renta, perfil
--                              laboral, pagos extra, aguinaldo, vacaciones, estimado de liquidación, reporte
--                              mensual para la CCSS y el INS, colilla de pago
-- Pegar TODO en Supabase → SQL Editor → New query → Run.  Requiere: 0025.
--
-- Qué hace
--   * Separa lo OPERATIVO (sumar horas, multiplicar por la tarifa, dividir entre 12, promediar) de lo que
--     REQUIERE VERIFICACIÓN LEGAL (porcentajes de la CCSS y del INS, tabla del impuesto sobre la renta, días de
--     vacaciones, tabla de preaviso y cesantía). Lo segundo no viene activado: el contador lo registra con su
--     nombre y el documento, y el dueño anota la confirmación «payroll_cr_rules» en Inicio → Ajustes. Hasta
--     entonces los cálculos salen marcados como estimados sin confirmar y nada se asienta.
--   * payroll_rules.category: ccss | ins | other. Las cargas del INS (póliza de riesgos del trabajo) se asientan
--     aparte (6105 contra 2133); las de la CCSS siguen como hasta hoy (6102 contra 2131).
--   * public.staff_profile: cédula o DIMEX, fecha de ingreso y de salida, tipo de contrato, hijos y cónyuge
--     (créditos del impuesto sobre la renta). Solo el dueño con el código del teléfono y el contador lo ven.
--   * public.payroll_params: la tabla de renta (tramos mensuales, créditos, método), los días de vacaciones por
--     mes y la tabla de preaviso y cesantía. Se guardan solo con quién lo confirmó y el documento. Las dos
--     últimas traen el texto de la ley como valor SIN confirmar, para los estimados.
--   * Planilla: pago extra por persona (vacaciones pagadas, bono, ajuste) con su nota; retención del impuesto
--     sobre la renta cuando el ajuste payroll_renta_withhold está encendido y hay tabla; provisión del aguinaldo
--     (1/12 del salario) cuando payroll_accrue_aguinaldo está encendido. Ambos ajustes nacen apagados y exigen la
--     confirmación. El asiento separa renta (2140), INS (2133) y CCSS (2131).
--   * Aguinaldo: estimado por persona (salarios asentados del 1 de diciembre al 30 de noviembre entre 12) y una
--     corrida especial que el contador revisa, se asienta (6103 contra 2150, descontando lo provisionado) y se paga.
--     Antes del 30 de noviembre solo se asienta con un motivo escrito (un adelanto, una salida); lo que falte se
--     prepara después como una corrida complementaria que descuenta lo ya pagado.
--   * Lo que cambia el dinero deja rastro en audit_log sin datos personales: el pago extra, otra deducción, el
--     perfil (solo qué campos cambiaron), las vacaciones y las reaperturas.
--   * Vacaciones: registro de días tomados o pagados, saldo estimado (días ganados menos tomados) y salario
--     diario promedio de las últimas 50 semanas de planillas asentadas.
--   * Estimado de liquidación: preaviso, cesantía, aguinaldo proporcional y vacaciones pendientes según el motivo
--     de salida. Solo un estimado: el contador prepara la liquidación final y la asienta en el diario.
--   * payroll_month_report: por mes, por persona, salario, días y horas, deducciones y cargas por categoría
--     (lo que piden la planilla de la CCSS y la del INS), con los que no tienen cédula registrada.
--   * payslip: la colilla de pago de una persona en una planilla.
-- Qué cambia para el personal: nada al marcar ni al cobrar. Las deducciones solo cambian cuando el contador
--   registra las reglas y el dueño anota la confirmación.
-- Reversión: drop function de las funciones nuevas y volver a crear payroll_prepare/adjust/review/post/get,
--   payroll_staff y payroll_rule_save de la 0025 y la 0022. Las tablas y los asientos quedan.
-- =====================================================================================================
select canopy.migration_begin(26, 'payroll_cr');

-- 1) accounts, mappings and the two settings (both OFF, behind the confirmation payroll_cr_rules) -------------------
insert into acct.accounts (code, name, type, cash, system) values
  ('2133', 'Póliza de riesgos del trabajo (INS) por pagar', 'liability', false, true),
  ('2150', 'Aguinaldo por pagar', 'liability', false, true),
  ('2151', 'Vacaciones por pagar', 'liability', false, true),
  ('6103', 'Aguinaldo', 'expense', false, true),
  ('6104', 'Vacaciones', 'expense', false, true),
  ('6105', 'Póliza de riesgos del trabajo (INS)', 'expense', false, true),
  ('6106', 'Preaviso y cesantía', 'expense', false, true)
on conflict (code) do nothing;
insert into acct.mappings (key, account, label) values
  ('payroll_renta', '2140', 'Retención del impuesto sobre la renta de los salarios'),
  ('payroll_ins', '2133', 'Póliza de riesgos del trabajo (INS) por pagar'),
  ('payroll_ins_expense', '6105', 'Póliza de riesgos del trabajo (INS)'),
  ('payroll_aguinaldo', '6103', 'Aguinaldo (gasto)'),
  ('payroll_aguinaldo_owed', '2150', 'Aguinaldo por pagar'),
  ('payroll_vacation', '6104', 'Vacaciones (gasto)'),
  ('payroll_vacation_owed', '2151', 'Vacaciones por pagar'),
  ('payroll_severance', '6106', 'Preaviso y cesantía')
on conflict (key) do nothing;

insert into canopy.setting_defs (key, kind, choices, default_value, guard, description) values
  ('payroll_renta_withhold', 'boolean', null, 'false', 'payroll_cr_rules',
   'Planilla: retener el impuesto sobre la renta del salario con la tabla que registró el contador (Contabilidad → Planilla). Apagado: la retención sale en cero y la planilla lo avisa.'),
  ('payroll_accrue_aguinaldo', 'boolean', null, 'false', 'payroll_cr_rules',
   'Planilla: provisionar el aguinaldo en cada planilla asentada (una doceava parte del salario, cuenta 2150), para que el gasto quede en el mes trabajado.')
on conflict (key) do update set kind = excluded.kind, choices = excluded.choices, default_value = excluded.default_value,
                                guard = excluded.guard, description = excluded.description;

-- 2) rule categories, the employee's profile, the legal parameters --------------------------------------------------
alter table public.payroll_rules add column if not exists category text not null default 'other';
alter table public.payroll_rules drop constraint if exists payroll_rules_category_check;
alter table public.payroll_rules add constraint payroll_rules_category_check check (category in ('ccss', 'ins', 'other'));

create table if not exists public.staff_profile (
  staff_id   uuid primary key references public.staff(id),
  id_number  text check (id_number is null or id_number ~ '^[0-9A-Za-z-]{6,20}$'),   -- cédula or DIMEX, as the CCSS wants it
  hired_on   date,
  ended_on   date,
  contract   text check (contract is null or contract in ('indefinido', 'plazo_fijo', 'por_horas')),
  children   int not null default 0 check (children between 0 and 20),
  spouse     boolean not null default false,
  notes      text,
  updated_by text not null,
  updated_at timestamptz not null default now(),
  check (ended_on is null or hired_on is null or ended_on >= hired_on)
);
create table if not exists public.payroll_params (
  key          text primary key check (key in ('renta', 'vacation', 'severance')),
  value        jsonb not null,
  confirmed_by text,                 -- null: the text of the law as a default, not confirmed by anyone
  reference    text,
  updated_by   text not null,
  updated_at   timestamptz not null default now()
);
-- the defaults are the law as written (Código de Trabajo, art. 28, 29 and 153): estimates only until confirmed
insert into public.payroll_params (key, value, updated_by) values
  ('vacation', '{"days_per_month": 1, "legal_basis": "Código de Trabajo art. 153: dos semanas por cada cincuenta semanas de trabajo continuo (un día por mes es la práctica usual). Verificar con el contador."}', 'sistema'),
  ('severance', '{"notice": {"3": 7, "6": 15, "12": 30}, "under_6_months_days": 7, "under_1_year_days": 14,
                  "per_year": {"1": 19.5, "2": 20, "3": 20.5, "4": 21, "5": 21.24, "6": 21.5, "7": 22, "8": 22, "9": 22, "10": 21.5, "11": 21, "12": 20.5, "13": 20},
                  "max_years": 8, "average_months": 6,
                  "legal_basis": "Código de Trabajo art. 28 (preaviso) y 29 (auxilio de cesantía): días por año según la antigüedad, máximo ocho años, sobre el salario promedio de los últimos seis meses. Verificar con el contador."}', 'sistema')
on conflict (key) do nothing;

create table if not exists public.payroll_special_runs (          -- aguinaldo (and later other once-a-year payments)
  id           uuid primary key default gen_random_uuid(),
  kind         text not null check (kind in ('aguinaldo')),
  year         int not null check (year between 2020 and 2100),
  status       text not null default 'draft' check (status in ('draft', 'reviewed', 'posted', 'paid')),
  lines        jsonb not null default '[]',
  total_crc    numeric(14,2) not null default 0,
  accrued_crc  numeric(14,2) not null default 0,
  prepared_by  text not null,
  prepared_at  timestamptz not null default now(),
  reviewed_by  text,
  reviewed_at  timestamptz,
  posted_on    date,
  note         text,                 -- why it was posted before 30 November (an advance, someone leaving)
  entry_id     bigint,
  pay_entry_id bigint
);
create unique index if not exists payroll_special_runs_open_idx on public.payroll_special_runs (kind, year) where status in ('draft', 'reviewed');
create table if not exists public.vacations (
  id          uuid primary key default gen_random_uuid(),
  staff_id    uuid not null references public.staff(id),
  from_on     date not null,
  to_on       date not null,
  days        numeric(5,2) not null check (days > 0 and days <= 60),
  kind        text not null check (kind in ('taken', 'paid_out')),
  note        text,
  created_by  text not null,
  created_at  timestamptz not null default now(),
  voided_at   timestamptz,
  void_reason text,
  check (to_on >= from_on)
);
create index if not exists vacations_staff_idx on public.vacations (staff_id, from_on);

alter table public.payroll_runs  add column if not exists params jsonb not null default '{}';
alter table public.payroll_lines add column if not exists extra_crc numeric(14,2) not null default 0;
alter table public.payroll_lines drop constraint if exists payroll_lines_extra_crc_check;
alter table public.payroll_lines add constraint payroll_lines_extra_crc_check check (extra_crc >= 0);
alter table public.payroll_lines add column if not exists extra_note text;
alter table public.payroll_lines add column if not exists renta_crc numeric(14,2) not null default 0;
alter table public.payroll_lines add column if not exists renta_detail jsonb;
alter table public.payroll_lines add column if not exists aguinaldo_accrual_crc numeric(14,2) not null default 0;

do $$
declare r record; cn text;
begin
  for r in select c.table_schema, c.table_name, c.column_name
             from information_schema.columns c
            where c.table_schema = 'public' and c.data_type = 'numeric' and c.is_generated = 'NEVER'
              and (c.table_name in ('payroll_special_runs', 'vacations') or (c.table_name = 'payroll_lines' and c.column_name in ('extra_crc', 'renta_crc', 'aguinaldo_accrual_crc'))) loop
    cn := left(r.table_name || '_' || r.column_name || '_finite', 63);
    execute format('alter table %I.%I drop constraint if exists %I', r.table_schema, r.table_name, cn);
    execute format('alter table %I.%I add constraint %I check (%I is null or abs(%I) < 1e15)', r.table_schema, r.table_name, cn, r.column_name, r.column_name);
  end loop;
end $$;

alter table public.staff_profile enable row level security;
alter table public.payroll_params enable row level security;
alter table public.payroll_special_runs enable row level security;
alter table public.vacations enable row level security;
revoke all on public.staff_profile, public.payroll_params, public.payroll_special_runs, public.vacations from anon, authenticated;

create or replace function public._payroll_cr_confirmed() returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.compliance_confirmations where key = 'payroll_cr_rules');
$$;
revoke all on function public._payroll_cr_confirmed() from public, anon, authenticated;

-- 3) profile and parameters ------------------------------------------------------------------------------------------
create or replace function public.staff_profile_set(p_staff_id uuid, p_profile jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare cur public.staff_profile; v_id text; v_hired date; v_ended date; v_contract text; v_children int; v_spouse boolean; v_notes text; changed text[] := '{}';
begin
  if not public._pay_staff_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if not exists (select 1 from public.staff where id = p_staff_id) then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if p_profile is null or jsonb_typeof(p_profile) <> 'object' then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  select * into cur from public.staff_profile where staff_id = p_staff_id;
  -- a key left out keeps what was there: the page sends every field, another caller may send one
  v_id := case when p_profile ? 'id_number' then nullif(trim(coalesce(p_profile->>'id_number', '')), '') else cur.id_number end;
  v_hired := case when p_profile ? 'hired_on' then nullif(p_profile->>'hired_on', '')::date else cur.hired_on end;
  v_ended := case when p_profile ? 'ended_on' then nullif(p_profile->>'ended_on', '')::date else cur.ended_on end;
  v_contract := case when p_profile ? 'contract' then nullif(p_profile->>'contract', '') else cur.contract end;
  v_children := case when p_profile ? 'children' then coalesce((p_profile->>'children')::int, 0) else coalesce(cur.children, 0) end;
  v_spouse := case when p_profile ? 'spouse' then coalesce((p_profile->>'spouse')::boolean, false) else coalesce(cur.spouse, false) end;
  v_notes := case when p_profile ? 'notes' then nullif(left(trim(coalesce(p_profile->>'notes', '')), 300), '') else cur.notes end;
  if v_id is not null and v_id !~ '^[0-9A-Za-z-]{6,20}$' then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  if v_contract is not null and v_contract not in ('indefinido', 'plazo_fijo', 'por_horas') then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  if v_children not between 0 and 20 then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  if v_hired is not null and v_ended is not null and v_ended < v_hired then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  if v_id is distinct from cur.id_number then changed := array_append(changed, 'id_number'); end if;
  if v_hired is distinct from cur.hired_on then changed := array_append(changed, 'hired_on'); end if;
  if v_ended is distinct from cur.ended_on then changed := array_append(changed, 'ended_on'); end if;
  if v_contract is distinct from cur.contract then changed := array_append(changed, 'contract'); end if;
  if v_children is distinct from cur.children then changed := array_append(changed, 'children'); end if;
  if v_spouse is distinct from cur.spouse then changed := array_append(changed, 'spouse'); end if;
  if v_notes is distinct from cur.notes then changed := array_append(changed, 'notes'); end if;
  insert into public.staff_profile (staff_id, id_number, hired_on, ended_on, contract, children, spouse, notes, updated_by)
    values (p_staff_id, v_id, v_hired, v_ended, v_contract, v_children, v_spouse, v_notes, public._pay_actor())
    on conflict (staff_id) do update set id_number = excluded.id_number, hired_on = excluded.hired_on, ended_on = excluded.ended_on, contract = excluded.contract,
                                        children = excluded.children, spouse = excluded.spouse, notes = excluded.notes, updated_by = excluded.updated_by, updated_at = now();
  -- the log says which fields changed and the dates that drive the balances; never the ID number, family or notes
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('staff_profile_set', null, public._pay_actor(), p_staff_id::text, 'perfil laboral: ' || coalesce(array_to_string(changed, ', '), ''),
            jsonb_build_object('changed', to_jsonb(changed), 'hired_on_before', cur.hired_on, 'hired_on', v_hired, 'ended_on_before', cur.ended_on, 'ended_on', v_ended));
  return jsonb_build_object('ok', true, 'changed', to_jsonb(changed));
end $$;

-- a number typed for the rules: a real, finite one (NaN and infinity are numeric values PostgreSQL accepts)
create or replace function public._payroll_finite(p numeric) returns boolean language sql immutable as $$
  select p is not null and p <> 'NaN'::numeric and abs(p) < 1e15;
$$;
revoke all on function public._payroll_finite(numeric) from public, anon, authenticated;

-- a legal parameter is saved only with who confirmed it and the document
create or replace function public.payroll_param_save(p_key text, p_value jsonb, p_confirmed_by text, p_reference text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare b jsonb; prev numeric := 0; n int := 0; up numeric; pc numeric; last_open boolean := false; k text; v numeric;
begin
  if not public._pay_staff_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if p_key not in ('renta', 'vacation', 'severance') or p_value is null or jsonb_typeof(p_value) <> 'object' then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  if coalesce(trim(p_confirmed_by), '') = '' or coalesce(trim(p_reference), '') = '' then return jsonb_build_object('ok', false, 'error', 'missing_reference'); end if;
  if p_key = 'renta' then
    if jsonb_typeof(p_value->'brackets') <> 'array' or jsonb_array_length(p_value->'brackets') = 0 then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
    for b in select * from jsonb_array_elements(p_value->'brackets') loop
      n := n + 1;
      if last_open then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;   -- nothing after the open-ended bracket
      up := nullif(b->>'upto', '')::numeric; pc := (b->>'pct')::numeric;
      if not public._payroll_finite(pc) or pc < 0 or pc > 50 then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
      if up is null then last_open := true;
      elsif not public._payroll_finite(up) or up <= prev then return jsonb_build_object('ok', false, 'error', 'bad_value');
      else prev := up; end if;
    end loop;
    if not last_open then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;      -- the last bracket has no upper limit
    for k in select unnest(array['credit_child', 'credit_spouse']) loop
      v := coalesce((p_value->>k)::numeric, 0);
      if not public._payroll_finite(v) or v < 0 then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
    end loop;
    if coalesce(p_value->>'method', 'prorate') not in ('prorate', 'monthly') then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  elsif p_key = 'vacation' then
    v := coalesce((p_value->>'days_per_month')::numeric, 0);
    if not public._payroll_finite(v) or v <= 0 or v > 5 then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  else
    if jsonb_typeof(p_value->'per_year') <> 'object' or jsonb_typeof(p_value->'notice') <> 'object' then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
    for v in select value::numeric from jsonb_each_text(p_value->'per_year') union all select value::numeric from jsonb_each_text(p_value->'notice')
             union all select coalesce((p_value->>'under_6_months_days')::numeric, 0) union all select coalesce((p_value->>'under_1_year_days')::numeric, 0) loop
      if not public._payroll_finite(v) or v < 0 or v > 400 then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
    end loop;
  end if;
  insert into public.payroll_params (key, value, confirmed_by, reference, updated_by)
    values (p_key, p_value, left(trim(p_confirmed_by), 80), left(trim(p_reference), 120), public._pay_actor())
    on conflict (key) do update set value = excluded.value, confirmed_by = excluded.confirmed_by, reference = excluded.reference, updated_by = excluded.updated_by, updated_at = now();
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('payroll_param_save', null, public._pay_actor(), p_key, 'confirmado por ' || trim(p_confirmed_by) || ' · ' || trim(p_reference), p_value);
  return jsonb_build_object('ok', true);
end $$;

-- payroll_rule_save: with its category (ccss | ins | other)
create or replace function public.payroll_rule_save(p_rule jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare c text := lower(trim(coalesce(p_rule->>'code', ''))); pct numeric := nullif(p_rule->>'pct', '')::numeric; cat text := coalesce(nullif(trim(p_rule->>'category'), ''), 'other');
begin
  if not public._pay_staff_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if coalesce(trim(p_rule->>'confirmed_by'), '') = '' or coalesce(trim(p_rule->>'reference'), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'missing_reference'); end if;
  if c !~ '^[a-z0-9_]{2,30}$' or coalesce(trim(p_rule->>'name'), '') = '' or p_rule->>'kind' not in ('employee', 'employer') or pct is null or pct < 0 or pct >= 50
     or cat not in ('ccss', 'ins', 'other') then
    return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  if cat = 'ins' and p_rule->>'kind' <> 'employer' then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;   -- the INS policy is the employer's
  insert into public.payroll_rules (code, name, kind, pct, active, confirmed_by, reference, category)
    values (c, left(trim(p_rule->>'name'), 80), p_rule->>'kind', pct, coalesce((p_rule->>'active')::boolean, true), left(trim(p_rule->>'confirmed_by'), 80), left(trim(p_rule->>'reference'), 120), cat)
    on conflict (code) do update set name = excluded.name, kind = excluded.kind, pct = excluded.pct, active = excluded.active, category = excluded.category,
                                     confirmed_by = excluded.confirmed_by, reference = excluded.reference, updated_at = now();
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('payroll_rule_save', null, public._pay_actor(), c, left(trim(p_rule->>'name'), 80) || ' ' || pct || ' %', p_rule);
  return jsonb_build_object('ok', true);
end $$;

-- payroll_staff: with the profiles, the parameters and the state of the Costa Rican rules
create or replace function public.payroll_staff()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public._pay_staff_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  return jsonb_build_object('ok', true,
    'staff', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'role', s.role, 'active', s.active,
                'pay', (select jsonb_build_object('kind', p.kind, 'rate_crc', p.rate_crc, 'effective_from', p.effective_from)
                          from public.staff_pay p where p.staff_id = s.id and p.effective_from <= public.cr_today() order by p.effective_from desc limit 1),
                'next', (select jsonb_build_object('kind', p.kind, 'rate_crc', p.rate_crc, 'effective_from', p.effective_from)
                          from public.staff_pay p where p.staff_id = s.id and p.effective_from > public.cr_today() order by p.effective_from limit 1),
                'profile', (select jsonb_build_object('id_number', sp.id_number, 'hired_on', sp.hired_on, 'ended_on', sp.ended_on, 'contract', sp.contract,
                                                      'children', sp.children, 'spouse', sp.spouse, 'notes', sp.notes) from public.staff_profile sp where sp.staff_id = s.id))
              order by s.active desc, s.name), '[]') from public.staff s),
    'rules', (select coalesce(jsonb_agg(to_jsonb(r) order by r.kind, r.code), '[]') from public.payroll_rules r),
    'params', (select coalesce(jsonb_object_agg(x.key, jsonb_build_object('value', x.value, 'confirmed_by', x.confirmed_by, 'reference', x.reference, 'updated_at', x.updated_at)), '{}')
                 from public.payroll_params x),
    'cr', jsonb_build_object('confirmed', public._payroll_cr_confirmed(),
                             'renta_withhold', public.setting('payroll_renta_withhold') = 'true'::jsonb,
                             'accrue_aguinaldo', public.setting('payroll_accrue_aguinaldo') = 'true'::jsonb));
end $$;

-- 4) the payroll: income tax, extra pay, categories --------------------------------------------------------------------
-- the monthly table applied to the pay of a period shorter than a month (under 28 days): the pay is taken to a month
-- (× 30 / days), the tax of that month is worked out by brackets, the credits for children and spouse are taken off, and
-- the tax comes back to the period. A period of 28 to 31 days is a month: the table applies to the pay as it is, so the
-- same monthly salary carries the same tax in February and in March. With method "monthly" nothing is ever scaled.
create or replace function public._payroll_renta(p_base numeric, p_days int, p_children int, p_spouse boolean, p_params jsonb)
returns jsonb language plpgsql immutable as $$
declare t jsonb := p_params->'renta'; st text := coalesce(p_params->>'renta_status', 'off'); method text; monthly numeric; tax numeric := 0;
        lower_b numeric := 0; upto numeric; b jsonb; credits numeric; mtax numeric; amount numeric; prorate boolean;
begin
  if st <> 'on' or t is null or p_base is null then return jsonb_build_object('status', st, 'amount', 0); end if;
  method := coalesce(t->>'method', 'prorate');
  prorate := method = 'prorate' and p_days is not null and p_days > 0 and p_days < 28;
  monthly := case when prorate then round(p_base * 30 / p_days, 2) else p_base end;
  for b in select * from jsonb_array_elements(t->'brackets') loop
    upto := nullif(b->>'upto', '')::numeric;
    if monthly > lower_b then
      tax := tax + (least(monthly, coalesce(upto, monthly)) - lower_b) * coalesce((b->>'pct')::numeric, 0) / 100;
    end if;
    if upto is not null then lower_b := upto; end if;
  end loop;
  credits := coalesce(p_children, 0) * coalesce((t->>'credit_child')::numeric, 0) + case when coalesce(p_spouse, false) then coalesce((t->>'credit_spouse')::numeric, 0) else 0 end;
  mtax := greatest(0, round(tax, 2) - credits);
  amount := case when prorate then round(mtax * p_days / 30, 2) else mtax end;
  return jsonb_build_object('status', 'on', 'method', method, 'days', p_days, 'monthly_base', monthly, 'monthly_tax', round(tax, 2), 'credits', credits,
                            'children', coalesce(p_children, 0), 'spouse', coalesce(p_spouse, false), 'amount', amount, 'valid_from', t->>'valid_from');
end $$;
revoke all on function public._payroll_renta(numeric, int, int, boolean, jsonb) from public, anon, authenticated;

-- one line worked out again from the run's snapshot of rules and parameters: deductions and charges on gross + extra
create or replace function public._payroll_line_recalc(p_run_id uuid, p_staff_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare r public.payroll_runs; l public.payroll_lines; p public.pay_periods; prof public.staff_profile; base numeric; days int; rj jsonb;
begin
  select * into r from public.payroll_runs where id = p_run_id;
  select * into l from public.payroll_lines where run_id = p_run_id and staff_id = p_staff_id;
  if r.id is null or l.run_id is null then return; end if;
  if l.gross_crc is null then
    update public.payroll_lines set deductions = '[]', deductions_crc = 0, employer = '[]', employer_crc = 0, renta_crc = 0, renta_detail = null, aguinaldo_accrual_crc = 0, net_crc = null
     where run_id = p_run_id and staff_id = p_staff_id;
    return;
  end if;
  select * into p from public.pay_periods where id = r.period_id;
  select * into prof from public.staff_profile where staff_id = p_staff_id;
  base := l.gross_crc + l.extra_crc; days := p.ends_on - p.starts_on + 1;
  rj := public._payroll_renta(base, days, coalesce(prof.children, 0), coalesce(prof.spouse, false), r.params);
  update public.payroll_lines set
    deductions = coalesce((select jsonb_agg(jsonb_build_object('code', x->>'code', 'name', x->>'name', 'pct', (x->>'pct')::numeric, 'category', coalesce(x->>'category', 'other'),
                                                               'amount', round(base * (x->>'pct')::numeric / 100, 2)) order by x->>'code')
                             from jsonb_array_elements(r.rules) x where x->>'kind' = 'employee'), '[]'),
    deductions_crc = coalesce((select sum(round(base * (x->>'pct')::numeric / 100, 2)) from jsonb_array_elements(r.rules) x where x->>'kind' = 'employee'), 0),
    employer = coalesce((select jsonb_agg(jsonb_build_object('code', x->>'code', 'name', x->>'name', 'pct', (x->>'pct')::numeric, 'category', coalesce(x->>'category', 'other'),
                                                             'amount', round(base * (x->>'pct')::numeric / 100, 2)) order by x->>'code')
                           from jsonb_array_elements(r.rules) x where x->>'kind' = 'employer'), '[]'),
    employer_crc = coalesce((select sum(round(base * (x->>'pct')::numeric / 100, 2)) from jsonb_array_elements(r.rules) x where x->>'kind' = 'employer'), 0),
    renta_crc = coalesce((rj->>'amount')::numeric, 0), renta_detail = rj,
    aguinaldo_accrual_crc = case when coalesce((r.params->>'accrue_aguinaldo')::boolean, false) then round(base / 12, 2) else 0 end
   where run_id = p_run_id and staff_id = p_staff_id;
  update public.payroll_lines set net_crc = gross_crc + extra_crc - deductions_crc - renta_crc - other_crc where run_id = p_run_id and staff_id = p_staff_id;
end $$;
revoke all on function public._payroll_line_recalc(uuid, uuid) from public, anon, authenticated;

-- the Costa Rican rules as they stand now: the snapshot a payroll is prepared with, and what the review compares it to
create or replace function public._payroll_params_now()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_renta public.payroll_params; st text;
begin
  select * into v_renta from public.payroll_params where key = 'renta';
  st := case when public.setting('payroll_renta_withhold') <> 'true'::jsonb or not public._payroll_cr_confirmed() then 'off'
             when v_renta.key is null or v_renta.confirmed_by is null then 'no_table' else 'on' end;
  return jsonb_build_object('renta_status', st, 'renta', case when st = 'on' then v_renta.value end,
                            'accrue_aguinaldo', public.setting('payroll_accrue_aguinaldo') = 'true'::jsonb and public._payroll_cr_confirmed(),
                            'cr_confirmed', public._payroll_cr_confirmed());
end $$;
revoke all on function public._payroll_params_now() from public, anon, authenticated;

-- payroll_prepare: as the 0025 (the moment it was prepared, as the clock says), plus the snapshot of the Costa Rican rules;
-- extra pay and other deductions already typed on a draft survive a new preparation
create or replace function public.payroll_prepare(p_period_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare p public.pay_periods; r public.payroll_runs; v_rules jsonb; v_params jsonb; sid uuid; keep jsonb := '[]';
begin
  if not public._pay_staff_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  select * into p from public.pay_periods where id = p_period_id;
  if p.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if p.status = 'open' then return jsonb_build_object('ok', false, 'error', 'not_approved'); end if;
  select * into r from public.payroll_runs where period_id = p.id for update;
  if r.id is not null and r.status <> 'draft' then return jsonb_build_object('ok', false, 'error', 'not_draft'); end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.kind, x.code), '[]') into v_rules from public.payroll_rules x where x.active;
  v_params := public._payroll_params_now();
  if r.id is null then
    insert into public.payroll_runs (period_id, rules, params, prepared_by, prepared_at) values (p.id, v_rules, v_params, public._pay_actor(), clock_timestamp()) returning * into r;
  else
    update public.payroll_runs set rules = v_rules, params = v_params, prepared_by = public._pay_actor(), prepared_at = clock_timestamp() where id = r.id;
    select coalesce(jsonb_agg(jsonb_build_object('staff_id', staff_id, 'extra_crc', extra_crc, 'extra_note', extra_note, 'other_crc', other_crc, 'other_note', other_note)), '[]') into keep
      from public.payroll_lines where run_id = r.id and (extra_crc > 0 or other_crc > 0);
    delete from public.payroll_lines where run_id = r.id;          -- a draft is worked out again from the approved hours
  end if;
  with h as (       -- the hours as approved (the latest approval of the period)
    select staff_id, staff_name, hours from public.pay_period_hours
     where period_id = p.id and approved_at = (select max(approved_at) from public.pay_period_hours where period_id = p.id)),
  pay as (
    select s.id as staff_id, s.name, coalesce(h.hours, 0) as hours,
           (select x from public.staff_pay x where x.staff_id = s.id and x.effective_from <= p.ends_on order by x.effective_from desc limit 1) as sp
      from public.staff s left join h on h.staff_id = s.id
     where h.staff_id is not null
        or exists (select 1 from public.staff_pay x where x.staff_id = s.id and x.kind = 'period' and x.effective_from <= p.ends_on and s.active)),
  g as (
    select staff_id, name, hours, (sp).kind as kind, (sp).rate_crc as rate,
           case when (sp).kind = 'hourly' then round(hours * (sp).rate_crc, 2) when (sp).kind = 'period' then (sp).rate_crc end as gross
      from pay)
  insert into public.payroll_lines (run_id, staff_id, staff_name, hours, pay_kind, rate_crc, gross_crc)
    select r.id, g.staff_id, g.name, g.hours, g.kind, g.rate, g.gross from g;
  update public.payroll_lines l set extra_crc = coalesce((k->>'extra_crc')::numeric, 0), extra_note = k->>'extra_note', other_crc = coalesce((k->>'other_crc')::numeric, 0), other_note = k->>'other_note'
    from jsonb_array_elements(keep) k where l.run_id = r.id and l.staff_id = (k->>'staff_id')::uuid and l.gross_crc is not null;
  for sid in select staff_id from public.payroll_lines where run_id = r.id loop perform public._payroll_line_recalc(r.id, sid); end loop;
  return jsonb_build_object('ok', true, 'run_id', r.id, 'kept', jsonb_array_length(keep));
end $$;

-- payroll_adjust: another deduction, worked out again with the rules of the run
create or replace function public.payroll_adjust(p_run_id uuid, p_staff_id uuid, p_other numeric, p_note text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare l public.payroll_lines;
begin
  if not public._pay_staff_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  perform 1 from public.payroll_runs where id = p_run_id and status = 'draft' for update;   -- serialized against the review
  if not found then return jsonb_build_object('ok', false, 'error', 'not_draft'); end if;
  select * into l from public.payroll_lines where run_id = p_run_id and staff_id = p_staff_id for update;
  if l.run_id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if p_other is null or not public._payroll_finite(p_other) or p_other < 0 or (l.gross_crc is not null and p_other > l.gross_crc + l.extra_crc - l.deductions_crc - l.renta_crc) then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  if p_other > 0 and coalesce(trim(p_note), '') = '' then return jsonb_build_object('ok', false, 'error', 'missing_reason'); end if;
  update public.payroll_lines set other_crc = round(p_other, 2), other_note = nullif(left(trim(coalesce(p_note, '')), 120), '') where run_id = p_run_id and staff_id = p_staff_id;
  perform public._payroll_line_recalc(p_run_id, p_staff_id);
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('payroll_adjust', null, public._pay_actor(), p_run_id::text, 'otra deducción ' || l.other_crc || ' → ' || round(p_other, 2),
            jsonb_build_object('staff_id', p_staff_id, 'before', l.other_crc, 'after', round(p_other, 2), 'note', nullif(left(trim(coalesce(p_note, '')), 120), '')));
  return jsonb_build_object('ok', true);
end $$;

-- extra pay in the period (vacation days paid, a bonus, an adjustment): part of the salary, so the rules and the tax apply to it
create or replace function public.payroll_extra(p_run_id uuid, p_staff_id uuid, p_extra numeric, p_note text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare l public.payroll_lines;
begin
  if not public._pay_staff_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  perform 1 from public.payroll_runs where id = p_run_id and status = 'draft' for update;   -- serialized against the review
  if not found then return jsonb_build_object('ok', false, 'error', 'not_draft'); end if;
  select * into l from public.payroll_lines where run_id = p_run_id and staff_id = p_staff_id for update;
  if l.run_id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if l.gross_crc is null then return jsonb_build_object('ok', false, 'error', 'missing_rates'); end if;
  if p_extra is null or not public._payroll_finite(p_extra) or p_extra < 0 or p_extra > 50000000 then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  if p_extra > 0 and coalesce(trim(p_note), '') = '' then return jsonb_build_object('ok', false, 'error', 'missing_reason'); end if;
  update public.payroll_lines set extra_crc = round(p_extra, 2), extra_note = nullif(left(trim(coalesce(p_note, '')), 120), '') where run_id = p_run_id and staff_id = p_staff_id;
  perform public._payroll_line_recalc(p_run_id, p_staff_id);
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('payroll_extra', null, public._pay_actor(), p_run_id::text, 'pago extra ' || l.extra_crc || ' → ' || round(p_extra, 2),
            jsonb_build_object('staff_id', p_staff_id, 'before', l.extra_crc, 'after', round(p_extra, 2), 'note', nullif(left(trim(coalesce(p_note, '')), 120), '')));
  return jsonb_build_object('ok', true);
end $$;

-- payroll_review: as the 0025, plus: with the withholding on, there has to be a confirmed tax table
create or replace function public.payroll_review(p_run_id uuid)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare r public.payroll_runs;
begin
  if public.account_kind() is distinct from 'accountant' then return jsonb_build_object('ok', false, 'error', 'accountant_only'); end if;
  select * into r from public.payroll_runs where id = p_run_id for update;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if r.status <> 'draft' then return jsonb_build_object('ok', false, 'error', 'not_draft'); end if;
  if not exists (select 1 from public.pay_periods p where p.id = r.period_id and p.status = 'approved' and r.prepared_at >= p.approved_at) then
    return jsonb_build_object('ok', false, 'error', 'prepare_again'); end if;
  if r.params->>'renta_status' = 'no_table' then return jsonb_build_object('ok', false, 'error', 'renta_table_missing'); end if;
  -- the rules, the settings or the confirmation changed since it was prepared: it is worked out again first
  if r.params is distinct from public._payroll_params_now() then return jsonb_build_object('ok', false, 'error', 'prepare_again'); end if;
  if exists (select 1 from public.payroll_lines where run_id = r.id and net_crc < 0) then return jsonb_build_object('ok', false, 'error', 'negative_net'); end if;
  if exists (select 1 from public.payroll_lines where run_id = r.id and gross_crc is null) then return jsonb_build_object('ok', false, 'error', 'missing_rates'); end if;
  if not exists (select 1 from public.payroll_lines where run_id = r.id) then return jsonb_build_object('ok', false, 'error', 'empty'); end if;
  update public.payroll_runs set status = 'reviewed', reviewed_by = acct.actor(), reviewed_at = now() where id = r.id;
  return jsonb_build_object('ok', true);
end $$;

-- payroll_post: salaries and charges against what is owed, by category: CCSS and other (2131), INS (2133), income tax (2140),
-- other deductions (2132), net pay (2130); the aguinaldo provision when it is on (6103 against 2150)
create or replace function public.payroll_post(p_run_id uuid)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare r public.payroll_runs; p public.pay_periods; g numeric; e_ccss numeric; e_ins numeric; d numeric; rt numeric; o numeric; n numeric; ag numeric; eid bigint;
begin
  if not public._pay_staff_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  select * into r from public.payroll_runs where id = p_run_id for update;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if r.status <> 'reviewed' then return jsonb_build_object('ok', false, 'error', 'not_reviewed'); end if;
  select * into p from public.pay_periods where id = r.period_id;
  if p.status <> 'approved' or r.prepared_at < p.approved_at then return jsonb_build_object('ok', false, 'error', 'prepare_again'); end if;
  select sum(gross_crc + extra_crc), sum(deductions_crc), sum(renta_crc), sum(other_crc), sum(net_crc), sum(aguinaldo_accrual_crc),
         coalesce(sum((select sum((x->>'amount')::numeric) from jsonb_array_elements(employer) x where coalesce(x->>'category', 'other') <> 'ins')), 0),
         coalesce(sum((select sum((x->>'amount')::numeric) from jsonb_array_elements(employer) x where x->>'category' = 'ins')), 0)
    into g, d, rt, o, n, ag, e_ccss, e_ins from public.payroll_lines where run_id = r.id;
  begin
    eid := acct.post(p.ends_on, 'Planilla del ' || to_char(p.starts_on, 'DD/MM') || ' al ' || to_char(p.ends_on, 'DD/MM/YYYY'), 'payroll', 'payroll:' || r.id,
             jsonb_build_array(jsonb_build_object('account', acct.map('payroll_gross'), 'debit', g),
                               jsonb_build_object('account', acct.map('payroll_employer'), 'debit', e_ccss),
                               jsonb_build_object('account', acct.map('payroll_ins_expense'), 'debit', e_ins, 'memo', 'Póliza de riesgos del trabajo'),
                               jsonb_build_object('account', acct.map('payroll_social'), 'credit', d + e_ccss),
                               jsonb_build_object('account', acct.map('payroll_ins'), 'credit', e_ins),
                               jsonb_build_object('account', acct.map('payroll_renta'), 'credit', rt, 'memo', 'Retención del impuesto sobre la renta'),
                               jsonb_build_object('account', acct.map('payroll_withheld'), 'credit', o),
                               jsonb_build_object('account', acct.map('payroll_net'), 'credit', n),
                               jsonb_build_object('account', acct.map('payroll_aguinaldo'), 'debit', ag, 'memo', 'Provisión del aguinaldo'),
                               jsonb_build_object('account', acct.map('payroll_aguinaldo_owed'), 'credit', ag)),
             null, public._pay_actor());
  exception when others then
    if sqlerrm ~ 'period_closed' then return jsonb_build_object('ok', false, 'error', 'period_closed'); end if;
    raise;
  end;
  update public.payroll_runs set status = 'posted', entry_id = eid where id = r.id;
  return jsonb_build_object('ok', true, 'entry_id', eid);
end $$;

-- payroll_get: with the new totals
create or replace function public.payroll_get(p_period_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare r public.payroll_runs;
begin
  if not public._pay_staff_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  select * into r from public.payroll_runs where period_id = p_period_id;
  if r.id is null then return jsonb_build_object('ok', true, 'run', null); end if;
  return jsonb_build_object('ok', true, 'run', to_jsonb(r),
    'lines', (select coalesce(jsonb_agg(to_jsonb(l) order by l.staff_name), '[]') from public.payroll_lines l where l.run_id = r.id),
    'totals', (select jsonb_build_object('hours', sum(hours), 'gross', sum(gross_crc), 'extra', sum(extra_crc), 'deductions', sum(deductions_crc), 'renta', sum(renta_crc),
                                         'other', sum(other_crc), 'employer', sum(employer_crc), 'accrual', sum(aguinaldo_accrual_crc), 'net', sum(net_crc))
                 from public.payroll_lines where run_id = r.id));
end $$;

-- the payslip of one person in one payroll
create or replace function public.payslip(p_run_id uuid, p_staff_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare r public.payroll_runs; p public.pay_periods; l public.payroll_lines; prof public.staff_profile;
begin
  if not public._pay_staff_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  select * into r from public.payroll_runs where id = p_run_id;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  select * into p from public.pay_periods where id = r.period_id;
  select * into l from public.payroll_lines where run_id = r.id and staff_id = p_staff_id;
  if l.run_id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  select * into prof from public.staff_profile where staff_id = p_staff_id;
  return jsonb_build_object('ok', true, 'status', r.status, 'period', jsonb_build_object('starts_on', p.starts_on, 'ends_on', p.ends_on, 'days', p.ends_on - p.starts_on + 1),
    'staff', jsonb_build_object('name', l.staff_name, 'id_number', prof.id_number, 'contract', prof.contract, 'hired_on', prof.hired_on),
    'hours', l.hours, 'pay_kind', l.pay_kind, 'rate_crc', l.rate_crc, 'gross_crc', l.gross_crc, 'extra_crc', l.extra_crc, 'extra_note', l.extra_note,
    'deductions', l.deductions, 'deductions_crc', l.deductions_crc, 'renta_crc', l.renta_crc, 'renta_detail', l.renta_detail,
    'other_crc', l.other_crc, 'other_note', l.other_note, 'net_crc', l.net_crc, 'employer', l.employer, 'employer_crc', l.employer_crc,
    'aguinaldo_accrual_crc', l.aguinaldo_accrual_crc, 'prepared_at', r.prepared_at, 'reviewed_by', r.reviewed_by, 'entry_id', r.entry_id, 'pay_entry_id', r.pay_entry_id,
    'cr_confirmed', coalesce((r.params->>'cr_confirmed')::boolean, false));
end $$;

-- 5) aguinaldo: the salaries posted from 1 December to 30 November, divided by twelve ---------------------------------
-- what is still owed per person: the window's posted salaries less what earlier posted or paid runs of the year covered
create or replace function public._aguinaldo_lines(p_year int, p_until date default null)
returns jsonb language sql stable security definer set search_path = public as $$
  with w as (select make_date(p_year - 1, 12, 1) as d0, least(make_date(p_year, 11, 30), coalesce(p_until, make_date(p_year, 11, 30))) as d1),
  x as (
    select l.staff_id, l.staff_name, sum(l.gross_crc + l.extra_crc) as salary, sum(l.aguinaldo_accrual_crc) as accrued,
           count(distinct date_trunc('month', pp.ends_on)) as months, min(pp.starts_on) as first_on, max(pp.ends_on) as last_on
      from public.payroll_lines l join public.payroll_runs r on r.id = l.run_id join public.pay_periods pp on pp.id = r.period_id, w
     where r.status in ('posted', 'paid') and pp.ends_on between w.d0 and w.d1 and l.gross_crc is not null
     group by l.staff_id, l.staff_name),
  prior as (
    select (e->>'staff_id')::uuid as staff_id, sum((e->>'salary_crc')::numeric) as salary, sum((e->>'accrued_crc')::numeric) as accrued, sum((e->>'aguinaldo_crc')::numeric) as paid
      from public.payroll_special_runs s, jsonb_array_elements(s.lines) e
     where s.kind = 'aguinaldo' and s.year = p_year and s.status in ('posted', 'paid')
     group by 1)
  select coalesce(jsonb_agg(jsonb_build_object('staff_id', x.staff_id, 'staff_name', x.staff_name, 'id_number', sp.id_number, 'salary_crc', round(x.salary - coalesce(pr.salary, 0), 2),
                                               'months', x.months, 'first_on', x.first_on, 'last_on', x.last_on,
                                               'aguinaldo_crc', round((x.salary - coalesce(pr.salary, 0)) / 12, 2), 'accrued_crc', round(x.accrued - coalesce(pr.accrued, 0), 2),
                                               'prior_salary_crc', round(coalesce(pr.salary, 0), 2), 'prior_paid_crc', round(coalesce(pr.paid, 0), 2)) order by x.staff_name), '[]')
    from x left join public.staff_profile sp on sp.staff_id = x.staff_id left join prior pr on pr.staff_id = x.staff_id
   where x.salary - coalesce(pr.salary, 0) > 0;
$$;
revoke all on function public._aguinaldo_lines(int, date) from public, anon, authenticated;

-- pay periods of the window already ended whose payroll is not posted yet: their salaries would be missing
create or replace function public._aguinaldo_pending(p_year int) returns int language sql stable security definer set search_path = public as $$
  select count(*)::int from public.pay_periods pp
   where pp.ends_on between make_date(p_year - 1, 12, 1) and least(make_date(p_year, 11, 30), public.cr_today())
     and not exists (select 1 from public.payroll_runs r where r.period_id = pp.id and r.status in ('posted', 'paid'));
$$;
revoke all on function public._aguinaldo_pending(int) from public, anon, authenticated;

create or replace function public.aguinaldo_estimate(p_year int)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare run public.payroll_special_runs;
begin
  if not public._pay_staff_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if p_year is null or p_year not between 2020 and 2100 then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  select * into run from public.payroll_special_runs where kind = 'aguinaldo' and year = p_year order by prepared_at desc limit 1;
  return jsonb_build_object('ok', true, 'year', p_year, 'from', make_date(p_year - 1, 12, 1), 'to', make_date(p_year, 11, 30), 'pay_by', make_date(p_year, 12, 20),
    'window_open', public.cr_today() < make_date(p_year, 11, 30), 'pending_payrolls', public._aguinaldo_pending(p_year),
    'confirmed', public._payroll_cr_confirmed(), 'lines', public._aguinaldo_lines(p_year), 'run', case when run.id is null then null else to_jsonb(run) end,
    'runs', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'status', s.status, 'total_crc', s.total_crc, 'posted_on', s.posted_on, 'note', s.note, 'prepared_at', s.prepared_at) order by s.prepared_at), '[]')
               from public.payroll_special_runs s where s.kind = 'aguinaldo' and s.year = p_year),
    'paid_crc', (select coalesce(sum(total_crc), 0) from public.payroll_special_runs where kind = 'aguinaldo' and year = p_year and status in ('posted', 'paid')),
    'legal_basis', 'Ley 2412: una doceava parte de los salarios ordinarios y extraordinarios devengados del 1 de diciembre al 30 de noviembre; se paga en los primeros veinte días de diciembre. Verificar con el contador.');
end $$;

-- prepared from what is still owed; a run posted earlier in the year (an advance, someone leaving) is not touched: the rest comes as a new run
create or replace function public.aguinaldo_prepare(p_year int)
returns jsonb language plpgsql security definer set search_path = public as $$
declare run public.payroll_special_runs; v_lines jsonb;
begin
  if not public._pay_staff_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if p_year is null or p_year not between 2020 and 2100 then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  select * into run from public.payroll_special_runs where kind = 'aguinaldo' and year = p_year and status in ('draft', 'reviewed') for update;
  if run.id is not null and run.status <> 'draft' then return jsonb_build_object('ok', false, 'error', 'not_draft'); end if;
  v_lines := public._aguinaldo_lines(p_year);
  if jsonb_array_length(v_lines) = 0 then return jsonb_build_object('ok', false, 'error', 'empty'); end if;
  if run.id is null then
    insert into public.payroll_special_runs (kind, year, lines, total_crc, accrued_crc, prepared_by, prepared_at)
      values ('aguinaldo', p_year, v_lines, (select coalesce(sum((x->>'aguinaldo_crc')::numeric), 0) from jsonb_array_elements(v_lines) x),
              (select coalesce(sum((x->>'accrued_crc')::numeric), 0) from jsonb_array_elements(v_lines) x), public._pay_actor(), clock_timestamp()) returning * into run;
  else
    update public.payroll_special_runs set lines = v_lines, total_crc = (select coalesce(sum((x->>'aguinaldo_crc')::numeric), 0) from jsonb_array_elements(v_lines) x),
           accrued_crc = (select coalesce(sum((x->>'accrued_crc')::numeric), 0) from jsonb_array_elements(v_lines) x), prepared_by = public._pay_actor(), prepared_at = clock_timestamp()
     where id = run.id;
  end if;
  return jsonb_build_object('ok', true, 'id', run.id);
end $$;

create or replace function public.aguinaldo_review(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare run public.payroll_special_runs;
begin
  if public.account_kind() is distinct from 'accountant' then return jsonb_build_object('ok', false, 'error', 'accountant_only'); end if;
  select * into run from public.payroll_special_runs where id = p_id for update;
  if run.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if run.status <> 'draft' then return jsonb_build_object('ok', false, 'error', 'not_draft'); end if;
  update public.payroll_special_runs set status = 'reviewed', reviewed_by = acct.actor(), reviewed_at = now() where id = run.id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.aguinaldo_reopen(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public._pay_staff_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  update public.payroll_special_runs set status = 'draft', reviewed_by = null, reviewed_at = null where id = p_id and status = 'reviewed';
  if not found then return jsonb_build_object('ok', false, 'error', 'not_reviewed'); end if;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('aguinaldo_reopen', null, public._pay_actor(), p_id::text, 'aguinaldo vuelto a borrador', '{}');
  return jsonb_build_object('ok', true);
end $$;

-- posted only once the Costa Rican rules are confirmed: the expense not yet provisioned, against what is owed;
-- before 30 November only with a written reason (an advance, someone leaving), kept on the run
create or replace function public.aguinaldo_post(p_id uuid, p_date date, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare run public.payroll_special_runs; eid bigint; rest numeric;
begin
  if not public._pay_staff_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if not public._payroll_cr_confirmed() then return jsonb_build_object('ok', false, 'error', 'needs_confirmation', 'guard', 'payroll_cr_rules'); end if;
  select * into run from public.payroll_special_runs where id = p_id for update;
  if run.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if run.status <> 'reviewed' then return jsonb_build_object('ok', false, 'error', 'not_reviewed'); end if;
  if p_date is null or p_date > public.cr_today() then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  if public.cr_today() < make_date(run.year, 11, 30) and coalesce(trim(p_note), '') = '' then return jsonb_build_object('ok', false, 'error', 'too_early'); end if;
  if public._aguinaldo_pending(run.year) > 0 then return jsonb_build_object('ok', false, 'error', 'pending_payrolls', 'pending', public._aguinaldo_pending(run.year)); end if;
  rest := run.total_crc - run.accrued_crc;          -- what the monthly provisions did not cover (nothing to post when they covered it all)
  if rest <> 0 then
    begin
      eid := acct.post(p_date, 'Aguinaldo ' || run.year || case when run.note is not null or coalesce(trim(p_note), '') <> '' then ' · ' || left(trim(coalesce(p_note, run.note)), 80) else '' end, 'payroll', 'aguinaldo:' || run.id,
               jsonb_build_array(jsonb_build_object('account', acct.map('payroll_aguinaldo'), 'debit', rest, 'memo', case when run.accrued_crc > 0 then 'Lo no provisionado' end),
                                 jsonb_build_object('account', acct.map('payroll_aguinaldo_owed'), 'credit', rest)),
               null, public._pay_actor());
    exception when others then
      if sqlerrm ~ 'period_closed' then return jsonb_build_object('ok', false, 'error', 'period_closed'); end if;
      raise;
    end;
  end if;
  update public.payroll_special_runs set status = 'posted', entry_id = eid, posted_on = p_date, note = coalesce(nullif(left(trim(coalesce(p_note, '')), 200), ''), note) where id = run.id;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('aguinaldo_post', null, public._pay_actor(), run.id::text, 'aguinaldo ' || run.year || ' asentado' || case when coalesce(trim(p_note), '') <> '' then ': ' || left(trim(p_note), 120) else '' end,
            jsonb_build_object('year', run.year, 'total_crc', run.total_crc, 'accrued_crc', run.accrued_crc, 'entry_id', eid, 'early', public.cr_today() < make_date(run.year, 11, 30)));
  return jsonb_build_object('ok', true, 'entry_id', eid);
end $$;

create or replace function public.aguinaldo_pay(p_id uuid, p_paid_from text, p_date date)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare run public.payroll_special_runs; eid bigint;
begin
  if not public._pay_staff_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  select * into run from public.payroll_special_runs where id = p_id for update;
  if run.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if run.status <> 'posted' then return jsonb_build_object('ok', false, 'error', 'not_posted'); end if;
  if p_paid_from not in ('bank', 'cash', 'petty') or p_date is null or p_date > public.cr_today() or p_date < run.posted_on then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  begin
    eid := acct.post(p_date, 'Pago del aguinaldo ' || run.year, 'payroll', 'aguinaldo-pay:' || run.id,
             jsonb_build_array(jsonb_build_object('account', acct.map('payroll_aguinaldo_owed'), 'debit', run.total_crc),
                               jsonb_build_object('account', acct.map(case p_paid_from when 'bank' then 'from_bank' when 'cash' then 'from_cash' else 'from_petty' end), 'credit', run.total_crc)),
             null, public._pay_actor());
  exception when others then
    if sqlerrm ~ 'period_closed' then return jsonb_build_object('ok', false, 'error', 'period_closed'); end if;
    raise;
  end;
  update public.payroll_special_runs set status = 'paid', pay_entry_id = eid where id = run.id;
  return jsonb_build_object('ok', true, 'entry_id', eid);
end $$;

-- 6) vacations: days taken or paid, the estimated balance, the average daily pay ---------------------------------------
-- average daily pay: the salaries of the payrolls posted in the window, divided by the days those periods cover
create or replace function public._avg_daily_pay(p_staff_id uuid, p_from date, p_to date)
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('salary_crc', round(coalesce(sum(l.gross_crc + l.extra_crc), 0), 2), 'days', coalesce(sum(pp.ends_on - pp.starts_on + 1), 0),
                            'daily_crc', case when coalesce(sum(pp.ends_on - pp.starts_on + 1), 0) > 0 then round(sum(l.gross_crc + l.extra_crc) / sum(pp.ends_on - pp.starts_on + 1), 2) end,
                            'from', p_from, 'to', p_to)
    from public.payroll_lines l join public.payroll_runs r on r.id = l.run_id join public.pay_periods pp on pp.id = r.period_id
   where l.staff_id = p_staff_id and r.status in ('posted', 'paid') and l.gross_crc is not null and pp.ends_on between p_from and p_to;
$$;
revoke all on function public._avg_daily_pay(uuid, date, date) from public, anon, authenticated;

-- when the person started: the profile's hire date, else the first payroll or the first punch
create or replace function public._staff_started_on(p_staff_id uuid)
returns date language sql stable security definer set search_path = public as $$
  select coalesce((select hired_on from public.staff_profile where staff_id = p_staff_id),
                  (select min(pp.starts_on) from public.payroll_lines l join public.payroll_runs r on r.id = l.run_id join public.pay_periods pp on pp.id = r.period_id
                    where l.staff_id = p_staff_id and r.status in ('posted', 'paid')),
                  (select min(public._shift_day(clock_in)) from public.time_entries where staff_id = p_staff_id));
$$;
revoke all on function public._staff_started_on(uuid) from public, anon, authenticated;

create or replace function public.vacation_record(p_staff_id uuid, p_from date, p_to date, p_days numeric, p_kind text, p_note text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare vid uuid;
begin
  if not public._pay_staff_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if not exists (select 1 from public.staff where id = p_staff_id) then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if p_from is null or p_to is null or p_to < p_from or p_days is null or p_days <= 0 or p_days > 60 or p_kind not in ('taken', 'paid_out') then
    return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  insert into public.vacations (staff_id, from_on, to_on, days, kind, note, created_by)
    values (p_staff_id, p_from, p_to, round(p_days, 2), p_kind, nullif(left(trim(coalesce(p_note, '')), 200), ''), public._pay_actor()) returning id into vid;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('vacation_record', null, public._pay_actor(), p_staff_id::text, p_days || ' días ' || p_kind, jsonb_build_object('id', vid, 'from', p_from, 'to', p_to, 'days', round(p_days, 2), 'kind', p_kind));
  return jsonb_build_object('ok', true, 'id', vid);
end $$;

-- a record is never deleted: it is voided with a reason, and the balance ignores it
create or replace function public.vacation_void(p_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public._pay_staff_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if coalesce(trim(p_reason), '') = '' then return jsonb_build_object('ok', false, 'error', 'missing_reason'); end if;
  update public.vacations set voided_at = now(), void_reason = left(trim(p_reason), 200) where id = p_id and voided_at is null;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('vacation_void', null, public._pay_actor(), p_id::text, 'registro de vacaciones anulado', '{}');
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.vacation_balance(p_staff_id uuid, p_as_of date default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare asof date := coalesce(p_as_of, public.cr_today()); started date; months int; par public.payroll_params; dpm numeric; earned numeric; taken numeric; avg jsonb; ended date;
begin
  if not public._pay_staff_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if not exists (select 1 from public.staff where id = p_staff_id) then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  select * into par from public.payroll_params where key = 'vacation';
  dpm := coalesce((par.value->>'days_per_month')::numeric, 1);
  started := public._staff_started_on(p_staff_id);
  select ended_on into ended from public.staff_profile where staff_id = p_staff_id;
  if started is null then months := 0;
  else months := greatest(0, (extract(year from age(least(asof, coalesce(ended, asof)), started)) * 12 + extract(month from age(least(asof, coalesce(ended, asof)), started)))::int); end if;
  earned := round(months * dpm, 2);
  select coalesce(sum(days), 0) into taken from public.vacations where staff_id = p_staff_id and voided_at is null and from_on <= asof;
  avg := public._avg_daily_pay(p_staff_id, asof - 350, asof);
  return jsonb_build_object('ok', true, 'as_of', asof, 'started_on', started, 'months', months, 'days_per_month', dpm, 'earned_days', earned, 'taken_days', taken,
    'remaining_days', earned - taken, 'daily_crc', avg->'daily_crc', 'value_crc', case when (avg->>'daily_crc') is not null then round((earned - taken) * (avg->>'daily_crc')::numeric, 2) end,
    'average', avg, 'confirmed', par.confirmed_by is not null and public._payroll_cr_confirmed(), 'legal_basis', par.value->>'legal_basis',
    'records', (select coalesce(jsonb_agg(to_jsonb(v) order by v.from_on desc), '[]') from public.vacations v where v.staff_id = p_staff_id));
end $$;

-- 7) the estimate of a settlement when someone leaves ------------------------------------------------------------------
create or replace function public.severance_estimate(p_staff_id uuid, p_end_on date, p_reason text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare started date; months int; years_r int; par public.payroll_params; avg jsonb; daily numeric; notice_days numeric := 0; sev_days numeric := 0; per_year numeric;
        vac jsonb; agui numeric; owes_severance boolean; items jsonb := '[]'; agui_salary numeric;
begin
  if not public._pay_staff_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if not exists (select 1 from public.staff where id = p_staff_id) then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if p_end_on is null or p_reason not in ('despido_sin_causa', 'despido_con_causa', 'renuncia', 'fin_contrato') then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  select * into par from public.payroll_params where key = 'severance';
  started := public._staff_started_on(p_staff_id);
  months := case when started is null or started > p_end_on then 0 else (extract(year from age(p_end_on, started)) * 12 + extract(month from age(p_end_on, started)))::int end;
  avg := public._avg_daily_pay(p_staff_id, p_end_on - (coalesce((par.value->>'average_months')::int, 6) * 30), p_end_on);
  daily := (avg->>'daily_crc')::numeric;
  owes_severance := p_reason = 'despido_sin_causa';
  if owes_severance then
    notice_days := case when months < 3 then 0 when months < 6 then coalesce((par.value->'notice'->>'3')::numeric, 7)
                        when months < 12 then coalesce((par.value->'notice'->>'6')::numeric, 15) else coalesce((par.value->'notice'->>'12')::numeric, 30) end;
    if months < 3 then sev_days := 0;
    elsif months < 6 then sev_days := coalesce((par.value->>'under_6_months_days')::numeric, 7);
    elsif months < 12 then sev_days := coalesce((par.value->>'under_1_year_days')::numeric, 14);
    else
      years_r := months / 12 + case when months % 12 > 6 then 1 else 0 end;
      per_year := coalesce((par.value->'per_year'->>least(years_r, 13)::text)::numeric, 20);
      sev_days := round(per_year * least(years_r, coalesce((par.value->>'max_years')::int, 8)), 2);
    end if;
  end if;
  vac := public.vacation_balance(p_staff_id, p_end_on);
  select coalesce(sum(l.gross_crc + l.extra_crc), 0) into agui_salary
    from public.payroll_lines l join public.payroll_runs r on r.id = l.run_id join public.pay_periods pp on pp.id = r.period_id
   where l.staff_id = p_staff_id and r.status in ('posted', 'paid') and l.gross_crc is not null
     and pp.ends_on between make_date(extract(year from p_end_on)::int - case when extract(month from p_end_on) = 12 then 0 else 1 end, 12, 1) and p_end_on;
  agui := round(agui_salary / 12, 2);
  items := jsonb_build_array(
    jsonb_build_object('key', 'preaviso', 'days', notice_days, 'amount_crc', case when daily is not null then round(notice_days * daily, 2) end, 'applies', owes_severance,
                       'basis', 'Código de Trabajo art. 28: una semana (3 a 6 meses), quince días (6 meses a 1 año) o un mes (más de un año), si el patrono no lo da trabajado.'),
    jsonb_build_object('key', 'cesantia', 'days', sev_days, 'amount_crc', case when daily is not null then round(sev_days * daily, 2) end, 'applies', owes_severance,
                       'basis', 'Código de Trabajo art. 29: días por año según la antigüedad (máximo ocho años) sobre el promedio de los últimos seis meses; solo en despido sin causa.'),
    jsonb_build_object('key', 'aguinaldo', 'days', null, 'amount_crc', agui, 'applies', true, 'basis', 'Ley 2412: salarios desde el 1 de diciembre anterior entre doce; siempre se paga.'),
    jsonb_build_object('key', 'vacaciones', 'days', vac->'remaining_days', 'amount_crc', vac->'value_crc', 'applies', true, 'basis', 'Código de Trabajo art. 156: las vacaciones no disfrutadas se pagan; siempre se pagan.'));
  return jsonb_build_object('ok', true, 'staff_id', p_staff_id, 'end_on', p_end_on, 'reason', p_reason, 'started_on', started, 'months', months, 'average', avg, 'daily_crc', daily,
    'items', items, 'total_crc', (select sum((x->>'amount_crc')::numeric) from jsonb_array_elements(items) x where (x->>'applies')::boolean),
    'confirmed', par.confirmed_by is not null and public._payroll_cr_confirmed(), 'legal_basis', par.value->>'legal_basis',
    'note', 'Estimado para conversar con el contador: la liquidación final la prepara el contador y se asienta en el diario (cuentas 6106, 6103, 6104).');
end $$;

-- 8) the month for the CCSS and the INS: salaries, days, hours, deductions and charges by category ---------------------
create or replace function public.payroll_month_report(p_year int, p_month int)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare d0 date; d1 date;
begin
  if not public._pay_staff_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if p_year is null or p_month is null or p_year not between 2020 and 2100 or p_month not between 1 and 12 then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  d0 := make_date(p_year, p_month, 1); d1 := (d0 + interval '1 month' - interval '1 day')::date;
  return jsonb_build_object('ok', true, 'year', p_year, 'month', p_month, 'from', d0, 'to', d1, 'confirmed', public._payroll_cr_confirmed(),
    'people', (
      with x as (
        select l.staff_id, l.staff_name, sum(l.hours) as hours, sum(l.gross_crc + l.extra_crc) as salary, sum(l.extra_crc) as extra, sum(l.renta_crc) as renta,
               sum(l.other_crc) as other, sum(l.net_crc) as net, count(*) as payrolls,
               coalesce(sum((select sum((e->>'amount')::numeric) from jsonb_array_elements(l.deductions) e where coalesce(e->>'category', 'other') = 'ccss')), 0) as emp_ccss,
               coalesce(sum((select sum((e->>'amount')::numeric) from jsonb_array_elements(l.deductions) e where coalesce(e->>'category', 'other') <> 'ccss')), 0) as emp_other,
               coalesce(sum((select sum((e->>'amount')::numeric) from jsonb_array_elements(l.employer) e where coalesce(e->>'category', 'other') = 'ccss')), 0) as er_ccss,
               coalesce(sum((select sum((e->>'amount')::numeric) from jsonb_array_elements(l.employer) e where e->>'category' = 'ins')), 0) as er_ins,
               coalesce(sum((select sum((e->>'amount')::numeric) from jsonb_array_elements(l.employer) e where coalesce(e->>'category', 'other') = 'other')), 0) as er_other
          from public.payroll_lines l join public.payroll_runs r on r.id = l.run_id join public.pay_periods pp on pp.id = r.period_id
         where r.status in ('posted', 'paid') and pp.ends_on between d0 and d1 and l.gross_crc is not null
         group by l.staff_id, l.staff_name)
      select coalesce(jsonb_agg(jsonb_build_object('staff_id', x.staff_id, 'staff_name', x.staff_name, 'id_number', sp.id_number, 'payrolls', x.payrolls, 'hours', x.hours,
               'days_worked', (select count(distinct public._shift_day(te.clock_in)) from public.time_entries te where te.staff_id = x.staff_id and public._shift_day(te.clock_in) between d0 and d1 and te.clock_out is not null),
               'salary_crc', round(x.salary, 2), 'extra_crc', round(x.extra, 2), 'employee_ccss_crc', round(x.emp_ccss, 2), 'employee_other_crc', round(x.emp_other, 2), 'renta_crc', round(x.renta, 2),
               'other_crc', round(x.other, 2), 'net_crc', round(x.net, 2), 'employer_ccss_crc', round(x.er_ccss, 2), 'employer_ins_crc', round(x.er_ins, 2), 'employer_other_crc', round(x.er_other, 2))
               order by x.staff_name), '[]')
        from x left join public.staff_profile sp on sp.staff_id = x.staff_id),
    'rules', (            -- each rule's total in the month, as the payrolls applied it
      select coalesce(jsonb_agg(jsonb_build_object('code', code, 'name', name, 'kind', kind, 'category', category, 'pct', pct, 'amount_crc', round(amount, 2)) order by kind, code), '[]') from (
        select e->>'code' as code, e->>'name' as name, 'employee' as kind, coalesce(e->>'category', 'other') as category, (e->>'pct')::numeric as pct, sum((e->>'amount')::numeric) as amount
          from public.payroll_lines l join public.payroll_runs r on r.id = l.run_id join public.pay_periods pp on pp.id = r.period_id, jsonb_array_elements(l.deductions) e
         where r.status in ('posted', 'paid') and pp.ends_on between d0 and d1 group by 1, 2, 3, 4, 5
        union all
        select e->>'code', e->>'name', 'employer', coalesce(e->>'category', 'other'), (e->>'pct')::numeric, sum((e->>'amount')::numeric)
          from public.payroll_lines l join public.payroll_runs r on r.id = l.run_id join public.pay_periods pp on pp.id = r.period_id, jsonb_array_elements(l.employer) e
         where r.status in ('posted', 'paid') and pp.ends_on between d0 and d1 group by 1, 2, 3, 4, 5) q),
    'pending_runs', (select count(*) from public.payroll_runs r join public.pay_periods pp on pp.id = r.period_id where r.status in ('draft', 'reviewed') and pp.ends_on between d0 and d1),
    'periods_without_payroll', (select count(*) from public.pay_periods pp where pp.ends_on between d0 and d1 and not exists (select 1 from public.payroll_runs r where r.period_id = pp.id)));
end $$;

revoke all on function public.staff_profile_set(uuid, jsonb), public.payroll_param_save(text, jsonb, text, text), public.payroll_rule_save(jsonb), public.payroll_staff(),
                       public.payroll_prepare(uuid), public.payroll_adjust(uuid, uuid, numeric, text), public.payroll_extra(uuid, uuid, numeric, text), public.payroll_review(uuid),
                       public.payroll_post(uuid), public.payroll_get(uuid), public.payslip(uuid, uuid), public.aguinaldo_estimate(int), public.aguinaldo_prepare(int),
                       public.aguinaldo_review(uuid), public.aguinaldo_reopen(uuid), public.aguinaldo_post(uuid, date, text), public.aguinaldo_pay(uuid, text, date),
                       public.vacation_record(uuid, date, date, numeric, text, text), public.vacation_void(uuid, text), public.vacation_balance(uuid, date),
                       public.severance_estimate(uuid, date, text), public.payroll_month_report(int, int) from public, anon;
grant execute on function public.staff_profile_set(uuid, jsonb), public.payroll_param_save(text, jsonb, text, text), public.payroll_rule_save(jsonb), public.payroll_staff(),
                          public.payroll_prepare(uuid), public.payroll_adjust(uuid, uuid, numeric, text), public.payroll_extra(uuid, uuid, numeric, text), public.payroll_review(uuid),
                          public.payroll_post(uuid), public.payroll_get(uuid), public.payslip(uuid, uuid), public.aguinaldo_estimate(int), public.aguinaldo_prepare(int),
                          public.aguinaldo_review(uuid), public.aguinaldo_reopen(uuid), public.aguinaldo_post(uuid, date, text), public.aguinaldo_pay(uuid, text, date),
                          public.vacation_record(uuid, date, date, numeric, text, text), public.vacation_void(uuid, text), public.vacation_balance(uuid, date),
                          public.severance_estimate(uuid, date, text), public.payroll_month_report(int, int) to authenticated;

select canopy.migration_end(26, 'payroll_cr');
notify pgrst, 'reload schema';
