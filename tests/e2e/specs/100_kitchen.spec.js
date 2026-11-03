/* The kitchen screen (/kitchen) with items added to a bill later (rounds), and the staff sign-in box (login.js):
   the message says why a login failed. Ported from the e2e3 suite kitchen-login-e2e.js. */
'use strict';
const assert = require('assert');
const { page, goto, until, sql } = require('../lib');
const gw = require('../gateway');

const API = 'http://127.0.0.1:' + (Number(process.env.E2E_SITE_PORT || 8090) + 1000);
const SANDWICH = 'b0000000-0000-4000-8000-0000000000a1';
const B1 = 'd0000000-0000-4000-8000-0000000000b1', B2 = 'd0000000-0000-4000-8000-0000000000b2';

/* a kitchen product with a known id (the old suite's "T Sandwich") and a bar product */
function testMenu() {
  sql(`insert into menu_categories (id, name, sort, kitchen) values
         ('b0000000-0000-4000-8000-0000000000c1', 'Test Kitchen', 20, true),
         ('b0000000-0000-4000-8000-0000000000c2', 'Test Bar', 21, false);
       insert into menu_items (id, category_id, name, price_crc, sort, available) values
         ('${SANDWICH}', 'b0000000-0000-4000-8000-0000000000c1', 'T Sandwich', 4000, 1, true),
         ('b0000000-0000-4000-8000-0000000000a2', 'b0000000-0000-4000-8000-0000000000c2', 'T Latte', 2000, 1, true);`);
}
/* the till (another device) adds to a bill, through the same API the pages use */
async function rpc(name, args) {
  const r = await fetch(API + '/rest/v1/rpc/' + name, { method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + gw.sessionFor('cafe@test.local').access_token },
    body: JSON.stringify(args) });
  const body = await r.json();
  if (!r.ok) throw new Error(name + ' ' + r.status + ' ' + JSON.stringify(body));
  return body;
}
const status = (oid) => sql(`select status from orders where id = '${oid}'`);
async function kitchen(browser) {
  const k = await page(browser, { login: 'cafe', lang: 'es', viewport: { width: 1280, height: 800 } });
  k.alerts = [];
  k.onDialog = async (d) => { k.alerts.push(d.message()); await d.accept(); };
  await goto(k, '/kitchen');
  return k;
}
/* the cook's screen one look behind: it stops looking for a moment (its 4 s poll), as if the next look had not come yet */
const freeze = (k) => k.evaluate(() => { clearInterval(pollTimer); });
const unfreeze = (k) => k.evaluate(() => { clearInterval(pollTimer); pollTimer = setInterval(poll, 4000); return poll(); });
const ticket = (k, oid) => k.locator('.tk[data-id="' + oid + '"]');

/* the sign-in box of a page, no session; the sign-in server's answer is chosen by the test */
async function signInPage(browser, path, answer) {
  const lp = await page(browser, { lang: 'es', viewport: { width: 820, height: 1180 } });
  lp.tries = 0; lp.bodies = [];
  await lp.route(/\/auth\/v1\/token/, (r) => {
    lp.tries++; lp.bodies.push(r.request().postData());
    return answer(r);
  });
  await goto(lp, path);
  return lp;
}
const reply = (status, body) => (r) => r.fulfill({ status, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: JSON.stringify(body) });

module.exports.tests = [
  {
    name: 'a delivered bill gets a sandwich added: the kitchen shows only the new round; a Ready from a screen one look behind is refused',
    run: async ({ browser }) => {
      testMenu();
      sql(`insert into orders (id, total_crc, payment_method, status, paid, source, station, pickup_number, needs_kitchen, done_at)
           values ('${B1}', 6000, 'pending', 'done', false, 'front', 'Caja', 7, true, now())`);
      sql(`insert into order_items (order_id, item_name, price_crc, qty) values ('${B1}', 'T Sandwich', 4000, 1), ('${B1}', 'T Latte', 2000, 1)`);
      const add = await rpc('tab_add_items', { p_order_id: B1, p_items: [{ menu_item_id: SANDWICH, qty: 2 }] });
      assert.ok(add.ok && add.kitchen && add.round === 2, 'added 2 sandwiches as round 2: ' + JSON.stringify(add));
      const k = await kitchen(browser);
      await k.waitForSelector('.tk:has-text("#7")', { timeout: 15000 });
      await until(async () => /Añadido al pedido/.test(await ticket(k, B1).textContent()), 8000, 'the round marked, in Spanish');
      const card = (await ticket(k, B1).textContent()).replace(/\s+/g, ' ');
      assert.ok(/2×\s*T Sandwich/.test(card) && !/T Latte/.test(card), 'the kitchen shows only the new round: ' + card);

      /* a third add lands while the cook still sees round 2: it joins round 2; a screen one round behind cannot mark it Ready */
      const add2 = await rpc('tab_add_items', { p_order_id: B1, p_items: [{ menu_item_id: SANDWICH, qty: 1 }] });
      assert.ok(add2.ok && add2.round === 2, 'added while preparing joins round 2: ' + JSON.stringify(add2));
      await freeze(k);
      await k.evaluate(() => { lastRows.forEach((o) => { if (o.pickup_number === 7) o.kitchen_round = 1; }); render(); });
      await ticket(k, B1).locator('button').click();
      await until(() => k.alerts.length > 0, 8000, 'the cook is told');
      assert.match(k.alerts[0], /Se acaba de añadir algo/, 'stale Ready refused with a clear message');
      assert.strictEqual(status(B1), 'preparing', 'still preparing');
      await unfreeze(k);
      await k.waitForSelector('.tk[data-id="' + B1 + '"] button:not([disabled])', { timeout: 8000 });
      await ticket(k, B1).locator('button').click();
      await until(() => status(B1) === 'ready', 8000, 'Ready on the current round works');
      assert.deepStrictEqual(k.errors, []);
    }
  },
  {
    name: 'something added while the kitchen is still making the order: same ticket, marked, chimes; a Ready from before is refused',
    run: async ({ browser }) => {
      testMenu();
      sql(`insert into orders (id, total_crc, payment_method, status, paid, source, station, pickup_number, needs_kitchen, accepted_at)
           values ('${B2}', 4000, 'pending', 'preparing', false, 'front', 'Caja', 12, true, now())`);
      sql(`insert into order_items (order_id, item_name, price_crc, qty, added_at) values ('${B2}', 'T Sandwich', 4000, 1, now() - interval '3 minutes')`);
      const k = await kitchen(browser);
      await k.waitForSelector('.tk:has-text("#12")', { timeout: 15000 });
      assert.ok(!/Se añadió algo/.test(await ticket(k, B2).textContent()), 'a fresh ticket has no "added" mark');
      await k.evaluate(() => { window.__chimes = []; const c = window.chime; window.chime = function (x) { window.__chimes.push(x); return c.apply(this, arguments); }; });
      /* the cook taps Ready before the screen has looked again */
      await freeze(k);
      const add3 = await rpc('tab_add_items', { p_order_id: B2, p_items: [{ menu_item_id: SANDWICH, qty: 1 }] });
      assert.ok(add3.ok && add3.round === 1, 'added while cooking stays round 1: ' + JSON.stringify(add3));
      await ticket(k, B2).locator('button').click();
      await until(() => k.alerts.length > 0, 8000, 'the cook is told');
      assert.match(k.alerts[0], /Se acaba de añadir algo/, 'stale Ready refused for an addition in the same round');
      assert.strictEqual(status(B2), 'preparing', 'still preparing');
      await unfreeze(k);
      await until(async () => /Se añadió algo/.test(await ticket(k, B2).textContent()), 10000, 'the ticket marked');
      const c12 = (await ticket(k, B2).textContent()).replace(/\s+/g, ' ');
      assert.ok(/Se añadió algo · revise el ticket/.test(c12) && (c12.match(/Nuevo/g) || []).length === 1, 'ticket marked, the new line tagged: ' + c12);
      await k.evaluate(() => { window.__chimes = []; });
      await rpc('tab_add_items', { p_order_id: B2, p_items: [{ menu_item_id: SANDWICH, qty: 1 }] });
      await until(() => k.evaluate(() => (window.__chimes || []).indexOf('new') > -1), 10000, 'the kitchen chimes for the addition');
      await k.waitForSelector('.tk[data-id="' + B2 + '"] button:not([disabled])', { timeout: 8000 });
      await until(async () => ((await ticket(k, B2).textContent()).match(/Nuevo/g) || []).length === 2, 10000, 'both new lines on the ticket');
      await ticket(k, B2).locator('button').click();
      await until(() => status(B2) === 'ready', 8000, 'Ready on the current ticket works');
      assert.deepStrictEqual(k.errors, []);
    }
  },
  {
    name: 'sign-in: the message says why (wrong password retried once without the space, not activated, too many tries)',
    run: async ({ browser }) => {
      const scenarios = [
        { body: { code: 400, error_code: 'invalid_credentials', msg: 'Invalid login credentials' }, status: 400, want: /correo o la contraseña no son correctos/, code: 'invalid_credentials' },
        { body: { code: 400, error_code: 'email_not_confirmed', msg: 'Email not confirmed' }, status: 400, want: /todavía no está activado/, code: 'email_not_confirmed' },
        { body: { code: 429, error_code: 'over_request_rate_limit', msg: 'Request rate limit reached' }, status: 429, want: /Demasiados intentos/, code: 'over_request_rate_limit' }
      ];
      for (const sc of scenarios) {
        const lp = await signInPage(browser, '/pos', reply(sc.status, sc.body));
        await lp.waitForSelector('#loginView:not([hidden])', { timeout: 15000 });
        assert.strictEqual(await lp.getAttribute('#em', 'autocapitalize'), 'none', 'the email field does not capitalise');
        assert.strictEqual(await lp.getAttribute('#pw', 'autocorrect'), 'off', 'the password field does not correct');
        assert.strictEqual(await lp.locator('.hgl-show').count(), 1, 'Show button next to the password');
        await lp.fill('#em', ' Cafe@Example.com ');
        await lp.fill('#pw', 'secreto1 ');
        await lp.click('.hgl-show');
        assert.strictEqual(await lp.getAttribute('#pw', 'type'), 'text', 'Show reveals the password');
        await until(async () => /Ocultar/.test(await lp.textContent('.hgl-show')), 8000, 'the button says Ocultar');
        await lp.click('#loginBtn');
        await until(async () => sc.want.test(await lp.textContent('#loginErr')), 8000, sc.code + ' explained');
        const msg = await lp.textContent('#loginErr');
        assert.ok(msg.indexOf(sc.code) > -1, sc.code + ': the technical reason is shown too: ' + msg);
        if (sc.code === 'invalid_credentials') {
          assert.strictEqual(lp.tries, 2, 'retried once');
          assert.match(lp.bodies[0], /"email":"cafe@example.com"/, 'the email cleaned');
          assert.match(lp.bodies[1], /"password":"secreto1"/, 'the second try without the space');
        } else assert.strictEqual(lp.tries, 1, 'no retry for ' + sc.code);
        assert.deepStrictEqual(lp.errors, []);
        await lp.context().close();
      }
    }
  },
  {
    name: 'sign-in with no way to reach the sign-in server says so (kitchen page)',
    run: async ({ browser }) => {
      const np = await signInPage(browser, '/kitchen', (r) => r.abort());
      await np.waitForSelector('#loginView:not([hidden])', { timeout: 15000 });
      await np.fill('#em', 'cafe@example.com'); await np.fill('#pw', 'x');
      await np.click('#loginBtn');
      await until(async () => /servidor de ingreso|internet/.test(await np.textContent('#loginErr')), 15000, 'a network failure explained');
      assert.ok(np.tries >= 1, 'it tried');
      assert.deepStrictEqual(np.errors, []);
    }
  },
  {
    name: 'every staff page with a sign-in box explains a refused login and has Show',
    run: async ({ browser }) => {
      for (const path of ['/sales', '/time', '/inventory', '/admin', '/home']) {
        const lp = await signInPage(browser, path, reply(400, { code: 'invalid_credentials', message: 'Invalid login credentials' }));
        await lp.waitForSelector('#loginForm', { state: 'visible', timeout: 15000 });
        await lp.fill('#em', 'cafe@example.com'); await lp.fill('#pw', 'x');
        await lp.click('#loginForm button[type=submit]');
        await until(async () => /no son correctos/.test(await lp.textContent('#loginErr')), 8000, path + ': a clear message');
        assert.strictEqual(await lp.locator('.hgl-show').count(), 1, path + ': Show next to the password');
        assert.deepStrictEqual(lp.errors, [], path + ': no page errors');
        await lp.context().close();
      }
    }
  },
  {
    name: 'the real test login signs in on the kitchen page and the board shows',
    run: async ({ browser }) => {
      /* not in the old suite (it could not sign in for real): the local stand-in answers like Supabase */
      const lp = await page(browser, { lang: 'es' });
      await goto(lp, '/kitchen');
      await lp.waitForSelector('#loginView:not([hidden])', { timeout: 15000 });
      await lp.fill('#em', 'cafe@test.local'); await lp.fill('#pw', 'test');
      await lp.click('#loginBtn');
      await lp.waitForSelector('#appView:not([hidden])', { timeout: 15000 });
      await until(async () => (await lp.locator('#board').textContent()).length > 0, 8000, 'the board');
      assert.strictEqual(lp.supabaseHits, 0, 'the real Supabase was never contacted');
      assert.deepStrictEqual(lp.errors, []);
    }
  }
];
