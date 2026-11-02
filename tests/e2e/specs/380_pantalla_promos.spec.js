/* Screen B (website/pantalla-promos.html, docs/PANTALLAS.md, migrations 0036 and 0037): products, brand, invitations
   and compositions (1 to 4 zones, each a presentation of its own) for the guests. The owner's conditions it is held to here:
   3) names, prices, photos and availability read only from the menu (through pantalla_datos), never written; it polls;
   4) a lost connection or old data never shows an expired slide or an unverified price as current;
   5) read from a distance: big prices, little else, nothing outside the screen;
   6) nothing new: the site, the public key and the TV's browser; nothing stored on the device;
   7) combos and discounts never announced (the till's helpers never show).
   P1-P17: the slides of 0036. P18-P29: the compositions of 0037 (templates, independent presentations, labels and
   live prices, what cannot show, the dwell, the owner's preview, the dissolve, photos that hang or fail, the turns
   across stays, the café's 32" TV read from 3 m).
   Slides are written straight into the test database (as its superuser): pantallas.html, which writes them for the
   owner, has its own tests. */
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const { page, goto, until, sql, SITE } = require('../lib');

const API_PORT = String(Number(process.env.E2E_SITE_PORT || 8090) + 1000);
const PGRST = 'http://127.0.0.1:' + (process.env.E2E_PGRST_PORT || 3013);
const READ = 'GET /rest/v1/rpc/pantalla_datos';
const LARGO_CM = (pulgadas) => pulgadas * 2.54 * 16 / Math.sqrt(337);   /* long side of a 16:9 screen */
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const digits = (s) => Number(String(s || '').replace(/\D/g, '')) || 0;
const H6 = 6 * 3600000, DAY = 86400000;
const crMin = (ms) => (((Math.floor((ms - H6) / 60000)) % 1440) + 1440) % 1440;
const hhmm = (m) => { m = ((m % 1440) + 1440) % 1440; return String(Math.floor(m / 60)).padStart(2, '0') + ':' + String(m % 60).padStart(2, '0'); };
const RESENA = 'https://www.tripadvisor.com/UserReview-g951347-d34058072-The_hanging_garden_cafe-Monteverde_Province_of_Puntarenas.html';
const MENU_QR = 'https://hanginggardencafe.com/m';
const NOTA = 'Precio por confirmar en caja · Please confirm the price at the counter';
const PIDA = 'Pídalo en la caja · Order at the counter';
/* a small real image for every photo (they live on hosts the tests never reach) */
const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAQAAAADCAIAAAA7ljmRAAAAEElEQVR4nGOQ8zaGIwacHACNwwdR68r19QAAAABJRU5ErkJggg==', 'base64');

/* qrcode-generator 1.4.4 for the page: the real file when the test machine has it (E2E_QRCODE_JS, or an installed
   copy), otherwise a stand-in with the same calls (qrcode(type, level), addData, make, getModuleCount, isDark) that
   draws finder patterns and a fixed pattern of the right size. Either way a recorder keeps what the page asked to
   encode. */
const QR_REAL = (() => {
  for (const p of [process.env.E2E_QRCODE_JS, path.join(__dirname, '../node_modules/qrcode-generator/qrcode.js'),
                   '/opt/node22/lib/node_modules/qrcode-generator/qrcode.js'].filter(Boolean)) {
    try { if (fs.existsSync(p)) return fs.readFileSync(p, 'utf8'); } catch (e) {}
  }
  return null;
})();
const QR_STANDIN = `var qrcode = function (type, level) {
  var data = '', n = 0, m = null;
  return {
    addData: function (d) { data += String(d); },
    make: function () {
      var cap = [14, 26, 42, 62, 84, 106, 122, 152, 180, 213], v = 1;   /* byte capacity per version, level M */
      while (v < cap.length && cap[v - 1] < data.length) v++;
      n = 17 + 4 * v; m = [];
      var h = 2166136261;
      for (var i = 0; i < data.length; i++) { h ^= data.charCodeAt(i); h = Math.imul(h, 16777619) >>> 0; }
      var finder = function (r, c) {
        var f = [[0, 0], [0, n - 7], [n - 7, 0]];
        for (var k = 0; k < 3; k++) {
          var y = r - f[k][0], x = c - f[k][1];
          if (y >= -1 && y <= 7 && x >= -1 && x <= 7) {
            if (y < 0 || y > 6 || x < 0 || x > 6) return 0;
            return (y === 0 || y === 6 || x === 0 || x === 6 || (y >= 2 && y <= 4 && x >= 2 && x <= 4)) ? 1 : 0;
          }
        }
        return -1;
      };
      for (var r = 0; r < n; r++) {
        m.push([]);
        for (var c = 0; c < n; c++) {
          var f = finder(r, c);
          if (f >= 0) { m[r].push(f === 1); continue; }
          var x = (h ^ Math.imul(r + 1, 73856093) ^ Math.imul(c + 1, 19349663)) >>> 0;
          x ^= x >>> 13; x = Math.imul(x, 1274126177) >>> 0; m[r].push((x >>> 7) % 2 === 1);
        }
      }
    },
    getModuleCount: function () { return n; },
    isDark: function (r, c) { return m[r][c]; }
  };
};`;
const QR_RECORDER = `;(function () {
  var q = window.qrcode; if (typeof q !== 'function') return;
  window.__qrDatos = [];
  window.qrcode = function (t, e) {
    var o = q(t, e), add = o.addData;
    o.addData = function (d) { window.__qrDatos.push(String(d)); return add.apply(o, arguments); };
    return o;
  };
  Object.keys(q).forEach(function (k) { window.qrcode[k] = q[k]; });
})();`;
const QR_JS = (QR_REAL || QR_STANDIN) + '\n' + QR_RECORDER;

/* the screen on its own device; every call to the database stand-in is kept (method and path) */
async function pantalla(browser, opts) {
  opts = opts || {};
  const pg = await page(browser, { context: opts.context, viewport: opts.viewport || { width: 1920, height: 1080 }, station: null, lang: 'es' });
  pg.api = [];
  pg.on('request', (r) => { const u = new URL(r.url()); if (u.port === API_PORT) pg.api.push(r.method() + ' ' + u.pathname); });
  /* photos: a small image, or a 404 for a name with «roto» (a broken link) */
  await pg.route(/^https:\/\/fotos\.test\//, (r) => (/roto/.test(r.request().url()) ? r.fulfill({ status: 404, body: 'not found' })
    : r.fulfill({ status: 200, contentType: 'image/png', body: PNG })));
  if (opts.qr === false) await pg.route(/cdnjs\.cloudflare\.com\//, (r) => r.abort());
  else await pg.route(/cdnjs\.cloudflare\.com\//, (r) => (/\/ajax\/libs\/qrcode-generator\/1\.4\.4\/qrcode\.min\.js$/.test(r.request().url())
    ? r.fulfill({ status: 200, contentType: 'application/javascript', body: QR_JS }) : r.abort()));
  if (opts.test) await pg.addInitScript((t) => { window.PANTALLA_TEST = t; }, opts.test);
  if (opts.setup) await opts.setup(pg);
  if (opts.url) { await pg.goto(opts.url, { waitUntil: 'domcontentloaded' }); return pg; }   /* another page (a frame's parent) */
  await goto(pg, '/pantalla-promos' + (opts.q === undefined ? '?tv=promos-1&pulgadas=55&distancia=3' : opts.q));
  await until(() => pg.evaluate(() => !!window.PANTALLA_B), 10000, 'the page script');
  if (opts.wait !== false) await until(() => pg.evaluate(() => PANTALLA_B.info().buenas > 0), 15000, 'the first good read');
  return pg;
}
const info = (pg) => pg.evaluate(() => PANTALLA_B.info());
/* what the slide on screen shows */
const vista = (pg) => pg.evaluate(() => {
  const sl = document.querySelector('#stage:not(.apagado) .capa.on .sl');
  if (!sl) return null;
  const t = (s) => { const e = sl.querySelector(s); return e ? e.textContent : null; };
  return { id: sl.dataset.id, kind: sl.dataset.kind, claro: sl.classList.contains('claro'), kick: t('.kick'), tit: t('.tit'), titEn: t('.tit-en'),
           cuerpo: t('.cuerpo'), cuerpoEn: t('.cuerpo-en'), precio: t('.precio'), cur: t('.precio .cur'), nota: t('.nota'), pida: t('.pida'),
           lugar: t('.lugar'), foto: (sl.querySelector('img.foto') || {}).src || null, qr: !!sl.querySelector('.qrcard svg'),
           dir: [...sl.querySelectorAll('.dir, .dirsola')].map((e) => e.textContent), solo: !!sl.querySelector('.qrcol.sinqr'),
           text: sl.innerText };
});
const stageText = (pg) => pg.evaluate(() => document.getElementById('stage').innerText);
const diag = (pg) => pg.evaluate(() => document.getElementById('diag').innerText);
const onlyReads = (pg) => pg.api.length > 0 && pg.api.every((r) => r === READ);
const mostrar = async (pg, id) => assert.ok(await pg.evaluate((i) => PANTALLA_B.mostrar(i), id), 'shown: ' + id);
const q = (v) => (v == null ? 'null' : "'" + String(v).replace(/'/g, "''") + "'");
const arr = (a) => (a == null ? 'null' : q('{' + a.join(',') + '}'));
/* a slide written straight into the database; returns its id */
function diapo(o) {
  return sql(`with x as (insert into public.screen_slides (kind, menu_item_id, kicker_es, kicker_en, title_es, title_en, body_es, body_en,
                                   photo_url, link, screen_ids, starts_at, ends_at, days, from_time, to_time, sort, status)
    values (${q(o.kind)}, ${o.item ? `(select id from public.menu_items where name = ${q(o.item)})` : 'null'},
            ${q(o.kicker_es)}, ${q(o.kicker_en)}, ${q(o.title_es)}, ${q(o.title_en)}, ${q(o.body_es)}, ${q(o.body_en)},
            ${q(o.photo)}, ${q(o.link)}, ${arr(o.screens)}, ${o.starts || "now() - interval '1 hour'"}, ${o.ends || "now() + interval '1 day'"},
            ${arr(o.days)}, ${q(o.from)}, ${q(o.to)}, ${o.sort == null ? 100 : o.sort}, ${q(o.status || 'activa')}) returning id) select id from x`);
}
const marca = (title, o) => diapo(Object.assign({ kind: 'marca', title_es: title, title_en: title + ' (en)' }, o || {}));
const epoch = (id, col) => Number(sql(`select (extract(epoch from ${col}) * 1000)::bigint from public.screen_slides where id = '${id}'`));
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
  await until(async () => (await fetch(PGRST + '/rpc/pantalla_datos?p_tv=promos-1')).status === 404, 10000, 'PostgREST without pantalla_datos');
}
/* the next time a Costa Rica weekday (1 Monday … 7 Sunday) is at hh:mm, within the next 8 days */
function enCR(wd, h, m) {
  for (let k = 1; k <= 8; k++) {
    const d = new Date(Date.now() - H6 + k * DAY);
    if ((d.getUTCDay() || 7) === wd) return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate(), h, m) + H6;
  }
  throw new Error('no such day');
}
/* every text of the slide on screen: its capital in px, its box on the screen, whether it is cut */
const medir = (pg) => pg.evaluate(() => {
  const cx = document.createElement('canvas').getContext('2d');
  const cap = (e) => { const cs = getComputedStyle(e); cx.font = cs.fontWeight + ' ' + cs.fontSize + ' ' + cs.fontFamily; return cx.measureText('H').actualBoundingBoxAscent; };
  const sl = document.querySelector('.capa.on .sl'), W = innerWidth, H = innerHeight;
  const out = { id: sl.dataset.id, kind: sl.dataset.kind, textos: [], fuera: [], cortados: [], qr: null };
  sl.querySelectorAll('[data-r]').forEach((e) => {
    if (!e.getClientRects().length) return;
    const r = e.getBoundingClientRect();
    out.textos.push({ r: e.dataset.r, cap: cap(e), t: e.textContent, lines: Math.round(e.offsetHeight / parseFloat(getComputedStyle(e).lineHeight)) });
    if (r.left < -1 || r.top < -1 || r.right > W + 1 || r.bottom > H + 1) out.fuera.push(e.textContent + ' @' + [r.left, r.top, r.right, r.bottom].map(Math.round));
    if (e.scrollWidth > e.clientWidth + 1) out.cortados.push(e.textContent);
  });
  const svg = sl.querySelector('.qrcard svg');
  if (svg) {
    const col = sl.querySelector('.qrcol'), n = Number(col.dataset.modulos), r = svg.getBoundingClientRect();
    const dirs = [...sl.querySelectorAll('.dir')].map((d) => d.getBoundingClientRect());
    const px = parseFloat(getComputedStyle(svg).width);   /* an SVG element has no offsetWidth */
    out.qr = { n, px, side: px * n / (n + 8), rect: [r.left, r.top, r.right, r.bottom],
               dentro: r.left >= -1 && r.top >= -1 && r.right <= W + 1 && r.bottom <= H + 1, dirs: dirs.map((d) => [d.left, d.top, d.right, d.bottom]) };
  }
  return out;
});

/* ---------- compositions (0037) ---------- */
const itemId = (name) => sql(`select id from public.menu_items where name = ${q(name)}`);
const sqlJson = (query) => JSON.parse(sql(query));
/* a composition written straight into the database, its zones as the owner's panel stores them (products by name;
   a string entry is a photo when it is an address, a product otherwise); returns its id */
function compo(o) {
  const entry = (e) => {
    if (typeof e === 'string') return /^https?:/.test(e) ? { item: null, photo: e, focus: [50, 50], zoom: 100 } : { item: itemId(e), photo: null, focus: [50, 50], zoom: 100 };
    return { item: e.item ? itemId(e.item) : null, photo: e.photo || null, focus: e.focus || [50, 50], zoom: e.zoom || 100 };
  };
  const zones = o.zones.map((z) => ({ mode: z.mode || 'fija', seconds: z.seconds == null ? 8 : z.seconds, labels: z.labels !== false,
                                       fallback: z.fallback || null, entries: z.entries.map(entry) }));
  return sql(`with x as (insert into public.screen_slides (kind, template, zones, dwell_seconds, kicker_es, kicker_en, screen_ids, starts_at, ends_at,
                                   days, from_time, to_time, sort, status)
    values ('composicion', ${q(o.template)}, ${q(JSON.stringify(zones))}::jsonb, ${o.dwell == null ? 'null' : o.dwell}, ${q(o.kicker_es)}, ${q(o.kicker_en)},
            ${arr(o.screens)}, ${o.starts || "now() - interval '1 hour'"}, ${o.ends || "now() + interval '1 day'"},
            ${arr(o.days)}, ${q(o.from)}, ${q(o.to)}, ${o.sort == null ? 100 : o.sort}, ${q(o.status || 'activa')}) returning id) select id from x`);
}
/* a slide exactly as pantalla_datos gives it to the screens (the owner's panel posts this shape to the preview) */
const slideJson = (id) => sqlJson(`select public._slide_json(d)::text from public.screen_slides d where id = '${id}'`);
const fotos = (pre, n) => Array.from({ length: n }, (_, i) => `https://fotos.test/${pre}${i}.png`);
const PLAZAS = { '1': 1, '2-lado': 2, '3-grande-izq': 3, '3-grande-der': 3, '4-cuadricula': 4, '4-centro': 4 };
/* the composition on screen: each zone's place (px inside the stage), what it shows and its two image layers */
const zonas = (pg) => pg.evaluate(() => {
  const sl = document.querySelector('#stage:not(.apagado) .capa.on .sl.k-composicion');
  if (!sl) return null;
  const st = document.getElementById('stage'), W = innerWidth, H = innerHeight;
  const cx = document.createElement('canvas').getContext('2d');
  const cap = (e) => { const cs = getComputedStyle(e); cx.font = cs.fontWeight + ' ' + cs.fontSize + ' ' + cs.fontFamily; return cx.measureText('H').actualBoundingBoxAscent; };
  return {
    id: sl.dataset.id, template: sl.dataset.template, kick: (sl.querySelector('.zkick') || {}).textContent || null, sup: (sl.querySelector('.sup') || {}).textContent || null,
    stage: [st.offsetWidth, st.offsetHeight], text: sl.innerText,
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
const compoInfo = (pg) => pg.evaluate(() => PANTALLA_B.info().composicion);
/* every zone of the composition on screen is at rest (one layer up, no dissolve under way) */
const quieta = (z) => !!z && z.zonas.every((x) => x.capas.filter((c) => c.on).length === 1);
/* samples what each zone shows every `cada` ms for `ms` ms */
async function muestrear(pg, ms, cada) {
  const out = [], t0 = Date.now();
  while (Date.now() - t0 < ms) { const z = await zonas(pg); out.push({ t: Date.now() - t0, z }); await sleep(cada || 40); }
  return out;
}
/* the moments (ms into the sampling) a zone's entry changed */
const cambios = (muestras, i) => muestras.filter((m, k) => k > 0 && m.z && muestras[k - 1].z && m.z.zonas[i].entrada !== muestras[k - 1].z.zonas[i].entrada).map((m) => m.t);

module.exports.tests = [
  {
    name: 'P1: no slide in force: the built-in brand slide «Hanging Garden Café · Monteverde, Costa Rica», no price, no date; only GET reads of pantalla_datos; nothing stored on the device; the real timings',
    run: async ({ browser }) => {
      const pg = await pantalla(browser);
      const i = await info(pg);
      assert.deepStrictEqual([i.actual, i.visibles, i.estado, i.fuente, i.razon, i.horaDe], ['marca', [], 'al-dia', 'db', null, 'servidor']);
      const v = await vista(pg);
      assert.deepStrictEqual([v.kind, v.tit, v.lugar, v.precio, v.foto], ['propia', 'Hanging Garden Café', 'Monteverde, Costa Rica', null, null]);
      const text = await stageText(pg);
      assert.ok(!/₡|\d/.test(text), 'no price and no date on the screen: ' + text);
      assert.deepStrictEqual([i.tiempos.cada, i.tiempos.fresco, i.tiempos.vencido, i.tiempos.revisar, i.tiempos.limite, i.diapositivaMs, i.salto],
        [30000, 120000, 600000, 1000, 12000, 10000, 3000], 'reads every 30 s (12 s limit); price 2 min, «por confirmar» to 10 min; checked every second; 10 s a slide');
      await sleep(1500);
      assert.ok(onlyReads(pg), 'only GET pantalla_datos: ' + [...new Set(pg.api)].join(', '));
      assert.strictEqual(pg.supabaseHits, 0);
      const kept = await pg.evaluate(() => [Object.keys(localStorage), Object.keys(sessionStorage)]);
      assert.deepStrictEqual(kept, [['hg_lang'], []], 'nothing kept on the device but the test\'s own language key: ' + JSON.stringify(kept));
      assert.ok(await pg.evaluate(() => document.getElementById('diag').hidden), 'no diagnosis box for the guests');
      assert.ok(await pg.evaluate(() => document.querySelector('meta[name="robots"]').content === 'noindex' && document.querySelector('meta[name="hg-build"]').content === '__BUILD__'));
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'P2: a product slide: the live name (Spanish first, English below only if different), price (₡ at 80 %) and photo; «Pídalo en la caja»; a new price, a new photo, a sold-out item and its return show on the next read by themselves',
    run: async ({ browser }) => {
      sql(`update public.menu_items set name_es = 'Pan de banano casero', photo_url = 'https://fotos.test/banana.png' where name = 'Banana Bread'`);
      const banana = diapo({ kind: 'producto', item: 'Banana Bread', kicker_es: 'Recién horneado', kicker_en: 'Freshly baked', sort: 1 });
      const latte = diapo({ kind: 'producto', item: 'Latte', sort: 2 });
      const capu = diapo({ kind: 'producto', item: 'Cappuccino', sort: 3 });
      const pg = await pantalla(browser, { test: { cada: 1000, diapositiva: 600000 } });
      let i = await info(pg);
      assert.deepStrictEqual([i.actual, i.visibles], [banana, [banana, latte, capu]], 'in the order of the slides');
      let v = await vista(pg);
      assert.deepStrictEqual([v.kind, v.kick, v.tit, v.titEn, digits(v.precio), v.cur, v.pida, v.nota, v.claro],
        ['producto', 'Recién horneado · Freshly baked', 'Pan de banano casero', 'Banana Bread', 1500, '₡', PIDA, null, false]);
      assert.ok(/^₡1\s?500$/.test(v.precio), 'the price as on the menu: ' + v.precio);
      assert.strictEqual(v.foto, 'https://fotos.test/banana.png', 'the item\'s photo');
      const ratio = await pg.evaluate(() => { const p = document.querySelector('.capa.on .precio'); return parseFloat(getComputedStyle(p.querySelector('.cur')).fontSize) / parseFloat(getComputedStyle(p).fontSize); });
      assert.ok(Math.abs(ratio - 0.8) < 0.01, 'the ₡ at 80 %: ' + ratio);
      await mostrar(pg, latte);
      v = await vista(pg);
      assert.deepStrictEqual([v.tit, v.titEn, digits(v.precio), v.kick, v.foto], ['Latte', null, 2200, null, null], 'a name the same in both languages, once; no photo: the brand background');
      await mostrar(pg, capu);
      v = await vista(pg);
      assert.deepStrictEqual([v.tit, v.titEn, digits(v.precio)], ['Capuchino', 'Cappuccino', 2000], 'Spanish from the site\'s dictionary');
      await mostrar(pg, banana);
      /* the Menu Manager changes: the screen follows on its next read, without being reloaded */
      sql(`update public.menu_items set price_crc = 1650 where name = 'Banana Bread'`);
      await until(async () => digits((await vista(pg)).precio) === 1650, 8000, 'the new price on screen');
      assert.strictEqual((await info(pg)).actual, banana, 'drawn again in place');
      sql(`update public.screen_slides set photo_url = 'https://fotos.test/promo.png' where id = '${banana}'`);
      await until(async () => (await vista(pg)).foto === 'https://fotos.test/promo.png', 8000, 'the slide\'s own photo first');
      await until(() => pg.evaluate(() => document.querySelector('.capa.on img.foto').classList.contains('ok')), 3000, 'the photo loaded and shows');
      sql(`update public.screen_slides set photo_url = 'https://fotos.test/roto.png' where id = '${banana}'`);
      await until(async () => { const j = await vista(pg); return j.id === banana && j.foto === null; }, 8000, 'a broken photo: the brand background');
      assert.strictEqual(digits((await vista(pg)).precio), 1650, 'the slide stays, with its price');
      sql(`update public.menu_items set available = false where name = 'Banana Bread'`);
      await until(async () => { const j = await info(pg); return !j.visibles.includes(banana) && j.actual === latte; }, 8000, 'the sold-out item gone at once');
      assert.ok(!/banano|Banana/.test(await stageText(pg)));
      sql(`update public.menu_items set available = false where name in ('Latte', 'Cappuccino')`);
      await until(async () => (await info(pg)).actual === 'marca', 8000, 'nothing to sell: the brand slide');
      assert.ok(!/₡/.test(await stageText(pg)));
      sql(`update public.menu_items set available = true where name = 'Banana Bread'`);
      await until(async () => { const j = await vista(pg); return j.id === banana && digits(j.precio) === 1650; }, 8000, 'back in stock');
      assert.ok(onlyReads(pg), [...new Set(pg.api)].join(', '));
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'P3: brand and invitation slides: Spanish then English, never a price; an invitation carries a QR code (review page or QR menu) dark on light with a quiet zone, at least a tenth of the distance wide, its short address under it; without the QR library, the address in text',
    run: async ({ browser }) => {
      const m = diapo({ kind: 'marca', kicker_es: 'Nuestro café', kicker_en: 'Our coffee', title_es: 'Café de altura de Monteverde', title_en: 'Highland coffee from Monteverde',
                        body_es: 'Tostado aquí, a pasos del bosque nuboso', body_en: 'Roasted here, steps from the cloud forest', sort: 1 });
      const r = diapo({ kind: 'invitacion', link: 'resena', title_es: '¿Le gustó su visita?', title_en: 'Loved your visit?', body_es: 'Cuéntelo en Tripadvisor', body_en: 'Tell others on Tripadvisor', sort: 2 });
      const mq = diapo({ kind: 'invitacion', link: 'menu', title_es: 'El menú en su teléfono', title_en: 'The menu on your phone', sort: 3 });
      const pg = await pantalla(browser, { test: { diapositiva: 600000 } });
      assert.deepStrictEqual((await info(pg)).visibles, [m, r, mq]);
      let v = await vista(pg);
      assert.deepStrictEqual([v.kind, v.kick, v.tit, v.titEn, v.cuerpo, v.cuerpoEn, v.precio, v.claro],
        ['marca', 'Nuestro café · Our coffee', 'Café de altura de Monteverde', 'Highland coffee from Monteverde', 'Tostado aquí, a pasos del bosque nuboso',
         'Roasted here, steps from the cloud forest', null, true], 'no photo: on the brand background');
      assert.ok(!/₡/.test(v.text));
      const pxCm = 1920 / LARGO_CM(55);
      for (const [id, url, dir] of [[r, RESENA, ['tripadvisor.com', 'Hanging Garden Café']], [mq, MENU_QR, ['hanginggardencafe.com/m']]]) {
        await mostrar(pg, id);
        v = await vista(pg);
        assert.deepStrictEqual([v.kind, v.qr, v.dir, v.precio], ['invitacion', true, dir, null], url);
        assert.strictEqual(await pg.evaluate(() => window.__qrDatos[window.__qrDatos.length - 1]), url, 'the code holds ' + url);
        const k = await medir(pg);
        assert.ok(k.qr.side / pxCm >= 30 - 0.05, `the code is at least 30 cm wide for 3 m: ${(k.qr.side / pxCm).toFixed(1)} cm`);
        assert.ok(k.qr.dentro && k.qr.dirs.every((d) => d[1] >= k.qr.rect[3] - 1), 'the code on the screen, the address under it: ' + JSON.stringify(k.qr));
        assert.ok(k.qr.dirs.every((d) => d[0] >= 0 && d[2] <= 1920), 'the address on the screen');
        const z = await pg.evaluate(() => {
          const svg = document.querySelector('.capa.on .qrcard svg'), n = Number(document.querySelector('.capa.on .qrcol').dataset.modulos);
          const d = svg.querySelector('path').getAttribute('d'), xs = [], ys = [];
          d.replace(/M(\d+) (\d+)h(\d+)/g, (_, x, y, w) => { xs.push(+x, +x + +w); ys.push(+y, +y + 1); });
          return { n, vb: svg.getAttribute('viewBox'), min: Math.min(...xs, ...ys), max: Math.max(...xs, ...ys), bg: svg.querySelector('rect').getAttribute('fill'),
                   ink: svg.querySelector('path').getAttribute('fill'), card: getComputedStyle(svg.parentNode).backgroundColor, crisp: svg.getAttribute('shape-rendering'),
                   whole: parseFloat(getComputedStyle(svg).width) % (n + 8) === 0 };
        });
        assert.deepStrictEqual([z.vb, z.min >= 4, z.max <= z.n + 4, z.bg, z.ink, z.card, z.crisp, z.whole],
          [`0 0 ${z.n + 8} ${z.n + 8}`, true, true, '#ffffff', '#0B1A10', 'rgb(255, 255, 255)', 'crispEdges', true],
          'dark modules on white, 4 modules of quiet zone, whole pixels: ' + JSON.stringify(z));
      }
      assert.strictEqual((await info(pg)).qr, 'listo');
      assert.ok(onlyReads(pg));
      assert.deepStrictEqual(pg.errors, []);
      await pg.context().close();
      /* the library could not be loaded (no internet when the TV started, a CDN problem): the address, in text */
      const pg2 = await pantalla(browser, { qr: false, test: { diapositiva: 600000 } });
      await until(async () => (await info(pg2)).qr === 'falta', 5000, 'the library missing');
      await mostrar(pg2, r);
      v = await vista(pg2);
      assert.deepStrictEqual([v.kind, v.qr, v.solo, v.dir, v.tit], ['invitacion', false, true, ['tripadvisor.com', 'Hanging Garden Café'], '¿Le gustó su visita?']);
      const k = await medir(pg2);
      assert.deepStrictEqual([k.fuera, k.cortados], [[], []]);
      assert.deepStrictEqual(pg2.errors, []);
    }
  },
  {
    name: 'P4: paused, retired, ended, not yet started, other TVs\' slides and products that cannot be sold (sold out, price 0, the till\'s Extras & Combos) never show',
    run: async ({ browser }) => {
      const ok1 = marca('Para esta TV', { screens: ['promos-1'], sort: 1 });
      const ok2 = marca('Para todas', { sort: 2 });
      const ok3 = marca('Para todas, desde antes', { sort: 2, starts: "now() - interval '2 hours'" });   /* same order: the earlier start first */
      const bad = [marca('Pausada', { status: 'pausada' }), marca('Retirada', { status: 'retirada' }), marca('Otra TV', { screens: ['promos-2'] }),
                   marca('Vencida', { starts: "now() - interval '2 days'", ends: "now() - interval '1 minute'" })];
      const later = marca('Más tarde', { starts: "now() + interval '2 hours'", ends: "now() + interval '1 day'" });
      sql(`update public.menu_items set available = false where name = 'Tea'; update public.menu_items set price_crc = 0 where name = 'Sweet Cane Drink'`);
      const prods = ['Tea', 'Sweet Cane Drink', 'Flavor shot', 'Combo discount · coffee + pastry'].map((n) => diapo({ kind: 'producto', item: n, sort: 0 }));
      const pg = await pantalla(browser, { test: { diapositiva: 1500, revisar: 200 } });
      const i = await info(pg);
      assert.deepStrictEqual(i.visibles, [ok1, ok3, ok2], 'only the three in force for this TV, by order then start');
      assert.deepStrictEqual(i.leidas, [ok1, ok3, ok2, later], 'the read brings one starting within a day, never the others');
      const seen = new Set(), texts = new Set();
      for (let k = 0; k < 40; k++) {
        const v = await vista(pg); seen.add(v.id); texts.add(v.text);
        await sleep(120);
      }
      assert.deepStrictEqual([...seen].sort(), [ok1, ok2, ok3].sort(), 'they take turns, nothing else shows');
      const all = [...texts].join(' | ');
      assert.ok(!/Pausada|Retirada|Otra TV|Vencida|Más tarde|₡|Tea|Té|Sweet|Agua dulce|Flavor|Combo/i.test(all), all);
      assert.ok(![...bad, ...prods].some((id) => i.leidas.includes(id)));
      assert.ok(onlyReads(pg));
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'P5: with the network down, a slide on screen disappears by itself when it ends, and one that starts appears by itself when it starts, on time by the server\'s clock',
    run: async ({ browser, setOffline }) => {
      const a = marca('Termina pronto', { ends: "now() + interval '7 seconds'", sort: 1 });
      const b = marca('Empieza pronto', { starts: "now() + interval '10 seconds'", ends: "now() + interval '1 day'", sort: 2 });
      const fin = epoch(a, 'ends_at'), inicio = epoch(b, 'starts_at');
      const pg = await pantalla(browser, { test: { cada: 1000, revisar: 200, diapositiva: 600000 } });
      assert.deepStrictEqual([(await info(pg)).actual, (await info(pg)).leidas], [a, [a, b]]);
      setOffline(true);
      await until(async () => (await info(pg)).actual !== a, 12000, 'the ended slide gone');
      const t1 = Date.now();
      assert.ok(t1 >= fin - 300 && t1 <= fin + 1500, `gone at its end: ${t1 - fin} ms`);
      const v = await vista(pg);
      assert.strictEqual(v.kind, 'propia', 'nothing else in force: the brand slide');
      assert.ok(await pg.evaluate(() => ![...document.querySelectorAll('.capa')].some((c) => getComputedStyle(c).visibility === 'visible' && /Termina pronto/.test(c.textContent))),
        'the ended slide is not visible at all (no fade)');
      await until(async () => (await info(pg)).actual === b, 12000, 'the new slide by itself');
      const t2 = Date.now();
      assert.ok(t2 >= inicio - 50 && t2 <= inicio + 1500, `shown at its start, never before: ${t2 - inicio} ms`);
      assert.strictEqual((await vista(pg)).tit, 'Empieza pronto');
      const i = await info(pg);
      assert.ok(i.intentos > i.buenas, 'the reads failed all along (no internet)');
      assert.ok(pg.api.every((r) => r === READ));
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'P6: days (1 Monday … 7 Sunday) and hours of Costa Rica, overnight hours too, by the server\'s clock on a device set to another time zone',
    run: async ({ browser }) => {
      const span = { starts: "now() - interval '20 days'", ends: "now() + interval '20 days'" };
      const vie = marca('Viernes', Object.assign({ days: [5], sort: 1 }, span));
      const sab = marca('Sábado', Object.assign({ days: [6], sort: 2 }, span));
      const man = marca('Mañana', Object.assign({ from: '09:00', to: '11:00', sort: 3 }, span));
      const noc = marca('Noche', Object.assign({ from: '20:00', to: '02:00', sort: 4 }, span));
      let base = enCR(5, 10, 0), t0 = Date.now();
      const ctx = await browser.newContext({ viewport: { width: 1920, height: 1080 }, locale: 'es-CR', timezoneId: 'Asia/Tokyo' });
      const pg = await pantalla(browser, { context: ctx, test: { cada: 500, revisar: 200, diapositiva: 600000 }, setup: relojServidor(() => base + Date.now() - t0) });
      assert.strictEqual(await pg.evaluate(() => Intl.DateTimeFormat().resolvedOptions().timeZone), 'Asia/Tokyo');
      const cases = [[5, 10, 0, [vie, man], 'Friday 10:00'], [5, 23, 30, [vie, noc], 'Friday 23:30'], [6, 1, 30, [sab, noc], 'Saturday 01:30'],
                     [6, 10, 59, [sab, man], 'Saturday 10:59'], [6, 11, 0, [sab], 'Saturday 11:00 (the end is not included)'],
                     [5, 8, 59, [vie], 'Friday 08:59'], [5, 9, 0, [vie, man], 'Friday 09:00'], [7, 2, 0, [], 'Sunday 02:00']];
      for (const [wd, h, m, want, what] of cases) {
        base = enCR(wd, h, m); t0 = Date.now();
        await until(async () => { const i = await info(pg); return i.horaCR === hhmm(h * 60 + m) && JSON.stringify(i.visibles) === JSON.stringify(want); }, 8000, what);
        const i = await info(pg);
        assert.ok(want.length ? want.includes(i.actual) : i.actual === 'marca', what + ': ' + i.actual);
      }
      assert.ok(onlyReads(pg));
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'P7: without a connection a product keeps its price while recent, then «Precio por confirmar en caja», then the product slide goes (sold out or repriced meanwhile) while brand slides go on; it comes back by itself',
    run: async ({ browser, setOffline }) => {
      const p = diapo({ kind: 'producto', item: 'Latte', kicker_es: 'Favorito', kicker_en: 'Favourite', sort: 1 });
      const m = marca('Pura vida', { sort: 2 });
      const T = { cada: 400, fresco: 2500, vencido: 5000, revisar: 150, diapositiva: 600000 };
      const pg = await pantalla(browser, { test: T });
      assert.strictEqual((await info(pg)).actual, p);
      setOffline(true);
      const t0 = Date.now();
      /* the screen checks every tick (150 ms here): wait for the note itself */
      await until(async () => (await info(pg)).estado === 'por-confirmar' && (await vista(pg)).nota === NOTA, 8000, '«por confirmar»');
      const dt = Date.now() - t0;
      assert.ok(dt >= T.fresco - T.cada - 600 && dt <= T.fresco + 1500, `the price counts as verified up to the limit (${dt} ms)`);
      let v = await vista(pg);
      assert.deepStrictEqual([v.id, digits(v.precio), v.nota], [p, 2200, NOTA], 'the price stays, to be confirmed');
      await until(async () => (await info(pg)).estado === 'sin-verificar', 8000, 'no verified price');
      assert.ok(Date.now() - t0 <= T.vencido + 1500);
      await until(async () => (await info(pg)).actual === m, 3000, 'the product slide gone at once');
      const i = await info(pg);
      assert.deepStrictEqual(i.visibles, [m], 'the brand slide goes on');
      await sleep(1500);
      assert.strictEqual(await pg.evaluate(() => document.querySelectorAll('.precio, .nota').length), 0, 'no price left anywhere in the page');
      assert.ok(!/₡|Latte/.test(await stageText(pg)));
      setOffline(false);
      await until(async () => { const j = await info(pg); return j.estado === 'al-dia' && j.visibles.includes(p); }, 8000, 'the product back');
      await mostrar(pg, p);
      v = await vista(pg);
      assert.deepStrictEqual([digits(v.precio), v.nota], [2200, null]);
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'P8: a cold start without internet: only the built-in brand slide (nothing was kept on the device), and it keeps trying; the slides come once the connection is back',
    run: async ({ browser, setOffline }) => {
      const p = diapo({ kind: 'producto', item: 'Latte', sort: 1 });
      const m = marca('Pura vida', { sort: 2 });
      /* the same device ran online first: it still keeps nothing that could show later */
      const ctx = await browser.newContext({ viewport: { width: 1920, height: 1080 }, locale: 'es-CR', timezoneId: 'America/Costa_Rica' });
      const on = await pantalla(browser, { context: ctx });
      assert.strictEqual((await info(on)).actual, p);
      await on.close();
      setOffline(true);
      for (const [q, fuente] of [['?tv=promos-1&pulgadas=55&distancia=3', 'direccion'], ['?tv=promos-1', 'omision']]) {
        const pg = await pantalla(browser, { context: ctx, q, wait: false, test: { cada: 500 } });
        await sleep(2000);
        const i = await info(pg);
        assert.deepStrictEqual([i.actual, i.visibles, i.estado, i.fuente, i.razon, i.buenas, i.horaDe], ['marca', [], 'sin-verificar', fuente, 'sin-lectura', 0, 'aparato'], q);
        assert.ok(i.intentos >= 3, 'it keeps trying: ' + i.intentos);
        const v = await vista(pg);
        assert.deepStrictEqual([v.kind, v.tit], ['propia', 'Hanging Garden Café']);
        assert.ok(!/₡|Latte|Pura vida/.test(await stageText(pg)));
        assert.deepStrictEqual(pg.errors, []);
        await pg.close();
      }
      const pg = await pantalla(browser, { context: ctx, wait: false, test: { cada: 500 } });
      await sleep(800);
      setOffline(false);
      await until(async () => { const i = await info(pg); return i.estado === 'al-dia' && i.actual === p && i.visibles.length === 2; }, 8000, 'the slides once online');
      assert.strictEqual(digits((await vista(pg)).precio), 2200);
      assert.deepStrictEqual(await pg.evaluate(() => Object.keys(localStorage)), ['hg_lang']);
      assert.ok(pg.api.every((r) => r === READ));
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'P9: the device clock moved back or forward (or a frozen clock) never brings back an ended slide; prices stay unverified until a read; the server\'s time sets it right',
    run: async ({ browser, setOffline }) => {
      const e = marca('Se acaba', { ends: "now() + interval '6 seconds'", sort: 1 });
      const l = marca('Larga', { ends: "now() + interval '3 days'", sort: 2 });
      const p = diapo({ kind: 'producto', item: 'Latte', sort: 3 });
      const fin = epoch(e, 'ends_at');
      const pg = await pantalla(browser, { test: { cada: 600000, revisar: 200, diapositiva: 600000 } });
      assert.deepStrictEqual((await info(pg)).visibles, [e, l, p]);
      setOffline(true);
      await until(async () => !(await info(pg)).visibles.includes(e), 12000, 'the slide ended');
      assert.ok(Date.now() >= fin - 300);
      const watch = async (what, ms) => {
        const end = Date.now() + ms;
        while (Date.now() < end) {
          const i = await info(pg);
          assert.ok(!i.visibles.includes(e) && i.actual !== e && i.ahora >= fin, what + ': the ended slide stays away ' + JSON.stringify([i.visibles, i.ahora - fin]));
          assert.ok(i.visibles.includes(l), what + ': the long one still in force');
          await sleep(150);
        }
      };
      await pg.evaluate(() => { const real = Date.now.bind(Date); Date.now = () => real() - 86400000; });
      await until(async () => (await info(pg)).dudoso, 3000, 'a clock jump makes prices unverified');
      await watch('clock a day back', 2000);
      assert.ok(!(await info(pg)).visibles.includes(p), 'no product after the jump');
      await pg.evaluate(() => { const p0 = performance.now(); performance.now = () => p0; });
      await watch('clock back and the monotonic clock frozen', 1500);
      await pg.evaluate(() => { const real = Date.now.bind(Date); Date.now = () => real() + 2 * 86400000; });
      await watch('clock a day forward', 1500);
      assert.deepStrictEqual(pg.errors, []);
      await pg.context().close();
      /* online again, a fresh device: the server says the slide is over, whatever the device's clock says */
      setOffline(false);
      const pg2 = await pantalla(browser, { test: { cada: 1000 }, setup: (x) => x.addInitScript(() => { const real = Date.now.bind(Date); Date.now = () => real() - 3600000; }) });
      const i = await info(pg2);
      assert.deepStrictEqual([i.visibles, i.horaDe], [[l, p], 'servidor'], 'the device thinks it is an hour earlier: still not shown');
      assert.deepStrictEqual(pg2.errors, []);
    }
  },
  {
    name: 'P10: the TV\'s hours (Costa Rica): outside them a black screen with nothing on it; overnight hours; the server\'s clock decides, not the device\'s',
    run: async ({ browser }) => {
      marca('Pura vida', { sort: 1 });
      const now = crMin(Date.now());
      const hours = (a, b) => sql(`update public.screens set on_from = '${hhmm(a)}', on_to = '${hhmm(b)}' where id = 'promos-1'`);
      const negro = (pg) => pg.evaluate(() => ({ text: document.body.innerText.trim(), nodes: document.querySelectorAll('.sl').length,
                                                 bg: getComputedStyle(document.body).backgroundColor, stage: getComputedStyle(document.getElementById('stage')).backgroundColor }));
      const BLACK = { text: '', nodes: 0, bg: 'rgb(0, 0, 0)', stage: 'rgb(0, 0, 0)' };
      hours(now - 60, now + 60);
      const pg = await pantalla(browser, { test: { cada: 500, revisar: 200 } });
      assert.ok(!(await info(pg)).apagado && (await vista(pg)).tit === 'Pura vida', 'inside its hours');
      hours(now + 60, now + 120);
      await until(async () => (await info(pg)).apagado, 8000, 'outside its hours');
      await sleep(300);
      assert.deepStrictEqual(await negro(pg), BLACK, 'a black screen');
      hours(now - 60, now - 120);                                /* from > to: overnight, open now */
      await until(async () => { const i = await info(pg); return !i.apagado && i.actual !== null; }, 8000, 'on again');
      assert.strictEqual((await vista(pg)).tit, 'Pura vida');
      hours(now + 60, now - 60);                                 /* overnight, closed now */
      await until(async () => (await info(pg)).apagado, 8000, 'off again');
      await sleep(300);
      assert.deepStrictEqual(await negro(pg), BLACK);
      assert.deepStrictEqual(pg.errors, []);
      await pg.context().close();
      /* 20:00 to 02:00 by the server's clock; the device's clock is 12 hours off and does not count */
      sql(`update public.screens set on_from = '20:00', on_to = '02:00' where id = 'promos-1';
           update public.screen_slides set starts_at = now() - interval '20 days', ends_at = now() + interval '20 days'`);
      let base = enCR(5, 23, 30), t0 = Date.now();
      const pg2 = await pantalla(browser, { q: '?tv=promos-1&diag=1', test: { cada: 500, revisar: 200 },
                                            setup: async (x) => { await x.addInitScript((ms) => { const real = Date.now.bind(Date), s = real(); Date.now = () => ms + (real() - s); }, Date.now() + 12 * 3600000);
                                                                  await relojServidor(() => base + Date.now() - t0)(x); } });
      let i = await info(pg2);
      assert.deepStrictEqual([i.apagado, i.horaDe, i.horaCR.slice(0, 4), i.tv.desde, i.tv.hasta], [false, 'servidor', '23:3', '20:00', '02:00'], 'open at 23:30');
      base = enCR(6, 3, 0); t0 = Date.now();
      await until(async () => (await info(pg2)).apagado, 8000, 'closed at 03:00');
      assert.ok(/Horario: 20:00–02:00 · APAGADA/.test(await diag(pg2)), await diag(pg2));
      assert.ok(await pg2.evaluate(() => document.body.innerText.trim() === document.getElementById('diag').innerText.trim()), 'nothing but the technician\'s box (diag=1)');
      base = enCR(6, 1, 59); t0 = Date.now();
      await until(async () => { const j = await info(pg2); return !j.apagado && j.actual !== null && j.actual !== 'marca'; }, 8000, 'open at 01:59');
      assert.ok(onlyReads(pg2));
      assert.deepStrictEqual(pg2.errors, []);
    }
  },
  {
    name: 'P11: legible from the farthest reader on screens of every size, landscape and turned: titles ≥ 1.2 cm per metre (a long one ≥ 1.0, then wrapped), prices ≥ 1.5, other text ≥ 0.8; the turned stage fills the screen; nothing outside it or cut',
    run: async ({ browser }) => {
      sql(`update public.menu_items set name_es = 'Pan de banano casero', photo_url = 'https://fotos.test/banana.png' where name = 'Banana Bread'`);
      const ids = {
        prod: diapo({ kind: 'producto', item: 'Banana Bread', kicker_es: 'Recién horneado', kicker_en: 'Freshly baked', sort: 1 }),
        largo: diapo({ kind: 'producto', item: 'Adventure Box · Mano de Piedra or Chicken Pesto', kicker_es: '¿Sale temprano mañana? Pídala hoy', kicker_en: 'Leaving early tomorrow? Order it today', sort: 2 }),
        marca: diapo({ kind: 'marca', kicker_es: 'Nuestro café', kicker_en: 'Our coffee', title_es: 'Café de altura', title_en: 'Highland coffee', body_es: 'Tostado aquí', body_en: 'Roasted here', sort: 3 }),
        foto: diapo({ kind: 'marca', photo: 'https://fotos.test/bosque.png', title_es: 'Bienvenidos al bosque nuboso', title_en: 'Welcome to the cloud forest', sort: 4 }),
        titulo: diapo({ kind: 'marca', title_es: 'Café de altura cultivado por familias de Monteverde y tostado aquí mismo cada semana',
                        title_en: 'Highland coffee grown by Monteverde families and roasted right here every week',
                        body_es: 'Pregunte por el origen de cada taza en la caja', body_en: 'Ask about the origin of every cup at the counter', sort: 5 }),
        resena: diapo({ kind: 'invitacion', link: 'resena', title_es: '¿Le gustó su visita?', title_en: 'Loved your visit?', body_es: 'Cuéntelo en Tripadvisor', body_en: 'Tell others on Tripadvisor', sort: 6 }),
        menu: diapo({ kind: 'invitacion', link: 'menu', kicker_es: 'Sin esperar', kicker_en: 'No waiting', title_es: 'El menú en su teléfono', title_en: 'The menu on your phone', sort: 7 })
      };
      const cases = [[960, 540, 'no'], [1920, 1080, 'no'], [3840, 2160, 'no'], [1920, 1080, 'derecha'], [1920, 1080, 'izquierda'], [1280, 720, 'derecha']];
      for (const [w, h, giro] of cases) {
        const pg = await pantalla(browser, { viewport: { width: w, height: h }, q: `?tv=promos-1&pulgadas=55&distancia=3&giro=${giro}`, test: { diapositiva: 600000 } });
        const where = `${w}×${h} giro ${giro}`;
        const st = await pg.evaluate(() => { const s = document.getElementById('stage'), r = s.getBoundingClientRect(); return [Math.round(r.left), Math.round(r.top), Math.round(r.width), Math.round(r.height), s.offsetWidth, s.offsetHeight, s.style.transform]; });
        assert.deepStrictEqual(st.slice(0, 4), [0, 0, w, h], `${where}: the stage covers the screen`);
        assert.deepStrictEqual(st.slice(4), giro === 'no' ? [w, h, ''] : [h, w, giro === 'derecha' ? `translate(${w}px, 0px) rotate(90deg)` : `translate(0px, ${h}px) rotate(-90deg)`], where);
        const pxCm = Math.max(w, h) / LARGO_CM(55), tol = 1 / pxCm;
        for (const key of Object.keys(ids).concat('marca-propia')) {
          const kind = key === 'marca-propia' ? 'propia' : /^(prod|largo)$/.test(key) ? 'producto' : /^(resena|menu)$/.test(key) ? 'invitacion' : 'marca';
          let m, i;
          for (let intento = 0; intento < 3; intento++) {
            /* a tick delayed by a loaded test machine counts as a pause (B8/P13): the products leave at once until the
               read that follows; wait for verified prices, show the slide, and show it again if that happened meanwhile */
            await until(async () => (await info(pg)).estado === 'al-dia', 8000, 'prices verified');
            await mostrar(pg, key === 'marca-propia' ? 'marca' : ids[key]);
            m = await medir(pg); i = await info(pg);
            if (m.kind === kind) break;
          }
          const at = `${where} ${key}`;
          assert.strictEqual(m.kind, kind, `${at}: the slide on screen`);
          const caps = (r) => m.textos.filter((t) => t.r === r).map((t) => t.cap / pxCm);
          assert.deepStrictEqual([m.fuera, m.cortados], [[], []], `${at}: nothing outside the screen or cut`);
          assert.ok(i.medidas.cabe && i.medidas.k === 1, `${at}: fits at the sizes for the distance ` + JSON.stringify(i.medidas));
          const t = caps('t');
          assert.strictEqual(t.length, 1, at);
          if (key === 'titulo') {
            assert.ok(t[0] >= 1.0 * 3 - tol && i.medidas.envuelto, `${at}: a long title wraps, never under 1.0 cm/m (${t[0].toFixed(2)} cm)`);
            assert.ok(m.textos.find((x) => x.r === 't').lines >= 2, at);
          } else if (i.medidas.envuelto || i.medidas.titulo < 1.2) {
            assert.ok(t[0] >= 1.0 * 3 - tol, `${at}: a title too long for one line at 1.2: ${t[0].toFixed(2)} cm`);
            assert.ok(!i.medidas.envuelto || i.medidas.titulo >= 1.0, at);
          } else assert.ok(t[0] >= 1.2 * 3 - tol, `${at}: title capital ${t[0].toFixed(2)} cm at 3 m (1.2 cm/m)`);
          if (key === 'marca') assert.ok(t[0] >= 1.2 * 3 - tol && !i.medidas.envuelto, `${at}: a short title at full size on one line`);
          if (key === 'prod' || key === 'largo') {
            assert.ok(caps('p').length === 1 && caps('p')[0] >= 1.5 * 3 - tol, `${at}: price capital ${caps('p')[0]} cm (1.5 cm/m); on screen ${m.id} ${m.kind}: ${JSON.stringify(m.textos.map((x) => x.r + ':' + x.t.slice(0, 24)))} ${JSON.stringify(i.medidas)}`);
          } else assert.strictEqual(caps('p').length, 0, `${at}: no price`);
          const small = m.textos.filter((x) => !['t', 'p'].includes(x.r));
          assert.ok(small.length >= (key === 'marca-propia' ? 1 : 2), at);
          small.forEach((x) => assert.ok(x.cap / pxCm >= 0.8 * 3 - tol, `${at}: «${x.t}» ${(x.cap / pxCm).toFixed(2)} cm (0.8 cm/m)`));
          if (key === 'resena' || key === 'menu') {
            assert.ok(m.qr && m.qr.side / pxCm >= 30 - 0.05 && m.qr.dentro, `${at}: QR ${m.qr && (m.qr.side / pxCm).toFixed(1)} cm, on the screen`);
            assert.ok(m.qr.dirs.length >= 1 && m.qr.dirs.every((d) => d[1] >= m.qr.rect[3] - 1 || (giro !== 'no')), `${at}: the address under the code`);
          }
        }
        assert.deepStrictEqual(pg.errors, [], where);
        await pg.context().close();
      }
    }
  },
  {
    name: 'P12: without migration 0036 (the function gone): the brand slide, and it keeps trying, with the same GET only',
    run: async ({ browser }) => {
      marca('Pura vida', { sort: 1 });
      await sinFuncion();
      const pg = await pantalla(browser, { q: '?tv=promos-1&diag=1', wait: false, test: { cada: 500 } });
      await until(async () => (await info(pg)).razon === 'sin-funcion', 8000, 'the missing function noticed');
      const n = (await info(pg)).intentos;
      await sleep(2000);
      const i = await info(pg);
      assert.deepStrictEqual([i.actual, i.visibles, i.fuente, i.buenas], ['marca', [], 'omision', 0]);
      assert.ok(i.intentos >= n + 3, `it keeps trying (${i.intentos - n} more in 2 s)`);
      assert.strictEqual((await vista(pg)).kind, 'propia');
      assert.ok(/falta la migración 0036/.test(await diag(pg)), await diag(pg));
      assert.ok(onlyReads(pg));
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'P13: after a resume, being shown again or a pause: no product until a read that started after it, and that read happens at once; the brand slides stay',
    run: async ({ browser, setOffline }) => {
      const p = diapo({ kind: 'producto', item: 'Latte', sort: 1 });
      const m = marca('Pura vida', { sort: 2 });
      const pg = await pantalla(browser, { test: { cada: 600000, revisar: 200, diapositiva: 600000 } });
      const fire = (ev) => pg.evaluate((e) => {
        if (e === 'pageshow') window.dispatchEvent(new PageTransitionEvent('pageshow', { persisted: true }));
        else document.dispatchEvent(new Event(e));
      }, ev);
      for (const ev of ['resume', 'visibilitychange', 'pageshow']) {
        await mostrar(pg, p);
        setOffline(true);
        await fire(ev);
        let i = await info(pg);
        assert.ok(i.estado === 'sin-verificar' && i.dudoso && i.edadMs < i.tiempos.fresco, `${ev}: unverified at once, though the age alone would allow the price (${i.edadMs} ms)`);
        assert.deepStrictEqual([i.visibles, i.actual], [[m], m], ev + ': the product gone, the brand slide stays');
        await sleep(600);
        assert.strictEqual((await info(pg)).estado, 'sin-verificar', `${ev}: still unverified without a read`);
        setOffline(false);
        const n = pg.api.length;
        await fire(ev);
        await until(async () => { const j = await info(pg); return j.estado === 'al-dia' && j.visibles.includes(p); }, 4000, `${ev}: verified by the read it started`);
        assert.ok(pg.api.length > n, ev + ': read at once');
      }
      assert.ok(onlyReads(pg));
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'P14: the TV\'s row sets it up (size, distance, turn, scale, look, seconds per slide) and the address overrides it setting by setting; a change shows on the next read; slides take turns at that pace with a crossfade; the diagnosis says where each setting comes from',
    run: async ({ browser }) => {
      marca('Uno', { sort: 1 }); marca('Dos', { sort: 2 });
      sql(`update public.screens set inches = 65, distance_m = 4, turn = 'derecha', scale_pct = 110, look = 'noche', slide_seconds = 7 where id = 'promos-1'`);
      let pg = await pantalla(browser, { q: '?tv=promos-1&diag=1', test: { cada: 1000 } });
      let i = await info(pg);
      assert.deepStrictEqual([i.fuente, i.tv.pulgadas, i.tv.distancia, i.tv.giro, i.tv.escala, i.tv.look, i.tv.diapositiva, i.diapositivaMs],
        ['db', 65, 4, 'derecha', 110, 'noche', 7, 7000]);
      assert.deepStrictEqual(i.tv.origen, { pulgadas: 'db', distancia: 'db', escala: 'db', diapositiva: 'db', giro: 'db', look: 'db' });
      assert.strictEqual(await pg.evaluate(() => document.getElementById('stage').style.transform), 'translate(1920px, 0px) rotate(90deg)');
      assert.ok(Math.abs(i.medidas.base - 4 * 1.1) < 1e-9 && Math.abs(i.medidas.pxPorCm - 1920 / LARGO_CM(65)) < 1e-9, JSON.stringify(i.medidas));
      let d = await diag(pg);
      assert.ok(/Origen: base de datos \(TV promos-1/.test(d) && /65" · 4 m/.test(d) && /7 s por diapositiva/.test(d) && /Precios: al-dia/.test(d), d);
      assert.strictEqual(await pg.evaluate(() => getComputedStyle(document.querySelector('.capa')).transitionDuration.split(',')[0]), '1s', 'a crossfade');
      /* the pace: 7 s a slide */
      const first = (await info(pg)).actual;
      await until(async () => (await info(pg)).actual !== first, 10000, 'the next slide');
      const t1 = Date.now();
      await until(async () => (await info(pg)).actual === first, 10000, 'back to the first');
      const gap = Date.now() - t1;
      assert.ok(gap >= 6500 && gap <= 8500, `7 s a slide: ${gap} ms`);
      sql(`update public.screens set inches = 50, distance_m = 2, turn = 'no' where id = 'promos-1'`);
      await until(async () => { const j = await info(pg); return j.tv.giro === 'no' && j.tv.distancia === 2 && j.tv.pulgadas === 50; }, 8000, 'the new settings');
      assert.strictEqual(await pg.evaluate(() => document.getElementById('stage').style.transform), '');
      assert.deepStrictEqual(pg.errors, []);
      await pg.context().close();
      pg = await pantalla(browser, { q: '?tv=promos-1&distancia=2.5&giro=no&look=dia&diapositiva=12&escala=90&pulgadas=abc&diag=1' });
      i = await info(pg);
      assert.deepStrictEqual([i.tv.pulgadas, i.tv.distancia, i.tv.giro, i.tv.look, i.tv.escala, i.diapositivaMs], [50, 2.5, 'no', 'dia', 90, 12000]);
      assert.deepStrictEqual(i.tv.origen, { pulgadas: 'db', distancia: 'direccion', escala: 'direccion', diapositiva: 'direccion', giro: 'direccion', look: 'direccion' });
      assert.deepStrictEqual([i.look, await pg.evaluate(() => document.getElementById('stage').classList.contains('dia'))], ['dia', true], 'the daylight look');
      assert.strictEqual(await pg.evaluate(() => getComputedStyle(document.querySelector('.capa.on .claro .fondo')).backgroundColor), 'rgb(255, 251, 241)', 'bright without a photo');
      d = await diag(pg);
      assert.ok(/de la dirección: distancia, escala, diapositiva, giro, look/.test(d) && /Ajustes no válidos: pulgadas=abc/.test(d), d);
      assert.ok(onlyReads(pg));
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'P15: a menu TV\'s name, an unknown TV or no TV in the address: only the brand slide; a TV switched off in pantallas goes black until switched on again; the diagnosis says why',
    run: async ({ browser }) => {
      const m = marca('Pura vida', { sort: 1 });
      for (const [q, razon] of [['?tv=menu-1&diag=1', 'otra-clase'], ['?tv=promos-9&diag=1', 'tv-desconocida']]) {
        const pg = await pantalla(browser, { q, wait: false, test: { cada: 500 } });
        await until(async () => (await info(pg)).razon === razon, 8000, razon);
        const i = await info(pg);
        assert.deepStrictEqual([i.actual, i.visibles, i.fuente, i.horaDe], ['marca', [], 'omision', 'servidor'], q);
        assert.ok(onlyReads(pg));
        assert.deepStrictEqual(pg.errors, []);
        await pg.context().close();
      }
      const none = await pantalla(browser, { q: '?diag=1', wait: false });
      await sleep(1500);
      assert.deepStrictEqual([(await info(none)).razon, (await info(none)).actual, none.api], ['sin-tv', 'marca', []], 'no TV: not a single call');
      assert.ok(/la dirección no dice \?tv=/.test(await diag(none)));
      await none.context().close();
      const pg = await pantalla(browser, { q: '?tv=promos-1&pulgadas=55&distancia=3&diag=1', test: { cada: 500 } });
      assert.strictEqual((await info(pg)).actual, m);
      sql(`update public.screens set active = false where id = 'promos-1'`);
      await until(async () => { const i = await info(pg); return i.razon === 'tv-apagada' && i.apagado === true && i.actual === null; }, 8000, 'switched off: black, nothing on it');
      await until(async () => /apagada en Pantallas/i.test(await diag(pg)), 4000, 'the diagnosis says the TV is switched off');
      sql(`update public.screens set active = true where id = 'promos-1'`);
      await until(async () => { const i = await info(pg); return !i.apagado && i.actual === m; }, 8000, 'switched on again: the slide is back');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'P16: a read counts from the moment its request started (a slow answer is never fresher than its request); the time limit covers the answer\'s body, so a stalled body never stops the reads',
    run: async ({ browser }) => {
      const p = diapo({ kind: 'producto', item: 'Latte', sort: 1 });
      marca('Pura vida', { sort: 2 });
      /* answers that take 1.5 s, with 1 s of «fresh»: the price is never shown as current, only to be confirmed */
      const slow = (x) => x.route(/\/rest\/v1\/rpc\/pantalla_datos/, async (route) => {
        let r; try { r = await route.fetch(); } catch (e) { return route.abort(); }
        await sleep(1500);
        return route.fulfill({ response: r });
      });
      const pg = await pantalla(browser, { wait: false, test: { cada: 400, fresco: 1000, vencido: 20000, revisar: 100, diapositiva: 600000 }, setup: slow });
      await until(async () => { const i = await info(pg); return i.estado === 'por-confirmar' && i.actual === p; }, 10000, 'the price, to be confirmed');
      const seen = new Set();
      for (let k = 0; k < 16; k++) {
        const i = await info(pg);
        seen.add(i.estado);
        assert.ok(i.edadMs >= 1400, 'a price is never younger than its answer took: ' + i.edadMs);
        await sleep(150);
      }
      assert.ok(!seen.has('al-dia') && seen.has('por-confirmar'), [...seen].join());
      await until(async () => (await vista(pg)).nota === NOTA, 3000, 'the note');
      assert.strictEqual(digits((await vista(pg)).precio), 2200);
      assert.deepStrictEqual(pg.errors, []);
      await pg.context().close();
      /* the headers arrive, the body never does: the limit cuts it and the next reads still happen */
      const stall = (x) => x.addInitScript(() => {
        const orig = window.fetch; window.__stall = true;
        window.fetch = function (url, opts) {
          return orig.apply(this, arguments).then((res) => {
            if (!window.__stall || !/pantalla_datos/.test(String(url))) return res;
            const sig = opts && opts.signal;
            res.json = () => new Promise((ok, no) => { if (sig) sig.addEventListener('abort', () => no(new DOMException('aborted', 'AbortError'))); });
            return res;
          });
        };
      });
      const pg2 = await pantalla(browser, { wait: false, test: { cada: 400, limite: 800, revisar: 100 }, setup: stall });
      await sleep(3500);
      const i = await info(pg2);
      assert.ok(i.intentos >= 3 && i.buenas === 0, 'each stalled read was cut at the limit and another one followed: ' + i.intentos);
      assert.deepStrictEqual([i.estado, i.actual], ['sin-verificar', 'marca']);
      await pg2.evaluate(() => { window.__stall = false; });
      await until(async () => { const j = await info(pg2); return j.estado === 'al-dia' && j.actual === p; }, 5000, 'verified once the answers arrive whole');
      assert.ok(onlyReads(pg2));
      assert.deepStrictEqual(pg2.errors, []);
    }
  },
  {
    name: 'P17: after a release the screen reloads by itself, with its settings and without a notice to the guests',
    run: async ({ browser, setRelease }) => {
      setRelease({ served: 'b1', published: 'b2' });
      const pg = await pantalla(browser, { q: '?tv=promos-1&pulgadas=65&distancia=4' });
      assert.strictEqual(await pg.evaluate(() => HG_VERSION.build), 'b1');
      await pg.evaluate(async () => { HG_VERSION.quietMs = 0; await HG_VERSION.check(); });
      assert.strictEqual(await pg.evaluate(() => HG_VERSION.pending), 'b2');
      assert.ok(!/new version|nueva versión/i.test(await pg.evaluate(() => document.body.innerText)), 'no notice on the screen');
      await until(async () => pg.evaluate(() => { try { return HG_VERSION.tick(); } catch (e) { return false; } }).catch(() => true), 10000, 'the reload');
      await until(() => pg.evaluate(() => !!window.HG_VERSION && HG_VERSION.build === 'b2' && !!window.PANTALLA_B && PANTALLA_B.info().buenas > 0), 15000, 'the new version running');
      const q = await pg.evaluate(() => location.search);
      assert.ok(/tv=promos-1/.test(q) && /pulgadas=65/.test(q) && /distancia=4/.test(q), 'the TV keeps its settings: ' + q);
      assert.strictEqual((await info(pg)).tv.pulgadas, 65);
    }
  },
  {
    name: 'P18: the six templates tile the whole screen with 1 to 4 zones in their places (4-centro: 3/8 · two of 2/8 stacked · 3/8), each zone with its own photo, nothing outside the stage; on a turned TV the zones stack in order',
    run: async ({ browser }) => {
      const ids = {}; let sort = 1;
      for (const t of Object.keys(PLAZAS)) ids[t] = compo({ template: t, sort: sort++, zones: fotos(t.replace(/\W/g, '') + '-', PLAZAS[t]).map((f) => ({ entries: [f] })) });
      const pg = await pantalla(browser, { test: { diapositiva: 600000, permanencia: 600000 } });
      assert.deepStrictEqual((await info(pg)).visibles, Object.values(ids), 'all six in force');
      const W = 1920, H = 1080, near = (a, b, tol) => Math.abs(a - b) <= (tol || 8);
      const want = {   /* [x, y, w, h] as fractions of the stage, in the zones' order */
        '1': [[0, 0, 1, 1]], '2-lado': [[0, 0, 1 / 2, 1], [1 / 2, 0, 1 / 2, 1]],
        '3-grande-izq': [[0, 0, 2 / 3, 1], [2 / 3, 0, 1 / 3, 1 / 2], [2 / 3, 1 / 2, 1 / 3, 1 / 2]],
        '3-grande-der': [[0, 0, 1 / 3, 1 / 2], [0, 1 / 2, 1 / 3, 1 / 2], [1 / 3, 0, 2 / 3, 1]],
        '4-cuadricula': [[0, 0, 1 / 2, 1 / 2], [1 / 2, 0, 1 / 2, 1 / 2], [0, 1 / 2, 1 / 2, 1 / 2], [1 / 2, 1 / 2, 1 / 2, 1 / 2]],
        '4-centro': [[0, 0, 3 / 8, 1], [3 / 8, 0, 2 / 8, 1 / 2], [3 / 8, 1 / 2, 2 / 8, 1 / 2], [5 / 8, 0, 3 / 8, 1]]
      };
      for (const t of Object.keys(PLAZAS)) {
        await mostrar(pg, ids[t]);
        await until(async () => { const z = await zonas(pg); return z && z.id === ids[t] && z.zonas.every((x) => x.estado === 'entrada'); }, 6000, t + ' on screen');
        const z = await zonas(pg), v = await vista(pg);
        assert.deepStrictEqual([v.kind, z.template, z.zonas.length, (await info(pg)).tipo], ['composicion', t, PLAZAS[t], 'composicion'], t);
        let area = 0;
        z.zonas.forEach((x, i) => {
          const [fx, fy, fw, fh] = want[t][i], at = `${t} zone ${i + 1} ${JSON.stringify(x.box)}`;
          assert.ok(near(x.box[0], fx * W) && near(x.box[1], fy * H) && near(x.box[2], fw * W) && near(x.box[3], fh * H), at + ' expected ' + JSON.stringify([fx * W, fy * H, fw * W, fh * H]));
          assert.ok(x.box[0] >= 0 && x.box[1] >= 0 && x.box[0] + x.box[2] <= W && x.box[1] + x.box[3] <= H && x.dentro, at + ': inside the stage');
          assert.strictEqual(x.src, `https://fotos.test/${t.replace(/\W/g, '')}-${i}.png`, at + ': its own photo, in order');
          assert.strictEqual(x.tamano, fw * fh >= 1 / 3 - 1e-9 ? 'grande' : 'pequena', at);
          assert.ok(x.capas.some((c) => c.on && c.lista), at + ': the photo painted');
          area += x.box[2] * x.box[3];
        });
        assert.ok(area >= 0.985 * W * H, `${t}: the zones fill the screen (${(100 * area / (W * H)).toFixed(1)} %)`);
        assert.ok(/Hanging Garden Café/.test(z.sup || ''), t + ': the brand line on top');
        assert.ok(!/₡|\d/.test(z.text), t + ': photos only, no text: ' + z.text);
      }
      const m = (await info(pg)).medidas;
      assert.ok(m.cabe && m.k === 1 && m.plantilla === '4-centro' && m.zonas.length === 4, JSON.stringify(m));
      assert.ok(onlyReads(pg));
      assert.deepStrictEqual(pg.errors, []);
      await pg.context().close();
      /* a vertical TV: the zones one above the other, in their order, each the full width */
      const pg2 = await pantalla(browser, { q: '?tv=promos-1&pulgadas=55&distancia=3&giro=derecha', test: { diapositiva: 600000, permanencia: 600000 } });
      await mostrar(pg2, ids['4-centro']);
      await until(async () => { const z = await zonas(pg2); return z && z.id === ids['4-centro'] && z.zonas.every((x) => x.estado === 'entrada'); }, 6000, 'turned');
      const z2 = await zonas(pg2);
      assert.deepStrictEqual(z2.stage, [1080, 1920]);
      z2.zonas.forEach((x, i) => {
        assert.ok(near(x.box[0], 0) && near(x.box[1], i * 480) && near(x.box[2], 1080) && near(x.box[3], 480) && x.dentro, `turned zone ${i + 1}: ${JSON.stringify(x.box)}`);
        assert.strictEqual(x.src, `https://fotos.test/4centro-${i}.png`);
      });
      assert.deepStrictEqual(pg2.errors, []);
    }
  },
  {
    name: 'P19: a fixed zone keeps its photo; each presentation zone takes turns among its own entries at its own seconds, in order, with a clock of its own (the zones never move together)',
    run: async ({ browser }) => {
      const c = compo({ template: '3-grande-izq', zones: [
        { mode: 'fija', entries: ['https://fotos.test/fija.png', 'https://fotos.test/nunca.png'] },   /* a fixed zone: its first entry only */
        { mode: 'auto', seconds: 4, entries: fotos('a', 3) },
        { mode: 'auto', seconds: 6, entries: fotos('b', 2) }
      ] });
      /* a declared second lasts 100 ms here: 4 s -> 400 ms, 6 s -> 600 ms; the dissolve 120 ms */
      const pg = await pantalla(browser, { test: { diapositiva: 600000, zona: 100, fundido: 120, revisar: 200 } });
      await until(async () => { const z = await zonas(pg); return z && z.zonas.every((x) => x.estado === 'entrada'); }, 6000, 'the composition up');
      const t0 = Date.now(), m = await muestrear(pg, 3000, 30);
      assert.ok(Date.now() - t0 >= 3000);
      const fija = new Set(m.map((x) => x.z.zonas[0].src + '|' + x.z.zonas[0].entrada));
      assert.deepStrictEqual([...fija], ['https://fotos.test/fija.png|0'], 'the fixed zone never changes');
      assert.ok(!m.some((x) => /nunca/.test(JSON.stringify(x.z.zonas[0]))), 'a fixed zone shows its first entry only');
      const c1 = cambios(m, 1), c2 = cambios(m, 2);
      assert.ok(c1.length >= 5 && c1.length <= 9, `the 4 s zone changed ${c1.length} times in 3 s (every 400 ms): ${c1.join(', ')}`);
      assert.ok(c2.length >= 3 && c2.length <= 6, `the 6 s zone changed ${c2.length} times in 3 s (every 600 ms): ${c2.join(', ')}`);
      assert.ok(c1.length > c2.length, 'each at its own pace');
      const seq = (i) => m.map((x) => x.z.zonas[i].entrada).filter((v, k, a) => k === 0 || v !== a[k - 1]);
      seq(1).forEach((v, k, a) => { if (k) assert.strictEqual(v, (a[k - 1] + 1) % 3, 'zone 2 in order: ' + a.join('')); });
      seq(2).forEach((v, k, a) => { if (k) assert.strictEqual(v, (a[k - 1] + 1) % 2, 'zone 3 in order: ' + a.join('')); });
      m.forEach((x) => x.z.zonas.forEach((zz, i) => assert.strictEqual(zz.src, `https://fotos.test/${['fija', 'a', 'b'][i]}${i ? zz.entrada : ''}.png`, 'the photo of the entry shown')));
      /* one zone advanced while the other did not, both ways */
      const solo = (a, b) => m.some((x, k) => k && x.z.zonas[a].entrada !== m[k - 1].z.zonas[a].entrada && x.z.zonas[b].entrada === m[k - 1].z.zonas[b].entrada);
      assert.ok(solo(1, 2) && solo(2, 1), 'independent clocks');
      const ci = await compoInfo(pg);
      assert.deepStrictEqual(ci.zonas.map((z) => [z.modo, z.seg, z.mostrables, z.reloj || z.cambiando]), [['fija', 8, 1, false], ['auto', 4, 3, true], ['auto', 6, 2, true]], JSON.stringify(ci));
      assert.ok(onlyReads(pg));
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'P20: with labels a zone writes the live name (Spanish first, English below) and the price; without them only the photo, framed as the owner set it; a new price shows in place without restarting; offline the price ages like a product slide (note, then none) while the photo and the name stay',
    run: async ({ browser, setOffline }) => {
      sql(`update public.menu_items set name_es = 'Pan de banano casero', photo_url = 'https://fotos.test/banana.png' where name = 'Banana Bread'`);
      const c = compo({ template: '2-lado', zones: [
        { mode: 'fija', labels: true, entries: [{ item: 'Banana Bread' }] },
        { mode: 'fija', labels: false, entries: [{ item: 'Latte', photo: 'https://fotos.test/latte.png', focus: [20, 80], zoom: 150 }] }
      ] });
      const T = { cada: 400, fresco: 2500, vencido: 5000, revisar: 150, diapositiva: 600000 };
      const pg = await pantalla(browser, { test: T });
      await until(async () => { const z = await zonas(pg); return z && z.zonas.every((x) => x.estado === 'entrada'); }, 6000, 'up');
      let z = await zonas(pg);
      const a = z.zonas[0], b = z.zonas[1];
      assert.deepStrictEqual([a.tit, a.titEn, digits(a.precio), a.nota, a.src], ['Pan de banano casero', 'Banana Bread', 1500, null, 'https://fotos.test/banana.png'], JSON.stringify(a));
      assert.ok(/^₡1\s?500$/.test(a.precio), 'the price as on the menu: ' + a.precio);
      assert.deepStrictEqual([b.tit, b.precio, b.src, b.encuadre], [null, null, 'https://fotos.test/latte.png', ['20% 80%', 'scale(1.5)']], 'labels off: the photo only, framed');
      assert.ok(!/Latte/.test(z.text), 'no name without labels: ' + z.text);
      const pxCm = 1920 / LARGO_CM(55), tol = 1 / pxCm, cm = (r) => a.caps.filter((x) => x.r === r).map((x) => x.cap / pxCm);
      assert.ok(cm('zt')[0] >= 1.0 * 3 - tol, 'the name 1.0 cm/m in a large zone: ' + cm('zt'));
      assert.ok(cm('zp')[0] >= 1.2 * 3 - tol, 'the price 1.2 x the name: ' + cm('zp'));
      assert.ok(a.caps.every((x) => !x.cortado) && b.caps.length === 0);
      /* the Menu Manager changes the price: written again in place, the photo untouched, the zone not restarted */
      sql(`update public.menu_items set price_crc = 1650 where name = 'Banana Bread'`);
      await until(async () => digits((await zonas(pg)).zonas[0].precio) === 1650, 8000, 'the new price');
      z = await zonas(pg);
      assert.deepStrictEqual([z.zonas[0].entrada, z.zonas[0].src, z.zonas[0].capas.filter((x) => x.on).length], [0, 'https://fotos.test/banana.png', 1]);
      assert.strictEqual((await info(pg)).actual, c);
      /* no connection: the price ages (note at 2 min, none at 10 min); the zone keeps its photo and its name */
      setOffline(true);
      await until(async () => (await info(pg)).estado === 'por-confirmar' && (await zonas(pg)).zonas[0].nota === NOTA, 8000, '«por confirmar» in the zone');
      z = await zonas(pg);
      assert.deepStrictEqual([digits(z.zonas[0].precio), z.zonas[0].tit], [1650, 'Pan de banano casero']);
      await until(async () => (await info(pg)).estado === 'sin-verificar' && (await zonas(pg)).zonas[0].precio === null, 8000, 'no price');
      z = await zonas(pg);
      assert.deepStrictEqual([z.zonas[0].tit, z.zonas[0].nota, z.zonas[0].src, z.id, (await info(pg)).actual], ['Pan de banano casero', null, 'https://fotos.test/banana.png', c, c],
        'the composition stays, the photo and the name stay, no price: ' + JSON.stringify(z.zonas[0]));
      assert.ok(!/₡/.test(await stageText(pg)));
      setOffline(false);
      await until(async () => { const j = await zonas(pg); return j && digits(j.zonas[0].precio) === 1650 && j.zonas[0].nota === null; }, 8000, 'the price back');
      assert.ok(onlyReads(pg));
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'P21: an entry whose product cannot be sold (sold out, the till\'s Extras & Combos) is skipped; a zone with nothing to show shows its fallback photo or the brand design; a composition with no zone to show leaves the screen and comes back by itself; the diagnosis names it all',
    run: async ({ browser }) => {
      const c = compo({ template: '2-lado', kicker_es: 'Desayuno', kicker_en: 'Breakfast', zones: [
        { mode: 'auto', seconds: 4, labels: true, fallback: 'https://fotos.test/respaldo.png', entries: [{ item: 'Banana Bread' }, { item: 'Latte' }, { item: 'Flavor shot' }] },
        { mode: 'fija', entries: [{ item: 'Tea' }] }
      ], sort: 1 });
      const m = marca('Pura vida', { sort: 2 });
      const pg = await pantalla(browser, { q: '?tv=promos-1&pulgadas=55&distancia=3&diag=1', test: { cada: 500, zona: 100, fundido: 100, revisar: 150, diapositiva: 600000, permanencia: 600000 } });
      await until(async () => { const z = await zonas(pg); return z && z.id === c && z.zonas.every((x) => x.estado === 'entrada'); }, 6000, 'up');
      let m1 = await muestrear(pg, 1500, 40);
      const vistas = new Set(m1.map((x) => x.z.zonas[0].entrada));
      assert.deepStrictEqual([...vistas].sort(), [0, 1], 'the two products take turns; the till helper never');
      assert.ok(!m1.some((x) => /Flavor|Combo/i.test(x.z.text)), 'never a till helper');
      assert.ok(cambios(m1, 0).length >= 2);
      assert.strictEqual((await zonas(pg)).kick, 'Desayuno · Breakfast');
      let d = await diag(pg);
      assert.ok(/Composición: plantilla 2-lado · 2 zonas/.test(d) && /Zona 1: presentación cada 4 s · 2 de 3 entradas con qué mostrar · con nombres y precios · muestra la [12] \((Pan de banano casero|Pan de banano|Banana Bread|Latte), precio\)/.test(d)
                && /Zona 2: foto fija · 1 de 1 entrada con qué mostrar · con nombres y precios · muestra la 1 \((Tea|Té), precio\)/.test(d), d);
      /* one sold out: the zone goes on with the other, without restarting the composition */
      sql(`update public.menu_items set available = false where name = 'Banana Bread'`);
      await until(async () => (await compoInfo(pg)).zonas[0].mostrables === 1, 8000, 'one left');
      await sleep(400);
      m1 = await muestrear(pg, 1200, 40);
      assert.ok(m1.every((x) => x.z.id === c && x.z.zonas[0].entrada === 1 && x.z.zonas[0].tit === 'Latte'), 'only Latte now: ' + JSON.stringify(m1[0].z.zonas[0]));
      assert.ok(!/banano|Banana/.test(await stageText(pg)));
      /* the other zone's product sold out: that zone shows the brand design (no fallback photo), the composition stays */
      sql(`update public.menu_items set available = false where name = 'Tea'`);
      await until(async () => { const z = await zonas(pg); return z && z.id === c && z.zonas[1].estado === 'marca' && quieta(z); }, 8000, 'the brand design in zone 2');
      let z = await zonas(pg);
      assert.deepStrictEqual([z.zonas[1].marca, z.zonas[1].tit, z.zonas[1].lugar, z.zonas[1].src], [true, null, 'Monteverde, Costa Rica', null], JSON.stringify(z.zonas[1]));
      assert.ok(/Hanging Garden Café/.test(z.zonas[1].text) && !/Tea|Té/.test(z.text));
      assert.ok(/Zona 2: foto fija · 0 de 1 entrada con qué mostrar · con nombres y precios · NADA QUE MOSTRAR: el diseño de marca/.test(await diag(pg)), await diag(pg));
      /* the last product of zone 1 sold out: nothing to show anywhere: the composition leaves (the server says so too) */
      sql(`update public.menu_items set available = false where name = 'Latte'`);
      await until(async () => { const i = await info(pg); return i.actual === m && !i.visibles.includes(c); }, 8000, 'the composition gone');
      assert.ok(!/₡|Latte/.test(await stageText(pg)));
      await until(() => pg.evaluate(() => document.querySelectorAll('.zona').length === 0), 3000, 'its zones cleared (the hidden layer is emptied after the cut)');
      /* back in stock: it comes back, zone 1 with the fallback until its products return */
      sql(`update public.menu_items set available = true where name = 'Tea'`);
      await until(async () => (await info(pg)).visibles.includes(c), 8000, 'back');
      await mostrar(pg, c);
      await until(async () => { const j = await zonas(pg); return j && j.id === c && j.zonas[0].estado === 'respaldo' && j.zonas[1].estado === 'entrada' && quieta(j); }, 8000, 'the fallback photo in zone 1');
      z = await zonas(pg);
      assert.deepStrictEqual([z.zonas[0].src, z.zonas[0].tit, z.zonas[0].precio, z.zonas[1].tit], ['https://fotos.test/respaldo.png', null, null, 'Té'], JSON.stringify(z.zonas));
      assert.ok(/Zona 1: presentación cada 4 s · 0 de 3 entradas con qué mostrar · con nombres y precios · NADA QUE MOSTRAR: la foto de respaldo/.test(await diag(pg)), await diag(pg));
      sql(`update public.menu_items set available = true where name = 'Latte'`);
      await until(async () => { const j = await zonas(pg); return j && j.id === c && j.zonas[0].estado === 'entrada' && j.zonas[0].tit === 'Latte' && quieta(j); }, 8000, 'Latte back in zone 1');
      assert.ok(onlyReads(pg));
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'P22: the screen checks a composition itself: one the server marks unusable, one without zones, one whose entries have nothing to show, one with the wrong number of zones and an unknown kind are left out',
    run: async ({ browser }) => {
      const c = compo({ template: '2-lado', zones: [{ entries: ['https://fotos.test/a.png'] }, { entries: [{ item: 'Latte' }] }], sort: 1 });
      const base = slideJson(c);
      const extra = [
        Object.assign({}, base, { id: '11111111-1111-4111-8111-111111111111', usable: false }),
        Object.assign({}, base, { id: '22222222-2222-4222-8222-222222222222', zones: [] }),
        Object.assign({}, base, { id: '33333333-3333-4333-8333-333333333333', zones: base.zones.map((z) => Object.assign({}, z, { entries: [{ item: Object.assign({}, base.zones[1].entries[0].item, { sellable: false }), photo: null, focus: [50, 50], zoom: 100 }] })) }),
        Object.assign({}, base, { id: '44444444-4444-4444-8444-444444444444', zones: base.zones.slice(0, 1) }),
        Object.assign({}, base, { id: '55555555-5555-4555-8555-555555555555', kind: 'grupo' })
      ];
      const inject = (x) => x.route(/\/rest\/v1\/rpc\/pantalla_datos/, async (route) => {
        let r; try { r = await route.fetch(); } catch (e) { return route.abort(); }
        let j = null; try { j = await r.json(); } catch (e) {}
        if (j && Array.isArray(j.slides)) j.slides = j.slides.concat(extra);
        return j ? route.fulfill({ response: r, json: j }) : route.fulfill({ response: r });
      });
      const pg = await pantalla(browser, { test: { diapositiva: 600000 }, setup: inject });
      const i = await info(pg);
      assert.deepStrictEqual([i.leidas, i.visibles, i.actual], [[c], [c], c], 'only the sound one: ' + JSON.stringify(i.leidas));
      await sleep(800);
      assert.deepStrictEqual((await info(pg)).leidas, [c]);
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'P23: a composition alone in force stays; sharing the TV it stays its dwell (60 s unless it says otherwise) while the other slides keep their seconds',
    run: async ({ browser }) => {
      const c = compo({ template: '1', zones: [{ entries: ['https://fotos.test/a.png'] }], sort: 1 });
      const pg = await pantalla(browser, { test: { cada: 1000, revisar: 200, diapositiva: 1000 } });
      let i = await info(pg);
      assert.deepStrictEqual([i.actual, i.permanenciaMs, i.diapositivaMs], [c, 60000, 1000], '60 s by default');
      sql(`update public.screen_slides set dwell_seconds = 15 where id = '${c}'`);
      await until(async () => (await info(pg)).permanenciaMs === 15000, 8000, 'its own dwell on the next read');
      await sleep(3000);
      assert.strictEqual((await info(pg)).actual, c, 'alone: it stays past the seconds of a slide');
      assert.deepStrictEqual(pg.errors, []);
      await pg.context().close();
      /* with a brand slide: the composition 1.5 s (the test\'s dwell), the brand slide 1 s */
      const m = marca('Pura vida', { sort: 2 });
      const pg2 = await pantalla(browser, { test: { cada: 1000, revisar: 100, diapositiva: 1000, permanencia: 1500 } });
      assert.deepStrictEqual((await info(pg2)).visibles, [c, m]);
      await until(async () => (await info(pg2)).actual === m, 5000, 'the brand slide');
      await until(async () => (await info(pg2)).actual === c, 5000, 'the composition again');
      const t1 = Date.now();
      await until(async () => (await info(pg2)).actual === m, 5000, 'the brand slide again');
      const t2 = Date.now();
      await until(async () => (await info(pg2)).actual === c, 5000, 'and back');
      const t3 = Date.now();
      assert.ok(t2 - t1 >= 1300 && t2 - t1 <= 2300, `the composition stayed its dwell: ${t2 - t1} ms`);
      assert.ok(t3 - t2 >= 800 && t3 - t2 <= 1800, `the brand slide its seconds: ${t3 - t2} ms`);
      assert.ok(onlyReads(pg2));
      assert.deepStrictEqual(pg2.errors, []);
    }
  },
  {
    name: 'P24: the owner\'s preview (?preview=1): the page reads nothing and writes nothing; it draws the slide its parent window posts (same origin, tipo pantalla-preview), presentations running, a later one replaces it; anything else (no tipo, another origin) is ignored',
    run: async ({ browser }) => {
      sql(`update public.menu_items set photo_url = 'https://fotos.test/croissant.png' where name = 'Butter Croissant'`);
      /* paused, for another TV and not started: the preview shows it anyway (nothing else ever does) */
      const c = compo({ template: '4-centro', kicker_es: 'Desayuno', kicker_en: 'Breakfast', status: 'pausada', screens: ['promos-2'], starts: "now() + interval '2 days'", ends: "now() + interval '3 days'",
        zones: [{ mode: 'auto', seconds: 4, entries: [{ item: 'Butter Croissant' }, { item: 'Banana Bread' }] }, { entries: [{ item: 'Iced Latte' }] },
                { entries: [{ item: 'Latte' }] }, { entries: [{ item: 'Ham & Cheese' }] }] });
      const uno = compo({ template: '1', status: 'pausada', zones: [{ entries: ['https://fotos.test/solo.png'] }] });
      const slide = slideJson(c), slide2 = slideJson(uno);
      assert.ok(slide.kind === 'composicion' && slide.zones.length === 4 && slide.zones[0].entries[0].item.name === 'Butter Croissant', JSON.stringify(slide).slice(0, 300));
      const T = { zona: 100, fundido: 100, revisar: 150, cada: 500 };
      const q = '?tv=promos-1&pulgadas=55&distancia=3&preview=1&diag=1';
      const pg = await pantalla(browser, { q, wait: false, test: T });
      await sleep(1200);
      let i = await info(pg);
      assert.deepStrictEqual([i.preview, i.razon, i.actual, i.intentos, pg.api], [true, 'vista-previa', 'marca', 0, []], 'nothing read: ' + JSON.stringify(i));
      assert.ok(/vista previa del Gestor/.test(await diag(pg)));
      /* the parent (this same page, the same origin) frames the preview and posts the slide */
      await pg.evaluate((src) => { const f = document.createElement('iframe'); f.id = 'pv'; f.src = src; f.width = 960; f.height = 540; document.body.appendChild(f); }, '/pantalla-promos' + q);
      const frame = await until(() => pg.frames().find((f) => f !== pg.mainFrame() && /preview=1/.test(f.url())), 8000, 'the frame');
      await until(() => frame.evaluate(() => !!window.PANTALLA_B), 10000, 'the frame\'s script');
      const post = (msg) => pg.evaluate((m) => { document.getElementById('pv').contentWindow.postMessage(m, location.origin); }, msg);
      await post({ slide });                                            /* no tipo: ignored */
      await post({ tipo: 'otra-cosa', slide });
      await sleep(600);
      assert.strictEqual(await frame.evaluate(() => PANTALLA_B.info().actual), 'marca', 'a message without the tipo is ignored');
      await pg.evaluate((s) => { document.getElementById('pv').contentWindow.postMessage({ tipo: 'pantalla-preview', slide: s }, location.origin); }, slide);
      await until(() => frame.evaluate((id) => PANTALLA_B.info().actual === id, c), 6000, 'the posted composition');
      await until(async () => { const z = await zonas(frame); return z && z.zonas.every((x) => x.estado === 'entrada'); }, 6000, 'its zones up');
      let z = await zonas(frame);
      assert.deepStrictEqual([z.template, z.zonas.length, z.kick, z.zonas[1].tit, z.zonas[1].titEn, z.zonas[2].tit, z.zonas[2].titEn, z.zonas[3].tit, z.zonas[3].titEn],
        ['4-centro', 4, 'Desayuno · Breakfast', 'Latte frío', 'Iced Latte', 'Latte', null, 'Jamón y queso', 'Ham & Cheese'], 'Spanish first (the site\'s dictionary), English below: ' + JSON.stringify(z.zonas.map((x) => [x.tit, x.titEn])));
      assert.ok(/^₡2\s?200$/.test(z.zonas[2].precio) && z.zonas[1].src === null && z.zonas[0].src === 'https://fotos.test/croissant.png', 'the live prices and photos the panel read: ' + JSON.stringify(z.zonas));
      i = await frame.evaluate(() => PANTALLA_B.info());
      assert.deepStrictEqual([i.preview, i.estado, i.visibles, i.intentos, i.buenas], [true, 'al-dia', [c], 0, 0]);
      const m = await muestrear(frame, 1500, 40);
      assert.ok(cambios(m, 0).length >= 2, 'the presentation zone takes turns in the preview: ' + cambios(m, 0).join(','));
      assert.ok(/Composición: plantilla 4-centro · 4 zonas/.test(await frame.evaluate(() => document.getElementById('diag').innerText)));
      /* a later message replaces it */
      await pg.evaluate((s) => { document.getElementById('pv').contentWindow.postMessage({ tipo: 'pantalla-preview', slide: s }, location.origin); }, slide2);
      await until(() => frame.evaluate((id) => PANTALLA_B.info().actual === id, uno), 6000, 'the second composition');
      await until(async () => { const j = await zonas(frame); return j && j.template === '1' && j.zonas[0].src === 'https://fotos.test/solo.png'; }, 6000, 'drawn');
      assert.deepStrictEqual(pg.api, [], 'not one call to the database from the preview or its parent');
      assert.deepStrictEqual(await pg.evaluate(() => Object.keys(localStorage)), ['hg_lang']);
      assert.deepStrictEqual(pg.errors, []);
      await pg.context().close();
      /* a parent of another origin: the same site served as «localhost» (another host than 127.0.0.1, so another
         origin, still on the loopback, which Chromium lets frame a loopback page); its message is ignored */
      const pg2 = await pantalla(browser, { url: SITE.replace('127.0.0.1', 'localhost') + '/pantalla-promos' + q, test: T });
      assert.notStrictEqual(await pg2.evaluate(() => location.origin), new URL(SITE).origin, 'another origin than the screen');
      await pg2.evaluate((src) => { const f = document.createElement('iframe'); f.id = 'pv'; f.src = src; f.width = 960; f.height = 540; document.body.appendChild(f); }, SITE + '/pantalla-promos' + q);
      const frame2 = await until(() => pg2.frames().find((f) => f !== pg2.mainFrame() && /preview=1/.test(f.url())), 8000, 'the frame');
      await until(() => frame2.evaluate(() => !!window.PANTALLA_B), 10000, 'the frame\'s script');
      await pg2.evaluate((s) => { document.getElementById('pv').contentWindow.postMessage({ tipo: 'pantalla-preview', slide: s }, '*'); }, slide);
      await sleep(1000);
      assert.strictEqual(await frame2.evaluate(() => PANTALLA_B.info().actual), 'marca', 'a message from another origin is ignored');
      assert.deepStrictEqual(pg2.api, []);
      assert.deepStrictEqual(pg2.errors, []);
    }
  },
  {
    name: 'P25: a zone changes photo with a dissolve: the next photo is already loaded, the new layer fades in over the old one, which stays opaque until the fade ends; never an empty frame',
    run: async ({ browser }) => {
      const c = compo({ template: '1', zones: [{ mode: 'auto', seconds: 5, entries: fotos('d', 3) }] });
      /* 5 s -> 1000 ms a photo, the dissolve 600 ms */
      const pg = await pantalla(browser, { test: { diapositiva: 600000, zona: 200, fundido: 600, revisar: 200 } });
      await until(async () => { const z = await zonas(pg); return z && z.zonas[0].estado === 'entrada' && quieta(z); }, 6000, 'up');
      /* right after a switch both layers carry .ya (no transition) for two frames: wait for a layer that transitions */
      await until(() => pg.evaluate(() => !!document.querySelector('.zcapa:not(.ya)')), 2000, 'a layer with its transition');
      assert.strictEqual(await pg.evaluate(() => getComputedStyle(document.querySelector('.zcapa:not(.ya)')).transitionDuration.split(',')[0]), '0.6s', 'the dissolve lasts what the test set');
      const m = await muestrear(pg, 2600, 25);
      let fundidos = 0;
      m.forEach((x) => {
        const cs = x.z.zonas[0].capas;
        assert.strictEqual(cs.length, 2, 'two layers');
        assert.ok(cs.some((k) => k.on && k.img && k.lista && k.opacity >= 0.99), `${x.t} ms: an opaque loaded photo at every moment: ` + JSON.stringify(cs));
        const e = cs.find((k) => k.entra), s = cs.find((k) => k.sale);
        if (e && s) { fundidos++; assert.ok(s.on && s.opacity >= 0.99 && e.on && e.lista, `${x.t} ms: the old photo stays opaque under the new one while it fades in: ` + JSON.stringify(cs)); }
      });
      assert.ok(fundidos >= 3, 'the fade was seen while under way: ' + fundidos + ' samples');
      assert.ok(m.some((x) => { const e = x.z.zonas[0].capas.find((k) => k.entra); return e && e.opacity > 0.05 && e.opacity < 0.95; }), 'a crossfade, not a cut');
      const seq = m.map((x) => x.z.zonas[0].src).filter((v, k, a) => k === 0 || v !== a[k - 1]);
      assert.ok(seq.length >= 3, 'the photos took turns: ' + seq.join(' '));
      seq.forEach((v, k) => { if (k) assert.strictEqual(v, `https://fotos.test/d${(Number(seq[k - 1].match(/d(\d)/)[1]) + 1) % 3}.png`, 'in order: ' + seq.join(' ')); });
      assert.ok(onlyReads(pg));
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'P26: a photo that never answers counts as failed once the limit has passed: a presentation zone keeps turning over its other photos (never an empty frame) and a product keeps its name without the photo; the reads still reach the zone (a new price, a sold-out); a photo that failed is asked for again once the retry time has passed, never sooner, and comes back into the turn when it answers; no zone is «changing» for good',
    run: async ({ browser }) => {
      const T = { cada: 600, limite: 1500, reintento: 2000, zona: 200, fundido: 100, revisar: 200, diapositiva: 600000, permanencia: 600000 };
      const COLGADA = 'https://fotos.test/colgada.png', LATTE = 'https://fotos.test/latte-colgada.png', REINTENTO = 'https://fotos.test/reintento.png';
      const c = compo({ template: '3-grande-izq', zones: [
        { mode: 'auto', seconds: 4, labels: false, entries: ['https://fotos.test/a0.png', COLGADA, 'https://fotos.test/a2.png'] },   /* 4 s -> 800 ms a photo */
        { mode: 'fija', labels: true, entries: [{ item: 'Latte', photo: LATTE }] },
        { mode: 'auto', seconds: 4, labels: false, entries: ['https://fotos.test/b0.png', REINTENTO, 'https://fotos.test/b2.png'] }
      ] });
      /* in front of the usual photo route: two requests that never answer (left pending) and one answered 404 until
         the test says otherwise; every request is kept with its time and the answer it got */
      const pedidas = {}, respuesta = { reintento: 404 };
      const fotosTest = (x) => x.route(/^https:\/\/fotos\.test\/(colgada|latte-colgada|reintento)\.png$/, (r) => {
        const u = r.request().url(); (pedidas[u] = pedidas[u] || []).push({ t: Date.now(), status: u === REINTENTO ? respuesta.reintento : null });
        if (u !== REINTENTO) return new Promise(() => {});
        return respuesta.reintento === 404 ? r.fulfill({ status: 404, body: 'not found' }) : r.fulfill({ status: 200, contentType: 'image/png', body: PNG });
      });
      const pg = await pantalla(browser, { q: '?tv=promos-1&pulgadas=55&distancia=3&diag=1', test: T, setup: fotosTest });
      await until(async () => { const z = await zonas(pg); return z && z.id === c && z.zonas[0].estado === 'entrada' && z.zonas[2].estado === 'entrada'; }, 6000, 'up');
      await until(() => [COLGADA, LATTE, REINTENTO].every((u) => (pedidas[u] || []).length >= 1), 3000, 'every photo asked for');
      assert.deepStrictEqual([pedidas[COLGADA].length, pedidas[LATTE].length, pedidas[REINTENTO].length], [1, 1, 1], 'each asked for once with the first read');
      /* 5 s watched: what each zone shows and whether it is «changing» */
      const t0 = Date.now(), m = [];
      while (Date.now() - t0 < 5000) { m.push({ t: Date.now() - t0, z: await zonas(pg), c: await compoInfo(pg) }); await sleep(40); }
      assert.ok(m.every((x) => x.z && x.z.id === c && x.c && x.c.zonas.length === 3), 'the composition stays on screen');
      /* zone 1: the photo that never answers is given up at the limit and skipped; the other two take turns; never an empty frame */
      m.forEach((x) => assert.ok(x.z.zonas[0].capas.some((k) => k.on && k.img && k.lista && k.opacity >= 0.99), `${x.t} ms: zone 1 shows an opaque loaded photo at every moment: ` + JSON.stringify(x.z.zonas[0].capas)));
      assert.deepStrictEqual([...new Set(m.map((x) => x.z.zonas[0].entrada))].sort(), [0, 2], 'the two photos that answer take turns; the one that never answers is never up');
      assert.ok(!m.some((x) => x.z.zonas[0].capas.some((k) => k.src === COLGADA)), 'the photo that never answered is never on a layer');
      const c1 = cambios(m, 0);
      assert.ok(c1.length >= 2, `zone 1 kept turning (800 ms a photo, at most the 1.5 s limit lost on the one that never answers): ${c1.length} changes, at ${c1.join(', ')} ms`);
      /* zone 2: the product whose photo never answers shows its name and its live price without the photo once the limit passed */
      const nombre = m.find((x) => x.z.zonas[1].estado === 'entrada');
      assert.ok(nombre && nombre.t <= T.limite + 2000, 'the product shows once the limit passed: ' + (nombre ? nombre.t + ' ms' : 'never (the zone waits for its photo for good)'));
      assert.ok(m.filter((x) => x.t < nombre.t).every((x) => x.z.zonas[1].estado === '' && x.c.zonas[1].cambiando), 'until then the zone was loading (never the brand design)');
      const z2 = nombre.z.zonas[1];
      assert.deepStrictEqual([z2.tit, z2.titEn, digits(z2.precio), z2.nota, z2.src, z2.encuadre], ['Latte', null, 2200, null, null, null], 'the name and the live price, no photo: ' + JSON.stringify(z2));
      /* zone 3: the photo that answered 404 is skipped; the other two take turns; never an empty frame */
      m.forEach((x) => assert.ok(x.z.zonas[2].capas.some((k) => k.on && k.img && k.lista && k.opacity >= 0.99), `${x.t} ms: zone 3 shows an opaque loaded photo at every moment: ` + JSON.stringify(x.z.zonas[2].capas)));
      assert.deepStrictEqual([...new Set(m.map((x) => x.z.zonas[2].entrada))].sort(), [0, 2], 'zone 3 turns over the two photos that answer; the one that failed is never up');
      assert.ok(cambios(m, 2).length >= 2, 'zone 3 kept turning: ' + cambios(m, 2).join(', '));
      /* no zone «changing» for longer than the limit (and a dissolve): a switch that waits for a photo gives up */
      [0, 1, 2].forEach((i) => {
        let desde = null, mayor = 0;
        m.forEach((x) => { const on = x.c.zonas[i].cambiando; if (on && desde === null) desde = x.t; if (!on && desde !== null) { mayor = Math.max(mayor, x.t - desde); desde = null; } });
        if (desde !== null) mayor = Math.max(mayor, m[m.length - 1].t - desde);
        assert.ok(mayor <= T.limite + T.fundido + 1500, `zone ${i + 1} was «changing» for ${mayor} ms at a stretch`);
      });
      await until(async () => (await compoInfo(pg)).zonas.every((x) => !x.cambiando), T.limite + 2500, 'every zone at rest');
      await until(async () => /Zona 2: foto fija · 1 de 1 entrada con qué mostrar · con nombres y precios · muestra la 1 \(Latte, precio\)/.test(await diag(pg)), 3000, 'the diagnosis: the product shown, with its price');
      let d = await diag(pg);
      assert.ok(/Zona 1: presentación cada 4 s · [23] de 3 entradas/.test(d) && /Zona 3: presentación cada 4 s · [23] de 3 entradas con qué mostrar · sin textos · muestra la [13] \(solo foto\)/.test(d) && !/cargando/.test(d), d);
      /* the reads reach the zone: a new price is written in place, a sold-out takes the product away (the brand design), its return brings it back */
      sql(`update public.menu_items set price_crc = 2350 where name = 'Latte'`);
      /* (when the read meets a retry of the photo under way, the zone waits for it once more and redraws the same
         frame by a dissolve: the zone is read at rest) */
      await until(async () => { const j = await zonas(pg); return j && digits(j.zonas[1].precio) === 2350 && j.zonas[1].capas.filter((k) => k.on).length === 1; }, 8000, 'the new price in the zone');
      let z = await zonas(pg);
      assert.deepStrictEqual([z.zonas[1].estado, z.zonas[1].tit, z.zonas[1].src, z.zonas[1].entrada, (await info(pg)).actual], ['entrada', 'Latte', null, 0, c], JSON.stringify(z.zonas[1]));
      sql(`update public.menu_items set available = false where name = 'Latte'`);
      await until(async () => { const j = await zonas(pg); return j && j.id === c && j.zonas[1].estado === 'marca' && j.zonas[1].capas.filter((k) => k.on).length === 1; }, 8000, 'sold out: the brand design in zone 2');
      z = await zonas(pg);
      assert.ok(z.zonas[1].marca && !/Latte|₡/.test(z.zonas[1].text), JSON.stringify(z.zonas[1]));
      sql(`update public.menu_items set available = true where name = 'Latte'`);
      await until(async () => { const j = await zonas(pg); return j && j.zonas[1].estado === 'entrada' && j.zonas[1].tit === 'Latte' && j.zonas[1].src === null && digits(j.zonas[1].precio) === 2350; }, 8000, 'back in stock: the name again, still without its photo');
      /* the photo that answered 404 was asked for again, once per retry time and never sooner; when it answers at
         last it comes back into the turn, its zone's clock with it */
      const antes = pedidas[REINTENTO].length;
      assert.ok(antes >= 2 && pedidas[REINTENTO].every((x) => x.status === 404), 'asked for again while it kept failing: ' + antes + ' requests');
      respuesta.reintento = 200;
      await until(async () => { const j = await zonas(pg); return j && j.zonas[2].entrada === 1 && j.zonas[2].src === REINTENTO && j.zonas[2].capas.some((k) => k.on && k.src === REINTENTO && k.lista); }, 10000, 'the photo back in the turn once it answered');
      const ts = pedidas[REINTENTO], buena = ts.findIndex((x) => x.status === 200);
      assert.ok(buena >= antes, 'asked for again after the answer changed: ' + JSON.stringify(ts.map((x) => x.status)));
      ts.slice(0, buena + 1).forEach((x, k) => { if (k) assert.ok(x.t - ts[k - 1].t >= T.reintento - 100, `never asked for again before the retry time: ${x.t - ts[k - 1].t} ms between two requests`); });
      await until(async () => { const j = await compoInfo(pg); return j.zonas[2].mostrables === 3 && (j.zonas[2].reloj || j.zonas[2].cambiando); }, 4000, 'the three photos in the turn, the clock running');
      const m2 = await muestrear(pg, 2600, 40);
      assert.deepStrictEqual([...new Set(m2.map((x) => x.z.zonas[2].entrada))].sort(), [0, 1, 2], 'zone 3 turns over the three photos now: ' + cambios(m2, 2).join(', '));
      assert.ok(cambios(m2, 2).length >= 2 && m2.every((x) => x.z.id === c && x.z.zonas[2].capas.some((k) => k.on && k.img && k.lista && k.opacity >= 0.99)), 'the turn goes on, never an empty frame');
      assert.ok(/Zona 3: presentación cada 4 s · 3 de 3 entradas con qué mostrar/.test(await diag(pg)), await diag(pg));
      assert.ok(onlyReads(pg));
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'P27: a composition that comes back after another slide goes on from the entry after the one it showed when it left (every photo of a long presentation gets its turn); its single zone\'s first turn on every stay is its own seconds (the stagger of the other zones of a composition, on every stay: P28)',
    run: async ({ browser }) => {
      const c = compo({ template: '1', zones: [{ mode: 'auto', seconds: 5, labels: false, entries: fotos('v', 4) }] });   /* 5 s -> 2.5 s a photo here */
      const otra = marca('Otra');
      /* the composition stays 4 s (two photos), the brand slide 1.2 s, then the composition again */
      const pg = await pantalla(browser, { test: { diapositiva: 1200, permanencia: 4000, zona: 500, fundido: 200, revisar: 100 } });   /* a stay of 4 s: two photos, the third 1 s after it leaves */
      const t0 = Date.now(), m = [];
      while (Date.now() - t0 < 18000) { const i = await info(pg), z = await zonas(pg); m.push({ actual: i.actual, entrada: z && z.id === c ? z.zonas[0].entrada : null }); await sleep(40); }
      /* the stays: which slide, and the entries its zone showed, in order */
      const stays = [];
      m.forEach((x) => {
        if (!stays.length || stays[stays.length - 1].actual !== x.actual) stays.push({ actual: x.actual, entradas: [] });
        const r = stays[stays.length - 1];
        if (x.entrada != null && r.entradas[r.entradas.length - 1] !== x.entrada) r.entradas.push(x.entrada);
      });
      const vueltas = stays.filter((r) => r.actual === c);
      assert.ok(vueltas.length >= 3 && stays.some((r) => r.actual === otra), 'the composition left and came back twice: ' + JSON.stringify(stays));
      vueltas.forEach((r, k) => {
        if (k < vueltas.length - 1 || stays[stays.length - 1].actual !== c) assert.ok(r.entradas.length >= 2, `stay ${k + 1}: two photos per stay: ` + JSON.stringify(vueltas));   /* the sampling may end inside the last stay */
        r.entradas.forEach((e, n) => { if (n) assert.strictEqual(e, (r.entradas[n - 1] + 1) % 4, 'in order: ' + JSON.stringify(vueltas)); });
        if (k) { const antes = vueltas[k - 1].entradas; assert.strictEqual(r.entradas[0], (antes[antes.length - 1] + 1) % 4, `stay ${k + 1} goes on from the entry after the last one shown: ` + JSON.stringify(vueltas)); }
      });
      const vistas = new Set(); vueltas.forEach((r) => r.entradas.forEach((e) => vistas.add(e)));
      assert.deepStrictEqual([...vistas].sort(), [0, 1, 2, 3], 'every photo got its turn: ' + JSON.stringify(vueltas));
      assert.ok(onlyReads(pg));
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'P28: zones with the same seconds never change together, also when the composition comes back after another slide: the first turn is staggered on every start (zone i waits 1 + 0.25·i turns)',
    run: async ({ browser }) => {
      const c = compo({ template: '3-grande-izq', sort: 1, zones: ['s', 't', 'u'].map((p) => ({ mode: 'auto', seconds: 5, labels: false, entries: fotos(p, 3) })) });   /* 5 s -> 2.5 s a turn here */
      const otra = marca('Otra', { sort: 2 });
      /* the composition stays 4 s, the brand slide 1.2 s: zone 1 turns at 2.5 s, zone 2 at 3.1 s, zone 3 at 3.75 s of each
         stay (only zones 1 and 2 surely inside it). The first read is held back a second, so the sampling sees the
         composition's first stay start too */
      let primeraLectura = true;
      const retener = (x) => x.route(/\/rest\/v1\/rpc\/pantalla_datos/, async (r) => { if (primeraLectura) { primeraLectura = false; await sleep(1000); } return r.continue(); });
      const pg = await pantalla(browser, { wait: false, setup: retener, test: { diapositiva: 1200, permanencia: 4000, zona: 500, fundido: 200, revisar: 100 } });
      /* every ~25 ms: the page's own clock, the slide on screen and each zone's entry */
      const m = [], t0 = Date.now();
      while (Date.now() - t0 < 14000) {
        m.push(await pg.evaluate(() => { const i = PANTALLA_B.info(); return { t: performance.now(), actual: i.actual, e: i.composicion ? i.composicion.zonas.map((z) => z.entrada) : null }; }));
        await sleep(25);
      }
      /* the stays: runs of samples with the same slide; one whose start was seen (not the first sample) and that ended (not the last run) */
      const runs = [];
      m.forEach((x, k) => {
        if (!runs.length || runs[runs.length - 1].actual !== x.actual) runs.push({ actual: x.actual, desde: x.t, visto: k > 0, muestras: [] });
        runs[runs.length - 1].muestras.push(x);
      });
      runs.forEach((r, k) => { r.completa = k < runs.length - 1; });
      const estancias = runs.filter((r) => r.actual === c);
      /* each zone's first change in a stay, in ms from the stay's start (null: not seen in it) */
      const primerCambio = (r, i) => {
        let e0 = null;
        for (const x of r.muestras) {
          if (!x.e || !(x.e[i] >= 0)) continue;
          if (e0 === null) e0 = x.e[i]; else if (x.e[i] !== e0) return Math.round(x.t - r.desde);
        }
        return null;
      };
      const medidas = estancias.map((r, k) => ({ vuelta: k, visto: r.visto, completa: r.completa, primera: [0, 1, 2].map((i) => primerCambio(r, i)) }));
      const resumen = JSON.stringify({ medidas, runs: runs.map((r) => [r.actual === c ? 'c' : r.actual === otra ? 'otra' : r.actual, Math.round(r.desde)]) });
      const medibles = medidas.filter((x) => x.visto && (x.completa || (x.primera[0] !== null && x.primera[1] !== null)));
      assert.ok(medidas.length >= 2 && medidas[0].visto && medidas[0].completa, 'the first stay seen from its start to its end: ' + resumen);
      assert.ok(medibles.some((x) => x.vuelta >= 1 && x.completa), 'the composition came back after the brand slide and stayed: ' + resumen);
      medibles.forEach((x) => {
        const [a, b, d] = x.primera, cual = (x.vuelta ? 'stay ' + (x.vuelta + 1) + ' (back after the brand slide)' : 'the first stay') + ': ';
        assert.ok(a !== null && b !== null, cual + 'zones 1 and 2 both changed inside the stay: ' + resumen);
        assert.ok(a >= 2000, cual + 'zone 1 waited its turn (2.5 s) before its first change: ' + resumen);
        assert.ok(b - a >= 400, cual + 'zone 2 changed well after zone 1 (a quarter of a turn later, 0.6 s): ' + resumen);
        if (d !== null) assert.ok(d > b, cual + 'zone 3 changed after zone 2: ' + resumen);
      });
      /* never the three zones within the same 150 ms, in any stay */
      const eventos = [];
      estancias.forEach((r) => r.muestras.forEach((x, k) => {
        const a = r.muestras[k - 1];
        if (k && a.e && x.e) x.e.forEach((v, i) => { if (a.e[i] >= 0 && v >= 0 && v !== a.e[i]) eventos.push({ i, t: Math.round(x.t) }); });
      }));
      assert.ok(eventos.length >= 4, 'the zones turned: ' + JSON.stringify(eventos));
      eventos.forEach((ev) => {
        const juntas = new Set(eventos.filter((o) => o.t >= ev.t && o.t - ev.t <= 150).map((o) => o.i));
        assert.ok(juntas.size < 3, `the three zones changed together at ${ev.t} ms: ` + JSON.stringify(eventos) + ' ' + resumen);
      });
      assert.ok(onlyReads(pg));
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'P29: a small zone that cannot hold the name, its English and the price at the distance\'s letter drops the English first and keeps the name and the price at full size; a zone where everything fits keeps the English, also on the layer that hid it for a long name; without a kicker the brand line shrinks before it goes',
    run: async ({ browser }) => {
      /* names whose Spanish and English differ, set here (the test does not lean on the site's dictionary) */
      sql(`update public.menu_items set name_es = 'Té' where name = 'Tea';
           update public.menu_items set name_es = 'Latte frío' where name = 'Iced Latte';
           update public.menu_items set name_es = 'Jamón y queso' where name = 'Ham & Cheese';
           update public.menu_items set name_es = 'Moca' where name = 'Mocha'`);
      ['Tea', 'Iced Latte', 'Ham & Cheese', 'Mocha'].forEach((n) => assert.ok(itemId(n), 'the test menu has ' + n));
      /* 4-centro on the café's 32" TV read from 3 m: the two centre zones are small (476 x 538 px) */
      const c = compo({ template: '4-centro', kicker_es: 'Desayuno', kicker_en: 'Breakfast', zones: [
        { entries: [{ item: 'Tea', photo: 'https://fotos.test/te.png' }] },                  /* large: a short name */
        { entries: [{ item: 'Tea', photo: 'https://fotos.test/te.png' }] },                  /* small: the same name */
        { entries: [{ item: 'Iced Latte', photo: 'https://fotos.test/latte.png' }] },        /* small */
        /* large: a long name, then two short ones; three entries on two layers, so the third (Tea) lands on the layer
           that carried the long name with its English hidden */
        { mode: 'auto', seconds: 4, entries: [{ item: 'Ham & Cheese', photo: 'https://fotos.test/jamon.png' }, { item: 'Mocha', photo: 'https://fotos.test/moca.png' },
                                              { item: 'Tea', photo: 'https://fotos.test/te.png' }] }
      ] });
      const pg = await pantalla(browser, { q: '?tv=promos-1&pulgadas=32&distancia=3&diag=1', test: { diapositiva: 600000, permanencia: 600000, zona: 300, fundido: 100, revisar: 150 } });
      const pxCm = 1920 / LARGO_CM(32), tol = 1;   /* 1 px */
      const ZT = { grande: 1.0, pequena: 0.8 }, ZTE = 0.64 / 0.8, ZP = 1.2;   /* ZFACT: the name per metre, the English 0.8 x it, the price 1.2 x it */
      /* each zone's front layer at rest: its texts, shown or not, and their capitals in px; the brand line and the kicker */
      const leer = () => pg.evaluate(() => {
        const cx = document.createElement('canvas').getContext('2d');
        const cap = (e) => { const cs = getComputedStyle(e); cx.font = cs.fontWeight + ' ' + cs.fontSize + ' ' + cs.fontFamily; return cx.measureText('H').actualBoundingBoxAscent; };
        const vis = (e) => !!e && e.getClientRects().length > 0;
        const sl = document.querySelector('#stage:not(.apagado) .capa.on .sl.k-composicion');
        if (!sl) return null;
        const kk = sl.querySelector('.zkick'), kr = kk && kk.getBoundingClientRect();
        return {
          id: sl.dataset.id, sup: vis(sl.querySelector('.sup')),
          kick: vis(kk) ? { t: kk.textContent, cap: cap(kk), dentro: kr.left >= -1 && kr.right <= innerWidth + 1 && kr.top >= -1, cortado: kk.scrollWidth > kk.clientWidth + 1 } : null,
          zonas: [...sl.querySelectorAll('.zona')].map((z) => {
            const on = z.querySelectorAll('.zcapa.on'), f = on.length === 1 ? on[0] : null, g = (r) => f && f.querySelector('[data-r="' + r + '"]');
            const tx = f && f.querySelector('.ztxt');
            return { tamano: z.dataset.tamano, quieta: !!f && !f.classList.contains('sale'), capa: f ? [...z.querySelectorAll('.zcapa')].indexOf(f) : -1, zsinen: !!f && f.classList.contains('zsinen'),
                     tit: g('zt') ? g('zt').textContent : null, en: g('zte') ? g('zte').textContent : null,
                     enVisible: vis(g('zte')), zt: vis(g('zt')) ? cap(g('zt')) : null, zte: vis(g('zte')) ? cap(g('zte')) : null, zp: vis(g('zp')) ? cap(g('zp')) : null,
                     cortado: !!f && [...f.querySelectorAll('[data-r]')].some((e) => vis(e) && e.scrollWidth > e.clientWidth + 1),
                     mitad: tx ? tx.scrollHeight <= z.clientHeight / 2 + 1 : null };
          })
        };
      });
      await until(async () => { const v = await leer(); return v && v.id === c && v.zonas.every((x) => x.quieta && x.tit); }, 8000, 'the four zones up with their labels');
      const v = await leer(), ci = await compoInfo(pg), z = v.zonas, txt = JSON.stringify(v);
      assert.deepStrictEqual(z.map((x) => x.tamano), ['grande', 'pequena', 'pequena', 'grande'], txt);
      /* the small zones: the English line is there but not shown; the name and the price at the full letter of a small zone for 3 m */
      [1, 2].forEach((i) => {
        const x = z[i], at = `small zone ${i + 1} (${x.tit}): `;
        assert.ok(x.en && !x.enVisible && x.zte === null, at + 'the English is not shown: ' + txt);
        assert.ok(x.zt >= ZT.pequena * 3 * pxCm - tol, at + `the name at ${(x.zt / pxCm).toFixed(2)} cm, the distance's letter is ${(ZT.pequena * 3).toFixed(2)} cm`);
        assert.ok(x.zp >= ZT.pequena * ZP * 3 * pxCm - tol, at + `the price at ${(x.zp / pxCm).toFixed(2)} cm, the distance's letter is ${(ZT.pequena * ZP * 3).toFixed(2)} cm`);
        assert.ok(!x.cortado && x.mitad, at + 'nothing cut, the labels in the lower half: ' + txt);
        assert.deepStrictEqual([ci.zonas[i].sinIngles, ci.zonas[i].k, ci.zonas[i].cabe], [true, 1, true], at + JSON.stringify(ci.zonas[i]));
      });
      assert.deepStrictEqual([z[1].tit, z[1].en, z[2].tit, z[2].en], ['Té', 'Tea', 'Latte frío', 'Iced Latte'], txt);
      /* the large zone with a short name: everything fits, the English stays, all at the full letter */
      const g = z[0];
      assert.ok(g.tit === 'Té' && g.en === 'Tea' && g.enVisible, 'the large zone keeps its English: ' + txt);
      assert.ok(g.zt >= ZT.grande * 3 * pxCm - tol && g.zte >= ZT.grande * ZTE * 3 * pxCm - tol && g.zp >= ZT.grande * ZP * 3 * pxCm - tol && !g.cortado && g.mitad,
        `the large zone at the full letter: name ${(g.zt / pxCm).toFixed(2)} cm, English ${(g.zte / pxCm).toFixed(2)}, price ${(g.zp / pxCm).toFixed(2)}`);
      assert.deepStrictEqual([ci.zonas[0].sinIngles, ci.zonas[0].k], [false, 1], JSON.stringify(ci.zonas[0]));
      /* the decision is per photo: in the large presentation zone the long name loses its English, the short one keeps it */
      const enZona4 = async (tit) => { await until(async () => { const j = await leer(); return j && j.zonas[3].quieta && j.zonas[3].tit === tit; }, 8000, tit + ' in zone 4'); return [(await leer()).zonas[3], (await compoInfo(pg)).zonas[3]]; };
      let [x4, c4] = await enZona4('Jamón y queso');
      assert.ok(x4.en === 'Ham & Cheese' && !x4.enVisible && x4.zsinen && c4.sinIngles && x4.zt >= ZT.grande * 3 * pxCm - tol && !x4.cortado, 'a long name in a large zone: no English, the name at the full letter: ' + JSON.stringify(x4));
      const capaJamon = x4.capa;
      assert.ok(capaJamon === 0 || capaJamon === 1, 'the layer of the long name: ' + JSON.stringify(x4));
      [x4, c4] = await enZona4('Moca');
      assert.ok(x4.en === 'Mocha' && x4.enVisible && !c4.sinIngles && x4.zte >= ZT.grande * ZTE * 3 * pxCm - tol, 'the next photo, a short name, keeps its English: ' + JSON.stringify(x4));
      /* the third photo, a short name, is drawn on the very layer that hid the English for «Jamón y queso»: the layer's
         «no English» goes with the long name, the short one shows its English at the full letter */
      await until(async () => { const j = await leer(); return j && j.zonas[3].quieta && j.zonas[3].tit === 'Té' && j.zonas[3].capa === capaJamon; }, 8000, 'Té in zone 4 on the layer of «Jamón y queso»');
      [x4, c4] = [(await leer()).zonas[3], (await compoInfo(pg)).zonas[3]];
      assert.ok(x4.tit === 'Té' && x4.capa === capaJamon && x4.en === 'Tea' && x4.enVisible && !x4.zsinen && !x4.cortado && x4.zte >= ZT.grande * ZTE * 3 * pxCm - tol,
        'a short name on the layer that hid the English keeps its English: ' + JSON.stringify(x4));
      assert.deepStrictEqual([c4.titulo, c4.sinIngles, c4.k, c4.cabe], ['Té', false, 1, true], JSON.stringify(c4));
      /* the diagnosis names the zone that dropped its English, and not the one that kept it */
      const lineas = (await diag(pg)).split('\n'), linea = (n) => lineas.find((l) => l.indexOf('Zona ' + n + ':') === 0) || '';
      assert.ok(/\(Té, precio\)$/.test(linea(1)) && /\(Té, precio\) · sin inglés \(no cabe\)$/.test(linea(2)) && /\(Latte frío, precio\) · sin inglés \(no cabe\)$/.test(linea(3)), lineas.join('\n'));
      /* the top edge of the same TV: the brand line and the kicker do not fit side by side even at 0.85, so the brand line
         goes and the kicker, alone, keeps the distance's full letter (0.8 cm per metre) */
      assert.ok(!v.sup, 'the brand line gives way on the 32" TV from 3 m: ' + txt);
      assert.ok(v.kick && v.kick.t === 'Desayuno · Breakfast' && v.kick.dentro && !v.kick.cortado, 'the kicker shown, inside the screen: ' + JSON.stringify(v.kick));
      assert.ok(v.kick.cap >= 0.8 * 3 * pxCm - tol, `the kicker at ${(v.kick.cap / pxCm).toFixed(2)} cm, the distance's letter is ${(0.8 * 3).toFixed(2)} cm`);
      assert.ok(onlyReads(pg));
      assert.deepStrictEqual(pg.errors, []);
      /* a composition WITHOUT a kicker: the brand line has the top edge to itself; it takes the largest of 1, 0.85, 0.72
         and 0.6 of the distance's letter (0.8 cm per metre) that fits, and goes only when it does not fit even at 0.6 */
      const sk = compo({ template: '1', zones: [{ entries: [{ item: 'Tea', photo: 'https://fotos.test/te.png' }] }] });
      const marcaSola = async (dist) => {
        const p2 = await pantalla(browser, { q: `?tv=promos-1&pulgadas=32&distancia=${dist}&diag=1`, test: { diapositiva: 600000, permanencia: 600000, zona: 300, fundido: 100, revisar: 150 } });
        await mostrar(p2, sk);
        const leerSup = () => p2.evaluate(() => {
          const cx = document.createElement('canvas').getContext('2d');
          const sl = document.querySelector('#stage:not(.apagado) .capa.on .sl.k-composicion');
          if (!sl) return null;
          const s = sl.querySelector('.sup'), vis = !!s && s.getClientRects().length > 0, r = vis ? s.getBoundingClientRect() : null, cs = s && getComputedStyle(s);
          if (vis) cx.font = cs.fontWeight + ' ' + cs.fontSize + ' ' + cs.fontFamily;
          return { id: sl.dataset.id, kick: !!sl.querySelector('.zkick'), vis: vis, t: s ? s.textContent : null, cap: vis ? cx.measureText('H').actualBoundingBoxAscent : null,
                   ancho: vis ? s.scrollWidth : null, dentro: !!r && r.left >= -1 && r.right <= innerWidth + 1 && r.top >= -1 };
        });
        await until(async () => { const j = await leerSup(); return j && j.id === sk; }, 8000, 'the composition without a kicker on the 32" TV from ' + dist + ' m');
        const b = await leerSup();
        assert.deepStrictEqual(p2.errors, []);
        return Object.assign(b, { letra: 0.8 * dist * pxCm });
      };
      const libre = 1920 - 2 * Math.round(0.03 * 1080);   /* the top edge less the margins */
      /* the café's 32" from 3 m: alone, the brand line fits at the full letter (about 1500 px of the 1856 free), so it
         shows unshrunk; it is the kicker that sends it away (above) */
      const m3 = await marcaSola(3);
      assert.ok(!m3.kick && m3.vis && m3.t === 'Hanging Garden Café' && m3.dentro && m3.ancho <= libre, 'without a kicker the brand line shows on the 32" TV from 3 m: ' + JSON.stringify(m3));
      assert.ok(m3.cap >= m3.letra - tol, `the brand line at ${(m3.cap / pxCm).toFixed(2)} cm, the distance's letter is ${(m3.letra / pxCm).toFixed(2)} cm: ` + JSON.stringify(m3));
      /* the same TV from 5 m: the brand line does not fit even at 0.85, but it does at 0.72 or 0.6: it shrinks and stays
         (it used to go as soon as 0.85 failed) */
      const m5 = await marcaSola(5);
      assert.ok(!m5.kick && m5.vis && m5.t === 'Hanging Garden Café' && m5.dentro && m5.ancho <= libre, 'without a kicker the brand line shrinks, not hidden, on the 32" TV from 5 m: ' + JSON.stringify(m5));
      assert.ok(m5.cap >= 0.6 * m5.letra - tol && m5.cap <= 0.72 * m5.letra + tol,
        `the brand line at ${(m5.cap / m5.letra).toFixed(2)} of the distance's letter (0.72 or 0.6 expected): ` + JSON.stringify(m5));
    }
  },
];
