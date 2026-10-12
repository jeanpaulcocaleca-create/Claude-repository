/* Insights (migration 0023): today as an estimate or final, months, busy hours, products, stock to order, suppliers. */
'use strict';
const assert = require('assert');
const { page, goto, until, sql, openRegister } = require('../lib');

function seed() {
  openRegister();
  sql(`update menu_items set price_crc = 2260 where name = 'Latte';
       insert into orders (id, created_at, total_crc, payment_method, paid, status)
         select ('0d000000-0000-4000-8000-0000000e24' || lpad(g::text, 2, '0'))::uuid, now() - make_interval(days => g), 4520, 'card', true, 'done' from generate_series(0, 9) g;
       insert into order_items (order_id, item_name, price_crc, qty)
         select ('0d000000-0000-4000-8000-0000000e24' || lpad(g::text, 2, '0'))::uuid, 'Latte', 2260, 2 from generate_series(0, 9) g;
       insert into vendors (id, name, lead_days) values ('5b000000-0000-4000-8000-0000000e2e24', 'Lácteos Monteverde', 2);
       insert into stock_items (id, name, unit, pack_qty, pack_label, cost_per_pack, on_hand, par_level, vendor_id)
         values ('5a000000-0000-4000-8000-0000000e2e24', 'Leche', 'ml', 1000, 'caja 1 L', 1000, 2000, 8000, '5b000000-0000-4000-8000-0000000e2e24');
       insert into stock_moves (item_id, kind, qty, at) select '5a000000-0000-4000-8000-0000000e2e24', 'sale', -1000, now() - make_interval(days => g) from generate_series(1, 7) g`);
}
async function insights(browser, lang) {
  const pg = await page(browser, { login: 'owner', aal: 'aal2', lang: lang || 'en' });
  await goto(pg, '/insights');
  await pg.waitForSelector('#content:not([hidden])', { timeout: 15000 });
  return pg;
}

module.exports.tests = [
  {
    name: 'the owner sees today as an estimate, the months, busy hours, products, what to order and the suppliers',
    run: async ({ browser }) => {
      seed();
      const pg = await insights(browser);
      await until(async () => (await pg.locator('#tState').textContent()) === 'Estimate', 8000, 'an estimate while the register is open');
      assert.match(await pg.locator('#tNet').textContent(), /^₡4\s000$/, 'today without IVA');
      assert.match(await pg.locator('#tLwSub').textContent(), /up to this time/);
      await until(async () => (await pg.locator('#mSales path.bar').count()) === 12, 8000, 'twelve months of bars');
      assert.match(await pg.locator('#mLegend').innerText(), /Food cost[\s\S]*Labor[\s\S]*Prime cost/, 'the owner sees labor and prime cost');
      await until(async () => (await pg.locator('#heat .c').count()) >= 7 * 12, 8000, 'the week by hour');
      await until(async () => /Latte(\s+No recipe)?\s+20\s+₡40\s000/.test(await pg.locator('#pTable').innerText()), 8000, 'products: 20 lattes sold');
      await until(async () => /Leche\s+.*Order now/.test((await pg.locator('#sTable').innerText()).replace(/\s+/g, ' ')), 8000, 'milk: order now');
      assert.match(await pg.locator('#sTable').innerText(), /caja 1 L/, 'in whole packs');
      const [dl] = await Promise.all([pg.waitForEvent('download'), pg.click('#mCsv')]);
      assert.strictEqual(dl.suggestedFilename(), 'tendencias.csv');
      await pg.click('#rangeTabs [data-days="91"]');
      await until(async () => /Latte(\s+No recipe)?\s+20/.test(await pg.locator('#pTable').innerText()), 8000, 'the longer range');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'in Spanish; and Home shows today\'s revenue as an estimate against last week',
    run: async ({ browser }) => {
      seed();
      const pg = await insights(browser, 'es');
      await until(async () => (await pg.locator('#tState').textContent()) === 'Estimado', 8000, 'Estimado');
      await until(async () => /Pedir ya/.test(await pg.locator('#sTable').innerText()), 8000, 'Pedir ya');
      assert.match(await pg.locator('#content').innerText(), /Mes a mes[\s\S]*Cuándo compra la gente/i);
      const home = await page(browser, { login: 'owner', aal: 'aal2', lang: 'en' });
      await goto(home, '/home');
      await until(async () => /^Estimate · without IVA ₡4\s000 · ▲ 0 % vs last week$/.test(await home.locator('#kRevSub').textContent()), 10000, 'estimate on Home');
      assert.strictEqual(await home.locator('a.tile[href="insights.html"]').count(), 1, 'Insights tile');
      assert.deepStrictEqual(pg.errors, []); assert.deepStrictEqual(home.errors, []);
    }
  }
];
