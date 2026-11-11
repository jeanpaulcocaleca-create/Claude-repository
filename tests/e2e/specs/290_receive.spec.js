/* Receive a delivery with the supplier invoice and the payment (migration 0029), through Proveedores since D-067
   (0039/0040; Inventario's receive window is gone): the café device with a manager PIN, the invoice typed, a SINPE
   payment, the rest paid later by card; a delivery whose invoice comes later stays pending and is registered from the
   supplier's payments (a double tap saves once); a wrong PIN or paying more than is owed is refused and saves nothing; a
   dollar invoice valued in colones at the typed rate. (Cash from the register is no longer offered here: the owner's two
   methods are SINPE and card; Contabilidad keeps cash and petty cash, D-067.) */
'use strict';
const assert = require('assert');
const { page, goto, until, sql, STAFF, PINS } = require('../lib');
const P = require('../prov');

const VENDOR = '5b000000-0000-4000-8000-0000000e2e91', ITEM = '5a000000-0000-4000-8000-0000000e2e91';
const PO = '9a000000-0000-4000-8000-0000000e2e91', LINE = '9b000000-0000-4000-8000-0000000e2e91';
function setup() {
  sql(`insert into vendors (id, name) values ('${VENDOR}', 'Panadería Sol');
       insert into stock_items (id, name, unit, pack_qty, cost_per_pack, vendor_id) values ('${ITEM}', 'Pan', 'unit', 10, 3000, '${VENDOR}');
       insert into purchase_orders (id, vendor_id, status) values ('${PO}', '${VENDOR}', 'sent');
       insert into purchase_lines (id, po_id, item_id, packs, qty, unit_cost) values ('${LINE}', '${PO}', '${ITEM}', 2, 20, 300)`);
}
const paid = (inv) => `(select coalesce(sum(a.amount_crc), 0) from supplier_payment_allocations a join supplier_payments p on p.id = a.payment_id where a.invoice_id = ${inv} and p.voided_at is null)`;
const lines = (prefix) => sql(`select coalesce(string_agg(l.account || ':' || (l.debit - l.credit), ',' order by e.id, l.account), '') from acct.lines l join acct.entries e on e.id = l.entry_id where e.source_key like '${prefix}%'`);

/* the order's receive form, as management */
async function receiveAll(pg, invoiceNo) {
  await pg.evaluate((h) => { location.hash = h; }, '#recibir=' + PO);
  await pg.waitForSelector('#recvCard', { timeout: 10000 });
  assert.strictEqual(await pg.inputValue('#rq0'), '2', '2 bags pending');
  if (invoiceNo) await pg.fill('#rInv', invoiceNo);
  await pg.click(invoiceNo ? '#recvGo' : '#recvAll');
  await pg.waitForSelector('#recvDone', { timeout: 10000 });
}
async function invoice(pg, o) {
  await pg.waitForSelector('#invModal:not([hidden])', { timeout: 8000 });
  if (o.number != null) await pg.fill('#invNum', o.number);
  if (o.usd) { await pg.selectOption('#invCur', 'USD'); await pg.waitForSelector('#invFxBox:not([hidden])'); await pg.fill('#invFx', o.usd); }
  await pg.fill('#invNet', o.net);
  await pg.fill('#invIva', o.iva);
}
async function pay(pg, o) {
  await pg.waitForSelector('#payModal:not([hidden])', { timeout: 8000 });
  if (o.card) await pg.locator('#payMethod button[data-m=card]').click();
  if (o.amount != null) await pg.fill('#payAmt', String(o.amount));
  if (o.ref) await pg.fill(o.card ? '#payRefC' : '#payRef', o.ref);
  if (o.pin) { await pg.selectOption('#payWho', STAFF.ana); await pg.fill('#payPin', o.pin); }
}

module.exports.tests = [
  {
    name: 'café device + manager PIN: the delivery, its invoice typed, a SINPE payment; the rest paid later by card',
    run: async ({ browser }) => {
      setup();
      const pg = await P.cafeManager(browser, { wait: '#hubVendors' });
      await receiveAll(pg, '00100001010000000123');
      await P.seen(pg.locator('#recvDone'), /^Pedido recibido, existencias actualizadas 2 × Pan Recibido al costo ₡6 000/, 'received, in Spanish', 5000);
      assert.strictEqual(sql(`select invoice_status || '|' || invoice_no || '|' || (invoice_id is null) || '|' || (select trim_scale(on_hand) from stock_items where id = '${ITEM}') from purchase_receipts`),
        'pending|00100001010000000123|true|20', 'the number typed at the door; the invoice itself is registered next');
      await pg.locator('#recvDone button', { hasText: 'Registrar factura' }).click();
      await invoice(pg, { net: '6000', iva: '780' });
      assert.strictEqual(await pg.inputValue('#invNum'), '00100001010000000123', 'the number typed at the door is proposed');
      await P.seen(pg.locator('#invTotal'), /^Total ₡6 780$/, 'the total, in Spanish', 3000);
      await P.untoast(pg); await pg.click('#invGo');
      await P.toasted(pg, /^Factura guardada · ₡6 780 · pendiente ₡6 780$/, 'the invoice, in Spanish');
      const r = sql(`select r.invoice_status || '|' || i.number || '|' || i.total_crc || '|' || i.currency from purchase_receipts r join supplier_invoices i on i.id = r.invoice_id`);
      assert.strictEqual(r, 'confirmed|00100001010000000123|6780.00|CRC');
      assert.strictEqual(lines('supinv:'), '1140:780.00,2101:-780.00', 'the invoice posts its IVA; the goods were posted when received');
      // a SINPE payment of ₡2 000 with the manager's PIN: applied to the invoice at once
      await P.nav(pg, '#pedido=' + PO, '#orderDoc');
      await pg.click('#docPay');
      await pay(pg, { amount: 2000, ref: '77665544', pin: PINS.ana });
      await P.untoast(pg); await pg.click('#payGo');
      await P.toasted(pg, /^Pago guardado$/, 'paid in part');
      assert.strictEqual(sql(`select ${paid('i.id')} || '|' || public._invoice_open(i.id) from supplier_invoices i`), '2000.00|4780.00');
      assert.strictEqual(lines('supadv:'), '1110:-2000.00,1160:2000.00', 'the transfer left the bank into «Anticipos a proveedores»');
      assert.strictEqual(lines('suppay:'), '1160:-2000.00,2101:2000.00', 'and was applied to the invoice');
      await P.seen(pg.locator('#orderDoc .dh'), /Recibido Parcialmente pagado$/, 'partly paid', 8000);
      // the rest by card: the open amount is proposed
      await pg.click('#docPay');
      await pay(pg, { card: true, pin: PINS.ana });
      assert.strictEqual(await pg.inputValue('#payAmt'), '4780', 'the open amount proposed');
      await P.untoast(pg); await pg.click('#payGo');
      await P.toasted(pg, /^Pago guardado$/, 'paid in full');
      assert.strictEqual(sql(`select ${paid('i.id')} || '|' || public._invoice_open(i.id) from supplier_invoices i`), '6780.00|0.00');
      await P.seen(pg.locator('#orderDoc .dh'), /Recibido Pagado$/, 'paid', 8000);
      await P.seen(pg.locator('#docMoney'), /^Pago Pagado A pagar ₡6 780 · Pagado ₡6 780/, 'nothing owed', 5000);
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, []);
      assert.strictEqual(pg.supabaseHits, 0);
    }
  },
  {
    name: 'a delivery whose invoice comes later stays pending; it is registered from the supplier\'s payments; a double tap saves once',
    run: async ({ browser }) => {
      setup();
      const pg = P.watchApi(await page(browser, { login: 'owner', aal: 'aal2', lang: 'en' }));
      await goto(pg, '/proveedores');
      await pg.waitForSelector('#hubVendors');
      await receiveAll(pg);
      await P.seen(pg.locator('#recvDone'), /^Order received, stock updated/, 'received', 5000);
      assert.strictEqual(sql(`select invoice_status || '|' || (invoice_id is null) from purchase_receipts`), 'pending|true');
      assert.strictEqual(sql(`select count(*) from supplier_invoices`), '0', 'no invoice, no tax yet');
      await P.nav(pg, '#p=' + VENDOR + '&t=pagos', '#pgInv');
      await P.seen(pg.locator('#fTab'), /Deliveries without invoice Order Nº \d+ .* received ₡6 000/i, 'shown as without invoice', 5000);
      await pg.click('#pgInv');
      await invoice(pg, { number: 'F-77', net: '6000', iva: '780' });
      // a double tap: one invoice (the request id is kept until the answer)
      await P.untoast(pg);
      await pg.evaluate(() => { const b = document.getElementById('invGo'); b.click(); b.click(); });
      await P.toasted(pg, /^Invoice saved · ₡6 780 · open ₡6 780$/, 'the invoice');
      assert.strictEqual(sql(`select count(*) || '|' || sum(total_crc) || '|' || string_agg(number, ',') from supplier_invoices`), '1|6780.00|F-77');
      await pg.waitForSelector('#pgPay');
      await pg.click('#pgPay');
      await pay(pg, { card: true });
      await pg.selectOption('#payPo', PO);
      await pg.fill('#payAmt', '6780');
      await P.untoast(pg);
      await pg.evaluate(() => { const b = document.getElementById('payGo'); b.click(); b.click(); });
      await P.toasted(pg, /^Payment saved$/, 'paid by debit card');
      assert.strictEqual(sql(`select count(*) || '|' || string_agg(method, ',') from supplier_advances`), '1|card_debit', 'one payment');
      assert.strictEqual(sql(`select count(*) || '|' || string_agg(paid_from || ':' || method, ',') from supplier_payments`), '1|advance:card_debit');
      assert.strictEqual(sql(`select ${paid('i.id')} || '|' || public._invoice_open(i.id) from supplier_invoices i`), '6780.00|0.00');
      assert.strictEqual(lines('supadv:'), '1110:-6780.00,1160:6780.00', 'paid from the bank account (debit card)');
      // the order tells the whole story
      await P.nav(pg, '#pedido=' + PO, '#orderDoc');
      await P.seen(pg.locator('#docMoney'), /Invoice F-77 · .* · total ₡6 780 Payment ₡6 780/, 'the invoice and the payment on the order', 5000);
      await P.seen(pg.locator('#main .rcpt'), /invoice F-77 · Invoice confirmed/, 'the delivery with its invoice', 5000);
      await pg.locator('#main details summary', { hasText: 'History of changes' }).click();
      const hist = await P.text(pg.locator('#main details'));
      assert.match(hist, /entrega · completa/, hist);
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, []);
    }
  },
  {
    name: 'a wrong PIN or paying more than is owed is refused, and nothing is saved',
    run: async ({ browser }) => {
      setup();
      const pg = await P.cafeManager(browser, { wait: '#hubVendors', lang: 'en' });
      await receiveAll(pg, 'F-78');
      await pg.locator('#recvDone button', { hasText: 'Register the invoice' }).click();
      await invoice(pg, { net: '6000', iva: '780' });
      await P.untoast(pg); await pg.click('#invGo');
      await P.toasted(pg, /^Invoice saved/, 'the invoice');
      await P.nav(pg, '#pedido=' + PO, '#orderDoc');
      await pg.click('#docPay');
      await pay(pg, { amount: 999999, ref: '55443322', pin: PINS.ana });
      await pg.click('#payGo');
      await P.seen(pg.locator('#payErr'), /^That is more than what is owed: the balance is ₡6 780\. Only the owner can register a payment above the balance\.$/, 'over what is owed', 8000);
      assert.strictEqual(sql(`select count(*) from supplier_advances`), '0');
      await pg.fill('#payAmt', '1000');
      await pg.fill('#payPin', '0000');
      await pg.click('#payGo');
      await P.seen(pg.locator('#payErr'), /^That PIN is not right\.$/, 'wrong PIN', 8000);
      assert.strictEqual(sql(`select count(*) from supplier_advances`), '0');
      assert.strictEqual(sql(`select count(*) from acct.entries where source_key like 'supadv:%'`), '0', 'nothing in the books');
      assert.strictEqual(sql(`select failed_pins from staff where id = '${STAFF.ana}'`), '1', 'the wrong try is counted');
      await pg.fill('#payPin', PINS.ana);
      await P.untoast(pg); await pg.click('#payGo');
      await P.toasted(pg, /^Payment saved$/, 'saved once everything is right');
      assert.strictEqual(sql(`select count(*) || '|' || sum(amount_crc) from supplier_advances`), '1|1000.00');
      assert.strictEqual(sql(`select public._invoice_open(id) from supplier_invoices`), '5780.00');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'a dollar invoice is valued in colones at the typed rate and shows so on the order',
    run: async ({ browser }) => {
      setup();
      const pg = P.watchApi(await page(browser, { login: 'owner', aal: 'aal2', lang: 'en' }));
      await goto(pg, '/proveedores');
      await pg.waitForSelector('#hubVendors');
      await receiveAll(pg, 'US-5');
      await pg.locator('#recvDone button', { hasText: 'Register the invoice' }).click();
      await invoice(pg, { usd: '520', net: '10', iva: '1.3' });
      await P.seen(pg.locator('#invTotal'), /^Total \$11\.30 = ₡5 876$/, 'the dollars and the colones', 3000);
      await P.untoast(pg); await pg.click('#invGo');
      await P.toasted(pg, /^Invoice saved · ₡5 876 · open ₡5 876$/, 'saved in colones');
      assert.strictEqual(sql(`select currency || '|' || fx_rate || '|' || net_fx || '|' || iva_fx || '|' || net_crc || '|' || iva_crc || '|' || total_crc from supplier_invoices`), 'USD|520.00|10.00|1.30|5200.00|676.00|5876.00');
      await P.nav(pg, '#pedido=' + PO, '#orderDoc');
      await P.seen(pg.locator('#docMoney'), /Invoice US-5 · .* · total \$11\.30 at ₡520 = ₡5 876 · open ₡5 876/, 'the dollar invoice on the order', 5000);
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, []);
    }
  }
];
