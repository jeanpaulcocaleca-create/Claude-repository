-- =====================================================================================================
-- Canopy OS · migración 0015 · Foto o PDF de la factura de cada gasto; el contador ve el IVA de ventas
-- Pegar TODO en Supabase → SQL Editor → New query → Run.  Requiere: 0014.
--
-- Qué hace
--   * Depósito privado "expense-receipts" (Supabase Storage): la foto o PDF de cada factura de gasto.
--     Solo el dueño, un encargado con PIN y el contador pueden subir y ver; nadie puede borrar ni reemplazar.
--   * expenses.receipt_path: el archivo de cada gasto.
--   * tax_summary (IVA de ventas por tarifa) también para el contador, para el paquete mensual.
-- Qué cambia para el personal: nada.
-- Reversión: drop policy "expense receipts read" / "expense receipts add" on storage.objects.
-- =====================================================================================================
select canopy.migration_begin(15, 'receipts_package');

insert into storage.buckets (id, name, public) values ('expense-receipts', 'expense-receipts', false) on conflict (id) do nothing;

create or replace function public._receipts_allowed()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.is_owner() or acct.can_read(), false);
$$;
revoke all on function public._receipts_allowed() from public, anon;
grant execute on function public._receipts_allowed() to authenticated;

drop policy if exists "expense receipts read" on storage.objects;
create policy "expense receipts read" on storage.objects for select to authenticated
  using (bucket_id = 'expense-receipts' and (select public._receipts_allowed()));
drop policy if exists "expense receipts add" on storage.objects;
create policy "expense receipts add" on storage.objects for insert to authenticated
  with check (bucket_id = 'expense-receipts' and (select public._receipts_allowed()));
-- no update or delete policy: a receipt, once filed, stays as it was

alter table public.expenses add column if not exists receipt_path text;

-- the file of an expense, set once (a later photo of the same expense is refused)
create or replace function public.expense_attach(p_id uuid, p_path text)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare x public.expenses;
begin
  if not public._receipts_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  select * into x from public.expenses where id = p_id for update;
  if x.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if coalesce(p_path, '') !~ ('^' || p_id::text || '/[^/]{1,120}$') then return jsonb_build_object('ok', false, 'error', 'bad_path'); end if;
  if x.receipt_path is not null then return jsonb_build_object('ok', false, 'error', 'already_attached'); end if;
  update public.expenses set receipt_path = p_path where id = p_id;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.expense_attach(uuid, text) from public, anon;
grant execute on function public.expense_attach(uuid, text) to authenticated;

create or replace function public.tax_summary(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare by_rate jsonb; untaxed jsonb;
begin
  if not (public.is_owner() or public.sales_open() or acct.can_read()) then return jsonb_build_object('ok', false, 'error', 'locked'); end if;
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

select canopy.migration_end(15, 'receipts_package');
notify pgrst, 'reload schema';
