-- =====================================================================================================
-- Canopy OS · migración 0018 · Comprobantes electrónicos: el registro de documentos (sin enviar nada)
-- Pegar TODO en Supabase → SQL Editor → New query → Run.  Requiere: 0017.
--
-- Qué hace
--   * public.e_documents: un documento por venta (tiquete), por devolución (nota de crédito, unida al
--     documento de la venta) y, si el cliente la pide con su cédula, factura. Cada documento lleva su estado
--     (pendiente, en cola, enviado, aceptado, rechazado, error, contingencia, anulado) y lo que le falta
--     (por ejemplo, el código CABYS de un producto).
--   * Ajuste einvoice_mode: off (como hoy, no se registra nada) o shadow (se registran los documentos para
--     revisar que los datos estén completos, pero NO se envía nada a Hacienda ni a ningún proveedor).
--     El envío real no existe todavía: se construye cuando el dueño elija el proveedor y el contador
--     confirme los requisitos (DEPENDENCIES A-02, A-10).
--   * einvoice_list: el dueño y el contador ven los documentos, cuántos hay por estado y qué productos no
--     tienen CABYS. einvoice_request_fe: la caja anota los datos del cliente que pide factura.
--   * canopy.einvoice_mark: el único camino para cambiar el estado (para el futuro conector del proveedor;
--     nadie desde la página lo puede llamar).
-- Qué cambia para el personal: nada mientras esté en off (así queda).
-- Reversión: update settings set value = '"off"' where key = 'einvoice_mode'; drop trigger order_e_document.
-- =====================================================================================================
select canopy.migration_begin(18, 'einvoice_scaffold');

insert into canopy.setting_defs (key, kind, choices, default_value, guard, description) values
  ('einvoice_mode', 'choice', '{off,shadow}', '"off"', null,
   'Comprobantes electrónicos: off = no se registran; shadow = cada venta y devolución registra su documento para revisar los datos, sin enviar nada. El envío real se agrega cuando haya proveedor y confirmación del contador.')
on conflict (key) do update set kind = excluded.kind, choices = excluded.choices, default_value = excluded.default_value,
                                guard = excluded.guard, description = excluded.description;

create table if not exists public.e_documents (
  id           uuid primary key default gen_random_uuid(),
  internal_no  bigint generated always as identity,
  kind         text not null check (kind in ('TE', 'FE', 'NC')),   -- tiquete, factura, nota de crédito
  order_id     uuid not null,
  reference_id uuid references public.e_documents(id),           -- a credit note points to the sale's document
  status       text not null default 'pending'
               check (status in ('pending', 'queued', 'sent', 'accepted', 'rejected', 'error', 'contingency', 'cancelled')),
  mode         text not null,                                    -- the mode when it was recorded (shadow)
  total_crc    numeric(14,2) not null,
  tax_crc      numeric(14,2),
  receiver     jsonb,                                            -- FE: who asked for it (name, id type, id number, email)
  missing      text[] not null default '{}',                     -- data a provider would need and is not there
  provider     text,
  provider_ref text,
  clave        text,                                             -- given by the provider / Hacienda, never made up here
  consecutive  text,
  response     jsonb,
  attempts     int not null default 0,
  last_error   text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  unique (order_id)
);
create index if not exists e_documents_status_idx on public.e_documents (status, created_at);
alter table public.e_documents enable row level security;
revoke all on public.e_documents from anon, authenticated;

-- what a sale's lines lack for a document: a CABYS code per product
create or replace function public._e_missing(p_order_id uuid) returns text[] language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(distinct 'cabys:' || i.item_name order by 'cabys:' || i.item_name), '{}')
    from public.order_items i
   where i.order_id = p_order_id
     and not exists (select 1 from public.menu_items m where lower(m.name) = lower(i.item_name) and m.cabys is not null);
$$;
revoke all on function public._e_missing(uuid) from public, anon, authenticated;

-- each sale or refund records its document while the mode is shadow; a sale is never stopped by this
create or replace function public._order_e_document()
returns trigger language plpgsql security definer set search_path = public as $$
declare ref uuid;
begin
  if (public.setting('einvoice_mode') #>> '{}') is distinct from 'shadow' then return new; end if;
  if new.part_of is not null or coalesce(new.status, 'done') = 'cancelled' then return new; end if;
  begin
    if new.refund_of is not null then
      select id into ref from public.e_documents where order_id = new.refund_of;
      insert into public.e_documents (kind, order_id, reference_id, mode, total_crc, tax_crc, missing)
        values ('NC', new.id, ref, 'shadow', new.total_crc, new.tax_crc, case when ref is null then '{reference}'::text[] else '{}' end)
        on conflict (order_id) do nothing;
    else
      insert into public.e_documents (kind, order_id, mode, total_crc, tax_crc)
        values ('TE', new.id, 'shadow', new.total_crc, new.tax_crc)
        on conflict (order_id) do nothing;
    end if;
  exception when others then
    insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
      values ('e_document_failed', null, 'sistema', new.id::text, left(sqlerrm, 200), '{}'::jsonb);
  end;
  return new;
end $$;
drop trigger if exists order_e_document on public.orders;
create trigger order_e_document after insert on public.orders for each row execute function public._order_e_document();

-- the lines arrive after the order: the document's IVA and missing data follow them; a void cancels it
create or replace function public._order_e_document_sync()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.e_documents where order_id = new.id) then return new; end if;
  begin
    update public.e_documents d
       set total_crc = new.total_crc, tax_crc = new.tax_crc,
           missing = public._e_missing(new.id) || case when d.kind = 'NC' and d.reference_id is null then '{reference}'::text[] else '{}' end,
           status = case when new.voided_at is not null and d.status = 'pending' then 'cancelled' else d.status end,
           updated_at = now()
     where d.order_id = new.id and d.status in ('pending', 'cancelled');
  exception when others then
    insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
      values ('e_document_failed', null, 'sistema', new.id::text, left(sqlerrm, 200), '{}'::jsonb);
  end;
  return new;
end $$;
drop trigger if exists order_e_document_sync on public.orders;
create trigger order_e_document_sync after update of tax_crc, total_crc, voided_at on public.orders
  for each row execute function public._order_e_document_sync();

-- the cashier writes down the customer who asks for an invoice with their ID (kept for the provider)
create or replace function public.einvoice_request_fe(p_order_id uuid, p_receiver jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare d public.e_documents; idn text; em text;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if (public.setting('einvoice_mode') #>> '{}') is distinct from 'shadow' then return jsonb_build_object('ok', false, 'error', 'einvoice_off'); end if;
  select * into d from public.e_documents where order_id = p_order_id for update;
  if d.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if d.kind = 'NC' or d.status not in ('pending', 'error') then return jsonb_build_object('ok', false, 'error', 'too_late'); end if;
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

-- the documents, for the owner and the accountant
create or replace function public.einvoice_list(p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public._books_allowed() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
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

-- the one way a document changes state: for the provider's connector (service role only, never the page)
create or replace function canopy.einvoice_mark(p_id uuid, p_status text, p_provider text default null, p_provider_ref text default null,
                                                p_clave text default null, p_consecutive text default null, p_response jsonb default null,
                                                p_error text default null)
returns jsonb language plpgsql security definer set search_path = public, canopy as $$
declare d public.e_documents;
begin
  select * into d from public.e_documents where id = p_id for update;
  if d.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  -- forward only: what Hacienda accepted or rejected never goes back
  if not ((d.status, p_status) in (('pending', 'queued'), ('pending', 'cancelled'), ('queued', 'sent'), ('queued', 'error'), ('queued', 'contingency'),
                                    ('contingency', 'queued'), ('error', 'queued'), ('sent', 'accepted'), ('sent', 'rejected'), ('sent', 'error'))) then
    return jsonb_build_object('ok', false, 'error', 'bad_transition', 'from', d.status, 'to', p_status);
  end if;
  update public.e_documents
     set status = p_status, provider = coalesce(p_provider, provider), provider_ref = coalesce(p_provider_ref, provider_ref),
         clave = coalesce(p_clave, clave), consecutive = coalesce(p_consecutive, consecutive), response = coalesce(p_response, response),
         last_error = case when p_status = 'error' then left(p_error, 300) else last_error end,
         attempts = attempts + case when p_status = 'sent' then 1 else 0 end, updated_at = now()
   where id = p_id;
  return jsonb_build_object('ok', true);
end $$;
revoke all on function canopy.einvoice_mark(uuid, text, text, text, text, text, jsonb, text) from public, anon, authenticated;

revoke all on function public.einvoice_request_fe(uuid, jsonb), public.einvoice_list(date, date) from public, anon;
grant execute on function public.einvoice_request_fe(uuid, jsonb), public.einvoice_list(date, date) to authenticated;
revoke all on function public._order_e_document(), public._order_e_document_sync() from public, anon, authenticated;

select canopy.migration_end(18, 'einvoice_scaffold');
notify pgrst, 'reload schema';
