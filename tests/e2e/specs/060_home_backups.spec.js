/* Owner Home shows whether last night's backup worked (migration 0002, ops/backup). */
'use strict';
const assert = require('assert');
const { page, goto, until, sql } = require('../lib');

module.exports.tests = [
  {
    name: 'the owner sees a green backup card in Spanish after a verified backup',
    run: async ({ browser }) => {
      sql(`insert into canopy.backup_runs (source, status, started_at, finished_at, size_bytes, restore_test)
           values ('cloud', 'ok', now() - interval '2 hours 5 minutes', now() - interval '2 hours', 123456, 'passed')`);
      const pg = await page(browser, { login: 'owner', aal: 'aal2', lang: 'es' });
      await goto(pg, '/home');
      await until(async () => !(await pg.locator('#bkCard').isHidden()), 10000, 'backup card');
      assert.match(await pg.locator('#bkCard').getAttribute('class'), /green/);
      // lang.js translates right after the page writes the English text
      await until(async () => (await pg.locator('#bkTitle').textContent()) === 'Respaldos al día', 5000, 'title in Spanish');
      await until(async () => (await pg.locator('#bkSub').textContent()) === 'Última copia verificada · hace 2 h · prueba de restauración aprobada', 5000, 'detail in Spanish');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'no backup in two days turns the card red',
    run: async ({ browser }) => {
      sql(`insert into canopy.backup_runs (source, status, finished_at, restore_test) values ('cloud', 'ok', now() - interval '3 days', 'passed');
           insert into canopy.backup_runs (source, status, finished_at, detail) values ('cloud', 'failed', now() - interval '1 day', 'x')`);
      const pg = await page(browser, { login: 'owner', aal: 'aal2', lang: 'en' });
      await goto(pg, '/home');
      await until(async () => !(await pg.locator('#bkCard').isHidden()), 10000, 'backup card');
      assert.match(await pg.locator('#bkCard').getAttribute('class'), /red/);
      assert.strictEqual(await pg.locator('#bkTitle').textContent(), 'No verified backup in 2 days');
      assert.match(await pg.locator('#bkSub').textContent(), /3 days ago · 1 failed this week/);
    }
  }
];
