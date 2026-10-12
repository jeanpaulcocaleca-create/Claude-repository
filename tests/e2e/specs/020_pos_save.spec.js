/* The POS saves each sale once, with its lines, online or after being offline; old databases still work. */
'use strict';
const assert = require('assert');
const { until, sql, pos } = require('../lib');

async function ringFirstItem(pg, times, method) {
  const first = pg.locator('.pbtn').first();
  const name = (await first.locator('.nm').textContent()).trim();
  for (let i = 0; i < times; i++) await first.click();
  await pg.click(`[data-pay="${method || 'cash_crc'}"]`);
  if (await pg.locator('#numModal:not([hidden])').count()) await pg.click('#numNone');
  return name;
}

module.exports.tests = [
  {
    name: 'a sale is saved in one call with its product ids',
    run: async ({ browser }) => {
      const pg = await pos(browser);
      const name = await ringFirstItem(pg, 3, 'card');
      await until(() => sql(`select count(*) from orders where payment_method = 'card'`) === '1', 10000, 'sale saved');
      const mid = sql(`select i.menu_item_id = m.id from order_items i join menu_items m on lower(m.name) = lower(i.item_name) where i.item_name = '${name.replace(/'/g, "''")}'`);
      assert.strictEqual(mid, 't', 'line linked to its menu item');
      assert.strictEqual(sql(`select count(*) from orders where 'total_mismatch' = any(flags)`), '0');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'a sale rung without internet is saved once when the connection returns',
    run: async ({ browser, setOffline }) => {
      const pg = await pos(browser);
      setOffline(true);
      await ringFirstItem(pg, 2);
      await new Promise((r) => setTimeout(r, 1500));
      assert.strictEqual(sql(`select count(*) from orders`), '0', 'nothing reached the server while offline');
      const queued = await pg.evaluate(() => JSON.parse(localStorage.getItem('hg-pos-queue') || '[]').length);
      assert.strictEqual(queued, 1, 'the sale waits on the device');
      setOffline(false);
      await pg.evaluate(() => syncQueue());
      await until(() => sql(`select count(*) from orders`) === '1', 15000, 'sale uploaded');
      await pg.evaluate(() => syncQueue());
      await new Promise((r) => setTimeout(r, 800));
      assert.strictEqual(sql(`select count(*) from orders`), '1', 'saved exactly once');
      assert.strictEqual(sql(`select count(*) from order_items`), '1', 'one line');
      await until(async () => (await pg.evaluate(() => JSON.parse(localStorage.getItem('hg-pos-queue') || '[]').length)) === 0, 8000, 'queue emptied');
    }
  },
  {
    name: 'a database without the new function still gets the sale (two-step save)',
    run: async ({ browser }) => {
      sql(`drop function public.pos_record_sale(jsonb); notify pgrst, 'reload schema';`);
      await new Promise((r) => setTimeout(r, 600));
      const pg = await pos(browser);
      await ringFirstItem(pg, 1, 'sinpe');
      await until(() => sql(`select count(*) from orders o join order_items i on i.order_id = o.id where o.payment_method = 'sinpe'`) === '1', 10000, 'sale saved the old way');
      assert.deepStrictEqual(pg.errors, []);
    }
  }
];
