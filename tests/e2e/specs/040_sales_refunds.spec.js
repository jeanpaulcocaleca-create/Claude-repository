/* Sales report past the 1000-row server limit; a sale from a closed register day is refunded today (0006). */
'use strict';
const assert = require('assert');
const { page, goto, until, sql, pos, STAFF, PINS } = require('../lib');

const digits = (t) => String(t || '').replace(/\D/g, '');

module.exports.tests = [
  {
    name: 'the sales report counts every sale, not just the first 1000',
    run: async ({ browser }) => {
      sql(`insert into orders (id, created_at, total_crc, payment_method, paid, status)
           select gen_random_uuid(), now() - (n || ' seconds')::interval, 1000, 'card', true, 'done' from generate_series(1, 2300) n`);
      const pg = await page(browser, { login: 'owner', aal: 'aal2', lang: 'en' });
      await goto(pg, '/sales');
      await until(async () => digits(await pg.locator('#kRev').textContent()) === '2300000', 20000, 'revenue of all 2300 sales');
      assert.strictEqual(await pg.locator('#kOrders').textContent(), '2300');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'voiding a sale after the register closed offers a refund dated today',
    run: async ({ browser }) => {
      const pg = await pos(browser);
      sql(`insert into orders (id, created_at, total_crc, payment_method, paid, status)
           values ('0d000000-0000-4000-8000-0000000e2e40', now() - interval '1 minute', 2500, 'card', true, 'done');
           insert into order_items (order_id, item_name, price_crc, qty) values ('0d000000-0000-4000-8000-0000000e2e40', 'Latte', 2500, 1);
           update register_days set closed_at = now(), closed_by_name = 'Ana' where business_date = cr_today()`);
      await pg.click('#ordersBtn');
      const row = pg.locator('.orow', { hasText: 'Latte' }).first();
      await row.locator('button', { hasText: 'Void' }).click();
      await pg.fill('#vReason', 'cliente devolvió');
      await pg.selectOption('#vMgr', STAFF.ana);
      await pg.fill('#vPin', PINS.ana);
      await pg.click('#vGo');
      await until(async () => !(await pg.locator('#vRefundBox').isHidden()), 8000, 'refund option');
      assert.match(await pg.locator('#voidErr').textContent(), /already closed/);
      assert.strictEqual(await pg.locator('#vMethod').inputValue(), 'card', 'the same way it came in, by default');
      await pg.fill('#vPin', PINS.ana);
      await pg.click('#vGo');
      const refund = await until(() => sql(`select total_crc || '|' || payment_method || '|' || (business_date = cr_today())
                                              from orders where refund_of = '0d000000-0000-4000-8000-0000000e2e40'`), 8000, 'refund saved');
      assert.strictEqual(refund, '-2500|card|true');
      assert.strictEqual(sql(`select voided_at is null and refunded_at is not null from orders where id = '0d000000-0000-4000-8000-0000000e2e40'`), 't');
      await until(async () => (await pg.locator('.orow', { hasText: 'Refund' }).count()) > 0, 8000, 'refund shown in the list');
      assert.deepStrictEqual(pg.errors, []);
    }
  }
];
