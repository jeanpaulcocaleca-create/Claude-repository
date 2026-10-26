/* Migration 0033 and its pages (D-053): signing out ends the unlock on the server, an unlock only works for the
   sign-in that made it, an empty PIN is never sent after the guard wipes a fill, and the team editor tells a PIN in use
   and removes a PIN lock with another manager's PIN. */
'use strict';
const assert = require('assert');
const { page, goto, until, sql, pos, STAFF, PINS } = require('../lib');

const CAFE = 'c0000000-0000-4000-8000-000000000001', OWNER = '0e000000-0000-4000-8000-000000000002';
const rowsOf = (tok) => Number(sql(`select count(*) from access_unlocks where token_hash = encode(extensions.digest('${tok}', 'sha256'), 'hex')`));
const putIn = (pg, sel, v) => pg.evaluate(([s, x]) => { const i = document.querySelector(s); i.value = x; i.dispatchEvent(new Event('input', { bubbles: true })); }, [sel, v]);
function calls(pg, re) { const seen = []; pg.on('request', (r) => { if (re.test(r.url())) seen.push(r); }); return seen; }

/* Home checks the sign-in two or three times as it loads and draws its PIN screen each time; a PIN typed into an
   earlier one is lost when the next replaces it (seen on the slower CI machine). Type only into the last one. */
async function lastGate(pg) {
  await pg.waitForSelector('.hga-wrap #hgaPin', { timeout: 10000 });
  await until(() => pg.evaluate(() => new Promise((ok) => {
    const w = document.querySelector('.hga-wrap');
    setTimeout(() => ok(!!w && w === document.querySelector('.hga-wrap') && w.querySelectorAll('#hgaWho option').length > 1), 700);
  })), 12000, 'the last PIN screen, with its list of people');
}
async function homeUnlocked(pg, who) {
  await goto(pg, '/home.html');
  await lastGate(pg);
  if (who) await pg.selectOption('#hgaWho', STAFF[who]);
  await pg.type('#hgaPin', PINS[who || 'ana']);
  await pg.press('#hgaPin', 'Enter');
  await pg.waitForSelector('.hga-pill', { timeout: 8000 });
  // Home shows #appView, checks the unlock again (HG_ACCESS.load) and hides it again if that check fails; a test that goes
  // offline before the check is answered sees the PIN screen come back (Home cannot confirm the unlock without a
  // connection, as before). networkidle and #appView fire before the check: wait for #secEmail, which Home writes only
  // once the check has passed (D-056)
  await until(() => pg.evaluate(() => !document.getElementById('appView').hidden && !!document.getElementById('secEmail').textContent), 8000, 'Home settled after its unlock check');
  return pg.evaluate(() => JSON.parse(localStorage.getItem('hg-unlock')).token);
}

module.exports.tests = [
  {
    name: 'signing out ends the unlock on the server first, with this device\'s token',
    run: async ({ browser }) => {
      const pg = await page(browser, { login: 'cafe', lang: 'es' });
      const seen = calls(pg, /rpc\/access_lock|auth\/v1\/logout/);
      const tok = await homeUnlocked(pg);
      assert.strictEqual(rowsOf(tok), 1, 'the unlock is open on the server');
      await pg.click('#outBtn');
      await pg.waitForSelector('#loginView:not([hidden])', { timeout: 8000 });
      assert.strictEqual(rowsOf(tok), 0, 'and ended there by the sign-out');
      const order = seen.map((r) => (/logout/.test(r.url()) ? 'logout' : r.url().replace(/^.*rpc\//, '')) + (r.headers()['x-hg-unlock'] ? '+token' : ''));
      assert.deepStrictEqual(order, ['access_lock+token', 'logout'], 'Lock first (with the token), then the sign-out (never with the token)');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: '«sign out everywhere» ends every unlock of that login, and no other login\'s',
    run: async ({ browser }) => {
      sql(`insert into access_unlocks (token_hash, user_id, staff_id, staff_name, staff_role, expires_at, session_id) values
             ('t350-owner-phone', '${OWNER}', '${STAFF.dueno}', 'Dueño', 'owner', now() + interval '15 minutes', 'owner-phone'),
             ('t350-cafe-tablet', '${CAFE}', '${STAFF.ana}', 'Ana', 'manager', now() + interval '15 minutes', 'cafe-tablet')`);
      const pg = await page(browser, { login: 'owner', lang: 'es' });
      await homeUnlocked(pg, 'dueno');
      assert.strictEqual(Number(sql(`select count(*) from access_unlocks where user_id = '${OWNER}'`)), 2, 'two unlocks of the owner login');
      await pg.waitForSelector('#outAllBtn', { state: 'visible', timeout: 8000 });
      await pg.click('#outAllBtn');                                         // confirm() is accepted
      await pg.waitForSelector('#loginView:not([hidden])', { timeout: 8000 });
      assert.strictEqual(Number(sql(`select count(*) from access_unlocks where user_id = '${OWNER}'`)), 0, 'all of them end');
      assert.strictEqual(Number(sql(`select count(*) from access_unlocks where user_id = '${CAFE}'`)), 1, 'the café login keeps its own');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'a token copied to another tablet of the same login opens nothing there',
    run: async ({ browser }) => {
      const a = await page(browser, { login: 'cafe', lang: 'es' });
      const tok = await homeUnlocked(a);
      const copied = JSON.stringify({ token: tok, until: new Date(Date.now() + 600000).toISOString(), localUntil: Date.now() + 600000, name: 'Ana', role: 'manager' });
      const b = await page(browser, { login: 'cafe', lang: 'es', storage: { 'hg-unlock': copied, 'hg-unlock-who': STAFF.ana, 'hg-unlock-login': CAFE } });
      await goto(b, '/home.html');
      await b.waitForSelector('.hga-wrap #hgaPin', { timeout: 10000 });
      assert.strictEqual(await b.locator('.hga-pill').count(), 0, 'tablet B asks for a PIN: its own sign-in never opened anything');
      await a.reload({ waitUntil: 'domcontentloaded' });
      await a.waitForSelector('.hga-pill', { timeout: 10000 });
      assert.strictEqual(rowsOf(tok), 1, 'tablet A is still open');
      assert.deepStrictEqual(a.errors.concat(b.errors), []);
    }
  },
  {
    name: 'signing out with no connection does not hang: the device stays signed in, as before',
    run: async ({ browser, setOffline }) => {
      const pg = await page(browser, { login: 'cafe', lang: 'es' });
      const tok = await homeUnlocked(pg);
      setOffline(true);
      const t0 = Date.now();
      await pg.click('#outBtn');
      await pg.waitForTimeout(3500);
      assert.ok(Date.now() - t0 < 8000, 'no long wait');
      assert.ok(await pg.locator('#loginView').isHidden(), 'still signed in (Supabase keeps the session when it cannot reach the server)');
      assert.strictEqual(await pg.evaluate(() => JSON.parse(localStorage.getItem('hg-unlock') || '{}').token), tok, 'and the unlock is kept for later');
      setOffline(false);
      await pg.reload({ waitUntil: 'domcontentloaded' });             // Home without a connection shows the PIN screen (as before)
      await pg.waitForSelector('.hga-pill', { timeout: 10000 });
      await pg.click('#outBtn');
      await pg.waitForSelector('#loginView:not([hidden])', { timeout: 10000 });
      assert.strictEqual(rowsOf(tok), 0, 'back online, the sign-out ends the unlock');
    }
  },
  {
    name: 'an empty PIN is never sent after the guard wipes a fill (the time clock, a POS void)',
    run: async ({ browser }) => {
      const tc = await page(browser, { login: 'cafe', lang: 'en' });
      const punches = calls(tc, /rpc\/clock_punch/);
      await goto(tc, '/time');
      await until(async () => (await tc.locator('#staffGrid button', { hasText: 'Marta' }).count()) > 0, 15000, 'the staff');
      await tc.locator('#staffGrid button', { hasText: 'Marta' }).first().click();
      await putIn(tc, '#pinInput', PINS.marta);
      assert.strictEqual(await tc.inputValue('#pinInput'), '', 'the filled-in PIN is wiped');
      await tc.click('#pinGo');
      await tc.waitForTimeout(600);
      assert.strictEqual(punches.length, 0, 'and OK sends nothing, not even an empty PIN');
      assert.deepStrictEqual(tc.errors, []);

      sql(`insert into orders (id, created_at, total_crc, payment_method, paid, status) values ('0d000000-0000-4000-8000-0000000e3501', now(), 1300, 'card', true, 'done');
           insert into order_items (order_id, item_name, price_crc, qty) values ('0d000000-0000-4000-8000-0000000e3501', 'Espresso', 1300, 1)`);
      const pg = await pos(browser);
      const voids = calls(pg, /rpc\/manager_void_order/);
      await pg.click('#ordersBtn');
      await pg.locator('.orow', { hasText: 'Espresso' }).first().locator('button', { hasText: 'Void' }).click();
      await pg.fill('#vReason', 'prueba');
      await pg.selectOption('#vMgr', STAFF.ana);
      await putIn(pg, '#vPin', PINS.ana);
      await pg.click('#vGo');
      await pg.waitForTimeout(600);
      assert.strictEqual(voids.length, 0, 'Void sends nothing either');
      assert.strictEqual(sql(`select failed_pins from staff where id = '${STAFF.ana}'`), '0', 'no wrong try counted for Ana');
      await pg.type('#vPin', PINS.ana);
      await pg.click('#vGo');
      await until(() => sql(`select voided_at is not null from orders where id = '0d000000-0000-4000-8000-0000000e3501'`) === 't', 8000, 'voided once typed');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'the team editor (Spanish): a PIN in use is told, a lock is logged, and another manager removes it with their PIN',
    run: async ({ browser }) => {
      const pg = await page(browser, { login: 'cafe', lang: 'es' });
      await goto(pg, '/time');
      await until(async () => (await pg.locator('#staffGrid button').count()) > 0, 15000, 'the clock');
      // Luis is locked out by 5 wrong PINs at the clock
      await pg.evaluate(async (luis) => { for (let i = 0; i < 5; i++) await db.rpc('clock_punch', { p_staff_id: luis, p_pin: '1111' }); }, STAFF.luis);
      assert.ok(Number(sql(`select count(*) from audit_log where action = 'pin_locked' and manager_id = '${STAFF.luis}'`)) === 1, 'the lock is logged');
      await pg.click('#tabHours');
      await pg.waitForSelector('#hoursPinModal:not([hidden])', { timeout: 10000 });
      await pg.selectOption('#hpWho', STAFF.ana);
      await pg.type('#hpPin', PINS.ana);
      await pg.click('#hoursPinForm button[type=submit]');
      await until(async () => pg.locator('#hoursPinModal').isHidden(), 8000, 'the manager opened the hours');
      await until(async () => /PIN bloqueado · Luis\s+PIN bloqueado 10 minutos tras 5 intentos incorrectos/.test(await pg.locator('#logBody').innerText()), 8000, 'the lock in the approvals log, in Spanish');
      // a PIN someone else uses
      await pg.locator('#teamBody .trow', { hasText: 'Luis' }).locator('button', { hasText: /^Editar$/ }).click();
      await pg.waitForSelector('#staffModal:not([hidden])', { timeout: 5000 });
      await until(async () => /Bloqueado tras 5 PIN incorrectos\? Quitar el bloqueo del PIN \(con el PIN de otro encargado\)/.test(await pg.locator('#stLockLine').innerText()), 5000, 'the lock line in Spanish');
      await pg.type('#stPin', PINS.marta);
      await pg.type('#stPin2', PINS.marta);
      await pg.click('#staffForm button[type=submit]');
      await until(async () => (await pg.locator('#staffErr').textContent()) === 'Ese PIN ya lo usa otra persona. Elija otro.', 8000, 'the PIN in use, in Spanish');
      // removing the lock asks for another manager's PIN; Enter (or ✓) in that box removes the lock, it does not save
      await pg.click('#stUnlockPin');
      await pg.waitForSelector('#stApprove:not([hidden])', { timeout: 5000 });
      await until(async () => (await pg.locator('#staffErr').textContent()) === 'Para quitar el bloqueo, otro encargado elige su nombre y escribe su PIN.', 5000, 'what to do, in Spanish');
      await pg.selectOption('#stMgr', STAFF.ana);
      await pg.type('#stMgrPin', PINS.ana);
      const saves = Number(sql(`select count(*) from audit_log where action = 'staff_save'`));
      await pg.press('#stMgrPin', 'Enter');
      await until(() => sql(`select failed_pins = 0 and locked_until is null from staff where id = '${STAFF.luis}'`) === 't', 8000, 'Luis unlocked');
      await until(async () => /Se quitó el bloqueo del PIN de Luis/.test(await pg.locator('body').innerText()), 5000, 'the confirmation in Spanish');
      assert.strictEqual(sql(`select manager_name from audit_log where action = 'pin_lock_cleared' and target_id = '${STAFF.luis}'`), 'Ana', 'logged with who did it');
      assert.strictEqual(Number(sql(`select count(*) from audit_log where action = 'staff_save'`)), saves, 'and nothing was saved instead');
      assert.ok(await pg.locator('#stApprove').isHidden(), 'the approval box goes away with it');
      // the next save needs no PIN, as before
      await pg.fill('#stPin', ''); await pg.fill('#stPin2', '');
      await pg.fill('#stName', 'Luis R.');
      await pg.click('#staffForm button[type=submit]');
      await until(() => sql(`select name from staff where id = '${STAFF.luis}'`) === 'Luis R.', 8000, 'the name saved without a PIN');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'PIN saves sent at the same moment wait for each other: the hourly limit holds (10 per login)',
    run: async ({ browser }) => {
      sql(`insert into audit_log (action, manager_name, target_id, summary, details)
             select 'pin_in_use', 'Ana', '', 'test', jsonb_build_object('by_login', '${CAFE}') from generate_series(1, 9)`);
      const pg = await page(browser, { login: 'cafe', lang: 'es' });
      await homeUnlocked(pg);
      const answers = await pg.evaluate(() => Promise.all(['8264', '9137', '7395'].map((pin, i) =>
        db.rpc('manager_save_staff', { p_manager_id: null, p_manager_pin: null, p_id: null, p_name: 'Junto ' + i, p_pin: pin, p_active: true, p_role: 'staff' })
          .then((r) => (r.data && (r.data.ok ? 'ok' : r.data.error)) || (r.error && r.error.message)))));
      assert.deepStrictEqual(answers.slice().sort(), ['ok', 'pin_tries', 'pin_tries'], 'one goes, the other two wait and find the 10 used: ' + answers.join(', '));
      assert.strictEqual(sql(`select count(*) from staff where name like 'Junto %'`), '1');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'a wiped PIN box that may stay empty (a new PIN when only the name changes) or is not on screen never holds Save back',
    run: async ({ browser }) => {
      const pg = await page(browser, { login: 'cafe', lang: 'es' });
      await goto(pg, '/time');
      await until(async () => (await pg.locator('#staffGrid button').count()) > 0, 15000, 'the clock');
      await pg.click('#tabHours');
      await pg.waitForSelector('#hoursPinModal:not([hidden])', { timeout: 10000 });
      await pg.selectOption('#hpWho', STAFF.ana);
      await pg.type('#hpPin', PINS.ana);
      await pg.click('#hoursPinForm button[type=submit]');
      await until(async () => pg.locator('#hoursPinModal').isHidden(), 8000, 'the manager opened the hours');
      await pg.locator('#teamBody .trow', { hasText: 'Marta' }).locator('button', { hasText: /^Editar$/ }).click();
      await pg.waitForSelector('#staffModal:not([hidden])', { timeout: 5000 });
      await putIn(pg, '#stPin', '9264');                                    // the browser fills the new PIN...
      await putIn(pg, '#stMgrPin', PINS.ana);                               // ...and the approval box that is not on screen
      assert.deepStrictEqual([await pg.inputValue('#stPin'), await pg.inputValue('#stMgrPin')], ['', ''], 'both wiped');
      assert.ok(await pg.locator('#stApprove').isHidden(), 'the approval box is not on screen');
      await pg.fill('#stName', 'Marta R.');
      await pg.click('#staffForm button[type=submit]');
      await until(() => sql(`select name from staff where id = '${STAFF.marta}'`) === 'Marta R.', 8000, 'the name saved');
      assert.strictEqual(sql(`select details->>'pin_changed' from audit_log where action = 'staff_save' order by id desc limit 1`), 'false', 'and the PIN left as it was');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'the lock removal\'s approval never gets in the way: a late answer, a wiped approval box, a list out of date',
    run: async ({ browser }) => {
      const pg = await page(browser, { login: 'cafe', lang: 'es' });
      await goto(pg, '/time');
      await until(async () => (await pg.locator('#staffGrid button').count()) > 0, 15000, 'the clock');
      await pg.evaluate(async (luis) => { for (let i = 0; i < 5; i++) await db.rpc('clock_punch', { p_staff_id: luis, p_pin: '1111' }); }, STAFF.luis);
      await pg.click('#tabHours');
      await pg.waitForSelector('#hoursPinModal:not([hidden])', { timeout: 10000 });
      await pg.selectOption('#hpWho', STAFF.ana);
      await pg.type('#hpPin', PINS.ana);
      await pg.click('#hoursPinForm button[type=submit]');
      await until(async () => pg.locator('#hoursPinModal').isHidden(), 8000, 'the manager opened the hours');
      const edit = async (who) => {
        await pg.locator('#teamBody .trow', { hasText: who }).locator('button', { hasText: /^Editar$/ }).click();
        await pg.waitForSelector('#staffModal:not([hidden])', { timeout: 5000 });
      };
      // a slow answer arrives after the manager went on to «Agregar persona»: it changes nothing there
      let release; const held = new Promise((ok) => { release = ok; });
      await pg.route('**/rest/v1/rpc/pin_lock_clear', async (route) => { await held; await route.continue(); });
      await edit('Luis');
      await pg.click('#stUnlockPin');
      await pg.click('#stCancel');
      await pg.click('#addStaffBtn');
      await pg.waitForSelector('#staffModal:not([hidden])', { timeout: 5000 });
      release();
      await pg.waitForTimeout(800);
      assert.ok(await pg.locator('#stApprove').isHidden(), 'no approval box in «Agregar persona»');
      assert.strictEqual(await pg.locator('#staffErr').textContent(), '', 'and no message from the other editor');
      await pg.unroute('**/rest/v1/rpc/pin_lock_clear');
      await pg.click('#stCancel');
      // the removal waits for a PIN; the browser fills the approval box and the guard wipes it: a name change still saves
      await edit('Luis');
      await pg.click('#stUnlockPin');
      await pg.waitForSelector('#stApprove:not([hidden])', { timeout: 5000 });
      await putIn(pg, '#stMgrPin', PINS.ana);
      assert.strictEqual(await pg.inputValue('#stMgrPin'), '', 'wiped');
      await pg.fill('#stName', 'Luis R.');
      await pg.click('#staffForm button[type=submit]');
      await until(() => sql(`select name from staff where id = '${STAFF.luis}'`) === 'Luis R.', 8000, 'the name saved, no PIN asked');
      assert.strictEqual(sql(`select locked_until > now() from staff where id = '${STAFF.luis}'`), 't', 'the lock is still there: nothing removed it');
      // Marta was made inactive on another tablet; this list still shows her active
      sql(`update staff set active = false where id = '${STAFF.marta}'`);
      await edit('Marta');
      await pg.fill('#stName', 'Marta R.');
      await pg.click('#staffForm button[type=submit]');
      await until(async () => (await pg.locator('#staffErr').textContent()) === 'Para volver a activar a alguien, póngale un PIN nuevo.', 8000, 'told to give a new PIN');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'a run of PIN locks never pushes an approval out of the approvals log',
    run: async ({ browser }) => {
      sql(`insert into audit_log (at, action, manager_id, manager_name, target_id, summary, details)
             values (now(), 'order_void', '${STAFF.ana}', 'Ana', '', 'anulación de prueba 350', '{}'::jsonb);
           insert into audit_log (at, action, manager_id, manager_name, target_id, summary, details)
             select now() + make_interval(secs => g), 'pin_locked', '${STAFF.luis}', 'Luis', '', 'PIN locked again for 10 minutes: a wrong try after the last lock ended',
                    jsonb_build_object('staff_name', 'Luis') from generate_series(1, 45) g`);   // 45 locks after the void
      const pg = await page(browser, { login: 'cafe', lang: 'es' });
      await goto(pg, '/time');
      await until(async () => (await pg.locator('#staffGrid button').count()) > 0, 15000, 'the clock');
      await pg.click('#tabHours');
      await pg.waitForSelector('#hoursPinModal:not([hidden])', { timeout: 10000 });
      await pg.selectOption('#hpWho', STAFF.ana);
      await pg.type('#hpPin', PINS.ana);
      await pg.click('#hoursPinForm button[type=submit]');
      await until(async () => /anulación de prueba 350/.test(await pg.locator('#logBody').innerText()), 8000, 'the void still in the log');
      await until(async () => (await pg.locator('#logBody .lrow', { hasText: 'PIN bloqueado otra vez 10 minutos' }).count()) === 10, 5000, 'the locks: their last 10, in Spanish');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'bringing someone back to the team asks for a new PIN (Spanish)',
    run: async ({ browser }) => {
      sql(`update staff set active = false where id = '${STAFF.marta}'`);
      const pg = await page(browser, { login: 'cafe', lang: 'es' });
      await goto(pg, '/time');
      await until(async () => (await pg.locator('#staffGrid button').count()) > 0, 15000, 'the clock');
      await pg.click('#tabHours');
      await pg.waitForSelector('#hoursPinModal:not([hidden])', { timeout: 10000 });
      await pg.selectOption('#hpWho', STAFF.ana);
      await pg.type('#hpPin', PINS.ana);
      await pg.click('#hoursPinForm button[type=submit]');
      await until(async () => pg.locator('#hoursPinModal').isHidden(), 8000, 'the manager opened the hours');
      await pg.locator('#teamBody .trow', { hasText: 'Marta' }).locator('button', { hasText: /^Editar$/ }).click();
      await pg.waitForSelector('#staffModal:not([hidden])', { timeout: 5000 });
      await until(async () => (await pg.locator('#stPinLabel').textContent()) === 'Nuevo PIN (necesario para volver a activarla)', 5000, 'the PIN label in Spanish');
      await pg.check('#stActive');
      await pg.click('#staffForm button[type=submit]');
      await until(async () => (await pg.locator('#staffErr').textContent()) === 'Para volver a activar a alguien, póngale un PIN nuevo.', 5000, 'asked for a new PIN');
      assert.strictEqual(sql(`select active from staff where id = '${STAFF.marta}'`), 'f', 'still away');
      await pg.type('#stPin', '7395');
      await pg.type('#stPin2', '7395');
      await pg.click('#staffForm button[type=submit]');
      await until(() => sql(`select active from staff where id = '${STAFF.marta}'`) === 't', 8000, 'back with a new PIN');
      assert.deepStrictEqual(pg.errors, []);
    }
  }
];
