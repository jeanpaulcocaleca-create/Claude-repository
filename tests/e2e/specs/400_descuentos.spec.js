/* The POS discount window of migration 0038 (pos.html #discModal), on a till registered for discounts
   (tests/e2e/lib.js registerTill): its fixed layout at four screen sizes in both languages (the owner's image,
   referencia-diseno.md), every message of its one line at 360 × 640, the codes (dots, never kept, never sent empty,
   a scripted key types nothing, the employee's code gone after a category change, Cancel or 2 minutes), each of the
   four discounts end to end (ticket row, total, the sale linked on the server), Spanish only, Guía Turista off by
   default and without an owner PIN, never stacked, the lines locked, parking on a bill, a reload, and the owner's
   adjustment 1: the owner's code for a courtesy opens nothing (no unlock, no owner area, the time clock still asks).
   Sources: proposal-final.md §3 and §5.2, mecanismo-intentos.md §10.1 and §13.3 (C-i, C-j, C-k), decisiones-dueno.md,
   build-plan.md L1-L3, api-0038.md §4 and §10. */
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const { page, goto, until, sql, openRegister, registerTill, guiaOn, STAFF, PINS } = require('../lib');
const gw = require('../gateway');

const API = 'http://127.0.0.1:' + (Number(process.env.E2E_SITE_PORT || 8090) + 1000);
const SHOTS = process.env.E2E_SHOTS_DIR || null;   // screenshots for the owner's review only when asked for (a folder)
const ITEM = { latte: 'b0000000-0000-4000-8000-0000000004a1', brownie: 'b0000000-0000-4000-8000-0000000004a2' };
const BILL = (n) => 'd0000000-0000-4000-8000-0000000040' + String(n).padStart(2, '0');

/* the texts as lang.js shows them (Spanish), and the English sources where a test runs in English */
const ES = {
  title: 'Aplicar descuento',
  leadMgr: 'Seleccione el tipo de descuento y autorícelo con el código de encargado.',
  leadOwner: 'Seleccione el tipo de descuento y autorícelo con el código del dueño.',
  cats: ['Empleado', 'Local', 'Huésped', 'Guía Turista'],
  pick: 'Elija el descuento', emp: 'Código de empleado', mgr: 'Código de encargado', owner: 'Código del dueño',
  company: 'Empresa del guía turístico', go: 'Autorizar descuento', cancel: 'Cancelar', erase: 'Borrar',
  typeEmp: 'Escriba el código de empleado (4 a 8 números).', typeMgr: 'Escriba el código de encargado (4 a 8 números).',
  typeOwner: 'Escriba el código del dueño (4 a 8 números).', typeCompany: 'Escriba la empresa del guía turístico (2 a 80 caracteres).',
  badMgr: 'Código de encargado no válido.', badOwner: 'Solo el dueño autoriza este descuento: código no válido.',
  badEmp: 'Código de empleado no válido. Escríbalo de nuevo.',
  warn: { wait_1m: 'Un error más y esta caja espera 1 minuto.', wait_5m: 'Un error más y esta caja espera 5 minutos.',
          wait_10m: 'Un error más y esta caja espera 10 minutos.', stop: 'Un error más detiene los descuentos en esta caja.' },
  wait30: 'Demasiados códigos equivocados en esta caja. Intente de nuevo en 30 segundos.',
  waitAt: (t) => `Demasiados códigos equivocados en esta caja. Próximo intento a las ${t}; puede cobrar sin descuento.`,
  stopped: 'Descuentos detenidos en esta caja por códigos equivocados. Un encargado la reanuda en la bitácora.',
  notEnrolled: 'Esta caja no está registrada para descuentos. Un encargado la registra en Reloj de marcas › Bitácora.',
  ended: 'Se quitó el registro de esta caja para descuentos. Un encargado la registra de nuevo en la bitácora.',
  noSession: 'No se pudo identificar esta caja. Cierre sesión y vuelva a entrar.',
  daily: 'Descuento diario ya utilizado', pending: (s, t) => `Sin usar todavía en ${s}: se libera a las ${t}.`,
  notSelf: 'Un encargado no puede autorizar su propio descuento.',
  noOwner: 'Guía Turista necesita el PIN del dueño. El dueño lo agrega en Equipo.',
  guiaOff: 'La cortesía Guía Turista espera la confirmación del IVA por el contador (A-13).',
  stacked: 'Este pedido ya tiene un descuento. Quítelo primero.', locked: 'Quite el descuento para cambiar el pedido.',
  hasParts: 'Un descuento cubre toda la cuenta: solo se da antes de cualquier pago.',
  combo: 'Esta cuenta tiene un combo. Los descuentos no se suman a los combos.',
  changed: 'La cuenta cambió en otro aparato. Revísela y autorice de nuevo.',
  offline: 'Un descuento necesita internet para revisar los códigos.',
  net: 'No se pudo revisar los códigos. Revise la conexión.',
  netBill: 'No se pudo confirmar el descuento. La cuenta se revisa de nuevo al volver la conexión.',
  dbUpdate: 'Los descuentos necesitan una actualización de la base de datos. Avise al dueño.',
  notFound: 'Ese pedido ya no está abierto.', cancelled: 'Ese pedido fue cancelado.', alreadyPaid: 'Esa cuenta ya fue pagada.',
  refundFirst: 'Parte de esta cuenta ya se pagó a cuenta. Un encargado anula (o devuelve) ese pago en Pedidos primero; luego intente de nuevo.',
  noAccount: 'Este ingreso todavía no está conectado al café.', generic: 'No se pudo aprobar. Intente de nuevo.',
  empty: 'El pedido está vacío.', discUsed: 'Esa aprobación ya se usó en otro pedido. Pida el descuento de nuevo.',
  discExpired: 'La aprobación del descuento tiene más de 30 minutos. Pídala de nuevo.',
  discNotApproved: 'No se encontró esa aprobación. Pida el descuento de nuevo.',
  courtesy: 'Registrar cortesía'
};
const EN = {
  cats: ['Employee', 'Local', 'Hotel guest', 'Tour guide'], pick: 'Pick the discount', emp: 'Employee code', mgr: 'Manager code',
  owner: 'Owner code', company: "Tour guide's company", go: 'Authorize discount', cancel: 'Cancel',
  typeOwner: 'Type the owner code (4 to 8 numbers).', badMgr: 'Manager code not valid.',
  guiaOff: "The tour guide courtesy waits for the accountant's IVA confirmation (A-13).", title: 'Apply a discount'
};
/* English category words that must never show on a Spanish screen outside a name or company typed by a person */
const EN_CAT = /\b(Employee|Hotel guest|Tour guide|Employee discount|Local discount|Hotel guest discount|Tour guide courtesy)\b/;

/* ---------- helpers ---------- */
const norm = (s) => String(s || '').replace(/[  ]/g, ' ').replace(/\s+/g, ' ').trim();
const text = async (pg, sel) => norm(await pg.textContent(sel));
const see = (pg, sel, want, ms) => until(async () => {
  const t = await text(pg, sel);
  return want instanceof RegExp ? want.test(t) : t === want;
}, ms || 8000, sel + ' to read «' + want + '»').catch(async (e) => { e.message += ' (it reads «' + (await text(pg, sel)) + '»)'; throw e; });
/* a seed PIN as a value of its own (not a piece of a uuid, an amount or a longer number) */
const pinIn = (s, pin) => new RegExp('(^|[^0-9a-f-])' + pin + '([^0-9a-f-]|$)', 'i').test(String(s || ''));
const anyPin = (s) => Object.values(PINS).filter((p) => pinIn(s, p));

function testMenu() {
  sql(`insert into menu_categories (id, name, sort, kitchen) values ('b0000000-0000-4000-8000-0000000004c1', 'Test Bar 400', 0, false);
       insert into menu_items (id, category_id, name, price_crc, sort, available) values
         ('${ITEM.latte}', 'b0000000-0000-4000-8000-0000000004c1', 'T Latte', 2000, 1, true),
         ('${ITEM.brownie}', 'b0000000-0000-4000-8000-0000000004c1', 'T Brownie', 1500, 2, true);`);
}
/* a bill not paid yet, as another device left it */
function bill(n, name, lines) {
  const total = lines.reduce((s, l) => s + l[1] * l[2], 0);
  sql(`insert into orders (id, total_crc, payment_method, status, paid, source, station, guest_name)
       values ('${BILL(n)}', ${total}, 'pending', 'ready', false, 'front', 'Caja', '${name}')`);
  sql(`insert into order_items (order_id, item_name, price_crc, qty) values ` + lines.map((l) => `('${BILL(n)}', '${l[0]}', ${l[1]}, ${l[2]})`).join(', '));
}

/* every request the page sends to a database function, with its body */
function watch(pg) {
  pg.rpcs = []; pg.inflight = 0;
  const api = (r) => r.url().startsWith(API);
  pg.on('requestfinished', (r) => { if (api(r)) pg.inflight--; });
  pg.on('requestfailed', (r) => { if (api(r)) pg.inflight--; });
  pg.on('request', (r) => {
    const u = r.url();
    if (!u.startsWith(API)) return;
    pg.inflight++;
    const m = u.match(/\/rest\/v1\/rpc\/([a-z_0-9]+)/);
    pg.rpcs.push({ fn: m ? m[1] : null, url: u, body: r.postData() || '' });
  });
}
const sent = (pg, fn) => pg.rpcs.filter((r) => r.fn === fn);
/* no request of the page on its way, three polls in a row */
async function quiet(pg) { let calm = 0; await until(() => { calm = pg.inflight <= 0 ? calm + 1 : 0; return calm >= 3; }, 10000, 'no request in flight'); }
const bodies = (pg, fn) => sent(pg, fn).map((r) => JSON.parse(r.body || '{}'));
/* proposal §5.2 C-a (340's watcher): a code goes only in descuento_autorizar, never empty there; nothing else carries one */
function noCodeLeak(pg) {
  for (const r of pg.rpcs) {
    if (r.fn === 'descuento_autorizar') {
      const b = JSON.parse(r.body || '{}');
      assert.ok(b.p_pin === null || /^\d{4,8}$/.test(b.p_pin), 'p_pin is a typed code (or null on a replay), never empty: ' + r.body);
      assert.ok(!('p_employee_pin' in b) || b.p_employee_pin === null || /^\d{4,8}$/.test(b.p_employee_pin), 'p_employee_pin never empty: ' + r.body);
      continue;
    }
    assert.deepStrictEqual(anyPin(r.url + ' ' + r.body), [], 'a code in a request other than descuento_autorizar: ' + r.fn + ' ' + r.body.slice(0, 300));
  }
}
/* mecanismo §13.3 C-k: no PIN or code in the page or in this device's storage */
async function noCodeKept(pg) {
  const where = await pg.evaluate(() => {
    const vals = [...document.querySelectorAll('input, textarea')].map((i) => i.id + '=' + i.value);
    const st = (s) => { const o = {}; try { for (let i = 0; i < s.length; i++) o[s.key(i)] = s.getItem(s.key(i)); } catch (e) {} return o; };
    return { dom: document.documentElement.outerHTML, values: vals.join(' '), local: JSON.stringify(st(localStorage)), session: JSON.stringify(st(sessionStorage)) };
  });
  for (const k of Object.keys(where)) assert.deepStrictEqual(anyPin(where[k]), [], 'a code kept in the page\'s ' + k);
}
const storeKeys = (pg) => pg.evaluate(() => {
  const k = (s) => { const o = []; try { for (let i = 0; i < s.length; i++) o.push(s.key(i)); } catch (e) {} return o.sort(); };
  return { local: k(localStorage), session: k(sessionStorage) };
});

/* the till: the POS signed in with the café login, the register open, its 20-second retry and live poll off (the test
   decides when it sends), registered for discounts as a manager does it */
async function till(browser, opts) {
  opts = Object.assign({ login: 'cafe', lang: 'es', viewport: { width: 1180, height: 820 } }, opts || {});
  openRegister();
  const pg = await page(browser, opts);
  watch(pg);
  if (opts.clock) await pg.clock.install();
  await pg.addInitScript(() => {
    const si = window.setInterval;
    window.setInterval = function (fn, ms) { return ms === 20000 ? 0 : si.apply(this, arguments); };
  });
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
  // the page's own first requests answered (its menu and tax caches written), so a storage baseline is not racing them
  await pg.waitForLoadState('networkidle');
  await until(() => pg.evaluate(() => !!localStorage.getItem('hg-pos-tax')), 8000, 'the page\'s tax settings cached');
  pg.keys0 = await storeKeys(pg);
  if (opts.register !== false) await registerTill(pg);
  return pg;
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
/* the window's own keys, tapped as a person does */
async function typeCode(pg, code) { for (const d of code) await pg.click(`#discPad button[data-k="${d}"]`); }
async function openWin(pg) {
  await pg.click('#discBtn');
  await pg.waitForSelector('#discModal:not([hidden])', { timeout: 5000 });
  await pg.waitForFunction(() => window.disc && disc.st, null, { timeout: 8000 });   // the till's state has come back
}
async function closeWin(pg) {
  await pg.click('#discCancel');
  await pg.waitForSelector('#discModal', { state: 'hidden', timeout: 5000 });
}
async function cat(pg, c) {
  await pg.click(`#discForm [data-cat="${c}"]`);
  await until(() => pg.evaluate((x) => document.querySelector(`#discForm [data-cat="${x}"]`).classList.contains('on'), c), 3000, c + ' selected');
}
const pinValue = (pg) => pg.inputValue('#discPin');
/* the one place the page keeps the employee's code between the two steps (pos.html discCode, a closure) */
const empKept = (pg) => pg.evaluate(() => window.discCode ? discCode.get() : 'no discCode');
const toastSays = (pg, want) => see(pg, '#toast', want, 6000);
/* the line holds its text: nothing cut off (spec 16) */
const fits = (pg) => pg.evaluate(() => {
  const e = document.getElementById('discErr'), g = document.createRange(); g.selectNodeContents(e);
  return { sh: e.scrollHeight, ch: e.clientHeight, lines: new Set([...g.getClientRects()].map((x) => Math.round(x.top))).size };
});
async function charge(pg, sel) {
  await pg.click(sel || '[data-pay="card"]');
  await until(async () => (await pg.isVisible('#numModal')) || (await pg.evaluate(() => !pendingPay)), 5000, 'the number window or the sale');
  if (await pg.isVisible('#numModal')) await pg.click('#numNone');
}
/* a sale on the server and the approval it carries: linked both ways */
function linked(category) {
  return sql(`select o.total_crc || '/' || o.subtotal_crc || '/' || o.discount_crc || '/' || o.discount_reason || '/' || coalesce(o.discount_by, '-') || '/' ||
                     (a.order_id = o.id) || '/' || (a.used_at is not null) || '/' ||
                     (('discount_not_verified' = any(o.flags)) or ('discount_late' = any(o.flags)))
                from orders o join discount_approvals a on a.id = o.discount_id where a.category = '${category}'`);
}
/* no text node outside a name or a company typed by a person (data-no-translate) carries an English category word */
const englishCats = (pg, sel) => pg.evaluate(([s, re]) => {
  const root = document.querySelector(s); if (!root) return 'no ' + s;
  const w = document.createTreeWalker(root, NodeFilter.SHOW_TEXT); const hits = []; let n;
  const rx = new RegExp(re);
  while ((n = w.nextNode())) {
    if (n.parentElement && n.parentElement.closest('[data-no-translate], script, style')) continue;
    if (rx.test(n.nodeValue)) hits.push(n.nodeValue.trim());
  }
  return hits;
}, [sel, EN_CAT.source]);

/* ---------- L-a: the window's fixed boxes ---------- */
async function boxes(pg) {
  return pg.evaluate(() => {
    const r = (el) => { const b = el.getBoundingClientRect(); return [b.left, b.top, b.width, b.height].map((v) => Math.round(v * 10) / 10); };
    const box = document.querySelector('#discForm');
    const field = [document.getElementById('discPin'), document.getElementById('discText')].find((e) => !e.hidden);
    return {
      pad: r(document.getElementById('discPad')), go: r(document.getElementById('discGo')), cancel: r(document.getElementById('discCancel')),
      cats: [...document.querySelectorAll('#discForm [data-cat]')].map(r), field: r(field), err: r(document.getElementById('discErr')),
      box: r(box), scroll: [box.scrollHeight, box.clientHeight, box.scrollWidth, box.clientWidth],
      page: [document.documentElement.scrollWidth, innerWidth, innerHeight],
      labels: { go: document.getElementById('discGo').textContent.trim(), cancel: document.getElementById('discCancel').textContent.trim() },
      catText: [...document.querySelectorAll('#discForm [data-cat]')].map((b) => b.textContent.replace(/\s+/g, ' ').trim()),
      catAttrs: [...document.querySelectorAll('#discForm [data-cat]')].map((b) => [b.title, b.getAttribute('aria-label') || ''].join(' ')),
      catLines: [...document.querySelectorAll('#discForm [data-cat] span')].map((sp) => { const g = document.createRange(); g.selectNodeContents(sp); return new Set([...g.getClientRects()].map((x) => Math.round(x.top))).size; }),
      catClip: [...document.querySelectorAll('#discForm [data-cat]')].map((b) => b.scrollHeight <= b.clientHeight && b.scrollWidth <= b.clientWidth),
      winText: document.getElementById('discModal').innerText,
      errFit: [document.getElementById('discErr').scrollHeight, document.getElementById('discErr').clientHeight]
    };
  });
}
function checkStep(b, ref, lang, size, step) {
  const at = ' at ' + size + ' (' + lang + '), step «' + step + '»';
  const L = lang === 'es' ? ES : EN;
  assert.deepStrictEqual(b.pad, ref.pad, '#discPad keeps its box' + at);
  assert.deepStrictEqual(b.go, ref.go, '#discGo keeps its box' + at);
  assert.deepStrictEqual(b.cancel, ref.cancel, '#discCancel keeps its box' + at);
  assert.deepStrictEqual(b.cats, ref.cats, 'the four category buttons keep their boxes' + at);
  assert.deepStrictEqual(b.field, ref.field, 'the code box (or the company box in its place) keeps its box' + at);
  assert.deepStrictEqual(b.err, ref.err, 'the message line keeps its box' + at);
  assert.deepStrictEqual(b.box, ref.box, 'the window keeps its size' + at);
  assert.deepStrictEqual(b.labels, { go: L.go, cancel: L.cancel }, 'Autorizar and Cancel keep their labels' + at);
  assert.deepStrictEqual(b.catText, L.cats, 'the four buttons read ' + L.cats.join(' · ') + at);
  assert.ok(!/%/.test(b.catText.join(' ') + b.catAttrs.join(' ')), 'no percentage on the buttons' + at);
  // proposal §3.1: each button at least 64 px high, a label of at most two lines, nothing cut off
  b.cats.forEach((c, i) => assert.ok(c[3] >= 64, 'button ' + i + ' at least 64 px high' + at + ': ' + c[3]));
  assert.ok(b.catLines.every((n) => n >= 1 && n <= 2) && b.catClip.every(Boolean), 'each label on one or two lines, not cut off' + at + ': ' + JSON.stringify([b.catLines, b.catClip]));
  assert.ok(!/%/.test(b.winText), 'no percentage anywhere in the window' + at + ': ' + b.winText);
  b.cats.forEach((c, i) => assert.ok(c[0] + c[2] <= b.pad[0], 'button ' + i + ' lies left of the keypad' + at + ' ' + JSON.stringify([c, b.pad])));
  // two columns, never stacked: the buttons sit beside the keypad, one under the other in one column
  assert.ok(b.cats[0][1] < b.pad[1] + b.pad[3] && b.pad[1] < b.cats[3][1] + b.cats[3][3], 'the buttons are beside the keypad' + at);
  for (let i = 1; i < 4; i++) assert.ok(b.cats[i][0] === b.cats[0][0] && b.cats[i][1] >= b.cats[i - 1][1] + b.cats[i - 1][3], 'the buttons are stacked in one column' + at);
  assert.ok(b.scroll[0] <= b.scroll[1] && b.scroll[2] <= b.scroll[3], 'the window never scrolls' + at + ' ' + JSON.stringify(b.scroll));
  assert.ok(b.box[1] >= 0 && b.box[1] + b.box[3] <= b.page[2] && b.box[0] >= 0 && b.box[0] + b.box[2] <= b.page[1], 'the window fits on the screen' + at);
  assert.ok(b.errFit[0] <= b.errFit[1], 'the message fits its line' + at);
}
/* the steps of proposal §5.2 L-a: none, Guía off (a message), Empleado 1 and 2, Local, Huésped, Guía 1 with the company
   box focused, Guía 2 with a page message, Guía 2, and a wrong code answered by the server */
async function walk(pg, lang, size, shots) {
  const L = lang === 'es' ? ES : EN;
  const shot = async (name) => {
    if (!shots || !SHOTS) return;
    await pg.mouse.move(1, 1);
    await pg.evaluate(() => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))));
    fs.mkdirSync(SHOTS, { recursive: true });
    await pg.screenshot({ path: path.join(SHOTS, `e2e-400-${size}-${lang}-${name}.png`) });
  };
  await openWin(pg);
  await see(pg, '#discStep', L.pick);
  const ref = await boxes(pg);
  checkStep(ref, ref, lang, size, 'none');
  assert.ok(await pg.isDisabled('#discGo'), 'Autorizar waits for a choice');
  await shot('1-sin-eleccion');
  const step = async (name) => checkStep(await boxes(pg), ref, lang, size, name);
  await cat(pg, 'guia');
  await see(pg, '#discErr', L.guiaOff);
  await step('Guía off, its text showing');
  await closeWin(pg);
  guiaOn();
  await openWin(pg);
  await cat(pg, 'empleado');
  await typeCode(pg, PINS.luis);
  await see(pg, '#discStep', L.emp);
  await step('Empleado 1');
  await pg.click('#discGo');
  await see(pg, '#discStep', L.mgr);
  await typeCode(pg, PINS.ana);
  await step('Empleado 2');
  await shot('2-empleado-2');
  await cat(pg, 'local'); await typeCode(pg, PINS.ana);
  await step('Local');
  await cat(pg, 'huesped'); await typeCode(pg, PINS.ana);
  await step('Huésped');
  await cat(pg, 'guia');
  await see(pg, '#discStep', L.company);
  assert.strictEqual(await pg.evaluate(() => document.activeElement && document.activeElement.id), 'discText', 'Guía 1: the company box has the focus');
  await pg.keyboard.type('Monteverde Tours');
  await step('Guía 1, the company box focused');
  await shot('3-guia-1');
  await pg.keyboard.press('Enter');
  await see(pg, '#discStep', L.owner);
  await typeCode(pg, PINS.dueno.slice(0, 2));
  await pg.click('#discGo');
  await see(pg, '#discErr', L.typeOwner);
  await step('Guía 2 with a page message');
  await typeCode(pg, PINS.dueno);
  await step('Guía 2');
  await shot('4-guia-2');
  await cat(pg, 'local'); await typeCode(pg, PINS.luis);
  await pg.click('#discGo');
  await see(pg, '#discErr', L.badMgr);
  await step('Local, a wrong code answered');
  await shot('5-codigo-equivocado');
  await closeWin(pg);
  return ref;
}
/* the window against the owner's image (referencia-diseno.md), at 1180 × 820 in Spanish */
async function looksLikeTheImage(pg) {
  await openWin(pg);
  await cat(pg, 'local');
  await pg.mouse.move(1, 1);   // no hover colour on the buttons
  const s = await pg.evaluate(() => {
    const cs = (el) => getComputedStyle(el), q = (x) => document.querySelector(x), r = (el) => el.getBoundingClientRect();
    const cats = [...document.querySelectorAll('#discForm [data-cat]')];
    const keys = [...document.querySelectorAll('#discPad button')];
    const left = r(q('#discForm .dcats')), right = r(q('#discPad')), line = q('#discForm .dline');
    return {
      title: q('#discTitle').textContent.trim(), titleFont: cs(q('#discTitle')).fontFamily, titleColor: cs(q('#discTitle')).color,
      lead: q('#discLead').textContent.trim(), cols: [Math.round(left.width), Math.round(right.width)],
      line: line ? [Math.round(r(line).width * 10) / 10, cs(line).backgroundColor, r(line).left > left.right, r(line).right < right.left] : null,
      icons: cats.map((b) => !!b.querySelector('svg') && cs(b.querySelector('svg')).stroke !== 'none'),
      on: cats.filter((b) => b.classList.contains('on')).map((b) => [b.dataset.cat, cs(b).backgroundColor, cs(b).color]),
      off: cats.filter((b) => !b.classList.contains('on')).map((b) => [cs(b).backgroundColor, cs(b).color, parseFloat(cs(b).borderTopWidth) >= 1 && parseFloat(cs(b).borderTopWidth) <= 1.5, cs(b).borderTopColor]),
      stepCentered: cs(q('#discStep')).textAlign, stepAbove: r(q('#discStep')).bottom <= r(q('#discPin')).top + 0.5,
      pinFull: [Math.round(r(q('#discPin')).width), Math.round(right.width)], pinDots: cs(q('#discPin')).webkitTextSecurity,
      keys: keys.map((b) => b.dataset.k), clr: !!q('#discPad [data-k="clr"]'),
      zero: [Math.round(r(q('#discPad [data-k="0"]')).width), Math.round(r(q('#discPad [data-k="1"]')).width), Math.round(r(q('#discPad [data-k="2"]')).width)],
      del: [q('#discPad [data-k="del"]').getAttribute('aria-label'), !!q('#discPad [data-k="del"] svg'),
            Math.round(r(q('#discPad [data-k="del"]')).left) === Math.round(r(q('#discPad [data-k="3"]')).left)],
      rows: [...new Set(keys.map((b) => Math.round(r(b).top)))].length,
      cancel: [r(q('#discCancel')).left < r(q('#discGo')).left, r(q('#discCancel')).width < r(q('#discGo')).width,
               cs(q('#discCancel')).color, cs(q('#discCancel')).borderTopColor],
      goStyle: [cs(q('#discGo')).backgroundColor, cs(q('#discGo')).color],
      msgPlace: r(q('#discErr')).top >= r(q('#discPad')).bottom - 0.5 && r(q('#discErr')).bottom <= r(q('#discGo')).top + 0.5,
      centered: Math.abs((r(q('#discCancel')).left + r(q('#discGo')).right) / 2 - (r(q('#discForm')).left + r(q('#discForm')).right) / 2)
    };
  });
  const ACCENT = 'rgb(30, 75, 51)', MUTED = 'rgb(201, 207, 182)', WHITE = 'rgb(255, 255, 255)';
  assert.strictEqual(s.title, ES.title, 'the image\'s title');
  assert.match(s.titleFont, /Playfair Display/, 'the title in Playfair Display');
  assert.strictEqual(s.titleColor, ACCENT, 'the title dark green');
  assert.strictEqual(s.lead, ES.leadMgr, 'the image\'s subtitle');
  assert.ok(Math.abs(s.cols[0] - s.cols[1]) <= 2, 'two equal columns: ' + s.cols);
  assert.ok(s.line && s.line[0] >= 1 && s.line[0] <= 2 && s.line[1] === MUTED && s.line[2] && s.line[3], 'a thin --muted line between the columns: ' + JSON.stringify(s.line));
  assert.deepStrictEqual(s.icons, [true, true, true, true], 'an outline icon on each button');
  assert.deepStrictEqual(s.on, [['local', ACCENT, WHITE]], 'only the selected button is filled dark green, white label');
  // the 1.5 px border of the image: Chromium draws it as 1 device pixel at a pixel ratio of 1
  s.off.forEach((o) => assert.deepStrictEqual(o, [WHITE, ACCENT, true, MUTED], 'the others light, a thin --muted border, green label'));
  assert.strictEqual(s.stepCentered, 'center', 'the step label is centred');
  assert.ok(s.stepAbove, 'the step label sits above the code box');
  assert.ok(Math.abs(s.pinFull[0] - s.pinFull[1]) <= 1, 'the code box is the right column\'s full width: ' + s.pinFull);
  assert.strictEqual(s.pinDots, 'disc', 'the code shows as dots');
  assert.deepStrictEqual(s.keys, ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0', 'del'], 'keys 1-9, 0 and ⌫');
  assert.strictEqual(s.clr, false, 'no «Limpiar» key (the image has none)');
  assert.strictEqual(s.rows, 4, 'four rows of keys');
  assert.ok(s.zero[0] > s.zero[1] + s.zero[2] - 2, '0 spans two columns: ' + s.zero);
  assert.deepStrictEqual(s.del, [ES.erase, true, true], '⌫ is an icon in the third column, read «Borrar»');
  assert.deepStrictEqual(s.cancel.slice(0, 2), [true, true], 'Cancelar on the left and narrower, Autorizar on the right and wider');
  assert.deepStrictEqual(s.cancel.slice(2), [ACCENT, MUTED], 'Cancelar outlined: --muted border, green text');
  assert.deepStrictEqual(s.goStyle, [ACCENT, WHITE], 'Autorizar filled dark green, white text');
  assert.ok(s.msgPlace, 'the message line sits between the keypad and the buttons');
  assert.ok(s.centered <= 2, 'the bottom row is centred under both columns: ' + s.centered);
  await closeWin(pg);
}
function layoutTest(w, h) {
  const size = w + 'x' + h;
  return {
    name: 'L-a ' + size + ': in Spanish and English the keypad, Autorizar and Cancelar keep one box at every step (a message showing too), the four buttons left of the keypad with no %, nothing scrolls' + (w === 1180 ? '; the look of the owner\'s image' : ''),
    run: async ({ browser }) => {
      testMenu();
      for (const lang of ['es', 'en']) {
        const pg = await till(browser, { lang, viewport: { width: w, height: h } });
        await tap(pg, 'T Latte'); await tap(pg, 'T Brownie');
        if (w === 1180 && lang === 'es') await looksLikeTheImage(pg);
        await walk(pg, lang, size, w === 1180 && lang === 'es');
        noCodeLeak(pg);
        await noCodeKept(pg);
        assert.deepStrictEqual(pg.errors, []);
        sql(`delete from public.settings where key = 'pos_discount_guia'`);   // the next language starts with Guía off again
      }
    }
  };
}

/* ---------- L-b: every message of the line, at 360 × 640 in Spanish ---------- */
const UNTIL = '2026-11-04T21:41:20.000Z', AT = '15:42';   // Costa Rica 15:41:20, rounded up to the minute
function lbCases() {
  const c = [];
  const wrong = (error, step, cat, base) => {
    c.push({ cat, ans: { error, step, warn: null, blocked: null, until: null, wait: null, wait_s: null }, want: base });
    for (const w of Object.keys(ES.warn)) c.push({ cat, ans: { error, step, warn: w, blocked: null, until: null, wait: null, wait_s: null }, want: base + ' ' + ES.warn[w] });
  };
  wrong('bad_pin', 'manager', 'local', ES.badMgr);
  wrong('bad_pin', 'owner', 'guia', ES.badOwner);
  wrong('bad_employee', 'employee', 'empleado', ES.badEmp);
  const blocked = (wait, want, stop) => c.push({ cat: 'local', ans: { error: 'bad_pin', step: 'manager', warn: stop ? null : 'wait_1m', blocked: stop ? 'stopped' : 'wait', until: UNTIL, wait, wait_s: 900 }, want, state: true });
  blocked('30s', ES.wait30); blocked('1m', ES.waitAt(AT)); blocked('5m', ES.waitAt(AT)); blocked('10m', ES.waitAt(AT)); blocked('stop', ES.stopped, true);
  c.push({ cat: 'empleado', ans: { error: 'bad_employee', step: 'employee', warn: null, blocked: 'wait', until: UNTIL, wait: '10m', wait_s: 900 }, want: ES.waitAt(AT), state: true });
  const st = (error, extra, want) => c.push({ cat: 'local', ans: Object.assign({ error }, extra), want, state: true });
  st('till_wait', { until: UNTIL, wait: '30s', wait_s: 900 }, ES.wait30);
  st('till_wait', { until: UNTIL, wait: '5m', wait_s: 900 }, ES.waitAt(AT));
  st('till_stopped', { until: UNTIL, wait: 'stop', wait_s: 900 }, ES.stopped);
  st('till_not_enrolled', {}, ES.notEnrolled); st('till_ended', {}, ES.ended); st('no_session', {}, ES.noSession);
  const one = (cat, ans, want) => c.push({ cat, ans, want });
  one('empleado', { error: 'daily_used', beneficiary: 'Luis', pending: false }, ES.daily);
  // the longest station a till sends (pos.html keeps 24 characters)
  one('empleado', { error: 'daily_used', beneficiary: 'Luis', pending: true, station: 'Barra de la terraza alta', until: UNTIL }, ES.daily + ' ' + ES.pending('Barra de la terraza alta', AT));
  one('empleado', { error: 'not_self' }, ES.notSelf);
  // these two change what the page knows of the till (owner_ready, guia_enabled): the window is opened again after each
  c.push({ cat: 'guia', ans: { error: 'no_owner' }, want: ES.noOwner, state: true });
  c.push({ cat: 'guia', ans: { error: 'guia_off' }, want: ES.guiaOff, state: true });
  one('guia', { error: 'missing_company' }, ES.typeCompany);
  one('empleado', { error: 'missing_employee' }, ES.typeEmp);
  for (const [e, t] of [['already_discounted', ES.stacked], ['has_parts', ES.hasParts], ['combo_first', ES.combo], ['changed', ES.changed],
                        ['not_found', ES.notFound], ['cancelled', ES.cancelled], ['already_paid', ES.alreadyPaid], ['refund_first', ES.refundFirst],
                        ['no_account', ES.noAccount], ['bad_request', ES.generic], ['bad_discount', ES.generic], ['empty', ES.empty],
                        ['discount_used', ES.discUsed], ['discount_expired', ES.discExpired], ['discount_not_approved', ES.discNotApproved],
                        ['no_request', '']]) one('local', { error: e }, t);
  return c;
}
/* the till's own state when the window opens (descuento_estado), each with its text */
function lbStates() {
  const reg = (t) => ({ ok: true, owner_ready: true, guia_enabled: true, session: true,
                        till: Object.assign({ registered: true, slot: 1, station: 'Caja', by: 'Ana', since: '2026-11-04T16:00:00Z', state: 'ok', until: null, wait: null, wait_s: null, warn: null }, t) });
  const s = [
    { st: { ok: true, owner_ready: true, guia_enabled: true, session: true, till: { registered: false, ended: false } }, want: ES.notEnrolled },
    { st: { ok: true, owner_ready: true, guia_enabled: true, session: true, till: { registered: false, ended: true } }, want: ES.ended },
    { st: { ok: true, owner_ready: true, guia_enabled: true, session: false, till: { registered: false, ended: false } }, want: ES.noSession },
    { st: reg({ state: 'wait', until: UNTIL, wait: '30s', wait_s: 900, warn: 'wait_1m' }), want: ES.wait30 },
    { st: reg({ state: 'wait', until: UNTIL, wait: '1m', wait_s: 900, warn: 'wait_5m' }), want: ES.waitAt(AT) },
    { st: reg({ state: 'wait', until: UNTIL, wait: '10m', wait_s: 900, warn: 'stop' }), want: ES.waitAt(AT) },
    // precedence (mecanismo §10.1, §13.3 C-i): a stopped till with Guía off shows the stop text for Guía and for Local
    { st: Object.assign(reg({ state: 'stopped', until: UNTIL, wait: 'stop', wait_s: 900 }), { guia_enabled: false }), want: ES.stopped, guia: true },
    { st: { ok: false, error: 'no_account' }, want: ES.noAccount },
    { missing: true, want: ES.dbUpdate }
  ];
  for (const w of Object.keys(ES.warn)) s.push({ st: reg({ warn: w }), want: ES.warn[w] });
  return s;
}

/* ---------- the tests ---------- */
module.exports.tests = [
  layoutTest(1180, 820), layoutTest(820, 1180), layoutTest(390, 844), layoutTest(360, 640),
  {
    name: 'L-b: at 360 × 640 in Spanish every server answer and page message shows its lang.js text and fits the line; the code box is empty after each',
    run: async ({ browser }) => {
      testMenu(); guiaOn();
      bill(1, 'Mesa Sin Red', [['T Latte', 2000, 2]]);
      const pg = await till(browser, { viewport: { width: 360, height: 640 } });
      let answer = null, state = null, drop = false;
      await pg.route(/\/rest\/v1\/rpc\/descuento_autorizar/, (r) => (drop ? r.abort('connectionreset') : answer
        ? r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(Object.assign({ ok: false }, answer)) }) : r.fallback()));
      await pg.route(/\/rest\/v1\/rpc\/descuento_estado/, (r) => (!state ? r.fallback()
        : state.missing ? r.fulfill({ status: 404, contentType: 'application/json', body: JSON.stringify({ code: 'PGRST202', message: 'Could not find the function public.descuento_estado(p_station) in the schema cache', details: null, hint: null }) })
          : r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(state) })));
      await pg.route(/\/rest\/v1\/rpc\/descuento_caja_volver/, (r) => r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ ok: true, already: true, station: 'Caja', slot: 1 }) }));
      await tap(pg, 'T Latte'); await tap(pg, 'T Brownie');
      const seen = [];
      const check = async (what, want) => {
        await see(pg, '#discErr', want);
        const f = await fits(pg);
        seen.push([what, want.length, f.lines]);
        assert.ok(f.sh <= f.ch, 'the line holds «' + want + '» (' + what + '): ' + f.sh + ' > ' + f.ch);
        assert.strictEqual(await pinValue(pg), '', 'the code box is empty after the answer (' + what + ')');
      };
      // the page's own checks, nothing sent
      await openWin(pg);
      await cat(pg, 'empleado'); await pg.click('#discGo'); await check('page: no employee code', ES.typeEmp);
      await cat(pg, 'local'); await typeCode(pg, '12'); await pg.click('#discGo'); await check('page: short manager code', ES.typeMgr);
      await cat(pg, 'guia'); await pg.click('#discGo'); await check('page: no company', ES.typeCompany);
      await pg.fill('#discText', ' X '); await pg.click('#discGo'); await check('page: a company of one character', ES.typeCompany);
      await see(pg, '#discStep', ES.company);
      await pg.fill('#discText', 'Selvatura'); await pg.click('#discGo'); await see(pg, '#discStep', ES.owner);
      await pg.click('#discGo'); await check('page: no owner code', ES.typeOwner);
      assert.strictEqual(sent(pg, 'descuento_autorizar').length, 0, 'the page\'s own checks send nothing');
      // offline at the moment of sending
      await cat(pg, 'local'); await typeCode(pg, PINS.ana);
      await pg.context().setOffline(true);
      await pg.click('#discGo'); await see(pg, '#discErr', ES.offline);
      await pg.context().setOffline(false);
      { const f = await fits(pg); assert.ok(f.sh <= f.ch, 'the offline text fits'); }
      // every answer of descuento_autorizar (api-0038 §4.2, §10.1)
      let open = true;
      for (const k of lbCases()) {
        if (!open) { await openWin(pg); open = true; }
        answer = k.ans;
        await cat(pg, k.cat);
        if (k.cat === 'empleado') { await typeCode(pg, PINS.luis); await pg.click('#discGo'); await see(pg, '#discStep', ES.mgr); }
        if (k.cat === 'guia') {
          if (!(await pg.inputValue('#discText'))) await pg.fill('#discText', 'Selvatura');
          await pg.click('#discGo'); await see(pg, '#discStep', ES.owner);
        }
        await typeCode(pg, PINS.ana);
        const n0 = sent(pg, 'descuento_autorizar').length;
        await pg.click('#discGo');
        await until(() => sent(pg, 'descuento_autorizar').length > n0, 5000, 'the call for ' + k.ans.error);
        if (k.want) await check(k.ans.error + (k.ans.warn ? '+' + k.ans.warn : '') + (k.ans.blocked ? ' blocked ' + k.ans.wait : ''), k.want);
        else { await pg.waitForFunction(() => !disc.busy); assert.strictEqual(await text(pg, '#discErr'), '', k.ans.error + ': no text'); }
        if (k.state) {
          assert.ok(await pg.isDisabled('#discGo'), 'Autorizar disabled while the till waits or is stopped (' + k.ans.error + ')');
          await closeWin(pg); open = false;
        }
      }
      answer = null;
      if (open) await closeWin(pg);
      // the till's state when the window opens (mecanismo §10.1 (1)); Autorizar off for each state that keeps codes out
      for (const s of lbStates()) {
        state = s.missing ? { missing: true } : s.st;
        await pg.click('#discBtn');
        await pg.waitForSelector('#discModal:not([hidden])');
        await check('estado ' + (s.missing ? 'missing' : JSON.stringify(s.st.till || s.st.error)), s.want);
        if (s.guia) { await cat(pg, 'guia'); await check('estado, Guía tapped while off', s.want); }
        await cat(pg, 'local');
        if (s.st && s.st.ok && s.st.till && s.st.till.registered && s.st.till.state === 'ok') {
          // what the next mistake costs is an answer's text: a tap clears it, and Autorizar stays on
          await see(pg, '#discErr', '');
          assert.ok(!(await pg.isDisabled('#discGo')), 'a warning alone leaves Autorizar on');
        } else {
          await check('estado, Local tapped (a till-state text never goes by tapping a category)', s.want);
          assert.ok(await pg.isDisabled('#discGo'), 'Autorizar off: ' + s.want);
        }
        await closeWin(pg);
      }
      state = null;
      // no answer at all (ticket): asked once more after 2 seconds, then the text; nothing on the ticket
      drop = true;
      await openWin(pg);
      await cat(pg, 'local'); await typeCode(pg, PINS.ana); await pg.click('#discGo');
      await see(pg, '#discErr', ES.net, 10000);
      await check('no answer, ticket', ES.net);
      assert.ok(await pg.isHidden('#discRow'), 'nothing on the ticket');
      await closeWin(pg);
      // no answer at all (bill)
      await pg.evaluate((x) => openTab(x), BILL(1));
      await pg.waitForSelector('#tabModal:not([hidden])');
      await pg.click('#tabDisc');
      await pg.waitForSelector('#discModal:not([hidden])');
      await pg.waitForFunction(() => window.disc && disc.st);
      await cat(pg, 'local'); await typeCode(pg, PINS.ana); await pg.click('#discGo');
      await see(pg, '#discErr', ES.netBill, 10000);
      await check('no answer, bill', ES.netBill);
      console.log('        L-b: ' + seen.length + ' texts checked; the longest: ' + seen.sort((a, b) => b[2] - a[2] || b[1] - a[1]).slice(0, 4).map((x) => x[0] + ' ' + x[1] + ' chars, ' + x[2] + ' lines').join('; '));
      noCodeLeak(pg);
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'C-a: codes as dots, a key pressed by a script and a filled-in code type nothing, Empleado sends nothing at step 1, the employee code is gone after another category, Cancel or 2 minutes; C-k nothing kept',
    run: async ({ browser }) => {
      testMenu();
      const pg = await till(browser, { clock: true });
      await tap(pg, 'T Latte'); await tap(pg, 'T Brownie');
      const k1 = await storeKeys(pg);
      await openWin(pg);
      assert.deepStrictEqual(await pg.evaluate(() => { const i = document.getElementById('discPin'); return [i.type, getComputedStyle(i).webkitTextSecurity, i.disabled]; }),
        ['text', 'disc', true], 'the code box: a text box drawn as dots, off until a choice');
      // Local: keys pressed by a script, and a code put in by the browser
      await cat(pg, 'local');
      await until(async () => !(await pg.isDisabled('#discGo')), 8000, 'Autorizar ready');
      await pg.evaluate((p) => { for (const d of p) document.querySelector(`#discPad button[data-k="${d}"]`).click(); }, PINS.ana);
      assert.strictEqual(await pinValue(pg), '', 'the keys pressed by a script type nothing');
      await pg.evaluate((p) => { const i = document.getElementById('discPin'); i.value = p; i.dispatchEvent(new Event('input', { bubbles: true })); }, PINS.ana);
      assert.strictEqual(await pinValue(pg), '', 'a code filled in (value and an input event) is wiped at once');
      await pg.evaluate((p) => { document.getElementById('discPin').value = p; }, PINS.ana);
      await pg.click('#discGo');
      await pg.keyboard.press('Enter');
      await until(async () => (await pinValue(pg)) === '', 3000, 'the filled-in code wiped');
      assert.strictEqual(sent(pg, 'descuento_autorizar').length, 0, 'a code nobody typed is never sent');
      // never more than 8 digits (maxlength 8), and ⌫ erases one digit
      await typeCode(pg, '123456789');
      assert.strictEqual(await pinValue(pg), '12345678', 'the box takes 8 digits at most');
      for (let i = 0; i < 8; i++) await pg.click('#discPad button[data-k="del"]');
      assert.strictEqual(await pinValue(pg), '', '⌫ empties it digit by digit');
      await typeCode(pg, '123');
      await pg.click('#discPad button[data-k="del"]');
      assert.strictEqual(await pinValue(pg), '12', '⌫ erases one digit');
      // Empleado: the employee code goes nowhere at step 1; the box is emptied at the step change
      await cat(pg, 'empleado');
      assert.strictEqual(await pinValue(pg), '', 'the box is emptied when the category changes');
      await typeCode(pg, PINS.luis);
      assert.strictEqual(await pinValue(pg), PINS.luis, 'typed with the window\'s own keys');
      const before = pg.rpcs.length;
      await pg.click('#discGo');
      await see(pg, '#discStep', ES.mgr);
      await see(pg, '#discSub', 'Pedido ₡3 500');
      assert.strictEqual(await pinValue(pg), '', 'the box is emptied at the step change');
      await pg.waitForTimeout(300);
      assert.deepStrictEqual(pg.rpcs.slice(before).map((r) => r.fn), [], 'Empleado makes no request at step 1');
      assert.strictEqual(await empKept(pg), PINS.luis, 'the employee code is kept in memory only');
      await noCodeKept(pg);
      // another category: the employee code is gone (Local's call carries no employee code)
      await cat(pg, 'local');
      await see(pg, '#discStep', ES.mgr);
      assert.strictEqual(await empKept(pg), null, 'the employee code wiped by the category change');
      await typeCode(pg, PINS.ana); await pg.click('#discGo');
      await pg.waitForSelector('#discModal', { state: 'hidden', timeout: 8000 });
      let b = bodies(pg, 'descuento_autorizar').pop();
      assert.strictEqual(b.p_category, 'local'); assert.ok(!('p_employee_pin' in b) || b.p_employee_pin === null, 'no employee code after a category change');
      assert.ok(!pinIn(JSON.stringify(b), PINS.luis), 'Luis\'s code is in no request after the category change');
      await see(pg, '#discLbl', 'Descuento Local');
      const freed = pg.waitForResponse((r) => /rpc\/descuento_liberar/.test(r.url()));
      await pg.click('#discX');
      await freed;
      // Cancel: gone too (the next Empleado starts at its step 1, and its call carries the code typed after Cancel)
      await openWin(pg);
      await cat(pg, 'empleado'); await typeCode(pg, PINS.luis); await pg.click('#discGo'); await see(pg, '#discStep', ES.mgr);
      await closeWin(pg);
      assert.strictEqual(await pinValue(pg), '', 'Cancel empties the box');
      assert.strictEqual(await empKept(pg), null, 'the employee code wiped by Cancel');
      await openWin(pg);
      await cat(pg, 'empleado');
      await see(pg, '#discStep', ES.emp);
      await typeCode(pg, PINS.ana); await pg.keyboard.press('Enter'); await see(pg, '#discStep', ES.mgr);   // Enter continues too (Q8)
      await typeCode(pg, PINS.ana); await pg.click('#discGo');
      await see(pg, '#discErr', ES.notSelf);
      b = bodies(pg, 'descuento_autorizar').pop();
      assert.strictEqual(b.p_employee_pin, PINS.ana, 'the employee code sent is the one typed after Cancel');
      assert.ok(!pinIn(JSON.stringify(b), PINS.luis), 'Luis\'s code went with Cancel');
      // the 2-minute timer (page.clock): kept at 1 min 57 s, gone at 2 min, the window back at the employee step
      await cat(pg, 'empleado'); await typeCode(pg, PINS.luis); await pg.click('#discGo'); await see(pg, '#discStep', ES.mgr);
      await pg.clock.fastForward(117000);
      await pg.waitForTimeout(100);
      assert.strictEqual(await text(pg, '#discStep'), ES.mgr, 'still kept before 2 minutes');
      assert.strictEqual(await empKept(pg), PINS.luis);
      await pg.clock.fastForward(4000);
      await see(pg, '#discStep', ES.emp);
      assert.strictEqual(await empKept(pg), null, 'the employee code wiped after 2 minutes');
      assert.strictEqual(await pinValue(pg), '', 'the box empty after the 2 minutes');
      const n0 = sent(pg, 'descuento_autorizar').length;
      await typeCode(pg, PINS.marta); await pg.click('#discGo'); await see(pg, '#discStep', ES.mgr);
      await typeCode(pg, PINS.ana); await pg.click('#discGo');
      await pg.waitForSelector('#discModal', { state: 'hidden', timeout: 8000 });
      b = bodies(pg, 'descuento_autorizar').slice(n0);
      assert.strictEqual(b.length, 1); assert.strictEqual(b[0].p_employee_pin, PINS.marta, 'the code typed after the 2 minutes');
      assert.ok(!pinIn(JSON.stringify(b), PINS.luis), 'Luis\'s code is in no request after the 2 minutes');
      await see(pg, '#discLbl', 'Descuento Empleado · Marta');
      assert.strictEqual(sql(`select beneficiary_name from discount_approvals where category = 'empleado' and freed_at is null`), 'Marta');
      noCodeLeak(pg);
      await noCodeKept(pg);
      const keys = await storeKeys(pg);
      assert.ok(k1.local.includes('hg-disc-till') && !pg.keys0.local.includes('hg-disc-till'), 'the device key, stored when the till was registered');
      assert.match(await pg.evaluate(() => JSON.parse(localStorage.getItem('hg-disc-till')).key), /^[0-9a-f]{64}$/, 'the device key: 64 hex');
      assert.deepStrictEqual(keys.local.filter((k) => !k1.local.includes(k)), ['hg-pos-disc-hold'],
        'the window stored nothing new but the hold of the authorization on the ticket (ids only)');
      assert.deepStrictEqual(keys.session, k1.session, 'nothing new in sessionStorage');
      const hold = JSON.parse(await pg.evaluate(() => localStorage.getItem('hg-pos-disc-hold')));
      assert.deepStrictEqual(hold.map((h) => Object.keys(h).sort().join(',')), ['at,id,load,request_id'], 'the hold keeps ids only');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'E-a Empleado end to end (ticket row, total, the sale linked on the server), again → «Descuento diario ya utilizado», self-authorization refused; T-a never stacked; T-b lines locked',
    run: async ({ browser }) => {
      testMenu();
      const pg = await till(browser);
      await tap(pg, 'T Latte'); await tap(pg, 'T Brownie');
      await openWin(pg);
      await see(pg, '#discLead', ES.leadMgr);
      await see(pg, '#discSub', 'Pedido ₡3 500');
      await cat(pg, 'empleado');
      await see(pg, '#discStep', ES.emp);
      await typeCode(pg, PINS.luis); await pg.click('#discGo');
      await see(pg, '#discStep', ES.mgr);
      assert.strictEqual(sent(pg, 'descuento_autorizar').length, 0, 'nothing sent at the employee step');
      // a staff code at the manager step: refused, and the manager may type again; the employee's code stays (proposal §3.3)
      await typeCode(pg, PINS.marta); await pg.click('#discGo');
      await see(pg, '#discErr', ES.badMgr);
      await see(pg, '#discStep', ES.mgr);
      assert.strictEqual(await pinValue(pg), '', 'the box empty after the answer');
      await typeCode(pg, PINS.ana); await pg.click('#discGo');
      await pg.waitForSelector('#discModal', { state: 'hidden', timeout: 8000 });
      await see(pg, '#discLbl', 'Descuento Empleado · Luis');
      assert.strictEqual(await pg.getAttribute('#discLbl', 'title'), 'Autorizado por Ana', 'the row says who authorized it');
      assert.strictEqual(await pg.evaluate(() => document.querySelector('#discLbl [data-no-translate]').textContent), ' · Luis', 'the name in a data-no-translate span');
      await see(pg, '#subAmt', '₡3 500'); await see(pg, '#discAmt', '−₡1 050'); await see(pg, '#totalAmt', '₡2 450');
      assert.ok(!/%/.test((await text(pg, '#discRow')) + (await pg.getAttribute('#discLbl', 'title'))), 'no percentage on the ticket\'s discount row');
      await toastSays(pg, 'Descuento aprobado por Ana');
      const [a0, a] = bodies(pg, 'descuento_autorizar');
      assert.deepStrictEqual([a0.p_pin, a0.p_employee_pin], [PINS.marta, PINS.luis], 'the refused try carried both codes');
      assert.deepStrictEqual([a.p_category, a.p_pin, a.p_employee_pin, a.p_subtotal, /^[0-9a-f-]{36}$/.test(a.p_request_id)], ['empleado', PINS.ana, PINS.luis, 3500, true],
        'the retry carries the same employee code, both codes in one call, the subtotal and a request id');
      assert.notStrictEqual(a.p_request_id, a0.p_request_id, 'each attempt has its own request id');
      // T-a: never stacked
      const n0 = pg.rpcs.length;
      await pg.click('#discBtn');
      await toastSays(pg, ES.stacked);
      assert.ok(await pg.isHidden('#discModal'), 'the window does not open on a discounted order');
      await pg.waitForTimeout(300);
      assert.deepStrictEqual(pg.rpcs.slice(n0).filter((r) => /^descuento_/.test(r.fn || '')).map((r) => r.fn), [], 'and nothing is asked of the server');
      // T-b: the lines are locked
      await pg.evaluate(() => { window.__toasts = []; });
      await pg.locator('#lines .line', { hasText: 'T Latte' }).locator('button', { hasText: '+' }).click();
      await pg.locator('#lines .line', { hasText: 'T Latte' }).locator('button', { hasText: '−' }).click();
      await tap(pg, 'T Brownie');
      await toastSays(pg, ES.locked);
      assert.deepStrictEqual(await pg.evaluate(() => window.__toasts), Array(3).fill('Remove the discount to change the order.'), '+, − and a product tap each answer «Quite el descuento…»');
      assert.deepStrictEqual(await pg.evaluate(() => ticket.map((l) => l.name + '×' + l.qty)), ['T Latte×1', 'T Brownie×1'], 'the lines are unchanged');
      await see(pg, '#totalAmt', '₡2 450');
      // charged: linked on the server
      await charge(pg);
      await until(() => linked('empleado') === '2450/3500/1050/Employee/Ana/true/true/false', 10000, 'the sale linked to the approval');
      assert.strictEqual(await pg.evaluate(() => localStorage.getItem('hg-pos-disc-hold')), null, 'no hold once the sale carries it');
      // the same employee again today
      await tap(pg, 'T Latte');
      await openWin(pg);
      await cat(pg, 'empleado'); await typeCode(pg, PINS.luis); await pg.click('#discGo'); await see(pg, '#discStep', ES.mgr);
      await typeCode(pg, PINS.ana); await pg.click('#discGo');
      await see(pg, '#discErr', ES.daily);
      await see(pg, '#discStep', ES.emp);
      assert.strictEqual(await pinValue(pg), '', 'the box empty after the answer');
      // self-authorization: Ana as the employee and the manager
      await typeCode(pg, PINS.ana); await pg.click('#discGo'); await see(pg, '#discStep', ES.mgr);
      await typeCode(pg, PINS.ana); await pg.click('#discGo');
      await see(pg, '#discErr', ES.notSelf);
      assert.strictEqual(sql(`select count(*) from audit_log where action = 'discount_code_wrong'`), '1', 'only Marta\'s code at the manager step counted; daily_used and not_self do not');
      await closeWin(pg);
      assert.ok(await pg.isHidden('#discRow'), 'nothing on the new ticket');
      assert.deepStrictEqual(await englishCats(pg, '.ticket'), [], 'no English category word on the ticket');
      noCodeLeak(pg);
      await noCodeKept(pg);
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'E-a Local and Huésped: Luis refused, Ana approves, each linked; T-c parked by «Añadir productos» on a bill, charged linked, never let go; S-a a reload lets a pending approval go',
    run: async ({ browser }) => {
      testMenu();
      bill(2, 'Mesa Doce', [['T Latte', 2000, 1]]);
      const pg = await till(browser);
      // Local
      await tap(pg, 'T Latte'); await tap(pg, 'T Brownie');
      await openWin(pg);
      await cat(pg, 'local');
      await see(pg, '#discStep', ES.mgr);
      await typeCode(pg, PINS.luis); await pg.click('#discGo');
      await see(pg, '#discErr', ES.badMgr);
      assert.strictEqual(await pinValue(pg), '', 'the box empty after the answer');
      await typeCode(pg, PINS.ana); await pg.click('#discGo');
      await pg.waitForSelector('#discModal', { state: 'hidden', timeout: 8000 });
      await see(pg, '#discLbl', 'Descuento Local');
      await see(pg, '#discAmt', '−₡350'); await see(pg, '#totalAmt', '₡3 150');
      // T-c: parked while adding to another bill, then charged
      await pg.evaluate((x) => openTab(x), BILL(2));
      await pg.waitForSelector('#tabModal:not([hidden])');
      await pg.click('#tabAdd');
      await pg.waitForSelector('#addBar:not([hidden])');
      assert.ok(await pg.isHidden('#discRow'), 'the parked order\'s discount is not on the bill being added to');
      await pg.click('#addCancel');
      await pg.waitForSelector('#tabModal:not([hidden])');
      await pg.click('#tabClose');
      await see(pg, '#discLbl', 'Descuento Local');
      await see(pg, '#totalAmt', '₡3 150');
      await charge(pg);
      await until(() => linked('local') === '3150/3500/350/Local/Ana/true/true/false', 10000, 'the Local sale linked');
      // Huésped
      await tap(pg, 'T Latte'); await tap(pg, 'T Brownie');
      await openWin(pg);
      await cat(pg, 'huesped');
      await typeCode(pg, PINS.luis); await pg.click('#discGo');
      await see(pg, '#discErr', ES.badMgr);
      await typeCode(pg, PINS.ana); await pg.click('#discGo');
      await pg.waitForSelector('#discModal', { state: 'hidden', timeout: 8000 });
      await see(pg, '#discLbl', 'Descuento Huésped');
      await see(pg, '#totalAmt', '₡3 150');
      await charge(pg, '[data-pay="sinpe"]');
      await until(() => linked('huesped') === '3150/3500/350/Hotel guest/Ana/true/true/false', 10000, 'the Huésped sale linked');
      assert.strictEqual(sent(pg, 'descuento_liberar').length, 0, 'T-c: parking never let the Local approval go');
      assert.strictEqual(sql(`select count(*) from audit_log where action = 'discount_code_wrong'`), '2', 'Luis\'s two codes counted');
      noCodeLeak(pg);
      // S-a: a reload with an approval on the ticket (not sold yet) lets it go
      await tap(pg, 'T Latte');
      await openWin(pg);
      await cat(pg, 'local'); await typeCode(pg, PINS.ana); await pg.click('#discGo');
      await pg.waitForSelector('#discModal', { state: 'hidden', timeout: 8000 });
      await see(pg, '#discLbl', 'Descuento Local');
      const pend = sql(`select id from discount_approvals where category = 'local' and order_id is null`);
      const freed = pg.waitForResponse((r) => /rpc\/descuento_liberar/.test(r.url()), { timeout: 15000 });
      await pg.reload({ waitUntil: 'domcontentloaded' });
      await freed;
      await until(() => sql(`select freed_how from discount_approvals where id = '${pend}'`) === 'released', 8000, 'the pending approval let go');
      await pg.waitForFunction(() => document.querySelectorAll('.pbtn').length > 0, null, { timeout: 15000 });
      await until(() => pg.evaluate(() => localStorage.getItem('hg-pos-disc-hold') === null), 5000, 'the hold dropped');
      assert.ok(await pg.isHidden('#discRow'), 'nothing on the ticket after the reload');
      assert.strictEqual(sql(`select string_agg(coalesce(freed_how, 'kept'), ',' order by category) from discount_approvals where order_id is not null`), 'kept,kept', 'the sold approvals are not let go');
      await noCodeKept(pg);
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'E-a Guía Turista (on): the company typed, Ana refused, the owner\'s code → ₡0, only «Registrar cortesía», the receipt and IVA ₡0; adjustment 1: no unlock, no owner area, the time clock still asks; E-b Spanish only',
    run: async ({ browser }) => {
      testMenu(); guiaOn();
      const owner0 = sql(`select failed_pins || '/' || coalesce(locked_until::text, '-') from staff where id = '${STAFF.dueno}'`);
      const pg = await till(browser);
      const unlocks0 = sql(`select count(*) from access_unlocks`), opens0 = sql(`select count(*) from audit_log where action in ('access_open', 'access_unlock')`);
      await tap(pg, 'T Latte'); await tap(pg, 'T Brownie');
      const k1 = await storeKeys(pg);
      await openWin(pg);
      await cat(pg, 'guia');
      await see(pg, '#discLead', ES.leadOwner);
      await see(pg, '#discStep', ES.company);
      assert.ok(await pg.isVisible('#discText') && await pg.isHidden('#discPin'), 'the company box in the code box\'s place');
      assert.ok(await pg.evaluate(() => document.getElementById('discPad').classList.contains('off') && [...document.querySelectorAll('#discPad button')].every((b) => b.disabled)), 'the keypad dimmed and off');
      await pg.keyboard.type('Tour guide');
      await pg.keyboard.press('Enter');
      await see(pg, '#discStep', ES.owner);
      await see(pg, '#discSub', 'Empresa: Tour guide · Pedido ₡3 500');
      // tapping Guía again goes back to its first step and keeps the company typed (ui-plan U1, referencia-diseno.md)
      await cat(pg, 'guia');
      await see(pg, '#discStep', ES.company);
      assert.strictEqual(await pg.inputValue('#discText'), 'Tour guide', 'the company kept');
      await pg.click('#discGo');
      await see(pg, '#discStep', ES.owner);
      assert.strictEqual(await pg.evaluate(() => [...document.querySelectorAll('#discSub [data-no-translate]')].map((e) => e.textContent).join('|')), 'Tour guide', 'the company as typed, never translated');
      await typeCode(pg, PINS.ana); await pg.click('#discGo');
      await see(pg, '#discErr', ES.badOwner);
      await typeCode(pg, PINS.dueno); await pg.click('#discGo');
      await pg.waitForSelector('#discModal', { state: 'hidden', timeout: 8000 });
      await see(pg, '#discLbl', 'Cortesía Guía Turista · Tour guide');
      assert.strictEqual(await pg.getAttribute('#discLbl', 'title'), 'Autorizado por Dueño');
      await see(pg, '#totalAmt', '₡0'); await see(pg, '#ivaAmt', '₡0'); await see(pg, '#discAmt', '−₡3 500');
      assert.ok(await pg.isVisible('#courtesyBtn'), '«Registrar cortesía» shows');
      assert.strictEqual(await text(pg, '#courtesyBtn'), ES.courtesy);
      assert.strictEqual(await pg.locator('#payRow [data-pay]:visible').count(), 0, 'only «Registrar cortesía»: no other way to pay');
      assert.ok(await pg.isDisabled('#sendBtn'), '«Cobrar después» off for a courtesy');
      const g = bodies(pg, 'descuento_autorizar').pop();
      assert.deepStrictEqual([g.p_category, g.p_company, g.p_pin], ['guia', 'Tour guide', PINS.dueno]);
      // adjustment 1 (build-plan L3, mecanismo C-j): the owner's code opened nothing, now and at the end of the test
      const nothingOpened = async (when) => {
        assert.deepStrictEqual(pg.rpcs.filter((r) => /^access_(unlock|open)/.test(r.fn || '')).map((r) => r.fn), [], 'the page never called access_unlock (' + when + ')');
        assert.strictEqual(sql(`select count(*) from access_unlocks`), unlocks0, 'no unlock row made (' + when + ')');
        assert.strictEqual(sql(`select count(*) from audit_log where action in ('access_open', 'access_unlock')`), opens0, 'no owner areas opened in the log (' + when + ')');
        assert.strictEqual(sql(`select failed_pins || '/' || coalesce(locked_until::text, '-') from staff where id = '${STAFF.dueno}'`), owner0, 'the owner\'s 0033 counter untouched (' + when + ')');
        assert.deepStrictEqual(await pg.evaluate(() => [localStorage.getItem('hg-unlock'), sessionStorage.getItem('hg-unlock'), localStorage.getItem('hg-unlock-who'), document.querySelectorAll('.hga-pill').length]),
          [null, null, null, 0], 'no unlock token, no one who opened, no owner-areas notice (' + when + ')');
      };
      await nothingOpened('right after the approval');
      const area = await pg.evaluate(() => ({
        pill: document.querySelectorAll('.hga-pill').length,
        open: [...document.querySelectorAll('[data-owner]')].filter((a) => !a.hidden && !a.classList.contains('hga-locked')).map((a) => a.textContent),
        level: window.HG_ACCESS && HG_ACCESS.state() ? HG_ACCESS.state().level || null : null,
        // access.js keeps an unlock in 'hg-unlock' ({token, …}) and who opened in 'hg-unlock-who' ('hg-unlock-login' only names the login)
        stored: (() => { const o = []; for (const s of [localStorage, sessionStorage]) for (let i = 0; i < s.length; i++) if (/^hg-unlock(-who)?$/.test(s.key(i)) || /"token"/.test(s.getItem(s.key(i)) || '')) o.push(s.key(i)); return o; })()
      }));
      assert.deepStrictEqual(area, { pill: 0, open: [], level: null, stored: [] }, 'no owner area on the POS, no unlock token in storage');
      const ks = await storeKeys(pg);
      assert.deepStrictEqual(ks.local.filter((k) => !k1.local.includes(k)), ['hg-pos-disc-hold'], 'the courtesy stored nothing but the hold of its approval');
      assert.deepStrictEqual(ks.session, k1.session, 'nothing new in sessionStorage');
      const sess = await pg.evaluate(() => JSON.parse(localStorage.getItem('sb-127-auth-token')));
      const st = await (await fetch(API + '/rest/v1/rpc/access_state', { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + sess.access_token }, body: '{}' })).json();
      assert.ok(!st.level, 'the server gives this sign-in no access level: ' + JSON.stringify(st));
      // E-b on the ticket: Spanish only, the company as typed
      assert.deepStrictEqual(await englishCats(pg, '.ticket'), [], 'no English category word on the ticket');
      // the courtesy recorded and printed
      await charge(pg, '#courtesyBtn');
      await until(() => sql(`select total_crc || '/' || payment_method || '/' || discount_reason || '/' || discount_crc || '/' || subtotal_crc || '/' || discount_by from orders where discount_id is not null`) === '0/other/Tour guide/3500/3500/Dueño', 10000, 'the courtesy recorded at ₡0');
      assert.strictEqual(linked('guia'), '0/3500/3500/Tour guide/Dueño/true/true/false', 'the courtesy linked to its approval');
      assert.strictEqual(sql(`select company || '/' || approver_role from discount_approvals where category = 'guia'`), 'Tour guide/owner');
      await pg.click('#printBtn');
      await until(() => pg.evaluate(() => (window.__printed || 0) > 0), 5000, 'printed');
      const rec = norm(await pg.evaluate(() => window.__printedHTML).then((h) => h.replace(/<[^>]+>/g, ' ')));
      assert.match(rec, /Cortesía Guía Turista · Tour guide courtesy −₡3 500/, 'the courtesy line on paper');
      assert.match(rec, /TOTAL ₡0/); assert.match(rec, /Incluye IVA 13% · Includes VAT ₡0/, 'IVA ₡0');
      assert.match(rec, /Cortesía · Courtesy/); assert.ok(!/Pago · Paid by/.test(rec), 'not a payment');
      assert.ok(!/%/.test(rec.replace(/IVA 13%/g, '')), 'no percentage for the discount on paper');
      assert.strictEqual((rec.match(/Tour guide/g) || []).length, (rec.match(/Tour guide courtesy/g) || []).length, 'the company typed at the till is not printed');
      // E-b: the Orders row
      await pg.click('#ordersBtn');
      await pg.waitForSelector('#ordersModal:not([hidden])');
      await see(pg, '#ordersBody', /Descuento ₡3 500 · Guía Turista · aprobado por Dueño/);
      assert.deepStrictEqual(await englishCats(pg, '#ordersBody'), [], 'no English category word in Orders');
      await pg.click('#ordersClose');
      await quiet(pg);
      await nothingOpened('after the sale, the receipt and Orders');
      noCodeLeak(pg);
      await noCodeKept(pg);
      // E-b: the sales report, on the owner's login (phone code)
      const so = await page(browser, { login: 'owner', aal: 'aal2', lang: 'es' });
      await goto(so, '/sales');
      await so.waitForSelector('#dcCard:not([hidden])', { timeout: 15000 });
      await see(so, '#dcBody', /Guía Turista/);
      const row = await so.evaluate(() => [...document.querySelectorAll('#dcBody tr')].map((tr) => [...tr.children].map((td) => td.textContent.trim())));
      const gr = row.find((r) => r[1] === 'Guía Turista');
      assert.ok(gr, 'the courtesy in «Descuentos por categoría»: ' + JSON.stringify(row));
      assert.strictEqual(gr[2], 'Tour guide', 'a company called «Tour guide» stays as typed');
      assert.deepStrictEqual(await englishCats(so, '#dcCard'), [], 'no English category word in the sales report');
      assert.deepStrictEqual(so.errors, []);
      // the time clock still asks for a PIN on this device
      await goto(pg, '/time');
      await pg.click('#tabHours');
      await pg.waitForSelector('#hoursPinModal:not([hidden])', { timeout: 10000 });
      assert.strictEqual(sql(`select count(*) from access_unlocks`), unlocks0, 'still no unlock');
      assert.strictEqual(await pg.evaluate(() => localStorage.getItem('hg-unlock')), null, 'the time clock found no unlock on this device');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'E-c Guía Turista off by default: its A-13 text, Autorizar off, no request; on but no owner PIN in the team: its text, no request',
    run: async ({ browser }) => {
      testMenu();
      const pg = await till(browser);
      await tap(pg, 'T Latte');
      const est = pg.waitForResponse((r) => /rpc\/descuento_estado/.test(r.url()));
      await openWin(pg);
      assert.strictEqual((await (await est).json()).guia_enabled, false, 'the setting ships off (adjustment 4)');
      await cat(pg, 'guia');
      await see(pg, '#discErr', ES.guiaOff);
      await see(pg, '#discLead', ES.leadOwner);
      assert.ok(await pg.isEnabled('#discForm [data-cat="guia"]'), 'Guía Turista stays tappable');
      assert.ok(await pg.isDisabled('#discGo'), 'Autorizar off');
      assert.ok(await pg.isDisabled('#discText'), 'the company box off');
      await pg.evaluate(() => document.getElementById('discForm').requestSubmit());
      await pg.waitForTimeout(300);
      assert.strictEqual(sent(pg, 'descuento_autorizar').length, 0, 'no request while Guía is off');
      { const f = await fits(pg); assert.ok(f.sh <= f.ch); }
      // another category clears it
      await cat(pg, 'local');
      await see(pg, '#discErr', '');
      assert.ok(!(await pg.isDisabled('#discGo')), 'Local can be authorized');
      await closeWin(pg);
      // on, but nobody in the team is the owner with a PIN
      guiaOn();
      sql(`update public.staff set pin_hash = null where role = 'owner'`);
      await openWin(pg);
      await cat(pg, 'guia');
      await see(pg, '#discErr', ES.noOwner);
      assert.ok(await pg.isDisabled('#discGo'), 'Autorizar off');
      assert.ok(await pg.isDisabled('#discText'), 'and it goes no further: the company box off');
      await pg.evaluate(() => document.getElementById('discForm').requestSubmit());
      await pg.waitForTimeout(300);
      assert.strictEqual(sent(pg, 'descuento_autorizar').length, 0, 'no request without an owner PIN');
      await closeWin(pg);
      noCodeLeak(pg);
      assert.deepStrictEqual(pg.errors, []);
    }
  }
];
