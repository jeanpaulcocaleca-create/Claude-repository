-- =====================================================================================================
-- Canopy OS · MENÚ PARA LAS PANTALLAS NUEVAS (SOLO LECTURA: no cambia nada) · fase 0 de docs/PANTALLAS.md
-- Supabase → SQL Editor → New query → pegar TODO → Run. Resultado: UNA celda ("menu_pantallas"). Copie la celda
-- completa y péguela en el chat para Claude.
--
-- Qué muestra, con el menú tal como está hoy (lo mismo que leería la Pantalla A, sin escribir nada):
--   * por categoría, en el orden del Gestor del menú: los productos que la pantalla mostraría (disponibles y con
--     precio mayor que cero), los agotados, y de cada producto: nombre, nombre en español si se escribió en el
--     Gestor del menú (name_es), precio final, si tiene foto, el largo del nombre y si su descripción trae un precio
--     escrito a mano;
--   * la categoría «Extras & Combos» aparte: la pantalla nunca la muestra (ayudas de la Caja y la línea de combo);
--   * un resumen: cuántos productos y categorías saldrían, cuántos no tienen name_es (el sitio tiene además un
--     diccionario propio que Claude revisa con este resultado), cuántas descripciones traen precios escritos a mano,
--     cuántos no tienen foto, y los nombres más largos.
-- No muestra nada de personas, ventas, ingresos ni claves: solo el menú que ya es público en el menú QR.
-- =====================================================================================================
set transaction read only;
with cats as (
  select c.id, c.name, c.sort, c.name = 'Extras & Combos' as helpers
    from public.menu_categories c
), items as (
  select i.category_id, i.name, nullif(btrim(coalesce(i.name_es, '')), '') as name_es, i.price_crc, coalesce(i.available, true) as available,
         i.photo_url is not null and btrim(i.photo_url) <> '' as has_photo, i.sort, i.description,
         coalesce(i.description, '') ~ '(₡|\+\s*₡?\s*[0-9]|[0-9]\s?[0-9]{3}\s*(colones|crc))' as typed_price
    from public.menu_items i
), shown as (
  select i.*, c.name as category, c.sort as cat_sort
    from items i join cats c on c.id = i.category_id
   where not c.helpers and i.available and i.price_crc > 0
)
select jsonb_pretty(jsonb_build_object(
  'revisado', to_char(now() at time zone 'America/Costa_Rica', 'YYYY-MM-DD HH24:MI') || ' (hora de Costa Rica)',
  'resumen', jsonb_build_object(
    'productos_en_pantalla', (select count(*) from shown),
    'categorias_en_pantalla', (select count(distinct category) from shown),
    'agotados_hoy', (select count(*) from items i join cats c on c.id = i.category_id where not c.helpers and not i.available),
    'sin_name_es', (select count(*) from shown where name_es is null),
    'descripciones_con_precio_a_mano', (select count(*) from items where typed_price),
    'sin_foto', (select count(*) from shown where not has_photo),
    'precio_cero_o_negativo_fuera_de_extras', (select count(*) from items i join cats c on c.id = i.category_id where not c.helpers and i.price_crc <= 0),
    'nombres_mas_largos', (select coalesce(jsonb_agg(name order by length(name) desc, name), '[]') from (select name from shown order by length(name) desc, name limit 5) l)),
  'categorias', (select coalesce(jsonb_agg(jsonb_build_object(
      'categoria', c.name,
      'en_pantalla', (select count(*) from shown s where s.category_id = c.id),
      'agotados', (select coalesce(jsonb_agg(i.name order by i.sort, i.name), '[]') from items i where i.category_id = c.id and not i.available),
      'productos', (select coalesce(jsonb_agg(jsonb_build_object(
          'nombre', s.name, 'name_es', s.name_es, 'precio_crc', s.price_crc, 'foto', s.has_photo, 'largo', length(s.name),
          'precio_en_descripcion', case when s.typed_price then s.description end) order by s.sort, s.name), '[]')
        from shown s where s.category_id = c.id)) order by c.sort, c.name), '[]')
    from cats c where not c.helpers),
  'extras_y_combos_no_se_muestran', (select coalesce(jsonb_agg(jsonb_build_object('nombre', i.name, 'precio_crc', i.price_crc, 'disponible', i.available)
                                       order by i.sort, i.name), '[]')
                                       from items i join cats c on c.id = i.category_id where c.helpers),
  'descripciones_con_precio_a_mano', (select coalesce(jsonb_agg(jsonb_build_object('nombre', i.name, 'descripcion', i.description) order by i.name), '[]')
                                        from items i where i.typed_price)
)) as menu_pantallas;
