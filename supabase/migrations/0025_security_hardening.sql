-- =====================================================================================================
-- Canopy OS · migración 0025 · Endurecimiento de seguridad (revisión independiente antes del lanzamiento)
-- Pegar TODO en Supabase → SQL Editor → New query → Run.  Requiere: 0024.
--
-- Qué hace (cada punto viene de la revisión de seguridad; ver docs/DECISIONS.md D-022)
--   * Los libros, la planilla, el banco, las confirmaciones legales, los ajustes y las tarifas de IVA piden al dueño
--     con el código del teléfono (antes bastaba el PIN del dueño en la tableta del café). El contador siempre entra
--     con el código del teléfono. El ingreso del café nunca puede volverse el del contador.
--   * Los números de ventas (reportes, información, historial de días anteriores, IVA de ventas) piden el permiso de
--     ventas; un encargado sin ese permiso puede buscar un recibo por su número para devolverlo.
--   * Ningún monto o cantidad puede ser "NaN" ni infinito (eso dañaba los libros sin remedio).
--   * No se puede fechar nada en un mes anterior a uno ya cerrado; pagos y facturas de un mismo proveedor van de uno
--     en uno; volver a asentar un movimiento del banco después de deshacerlo crea su asiento; la planilla solo se
--     revisa y asienta si salió de las horas aprobadas; el PIN cuenta los intentos aunque lleguen juntos; el tipo de
--     cambio escrito a mano queda entre 100 y 2 000 y cerca del anterior; un inventario inicial no cambia el costo de
--     un insumo con historial; las líneas de compra recibidas no se editan; la foto de una factura solo entra en la
--     carpeta de un gasto sin foto; la tableta solo ve el efectivo de días anteriores con permiso de ventas.
-- Qué cambia para el personal: nada en la caja. El dueño entra a Contabilidad e Información con el código del
--   teléfono; un encargado necesita el permiso de ventas para ver Información.
-- Reversión: cada función vuelve a su versión anterior aplicando de nuevo su migración; no toca datos.
-- =====================================================================================================
select canopy.migration_begin(25, 'security_hardening');

-- the owner signed in with the phone code (not a PIN typed on the café tablet)
create or replace function public.owner_with_code() returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select a.kind = 'owner' from public.app_accounts a where a.user_id = auth.uid())
                  and coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2', false);
$$;
revoke all on function public.owner_with_code() from public, anon;
grant execute on function public.owner_with_code() to authenticated;

-- the accountant always signs in with the phone code
create or replace function public.account_kind()
returns text language sql stable security definer set search_path = public as $$
  select case when a.kind = 'owner' and public.mfa_ok() then 'owner'
              when a.kind = 'owner' then 'owner_needs_code'
              when a.kind = 'accountant' and coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2' then 'accountant'
              when a.kind = 'accountant' then 'accountant_needs_code'
              else a.kind end
  from public.app_accounts a where a.user_id = auth.uid();
$$;

-- the books: the owner with the phone code, or the accountant
create or replace function acct.can_read()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.owner_with_code() or public.account_kind() = 'accountant', false);
$$;

-- giving the accountant access: the owner with the phone code; never to the café login
create or replace function public.accountant_grant(p_email text, p_on boolean default true)
returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare uid uuid;
begin
  if not public.owner_with_code() then return jsonb_build_object('ok', false, 'error', 'owner_only'); end if;
  select id into uid from auth.users where lower(email) = lower(trim(p_email));
  if uid is null then return jsonb_build_object('ok', false, 'error', 'no_such_login'); end if;
  if exists (select 1 from public.app_accounts where user_id = uid and kind = 'owner') then
    return jsonb_build_object('ok', false, 'error', 'is_owner'); end if;
  -- the café tablet's login never becomes the accountant's
  if exists (select 1 from public.app_accounts where user_id = uid and kind = 'cafe') then
    return jsonb_build_object('ok', false, 'error', 'is_cafe_login'); end if;
  if coalesce(p_on, true) then
    insert into public.app_accounts (user_id, kind, label) values (uid, 'accountant', lower(trim(p_email)))
      on conflict (user_id) do update set kind = 'accountant', label = excluded.label;
  else
    delete from public.app_accounts where user_id = uid and kind = 'accountant';
  end if;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('accountant_access', null, public._owner_label(), uid::text,
            case when coalesce(p_on, true) then 'acceso de contador para ' else 'quitó el acceso de contador de ' end || lower(trim(p_email)), '{}'::jsonb);
  return jsonb_build_object('ok', true);
end $$;

-- public.setting_set: only the owner with the phone code (regulated switches and rates)
create or replace function public.setting_set(p_key text, p_value jsonb)
returns jsonb language plpgsql security definer set search_path = public, canopy as $$
declare d canopy.setting_defs; before jsonb;
begin
  if not public.owner_with_code() then return jsonb_build_object('ok', false, 'error', 'owner_only'); end if;
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

-- public.compliance_confirm: only the owner with the phone code (regulated switches and rates)
create or replace function public.compliance_confirm(p_key text, p_confirmed_by text, p_reference text, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public, canopy as $$
begin
  if not public.owner_with_code() then return jsonb_build_object('ok', false, 'error', 'owner_only'); end if;
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

-- public.tax_rate_save: only the owner with the phone code (regulated switches and rates)
create or replace function public.tax_rate_save(p_code text, p_name text, p_rate numeric, p_confirmed_by text, p_reference text,
                                                p_active boolean default true)
returns jsonb language plpgsql security definer set search_path = public as $$
declare before public.tax_rates;
begin
  if not public.owner_with_code() then return jsonb_build_object('ok', false, 'error', 'owner_only'); end if;
  if coalesce(trim(p_confirmed_by), '') = '' or coalesce(trim(p_reference), '') = '' then
    return jsonb_build_object('ok', false, 'error', 'missing_reference'); end if;
  if p_rate is null or p_rate < 0 or p_rate >= 1 or coalesce(trim(p_name), '') = '' or upper(coalesce(p_code, '')) !~ '^[A-Z0-9_]{2,16}$' then
    return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  select * into before from public.tax_rates where code = upper(p_code);
  -- a rate already used on sales is never rewritten: add a new code instead
  if before.code is not null and before.rate <> p_rate
     and exists (select 1 from public.order_items where tax_code = before.code) then
    return jsonb_build_object('ok', false, 'error', 'rate_in_use'); end if;
  insert into public.tax_rates (code, name, rate, active, confirmed_by, reference)
    values (upper(p_code), trim(p_name), p_rate, coalesce(p_active, true), trim(p_confirmed_by), trim(p_reference))
    on conflict (code) do update set name = excluded.name, rate = excluded.rate, active = excluded.active,
                                     confirmed_by = excluded.confirmed_by, reference = excluded.reference;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('tax_rate_save', null, public._owner_label(), upper(p_code), trim(p_name) || ' · ' || (p_rate * 100)::text || ' %',
            jsonb_build_object('before', to_jsonb(before), 'rate', p_rate, 'confirmed_by', trim(p_confirmed_by), 'reference', trim(p_reference)));
  return jsonb_build_object('ok', true);
end $$;

-- pay, payroll and the bank: the owner with the phone code, or the accountant
create or replace function public._pay_staff_allowed() returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(acct.can_read(), false);
$$;

-- public.timesheet_approve: the owner with the phone code
create or replace function public.timesheet_approve(p_period_id uuid)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare p public.pay_periods; n int; v_at timestamptz := clock_timestamp();
begin
  if not public.owner_with_code() then return jsonb_build_object('ok', false, 'error', 'owner_only'); end if;
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

-- public.timesheet_reopen: the owner with the phone code
create or replace function public.timesheet_reopen(p_period_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare p public.pay_periods;
begin
  if not public.owner_with_code() then return jsonb_build_object('ok', false, 'error', 'owner_only'); end if;
  if coalesce(trim(p_reason), '') = '' then return jsonb_build_object('ok', false, 'error', 'missing_reason'); end if;
  select * into p from public.pay_periods where id = p_period_id for update;
  if p.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if p.status <> 'approved' then return jsonb_build_object('ok', false, 'error', 'not_approved'); end if;
  if exists (select 1 from public.payroll_runs where period_id = p.id and status in ('posted', 'paid')) then
    return jsonb_build_object('ok', false, 'error', 'payroll_posted'); end if;
  update public.pay_periods set status = 'open' where id = p.id;
  update public.payroll_runs set status = 'draft', reviewed_by = null, reviewed_at = null where period_id = p.id;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('timesheet_reopen', null, public._owner_label(), p.id::text, trim(p_reason), jsonb_build_object('starts_on', p.starts_on, 'ends_on', p.ends_on));
  return jsonb_build_object('ok', true);
end $$;

-- payroll_prepare: the moment it was prepared, as the clock says
create or replace function public.payroll_prepare(p_period_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare p public.pay_periods; r public.payroll_runs; v_rules jsonb;
begin
  if not public._pay_staff_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  select * into p from public.pay_periods where id = p_period_id;
  if p.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if p.status = 'open' then return jsonb_build_object('ok', false, 'error', 'not_approved'); end if;
  select * into r from public.payroll_runs where period_id = p.id for update;
  if r.id is not null and r.status <> 'draft' then return jsonb_build_object('ok', false, 'error', 'not_draft'); end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.kind, x.code), '[]') into v_rules from public.payroll_rules x where x.active;
  if r.id is null then
    insert into public.payroll_runs (period_id, rules, prepared_by, prepared_at) values (p.id, v_rules, public._pay_actor(), clock_timestamp()) returning * into r;
  else
    update public.payroll_runs set rules = v_rules, prepared_by = public._pay_actor(), prepared_at = clock_timestamp() where id = r.id;
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
  insert into public.payroll_lines (run_id, staff_id, staff_name, hours, pay_kind, rate_crc, gross_crc, deductions, deductions_crc, employer, employer_crc, net_crc)
    select r.id, g.staff_id, g.name, g.hours, g.kind, g.rate, g.gross,
           coalesce((select jsonb_agg(jsonb_build_object('code', x->>'code', 'name', x->>'name', 'pct', (x->>'pct')::numeric,
                                                         'amount', round(g.gross * (x->>'pct')::numeric / 100, 2)))
                       from jsonb_array_elements(v_rules) x where x->>'kind' = 'employee' and g.gross is not null), '[]'),
           coalesce((select sum(round(g.gross * (x->>'pct')::numeric / 100, 2)) from jsonb_array_elements(v_rules) x where x->>'kind' = 'employee'), 0),
           coalesce((select jsonb_agg(jsonb_build_object('code', x->>'code', 'name', x->>'name', 'pct', (x->>'pct')::numeric,
                                                         'amount', round(g.gross * (x->>'pct')::numeric / 100, 2)))
                       from jsonb_array_elements(v_rules) x where x->>'kind' = 'employer' and g.gross is not null), '[]'),
           coalesce((select sum(round(g.gross * (x->>'pct')::numeric / 100, 2)) from jsonb_array_elements(v_rules) x where x->>'kind' = 'employer'), 0),
           null
      from g;
  update public.payroll_lines set net_crc = gross_crc - deductions_crc - other_crc where run_id = r.id and gross_crc is not null;
  return jsonb_build_object('ok', true, 'run_id', r.id);
end $$;

-- sales numbers: the owner, a manager allowed to see sales, or the accountant (a manager PIN alone is not enough)
create or replace function public._books_allowed() returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.sales_open() or acct.can_read(), false);
$$;
create or replace function public._insights_allowed() returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.sales_open() or acct.can_read(), false);
$$;

-- tax_summary: sales permission or the books
create or replace function public.tax_summary(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare by_rate jsonb; untaxed jsonb;
begin
  if not (public.sales_open() or acct.can_read()) then return jsonb_build_object('ok', false, 'error', 'locked'); end if;
  select coalesce(jsonb_agg(x order by x->>'code'), '[]'::jsonb) into by_rate from (
    select jsonb_build_object('code', i.tax_code, 'rate', i.tax_rate, 'lines', count(*),
                              'gross_crc', sum(i.price_crc * i.qty - coalesce(i.discount_alloc_crc, 0)),
                              'net_crc', sum(i.net_crc), 'tax_crc', sum(i.tax_crc)) as x
      from public.order_items i join public.orders o on o.id = i.order_id
     where o.business_date between p_from and p_to and o.voided_at is null and coalesce(o.paid, true)
       and o.part_of is null and i.tax_crc is not null
     group by i.tax_code, i.tax_rate) q;
  select jsonb_build_object('orders', count(*), 'total_crc', coalesce(sum(o.total_crc), 0)) into untaxed
    from public.orders o
   where o.business_date between p_from and p_to and o.voided_at is null and coalesce(o.paid, true) and o.part_of is null
     and o.refund_of is null and o.tax_crc is null and o.total_crc > 0;
  return jsonb_build_object('ok', true, 'from', p_from, 'to', p_to, 'by_rate', by_rate,
    'refunds_tax_crc', (select coalesce(sum(tax_crc), 0) from public.orders where refund_of is not null and voided_at is null
                          and business_date between p_from and p_to),
    'without_tax_detail', untaxed);
end $$;

-- order_search: earlier days need the sales permission; one receipt by number is enough for a refund
create or replace function public.order_search(p_from date, p_to date, p_text text default null, p_receipt bigint default null,
                                               p_amount int default null, p_method text default null, p_limit int default 50)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare q text; res jsonb;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 92 then return jsonb_build_object('ok', false, 'error', 'bad_range'); end if;
  -- earlier days are sales history: a manager's PIN (or the owner) opens them, as on the sales page
  -- a manager without sales permission may still look up one receipt by its number (to refund it)
  if p_from < public.cr_today() and not public.sales_open() and not (public.is_owner() and p_receipt is not null) then
    return jsonb_build_object('ok', false, 'error', 'locked');
  end if;
  q := nullif(trim(coalesce(p_text, '')), '');
  select coalesce(jsonb_agg(x order by (x->>'created_at') desc), '[]'::jsonb) into res from (
    select jsonb_build_object(
      'id', o.id, 'receipt_no', o.receipt_no, 'created_at', o.created_at, 'day', public._order_day(o),
      'total_crc', o.total_crc, 'payment_method', o.payment_method, 'paid', o.paid, 'status', o.status,
      'voided_at', o.voided_at, 'void_reason', o.void_reason, 'refunded_at', o.refunded_at, 'refund_of', o.refund_of,
      'guest_name', o.guest_name, 'station', o.station, 'operator_name', o.operator_name, 'pickup_number', o.pickup_number,
      'subtotal_crc', o.subtotal_crc, 'discount_crc', o.discount_crc, 'discount_reason', o.discount_reason, 'tax_crc', o.tax_crc,
      'parts_crc', o.parts_crc, 'notes', o.notes,
      'items', (select coalesce(jsonb_agg(jsonb_build_object('name', i.item_name, 'qty', i.qty, 'price', i.price_crc,
                                                             'tax_rate', i.tax_rate, 'tax', i.tax_crc) order by i.added_at, i.id), '[]'::jsonb)
                  from public.order_items i where i.order_id = o.id),
      'tender', (select jsonb_build_object('crc_in', t.crc_in, 'usd_in', t.usd_in, 'change_crc', t.change_crc, 'fx_rate', t.fx_rate)
                   from public.cash_tenders t where t.order_id = o.id),
      'parts', (select coalesce(jsonb_agg(jsonb_build_object('receipt_no', p.receipt_no, 'total_crc', p.total_crc, 'method', p.payment_method,
                                                             'at', p.created_at, 'voided', p.voided_at is not null) order by p.created_at), '[]'::jsonb)
                  from public.orders p where p.part_of = o.id),
      'can_void', o.voided_at is null and o.refunded_at is null and o.refund_of is null and o.total_crc >= 0
                  and (not coalesce(o.paid, true) or public._order_day_open(o)),
      'can_refund', o.voided_at is null and o.refunded_at is null and o.refund_of is null and o.total_crc > 0
                    and coalesce(o.paid, true) and coalesce(o.parts_crc, 0) = 0 and not public._order_day_open(o)) as x
      from public.orders o
     where o.part_of is null
       and public._order_day(o) between p_from and p_to
       and (p_receipt is null or o.receipt_no = p_receipt)
       and (p_amount is null or o.total_crc = p_amount or o.total_crc = -p_amount)
       and (p_method is null or o.payment_method = p_method)
       and (q is null or o.guest_name ilike '%' || q || '%' or o.operator_name ilike '%' || q || '%' or o.station ilike '%' || q || '%'
            or exists (select 1 from public.order_items i where i.order_id = o.id and i.item_name ilike '%' || q || '%'))
     order by o.created_at desc
     limit least(greatest(coalesce(p_limit, 50), 1), 200)) s;
  return jsonb_build_object('ok', true, 'orders', res);
end $$;

-- einvoice_list: customers' ID numbers are for the owner and the accountant only
create or replace function public.einvoice_list(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not acct.can_read() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 92 then return jsonb_build_object('ok', false, 'error', 'bad_range'); end if;
  return jsonb_build_object('ok', true, 'mode', public.setting('einvoice_mode'),
    'provider_ready', exists (select 1 from public.compliance_confirmations where key = 'einvoice_provider_ready'),
    'counts', (select coalesce(jsonb_object_agg(status, n), '{}') from (select status, count(*) as n from public.e_documents
                 where (created_at at time zone 'America/Costa_Rica')::date between p_from and p_to group by status) c),
    'documents', (select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'internal_no', d.internal_no, 'kind', d.kind, 'status', d.status,
                     'created_at', d.created_at, 'receipt_no', o.receipt_no, 'total_crc', d.total_crc, 'tax_crc', d.tax_crc, 'missing', d.missing,
                     'receiver', d.receiver, 'clave', d.clave, 'last_error', d.last_error) order by d.internal_no desc), '[]')
                    from (select * from public.e_documents where (created_at at time zone 'America/Costa_Rica')::date between p_from and p_to
                           order by internal_no desc limit 500) d
                    left join public.orders o on o.id = d.order_id),
    'products_without_cabys', (select coalesce(jsonb_agg(name order by name), '[]') from public.menu_items where available and cabys is null));
end $$;

-- einvoice_request_fe: once, for a sale of today
create or replace function public.einvoice_request_fe(p_order_id uuid, p_receiver jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare d public.e_documents; idn text; em text;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if (public.setting('einvoice_mode') #>> '{}') is distinct from 'shadow' then return jsonb_build_object('ok', false, 'error', 'einvoice_off'); end if;
  select * into d from public.e_documents where order_id = p_order_id for update;
  if d.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  -- the cashier writes it once, for a sale of today; a correction is the owner's
  if d.kind <> 'TE' or d.status not in ('pending', 'error') or public._shift_day(d.created_at) < public.cr_today() then
    return jsonb_build_object('ok', false, 'error', 'too_late'); end if;
  idn := regexp_replace(coalesce(p_receiver->>'id_number', ''), '[^0-9A-Za-z]', '', 'g');
  em := nullif(trim(coalesce(p_receiver->>'email', '')), '');
  -- the exact ID formats are checked by the provider; here only that something usable was written
  if coalesce(trim(p_receiver->>'name'), '') = '' or length(idn) not between 6 and 20
     or coalesce(p_receiver->>'id_type', '') not in ('fisica', 'juridica', 'dimex', 'nite', 'extranjero')
     or (em is not null and em !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$') then
    return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  update public.e_documents
     set kind = 'FE', updated_at = now(),
         receiver = jsonb_build_object('name', left(trim(p_receiver->>'name'), 100), 'id_type', p_receiver->>'id_type', 'id_number', idn, 'email', em)
   where id = d.id;
  return jsonb_build_object('ok', true, 'id', d.id);
end $$;

-- money and quantities are real numbers: NaN and infinity are refused in every table (checked on every new or changed row)
do $$
declare r record; cn text;
begin
  for r in select c.table_schema, c.table_name, c.column_name
             from information_schema.columns c
             join information_schema.tables t on t.table_schema = c.table_schema and t.table_name = c.table_name and t.table_type = 'BASE TABLE'
            where c.table_schema in ('public', 'acct') and c.data_type = 'numeric' and c.is_generated = 'NEVER' loop
    cn := left(r.table_name || '_' || r.column_name || '_finite', 63);
    execute format('alter table %I.%I drop constraint if exists %I', r.table_schema, r.table_name, cn);
    execute format('alter table %I.%I add constraint %I check (%I is null or abs(%I) < 1e15) not valid', r.table_schema, r.table_name, cn, r.column_name, r.column_name);
  end loop;
end $$;

-- acct.period_of: no backdating into a past month before one already closed
create or replace function acct.period_of(p_date date)
returns acct.periods language plpgsql security definer set search_path = acct, public as $$
declare p acct.periods; pid int := extract(year from p_date)::int * 100 + extract(month from p_date)::int;
begin
  -- a month that never had entries, before a month already closed or locked, is born closed: nothing is
  -- dated behind the accountant's back into the past they already reported
  insert into acct.periods (id, starts_on, ends_on, status)
    values (pid, date_trunc('month', p_date)::date, (date_trunc('month', p_date) + interval '1 month - 1 day')::date,
            case when exists (select 1 from acct.periods x where x.id > pid and x.status <> 'open') then 'closed' else 'open' end)
    on conflict (id) do nothing;
  select * into p from acct.periods where id = pid;
  return p;
end $$;

-- supplier_invoice_save: serialized per supplier
create or replace function public.supplier_invoice_save(p_invoice jsonb, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare x public.supplier_invoices; v public.vendors; net numeric; iva numeric; num text; rids uuid[]; rec numeric; eid bigint; who text; d date;
        a acct.accounts; diff_acct text;
begin
  if not public._ap_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if p_request_id is null then return jsonb_build_object('ok', false, 'error', 'bad_request'); end if;
  select * into x from public.supplier_invoices where id = p_request_id;
  if x.id is not null then return jsonb_build_object('ok', true, 'repeat', true, 'id', x.id); end if;
  select * into v from public.vendors where id = nullif(p_invoice->>'vendor_id', '')::uuid;
  if v.id is null then return jsonb_build_object('ok', false, 'error', 'no_vendor'); end if;
  perform 1 from public.vendors where id = v.id for update;     -- one invoice or payment of a supplier at a time
  num := nullif(left(trim(coalesce(p_invoice->>'number', '')), 50), '');
  net := round(nullif(p_invoice->>'net_crc', '')::numeric, 2); iva := round(coalesce(nullif(p_invoice->>'iva_crc', '')::numeric, 0), 2);
  d := nullif(p_invoice->>'date', '')::date;
  if num is null or net is null or net < 0 or iva < 0 or d is null or net + iva = 0
     or nullif(p_invoice->>'due_date', '')::date < d then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  if d > public.cr_today() then return jsonb_build_object('ok', false, 'error', 'future_date'); end if;
  if exists (select 1 from public.supplier_invoices where vendor_id = v.id and lower(number) = lower(num) and voided_at is null) then
    return jsonb_build_object('ok', false, 'error', 'duplicate_invoice'); end if;
  select coalesce(array_agg(r::uuid), '{}') into rids from jsonb_array_elements_text(coalesce(p_invoice->'receipt_ids', '[]'::jsonb)) r;
  -- the deliveries are this vendor's and not invoiced yet
  if exists (select 1 from unnest(rids) r left join public.purchase_receipts pr on pr.id = r
              where pr.id is null or pr.vendor_id is distinct from v.id or pr.invoice_id is not null) then
    return jsonb_build_object('ok', false, 'error', 'bad_receipts'); end if;
  select coalesce(sum(total_crc), 0) into rec from public.purchase_receipts where id = any(rids);
  -- with deliveries, a price difference is an inventory adjustment; without them, the invoice says what it was for
  if cardinality(rids) > 0 then diff_acct := acct.map('price_variance');
  else
    select * into a from acct.accounts where code = p_invoice->>'account';
    if a.code is null or not a.active or a.cash or a.type not in ('expense', 'asset') or not public._ap_target(a.code) then
      return jsonb_build_object('ok', false, 'error', 'bad_account'); end if;
    diff_acct := a.code;
  end if;
  who := case when acct.can_read() then acct.actor() else public._owner_label() end;
  -- the deliveries were owed at their cost already (the day's entry); the invoice adds its IVA and any price
  -- difference. An invoice equal to what was received, without IVA, has nothing more to post.
  if iva <> 0 or net <> rec then
    begin
      eid := acct.post(d, 'Factura ' || num || ' · ' || v.name, 'ap', 'supinv:' || p_request_id,
               jsonb_build_array(jsonb_build_object('account', acct.map('iva_in'), 'debit', iva),
                                 jsonb_build_object('account', diff_acct, 'debit', net - rec),
                                 jsonb_build_object('account', acct.map('ap'), 'credit', net - rec + iva, 'memo', v.name)),
               null, who);
    exception when others then
      if sqlerrm ~ 'period_closed' then return jsonb_build_object('ok', false, 'error', 'period_closed'); end if;
      raise;
    end;
  end if;
  insert into public.supplier_invoices (id, vendor_id, number, date, due_date, net_crc, iva_crc, receipt_ids, account, received_crc, entry_id, created_by)
    values (p_request_id, v.id, num, d, nullif(p_invoice->>'due_date', '')::date, net, iva, rids, case when cardinality(rids) = 0 then diff_acct end, rec, eid, who);
  update public.purchase_receipts set invoice_id = p_request_id where id = any(rids);
  return jsonb_build_object('ok', true, 'id', p_request_id, 'entry_id', eid, 'difference', net - rec);
end $$;

-- supplier_payment_save: serialized per supplier (never more than owed, even at the same moment)
create or replace function public.supplier_payment_save(p_payment jsonb, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare v public.vendors; amt numeric; left_amt numeric; src text; d date; inv record; part numeric; eid bigint; who text; owed numeric; po uuid;
begin
  if not public._ap_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if exists (select 1 from public.supplier_payments where id = p_request_id) then return jsonb_build_object('ok', true, 'repeat', true); end if;
  select * into v from public.vendors where id = nullif(p_payment->>'vendor_id', '')::uuid;
  if v.id is null then return jsonb_build_object('ok', false, 'error', 'no_vendor'); end if;
  perform 1 from public.vendors where id = v.id for update;     -- one invoice or payment of a supplier at a time
  if exists (select 1 from public.supplier_payments where id = p_request_id) then return jsonb_build_object('ok', true, 'repeat', true); end if;
  amt := round(nullif(p_payment->>'amount_crc', '')::numeric, 2); src := p_payment->>'paid_from'; d := nullif(p_payment->>'date', '')::date;
  po := nullif(p_payment->>'payout_id', '')::uuid;
  if src = 'payout' and po is not null and not exists (select 1 from public.cash_movements m where m.id = po and m.purpose = 'payout' and m.voided_at is null) then
    return jsonb_build_object('ok', false, 'error', 'bad_payout'); end if;
  if p_request_id is null or amt is null or amt <= 0 or src not in ('cash', 'petty', 'bank', 'payout') or d is null or d > public.cr_today() then
    return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  select coalesce(sum(public._invoice_open(id)), 0) into owed from public.supplier_invoices where vendor_id = v.id and voided_at is null;
  if amt > owed then return jsonb_build_object('ok', false, 'error', 'more_than_owed', 'owed', owed); end if;
  who := case when acct.can_read() then acct.actor() else public._owner_label() end;
  begin
    eid := acct.post(d, 'Pago a ' || v.name || coalesce(' · ' || nullif(trim(p_payment->>'reference'), ''), ''), 'ap', 'suppay:' || p_request_id,
             jsonb_build_array(jsonb_build_object('account', acct.map('ap'), 'debit', amt, 'memo', v.name),
                               jsonb_build_object('account', acct.map(case src when 'cash' then 'from_cash' when 'petty' then 'from_petty' when 'payout' then 'from_payout' else 'from_bank' end), 'credit', amt)),
             null, who);
  exception when others then
    if sqlerrm ~ 'period_closed' then return jsonb_build_object('ok', false, 'error', 'period_closed'); end if;
    raise;
  end;
  insert into public.supplier_payments (id, vendor_id, date, amount_crc, paid_from, reference, entry_id, created_by, payout_id)
    values (p_request_id, v.id, d, amt, src, nullif(left(trim(coalesce(p_payment->>'reference', '')), 80), ''), eid, who, case when src = 'payout' then po end);
  left_amt := amt;
  for inv in select id from public.supplier_invoices
              where vendor_id = v.id and voided_at is null and public._invoice_open(id) > 0
              order by (id::text = any(array(select jsonb_array_elements_text(coalesce(p_payment->'invoice_ids', '[]'::jsonb))))) desc, coalesce(due_date, date), date, id loop
    exit when left_amt <= 0;
    part := least(left_amt, public._invoice_open(inv.id));
    insert into public.supplier_payment_allocations (payment_id, invoice_id, amount_crc) values (p_request_id, inv.id, part);
    left_amt := left_amt - part;
  end loop;
  return jsonb_build_object('ok', true, 'entry_id', eid);
end $$;

-- supplier_invoice_void: serialized per supplier
create or replace function public.supplier_invoice_void(p_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare x public.supplier_invoices; r jsonb;
begin
  if not acct.can_read() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if coalesce(trim(p_reason), '') = '' then return jsonb_build_object('ok', false, 'error', 'missing_reason'); end if;
  select * into x from public.supplier_invoices where id = p_id for update;
  if x.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  perform 1 from public.vendors where id = x.vendor_id for update;
  if x.voided_at is not null then return jsonb_build_object('ok', false, 'error', 'already_voided'); end if;
  if public._invoice_open(x.id) <> x.total_crc then return jsonb_build_object('ok', false, 'error', 'has_payments'); end if;
  if x.entry_id is not null then
    r := public.acct_entry_reverse(x.entry_id, public.cr_today(), 'factura de proveedor anulada: ' || trim(p_reason));
    if not coalesce((r->>'ok')::boolean, false) then return r; end if;
  end if;
  update public.supplier_invoices set voided_at = now(), void_reason = left(trim(p_reason), 200), void_entry_id = (r->>'entry_id')::bigint where id = x.id;
  update public.purchase_receipts set invoice_id = null where invoice_id = x.id;
  return jsonb_build_object('ok', true);
end $$;

-- expense invoice files: uploaded only into the folder of an expense that has no file yet
create or replace function public._receipt_slot_open(p_name text) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.expenses e where e.id::text = split_part(p_name, '/', 1) and e.receipt_path is null and e.voided_at is null);
$$;
revoke all on function public._receipt_slot_open(text) from public, anon;
grant execute on function public._receipt_slot_open(text) to authenticated;
drop policy if exists "expense receipts add" on storage.objects;
create policy "expense receipts add" on storage.objects for insert to authenticated
  with check (bucket_id = 'expense-receipts' and (select public._receipts_allowed()) and public._receipt_slot_open(name));

-- bank_account_save: colón accounts only for now
create or replace function public.bank_account_save(p_account jsonb)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare a acct.accounts; v_id uuid; l4 text;
begin
  if not acct.can_read() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  select * into a from acct.accounts where code = p_account->>'gl_account';
  if a.code is null or not a.active or not a.cash then return jsonb_build_object('ok', false, 'error', 'bad_account'); end if;
  -- dollar accounts wait until their movements are valued in colones (exchange differences, A-06)
  if coalesce(p_account->>'currency', 'CRC') = 'USD' then return jsonb_build_object('ok', false, 'error', 'usd_not_supported'); end if;
  l4 := nullif(right(regexp_replace(coalesce(p_account->>'last4', ''), '[^0-9]', '', 'g'), 4), '');
  if coalesce(trim(p_account->>'name'), '') = '' or (l4 is not null and length(l4) <> 4)
     or coalesce(p_account->>'currency', 'CRC') not in ('CRC', 'USD') then
    return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  v_id := nullif(p_account->>'id', '')::uuid;
  if v_id is null then
    insert into public.bank_accounts (name, bank, currency, last4, gl_account)
      values (left(trim(p_account->>'name'), 60), nullif(left(trim(coalesce(p_account->>'bank', '')), 60), ''), coalesce(p_account->>'currency', 'CRC'), l4, a.code)
      returning bank_accounts.id into v_id;
  else
    update public.bank_accounts set name = left(trim(p_account->>'name'), 60), bank = nullif(left(trim(coalesce(p_account->>'bank', '')), 60), ''),
           last4 = l4, gl_account = a.code, active = coalesce((p_account->>'active')::boolean, active)
     where bank_accounts.id = v_id;
    if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- a ledger line is free for the bank when no statement line has it and its entry was not reversed (nor is a reversal)
create or replace function public._bank_free(p_line_id bigint) returns boolean language sql stable security definer set search_path = public as $$
  select not exists (select 1 from public.bank_lines where ledger_line_id = p_line_id)
     and not exists (select 1 from acct.lines l join acct.entries e on e.id = l.entry_id
                      where l.id = p_line_id and (e.source = 'reversal' or exists (select 1 from acct.entries r where r.reverses = e.id)));
$$;
revoke all on function public._bank_free(bigint) from public, anon, authenticated;

-- bank_post: a new entry each time (posting again after an undo works); colón accounts only
create or replace function public.bank_post(p_line_id bigint, p_parts jsonb, p_memo text)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare bl public.bank_lines; b public.bank_accounts; total numeric; lines jsonb; eid bigint; lid bigint; n int;
begin
  if not acct.can_read() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  select * into bl from public.bank_lines where id = p_line_id for update;
  if bl.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if bl.status <> 'open' then return jsonb_build_object('ok', false, 'error', 'not_open'); end if;
  select * into b from public.bank_accounts where id = bl.account_id;
  if b.currency <> 'CRC' then return jsonb_build_object('ok', false, 'error', 'usd_not_supported'); end if;
  if jsonb_typeof(p_parts) <> 'array' or jsonb_array_length(p_parts) = 0 then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  if exists (select 1 from jsonb_array_elements(p_parts) x left join acct.accounts a on a.code = x->>'account'
              where a.code is null or not a.active or a.code = b.gl_account or nullif(x->>'amount', '') is null) then
    return jsonb_build_object('ok', false, 'error', 'bad_account'); end if;
  select sum(round((x->>'amount')::numeric, 2)) into total from jsonb_array_elements(p_parts) x;
  if total <> bl.amount then return jsonb_build_object('ok', false, 'error', 'parts_differ', 'parts', total, 'amount', bl.amount); end if;
  -- the bank's line first (debit when money came in), then each part on the other side
  select jsonb_build_array(jsonb_build_object('account', b.gl_account, 'debit', bl.amount, 'memo', left(bl.description, 200)))
         || jsonb_agg(jsonb_build_object('account', x->>'account', 'debit', -round((x->>'amount')::numeric, 2), 'memo', nullif(x->>'memo', '')))
    into lines from jsonb_array_elements(p_parts) x;
  begin
    -- each posting of a line is its own entry: after an undo (a reversal) the line can be posted again
    select count(*) into n from acct.entries where source = 'bank' and (source_key = 'bank:' || bl.id or source_key like 'bank:' || bl.id || ':%');
    eid := acct.post(bl.date, coalesce(nullif(trim(p_memo), ''), 'Banco: ' || bl.description), 'bank', 'bank:' || bl.id || ':' || (n + 1), lines, null, acct.actor());
  exception when others then
    if sqlerrm ~ 'period_closed' then return jsonb_build_object('ok', false, 'error', 'period_closed'); end if;
    raise;
  end;
  select id into lid from acct.lines where entry_id = eid and account = b.gl_account order by id limit 1;
  update public.bank_lines set status = 'posted', ledger_line_id = lid, done_by = acct.actor(), done_at = now() where id = bl.id;
  return jsonb_build_object('ok', true, 'entry_id', eid);
end $$;

-- payroll_review: the accountant, on a payroll prepared from the hours as approved; no negative net pay
create or replace function public.payroll_review(p_run_id uuid)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare r public.payroll_runs;
begin
  if public.account_kind() is distinct from 'accountant' then return jsonb_build_object('ok', false, 'error', 'accountant_only'); end if;
  select * into r from public.payroll_runs where id = p_run_id for update;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if r.status <> 'draft' then return jsonb_build_object('ok', false, 'error', 'not_draft'); end if;
  -- only a payroll prepared from the hours as approved now
  if not exists (select 1 from public.pay_periods p where p.id = r.period_id and p.status = 'approved' and r.prepared_at >= p.approved_at) then
    return jsonb_build_object('ok', false, 'error', 'prepare_again'); end if;
  if exists (select 1 from public.payroll_lines where run_id = r.id and net_crc < 0) then return jsonb_build_object('ok', false, 'error', 'negative_net'); end if;
  if exists (select 1 from public.payroll_lines where run_id = r.id and gross_crc is null) then return jsonb_build_object('ok', false, 'error', 'missing_rates'); end if;
  if not exists (select 1 from public.payroll_lines where run_id = r.id) then return jsonb_build_object('ok', false, 'error', 'empty'); end if;
  update public.payroll_runs set status = 'reviewed', reviewed_by = acct.actor(), reviewed_at = now() where id = r.id;
  return jsonb_build_object('ok', true);
end $$;

-- payroll_post: only for hours still approved as prepared
create or replace function public.payroll_post(p_run_id uuid)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare r public.payroll_runs; p public.pay_periods; g numeric; e numeric; d numeric; o numeric; n numeric; eid bigint;
begin
  if not public._pay_staff_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  select * into r from public.payroll_runs where id = p_run_id for update;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if r.status <> 'reviewed' then return jsonb_build_object('ok', false, 'error', 'not_reviewed'); end if;
  select * into p from public.pay_periods where id = r.period_id;
  if p.status <> 'approved' or r.prepared_at < p.approved_at then return jsonb_build_object('ok', false, 'error', 'prepare_again'); end if;
  select sum(gross_crc), sum(employer_crc), sum(deductions_crc), sum(other_crc), sum(net_crc) into g, e, d, o, n from public.payroll_lines where run_id = r.id;
  begin
    eid := acct.post(p.ends_on, 'Planilla del ' || to_char(p.starts_on, 'DD/MM') || ' al ' || to_char(p.ends_on, 'DD/MM/YYYY'), 'payroll', 'payroll:' || r.id,
             jsonb_build_array(jsonb_build_object('account', acct.map('payroll_gross'), 'debit', g),
                               jsonb_build_object('account', acct.map('payroll_employer'), 'debit', e),
                               jsonb_build_object('account', acct.map('payroll_social'), 'credit', d + e),
                               jsonb_build_object('account', acct.map('payroll_withheld'), 'credit', o),
                               jsonb_build_object('account', acct.map('payroll_net'), 'credit', n)),
             null, public._pay_actor());
  exception when others then
    if sqlerrm ~ 'period_closed' then return jsonb_build_object('ok', false, 'error', 'period_closed'); end if;
    raise;
  end;
  update public.payroll_runs set status = 'posted', entry_id = eid where id = r.id;
  return jsonb_build_object('ok', true, 'entry_id', eid);
end $$;

-- _time_entries_period_lock: waits for an approval in progress
create or replace function public._time_entries_period_lock()
returns trigger language plpgsql security definer set search_path = public as $$
declare d date;
begin
  for d in select public._shift_day(x) from unnest(array[case when tg_op <> 'INSERT' then old.clock_in end,
                                                         case when tg_op <> 'DELETE' then new.clock_in end]) x where x is not null loop
    perform 1 from public.pay_periods p where d between p.starts_on and p.ends_on for share;   -- waits for an approval in progress
    if exists (select 1 from public.pay_periods p where d between p.starts_on and p.ends_on and p.status <> 'open') then
      raise exception 'period_locked: las horas del % ya están aprobadas', d using errcode = 'P0001';
    end if;
  end loop;
  return case when tg_op = 'DELETE' then old else new end;
end $$;

-- _verify_pin: tries are counted one by one
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

-- fx_rate_set: a rate within 100–2 000 and close to the last one
create or replace function public.fx_rate_set(p_day date, p_buy numeric, p_sell numeric)
returns jsonb language plpgsql security definer set search_path = public as $$
declare cur public.fx_rates;
begin
  if not public.is_owner() then return jsonb_build_object('ok', false, 'error', 'owner_only'); end if;
  if p_day is null or p_day > public.cr_today() + 1 or p_buy is null or p_sell is null or p_buy <= 0 or p_sell <= 0
     or p_buy > p_sell * 1.1 or p_sell > p_buy * 1.2 then
    return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  -- the same bounds as the official import; a jump of more than 5 % from the last rate needs the owner with the phone code
  if p_buy < 100 or p_sell > 2000 then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  if not public.owner_with_code() and exists (select 1 from public._fx_for(p_day - 1) f
                                                where f.rate is not null and (greatest(p_buy, p_sell) > f.sell * 1.05 or least(p_buy, p_sell) < f.buy * 0.95)) then
    return jsonb_build_object('ok', false, 'error', 'big_change'); end if;
  select * into cur from public.fx_rates where day = p_day;
  if cur.day is not null and cur.source <> 'manual' then return jsonb_build_object('ok', false, 'error', 'official_exists'); end if;
  insert into public.fx_rates (day, buy, sell, source, entered_by) values (p_day, p_buy, p_sell, 'manual', public._owner_label())
    on conflict (day) do update set buy = excluded.buy, sell = excluded.sell, fetched_at = now(), entered_by = excluded.entered_by;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('fx_rate_set', null, public._owner_label(), p_day::text, 'tipo de cambio manual ' || p_buy || ' / ' || p_sell,
            jsonb_build_object('before', to_jsonb(cur), 'buy', p_buy, 'sell', p_sell));
  return jsonb_build_object('ok', true);
end $$;

-- stock_receive: an opening balance never rewrites the cost of an item with history
create or replace function public.stock_receive(p_item_id uuid, p_qty numeric, p_unit_cost numeric default null,
                                                p_expires_on date default null, p_note text default null,
                                                p_request_id uuid default null, p_opening boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare it public.stock_items; opening boolean; first_stock boolean;
begin
  if not public.inventory_open() then return jsonb_build_object('ok', false, 'error', 'locked'); end if;
  if p_request_id is not null and exists (select 1 from public.stock_moves where request_id = p_request_id) then
    return jsonb_build_object('ok', true, 'repeat', true);
  end if;
  if coalesce(p_qty, 0) <= 0 then return jsonb_build_object('ok', false, 'error', 'bad_qty'); end if;
  if p_unit_cost is not null and p_unit_cost < 0 then return jsonb_build_object('ok', false, 'error', 'bad_cost'); end if;
  select * into it from public.stock_items where id = p_item_id;
  if it.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  -- the stock a new item starts with is an opening balance, not a purchase (older pages say 'starting stock')
  opening := coalesce(p_opening, false) or coalesce(p_note, '') = 'starting stock';
  -- an opening balance sets the average cost only for an item without any movement yet; otherwise it averages in
  first_stock := not exists (select 1 from public.stock_moves where item_id = p_item_id);
  begin
    insert into public.stock_moves (item_id, kind, qty, unit_cost, expires_on, note, by_name, request_id)
      values (p_item_id, case when opening then 'adjust' else 'purchase' end, p_qty, p_unit_cost,
              coalesce(p_expires_on, case when it.shelf_life_days is not null then current_date + it.shelf_life_days end),
              case when opening then coalesce(p_note, 'inventario inicial') else p_note end, public._inv_actor(), p_request_id);
  exception when unique_violation then
    return jsonb_build_object('ok', true, 'repeat', true);
  end;
  if p_unit_cost is not null and p_unit_cost > 0 then
    update public.stock_items set cost_per_pack = p_unit_cost * pack_qty where id = p_item_id;
    if opening and first_stock then update public.stock_items set avg_cost = round(p_unit_cost, 4) where id = p_item_id; end if;
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- purchase lines already received are history: a page cannot change them
create or replace function public._purchase_line_guard()
returns trigger language plpgsql as $$
begin
  if current_user not in ('authenticated', 'anon') then return new; end if;    -- the receiving functions (owner rights) go on
  if coalesce(old.received_qty, 0) > 0 or exists (select 1 from public.purchase_orders p where p.id = old.po_id
                                                    and p.status in ('received', 'partially_received', 'cancelled')) then
    raise exception 'purchase_line_history: esta línea ya se recibió; registre una entrega o un ajuste' using errcode = 'P0001';
  end if;
  if new.received_qty is distinct from old.received_qty then
    raise exception 'purchase_line_history: lo recibido se registra con "Recibir"' using errcode = 'P0001';
  end if;
  return new;
end $$;
drop trigger if exists purchase_line_guard on public.purchase_lines;
create trigger purchase_line_guard before update on public.purchase_lines for each row execute function public._purchase_line_guard();
-- the unit of an item is one of the units the pages know (its name is shown on several screens)
alter table public.stock_items drop constraint if exists stock_items_unit_known;
alter table public.stock_items add constraint stock_items_unit_known check (unit in ('unit', 'g', 'kg', 'ml', 'L')) not valid;

-- cash tenders: older days only with the sales permission, like the sales themselves
drop policy if exists "tenders read" on public.cash_tenders;
create policy "tenders read" on public.cash_tenders for select to authenticated
  using ((select public.is_cafe()) and (recorded_at >= public.cr_today_start() or (select public.sales_open())));

select canopy.migration_end(25, 'security_hardening');
notify pgrst, 'reload schema';
