/* Screen A (prototipos/pantalla-menu/pantalla-menu.html, docs/PANTALLAS.md): the menu with prices for the guests, a
   private prototype. The owner's conditions of 2026-10-31 it is held to here:
   3) prices and availability read only from the existing menu, never written;
   4) a lost connection or old data never shows a price as current;
   5) read from a distance: big prices, little else.
   Run by tests/prototipos/run.sh, which serves the page next to a copy of website/ (config.js, lang.js, version.js). */
'use strict';
const assert = require('assert');
const { page, goto, until, sql } = require('../../e2e/lib');

const API_PORT = String(Number(process.env.E2E_SITE_PORT || 8090) + 1000);
const LARGO_CM = (pulgadas) => pulgadas * 2.54 * 16 / Math.sqrt(337);   /* long side of a 16:9 screen */
const clave = (s) => String(s || '').replace(/\s+/g, ' ').trim().toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
const digits = (s) => Number(String(s || '').replace(/\D/g, '')) || 0;

/* the screen on its own device; every call to the database stand-in is kept (method and path) */
async function pantalla(browser, opts) {
  opts = opts || {};
  const pg = await page(browser, { context: opts.context, viewport: opts.viewport || { width: 1920, height: 1080 }, station: null, lang: 'es' });
  pg.api = [];
  pg.on('request', (r) => { const u = new URL(r.url()); if (u.port === API_PORT) pg.api.push(r.method() + ' ' + u.pathname); });
  if (opts.test) await pg.addInitScript((t) => { window.PANTALLA_TEST = t; }, opts.test);
  await goto(pg, '/pantalla-menu' + (opts.q === undefined ? '?pulgadas=55&distancia=3' : opts.q));
  if (opts.wait !== false) await until(() => pg.evaluate(() => !!window.PANTALLA && PANTALLA.info().estado === 'al-dia'), 15000, 'the prices verified');
  return pg;
}
const info = (pg) => pg.evaluate(() => PANTALLA.info());
/* what every page of the screen holds (hidden pages too) */
const contenido = (pg) => pg.evaluate(() => [...document.querySelectorAll('#main .page')].map((p) => [...p.querySelectorAll('.cat')].map((c) => ({
  cat: c.querySelector('h2 .ces').textContent, catEn: (c.querySelector('h2 .cen') || {}).textContent || '',
  items: [...c.querySelectorAll('.it')].map((i) => ({ es: i.querySelector('.es').textContent, en: (i.querySelector('.en') || {}).textContent || '',
                                                     pr: (i.querySelector('.pr') || {}).textContent || '' }))
}))));
const items = (pages) => pages.flat().flatMap((c) => c.items);
const stageText = (pg) => pg.evaluate(() => document.getElementById('stage').innerText);
const aviso = (pg) => pg.evaluate(() => { const a = document.getElementById('aviso'); return a.hidden ? '' : a.innerText.replace(/\s+/g, ' ').trim(); });
/* what the screen must show: available items with a price above zero, never Extras & Combos */
const EXPECTED = `select coalesce(json_agg(json_build_object('cat', c.name, 'name', i.name, 'name_es', i.name_es, 'price', i.price_crc)
                   order by c.sort, i.sort, i.name), '[]')
                    from menu_items i join menu_categories c on c.id = i.category_id
                   where c.name <> 'Extras & Combos' and i.available and i.price_crc > 0`;

module.exports.tests = [
  {
    name: 'A1: every available item with its price, in the Menu Manager order; never Extras & Combos, a sold-out item or a price of zero; Spanish first, a name the same in both languages once; only reads',
    run: async ({ browser }) => {
      sql(`update menu_items set available = false where name = 'Tea';
           update menu_items set price_crc = 0 where name = 'Sweet Cane Drink';
           update menu_items set name_es = 'Pan de banano casero' where name = 'Banana Bread';`);
      const pg = await pantalla(browser);
      const want = JSON.parse(sql(EXPECTED));
      const pages = await contenido(pg), got = items(pages);
      assert.ok(want.length > 30, 'the test menu has its items');
      assert.strictEqual(got.length, want.length, 'one line per available item with a price, each once');
      want.forEach((w) => {
        const hit = got.filter((g) => digits(g.pr) === w.price && (g.en === w.name || (w.name_es && g.es === w.name_es) || (!g.en && clave(g.es) === clave(w.name))));
        assert.ok(hit.length >= 1, `${w.name} (₡${w.price}) is on the screen with its price`);
      });
      /* categories in the Menu Manager order (a category cut across pages shows its title on each part) */
      const cats = pages.flat().map((c) => c.catEn || c.cat).filter((c, i, a) => i === 0 || clave(c) !== clave(a[i - 1]));
      assert.deepStrictEqual(cats.map(clave), [...new Set(want.map((w) => w.cat))].map(clave), 'categories in the Menu Manager order');
      const text = await stageText(pg);
      assert.ok(!/Combo|Flavor shot|Add ham|milk upgrade|Extras/i.test(text), 'nothing of Extras & Combos on the screen');
      assert.ok(!got.some((g) => /Tea|Té$|Sweet Cane|Agua dulce/.test(g.es + ' ' + g.en)), 'the sold-out item and the item without a price are not shown');
      assert.ok(got.every((g) => /^₡\s?\d{1,3}([\s  ]\d{3})*$/.test(g.pr) && digits(g.pr) > 0), 'every price is ₡ and a positive amount');
      /* Spanish first: the Menu Manager's name_es, else the site's dictionary; English below; the same name once */
      const by = (es) => got.find((g) => g.es === es);
      assert.deepStrictEqual(by('Pan de banano casero'), { es: 'Pan de banano casero', en: 'Banana Bread', pr: by('Pan de banano casero').pr });
      assert.strictEqual(by('Capuchino').en, 'Cappuccino');
      assert.strictEqual(by('Espresso').en, '', 'Espresso is written once');
      assert.strictEqual(by('Tres leches').en, '', 'Tres Leches / Tres leches is written once');
      assert.ok(pages.flat().some((c) => c.cat === 'Café' && c.catEn === 'Coffee'), 'category titles in Spanish with the English beside');
      assert.ok(/Precios en colones, IVA incluido · Prices in colones, tax \(IVA\) included/.test(text), 'the note on colones and IVA');
      assert.strictEqual(await aviso(pg), '', 'no warning while the prices are verified');
      /* only reads the menu: no sign-in, no write, no function call; the real Supabase is never reached */
      assert.ok(pg.api.length >= 1 && pg.api.every((r) => r === 'GET /rest/v1/menu_categories'), 'only reads of the menu: ' + [...new Set(pg.api)].join(', '));
      assert.strictEqual(pg.supabaseHits, 0);
      /* this TV keeps the names for a start without internet, never the prices */
      const copia = await pg.evaluate(() => localStorage.getItem('hg-pantalla-menu'));
      assert.ok(copia && JSON.parse(copia).cats.length >= 8, 'the names are kept on the device');
      assert.ok(!/precio|price|₡|"\d{3,}/.test(copia), 'no price is kept on the device: ' + copia.slice(0, 120));
      const i = await info(pg);
      assert.deepStrictEqual([i.tiempos.cada, i.tiempos.fresco, i.tiempos.vencido, i.paginaMs], [30000, 120000, 600000, 28000],
        'reads every 30 s; prices shown up to 2 min, «por confirmar» up to 10 min; a page every 28 s');
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
        const pg = await pantalla(browser, { viewport: { width: w, height: h }, q: `?pulgadas=55&distancia=3&giro=${giro}` });
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
      const find = async (es) => items(await contenido(pg)).find((g) => g.es === es);
      assert.ok(await find('Latte'));
      sql(`update menu_items set available = false where name = 'Latte'; update menu_items set price_crc = 1600 where name = 'Americano';`);
      await until(async () => !(await find('Latte')), 8000, 'the sold-out Latte left the screen');
      await until(async () => digits((await find('Americano')).pr) === 1600, 8000, 'the new price of the Americano');
      sql(`update menu_items set available = true where name = 'Latte'`);
      await until(async () => !!(await find('Latte')), 8000, 'the Latte back');
      assert.ok(pg.api.every((r) => r === 'GET /rest/v1/menu_categories'));
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'A4: without a connection the prices stay only while recent, then «Precios por confirmar en caja», then no price at all; they come back by themselves',
    run: async ({ browser, setOffline }) => {
      const T = { cada: 400, fresco: 2500, vencido: 5000, revisar: 150 };
      const pg = await pantalla(browser, { test: T });
      const i0 = await info(pg);
      setOffline(true);
      const t0 = Date.now();
      await until(async () => (await info(pg)).estado === 'por-confirmar', 8000, '«por confirmar»');
      let i = await info(pg);
      assert.ok(Date.now() - t0 >= T.fresco - 600 && i.edadMs > T.fresco, 'prices count as verified only up to the limit');
      assert.deepStrictEqual([i.paginas, i.capCm, i.partes], [i0.paginas, i0.capCm, i0.partes], 'the warning moves nothing: same pages, same letter');
      assert.ok(await pg.evaluate(() => { const a = document.getElementById('aviso'); return a.scrollWidth <= a.clientWidth + 1 && a.getBoundingClientRect().bottom <= document.querySelector('header').getBoundingClientRect().bottom + 1; }),
        'the warning fits its place');
      assert.strictEqual(await aviso(pg), 'Precios por confirmar en caja Please confirm prices at the counter');
      assert.ok(items(await contenido(pg)).every((g) => digits(g.pr) > 0), 'the prices stay, marked to be confirmed');
      await until(async () => (await info(pg)).estado === 'sin-verificar', 8000, 'no verified prices');
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
      await off.evaluate(() => { const v = JSON.parse(localStorage.getItem('hg-pantalla-menu')); v.at = Date.now() - 4 * 86400000; localStorage.setItem('hg-pantalla-menu', JSON.stringify(v)); });
      await off.close();
      setOffline(true);
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
      let pg = await pantalla(browser, { q: '?pulgadas=55&distancia=3&look=dia' });
      assert.ok(await pg.evaluate(() => document.getElementById('stage').classList.contains('dia')));
      assert.ok(await pg.evaluate(() => document.getElementById('diag').hidden), 'no diagnosis box for the guests');
      await pg.context().close();
      pg = await pantalla(browser, { q: '?pulgadas=55&distancia=3&look=noche' });
      assert.ok(!(await pg.evaluate(() => document.getElementById('stage').classList.contains('dia'))));
      await pg.context().close();
      pg = await pantalla(browser, { q: '?tv=menu-1&pulgadas=abc&distancia=40&giro=arriba&diag=1' });
      const d = await pg.evaluate(() => document.getElementById('diag').innerText);
      assert.ok(/menu-1/.test(d) && /55" · 3 m/.test(d) && /mayúscula \d+\.\d\d cm \(mínimo 2\.40, meta 3\.00\)/.test(d), d);
      assert.ok(/Ajustes no válidos: pulgadas=abc, distancia=40, giro=arriba/.test(d), d);
      assert.deepStrictEqual(pg.errors, []);
    }
  }
];
