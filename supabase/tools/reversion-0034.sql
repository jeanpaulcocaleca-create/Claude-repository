-- =====================================================================================================
-- Canopy OS · REVERSIÓN DE LA MIGRACIÓN 0034 (Contabilidad nueva, 1 de 2: lecturas, lo habitual por proveedor, gastos solo con libros)
-- Supabase → SQL Editor → New query → pegar TODO → Run. Es una sola transacción: si algo falla, no cambia nada.
-- Úsela solo si la 0034 causa un problema y así lo decide el dueño, fuera del horario de atención. Si la 0035 está
--   aplicada, revierta primero la 0035 (supabase/tools/reversion-0035.sql).
--
-- Qué hace
--   * Deja exactamente como estaban antes de la 0034: registrar gastos (expense_save de la 0019), la lista de gastos
--     (expense_list de la 0014) y la regla del depósito de facturas (_receipts_allowed de la 0015): vuelven a abrir
--     también para una tableta del café con el PIN de un encargado.
--   * Quita las funciones nuevas: vendors_list, vendor_save, vendor_defaults_save, vendor_history, purchases_list,
--     sales_by_method, cash_position, period_compare, acct_audit y las internas _expense_allowed, _expense_open,
--     _period_figures.
--   * Quita la 0034 del registro de migraciones (la base vuelve a la versión 33).
-- Qué NO hace: no quita las seis columnas nuevas de proveedores ni lo que el dueño haya escrito en ellas (quedan sin uso)
--   y no borra ninguna fila de ninguna tabla.
-- Después: contabilidad.html avisa que falta la migración 0034; accounting.html sigue igual que hoy.
-- =====================================================================================================
do $$ begin
  if not exists (select 1 from canopy.migrations where version = 34) then
    raise exception 'La migración 0034 no está aplicada: no hay nada que revertir. No se cambió nada.';
  end if;
  if exists (select 1 from canopy.migrations where version > 34) then
    raise exception 'Hay migraciones posteriores a la 0034: revierta primero esas. No se cambió nada.';
  end if;
end $$;
set local lock_timeout = '8s';

drop function if exists public.vendors_list();
drop function if exists public.vendor_save(jsonb);
drop function if exists public.vendor_defaults_save(uuid, jsonb);
drop function if exists public.vendor_history(uuid, date, date);
drop function if exists public.purchases_list(date, date, uuid);
drop function if exists public.sales_by_method(date, date);
drop function if exists public.cash_position();
drop function if exists public.period_compare(date, date);
drop function if exists public._period_figures(date, date, boolean);
drop function if exists public.acct_audit(date, date);

-- the receipts rule as in 0015
create or replace function public._receipts_allowed()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.is_owner() or acct.can_read(), false);
$$;

-- expense_save as in 0019
create or replace function public.expense_save(p_expense jsonb, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare x public.expenses; a acct.accounts; amt numeric; iva numeric; src text; inv text; vid uuid; vname text; eid bigint; who text; po uuid;
begin
  if not (public.is_owner() or acct.can_read()) then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if p_request_id is null then return jsonb_build_object('ok', false, 'error', 'bad_request'); end if;
  select * into x from public.expenses where id = p_request_id;
  if x.id is not null then return jsonb_build_object('ok', true, 'repeat', true, 'id', x.id); end if;
  amt := round(nullif(p_expense->>'amount_crc', '')::numeric, 2);
  iva := round(coalesce(nullif(p_expense->>'iva_crc', '')::numeric, 0), 2);
  src := p_expense->>'paid_from';
  inv := nullif(left(trim(coalesce(p_expense->>'invoice_no', '')), 40), '');
  vid := nullif(p_expense->>'vendor_id', '')::uuid;
  vname := nullif(left(trim(coalesce(p_expense->>'vendor_name', '')), 80), '');
  if vid is not null then select name into vname from public.vendors where id = vid; end if;
  select * into a from acct.accounts where code = p_expense->>'account';
  if a.code is null or not a.active or a.type <> 'expense' then return jsonb_build_object('ok', false, 'error', 'bad_account'); end if;
  po := nullif(p_expense->>'payout_id', '')::uuid;
  if src = 'payout' and po is not null and not exists (select 1 from public.cash_movements m where m.id = po and m.purpose = 'payout' and m.voided_at is null) then
    return jsonb_build_object('ok', false, 'error', 'bad_payout'); end if;
  if amt is null or amt <= 0 or iva < 0 or iva >= amt or src not in ('cash', 'petty', 'bank', 'credit', 'payout')
     or coalesce(trim(p_expense->>'description'), '') = '' or nullif(p_expense->>'date', '') is null then
    return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  if (p_expense->>'date')::date > public.cr_today() then return jsonb_build_object('ok', false, 'error', 'future_date'); end if;
  if inv is not null and exists (select 1 from public.expenses e where e.voided_at is null and lower(e.invoice_no) = lower(inv)
                                    and coalesce(e.vendor_id::text, lower(e.vendor_name)) = coalesce(vid::text, lower(vname))) then
    return jsonb_build_object('ok', false, 'error', 'duplicate_invoice'); end if;
  who := case when acct.can_read() then acct.actor() else public._owner_label() end;
  begin
    eid := acct.post((p_expense->>'date')::date, 'Gasto: ' || trim(p_expense->>'description') || coalesce(' · ' || vname, '') || coalesce(' · fact. ' || inv, ''),
                     'expense', 'expense:' || p_request_id,
                     jsonb_build_array(jsonb_build_object('account', a.code, 'debit', amt - iva),
                                       jsonb_build_object('account', acct.map('iva_in'), 'debit', iva),
                                       jsonb_build_object('account', acct.map(case src when 'cash' then 'from_cash' when 'petty' then 'from_petty'
                                                                                       when 'bank' then 'from_bank' when 'payout' then 'from_payout' else 'from_credit' end), 'credit', amt)),
                     null, who);
  exception when others then
    if sqlerrm ~ 'period_closed' then return jsonb_build_object('ok', false, 'error', 'period_closed'); end if;
    raise;
  end;
  insert into public.expenses (id, date, vendor_id, vendor_name, description, account, amount_crc, iva_crc, paid_from, invoice_no, invoice_date, entry_id, created_by, payout_id)
    values (p_request_id, (p_expense->>'date')::date, vid, vname, left(trim(p_expense->>'description'), 200), a.code, amt, iva, src, inv,
            nullif(p_expense->>'invoice_date', '')::date, eid, who, case when src = 'payout' then po end);
  return jsonb_build_object('ok', true, 'id', p_request_id, 'entry_id', eid);
end $$;

-- expense_list as in 0014
create or replace function public.expense_list(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public, acct as $$
begin
  if not (public.is_owner() or acct.can_read()) then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  return jsonb_build_object('ok', true, 'expenses', (
    select coalesce(jsonb_agg(to_jsonb(e) || jsonb_build_object('account_name', a.name) order by e.date desc, e.created_at desc), '[]')
      from public.expenses e join acct.accounts a on a.code = e.account where e.date between p_from and p_to),
    'accounts', (select coalesce(jsonb_agg(jsonb_build_object('code', code, 'name', name) order by code), '[]') from acct.accounts where type = 'expense' and active));
end $$;
revoke all on function public.expense_save(jsonb, uuid), public.expense_list(date, date) from public, anon;
grant execute on function public.expense_save(jsonb, uuid), public.expense_list(date, date) to authenticated;

drop function if exists public._expense_open(uuid);
drop function if exists public._expense_allowed();

delete from canopy.migrations where version = 34;
notify pgrst, 'reload schema';
select 'listo: la 0034 se revirtió; los gastos y el depósito de facturas vuelven a las reglas de antes' as resultado;
