/* Open orders kept on this device (pos.html: queue, openLocal, qSteps): a lost reply then a refusal, kitchen items,
   a bill changed on another device, lines already there, offline, paid after midnight, an old queued sale, an item
   gone from the menu, a bill cancelled elsewhere. Ported from the e2e3 suite open-local-e2e3.js.
   The till now saves a sale with ONE call (rpc/pos_record_sale); the failures are injected on that call:
     lost    the sale reaches the database, the reply is lost (connection reset)
     jwt     401 JWT expired (a sure "no" to that try)
     server  503, the system not answering (not sure)
     refused 400, the database refused the sale (sure) */
'use strict';
const assert = require('assert');
const { page, goto, until, sql, openRegister } = require('../lib');

const id = (n) => 'f1000000-0000-4000-8000-0000000060' + String(n).padStart(2, '0');
const CORS = { 'access-control-allow-origin': '*' };
/* a sale rung 15 minutes ago, to pay later, with its number and lines [name, price, qty] */
const later = (n, num, lines, extra) => Object.assign({ local_id: 'o' + n, id: id(n), created_at: new Date(Date.now() - 15 * 60000).toISOString(),
  total_crc: lines.reduce((s, l) => s + l[1] * l[2], 0), payment_method: 'pending', pickup_number: num, needs_kitchen: false,
  status: 'ready', paid: false, none: true, station: 'Caja', guest_name: null,
  items: lines.map((l, i) => ({ id: 'f1000000-0000-4000-8000-' + String(700000000000 + n * 10 + i), item_name: l[0], price_crc: l[1], qty: l[2] })) }, extra || {});
/* the order as the system has it: total|paid|method|status|needs kitchen|lines */
const dbo = (n) => sql(`select total_crc || '|' || paid || '|' || payment_method || '|' || status || '|' || needs_kitchen || '|' ||
  coalesce((select string_agg(qty || 'x' || item_name, ',' order by item_name) from order_items where order_id = o.id), '') from orders o where id = '${id(n)}'`);

/* a kitchen product (the old suite's "T Sandwich"); Latte and Espresso come from the café menu */
function kitchenItem() {
  sql(`insert into menu_categories (id, name, sort, kitchen) values ('b0000000-0000-4000-8000-0000000000c1', 'Test Kitchen', 20, true);
       insert into menu_items (id, category_id, name, price_crc, sort, available)
       values ('b0000000-0000-4000-8000-0000000000a1', 'b0000000-0000-4000-8000-0000000000c1', 'T Sandwich', 4000, 1, true);`);
}

/* a till on its own device; the tests drive every round themselves: the till's own 20 s retry is off */
async function device(browser) {
  openRegister();
  const pg = await page(browser, { login: 'cafe', lang: 'en', viewport: { width: 1180, height: 820 } });
  await pg.addInitScript(() => {
    const si = window.setInterval;
    window.setInterval = function (fn, ms) { return ms === 20000 ? 0 : si.apply(this, arguments); };
  });
  pg.fail = null; pg.calls = {}; pg.payFail = 0;
  await pg.route(/rest\/v1\/rpc\/pos_record_sale/, async (r) => {
    if (r.request().method() !== 'POST' || !pg.fail) return r.fallback();
    const k = pg.fail;
    if (k === 'lost') {   /* reaches the database, the reply is lost */
      await r.fetch().catch(() => {});
      return r.abort('connectionreset');
    }
    if (k === 'jwt') return r.fulfill({ status: 401, contentType: 'application/json', headers: CORS, body: JSON.stringify({ code: 'PGRST301', message: 'JWT expired' }) });
    if (k === 'server') return r.fulfill({ status: 503, contentType: 'text/plain', headers: CORS, body: 'down' });
    return r.fulfill({ status: 400, contentType: 'application/json', headers: CORS, body: JSON.stringify({ code: '23514', message: 'violates check constraint' }) });
  });
  await pg.route(/rest\/v1\/rpc\/tab_pay/, (r) => {
    if (r.request().method() !== 'POST') return r.fallback();
    pg.calls.pay = (pg.calls.pay || 0) + 1;
    return pg.payFail-- > 0 ? r.fulfill({ status: 503, contentType: 'text/plain', headers: CORS, body: 'down' }) : r.fallback();
  });
  await pg.route(/rest\/v1\/rpc\/tab_add_items/, (r) => { if (r.request().method() === 'POST') pg.calls.add = (pg.calls.add || 0) + 1; return r.fallback(); });
  await goto(pg, '/pos');
  await pg.waitForSelector('#appView:not([hidden])', { timeout: 15000 });
  await pg.waitForFunction(() => document.querySelectorAll('.pbtn').length > 0, null, { timeout: 15000 });
  if (await pg.isVisible('#dayModal')) await pg.click('#dayClose');
  if (await pg.isVisible('#stationModal')) await pg.click('#stationForm button[type=submit]');
  await pg.evaluate(() => { clearInterval(liveTimer); });
  return pg;
}
/* one saving round, after any round already running (a running round that stops would not run again) */
const round = (pg) => pg.evaluate(async () => {
  while (qRound) { try { await qRound; } catch (e) {} }
  queue.forEach((o) => delete o.err);
  return syncQueue();
});
const push = (pg, s) => pg.evaluate(async (x) => {
  while (qRound) { try { await qRound; } catch (e) {} }
  queue.push(x); saveQueue(); return syncQueue();
}, s);
const idle = (pg) => until(() => pg.evaluate(() => !qRound), 15000, 'the saving round to finish');
/* tap a product, whichever tab of the menu it is under (tab and product tapped in one go: the menu may be drawn
   again at any moment, e.g. after the sign-in is renewed) */
async function tap(pg, name) {
  const hit = await pg.evaluate((nm) => {
    const find = () => [...document.querySelectorAll('.pbtn')].find((x) => (x.querySelector('.nm') || x).textContent.trim() === nm);
    let b = find();
    for (const t of [...document.querySelectorAll('#rail .tab')]) { if (b) break; t.click(); b = find(); }
    if (b) b.click();
    return !!b;
  }, name);
  if (!hit) throw new Error('no menu button ' + name);
}
const card = (pg, num) => pg.locator('#openBar .ocard', { hasText: '#' + num });
/* the order's own window while it is only on this device */
async function openLocal(pg, num) {
  await card(pg, num).click();
  await pg.waitForSelector('#locModal:not([hidden])', { timeout: 8000 });
}
/* Add items from that window: the products go with the order */
async function addHere(pg, name) {
  await pg.click('#locAdd');
  await pg.waitForSelector('#addBar:not([hidden])');
  await tap(pg, name);
  await pg.click('#addGo');
  await pg.waitForSelector('#locModal:not([hidden])', { timeout: 8000 });   /* back on the order's window */
}
async function chargeHere(pg, method) {
  await pg.click('#locPayRow [data-lpay="' + method + '"]');
  await pg.waitForSelector('#locPaid:not([hidden])');
}
async function closeLocal(pg) { await pg.click('#locClose'); await idle(pg); }
/* another device adds a product to the bill in the system, from its own bill window */
async function addElsewhere(B, num, name, total, n) {
  await B.evaluate(() => pollLive());
  await card(B, num).click();
  await B.waitForSelector('#tabModal:not([hidden])', { timeout: 8000 });
  await B.click('#tabAdd');
  await B.waitForSelector('#addBar:not([hidden])');
  await tap(B, name);
  await B.click('#addGo');
  await until(() => sql(`select total_crc from orders where id = '${id(n)}'`) === String(total), 8000, 'the item added on the other device');
  await B.waitForSelector('#tabModal:not([hidden])', { timeout: 8000 });
  await B.click('#tabClose');
}
const notes = (pg) => pg.evaluate(() => [!document.getElementById('noteModal').hidden, document.getElementById('noteList').textContent]);
const noErrors = (...pgs) => assert.deepStrictEqual([].concat(...pgs.map((p) => p.errors)), [], 'no page errors');

module.exports.tests = [
  {
    name: 'S1/N1: the reply was lost, then an expired sign-in; an item and a card payment taken here are not folded into the order already in the system',
    run: async ({ browser }) => {
      const A = await device(browser);
      A.fail = 'lost';
      await push(A, later(1, 71, [['Latte', 2200, 1]]));
      assert.strictEqual(sql(`select count(*) from orders where id = '${id(1)}'`), '1', 'the order is in the system (its reply was lost)');
      A.fail = 'jwt';
      await round(A);
      assert.strictEqual(await A.evaluate((i) => qFind(i).none, id(1)), false, 'after the expired sign-in it is still "maybe in the system"');
      await openLocal(A, 71);
      await addHere(A, 'Espresso');
      await chargeHere(A, 'card');
      await closeLocal(A);
      A.fail = null;
      await round(A);
      await until(() => dbo(1) === '3500|true|card|ready|false|1xEspresso,1xLatte', 8000, 'the added item and the card payment reached the system: ' + dbo(1));
      assert.strictEqual(await A.evaluate(() => queue.length), 0, 'nothing left on the device');
      assert.ok(!(await A.isVisible('#noteModal')), 'no notice');
      noErrors(A);
    }
  },
  {
    name: 'N2/F7: a kitchen item added here goes in with the order: it reaches the kitchen, its timer from when it was added',
    run: async ({ browser }) => {
      kitchenItem();
      const A = await device(browser);
      A.fail = 'refused';
      await push(A, later(2, 72, [['Latte', 2200, 1]]));
      await openLocal(A, 72);
      await addHere(A, 'T Sandwich');
      await closeLocal(A);
      A.fail = null;
      const add0 = A.calls.add || 0;
      await round(A);
      await until(() => dbo(2) === '6200|false|pending|preparing|true|1xLatte,1xT Sandwich', 8000, 'in with the order, for the kitchen: ' + dbo(2));
      assert.strictEqual(A.calls.add || 0, add0, 'no separate "add items" step');
      const acc = Number(sql(`select extract(epoch from (accepted_at - created_at))::int from orders where id = '${id(2)}'`));
      assert.ok(acc > 600, 'its kitchen timer starts when the item was added, not when the order was rung (' + acc + ' s later)');
      noErrors(A);
    }
  },
  {
    name: 'S4: a payment taken here is on its way; another device adds an item meanwhile: nothing is recorded for another total, the cashier is told',
    run: async ({ browser }) => {
      const A = await device(browser);
      const B = await device(browser);
      A.fail = 'server';
      await push(A, later(3, 73, [['Latte', 2200, 1]]));
      await openLocal(A, 73);
      await chargeHere(A, 'cash_crc');
      await closeLocal(A);
      A.fail = null; A.payFail = 100;
      await round(A);   /* the order goes in; its payment does not (system busy) */
      await until(() => dbo(3) === '2200|false|pending|ready|false|1xLatte', 8000, 'the order in, not paid yet: ' + dbo(3));
      await addElsewhere(B, 73, 'Espresso', 3500, 3);
      A.payFail = 0;
      await round(A);
      const n4 = await notes(A);
      assert.ok(n4[0] && /Payment not recorded · #73/.test(n4[1]) && /changed on another device/.test(n4[1]) && /2.200/.test(n4[1].replace(/\s/g, '.')),
        'says the payment was not recorded because the bill changed: ' + n4[1].slice(0, 220));
      assert.ok(dbo(3).startsWith('3500|false|pending'), 'the system bill is left as it is (₡3 500, not paid): ' + dbo(3));
      assert.strictEqual(await A.evaluate(() => queue.length), 0, 'nothing stuck');
      await A.click('#noteOk');
      noErrors(A, B);
    }
  },
  {
    /* The old suite let the order in and failed its lines (two inserts). The sale and its lines now go in ONE call,
       so a half-saved sale cannot happen through it: a line the database refuses takes the whole sale back with it.
       The other half of the old check stays: an order already in the system without this sale's lines (left by an
       older version of the till) that another device has added to is not taken as fully saved; the cashier is told
       which line is missing. */
    name: 'R2-2: saved whole or not at all; an order already in without its own lines (older till) is not taken as saved',
    run: async ({ browser }) => {
      const A = await device(browser);
      const B = await device(browser);
      /* a line the database refuses: neither the order nor its lines are kept */
      sql(`create function public.zz_refuse_line() returns trigger language plpgsql as $$
             begin if new.order_id = '${id(4)}' then raise exception 'line refused for the test' using errcode = '23514'; end if; return new; end $$;
           create trigger zz_refuse_line before insert on public.order_items for each row execute function public.zz_refuse_line();`);
      await push(A, later(4, 74, [['Latte', 2200, 1]]));
      assert.strictEqual(sql(`select count(*) from orders where id = '${id(4)}'`), '0', 'no order without its lines');
      assert.ok(await A.evaluate((i) => !!qFind(i) && qFind(i).none === true && qFind(i).err.kind === 'refused', id(4)), 'kept on the device, surely not in the system');
      sql(`drop trigger zz_refuse_line on public.order_items; drop function public.zz_refuse_line();`);
      await round(A);
      await until(() => dbo(4) === '2200|false|pending|ready|false|1xLatte', 8000, 'then saved with its line: ' + dbo(4));

      /* an older till left the order in without its lines; another device added an item to it */
      A.fail = 'server';
      const s = later(10, 80, [['Latte', 2200, 1]]);
      await push(A, s);
      sql(`insert into orders (id, created_at, total_crc, payment_method, status, paid, source, station, pickup_number, needs_kitchen)
           values ('${id(10)}', '${s.created_at}', 2200, 'pending', 'ready', false, 'front', 'Caja', 80, false)`);
      await addElsewhere(B, 80, 'Espresso', 3500, 10);
      A.fail = null;
      await round(A);
      const n22 = await notes(A);
      assert.ok(await A.evaluate((i) => !qFind(i), id(10)), 'the order (with its total) is in: it leaves the device');
      assert.ok(n22[0] && /Not on the list of #80/.test(n22[1]) && /1× Latte/.test(n22[1]), 'the cashier is told which line is missing: ' + n22[1].slice(0, 160));
      assert.ok(dbo(10).startsWith('3500|false|pending'), 'the bill keeps its total: ' + dbo(10));
      await A.click('#noteOk');
      noErrors(A, B);
    }
  },
  {
    name: 'M5: rung offline, the tries made offline decide nothing; charged here; back online it goes in paid at once',
    run: async ({ browser }) => {
      const A = await device(browser);
      await A.context().setOffline(true);
      await push(A, later(5, 75, [['Latte', 2200, 1]]));
      assert.strictEqual(await A.evaluate((i) => qFind(i).none, id(5)), true, 'tried offline: still surely not in the system');
      await openLocal(A, 75);
      await chargeHere(A, 'sinpe');
      await closeLocal(A);
      const pay0 = A.calls.pay || 0;
      await A.context().setOffline(false);
      await round(A);
      await until(() => dbo(5).startsWith('2200|true|sinpe'), 8000, 'in the system paid by SINPE: ' + dbo(5));
      assert.strictEqual(A.calls.pay || 0, pay0, 'in one go (no separate payment step)');
      noErrors(A);
    }
  },
  {
    name: 'S7/F6: rung yesterday, paid here today: the payment goes as a step; the system counts it today and closes the old ticket',
    run: async ({ browser }) => {
      const A = await device(browser);
      A.fail = 'refused';
      await push(A, later(6, 76, [['Latte', 2200, 1]], { created_at: new Date(Date.now() - 24 * 3600e3).toISOString() }));
      await openLocal(A, 76);
      await chargeHere(A, 'cash_crc');
      await closeLocal(A);
      A.fail = null;
      const p6 = A.calls.pay || 0;
      await round(A);
      await until(() => dbo(6).startsWith('2200|true|cash_crc|done'), 8000, 'paid and closed: ' + dbo(6));
      const d6 = sql(`select (created_at at time zone 'America/Costa_Rica')::date = (now() at time zone 'America/Costa_Rica')::date from orders where id = '${id(6)}'`);
      assert.strictEqual(d6, 't', 'counted today');
      assert.strictEqual(A.calls.pay || 0, p6 + 1, 'the payment went as its own step');
      noErrors(A);
    }
  },
  {
    name: 'an old queued sale (kept by the earlier version: no "none"): the order first, then its add and payment as steps',
    run: async ({ browser }) => {
      const A = await device(browser);
      A.fail = 'refused';
      const old = later(7, 77, [['Latte', 2200, 1]]); delete old.none;
      old.err = { kind: 'refused', code: '23514', msg: 'x', at: Date.now() }; old.tries = 2;
      await push(A, old);
      await openLocal(A, 77);
      await addHere(A, 'Espresso');
      await chargeHere(A, 'card');
      await closeLocal(A);
      A.fail = null;
      const a7 = A.calls.add || 0, p7 = A.calls.pay || 0;
      await round(A);
      await until(() => dbo(7) === '3500|true|card|ready|false|1xEspresso,1xLatte', 8000, 'in, then its add and payment: ' + dbo(7));
      assert.strictEqual(A.calls.add || 0, a7 + 1, 'the add as a step');
      assert.strictEqual(A.calls.pay || 0, p7 + 1, 'the payment as a step');
      assert.strictEqual(await A.evaluate(() => queue.length), 0, 'nothing left');
      assert.ok(!(await A.isVisible('#noteModal')), 'no notice');
      noErrors(A);
    }
  },
  {
    name: 'F4: order in (lost reply); an item since taken off the menu is refused for good; the bill is then charged for what it is',
    run: async ({ browser }) => {
      sql(`insert into menu_items (category_id, name, price_crc, sort, available) select id, 'zz Gone', 1000, 98, true from menu_categories where name = 'Coffee';`);
      const A = await device(browser);
      await until(() => A.evaluate(() => menuCats.some((c) => c.items.some((i) => i.name === 'zz Gone'))), 8000, 'the item on the menu');
      A.fail = 'lost';
      await push(A, later(8, 78, [['Latte', 2200, 1]]));
      A.fail = 'server';
      await openLocal(A, 78);
      await addHere(A, 'zz Gone');
      await closeLocal(A);
      sql(`delete from menu_items where name = 'zz Gone';`);
      A.fail = null;
      await round(A);
      const n8 = await notes(A);
      assert.ok(n8[0] && /Not added to #78/.test(n8[1]) && /Charge these/.test(n8[1]), 'the item is refused for good, the cashier is told: ' + n8[1].slice(0, 160));
      await A.click('#noteOk');
      if (await A.evaluate((i) => !!qFind(i), id(8))) {
        await openLocal(A, 78);
        await chargeHere(A, 'card');
        await closeLocal(A);
        await round(A);
      } else {
        await A.evaluate(() => pollLive());
        await card(A, 78).click();
        await A.waitForSelector('#tabModal:not([hidden])', { timeout: 8000 });
        await A.click('#tabPayRow [data-tpay="card"]');
        await A.waitForSelector('#tabPaidAll:not([hidden])', { timeout: 8000 });
        await A.click('#tabClose');
      }
      await until(() => dbo(8) === '2200|true|card|ready|false|1xLatte', 8000, 'paid by card for the bill as it is: ' + dbo(8));
      assert.ok(!(await A.isVisible('#noteModal')), 'no false notice');
      noErrors(A);
    }
  },
  {
    name: 'F9: an item added and the bill charged here; another device cancels the bill: the notices agree (give it back)',
    run: async ({ browser }) => {
      const A = await device(browser);
      const B = await device(browser);
      A.fail = 'server';
      await push(A, later(9, 79, [['Latte', 2200, 1]]));
      await openLocal(A, 79);
      await addHere(A, 'Espresso');
      await chargeHere(A, 'cash_crc');
      await closeLocal(A);
      A.fail = null;
      const down = (r) => r.fulfill({ status: 503, contentType: 'text/plain', headers: CORS, body: 'down' });
      await A.route(/rest\/v1\/rpc\/tab_add_items/, down);
      await round(A);
      await until(() => dbo(9) === '2200|false|pending|ready|false|1xLatte', 8000, 'the order in, its add not yet: ' + dbo(9));
      const c = await B.evaluate((i) => db.rpc('cancel_unpaid_order', { p_order_id: i }).then((r) => r.data), id(9));
      assert.ok(c && c.ok, 'cancelled on the other device: ' + JSON.stringify(c));
      await A.unroute(/rest\/v1\/rpc\/tab_add_items/, down);
      await round(A);
      const n9 = (await notes(A))[1];
      assert.ok(/Not added to #79/.test(n9) && !/Already paid here/.test(n9) && /Payment not recorded · #79/.test(n9) && /give it back/.test(n9), 'the notices agree: ' + n9.slice(0, 260));
      await A.click('#noteOk');
      noErrors(A, B);
    }
  },
  {
    name: 'N6: a notice about an order with no number, in Spanish',
    run: async ({ browser }) => {
      const A = await device(browser);
      await A.click('.hg-lang button[lang="es"]');
      await A.evaluate(() => qNotice(['Not added to No number', 'That bill was already paid.']));
      await until(async () => /No se añadió a Sin número/.test(await A.textContent('#noteList')) && /Revise esto/.test(await A.textContent('#noteTitle')), 8000, 'the notice in Spanish');
      await A.click('#noteOk');
      noErrors(A);
    }
  }
];
