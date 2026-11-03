/* Touch screens get large on-screen pads; staff screens start in Spanish. */
'use strict';
const assert = require('assert');
const { page, goto, until, sql, openRegister, STAFF, PINS } = require('../lib');

async function touchPos(browser, opts) {
  openRegister();
  const context = await browser.newContext({ viewport: { width: 1180, height: 820 }, hasTouch: true, locale: 'en-US', timezoneId: 'America/Costa_Rica' });
  const pg = await page(browser, Object.assign({ context, login: 'cafe', lang: 'en' }, opts || {}));
  return pg;
}

module.exports.tests = [
  {
    name: 'a manager approves a void on a touch screen with the PIN pad',
    run: async ({ browser }) => {
      sql(`insert into orders (id, created_at, total_crc, payment_method, paid, status) values ('0d000000-0000-4000-8000-0000000e2e11', now(), 1300, 'card', true, 'done');
           insert into order_items (order_id, item_name, price_crc, qty) values ('0d000000-0000-4000-8000-0000000e2e11', 'Espresso', 1300, 1)`);
      const pg = await touchPos(browser);
      await goto(pg, '/pos');
      await pg.waitForSelector('.pbtn', { timeout: 15000 });
      await pg.click('#ordersBtn');
      await pg.locator('.orow', { hasText: 'Espresso' }).first().locator('button', { hasText: 'Void' }).click();
      await pg.fill('#vReason', 'prueba');
      await pg.selectOption('#vMgr', STAFF.ana);
      await pg.focus('#vPin');
      const pad = pg.locator('#vPin + .hg-pad');
      await until(async () => pad.isVisible(), 5000, 'PIN pad');
      assert.strictEqual(await pg.locator('#vPin').getAttribute('inputmode'), 'none', 'no phone keyboard on top of the pad');
      for (const d of PINS.ana) await pad.locator('button', { hasText: new RegExp('^' + d + '$') }).click();
      assert.strictEqual(await pg.locator('#vPin').inputValue(), PINS.ana);
      await pad.locator('button.ok').click();
      await until(() => sql(`select voided_at is not null from orders where id = '0d000000-0000-4000-8000-0000000e2e11'`) === 't', 8000, 'voided');
      assert.strictEqual(await pg.locator('#vPin').inputValue(), '', 'the PIN is cleared afterwards');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'the amount pad types into the register close fields',
    run: async ({ browser }) => {
      const pg = await touchPos(browser);
      await goto(pg, '/pos');
      await pg.waitForSelector('.pbtn', { timeout: 15000 });
      await pg.click('#dayBtn');
      await pg.waitForSelector('#rcCash', { state: 'visible', timeout: 5000 });
      await pg.focus('#rcCash');
      const pad = pg.locator('#rcCash + .hg-pad');
      await until(async () => pad.isVisible(), 5000, 'amount pad');
      await pad.locator('button', { hasText: /^5$/ }).click();
      await pad.locator('button', { hasText: /^000$/ }).click();
      await pad.locator('button', { hasText: /^0$/ }).click();
      assert.strictEqual(await pg.locator('#rcCash').inputValue(), '50000');
      await pad.locator('button', { hasText: '⌫' }).click();
      assert.strictEqual(await pg.locator('#rcCash').inputValue(), '5000');
    }
  },
  {
    name: 'a desktop with a keyboard never shows the pad',
    run: async ({ browser }) => {
      openRegister();
      const pg = await page(browser, { login: 'cafe', lang: 'en' });
      await goto(pg, '/pos');
      await pg.waitForSelector('.pbtn', { timeout: 15000 });
      await pg.click('#dayBtn');
      await pg.waitForSelector('#rcCash', { state: 'visible', timeout: 5000 });
      await pg.focus('#rcCash');
      await new Promise((r) => setTimeout(r, 300));
      assert.strictEqual(await pg.locator('#rcCash + .hg-pad').isVisible(), false);
    }
  },
  {
    name: 'staff screens start in Spanish on a device set to English; the public menu follows the device',
    run: async ({ browser }) => {
      openRegister();
      const context = await browser.newContext({ locale: 'en-US', timezoneId: 'America/Costa_Rica' });
      const pg = await page(browser, { context, login: 'cafe', lang: 'en' });
      await pg.addInitScript(() => { try { localStorage.removeItem('hg_lang'); } catch (e) {} });
      await goto(pg, '/pos');
      await pg.waitForSelector('.pbtn', { timeout: 15000 });
      await until(async () => (await pg.locator('#ordersBtn').textContent()).trim() === 'Pedidos', 5000, 'Spanish POS');
      await goto(pg, '/m');
      await until(async () => (await pg.evaluate(() => window.HG_LANG)) === 'en', 5000, 'menu in the visitor language');
    }
  }
];
