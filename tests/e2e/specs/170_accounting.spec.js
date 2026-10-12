/* The accounting page (migrations 0013, 0014): the accountant posts a day, reads the reports, records an expense. */
'use strict';
const assert = require('assert');
const { page, goto, until, sql } = require('../lib');

async function books(browser, who) {
  const pg = await page(browser, { login: who || 'accountant', aal: who === 'owner' ? 'aal2' : 'aal1', lang: 'en' });
  await goto(pg, '/accounting');
  await pg.waitForSelector('#appView:not([hidden])', { timeout: 15000 });
  return pg;
}
function closedDay() {
  sql(`insert into register_days (business_date, opened_by_name, float_crc, closed_at, closed_by_name, cash_diff_crc) values (cr_today(), 'Ana', 50000, now(), 'Ana', 0);
       insert into orders (id, created_at, total_crc, payment_method, paid, status) values ('0d000000-0000-4000-8000-0000000e2e71', now(), 2260, 'card', true, 'done');
       insert into order_items (order_id, item_name, price_crc, qty) values ('0d000000-0000-4000-8000-0000000e2e71', 'Mocha', 2260, 1)`);
}

module.exports.tests = [
  {
    name: 'the café login and the accountant: only the accountant opens the books',
    run: async ({ browser }) => {
      const cafe = await page(browser, { login: 'cafe', lang: 'en' });
      await goto(cafe, '/accounting');
      await cafe.waitForSelector('#noView:not([hidden])', { timeout: 15000 });
      const pg = await books(browser);
      assert.strictEqual(await pg.locator('#whoSub').textContent(), 'Accountant');
      assert.strictEqual(await pg.locator('#ownerNav').isVisible(), false, 'no links to the owner areas');
    }
  },
  {
    name: 'a closed day is posted, shows in the journal and the income statement; the CSV downloads',
    run: async ({ browser }) => {
      closedDay();
      const pg = await books(browser);
      await until(async () => /\d{4}-\d\d-\d\d/.test(await pg.locator('#pendingList').textContent()), 8000, 'pending day listed');
      await pg.click('#pendingGo');
      await until(() => sql(`select count(*) from acct.entries where source = 'day'`) === '1', 8000, 'posted');
      await until(async () => (await pg.locator('#kRev').textContent()).replace(/\D/g, '') === '2000', 8000, 'revenue without IVA in the summary');
      await pg.click('#tabs [data-view=journal]');
      await until(async () => /Ventas de alimentos/.test(await pg.locator('#jList').textContent()), 8000, 'entry in the journal');
      const [dl] = await Promise.all([pg.waitForEvent('download'), pg.click('#jCsv')]);
      assert.match(dl.suggestedFilename(), /^diario-.*\.csv$/);
      await pg.click('#tabs [data-view=reports]');
      await pg.selectOption('#rKind', 'is');
      await until(async () => /Net income/.test(await pg.locator('#rOut').textContent()), 8000, 'income statement');
      assert.match(await pg.locator('#rOut').textContent(), /₡2\s000/);
      await pg.selectOption('#rKind', 'bs');
      await until(async () => /Total assets/.test(await pg.locator('#rOut').textContent()), 8000, 'balance sheet');
      assert.doesNotMatch(await pg.locator('#rOut').textContent(), /does not balance/);
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'a manual entry must balance; an expense is posted with its IVA; a month is closed',
    run: async ({ browser }) => {
      const pg = await books(browser);
      await pg.click('#tabs [data-view=journal]');
      await pg.click('#jNew');
      await pg.fill('#nMemo', 'Aporte de capital');
      const rows = pg.locator('#nLines .lrow');
      await rows.nth(0).locator('select').selectOption('1110'); await rows.nth(0).locator('input').nth(0).fill('100000');
      await rows.nth(1).locator('select').selectOption('3101'); await rows.nth(1).locator('input').nth(1).fill('90000');
      await pg.click('#nGo');
      await until(async () => /Debits and credits must be equal/.test(await pg.locator('#nErr').textContent()), 5000, 'unbalanced refused');
      await rows.nth(1).locator('input').nth(1).fill('100000');
      await pg.click('#nGo');
      await until(() => sql(`select count(*) from acct.entries where source = 'manual'`) === '1', 8000, 'manual entry posted');
      await pg.click('#tabs [data-view=expenses]');
      await pg.fill('#xVendor', 'Súper');
      await pg.fill('#xDesc', 'Cloro');
      await pg.selectOption('#xAcct', '6204');
      await pg.fill('#xAmt', '1130');
      await pg.fill('#xIva', '130');
      await pg.click('#xGo');
      await until(() => sql(`select string_agg(l.account || ':' || (l.debit - l.credit), ',' order by l.account) from acct.lines l join acct.entries e on e.id = l.entry_id where e.source = 'expense'`)
                    === '1101:-1130.00,1140:130.00,6204:1000.00', 8000, 'expense posted with its IVA');
      await pg.click('#tabs [data-view=periods]');
      await pg.locator('#pTable button', { hasText: 'Close' }).first().click();
      await until(() => sql(`select status from acct.periods limit 1`) === 'closed', 8000, 'month closed');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'the owner approves the chart and switches on the automatic entries',
    run: async ({ browser }) => {
      const pg = await books(browser, 'owner');
      await pg.waitForSelector('#approveBox:not([hidden])', { timeout: 8000 });
      await pg.fill('#apWho', 'Contadora M. Rojas');
      await pg.fill('#apRef', 'Correo del 12/10');
      await pg.click('#apGo');
      await until(() => sql(`select value::text from settings where key = 'ledger_auto_post'`) === 'true', 8000, 'switched on');
      await until(async () => pg.locator('#setupCard').isHidden(), 8000, 'banner gone');
    }
  }
,
  {
    name: 'an expense keeps a photo of its invoice; the month\'s package downloads as a ZIP with every report',
    run: async ({ browser }) => {
      closedDay();
      const pg = await books(browser);
      await pg.click('#pendingGo');
      await pg.click('#tabs [data-view=expenses]');
      await pg.fill('#xDesc', 'Gas');
      await pg.selectOption('#xAcct', '6299');
      await pg.fill('#xAmt', '5000');
      await pg.setInputFiles('#xFile', { name: 'factura gas.jpg', mimeType: 'image/jpeg', buffer: Buffer.from('fake-jpeg') });
      await pg.click('#xGo');
      await until(() => sql(`select receipt_path from expenses`) !== '', 8000, 'receipt attached');
      assert.match(sql(`select receipt_path from expenses`), /^[0-9a-f-]{36}\/factura_gas\.jpg$/);
      const row = pg.locator('#xTable tbody tr').first();
      await until(async () => (await row.locator('button', { hasText: 'Invoice' }).count()) === 1, 8000, 'invoice button');
      await pg.evaluate(() => { window.open = (u) => { window.__opened = u; return null; }; });
      await row.locator('button', { hasText: 'Invoice' }).click();
      const url = await until(async () => pg.evaluate(() => window.__opened), 5000, 'the invoice link');
      assert.match(url, /\/storage\/v1\/object\/sign\/expense-receipts\//, 'opened from a signed link');
      assert.strictEqual(await pg.evaluate(async (u) => (await fetch(u)).text(), url), 'fake-jpeg');
      await pg.click('#tabs [data-view=reports]');
      const [dl] = await Promise.all([pg.waitForEvent('download'), pg.click('#rPack')]);
      assert.match(dl.suggestedFilename(), /^contabilidad-\d{4}-\d\d\.zip$/);
      const fs = require('fs'); const p = await dl.path(); const z = fs.readFileSync(p);
      assert.strictEqual(z.readUInt32LE(0), 0x04034b50, 'a ZIP file');
      const t = require('child_process').spawnSync('python3', ['-c', 'import zipfile,sys; z=zipfile.ZipFile(sys.argv[1]); print(z.testzip(), len(z.namelist()), z.read("diario.csv").decode("utf-8-sig").splitlines()[0])', p], { encoding: 'utf8' });
      assert.strictEqual(t.stdout.trim(), 'None 9 entry_no,date,source,memo,account,account_name,debit,credit', 'a valid ZIP that opens anywhere: ' + t.stderr);
      const names = z.toString('latin1');
      ['diario.csv', 'balanza.csv', 'estado-resultados.csv', 'balance-general.csv', 'flujo-efectivo.csv', 'gastos.csv', 'iva-ventas.csv', 'iva-compras.csv', 'inventario-valorado-']
        .forEach((n) => assert.ok(names.includes(n), n + ' in the package'));
      assert.deepStrictEqual(pg.errors, []);
    }
  }
];
