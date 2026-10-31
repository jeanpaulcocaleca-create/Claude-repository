-- Migration 0036 (docs/PANTALLAS.md): the customer screens. The TVs read one public, read-only function (pantalla_datos);
-- only the owner (owner-role PIN, or the owner login with the phone code) manages them, every change in an append-only
-- log; the texts never carry a price, a combo or a discount; a product slide reads its name, price and availability
-- from the menu on every read and never writes it; nothing that existed before 0036 is written.
begin;
select id as latte from public.menu_items where name = 'Latte' \gset
select id as tea from public.menu_items where name = 'Tea' \gset
select id as bread from public.menu_items where name = 'Banana Bread' \gset
select id as box from public.menu_items where name = 'Adventure Box · Ham & Cheese or Monteverde' \gset
select id as shot from public.menu_items where name = 'Flavor shot' \gset
select id as combo from public.menu_items where name ~ '^Combo discount' \gset
select 'a0000000-0000-4000-8000-000000000001' as cat_coffee, 'a0000000-0000-4000-8000-000000000003' as cat_smoothies,
       'a0000000-0000-4000-8000-000000000009' as cat_extras \gset
-- an item the test deletes later (as the Menu Manager may)
insert into public.menu_items (id, category_id, name, price_crc) values ('1b000000-0000-4000-8000-000000004401', :'cat_coffee', 'Café de prueba 440', 1900);

-- the unlocks first (each one writes its own log line): the window below then must write nothing outside the screens' tables
select test.login('cafe'); set role authenticated;
select set_config('test.h_ana', test.unlock(test.staff('ana'), '4826')::text, false) \g /dev/null
select test.login('cafe'); select set_config('test.h_dueno', test.unlock(test.staff('dueno'), '7391')::text, false) \g /dev/null
reset role;

-- every write outside the three new tables in this transaction, per table (pg_stat_xact_*), and fingerprints of what
-- the screens read: the menu, the current TV's tables, the general log, the settings
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

-- every guard in one string; each probe stops right after the guard when allowed (a bad scale, no dates, an unknown
-- slide), so an allowed caller writes nothing either
create function pg_temp.guards() returns text language sql as $$
  select concat_ws(' ',
    'estado=' || coalesce(public.pantallas_estado() ->> 'error', 'ok'),
    'pantalla=' || coalesce(public.pantalla_guardar('{"id": "menu-1", "scale_pct": 999}') ->> 'error', 'ok'),
    'diapositiva=' || coalesce(public.diapositiva_guardar('{"kind": "marca", "title_es": "Hola"}') ->> 'error', 'ok'),
    'estado_diapositiva=' || coalesce(public.diapositiva_estado('00000000-0000-4000-8000-000000000000', 'pausada') ->> 'error', 'ok')) $$;
select 'estado=owner_only pantalla=owner_only diapositiva=owner_only estado_diapositiva=owner_only' as all_closed,
       'estado=ok pantalla=invalid diapositiva=dates_required estado_diapositiva=not_found' as all_open \gset

-- the owner's writes, each with what it logged: read back through pantallas_estado (the log itself is closed to logins)
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
-- "ok · 1 logged · crear diapositiva by …" or "false invalid/kind · 0 logged"
create function pg_temp.brief(r jsonb) returns text language sql as $$
  select coalesce(r ->> 'ok', '?') || coalesce(' ' || (r ->> 'error'), '') || coalesce('/' || (r ->> 'field'), '')
      || ' · ' || coalesce(r ->> '_logged', '?') || ' logged'
      || coalesce(' · ' || (r -> '_log' ->> 'action') || ' ' || (r -> '_log' ->> 'target_kind') || ' by ' || (r -> '_log' ->> 'by'), '') $$;
-- a dated slide of the brand, with p on top
create function pg_temp.marca(p jsonb) returns jsonb language sql as $$
  select jsonb_build_object('kind', 'marca', 'title_es', 'Café de altura', 'starts_at', now() - interval '1 hour', 'ends_at', now() + interval '30 days') || p $$;
-- one forbidden text tried in each of the six text fields: "field=error/field ..."
create function pg_temp.text_rule(t text) returns text language sql as $$
  select string_agg(f || '=' || coalesce(r ->> 'error', 'ok') || '/' || coalesce(r ->> 'field', '-'), ' ' order by o)
    from unnest(array['kicker_es', 'kicker_en', 'title_es', 'title_en', 'body_es', 'body_en']) with ordinality u(f, o)
         cross join lateral (select public.diapositiva_guardar(pg_temp.marca(jsonb_build_object(f, t)))) x(r) $$;
-- a product slide in force for a month (no text of its own: the screens show the product's name)
create function pg_temp.producto(i uuid, o int) returns jsonb language sql as $$
  select jsonb_build_object('kind', 'producto', 'menu_item_id', i, 'starts_at', now() - interval '1 hour', 'ends_at', now() + interval '30 days', 'sort', o) $$;
create function pg_temp.want(e text) returns text language sql as $$
  select string_agg(f || '=' || e || '/' || f, ' ' order by o)
    from unnest(array['kicker_es', 'kicker_en', 'title_es', 'title_en', 'body_es', 'body_en']) with ordinality u(f, o) $$;
-- the slides a TV shows now, by title (or the product's name)
create function pg_temp.shown(tv text) returns text language sql as $$
  select coalesce(string_agg(coalesce(s ->> 'title_es', s -> 'item' ->> 'name'), ' | ' order by o), '')
    from jsonb_array_elements(public.pantalla_datos(tv) -> 'slides') with ordinality x(s, o) $$;

-- 1) rights, from the catalog ---------------------------------------------------------------------------------------------
select test.eq((select string_agg(p.oid::regprocedure::text, ', ' order by p.proname) from pg_proc p
                 where p.pronamespace = 'public'::regnamespace and p.proname ~ '^(pantalla|diapositiva|_screen|_slide)'),
               '_screen_changes_immutable(), _screen_json(screens), _screen_log(text,text,text,text,jsonb,jsonb), _screen_text_problem(text), '
               || '_slide_json(screen_slides), diapositiva_estado(uuid,text), diapositiva_guardar(jsonb), pantalla_datos(text), '
               || 'pantalla_guardar(jsonb), pantallas_estado()', 'the ten functions of 0036, no other');
select test.eq((select string_agg(p.proname, ' ' order by p.proname) from pg_proc p
                 where p.pronamespace = 'public'::regnamespace and p.proname ~ '^(pantalla|diapositiva|_screen|_slide)'
                   and has_function_privilege('anon', p.oid, 'execute')), 'pantalla_datos', 'a visitor (the TVs) may run pantalla_datos and nothing else new');
select test.eq((select string_agg(p.proname, ' ' order by p.proname) from pg_proc p
                 where p.pronamespace = 'public'::regnamespace and p.proname ~ '^(pantalla|diapositiva|_screen|_slide)'
                   and has_function_privilege('authenticated', p.oid, 'execute')),
               'diapositiva_estado diapositiva_guardar pantalla_datos pantalla_guardar pantallas_estado',
               'a login may call the five functions of the API (each checks the owner itself), never the internal ones');
select test.eq((select count(*)::int from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname ~ '^(pantalla|diapositiva|_screen|_slide)'
                   and has_function_privilege('canopy_backup', p.oid, 'execute')), 0, 'the backup account can run none of them');
select test.eq((select string_agg(p.proname, ' ' order by p.proname) from pg_proc p
                 where p.pronamespace = 'public'::regnamespace and p.proname ~ '^(pantalla|diapositiva|_screen|_slide)' and p.prosecdef),
               '_screen_log diapositiva_estado diapositiva_guardar pantalla_datos pantalla_guardar pantallas_estado', 'the owner-rights functions');
select test.eq((select count(*)::int from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname ~ '^(pantalla|diapositiva|_screen|_slide)'
                   and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c = 'search_path=public')), 0,
               'every one of them fixes its search path');
select test.eq((select string_agg(p.proname || '=' || p.provolatile::text, ' ' order by p.proname) from pg_proc p
                 where p.pronamespace = 'public'::regnamespace and p.proname in ('pantalla_datos', 'pantallas_estado', 'pantalla_guardar', 'diapositiva_guardar', 'diapositiva_estado')),
               'diapositiva_estado=v diapositiva_guardar=v pantalla_datos=s pantalla_guardar=v pantallas_estado=s',
               'pantalla_datos and pantallas_estado are STABLE (a GET reads them in a read-only transaction); the three writers are not');
select test.eq((select count(*)::int from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname ~ '^(pantalla|diapositiva|_screen|_slide)'
                   and p.prosrc ~ '_verify_pin|crypt\('), 0, 'none of them checks a PIN itself (the unlock is the shared one)');
select test.ok((select bool_and(c.relrowsecurity) from pg_class c where c.oid in ('public.screens'::regclass, 'public.screen_slides'::regclass, 'public.screen_changes'::regclass)),
               'the three tables have row security');
select test.eq((select count(*)::int from pg_policies where schemaname = 'public' and tablename in ('screens', 'screen_slides', 'screen_changes')), 0,
               'and no rule at all: nobody reads or writes them but the functions');
select test.ok(not exists (select 1 from unnest(array['anon', 'authenticated']) r, unnest(array['public.screens', 'public.screen_slides', 'public.screen_changes']) t
                            where has_table_privilege(r, t, 'select,insert,update,delete,truncate,references,trigger')),
               'neither a visitor nor a login has any right on the three tables');
select test.ok(has_table_privilege('canopy_backup', 'public.screens', 'select') and has_table_privilege('canopy_backup', 'public.screen_slides', 'select')
               and has_table_privilege('canopy_backup', 'public.screen_changes', 'select') and has_sequence_privilege('canopy_backup', 'public.screen_changes_id_seq', 'select')
               and not has_table_privilege('canopy_backup', 'public.screen_slides', 'insert,update,delete'),
               'the backup account reads the three tables (and the log''s sequence), and writes nothing');
select test.eq((select string_agg(tgname, ' ' order by tgname) from pg_trigger where tgrelid = 'public.screen_changes'::regclass and not tgisinternal),
               'screen_changes_immutable screen_changes_no_truncate', 'the log''s guard: one trigger for update/delete, one for truncate');
select test.eq((select string_agg(id || ':' || kind || ':' || active, ' ' order by id) from public.screens), 'menu-1:menu:true promos-1:promos:true',
               'born with the two TVs of the plan');
select test.eq((select count(*)::int from public.screen_slides) + (select count(*)::int from public.screen_changes), 0, 'and no slide, no change');

-- 2) a visitor: the TVs read pantalla_datos and nothing else ----------------------------------------------------------------
select test.login('anon'); set role anon;
select test.eq(public.pantalla_datos('menu-1') ->> 'ok', 'true', 'a visitor reads the menu TV''s settings');
select test.eq((select string_agg(k, ' ' order by k) from jsonb_object_keys(public.pantalla_datos('menu-1')) k), 'now ok slides tv', 'the answer: ok, now, tv, slides');
select test.eq((select string_agg(k, ' ' order by k) from jsonb_object_keys(public.pantalla_datos('menu-1') -> 'tv') k),
               'active category_ids distance_m id inches kind look name on_from on_to page_seconds scale_pct slide_seconds sold_out turn updated_at',
               'the TV''s settings, exactly the contract''s');
select test.eq(public.pantalla_datos('menu-1') #>> '{tv,scale_pct}', '100', 'with the prudent values of the plan');
select test.ok((public.pantalla_datos('promos-1') ->> 'now')::timestamptz = now(), 'and the server''s clock (a TV with a wrong clock still ends a slide on time)');
select test.eq(public.pantalla_datos('nope'), jsonb_build_object('ok', false, 'error', 'unknown_tv', 'now', now()), 'an unknown TV: unknown_tv, with the time');
select test.eq(public.pantalla_datos(null) ->> 'error', 'unknown_tv', 'no TV given: the same');
select test.throws($$select * from public.screens$$, 'permission denied', 'a visitor cannot read the TVs table');
select test.throws($$select * from public.screen_slides$$, 'permission denied', 'nor the slides');
select test.throws($$select * from public.screen_changes$$, 'permission denied', 'nor the change log');
select test.throws($$insert into public.screen_slides (kind, title_es, starts_at, ends_at) values ('marca', 'x', now(), now() + interval '1 day')$$,
                   'permission denied', 'nor write a slide');
select test.throws($$select public.pantallas_estado()$$, 'permission denied', 'nor call pantallas_estado');
select test.throws($$select public.pantalla_guardar('{"id": "menu-1"}')$$, 'permission denied', 'nor pantalla_guardar');
select test.throws($$select public.diapositiva_guardar('{}')$$, 'permission denied', 'nor diapositiva_guardar');
select test.throws($$select public.diapositiva_estado(gen_random_uuid(), 'pausada')$$, 'permission denied', 'nor diapositiva_estado');
select test.throws($$select public._screen_text_problem('x')$$, 'permission denied', 'nor an internal helper');
reset role;

-- 3) who manages them: only the owner ----------------------------------------------------------------------------------------
select test.login('cafe'); set role authenticated;
select test.eq(pg_temp.guards(), :'all_closed', 'the café login without a PIN: owner_only from every owner function');
select test.throws($$select * from public.screens$$, 'permission denied', 'and the tables stay closed to a login');
reset role;
select test.login('cafe', 'aal1', current_setting('test.h_ana')::jsonb); set role authenticated;
select test.eq(public.access_level(), 'manager', 'café + Ana''s manager PIN: the owner areas are open (Menu Manager, Home)…');
select test.eq(pg_temp.guards(), :'all_closed', '…but a manager PIN is not the owner''s: owner_only from every owner function');
select test.eq(public.pantalla_guardar('{"id": "menu-1", "scale_pct": 120}') ->> 'error', 'owner_only', 'a manager cannot change a TV');
reset role;
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(pg_temp.guards(), :'all_closed', 'the accountant with the phone code: owner_only');
reset role;
select test.login('accountant', 'aal1'); set role authenticated;
select test.eq(pg_temp.guards(), :'all_closed', 'the accountant without it: owner_only');
reset role;
select test.login('owner', 'aal1'); set role authenticated;
select test.eq(pg_temp.guards(), :'all_closed', 'the owner''s login without the phone code: owner_only');
reset role;
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(pg_temp.guards(), :'all_open', 'the owner''s login with the phone code: every owner function opens');
reset role;
select test.login('cafe', 'aal1', current_setting('test.h_dueno')::jsonb); set role authenticated;
select test.eq(public.access_level(), 'owner', 'café + the Dueño''s owner PIN');
select test.eq(pg_temp.guards(), :'all_open', 'the owner PIN opens every owner function');
reset role;
select test.eq((select count(*)::int from public.screen_changes) + (select count(*)::int from public.screen_slides), 0, 'the probes wrote nothing');
select test.eq((select string_agg(id || ':' || scale_pct, ' ' order by id) from public.screens), 'menu-1:100 promos-1:100', 'nor changed a TV');

-- 4) a TV's settings (café + owner PIN) ----------------------------------------------------------------------------------
select test.login('cafe', 'aal1', current_setting('test.h_dueno')::jsonb); set role authenticated;
select pg_temp.tv(jsonb_build_object('id', 'menu-1', 'scale_pct', 120, 'distance_m', 4.5, 'look', 'noche', 'page_seconds', 30,
                                     'category_ids', jsonb_build_array(:'cat_coffee', :'cat_smoothies'), 'sold_out', 'tachar',
                                     'on_from', '06:30', 'on_to', '18:00')) as r \gset
select test.eq(pg_temp.brief(:'r'), 'true · 1 logged · cambiar tv by Dueño (owner)', 'the owner changes the menu TV: one line in the log, with the name');
select test.eq(((:'r'::jsonb) -> 'tv') - 'updated_at',
               jsonb_build_object('id', 'menu-1', 'kind', 'menu', 'name', 'Pantalla A · menú', 'inches', 55.0, 'distance_m', 4.5, 'turn', 'no', 'scale_pct', 120,
                                  'look', 'noche', 'page_seconds', 30, 'slide_seconds', 10, 'category_ids', jsonb_build_array(:'cat_coffee', :'cat_smoothies'),
                                  'sold_out', 'tachar', 'on_from', '06:30', 'on_to', '18:00', 'active', true), 'saved as asked, the rest kept');
select test.ok((:'r'::jsonb) #>> '{_log,before,scale_pct}' = '100' and (:'r'::jsonb) #>> '{_log,after,scale_pct}' = '120'
               and (:'r'::jsonb) #>> '{_log,target_id}' = 'menu-1' and (:'r'::jsonb) #>> '{_log,summary}' = 'Pantalla A · menú',
               'the log keeps what it was and what it is now');
select test.eq(pg_temp.brief(pg_temp.tv('{"id": "menu-1", "kind": "promos"}')), 'false invalid/kind · 0 logged', 'a TV''s kind never changes');
select test.eq(pg_temp.brief(pg_temp.tv('{"id": "menu-1", "kind": "menu", "name": "  Pantalla A · menú  "}')), 'true · 1 logged · cambiar tv by Dueño (owner)',
               'the same kind again is fine (the name is trimmed)');
select test.eq(pg_temp.brief(pg_temp.tv('{"id": "menu-2", "name": "Patio"}')), 'false invalid/kind · 0 logged', 'a new TV needs its kind');
select test.eq(pg_temp.brief(pg_temp.tv('{"id": "Menu 2!", "kind": "menu"}')), 'false invalid/id · 0 logged', 'and a plain id');
select test.eq(pg_temp.brief(pg_temp.tv('{"id": "x", "kind": "menu"}')), 'false invalid/id · 0 logged', 'of two characters or more');
select pg_temp.tv('{"id": "MENU-2", "kind": "menu", "name": "Pantalla del patio"}') as r \gset
select test.eq(pg_temp.brief(:'r'), 'true · 1 logged · crear tv by Dueño (owner)', 'a new TV (its id in small letters)');
select test.ok((:'r'::jsonb) #>> '{tv,id}' = 'menu-2' and (:'r'::jsonb) -> '_log' -> 'before' = 'null'::jsonb, 'created with nothing before it');
select test.eq(pg_temp.brief(pg_temp.tv('{"id": "promos-2", "kind": "promos", "name": "Pantalla B · terraza"}')), 'true · 1 logged · crear tv by Dueño (owner)',
               'and a second promotions TV');
-- ranges, words and hours: refused, nothing written, nothing logged
select test.eq((select string_agg(k || '=' || coalesce(r ->> 'error', 'ok') || '/' || (r ->> '_logged'), ' ' order by o)
                  from (values (1, 'inches', '23'::jsonb), (2, 'inches', '111'), (3, 'distance_m', '0.5'), (4, 'distance_m', '16'), (5, 'scale_pct', '69'),
                               (6, 'scale_pct', '161'), (7, 'scale_pct', '"grande"'), (8, 'page_seconds', '14'), (9, 'page_seconds', '61'), (10, 'slide_seconds', '5'),
                               (11, 'slide_seconds', '31'), (12, 'turn', '"arriba"'), (13, 'look', '"neon"'), (14, 'sold_out', '"gris"'), (15, 'active', '"quizá"'),
                               (16, 'inches', '1000'), (17, 'scale_pct', '1.5'), (18, 'name', to_jsonb(repeat('a', 61)))) x(o, k, v)
                  cross join lateral (select pg_temp.tv(jsonb_build_object('id', 'menu-1') || jsonb_build_object(k, v))) y(r)),
               'inches=invalid/0 inches=invalid/0 distance_m=invalid/0 distance_m=invalid/0 scale_pct=invalid/0 scale_pct=invalid/0 scale_pct=invalid/0 '
               || 'page_seconds=invalid/0 page_seconds=invalid/0 slide_seconds=invalid/0 slide_seconds=invalid/0 turn=invalid/0 look=invalid/0 '
               || 'sold_out=invalid/0 active=invalid/0 inches=invalid/0 scale_pct=invalid/0 name=invalid/0',
               'every setting out of its range is refused and logs nothing');
select test.eq(pg_temp.brief(pg_temp.tv('{"id": "menu-1", "inches": 110, "distance_m": 15, "scale_pct": 160, "page_seconds": 60, "slide_seconds": 30}')),
               'true · 1 logged · cambiar tv by Dueño (owner)', 'the upper ends are accepted');
select test.eq(pg_temp.brief(pg_temp.tv('{"id": "menu-1", "inches": 24, "distance_m": 1, "scale_pct": 70, "page_seconds": 15, "slide_seconds": 6}')),
               'true · 1 logged · cambiar tv by Dueño (owner)', 'and the lower ends');
select test.eq(pg_temp.brief(pg_temp.tv('{"id": "menu-1", "name": "Pantalla ₡ 2500"}')), 'false text_precio/name · 0 logged', 'no price in a TV''s name either');
select test.eq((select string_agg(coalesce(pg_temp.tv(jsonb_build_object('id', 'menu-1', 'category_ids', v)) ->> 'field', 'ok'), ' ' order by o)
                  from (values (1, '["no-es-un-id"]'::jsonb), (2, '["00000000-0000-4000-8000-000000000000"]'), (3, jsonb_build_array(:'cat_extras')),
                               (4, jsonb_build_array(:'cat_coffee', null)), (5, to_jsonb(:'cat_coffee'::text)), (6, '{"a": 1}'), (7, '[1]')) x(o, v)),
               'category_ids category_ids category_ids category_ids category_ids category_ids category_ids',
               'category_ids: only categories of the menu, never «Extras & Combos», and only as a list');
reset role;
select test.eq((select count(*)::int from public.screen_changes where target_id = 'menu-1'), 4, 'none of those refusals was logged (4 changes of menu-1 so far)');
set role authenticated;
select test.eq(pg_temp.tv(jsonb_build_object('id', 'menu-1', 'category_ids', jsonb_build_array(:'cat_smoothies', :'cat_coffee'))) #> '{tv,category_ids}',
               jsonb_build_array(:'cat_smoothies', :'cat_coffee'), 'the categories in the owner''s order');
select test.eq(pg_temp.tv('{"id": "menu-1", "scale_pct": 110}') #> '{tv,category_ids}', jsonb_build_array(:'cat_smoothies', :'cat_coffee'), 'a change without the field keeps them');
select test.eq(pg_temp.tv('{"id": "menu-1", "category_ids": []}') #> '{tv,category_ids}', 'null'::jsonb, 'an empty list = every category');
select test.eq(pg_temp.tv(jsonb_build_object('id', 'menu-1', 'category_ids', jsonb_build_array(:'cat_coffee'))) #> '{tv,category_ids}', jsonb_build_array(:'cat_coffee'), 'one category');
select test.eq(pg_temp.tv('{"id": "menu-1", "category_ids": null}') #> '{tv,category_ids}', 'null'::jsonb, 'null = every category');
select test.eq((select string_agg(coalesce(r ->> 'error', 'ok') || '/' || (r ->> '_logged'), ' ' order by o)
                  from (select o, pg_temp.tv(jsonb_build_object('id', 'menu-1') || v) as r
                          from (values (1, '{"on_from": "06:30", "on_to": ""}'::jsonb), (2, '{"on_from": "07:00", "on_to": "07:00"}'), (3, '{"on_from": "25:00", "on_to": "18:00"}'),
                                       (4, '{"on_from": "mañana", "on_to": "18:00"}'), (5, '{"on_from": "", "on_to": "18:00"}')) x(o, v)) y),
               'invalid/0 invalid/0 invalid/0 invalid/0 invalid/0', 'hours: both or none, different, real times');
select test.eq(pg_temp.tv('{"id": "menu-1", "on_from": "", "on_to": ""}') -> 'tv' ->> 'on_from', null, 'both cleared = on all day');
select test.eq(pg_temp.tv('{"id": "menu-1", "on_from": "20:00", "on_to": "02:00"}') -> 'tv' ->> 'on_to', '02:00', 'across midnight is fine');
select test.eq(pg_temp.tv('{"id": "menu-1", "name": "   "}') #>> '{tv,name}', 'Pantalla A · menú', 'a blank name keeps the old one');
select test.eq(pg_temp.brief(pg_temp.tv('[1, 2]')), 'false invalid · 0 logged', 'not an object: invalid');
select test.eq(pg_temp.brief(pg_temp.tv(null)), 'false invalid · 0 logged', 'nothing: invalid');

-- 5) slides (the owner's login with the phone code) ---------------------------------------------------------------------
reset role;
select test.login('owner', 'aal2'); set role authenticated;
select pg_temp.slide(pg_temp.marca('{"title_es": "Café de altura de Monteverde", "title_en": "Monteverde highland coffee", "kicker_es": "Desde 1990", "sort": 10}')) as r \gset
select test.eq(pg_temp.brief(:'r'), 'true · 1 logged · crear diapositiva by owner login · owner@test.local', 'the owner''s login creates a brand slide, logged with its name');
select (:'r'::jsonb) #>> '{slide,id}' as s_marca \gset
reset role;
select test.eq((select created_by || ' / ' || updated_by || ' / ' || status from public.screen_slides where id = :'s_marca'),
               'owner login · owner@test.local / owner login · owner@test.local / activa', 'who created it, and active');
set role authenticated;
select test.eq((select string_agg(k, ' ' order by k) from jsonb_object_keys((:'r'::jsonb) -> 'slide') k),
               'body_en body_es days ends_at from_time id item kicker_en kicker_es kind link menu_item_id photo_url screen_ids sort starts_at status title_en title_es to_time',
               'a slide as the screens see it, exactly the contract''s');
select test.ok((:'r'::jsonb) #> '{_log,before}' = 'null'::jsonb and (:'r'::jsonb) #>> '{_log,after,title_es}' = 'Café de altura de Monteverde'
               and (:'r'::jsonb) #>> '{_log,summary}' = 'Café de altura de Monteverde' and not ((:'r'::jsonb) -> '_log' -> 'after') ? 'item',
               'the log: nothing before, the slide after (without the menu''s data), its title as the summary');
-- the owner's condition 7 and the screens' price rule, field by field
select test.eq(pg_temp.text_rule('Hoy ₡1 500'), pg_temp.want('text_precio'), '₡ is refused in every text');
select test.eq(pg_temp.text_rule('Solo $4'), pg_temp.want('text_precio'), '$ too');
select test.eq(pg_temp.text_rule('100% de Monteverde'), pg_temp.want('text_precio'), '% too');
select test.eq(pg_temp.text_rule('Dos mil colones'), pg_temp.want('text_precio'), 'colones too');
select test.eq(pg_temp.text_rule('Tres DÓLARES'), pg_temp.want('text_precio'), 'dólares too (any case)');
select test.eq(pg_temp.text_rule('El combo del día'), pg_temp.want('text_combo_descuento'), 'a combo is never announced');
select test.eq(pg_temp.text_rule('Con descuento'), pg_temp.want('text_combo_descuento'), 'nor a discount');
select test.eq(pg_temp.text_rule('2x1 en empanadas'), pg_temp.want('text_combo_descuento'), 'nor a 2x1');
select test.eq(pg_temp.text_rule('Galleta gratis'), pg_temp.want('text_combo_descuento'), 'nor something free');
select test.eq(pg_temp.text_rule('3x2 en empanadas') || ' ' || pg_temp.text_rule('2 por 1 los martes'), pg_temp.want('text_combo_descuento') || ' ' || pg_temp.want('text_combo_descuento'),
               'nor a 3x2 or a «2 por 1»');
select test.eq(pg_temp.text_rule(repeat('á', 141)), pg_temp.want('text_largo'), 'more than 140 characters is refused in every text');
reset role;
select test.eq((select count(*)::int from public.screen_slides), 1, 'none of those refusals saved a slide');
set role authenticated;
select pg_temp.slide(jsonb_build_object('kind', 'producto', 'menu_item_id', :'box', 'kicker_es', 'Para el sendero',
                                        'body_es', '¿Sale temprano mañana? Pida su Adventure Box', 'body_en', 'Leaving early tomorrow? Order your Adventure Box',
                                        'starts_at', now() - interval '1 day', 'ends_at', now() + interval '7 days', 'sort', 20)) as r \gset
select test.eq(pg_temp.brief(:'r'), 'true · 1 logged · crear diapositiva by owner login · owner@test.local', 'normal Spanish is accepted: «¿Sale temprano mañana? Pida su Adventure Box»');
select (:'r'::jsonb) #>> '{slide,id}' as s_box \gset
select test.eq((:'r'::jsonb) #>> '{_log,summary}', 'Adventure Box · Ham & Cheese or Monteverde', 'a product slide''s summary is the product''s name');
reset role;
select test.eq((select coalesce(menu_item_id::text, '') || '|' || coalesce(title_es, '-') || '|' || (to_jsonb(s) ? 'price_crc')::text from public.screen_slides s where id = :'s_box'),
               :'box' || '|-|false', 'a product slide stores the product, never its name or price');
set role authenticated;
select pg_temp.slide(pg_temp.marca(jsonb_build_object('title_es', repeat('á', 140), 'status', 'pausada'))) as r \gset
select test.eq(pg_temp.brief(:'r'), 'true · 1 logged · crear diapositiva by owner login · owner@test.local', '140 characters are accepted');
select test.eq((:'r'::jsonb) #>> '{slide,status}', 'pausada', 'created paused, as asked');
-- what a product slide may point at
select test.eq((select string_agg(coalesce(r ->> 'error', 'ok') || '/' || coalesce(r ->> 'field', '-'), ' ' order by o)
                  from (values (1, '{}'::jsonb), (2, '{"menu_item_id": "00000000-0000-4000-8000-000000000000"}'), (3, '{"menu_item_id": "abc"}'),
                               (4, jsonb_build_object('menu_item_id', :'shot')), (5, jsonb_build_object('menu_item_id', :'combo'))) x(o, v)
                  cross join lateral (select pg_temp.slide(pg_temp.marca('{}') || jsonb_build_object('kind', 'producto') || v)) y(r)),
               'invalid/menu_item_id invalid/menu_item_id invalid/menu_item_id text_combo_descuento/menu_item_id text_combo_descuento/menu_item_id',
               'a product slide needs a product of the menu, never one of «Extras & Combos» (the till''s helpers and the combo line)');
-- kinds, links, dates, days, hours, photos, TVs
select test.eq((select string_agg(coalesce(r ->> 'error', 'ok') || coalesce('/' || (r ->> 'field'), ''), ' ' order by o)
                  from (select o, public.diapositiva_guardar(v) as r from (values
                    (1, '{"kind": "aviso", "title_es": "x", "starts_at": "2026-11-01T08:00:00-06:00", "ends_at": "2026-11-02T08:00:00-06:00"}'::jsonb),
                    (2, '{"kind": "marca", "starts_at": "2026-11-01T08:00:00-06:00", "ends_at": "2026-11-02T08:00:00-06:00"}'),
                    (3, '{"kind": "invitacion", "title_es": "Déjenos una reseña", "starts_at": "2026-11-01T08:00:00-06:00", "ends_at": "2026-11-02T08:00:00-06:00"}'),
                    (4, '{"kind": "invitacion", "title_es": "Déjenos una reseña", "link": "instagram", "starts_at": "2026-11-01T08:00:00-06:00", "ends_at": "2026-11-02T08:00:00-06:00"}'),
                    (5, '{"kind": "marca", "title_es": "Hola"}'),
                    (6, '{"kind": "marca", "title_es": "Hola", "starts_at": "2026-11-01T08:00:00-06:00"}'),
                    (7, '{"kind": "marca", "title_es": "Hola", "ends_at": "2026-11-02T08:00:00-06:00"}'),
                    (8, '{"kind": "marca", "title_es": "Hola", "starts_at": "", "ends_at": "2026-11-02T08:00:00-06:00"}'),
                    (9, '{"kind": "marca", "title_es": "Hola", "starts_at": null, "ends_at": "2026-11-02T08:00:00-06:00"}'),
                    (10, '{"kind": "marca", "title_es": "Hola", "starts_at": "2026-11-02T08:00:00-06:00", "ends_at": "2026-11-02T08:00:00-06:00"}'),
                    (11, '{"kind": "marca", "title_es": "Hola", "starts_at": "2026-11-02T08:00:00-06:00", "ends_at": "2026-11-01T08:00:00-06:00"}'),
                    (12, '{"kind": "marca", "title_es": "Hola", "starts_at": "2026-11-01T08:00:00-06:00", "ends_at": "2027-11-03T08:00:00-06:00"}'),
                    (13, '{"kind": "marca", "title_es": "Hola", "starts_at": "pronto", "ends_at": "2026-11-02T08:00:00-06:00"}'),
                    (14, '{"kind": "marca", "title_es": "Hola", "starts_at": "2026-11-01T08:00:00-06:00", "ends_at": "2026-11-02T08:00:00-06:00", "days": [0]}'),
                    (15, '{"kind": "marca", "title_es": "Hola", "starts_at": "2026-11-01T08:00:00-06:00", "ends_at": "2026-11-02T08:00:00-06:00", "days": [8]}'),
                    (16, '{"kind": "marca", "title_es": "Hola", "starts_at": "2026-11-01T08:00:00-06:00", "ends_at": "2026-11-02T08:00:00-06:00", "days": ["lunes"]}'),
                    (17, '{"kind": "marca", "title_es": "Hola", "starts_at": "2026-11-01T08:00:00-06:00", "ends_at": "2026-11-02T08:00:00-06:00", "days": "1"}'),
                    (18, '{"kind": "marca", "title_es": "Hola", "starts_at": "2026-11-01T08:00:00-06:00", "ends_at": "2026-11-02T08:00:00-06:00", "days": [1, null]}'),
                    (19, '{"kind": "marca", "title_es": "Hola", "starts_at": "2026-11-01T08:00:00-06:00", "ends_at": "2026-11-02T08:00:00-06:00", "from_time": "07:00"}'),
                    (20, '{"kind": "marca", "title_es": "Hola", "starts_at": "2026-11-01T08:00:00-06:00", "ends_at": "2026-11-02T08:00:00-06:00", "from_time": "07:00", "to_time": "07:00"}'),
                    (21, '{"kind": "marca", "title_es": "Hola", "starts_at": "2026-11-01T08:00:00-06:00", "ends_at": "2026-11-02T08:00:00-06:00", "from_time": "07:00", "to_time": "24:30"}'),
                    (22, '{"kind": "marca", "title_es": "Hola", "starts_at": "2026-11-01T08:00:00-06:00", "ends_at": "2026-11-02T08:00:00-06:00", "photo_url": "javascript:alert(1)"}'),
                    (23, '{"kind": "marca", "title_es": "Hola", "starts_at": "2026-11-01T08:00:00-06:00", "ends_at": "2026-11-02T08:00:00-06:00", "photo_url": "https://x.cr/a b.jpg"}'),
                    (24, '{"kind": "marca", "title_es": "Hola", "starts_at": "2026-11-01T08:00:00-06:00", "ends_at": "2026-11-02T08:00:00-06:00", "screen_ids": ["menu-1"]}'),
                    (25, '{"kind": "marca", "title_es": "Hola", "starts_at": "2026-11-01T08:00:00-06:00", "ends_at": "2026-11-02T08:00:00-06:00", "screen_ids": ["promos-9"]}'),
                    (26, '{"kind": "marca", "title_es": "Hola", "starts_at": "2026-11-01T08:00:00-06:00", "ends_at": "2026-11-02T08:00:00-06:00", "screen_ids": "promos-1"}'),
                    (27, '{"kind": "marca", "title_es": "Hola", "starts_at": "2026-11-01T08:00:00-06:00", "ends_at": "2026-11-02T08:00:00-06:00", "sort": "primero"}'),
                    (28, '"marca"'), (29, '{"id": "no-es-un-id", "title_es": "Hola"}'), (30, '{"id": "00000000-0000-4000-8000-000000000000", "title_es": "Hola"}')
                  ) x(o, v)) y),
               'invalid/kind invalid invalid invalid dates_required dates_required dates_required dates_required dates_required invalid invalid invalid invalid '
               || 'invalid/days invalid/days invalid/days invalid/days invalid/days invalid invalid invalid invalid/photo_url invalid/photo_url '
               || 'invalid/screen_ids invalid/screen_ids invalid/screen_ids invalid invalid invalid/id not_found',
               'refused: unknown kind, a brand slide without title, an invitation without (or with an unknown) link, missing dates, ends not after starts, '
               || 'more than 366 days, days outside 1-7 or not a list, half or equal hours, a photo that is not a plain web address, a TV that is not a '
               || 'promotions one or not a list, a bad id, an unknown slide');
reset role;
select test.eq((select count(*)::int from public.screen_slides), 3, 'none of those saved anything');
set role authenticated;
select test.eq(pg_temp.brief(pg_temp.slide('{"kind": "marca", "title_es": "Un año", "starts_at": "2026-11-01T08:00:00-06:00", "ends_at": "2027-11-02T08:00:00-06:00", "status": "pausada"}')),
               'true · 1 logged · crear diapositiva by owner login · owner@test.local', '366 days are accepted');
select pg_temp.slide(pg_temp.marca(jsonb_build_object('kind', 'invitacion', 'title_es', '¿Le gustó? Déjenos una reseña', 'title_en', 'Enjoyed it? Leave us a review',
                                                      'link', 'resena', 'screen_ids', jsonb_build_array('promos-1'), 'days', '[5, 1, 3, 3]'::jsonb,
                                                      'from_time', '07:00', 'to_time', '11:30', 'photo_url', 'https://example.com/resena.jpg', 'sort', 30))) as r \gset
select test.eq(pg_temp.brief(:'r'), 'true · 1 logged · crear diapositiva by owner login · owner@test.local', 'an invitation to review, for promos-1, three mornings');
select (:'r'::jsonb) #>> '{slide,id}' as s_resena \gset
select test.eq((:'r'::jsonb) -> 'slide' -> 'days', '[1, 3, 5]'::jsonb, 'its days in order, each once');
select test.eq((:'r'::jsonb) #>> '{slide,from_time}' || '-' || ((:'r'::jsonb) #>> '{slide,to_time}') || ' ' || ((:'r'::jsonb) #>> '{slide,screen_ids,0}'), '07:00-11:30 promos-1', 'its hours and its TV');
select pg_temp.slide(pg_temp.marca('{"title_es": "Todos los días", "days": [1, 2, 3, 4, 5, 6, 7], "screen_ids": [], "status": "pausada"}')) -> 'slide' as r \gset
select test.ok((:'r'::jsonb) -> 'days' = 'null'::jsonb and (:'r'::jsonb) -> 'screen_ids' = 'null'::jsonb,
               'the seven days = every day (null); an empty TV list = every promotions TV (null)');
-- changes: a slide's kind never changes, a missing field stays, a blanked date is refused
select test.eq(pg_temp.brief(pg_temp.slide(jsonb_build_object('id', :'s_marca', 'kind', 'invitacion'))), 'false invalid/kind · 0 logged', 'a slide''s kind never changes');
select pg_temp.slide(jsonb_build_object('id', :'s_marca', 'title_en', 'Coffee from the Monteverde highlands')) as r \gset
select test.eq(pg_temp.brief(:'r'), 'true · 1 logged · cambiar diapositiva by owner login · owner@test.local', 'a change to one text');
select test.eq((:'r'::jsonb) #>> '{slide,title_es}' || ' | ' || ((:'r'::jsonb) #>> '{slide,kicker_es}') || ' | ' || ((:'r'::jsonb) #>> '{slide,sort}'),
               'Café de altura de Monteverde | Desde 1990 | 10', 'the other fields stay');
select test.ok((:'r'::jsonb) #>> '{_log,before,title_en}' = 'Monteverde highland coffee' and (:'r'::jsonb) #>> '{_log,after,title_en}' = 'Coffee from the Monteverde highlands',
               'the log has the text before and after');
select test.eq((select string_agg(coalesce(pg_temp.slide(jsonb_build_object('id', :'s_marca') || v) ->> 'error', 'ok'), ' ' order by o)
                  from (values (1, '{"starts_at": ""}'::jsonb), (2, '{"ends_at": null}'), (3, '{"title_es": ""}'), (4, '{"body_es": "Solo hoy: 20% menos"}'),
                               (5, jsonb_build_object('ends_at', now() + interval '400 days'))) x(o, v)),
               'dates_required dates_required invalid text_precio invalid', 'a change cannot blank a date or the title, add a price, or pass a year');
reset role;
select test.eq((select title_en || ' ' || ends_at::text from public.screen_slides where id = :'s_marca'),
               'Coffee from the Monteverde highlands ' || (now() + interval '30 days')::text, 'and none of those changed it');
set role authenticated;
-- pause, resume, retire
select test.eq(pg_temp.brief(pg_temp.st(:'s_marca', 'pausada')), 'true · 1 logged · pausar diapositiva by owner login · owner@test.local', 'paused');
select test.eq(pg_temp.brief(pg_temp.st(:'s_marca', 'pausada')), 'true · 0 logged', 'paused again: nothing changes, nothing logged');
select test.ok((pg_temp.st(:'s_marca', 'pausada') ->> 'unchanged')::boolean, 'and it says so');
select pg_temp.st(:'s_marca', 'activa') as r \gset
select test.eq(pg_temp.brief(:'r'), 'true · 1 logged · reanudar diapositiva by owner login · owner@test.local', 'resumed');
select test.ok((:'r'::jsonb) -> '_log' -> 'before' = '{"status": "pausada"}' and (:'r'::jsonb) -> '_log' -> 'after' = '{"status": "activa"}', 'the log: from paused to active');
select test.eq(pg_temp.brief(pg_temp.st(:'s_marca', 'borrada')), 'false invalid · 0 logged', 'an unknown state is refused');
select test.eq(pg_temp.brief(pg_temp.st('00000000-0000-4000-8000-000000000000', 'pausada')), 'false not_found · 0 logged', 'an unknown slide');
select pg_temp.slide(pg_temp.marca('{"title_es": "Cerramos temprano el viernes"}')) as r \gset
select (:'r'::jsonb) #>> '{slide,id}' as s_retirada \gset
select test.eq(pg_temp.brief(pg_temp.st(:'s_retirada', 'retirada')), 'true · 1 logged · retirar diapositiva by owner login · owner@test.local', 'retired');
select test.eq(pg_temp.brief(pg_temp.st(:'s_retirada', 'activa')), 'false retired · 0 logged', 'a retired slide is never reactivated');
select test.eq(pg_temp.brief(pg_temp.st(:'s_retirada', 'pausada')), 'false retired · 0 logged', 'nor paused');
select test.eq(pg_temp.brief(pg_temp.slide(jsonb_build_object('id', :'s_retirada', 'title_es', 'Abrimos el viernes'))), 'false retired · 0 logged', 'nor edited');
reset role;
select test.eq((select title_es || ' ' || status from public.screen_slides where id = :'s_retirada'), 'Cerramos temprano el viernes retirada', 'it stays as it was: never deleted');
set role authenticated;

-- 6) what the promotions TVs show (slides created by the owner, read as a visitor) ---------------------------------------
select pg_temp.slide(pg_temp.marca(jsonb_build_object('title_es', 'Solo en la terraza', 'screen_ids', jsonb_build_array('promos-2'), 'sort', 40))) ->> 'ok' as ok1,
       pg_temp.slide(pg_temp.marca(jsonb_build_object('title_es', 'En pausa', 'status', 'pausada', 'sort', 41))) ->> 'ok' as ok2,
       pg_temp.slide(jsonb_build_object('kind', 'marca', 'title_es', 'Ya terminó', 'starts_at', now() - interval '3 days', 'ends_at', now() - interval '1 minute', 'sort', 42)) ->> 'ok' as ok3,
       pg_temp.slide(jsonb_build_object('kind', 'marca', 'title_es', 'Empieza en 23 horas', 'starts_at', now() + interval '23 hours', 'ends_at', now() + interval '3 days', 'sort', 43)) ->> 'ok' as ok4,
       pg_temp.slide(jsonb_build_object('kind', 'marca', 'title_es', 'Empieza en 25 horas', 'starts_at', now() + interval '25 hours', 'ends_at', now() + interval '3 days', 'sort', 44)) ->> 'ok' as ok5,
       pg_temp.slide(pg_temp.producto(:'latte', 50)) ->> 'ok' as ok6,
       pg_temp.slide(pg_temp.producto(:'tea', 51)) ->> 'ok' as ok7,
       pg_temp.slide(pg_temp.producto(:'bread', 52)) ->> 'ok' as ok8,
       pg_temp.slide(pg_temp.producto('1b000000-0000-4000-8000-000000004401', 53)) ->> 'ok' as ok9 \gset
select test.eq(:'ok1' || :'ok2' || :'ok3' || :'ok4' || :'ok5' || :'ok6' || :'ok7' || :'ok8' || :'ok9', repeat('true', 9), 'nine more slides');
select test.eq(pg_temp.brief(pg_temp.tv('{"id": "menu-2", "active": false}')), 'true · 1 logged · cambiar tv by owner login · owner@test.local', 'the patio TV switched off');
reset role;
select test.eq((select count(*)::int from public.screen_changes), (select count(*)::int from public.screen_changes where by_name is not null and btrim(by_name) <> ''),
               'every line of the log names who did it');
-- 15 writes of TVs (2 created, 12 changes in section 4, the patio switched off) and 20 of slides (16 created, 1 text change, pause, resume,
-- retire); the refusals and the no-op logged nothing
select test.eq((select count(*)::int from public.screen_changes), 35, 'every successful write logged exactly one line: 35 writes, 35 lines');
select test.eq((select count(*) filter (where target_kind = 'tv') || ' tv · ' || count(*) filter (where target_kind = 'diapositiva') || ' diapositiva · '
                       || count(distinct action) || ' actions' from public.screen_changes), '15 tv · 20 diapositiva · 5 actions', 'by kind (crear, cambiar, pausar, reanudar, retirar)');
select test.eq((select count(*)::int from public.screen_slides), 16, 'and the 16 slides are there (none deleted)');
select test.ok(not exists (select 1 from public.screen_changes where coalesce(before::text, '') || coalesce(after::text, '') ~ '(Dueño|owner login|@test)'),
               'the log''s before/after hold the settings and the slides only, never who (that is by_name)');

select test.login('anon'); set role anon;
select test.eq(pg_temp.shown('promos-1'), 'Café de altura de Monteverde | Adventure Box · Ham & Cheese or Monteverde | ¿Le gustó? Déjenos una reseña | Empieza en 23 horas | '
               || 'Latte | Tea | Banana Bread | Café de prueba 440',
               'promos-1 shows the active slides in force or starting within a day, in order; not paused, retired, ended, far off or another TV''s');
select test.eq(pg_temp.shown('promos-2'), 'Café de altura de Monteverde | Adventure Box · Ham & Cheese or Monteverde | Solo en la terraza | Empieza en 23 horas | '
               || 'Latte | Tea | Banana Bread | Café de prueba 440', 'promos-2 gets its own slide, not promos-1''s invitation');
select test.eq(public.pantalla_datos('menu-1') -> 'slides', '[]'::jsonb, 'the menu TV gets no slides');
select test.eq(public.pantalla_datos('menu-2'), jsonb_build_object('ok', false, 'error', 'tv_apagada', 'now', now()),
               'a switched-off TV gets tv_apagada (the screen goes black), distinct from a wrong address');
select test.eq((select s -> 'item' from jsonb_array_elements(public.pantalla_datos('promos-1') -> 'slides') s where s ->> 'menu_item_id' = :'latte'),
               jsonb_build_object('name', 'Latte', 'name_es', null, 'price_crc', 2200, 'photo_url', (select photo_url from public.menu_items where id = :'latte'),
                                  'available', true, 'category', 'Coffee', 'sellable', true),
               'a product slide carries the menu''s name, price, photo and availability');
select test.ok(public.pantalla_datos('promos-1')::text !~ '(Dueño|owner login|created_by|updated_by|created_at)', 'nothing about who in what the TVs read');
-- a GET: PostgREST reads a STABLE function in a read-only transaction
savepoint ro;
set transaction read only;
select jsonb_array_length(public.pantalla_datos('promos-1') -> 'slides') as ro_slides, current_setting('transaction_read_only') as ro_on \gset
rollback to savepoint ro;
reset role;
select test.eq(:'ro_on' || ' ' || :'ro_slides', 'on 8', 'pantalla_datos answers inside a read-only transaction (GET /rest/v1/rpc/pantalla_datos)');

-- 7) nothing that existed was written: no row of any existing table, in all of the above ---------------------------------
select test.eq(pg_temp.writes()::text, :'writes_before', 'no existing table got a single write (inserts, updates or deletes counted per table)');
select test.eq(pg_temp.fp(), :'fp_before', 'the menu, its categories, the current TV''s settings and group slides, the app settings and the general log are byte for byte the same');

-- 8) the menu decides, live: a change in the Menu Manager shows on the next read ------------------------------------------
select test.login('owner', 'aal2'); set role authenticated;
update public.menu_items set price_crc = 2300, name_es = 'Café latte' where id = :'latte';
update public.menu_items set available = false where id = :'tea';
update public.menu_items set price_crc = 0 where id = :'bread';
delete from public.menu_items where id = '1b000000-0000-4000-8000-000000004401';
reset role;
select test.login('anon'); set role anon;
select test.eq(pg_temp.shown('promos-1'), 'Café de altura de Monteverde | Adventure Box · Ham & Cheese or Monteverde | ¿Le gustó? Déjenos una reseña | Empieza en 23 horas | Latte',
               'sold out, priced 0 or deleted: the product slide hides by itself');
select test.eq((select (s #>> '{item,price_crc}') || ' ' || (s #>> '{item,name_es}') from jsonb_array_elements(public.pantalla_datos('promos-1') -> 'slides') s where s ->> 'menu_item_id' = :'latte'),
               '2300 Café latte', 'and a new price or name shows on the next read');
reset role;
update public.menu_items set available = true where id = :'tea';
update public.menu_items set price_crc = -1 where id = :'bread';
update public.menu_items set name = '   ' where id = :'latte';
update public.menu_items set category_id = :'cat_extras' where id = :'box';
select test.login('anon'); set role anon;
select test.eq(pg_temp.shown('promos-1'), 'Café de altura de Monteverde | ¿Le gustó? Déjenos una reseña | Empieza en 23 horas | Tea',
               'back in stock it shows again; a negative price, a blank name or a move to «Extras & Combos» hides it');
reset role;
select test.eq((select count(*)::int from public.screen_changes), 35, 'the menu''s changes write nothing in the screens'' log');
select test.eq((select count(*)::int from public.screen_slides where status = 'activa'), 11, 'and change no slide (they only hide)');

-- 9) the change log: rows are only added, by nobody changed (not even the database owner) ---------------------------------
select test.throws($$update public.screen_changes set summary = 'otro'$$, 'screen_changes_immutable', 'a log line cannot be changed');
select test.throws($$delete from public.screen_changes$$, 'screen_changes_immutable', 'nor deleted');
select test.throws($$truncate public.screen_changes$$, 'screen_changes_immutable', 'nor truncated');
select test.login('owner', 'aal2'); set role authenticated;
select test.throws($$delete from public.screen_changes$$, 'permission denied', 'the owner''s login cannot touch it either');
select test.throws($$update public.screen_slides set status = 'activa'$$, 'permission denied', 'nor the slides, except through the functions');
select test.eq(jsonb_array_length(public.pantallas_estado() -> 'changes'), 35, 'the owner reads the log through pantallas_estado');
reset role;

-- 10) pantallas_estado: everything pantallas.html needs, nothing of the till's helpers ------------------------------------
select test.login('cafe', 'aal1', current_setting('test.h_dueno')::jsonb); set role authenticated;
select public.pantallas_estado() as e \gset
reset role;
select test.eq((select string_agg(k, ' ' order by k) from jsonb_object_keys(:'e'::jsonb) k), 'categories changes items now ok screens slides who', 'the answer''s parts');
select test.eq((:'e'::jsonb) ->> 'who', 'Dueño (owner)', 'who is managing');
select test.eq((select string_agg(s ->> 'id', ' ' order by o) from jsonb_array_elements((:'e'::jsonb) -> 'screens') with ordinality x(s, o)),
               'menu-1 menu-2 promos-1 promos-2', 'every TV, the switched-off one too');
select test.eq(jsonb_array_length((:'e'::jsonb) -> 'slides'), 16, 'every slide, the retired one too');
select test.eq((:'e'::jsonb) -> 'slides' -> -1 ->> 'status', 'retirada', 'the retired ones last');
select test.ok((select bool_and(s ? 'created_at' and s ? 'updated_at') from jsonb_array_elements((:'e'::jsonb) -> 'slides') s), 'with when each was created and changed');
select test.eq((select string_agg(k, ' ' order by k) from jsonb_object_keys((:'e'::jsonb) -> 'changes' -> 0) k), 'action after at before by summary target_id target_kind',
               'each change: when, who, what, before and after');
select test.ok(not exists (select 1 from jsonb_array_elements((:'e'::jsonb) -> 'categories') c where c ->> 'name' = 'Extras & Combos')
               and jsonb_array_length((:'e'::jsonb) -> 'categories') = 8, 'the categories to choose from, never «Extras & Combos»');
select test.ok(not exists (select 1 from jsonb_array_elements((:'e'::jsonb) -> 'items') i where i ->> 'category' = 'Extras & Combos' or (i ->> 'price_crc')::int <= 0)
               and exists (select 1 from jsonb_array_elements((:'e'::jsonb) -> 'items') i where i ->> 'name' = 'Tea'),
               'the products to choose from: none of the till''s helpers, none at 0 or less');
select test.done();
rollback;
