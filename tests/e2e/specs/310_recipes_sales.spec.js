/* Recipes stage 1B (migrations 0031-0032), with several devices: a sale rung without internet keeps the recipe and the
   cost of its moment although a manager changed the recipe on another device before it was sent; an item taken off a
   bill gives back exactly what it took although the recipe changed; a second device with an old view of the bill is
   refused; a bill paid in part and voided leaves out only what was eaten; a void nets the bill to zero; an item added on
   the device to an order not confirmed yet keeps the recipe of when it was added. */
'use strict';
const assert = require('assert');
const { page, goto, until, sql, openRegister, STAFF, PINS } = require('../lib');
const gw = require('../gateway');

const API = 'http://127.0.0.1:' + (Number(process.env.E2E_SITE_PORT || 8090) + 1000);
const BATIDO = '1b000000-0000-4000-8000-0000000e3101', FRESA = '5a000000-0000-4000-8000-0000000e3101', LECHE = '5a000000-0000-4000-8000-0000000e3102';
function setup() {
  sql(`insert into menu_items (id, category_id, name, price_crc, sort, available) values
         ('${BATIDO}', 'a0000000-0000-4000-8000-000000000003', 'T Batido', 3000, 0, true);
       insert into stock_items (id, name, unit, pack_qty, cost_per_pack) values
         ('${FRESA}', 'Fresa e2e', 'g', 1000, 4000), ('${LECHE}', 'Leche e2e', 'ml', 1000, 1000);
       insert into recipes (menu_item_id, stock_item_id, qty) values ('${BATIDO}', '${FRESA}', 120), ('${BATIDO}', '${LECHE}', 100);`);
}
const moves = (where) => sql(`select coalesce(string_agg(s.name || ':' || trim_scale(m.qty)::text || '@' || trim_scale(m.unit_cost)::text, ' ' order by m.id), '')
                                from stock_moves m join stock_items s on s.id = m.item_id where ${where}`);
const net = (order) => sql(`select coalesce(string_agg(s.name || '=' || trim_scale(x.q)::text, ' ' order by s.name), '')
                              from (select item_id, sum(qty) q from stock_moves where order_id = '${order}' group by item_id) x
                              join stock_items s on s.id = x.item_id where x.q <> 0`);
/* another device of the café, through the same API the pages use */
async function rpc(name, args) {
  const r = await fetch(API + '/rest/v1/rpc/' + name, { method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + gw.sessionFor('cafe@test.local').access_token },
    body: JSON.stringify(args) });
  const body = await r.json();
  if (!r.ok) throw new Error(name + ' ' + r.status + ' ' + JSON.stringify(body));
  return body;
}
/* the till with the register open; its own 20 s retry is off: the test decides when it sends */
async function till(browser) {
  openRegister();
  const pg = await page(browser, { login: 'cafe', lang: 'en' });
  await pg.addInitScript(() => {
    const si = window.setInterval;
    window.setInterval = function (fn, ms) { return ms === 20000 ? 0 : si.apply(this, arguments); };
  });
  await goto(pg, '/pos');
  await pg.waitForFunction(() => document.querySelectorAll('.pbtn').length > 0, null, { timeout: 15000 });
  if (await pg.isVisible('#dayModal')) await pg.click('#dayClose');
  if (await pg.isVisible('#stationModal')) await pg.click('#stationForm button[type=submit]');
  await pg.evaluate(() => clearInterval(liveTimer));
  return pg;
}
async function tap(pg, name) {
  const hit = await pg.evaluate((nm) => {
    const find = () => [...document.querySelectorAll('.pbtn')].find((x) => (x.querySelector('.nm') || x).textContent.trim() === nm);
    let b = find();
    for (const t of [...document.querySelectorAll('#rail .tab')]) { if (b) break; t.click(); b = find(); }
    if (b) b.click();
    return !!b;
  }, name);
  if (!hit) throw new Error('no menu button ' + name);
}
const queued = (pg) => pg.evaluate(() => JSON.parse(localStorage.getItem('hg-pos-queue') || '[]').length);

/* the recipe editor on the owner's device: one quantity changed, saved with Ana's PIN */
async function changeRecipe(browser, grams) {
  const pg = await page(browser, { login: 'owner', aal: 'aal2', lang: 'en' });
  await goto(pg, '/inventory');
  await until(async () => (await pg.locator('#kItems').textContent()) !== '–', 15000, 'inventory loaded');
  await pg.click('#tabs [data-view=recipes]');
  await until(async () => (await pg.locator('#menuList button').count()) > 0, 10000, 'menu listed');
  const i = await pg.evaluate(() => Array.prototype.findIndex.call(document.querySelectorAll('#menuList button'),
    (b) => b.firstChild && b.firstChild.firstChild && b.firstChild.firstChild.textContent === 'T Batido'));
  await pg.locator('#menuList button').nth(i).click();
  await pg.waitForSelector('#recipeCard:not([hidden])');
  await until(async () => (await pg.locator('#recipeRows .recipe-row').count()) === 2, 5000, 'the two lines');
  const row = pg.locator('#recipeRows .recipe-row').filter({ has: pg.locator('select.ing option:checked', { hasText: 'Fresa e2e' }) });
  await row.locator('input').fill(String(grams));
  await pg.click('#recipeSave');
  await pg.waitForSelector('#recPinModal:not([hidden])');
  await pg.selectOption('#recMgr', STAFF.ana);
  await pg.fill('#recPin', PINS.ana);
  await pg.click('#recPinGo');
  await until(async () => /^Recipe saved · version \d+$/.test(((await pg.locator('#toast').textContent()) || '').trim()), 8000, 'saved with the PIN');
  assert.deepStrictEqual(pg.errors, []);
  await pg.context().close();
}

module.exports.tests = [
  {
    name: 'a sale rung without internet keeps the recipe and the cost of its moment, although the recipe changed on another device before it was sent',
    run: async ({ browser }) => {
      setup();
      const b = await till(browser);
      // this device loses its connection (the browser says it is offline; the other devices are still online)
      await b.context().setOffline(true);
      await tap(b, 'T Batido'); await tap(b, 'T Batido');
      await b.click('[data-pay="card"]');
      if (await b.locator('#numModal:not([hidden])').count()) await b.click('#numNone');
      await until(async () => (await queued(b)) === 1, 5000, 'the sale waits on the device');
      // meanwhile, on the owner's device: 150 g instead of 120 g; and dearer strawberries arrive
      await changeRecipe(browser, 150);
      sql(`insert into stock_moves (item_id, kind, qty, unit_cost) values ('${FRESA}', 'purchase', 5000, 6)`);
      assert.strictEqual(sql(`select count(*) from orders`), '0', 'the till has not sent it yet');
      await b.context().setOffline(false);      // the connection is back: the till sends what it kept
      await b.evaluate(() => syncQueue());
      await until(() => sql(`select count(*) from orders o join order_items i on i.order_id = o.id`) === '1', 15000, 'the sale arrives');
      const order = sql(`select id from orders`);
      assert.strictEqual(moves(`order_id = '${order}'`), 'Fresa e2e:-240@4 Leche e2e:-200@1', 'two smoothies as rung: 120 g each at ₡4');
      assert.strictEqual(sql(`select v.source || ':' || v.version from order_items i join recipe_versions v on v.id = i.recipe_version_id`), 'direct:1',
                         'the line names the version it took');
      // the next sale, rung now, takes the new recipe at the new cost
      await tap(b, 'T Batido');
      await b.click('[data-pay="card"]');
      if (await b.locator('#numModal:not([hidden])').count()) await b.click('#numNone');
      await until(() => sql(`select count(*) from orders`) === '2', 15000, 'the second sale');
      assert.strictEqual(moves(`order_id <> '${order}'`), 'Fresa e2e:-150@6 Leche e2e:-100@1', 'a sale of now: 150 g at ₡6');
      await until(async () => (await queued(b)) === 0, 8000, 'nothing left on the device');
      assert.deepStrictEqual(b.errors, []);
    }
  },
  {
    name: 'two devices on one bill: an item taken off gives back exactly what it took; the other device is refused; part paid then voided leaves out only what was eaten',
    run: async ({ browser }) => {
      setup();
      const BILL = '0d000000-0000-4000-8000-0000000e3101', LINE = '0e000000-0000-4000-8000-0000000e3101';
      sql(`insert into orders (id, total_crc, payment_method, status, paid, source, station, guest_name)
             values ('${BILL}', 10500, 'pending', 'preparing', false, 'front', 'Caja', 'Mesa 7');
           insert into order_items (id, order_id, item_name, price_crc, qty, menu_item_id) values
             ('${LINE}', '${BILL}', 'T Batido', 3000, 3, '${BATIDO}'),
             ('0e000000-0000-4000-8000-0000000e3102', '${BILL}', 'Espresso', 1500, 1, null)`);
      assert.strictEqual(net(BILL), 'Fresa e2e=-360 Leche e2e=-300', 'three smoothies out (120 g each)');
      // the recipe changes and strawberries get dearer
      await changeRecipe(browser, 200);
      sql(`insert into stock_moves (item_id, kind, qty, unit_cost) select id, 'purchase', on_hand, 16 from stock_items where id = '${FRESA}'`);
      const one = await till(browser), two = await till(browser);
      for (const d of [one, two]) {
        await d.evaluate((x) => openTab(x), BILL);
        await d.waitForSelector('#tabModal:not([hidden])');
        await until(async () => (await d.locator('#tabLines .tline').count()) === 2, 8000, 'the bill');
      }
      // device one takes a smoothie off
      await one.locator('#tabLines .tline', { hasText: 'T Batido' }).locator('button.rm').click();
      await until(() => moves(`order_id = '${BILL}' and qty > 0`) === 'Fresa e2e:120@4 Leche e2e:100@1', 8000, 'what it took comes back: 120 g at ₡4 (not 200 g at ₡10)');
      // device two still shows the old bill: refused, nothing more comes back
      await two.locator('#tabLines .tline', { hasText: 'T Batido' }).locator('button.rm').click();
      await until(async () => /The bill changed on another device/.test((await two.textContent('#tabErr')) || ''), 8000, 'the other device is told');
      assert.strictEqual(moves(`order_id = '${BILL}' and qty > 0`), 'Fresa e2e:120@4 Leche e2e:100@1', 'and nothing else came back');
      assert.strictEqual(sql(`select qty from order_items where id = '${LINE}'`), '2', 'two smoothies left');
      // one smoothie paid by item, then the bill is voided by a manager
      const total = Number(sql(`select total_crc from orders where id = '${BILL}'`));
      const paid = await rpc('tab_pay', { p_order_id: BILL, p_method: 'card', p_lines: [{ item_id: LINE, qty: 1 }], p_amount: null, p_station: 'Caja', p_expect: total });
      assert.ok(paid.ok, 'paid by item: ' + JSON.stringify(paid));
      const voided = await rpc('manager_void_order', { p_manager_id: STAFF.ana, p_manager_pin: PINS.ana, p_order_id: BILL, p_reason: 'se fueron' });
      assert.ok(voided.ok, 'voided: ' + JSON.stringify(voided));
      assert.strictEqual(net(BILL), '', 'the bill itself nets to zero');
      assert.strictEqual(moves(`order_item_id = '${LINE}' and order_id is null`), 'Fresa e2e:-120@4 Leche e2e:-100@1', 'the smoothie paid and eaten stays out, as it went out');
      assert.deepStrictEqual(one.errors.concat(two.errors), []);
    }
  },
  {
    name: 'an item added on the device to an order the system has not confirmed takes the recipe and cost of when it was added, although they changed before it was sent',
    run: async ({ browser }) => {
      setup();
      const b = await till(browser);
      // the order reaches the system but its reply is lost: the till keeps it, and sends what is added after it
      let lost = true;
      await b.route(/rest\/v1\/rpc\/pos_record_sale/, async (r) => {
        if (r.request().method() !== 'POST' || !lost) return r.fallback();
        await r.fetch().catch(() => {});
        return r.abort('connectionreset');
      });
      const ORDER = 'f1000000-0000-4000-8000-0000000e3103';
      await b.evaluate((o) => { queue.push(o); saveQueue(); return syncQueue(); }, {
        local_id: 'o1', id: ORDER, created_at: new Date(Date.now() - 15 * 60000).toISOString(), total_crc: 1500, payment_method: 'pending',
        pickup_number: 74, needs_kitchen: false, status: 'ready', paid: false, none: true, station: 'Caja', guest_name: null,
        items: [{ id: 'f1000000-0000-4000-8000-0000000e3104', item_name: 'Espresso', price_crc: 1500, qty: 1 }] });
      assert.strictEqual(sql(`select count(*) from orders where id = '${ORDER}'`), '1', 'the order is in the system; the till does not know it');
      // a smoothie added on this device to that order
      await b.locator('#openBar .ocard', { hasText: '#74' }).click();
      await b.waitForSelector('#locModal:not([hidden])', { timeout: 8000 });
      await b.click('#locAdd');
      await b.waitForSelector('#addBar:not([hidden])');
      await tap(b, 'T Batido');
      await b.click('#addGo');
      await b.waitForSelector('#locModal:not([hidden])', { timeout: 8000 });
      await b.click('#locClose');
      await until(() => b.evaluate(() => !qRound), 15000, 'the saving round to finish');
      assert.strictEqual(sql(`select count(*) from order_items where order_id = '${ORDER}'`), '1', 'the smoothie is still only on the device');
      // then, on the owner's device, 150 g instead of 120 g; and dearer strawberries arrive
      await changeRecipe(browser, 150);
      sql(`insert into stock_moves (item_id, kind, qty, unit_cost) values ('${FRESA}', 'purchase', 5000, 6)`);
      // the replies come back: the order is confirmed and the smoothie goes after it, with the time it was added
      lost = false;
      await b.evaluate(async () => { while (qRound) { try { await qRound; } catch (e) {} } queue.forEach((o) => delete o.err); return syncQueue(); });
      await until(() => sql(`select count(*) from order_items where order_id = '${ORDER}'`) === '2', 15000, 'the smoothie arrives');
      assert.strictEqual(moves(`order_id = '${ORDER}'`), 'Fresa e2e:-120@4 Leche e2e:-100@1', 'as when it was added: 120 g at ₡4, not 150 g at ₡6');
      await until(async () => (await queued(b)) === 0, 8000, 'nothing left on the device');
      assert.deepStrictEqual(b.errors, []);
    }
  }
];
