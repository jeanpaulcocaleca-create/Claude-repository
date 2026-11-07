-- supabase/tools/reversion-0036.sql: undoes migration 0036 (the customer screens). Every function of 0036 goes, except the
-- change log's guard; the three tables stay with every row (and closed); the database is back at version 35; the script
-- refuses while 0036 is not applied or while a later migration is; 0036 can then be applied again, finding everything.
begin;
select id as latte from public.menu_items where name = 'Latte' \gset
-- state made under 0036: the owner changes a TV and makes slides (one retired), each change logged
select test.login('cafe'); select test.unlock(test.staff('dueno'), '7391'); set role authenticated;
select test.eq(public.pantalla_guardar('{"id": "menu-1", "scale_pct": 125, "look": "dia"}') ->> 'ok', 'true', 'a TV changed under 0036');
select public.diapositiva_guardar(jsonb_build_object('kind', 'marca', 'title_es', 'Café de altura', 'starts_at', now() - interval '1 hour',
                                                     'ends_at', now() + interval '20 days', 'sort', 1)) #>> '{slide,id}' as s_marca \gset
select public.diapositiva_guardar(jsonb_build_object('kind', 'producto', 'menu_item_id', :'latte', 'starts_at', now() - interval '1 hour',
                                                     'ends_at', now() + interval '20 days', 'sort', 2)) #>> '{slide,id}' as s_latte \gset
select public.diapositiva_guardar(jsonb_build_object('kind', 'marca', 'title_es', 'Ya no', 'starts_at', now() - interval '1 hour',
                                                     'ends_at', now() + interval '20 days')) #>> '{slide,id}' as s_old \gset
select test.eq(public.diapositiva_estado(:'s_old', 'retirada') ->> 'ok', 'true', 'and three slides, one retired');
reset role;
select test.eq((select count(*)::int from public.screen_changes), 5, 'five changes logged');
-- the three tables, row for row, and what existed before 0036
create function pg_temp.rows() returns text language sql as $$
  select concat_ws(' ',
    (select count(*) || ':' || md5(string_agg(t::text, ',' order by t.id)) from public.screens t),
    (select count(*) || ':' || md5(string_agg(t::text, ',' order by t.id)) from public.screen_slides t),
    (select count(*) || ':' || md5(string_agg(t::text, ',' order by t.id)) from public.screen_changes t)) $$;
create function pg_temp.fp() returns text language sql as $$
  select concat_ws(' ',
    (select count(*) || ':' || md5(string_agg(t::text, ',' order by t.id)) from public.menu_items t),
    (select count(*) || ':' || md5(string_agg(t::text, ',' order by t.id)) from public.menu_categories t),
    (select count(*) || ':' || coalesce(md5(string_agg(t::text, ',' order by t.id)), '-') from public.board_settings t),
    (select count(*) || ':' || coalesce(md5(string_agg(t::text, ',' order by t.id)), '-') from public.board_group_slides t),
    (select count(*) || ':' || coalesce(md5(string_agg(t::text, ',' order by t.id)), '-') from public.audit_log t)) $$;
-- every function of 0036 that is still there, by signature
create function pg_temp.fns() returns text language sql as $$
  select coalesce(string_agg(p.oid::regprocedure::text, ' ' order by p.proname), '')
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname ~ '^(pantalla|diapositiva|_screen|_slide)' $$;
-- what a visitor may run with the owner's rights (the same reading as release-check.sql's anon_can_run)
create function pg_temp.anon_definer() returns text language sql as $$
  select string_agg(p.proname, ' ' order by p.proname) from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and p.prorettype <> 'trigger'::regtype and p.prosecdef
     and has_function_privilege('anon', p.oid, 'execute') $$;
select pg_temp.rows() as rows_before, pg_temp.fp() as fp_before, pg_temp.fns() as fns_0036 \gset
select test.eq(pg_temp.anon_definer(), 'canopy_schema_version order_status pantalla_datos place_room_order room_lookup', 'under 0036 a visitor runs pantalla_datos too');

-- 0038 (the POS discounts), 0039 and 0040 (Proveedores) come after: they are reverted first (each reversal refuses while a
-- later migration is applied)
\o /dev/null
\ir ../../supabase/tools/reversion-0040.sql
\ir ../../supabase/tools/reversion-0039.sql
\ir ../../supabase/tools/reversion-0038.sql
\o
-- 1) a later migration is applied: the script stops at its first statement and changes nothing ------------------------------
insert into canopy.migrations (version, name) values (38, 'siguiente de prueba');
savepoint later;
\set ON_ERROR_STOP 0
\o /dev/null
\ir ../../supabase/tools/reversion-0036.sql
\o
\set ON_ERROR_STOP 1
-- the guard raised first; like one paste in the SQL Editor, every statement after it was refused ("transaction aborted")
\set later_state :LAST_ERROR_SQLSTATE
rollback to savepoint later;
select test.eq(:'later_state'::text, '25P02', 'with a later migration applied the script stops at its guard: nothing after it ran');
select test.eq(pg_temp.fns(), :'fns_0036', 'every function of 0036 is still there');
select test.eq((select string_agg(version::text, ' ' order by version) from canopy.migrations where version >= 35), '35 36 37 38', 'and the ledger is as it was');
delete from canopy.migrations where version = 38;

-- 2) the reversal ---------------------------------------------------------------------------------------------------------
\o /dev/null
\ir ../../supabase/tools/reversion-0037.sql
\ir ../../supabase/tools/reversion-0036.sql
\o
select test.eq(public.canopy_schema_version(), 35, 'the database is back at version 35');
select test.eq(pg_temp.fns(), '_screen_changes_immutable() _screen_template_places(text)', 'every function of 0036 is gone but the change log''s guard (and 0037''s template helper, kept by its reversal because the kind rule uses it)');
select test.ok(to_regprocedure('public.pantalla_datos(text)') is null and to_regprocedure('public.pantallas_estado()') is null
               and to_regprocedure('public.pantalla_guardar(jsonb)') is null and to_regprocedure('public.diapositiva_guardar(jsonb)') is null
               and to_regprocedure('public.diapositiva_estado(uuid, text)') is null
               and to_regprocedure('public._screen_log(text, text, text, text, jsonb, jsonb)') is null
               and to_regprocedure('public._slide_json(public.screen_slides)') is null and to_regprocedure('public._screen_json(public.screens)') is null
               and to_regprocedure('public._screen_text_problem(text)') is null and to_regprocedure('public._screen_owner_any_device()') is null
               and to_regprocedure('public._screen_actor()') is null and to_regprocedure('public._screen_hhmm(text)') is null,
               'by name: the TVs'' reading, the management and the helpers');
select test.eq((select string_agg(policyname, ' ' order by policyname) from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname like '%photos%'),
               'menu photos owner write menu photos read', 'the Storage rules as before the 0036: one writing rule for the whole bucket, none for pantallas/');
select test.ok((select qual !~ 'pantallas' from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'menu photos owner write'),
               'and that rule covers the whole bucket again');
select test.eq(pg_temp.anon_definer(), 'canopy_schema_version order_status place_room_order room_lookup', 'a visitor runs exactly what it ran before 0036');
select test.ok(to_regclass('public.screens') is not null and to_regclass('public.screen_slides') is not null and to_regclass('public.screen_changes') is not null,
               'the three tables stay');
select test.eq(pg_temp.rows(), :'rows_before', 'with every row, byte for byte (the TVs, the slides, the retired one, the log)');
select test.eq(pg_temp.fp(), :'fp_before', 'nothing that existed before 0036 changed (menu, categories, current TV, group slides, general log)');
select test.ok((select bool_and(c.relrowsecurity) from pg_class c where c.oid in ('public.screens'::regclass, 'public.screen_slides'::regclass, 'public.screen_changes'::regclass))
               and not exists (select 1 from unnest(array['anon', 'authenticated']) r, unnest(array['public.screens', 'public.screen_slides', 'public.screen_changes']) t
                                where has_table_privilege(r, t, 'select,insert,update,delete,truncate,references,trigger'))
               and (select count(*) from pg_policies where schemaname = 'public' and tablename in ('screens', 'screen_slides', 'screen_changes')) = 0,
               'and they stay closed: row security, no rule, no right for visitors or logins');
select test.ok(has_table_privilege('canopy_backup', 'public.screens', 'select') and has_table_privilege('canopy_backup', 'public.screen_slides', 'select')
               and has_table_privilege('canopy_backup', 'public.screen_changes', 'select'), 'the backup account still reads them');
select test.throws($$delete from public.screen_changes$$, 'screen_changes_immutable', 'the change log still cannot be deleted');
select test.throws($$truncate public.screen_changes$$, 'screen_changes_immutable', 'nor truncated');
select test.throws($$update public.screen_changes set summary = 'x'$$, 'screen_changes_immutable', 'nor changed');
-- what the pages see now: the TVs' reading is gone (they fall back to their address settings), the menu is as it was
select test.login('anon'); set role anon;
select test.throws($$select public.pantalla_datos('promos-1')$$, 'does not exist', 'a TV asking for its data gets "no such function" (the page falls back)');
select test.eq((select count(*)::int from public.menu_items where name = 'Latte' and price_crc = 2200), 1, 'the menu reads as before');
reset role;
select test.login('cafe'); set role authenticated;
select test.eq(public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000004501', 'total_crc', 2200, 'payment_method', 'card',
       'items', jsonb_build_array(jsonb_build_object('id', gen_random_uuid(), 'item_name', 'Latte', 'price_crc', 2200, 'qty', 1, 'menu_item_id', :'latte'))))->>'ok',
       'true', 'the café sells as usual');
reset role;
-- the release check says what the header says
\set rc_file `mktemp`
\pset format unaligned
\pset tuples_only on
\o :rc_file
\ir ../../supabase/tools/release-check.sql
\o
\set rc `cat :'rc_file'`
\pset tuples_only off
\pset format aligned
select test.eq((:'rc'::jsonb) -> 'migrations_missing', '[36, 37, 38, 39, 40]'::jsonb, 'release-check.sql: 36, 37, 38, 39 and 40 are missing');
select test.eq((:'rc'::jsonb) -> 'functions_missing', '["descuento_autorizar", "descuento_caja_quitar", "descuento_caja_reanudar", "descuento_caja_registrar", "descuento_caja_volver", "descuento_cajas", "descuento_cupo_devolver", "descuento_estado", "descuento_liberar", "descuento_quitar_cuenta", "descuentos_informe", "diapositiva_estado", "diapositiva_guardar", "pantalla_datos", "pantalla_guardar", "pantallas_estado", "proveedor_anticipos_aplicar", "proveedor_borrador_descartar", "proveedor_borrador_guardar", "proveedor_factura_anular", "proveedor_factura_registrar", "proveedor_ficha", "proveedor_guardar", "proveedor_historial", "proveedor_pago_anular", "proveedor_pago_registrar", "proveedor_pedido", "proveedor_pedido_asignar", "proveedor_pedido_cancelar", "proveedor_pedido_cerrar", "proveedor_pedido_confirmar", "proveedor_pedido_crear", "proveedor_pedido_editar", "proveedor_producto_guardar", "proveedor_recepcion_corregir", "proveedor_recibir", "proveedores_alertas", "proveedores_bitacora", "proveedores_lista", "proveedores_por_recibir", "turno_aqui", "turno_desde_caja", "turno_estado", "turno_terminar"]'::jsonb,
               'and the five functions of the screens (and the eleven of 0038, reverted first)');
select test.eq((:'rc'::jsonb) -> 'anon_can_run', '["canopy_schema_version", "order_status", "place_room_order", "room_lookup"]'::jsonb,
               'and a visitor runs only what it ran before');

-- 3) 0036 not applied: the script refuses with its message and changes nothing ---------------------------------------------
\set ON_ERROR_STOP 0
\set ON_ERROR_ROLLBACK on
\o /dev/null
\ir ../../supabase/tools/reversion-0036.sql
\o
\set ON_ERROR_ROLLBACK off
\set ON_ERROR_STOP 1
select test.ok(:'LAST_ERROR_MESSAGE' ~ '^La migración 0036 no está aplicada: no hay nada que revertir\. No se cambió nada\.$',
               'run again: «La migración 0036 no está aplicada: no hay nada que revertir»');
select test.eq(public.canopy_schema_version(), 35, 'still at version 35');
select test.eq(pg_temp.rows(), :'rows_before', 'and the tables are untouched');

-- 4) 0036 and then 0037 apply again and find everything as it was ---------------------------------------------------------
\o /dev/null
\ir ../../supabase/migrations/0036_pantallas.sql
\ir ../../supabase/migrations/0037_pantallas_v2.sql
\o
select test.eq(public.canopy_schema_version(), 37, 'applied again: version 37');
select test.eq(pg_temp.fns(), :'fns_0036', 'with every function, the same ten');
select test.eq(pg_temp.rows(), :'rows_before', 'the tables and rows exactly as the reversal left them (the two TVs are not seeded twice)');
select test.eq(pg_temp.anon_definer(), 'canopy_schema_version order_status pantalla_datos place_room_order room_lookup', 'a visitor runs pantalla_datos again');
select test.eq((select string_agg(tgname, ' ' order by tgname) from pg_trigger where tgrelid = 'public.screen_changes'::regclass and not tgisinternal),
               'screen_changes_immutable screen_changes_no_truncate', 'the log''s guard once, not twice');
select test.login('anon'); set role anon;
select test.eq((select string_agg(coalesce(s ->> 'title_es', s #>> '{item,name}'), ' | ' order by o)
                  from jsonb_array_elements(public.pantalla_datos('promos-1') -> 'slides') with ordinality x(s, o)), 'Café de altura | Latte',
               'the promotions TV shows the slides that were there (the retired one stays retired)');
select test.eq(public.pantalla_datos('menu-1') #>> '{tv,scale_pct}', '125', 'and the menu TV keeps the owner''s settings');
reset role;
select test.login('cafe'); select test.unlock(test.staff('dueno'), '7391'); set role authenticated;
select test.eq(public.diapositiva_estado(:'s_marca', 'pausada') ->> 'ok', 'true', 'the owner manages them again');
select test.eq(public.diapositiva_estado(:'s_old', 'activa') ->> 'error', 'retired', 'a slide retired before the reversal stays retired');
select test.eq(jsonb_array_length(public.pantallas_estado() -> 'changes'), 6, 'and the log goes on from where it was: 5 + 1');
reset role;
select test.done();
rollback;
