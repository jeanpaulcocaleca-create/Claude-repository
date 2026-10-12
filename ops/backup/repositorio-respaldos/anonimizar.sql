-- =====================================================================================================
-- Canopy OS · ANONIMIZAR una copia de producción antes de cargarla en el proyecto de PRUEBAS.
-- Solo se ejecuta sobre una base desechable dentro del trabajo de GitHub (ensayo.sh), NUNCA sobre producción.
-- Quita lo que identifica personas y lo que da acceso; deja intactos montos, productos, fechas y cantidades,
-- que es lo que el ensayo necesita.
--   * personal: nombre "Persona N", todos con el PIN de pruebas (secreto STAGING_PIN); sin bloqueos
--   * huéspedes: sin nombre real ni teléfono; notas de habitación borradas
--   * proveedores: "Proveedor N", sin contacto
--   * bitácora, caja, inventario, compras, descuentos: quién lo hizo → "Persona"
--   * preguntas del chat del sitio: texto genérico
--   * cuentas de ingreso (app_accounts) y llaves de desbloqueo: se quitan (en pruebas se crean otras)
-- Uso: psql -v pin=NNNN -f anonimizar.sql   (funciona antes y después de cualquier migración)
-- =====================================================================================================
\set ON_ERROR_STOP on
-- a throw-away copy: the protections of the real database (history guards, audit triggers) do not apply here
set session_replication_role = replica;
select set_config('canopy.staging_pin', :'pin', false);
do $$
declare
  t record;
  has boolean;
  pin text := current_setting('canopy.staging_pin');
begin
  if pin !~ '^[0-9]{4,8}$' then raise exception 'STAGING_PIN debe tener de 4 a 8 dígitos'; end if;
  -- people
  update public.staff s set name = 'Persona ' || x.n, pin_hash = extensions.crypt(pin, extensions.gen_salt('bf')), failed_pins = 0, locked_until = null
    from (select id, row_number() over (order by created_at, id) as n from public.staff) x where x.id = s.id;
  update public.vendors v set name = 'Proveedor ' || x.n, contact_name = null, phone = null, whatsapp = null, email = null, notes = null
    from (select id, row_number() over (order by created_at, id) as n from public.vendors) x where x.id = v.id;
  update public.orders set guest_name = case when guest_name is not null then 'Huésped' end, guest_phone = null,
                           notes = case when source = 'room' then null else notes end
   where guest_name is not null or guest_phone is not null or source = 'room';
  update public.chat_questions set message = 'pregunta', session = null;
  -- "who did it" columns, wherever they exist in this copy
  for t in select c.table_name, c.column_name from information_schema.columns c
            where c.table_schema = 'public'
              and c.column_name in ('manager_name', 'opened_by_name', 'closed_by_name', 'by_name', 'approved_name', 'discount_by',
                                    'operator_name', 'staff_name', 'approved_by_name', 'reviewed_by_name', 'prepared_by_name')
              and exists (select 1 from information_schema.tables x where x.table_schema = 'public' and x.table_name = c.table_name and x.table_type = 'BASE TABLE') loop
    execute format('update public.%I set %I = ''Persona'' where %I is not null', t.table_name, t.column_name, t.column_name);
  end loop;
  update public.audit_log set summary = action, details = '{}'::jsonb;
  -- logins and unlock tokens belong to production only
  delete from public.app_accounts;
  for t in select table_name from information_schema.tables
            where table_schema = 'public' and table_name in ('access_unlocks', 'sales_unlocks', 'inventory_unlocks', 'operator_sessions') loop
    execute format('delete from public.%I', t.table_name);
  end loop;
  select exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'expenses' and column_name = 'notes') into has;
  if has then update public.expenses set notes = null where notes is not null; end if;
end $$;
select set_config('canopy.staging_pin', '', false);
set session_replication_role = origin;
select 'copia anonimizada: ' || (select count(*) from public.staff) || ' personas, ' || (select count(*) from public.orders) || ' ventas' as resultado;
