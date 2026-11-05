/* Purchasing (migration 0012), through Proveedores since D-067 (0039/0040; Inventario's Orders tab is gone): an order for
   each supplier from its own file, each with its number; a delivery in two parts with the supplier invoice, the same
   invoice twice refused; the purchase order as a document with its number, supplier and total (an order the old page
   made, with old-style lines, included). */
'use strict';
const assert = require('assert');
const { page, goto, until, sql } = require('../lib');
const P = require('../prov');

const LAC = '5b000000-0000-4000-8000-0000000e2e61', PAN = '5b000000-0000-4000-8000-0000000e2e62';
const LECHE = '5a000000-0000-4000-8000-0000000e2e61', PANI = '5a000000-0000-4000-8000-0000000e2e62';
function setup() {
  sql(`insert into vendors (id, name, email, contact_name) values ('${LAC}', 'Lácteos', 'ventas@lacteos.test', 'Rosa'),
                                                                ('${PAN}', 'Panadería', null, null);
       insert into stock_items (id, name, unit, pack_qty, cost_per_pack, par_level, reorder_point, vendor_id)
         values ('${LECHE}', 'Leche', 'ml', 1000, 1000, 10000, 3000, '${LAC}'),
                ('${PANI}', 'Pan', 'unit', 10, 3000, 40, 10, '${PAN}')`);
}
async function proveedores(browser, hash, wait) {
  const pg = P.watchApi(await page(browser, { login: 'owner', aal: 'aal2', lang: 'en' }));
  await goto(pg, '/proveedores' + (hash || ''));
  await pg.waitForSelector(wait || '#hubVendors', { timeout: 15000 });
  return pg;
}

module.exports.tests = [
  {
    name: 'an order for each supplier from its own file (the low-stock alert opens it); each gets a number and is listed to receive',
    run: async ({ browser }) => {
      setup();
      const pg = await proveedores(browser);
      for (const [item, name] of [[LECHE, 'Lácteos'], [PANI, 'Panadería']]) {
        await pg.locator(`#hubAlerts a.acard[data-item="${item}"]`).click();
        const pin = pg.locator('#pList .prow.pin');
        await pin.waitFor({ timeout: 8000 });
        await pin.locator('.ck input').check();
        await pg.click('#pCreate');
        await pg.waitForSelector('#orderDoc', { timeout: 10000 });
        assert.match(await P.text(pg.locator('#orderDoc .dh')), /^Order Nº \d+ Created Payment pending$/);
        assert.match(await P.text(pg.locator('#orderDoc .doc')), new RegExp('Supplier: ' + name));
        await pg.locator('#main .crumbs a', { hasText: 'Suppliers' }).click();
        await pg.waitForSelector('#hubVendors');
      }
      assert.strictEqual(sql(`select count(*) from purchase_orders where po_number is not null and status = 'sent'`), '2');
      assert.strictEqual(sql(`select count(*) from purchase_lines`), '2');
      // 10 000 ml par − 0 on hand = 10 litres of milk; 40 bread − 0 = 4 bags of 10 (inventory_stats' own quantity)
      assert.strictEqual(sql(`select string_agg(trim_scale(l.packs) || '×' || trim_scale(l.pack_qty), ',' order by i.name) from purchase_lines l join stock_items i on i.id = l.item_id`), '10×1000,4×10');
      await P.seen(pg.locator('#hubReceive'), /^To receive Order Nº \d+ Lácteos .*Receive Open Order Nº \d+ Panadería .*Receive Open$/, 'both listed', 8000);
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, []);
    }
  },
  {
    name: 'a delivery in two parts with the supplier invoice; the same invoice twice is refused',
    run: async ({ browser }) => {
      setup();
      // an order with an old-style line (the published Inventario page writes them directly: no catalog row of its own)
      sql(`insert into purchase_orders (id, vendor_id, status) values ('9a000000-0000-4000-8000-0000000e2e61', '${LAC}', 'sent');
           insert into purchase_lines (id, po_id, item_id, packs, qty, unit_cost) values ('9b000000-0000-4000-8000-0000000e2e61', '9a000000-0000-4000-8000-0000000e2e61', '${LECHE}', 10, 10000, 1)`);
      const pg = await proveedores(browser);
      await pg.locator('#hubReceive a', { hasText: 'Receive' }).click();
      await pg.waitForSelector('#recvCard');
      assert.strictEqual(await pg.inputValue('#rq0'), '10', '10 packs of 1 litre pending');
      await pg.fill('#rInv', 'F-200');
      await pg.fill('#rq0', '6');
      await pg.click('#recvGo');
      await pg.waitForSelector('#recvDone', { timeout: 10000 });
      assert.strictEqual(sql(`select status from purchase_orders where id = '9a000000-0000-4000-8000-0000000e2e61'`), 'partially_received');
      await pg.locator('#recvDone a', { hasText: 'Open the order' }).click();
      await P.seen(pg.locator('#orderDoc .dh'), /Partially received/, 'shown as partly received', 8000);
      await pg.locator('#docActs a', { hasText: 'Receive' }).click();
      await pg.waitForSelector('#recvCard');
      assert.strictEqual(await pg.inputValue('#rq0'), '4', 'the rest is proposed');
      await pg.fill('#rInv', 'f-200');
      await pg.click('#recvGo');
      await P.seen(pg.locator('#rErr'), /That invoice number is already registered for this supplier\./, 'duplicate invoice refused', 8000);
      assert.strictEqual(sql(`select count(*) from purchase_receipts`), '1', 'nothing booked');
      await pg.fill('#rInv', 'F-212');
      await pg.click('#recvGo');
      await pg.waitForSelector('#recvDone', { timeout: 10000 });
      assert.strictEqual(sql(`select status from purchase_orders where id = '9a000000-0000-4000-8000-0000000e2e61'`), 'received');
      assert.strictEqual(sql(`select trim_scale(on_hand) from stock_items where id = '${LECHE}'`), '10000');
      assert.strictEqual(sql(`select string_agg(invoice_no, ',' order by received_at) from purchase_receipts`), 'F-200,F-212');
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, []);
    }
  },
  {
    name: 'the purchase order prints as a document with its number, supplier and total (an old page\'s draft order too)',
    run: async ({ browser }) => {
      setup();
      sql(`insert into purchase_orders (id, vendor_id, status) values ('9a000000-0000-4000-8000-0000000e2e62', '${LAC}', 'draft');
           insert into purchase_lines (po_id, item_id, packs, qty, unit_cost) values ('9a000000-0000-4000-8000-0000000e2e62', '${LECHE}', 3, 3000, 1)`);
      const no = sql(`select po_number from purchase_orders where id = '9a000000-0000-4000-8000-0000000e2e62'`);
      const pg = await proveedores(browser, '#pedido=9a000000-0000-4000-8000-0000000e2e62', '#orderDoc');
      assert.match(await P.text(pg.locator('#orderDoc .dh')), new RegExp('^Order Nº ' + no + ' Draft'));
      await pg.click('#docPrint');
      assert.strictEqual(await pg.evaluate(() => window.__printed), 1);
      const html = await pg.evaluate(() => document.getElementById('printDoc').innerHTML);
      assert.match(html, new RegExp('PEDIDO Nº ' + no));
      assert.match(html, /Lácteos/);
      assert.match(html, /₡3 000/);
      // the old page's draft is confirmed here: it becomes «Creado» (sent) with its time
      await pg.locator('#docActs button', { hasText: 'Confirm the order' }).click();
      await P.toasted(pg, /^Order confirmed$/, 'confirmed');
      assert.strictEqual(sql(`select status || '|' || (sent_at is not null) from purchase_orders where id = '9a000000-0000-4000-8000-0000000e2e62'`), 'sent|true');
      assert.deepStrictEqual(pg.errors, []);
    }
  }
];
