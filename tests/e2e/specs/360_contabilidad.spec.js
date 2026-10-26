/* The new accounting page (contabilidad.html, migrations 0034/0035, D-057): the same door as accounting.html, the eight
   sections, the quick «New expense» that learns each supplier's habits and keeps the receipt, the server refusing the café
   login, credit expenses paid from their row, suppliers from both sides, the bank import, the reports, the books, Spanish
   first, a tablet and a phone, and a network failure that explains itself. */
'use strict';
const assert = require('assert');
const fs = require('fs');
const { page, goto, until, sql } = require('../lib');

const VENDOR = 'ab000000-0000-4000-8000-0000000e2e36', PO = '9a000000-0000-4000-8000-0000000e2e36', RC = '7e000000-0000-4000-8000-0000000e2e36';
const ACCOUNTANT = 'ac000000-0000-4000-8000-000000000003';
function asAccountant(q) {   // run q as the accountant (phone code) through the SQL functions, like the page would; returns q's last value
  const out = sql(`select set_config('request.jwt.claims', '{"sub":"${ACCOUNTANT}","role":"authenticated","aal":"aal2"}', false); select set_config('request.jwt.claim.sub', '${ACCOUNTANT}', false); set role authenticated; ${q}; reset role;`);
  return out.split('\n').filter((l) => !/^(SET|RESET)$/.test(l)).pop();
}
/* two closed days with sales, a supplier with a delivery waiting for its invoice, a bank account and a manual deposit */
function seed() {
  sql(`insert into register_days (business_date, opened_by_name, float_crc, closed_at, closed_by_name, cash_diff_crc) values (cr_today() - 1, 'Ana', 50000, now() - interval '1 day', 'Ana', 0), (cr_today() - 2, 'Ana', 50000, now() - interval '2 day', 'Ana', -500);
       insert into orders (id, created_at, business_date, total_crc, payment_method, paid, status) values
         ('0d000000-0000-4000-8000-0000000e2e31', now() - interval '1 day', cr_today() - 1, 2260, 'card', true, 'done'),
         ('0d000000-0000-4000-8000-0000000e2e32', now() - interval '1 day', cr_today() - 1, 4520, 'cash', true, 'done'),
         ('0d000000-0000-4000-8000-0000000e2e33', now() - interval '2 day', cr_today() - 2, 3390, 'sinpe', true, 'done');
       insert into order_items (order_id, item_name, price_crc, qty) values ('0d000000-0000-4000-8000-0000000e2e31', 'Mocha', 2260, 1), ('0d000000-0000-4000-8000-0000000e2e32', 'Mocha', 2260, 2), ('0d000000-0000-4000-8000-0000000e2e33', 'Latte', 3390, 1);
       insert into vendors (id, name, phone, contact_name) values ('${VENDOR}', 'Café de Altura', '8888-0000', 'Don Beto');
       insert into purchase_orders (id, vendor_id, status) values ('${PO}', '${VENDOR}', 'received');
       insert into purchase_receipts (id, po_id, vendor_id, invoice_no, total_crc, final) values ('${RC}', '${PO}', '${VENDOR}', 'F-88', 10000, true);
       insert into bank_accounts (id, name, bank, gl_account, currency) values ('b0000000-0000-4000-8000-0000000e2e36', 'BCR colones', 'BCR', '1110', 'CRC');
       select acct.post(cr_today() - 1, 'Depósito de la caja', 'manual', 'e2e:dep', '[{"account":"1110","debit":30000},{"account":"1101","credit":30000}]'::jsonb, null, 'prueba')`);
}
async function open(browser, who, opts) {
  const pg = await page(browser, Object.assign({ login: who || 'accountant', aal: 'aal2', lang: 'en' }, opts || {}));
  await goto(pg, '/contabilidad');
  await pg.waitForSelector('#appView:not([hidden])', { timeout: 15000 });
  return pg;
}
async function settled(pg) {
  await until(() => pg.evaluate(() => !document.querySelector('.loading')), 15000, 'section loaded');
}
async function section(pg, v) {
  await pg.evaluate((h) => { location.hash = h; }, v);
  await until(() => pg.evaluate((h) => document.querySelector('#nav a[aria-current]') && document.querySelector('#nav a[aria-current]').dataset.view === h, v), 8000, 'section ' + v);
  await settled(pg);
}
async function drawerOpen(pg) {
  await until(() => pg.evaluate(() => document.getElementById('drawer').classList.contains('open') && !document.querySelector('#drawerBody .loading')), 8000, 'drawer open');
}
async function drawerClosed(pg) {
  await until(() => pg.evaluate(() => !document.getElementById('drawer').classList.contains('open')), 8000, 'drawer closed');
}
const typeIn = (pg, sel, v) => pg.evaluate(([s, x]) => { const i = document.querySelector(s); i.value = x; i.dispatchEvent(new Event('input', { bubbles: true })); i.dispatchEvent(new Event('change', { bubbles: true })); }, [sel, v]);
const crDay = (n) => sql(`select (cr_today() + ${n})::text`);

module.exports.tests = [
  {
    name: 'the same door as the old page: the café login and the accountant without the code stay out; the accountant and the owner get in',
    run: async ({ browser }) => {
      seed();
      const cafe = await page(browser, { login: 'cafe', lang: 'en' });
      await goto(cafe, '/contabilidad');
      await cafe.waitForSelector('#noView:not([hidden])', { timeout: 15000 });
      // the server, not the page, is what keeps the café out: a direct call from its session is refused
      const r = await cafe.evaluate(async () => (await db.rpc('expense_save', { p_expense: { description: 'x', account: '6299', amount_crc: 1000, iva_crc: 0, paid_from: 'cash', date: '2026-01-01' }, p_request_id: 'e0000000-0000-4000-8000-0000000e2e99' })).data);
      assert.deepStrictEqual(r, { ok: false, error: 'not_allowed' }, 'expense_save refused for the café login');
      assert.strictEqual(sql(`select count(*) from expenses`), '0');
      const r2 = await cafe.evaluate(async () => (await db.rpc('expense_list', { p_from: '2026-01-01', p_to: '2026-01-31' })).data);
      assert.strictEqual(r2.error, 'not_allowed', 'expense_list refused for the café login');
      const no = await page(browser, { login: 'accountant', aal: 'aal1', lang: 'es' });
      await goto(no, '/contabilidad');
      await no.waitForSelector('#noView:not([hidden])', { timeout: 15000 });
      await until(async () => /código de su teléfono/.test(await no.locator('#noWhy').textContent()), 8000, 'why, in Spanish');
      assert.strictEqual(await no.locator('#enrollStart').isVisible(), true, 'offers to turn the phone code on');
      const pg = await open(browser, 'accountant');
      assert.strictEqual(await pg.locator('#whoSub').textContent(), 'Accountant');
      assert.strictEqual(await pg.locator('#ownerLinks').isVisible(), false, 'no links to the owner areas');
      await section(pg, 'contabilidad');
      assert.strictEqual(await pg.locator('#bookTabs [data-s=act]').count(), 0, 'the activation tab is the owner\'s');
      const ow = await open(browser, 'owner');
      assert.strictEqual(await ow.locator('#ownerLinks').isVisible(), true);
      await section(ow, 'contabilidad');
      assert.strictEqual(await ow.locator('#bookTabs [data-s=act]').count(), 1);
      assert.deepStrictEqual(pg.errors.concat(ow.errors, cafe.errors), []);
    }
  },
  {
    name: 'overview and income: the closed days are counted, posted from the page, and each day opens with its entry',
    run: async ({ browser }) => {
      seed();
      const pg = await open(browser);
      await settled(pg);
      await until(async () => /2 closed days not in the books/.test(await pg.locator('#view').textContent()), 8000, 'pending days in the overview');
      assert.match((await pg.locator('#view .kpi').first().textContent()).replace(/\s/g, ''), /₡9000/, 'revenue without IVA of the two days (2000 + 4000 + 3000)');
      await section(pg, 'ingresos');
      await until(async () => (await pg.locator('#tbl-dias tbody tr.row').count()) === 2, 8000, 'two days in the table');
      await pg.click('#postAll');
      await until(() => sql(`select count(*) from acct.entries where source = 'day'`) === '2', 10000, 'both days posted');
      await until(async () => (await pg.locator('#tbl-dias tbody').textContent()).indexOf('to post') < 0, 8000, 'the table shows them posted');
      await pg.click('#tbl-dias tbody tr.row >> nth=0');
      await drawerOpen(pg);
      await until(async () => /Ventas de alimentos/.test(await pg.locator('#drawerBody').textContent()), 8000, 'the day\'s entry in the drawer');
      assert.strictEqual(await pg.locator('#osGo').count(), 0, 'the receipt search is the owner\'s');
      await pg.click('#drawerClose');
      await drawerClosed(pg);
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'quick expense: the first time it asks category, IVA and payment and remembers them; the second time supplier + amount is enough; the receipt is kept privately',
    run: async ({ browser }) => {
      seed();
      // receipt files from the new page need the owner's switch (off until the private files are backed up, E-17)
      const off = await open(browser, 'accountant', { lang: 'es' });
      await section(off, 'gastos');
      await off.click('#btnNew');
      await drawerOpen(off);
      assert.strictEqual(await off.locator('#ef-photo').count(), 0, 'no photo button while the switch is off');
      assert.match(await off.locator('#ef-noreceipt').textContent(), /E-17/);
      await off.context().close();
      sql(`insert into public.settings (key, value, updated_by) values ('expense_receipt_photos', 'true', 'prueba') on conflict (key) do update set value = 'true'`);
      const pg = await open(browser, 'accountant', { lang: 'es' });
      await section(pg, 'gastos');
      await pg.click('#btnNew');
      await drawerOpen(pg);
      await typeIn(pg, '#ef-vendor', 'Café de Altura');
      await typeIn(pg, '#ef-total', '11300');
      await until(() => pg.evaluate(() => !document.getElementById('ef-ask').hidden && !!document.querySelector('#ef-ask #ef-cat')), 5000, 'asks for what the supplier has no habit of');
      await until(async () => /aún le falta lo habitual de: categoría, IVA, pagado con/.test(await pg.locator('#ef-ask .ask-hint').textContent()), 5000, 'the hint, in Spanish');
      await pg.click('#ef-save');
      await until(async () => /Indique lo que falta/.test(await pg.locator('#drawerFoot').textContent()), 5000, 'refuses to guess');
      await pg.selectOption('#ef-cat', '5101');
      await pg.selectOption('#ef-rate', '0.13');
      await pg.selectOption('#ef-pm', 'cash');
      await until(async () => /5101/.test(await pg.locator('#ef-resolved').textContent()) && /1\s300/.test(await pg.locator('#ef-resolved').textContent()), 5000, 'the IVA is worked out from the rate');
      assert.strictEqual(await pg.locator('#ef-remember').isChecked(), true, 'remembers by default');
      await pg.setInputFiles('#ef-doc', { name: 'factura café.jpg', mimeType: 'image/jpeg', buffer: Buffer.from('fake-jpeg') });
      await until(async () => /factura café\.jpg/.test(await pg.locator('#ef-fname').textContent()), 3000, 'file named');
      await pg.click('#ef-save');
      await until(() => sql(`select count(*) from expenses where vendor_id = '${VENDOR}'`) === '1', 10000, 'expense saved');
      assert.strictEqual(sql(`select account || ':' || amount_crc || ':' || iva_crc || ':' || paid_from || ':' || description from expenses`), '5101:11300.00:1300.00:cash:Café de Altura', 'account, IVA from the 13 %, cash, the supplier as description');
      assert.match(sql(`select receipt_path from expenses`), /^[0-9a-f-]{36}\/factura_caf.*\.jpg$/, 'the receipt is stored under the expense');
      assert.strictEqual(sql(`select default_account || ':' || default_paid_from || ':' || default_iva_rate from vendors where id = '${VENDOR}'`), '5101:cash:0.1300', 'the habits were remembered');
      assert.strictEqual(sql(`select string_agg(l.account || ':' || (l.debit - l.credit), ',' order by l.account) from acct.lines l join acct.entries e on e.id = l.entry_id where e.source = 'expense'`), '1101:-11300.00,1140:1300.00,5101:10000.00', 'posted with its IVA credit');
      await drawerClosed(pg);
      // second time: supplier and amount only
      await pg.click('#btnNew');
      await drawerOpen(pg);
      await typeIn(pg, '#ef-vendor', 'Café de Altura');
      await typeIn(pg, '#ef-total', '22600');
      await until(() => pg.evaluate(() => document.getElementById('ef-ask').hidden), 5000, 'nothing to ask');
      await until(async () => /de lo habitual del proveedor/.test(await pg.locator('#ef-resolved').textContent()), 5000, 'says the habits were used');
      await pg.click('#ef-save');
      await until(() => sql(`select count(*) from expenses where vendor_id = '${VENDOR}'`) === '2', 10000, 'second expense saved');
      assert.strictEqual(sql(`select account || ':' || iva_crc || ':' || paid_from from expenses where amount_crc = 22600`), '5101:2600.00:cash');
      // the receipt opens from a signed link (private bucket) and the table shows it attached
      await until(async () => (await pg.locator('#tbl-gastos tbody tr.row').count()) === 2, 8000, 'both in the table');
      await pg.evaluate(() => { window.open = (u) => { window.__opened = u; return null; }; });
      await pg.locator('#tbl-gastos tbody tr.row', { hasText: '11 300' }).click();
      await drawerOpen(pg);
      await pg.click('#xd-open');
      const url = await until(() => pg.evaluate(() => window.__opened), 5000, 'the receipt link');
      assert.match(url, /\/storage\/v1\/object\/sign\/expense-receipts\//, 'a signed link, never a public one');
      assert.strictEqual(await pg.evaluate(async (u) => (await fetch(u)).text(), url), 'fake-jpeg');
      // void with a reason: a reversal, never a deletion
      pg.onDialog = (d) => d.accept('se duplicó');
      await pg.click('#xd-void');
      await until(() => sql(`select count(*) from expenses where voided_at is not null`) === '1', 8000, 'voided');
      assert.strictEqual(sql(`select count(*) from expenses`), '2', 'nothing deleted');
      assert.strictEqual(sql(`select count(*) from acct.entries where source = 'reversal'`), '1', 'the reversal entry');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'a credit expense is paid from its row, partly then fully, against the same payable; a recurring bill reminds and pre-fills but never posts on its own',
    run: async ({ browser }) => {
      seed();
      asAccountant(`select expense_save(jsonb_build_object('vendor_id', '${VENDOR}', 'description', 'Leche', 'account', '5101', 'amount_crc', 20000, 'iva_crc', 0, 'paid_from', 'credit', 'date', (cr_today() - 2)::text), 'e0000000-0000-4000-8000-0000000e2e02');
                    select expense_schedule_save(jsonb_build_object('vendor_id', '${VENDOR}', 'description', 'Alquiler', 'account', '6201', 'amount_crc', 350000, 'paid_from', 'bank', 'every', 'month', 'day_of', extract(day from cr_today() + 2)::int, 'next_due', (cr_today() + 2)::text))`);
      const pg = await open(browser);
      await section(pg, 'gastos');
      await until(async () => (await pg.locator('#tbl-gastos [data-act=pay]').count()) === 1, 8000, 'the pay button on the credit row');
      await pg.click('#tbl-gastos [data-act=pay]');
      await drawerOpen(pg);
      await typeIn(pg, '#pf-amt', '8000');
      await pg.selectOption('#pf-pm', 'bank');
      await pg.click('#pf-save');
      await until(() => sql(`select count(*) from expense_payments`) === '1', 8000, 'partial payment');
      assert.strictEqual(sql(`select string_agg(l.account || ':' || (l.debit - l.credit), ',' order by l.account) from acct.lines l join acct.entries e on e.id = l.entry_id where e.source_key like 'exppay:%'`), '1110:-8000.00,2101:8000.00', 'bank → payable');
      await until(async () => /owes.*12\s000/.test((await pg.locator('#tbl-gastos tbody').textContent())), 8000, 'still owes 12 000');
      await pg.click('#tbl-gastos [data-act=pay]');
      await drawerOpen(pg);
      await typeIn(pg, '#pf-amt', '13000');
      await pg.selectOption('#pf-pm', 'bank');
      await pg.click('#pf-save');
      await until(async () => /more than is owed/.test(await pg.locator('#drawerFoot').textContent()), 5000, 'never more than what is owed');
      await typeIn(pg, '#pf-amt', '12000');
      await pg.click('#pf-save');
      await until(() => sql(`select count(*) from expense_payments`) === '2', 8000, 'paid in full');
      assert.strictEqual(Number(sql(`select coalesce(sum(_expense_open(id)), 0) from expenses where paid_from = 'credit'`)), 0, 'nothing open on credit');
      assert.strictEqual(Number(asAccountant(`select (ap_aging(null)->'ledger'->>'expenses_on_credit')`)), 0, 'nothing open in the aging');
      await until(async () => (await pg.locator('#tbl-gastos [data-act=pay]').count()) === 0, 8000, 'no pay button left');
      // the recurring bill: due in two days, shown, pre-fills the form; nothing posted until confirmed
      await until(async () => /Alquiler/.test(await pg.locator('#view').textContent()), 8000, 'due bill listed');
      assert.strictEqual(sql(`select count(*) from expenses where description = 'Alquiler'`), '0', 'nothing posted on its own');
      await pg.click('[data-due]');
      await drawerOpen(pg);
      assert.strictEqual(await pg.locator('#ef-total').inputValue(), '350000', 'amount pre-filled');
      assert.strictEqual(await pg.locator('#ef-vendor').inputValue(), 'Café de Altura');
      assert.strictEqual(await pg.locator('#ef-date').inputValue(), crDay(0), 'registered on the day it is paid, not the due date');
      await pg.fill('#ef-date', crDay(2));
      await pg.click('#ef-save');
      await until(async () => /future/.test(await pg.locator('#drawerFoot').textContent()), 5000, 'a future date is refused by the server');
      await pg.fill('#ef-date', crDay(0));
      await pg.click('#ef-save');
      await until(() => sql(`select count(*) from expenses where description = 'Alquiler'`) === '1', 10000, 'registered on confirmation');
      assert.strictEqual(sql(`select next_due > cr_today() + 2 from expense_schedules`), 't', 'the reminder moved to the next month');
      assert.strictEqual(sql(`select period_key::text from expenses where description = 'Alquiler'`), crDay(2), 'tied to its period');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'suppliers from both sides: the owner adds one, its card shows deliveries and balances, the invoice settles the delivery, the accountant consults but does not edit',
    run: async ({ browser }) => {
      seed();
      const ow = await open(browser, 'owner');
      await section(ow, 'proveedores');
      await ow.click('#btnVendor');
      await drawerOpen(ow);
      await ow.fill('#vf-name', 'Lácteos Monteverde');
      await ow.fill('#vf-phone', '2645-0000');
      await ow.fill('#vf-credit', '15');
      await ow.click('#vf-save');
      await until(() => sql(`select credit_days::text from vendors where name = 'Lácteos Monteverde'`) === '15', 8000, 'vendor saved with its credit days');
      assert.strictEqual(sql(`select count(*) from audit_log where action = 'vendor_save'`), '1', 'audited');
      await until(async () => /Lácteos Monteverde/.test(await ow.locator('#drawerTitle').textContent()), 8000, 'the new supplier\'s card opens');
      await ow.click('#drawerClose');
      await drawerClosed(ow);
      await until(async () => (await ow.locator('#tbl-prov tbody tr.row').count()) === 2, 8000, 'two suppliers listed');
      await ow.locator('#tbl-prov tbody tr.row', { hasText: 'Café de Altura' }).click();
      await drawerOpen(ow);
      await until(async () => /F-88/.test(await ow.locator('#drawerBody').textContent()), 8000, 'the delivery waiting for its invoice');
      await ow.click('#vc-inv');
      await drawerOpen(ow);
      await until(() => ow.evaluate(() => !!document.querySelector('#drawerBody [data-rec]')), 8000, 'the delivery offered');
      await ow.check('#drawerBody [data-rec]');
      await ow.fill('#vi-num', 'F-88');
      await ow.fill('#vi-net', '10000');
      await ow.fill('#vi-iva', '1300');
      await ow.click('#vi-save');
      await until(() => sql(`select number || ':' || total_crc from supplier_invoices`) === 'F-88:11300.00', 8000, 'invoice saved');
      assert.strictEqual(sql(`select invoice_id is not null from purchase_receipts`), 't', 'the delivery points to its invoice');
      await section(ow, 'compras');
      await until(async () => (await ow.locator('#tbl-po tbody tr.row').count()) === 1, 8000, 'the order in Purchases');
      assert.match(await ow.locator('#tbl-po tbody tr.row').textContent(), /invoiced/);
      // the accountant sees the card, can set the habits, cannot edit the supplier itself
      const pg = await open(browser, 'accountant');
      await section(pg, 'proveedores');
      assert.strictEqual(await pg.locator('#btnVendor').count(), 0, 'no new-supplier button');
      await pg.locator('#tbl-prov tbody tr.row', { hasText: 'Café de Altura' }).click();
      await drawerOpen(pg);
      assert.strictEqual(await pg.locator('#vc-edit').count(), 0, 'no edit button');
      await pg.click('#vc-habits');
      await drawerOpen(pg);
      await pg.selectOption('#vd-cat', '5101');
      await pg.selectOption('#vd-pm', 'credit');
      await pg.click('#vd-save');
      await until(() => sql(`select default_account || ':' || default_paid_from from vendors where id = '${VENDOR}'`) === '5101:credit', 8000, 'habits saved by the accountant');
      const r = await pg.evaluate(async () => (await db.rpc('vendor_save', { p_vendor: { name: 'Otro' } })).data);
      assert.strictEqual(r.error, 'not_allowed', 'the server refuses the accountant a new supplier');
      assert.deepStrictEqual(ow.errors.concat(pg.errors), []);
    }
  },
  {
    name: 'bank: the statement is imported from the bank\'s CSV, a deposit matches the books, a fee is posted; nothing talks to the bank',
    run: async ({ browser }) => {
      seed();
      const pg = await open(browser, 'owner');
      await section(pg, 'banco');
      await pg.click('#bankTabs [data-s=bank]');
      await settled(pg);
      await pg.click('#bkImportBtn');
      await drawerOpen(pg);
      const d = (n) => { const x = crDay(n).split('-'); return x[2] + '/' + x[1] + '/' + x[0]; };
      const csv = '﻿Fecha;Descripción;Referencia;Débito;Crédito;Saldo\n' + d(-1) + ';DEPOSITO EFECTIVO;1001;;30.000,00;130.000,00\n' + d(-1) + ';COMISION MANTENIMIENTO;1002;350,00;;129.650,00\n';
      await pg.setInputFiles('#bk-file', { name: 'bcr.csv', mimeType: 'text/csv', buffer: Buffer.from(csv, 'utf8') });
      await until(() => pg.evaluate(() => !document.getElementById('bk-map').hidden && !document.getElementById('bk-import').disabled), 8000, 'preview');
      assert.match(await pg.locator('#bk-note').textContent(), /2 movements/);
      await pg.click('#bk-import');
      await until(() => sql(`select count(*) from bank_lines`) === '2', 8000, 'imported');
      await drawerClosed(pg);
      await until(async () => (await pg.locator('#tbl-bank [data-act=match]').count()) === 1, 8000, 'the deposit has a suggestion');
      await pg.click('#tbl-bank [data-act=match]');
      await until(() => sql(`select status from bank_lines where amount = 30000`) === 'matched', 8000, 'matched to the manual deposit');
      await pg.locator('#tbl-bank tbody tr.row', { hasText: 'COMISION' }).locator('[data-act=post]').click();
      await drawerOpen(pg);
      await pg.selectOption('#bp-a1', '6208');
      await pg.click('#bp-save');
      await until(() => sql(`select string_agg(l.account || ':' || (l.debit - l.credit), ',' order by l.account) from acct.lines l join acct.entries e on e.id = l.entry_id where e.source = 'bank'`) === '1110:-350.00,6208:350.00', 8000, 'fee posted');
      await until(async () => (await pg.locator('#tbl-bank [data-act=post]').count()) === 0, 8000, 'nothing left to reconcile');
      assert.strictEqual(pg.supabaseHits, 0, 'nothing left the test machine');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'reports: the income statement compares with the previous period, each report downloads as CSV, the month\'s package is a valid ZIP',
    run: async ({ browser }) => {
      seed();
      asAccountant(`select acct_post_days(cr_today() - 2, cr_today())`);
      const pg = await open(browser);
      await section(pg, 'reportes');
      await until(async () => /Gross margin/.test(await pg.locator('#repBody').textContent()), 8000, 'income statement');
      assert.match((await pg.locator('#repBody').textContent()).replace(/\s/g, ''), /Revenue,noIVA\(refundsalreadydeducted\)₡9000/);
      const [dl] = await Promise.all([pg.waitForEvent('download'), pg.click('#rCsv')]);
      assert.match(dl.suggestedFilename(), /^estado-resultados-.*\.csv$/);
      await pg.click('#repGrid [data-r=iva]');
      await until(async () => /IVA charged on sales/.test(await pg.locator('#repBody').textContent()), 8000, 'IVA draft');
      assert.match((await pg.locator('#repBody').textContent()).replace(/\s/g, ''), /IVAchargedonsales₡1170/, '13 % of 9 000');
      await pg.click('#repGrid [data-r=bs]');
      await until(async () => /Total assets/.test(await pg.locator('#repBody').textContent()), 8000, 'balance sheet');
      assert.doesNotMatch(await pg.locator('#repBody').textContent(), /does not balance/);
      const [zip] = await Promise.all([pg.waitForEvent('download'), pg.click('#rPack')]);
      assert.match(zip.suggestedFilename(), /^contabilidad-\d{4}-\d\d\.zip$/);
      const p = await zip.path();
      const t = require('child_process').spawnSync('python3', ['-c', 'import zipfile,sys; z=zipfile.ZipFile(sys.argv[1]); print(z.testzip(), len(z.namelist()), z.read("diario.csv").decode("utf-8-sig").splitlines()[0])', p], { encoding: 'utf8' });
      assert.strictEqual(t.stdout.trim(), 'None 9 entry_no,date,source,memo,account,account_name,debit,credit', 'a valid ZIP with the nine files: ' + t.stderr);
      assert.ok(fs.readFileSync(p).toString('latin1').includes('iva-compras.csv'));
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'books: a manual entry must balance, a manual entry is reversed with a reason, a day entry is not, a month closes',
    run: async ({ browser }) => {
      seed();
      asAccountant(`select acct_post_days(cr_today() - 2, cr_today())`);
      const pg = await open(browser);
      await section(pg, 'contabilidad');
      await until(async () => (await pg.locator('#tbl-diario tbody tr.row').count()) === 3, 8000, 'three entries (deposit + two days)');
      await pg.click('#jNew');
      await drawerOpen(pg);
      await pg.fill('#ne-memo', 'Aporte de capital');
      const rows = pg.locator('#ne-lines .lrow');
      await rows.nth(0).locator('select').selectOption('1110'); await rows.nth(0).locator('input').nth(0).fill('100000');
      await rows.nth(1).locator('select').selectOption('3101'); await rows.nth(1).locator('input').nth(1).fill('90000');
      await pg.click('#ne-save');
      await until(async () => /Debits and credits must be equal/.test(await pg.locator('#drawerFoot').textContent()), 5000, 'unbalanced refused by the server');
      await rows.nth(1).locator('input').nth(1).fill('100000');
      await pg.click('#ne-save');
      await until(() => sql(`select count(*) from acct.entries where memo = 'Aporte de capital'`) === '1', 8000, 'posted');
      await drawerClosed(pg);
      await pg.locator('#tbl-diario tbody tr.row', { hasText: 'Aporte de capital' }).click();
      await drawerOpen(pg);
      await pg.fill('#rv-why', 'cuenta equivocada');
      await pg.click('#rv-go');
      await until(() => sql(`select count(*) from acct.entries where source = 'reversal'`) === '1', 8000, 'reversed');
      await drawerClosed(pg);
      await pg.locator('#tbl-diario tbody tr.row').filter({ has: pg.locator('.tag', { hasText: /^Day$/ }) }).first().click();
      await drawerOpen(pg);
      assert.strictEqual(await pg.locator('#rv-go').count(), 0, 'a day entry is undone from its document, not here');
      await pg.click('#rv-cancel');
      await pg.click('#bookTabs [data-s=periodos]');
      await settled(pg);
      await pg.locator('#bookBody button[data-to=closed]').first().click();
      await until(() => sql(`select count(*) from acct.periods where status = 'closed'`) === '1', 8000, 'month closed');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'Spanish first on the staff page, English on the switch; a tablet shows the rail, a phone the menu button; a lost connection explains itself',
    run: async ({ browser, setOffline }) => {
      seed();
      const pg = await open(browser, 'accountant', { lang: undefined });
      await settled(pg);
      assert.strictEqual(await pg.locator('#nav a[data-view=resumen] span').textContent(), 'Resumen');
      assert.strictEqual(await pg.locator('#title').textContent(), 'Resumen');
      const nav = await pg.locator('#nav').textContent();
      ['Gastos', 'Proveedores', 'Ingresos', 'Compras', 'Banco y efectivo', 'Reportes', 'Contabilidad'].forEach((w) => assert.ok(nav.includes(w), w + ' in the menu'));
      assert.doesNotMatch(await pg.locator('#view').textContent(), /Revenue|Expenses|Pending|See ›/, 'no English left in the Spanish overview');
      await pg.click('.hg-lang button[lang=en]');
      await until(async () => (await pg.locator('#title').textContent()) === 'Overview', 5000, 'English on the switch');
      // tablet: the rail
      const tb = await page(browser, { login: 'accountant', aal: 'aal2', lang: 'es', viewport: { width: 820, height: 1180 } });
      await goto(tb, '/contabilidad');
      await tb.waitForSelector('#appView:not([hidden])', { timeout: 15000 });
      await settled(tb);
      const sideW = await tb.evaluate(() => document.getElementById('side').getBoundingClientRect().width);
      assert.ok(sideW > 80 && sideW < 140, 'the sidebar is a rail on a tablet: ' + sideW);
      assert.strictEqual(await tb.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), true, 'no horizontal scroll');
      // phone: the menu button opens the sidebar; the quick expense fits
      const ph = await page(browser, { login: 'accountant', aal: 'aal2', lang: 'es', viewport: { width: 390, height: 800 } });
      await goto(ph, '/contabilidad');
      await ph.waitForSelector('#appView:not([hidden])', { timeout: 15000 });
      await settled(ph);
      assert.strictEqual(await ph.locator('#menuBtn').isVisible(), true);
      await ph.click('#menuBtn');
      await until(() => ph.evaluate(() => document.getElementById('side').classList.contains('open')), 3000, 'sidebar open');
      await ph.click('#nav a[data-view=gastos]');
      await until(() => ph.evaluate(() => location.hash === '#gastos' && !document.getElementById('side').classList.contains('open')), 5000, 'navigated and closed');
      await settled(ph);
      await ph.click('#btnNew');
      await drawerOpen(ph);
      assert.strictEqual(await ph.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), true, 'the drawer fits the phone');
      assert.strictEqual(await ph.locator('#ef-total').getAttribute('inputmode'), 'decimal', 'the phone keyboard for the amount');
      await ph.click('#ef-cancel');
      // the connection drops: the section says so and offers to try again
      setOffline(true);
      await section(pg, 'proveedores').catch(() => {});
      await until(async () => (await pg.locator('#retryBtn').count()) === 1, 10000, 'the error banner');
      assert.match(await pg.locator('#view').textContent(), /Could not load this section/);
      setOffline(false);
      await pg.click('#retryBtn');
      await until(async () => (await pg.locator('#tbl-prov tbody tr.row').count()) === 1, 10000, 'loaded on retry');
      assert.deepStrictEqual(pg.errors.concat(tb.errors, ph.errors), []);
    }
  },
  {
    name: "Home's accounting tile opens the new page and reads in Spanish (the tile text changed with D-057)",
    run: async ({ browser }) => {
      const pg = await page(browser, { login: 'owner', aal: 'aal2', lang: 'es' });
      await goto(pg, '/home');
      const tile = pg.locator('a.tile[href="contabilidad.html"]');
      await until(async () => (await tile.count()) === 1, 10000, 'the accounting tile');
      // lang.js translates right after the page writes the English text
      await until(async () => (await tile.locator('.d').textContent()) === 'Ingresos, gastos con sus comprobantes, proveedores, banco y efectivo, reportes y los libros para el contador.', 5000, 'tile text in Spanish');
      assert.strictEqual(await pg.locator('a.tile[href="accounting.html"]').count(), 0, 'Home no longer opens the old page');
      assert.deepStrictEqual(pg.errors, []);
    }
  }
];
