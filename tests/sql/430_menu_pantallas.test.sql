-- The menu for the new customer screens (supabase/tools/menu-pantallas.sql, docs/PANTALLAS.md phase 0): the owner's
-- read-only look at what Screen A would show. The file runs as shipped: its first statement makes the paste a
-- read-only transaction; it reads only the menu (public in the QR menu); it never lists «Extras & Combos» among the
-- categories; it counts exactly what the screen shows (available, a price above 0, a name that is not blank): a sold-out
-- item, a zero or negative price or a blank name outside «Extras & Combos» is listed apart, to be fixed, never as shown.
begin;
-- a known state on top of the test menu (menu-2026.sql): one item sold out, one Spanish name, one typed price, and
-- outside «Extras & Combos» a price at 0, a negative price and a blank name (typed by mistake in the Menu Manager)
update public.menu_items set available = false where name = 'Tea';
update public.menu_items set name_es = 'Pan de banano casero' where name = 'Banana Bread';
update public.menu_items set price_crc = 0 where name = 'Tamal Asado';
update public.menu_items set price_crc = -100 where name = 'Carrot Cake';
update public.menu_items set name = E' \t ' where name = 'Mocha';
-- the screen's own rule (website/pantalla-menu.html: available === true, a trimmed name, a price above 0), counted independently
select count(*) as expected_shown from public.menu_items i join public.menu_categories c on c.id = i.category_id
 where c.name <> 'Extras & Combos' and i.available is true and btrim(i.name, E' \t\n') <> '' and i.price_crc > 0 \gset
select count(distinct c.id) as expected_cats from public.menu_items i join public.menu_categories c on c.id = i.category_id
 where c.name <> 'Extras & Combos' and i.available is true and btrim(i.name, E' \t\n') <> '' and i.price_crc > 0 \gset
select count(*) as all_outside from public.menu_items i join public.menu_categories c on c.id = i.category_id where c.name <> 'Extras & Combos' \gset

select coalesce(sum(n_tup_ins + n_tup_upd + n_tup_del), 0) as writes_before from pg_stat_xact_all_tables \gset
savepoint tool_run;
\set rc_file `mktemp`
\pset format unaligned
\pset tuples_only on
\o :rc_file
\ir ../../supabase/tools/menu-pantallas.sql
\o
\pset format aligned
\pset tuples_only off
select coalesce(sum(n_tup_ins + n_tup_upd + n_tup_del), 0) as writes_after from pg_stat_xact_all_tables \gset
select current_setting('transaction_read_only') as read_only_after \gset
\set ON_ERROR_STOP 0
\set ON_ERROR_ROLLBACK on
update public.menu_items set price_crc = price_crc where name = 'Latte';
\set ON_ERROR_ROLLBACK off
\set ON_ERROR_STOP 1
rollback to savepoint tool_run;
\set rc `cat :'rc_file'`

select test.eq(:'read_only_after'::text, 'on', 'after the report ran, the transaction is read only');
select test.ok(:'LAST_ERROR_SQLSTATE' = '25006', 'after the report ran, a write to the menu is refused by the database');
select test.eq(:'writes_after'::bigint, :'writes_before'::bigint, 'the report wrote no row');

select test.eq(((:'rc'::jsonb) -> 'resumen' ->> 'productos_en_pantalla')::int, :expected_shown::int, 'counts exactly what the screen would show');
select test.eq(((:'rc'::jsonb) -> 'resumen' ->> 'categorias_en_pantalla')::int, :expected_cats::int, 'and the categories with something to show');
select test.ok(not exists (select 1 from jsonb_array_elements((:'rc'::jsonb) -> 'categorias') c where c ->> 'categoria' = 'Extras & Combos'),
               '«Extras & Combos» is never among the categories of the screen');
select test.ok(exists (select 1 from jsonb_array_elements((:'rc'::jsonb) -> 'extras_y_combos_no_se_muestran') e
                        where e ->> 'nombre' ~ '^Combo discount' and (e ->> 'precio_crc')::numeric < 0),
               'the combo line is listed apart, as not shown');
select test.ok(exists (select 1 from jsonb_array_elements((:'rc'::jsonb) -> 'categorias') c, jsonb_array_elements_text(c -> 'agotados') a
                        where a = 'Tea')
               and not exists (select 1 from jsonb_array_elements((:'rc'::jsonb) -> 'categorias') c, jsonb_array_elements(c -> 'productos') p
                                where p ->> 'nombre' = 'Tea'),
               'a sold-out item is listed as sold out and not as shown');
select test.ok(exists (select 1 from jsonb_array_elements((:'rc'::jsonb) -> 'categorias') c, jsonb_array_elements(c -> 'productos') p
                        where p ->> 'nombre' = 'Banana Bread' and p ->> 'name_es' = 'Pan de banano casero'),
               'the Spanish name typed in the Menu Manager is shown');
select test.ok(exists (select 1 from jsonb_array_elements((:'rc'::jsonb) -> 'descripciones_con_precio_a_mano') d
                        where d ->> 'nombre' = 'Golden Passion Bloom' and d ->> 'descripcion' ~ '₡3 500'),
               'a price typed by hand in a description is found');
select test.eq(:expected_shown::int, :all_outside::int - 4, '(the four items above are the only ones outside «Extras & Combos» that the screen leaves out)');
select test.ok(not exists (select 1 from jsonb_array_elements((:'rc'::jsonb) -> 'categorias') c, jsonb_array_elements(c -> 'productos') p
                            where p ->> 'nombre' in ('Tamal Asado', 'Carrot Cake') or btrim(p ->> 'nombre', E' \t') = ''),
               'a price at 0, a negative price or a blank name is never counted as shown');
select test.eq((select string_agg((e ->> 'nombre') || ' ' || (e ->> 'precio_crc') || ' ' || (e ->> 'motivo'), ' | ' order by (e ->> 'precio_crc')::int)
                  from jsonb_array_elements((:'rc'::jsonb) -> 'no_se_muestran_por_precio_o_nombre') e),
               'Carrot Cake -100 precio cero o negativo | Tamal Asado 0 precio cero o negativo | ' || E' \t ' || ' 2400 sin nombre',
               'they are listed apart with the reason, to be fixed in the Menu Manager');
select test.eq(((:'rc'::jsonb) #>> '{resumen,precio_cero_o_negativo_fuera_de_extras}') || ' ' || ((:'rc'::jsonb) #>> '{resumen,sin_nombre_fuera_de_extras}'), '2 1',
               'and counted in the summary (the combo line''s negative price inside «Extras & Combos» is not)');
select test.ok(:'rc' !~* '\m(pin|pin_hash|email|password|staff|orders|total_crc)\M', 'nothing about people, sales or keys in the result');
select test.done();
rollback;
