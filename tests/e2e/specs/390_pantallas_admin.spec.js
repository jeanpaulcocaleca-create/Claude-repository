/* The owner's page for the customer TVs (website/pantallas.html + pantallas.js, migration 0036, docs/PANTALLAS.md).
   The owner's conditions it is held to here:
   2) a new page only: no PIN box of its own (340 still counts 19), the shared PIN screen of access.js;
   3) prices and availability only from the menu, never written (a product slide stores the item, not its price);
   6) nothing new: Storage's existing bucket for the photos;
   7) combos and discounts never announced: blocked while typing and refused by the server;
   8) only with the owner's PIN (or the owner login with the phone code), the server's own checks and a change log.
   Also: an unknown address is refused before any client exists, Spanish only, and a slide made here is what the
   promotions TV reads (pantalla_datos). */
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
/* the page on its own device; every database function it calls is kept in pg.rpc */
async function open(browser, opts) {
  opts = Object.assign({ login: 'cafe', lang: 'es' }, opts || {});
  const pg = await page(browser, opts);
  pg.rpc = [];
  pg.on('request', (r) => { const m = /\/rest\/v1\/rpc\/([a-z_]+)/.exec(r.url()); if (m) pg.rpc.push(m[1]); });
  await pg.route(/cloudfront\.net/, (r) => r.fulfill({ status: 200, contentType: 'image/png', body: PHOTO }));
  await goto(pg, '/pantallas');
  return pg;
}
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
  }
];
