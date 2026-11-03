/* Smoke tests: the real pages run against the local test database and never reach Supabase. */
'use strict';
const assert = require('assert');
const { page, goto, until, sql, pos, cashExact } = require('../lib');

module.exports.tests = [
  {
    name: 'the public QR menu loads from the test database',
    run: async ({ browser }) => {
      const pg = await page(browser, { lang: 'en' });
      await goto(pg, '/m');
      await until(async () => (await pg.locator('text=Espresso').count()) > 0, 10000, 'menu items');
      assert.strictEqual(pg.supabaseHits, 0, 'the real Supabase was contacted');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'the POS records a cash sale with its lines',
    run: async ({ browser }) => {
      const pg = await pos(browser);
      const first = pg.locator('.pbtn').first();
      const name = (await first.locator('.nm').textContent()).trim();
      await first.click(); await first.click();
      await pg.click('[data-pay="cash_crc"]');
      await cashExact(pg);
      if (await pg.locator('#numModal:not([hidden])').count()) await pg.click('#numNone');
      const row = await until(() => sql(`select o.total_crc || '|' || i.qty || '|' || i.item_name from orders o join order_items i on i.order_id = o.id where o.payment_method = 'cash_crc' limit 1`), 10000, 'sale saved');
      const [total, qty, item] = row.split('|');
      const price = Number(sql(`select price_crc from menu_items where name = '${name.replace(/'/g, "''")}' limit 1`));
      assert.strictEqual(Number(total), 2 * price, 'total is 2 × price');
      assert.strictEqual(qty, '2'); assert.strictEqual(item, name);
      assert.strictEqual(pg.supabaseHits, 0);
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'staff pages refuse to run on an unknown address',
    run: async ({ browser }) => {
      const pg = await page(browser, { login: 'cafe', lang: 'en' });
      await pg.goto('http://127.0.0.2:' + (process.env.E2E_SITE_PORT || 8090) + '/pos', { waitUntil: 'domcontentloaded' });
      await until(async () => (await pg.locator('text=no está autorizada').count()) > 0, 8000, 'blocked notice');
      assert.strictEqual(pg.supabaseHits, 0);
    }
  }
];
