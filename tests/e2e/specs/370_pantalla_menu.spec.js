/* Screen A (website/pantalla-menu.html, docs/PANTALLAS.md, migration 0036): the menu with prices for the guests.
   The owner's conditions it is held to here:
   3) prices and availability read only from the existing menu, never written; in sync by itself (it polls);
   4) a lost connection or old data never shows a price as current;
   5) read from a distance: big prices, little else;
   7) never Extras & Combos (combos and discounts are not announced);
   8) its settings come from the owner's page (pantallas, table screens), read with the public key, never written.
   A1-A9 are the prototype's tests (fixed per the review); B1-B10 the settings from the database and the review fixes. */
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
const CAT = { coffee: 'a0000000-0000-4000-8000-000000000001', pastries: 'a0000000-0000-4000-8000-000000000006',
              extras: 'a0000000-0000-4000-8000-000000000009', gone: '0b000000-0000-4000-8000-0000000000ff' };

/* the screen on its own device; every call to the database stand-in is kept (method and path) */
async function pantalla(browser, opts) {
  opts = opts || {};
  const pg = await page(browser, { context: opts.context, viewport: opts.viewport || { width: 1920, height: 1080 }, station: null, lang: 'es' });
  pg.api = [];
  pg.on('request', (r) => { const u = new URL(r.url()); if (u.port === API_PORT) pg.api.push(r.method() + ' ' + u.pathname); });
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
      const raw = await pg.evaluate(() => localStorage.getItem('hg-pantalla-menu'));
      const copia = JSON.parse(raw);
      assert.deepStrictEqual(Object.keys(copia).sort(), ['at', 'cats']);
      assert.ok(copia.cats.length >= 8, 'the names are kept on the device');
      copia.cats.forEach((c) => {
        assert.deepStrictEqual(Object.keys(c).sort(), ['en', 'es', 'items']);
        c.items.forEach((it) => assert.deepStrictEqual(Object.keys(it).sort(), ['en', 'es'], 'an item of the copy is only its names'));
        [c.es, c.en].concat(...c.items.map((it) => [it.es, it.en])).forEach((s) => assert.ok(typeof s === 'string' && !/₡|\d{3}/.test(s), s));
      });
      assert.strictEqual(copia.cats.flatMap((c) => c.items).length, want.length);
      assert.ok(!/precio|price|₡|"\d{3,}/.test(raw), 'no price is kept on the device: ' + raw.slice(0, 120));
      const tv = JSON.parse(await pg.evaluate(() => localStorage.getItem('hg-pantalla-menu-tv')));
      assert.ok(tv.fila && !Object.keys(tv.fila).some((k) => /price|precio|item/.test(k)) && !/₡/.test(JSON.stringify(tv)), 'the settings copy holds no price');
      const i = await info(pg);
      assert.deepStrictEqual([i.tiempos.cada, i.tiempos.fresco, i.tiempos.vencido, i.paginaMs, i.salto, i.tiempos.limite], [30000, 120000, 600000, 28000, 15000, 12000],
        'reads every 30 s; prices shown up to 2 min, «por confirmar» up to 10 min; a page every 28 s; a pause over 3 ticks of 5 s; 12 s per read');
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
        assert.ok((giro === 'no' ? [2, 3] : [1, 2]).includes(i.columnas), `${where}: ${i.columnas} columns for the orientation`);
        /* a category is cut only when it is longer than a whole page, and its parts follow each other */
        const seen = {}; i.partes.forEach((pgParts, k) => pgParts.forEach((p) => { (seen[p.categoria] = seen[p.categoria] || []).push(k); }));
        Object.keys(seen).forEach((c) => {
          const ks = seen[c]; assert.ok(ks.every((k, j) => j === 0 || k === ks[j - 1] + 1), `${where}: ${c} on consecutive pages`);
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
        assert.ok((giro === 'no' ? [2, 3] : [1, 2]).includes(i.columnas), `${where}: ${i.columnas} columns`);
        const st = await pg.evaluate(() => { const s = document.getElementById('stage'); return [s.offsetWidth, s.offsetHeight, s.style.transform]; });
        assert.deepStrictEqual(st, giro === 'no' ? [1920, 1080, ''] : [1080, 1920, 'translate(1920px, 0px) rotate(90deg)'], `${where}: the stage`);
        const c = await capitales(pg), pxCm = 1920 / LARGO_CM(pulgadas), tol = 1 / pxCm;
        assert.ok(c.min / pxCm >= i.minCm - tol && Math.abs(c.min / pxCm - i.capCm) <= tol + 0.02, `${where}: the capital drawn ${(c.min / pxCm).toFixed(2)} cm is the one chosen (${i.capCm}, minimum ${i.minCm})`);
        assert.strictEqual(i.cabe, true, where);
        return i;
      };
      await check(65, 4, 'derecha', 110, 17000);
      assert.deepStrictEqual((await info(pg)).origen, { pulgadas: 'base', distancia: 'base', escala: 'base', pagina: 'base', giro: 'base', look: 'base' });
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
      assert.ok(Object.keys(kept.fila).every((k) => ['id', 'kind', 'inches', 'distance_m', 'turn', 'scale_pct', 'look', 'page_seconds', 'category_ids', 'sold_out', 'on_from', 'on_to', 'updated_at'].includes(k)), Object.keys(kept.fila).join());
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
      assert.deepStrictEqual(i.origen, { pulgadas: 'base', distancia: 'direccion', escala: 'direccion', pagina: 'direccion', giro: 'direccion', look: 'direccion' });
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
  }
];
