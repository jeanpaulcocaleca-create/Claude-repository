/* Who is ringing up (migration 0008): sign in with a PIN, every sale carries the operator, also offline. */
'use strict';
const assert = require('assert');
const { page, goto, until, settle, sql, pos, cashExact, STAFF, PINS } = require('../lib');

async function ring(pg, method) {
  await pg.locator('.pbtn').first().click();
  await pg.click(`[data-pay="${method || 'card'}"]`);
  if (/^cash/.test(method || 'card')) await cashExact(pg);
  if (await pg.locator('#numModal:not([hidden])').count()) await pg.click('#numNone');
}
/* every check of the mode answered first: a late answer opens the window again, and the person picked is lost */
async function signIn(pg, who, pin) {
  await pg.waitForSelector('#opModal:not([hidden])', { timeout: 10000 });
  await settle(pg);
  await pg.locator('#opWho button', { hasText: who }).click();
  await pg.fill('#opPin', pin);
  await pg.click('#opGo');
}

module.exports.tests = [
  {
    name: 'with the mode off the POS looks and works as before',
    run: async ({ browser }) => {
      const pg = await pos(browser);
      await new Promise((r) => setTimeout(r, 500));
      assert.strictEqual(await pg.locator('#opBtn').isVisible(), false);
      assert.strictEqual(await pg.locator('#opModal').isVisible(), false);
      await ring(pg);
      await until(() => sql(`select count(*) from orders`) === '1', 10000, 'sale saved');
      assert.strictEqual(sql(`select coalesce(operator_name, '-') || '|' || array_to_string(flags, ',') from orders`), '-|');
    }
  },
  {
    name: 'record mode: the cashier signs in with a PIN and the sale is theirs (marked: not clocked in)',
    run: async ({ browser }) => {
      sql(`insert into settings (key, value) values ('operator_mode', '"record"')`);
      const pg = await pos(browser);
      await signIn(pg, 'Luis', PINS.luis);
      await until(async () => (await pg.locator('#opBtn').textContent()) === 'Luis', 8000, 'Luis signed in');
      assert.strictEqual(await pg.locator('#opPin').inputValue(), '', 'the PIN is not left in the box');
      await ring(pg);
      await until(() => sql(`select count(*) from orders`) === '1', 10000, 'sale saved');
      assert.strictEqual(sql(`select operator_name || '|' || array_to_string(flags, ',') from orders`), 'Luis|operator_not_clocked_in');
      await pg.click('#opBtn');
      await pg.click('#opEnd');
      await until(() => sql(`select count(*) from operator_sessions where ended_at is not null`) === '1', 8000, 'his turn ended on the server');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'enforce mode: clock in from the POS, then ring up',
    run: async ({ browser }) => {
      sql(`insert into settings (key, value) values ('operator_mode', '"enforce"')`);
      const pg = await pos(browser);
      assert.strictEqual(await pg.locator('#opSkip').isVisible(), false, 'no skipping in enforce mode');
      await signIn(pg, 'Marta', PINS.marta);
      await until(async () => !(await pg.locator('#opClockGo').isHidden()), 8000, 'clock-in offer');
      await pg.fill('#opPin', PINS.marta);
      await pg.click('#opClockGo');
      await until(async () => (await pg.locator('#opBtn').textContent()) === 'Marta', 8000, 'Marta signed in');
      assert.strictEqual(sql(`select count(*) from time_entries where staff_id = '${STAFF.marta}' and clock_out is null`), '1', 'her shift started');
      await ring(pg, 'cash_crc');
      await until(() => sql(`select count(*) from orders`) === '1', 10000, 'sale saved');
      assert.strictEqual(sql(`select operator_name || '|' || array_to_string(flags, ',') from orders`), 'Marta|');
    }
  },
  {
    name: 'without internet: a sale keeps the person who rang it, marked not checked',
    run: async ({ browser, setOffline }) => {
      sql(`insert into settings (key, value) values ('operator_mode', '"record"')`);
      const pg = await pos(browser);
      await pg.waitForSelector('#opModal:not([hidden])', { timeout: 10000 });
      await settle(pg);   // every check of the mode answered, and the staff list kept for offline use
      await pg.click('#opSkip');
      await pg.waitForSelector('#opModal', { state: 'hidden', timeout: 5000 });
      await pg.waitForSelector('#opBtn:not([hidden])', { timeout: 5000 });
      setOffline(true);
      await pg.evaluate(() => { Object.defineProperty(navigator, 'onLine', { configurable: true, get: () => false }); });
      await pg.click('#opBtn');
      await pg.locator('#opWho button', { hasText: 'Ana' }).click();
      await pg.click('#opOffline');
      await until(async () => /Ana/.test(await pg.locator('#opBtn').textContent()), 5000, 'Ana chosen offline');
      await ring(pg, 'cash_crc');
      await new Promise((r) => setTimeout(r, 800));
      assert.strictEqual(sql(`select count(*) from orders`), '0');
      setOffline(false);
      await pg.evaluate(() => { delete navigator.onLine; syncQueue(); });
      await until(() => sql(`select count(*) from orders`) === '1', 15000, 'sale uploaded');
      assert.strictEqual(sql(`select operator_name || '|' || array_to_string(flags, ',') from orders`), 'Ana|operator_unverified,operator_not_clocked_in');
    }
  },
  {
    name: 'without internet: the screen waking up keeps the mode, and the next sale still carries who rang it',
    run: async ({ browser, setOffline }) => {
      sql(`insert into settings (key, value) values ('operator_mode', '"record"')`);
      const pg = await pos(browser);
      await pg.waitForSelector('#opModal:not([hidden])', { timeout: 10000 });
      await settle(pg);
      await pg.click('#opSkip');
      setOffline(true);
      await pg.evaluate(() => { Object.defineProperty(navigator, 'onLine', { configurable: true, get: () => false }); });
      await pg.click('#opBtn');
      await pg.locator('#opWho button', { hasText: 'Ana' }).click();
      await pg.click('#opOffline');
      // the tablet's screen wakes up: supabase-js announces the sign-in again, so the POS checks the mode again, and
      // without internet nothing answers (this turned the mode off before D-054: no chip, and sales went up with nobody)
      const check = pg.waitForEvent('requestfailed', (r) => /rpc\/setting$/.test(r.url()) && /operator_mode/.test(r.postData() || ''));
      await pg.evaluate(() => window.dispatchEvent(new Event('visibilitychange')));
      await check;
      await pg.evaluate(() => new Promise((r) => setTimeout(r, 300)));
      assert.strictEqual(await pg.locator('#opBtn').isVisible(), true, 'the chip stays');
      assert.strictEqual(await pg.locator('#opBtn').textContent(), 'Ana · not checked');
      await ring(pg, 'cash_crc');
      await until(async () => (await pg.evaluate(() => queue.length)) === 1, 5000, 'the sale waits on the device');
      setOffline(false);
      await pg.evaluate(() => { delete navigator.onLine; syncQueue(); });
      await until(() => sql(`select count(*) from orders`) === '1', 15000, 'sale uploaded');
      assert.strictEqual(sql(`select coalesce(operator_name, 'nobody') || '|' || array_to_string(flags, ',') from orders`), 'Ana|operator_unverified,operator_not_clocked_in');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'the owner switches the mode on Home, and the change is logged',
    run: async ({ browser }) => {
      const pg = await page(browser, { login: 'owner', aal: 'aal2', lang: 'en' });
      await goto(pg, '/home');
      const sel = pg.locator('#setList select[aria-label="Who rings up each sale"]');
      await until(async () => sel.isVisible(), 10000, 'settings card');
      await sel.selectOption('record');
      await until(() => sql(`select value #>> '{}' from settings where key = 'operator_mode'`) === 'record', 8000, 'saved');
      assert.match(await pg.locator('#setMsg').textContent(), /Saved/);
      assert.strictEqual(sql(`select count(*) from audit_log where action = 'setting_change'`), '1');
    }
  }
];
