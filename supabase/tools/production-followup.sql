-- =====================================================================================================
-- Canopy OS · SEGUIMIENTO DE LA FOTO DE PRODUCCIÓN (SOLO LECTURA: no cambia nada)
-- Supabase → SQL Editor → New query → pegar TODO → Run. Resultado: UNA celda ("seguimiento"). Copie la celda
-- completa y péguela en el chat o en un archivo para Claude.
--
-- Contesta lo que dejó abierto la foto del 2026-10-12 (supabase/tools/production-snapshot.sql). No muestra
-- contraseñas, PINs, claves, montos ni nombres del personal, ni el texto de ninguna nota:
--   * logins_that_typed_pins: cada ingreso (correo enmascarado, jo***@gmail.com), su tipo, si tiene el código del
--     teléfono, y cuántas veces y entre qué fechas se escribió en él un PIN para abrir las áreas del dueño, las
--     ventas o el inventario: así se sabe qué ingreso usan los aparatos del café;
--   * team_roles: cuántas personas tiene el equipo por rol, activas o no;
--   * orders_note: la columna "note" de los pedidos (solo existe en producción): posición, tipo, si es obligatoria,
--     su valor por defecto, comentario, reglas y disparadores, y cuántos pedidos tienen algo escrito ahí, el largo
--     mayor y entre qué fechas (nunca el texto);
--   * audit_menu: la función que anota los cambios del menú (en producción es distinta a la del repositorio): sus
--     huellas, cómo corre, sus disparadores, qué cambios del menú anotó cada mes, y su código completo TAL COMO ESTÁ
--     GUARDADO en la base (si alguien escribió ahí un comentario, un nombre o un correo, aparece tal cual);
--   * storage_rights: qué puede hacer en Storage la cuenta del SQL Editor (lo que necesita la migración 0015);
--   * original_tables_triggers: los disparadores de las tablas originales (tabla · nombre · función · estado).
-- Sirve antes y después de las migraciones, y también en una base sin Supabase. Las partes que dependen de tablas
-- opcionales usan query_to_xml solo para leer.
-- =====================================================================================================
select jsonb_pretty(jsonb_build_object(
  'checked_at', now(),
  -- access_unlock, sales_unlock and inventory_unlock write these actions with target_id = the signed-in login's id
  'logins_that_typed_pins', case when to_regclass('auth.users') is null or to_regclass('public.audit_log') is null then null else
      replace(replace(replace((xpath('/row/j/text()', query_to_xml(format($q$
        with pins as (
          select l.target_id, l.action, count(*) as n, min(l.at) as first_at, max(l.at) as last_at
            from public.audit_log l where l.action in ('access_open', 'sales_view', 'inventory_view') group by 1, 2
        ), per_login as (
          select target_id, max(last_at) as last_at,
                 jsonb_object_agg(action, jsonb_build_object('n', n, 'first', to_char(first_at at time zone 'America/Costa_Rica', 'YYYY-MM-DD'),
                                                             'last', to_char(last_at at time zone 'America/Costa_Rica', 'YYYY-MM-DD'))) as pins
            from pins group by target_id
        )
        select coalesce(jsonb_agg(x order by last_at desc nulls last, x ->> 'created'), '[]')::text as j from (
          select jsonb_build_object(
                   'login', case when position('@' in coalesce(u.email, '')) > 0
                                 then left(split_part(u.email, '@', 1), 2) || '***@' || split_part(u.email, '@', 2) else '(no email)' end,
                   'created', left(to_jsonb(u) ->> 'created_at', 10),
                   'last_sign_in', left(to_jsonb(u) ->> 'last_sign_in_at', 10),
                   'kind', %s,
                   'phone_code_verified', %s,
                   'pins', coalesce(p.pins, '{}')) as x, p.last_at
            from (select * from auth.users order by created_at limit 40) u left join per_login p on p.target_id = u.id::text
          union all
          -- PINs typed on logins that no longer exist
          select jsonb_build_object('login', '(deleted login)', 'pins', jsonb_object_agg(action, jsonb_build_object('n', n,
                   'first', to_char(first_at at time zone 'America/Costa_Rica', 'YYYY-MM-DD'), 'last', to_char(last_at at time zone 'America/Costa_Rica', 'YYYY-MM-DD')))),
                 max(last_at)
            from (select action, sum(n) as n, min(first_at) as first_at, max(last_at) as last_at from pins
                   where not exists (select 1 from auth.users u where u.id::text = pins.target_id) group by action) d
          having count(*) > 0
        ) s $q$,
        case when to_regclass('public.app_accounts') is null then 'null'
             else '(select a.kind from public.app_accounts a where a.user_id = u.id)' end,
        case when to_regclass('auth.mfa_factors') is null then 'null'
             else 'exists (select 1 from auth.mfa_factors f where f.user_id = u.id and f.status::text = ''verified'')' end),
        false, true, '')))[1]::text, '&lt;', '<'), '&gt;', '>'), '&amp;', '&')::jsonb end,
  'team_roles', case when to_regclass('public.staff') is null then null else
      replace(replace(replace((xpath('/row/j/text()', query_to_xml($q$
        select coalesce(jsonb_object_agg(k, n), '{}')::text as j from (
          select coalesce(role, '?') || case when active then '' else ' (inactive)' end as k, count(*) as n from public.staff group by 1) r $q$,
        false, true, '')))[1]::text, '&lt;', '<'), '&gt;', '>'), '&amp;', '&')::jsonb end,
  -- structure and counts only: the text itself is never read out
  'orders_note', case when to_regclass('public.orders') is null then null else (
      select jsonb_build_object(
               'exists', a.attnum is not null,
               'position', a.attnum,
               'type', format_type(a.atttypid, a.atttypmod),
               'not_null', a.attnotnull,
               'default', pg_get_expr(d.adbin, d.adrelid),
               'comment', col_description(a.attrelid, a.attnum),
               'dropped_columns', (select count(*) from pg_attribute x where x.attrelid = to_regclass('public.orders') and x.attisdropped),
               'constraints_on_it', (select count(*) from pg_constraint c where c.conrelid = a.attrelid and a.attnum = any (c.conkey)),
               'orders_triggers', (select count(*) from pg_trigger t where t.tgrelid = to_regclass('public.orders') and not t.tgisinternal))
             || case when a.attnum is null then '{}'::jsonb else
                  replace(replace(replace((xpath('/row/j/text()', query_to_xml($q$
                    select jsonb_build_object(
                             'orders', count(*),
                             'orders_with_text', count(*) filter (where nullif(btrim(note::text), '') is not null),
                             'longest', max(length(note::text)),
                             'dates_with_text', to_char(min(created_at) filter (where nullif(btrim(note::text), '') is not null) at time zone 'America/Costa_Rica', 'YYYY-MM-DD')
                                                || ' → ' ||
                                                to_char(max(created_at) filter (where nullif(btrim(note::text), '') is not null) at time zone 'America/Costa_Rica', 'YYYY-MM-DD')
                           )::text as j from public.orders $q$,
                    false, true, '')))[1]::text, '&lt;', '<'), '&gt;', '>'), '&amp;', '&')::jsonb end
        from (select 1) one
        left join pg_attribute a on a.attrelid = to_regclass('public.orders') and a.attname = 'note' and not a.attisdropped
        left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum) end,
  -- the repository's body (supabase/accounts.sql) gives h 206861a3c597, h_ws aa2499233cf7, h_code 559f340e7bbd
  'audit_menu', (select jsonb_build_object(
        'exists', p.oid is not null,
        'h', left(md5(p.prosrc), 12),
        'h_ws', left(md5(btrim(regexp_replace(p.prosrc, '\s+', ' ', 'g'))), 12),
        'h_code', left(md5(lower(btrim(regexp_replace(regexp_replace(p.prosrc, '-{2}[^\n]*', '', 'g'), '\s+', ' ', 'g')))), 12),
        'length', length(p.prosrc),
        'security_definer', p.prosecdef,
        'settings', p.proconfig,
        'owner', pg_get_userbyid(p.proowner),
        'definition', pg_get_functiondef(p.oid),
        'triggers', (select coalesce(jsonb_agg(jsonb_build_object(
                        'table', (select n.nspname || '.' || c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace where c.oid = t.tgrelid),
                        'name', t.tgname, 'enabled', t.tgenabled::text, 'definition', pg_get_triggerdef(t.oid)) order by t.tgname), '[]')
                       from pg_trigger t where t.tgfoid = p.oid and not t.tgisinternal),
        -- month · first word of the summary · keys of details · who · whether name/price/available stayed the same
        'menu_log', case when to_regclass('public.audit_log') is null then null else
            replace(replace(replace((xpath('/row/j/text()', query_to_xml($q$
              select coalesce(jsonb_object_agg(k, n), '{}')::text as j from (
                select to_char(l.at, 'YYYY-MM') || ' · ' || split_part(coalesce(l.summary, ''), ' ', 1) || ' · ' ||
                       coalesce((select string_agg(x, ',' order by x) from jsonb_object_keys(case when jsonb_typeof(l.details) = 'object' then l.details else '{}'::jsonb end) x), '-') || ' · ' ||
                       case when l.manager_name is null then 'who=null' when l.manager_name = 'owner login' then 'who=owner login'
                            when l.manager_name like '%@%' then 'who=email' else 'who=other' end ||
                       case when (l.details -> 'before') is not null and l.details -> 'before' = l.details -> 'after' then ' · same name/price/available' else '' end as k,
                       count(*) as n
                  from public.audit_log l where l.action = 'menu_change' group by 1) m $q$,
              false, true, '')))[1]::text, '&lt;', '<'), '&gt;', '>'), '&amp;', '&')::jsonb end)
      from (select 1) one left join pg_proc p on p.oid = to_regprocedure('public.audit_menu()')),
  -- what migration 0015 needs: insert the receipts bucket, create and drop policies on storage.objects
  'storage_rights', jsonb_build_object(
      'account', current_user,
      'can_insert_buckets', case when to_regclass('storage.buckets') is null then null else has_table_privilege(to_regclass('storage.buckets'), 'INSERT') end,
      'member_of_storage_owner', (select pg_has_role(c.relowner, 'USAGE') from pg_class c where c.oid = to_regclass('storage.objects')),
      -- null when supautils is not there; read without failing whatever the setting holds
      'policy_grants_storage_objects', case
          when nullif(btrim(coalesce(current_setting('supautils.policy_grants', true), '')), '') is null then null
          when to_regprocedure('pg_input_is_valid(text, text)') is null then   -- PostgreSQL 15: no JSON check, read the text
            to_jsonb(current_setting('supautils.policy_grants', true) ~ ('"' || current_user || '"\s*:\s*\[[^]]*"storage\.objects"'))
          else (xpath('/row/j/text()', query_to_xml($q$
            select case when pg_input_is_valid(current_setting('supautils.policy_grants', true), 'jsonb')
                        then to_jsonb(coalesce((current_setting('supautils.policy_grants', true)::jsonb -> current_user::text) ? 'storage.objects', false))
                        else to_jsonb('not JSON'::text) end::text as j $q$, false, true, '')))[1]::text::jsonb end,
      'privileged_role', current_setting('supautils.privileged_role', true)),
  -- the tables production had before migration 0000
  'original_tables_triggers', (select coalesce(jsonb_agg(c.relname || ' · ' || t.tgname || ' · ' || pn.nspname || '.' || p.proname || '(' ||
                                   pg_get_function_identity_arguments(p.oid) || ') · ' || t.tgenabled::text order by c.relname, t.tgname), '[]')
      from pg_trigger t join pg_class c on c.oid = t.tgrelid join pg_namespace n on n.oid = c.relnamespace
      join pg_proc p on p.oid = t.tgfoid join pg_namespace pn on pn.oid = p.pronamespace
     where n.nspname = 'public' and not t.tgisinternal
       and c.relname in ('access_unlocks', 'app_accounts', 'app_settings', 'audit_log', 'board_group_slides', 'board_settings',
                         'chat_questions', 'discount_approvals', 'inventory_unlocks', 'menu_categories', 'menu_items', 'order_items',
                         'order_part_lines', 'orders', 'purchase_lines', 'purchase_orders', 'recipes', 'register_days', 'rooms',
                         'sales_unlocks', 'staff', 'stock_items', 'stock_moves', 'tab_adds', 'time_entries', 'vendors'))
)) as seguimiento;
