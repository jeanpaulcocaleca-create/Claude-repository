/* Money in and out of the drawer (migration 0019), and the day's dollar rate typed on Home. */
'use strict';
const assert = require('assert');
const { page, goto, until, sql, pos, openRegister, STAFF, PINS } = require('../lib');

module.exports.tests = [
  {
    name: 'a manager takes cash to the bank: the drawer expects less, the close is exact; a wrong one is voided',
    run: async ({ browser }) => {
      openRegister();
      const pg = await pos(browser);
      await pg.click('#dayBtn');
      await pg.waitForSelector('#cmBtn', { state: 'visible', timeout: 10000 });
      await pg.click('#cmBtn');
      await pg.selectOption('#cmKind', 'out:bank');
      await pg.fill('#cmAmt', '20000');
      await pg.fill('#cmWhy', 'Depósito BCR');
      await pg.selectOption('#cmStaff', STAFF.ana);
      await pg.fill('#cmPin', PINS.ana);
      await pg.click('#regMoveForm button[type=submit]');
      await until(() => sql(`select direction || ':' || purpose || ':' || amount from cash_movements`) === 'out:bank:20000.00', 8000, 'movement saved');
      await until(async () => /Deposit at the bank · Depósito BCR/.test(await pg.locator('#cmList').innerText()), 8000, 'listed on the counter');
      await until(async () => /₡30\s000/.test(await pg.locator('#dayBody').innerText()), 8000, 'expected: ₡50 000 float − ₡20 000');
      assert.strictEqual(await pg.locator('#cmPin').inputValue(), '', 'the PIN never stays on screen');
      // a second one typed wrong, voided with the manager's PIN
      await pg.click('#cmBtn');
      await pg.selectOption('#cmKind', 'out:petty');
      await pg.fill('#cmAmt', '9999');
      await pg.fill('#cmWhy', 'error');
      await pg.selectOption('#cmStaff', STAFF.ana);
      await pg.fill('#cmPin', PINS.ana);
      await pg.click('#regMoveForm button[type=submit]');
      await until(() => sql(`select count(*) from cash_movements`) === '2', 8000, 'second saved');
      await until(async () => (await pg.locator('#cmList button', { hasText: 'Void' }).count()) === 2, 8000, 'void buttons');
      await pg.locator('#cmList button', { hasText: 'Void' }).nth(1).click();
      await until(async () => /type the PIN below/.test(await pg.locator('#cmErr').textContent()), 5000, 'asks for the PIN first');
      await pg.fill('#cmPin', PINS.ana);
      pg.onDialog = (d) => d.accept('monto equivocado');
      await pg.locator('#cmList button', { hasText: 'Void' }).nth(1).click();
      await until(() => sql(`select count(*) from cash_movements where voided_at is not null`) === '1', 8000, 'voided');
      // the close: counted ₡30 000 is exact
      await until(async () => pg.locator('#rcCash').isVisible(), 8000, 'close form');
      await pg.fill('#rcTerminal', '0');
      await pg.fill('#rcCash', '30000');
      await pg.selectOption('#rcStaff', STAFF.ana);
      await pg.fill('#rcPin', PINS.ana);
      await pg.click('#regCloseForm button[type=submit]');
      await until(() => sql(`select cash_diff_crc from register_days where business_date = cr_today()`) === '0', 10000, 'exact close');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'the owner types the day\'s dollar rate on Home when the official one is missing (Spanish)',
    run: async ({ browser }) => {
      const home = await page(browser, { login: 'owner', aal: 'aal2', lang: 'es' });
      await goto(home, '/home');
      await until(async () => home.locator('#fxRow').isVisible(), 10000, 'rate row');
      await until(async () => /Todavía sin tipo de cambio/.test(await home.locator('#fxNow').textContent()), 8000, 'no rate yet, in Spanish');
      await home.fill('#fxBuy', '505.5');
      await home.fill('#fxSell', '512');
      await home.click('#fxGo');
      await until(() => sql(`select buy || '/' || sell || '/' || source from fx_rates`) === '505.50/512.00/manual', 8000, 'saved as typed');
      await until(async () => /₡505\.50 · .* · escrito a mano/.test(await home.locator('#fxNow').textContent()), 8000, 'shown');
      sql(`update fx_rates set source = 'hacienda'`);
      await home.fill('#fxBuy', '400');
      await home.fill('#fxSell', '410');
      await home.click('#fxGo');
      await until(async () => /El tipo oficial de hoy ya está/.test(await home.locator('#setMsg').textContent()), 8000, 'never over the official rate');
      assert.deepStrictEqual(home.errors, []);
    }
  },
  {
    name: 'the accountant sees the day\'s cash in both currencies and files the invoice of a payout',
    run: async ({ browser }) => {
      openRegister();
      sql(`insert into cash_movements (id, business_date, direction, purpose, currency, amount, amount_crc, reason, staff_name)
             values ('7e000000-0000-4000-8000-0000000e2e21', cr_today(), 'out', 'payout', 'CRC', 4500, 4500, 'Leche en el súper', 'Ana')`);
      const pg = await page(browser, { login: 'accountant', lang: 'en' });
      await goto(pg, '/accounting');
      await pg.waitForSelector('#appView:not([hidden])', { timeout: 15000 });
      await pg.click('#tabs [data-view=cash]');
      await until(async () => (await pg.locator('#cTable tbody tr').count()) >= 1, 8000, 'the day');
      assert.match((await pg.locator('#cTable tbody tr').first().innerText()).replace(/\s+/g, ' '), /₡ ₡50 000 ₡0 ₡0 ₡4 500 ₡45 500/, 'float, sales, in, out, expected');
      await until(async () => /Leche en el súper/.test(await pg.locator('#poTable').innerText()), 8000, 'payout to file');
      await pg.locator('#poTable button', { hasText: 'File its invoice' }).click();
      await until(async () => pg.locator('#xDesc').isVisible(), 5000, 'expense form');
      assert.strictEqual(await pg.locator('#xPayout').inputValue(), '7e000000-0000-4000-8000-0000000e2e21', 'the payout is picked');
      assert.strictEqual(await pg.locator('#xAmt').inputValue(), '4500');
      await pg.fill('#xDesc', 'Leche');
      await pg.selectOption('#xAcct', '6299');
      await pg.click('#xGo');
      await until(() => sql(`select paid_from || ':' || payout_id from expenses`) === 'payout:7e000000-0000-4000-8000-0000000e2e21', 8000, 'filed against the payout');
      await pg.click('#tabs [data-view=cash]');
      await until(async () => (await pg.locator('#poTable button', { hasText: 'File its invoice' }).count()) === 0, 8000, 'nothing left to file');
      assert.deepStrictEqual(pg.errors, []);
    }
  }
];
