/* Recipes stage 1B (migrations 0031-0032), with several devices: a sale rung without internet keeps the recipe and the
   cost of its moment although a manager changed the recipe on another device before it was sent; an item taken off a
   bill gives back exactly what it took although the recipe changed; a second device with an old view of the bill is
   refused; a bill paid in part and voided leaves out only what was eaten; a void nets the bill to zero; an item added on
   the device to an order (not confirmed yet, or never sent) keeps the recipe of when it was added; two devices at the
   same instant, and a sale rung while a recipe is being saved. */
'use strict';
const assert = require('assert');
const { spawn } = require('child_process');
const { page, goto, until, sql, openRegister, registerSettled, earlierToday, STAFF, PINS } = require('../lib');
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
  await registerSettled(pg);
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
/* a database session of its own, running alongside the others (a transaction held open on purpose) */
function session(script) {
  return new Promise((resolve, reject) => {
    const p = spawn('psql', ['-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1', '-d', process.env.CANOPY_E2E_DB, '-f', '-']);
    let out = '', err = '';
    p.stdout.on('data', (d) => { out += d; });
    p.stderr.on('data', (d) => { err += d; });
    p.on('close', (code) => (code === 0 ? resolve(out.trim()) : reject(new Error('psql ' + code + ': ' + err))));
    p.stdin.end(script);
  });
}
const waiting = (marker) => until(() => sql(`select count(*) from pg_stat_activity where datname = current_database() and state = 'active' and query like '%${marker}%' and pid <> pg_backend_pid()`) === '1',
                                  5000, 'the other session to hold its transaction');
/* a local order rung 5 minutes ago (within today's business day), kept on the device, to pay later */
const localOrder = (id, num) => ({ local_id: 'o' + num, id, created_at: earlierToday(5), total_crc: 1500,
  payment_method: 'pending', pickup_number: num, needs_kitchen: false, status: 'ready', paid: false, none: true, station: 'Caja', guest_name: null,
  items: [{ id: id.slice(0, -2) + '99', item_name: 'Espresso', price_crc: 1500, qty: 1 }] });
async function addOnDevice(b, num, name) {
  await b.locator('#openBar .ocard', { hasText: '#' + num }).click();
  await b.waitForSelector('#locModal:not([hidden])', { timeout: 8000 });
  await b.click('#locAdd');
  await b.waitForSelector('#addBar:not([hidden])');
  await tap(b, name);
  await b.click('#addGo');
  await b.waitForSelector('#locModal:not([hidden])', { timeout: 8000 });
  await b.click('#locClose');
}

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
      await b.evaluate((o) => { queue.push(o); saveQueue(); return syncQueue(); }, localOrder(ORDER, 74));
      assert.strictEqual(sql(`select count(*) from orders where id = '${ORDER}'`), '1', 'the order is in the system; the till does not know it');
      // a smoothie added on this device to that order
      await addOnDevice(b, 74, 'T Batido');
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
  },
  {
    name: 'without internet the whole time: an item added to an order on the device goes up with it and keeps the recipe and cost of when it was added',
    run: async ({ browser }) => {
      setup();
      const b = await till(browser);
      await b.context().setOffline(true);
      const ORDER = 'f1000000-0000-4000-8000-0000000e3105';
      await b.evaluate((o) => { queue.push(o); saveQueue(); return syncQueue(); }, localOrder(ORDER, 75));
      // the recipe changes on the owner's device (150 g); then the smoothie is added on the till, still offline
      await changeRecipe(browser, 150);
      await addOnDevice(b, 75, 'T Batido');
      // later, dearer strawberries arrive
      sql(`insert into stock_moves (item_id, kind, qty, unit_cost) values ('${FRESA}', 'purchase', 5000, 6)`);
      assert.strictEqual(sql(`select count(*) from orders`), '0', 'nothing has left the till');
      await b.context().setOffline(false);
      await b.evaluate(() => syncQueue());
      await until(() => sql(`select count(*) from order_items where order_id = '${ORDER}'`) === '2', 15000, 'the order and its smoothie arrive together');
      assert.strictEqual(moves(`order_id = '${ORDER}'`), 'Fresa e2e:-150@4 Leche e2e:-100@1',
                         'the recipe of when it was added (150 g, after the change) at the cost then (₡4, before the delivery)');
      await until(async () => (await queued(b)) === 0, 8000, 'nothing left on the device');
      assert.deepStrictEqual(b.errors, []);
    }
  },
  {
    name: 'at the same instant: two devices take the same item off (one wins, nothing comes back twice); a sale rung while a recipe is being saved is kept, whole',
    run: async ({ browser }) => {
      setup();
      const BILL = '0d000000-0000-4000-8000-0000000e3106', LINE = '0e000000-0000-4000-8000-0000000e3106';
      sql(`insert into orders (id, total_crc, payment_method, status, paid, source, station, guest_name)
             values ('${BILL}', 10500, 'pending', 'preparing', false, 'front', 'Caja', 'Mesa 9');
           insert into order_items (id, order_id, item_name, price_crc, qty, menu_item_id) values
             ('${LINE}', '${BILL}', 'T Batido', 3000, 3, '${BATIDO}'), ('0e000000-0000-4000-8000-0000000e3107', '${BILL}', 'Espresso', 1500, 1, null)`);
      // the bill is busy for a moment (another device paying, say): both take-offs arrive while it is held
      const held = session(`begin; select 1 from orders where id = '${BILL}' for update; select pg_sleep(2.5) /* hold-bill */; commit;`);
      await waiting('hold-bill');
      const both = await Promise.all([1, 2].map(() => rpc('tab_remove_item', { p_item_id: LINE, p_qty: 1, p_reason: '', p_station: 'Caja',
                                                                            p_staff_id: null, p_pin: null, p_expect: 10500 })));
      await held;
      assert.deepStrictEqual(both.map((r) => r.ok ? 'ok' : r.error).sort(), ['changed', 'ok'], 'one take-off went through, the other was told');
      assert.strictEqual(moves(`order_id = '${BILL}' and qty > 0`), 'Fresa e2e:120@4 Leche e2e:100@1', 'one smoothie came back, once');
      assert.strictEqual(sql(`select qty from order_items where id = '${LINE}'`), '2');
      // a manager saves a recipe (150 g) and the save is still open when a sale is rung on the till
      const claims = JSON.stringify({ sub: gw.USERS['owner@test.local'], role: 'authenticated', aud: 'authenticated', aal: 'aal2', email: 'owner@test.local' });
      const ver = Number(sql(`select coalesce(max(version), 0) from recipe_versions where menu_item_id = '${BATIDO}'`));
      const lines = JSON.stringify([{ stock_item_id: FRESA, qty: 150, unit: 'g' }, { stock_item_id: LECHE, qty: 100, unit: 'ml' }]);
      const saving = session(`begin;
        select set_config('request.jwt.claims', '${claims}', true) \\g /dev/null
        set local role authenticated;
        select public.recipe_save('${BATIDO}', '${lines}'::jsonb, ${ver}, '${STAFF.ana}', '${PINS.ana}', null, gen_random_uuid())->>'ok';
        select pg_sleep(2.5) /* hold-save */ \\g /dev/null
        commit;`);
      await waiting('hold-save');
      const SALE = '0d000000-0000-4000-8000-0000000e3108';
      const sold = await rpc('pos_record_sale', { p_order: { id: SALE, total_crc: 3000, payment_method: 'card',
        items: [{ id: '0e000000-0000-4000-8000-0000000e3108', item_name: 'T Batido', price_crc: 3000, qty: 1, menu_item_id: BATIDO }] } });
      assert.strictEqual(await saving, 'true', 'the recipe was saved');
      assert.ok(sold.ok, 'the sale was kept: ' + JSON.stringify(sold));
      assert.strictEqual(moves(`order_id = '${SALE}'`), 'Fresa e2e:-120@4 Leche e2e:-100@1', 'the whole recipe of before, not half of each');
      assert.strictEqual(sql(`select v.version from order_items i join recipe_versions v on v.id = i.recipe_version_id where i.order_id = '${SALE}'`), String(ver),
                         'and it names the version it took');
      // the next sale takes the saved recipe
      const next = await rpc('pos_record_sale', { p_order: { id: '0d000000-0000-4000-8000-0000000e3109', total_crc: 3000, payment_method: 'card',
        items: [{ id: '0e000000-0000-4000-8000-0000000e3109', item_name: 'T Batido', price_crc: 3000, qty: 1, menu_item_id: BATIDO }] } });
      assert.ok(next.ok);
      assert.strictEqual(moves(`order_id = '0d000000-0000-4000-8000-0000000e3109'`), 'Fresa e2e:-150@4 Leche e2e:-100@1', 'the next sale: 150 g');
      assert.strictEqual(sql(`select count(*) from orders where flags <> '{}'`), '0', 'nothing was marked');
    }
  },
  {
    name: 'a sale whose stock could not be taken off, arrived late, came from a device with its clock off or lost its discount is shown in Sales for a manager (in Spanish)',
    run: async ({ browser }) => {
      sql(`insert into orders (id, created_at, total_crc, payment_method, paid, status, flags) values
             ('0d000000-0000-4000-8000-0000000e3110', now(), 3000, 'card', true, 'done', '{stock_not_taken,clock_ahead,discount_not_verified}'),
             ('0d000000-0000-4000-8000-0000000e3111', now(), 3000, 'card', true, 'done', '{recipe_item_missing,late_sync,after_close}');
           insert into order_items (order_id, item_name, price_crc, qty) values
             ('0d000000-0000-4000-8000-0000000e3110', 'Latte', 3000, 1), ('0d000000-0000-4000-8000-0000000e3111', 'Mocha', 3000, 1)`);
      const pg = await page(browser, { login: 'owner', aal: 'aal2', lang: 'es' });
      await goto(pg, '/sales');
      await until(async () => /Inventario no descontado · revisar con el encargado/.test(await pg.textContent('body')), 15000, 'the notice');
      const body = await pg.textContent('body');
      for (const t of ['Un ingrediente de su receta quedó fuera · revisar con el encargado', 'Reloj del aparato adelantado · revisar el aparato',
                       'Llegó tarde (guardada en un aparato) · cuenta en su propio día', 'Llegó después del cierre de caja de ese día · revisar con el encargado',
                       'Descuento sin verificar · revisar con el encargado']) assert.ok(body.includes(t), 'shown: ' + t);
      assert.deepStrictEqual(pg.errors, []);
    }
  }
];
