/* Inventory page against migration 0005: opening stock, repeat-safe moves, protected history. */
'use strict';
const assert = require('assert');
const { page, goto, until, sql } = require('../lib');

async function inventory(browser) {
  const pg = await page(browser, { login: 'owner', aal: 'aal2', lang: 'en' });
  await goto(pg, '/inventory');
  await until(async () => (await pg.locator('#kItems').textContent()) !== '–', 15000, 'inventory loaded');
  await pg.click('#tabs [data-view=stock]');
  await pg.waitForSelector('#addItemBtn', { state: 'visible', timeout: 5000 });
  return pg;
}

module.exports.tests = [
  {
    name: 'a new item with starting stock is recorded as an opening adjustment',
    run: async ({ browser }) => {
      const pg = await inventory(browser);
      await pg.click('#addItemBtn');
      await pg.fill('#itName', 'Leche entera');
      await pg.fill('#itPackQty', '1000');
      await pg.fill('#itCost', '1100');
      await pg.fill('#itStart', '3000');
      await pg.click('#itemForm button[type=submit]');
      const row = await until(() => sql(`select m.kind || '|' || m.qty || '|' || i.on_hand || '|' || i.avg_cost || '|' || (m.request_id is not null)
                                           from stock_moves m join stock_items i on i.id = m.item_id where i.name = 'Leche entera'`), 10000, 'opening move');
      assert.strictEqual(row, 'adjust|3000|3000|1.1000|true');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'saving the same waste twice (double tap, retry) takes stock out once',
    run: async ({ browser }) => {
      sql(`insert into stock_items (id, name, unit, pack_qty, cost_per_pack) values ('5a000000-0000-4000-8000-0000000e2e01', 'Vasos 12oz', 'unit', 50, 2500);
           insert into stock_moves (item_id, kind, qty, note) values ('5a000000-0000-4000-8000-0000000e2e01', 'adjust', 200, 'test')`);
      const pg = await inventory(browser);
      const row = pg.locator('tr', { hasText: 'Vasos 12oz' }).first();
      await row.locator('button', { hasText: 'Waste' }).click();
      await pg.fill('#mvQty', '5');
      // two saves of the same form, as a double tap or a retry after a timeout would send
      await pg.evaluate(() => { const f = document.getElementById('moveForm'); f.requestSubmit(); f.requestSubmit(); });
      await until(() => sql(`select count(*) from stock_moves where item_id = '5a000000-0000-4000-8000-0000000e2e01' and kind = 'waste'`) === '1', 8000, 'waste saved');
      await new Promise((r) => setTimeout(r, 800));
      assert.strictEqual(sql(`select count(*) from stock_moves where item_id = '5a000000-0000-4000-8000-0000000e2e01' and kind = 'waste'`), '1');
      assert.strictEqual(sql(`select on_hand from stock_items where id = '5a000000-0000-4000-8000-0000000e2e01'`), '195');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'an item with history cannot be deleted; the page explains why',
    run: async ({ browser }) => {
      sql(`insert into stock_items (id, name, unit) values ('5a000000-0000-4000-8000-0000000e2e02', 'Azúcar', 'g');
           insert into stock_moves (item_id, kind, qty, note) values ('5a000000-0000-4000-8000-0000000e2e02', 'adjust', 500, 'test')`);
      const pg = await inventory(browser);
      await pg.locator('tr', { hasText: 'Azúcar' }).first().locator('button', { hasText: 'Edit' }).click();
      await pg.click('#itDelete');
      await until(async () => /has history/.test(await pg.locator('#itErr').textContent()), 8000, 'history message');
      assert.strictEqual(sql(`select count(*) from stock_items where id = '5a000000-0000-4000-8000-0000000e2e02'`), '1');
      assert.strictEqual(sql(`select count(*) from stock_moves where item_id = '5a000000-0000-4000-8000-0000000e2e02'`), '1');
    }
  }
];
