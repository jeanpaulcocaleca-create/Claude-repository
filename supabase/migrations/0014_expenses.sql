-- =====================================================================================================
-- Canopy OS · migración 0014 · Gastos (con IVA crédito fiscal) asentados en el libro diario
-- Pegar TODO en Supabase → SQL Editor → New query → Run.  Requiere: 0013.
--
-- Qué hace
--   * public.expenses: cada gasto con fecha, proveedor, descripción, cuenta de gasto, total pagado, IVA
--     acreditable, de dónde salió el dinero (caja, caja chica, banco, o a crédito) y la factura.
--   * Al guardarlo se asienta: gasto (sin IVA) + IVA crédito fiscal contra caja, banco o cuentas por pagar.
--     Repetir el envío no lo duplica; la misma factura del mismo proveedor no se registra dos veces.
--   * Anular un gasto registra su reversión (nada se borra).
--   * Lo registran el dueño, un encargado con PIN o el contador; lo anulan el dueño o el contador.
-- Qué cambia para el personal: nada en la caja.
-- Reversión: drop function expense_save, expense_void (la tabla y los asientos quedan).
-- =====================================================================================================
select canopy.migration_begin(14, 'expenses');

insert into acct.mappings (key, account, label) values
  ('from_cash', '1101', 'Gasto pagado de la caja'),
  ('from_petty', '1103', 'Gasto pagado de caja chica'),
  ('from_bank', '1110', 'Gasto pagado por banco o tarjeta de la empresa'),
  ('from_credit', '2101', 'Gasto a crédito (cuentas por pagar)')
on conflict (key) do nothing;

create table if not exists public.expenses (
  id           uuid primary key,                       -- the page's request id
  date         date not null,
  vendor_id    uuid references public.vendors(id),
  vendor_name  text,
  description  text not null,
  account      text not null,
  amount_crc   numeric(14,2) not null check (amount_crc > 0),   -- what was paid, IVA included
  iva_crc      numeric(14,2) not null default 0 check (iva_crc >= 0),
  paid_from    text not null check (paid_from in ('cash', 'petty', 'bank', 'credit')),
  invoice_no   text,
  invoice_date date,
  entry_id     bigint,
  void_entry_id bigint,
  voided_at    timestamptz,
  void_reason  text,
  created_at   timestamptz not null default now(),
  created_by   text not null,
  check (iva_crc < amount_crc)
);
create unique index if not exists expenses_invoice_once on public.expenses (coalesce(vendor_id::text, lower(vendor_name)), lower(invoice_no))
  where invoice_no is not null and voided_at is null;
create index if not exists expenses_date_idx on public.expenses (date);
alter table public.expenses enable row level security;
revoke all on public.expenses from anon, authenticated;

create or replace function public.expense_save(p_expense jsonb, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare x public.expenses; a acct.accounts; amt numeric; iva numeric; src text; inv text; vid uuid; vname text; eid bigint; who text;
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
  if amt is null or amt <= 0 or iva < 0 or iva >= amt or src not in ('cash', 'petty', 'bank', 'credit')
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
                                                                                       when 'bank' then 'from_bank' else 'from_credit' end), 'credit', amt)),
                     null, who);
  exception when others then
    if sqlerrm ~ 'period_closed' then return jsonb_build_object('ok', false, 'error', 'period_closed'); end if;
    raise;
  end;
  insert into public.expenses (id, date, vendor_id, vendor_name, description, account, amount_crc, iva_crc, paid_from, invoice_no, invoice_date, entry_id, created_by)
    values (p_request_id, (p_expense->>'date')::date, vid, vname, left(trim(p_expense->>'description'), 200), a.code, amt, iva, src, inv,
            nullif(p_expense->>'invoice_date', '')::date, eid, who);
  return jsonb_build_object('ok', true, 'id', p_request_id, 'entry_id', eid);
end $$;

create or replace function public.expense_void(p_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare x public.expenses; r jsonb;
begin
  if not acct.can_read() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if coalesce(trim(p_reason), '') = '' then return jsonb_build_object('ok', false, 'error', 'missing_reason'); end if;
  select * into x from public.expenses where id = p_id for update;
  if x.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if x.voided_at is not null then return jsonb_build_object('ok', false, 'error', 'already_voided'); end if;
  r := public.acct_entry_reverse(x.entry_id, public.cr_today(), 'gasto anulado: ' || trim(p_reason));
  if not coalesce((r->>'ok')::boolean, false) then return r; end if;
  update public.expenses set voided_at = now(), void_reason = left(trim(p_reason), 200), void_entry_id = (r->>'entry_id')::bigint where id = x.id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.expense_list(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public, acct as $$
begin
  if not (public.is_owner() or acct.can_read()) then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  return jsonb_build_object('ok', true, 'expenses', (
    select coalesce(jsonb_agg(to_jsonb(e) || jsonb_build_object('account_name', a.name) order by e.date desc, e.created_at desc), '[]')
      from public.expenses e join acct.accounts a on a.code = e.account where e.date between p_from and p_to),
    'accounts', (select coalesce(jsonb_agg(jsonb_build_object('code', code, 'name', name) order by code), '[]') from acct.accounts where type = 'expense' and active));
end $$;

revoke all on function public.expense_save(jsonb, uuid), public.expense_void(uuid, text), public.expense_list(date, date) from public, anon;
grant execute on function public.expense_save(jsonb, uuid), public.expense_void(uuid, text), public.expense_list(date, date) to authenticated;

select canopy.migration_end(14, 'expenses');
notify pgrst, 'reload schema';
