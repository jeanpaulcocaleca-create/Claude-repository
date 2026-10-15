/* Receive a delivery with the supplier invoice and the payment (migration 0029): the café device with a manager PIN,
   the invoice typed by hand, cash from the register and a later bank payment; a delivery whose invoice comes later;
   refusals that save nothing; a dollar invoice valued in colones. */
'use strict';
const assert = require('assert');
const { page, goto, until, sql, openRegister, STAFF, PINS } = require('../lib');

const VENDOR = '5b000000-0000-4000-8000-0000000e2e91', ITEM = '5a000000-0000-4000-8000-0000000e2e91';
const PO = '9a000000-0000-4000-8000-0000000e2e91', LINE = '9b000000-0000-4000-8000-0000000e2e91';
function setup() {
  sql(`insert into vendors (id, name) values ('${VENDOR}', 'Panadería Sol');
       insert into stock_items (id, name, unit, pack_qty, cost_per_pack, vendor_id) values ('${ITEM}', 'Pan', 'unit', 10, 3000, '${VENDOR}');
       insert into purchase_orders (id, vendor_id, status) values ('${PO}', '${VENDOR}', 'sent');
       insert into purchase_lines (id, po_id, item_id, packs, qty, unit_cost) values ('${LINE}', '${PO}', '${ITEM}', 2, 20, 300)`);
}
const today = () => sql(`select cr_today()::text`);

/* the Orders tab of the inventory page; a café device opens it with a manager PIN */
async function orders(browser, opts) {
  const pg = await page(browser, Object.assign({ login: 'owner', aal: 'aal2', lang: 'en' }, opts || {}));
  await goto(pg, '/inventory');
  if ((opts || {}).login === 'cafe') {
    await pg.waitForSelector('#hgaPin', { timeout: 8000 });
    await pg.selectOption('#hgaWho', STAFF.ana);
    await pg.fill('#hgaPin', PINS.ana);
    await pg.click('.hga-go');
  }
  await until(async () => (await pg.locator('#kItems').textContent()) !== '–', 15000, 'inventory loaded');
  await pg.click('#tabs [data-view=orders]');
  await pg.waitForSelector('#pendCard:not([hidden])', { timeout: 8000 });
  return pg;
}
async function openReceive(pg) {
  const card = pg.locator('#poList .po').first();
  await until(async () => (await card.count()) > 0, 8000, 'order listed');
  await card.locator('button', { hasText: /^(Receive|Recibir)$/ }).click();
  await pg.waitForSelector('#recvModal:not([hidden])', { timeout: 5000 });
  await pg.waitForSelector('#rvBox:not([hidden])', { timeout: 5000 });
}
async function payRow(pg, method, amount) {
  await pg.click('#rvAddPay');
  const row = pg.locator('#rvPays .rv-pay').last();
  await row.locator('.rv-method').selectOption(method);
  await row.locator('.rv-amount').fill(String(amount));
}
async function pin(pg, who, code) {
  await pg.waitForSelector('#rvPinBox:not([hidden])', { timeout: 5000 });
  await pg.selectOption('#rvMgr', who);
  await pg.fill('#rvPin', code);
}
const plain = (s) => String(s || '').replace(/\s+/g, ' ');   // the page's money uses narrow no-break spaces
const toast = async (pg) => plain(await pg.locator('#toast').textContent());
const text = async (loc) => plain(await loc.textContent());
const paid = (inv) => `(select coalesce(sum(a.amount_crc), 0) from supplier_payment_allocations a where a.invoice_id = ${inv})`;
/* waits for a toast; a timeout reports what the modal said instead */
async function toasted(pg, re, what) {
  try { await until(async () => re.test(await toast(pg)), 10000, what); }
  catch (e) { throw new Error(e.message + ' · toast: ' + (await toast(pg)) + ' · error shown: ' + plain(await pg.locator('#recvErr').textContent())); }
}

module.exports.tests = [
  {
    name: 'café device + manager PIN: the delivery, its invoice typed, cash from the register; the rest paid later by bank',
    run: async ({ browser }) => {
      setup(); openRegister();
      const pg = await orders(browser, { login: 'cafe', lang: 'es' });
      await until(async () => /No se debe nada/.test(await text(pg.locator('#pendOwed'))), 5000, 'nothing owed yet, in Spanish');   // the translation runs a frame later
      await openReceive(pg);
      await until(async () => (await text(pg.locator('#recvGo'))) === 'Confirmar recepción', 5000, 'the button, in Spanish');
      assert.strictEqual(await pg.locator('#rvCamBtn, #rvFileBtn, #rvRead').count(), 0, 'no photo, file or reader buttons');
      await pg.locator('#recvTable [data-f=qty]').fill('20');
      await pg.fill('#recvInv', '00100001010000000123');
      await pg.fill('#recvInvDate', today());
      await pg.selectOption('#rvMode', 'confirm');
      await pg.fill('#rvNet', '6000'); await pg.fill('#rvIva', '780');
      await payRow(pg, 'register', 2000);
      await until(async () => /Pagado: ₡2 000 · Saldo: ₡4 780/.test(await text(pg.locator('#rvPaySum'))), 5000, 'the balance, in Spanish');
      await pin(pg, STAFF.ana, PINS.ana);
      await pg.click('#recvGo');
      await toasted(pg, /Factura confirmada · pagado ₡2 000 · pendiente ₡4 780/, 'confirmed, in Spanish');
      const r = sql(`select r.invoice_status || '|' || i.number || '|' || i.total_crc || '|' || ${paid('i.id')} || '|' || i.currency || '|' || (select on_hand from stock_items where id = '${ITEM}')
                     from purchase_receipts r join supplier_invoices i on i.id = r.invoice_id`);
      assert.strictEqual(r, 'confirmed|00100001010000000123|6780.00|2000.00|CRC|20');
      assert.strictEqual(sql(`select direction || '|' || purpose || '|' || amount_crc || '|' || (business_date = cr_today()) from cash_movements`), 'out|payout|2000.00|true', 'the cash left the register drawer');
      assert.strictEqual(sql(`select paid_from || '|' || amount_crc || '|' || (payout_id is not null) from supplier_payments`), 'payout|2000.00|true', 'the payment points at the register payout');
      // the invoice and the payment are in the books, the IVA apart from the goods
      assert.strictEqual(sql(`select string_agg(l.account || ':' || (l.debit - l.credit), ',' order by l.account) from acct.lines l join acct.entries e on e.id = l.entry_id
                                where e.source_key like 'supinv:%'`), '1140:780.00,2101:-780.00', 'the invoice posts its IVA; the goods were posted when received');
      // what is still owed shows on the page; the rest is paid by bank with the PIN
      await until(async () => /pendiente ₡4 780/.test(await text(pg.locator('#pendInvoices'))), 8000, 'the open invoice listed');
      await pg.locator('#pendInvoices button', { hasText: /^Registrar pago$/ }).click();
      await pg.waitForSelector('#recvModal:not([hidden])', { timeout: 5000 });
      await until(async () => /^Registrar un pago · Nº/.test(await text(pg.locator('#recvTitle'))), 5000, 'the pay window title, in Spanish');
      // the page proposes one row with the whole open amount from the register: pay it by bank instead
      const row = pg.locator('#rvPays .rv-pay');
      await until(async () => (await row.count()) === 1 && (await row.locator('.rv-amount').inputValue()) === '4780', 5000, 'the open amount proposed');
      await row.locator('.rv-method').selectOption('bank');
      await pin(pg, STAFF.ana, PINS.ana);
      await pg.click('#recvGo');
      await toasted(pg, /Pago registrado · pendiente ₡0/, 'paid in full');
      assert.strictEqual(sql(`select ${paid('i.id')} || '|' || public._invoice_open(i.id) from supplier_invoices i`), '6780.00|0.00');
      await until(async () => /No se debe nada/.test(await pg.locator('#pendOwed').textContent()), 8000, 'nothing owed again');
      assert.deepStrictEqual(pg.errors, []);
      assert.strictEqual(pg.supabaseHits, 0);
    }
  },
  {
    name: 'a delivery whose invoice comes later stays pending; it is registered from the pending card; a double tap saves once',
    run: async ({ browser }) => {
      setup();
      const pg = await orders(browser);
      await openReceive(pg);
      await pg.locator('#recvTable [data-f=qty]').fill('20');
      assert.strictEqual(await pg.inputValue('#rvMode'), 'pending');
      await pg.click('#recvGo');
      await toasted(pg, /Order received, stock updated/, 'received');
      assert.strictEqual(sql(`select invoice_status || '|' || (invoice_id is null) from purchase_receipts`), 'pending|true');
      assert.strictEqual(sql(`select count(*) from supplier_invoices`), '0', 'no invoice, no tax yet');
      await until(async () => /Invoice pending/.test(await text(pg.locator('#pendReceipts'))), 8000, 'shown as pending');
      await pg.locator('#pendReceipts button', { hasText: /^Register invoice$/ }).click();
      await pg.waitForSelector('#recvModal:not([hidden])', { timeout: 5000 });
      assert.match(await pg.locator('#recvTitle').textContent(), /^Invoice and payment · Nº/);
      assert.strictEqual(await pg.locator('#recvLinesBox').isVisible(), false, 'the goods were already received');
      await pg.fill('#recvInv', 'F-77');
      await pg.fill('#recvInvDate', today());
      await pg.selectOption('#rvMode', 'confirm');
      await pg.fill('#rvNet', '6000');
      await pg.fill('#rvIva', '780');
      await payRow(pg, 'card_debit', 6780);
      await pin(pg, STAFF.ana, PINS.ana);
      // a double tap: the second one is ignored by the page, and the server would answer the same thing anyway
      await pg.evaluate(() => { const b = document.getElementById('recvGo'); b.click(); b.click(); });
      await toasted(pg, /Invoice confirmed · paid ₡6 780 · open ₡0/, 'confirmed and paid');
      assert.strictEqual(sql(`select count(*) || '|' || sum(total_crc) || '|' || sum(${paid('i.id')}) from supplier_invoices i`), '1|6780.00|6780.00');
      assert.strictEqual(sql(`select count(*) || '|' || string_agg(paid_from, ',') from supplier_payments`), '1|card_debit');
      assert.strictEqual(sql(`select string_agg(l.account || ':' || (l.debit - l.credit), ',' order by l.account) from acct.lines l join acct.entries e on e.id = l.entry_id
                                where e.source_key like 'suppay:%'`), '1110:-6780.00,2101:6780.00', 'paid from the bank account (debit card)');
      // the history of the order tells the whole story
      await until(async () => (await pg.locator('#poDone .po').count()) > 0, 8000, 'in received orders');
      await pg.locator('#poDone .po').first().locator('button', { hasText: /^Details$/ }).click();
      await pg.waitForSelector('#histModal:not([hidden])', { timeout: 5000 });
      const hist = await text(pg.locator('#histBody'));
      assert.match(hist, /Invoice confirmed/); assert.match(hist, /Invoice Nº F-77/); assert.match(hist, /Payment on .* · Debit card · ₡6 780/);
      assert.strictEqual(await pg.locator('#histBody button', { hasText: /Attach|View file/ }).count(), 0, 'nothing about files');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'cash from a closed register, a wrong PIN or paying more than the invoice is refused, and nothing of the delivery is saved',
    run: async ({ browser }) => {
      setup();
      const pg = await orders(browser);
      await openReceive(pg);
      await pg.locator('#recvTable [data-f=qty]').fill('20');
      await pg.fill('#recvInv', 'F-78');
      await pg.fill('#recvInvDate', today());
      await pg.selectOption('#rvMode', 'confirm');
      await pg.fill('#rvNet', '6000'); await pg.fill('#rvIva', '780');
      await payRow(pg, 'register', 1000);
      await pin(pg, STAFF.ana, PINS.ana);
      await pg.click('#recvGo');
      await until(async () => /The register is not open/.test(await pg.locator('#recvErr').textContent()), 8000, 'no register open');
      assert.strictEqual(sql(`select count(*) from purchase_receipts`), '0', 'the delivery was not saved half-way');
      assert.strictEqual(sql(`select on_hand from stock_items where id = '${ITEM}'`), '0');
      openRegister();
      await pg.fill('#rvPin', '0000');
      await pg.click('#recvGo');
      await until(async () => /That PIN is not right/.test(await pg.locator('#recvErr').textContent()), 8000, 'wrong PIN');
      assert.strictEqual(sql(`select count(*) from purchase_receipts`), '0');
      assert.strictEqual(sql(`select count(*) from cash_movements`), '0', 'no money left the register');
      assert.strictEqual(sql(`select failed_pins from staff where id = '${STAFF.ana}'`), '1', 'the wrong try is counted');
      await pg.locator('#rvPays .rv-amount').last().fill('999999');
      await pg.fill('#rvPin', PINS.ana);
      await pg.click('#recvGo');
      await until(async () => /more than the invoice/.test(await pg.locator('#recvErr').textContent()), 8000, 'over the invoice');
      assert.strictEqual(sql(`select count(*) from purchase_receipts`), '0');
      await pg.locator('#rvPays .rv-amount').last().fill('1000');
      await pg.click('#recvGo');
      await toasted(pg, /Invoice confirmed · paid ₡1 000 · open ₡5 780/, 'saved once everything is right');
      assert.strictEqual(sql(`select count(*) || '|' || (select count(*) from cash_movements) from purchase_receipts`), '1|1');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'a dollar invoice is valued in colones at the typed rate and shows so in the history',
    run: async ({ browser }) => {
      setup();
      const pg = await orders(browser);
      await openReceive(pg);
      await pg.locator('#recvTable [data-f=qty]').fill('20');
      await pg.fill('#recvInv', 'US-5');
      await pg.fill('#recvInvDate', today());
      await pg.selectOption('#rvMode', 'confirm');
      await pg.selectOption('#rvCur', 'USD');
      await pg.waitForSelector('#rvFxRow:not([hidden])', { timeout: 3000 });
      await pg.fill('#rvFx', '520');
      await pg.fill('#rvNet', '10'); await pg.fill('#rvIva', '1.3');
      assert.match(await text(pg.locator('#rvTotals')), /Invoice total: \$11\.30 = ₡5 876/);
      await pg.click('#recvGo');
      await toasted(pg, /Invoice confirmed · paid ₡0 · open ₡5 876/, 'confirmed in colones');
      assert.strictEqual(sql(`select currency || '|' || fx_rate || '|' || net_fx || '|' || iva_fx || '|' || net_crc || '|' || iva_crc || '|' || total_crc from supplier_invoices`), 'USD|520.00|10.00|1.30|5200.00|676.00|5876.00');
      await until(async () => (await pg.locator('#poDone .po').count()) > 0, 8000, 'in received orders');
      await pg.locator('#poDone .po').first().locator('button', { hasText: /^Details$/ }).click();
      await pg.waitForSelector('#histModal:not([hidden])', { timeout: 5000 });
      assert.match(await text(pg.locator('#histBody')), /Total \$11\.30 at ₡520 = ₡5 876 · open ₡5 876/);
      assert.deepStrictEqual(pg.errors, []);
    }
  }
];
