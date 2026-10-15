-- =====================================================================================================
-- Canopy OS · migración 0030 · El archivo de la factura de cada entrega (foto, PDF o XML) en Supabase Storage
-- Pegar TODO en Supabase → SQL Editor → New query → Run.  Requiere: 0029.
--
-- Qué hace
--   * Depósito privado "purchase-invoices": hasta 3 archivos por entrega (una factura de varias páginas), 10 MB cada
--     uno, solo imagen, PDF o XML. Nadie borra ni reemplaza un archivo subido.
--   * Quién sube y ve: el dueño con el código del teléfono, el contador, o el ingreso del café mientras tenga un
--     desbloqueo con PIN de encargado vigente (Storage no recibe el encabezado del PIN que ven las demás reglas:
--     por eso la regla mira el desbloqueo del ingreso en access_unlocks). Subir, además, solo a la carpeta de una
--     entrega de los últimos 90 días que tenga menos de 3 archivos.
--   * purchase_doc_attach: registra el archivo en la entrega (purchase_receipt_files, tabla de la 0029).
--   * Va aparte de la 0029 porque crea reglas en las tablas de Storage, que la cuenta del SQL Editor no posee: si
--     este archivo fallara, todo lo de la 0029 sigue funcionando, menos adjuntar el archivo.
-- Qué cambia para el personal: en «Recibir» y en el historial del pedido aparecen «Tomar foto» y «Elegir archivo».
-- Reversión: drop policy "purchase invoices read" / "purchase invoices add" on storage.objects; drop function
--   purchase_doc_attach, _purchase_doc_slot_open, _login_unlocked (el depósito y sus archivos quedan).
-- =====================================================================================================
select canopy.migration_begin(30, 'facturas_archivo');

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values ('purchase-invoices', 'purchase-invoices', false, 10485760, array['image/jpeg', 'image/png', 'image/webp', 'application/pdf', 'text/xml', 'application/xml']) on conflict (id) do nothing;

-- the login may handle these files: the owner with the phone code, the accountant, or a café login with a live
-- manager PIN unlock on one of its devices (the unlock header never reaches Storage)
create or replace function public._login_unlocked()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.is_owner() or acct.can_read()
                  or exists (select 1 from public.access_unlocks u join public.staff s on s.id = u.staff_id
                              where u.user_id = auth.uid() and u.expires_at > now() and s.active and s.role in ('manager', 'owner')), false);
$$;
revoke all on function public._login_unlocked() from public, anon;
grant execute on function public._login_unlocked() to authenticated;

-- a file goes only into the folder of a recent delivery that still has room (3 files)
create or replace function public._purchase_doc_slot_open(p_name text)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.purchase_receipts r where r.id::text = split_part(p_name, '/', 1) and r.received_at > now() - interval '90 days')
     and (select count(*) from storage.objects o where o.bucket_id = 'purchase-invoices' and split_part(o.name, '/', 1) = split_part(p_name, '/', 1)) < 3
     and p_name ~ '^[0-9a-f-]{36}/[A-Za-z0-9._-]{1,120}$';
$$;
revoke all on function public._purchase_doc_slot_open(text) from public, anon;
grant execute on function public._purchase_doc_slot_open(text) to authenticated;

drop policy if exists "purchase invoices read" on storage.objects;
create policy "purchase invoices read" on storage.objects for select to authenticated using (bucket_id = 'purchase-invoices' and (select public._login_unlocked()));
drop policy if exists "purchase invoices add" on storage.objects;
create policy "purchase invoices add" on storage.objects for insert to authenticated with check (bucket_id = 'purchase-invoices' and (select public._login_unlocked()) and public._purchase_doc_slot_open(name));
-- no update or delete rule: a filed invoice stays as it was

-- the file, registered on its delivery (once per path; a retry that finds it already there is fine)
create or replace function public.purchase_doc_attach(p_receipt_id uuid, p_path text)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare r public.purchase_receipts; k text; n int;
begin
  if not (public.inventory_open() or public._login_unlocked()) then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  select * into r from public.purchase_receipts where id = p_receipt_id for update;
  if r.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if coalesce(p_path, '') !~ ('^' || r.id::text || '/[A-Za-z0-9._-]{1,120}$') then return jsonb_build_object('ok', false, 'error', 'bad_path'); end if;
  if exists (select 1 from public.purchase_receipt_files where path = p_path) then return jsonb_build_object('ok', true, 'repeat', true); end if;
  select count(*) into n from public.purchase_receipt_files where receipt_id = r.id;
  if n >= 3 then return jsonb_build_object('ok', false, 'error', 'too_many'); end if;
  k := case when p_path ~* '\.pdf$' then 'pdf' when p_path ~* '\.xml$' then 'xml' when p_path ~* '\.(jpe?g|png|webp)$' then 'image' else 'other' end;
  insert into public.purchase_receipt_files (receipt_id, path, kind, by_name) values (r.id, p_path, k, public._inv_actor());
  return jsonb_build_object('ok', true, 'kind', k, 'files', n + 1);
end $$;
revoke all on function public.purchase_doc_attach(uuid, text) from public, anon;
grant execute on function public.purchase_doc_attach(uuid, text) to authenticated;

select canopy.migration_end(30, 'facturas_archivo');
notify pgrst, 'reload schema';
