/* Open bills at the till (pos.html, supabase/pos-tabs.sql): a pay-later order, items added, paid by item, in equal
   parts and by amount, an item taken off with a manager's PIN, discounts on a bill; and the sales kept on the device
   while the system does not take them (queue). Ported from the e2e3 suites tabs-e2e.js and tabs-e2e6.js. */
'use strict';
const assert = require('assert');
const { page, goto, until, sql, openRegister, cashExact, PINS } = require('../lib');
const gw = require('../gateway');

const API = 'http://127.0.0.1:' + (Number(process.env.E2E_SITE_PORT || 8090) + 1000);
const id = (n) => 'd0000000-0000-4000-8000-0000000010' + String(n).padStart(2, '0');
const line = (n) => 'd0000000-0000-4000-8000-0000000020' + String(n).padStart(2, '0');
const ITEM = { sandwich: 'b0000000-0000-4000-8000-0000000000a1', latte: 'b0000000-0000-4000-8000-0000000000a2',
               brownie: 'b0000000-0000-4000-8000-0000000000a3' };
const money = (s) => String(s || '').replace(/\s/g, '');

/* test products with known ids and prices: a kitchen sandwich, a latte and a brownie from the bar */
function testMenu() {
  sql(`insert into menu_categories (id, name, sort, kitchen) values
         ('b0000000-0000-4000-8000-0000000000c1', 'Test Kitchen', 20, true),
         ('b0000000-0000-4000-8000-0000000000c2', 'Test Bar', 21, false);
       insert into menu_items (id, category_id, name, price_crc, sort, available) values
         ('${ITEM.sandwich}', 'b0000000-0000-4000-8000-0000000000c1', 'T Sandwich', 4000, 1, true),
         ('${ITEM.latte}', 'b0000000-0000-4000-8000-0000000000c2', 'T Latte', 2000, 1, true),
         ('${ITEM.brownie}', 'b0000000-0000-4000-8000-0000000000c2', 'T Brownie', 1500, 2, true);`);
}
/* a bill not paid yet, as another device left it */
function bill(n, name, status, lines, extra) {
  const total = lines.reduce((s, l) => s + l[1] * l[2], 0);
  sql(`insert into orders (id, total_crc, payment_method, status, paid, source, station, guest_name, pickup_number, done_at)
       values ('${id(n)}', ${total}, 'pending', '${status}', false, 'front', '${(extra && extra.station) || 'Caja'}',
               ${name ? `'${name}'` : 'null'}, ${(extra && extra.number) || 'null'}, ${status === 'done' ? 'now()' : 'null'})`);
  sql(`insert into order_items (id, order_id, item_name, price_crc, qty) values ` +
      lines.map((l, i) => `('${l[3] || line(n * 4 + i)}', '${id(n)}', '${l[0]}', ${l[1]}, ${l[2]})`).join(', '));
}
/* another device of the café, through the same API the pages use */
async function rpc(name, args) {
  const r = await fetch(API + '/rest/v1/rpc/' + name, { method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + gw.sessionFor('cafe@test.local').access_token },
    body: JSON.stringify(args) });
  const body = await r.json();
  if (!r.ok) throw new Error(name + ' ' + r.status + ' ' + JSON.stringify(body));
  return body;
}
function gate() { let open; const wait = new Promise((r) => { open = r; }); return { wait, open }; }
const CORS = { 'access-control-allow-origin': '*' };

/* the till with the register open; its own 20 s retry is off (the tests drive every round), the live poll too */
async function till(browser, opts) {
  opts = Object.assign({ login: 'cafe', lang: 'es' }, opts || {});
  openRegister();
  const pg = await page(browser, opts);
  track(pg);
  await pg.addInitScript(() => {
    const si = window.setInterval;
    window.setInterval = function (fn, ms) { return ms === 20000 ? 0 : si.apply(this, arguments); };
  });
  if (opts.before) await opts.before(pg);
  await goto(pg, '/pos');
  await pg.waitForSelector('#appView:not([hidden])', { timeout: 15000 });
  await pg.waitForFunction(() => document.querySelectorAll('.pbtn').length > 0, null, { timeout: 15000 });
  if (await pg.isVisible('#dayModal')) await pg.click('#dayClose');
  if (await pg.isVisible('#stationModal')) await pg.click('#stationForm button[type=submit]');
  await pg.evaluate(() => {
    clearInterval(liveTimer);
    window.__toasts = [];
    const t = window.toast; window.toast = function (m) { window.__toasts.push(m); return t.apply(this, arguments); };
  });
  return pg;
}
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
const text = async (pg, sel) => (await pg.textContent(sel)) || '';
const untilText = (pg, sel, re, ms) => until(async () => re.test(await text(pg, sel)), ms || 8000, sel + ' to read ' + re);
const printed = (pg) => pg.evaluate(() => window.__printed || 0);
async function printOf(pg, click) {
  const n0 = await printed(pg);
  await pg.click(click);
  await until(async () => (await printed(pg)) > n0, 8000, 'printing');
  return pg.evaluate(() => window.__printedHTML || '');
}
async function managers(pg, sel) {
  await until(() => pg.evaluate((s) => [...document.querySelectorAll(s + ' option')].some((o) => o.textContent === 'Ana'), sel), 8000, 'managers listed');
  await pg.selectOption(sel, { label: 'Ana' });
}
const roundDone = (pg) => until(() => pg.evaluate(() => !qRound), 15000, 'the saving round to finish');
const sale = (k, extra) => Object.assign({ local_id: 'o' + k, created_at: new Date().toISOString(), total_crc: 2000, payment_method: 'cash_crc',
  status: 'done', paid: true, station: 'Caja', items: [{ item_name: 'T Latte', price_crc: 2000, qty: 1 }] }, extra || {});
const push = (pg, s) => pg.evaluate((x) => { queue.push(x); saveQueue(); return syncQueue(); }, s);
/* requests to the API still on their way (for "nothing else happened" checks) */
function track(pg) {
  pg.inflight = 0;
  const api = (r) => r.url().startsWith(API + '/rest/v1/');
  pg.on('request', (r) => { if (api(r)) pg.inflight++; });
  pg.on('requestfinished', (r) => { if (api(r)) pg.inflight--; });
  pg.on('requestfailed', (r) => { if (api(r)) pg.inflight--; });
}
async function quiet(pg) { let calm = 0; await until(() => { calm = pg.inflight === 0 ? calm + 1 : 0; return calm >= 3; }, 10000, 'no request in flight'); }

module.exports.tests = [
  {
    name: 'a pay-later bill: an item added, one paid by item, the rest in two equal parts; Orders, a manager takes an item off, rename, print',
    run: async ({ browser }) => {
      testMenu();
      const pg = await till(browser);

      /* 1. a pay-later order: latte + sandwich, number 5, name Ana */
      await tap(pg, 'T Latte'); await tap(pg, 'T Sandwich');
      await pg.click('#sendBtn');
      await pg.waitForSelector('#numModal:not([hidden])');
      assert.ok(await pg.isVisible('#numWhoRow'), 'pay later asks for a name or table');
      await untilText(pg, '#numWhoRow label', /Nombre o mesa/);
      await pg.fill('#numWho', 'Ana');
      await pg.locator('#numGrid button', { hasText: /^5$/ }).click();
      const row = await until(() => sql(`select pickup_number || '|' || guest_name || '|' || paid || '|' || status || '|' || total_crc from orders where pickup_number = 5`), 10000, 'order saved');
      assert.strictEqual(row, '5|Ana|false|preparing|6000', 'order saved unpaid with name');
      await until(() => pg.evaluate(() => queue.length === 0), 8000, 'queue empty');

      /* 2. the live bar offers to open the bill */
      await pg.evaluate(() => pollLive());
      await pg.waitForSelector('.lv.due', { timeout: 8000 });
      await untilText(pg, '.lv.due', /Abrir cuenta/);
      assert.match(await text(pg, '.lv.due'), /Sin pagar/, 'chip shows Sin pagar');

      /* 3. open the bill */
      await pg.locator('.lv.due button', { hasText: 'Abrir cuenta' }).click();
      await pg.waitForSelector('#tabModal:not([hidden])');
      assert.strictEqual(await text(pg, '#tabTitle'), '#5', 'bill title #5');
      assert.match(await text(pg, '#tabMeta'), /Ana/, 'bill shows the name');
      assert.strictEqual(await pg.locator('#tabLines .tline').count(), 2, 'two lines on the bill');
      assert.strictEqual(money(await text(pg, '#tabDue')), '₡6000', 'due whole bill ₡6 000');

      /* 4. add a brownie later */
      await pg.click('#tabAdd');
      await pg.waitForSelector('#addBar:not([hidden])');
      assert.ok(!(await pg.isVisible('#payRow')), 'order panel switched to adding mode');
      await untilText(pg, '#addBar', /Añadiendo a la cuenta/);
      await tap(pg, 'T Brownie');
      assert.match(await text(pg, '#addGo'), /₡1/, 'add button shows the amount');
      await pg.click('#addGo');
      await pg.waitForSelector('#tabModal:not([hidden])', { timeout: 8000 });
      await until(async () => (await pg.locator('#tabLines .tline').count()) === 3, 8000, 'three lines after adding');
      await until(async () => money(await text(pg, '#tabDue')) === '₡7500', 8000, 'due ₡7 500 after the brownie');
      assert.ok(await pg.isVisible('#payRow') && !(await pg.isVisible('#addBar')), 'order panel back to normal');
      assert.strictEqual(sql(`select total_crc from orders where pickup_number = 5`), '7500', 'database total 7500');

      /* 5. Ana pays her latte by card (by item) */
      await pg.click('#tabSplit [data-mode="items"]');
      const plus = pg.locator('#tabLines .tline', { hasText: 'T Latte' }).locator('.pick button', { hasText: '+' });
      assert.strictEqual(await plus.count(), 1, 'item stepper shown');
      assert.ok(await pg.isDisabled('#tabPayRow [data-tpay="card"]'), 'pay disabled before picking');
      await plus.click();
      assert.strictEqual(money(await text(pg, '#tabDue')), '₡2000', 'due ₡2 000 for the latte');
      await pg.click('#tabPayRow [data-tpay="card"]');
      await until(async () => (await pg.locator('#tabTotals .trow.part').count()) === 1, 8000, 'one part paid');
      await untilText(pg, '#tabTotals', /Por pagar/);
      assert.strictEqual(money(await text(pg, '#tabDue')), '₡0', 'nothing picked for the next person');
      await untilText(pg, '#splitBody', /Toque \+/);
      assert.ok(!(await pg.isDisabled('#tabReceipt')), 'receipt of the part can be printed');
      const rec = await printOf(pg, '#tabReceipt');
      assert.ok(/PAGO PARCIAL/.test(rec) && /T Latte/.test(rec) && /2 000/.test(rec), 'part receipt has the latte and ₡2 000: ' + rec.slice(0, 300));

      /* 6. the rest in 2 equal parts: cash, then SINPE closes the bill */
      await pg.click('#tabSplit [data-mode="equal"]');
      await pg.locator('#splitBody .chips button', { hasText: /^2$/ }).click();
      assert.strictEqual(money(await text(pg, '#tabDue')), '₡2750', 'half of ₡5 500 = ₡2 750');
      await pg.click('#tabPayRow [data-tpay="cash_crc"]');
      await cashExact(pg);
      await until(async () => (await pg.locator('#tabTotals .trow.part').count()) === 2, 8000, 'two parts paid');
      await untilText(pg, '#tabDueLbl', /cierra la cuenta/);
      assert.strictEqual(money(await text(pg, '#tabDue')), '₡2750', 'second half ₡2 750');
      await pg.click('#tabPayRow [data-tpay="sinpe"]');
      await pg.waitForSelector('#tabPaidAll:not([hidden])', { timeout: 8000 });
      assert.ok(await pg.isHidden('#tabPayArea'), 'pay area hidden once paid');
      const rec2 = await printOf(pg, '#tabReceipt');
      assert.ok(/CUENTA · BILL/.test(rec2) && /Pagado antes/.test(rec2) && /2 750/.test(rec2), 'closing receipt: remaining items, paid before, ₡2 750: ' + rec2.slice(0, 400));
      const byMethod = sql(`select string_agg(payment_method || '=' || total_crc, ',' order by payment_method) from orders where pickup_number = 5 and voided_at is null`);
      assert.strictEqual(byMethod, 'card=2000,cash_crc=2750,sinpe=2750', 'money by method');
      assert.strictEqual(sql(`select sum(total_crc) from orders where pickup_number = 5`), '7500', 'all payments add up to the bill');
      await pg.click('#tabClose');

      /* 7. Orders: parts read as parts of the bill, an unpaid bill can be opened */
      sql(`insert into orders (id, total_crc, payment_method, status, paid, source, station, guest_name, done_at)
           values ('d0000000-0000-4000-8000-0000000000aa', 3500, 'pending', 'done', false, 'front', 'iPad', 'Mesa 2', now())`);
      sql(`insert into order_items (id, order_id, item_name, price_crc, qty, added_at) values
           ('e0000000-0000-4000-8000-0000000000aa', 'd0000000-0000-4000-8000-0000000000aa', 'T Brownie', 1500, 1, now() - interval '30 minutes'),
           ('e0000000-0000-4000-8000-0000000000ab', 'd0000000-0000-4000-8000-0000000000aa', 'T Latte', 2000, 1, now() - interval '30 minutes')`);
      await pg.click('#ordersBtn');
      await until(async () => (await pg.locator('#ordersBody .orow').count()) >= 4, 8000, 'orders listed');
      await untilText(pg, '#ordersBody', /Parte de la cuenta #5/);
      assert.strictEqual(await pg.locator('#ordersBody .orow button.open').count(), 1, 'the unpaid bill has an Abrir cuenta button');
      await pg.click('#ordersBody .orow button.open');
      await pg.waitForSelector('#tabModal:not([hidden])');
      await untilText(pg, '#tabTitle', /^Mesa 2$/);

      /* 8. delivered bill, item older than 10 minutes: a manager approves taking it off */
      await pg.locator('#tabLines .tline', { hasText: 'T Brownie' }).locator('button.rm').click();
      await pg.waitForSelector('#tabRmBox:not([hidden])', { timeout: 8000 });
      await untilText(pg, '#tabRmWhich', /Quitar 1× T Brownie/);
      await pg.fill('#tabRmWhy', 'se equivocó');
      await managers(pg, '#tabRmMgr');
      await pg.fill('#tabRmPin', '0000');
      await pg.click('#tabRmGo');
      await untilText(pg, '#tabRmErr', /PIN/);
      await pg.fill('#tabRmPin', PINS.ana);
      await pg.click('#tabRmGo');
      await pg.waitForSelector('#tabRmBox', { state: 'hidden', timeout: 8000 });
      await until(async () => (await pg.locator('#tabLines .tline').count()) === 1 && money(await text(pg, '#tabDue')) === '₡2000', 8000, 'brownie off, ₡2 000 left');
      assert.strictEqual(sql(`select manager_name from audit_log where action = 'tab_item_removed' order by at desc limit 1`), 'Ana', 'logged as approved by Ana');
      assert.ok(await pg.isHidden('#tabCancel'), 'no Cancel on a delivered bill');
      await pg.click('#tabClose');

      /* 9. delivered and not paid: under the menu in Open orders, no longer at the top; renamed */
      await pg.evaluate(() => pollLive());
      assert.strictEqual(await pg.locator('#liveBar .lv', { hasText: 'Mesa 2' }).count(), 0, 'delivered unpaid bill left the top bar');
      pg.onDialog = async (d) => { if (d.type() === 'prompt') await d.accept('Mesa 9'); else await d.accept(); };
      await pg.locator('#openBar .ocard', { hasText: 'Mesa 2' }).click();
      await pg.waitForSelector('#tabModal:not([hidden])');
      await pg.click('#tabRename');
      await untilText(pg, '#tabTitle', /^Mesa 9$/);
      pg.onDialog = null;

      /* 10. the bill on paper (not a receipt) */
      const paper = await printOf(pg, '#tabBill');
      assert.ok(/CUENTA · BILL Mesa 9/.test(paper) && /POR PAGAR/.test(paper) && /No es comprobante/.test(paper), 'the bill on paper says what is due and that it is not a receipt');
      await pg.click('#tabClose');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'a bill paid by amount: a part, an amount above the bill refused, the rest closes it',
    run: async ({ browser }) => {
      testMenu();
      bill(20, 'Mesa Monto', 'done', [['T Latte', 2000, 1], ['T Brownie', 1500, 2]]);
      const pg = await till(browser);
      await pg.evaluate((x) => openTab(x), id(20));
      await pg.waitForSelector('#tabModal:not([hidden])');
      await pg.click('#tabSplit [data-mode="amount"]');
      await pg.fill('#tabAmt', '1200');
      assert.strictEqual(money(await text(pg, '#tabDue')), '₡1200', 'due what was typed');
      await pg.click('#tabPayRow [data-tpay="card"]');
      await until(async () => (await pg.locator('#tabTotals .trow.part').count()) === 1, 8000, 'one part paid');
      assert.strictEqual(sql(`select string_agg(payment_method || '=' || total_crc, ',') from orders where part_of = '${id(20)}'`), 'card=1200', 'the part is a card payment of ₡1 200');
      assert.strictEqual(sql(`select total_crc || ' ' || paid from orders where id = '${id(20)}'`), '3800 false', 'the bill owes ₡3 800');
      await pg.fill('#tabAmt', '9000');
      await until(async () => (await text(pg, '#tabErr')).length > 0, 8000, 'too much refused');
      assert.ok(await pg.isDisabled('#tabPayRow [data-tpay="cash_crc"]'), 'nothing to charge for more than is owed');
      await pg.click('#tabSplit [data-mode="all"]');
      assert.strictEqual(money(await text(pg, '#tabDue')), '₡3800', 'the rest');
      await pg.click('#tabPayRow [data-tpay="cash_crc"]');
      await cashExact(pg);
      await pg.waitForSelector('#tabPaidAll:not([hidden])', { timeout: 8000 });
      assert.strictEqual(sql(`select paid || ' ' || payment_method || ' ' || total_crc from orders where id = '${id(20)}'`), 'true cash_crc 3800', 'closed in cash');
      await until(() => sql(`select crc_in || ' ' || change_crc from cash_tenders where order_id = '${id(20)}'`) === '3800 0', 8000, 'the cash received is kept with the payment');
      assert.strictEqual(sql(`select sum(total_crc) from orders where id = '${id(20)}' or part_of = '${id(20)}'`), '5000', 'all payments add up to the bill');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'Q-a: five sales kept by an older version (no ids) are saved once each, though the queue is read twice at start',
    run: async ({ browser }) => {
      const five = [1, 2, 3, 4, 5].map((k) => sale(k, { total_crc: 1000 + k }));
      const pg = await till(browser, { viewport: { width: 820, height: 1180 }, before: (p) => p.addInitScript((list) => {
        if (!sessionStorage.getItem('seeded')) { sessionStorage.setItem('seeded', '1'); localStorage.setItem('hg-pos-queue', JSON.stringify(list)); }
      }, five) });
      await until(() => pg.evaluate(() => queue.length === 0 && !qRound), 15000, 'the old sales uploaded');
      await pg.evaluate(() => syncQueue());   /* one more round finds nothing to send */
      assert.strictEqual(sql(`select count(*) || ' ' || count(distinct total_crc) from orders where total_crc between 1001 and 1005`), '5 5', 'five old sales saved once each');
      assert.strictEqual(sql(`select count(*) from order_items i join orders o on o.id = i.order_id where o.total_crc between 1001 and 1005`), '5', 'one line each');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'Q-b: two tabs of the till on one device, uploads failing: neither tab wipes the other\'s sale',
    run: async ({ browser }) => {
      const pgA = await till(browser, { viewport: { width: 820, height: 1180 } });
      const pgB = await till(browser, { context: pgA.context() });
      let fail = true;
      for (const p of [pgA, pgB]) {
        await p.route(/rest\/v1\/rpc\/pos_record_sale/, (r) => (r.request().method() === 'POST' && fail)
          ? r.fulfill({ status: 401, contentType: 'application/json', headers: CORS, body: JSON.stringify({ code: 'PGRST301', message: 'JWT expired' }) })
          : r.fallback());
      }
      const sA = sale('A', { id: id(1), total_crc: 2222, items: [{ id: line(1), item_name: 'T Latte', price_crc: 2222, qty: 1 }] });
      const sB = sale('B', { id: id(2), total_crc: 1777, items: [{ id: line(2), item_name: 'T Cafe', price_crc: 1777, qty: 1 }] });
      await pgA.evaluate((s) => { queue.push(s); saveQueue(); syncQueue(); }, sA);
      await until(() => pgA.evaluate((i) => !qRound && !!(qFind(i) || {}).err, id(1)), 10000, 'A tried and failed');
      await pgB.evaluate((s) => { queue.push(s); saveQueue(); syncQueue(); }, sB);
      /* B's round meets A's sale first (it is in the shared storage) and stops at the same refusal */
      await until(() => pgB.evaluate((i) => !qRound && !!qFind(i) && queue.some((o) => o.err), id(2)), 10000, 'B tried and failed');
      await pgA.evaluate(() => loadQueue()); await pgB.evaluate(() => loadQueue());   /* an auth event in both tabs */
      assert.strictEqual(await pgA.evaluate(() => queue.map((o) => o.total_crc).sort().join(',')), '1777,2222', 'tab A keeps both sales after reading the storage again');
      fail = false;
      await roundDone(pgA); await roundDone(pgB);
      await pgA.evaluate(() => { queue.forEach((o) => delete o.err); return syncQueue(); });
      await pgB.evaluate(() => { queue.forEach((o) => delete o.err); return syncQueue(); });
      await until(() => sql(`select count(*) from orders where total_crc in (2222, 1777)`) === '2', 10000, 'both sales saved');
      await until(async () => (await pgA.evaluate(() => queue.length)) === 0 && (await pgB.evaluate(() => queue.length)) === 0, 10000, 'both queues empty');
      assert.strictEqual(sql(`select string_agg(total_crc::text, ',' order by total_crc) from orders where total_crc in (2222, 1777)`), '1777,2222', 'both sales in the system once');
      assert.deepStrictEqual(pgA.errors.concat(pgB.errors), []);
    }
  },
  {
    name: 'Q-c/Q-d: the system not answering (503) waits and says so; "Try again now" during a round keeps the reasons until a new round runs',
    run: async ({ browser }) => {
      const pg = await till(browser, { viewport: { width: 820, height: 1180 } });
      let mode = 'html503', calls = 0, hold = null;
      await pg.route(/rest\/v1\/rpc\/pos_record_sale/, async (r) => {
        if (r.request().method() !== 'POST' || !mode) return r.fallback();
        calls++;
        if (mode === 'html503') return r.fulfill({ status: 503, contentType: 'text/html', headers: CORS, body: '<html><head><title>503 Service Temporarily Unavailable</title></head><body>down</body></html>' });
        await hold.wait;
        return r.fulfill({ status: 503, contentType: 'application/json', headers: CORS, body: JSON.stringify({ code: 'PGRST002', message: 'Could not query the database' }) });
      });

      /* Q-c. kind "server", no HTML in the reason, the window says the system is not answering */
      await push(pg, sale('C', { id: id(3), total_crc: 3333, items: [{ id: line(3), item_name: 'T Latte', price_crc: 3333, qty: 1 }] }));
      const kc = await pg.evaluate(() => queue.map((o) => o.err && o.err.kind + '|' + o.err.msg).join(';'));
      assert.ok(/^server\|/.test(kc) && !/</.test(kc), 'kind server, no HTML in the reason: ' + kc);
      await pg.click('#netChip');
      await pg.waitForSelector('#queueModal:not([hidden])');
      await untilText(pg, '#queueModal', /El sistema no responde en este momento/);
      assert.ok(!/rechazó/.test(await text(pg, '#queueModal')), 'not "refused"');
      await pg.click('#queueClose');
      /* the register close says it about one sale, in the singular, in Spanish */
      const qm = await pg.evaluate(() => {
        const e = document.createElement('p'); e.id = 'qmTest'; e.textContent = queueMsg(); document.body.appendChild(e);
        return new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(() => r(document.getElementById('qmTest').textContent))));
      });
      assert.match(qm, /^Una venta no se ha guardado todavía/, 'one sale, singular, in Spanish');

      /* Q-d. a slow round is running; the window opens and "Try again now" is tapped meanwhile */
      await roundDone(pg);
      mode = 'slow'; hold = gate();
      const c0 = calls;
      await pg.evaluate(() => { syncQueue(); });
      await until(() => calls === c0 + 1, 8000, 'the first round reached the system');
      await pg.click('#netChip');
      await pg.waitForSelector('#queueModal:not([hidden])');
      await pg.click('#queueRetry');
      assert.ok(await pg.evaluate(() => !!qRound && queue.every((o) => o.err)), 'while the first round runs, the reasons are still there');
      hold.open();
      await until(async () => (await pg.evaluate(() => !qRound && !document.getElementById('queueRetry').disabled)) && calls === c0 + 2, 10000, 'a real new round ran');
      assert.ok(await pg.evaluate(() => queue.length === 1 && !!queue[0].err && queue[0].err.kind === 'server'), 'after the new round, the reason is back (server)');
      mode = null;
      await pg.click('#queueRetry');
      await until(() => pg.evaluate(() => queue.length === 0), 10000, 'saved');
      assert.strictEqual(sql(`select count(*) from orders where total_crc = 3333`), '1', 'saved once when the system answers');
      await untilText(pg, '#queueModal', /Todo lo que se tomó en este dispositivo está guardado/);
      await pg.click('#queueClose');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'Q-e: a sale rung while another is uploading goes right after it, not on the next 20 s retry',
    run: async ({ browser }) => {
      const pg = await till(browser, { viewport: { width: 820, height: 1180 } });
      let n = 0; const hold = gate();
      await pg.route(/rest\/v1\/rpc\/pos_record_sale/, async (r) => {
        if (r.request().method() === 'POST' && ++n === 1) await hold.wait;
        return r.fallback();
      });
      await pg.evaluate((s) => { queue.push(s); saveQueue(); syncQueue(); }, sale('E1', { id: id(4), total_crc: 4441, items: [{ id: line(4), item_name: 'T Latte', price_crc: 4441, qty: 1 }] }));
      await until(() => n === 1, 8000, 'the first sale on its way');
      await pg.evaluate((s) => { queue.push(s); saveQueue(); syncQueue(); }, sale('E2', { id: id(5), total_crc: 4442, items: [{ id: line(5), item_name: 'T Latte', price_crc: 4442, qty: 1 }] }));
      assert.strictEqual(await pg.evaluate(() => qAgain), true, 'the second sale waits for the running round');
      const t0 = Date.now();
      hold.open();
      /* the till's own 20 s retry is switched off in these tests: only "right after" can save the second sale */
      await until(() => pg.evaluate(() => queue.length === 0), 8000, 'both saved');
      assert.strictEqual(sql(`select count(*) from orders where total_crc in (4441, 4442)`), '2', 'both saved in ' + (Date.now() - t0) + ' ms');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'Q-f: this device\'s storage full: the sale is not lost or doubled, the chip says it',
    run: async ({ browser }) => {
      const pg = await till(browser, { viewport: { width: 820, height: 1180 } });
      await pg.evaluate(() => {
        const o = Storage.prototype.setItem; window.__realSet = o;
        Storage.prototype.setItem = function (k, v) { if (k === 'hg-pos-queue') throw new DOMException('full', 'QuotaExceededError'); return o.call(this, k, v); };
      });
      const refuse = (r) => r.request().method() === 'POST'
        ? r.fulfill({ status: 401, contentType: 'application/json', headers: CORS, body: JSON.stringify({ code: 'PGRST301', message: 'JWT expired' }) }) : r.fallback();
      await pg.route(/rest\/v1\/rpc\/pos_record_sale/, refuse);
      await pg.evaluate(() => { document.querySelector('.pbtn').click(); });
      await pg.click('[data-pay="cash_crc"]');
      await cashExact(pg);
      await until(async () => (await pg.isVisible('#numModal')) || (await pg.evaluate(() => queue.length > 0)), 8000, 'the number window or the sale');
      if (await pg.isVisible('#numModal')) await pg.click('#numNone');
      await untilText(pg, '#netChip', /no guardado en este dispositivo/);
      await roundDone(pg);
      assert.deepStrictEqual(pg.errors, [], 'no page error');
      assert.ok(await pg.evaluate(() => ticket.length === 0 && queue.length === 1), 'the ticket cleared, the sale kept in the page');
      await pg.evaluate(() => loadQueue());
      assert.strictEqual(await pg.evaluate(() => queue.length), 1, 'an auth event does not drop it');
      await pg.evaluate(() => { Storage.prototype.setItem = window.__realSet; });
      await pg.unroute(/rest\/v1\/rpc\/pos_record_sale/, refuse);
      await roundDone(pg);
      await pg.evaluate(() => { queue.forEach((o) => delete o.err); return syncQueue(); });
      await until(() => pg.evaluate(() => queue.length === 0), 10000, 'saved once storage works');
      await untilText(pg, '#netChip', /en línea/);
      assert.strictEqual(sql(`select count(*) from orders`), '1', 'one sale, once');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'D-a/D-b: a slow approval cancelled is not used on another bill; the discount window follows the bill under it',
    run: async ({ browser }) => {
      testMenu();
      bill(11, 'Mesa Lenta A', 'done', [['T Latte', 2000, 4]]);
      bill(12, 'Mesa Lenta B', 'done', [['T Latte', 2000, 3]]);
      const pg = await till(browser, { viewport: { width: 820, height: 1180 } });
      let approvals = 0; const hold = gate();
      await pg.route(/rest\/v1\/rpc\/approve_discount/, async (r) => { approvals++; await hold.wait; return r.fallback(); });

      /* D-a. slow approval, Cancel, another bill: the approval is not used on the other bill */
      await pg.evaluate((x) => openTab(x), id(11));
      await pg.waitForSelector('#tabModal:not([hidden])');
      await pg.click('#tabDisc');
      await pg.waitForSelector('#discModal:not([hidden])');
      await pg.click('[data-pct="50"]');
      await pg.selectOption('#discWhy', 'Team member');
      await managers(pg, '#discMgr');
      await pg.fill('#discPin', PINS.ana);
      await pg.click('#discGo');
      await until(() => approvals === 1, 8000, 'the approval on its way');
      await pg.click('#discCancel');
      await pg.click('#tabClose');
      await pg.evaluate((x) => openTab(x), id(12));
      await pg.waitForSelector('#tabModal:not([hidden])');
      await pg.click('#tabDisc');
      await pg.waitForSelector('#discModal:not([hidden])');
      const answered = pg.waitForResponse((r) => /rpc\/approve_discount/.test(r.url()));
      hold.open();
      await answered;
      await until(() => pg.evaluate(() => !document.getElementById('discGo').disabled), 8000, 'the late answer handled');
      await quiet(pg);
      const both = sql(`select string_agg(total_crc || '/' || discount_crc, ' ' order by guest_name) from orders where id in ('${id(11)}', '${id(12)}')`);
      assert.strictEqual(both, '8000/0 6000/0', 'neither bill got the cancelled approval');
      assert.ok(await pg.isVisible('#discModal'), 'bill B\'s discount window stays open, untouched');
      assert.match(await text(pg, '#discTitle'), /Mesa Lenta B/, 'the window is for bill B');

      /* D-b. the discount window follows the bill under it when another device adds an item */
      await pg.click('[data-pct="10"]');
      await untilText(pg, '#discPrev', /₡600/);
      const add = await rpc('tab_add_items', { p_order_id: id(12), p_items: [{ menu_item_id: ITEM.latte, qty: 1 }] });
      assert.ok(add.ok && add.total === 8000, 'a latte added on another device: ' + JSON.stringify(add));
      await pg.evaluate(() => pollLive());
      await untilText(pg, '#discPrev', /₡800/);
      await untilText(pg, '#discLead', /₡8.?000/);
      await pg.click('#discCancel');
      await pg.click('#tabClose');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'D-c: a discount after an item was paid by item covers what is left, as the screen said; taking an item off keeps the 10 %',
    run: async ({ browser }) => {
      testMenu();
      bill(13, 'Mesa Parcial', 'ready', [['T Sandwich', 4000, 1, line(61)], ['T Latte', 2000, 1, line(62)], ['T Brownie', 1500, 2, line(63)]]);
      const paid = await rpc('tab_pay', { p_order_id: id(13), p_method: 'card', p_lines: [{ item_id: line(61), qty: 1 }], p_amount: null, p_station: 'Caja', p_expect: 9000 });
      assert.ok(paid.ok && paid.amount === 4000, 'the sandwich paid by item on another device: ' + JSON.stringify(paid));
      const pg = await till(browser, { viewport: { width: 820, height: 1180 } });
      await pg.evaluate((x) => openTab(x), id(13));
      await pg.waitForSelector('#tabModal:not([hidden])');
      await pg.click('#tabDisc');
      await pg.waitForSelector('#discModal:not([hidden])');
      await pg.click('[data-pct="10"]');
      await untilText(pg, '#discPrev', /Descuento ₡500 · Por pagar ₡4.?500/);
      await pg.selectOption('#discWhy', 'Promotion');
      await managers(pg, '#discMgr');
      await pg.fill('#discPin', PINS.ana);
      await pg.click('#discGo');
      await pg.waitForSelector('#discModal', { state: 'hidden', timeout: 8000 });
      assert.strictEqual(sql(`select total_crc from orders where id = '${id(13)}'`), '4500', 'the bill is what the preview said');
      await until(async () => /4.?500/.test(await text(pg, '#tabTotals')), 8000, 'the window shows ₡4 500');
      await pg.locator('#tabLines .tline', { hasText: 'T Brownie' }).locator('button.rm').click();
      await until(() => sql(`select total_crc from orders where id = '${id(13)}'`) === '3150', 8000, 'a brownie off: 10 % of what is left (₡3 150)');
      await pg.click('#tabClose');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'U-a/U-b: a card from another device keeps a readable label and a light hover; a session that ends leaves no window over the sign-in box',
    run: async ({ browser }) => {
      testMenu();
      bill(14, null, 'done', [['T Latte', 2000, 1]], { station: 'Caja del frente', number: 7 });
      const pg = await till(browser, { viewport: { width: 820, height: 1180 } });
      await pg.evaluate(() => pollLive());
      const c7 = pg.locator('#openBar .ocard', { hasText: 'Caja del frente' });
      await until(async () => (await c7.count()) === 1, 8000, 'the card from the other device');
      const lw = await c7.locator('.on').evaluate((e) => e.getBoundingClientRect().width);
      assert.ok(lw >= 24, 'label #7 is ' + Math.round(lw) + ' px wide');
      assert.strictEqual(await c7.locator('.on').textContent(), '#7');
      await c7.hover();
      await until(async () => (await c7.evaluate((e) => getComputedStyle(e).backgroundColor)) === 'rgb(255, 255, 255)', 3000, 'a white hover background');

      await pg.evaluate((x) => openTab(x), id(14));
      await pg.waitForSelector('#tabModal:not([hidden])');
      await pg.evaluate(() => db.auth.signOut({ scope: 'local' }));
      await until(async () => (await pg.isVisible('#loginForm')) && (await pg.evaluate(() => [...document.querySelectorAll('.modal')].every((m) => m.hidden))), 8000, 'signed out, no window over the sign-in box');
      assert.deepStrictEqual(pg.errors, []);
    }
  }
];
