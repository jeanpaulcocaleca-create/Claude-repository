/* Electronic documents (migration 0018): off by default; "record only" lists what would be sent, nothing is sent. */
'use strict';
const assert = require('assert');
const { page, goto, until, sql } = require('../lib');

async function docs(browser, lang) {
  const pg = await page(browser, { login: 'accountant', aal: 'aal2', lang: lang || 'en' });
  await goto(pg, '/accounting');
  await pg.waitForSelector('#appView:not([hidden])', { timeout: 15000 });
  await pg.click('#tabs [data-view=einvoice]');
  return pg;
}

module.exports.tests = [
  {
    name: 'off by default: the tab says nothing is recorded; the owner switches on "record only" from Home',
    run: async ({ browser }) => {
      const pg = await docs(browser);
      await until(async () => /Off: nothing is recorded or sent/.test(await pg.locator('#eMode').textContent()), 8000, 'off');
      const home = await page(browser, { login: 'owner', aal: 'aal2', lang: 'en' });
      await goto(home, '/home');
      const sel = home.locator('#setList select[aria-label="Electronic invoices (Hacienda)"]');
      await until(async () => sel.isVisible(), 10000, 'the e-invoice setting on Home');
      assert.strictEqual(await home.locator('#setList select[aria-label="ledger_auto_post"]').count(), 0, 'the books\' switches are not on Home');
      await sel.selectOption('shadow');
      await until(() => sql(`select value #>> '{}' from settings where key = 'einvoice_mode'`) === 'shadow', 8000, 'saved');
      assert.deepStrictEqual(home.errors, []);
    }
  },
  {
    name: 'record only: a sale is listed as a ticket waiting, with the products that lack a CABYS code (Spanish)',
    run: async ({ browser }) => {
      sql(`insert into settings (key, value) values ('einvoice_mode', '"shadow"');
           insert into orders (id, created_at, total_crc, payment_method, paid, status) values ('0d000000-0000-4000-8000-0000000e2ea1', now(), 2260, 'card', true, 'done');
           insert into order_items (order_id, item_name, price_crc, qty) values ('0d000000-0000-4000-8000-0000000e2ea1', 'Latte', 2260, 1)`);
      assert.strictEqual(sql(`select kind || ':' || status from e_documents`), 'TE:pending');
      const pg = await docs(browser, 'es');
      await until(async () => /Solo registro/.test(await pg.locator('#eMode').textContent()), 8000, 'shadow, in Spanish');
      await until(async () => (await pg.locator('#eTable tbody tr').count()) === 1, 8000, 'the document listed');
      const row = (await pg.locator('#eTable tbody tr').first().innerText()).replace(/\s+/g, ' ');
      assert.match(row, /Tiquete .*₡2 260 ₡260 En espera CABYS: Latte/);
      assert.match(await pg.locator('#eCabys').textContent(), /no tienen código CABYS/);
      assert.deepStrictEqual(pg.errors, []);
    }
  }
];
