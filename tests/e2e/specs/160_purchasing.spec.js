/* Purchasing (migration 0012): orders for every vendor in one tap, deliveries with the supplier invoice, PO document. */
'use strict';
const assert = require('assert');
const { page, goto, until, sql } = require('../lib');

async function orders(browser) {
  const pg = await page(browser, { login: 'owner', aal: 'aal2', lang: 'en' });
  await goto(pg, '/inventory');
  await until(async () => (await pg.locator('#kItems').textContent()) !== '–', 15000, 'inventory loaded');
  await pg.click('#tabs [data-view=orders]');
  return pg;
}
function setup() {
  sql(`insert into vendors (id, name, email, contact_name) values ('5b000000-0000-4000-8000-0000000e2e61', 'Lácteos', 'ventas@lacteos.test', 'Rosa'),
                                                                ('5b000000-0000-4000-8000-0000000e2e62', 'Panadería', null, null);
       insert into stock_items (id, name, unit, pack_qty, cost_per_pack, par_level, reorder_point, vendor_id)
         values ('5a000000-0000-4000-8000-0000000e2e61', 'Leche', 'ml', 1000, 1000, 10000, 3000, '5b000000-0000-4000-8000-0000000e2e61'),
                ('5a000000-0000-4000-8000-0000000e2e62', 'Pan', 'unit', 10, 3000, 40, 10, '5b000000-0000-4000-8000-0000000e2e62')`);
}

module.exports.tests = [
  {
    name: 'create the orders of every vendor in one tap; each gets a number',
    run: async ({ browser }) => {
      setup();
      const pg = await orders(browser);
      await pg.waitForSelector('#allPoBtn', { state: 'visible', timeout: 8000 });
      await pg.click('#allPoBtn');
      await until(() => sql(`select count(*) from purchase_orders where po_number is not null`) === '2', 8000, 'two orders');
      assert.strictEqual(sql(`select count(*) from purchase_lines`), '2');
      await until(async () => (await pg.locator('#poList .po').count()) === 2, 8000, 'both listed');
      assert.match(await pg.locator('#poList .po').first().textContent(), /Nº \d+/);
    }
  },
  {
    name: 'a delivery in two parts with the supplier invoice; the same invoice twice is refused',
    run: async ({ browser }) => {
      setup();
      sql(`insert into purchase_orders (id, vendor_id, status) values ('9a000000-0000-4000-8000-0000000e2e61', '5b000000-0000-4000-8000-0000000e2e61', 'sent');
           insert into purchase_lines (id, po_id, item_id, packs, qty, unit_cost) values ('9b000000-0000-4000-8000-0000000e2e61', '9a000000-0000-4000-8000-0000000e2e61', '5a000000-0000-4000-8000-0000000e2e61', 10, 10000, 1)`);
      const pg = await orders(browser);
      const card = pg.locator('#poList .po').first();
      await until(async () => (await card.count()) > 0, 8000, 'order listed');
      await card.locator('button', { hasText: 'Receive' }).click();
      await pg.fill('#recvInv', 'F-200');
      await pg.locator('#recvTable [data-f=qty]').fill('6000');
      await pg.click('#recvForm button[type=submit]');
      await until(() => sql(`select status from purchase_orders where id = '9a000000-0000-4000-8000-0000000e2e61'`) === 'partially_received', 8000, 'part received');
      await until(async () => /Partly received/.test(await pg.locator('#poList').textContent()), 8000, 'shown as partly received');
      await pg.locator('#poList .po').first().locator('button', { hasText: 'Receive' }).click();
      assert.strictEqual(await pg.locator('#recvTable [data-f=qty]').inputValue(), '4000', 'the rest is proposed');
      await pg.fill('#recvInv', 'f-200');
      await pg.click('#recvForm button[type=submit]');
      await until(async () => /already entered/.test(await pg.locator('#recvErr').textContent()), 8000, 'duplicate invoice refused');
      await pg.fill('#recvInv', 'F-212');
      await pg.click('#recvForm button[type=submit]');
      await until(() => sql(`select status from purchase_orders where id = '9a000000-0000-4000-8000-0000000e2e61'`) === 'received', 8000, 'received');
      assert.strictEqual(sql(`select on_hand from stock_items where id = '5a000000-0000-4000-8000-0000000e2e61'`), '10000');
      assert.strictEqual(sql(`select string_agg(invoice_no, ',' order by received_at) from purchase_receipts`), 'F-200,F-212');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'the purchase order prints as a document with its number, vendor and total',
    run: async ({ browser }) => {
      setup();
      sql(`insert into purchase_orders (id, vendor_id, status) values ('9a000000-0000-4000-8000-0000000e2e62', '5b000000-0000-4000-8000-0000000e2e61', 'draft');
           insert into purchase_lines (po_id, item_id, packs, qty, unit_cost) values ('9a000000-0000-4000-8000-0000000e2e62', '5a000000-0000-4000-8000-0000000e2e61', 3, 3000, 1)`);
      const pg = await orders(browser);
      const card = pg.locator('#poList .po').first();
      await until(async () => (await card.count()) > 0, 8000, 'order listed');
      const [doc] = await Promise.all([pg.context().waitForEvent('page'), card.locator('button', { hasText: 'Print / PDF' }).click()]);
      const html = await doc.content();
      const no = sql(`select po_number from purchase_orders where id = '9a000000-0000-4000-8000-0000000e2e62'`);
      assert.match(html, new RegExp('PURCHASE ORDER Nº ' + no));
      assert.match(html, /Lácteos/);
      assert.match(html, /3\s?000/);
    }
  }
];
