/* Screen A (website/pantalla-menu.html, docs/PANTALLAS.md, migration 0036): the menu with prices for the guests.
   The owner's conditions it is held to here:
   3) prices and availability read only from the existing menu, never written; in sync by itself (it polls);
   4) a lost connection or old data never shows a price as current;
   5) read from a distance: big prices, little else;
   7) never Extras & Combos (combos and discounts are not announced);
   8) its settings come from the owner's page (pantallas, table screens), read with the public key, never written.
   A1-A9 are the prototype's tests (fixed per the review); B1-B11 the settings from the database and the review fixes;
   B12-B22 the v2 board (migration 0037): category blocks in explicit balanced columns, one screen when the letter allows
   it, density and English per TV, promotions intercalated in the menu (drawn by Screen B's renderer, copied into the
   page: B21 a composition as an interlude, B22 the slides' prices aging with the read that brought them), the new
   address overrides. */
'use strict';
const assert = require('assert');
const { page, goto, until, sql } = require('../lib');

const API_PORT = String(Number(process.env.E2E_SITE_PORT || 8090) + 1000);
const PGRST = 'http://127.0.0.1:' + (process.env.E2E_PGRST_PORT || 3013);
const LARGO_CM = (pulgadas) => pulgadas * 2.54 * 16 / Math.sqrt(337);   /* long side of a 16:9 screen */
const clave = (s) => String(s || '').replace(/\s+/g, ' ').trim().toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
const digits = (s) => Number(String(s || '').replace(/\D/g, '')) || 0;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const READS = ['GET /rest/v1/menu_categories', 'GET /rest/v1/rpc/pantalla_datos'];
/* Costa Rica is UTC-6 all year */
const crMin = (ms) => (((Math.floor(ms / 60000) - 360) % 1440) + 1440) % 1440;
const hhmm = (m) => { m = ((m % 1440) + 1440) % 1440; return String(Math.floor(m / 60)).padStart(2, '0') + ':' + String(m % 60).padStart(2, '0'); };
/* the columns of the TV's row the device may keep (never a price) */
const CAMPOS_FILA = ['id', 'kind', 'inches', 'distance_m', 'turn', 'scale_pct', 'look', 'page_seconds', 'category_ids', 'item_ids', 'sold_out', 'on_from', 'on_to', 'updated_at',
                     'layout', 'density', 'english', 'promo_mode', 'promo_every', 'promo_seconds'];
const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAQAAAADCAIAAAA7ljmRAAAAEElEQVR4nGOQ8zaGIwacHACNwwdR68r19QAAAABJRU5ErkJggg==', 'base64');
const CAT = { coffee: 'a0000000-0000-4000-8000-000000000001', pastries: 'a0000000-0000-4000-8000-000000000006',
              extras: 'a0000000-0000-4000-8000-000000000009', gone: '0b000000-0000-4000-8000-0000000000ff' };

/* the screen on its own device; every call to the database stand-in is kept (method and path) */
async function pantalla(browser, opts) {
  opts = opts || {};
  const pg = await page(browser, { context: opts.context, viewport: opts.viewport || { width: 1920, height: 1080 }, station: null, lang: 'es' });
  pg.api = [];
  pg.on('request', (r) => { const u = new URL(r.url()); if (u.port === API_PORT) pg.api.push(r.method() + ' ' + u.pathname); });
  /* photos of the slides: a small real image (they live on hosts the tests never reach) */
  await pg.route(/^https:\/\/fotos\.test\//, (r) => r.fulfill({ status: 200, contentType: 'image/png', body: PNG }));
  if (opts.test) await pg.addInitScript((t) => { window.PANTALLA_TEST = t; }, opts.test);
  if (opts.reloj) await pg.addInitScript((ms) => { const real = Date.now.bind(Date), t0 = real(); Date.now = () => ms + (real() - t0); }, opts.reloj);
  if (opts.setup) await opts.setup(pg);
  await goto(pg, '/pantalla-menu' + (opts.q === undefined ? '?tv=menu-1&pulgadas=55&distancia=3' : opts.q));
  if (opts.wait !== false) await until(() => pg.evaluate(() => !!window.PANTALLA && PANTALLA.info().estado === 'al-dia'), 15000, 'the prices verified');
  return pg;
}
const info = (pg) => pg.evaluate(() => PANTALLA.info());
/* what every page of the screen holds (hidden pages too) */
const contenido = (pg) => pg.evaluate(() => [...document.querySelectorAll('#main .page')].map((p) => [...p.querySelectorAll('.cat')].map((c) => ({
  cat: c.querySelector('h2 .ces').textContent, catEn: (c.querySelector('h2 .cen') || {}).textContent || '',
  items: [...c.querySelectorAll('.it')].map((i) => ({ es: i.querySelector('.es').textContent, en: (i.querySelector('.en') || {}).textContent || '',
                                                     pr: (i.querySelector('.pr') || {}).textContent || '',
                                                     ago: i.classList.contains('agotado'), tag: (i.querySelector('.ago') || {}).textContent || '',
                                                     strike: getComputedStyle(i.querySelector('.es')).textDecorationLine }))
}))));
const items = (pages) => pages.flat().flatMap((c) => c.items);
const cats = (pages) => pages.flat().map((c) => clave(c.catEn || c.cat)).filter((c, i, a) => i === 0 || c !== a[i - 1]);
const find = async (pg, name) => items(await contenido(pg)).find((g) => g.es === name || g.en === name);
const stageText = (pg) => pg.evaluate(() => document.getElementById('stage').innerText);
const diag = (pg) => pg.evaluate(() => document.getElementById('diag').innerText);
const aviso = (pg) => pg.evaluate(() => { const a = document.getElementById('aviso'); return a.hidden ? '' : a.innerText.replace(/\s+/g, ' ').trim(); });
const onlyReads = (pg) => pg.api.length > 0 && pg.api.every((r) => READS.includes(r));
const reads = (pg, k) => pg.api.filter((r) => r === READS[k]).length;
/* the capital of the names as drawn, in cm on a screen of that size */
const capitales = (pg) => pg.evaluate(() => {
  const cx = document.createElement('canvas').getContext('2d');
  const cap = (e) => { const cs = getComputedStyle(e); cx.font = cs.fontWeight + ' ' + cs.fontSize + ' ' + cs.fontFamily; return cx.measureText('H').actualBoundingBoxAscent; };
  const n = [...document.querySelectorAll('#main .page .it .es')].map(cap);
  return { min: Math.min(...n), max: Math.max(...n) };
});
/* the server's clock as the screen sees it: every answer of pantalla_datos carries now = reloj() */
const relojServidor = (reloj) => (pg) => pg.route(/\/rest\/v1\/rpc\/pantalla_datos/, async (route) => {
  let r; try { r = await route.fetch(); } catch (e) { return route.abort(); }
  let j = null; try { j = await r.json(); } catch (e) {}
  if (j && typeof j === 'object') j.now = new Date(reloj()).toISOString();
  return j ? route.fulfill({ response: r, json: j }) : route.fulfill({ response: r });
});
/* the migration not applied: the function gone, and PostgREST knows */
async function sinFuncion() {
  sql(`drop function public.pantalla_datos(text); notify pgrst, 'reload schema';`);
  await until(async () => (await fetch(PGRST + '/rpc/pantalla_datos?p_tv=menu-1')).status === 404, 10000, 'PostgREST without pantalla_datos');
}
/* what the screen must show: available items with a price above zero, never Extras & Combos */
const EXPECTED = `select coalesce(json_agg(json_build_object('cat', c.name, 'name', i.name, 'name_es', i.name_es, 'price', i.price_crc)
                   order by c.sort, i.sort, i.name), '[]')
                    from menu_items i join menu_categories c on c.id = i.category_id
                   where c.name <> 'Extras & Combos' and i.available and i.price_crc > 0`;

/* the café's real menu as the public page shows it: the 7 categories and 39 products (the test seed carries two more
   lines, the Adventure Box, which the public page does not sell as menu lines) with the Spanish names of the public page */
const REAL_ES = { Cappuccino: 'Capuchino', Mocha: 'Moca', 'Café con Leche': 'Café con leche', 'Cloud Forest Latte': 'Latte del Bosque Nuboso',
  'Iced Americano': 'Americano frío', 'Iced Latte': 'Latte frío', 'Iced Mocha': 'Moca frío', 'Costa Rican Hot Chocolate': 'Chocolate caliente costarricense',
  Tea: 'Té', 'Sweet Cane Drink': 'Agua dulce', 'Ham & Cheese': 'Jamón y queso', 'Chicken Pesto': 'Pollo al pesto', 'Chicken Empanada': 'Empanada de pollo',
  'Beef Empanada': 'Empanada de carne', 'Ham & Cheese Croissant': 'Croissant de jamón y queso', 'Butter Croissant': 'Croissant de mantequilla',
  'Chocolate Croissant': 'Croissant de chocolate', 'Banana Bread': 'Pan de banano', 'Carrot Cake': 'Queque de zanahoria', 'Tres Leches': 'Tres leches', 'Tamal Asado': 'Tamal asado' };
function menuReal() {
  sql(`update menu_items set available = false where category_id = (select id from menu_categories where name = 'Adventure Box');
       update menu_items set name_es = null where name not in (${Object.keys(REAL_ES).map((k) => `'${k.replace(/'/g, "''")}'`).join(', ')});
       ${Object.keys(REAL_ES).map((k) => `update menu_items set name_es = '${REAL_ES[k]}' where name = '${k.replace(/'/g, "''")}';`).join('\n')}`);
}
/* the explicit columns of every page: each column's blocks (a title first, then only items), their places and the column's room */
const columnas = (pg) => pg.evaluate(() => [...document.querySelectorAll('#main .page')].map((p) => [...p.querySelectorAll('.col')].map((c) => ({
  secciones: [...c.children].map((s) => ({ ok: s.classList.contains('cat') && !!s.firstElementChild && s.firstElementChild.tagName === 'H2' && [...s.children].slice(1).every((e) => e.classList.contains('it')),
                                          cat: (s.querySelector('h2 .ces') || {}).textContent || '', cont: !!s.querySelector('h2 .cont'), n: s.querySelectorAll('.it').length,
                                          top: s.offsetTop - c.offsetTop, bottom: s.offsetTop - c.offsetTop + s.offsetHeight })),
  alto: c.clientHeight, scroll: c.scrollHeight, w: c.clientWidth }))));
/* the promotion layer over the menu and what it shows: Screen B's renderer, copied into the page, so the slide has
   Screen B's classes (.sl, .tit, .precio, .zona …) and 380's helpers read it the same way */
const promoVista = (pg) => pg.evaluate(() => {
  const p = document.getElementById('promo'), sl = p.querySelector('.sl'), t = (s) => { const e = sl && sl.querySelector(s); return e ? e.textContent : null; };
  return { on: p.classList.contains('on'), opacity: Number(getComputedStyle(p).opacity), id: sl ? sl.dataset.id : null, kind: sl ? sl.dataset.kind : null,
           kick: t('.kick'), tit: t('.tit'), titEn: t('.tit-en'), precio: t('.precio'), cur: t('.precio .cur'), nota: t('.nota'), pida: t('.pida'), sup: t('.sup'),
           qr: !!(sl && sl.querySelector('.qrcard svg')), dir: sl ? [...sl.querySelectorAll('.dir, .dirsola')].map((d) => d.textContent) : [], text: p.innerText };
});
/* the composition on the promotion layer (as 380's zonas helper reads Screen B's): each zone's place (px inside the
   stage), what it shows (its front image layer) and its two image layers */
const zonasPromo = (pg) => pg.evaluate(() => {
  const sl = document.querySelector('#promo .sl.k-composicion');
  if (!sl) return null;
  const W = innerWidth, H = innerHeight, cx = document.createElement('canvas').getContext('2d');
  const cap = (e) => { const cs = getComputedStyle(e); cx.font = cs.fontWeight + ' ' + cs.fontSize + ' ' + cs.fontFamily; return cx.measureText('H').actualBoundingBoxAscent; };
  return {
    id: sl.dataset.id, template: sl.dataset.template, kick: (sl.querySelector('.zkick') || {}).textContent || null, sup: (sl.querySelector('.sup') || {}).textContent || null,
    text: sl.innerText,
    zonas: [...sl.querySelectorAll('.zona')].map((z) => {
      const front = z.querySelector('.zcapa.on.entra') || z.querySelector('.zcapa.on:not(.sale)') || z.querySelector('.zcapa.on');
      const f = (s) => { const e = front && front.querySelector(s); return e ? e.textContent : null; };
      const r = z.getBoundingClientRect(), im = front && front.querySelector('img');
      return { i: Number(z.dataset.zona), modo: z.dataset.modo, estado: z.dataset.estado, entrada: z.dataset.entrada === '' ? null : Number(z.dataset.entrada),
               tamano: z.dataset.tamano, box: [z.offsetLeft, z.offsetTop, z.offsetWidth, z.offsetHeight],
               dentro: r.left >= -1 && r.top >= -1 && r.right <= W + 1 && r.bottom <= H + 1,
               src: front ? front.dataset.src || null : null, tit: f('.ztit'), titEn: f('.ztit-en'), precio: f('.zprecio'), nota: f('.znota'),
               marca: !!(front && front.querySelector('.zmarca')), lugar: f('.lugar'),
               encuadre: im ? [im.style.objectPosition, im.style.transform] : null,
               caps: [...z.querySelectorAll('[data-r]')].filter((e) => e.getClientRects().length).map((e) => ({ r: e.dataset.r, cap: cap(e), cortado: e.scrollWidth > e.clientWidth + 1 })),
               capas: [...z.querySelectorAll('.zcapa')].map((c) => { const i = c.querySelector('img'); return { on: c.classList.contains('on'), entra: c.classList.contains('entra'),
                 sale: c.classList.contains('sale'), opacity: Number(getComputedStyle(c).opacity), src: c.dataset.src || null,
                 img: !!i, lista: !!i && i.complete && i.naturalWidth > 0, marca: !!c.querySelector('.zmarca') }; }),
               text: z.innerText };
    })
  };
});
/* samples what each zone of the composition on the layer shows every `cada` ms for `ms` ms, and the moments a zone's entry changed */
async function muestrearPromo(pg, ms, cada) {
  const out = [], t0 = Date.now();
  while (Date.now() - t0 < ms) { const z = await zonasPromo(pg); out.push({ t: Date.now() - t0, z }); await sleep(cada || 40); }
  return out;
}
const cambiosPromo = (muestras, i) => muestras.filter((m, k) => k > 0 && m.z && muestras[k - 1].z && m.z.zonas[i].entrada !== muestras[k - 1].z.zonas[i].entrada).map((m) => m.t);
const fotos = (pre, n) => Array.from({ length: n }, (_, i) => `https://fotos.test/${pre}${i}.png`);
const q = (v) => (v == null ? 'null' : "'" + String(v).replace(/'/g, "''") + "'");
const arr = (a) => (a == null ? 'null' : q('{' + a.join(',') + '}'));
/* a slide written straight into the database (pantallas.html, which writes them for the owner, has its own tests); returns its id */
function diapo(o) {
  return sql(`with x as (insert into public.screen_slides (kind, menu_item_id, kicker_es, kicker_en, title_es, title_en, body_es, body_en,
                                   photo_url, link, screen_ids, starts_at, ends_at, days, from_time, to_time, sort, status)
    values (${q(o.kind)}, ${o.item ? `(select id from public.menu_items where name = ${q(o.item)})` : 'null'},
            ${q(o.kicker_es)}, ${q(o.kicker_en)}, ${q(o.title_es)}, ${q(o.title_en)}, ${q(o.body_es)}, ${q(o.body_en)},
            ${q(o.photo)}, ${q(o.link)}, ${arr(o.screens)}, ${o.starts || "now() - interval '1 hour'"}, ${o.ends || "now() + interval '1 day'"},
            ${arr(o.days)}, ${q(o.from)}, ${q(o.to)}, ${o.sort == null ? 100 : o.sort}, ${q(o.status || 'activa')}) returning id) select id from x`);
}
const marca = (title, o) => diapo(Object.assign({ kind: 'marca', title_es: title, title_en: title + ' (en)' }, o || {}));
const itemId = (name) => sql(`select id from public.menu_items where name = ${q(name)}`);
/* a composition (migration 0037) written straight into the database; a string entry is a photo when it is an address, a product otherwise */
function compo(o) {
  const entry = (e) => {
    if (typeof e === 'string') return /^https?:/.test(e) ? { item: null, photo: e, focus: [50, 50], zoom: 100 } : { item: itemId(e), photo: null, focus: [50, 50], zoom: 100 };
    return { item: e.item ? itemId(e.item) : null, photo: e.photo || null, focus: e.focus || [50, 50], zoom: e.zoom || 100 };
  };
  const zones = o.zones.map((z) => ({ mode: z.mode || 'fija', seconds: z.seconds == null ? 8 : z.seconds, labels: z.labels !== false, fallback: z.fallback || null, entries: z.entries.map(entry) }));
  return sql(`with x as (insert into public.screen_slides (kind, template, zones, dwell_seconds, kicker_es, kicker_en, screen_ids, starts_at, ends_at, days, from_time, to_time, sort, status)
    values ('composicion', ${q(o.template)}, ${q(JSON.stringify(zones))}::jsonb, ${o.dwell == null ? 'null' : o.dwell}, ${q(o.kicker_es)}, ${q(o.kicker_en)},
            ${arr(o.screens)}, ${o.starts || "now() - interval '1 hour'"}, ${o.ends || "now() + interval '1 day'"},
            ${arr(o.days)}, ${q(o.from)}, ${q(o.to)}, ${o.sort == null ? 100 : o.sort}, ${q(o.status || 'activa')}) returning id) select id from x`);
}

module.exports.tests = [
  {
    name: 'A1: every available item with its price, categories and items in the Menu Manager order; never Extras & Combos, a sold-out item or a price of zero; Spanish first, a name the same in both languages once; only GET reads; the device keeps only names',
    run: async ({ browser }) => {
      sql(`update menu_items set available = false where name = 'Tea';
           update menu_items set price_crc = 0 where name = 'Sweet Cane Drink';
           update menu_items set name_es = 'Pan de banano casero' where name = 'Banana Bread';`);
      const pg = await pantalla(browser);
      const want = JSON.parse(sql(EXPECTED));
      const pages = await contenido(pg), got = items(pages);
      assert.ok(want.length > 30, 'the test menu has its items');
      assert.strictEqual(got.length, want.length, 'one line per available item with a price, each once');
      const match = (g, w) => g.en === w.name || (w.name_es && g.es === w.name_es) || (!g.en && clave(g.es) === clave(w.name));
      want.forEach((w) => {
        const hit = got.filter((g) => digits(g.pr) === w.price && match(g, w));
        assert.ok(hit.length >= 1, `${w.name} (₡${w.price}) is on the screen with its price`);
      });
      /* categories, and the items inside each, in the Menu Manager order (a category cut across pages shows its title on each part) */
      assert.deepStrictEqual(cats(pages), [...new Set(want.map((w) => clave(w.cat)))], 'categories in the Menu Manager order');
      const order = got.map((g) => want.findIndex((w) => match(g, w)));
      assert.ok(order.every((k, j) => k >= 0 && (j === 0 || k > order[j - 1])), 'items in the Menu Manager order inside each category: ' + order.join(','));
      const text = await stageText(pg);
      assert.ok(!/Combo|Flavor shot|Add ham|milk upgrade|Extras/i.test(text), 'nothing of Extras & Combos on the screen');
      assert.ok(!got.some((g) => /Tea|Té$|Sweet Cane|Agua dulce/.test(g.es + ' ' + g.en)), 'the sold-out item and the item without a price are not shown');
      assert.ok(got.every((g) => /^₡\s?\d{1,3}([\s  ]\d{3})*$/.test(g.pr) && digits(g.pr) > 0), 'every price is ₡ and a positive amount');
      /* Spanish first: the Menu Manager's name_es, else the site's dictionary; English below; the same name once */
      const by = (es) => got.find((g) => g.es === es);
      assert.deepStrictEqual([by('Pan de banano casero').es, by('Pan de banano casero').en], ['Pan de banano casero', 'Banana Bread']);
      assert.strictEqual(by('Capuchino').en, 'Cappuccino');
      assert.strictEqual(by('Espresso').en, '', 'Espresso is written once');
      assert.strictEqual(by('Tres leches').en, '', 'Tres Leches / Tres leches is written once');
      assert.ok(pages.flat().some((c) => c.cat === 'Café' && c.catEn === 'Coffee'), 'category titles in Spanish with the English beside');
      assert.ok(/Precios en colones, IVA incluido · Prices in colones, tax \(IVA\) included/.test(text), 'the note on colones and IVA');
      assert.strictEqual(await aviso(pg), '', 'no warning while the prices are verified');
      /* only reads: the menu and this TV's settings, GET only; no sign-in, no write; the real Supabase is never reached */
      assert.ok(onlyReads(pg) && reads(pg, 0) >= 1 && reads(pg, 1) >= 1, 'only GET reads of the menu and of pantalla_datos: ' + [...new Set(pg.api)].join(', '));
      assert.strictEqual(pg.supabaseHits, 0);
      /* this TV keeps the names for a start without internet, never the prices: the copy parsed holds names only */
      assert.deepStrictEqual(await pg.evaluate(() => [Object.keys(localStorage).sort(), Object.keys(sessionStorage)]),
        [['hg-pantalla-menu', 'hg-pantalla-menu-tv', 'hg_lang'], []], 'the device holds the names copy, the settings row and the language: nothing else');
      const raw = await pg.evaluate(() => localStorage.getItem('hg-pantalla-menu'));
      const copia = JSON.parse(raw);
      assert.deepStrictEqual(Object.keys(copia).sort(), ['at', 'cats', 'muestra']);
      assert.deepStrictEqual(copia.muestra, { categorias: 'todas', categoriasFaltan: 0, productos: 'todos', productosFaltan: 0, enPantalla: null },
        'what the copy was filtered by (states and counts, so a cold start says the same): never a price');
      assert.ok(copia.cats.length >= 8, 'the names are kept on the device');
      copia.cats.forEach((c) => {
        assert.deepStrictEqual(Object.keys(c).sort(), ['en', 'es', 'items']);
        c.items.forEach((it) => assert.deepStrictEqual(Object.keys(it).sort(), ['en', 'es'], 'an item of the copy is only its names'));
        [c.es, c.en].concat(...c.items.map((it) => [it.es, it.en])).forEach((s) => assert.ok(typeof s === 'string' && !/₡|\d{3}/.test(s), s));
      });
      assert.strictEqual(copia.cats.flatMap((c) => c.items).length, want.length);
      assert.ok(!/precio|price|₡|"\d{3,}/.test(raw), 'no price is kept on the device: ' + raw.slice(0, 120));
      const tv = JSON.parse(await pg.evaluate(() => localStorage.getItem('hg-pantalla-menu-tv')));
      assert.ok(tv.fila && !Object.keys(tv.fila).some((k) => k !== 'item_ids' && /price|precio|item/.test(k)) && !/₡/.test(JSON.stringify(tv)), 'the settings copy holds no price');
      const i = await info(pg);
      assert.deepStrictEqual([i.tiempos.cada, i.tiempos.fresco, i.tiempos.vencido, i.paginaMs, i.salto, i.tiempos.limite], [30000, 120000, 600000, 28000, 3000, 12000],
        'reads every 30 s; prices shown up to 2 min, «por confirmar» up to 10 min; a page every 28 s; a pause over 3 s (3 ticks of 1 s); 12 s per read');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'A2: legible from the farthest reader on TV browsers of every size, landscape and turned either way: capitals ≥ 0.8 cm per metre (target 1), titles 1.5× (≥ 1.25× when a word is longer than the column), English ≥ 75 %, prices as big as the names, nothing cut off',
    run: async ({ browser }) => {
      const want = JSON.parse(sql(EXPECTED)).length;
      const cases = [[960, 540, 'no'], [1280, 720, 'no'], [1920, 1080, 'no'], [3840, 2160, 'no'],
                     [1920, 1080, 'derecha'], [1920, 1080, 'izquierda'], [1280, 720, 'derecha']];
      for (const [w, h, giro] of cases) {
        const pg = await pantalla(browser, { viewport: { width: w, height: h }, q: `?tv=menu-1&pulgadas=55&distancia=3&giro=${giro}` });
        const where = `${w}×${h} giro ${giro}`;
        const m = await pg.evaluate(() => {
          const cx = document.createElement('canvas').getContext('2d');
          const cap = (e) => { const cs = getComputedStyle(e); cx.font = cs.fontWeight + ' ' + cs.fontSize + ' ' + cs.fontFamily; return cx.measureText('H').actualBoundingBoxAscent; };
          const fs = (e) => parseFloat(getComputedStyle(e).fontSize);
          const box = document.getElementById('main').getBoundingClientRect(), st = document.getElementById('stage').getBoundingClientRect();
          const inside = (r) => r.left >= box.left - 1 && r.right <= box.right + 1 && r.top >= box.top - 1 && r.bottom <= box.bottom + 1;
          const where = (e) => { const r = e.getBoundingClientRect(); return e.textContent.replace(/\s+/g, ' ') + ' @' + [r.left, r.top, r.right, r.bottom].map(Math.round) + ' board ' + [box.left, box.top, box.right, box.bottom].map(Math.round); };
          const out = { name: [], cat: [], small: [], en: [], pr: [], cut: [], n: 0,
                        stage: [Math.round(st.left), Math.round(st.top), Math.round(st.width), Math.round(st.height)] };
          document.querySelectorAll('#main .page').forEach((p) => {
            p.querySelectorAll('.it').forEach((it) => {
              out.n++;
              const l1 = it.querySelector('.l1');
              out.name.push(cap(it.querySelector('.es')));
              if (it.querySelector('.en')) out.en.push(fs(it.querySelector('.en')) / fs(l1));
              if (it.querySelector('.pr')) out.pr.push(fs(it.querySelector('.pr')) / fs(l1));
              if (!inside(it.getBoundingClientRect())) out.cut.push(where(it));
            });
            p.querySelectorAll('h2').forEach((h2) => {
              const ces = h2.querySelector('.ces');
              (ces.style.fontSize ? out.small : out.cat).push(cap(ces));   /* a title made smaller to fit its column */
              if (!inside(h2.getBoundingClientRect()) || h2.scrollWidth > h2.clientWidth + 1) out.cut.push(where(h2));
            });
          });
          return out;
        });
        const i = await info(pg);
        const pxCm = Math.max(w, h) / LARGO_CM(55);
        const nameCm = Math.min(...m.name) / pxCm, tol = 1 / pxCm;   /* a capital is drawn to the whole pixel (font hinting) */
        assert.strictEqual(m.n, want, `${where}: every item once`);
        assert.deepStrictEqual(m.stage, [0, 0, w, h], `${where}: the turned stage covers the screen`);
        assert.ok(nameCm >= 0.8 * 3 - tol, `${where}: capital of the names ${nameCm.toFixed(2)} cm at 3 m (minimum 2.4)`);
        assert.ok(Math.max(...m.name) / pxCm <= 1.25 * 3 + tol, `${where}: never bigger than 1.25 cm per metre`);
        assert.ok(Math.abs(nameCm - i.capCm) <= tol + 0.02, `${where}: the measured capital ${nameCm.toFixed(2)} cm is the one chosen (${i.capCm})`);
        assert.ok(m.cat.length > m.small.length && Math.min(...m.cat) >= 1.5 * Math.max(...m.name) * 0.95, `${where}: category titles 1.5× the names`);
        assert.ok(!m.small.length || Math.min(...m.small) >= 1.25 * Math.max(...m.name) * 0.95, `${where}: a title with a word too long for its column, never under 1.25×`);
        assert.ok(m.en.length > 5 && Math.min(...m.en) >= 0.749, `${where}: English at least 75 % of the Spanish`);
        assert.ok(m.pr.length === want && Math.min(...m.pr) >= 1, `${where}: prices as big as the names`);
        assert.deepStrictEqual(m.cut, [], `${where}: nothing cut off or outside the board`);
        assert.strictEqual(i.cabe, true, `${where}: every page fits`);
        assert.ok((giro === 'no' ? [2, 3, 4, 5] : [1, 2]).includes(i.columnas), `${where}: ${i.columnas} columns for the orientation`);
        /* a category is cut only when it is taller than a whole column, and its parts follow each other (v2: the next column, which may be on the same page) */
        const seen = {}; i.partes.forEach((pgParts, k) => pgParts.forEach((p) => { (seen[p.categoria] = seen[p.categoria] || []).push(k); }));
        Object.keys(seen).forEach((c) => {
          const ks = seen[c]; assert.ok(ks.every((k, j) => j === 0 || k === ks[j - 1] || k === ks[j - 1] + 1), `${where}: ${c} on consecutive pages`);
        });
        assert.strictEqual(await pg.evaluate(() => document.getElementById('pag').textContent), i.paginas > 1 ? `1/${i.paginas}` : '', `${where}: page number`);
        assert.deepStrictEqual(pg.errors, [], where);
        await pg.context().close();
      }
    }
  },
  {
    name: 'A3: a sold-out item leaves the screen and a new price shows on the next read, by themselves; an item back in stock returns',
    run: async ({ browser }) => {
      const pg = await pantalla(browser, { test: { cada: 1000 } });
      assert.ok(await find(pg, 'Latte'));
      sql(`update menu_items set available = false where name = 'Latte'; update menu_items set price_crc = 1600 where name = 'Americano';`);
      await until(async () => !(await find(pg, 'Latte')), 8000, 'the sold-out Latte left the screen');
      await until(async () => digits((await find(pg, 'Americano')).pr) === 1600, 8000, 'the new price of the Americano');
      sql(`update menu_items set available = true where name = 'Latte'`);
      await until(async () => !!(await find(pg, 'Latte')), 8000, 'the Latte back');
      assert.ok(onlyReads(pg));
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'A4: without a connection the prices stay only while recent (counted from the start of the last good read), then «Precios por confirmar en caja» no later than the limit, then no price at all; they come back by themselves',
    run: async ({ browser, setOffline }) => {
      const T = { cada: 400, fresco: 2500, vencido: 5000, revisar: 150 };
      const pg = await pantalla(browser, { test: T });
      const i0 = await info(pg);
      setOffline(true);
      const t0 = Date.now();
      await until(async () => (await info(pg)).estado === 'por-confirmar', 8000, '«por confirmar»');
      const dt = Date.now() - t0;
      let i = await info(pg);
      /* the last good read started at most one read interval (and a tick) before the connection went */
      assert.ok(dt >= T.fresco - T.cada - 600, `prices count as verified up to the limit (${dt} ms)`);
      assert.ok(dt <= T.fresco + 1500, `«por confirmar» no later than the limit (${dt} ms)`);
      assert.ok(i.edadMs > T.fresco && i.edadMs <= T.vencido, 'the age that decided it: ' + i.edadMs);
      assert.deepStrictEqual([i.paginas, i.capCm, i.partes], [i0.paginas, i0.capCm, i0.partes], 'the warning moves nothing: same pages, same letter');
      assert.ok(await pg.evaluate(() => { const a = document.getElementById('aviso'); return a.scrollWidth <= a.clientWidth + 1 && a.getBoundingClientRect().bottom <= document.querySelector('header').getBoundingClientRect().bottom + 1; }),
        'the warning fits its place');
      assert.strictEqual(await aviso(pg), 'Precios por confirmar en caja Please confirm prices at the counter');
      assert.ok(items(await contenido(pg)).every((g) => digits(g.pr) > 0), 'the prices stay, marked to be confirmed');
      await until(async () => (await info(pg)).estado === 'sin-verificar', 8000, 'no verified prices');
      assert.ok(Date.now() - t0 <= T.vencido + 1500, 'no price no later than the limit');
      i = await info(pg);
      assert.ok(i.edadMs > T.vencido);
      const got = items(await contenido(pg));
      assert.ok(got.length > 30 && got.every((g) => g.pr === ''), 'the names stay, without a single price');
      assert.strictEqual(await pg.locator('#stage .pr').count(), 0, 'no price in the page at all');
      assert.ok(!/₡/.test(await stageText(pg)), 'no ₡ anywhere on the screen');
      assert.strictEqual(await aviso(pg), 'Consulte los precios en la caja Please ask for prices at the counter');
      assert.ok(await pg.evaluate(() => document.getElementById('nota').hidden), 'no note about prices without prices');
      setOffline(false);
      await until(async () => (await info(pg)).estado === 'al-dia', 8000, 'the prices verified again');
      assert.ok(items(await contenido(pg)).every((g) => digits(g.pr) > 0));
      assert.strictEqual(await aviso(pg), '');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'A5: a TV that slept or whose clock jumped: old prices never pass for current (the larger of the two clocks counts)',
    run: async ({ browser, setOffline }) => {
      const pg = await pantalla(browser, { test: { cada: 600000, revisar: 150 } });
      setOffline(true);
      /* asleep: the clock that never moves did not count the sleep, the wall clock did */
      await pg.evaluate(() => { const p = performance.now(); performance.now = () => p; const real = Date.now; Date.now = () => real() + 11 * 60000; });
      await until(async () => (await info(pg)).estado === 'sin-verificar', 5000, 'old prices after the sleep');
      assert.strictEqual(await pg.locator('#stage .pr').count(), 0);
      assert.deepStrictEqual(pg.errors, []);
      await pg.context().close();
      /* a wall clock moved back does not make prices younger: the clock that never moves still counts */
      setOffline(false);
      const pg2 = await pantalla(browser, { test: { cada: 600000, revisar: 150, fresco: 1500, vencido: 3000 } });
      setOffline(true);
      await pg2.evaluate(() => { const real = Date.now; Date.now = () => real() - 86400000; });
      await until(async () => (await info(pg2)).estado === 'sin-verificar', 8000, 'old prices with the clock moved back');
      assert.strictEqual(await pg2.locator('#stage .pr').count(), 0);
      await sleep(3500);
      assert.ok((await info(pg2)).edadMs > 3000, 'the monotonic clock still counts the age');
      assert.strictEqual(await pg2.locator('#stage .pr').count(), 0);
      assert.deepStrictEqual(pg2.errors, []);
    }
  },
  {
    name: 'A6: starting without a connection: the names of this TV\'s last copy and «Consulte los precios en la caja», never a price; no copy (or a copy older than 3 days): a welcome screen',
    run: async ({ browser, setOffline }) => {
      const ctx = await browser.newContext({ viewport: { width: 1920, height: 1080 }, locale: 'es-CR', timezoneId: 'America/Costa_Rica' });
      const pg = await pantalla(browser, { context: ctx });
      const n = items(await contenido(pg)).length;
      await pg.close();
      setOffline(true);
      const off = await pantalla(browser, { context: ctx, wait: false, test: { cada: 500, revisar: 150 } });
      await until(async () => off.evaluate(() => !!window.PANTALLA && PANTALLA.info().deCopia && PANTALLA.info().paginas > 0), 8000, 'the names from the copy');
      const got = items(await contenido(off));
      assert.strictEqual(got.length, n, 'the same names');
      assert.ok(got.every((g) => g.pr === '') && !/₡/.test(await stageText(off)), 'no price');
      assert.strictEqual(await aviso(off), 'Consulte los precios en la caja Please ask for prices at the counter');
      setOffline(false);
      await until(async () => (await info(off)).estado === 'al-dia', 8000, 'prices once the connection is back');
      assert.ok(items(await contenido(off)).every((g) => digits(g.pr) > 0));
      /* offline first, and a read in flight given time to end: no new read can write a fresh copy after the back-dating */
      setOffline(true);
      await sleep(1200);
      await off.evaluate(() => { const v = JSON.parse(localStorage.getItem('hg-pantalla-menu')); v.at = Date.now() - 4 * 86400000; localStorage.setItem('hg-pantalla-menu', JSON.stringify(v)); });
      await off.close();
      for (const c of [ctx, null]) {
        const pg2 = await pantalla(browser, { context: c || undefined, wait: false });
        await until(() => pg2.evaluate(() => !!window.PANTALLA && !document.getElementById('vacio').hidden), 8000, 'the welcome screen');
        const t = await stageText(pg2);
        assert.ok(/Consulte el menú y los precios en la caja/.test(t) && /Please ask for the menu and prices at the counter/.test(t), t);
        assert.ok(!/₡/.test(t));
        assert.strictEqual(await pg2.locator('#main .page').count(), 0);
        assert.deepStrictEqual(pg2.errors, []);
      }
    }
  },
  {
    name: 'A7: the Spanish names column missing in the database (menu-spanish.sql not applied): the menu still shows, Spanish from the dictionary',
    run: async ({ browser }) => {
      sql(`alter table menu_items drop column if exists description_es; alter table menu_items drop column if exists name_es; notify pgrst, 'reload schema';`);
      const pg = await pantalla(browser);
      const got = items(await contenido(pg));
      assert.strictEqual(got.length, JSON.parse(sql(EXPECTED.replace("'name_es', i.name_es, ", ''))).length);
      assert.ok(got.some((g) => g.es === 'Capuchino' && g.en === 'Cappuccino'));
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'A8: after a release the screen reloads by itself, with its settings and without a notice to the guests',
    run: async ({ browser, setRelease }) => {
      setRelease({ served: 'b1', published: 'b2' });
      const pg = await pantalla(browser, { q: '?tv=menu-1&pulgadas=65&distancia=4' });
      assert.strictEqual(await pg.evaluate(() => HG_VERSION.build), 'b1');
      await pg.evaluate(async () => { HG_VERSION.quietMs = 0; await HG_VERSION.check(); });
      assert.strictEqual(await pg.evaluate(() => HG_VERSION.pending), 'b2');
      assert.ok(!/new version|nueva versión/i.test(await pg.evaluate(() => document.body.innerText)), 'no notice on the screen');
      await until(async () => pg.evaluate(() => { try { return HG_VERSION.tick(); } catch (e) { return false; } }).catch(() => true), 10000, 'the reload');
      await until(() => pg.evaluate(() => !!window.HG_VERSION && HG_VERSION.build === 'b2' && !!window.PANTALLA && PANTALLA.info().estado === 'al-dia'), 15000, 'the new version running');
      const q = await pg.evaluate(() => location.search);
      assert.ok(/tv=menu-1/.test(q) && /pulgadas=65/.test(q) && /distancia=4/.test(q), 'the TV keeps its settings: ' + q);
      assert.strictEqual((await info(pg)).ajustes.pulgadas, 65);
    }
  },
  {
    name: 'A9: the technician\'s settings: look by day or night, diagnosis box, wrong values fall back and are named',
    run: async ({ browser }) => {
      let pg = await pantalla(browser, { q: '?tv=menu-1&pulgadas=55&distancia=3&look=dia' });
      assert.ok(await pg.evaluate(() => document.getElementById('stage').classList.contains('dia')));
      assert.ok(await pg.evaluate(() => document.getElementById('diag').hidden), 'no diagnosis box for the guests');
      await pg.context().close();
      pg = await pantalla(browser, { q: '?tv=menu-1&pulgadas=55&distancia=3&look=noche' });
      assert.ok(!(await pg.evaluate(() => document.getElementById('stage').classList.contains('dia'))));
      await pg.context().close();
      pg = await pantalla(browser, { q: '?tv=menu-1&pulgadas=abc&distancia=40&giro=arriba&diag=1' });
      const d = await diag(pg);
      assert.ok(/menu-1/.test(d) && /55" · 3 m/.test(d) && /mayúscula \d+\.\d\d cm \(mínimo 2\.40, meta 3\.00\)/.test(d), d);
      assert.ok(/Ajustes no válidos: pulgadas=abc, distancia=40, giro=arriba/.test(d), d);
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'B1: the TV\'s row (pantallas, migration 0036) sets it up: size, distance, turn, scale and page time change the letter and the layout; a change shows by itself on the next read; a cold start without internet keeps the last settings, never a price',
    run: async ({ browser, setOffline }) => {
      sql(`update public.screens set inches = 65, distance_m = 4, turn = 'derecha', scale_pct = 110, page_seconds = 17 where id = 'menu-1'`);
      const ctx = await browser.newContext({ viewport: { width: 1920, height: 1080 }, locale: 'es-CR', timezoneId: 'America/Costa_Rica' });
      const pg = await pantalla(browser, { context: ctx, q: '?tv=menu-1&diag=1', test: { cada: 1000 } });
      const check = async (pulgadas, distancia, giro, escala, paginaMs) => {
        const i = await info(pg), where = `${pulgadas}" ${distancia} m giro ${giro}`;
        assert.strictEqual(i.fuente, 'base', where);
        assert.deepStrictEqual([i.ajustes.pulgadas, i.ajustes.distancia, i.ajustes.giro, i.ajustes.escala, i.paginaMs], [pulgadas, distancia, giro, escala, paginaMs], where);
        assert.ok(Math.abs(i.minCm - 0.8 * distancia * escala / 100) < 1e-9 && Math.abs(i.metaCm - distancia * escala / 100) < 1e-9, `${where}: the letter follows distance and scale`);
        assert.ok((giro === 'no' ? [2, 3, 4, 5] : [1, 2]).includes(i.columnas), `${where}: ${i.columnas} columns`);
        const st = await pg.evaluate(() => { const s = document.getElementById('stage'); return [s.offsetWidth, s.offsetHeight, s.style.transform]; });
        assert.deepStrictEqual(st, giro === 'no' ? [1920, 1080, ''] : [1080, 1920, 'translate(1920px, 0px) rotate(90deg)'], `${where}: the stage`);
        const c = await capitales(pg), pxCm = 1920 / LARGO_CM(pulgadas), tol = 1 / pxCm;
        assert.ok(c.min / pxCm >= i.minCm - tol && Math.abs(c.min / pxCm - i.capCm) <= tol + 0.02, `${where}: the capital drawn ${(c.min / pxCm).toFixed(2)} cm is the one chosen (${i.capCm}, minimum ${i.minCm})`);
        assert.strictEqual(i.cabe, true, where);
        return i;
      };
      await check(65, 4, 'derecha', 110, 17000);
      assert.deepStrictEqual((await info(pg)).origen, { pulgadas: 'base', distancia: 'base', escala: 'base', pagina: 'base', promo_cada: 'base', promo_seg: 'base', giro: 'base', look: 'base', densidad: 'base', ingles: 'base', layout: 'base', promo: 'base' });
      let d = await diag(pg);
      assert.ok(/Origen: base de datos \(TV menu-1/.test(d) && /65" · 4 m/.test(d) && /17 s cada una/.test(d), d);
      /* the owner changes it in pantallas: the screen follows on its next read */
      sql(`update public.screens set inches = 50, distance_m = 2, turn = 'no', page_seconds = 40 where id = 'menu-1'`);
      await until(async () => { const j = await info(pg); return j.ajustes.giro === 'no' && j.ajustes.distancia === 2 && j.paginaMs === 40000; }, 8000, 'the new settings');
      await check(50, 2, 'no', 110, 40000);
      assert.ok(onlyReads(pg));
      assert.deepStrictEqual(pg.errors, []);
      await pg.close();
      /* a cold start without internet: the settings this TV kept (no price in them), the names without prices */
      setOffline(true);
      const off = await pantalla(browser, { context: ctx, q: '?tv=menu-1&diag=1', wait: false, test: { cada: 500 } });
      await until(() => off.evaluate(() => !!window.PANTALLA && PANTALLA.info().paginas > 0), 8000, 'the names from the copy');
      const j = await info(off);
      assert.deepStrictEqual([j.fuente, j.estado, j.ajustes.pulgadas, j.ajustes.distancia, j.ajustes.giro, j.paginaMs], ['copia', 'sin-verificar', 50, 2, 'no', 40000]);
      assert.strictEqual(await off.locator('#stage .pr').count(), 0);
      d = await diag(off);
      assert.ok(/Origen: copia del aparato/.test(d), d);
      const kept = JSON.parse(await off.evaluate(() => localStorage.getItem('hg-pantalla-menu-tv')));
      assert.strictEqual(kept.tv, 'menu-1');
      assert.ok(Object.keys(kept.fila).every((k) => CAMPOS_FILA.includes(k)), Object.keys(kept.fila).join());
      assert.deepStrictEqual(off.errors, []);
    }
  },
  {
    name: 'B2: the address still overrides the TV\'s row, setting by setting, so a technician can correct one TV; the diagnosis says where each comes from',
    run: async ({ browser }) => {
      sql(`update public.screens set inches = 65, distance_m = 4, turn = 'derecha', scale_pct = 120, look = 'noche', page_seconds = 17 where id = 'menu-1'`);
      const pg = await pantalla(browser, { q: '?tv=menu-1&distancia=2&giro=no&look=dia&pagina=20&escala=90&diag=1' });
      const i = await info(pg);
      assert.deepStrictEqual([i.ajustes.pulgadas, i.ajustes.distancia, i.ajustes.giro, i.ajustes.look, i.ajustes.escala, i.paginaMs], [65, 2, 'no', 'dia', 90, 20000]);
      assert.deepStrictEqual(i.origen, { pulgadas: 'base', distancia: 'direccion', escala: 'direccion', pagina: 'direccion', promo_cada: 'base', promo_seg: 'base', giro: 'direccion', look: 'direccion', densidad: 'base', ingles: 'base', layout: 'base', promo: 'base' });
      assert.ok(Math.abs(i.minCm - 0.8 * 2 * 0.9) < 1e-9);
      assert.ok(await pg.evaluate(() => document.getElementById('stage').classList.contains('dia')), 'look from the address');
      assert.strictEqual(await pg.evaluate(() => document.getElementById('stage').style.transform), '', 'not turned: the address said no');
      const d = await diag(pg);
      assert.ok(/Origen: base de datos \(TV menu-1.* · de la dirección: distancia, escala, pagina, giro, look/.test(d) && /65" · 2 m/.test(d), d);
      assert.ok(onlyReads(pg));
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'B3: an unknown TV or the database without migration 0036: the screen works exactly as before, from its address and the defaults; a TV switched off in pantallas goes black until switched on again; the diagnosis says why',
    run: async ({ browser }) => {
      const want = JSON.parse(sql(EXPECTED)).length;
      let pg = await pantalla(browser, { q: '?tv=menu-9&diag=1' });
      let i = await info(pg);
      assert.deepStrictEqual([i.fuente, i.razon, i.ajustes.pulgadas, i.ajustes.distancia, i.ajustes.supuesto, i.horaDe], ['direccion', 'tv-desconocida', 55, 3, true, 'servidor']);
      assert.ok(/Origen: dirección y valores por omisión \(la TV «menu-9» no existe/.test(await diag(pg)));
      assert.strictEqual(items(await contenido(pg)).length, want);
      assert.ok(onlyReads(pg));
      assert.deepStrictEqual(pg.errors, []);
      await pg.context().close();
      /* the owner switched menu-1 off in pantallas: the screen goes black (no text, no price) until it is switched on again */
      sql(`update public.screens set active = false, distance_m = 5 where id = 'menu-1'`);
      pg = await pantalla(browser, { q: '?tv=menu-1&pulgadas=50&diag=1', wait: false, test: { cada: 600 } });
      await until(async () => (await info(pg)).razon === 'tv-apagada', 8000, 'switched off');
      i = await info(pg);
      assert.deepStrictEqual([i.apagado, i.paginas, i.razon], [true, 0, 'tv-apagada']);
      assert.strictEqual(await pg.locator('#stage .pr').count(), 0, 'no price on a switched-off TV');
      assert.deepStrictEqual(await pg.evaluate(() => [localStorage.getItem('hg-pantalla-menu'), localStorage.getItem('hg-pantalla-menu-tv')]), [null, null],
        'and the device forgets its copies: a reboot without network stays black or shows the welcome, never the menu');
      await until(async () => /apagada en Pantallas/i.test(await diag(pg)), 4000, 'the diagnosis says the TV is switched off');
      sql(`update public.screens set active = true where id = 'menu-1'`);
      await until(async () => { const j = await info(pg); return !j.apagado && j.paginas > 0 && j.estado === 'al-dia'; }, 8000, 'switched on again: the menu is back');
      assert.strictEqual((await info(pg)).ajustes.distancia, 5, 'with its settings from the database');
      assert.deepStrictEqual(pg.errors, []);
      await pg.context().close();
      /* without the migration: the function is missing (404); prices, layout and reads as the prototype */
      await sinFuncion();
      pg = await pantalla(browser, { q: '?tv=menu-1&pulgadas=50&distancia=2&diag=1', test: { cada: 1000 } });
      i = await info(pg);
      assert.deepStrictEqual([i.fuente, i.razon, i.ajustes.pulgadas, i.ajustes.distancia, i.horaDe], ['direccion', 'sin-funcion', 50, 2, 'aparato']);
      assert.ok(/falta la migración 0036/.test(await diag(pg)), await diag(pg));
      assert.strictEqual(items(await contenido(pg)).length, want);
      sql(`update menu_items set price_crc = 1550 where name = 'Americano'`);
      await until(async () => digits((await find(pg, 'Americano')).pr) === 1550, 8000, 'still in sync without the migration');
      assert.ok(onlyReads(pg));
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'B4: the TV\'s categories: only those, in the Menu Manager order; one that no longer exists is skipped; if none exists any more, all of them, and the diagnosis says so',
    run: async ({ browser }) => {
      sql(`update public.screens set category_ids = '{${CAT.pastries},${CAT.coffee}}' where id = 'menu-1'`);
      const pg = await pantalla(browser, { q: '?tv=menu-1&pulgadas=55&distancia=3&diag=1', test: { cada: 1000 } });
      const only = JSON.parse(sql(EXPECTED + ` and c.id in ('${CAT.coffee}', '${CAT.pastries}')`));
      let pages = await contenido(pg);
      assert.deepStrictEqual(cats(pages), ['coffee', 'pastries & cake'], 'the chosen categories, in the Menu Manager order');
      assert.strictEqual(items(pages).length, only.length);
      assert.strictEqual((await info(pg)).categorias, 'elegidas');
      sql(`update public.screens set category_ids = '{${CAT.pastries},${CAT.gone}}' where id = 'menu-1'`);
      await until(async () => { const c = cats(await contenido(pg)); return c.length === 1 && c[0] === 'pastries & cake'; }, 8000, 'only the pastries');
      assert.ok(/categorías elegidas \(1 ya no existen\)/.test(await diag(pg)), await diag(pg));
      /* none of them on the screen any more (a deleted one, and the till's helpers, which never show) */
      sql(`update public.screens set category_ids = '{${CAT.gone},${CAT.extras}}' where id = 'menu-1'`);
      const want = JSON.parse(sql(EXPECTED));
      await until(async () => items(await contenido(pg)).length === want.length, 8000, 'every category');
      assert.strictEqual((await info(pg)).categorias, 'no-existen');
      assert.ok(/TODAS: las categorías elegidas ya no existen/.test(await diag(pg)));
      assert.ok(!/Combo|Flavor shot|Add ham|Extras/i.test(await stageText(pg)));
      sql(`update public.screens set category_ids = null where id = 'menu-1'`);
      await until(async () => (await info(pg)).categorias === 'todas', 8000, 'all, chosen by nobody');
      pages = await contenido(pg);
      assert.deepStrictEqual(cats(pages), [...new Set(want.map((w) => clave(w.cat)))]);
      assert.ok(onlyReads(pg));
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'B5: sold-out items struck through («tachar»): still listed, crossed out, «Agotado · Sold out», never a price; back in stock with its price; «ocultar» hides them; the device copy never lists them',
    run: async ({ browser }) => {
      sql(`update public.screens set sold_out = 'tachar' where id = 'menu-1';
           update menu_items set available = false where name in ('Latte', 'Carrot Cake', 'Flavor shot');
           update menu_items set available = false, price_crc = 0 where name = 'Sweet Cane Drink';`);
      const pg = await pantalla(browser, { test: { cada: 1000 } });
      const want = JSON.parse(sql(EXPECTED));
      let got = items(await contenido(pg));
      assert.strictEqual(got.length, want.length + 2, 'the available items and the two sold out');
      for (const name of ['Latte', 'Carrot Cake']) {
        const g = got.find((x) => x.es === name || x.en === name);
        assert.ok(g && g.ago && g.tag === 'Agotado · Sold out' && g.pr === '' && /line-through/.test(g.strike), name + ': ' + JSON.stringify(g));
      }
      assert.ok(got.filter((g) => !g.ago).every((g) => digits(g.pr) > 0 && g.tag === '' && !/line-through/.test(g.strike)), 'the others with their prices, not struck');
      assert.ok(!got.some((g) => /Sweet Cane|Agua dulce/.test(g.es + ' ' + g.en)), 'an item without a price never shows, sold out or not');
      assert.ok(!/Flavor shot|Combo|Extras/i.test(await stageText(pg)), 'never Extras & Combos');
      const raw = await pg.evaluate(() => localStorage.getItem('hg-pantalla-menu'));
      const names = JSON.parse(raw).cats.flatMap((c) => c.items).flatMap((it) => [it.es, it.en]);
      assert.ok(!names.includes('Latte') && !names.includes('Carrot Cake') && !/agotado|sold/i.test(raw), 'the copy holds the available names only');
      sql(`update menu_items set available = true where name = 'Latte'`);
      await until(async () => { const g = await find(pg, 'Latte'); return g && !g.ago && digits(g.pr) === 2200; }, 8000, 'the Latte back with its price');
      sql(`update public.screens set sold_out = 'ocultar' where id = 'menu-1'`);
      await until(async () => !(await find(pg, 'Carrot Cake')), 8000, 'hidden, as the owner chose');
      got = items(await contenido(pg));
      assert.ok(got.length === want.length + 1 && got.every((g) => !g.ago && digits(g.pr) > 0));
      assert.ok(onlyReads(pg));
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'B6: the TV\'s hours (Costa Rica): outside them the screen is black, no text, no price; overnight hours work; the server\'s clock decides, not the device\'s',
    run: async ({ browser }) => {
      const now = crMin(Date.now());
      const hours = (a, b) => sql(`update public.screens set on_from = '${hhmm(a)}', on_to = '${hhmm(b)}' where id = 'menu-1'`);
      const negro = (pg) => pg.evaluate(() => ({ text: document.body.innerText.trim(), nodes: document.querySelectorAll('#stage .pr, #main .page').length,
                                                 bg: getComputedStyle(document.body).backgroundColor, stage: getComputedStyle(document.getElementById('stage')).backgroundColor }));
      const BLACK = { text: '', nodes: 0, bg: 'rgb(0, 0, 0)', stage: 'rgb(0, 0, 0)' };
      hours(now - 60, now + 60);
      const pg = await pantalla(browser, { test: { cada: 1000, revisar: 200 } });
      assert.ok(!(await info(pg)).apagado && (await pg.locator('#stage .pr').count()) > 30, 'inside its hours: the menu with prices');
      hours(now + 60, now + 120);
      await until(async () => (await info(pg)).apagado, 8000, 'outside its hours');
      assert.deepStrictEqual(await negro(pg), BLACK, 'a black screen');
      hours(now - 60, now - 120);                                /* from > to (unless it wraps the other way): open now */
      await until(async () => { const i = await info(pg); return !i.apagado && i.estado === 'al-dia'; }, 8000, 'on again');
      assert.ok((await pg.locator('#stage .pr').count()) > 30);
      hours(now + 60, now - 60);                                 /* overnight, closed now */
      await until(async () => (await info(pg)).apagado, 8000, 'off again');
      assert.deepStrictEqual(await negro(pg), BLACK);
      assert.deepStrictEqual(pg.errors, []);
      await pg.context().close();
      /* 20:00 to 02:00 by the server's clock; the device's clock is 12 hours off and does not count */
      sql(`update public.screens set on_from = '20:00', on_to = '02:00' where id = 'menu-1'`);
      let base = Date.UTC(2026, 9, 31, 5, 30), t0 = Date.now();   /* 23:30 in Costa Rica */
      const pg2 = await pantalla(browser, { q: '?tv=menu-1&diag=1', test: { cada: 1000, revisar: 200 }, reloj: Date.now() + 12 * 3600000,
                                            setup: relojServidor(() => base + Date.now() - t0) });
      let i = await info(pg2);
      assert.deepStrictEqual([i.apagado, i.horaDe, i.horaCR.slice(0, 4)], [false, 'servidor', '23:3'], 'open at 23:30');
      base = Date.UTC(2026, 9, 31, 9, 0); t0 = Date.now();          /* 03:00 */
      await until(async () => (await info(pg2)).apagado, 8000, 'closed at 03:00');
      assert.ok(/Horario: 20:00–02:00 · APAGADA/.test(await diag(pg2)), await diag(pg2));
      assert.ok(await pg2.evaluate(() => document.body.innerText.trim() === document.getElementById('diag').innerText.trim()), 'nothing but the technician\'s box (diag=1)');
      assert.strictEqual(await pg2.locator('#stage .pr').count(), 0);
      base = Date.UTC(2026, 9, 31, 7, 59); t0 = Date.now();         /* 01:59 */
      await until(async () => { const j = await info(pg2); return !j.apagado && j.estado === 'al-dia'; }, 8000, 'open at 01:59');
      assert.ok(onlyReads(pg2));
      assert.deepStrictEqual(pg2.errors, []);
    }
  },
  {
    name: 'B7: look «auto» by Costa Rica\'s time (bright 6:00-18:00) from the server\'s clock, or the device\'s clock when there is none, never the device\'s time zone',
    run: async ({ browser }) => {
      const tokyo = () => browser.newContext({ viewport: { width: 1920, height: 1080 }, locale: 'es-CR', timezoneId: 'Asia/Tokyo' });
      const dia = (pg) => pg.evaluate(() => document.getElementById('stage').classList.contains('dia'));
      let base = Date.UTC(2026, 9, 31, 16, 0), t0 = Date.now();   /* 10:00 in Costa Rica, 01:00 in Tokyo */
      const pg = await pantalla(browser, { context: await tokyo(), test: { cada: 1000 }, setup: relojServidor(() => base + Date.now() - t0) });
      assert.strictEqual(await pg.evaluate(() => Intl.DateTimeFormat().resolvedOptions().timeZone), 'Asia/Tokyo');
      let i = await info(pg);
      assert.deepStrictEqual([i.horaDe, i.horaCR.slice(0, 4), i.ajustes.look, i.look, await dia(pg)], ['servidor', '10:0', 'auto', 'dia', true]);
      base = Date.UTC(2026, 10, 1, 4, 0); t0 = Date.now();          /* 22:00 in Costa Rica, 13:00 in Tokyo */
      await until(async () => (await info(pg)).look === 'noche', 8000, 'night by Costa Rica\'s time');
      assert.strictEqual(await dia(pg), false);
      assert.deepStrictEqual(pg.errors, []);
      await pg.context().close();
      /* no server time (the migration not applied): the device's clock, read as Costa Rica's time */
      await sinFuncion();
      for (const [ms, look] of [[Date.UTC(2026, 9, 31, 16, 0), 'dia'], [Date.UTC(2026, 10, 1, 4, 0), 'noche']]) {
        const p = await pantalla(browser, { context: await tokyo(), reloj: ms });
        i = await info(p);
        assert.deepStrictEqual([i.horaDe, i.razon, i.look, await dia(p)], ['aparato', 'sin-funcion', look, look === 'dia'], look);
        assert.deepStrictEqual(p.errors, []);
        await p.context().close();
      }
    }
  },
  {
    name: 'B8: review fixes: a clock moved back never stops the reads; after a resume, being shown again or a pause in a tick, no price until a read that started after it, and that read happens at once',
    run: async ({ browser, setOffline }) => {
      const pg = await pantalla(browser, { test: { cada: 1000, revisar: 200 } });
      await pg.evaluate(() => { const real = Date.now.bind(Date); Date.now = () => real() - 86400000; });
      sql(`update menu_items set price_crc = 1650 where name = 'Americano'`);
      await until(async () => digits((await find(pg, 'Americano')).pr) === 1650, 10000, 'a new price read with the clock a day back');
      await until(async () => (await info(pg)).estado === 'al-dia', 5000, 'verified with the clock a day back');
      let n = reads(pg, 0);
      await sleep(3000);
      assert.ok(reads(pg, 0) >= n + 2, `the reads go on (${reads(pg, 0) - n} in 3 s)`);
      assert.strictEqual((await info(pg)).estado, 'al-dia');
      /* a wall clock that stopped (no jump to notice): the reads go on by the monotonic clock */
      await pg.evaluate(() => { const t = Date.now(); Date.now = () => t; });
      sql(`update menu_items set price_crc = 1660 where name = 'Americano'`);
      await until(async () => digits((await find(pg, 'Americano')).pr) === 1660, 10000, 'a new price read with the wall clock stopped');
      n = reads(pg, 0);
      await sleep(3000);
      assert.ok(reads(pg, 0) >= n + 2, `the reads go on with the clock stopped (${reads(pg, 0) - n} in 3 s)`);
      assert.strictEqual((await info(pg)).estado, 'al-dia');
      assert.deepStrictEqual(pg.errors, []);
      await pg.context().close();

      const pg2 = await pantalla(browser, { test: { cada: 600000, revisar: 200 } });   /* no read due by itself for 10 min */
      const fire = (ev) => pg2.evaluate((e) => {
        if (e === 'pageshow') window.dispatchEvent(new PageTransitionEvent('pageshow', { persisted: true }));
        else document.dispatchEvent(new Event(e));
      }, ev);
      for (const ev of ['resume', 'visibilitychange', 'pageshow']) {
        setOffline(true);
        await fire(ev);
        let i = await info(pg2);
        assert.ok(i.estado === 'sin-verificar' && i.dudoso && i.edadMs < i.tiempos.fresco, `${ev}: unverified at once, though the age alone would allow prices (${i.edadMs} ms)`);
        assert.strictEqual(await pg2.locator('#stage .pr').count(), 0, ev);
        assert.strictEqual(await aviso(pg2), 'Consulte los precios en la caja Please ask for prices at the counter', ev);
        await sleep(800);
        assert.strictEqual((await info(pg2)).estado, 'sin-verificar', `${ev}: still unverified without a read`);
        setOffline(false);
        const n0 = reads(pg2, 0);
        await fire(ev);
        await until(async () => (await info(pg2)).estado === 'al-dia', 4000, `${ev}: verified by the read it started`);
        assert.ok(reads(pg2, 0) > n0, ev + ': read at once');
        assert.ok((await pg2.locator('#stage .pr').count()) > 30, ev);
      }
      /* a pause seen by a tick: the wall clock moved back an hour (the age by the monotonic clock is still small) */
      setOffline(true);
      await pg2.evaluate(() => { const real = Date.now.bind(Date); Date.now = () => real() - 3600000; });
      await until(async () => { const i = await info(pg2); return i.estado === 'sin-verificar' && i.duda === 'pausa'; }, 4000, 'unverified after the pause');
      assert.ok((await info(pg2)).edadMs < 120000);
      assert.strictEqual(await pg2.locator('#stage .pr').count(), 0);
      setOffline(false);
      await fire('resume');
      await until(async () => (await info(pg2)).estado === 'al-dia', 4000, 'verified again');
      assert.ok(onlyReads(pg2));
      assert.deepStrictEqual(pg2.errors, []);
    }
  },
  {
    name: 'B9: review fixes on a turned TV: a title with a word too long for its column shrinks to fit (never under 1.25×); the header warning is never cut: its letter shrinks to fit (never under 0.4×)',
    run: async ({ browser, setOffline }) => {
      const LONG = 'Desayunosextraordinarios';
      sql(`update menu_categories set name = '${LONG}' where name = 'Savory'`);
      const pg = await pantalla(browser, { q: '?tv=menu-1&pulgadas=55&distancia=3&giro=derecha', test: { cada: 400, fresco: 2500, vencido: 60000, revisar: 150 } });
      const t = await pg.evaluate((long) => {
        const out = [];
        document.querySelectorAll('#main .page h2 .ces').forEach((ces) => {
          if (ces.textContent !== long) return;
          const h2 = ces.parentNode, name = h2.closest('.cat').querySelector('.it .es');
          out.push({ small: ces.style.fontSize, fs: parseFloat(getComputedStyle(ces).fontSize), name: parseFloat(getComputedStyle(name).fontSize),
                     w: ces.offsetWidth, cw: h2.clientWidth, sw: h2.scrollWidth });
        });
        return out;
      }, LONG);
      assert.ok(t.length >= 1, 'the long title is on the screen');
      t.forEach((x) => {
        assert.ok(x.small !== '' && x.fs < 1.5 * x.name - 0.5, 'the title was made smaller: ' + JSON.stringify(x));
        assert.ok(x.w <= x.cw + 1 && x.sw <= x.cw + 1, 'and fits its column: ' + JSON.stringify(x));
        assert.ok(x.fs >= 1.25 * x.name - 0.5, 'never under 1.25× the names: ' + JSON.stringify(x));
      });
      assert.strictEqual((await info(pg)).cabe, true, 'every page fits');
      const avisoCabe = (p) => p.evaluate(() => {
        const av = document.getElementById('aviso'), sm = av.querySelector('small'), hd = document.querySelector('header');
        const f = parseFloat(document.getElementById('stage').style.getPropertyValue('--f'));
        return { fits: av.scrollWidth <= av.clientWidth + 1 && sm.scrollWidth <= sm.clientWidth + 1 && av.offsetTop - hd.offsetTop + av.offsetHeight <= hd.clientHeight + 1,
                 ratio: parseFloat(getComputedStyle(av).fontSize) / f, text: av.innerText.replace(/\s+/g, ' ') };
      });
      setOffline(true);
      await until(async () => (await info(pg)).estado === 'por-confirmar', 8000, '«por confirmar»');
      let a = await avisoCabe(pg);
      assert.ok(a.fits && a.ratio >= 0.4 - 1e-3, 'the warning fits on the turned TV: ' + JSON.stringify(a));
      await pg.context().close();
      /* farther away the letter is bigger and the warning would not fit at its usual size: it shrinks, never cut */
      setOffline(false);
      const pg2 = await pantalla(browser, { q: '?tv=menu-1&pulgadas=55&distancia=5&giro=izquierda', test: { cada: 400, fresco: 1500, vencido: 3500, revisar: 150 } });
      setOffline(true);
      await until(async () => (await info(pg2)).estado === 'por-confirmar', 8000, '«por confirmar» at 5 m');
      a = await avisoCabe(pg2);
      assert.ok(a.fits && a.ratio < 0.66 - 1e-3 && a.ratio >= 0.4 - 1e-3, 'shrunk to fit: ' + JSON.stringify(a));
      await until(async () => (await info(pg2)).estado === 'sin-verificar', 8000, 'no price at 5 m');
      a = await avisoCabe(pg2);
      assert.ok(a.fits && a.ratio >= 0.4 - 1e-3 && /Consulte los precios en la caja/.test(a.text), 'the longer warning fits too: ' + JSON.stringify(a));
      assert.deepStrictEqual(pg2.errors, []);
    }
  },
  {
    name: 'B10: review fixes: a board rebuilt after new data is never blank (no fade through nothing); the letter is measured and laid out again when a web font finishes loading',
    run: async ({ browser }) => {
      const pg = await pantalla(browser, { test: { cada: 1000, pagina: 3600000 } });
      await sleep(800);
      await pg.evaluate(() => {
        window.__blank = 0; window.__frames = 0;
        const f = () => {
          const op = [...document.querySelectorAll('#main .page')].map((p) => Number(getComputedStyle(p).opacity));
          window.__frames++; if (!(Math.max(0, ...op) >= 0.99)) window.__blank++;
          requestAnimationFrame(f);
        };
        requestAnimationFrame(f);
      });
      const m0 = (await info(pg)).maquetas;
      sql(`update menu_items set price_crc = 1700 where name = 'Americano'`);
      await until(async () => digits((await find(pg, 'Americano')).pr) === 1700, 8000, 'the new price');
      await sleep(1000);                                          /* a fade would take 0.6 s */
      const r = await pg.evaluate(() => [window.__blank, window.__frames, document.querySelectorAll('#main .page').length, document.querySelectorAll('#main .page.on').length]);
      const i = await info(pg);
      assert.ok(i.maquetas > m0, 'the board was rebuilt');
      assert.strictEqual(r[0], 0, `never a frame without a visible page (${r[0]} of ${r[1]})`);
      assert.ok(r[1] > 10, 'frames were watched: ' + r[1]);
      assert.deepStrictEqual([r[2], r[3]], [i.paginas, 1], 'the old pages are gone, one page shown');
      /* a web font that finishes loading: measured again and laid out again at once (not at the next 5 s tick) */
      const m1 = (await info(pg)).maquetas;
      await pg.evaluate(() => document.fonts.dispatchEvent(new Event('loadingdone')));
      await until(async () => (await info(pg)).maquetas > m1, 1500, 'laid out again after the font');
      const c = await capitales(pg), j = await info(pg);
      assert.ok(Math.abs(c.min / j.pxPorCm - j.capCm) <= 1 / j.pxPorCm + 0.02, 'the capital drawn is the one chosen');
      assert.ok(onlyReads(pg));
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'B11: review fixes: a read counts from the moment its request started (a slow answer is never fresher than its request); the time limit covers the answer\'s body, so a stalled body never stops the reads',
    run: async ({ browser }) => {
      /* answers that take 1.5 s, with 1 s of «fresh»: the prices never show as current, only to be confirmed */
      const slow = (pg) => pg.route(/\/rest\/v1\/menu_categories/, async (route) => {
        let r; try { r = await route.fetch(); } catch (e) { return route.abort(); }
        await sleep(1500);
        return route.fulfill({ response: r });
      });
      const pg = await pantalla(browser, { wait: false, test: { cada: 400, fresco: 1000, vencido: 20000, revisar: 100 }, setup: slow });
      await until(async () => (await info(pg)).estado === 'por-confirmar', 10000, 'prices, to be confirmed');
      const seen = new Set();
      for (let k = 0; k < 16; k++) {
        const i = await info(pg);
        seen.add(i.estado);
        assert.ok(i.edadMs >= 1400, 'a price is never younger than its answer took: ' + i.edadMs);
        await sleep(150);
      }
      assert.ok(!seen.has('al-dia') && seen.has('por-confirmar'), [...seen].join());
      assert.ok((await pg.locator('#stage .pr').count()) > 30);
      assert.strictEqual(await aviso(pg), 'Precios por confirmar en caja Please confirm prices at the counter');
      assert.deepStrictEqual(pg.errors, []);
      await pg.context().close();
      /* the headers arrive, the body never does: the limit cuts it and the next reads still happen */
      const stall = (p) => p.addInitScript(() => {
        const orig = window.fetch; window.__stall = true;
        window.fetch = function (url, opts) {
          return orig.apply(this, arguments).then((res) => {
            if (!window.__stall || !/menu_categories/.test(String(url))) return res;
            const sig = opts && opts.signal;
            res.json = () => new Promise((ok, no) => { if (sig) sig.addEventListener('abort', () => no(new DOMException('aborted', 'AbortError'))); });
            return res;
          });
        };
      });
      const pg2 = await pantalla(browser, { wait: false, test: { cada: 400, limite: 800, revisar: 100 }, setup: stall });
      await sleep(3500);
      assert.ok(reads(pg2, 0) >= 3, 'each stalled read was cut at the limit and another one followed: ' + reads(pg2, 0));
      assert.strictEqual((await info(pg2)).estado, 'sin-verificar');
      assert.strictEqual(await pg2.locator('#stage .pr').count(), 0);
      await pg2.evaluate(() => { window.__stall = false; });
      await until(async () => (await info(pg2)).estado === 'al-dia', 5000, 'verified once the answers arrive whole');
      assert.ok(onlyReads(pg2));
      assert.deepStrictEqual(pg2.errors, []);
    }
  },
  {
    name: 'B12: v2 board: every category is one block (its title first, then only its items) packed into explicit columns, never a title between another category\'s items and every column starting with a title; a block that does not fit is cut only when both pieces keep two items or more, its title repeated with «(continúa)», else it moves whole; the columns of a page are as even as the cuts allow (the tallest could not give an item to a neighbour and be lower), and nothing overflows',
    run: async ({ browser }) => {
      const want = JSON.parse(sql(EXPECTED));
      for (const [w, h, q] of [[1920, 1080, '?tv=menu-1&pulgadas=55&distancia=3'], [1280, 720, '?tv=menu-1&pulgadas=65&distancia=2.5'], [1920, 1080, '?tv=menu-1&pulgadas=55&distancia=3&giro=derecha']]) {
        const pg = await pantalla(browser, { viewport: { width: w, height: h }, q });
        const i = await info(pg), where = `${w}×${h} ${q}`;
        const cols = await columnas(pg);
        assert.strictEqual(cols.length, i.paginas, where + ': one DOM page per page');
        cols.forEach((p, k) => {
          assert.strictEqual(p.length, i.columnas, `${where}: page ${k + 1} has ${i.columnas} explicit columns`);
          p.forEach((c, j) => {
            assert.ok(c.secciones.every((s) => s.ok), `${where}: page ${k + 1} column ${j + 1}: a title first, then only that category's items: ${JSON.stringify(c.secciones)}`);
            assert.ok(c.secciones.every((s, n) => n === 0 || s.top >= c.secciones[n - 1].bottom - 1), `${where}: the blocks follow each other down the column`);
            assert.ok(c.scroll <= c.alto + 1 && c.secciones.every((s) => s.bottom <= c.alto + 1), `${where}: page ${k + 1} column ${j + 1} holds its blocks (${c.scroll} in ${c.alto})`);
          });
        });
        /* the Menu Manager's order, column after column and page after page; every item once */
        const pages = await contenido(pg);
        assert.deepStrictEqual(cats(pages), [...new Set(want.map((x) => clave(x.cat)))], where);
        assert.strictEqual(items(pages).length, want.length, where);
        /* even: on every page the columns end under the page's top (the tallest column), a cut leaves two items or more on
           each side, the shortest column is within one piece of the tallest (a block kept whole moves only whole), and
           the one tallest column cannot give an item across a cut to a neighbour and be lower (the deal of each page is
           the lowest tallest column first, then the least empty board: the page's own engine, checked here from outside) */
        const g = i.maqueta.gap, H = i.maqueta.alto;
        const piezas = []; i.maqueta.paginas.forEach((p, k) => p.forEach((c, j) => c.bloques.forEach((b, n) => piezas.push({ k, j, n, b, lim: c.limite }))));
        i.maqueta.paginas.forEach((p, k) => {
          const lim = p[0].limite, tope = p[0].tope, usadas = p.filter((c) => c.bloques.length), alturas = usadas.map((c) => c.alto);
          assert.ok(lim <= tope + 0.5 && tope <= H + 0.5 && usadas.length, `${where}: page ${k + 1}: limit ${lim} and top ${tope} within the board ${H}`);
          /* every column under the top, the tallest at it; a column over the balancing limit holds exactly one piece: a block (or
             what was left of a cut one) that fits the real column and was placed whole rather than in pieces */
          assert.ok(alturas.every((a) => a <= tope + 0.5) && Math.max(...alturas) >= tope - 1, `${where}: page ${k + 1}: columns ${alturas} under the top ${tope}, the tallest at it`);
          usadas.forEach((c, j) => { if (c.alto > lim + 0.5) assert.ok(c.bloques.length === 1, `${where}: page ${k + 1} column ${j + 1} over the limit ${lim} with more than one piece: ${JSON.stringify(c.bloques.map((b) => b.categoria))}`); });
          let unidad = 0, item = 0;
          p.forEach((c, j) => {
            c.bloques.forEach((b, n) => {
              const cut = b.desde > 0 || b.hasta < b.n;
              if (cut && b.hasta - b.desde < 2) {
                /* a piece of one item only when the block is taller than a column: it opens its column and one more item would not fit */
                const at = piezas.findIndex((x) => x.k === k && x.j === j && x.n === n), sig = piezas[at + 1];
                assert.ok(n === 0, `${where}: page ${k + 1} column ${j + 1}: a piece of one item of «${b.categoria}» in the middle of a column: ${JSON.stringify(b)}`);
                if (b.hasta < b.n) {
                  assert.ok(sig && sig.b.categoria === b.categoria && sig.b.desde === b.hasta, `${where}: page ${k + 1} column ${j + 1}: the continuation of «${b.categoria}» follows`);
                  /* one more item would not have fit; or the block has three and the cut keeps two for the continuation (a lone item never follows a repeated title) */
                  assert.ok(b.alto + sig.b.alturas[0] + 1 > lim - 0.5 || (b.n === 3 && sig.b.hasta - sig.b.desde === 2),
                    `${where}: page ${k + 1} column ${j + 1}: «${b.categoria}» cut to one item although one more would fit (${b.alto} + ${sig.b.alturas[0]} in ${lim})`);
                }
              }
              const dos = b.alturas.slice().sort((x, y) => y - x).slice(0, 2).reduce((u, v) => u + v, 0);
              unidad = Math.max(unidad, (b.desde === 0 && b.hasta === b.n) || b.n < 4 ? b.alto : Math.max(b.titulo, b.tituloCont) + dos + 3);   /* a block kept whole moves only whole */
              item = Math.max(item, ...b.alturas);
            });
          });
          assert.ok(Math.min(...alturas) >= Math.max(...alturas) - (unidad + item + g + 2), `${where}: page ${k + 1}: columns ${alturas} within one piece (${unidad + item + g}) of each other`);
          /* balanced: the page's one tallest column cannot be lowered by moving one item across a cut it shares with a
             neighbour (both pieces keeping two items) without the neighbour reaching it */
          const max = Math.max(...p.map((c) => c.alto)), altas = p.filter((c) => c.alto > max - 0.5);
          if (altas.length === 1) {
            const jm = p.indexOf(altas[0]);
            [-1, 1].forEach((d) => {
              const o = p[jm + d]; if (!o || !o.bloques.length) return;
              const A = p[jm], pa = d > 0 ? A.bloques[A.bloques.length - 1] : A.bloques[0], pb = d > 0 ? o.bloques[0] : o.bloques[o.bloques.length - 1];
              if (pa.categoria !== pb.categoria || (d > 0 ? pa.hasta !== pb.desde : pb.hasta !== pa.desde) || pa.hasta - pa.desde < 3) return;
              const it = d > 0 ? pa.alturas[pa.alturas.length - 1] : pa.alturas[0];
              assert.ok(!(o.alto + it + 1 < max - 0.5), `${where}: page ${k + 1}: the tallest column (${max}) could give one item of «${pa.categoria}» (${it}) to its neighbour (${o.alto}) and be lower`);
            });
          }
          /* every column starts with a title: its first piece is a block's start or a continuation with its own title */
          p.forEach((c, j) => { if (c.bloques.length) assert.ok(c.bloques[0].desde === 0 || c.bloques[0].cont, `${where}: page ${k + 1} column ${j + 1} starts with a title`); });
        });
        assert.ok(i.cabe && i.capCm >= i.minCm - 1e-9, where);
        assert.deepStrictEqual(pg.errors, [], where);
        await pg.context().close();
      }
      /* a turned TV read from 4 m: one column, the letter big, categories taller than the column and so cut, each continuation titled «(continúa)» */
      const pg = await pantalla(browser, { q: '?tv=menu-1&pulgadas=55&distancia=4&giro=derecha' });
      const i = await info(pg);
      assert.ok(i.cabe && i.columnas === 1, `one column, nothing cut (${i.columnas} columns, cabe ${i.cabe})`);
      const cortes = i.partes.flat().filter((p) => p.cont);
      assert.ok(cortes.length >= 1 && cortes.every((p) => p.desde > 0), 'a category cut, its continuation starting where the first part ended: ' + JSON.stringify(cortes));
      const titles = await pg.evaluate(() => [...document.querySelectorAll('#main .page h2')].map((h) => ({ ces: h.querySelector('.ces').textContent, cont: (h.querySelector('.cont') || {}).textContent || '' })));
      assert.ok(titles.some((t) => t.cont === '(continúa)'), 'the continuation says so');
      assert.ok(titles.every((t) => t.cont === '' || t.cont === '(continúa)'));
      const cols = await columnas(pg);
      cols.forEach((p) => p.forEach((c) => assert.ok(c.secciones.every((s) => s.ok) && c.scroll <= c.alto + 1, JSON.stringify(c))));
      /* the pieces of a cut category are consecutive: the continuation starts where the first part ended, in the next column (or page) */
      const flat = []; i.partes.forEach((p, k) => p.forEach((x) => flat.push(Object.assign({ pagina: k }, x))));
      flat.forEach((x, n) => { if (x.cont) assert.ok(n > 0 && flat[n - 1].categoria === x.categoria && flat[n - 1].hasta === x.desde && flat[n - 1].pagina >= x.pagina - 1, JSON.stringify([flat[n - 1], x])); });
      const pages = await contenido(pg);
      assert.deepStrictEqual(cats(pages), [...new Set(want.map((x) => clave(x.cat)))], 'a continuation is still the same category');
      assert.strictEqual(items(pages).length, want.length);
      assert.ok(i.capCm >= i.minCm - 1e-9, 'never under the minimum letter');
      assert.deepStrictEqual(pg.errors, []);
      await pg.context().close();
      /* a tiny screen read from far: nothing fits by width at any letter; the minimum letter and the fewest columns, and the diagnosis says NO CABE */
      const tiny = await pantalla(browser, { viewport: { width: 960, height: 540 }, q: '?tv=menu-1&pulgadas=55&distancia=6&diag=1' });
      const t = await info(tiny);
      assert.ok(t.cabe === false && t.columnas === 2 && Math.abs(t.capCm - t.minCm) < 1e-6, 'the least harm (the minimum letter, the fewest columns): ' + JSON.stringify([t.cabe, t.columnas, t.capCm, t.minCm]));
      assert.ok(/NO CABE: baje la escala o la distancia/.test(await diag(tiny)));
      assert.deepStrictEqual(tiny.errors, []);
    }
  },
  {
    name: 'B13: the café\'s real menu (7 categories, 39 products with the public page\'s names) fits ONE screen on a 75" TV read from 2 m and pages on a 55" from 3 m, the letter never under the minimum; layout «una-pantalla» says so in the diagnosis when it had to page; «paginas» (today\'s rule) gives the same board as «auto», which already pages only when one screen would need a letter under the minimum',
    run: async ({ browser }) => {
      menuReal();
      const want = JSON.parse(sql(EXPECTED));
      assert.strictEqual(want.length, 39, 'the real menu: 39 products');
      assert.strictEqual(new Set(want.map((w) => w.cat)).size, 7, 'in 7 categories');
      const one = await pantalla(browser, { q: '?tv=menu-1&pulgadas=75&distancia=2&diag=1' });
      let i = await info(one), pages = await contenido(one);
      assert.strictEqual(items(pages).length, 39);
      assert.ok(pages.flat().some((c) => c.cat === 'Repostería y queques' && c.catEn === 'Pastries & Cake') && items(pages).some((g) => g.es === 'Latte del Bosque Nuboso'), 'the public page\'s names');
      assert.deepStrictEqual([i.paginas, i.unaPantalla, i.cabe, i.layout], [1, true, true, 'auto'], '75" at 2 m: one screen');
      assert.ok(i.capCm >= i.minCm - 1e-9 && i.letraPct >= 80, `letter ${i.letraPct} % of the target`);
      assert.ok(/Maqueta: layout auto · densidad normal · inglés debajo · \d columnas · cabe en una pantalla: sí \(letra \d+ % de la meta\)/.test(await diag(one)), await diag(one));
      assert.ok(!/NO CABE EN UNA PANTALLA/.test(await diag(one)));
      const c = await capitales(one), pxCm = 1920 / LARGO_CM(75);
      assert.ok(c.min / pxCm >= i.minCm - 1 / pxCm, `the capital drawn ${(c.min / pxCm).toFixed(2)} cm ≥ ${i.minCm}`);
      assert.deepStrictEqual(one.errors, []);
      await one.context().close();
      /* «paginas» (today's rule: fewest pages, then the largest letter) chooses the same board */
      const pg2 = await pantalla(browser, { q: '?tv=menu-1&pulgadas=75&distancia=2&layout=paginas&diag=1' });
      const j = await info(pg2);
      assert.deepStrictEqual([j.paginas, j.columnas, j.capCm, j.layout], [1, i.columnas, i.capCm, 'paginas'], 'paginas = auto when one screen fits');
      assert.ok(/Maqueta: layout paginas/.test(await diag(pg2)));
      await pg2.context().close();
      /* 55" at 3 m: it does not fit one screen at the minimum letter: pages, and the letter stays at or over the minimum */
      const far = await pantalla(browser, { q: '?tv=menu-1&pulgadas=55&distancia=3&diag=1' });
      i = await info(far);
      assert.ok(i.paginas >= 2 && i.unaPantalla === false && i.cabe, `55" at 3 m: ${i.paginas} pages`);
      assert.ok(i.capCm >= i.minCm - 1e-9 && Math.abs(i.minCm - 2.4) < 1e-9, `letter ${i.capCm} cm, never under 2.40`);
      assert.ok(/cabe en una pantalla: no \(letra \d+ % de la meta\)/.test(await diag(far)) && !/NO CABE EN UNA PANTALLA/.test(await diag(far)), await diag(far));
      assert.strictEqual(items(await contenido(far)).length, 39);
      assert.deepStrictEqual(far.errors, []);
      await far.context().close();
      sql(`update public.screens set layout = 'una-pantalla' where id = 'menu-1'`);
      const flag = await pantalla(browser, { q: '?tv=menu-1&pulgadas=55&distancia=3&diag=1' });
      const k = await info(flag);
      assert.deepStrictEqual([k.layout, k.paginas, k.capCm, k.columnas], ['una-pantalla', i.paginas, i.capCm, i.columnas], 'una-pantalla pages the same, never under the minimum');
      assert.ok(/NO CABE EN UNA PANTALLA AL MÍNIMO/.test(await diag(flag)), await diag(flag));
      const pg3 = await pantalla(browser, { q: '?tv=menu-1&pulgadas=55&distancia=3&layout=paginas&diag=1' });
      const m = await info(pg3);
      assert.deepStrictEqual([m.paginas, m.columnas, m.capCm], [i.paginas, i.columnas, i.capCm], 'paginas = auto when it must page');
      assert.deepStrictEqual(flag.errors.concat(pg3.errors), []);
    }
  },
  {
    name: 'B14: density «compacta»: titles 1.3× the names, lines 1.06, English 72 %, less padding and a tighter header; the same TV fits more (fewer pages or a bigger letter); «normal» keeps today\'s board',
    run: async ({ browser }) => {
      menuReal();
      const medidas = (pg) => pg.evaluate(() => {
        const f = parseFloat(document.getElementById('stage').style.getPropertyValue('--f'));
        const fs = (e) => parseFloat(getComputedStyle(e).fontSize);
        const l1 = document.querySelector('#main .page .it .l1'), it = document.querySelector('#main .page .it');
        const en = document.querySelector('#main .page .it .en');
        const titles = [...document.querySelectorAll('#main .page h2 .ces')].filter((e) => !e.style.fontSize);
        const hd = document.querySelector('header');
        return { f, compacta: document.getElementById('stage').classList.contains('compacta'),
                 tit: titles.length ? fs(titles[0]) / f : null, lh: parseFloat(getComputedStyle(l1).lineHeight) / fs(l1),
                 en: en ? fs(en) / f : null, padA: parseFloat(getComputedStyle(it).paddingTop) / f, padB: parseFloat(getComputedStyle(it).paddingBottom) / f,
                 header: hd.offsetHeight / f, gap: PANTALLA.info().maqueta.gap / f };
      });
      const normal = await pantalla(browser, { q: '?tv=menu-1&pulgadas=55&distancia=3' });
      const n = await info(normal), mn = await medidas(normal);
      assert.ok(!mn.compacta && Math.abs(mn.tit - 1.5) < 0.02 && Math.abs(mn.lh - 1.12) < 0.02 && Math.abs(mn.en - 0.75) < 0.02 && Math.abs(mn.padA - 0.12) < 0.02 && Math.abs(mn.padB - 0.26) < 0.02 && Math.abs(mn.header - 1.75) < 0.05,
        'normal: today\'s board: ' + JSON.stringify(mn));
      assert.ok(Math.abs(mn.gap - 0.65) < 0.01, 'blocks 0.65 names apart: ' + mn.gap);
      await normal.context().close();
      sql(`update public.screens set density = 'compacta' where id = 'menu-1'`);
      const comp = await pantalla(browser, { q: '?tv=menu-1&pulgadas=55&distancia=3&diag=1' });
      const c = await info(comp), mc = await medidas(comp);
      assert.ok(mc.compacta && Math.abs(mc.tit - 1.3) < 0.02 && Math.abs(mc.lh - 1.06) < 0.02 && Math.abs(mc.en - 0.72) < 0.02 && Math.abs(mc.padA - 0.05) < 0.02 && Math.abs(mc.padB - 0.12) < 0.02 && Math.abs(mc.header - 1.5) < 0.05,
        'compacta: ' + JSON.stringify(mc));
      assert.ok(Math.abs(mc.gap - 0.35) < 0.01, 'blocks 0.35 names apart: ' + mc.gap);
      assert.strictEqual(c.densidad, 'compacta');
      assert.ok(c.paginas < n.paginas || (c.paginas === n.paginas && c.capCm >= n.capCm), `fits more: ${c.paginas} pages at ${c.capCm} cm vs ${n.paginas} at ${n.capCm}`);
      assert.ok(c.capCm >= c.minCm - 1e-9 && c.cabe, 'never under the minimum, nothing cut');
      assert.ok(/densidad compacta/.test(await diag(comp)));
      assert.strictEqual(items(await contenido(comp)).length, 39);
      /* a title with a word too long for its column is still made smaller, never under 1.25× */
      const t = await comp.evaluate(() => [...document.querySelectorAll('#main .page h2 .ces')].map((e) => ({ small: e.style.fontSize, r: parseFloat(getComputedStyle(e).fontSize) / parseFloat(document.getElementById('stage').style.getPropertyValue('--f')) })));
      assert.ok(t.every((x) => x.r >= 1.25 - 0.02 && x.r <= 1.3 + 0.02), JSON.stringify(t));
      assert.deepStrictEqual(comp.errors, []);
    }
  },
  {
    name: 'B15: the English per TV: «debajo» (today), «en-linea» after the name in grey and smaller, on the same line when it fits and wrapping when not, «no» (Spanish only, no English title either); a name the same in both languages is one line in every mode',
    run: async ({ browser }) => {
      menuReal();
      const linea = (pg) => pg.evaluate(() => {
        const fs = (e) => parseFloat(getComputedStyle(e).fontSize);
        const by = (es) => [...document.querySelectorAll('#main .page .it')].find((i) => i.querySelector('.es').textContent === es);
        const one = (es) => { const it = by(es); if (!it) return null; const e = it.querySelector('.es'), en = it.querySelector('.en'), pr = it.querySelector('.pr'), l1 = it.querySelector('.l1');
          const re = e.getBoundingClientRect(), rn = en ? en.getBoundingClientRect() : null;   /* a smaller inline box sits lower on the same line: compare line boxes, not tops */
          return { inline: !!(en && en.parentNode.classList.contains('l1')), below: !!(en && en.parentNode.classList.contains('it')), en: en ? en.textContent : '',
                   sameLine: !!(rn && rn.top >= re.top - 1 && rn.bottom <= re.bottom + 1 && l1.offsetHeight < 1.6 * fs(e)), wrapped: l1.offsetHeight > 1.6 * fs(e),
                   ratio: en ? fs(en) / fs(e) : null, grey: en ? getComputedStyle(en).color : null,
                   ink: getComputedStyle(e).color, price: pr ? pr.textContent : '', priceAfter: !!(pr && en && pr.compareDocumentPosition(en) & Node.DOCUMENT_POSITION_PRECEDING) }; };
        return { te: one('Té'), choc: one('Chocolate caliente costarricense'), latte: one('Latte'), cen: document.querySelectorAll('#main .page h2 .cen').length,
                 ens: document.querySelectorAll('#main .page .en').length, items: document.querySelectorAll('#main .page .it').length };
      });
      const de = await pantalla(browser, { q: '?tv=menu-1&pulgadas=55&distancia=2&diag=1' });
      let m = await linea(de), i = await info(de);
      const ens = m.ens, cen = m.cen;
      assert.ok(i.ingles === 'debajo' && m.te.below && !m.te.inline && m.te.en === 'Tea' && !m.te.sameLine && m.choc.below && m.latte.en === '' && ens > 10 && cen > 0 && m.items === 39,
        'debajo, as today: ' + JSON.stringify(m));
      assert.ok(/inglés debajo/.test(await diag(de)));
      await de.context().close();
      sql(`update public.screens set english = 'en-linea' where id = 'menu-1'`);
      const pg = await pantalla(browser, { q: '?tv=menu-1&pulgadas=55&distancia=2&diag=1' });
      m = await linea(pg); i = await info(pg);
      assert.strictEqual(i.ingles, 'en-linea');
      assert.ok(m.te.inline && !m.te.below && m.te.en === 'Tea' && m.te.sameLine && m.te.priceAfter && digits(m.te.price) === 1000, 'Té · Tea · price on one line: ' + JSON.stringify(m.te));
      assert.ok(m.te.ratio < 1 && m.te.ratio >= 0.72 && m.te.grey !== m.te.ink, 'the English smaller and grey: ' + JSON.stringify(m.te));
      assert.ok(m.choc.inline && m.choc.en === 'Costa Rican Hot Chocolate' && m.choc.wrapped, 'a long pair wraps: ' + JSON.stringify(m.choc));
      assert.ok(m.latte.en === '' && !m.latte.inline && !m.latte.below, 'Latte once');
      assert.deepStrictEqual([m.cen, m.ens, m.items], [cen, ens, 39], 'every English name once, in the line; the titles keep their English');
      assert.ok(/inglés en-linea/.test(await diag(pg)));
      assert.ok(i.cabe && i.capCm >= i.minCm - 1e-9);
      await pg.context().close();
      sql(`update public.screens set english = 'no' where id = 'menu-1'`);
      const no = await pantalla(browser, { q: '?tv=menu-1&pulgadas=55&distancia=2&diag=1' });
      m = await linea(no); i = await info(no);
      assert.deepStrictEqual([i.ingles, m.cen, m.ens, m.items, m.te.en, m.choc.en], ['no', 0, 0, 39, '', ''], 'Spanish only: ' + JSON.stringify(m));
      assert.ok(!/Costa Rican Hot Chocolate|Pastries|Cappuccino/.test(await stageText(no)), 'no English on the screen');
      assert.ok(/Chocolate caliente costarricense/.test(await stageText(no)) && /Capuchino/.test(await stageText(no)));
      assert.ok(/inglés no/.test(await diag(no)));
      assert.deepStrictEqual(de.errors.concat(no.errors, pg.errors), []);
    }
  },
  {
    name: 'B16: promotions intercalated (promo_mode = intercalar): every promo_every s one of this TV\'s slides in force shows for promo_seconds s with a fade, by turns, and the same page of the menu comes back (the pages wait meanwhile); the slide carries the live name and price; the device never keeps a slide',
    run: async ({ browser }) => {
      sql(`update public.screens set promo_mode = 'intercalar', promo_every = 45, promo_seconds = 8 where id = 'menu-1'`);
      const a = marca('Bienvenidos', { sort: 1, screens: ['menu-1'] });
      const b = diapo({ kind: 'producto', item: 'Latte', kicker_es: 'Hoy', kicker_en: 'Today', sort: 2 });
      const T = { cada: 600, revisar: 100, promoCada: 1600, promoSeg: 2500, pagina: 1500 };
      const pg = await pantalla(browser, { q: '?tv=menu-1&pulgadas=55&distancia=3&diag=1', test: T });
      const i0 = await info(pg);
      assert.deepStrictEqual([i0.promo.modo, i0.promo.cadaMs, i0.promo.segMs, i0.promo.leidas, i0.promo.vigentes, i0.promo.enPantalla, i0.ajustes.promo_cada, i0.ajustes.promo_seg],
        ['intercalar', T.promoCada, T.promoSeg, 2, [a, b], null, 45, 8], JSON.stringify(i0.promo));
      assert.ok(i0.paginas > 1, 'a menu of several pages: ' + i0.paginas);
      assert.ok(/Promos: intercalar · cada 2 s · 3 s cada una · 2 leídas · 2 vigentes ahora/.test(await diag(pg)), await diag(pg));
      const shown = [];
      for (let k = 0; k < 2; k++) {
        const t0 = Date.now();
        /* the layer turns on and fades in: wait for the fade to have started (its first frame is still at opacity 0) */
        await until(async () => { const v = await promoVista(pg); return v.on && v.opacity > 0; }, T.promoCada + 2500, 'a promotion on the menu');
        const tOn = Date.now(), v = await promoVista(pg), p0 = (await info(pg)).pagina;
        shown.push(v.id);
        assert.ok(k === 0 || tOn - t0 >= T.promoCada - 400, `the next one ${T.promoCada} ms after the last (${tOn - t0} ms)`);
        assert.ok(v.on && v.opacity > 0, JSON.stringify(v));
        if (v.kind === 'producto') assert.ok(v.id === b && v.tit === 'Latte' && v.kick === 'Hoy · Today' && digits(v.precio) === 2200 && v.cur === '₡' && v.pida && !v.nota, JSON.stringify(v));
        else assert.ok(v.id === a && v.kind === 'marca' && v.tit === 'Bienvenidos' && v.titEn === 'Bienvenidos (en)' && !v.precio, JSON.stringify(v));
        /* the menu waits: the page under the promotion is the same at the end as at the start (its timer fired meanwhile) */
        await sleep(T.promoSeg - 500);
        const during = await promoVista(pg), p1 = (await info(pg)).pagina;
        assert.ok(during.on && during.id === v.id, 'still the same promotion');
        assert.strictEqual(p1, p0, 'the page did not change under the promotion');
        assert.strictEqual(await pg.evaluate(() => document.querySelectorAll('#main .page.on').length), 1);
        await until(async () => !(await promoVista(pg)).on, 2500, 'the promotion ends');
        const dt = Date.now() - tOn;
        assert.ok(dt >= T.promoSeg - 300 && dt <= T.promoSeg + 1500, `shown ${dt} ms (${T.promoSeg})`);
        assert.strictEqual((await info(pg)).pagina, p0, 'the same page is back');
      }
      assert.deepStrictEqual(shown.slice().sort(), [a, b].sort(), 'both slides, by turns: ' + shown.join());
      assert.ok((await info(pg)).promo.mostradas >= 2);
      /* the fade: the layer's opacity moves through values between 0 and 1 */
      await until(async () => (await promoVista(pg)).on, T.promoCada + 2500, 'a third promotion');
      const ops = []; for (let k = 0; k < 12; k++) { ops.push((await promoVista(pg)).opacity); await sleep(60); }
      assert.ok(ops.some((o) => o > 0 && o < 1) || ops[0] === 1, 'a fade in: ' + ops.join());
      assert.ok(onlyReads(pg), [...new Set(pg.api)].join());
      assert.deepStrictEqual(await pg.evaluate(() => Object.keys(localStorage).sort()), ['hg-pantalla-menu', 'hg-pantalla-menu-tv', 'hg_lang'], 'no slide kept on the device');
      assert.ok(!/Bienvenidos|Latte|slides|title|kicker|₡/i.test(await pg.evaluate(() => localStorage.getItem('hg-pantalla-menu-tv'))), 'nothing of the slides in the settings copy');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'B17: nothing in force (an ended slide, one for another TV, one for tomorrow, one paused): the menu is never interrupted, and the diagnosis says so; promo_mode = no: never, whatever the slides; a slide that comes into force shows on the next read',
    run: async ({ browser }) => {
      sql(`update public.screens set promo_mode = 'intercalar' where id = 'menu-1'`);
      marca('Vencida', { starts: "now() - interval '2 days'", ends: "now() - interval '1 hour'" });
      marca('Otra TV', { screens: ['promos-1'] });
      marca('Pausada', { status: 'pausada' });
      const manana = marca('Mañana', { starts: "now() + interval '20 hours'", ends: "now() + interval '2 days'" });
      const T = { cada: 500, revisar: 100, promoCada: 800, promoSeg: 700 };
      const pg = await pantalla(browser, { q: '?tv=menu-1&pulgadas=55&distancia=3&diag=1', test: T });
      let i = await info(pg);
      assert.deepStrictEqual([i.promo.modo, i.promo.leidas, i.promo.vigentes, i.promo.enPantalla], ['intercalar', 1, [], null], JSON.stringify(i.promo));
      let seen = 0; const t0 = Date.now();
      while (Date.now() - t0 < 3 * T.promoCada + 1000) { if ((await promoVista(pg)).on) seen++; await sleep(80); }
      assert.strictEqual(seen, 0, 'never interrupted');
      assert.strictEqual((await info(pg)).promo.mostradas, 0);
      assert.ok(/Promos: intercalar · .* · 1 leídas · 0 vigentes ahora · sin diapositivas vigentes: no interrumpe/.test(await diag(pg)), await diag(pg));
      assert.ok(!/Vencida|Otra TV|Pausada|Mañana/.test(await stageText(pg)), 'none of their texts on the screen');
      /* the slide for tomorrow comes into force now (the owner moved it): shown on the next read */
      sql(`update public.screen_slides set starts_at = now() - interval '1 minute' where id = '${manana}'`);
      await until(async () => (await promoVista(pg)).on, 6000, 'the slide now in force');
      const v = await promoVista(pg);
      assert.ok(v.id === manana && v.tit === 'Mañana', JSON.stringify(v));
      assert.deepStrictEqual(pg.errors, []);
      await pg.context().close();
      /* promo_mode = no: the server sends no slides and the screen never interrupts */
      sql(`update public.screens set promo_mode = 'no' where id = 'menu-1'`);
      const no = await pantalla(browser, { q: '?tv=menu-1&pulgadas=55&distancia=3&diag=1', test: T });
      i = await info(no);
      assert.deepStrictEqual([i.promo.modo, i.promo.leidas, i.promo.vigentes], ['no', 0, []]);
      seen = 0; const t1 = Date.now();
      while (Date.now() - t1 < 3 * T.promoCada + 500) { if ((await promoVista(no)).on) seen++; await sleep(80); }
      assert.strictEqual(seen, 0);
      assert.ok(/Promos: no/.test(await diag(no)));
      assert.ok(onlyReads(no));
      assert.deepStrictEqual(no.errors, []);
    }
  },
  {
    name: 'B18: a product slide whose item is sold out (or has no price) is skipped, as on Screen B; one on screen when its item sells out goes at once on the next read; back in stock, it returns to the turn',
    run: async ({ browser }) => {
      sql(`update public.screens set promo_mode = 'intercalar' where id = 'menu-1';
           update menu_items set available = false where name = 'Latte';
           update menu_items set price_crc = 0 where name = 'Sweet Cane Drink';`);
      const latte = diapo({ kind: 'producto', item: 'Latte', sort: 1 });
      diapo({ kind: 'producto', item: 'Sweet Cane Drink', sort: 2 });
      const m = marca('Marca', { sort: 3 });
      const T = { cada: 500, revisar: 100, promoCada: 700, promoSeg: 600 };
      const pg = await pantalla(browser, { q: '?tv=menu-1&pulgadas=55&distancia=3&diag=1', test: T });
      let i = await info(pg);
      assert.deepStrictEqual([i.promo.leidas, i.promo.vigentes], [1, [m]], 'only the brand slide can show: ' + JSON.stringify(i.promo));
      const ids = new Set(); const t0 = Date.now();
      while (Date.now() - t0 < 4 * (T.promoCada + T.promoSeg)) { const v = await promoVista(pg); if (v.on) ids.add(v.id); await sleep(60); }
      assert.deepStrictEqual([...ids], [m], 'only the brand slide showed');
      assert.ok(!/Latte|Sweet Cane|Agua dulce/.test(await pg.evaluate(() => document.getElementById('promo').innerText)));
      /* back in stock: in the turn again */
      sql(`update menu_items set available = true where name = 'Latte'`);
      await until(async () => (await info(pg)).promo.leidas === 2, 5000, 'the Latte slide read again');
      await until(async () => { const v = await promoVista(pg); return v.on && v.id === latte; }, 3 * (T.promoCada + T.promoSeg) + 2000, 'the Latte slide shown');
      let v = await promoVista(pg);
      assert.ok(v.tit === 'Latte' && digits(v.precio) === 2200, JSON.stringify(v));
      await pg.context().close();
      /* on screen when it sells out: cut at once on the read that says so, no fade through a sold-out product */
      sql(`update menu_items set available = true where name = 'Latte'`);
      const T2 = { cada: 400, revisar: 100, promoCada: 600, promoSeg: 8000 };
      const pg2 = await pantalla(browser, { q: '?tv=menu-1&pulgadas=55&distancia=3', test: T2 });
      await until(async () => { const x = await promoVista(pg2); return x.on && x.id === latte; }, 2 * (T2.promoCada + T2.promoSeg) + 2000, 'the Latte slide on screen');
      sql(`update menu_items set available = false where name = 'Latte'`);
      const t1 = Date.now();
      await until(async () => !(await promoVista(pg2)).on, 3000, 'gone');
      assert.ok(Date.now() - t1 <= T2.cada + 1500, 'cut on the next read');
      assert.strictEqual(await pg2.evaluate(() => getComputedStyle(document.getElementById('promo')).opacity), '0', 'at once, no fade');
      assert.ok(!(await find(pg2, 'Latte')), 'and the menu no longer lists it either');
      await until(async () => { const x = await promoVista(pg2); return x.on; }, 2 * (T2.promoCada + T2.promoSeg) + 2000, 'the next promotion');
      v = await promoVista(pg2);
      assert.strictEqual(v.id, m, 'the brand slide, not the sold-out product');
      assert.ok(onlyReads(pg2));
      assert.deepStrictEqual(pg2.errors, []);
    }
  },
  {
    name: 'B19: the slides\' prices follow the menu\'s freshness: without a connection the price stays «por confirmar» up to the limit, then a product slide leaves at once and a composition keeps its photos and names without any price; prices come back with the connection',
    run: async ({ browser, setOffline }) => {
      sql(`update public.screens set promo_mode = 'intercalar' where id = 'menu-1'`);
      const latte = diapo({ kind: 'producto', item: 'Latte', sort: 1 });
      const T = { cada: 400, revisar: 100, fresco: 1800, vencido: 3400, promoCada: 600, promoSeg: 30000 };
      const pg = await pantalla(browser, { q: '?tv=menu-1&pulgadas=55&distancia=3&diag=1', test: T });
      await until(async () => { const v = await promoVista(pg); return v.on && v.id === latte; }, 5000, 'the product slide');
      let v = await promoVista(pg);
      assert.ok(digits(v.precio) === 2200 && !v.nota, JSON.stringify(v));
      setOffline(true);
      await until(async () => (await info(pg)).estado === 'por-confirmar', 8000, '«por confirmar»');
      v = await promoVista(pg);
      assert.ok(v.on && v.id === latte && digits(v.precio) === 2200 && /Precio por confirmar en caja · Please confirm the price at the counter/.test(v.nota || ''), 'the price with its note: ' + JSON.stringify(v));
      await until(async () => (await info(pg)).estado === 'sin-verificar', 8000, 'no verified prices');
      v = await promoVista(pg);
      assert.ok(!v.on, 'the product slide left: ' + JSON.stringify(v));
      assert.ok(!/₡/.test(await stageText(pg)) && !/₡/.test(await pg.evaluate(() => document.getElementById('promo').innerText)), 'no price anywhere');
      assert.strictEqual(await pg.locator('#stage .pr').count(), 0);
      let seen = 0; const t0 = Date.now();
      while (Date.now() - t0 < 2 * T.promoCada + 800) { if ((await promoVista(pg)).on) seen++; await sleep(80); }
      assert.strictEqual(seen, 0, 'no product slide without a verified price');
      setOffline(false);
      await until(async () => (await info(pg)).estado === 'al-dia', 8000, 'verified again');
      await until(async () => { const x = await promoVista(pg); return x.on && x.id === latte; }, 2 * T.promoCada + 3000, 'the product slide back with its price');
      v = await promoVista(pg);
      assert.ok(digits(v.precio) === 2200 && !v.nota, JSON.stringify(v));
      await pg.context().close();
      /* a composition with names and prices (labels): the photos and names stay, the price follows the same rule */
      sql(`update public.screen_slides set status = 'retirada' where id = '${latte}'`);
      const c = compo({ template: '2-lado', kicker_es: 'Desayuno', zones: [{ entries: [{ item: 'Latte' }] }, { labels: false, entries: ['https://fotos.test/pan.png'] }] });
      setOffline(false);
      const pg2 = await pantalla(browser, { q: '?tv=menu-1&pulgadas=55&distancia=3', test: T });
      await until(async () => { const x = await promoVista(pg2); return x.on && x.id === c; }, 5000, 'the composition');
      await until(async () => { const j = await zonasPromo(pg2); return j && j.zonas.every((x) => x.estado === 'entrada'); }, 4000, 'its zones up');
      let z = (await zonasPromo(pg2)).zonas;
      assert.ok(z.length === 2 && z[0].tit === 'Latte' && digits(z[0].precio) === 2200 && z[1].tit === null && z[1].src === 'https://fotos.test/pan.png', JSON.stringify(z));
      setOffline(true);
      await until(async () => (await info(pg2)).estado === 'por-confirmar' && /Precio por confirmar/.test((await zonasPromo(pg2)).zonas[0].nota || ''), 8000, '«por confirmar» in the zone');
      z = (await zonasPromo(pg2)).zonas;
      assert.ok(digits(z[0].precio) === 2200 && z[0].tit === 'Latte' && z[0].src === null, 'the price with its note, in place: ' + JSON.stringify(z[0]));
      await until(async () => (await info(pg2)).estado === 'sin-verificar' && (await zonasPromo(pg2)).zonas[0].precio === null, 8000, 'no verified prices');
      v = await promoVista(pg2); z = (await zonasPromo(pg2)).zonas;
      assert.ok(v.on && v.id === c, 'the composition stays (its photos are not prices)');
      assert.ok(z[0].tit === 'Latte' && z[0].precio === null && !z[0].nota && z[1].src === 'https://fotos.test/pan.png', 'the name without a price: ' + JSON.stringify(z));
      assert.ok(!/₡/.test(await pg2.evaluate(() => document.getElementById('promo').innerText)));
      assert.deepStrictEqual(pg2.errors, []);
    }
  },
  {
    name: 'B20: the technician\'s address overrides the v2 settings too (densidad, ingles, layout, promo, promo_cada, promo_seg), named in the diagnosis; wrong values fall back to the TV\'s row and are named; a cold start without internet keeps the v2 settings in the device copy',
    run: async ({ browser, setOffline }) => {
      sql(`update public.screens set density = 'compacta', english = 'no', layout = 'una-pantalla', promo_mode = 'intercalar', promo_every = 60, promo_seconds = 7 where id = 'menu-1'`);
      marca('Promo', {});
      const ctx = await browser.newContext({ viewport: { width: 1920, height: 1080 }, locale: 'es-CR', timezoneId: 'America/Costa_Rica' });
      let pg = await pantalla(browser, { context: ctx, q: '?tv=menu-1&densidad=normal&ingles=en-linea&layout=paginas&promo=no&promo_cada=120&promo_seg=12&diag=1', test: { cada: 500, revisar: 100, promoCada: 600, promoSeg: 500 } });
      let i = await info(pg);
      assert.deepStrictEqual([i.ajustes.densidad, i.ajustes.ingles, i.ajustes.layout, i.ajustes.promo, i.ajustes.promo_cada, i.ajustes.promo_seg], ['normal', 'en-linea', 'paginas', 'no', 120, 12]);
      assert.deepStrictEqual([i.origen.densidad, i.origen.ingles, i.origen.layout, i.origen.promo, i.origen.promo_cada, i.origen.promo_seg, i.origen.pulgadas], ['direccion', 'direccion', 'direccion', 'direccion', 'direccion', 'direccion', 'base']);
      assert.deepStrictEqual([i.densidad, i.ingles, i.layout, i.promo.modo, i.promo.leidas], ['normal', 'en-linea', 'paginas', 'no', 1], 'the board follows the address; the slides are read (the row says intercalar) but never shown (the address says no)');
      assert.ok(!(await pg.evaluate(() => document.getElementById('stage').classList.contains('compacta'))));
      assert.ok((await pg.locator('#main .page .l1 .en').count()) > 5 && (await pg.locator('#main .page .it > .en').count()) === 0, 'English in the line');
      let d = await diag(pg);
      assert.ok(/Origen: base de datos \(TV menu-1.* · de la dirección: promo_cada, promo_seg, densidad, ingles, layout, promo/.test(d) && /Maqueta: layout paginas · densidad normal · inglés en-linea/.test(d) && /Promos: no/.test(d), d);
      let seen = 0; const t0 = Date.now();
      while (Date.now() - t0 < 2000) { if ((await promoVista(pg)).on) seen++; await sleep(80); }
      assert.strictEqual(seen, 0, 'promo=no from the address: never');
      await pg.close();
      /* wrong values: the row's values, and the diagnosis names them */
      pg = await pantalla(browser, { context: ctx, q: '?tv=menu-1&densidad=densa&ingles=si&layout=tres&promo=mucho&promo_cada=5&promo_seg=99&diag=1', test: { cada: 500, revisar: 100, promoCada: 600, promoSeg: 500 } });
      i = await info(pg);
      assert.deepStrictEqual([i.ajustes.densidad, i.ajustes.ingles, i.ajustes.layout, i.ajustes.promo, i.ajustes.promo_cada, i.ajustes.promo_seg], ['compacta', 'no', 'una-pantalla', 'intercalar', 60, 7]);
      assert.deepStrictEqual(i.malos, ['promo_cada=5', 'promo_seg=99', 'densidad=densa', 'ingles=si', 'layout=tres', 'promo=mucho']);
      assert.ok(/Ajustes no válidos: promo_cada=5, promo_seg=99, densidad=densa, ingles=si, layout=tres, promo=mucho/.test(await diag(pg)), await diag(pg));
      assert.ok(await pg.evaluate(() => document.getElementById('stage').classList.contains('compacta')));
      assert.strictEqual(await pg.locator('#main .page .en').count(), 0, 'Spanish only, as the row says');
      await until(async () => (await promoVista(pg)).on, 3000, 'the row\'s intercalar applies');
      /* with the real promo timings from the row when the test does not shorten them */
      await pg.close();
      pg = await pantalla(browser, { context: ctx, q: '?tv=menu-1&diag=1' });
      i = await info(pg);
      assert.deepStrictEqual([i.promo.cadaMs, i.promo.segMs, i.promo.modo], [60000, 7000, 'intercalar']);
      assert.ok(/Promos: intercalar · cada 60 s · 7 s cada una/.test(await diag(pg)));
      await pg.close();
      /* a cold start without internet: the v2 settings from the device copy of the row; no slide (they are never kept) */
      setOffline(true);
      const off = await pantalla(browser, { context: ctx, q: '?tv=menu-1&diag=1', wait: false, test: { cada: 500, revisar: 100, promoCada: 600, promoSeg: 500 } });
      await until(() => off.evaluate(() => !!window.PANTALLA && PANTALLA.info().paginas > 0), 8000, 'the names from the copy');
      i = await info(off);
      assert.deepStrictEqual([i.fuente, i.ajustes.densidad, i.ajustes.ingles, i.ajustes.layout, i.ajustes.promo, i.ajustes.promo_cada, i.ajustes.promo_seg, i.promo.leidas, i.promo.vigentes],
        ['copia', 'compacta', 'no', 'una-pantalla', 'intercalar', 60, 7, 0, []]);
      assert.ok(await off.evaluate(() => document.getElementById('stage').classList.contains('compacta')));
      seen = 0; const t1 = Date.now();
      while (Date.now() - t1 < 1500) { if ((await promoVista(off)).on) seen++; await sleep(80); }
      assert.strictEqual(seen, 0, 'nothing to show without a read');
      assert.strictEqual(await off.locator('#stage .pr').count(), 0);
      assert.deepStrictEqual(off.errors, []);
    }
  },
  {
    name: 'B21: a composition as an interlude, drawn as Screen B draws it: two zones, one fixed (a product with its live name and price, framed as the owner set it) and one presentation (its photos take turns at its own seconds, in order, with a dissolve between two loaded layers, never an empty frame); the kicker and the brand line; the letters per metre of a zone; a new price is written in place; the menu waits and comes back on the same page; the zones stop and leave the layer after the interlude; a product sold out leaves its zone to the brand design; the diagnosis names it all',
    run: async ({ browser }) => {
      sql(`update public.screens set promo_mode = 'intercalar' where id = 'menu-1';
           update public.menu_items set name_es = 'Pan de banano casero', photo_url = 'https://fotos.test/banana.png' where name = 'Banana Bread'`);
      const c = compo({ template: '2-lado', kicker_es: 'Desayuno', kicker_en: 'Breakfast', zones: [
        { mode: 'fija', labels: true, entries: [{ item: 'Banana Bread', focus: [20, 80], zoom: 150 }, 'https://fotos.test/nunca.png'] },   /* a fixed zone: its first entry only */
        { mode: 'auto', seconds: 15, labels: false, entries: fotos('p', 3) }
      ] });
      /* a declared second of a zone lasts 100 ms here (15 s -> 1.5 s a photo); the dissolve its real second (the test browser
         draws at 15-20 frames a second, and a fade starts a frame or two after the switch: as on a TV, the fade ends well
         before its clean-up and the next turn); the interlude 7 s, every 1.2 s */
      const T = { cada: 600, revisar: 100, promoCada: 1200, promoSeg: 7000, pagina: 1500, zona: 100, fundido: 1000 };
      const pg = await pantalla(browser, { q: '?tv=menu-1&pulgadas=55&distancia=3&diag=1', test: T });
      const i0 = await info(pg);
      assert.deepStrictEqual([i0.promo.vigentes, i0.promo.enPantalla, i0.promo.composicion, i0.tiempos.zona, i0.tiempos.fundido], [[c], null, null, 100, 1000], JSON.stringify(i0.promo));
      assert.ok(i0.paginas > 1, 'a menu of several pages: ' + i0.paginas);
      await until(async () => { const v = await promoVista(pg); return v.on && v.id === c; }, T.promoCada + 3000, 'the composition on the menu');
      const tOn = Date.now(), p0 = (await info(pg)).pagina;
      /* up and quiet: every zone shows an entry, one layer on, none entering or leaving (the first frame is a cut whose
         clean-up takes two animation frames; a sample inside that window would see the empty first layer marked «sale») */
      await until(async () => { const z = await zonasPromo(pg); return z && z.zonas.every((x) => x.estado === 'entrada' && x.capas.filter((k) => k.on).length === 1 && x.capas.every((k) => !k.entra && !k.sale)); }, 4000, 'its zones up');
      let z = await zonasPromo(pg);
      const a = z.zonas[0], b = z.zonas[1];
      assert.deepStrictEqual([z.template, z.zonas.length, z.kick, z.sup, (await promoVista(pg)).kind], ['2-lado', 2, null, null, 'composicion'],
        'nothing over the zones: no slot title (its kicker «Desayuno») and no brand line (the owner, 2026-11-03): ' + JSON.stringify(z));
      assert.deepStrictEqual([a.modo, a.tamano, a.tit, a.titEn, digits(a.precio), a.nota, a.src, a.encuadre],
        ['fija', 'grande', 'Pan de banano casero', 'Banana Bread', 1500, null, 'https://fotos.test/banana.png', ['20% 80%', 'scale(1.5)']], 'the live name and price, the photo framed: ' + JSON.stringify(a));
      assert.ok(/^₡1\s?500$/.test(a.precio), 'the price as on the menu: ' + a.precio);
      assert.deepStrictEqual([b.modo, b.tamano, b.tit, b.precio, b.caps.length], ['auto', 'grande', null, null, 0], 'labels off: the photo only: ' + JSON.stringify(b));
      assert.ok(/^https:\/\/fotos\.test\/p\d\.png$/.test(b.src), b.src);
      /* the places: the two halves of the stage with a thin gap between them, nothing outside the screen */
      assert.deepStrictEqual([a.box[0], a.box[1], b.box[1], a.dentro, b.dentro], [0, 0, 0, true, true], JSON.stringify([a.box, b.box]));
      assert.ok(Math.abs(a.box[2] - 960) <= 4 && Math.abs(b.box[0] - 960) <= 4 && b.box[0] + b.box[2] === 1920 && a.box[3] === 1080 && b.box[3] === 1080, 'two halves: ' + JSON.stringify([a.box, b.box]));
      /* the letters as on Screen B: the name 1.0 cm/m in a large zone, the price 1.2 x the name, nothing cut */
      const pxCm = 1920 / LARGO_CM(55), tol = 1 / pxCm, cm = (r) => a.caps.filter((x) => x.r === r).map((x) => x.cap / pxCm);
      assert.ok(cm('zt')[0] >= 1.0 * 3 - tol, 'the name 1.0 cm/m in a large zone: ' + cm('zt'));
      assert.ok(cm('zp')[0] >= 1.2 * 3 - tol, 'the price 1.2 x the name: ' + cm('zp'));
      assert.ok(a.caps.every((x) => !x.cortado), 'nothing cut: ' + JSON.stringify(a.caps));
      /* the presentation: the fixed zone never changes; the other takes turns in order every 1.5 s with a dissolve (the new
         layer fades in over the old one, which stays opaque until the fade ends; a loaded photo at every moment) */
      const m = await muestrearPromo(pg, 3600, 30);
      assert.deepStrictEqual([...new Set(m.map((x) => x.z.zonas[0].src + '|' + x.z.zonas[0].entrada))], ['https://fotos.test/banana.png|0'], 'the fixed zone never changes');
      assert.ok(!m.some((x) => /nunca/.test(JSON.stringify(x.z))), 'a fixed zone shows its first entry only');
      const c1 = cambiosPromo(m, 1);
      assert.ok(c1.length >= 2 && c1.length <= 3, `the 15 s zone changed ${c1.length} times in 3.6 s (every 1.5 s): ${c1.join(', ')}`);
      const seq = m.map((x) => x.z.zonas[1].entrada).filter((v, k, arr) => k === 0 || v !== arr[k - 1]);
      seq.forEach((v, k, arr) => { if (k) assert.strictEqual(v, (arr[k - 1] + 1) % 3, 'in order: ' + arr.join('')); });
      m.forEach((x) => assert.strictEqual(x.z.zonas[1].src, `https://fotos.test/p${x.z.zonas[1].entrada}.png`, 'the photo of the entry shown'));
      let fundidos = 0;
      m.forEach((x) => {
        const cs = x.z.zonas[1].capas;
        assert.strictEqual(cs.length, 2, 'two layers');
        assert.ok(cs.some((k) => k.on && k.img && k.lista && k.opacity >= 0.99), `${x.t} ms: an opaque loaded photo at every moment: ` + JSON.stringify(cs));
        const e = cs.find((k) => k.entra), s = cs.find((k) => k.sale);
        if (e && s) { fundidos++; assert.ok(s.on && s.opacity >= 0.99 && e.on && e.lista, `${x.t} ms: the old photo stays opaque under the new one while it fades in: ` + JSON.stringify(cs)); }
      });
      assert.ok(fundidos >= 1 && m.some((x) => { const e = x.z.zonas[1].capas.find((k) => k.entra); return e && e.opacity > 0.05 && e.opacity < 0.95; }), 'a crossfade, not a cut: ' + fundidos + ' samples');
      /* the Menu Manager changes the price: written in place on the next read, the photo untouched, the interlude the same */
      sql(`update public.menu_items set price_crc = 1650 where name = 'Banana Bread'`);
      await until(async () => { const j = await zonasPromo(pg); return j && digits(j.zonas[0].precio) === 1650; }, T.cada + 2500, 'the new price');
      z = await zonasPromo(pg);
      assert.deepStrictEqual([z.id, z.zonas[0].entrada, z.zonas[0].src, z.zonas[0].tit, z.zonas[0].capas.filter((x) => x.on).length, (await info(pg)).promo.mostradas],
        [c, 0, 'https://fotos.test/banana.png', 'Pan de banano casero', 1, 1], JSON.stringify(z.zonas[0]));
      const d = await diag(pg);
      assert.ok(/Composición: plantilla 2-lado · 2 zonas · 7 s · línea «Desayuno»/.test(d) && /Zona 1: foto fija · 1 de 1 entrada con qué mostrar · con nombres y precios · muestra la 1 \(Pan de banano casero, precio\)/.test(d)
                && /Zona 2: presentación cada 15 s · 3 de 3 entradas con qué mostrar · sin textos · muestra la [123] \(solo foto\)/.test(d), d);
      /* the menu waits under the interlude (its page timer fired meanwhile) and comes back on the same page */
      assert.strictEqual((await info(pg)).pagina, p0, 'the page did not change under the promotion');
      assert.strictEqual(await pg.evaluate(() => document.querySelectorAll('#main .page.on').length), 1);
      await until(async () => !(await promoVista(pg)).on, T.promoSeg + 2000, 'the interlude ends');
      const dt = Date.now() - tOn;
      assert.ok(dt >= T.promoSeg - 600 && dt <= T.promoSeg + 1500, `shown ${dt} ms (${T.promoSeg})`);
      assert.strictEqual((await info(pg)).pagina, p0, 'the same page is back');
      await until(() => pg.evaluate(() => document.querySelectorAll('#promo .zona').length === 0), 2500, 'its zones left the layer (emptied after the fade out)');
      assert.strictEqual((await info(pg)).promo.composicion, null);
      await until(async () => (await promoVista(pg)).opacity < 0.05, 2500, 'faded out');
      /* the next interlude: the composition again, its zones up; a product sold out meanwhile leaves its zone to the
         brand design (no fallback photo) on the next read, the other zone goes on, the interlude stays */
      sql(`update public.menu_items set available = false where name = 'Banana Bread'`);
      await until(async () => { const v = await promoVista(pg); return v.on && v.id === c; }, T.promoCada + 3000, 'the composition again');
      await until(async () => { const j = await zonasPromo(pg); return j && j.zonas[0].estado === 'marca' && j.zonas[1].estado === 'entrada' && j.zonas.every((x) => x.capas.filter((k) => k.on).length === 1); }, 5000, 'the brand design in zone 1');
      z = await zonasPromo(pg);
      assert.deepStrictEqual([z.zonas[0].marca, z.zonas[0].tit, z.zonas[0].precio, z.zonas[0].lugar, z.zonas[0].src, (await info(pg)).promo.mostradas], [true, null, null, 'Monteverde, Costa Rica', null, 2], JSON.stringify(z.zonas[0]));
      assert.ok(/Hanging Garden Café/.test(z.zonas[0].text) && !/banano|Banana|₡/.test(z.text), z.text);
      assert.ok(/Zona 1: foto fija · 0 de 1 entrada con qué mostrar · con nombres y precios · NADA QUE MOSTRAR: el diseño de marca/.test(await diag(pg)), await diag(pg));
      assert.ok(cambiosPromo(await muestrearPromo(pg, 2000, 30), 1).length >= 1, 'the presentation goes on');
      assert.ok(onlyReads(pg), [...new Set(pg.api)].join());
      assert.deepStrictEqual(await pg.evaluate(() => Object.keys(localStorage).sort()), ['hg-pantalla-menu', 'hg-pantalla-menu-tv', 'hg_lang'], 'no slide kept on the device');
      assert.ok(!/fotos\.test|zones|Desayuno|₡|1650/.test(await pg.evaluate(() => localStorage.getItem('hg-pantalla-menu') + localStorage.getItem('hg-pantalla-menu-tv'))), 'nothing of the composition on the device');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'B22: the slides\' prices age with the pantalla_datos read that brought them, not only with the menu read: the RPC failing (503) while the menu read goes on, the board shows a new price as current but the interlude\'s price goes «por confirmar» after the limit counted from the last good pantalla_datos read, then a product slide leaves and a composition\'s zone keeps its name without a price, never the old price as current; with the RPC back, the price comes back at once',
    run: async ({ browser }) => {
      sql(`update public.screens set promo_mode = 'intercalar' where id = 'menu-1'`);
      const latte = diapo({ kind: 'producto', item: 'Latte', sort: 1 });
      const T = { cada: 400, revisar: 100, fresco: 1800, vencido: 3400, promoCada: 600, promoSeg: 30000 };
      /* the RPC answers as the stand-in does until the test cuts it: then 503 (what the stand-in answers when PostgREST
         is down) while the menu read goes on untouched */
      const caida = { on: false, n: 0 };   /* n: answers refused */
      const setup = (pg) => pg.route(/\/rest\/v1\/rpc\/pantalla_datos/, (route) => {
        if (!caida.on) return route.continue();
        caida.n++; return route.fulfill({ status: 503, contentType: 'application/json', body: JSON.stringify({ message: 'PostgREST unavailable' }) });
      });
      /* cuts the RPC and waits for its first refusal (the reads never overlap: the last good read is then over, so a
         price changed after the cut can never reach the slide); returns when the cut was made */
      const cortar = async () => { const n = caida.n, t = Date.now(); caida.on = true; await until(() => caida.n > n, T.cada + 2500, 'the RPC refused'); return t; };
      const NOTA = /Precio por confirmar en caja · Please confirm the price at the counter/;
      /* from the moment the slide's price is marked until it leaves: the old price always marked, never the new one */
      const marcado = (v) => !v.on || (digits(v.precio) === 2200 && NOTA.test(v.nota || ''));
      const pg = await pantalla(browser, { q: '?tv=menu-1&pulgadas=55&distancia=3&diag=1', test: T, setup });
      await until(async () => { const v = await promoVista(pg); return v.on && v.id === latte; }, 5000, 'the product slide');
      let v = await promoVista(pg);
      assert.ok(digits(v.precio) === 2200 && !v.nota, JSON.stringify(v));
      const n0 = [reads(pg, 0), reads(pg, 1)];
      const t0 = await cortar();
      sql(`update menu_items set price_crc = 2500 where name = 'Latte'`);
      /* the board follows the menu read: the new price, verified, no warning */
      await until(async () => digits((await find(pg, 'Latte')).pr) === 2500, T.cada + 2500, 'the new price on the board');
      let i = await info(pg);
      assert.deepStrictEqual([i.estado, await aviso(pg)], ['al-dia', ''], 'the board\'s prices are current');
      /* the slide's price came with the RPC: the old one, and it counts as verified only while that read is recent */
      v = await promoVista(pg);
      assert.ok(v.on && v.id === latte && digits(v.precio) === 2200, 'the slide keeps the price of its own read: ' + JSON.stringify(v));
      await until(async () => NOTA.test((await promoVista(pg)).nota || ''), T.fresco + 2500, '«por confirmar» on the slide');
      const dt = Date.now() - t0;
      assert.ok(dt >= T.fresco - T.cada - 600, `the slide's price counts as verified up to the limit (${dt} ms)`);
      assert.ok(dt <= T.fresco + 1500, `«por confirmar» no later than the limit, counted from the last good pantalla_datos read (${dt} ms)`);
      v = await promoVista(pg); i = await info(pg);
      assert.ok(v.on && v.id === latte && marcado(v), 'the old price, marked: ' + JSON.stringify(v));
      assert.ok(i.estado === 'al-dia' && i.edadMs <= T.fresco, 'while the board\'s prices are still current: ' + JSON.stringify([i.estado, i.edadMs]));
      assert.strictEqual(await aviso(pg), '', 'no warning on the board');
      assert.strictEqual(digits((await find(pg, 'Latte')).pr), 2500, 'the board keeps the new price');
      /* then no price at all: the product slide leaves, counted from the same read; meanwhile the old price was never current */
      let dejo = null;
      while (Date.now() - t0 < T.vencido + 2500) {
        const x = await promoVista(pg);
        assert.ok(marcado(x), 'never the old price as current, never the new one: ' + JSON.stringify(x));
        if (!x.on) { dejo = Date.now(); break; }
        await sleep(60);
      }
      assert.ok(dejo, 'the product slide left');
      const dt2 = dejo - t0;
      assert.ok(dt2 >= T.vencido - T.cada - 600 && dt2 <= T.vencido + 1500, `no price no later than the limit, counted from the last good pantalla_datos read (${dt2} ms)`);
      i = await info(pg);
      assert.deepStrictEqual([i.estado, i.promo.vigentes, i.promo.enPantalla], ['al-dia', [], null], 'the board current, the product slide out of the turn: ' + JSON.stringify(i.promo));
      assert.ok(!/₡/.test(await pg.evaluate(() => document.getElementById('promo').innerText)) && digits((await find(pg, 'Latte')).pr) === 2500, 'no price on the layer, the board with its prices');
      /* both reads went on meanwhile: the RPC asked and refused, the menu answered */
      assert.ok(reads(pg, 0) >= n0[0] + 3 && reads(pg, 1) >= n0[1] + 3 && caida.n >= 3, 'both reads went on: ' + JSON.stringify([n0, reads(pg, 0), reads(pg, 1), caida.n]));
      let seen = 0; const t1 = Date.now();
      while (Date.now() - t1 < 2 * T.promoCada + 800) { if ((await promoVista(pg)).on) seen++; await sleep(80); }
      assert.strictEqual(seen, 0, 'no product slide while the RPC fails');
      /* the RPC answers again: the slide back at once, with the price the RPC now carries, verified */
      caida.on = false;
      const t2 = Date.now();
      await until(async () => { const x = await promoVista(pg); return x.on && x.id === latte; }, T.cada + T.promoCada + 3000, 'the product slide back');
      v = await promoVista(pg);
      assert.ok(digits(v.precio) === 2500 && !v.nota, 'the new price, verified: ' + JSON.stringify(v));
      assert.ok(Date.now() - t2 <= T.cada + T.promoCada + 1500, `at once, on the first good read (${Date.now() - t2} ms)`);
      assert.ok(onlyReads(pg), [...new Set(pg.api)].join());
      assert.deepStrictEqual(pg.errors, []);
      await pg.context().close();
      /* a composition with a name and price in a zone: the zone keeps its name through it all and the composition never
         leaves (its photos are not prices); its price marked, then gone, then back at once with the RPC */
      sql(`update public.screen_slides set status = 'retirada' where id = '${latte}'`);
      const c = compo({ template: '2-lado', kicker_es: 'Desayuno', zones: [{ entries: [{ item: 'Latte' }] }, { labels: false, entries: ['https://fotos.test/pan.png'] }] });
      caida.on = false;
      const pg2 = await pantalla(browser, { q: '?tv=menu-1&pulgadas=55&distancia=3', test: T, setup });
      await until(async () => { const x = await promoVista(pg2); return x.on && x.id === c; }, 5000, 'the composition');
      await until(async () => { const j = await zonasPromo(pg2); return j && j.zonas.every((x) => x.estado === 'entrada'); }, 4000, 'its zones up');
      let z = (await zonasPromo(pg2)).zonas;
      assert.ok(z.length === 2 && z[0].tit === 'Latte' && digits(z[0].precio) === 2500 && !z[0].nota && z[1].src === 'https://fotos.test/pan.png', JSON.stringify(z));
      const t3 = await cortar();
      sql(`update menu_items set price_crc = 2700 where name = 'Latte'`);
      await until(async () => digits((await find(pg2, 'Latte')).pr) === 2700, T.cada + 2500, 'the new price on the board');
      await until(async () => NOTA.test((await zonasPromo(pg2)).zonas[0].nota || ''), T.fresco + 2500, '«por confirmar» in the zone');
      const dt3 = Date.now() - t3;
      assert.ok(dt3 >= T.fresco - T.cada - 600 && dt3 <= T.fresco + 1500, `«por confirmar» counted from the last good pantalla_datos read (${dt3} ms)`);
      z = (await zonasPromo(pg2)).zonas; i = await info(pg2);
      assert.ok(digits(z[0].precio) === 2500 && z[0].tit === 'Latte' && z[0].src === null && z[1].src === 'https://fotos.test/pan.png', 'the old price with its note, in place: ' + JSON.stringify(z));
      assert.deepStrictEqual([i.estado, i.promo.enPantalla, await aviso(pg2)], ['al-dia', c, ''], 'the board current, the composition on');
      /* then the name without a price; meanwhile the old price was never current and the composition stayed */
      let sinPrecio = null;
      while (Date.now() - t3 < T.vencido + 2500) {
        const j = await zonasPromo(pg2);
        assert.ok(j && j.id === c, 'the composition stays');
        const a = j.zonas[0];
        assert.ok(a.tit === 'Latte' && (a.precio === null ? !a.nota : digits(a.precio) === 2500 && NOTA.test(a.nota || '')), 'never the old price as current, never the new one: ' + JSON.stringify(a));
        if (a.precio === null) { sinPrecio = Date.now(); break; }
        await sleep(60);
      }
      assert.ok(sinPrecio, 'no price in the zone');
      const dt4 = sinPrecio - t3;
      assert.ok(dt4 >= T.vencido - T.cada - 600 && dt4 <= T.vencido + 1500, `no price no later than the limit, counted from the last good pantalla_datos read (${dt4} ms)`);
      v = await promoVista(pg2); z = (await zonasPromo(pg2)).zonas;
      assert.ok(v.on && v.id === c && z[0].tit === 'Latte' && z[0].precio === null && !z[0].nota && z[1].src === 'https://fotos.test/pan.png', 'the name without a price: ' + JSON.stringify(z));
      assert.ok(!/₡/.test(await pg2.evaluate(() => document.getElementById('promo').innerText)), 'no price on the layer');
      assert.ok(digits((await find(pg2, 'Latte')).pr) === 2700 && (await info(pg2)).estado === 'al-dia', 'the board with its new price, current');
      /* the RPC back: the price the RPC now carries, written in place at once, verified; the interlude the same */
      caida.on = false;
      const t4 = Date.now();
      await until(async () => { const j = await zonasPromo(pg2); return j && digits(j.zonas[0].precio) === 2700; }, T.cada + 2500, 'the price back in the zone');
      z = (await zonasPromo(pg2)).zonas; v = await promoVista(pg2);
      assert.ok(Date.now() - t4 <= T.cada + 1500, `at once, on the first good read (${Date.now() - t4} ms)`);
      assert.ok(v.on && v.id === c && z[0].tit === 'Latte' && !z[0].nota && z[1].src === 'https://fotos.test/pan.png', 'in place, the new price verified: ' + JSON.stringify(z));
      assert.ok(onlyReads(pg2), [...new Set(pg2.api)].join());
      assert.deepStrictEqual(pg2.errors, []);
    }
  },
  {
    name: 'B23: the interludes go on where the last one stopped: a presentation zone starts the next interlude at the entry after the one it showed when the interlude ended (every photo of a long presentation gets its turn across interludes); its single zone\'s first turn in every interlude is its own seconds (zone i of a composition waits 1 + 0.25·i turns on every start, as on Screen B: 380 P28)',
    run: async ({ browser }) => {
      sql(`update public.screens set promo_mode = 'intercalar' where id = 'menu-1'`);
      const c = compo({ template: '1', zones: [{ mode: 'auto', seconds: 10, labels: false, entries: fotos('w', 4) }] });   /* 10 s -> 2.5 s a photo here */
      /* the interlude 4 s (two photos), every 0.9 s */
      const T = { cada: 600, revisar: 100, promoCada: 900, promoSeg: 4000, pagina: 1500, zona: 250, fundido: 200 };   /* the interlude 4 s: two photos, the next one 1 s after it ends */
      const pg = await pantalla(browser, { q: '?tv=menu-1&pulgadas=55&distancia=3', test: T });
      const t0 = Date.now(), m = [];
      while (Date.now() - t0 < 19000) { const v = await promoVista(pg), z = v.on && v.id === c ? await zonasPromo(pg) : null; m.push({ on: !!z, entrada: z ? z.zonas[0].entrada : null }); await sleep(40); }
      /* the interludes: the entries the zone showed in each, in order */
      const runs = []; let abierta = false;
      m.forEach((x) => {
        if (!x.on) { abierta = false; return; }
        if (!abierta) { runs.push([]); abierta = true; }
        const r = runs[runs.length - 1];
        if (x.entrada != null && r[r.length - 1] !== x.entrada) r.push(x.entrada);
      });
      assert.ok(runs.length >= 3, 'three interludes: ' + JSON.stringify(runs));
      runs.forEach((r, k) => {
        if (k < runs.length - 1 || !abierta) assert.ok(r.length >= 2, `interlude ${k + 1}: two photos per interlude: ` + JSON.stringify(runs));   /* the sampling may end inside the last interlude */
        r.forEach((e, n) => { if (n) assert.strictEqual(e, (r[n - 1] + 1) % 4, 'in order: ' + JSON.stringify(runs)); });
        if (k) { const antes = runs[k - 1]; assert.strictEqual(r[0], (antes[antes.length - 1] + 1) % 4, `interlude ${k + 1} goes on from the entry after the last one shown: ` + JSON.stringify(runs)); }
      });
      const vistas = new Set(); runs.forEach((r) => r.forEach((e) => vistas.add(e)));
      assert.deepStrictEqual([...vistas].sort(), [0, 1, 2, 3], 'every photo got its turn: ' + JSON.stringify(runs));
      assert.ok(onlyReads(pg));
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'B24: the TV\'s products (item_ids): only those, under their categories in the Menu Manager order; a category left without a chosen product disappears; an id that no longer exists is skipped and counted; none left = every product and the diagnosis says so; the device copy keeps the choice; with the real menu, 9 chosen products (3 categories) fit 2–3 pages on a 32" TV read from 3 m (compacta, sin inglés) at a letter never under the minimum',
    run: async ({ browser, setOffline }) => {
      const idDe = (name) => sql(`select id from public.menu_items where name = '${name.replace(/'/g, "''")}'`);
      const latte = idDe('Latte'), conLeche = idDe('Café con Leche'), croissant = idDe('Butter Croissant');
      assert.ok([latte, conLeche, croissant].every((x) => /^[0-9a-f-]{36}$/.test(x)), 'the seed has the three products');
      const nombres = (pages) => items(pages).map((g) => clave(g.en || g.es));
      /* (a) three chosen products in two categories, and one id that no longer exists */
      sql(`update public.screens set item_ids = '{${latte},${conLeche},${croissant},${CAT.gone}}' where id = 'menu-1'`);
      const pg = await pantalla(browser, { q: '?tv=menu-1&pulgadas=55&distancia=3&diag=1', test: { cada: 1000 } });
      let pages = await contenido(pg), i = await info(pg);
      assert.deepStrictEqual(nombres(pages), ['latte', 'cafe con leche', 'butter croissant'], 'only the chosen products, each under its category, in the Menu Manager order');
      assert.deepStrictEqual(cats(pages), ['coffee', 'pastries & cake'], 'only the categories with a chosen product, in the Menu Manager order');
      assert.ok(items(pages).every((g) => digits(g.pr) > 0), 'with their prices');
      assert.deepStrictEqual([i.productos, i.productosFaltan, i.categorias], ['elegidos', 1, 'todas']);
      assert.ok(/Muestra: todas las categorías · productos elegidos \(3\) \(1 ya no existen\) · agotados ocultos/.test(await diag(pg)), await diag(pg));
      /* combined with the TV's categories: a chosen product shows only when its category is shown too (it is not "gone") */
      sql(`update public.screens set category_ids = '{${CAT.pastries}}' where id = 'menu-1'`);
      await until(async () => (await info(pg)).categorias === 'elegidas', 8000, 'the category rule');
      pages = await contenido(pg); i = await info(pg);
      assert.deepStrictEqual([nombres(pages), cats(pages), i.productos, i.productosFaltan], [['butter croissant'], ['pastries & cake'], 'elegidos', 1]);
      assert.ok(/Muestra: categorías elegidas · productos elegidos \(3, 1 en pantalla\) \(1 ya no existen\)/.test(await diag(pg)), await diag(pg));
      /* (b) none of the chosen ids exists any more: every product, and the diagnosis says so */
      sql(`update public.screens set category_ids = null, item_ids = '{${CAT.gone}}' where id = 'menu-1'`);
      const want = JSON.parse(sql(EXPECTED));
      await until(async () => items(await contenido(pg)).length === want.length, 8000, 'every product');
      i = await info(pg); pages = await contenido(pg);
      assert.deepStrictEqual([i.productos, i.categorias], ['no-existen', 'todas']);
      assert.deepStrictEqual(cats(pages), [...new Set(want.map((w) => clave(w.cat)))], 'every category, in the Menu Manager order');
      assert.ok(/Muestra: todas las categorías · TODOS los productos: los elegidos ya no existen en el menú · agotados ocultos/.test(await diag(pg)), await diag(pg));
      assert.ok(!/Combo|Flavor shot|Add ham|Extras/i.test(await stageText(pg)), 'never Extras & Combos');
      /* (c) no choice: every product, chosen by nobody, and nothing extra in the diagnosis */
      sql(`update public.screens set item_ids = null where id = 'menu-1'`);
      await until(async () => (await info(pg)).productos === 'todos', 8000, 'all, chosen by nobody');
      assert.strictEqual(items(await contenido(pg)).length, want.length);
      assert.ok(/Muestra: todas las categorías · agotados ocultos/.test(await diag(pg)), await diag(pg));
      /* (d) the device keeps the choice with the other settings and the names copy already holds only the chosen ones:
         a cold start without internet shows only those, without a price, and the diagnosis says so */
      sql(`update public.screens set item_ids = '{${latte},${croissant}}' where id = 'menu-1'`);
      await until(async () => (await info(pg)).productos === 'elegidos' && items(await contenido(pg)).length === 2, 8000, 'the two chosen products');
      await until(async () => { const v = JSON.parse(await pg.evaluate(() => localStorage.getItem('hg-pantalla-menu'))); return v && v.cats.flatMap((c) => c.items).length === 2; }, 8000, 'the copy holds the two names only');
      const kept = JSON.parse(await pg.evaluate(() => localStorage.getItem('hg-pantalla-menu-tv')));
      assert.deepStrictEqual(kept.fila.item_ids, [latte, croissant], 'the settings copy keeps the choice (ids only)');
      assert.ok(Object.keys(kept.fila).every((k) => CAMPOS_FILA.includes(k)), Object.keys(kept.fila).join());
      assert.ok(onlyReads(pg));
      assert.deepStrictEqual(pg.errors, []);
      const ctx = pg.context();
      await pg.close();
      setOffline(true);
      const off = await pantalla(browser, { context: ctx, q: '?tv=menu-1&pulgadas=55&distancia=3&diag=1', wait: false, test: { cada: 500 } });
      await until(() => off.evaluate(() => !!window.PANTALLA && PANTALLA.info().deCopia && PANTALLA.info().paginas > 0), 8000, 'the names from the copy');
      pages = await contenido(off); i = await info(off);
      assert.deepStrictEqual(nombres(pages), ['latte', 'butter croissant'], 'the copy\'s names are only the chosen ones');
      assert.deepStrictEqual([i.fuente, i.productos, i.estado, i.ajustes.productos], ['copia', 'elegidos', 'sin-verificar', [latte, croissant]]);
      assert.ok(items(pages).every((g) => g.pr === '') && await off.locator('#stage .pr').count() === 0, 'never a price');
      assert.ok(/Origen: copia del aparato/.test(await diag(off)) && /productos elegidos \(2\)/.test(await diag(off)), await diag(off));
      assert.deepStrictEqual(off.errors, []);
      setOffline(false);
      await ctx.close();
      /* (e) the summarized menu the owner asked for (D-064): 9 of the real menu's products, the first of each category in
         the Menu Manager order, on a 32" TV read from 3 m, compacta and sin inglés: 2-3 pages, the letter never under 2.40 cm */
      menuReal();
      const primeros = (cat, n) => sql(`select i.id from menu_items i join menu_categories c on c.id = i.category_id
                                         where c.name = '${cat}' and i.available and i.price_crc > 0 order by i.sort, i.name limit ${n}`).split('\n').filter(Boolean);
      const resumen = [].concat(primeros('Coffee', 4), primeros('Sandwiches', 2), primeros('Pastries & Cake', 3));   /* 9 in 3 categories: 2 pages here, one more with a wider font */
      assert.strictEqual(resumen.length, 9, 'the real menu has the 9 products');
      sql(`update public.screens set item_ids = '{${resumen.join(',')}}' where id = 'menu-1'`);
      const tv = await pantalla(browser, { q: '?tv=menu-1&pulgadas=32&distancia=3&densidad=compacta&ingles=no&look=dia&diag=1' });
      i = await info(tv); pages = await contenido(tv);
      assert.strictEqual(items(pages).length, 9, 'the 9 chosen products');
      assert.strictEqual(new Set(cats(pages)).size, 3, 'their three categories: ' + cats(pages).join(', '));
      assert.ok(i.paginas >= 1 && i.paginas <= 3, `32" at 3 m: ${i.paginas} pages (2-3 expected)`);
      assert.deepStrictEqual([i.cabe, i.productos, i.productosFaltan, i.densidad, i.ingles, i.ajustes.pulgadas, i.ajustes.distancia], [true, 'elegidos', 0, 'compacta', 'no', 32, 3]);
      assert.ok(i.capCm >= i.minCm - 1e-9 && Math.abs(i.minCm - 2.4) < 1e-9, `letter ${i.capCm} cm, never under 2.40`);
      assert.ok(i.columnas >= 2, `${i.columnas} columns`);
      assert.ok(i.maqueta.paginas.length === i.paginas && i.maqueta.paginas.every((p) => p.some((col) => col.bloques.length > 0)), 'every page has at least one column with something in it');
      const c = await capitales(tv), pxCm = 1920 / LARGO_CM(32);
      assert.ok(c.min / pxCm >= i.minCm - 1 / pxCm, `the capital drawn ${(c.min / pxCm).toFixed(2)} cm ≥ ${i.minCm}`);
      assert.ok(items(pages).every((g) => digits(g.pr) > 0 && g.en === ''), 'every price shown, no English');
      assert.ok(/productos elegidos \(9\) · agotados ocultos/.test(await diag(tv)), await diag(tv));
      assert.ok(onlyReads(tv));
      assert.deepStrictEqual(tv.errors, []);
      sql(`update public.screens set item_ids = null where id = 'menu-1'`);
    }
  },
];
