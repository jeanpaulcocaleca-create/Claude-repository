/* PIN boxes (D-052): browsers and password managers never take them for passwords, a PIN that was not typed by a
   person opens nothing, and an unlock or the person who opened last never carries over to another login. */
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const { page, goto, until, sql, pos, openRegister, STAFF, PINS, SITE, ROOT } = require('../lib');

const CAFE = 'c0000000-0000-4000-8000-000000000001';
const opens = () => Number(sql(`select count(*) from audit_log where action = 'access_open'`));
/* the requests the page sends to a database function */
function calls(pg, fn) { const seen = []; pg.on('request', (r) => { if (r.url().includes('/rpc/' + fn)) seen.push(r.url()); }); return seen; }
/* the value put in a box with no event at all: what an extension or a password manager may do */
const putIn = (pg, sel, v) => pg.evaluate(([s, x]) => { document.querySelector(s).value = x; }, [sel, v]);

/* Home on a café device: the PIN screen with its list of people */
async function homeGate(pg) {
  await goto(pg, '/home.html');
  await pg.waitForSelector('.hga-wrap #hgaPin', { timeout: 10000 });
  await until(async () => (await pg.locator('#hgaWho option').count()) > 1, 8000, 'the list of people');
}
const picked = (pg) => pg.locator('#hgaWho option:checked').textContent();
/* the POS's Today window, which a main register also opens by itself once a day */
async function openDay(pg) {
  await pg.waitForTimeout(800);
  if (!(await pg.locator('#dayModal').isVisible())) await pg.click('#dayBtn');
  await until(async () => pg.locator('#dayModal').isVisible(), 12000, 'the Today window');
}

module.exports.tests = [
  {
    name: 'no PIN box on any page is a password box; each one says "not a password" to browsers and password managers',
    run: async ({ browser }) => {
      const sources = fs.readdirSync(path.join(ROOT, 'website')).filter((f) => f.endsWith('.html'))
        .map((f) => [f, fs.readFileSync(path.join(ROOT, 'website', f), 'utf8')])
        .concat([['access.js', fs.readFileSync(path.join(ROOT, 'website/access.js'), 'utf8').replace(/' \+\s*'/g, '')]]);
      let pins = 0;
      for (const [f, src] of sources) {
        for (const tag of src.match(/<input\b[^>]*>/g) || []) {
          if (/type="password"/.test(tag)) {
            assert.match(tag, /id="pw[12]?"/, f + ': only the sign-in password is a password box: ' + tag);
            continue;
          }
          if (!/\bdata-pin\b/.test(tag) && !/id="[^"]*pin\d?"/i.test(tag)) continue;    // a PIN box, or one named like one
          pins++;
          for (const want of ['type="text"', 'data-pin', 'autocomplete="off"', 'data-1p-ignore', 'data-lpignore="true"', 'data-bwignore', 'data-form-type="other"']) {
            assert.ok(tag.includes(want), f + ': a PIN box without ' + want + ': ' + tag);
          }
        }
      }
      assert.strictEqual(pins, 19, 'every PIN box was checked (18 on the pages, the time clock team editor included, and the PIN screen)');

      const pg = await page(browser, { login: 'cafe', lang: 'es' });
      await homeGate(pg);
      const box = await pg.evaluate(() => {
        const i = document.getElementById('hgaPin');
        return { type: i.type, dots: getComputedStyle(i).webkitTextSecurity, passwords: document.querySelectorAll('input[type=password]').length,
                 loginPw: document.querySelectorAll('input[type=password]#pw').length };
      });
      assert.deepStrictEqual(box, { type: 'text', dots: 'disc', passwords: 1, loginPw: 1 }, 'the PIN is drawn as dots; the only password box is the sign-in one');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'a PIN put in by the browser opens nothing and never reaches the database; the same PIN typed opens',
    run: async ({ browser }) => {
      const pg = await page(browser, { login: 'cafe', lang: 'es' });
      await homeGate(pg);
      const sent = calls(pg, 'access_unlock');
      const before = opens();
      // the way a browser or password manager fills a box: the value and an "input" event, no key pressed
      await pg.evaluate((p) => { const i = document.getElementById('hgaPin'); i.value = p; i.dispatchEvent(new Event('input', { bubbles: true })); }, PINS.ana);
      assert.strictEqual(await pg.inputValue('#hgaPin'), '', 'a filled-in PIN is wiped at once');
      // filled in without any event, then an Enter (a second Enter after signing in, or "fill and send")
      await pg.evaluate((p) => { document.getElementById('hgaPin').value = p; }, PINS.ana);
      await pg.press('#hgaPin', 'Enter');
      await pg.waitForTimeout(800);
      assert.strictEqual(await pg.inputValue('#hgaPin'), '', 'and wiped when the form tries to go');
      assert.strictEqual(opens(), before, 'nothing was opened');
      assert.strictEqual(sent.length, 0, 'the PIN was never sent to the database');
      assert.strictEqual(await pg.locator('.hga-pill').count(), 0, 'no "owner areas open" notice');
      assert.ok(await pg.locator('.hga-wrap').isVisible(), 'the PIN screen is still there');

      await pg.type('#hgaPin', PINS.ana);
      await pg.press('#hgaPin', 'Enter');
      await pg.waitForSelector('.hga-pill', { timeout: 8000 });
      assert.strictEqual(opens(), before + 1, 'typed by a person, it opens');
      assert.strictEqual(sent.length, 1, 'with one request');
      assert.match(await pg.locator('.hga-pill span').textContent(), /Ana/);
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'a PIN cannot be copied out of its box; a browser that cannot draw the dots gets a password box, still guarded',
    run: async ({ browser }) => {
      const pg = await page(browser, { login: 'cafe', lang: 'es' });
      await homeGate(pg);
      await pg.context().grantPermissions(['clipboard-read', 'clipboard-write'], { origin: SITE });
      await pg.evaluate(() => navigator.clipboard.writeText('nada'));
      await pg.type('#hgaPin', PINS.ana);
      await pg.focus('#hgaPin');
      await pg.keyboard.press('Control+A');
      await pg.keyboard.press('Control+C');
      await pg.keyboard.press('Control+X');
      assert.strictEqual(await pg.evaluate(() => navigator.clipboard.readText()), 'nada', 'Ctrl+C and Ctrl+X copy nothing out of the PIN box');
      assert.strictEqual(await pg.inputValue('#hgaPin'), PINS.ana, 'and the PIN typed stays as it was');
      // pasting is a person's own act: it still works, as in a password box
      await pg.evaluate((p) => navigator.clipboard.writeText(p), PINS.ana);
      await pg.fill('#hgaPin', '');
      await pg.focus('#hgaPin');
      await pg.keyboard.press('Control+V');
      assert.strictEqual(await pg.inputValue('#hgaPin'), PINS.ana, 'a PIN pasted by a person counts');

      const old = await page(browser, { login: 'cafe', lang: 'es' });
      await old.addInitScript(() => {
        const s = CSS.supports.bind(CSS);
        CSS.supports = function (p, v) { return /text-security/.test(String(p)) ? false : s.apply(null, arguments); };
      });
      await homeGate(old);
      assert.strictEqual(await old.evaluate(() => document.getElementById('hgaPin').type), 'password', 'no dots: a password box');
      const before = opens();
      await old.evaluate((p) => { const i = document.getElementById('hgaPin'); i.value = p; i.dispatchEvent(new Event('input', { bubbles: true })); }, PINS.ana);
      await old.press('#hgaPin', 'Enter');
      await old.waitForTimeout(800);
      assert.strictEqual(opens(), before, 'a filled-in PIN still opens nothing');
      await old.type('#hgaPin', PINS.ana);
      await old.press('#hgaPin', 'Enter');
      await old.waitForSelector('.hga-pill', { timeout: 8000 });
      assert.deepStrictEqual(pg.errors.concat(old.errors), []);
    }
  },
  {
    name: 'a PIN with no key of its own is wiped, even when the browser calls the change trusted',
    run: async ({ browser }) => {
      const pg = await page(browser, { login: 'cafe', lang: 'es' });
      await homeGate(pg);
      const sent = calls(pg, 'access_unlock');
      // a trusted change with no key: what the browser's autofill and an extension's execCommand produce
      await pg.focus('#hgaPin');
      await pg.evaluate((p) => document.execCommand('insertText', false, p), PINS.ana);
      assert.strictEqual(await pg.inputValue('#hgaPin'), '', 'a trusted change with no key is wiped');
      // a key that changes nothing (a 9th digit), then a change with no key at once
      await pg.type('#hgaPin', '12345678');
      await pg.keyboard.press('9');
      await pg.evaluate((p) => { const i = document.getElementById('hgaPin'); i.select(); document.execCommand('insertText', false, p); }, PINS.ana);
      assert.strictEqual(await pg.inputValue('#hgaPin'), '', 'the 9th digit leaves no mark for the next change');
      await pg.type('#hgaPin', '12345678');
      await pg.keyboard.press('9');
      await pg.evaluate(() => { const i = document.getElementById('hgaPin'); i.select(); document.execCommand('insertText', false, '9'); });
      assert.strictEqual(await pg.inputValue('#hgaPin'), '', 'not even for a change with the same text as that key');
      // a PIN typed, the box emptied by the page (as every page does after a try), then the same PIN put in with no key
      await pg.fill('#hgaPin', '');
      await pg.type('#hgaPin', PINS.ana);
      await pg.evaluate(() => { document.getElementById('hgaPin').value = ''; });
      await pg.click('#hgaWho');
      await pg.keyboard.press('Escape');
      await putIn(pg, '#hgaPin', PINS.ana);
      await pg.press('#hgaPin', 'Enter');
      assert.strictEqual(await pg.inputValue('#hgaPin'), '', 'an emptied box does not keep the PIN typed before');
      // a key on top of a PIN put in with no event
      await putIn(pg, '#hgaPin', PINS.ana.slice(0, 3));
      await pg.focus('#hgaPin');
      await pg.keyboard.press('End');
      await pg.keyboard.type(PINS.ana.slice(3));
      assert.strictEqual(await pg.inputValue('#hgaPin'), '', 'one key on top of a filled-in PIN does not make it typed');
      await pg.press('#hgaPin', 'Enter');
      // a form sent with no click at all, as the on-screen pad's ✓ does (requestSubmit)
      await putIn(pg, '#hgaPin', PINS.ana);
      await pg.evaluate(() => document.querySelector('.hga-box').requestSubmit());
      assert.strictEqual(await pg.inputValue('#hgaPin'), '', 'a form sent without a click wipes the filled-in PIN');
      await pg.waitForTimeout(600);
      assert.strictEqual(sent.length, 0, 'nothing was sent');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'a person\'s own ways of entering a PIN still count: a phone keyboard, Backspace and undo, a paste with a line break',
    run: async ({ browser }) => {
      const pg = await page(browser, { login: 'cafe', lang: 'es' });
      await homeGate(pg);
      const cdp = await pg.context().newCDPSession(pg);
      await pg.focus('#hgaPin');
      // a phone keyboard that composes each digit, and drops one digit while composing it
      for (const d of PINS.ana.slice(0, 2)) { await cdp.send('Input.imeSetComposition', { text: d, selectionStart: 1, selectionEnd: 1 }); await cdp.send('Input.insertText', { text: d }); }
      await cdp.send('Input.imeSetComposition', { text: PINS.ana[2], selectionStart: 1, selectionEnd: 1 });
      await cdp.send('Input.imeSetComposition', { text: '', selectionStart: 0, selectionEnd: 0 });
      assert.strictEqual(await pg.inputValue('#hgaPin'), PINS.ana.slice(0, 2), 'a digit dropped while composing leaves the others');
      for (const d of PINS.ana.slice(2)) { await cdp.send('Input.imeSetComposition', { text: d, selectionStart: 1, selectionEnd: 1 }); await cdp.send('Input.insertText', { text: d }); }
      assert.strictEqual(await pg.inputValue('#hgaPin'), PINS.ana, 'composed digits count');
      // Backspace, then undo
      await pg.keyboard.press('Backspace');
      await pg.keyboard.press('Control+Z');
      assert.strictEqual(await pg.inputValue('#hgaPin'), PINS.ana, 'Backspace and undo count');
      // a PIN copied with its line break (a spreadsheet cell, a line of a note)
      await pg.context().grantPermissions(['clipboard-read', 'clipboard-write'], { origin: SITE });
      await pg.evaluate((p) => navigator.clipboard.writeText(p + '\r\n'), PINS.ana);
      await pg.fill('#hgaPin', '');
      await pg.focus('#hgaPin');
      await pg.keyboard.press('Control+V');
      assert.strictEqual(await pg.inputValue('#hgaPin'), PINS.ana, 'a pasted PIN with a line break counts');
      await pg.press('#hgaPin', 'Enter');
      await pg.waitForSelector('.hga-pill', { timeout: 8000 });
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'a touch screen: the on-screen keys type and ✓ sends; the same keys pressed by a script type nothing',
    run: async ({ browser }) => {
      const context = await browser.newContext({ viewport: { width: 1180, height: 820 }, hasTouch: true, locale: 'es-CR', timezoneId: 'America/Costa_Rica' });
      const pg = await page(browser, { context, login: 'cafe', lang: 'es' });
      await homeGate(pg);
      await pg.focus('#hgaPin');
      const pad = pg.locator('#hgaPin + .hg-pad');
      await until(async () => pad.isVisible(), 5000, 'the PIN pad');
      await pg.evaluate((p) => { const pad = document.querySelector('#hgaPin + .hg-pad'); for (const d of p) [...pad.querySelectorAll('button')].find((b) => b.textContent === d).click(); }, PINS.ana);
      assert.strictEqual(await pg.inputValue('#hgaPin'), '', 'keys pressed by a script type nothing');
      for (const d of PINS.ana) await pad.locator('button', { hasText: new RegExp('^' + d + '$') }).click();
      assert.strictEqual(await pg.inputValue('#hgaPin'), PINS.ana, 'the person\'s taps type');
      await pad.locator('button.ok').click();
      await pg.waitForSelector('.hga-pill', { timeout: 8000 });
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'buttons that read the PIN themselves (Void an order, Void a cash move) send nothing when the PIN was not typed',
    run: async ({ browser }) => {
      sql(`insert into orders (id, created_at, total_crc, payment_method, paid, status) values ('0d000000-0000-4000-8000-0000000e2e34', now(), 1300, 'card', true, 'done');
           insert into order_items (order_id, item_name, price_crc, qty) values ('0d000000-0000-4000-8000-0000000e2e34', 'Espresso', 1300, 1)`);
      let pg = await pos(browser);
      const withPin = [];
      pg.on('request', (r) => { if ((r.postData() || '').includes(PINS.ana) || /"p_(manager_)?pin":""/.test(r.postData() || '')) withPin.push(r.url()); });
      // the order's Void: its own button (data-keypad-ok)
      await pg.click('#ordersBtn');
      await pg.locator('.orow', { hasText: 'Espresso' }).first().locator('button', { hasText: 'Void' }).click();
      await pg.fill('#vReason', 'prueba');
      await pg.selectOption('#vMgr', STAFF.ana);
      await putIn(pg, '#vPin', PINS.ana);
      await pg.click('#vGo');
      await pg.waitForTimeout(600);
      assert.strictEqual(withPin.length, 0, 'Void: no PIN sent, not even an empty one (a wrong try)');
      assert.strictEqual(await pg.inputValue('#vPin'), '', 'Void: the filled-in PIN is wiped');
      assert.strictEqual(sql(`select voided_at is null from orders where id = '0d000000-0000-4000-8000-0000000e2e34'`), 't', 'Void: nothing voided');
      await pg.type('#vPin', PINS.ana);
      await pg.click('#vGo');
      await until(() => sql(`select voided_at is not null from orders where id = '0d000000-0000-4000-8000-0000000e2e34'`) === 't', 8000, 'voided with the PIN typed');
      assert.deepStrictEqual(pg.errors, []);

      // a cash move's Void: a button with no link to its PIN box, in the same window
      await pg.context().close();
      pg = await pos(browser, { register: false });
      pg.on('request', (r) => { if ((r.postData() || '').includes(PINS.ana) || /"p_(manager_)?pin":""/.test(r.postData() || '')) withPin.push(r.url()); });
      await pg.click('#dayBtn');
      await pg.waitForSelector('#cmBtn', { state: 'visible', timeout: 10000 });
      await pg.click('#cmBtn');
      await pg.selectOption('#cmKind', 'out:petty');
      await pg.fill('#cmAmt', '9999');
      await pg.fill('#cmWhy', 'error');
      await pg.selectOption('#cmStaff', STAFF.ana);
      await pg.type('#cmPin', PINS.ana);
      await pg.click('#regMoveForm button[type=submit]');
      await until(() => sql(`select count(*) from cash_movements`) === '1', 8000, 'a cash move saved with the PIN typed');
      await until(async () => (await pg.locator('#cmList button', { hasText: 'Void' }).count()) === 1, 8000, 'its Void button');
      const before = withPin.length;
      let asked = 0;
      pg.onDialog = async (d) => { asked++; await d.dismiss(); };
      await pg.locator('#cmList button', { hasText: 'Void' }).first().click();            // shows the manager and PIN boxes
      await pg.selectOption('#cmStaff', STAFF.ana);
      await putIn(pg, '#cmPin', PINS.ana);
      await pg.evaluate(() => { document.getElementById('cmErr').textContent = ''; });
      await pg.locator('#cmList button', { hasText: 'Void' }).first().click();
      await pg.waitForTimeout(600);
      assert.strictEqual(await pg.locator('#cmErr').textContent(), '', 'cash Void: its button never ran (the click stopped in its window)');
      assert.strictEqual(asked, 0, 'cash Void: not even the reason is asked');
      assert.strictEqual(withPin.length, before, 'cash Void: nothing sent');
      assert.strictEqual(await pg.inputValue('#cmPin'), '', 'cash Void: the filled-in PIN is wiped');
      await pg.type('#cmPin', PINS.ana);
      pg.onDialog = (d) => d.accept('monto equivocado');
      await pg.locator('#cmList button', { hasText: 'Void' }).first().click();
      await until(() => sql(`select count(*) from cash_movements where voided_at is not null`) === '1', 8000, 'voided with the PIN typed');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'the time clock: deleting a shift sends nothing when the manager PIN was not typed',
    run: async ({ browser }) => {
      sql(`insert into time_entries (staff_id, clock_in, clock_out) values ('${STAFF.luis}', now() - interval '5 hours', now() - interval '1 hour')`);
      const pg = await page(browser, { login: 'cafe', lang: 'en' });
      const del = calls(pg, 'manager_delete_shift');
      let asked = 0;
      pg.onDialog = async (d) => { asked++; await d.accept(); };
      await goto(pg, '/time');
      await pg.click('#tabHours');
      await pg.waitForSelector('#hoursPinModal:not([hidden])', { timeout: 10000 });
      await pg.selectOption('#hpWho', STAFF.ana);
      await pg.type('#hpPin', PINS.ana);
      await pg.click('#hoursPinForm button[type=submit]');
      await until(async () => pg.locator('#hoursPinModal').isHidden(), 8000, 'the manager opened the hours');
      await until(async () => (await pg.locator('button', { hasText: /^Edit$/ }).count()) > 0, 8000, 'the shift');
      await pg.locator('button', { hasText: /^Edit$/ }).first().click();
      await pg.waitForSelector('#shiftModal:not([hidden])', { timeout: 5000 });
      await pg.fill('#shReason', 'prueba');
      await pg.selectOption('#shMgr', STAFF.ana);
      await putIn(pg, '#shPin', PINS.ana);
      await pg.click('#shDelete');
      await pg.waitForTimeout(600);
      assert.strictEqual(asked, 0, 'not even the confirmation is asked');
      assert.strictEqual(del.length, 0, 'nothing sent');
      assert.strictEqual(await pg.inputValue('#shPin'), '', 'the filled-in PIN is wiped');
      await pg.type('#shPin', PINS.ana);
      await pg.click('#shDelete');
      await until(() => del.length === 1, 8000, 'sent with the PIN typed');
      assert.strictEqual(asked, 1, 'asked once');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'the time clock: its own keys still punch; a PIN put in by the browser does not',
    run: async ({ browser }) => {
      const pg = await page(browser, { login: 'cafe', lang: 'es' });
      await goto(pg, '/time.html');
      await until(async () => (await pg.locator('#staffGrid button', { hasText: 'Marta' }).count()) > 0, 15000, 'the staff');
      const punches = () => sql(`select count(*) from time_entries where staff_id = '${STAFF.marta}'`);
      const sent = calls(pg, 'clock_punch');
      await pg.locator('#staffGrid button', { hasText: 'Marta' }).first().click();
      await pg.evaluate((p) => { document.getElementById('pinInput').value = p; }, PINS.marta);
      await pg.click('#pinGo');
      await pg.waitForTimeout(800);
      assert.strictEqual(punches(), '0', 'a PIN nobody typed punches nobody in');
      assert.strictEqual(sent.length, 0, 'and was never sent to the database');
      await pg.evaluate((p) => { for (const d of p) document.querySelector(`#pinPad button[data-k="${d}"]`).click(); }, PINS.marta);
      assert.strictEqual(await pg.inputValue('#pinInput'), '', 'its keys pressed by a script type nothing');
      for (const d of PINS.marta) await pg.click(`#pinPad button[data-k="${d}"]`);
      await pg.click('#pinGo');
      await until(() => punches() === '1', 8000, 'the punch with the keys on the screen');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'signing out takes the notice down and forgets the unlock; the next login is not offered the person of the last one',
    run: async ({ browser }) => {
      // the shared login of today opens with the owner's PIN on this device
      const pg = await page(browser, { login: 'owner', lang: 'es' });
      await homeGate(pg);
      await pg.selectOption('#hgaWho', STAFF.dueno);
      await pg.type('#hgaPin', PINS.dueno);
      await pg.press('#hgaPin', 'Enter');
      await pg.waitForSelector('.hga-pill', { timeout: 8000 });
      const keys = () => pg.evaluate(() => ['hg-unlock', 'hg-unlock-who', 'hg-unlock-login'].map((k) => localStorage.getItem(k) !== null));
      assert.deepStrictEqual((await keys()).slice(0, 2), [true, true], 'the unlock and who opened are kept on this device');
      assert.strictEqual(await pg.evaluate(() => localStorage.getItem('hg-unlock-login')), '0e000000-0000-4000-8000-000000000002', 'for this login');

      await pg.click('#outBtn');                                  // Home signs out without reloading the page
      await pg.waitForSelector('#loginView:not([hidden])', { timeout: 8000 });
      assert.strictEqual(await pg.locator('.hga-pill').count(), 0, 'the notice is gone with the login');
      assert.deepStrictEqual(await keys(), [false, false, false], 'the unlock, who opened and their login are forgotten');

      // the café login signs in on the same device, the same page
      await pg.fill('#em', 'cafe@test.local');
      await pg.fill('#pw', 'test');
      await pg.press('#pw', 'Enter');
      await pg.waitForSelector('.hga-wrap #hgaPin', { timeout: 10000 });
      await until(async () => (await pg.locator('#hgaWho option').count()) > 1, 8000, 'the list of people');
      assert.match(await picked(pg), /^Ana/, 'the list starts at the top, not at the person who opened on the other login');
      assert.strictEqual(await pg.locator('.hga-pill').count(), 0, 'nothing shows as open');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'a check still on its way when the login signs out never brings the notice back',
    run: async ({ browser }) => {
      const pg = await page(browser, { login: 'cafe', lang: 'es' });
      await homeGate(pg);
      await pg.type('#hgaPin', PINS.ana);
      await pg.press('#hgaPin', 'Enter');
      await pg.waitForSelector('.hga-pill', { timeout: 8000 });
      // the next "what is open here" answer is held back until after the sign-out (Home's own refresh has finished first)
      await pg.waitForLoadState('networkidle');
      let release, held = false;
      const gate = new Promise((ok) => { release = ok; });
      await pg.route('**/rest/v1/rpc/access_state', async (route) => {
        if (held) return route.continue();
        held = true; await gate; return route.continue();
      });
      await pg.evaluate(() => { window.__late = HG_ACCESS.load(db).then((st) => { if (st && st.level) HG_ACCESS.pill(db); return st; }); });
      await until(() => held, 5000, 'the check on its way');
      await pg.click('#outBtn');
      await pg.waitForSelector('#loginView:not([hidden])', { timeout: 8000 });
      assert.strictEqual(await pg.locator('.hga-pill').count(), 0, 'the notice went with the login');
      release();
      const late = await pg.evaluate(() => window.__late);
      assert.strictEqual(late.level, 'manager', 'the late answer did come back');
      await pg.waitForTimeout(300);
      assert.strictEqual(await pg.locator('.hga-pill').count(), 0, 'and did not bring the notice back');
      assert.strictEqual(await pg.evaluate(() => HG_ACCESS.state()), null, 'nothing kept from it');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'another tab signing out takes this tab\'s notice down too, even when that tab already forgot everything',
    run: async ({ browser }) => {
      // the deterministic case: the other tab has already removed what this login kept, then the sign-out reaches this tab
      const pg = await page(browser, { login: 'cafe', lang: 'es' });
      await homeGate(pg);
      await pg.type('#hgaPin', PINS.ana);
      await pg.press('#hgaPin', 'Enter');
      await pg.waitForSelector('.hga-pill', { timeout: 8000 });
      await pg.evaluate(() => ['hg-unlock', 'hg-unlock-who', 'hg-unlock-login'].forEach((k) => localStorage.removeItem(k)));
      await pg.click('#outBtn');
      await pg.waitForSelector('#loginView:not([hidden])', { timeout: 8000 });
      assert.strictEqual(await pg.locator('.hga-pill').count(), 0, 'the notice goes');
      assert.strictEqual(await pg.evaluate(() => HG_ACCESS.state()), null, 'and nothing of it is kept on the page');
      await pg.context().close();
      // two real tabs of one browser: the second signs out
      const ctx = await browser.newContext({ locale: 'es-CR', timezoneId: 'America/Costa_Rica' });
      const a = await page(browser, { context: ctx, login: 'cafe', lang: 'es' });
      await homeGate(a);
      await a.type('#hgaPin', PINS.ana);
      await a.press('#hgaPin', 'Enter');
      await a.waitForSelector('.hga-pill', { timeout: 8000 });
      const b = await page(browser, { context: ctx, login: 'cafe', lang: 'es' });
      await goto(b, '/home.html');
      await b.waitForSelector('.hga-pill', { timeout: 10000 });
      await b.click('#outBtn');
      await b.waitForSelector('#loginView:not([hidden])', { timeout: 8000 });
      await until(async () => (await a.locator('.hga-pill').count()) === 0, 8000, 'the first tab\'s notice gone');
      assert.deepStrictEqual(a.errors, []);
      await ctx.close();
    }
  },
  {
    name: 'the POS: after signing out and in with another login on the same page, the register lists start at the top',
    run: async ({ browser }) => {
      const pg = await page(browser, { login: 'cafe', lang: 'en' });
      await goto(pg, '/pos');
      await pg.waitForSelector('.pbtn', { timeout: 15000 });
      await openDay(pg);                                          // a main register opens Today by itself once a day
      await pg.waitForSelector('#regOpenForm:not([hidden])', { timeout: 10000 });
      await until(async () => (await pg.locator('#roStaff option').count()) > 1, 8000, 'who is opening');
      await pg.selectOption('#roStaff', STAFF.dueno);
      await pg.type('#roPin', PINS.dueno);
      await pg.fill('#roFloat', '50000');
      await pg.click('#regOpenForm button[type=submit]');
      await until(() => sql(`select opened_by_name from register_days where business_date = cr_today()`) === 'Dueño', 10000, 'the register opened by Dueño');
      // the same login, the next time the page loads: the person who opened is offered to close, as before
      await pg.reload({ waitUntil: 'domcontentloaded' });
      await pg.waitForSelector('.pbtn', { timeout: 15000 });
      await openDay(pg);
      await pg.waitForSelector('#regCloseForm:not([hidden])', { timeout: 8000 });
      await until(async () => (await pg.locator('#rcStaff option').count()) > 1, 8000, 'who is closing');
      assert.strictEqual(await pg.locator('#rcStaff').inputValue(), STAFF.dueno, 'the same login: the person who opened is offered to close');
      await pg.click('#dayClose');
      await pg.click('#outBtn');
      await pg.waitForSelector('#loginView:not([hidden])', { timeout: 8000 });
      await pg.fill('#em', 'owner@test.local');
      await pg.fill('#pw', 'test');
      await pg.press('#pw', 'Enter');
      await pg.waitForSelector('#appView:not([hidden])', { timeout: 10000 });
      await openDay(pg);
      await pg.waitForSelector('#regCloseForm:not([hidden])', { timeout: 10000 });
      await until(async () => (await pg.locator('#rcStaff option').count()) > 1, 8000, 'who is closing');
      assert.notStrictEqual(await pg.locator('#rcStaff').inputValue(), STAFF.dueno, 'another login: the person the last login remembered is not chosen');
      assert.notStrictEqual(await pg.locator('#cmStaff').inputValue(), STAFF.dueno, 'nor for a cash move');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'who opened last is offered again only to the login that saved it',
    run: async ({ browser }) => {
      const cases = [
        [{ 'hg-unlock-who': STAFF.dueno, 'hg-unlock-login': CAFE }, /^Dueño/, 'the same login: offered first, as before'],
        [{ 'hg-unlock-who': STAFF.dueno, 'hg-unlock-login': '0e000000-0000-4000-8000-000000000002' }, /^Ana/, 'saved by another login: not offered'],
        [{ 'hg-unlock-who': STAFF.dueno }, /^Ana/, 'saved by an older version, login unknown: not offered']
      ];
      for (const [storage, want, what] of cases) {
        const pg = await page(browser, { login: 'cafe', lang: 'es', storage });
        await homeGate(pg);
        assert.match(await picked(pg), want, what);
        assert.deepStrictEqual(pg.errors, []);
        await pg.context().close();
      }
      // the POS register's last person follows the same rule
      openRegister();
      for (const [login, want] of [[CAFE, STAFF.dueno], ['0e000000-0000-4000-8000-000000000002', null]]) {
        const p2 = await pos(browser, { register: false, storage: { 'hg-pos-reg-staff': STAFF.dueno, 'hg-unlock-login': login } });
        await until(async () => (await p2.evaluate(() => localStorage.getItem('hg-unlock-login'))) === CAFE, 8000, 'the POS knows its login');
        assert.strictEqual(await p2.evaluate(() => localStorage.getItem('hg-pos-reg-staff')), want,
                           want ? 'the register person kept by the same login stays' : 'the register person kept by another login is forgotten');
        assert.deepStrictEqual(p2.errors, []);
        await p2.context().close();
      }
      // an unlock another login left on the device is dropped by the page's first check, and never shown as open
      // (requests sent before that check may still carry it: the database ignores it for any other login, section 2 of SQL 380)
      const pg = await page(browser, { login: 'cafe', lang: 'es', storage: {
        'hg-unlock': JSON.stringify({ token: 'ff'.repeat(24), until: new Date(Date.now() + 600000).toISOString(), localUntil: Date.now() + 600000, name: 'Dueño', role: 'owner' }),
        'hg-unlock-who': STAFF.dueno, 'hg-unlock-login': '0e000000-0000-4000-8000-000000000002' } });
      const carried = [];
      pg.on('request', (r) => { if (r.headers()['x-hg-unlock'] && /rpc\/access_state|\/rest\/v1\/staff/.test(r.url())) carried.push(r.url()); });
      await homeGate(pg);
      assert.deepStrictEqual(carried, [], 'the check of what is open, and everything after it, go without the other login\'s unlock');
      assert.strictEqual(await pg.locator('.hga-pill').count(), 0, 'no notice');
      assert.deepStrictEqual(await pg.evaluate(() => ['hg-unlock', 'hg-unlock-who'].map((k) => localStorage.getItem(k))), [null, null], 'both forgotten');
      assert.deepStrictEqual(pg.errors, []);
    }
  }
];
