/* Payroll (migrations 0021, 0022): the owner approves the hours, sets the rate, prepares the payroll; the accountant reviews, posts and pays. */
'use strict';
const assert = require('assert');
const { page, goto, until, sql, STAFF } = require('../lib');

function crDay(offset) { return new Date(Date.now() - 6 * 3600000 + offset * 86400000).toISOString().slice(0, 10); }
async function payroll(browser, who) {
  const pg = await page(browser, { login: who, aal: who === 'owner' ? 'aal2' : 'aal1', lang: 'en' });
  await goto(pg, '/accounting');
  await pg.waitForSelector('#appView:not([hidden])', { timeout: 15000 });
  await pg.click('#tabs [data-view=payroll]');
  return pg;
}

module.exports.tests = [
  {
    name: 'hours approved by the owner, paid by the hour; the accountant reviews, posts and pays; labor cost in the reports',
    run: async ({ browser }) => {
      sql(`insert into time_entries (staff_id, clock_in, clock_out) values
             ('${STAFF.ana}', cr_day_start(cr_today() - 15) + interval '7 hours', cr_day_start(cr_today() - 15) + interval '15 hours'),
             ('${STAFF.ana}', cr_day_start(cr_today() - 14) + interval '7 hours', cr_day_start(cr_today() - 14) + interval '15 hours'),
             ('${STAFF.ana}', cr_day_start(cr_today() - 13) + interval '7 hours', cr_day_start(cr_today() - 13) + interval '15 hours')`);
      const own = await payroll(browser, 'owner');
      await own.click('#ppNew');
      await own.fill('#ppFrom', crDay(-20));
      await own.fill('#ppTo', crDay(-7));
      await own.click('#ppSave');
      await until(async () => /Ana\s+24\s+3/.test(await own.locator('#tsTable').innerText()), 8000, 'Ana: 24 hours in 3 shifts');
      own.onDialog = (d) => d.accept();
      await own.click('#tsApprove');
      await until(() => sql(`select status from pay_periods`) === 'approved', 8000, 'approved');
      // Ana's rate
      await until(async () => (await own.locator('#rtTable tr', { hasText: 'Ana' }).count()) === 1, 8000, 'rates listed');
      await own.locator('#rtTable tr', { hasText: 'Ana' }).locator('button').click();
      await own.fill('#rtRate', '2500');
      await own.fill('#rtFrom', crDay(-30));
      await own.click('#rtSave');
      await until(() => sql(`select rate_crc from staff_pay`) === '2500.00', 8000, 'rate saved');
      await until(async () => own.locator('#prPrepare').isVisible(), 8000, 'prepare button');
      await own.click('#prPrepare');
      await until(async () => /Ana\s+24\s+₡2\s500 \/h\s+₡60\s000/.test(await own.locator('#prTable').innerText()), 8000, 'gross from the approved hours');
      assert.match(await own.locator('#prState').textContent(), /gross pay only/);
      assert.strictEqual(await own.locator('#prReview').isVisible(), false, 'only the accountant reviews');
      assert.deepStrictEqual(own.errors, []);

      const acc = await payroll(browser, 'accountant');
      await until(async () => acc.locator('#prReview').isVisible(), 8000, 'review button for the accountant');
      await acc.click('#prReview');
      await until(() => sql(`select status from payroll_runs`) === 'reviewed', 8000, 'reviewed');
      acc.onDialog = (d) => d.accept();
      await until(async () => acc.locator('#prPost').isVisible(), 8000, 'post button');
      await acc.click('#prPost');
      await until(() => sql(`select status from payroll_runs`) === 'posted', 8000, 'posted');
      await until(async () => acc.locator('#prPay').isVisible(), 8000, 'pay button');
      await acc.click('#prPay');
      await until(() => sql(`select status from pay_periods`) === 'paid', 8000, 'paid');
      assert.strictEqual(sql(`select sum(debit - credit) from acct.lines where account = '2130'`), '0.00', 'net salaries settled');
      assert.strictEqual(sql(`select sum(debit - credit) from acct.lines where account = '6101'`), '60000.00', 'salaries expense');
      await acc.click('#tabs [data-view=reports]');
      await acc.fill('#rFrom', crDay(-20));
      await acc.fill('#rTo', crDay(-7));
      await acc.selectOption('#rKind', 'labor');
      await until(async () => /Total\s+24\s+₡60\s000/.test(await acc.locator('#rOut').innerText()), 8000, 'labor cost of the period');
      assert.deepStrictEqual(acc.errors, []);
    }
  }
];
