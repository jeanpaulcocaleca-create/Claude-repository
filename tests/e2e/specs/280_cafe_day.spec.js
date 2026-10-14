/* A café morning on two devices with three people (migrations 0008, 0010, 0021, 0027): Ana opened the register; Luis
   signs in and clocks in on the front register, Marta on the terrace tablet; a sale, a pay-later order sent to the
   kitchen, the cook marks it ready, Luis closes Marta's bill; both end their turns; Ana counts the register; the owner
   reads the day by cashier. Every device is its own browser context. */
'use strict';
const assert = require('assert');
const { page, goto, until, sql, openRegister, STAFF, PINS } = require('../lib');

const ITEM = { sandwich: 'b0000000-0000-4000-8000-0000000000a1', latte: 'b0000000-0000-4000-8000-0000000000a2' };
function testMenu() {
  sql(`insert into menu_categories (id, name, sort, kitchen) values
         ('b0000000-0000-4000-8000-0000000000c1', 'Test Kitchen', 20, true), ('b0000000-0000-4000-8000-0000000000c2', 'Test Bar', 21, false);
       insert into menu_items (id, category_id, name, price_crc, sort, available) values
         ('${ITEM.sandwich}', 'b0000000-0000-4000-8000-0000000000c1', 'T Sandwich', 4000, 1, true),
         ('${ITEM.latte}', 'b0000000-0000-4000-8000-0000000000c2', 'T Latte', 2000, 1, true)`);
}
/* a device of the café: the POS with its station name; its 20 s retry is off (the test drives every round) */
async function device(browser, station) {
  const pg = await page(browser, { login: 'cafe', lang: 'es', station });
  await pg.addInitScript(() => { const si = window.setInterval; window.setInterval = function (fn, ms) { return ms === 20000 ? 0 : si.apply(this, arguments); }; });
  await goto(pg, '/pos');
  await pg.waitForSelector('#appView:not([hidden])', { timeout: 15000 });
  await pg.waitForFunction(() => document.querySelectorAll('.pbtn').length > 0, null, { timeout: 15000 });
  return pg;
}
async function signInAndClockIn(pg, who, pin) {
  await pg.waitForSelector('#opModal:not([hidden])', { timeout: 10000 });
  await pg.locator('#opWho button', { hasText: who }).click();
  await pg.fill('#opPin', pin);
  await pg.click('#opGo');
  await until(async () => pg.locator('#opClockGo').isVisible(), 8000, who + ': clock-in offered');
  await pg.fill('#opPin', pin);
  await pg.click('#opClockGo');
  await until(async () => (await pg.locator('#opBtn').textContent()) === who, 8000, who + ' signed in');
}
/* a product button, switching category tabs until it shows (as the tabs spec does) */
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
const text = async (pg, sel) => (await pg.locator(sel).textContent()) || '';

module.exports.tests = [
  {
    name: 'a morning on two devices: clock-ins from the POS, a sale, a pay-later order through the kitchen closed by another person, turns ended, the register counted, the day by cashier',
    run: async ({ browser }) => {
      sql(`insert into settings (key, value) values ('operator_mode', '"enforce"')`);
      testMenu();
      openRegister(50000);
      const caja = await device(browser, { name: 'Caja', main: true });
      const terraza = await device(browser, { name: 'Terraza', main: false });
      await signInAndClockIn(caja, 'Luis', PINS.luis);
      await signInAndClockIn(terraza, 'Marta', PINS.marta);
      assert.strictEqual(sql(`select count(*) from time_entries where clock_out is null`), '2', 'both clocked in');

      /* Luis: a latte by card on the front register */
      await tap(caja, 'T Latte');
      await caja.click('[data-pay="card"]');
      if (await caja.locator('#numModal:not([hidden])').count()) await caja.click('#numNone');
      await until(() => sql(`select count(*) from orders where paid`) === '1', 10000, 'the latte is saved');
      assert.strictEqual(sql(`select operator_name || '|' || station from orders where paid`), 'Luis|Caja');

      /* Marta: a pay-later order for table 2, number 7, sent from the terrace */
      await tap(terraza, 'T Sandwich'); await tap(terraza, 'T Latte');
      await terraza.click('#sendBtn');
      await terraza.waitForSelector('#numModal:not([hidden])');
      await terraza.fill('#numWho', 'Mesa 2');
      await terraza.locator('#numGrid button', { hasText: /^7$/ }).click();
      const bill = await until(() => sql(`select id from orders where pickup_number = 7 and not paid`), 10000, 'the order is saved unpaid');
      assert.strictEqual(sql(`select operator_name || '|' || station || '|' || status || '|' || total_crc from orders where id = '${bill}'`), 'Marta|Terraza|preparing|6000');

      /* the kitchen screen: the cook marks it ready */
      const k = await page(browser, { login: 'cafe', lang: 'es', viewport: { width: 1280, height: 800 } });
      await goto(k, '/kitchen');
      const ticket = k.locator('.tk[data-id="' + bill + '"]');
      await until(async () => (await ticket.count()) === 1, 10000, 'ticket 7 on the kitchen screen');
      assert.match(await ticket.textContent(), /T Sandwich/);
      await ticket.locator('button').first().click();
      await until(() => sql(`select status from orders where id = '${bill}'`) === 'ready', 8000, 'ready');

      /* Luis closes Marta's bill at the front register, by card: the money is his, the order stays hers */
      await caja.evaluate(() => pollLive());
      await caja.waitForSelector('.lv.due', { timeout: 8000 });
      await caja.locator('.lv.due button', { hasText: 'Abrir cuenta' }).click();
      await caja.waitForSelector('#tabModal:not([hidden])');
      assert.match(await text(caja, '#tabMeta'), /Mesa 2/);
      await caja.click('#tabPayRow [data-tpay="card"]');
      await until(() => sql(`select paid::text from orders where id = '${bill}'`) === 'true', 8000, 'the bill is closed');
      assert.strictEqual(sql(`select operator_name || '|' || paid_operator_name || '|' || payment_method from orders where id = '${bill}'`), 'Marta|Luis|card');
      await caja.click('#tabClose');
      await until(async () => (await caja.locator('#tabModal:not([hidden])').count()) === 0, 8000, 'bill window closed');

      /* turns end: Luis clocks out from the POS, Marta keeps her shift open */
      caja.onDialog = (d) => d.accept();
      await caja.click('#opBtn'); await caja.click('#opEnd');
      await until(() => sql(`select count(*) from time_entries where staff_id = '${STAFF.luis}' and clock_out is not null`) === '1', 8000, 'Luis clocked out');
      terraza.onDialog = (d) => d.dismiss();
      await terraza.click('#opBtn'); await terraza.click('#opEnd');
      await until(() => sql(`select count(*) from operator_sessions where ended_at is not null`) === '2', 8000, 'both turns ended');
      assert.strictEqual(sql(`select count(*) from time_entries where staff_id = '${STAFF.marta}' and clock_out is null`), '1', 'Marta still clocked in');

      /* Ana takes over the front register (enforce mode: the device asks who is ringing up) and counts it:
         ₡8 000 on the card terminal, the ₡50 000 float in the drawer */
      await signInAndClockIn(caja, 'Ana', PINS.ana);
      await caja.click('#dayBtn');
      await caja.waitForSelector('#rcCash', { state: 'visible', timeout: 5000 });
      await caja.fill('#rcTerminal', '8000');
      await caja.fill('#rcCash', '50000');
      await caja.selectOption('#rcStaff', STAFF.ana);
      await caja.fill('#rcPin', PINS.ana);
      await caja.click('#rcSubmit');
      await until(() => sql(`select closed_by_name from register_days where business_date = cr_today()`) === 'Ana', 8000, 'closed by Ana');
      assert.strictEqual(sql(`select terminal_crc || '|' || cash_counted_crc from register_days where business_date = cr_today()`), '8000|50000');

      /* the owner reads the day: the money by cashier */
      const own = await page(browser, { login: 'owner', aal: 'aal2', lang: 'en' });
      await goto(own, '/sales');
      await until(async () => own.locator('#cashierCard').isVisible(), 15000, 'by-cashier card');
      assert.match(await text(own, '#cashierBars'), /Luis[\s\S]*2 sales · ₡8\s000/, 'Luis took both payments');
      assert.doesNotMatch(await text(own, '#cashierBars'), /Marta/, 'Marta took no money');
      for (const [name, pg] of [['caja', caja], ['terraza', terraza], ['kitchen', k], ['owner', own]]) assert.deepStrictEqual(pg.errors, [], name + ' page errors');
    }
  }
];
