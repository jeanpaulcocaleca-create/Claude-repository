/* Costa Rican payroll (migration 0026): the accountant sees the income tax worked out from the confirmed table, adds extra pay,
   prints a payslip, posts the payroll, reads the month for the CCSS and the INS, the aguinaldo, the vacations and a settlement estimate. */
'use strict';
const assert = require('assert');
const { page, goto, until, sql, STAFF } = require('../lib');

function crDay(offset) { return new Date(Date.now() - 6 * 3600000 + offset * 86400000).toISOString().slice(0, 10); }
async function payroll(browser, who) {
  const pg = await page(browser, { login: who, aal: 'aal2', lang: 'en' });
  await goto(pg, '/accounting');
  await pg.waitForSelector('#appView:not([hidden])', { timeout: 15000 });
  await pg.click('#tabs [data-view=payroll]');
  return pg;
}

module.exports.tests = [
  {
    name: 'income tax from the confirmed table, extra pay, payslip, the month for the CCSS and the INS, aguinaldo, vacations, settlement',
    run: async ({ browser }) => {
      // an approved 14-day period; Marta on a fixed pay with one child; CCSS and INS rules; the tax table; the owner's confirmation and the two settings on
      sql(`insert into pay_periods (id, starts_on, ends_on, status, approved_by, approved_at, created_by)
             values ('ae000000-0000-4000-8000-000000002601', '${crDay(-20)}', '${crDay(-7)}', 'approved', 'Dueño', now() - interval '1 minute', 'test');
           insert into staff_pay (staff_id, kind, rate_crc, effective_from, created_by) values ('${STAFF.marta}', 'period', 1400000, '${crDay(-30)}', 'test');
           insert into staff_profile (staff_id, id_number, hired_on, contract, children, updated_by) values ('${STAFF.marta}', '155812345678', '${crDay(-400)}', 'indefinido', 1, 'test');
           insert into payroll_rules (code, name, kind, pct, confirmed_by, reference, category) values
             ('ccss_obrero', 'CCSS trabajador', 'employee', 10.5, 'Contadora', 'prueba', 'ccss'), ('ins_rt', 'INS riesgos del trabajo', 'employer', 1.5, 'Contadora', 'prueba', 'ins');
           insert into payroll_params (key, value, confirmed_by, reference, updated_by) values
             ('renta', '{"brackets": [{"upto": 922000, "pct": 0}, {"upto": 1352000, "pct": 10}, {"upto": null, "pct": 15}], "credit_child": 1720, "credit_spouse": 2600, "method": "prorate"}', 'Contadora', 'prueba', 'test');
           insert into compliance_confirmations (key, confirmed_by, reference) values ('payroll_cr_rules', 'Contadora', 'Oficio 7-2026');
           insert into settings (key, value, updated_by) values ('payroll_renta_withhold', 'true', 'test'), ('payroll_accrue_aguinaldo', 'true', 'test')`);
      const acc = await payroll(browser, 'accountant');
      await until(async () => acc.locator('#prPrepare').isVisible(), 8000, 'prepare button');
      await acc.click('#prPrepare');
      // 1 400 000 in 14 days: 3 000 000 a month -> 290 200 - 1 720 = 288 480 -> 134 624 for the period, flagged as taken to a month
      await until(async () => /Marta[\s\S]*₡134\s624/.test(await acc.locator('#prTable').innerText()), 8000, 'income tax column');
      assert.match(await acc.locator('#prTable').innerText(), /×30\/14/, 'the prorating is flagged on the line');
      assert.match(await acc.locator('#prState').textContent(), /income tax withheld · aguinaldo provisioned/);
      // extra pay on the draft line: the tax and the rules apply to it
      await acc.locator('#prTable input[aria-label="Extra pay"]').fill('10000');
      await acc.locator('#prTable input[aria-label="What for"]').first().fill('bono');
      await acc.locator('#prTable tr', { hasText: 'Marta' }).locator('button', { hasText: 'Save' }).first().click();
      await until(() => sql(`select extra_crc from payroll_lines where staff_id = '${STAFF.marta}'`) === '10000.00', 8000, 'extra pay saved');
      assert.strictEqual(sql(`select deductions_crc from payroll_lines where staff_id = '${STAFF.marta}'`), '148050.00', 'CCSS on 1 410 000');
      // the payslip, in Spanish, on the page
      await until(async () => (await acc.locator('#prTable button', { hasText: 'Payslip' }).count()) === 1, 8000, 'payslip button');
      await acc.locator('#prTable button', { hasText: 'Payslip' }).click();
      await until(async () => acc.locator('#slip').isVisible(), 8000, 'payslip shown');
      const slip = await acc.locator('#slipBody').innerText();
      assert.match(slip, /Marta/); assert.match(slip, /155812345678/); assert.match(slip, /Retención del impuesto sobre la renta/); assert.match(slip, /Salario neto/);
      await acc.click('#slipClose');
      // the Costa Rican rules card shows the state and the table
      assert.match(await acc.locator('#crState').textContent(), /Confirmation "payroll_cr_rules" recorded · Income tax withholding on · Aguinaldo provision on/);
      assert.strictEqual(await acc.locator('#rbTable tbody tr').count(), 3, 'three brackets');
      assert.match(await acc.locator('#crRentaState').textContent(), /Confirmed by Contadora · prueba/);
      // reviewed and posted by the accountant
      await acc.click('#prReview');
      await until(() => sql(`select status from payroll_runs`) === 'reviewed', 8000, 'reviewed');
      acc.onDialog = (d) => d.accept();
      await until(async () => acc.locator('#prPost').isVisible(), 8000, 'post button');
      await acc.click('#prPost');
      await until(() => sql(`select status from payroll_runs`) === 'posted', 8000, 'posted');
      assert.strictEqual(sql(`select sum(credit) from acct.lines where account = '2140'`), '136124.00', 'income tax owed to Hacienda (on 1 410 000)');
      assert.strictEqual(sql(`select sum(credit) from acct.lines where account = '2133'`), '21150.00', 'the INS policy apart');
      assert.strictEqual(sql(`select sum(credit) from acct.lines where account = '2150'`), '117500.00', 'one twelfth provisioned for the aguinaldo');
      // the month for the CCSS and the INS
      await acc.fill('#mrMonth', crDay(-7).slice(0, 7));
      await acc.click('#mrGo');
      await until(async () => /Marta\s+155812345678/.test(await acc.locator('#mrTable').innerText()), 8000, 'Marta in the month');
      assert.match(await acc.locator('#mrTable').innerText(), /₡1\s410\s000[\s\S]*₡148\s050[\s\S]*₡136\s124/, 'salary, CCSS, income tax');
      assert.match(await acc.locator('#mrRules').innerText(), /INS riesgos del trabajo\s+Paid by the business on top\s+INS \(occupational risk policy\)\s+1,5\s+₡21\s150/);
      // the aguinaldo estimate: the posted salary over twelve, already provisioned
      await acc.click('#agGo');
      await until(async () => /Marta\s+155812345678\s+1\s+₡1\s410\s000\s+₡117\s500\s+₡117\s500/.test(await acc.locator('#aguTable').innerText()), 8000, 'aguinaldo line');
      assert.strictEqual(await acc.locator('#agStatus').textContent(), 'Estimate');
      await acc.click('#agPrepare');
      await until(() => sql(`select status from payroll_special_runs`) === 'draft', 8000, 'aguinaldo run prepared');
      await until(async () => acc.locator('#agReview').isVisible(), 8000, 'review button');
      // vacations: two days taken, the balance from the hire date
      await acc.selectOption('#vcWho', STAFF.marta);
      await acc.fill('#vcFrom', crDay(-3)); await acc.fill('#vcTo', crDay(-2)); await acc.fill('#vcDays', '2');
      await acc.click('#vcSave');
      await until(() => sql(`select count(*) from vacations`) === '1', 8000, 'vacation recorded');
      await until(async () => /taken 2 · remaining 11 · daily pay average ₡100\s714,29/.test(await acc.locator('#vcBalance').textContent()), 8000, 'balance: 13 months, 2 taken, 1 410 000 / 14 days');
      // a settlement estimate for a resignation: aguinaldo and vacations only
      await acc.selectOption('#lqWho', STAFF.marta);
      await acc.selectOption('#lqReason', 'renuncia');
      await acc.click('#lqGo');
      await until(async () => /Severance\s+Does not apply/.test(await acc.locator('#lqTable').innerText()), 8000, 'settlement table');
      assert.match(await acc.locator('#lqTable').innerText(), /Proportional aguinaldo\s+₡117\s500/);
      assert.match(await acc.locator('#lqHint').textContent(), /the notice and severance table is the law as written, not confirmed/);
      assert.deepStrictEqual(acc.errors, []);
    }
  },
  {
    name: 'withholding on without a table: the payroll says so and the accountant cannot review it; the owner edits a profile',
    run: async ({ browser }) => {
      sql(`insert into pay_periods (id, starts_on, ends_on, status, approved_by, approved_at, created_by)
             values ('ae000000-0000-4000-8000-000000002602', '${crDay(-20)}', '${crDay(-7)}', 'approved', 'Dueño', now() - interval '1 minute', 'test');
           insert into staff_pay (staff_id, kind, rate_crc, effective_from, created_by) values ('${STAFF.marta}', 'period', 500000, '${crDay(-30)}', 'test');
           insert into compliance_confirmations (key, confirmed_by, reference) values ('payroll_cr_rules', 'Contadora', 'Oficio 7-2026');
           insert into settings (key, value, updated_by) values ('payroll_renta_withhold', 'true', 'test')`);
      const own = await payroll(browser, 'owner');
      await until(async () => own.locator('#prPrepare').isVisible(), 8000, 'prepare button');
      await own.click('#prPrepare');
      await until(async () => /no tax table/.test(await own.locator('#prTable').innerText()), 8000, 'the line is flagged');
      assert.match(await own.locator('#prState').textContent(), /withholding is on but there is no tax table/);
      // the owner fills Marta's profile
      await until(async () => (await own.locator('#rtTable tr', { hasText: 'Marta' }).count()) === 1, 8000, 'rates listed');
      await own.locator('#rtTable tr', { hasText: 'Marta' }).locator('button', { hasText: 'Profile' }).click();
      await own.fill('#pfId', '1-0999-0888');
      await own.fill('#pfHired', crDay(-100));
      await own.selectOption('#pfContract', 'por_horas');
      await own.click('#pfSave');
      await until(() => sql(`select id_number || '|' || contract from staff_profile where staff_id = '${STAFF.marta}'`) === '1-0999-0888|por_horas', 8000, 'profile saved');
      assert.deepStrictEqual(own.errors, []);
      const acc = await payroll(browser, 'accountant');
      await until(async () => acc.locator('#prReview').isVisible(), 8000, 'review button');
      await acc.click('#prReview');
      await until(async () => /no confirmed tax table/.test(await acc.locator('#prErr').textContent()), 8000, 'review refused until the table exists');
      assert.strictEqual(sql(`select status from payroll_runs`), 'draft');
      assert.deepStrictEqual(acc.errors, []);
    }
  }
];
