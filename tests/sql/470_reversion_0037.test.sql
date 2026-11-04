-- supabase/tools/reversion-0037.sql: undoes migration 0037 (the screens v2). The six functions 0037 changed go back to
-- their 0036 behaviour (_slide_json with \uXXXX escapes instead of the literal characters, D-063: checked by behaviour
-- and by its text, not byte for byte), _screen_item_json goes, _screen_template_places stays (the kind rule uses it);
-- the columns, the rows (a composition among them) and the Storage rules stay; the ledger is back at 36; the script
-- refuses while 0037 is not applied or while a later migration is; 0037 then applies again and finds everything.
begin;
select id as latte from public.menu_items where name = 'Latte' \gset
-- state made under 0037: the owner sets the v2 choices of the menu TV and makes a composition, a product slide and two
-- brand slides (one retired), each change logged
select test.login('cafe'); select test.unlock(test.staff('dueno'), '7391'); set role authenticated;
select test.eq(public.pantalla_guardar('{"id": "menu-1", "scale_pct": 125, "layout": "paginas", "density": "compacta", "english": "no", "promo_mode": "intercalar", "promo_every": 120, "promo_seconds": 8}') ->> 'ok',
               'true', 'the menu TV changed under 0037: the six choices of v2');
select public.diapositiva_guardar(jsonb_build_object('kind', 'marca', 'title_es', 'Café de altura', 'starts_at', now() - interval '1 hour',
                                                     'ends_at', now() + interval '20 days', 'sort', 1)) #>> '{slide,id}' as s_marca \gset
select public.diapositiva_guardar(jsonb_build_object('kind', 'producto', 'menu_item_id', :'latte', 'starts_at', now() - interval '1 hour',
                                                     'ends_at', now() + interval '20 days', 'sort', 2)) #>> '{slide,id}' as s_latte \gset
select public.diapositiva_guardar(jsonb_build_object('kind', 'composicion', 'template', '4-centro', 'kicker_es', 'Desayuno', 'dwell_seconds', 90, 'sort', 3,
                                                     'starts_at', now() - interval '1 hour', 'ends_at', now() + interval '20 days',
                                                     'zones', (select jsonb_agg(jsonb_build_object('mode', 'fija', 'entries', jsonb_build_array(jsonb_build_object('item', i.id))) order by u.o)
                                                                 from unnest(array['Latte', 'Tea', 'Banana Bread', 'Ham & Cheese']) with ordinality u(nm, o)
                                                                 join public.menu_items i on i.name = u.nm))) as r \gset
select test.eq((:'r'::jsonb) ->> 'ok', 'true', 'and a composition of four windows');
select (:'r'::jsonb) #>> '{slide,id}' as s_comp \gset
select public.diapositiva_guardar(jsonb_build_object('kind', 'marca', 'title_es', 'Ya no', 'starts_at', now() - interval '1 hour',
                                                     'ends_at', now() + interval '20 days')) #>> '{slide,id}' as s_old \gset
select test.eq(public.diapositiva_estado(:'s_old', 'retirada') ->> 'ok', 'true', 'and three more slides, one retired');
reset role;
select test.eq((select count(*)::int from public.screen_changes), 6, 'six changes logged');
select test.eq((select string_agg(coalesce(s ->> 'title_es', s #>> '{item,name}', s ->> 'kicker_es') || ':' || jsonb_array_length(s -> 'zones'), ' | ' order by o)
                  from jsonb_array_elements(public.pantalla_datos('menu-1') -> 'slides') with ordinality x(s, o)), 'Café de altura:0 | Latte:0 | Desayuno:4',
               'under 0037 the menu TV reads its slides (it intercalates promotions), the composition with its four zones');
-- the three tables, row for row; what existed before 0036; the functions by signature and by text; what a visitor runs
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
create function pg_temp.fns() returns text language sql as $$
  select coalesce(string_agg(p.oid::regprocedure::text, ' ' order by p.proname), '')
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname ~ '^(pantalla|diapositiva|_screen|_slide)' $$;
create function pg_temp.src() returns text language sql as $$
  select coalesce(string_agg(p.proname || ':' || md5(p.prosrc), ' ' order by p.proname), '')
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname ~ '^(pantalla|diapositiva|_screen|_slide)' $$;
create function pg_temp.body(f text) returns text language sql as $$ select prosrc from pg_proc where oid = f::regprocedure $$;
create function pg_temp.anon_definer() returns text language sql as $$
  select string_agg(p.proname, ' ' order by p.proname) from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and p.prorettype <> 'trigger'::regtype and p.prosecdef
     and has_function_privilege('anon', p.oid, 'execute') $$;
create function pg_temp.keys(j jsonb) returns text language sql as $$ select string_agg(k, ' ' order by k) from jsonb_object_keys(j) k $$;
create function pg_temp.policies() returns text language sql as $$
  select string_agg(policyname || ':' || left(md5(coalesce(qual, '') || coalesce(with_check, '')), 8), ' ' order by policyname)
    from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname like '%photos%' $$;
create function pg_temp.cols() returns text language sql as $$
  select string_agg(table_name || '.' || column_name || '=' || coalesce(column_default, '-'), ' ' order by table_name, ordinal_position)
    from information_schema.columns where table_schema = 'public'
     and ((table_name = 'screens' and column_name in ('layout', 'density', 'english', 'promo_mode', 'promo_every', 'promo_seconds'))
       or (table_name = 'screen_slides' and column_name in ('template', 'zones', 'dwell_seconds'))) $$;
select pg_temp.rows() as rows_before, pg_temp.fp() as fp_before, pg_temp.fns() as fns_0037, pg_temp.src() as src_0037, pg_temp.policies() as pol_before, pg_temp.cols() as cols_before \gset
select zones::text as zones_comp from public.screen_slides where id = :'s_comp' \gset
select test.eq(pg_temp.anon_definer(), 'canopy_schema_version order_status pantalla_datos place_room_order room_lookup', 'under 0037 a visitor runs pantalla_datos and nothing else new');
select test.eq((select string_agg(policyname || case when qual ~ '_screen_owner_any_device' then '*' else '' end, ' ' order by policyname)
                  from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname like '%photos%'),
               'menu photos owner write menu photos read screen photos owner write*', 'the three photo rules, the slides'' one with the owner''s check');

-- 0038 (the POS discounts) comes after: it is reverted first (each reversal refuses while a later migration is applied)
\o /dev/null
\ir ../../supabase/tools/reversion-0038.sql
\o
-- 1) a later migration is applied: the script stops at its first statement and changes nothing ------------------------------
insert into canopy.migrations (version, name) values (38, 'siguiente de prueba');
savepoint later;
\set ON_ERROR_STOP 0
\o /dev/null
\ir ../../supabase/tools/reversion-0037.sql
\o
\set ON_ERROR_STOP 1
-- the guard raised first; like one paste in the SQL Editor, every statement after it was refused ("transaction aborted")
\set later_state :LAST_ERROR_SQLSTATE
rollback to savepoint later;
select test.eq(:'later_state'::text, '25P02', 'with a later migration applied the script stops at its guard: nothing after it ran');
select test.eq(pg_temp.src(), :'src_0037', 'every function is as 0037 left it, byte for byte');
select test.eq((select string_agg(version::text, ' ' order by version) from canopy.migrations where version >= 35), '35 36 37 38', 'and the ledger is as it was');
delete from canopy.migrations where version = 38;

-- 2) the reversal ---------------------------------------------------------------------------------------------------------
\o /dev/null
\ir ../../supabase/tools/reversion-0037.sql
\o
select test.eq(public.canopy_schema_version(), 36, 'the database is back at version 36');
select test.eq((select string_agg(version::text, ' ' order by version) from canopy.migrations where version >= 35), '35 36', 'the ledger: 37 gone, 36 kept');
select test.eq(pg_temp.fns(), '_screen_actor() _screen_changes_immutable() _screen_hhmm(text) _screen_json(screens) _screen_log(text,text,text,text,jsonb,jsonb) _screen_owner_any_device() '
               || '_screen_template_places(text) _screen_text_problem(text) _slide_json(screen_slides) diapositiva_estado(uuid,text) diapositiva_guardar(jsonb) pantalla_datos(text) pantalla_guardar(jsonb) pantallas_estado()',
               'the thirteen functions of 0036 and the template helper; _screen_item_json is gone');
select test.ok(to_regprocedure('public._screen_item_json(uuid)') is null, 'by name: the product helper is gone');
select test.ok((select pg_get_constraintdef(oid) ~ '_screen_template_places' from pg_constraint where conname = 'screen_slides_kind' and conrelid = 'public.screen_slides'::regclass),
               'the template helper stays because the kind rule still uses it');
select test.ok(not has_function_privilege('anon', 'public._screen_template_places(text)', 'execute') and not has_function_privilege('authenticated', 'public._screen_template_places(text)', 'execute'),
               'and stays closed to visitors and logins');
-- the six functions by their text: nothing of v2 left; _slide_json with escapes, never a literal invisible character
select test.ok(pg_temp.body('public._screen_json(public.screens)') !~ '(layout|density|english|promo)', '_screen_json knows nothing of the six choices');
select test.ok(pg_temp.body('public._slide_json(public.screen_slides)') !~ '(zones|template|dwell|usable|_screen_item_json)', '_slide_json knows nothing of a composition');
select test.ok(pg_temp.body('public._slide_json(public.screen_slides)') ~ ('\\' || 'u00a0') and pg_temp.body('public._slide_json(public.screen_slides)') !~ '[   -‏    　﻿]',
               'its blank rule is written with \uXXXX escapes (D-063): the text survives a paste');
select test.ok(pg_temp.body('public.pantalla_datos(text)') !~ '(promo_mode|composicion|usable)', 'pantalla_datos knows nothing of promotions in the menu TV or of compositions');
select test.ok(pg_temp.body('public.pantalla_guardar(jsonb)') !~ '(layout|density|english|promo_mode|promo_every|promo_seconds)', 'pantalla_guardar knows nothing of the six choices');
select test.ok(pg_temp.body('public.diapositiva_guardar(jsonb)') !~ '(composicion|zones|template|dwell)', 'diapositiva_guardar knows nothing of a composition');
select test.ok(pg_temp.body('public.diapositiva_estado(uuid, text)') !~ '(composicion|template)', 'diapositiva_estado knows nothing of a composition (its summary knows titles and products only)');
select test.eq((select string_agg(p.proname, ' ' order by p.proname) from pg_proc p
                 where p.pronamespace = 'public'::regnamespace and p.proname ~ '^(pantalla|diapositiva|_screen|_slide)' and has_function_privilege('authenticated', p.oid, 'execute')),
               '_screen_owner_any_device diapositiva_estado diapositiva_guardar pantalla_datos pantalla_guardar pantallas_estado', 'a login may call what it could under 0036, nothing else');
select test.eq(pg_temp.anon_definer(), 'canopy_schema_version order_status pantalla_datos place_room_order room_lookup', 'a visitor runs exactly what it ran');
select test.eq((select string_agg(p.proname, ' ' order by p.proname) from pg_proc p
                 where p.pronamespace = 'public'::regnamespace and p.proname ~ '^(pantalla|diapositiva|_screen|_slide)' and p.prosecdef),
               '_screen_actor _screen_log _screen_owner_any_device diapositiva_estado diapositiva_guardar pantalla_datos pantalla_guardar pantallas_estado', 'the owner-rights functions as in 0036');
select test.eq((select count(*)::int from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname ~ '^(pantalla|diapositiva|_screen|_slide)'
                   and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c = 'search_path=public')), 0, 'every one of them fixes its search path');
-- what the pages see now: the 0036 shapes
select test.eq(pg_temp.keys((select public._screen_json(s) from public.screens s where id = 'menu-1')),
               'active category_ids distance_m id inches kind look name on_from on_to page_seconds scale_pct slide_seconds sold_out turn updated_at', 'a TV as 0036 read it: 16 keys, no layout, no promotions');
select test.eq(pg_temp.keys((select public._slide_json(d) from public.screen_slides d where id = :'s_comp')),
               'body_en body_es days ends_at from_time id item kicker_en kicker_es kind link menu_item_id photo_url screen_ids sort starts_at status title_en title_es to_time',
               'a slide as 0036 read it: 21 keys, no zones, no template, no dwell, no usable (the composition included)');
select test.eq((select promo_mode || ' ' || layout from public.screens where id = 'menu-1'), 'intercalar paginas', 'the menu TV''s row keeps intercalar and paginas…');
select test.eq(public.pantalla_datos('menu-1') -> 'slides', '[]'::jsonb, '…but under 0036 the menu TV gets no slides at all');
select test.eq((select string_agg(coalesce(s ->> 'title_es', s #>> '{item,name}', s ->> 'kicker_es') || ':' || (s ->> 'kind') || ':' || (s ? 'zones')::text || ':' || coalesce(s ->> 'item', 'null'), ' | ' order by o)
                  from jsonb_array_elements(public.pantalla_datos('promos-1') -> 'slides') with ordinality x(s, o)),
               'Café de altura:marca:false:null | Latte:producto:false:' || (select (public._slide_json(d) ->> 'item') from public.screen_slides d where id = :'s_latte') || ' | Desayuno:composicion:false:null',
               'the promotions TV lists the composition by its kind without zones (the published pages ignore a kind they do not know); the product carries its item as in 0036');
-- the tables: columns, rows, rules, rights
select test.eq(pg_temp.cols(), :'cols_before', 'the nine columns of 0037 stay, with their defaults');
select test.eq(pg_temp.rows(), :'rows_before', 'every row, byte for byte (the TVs with their v2 choices, the slides, the composition, the retired one, the log)');
select test.eq((select template || ' ' || zones::text from public.screen_slides where id = :'s_comp'), '4-centro ' || :'zones_comp', 'the composition keeps its template and its zones');
select test.eq(pg_temp.fp(), :'fp_before', 'nothing that existed before 0036 changed (menu, categories, current TV, group slides, general log)');
select test.eq(pg_temp.policies(), :'pol_before', 'the three Storage rules exactly as they were (the reversal of 0037 touches no rule)');
select test.ok((select bool_and(c.relrowsecurity) from pg_class c where c.oid in ('public.screens'::regclass, 'public.screen_slides'::regclass, 'public.screen_changes'::regclass))
               and not exists (select 1 from unnest(array['anon', 'authenticated']) r, unnest(array['public.screens', 'public.screen_slides', 'public.screen_changes']) t
                                where has_table_privilege(r, t, 'select,insert,update,delete,truncate,references,trigger'))
               and (select count(*) from pg_policies where schemaname = 'public' and tablename in ('screens', 'screen_slides', 'screen_changes')) = 0,
               'and they stay closed: row security, no rule, no right for visitors or logins');
select test.eq((select string_agg(conname, ' ' order by conname) from pg_constraint
                 where conrelid in ('public.screens'::regclass, 'public.screen_slides'::regclass) and conname ~ 'layout|density|english|promo|dwell|template|kind'),
               'screen_slides_dwell_seconds_check screen_slides_kind screen_slides_kind_check screen_slides_template_check screens_density_check screens_english_check '
               || 'screens_kind_check screens_layout_check screens_promo_every_check screens_promo_mode_check screens_promo_seconds_check', 'the widened rules stay (a composition row must keep passing them)');
select test.throws($$delete from public.screen_changes$$, 'screen_changes_immutable', 'the change log still cannot be deleted');
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
select test.eq((:'rc'::jsonb) -> 'migrations_missing', '[37, 38]'::jsonb, 'release-check.sql: 37 (and 38, reverted first) are missing');
select test.eq((:'rc'::jsonb) -> 'functions_missing', '["descuento_autorizar", "descuento_caja_quitar", "descuento_caja_reanudar", "descuento_caja_registrar", "descuento_caja_volver", "descuento_cajas", "descuento_cupo_devolver", "descuento_estado", "descuento_liberar", "descuento_quitar_cuenta", "descuentos_informe"]'::jsonb, 'no function of the screens is missing (the five are back in their 0036 form; only the eleven of 0038, reverted first)');
select test.eq((:'rc'::jsonb) -> 'anon_can_run', '["canopy_schema_version", "order_status", "pantalla_datos", "place_room_order", "room_lookup"]'::jsonb, 'and a visitor runs what 0036 allowed');
select test.eq((:'rc'::jsonb) -> 'storage_policies_missing', '[]'::jsonb, 'no Storage rule is missing');
-- the 0036 behaviour of the writers, as the owner
select test.login('cafe'); select test.unlock(test.staff('dueno'), '7391'); set role authenticated;
select public.pantalla_guardar('{"id": "menu-1", "layout": "auto", "promo_mode": "no", "scale_pct": 110}') as r \gset
select test.eq((:'r'::jsonb) ->> 'ok' || ' ' || ((:'r'::jsonb) #>> '{tv,scale_pct}') || ' ' || ((:'r'::jsonb) -> 'tv' ? 'layout')::text, 'true 110 false',
               'pantalla_guardar saves as 0036 did; a v2 choice given is ignored, not refused, and the answer has no v2 key');
select test.eq(public.diapositiva_guardar(jsonb_build_object('kind', 'composicion', 'template', '1', 'starts_at', now(), 'ends_at', now() + interval '1 day',
                                                             'zones', jsonb_build_array(jsonb_build_object('entries', jsonb_build_array(jsonb_build_object('item', :'latte')))))) ->> 'error' || '/'
               || (public.diapositiva_guardar(jsonb_build_object('kind', 'composicion', 'template', '1', 'starts_at', now(), 'ends_at', now() + interval '1 day')) ->> 'field'),
               'invalid/kind', 'diapositiva_guardar refuses a new composition: invalid/kind');
select test.eq(public.diapositiva_guardar(jsonb_build_object('id', :'s_comp', 'kicker_es', 'Desayunos')) ->> 'error' || '/' || (public.diapositiva_guardar(jsonb_build_object('id', :'s_comp', 'kicker_es', 'Desayunos')) ->> 'field'),
               'invalid/kind', 'and a change to the saved one (its kind is unknown to 0036)');
select test.eq(public.diapositiva_guardar(jsonb_build_object('kind', 'marca', 'title_es', 'En la A', 'starts_at', now(), 'ends_at', now() + interval '1 day', 'screen_ids', '["menu-1"]'::jsonb)) ->> 'field',
               'screen_ids', 'a slide may name only a promotions TV again');
select test.eq(public.diapositiva_estado(:'s_comp', 'pausada') ->> 'ok', 'true', 'diapositiva_estado (back to the 0036 text) still pauses the composition');
select test.eq(jsonb_array_length(public.pantallas_estado() -> 'slides') || ' ' || ((select s ? 'zones' from jsonb_array_elements(public.pantallas_estado() -> 'slides') s where s ->> 'id' = :'s_comp')::text),
               '4 false', 'pantallas_estado lists every slide, the composition without its zones');
reset role;
select test.eq((select promo_mode || ' ' || layout || ' ' || scale_pct from public.screens where id = 'menu-1'), 'intercalar paginas 110', 'the row keeps the v2 choices it had: 0036''s function neither reads nor writes them');
select test.eq((select count(*)::int from public.screen_changes), 8, 'the log goes on: 6 + a TV change + a pause');
select test.ok((select after::text !~ '(layout|promo)' from public.screen_changes where target_kind = 'tv' order by id desc limit 1), 'logged in the 0036 form, without the v2 choices');
-- what the pages see: the menu as it was; the café sells as usual
select test.login('anon'); set role anon;
select test.eq((select count(*)::int from public.menu_items where name = 'Latte' and price_crc = 2200), 1, 'the menu reads as before');
reset role;
select test.login('cafe'); set role authenticated;
select test.eq(public.pos_record_sale(jsonb_build_object('id', '0d000000-0000-4000-8000-000000004701', 'total_crc', 2200, 'payment_method', 'card',
       'items', jsonb_build_array(jsonb_build_object('id', gen_random_uuid(), 'item_name', 'Latte', 'price_crc', 2200, 'qty', 1, 'menu_item_id', :'latte'))))->>'ok',
       'true', 'the café sells as usual');
reset role;
select pg_temp.rows() as rows_mid, pg_temp.src() as src_0036 \gset

-- 3) 0037 not applied: the script refuses with its message and changes nothing ---------------------------------------------
\set ON_ERROR_STOP 0
\set ON_ERROR_ROLLBACK on
\o /dev/null
\ir ../../supabase/tools/reversion-0037.sql
\o
\set ON_ERROR_ROLLBACK off
\set ON_ERROR_STOP 1
select test.ok(:'LAST_ERROR_MESSAGE' ~ '^La migración 0037 no está aplicada: no hay nada que revertir\. No se cambió nada\.$',
               'run again: «La migración 0037 no está aplicada: no hay nada que revertir»');
select test.eq(public.canopy_schema_version(), 36, 'still at version 36');
select test.eq(pg_temp.src(), :'src_0036', 'the functions untouched');
select test.eq(pg_temp.rows(), :'rows_mid', 'and the tables untouched');

-- 4) 0037 applies again and finds everything as it was ----------------------------------------------------------------------
\o /dev/null
\ir ../../supabase/migrations/0037_pantallas_v2.sql
\o
select test.eq(public.canopy_schema_version(), 37, 'applied again: version 37');
select test.eq(pg_temp.fns(), :'fns_0037', 'with every function, the fifteen');
select test.eq(pg_temp.src(), :'src_0037', 'each one byte for byte as the first time');
select test.eq(pg_temp.rows(), :'rows_mid', 'the tables and rows exactly as the reversal left them (no column or row is added twice)');
select test.eq(pg_temp.cols() || ' ' || pg_temp.policies(), :'cols_before' || ' ' || :'pol_before', 'the columns and the Storage rules as they were');
select test.eq(pg_temp.anon_definer(), 'canopy_schema_version order_status pantalla_datos place_room_order room_lookup', 'a visitor runs pantalla_datos and nothing else new');
select test.eq((select string_agg(tgname, ' ' order by tgname) from pg_trigger where tgrelid = 'public.screen_changes'::regclass and not tgisinternal),
               'screen_changes_immutable screen_changes_no_truncate', 'the log''s guard once, not twice');
select test.login('anon'); set role anon;
select test.eq((select string_agg(coalesce(s ->> 'title_es', s #>> '{item,name}', s ->> 'kicker_es') || ':' || jsonb_array_length(s -> 'zones'), ' | ' order by o)
                  from jsonb_array_elements(public.pantalla_datos('menu-1') -> 'slides') with ordinality x(s, o)), 'Café de altura:0 | Latte:0',
               'the menu TV reads its slides again (intercalar kept): the composition is paused, so not yet');
select test.eq(public.pantalla_datos('menu-1') #>> '{tv,layout}' || ' ' || (public.pantalla_datos('menu-1') #>> '{tv,scale_pct}'), 'paginas 110', 'and its v2 choices as the owner left them');
reset role;
select test.login('cafe'); select test.unlock(test.staff('dueno'), '7391'); set role authenticated;
select test.eq(public.diapositiva_estado(:'s_comp', 'activa') ->> 'ok', 'true', 'the owner resumes the composition…');
select public.diapositiva_guardar(jsonb_build_object('id', :'s_comp', 'kicker_es', 'Desayunos')) as r \gset
select test.eq((:'r'::jsonb) ->> 'ok' || ' ' || ((:'r'::jsonb) #>> '{slide,kicker_es}') || ' ' || ((:'r'::jsonb) #>> '{slide,usable}') || ' ' || ((:'r'::jsonb) #>> '{slide,zones,0,entries,0,item,name}'), 'true Desayunos true Latte',
               '…and changes it again, with its zones resolved live');
select test.eq(public.diapositiva_estado(:'s_old', 'activa') ->> 'error', 'retired', 'a slide retired before the reversal stays retired');
select test.eq(jsonb_array_length(public.pantallas_estado() -> 'changes') || ' ' || (public.pantallas_estado() -> 'changes' -> 0 ->> 'summary'), '10 composición · 4-centro', 'the log goes on from where it was: 8 + 2, the composition summarised again');
reset role;
select test.login('anon'); set role anon;
select test.eq((select string_agg(coalesce(s ->> 'title_es', s #>> '{item,name}', s ->> 'kicker_es') || ':' || jsonb_array_length(s -> 'zones'), ' | ' order by o)
                  from jsonb_array_elements(public.pantalla_datos('menu-1') -> 'slides') with ordinality x(s, o)), 'Café de altura:0 | Latte:0 | Desayunos:4',
               'the composition is back on the menu TV with its four zones');
reset role;
select test.done();
rollback;
