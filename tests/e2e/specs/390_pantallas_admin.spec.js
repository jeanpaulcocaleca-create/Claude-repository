/* The owner's page for the customer TVs (website/pantallas.html + pantallas.js, migration 0036, docs/PANTALLAS.md).
   The owner's conditions it is held to here:
   2) a new page only: no PIN box of its own (340 still counts 19), the shared PIN screen of access.js;
   3) prices and availability only from the menu, never written (a product slide stores the item, not its price);
   6) nothing new: Storage's existing bucket for the photos;
   7) combos and discounts never announced: blocked while typing and refused by the server;
   8) only with the owner's PIN (or the owner login with the phone code), the server's own checks and a change log.
   Also: an unknown address is refused before any client exists, Spanish only, and a slide made here is what the
   promotions TV reads (pantalla_datos).
   v2 (migration 0037): the menu TV's layout, density, English and intercalated promotions; compositions of 1 to 4
   zones built in the visual editor (template, products from the picker, uploaded photos, focus and zoom), refused by
   the server next to the zone and the entry, previewed in the real TV page before saving; «Programación sugerida»
   creates four paused compositions from the menu (without names and prices, the owner's 2026-11-02 request); «Hoy en
   pantalla» lists a composition with its zones. The menu TV's products (item_ids, a summarised menu for a 32" at 3 m):
   ticked per product under their categories, saved, logged and read by the TV; none = every product. The final 32"/3 m
   validation: the suggested windows turn at seconds of their own, a zone with nothing to show says so in the list, a
   menu TV's preview says its pages and letter (or NO CABE) and reads it only while open, «Cambiar foto» replaces an
   entry's photo in its place (the entry itself, even moved meanwhile) and an upload that ends late never puts the older
   photo back, and the idle sign-out leaves no photo uploaded for a preview behind. */
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const { page, goto, until, sql, STAFF, PINS, SITE, ROOT } = require('../lib');
const { STORE } = require('../gateway');

const PORT = Number(process.env.E2E_SITE_PORT || 8090), API = 'http://127.0.0.1:' + (PORT + 1000);
const PGRST = 'http://127.0.0.1:' + (process.env.E2E_PGRST_PORT || 3013);
const OWNER = '0e000000-0000-4000-8000-000000000002';
const CAT = { coffee: 'a0000000-0000-4000-8000-000000000001', pastries: 'a0000000-0000-4000-8000-000000000006' };
const crMin = (ms) => (((Math.floor(ms / 60000) - 360) % 1440) + 1440) % 1440;
const PHOTO = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64');

/* q run as the owner login with the phone code, through the SQL functions like the page; returns q's last value */
function asOwner(q) {
  const out = sql(`select set_config('request.jwt.claims', '{"sub":"${OWNER}","role":"authenticated","aal":"aal2"}', false); select set_config('request.jwt.claim.sub', '${OWNER}', false); set role authenticated; ${q}; reset role;`);
  return out.split('\n').filter((l) => !/^(SET|RESET)$/.test(l)).pop();
}
const one = (q) => sql(q);
/* the page may draw the PIN screen again while it loads: type only into the last one, once it lists people (350) */
async function lastGate(pg) {
  await pg.waitForSelector('.hga-wrap #hgaPin', { timeout: 10000 });
  await until(() => pg.evaluate(() => new Promise((ok) => {
    const w = document.querySelector('.hga-wrap');
    setTimeout(() => ok(!!w && w === document.querySelector('.hga-wrap') && w.querySelectorAll('#hgaWho option').length > 1), 700);
  })), 12000, 'the last PIN screen, with its list of people');
}
/* the PIN typed with real keys (keypad.js wipes a PIN put in any other way) */
async function unlockAs(pg, who) {
  await lastGate(pg);
  await pg.selectOption('#hgaWho', STAFF[who]);
  await pg.type('#hgaPin', PINS[who]);
  await pg.press('#hgaPin', 'Enter');
}
/* the page on its own device; every database function it calls is kept in pg.rpc. opts.init runs in every frame
   before its scripts (the preview frame reads window.PANTALLA_TEST); test photos (fotos.test, the CDN and the local
   Storage's public addresses) answer with a 1 x 1 PNG */
async function open(browser, opts) {
  opts = Object.assign({ login: 'cafe', lang: 'es' }, opts || {});
  const pg = await page(browser, opts);
  if (opts.init) await pg.addInitScript(opts.init);
  pg.rpc = []; pg.deletes = [];   /* the functions called; the Storage removals asked for (bucket and body) */
  pg.on('request', (r) => {
    const m = /\/rest\/v1\/rpc\/([a-z_]+)/.exec(r.url()); if (m) pg.rpc.push(m[1]);
    if (r.method() === 'DELETE' && /\/storage\/v1\/object\//.test(r.url())) pg.deletes.push(r.url() + ' ' + (r.postData() || ''));
  });
  await pg.route(/cloudfront\.net|fotos\.test|\/storage\/v1\/object\/public\//, (r) => r.fulfill({ status: 200, contentType: 'image/png', body: PHOTO }));
  await goto(pg, '/pantallas');
  return pg;
}
const itemId = (name) => one(`select id from menu_items where name = '${name.replace(/'/g, "''")}' limit 1`);
/* a composition put straight into the table (0037 shape): entries by item name or photo address */
function compo(o) {
  const q = (v) => v == null ? 'null' : `'${String(v).replace(/'/g, "''")}'`;
  const entry = (e) => typeof e === 'string' ? { item: null, photo: e, focus: [50, 50], zoom: 100 }
    : { item: e.item ? itemId(e.item) : null, photo: e.photo || null, focus: e.focus || [50, 50], zoom: e.zoom || 100 };
  const zones = o.zones.map((z) => ({ mode: z.mode || 'fija', seconds: z.seconds == null ? 8 : z.seconds, labels: z.labels !== false,
                                       fallback: z.fallback || null, entries: z.entries.map(entry) }));
  return one(`insert into screen_slides (kind, template, zones, dwell_seconds, kicker_es, kicker_en, screen_ids, starts_at, ends_at, days, from_time, to_time, sort, status, created_by)
    values ('composicion', ${q(o.template)}, ${q(JSON.stringify(zones))}::jsonb, ${o.dwell == null ? 'null' : o.dwell}, ${q(o.kicker_es)}, ${q(o.kicker_en)},
            ${o.screens ? q('{' + o.screens.join(',') + '}') : 'null'}, ${o.starts || "now() - interval '1 hour'"}, ${o.ends || "now() + interval '1 day'"},
            ${o.days ? q('{' + o.days.join(',') + '}') : 'null'}, ${q(o.from)}, ${q(o.to)}, ${o.sort == null ? 100 : o.sort}, ${q(o.status || 'activa')}, 'prueba') returning id`).split('\n')[0];
}
/* the composition drawn in the preview frame: its template, anything over its zones (none since 2026-11-03) and, per
   zone, what is in front */
const zonasEn = (frame) => frame.evaluate(() => {
  const sl = document.querySelector('#stage:not(.apagado) .capa.on .sl.k-composicion');
  if (!sl) return null;
  return { template: sl.dataset.template, kick: (sl.querySelector('.zkick') || {}).textContent || null, sup: (sl.querySelector('.sup') || {}).textContent || null,
    zonas: [...sl.querySelectorAll('.zona')].map((z) => {
      const front = z.querySelector('.zcapa.on.entra') || z.querySelector('.zcapa.on:not(.sale)') || z.querySelector('.zcapa.on');
      const f = (s) => { const e = front && front.querySelector(s); return e ? e.textContent : null; };
      return { modo: z.dataset.modo, estado: z.dataset.estado, tit: f('.ztit'), precio: f('.zprecio'), src: front ? front.dataset.src || null : null };
    }) };
});
/* the entries' zoom slider and focus readout of an entry in the editor */
const encuadre = (pg, sel) => pg.evaluate((s) => {
  const li = document.querySelector(s), i = li.querySelector('.frame img');
  return { zoom: li.querySelector('input[type=range]').value, focus: li.querySelector('.focus').textContent, pos: i ? i.style.objectPosition : null, tr: i ? i.style.transform : null };
}, sel);
const slideJson = (id) => JSON.parse(one(`select json_build_object('kind', kind, 'template', template, 'dwell', dwell_seconds, 'kicker', kicker_es, 'kicker_en', kicker_en, 'title', title_es, 'zones', zones)::text from screen_slides where id = '${id}'`));
async function asOwnerPin(browser, opts) {
  const pg = await open(browser, opts);
  await unlockAs(pg, 'dueno');
  await pg.waitForSelector('#appView:not([hidden]) article.tv', { timeout: 12000 });
  return pg;
}
async function tab(pg, t) { await pg.click('#tab-' + t); await pg.waitForSelector('#sec-' + t + ':not([hidden])'); }
/* clicks a save button and waits for «Guardado» */
async function save(pg, sel) {
  await pg.evaluate(() => { const t = document.getElementById('toast'); t.classList.remove('show'); t.textContent = ''; });
  await pg.click(sel);
  await until(() => pg.evaluate(() => { const t = document.getElementById('toast'); return t.classList.contains('show') && t.textContent === 'Guardado'; }), 10000, '«Guardado»');
}
const text = (pg, sel) => pg.evaluate((s) => { const e = document.querySelector(s); return e ? e.textContent.replace(/\s+/g, ' ').trim() : null; }, sel);
/* as the owner reads it (blocks and flex items apart) */
const inner = (pg, sel) => pg.evaluate((s) => { const e = document.querySelector(s); return e ? e.innerText.replace(/\s+/g, ' ').trim() : null; }, sel);
const slides = () => Number(one('select count(*) from screen_slides'));
function marca(title, extra) {
  return one(`insert into screen_slides (kind, title_es, starts_at, ends_at, created_by ${extra ? ', ' + Object.keys(extra).join(', ') : ''})
              values ('marca', '${title}', now() - interval '1 hour', now() + interval '20 days', 'prueba'
                      ${extra ? ', ' + Object.values(extra).join(', ') : ''}) returning id`).split('\n')[0];
}
/* width and height of a JPEG (its SOF marker) */
function jpegSize(b) {
  for (let i = 2; i < b.length - 9;) {
    if (b[i] !== 0xFF) { i++; continue; }
    const m = b[i + 1], len = b.readUInt16BE(i + 2);
    if (m >= 0xC0 && m <= 0xCF && m !== 0xC4 && m !== 0xC8 && m !== 0xCC) return { h: b.readUInt16BE(i + 5), w: b.readUInt16BE(i + 7) };
    i += 2 + len;
  }
  return null;
}
const photos = () => [...STORE.keys()].filter((k) => k.startsWith('menu-photos/pantallas/'));
async function anonDatos(pg, tv) {
  const key = await pg.evaluate(() => HG_CONFIG.key);
  const r = await fetch(API + '/rest/v1/rpc/pantalla_datos?p_tv=' + tv, { headers: { apikey: key, Authorization: 'Bearer ' + key } });
  assert.strictEqual(r.status, 200, 'pantalla_datos answers the public key');
  return r.json();
}

module.exports.tests = [
  {
    name: 'an unknown address is refused before any client exists (no request to any database)',
    run: async ({ browser }) => {
      const pg = await page(browser, { login: 'cafe', lang: 'es' });
      const seen = [];
      pg.on('request', (r) => { if (/\/(rest|auth|storage)\/v1\/|supabase\.co/.test(r.url())) seen.push(r.url()); });
      await pg.goto('http://127.0.0.2:' + PORT + '/pantallas', { waitUntil: 'domcontentloaded' });
      await until(async () => (await pg.locator('text=Esta copia de Canopy OS no está autorizada.').count()) > 0, 8000, 'the refusal');
      await pg.waitForTimeout(1200);
      assert.strictEqual(pg.supabaseHits, 0, 'never the real Supabase');
      assert.deepStrictEqual(seen, [], 'no database request at all');
      assert.strictEqual(await pg.locator('#loginView, #appView, .hga-wrap').count(), 0, 'no sign-in, no page, no PIN screen');
      assert.ok(pg.errors.every((e) => /environment not allowed here/.test(e)), 'only the deliberate stop: ' + pg.errors.join(' | '));
    }
  },
  {
    name: 'without a sign-in: the sign-in form in Spanish; a wrong password says why in Spanish; the café login then asks for the owner\'s PIN',
    run: async ({ browser }) => {
      const pg = await open(browser, { login: null });
      await pg.waitForSelector('#loginView:not([hidden]) #loginForm:not([hidden])', { timeout: 10000 });
      assert.strictEqual(await pg.locator('#appView').isHidden(), true, 'nothing of the TVs');
      assert.strictEqual(await text(pg, '#loginBtn'), 'Ingresar');
      await until(async () => (await text(pg, '.hgl-show')) === 'Mostrar', 4000, 'login.js\'s Show button in Spanish');
      await pg.fill('#em', 'cafe@test.local');
      await pg.fill('#pw', 'not-the-password');
      await pg.click('#loginBtn');
      await until(async () => /El correo o la contraseña no son correctos/.test(await text(pg, '#loginErr')), 8000, 'the reason, in Spanish');
      assert.strictEqual(await text(pg, '#loginBtn'), 'Ingresar', 'login.js put its English back; the page keeps Spanish');
      await pg.fill('#pw', 'test');
      await pg.click('#loginBtn');
      await lastGate(pg);
      assert.strictEqual(await text(pg, '#hgaTitle'), 'Pantallas · solo el dueño');
      assert.strictEqual(await text(pg, '.hga-msg'), 'Abra con el PIN del dueño.');
      assert.strictEqual(await pg.locator('article.tv').count(), 0, 'no data before the PIN');
      assert.ok(!pg.rpc.includes('pantallas_estado'), 'the screens are not even asked for before a PIN');
      const leak = await pg.evaluate(() => document.getElementById('pg').innerText);
      assert.ok(!/\b(Sign in|Signing|Show|Email|Password|Forgot)\b/.test(leak), 'no English on the page itself: ' + leak);
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'café login + a manager\'s PIN (Ana): only «solo el dueño», no data; its button ends the unlock and asks again',
    run: async ({ browser }) => {
      const pg = await open(browser);
      const answers = [];
      pg.on('response', async (r) => { if (/rpc\/pantallas_estado/.test(r.url())) { try { answers.push(await r.json()); } catch (e) {} } });
      await unlockAs(pg, 'ana');
      await pg.waitForSelector('#ownerOnlyView:not([hidden])', { timeout: 10000 });
      assert.strictEqual(await text(pg, '#ownerOnlyMsg'), 'Solo el dueño puede cambiar las pantallas. Abra con el PIN del dueño.');
      await until(() => answers.length, 4000, 'the server\'s answer');
      assert.deepStrictEqual(answers[0], { ok: false, error: 'owner_only' }, 'the server itself says no');
      assert.strictEqual(await pg.locator('#appView').isHidden(), true);
      assert.strictEqual(await pg.locator('article.tv, article.slide, article.chg, .pick').count(), 0, 'nothing of the screens on the page');
      const body = await pg.evaluate(() => document.body.innerText);
      assert.ok(!/menu-1|promos-1|Pantalla A/.test(body), 'no TV is named');
      assert.ok(!pg.rpc.some((f) => /pantalla_guardar|diapositiva_/.test(f)), 'nothing was written');
      assert.strictEqual(Number(one(`select count(*) from access_unlocks where staff_id = '${STAFF.ana}'`)), 1, 'Ana\'s unlock is open');
      await pg.click('#ownerOnlyLock');
      await lastGate(pg);
      assert.strictEqual(Number(one(`select count(*) from access_unlocks where staff_id = '${STAFF.ana}'`)), 0, 'and ended on the server (access_lock)');
      assert.strictEqual(Number(one('select count(*) from screen_changes')), 0);
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'café login + the owner\'s PIN (typed): the TVs, their addresses, the categories and the menu\'s items, never Extras & Combos',
    run: async ({ browser }) => {
      const pg = await asOwnerPin(browser);
      assert.deepStrictEqual(await pg.$$eval('article.tv', (a) => a.map((x) => x.getAttribute('data-tv'))), ['menu-1', 'promos-1']);
      assert.match(await text(pg, '#who'), /Dueño \(owner\)/);
      assert.strictEqual(await pg.locator('.hga-pill').count(), 1, 'the shared notice with Lock');
      assert.strictEqual(await pg.locator('#outBtn').isHidden(), true, 'the café tablet is never signed out from here (the Caja would be too)');
      const cats = Number(one(`select count(*) from menu_categories where name <> 'Extras & Combos'`));
      assert.strictEqual(await pg.locator('article.tv[data-tv="menu-1"] input[data-cat]').count(), cats, 'every category of the menu but Extras & Combos');
      assert.strictEqual(await pg.locator('article.tv[data-tv="promos-1"] input[data-cat]').count(), 0, 'categories only on the menu TV');
      assert.strictEqual(await pg.locator('#tv-menu-1-page_seconds').count(), 1);
      assert.strictEqual(await pg.locator('#tv-promos-1-slide_seconds').count(), 1);
      assert.strictEqual(await text(pg, 'article.tv[data-tv="menu-1"] code[data-addr]'), SITE + '/pantalla-menu?tv=menu-1');
      assert.strictEqual(await text(pg, 'article.tv[data-tv="promos-1"] code[data-addr]'), SITE + '/pantalla-promos?tv=promos-1');
      await tab(pg, 'slides');
      await pg.click('#newSlide');
      await pg.waitForSelector('#slideForm .pick');
      const items = Number(one(`select count(*) from menu_items i join menu_categories c on c.id = i.category_id where c.name <> 'Extras & Combos' and i.price_crc > 0`));
      assert.strictEqual(await pg.locator('#edPicker .pick').count(), items, 'the menu\'s items with a price');
      const picks = await pg.$$eval('#edPicker .pick', (a) => a.map((x) => x.textContent));
      assert.ok(!picks.some((t) => /Extras & Combos/.test(t)), 'never Extras & Combos');
      await pg.fill('#edSearch', 'banana');
      await until(async () => (await pg.locator('#edPicker .pick').count()) === 1, 4000, 'the search');
      assert.match(await inner(pg, '#edPicker .pick'), /Banana Bread Pastries & Cake · ₡1 500$/);
      const leak = await pg.evaluate(() => [...document.querySelectorAll('#pg button, #pg label, #pg h1, #pg h2, #pg legend')].map((e) => e.textContent).join(' | '));
      assert.ok(!/\b(Save|Cancel|Sign out|Loading|Preview|Copy)\b/.test(leak), 'Spanish only: ' + leak);
      assert.strictEqual(await pg.evaluate(() => document.getElementById('pg').hasAttribute('data-no-translate')), true);
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'the owner login with the phone code opens it without a PIN',
    run: async ({ browser }) => {
      const pg = await open(browser, { login: 'owner', aal: 'aal2' });
      await pg.waitForSelector('#appView:not([hidden]) article.tv', { timeout: 12000 });
      assert.strictEqual(await pg.locator('.hga-wrap').count(), 0, 'no PIN screen');
      assert.match(await text(pg, '#who'), /Ingreso del dueño · owner@test\.local/);
      await pg.fill('#tv-promos-1-slide_seconds', '12');
      await save(pg, 'article.tv[data-tv="promos-1"] button[type=submit]');
      assert.strictEqual(one(`select slide_seconds || ' ' || updated_by from screens where id = 'promos-1'`), '12 owner login · owner@test.local');
      await pg.click('#outBtn');
      await pg.waitForSelector('#loginView:not([hidden]) #loginForm:not([hidden])', { timeout: 8000 });
      assert.strictEqual(await pg.locator('#appView').isHidden(), true);
      assert.strictEqual(await pg.locator('article.tv, article.slide, article.chg').count(), 0, 'signed out: nothing of the screens stays on the page');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'a TV\'s settings: checked in the page, saved, logged with «Dueño (owner)»; a new TV; no connection says so',
    run: async ({ browser, setOffline }) => {
      const pg = await asOwnerPin(browser);
      const card = 'article.tv[data-tv="menu-1"]';
      await pg.fill('#tv-menu-1-inches', '200');
      await pg.click(card + ' button[type=submit]');
      await until(async () => /Tamaño: de 24 a 110 pulgadas/.test(await text(pg, card + ' .err')), 4000, 'the page\'s check');
      assert.ok(!pg.rpc.includes('pantalla_guardar'), 'nothing sent');
      assert.match(await text(pg, card + ' .dirty'), /Cambios sin guardar/);
      await pg.fill('#tv-menu-1-inches', '65');
      await pg.fill('#tv-menu-1-distance_m', '4.5');
      await pg.selectOption('#tv-menu-1-turn', 'derecha');
      await pg.fill('#tv-menu-1-scale_pct', '110');
      await pg.selectOption('#tv-menu-1-look', 'noche');
      await pg.fill('#tv-menu-1-page_seconds', '30');
      await pg.selectOption('#tv-menu-1-sold_out', 'tachar');
      await pg.check(`${card} input[data-cat][value="${CAT.coffee}"]`);
      await pg.check(`${card} input[data-cat][value="${CAT.pastries}"]`);
      await pg.fill('#tv-menu-1-on_from', '06:00');
      await pg.fill('#tv-menu-1-on_to', '19:00');
      await save(pg, card + ' button[type=submit]');
      assert.strictEqual(one(`select concat_ws(' ', inches, distance_m, turn, scale_pct, look, page_seconds, sold_out, on_from, on_to, active, updated_by) from screens where id = 'menu-1'`),
        '65.0 4.5 derecha 110 noche 30 tachar 06:00:00 19:00:00 t Dueño (owner)');
      assert.strictEqual(one(`select category_ids = array['${CAT.coffee}', '${CAT.pastries}']::uuid[] or category_ids = array['${CAT.pastries}', '${CAT.coffee}']::uuid[] from screens where id = 'menu-1'`), 't');
      assert.strictEqual(await pg.locator(card + ' .dirty').isHidden(), true, 'saved: nothing pending');
      assert.strictEqual(await pg.inputValue('#tv-menu-1-inches'), '65', 'the card shows what the server keeps');

      await tab(pg, 'log');
      const first = pg.locator('#logList article.chg').first();
      assert.strictEqual(await first.getAttribute('data-target'), 'tv:menu-1');
      assert.strictEqual(await first.getAttribute('data-action'), 'cambiar');
      assert.match(await first.innerText(), /Cambió la TV menu-1[\s\S]*por Dueño \(owner\)/);
      await first.locator('summary').click();
      assert.strictEqual(await first.locator('tr[data-k="inches"] td.was').innerText(), '55');
      assert.strictEqual(await first.locator('tr[data-k="inches"] td.now').innerText(), '65');
      assert.match(await first.locator('tr[data-k="category_ids"] td.now').innerText(), /Coffee/);
      assert.strictEqual(one(`select count(*) || ' ' || max(by_name) from screen_changes where target_id = 'menu-1' and action = 'cambiar'`), '1 Dueño (owner)');

      await tab(pg, 'tvs');
      await pg.fill('#newId', 'Promos 2');
      await pg.click('#addTvBtn');
      await until(async () => /El identificador lleva/.test(await text(pg, '#addTvErr')), 4000, 'a bad id refused in the page');
      await pg.fill('#newId', 'menu-1');
      await pg.click('#addTvBtn');
      await until(async () => /Ya hay una TV con ese identificador/.test(await text(pg, '#addTvErr')), 4000, 'an existing id is never overwritten');
      await pg.fill('#newId', 'promos-2');
      await pg.selectOption('#newKind', 'promos');
      await pg.fill('#newName', 'Pantalla de la terraza');
      await save(pg, '#addTvBtn');
      await pg.waitForSelector('article.tv[data-tv="promos-2"]');
      assert.strictEqual(one(`select kind || ' ' || name || ' ' || inches from screens where id = 'promos-2'`), 'promos Pantalla de la terraza 55.0');
      assert.strictEqual(one(`select action || ' ' || by_name from screen_changes where target_id = 'promos-2'`), 'crear Dueño (owner)');

      setOffline(true);
      await pg.fill('#tv-promos-1-scale_pct', '120');
      await pg.click('article.tv[data-tv="promos-1"] button[type=submit]');
      await until(async () => /Sin conexión/.test(await text(pg, 'article.tv[data-tv="promos-1"] .err')), 10000, '«Sin conexión»');
      setOffline(false);
      assert.strictEqual(one(`select scale_pct from screens where id = 'promos-1'`), '100', 'nothing changed');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'three slides from the page: a product (no price stored), the brand and an invitation with its days, hours and TV',
    run: async ({ browser }) => {
      const pg = await asOwnerPin(browser);
      await tab(pg, 'slides');
      const latte = one(`select id from menu_items where name = 'Latte' limit 1`);
      await pg.click('#newSlide');
      await pg.fill('#edSearch', 'latte');
      await pg.click(`#edPicker .pick[data-item="${latte}"]`);
      assert.match(await text(pg, '#edChosen'), /Elegido: Latte/);
      await pg.fill('#ed-kicker_es', 'Recién hecho');
      await pg.fill('#ed-kicker_en', 'Freshly made');
      await save(pg, '#edSave');
      assert.strictEqual(await pg.locator('#slideForm').count(), 0, 'the editor closes');
      const p = one(`select concat_ws('|', kind, menu_item_id, kicker_es, coalesce(title_es, '-'), coalesce(photo_url, '-'), coalesce(days::text, '-'), coalesce(screen_ids::text, '-'), status, created_by,
                       round(extract(epoch from (ends_at - starts_at)) / 86400), abs(extract(epoch from (starts_at - now()))) < 180) from screen_slides`);
      assert.strictEqual(p, ['producto', latte, 'Recién hecho', '-', '-', '-', '-', 'activa', 'Dueño (owner)', '30', 't'].join('|'),
        'the item only (its name, photo and price stay in the menu), from now, for 30 days, every day, every promotions TV');

      await pg.click('#newSlide');
      await pg.check('input[name=edKind][value=marca]');
      assert.strictEqual(await pg.locator('#edProduct').isHidden(), true);
      await pg.fill('#ed-title_es', 'Café de altura de Monteverde');
      await pg.fill('#ed-title_en', 'Highland coffee from Monteverde');
      await save(pg, '#edSave');

      await pg.click('#newSlide');
      await pg.check('input[name=edKind][value=invitacion]');
      await pg.fill('#ed-title_es', '¿Le gustó su visita?');
      await pg.fill('#ed-title_en', 'Loved your visit?');
      assert.deepStrictEqual(await pg.$$eval('#edLink option', (o) => o.map((x) => x.textContent)), ['Reseña en Tripadvisor', 'El menú en el teléfono'],
        'the QR goes to Tripadvisor (the only approved review link, E-35) or to the QR menu, and the page says so');
      await pg.selectOption('#edLink', 'resena');
      await pg.click('.days button[data-day="7"]');
      await pg.fill('#edFrom', '07:00');
      await pg.fill('#edTo', '11:30');
      await pg.check('#edTvs input[value="promos-1"]');
      await pg.fill('#edSort', '30');
      await save(pg, '#edSave');
      assert.strictEqual(one(`select concat_ws('|', link, days::text, from_time, to_time, screen_ids::text, sort) from screen_slides where kind = 'invitacion'`),
        'resena|{1,2,3,4,5,6}|07:00:00|11:30:00|{promos-1}|30');
      assert.strictEqual(one(`select string_agg(kind || ':' || action || ':' || by_name, ',' order by c.id) from screen_changes c join screen_slides s on s.id::text = c.target_id`),
        'producto:crear:Dueño (owner),marca:crear:Dueño (owner),invitacion:crear:Dueño (owner)');
      assert.strictEqual(await pg.locator('#slideList article.slide').count(), 3);
      assert.match(await text(pg, '#nSlides'), /^3$/);
      const inv = one(`select id from screen_slides where kind = 'invitacion'`);
      assert.match(await text(pg, `article.slide[data-slide="${inv}"] .meta`), /Lun, mar, mié, jue, vie, sáb · de 07:00 a 11:30/);
      const lat = one(`select id from screen_slides where kind = 'producto'`);
      assert.match(await inner(pg, `article.slide[data-slide="${lat}"] .t`), /^Latte · Producto: Latte · Coffee · ₡[\d ]+ en el menú$/);
      assert.match(await text(pg, `article.slide[data-slide="${lat}"] [data-status]`), /Activa/);
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'a price or a combo in a text is blocked while typing and, sent past the page, refused by the server; dates are required',
    run: async ({ browser }) => {
      const pg = await asOwnerPin(browser);
      await tab(pg, 'slides');
      await pg.click('#newSlide');
      await pg.check('input[name=edKind][value=marca]');
      for (const [v, re] of [['Latte a ₡1500', /Sin precios/], ['Combo desayuno', /Sin combos ni descuentos/], ['Hoy 20% menos', /Sin precios/],
                             ['2x1 en lattes', /Sin combos/], ['Café de altura', null]]) {
        await pg.fill('#ed-title_es', v);
        const err = await text(pg, '#err-title_es');
        if (re) assert.match(err, re, v); else assert.strictEqual(err, '', v);
        assert.strictEqual(await pg.locator('#edSave').isDisabled(), !!re, 'Guardar ' + (re ? 'blocked' : 'open') + ' for ' + v);
      }
      await pg.fill('#ed-title_en', 'Special price today');
      assert.match(await text(pg, '#err-title_en'), /Sin combos ni descuentos/);
      await pg.fill('#ed-title_en', '');
      await pg.fill('#ed-body_es', 'x'.repeat(141));
      assert.match(await text(pg, '#err-body_es'), /Máximo 140 letras/);
      assert.match(await pg.getAttribute('#cnt-body_es', 'class'), /over/);
      await pg.fill('#ed-body_es', '');
      assert.strictEqual(slides(), 0);
      assert.ok(!pg.rpc.includes('diapositiva_guardar'), 'nothing sent while blocked');

      // sent past the page: the server refuses with its own reason, said in Spanish
      await pg.fill('#ed-title_es', 'Latte a ₡1500');
      await pg.evaluate(() => { window.PANTALLAS_TEST = { sinRevisar: true }; document.getElementById('slideForm').requestSubmit(); });
      await until(async () => /Sin precios en el texto[\s\S]*\(el título \(español\)\)/.test(await text(pg, '#edErr')), 8000, 'the server\'s text_precio');
      await pg.fill('#ed-title_es', 'Combo desayuno');
      await pg.evaluate(() => document.getElementById('slideForm').requestSubmit());
      await until(async () => /Sin combos ni descuentos[\s\S]*\(el título \(español\)\)/.test(await text(pg, '#edErr')), 8000, 'the server\'s text_combo_descuento');
      assert.strictEqual(slides(), 0, 'nothing kept');
      assert.strictEqual(pg.rpc.filter((f) => f === 'diapositiva_guardar').length, 2, 'both reached the server');

      // dates: the page asks for both; sent without an end, the server refuses too
      await pg.evaluate(() => { window.PANTALLAS_TEST = {}; });
      await pg.fill('#ed-title_es', 'Café de altura');
      await pg.fill('#edEnd', '');
      await pg.click('#edSave');
      await until(async () => /sin fin no se publica/.test(await text(pg, '#edErr')), 4000, 'the page\'s check');
      assert.strictEqual(pg.rpc.filter((f) => f === 'diapositiva_guardar').length, 2, 'not sent');
      await pg.evaluate(() => { window.PANTALLAS_TEST = { sinRevisar: true }; document.getElementById('edErr').textContent = ''; document.getElementById('slideForm').requestSubmit(); });
      await until(async () => /sin fin no se publica/.test(await text(pg, '#edErr')), 8000, 'the server\'s dates_required');
      assert.strictEqual(pg.rpc.filter((f) => f === 'diapositiva_guardar').length, 3);
      assert.strictEqual(slides(), 0);
      assert.strictEqual(asOwner(`select public.diapositiva_guardar('{"kind":"marca","title_es":"Hola","starts_at":"2026-11-01T08:00:00-06:00"}')->>'error'`), 'dates_required', 'the server, directly');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'pause, resume and retire: the confirmation is in the page (no browser dialog); a retired slide cannot be edited',
    run: async ({ browser }) => {
      const id = marca('Bienvenidos al bosque');
      const pg = await asOwnerPin(browser);
      let dialogs = 0;
      pg.onDialog = async (d) => { dialogs++; await d.dismiss(); };
      await tab(pg, 'slides');
      const row = `article.slide[data-slide="${id}"]`;
      assert.match(await text(pg, row + ' [data-when]'), /En pantalla ahora/);
      // edit: its dates in Costa Rica time, its type fixed; a text changed and logged
      await pg.click(row + ' [data-act=editar]');
      await pg.waitForSelector('#slideForm');
      assert.strictEqual(await text(pg, '#slideForm h2'), 'Editar la diapositiva');
      assert.strictEqual(await pg.inputValue('#edStart'), one(`select to_char(starts_at at time zone 'America/Costa_Rica', 'YYYY-MM-DD"T"HH24:MI') from screen_slides where id = '${id}'`));
      assert.strictEqual(await pg.locator('input[name=edKind]:not([disabled])').count(), 0, 'the type never changes');
      assert.strictEqual(await pg.inputValue('#ed-title_es'), 'Bienvenidos al bosque');
      await pg.fill('#ed-title_en', 'Welcome to the forest');
      await save(pg, '#edSave');
      assert.strictEqual(one(`select title_en || ' ' || updated_by from screen_slides where id = '${id}'`), 'Welcome to the forest Dueño (owner)');
      await save(pg, row + ' [data-act=pausar]');
      assert.strictEqual(one(`select status from screen_slides where id = '${id}'`), 'pausada');
      assert.match(await text(pg, row + ' [data-status]'), /Pausada/);
      await save(pg, row + ' [data-act=reanudar]');
      assert.strictEqual(one(`select status from screen_slides where id = '${id}'`), 'activa');
      await pg.click(row + ' [data-act=retirar]');
      await pg.waitForSelector(row + ' .confirm');
      assert.match(await text(pg, row + ' .confirm'), /¿Retirar «Bienvenidos al bosque» para siempre\?/);
      await pg.click(row + ' .confirm [data-act=no]');
      assert.strictEqual(await pg.locator(row + ' .confirm').count(), 0);
      assert.strictEqual(one(`select status from screen_slides where id = '${id}'`), 'activa', '«No» changes nothing');
      await pg.click(row + ' [data-act=retirar]');
      await save(pg, row + ' .confirm [data-act=confirmar]');
      assert.strictEqual(one(`select status from screen_slides where id = '${id}'`), 'retirada');
      assert.strictEqual(await pg.locator(row).count(), 0, 'retired slides are put away');
      await pg.click('#showRetired');
      await pg.waitForSelector(row);
      assert.strictEqual(await pg.locator(row + ' [data-act]').count(), 0, 'no Editar, Pausar, Reanudar or Retirar');
      assert.match(await text(pg, row), /no se edita ni vuelve a salir/);
      assert.strictEqual(asOwner(`select public.diapositiva_guardar('{"id":"${id}","title_es":"Otra vez"}')->>'error'`), 'retired', 'the server refuses an edit');
      assert.strictEqual(asOwner(`select public.diapositiva_estado('${id}', 'activa')->>'error'`), 'retired', 'and bringing it back');
      assert.strictEqual(one(`select string_agg(action || ':' || by_name, ',' order by id) from screen_changes where target_id = '${id}'`),
        'cambiar:Dueño (owner),pausar:Dueño (owner),reanudar:Dueño (owner),retirar:Dueño (owner)');
      await tab(pg, 'log');
      assert.match(await inner(pg, '#logList article.chg'), /Retiró la diapositiva «Bienvenidos al bosque» por Dueño \(owner\)/);
      const edit = pg.locator('#logList article.chg[data-action=cambiar]');
      await edit.locator('summary').click();
      assert.strictEqual(await edit.locator('tr[data-k="title_en"] td.was').innerText(), '—');
      assert.strictEqual(await edit.locator('tr[data-k="title_en"] td.now').innerText(), 'Welcome to the forest');
      assert.strictEqual(await edit.locator('tr').count(), 2, 'only what changed (and the header)');
      assert.strictEqual(dialogs, 0, 'never a browser dialog');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'a photo: made smaller in the browser (JPEG, 1600 px wide), kept in Storage under menu-photos/pantallas/, used by the slide; over 8 MB refused',
    run: async ({ browser }) => {
      const pg = await asOwnerPin(browser);
      await tab(pg, 'slides');
      await pg.click('#newSlide');
      await pg.check('input[name=edKind][value=marca]');
      await pg.fill('#ed-title_es', 'El jardín colgante');
      await pg.check('input[name=edPhotoMode][value=propia]');
      const before = photos();
      await pg.setInputFiles('#photoFile', { name: 'enorme.jpg', mimeType: 'image/jpeg', buffer: Buffer.alloc(8 * 1024 * 1024 + 100, 1) });
      await until(async () => /pesa más de 8 MB/.test(await text(pg, '#edPhotoMsg')), 4000, 'over 8 MB refused');
      // a phone photo: 3200 x 2133, high quality
      const b64 = await pg.evaluate(async () => {
        const c = document.createElement('canvas'); c.width = 3200; c.height = 2133;
        const x = c.getContext('2d'), g = x.createLinearGradient(0, 0, 3200, 2133);
        g.addColorStop(0, '#1E4B33'); g.addColorStop(0.5, '#B98A35'); g.addColorStop(1, '#F6F1E2');
        x.fillStyle = g; x.fillRect(0, 0, 3200, 2133);
        for (let i = 0; i < 4000; i++) { x.fillStyle = 'hsl(' + ((i * 37) % 360) + ',60%,' + (25 + (i % 6) * 10) + '%)'; x.fillRect((i * 997) % 3200, (i * 613) % 2133, 9 + (i % 40), 7 + (i % 30)); }
        const blob = await new Promise((r) => c.toBlob(r, 'image/jpeg', 1));
        return await new Promise((r) => { const f = new FileReader(); f.onload = () => r(String(f.result).split(',')[1]); f.readAsDataURL(blob); });
      });
      const original = Buffer.from(b64, 'base64');
      await pg.setInputFiles('#photoFile', { name: 'foto.jpg', mimeType: 'image/jpeg', buffer: original });
      await until(async () => /Lista: 1600 × 1067 px/.test(await text(pg, '#edPhotoMsg')), 8000, 'the photo made smaller');
      assert.deepStrictEqual(photos(), before, 'nothing uploaded before Guardar');
      await save(pg, '#edSave');
      const url = one(`select photo_url from screen_slides where title_es = 'El jardín colgante'`);
      const m = /\/storage\/v1\/object\/public\/menu-photos\/(pantallas\/[0-9a-f-]{36}\.jpg)$/.exec(url);
      assert.ok(m, 'the public address of menu-photos/pantallas/<uuid>.jpg: ' + url);
      const added = photos().filter((k) => !before.includes(k));
      assert.deepStrictEqual(added, ['menu-photos/' + m[1]], 'one new file, the one the slide uses');
      const kept = STORE.get(added[0]);
      assert.strictEqual(kept.type, 'image/jpeg');
      assert.deepStrictEqual([...kept.body.slice(0, 3)], [0xFF, 0xD8, 0xFF], 'a JPEG');
      assert.ok(kept.body.length < original.length, 'smaller than the original: ' + kept.body.length + ' < ' + original.length);
      assert.deepStrictEqual(jpegSize(kept.body), { w: 1600, h: 1067 }, 'at most 1600 px wide, same proportions');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: '«Hoy en pantalla»: what is on now on each promotions TV, and what starts later today, with the screen\'s rules',
    run: async ({ browser }) => {
      const on = marca('Ahora sí');
      marca('En pausa', { status: `'pausada'` });
      one(`insert into screen_slides (kind, title_es, starts_at, ends_at) values ('marca', 'Ya vencida', now() - interval '2 days', now() - interval '1 minute')`);
      one(`insert into screen_slides (kind, title_es, starts_at, ends_at, screen_ids) values ('marca', 'Solo en otra TV', now() - interval '1 hour', now() + interval '1 day', '{promos-9}')`);
      one(`update menu_items set available = false where name = 'Espresso'`);
      const gone = one(`insert into screen_slides (kind, menu_item_id, starts_at, ends_at) select 'producto', id, now() - interval '1 hour', now() + interval '1 day' from menu_items where name = 'Espresso' limit 1 returning id`).split('\n')[0];
      const minute = crMin(Date.now()), later = minute < 21 * 60;    // a start in 90 minutes is still today in Costa Rica
      if (later) one(`insert into screen_slides (kind, title_es, starts_at, ends_at) values ('marca', 'Más tarde', now() + interval '90 minutes', now() + interval '3 days')`);
      const pg = await asOwnerPin(browser);
      await tab(pg, 'today');
      const card = 'article.today[data-today="promos-1"]';
      await pg.waitForSelector(card);
      assert.deepStrictEqual(await pg.$$eval(card + ' ol[data-list=ahora] li', (a) => a.map((x) => x.querySelector('b').textContent)), ['Ahora sí'],
        'only what is on: not paused, not ended, not for another TV, not a sold-out product');
      assert.strictEqual(await pg.locator(`${card} li[data-slide="${on}"]`).count(), 1);
      if (later) assert.match(await inner(pg, card + ' ol[data-list=luego]'), /^Más tarde Marca · desde las \d\d:\d\d$/);
      else assert.match(await text(pg, card), /Nada más hoy/);
      assert.match(await text(pg, card + ' h2'), /Encendida siempre/);
      await tab(pg, 'slides');
      assert.match(await text(pg, `article.slide[data-slide="${gone}"] [data-when]`), /No sale: producto agotado/);
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'the preview shows the real TV page in a scaled frame, turned like a vertical TV hangs',
    run: async ({ browser }) => {
      one(`update screens set turn = 'derecha' where id = 'promos-1'`);
      const pg = await asOwnerPin(browser, { viewport: { width: 1280, height: 900 } });
      const menu = 'article.tv[data-tv="menu-1"]', promos = 'article.tv[data-tv="promos-1"]';
      await pg.click(menu + ' [data-preview]');
      await pg.waitForSelector(menu + ' .pv iframe');
      assert.strictEqual(await pg.getAttribute(menu + ' .pv iframe', 'src'), 'pantalla-menu?tv=menu-1');
      const fit = await pg.evaluate((s) => { const f = document.querySelector(s + ' .pv iframe').getBoundingClientRect(); return { w: f.width, h: f.height }; }, menu);
      assert.ok(fit.w > 300 && fit.w < 700 && Math.abs(fit.w / fit.h - 16 / 9) < 0.01, '1920 x 1080 scaled to the card: ' + JSON.stringify(fit));
      if (fs.existsSync(path.join(ROOT, 'website/pantalla-menu.html'))) {
        const frame = await until(() => pg.frames().find((f) => /pantalla-menu\?tv=menu-1/.test(f.url())), 8000, 'the frame');
        await frame.waitForSelector('#stage', { timeout: 10000 });
      }
      await pg.click(promos + ' [data-preview]');
      await pg.waitForSelector(promos + ' .pv.vertical iframe');
      assert.strictEqual(await pg.getAttribute(promos + ' .pv iframe', 'src'), 'pantalla-promos?tv=promos-1');
      const turned = await pg.evaluate((s) => {
        const pv = document.querySelector(s + ' .pv'), f = pv.querySelector('iframe'), r = f.getBoundingClientRect();
        return { tall: r.height > r.width, ratio: r.height / r.width, m: getComputedStyle(f).transform };
      }, promos);
      assert.ok(turned.tall && Math.abs(turned.ratio - 16 / 9) < 0.01, 'a vertical TV: the frame stands up ' + JSON.stringify(turned));
      assert.match(turned.m, /^matrix\(0(\.0+)?(e-\d+)?, -/, 'turned back left for «derecha»: ' + turned.m);
      if (fs.existsSync(path.join(ROOT, 'website/pantalla-promos.html'))) {
        const frame = await until(() => pg.frames().find((f) => /pantalla-promos\?tv=promos-1/.test(f.url())), 8000, 'the frame');
        await frame.waitForSelector('meta[name="hg-build"]', { state: 'attached', timeout: 10000 });
      }
      await pg.click(menu + ' [data-preview]');
      assert.strictEqual(await pg.locator(menu + ' .pv').count(), 0, 'closed again');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'end to end: a slide made in the page is what pantalla_datos gives the promotions TV, and leaves it when paused',
    run: async ({ browser }) => {
      const pg = await asOwnerPin(browser);
      await tab(pg, 'slides');
      await pg.click('#newSlide');
      await pg.check('input[name=edKind][value=marca]');
      await pg.fill('#ed-kicker_es', 'Desde 2019');
      await pg.fill('#ed-title_es', 'Café del bosque nuboso');
      await pg.fill('#ed-title_en', 'Cloud forest coffee');
      await save(pg, '#edSave');
      const latte = one(`select id from menu_items where name = 'Latte' limit 1`);
      await pg.click('#newSlide');
      await pg.fill('#edSearch', 'latte');
      await pg.click(`#edPicker .pick[data-item="${latte}"]`);
      await save(pg, '#edSave');
      const d = await anonDatos(pg, 'promos-1');
      assert.strictEqual(d.ok, true);
      const brand = d.slides.find((s) => s.kind === 'marca'), prod = d.slides.find((s) => s.kind === 'producto');
      assert.ok(brand && brand.title_es === 'Café del bosque nuboso' && brand.title_en === 'Cloud forest coffee' && brand.kicker_es === 'Desde 2019', JSON.stringify(d.slides));
      assert.strictEqual(prod.menu_item_id, latte);
      assert.strictEqual(prod.item.price_crc, Number(one(`select price_crc from menu_items where id = '${latte}'`)), 'the price, read from the menu');
      one(`update menu_items set price_crc = price_crc + 100 where id = '${latte}'`);
      assert.strictEqual((await anonDatos(pg, 'promos-1')).slides.find((s) => s.kind === 'producto').item.price_crc,
        Number(one(`select price_crc from menu_items where id = '${latte}'`)), 'a new price in the menu is the new price on the TV');
      assert.deepStrictEqual((await anonDatos(pg, 'menu-1')).slides, [], 'the menu TV gets no slides');
      const row = `article.slide[data-slide="${brand.id}"]`;
      await save(pg, row + ' [data-act=pausar]');
      assert.ok(!(await anonDatos(pg, 'promos-1')).slides.some((s) => s.id === brand.id), 'paused: off the TV');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'v2 · the menu TV\'s layout, density, English and intercalated promotions: saved, logged, read by the TV; out of range the page says so and, sent past the page, the server refuses by field',
    run: async ({ browser }) => {
      const pg = await asOwnerPin(browser);
      const card = 'article.tv[data-tv="menu-1"]';
      assert.strictEqual(await pg.locator('#tv-promos-1-layout, #tv-promos-1-promo_mode').count(), 0, 'only the menu TV has them');
      assert.deepStrictEqual(await pg.$$eval('#tv-menu-1-layout option', (o) => o.map((x) => x.value)), ['auto', 'una-pantalla', 'paginas']);
      assert.deepStrictEqual([await pg.inputValue('#tv-menu-1-promo_every'), await pg.inputValue('#tv-menu-1-promo_seconds'), await pg.inputValue('#tv-menu-1-promo_mode')], ['180', '10', 'no'], 'the 0037 defaults');
      await pg.selectOption('#tv-menu-1-layout', 'una-pantalla');
      await pg.selectOption('#tv-menu-1-density', 'compacta');
      await pg.selectOption('#tv-menu-1-english', 'en-linea');
      await pg.selectOption('#tv-menu-1-promo_mode', 'intercalar');
      await pg.fill('#tv-menu-1-promo_every', '120');
      await pg.fill('#tv-menu-1-promo_seconds', '8');
      await save(pg, card + ' button[type=submit]');
      assert.strictEqual(one(`select concat_ws(' ', layout, density, english, promo_mode, promo_every, promo_seconds, updated_by) from screens where id = 'menu-1'`),
        'una-pantalla compacta en-linea intercalar 120 8 Dueño (owner)');
      const d = await anonDatos(pg, 'menu-1');
      assert.deepStrictEqual([d.tv.layout, d.tv.density, d.tv.english, d.tv.promo_mode, d.tv.promo_every, d.tv.promo_seconds], ['una-pantalla', 'compacta', 'en-linea', 'intercalar', 120, 8], 'what the TV reads');
      await tab(pg, 'log');
      const first = pg.locator('#logList article.chg').first();
      await first.locator('summary').click();
      assert.strictEqual(await first.locator('tr[data-k="promo_mode"] td.now').innerText(), 'Intercalar las diapositivas asignadas a esta TV');
      assert.strictEqual(await first.locator('tr[data-k="promo_every"] td.was').innerText(), '180');
      assert.strictEqual(await first.locator('tr[data-k="density"] td.now').innerText(), 'Compacta: más líneas, menos aire');
      await tab(pg, 'tvs');
      await pg.fill('#tv-menu-1-promo_every', '20');
      await pg.click(card + ' button[type=submit]');
      await until(async () => /Una promoción cada: de 30 a 900 segundos/.test(await text(pg, card + ' .err')), 4000, 'the page\'s check');
      assert.strictEqual(pg.rpc.filter((f) => f === 'pantalla_guardar').length, 1, 'not sent');
      await pg.evaluate(() => { window.PANTALLAS_TEST = { sinRevisar: true }; });
      await pg.click(card + ' button[type=submit]');
      await until(async () => /Revise cada cuántos segundos van las promociones\./.test(await text(pg, card + ' .err')), 8000, 'the server\'s invalid/promo_every');
      assert.match(await pg.getAttribute('#tv-menu-1-promo_every', 'class'), /bad/, 'marked at the field');
      assert.strictEqual(one(`select promo_every from screens where id = 'menu-1'`), '120', 'nothing changed');
      /* a menu TV that intercalates promotions can now be assigned slides, and appears in «Hoy en pantalla» */
      await tab(pg, 'slides');
      await pg.click('#newSlide');
      assert.deepStrictEqual(await pg.$$eval('#edTvs input', (a) => a.map((x) => x.value)), ['menu-1', 'promos-1']);
      assert.match(await text(pg, '#edTvs'), /Pantalla A · menú \(menú, con promociones\)/);
      await tab(pg, 'today');
      assert.match(await text(pg, 'article.today[data-today="menu-1"]'), /las intercala cada 120 s, durante 8 s/);
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'v2 · a composition in the visual editor: template 4-centro, a fixed zone and three presentations, products from the picker, an uploaded photo, focus and zoom; saved exactly as written and read back; edited and saved again, the order stays',
    run: async ({ browser }) => {
      one(`update menu_items set photo_url = 'https://fotos.test/croissant.png' where name = 'Butter Croissant'`);
      const pg = await asOwnerPin(browser, { viewport: { width: 1280, height: 900 } });
      await tab(pg, 'slides');
      const croissant = itemId('Butter Croissant'), icedLatte = itemId('Iced Latte'), icedAm = itemId('Iced Americano'), latte = itemId('Latte'), ham = itemId('Ham & Cheese');
      await pg.click('#newCompo');
      await pg.waitForSelector('#slideForm #edZones .zone');
      assert.strictEqual(await text(pg, '#slideForm h2'), 'Nueva composición');
      assert.strictEqual(await pg.isChecked('input[name=edKind][value=composicion]'), true);
      assert.strictEqual(await pg.locator('#edTemplates .tpl').count(), 6, 'six templates, each with its small scheme');
      assert.strictEqual(await pg.locator('#edTemplates .tpl[data-template="4-centro"] .mini i').count(), 4);
      assert.strictEqual(await pg.locator('#edPhotoBox').isHidden(), true, 'a composition\'s photos live in its zones');
      assert.strictEqual(await pg.locator('#pair-title').isHidden(), true, 'no title');
      await pg.click('#edTemplates .tpl[data-template="2-lado"]');
      assert.strictEqual(await pg.locator('#edZones .zone').count(), 2);
      await pg.click('#edTemplates .tpl[data-template="4-centro"]');
      assert.deepStrictEqual(await pg.$$eval('#edZones .zone h3 > span:first-child', (a) => a.map((x) => x.textContent)), ['Izquierda', 'Centro arriba', 'Centro abajo', 'Derecha'],
        'one zone editor per place, named as the owner sees the TV');
      assert.deepStrictEqual(await pg.$$eval('#edZones .zone', (a) => a.map((z) => getComputedStyle(z).gridArea.split(' / ')[0])), ['a', 'b', 'c', 'd']);
      const zone = (i) => `#edZones .zone[data-zone="${i}"]`;
      const add = async (i, q, item) => {
        if ((await pg.getAttribute(`#edZ-${i}-add`, 'aria-pressed')) !== 'true') await pg.click(`#edZ-${i}-add`);
        await pg.fill(`#edZ-${i}-search`, q);
        await pg.click(`#edZ-${i}-picker .pick[data-item="${item}"]`);
      };
      /* left: a fixed croissant, framed with a tap and the zoom slider */
      await pg.click('#edZ-0-mode-fija');
      assert.strictEqual(await pg.locator('#edZ-0-seconds').isHidden(), true, 'a fixed photo has no seconds');
      await add(0, 'butter', croissant);
      assert.match(await inner(pg, zone(0) + ' .entry[data-entry="0"] .einfo b'), /^1\. Butter Croissant · ₡1 500 en el menú$/);
      const fr = await pg.locator(zone(0) + ' .entry[data-entry="0"] .frame').boundingBox();
      await pg.mouse.click(fr.x + fr.width * 0.25, fr.y + fr.height * 0.8);
      const focus = await until(async () => { const m = /Enfoque (\d+) %, (\d+) %/.exec(await text(pg, zone(0) + ' .entry[data-entry="0"] .focus')); return m && Number(m[1]) !== 50 ? [Number(m[1]), Number(m[2])] : null; }, 3000, 'the focus point');
      assert.ok(Math.abs(focus[0] - 25) <= 2 && Math.abs(focus[1] - 80) <= 2, 'where the tap landed: ' + focus);
      await pg.evaluate((s) => { const z = document.querySelector(s + ' input[type=range]'); z.value = 150; z.dispatchEvent(new Event('input', { bubbles: true })); }, zone(0) + ' .entry[data-entry="0"]');
      assert.deepStrictEqual(await encuadre(pg, zone(0) + ' .entry[data-entry="0"]'), { zoom: '150', focus: `Enfoque ${focus[0]} %, ${focus[1]} % · tamaño 150 % · toque o arrastre la miniatura`, pos: `${focus[0]}% ${focus[1]}%`, tr: 'scale(1.5)' },
        'the thumbnail is framed as the TV will frame it');
      /* centre top: a presentation of the iced coffees every 6 s */
      await pg.fill('#edZ-1-seconds', '6');
      await add(1, 'iced', icedLatte);
      await add(1, 'iced', icedAm);
      /* centre bottom: a latte without name or price, the croissant's photo as the fallback */
      await pg.uncheck('#edZ-2-labels');
      await add(2, 'latte', latte);
      await pg.click(zone(2) + ' [data-act=fb-producto]');
      await pg.fill('#edZ-2-search', 'butter');
      await pg.click(`#edZ-2-picker .pick[data-item="${croissant}"]`);
      assert.match(await pg.getAttribute(zone(2) + ' .fb .ph img', 'src'), /croissant\.png$/);
      /* right: an uploaded photo and a sandwich, then the sandwich first */
      const before = photos();
      await pg.click(zone(3) + ' [data-act=subir]');
      await pg.setInputFiles('#photoFile', { name: 'terraza.png', mimeType: 'image/png', buffer: PHOTO });
      await until(async () => /Lista: 1 × 1 px/.test(await text(pg, '#edZerr-3')), 8000, 'the photo made ready');
      await add(3, 'ham & cheese', ham);
      assert.deepStrictEqual(await pg.$$eval(zone(3) + ' .entry .einfo b', (a) => a.map((x) => x.textContent)), ['1. Foto (nueva)', '2. Ham & Cheese · ₡4 000 en el menú']);
      await pg.click(zone(3) + ' .entry[data-entry="1"] [data-act=arriba]');
      assert.deepStrictEqual(await pg.$$eval(zone(3) + ' .entry .einfo b', (a) => a.map((x) => x.textContent)), ['1. Ham & Cheese · ₡4 000 en el menú', '2. Foto (nueva)']);
      assert.deepStrictEqual(photos(), before, 'nothing uploaded before Guardar');
      await pg.fill('#ed-kicker_es', 'Desayuno');
      await pg.fill('#ed-kicker_en', 'Breakfast');
      await pg.fill('#edDwell', '90');
      await save(pg, '#edSave');
      const id = one(`select id from screen_slides`);
      const saved = slideJson(id);
      const url = saved.zones[3].entries[1].photo;
      const m = /\/storage\/v1\/object\/public\/menu-photos\/(pantallas\/[0-9a-f-]{36}\.jpg)$/.exec(url || '');
      assert.ok(m, 'the uploaded photo\'s public address: ' + url);
      assert.deepStrictEqual(photos().filter((k) => !before.includes(k)), ['menu-photos/' + m[1]], 'one new file in Storage, the one the zone uses');
      assert.deepStrictEqual(saved, { kind: 'composicion', template: '4-centro', dwell: 90, kicker: 'Desayuno', kicker_en: 'Breakfast', title: null, zones: [
        { mode: 'fija', seconds: 8, labels: true, fallback: null, entries: [{ item: croissant, photo: null, focus: focus, zoom: 150 }] },
        { mode: 'auto', seconds: 6, labels: true, fallback: null, entries: [{ item: icedLatte, photo: null, focus: [50, 50], zoom: 100 }, { item: icedAm, photo: null, focus: [50, 50], zoom: 100 }] },
        { mode: 'auto', seconds: 8, labels: false, fallback: 'https://fotos.test/croissant.png', entries: [{ item: latte, photo: null, focus: [50, 50], zoom: 100 }] },
        { mode: 'auto', seconds: 8, labels: true, fallback: null, entries: [{ item: ham, photo: null, focus: [50, 50], zoom: 100 }, { item: null, photo: url, focus: [50, 50], zoom: 100 }] }
      ] }, 'the zones exactly as written: ids, photos and framing, never a name or a price');
      assert.strictEqual(one(`select status || ' ' || created_by from screen_slides where id = '${id}'`), 'activa Dueño (owner)');
      const row = `article.slide[data-slide="${id}"]`;
      assert.match(await inner(pg, row + ' .t'), /^Desayuno · Composición · plantilla Centro en dos · Izquierda: foto fija · Butter Croissant · Centro arriba: presentación cada 6 s · 2 entradas · Centro abajo: presentación cada 8 s · Latte · sin nombres ni precios · NADA QUE MOSTRAR: suba fotos o active nombres y precios · Derecha: presentación cada 8 s · 2 entradas · se queda 90 s$/,
        'the zone with nothing to show (its fallback photo stands in) says so');
      assert.match(await text(pg, row + ' [data-when]'), /En pantalla ahora/);
      const d = await anonDatos(pg, 'promos-1');
      assert.deepStrictEqual([d.slides.length, d.slides[0].kind, d.slides[0].usable, d.slides[0].zones.map((z) => z.showable), d.slides[0].zones[0].entries[0].item.price_crc],
        [1, 'composicion', true, [true, true, false, true], 1500], 'what the TV reads: three zones have something to show (the centre-bottom latte has no photo and no labels: its fallback photo shows), the price live');
      /* read back into the editor and saved again without a change: the same zones, in the same order; the photo stays */
      await pg.click(row + ' [data-act=editar]');
      await pg.waitForSelector('#slideForm #edZones .zone');
      assert.strictEqual(await text(pg, '#slideForm h2'), 'Editar la composición');
      assert.strictEqual(await pg.getAttribute('#edTemplates .tpl[data-template="4-centro"]', 'aria-pressed'), 'true');
      assert.strictEqual(await pg.isChecked('#edZ-0-mode-fija'), true);
      assert.strictEqual(await pg.inputValue('#edZ-1-seconds'), '6');
      assert.strictEqual(await pg.isChecked('#edZ-2-labels'), false);
      assert.strictEqual(await pg.inputValue('#edDwell'), '90');
      assert.deepStrictEqual(await encuadre(pg, zone(0) + ' .entry[data-entry="0"]'), { zoom: '150', focus: `Enfoque ${focus[0]} %, ${focus[1]} % · tamaño 150 % · toque o arrastre la miniatura`, pos: `${focus[0]}% ${focus[1]}%`, tr: 'scale(1.5)' });
      assert.deepStrictEqual(await pg.$$eval(zone(3) + ' .entry .einfo b', (a) => a.map((x) => x.textContent)), ['1. Ham & Cheese · ₡4 000 en el menú', '2. Foto']);
      assert.match(await pg.getAttribute(zone(3) + ' .entry[data-entry="1"] .frame img', 'src'), /menu-photos\/pantallas\//);
      await pg.fill('#ed-kicker_es', 'Desayuno en el jardín');
      await save(pg, '#edSave');
      const again = slideJson(id);
      assert.deepStrictEqual(again, Object.assign({}, saved, { kicker: 'Desayuno en el jardín' }), 'the zones exactly as before');
      assert.deepStrictEqual(photos().filter((k) => !before.includes(k)), ['menu-photos/' + m[1]], 'the photo stays, nothing else uploaded');
      assert.strictEqual(one(`select string_agg(action, ',' order by id) from screen_changes where target_id = '${id}'`), 'crear,cambiar');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'v2 · a composition refused by the server is said next to the zone and the entry: an Extras & Combos product sent past the page, too many entries; a kicker with a price blocked while typing and refused past the page; the page\'s own checks first',
    run: async ({ browser }) => {
      const pg = await asOwnerPin(browser);
      await tab(pg, 'slides');
      const latte = itemId('Latte'), shot = itemId('Flavor shot');
      await pg.click('#newCompo');
      await pg.waitForSelector('#slideForm #edZones .zone');
      await pg.click('#edTemplates .tpl[data-template="2-lado"]');
      await pg.click('#edZ-0-add');
      await pg.fill('#edZ-0-search', 'flavor');
      await until(async () => /Nada en el menú con esa búsqueda/.test(await text(pg, '#edZ-0-picker')), 3000, 'Extras & Combos is never offered');
      await pg.fill('#edZ-0-search', 'latte');
      await pg.click(`#edZ-0-picker .pick[data-item="${latte}"]`);
      /* the page's checks: an empty zone, a fixed zone with two entries */
      await pg.click('#edSave');
      await until(async () => /Derecha: agregue al menos un producto o una foto\./.test(await text(pg, '#edZerr-1')), 4000, 'the empty zone, at the zone');
      assert.ok(!pg.rpc.includes('diapositiva_guardar'), 'nothing sent');
      await pg.click('#edZ-1-add');
      await pg.fill('#edZ-1-search', 'latte');
      await pg.click(`#edZ-1-picker .pick[data-item="${latte}"]`);
      await pg.click(`#edZ-1-picker .pick[data-item="${latte}"]`);
      await pg.click('#edZ-1-mode-fija');
      await pg.click('#edSave');
      await until(async () => /Derecha: una foto fija lleva una sola entrada/.test(await text(pg, '#edZerr-1')), 4000, 'two entries in a fixed zone');
      assert.ok(!pg.rpc.includes('diapositiva_guardar'), 'still nothing sent');
      assert.strictEqual(await text(pg, '#edZerr-0'), '', 'the other zone is clean');
      /* past the page: the same fixed zone with two entries, refused by the server at the zone */
      await pg.evaluate(() => { window.PANTALLAS_TEST = { sinRevisar: true }; document.getElementById('slideForm').requestSubmit(); });
      await until(async () => /Derecha: una foto fija lleva exactamente una entrada; una presentación, de 1 a 12\./.test(await text(pg, '#edZerr-1')), 8000, 'the server\'s invalid/zones.1.entries');
      assert.match(await pg.getAttribute('#edZones .zone[data-zone="1"]', 'class'), /bad/);
      await pg.click('#edZ-1-mode-auto');
      await pg.click('#edZones .zone[data-zone="1"] .entry[data-entry="1"] [data-act=quitar]');
      /* past the page: an Extras & Combos product in the second zone's entry */
      await pg.evaluate((shot) => {
        window.PANTALLAS_TEST = { sinRevisar: true, antesDeEnviar: (p) => { p.zones[1].entries[0].item = shot; return p; } };
        document.getElementById('slideForm').requestSubmit();
      }, shot);
      await until(async () => /Derecha, entrada 1: ese producto es de Extras & Combos: no se anuncia\./.test(await text(pg, '#edZerr-1')), 8000, 'the server\'s text_combo_descuento, at the entry');
      assert.strictEqual(await text(pg, '#edErr'), 'Derecha, entrada 1: ese producto es de Extras & Combos: no se anuncia.');
      assert.match(await pg.getAttribute('#edZones .zone[data-zone="1"] .entry[data-entry="0"]', 'class'), /bad/, 'marked at the entry');
      assert.strictEqual(await text(pg, '#edZerr-0'), '', 'the other zone is clean');
      /* past the page: thirteen entries in the first zone */
      await pg.evaluate(() => {
        window.PANTALLAS_TEST = { sinRevisar: true, antesDeEnviar: (p) => { p.zones[0].mode = 'auto'; p.zones[0].entries = Array(13).fill(p.zones[0].entries[0]); return p; } };
        document.getElementById('slideForm').requestSubmit();
      });
      await until(async () => /Izquierda: a lo sumo 12 entradas\./.test(await text(pg, '#edZerr-0')), 8000, 'the server\'s too_many/zones.0.entries');
      assert.strictEqual(await text(pg, '#edZerr-1'), '', 'the earlier refusal is cleared');
      /* a kicker with a price: blocked while typing; past the page the server refuses it before looking at the zones */
      await pg.evaluate(() => { window.PANTALLAS_TEST = { sinRevisar: true }; });
      await pg.fill('#ed-kicker_es', 'Latte a ₡1500');
      assert.match(await text(pg, '#err-kicker_es'), /Sin precios/);
      assert.strictEqual(await pg.locator('#edSave').isDisabled(), true);
      await pg.evaluate(() => document.getElementById('slideForm').requestSubmit());
      await until(async () => /Sin precios en el texto[\s\S]*\(la línea de arriba \(español\)\)/.test(await text(pg, '#edErr')), 8000, 'the server\'s text_precio');
      assert.strictEqual(pg.rpc.filter((f) => f === 'diapositiva_guardar').length, 4, 'four reached the server');
      assert.strictEqual(slides(), 0, 'nothing kept');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'v2 · «Vista previa en la TV»: the real pantalla-promos page in preview mode, framed, draws the composition as it stands (nothing saved, nothing read) and follows every change; a new photo goes up for it and comes down with Cancelar',
    run: async ({ browser }) => {
      one(`update menu_items set photo_url = 'https://fotos.test/croissant.png' where name = 'Butter Croissant'`);
      const pg = await asOwnerPin(browser, { viewport: { width: 1280, height: 900 }, init: () => { window.PANTALLA_TEST = { zona: 100, fundido: 100, revisar: 150 }; } });
      await tab(pg, 'slides');
      const croissant = itemId('Butter Croissant'), latte = itemId('Latte'), ham = itemId('Ham & Cheese');
      await pg.click('#newCompo');
      await pg.waitForSelector('#slideForm #edZones .zone');
      await pg.click('#edTemplates .tpl[data-template="3-grande-izq"]');
      const add = async (i, q, item) => {
        if ((await pg.getAttribute(`#edZ-${i}-add`, 'aria-pressed')) !== 'true') await pg.click(`#edZ-${i}-add`);
        await pg.fill(`#edZ-${i}-search`, q);
        await pg.click(`#edZ-${i}-picker .pick[data-item="${item}"]`);
      };
      await add(0, 'butter', croissant);
      await pg.click('#edZ-1-mode-fija');
      await add(1, 'latte', latte);
      await add(2, 'ham', ham);
      await pg.fill('#ed-kicker_es', 'Desayuno');
      assert.deepStrictEqual(await pg.$$eval('#edPvTv option', (o) => o.map((x) => x.value)), ['promos-1']);
      await pg.click('#edPreviewBtn');
      await pg.waitForSelector('#edPreview .pv iframe');
      const pvSrc = await pg.getAttribute('#edPreview .pv iframe', 'src');
      assert.ok(/^pantalla-promos\?tv=promos-1&preview=1(&|$)/.test(pvSrc) && /&pulgadas=\d+/.test(pvSrc) && /&distancia=[\d.]+/.test(pvSrc) && /&escala=\d+/.test(pvSrc) && /&giro=(no|derecha|izquierda)/.test(pvSrc) && /&look=(auto|dia|noche)/.test(pvSrc),
        'the real page, in preview mode, with that TV\'s size, distance, scale, turn and look in the address: ' + pvSrc);
      assert.strictEqual(await text(pg, '#edPreviewBtn'), 'Cerrar la vista previa');
      const frame = await until(() => pg.frames().find((f) => f !== pg.mainFrame() && /preview=1/.test(f.url())), 8000, 'the frame');
      await until(() => frame.evaluate(() => !!window.PANTALLA_B && PANTALLA_B.info().actual === 'previa'), 12000, 'the posted composition');
      await until(async () => { const z = await zonasEn(frame); return z && z.zonas.length === 3 && z.zonas.every((x) => x.estado === 'entrada'); }, 8000, 'its zones up');
      const z = await zonasEn(frame);
      /* the TV writes the names in Spanish first (the site's dictionary), as it does for a product slide; the kicker
         («Desayuno») is only the composition's name in the panel: nothing over the zones, as on the TV (2026-11-03) */
      assert.deepStrictEqual([z.template, z.kick, z.sup, z.zonas.map((x) => x.tit), z.zonas.map((x) => x.modo)],
        ['3-grande-izq', null, null, ['Croissant de mantequilla', 'Latte', 'Jamón y queso'], ['auto', 'fija', 'auto']], JSON.stringify(z));
      assert.ok(/^₡2\s?200$/.test(z.zonas[1].precio), 'the live price the panel read from the menu: ' + z.zonas[1].precio);
      assert.strictEqual(z.zonas[0].src, 'https://fotos.test/croissant.png', 'the menu\'s photo');
      const i = await frame.evaluate(() => PANTALLA_B.info());
      assert.deepStrictEqual([i.preview, i.razon, i.intentos, i.buenas, i.estado], [true, 'vista-previa', 0, 0, 'al-dia'], 'the preview reads nothing: ' + JSON.stringify(i));
      assert.ok(!pg.rpc.includes('pantalla_datos') && !pg.rpc.includes('diapositiva_guardar'), 'nor the panel: ' + pg.rpc.join(','));
      /* every change follows: names and prices off in the latte's zone; the zones swapped */
      await pg.uncheck('#edZ-1-labels');
      await until(async () => { const j = await zonasEn(frame); return j && j.zonas[1].tit === null && j.zonas[1].precio === null; }, 6000, 'the change reaches the preview');
      await pg.click('#edZones .zone[data-zone="1"] [data-act=swap-next]');
      await until(async () => { const j = await zonasEn(frame); return j && j.zonas.map((x) => x.tit).join('|') === 'Croissant de mantequilla|Jamón y queso|'; }, 6000, 'the zones swapped');
      assert.deepStrictEqual(await pg.$$eval('#edZones .zone .entry .einfo b', (a) => a.map((x) => x.textContent)), ['1. Butter Croissant · ₡1 500 en el menú', '1. Ham & Cheese · ₡4 000 en el menú', '1. Latte · ₡2 200 en el menú']);
      /* a new photo: it goes up when the preview needs it, shows there, and comes down when the owner gives up */
      const before = photos();
      await pg.click('#edZones .zone[data-zone="0"] [data-act=subir]');
      await pg.setInputFiles('#photoFile', { name: 'jardin.png', mimeType: 'image/png', buffer: PHOTO });
      await until(() => photos().length === before.length + 1, 8000, 'uploaded for the preview');
      const key = photos().filter((k) => !before.includes(k))[0];
      await until(async () => { const j = await zonasEn(frame); return j && j.zonas[0].src && j.zonas[0].src.endsWith('/' + key); }, 8000, 'the new photo takes its turn in the preview');
      assert.strictEqual(slides(), 0, 'nothing saved');
      /* Cancelar takes the photo away (the test Storage keeps no DELETE: the request itself, naming the file, is the proof) */
      await pg.click('#edCancel');
      await until(() => pg.deletes.some((d) => d.includes(key.replace(/^menu-photos\//, ''))), 8000, 'the photo taken away: no orphan file');
      assert.strictEqual(await pg.locator('#slideForm, #edPreview iframe').count(), 0);
      assert.strictEqual(slides(), 0);
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'v2 · «Programación sugerida»: four paused compositions for the day from the menu\'s own categories (breakfast in 4-centro, lunch, afternoon, dinner), told to the owner; a second click creates nothing',
    run: async ({ browser }) => {
      const pg = await asOwnerPin(browser);
      await tab(pg, 'slides');
      await pg.click('#sugerir');
      await until(async () => /Se crearon en pausa: Desayuno \(06:00–10:00\), Almuerzo \(10:00–13:00\), Tarde \(13:00–17:00\), Cena \(17:00–19:00\)\. Revíselas/.test(await text(pg, '#sugerirMsg')), 20000, 'the four, told');
      assert.match(await text(pg, '#sugerirMsg'), /ninguna sale sola\. Van sin nombres ni precios; actívelos por ventana en el editor\. Un producto sin foto no se muestra mientras su ventana vaya sin nombres: súbale foto en el Gestor de menú o elija otra en el editor\.$/,
        'the owner is told the four go without names and prices, and that a product without a photo does not show then');
      const rows = JSON.parse(one(`select json_agg(json_build_object('t', kicker_es, 'en', kicker_en, 'template', template, 'status', status, 'from', from_time, 'to', to_time, 'days', days, 'sort', sort,
                                       'screens', screen_ids, 'dias', round(extract(epoch from (ends_at - starts_at)) / 86400), 'zones', zones) order by sort)::text from screen_slides`));
      assert.deepStrictEqual(rows.map((r) => [r.t, r.en, r.template, r.status, r.from, r.to, r.days, r.sort, r.screens, r.dias]), [
        ['Desayuno', 'Breakfast', '4-centro', 'pausada', '06:00:00', '10:00:00', null, 10, null, 365],
        ['Almuerzo', 'Lunch', '3-grande-izq', 'pausada', '10:00:00', '13:00:00', null, 20, null, 365],
        ['Tarde', 'Afternoon', '2-lado', 'pausada', '13:00:00', '17:00:00', null, 30, null, 365],
        ['Cena', 'Dinner', '1', 'pausada', '17:00:00', '19:00:00', null, 40, null, 365]
      ], 'four, paused, every day, every TV, a year');
      const names = (r) => r.zones.map((z) => z.entries.map((e) => one(`select name from menu_items where id = '${e.item}'`)));
      const reposteria = ['Butter Croissant', 'Chocolate Croissant', 'Ham & Cheese Croissant', 'Banana Bread', 'Carrot Cake', 'Chicken Empanada', 'Beef Empanada'];
      const sandwiches = ['Ham & Cheese', 'Mano de Piedra', 'Chicken Pesto', 'Monteverde'];
      const frios = ['Iced Latte', 'Iced Americano', 'Iced Mocha'];
      const calientes = ['Latte', 'Café con Leche', 'Espresso', 'Americano', 'Macchiato', 'Cappuccino', 'Flat White', 'Mocha', 'Cloud Forest Latte'];
      const batidos = ['Golden Passion Bloom', 'Berry Violet Blossom', 'White Plumeria Cream', 'Sunflower Citrus Bloom', 'Green Jasmine Mint', 'Coral Rose Splash', 'Pink Dahlia Delight', 'Emerald Orchid', 'Lemon Rose Blossom', 'Fresh Water Lily', 'Golden Magnolia'];
      assert.deepStrictEqual(names(rows[0]), [reposteria, frios, calientes, sandwiches], 'breakfast: left pastries (croissants first), centre top iced coffees (iced latte first), centre bottom hot coffees (latte and café con leche first), right sandwiches');
      assert.deepStrictEqual(names(rows[1]), [sandwiches, batidos, frios.concat(['Costa Rican Hot Chocolate', 'Tea', 'Sweet Cane Drink'])], 'lunch: the iced coffees first among the cold drinks');
      assert.deepStrictEqual(names(rows[2]), [calientes, reposteria], 'afternoon');
      assert.deepStrictEqual(names(rows[3]), [sandwiches], 'dinner');
      const secs = { Desayuno: [14, 16, 18, 20], Almuerzo: [12, 15, 18], Tarde: [12, 15], Cena: [10] };
      rows.forEach((r) => r.zones.forEach((z, i) => {
        assert.deepStrictEqual([z.mode, z.seconds, z.labels, z.fallback], ['auto', secs[r.t][i], false, null],
          r.t + ', zone ' + (i + 1) + ': presentations at seconds of their own (never two windows together), without names and prices (the owner turns them on per zone), the brand as the fallback');
        z.entries.forEach((e) => assert.deepStrictEqual([e.photo, e.focus, e.zoom, Object.keys(e).sort()], [null, [50, 50], 100, ['focus', 'item', 'photo', 'zoom']], 'ids and framing only'));
      }));
      assert.strictEqual(one(`select count(*) || ' ' || string_agg(distinct action || ':' || by_name, ',') from screen_changes`), '4 crear:Dueño (owner)');
      assert.deepStrictEqual((await anonDatos(pg, 'promos-1')).slides, [], 'paused: nothing goes on the TV by itself');
      assert.strictEqual(await pg.locator('#slideList article.slide[data-kind=composicion]').count(), 4);
      /* the seed's products have no photo: without names, no window has anything to show, and the list says so */
      const nada = ' · sin nombres ni precios · NADA QUE MOSTRAR: suba fotos o active nombres y precios';
      assert.strictEqual(await inner(pg, '#slideList article.slide[data-kind=composicion] .t'), 'Desayuno · Composición · plantilla Centro en dos · Izquierda: presentación cada 14 s · 7 entradas' + nada +
        ' · Centro arriba: presentación cada 16 s · 3 entradas' + nada + ' · Centro abajo: presentación cada 18 s · 9 entradas' + nada + ' · Derecha: presentación cada 20 s · 4 entradas' + nada + ' · se queda 60 s');
      assert.match(await text(pg, '#slideList article.slide[data-kind=composicion] [data-status]'), /Pausada/);
      await pg.click('#sugerir');
      await until(async () => /^No se creó nada\. Ya existían: Desayuno, Almuerzo, Tarde, Cena\.$/.test(await text(pg, '#sugerirMsg')), 8000, 'nothing twice');
      assert.strictEqual(slides(), 4);
      assert.strictEqual(one(`select count(*) from screen_changes`), '4');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'v2 · «Hoy en pantalla» lists a composition with its zones; one whose zones have nothing to show is not on, and the list says why',
    run: async ({ browser }) => {
      const on = compo({ template: '2-lado', kicker_es: 'Mañana', ends: "now() + interval '20 days'",
        zones: [{ mode: 'fija', entries: [{ item: 'Latte' }] }, { mode: 'auto', seconds: 5, entries: [{ item: 'Banana Bread' }, 'https://fotos.test/jardin.png'] }] });
      one(`update menu_items set available = false where name = 'Espresso'`);
      const off = compo({ template: '1', kicker_es: 'Nada que mostrar', zones: [{ entries: [{ item: 'Espresso' }] }] });
      const pg = await asOwnerPin(browser);
      await tab(pg, 'today');
      const card = 'article.today[data-today="promos-1"]';
      await pg.waitForSelector(card);
      assert.deepStrictEqual(await pg.$$eval(card + ' ol[data-list=ahora] li', (a) => a.map((x) => x.querySelector('b').textContent)), ['Mañana'], 'only the usable one');
      assert.match(await inner(pg, `${card} li[data-slide="${on}"]`), /^Mañana Composición · Dos mitades · todo el día Izquierda: foto fija · Latte · Derecha: presentación cada 5 s · 2 entradas$/);
      assert.strictEqual(await pg.locator(`${card} li[data-slide="${off}"]`).count(), 0);
      await tab(pg, 'slides');
      assert.match(await text(pg, `article.slide[data-slide="${off}"] [data-when]`), /No sale: ninguna zona tiene qué mostrar/);
      assert.match(await text(pg, `article.slide[data-slide="${on}"] [data-when]`), /En pantalla ahora/);
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'without migration 0036 the page says which one is missing',
    run: async ({ browser }) => {
      one(`drop function public.pantallas_estado(); notify pgrst, 'reload schema'`);
      await until(async () => (await fetch(PGRST + '/rpc/pantallas_estado', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' })).status === 404, 10000, 'PostgREST without it');
      const pg = await open(browser);
      await unlockAs(pg, 'dueno');
      await pg.waitForSelector('#noView:not([hidden])', { timeout: 10000 });
      assert.strictEqual(await text(pg, '#noMsg'), 'Falta aplicar la migración 0036 (docs/ACTIVACION-PANTALLAS.md).');
      assert.strictEqual(await pg.locator('#appView').isHidden(), true);
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'v2 · the menu TV\'s products: three ticked in the card (two coffees and a pastry), saved, logged and read by the TV as item_ids; the card reopened shows them ticked and «3 elegidos»; none ticked = null (all); a product of Extras & Combos is never offered',
    run: async ({ browser }) => {
      const pg = await asOwnerPin(browser);
      const card = 'article.tv[data-tv="menu-1"]', sum = card + ' details.prods summary';
      assert.strictEqual(await text(pg, sum), 'Productos que muestra: todos', 'nothing chosen: every product of its categories');
      assert.strictEqual(await pg.locator('article.tv[data-tv="promos-1"] details.prods').count(), 0, 'products only on the menu TV');
      const offered = await pg.$$eval(card + ' input[data-item]', (a) => a.map((x) => x.value));
      const extras = one(`select coalesce(string_agg(id::text, ','), '') from menu_items where category_id = (select id from menu_categories where name = 'Extras & Combos')`).split(',').filter(Boolean);
      assert.ok(extras.length > 0, 'the seed has Extras & Combos products');
      assert.ok(offered.length > 10 && !offered.some((id) => extras.includes(id)), 'the menu\'s products, never Extras & Combos');
      assert.strictEqual(offered.length, Number(one(`select count(*) from menu_items i join menu_categories c on c.id = i.category_id where c.name <> 'Extras & Combos' and i.price_crc > 0`)), 'every product with a price, once');
      assert.strictEqual(new Set(offered).size, offered.length, 'no product twice');
      assert.deepStrictEqual(await pg.$$eval(card + ' details.prods .pcat', (a) => a.map((x) => x.textContent)),
        JSON.parse(one(`select json_agg(name order by sort, name)::text from menu_categories where name <> 'Extras & Combos' and id in (select category_id from menu_items where price_crc > 0)`)),
        'grouped under the categories in the Menu Manager\'s order');
      const ids = ['Latte', 'Cappuccino', 'Banana Bread'].map(itemId);
      await pg.click(sum);
      for (const id of ids) await pg.check(`${card} input[data-item][value="${id}"]`);
      assert.strictEqual(await text(pg, sum), 'Productos que muestra: 3 elegidos', 'counted as they are ticked');
      assert.match(await text(pg, card + ' .dirty'), /Cambios sin guardar/);
      const order = await pg.$$eval(card + ' input[data-item]:checked', (a) => a.map((x) => x.value));
      assert.deepStrictEqual(order.slice().sort(), ids.slice().sort(), 'the three, in the card\'s order (the coffees before the pastry)');
      await save(pg, card + ' button[type=submit]');
      assert.strictEqual(pg.rpc.filter((f) => f === 'pantalla_guardar').length, 1, 'sent once, accepted');
      assert.strictEqual(one(`select item_ids::text from screens where id = 'menu-1'`), '{' + order.join(',') + '}', 'kept in the order given');
      const d = await anonDatos(pg, 'menu-1');
      assert.deepStrictEqual(d.tv.item_ids, order, 'what the TV reads');
      assert.deepStrictEqual(await pg.$$eval(card + ' input[data-item]:checked', (a) => a.map((x) => x.value)), order, 'the card shows what the server keeps');
      await tab(pg, 'log');
      const first = pg.locator('#logList article.chg').first();
      assert.strictEqual(await first.getAttribute('data-target'), 'tv:menu-1');
      await first.locator('summary').click();
      const nameOf = (id) => one(`select case when nullif(btrim(coalesce(to_jsonb(i) ->> 'name_es', '')), '') is not null and (to_jsonb(i) ->> 'name_es') <> i.name
                                               then (to_jsonb(i) ->> 'name_es') || ' · ' || i.name else i.name end from menu_items i where i.id = '${id}'`);
      assert.strictEqual(await first.locator('tr[data-k="item_ids"] td.k').innerText(), 'Productos');
      assert.strictEqual(await first.locator('tr[data-k="item_ids"] td.was').innerText(), 'todos');
      assert.strictEqual(await first.locator('tr[data-k="item_ids"] td.now').innerText(), order.map(nameOf).join(', '), 'the products by name');
      assert.strictEqual(one(`select jsonb_array_length(after -> 'item_ids') from screen_changes where target_id = 'menu-1' and action = 'cambiar' order by id desc limit 1`), '3', 'the log row carries item_ids');
      /* the panel opened again (it comes back on the log tab it was left on): the three ticked and counted; all unticked = every product (null) */
      await pg.reload({ waitUntil: 'domcontentloaded' });
      await pg.waitForSelector('#appView:not([hidden]) ' + card, { state: 'attached', timeout: 12000 });
      await tab(pg, 'tvs');
      assert.strictEqual(await text(pg, sum), 'Productos que muestra: 3 elegidos');
      assert.deepStrictEqual(await pg.$$eval(card + ' input[data-item]:checked', (a) => a.map((x) => x.value)), order);
      await pg.click(sum);
      for (const id of ids) await pg.uncheck(`${card} input[data-item][value="${id}"]`);
      assert.strictEqual(await text(pg, sum), 'Productos que muestra: todos');
      await save(pg, card + ' button[type=submit]');
      assert.strictEqual(one(`select item_ids is null from screens where id = 'menu-1'`), 't', 'none ticked = null');
      assert.strictEqual((await anonDatos(pg, 'menu-1')).tv.item_ids, null, 'the TV shows every product again');
      assert.strictEqual(await text(pg, sum), 'Productos que muestra: todos');
      assert.strictEqual(await pg.locator(card + ' input[data-item]:checked').count(), 0);
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'v2 · «Programación sugerida» with a group without products: the template is reduced and takes the smaller template\'s seconds per window (3 zones 12/15/18 s, 1 zone 10 s)',
    run: async ({ browser }) => {
      one(`update menu_items set price_crc = 0 where category_id in (select id from menu_categories where name in ('Pastries & Cake', 'Savory'))`);
      const pg = await asOwnerPin(browser);
      await tab(pg, 'slides');
      await pg.click('#sugerir');
      await until(async () => /^Se crearon en pausa: Desayuno \(06:00–10:00, con 3 zonas: faltan productos de alguna categoría\), Almuerzo \(10:00–13:00\), Tarde \(13:00–17:00, con 1 zona: faltan productos de alguna categoría\), Cena \(17:00–19:00\)\./.test(await text(pg, '#sugerirMsg')),
        20000, 'the four, two of them reduced');
      const rows = JSON.parse(one(`select json_agg(json_build_object('t', kicker_es, 'template', template,
                                     'secs', (select json_agg((z ->> 'seconds')::int order by o) from jsonb_array_elements(zones) with ordinality x(z, o))) order by sort)::text from screen_slides`));
      assert.deepStrictEqual(rows.map((r) => [r.t, r.template, r.secs]), [
        ['Desayuno', '3-grande-izq', [12, 15, 18]], ['Almuerzo', '3-grande-izq', [12, 15, 18]], ['Tarde', '1', [10]], ['Cena', '1', [10]]
      ], 'breakfast without pastries in three windows and the afternoon in one, each with the seconds of the template it got');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'v2 · a menu TV\'s preview says under the frame what the real page measured with the saved row (pages, columns, letter: its own PANTALLA.info()), «Midiendo…» before; the whole menu on a 32" at 3 m, normal density and English below, says NO CABE; a promotions TV has no such line',
    run: async ({ browser }) => {
      const pg = await asOwnerPin(browser, { viewport: { width: 1280, height: 900 } });
      const card = 'article.tv[data-tv="menu-1"]', line = card + ' [data-pvinfo]';
      const first = await pg.evaluate((c) => { document.querySelector(c + ' [data-preview]').click(); const l = document.querySelector(c + ' [data-pvinfo]'); return l ? l.textContent : null; }, card);
      assert.strictEqual(first, 'Midiendo…', 'nothing said before the page has drawn its board');
      const frameOf = () => until(() => pg.frames().find((f) => /pantalla-menu\?tv=menu-1/.test(f.url())), 8000, 'the frame');
      let frame = await frameOf();
      const cm = (n) => n.toFixed(2).replace('.', ',');
      /* the line and the frame's own measure, read until they agree (a font that arrives lays the board out again) */
      const seen = await until(async () => {
        const t = await text(pg, line), i = await frame.evaluate(() => window.PANTALLA ? PANTALLA.info() : null).catch(() => null);
        if (!i || !(i.paginas > 1) || i.fuente !== 'base') return null;
        const want = 'En la TV: ' + i.paginas + ' páginas de ' + Math.round(i.paginaMs / 1000) + ' s · ' + i.columnas + ' columnas · letra ' + cm(i.capCm) + ' cm (mínimo ' + cm(i.minCm) + ')';
        return t === want ? { t, i } : null;
      }, 15000, 'the line, as the frame measured it');
      assert.ok(seen.i.cabe === true && seen.i.capCm >= seen.i.minCm, 'the seed\'s 55" at 3 m fits: ' + JSON.stringify([seen.i.paginas, seen.i.capCm, seen.i.cabe]));
      assert.match(seen.t, /^En la TV: \d+ páginas de 28 s · \d columnas · letra \d,\d\d cm \(mínimo 2,40\)$/, 'the pages and the letter, with the Spanish decimal comma: ' + seen.t);
      assert.doesNotMatch(await pg.getAttribute(line, 'class'), /\bbad\b/);
      await pg.click('article.tv[data-tv="promos-1"] [data-preview]');
      await pg.waitForSelector('article.tv[data-tv="promos-1"] .pv iframe');
      assert.strictEqual(await pg.locator('article.tv[data-tv="promos-1"] [data-pvinfo]').count(), 0, 'only a menu TV has pages to count');
      /* 32" at 3 m with the whole menu, normal density and English below: the preview reopened reads the row again */
      one(`update screens set density = 'normal', english = 'debajo', inches = 32, distance_m = 3 where id = 'menu-1'`);
      await pg.click(card + ' [data-preview]');
      assert.strictEqual(await pg.locator(line).count(), 0, 'closed: no line');
      await pg.click(card + ' [data-preview]');
      await until(async () => (await text(pg, line)) === 'NO CABE a la letra mínima: use densidad compacta y sin inglés, o menos productos', 15000, 'NO CABE');
      frame = await frameOf();
      const j = await frame.evaluate(() => PANTALLA.info());
      assert.deepStrictEqual([j.cabe, Number(j.ajustes.pulgadas), Number(j.ajustes.distancia), j.ajustes.densidad, j.ajustes.ingles], [false, 32, 3, 'normal', 'debajo'], 'as the frame measured it');
      assert.match(await pg.getAttribute(line, 'class'), /\bbad\b/, 'said in red');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'v2 · a menu TV preview\'s line reads every 2 s only while that preview is open: «Cerrar la vista previa» stops it at once, a TV save that draws the open preview again leaves exactly one reading, «Cerrar sesión» none',
    run: async ({ browser }) => {
      /* the panel's own 2 s timers (not the frames'): which are alive, and how many times they ran */
      const pg = await open(browser, { login: 'owner', aal: 'aal2', viewport: { width: 1280, height: 900 }, init: () => {
        if (window.top !== window) return;
        const set = window.setInterval, unset = window.clearInterval, pv = { live: new Set(), runs: 0 };
        window.__pv = pv;
        window.setInterval = function (fn, ms) {
          if (ms !== 2000 || typeof fn !== 'function') return set.apply(window, arguments);
          const id = set.call(window, function () { pv.runs++; return fn.apply(this, arguments); }, ms);
          pv.live.add(id);
          return id;
        };
        window.clearInterval = function (id) { pv.live.delete(id); return unset.call(window, id); };
      } });
      await pg.waitForSelector('#appView:not([hidden]) article.tv', { timeout: 12000 });
      const card = 'article.tv[data-tv="menu-1"]', line = card + ' [data-pvinfo]';
      const pv = () => pg.evaluate(() => ({ live: window.__pv.live.size, runs: window.__pv.runs }));
      const measured = () => until(async () => /^(En la TV: |NO CABE)/.test((await text(pg, line)) || ''), 15000, 'the line, as the frame measured it');
      /* how many times the readings ran in a window of ms (at least 2.5 s: one 2 s tick, even on a loaded machine) */
      const ran = async (ms) => { const a = await pv(); await pg.waitForTimeout(ms); return (await pv()).runs - a.runs; };
      assert.deepStrictEqual(await pv(), { live: 0, runs: 0 }, 'no preview open: no reading');
      await pg.click(card + ' [data-preview]');
      await measured();
      assert.strictEqual((await pv()).live, 1, 'one reading for the open preview');
      assert.ok((await ran(4500)) >= 1, 'it reads while the preview is open');
      /* «Cerrar la vista previa»: stopped there and then, and it never runs again */
      await pg.click(card + ' [data-preview]');
      assert.strictEqual((await pv()).live, 0, 'stopped by «Cerrar la vista previa»');
      assert.strictEqual(await ran(2600), 0, 'no reading after the close');
      /* a TV save with the preview open draws the card again: the old reading goes, one starts for the new frame */
      await pg.click(card + ' [data-preview]');
      await measured();
      const old = await pg.$(line);
      await pg.fill('#tv-menu-1-page_seconds', '30');
      await save(pg, card + ' button[type=submit]');
      assert.strictEqual(await old.evaluate((e) => e.isConnected), false, 'the card drawn again');
      assert.strictEqual(await pg.locator(card + ' .pv iframe').count(), 1, 'with its preview open');
      assert.strictEqual((await pv()).live, 1, 'exactly one reading after the save');
      await measured();
      const n = await ran(4500);
      assert.ok(n >= 1 && n <= 3, 'one reading every 2 s, not two: ' + n + ' runs in 4.5 s');
      assert.strictEqual((await pv()).live, 1, 'still one');
      /* «Cerrar sesión» with the preview open: nothing left reading */
      await pg.click('#outBtn');
      assert.strictEqual((await pv()).live, 0, 'stopped by «Cerrar sesión»');
      await pg.waitForSelector('#loginView:not([hidden]) #loginForm:not([hidden])', { timeout: 8000 });
      assert.strictEqual(await ran(2600), 0, 'no reading after signing out');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'v2 · «Cambiar foto» replaces an entry\'s photo in its place: a product keeps its product with a photo of its own (uploaded under menu-photos/pantallas/ on saving), «Foto del menú» takes it back to the menu\'s; a photo-only entry gets the new photo at the same index',
    run: async ({ browser }) => {
      one(`update menu_items set photo_url = 'https://fotos.test/latte.png' where name = 'Latte'`);
      const pg = await asOwnerPin(browser, { viewport: { width: 1280, height: 900 } });
      await tab(pg, 'slides');
      const latte = itemId('Latte'), ham = itemId('Ham & Cheese'), banana = itemId('Banana Bread'), before = photos();
      await pg.click('#newCompo');
      await pg.waitForSelector('#slideForm #edZones .zone');
      await pg.click('#edTemplates .tpl[data-template="2-lado"]');
      const zone = (i) => `#edZones .zone[data-zone="${i}"]`, entry = (i, j) => `${zone(i)} .entry[data-entry="${j}"]`;
      const add = async (i, q, item) => {
        if ((await pg.getAttribute(`#edZ-${i}-add`, 'aria-pressed')) !== 'true') await pg.click(`#edZ-${i}-add`);
        await pg.fill(`#edZ-${i}-search`, q);
        await pg.click(`#edZ-${i}-picker .pick[data-item="${item}"]`);
      };
      const labels = (i) => pg.$$eval(zone(i) + ' .entry .einfo b', (a) => a.map((x) => x.textContent));
      const src = (sel) => pg.getAttribute(sel + ' .frame img', 'src');
      /* left: the latte (the menu's photo) and the sandwich; right: an uploaded photo and the banana bread */
      await add(0, 'latte', latte);
      await add(0, 'ham & cheese', ham);
      await pg.click(zone(1) + ' [data-act=subir]');
      await pg.setInputFiles('#photoFile', { name: 'vieja.png', mimeType: 'image/png', buffer: PHOTO });
      await until(async () => /Lista: 1 × 1 px/.test(await text(pg, '#edZerr-1')), 8000, 'the first photo made ready');
      await add(1, 'banana', banana);
      assert.strictEqual(await src(entry(0, 0)), 'https://fotos.test/latte.png', 'the menu\'s photo');
      assert.strictEqual(await pg.locator(entry(0, 0) + ' [data-act=foto-menu]').count(), 0, 'no «Foto del menú» while it shows the menu\'s');
      assert.strictEqual(await pg.locator(zone(0) + ' .entry [data-act=cambiar-foto]').count(), 2, '«Cambiar foto» on every entry');
      await pg.evaluate((s) => { const z = document.querySelector(s + ' input[type=range]'); z.value = 150; z.dispatchEvent(new Event('input', { bubbles: true })); }, entry(0, 0));
      /* «Cambiar foto» on the latte: the same place, the same product, a photo of its own, the framing from the start */
      await pg.click(entry(0, 0) + ' [data-act=cambiar-foto]');
      await pg.setInputFiles('#photoFile', { name: 'latte-propia.png', mimeType: 'image/png', buffer: PHOTO });
      await until(async () => /^Lista: 1 × 1 px, \d+ KB\. Se sube al guardar o al abrir la vista previa\.$/.test(await text(pg, '#edZerr-0')), 8000, 'the new photo made ready, said at the zone');
      assert.deepStrictEqual(await labels(0), ['1. Latte · ₡2 200 en el menú', '2. Ham & Cheese · ₡4 000 en el menú'], 'the entry stays first, with its product');
      assert.match(await src(entry(0, 0)), /^blob:/, 'the new photo in its frame');
      assert.deepStrictEqual(await encuadre(pg, entry(0, 0)), { zoom: '100', focus: 'Enfoque 50 %, 50 % · tamaño 100 % · toque o arrastre la miniatura', pos: '50% 50%', tr: '' }, 'framing reset for the new picture');
      assert.strictEqual(await pg.locator(entry(0, 0) + ' [data-act=foto-menu]').count(), 1, '«Foto del menú» to go back');
      assert.strictEqual(await pg.locator(entry(0, 1) + ' [data-act=foto-menu]').count(), 0, 'not on an entry that shows the menu\'s photo');
      assert.strictEqual(await pg.locator(entry(1, 0) + ' [data-act=foto-menu]').count(), 0, 'not on a photo-only entry');
      /* «Cambiar foto» on the photo-only entry: the new photo, in its place */
      const old = await src(entry(1, 0));
      await pg.click(entry(1, 0) + ' [data-act=cambiar-foto]');
      await pg.setInputFiles('#photoFile', { name: 'nueva.png', mimeType: 'image/png', buffer: PHOTO });
      await until(async () => (await src(entry(1, 0))) !== old, 8000, 'the new photo in the first entry\'s frame');
      assert.match(await src(entry(1, 0)), /^blob:/);
      const right = await labels(1);
      assert.ok(right.length === 2 && right[0] === '1. Foto (nueva)' && /^2\. Banana Bread · /.test(right[1]), 'still first, the banana bread second: ' + right);
      assert.deepStrictEqual(photos(), before, 'nothing uploaded before Guardar');
      await pg.fill('#ed-kicker_es', 'Tarde');
      await save(pg, '#edSave');
      const id = one(`select id from screen_slides`);
      const saved = slideJson(id), z0 = saved.zones[0].entries, z1 = saved.zones[1].entries;
      const URL_RX = /^https?:\/\/[^/]+\/storage\/v1\/object\/public\/menu-photos\/(pantallas\/[0-9a-f-]{36}\.jpg)$/;
      assert.deepStrictEqual([z0.length, z0[0].item, z0[0].focus, z0[0].zoom], [2, latte, [50, 50], 100], 'the latte keeps its product and its place');
      assert.match(z0[0].photo || '', URL_RX, 'with a photo of its own, uploaded under menu-photos/pantallas/');
      assert.deepStrictEqual(z0[1], { item: ham, photo: null, focus: [50, 50], zoom: 100 }, 'the sandwich as it was');
      assert.deepStrictEqual([z1.length, z1[0].item, z1[1].item, z1[1].photo], [2, null, banana, null], 'the photo-only entry still first');
      assert.match(z1[0].photo || '', URL_RX);
      assert.notStrictEqual(z0[0].photo, z1[0].photo);
      assert.deepStrictEqual(photos().filter((k) => !before.includes(k)).sort(), [z0[0].photo, z1[0].photo].map((u) => 'menu-photos/' + URL_RX.exec(u)[1]).sort(),
        'two files, the two in use: the replaced first photo never went up');
      /* «Foto del menú»: the latte back to the menu's photo */
      await pg.click(`article.slide[data-slide="${id}"] [data-act=editar]`);
      await pg.waitForSelector('#slideForm #edZones .zone');
      assert.strictEqual(await src(entry(0, 0)), z0[0].photo, 'read back with its own photo');
      await pg.click(entry(0, 0) + ' [data-act=foto-menu]');
      assert.strictEqual(await src(entry(0, 0)), 'https://fotos.test/latte.png', 'the menu\'s photo again');
      assert.strictEqual(await pg.locator(entry(0, 0) + ' [data-act=foto-menu]').count(), 0);
      assert.deepStrictEqual(await labels(0), ['1. Latte · ₡2 200 en el menú', '2. Ham & Cheese · ₡4 000 en el menú']);
      await save(pg, '#edSave');
      const back = slideJson(id);
      assert.deepStrictEqual(back.zones[0].entries[0], { item: latte, photo: null, focus: [50, 50], zoom: 100 }, 'no photo of its own: the menu\'s, the product unchanged');
      assert.deepStrictEqual([back.zones[0].entries[1], back.zones[1]], [saved.zones[0].entries[1], saved.zones[1]], 'the rest as it was');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'v2 · «Cambiar foto» follows its entry (moved or taken out meanwhile) and never puts an older photo back: after the preview uploaded the first, the second is saved and the first taken away; also when the first upload ends only after «Cambiar foto», or during Guardar, and Cancelar takes both away',
    run: async ({ browser }) => {
      const pg = await asOwnerPin(browser, { viewport: { width: 1280, height: 900 } });
      await tab(pg, 'slides');
      const zone = '#edZones .zone[data-zone="0"]', entry = (j) => `${zone} .entry[data-entry="${j}"]`;
      const src = (j) => pg.getAttribute(entry(j) + ' .frame img', 'src');
      const URL_RX = /\/storage\/v1\/object\/public\/menu-photos\/(pantallas\/[0-9a-f-]{36}\.jpg)$/;
      /* every upload under menu-photos/pantallas/, in order (bucket path); the one numbered hold.n waits for hold.go */
      const ups = []; let hold = null;
      const holdNext = () => { let go; hold = { n: ups.length + 1, p: new Promise((ok) => { go = ok; }) }; return go; };
      await pg.route(/\/storage\/v1\/object\/menu-photos\/pantallas\/[0-9a-f-]{36}\.jpg$/, async (r) => {
        if (r.request().method() !== 'POST') return r.continue();
        ups.push(/(pantallas\/[0-9a-f-]{36}\.jpg)$/.exec(r.request().url())[1]);
        if (hold && ups.length === hold.n) await hold.p;
        return r.continue();
      });
      const stored = (k) => photos().includes('menu-photos/' + k);
      const deleted = (k) => pg.deletes.some((d) => d.includes(k));
      const ready = () => until(async () => /^Lista: 1 × 1 px/.test((await text(pg, '#edZerr-0')) || ''), 8000, 'the photo made ready');
      const pick = async (sel, file) => {
        await pg.evaluate(() => { document.getElementById('edZerr-0').textContent = ''; });
        await pg.click(sel);
        await pg.setInputFiles('#photoFile', { name: file, mimeType: 'image/png', buffer: PHOTO });
      };
      /* a composition of one zone whose entries are photos */
      const start = async (n) => {
        await pg.click('#newCompo');
        await pg.waitForSelector('#slideForm #edZones .zone');
        await pg.click('#edTemplates .tpl[data-template="1"]');
        for (let k = 0; k < n; k++) { await pick(zone + ' [data-act=subir]', 'foto-' + k + '.png'); await ready(); }
        await pg.fill('#ed-kicker_es', 'Jardín');
      };
      const savedPhoto = (id) => { const p = slideJson(id).zones[0].entries[0].photo || '', m = URL_RX.exec(p); assert.ok(m, 'an uploaded photo: ' + p); return m[1]; };
      const newest = (but) => one(`select id from screen_slides where id::text <> all('{${but.join(',')}}'::text[])`);   /* the one saved last */

      /* 1) «Cambiar foto» goes to its entry, not to the place it had when it was clicked */
      await start(2);
      const a = await src(0), b = await src(1);
      await pg.click(entry(0) + ' [data-act=cambiar-foto]');
      await pg.click(entry(0) + ' [data-act=abajo]');               /* the entry moves to second while the file is chosen */
      await pg.setInputFiles('#photoFile', { name: 'otra.png', mimeType: 'image/png', buffer: PHOTO });
      await until(async () => (await src(1)) !== a, 8000, 'the new photo, on the moved entry');
      assert.strictEqual(await src(0), b, 'the other entry keeps its photo');
      await pg.click(entry(1) + ' [data-act=cambiar-foto]');
      await pg.click(entry(1) + ' [data-act=quitar]');              /* and this one is taken out meanwhile */
      const c = await src(0);
      await pg.setInputFiles('#photoFile', { name: 'tarde.png', mimeType: 'image/png', buffer: PHOTO });
      await until(async () => (await text(pg, '#edZerr-0')) === 'Esa entrada ya no está. Elija la foto otra vez.', 8000, 'said at the zone');
      assert.deepStrictEqual([await pg.locator(zone + ' .entry').count(), await src(0)], [1, c], 'nothing else changed');
      await pg.click('#edCancel');

      /* 2) the preview uploads the first photo; «Cambiar foto» then: the second is saved, the first taken away */
      await start(1);
      await pg.click('#edPreviewBtn');
      await until(() => ups.length === 1 && stored(ups[0]), 8000, 'the first photo uploaded for the preview');
      await pick(entry(0) + ' [data-act=cambiar-foto]', 'segunda.png');
      await ready();
      await save(pg, '#edSave');
      const id1 = newest([]), s1 = savedPhoto(id1);
      assert.deepStrictEqual([ups.length, s1], [2, ups[1]], 'the second photo saved, not the first: ' + JSON.stringify(ups));
      await until(() => deleted(ups[0]), 8000, 'the first one taken away (the test Storage keeps no DELETE: the request naming the file is the proof)');
      assert.ok(!deleted(s1), 'the saved one stays');

      /* 3) the first upload ends only after «Cambiar foto» (held here until then): still the second is saved */
      let go = holdNext();
      await start(1);
      await pg.click('#edPreviewBtn');
      await until(() => ups.length === hold.n, 8000, 'the first upload under way');
      const late = ups[hold.n - 1];
      await pick(entry(0) + ' [data-act=cambiar-foto]', 'cuarta.png');
      await ready();
      assert.ok(!stored(late), 'the first upload still held');
      go();
      await until(() => stored(late), 8000, 'the first upload ended');
      await save(pg, '#edSave');
      const id2 = newest([id1]), s2 = savedPhoto(id2);
      assert.deepStrictEqual([ups.length - hold.n, s2], [1, ups[hold.n]], 'the second photo saved, not the late first: ' + JSON.stringify(ups));
      await until(() => deleted(late), 8000, 'the late first one taken away');
      assert.ok(!deleted(s2));

      /* 4) the same during Guardar itself (no preview): the late first one never makes it into the slide */
      go = holdNext();
      await start(1);
      await pg.evaluate(() => { const t = document.getElementById('toast'); t.classList.remove('show'); t.textContent = ''; });
      await pg.click('#edSave');
      await until(() => ups.length === hold.n, 8000, 'Guardar uploading the first photo');
      const late2 = ups[hold.n - 1];
      await pick(entry(0) + ' [data-act=cambiar-foto]', 'sexta.png');
      await ready();
      go();
      await until(() => pg.evaluate(() => { const t = document.getElementById('toast'); return t.classList.contains('show') && t.textContent === 'Guardado'; }), 10000, '«Guardado»');
      const id3 = newest([id1, id2]), s3 = savedPhoto(id3);
      assert.deepStrictEqual([ups.length - hold.n, s3], [1, ups[hold.n]], 'Guardar uploaded the second one too and saved it: ' + JSON.stringify(ups));
      await until(() => deleted(late2), 8000, 'the late first one taken away');
      assert.ok(!deleted(s3));

      /* 5) the race again, then Cancelar: the late first one and the second both taken away */
      go = holdNext();
      await start(1);
      await pg.click('#edPreviewBtn');
      await until(() => ups.length === hold.n, 8000, 'the first upload under way');
      const late3 = ups[hold.n - 1];
      await pick(entry(0) + ' [data-act=cambiar-foto]', 'octava.png');
      await ready();
      go();
      await until(() => ups.length === hold.n + 1 && stored(late3) && stored(ups[hold.n]), 8000, 'both uploaded for the preview');
      const second = ups[hold.n];
      await pg.click('#edCancel');
      await until(() => deleted(late3) && deleted(second), 8000, 'both taken away: no orphan file');
      assert.strictEqual(slides(), 3, 'nothing more saved');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'the owner login\'s idle sign-out first takes away a photo uploaded for a preview and never saved: no orphan file in Storage',
    run: async ({ browser }) => {
      const pg = await open(browser, { login: 'owner', aal: 'aal2', viewport: { width: 1280, height: 900 } });
      await pg.waitForSelector('#appView:not([hidden]) article.tv', { timeout: 12000 });
      await tab(pg, 'slides');
      await pg.click('#newCompo');
      await pg.waitForSelector('#slideForm #edZones .zone');
      await pg.click('#edTemplates .tpl[data-template="1"]');
      const before = photos();
      await pg.click('#edZones .zone[data-zone="0"] [data-act=subir]');
      await pg.setInputFiles('#photoFile', { name: 'abandonada.png', mimeType: 'image/png', buffer: PHOTO });
      await until(async () => /Lista: 1 × 1 px/.test(await text(pg, '#edZerr-0')), 8000, 'the photo made ready');
      await pg.click('#edPreviewBtn');
      await until(() => photos().length === before.length + 1, 8000, 'uploaded for the preview');
      const key = photos().filter((k) => !before.includes(k))[0].replace(/^menu-photos\//, '');
      assert.ok(!pg.deletes.some((d) => d.includes(key)), 'nothing taken away yet');
      /* the owner walks away: the test's idle time, armed again by a key */
      await pg.evaluate(() => { window.PANTALLAS_TEST = { idleMs: 600 }; document.dispatchEvent(new KeyboardEvent('keydown')); });
      await until(() => pg.deletes.some((d) => d.includes(key)), 8000, 'the photo taken away (the test Storage keeps no DELETE: the request naming the file is the proof)');
      await pg.waitForSelector('#loginView:not([hidden]) #loginForm:not([hidden])', { timeout: 10000 });
      assert.strictEqual(await pg.locator('#appView').isHidden(), true, 'signed out');
      assert.strictEqual(slides(), 0, 'nothing saved');
      assert.deepStrictEqual(pg.errors, []);
    }
  }
];
