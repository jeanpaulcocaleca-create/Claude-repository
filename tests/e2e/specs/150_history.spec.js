/* Earlier sales (migration 0011): search, reprint marked COPIA, refund of a closed day's sale. */
'use strict';
const assert = require('assert');
const { until, sql, pos, STAFF, PINS } = require('../lib');

module.exports.tests = [
  {
    name: 'find today\'s sale by item and reprint it as a copy with its receipt number and change',
    run: async ({ browser }) => {
      const pg = await pos(browser);
      sql(`insert into orders (id, created_at, total_crc, payment_method, paid, status) values ('0d000000-0000-4000-8000-0000000e2e50', now(), 2200, 'cash_crc', true, 'done');
           insert into order_items (order_id, item_name, price_crc, qty) values ('0d000000-0000-4000-8000-0000000e2e50', 'Latte', 2200, 1);
           insert into cash_tenders (order_id, crc_in, change_crc) values ('0d000000-0000-4000-8000-0000000e2e50', 5000, 2800)`);
      const no = sql(`select receipt_no from orders where id = '0d000000-0000-4000-8000-0000000e2e50'`);
      await pg.click('#ordersBtn');
      await pg.click('#histBtn');
      await pg.fill('#hText', 'latte');
      await pg.click('#hGo');
      const row = pg.locator('#hList .hrow').first();
      await until(async () => /Nº/.test(await row.textContent()), 8000, 'found');
      await row.locator('button', { hasText: 'Reprint' }).click();
      const html = await until(async () => pg.evaluate(() => window.__printedHTML || ''), 5000, 'printed');
      assert.match(html, /COPIA · COPY/);
      assert.match(html, new RegExp('Receipt Nº ' + no));
      assert.match(html, /Vuelto · Change<\/span><span>₡2 800/);
      await until(() => sql(`select count(*) from audit_log where action = 'receipt_reprint'`) === '1', 5000, 'reprint logged');
      // by receipt number
      await pg.fill('#hText', no);
      await pg.click('#hGo');
      await until(async () => (await pg.locator('#hList .hrow').count()) === 1, 5000, 'one by number');
    }
  },
  {
    name: 'yesterday\'s sale (register closed) is refunded today from the search, after a manager opens the history',
    run: async ({ browser }) => {
      sql(`insert into register_days (business_date, opened_by_name, float_crc, closed_at, closed_by_name) values (cr_today() - 1, 'Ana', 50000, now() - interval '10 hours', 'Ana');
           insert into orders (id, created_at, total_crc, payment_method, paid, status) values ('0d000000-0000-4000-8000-0000000e2e51', cr_day_start(cr_today() - 1) + interval '10 hours', 2500, 'card', true, 'done');
           insert into order_items (order_id, item_name, price_crc, qty) values ('0d000000-0000-4000-8000-0000000e2e51', 'Mocha', 2500, 1)`);
      const pg = await pos(browser);
      await pg.click('#ordersBtn');
      await pg.click('#histBtn');
      const y = sql(`select (cr_today() - 1)::text`);
      await pg.fill('#hDay', y);
      await pg.click('#hGo');
      await until(async () => pg.locator('#hUnlock').isVisible(), 8000, 'asks for a manager');
      await pg.click('#hUnlock');
      await pg.waitForSelector('#hgaPin', { timeout: 5000 });
      await pg.selectOption('#hgaWho', STAFF.ana);
      await pg.fill('#hgaPin', PINS.ana);
      await pg.click('.hga-go');
      const row = pg.locator('#hList .hrow', { hasText: 'Mocha' }).first();
      await until(async () => (await row.count()) > 0, 8000, 'yesterday listed');
      assert.strictEqual(await row.locator('button', { hasText: /^Void$/ }).count(), 0, 'no void for a closed day');
      await row.locator('button', { hasText: 'Refund' }).click();
      await pg.fill('#hReason', 'cliente insatisfecho');
      await pg.selectOption('#hMgr', STAFF.ana);
      await pg.fill('#hPin', PINS.ana);
      await pg.click('#hBoxGo');
      await until(() => sql(`select total_crc || '|' || payment_method || '|' || (business_date = cr_today()) from orders where refund_of = '0d000000-0000-4000-8000-0000000e2e51'`) === '-2500|card|true', 8000, 'refunded today');
      assert.deepStrictEqual(pg.errors, []);
    }
  }
];
