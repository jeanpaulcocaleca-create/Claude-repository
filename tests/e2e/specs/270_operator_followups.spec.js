/* Who took the money (migration 0027): "End my turn" on the POS can clock the person out; Sales lists the money by cashier,
   a bill paid later under the person who closed it. */
'use strict';
const assert = require('assert');
const { page, goto, until, sql, pos, cashExact, STAFF, PINS } = require('../lib');

async function ring(pg, method) {
  await pg.locator('.pbtn').first().click();
  await pg.click(`[data-pay="${method || 'card'}"]`);
  if (/^cash/.test(method || 'card')) await cashExact(pg);
  if (await pg.locator('#numModal:not([hidden])').count()) await pg.click('#numNone');
}
async function signIn(pg, who, pin) {
  await pg.waitForSelector('#opModal:not([hidden])', { timeout: 10000 });
  await pg.locator('#opWho button', { hasText: who }).click();
  await pg.fill('#opPin', pin);
  await pg.click('#opGo');
}

module.exports.tests = [
  {
    name: 'enforce mode: Luis clocks in from the POS, rings a sale and ends his turn clocking out; Sales shows the money by cashier',
    run: async ({ browser }) => {
      sql(`insert into settings (key, value) values ('operator_mode', '"enforce"')`);
      const pg = await pos(browser);
      await signIn(pg, 'Luis', PINS.luis);
      await until(async () => pg.locator('#opClockGo').isVisible(), 8000, 'clock-in offered');
      await pg.fill('#opPin', PINS.luis);
      await pg.click('#opClockGo');
      await until(async () => (await pg.locator('#opBtn').textContent()) === 'Luis', 8000, 'Luis signed in');
      assert.strictEqual(sql(`select count(*) from time_entries where staff_id = '${STAFF.luis}' and clock_out is null`), '1', 'clocked in');
      await ring(pg);
      await until(() => sql(`select count(*) from orders`) === '1', 10000, 'sale saved');
      // a bill Luis opened earlier that Marta closed (the server records who took the money)
      sql(`insert into orders (id, created_at, total_crc, payment_method, paid, status, operator_id, operator_name, paid_operator_id, paid_operator_name)
             values ('0d000000-0000-4000-8000-0000000e2e70', now() - interval '2 minutes', 7000, 'card', true, 'done', '${STAFF.luis}', 'Luis', '${STAFF.marta}', 'Marta')`);
      // End my turn: the page asks about the clock; the test's dialogs are accepted
      pg.onDialog = (d) => d.accept();
      await pg.click('#opBtn');
      await pg.click('#opEnd');
      await until(() => sql(`select count(*) from time_entries where staff_id = '${STAFF.luis}' and clock_out is not null`) === '1', 8000, 'clocked out from the POS');
      assert.strictEqual(sql(`select count(*) from operator_sessions where ended_at is not null`), '1', 'his turn ended on the server');
      assert.deepStrictEqual(pg.errors, []);

      const own = await page(browser, { login: 'owner', aal: 'aal2', lang: 'en' });
      await goto(own, '/sales');
      await until(async () => own.locator('#cashierCard').isVisible(), 15000, 'by-cashier card');
      const bars = await own.locator('#cashierBars').innerText();
      assert.match(bars, /Marta[\s\S]*1 sales · ₡7\s000/, 'the bill paid later counts for Marta, who closed it');
      assert.match(bars, /Luis[\s\S]*1 sales/, 'Luis has his own sale');
      assert.deepStrictEqual(own.errors, []);
    }
  },
  {
    name: 'declining the clock-out question ends the turn and leaves the shift open',
    run: async ({ browser }) => {
      sql(`insert into settings (key, value) values ('operator_mode', '"enforce"')`);
      const pg = await pos(browser);
      await signIn(pg, 'Marta', PINS.marta);
      await until(async () => pg.locator('#opClockGo').isVisible(), 8000, 'clock-in offered');
      await pg.fill('#opPin', PINS.marta);
      await pg.click('#opClockGo');
      await until(async () => (await pg.locator('#opBtn').textContent()) === 'Marta', 8000, 'Marta signed in');
      pg.onDialog = (d) => d.dismiss();
      await pg.click('#opBtn');
      await pg.click('#opEnd');
      await until(() => sql(`select count(*) from operator_sessions where ended_at is not null`) === '1', 8000, 'her turn ended on the server');
      assert.strictEqual(sql(`select count(*) from time_entries where staff_id = '${STAFF.marta}' and clock_out is null`), '1', 'still clocked in');
      assert.deepStrictEqual(pg.errors, []);
    }
  }
];
