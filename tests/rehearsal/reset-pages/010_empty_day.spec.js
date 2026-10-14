/* Canopy OS rehearsal · the NEW pages (website/) on the copy of production after the one-time reset and every migration
   (tests/rehearsal/run.sh step 10): the café as the owner finds it on the launch morning, with its menu, team, recipes,
   suppliers and rooms, and no sale, shift, stock move or register day at all, every stock at zero. Every page must open
   clean with its empty state; then the first real day: a manager opens the register, one cash sale, the register is
   counted, and Home and Insights show the day. Logins and PINs are the rehearsal seed's (tests/rehearsal/seed-legacy.sql). */
'use strict';
const assert = require('assert');
const { page, goto, until, sql, cashExact, STAFF, PINS } = require('../../e2e/lib');

/* the local stand-in for Supabase answers on the site port + 1000 (tests/e2e/gateway.js) */
const API = 'http://127.0.0.1:' + (Number(process.env.E2E_SITE_PORT || 8090) + 1000);
function watchApi(pg) {
  pg.apiErrors = [];
  pg.on('response', (r) => {
    if (r.url().startsWith(API + '/') && r.status() >= 400) pg.apiErrors.push(r.status() + ' ' + r.request().method() + ' ' + r.url().slice(API.length));
  });
  return pg;
}
const quiet = (ms) => new Promise((r) => setTimeout(r, ms));
/* the Today panel: on a day with no register opened yet, the POS opens it once by itself (a nudge to open the register),
   covering the Today button; open it only if it is not already open */
async function openDay(pg) {
  await quiet(800);
  if (!(await pg.locator('#dayModal').isVisible())) await pg.click('#dayBtn');
  await until(async () => pg.locator('#dayModal').isVisible(), 12000, 'the Today panel');
}
const text = async (pg, sel) => ((await pg.locator(sel).textContent()) || '').trim();
const visible = (pg, sel) => until(async () => pg.locator(sel).first().isVisible(), 12000, sel + ' visible');
/* the café's pages: who opens them, and what an empty café must show on each */
async function open(browser, login, path) {
  const pg = watchApi(await page(browser, { login: login || undefined, aal: login === 'owner' ? 'aal2' : undefined, lang: 'en' }));
  await goto(pg, path);
  return pg;
}
function problems(pg, where) {
  const out = [];
  if (pg.errors.length) out.push(where + ' script errors: ' + pg.errors.join(' | '));
  if (pg.apiErrors.length) out.push(where + ' API: ' + pg.apiErrors.join(' | '));
  if (pg.supabaseHits) out.push(where + ' tried the real Supabase');
  return out;
}

module.exports.tests = [
  {
    name: 'the empty café: POS, Home, Sales, Inventory, Time clock, Kitchen, TV board, QR menu, Insights and Accounting open with their empty states, no script errors, no refused API call',
    run: async ({ browser }) => {
      // the reset copy as run.sh left it: nothing operational, everything configured
      assert.strictEqual(sql(`select count(*) from public.orders`) + '|' + sql(`select count(*) from public.register_days`) + '|' +
                         sql(`select count(*) from public.time_entries`) + '|' + sql(`select count(*) from public.stock_moves`), '0|0|0|0', 'the café is empty');
      const items = Number(sql(`select count(*) from public.stock_items where active`)), staff = Number(sql(`select count(*) from public.staff where active`));
      assert.ok(items > 0 && staff > 0, 'the configuration stayed');
      assert.strictEqual(sql(`select count(*) from public.stock_items where on_hand <> 0`), '0', 'every stock at zero');
      const found = [];
      const pages = [
        ['cafe', '/pos', async (pg) => {   // the menu grid, nothing sold today, nothing waiting
          await pg.waitForSelector('#appView:not([hidden])', { timeout: 15000 });
          await until(async () => (await pg.locator('#menuGrid .pbtn').count()) > 1, 15000, 'the menu grid');
          await openDay(pg);
          await until(async () => /Orders\s*0[\s\S]*Total\s*₡0/.test(await text(pg, '#dayBody')), 8000, 'today at the counter: 0 orders, ₡0');
          await visible(pg, '#regOpenForm');    // the register has not been opened yet
          await pg.click('#dayClose');
        }],
        ['owner', '/home', async (pg) => {
          await pg.waitForSelector('#appView:not([hidden])', { timeout: 15000 });
          await until(async () => (await text(pg, '#kOrders')) === '0', 10000, 'orders today 0');
          assert.match(await text(pg, '#kRev'), /^₡\s?0$/, 'revenue today');
          await until(async () => (await text(pg, '#kClock')) === 'Nobody in', 8000, 'nobody on the clock');
        }],
        ['owner', '/sales', async (pg) => {
          await visible(pg, 'text=No sales in this period yet');
        }],
        ['owner', '/inventory', async (pg) => {
          await until(async () => (await pg.locator('#stockTable tbody tr').count()) === items, 15000, items + ' stock items listed');
          const onHand = await pg.locator('#stockTable tbody tr td:nth-child(2)').allTextContents();
          assert.ok(onHand.length === items && onHand.every((t) => /^0(\.0)? /.test(t.trim())), 'every item at 0 on hand: ' + onHand.slice(0, 3).join(' · '));
          assert.match(await text(pg, '#kValue'), /^₡\s?0$/, 'stock value ₡0');
        }],
        ['cafe', '/time', async (pg) => {
          await until(async () => (await pg.locator('#staffGrid button').count()) === staff, 15000, staff + ' people on the clock-in grid');
        }],
        ['cafe', '/kitchen', async (pg) => {
          await pg.waitForSelector('#appView:not([hidden])', { timeout: 15000 });
          await visible(pg, '#board .empty');
          assert.strictEqual(await text(pg, '#board .empty'), 'Nothing to prepare right now.');
        }],
        [null, '/tv', async (pg) => {
          await until(async () => (await pg.locator('#pages .it').count()) > 10, 15000, 'the menu on the board');
          assert.strictEqual(await pg.locator('#err').isVisible(), false, 'no connection error');
        }],
        [null, '/m', async (pg) => {
          await until(async () => pg.locator('#status').isHidden(), 15000, 'the QR menu loaded');
          await until(async () => (await pg.locator('#menu section').count()) > 3 && (await pg.locator('text=Espresso').count()) > 0, 10000, 'the sections and an item of the menu');
          assert.strictEqual(await pg.locator('#failed').isVisible(), false, 'no failure notice');
        }],
        ['owner', '/insights', async (pg) => {
          await pg.waitForSelector('#content:not([hidden])', { timeout: 15000 });
          await until(async () => (await text(pg, '#tState')) === 'Register not opened', 10000, 'today: register not opened');
          await visible(pg, 'text=No sales in these days.');
        }],
        ['owner', '/accounting', async (pg) => {
          await pg.waitForSelector('#appView:not([hidden])', { timeout: 15000 });
          await pg.click('#tabs [data-view=journal]');
          await quiet(1500);
          assert.strictEqual(sql(`select count(*) from acct.entries`), '0', 'no ledger entry on the empty café');
        }]
      ];
      for (const [login, path, expect] of pages) {
        const pg = await open(browser, login, path);
        const where = (login || 'visitor') + ' ' + path;
        try { await expect(pg); } catch (e) { found.push(where + ': ' + e.message.split('\n')[0]); }
        await quiet(1200);   // late requests and errors
        found.push(...problems(pg, where));
        await pg.context().close();
      }
      assert.deepStrictEqual(found, []);
    }
  },
  {
    name: 'the first real day: a manager opens the register with a float, one cash sale, the register is counted; Home and Insights show the day as final',
    run: async ({ browser }) => {
      const pos = await open(browser, 'cafe', '/pos');
      await pos.waitForSelector('#appView:not([hidden])', { timeout: 15000 });
      await until(async () => (await pos.locator('#menuGrid .pbtn').count()) > 1, 15000, 'the menu grid');
      /* Ana opens the register with ₡50 000 */
      await openDay(pos);
      await visible(pos, '#regOpenForm');
      await until(async () => (await pos.locator('#roStaff option').count()) > 0, 8000, 'who is opening');
      await pos.selectOption('#roStaff', STAFF.ana);
      await pos.fill('#roPin', PINS.ana);
      await pos.fill('#roFloat', '50000');
      await pos.click('#regOpenForm button[type=submit]');
      await until(() => sql(`select opened_by_name || '|' || float_crc from public.register_days where business_date = public.cr_today()`) === 'Ana|50000', 10000, 'the register opened');
      await visible(pos, '#regCloseForm');
      await pos.click('#dayClose');
      /* one cash sale: two of the first product */
      const first = pos.locator('#menuGrid .pbtn').first();
      const name = (await first.locator('.nm').textContent()).trim();
      const price = Number(sql(`select price_crc from public.menu_items where name = '${name.replace(/'/g, "''")}' limit 1`));
      assert.ok(price > 0, 'a priced product on the grid: ' + name);
      await first.click(); await first.click();
      await pos.click('[data-pay="cash_crc"]');
      await cashExact(pos);
      if (await pos.locator('#numModal:not([hidden])').count()) await pos.click('#numNone');
      const sale = await until(() => sql(`select total_crc || '|' || payment_method || '|' || paid || '|' || (business_date = public.cr_today()) || '|' || (receipt_no is not null) || '|' ||
                                                 (select count(*) from public.order_items i where i.order_id = o.id and i.menu_item_id is not null and i.tax_rate is not null)
                                            from public.orders o`), 10000, 'the sale saved');
      assert.strictEqual(sale, `${2 * price}|cash_crc|true|true|true|1`, 'the first sale of the café: ' + sale);
      /* Ana counts the register: nothing on the card terminal, the float plus the sale in the drawer */
      await openDay(pos);
      await visible(pos, '#rcCash');
      await pos.fill('#rcTerminal', '0');
      await pos.fill('#rcCash', String(50000 + 2 * price));
      await pos.selectOption('#rcStaff', STAFF.ana);
      await pos.fill('#rcPin', PINS.ana);
      await pos.click('#rcSubmit');
      await until(() => sql(`select closed_by_name from public.register_days where business_date = public.cr_today()`) === 'Ana', 10000, 'the register closed');
      assert.strictEqual(sql(`select sales_total_crc || '|' || cash_counted_crc || '|' || cash_diff_crc from public.register_days where business_date = public.cr_today()`),
                         `${2 * price}|${50000 + 2 * price}|0`, 'the day counted without a difference');
      /* the owner reads the day */
      const home = await open(browser, 'owner', '/home');
      await home.waitForSelector('#appView:not([hidden])', { timeout: 15000 });
      await until(async () => (await text(home, '#kOrders')) === '1', 10000, 'one order today on Home');
      assert.strictEqual((await text(home, '#kRev')).replace(/\s/g, ''), '₡' + (2 * price).toLocaleString('fr-FR').replace(/\s/g, ''), 'revenue today');
      assert.match(await text(home, '#kRevSub'), /^Final · without IVA ₡/, 'final once the register is closed');
      const ins = await open(browser, 'owner', '/insights');
      await ins.waitForSelector('#content:not([hidden])', { timeout: 15000 });
      await until(async () => (await text(ins, '#tState')) === 'Final', 10000, 'today final on Insights');
      assert.match((await text(ins, '#tGross')).replace(/\s/g, ''), new RegExp('^withIVA₡' + (2 * price).toLocaleString('fr-FR').replace(/\s/g, '') + '$'), 'today with IVA');
      await quiet(1000);
      const found = [].concat(problems(pos, 'cafe /pos'), problems(home, 'owner /home'), problems(ins, 'owner /insights'));
      assert.deepStrictEqual(found, []);
    }
  }
];
