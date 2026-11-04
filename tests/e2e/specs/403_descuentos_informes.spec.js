/* The discounts of migration 0038 in the reports, the books and the stock: typed text stays text everywhere it is shown
   or downloaded (proposal §5.2 X-a: a tour guide company <img src=x onerror=alert(1)> and =HYPERLINK("x") on the ticket,
   in Sales «Descuentos por categoría», in the approvals log, in «Descargar descuentos (CSV)» and in the accountant's
   descuentos.csv); the Sales section itself (the summaries by category, employee, authorizer and company, the courtesies'
   line by IVA rate, the status texts of a used, voided, freed, let-go, expired, waiting and taken-off approval, the
   «Códigos equivocados» block); the accountant's login sees the report and nothing it should not; Home's settings card
   (the old free window on, Guía Turista off with its guard, refused without the confirmation); and a discounted sale and
   a courtesy against the same sale without a discount: the same stock moves, the register closing (the courtesy as
   'other' at ₡0), the daily posting still off (A-07) and the IVA on the discounted amount, as the ticket shows it.
   Sources: proposal-final.md §2.10, §4 and §5.2 (X-a), api-0038.md §1, §4.6 and §10.4-§10.5, mecanismo-intentos.md
   §10.5, build-plan.md L1-L3, decisiones-dueno.md (adjustments 3 and 4), ui-plan.md U3. */
'use strict';
const assert = require('assert');
const crypto = require('crypto');
const { spawnSync } = require('child_process');
const { page, goto, until, sql, sqlJson, openRegister, registerTill, guiaOn, STAFF, PINS } = require('../lib');
const gw = require('../gateway');

const API = 'http://127.0.0.1:' + (Number(process.env.E2E_SITE_PORT || 8090) + 1000);
const AUTH_KEY = 'sb-127-auth-token';
const MENU_CAT = 'b0000000-0000-4000-8000-0000000403c1';
const ITEM = { batido: 'b0000000-0000-4000-8000-0000000403a1', agua: 'b0000000-0000-4000-8000-0000000403a2' };
const NAME = { batido: 'T Batido 403', agua: 'T Agua 403' };
const STOCK = { fresa: '5a000000-0000-4000-8000-0000000e4031', leche: '5a000000-0000-4000-8000-0000000e4032', agua: '5a000000-0000-4000-8000-0000000e4033' };
const BILL = 'd0000000-0000-4000-8000-000000040301';
const XSS = '<img src=x onerror=alert(1)>', FORMULA = '=HYPERLINK("x")';
const WRONG = '1111';   // nobody's code (the seed's are 4826, 5284, 6173, 7391)

/* the texts as the pages show them in Spanish (website/lang.js) */
const ES = {
  emp: 'Código de empleado', mgr: 'Código de encargado', owner: 'Código del dueño', company: 'Empresa del guía turístico',
  ticket: { empleado: 'Descuento Empleado', local: 'Descuento Local', huesped: 'Descuento Huésped', guia: 'Cortesía Guía Turista' },
  cat: { empleado: 'Empleado', local: 'Local', huesped: 'Huésped', guia: 'Guía Turista' },
  role: { manager: 'Encargado', owner: 'Dueño' },
  status: { used: 'Usado', voided: 'Anulado', voided_freed: 'Anulado · cupo libre', released: 'Liberado', expired: 'Vencido',
            pending: 'En espera', removed: 'Quitado de la cuenta', removed_counts: 'Quitado de la cuenta · sigue contando hoy' },
  card: 'Descuentos por categoría', csv: 'Descargar descuentos (CSV)', wrong: 'Códigos equivocados',
  court: 'Cortesías: valor de lista por tasa de IVA (informativo, pendiente del contador · A-13)',
  caption: { cat: 'Por categoría', emp: 'Por empleado', auth: 'Por quien autorizó', comp: 'Por empresa' },
  head: { cat: ['Categoría', 'Autorizados', 'Aplicados', 'Descuento', 'Valor de lista'], emp: ['Empleado', 'Autorizados', 'Aplicados', 'Descuento'],
          auth: ['Autorizado por', 'Puesto', 'Aplicados', 'Descuento'], comp: ['Empresa', 'Autorizados', 'Aplicados', 'Descuento', 'Valor de lista'] },
  table: ['Cuándo', 'Categoría', 'Empleado o empresa', 'Autorizado por', 'Valor de lista', 'Descuento', 'Cobrado', 'Productos cubiertos', 'Estado', 'Recibo'],
  logApproved: 'Descuento aprobado',
  // Home › system settings (home.html SET_LABEL / KEY_CHOICE_LABEL / SET_ERR through lang.js)
  setFree: 'Ventana anterior de descuento libre (cajas aún sin recargar)',
  setFreeOn: 'Encendida (hasta que termine la activación)', setFreeOff: 'Apagada (solo los cuatro descuentos)',
  setGuia: 'Cortesía Guía Turista 100 % (necesita la confirmación del IVA por el contador, A-13)',
  setGuiaOff: 'Apagada (hasta que el contador confirme el IVA)', setGuiaOn: 'Encendida (IVA confirmado por el contador)',
  needsConf: 'Con candado: primero registre la confirmación de esta regla.',
  // the settings' own descriptions (canopy.setting_defs, Spanish; api-0038.md §1)
  descFree: 'Ventana de descuento libre de la Caja anterior (porcentaje o monto con el PIN de un encargado). on = sigue funcionando para las cajas que todavía no se recargaron, como hoy; off = solo los cuatro descuentos nuevos. Se apaga al final de la activación (docs/ACTIVACION-DESCUENTOS.md §4).',
  descGuia: 'Cortesía Guía Turista 100 %: apagada hasta que el contador confirme el tratamiento del IVA (A-13) y el dueño lo registre con compliance_confirm(\'courtesy_iva_confirmed\', …); luego el dueño la enciende con el código del teléfono.'
};

/* ---------- small helpers ---------- */
const norm = (s) => String(s == null ? '' : s).replace(/[\u00a0\u202f]/g, ' ').replace(/\s+/g, ' ').trim();
const text = async (pg, sel) => norm(await pg.textContent(sel));
const see = (pg, sel, want, ms) => until(async () => {
  const t = await text(pg, sel);
  return want instanceof RegExp ? want.test(t) : t === want;
}, ms || 8000, sel + ' to read «' + want + '»').catch(async (e) => { e.message += ' (it reads «' + (await text(pg, sel).catch(() => '?')) + '»)'; throw e; });
const crc = (n) => '₡' + Number(n).toLocaleString('fr-FR').replace(/[\u00a0\u202f]/g, ' ');   // as the pages print it, spaces normalised
const pinIn = (s, pin) => new RegExp('(^|[^0-9a-f-])' + pin + '([^0-9a-f-]|$)', 'i').test(String(s || ''));
const anyPin = (s) => Object.values(PINS).filter((p) => pinIn(s, p));
const uuid = () => crypto.randomUUID();
const hhmmCR = (iso) => sql(`select to_char(('${iso}'::timestamptz) at time zone 'America/Costa_Rica', 'HH24:MI')`);

/* two products with recipes (one at 13 %, one at a reduced 4 % rate), as the café sells them */
function testMenu() {
  sql(`insert into tax_rates (code, name, rate, confirmed_by, reference) values ('IVA4', 'Reducida 4 %', 0.04, 'prueba', 'prueba') on conflict do nothing;
       insert into menu_categories (id, name, sort, kitchen) values ('${MENU_CAT}', 'Test Bar 403', 0, false);
       insert into menu_items (id, category_id, name, price_crc, sort, available, tax_code) values
         ('${ITEM.batido}', '${MENU_CAT}', '${NAME.batido}', 3000, 1, true, 'IVA13'),
         ('${ITEM.agua}', '${MENU_CAT}', '${NAME.agua}', 1000, 2, true, 'IVA4');
       insert into stock_items (id, name, unit, pack_qty, cost_per_pack) values
         ('${STOCK.fresa}', 'Fresa 403', 'g', 1000, 4000), ('${STOCK.leche}', 'Leche 403', 'ml', 1000, 1000), ('${STOCK.agua}', 'Agua 403', 'unit', 24, 12000);
       insert into recipes (menu_item_id, stock_item_id, qty) values
         ('${ITEM.batido}', '${STOCK.fresa}', 120), ('${ITEM.batido}', '${STOCK.leche}', 100), ('${ITEM.agua}', '${STOCK.agua}', 1);`);
}

/* every request the page sends to the API, with its body */
function watch(pg) {
  pg.rpcs = [];
  pg.on('request', (r) => {
    const u = r.url();
    if (!u.startsWith(API)) return;
    const m = u.match(/\/rest\/v1\/rpc\/([a-z_0-9]+)/);
    pg.rpcs.push({ fn: m ? m[1] : null, url: u, body: r.postData() || '' });
  });
}
/* a code goes only where a person typed it for that purpose */
const CODE_FNS = ['descuento_autorizar', 'access_unlock', 'manager_void_order', 'register_close'];
function noCodeLeak(pg) {
  for (const r of pg.rpcs || []) {
    if (CODE_FNS.includes(r.fn)) continue;
    assert.deepStrictEqual(anyPin(r.url + ' ' + r.body), [], 'a code in a request of ' + (r.fn || r.url) + ': ' + r.body.slice(0, 200));
  }
}
/* the dialogs a page opens (an alert from a typed company would be one) */
function dialogs(pg) { pg.dialogs = []; pg.onDialog = async (d) => { pg.dialogs.push(d.type() + ': ' + d.message()); await d.dismiss(); }; return pg; }
/* nothing made from a typed text: no element, no handler, no dialog, no page error */
async function noMarkup(pg, where) {
  const n = await pg.evaluate(() => [document.querySelectorAll('img[src="x"]').length, document.querySelectorAll('[onerror]').length]);
  assert.deepStrictEqual(n, [0, 0], 'no element made from the typed company (' + where + ')');
  assert.deepStrictEqual(pg.dialogs, [], 'no dialog (' + where + ')');
  assert.deepStrictEqual(pg.errors, [], 'no page error (' + where + ')');
}

/* the till: the POS signed in with the café login, the register open, its 20-second retry and live poll off, registered
   for discounts as a manager does it (lib.registerTill) */
async function till(browser, opts) {
  opts = Object.assign({ login: 'cafe', lang: 'es', viewport: { width: 1180, height: 820 } }, opts || {});
  openRegister();
  const pg = dialogs(await page(browser, opts));
  watch(pg);
  await pg.addInitScript(() => {
    const si = window.setInterval;
    window.setInterval = function (fn, ms) { return ms === 20000 ? 0 : si.apply(this, arguments); };
  });
  await goto(pg, '/pos');
  await pg.waitForSelector('#appView:not([hidden])', { timeout: 15000 });
  await pg.waitForFunction(() => document.querySelectorAll('.pbtn').length > 0, null, { timeout: 15000 });
  if (await pg.isVisible('#dayModal')) await pg.click('#dayClose');
  if (await pg.isVisible('#stationModal')) await pg.click('#stationForm button[type=submit]');
  await pg.evaluate(() => clearInterval(liveTimer));
  await pg.waitForLoadState('networkidle');
  // the IVA rates of the menu cached (the ticket's IVA depends on them)
  await until(() => pg.evaluate(() => !!localStorage.getItem('hg-pos-tax')), 8000, 'the page\'s tax settings cached');
  await registerTill(pg, { station: 'Caja' });
  return pg;
}
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
  await pg.waitForFunction(() => window.disc && disc.st, null, { timeout: 8000 });
}
async function cat(pg, c) {
  await pg.click(`#discForm [data-cat="${c}"]`);
  await until(() => pg.evaluate((x) => document.querySelector(`#discForm [data-cat="${x}"]`).classList.contains('on'), c), 3000, c + ' selected');
}
async function charge(pg, sel) {
  await pg.click(sel || '[data-pay="card"]');
  await until(async () => (await pg.isVisible('#numModal')) || (await pg.evaluate(() => !pendingPay)), 5000, 'the number window or the sale');
  if (await pg.isVisible('#numModal')) await pg.click('#numNone');
}
const lastApproval = () => sql(`select id from discount_approvals where category is not null order by created_at desc, id desc limit 1`);
/* one discount given on the ticket through the window, as staff do it: Empleado's employee code first, Guía's company
   typed on the keyboard; returns the approval id once the window has closed with it on the ticket */
async function give(pg, c, o) {
  o = o || {};
  const n0 = sql(`select count(*) from discount_approvals where category is not null`);
  await openWin(pg);
  await cat(pg, c);
  if (c === 'empleado') { await see(pg, '#discStep', ES.emp); await typeCode(pg, PINS[o.employee || 'luis']); await pg.click('#discGo'); await see(pg, '#discStep', ES.mgr); }
  if (c === 'guia') {
    await see(pg, '#discStep', ES.company);
    assert.strictEqual(await pg.evaluate(() => document.activeElement && document.activeElement.id), 'discText', 'the company box has the focus');
    await pg.keyboard.type(o.company);
    await pg.keyboard.press('Enter');
    await see(pg, '#discStep', ES.owner);
  }
  await typeCode(pg, PINS[o.by || (c === 'guia' ? 'dueno' : 'ana')]);
  await pg.click('#discGo');
  await pg.waitForSelector('#discModal', { state: 'hidden', timeout: 8000 });
  await until(() => sql(`select count(*) from discount_approvals where category is not null`) !== n0, 5000, 'the approval recorded');
  return lastApproval();
}
/* the sale of the ticket, charged (or the courtesy recorded); the order the approval went on */
async function sell(pg, approval, sel) {
  const n0 = Number(sql(`select count(*) from orders`));
  await charge(pg, sel);
  await until(() => Number(sql(`select count(*) from orders`)) === n0 + 1, 10000, 'the sale recorded');
  if (approval) await until(() => sql(`select order_id is not null from discount_approvals where id = '${approval}'`) === 't', 8000, 'the sale linked to its approval');
  return approval ? sql(`select order_id from discount_approvals where id = '${approval}'`) : sql(`select id from orders order by created_at desc, id desc limit 1`);
}
/* a database function called from the test with this page's own sign-in (and an unlock token when given) */
async function rpcAs(pg, name, args, unlock) {
  const s = await pg.evaluate((k) => JSON.parse(localStorage.getItem(k) || 'null'), AUTH_KEY);
  return rpcTok(s.access_token, name, args, unlock);
}
async function rpcTok(token, name, args, unlock) {
  const headers = { 'Content-Type': 'application/json', Authorization: 'Bearer ' + token };
  if (unlock) headers['x-hg-unlock'] = unlock;
  const r = await fetch(API + '/rest/v1/rpc/' + name, { method: 'POST', headers, body: JSON.stringify(args || {}) });
  const t = await r.text();
  if (!r.ok) throw new Error(name + ' ' + r.status + ' ' + t);
  return t ? JSON.parse(t) : null;
}
async function rest(token, pathQ) {
  const r = await fetch(API + '/rest/v1/' + pathQ, { headers: { Authorization: 'Bearer ' + token, Accept: 'application/json' } });
  return { status: r.status, body: await r.text() };
}

/* CSV read back as a spreadsheet reads it (Python's csv module); a file inside a ZIP is read from the ZIP */
function readCsv(file, inZip) {
  const py = inZip
    ? 'import csv, io, json, sys, zipfile; z = zipfile.ZipFile(sys.argv[1]); t = z.read(sys.argv[2]).decode("utf-8-sig"); print(json.dumps({"raw": t, "rows": list(csv.reader(io.StringIO(t)))}))'
    : 'import csv, io, json, sys; t = open(sys.argv[1], encoding="utf-8-sig", newline="").read(); print(json.dumps({"raw": t, "rows": list(csv.reader(io.StringIO(t)))}))';
  const r = spawnSync('python3', ['-I', '-c', py, file].concat(inZip ? [inZip] : []), { encoding: 'utf8' });
  if (r.status !== 0) throw new Error('reading the CSV: ' + r.stderr);
  const out = JSON.parse(r.stdout);
  const [head, ...rows] = out.rows;
  return { raw: out.raw, head, rows: rows.map((x) => Object.fromEntries(head.map((k, i) => [k, x[i]]))) };
}
const zipNames = (file) => {
  const r = spawnSync('python3', ['-I', '-c', 'import json, sys, zipfile; z = zipfile.ZipFile(sys.argv[1]); print(json.dumps([z.testzip(), z.namelist()]))', file], { encoding: 'utf8' });
  if (r.status !== 0) throw new Error('reading the ZIP: ' + r.stderr);
  return JSON.parse(r.stdout);
};

/* Sales › «Descuentos por categoría» as the page shows it */
async function salesPage(browser, opts) {
  const so = dialogs(await page(browser, Object.assign({ login: 'owner', aal: 'aal2', lang: 'es' }, opts || {})));
  await goto(so, '/sales');
  await so.waitForSelector('#dcCard:not([hidden])', { timeout: 15000 });
  return so;
}
const reportRows = (pg) => pg.evaluate(async () => {
  await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));   // lang.js translates on the next frame
  const nz = (x) => String(x == null ? '' : x).replace(/[\u00a0\u202f]/g, ' ').replace(/\s+/g, ' ').trim();
  return [...document.querySelectorAll('#dcBody tr')].map((tr) => {
    const td = [...tr.children];
    if (td.length < 10) return { empty: nz(tr.textContent) };
    const first = (e) => (e.firstChild ? nz(e.firstChild.textContent) : '');
    return {
      when: nz(td[0].textContent), cat: first(td[1]), who: td[2].textContent, whoNodes: td[2].children.length, whoTranslate: td[2].hasAttribute('data-no-translate'),
      by: td[3].querySelector('span') ? td[3].querySelector('span').textContent : nz(td[3].textContent), role: td[3].querySelector('.dreason') ? nz(td[3].querySelector('.dreason').textContent) : '',
      list: nz(td[4].textContent), discount: nz(td[5].textContent), charged: first(td[6]), products: td[7].firstChild ? td[7].firstChild.textContent : '',
      status: first(td[8]), flags: [...td[8].querySelectorAll('.dcflag')].map((f) => nz(f.textContent)), receipt: nz(td[9].textContent), void: tr.classList.contains('void')
    };
  });
});
const sumTables = (pg) => pg.evaluate(async () => {
  await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));   // lang.js translates on the next frame
  const nz = (x) => String(x == null ? '' : x).replace(/[\u00a0\u202f]/g, ' ').replace(/\s+/g, ' ').trim();
  const o = {};
  document.querySelectorAll('#dcSum table').forEach((t) => {
    o[nz(t.querySelector('caption').textContent)] = {
      head: [...t.querySelectorAll('thead th')].map((th) => nz(th.textContent)),
      rows: [...t.querySelectorAll('tbody tr')].map((tr) => [...tr.children].map((td) => nz(td.textContent)))
    };
  });
  return o;
});
const byFirst = (rows) => Object.fromEntries(rows.map((r) => [r[0], r.slice(1)]));

/* Reloj de marcas › Horas y equipo with the owner areas open on this device (the person's own PIN in the unlock box) */
async function timeUnlock(pg, who) {
  await goto(pg, '/time');
  await until(async () => (await pg.locator('#staffGrid button').count()) > 0, 15000, 'the clock');
  await pg.click('#tabHours');
  await until(async () => (await pg.isVisible('#hoursPinModal')) || (await pg.isVisible('#logCard')), 10000, 'the PIN box or the log');
  if (await pg.isVisible('#hoursPinModal')) {
    await pg.selectOption('#hpWho', STAFF[who]);
    await pg.type('#hpPin', PINS[who]);
    await pg.click('#hoursPinForm button[type=submit]');
    await until(async () => pg.locator('#hoursPinModal').isHidden(), 8000, 'the owner areas opened by ' + who);
  }
  await pg.waitForSelector('#logCard:not([hidden])', { timeout: 10000 });
}
const logRows = (pg, label) => pg.evaluate(async (l) => { await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))); return [...document.querySelectorAll('#logBody .lrow')].filter((r) => (r.querySelector('.what > b') || {}).textContent === l)
  .map((r) => ({ text: r.querySelector('.what').textContent.replace(/[\u00a0\u202f]/g, ' ').replace(/\s+/g, ' ').trim(),
                 values: [...r.querySelectorAll('.what [data-no-translate]')].map((s) => s.textContent) })); }, label);

/* the accountant's month for the books, downloaded as the accountant does it (contabilidad › Reportes › the package) */
async function accountantPackage(browser) {
  const pg = dialogs(await page(browser, { login: 'accountant', aal: 'aal2', lang: 'es' }));
  watch(pg);
  await goto(pg, '/contabilidad');
  await pg.waitForSelector('#appView:not([hidden])', { timeout: 15000 });
  await pg.evaluate(() => { location.hash = 'reportes'; });
  await pg.waitForSelector('#rPack', { timeout: 15000 });
  const [zip] = await Promise.all([pg.waitForEvent('download', { timeout: 20000 }), pg.click('#rPack')]);
  return { pg, file: await zip.path(), name: zip.suggestedFilename() };
}

/* the stock an order took, item by item: name:qty@unit cost */
const movesOf = (order) => sql(`select coalesce(string_agg(s.name || ':' || trim_scale(m.qty)::text || '@' || trim_scale(coalesce(m.unit_cost, 0))::text || ':' || m.kind, ' ' order by s.name), '')
                                  from stock_moves m join stock_items s on s.id = m.item_id where m.order_id = '${order}'`);

/* ---------- the tests ---------- */
module.exports.tests = [
  {
    name: 'X-a: a tour guide company <img src=x onerror=alert(1)> and =HYPERLINK("x") stay text on the ticket, in «Descuentos por categoría», in the approvals log; «Descargar descuentos (CSV)» and the accountant\'s descuentos.csv hold the same text through csvSafe (read back \'=HYPERLINK("x")); no element, no dialog, no page error',
    run: async ({ browser }) => {
      testMenu(); guiaOn();
      const pg = await till(browser);
      // the first courtesy: the company typed on the keyboard
      await tap(pg, NAME.batido); await tap(pg, NAME.agua);
      const g1 = await give(pg, 'guia', { company: XSS });
      await see(pg, '#discLbl', ES.ticket.guia + ' · ' + XSS);
      assert.strictEqual(await pg.evaluate(() => document.querySelector('#discLbl [data-no-translate]').textContent), ' · ' + XSS, 'the company a text of its own on the ticket');
      assert.strictEqual(await pg.evaluate(() => document.querySelectorAll('#discLbl *').length), 1, 'no element made inside the ticket row');
      await noMarkup(pg, 'the ticket');
      const o1 = await sell(pg, g1, '#courtesyBtn');
      await noMarkup(pg, 'after the courtesy');
      // the second
      await tap(pg, NAME.batido);
      const g2 = await give(pg, 'guia', { company: FORMULA });
      await see(pg, '#discLbl', ES.ticket.guia + ' · ' + FORMULA);
      const o2 = await sell(pg, g2, '#courtesyBtn');
      assert.deepStrictEqual(sqlJson(`select json_agg(company order by created_at) from discount_approvals where category = 'guia'`), [XSS, FORMULA], 'the companies kept as typed');
      assert.strictEqual(sql(`select string_agg(total_crc || '/' || payment_method, ' ' order by created_at) from orders where id in ('${o1}', '${o2}')`), '0/other 0/other');
      await noMarkup(pg, 'the POS at the end');
      noCodeLeak(pg);

      // Sales › «Descuentos por categoría» (the owner with the phone code)
      const so = await salesPage(browser);
      await see(so, '#dcCard h2', ES.card);
      await until(async () => (await reportRows(so)).filter((r) => r.cat === ES.cat.guia).length === 2, 8000, 'the two courtesies in the table');
      const rows = (await reportRows(so)).filter((r) => r.cat === ES.cat.guia);
      assert.deepStrictEqual(rows.map((r) => r.who).sort(), [XSS, FORMULA].sort(), 'each company shown as typed in «Empleado o empresa»');
      assert.ok(rows.every((r) => r.whoNodes === 0 && r.whoTranslate), 'each company a plain text cell, never translated: ' + JSON.stringify(rows));
      const comp = (await sumTables(so))[ES.caption.comp];
      assert.ok(comp, '«Por empresa» shows');
      assert.deepStrictEqual(comp.rows.map((r) => r[0]).sort(), [XSS, FORMULA].sort(), 'each company as text in «Por empresa»');
      assert.strictEqual(await so.evaluate(() => document.querySelectorAll('#dcSum table *:not(caption):not(thead):not(tbody):not(tr):not(th):not(td)').length), 0, 'only table cells in the summaries');
      await noMarkup(so, 'Sales');
      // «Descargar descuentos (CSV)»: the same text, every text cell through csvSafe
      await see(so, '#dcCsv', ES.csv);
      const [dl] = await Promise.all([so.waitForEvent('download'), so.click('#dcCsv')]);
      assert.match(dl.suggestedFilename(), /^hanging-garden-descuentos-\d{4}-\d\d-\d\d-\d{4}-\d\d-\d\d\.csv$/);
      const sc = readCsv(await dl.path());
      const sg = sc.rows.filter((r) => r.category === 'guia');
      assert.deepStrictEqual(sg.map((r) => r.company).sort(), [XSS, "'" + FORMULA].sort(), 'Sales CSV: the company read back as typed, the formula as text (\'=HYPERLINK("x"))');
      assert.ok(sc.raw.includes('"\'=HYPERLINK(""x"")"') && sc.raw.includes('"' + XSS + '"'), 'Sales CSV: both companies quoted by the CSV writer');
      for (const r of sc.rows) for (const [k, v] of Object.entries(r)) assert.ok(!/^[=+\-@\t\r]/.test(v || '') || /^-?\d+([.,]\d+)?$/.test(v), 'Sales CSV: no cell starts a formula: ' + k + '=' + v);
      await noMarkup(so, 'Sales after the download');

      // the accountant's monthly package: descuentos.csv holds the same
      const acc = await accountantPackage(browser);
      const [bad, names] = zipNames(acc.file);
      assert.strictEqual(bad, null, 'a valid ZIP');
      assert.ok(names.includes('descuentos.csv'), 'descuentos.csv in the month\'s package: ' + names.join(', '));
      const ac = readCsv(acc.file, 'descuentos.csv');
      const ag = ac.rows.filter((r) => r.category === 'guia' && /^\d{4}-\d\d-\d\d$/.test(r.day));   // (the courtesies' lines by rate follow the rows)
      assert.deepStrictEqual(ag.map((r) => r.company).sort(), [XSS, "'" + FORMULA].sort(), 'descuentos.csv: the company read back as typed, the formula as text');
      assert.ok(ac.raw.includes('"\'=HYPERLINK(""x"")"'), 'descuentos.csv: the formula cell quoted by the CSV writer');
      for (const r of ac.rows) for (const [k, v] of Object.entries(r)) assert.ok(!/^[=+\-@\t\r]/.test(v || '') || /^-?\d+([.,]\d+)?$/.test(v), 'descuentos.csv: no cell starts a formula: ' + k + '=' + v);
      // and, after the rows, the courtesies' list value by IVA rate (information only, A-13): ₡3 000 + ₡3 000 at 13 %, ₡1 000 at 4 %
      assert.deepStrictEqual(ac.rows.filter((r) => /^courtesy_list_value_by_iva_rate/.test(r.day)).map((r) => [r.products, Number(r.list_value_crc)]).sort(),
        [['iva_rate 0.04', 1000], ['iva_rate 0.13', 6000]], 'descuentos.csv: the courtesies by rate, no tax computed');
      await noMarkup(acc.pg, 'contabilidad');

      // the approvals log (the café login, the owner areas opened by Ana on that device)
      const lg = dialogs(await page(browser, { login: 'cafe', lang: 'es', station: { name: 'Tableta 403', main: false } }));
      await timeUnlock(lg, 'ana');
      await until(async () => (await logRows(lg, ES.logApproved)).length === 2, 10000, 'the two approvals in the log');
      const lr = await logRows(lg, ES.logApproved);
      assert.deepStrictEqual(lr.map((r) => r.values).sort(), [[XSS], [FORMULA]].sort(), 'each company in its own text span: ' + JSON.stringify(lr));
      assert.deepStrictEqual(lr.map((r) => r.text).sort(),
        [`${ES.logApproved} · ${ES.cat.guia} · ${XSS} · ${crc(4000)} · aprobado por Dueño`, `${ES.logApproved} · ${ES.cat.guia} · ${FORMULA} · ${crc(3000)} · aprobado por Dueño`].sort(),
        'the log rows: category, company as typed, amount, who');
      await noMarkup(lg, 'the approvals log');
    }
  },
  {
    name: 'Sales › «Descuentos por categoría»: the summaries by category, employee, authorizer (with role) and company over the given rows, the courtesies\' list value by IVA rate (no tax computed), each status text (used, voided, voided with the day freed, let go, expired, waiting, taken off the bill and still counting, then given back), the «Códigos equivocados» block of the day',
    run: async ({ browser }) => {
      testMenu(); guiaOn();
      const pg = await till(browser);
      const both = async () => { await tap(pg, NAME.batido); await tap(pg, NAME.agua); };
      // a) Empleado for Luis, sold
      await both();
      const a = await give(pg, 'empleado', { employee: 'luis' });
      await see(pg, '#discLbl', ES.ticket.empleado + ' · Luis');
      const oa = await sell(pg, a);
      // b) Local, sold, then voided by Ana; c) Empleado for Marta, sold, then voided by Ana (her day freed)
      await both();
      const b = await give(pg, 'local');
      const ob = await sell(pg, b);
      await both();
      const c = await give(pg, 'empleado', { employee: 'marta' });
      const oc = await sell(pg, c);
      // g) a tour guide courtesy, approved by the owner
      await both();
      const g = await give(pg, 'guia', { company: 'Selvatura' });
      const og = await sell(pg, g, '#courtesyBtn');
      for (const o of [ob, oc]) {
        const v = await rpcAs(pg, 'manager_void_order', { p_manager_id: STAFF.ana, p_manager_pin: PINS.ana, p_order_id: o, p_reason: 'prueba 403' });
        assert.ok(v && v.ok, 'voided by Ana: ' + JSON.stringify(v));
      }
      assert.strictEqual(sql(`select freed_how from discount_approvals where id = '${c}'`), 'void', 'Marta\'s day freed by the void');
      // d) Huésped let go, e) Local expired, f) Huésped waiting: approved at this till for a ticket, never sold
      const auth = (cat, sub, extra) => rpcAs(pg, 'descuento_autorizar', Object.assign({ p_category: cat, p_pin: PINS.ana, p_subtotal: sub, p_request_id: uuid(), p_station: 'Caja' }, extra || {}));
      const d = await auth('huesped', 4000);
      assert.ok(d.ok, JSON.stringify(d));
      assert.ok((await rpcAs(pg, 'descuento_liberar', { p_id: d.id })).ok, 'let go');
      const e = await auth('local', 2000);
      assert.ok(e.ok, JSON.stringify(e));
      sql(`update discount_approvals set created_at = created_at - interval '31 minutes' where id = '${e.id}'`);   // older than 30 minutes (486's fixture)
      const f = await auth('huesped', 1500);
      assert.ok(f.ok, JSON.stringify(f));
      // h) Empleado for Marta on a bill, taken off with nothing paid: her day still counts until a manager gives it back
      sql(`insert into orders (id, total_crc, payment_method, status, paid, source, station, guest_name) values ('${BILL}', 4000, 'pending', 'ready', false, 'front', 'Caja', 'Mesa 403');
           insert into order_items (order_id, item_name, price_crc, qty, menu_item_id) values
             ('${BILL}', '${NAME.batido}', 3000, 1, '${ITEM.batido}'), ('${BILL}', '${NAME.agua}', 1000, 1, '${ITEM.agua}')`);
      const h = await auth('empleado', 4000, { p_employee_pin: PINS.marta, p_order_id: BILL, p_expect: 4000 });
      assert.ok(h.ok && h.total === 2800, JSON.stringify(h));
      const q = await rpcAs(pg, 'descuento_quitar_cuenta', { p_order_id: BILL, p_expect: 2800, p_station: 'Caja' });
      assert.ok(q.ok && q.counts === true, 'taken off, the day still counts: ' + JSON.stringify(q));
      // the wrong codes of the day, last (the third makes this till wait 30 seconds): two at the manager step, one at the employee's
      const w = [await auth('local', 1000, { p_pin: WRONG }), await auth('local', 1000, { p_pin: WRONG }), await auth('empleado', 1000, { p_employee_pin: WRONG })];
      assert.deepStrictEqual(w.map((x) => [x.error, x.step, x.blocked]), [['bad_pin', 'manager', null], ['bad_pin', 'manager', null], ['bad_employee', 'employee', 'wait']], JSON.stringify(w));
      noCodeLeak(pg);

      const so = await salesPage(browser);
      await see(so, '#dcCard h2', ES.card);
      await until(async () => (await reportRows(so)).length === 8, 8000, 'the eight approvals of the day in the table');
      // the summaries: counts of every row, «Aplicados», discount and list value over the given rows only (api-0038 §4.6)
      const sums = await sumTables(so);
      assert.deepStrictEqual(Object.keys(sums), [ES.caption.cat, ES.caption.emp, ES.caption.auth, ES.caption.comp], 'the four summaries, in Spanish');
      assert.deepStrictEqual(sums[ES.caption.cat].head, ES.head.cat);
      assert.deepStrictEqual(byFirst(sums[ES.caption.cat].rows), {
        [ES.cat.empleado]: ['3', '1', crc(1200), crc(4000)], [ES.cat.local]: ['2', '0', crc(0), crc(0)],
        [ES.cat.huesped]: ['2', '0', crc(0), crc(0)], [ES.cat.guia]: ['1', '1', crc(4000), crc(4000)]
      }, 'by category: Empleado 3 authorized (Luis used; Marta voided, and taken off a bill), 1 given; the voided Local and the unused ones give nothing');
      assert.deepStrictEqual(sums[ES.caption.emp].head, ES.head.emp);
      assert.deepStrictEqual(byFirst(sums[ES.caption.emp].rows), { Luis: ['1', '1', crc(1200)], Marta: ['2', '0', crc(0)] }, 'by employee (Empleado only)');
      assert.deepStrictEqual(sums[ES.caption.auth].head, ES.head.auth);
      assert.deepStrictEqual(byFirst(sums[ES.caption.auth].rows), { Ana: [ES.role.manager, '1', crc(1200)], 'Dueño': [ES.role.owner, '1', crc(4000)] }, 'by authorizer, with the role of the code typed');
      assert.deepStrictEqual(sums[ES.caption.comp].head, ES.head.comp);
      assert.deepStrictEqual(byFirst(sums[ES.caption.comp].rows), { Selvatura: ['1', '1', crc(4000), crc(4000)] }, 'by company (Guía only)');
      // the courtesies' list value by IVA rate: information only, no tax computed (A-13, proposal §2.10, §4)
      const court = await so.evaluate(async () => { await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))); const e = document.getElementById('dcCourt'); return { hidden: e.hidden, nodes: [...e.childNodes].map((n) => n.nodeName === 'BR' ? '<br>' : n.textContent) }; });
      assert.strictEqual(court.hidden, false, 'the courtesies\' line shows');
      assert.strictEqual(court.nodes[0], ES.court);
      assert.strictEqual(court.nodes[1], '<br>');
      assert.deepStrictEqual(norm(court.nodes.slice(2).join('')).split(' · ').sort(), ['13 %: ' + crc(3000), '4 %: ' + crc(1000)].sort(),
        'the batido\'s ₡3 000 at 13 % and the water\'s ₡1 000 at 4 %: the list value of the courtesy\'s lines by their stamped rate');
      // the table: every row with its status text, who, amounts, products and receipt
      assert.deepStrictEqual(await so.evaluate(async () => { await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))); return [...document.querySelectorAll('#dcCard .dctable thead th')].map((t) => t.textContent.trim()); }), ES.table);
      const MON = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'set', 'oct', 'nov', 'dic'];
      const when = (id) => { const [dd, mm, hm] = sql(`select to_char(created_at at time zone 'America/Costa_Rica', 'FMDD|FMMM|HH24:MI') from discount_approvals where id = '${id}'`).split('|'); return `${dd} ${MON[mm - 1]} ${hm}`; };
      const rcpt = (o) => sql(`select coalesce(receipt_no::text, '—') from orders where id = '${o}'`);
      const P = [`1× ${NAME.agua}`, `1× ${NAME.batido}`];
      const row = (id, cat, who, by, role, list, disc, charged, products, status, receipt, isVoid) =>
        ({ when: when(id), cat: ES.cat[cat], who, by, role: ES.role[role], list: crc(list), discount: crc(disc), charged: charged === null ? '—' : crc(charged),
           products: products || ['—'], status: ES.status[status], flags: [], receipt, void: !!isVoid });
      const want = [
        row(a, 'empleado', 'Luis', 'Ana', 'manager', 4000, 1200, 2800, P, 'used', rcpt(oa)),
        row(b, 'local', '—', 'Ana', 'manager', 4000, 400, 0, P, 'voided', rcpt(ob), true),
        row(c, 'empleado', 'Marta', 'Ana', 'manager', 4000, 1200, 0, P, 'voided_freed', rcpt(oc), true),
        row(g, 'guia', 'Selvatura', 'Dueño', 'owner', 4000, 4000, 0, P, 'used', rcpt(og)),
        row(d.id, 'huesped', '—', 'Ana', 'manager', 4000, 400, null, null, 'released', '—'),
        row(e.id, 'local', '—', 'Ana', 'manager', 2000, 200, null, null, 'expired', '—'),
        row(f.id, 'huesped', '—', 'Ana', 'manager', 1500, 150, null, null, 'pending', '—'),
        row(h.id, 'empleado', 'Marta', 'Ana', 'manager', 4000, 1200, 0, P, 'removed_counts', rcpt(BILL))
      ];
      const seen = (rs) => rs.map((r) => ({ when: r.when, cat: r.cat, who: r.who, by: r.by, role: r.role, list: r.list, discount: r.discount, charged: r.charged,
        products: r.products.split(', ').sort(), status: r.status, flags: r.flags, receipt: r.receipt, void: r.void }));
      const key = (r) => [r.cat, r.status, r.who, r.list].join('|');
      const sortK = (xs) => xs.slice().sort((x, y) => (key(x) < key(y) ? -1 : 1));
      assert.deepStrictEqual(sortK(seen(await reportRows(so))), sortK(want), 'each approval of the day with its status text');
      assert.ok((await reportRows(so)).every((r) => r.whoNodes === 0 && r.whoTranslate), 'names and companies as text, never translated');
      // «Códigos equivocados» (mecanismo §10.5): the day's wrong codes by step and why, the place with its wait, the registration
      const wb = await so.evaluate(async () => {
        await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));   // lang.js translates on the next frame
        const nz = (x) => String(x || '').replace(/[\u00a0\u202f]/g, ' ').replace(/\s+/g, ' ').trim();
        const box = document.getElementById('dcWrong');
        return { hidden: box.hidden, h3: nz(box.querySelector('h3').textContent),
                 days: [...box.querySelectorAll('.dcday')].map((dv) => ({ head: nz([...dv.childNodes].filter((n) => !(n.classList && n.classList.contains('sub'))).map((n) => n.textContent).join('')),
                                                                         subs: [...dv.querySelectorAll('.sub')].map((s) => nz(s.textContent)) })) };
      });
      const [dd, mm] = sql(`select to_char(cr_today(), 'FMDD|FMMM')`).split('|');
      const enrolledAt = hhmmCR(sql(`select at from audit_log where action = 'discount_till_enrolled' order by id desc limit 1`));
      assert.deepStrictEqual(wb, { hidden: false, h3: ES.wrong, days: [{
        head: `${dd} ${MON[mm - 1]} · 3 códigos equivocados · 2 en el código de encargado · 1 en el código de empleado · 3 sin coincidencia`,
        subs: ['Puesto 1 · Caja · 3 códigos equivocados · 1 espera iniciada', `Caja · Puesto 1 · registrada a las ${enrolledAt} por Ana`] }] }, 'the «Códigos equivocados» block');
      await noMarkup(so, 'Sales');

      // a manager gives Marta's day back (another device, the owner areas open with Ana's PIN): the row reads «Quitado de la cuenta»
      const tok = gw.sessionFor('cafe@test.local').access_token;
      const u = await rpcTok(tok, 'access_unlock', { p_staff_id: STAFF.ana, p_pin: PINS.ana });
      assert.ok(u && u.ok, 'the owner areas opened: ' + JSON.stringify(u));
      let back;
      try { back = await rpcTok(tok, 'descuento_cupo_devolver', { p_approval_id: h.id, p_manager_id: STAFF.ana, p_manager_pin: PINS.ana, p_station: 'Tableta 403' }, u.token); }
      finally { await rpcTok(tok, 'access_lock', {}, u.token).catch(() => {}); }
      assert.ok(back && back.ok && back.how === 'bill_removed', 'the day given back: ' + JSON.stringify(back));
      await so.reload({ waitUntil: 'domcontentloaded' });
      await so.waitForSelector('#dcCard:not([hidden])', { timeout: 15000 });
      await until(async () => (await reportRows(so)).filter((r) => r.who === 'Marta' && r.status === ES.status.removed).length === 1, 8000, 'the taken-off row given back');
      assert.deepStrictEqual(sortK(seen(await reportRows(so))), sortK(want.map((r) => (r.status === ES.status.removed_counts ? Object.assign({}, r, { status: ES.status.removed }) : r))),
        'only that row changed: «Quitado de la cuenta»');
      assert.deepStrictEqual(byFirst((await sumTables(so))[ES.caption.emp].rows), { Luis: ['1', '1', crc(1200)], Marta: ['2', '0', crc(0)] }, 'the summaries unchanged (nothing given)');
      await noMarkup(so, 'Sales after the reload');
    }
  },
  {
    name: 'the accountant\'s login (phone code) reads the report: descuentos.csv in the month\'s package holds the same rows as the owner\'s «Descargar descuentos (CSV)»; and nothing it should not: no sign-in id, device key, request id or code in it, no discount table, till or log row, every café discount function answers no_account, without the phone code not_allowed',
    run: async ({ browser }) => {
      testMenu();
      const pg = await till(browser);
      await tap(pg, NAME.batido); await tap(pg, NAME.agua);
      const a = await give(pg, 'empleado', { employee: 'luis' });
      await sell(pg, a);
      const l = await rpcAs(pg, 'descuento_autorizar', { p_category: 'local', p_pin: PINS.ana, p_subtotal: 2000, p_request_id: uuid(), p_station: 'Caja' });
      assert.ok(l.ok, JSON.stringify(l));
      assert.ok((await rpcAs(pg, 'descuento_liberar', { p_id: l.id })).ok);
      const w = await rpcAs(pg, 'descuento_autorizar', { p_category: 'local', p_pin: WRONG, p_subtotal: 2000, p_request_id: uuid(), p_station: 'Caja' });
      assert.strictEqual(w.error, 'bad_pin');
      // what must never reach the accountant: this till's sign-in, its device key, the request ids, the codes
      const tillRow = sqlJson(`select row_to_json(t) from (select session_id, key_hash from discount_tills where ended_at is null) t`);
      const devKey = (await pg.evaluate(() => JSON.parse(localStorage.getItem('hg-disc-till') || 'null'))).key;
      const secrets = [tillRow.session_id, tillRow.key_hash, devKey].concat(sql(`select string_agg(request_id::text, ' ') from discount_approvals`).split(' '), sql(`select string_agg(login_id::text, ' ') from discount_approvals`).split(' '));
      assert.ok(secrets.every((x) => x && x.length >= 8), 'the values to look for: ' + JSON.stringify(secrets));
      const clean = (where, txt) => {
        for (const x of secrets) assert.ok(!String(txt).includes(x), where + ' holds a sign-in id, a device key, a login or a request id: ' + x);
        assert.deepStrictEqual(anyPin(txt), [], where + ' holds a code');
      };

      // the owner's download from Sales, the reference
      const so = await salesPage(browser);
      await until(async () => (await reportRows(so)).length === 2, 8000, 'the two approvals in the owner\'s report');
      const [dl] = await Promise.all([so.waitForEvent('download'), so.click('#dcCsv')]);
      const owner = readCsv(await dl.path());
      // the accountant's month
      const acc = await accountantPackage(browser);
      assert.match(acc.name, /^contabilidad-\d{4}-\d\d\.zip$/);
      const ac = readCsv(acc.file, 'descuentos.csv');
      const rowsOf = (rs) => rs.filter((r) => /^\d{4}-\d\d-\d\d$/.test(r.day)).map((r) => [r.day, r.category, r.status, r.given, r.beneficiary, r.company, r.authorizer, r.role, r.station,
        r.receipt_no, r.list_value_crc, r.discount_crc, r.charged_crc, r.refunded_crc, r.flags, r.reason].join('|')).sort();
      assert.strictEqual(rowsOf(ac.rows).length, 2, 'the accountant\'s file has the two approvals: ' + JSON.stringify(ac.rows));
      assert.deepStrictEqual(rowsOf(ac.rows), rowsOf(owner.rows), 'the accountant sees the same report as the owner');
      assert.deepStrictEqual(ac.rows.filter((r) => /^\d{4}-/.test(r.day)).map((r) => [r.category, r.status, r.beneficiary, r.discount_crc, r.charged_crc]).sort(),
        [['empleado', 'used', 'Luis', '1200', '2800'], ['local', 'released', '', '200', '']], 'the used Empleado and the Local let go, with their amounts');
      for (const h of ac.head.concat(owner.head)) assert.ok(!/session|login|request|key|token|pin|till/i.test(h), 'no column for a sign-in, a key, a request or a code: ' + h);
      clean('descuentos.csv', ac.raw);
      clean('the owner\'s CSV', owner.raw);
      assert.deepStrictEqual(acc.pg.rpcs.filter((r) => /^descuento/.test(r.fn || '')).map((r) => r.fn), ['descuentos_informe'], 'the accounting page asks only for the report');
      await noMarkup(acc.pg, 'contabilidad');

      // the same report through the API with the accountant's own sign-in: ok, and nothing private in it
      const accTok = await acc.pg.evaluate((k) => JSON.parse(localStorage.getItem(k)).access_token, AUTH_KEY);
      const rep = await rpcTok(accTok, 'descuentos_informe', { p_from: null, p_to: null });
      assert.strictEqual(rep.ok, true, 'the accountant reads descuentos_informe');
      const keys = new Set(); (function walk(v) { if (v && typeof v === 'object') for (const [k, x] of Object.entries(v)) { keys.add(k); walk(x); } })(rep);
      assert.deepStrictEqual([...keys].filter((k) => /session|login|request|key|token|pin|till_id|hash/i.test(k)), [], 'no sign-in, key, request or code field in the report');
      clean('the report', JSON.stringify(rep));
      // nothing else: the tables stay closed, every café discount function says no_account
      for (const t of ['discount_approvals?select=*', 'discount_tills?select=*', 'audit_log?select=action,details&action=like.discount*']) {
        const r = await rest(accTok, t);
        assert.ok(r.status >= 400 || r.body === '[]', 'the accountant reads no ' + t.split('?')[0] + ' rows: ' + r.status + ' ' + r.body.slice(0, 200));
      }
      const calls = { descuento_estado: { p_station: 'x' }, descuento_cajas: {}, descuento_caja_registrar: { p_station: 'x' }, descuento_caja_volver: { p_key: devKey },
        descuento_autorizar: { p_category: 'local', p_pin: WRONG, p_subtotal: 1000 }, descuento_liberar: { p_id: l.id }, descuento_cupo_devolver: { p_approval_id: a },
        descuento_quitar_cuenta: { p_order_id: BILL, p_expect: 0 }, descuento_caja_reanudar: { p_slot: 1 }, descuento_caja_quitar: { p_till_id: uuid() } };
      for (const [fn, args] of Object.entries(calls)) {
        const r = await rpcTok(accTok, fn, args).catch((e) => ({ thrown: e.message }));
        assert.deepStrictEqual([r.ok, r.error], [false, 'no_account'], 'the accountant gets no_account from ' + fn + ': ' + JSON.stringify(r));
      }
      assert.deepStrictEqual(sqlJson(`select json_agg(json_build_object('session_id', session_id, 'key_hash', key_hash)) from discount_tills`), [tillRow],
        'the accountant registered no till and spent no key: the POS\'s till as it was');
      assert.strictEqual(sql(`select freed_how from discount_approvals where id = '${a}'`), '', 'nothing of the sold approval changed');
      // the accountant without the phone code, and the café login without the owner areas: not_allowed
      for (const [who, tok] of [['the accountant without the phone code', gw.sessionFor('contador@test.local', 'aal1').access_token], ['the café login', gw.sessionFor('cafe@test.local').access_token]]) {
        const r = await rpcTok(tok, 'descuentos_informe', { p_from: null, p_to: null });
        assert.deepStrictEqual([r.ok, r.error, r.rows], [false, 'not_allowed', undefined], who + ' may not read the report: ' + JSON.stringify(r).slice(0, 200));
      }
    }
  },
  {
    name: 'Home › system settings: the old free window shows on (until the activation ends), Guía Turista off with its guard explained (the accountant\'s IVA confirmation, A-13); turning Guía on without the confirmation is refused (needs_confirmation): the switch goes back to off, nothing saved',
    run: async ({ browser }) => {
      const pg = dialogs(await page(browser, { login: 'owner', aal: 'aal2', lang: 'es' }));
      watch(pg);
      await goto(pg, '/home');
      await pg.waitForSelector('#setCard:not([hidden])', { timeout: 15000 });
      const readRows = () => pg.evaluate(async () => { await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))); return [...document.querySelectorAll('#setList .setrow')].map((r) => {
        const b = r.querySelector('b'), sel = r.querySelector('select');
        return { label: b.firstChild.textContent, locked: !!b.querySelector('span'), value: sel.value, shown: sel.options[sel.selectedIndex].textContent,
                 options: [...sel.options].map((o) => [o.value, o.textContent]), desc: r.querySelector('.s').textContent, descTranslate: r.querySelector('.s').hasAttribute('data-no-translate') };
      }); });
      let rows;
      await until(async () => { rows = await readRows(); return rows.some((r) => r.label === ES.setGuia); }, 8000, 'the discount switches in the card');
      const free = rows.find((r) => r.label === ES.setFree), guia = rows.find((r) => r.label === ES.setGuia);
      assert.ok(free, 'the old free window\'s switch shows: ' + JSON.stringify(rows.map((r) => r.label)));
      assert.deepStrictEqual(free, { label: ES.setFree, locked: false, value: 'on', shown: ES.setFreeOn, options: [['on', ES.setFreeOn], ['off', ES.setFreeOff]], desc: ES.descFree, descTranslate: true },
        'pos_free_discount: on, as it ships, with its own choice labels');
      assert.deepStrictEqual(guia, { label: ES.setGuia, locked: true, value: 'off', shown: ES.setGuiaOff, options: [['off', ES.setGuiaOff], ['on', ES.setGuiaOn]], desc: ES.descGuia, descTranslate: true },
        'pos_discount_guia: off and locked, its guard explained');
      assert.ok(await pg.isVisible('#confBox'), 'the box to record a confirmation shows');
      const conf = await pg.evaluate(() => [...document.querySelectorAll('#confKey option')].map((o) => [o.value, o.textContent]));
      assert.deepStrictEqual(conf.filter((c) => c[0] === 'courtesy_iva_confirmed'), [['courtesy_iva_confirmed', 'courtesy_iva_confirmed']], 'its guard listed there, not confirmed yet (no ✓)');
      // turning it on without the confirmation
      const answer = pg.waitForResponse((r) => /rpc\/setting_set/.test(r.url()), { timeout: 8000 });
      await pg.locator('#setList .setrow', { hasText: ES.setGuia }).locator('select').selectOption('on');
      const res = await (await answer).json();
      assert.deepStrictEqual([res.ok, res.error], [false, 'needs_confirmation'], 'the server refuses it: ' + JSON.stringify(res));
      assert.deepStrictEqual(JSON.parse(pg.rpcs.filter((r) => r.fn === 'setting_set').pop().body), { p_key: 'pos_discount_guia', p_value: 'on' });
      await see(pg, '#setMsg', ES.needsConf);
      assert.strictEqual(await pg.locator('#setList .setrow', { hasText: ES.setGuia }).locator('select').inputValue(), 'off', 'the switch goes back to off');
      assert.strictEqual(sql(`select coalesce((select value::text from settings where key = 'pos_discount_guia'), 'default') || '/' || public.setting('pos_discount_guia')::text`), 'default/"off"', 'nothing saved');
      assert.strictEqual(sql(`select count(*) from compliance_confirmations where key = 'courtesy_iva_confirmed'`), '0', 'no confirmation recorded');
      assert.strictEqual(sql(`select count(*) from audit_log where action = 'setting_change'`), '0', 'no setting change in the log');
      // and the POS still has it off
      const st = await rpcTok(gw.sessionFor('cafe@test.local').access_token, 'descuento_estado', { p_station: 'Caja' });
      assert.strictEqual(st.guia_enabled, false, 'the POS still sees Guía Turista off');
      assert.strictEqual(sql(`select public.setting('pos_free_discount')::text`), '"on"', 'the old window untouched');
      assert.deepStrictEqual(pg.dialogs, []);
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'stock, register and books: an Empleado sale and a courtesy take exactly the stock of the same sale without a discount (each recipe line, at the same cost); the register closing counts the three (the courtesy as \'other\' at ₡0); the daily posting stays off (A-07), the day waiting with revenue and IVA on the discounted amounts; the discounted sale\'s IVA is the one the ticket shows',
    run: async ({ browser }) => {
      testMenu(); guiaOn();
      const pg = await till(browser);
      const both = async () => { await tap(pg, NAME.batido); await tap(pg, NAME.agua); };
      const shown = async () => ({ sub: await text(pg, '#subAmt'), disc: await text(pg, '#discAmt'), total: await text(pg, '#totalAmt'), iva: await text(pg, '#ivaAmt'), ivaLbl: await text(pg, '#ivaLbl') });
      // 1) the sale without a discount
      await both();
      await see(pg, '#totalAmt', crc(4000));
      const plain = await shown();
      const o1 = await sell(pg, null);
      // 2) the same with Empleado for Luis
      await both();
      const a = await give(pg, 'empleado', { employee: 'luis' });
      await see(pg, '#totalAmt', crc(2800));
      const emp = await shown();
      const o2 = await sell(pg, a);
      // 3) the same as a tour guide courtesy
      await both();
      const g = await give(pg, 'guia', { company: 'Selvatura' });
      await see(pg, '#totalAmt', crc(0));
      const cour = await shown();
      const o3 = await sell(pg, g, '#courtesyBtn');
      noCodeLeak(pg);
      assert.deepStrictEqual([emp.sub, emp.disc, emp.total], [crc(4000), '−' + crc(1200), crc(2800)], 'the ticket of the Empleado sale');
      assert.deepStrictEqual([cour.sub, cour.disc, cour.total, cour.iva], [crc(4000), '−' + crc(4000), crc(0), crc(0)], 'the courtesy\'s ticket: ₡0, IVA ₡0');

      // the stock: each sale takes the recipe of its products, at the same cost, discount or not
      const m1 = movesOf(o1);
      assert.strictEqual(m1, 'Agua 403:-1@500:sale Fresa 403:-120@4:sale Leche 403:-100@1:sale', 'the plain sale takes each recipe line');
      assert.strictEqual(movesOf(o2), m1, 'the Empleado sale takes exactly the same stock');
      assert.strictEqual(movesOf(o3), m1, 'the courtesy takes exactly the same stock');
      assert.strictEqual(sql(`select string_agg(name || '=' || trim_scale(on_hand)::text, ' ' order by name) from stock_items where name like '% 403'`), 'Agua 403=-3 Fresa 403=-360 Leche 403=-300', 'three times the recipe off the shelf');

      // the IVA: on the discounted amount, as the ticket shows it, line by line on the server
      const num = (s) => Number(String(s).replace(/[^\d]/g, ''));
      const ord = (o) => sqlJson(`select row_to_json(t) from (select total_crc, subtotal_crc, discount_crc, tax_crc, payment_method, receipt_no is not null as receipt,
                                         (select json_agg(json_build_object('name', item_name, 'gross', price_crc * qty, 'alloc', coalesce(discount_alloc_crc, 0), 'rate', tax_rate, 'tax', tax_crc, 'net', net_crc) order by item_name)
                                            from order_items where order_id = o.id) as lines from orders o where id = '${o}') t`);
      const [s1, s2, s3] = [ord(o1), ord(o2), ord(o3)];
      const ivaOf = (s) => s.lines.reduce((t, l) => t + (l.gross - l.alloc) * Number(l.rate) / (1 + Number(l.rate)), 0);
      assert.strictEqual(num(plain.iva), s1.tax_crc, 'the plain sale: the ticket\'s IVA is the server\'s');
      assert.strictEqual(num(emp.iva), s2.tax_crc, 'the Empleado sale: the ticket\'s IVA is the server\'s');
      assert.strictEqual(emp.ivaLbl, 'Incluye IVA 13% · 4%', 'both rates on the ticket');
      assert.deepStrictEqual(s2.lines.map((l) => [l.name, l.gross, l.alloc]), [[NAME.agua, 1000, 300], [NAME.batido, 3000, 900]], 'the discount spread over the lines (30 % of each)');
      assert.strictEqual(s2.discount_crc, 1200);
      // each line's IVA is the IVA included in what is charged for it (its amount less its share of the discount), in colones
      for (const s of [s1, s2]) for (const l of s.lines) {
        const exact = (l.gross - l.alloc) * Number(l.rate) / (1 + Number(l.rate));
        assert.ok(Math.abs(Number(l.tax) - exact) <= 0.5 && Number(l.net) === l.gross - l.alloc - Number(l.tax), 'the IVA of ' + l.name + ' on ₡' + (l.gross - l.alloc) + ': ' + JSON.stringify(l));
      }
      assert.strictEqual(s2.lines.reduce((t, l) => t + Number(l.tax), 0), s2.tax_crc, 'the lines\' IVA adds up to the sale\'s');
      assert.ok(Math.abs(s2.tax_crc - ivaOf(s2)) < 1, 'the Empleado sale\'s IVA is on the discounted amounts (₡2 100 at 13 %, ₡700 at 4 %): ' + s2.tax_crc + ' vs ' + ivaOf(s2));
      assert.ok(s2.tax_crc < s1.tax_crc, 'and less than the plain sale\'s ' + s1.tax_crc);
      assert.deepStrictEqual([s3.total_crc, s3.subtotal_crc, s3.discount_crc, s3.tax_crc, s3.payment_method, s3.receipt], [0, 4000, 4000, 0, 'other', true], 'the courtesy: ₡0, \'other\', IVA 0, a receipt');
      assert.ok(s3.lines.every((l) => l.alloc === l.gross && Number(l.tax) === 0 && Number(l.net) === 0), 'each courtesy line: discounted in full, IVA 0, net 0: ' + JSON.stringify(s3.lines));

      // the register closing on the POS: the three orders, ₡6 800 by card, the courtesy at ₡0
      await pg.click('#dayBtn');
      await pg.waitForSelector('#rcCash', { state: 'visible', timeout: 10000 });
      let day;
      await until(async () => { day = await pg.evaluate(() => [...document.querySelectorAll('#dayBody .dayrow')].map((r) => [...r.children].map((c) => c.textContent.replace(/[\u00a0\u202f]/g, ' ').trim()))); return day.some((r) => r[0] === 'Pedidos'); }, 5000, 'Today\'s summary in Spanish');
      assert.deepStrictEqual(day.find((r) => r[0] === 'Pedidos'), ['Pedidos', '3'], 'Today counts the three orders, the courtesy too: ' + JSON.stringify(day));
      assert.deepStrictEqual(day.find((r) => r[0] === 'Tarjeta'), ['Tarjeta', crc(6800)], 'card: the plain sale and the discounted one');
      assert.deepStrictEqual(day.find((r) => r[0] === 'Total'), ['Total', crc(6800)], 'the courtesy adds ₡0');
      assert.deepStrictEqual(day.find((r) => /^Debe haber en la caja/.test(r[0])), ['Debe haber en la caja (fondo + efectivo)', crc(50000)], 'nothing in the drawer for the courtesy');
      await pg.fill('#rcTerminal', '6800');
      await pg.fill('#rcCash', '50000');
      await pg.selectOption('#rcStaff', STAFF.ana);
      await pg.fill('#rcPin', PINS.ana);
      await pg.click('#regCloseForm button[type=submit]');
      await until(() => sql(`select closed_at is not null from register_days where business_date = cr_today()`) === 't', 10000, 'the register closed');
      assert.deepStrictEqual(sqlJson(`select row_to_json(t) from (select orders_count, sales_cash_crc, sales_card_crc, sales_sinpe_crc, sales_other_crc, sales_total_crc,
                                             expected_cash_crc, cash_diff_crc, card_diff_crc from register_days where business_date = cr_today()) t`),
        { orders_count: 3, sales_cash_crc: 0, sales_card_crc: 6800, sales_sinpe_crc: 0, sales_other_crc: 0, sales_total_crc: 6800, expected_cash_crc: 50000, cash_diff_crc: 0, card_diff_crc: 0 },
        'the closing: three orders, the courtesy as other at ₡0, nothing expected in the drawer for it, no difference');

      // the books: automatic posting stays off (A-07), so the close posts nothing; the day waits with what it would post
      assert.strictEqual(sql(`select public.setting('ledger_auto_post')::text`), 'false', 'ledger_auto_post off, as it ships');
      assert.strictEqual(sql(`select count(*) from acct.entries`), '0', 'no journal entry from the close');
      assert.strictEqual(sql(`select count(*) from audit_log where action = 'ledger_post_failed'`), '0', 'and no failed posting');
      const tgt = Object.fromEntries(sql(`select account || '=' || trim_scale(amount)::text from acct.day_target(cr_today())`).split('\n').filter(Boolean).map((x) => x.split('=')));
      const acctOf = (k) => sql(`select acct.map('${k}')`);
      const tax = s1.tax_crc + s2.tax_crc;
      assert.strictEqual(Number(tgt[acctOf('iva_out')]), -tax, 'the day\'s IVA: the plain sale\'s and the discounted sale\'s, the courtesy 0: ' + JSON.stringify(tgt));
      assert.strictEqual(Number(tgt[acctOf('revenue')]), -(6800 - tax), 'revenue without IVA on what was charged (the courtesy 0)');
      assert.strictEqual(Number(tgt[acctOf('pay_card')]), 6800, 'card money');
      assert.ok(!(acctOf('advances') in tgt) && !(acctOf('pay_other') in tgt), 'no advance and no other money for the courtesy: ' + JSON.stringify(tgt));
      assert.strictEqual(Number(tgt[acctOf('cogs')]), 3 * (120 * 4 + 100 * 1 + 500), 'the cost of goods of the three sales, the courtesy\'s too');
      // the accountant's IVA by rate (tax_summary): each rate on what was charged, the courtesy's lines at 0, nothing untaxed
      const today = sql(`select cr_today()::text`);
      const ts = await rpcTok(gw.sessionFor('contador@test.local', 'aal2').access_token, 'tax_summary', { p_from: today, p_to: today });
      const line = (name, s) => s.lines.find((x) => x.name === name);
      assert.deepStrictEqual(ts.by_rate.map((x) => [x.code, Number(x.rate), x.lines, Number(x.gross_crc), Number(x.tax_crc)]).sort(),
        [['IVA13', 0.13, 3, 3000 + 2100 + 0, line(NAME.batido, s1).tax + line(NAME.batido, s2).tax + 0], ['IVA4', 0.04, 3, 1000 + 700 + 0, line(NAME.agua, s1).tax + line(NAME.agua, s2).tax + 0]].sort(),
        'IVA by rate on the discounted amounts: ' + JSON.stringify(ts.by_rate));
      assert.strictEqual(ts.by_rate.reduce((t, x) => t + Number(x.tax_crc), 0), tax, 'the same IVA as the day\'s target');
      assert.deepStrictEqual([ts.without_tax_detail.orders, ts.refunds_tax_crc], [0, 0], 'the courtesy is not an untaxed sale');
      assert.deepStrictEqual(pg.dialogs, []);
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'P4: a Local approval used by a second sale (sent from another device after the first used it) is kept, flagged and listed apart: «Usado · sin verificar», «Aprobación ya usada por otra venta», what it charged; the report keeps its products, its own station, its Costa Rica business day (a sale at 18:30, the next day in UTC) and who authorized the approval it claimed, in the table, «Descargar descuentos (CSV)» and descuentos.csv',
    run: async ({ browser }) => {
      testMenu();
      const pg = await till(browser);
      await tap(pg, NAME.batido); await tap(pg, NAME.agua);
      const l = await give(pg, 'local');
      await see(pg, '#discLbl', ES.ticket.local);
      const o1 = await sell(pg, l);
      // another device of the café sends a sale it kept, carrying the same approval (what a till that sold offline sends)
      const o2 = uuid();
      const r = await rpcTok(gw.sessionFor('cafe@test.local').access_token, 'pos_record_sale', { p_order: {
        id: o2, total_crc: 3600, payment_method: 'card', paid: true, status: 'done', source: 'front', station: 'Caja B', subtotal_crc: 4000, discount_crc: 400, discount_id: l,
        items: [{ item_name: NAME.batido, price_crc: 3000, qty: 1, menu_item_id: ITEM.batido }, { item_name: NAME.agua, price_crc: 1000, qty: 1, menu_item_id: ITEM.agua }] } });
      assert.ok(r && r.ok, 'the server records the money taken (never refuses it): ' + JSON.stringify(r));
      assert.strictEqual(sql(`select coalesce(discount_id::text, '-') || '|' || coalesce(discount_by, '-') || '|' || discount_reason || '|' || total_crc || '|' || ('discount_not_verified' = any(flags)) from orders where id = '${o2}'`),
        '-|-|Local · not verified|3600|true', 'kept with the money as charged, not linked, nobody named, flagged');
      assert.strictEqual(sql(`select details ->> 'why' || '|' || (details ->> 'approval') from audit_log where action = 'discount_not_verified' and target_id = '${o2}'`), 'used_by_other|' + l);
      assert.strictEqual(sql(`select order_id from discount_approvals where id = '${l}'`), o1, 'the approval stays with the first sale');
      // the second sale rung at 18:30 Costa Rica today (00:30 UTC of the next day: the UTC date is not the business day),
      // its log row the same moment, so the report of today lists it (test superuser, this copy only)
      const at1830 = sql(`select to_json(public.cr_day_start(public.cr_today()) + interval '18 hours 30 minutes') #>> '{}'`);
      sql(`update orders set created_at = '${at1830}' where id = '${o2}';
           update audit_log set at = '${at1830}' where action = 'discount_not_verified' and target_id = '${o2}'`);
      const today = sql(`select public.cr_today()::text`);
      assert.notStrictEqual(new Date(at1830).toISOString().slice(0, 10), today, 'the UTC date of 18:30 Costa Rica is the next day');

      // the report itself (descuentos_informe) carries them: the anomaly's products, its own station and the claimed
      // approval's authorizer
      const rep = await rpcTok(gw.sessionFor('owner@test.local', 'aal2').access_token, 'descuentos_informe', { p_from: null, p_to: null });
      assert.deepStrictEqual((rep.anomalies || []).map((x) => [x.order_id, x.approval, x.category, x.status, x.authorizer, x.role, x.station, (x.products || []).map((p) => p.qty + '× ' + p.name).sort()]),
        [[o2, l, 'local', 'used_unverified', 'Ana', 'manager', 'Caja B', [`1× ${NAME.agua}`, `1× ${NAME.batido}`]]], 'descuentos_informe lists the anomaly with its products, station and who: ' + JSON.stringify(rep.anomalies));
      const so = await salesPage(browser);
      await until(async () => (await reportRows(so)).length === 2, 8000, 'the approval and the second sale in the table');
      const rows = await reportRows(so);
      const first = rows.find((x) => x.receipt === sql(`select receipt_no from orders where id = '${o1}'`));
      const second = rows.find((x) => x.receipt === sql(`select receipt_no from orders where id = '${o2}'`));
      assert.ok(first && second, JSON.stringify(rows));
      assert.deepStrictEqual([first.cat, first.status, first.by, first.charged], [ES.cat.local, ES.status.used, 'Ana', crc(3600)], 'the approval\'s own row: used by the first sale');
      assert.deepStrictEqual([second.cat, second.status, second.flags, second.list, second.discount, second.charged, second.who],
        [ES.cat.local, 'Usado · sin verificar', ['Aprobación ya usada por otra venta'], crc(4000), crc(400), crc(3600), '—'], 'the second sale listed apart, marked, with what it charged');
      const [dl] = await Promise.all([so.waitForEvent('download'), so.click('#dcCsv')]);
      const sc = readCsv(await dl.path());
      const acc = await accountantPackage(browser);
      const ac = readCsv(acc.file, 'descuentos.csv');
      const anomaly = (rs) => rs.filter((x) => x.receipt_no === sql(`select receipt_no from orders where id = '${o2}'`) && x.status === 'used_unverified')
        .map((x) => ({ products: (x.products || '').split(/[,;] /).filter(Boolean).sort(), authorizer: x.authorizer, role: x.role, station: x.station, day: x.day,
                       time: x.time === undefined ? hhmmCR(x.at) : x.time }));
      // P4 (proposal appendix: «unverified sales lose category, products and authorizer in the report», fixed by the audit
      // row the report reads; §5.1 item 16 «for a not-verified sale, its products»; api-0038 §4.6 and §13 item 30)
      const seenP4 = { table: { products: second.products.split(', ').sort(), by: second.by, role: second.role }, salesCsv: anomaly(sc.rows), accountantCsv: anomaly(ac.rows) };
      assert.deepStrictEqual(seenP4, {
        table: { products: [`1× ${NAME.agua}`, `1× ${NAME.batido}`], by: 'Ana', role: ES.role.manager },
        salesCsv: [{ products: [`1× ${NAME.agua}`, `1× ${NAME.batido}`], authorizer: 'Ana', role: 'manager', station: 'Caja B', day: today, time: '18:30' }],
        accountantCsv: [{ products: [`1x ${NAME.agua}`, `1x ${NAME.batido}`], authorizer: 'Ana', role: 'manager', station: 'Caja B', day: today, time: '18:30' }]
      }, 'the not-verified sale keeps its products, its own station (o.station), its Costa Rica business day (18:30 is not the next UTC day) and who authorized the approval it claimed, everywhere the report is read; it shows ' + JSON.stringify(seenP4));
      await noMarkup(so, 'Sales');
      await noMarkup(acc.pg, 'contabilidad');
    }
  },
  {
    name: 'a database without descuentos_informe (before 0038): Sales hides «Descuentos por categoría» and the rest of the page works; the accountant\'s month still downloads, without descuentos.csv (fetched apart, never failing the package)',
    run: async ({ browser }) => {
      const missing = (r) => r.fulfill({ status: 404, contentType: 'application/json',
        body: JSON.stringify({ code: 'PGRST202', details: null, hint: null, message: 'Could not find the function public.descuentos_informe(p_from, p_to) in the schema cache' }) });
      sql(`insert into orders (id, total_crc, payment_method, paid, status) values ('${uuid()}', 2000, 'card', true, 'done')`);
      const so = dialogs(await page(browser, { login: 'owner', aal: 'aal2', lang: 'es' }));
      await so.route(/\/rest\/v1\/rpc\/descuentos_informe/, missing);
      const asked = so.waitForResponse((r) => /rpc\/descuentos_informe/.test(r.url()), { timeout: 15000 });
      await goto(so, '/sales');
      assert.strictEqual((await asked).status(), 404, 'the page asked, and the database had no such function');
      await until(async () => (await so.locator('#txBody tr').count()) === 1, 15000, 'the day\'s sale in «Transacciones»');
      await so.waitForLoadState('networkidle');
      assert.ok(await so.isHidden('#dcCard'), 'no discounts section');
      assert.deepStrictEqual(so.errors, [], 'no page error');
      // the accountant's package without the file
      const pg = dialogs(await page(browser, { login: 'accountant', aal: 'aal2', lang: 'es' }));
      await pg.route(/\/rest\/v1\/rpc\/descuentos_informe/, missing);
      await goto(pg, '/contabilidad');
      await pg.waitForSelector('#appView:not([hidden])', { timeout: 15000 });
      await pg.evaluate(() => { location.hash = 'reportes'; });
      await pg.waitForSelector('#rPack', { timeout: 15000 });
      const [zip] = await Promise.all([pg.waitForEvent('download', { timeout: 20000 }), pg.click('#rPack')]);
      const [bad, names] = zipNames(await zip.path());
      assert.strictEqual(bad, null, 'a valid ZIP');
      assert.ok(!names.includes('descuentos.csv'), 'descuentos.csv left out: ' + names.join(', '));
      assert.deepStrictEqual(names.filter((n) => !/^inventario-valorado-/.test(n)).sort(),
        ['balance-general.csv', 'balanza.csv', 'diario.csv', 'estado-resultados.csv', 'flujo-efectivo.csv', 'gastos.csv', 'iva-compras.csv', 'iva-ventas.csv'], 'the other files all there');
      await noMarkup(pg, 'contabilidad');
    }
  }
  ,
  {
    name: 'P4, the money of a not-verified sale: two more sales claim a Local already used (as two tabs or a replayed queue send them); one paid then voided by Ana, one «Cobrar después» then cancelled: each anomaly reads the rows\' status (Anulado with the voided style, Cuenta cancelada) and Cobrado ₡0, in the table, «Descargar descuentos (CSV)» and descuentos.csv',
    run: async ({ browser }) => {
      testMenu();
      const pg = await till(browser);
      await tap(pg, NAME.batido); await tap(pg, NAME.agua);
      const l = await give(pg, 'local');
      await sell(pg, l);
      const tok = gw.sessionFor('cafe@test.local').access_token;
      const items = (paid) => [{ item_name: NAME.batido, price_crc: 3000, qty: 1, menu_item_id: ITEM.batido }, { item_name: NAME.agua, price_crc: 1000, qty: 1, menu_item_id: ITEM.agua }]
        .map((x) => (paid ? x : Object.assign({ id: uuid() }, x)));
      const o2 = uuid(), o3 = uuid();
      const r2 = await rpcTok(tok, 'pos_record_sale', { p_order: { id: o2, total_crc: 3600, payment_method: 'card', paid: true, status: 'done', source: 'front',
        station: 'Caja B', subtotal_crc: 4000, discount_crc: 400, discount_id: l, items: items(true) } });
      const r3 = await rpcTok(tok, 'pos_record_sale', { p_order: { id: o3, total_crc: 3600, payment_method: 'pending', paid: false, status: 'ready', source: 'front',
        station: 'Caja B', guest_name: 'Mesa repetida', subtotal_crc: 4000, discount_crc: 400, discount_id: l, items: items(false) } });
      assert.ok(r2.ok && r3.ok, 'the money taken is recorded, never refused: ' + JSON.stringify([r2, r3]));
      const v = await rpcTok(tok, 'manager_void_order', { p_manager_id: STAFF.ana, p_manager_pin: PINS.ana, p_order_id: o2, p_reason: 'cobrado dos veces' });
      const c = await rpcTok(tok, 'cancel_unpaid_order', { p_order_id: o3 });
      assert.ok(v.ok && c.ok, 'voided and cancelled: ' + JSON.stringify([v, c]));
      const rec = (o) => sql(`select receipt_no from orders where id = '${o}'`);
      const rep = await rpcTok(gw.sessionFor('owner@test.local', 'aal2').access_token, 'descuentos_informe', { p_from: null, p_to: null });
      assert.deepStrictEqual((rep.anomalies || []).map((x) => [x.order_id, x.status, x.charged, x.refunded, x.total]),
        [[o2, 'voided', 0, 0, 3600], [o3, 'bill_cancelled', 0, 0, 3600]], 'descuentos_informe: the rows\' ladder and what each really charged');
      const so = await salesPage(browser);
      await until(async () => (await reportRows(so)).length === 3, 8000, 'the approval and the two sales in the table');
      const rows = await reportRows(so);
      const two = rows.find((x) => x.receipt === rec(o2)), three = rows.find((x) => x.receipt === rec(o3));
      assert.deepStrictEqual([two.status, two.charged, two.void, two.flags], [ES.status.voided, crc(0), true, ['Aprobación ya usada por otra venta']], 'the voided sale: «Anulado», voided style, ₡0');
      assert.deepStrictEqual([three.status, three.charged, three.void], ['Cuenta cancelada', crc(0), false], 'the cancelled bill: «Cuenta cancelada», ₡0');
      const [dl] = await Promise.all([so.waitForEvent('download'), so.click('#dcCsv')]);
      const sc = readCsv(await dl.path());
      const acc = await accountantPackage(browser);
      const ac = readCsv(acc.file, 'descuentos.csv');
      const money = (rs) => rs.filter((x) => [rec(o2), rec(o3)].includes(x.receipt_no)).map((x) => [x.receipt_no, x.status, x.given, x.charged_crc, x.refunded_crc]).sort();
      const want = [[rec(o2), 'voided', 'no', '0', '0'], [rec(o3), 'bill_cancelled', 'no', '0', '0']].sort();
      assert.deepStrictEqual({ sales: money(sc.rows), accountant: money(ac.rows) }, { sales: want, accountant: want }, 'both CSVs: charged_crc 0, not the order\'s total');
      await noMarkup(so, 'Sales');
    }
  },
  {
    name: 'the report times out (the server\'s 8 s limit): Sales keeps «Descuentos por categoría» with «No se pudieron cargar los descuentos…» and no CSV; the accountant\'s month downloads with a note in place of descuentos.csv and says so on the screen',
    run: async ({ browser }) => {
      const timeout = (r) => r.fulfill({ status: 500, contentType: 'application/json',
        body: JSON.stringify({ code: '57014', details: null, hint: null, message: 'canceling statement due to statement timeout' }) });
      sql(`insert into orders (id, total_crc, payment_method, paid, status) values ('${uuid()}', 2000, 'card', true, 'done')`);
      const so = dialogs(await page(browser, { login: 'owner', aal: 'aal2', lang: 'es' }));
      await so.route(/\/rest\/v1\/rpc\/descuentos_informe/, timeout);
      await goto(so, '/sales');
      await so.waitForSelector('#dcCard:not([hidden])', { timeout: 15000 });
      await see(so, '#dcBody', 'No se pudieron cargar los descuentos. Revise la conexión o elija un periodo más corto.');
      assert.ok(await so.isDisabled('#dcCsv'), 'nothing to download');
      assert.deepStrictEqual(so.errors, [], 'no page error');
      const pg = dialogs(await page(browser, { login: 'accountant', aal: 'aal2', lang: 'es' }));
      await pg.route(/\/rest\/v1\/rpc\/descuentos_informe/, timeout);
      await goto(pg, '/contabilidad');
      await pg.waitForSelector('#appView:not([hidden])', { timeout: 15000 });
      await pg.evaluate(() => {
        location.hash = 'reportes';
        window.__toasts = [];
        const t = document.getElementById('toast');
        new MutationObserver(() => { if (t.textContent) window.__toasts.push(t.textContent); }).observe(t, { childList: true, characterData: true, subtree: true });
      });
      await pg.waitForSelector('#rPack', { timeout: 15000 });
      const [zip] = await Promise.all([pg.waitForEvent('download', { timeout: 20000 }), pg.click('#rPack')]);
      const [bad, names] = zipNames(await zip.path());
      assert.strictEqual(bad, null, 'a valid ZIP');
      assert.ok(!names.includes('descuentos.csv') && names.includes('descuentos-NO-INCLUIDO.txt'), 'a note in place of descuentos.csv: ' + names.join(', '));
      await until(() => pg.evaluate(() => window.__toasts.includes('El paquete se armó sin descuentos.csv: no se pudieron leer los descuentos. Descárguelo otra vez.')), 8000, 'the screen says so');
      assert.deepStrictEqual(pg.errors, []);
    }
  }
];
