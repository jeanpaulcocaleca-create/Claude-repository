/* Screen B (website/pantalla-promos.html, docs/PANTALLAS.md, migration 0036): products, brand and invitations for the
   guests. The owner's conditions it is held to here:
   3) names, prices, photos and availability read only from the menu (through pantalla_datos), never written; it polls;
   4) a lost connection or old data never shows an expired slide or an unverified price as current;
   5) read from a distance: big prices, little else, nothing outside the screen;
   6) nothing new: the site, the public key and the TV's browser; nothing stored on the device;
   7) combos and discounts never announced (the till's helpers never show).
   Slides are written straight into the test database (as its superuser): pantallas.html, which writes them for the
   owner, has its own tests. */
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const { page, goto, until, sql } = require('../lib');

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
      assert.ok(await pg.evaluate(() => document.querySelector('.capa.on img.foto').classList.contains('ok')), 'the photo loaded and shows');
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
          await mostrar(pg, key === 'marca-propia' ? 'marca' : ids[key]);
          const m = await medir(pg), i = await info(pg), at = `${where} ${key}`;
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
            assert.ok(caps('p').length === 1 && caps('p')[0] >= 1.5 * 3 - tol, `${at}: price capital ${caps('p')[0]} cm (1.5 cm/m)`);
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
  }
];
