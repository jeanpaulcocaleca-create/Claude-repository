/* Discounts on bills (migration 0038, pos.html bill mode, time.html's «Devolver el cupo del día»): proposal §5.2 B-a
   (the whole bill, removal with nothing paid and after a payment, the day given back, a manager who is the beneficiary,
   a part paid on another device, the tour guide courtesy at ₡0), B-b (a pay-later ticket charged, voided and cancelled),
   O-c (a bill-mode reply lost, with and without an «online» event) and T-d (a slow bill-mode answer that arrives after
   the staff moved on). Owner's adjustment 3 (Q3's default, W1): an Empleado day stays used after it was given, until a
   valid void or a manager's audited give-back.
   Already in 070_tabs.spec.js and not repeated here: D-a (a held Empleado on bill A, Cancel, bill B opened: the late ok
   taken off A, the day still counts, B untouched), D-b (the window follows the bill under it) and D-c (a bill with an
   item paid by item refused before any code). Seed codes: Ana manager 4826, Luis staff 5284, Marta staff 6173, Dueño
   owner 7391 (tests/db/90_seed.sql). */
'use strict';
const assert = require('assert');
const { page, goto, until, sql, sqlJson, openRegister, registerTill, guiaOn, STAFF, PINS } = require('../lib');
const gw = require('../gateway');

const API = 'http://127.0.0.1:' + (Number(process.env.E2E_SITE_PORT || 8090) + 1000);
const id = (n) => 'd0000000-0000-4000-8000-0000004010' + String(n).padStart(2, '0');
const line = (n) => 'd0000000-0000-4000-8000-0000004020' + String(n).padStart(2, '0');
const ITEM = { sandwich: 'b0000000-0000-4000-8000-0000000000a1', latte: 'b0000000-0000-4000-8000-0000000000a2' };
const norm = (s) => String(s || '').replace(/\s/g, '');   /* amounts are printed with a (narrow) no-break space */

/* the Spanish the pages show (website/lang.js) */
const ES = {
  counts: 'Descuento quitado. El cupo del empleado sigue usado hoy; un encargado puede devolverlo en la bitácora de aprobaciones.',
  countsPaid: 'Descuento quitado. El cupo del empleado sigue usado hoy: ya se hizo un pago, así que no se puede devolver.',
  notAdded: 'Esa cuenta ya fue pagada. · Este pedido tiene un descuento, así que los productos no se agregaron: cóbrelos después de esta venta.',
  daily: 'Descuento diario ya utilizado',
  hasParts: 'Un descuento cubre toda la cuenta: solo se da antes de cualquier pago.',
  lost: 'No se pudo confirmar el descuento. La cuenta se revisa de nuevo al volver la conexión.',
  stayed: 'El descuento que no se pudo confirmar sí quedó en la cuenta.',
  late: 'El descuento que llegó tarde quedó en la cuenta: quítelo con ×.',
  offPaid: 'Quitar el descuento de una cuenta pagada en parte',
  courtesyAdd: 'Esta cuenta es una cortesía: cobre lo nuevo en otro pedido.',
  notFreedLbl: 'El descuento de empleado sigue contando',
  give: 'Devolver el cupo del día',
  notSelf: 'El empleado no puede devolverse su propio cupo.',
  prior: (n, m) => `Segundo descuento de empleado hoy para ${n}: el anterior lo anuló ${m}.`,
  givenBack: (n) => `Cupo devuelto a ${n}`
};

/* test products with known ids and prices (as 070): a kitchen sandwich and a latte from the bar */
function testMenu() {
  sql(`insert into menu_categories (id, name, sort, kitchen) values
         ('b0000000-0000-4000-8000-0000000000c1', 'Test Kitchen', 20, true),
         ('b0000000-0000-4000-8000-0000000000c2', 'Test Bar', 21, false);
       insert into menu_items (id, category_id, name, price_crc, sort, available) values
         ('${ITEM.sandwich}', 'b0000000-0000-4000-8000-0000000000c1', 'T Sandwich', 4000, 1, true),
         ('${ITEM.latte}', 'b0000000-0000-4000-8000-0000000000c2', 'T Latte', 2000, 1, true);`);
}
/* a bill not paid yet, as another device left it: 2 lattes and a sandwich, ₡8 000, unless lines are given */
function bill(n, name, lines) {
  lines = lines || [['T Latte', 2000, 2], ['T Sandwich', 4000, 1]];
  const total = lines.reduce((s, l) => s + l[1] * l[2], 0);
  sql(`insert into orders (id, total_crc, payment_method, status, paid, source, station, guest_name, done_at)
       values ('${id(n)}', ${total}, 'pending', 'done', false, 'front', 'Caja', '${name}', now())`);
  sql(`insert into order_items (id, order_id, item_name, price_crc, qty) values ` +
      lines.map((l, i) => `('${line(n * 4 + i)}', '${id(n)}', '${l[0]}', ${l[1]}, ${l[2]})`).join(', '));
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
const totalOf = (n) => Number(sql(`select total_crc from orders where id = '${id(n)}'`));
/* a part paid on another device: an amount, or one item by item */
async function payAmount(n, amount) {
  const r = await rpc('tab_pay', { p_order_id: id(n), p_method: 'card', p_lines: null, p_amount: amount, p_station: 'Caja 2', p_expect: totalOf(n) });
  assert.ok(r.ok, 'a part paid on another device: ' + JSON.stringify(r));
  return r;
}
async function payItem(n, lineId) {
  const r = await rpc('tab_pay', { p_order_id: id(n), p_method: 'card', p_lines: [{ item_id: lineId, qty: 1 }], p_amount: null, p_station: 'Caja 2', p_expect: totalOf(n) });
  assert.ok(r.ok, 'an item paid by item on another device: ' + JSON.stringify(r));
  return r;
}
function gate() { let open; const wait = new Promise((r) => { open = r; }); return { wait, open }; }
const approvals = (where) => sqlJson(`select coalesce(json_agg(json_build_object('id', id, 'bill', bill_id, 'order', order_id,
    'ben', beneficiary_name, 'amount', amount_crc, 'sub', subtotal_crc, 'freed', freed_how, 'freed_at', freed_at,
    'by', approved_name, 'role', approver_role, 'req', request_id) order by created_at), '[]'::json)
  from discount_approvals where category is not null and ${where}`);
const billRow = (n) => sqlJson(`select json_build_object('total', total_crc, 'disc', coalesce(discount_crc, 0), 'did', discount_id,
    'reason', discount_reason, 'paid', paid, 'parts', parts_crc, 'method', payment_method, 'status', status, 'voided', voided_at is not null)
  from orders where id = '${id(n)}'`);
const audits = (action, approval, extra) => Number(sql(`select count(*) from audit_log where action = '${action}'
    and details ->> 'approval' = '${approval}' ${extra || ''}`));

/* what a page asked the API (rpc name and body), in order, and what it showed in its toast (each text once it changed,
   so the Spanish lang.js puts in is kept even when the next toast replaces it) */
function recorder(pg) {
  pg.rpcs = [];
  pg.inflight = 0;
  const api = (r) => r.url().startsWith(API + '/rest/v1/');
  pg.on('request', (r) => {
    if (api(r)) pg.inflight++;
    const m = /\/rest\/v1\/rpc\/([a-z_0-9]+)/.exec(r.url());
    if (m && r.method() === 'POST') { let b = {}; try { b = JSON.parse(r.postData() || '{}'); } catch (e) {} pg.rpcs.push({ fn: m[1], body: b }); }
  });
  pg.on('requestfinished', (r) => { if (api(r)) pg.inflight--; });
  pg.on('requestfailed', (r) => { if (api(r)) pg.inflight--; });
}
async function toasts(pg) {
  await pg.evaluate(() => {
    window.__seen = [];
    const t = document.getElementById('toast');
    new MutationObserver(() => { const s = t.textContent; if (s && window.__seen[window.__seen.length - 1] !== s) window.__seen.push(s); })
      .observe(t, { childList: true, characterData: true, subtree: true });
  });
}
const seen = (pg) => pg.evaluate(() => window.__seen.slice());
const toastSeen = (pg, s, ms) => until(async () => (await seen(pg)).includes(s), ms || 8000, 'the message «' + s + '»');
const calls = (pg, fn) => pg.rpcs.filter((c) => c.fn === fn);
async function quiet(pg) { let calm = 0; await until(() => { calm = pg.inflight === 0 ? calm + 1 : 0; return calm >= 3; }, 10000, 'no request in flight'); }

/* the till (Spanish) with the register open, registered for discounts as a manager does it; its own 20 s retry and the
   live poll off (the tests drive every round), as in 070 */
async function till(browser, opts) {
  opts = Object.assign({ login: 'cafe', lang: 'es', viewport: { width: 1180, height: 820 } }, opts || {});
  openRegister();
  const pg = await page(browser, opts);
  recorder(pg);
  await pg.addInitScript(() => {
    const si = window.setInterval;
    window.setInterval = function (fn, ms) { return ms === 20000 ? 0 : si.apply(this, arguments); };
  });
  await goto(pg, '/pos');
  await pg.waitForSelector('#appView:not([hidden])', { timeout: 15000 });
  await pg.waitForFunction(() => document.querySelectorAll('.pbtn').length > 0, null, { timeout: 15000 });
  if (await pg.isVisible('#dayModal')) await pg.click('#dayClose');
  if (await pg.isVisible('#stationModal')) await pg.click('#stationForm button[type=submit]');
  await pg.evaluate(() => { clearInterval(liveTimer); });
  await toasts(pg);
  await registerTill(pg);
  return pg;
}
const text = async (pg, sel) => (await pg.textContent(sel)) || '';
const untilText = (pg, sel, re, ms) => until(async () => re.test(await text(pg, sel)), ms || 8000, sel + ' to read ' + re);
const exactly = (s) => new RegExp('^' + s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '$');
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
/* the discount window's own keys (pos.html #discPad), tapped as a person does */
async function padType(pg, code) { for (const d of code) await pg.click(`#discPad button[data-k="${d}"]`); }
async function openBill(pg, n) {
  await pg.evaluate((x) => openTab(x), id(n));
  await pg.waitForSelector('#tabModal:not([hidden])');
  await until(() => pg.evaluate((x) => !!tab && tab.o.id === x, id(n)), 8000, 'bill ' + n + ' open');
}
/* «Descuento» on the open bill: the window opens and has read the till's state */
async function discWindow(pg) {
  await pg.click('#tabDisc');
  await pg.waitForSelector('#discModal:not([hidden])');
  await until(() => pg.evaluate(() => !!disc.st || document.getElementById('discModal').hidden), 8000, 'the till state read');
}
/* Empleado: the employee's code, Autorizar (it continues), the manager's (or the owner's) code, Autorizar */
async function empleado(pg, emp, mgr) {
  await pg.click('[data-cat="empleado"]');
  await padType(pg, PINS[emp]);
  await pg.click('#discGo');
  await untilText(pg, '#discStep', /^Código de encargado$/);
  await padType(pg, PINS[mgr]);
  await pg.click('#discGo');
}
/* an Empleado on the open bill, approved: the window closes and the server has it on the bill */
async function empleadoOnBill(pg, n, emp, mgr) {
  await discWindow(pg);
  await empleado(pg, emp, mgr);
  await pg.waitForSelector('#discModal', { state: 'hidden', timeout: 10000 });
  await until(() => (billRow(n) || {}).disc > 0, 8000, 'the discount on bill ' + n);
  await until(async () => /Descuento₡[\d]+·Empleado/.test(norm(await text(pg, '#tabTotals'))), 8000, 'the bill window shows the discount');
}
async function managers(pg, sel, who) {
  await until(() => pg.evaluate((s) => [...document.querySelectorAll(s + ' option')].some((o) => o.textContent === 'Ana'), sel), 8000, 'managers listed');
  await pg.selectOption(sel, STAFF[who || 'ana']);
}
/* Reloj de marcas › Bitácora de aprobaciones on another device of the café: Ana opens the owner areas with her PIN */
async function approvalsLog(browser) {
  const lg = await page(browser, { login: 'cafe', lang: 'es', viewport: { width: 1180, height: 820 } });
  recorder(lg);
  await goto(lg, '/time');
  await until(async () => (await lg.locator('#staffGrid button').count()) > 0, 15000, 'the clock');
  await toasts(lg);
  await lg.click('#tabHours');
  await lg.waitForSelector('#hoursPinModal:not([hidden])', { timeout: 10000 });
  await lg.selectOption('#hpWho', STAFF.ana);
  await lg.type('#hpPin', PINS.ana);
  await lg.click('#hoursPinForm button[type=submit]');
  await until(async () => lg.locator('#hoursPinModal').isHidden(), 8000, 'the owner areas opened');
  return lg;
}
/* the log's «El descuento de empleado sigue contando» row of that employee, with its «Devolver el cupo del día» */
const notFreedRow = (lg, who) => lg.locator('#logBody .lrow', { hasText: ES.notFreedLbl }).filter({ hasText: who });

/* the next c.left calls of fn answered as PostgREST answers a deadlock (HTTP 500, SQLSTATE 40P01): the server ended the
   call and rolled it back whole, so here it never reaches the database; then the real server. The time of each call */
const DEADLOCK = { code: '40P01', message: 'deadlock detected', details: 'Process 101 waits for ShareLock on transaction 202; blocked by process 303.', hint: 'See server log for query details.' };
async function deadlocks(pg, fn) {
  const c = { left: 0, at: [], dead: 0 };
  await pg.route(new RegExp('/rest/v1/rpc/' + fn + '(\\?|$)'), async (r) => {
    if (r.request().method() !== 'POST') return r.fallback();
    c.at.push(Date.now());
    if (c.left > 0) { c.left--; c.dead++; return r.fulfill({ status: 500, contentType: 'application/json', body: JSON.stringify(DEADLOCK) }); }
    return r.fallback();
  });
  return c;
}
const gap = (c, i) => c.at[i] - c.at[i - 1];

/* checks whose failure is reported but does not stop the scenario: the later checks still run */
function softly() {
  const fails = [];
  const check = (ok, msg) => { if (!ok) fails.push(msg); };
  check.done = () => assert.deepStrictEqual(fails, [], 'failed checks:\n  - ' + fails.join('\n  - '));
  return check;
}

module.exports.tests = [
  {
    name: 'B-a: an Empleado on the whole bill; taken off with nothing paid (no PIN, the day stays used); Ana gives the day back in the approvals log and Luis is approved again; a bill paid in part refused before any code',
    run: async ({ browser }) => {
      testMenu();
      bill(1, 'Mesa Uno');
      bill(2, 'Mesa Pagada');
      await payAmount(2, 1000);   /* paid by amount on another device (070 D-c is the bill paid by item) */
      const pg = await till(browser);

      /* a bill with a part paid: refused before any code, nothing asked of the server */
      await openBill(pg, 2);
      await pg.click('#tabDisc');
      await untilText(pg, '#tabErr', exactly(ES.hasParts));
      assert.ok(await pg.isHidden('#discModal'), 'the window does not open on a bill paid in part');
      assert.strictEqual(pg.rpcs.filter((c) => /^descuento_/.test(c.fn)).length, 0, 'nothing asked of the server, no code typed');
      await pg.click('#tabClose');

      /* the whole bill: ₡8 000 of items, 30 % of all of them */
      await openBill(pg, 1);
      await discWindow(pg);
      await untilText(pg, '#discSub', /^Cuenta · Mesa Uno · ₡8.?000$/);
      await empleado(pg, 'luis', 'ana');
      await pg.waitForSelector('#discModal', { state: 'hidden', timeout: 10000 });
      const ask = calls(pg, 'descuento_autorizar').pop();
      assert.strictEqual(ask.body.p_order_id, id(1), 'bill mode: the call names the bill');
      assert.strictEqual(ask.body.p_subtotal, 8000, 'the subtotal is every item of the bill');
      assert.strictEqual(ask.body.p_expect, 8000, 'the total the page shows');
      await until(() => (billRow(1) || {}).disc === 2400, 8000, 'the discount on the bill');
      const a1 = approvals(`bill_id = '${id(1)}'`);
      assert.strictEqual(a1.length, 1, 'one approval for the bill');
      assert.deepStrictEqual([a1[0].ben, a1[0].sub, a1[0].amount, a1[0].order, a1[0].freed], ['Luis', 8000, 2400, id(1), null], 'Luis, the whole bill, linked to it');
      const b1 = billRow(1);
      assert.deepStrictEqual([b1.total, b1.disc, b1.did, b1.reason], [5600, 2400, a1[0].id, 'Employee'], 'the bill carries the approval: ₡5 600 to pay');
      await until(async () => norm(await text(pg, '#tabTotals')).includes('Descuento₡2400·Empleado'), 8000, 'the bill window shows the discount');
      assert.ok(!/%/.test(await text(pg, '#tabTotals')), 'no percentage on the bill');
      assert.ok(await pg.isHidden('#tabDisc') && await pg.isVisible('#tabDiscX'), 'Descuento hidden, «Quitar el descuento» shown');

      /* taken off with nothing paid: a confirmation, no PIN, the day stays used (Q3's default, W1) */
      const nq = calls(pg, 'descuento_quitar_cuenta').length;
      await pg.click('#tabDiscX');
      await toastSeen(pg, ES.counts);
      const off = calls(pg, 'descuento_quitar_cuenta').slice(nq);
      assert.strictEqual(off.length, 1, 'one removal sent');
      assert.ok(off[0].body.p_manager_id == null && off[0].body.p_manager_pin == null, 'no PIN for a bill with nothing paid: ' + JSON.stringify(off[0].body));
      assert.ok(await pg.isHidden('#tabRmBox'), 'no manager box');
      await until(() => (billRow(1) || {}).disc === 0, 8000, 'the discount off the bill');
      assert.deepStrictEqual([billRow(1).total, billRow(1).did], [8000, null], 'the bill back to ₡8 000');
      assert.strictEqual(approvals(`id = '${a1[0].id}'`)[0].freed_at, null, 'the approval still counts today');
      assert.strictEqual(audits('discount_not_freed', a1[0].id, `and details ->> 'why' = 'needs_manager' and details ->> 'how' = 'bill_removed'`), 1, 'logged: a manager can give it back');
      await until(() => pg.isVisible('#tabDisc'), 8000, 'Descuento offered again');

      /* the day stays used: Luis's next Empleado answers daily_used (no «Sin usar todavía»: that approval was used) */
      await discWindow(pg);
      await empleado(pg, 'luis', 'ana');
      await untilText(pg, '#discErr', exactly(ES.daily));
      assert.strictEqual(billRow(1).disc, 0, 'nothing on the bill');
      await pg.click('#discCancel');

      /* by now the café wrote more than 40 ordinary log rows (reprints, approvals, items taken off: anyone can cause them):
         the row and its button are still there (the server takes the give-back until midnight) */
      sql(`insert into audit_log (action, manager_name, target_id, summary, details)
           select 'receipt_reprint', 'Caja', 'r' || g, 'receipt reprinted', '{}'::jsonb from generate_series(1, 45) g`);
      /* the approvals log: «Devolver el cupo del día» next to the row; Ana gives it back with her own PIN (#lgApprove) */
      const lg = await approvalsLog(browser);
      const row = notFreedRow(lg, 'Luis');
      await until(async () => (await row.count()) === 1, 10000, 'the row «' + ES.notFreedLbl + '» for Luis');
      assert.match(await row.innerText(), /un encargado puede devolverlo/, 'it says a manager can give it back');
      await row.locator('button', { hasText: ES.give }).click();
      await lg.waitForSelector('#lgApprove:not([hidden])');
      // the box's title is set in English and translated by lang.js on the next frame: wait for the Spanish (a slow runner read it first)
      await until(async () => (await text(lg, '#lgWhat')) === 'Devolver el cupo del día a Luis', 5000, '#lgWhat «Devolver el cupo del día a Luis»');
      await lg.selectOption('#lgMgr', STAFF.ana);
      await lg.type('#lgMgrPin', PINS.ana);
      await lg.click('#lgGo');
      await toastSeen(lg, ES.givenBack('Luis'));
      const g = approvals(`id = '${a1[0].id}'`)[0];
      assert.strictEqual(g.freed, 'bill_removed', 'the day given back: taken off the bill');
      assert.strictEqual(sql(`select manager_name from audit_log where action = 'discount_freed' and details ->> 'approval' = '${a1[0].id}'`), 'Ana', 'the give-back names who did it');
      await until(async () => (await lg.locator('#logBody button', { hasText: ES.give }).count()) === 0, 8000, 'no «' + ES.give + '» left once given back');
      assert.deepStrictEqual(lg.errors, []);

      /* Luis's next Empleado is approved */
      await empleadoOnBill(pg, 1, 'luis', 'ana');
      assert.strictEqual(approvals(`beneficiary_id = '${STAFF.luis}' and freed_at is null`).length, 1, 'one live approval for Luis again');
      assert.strictEqual(billRow(1).total, 5600);
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'B-a: a manager who is the beneficiary cannot give her own day back («El empleado no puede devolverse su propio cupo.», no PIN tested); the owner can',
    run: async ({ browser }) => {
      testMenu();
      bill(3, 'Mesa Ana');
      const pg = await till(browser);
      await openBill(pg, 3);
      await empleadoOnBill(pg, 3, 'ana', 'dueno');   /* Ana's employee discount, authorized by the owner's code */
      const a = approvals(`bill_id = '${id(3)}'`)[0];
      assert.deepStrictEqual([a.ben, a.by, a.role], ['Ana', 'Dueño', 'owner'], 'Ana is the beneficiary, the owner authorized it');
      await pg.click('#tabDiscX');
      await toastSeen(pg, ES.counts);
      await until(() => (billRow(3) || {}).disc === 0, 8000, 'the discount off the bill');

      const lg = await approvalsLog(browser);
      const row = notFreedRow(lg, 'Ana');
      await until(async () => (await row.count()) === 1, 10000, 'the row for Ana');
      await row.locator('button', { hasText: ES.give }).click();
      await lg.waitForSelector('#lgApprove:not([hidden])');
      await lg.selectOption('#lgMgr', STAFF.ana);
      await lg.type('#lgMgrPin', '0000');   /* a wrong PIN: the refusal comes before any PIN is tested */
      const failed0 = sql(`select failed_pins || '/' || coalesce(locked_until::text, '-') from staff where id = '${STAFF.ana}'`);
      await lg.click('#lgGo');
      await untilText(lg, '#lgErr', exactly(ES.notSelf));
      assert.ok(await lg.isVisible('#lgApprove'), 'the box stays open');
      assert.strictEqual(sql(`select failed_pins || '/' || coalesce(locked_until::text, '-') from staff where id = '${STAFF.ana}'`), failed0, 'no PIN tested: Ana\'s count unchanged');
      assert.strictEqual(approvals(`id = '${a.id}'`)[0].freed_at, null, 'the day still used');
      assert.strictEqual(audits('discount_freed', a.id), 0, 'nothing given back');
      /* another person who may authorize gives it back */
      await lg.selectOption('#lgMgr', STAFF.dueno);
      await lg.type('#lgMgrPin', PINS.dueno);
      await lg.click('#lgGo');
      await toastSeen(lg, ES.givenBack('Ana'));
      assert.strictEqual(approvals(`id = '${a.id}'`)[0].freed, 'bill_removed');
      assert.deepStrictEqual(pg.errors.concat(lg.errors), []);
    }
  },
  {
    name: 'B-a: taken off after a part paid opens the manager box and the day stays used; a part paid on another device before the tap: nothing removed without the PIN (V5)',
    run: async ({ browser }) => {
      testMenu();
      bill(4, 'Mesa Parte');
      bill(5, 'Mesa Otra');
      bill(6, 'Mesa Dos Aparatos');
      const check = softly();
      const pg = await till(browser);

      /* Luis on bill 4, then ₡1 000 of it paid here by amount */
      await openBill(pg, 4);
      await empleadoOnBill(pg, 4, 'luis', 'ana');
      const a4 = approvals(`bill_id = '${id(4)}'`)[0];
      await pg.click('#tabSplit [data-mode="amount"]');
      await pg.fill('#tabAmt', '1000');
      await pg.click('#tabPayRow [data-tpay="card"]');
      await until(async () => (await pg.locator('#tabTotals .trow.part').count()) === 1, 8000, 'one part paid');
      assert.strictEqual(billRow(4).total, 4600, '₡5 600 less ₡1 000 paid');

      /* × opens the manager box (title, reason, a manager and the PIN); nothing is sent before the PIN */
      const nq = calls(pg, 'descuento_quitar_cuenta').length;
      await pg.click('#tabDiscX');
      await pg.waitForSelector('#tabRmBox:not([hidden])', { timeout: 5000 });
      await untilText(pg, '#tabRmWhich', exactly(ES.offPaid));
      await quiet(pg);
      assert.strictEqual(calls(pg, 'descuento_quitar_cuenta').length, nq, 'nothing sent before the manager\'s PIN');
      await pg.fill('#tabRmWhy', 'el cliente lo pidió');
      await managers(pg, '#tabRmMgr', 'ana');
      await pg.fill('#tabRmPin', PINS.ana);
      await pg.click('#tabRmGo');
      /* a payment was made: the day is never given back, so the message does not send a manager to the approvals log */
      await toastSeen(pg, ES.countsPaid);
      assert.ok(!(await seen(pg)).includes(ES.counts), 'not «un encargado puede devolverlo»: ' + JSON.stringify(await seen(pg)));
      await pg.waitForSelector('#tabRmBox', { state: 'hidden', timeout: 5000 });
      const sent = calls(pg, 'descuento_quitar_cuenta').slice(nq);
      assert.strictEqual(sent.length, 1);
      assert.deepStrictEqual([sent[0].body.p_manager_id, sent[0].body.p_reason], [STAFF.ana, 'el cliente lo pidió'], 'the manager and the reason go with it');
      const b4 = billRow(4);
      assert.deepStrictEqual([b4.total, b4.disc, b4.did], [7000, 0, null], 'the discount off: ₡8 000 less the ₡1 000 paid');
      assert.strictEqual(sql(`select manager_name || '|' || summary from audit_log where action = 'discount_removed_paid' and details ->> 'approval' = '${a4.id}'`),
        'Ana|el cliente lo pidió', 'logged with the manager and the reason');
      assert.strictEqual(audits('discount_not_freed', a4.id, `and details ->> 'why' = 'paid'`), 1, 'the day is not freed after a payment');
      assert.strictEqual(approvals(`id = '${a4.id}'`)[0].freed_at, null, 'the approval still counts');
      await pg.click('#tabClose');
      /* the day stays used */
      await openBill(pg, 5);
      await discWindow(pg);
      await empleado(pg, 'luis', 'ana');
      await untilText(pg, '#discErr', exactly(ES.daily));
      await pg.click('#discCancel');
      await pg.click('#tabClose');

      /* V5: Marta on bill 6; this device saw nothing paid; another device pays ₡1 000 of it; then × is tapped */
      await openBill(pg, 6);
      await empleadoOnBill(pg, 6, 'marta', 'ana');
      const a6 = approvals(`bill_id = '${id(6)}'`)[0];
      await payAmount(6, 1000);
      const nq6 = calls(pg, 'descuento_quitar_cuenta').length;
      const answered = pg.waitForResponse((r) => /rpc\/descuento_quitar_cuenta/.test(r.url()));
      await pg.click('#tabDiscX');
      const ans = await (await answered).json();
      const noPin = calls(pg, 'descuento_quitar_cuenta').slice(nq6);
      assert.ok(noPin.length === 1 && noPin[0].body.p_manager_pin == null, 'the removal went without a PIN (the page saw nothing paid)');
      assert.ok(!ans.ok, 'the server refuses it without a PIN: ' + JSON.stringify(ans));
      await quiet(pg);
      const b6 = billRow(6);
      assert.ok(b6.disc > 0 && b6.did === a6.id, 'nothing removed without the PIN: ' + JSON.stringify(b6));
      assert.ok(['needs_pin', 'changed'].includes(ans.error), 'a part paid meanwhile (needs_pin) or the bill changed under the page: ' + JSON.stringify(ans));
      check(await pg.isVisible('#tabRmBox') && await untilText(pg, '#tabRmWhich', exactly(ES.offPaid), 3000).then(() => true, () => false),
        'V5: the manager box opens after the PIN-less removal is refused (proposal §3.5, §5.2 B-a); #tabRmBox hidden=' + (await pg.isHidden('#tabRmBox')) + ', #tabErr «' + (await text(pg, '#tabErr')) + '»');
      /* the page has the bill as it is now: × opens the manager box; with the PIN it is taken off */
      if (await pg.isHidden('#tabRmBox')) {
        await pg.click('#tabDiscX');
        await pg.waitForSelector('#tabRmBox:not([hidden])', { timeout: 5000 });
      }
      assert.strictEqual(billRow(6).did, a6.id, 'still on the bill until a manager confirms');
      await pg.fill('#tabRmWhy', 'pagó una parte en la otra caja');
      await managers(pg, '#tabRmMgr', 'ana');
      await pg.fill('#tabRmPin', PINS.ana);
      await pg.click('#tabRmGo');
      await toastSeen(pg, ES.countsPaid);
      await until(() => (billRow(6) || {}).disc === 0, 8000, 'taken off with the PIN');
      assert.strictEqual(audits('discount_removed_paid', a6.id), 1);
      assert.strictEqual(approvals(`id = '${a6.id}'`)[0].freed_at, null, 'Marta\'s day stays used');

      /* the approvals log: both removals after a payment still count, and no one can give those days back */
      const lg = await approvalsLog(browser);
      await until(async () => (await lg.locator('#logBody .lrow', { hasText: ES.notFreedLbl }).filter({ hasText: 'quitado después de un pago' }).count()) === 2, 10000,
        'the two «' + ES.notFreedLbl + ' · … · quitado después de un pago» rows');
      assert.strictEqual(await lg.locator('#logBody button', { hasText: ES.give }).count(), 0, 'no «' + ES.give + '» after a payment');
      assert.deepStrictEqual(pg.errors.concat(lg.errors), []);
      check.done();
    }
  },
  {
    name: 'B-a: a tour guide courtesy on a bill shows only «Registrar cortesía», which calls tab_pay with \'other\' and no lines or amount and closes it at ₡0; adding to it is refused',
    run: async ({ browser }) => {
      guiaOn();
      testMenu();
      bill(7, 'Mesa Guía');
      const pg = await till(browser);
      await openBill(pg, 7);
      await discWindow(pg);
      await pg.click('[data-cat="guia"]');
      await pg.waitForSelector('#discText:not([hidden])');
      await pg.click('#discText');
      await pg.keyboard.type('Monteverde Tours');
      await pg.click('#discGo');
      await untilText(pg, '#discStep', /^Código del dueño$/);
      await padType(pg, PINS.dueno);
      await pg.click('#discGo');
      await pg.waitForSelector('#discModal', { state: 'hidden', timeout: 10000 });
      await until(() => (billRow(7) || {}).total === 0, 8000, 'the courtesy on the bill');
      const a = approvals(`bill_id = '${id(7)}'`)[0];
      assert.deepStrictEqual([a.amount, a.sub, a.by, a.role], [8000, 8000, 'Dueño', 'owner'], 'the whole bill, by the owner');
      assert.deepStrictEqual([billRow(7).disc, billRow(7).reason], [8000, 'Tour guide']);
      assert.strictEqual(Number(sql(`select count(*) from access_unlocks where staff_id = '${STAFF.dueno}'`)), 0, 'the owner\'s code opened no owner area (adjustment 1)');

      /* only «Registrar cortesía»; no split */
      await until(async () => (await pg.locator('#tabPayRow [data-tpay]:visible').count()) === 1, 8000, 'one pay button');
      const only = pg.locator('#tabPayRow [data-tpay]:visible');
      assert.strictEqual((await only.textContent()).trim(), 'Registrar cortesía');
      assert.strictEqual(await only.getAttribute('data-tpay'), 'other');
      assert.ok(await pg.isHidden('#tabSplit'), 'no way to split a courtesy');

      /* adding to it is refused */
      await pg.click('#tabAdd');
      await untilText(pg, '#tabErr', exactly(ES.courtesyAdd));
      assert.ok(await pg.isHidden('#addBar'), 'not in adding mode');
      assert.ok(await pg.isVisible('#tabModal'), 'the bill stays open');
      assert.strictEqual(calls(pg, 'tab_add_items').length, 0);

      /* closed at ₡0 */
      const n0 = calls(pg, 'tab_pay').length;
      await only.click();
      await pg.waitForSelector('#tabPaidAll:not([hidden])', { timeout: 8000 });
      const pay = calls(pg, 'tab_pay').slice(n0);
      assert.strictEqual(pay.length, 1, 'one call');
      assert.deepStrictEqual([pay[0].body.p_method, pay[0].body.p_lines, pay[0].body.p_amount, pay[0].body.p_order_id], ['other', null, null, id(7)], 'tab_pay: other, no lines, no amount');
      const b = billRow(7);
      assert.deepStrictEqual([b.paid, b.total, b.method], [true, 0, 'other'], 'closed at ₡0 as a courtesy');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'B-b: a pay-later ticket with Empleado, charged with tab_pay and voided by Ana (the day freed: the next is approved with the «Segundo descuento…» line); another, cancelled (the day still counts)',
    run: async ({ browser }) => {
      testMenu();
      const pg = await till(browser);
      async function payLater(who, number) {
        await tap(pg, 'T Latte'); await tap(pg, 'T Latte'); await tap(pg, 'T Sandwich');
        await pg.click('#discBtn');
        await pg.waitForSelector('#discModal:not([hidden])');
        await until(() => pg.evaluate(() => !!disc.st), 8000, 'the till state read');
        await empleado(pg, 'luis', 'ana');
        await pg.waitForSelector('#discModal', { state: 'hidden', timeout: 10000 });
        await until(() => pg.evaluate(() => !!tDisc), 8000, 'the discount on the ticket');
        assert.strictEqual((await text(pg, '#sendBtn')).trim(), 'Cobrar después', 'the main till\'s pay-later button');
        await pg.click('#sendBtn');
        await pg.waitForSelector('#numModal:not([hidden])');
        await pg.fill('#numWho', who);
        await pg.locator('#numGrid button', { hasText: new RegExp('^' + number + '$') }).click();
        const oid = await until(() => sql(`select id from orders where pickup_number = ${number} and guest_name = '${who}'`), 10000, 'the pay-later order saved');
        await until(() => pg.evaluate(() => queue.length === 0), 8000, 'nothing waiting on the device');
        return oid;
      }
      const freedOf = (oid) => approvals(`order_id = '${oid}'`)[0];

      /* 1. Cobrar después, then charged with tab_pay, then voided by Ana (not the beneficiary): the day freed */
      const o1 = await payLater('Cuenta Luis', 7);
      const r1 = sqlJson(`select json_build_object('paid', paid, 'total', total_crc, 'disc', discount_crc, 'did', discount_id, 'm', payment_method) from orders where id = '${o1}'`);
      const ap1 = freedOf(o1);
      assert.deepStrictEqual([r1.paid, r1.total, r1.disc, r1.did, r1.m], [false, 5600, 2400, ap1.id, 'pending'], 'sent unpaid, carrying the approval');
      await pg.evaluate((x) => openTab(x), o1);
      await pg.waitForSelector('#tabModal:not([hidden])');
      await until(async () => norm(await text(pg, '#tabDue')) === '₡5600', 8000, 'the bill: ₡5 600 to pay');
      const np = calls(pg, 'tab_pay').length;
      await pg.click('#tabPayRow [data-tpay="card"]');
      await pg.waitForSelector('#tabPaidAll:not([hidden])', { timeout: 8000 });
      assert.strictEqual(calls(pg, 'tab_pay').length, np + 1, 'charged with tab_pay');
      assert.strictEqual(sql(`select paid || '/' || total_crc || '/' || payment_method from orders where id = '${o1}'`), 'true/5600/card', 'charged');
      await pg.click('#tabClose');
      await pg.click('#ordersBtn');
      const orow = pg.locator('#ordersBody .orow', { hasText: 'Cuenta Luis' });
      await until(async () => (await orow.count()) === 1, 8000, 'the order in Orders');
      await orow.locator('button', { hasText: /^Anular$/ }).click();
      await pg.waitForSelector('#voidBox:not([hidden])');
      await pg.fill('#vReason', 'prueba de anulación');
      await pg.selectOption('#vMgr', STAFF.ana);
      await pg.fill('#vPin', PINS.ana);
      await pg.click('#vGo');
      await until(() => sql(`select voided_at is not null from orders where id = '${o1}'`) === 't', 8000, 'voided');
      assert.strictEqual(freedOf(o1).freed, 'void', 'the void frees the day');
      assert.strictEqual(sql(`select manager_name || '/' || (details ->> 'how') from audit_log where action = 'discount_freed' and details ->> 'approval' = '${ap1.id}'`), 'Ana/void', 'logged: freed by Ana\'s void');
      await pg.click('#ordersClose');

      /* 2. the day is free again: approved, with the line about the void; then the unpaid order is cancelled */
      const o2 = await payLater('Cuenta Luis 2', 8);
      await toastSeen(pg, ES.prior('Luis', 'Ana'));
      const ap2 = freedOf(o2);
      assert.strictEqual(ap2.freed_at, null);
      assert.strictEqual(sql(`select status from orders where id = '${o2}'`) !== 'done', true, 'the sandwich keeps it in the kitchen: it can still be cancelled');
      await pg.evaluate((x) => openTab(x), o2);
      await pg.waitForSelector('#tabModal:not([hidden])');
      await pg.waitForSelector('#tabCancel:not([hidden])');
      await pg.click('#tabCancel');
      await toastSeen(pg, 'Pedido cancelado');
      assert.strictEqual(sql(`select status from orders where id = '${o2}'`), 'cancelled', 'cancelled');
      assert.strictEqual(freedOf(o2).freed_at, null, 'a cancelled bill does not free the day by itself (Q3)');
      assert.strictEqual(audits('discount_not_freed', ap2.id, `and details ->> 'why' = 'needs_manager' and details ->> 'how' = 'bill_cancelled'`), 1, 'logged: a manager can give it back');

      /* 3. the day still counts */
      await tap(pg, 'T Latte');
      await pg.click('#discBtn');
      await pg.waitForSelector('#discModal:not([hidden])');
      await until(() => pg.evaluate(() => !!disc.st), 8000, 'the till state read');
      await empleado(pg, 'luis', 'ana');
      await untilText(pg, '#discErr', exactly(ES.daily));
      await pg.click('#discCancel');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'O-c: both replies of a bill-mode Empleado lost, Cancel, then the connection returns: the replay (same request id, no codes) finds it and takes it off again; the day still counts',
    run: async ({ browser }) => {
      testMenu();
      bill(8, 'Mesa Sin Red');
      const pg = await till(browser);
      let drop = 0; const lost = [];
      await pg.route(/rest\/v1\/rpc\/descuento_autorizar/, async (r) => {
        let b = {}; try { b = JSON.parse(r.request().postData() || '{}'); } catch (e) {}
        if (r.request().method() !== 'POST' || drop <= 0 || !b.p_pin) return r.fallback();
        drop--;
        const resp = await r.fetch();          /* the server commits; the page never hears it */
        lost.push(await resp.json());
        return r.abort('failed');
      });
      await openBill(pg, 8);
      await discWindow(pg);
      drop = 2;
      await empleado(pg, 'luis', 'ana');
      await untilText(pg, '#discErr', exactly(ES.lost), 15000);
      assert.strictEqual(lost.length, 2, 'the first try and the retry both lost');
      assert.ok(lost[0].ok && lost[1].ok && lost[1].replay === true && lost[1].id === lost[0].id, 'the retry was answered as a replay of the first: ' + JSON.stringify(lost));
      const reqId = calls(pg, 'descuento_autorizar').pop().body.p_request_id;
      assert.strictEqual(approvals(`bill_id = '${id(8)}'`).length, 1, 'one approval');
      assert.strictEqual(billRow(8).disc, 2400, 'the first call committed: the discount is on the bill');

      await pg.click('#discCancel');
      await quiet(pg);
      const n0 = pg.rpcs.length;
      await pg.context().setOffline(true);
      await until(() => pg.evaluate(() => !navigator.onLine), 5000, 'offline');
      const takenBack = pg.waitForResponse((r) => /rpc\/descuento_quitar_cuenta/.test(r.url()), { timeout: 10000 });
      await pg.context().setOffline(false);
      const ans = await (await takenBack).json();
      const after = pg.rpcs.slice(n0);
      const replay = after.find((c) => c.fn === 'descuento_autorizar');
      assert.ok(replay, 'a replay on «online»');
      assert.strictEqual(replay.body.p_request_id, reqId, 'the same request id');
      assert.ok(replay.body.p_pin == null && replay.body.p_employee_pin == null, 'no codes in the replay: ' + JSON.stringify(replay.body));
      assert.ok(!JSON.stringify(replay.body).includes(PINS.luis) && !JSON.stringify(replay.body).includes(PINS.ana), 'no code anywhere in it');
      assert.ok(after.indexOf(replay) < after.findIndex((c) => c.fn === 'descuento_quitar_cuenta'), 'the replay first, then the removal');
      assert.ok(ans.ok && ans.counts === true, 'taken off again: ' + JSON.stringify(ans));
      await toastSeen(pg, ES.counts);
      await until(() => (billRow(8) || {}).disc === 0, 8000, 'the bill ends without the discount');
      const a = approvals(`bill_id = '${id(8)}'`);
      assert.strictEqual(a.length, 1, 'still one approval');
      assert.strictEqual(a[0].freed_at, null, 'it still counts (Q3, W1)');
      assert.strictEqual(audits('discount_not_freed', a[0].id, `and details ->> 'why' = 'needs_manager'`), 1);
      await until(async () => !norm(await text(pg, '#tabTotals')).includes('Descuento'), 8000, 'the bill window reloaded without it');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'O-c: both replies lost with the window still open on the bill, then the connection returns: the replay finds the discount and the bill keeps it',
    run: async ({ browser }) => {
      testMenu();
      bill(9, 'Mesa Espera');
      const check = softly();
      const pg = await till(browser);
      let drop = 0;
      await pg.route(/rest\/v1\/rpc\/descuento_autorizar/, async (r) => {
        let b = {}; try { b = JSON.parse(r.request().postData() || '{}'); } catch (e) {}
        if (r.request().method() !== 'POST' || drop <= 0 || !b.p_pin) return r.fallback();
        drop--; await r.fetch(); return r.abort('failed');
      });
      await openBill(pg, 9);
      await discWindow(pg);
      drop = 2;
      await empleado(pg, 'luis', 'ana');
      await untilText(pg, '#discErr', exactly(ES.lost), 15000);
      const reqId = calls(pg, 'descuento_autorizar').pop().body.p_request_id;
      const a = approvals(`bill_id = '${id(9)}'`)[0];
      assert.ok(await pg.isVisible('#discModal'), 'the window is still open on the bill');

      await quiet(pg);
      const n0 = pg.rpcs.length;
      await pg.context().setOffline(true);
      await until(() => pg.evaluate(() => !navigator.onLine), 5000, 'offline');
      const replayed = pg.waitForResponse((r) => /rpc\/descuento_autorizar/.test(r.url()), { timeout: 10000 });
      await pg.context().setOffline(false);
      await replayed;
      await quiet(pg);
      const after = pg.rpcs.slice(n0);
      const replay = after.find((c) => c.fn === 'descuento_autorizar');
      assert.ok(replay && replay.body.p_request_id === reqId && replay.body.p_pin == null && replay.body.p_employee_pin == null,
        'the replay: the same request id, no codes: ' + JSON.stringify(replay && replay.body));
      const b = billRow(9);
      check(b.disc === 2400 && b.did === a.id,
        'O-c: on reconnect with the window still open on that bill, the bill keeps the discount the first call committed (proposal §5.2 O-c; the task); it is ' + JSON.stringify(b));
      check(calls(pg, 'descuento_quitar_cuenta').length === 0,
        'O-c: the page does not take the found discount off when the staff never left that bill (no Cancel, no other bill); it sent descuento_quitar_cuenta and showed ' +
        JSON.stringify(await seen(pg)));
      check(await until(async () => norm(await text(pg, '#tabTotals')).includes('Descuento₡2400·Empleado'), 5000, 'the bill window').catch(() => false),
        'O-c: the bill window, reloaded, shows the discount; it reads «' + (await text(pg, '#tabTotals')) + '»');
      check(audits('discount_not_freed', a.id) === 0, 'O-c: Luis\'s day is not marked «sigue contando» for a discount he kept');
      assert.strictEqual(approvals(`bill_id = '${id(9)}'`).length, 1, 'no second approval');
      assert.deepStrictEqual(pg.errors, []);
      check.done();
    }
  },
  {
    name: 'O-c (W6): replies lost while navigator.onLine stays true; reopened on the same bill, or the codes typed again: the replay goes first with no codes, the discount stays, «sí quedó en la cuenta»',
    run: async ({ browser }) => {
      testMenu();
      bill(10, 'Mesa Wifi');
      bill(11, 'Mesa Wifi Dos');
      const pg = await till(browser);
      let drop = 0;
      await pg.route(/rest\/v1\/rpc\/descuento_autorizar/, async (r) => {
        let b = {}; try { b = JSON.parse(r.request().postData() || '{}'); } catch (e) {}
        if (r.request().method() !== 'POST' || drop <= 0 || !b.p_pin) return r.fallback();
        drop--; await r.fetch(); return r.abort('failed');
      });
      const lostOn = async (n, emp) => {
        await openBill(pg, n);
        await discWindow(pg);
        drop = 2;
        await empleado(pg, emp, 'ana');
        await untilText(pg, '#discErr', exactly(ES.lost), 15000);
        assert.ok(await pg.evaluate(() => navigator.onLine), 'the browser still says online: no «online» event will come');
        await quiet(pg);
        return calls(pg, 'descuento_autorizar').pop().body.p_request_id;
      };

      /* (a) Luis on bill 10; Cancel; the window opened again on the same bill */
      const req10 = await lostOn(10, 'luis');
      const a10 = approvals(`bill_id = '${id(10)}'`)[0];
      await pg.click('#discCancel');
      await quiet(pg);
      const n0 = pg.rpcs.length;
      await pg.click('#tabDisc');
      await toastSeen(pg, ES.stayed);
      await pg.waitForSelector('#discModal', { state: 'hidden', timeout: 8000 });
      await quiet(pg);
      const after = pg.rpcs.slice(n0);
      const iRep = after.findIndex((c) => c.fn === 'descuento_autorizar');
      const iEst = after.findIndex((c) => c.fn === 'descuento_estado');
      assert.ok(iRep > -1 && after[iRep].body.p_request_id === req10 && after[iRep].body.p_pin == null && after[iRep].body.p_employee_pin == null,
        'the replay: same request id, no codes: ' + JSON.stringify(after[iRep] && after[iRep].body));
      assert.ok(iEst === -1 || iRep < iEst, 'the replay goes first: ' + after.map((c) => c.fn).join(', '));
      assert.strictEqual(after.filter((c) => c.fn === 'descuento_autorizar').length, 1, 'no second approval asked for');
      assert.strictEqual(after.filter((c) => c.fn === 'descuento_quitar_cuenta').length, 0, 'nothing taken off');
      const b10 = billRow(10);
      assert.deepStrictEqual([b10.disc, b10.did], [2400, a10.id], 'the discount stays on the bill');
      assert.strictEqual(approvals(`beneficiary_id = '${STAFF.luis}'`).length, 1, 'one approval for Luis');
      assert.strictEqual(audits('discount_not_freed', a10.id), 0, 'Luis\'s day not touched');
      await until(async () => norm(await text(pg, '#tabTotals')).includes('Descuento₡2400·Empleado'), 8000, 'the bill reloaded with it');
      await pg.click('#tabClose');

      /* (b) Marta on bill 11; the window stays open and the codes are typed again: the replay goes before any new call */
      const req11 = await lostOn(11, 'marta');
      const a11 = approvals(`bill_id = '${id(11)}'`)[0];
      const n1 = pg.rpcs.length;
      await empleado(pg, 'marta', 'ana');
      await toastSeen(pg, ES.stayed);
      await pg.waitForSelector('#discModal', { state: 'hidden', timeout: 8000 });
      await quiet(pg);
      const typed = pg.rpcs.slice(n1).filter((c) => c.fn === 'descuento_autorizar');
      assert.strictEqual(typed.length, 1, 'one call: the replay');
      assert.ok(typed[0].body.p_request_id === req11 && typed[0].body.p_pin == null && typed[0].body.p_employee_pin == null, 'the codes typed again are not sent: ' + JSON.stringify(typed[0].body));
      assert.ok(!pg.rpcs.slice(n1).some((c) => JSON.stringify(c.body).includes(PINS.marta)), 'Marta\'s code is not sent again');
      assert.deepStrictEqual([billRow(11).disc, billRow(11).did], [2400, a11.id], 'the discount stays on bill 11');
      assert.strictEqual(approvals(`beneficiary_id = '${STAFF.marta}'`).length, 1, 'one approval for Marta');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'O-c (W6): a reply lost on bill A while online, then the window opened on bill B: the replay goes first and takes A\'s discount off again; B then answers daily_used for Luis',
    run: async ({ browser }) => {
      testMenu();
      bill(12, 'Mesa A');
      bill(13, 'Mesa B');
      const pg = await till(browser);
      let drop = 0;
      await pg.route(/rest\/v1\/rpc\/descuento_autorizar/, async (r) => {
        let b = {}; try { b = JSON.parse(r.request().postData() || '{}'); } catch (e) {}
        if (r.request().method() !== 'POST' || drop <= 0 || !b.p_pin) return r.fallback();
        drop--; await r.fetch(); return r.abort('failed');
      });
      await openBill(pg, 12);
      await discWindow(pg);
      drop = 2;
      await empleado(pg, 'luis', 'ana');
      await untilText(pg, '#discErr', exactly(ES.lost), 15000);
      const reqA = calls(pg, 'descuento_autorizar').pop().body.p_request_id;
      const aA = approvals(`bill_id = '${id(12)}'`)[0];
      await pg.click('#discCancel');
      await pg.click('#tabClose');
      await quiet(pg);

      const n0 = pg.rpcs.length;
      await openBill(pg, 13);
      await discWindow(pg);
      await toastSeen(pg, ES.counts);
      await until(() => (billRow(12) || {}).disc === 0, 8000, 'A\'s discount taken off');
      const seenB = pg.rpcs.slice(n0);
      const iRep = seenB.findIndex((c) => c.fn === 'descuento_autorizar');
      const iOff = seenB.findIndex((c) => c.fn === 'descuento_quitar_cuenta');
      assert.ok(iRep > -1 && seenB[iRep].body.p_request_id === reqA && seenB[iRep].body.p_pin == null, 'the replay of A, no codes');
      assert.ok(iOff > iRep && seenB[iOff].body.p_order_id === id(12), 'then A\'s discount taken off');
      assert.ok(await pg.isVisible('#discModal'), 'B\'s window stays open');
      assert.match(await text(pg, '#discSub'), /Mesa B/, 'for bill B');
      assert.strictEqual(approvals(`id = '${aA.id}'`)[0].freed_at, null, 'Luis\'s day stays used');
      assert.strictEqual(audits('discount_not_freed', aA.id, `and details ->> 'why' = 'needs_manager'`), 1);

      /* B's call for Luis: the day stays used until a manager gives it back */
      await empleado(pg, 'luis', 'ana');
      await untilText(pg, '#discErr', exactly(ES.daily));
      const bCall = calls(pg, 'descuento_autorizar').pop();
      assert.ok(bCall.body.p_order_id === id(13) && iOff < pg.rpcs.indexOf(bCall), 'B\'s own call after the replay and the removal');
      assert.deepStrictEqual([billRow(12).disc, billRow(13).disc], [0, 0], 'both bills end without a discount');
      assert.strictEqual(approvals(`beneficiary_id = '${STAFF.luis}'`).length, 1, 'no second approval');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'T-d: a held Empleado on bill A, another category tapped (the window\'s «Volver»): the late ok is taken off A again, the window stays on A untouched, the day still counts',
    run: async ({ browser }) => {
      testMenu();
      bill(14, 'Mesa Lenta');
      const pg = await till(browser);
      let held = false; const hold = gate();
      await pg.route(/rest\/v1\/rpc\/descuento_autorizar/, async (r) => {
        let b = {}; try { b = JSON.parse(r.request().postData() || '{}'); } catch (e) {}
        if (r.request().method() === 'POST' && b.p_pin && !held){ held = true; await hold.wait; }
        return r.fallback();
      });
      await openBill(pg, 14);
      await discWindow(pg);
      await empleado(pg, 'luis', 'ana');
      await until(() => held, 8000, 'the approval on its way, held');
      await pg.click('[data-cat="local"]');
      await untilText(pg, '#discStep', /^Código de encargado$/);
      const off = pg.waitForResponse((r) => /rpc\/descuento_quitar_cuenta/.test(r.url()) && JSON.parse(r.request().postData() || '{}').p_order_id === id(14));
      hold.open();
      const ans = await (await off).json();
      assert.ok(ans.ok && ans.counts === true, 'taken off again with no PIN: ' + JSON.stringify(ans));
      await toastSeen(pg, ES.counts);
      await quiet(pg);
      const a = approvals(`bill_id = '${id(14)}'`);
      assert.strictEqual(a.length, 1, 'the approval was made');
      assert.deepStrictEqual([billRow(14).total, billRow(14).disc, billRow(14).did], [8000, 0, null], 'bill A ends without the discount');
      assert.strictEqual(sql(`select string_agg(action, ',' order by action) from audit_log where action in ('discount_approved', 'tab_discount_removed', 'discount_not_freed')
                               and (target_id in ('${id(14)}', '${a[0].id}') or details ->> 'bill' = '${id(14)}')`),
        'discount_approved,discount_not_freed,tab_discount_removed', 'logged once each: approved, taken off, still counts');
      assert.strictEqual(audits('discount_not_freed', a[0].id, `and details ->> 'why' = 'needs_manager'`), 1);
      assert.ok(await pg.isVisible('#discModal'), 'the window stays open');
      assert.strictEqual(await pg.evaluate(() => disc.cat + '/' + disc.step + '/' + disc.bill), 'local/1/' + id(14), 'on Local, step 1, bill A');
      assert.strictEqual(await text(pg, '#discErr'), '', 'no message in the window');
      assert.strictEqual(await pg.inputValue('#discPin'), '', 'the code box empty');
      /* Luis's next Empleado: the day still counts (a manager gives it back: B-a above) */
      await empleado(pg, 'luis', 'ana');
      await untilText(pg, '#discErr', exactly(ES.daily));
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'T-d: a slow Empleado answer on bill A arrives after Cancel, but an item of A was paid on another device meanwhile: it stays on A, «quedó en la cuenta: quítelo con ×», and × needs the manager',
    run: async ({ browser }) => {
      testMenu();
      bill(15, 'Mesa Pagando');
      const pg = await till(browser);
      let holding = false, committed = false; const hold = gate();
      await pg.route(/rest\/v1\/rpc\/descuento_autorizar/, async (r) => {
        let b = {}; try { b = JSON.parse(r.request().postData() || '{}'); } catch (e) {}
        if (r.request().method() !== 'POST' || !b.p_pin || holding) return r.fallback();
        holding = true;
        const resp = await r.fetch();         /* the server approves and applies; its reply waits */
        committed = true;
        await hold.wait;
        return r.fulfill({ response: resp });
      });
      await openBill(pg, 15);
      await discWindow(pg);
      await empleado(pg, 'marta', 'ana');
      await until(() => committed, 8000, 'the server answered (the reply held)');
      const a = approvals(`bill_id = '${id(15)}'`)[0];
      assert.strictEqual(billRow(15).did, a.id, 'on the bill on the server');
      await pg.click('#discCancel');
      assert.ok(await pg.isVisible('#tabModal'), 'bill A still open on this device');
      await payItem(15, line(60));   /* one latte of bill A paid by item on another device */

      const off = pg.waitForResponse((r) => /rpc\/descuento_quitar_cuenta/.test(r.url()));
      const n0 = calls(pg, 'descuento_quitar_cuenta').length;
      hold.open();
      const ans = await (await off).json();
      const sent = calls(pg, 'descuento_quitar_cuenta').slice(n0);
      assert.ok(sent.length === 1 && sent[0].body.p_manager_pin == null && sent[0].body.p_order_id === id(15), 'the page tries to take the late discount off, with no PIN');
      assert.ok(!ans.ok && ['needs_pin', 'changed'].includes(ans.error), 'the server keeps it: a part was paid (needs_pin) or the bill changed: ' + JSON.stringify(ans));
      await toastSeen(pg, ES.late);
      await quiet(pg);
      const b = billRow(15);
      assert.ok(b.did === a.id && b.disc > 0, 'the discount stayed on bill A: ' + JSON.stringify(b));
      await until(async () => /Descuento₡\d+·Empleado/.test(norm(await text(pg, '#tabTotals'))), 8000, 'the bill reloaded with the discount');
      assert.ok(await pg.isVisible('#tabDiscX'), 'with its ×');
      assert.ok(await pg.isVisible('#tabTotals .trow.part') || (await pg.locator('#tabLines .tline .tags .paid').count()) > 0, 'and the item paid on the other device');
      assert.strictEqual(audits('discount_not_freed', a.id), 0, 'nothing taken off, nothing logged as taken off');

      /* × now needs a manager: the box opens, nothing is sent before the PIN */
      await pg.click('#tabDiscX');
      await pg.waitForSelector('#tabRmBox:not([hidden])', { timeout: 5000 });
      await untilText(pg, '#tabRmWhich', exactly(ES.offPaid));
      await quiet(pg);
      assert.strictEqual(calls(pg, 'descuento_quitar_cuenta').length, n0 + 1, 'nothing sent without the PIN');
      await pg.click('#tabRmCancel');
      assert.strictEqual(billRow(15).did, a.id, 'still on the bill');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'api-0038 §9 (the one lock cycle 0038 cannot rule out: tab_remove_item against a discount call on the same bill): a bill call ended by a deadlock (40P01, rolled back whole) is sent once more after a short random wait and goes through: descuento_autorizar on the bill (the same request id, one approval), × (descuento_quitar_cuenta), take one off (tab_remove_item); a second 40P01 in a row shows the usual error, nothing changed and nothing left to replay',
    run: async ({ browser }) => {
      testMenu();
      bill(16, 'Mesa Cruce');
      const pg = await till(browser);
      const dA = await deadlocks(pg, 'descuento_autorizar'), dQ = await deadlocks(pg, 'descuento_quitar_cuenta'), dR = await deadlocks(pg, 'tab_remove_item');
      const jitter = (c, i, what) => {
        const g = gap(c, i);
        assert.ok(g >= 120 && g < 1500, what + ': sent again after a short wait, not the 2-second wait for the network (' + g + ' ms)');
      };
      await openBill(pg, 16);
      /* descuento_autorizar: two deadlocks in a row: the usual error, no approval, nothing kept to replay */
      await discWindow(pg);
      let n0 = calls(pg, 'descuento_autorizar').length;
      dA.left = 2;
      await empleado(pg, 'luis', 'ana');
      await untilText(pg, '#discErr', exactly('No se pudo aprobar. Intente de nuevo.'), 10000);
      let sentA = calls(pg, 'descuento_autorizar').slice(n0);
      assert.strictEqual(sentA.length, 2, 'the call and one retry, no third');
      assert.ok(sentA[0].body.p_request_id && sentA[1].body.p_request_id === sentA[0].body.p_request_id, 'the retry is the same request id');
      assert.strictEqual(sentA[1].body.p_order_id, id(16), 'on the bill');
      jitter(dA, dA.at.length - 1, 'descuento_autorizar');
      assert.strictEqual(approvals(`bill_id = '${id(16)}'`).length, 0, 'no approval');
      assert.strictEqual(billRow(16).disc, 0, 'nothing on the bill');
      assert.ok(await pg.evaluate(() => discBillLost === null), 'nothing kept as a lost bill call (a deadlock is an answer: rolled back)');
      await quiet(pg);
      assert.strictEqual(calls(pg, 'descuento_autorizar').length - n0, 2, 'no replay afterwards');
      await pg.click('#discCancel');
      await pg.waitForSelector('#discModal', { state: 'hidden' });
      /* one deadlock: the retry goes through */
      await discWindow(pg);
      n0 = calls(pg, 'descuento_autorizar').length;
      dA.left = 1;
      await empleado(pg, 'luis', 'ana');
      await pg.waitForSelector('#discModal', { state: 'hidden', timeout: 10000 });
      await until(() => (billRow(16) || {}).disc === 2400, 8000, 'the discount on the bill');
      sentA = calls(pg, 'descuento_autorizar').slice(n0);
      assert.strictEqual(sentA.length, 2, 'the call and its retry');
      assert.strictEqual(sentA[1].body.p_request_id, sentA[0].body.p_request_id, 'the same request id');
      jitter(dA, dA.at.length - 1, 'descuento_autorizar');
      const a = approvals(`bill_id = '${id(16)}'`);
      assert.deepStrictEqual([a.length, a[0].req, a[0].ben, a[0].amount], [1, sentA[0].body.p_request_id, 'Luis', 2400], 'one approval, of that request');
      await until(async () => norm(await text(pg, '#tabTotals')).includes('Descuento₡2400·Empleado'), 8000, 'the bill window shows the discount');
      /* ×: one deadlock, the retry takes it off */
      n0 = calls(pg, 'descuento_quitar_cuenta').length;
      dQ.left = 1;
      await pg.click('#tabDiscX');
      await toastSeen(pg, ES.counts);
      assert.strictEqual(calls(pg, 'descuento_quitar_cuenta').length - n0, 2, 'the removal and its retry');
      jitter(dQ, dQ.at.length - 1, 'descuento_quitar_cuenta');
      await until(() => (billRow(16) || {}).disc === 0, 8000, 'the discount off the bill');
      assert.strictEqual(audits('discount_not_freed', a[0].id, `and details ->> 'how' = 'bill_removed'`), 1, 'taken off once');
      /* take one off: one deadlock, the retry takes it off; two in a row: the usual error, nothing taken off */
      await until(() => pg.isVisible('#tabDisc'), 8000, 'the bill window reloaded');
      n0 = calls(pg, 'tab_remove_item').length;
      dR.left = 1;
      await pg.locator('#tabLines .tline', { hasText: 'T Sandwich' }).locator('button.rm').click();
      await until(() => totalOf(16) === 4000, 8000, 'the sandwich off the bill');
      assert.strictEqual(calls(pg, 'tab_remove_item').length - n0, 2, 'the removal and its retry');
      jitter(dR, dR.at.length - 1, 'tab_remove_item');
      await until(async () => (await pg.locator('#tabLines .tline', { hasText: 'T Sandwich' }).count()) === 0, 8000, 'the bill window without the sandwich');
      n0 = calls(pg, 'tab_remove_item').length;
      dR.left = 2;
      await pg.locator('#tabLines .tline', { hasText: 'T Latte' }).locator('button.rm').click();
      await untilText(pg, '#tabErr', exactly('No se pudo guardar. Revise la conexión e intente de nuevo.'), 10000);
      await quiet(pg);
      assert.strictEqual(calls(pg, 'tab_remove_item').length - n0, 2, 'the call and one retry, no third');
      assert.strictEqual(totalOf(16), 4000, 'nothing taken off');
      assert.strictEqual(sql(`select qty from order_items where order_id = '${id(16)}' and item_name = 'T Latte'`), '2', 'both lattes still on the bill');
      assert.deepStrictEqual([dA.dead, dQ.dead, dR.dead], [3, 1, 3], 'every scripted deadlock was answered');
      assert.deepStrictEqual(pg.errors, []);
    }
  }
  ,
  {
    name: 'O-c: both replies of an Empleado on a bill lost; the codes typed again while that replay is lost too: no new attempt goes on that bill (it would answer «ya tiene un descuento» and the discount be taken back later on another screen); the line stays, the next try finds it and the bill keeps it, also after a ticket window',
    run: async ({ browser }) => {
      testMenu();
      bill(17, 'Mesa Replay');
      const pg = await till(browser);
      let drop = 0, cutReplay = 0;
      await pg.route(/rest\/v1\/rpc\/descuento_autorizar/, async (r) => {
        let b = {}; try { b = JSON.parse(r.request().postData() || '{}'); } catch (e) {}
        if (r.request().method() !== 'POST') return r.fallback();
        if (!b.p_pin && cutReplay > 0) { cutReplay--; return r.abort('failed'); }   /* a replay (no code) lost on the way */
        if (drop <= 0 || !b.p_pin) return r.fallback();
        drop--; await r.fetch(); return r.abort('failed');                          /* the server commits; the page never hears it */
      });
      await openBill(pg, 17);
      await discWindow(pg);
      drop = 2;
      await empleado(pg, 'luis', 'ana');
      await untilText(pg, '#discErr', exactly(ES.lost), 15000);
      const a = approvals(`bill_id = '${id(17)}'`)[0];
      assert.deepStrictEqual([billRow(17).disc, billRow(17).did], [2400, a.id], 'the first call committed: the discount is on the bill');
      await quiet(pg);
      /* the codes typed again on the same bill: the replay goes first, with no code, and is lost too */
      let n0 = calls(pg, 'descuento_autorizar').length;
      cutReplay = 1;
      await empleado(pg, 'luis', 'ana');
      await quiet(pg);
      let sent = calls(pg, 'descuento_autorizar').slice(n0);
      assert.strictEqual(sent.length, 1, 'only the replay: no new attempt on that bill while its lost call has no answer: ' + JSON.stringify(sent.map((c) => c.body)));
      assert.ok(sent[0].body.p_request_id === a.req && sent[0].body.p_pin == null && sent[0].body.p_employee_pin == null, 'the replay: the lost request id, no code');
      await untilText(pg, '#discErr', exactly(ES.lost));
      assert.ok(!(await seen(pg)).includes('Este pedido ya tiene un descuento. Quítelo primero.'), 'never «ya tiene un descuento»');
      assert.ok(await pg.evaluate((x) => !!discBillLost && discBillLost.order_id === x, id(17)), 'the lost call is kept, to ask again');
      /* the next try: the replay answers; the discount the bill has stays («sí quedó en la cuenta») */
      n0 = calls(pg, 'descuento_autorizar').length;
      await empleado(pg, 'luis', 'ana');
      await toastSeen(pg, ES.stayed);
      await pg.waitForSelector('#discModal', { state: 'hidden', timeout: 8000 });
      await quiet(pg);
      sent = calls(pg, 'descuento_autorizar').slice(n0);
      assert.ok(sent.length === 1 && sent[0].body.p_pin == null, 'one call, the replay: ' + JSON.stringify(sent.map((c) => c.body)));
      /* a ticket window afterwards takes nothing back */
      await pg.click('#tabClose');
      await tap(pg, 'T Latte');
      await pg.click('#discBtn');
      await pg.waitForSelector('#discModal:not([hidden])');
      await until(() => pg.evaluate(() => !!disc.st), 8000, 'the till state read');
      await quiet(pg);
      await pg.click('#discCancel');
      await quiet(pg);
      assert.strictEqual(calls(pg, 'descuento_quitar_cuenta').length, 0, 'nothing taken off the bill');
      assert.deepStrictEqual([billRow(17).disc, billRow(17).did, billRow(17).total], [2400, a.id, 5600], 'the bill keeps the discount it showed');
      assert.strictEqual(audits('discount_not_freed', a.id), 0, 'Luis\'s day not marked');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'T-d: the first call cut by the network before the server (or ended by a deadlock), Cancel at once: the retry goes with the same request id and no code; nothing approved, nothing counted, Luis\'s day free (a bill; and a ticket with a wrong code: no wrong code counted)',
    run: async ({ browser }) => {
      testMenu();
      bill(18, 'Mesa Corte');
      const pg = await till(browser);
      let plan = [];
      await pg.route(/rest\/v1\/rpc\/descuento_autorizar/, async (r) => {
        let b = {}; try { b = JSON.parse(r.request().postData() || '{}'); } catch (e) {}
        if (r.request().method() !== 'POST' || !b.p_pin || !plan.length) return r.fallback();
        const step = plan.shift();
        await step.gate.wait;                              /* held until the test has tapped Cancel */
        if (step.how === 'cut') return r.abort('failed');  /* it never reaches the server */
        return r.fulfill({ status: 500, contentType: 'application/json',
          body: JSON.stringify({ code: '40P01', message: 'deadlock detected', details: null, hint: null }) });
      });
      const wrong0 = Number(sql(`select count(*) from audit_log where action = 'discount_code_wrong'`));
      const cancelled = async (how, start) => {
        const g = gate(); plan.push({ how, gate: g });
        const n0 = calls(pg, 'descuento_autorizar').length;
        await start();
        await until(() => calls(pg, 'descuento_autorizar').length > n0, 5000, 'the first call sent');
        await pg.click('#discCancel');
        await pg.waitForSelector('#discModal', { state: 'hidden' });
        g.open();
        await until(() => calls(pg, 'descuento_autorizar').length - n0 === 2, 6000, 'the page\'s own retry');
        await quiet(pg);
        const sent = calls(pg, 'descuento_autorizar').slice(n0);
        assert.strictEqual(sent.length, 2, how + ': the call and its one retry');
        assert.strictEqual(sent[1].body.p_request_id, sent[0].body.p_request_id, how + ': the same request id');
        assert.ok(sent[1].body.p_pin == null && sent[1].body.p_employee_pin == null, how + ': after Cancel the retry carries no code: ' + JSON.stringify(sent[1].body));
        assert.deepStrictEqual(Object.values(PINS).filter((c) => JSON.stringify(sent[1].body).includes(c)), [], how + ': no code anywhere in it');
        return sent;
      };
      /* (A) a bill, Empleado: the first call cut, Cancel */
      await openBill(pg, 18);
      await discWindow(pg);
      await cancelled('cut', () => empleado(pg, 'luis', 'ana'));
      /* (B) the same bill: the first call ended by a deadlock (40P01), Cancel */
      await discWindow(pg);
      await cancelled('deadlock', () => empleado(pg, 'luis', 'ana'));
      assert.strictEqual(approvals(`beneficiary_id = '${STAFF.luis}'`).length, 0, 'nothing approved for Luis');
      assert.deepStrictEqual([billRow(18).disc, billRow(18).did], [0, null], 'nothing on the bill');
      assert.strictEqual(calls(pg, 'descuento_quitar_cuenta').length, 0, 'nothing to take back');
      /* Luis's day is free: his Empleado on the bill is approved */
      await empleadoOnBill(pg, 18, 'luis', 'ana');
      await pg.click('#tabClose');
      /* (C) a ticket: Local with a wrong code, the first call cut, Cancel: the code is never tested */
      await tap(pg, 'T Latte');
      await pg.click('#discBtn');
      await pg.waitForSelector('#discModal:not([hidden])');
      await until(() => pg.evaluate(() => !!disc.st), 8000, 'the till state read');
      await cancelled('cut', async () => { await pg.click('[data-cat="local"]'); await padType(pg, '0000'); await pg.click('#discGo'); });
      assert.strictEqual(Number(sql(`select count(*) from audit_log where action = 'discount_code_wrong'`)), wrong0, 'no wrong code counted on the till');
      assert.ok(await pg.evaluate(() => !tDisc), 'nothing on the ticket');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'O-c, two tablets: both replies of Local on a bill lost on tablet 1; tablet 2 takes it off with × and authorizes Huésped (the same ₡800); tablet 1 back online: its replay finds the old Local and takes back only that one (p_discount_id answers not_on_bill): tablet 2\'s Huésped stays',
    run: async ({ browser }) => {
      testMenu();
      bill(19, 'Mesa Dos Tabletas');
      const t1 = await till(browser), t2 = await till(browser);
      let drop = 0;
      await t1.route(/rest\/v1\/rpc\/descuento_autorizar/, async (r) => {
        let b = {}; try { b = JSON.parse(r.request().postData() || '{}'); } catch (e) {}
        if (r.request().method() !== 'POST' || drop <= 0 || !b.p_pin) return r.fallback();
        drop--; await r.fetch(); return r.abort('failed');
      });
      await openBill(t1, 19);
      await discWindow(t1);
      drop = 2;
      await t1.click('[data-cat="local"]'); await padType(t1, PINS.ana); await t1.click('#discGo');
      await untilText(t1, '#discErr', exactly(ES.lost), 15000);
      const x = approvals(`bill_id = '${id(19)}'`)[0];
      assert.deepStrictEqual([billRow(19).disc, billRow(19).did], [800, x.id], 'Local X is on the bill');
      await t1.click('#discCancel');
      await quiet(t1);
      await t1.context().setOffline(true);
      await until(() => t1.evaluate(() => !navigator.onLine), 5000, 'tablet 1 offline');
      /* tablet 2: × (nothing paid: no PIN), then Huésped */
      await openBill(t2, 19);
      await until(() => t2.isVisible('#tabDiscX'), 8000, 'the discount\'s × on tablet 2');
      await t2.click('#tabDiscX');
      await until(() => (billRow(19) || {}).disc === 0, 8000, 'X taken off');
      await until(() => t2.isVisible('#tabDisc'), 8000, 'Descuento offered again');
      await discWindow(t2);
      await t2.click('[data-cat="huesped"]'); await padType(t2, PINS.ana); await t2.click('#discGo');
      await t2.waitForSelector('#discModal', { state: 'hidden', timeout: 10000 });
      await until(() => { const b = billRow(19); return b.disc === 800 && b.did && b.did !== x.id; }, 8000, 'Huésped Y on the bill');
      const y = billRow(19).did;
      /* tablet 1 back online: the replay (X's request, no code), then the take-back of X only */
      const n0 = calls(t1, 'descuento_quitar_cuenta').length;
      const back = t1.waitForResponse((r) => /rpc\/descuento_quitar_cuenta/.test(r.url()), { timeout: 10000 });
      await t1.context().setOffline(false);
      const ans = await (await back).json();
      await quiet(t1);
      const sent = calls(t1, 'descuento_quitar_cuenta').slice(n0);
      assert.strictEqual(sent.length, 1, 'one take-back');
      assert.strictEqual(sent[0].body.p_discount_id, x.id, 'it names the late approval X');
      assert.deepStrictEqual(ans, { ok: false, error: 'not_on_bill' }, 'the bill no longer carries X: nothing taken off');
      const b = billRow(19);
      assert.deepStrictEqual([b.did, b.disc, b.total, b.reason], [y, 800, 7200, 'Hotel guest'], 'tablet 2\'s Huésped stays on the bill');
      assert.ok(!(await seen(t1)).includes(ES.late), 'tablet 1 does not tell staff a late discount stayed: ' + JSON.stringify(await seen(t1)));
      assert.deepStrictEqual(t1.errors.concat(t2.errors), []);
    }
  },
  {
    name: 'a ticket with Local; «Agregar» to a bill that is paid on another device meanwhile: the item tapped is not merged into the discounted ticket (its lines stay locked), the message says so, and the sale records the approved discount, verified',
    run: async ({ browser }) => {
      testMenu();
      bill(20, 'Mesa Pagada');
      const pg = await till(browser);
      await tap(pg, 'T Latte');
      await pg.click('#discBtn');
      await pg.waitForSelector('#discModal:not([hidden])');
      await until(() => pg.evaluate(() => !!disc.st), 8000, 'the till state read');
      await pg.click('[data-cat="local"]'); await padType(pg, PINS.ana); await pg.click('#discGo');
      await pg.waitForSelector('#discModal', { state: 'hidden', timeout: 10000 });
      const appr = await until(() => pg.evaluate(() => tDisc && tDisc.id), 8000, 'Local on the ticket');
      /* «Agregar» on the bill; a sandwich tapped for it; the bill is paid on another device meanwhile */
      await openBill(pg, 20);
      await pg.click('#tabAdd');
      await pg.waitForSelector('#addBar:not([hidden])');
      await tap(pg, 'T Sandwich');
      const paid = await rpc('tab_pay', { p_order_id: id(20), p_method: 'card', p_lines: null, p_amount: null, p_station: 'Caja 2', p_expect: totalOf(20) });
      assert.ok(paid.ok, 'the bill paid on another device: ' + JSON.stringify(paid));
      await pg.click('#addGo');
      await toastSeen(pg, ES.notAdded);
      const t = await pg.evaluate(() => ({ lines: ticket.map((l) => l.name + '×' + l.qty), disc: tDisc && tDisc.id }));
      assert.deepStrictEqual(t, { lines: ['T Latte×1'], disc: appr }, 'the ticket as authorized: the sandwich not merged into it, the discount kept');
      await pg.fill('#forWho', 'Venta Bloqueada');
      await pg.click('[data-pay="card"]');
      await until(async () => (await pg.isVisible('#numModal')) || (await pg.evaluate(() => !pendingPay)), 5000, 'the number window or the sale');
      if (await pg.isVisible('#numModal')) await pg.click('#numNone');
      const o = await until(() => sqlJson(`select json_build_object('sub', subtotal_crc, 'disc', discount_crc, 'total', total_crc, 'did', discount_id,
          'by', discount_by, 'flags', flags) from orders where guest_name = 'Venta Bloqueada'`), 10000, 'the sale recorded');
      assert.deepStrictEqual([o.sub, o.disc, o.total, o.did, o.by], [2000, 200, 1800, appr, 'Ana'], 'the approved Local, linked');
      assert.deepStrictEqual((o.flags || []).filter((f) => /discount/.test(f)), [], 'verified: no discount_not_verified');
      assert.deepStrictEqual(pg.errors, []);
    }
  }
];
