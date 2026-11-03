/* Menu Manager with price_mode 'exclusive' (migration 0009): the editor and the new-item prompt ask for the price
   before IVA, the list shows it the same way, and what is stored (price_crc, always with IVA) does not drift. */
'use strict';
const assert = require('assert');
const { page, goto, until, sql } = require('../lib');

/* the owner's policy of showing prices before IVA, confirmed and switched on (see 130_tax.spec.js) */
function exclusiveMode() {
  sql(`insert into compliance_confirmations (key, confirmed_by, reference) values ('price_display_rules', 'prueba', 'prueba');
       insert into settings (key, value) values ('price_mode', '"exclusive"')`);
}

async function admin(browser) {
  const pg = await page(browser, { login: 'owner', aal: 'aal2', lang: 'en' });
  await goto(pg, '/admin');
  await until(async () => (await pg.locator('.item').count()) > 0, 15000, 'menu loaded');
  return pg;
}
function itemRow(pg, name) { return pg.locator('.item', { has: pg.locator('text=/^' + name + '$/') }).first(); }
async function toastShown(pg, text) {
  await until(async () => (await pg.locator('#toast.show').textContent()) === text, 8000, 'toast "' + text + '"');
}
/* answers the two prompts of "+ Add item" in order and keeps their messages */
function answerPrompts(pg, answers) {
  const seen = [];
  pg.onDialog = async (d) => { seen.push(d.message()); await d.accept(answers.shift()); };
  return seen;
}

module.exports.tests = [
  {
    name: 'exclusive mode: saving an item without touching the price keeps price_crc (no rounding drift)',
    run: async ({ browser }) => {
      exclusiveMode();
      const pg = await admin(browser);
      // Espresso 1300 with IVA → 1150 before IVA, shown like the POS buttons
      assert.match(await itemRow(pg, 'Espresso').locator('.pr').textContent(), /^₡1\s?150 \+ IVA$/);
      await itemRow(pg, 'Espresso').locator('button', { hasText: 'Edit' }).click();
      const box = itemRow(pg, 'Espresso').locator('.editbox');
      assert.strictEqual(await box.locator('input[name=price]').inputValue(), '1150');
      assert.match(await box.locator('[data-final]').textContent(), /^= ₡1\s?300 with IVA$/, 'the final price is shown');
      await box.locator('button[type=submit]').click();
      await toastShown(pg, 'Saved');
      await new Promise((r) => setTimeout(r, 500));
      assert.strictEqual(sql(`select price_crc from menu_items where name = 'Espresso'`), '1300', 'untouched price stays 1300');
      // save again: still 1300 (the old code went 1300 → 1150 → 1299.5 → 1299…)
      await itemRow(pg, 'Espresso').locator('button', { hasText: 'Edit' }).click();
      await itemRow(pg, 'Espresso').locator('.editbox button[type=submit]').click();
      await toastShown(pg, 'Saved');
      await new Promise((r) => setTimeout(r, 500));
      assert.strictEqual(sql(`select price_crc from menu_items where name = 'Espresso'`), '1300');
      assert.match(await itemRow(pg, 'Espresso').locator('.pr').textContent(), /^₡1\s?150 \+ IVA$/);
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'exclusive mode: a changed before-IVA price is stored with IVA (2000 → 2260) and previewed while typing',
    run: async ({ browser }) => {
      exclusiveMode();
      const pg = await admin(browser);
      await itemRow(pg, 'Espresso').locator('button', { hasText: 'Edit' }).click();
      const box = itemRow(pg, 'Espresso').locator('.editbox');
      await box.locator('input[name=price]').fill('2000');
      assert.match(await box.locator('[data-final]').textContent(), /^= ₡2\s?260 with IVA$/, 'the preview follows the typing');
      await box.locator('button[type=submit]').click();
      await until(() => sql(`select price_crc from menu_items where name = 'Espresso'`) === '2260', 8000, 'stored with IVA');
      await until(async () => /2\s?000 \+ IVA/.test(await itemRow(pg, 'Espresso').locator('.pr').textContent()), 8000, 'list shows 2 000 + IVA');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'exclusive mode: "+ Add item" asks for the price before IVA and stores it with IVA 13% (1000 → 1130)',
    run: async ({ browser }) => {
      exclusiveMode();
      const pg = await admin(browser);
      const seen = answerPrompts(pg, ['Prueba sin IVA', '1000']);
      await pg.locator('button.addrow', { hasText: 'Add item to Coffee' }).click();
      await until(() => sql(`select price_crc from menu_items where name = 'Prueba sin IVA'`) === '1130', 8000, 'new item stored with IVA');
      assert.deepStrictEqual(seen, ['Name of the new item in Coffee:', 'Price before IVA (numbers only):']);
      assert.strictEqual(sql(`select tax_code from menu_items where name = 'Prueba sin IVA'`), 'IVA13');
      await until(async () => /^₡1\s?000 \+ IVA$/.test(await itemRow(pg, 'Prueba sin IVA').locator('.pr').textContent()), 8000, 'listed before IVA');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'inclusive mode (the default): "+ Add item" stores the typed price as it is (1000)',
    run: async ({ browser }) => {
      const pg = await admin(browser);
      assert.match(await itemRow(pg, 'Espresso').locator('.pr').textContent(), /^₡1\s?300$/, 'the list shows the final price');
      const seen = answerPrompts(pg, ['Prueba con IVA', '1000']);
      await pg.locator('button.addrow', { hasText: 'Add item to Coffee' }).click();
      await until(() => sql(`select price_crc from menu_items where name = 'Prueba con IVA'`) === '1000', 8000, 'new item stored as typed');
      assert.deepStrictEqual(seen, ['Name of the new item in Coffee:', 'Price in colones (numbers only):']);
      await until(async () => /^₡1\s?000$/.test(await itemRow(pg, 'Prueba con IVA').locator('.pr').textContent()), 8000, 'listed with IVA, no suffix');
      // the editor has no before-IVA field or preview in this mode
      await itemRow(pg, 'Prueba con IVA').locator('button', { hasText: 'Edit' }).click();
      const box = itemRow(pg, 'Prueba con IVA').locator('.editbox');
      assert.strictEqual(await box.locator('input[name=price]').inputValue(), '1000');
      assert.strictEqual(await box.locator('[data-final]').count(), 0);
      assert.deepStrictEqual(pg.errors, []);
    }
  }
];
