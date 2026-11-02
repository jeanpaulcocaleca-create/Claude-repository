-- =====================================================================================================
-- Canopy OS · migración 0037 · Pantallas v2: el menú en una pantalla cuando cabe, promociones intercaladas en la
-- Pantalla A y composiciones de 1 a 4 fotos en la Pantalla B (plantillas, encuadre y franjas horarias)
-- Pegar TODO en Supabase → SQL Editor → New query → Run. Requiere: 0036. Una sola transacción.
--
-- Qué hace (rediseño pedido por el dueño el 2026-11-02, docs/PANTALLAS.md, D-064)
--   * screens: seis ajustes nuevos por TV, todos con valor por omisión (las dos TV siguen como están):
--       layout      auto | una-pantalla | paginas   cómo reparte el menú la Pantalla A (nunca bajo la letra mínima)
--       density     normal | compacta               separación entre líneas y bloques
--       english     debajo | en-linea | no          dónde va el inglés
--       promo_mode  no | intercalar                 la Pantalla A muestra de vez en cuando una diapositiva de esa TV
--       promo_every 30..900 s                       cada cuánto;  promo_seconds 6..30 s  cuánto dura
--   * screen_slides: una clase nueva, «composicion»: una plantilla (1, 2-lado, 3-grande-izq, 3-grande-der,
--     4-cuadricula, 4-centro) y una zona por lugar (zones, de 1 a 4). Cada zona es, a elección del dueño, una foto fija
--     o una presentación propia (su lista ordenada de productos o fotos, sus segundos, si muestra nombres y precios,
--     y una foto de respaldo cuando no le queda nada que mostrar). Cada entrada lleva un producto del menú (su nombre,
--     foto y precio se leen en vivo en cada lectura; nunca se guardan) o solo una foto subida, con su encuadre (punto de
--     enfoque y zoom). Igual que un producto solo: una entrada cuyo producto no se puede vender desaparece sola.
--     dwell_seconds: cuánto se queda la composición cuando comparte la TV con otras diapositivas (sola, se queda).
--   * pantalla_datos: una TV de menú con promo_mode = intercalar recibe también sus diapositivas; una composición solo
--     cuenta mientras alguna zona tenga algo que mostrar.
--   * pantalla_guardar y diapositiva_guardar validan lo nuevo; diapositiva_estado anota la plantilla como resumen al
--     pausar, reanudar o retirar una composición; el resto de las reglas de la 0036 no cambia (dueño solo, textos sin
--     precios ni combos, vigencia obligatoria, registro inmutable).
--   * _slide_json se vuelve a escribir sin caracteres invisibles literales (D-063): la regla de «nombre en blanco» usa
--     escapes \uXXXX, así el texto guardado coincide con este archivo pase por donde pase.
-- Qué NO cambia: ninguna tabla, función ni fila existente fuera de las tres de las pantallas; ni el menú, ni la TV
--   actual, ni la Caja, ni la Cocina, ni la Contabilidad, ni el menú QR. Las filas de screens y screen_slides quedan
--   iguales (las columnas nuevas nacen con su valor por omisión). Ningún derecho cambia.
-- Qué ve una página anterior: nada distinto (los campos nuevos sobran; una clase que no conoce la ignora).
-- Cuándo: cuando el dueño lo decida; no bloquea ventas.
-- Reversión: supabase/tools/reversion-0037.sql (vuelve las funciones a la 0036; las columnas y las filas quedan).
-- =====================================================================================================
select canopy.migration_begin(37, 'pantallas_v2');
set local lock_timeout = '8s';

-- 1) columnas nuevas, con valor por omisión --------------------------------------------------------------------------------
alter table public.screens
  add column if not exists layout        text not null default 'auto',
  add column if not exists density       text not null default 'normal',
  add column if not exists english       text not null default 'debajo',
  add column if not exists promo_mode    text not null default 'no',
  add column if not exists promo_every   int  not null default 180,
  add column if not exists promo_seconds int  not null default 10;
alter table public.screens drop constraint if exists screens_layout_check;
alter table public.screens add constraint screens_layout_check check (layout in ('auto', 'una-pantalla', 'paginas'));
alter table public.screens drop constraint if exists screens_density_check;
alter table public.screens add constraint screens_density_check check (density in ('normal', 'compacta'));
alter table public.screens drop constraint if exists screens_english_check;
alter table public.screens add constraint screens_english_check check (english in ('debajo', 'en-linea', 'no'));
alter table public.screens drop constraint if exists screens_promo_mode_check;
alter table public.screens add constraint screens_promo_mode_check check (promo_mode in ('no', 'intercalar'));
alter table public.screens drop constraint if exists screens_promo_every_check;
alter table public.screens add constraint screens_promo_every_check check (promo_every between 30 and 900);
alter table public.screens drop constraint if exists screens_promo_seconds_check;
alter table public.screens add constraint screens_promo_seconds_check check (promo_seconds between 6 and 30);

alter table public.screen_slides
  add column if not exists template      text,
  add column if not exists zones         jsonb not null default '[]'::jsonb,
  add column if not exists dwell_seconds int;
alter table public.screen_slides drop constraint if exists screen_slides_dwell_seconds_check;
alter table public.screen_slides add constraint screen_slides_dwell_seconds_check check (dwell_seconds is null or dwell_seconds between 10 and 600);
-- the kind gains «composicion»; the per-kind rule gains its shape (a template and as many zones as it has places)
alter table public.screen_slides drop constraint if exists screen_slides_kind_check;
alter table public.screen_slides add constraint screen_slides_kind_check check (kind in ('producto', 'marca', 'invitacion', 'composicion'));
alter table public.screen_slides drop constraint if exists screen_slides_template_check;
alter table public.screen_slides add constraint screen_slides_template_check
  check (template is null or template in ('1', '2-lado', '3-grande-izq', '3-grande-der', '4-cuadricula', '4-centro'));
-- 2) ayudas ---------------------------------------------------------------------------------------------------------------
-- how many places a template has (the constraint above and the validation use it)
create or replace function public._screen_template_places(p text)
returns int language sql immutable set search_path = public as $$
  select case p when '1' then 1 when '2-lado' then 2 when '3-grande-izq' then 3 when '3-grande-der' then 3
                when '4-cuadricula' then 4 when '4-centro' then 4 end;
$$;
revoke all on function public._screen_template_places(text) from public, anon, authenticated;

-- the per-kind rule, now that the helper exists (a composition has as many zones as its template has places)
alter table public.screen_slides drop constraint if exists screen_slides_kind;
alter table public.screen_slides add constraint screen_slides_kind check (
     (kind = 'producto'    and menu_item_id is not null)
  or (kind = 'marca'       and menu_item_id is null and nullif(btrim(title_es), '') is not null)
  or (kind = 'invitacion'  and menu_item_id is null and link is not null and nullif(btrim(title_es), '') is not null)
  or (kind = 'composicion' and menu_item_id is null and template is not null and jsonb_typeof(zones) = 'array'
      and jsonb_array_length(zones) = public._screen_template_places(template)));


-- a menu item as the screens see it: name, Spanish name, live price, photo, availability, category and whether the
-- till sells it as shown (available, a price above 0, a name that is not blank as JavaScript's trim() sees it, never a
-- till helper). The blank test lists every Unicode space the pages' trim() drops, written as escapes (D-063).
create or replace function public._screen_item_json(p_item uuid)
returns jsonb language sql stable set search_path = public as $$
  select jsonb_build_object('id', i.id, 'name', i.name, 'name_es', nullif(btrim(coalesce(to_jsonb(i) ->> 'name_es', '')), ''),
                            'price_crc', i.price_crc, 'photo_url', i.photo_url, 'available', i.available, 'category', c.name,
                            'sellable', (i.available and i.price_crc > 0
                                         and coalesce(i.name, '') ~ '[^[:space:]\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]'
                                         and c.name is distinct from 'Extras & Combos'))
    from public.menu_items i left join public.menu_categories c on c.id = i.category_id
   where i.id = p_item;
$$;
revoke all on function public._screen_item_json(uuid) from public, anon, authenticated;

-- 3) lo que leen las TV ---------------------------------------------------------------------------------------------------
create or replace function public._screen_json(s public.screens)
returns jsonb language sql stable set search_path = public as $$
  select jsonb_build_object('id', s.id, 'kind', s.kind, 'name', s.name, 'inches', s.inches, 'distance_m', s.distance_m,
    'turn', s.turn, 'scale_pct', s.scale_pct, 'look', s.look, 'page_seconds', s.page_seconds, 'slide_seconds', s.slide_seconds,
    'category_ids', to_jsonb(s.category_ids), 'sold_out', s.sold_out,
    'on_from', to_char(s.on_from, 'HH24:MI'), 'on_to', to_char(s.on_to, 'HH24:MI'), 'active', s.active, 'updated_at', s.updated_at,
    'layout', s.layout, 'density', s.density, 'english', s.english,
    'promo_mode', s.promo_mode, 'promo_every', s.promo_every, 'promo_seconds', s.promo_seconds);
$$;
revoke all on function public._screen_json(public.screens) from public, anon, authenticated;

-- a slide as the screens see it. A product slide carries its item live; a composition carries every zone with its
-- entries' items live (the menu's name, photo, price and availability at this very read), each zone's «showable»
-- (something to show now) and the slide's «usable» (at least one zone showable)
create or replace function public._slide_json(d public.screen_slides)
returns jsonb language sql stable set search_path = public as $$
  with z as (
    select zo, zx from jsonb_array_elements(case when jsonb_typeof(d.zones) = 'array' then d.zones else '[]'::jsonb end) with ordinality u(zx, zo)),
  e as (
    select z.zo, eo, ex,
           case when ex ->> 'item' ~ '^[0-9a-fA-F-]{36}$' then public._screen_item_json((ex ->> 'item')::uuid) end as item
      from z, jsonb_array_elements(case when jsonb_typeof(z.zx -> 'entries') = 'array' then z.zx -> 'entries' else '[]'::jsonb end) with ordinality v(ex, eo)),
  zr as (
    select z.zo,
           jsonb_build_object('mode', coalesce(z.zx ->> 'mode', 'fija'), 'seconds', coalesce(z.zx -> 'seconds', '8'::jsonb),
                              'labels', coalesce(z.zx -> 'labels', 'true'::jsonb), 'fallback', nullif(z.zx ->> 'fallback', ''),
                              'entries', (select coalesce(jsonb_agg(jsonb_build_object('item', e.item, 'photo', nullif(e.ex ->> 'photo', ''),
                                                                                      'focus', coalesce(e.ex -> 'focus', '[50, 50]'::jsonb),
                                                                                      'zoom', coalesce(e.ex -> 'zoom', '100'::jsonb)) order by e.eo), '[]'::jsonb)
                                            from e where e.zo = z.zo),
                              'showable', exists (select 1 from e where e.zo = z.zo
                                                    and (coalesce((e.item ->> 'sellable')::boolean, false)
                                                         or (e.item is null and nullif(e.ex ->> 'photo', '') is not null)))) as j
      from z)
  select jsonb_build_object('id', d.id, 'kind', d.kind, 'menu_item_id', d.menu_item_id,
    'kicker_es', d.kicker_es, 'kicker_en', d.kicker_en, 'title_es', d.title_es, 'title_en', d.title_en,
    'body_es', d.body_es, 'body_en', d.body_en, 'photo_url', d.photo_url, 'link', d.link, 'screen_ids', to_jsonb(d.screen_ids),
    'starts_at', d.starts_at, 'ends_at', d.ends_at, 'days', to_jsonb(d.days),
    'from_time', to_char(d.from_time, 'HH24:MI'), 'to_time', to_char(d.to_time, 'HH24:MI'), 'sort', d.sort, 'status', d.status,
    'template', d.template, 'dwell_seconds', d.dwell_seconds,
    'zones', (select coalesce(jsonb_agg(zr.j order by zr.zo), '[]'::jsonb) from zr),
    'usable', case when d.kind = 'composicion' then exists (select 1 from zr where (zr.j ->> 'showable')::boolean) else null end,
    'item', case when d.menu_item_id is not null then public._screen_item_json(d.menu_item_id) - 'id' end);
$$;
revoke all on function public._slide_json(public.screen_slides) from public, anon, authenticated;

create or replace function public.pantalla_datos(p_tv text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare s public.screens; sl jsonb := '[]'::jsonb;
begin
  select * into s from public.screens where id = p_tv;
  if s.id is null then return jsonb_build_object('ok', false, 'error', 'unknown_tv', 'now', now()); end if;
  -- switched off by the owner in pantallas.html: the screen goes black (distinct from a wrong address)
  if not s.active then return jsonb_build_object('ok', false, 'error', 'tv_apagada', 'now', now()); end if;
  -- the promotions TV, and the menu TV when the owner intercalates promotions in it
  if s.kind = 'promos' or (s.kind = 'menu' and s.promo_mode = 'intercalar') then
    -- in force or starting within a day (the TV switches on time even if a read is late, and hides an ended slide by
    -- itself without internet); a product only while the item can be sold; a composition while a tile can show
    -- (those checks come before the cap of 60, so sold-out products never push a sellable slide out)
    select coalesce(jsonb_agg(x.j order by x.sort, x.starts_at, x.id), '[]'::jsonb) into sl
      from (select y.j, y.sort, y.starts_at, y.id
              from (select public._slide_json(d) as j, d.sort, d.starts_at, d.id
                      from public.screen_slides d
                     where d.status = 'activa' and (d.screen_ids is null or s.id = any (d.screen_ids))
                       and d.ends_at > now() and d.starts_at < now() + interval '1 day') y
             where case y.j ->> 'kind'
                     when 'producto'    then coalesce((y.j -> 'item' ->> 'sellable')::boolean, false)
                     when 'composicion' then coalesce((y.j ->> 'usable')::boolean, false)
                     else true end
             order by (y.starts_at > now()), y.sort, y.starts_at, y.id   -- in force first: an upcoming one never pushes one out
             limit 60) x;
  end if;
  return jsonb_build_object('ok', true, 'now', now(), 'tv', public._screen_json(s), 'slides', sl);
end $$;
revoke all on function public.pantalla_datos(text) from public;
grant execute on function public.pantalla_datos(text) to anon, authenticated;

-- 4) la gestión: solo el dueño --------------------------------------------------------------------------------------------
create or replace function public.pantalla_guardar(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare old public.screens; new_row public.screens; v_id text; v_kind text; cats uuid[]; bad text; f text;
begin
  if not public.is_true_owner() then return jsonb_build_object('ok', false, 'error', 'owner_only'); end if;
  if p is null or jsonb_typeof(p) <> 'object' then return jsonb_build_object('ok', false, 'error', 'invalid'); end if;
  v_id := lower(btrim(coalesce(p ->> 'id', '')));
  if v_id !~ '^[a-z0-9][a-z0-9-]{1,29}$' then return jsonb_build_object('ok', false, 'error', 'invalid', 'field', 'id'); end if;
  select * into old from public.screens where id = v_id for update;
  v_kind := coalesce(old.kind, p ->> 'kind');
  if v_kind is null or v_kind not in ('menu', 'promos') then return jsonb_build_object('ok', false, 'error', 'invalid', 'field', 'kind'); end if;
  if old.id is not null and p ? 'kind' and p ->> 'kind' <> old.kind then
    return jsonb_build_object('ok', false, 'error', 'invalid', 'field', 'kind');
  end if;
  bad := public._screen_text_problem(p ->> 'name');
  if bad is not null then return jsonb_build_object('ok', false, 'error', 'text_' || bad, 'field', 'name'); end if;
  if p ? 'on_from' and not (public._screen_hhmm(p ->> 'on_from')).ok then return jsonb_build_object('ok', false, 'error', 'invalid', 'field', 'on_from'); end if;
  if p ? 'on_to' and not (public._screen_hhmm(p ->> 'on_to')).ok then return jsonb_build_object('ok', false, 'error', 'invalid', 'field', 'on_to'); end if;
  -- the v2 choices, each named when refused
  if p ? 'layout' and coalesce(p ->> 'layout', '') not in ('auto', 'una-pantalla', 'paginas') then return jsonb_build_object('ok', false, 'error', 'invalid', 'field', 'layout'); end if;
  if p ? 'density' and coalesce(p ->> 'density', '') not in ('normal', 'compacta') then return jsonb_build_object('ok', false, 'error', 'invalid', 'field', 'density'); end if;
  if p ? 'english' and coalesce(p ->> 'english', '') not in ('debajo', 'en-linea', 'no') then return jsonb_build_object('ok', false, 'error', 'invalid', 'field', 'english'); end if;
  if p ? 'promo_mode' and coalesce(p ->> 'promo_mode', '') not in ('no', 'intercalar') then return jsonb_build_object('ok', false, 'error', 'invalid', 'field', 'promo_mode'); end if;
  foreach f in array array['promo_every', 'promo_seconds'] loop
    if p ? f and (p ->> f) !~ '^\d{1,4}$' then return jsonb_build_object('ok', false, 'error', 'invalid', 'field', f); end if;
  end loop;
  if p ? 'promo_every' and (p ->> 'promo_every')::int not between 30 and 900 then return jsonb_build_object('ok', false, 'error', 'invalid', 'field', 'promo_every'); end if;
  if p ? 'promo_seconds' and (p ->> 'promo_seconds')::int not between 6 and 30 then return jsonb_build_object('ok', false, 'error', 'invalid', 'field', 'promo_seconds'); end if;
  -- the categories Screen A shows: null (or an empty list) = all; otherwise categories of the menu, never the till's helpers
  if p ? 'category_ids' and jsonb_typeof(p -> 'category_ids') not in ('array', 'null') then
    return jsonb_build_object('ok', false, 'error', 'invalid', 'field', 'category_ids');
  end if;
  if jsonb_typeof(p -> 'category_ids') = 'array' then
    if jsonb_array_length(p -> 'category_ids') > 50 then return jsonb_build_object('ok', false, 'error', 'too_many', 'field', 'category_ids'); end if;
    begin
      -- in the order given, each category once
      select array_agg(x::uuid order by o) into cats
        from (select x, min(o) as o from jsonb_array_elements_text(p -> 'category_ids') with ordinality t(x, o) group by x) u;
    exception when invalid_text_representation then
      return jsonb_build_object('ok', false, 'error', 'invalid', 'field', 'category_ids');
    end;
    if exists (select 1 from unnest(cats) c
                where not exists (select 1 from public.menu_categories m where m.id = c and m.name <> 'Extras & Combos')) then
      return jsonb_build_object('ok', false, 'error', 'invalid', 'field', 'category_ids');
    end if;
  end if;
  begin
    insert into public.screens as s (id, kind, name, inches, distance_m, turn, scale_pct, look, page_seconds, slide_seconds,
                                     category_ids, sold_out, on_from, on_to, active, updated_at, updated_by,
                                     layout, density, english, promo_mode, promo_every, promo_seconds)
    values (v_id, v_kind,
            coalesce(nullif(btrim(p ->> 'name'), ''), old.name, v_id),
            coalesce((p ->> 'inches')::numeric, old.inches, 55),
            coalesce((p ->> 'distance_m')::numeric, old.distance_m, 3),
            coalesce(p ->> 'turn', old.turn, 'no'),
            coalesce((p ->> 'scale_pct')::int, old.scale_pct, 100),
            coalesce(p ->> 'look', old.look, 'auto'),
            coalesce((p ->> 'page_seconds')::int, old.page_seconds, 28),
            coalesce((p ->> 'slide_seconds')::int, old.slide_seconds, 10),
            case when p ? 'category_ids' then case when cardinality(cats) > 0 then cats end else old.category_ids end,
            coalesce(p ->> 'sold_out', old.sold_out, 'ocultar'),
            case when p ? 'on_from' then (public._screen_hhmm(p ->> 'on_from')).t else old.on_from end,
            case when p ? 'on_to' then (public._screen_hhmm(p ->> 'on_to')).t else old.on_to end,
            coalesce((p ->> 'active')::boolean, old.active, true),
            now(), public._screen_actor(),
            coalesce(p ->> 'layout', old.layout, 'auto'),
            coalesce(p ->> 'density', old.density, 'normal'),
            coalesce(p ->> 'english', old.english, 'debajo'),
            coalesce(p ->> 'promo_mode', old.promo_mode, 'no'),
            coalesce((p ->> 'promo_every')::int, old.promo_every, 180),
            coalesce((p ->> 'promo_seconds')::int, old.promo_seconds, 10))
    on conflict (id) do update set
      name = excluded.name, inches = excluded.inches, distance_m = excluded.distance_m, turn = excluded.turn,
      scale_pct = excluded.scale_pct, look = excluded.look, page_seconds = excluded.page_seconds,
      slide_seconds = excluded.slide_seconds, category_ids = excluded.category_ids, sold_out = excluded.sold_out,
      on_from = excluded.on_from, on_to = excluded.on_to, active = excluded.active,
      updated_at = excluded.updated_at, updated_by = excluded.updated_by,
      layout = excluded.layout, density = excluded.density, english = excluded.english,
      promo_mode = excluded.promo_mode, promo_every = excluded.promo_every, promo_seconds = excluded.promo_seconds
    returning * into new_row;
  exception when check_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow
                 or numeric_value_out_of_range or invalid_parameter_value then
    return jsonb_build_object('ok', false, 'error', 'invalid', 'detail', sqlerrm);
  end;
  perform public._screen_log('tv', v_id, case when old.id is null then 'crear' else 'cambiar' end,
                             new_row.name, case when old.id is null then null else public._screen_json(old) end,
                             public._screen_json(new_row));
  return jsonb_build_object('ok', true, 'tv', public._screen_json(new_row));
end $$;
revoke all on function public.pantalla_guardar(jsonb) from public, anon;
grant execute on function public.pantalla_guardar(jsonb) to authenticated;

-- a slide: created without an id, changed with its id; its kind never changes; a retired slide is not edited.
-- A composition: a template and one zone per place (a fixed photo, or a presentation of its own); each entry a product
-- of the menu (never a till helper), or only a photo; its framing (focus 0..100 x 0..100, zoom 100..200 %) is kept as
-- given. Nothing of the menu is stored.
create or replace function public.diapositiva_guardar(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare old public.screen_slides; new_row public.screen_slides; v_id uuid; v_kind text; f text; bad text; v_item uuid; v_cat text;
        scr text[]; dys smallint[]; v_link text; v_photo text; v_template text; v_zones jsonb; zl jsonb; zn int; zx jsonb; zm text;
        zs numeric; zf text; v_entries jsonb; el jsonb; n int; t_item uuid; t_photo text; t_focus jsonb; t_zoom numeric; fx numeric;
        fy numeric; v_summary text; v_dwell int; zpath text; epath text;
begin
  if not public.is_true_owner() then return jsonb_build_object('ok', false, 'error', 'owner_only'); end if;
  if p is null or jsonb_typeof(p) <> 'object' then return jsonb_build_object('ok', false, 'error', 'invalid'); end if;
  if nullif(p ->> 'id', '') is not null then
    begin v_id := (p ->> 'id')::uuid; exception when others then return jsonb_build_object('ok', false, 'error', 'invalid', 'field', 'id'); end;
    select * into old from public.screen_slides where id = v_id for update;
    if old.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
    if old.status = 'retirada' then return jsonb_build_object('ok', false, 'error', 'retired'); end if;
  end if;
  v_kind := coalesce(old.kind, p ->> 'kind');
  if v_kind is null or v_kind not in ('producto', 'marca', 'invitacion', 'composicion') then
    return jsonb_build_object('ok', false, 'error', 'invalid', 'field', 'kind');
  end if;
  if old.id is not null and p ? 'kind' and p ->> 'kind' <> old.kind then
    return jsonb_build_object('ok', false, 'error', 'invalid', 'field', 'kind');
  end if;
  -- every text: no prices, no combos or discounts, at most 140 characters
  foreach f in array array['kicker_es', 'kicker_en', 'title_es', 'title_en', 'body_es', 'body_en'] loop
    bad := public._screen_text_problem(p ->> f);
    if bad is not null then return jsonb_build_object('ok', false, 'error', 'text_' || bad, 'field', f); end if;
  end loop;
  -- a product: an item of the menu that is not a till helper (Extras & Combos)
  if v_kind = 'producto' then
    begin
      select i.id, c.name into v_item, v_cat from public.menu_items i left join public.menu_categories c on c.id = i.category_id
       where i.id = coalesce(nullif(p ->> 'menu_item_id', '')::uuid, old.menu_item_id);
    exception when invalid_text_representation then return jsonb_build_object('ok', false, 'error', 'invalid', 'field', 'menu_item_id');
    end;
    if v_item is null then return jsonb_build_object('ok', false, 'error', 'invalid', 'field', 'menu_item_id'); end if;
    if v_cat = 'Extras & Combos' then return jsonb_build_object('ok', false, 'error', 'text_combo_descuento', 'field', 'menu_item_id'); end if;
  end if;
  -- a composition: its template, how long it stays when it shares the TV, and its zones checked one by one. A zone is a
  -- fixed photo (one entry) or its own presentation (1 to 12 entries, its seconds, names and prices or not, a fallback
  -- photo for when nothing of it can show); every entry a product of the menu (never a till helper) or only a photo
  if v_kind = 'composicion' then
    v_template := coalesce(nullif(btrim(p ->> 'template'), ''), old.template);
    if v_template is null or public._screen_template_places(v_template) is null then
      return jsonb_build_object('ok', false, 'error', 'invalid', 'field', 'template');
    end if;
    if p ? 'dwell_seconds' then
      if nullif(p ->> 'dwell_seconds', '') is null then v_dwell := null;
      elsif (p ->> 'dwell_seconds') !~ '^\d{1,4}$' or (p ->> 'dwell_seconds')::int not between 10 and 600 then
        return jsonb_build_object('ok', false, 'error', 'invalid', 'field', 'dwell_seconds');
      else v_dwell := (p ->> 'dwell_seconds')::int; end if;
    else v_dwell := old.dwell_seconds; end if;
    if p ? 'zones' then zl := p -> 'zones'; else zl := old.zones; end if;
    if zl is null or jsonb_typeof(zl) <> 'array' then return jsonb_build_object('ok', false, 'error', 'invalid', 'field', 'zones'); end if;
    if jsonb_array_length(zl) > 4 then return jsonb_build_object('ok', false, 'error', 'too_many', 'field', 'zones'); end if;
    if jsonb_array_length(zl) <> public._screen_template_places(v_template) then
      return jsonb_build_object('ok', false, 'error', 'invalid', 'field', 'zones');
    end if;
    v_zones := '[]'::jsonb;
    for zn in 0 .. jsonb_array_length(zl) - 1 loop
      zpath := 'zones.' || zn; zx := zl -> zn;
      if jsonb_typeof(zx) <> 'object' then return jsonb_build_object('ok', false, 'error', 'invalid', 'field', zpath); end if;
      zm := coalesce(nullif(zx ->> 'mode', ''), 'fija');
      if zm not in ('fija', 'auto') then return jsonb_build_object('ok', false, 'error', 'invalid', 'field', zpath || '.mode'); end if;
      if zx ? 'seconds' and jsonb_typeof(zx -> 'seconds') <> 'number' then return jsonb_build_object('ok', false, 'error', 'invalid', 'field', zpath || '.seconds'); end if;
      zs := coalesce((zx ->> 'seconds')::numeric, 8);
      if zs < 4 or zs > 60 then return jsonb_build_object('ok', false, 'error', 'invalid', 'field', zpath || '.seconds'); end if;
      if zx ? 'labels' and jsonb_typeof(zx -> 'labels') <> 'boolean' then return jsonb_build_object('ok', false, 'error', 'invalid', 'field', zpath || '.labels'); end if;
      zf := nullif(btrim(coalesce(zx ->> 'fallback', '')), '');
      if zf is not null and (length(zf) > 500 or zf !~ '^https?://[^\s"''<>()\\]+$') then
        return jsonb_build_object('ok', false, 'error', 'invalid', 'field', zpath || '.fallback');
      end if;
      el := zx -> 'entries';
      if el is null or jsonb_typeof(el) <> 'array' or jsonb_array_length(el) = 0 then return jsonb_build_object('ok', false, 'error', 'invalid', 'field', zpath || '.entries'); end if;
      if jsonb_array_length(el) > 12 then return jsonb_build_object('ok', false, 'error', 'too_many', 'field', zpath || '.entries'); end if;
      if zm = 'fija' and jsonb_array_length(el) <> 1 then return jsonb_build_object('ok', false, 'error', 'invalid', 'field', zpath || '.entries'); end if;
      v_entries := '[]'::jsonb;
      for n in 0 .. jsonb_array_length(el) - 1 loop
        epath := zpath || '.entries.' || n;
        if jsonb_typeof(el -> n) <> 'object' then return jsonb_build_object('ok', false, 'error', 'invalid', 'field', epath); end if;
        t_item := null; t_photo := nullif(btrim(coalesce(el -> n ->> 'photo', '')), '');
        if nullif(el -> n ->> 'item', '') is not null then
          if (el -> n ->> 'item') !~ '^[0-9a-fA-F-]{36}$' then return jsonb_build_object('ok', false, 'error', 'invalid', 'field', epath || '.item'); end if;
          select i.id, c.name into t_item, v_cat from public.menu_items i left join public.menu_categories c on c.id = i.category_id
           where i.id = (el -> n ->> 'item')::uuid;
          if t_item is null then return jsonb_build_object('ok', false, 'error', 'invalid', 'field', epath || '.item'); end if;
          if v_cat = 'Extras & Combos' then return jsonb_build_object('ok', false, 'error', 'text_combo_descuento', 'field', epath || '.item'); end if;
        end if;
        if t_photo is not null and (length(t_photo) > 500 or t_photo !~ '^https?://[^\s"''<>()\\]+$') then
          return jsonb_build_object('ok', false, 'error', 'invalid', 'field', epath || '.photo');
        end if;
        if t_item is null and t_photo is null then return jsonb_build_object('ok', false, 'error', 'invalid', 'field', epath); end if;
        t_focus := coalesce(el -> n -> 'focus', '[50, 50]'::jsonb);
        if jsonb_typeof(t_focus) <> 'array' or jsonb_array_length(t_focus) <> 2
           or jsonb_typeof(t_focus -> 0) <> 'number' or jsonb_typeof(t_focus -> 1) <> 'number' then
          return jsonb_build_object('ok', false, 'error', 'invalid', 'field', epath || '.focus');
        end if;
        fx := (t_focus ->> 0)::numeric; fy := (t_focus ->> 1)::numeric;
        if fx < 0 or fx > 100 or fy < 0 or fy > 100 then return jsonb_build_object('ok', false, 'error', 'invalid', 'field', epath || '.focus'); end if;
        if el -> n ? 'zoom' and jsonb_typeof(el -> n -> 'zoom') <> 'number' then return jsonb_build_object('ok', false, 'error', 'invalid', 'field', epath || '.zoom'); end if;
        t_zoom := coalesce((el -> n ->> 'zoom')::numeric, 100);
        if t_zoom < 100 or t_zoom > 200 then return jsonb_build_object('ok', false, 'error', 'invalid', 'field', epath || '.zoom'); end if;
        v_entries := v_entries || jsonb_build_array(jsonb_build_object('item', t_item, 'photo', t_photo,
                                                                       'focus', jsonb_build_array(round(fx), round(fy)), 'zoom', round(t_zoom)));
      end loop;
      v_zones := v_zones || jsonb_build_array(jsonb_build_object('mode', zm, 'seconds', round(zs), 'labels', coalesce((zx ->> 'labels')::boolean, true),
                                                                 'fallback', zf, 'entries', v_entries));
    end loop;
  end if;
  if p ? 'from_time' and not (public._screen_hhmm(p ->> 'from_time')).ok then return jsonb_build_object('ok', false, 'error', 'invalid', 'field', 'from_time'); end if;
  if p ? 'to_time' and not (public._screen_hhmm(p ->> 'to_time')).ok then return jsonb_build_object('ok', false, 'error', 'invalid', 'field', 'to_time'); end if;
  v_link := case when p ? 'link' then nullif(p ->> 'link', '') else old.link end;
  v_photo := case when p ? 'photo_url' then nullif(btrim(p ->> 'photo_url'), '') else old.photo_url end;
  if v_photo is not null and (length(v_photo) > 500 or v_photo !~ '^https?://[^\s"''<>()\\]+$') then
    return jsonb_build_object('ok', false, 'error', 'invalid', 'field', 'photo_url');
  end if;
  -- which TVs and which days: null (or an empty list) = every one; anything but a list is refused, never read as "all"
  foreach f in array array['screen_ids', 'days'] loop
    if p ? f and jsonb_typeof(p -> f) not in ('array', 'null') then
      return jsonb_build_object('ok', false, 'error', 'invalid', 'field', f);
    end if;
  end loop;
  if jsonb_typeof(p -> 'days') = 'array' then
    begin
      if jsonb_array_length(p -> 'days') > 50 then return jsonb_build_object('ok', false, 'error', 'too_many', 'field', 'days'); end if;
      select array_agg(distinct x::smallint order by x::smallint) into dys from jsonb_array_elements_text(p -> 'days') x;
    exception when invalid_text_representation or numeric_value_out_of_range then
      return jsonb_build_object('ok', false, 'error', 'invalid', 'field', 'days');
    end;
    if exists (select 1 from unnest(dys) x where x is null or x not between 1 and 7) then
      return jsonb_build_object('ok', false, 'error', 'invalid', 'field', 'days');
    end if;
  end if;
  begin
    if jsonb_typeof(p -> 'screen_ids') = 'array' then
      if jsonb_array_length(p -> 'screen_ids') > 50 then return jsonb_build_object('ok', false, 'error', 'too_many', 'field', 'screen_ids'); end if;
      select array_agg(distinct x) into scr from jsonb_array_elements_text(p -> 'screen_ids') x;
      -- a promotions TV, or a menu TV (it shows them only when its owner intercalates promotions)
      if exists (select 1 from unnest(scr) x where not exists (select 1 from public.screens s where s.id = x)) then
        return jsonb_build_object('ok', false, 'error', 'invalid', 'field', 'screen_ids');
      end if;
    end if;
    if (p ? 'starts_at' and nullif(p ->> 'starts_at', '') is null) or (p ? 'ends_at' and nullif(p ->> 'ends_at', '') is null)
       or (old.id is null and (nullif(p ->> 'starts_at', '') is null or nullif(p ->> 'ends_at', '') is null)) then
      return jsonb_build_object('ok', false, 'error', 'dates_required');
    end if;
    if old.id is null then
      insert into public.screen_slides (kind, menu_item_id, kicker_es, kicker_en, title_es, title_en, body_es, body_en, photo_url,
                                        link, screen_ids, starts_at, ends_at, days, from_time, to_time, sort, status,
                                        created_by, updated_by, template, zones, dwell_seconds)
      values (v_kind, case when v_kind = 'producto' then v_item end,
              nullif(btrim(p ->> 'kicker_es'), ''), nullif(btrim(p ->> 'kicker_en'), ''),
              case when v_kind = 'composicion' then null else nullif(btrim(p ->> 'title_es'), '') end,
              case when v_kind = 'composicion' then null else nullif(btrim(p ->> 'title_en'), '') end,
              case when v_kind = 'composicion' then null else nullif(btrim(p ->> 'body_es'), '') end,
              case when v_kind = 'composicion' then null else nullif(btrim(p ->> 'body_en'), '') end,
              v_photo, v_link, case when cardinality(scr) > 0 then scr end,
              (p ->> 'starts_at')::timestamptz, (p ->> 'ends_at')::timestamptz,
              case when cardinality(dys) between 1 and 6 then dys end,
              (public._screen_hhmm(p ->> 'from_time')).t, (public._screen_hhmm(p ->> 'to_time')).t,
              coalesce((p ->> 'sort')::int, 100),
              case when p ->> 'status' = 'pausada' then 'pausada' else 'activa' end,
              public._screen_actor(), public._screen_actor(),
              case when v_kind = 'composicion' then v_template end,
              case when v_kind = 'composicion' then v_zones else '[]'::jsonb end,
              case when v_kind = 'composicion' then v_dwell end)
      returning * into new_row;
    else
      update public.screen_slides d set
        menu_item_id = case when v_kind = 'producto' then v_item end,
        kicker_es = case when p ? 'kicker_es' then nullif(btrim(p ->> 'kicker_es'), '') else d.kicker_es end,
        kicker_en = case when p ? 'kicker_en' then nullif(btrim(p ->> 'kicker_en'), '') else d.kicker_en end,
        title_es  = case when v_kind = 'composicion' then null when p ? 'title_es' then nullif(btrim(p ->> 'title_es'), '') else d.title_es end,
        title_en  = case when v_kind = 'composicion' then null when p ? 'title_en' then nullif(btrim(p ->> 'title_en'), '') else d.title_en end,
        body_es   = case when v_kind = 'composicion' then null when p ? 'body_es'  then nullif(btrim(p ->> 'body_es'), '')  else d.body_es end,
        body_en   = case when v_kind = 'composicion' then null when p ? 'body_en'  then nullif(btrim(p ->> 'body_en'), '')  else d.body_en end,
        photo_url = v_photo, link = v_link,
        screen_ids = case when p ? 'screen_ids' then case when cardinality(scr) > 0 then scr end else d.screen_ids end,
        starts_at = coalesce((nullif(p ->> 'starts_at', ''))::timestamptz, d.starts_at),
        ends_at   = coalesce((nullif(p ->> 'ends_at', ''))::timestamptz, d.ends_at),
        days      = case when p ? 'days' then case when cardinality(dys) between 1 and 6 then dys end else d.days end,
        from_time = case when p ? 'from_time' then (public._screen_hhmm(p ->> 'from_time')).t else d.from_time end,
        to_time   = case when p ? 'to_time' then (public._screen_hhmm(p ->> 'to_time')).t else d.to_time end,
        sort      = coalesce((p ->> 'sort')::int, d.sort),
        template  = case when v_kind = 'composicion' then v_template else d.template end,
        zones     = case when v_kind = 'composicion' then v_zones else d.zones end,
        dwell_seconds = case when v_kind = 'composicion' then v_dwell else d.dwell_seconds end,
        updated_at = now(), updated_by = public._screen_actor()
      where d.id = old.id
      returning * into new_row;
    end if;
  exception when check_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow
                 or numeric_value_out_of_range or not_null_violation or invalid_parameter_value then
    return jsonb_build_object('ok', false, 'error', 'invalid', 'detail', sqlerrm);
  end;
  v_summary := coalesce(new_row.title_es, (select i.name from public.menu_items i where i.id = new_row.menu_item_id),
                        case when new_row.kind = 'composicion' then 'composición · ' || new_row.template end);
  perform public._screen_log('diapositiva', new_row.id::text, case when old.id is null then 'crear' else 'cambiar' end,
                             v_summary,
                             case when old.id is null then null else public._slide_json(old) - 'item' - 'zones' - 'usable' || jsonb_build_object('zones', old.zones) end,
                             public._slide_json(new_row) - 'item' - 'zones' - 'usable' || jsonb_build_object('zones', new_row.zones));
  return jsonb_build_object('ok', true, 'slide', public._slide_json(new_row));
end $$;
revoke all on function public.diapositiva_guardar(jsonb) from public, anon;
grant execute on function public.diapositiva_guardar(jsonb) to authenticated;

-- pausing, resuming or retiring a slide logs its summary; a composition's summary is its template, as diapositiva_guardar
-- writes it (the 0036 text knew only titles and products)
create or replace function public.diapositiva_estado(p_id uuid, p_estado text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare old public.screen_slides; new_row public.screen_slides;
begin
  if not public.is_true_owner() then return jsonb_build_object('ok', false, 'error', 'owner_only'); end if;
  if p_estado is null or p_estado not in ('activa', 'pausada', 'retirada') then return jsonb_build_object('ok', false, 'error', 'invalid'); end if;
  select * into old from public.screen_slides where id = p_id for update;
  if old.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if old.status = 'retirada' then return jsonb_build_object('ok', false, 'error', 'retired'); end if;
  if old.status = p_estado then return jsonb_build_object('ok', true, 'slide', public._slide_json(old), 'unchanged', true); end if;
  update public.screen_slides set status = p_estado, updated_at = now(), updated_by = public._screen_actor()
   where id = p_id returning * into new_row;
  perform public._screen_log('diapositiva', p_id::text,
                             case p_estado when 'activa' then 'reanudar' when 'pausada' then 'pausar' else 'retirar' end,
                             coalesce(new_row.title_es, (select i.name from public.menu_items i where i.id = new_row.menu_item_id),
                                      case when new_row.kind = 'composicion' then 'composición · ' || new_row.template end),
                             jsonb_build_object('status', old.status), jsonb_build_object('status', new_row.status));
  return jsonb_build_object('ok', true, 'slide', public._slide_json(new_row));
end $$;
revoke all on function public.diapositiva_estado(uuid, text) from public, anon;
grant execute on function public.diapositiva_estado(uuid, text) to authenticated;

select canopy.migration_end(37, 'pantallas_v2');
notify pgrst, 'reload schema';
