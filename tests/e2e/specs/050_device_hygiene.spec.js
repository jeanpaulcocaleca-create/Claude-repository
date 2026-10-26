/* Devices after a release reload themselves only between sales; PINs are never kept on screen or in memory. */
'use strict';
const assert = require('assert');
const { page, goto, until, sql, openRegister, STAFF, PINS } = require('../lib');

module.exports.tests = [
  {
    name: 'after a release the POS waits for the sale in progress, then reloads to the new version',
    run: async ({ browser, setRelease }) => {
      openRegister();
      // the open page is build b1; the site now says b2 is published
      setRelease({ served: 'b1', published: 'b2' });
      const pg = await page(browser, { login: 'cafe', lang: 'en' });
      await goto(pg, '/pos');
      await pg.waitForSelector('.pbtn', { timeout: 15000 });
      assert.strictEqual(await pg.evaluate(() => HG_VERSION.build), 'b1');

      await pg.locator('.pbtn').first().click();
      await pg.evaluate(async () => { HG_VERSION.quietMs = 0; await HG_VERSION.check(); });
      assert.strictEqual(await pg.locator('#netChip').textContent(), 'update ready', 'the staff sees that an update is waiting');
      assert.strictEqual(await pg.evaluate(() => HG_VERSION.tick()), false, 'no reload with a sale on the screen');

      await pg.click('[data-pay="card"]');
      if (await pg.locator('#numModal:not([hidden])').count()) await pg.click('#numNone');
      await until(() => sql(`select count(*) from orders where payment_method = 'card'`) === '1', 10000, 'sale saved');
      await until(async () => pg.evaluate(() => { try { return HG_VERSION.tick(); } catch (e) { return false; } }).catch(() => true), 10000, 'reload once safe');
      await until(async () => /v=b2/.test(pg.url()), 10000, 'new address');
      await pg.waitForSelector('.pbtn', { timeout: 15000 });
      assert.strictEqual(await pg.evaluate(() => HG_VERSION.build), 'b2', 'the new version is running');
      assert.strictEqual(sql(`select count(*) from orders`), '1', 'the sale was saved once');
    }
  },
  {
    name: 'a development copy never reloads itself',
    run: async ({ browser }) => {
      openRegister();
      const pg = await page(browser, { login: 'cafe', lang: 'en' });
      await pg.route(/\/version\.json/, (route) => route.fulfill({ contentType: 'application/json', body: '{"build":"b2"}' }));
      await goto(pg, '/pos');
      await pg.waitForSelector('.pbtn', { timeout: 15000 });
      assert.strictEqual(await pg.evaluate(() => typeof HG_VERSION.check), 'function');
      assert.strictEqual(await pg.evaluate(() => HG_VERSION.pending), null);
      assert.strictEqual(await pg.locator('#netChip').textContent(), 'online');
    }
  },
  {
    name: 'the time clock shows a team member their hours without keeping their PIN',
    run: async ({ browser }) => {
      sql(`insert into time_entries (staff_id, clock_in, clock_out) values ('${STAFF.luis}', now() - interval '5 hours', now() - interval '1 hour')`);
      const pg = await page(browser, { login: 'cafe', lang: 'en' });
      await goto(pg, '/time');
      await pg.click('#tabHours');
      await pg.waitForSelector('#hoursPinModal:not([hidden])', { timeout: 10000 });
      await pg.selectOption('#hpWho', STAFF.luis);
      await pg.fill('#hpPin', PINS.luis);
      await pg.click('#hoursPinForm button[type=submit]');
      await until(async () => pg.locator('#hoursPinModal').isHidden(), 8000, 'PIN accepted');
      const kept = await pg.evaluate(() => JSON.stringify(window.hoursAuth));
      assert.ok(kept && kept.indexOf('"entries"') > -1, 'the hours are kept');
      assert.ok(kept.indexOf(PINS.luis) === -1, 'the PIN is not kept in memory');
      assert.strictEqual(await pg.locator('#hpPin').inputValue(), '', 'nor left in the box');
      assert.deepStrictEqual(pg.errors, []);
    }
  }
];
