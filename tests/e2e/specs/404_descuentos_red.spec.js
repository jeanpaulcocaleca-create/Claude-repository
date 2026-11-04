/* The POS discounts of migration 0038 on a bad network, offline and in races, on the ticket (pos.html #discModal):
   proposal-final.md §5.2 O-a (offline: the window refuses, a connection lost between the steps applies nothing, an
   approval carried by a sale queued offline is linked on reconnect and never let go, also across a reload), O-b (a lost
   reply: the retry with the same request id gets the same approval; both replies lost: nothing on the ticket and the
   approval let go by its request id on reconnect, or before the next attempt while the browser still says online (W6),
   or when the window opens again with descuento_estado, or on the next load), R-a (two sign-ins at once on Empleado for
   Luis), R-b (a void in Orders by Ana, then Empleado again with «Segundo descuento…»), R-c (one attempt sent twice at
   once with the same request id, Empleado and Local; and the page's own retry arriving while the first call is still
   running on the server) and T-d for the ticket (Cancel, the same or another category tapped, or a reopen while
   descuento_autorizar is held: the late approval never reaches the ticket and is let go with descuento_liberar).
   Also: without a discount the POS sells online and offline exactly as before, and the server never refuses money (a
   queued sale whose approval expired on the server meanwhile is accepted, linked and flagged).
   Sources: proposal-final.md §3.3, §3.4 and §5.2; mecanismo-intentos.md §13.3 (tills); build-plan.md L1 (no
   descuento_caja_cerrar), L4 (the daily quota); decisiones-dueno.md adjustment 3; api-0038.md §4.2 (replays, the
   backstops, no 23505), §4.3 (descuento_liberar) and §5 (_order_discount_check never refuses a category sale).
   Seed codes: Ana manager 4826, Luis staff 5284, Marta staff 6173, Dueño owner 7391 (tests/db/90_seed.sql). */
'use strict';
const assert = require('assert');
const crypto = require('crypto');
const { spawn } = require('child_process');
const { page, goto, until, sql, sqlJson, openRegister, registerTill, STAFF, PINS } = require('../lib');

const API = 'http://127.0.0.1:' + (Number(process.env.E2E_SITE_PORT || 8090) + 1000);
const ITEM = { latte: 'b0000000-0000-4000-8000-0000000404a1', brownie: 'b0000000-0000-4000-8000-0000000404a2' };

/* the Spanish the pages show (website/lang.js) */
const ES = {
  offline: 'Un descuento necesita internet para revisar los códigos.',
  net: 'No se pudo revisar los códigos. Revise la conexión.',
  daily: 'Descuento diario ya utilizado',
  pending: (s, t) => `Sin usar todavía en ${s}: se libera a las ${t}.`,
  prior: (n, m) => `Segundo descuento de empleado hoy para ${n}: el anterior lo anuló ${m}.`,
  approvedBy: (n) => `Descuento aprobado por ${n}`,
  pick: 'Elija el descuento', emp: 'Código de empleado', mgr: 'Código de encargado',
  rowEmp: (n) => `Descuento Empleado · ${n}`, rowLocal: 'Descuento Local',
  chipOffline: (n) => `sin conexión · ${n} en este dispositivo`
};

/* ---------- helpers ---------- */
const norm = (s) => String(s || '').replace(/[  ]/g, ' ').replace(/\s+/g, ' ').trim();
const text = async (pg, sel) => norm(await pg.textContent(sel));
const see = (pg, sel, want, ms) => until(async () => {
  const t = await text(pg, sel);
  return want instanceof RegExp ? want.test(t) : t === want;
}, ms || 8000, sel + ' to read «' + want + '»').catch(async (e) => { e.message += ' (it reads «' + (await text(pg, sel)) + '»)'; throw e; });
const pinIn = (s, pin) => new RegExp('(^|[^0-9a-f-])' + pin + '([^0-9a-f-]|$)', 'i').test(String(s || ''));
const anyPin = (s) => Object.values(PINS).filter((p) => pinIn(s, p));
function gate() { let open; const wait = new Promise((r) => { open = r; }); return { wait, open }; }
const uuid = () => crypto.randomUUID();

function testMenu() {
  sql(`insert into menu_categories (id, name, sort, kitchen) values ('b0000000-0000-4000-8000-0000000404c1', 'Test Bar 404', 0, false);
       insert into menu_items (id, category_id, name, price_crc, sort, available) values
         ('${ITEM.latte}', 'b0000000-0000-4000-8000-0000000404c1', 'T Latte', 2000, 1, true),
         ('${ITEM.brownie}', 'b0000000-0000-4000-8000-0000000404c1', 'T Brownie', 1500, 2, true);`);
}

/* every request the page sends to the API (the rpc name, its body, when), and every answer of a descuento_* function */
function watch(pg) {
  pg.rpcs = []; pg.answers = []; pg.inflight = 0;
  const api = (r) => r.url().startsWith(API);
  pg.on('request', (r) => {
    if (!api(r)) return;
    pg.inflight++;
    const m = r.url().match(/\/rest\/v1\/rpc\/([a-z_0-9]+)/);
    let b = {}; try { b = JSON.parse(r.postData() || '{}'); } catch (e) {}
    pg.rpcs.push({ fn: m ? m[1] : null, url: r.url(), raw: r.postData() || '', body: b, t: Date.now() });
  });
  pg.on('requestfinished', (r) => { if (api(r)) pg.inflight--; });
  pg.on('requestfailed', (r) => { if (api(r)) pg.inflight--; });
  pg.on('response', async (resp) => {
    const m = resp.url().match(/\/rest\/v1\/rpc\/(descuento_[a-z_]+)/);
    if (!m) return;
    const rec = { fn: m[1], status: resp.status(), body: null, req: null, t: Date.now() };
    try { rec.req = JSON.parse(resp.request().postData() || '{}'); } catch (e) {}
    pg.answers.push(rec);
    try { rec.body = await resp.json(); } catch (e) {}
  });
}
const sent = (pg, fn, from) => pg.rpcs.slice(from || 0).filter((r) => r.fn === fn);
const answered = (pg, fn) => pg.answers.filter((a) => a.fn === fn);
/* the answers of fn that came after a moment, once their bodies are read */
async function answers(pg, fn, after) {
  const l = () => pg.answers.filter((a) => a.fn === fn && a.t >= (after || 0));
  await until(() => l().length > 0 && l().every((a) => a.body !== null), 5000, 'the answers of ' + fn);
  return l().map((a) => a.body);
}
/* no request of the page on its way, three polls in a row */
async function quiet(pg) { let calm = 0; await until(() => { calm = pg.inflight <= 0 ? calm + 1 : 0; return calm >= 3; }, 15000, 'no request in flight'); }
/* proposal §5.2 C-a (340's watcher): a code goes only in descuento_autorizar, never empty there; nothing else carries one
   (but the functions that take a manager's PIN by design, as before 0038: a void in Orders) */
const PIN_BY_DESIGN = ['manager_void_order'];
function noCodeLeak(pg) {
  for (const r of pg.rpcs) {
    if (PIN_BY_DESIGN.includes(r.fn)) continue;
    if (r.fn === 'descuento_autorizar') {
      assert.ok(r.body.p_pin == null || /^\d{4,8}$/.test(r.body.p_pin), 'p_pin is a typed code, never empty: ' + r.raw);
      assert.ok(r.body.p_employee_pin == null || /^\d{4,8}$/.test(r.body.p_employee_pin), 'p_employee_pin never empty: ' + r.raw);
      continue;
    }
    assert.deepStrictEqual(anyPin(r.url + ' ' + r.raw), [], 'a code in a request other than descuento_autorizar: ' + r.fn + ' ' + r.raw.slice(0, 300));
  }
}

/* the network between the page and one database function, scripted: each POST takes the next action of c.plan (or
   c.dflt when the plan is empty): 'pass'; 'cut' (never reaches the server); 'drop' (the server answers, the reply is
   lost); 'dropOffline' (the same, and the device loses the connection as the reply is lost); 'hold' (the server
   answers, the reply waits for its gate); 'holdDrop' (the same, then the reply is lost); 'wait' (waits for its gate
   before reaching the server); or a function */
async function wire(pg, fn) {
  const c = { plan: [], dflt: 'pass', lost: [], held: [], n: 0 };
  await pg.route(new RegExp('/rest/v1/rpc/' + fn + '(\\?|$)'), async (r) => {
    if (r.request().method() !== 'POST') return r.fallback();
    const act = c.plan.length ? c.plan.shift() : c.dflt;
    c.n++;
    let body = {}; try { body = JSON.parse(r.request().postData() || '{}'); } catch (e) {}
    try {
      if (typeof act === 'function') return await act(r, body);
      if (act === 'cut') return await r.abort('failed');
      if (act === 'drop' || act === 'dropOffline') {
        const resp = await r.fetch();
        c.lost.push(await resp.json());
        if (act === 'dropOffline') await pg.context().setOffline(true);
        return await r.abort('failed');
      }
      if (act === 'holdDrop') {   /* the server answers, the reply waits for its gate and is then lost */
        const resp = await r.fetch();
        const g = gate(); c.held.push({ answer: await resp.json(), body, open: g.open });
        await g.wait;
        return await r.abort('failed');
      }
      if (act === 'hold') {
        const resp = await r.fetch();
        const g = gate(); c.held.push({ answer: await resp.json(), body, open: g.open });
        await g.wait;
        return await r.fulfill({ response: resp });
      }
      if (act === 'wait') {
        const g = gate(); c.held.push({ body, open: g.open });
        await g.wait;
        return await r.fallback();
      }
      return await r.fallback();
    } catch (e) { return undefined; }   /* the page went away meanwhile (a reload) */
  });
  return c;
}

/* what the page showed in its toast, each text once it changed (so the Spanish lang.js puts in is kept) */
async function toasts(pg) {
  await pg.evaluate(() => {
    window.__seen = [];
    const t = document.getElementById('toast');
    new MutationObserver(() => { const s = t.textContent; if (s && window.__seen[window.__seen.length - 1] !== s) window.__seen.push(s); })
      .observe(t, { childList: true, characterData: true, subtree: true });
  });
}
const seenToasts = (pg) => pg.evaluate(() => (window.__seen || []).map((s) => s.replace(/[  ]/g, ' ')));
const toastSeen = (pg, s, ms) => until(async () => (await seenToasts(pg)).includes(s), ms || 8000, 'the message «' + s + '»')
  .catch(async (e) => { e.message += ' (seen: ' + JSON.stringify(await seenToasts(pg)) + ')'; throw e; });

/* the till: the POS signed in with the café login (Spanish), the register open, its 20-second queue retry and live poll off
   (the test decides when it sends), registered for discounts as a manager does it (lib.registerTill) */
async function till(browser, opts) {
  opts = Object.assign({ login: 'cafe', lang: 'es', viewport: { width: 1180, height: 820 }, station: { name: 'Caja', main: true } }, opts || {});
  openRegister();
  const pg = await page(browser, opts);
  watch(pg);
  await pg.addInitScript(() => {
    const si = window.setInterval;
    window.setInterval = function (fn, ms) { return ms === 20000 ? 0 : si.apply(this, arguments); };
  });
  await goto(pg, '/pos');
  await ready(pg);
  if (opts.register !== false) pg.till = await registerTill(pg, { station: opts.station.name });
  return pg;
}
/* a second tab of the till on the same device (the same browser context: one storage, one sign-in), as the queue's
   own «storage» listener supports */
async function secondTab(A) {
  const B = await page(A.context().browser(), { context: A.context(), lang: 'es' });
  watch(B);
  await B.addInitScript(() => {
    const si = window.setInterval;
    window.setInterval = function (fn, ms) { return ms === 20000 ? 0 : si.apply(this, arguments); };
  });
  await goto(B, '/pos');
  await ready(B);
  return B;
}
async function ready(pg) {
  await pg.waitForSelector('#appView:not([hidden])', { timeout: 15000 });
  await pg.waitForFunction(() => document.querySelectorAll('.pbtn').length > 0, null, { timeout: 15000 });
  if (await pg.isVisible('#dayModal')) await pg.click('#dayClose');
  if (await pg.isVisible('#stationModal')) await pg.click('#stationForm button[type=submit]');
  await pg.evaluate(() => clearInterval(liveTimer));
  await toasts(pg);
  await pg.waitForLoadState('networkidle');
}
/* tap a product, whichever tab of the menu it is under */
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
async function typeCode(pg, code) { for (const d of code) await pg.click(`#discPad button[data-k="${d}"]`); }
async function openWin(pg) {
  await pg.click('#discBtn');
  await pg.waitForSelector('#discModal:not([hidden])', { timeout: 5000 });
  await pg.waitForFunction(() => window.disc && disc.st, null, { timeout: 8000 });   /* the till's state has come back */
}
async function closeWin(pg) {
  await pg.click('#discCancel');
  await pg.waitForSelector('#discModal', { state: 'hidden', timeout: 5000 });
}
async function cat(pg, c) {
  await pg.click(`#discForm [data-cat="${c}"]`);
  await until(() => pg.evaluate((x) => document.querySelector(`#discForm [data-cat="${x}"]`).classList.contains('on'), c), 3000, c + ' selected');
}
/* Empleado: the employee's code, Autorizar (it continues), the manager's code; Autorizar is tapped by the caller unless go */
async function empleado(pg, emp, mgr, go) {
  await cat(pg, 'empleado');
  await see(pg, '#discStep', ES.emp);
  await typeCode(pg, PINS[emp]);
  await pg.click('#discGo');
  await see(pg, '#discStep', ES.mgr);
  await typeCode(pg, PINS[mgr]);
  if (go !== false) await pg.click('#discGo');
}
async function local(pg, mgr, go) {
  await cat(pg, 'local');
  await see(pg, '#discStep', ES.mgr);
  await typeCode(pg, PINS[mgr]);
  if (go !== false) await pg.click('#discGo');
}
const closed = (pg) => pg.waitForSelector('#discModal', { state: 'hidden', timeout: 10000 });
async function charge(pg, sel) {
  await pg.click(sel || '[data-pay="card"]');
  await until(async () => (await pg.isVisible('#numModal')) || (await pg.evaluate(() => !pendingPay)), 5000, 'the number window or the sale');
  if (await pg.isVisible('#numModal')) await pg.click('#numNone');
}
async function goOffline(pg) {
  await pg.waitForLoadState('networkidle');   /* the page's own reads answered first (lib.settle) */
  await pg.context().setOffline(true);
  await until(() => pg.evaluate(() => !navigator.onLine), 5000, 'offline');
}
async function goOnline(pg) {
  await pg.context().setOffline(false);
  await until(() => pg.evaluate(() => navigator.onLine), 5000, 'online');
}
const stored = (pg, key) => pg.evaluate((k) => { try { return JSON.parse(localStorage.getItem(k) || 'null'); } catch (e) { return 'unreadable'; } }, key);
const queued = async (pg) => (await stored(pg, 'hg-pos-queue')) || [];
const holds = async (pg) => (await stored(pg, 'hg-pos-disc-hold')) || [];
const tDiscId = (pg) => pg.evaluate(() => (window.tDisc ? tDisc.id : null));

/* the category approvals on the server */
const approvals = (where) => sqlJson(`select coalesce(json_agg(json_build_object('id', id, 'cat', category, 'ben', beneficiary_name,
    'order', order_id, 'used', used_at is not null, 'freed', freed_how, 'req', request_id, 'station', station, 'by', approved_name,
    'amount', amount_crc, 'sub', subtotal_crc) order by created_at), '[]'::json)
  from discount_approvals where category is not null ${where ? 'and ' + where : ''}`);
/* the order a sale made on the server, by the name typed for it */
const orderBy = (who) => sqlJson(`select json_build_object('id', id, 'total', total_crc, 'sub', subtotal_crc, 'disc', discount_crc,
    'did', discount_id, 'reason', discount_reason, 'by', discount_by, 'flags', flags, 'notes', notes, 'voided', voided_at is not null,
    'lines', (select count(*) from order_items i where i.order_id = o.id))
  from orders o where guest_name = '${who}'`);
const audits = (action, where) => Number(sql(`select count(*) from audit_log where action = '${action}' ${where ? 'and ' + where : ''}`));
/* {t} of the pending line: the approval's created_at + 30 minutes, rounded up to the minute, HH:MM in Costa Rica (UTC−6) */
function crHHMM(epochSeconds) {
  const d = new Date(Math.ceil(epochSeconds * 1000 / 60000) * 60000 - 6 * 3600000);
  return String(d.getUTCHours()).padStart(2, '0') + ':' + String(d.getUTCMinutes()).padStart(2, '0');
}

/* checks whose failure is reported but does not stop the scenario: the later checks still run */
function softly() {
  const fails = [];
  const check = (ok, msg) => { if (!ok) fails.push(msg); return ok; };
  check.done = () => assert.deepStrictEqual(fails, [], 'failed checks:\n  - ' + fails.join('\n  - '));
  return check;
}

module.exports.tests = [
  {
    name: 'N: without a discount the POS sells exactly as before: a sale recorded at once online, a sale rung offline kept on the device and uploaded once on reconnect; no discount field is sent and no descuento_* request is made',
    run: async ({ browser }) => {
      testMenu();
      const pg = await till(browser);
      /* online */
      await tap(pg, 'T Latte'); await tap(pg, 'T Brownie');
      await pg.fill('#forWho', 'Sin descuento uno');
      await charge(pg);
      await until(() => (orderBy('Sin descuento uno') || {}).lines === 2, 10000, 'the online sale recorded with its two lines');
      /* offline */
      await goOffline(pg);
      await tap(pg, 'T Latte'); await tap(pg, 'T Brownie');
      await pg.fill('#forWho', 'Sin descuento dos');
      await charge(pg, '[data-pay="sinpe"]');
      await until(async () => (await queued(pg)).length === 1, 5000, 'the sale kept on the device');
      await see(pg, '#netChip', ES.chipOffline(1));
      assert.strictEqual(orderBy('Sin descuento dos'), null, 'nothing reached the server while offline');
      await goOnline(pg);
      await until(() => (orderBy('Sin descuento dos') || {}).lines === 2, 15000, 'the queued sale uploaded on reconnect');
      await until(async () => (await queued(pg)).length === 0, 8000, 'the queue emptied');
      await pg.evaluate(() => syncQueue());
      await quiet(pg);
      assert.strictEqual(sql(`select count(*) from orders where guest_name like 'Sin descuento%'`), '2', 'each sale saved exactly once');
      for (const [who, method] of [['Sin descuento uno', 'card'], ['Sin descuento dos', 'sinpe']]) {
        const o = orderBy(who);
        assert.deepStrictEqual([o.total, o.sub, o.disc, o.did, o.reason, o.by, (o.flags || []).filter((f) => /discount/.test(f)), o.notes],
          [3500, null, 0, null, null, null, [], null], 'a sale without a discount, as before 0038: ' + who + ' ' + JSON.stringify(o));
        assert.strictEqual(sql(`select payment_method from orders where id = '${o.id}'`), method);
      }
      const saves = sent(pg, 'pos_record_sale');
      assert.ok(saves.length >= 2, 'each sale went up through pos_record_sale');
      for (const s of saves) {
        const o = s.body.p_order || {};
        assert.deepStrictEqual(['subtotal_crc', 'discount_crc', 'discount_id', 'discount_note', 'disc_reason'].filter((k) => k in o), [],
          'no discount field in the upload of a sale without a discount: ' + s.raw.slice(0, 300));
        assert.strictEqual(o.total_crc, 3500);
      }
      assert.deepStrictEqual(pg.rpcs.filter((r) => /^descuento_/.test(r.fn || '')).map((r) => r.fn), [],
        'a sale without a discount asks nothing of the discount functions (no state, no release)');
      noCodeLeak(pg);
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'O-a: offline the window refuses (its text, no window, no request); the connection lost between the steps (Empleado step 2, Local) applies nothing; back online the same window approves',
    run: async ({ browser }) => {
      testMenu();
      const pg = await till(browser);
      await tap(pg, 'T Latte'); await tap(pg, 'T Brownie');
      /* the window refuses */
      await goOffline(pg);
      const n0 = pg.rpcs.length;
      await pg.click('#discBtn');
      await toastSeen(pg, ES.offline);
      assert.ok(await pg.isHidden('#discModal'), 'the window does not open offline');
      await goOnline(pg);
      await quiet(pg);
      assert.deepStrictEqual(pg.rpcs.slice(n0).filter((r) => /^descuento_/.test(r.fn || '')).map((r) => r.fn), [],
        'nothing asked of the server for the refused window');
      /* Empleado: the employee's code taken online (nothing sent at step 1), then the connection goes */
      await openWin(pg);
      await empleado(pg, 'luis', 'ana', false);
      assert.strictEqual(sent(pg, 'descuento_autorizar').length, 0, 'nothing sent at the employee step');
      await goOffline(pg);
      await pg.click('#discGo');
      await see(pg, '#discErr', ES.offline);
      assert.ok(await pg.isVisible('#discModal'), 'the window stays open');
      /* Local, still offline */
      await local(pg, 'ana');
      await see(pg, '#discErr', ES.offline);
      assert.strictEqual(sent(pg, 'descuento_autorizar').length, 0, 'no code sent while offline');
      assert.strictEqual(await tDiscId(pg), null, 'nothing on the ticket');
      assert.ok(await pg.isHidden('#discRow'), 'no discount row');
      await see(pg, '#totalAmt', '₡3 500');
      assert.deepStrictEqual(approvals(), [], 'no approval made on the server');
      assert.strictEqual(audits('discount_code_wrong'), 0, 'nothing counted');
      /* back online: the same window approves (Local tapped again starts it again) */
      await goOnline(pg);
      await local(pg, 'ana');
      await closed(pg);
      await see(pg, '#discLbl', ES.rowLocal);
      await see(pg, '#totalAmt', '₡3 150');
      const a = approvals();
      assert.strictEqual(a.length, 1, 'one approval, made after the connection returned');
      assert.strictEqual(sent(pg, 'descuento_autorizar').length, 1, 'one call, after the connection returned');
      assert.strictEqual(await tDiscId(pg), a[0].id);
      noCodeLeak(pg);
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'O-a (money 2): Empleado approved online, then offline: the sale is queued carrying it (the hold cleared in the same step); on reconnect it is uploaded and linked, never let go',
    run: async ({ browser }) => {
      testMenu();
      const pg = await till(browser);
      await tap(pg, 'T Latte'); await tap(pg, 'T Brownie');
      await openWin(pg);
      await empleado(pg, 'luis', 'ana');
      await closed(pg);
      await see(pg, '#discLbl', ES.rowEmp('Luis'));
      await see(pg, '#totalAmt', '₡2 450');
      const [ap] = approvals();
      assert.deepStrictEqual((await holds(pg)).map((h) => h.id), [ap.id], 'the approval on the ticket is held on the device');
      await goOffline(pg);
      await pg.fill('#forWho', 'Cola Luis');
      await charge(pg);
      await until(async () => (await queued(pg)).length === 1, 5000, 'the sale queued');
      const q = (await queued(pg))[0];
      assert.deepStrictEqual([q.total_crc, q.subtotal_crc, q.discount_crc, q.discount_id], [2450, 3500, 1050, ap.id], 'the queued sale carries the approval');
      assert.deepStrictEqual(await holds(pg), [], 'the hold cleared in the same step as the sale was queued');
      await see(pg, '#netChip', ES.chipOffline(1));
      assert.strictEqual(orderBy('Cola Luis'), null, 'nothing on the server yet');
      assert.deepStrictEqual([approvals()[0].order, approvals()[0].freed], [null, null], 'the approval waits, not let go');
      await goOnline(pg);
      await until(() => (orderBy('Cola Luis') || {}).did === ap.id, 15000, 'the queued sale uploaded and linked');
      await until(async () => (await queued(pg)).length === 0, 8000, 'the queue emptied');
      await quiet(pg);
      const o = orderBy('Cola Luis'), a = approvals()[0];
      assert.deepStrictEqual([o.total, o.sub, o.disc, o.reason, o.by], [2450, 3500, 1050, 'Employee', 'Ana'], 'linked as approved: ' + JSON.stringify(o));
      assert.deepStrictEqual((o.flags || []).filter((f) => /discount/.test(f)), [], 'no flag: verified, in time');
      assert.deepStrictEqual([a.order, a.used, a.freed], [o.id, true, null], 'the approval used by this sale, never freed');
      assert.strictEqual(sent(pg, 'descuento_liberar').length, 0, 'no descuento_liberar request at any moment');
      assert.strictEqual(audits('discount_released'), 0);
      noCodeLeak(pg);
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'O-a: a reload with the sale still queued (its upload not through yet) lets nothing go, even with an earlier load\'s hold naming that approval; the sale then goes up linked',
    run: async ({ browser }) => {
      testMenu();
      const pg = await till(browser);
      const rec = await wire(pg, 'pos_record_sale');
      await tap(pg, 'T Latte'); await tap(pg, 'T Brownie');
      await openWin(pg);
      await local(pg, 'ana');
      await closed(pg);
      await see(pg, '#discLbl', ES.rowLocal);
      const [ap] = approvals();
      const reqId = sent(pg, 'descuento_autorizar').pop().body.p_request_id;
      await goOffline(pg);
      await pg.fill('#forWho', 'Cola Recarga');
      await charge(pg);
      await until(async () => (await queued(pg)).length === 1, 5000, 'the sale queued');
      assert.deepStrictEqual(await holds(pg), [], 'the hold cleared in the same step');
      /* the connection returns, but the sale's upload does not get through yet */
      rec.dflt = 'cut';
      await goOnline(pg);
      await until(() => rec.n > 0, 8000, 'the upload tried on reconnect');
      await quiet(pg);
      assert.strictEqual((await queued(pg)).length, 1, 'still queued');
      /* a hold an earlier load of the page left naming that approval (proposal §3.4: on load only holds no queued sale carries are let go) */
      await pg.evaluate(([id, rid]) => localStorage.setItem('hg-pos-disc-hold', JSON.stringify([{ id, request_id: rid, at: Date.now() - 60000, load: 'an-earlier-load' }])), [ap.id, reqId]);
      const n0 = pg.rpcs.length, tries = rec.n;
      await pg.reload({ waitUntil: 'domcontentloaded' });
      await ready(pg);
      await until(() => rec.n > tries, 15000, 'the queued sale tried again after the reload');
      await pg.evaluate(() => discRelChain.then(() => true));   /* the load's own release round has run */
      await quiet(pg);
      assert.strictEqual(sent(pg, 'descuento_liberar', n0).length, 0, 'the reload let nothing go: ' + JSON.stringify(sent(pg, 'descuento_liberar', n0).map((r) => r.body)));
      assert.deepStrictEqual(await holds(pg), [], 'the hold the queued sale carries is dropped, not let go');
      assert.strictEqual((await queued(pg)).length, 1, 'the sale still queued after the reload');
      assert.deepStrictEqual([approvals()[0].order, approvals()[0].freed], [null, null], 'the approval waits for its sale, not freed');
      /* the upload gets through */
      rec.dflt = 'pass';
      await pg.evaluate(() => syncQueue());
      await until(() => (orderBy('Cola Recarga') || {}).did === ap.id, 15000, 'the sale linked');
      await until(async () => (await queued(pg)).length === 0, 8000, 'the queue emptied');
      await quiet(pg);
      const o = orderBy('Cola Recarga'), a = approvals()[0];
      assert.deepStrictEqual([o.total, o.sub, o.disc, o.reason, o.by], [3150, 3500, 350, 'Local', 'Ana']);
      assert.deepStrictEqual([a.order, a.used, a.freed], [o.id, true, null], 'linked, never freed');
      assert.strictEqual(sent(pg, 'descuento_liberar').length, 0, 'no descuento_liberar at any moment');
      noCodeLeak(pg);
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'money: a sale queued offline whose approval expired on the server meanwhile (another till approved Luis again) is accepted when it goes up: linked, the money as charged, flagged discount_late and discount_daily_twice; the queue empties',
    run: async ({ browser }) => {
      testMenu();
      const A = await till(browser, { station: { name: 'Caja A', main: true } });
      await tap(A, 'T Latte'); await tap(A, 'T Brownie');
      await openWin(A);
      await empleado(A, 'luis', 'ana');
      await closed(A);
      await see(A, '#discLbl', ES.rowEmp('Luis'));
      const [x] = approvals();
      await goOffline(A);
      await A.fill('#forWho', 'Venta Vencida');
      await charge(A);
      await until(async () => (await queued(A)).length === 1, 5000, 'the sale queued on A');
      /* the approval is 40 minutes old on the server by the time A's sale can go up (as test.back moves the audit rows) */
      sql(`update discount_approvals set created_at = created_at - interval '40 minutes' where id = '${x.id}'`);
      /* B, another registered till: Luis's unused approval has expired, so he is approved again there */
      const B = await till(browser, { station: { name: 'Caja B', main: true } });
      await tap(B, 'T Latte'); await tap(B, 'T Brownie');
      await openWin(B);
      await empleado(B, 'luis', 'ana');
      await closed(B);
      await see(B, '#discLbl', ES.rowEmp('Luis'));
      const all = approvals();
      assert.deepStrictEqual(all.map((a) => [a.id === x.id, a.freed, a.order]), [[true, 'expired', null], [false, null, null]],
        'A\'s approval expired on the server, B\'s is live: ' + JSON.stringify(all));
      const y = all[1];
      /* A reconnects: the server never refuses the money already taken */
      await goOnline(A);
      await until(() => !!orderBy('Venta Vencida'), 15000, 'A\'s queued sale accepted');
      await until(async () => (await queued(A)).length === 0, 8000, 'A\'s queue emptied');
      await quiet(A);
      const o = orderBy('Venta Vencida');
      assert.deepStrictEqual([o.total, o.sub, o.disc, o.did, o.reason, o.by], [2450, 3500, 1050, x.id, 'Employee', 'Ana'],
        'the money as charged, linked to its approval: ' + JSON.stringify(o));
      const fl = (o.flags || []).filter((f) => /discount/.test(f)).sort();
      assert.deepStrictEqual(fl, ['discount_daily_twice', 'discount_late'], 'flagged for a manager: rung late, a second employee discount that day: ' + JSON.stringify(o.flags));
      const x2 = approvals(`id = '${x.id}'`)[0];
      assert.deepStrictEqual([x2.order, x2.used, x2.freed], [o.id, true, 'expired'], 'used by the sale; it stays freed (B\'s holds the day)');
      assert.strictEqual(audits('discount_used_after_release', `target_id = '${x.id}' and details ->> 'day_taken' = 'false'`), 1, 'logged: used after it was let go, the day not taken');
      assert.strictEqual(await A.evaluate(() => document.getElementById('noteModal').hidden), true, 'no warning for the cashier: the sale is in');
      assert.deepStrictEqual(await stored(A, 'hg-pos-notes'), null, 'no note kept on the device');
      /* B charges its own: linked as usual */
      await B.fill('#forWho', 'Venta B');
      await charge(B);
      await until(() => (orderBy('Venta B') || {}).did === y.id, 10000, 'B\'s sale linked');
      const ob = orderBy('Venta B');
      assert.deepStrictEqual((ob.flags || []).filter((f) => /discount/.test(f)), [], 'B\'s sale has no flag');
      assert.deepStrictEqual(approvals(`id = '${y.id}'`).map((a) => [a.order, a.freed]), [[ob.id, null]]);
      noCodeLeak(A); noCodeLeak(B);
      assert.deepStrictEqual(A.errors, []); assert.deepStrictEqual(B.errors, []);
    }
  },
  {
    name: 'O-b: the first reply of descuento_autorizar lost → the page asks again after 2 s with the same request id and the same codes, the server replays the same approval, the ticket gets it (one row), and the sale is linked',
    run: async ({ browser }) => {
      testMenu();
      const pg = await till(browser);
      const au = await wire(pg, 'descuento_autorizar');
      await tap(pg, 'T Latte'); await tap(pg, 'T Brownie');
      await openWin(pg);
      await empleado(pg, 'luis', 'ana', false);
      au.plan = ['drop'];
      await pg.click('#discGo');
      await closed(pg);
      await see(pg, '#discLbl', ES.rowEmp('Luis'));
      await see(pg, '#totalAmt', '₡2 450');
      await toastSeen(pg, ES.approvedBy('Ana'));
      await quiet(pg);
      const calls = sent(pg, 'descuento_autorizar');
      assert.strictEqual(calls.length, 2, 'the first try and one retry');
      assert.strictEqual(calls[1].body.p_request_id, calls[0].body.p_request_id, 'the retry carries the same request id');
      assert.deepStrictEqual([calls[1].body.p_pin, calls[1].body.p_employee_pin, calls[1].body.p_subtotal], [PINS.ana, PINS.luis, 3500],
        'the retry carries the codes still in memory');
      assert.ok(calls[1].t - calls[0].t >= 1900, 'the retry comes after about 2 seconds: ' + (calls[1].t - calls[0].t) + ' ms');
      assert.ok(au.lost.length === 1 && au.lost[0].ok, 'the server answered the first try (the reply was lost): ' + JSON.stringify(au.lost));
      const rep = (await answers(pg, 'descuento_autorizar')).pop();
      assert.ok(answered(pg, 'descuento_autorizar').every((x) => x.status === 200), 'no HTTP error');
      assert.ok(rep && rep.ok && rep.replay === true && rep.id === au.lost[0].id,
        'the retry answered as a replay of the same approval: ' + JSON.stringify(rep));
      const a = approvals();
      assert.strictEqual(a.length, 1, 'one approval row');
      assert.deepStrictEqual([a[0].id, a[0].req], [au.lost[0].id, calls[0].body.p_request_id]);
      assert.strictEqual(await tDiscId(pg), a[0].id, 'the ticket carries that approval');
      assert.strictEqual(audits('discount_approved', `target_id = '${a[0].id}'`), 1, 'approved once');
      assert.strictEqual(audits('discount_code_wrong'), 0, 'the replay tested no code');
      assert.strictEqual(sent(pg, 'descuento_liberar').length, 0, 'nothing let go');
      assert.strictEqual(await pg.evaluate(() => discCode.get()), null, 'the employee code gone after the answer');
      await pg.fill('#forWho', 'Venta Reintento');
      await charge(pg);
      await until(() => (orderBy('Venta Reintento') || {}).did === a[0].id, 10000, 'the sale linked');
      assert.deepStrictEqual([approvals()[0].order, approvals()[0].freed], [orderBy('Venta Reintento').id, null]);
      noCodeLeak(pg);
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'O-b: both replies lost and the connection gone → «No se pudo revisar los códigos…», nothing on the ticket, the codes wiped; on reconnect descuento_liberar goes with that request id, the approval is let go, and Luis is approved again at once (V4)',
    run: async ({ browser }) => {
      testMenu();
      const pg = await till(browser);
      const au = await wire(pg, 'descuento_autorizar');
      await tap(pg, 'T Latte'); await tap(pg, 'T Brownie');
      await openWin(pg);
      await empleado(pg, 'luis', 'ana', false);
      au.plan = ['drop', 'dropOffline'];
      await pg.click('#discGo');
      await see(pg, '#discErr', ES.net, 15000);
      assert.strictEqual(await pg.evaluate(() => navigator.onLine), false, 'the device lost the connection');
      assert.ok(au.lost.length === 2 && au.lost[0].ok && au.lost[1].replay === true && au.lost[1].id === au.lost[0].id,
        'the first call committed, the retry was its replay: ' + JSON.stringify(au.lost));
      const reqId = sent(pg, 'descuento_autorizar').pop().body.p_request_id;
      assert.strictEqual(await tDiscId(pg), null, 'nothing on the ticket');
      assert.ok(await pg.isHidden('#discRow'), 'no discount row');
      await see(pg, '#totalAmt', '₡3 500');
      await see(pg, '#discStep', ES.emp);
      assert.strictEqual(await pg.evaluate(() => discCode.get()), null, 'the codes wiped after the second try');
      assert.strictEqual(await pg.inputValue('#discPin'), '', 'the code box empty');
      const h = await holds(pg);
      assert.deepStrictEqual(h.map((x) => [x.id, x.request_id]), [[null, reqId]], 'the request id held to be let go (ids only)');
      const [ap] = approvals();
      assert.deepStrictEqual([ap.id, ap.order, ap.freed], [au.lost[0].id, null, null], 'the approval committed and live on the server');
      assert.ok(!(await seenToasts(pg)).includes(ES.approvedBy('Ana')), 'the lost approval is not announced');
      /* the connection returns: the online event lets it go by its request id */
      const n0 = pg.rpcs.length;
      const freed = pg.waitForResponse((r) => /rpc\/descuento_liberar/.test(r.url()) && r.status() === 200, { timeout: 10000 });
      await goOnline(pg);
      const fr = await freed;
      const body = JSON.parse(fr.request().postData() || '{}');
      assert.deepStrictEqual([body.p_request_id, body.p_id == null], [reqId, true], 'descuento_liberar with that request id');
      assert.ok((await fr.json()).ok, 'let go');
      await until(() => approvals()[0].freed === 'released', 8000, 'the approval released');
      await until(async () => (await holds(pg)).length === 0, 5000, 'the hold dropped');
      assert.strictEqual(sent(pg, 'descuento_autorizar', n0).length, 0, 'the reconnect sent no code');
      /* Luis again at once, no 30-minute wait */
      await empleado(pg, 'luis', 'ana');
      await closed(pg);
      await see(pg, '#discLbl', ES.rowEmp('Luis'));
      const all = approvals();
      assert.deepStrictEqual(all.map((a) => a.freed), ['released', null], 'the lost one released, the new one live');
      assert.strictEqual(await tDiscId(pg), all[1].id);
      assert.notStrictEqual(all[1].req, reqId, 'a new attempt, a new request id');
      await pg.fill('#forWho', 'Venta Sin Red');
      await charge(pg);
      await until(() => (orderBy('Venta Sin Red') || {}).did === all[1].id, 10000, 'the sale linked to the new approval');
      noCodeLeak(pg);
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'O-b (W6): both replies lost while navigator.onLine stays true (and the page\'s first release lost too): typed again, the release goes first and is awaited, then the new attempt is approved at once (a release lost again lets the call go ahead and is tried first next time); the same when the window is closed and opened again (the release goes with descuento_estado) and after a reload',
    run: async ({ browser }) => {
      testMenu();
      const pg = await till(browser);
      const au = await wire(pg, 'descuento_autorizar');
      const rel = await wire(pg, 'descuento_liberar');
      await tap(pg, 'T Latte'); await tap(pg, 'T Brownie');
      /* both replies of an attempt lost, and the release the page sends at once lost too; the browser still says online */
      async function lose() {
        const r0 = rel.n;
        au.plan = ['drop', 'drop']; rel.plan = ['cut'];
        await empleado(pg, 'luis', 'ana');
        await see(pg, '#discErr', ES.net, 15000);
        assert.ok(await pg.evaluate(() => navigator.onLine), 'the browser still says online: no «online» event will come');
        await until(() => rel.n > r0, 5000, 'the page tried to let it go at once (that release lost)');
        await quiet(pg);
        const req = sent(pg, 'descuento_autorizar').pop().body.p_request_id;
        const a = approvals(`request_id = '${req}'`);
        assert.ok(a.length === 1 && a[0].freed === null, 'the lost attempt committed and is live: ' + JSON.stringify(a));
        assert.deepStrictEqual((await holds(pg)).map((x) => x.request_id), [req], 'its request id held');
        return { req, id: a[0].id };
      }
      async function approvedAgain(after) {
        await closed(pg);
        await see(pg, '#discLbl', ES.rowEmp('Luis'));
        const fresh = await answers(pg, 'descuento_autorizar', after);
        assert.ok(fresh.length === 1 && fresh[0].ok && !fresh[0].replay, 'approved at once, no daily_used and no pending line: ' + JSON.stringify(fresh));
        const live = approvals(`beneficiary_id = '${STAFF.luis}' and freed_at is null`);
        assert.strictEqual(live.length, 1, 'one live approval for Luis');
        assert.strictEqual(await tDiscId(pg), live[0].id);
        /* × lets it go for the next part */
        const off = pg.waitForResponse((r) => /rpc\/descuento_liberar/.test(r.url()) && r.status() === 200);
        await pg.click('#discX');
        await off;
        await until(() => approvals(`id = '${live[0].id}'`)[0].freed === 'released', 8000, '× let it go');
        await quiet(pg);
      }

      /* (a) the codes typed again in the same window. First the release before the new attempt is lost too: the call goes
         ahead (proposal §3.3 W6) and the server, which still has the lost attempt live, answers daily_used with the pending
         line; the hold stays. Typed again: the release first, the new call waits for its answer, and it is approved */
      await openWin(pg);
      const L1 = await lose();
      rel.plan = ['cut'];
      const m0 = pg.rpcs.length, r1 = rel.n;
      await empleado(pg, 'luis', 'ana');
      const ep1 = Number(sql(`select extract(epoch from created_at + interval '30 minutes') from discount_approvals where id = '${L1.id}'`));
      await see(pg, '#discErr', ES.daily + ' ' + ES.pending('Caja', crHHMM(ep1)));
      assert.ok(rel.n === r1 + 1 && sent(pg, 'descuento_liberar', m0)[0].t < sent(pg, 'descuento_autorizar', m0)[0].t,
        'the release was tried first (and lost), then the call went ahead');
      assert.deepStrictEqual((await holds(pg)).map((x) => x.request_id), [L1.req], 'the hold stays for the next attempt');
      assert.strictEqual(approvals(`id = '${L1.id}'`)[0].freed, null, 'the lost attempt still live');
      await quiet(pg);
      rel.plan = ['wait'];
      const n0 = pg.rpcs.length, t0 = Date.now();
      await empleado(pg, 'luis', 'ana');
      await until(() => rel.held.length === 1, 8000, 'the release sent before the new attempt');
      assert.deepStrictEqual([rel.held[0].body.p_request_id, rel.held[0].body.p_id == null], [L1.req, true], 'the release names the held request id');
      await pg.waitForTimeout(500);   /* a negative check: nothing else may go while the release is unanswered */
      assert.strictEqual(sent(pg, 'descuento_autorizar', n0).length, 0, 'no new descuento_autorizar while the release is unanswered');
      rel.held[0].open();
      await approvedAgain(t0);
      const seq = pg.rpcs.slice(n0).map((r) => r.fn).filter((f) => /^descuento_(liberar|autorizar)$/.test(f));
      assert.deepStrictEqual(seq.slice(0, 2), ['descuento_liberar', 'descuento_autorizar'], 'the release, then the new attempt: ' + seq.join(', '));
      const relAns = answered(pg, 'descuento_liberar').find((x) => x.req && x.req.p_request_id === L1.req);
      assert.ok(relAns && relAns.body && relAns.body.ok && relAns.t <= sent(pg, 'descuento_autorizar', n0)[0].t,
        'its answer came back before the new attempt was sent: ' + JSON.stringify(relAns && relAns.body));
      assert.strictEqual(approvals(`id = '${L1.id}'`)[0].freed, 'released', 'the lost attempt released');

      /* (b) the window closed and opened again: the release goes with descuento_estado, before any new attempt */
      await openWin(pg);
      const L2 = await lose();
      await closeWin(pg);
      const n1 = pg.rpcs.length, t1 = Date.now();
      await openWin(pg);
      await until(() => approvals(`id = '${L2.id}'`)[0].freed === 'released', 8000, 'released when the window opened');
      await quiet(pg);
      const open = pg.rpcs.slice(n1).map((r) => r.fn);
      assert.ok(open.includes('descuento_estado') && open.includes('descuento_liberar') && !open.includes('descuento_autorizar'),
        'the window\'s opening sends the release with descuento_estado and no code: ' + open.join(', '));
      assert.strictEqual(sent(pg, 'descuento_liberar', n1)[0].body.p_request_id, L2.req, 'by its request id');
      assert.deepStrictEqual(await holds(pg), [], 'the hold dropped');
      await empleado(pg, 'luis', 'ana');
      await approvedAgain(t1);

      /* (c) a reload instead: the page's load lets it go */
      await openWin(pg);
      const L3 = await lose();
      const n2 = pg.rpcs.length;
      await pg.reload({ waitUntil: 'domcontentloaded' });
      await ready(pg);
      await until(() => approvals(`id = '${L3.id}'`)[0].freed === 'released', 8000, 'released by the page\'s load');
      assert.strictEqual(sent(pg, 'descuento_liberar', n2)[0].body.p_request_id, L3.req, 'by its request id');
      await until(async () => (await holds(pg)).length === 0, 5000, 'the hold dropped');
      assert.strictEqual(approvals(`beneficiary_id = '${STAFF.luis}' and freed_at is null`).length, 0, 'nothing of Luis left live');
      noCodeLeak(pg);
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'R-a: two tills at once on Empleado for Luis (two sign-ins, both registered, the calls reaching the server together) → exactly one approved and one «Descuento diario ya utilizado» with the pending line; no 23505',
    run: async ({ browser }) => {
      testMenu();
      const A = await till(browser, { station: { name: 'Caja A', main: true } });
      const B = await till(browser, { station: { name: 'Caja B', main: true } });
      assert.notStrictEqual(A.till.slot, B.till.slot, 'two places');
      const g = gate(); let arrived = 0;
      for (const p of [A, B]) {
        await tap(p, 'T Latte'); await tap(p, 'T Brownie');
        await openWin(p);
        await empleado(p, 'luis', 'ana', false);
        await p.route(/rest\/v1\/rpc\/descuento_autorizar/, async (r) => {
          if (r.request().method() === 'POST') { arrived++; if (arrived === 2) g.open(); await g.wait; }
          return r.fallback();
        });
      }
      const resp = [A, B].map((p) => p.waitForResponse((r) => /rpc\/descuento_autorizar/.test(r.url()), { timeout: 15000 }));
      await Promise.all([A.click('#discGo'), B.click('#discGo')]);
      const r = await Promise.all(resp);
      const ans = await Promise.all(r.map((x) => x.json()));
      assert.deepStrictEqual(r.map((x) => x.status()), [200, 200], 'both answered without an HTTP error (no 23505): ' + JSON.stringify(ans));
      assert.deepStrictEqual(ans.map((a) => (a.ok ? 'ok' : a.error)).sort(), ['daily_used', 'ok'], 'exactly one ok and one daily_used: ' + JSON.stringify(ans));
      const wi = ans[0].ok ? 0 : 1, win = [A, B][wi], lose = [A, B][1 - wi], wst = ['Caja A', 'Caja B'][wi];
      assert.notStrictEqual(sent(A, 'descuento_autorizar')[0].body.p_request_id, sent(B, 'descuento_autorizar')[0].body.p_request_id, 'two attempts, two request ids');
      await closed(win);
      await see(win, '#discLbl', ES.rowEmp('Luis'));
      const all = approvals();
      assert.strictEqual(all.length, 1, 'one approval for Luis: ' + JSON.stringify(all));
      assert.deepStrictEqual([all[0].ben, all[0].station, all[0].freed], ['Luis', wst, null]);
      const lost = ans[1 - wi];
      assert.deepStrictEqual([lost.beneficiary, lost.pending, lost.station], ['Luis', true, wst], 'the other answer names the pending approval: ' + JSON.stringify(lost));
      const ep = Number(sql(`select extract(epoch from created_at + interval '30 minutes') from discount_approvals where id = '${all[0].id}'`));
      assert.ok(Math.abs(Date.parse(lost.until) - ep * 1000) <= 1, 'let go at its created_at + 30 minutes: ' + lost.until);
      await see(lose, '#discErr', ES.daily + ' ' + ES.pending(wst, crHHMM(Date.parse(lost.until) / 1000)));
      await see(lose, '#discStep', ES.emp);
      assert.ok(await lose.isHidden('#discRow'), 'nothing on the other ticket');
      assert.strictEqual(audits('discount_daily_refused'), 1, 'one refusal logged');
      assert.strictEqual(audits('discount_code_wrong'), 0, 'nothing counted');
      /* the winner sells it; the other asks again: used now, no pending line */
      await win.fill('#forWho', 'Venta Carrera');
      await charge(win);
      await until(() => (orderBy('Venta Carrera') || {}).did === all[0].id, 10000, 'the sale linked');
      await empleado(lose, 'luis', 'ana');
      await see(lose, '#discErr', ES.daily);
      assert.strictEqual(approvals().length, 1, 'still one approval');
      noCodeLeak(A); noCodeLeak(B);
      assert.deepStrictEqual(A.errors, []); assert.deepStrictEqual(B.errors, []);
    }
  },
  {
    name: 'R-b: Luis\'s discounted sale voided in Orders by Ana frees the day; Empleado for Luis again is approved with «Segundo descuento de empleado hoy para Luis: el anterior lo anuló Ana.» and its sale is linked',
    run: async ({ browser }) => {
      testMenu();
      const pg = await till(browser);
      await tap(pg, 'T Latte'); await tap(pg, 'T Brownie');
      await openWin(pg);
      await empleado(pg, 'luis', 'ana');
      await closed(pg);
      await see(pg, '#discLbl', ES.rowEmp('Luis'));
      const [a1] = approvals();
      await pg.fill('#forWho', 'Venta Anulada');
      await charge(pg);
      await until(() => (orderBy('Venta Anulada') || {}).did === a1.id, 10000, 'the first sale linked');
      const o1 = orderBy('Venta Anulada');
      /* voided in Orders by Ana */
      await pg.click('#ordersBtn');
      const row = pg.locator('#ordersBody .orow', { hasText: 'Venta Anulada' });
      await until(async () => (await row.count()) === 1, 8000, 'the sale in Orders');
      await row.locator('button', { hasText: /^Anular$/ }).click();
      await pg.waitForSelector('#voidBox:not([hidden])');
      await pg.fill('#vReason', 'cobrado dos veces');
      await until(() => pg.evaluate((id) => [...document.querySelectorAll('#vMgr option')].some((o) => o.value === id), STAFF.ana), 8000, 'the managers listed');
      await pg.selectOption('#vMgr', STAFF.ana);
      await pg.fill('#vPin', PINS.ana);
      await pg.click('#vGo');
      await until(() => orderBy('Venta Anulada').voided, 8000, 'voided');
      await until(() => approvals(`id = '${a1.id}'`)[0].freed === 'void', 5000, 'the void freed the day');
      assert.strictEqual(sql(`select manager_name || '/' || (details ->> 'how') from audit_log where action = 'discount_freed' and details ->> 'approval' = '${a1.id}'`), 'Ana/void');
      await pg.click('#ordersClose');
      /* Luis again: approved, with the line about the void */
      await tap(pg, 'T Latte'); await tap(pg, 'T Brownie');
      const t0 = Date.now();
      await openWin(pg);
      await empleado(pg, 'luis', 'ana');
      await closed(pg);
      await toastSeen(pg, ES.prior('Luis', 'Ana'));
      await see(pg, '#discLbl', ES.rowEmp('Luis'));
      const ans = (await answers(pg, 'descuento_autorizar', t0)).pop();
      assert.deepStrictEqual(ans.prior, { how: 'void', by: 'Ana' }, 'the answer names the earlier void');
      const all = approvals();
      assert.deepStrictEqual(all.map((a) => [a.ben, a.freed]), [['Luis', 'void'], ['Luis', null]]);
      assert.strictEqual(await tDiscId(pg), all[1].id);
      await pg.fill('#forWho', 'Venta Segunda');
      await charge(pg);
      await until(() => (orderBy('Venta Segunda') || {}).did === all[1].id, 10000, 'the second sale linked');
      const o2 = orderBy('Venta Segunda');
      assert.deepStrictEqual((o2.flags || []).filter((f) => /discount/.test(f)), [], 'a valid second discount: no flag');
      assert.strictEqual(o1.voided === false && orderBy('Venta Anulada').voided, true, 'the first sale stays on record as voided');
      noCodeLeak(pg);
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'R-c: one attempt sent twice at once with the same request id → the same approval twice, one row, no daily_used, no 23505 (Empleado for Luis, and Local four times); the page\'s own retry arriving while the first call still runs on the server waits for it and gets the same approval',
    run: async ({ browser }) => {
      testMenu();
      const pg = await till(browser);
      await tap(pg, 'T Latte'); await tap(pg, 'T Brownie');
      const twice = (args) => pg.evaluate(async (a) => {
        const one = () => db.rpc('descuento_autorizar', a).then((r) => ({ status: r.status, error: r.error, data: r.data }));
        return Promise.all([one(), one()]);
      }, args);
      const same = (res, what) => {
        assert.deepStrictEqual(res.map((x) => [x.status, x.error]), [[200, null], [200, null]], what + ': no HTTP error, no 23505: ' + JSON.stringify(res));
        assert.ok(res.every((x) => x.data && x.data.ok), what + ': both ok (no daily_used): ' + JSON.stringify(res.map((x) => x.data)));
        assert.strictEqual(res[0].data.id, res[1].data.id, what + ': the same approval twice');
        assert.deepStrictEqual(res.map((x) => x.data.replay === true).sort(), [false, true], what + ': one made it, the other is its replay');
        const strip = (d) => { const c = Object.assign({}, d); delete c.replay; return c; };
        assert.deepStrictEqual(strip(res[0].data), strip(res[1].data), what + ': the same answer');
        return res[0].data.id;
      };
      const r1 = uuid();
      const idE = same(await twice({ p_category: 'empleado', p_pin: PINS.ana, p_employee_pin: PINS.luis, p_subtotal: 3500, p_request_id: r1, p_station: 'Caja' }), 'Empleado');
      assert.deepStrictEqual(approvals(`request_id = '${r1}'`).map((a) => [a.id, a.ben, a.freed]), [[idE, 'Luis', null]], 'one row');
      assert.strictEqual(approvals(`beneficiary_id = '${STAFF.luis}'`).length, 1, 'one approval for Luis');
      for (let i = 0; i < 4; i++) {
        const r = uuid();
        const id = same(await twice({ p_category: 'local', p_pin: PINS.ana, p_subtotal: 3500, p_request_id: r, p_station: 'Caja' }), 'Local ' + (i + 1));
        assert.deepStrictEqual(approvals(`request_id = '${r}'`).map((a) => a.id), [id], 'Local ' + (i + 1) + ': one row');
      }
      assert.strictEqual(approvals(`category = 'local'`).length, 4, 'four Local rows for four attempts');
      assert.strictEqual(audits('discount_daily_refused'), 0, 'no daily_used, not even a backstop');
      assert.strictEqual(audits('discount_refused'), 0, 'no bad_request');
      assert.strictEqual(audits('discount_approved', `details ->> 'category' is not null`), 5, 'five approvals logged, once each');

      /* the page's own retry while the first call is still running on the server: the till's place lock held by another
         connection keeps the first call waiting (it holds its request lock); its reply is lost at the page; the retry 2 s
         later waits behind it on the request lock and reads its row */
      const key = `hashtextextended('canopy.discount_slot:${pg.till.slot}', 0)`;
      const locker = spawn('psql', ['-X', '-At', '-d', process.env.CANOPY_E2E_DB], { stdio: ['pipe', 'pipe', 'pipe'] });
      let lout = '';
      locker.stdout.on('data', (d) => { lout += d; });
      try {
        locker.stdin.write(`select 'locked' from (select pg_advisory_lock(${key})) x;\n`);
        await until(() => lout.includes('locked'), 8000, 'the place lock taken by another connection');
        const waiting = () => Number(sql(`select count(*) from pg_stat_activity where datname = current_database()
                                            and wait_event_type = 'Lock' and wait_event = 'advisory' and query ilike '%descuento_autorizar%'`));
        const au = await wire(pg, 'descuento_autorizar');
        let first = null;
        au.plan = [async (r) => {
          first = r.fetch().then((x) => x.json());   /* the call goes on at the server */
          await until(() => waiting() === 1, 8000, 'the first call waiting on the server');
          return r.abort('failed');                   /* and the page never hears it */
        }];
        const n0 = pg.rpcs.length;
        await openWin(pg);
        await empleado(pg, 'marta', 'ana');
        await until(() => waiting() === 2, 10000, 'the retry waiting behind the first');
        const calls = sent(pg, 'descuento_autorizar', n0);
        assert.strictEqual(calls.length, 2);
        assert.strictEqual(calls[1].body.p_request_id, calls[0].body.p_request_id, 'the retry: the same request id');
        locker.stdin.write(`select pg_advisory_unlock(${key});\n\\q\n`);
        await closed(pg);
        await see(pg, '#discLbl', ES.rowEmp('Marta'));
        const f = await first;
        const rep = (await answers(pg, 'descuento_autorizar', calls[1].t)).pop();
        assert.ok(f.ok && !f.replay, 'the first call made the approval: ' + JSON.stringify(f));
        assert.ok(rep.ok && rep.replay === true && rep.id === f.id, 'the retry got the same approval: ' + JSON.stringify(rep));
        assert.deepStrictEqual(approvals(`beneficiary_id = '${STAFF.marta}'`).map((a) => [a.id, a.req]), [[f.id, calls[0].body.p_request_id]], 'one row for Marta');
        assert.strictEqual(await tDiscId(pg), f.id, 'the ticket carries it');
        assert.strictEqual(audits('discount_daily_refused'), 0, 'no daily_used for Marta');
      } finally { try { locker.kill(); } catch (e) {} }
      noCodeLeak(pg);
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'T-d (ticket): Cancel, the same category tapped again, another category tapped, or a reopen while descuento_autorizar is held → the late approval never reaches the ticket and is let go with descuento_liberar (by its request id when the late replies are lost too); in the reopened window Luis is approved at once',
    run: async ({ browser }) => {
      testMenu();
      const pg = await till(browser);
      const au = await wire(pg, 'descuento_autorizar');
      await tap(pg, 'T Latte'); await tap(pg, 'T Brownie');
      const check = softly();
      /* the reply held while the staff move on; then it arrives */
      async function late(i, what) {
        await until(() => au.held.length === i + 1, 8000, 'the approval made on the server, its reply held');
        const a = au.held[i].answer;
        assert.ok(a.ok, 'the server approved: ' + JSON.stringify(a));
        await what();
        const freed = pg.waitForResponse((r) => /rpc\/descuento_liberar/.test(r.url()), { timeout: 10000 });
        au.held[i].open();
        const fr = await freed;
        const body = JSON.parse(fr.request().postData() || '{}');
        check(body.p_id === a.id, 'the late approval let go by its id: ' + JSON.stringify(body));
        check((await fr.json()).ok === true, 'descuento_liberar answered ok');
        await until(() => approvals(`id = '${a.id}'`)[0].freed === 'released', 8000, 'released on the server');
        await quiet(pg);
        check(await tDiscId(pg) === null, 'never on the ticket');
        check(await pg.isHidden('#discRow'), 'no discount row');
        check(norm(await pg.textContent('#totalAmt')) === '₡3 500', 'the total unchanged');
        check((await holds(pg)).length === 0, 'nothing left held');
        return a;
      }
      /* (a) Cancel */
      au.plan = ['hold'];
      await openWin(pg);
      await empleado(pg, 'luis', 'ana');
      await late(0, () => closeWin(pg));
      /* (b1) the same category tapped again (the window's «Volver»: it restarts at its step 1) */
      au.plan = ['hold'];
      await openWin(pg);
      await local(pg, 'ana');
      await late(1, async () => { await cat(pg, 'local'); await see(pg, '#discStep', ES.mgr); });
      check(await pg.isVisible('#discModal'), '(b1) the window stays open');
      check(await pg.evaluate(() => disc.cat + '/' + disc.step + '/' + disc.busy) === 'local/1/false', '(b1) on Local step 1, not busy');
      check((await text(pg, '#discErr')) === '', '(b1) no message');
      /* (b2) another category tapped */
      au.plan = ['hold'];
      await typeCode(pg, PINS.ana); await pg.click('#discGo');
      await late(2, async () => { await cat(pg, 'huesped'); await see(pg, '#discStep', ES.mgr); });
      check(await pg.isVisible('#discModal'), '(b2) the window stays open');
      check(await pg.evaluate(() => disc.cat + '/' + disc.step) === 'huesped/1', '(b2) on Huésped');
      check((await text(pg, '#discErr')) === '', '(b2) no message');
      await closeWin(pg);
      /* (d) Cancel, and then both late replies lost (the first held then lost, the page's retry lost): the late
         attempt is let go by its request id at once, as an unknown outcome (proposal §3.3, §3.4) */
      au.plan = ['holdDrop', 'drop'];
      await openWin(pg);
      await empleado(pg, 'marta', 'ana');
      await until(() => au.held.length === 4, 8000, 'Marta\'s approval made on the server, its reply held');
      const d = au.held[3].answer;
      await closeWin(pg);
      const freedD = pg.waitForResponse((r) => /rpc\/descuento_liberar/.test(r.url()), { timeout: 15000 });
      au.held[3].open();
      const frD = await freedD;
      const bD = JSON.parse(frD.request().postData() || '{}');
      check(bD.p_request_id === au.held[3].body.p_request_id && bD.p_id == null, '(d) let go by its request id: ' + JSON.stringify(bD));
      await until(() => approvals(`id = '${d.id}'`)[0].freed === 'released', 8000, '(d) released on the server');
      await quiet(pg);
      check(await tDiscId(pg) === null && await pg.isHidden('#discRow'), '(d) never on the ticket');
      check((await holds(pg)).length === 0, '(d) nothing left held');
      /* (c) a reopen: Cancel, the window opened again, then the late reply */
      au.plan = ['hold'];
      await openWin(pg);
      await empleado(pg, 'luis', 'ana');   /* Luis's day is free again: (a)'s approval was let go */
      await late(4, async () => { await closeWin(pg); await openWin(pg); });
      check(await pg.isVisible('#discModal'), '(c) the reopened window stays open');
      check((await text(pg, '#discStep')) === ES.pick && (await text(pg, '#discErr')) === '', '(c) the reopened window untouched: no category, no message');
      check(!(await seenToasts(pg)).includes(ES.approvedBy('Ana')), 'no late approval announced');
      /* in the reopened window: Luis at once (his day was given back by the release) */
      await empleado(pg, 'luis', 'ana');
      await closed(pg);
      await see(pg, '#discLbl', ES.rowEmp('Luis'));
      const all = approvals();
      check(JSON.stringify(all.map((a) => a.freed)) === JSON.stringify(['released', 'released', 'released', 'released', 'released', null]),
        'five late approvals let go, the last one live: ' + JSON.stringify(all.map((a) => [a.cat, a.freed])));
      check(await tDiscId(pg) === all[all.length - 1].id, 'the ticket carries the last one');
      await pg.fill('#forWho', 'Venta Lenta');
      await charge(pg);
      await until(() => (orderBy('Venta Lenta') || {}).did === all[all.length - 1].id, 10000, 'the sale linked');
      check(sent(pg, 'descuento_liberar').length === 5, 'one release per late approval, none for the sold one: ' + sent(pg, 'descuento_liberar').length);
      noCodeLeak(pg);
      assert.deepStrictEqual(pg.errors, []);
      check.done();
    }
  }
  ,
  {
    name: 'two tabs of the till on one device: tab B opening, and a Wi-Fi blip with both open, never let go of tab A\'s live Empleado (A\'s load still beats); A\'s sale is linked and verified, nothing «used after it was let go»; once A is gone (its beat stale), B lets its hold go',
    run: async ({ browser }) => {
      testMenu();
      const A = await till(browser, { station: { name: 'Caja A', main: true } });
      await tap(A, 'T Latte'); await tap(A, 'T Brownie');
      await openWin(A); await empleado(A, 'luis', 'ana'); await closed(A);
      await see(A, '#discLbl', ES.rowEmp('Luis'));
      const [ap] = approvals();
      const loadA = await A.evaluate(() => DISC_LOAD);
      assert.deepStrictEqual((await holds(A)).map((h) => [h.id, h.load]), [[ap.id, loadA]], 'A holds its approval, tagged with its load');
      /* tab B opens on the same device */
      const B = await secondTab(A);
      await quiet(B);
      assert.deepStrictEqual(sent(B, 'descuento_liberar').map((r) => r.body), [], 'B lets nothing of A go when it loads');
      assert.strictEqual(approvals()[0].freed, null, 'A\'s approval still live');
      /* a Wi-Fi blip with both tabs open: «online» in both */
      const a0 = A.rpcs.length, b0 = B.rpcs.length;
      await goOffline(A);
      await goOnline(A);
      await until(() => B.evaluate(() => navigator.onLine), 5000, 'B online');
      await new Promise((r) => setTimeout(r, 1500));
      await quiet(A); await quiet(B);
      assert.deepStrictEqual(sent(A, 'descuento_liberar', a0).concat(sent(B, 'descuento_liberar', b0)).map((r) => r.body), [], 'nothing let go on «online»');
      assert.strictEqual(approvals()[0].freed, null, 'still live after the blip');
      assert.strictEqual(await tDiscId(A), ap.id, 'still on A\'s ticket');
      /* A charges: linked and verified */
      await A.fill('#forWho', 'Venta Dos Pestanas');
      await charge(A);
      const o = await until(() => orderBy('Venta Dos Pestanas'), 10000, 'A\'s sale');
      assert.deepStrictEqual([o.did, (o.flags || []).filter((f) => /discount/.test(f))], [ap.id, []], 'linked, no flag');
      assert.deepStrictEqual([audits('discount_released'), audits('discount_used_after_release')], [0, 0], 'nothing let go, nothing used after a release');
      /* A authorizes Local on a new ticket, then A is gone for good (its beat older than 2 minutes): B's next «online»
         lets that hold go */
      await tap(A, 'T Latte');
      await openWin(A); await local(A, 'ana'); await closed(A);
      const a2 = await until(() => tDiscId(A), 5000, 'Local on A\'s ticket');
      await A.close();
      await B.evaluate((k) => localStorage.setItem(k, String(Date.now() - 180000)), 'hg-pos-disc-load:' + loadA);
      const freed = B.waitForResponse((r) => /rpc\/descuento_liberar/.test(r.url()) && r.status() === 200, { timeout: 10000 });
      await goOffline(B);
      await goOnline(B);
      await freed;
      await until(() => (approvals(`id = '${a2}'`)[0] || {}).freed === 'released', 8000, 'the gone tab\'s approval let go');
      assert.deepStrictEqual(B.errors, []);
    }
  },
  {
    name: 'Q7 on paper: an Empleado ticket sent to «Cobrar después» while offline and charged on this device from its own window prints «Descuento Empleado · Employee discount», as every other path does',
    run: async ({ browser }) => {
      testMenu();
      const pg = await till(browser);
      await tap(pg, 'T Latte'); await tap(pg, 'T Brownie');
      await openWin(pg); await empleado(pg, 'luis', 'ana'); await closed(pg);
      await see(pg, '#discLbl', ES.rowEmp('Luis'));
      const [ap] = approvals();
      await goOffline(pg);
      await pg.click('#sendBtn');
      await pg.waitForSelector('#numModal:not([hidden])');
      await pg.fill('#numWho', 'Luis Mesa');
      await pg.locator('#numGrid button', { hasText: /^9$/ }).click();
      await until(async () => (await queued(pg)).length === 1, 5000, 'the order kept on the device');
      await pg.locator('#openBar .ocard', { hasText: '#9' }).click();
      await pg.waitForSelector('#locModal:not([hidden])', { timeout: 8000 });
      await pg.click('#locPayRow [data-lpay="card"]');
      await pg.waitForSelector('#locPaid:not([hidden])');
      await pg.click('#locReceipt');
      const html = await until(async () => pg.evaluate(() => window.__printedHTML || ''), 5000, 'printed');
      const rec = norm(html.replace(/<[^>]+>/g, ' '));
      assert.ok(rec.includes('Descuento Empleado · Employee discount'), 'the category\'s label on the receipt: ' + rec);
      assert.ok(!rec.includes('Descuento · Discount'), 'not the generic label');
      assert.ok(!/%/.test(rec.replace(/IVA 13%/g, '')), 'no percentage for the discount on paper');
      /* back online: the sale goes up linked to its approval */
      await goOnline(pg);
      await until(async () => (await queued(pg)).length === 0, 15000, 'the order sent once online');
      const o = await until(() => orderBy('Luis Mesa'), 10000, 'the sale on the server');
      assert.deepStrictEqual([o.did, o.disc, o.total], [ap.id, 1050, 2450], 'linked, at the approved discount');
      assert.deepStrictEqual(pg.errors, []);
    }
  }
];
