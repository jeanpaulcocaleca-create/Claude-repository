-- =====================================================================================================
-- Canopy OS · revisión de una versión (SOLO LECTURA: no cambia nada, no muestra ventas, nombres ni PINs)
-- Supabase → SQL Editor → New query → pegar → Run. Copie la celda del resultado si se la piden.
--
-- Muestra
--   * qué migraciones están aplicadas y cuáles faltan (0000 a la última de esta versión);
--   * los interruptores (ajustes) y las confirmaciones registradas;
--   * las funciones que la página necesita y no existen;
--   * funciones de la API que cualquiera sin iniciar sesión podría ejecutar (debe estar vacío salvo las públicas
--     del menú y los pedidos de habitación);
--   * tablas expuestas sin RLS (debe estar vacío);
--   * Storage (storage_buckets_missing y storage_policies_missing deben estar vacíos, receipt_upload_rule_current en
--     true): el depósito de facturas de gastos y sus dos reglas (desde la 0015), la regla de subida de la 0025, y las
--     reglas de fotos del menú solo si existe ese depósito (menu_photos_bucket; un proyecto de PRUEBAS no lo tiene).
-- =====================================================================================================
with expected as (select generate_series(0, 32) as v),
applied as (select version from canopy.migrations),
needed(fn) as (values
  ('pos_record_sale'), ('pos_record_tender'), ('register_open'), ('register_close'), ('register_expected'), ('register_today'),
  ('manager_void_order'), ('manager_refund_order'), ('order_search'), ('order_reprint'), ('pos_operator_start'), ('fx_today'), ('fx_rate_set'),
  ('settings_get'), ('setting_set'), ('compliance_confirm'), ('po_receive_delivery'), ('stock_count'), ('stock_waste'),
  ('acct_overview'), ('acct_post_days'), ('acct_entry_post'), ('acct_entry_reverse'), ('acct_journal_reverse'), ('acct_trial_balance'), ('acct_income_statement'),
  ('acct_balance_sheet'), ('acct_cash_flow'), ('acct_journal'), ('expense_save'), ('expense_attach'), ('expense_list'), ('tax_summary'),
  ('supplier_invoice_save'), ('supplier_payment_save'), ('ap_aging'), ('iva_report'), ('inventory_valuation'), ('product_profitability'),
  ('einvoice_list'), ('register_cash_move'), ('register_cash_moves'), ('cash_reconciliation'), ('cash_payouts'),
  ('bank_overview'), ('bank_import'), ('bank_post'), ('timesheet'), ('timesheet_approve'), ('payroll_prepare'), ('payroll_post'), ('labor_cost'), ('payroll_month_report'), ('aguinaldo_estimate'),
  ('dashboard_today'), ('sales_patterns'), ('trends_monthly'), ('supplier_insights'), ('stock_forecast'),
  ('po_receive_and_settle'), ('po_receipt_settle'), ('po_receipt_pay'), ('po_history'), ('po_pending'),
  ('recipe_save'), ('recipes_autolink_pin')),
menu_photos as (select exists (select 1 from storage.buckets where id = 'menu-photos') as present),
storage_rules(name) as (select policyname from pg_policies where schemaname = 'storage' and tablename = 'objects')
select jsonb_pretty(jsonb_build_object(
  'checked_at', now(),
  'migrations_applied', (select coalesce(jsonb_agg(version order by version), '[]') from applied),
  'migrations_missing', (select coalesce(jsonb_agg(v order by v), '[]') from expected where v not in (select version from applied)),
  'settings', (select coalesce(jsonb_object_agg(d.key, coalesce(s.value, d.default_value)), '{}')
                 from canopy.setting_defs d left join public.settings s on s.key = d.key),
  'confirmations', (select coalesce(jsonb_agg(jsonb_build_object('key', key, 'by', confirmed_by, 'at', confirmed_at) order by key), '[]')
                      from public.compliance_confirmations),
  'functions_missing', (select coalesce(jsonb_agg(fn order by fn), '[]') from needed
                         where not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = needed.fn)),
  'anon_can_run', (select coalesce(jsonb_agg(p.proname order by p.proname), '[]')
                     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                    where n.nspname = 'public' and p.prokind = 'f' and p.prorettype <> 'trigger'::regtype
                      and has_function_privilege('anon', p.oid, 'execute') and p.prosecdef),
  'tables_without_rls', (select coalesce(jsonb_agg(c.relname order by c.relname), '[]')
                           from pg_class c join pg_namespace n on n.oid = c.relnamespace
                          where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity),
  'ledger', jsonb_build_object('entries', (select count(*) from acct.entries), 'unbalanced', (
      select count(*) from (select entry_id from acct.lines group by entry_id having sum(debit) <> sum(credit)) u)),
  'backups_last_ok', (select max(finished_at) from canopy.backup_runs where status = 'ok'),
  'menu_photos_bucket', (select present from menu_photos),
  'storage_buckets_missing', (select coalesce(jsonb_agg(b order by b), '[]') from (values ('expense-receipts')) x(b)
                               where 15 in (select version from applied) and not exists (select 1 from storage.buckets where id = x.b)),
  'storage_policies_missing', (select coalesce(jsonb_agg(p order by p), '[]') from (values
                                 ('expense receipts read', 15 in (select version from applied)), ('expense receipts add', 15 in (select version from applied)),
                                 ('menu photos read', (select present from menu_photos)), ('menu photos owner write', (select present from menu_photos))) x(p, wanted)
                                where wanted and p not in (select name from storage_rules)),
  -- 0025: uploads only into the folder of an expense that has no file yet
  'receipt_upload_rule_current', (select case when 25 in (select version from applied) then coalesce((
      select strpos(with_check, '_receipt_slot_open') > 0 from pg_policies
       where schemaname = 'storage' and tablename = 'objects' and policyname = 'expense receipts add'), false) end)
)) as release_check;
