/* Touch screens get large on-screen pads; staff screens start in Spanish. */
'use strict';
const assert = require('assert');
const { page, goto, until, settle, sql, openRegister, registerTill, tapOnce, tapLanded, STAFF, PINS } = require('../lib');

async function touchPos(browser, opts) {
  openRegister();
  const context = await browser.newContext({ viewport: { width: 1180, height: 820 }, hasTouch: true, locale: 'en-US', timezoneId: 'America/Costa_Rica' });
  const pg = await page(browser, Object.assign({ context, login: 'cafe', lang: 'en' }, opts || {}));
  return pg;
}
/* the café's tablet held upright (D-068): its windows fit without scrolling, so a button under an open pad moved up by
   the pad's whole height when the pad closed (in a window scrolled to its end the scroll could keep it in place) */
async function tablet(browser, opts) {
  const context = await browser.newContext({ viewport: { width: 820, height: 1180 }, hasTouch: true, isMobile: true, locale: 'en-US', timezoneId: 'America/Costa_Rica' });
  return page(browser, Object.assign({ context, login: 'cafe', lang: 'en' }, opts || {}));
}

module.exports.tests = [
  {
    name: 'a manager approves a void on a touch screen with the PIN pad',
    run: async ({ browser }) => {
      sql(`insert into orders (id, created_at, total_crc, payment_method, paid, status) values ('0d000000-0000-4000-8000-0000000e2e11', now(), 1300, 'card', true, 'done');
           insert into order_items (order_id, item_name, price_crc, qty) values ('0d000000-0000-4000-8000-0000000e2e11', 'Espresso', 1300, 1)`);
      const pg = await touchPos(browser);
      await goto(pg, '/pos');
      await pg.waitForSelector('.pbtn', { timeout: 15000 });
      await pg.click('#ordersBtn');
      await pg.locator('.orow', { hasText: 'Espresso' }).first().locator('button', { hasText: 'Void' }).click();
      await pg.fill('#vReason', 'prueba');
      await pg.selectOption('#vMgr', STAFF.ana);
      await pg.focus('#vPin');
      const pad = pg.locator('#vPin + .hg-pad');
      await until(async () => pad.isVisible(), 5000, 'PIN pad');
      assert.strictEqual(await pg.locator('#vPin').getAttribute('inputmode'), 'none', 'no phone keyboard on top of the pad');
      for (const d of PINS.ana) await pad.locator('button', { hasText: new RegExp('^' + d + '$') }).click();
      assert.strictEqual(await pg.locator('#vPin').inputValue(), PINS.ana);
      await pad.locator('button.ok').click();
      await until(() => sql(`select voided_at is not null from orders where id = '0d000000-0000-4000-8000-0000000e2e11'`) === 't', 8000, 'voided');
      assert.strictEqual(await pg.locator('#vPin').inputValue(), '', 'the PIN is cleared afterwards');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'a touch screen: «Void this order» tapped right after the PIN digits voids with that one tap (D-068)',
    run: async ({ browser }) => {
      sql(`insert into orders (id, created_at, total_crc, payment_method, paid, status) values ('0d000000-0000-4000-8000-0000000e2e12', now(), 1300, 'card', true, 'done');
           insert into order_items (order_id, item_name, price_crc, qty) values ('0d000000-0000-4000-8000-0000000e2e12', 'Espresso', 1300, 1)`);
      openRegister();
      const pg = await tablet(browser);
      await goto(pg, '/pos');
      await pg.waitForSelector('.pbtn', { timeout: 15000 });
      await pg.locator('#ordersBtn').tap();
      await pg.locator('.orow', { hasText: 'Espresso' }).first().locator('button', { hasText: 'Void' }).tap();
      await pg.fill('#vReason', 'prueba');
      await pg.selectOption('#vMgr', STAFF.ana);
      await pg.locator('#vPin').tap();
      const pad = pg.locator('#vPin + .hg-pad');
      await pad.waitFor({ state: 'visible', timeout: 5000 });
      for (const d of PINS.ana) await pad.locator('button', { hasText: new RegExp('^' + d + '$') }).tap();
      assert.strictEqual((await pg.locator('#vPin').inputValue()).length, PINS.ana.length, 'the PIN typed on the pad');   /* never prints it */
      /* «Void this order» sits right under the open pad: the pad closes as the tap moves the focus, and the button must
         not move away before the tap ends */
      tapLanded(await tapOnce(pg.locator('#vGo')), 'the tap on «Void this order»');
      await until(() => sql(`select voided_at is not null from orders where id = '0d000000-0000-4000-8000-0000000e2e12'`) === 't', 8000, 'voided by that one tap');
      assert.strictEqual(await pg.locator('#vPin').inputValue(), '', 'the PIN is cleared afterwards');
      await pad.waitFor({ state: 'hidden', timeout: 3000 });
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'a touch screen: «Open the register» tapped right after the float typed on the amount pad opens it with that one tap (D-068)',
    run: async ({ browser }) => {
      const pg = await tablet(browser);   /* the register not opened yet today */
      await goto(pg, '/pos');
      await pg.waitForSelector('.pbtn', { timeout: 15000 });
      await pg.waitForTimeout(800);                                             /* a main register opens Today by itself once a day */
      if (!(await pg.locator('#dayModal').isVisible())) await pg.locator('#dayBtn').tap();
      await pg.waitForSelector('#regOpenForm:not([hidden])', { timeout: 10000 });
      await until(async () => (await pg.locator('#roStaff option').count()) > 1, 8000, 'who is opening');
      await pg.selectOption('#roStaff', STAFF.ana);
      await pg.locator('#roPin').tap();
      const pinPad = pg.locator('#roPin + .hg-pad');
      await pinPad.waitFor({ state: 'visible', timeout: 5000 });
      for (const d of PINS.ana) await pinPad.locator('button', { hasText: new RegExp('^' + d + '$') }).tap();
      /* the float box right under the PIN pad takes the focus with one tap and opens its own pad; the PIN pad goes */
      await pg.locator('#roFloat').tap();
      const pad = pg.locator('#roFloat + .hg-pad');
      await pad.waitFor({ state: 'visible', timeout: 3000 });
      await pinPad.waitFor({ state: 'hidden', timeout: 3000 });
      for (const k of ['C', '6', '0', '000']) await pad.locator('button', { hasText: new RegExp('^' + k + '$') }).tap();
      assert.strictEqual(await pg.locator('#roFloat').inputValue(), '60000');
      tapLanded(await tapOnce(pg.locator('#regOpenForm button[type=submit]')), 'the tap on «Open the register»');
      await until(() => sql(`select opened_by_name || '|' || float_crc from register_days where business_date = cr_today()`) === 'Ana|60000', 10000, 'the register opened by that one tap');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'without internet: a cash sale with the amount typed on the pad and «Charge» tapped right under the open pad waits on the device after that one tap, and is saved once back online (D-068)',
    run: async ({ browser, setOffline }) => {
      openRegister();
      const pg = await tablet(browser);
      await goto(pg, '/pos');
      await pg.waitForSelector('.pbtn', { timeout: 15000 });
      await settle(pg);
      setOffline(true);
      await pg.locator('.pbtn').first().tap();
      await pg.locator('[data-pay="cash_crc"]').tap();
      await pg.waitForSelector('#cashModal:not([hidden])', { timeout: 5000 });
      const due = Number((await pg.locator('#cashDue').textContent()).replace(/[^\d]/g, ''));
      const amount = String(Math.ceil(due / 1000) * 1000);
      await pg.locator('#cashTyped').tap();
      const pad = pg.locator('#cashTyped + .hg-pad');
      await pad.waitFor({ state: 'visible', timeout: 3000 });
      for (const k of amount) await pad.locator('button', { hasText: new RegExp('^' + k + '$') }).tap();
      await pad.locator('.ok').tap();                         /* ✓ adds the typed amount; the box keeps the focus and its pad */
      await until(async () => !(await pg.locator('#cashGo').isDisabled()), 3000, '«Charge» ready');
      assert.strictEqual(await pad.isVisible(), true, 'the pad is still open above «Charge»');
      tapLanded(await tapOnce(pg.locator('#cashGo')), 'the tap on «Charge»');
      if (await pg.locator('#numModal:not([hidden])').count()) await pg.locator('#numNone').tap();
      await until(async () => (await pg.evaluate(() => JSON.parse(localStorage.getItem('hg-pos-queue') || '[]').length)) === 1, 8000, 'the sale waits on the device');
      assert.strictEqual(sql(`select count(*) from orders`), '0', 'nothing reached the server while offline');
      setOffline(false);
      await pg.evaluate(() => syncQueue());
      await until(() => sql(`select count(*) || '|' || string_agg(payment_method, ',') from orders`) === '1|cash_crc', 15000, 'the sale saved once back online');
      await until(async () => (await pg.evaluate(() => JSON.parse(localStorage.getItem('hg-pos-queue') || '[]').length)) === 0, 8000, 'queue emptied');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'the pad closes after the press that moved the focus: a mouse held on the field below lands there; no press: the next turn; the focus back at once: it stays; never more than 1.5 s held back (D-068)',
    run: async ({ browser }) => {
      openRegister();
      /* a register PC with a touch screen and a mouse: the pad switched on for this device (HG_KEYPAD.setMode('on')) */
      const pg = await page(browser, { login: 'cafe', lang: 'en', storage: { 'hg-keypad': 'on' } });
      await goto(pg, '/pos');
      await pg.waitForSelector('.pbtn', { timeout: 15000 });
      await pg.click('#dayBtn');
      await pg.waitForSelector('#rcCash', { state: 'visible', timeout: 5000 });
      const padT = pg.locator('#rcTerminal + .hg-pad'), padC = pg.locator('#rcCash + .hg-pad'), padU = pg.locator('#rcCashUsd + .hg-pad');
      const t0 = Date.now();
      await pg.click('#rcTerminal');
      await padT.waitFor({ state: 'visible', timeout: 3000 });
      /* the mouse pressed on the cash box right under the open pad and held: the box has the focus at once, but neither
         pad changes (nothing moves) until the release, and the click lands on the box; then the first pad closes and the
         box's own opens. The press starts 1.2 s after the first click and is held past 1.5 s: the first click's time
         limit, which ends during this press, does not end this one */
      const cash = await pg.locator('#rcCash').elementHandle();
      await cash.evaluate((b) => {
        const log = b.__hgTapLog = [];
        ['mousedown', 'mouseup', 'click'].forEach((t) => document.addEventListener(t, (e) => log.push({ t, on: b === e.target, top: Math.round(b.getBoundingClientRect().top) }), { capture: true, once: true }));
      });
      await cash.scrollIntoViewIfNeeded();
      const box = await cash.boundingBox();
      await pg.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
      await pg.waitForTimeout(Math.max(0, 1200 - (Date.now() - t0)));
      await pg.mouse.down();
      await pg.waitForTimeout(Math.max(400, 2000 - (Date.now() - t0)));
      assert.ok(Date.now() - t0 > 1700, 'held past the first click\'s 1.5 s');
      assert.strictEqual(await pg.evaluate(() => document.activeElement.id), 'rcCash', 'the press moved the focus to the cash box (at ' + JSON.stringify(box) + ')');
      assert.strictEqual(await padT.isVisible(), true, 'held: the first pad is still there');
      assert.strictEqual(await padC.isVisible(), false, 'held: the cash box\'s own pad waits too');
      await pg.mouse.up();
      const log = await cash.evaluate((b) => b.__hgTapLog);
      assert.ok(log.length === 3 && log.every((x) => x.on) && log.every((x) => x.top === log[0].top), 'the click landed on the cash box, which stayed in place: ' + JSON.stringify(log));
      await padT.waitFor({ state: 'hidden', timeout: 3000 });
      await padC.waitFor({ state: 'visible', timeout: 3000 });
      assert.strictEqual(await pg.evaluate(() => document.activeElement.id), 'rcCash');
      /* the focus moved without a press (a page's own focus(), a keyboard): the cash pad closes on the next turn */
      await pg.focus('#rcCashUsd');
      await padC.waitFor({ state: 'hidden', timeout: 3000 });
      await padU.waitFor({ state: 'visible', timeout: 3000 });
      /* the focus back in its box before the pad closes: the pad stays */
      await pg.evaluate(() => { const i = document.getElementById('rcCashUsd'); i.blur(); i.focus(); });
      await pg.waitForTimeout(300);
      assert.strictEqual(await padU.isVisible(), true, 'the focus came back at once: the pad stays');
      /* a press held off any field (the window's title): the pad waits for the release, but never more than 1.5 s */
      await pg.locator('#regCloseForm h3').scrollIntoViewIfNeeded();
      const h = await pg.locator('#regCloseForm h3').boundingBox();
      await pg.mouse.move(h.x + 10, h.y + h.height / 2);
      await pg.mouse.down();
      await pg.waitForTimeout(500);
      assert.strictEqual(await padU.isVisible(), true, 'held: the pad waits');
      await padU.waitFor({ state: 'hidden', timeout: 2500 });
      await pg.mouse.up();
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'the discount window types with its own keys on a touch screen: no keypad.js pad under its code box, no phone keyboard',
    run: async ({ browser }) => {
      const pg = await touchPos(browser);
      await goto(pg, '/pos');
      await pg.waitForSelector('.pbtn', { timeout: 15000 });
      if (await pg.isVisible('#dayModal')) await pg.click('#dayClose');
      await registerTill(pg);
      await pg.locator('.pbtn').first().click();
      await pg.click('#discBtn');
      await pg.waitForSelector('#discModal:not([hidden])');
      await pg.locator('[data-cat="local"]').tap();
      await pg.focus('#discPin');
      await new Promise((r) => setTimeout(r, 300));
      assert.strictEqual(await pg.locator('#discModal .hg-pad').count(), 0, 'keypad.js adds no pad of its own (data-keypad="off")');
      assert.strictEqual(await pg.locator('#discPin').getAttribute('inputmode'), 'none', 'no phone keyboard on top of the keys');
      for (const d of PINS.ana) await pg.locator('#discPad button[data-k="' + d + '"]').tap();
      assert.strictEqual(await pg.locator('#discPin').inputValue(), PINS.ana, 'the window\'s own keys type');
      await pg.locator('#discPad button[data-k="del"]').tap();
      assert.strictEqual(await pg.locator('#discPin').inputValue(), PINS.ana.slice(0, 3), '⌫ erases one digit');
      assert.strictEqual(await pg.evaluate(() => document.activeElement && document.activeElement.id), 'discPin', 'the keys never take the focus from the code box');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'the amount pad types into the register close fields',
    run: async ({ browser }) => {
      const pg = await touchPos(browser);
      await goto(pg, '/pos');
      await pg.waitForSelector('.pbtn', { timeout: 15000 });
      await pg.click('#dayBtn');
      await pg.waitForSelector('#rcCash', { state: 'visible', timeout: 5000 });
      await pg.focus('#rcCash');
      const pad = pg.locator('#rcCash + .hg-pad');
      await until(async () => pad.isVisible(), 5000, 'amount pad');
      await pad.locator('button', { hasText: /^5$/ }).click();
      await pad.locator('button', { hasText: /^000$/ }).click();
      await pad.locator('button', { hasText: /^0$/ }).click();
      assert.strictEqual(await pg.locator('#rcCash').inputValue(), '50000');
      await pad.locator('button', { hasText: '⌫' }).click();
      assert.strictEqual(await pg.locator('#rcCash').inputValue(), '5000');
    }
  },
  {
    name: 'a desktop with a keyboard never shows the pad',
    run: async ({ browser }) => {
      openRegister();
      const pg = await page(browser, { login: 'cafe', lang: 'en' });
      await goto(pg, '/pos');
      await pg.waitForSelector('.pbtn', { timeout: 15000 });
      await pg.click('#dayBtn');
      await pg.waitForSelector('#rcCash', { state: 'visible', timeout: 5000 });
      await pg.focus('#rcCash');
      await new Promise((r) => setTimeout(r, 300));
      assert.strictEqual(await pg.locator('#rcCash + .hg-pad').isVisible(), false);
    }
  },
  {
    name: 'staff screens start in Spanish on a device set to English; the public menu follows the device',
    run: async ({ browser }) => {
      openRegister();
      const context = await browser.newContext({ locale: 'en-US', timezoneId: 'America/Costa_Rica' });
      const pg = await page(browser, { context, login: 'cafe', lang: 'en' });
      await pg.addInitScript(() => { try { localStorage.removeItem('hg_lang'); } catch (e) {} });
      await goto(pg, '/pos');
      await pg.waitForSelector('.pbtn', { timeout: 15000 });
      await until(async () => (await pg.locator('#ordersBtn').textContent()).trim() === 'Pedidos', 5000, 'Spanish POS');
      await goto(pg, '/m');
      await until(async () => (await pg.evaluate(() => window.HG_LANG)) === 'en', 5000, 'menu in the visitor language');
    }
  }
];
