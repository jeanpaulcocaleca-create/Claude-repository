/* The cash window (migration 0010): notes received, change, dollars at the day's rate, the drawer in two currencies. */
'use strict';
const assert = require('assert');
const { until, sql, pos, openRegister, STAFF, PINS } = require('../lib');

const n = (t) => String(t || '').replace(/[^\d.]/g, '');
async function ringLatte(pg) {
  await pg.evaluate(() => { const b = [...document.querySelectorAll('.pbtn')].find((x) => /^Latte/.test(x.textContent.trim())); b.click(); });
}

module.exports.tests = [
  {
    name: 'a ₡5 000 note for a ₡2 200 latte: ₡2 800 change, kept with the sale',
    run: async ({ browser }) => {
      const pg = await pos(browser);
      await ringLatte(pg);
      await pg.click('[data-pay="cash_crc"]');
      await pg.waitForSelector('#cashModal:not([hidden])');
      assert.strictEqual(await pg.isDisabled('#cashGo'), true, 'nothing received yet');
      await pg.locator('#denCrc button', { hasText: /^₡5\s000$/ }).click();
      assert.strictEqual(n(await pg.locator('#cashChange').textContent()), '2800');
      await pg.click('#cashGo');
      if (await pg.locator('#numModal:not([hidden])').count()) await pg.click('#numNone');
      await until(() => sql(`select o.payment_method || '|' || t.crc_in || '|' || t.change_crc || '|' || (array_length(t.flags, 1) is null)
                               from orders o join cash_tenders t on t.order_id = o.id`) === 'cash_crc|5000|2800|true', 10000, 'sale with its tender');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'paid with a $10 bill at the day\'s rate: change in colones, the drawer expects the dollars',
    run: async ({ browser }) => {
      openRegister();
      sql(`insert into fx_rates (day, buy, sell, source) values (cr_today(), 500, 510, 'hacienda');
           update register_days set float_usd = 20 where business_date = cr_today()`);
      const pg = await pos(browser);
      await until(async () => !(await pg.locator('#usdRow').isHidden()) || (await ringLatte(pg), false), 8000, 'dollar total shown');
      assert.strictEqual(await pg.locator('#usdAmt').textContent(), '≈ $4.40');
      await pg.click('[data-pay="cash_crc"]');
      await pg.waitForSelector('#cashModal:not([hidden])');
      await pg.locator('#denUsd button', { hasText: /^\$10$/ }).click();
      assert.strictEqual(n(await pg.locator('#cashChange').textContent()), '2800', '5 000 − 2 200');
      await pg.click('#cashGo');
      if (await pg.locator('#numModal:not([hidden])').count()) await pg.click('#numNone');
      await until(() => sql(`select o.payment_method || '|' || t.usd_in || '|' || t.fx_rate || '|' || t.change_crc
                               from orders o join cash_tenders t on t.order_id = o.id`) === 'cash_usd|10.00|500.00|2800', 10000, 'dollar sale saved');
      // close the day: ₡50 000 float − ₡2 800 change = ₡47 200 ; $20 + $10 = $30
      await pg.click('#dayBtn');
      await pg.waitForSelector('#rcCash', { state: 'visible' });
      await pg.fill('#rcTerminal', '0');
      await pg.fill('#rcCash', '47200');
      await pg.fill('#rcCashUsd', '30');
      await until(async () => /Expected \$30\.00 · 0\.00/.test(await pg.locator('#rcUsdDiff').textContent()), 8000, 'dollars match on screen');
      await pg.selectOption('#rcStaff', STAFF.ana);
      await pg.fill('#rcPin', PINS.ana);
      await pg.click('#regCloseForm button[type=submit]');
      await until(() => sql(`select cash_diff_crc || '|' || cash_diff_usd from register_days where business_date = cr_today()`) === '0|0.00', 10000, 'closed, both currencies match');
      assert.deepStrictEqual(pg.errors, []);
    }
  }
,
  {
    name: 'a room order paid in cash at the window keeps its change',
    run: async ({ browser }) => {
      sql(`insert into orders (id, created_at, total_crc, payment_method, status, paid, source, needs_kitchen, room_id)
             select '0d000000-0000-4000-8000-0000000e2e14', now(), 3000, 'pending', 'ready', false, 'room', false, id from rooms order by number limit 1;
           insert into order_items (order_id, item_name, price_crc, qty) values ('0d000000-0000-4000-8000-0000000e2e14', 'Mocha', 1500, 2)`);
      const pg = await pos(browser);
      const paid = pg.locator('button', { hasText: 'Paid & picked up' }).first();
      await until(async () => (await paid.count()) > 0, 10000, 'room order on the live bar');
      await paid.click();
      await pg.click('[data-rpay="cash_crc"]');
      await pg.waitForSelector('#cashModal:not([hidden])');
      await pg.locator('#denCrc button', { hasText: /^₡5\s000$/ }).click();
      await pg.click('#cashGo');
      await until(() => sql(`select o.paid || '|' || t.crc_in || '|' || t.change_crc from orders o join cash_tenders t on t.order_id = o.id
                               where o.id = '0d000000-0000-4000-8000-0000000e2e14'`) === 'true|5000|2000', 10000, 'paid with its tender');
      assert.deepStrictEqual(pg.errors, []);
    }
  }
];
