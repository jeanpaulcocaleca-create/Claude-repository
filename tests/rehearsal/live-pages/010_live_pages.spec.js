/* Canopy OS rehearsal · the pages that are LIVE on hanginggardencafe.com today (the gh-pages build named in
   tests/rehearsal/LIVE_PAGES), on the copy of production after every migration (0000-0038 today). Until the new pages are
   published, the café keeps using these: they must load and work exactly as before. Also run on the reset copy
   (tests/rehearsal/reset-pages.sh): nothing here assumes earlier sales, so the same checks hold on the empty café. */
'use strict';
const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { page, goto, until, settle, sql, registerTill, STAFF, PINS } = require('../../e2e/lib');
const gw = require('../../e2e/gateway');

/* the local stand-in for Supabase answers on the site port + 1000 (tests/e2e/gateway.js; live-pages.sh points the pages there) */
const API = 'http://127.0.0.1:' + (Number(process.env.E2E_SITE_PORT || 8090) + 1000);
function watchApi(pg) {
  pg.apiErrors = [];
  pg.on('response', (r) => {
    if (r.url().startsWith(API + '/') && r.status() >= 400) pg.apiErrors.push(r.status() + ' ' + r.request().method() + ' ' + r.url().slice(API.length));
  });
  return pg;
}
const quiet = (ms) => new Promise((r) => setTimeout(r, ms));
/* on a day with no register opened yet, the live POS opens its Today panel once by itself (a nudge to open the register)
   over the product grid; a cashier closes it and sells, the register is opened by the manager (the empty café after
   the reset, tests/rehearsal/reset-pages.sh) */
async function closeDayNudge(pg) {
  await quiet(800);
  if (await pg.locator('#dayModal').isVisible()) await pg.click('#dayClose');
}
/* sales saved with their lines (the old POS writes the order, then its lines, in two requests) */
const withLines = () => Number(sql(`select count(*) from public.orders o where exists (select 1 from public.order_items i where i.order_id = o.id)`));

/* ---------- the POS discounts of 0038 (D-065) under the live POS: proposal §5.3, W2 and W3 ----------
   The live build has the old free window (approve_discount: a percentage, a reason, a manager picked from the list and
   their PIN) and the old × on a bill (tab_set_discount with no approval). On a copy with 0038: with pos_free_discount on
   (its default) that window works as today, but a reason that reads as one of the four categories is refused with the old
   page's own missing_reason text (W2); the old × takes a category discount off a bill while nothing is paid, and refuses
   once a part is paid (W3); with the switch off the window shows the page's own «reload this page» text and the till keeps
   selling. A copy without 0038, or a build without the old window (once the discounts are published), has nothing to
   check. Seed codes: Ana manager 4826, Luis staff 5284, Marta staff 6173 (seed-legacy.sql, tests/db/90_seed.sql). */
const liveFile = (name) => { try { return fs.readFileSync(path.join(process.env.E2E_SITE_ROOT || '', name), 'utf8'); } catch (e) { return ''; } };
/* the old page's texts: the English source in the live pos.html, the Spanish the live lang.js shows (the till opens in Spanish) */
const OLD = {
  reason: ['Pick the reason for the discount.', 'Elija el motivo del descuento.'],                      // DISC_ERR.missing_reason
  removed: ['Discount removed', 'Descuento quitado'],                                                     // the bill's × with nothing left
  update: ['This needs a database update: apply the pending migrations (docs/MIGRACIONES.md), then reload this page.',
           'Esto necesita una actualización de la base de datos: aplique las migraciones pendientes (docs/MIGRACIONES.md) y recargue esta página.'],
  approved: ['Discount approved by {n}', 'Descuento aprobado por {n}']
};
/* why there is nothing to check on this copy or build, or null; the texts above must be the live build's own */
function oldDiscounts() {
  if (sql(`select count(*) from canopy.migrations where version = 38`) !== '1') return '0038 is not on this copy';
  const pos = liveFile('pos.html'), lang = liveFile('lang.js');
  if (!/rpc\('approve_discount'/.test(pos) || !pos.includes('id="discWhy"') || !pos.includes('id="tabDiscX"')) return 'this build has no old discount window';
  for (const [en, es] of Object.values(OLD)) {
    if (!en.includes('{n}')) assert.ok(pos.includes(`'${en}'`), 'the live pos.html says «' + en + '»');
    assert.ok(lang.includes(`'${en}': '${es}'`), 'the live lang.js translates «' + en + '» as «' + es + '»');
  }
  return null;
}
/* the live till (Spanish, as the café runs it), its toasts recorded as shown (each text once it changed, so the Spanish
   lang.js puts in is kept even when the next toast replaces it) */
async function liveTill(browser) {
  const pg = watchApi(await page(browser, { login: 'cafe' }));
  await goto(pg, '/pos.html');
  await until(async () => (await pg.locator('#menuGrid .pbtn').count()) > 1, 15000, 'the menu');
  await settle(pg);
  await closeDayNudge(pg);
  await pg.evaluate(() => {
    window.__seen = [];
    const t = document.getElementById('toast');
    new MutationObserver(() => { const s = t.textContent; if (s && window.__seen[window.__seen.length - 1] !== s) window.__seen.push(s); })
      .observe(t, { childList: true, characterData: true, subtree: true });
  });
  return pg;
}
const toastSeen = (pg, s) => until(() => pg.evaluate((x) => window.__seen.includes(x), s), 8000, 'the message «' + s + '»');
/* the old window over the ticket, filled as a cashier does: 10 %, a reason (and its details), Ana and her PIN; returns the
   server's answer to approve_discount */
async function openOldWindow(pg) {
  await pg.click('#discBtn');
  await pg.waitForSelector('#discModal:not([hidden])', { timeout: 5000 });
  await until(() => pg.evaluate((a) => [...document.querySelectorAll('#discMgr option')].some((o) => o.value === a), STAFF.ana), 8000, 'the managers listed');
}
async function askOld(pg, why, note) {
  await pg.click('#discPct [data-pct="10"]');
  await pg.selectOption('#discWhy', why);
  await pg.fill('#discNote', note || '');
  await pg.selectOption('#discMgr', STAFF.ana);
  await pg.fill('#discPin', PINS.ana);
  const answer = pg.waitForResponse((r) => /\/rest\/v1\/rpc\/approve_discount$/.test(r.url()) && r.request().method() === 'POST', { timeout: 10000 });
  await pg.click('#discGo');
  const r = await answer;
  const body = await r.json().catch(() => null);
  await until(() => pg.evaluate(() => !document.getElementById('discGo').disabled), 8000, 'the answer handled');
  return { status: r.status(), body };
}
const approvalsCount = () => Number(sql(`select count(*) from public.discount_approvals`));
/* the API as a page calls it: this page's own sign-in (a registered till), or another device of the café */
async function signedIn(pg) {
  const s = await pg.evaluate(() => { try { return JSON.parse(localStorage.getItem('sb-127-auth-token') || 'null'); } catch (e) { return null; } });
  assert.ok(s && s.access_token, 'the live page is signed in');
  return s.access_token;
}
async function rpcAs(token, name, args) {
  const r = await fetch(API + '/rest/v1/rpc/' + name, { method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + token }, body: JSON.stringify(args) });
  const body = await r.json();
  if (!r.ok) throw new Error(name + ' ' + r.status + ' ' + JSON.stringify(body));
  return body;
}
/* a bill not paid yet, as another device left it: 2 lattes and a sandwich, ₡8 000 */
const W3 = (n) => 'd0380000-0000-4000-8000-00000000000' + n, W3LINE = (n, i) => 'd0380000-0000-4000-8000-0000000001' + n + i;
function w3Bill(n, name) {
  sql(`insert into public.orders (id, total_crc, payment_method, status, paid, source, station, guest_name, done_at)
         values ('${W3(n)}', 8000, 'pending', 'done', false, 'front', 'Caja', '${name}', now());
       insert into public.order_items (id, order_id, item_name, price_crc, qty)
         values ('${W3LINE(n, 1)}', '${W3(n)}', 'Latte ensayo', 2000, 2), ('${W3LINE(n, 2)}', '${W3(n)}', 'Sándwich ensayo', 4000, 1)`);
}
const w3State = (n) => sql(`select total_crc || '|' || coalesce(discount_crc, 0) || '|' || coalesce(discount_id::text, '-') || '|' || coalesce(subtotal_crc::text, '-')
                                   || '|' || coalesce(parts_crc, 0) || '|' || coalesce(discount_reason, '-') || '|' || paid from public.orders where id = '${W3(n)}'`);

module.exports.tests = [
  {
    name: 'every live page loads on the migrated database: no script errors, no refused API call, nothing sent to the real Supabase',
    run: async ({ browser }) => {
      sql(`update public.app_settings set room_orders_enabled = true, room_open = '00:00', room_close = '23:59' where id = 1`);
      const room = sql(`select code from public.rooms where active order by number limit 1`);
      const pages = [
        ['cafe', '/pos.html'], ['cafe', '/kitchen.html'], ['cafe', '/time.html'], ['cafe', '/sales.html'],
        ['owner', '/home.html'], ['owner', '/inventory.html'], ['owner', '/admin.html'], ['owner', '/qr.html'],
        // an owner login without the phone code enrolled signs in at aal1
        ['owner1', '/home.html'], ['owner1', '/inventory.html'], ['owner1', '/admin.html'],
        [null, '/index.html'], [null, '/m.html'], [null, '/menu.html'], [null, '/tv.html'], [null, '/room.html?r=' + room],
        [null, '/es/menu.html']
      ];
      const problems = [];
      for (const [login, path] of pages) {
        const pg = watchApi(await page(browser, { login: login ? login.replace('owner1', 'owner') : undefined, aal: login === 'owner' ? 'aal2' : undefined }));
        await goto(pg, path);
        await quiet(2500);
        const where = (login || 'visitor') + ' ' + path;
        if (pg.errors.length) problems.push(where + ' script errors: ' + pg.errors.join(' | '));
        if (pg.apiErrors.length) problems.push(where + ' API: ' + pg.apiErrors.join(' | '));
        if (pg.supabaseHits) problems.push(where + ' tried the real Supabase');
        await pg.context().close();
      }
      assert.deepStrictEqual(problems, []);
    }
  },
  {
    name: 'the live POS rings a sale; the new database numbers it, dates it and stamps its tax',
    run: async ({ browser }) => {
      const pg = watchApi(await page(browser, { login: 'cafe' }));
      await goto(pg, '/pos.html');
      await until(async () => (await pg.locator('#menuGrid .pbtn').count()) > 1, 15000, 'the menu');
      await closeDayNudge(pg);
      const before = withLines();
      await pg.locator('#menuGrid .pbtn').nth(0).click();
      await pg.locator('#menuGrid .pbtn').nth(1).click();
      await pg.click('[data-pay=card]');
      if (await pg.locator('#numModal').isVisible()) await pg.click('#numNone');
      await until(() => withLines() === before + 1, 10000, 'the sale saved with its lines');
      const o = sql(`select business_date = public.cr_today(), receipt_no is not null, location_id is not null, payment_method,
                            (select count(*) from public.order_items i where i.order_id = o.id and i.net_crc is not null and i.tax_rate is not null)
                       from public.orders o order by created_at desc limit 1`);
      assert.match(o, /^t\|t\|t\|card\|[12]$/, 'sale of the old page: ' + o);
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, []);
    }
  },
  {
    name: 'the live POS keeps a sale taken without internet and uploads it when the connection is back',
    run: async ({ browser, setOffline }) => {
      const pg = watchApi(await page(browser, { login: 'cafe' }));
      await goto(pg, '/pos.html');
      await until(async () => (await pg.locator('#menuGrid .pbtn').count()) > 0, 15000, 'the menu');
      await settle(pg);   // every load-time check answered: the Today nudge, if any, is up before it is closed
      await closeDayNudge(pg);
      const before = Number(sql(`select count(*) from public.orders`)), beforeLines = withLines();
      setOffline(true);
      await pg.locator('#menuGrid .pbtn').nth(0).click();
      await pg.click('[data-pay=cash_crc]');
      // a build with the cash window (0010; v2026.10.14-1 on) asks what was handed over: the exact amount
      await quiet(400);
      if (await pg.locator('#cashModal').isVisible()) await pg.click('#cashExact');
      if (await pg.locator('#numModal').isVisible()) await pg.click('#numNone');
      await quiet(1500);
      assert.strictEqual(Number(sql(`select count(*) from public.orders`)), before, 'nothing reached the database while offline');
      setOffline(false);
      await until(() => withLines() === beforeLines + 1, 70000, 'the offline sale uploaded with its lines');
      assert.strictEqual(Number(sql(`select count(*) from public.orders`)), before + 1, 'saved once');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    // a device that stayed offline for days while recipes changed and 0030-0032 were applied: the sale it kept (dated
    // before the window) uploads untouched, takes the recipe the history started with and the first cost it knows, and
    // is flagged for a manager (0003); nothing is lost and nothing of today's recipe is deducted
    name: 'the live POS uploads a sale it kept for three days (rung before 0030, recipe and cost changed meanwhile): the starting recipe, the first cost, late_sync and after_close',
    run: async ({ browser }) => {
      const MI = '1c000000-0000-4000-8000-00000000c001', FR = '5c000000-0000-4000-8000-00000000c001', LE = '5c000000-0000-4000-8000-00000000c002';
      const SALE = '0c000000-0000-4000-8000-00000000c001', LINE = '0e000000-0000-4000-8000-00000000c001';
      const cat = sql(`select id from public.menu_categories order by sort, name limit 1`);
      // the product had its recipe before the window (no history: written with the triggers off); 0030 wrote the starting
      // version today; since then the recipe changed (a direct change, which 0030 records) and dearer strawberries arrived;
      // the register of the sale's day is closed
      sql(`insert into public.menu_items (id, category_id, name, price_crc) values ('${MI}', '${cat}', 'Batido ensayo', 3000);
           insert into public.stock_items (id, name, unit, pack_qty, cost_per_pack) values ('${FR}', 'Fresa ensayo', 'g', 1000, 4000), ('${LE}', 'Leche ensayo', 'ml', 1000, 1000);
           set session_replication_role = replica;
           insert into public.recipes (menu_item_id, stock_item_id, qty) values ('${MI}', '${FR}', 120), ('${MI}', '${LE}', 100);
           set session_replication_role = origin;
           select canopy.recipe_baseline();
           update public.recipes set qty = 150 where menu_item_id = '${MI}' and stock_item_id = '${FR}';
           insert into public.stock_moves (item_id, kind, qty, unit_cost) values ('${FR}', 'purchase', 5000, 6);
           insert into public.register_days (business_date, opened_by, opened_by_name, float_crc, closed_at, closed_by, closed_by_name)
             values (((now() - interval '3 days') at time zone 'America/Costa_Rica')::date, '${STAFF.ana}', 'Ana', 50000, now() - interval '2 days 10 hours', '${STAFF.ana}', 'Ana')
             on conflict (business_date) do update set closed_at = coalesce(public.register_days.closed_at, excluded.closed_at)`);
      // the sale exactly as the live recordSale() keeps it in localStorage 'hg-pos-queue', dated three days ago
      const kept = { local_id: 'o1760000000000abcde', id: SALE, none: true, created_at: new Date(Date.now() - 3 * 86400e3).toISOString(), total_crc: 6000,
                     payment_method: 'card', pickup_number: null, needs_kitchen: false, status: 'done', paid: true, station: 'Caja', guest_name: null,
                     items: [{ id: LINE, item_name: 'Batido ensayo', price_crc: 3000, qty: 2, menu_item_id: MI }] };
      const pg = watchApi(await page(browser, { login: 'cafe', storage: { 'hg-pos-queue': JSON.stringify([kept]) } }));
      await goto(pg, '/pos.html');
      await until(() => Number(sql(`select count(*) from public.order_items where order_id = '${SALE}'`)) === 1, 70000, 'the old sale uploaded with its line');
      await until(async () => (await pg.evaluate(() => JSON.parse(localStorage.getItem('hg-pos-queue') || '[]').length)) === 0, 10000, 'the device let it go');
      // (on the reset copy the sale is also from before the reset: 0028 adds before_reset, nothing else)
      const o = sql(`select (flags @> '{late_sync,after_close}' and flags <@ '{late_sync,after_close,before_reset}') || '|' || flags::text || '|'
                            || (business_date = ((now() - interval '3 days') at time zone 'America/Costa_Rica')::date) || '|' || (rung_at = created_at)
                       from public.orders where id = '${SALE}'`);
      assert.match(o, /^true\|\{[a-z_,]+\}\|true\|true$/, 'flagged late_sync and after_close, counted on its own day, rung_at kept: ' + o);
      assert.strictEqual(sql(`select v.source || ' v' || v.version || '|' || (i.stock_time = o.created_at) from public.order_items i join public.orders o on o.id = i.order_id
                                join public.recipe_versions v on v.id = i.recipe_version_id where i.id = '${LINE}'`), 'baseline v1|true', 'the line names the starting version and its own moment');
      assert.strictEqual(sql(`select string_agg(s.name || ':' || trim_scale(m.qty) || '@' || trim_scale(m.unit_cost), ' ' order by s.name)
                                from public.stock_moves m join public.stock_items s on s.id = m.item_id where m.order_id = '${SALE}'`),
                         'Fresa ensayo:-240@4 Leche ensayo:-200@1', 'the recipe of before (120 g) at the cost of before (₡4), not 150 g at ₡6');
      assert.strictEqual(sql(`select count(*) from public.audit_log where action = 'late_sale_after_close' and target_id = '${SALE}'`), '1', 'the manager log names it');
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, []);
    }
  },
  {
    name: 'the live time clock punches with a PIN',
    run: async ({ browser }) => {
      const pg = watchApi(await page(browser, { login: 'cafe' }));
      await goto(pg, '/time.html');
      await until(async () => (await pg.locator('#staffGrid button', { hasText: 'Marta' }).count()) > 0, 15000, 'the staff');
      const before = Number(sql(`select count(*) from public.time_entries`));
      await pg.locator('#staffGrid button', { hasText: 'Marta' }).first().click();
      await pg.fill('#pinInput', '6173');
      await pg.click('#pinGo');
      await until(() => Number(sql(`select count(*) from public.time_entries`)) === before + 1, 10000, 'the punch');
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, []);
    }
  },
  {
    // 0033 (D-053) changed every PIN check and the team editor underneath the live pages: a wrong PIN, the manager PIN
    // that opens Hours, and adding a person with a free PIN must behave exactly as before
    name: 'the live Hours and team editor: a wrong PIN, the manager PIN, and a new person with a free PIN',
    run: async ({ browser }) => {
      const level = Number(sql(`select public.canopy_schema_version()`));
      const pg = watchApi(await page(browser, { login: 'cafe', lang: 'en' }));
      await goto(pg, '/time.html');
      await until(async () => (await pg.locator('#staffGrid button').count()) > 0, 15000, 'the clock');
      await pg.click('#tabHours');
      await pg.waitForSelector('#hoursPinModal:not([hidden])', { timeout: 10000 });
      await pg.selectOption('#hpWho', STAFF.ana);
      await pg.fill('#hpPin', '1111');
      await pg.click('#hoursPinForm button[type=submit]');
      await until(async () => /not right/.test(await pg.locator('#hpErr').textContent()), 8000, 'a wrong PIN is refused');
      await pg.fill('#hpPin', '4826');
      await pg.click('#hoursPinForm button[type=submit]');
      await until(async () => pg.locator('#hoursPinModal').isHidden(), 8000, 'the manager PIN opens Hours');
      await pg.click('#addStaffBtn');
      await pg.waitForSelector('#staffModal:not([hidden])', { timeout: 5000 });
      await pg.fill('#stName', 'Ensayo Equipo');
      await pg.fill('#stPin', '9264');
      await pg.fill('#stPin2', '9264');
      await pg.click('#staffForm button[type=submit]');
      await until(() => sql(`select count(*) from public.staff where name = 'Ensayo Equipo' and active`) === '1', 8000, 'the new person saved');
      if (level >= 33) assert.strictEqual(sql(`select details->>'by_login' is not null from public.audit_log where action = 'staff_save' order by id desc limit 1`), 't', 'logged with the login (0033)');
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, []);
    }
  },
  {
    name: 'the live Menu Manager still recolors a category and moves it to the kitchen (owner login)',
    run: async ({ browser }) => {
      const pg = watchApi(await page(browser, { login: 'owner', aal: 'aal2' }));
      await goto(pg, '/admin.html');
      await until(async () => (await pg.locator('#cats input[type=color]').count()) > 0, 15000, 'the categories');
      const id = sql(`select id from public.menu_categories order by sort, name limit 1`);
      await pg.locator('#cats input[type=color]').first().evaluate((el) => { el.value = '#3b6ea8'; el.dispatchEvent(new Event('change')); });
      await until(() => sql(`select color from public.menu_categories where id = '${id}'`) === '#3b6ea8', 8000, 'the color saved');
      const k = sql(`select kitchen from public.menu_categories where id = '${id}'`);
      await pg.locator('#cats input[type=checkbox]').first().click();
      await until(() => sql(`select kitchen from public.menu_categories where id = '${id}'`) !== k, 8000, 'the kitchen switch saved');
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, []);
    }
  },
  {
    // Two live editors are possible. The pre-1A editor (published until v2026.10.15-1) deletes the recipe and inserts
    // it again without a PIN: on 0030 and 0031 that works and the history records it as a direct change; from 0032 it is
    // refused and nothing changes. The editor published with 0030-0032 (v2026.10.17-1 and later) asks for a manager's
    // PIN and saves through recipe_save: one new version, source editor (on a database without 0030 it saves the old way).
    name: 'the live recipe editor: the PIN editor saves a version with a manager PIN; the old one saves up to 0031 and is refused from 0032',
    run: async ({ browser }) => {
      const stock = sql(`select id from public.stock_items where active order by name limit 1`);
      let mi = sql(`select menu_item_id from public.recipes order by menu_item_id limit 1`);
      if (!mi) {   // a copy without recipes: give one product a line first
        mi = sql(`select id from public.menu_items order by name limit 1`);
        sql(`insert into public.recipes (menu_item_id, stock_item_id, qty) values ('${mi}', '${stock}', 1)`);
      }
      const name = sql(`select name from public.menu_items where id = '${mi}'`);
      const level = Number(sql(`select public.canopy_schema_version()`)), v30 = level >= 30, locked = level >= 32;
      const versions = () => Number(sql(`select count(*) from public.recipe_versions where menu_item_id = '${mi}'`));
      const before = v30 ? versions() : 0;
      // in English: the Spanish page translates product names, and the product is found by its stored name
      const pg = watchApi(await page(browser, { login: 'owner', aal: 'aal2', lang: 'en' }));
      await goto(pg, '/inventory.html');
      await until(async () => (await pg.locator('#kItems').textContent()) !== '–', 15000, 'inventory loaded');
      await pg.click('#tabs [data-view=recipes]');
      await until(async () => (await pg.locator('#menuList button').count()) > 0, 10000, 'the menu listed');
      const i = await pg.evaluate((n) => Array.prototype.findIndex.call(document.querySelectorAll('#menuList button'),
        (b) => b.firstChild && b.firstChild.firstChild && b.firstChild.firstChild.textContent === n), name);
      assert.ok(i >= 0, name + ' is listed');
      await pg.locator('#menuList button').nth(i).click();
      await pg.waitForSelector('#recipeCard:not([hidden])', { timeout: 5000 });
      const line = pg.locator('#recipeRows .recipe-row').first();
      const item = await line.locator('select').first().inputValue();   // the ingredient; the PIN editor adds a unit select
      const qty = Number(await line.locator('input').inputValue());
      await line.locator('input').fill(String(qty + 1));
      await pg.click('#recipeSave');
      const pinEditor = (await pg.locator('#recPinForm').count()) > 0;
      if (pinEditor && v30) {
        // the editor published with 0030-0032: a manager (Ana, seeded with her test PIN) authorizes; recipe_save writes one version
        await pg.waitForSelector('#recPinModal:not([hidden])', { timeout: 5000 });
        await pg.selectOption('#recMgr', 'a1000000-0000-4000-8000-000000000001');
        await pg.fill('#recPin', '4826');
        await pg.click('#recPinGo');
        try { await until(async () => /Recipe saved|Receta guardada/.test(await pg.locator('#toast').textContent()), 8000, 'saved with the PIN'); }
        catch (e) { throw new Error(e.message + ' · PIN window: ' + (await pg.locator('#recPinErr').textContent()) + ' · recipe: ' + (await pg.locator('#recipeErr').textContent())); }
        assert.strictEqual(Number(sql(`select qty from public.recipes where menu_item_id = '${mi}' and stock_item_id = '${item}'`)), qty + 1, 'the new quantity is saved');
        await until(() => versions() === before + 1, 5000, 'one version more');
        assert.strictEqual(sql(`select source || ':' || coalesce(by_name, '') from public.recipe_versions where menu_item_id = '${mi}' order by version desc limit 1`),
          'editor:Ana', 'recorded as an editor version authorized by Ana');
        assert.deepStrictEqual(pg.errors, []);
        assert.deepStrictEqual(pg.apiErrors, []);
        return;
      }
      if (locked) {
        await until(async () => /Could not save the recipe/.test(await pg.locator('#toast').textContent()), 8000, 'refused');
        assert.strictEqual(Number(sql(`select qty from public.recipes where menu_item_id = '${mi}' and stock_item_id = '${item}'`)), qty, 'the recipe is unchanged');
        assert.strictEqual(versions(), before, 'and nothing was recorded');
        assert.deepStrictEqual(pg.errors, []);
        assert.ok(pg.apiErrors.length >= 1 && pg.apiErrors.every((e) => /^40[13] DELETE \/rest\/v1\/recipes/.test(e)), 'only the refused delete: ' + pg.apiErrors.join(' | '));
        return;
      }
      await until(async () => /Recipe saved|Receta guardada/.test(await pg.locator('#toast').textContent()), 8000, 'saved');
      assert.strictEqual(Number(sql(`select qty from public.recipes where menu_item_id = '${mi}' and stock_item_id = '${item}'`)), qty + 1, 'the new quantity is saved');
      if (v30) {
        // the live page deletes, then inserts: two direct versions (the recipe emptied, then the new one)
        await until(() => versions() === before + 2, 5000, 'two versions more');
        assert.strictEqual(sql(`select string_agg(source || ':' || jsonb_array_length(lines), ' ' order by version) from (select * from public.recipe_versions
                                 where menu_item_id = '${mi}' order by version desc limit 2) v`), 'direct:0 direct:' + sql(`select count(*) from public.recipes where menu_item_id = '${mi}'`));
      }
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, []);
    }
  },
  {
    name: 'the live customer screens (V2, when the build has them) on the copy migrated to the last migration with V2 data saved, as the owner configures them (docs/ACTIVACION-PANTALLAS-V2.md §4): Screen B shows the composition in force, Screen A shows only the summarized menu, with live prices',
    run: async ({ browser }) => {
      const fs = require('fs'), path = require('path');
      const root = process.env.E2E_SITE_ROOT || '';
      if (!fs.existsSync(path.join(root, 'pantalla-promos.html')) || !fs.existsSync(path.join(root, 'pantalla-menu.html'))) {
        console.log('    (this build has no customer screens: nothing to check)'); return;
      }
      if (sql(`select count(*) from canopy.migrations where version = 37`) !== '1') { console.log('    (0037 is not on this copy: nothing to check)'); return; }
      const items = JSON.parse(sql(`select json_agg(json_build_object('id', i.id, 'name', i.name, 'es', coalesce(i.name_es, i.name)) order by c.sort, i.sort, i.name)
                                       from public.menu_items i join public.menu_categories c on c.id = i.category_id
                                      where i.available and i.price_crc > 0 and c.name <> 'Extras & Combos'`));
      assert.ok(items.length >= 2, 'the copy sells at least two products');
      /* what the V2 panel saves: a composition in force on every TV, and the summarized menu with the 32" choices */
      const zones = JSON.stringify([{ mode: 'fija', seconds: 8, labels: true, fallback: null, entries: [{ item: items[0].id, photo: null, focus: [50, 50], zoom: 100 }] }]);
      const compo = sql(`with x as (insert into public.screen_slides (kind, template, zones, kicker_es, kicker_en, starts_at, ends_at, sort, status)
        values ('composicion', '1', '${zones}'::jsonb, 'Composición V2', 'V2 composition', now() - interval '1 hour', now() + interval '1 day', 10, 'activa') returning id) select id from x`);
      sql(`update public.screens set item_ids = array['${items[0].id}']::uuid[], density = 'compacta', english = 'no' where id = 'menu-1'`);
      assert.strictEqual(sql(`select (public.pantalla_datos('promos-1') -> 'slides' -> 0 ->> 'kind')`), 'composicion', '0037 gives the composition to the promotions TV');

      /* Screen B (V2): the composition in force is read and shown */
      const b = watchApi(await page(browser, {}));
      await goto(b, '/pantalla-promos.html?tv=promos-1');
      await until(() => b.evaluate(() => window.PANTALLA_B && PANTALLA_B.info().estado === 'al-dia'), 15000, 'Screen B read pantalla_datos');
      await until(() => b.evaluate((c) => PANTALLA_B.info().actual === c, compo), 15000, 'Screen B shows the composition');
      const i = await b.evaluate(() => PANTALLA_B.info());
      assert.deepStrictEqual([i.actual, i.tipo, i.leidas.includes(compo)], [compo, 'composicion', true], 'the composition in force');
      assert.deepStrictEqual(b.errors, []);
      assert.deepStrictEqual(b.apiErrors, []);
      await b.context().close();

      /* Screen A (V2): only the products of the summarized menu, prices live */
      const a = watchApi(await page(browser, {}));
      await goto(a, '/pantalla-menu.html?tv=menu-1');
      await until(() => a.evaluate(() => window.PANTALLA && PANTALLA.info().estado === 'al-dia'), 15000, 'Screen A read the menu');
      /* every page of the board (the pages take turns; textContent reads the ones waiting too) */
      const shown = await a.evaluate(() => document.getElementById('main').textContent);
      assert.ok(shown.includes(items[0].es) || shown.includes(items[0].name), 'the product of the summary is on the board: ' + items[0].name);
      const other = items.find((x) => x.name !== items[0].name && x.es !== items[0].es && !items[0].es.includes(x.es) && !x.es.includes(items[0].es));
      if (other) assert.ok(!shown.includes(other.es) && !shown.includes(other.name), 'a product outside the summary is not on the board: ' + other.name);
      assert.match(shown, /₡/, 'with prices');
      assert.deepStrictEqual(a.errors, []);
      assert.deepStrictEqual(a.apiErrors, []);
      await a.context().close();
    }
  },
  {
    // proposal §5.3 (W2): pos_free_discount on, the old window approves as today; a reason that reads as a category is not
    // one it may give (it would read as a category discount in the reports), so the server answers missing_reason and the
    // live window shows its own text for that answer
    name: 'the live discount window on 0038 with pos_free_discount on: «Other · Local» is refused with the old missing_reason text and no approval (W2); «Regular customer» is approved and its sale recorded as today',
    run: async ({ browser }) => {
      const skip = oldDiscounts();
      if (skip) { console.log('    (' + skip + ': nothing to check)'); return; }
      assert.strictEqual(sql(`select public.setting('pos_free_discount') #>> '{}'`), 'on', 'the old window is on, as 0038 leaves it');
      const pg = await liveTill(browser);
      const before = approvalsCount(), sales = withLines();
      await pg.locator('#menuGrid .pbtn').nth(0).click();
      await pg.locator('#menuGrid .pbtn').nth(1).click();
      await openOldWindow(pg);

      /* Other with the details «Local»: the reason «Other · Local» reads as the Local category */
      let r = await askOld(pg, 'Other', 'Local');
      assert.deepStrictEqual([r.status, r.body], [200, { ok: false, error: 'missing_reason' }], 'the server refuses the reserved reason');
      await until(async () => (await pg.textContent('#discErr')) === OLD.reason[1], 8000, 'the old page\'s text for missing_reason');
      assert.ok(await pg.isVisible('#discModal'), 'the window stays open');
      assert.ok(await pg.isHidden('#discRow'), 'no discount on the ticket');
      assert.strictEqual(approvalsCount(), before, 'no approval row made');

      /* the same window, «Regular customer» (the details cleared): approved and recorded as today */
      r = await askOld(pg, 'Regular customer', '');
      assert.ok(r.status === 200 && r.body && r.body.ok && r.body.name === 'Ana' && r.body.reason === 'Regular customer', 'approved: ' + JSON.stringify(r.body));
      await pg.waitForSelector('#discModal', { state: 'hidden', timeout: 8000 });
      await toastSeen(pg, OLD.approved[1].replace('{n}', 'Ana'));
      assert.ok(await pg.isVisible('#discRow'), 'the discount on the ticket');
      await pg.click('[data-pay=card]');
      if (await pg.locator('#numModal').isVisible()) await pg.click('#numNone');
      await until(() => withLines() === sales + 1, 10000, 'the discounted sale saved with its lines');
      const ap = r.body.id;
      // as before 0038: an old-kind approval (no category, no till, no day), used once by this sale; the sale carries
      // the 10 % of its subtotal, the reason and who approved it, and no discount flag
      assert.strictEqual(sql(`select (a.category is null) || '|' || a.kind || '|' || a.value || '|' || a.reason || '|' || a.approved_name || '|'
                                     || (a.till_id is null and a.cr_day is null and a.request_id is null) || '|' || (a.used_at is not null) || '|'
                                     || (a.subtotal_crc = o.subtotal_crc and a.amount_crc = o.discount_crc) || '|'
                                     || (o.discount_crc = round(o.subtotal_crc * 10 / 100.0)::int and o.total_crc = o.subtotal_crc - o.discount_crc) || '|'
                                     || o.discount_reason || '|' || o.discount_by || '|' || o.paid || '|' || o.payment_method || '|' || (o.business_date = public.cr_today()) || '|'
                                     || not (coalesce(o.flags, '{}') && array['discount_not_verified', 'discount_late', 'discount_daily_twice']::text[])
                                from public.discount_approvals a join public.orders o on o.id = a.order_id where a.id = '${ap}'`),
                         'true|percent|10|Regular customer|Ana|true|true|true|true|Regular customer|Ana|true|card|true|true', 'the sale and its approval as today');
      assert.strictEqual(approvalsCount(), before + 1, 'one approval, used');
      assert.strictEqual(sql(`select count(*) from public.audit_log where action = 'discount_approved' and target_id = '${ap}' and summary = 'Regular customer' and not (details ? 'category')`),
                         '1', 'logged as the old window logs it');
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, []);
    }
  },
  {
    // proposal §5.3 (W3): an Empleado discount on a bill, given by descuento_autorizar on a registered till as the new
    // page gives it; then the live page, which knows only tab_set_discount, takes it off with its ×. With nothing paid
    // it comes off as today and the employee's day still counts (a manager gives it back in the approvals log); once an
    // item is paid by item only descuento_quitar_cuenta (a manager's PIN) may take it off, so the live page shows its
    // own «database update» text and nothing changes
    name: 'the live bill × on 0038 over an Empleado discount from a registered till (W3): nothing paid, taken off as today and the day still counts; an item paid by item, the old «database update» text and nothing changes',
    run: async ({ browser }) => {
      const skip = oldDiscounts();
      if (skip) { console.log('    (' + skip + ': nothing to check)'); return; }
      w3Bill(1, 'Ensayo W3 sin pagar');
      w3Bill(2, 'Ensayo W3 pagada en parte');
      const pg = await liveTill(browser);
      await registerTill(pg, { station: 'Caja' });
      const me = await signedIn(pg), other = gw.sessionFor('cafe@test.local').access_token;
      const empleado = (n, employeePin) => rpcAs(me, 'descuento_autorizar', { p_category: 'empleado', p_pin: PINS.ana, p_subtotal: 8000,
        p_employee_pin: employeePin, p_order_id: W3(n), p_expect: 8000, p_request_id: crypto.randomUUID(), p_station: 'Caja' });

      /* 1. nothing paid: the old × takes it off as today */
      const a1 = await empleado(1, PINS.luis);
      assert.ok(a1.ok && a1.category === 'empleado' && a1.beneficiary === 'Luis' && a1.name === 'Ana' && a1.order_id === W3(1) && a1.total === 5600 && a1.discount === 2400,
                'Empleado for Luis on the bill: ' + JSON.stringify(a1));
      assert.strictEqual(w3State(1), `5600|2400|${a1.id}|8000|0|Employee|false`, 'the bill carries the category discount');
      await pg.evaluate((x) => openTab(x), W3(1));
      await pg.waitForSelector('#tabModal:not([hidden])', { timeout: 8000 });
      await pg.waitForSelector('#tabDiscX', { state: 'visible', timeout: 8000 });
      await pg.click('#tabDiscX');   // the confirm() is accepted, as a cashier does
      await toastSeen(pg, OLD.removed[1]);
      await until(() => w3State(1) === '8000|0|-|-|0|-|false', 8000, 'the discount off the bill');
      assert.strictEqual(sql(`select count(*) from public.audit_log where action = 'tab_discount_removed' and target_id = '${W3(1)}'`), '1', 'tab_discount_removed written');
      assert.strictEqual(sql(`select (freed_at is null) || '|' || coalesce(freed_how, '-') from public.discount_approvals where id = '${a1.id}'`), 'true|-',
                         'the approval is not freed: the employee\'s day still counts');
      assert.strictEqual(sql(`select string_agg((details ->> 'why') || '/' || (details ->> 'how'), ' ') from public.audit_log
                               where action = 'discount_not_freed' and target_id = '${a1.id}'`), 'needs_manager/bill_removed', 'discount_not_freed: a manager gives the day back');
      const again = await rpcAs(me, 'descuento_autorizar', { p_category: 'empleado', p_pin: PINS.ana, p_subtotal: 2000, p_employee_pin: PINS.luis,
                                                             p_request_id: crypto.randomUUID(), p_station: 'Caja' });
      assert.strictEqual(again.ok === false && again.error, 'daily_used', 'a second Empleado for Luis today is refused: ' + JSON.stringify(again));
      await pg.click('#tabClose');

      /* 2. one item paid by item first (on another device): the same × is refused, the old text, nothing changes */
      const a2 = await empleado(2, PINS.marta);
      assert.ok(a2.ok && a2.beneficiary === 'Marta' && a2.total === 5600, 'Empleado for Marta on the second bill: ' + JSON.stringify(a2));
      const paid = await rpcAs(other, 'tab_pay', { p_order_id: W3(2), p_method: 'card', p_lines: [{ item_id: W3LINE(2, 1), qty: 1 }], p_amount: null,
                                                   p_station: 'Caja 2', p_expect: 5600 });
      assert.ok(paid.ok, 'a latte paid by item on another device: ' + JSON.stringify(paid));
      const held = w3State(2), approvals = approvalsCount(), logged = sql(`select count(*) from public.audit_log`);
      assert.match(held, new RegExp('^\\d+\\|\\d+\\|' + a2.id + '\\|8000\\|[1-9]\\d*\\|Employee\\|false$'), 'the bill still carries it, a part paid: ' + held);
      await pg.evaluate((x) => openTab(x), W3(2));
      await pg.waitForSelector('#tabModal:not([hidden])', { timeout: 8000 });
      await pg.waitForSelector('#tabDiscX', { state: 'visible', timeout: 8000 });
      const refused = pg.waitForResponse((r) => /\/rest\/v1\/rpc\/tab_set_discount$/.test(r.url()) && r.request().method() === 'POST', { timeout: 10000 });
      await pg.click('#tabDiscX');
      const rr = await refused;
      assert.deepStrictEqual([rr.status(), ((await rr.json().catch(() => null)) || {}).message], [400, 'tab_set_discount_category'], 'the guard refuses the old call');
      await until(async () => (await pg.textContent('#tabErr')) === OLD.update[1], 8000, 'the old page\'s «database update» text');
      await quiet(1500);
      assert.strictEqual(w3State(2), held, 'the bill is unchanged');
      assert.strictEqual(approvalsCount(), approvals, 'no approval made');
      assert.strictEqual(sql(`select count(*) from public.audit_log`), logged, 'nothing logged');
      assert.strictEqual(sql(`select (freed_at is null) || '|' || coalesce(order_id::text, '-') from public.discount_approvals where id = '${a2.id}'`),
                         'true|' + W3(2), 'the approval as it was');
      assert.ok(await pg.isVisible('#tabModal'), 'the bill stays open on the till');
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, ['400 POST /rest/v1/rpc/tab_set_discount'], 'only the refused call');
    }
  },
  {
    // proposal §5.3: the owner turns the old window off at the end of the activation (descuento-libre-apagar.sql); an
    // older page still open then gets approve_discount_off, which it reads as a database it does not know: it shows its
    // own «reload this page» text (pos.html at that build: /approve_discount|schema cache|could not find/), approves
    // nothing, and sells as before
    name: 'the live discount window on 0038 with pos_free_discount off: its «reload this page» text, no approval, and the till keeps selling',
    run: async ({ browser }) => {
      const skip = oldDiscounts();
      if (skip) { console.log('    (' + skip + ': nothing to check)'); return; }
      sql(`insert into public.settings (key, value) values ('pos_free_discount', '"off"') on conflict (key) do update set value = excluded.value`);
      const pg = await liveTill(browser);
      const before = approvalsCount(), sales = withLines();
      await pg.locator('#menuGrid .pbtn').nth(0).click();
      await openOldWindow(pg);
      const r = await askOld(pg, 'Regular customer', '');
      assert.deepStrictEqual([r.status, r.body && r.body.message], [400, 'approve_discount_off'], 'the switch refuses the old call');
      await until(async () => (await pg.textContent('#discErr')) === OLD.update[1], 8000, 'the old page\'s «reload this page» text');
      assert.strictEqual(approvalsCount(), before, 'no approval made');
      await pg.click('#discCancel');
      assert.ok(await pg.isHidden('#discRow'), 'no discount on the ticket');

      /* the same ticket, charged without a discount */
      await pg.click('[data-pay=card]');
      if (await pg.locator('#numModal').isVisible()) await pg.click('#numNone');
      await until(() => withLines() === sales + 1, 10000, 'the sale saved with its lines');
      assert.match(sql(`select paid || '|' || payment_method || '|' || coalesce(discount_crc, 0) || '|' || coalesce(discount_id::text, '-') || '|'
                               || (total_crc = (select sum(qty * price_crc) from public.order_items i where i.order_id = o.id)) || '|' || (business_date = public.cr_today())
                          from public.orders o where exists (select 1 from public.order_items i where i.order_id = o.id) order by created_at desc limit 1`),
                   /^true\|card\|0\|-\|true\|true$/, 'a normal sale, as today');
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, ['400 POST /rest/v1/rpc/approve_discount'], 'only the refused call');
    }
  }
];
