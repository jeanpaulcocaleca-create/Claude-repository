/* Reports for the accountant and the owner (migration 0017): the period's IVA, inventory at average cost, profit by product. */
'use strict';
const assert = require('assert');
const { page, goto, until, sql } = require('../lib');

function seed() {
  sql(`update menu_items set price_crc = 2260 where name = 'Latte';
       insert into stock_items (id, name, category, unit, pack_qty, cost_per_pack, on_hand) values ('5a000000-0000-4000-8000-0000000e2e91', 'Leche', 'dairy', 'ml', 1000, 1000, 10000);
       delete from recipes where menu_item_id = (select id from menu_items where name = 'Latte' limit 1);
       insert into recipes (menu_item_id, stock_item_id, qty) select id, '5a000000-0000-4000-8000-0000000e2e91', 200 from menu_items where name = 'Latte' limit 1;
       insert into orders (id, created_at, total_crc, payment_method, paid, status) values ('0d000000-0000-4000-8000-0000000e2e91', now(), 4520, 'card', true, 'done');
       insert into order_items (order_id, item_name, price_crc, qty) values ('0d000000-0000-4000-8000-0000000e2e91', 'Latte', 2260, 2);
       insert into expenses (id, date, description, account, amount_crc, iva_crc, paid_from, vendor_name, invoice_no, created_by)
         values ('7e000000-0000-4000-8000-0000000e2e91', cr_today(), 'Jabón', '6204', 1130, 130, 'cash', 'Súper', 'E-9', 'prueba')`);
}
async function reports(browser, lang) {
  const pg = await page(browser, { login: 'accountant', lang: lang || 'en' });
  await goto(pg, '/accounting');
  await pg.waitForSelector('#appView:not([hidden])', { timeout: 15000 });
  await pg.click('#tabs [data-view=reports]');
  return pg;
}
const text = async (pg) => (await pg.locator('#rOut').innerText()).replace(/\s+/g, ' ');

module.exports.tests = [
  {
    name: 'the IVA of the period: sales IVA by rate, creditable IVA with its documents, the net; downloads as CSV',
    run: async ({ browser }) => {
      seed();
      const pg = await reports(browser);
      await pg.selectOption('#rKind', 'iva');
      await until(async () => /Total IVA on sales/.test(await text(pg)), 8000, 'IVA report');
      const t = await text(pg);
      assert.match(t, /IVA13 · 13 %/);
      assert.match(t, /Total IVA on sales ₡520/);
      assert.match(t, /Total creditable IVA ₡130/);
      assert.match(t, /IVA to pay ₡390/);
      assert.match(t, /Súper E-9 ₡1 000 ₡130/, 'the purchase document listed');
      const [dl] = await Promise.all([pg.waitForEvent('download'), pg.click('#rCsv')]);
      assert.match(dl.suggestedFilename(), /^iva-periodo-\d{4}-\d\d-\d\d\.csv$/);
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'inventory at average cost against the books, and profit by product, in Spanish',
    run: async ({ browser }) => {
      seed();
      const pg = await reports(browser, 'es');
      await pg.selectOption('#rKind', 'inv');
      await until(async () => /Inventario en los libros/i.test(await text(pg)), 8000, 'valuation in Spanish');
      assert.match(await text(pg), /Leche 9 600 ml ₡1 ₡9 600/, '10 000 ml − 2 × 200 ml at ₡1');
      assert.strictEqual(await pg.locator('#rTo').isDisabled(), true, 'the valuation is as of now');
      await pg.selectOption('#rKind', 'pp');
      await until(async () => /Costo de la receta/i.test(await text(pg)), 8000, 'profit by product in Spanish');
      const t = await text(pg);
      assert.match(t, /Latte 2 ₡4 000 ₡400 ₡3 600 10 %/, 'sold net of IVA, cost, margin, food cost');
      assert.match(t, /₡1 800 · 90 %/, 'margin per unit at today\'s price');
      assert.match(t, /productos del menú todavía no tienen receta/, 'products without a recipe are counted');
      assert.doesNotMatch(t, /Espresso/, 'unsold products without a recipe are left out of the table');
      assert.deepStrictEqual(pg.errors, []);
    }
  }
];
