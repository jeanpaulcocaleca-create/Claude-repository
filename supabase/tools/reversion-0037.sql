-- =====================================================================================================
-- Canopy OS · reversión de la migración 0037 (Pantallas v2) · pegar TODO en Supabase → SQL Editor → Run
-- Solo por una falla de una función de la 0037. Vuelve las seis funciones que la 0037 cambió a su texto de la 0036
-- (_screen_json, _slide_json, pantalla_datos, pantalla_guardar, diapositiva_guardar, diapositiva_estado), quita
-- _screen_item_json y deja el libro en la 0036. NO borra nada: las columnas nuevas de screens y screen_slides quedan
-- (con lo que tengan), y
-- _screen_template_places queda porque la regla screen_slides_kind la usa (una columna y una regla aditivas no
-- estorban a nadie). Una diapositiva de clase «composicion» queda guardada; las páginas publicadas antes de la v2 la
-- ignoran, y las de la v2 la muestran solo si la lectura trae sus zonas, así que con la 0036 no la muestran.
-- _slide_json se vuelve a crear con el texto de la 0036 escrito con escapes \uXXXX (lint 14, D-063): misma regla, mismo
-- comportamiento; su huella está aceptada en production-snapshot.sql como versión 0036.
-- Se niega si la 0037 no está aplicada o si hay una migración posterior aplicada (revierta esa primero).
-- Después: production-snapshot.sql debe decir que la última migración es la 36.
-- =====================================================================================================
do $$
begin
  if not exists (select 1 from canopy.migrations where version = 37) then
    raise exception 'La migración 0037 no está aplicada: no hay nada que revertir. No se cambió nada.';
  end if;
  if exists (select 1 from canopy.migrations where version > 37) then
    raise exception 'Hay una migración posterior a la 0037 aplicada (%): revierta esa primero. No se cambió nada.',
      (select string_agg(version::text, ', ' order by version) from canopy.migrations where version > 37);
  end if;
end $$;
set local lock_timeout = '8s';

-- 1) las funciones vuelven a la 0036 ---------------------------------------------------------------------------------
create or replace function public._screen_json(s public.screens)
returns jsonb language sql stable set search_path = public as $$
  select jsonb_build_object('id', s.id, 'kind', s.kind, 'name', s.name, 'inches', s.inches, 'distance_m', s.distance_m,
    'turn', s.turn, 'scale_pct', s.scale_pct, 'look', s.look, 'page_seconds', s.page_seconds, 'slide_seconds', s.slide_seconds,
    'category_ids', to_jsonb(s.category_ids), 'sold_out', s.sold_out,
    'on_from', to_char(s.on_from, 'HH24:MI'), 'on_to', to_char(s.on_to, 'HH24:MI'), 'active', s.active, 'updated_at', s.updated_at);
$$;
revoke all on function public._screen_json(public.screens) from public, anon, authenticated;

-- a slide as the screens see it; a product slide carries the item's live name, Spanish name, price, photo, availability
-- and category (read with to_jsonb, so the Spanish name works whether menu-spanish.sql was applied or not)
create or replace function public._slide_json(d public.screen_slides)
returns jsonb language sql stable set search_path = public as $$
  select jsonb_build_object('id', d.id, 'kind', d.kind, 'menu_item_id', d.menu_item_id,
    'kicker_es', d.kicker_es, 'kicker_en', d.kicker_en, 'title_es', d.title_es, 'title_en', d.title_en,
    'body_es', d.body_es, 'body_en', d.body_en, 'photo_url', d.photo_url, 'link', d.link, 'screen_ids', to_jsonb(d.screen_ids),
    'starts_at', d.starts_at, 'ends_at', d.ends_at, 'days', to_jsonb(d.days),
    'from_time', to_char(d.from_time, 'HH24:MI'), 'to_time', to_char(d.to_time, 'HH24:MI'), 'sort', d.sort, 'status', d.status,
    'item', (select jsonb_build_object('name', i.name, 'name_es', nullif(btrim(coalesce(to_jsonb(i) ->> 'name_es', '')), ''),
                                       'price_crc', i.price_crc, 'photo_url', i.photo_url, 'available', i.available,
                                       'category', c.name,
                                       -- what Screen A shows too: available, a price above 0, a name that is not blank
                                       -- (blank as the screens' JavaScript trim() sees it), never a till helper
                                       'sellable', (i.available and i.price_crc > 0
                                                    and coalesce(i.name, '') ~ '[^[:space:]\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]'
                                                    and c.name is distinct from 'Extras & Combos'))
               from public.menu_items i left join public.menu_categories c on c.id = i.category_id
              where i.id = d.menu_item_id));
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
  if s.kind = 'promos' then
    -- in force or starting within a day (the TV switches on time even if a read is late, and hides an ended slide by
    -- itself without internet); a product slide only while the item can be sold
    -- (the product check comes before the cap of 60, so sold-out products never push a sellable slide out)
    select coalesce(jsonb_agg(x.j order by x.sort, x.starts_at, x.id), '[]'::jsonb) into sl
      from (select y.j, y.sort, y.starts_at, y.id
              from (select public._slide_json(d) as j, d.sort, d.starts_at, d.id
                      from public.screen_slides d
                     where d.status = 'activa' and (d.screen_ids is null or s.id = any (d.screen_ids))
                       and d.ends_at > now() and d.starts_at < now() + interval '1 day') y
             where y.j ->> 'kind' <> 'producto' or coalesce((y.j -> 'item' ->> 'sellable')::boolean, false)
             order by (y.starts_at > now()), y.sort, y.starts_at, y.id   -- in force first: an upcoming one never pushes one out
             limit 60) x;
  end if;
  return jsonb_build_object('ok', true, 'now', now(), 'tv', public._screen_json(s), 'slides', sl);
end $$;
revoke all on function public.pantalla_datos(text) from public;
grant execute on function public.pantalla_datos(text) to anon, authenticated;

-- a TV's settings; a new TV needs its id and kind, an existing one keeps them
create or replace function public.pantalla_guardar(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare old public.screens; new_row public.screens; v_id text; v_kind text; cats uuid[]; bad text;
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
                                     category_ids, sold_out, on_from, on_to, active, updated_at, updated_by)
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
            now(), public._screen_actor())
    on conflict (id) do update set
      name = excluded.name, inches = excluded.inches, distance_m = excluded.distance_m, turn = excluded.turn,
      scale_pct = excluded.scale_pct, look = excluded.look, page_seconds = excluded.page_seconds,
      slide_seconds = excluded.slide_seconds, category_ids = excluded.category_ids, sold_out = excluded.sold_out,
      on_from = excluded.on_from, on_to = excluded.on_to, active = excluded.active,
      updated_at = excluded.updated_at, updated_by = excluded.updated_by
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

-- a slide: created without an id, changed with its id; its kind never changes; a retired slide is not edited
create or replace function public.diapositiva_guardar(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare old public.screen_slides; new_row public.screen_slides; v_id uuid; v_kind text; f text; bad text; v_item uuid; v_cat text;
        scr text[]; dys smallint[]; v_link text; v_photo text;
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
  if v_kind is null or v_kind not in ('producto', 'marca', 'invitacion') then
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
      if exists (select 1 from unnest(scr) x where not exists (select 1 from public.screens s where s.id = x and s.kind = 'promos')) then
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
                                        created_by, updated_by)
      values (v_kind, case when v_kind = 'producto' then v_item end,
              nullif(btrim(p ->> 'kicker_es'), ''), nullif(btrim(p ->> 'kicker_en'), ''),
              nullif(btrim(p ->> 'title_es'), ''), nullif(btrim(p ->> 'title_en'), ''),
              nullif(btrim(p ->> 'body_es'), ''), nullif(btrim(p ->> 'body_en'), ''),
              v_photo, v_link, case when cardinality(scr) > 0 then scr end,
              (p ->> 'starts_at')::timestamptz, (p ->> 'ends_at')::timestamptz,
              case when cardinality(dys) between 1 and 6 then dys end,
              (public._screen_hhmm(p ->> 'from_time')).t, (public._screen_hhmm(p ->> 'to_time')).t,
              coalesce((p ->> 'sort')::int, 100),
              case when p ->> 'status' = 'pausada' then 'pausada' else 'activa' end,
              public._screen_actor(), public._screen_actor())
      returning * into new_row;
    else
      update public.screen_slides d set
        menu_item_id = case when v_kind = 'producto' then v_item end,
        kicker_es = case when p ? 'kicker_es' then nullif(btrim(p ->> 'kicker_es'), '') else d.kicker_es end,
        kicker_en = case when p ? 'kicker_en' then nullif(btrim(p ->> 'kicker_en'), '') else d.kicker_en end,
        title_es  = case when p ? 'title_es'  then nullif(btrim(p ->> 'title_es'), '')  else d.title_es end,
        title_en  = case when p ? 'title_en'  then nullif(btrim(p ->> 'title_en'), '')  else d.title_en end,
        body_es   = case when p ? 'body_es'   then nullif(btrim(p ->> 'body_es'), '')   else d.body_es end,
        body_en   = case when p ? 'body_en'   then nullif(btrim(p ->> 'body_en'), '')   else d.body_en end,
        photo_url = v_photo, link = v_link,
        screen_ids = case when p ? 'screen_ids' then case when cardinality(scr) > 0 then scr end else d.screen_ids end,
        starts_at = coalesce((nullif(p ->> 'starts_at', ''))::timestamptz, d.starts_at),
        ends_at   = coalesce((nullif(p ->> 'ends_at', ''))::timestamptz, d.ends_at),
        days      = case when p ? 'days' then case when cardinality(dys) between 1 and 6 then dys end else d.days end,
        from_time = case when p ? 'from_time' then (public._screen_hhmm(p ->> 'from_time')).t else d.from_time end,
        to_time   = case when p ? 'to_time' then (public._screen_hhmm(p ->> 'to_time')).t else d.to_time end,
        sort      = coalesce((p ->> 'sort')::int, d.sort),
        updated_at = now(), updated_by = public._screen_actor()
      where d.id = old.id
      returning * into new_row;
    end if;
  exception when check_violation or invalid_text_representation or invalid_datetime_format or datetime_field_overflow
                 or numeric_value_out_of_range or not_null_violation or invalid_parameter_value then
    return jsonb_build_object('ok', false, 'error', 'invalid', 'detail', sqlerrm);
  end;
  perform public._screen_log('diapositiva', new_row.id::text, case when old.id is null then 'crear' else 'cambiar' end,
                             coalesce(new_row.title_es, (select i.name from public.menu_items i where i.id = new_row.menu_item_id)),
                             case when old.id is null then null else public._slide_json(old) - 'item' end,
                             public._slide_json(new_row) - 'item');
  return jsonb_build_object('ok', true, 'slide', public._slide_json(new_row));
end $$;
revoke all on function public.diapositiva_guardar(jsonb) from public, anon;
grant execute on function public.diapositiva_guardar(jsonb) to authenticated;


-- a slide's state; the summary knows titles and products, as the 0036 wrote it
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
                             coalesce(new_row.title_es, (select i.name from public.menu_items i where i.id = new_row.menu_item_id)),
                             jsonb_build_object('status', old.status), jsonb_build_object('status', new_row.status));
  return jsonb_build_object('ok', true, 'slide', public._slide_json(new_row));
end $$;
revoke all on function public.diapositiva_estado(uuid, text) from public, anon;
grant execute on function public.diapositiva_estado(uuid, text) to authenticated;

-- 2) lo que solo existía por la 0037 -----------------------------------------------------------------------------------
drop function if exists public._screen_item_json(uuid);
-- _screen_template_places(text) queda: la regla screen_slides_kind (aditiva) la usa

-- 3) el libro --------------------------------------------------------------------------------------------------------------
delete from canopy.migrations where version = 37;
notify pgrst, 'reload schema';
