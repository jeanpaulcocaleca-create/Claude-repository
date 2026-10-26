/* IVA per product (migration 0009): the ticket and the receipt show what the server stores. */
'use strict';
const assert = require('assert');
const { page, goto, until, sql, pos } = require('../lib');

async function tapItem(pg, name) {
  const b = pg.locator('.pbtn', { hasText: name }).first();
  if (!(await b.count())) {
    for (const tab of await pg.locator('#rail button').all()) { await tab.click(); if (await pg.locator('.pbtn', { hasText: name }).count()) break; }
  }
  await pg.locator('.pbtn', { hasText: name }).first().click();
}

module.exports.tests = [
  {
    name: 'a ticket with two rates shows the IVA of each product, equal to what the server stores',
    run: async ({ browser }) => {
      sql(`insert into tax_rates (code, name, rate, confirmed_by, reference) values ('IVA4', 'Reducida 4 %', 0.04, 'prueba', 'prueba');
           update menu_items set tax_code = 'IVA4' where name = 'Iced Latte'`);
      const pg = await pos(browser);
      await tapItem(pg, 'Latte'); await tapItem(pg, 'Iced Latte');
      await until(async () => (await pg.locator('#ivaLbl').textContent()) === 'Includes IVA 13% · 4%', 8000, 'two rates');
      const shown = Number((await pg.locator('#ivaAmt').textContent()).replace(/\D/g, ''));
      await pg.click('[data-pay="card"]');
      if (await pg.locator('#numModal:not([hidden])').count()) await pg.click('#numNone');
      await until(() => sql(`select count(*) from orders where tax_crc is not null`) === '1', 10000, 'sale saved');
      assert.strictEqual(Number(sql(`select tax_crc from orders`)), shown, 'the screen and the server agree');
      // 2200 × 13/113 = 253 ; 2200 × 4/104 = 85
      assert.strictEqual(shown, 253 + 85);
      await pg.click('#printBtn');
      const html = await pg.evaluate(() => window.__printedHTML || '');
      assert.match(html, /IVA 13%[^<]*<\/span><span>₡253/);
      assert.match(html, /IVA 4%[^<]*<\/span><span>₡85/);
    }
  },
  {
    name: 'tax-exclusive display (once confirmed): buttons before IVA, the same amount charged',
    run: async ({ browser }) => {
      sql(`insert into compliance_confirmations (key, confirmed_by, reference) values ('price_display_rules', 'prueba', 'prueba');
           insert into settings (key, value) values ('price_mode', '"exclusive"')`);
      const pg = await pos(browser);
      await until(async () => /\+ IVA/.test(await pg.locator('.pbtn', { hasText: 'Espresso' }).first().textContent()), 8000, 'prices before IVA');
      // Espresso 1300 with IVA → 1150 before IVA
      assert.match(await pg.locator('.pbtn', { hasText: 'Espresso' }).first().textContent(), /1\s?150 \+ IVA/);
      await tapItem(pg, 'Espresso');
      assert.strictEqual((await pg.locator('#netAmt').textContent()).replace(/\D/g, ''), '1150');
      assert.strictEqual((await pg.locator('#ivaAmt').textContent()).replace(/\D/g, ''), '150');
      assert.strictEqual((await pg.locator('#totalAmt').textContent()).replace(/\D/g, ''), '1300');
      await pg.click('[data-pay="card"]');
      if (await pg.locator('#numModal:not([hidden])').count()) await pg.click('#numNone');
      await until(() => sql(`select total_crc || '|' || tax_crc from orders`) === '1300|150', 10000, 'charged the final price');
    }
  }
,
  {
    name: 'the owner sets an item\'s IVA rate and CABYS code in the Menu Manager',
    run: async ({ browser }) => {
      sql(`insert into tax_rates (code, name, rate, confirmed_by, reference) values ('IVA4', 'Reducida 4 %', 0.04, 'prueba', 'prueba')`);
      const pg = await page(browser, { login: 'owner', aal: 'aal2', lang: 'en' });
      await goto(pg, '/admin');
      const row = pg.locator('.item', { has: pg.locator('text=/^Mocha$/') }).first();
      await until(async () => (await row.count()) > 0, 15000, 'menu loaded');
      await row.locator('button', { hasText: 'Edit' }).click();
      await row.locator('select[name=tax_code]').selectOption('IVA4');
      await row.locator('input[name=cabys]').fill('123');
      await row.locator('button[type=submit]').click();
      await new Promise((r) => setTimeout(r, 500));
      assert.strictEqual(sql(`select tax_code from menu_items where name = 'Mocha'`), 'IVA13', 'a bad CABYS is not saved');
      await row.locator('input[name=cabys]').fill('2399999009900');
      await row.locator('button[type=submit]').click();
      await until(() => sql(`select tax_code || '|' || cabys from menu_items where name = 'Mocha'`) === 'IVA4|2399999009900', 8000, 'saved');
      assert.deepStrictEqual(pg.errors, []);
    }
  }
];
