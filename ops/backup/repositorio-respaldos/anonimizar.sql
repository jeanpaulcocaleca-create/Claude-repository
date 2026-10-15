-- =====================================================================================================
-- Canopy OS · ANONIMIZAR una copia de producción antes de cargarla en el proyecto de PRUEBAS.
-- Solo se ejecuta sobre una base desechable dentro del trabajo de GitHub (ensayo.sh), NUNCA sobre producción
-- (se niega si la cuenta no es superusuario: en Supabase, ni producción ni pruebas lo son).
-- Quita lo que identifica personas y lo que da acceso; deja intactos montos, productos, fechas y cantidades,
-- que es lo que el ensayo necesita.
--   * personal: nombre "Persona N", todos con el PIN de pruebas (secreto STAGING_PIN); sin bloqueos
--   * huéspedes y cuentas abiertas: sin nombre real ni teléfono; enlaces de seguimiento y códigos QR de habitación nuevos
--   * proveedores: "Proveedor N", sin contacto
--   * quién lo hizo (bitácora, caja, inventario, compras, descuentos, contabilidad, planilla) → "Persona";
--     el nombre de cada aparato → "Aparato N"
--   * texto libre (notas, motivos, descripciones, referencias, líneas del banco, memos) → "texto"; la columna libre
--     "note" de los pedidos de producción, a su valor por defecto
--   * preguntas del chat del sitio: texto genérico
--   * cuentas de ingreso (app_accounts) y llaves de desbloqueo: se quitan (en pruebas se crean otras)
-- Cada columna de texto de la copia está en una de las listas de abajo. Si una migración nueva agrega otra, el
-- script se detiene ANTES de cambiar nada y nombra la columna (nunca su contenido): pruebas no recibe nada sin revisar.
-- Uso: psql -v pin=NNNN -f anonimizar.sql   (funciona antes y después de cualquier migración)
-- =====================================================================================================
\set ON_ERROR_STOP on
-- only on the job's throw-away server, where this account is a superuser (on Supabase it never is)
do $$ begin
  if not coalesce((select rolsuper from pg_roles where rolname = current_user), false) then
    raise exception 'anonimizar.sql solo corre en la base desechable del trabajo. No se cambió nada.';
  end if;
end $$;
-- a throw-away copy: the protections of the real database (history guards, audit triggers) do not apply here
set session_replication_role = replica;
-- its result is the PIN itself: never printed (if a later step fails it would be the last line in the log)
select set_config('canopy.staging_pin', :'pin', false) \g /dev/null
do $$
declare
  t record;
  pin text := current_setting('canopy.staging_pin');
  -- who did it: a text column with one of these names, in any table of public or acct, becomes "Persona"
  who text[] := array['manager_name', 'opened_by_name', 'closed_by_name', 'by_name', 'approved_name', 'discount_by', 'operator_name', 'paid_operator_name',
                      'staff_name', 'created_by', 'confirmed_by', 'entered_by', 'imported_by', 'done_by', 'prepared_by', 'reviewed_by', 'settled_by',
                      'approved_by', 'updated_by', 'changed_by', 'voided_by'];
  -- typed by people: becomes "texto" (never empty, so "it has a reason" stays true)
  free text[] := array['public.orders.notes', 'public.orders.void_reason', 'public.orders.discount_reason', 'public.discount_approvals.reason',
                       'public.register_days.notes', 'public.stock_moves.note', 'public.stock_items.notes', 'public.purchase_orders.note',
                       'public.vendors.notes', 'public.expenses.notes', 'public.expenses.description', 'public.expenses.void_reason',
                       'public.cash_movements.reason', 'public.cash_movements.void_reason', 'public.supplier_invoices.void_reason',
                       'public.supplier_payments.reference', 'public.supplier_payments.void_reason', 'public.bank_accounts.name',
                       'public.bank_lines.description', 'public.bank_lines.reference', 'public.bank_lines.note', 'public.bank_imports.file_name',
                       'public.compliance_confirmations.reference', 'public.compliance_confirmations.note', 'public.tax_rates.reference',
                       'public.payroll_rules.reference', 'public.payroll_lines.other_note', 'public.payroll_lines.extra_note',
                       'public.payroll_params.reference', 'public.staff_profile.notes', 'public.vacations.note', 'public.vacations.void_reason',
                       'public.payroll_special_runs.note', 'public.e_documents.last_error',
                       'acct.entries.memo', 'acct.lines.memo'];
  -- emptied (nullable): a bank account's last digits, the e-invoice receiver and Hacienda's answer about it
  cleared text[] := array['public.bank_accounts.last4', 'public.e_documents.receiver', 'public.e_documents.response'];
  -- handled one by one below
  special text[] := array['public.staff.name', 'public.staff.pin_hash', 'public.vendors.name', 'public.vendors.contact_name', 'public.vendors.phone',
                          'public.vendors.whatsapp', 'public.vendors.email', 'public.orders.guest_name', 'public.orders.guest_phone',
                          'public.orders.note', 'public.orders.track_token', 'public.rooms.code', 'public.chat_questions.message',
                          'public.chat_questions.session', 'public.audit_log.summary', 'public.audit_log.details', 'public.audit_log.target_id',
                          'public.expenses.vendor_name', 'public.expenses.receipt_path', 'public.bank_lines.fingerprint',
                          'public.payroll_runs.rules', 'public.staff_profile.id_number', 'public.payroll_special_runs.lines',
                          'public.purchase_receipts.invoice_draft'];
  -- logins and unlock tokens belong to production only: these tables are emptied
  emptied text[] := array['app_accounts', 'access_unlocks', 'sales_unlocks', 'inventory_unlocks', 'operator_sessions'];
  -- about the business, not about anyone: menu, stock, chart of accounts, settings, codes, kinds and statuses
  keep text[] := array['acct.accounts.code', 'acct.accounts.name', 'acct.accounts.type', 'acct.entries.source', 'acct.entries.source_key',
                       'acct.lines.account', 'acct.mappings.account', 'acct.mappings.key', 'acct.mappings.label', 'acct.periods.status',
                       'canopy.backup_runs.detail', 'canopy.backup_runs.file_name', 'canopy.backup_runs.restore_test', 'canopy.backup_runs.row_counts',
                       'canopy.backup_runs.source', 'canopy.backup_runs.status', 'canopy.fx_fetch_log.detail', 'canopy.migrations.applied_by',
                       'canopy.migrations.name', 'canopy.setting_defs.choices', 'canopy.setting_defs.default_value', 'canopy.setting_defs.description',
                       'canopy.setting_defs.guard', 'canopy.setting_defs.key', 'canopy.setting_defs.kind', 'public.audit_log.action',
                       'public.bank_accounts.bank', 'public.bank_accounts.currency', 'public.bank_accounts.gl_account', 'public.bank_lines.status',
                       'public.board_group_slides.item_ids', 'public.board_group_slides.kicker', 'public.board_group_slides.title',
                       'public.board_settings.mode', 'public.board_settings.rotation', 'public.board_settings.tagline', 'public.board_settings.theme',
                       'public.cash_movements.currency', 'public.cash_movements.direction', 'public.cash_movements.purpose', 'public.cash_tenders.flags',
                       'public.chat_questions.lang', 'public.chat_questions.matched', 'public.compliance_confirmations.key',
                       'public.discount_approvals.kind', 'public.e_documents.clave', 'public.e_documents.consecutive', 'public.e_documents.kind',
                       'public.e_documents.missing', 'public.e_documents.mode', 'public.e_documents.provider', 'public.e_documents.provider_ref',
                       'public.e_documents.status', 'public.expenses.account', 'public.expenses.invoice_no', 'public.expenses.paid_from',
                       'public.fx_rates.source', 'public.locations.name', 'public.menu_categories.color', 'public.menu_categories.name',
                       'public.menu_items.cabys', 'public.menu_items.color', 'public.menu_items.description', 'public.menu_items.description_es',
                       'public.menu_items.name', 'public.menu_items.name_es', 'public.menu_items.photo_url', 'public.menu_items.quick',
                       'public.menu_items.tax_code', 'public.order_items.item_name', 'public.order_items.tax_code', 'public.orders.flags',
                       'public.orders.guest_lang', 'public.orders.payment_method', 'public.orders.source', 'public.orders.status',
                       'public.pay_periods.status', 'public.payroll_lines.deductions', 'public.payroll_lines.employer', 'public.payroll_lines.pay_kind',
                       'public.payroll_lines.renta_detail', 'public.payroll_params.key', 'public.payroll_params.value', 'public.payroll_runs.params',
                       'public.payroll_rules.category', 'public.staff_profile.contract', 'public.vacations.kind', 'public.payroll_special_runs.kind',
                       'public.payroll_special_runs.status',
                       'public.payroll_rules.code', 'public.payroll_rules.kind', 'public.payroll_rules.name', 'public.payroll_runs.status',
                       'public.purchase_orders.status', 'public.purchase_receipts.invoice_no', 'public.purchase_receipts.invoice_status',
                       'public.supplier_invoices.currency', 'public.settings.key', 'public.settings.value',
                       'public.staff.role', 'public.staff_pay.kind', 'public.stock_items.category', 'public.stock_items.name',
                       'public.stock_items.pack_label', 'public.stock_items.unit', 'public.stock_moves.kind', 'public.supplier_invoices.account',
                       'public.supplier_invoices.number', 'public.supplier_payments.paid_from', 'public.tab_adds.result', 'public.tax_rates.code',
                       'public.tax_rates.name', 'public.vendors.order_days'];
  unknown text;
begin
  if pin !~ '^[0-9]{4,8}$' then raise exception 'STAGING_PIN debe tener de 4 a 8 dígitos'; end if;
  -- every text, json or binary column this copy has (names only, never their content)
  create temp table _cols on commit drop as
    select n.nspname as s, c.relname as tb, a.attname as col, n.nspname || '.' || c.relname || '.' || a.attname as q,
           ty.typcategory = 'S' as is_text
      from pg_attribute a join pg_class c on c.oid = a.attrelid join pg_namespace n on n.oid = c.relnamespace
      join pg_type ty on ty.oid = a.atttypid left join pg_type el on el.oid = ty.typelem and ty.typcategory = 'A'
     where n.nspname in ('public', 'canopy', 'acct') and c.relkind in ('r', 'p') and a.attnum > 0 and not a.attisdropped
       -- text, json, xml, binary, and network or device addresses (an IP or a MAC is personal): a new one must be classified above
       and (coalesce(el.typcategory, ty.typcategory) in ('S', 'I') or coalesce(el.typname, ty.typname) in ('json', 'jsonb', 'xml', 'bytea', 'macaddr', 'macaddr8'));
  select string_agg(q, ', ' order by q) into unknown from _cols
   where not (q = any (keep || special) or (is_text and q = any (free)) or q = any (cleared)
              or (s <> 'canopy' and is_text and (col = any (who) or col = 'station')) or (s = 'public' and tb = any (emptied)));
  if unknown is not null then
    raise exception 'anonimizar.sql no sabe si estas columnas guardan datos de personas: %. Hay que clasificarlas en anonimizar.sql; no se cambió ni se copió nada.', unknown;
  end if;
  -- people
  update public.staff s set name = 'Persona ' || x.n, pin_hash = extensions.crypt(pin, extensions.gen_salt('bf')), failed_pins = 0, locked_until = null
    from (select id, row_number() over (order by created_at, id) as n from public.staff) x where x.id = s.id;
  update public.vendors v set name = 'Proveedor ' || x.n, contact_name = null, phone = null, whatsapp = null, email = null, notes = null
    from (select id, row_number() over (order by created_at, id) as n from public.vendors) x where x.id = v.id;
  -- guests and open tabs (a tab is named by its guest_name); order-tracking links and room QR codes open things
  update public.orders set guest_name = case when guest_name is not null then 'Huésped' end, guest_phone = null,
                           notes = case when source = 'room' then null else notes end
   where guest_name is not null or guest_phone is not null or source = 'room';
  update public.orders set track_token = md5(random()::text || id::text) where track_token is not null;
  -- ID numbers (cédula, DIMEX) and the names and ID numbers copied into an aguinaldo run (0026)
  if exists (select 1 from _cols where q = 'public.staff_profile.id_number') then
    execute $q$update public.staff_profile p set id_number = '0-0000-' || lpad(x.n::text, 4, '0'), notes = case when notes is not null then 'texto' end
               from (select staff_id, row_number() over (order by staff_id) as n from public.staff_profile) x where x.staff_id = p.staff_id$q$;
  end if;
  if exists (select 1 from _cols where q = 'public.payroll_special_runs.lines') then
    execute $q$update public.payroll_special_runs set lines = (select coalesce(jsonb_agg((e - 'id_number') || jsonb_build_object('staff_name', 'Persona')), '[]') from jsonb_array_elements(lines) e)
               where jsonb_array_length(lines) > 0$q$;
  end if;
  update public.rooms set code = coalesce(number::text, 'h') || '-' || left(md5(random()::text || id::text), 6);
  -- visitors write this table directly (anyone may insert): keep lang and matched only when they look like codes
  update public.chat_questions set message = 'pregunta', session = null,
         lang = case when lang in ('en', 'es') then lang end, matched = case when matched ~ '^[a-z0-9_.-]{1,40}$' then matched end;
  -- "who did it", free text and emptied columns, wherever they exist in this copy
  for t in select * from _cols where s <> 'canopy' and is_text and col = any (who) loop
    execute format('update %I.%I set %I = ''Persona'' where %I is not null', t.s, t.tb, t.col, t.col);
  end loop;
  for t in select * from _cols where is_text and q = any (free) loop
    execute format('update %I.%I set %I = ''texto'' where %I is not null', t.s, t.tb, t.col, t.col);
  end loop;
  for t in select * from _cols where q = any (cleared) loop
    execute format('update %I.%I set %I = null where %I is not null', t.s, t.tb, t.col, t.col);
  end loop;
  -- each device's name is typed on it (e.g. "iPad de …"): "Aparato N", the same name in every table
  create temp table _aparatos (old text primary key, new text) on commit drop;
  for t in select * from _cols where s <> 'canopy' and is_text and col = 'station' loop
    execute format('insert into _aparatos (old) select distinct %I from %I.%I where %I is not null on conflict do nothing', t.col, t.s, t.tb, t.col);
  end loop;
  update _aparatos a set new = 'Aparato ' || x.n from (select old, row_number() over (order by old) as n from _aparatos) x where x.old = a.old;
  for t in select * from _cols where s <> 'canopy' and is_text and col = 'station' loop
    execute format('update %I.%I x set %I = a.new from _aparatos a where a.old = x.%I', t.s, t.tb, t.col, t.col);
  end loop;
  -- after the migrations: suppliers typed by hand (one name each, so an invoice number stays unique per supplier),
  -- invoice file names (the files themselves never go to staging), a hash of each bank line's text, and who
  -- confirmed each payroll rule inside a payroll run's copy of the rules
  if exists (select 1 from _cols where q = 'public.expenses.vendor_name') then
    execute 'update public.expenses e set vendor_name = ''Proveedor externo '' || x.n
               from (select v, dense_rank() over (order by v) as n from (select distinct lower(vendor_name) as v from public.expenses) d where v is not null) x
              where lower(e.vendor_name) = x.v';
  end if;
  if exists (select 1 from _cols where q = 'public.expenses.receipt_path') then
    execute 'update public.expenses set receipt_path = id || ''/factura'' where receipt_path is not null';
  end if;
  -- 0029: the draft of a delivery's invoice names who captured it and may carry a note may carry the supplier
  if exists (select 1 from _cols where q = 'public.purchase_receipts.invoice_draft') then
    execute $d$update public.purchase_receipts set invoice_draft = invoice_draft || jsonb_strip_nulls(jsonb_build_object(
               'captured_by', case when invoice_draft ? 'captured_by' then 'Persona' end, 'notes', case when invoice_draft ? 'notes' then 'texto' end))
             where invoice_draft is not null$d$;
  end if;
  if exists (select 1 from _cols where q = 'public.bank_lines.fingerprint') then
    execute 'update public.bank_lines set fingerprint = md5(random()::text || id::text)';
  end if;
  if exists (select 1 from _cols where q = 'public.payroll_runs.rules') then
    execute $u$update public.payroll_runs r set rules = (
               select coalesce(jsonb_agg(case when jsonb_typeof(e) = 'object'
                                              then e || jsonb_strip_nulls(jsonb_build_object('confirmed_by', case when e ? 'confirmed_by' then 'Persona' end,
                                                                                             'reference', case when e ? 'reference' then 'texto' end))
                                              else e end order by i), '[]'::jsonb)
                 from jsonb_array_elements(r.rules) with ordinality x(e, i))
             where jsonb_typeof(rules) = 'array'$u$;
  end if;
  -- the log quotes names, guests, reasons and emails; its target is an id, a date or a code (anything else goes)
  update public.audit_log set summary = action, details = '{}'::jsonb,
                              target_id = case when target_id ~ '^([0-9a-fA-F-]{36}|[0-9]{4}-[0-9]{2}-[0-9]{2}|[A-Za-z0-9_.:]{1,64})$' then target_id end;
  -- logins and unlock tokens
  for t in select c.relname from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'p') and c.relname = any (emptied) loop
    execute format('delete from public.%I', t.relname);
  end loop;
  -- production's orders has an extra free-text column "note" (snapshot 2026-10-12) whose content is unknown;
  -- it may be NOT NULL with a default, so it gets its default (null or blank) rather than null
  if exists (select 1 from _cols where q = 'public.orders.note') then execute 'update public.orders set note = default where note is not null'; end if;
end $$;
select set_config('canopy.staging_pin', '', false);
set session_replication_role = origin;
select 'copia anonimizada: ' || (select count(*) from public.staff) || ' personas, ' || (select count(*) from public.orders) || ' ventas' as resultado;
