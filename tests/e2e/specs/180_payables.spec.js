/* Suppliers on the accounting page (migration 0016): an invoice linked to its delivery, a payment, the aging, a void. */
'use strict';
const assert = require('assert');
const { page, goto, until, sql } = require('../lib');

const VENDOR = '5b000000-0000-4000-8000-0000000e2e81';
function delivery() {
  sql(`insert into vendors (id, name) values ('${VENDOR}', 'Café de Altura');
       insert into purchase_orders (id, vendor_id, status) values ('9a000000-0000-4000-8000-0000000e2e81', '${VENDOR}', 'received');
       insert into purchase_receipts (id, po_id, vendor_id, invoice_no, total_crc, final)
         values ('7e000000-0000-4000-8000-0000000e2e81', '9a000000-0000-4000-8000-0000000e2e81', '${VENDOR}', 'F-88', 10000, true)`);
}
async function suppliers(browser, lang) {
  const pg = await page(browser, { login: 'accountant', lang: lang || 'en' });
  await goto(pg, '/accounting');
  await pg.waitForSelector('#appView:not([hidden])', { timeout: 15000 });
  await pg.click('#tabs [data-view=payables]');
  await until(async () => (await pg.locator('#viVendor option').count()) > 1, 8000, 'suppliers listed');
  return pg;
}

module.exports.tests = [
  {
    name: 'an invoice is linked to its delivery, then paid; the aging and the books follow',
    run: async ({ browser }) => {
      delivery();
      const pg = await suppliers(browser);
      await pg.selectOption('#viVendor', VENDOR);
      await until(async () => (await pg.locator('#viRecs input').count()) === 1, 5000, 'the delivery waiting for its invoice');
      await pg.locator('#viRecs input').check();
      assert.strictEqual(await pg.locator('#viAcctBox').isHidden(), true, 'no account to pick when it is a delivery');
      await pg.fill('#viNum', 'F-88');
      await pg.fill('#viNet', '10200');
      await pg.fill('#viIva', '1326');
      await until(async () => /difference with the invoice ₡200/.test((await pg.locator('#viDiff').textContent()).replace(/\s/g, ' ')), 5000, 'the price difference shown');
      await pg.click('#viGo');
      await until(() => sql(`select number || ':' || total_crc from supplier_invoices`) === 'F-88:11526.00', 8000, 'invoice saved');
      assert.strictEqual(sql(`select invoice_id is not null from purchase_receipts`), 't', 'the delivery points to its invoice');
      await until(async () => /Café de Altura/.test(await pg.locator('#agTable').textContent()), 8000, 'the supplier in the aging');
      assert.match((await pg.locator('#agTable tbody tr').first().textContent()).replace(/\s/g, ''), /₡11526/);
      // pay part of it by bank
      await pg.selectOption('#vpVendor', VENDOR);
      await until(async () => /11\s526/.test(await pg.locator('#vpOwed').textContent()), 5000, 'what is owed');
      await pg.fill('#vpAmt', '6000');
      await pg.fill('#vpRef', 'TRF 991');
      await pg.click('#vpGo');
      await until(() => sql(`select amount_crc::text from supplier_payment_allocations`) === '6000.00', 8000, 'payment applied to the invoice');
      await until(async () => /TRF 991/.test(await pg.locator('#vpTable').textContent()), 8000, 'payment listed');
      assert.strictEqual(sql(`select string_agg(l.account || ':' || (l.debit - l.credit), ',' order by l.account, l.debit - l.credit) from acct.lines l join acct.entries e on e.id = l.entry_id where e.source = 'ap'`),
        '1110:-6000.00,1140:1326.00,2101:-1526.00,2101:6000.00,5103:200.00', 'invoice: IVA credit + price difference; payment: payable against the bank');
      assert.strictEqual(sql(`select sum(l.debit - l.credit)::text from acct.lines l join acct.entries e on e.id = l.entry_id where e.source = 'ap' and l.account = '2101'`), '4474.00',
        'payable: −1 526 (IVA + difference) + 6 000 paid');
      // the payment is voided: what it paid is owed again
      pg.onDialog = (d) => d.accept('transferencia devuelta');
      await pg.locator('#vpTable button', { hasText: 'Void' }).click();
      await until(() => sql(`select voided_at is not null from supplier_payments`) === 't', 8000, 'payment voided');
      await until(async () => (await pg.locator('#vpTable tbody tr').count()) === 0, 8000, 'gone from the recent payments');
      assert.match((await pg.locator('#agTable tbody tr').first().textContent()).replace(/\s/g, ''), /₡11526/);
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'in Spanish; an invoice for a service needs its account; more than owed is refused',
    run: async ({ browser }) => {
      delivery();
      const pg = await suppliers(browser, 'es');
      await until(async () => /Lo que se debe a proveedores/.test(await pg.locator('#view-payables').textContent()), 5000, 'Spanish headings');
      await pg.selectOption('#viVendor', VENDOR);
      await until(async () => (await pg.locator('#viRecs input').count()) === 1, 5000, 'the delivery');
      // not ticked: the invoice is for a repair
      assert.strictEqual(await pg.locator('#viAcctBox').isVisible(), true, 'the account is asked when there is no delivery');
      const accts = await pg.locator('#viAcct option').evaluateAll((os) => os.map((o) => o.value));
      assert.match(accts[0], /^[56]/, 'costs and expenses first');
      ['1101', '1110', '1120', '1130', '1140', '2101'].forEach((c) => assert.ok(!accts.includes(c), c + ' is not offered: money, IVA or payables'));
      assert.ok(accts.includes('1201'), 'equipment can be bought on an invoice');
      await pg.fill('#viNum', 'S-12');
      await pg.fill('#viNet', '20000');
      await pg.fill('#viIva', '2600');
      await pg.selectOption('#viAcct', '6206');
      await pg.click('#viGo');
      await until(() => sql(`select account from supplier_invoices`) === '6206', 8000, 'service invoice saved with its account');
      await pg.selectOption('#vpVendor', VENDOR);
      await pg.fill('#vpAmt', '30000');
      await pg.click('#vpGo');
      await until(async () => /más de lo que se le debe/.test(await pg.locator('#vpErr').textContent()), 5000, 'refused in Spanish');
      assert.strictEqual(sql(`select count(*) from supplier_payments`), '0');
      assert.deepStrictEqual(pg.errors, []);
    }
  }
];
