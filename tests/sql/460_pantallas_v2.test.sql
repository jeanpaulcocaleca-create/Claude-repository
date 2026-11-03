-- Migration 0037 (docs/PANTALLAS.md, D-064): the screens v2. Six choices per TV, each with a default and a range; a
-- slide of kind «composicion» (a template of 1 to 4 zones, each a fixed photo or a presentation of its own, every
-- entry a product read live from the menu or a photo); the menu TV reads its slides only while it intercalates
-- promotions; the log keeps the zones as written (ids, never names or prices); every right of 0036 stays as it was.
begin;
select id as latte from public.menu_items where name = 'Latte' \gset
select id as tea from public.menu_items where name = 'Tea' \gset
select id as bread from public.menu_items where name = 'Banana Bread' \gset
select id as ham from public.menu_items where name = 'Ham & Cheese' \gset
select id as shot from public.menu_items where name = 'Flavor shot' \gset
select id as combo from public.menu_items where name ~ '^Combo discount' \gset
select 'a0000000-0000-4000-8000-000000000001' as cat_coffee, 'a0000000-0000-4000-8000-000000000009' as cat_extras,
       '1b000000-0000-4000-8000-000000004601' as temp_item \gset
-- an item the test deletes later (as the Menu Manager may)
insert into public.menu_items (id, category_id, name, price_crc) values (:'temp_item', :'cat_coffee', 'Café de prueba 460', 1900);

-- the unlocks first (each one writes its own log line): everything below must write nothing outside the screens' tables
select test.login('cafe'); set role authenticated;
select set_config('test.h_ana', test.unlock(test.staff('ana'), '4826')::text, false) \g /dev/null
select test.login('cafe'); select set_config('test.h_dueno', test.unlock(test.staff('dueno'), '7391')::text, false) \g /dev/null
reset role;

-- every write outside the three screens' tables in this transaction, per table, and fingerprints of what the screens read
create function pg_temp.writes() returns jsonb language sql as $$
  select coalesce(jsonb_object_agg(schemaname || '.' || relname, n_tup_ins + n_tup_upd + n_tup_del), '{}')
    from pg_stat_xact_all_tables
   where schemaname in ('public', 'canopy', 'acct', 'auth', 'storage')
     and relname not in ('screens', 'screen_slides', 'screen_changes') and n_tup_ins + n_tup_upd + n_tup_del > 0 $$;
create function pg_temp.fp() returns text language sql as $$
  select concat_ws(' ',
    (select count(*) || ':' || md5(string_agg(t::text, ',' order by t.id)) from public.menu_items t),
    (select count(*) || ':' || md5(string_agg(t::text, ',' order by t.id)) from public.menu_categories t),
    (select count(*) || ':' || coalesce(md5(string_agg(t::text, ',' order by t.id)), '-') from public.board_settings t),
    (select count(*) || ':' || coalesce(md5(string_agg(t::text, ',' order by t.id)), '-') from public.board_group_slides t),
    (select count(*) || ':' || coalesce(md5(string_agg(t::text, ',' order by t.id)), '-') from public.app_settings t),
    (select count(*) || ':' || coalesce(md5(string_agg(t::text, ',' order by t.id)), '-') from public.audit_log t)) $$;
select pg_temp.writes()::text as writes_before, pg_temp.fp() as fp_before \gset

-- the owner's writes, each with what it logged (read back through pantallas_estado), as 440 does
create function pg_temp.nlog() returns int language sql as $$ select jsonb_array_length(public.pantallas_estado() -> 'changes') $$;
create function pg_temp.logged(r jsonb, n0 int) returns jsonb language plpgsql as $$
declare n1 int := pg_temp.nlog();
begin
  return r || jsonb_build_object('_logged', n1 - n0, '_log', case when n1 > n0 then public.pantallas_estado() -> 'changes' -> 0 end);
end $$;
create function pg_temp.tv(p jsonb) returns jsonb language plpgsql as $$
declare n0 int := pg_temp.nlog(); r jsonb;
begin r := public.pantalla_guardar(p); return pg_temp.logged(r, n0); end $$;
create function pg_temp.slide(p jsonb) returns jsonb language plpgsql as $$
declare n0 int := pg_temp.nlog(); r jsonb;
begin r := public.diapositiva_guardar(p); return pg_temp.logged(r, n0); end $$;
create function pg_temp.st(i uuid, s text) returns jsonb language plpgsql as $$
declare n0 int := pg_temp.nlog(); r jsonb;
begin r := public.diapositiva_estado(i, s); return pg_temp.logged(r, n0); end $$;
-- "true · 1 logged · crear diapositiva by …" or "false invalid/kind · 0 logged"
create function pg_temp.brief(r jsonb) returns text language sql as $$
  select coalesce(r ->> 'ok', '?') || coalesce(' ' || (r ->> 'error'), '') || coalesce('/' || (r ->> 'field'), '')
      || ' · ' || coalesce(r ->> '_logged', '?') || ' logged'
      || coalesce(' · ' || (r -> '_log' ->> 'action') || ' ' || (r -> '_log' ->> 'target_kind') || ' by ' || (r -> '_log' ->> 'by'), '') $$;
-- "ok", or "error/field" exactly as the function returns them
create function pg_temp.err(r jsonb) returns text language sql as $$
  select coalesce(r ->> 'error', 'ok') || coalesce('/' || (r ->> 'field'), '') $$;
create function pg_temp.keys(j jsonb) returns text language sql as $$ select string_agg(k, ' ' order by k) from jsonb_object_keys(j) k $$;
-- the six choices of v2 of a TV, "density=… english=… layout=… promo_every=… promo_mode=… promo_seconds=…"
create function pg_temp.v2(t jsonb) returns text language sql as $$
  select string_agg(k || '=' || coalesce(t ->> k, 'null'), ' ' order by k)
    from unnest(array['layout', 'density', 'english', 'promo_mode', 'promo_every', 'promo_seconds']) k $$;
-- an entry with a product, an entry with only a photo (p on top of either)
create function pg_temp.ei(i uuid, p jsonb default '{}') returns jsonb language sql as $$ select jsonb_build_object('item', i) || p $$;
create function pg_temp.ep(u text, p jsonb default '{}') returns jsonb language sql as $$ select jsonb_build_object('photo', u) || p $$;
-- a fixed zone with one entry; a presentation with its list of entries (p on top of the zone)
create function pg_temp.fija(e jsonb, p jsonb default '{}') returns jsonb language sql as $$ select jsonb_build_object('mode', 'fija', 'entries', jsonb_build_array(e)) || p $$;
create function pg_temp.auto(e jsonb, p jsonb default '{}') returns jsonb language sql as $$ select jsonb_build_object('mode', 'auto', 'entries', e) || p $$;
-- n fixed zones: Latte, Tea, Banana Bread, Ham & Cheese
create function pg_temp.fijas(n int) returns jsonb language sql as $$
  select jsonb_agg(pg_temp.fija(pg_temp.ei(i.id)) order by u.o)
    from unnest(array['Latte', 'Tea', 'Banana Bread', 'Ham & Cheese']) with ordinality u(nm, o) join public.menu_items i on i.name = u.nm where u.o <= n $$;
-- a composition in force for a month, with p on top
create function pg_temp.comp(t text, z jsonb, p jsonb default '{}') returns jsonb language sql as $$
  select jsonb_build_object('kind', 'composicion', 'template', t, 'zones', z, 'starts_at', now() - interval '1 hour', 'ends_at', now() + interval '30 days') || p $$;
-- a one-zone composition: a fixed Latte with v on top of the zone; a one-zone composition whose fixed zone holds the entry e
create function pg_temp.zona(v jsonb) returns jsonb language sql as $$
  select pg_temp.comp('1', jsonb_build_array(pg_temp.fija(pg_temp.ei((select id from public.menu_items where name = 'Latte'))) || v)) $$;
create function pg_temp.entrada(e jsonb) returns jsonb language sql as $$ select pg_temp.comp('1', jsonb_build_array(pg_temp.fija(e))) $$;
-- what a TV shows now: the title, the product's name or the kicker (every composition of this test has one)
create function pg_temp.shown(tv text) returns text language sql as $$
  select coalesce(string_agg(coalesce(s ->> 'title_es', s #>> '{item,name}', s ->> 'kicker_es'), ' | ' order by o), '')
    from jsonb_array_elements(public.pantalla_datos(tv) -> 'slides') with ordinality x(s, o) $$;
-- one slide of a TV's read, by its kicker
create function pg_temp.leida(tv text, k text) returns jsonb language sql as $$
  select s from jsonb_array_elements(public.pantalla_datos(tv) -> 'slides') s where s ->> 'kicker_es' = k $$;
-- "showable showable … · usable" of a composition
create function pg_temp.muestra(s jsonb) returns text language sql as $$
  select coalesce((select string_agg(z ->> 'showable', ' ' order by o) from jsonb_array_elements(s -> 'zones') with ordinality x(z, o)), '-') || ' · ' || coalesce(s ->> 'usable', 'null') $$;

-- 1) the columns, their defaults and their rules; the two helpers ---------------------------------------------------------
select test.eq((select string_agg(column_name || '=' || column_default || '/' || is_nullable, ' ' order by ordinal_position)
                  from information_schema.columns where table_schema = 'public' and table_name = 'screens'
                   and column_name in ('layout', 'density', 'english', 'promo_mode', 'promo_every', 'promo_seconds')),
               'layout=''auto''::text/NO density=''normal''::text/NO english=''debajo''::text/NO promo_mode=''no''::text/NO promo_every=180/NO promo_seconds=10/NO',
               'screens: the six choices of v2, each with its default, none null');
select test.eq((select string_agg(column_name || '=' || coalesce(column_default, '-') || '/' || is_nullable, ' ' order by ordinal_position)
                  from information_schema.columns where table_schema = 'public' and table_name = 'screen_slides' and column_name in ('template', 'zones', 'dwell_seconds')),
               'template=-/YES zones=''[]''::jsonb/NO dwell_seconds=-/YES', 'screen_slides: template, zones (a list, never null) and dwell_seconds');
select test.eq((select string_agg(conname, ' ' order by conname) from pg_constraint
                 where conrelid in ('public.screens'::regclass, 'public.screen_slides'::regclass) and conname ~ 'layout|density|english|promo|dwell|template|kind'),
               'screen_slides_dwell_seconds_check screen_slides_kind screen_slides_kind_check screen_slides_template_check screens_density_check screens_english_check '
               || 'screens_kind_check screens_layout_check screens_promo_every_check screens_promo_mode_check screens_promo_seconds_check', 'the rules of the tables, by name');
select test.eq((select string_agg(id || ':' || layout || ':' || density || ':' || english || ':' || promo_mode || ':' || promo_every || ':' || promo_seconds, ' ' order by id) from public.screens),
               'menu-1:auto:normal:debajo:no:180:10 promos-1:auto:normal:debajo:no:180:10', 'the two TVs of 0036 carry the defaults (nothing changes on their screens)');
-- the rules of the tables themselves, as the database owner
select test.throws($$update public.screens set layout = 'grande' where id = 'menu-1'$$, 'screens_layout_check', 'layout: auto, una-pantalla or paginas');
select test.throws($$update public.screens set density = 'x' where id = 'menu-1'$$, 'screens_density_check', 'density: normal or compacta');
select test.throws($$update public.screens set english = 'arriba' where id = 'menu-1'$$, 'screens_english_check', 'english: debajo, en-linea or no');
select test.throws($$update public.screens set promo_mode = 'si' where id = 'menu-1'$$, 'screens_promo_mode_check', 'promo_mode: no or intercalar');
select test.throws($$update public.screens set promo_every = 29 where id = 'menu-1'$$, 'screens_promo_every_check', 'promo_every: 30 to 900');
select test.throws($$update public.screens set promo_seconds = 31 where id = 'menu-1'$$, 'screens_promo_seconds_check', 'promo_seconds: 6 to 30');
select test.throws($$insert into public.screen_slides (kind, title_es, starts_at, ends_at, dwell_seconds) values ('marca', 'x', now(), now() + interval '1 day', 9)$$,
                   'screen_slides_dwell_seconds_check', 'dwell_seconds: null or 10 to 600');
select test.throws($$insert into public.screen_slides (kind, title_es, starts_at, ends_at, template) values ('marca', 'x', now(), now() + interval '1 day', '5')$$,
                   'screen_slides_template_check', 'template: one of the six');
select test.throws($$insert into public.screen_slides (kind, starts_at, ends_at, template, zones) values ('composicion', now(), now() + interval '1 day', '2-lado', '[{}]')$$,
                   'screen_slides_kind', 'a composition has as many zones as its template has places');
select test.throws($$insert into public.screen_slides (kind, title_es, starts_at, ends_at) values ('grupo', 'x', now(), now() + interval '1 day')$$,
                   'screen_slides_kind', 'an unknown kind is refused (producto, marca, invitacion, composicion)');
select test.eq((select string_agg(coalesce(public._screen_template_places(t)::text, 'null'), ' ' order by o)
                  from unnest(array['1', '2-lado', '3-grande-izq', '3-grande-der', '4-cuadricula', '4-centro', '4', '']) with ordinality u(t, o)),
               '1 2 3 3 4 4 null null', 'the places of each template');
select test.eq(pg_temp.keys((select public._screen_json(s) from public.screens s where id = 'menu-1')),
               'active category_ids density distance_m english id inches item_ids kind layout look name on_from on_to page_seconds promo_every promo_mode promo_seconds scale_pct slide_seconds sold_out turn updated_at',
               'a TV as the screens see it: the 16 keys of 0036 plus the six choices and item_ids (the summarized menu)');
select test.eq((select column_name || '/' || is_nullable || '/' || coalesce(column_default, 'NO') || '/' || data_type from information_schema.columns
                 where table_schema = 'public' and table_name = 'screens' and column_name = 'item_ids'), 'item_ids/YES/NO/ARRAY',
               'item_ids: a list of uuids, null by default (every product of the shown categories)');
select test.eq(public._screen_item_json(:'latte'),
               jsonb_build_object('id', :'latte', 'name', 'Latte', 'name_es', null, 'price_crc', 2200, 'photo_url', null, 'available', true, 'category', 'Coffee', 'sellable', true),
               'a product as the screens see it: id, name, Spanish name, live price, photo, availability, category, sellable');
select test.eq(public._screen_item_json(:'shot') ->> 'sellable' || ' ' || (public._screen_item_json(:'combo') ->> 'sellable'), 'false false', 'a till helper or the combo line is never sellable on a screen');
select test.eq(public._screen_item_json('00000000-0000-4000-8000-000000000000'), null::jsonb, 'an unknown product: nothing');
select test.eq((select string_agg(p.proname || '=' || p.provolatile::text || '/' || p.prosecdef || '/' || p.proconfig::text, ' ' order by p.proname)
                  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('_screen_item_json', '_screen_template_places')),
               '_screen_item_json=s/false/{search_path=public} _screen_template_places=i/false/{search_path=public}',
               'the two helpers of 0037: the live read of a product (STABLE) and the places of a template (IMMUTABLE), without the owner''s rights, with a fixed search path');
select test.ok(not exists (select 1 from unnest(array['anon', 'authenticated', 'canopy_backup']) r, unnest(array['public._screen_item_json(uuid)', 'public._screen_template_places(text)']) f
                            where has_function_privilege(r, f, 'execute')), 'neither a visitor, a login nor the backup account may run them');

-- 2) a visitor: the TVs read the six choices; the helpers are closed --------------------------------------------------------
select test.login('anon'); set role anon;
select test.eq(pg_temp.v2(public.pantalla_datos('menu-1') -> 'tv'), 'density=normal english=debajo layout=auto promo_every=180 promo_mode=no promo_seconds=10',
               'a visitor reads the six choices with their defaults');
select test.eq(public.pantalla_datos('menu-1') -> 'slides', '[]'::jsonb, 'the menu TV without promotions: no slides');
select test.throws($$select public._screen_item_json('00000000-0000-4000-8000-000000000000')$$, 'permission denied', 'a visitor cannot run the product helper');
select test.throws($$select public._screen_template_places('1')$$, 'permission denied', 'nor the template helper');
reset role;
select test.login('cafe'); set role authenticated;
select test.throws($$select public._screen_item_json('00000000-0000-4000-8000-000000000000')$$, 'permission denied', 'nor a login the product helper');
select test.throws($$select public._screen_template_places('1')$$, 'permission denied', 'nor the template helper');
reset role;

-- 3) the six choices of a TV (café + owner PIN) -----------------------------------------------------------------------------
select test.login('cafe', 'aal1', current_setting('test.h_dueno')::jsonb); set role authenticated;
select test.eq((select string_agg(k || '=' || pg_temp.err(r) || '/' || (r ->> '_logged'), ' ' order by o)
                  from (values (1, 'layout', '"grande"'::jsonb), (2, 'layout', '"Auto"'), (3, 'layout', 'null'), (4, 'density', '"x"'), (5, 'density', '1'), (6, 'english', '"arriba"'),
                               (7, 'promo_mode', '"si"'), (8, 'promo_mode', '"none"'), (9, 'promo_every', '29'), (10, 'promo_every', '901'), (11, 'promo_every', '"muchos"'),
                               (12, 'promo_every', '30.5'), (13, 'promo_seconds', '5'), (14, 'promo_seconds', '31'), (15, 'promo_seconds', '-6'), (16, 'promo_seconds', 'true'), (17, 'promo_every', 'null'), (18, 'promo_seconds', 'null')) x(o, k, v)
                  cross join lateral (select pg_temp.tv(jsonb_build_object('id', 'menu-1') || jsonb_build_object(k, v))) y(r)),
               'layout=invalid/layout/0 layout=invalid/layout/0 layout=invalid/layout/0 density=invalid/density/0 density=invalid/density/0 english=invalid/english/0 '
               || 'promo_mode=invalid/promo_mode/0 promo_mode=invalid/promo_mode/0 promo_every=invalid/promo_every/0 promo_every=invalid/promo_every/0 promo_every=invalid/promo_every/0 '
               || 'promo_every=invalid/promo_every/0 promo_seconds=invalid/promo_seconds/0 promo_seconds=invalid/promo_seconds/0 promo_seconds=invalid/promo_seconds/0 promo_seconds=invalid/promo_seconds/0 promo_every=invalid/promo_every/0 promo_seconds=invalid/promo_seconds/0',
               'a choice outside its words or its range (not a whole number, or a null) is refused by name and logs nothing');
select pg_temp.tv('{"id": "menu-1", "layout": "una-pantalla", "density": "compacta", "english": "en-linea", "promo_mode": "intercalar", "promo_every": 30, "promo_seconds": 6}') as r \gset
select test.eq(pg_temp.brief(:'r'), 'true · 1 logged · cambiar tv by Dueño (owner)', 'the owner sets the six choices: one line in the log');
select test.eq(pg_temp.v2((:'r'::jsonb) -> 'tv'), 'density=compacta english=en-linea layout=una-pantalla promo_every=30 promo_mode=intercalar promo_seconds=6', 'saved as asked (the lower ends of both ranges)');
select test.eq(pg_temp.v2((:'r'::jsonb) #> '{_log,before}') || ' > ' || pg_temp.v2((:'r'::jsonb) #> '{_log,after}'),
               'density=normal english=debajo layout=auto promo_every=180 promo_mode=no promo_seconds=10 > density=compacta english=en-linea layout=una-pantalla promo_every=30 promo_mode=intercalar promo_seconds=6',
               'the log keeps the six choices before and after');
select test.eq(pg_temp.v2(pg_temp.tv('{"id": "menu-1", "layout": "paginas", "english": "no", "promo_every": 900, "promo_seconds": 30}') -> 'tv'),
               'density=compacta english=no layout=paginas promo_every=900 promo_mode=intercalar promo_seconds=30', 'the upper ends and the other words');
-- 3b) the products of a TV (the summarized menu, owner 2026-11-02): null or [] = all; a list of products of the menu, each once,
--     in the order given; never a till helper nor the combo line; refused by name otherwise
select test.eq((select string_agg(pg_temp.err(r) || '/' || (r ->> '_logged'), ' ' order by o)
                  from (values (1, '"x"'::jsonb), (2, '{}'), (3, '["abc"]'), (4, '[null]'), (5, '[12]'), (6, jsonb_build_array(:'shot')), (7, jsonb_build_array(:'combo')),
                               (8, jsonb_build_array('00000000-0000-4000-8000-000000000000')), (9, jsonb_build_array(:'latte', 'c0ffee')),
                               (10, (select jsonb_agg(:'latte'::text) from generate_series(1, 301)))) x(o, v)
                  cross join lateral (select pg_temp.tv(jsonb_build_object('id', 'menu-1', 'item_ids', v))) y(r)),
               'invalid/item_ids/0 invalid/item_ids/0 invalid/item_ids/0 invalid/item_ids/0 invalid/item_ids/0 invalid/item_ids/0 invalid/item_ids/0 invalid/item_ids/0 invalid/item_ids/0 too_many/item_ids/0',
               'item_ids: a list of canonical uuids of menu products (no till helper, no combo line, no unknown id), at most 300; anything else is refused by name and logs nothing');
select pg_temp.tv(jsonb_build_object('id', 'menu-1', 'item_ids', jsonb_build_array(:'latte', upper(:'latte'), :'bread', :'latte'))) as r \gset
select test.eq(pg_temp.brief(:'r'), 'true · 1 logged · cambiar tv by Dueño (owner)', 'the owner chooses the products: one line in the log');
select test.eq((:'r'::jsonb) #> '{tv,item_ids}', jsonb_build_array(:'latte', :'bread'), 'saved once each, in the order given, in the canonical form');
select test.eq(coalesce((:'r'::jsonb) #> '{_log,before,item_ids}', 'null'::jsonb) || ((:'r'::jsonb) #> '{_log,after,item_ids}'), 'null'::jsonb || jsonb_build_array(:'latte', :'bread'),
               'the log keeps the products before (none) and after');
select test.eq(pg_temp.tv('{"id": "menu-1", "scale_pct": 110}') #> '{tv,item_ids}', jsonb_build_array(:'latte', :'bread'), 'a change without the field keeps them');
select test.eq(pg_temp.tv('{"id": "menu-1", "item_ids": []}') #> '{tv,item_ids}', 'null'::jsonb, 'an empty list = every product');
select test.eq(pg_temp.tv(jsonb_build_object('id', 'menu-1', 'item_ids', jsonb_build_array(:'ham'))) #> '{tv,item_ids}', jsonb_build_array(:'ham'), 'one product');
select test.eq(pg_temp.tv('{"id": "menu-1", "item_ids": null}') #> '{tv,item_ids}', 'null'::jsonb, 'null = every product');
reset role;
select test.login('anon'); set role anon;
select test.eq(public.pantalla_datos('menu-1') #> '{tv,item_ids}', 'null'::jsonb, 'a visitor reads item_ids with the TV (null here)');
reset role;
select test.login('cafe', 'aal1', current_setting('test.h_dueno')::jsonb); set role authenticated;
select test.eq(pg_temp.v2(pg_temp.tv('{"id": "menu-1", "scale_pct": 110}') -> 'tv'),
               'density=compacta english=no layout=paginas promo_every=900 promo_mode=intercalar promo_seconds=30', 'a change without them keeps them');
select test.eq(pg_temp.v2(pg_temp.tv('{"id": "promos-2", "kind": "promos", "name": "Pantalla B · terraza"}') -> 'tv'),
               'density=normal english=debajo layout=auto promo_every=180 promo_mode=no promo_seconds=10', 'a new TV is born with the defaults');
select test.eq(pg_temp.v2(pg_temp.tv('{"id": "menu-1", "promo_mode": "no", "layout": "auto", "density": "normal", "english": "debajo", "promo_every": 180, "promo_seconds": 10}') -> 'tv'),
               'density=normal english=debajo layout=auto promo_every=180 promo_mode=no promo_seconds=10', 'back to the defaults');
reset role;
select test.eq((select count(*)::int from public.screen_changes), 10, 'ten changes of TVs logged (five of the choices, five of the products), the refusals none');

-- 4) compositions (the owner's login with the phone code) --------------------------------------------------------------------
select test.login('owner', 'aal2'); set role authenticated;
select test.eq((select string_agg(t || '=' || pg_temp.err(r) || '/' || coalesce(jsonb_array_length(r -> 'slide' -> 'zones')::text, '-') || '/' || coalesce(r -> 'slide' ->> 'template', '-'), ' ' order by o)
                  from (values (1, '1', 1), (2, '2-lado', 2), (3, '3-grande-izq', 3), (4, '3-grande-der', 3), (5, '4-cuadricula', 4), (6, '4-centro', 4)) x(o, t, n)
                  cross join lateral (select public.diapositiva_guardar(pg_temp.comp(t, pg_temp.fijas(n), '{"status": "pausada"}'))) y(r)),
               '1=ok/1/1 2-lado=ok/2/2-lado 3-grande-izq=ok/3/3-grande-izq 3-grande-der=ok/3/3-grande-der 4-cuadricula=ok/4/4-cuadricula 4-centro=ok/4/4-centro',
               'the six templates, each with as many zones as places (made paused)');
-- the owner's four windows: left the pastry, right the sandwich, centre a presentation and a fixed photo
select pg_temp.slide(pg_temp.comp('4-centro', jsonb_build_array(
         pg_temp.fija(pg_temp.ei(:'latte', '{"focus": [20, 80], "zoom": 150}'), '{"labels": true}'),
         pg_temp.auto(jsonb_build_array(pg_temp.ei(:'tea'), pg_temp.ep('https://example.com/te.jpg')), '{"seconds": 5, "labels": false, "fallback": "https://example.com/marca.jpg"}'),
         pg_temp.fija(pg_temp.ei(:'bread', '{"photo": "https://example.com/pan.jpg"}')),
         pg_temp.fija(pg_temp.ep('https://example.com/terraza.jpg'))),
       jsonb_build_object('kicker_es', 'Desayuno', 'kicker_en', 'Breakfast', 'title_es', 'Se ignora', 'body_es', 'También', 'menu_item_id', :'ham', 'dwell_seconds', 90, 'sort', 10))) as r \gset
select test.eq(pg_temp.brief(:'r'), 'true · 1 logged · crear diapositiva by owner login · owner@test.local', 'the owner''s login creates a composition of four zones');
select (:'r'::jsonb) #>> '{slide,id}' as c_desayuno, (:'r'::jsonb) #>> '{_log,after,zones}' as z_desayuno \gset
select test.eq(pg_temp.keys((:'r'::jsonb) -> 'slide'),
               'body_en body_es days dwell_seconds ends_at from_time id item kicker_en kicker_es kind link menu_item_id photo_url screen_ids sort starts_at status template title_en title_es to_time usable zones',
               'a slide as the screens see it: the 21 keys of 0036 plus template, dwell_seconds, zones and usable');
select test.eq(pg_temp.keys((:'r'::jsonb) #> '{slide,zones,0}'), 'entries fallback labels mode seconds showable', 'a zone: mode, seconds, labels, fallback, its entries and whether it can show now');
select test.eq(pg_temp.keys((:'r'::jsonb) #> '{slide,zones,0,entries,0}'), 'focus item photo zoom', 'an entry: the product (live), the photo, the framing');
select test.eq(pg_temp.keys((:'r'::jsonb) #> '{slide,zones,0,entries,0,item}'), 'available category id name name_es photo_url price_crc sellable', 'the product as the menu has it right now');
select test.eq((:'r'::jsonb) #> '{slide,zones,0,entries,0}',
               jsonb_build_object('item', jsonb_build_object('id', :'latte', 'name', 'Latte', 'name_es', null, 'price_crc', 2200, 'photo_url', null, 'available', true, 'category', 'Coffee', 'sellable', true),
                                  'photo', null, 'focus', '[20, 80]'::jsonb, 'zoom', 150),
               'the Latte entry: the menu''s name, price, photo and availability, and the framing as given');
select test.eq(((:'r'::jsonb) #> '{slide,zones,1}') - 'entries', '{"mode": "auto", "seconds": 5, "labels": false, "fallback": "https://example.com/marca.jpg", "showable": true}'::jsonb,
               'the presentation zone: its seconds, without labels, its fallback');
select test.eq((:'r'::jsonb) #> '{slide,zones,1,entries,1}', '{"item": null, "photo": "https://example.com/te.jpg", "focus": [50, 50], "zoom": 100}'::jsonb, 'a photo-only entry: no product, the default framing');
select test.eq(((:'r'::jsonb) #>> '{slide,zones,2,entries,0,photo}') || ' ' || ((:'r'::jsonb) #>> '{slide,zones,2,entries,0,item,name}'), 'https://example.com/pan.jpg Banana Bread',
               'a product with its own photo keeps both (the photo wins on screen, the name and price are the product''s)');
select test.eq(pg_temp.muestra((:'r'::jsonb) -> 'slide'), 'true true true true · true', 'every zone can show, so the composition is usable');
select test.eq(((:'r'::jsonb) #>> '{slide,template}') || ' ' || ((:'r'::jsonb) #>> '{slide,dwell_seconds}') || ' ' || ((:'r'::jsonb) #>> '{slide,kicker_es}') || ' ' || ((:'r'::jsonb) #>> '{slide,kicker_en}'),
               '4-centro 90 Desayuno Breakfast', 'template, dwell and the kicker');
select test.ok((:'r'::jsonb) #> '{slide,title_es}' = 'null'::jsonb and (:'r'::jsonb) #> '{slide,body_es}' = 'null'::jsonb and (:'r'::jsonb) #> '{slide,item}' = 'null'::jsonb
               and (:'r'::jsonb) #> '{slide,menu_item_id}' = 'null'::jsonb, 'a composition has no title, no body, no product of its own (given, they are dropped)');
-- the log
select test.eq((:'r'::jsonb) #>> '{_log,summary}', 'composición · 4-centro', 'its summary in the log');
select test.eq(pg_temp.keys((:'r'::jsonb) #> '{_log,after}'),
               'body_en body_es days dwell_seconds ends_at from_time id kicker_en kicker_es kind link menu_item_id photo_url screen_ids sort starts_at status template title_en title_es to_time zones',
               'the log''s after: the slide without the menu''s data (no item, no usable)');
select test.eq((:'r'::jsonb) #> '{_log,after,zones}', jsonb_build_array(
         jsonb_build_object('mode', 'fija', 'seconds', 8, 'labels', true, 'fallback', null, 'entries', jsonb_build_array(jsonb_build_object('item', :'latte', 'photo', null, 'focus', '[20, 80]'::jsonb, 'zoom', 150))),
         jsonb_build_object('mode', 'auto', 'seconds', 5, 'labels', false, 'fallback', 'https://example.com/marca.jpg', 'entries', jsonb_build_array(
           jsonb_build_object('item', :'tea', 'photo', null, 'focus', '[50, 50]'::jsonb, 'zoom', 100), jsonb_build_object('item', null, 'photo', 'https://example.com/te.jpg', 'focus', '[50, 50]'::jsonb, 'zoom', 100))),
         jsonb_build_object('mode', 'fija', 'seconds', 8, 'labels', true, 'fallback', null, 'entries', jsonb_build_array(jsonb_build_object('item', :'bread', 'photo', 'https://example.com/pan.jpg', 'focus', '[50, 50]'::jsonb, 'zoom', 100))),
         jsonb_build_object('mode', 'fija', 'seconds', 8, 'labels', true, 'fallback', null, 'entries', jsonb_build_array(jsonb_build_object('item', null, 'photo', 'https://example.com/terraza.jpg', 'focus', '[50, 50]'::jsonb, 'zoom', 100)))),
       'the log keeps the zones as written: product ids, photos and framing, the defaults filled in; never a name or a price');
select test.ok(((:'r'::jsonb) #> '{_log,after}')::text !~ '(Latte|2200|Coffee|sellable|showable|price_crc)', 'nothing of the menu in the log');
reset role;
select test.eq((select zones from public.screen_slides where id = :'c_desayuno'), :'z_desayuno'::jsonb, 'the row stores exactly that (nothing of the menu)');
select test.eq((select template || ' ' || dwell_seconds || ' ' || coalesce(title_es, '-') || ' ' || coalesce(menu_item_id::text, '-') from public.screen_slides where id = :'c_desayuno'), '4-centro 90 - -', 'with its template and dwell; no title, no product');
set role authenticated;
-- refused: templates and zones
select test.eq((select string_agg(pg_temp.err(public.diapositiva_guardar(pg_temp.comp(t, z))), ' ' order by o)
                  from (values (1, '2-lado', pg_temp.fijas(1)), (2, '1', pg_temp.fijas(2)), (3, '4-centro', pg_temp.fijas(4) || pg_temp.fijas(1)), (4, '1', pg_temp.fijas(4) || pg_temp.fijas(1)),
                               (5, '1', '"x"'::jsonb), (6, '1', '[]'::jsonb), (7, '1', null), (8, null, pg_temp.fijas(1)), (9, 'cinco', pg_temp.fijas(1)), (10, '4', pg_temp.fijas(4)),
                               (11, '2-lado', '[1, 2]'::jsonb), (12, '2-lado', pg_temp.fijas(1) || '[1]'::jsonb)) x(o, t, z)),
               'invalid/zones invalid/zones too_many/zones too_many/zones invalid/zones invalid/zones invalid/zones invalid/template invalid/template invalid/template invalid/zones.0 invalid/zones.1',
               'refused: fewer or more zones than places, more than four, zones that are not a list, no template or an unknown one, a zone that is not an object');
-- refused: a zone, by its path
select test.eq((select string_agg(pg_temp.err(public.diapositiva_guardar(pg_temp.zona(v))), ' ' order by o)
                  from (values (1, '{"mode": "rotar"}'::jsonb), (2, jsonb_build_object('entries', jsonb_build_array(pg_temp.ei(:'latte'), pg_temp.ei(:'tea')))), (3, '{"entries": []}'),
                               (4, '{"entries": null}'), (5, '{"entries": "x"}'), (6, jsonb_build_object('mode', 'auto', 'entries', (select jsonb_agg(pg_temp.ei(:'latte')) from generate_series(1, 13)))),
                               (7, '{"mode": "auto", "entries": []}'), (8, '{"seconds": 3}'), (9, '{"seconds": 61}'), (10, '{"seconds": "8"}'), (11, '{"labels": "si"}'), (12, '{"labels": 1}'),
                               (13, '{"fallback": "javascript:alert(1)"}'), (14, '{"fallback": "https://x.cr/a b.jpg"}'), (15, jsonb_build_object('fallback', 'https://x.cr/' || repeat('a', 490)))) x(o, v)),
               'invalid/zones.0.mode invalid/zones.0.entries invalid/zones.0.entries invalid/zones.0.entries invalid/zones.0.entries too_many/zones.0.entries invalid/zones.0.entries '
               || 'invalid/zones.0.seconds invalid/zones.0.seconds invalid/zones.0.seconds invalid/zones.0.labels invalid/zones.0.labels invalid/zones.0.fallback invalid/zones.0.fallback invalid/zones.0.fallback',
               'a zone refused by its path: an unknown mode, a fixed zone with two (or no) entries, a presentation with none or thirteen, seconds outside 4..60 or not a number, '
               || 'labels not yes/no, a fallback that is not a plain web address of 500 characters or less');
-- refused: an entry, by its path
select test.eq((select string_agg(pg_temp.err(public.diapositiva_guardar(pg_temp.entrada(e))), ' ' order by o)
                  from (values (1, '{}'::jsonb), (2, '"x"'), (3, '{"focus": [50, 50]}'), (4, jsonb_build_object('item', :'shot')), (5, jsonb_build_object('item', :'combo')),
                               (6, '{"item": "00000000-0000-4000-8000-000000000000"}'), (7, '{"item": "abc"}'), (8, pg_temp.ei(:'latte', '{"focus": [50]}')), (9, pg_temp.ei(:'latte', '{"focus": [101, 50]}')),
                               (10, pg_temp.ei(:'latte', '{"focus": [50, -1]}')), (11, pg_temp.ei(:'latte', '{"focus": ["a", 50]}')), (12, pg_temp.ei(:'latte', '{"focus": "centro"}')),
                               (13, pg_temp.ei(:'latte', '{"zoom": 99}')), (14, pg_temp.ei(:'latte', '{"zoom": 201}')), (15, pg_temp.ei(:'latte', '{"zoom": "100"}')),
                               (16, pg_temp.ep('javascript:alert(1)')), (17, pg_temp.ep('https://x.cr/a b.jpg')), (18, pg_temp.ep('https://x.cr/' || repeat('a', 490))),
                               (19, pg_temp.ei(:'latte', '{"photo": "ftp://x.cr/a.jpg"}'))) x(o, e)),
               'invalid/zones.0.entries.0 invalid/zones.0.entries.0 invalid/zones.0.entries.0 text_combo_descuento/zones.0.entries.0.item text_combo_descuento/zones.0.entries.0.item '
               || 'invalid/zones.0.entries.0.item invalid/zones.0.entries.0.item invalid/zones.0.entries.0.focus invalid/zones.0.entries.0.focus invalid/zones.0.entries.0.focus '
               || 'invalid/zones.0.entries.0.focus invalid/zones.0.entries.0.focus invalid/zones.0.entries.0.zoom invalid/zones.0.entries.0.zoom invalid/zones.0.entries.0.zoom '
               || 'invalid/zones.0.entries.0.photo invalid/zones.0.entries.0.photo invalid/zones.0.entries.0.photo invalid/zones.0.entries.0.photo',
               'an entry refused by its path: nothing in it, not an object, a till helper or the combo line, an unknown product, a focus outside 0..100 or not a pair of numbers, '
               || 'a zoom outside 100..200 or not a number, a photo that is not a plain web address');
select test.eq(pg_temp.err(public.diapositiva_guardar(pg_temp.comp('2-lado', jsonb_build_array(pg_temp.fija(pg_temp.ei(:'latte')), pg_temp.auto(jsonb_build_array(pg_temp.ei(:'tea'), jsonb_build_object('item', :'shot'))))))),
               'text_combo_descuento/zones.1.entries.1.item', 'the path names the zone and the entry: zones.1.entries.1.item');
-- refused by its path, never a raw SQL error: an item of 36 hex characters and dashes that is not a uuid (only the canonical form passes)
select test.eq((select string_agg(pg_temp.err(public.diapositiva_guardar(pg_temp.entrada(jsonb_build_object('item', v)))), ' ' order by o)
                  from (values (1, '0123456789abcdef0123456789abcdef0123'), (2, '1b00000-00000-4000-8000-000000004601'), (3, '1b000000-0000-4000-8000-00000000460-'),
                               (4, replace(:'latte', '-', '') || '0000'), (5, replace(:'latte', '-', ''))) x(o, v)),
               'invalid/zones.0.entries.0.item invalid/zones.0.entries.0.item invalid/zones.0.entries.0.item invalid/zones.0.entries.0.item invalid/zones.0.entries.0.item',
               'an item of 36 hex characters and dashes that is not a uuid (36 digits without dashes, the dashes in the wrong places, a dash at the end, the Latte''s id run '
               || 'together) is refused by its path, never a raw SQL error; the id without dashes too (only the canonical form)');
select test.eq(pg_temp.err(public.diapositiva_guardar(pg_temp.comp('2-lado', jsonb_build_array(pg_temp.fija(pg_temp.ei(:'latte')), pg_temp.auto(jsonb_build_array(pg_temp.ei(:'tea'), '{"item": "0123456789abcdef0123456789abcdef0123"}'::jsonb)))))),
               'invalid/zones.1.entries.1.item', 'with the zone and the entry in the path: zones.1.entries.1.item');
-- refused: dwell and the kicker
select test.eq((select string_agg(pg_temp.err(public.diapositiva_guardar(pg_temp.comp('1', pg_temp.fijas(1), jsonb_build_object('dwell_seconds', v)))), ' ' order by o)
                  from (values (1, '9'::jsonb), (2, '601'), (3, '"largo"'), (4, '-10'), (5, '60.5')) x(o, v)),
               'invalid/dwell_seconds invalid/dwell_seconds invalid/dwell_seconds invalid/dwell_seconds invalid/dwell_seconds', 'dwell_seconds outside 10..600 or not a whole number is refused');
select test.eq(pg_temp.err(public.diapositiva_guardar(pg_temp.comp('1', pg_temp.fijas(1), '{"kicker_es": "Hoy ₡1 500"}'))), 'text_precio/kicker_es', 'the kicker goes through the text rule: no price');
select test.eq(pg_temp.err(public.diapositiva_guardar(pg_temp.comp('1', pg_temp.fijas(1), '{"kicker_en": "2x1 today"}'))), 'text_combo_descuento/kicker_en', 'nor a 2x1');
select test.eq(pg_temp.err(public.diapositiva_guardar(pg_temp.comp('1', pg_temp.fijas(1), jsonb_build_object('kicker_es', repeat('a', 141))))), 'text_largo/kicker_es', 'nor more than 140 characters');
reset role;
select test.eq((select count(*)::int from public.screen_slides) || ' ' || (select count(*)::int from public.screen_changes), '7 17', 'none of those refusals saved or logged anything (7 slides, 17 lines)');
set role authenticated;
-- accepted: the ends of the ranges, rounding, the defaults
select pg_temp.slide(pg_temp.comp('2-lado', jsonb_build_array(
         pg_temp.auto(jsonb_build_array(pg_temp.ei(:'latte', '{"focus": [33.4, 66.6], "zoom": 150.4}')), '{"seconds": 4}'),
         pg_temp.auto((select jsonb_agg(pg_temp.ei(:'tea')) from generate_series(1, 12)), '{"seconds": 60, "fallback": "  https://example.com/f.jpg  "}')),
       '{"status": "pausada", "dwell_seconds": 10}')) as r \gset
select test.eq(pg_temp.brief(:'r'), 'true · 1 logged · crear diapositiva by owner login · owner@test.local', 'a presentation of one entry and one of twelve, 4 and 60 seconds, dwell 10: accepted');
select test.eq(((:'r'::jsonb) #>> '{slide,zones,0,entries,0,focus}') || ' ' || ((:'r'::jsonb) #>> '{slide,zones,0,entries,0,zoom}') || ' ' || ((:'r'::jsonb) #>> '{slide,zones,0,seconds}') || ' '
               || ((:'r'::jsonb) #>> '{slide,zones,1,seconds}') || ' ' || jsonb_array_length((:'r'::jsonb) #> '{slide,zones,1,entries}') || ' ' || ((:'r'::jsonb) #>> '{slide,zones,1,fallback}') || ' ' || ((:'r'::jsonb) #>> '{slide,dwell_seconds}'),
               '[33, 67] 150 4 60 12 https://example.com/f.jpg 10', 'the framing is rounded, the fallback trimmed, the ends of the ranges kept');
select pg_temp.slide(pg_temp.comp('1', jsonb_build_array(jsonb_build_object('entries', jsonb_build_array(jsonb_build_object('item', :'latte', 'photo', '')), 'fallback', '')), '{"status": "pausada", "dwell_seconds": 600}')) as r \gset
select test.eq(pg_temp.brief(:'r'), 'true · 1 logged · crear diapositiva by owner login · owner@test.local', 'a zone given only its entries (dwell 600): accepted');
select test.eq(((:'r'::jsonb) #> '{slide,zones,0}') - 'entries' - 'showable', '{"mode": "fija", "seconds": 8, "labels": true, "fallback": null}'::jsonb, 'fixed, 8 seconds, with labels, no fallback (a blank is none)');
select test.eq(((:'r'::jsonb) #> '{slide,zones,0,entries,0}') - 'item', '{"photo": null, "focus": [50, 50], "zoom": 100}'::jsonb, 'an entry given only its product: no photo (a blank is none), the default framing');
select test.eq((:'r'::jsonb) #>> '{slide,dwell_seconds}', '600', 'dwell 600');
select test.eq((select string_agg(coalesce(public.diapositiva_guardar(pg_temp.comp('1', pg_temp.fijas(1), jsonb_build_object('status', 'pausada') || v)) #>> '{slide,dwell_seconds}', 'null'), ' ' order by o)
                  from (values (1, '{"dwell_seconds": null}'::jsonb), (2, '{"dwell_seconds": ""}'), (3, '{}'), (4, '{"dwell_seconds": 60}')) x(o, v)),
               'null null null 60', 'dwell null, blank or absent is stored as null (60 on the TV); 60 as 60');
-- which TVs: the menu TV may be named (it shows them only while it intercalates promotions)
select test.eq((select string_agg(pg_temp.err(r) || coalesce(':' || (r #>> '{slide,screen_ids}'), ''), ' ' order by o)
                  from (values (1, '["menu-1"]'::jsonb), (2, '["menu-1", "promos-1"]'), (3, '["menu-9"]'), (4, '"menu-1"')) x(o, v)
                  cross join lateral (select public.diapositiva_guardar(pg_temp.comp('1', pg_temp.fijas(1), jsonb_build_object('status', 'pausada', 'screen_ids', v)))) y(r)),
               'ok:["menu-1"] ok:["menu-1", "promos-1"] invalid/screen_ids invalid/screen_ids', 'a composition may name the menu TV, never an unknown one, and only as a list');
select test.eq(pg_temp.err(public.diapositiva_guardar(jsonb_build_object('kind', 'marca', 'title_es', 'En la A', 'starts_at', now() - interval '1 hour', 'ends_at', now() + interval '30 days', 'status', 'pausada', 'screen_ids', '["menu-1"]'::jsonb))),
               'ok', 'a brand slide may name the menu TV too');
-- changes: the zones stay unless given; the template and the zones change together; the kind never
select pg_temp.slide(jsonb_build_object('id', :'c_desayuno', 'kicker_es', 'Desayunos', 'dwell_seconds', 120)) as r \gset
select test.eq(pg_temp.brief(:'r'), 'true · 1 logged · cambiar diapositiva by owner login · owner@test.local', 'a change of the kicker and the dwell');
select test.eq(((:'r'::jsonb) #>> '{slide,kicker_es}') || ' ' || ((:'r'::jsonb) #>> '{slide,dwell_seconds}') || ' ' || ((:'r'::jsonb) #>> '{slide,template}') || ' ' || jsonb_array_length((:'r'::jsonb) #> '{slide,zones}') || ' ' || ((:'r'::jsonb) #>> '{slide,zones,0,entries,0,item,name}'),
               'Desayunos 120 4-centro 4 Latte', 'the template and the zones stay');
select test.ok((:'r'::jsonb) #> '{_log,before,zones}' = :'z_desayuno'::jsonb and (:'r'::jsonb) #> '{_log,after,zones}' = :'z_desayuno'::jsonb and (:'r'::jsonb) #>> '{_log,before,kicker_es}' = 'Desayuno'
               and (:'r'::jsonb) #>> '{_log,summary}' = 'composición · 4-centro', 'the log: the zones before and after as written, the kicker before, the summary');
select test.eq((select string_agg(pg_temp.err(r) || '/' || (r ->> '_logged'), ' ' order by o)
                  from (values (1, '{"template": "1"}'::jsonb), (2, '{"kind": "marca"}'), (3, jsonb_build_object('zones', pg_temp.fijas(1))), (4, '{"zones": "x"}'), (5, '{"dwell_seconds": 5}'),
                               (6, '{"template": "siete"}'), (7, jsonb_build_object('zones', :'z_desayuno'::jsonb || jsonb_build_array(jsonb_build_object('entries', jsonb_build_array(jsonb_build_object('item', :'shot'))))))) x(o, v)
                  cross join lateral (select pg_temp.slide(jsonb_build_object('id', :'c_desayuno') || v)) y(r)),
               'invalid/zones/0 invalid/kind/0 invalid/zones/0 invalid/zones/0 invalid/dwell_seconds/0 invalid/template/0 too_many/zones/0',
               'a change cannot leave the template with the wrong number of zones, change the kind, break a range, name an unknown template or pass four zones');
select pg_temp.slide(jsonb_build_object('id', :'c_desayuno', 'template', '2-lado', 'zones', pg_temp.fijas(2))) as r \gset
select test.eq(pg_temp.brief(:'r') || ' · ' || ((:'r'::jsonb) #>> '{_log,summary}') || ' · ' || jsonb_array_length((:'r'::jsonb) #> '{_log,before,zones}') || '>' || jsonb_array_length((:'r'::jsonb) #> '{_log,after,zones}'),
               'true · 1 logged · cambiar diapositiva by owner login · owner@test.local · composición · 2-lado · 4>2', 'template and zones change together; the log has four zones before, two after');
select test.eq(pg_temp.slide(jsonb_build_object('id', :'c_desayuno', 'template', '4-centro', 'zones', :'z_desayuno'::jsonb)) #> '{_log,after,zones}', :'z_desayuno'::jsonb, 'and back to the four windows (the stored form is accepted as given)');
-- the other kinds know nothing of the new fields
select pg_temp.slide(jsonb_build_object('kind', 'marca', 'title_es', 'Café de altura', 'starts_at', now() - interval '1 hour', 'ends_at', now() + interval '30 days', 'sort', 1,
                                        'template', '1', 'zones', pg_temp.fijas(1), 'dwell_seconds', 30)) as r \gset
select test.eq(pg_temp.brief(:'r'), 'true · 1 logged · crear diapositiva by owner login · owner@test.local', 'a brand slide given a template, zones and a dwell: accepted…');
select (:'r'::jsonb) #>> '{slide,id}' as s_marca \gset
select test.eq(jsonb_build_array((:'r'::jsonb) #> '{slide,template}', (:'r'::jsonb) #> '{slide,zones}', (:'r'::jsonb) #> '{slide,dwell_seconds}', (:'r'::jsonb) #> '{slide,usable}'), '[null, [], null, null]'::jsonb,
               '…and they are ignored: no template, no zones, no dwell, usable not even asked');
select pg_temp.slide(jsonb_build_object('kind', 'producto', 'menu_item_id', :'latte', 'starts_at', now() - interval '1 hour', 'ends_at', now() + interval '30 days', 'sort', 2)) as r \gset
select test.eq(pg_temp.brief(:'r'), 'true · 1 logged · crear diapositiva by owner login · owner@test.local', 'a product slide as in 0036');
select test.eq(jsonb_build_array((:'r'::jsonb) #> '{slide,template}', (:'r'::jsonb) #> '{slide,zones}', (:'r'::jsonb) #> '{slide,usable}', (:'r'::jsonb) #> '{slide,item,name}'), '[null, [], null, "Latte"]'::jsonb,
               'carries its product live and nothing of a composition');
select test.eq(pg_temp.err(pg_temp.slide(jsonb_build_object('id', :'s_marca', 'kind', 'composicion', 'template', '1', 'zones', pg_temp.fijas(1)))), 'invalid/kind', 'a brand slide never becomes a composition');
-- a composition is paused, resumed and retired like any slide
select pg_temp.st(:'c_desayuno', 'pausada') as r \gset
select test.eq(pg_temp.brief(:'r') || ' · ' || ((:'r'::jsonb) #>> '{_log,summary}'), 'true · 1 logged · pausar diapositiva by owner login · owner@test.local · composición · 4-centro',
               'a composition is paused like any slide, its template as the summary of the log line…');
select pg_temp.st(:'c_desayuno', 'activa') as r \gset
select test.eq(pg_temp.brief(:'r') || ' · ' || ((:'r'::jsonb) #>> '{_log,summary}'), 'true · 1 logged · reanudar diapositiva by owner login · owner@test.local · composición · 4-centro', '…and resumed');
reset role;

-- 5) who may: the owner only, as 0036 -----------------------------------------------------------------------------------
select test.login('cafe', 'aal1', current_setting('test.h_ana')::jsonb); set role authenticated;
select test.eq(pg_temp.err(public.diapositiva_guardar(pg_temp.comp('1', pg_temp.fijas(1)))) || ' ' || pg_temp.err(public.pantalla_guardar('{"id": "menu-1", "promo_mode": "intercalar"}')), 'owner_only owner_only',
               'a manager''s PIN can neither make a composition nor intercalate promotions in the menu TV');
reset role;
select test.login('cafe'); set role authenticated;
select test.eq(pg_temp.err(public.diapositiva_guardar(pg_temp.comp('1', pg_temp.fijas(1)))), 'owner_only', 'the café login alone neither');
reset role;
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(pg_temp.err(public.diapositiva_guardar(pg_temp.comp('1', pg_temp.fijas(1)))), 'owner_only', 'nor the accountant with the phone code');
reset role;
select test.login('owner', 'aal1'); set role authenticated;
select test.eq(pg_temp.err(public.diapositiva_guardar(pg_temp.comp('1', pg_temp.fijas(1)))), 'owner_only', 'nor the owner''s login without it');
reset role;
select test.login('anon'); set role anon;
select test.throws($$select public.diapositiva_guardar('{"kind": "composicion"}')$$, 'permission denied', 'a visitor cannot even call it');
reset role;
select test.login('cafe', 'aal1', current_setting('test.h_dueno')::jsonb); set role authenticated;
select pg_temp.slide(pg_temp.comp('1', jsonb_build_array(pg_temp.fija(pg_temp.ep('https://example.com/terraza.jpg'))), '{"kicker_es": "Terraza", "sort": 15}')) as r \gset
select test.eq(pg_temp.brief(:'r'), 'true · 1 logged · crear diapositiva by Dueño (owner)', 'the owner''s PIN makes one (a single fixed photo: the whole screen)');
select test.eq(pg_temp.muestra((:'r'::jsonb) -> 'slide'), 'true · true', 'a photo alone can always show');
-- the rest of the slides the TVs will read (the owner's PIN): one per rule
select pg_temp.slide(pg_temp.comp('1', jsonb_build_array(pg_temp.fija(pg_temp.ei(:'tea'))), '{"kicker_es": "Solo té", "sort": 11}')) ->> 'ok' as ok1,
       pg_temp.slide(pg_temp.comp('1', jsonb_build_array(pg_temp.fija(pg_temp.ei(:'ham'))), '{"kicker_es": "Solo en la A", "sort": 12, "screen_ids": ["menu-1"]}')) ->> 'ok' as ok2,
       pg_temp.slide(pg_temp.comp('1', jsonb_build_array(pg_temp.fija(pg_temp.ei(:'bread'))), '{"kicker_es": "Solo en la B", "sort": 13, "screen_ids": ["promos-1"]}')) ->> 'ok' as ok3,
       pg_temp.slide(pg_temp.comp('1', jsonb_build_array(pg_temp.fija(pg_temp.ei(:'temp_item'))), '{"kicker_es": "De prueba", "sort": 14}')) ->> 'ok' as ok4,
       pg_temp.slide(pg_temp.comp('1', jsonb_build_array(pg_temp.fija(pg_temp.ei(:'temp_item', '{"photo": "https://example.com/prueba.jpg"}'))), '{"kicker_es": "De prueba con foto", "sort": 16}')) ->> 'ok' as ok5 \gset
select test.eq(:'ok1' || :'ok2' || :'ok3' || :'ok4' || :'ok5', repeat('true', 5), 'five more compositions: only tea, only on the menu TV, only on the promotions TV, the test item alone, the test item with a photo');
reset role;
select test.eq((select count(*)::int from public.screen_slides) || ' ' || (select count(*)::int from public.screen_changes) || ' ' || (select count(*)::int from public.screen_changes where by_name !~ '(Dueño|owner login)'),
               '24 39 0', '24 slides (15 of them paused), 39 lines in the log, every one by the owner');

-- 6) what the TVs show (read as a visitor) -------------------------------------------------------------------------------
select test.login('anon'); set role anon;
select test.eq(public.pantalla_datos('menu-1') -> 'slides', '[]'::jsonb, 'the menu TV with promo_mode = no: no slides, though some name it');
select test.eq(pg_temp.shown('promos-1'), 'Café de altura | Latte | Desayunos | Solo té | Solo en la B | De prueba | Terraza | De prueba con foto',
               'the promotions TV: the brand, the product, the compositions in force (not the paused ones, not the menu TV''s), in order');
reset role;
select test.login('cafe', 'aal1', current_setting('test.h_dueno')::jsonb); set role authenticated;
select test.eq(pg_temp.brief(pg_temp.tv('{"id": "menu-1", "promo_mode": "intercalar", "promo_every": 120, "promo_seconds": 8}')), 'true · 1 logged · cambiar tv by Dueño (owner)', 'the owner intercalates promotions in the menu TV');
reset role;
select test.login('anon'); set role anon;
select test.eq(pg_temp.shown('menu-1'), 'Café de altura | Latte | Desayunos | Solo té | Solo en la A | De prueba | Terraza | De prueba con foto',
               'now the menu TV reads its slides: those for every TV and those naming it, never the promotions TV''s own');
select test.eq(pg_temp.v2(public.pantalla_datos('menu-1') -> 'tv'), 'density=normal english=debajo layout=auto promo_every=120 promo_mode=intercalar promo_seconds=8', 'with how often and how long');
select pg_temp.leida('promos-1', 'Desayunos') as d \gset
select test.eq((:'d'::jsonb) #> '{zones,0,entries,0,item}', jsonb_build_object('id', :'latte', 'name', 'Latte', 'name_es', null, 'price_crc', 2200, 'photo_url', null, 'available', true, 'category', 'Coffee', 'sellable', true),
               'a visitor gets each entry''s product live: name, price, photo, availability');
select test.eq(pg_temp.muestra(:'d'::jsonb) || ' · ' || ((:'d'::jsonb) ->> 'template') || ' · ' || ((:'d'::jsonb) ->> 'dwell_seconds'), 'true true true true · true · 4-centro · 120', 'the four windows can show; the template and the dwell');
select test.ok(public.pantalla_datos('promos-1')::text !~ '(Dueño|owner login|created_by|updated_by|created_at)', 'nothing about who in what the TVs read');
select test.eq((select string_agg(coalesce(s ->> 'usable', 'null') || '/' || jsonb_array_length(s -> 'zones'), ' ' order by o) from jsonb_array_elements(public.pantalla_datos('promos-1') -> 'slides') with ordinality x(s, o) where s ->> 'kind' <> 'composicion'),
               'null/0 null/0', 'the brand and the product slides: no zones, usable not asked');
-- a GET: PostgREST reads a STABLE function in a read-only transaction
savepoint ro;
set transaction read only;
select jsonb_array_length(public.pantalla_datos('menu-1') -> 'slides') as ro_slides, current_setting('transaction_read_only') as ro_on \gset
rollback to savepoint ro;
reset role;
select test.eq(:'ro_on' || ' ' || :'ro_slides', 'on 8', 'the menu TV''s read with promotions answers inside a read-only transaction');
-- stored by hand, as diapositiva_guardar never writes them (a hand edit, an older page): an item of 36 hex characters that is not a uuid,
-- and windows without labels whose product has no photo of its own nor in the menu. Inside a savepoint undone after the read, so the
-- counts below stay as they are (the values are captured first and asserted after the rollback, as the read-only check above)
savepoint a_mano;
insert into public.screen_slides (kind, kicker_es, starts_at, ends_at, template, zones, sort) values
  ('composicion', 'A mano', now() - interval '1 hour', now() + interval '30 days', '4-cuadricula', jsonb_build_array(
     pg_temp.fija('{"item": "0123456789abcdef0123456789abcdef0123"}'::jsonb),
     pg_temp.fija(pg_temp.ei(:'latte'), '{"labels": false}'),
     pg_temp.fija(pg_temp.ei(:'latte', '{"photo": "https://example.com/latte.jpg"}'), '{"labels": false}'),
     pg_temp.fija(pg_temp.ep('https://example.com/mano.jpg'), '{"labels": false}')), 17),
  ('composicion', 'Sin rótulo', now() - interval '1 hour', now() + interval '30 days', '2-lado', jsonb_build_array(
     pg_temp.fija(pg_temp.ei(:'tea'), '{"labels": false}'),
     pg_temp.auto(jsonb_build_array(pg_temp.ei(:'bread'), pg_temp.ei(:'ham')), '{"labels": false, "fallback": "https://example.com/marca.jpg"}')), 18);
select pg_temp.muestra(public._slide_json(d)) as m_rotulo from public.screen_slides d where kicker_es = 'Sin rótulo' \gset
select test.login('anon'); set role anon;
select pg_temp.shown('promos-1') as m_shown, pg_temp.muestra(pg_temp.leida('promos-1', 'A mano')) as m_muestra,
       coalesce(pg_temp.leida('promos-1', 'A mano') #> '{zones,0,entries,0}', '{}'::jsonb) as m_e0, (pg_temp.leida('promos-1', 'Sin rótulo') is null)::text as m_oculta \gset
reset role;
rollback to savepoint a_mano;
select test.eq(:'m_shown'::text, 'Café de altura | Latte | Desayunos | Solo té | Solo en la B | De prueba | Terraza | De prueba con foto | A mano',
               'a hand-stored item that is not a uuid does not break the TV''s read: the composition shows by its other windows, the rest as before');
select test.eq(:'m_e0'::jsonb, '{"item": null, "photo": null, "focus": [50, 50], "zoom": 100}'::jsonb, 'that entry reads as no product and no photo');
select test.eq(:'m_muestra'::text, 'false false true true · true',
               'without labels: the bad item cannot show, nor the Latte without a photo of its own or in the menu (the page would draw nothing); '
               || 'the Latte with its own photo and the photo alone can');
select test.eq(:'m_rotulo' || ' · ' || :'m_oculta', 'false false · false · true',
               'a composition whose windows have no labels and no photo at all (fixed or presentation) is not usable and hides from the TV');

-- 7) nothing that existed was written, in all of the above ---------------------------------------------------------------
select test.eq(pg_temp.writes()::text, :'writes_before', 'no existing table got a single write');
select test.eq(pg_temp.fp(), :'fp_before', 'the menu, its categories, the current TV''s settings and group slides, the app settings and the general log are byte for byte the same');

-- 8) the menu decides, live: a change in the Menu Manager shows on the next read, without a write -----------------------------
update public.menu_items set available = false where id = :'tea';
update public.menu_items set price_crc = 2300, name_es = 'Café latte', photo_url = 'https://x.cr/latte.jpg' where id = :'latte';
update public.menu_items set price_crc = 0 where id = :'bread';
update public.menu_items set category_id = :'cat_extras' where id = :'ham';
delete from public.menu_items where id = :'temp_item';
select test.login('anon'); set role anon;
select test.eq(pg_temp.shown('promos-1'), 'Café de altura | Latte | Desayunos | Terraza | De prueba con foto',
               'sold out (only tea), deleted (the test item alone): a composition with no window to show hides by itself; the one whose item was deleted but has its own photo stays');
select test.eq(pg_temp.shown('menu-1'), 'Café de altura | Latte | Desayunos | Terraza | De prueba con foto', 'the menu TV too (the sandwich moved to «Extras & Combos» hides «Solo en la A»)');
select pg_temp.leida('promos-1', 'Desayunos') as d \gset
select test.eq(pg_temp.muestra(:'d'::jsonb), 'true true false true · true', 'the bread at price 0 cannot show even with its own photo; the tea''s window still can (its second entry is a photo alone)');
select test.eq(((:'d'::jsonb) #>> '{zones,0,entries,0,item,price_crc}') || ' ' || ((:'d'::jsonb) #>> '{zones,0,entries,0,item,name_es}') || ' ' || ((:'d'::jsonb) #>> '{zones,0,entries,0,item,photo_url}'),
               '2300 Café latte https://x.cr/latte.jpg', 'the new price, Spanish name and photo show on the next read');
select test.eq(((:'d'::jsonb) #>> '{zones,1,entries,0,item,sellable}') || ' ' || ((:'d'::jsonb) #>> '{zones,1,entries,0,item,available}') || ' ' || jsonb_array_length((:'d'::jsonb) #> '{zones,1,entries}'),
               'false false 2', 'the sold-out tea stays in its list, marked not sellable (the TV skips it)');
select test.eq(pg_temp.leida('promos-1', 'De prueba con foto') #> '{zones,0,entries,0}', '{"item": null, "photo": "https://example.com/prueba.jpg", "focus": [50, 50], "zoom": 100}'::jsonb,
               'a deleted product with its own photo reads as a photo alone (no name, no price)');
reset role;
-- a window without labels shows its product by the photo the menu gave it (stored by hand inside a savepoint, undone after the read)
savepoint a_mano_menu;
insert into public.screen_slides (kind, kicker_es, starts_at, ends_at, template, zones, sort) values
  ('composicion', 'Sin rótulo', now() - interval '1 hour', now() + interval '30 days', '2-lado', jsonb_build_array(
     pg_temp.fija(pg_temp.ei(:'latte'), '{"labels": false}'), pg_temp.fija(pg_temp.ei(:'bread', '{"photo": "https://example.com/pan.jpg"}'), '{"labels": false}')), 18);
select test.login('anon'); set role anon;
select pg_temp.muestra(pg_temp.leida('promos-1', 'Sin rótulo')) as m_menu \gset
reset role;
rollback to savepoint a_mano_menu;
select test.eq(:'m_menu'::text, 'true false · true', 'without labels, the Latte now shows by the photo the menu gave it; the bread at price 0 still cannot, even with its own photo');
update public.menu_items set available = true where id = :'tea';
update public.menu_items set price_crc = -1 where id = :'bread';
update public.menu_items set name = '   ' where id = :'latte';
select test.login('anon'); set role anon;
select test.eq(pg_temp.shown('promos-1'), 'Café de altura | Desayunos | Solo té | Terraza | De prueba con foto', 'back in stock it shows again; a negative price or a blank name hides a product');
select test.eq(pg_temp.muestra(pg_temp.leida('promos-1', 'Desayunos')), 'false true false true · true', 'the blank-named latte''s window cannot show; the composition is still usable by its other windows');
reset role;
update public.menu_items set name = 'Latte' where id = :'latte';
select test.eq((select count(*)::int from public.screen_changes) || ' ' || (select count(*)::int from public.screen_slides where status = 'activa'), '40 9',
               'the menu''s changes write nothing in the screens'' log and change no slide (they only hide)');
select test.eq((select zones::text !~ '(2300|latte\.jpg|Café latte|Latte|price_crc)' from public.screen_slides where id = :'c_desayuno'), true, 'the composition''s row still holds ids, never the menu''s data');
-- the management page sees the same live data
select test.login('owner', 'aal2'); set role authenticated;
select test.eq((select (s #>> '{zones,0,entries,0,item,price_crc}') || ' ' || (s ->> 'usable') from jsonb_array_elements(public.pantallas_estado() -> 'slides') s where s ->> 'kicker_es' = 'Desayunos'), '2300 true',
               'pantallas_estado carries the zones with their products live, and usable');
select test.eq((select count(*)::int from jsonb_array_elements(public.pantallas_estado() -> 'slides') s where s ->> 'kind' = 'composicion'), 21, 'every composition, the paused ones too');
reset role;
select test.done();
rollback;
