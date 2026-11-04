/* The tills registered for discounts (migration 0038, the owner's adjustment 2: «Cajas registradas en puestos»), in the
   browser: registering a device in Reloj de marcas › Bitácora (the owner areas open on that same device), the device
   key that brings a till back to its own place after any new sign-in (no PIN), the read-only line in «¿Qué dispositivo
   es este?», each place's own wrong-code count (the wait ladder, the stop, the resume), a locked person's right code
   still accepted at a registered till (rule 5), the café-wide caps per person (till_full, «Reemplazar con este
   dispositivo», person_limit), typed station names as text, every till-state, wait, stop and warning text at 360 × 640
   with its precedence, the approvals log's buckets, a wait timer that follows the server's clock, and one person at one
   tablet unable to stop the discounts of the other tills.
   Sources: mecanismo-intentos.md §1, §3, §8, §10 and §13.3 (C-a … C-n), build-plan.md L1 (no descuento_caja_cerrar, no
   signed_out row: a signed-out till comes back by its key, ending its row 'rebound'), L2 (Guía off), L3, api-0038.md §4
   and §10, decisiones-dueno.md (adjustment 2). */
'use strict';
const assert = require('assert');
const crypto = require('crypto');
const { page, goto, until, sql, sqlJson, openRegister, registerTill, guiaOn, STAFF, PINS } = require('../lib');
const gw = require('../gateway');

const API = 'http://127.0.0.1:' + (Number(process.env.E2E_SITE_PORT || 8090) + 1000);
const CAFE = gw.USERS['cafe@test.local'];
const AUTH_KEY = 'sb-127-auth-token';
/* a second manager (mecanismo §13.3 names her) and a code nobody has */
const BEA = { id: 'a1000000-0000-4000-8000-000000000402', pin: '3917' };
const ID = { ana: STAFF.ana, bea: BEA.id, dueno: STAFF.dueno, luis: STAFF.luis };
const PIN = { ana: PINS.ana, bea: BEA.pin, dueno: PINS.dueno, luis: PINS.luis };
const WRONG = '1111';
const ITEM = 'T Latte 402';

/* the texts as lang.js shows them in Spanish (website/lang.js; mecanismo §10.1-§10.3, api-0038 §10) */
const ES = {
  pick: 'Elija el descuento', emp: 'Código de empleado', mgr: 'Código de encargado', owner: 'Código del dueño', company: 'Empresa del guía turístico',
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
  guiaOff: 'La cortesía Guía Turista espera la confirmación del IVA por el contador (A-13).',
  noOwner: 'Guía Turista necesita el PIN del dueño. El dueño lo agrega en Equipo.',
  // «¿Qué dispositivo es este?» (mecanismo §10.2)
  lineReg: (by, d) => `Descuentos: registrada (${by}, ${d}).`,
  lineNot: 'Descuentos: sin registrar. Un encargado la registra en Reloj de marcas › Bitácora de aprobaciones.',
  lineEnded: 'Descuentos: se quitó el registro; un encargado la registra de nuevo en la bitácora.',
  // Reloj de marcas › Bitácora › «Cajas para descuentos» (mecanismo §10.3)
  register: 'Registrar este dispositivo para descuentos', replace: 'Reemplazar con este dispositivo',
  resume: 'Reanudar descuentos', remove: 'Quitar registro',
  registered: 'Dispositivo registrado para descuentos.', registeredIn: (s) => `Dispositivo registrado en lugar de «${s}».`,
  tillFull: 'Los 3 puestos están ocupados. Elija abajo qué caja reemplaza este dispositivo (cuenta en sus 3 del día).',
  personLimit: 'Usted ya tiene 2 cajas registradas. Reemplace una de las suyas, o que otro encargado registre este dispositivo.',
  resumed: (n) => `Descuentos reanudados en el puesto ${n}.`,
  resumeLimit: (t) => `Ese puesto ya se reanudó en las últimas 24 horas, o el café ya usó sus 2. Vuelve solo a las ${t}.`,
  removed: (s) => `Registro quitado: «${s}».`,
  replaceAsk: (s, t) => `¿Reemplazar «${s}» (último uso ${t}) con este dispositivo?`,
  unknownN: (n) => `${n} códigos escritos en dispositivos sin registrar en 24 h.`,
  wrongN: (n) => (n === 1 ? '1 código equivocado en 24 h' : `${n} códigos equivocados en 24 h`),
  active: 'Activa', here: 'este dispositivo', waiting: (t) => `En espera hasta las ${t}`, stoppedUntil: (d) => `Detenida hasta ${d}`,
  foot: (r, me) => `Reanudaciones en 24 h: ${r} de 2` + (me ? ` · Usted: ${me[0]} de 2 cajas registradas, ${me[1]} de 3 registros quitados o reemplazados, ${me[2]} de 6 dispositivos registrados en 24 h` : ''),
  locked: 'Demasiados PIN incorrectos. Espere 10 minutos e intente de nuevo.',
  // the log's labels (time.html ACTION_LABEL through lang.js)
  log: { wrong: 'Código de descuento equivocado', unknown: 'Código escrito en un dispositivo sin registrar', stopped: 'Descuentos detenidos en una caja',
         enrolled: 'Caja registrada para descuentos', ended: 'Registro de caja quitado', rebound: 'Caja volvió a su puesto',
         pinLocked: 'PIN bloqueado', voided: 'Pedido anulado' },
  labelLocal: 'Descuento Local'
};

/* ---------- small helpers ---------- */
const norm = (s) => String(s == null ? '' : s).replace(/[  ]/g, ' ').replace(/\s+/g, ' ').trim();
const text = async (pg, sel) => norm(await pg.textContent(sel));
const see = (pg, sel, want, ms) => until(async () => {
  const t = await text(pg, sel);
  return want instanceof RegExp ? want.test(t) : t === want;
}, ms || 8000, sel + ' to read «' + want + '»').catch(async (e) => { e.message += ' (it reads «' + (await text(pg, sel).catch(() => '?')) + '»)'; throw e; });
const sha256 = (s) => crypto.createHash('sha256').update(s).digest('hex');
/* Costa Rica (UTC−6, no daylight saving): the formats the pages print, in Spanish (lang.js turns Nov → nov, Thu → jue) */
const MON = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'set', 'oct', 'nov', 'dic'];
const DAY = ['dom', 'lun', 'mar', 'mié', 'jue', 'vie', 'sáb'];
const p2 = (n) => String(n).padStart(2, '0');
const crAt = (ms, up) => new Date((up ? Math.ceil(ms / 60000) * 60000 : ms) - 6 * 3600000);
const hhmm = (ms, up) => { const d = crAt(ms, up); return p2(d.getUTCHours()) + ':' + p2(d.getUTCMinutes()); };
const dmon = (ms) => { const d = crAt(ms); return d.getUTCDate() + ' ' + MON[d.getUTCMonth()] + ' ' + hhmm(ms); };           // «3 nov 10:02»
const dayTime = (ms) => { const d = crAt(ms, true); return DAY[d.getUTCDay()] + ' ' + d.getUTCDate() + ' ' + MON[d.getUTCMonth()] + ' ' + hhmm(ms, true); };
const ms = (iso) => Math.floor(Date.parse(iso));
const sqlMs = (q) => Math.floor(Number(sql(`select extract(epoch from (${q})) * 1000`)));
/* a seed PIN as a value of its own (not a piece of a uuid, a key or a longer number) */
const pinIn = (s, pin) => new RegExp('(^|[^0-9a-f-])' + pin + '([^0-9a-f-]|$)', 'i').test(String(s || ''));
const anyPin = (s) => Object.values(PIN).filter((p) => pinIn(s, p));

function testMenu() {
  sql(`insert into menu_categories (id, name, sort, kitchen) values ('b0000000-0000-4000-8000-0000000402c1', 'Test Bar 402', 0, false);
       insert into menu_items (id, category_id, name, price_crc, sort, available) values
         ('b0000000-0000-4000-8000-0000000402a1', 'b0000000-0000-4000-8000-0000000402c1', '${ITEM}', 2000, 1, true)`);
}
function addBea() {
  sql(`insert into public.staff (id, name, role, active, pin_hash) values ('${BEA.id}', 'Bea', 'manager', true, extensions.crypt('${BEA.pin}', extensions.gen_salt('bf')))`);
}
/* the live till of a place, as the database keeps it */
function tillAt(slot) {
  return sqlJson(`select row_to_json(t) from (select id, slot, station, enrolled_by, enrolled_by_name, key_hash, session_id, rebound_from,
                         floor(extract(epoch from enrolled_at) * 1000)::bigint as since
                    from public.discount_tills where slot = ${slot} and ended_at is null) t`);
}
/* fixture rows of a place (the test superuser): wrong codes typed «ages» seconds ago, and a fresh start of its count (a
   resume row of the owner's SQL tool: counts are taken after the last resume by id, and the tool counts toward no cap) */
function wrongRows(slot, ages) {
  if (!ages.length) return;
  sql(`insert into public.audit_log (at, action, target_id, summary, details)
       select now() - make_interval(secs => u.a), 'discount_code_wrong',
              coalesce((select id::text from public.discount_tills where slot = ${slot} and ended_at is null), ''), 'fixture 402',
              jsonb_build_object('slot', ${slot}, 'step', 'manager', 'why', 'no_match', 'category', 'local', 'station', 'fixture', 'till_station', 'fixture')
         from unnest(array[${ages.join(',')}]::float8[]) with ordinality u(a, i) order by u.i`);
}
const times = (n, age) => Array.from({ length: n }, () => age);
function freshPlace(slot) {
  sql(`insert into public.audit_log (action, target_id, summary, details)
       values ('discount_till_resumed', '${slot}', 'fixture 402: the place starts again', jsonb_build_object('slot', ${slot}, 'how', 'sql_editor'))`);
}
/* as if the time had passed on the server: the place's wrong codes moved back */
function shiftBack(slot, secs) {
  sql(`update public.audit_log set at = at - make_interval(secs => ${secs}) where action = 'discount_code_wrong' and details ->> 'slot' = '${slot}'`);
}
const wrongCount = (slot) => Number(sql(`select count(*) from public.audit_log where action = 'discount_code_wrong' and details ->> 'slot' = '${slot}'`));
/* when a stopped place comes back by itself: its 12th most recent wrong code (after its last resume) + 24 hours */
const stopAt = (slot) => sqlMs(`select at + interval '24 hours' from public.audit_log where action = 'discount_code_wrong' and details ->> 'slot' = '${slot}'
                                  and id > coalesce((select max(id) from public.audit_log where action = 'discount_till_resumed' and details ->> 'slot' = '${slot}'), 0)
                                order by at desc, id desc offset 11 limit 1`);
/* «último uso {hora}» today, «último uso {d mmm HH:MM}» another day (time.html) */
const crDay = (t) => crAt(t).toISOString().slice(0, 10);
const lastUse = (t) => 'último uso ' + (crDay(t) === crDay(Date.now()) ? hhmm(t) : dmon(t));

/* every request the page sends to the API, with its body */
function watch(pg) {
  pg.reqs = [];
  pg.on('request', (r) => {
    const u = r.url();
    if (!u.startsWith(API)) return;
    const m = u.match(/\/rest\/v1\/rpc\/([a-z_0-9]+)/);
    pg.reqs.push({ fn: m ? m[1] : null, url: u, body: r.postData() || '' });
  });
}
const sent = (pg, fn) => pg.reqs.filter((r) => r.fn === fn);
/* a code goes only where a person typed it for that purpose (the discount window, the unlock box, the log's own PIN box) */
const CODE_FNS = ['descuento_autorizar', 'access_unlock', 'descuento_caja_reanudar', 'descuento_caja_quitar'];
function noCodeLeak(pg) {
  for (const r of pg.reqs) {
    if (CODE_FNS.includes(r.fn)) continue;
    assert.deepStrictEqual(anyPin(r.url + ' ' + r.body), [], 'a code in a request of ' + (r.fn || r.url) + ': ' + r.body.slice(0, 200));
  }
}

/* the POS on the café login, the register open, its 20-second retry and the live poll off */
async function posPage(browser, opts) {
  opts = Object.assign({ login: 'cafe', lang: 'es', viewport: { width: 1180, height: 820 } }, opts || {});
  openRegister();
  const pg = await page(browser, opts);
  watch(pg);
  if (opts.clockAt) await pg.clock.install({ time: opts.clockAt });
  await pg.addInitScript(() => {
    const si = window.setInterval;
    window.setInterval = function (fn, ms) { return ms === 20000 ? 0 : si.apply(this, arguments); };
  });
  await goto(pg, '/pos');
  await posReady(pg);
  return pg;
}
async function posReady(pg) {
  await pg.waitForSelector('#appView:not([hidden])', { timeout: 15000 });
  await until(() => pg.evaluate(() => document.querySelectorAll('.pbtn').length > 0), 15000, 'the menu');
  if (await pg.isVisible('#dayModal')) await pg.click('#dayClose');
  if (await pg.isVisible('#stationModal')) await pg.click('#stationForm button[type=submit]');
  await pg.evaluate(() => clearInterval(liveTimer));
}
async function tap(pg) {
  const hit = await pg.evaluate((nm) => {
    const find = () => [...document.querySelectorAll('.pbtn')].find((x) => (x.querySelector('.nm') || x).textContent.trim() === nm);
    let b = find();
    for (const t of [...document.querySelectorAll('#rail .tab')]) { if (b) break; t.click(); b = find(); }
    if (b) b.click();
    return !!b;
  }, ITEM);
  if (!hit) throw new Error('no menu button ' + ITEM);
}
async function item(pg) { if (!(await pg.evaluate(() => ticket.length))) await tap(pg); }
async function typeCode(pg, code) { for (const d of code) await pg.click(`#discPad button[data-k="${d}"]`); }
async function openWin(pg) {
  await item(pg);
  await pg.click('#discBtn');
  await pg.waitForSelector('#discModal:not([hidden])', { timeout: 5000 });
  await until(() => pg.evaluate(() => !!(window.disc && disc.st)), 8000, 'the till\'s state');   // (a page clock may be installed)
}
async function closeWin(pg) {
  await pg.click('#discCancel');
  await pg.waitForSelector('#discModal', { state: 'hidden', timeout: 5000 });
}
async function cat(pg, c) {
  await pg.click(`#discForm [data-cat="${c}"]`);
  await until(() => pg.evaluate((x) => document.querySelector(`#discForm [data-cat="${x}"]`).classList.contains('on'), c), 3000, c + ' selected');
}
const nextAnswer = (pg) => pg.waitForResponse((r) => /\/rest\/v1\/rpc\/descuento_autorizar/.test(r.url()), { timeout: 10000 }).then((r) => r.json());
const nextEstado = (pg) => pg.waitForResponse((r) => /\/rest\/v1\/rpc\/descuento_estado/.test(r.url()), { timeout: 15000 }).then((r) => r.json());
/* one attempt in the open window: Empleado's employee code first, Guía's company first; the answer of the server */
async function attempt(pg, c, code, o) {
  o = o || {};
  await cat(pg, c);
  if (c === 'empleado') { await typeCode(pg, o.employee || PIN.luis); await pg.click('#discGo'); await see(pg, '#discStep', ES.mgr); }
  if (c === 'guia') { await pg.fill('#discText', o.company || 'Selvatura'); await pg.click('#discGo'); await see(pg, '#discStep', ES.owner); }
  await typeCode(pg, code);
  const ans = nextAnswer(pg);
  await pg.click('#discGo');
  return ans;
}
/* Local approved with Ana's code: on the ticket, then let go again (the ticket stays free for the next attempt) */
async function approveLocal(pg, who) {
  await openWin(pg);
  const a = await attempt(pg, 'local', PIN[who || 'ana']);
  assert.ok(a.ok, 'Local approved with ' + (who || 'ana') + '\'s code: ' + JSON.stringify(a));
  await pg.waitForSelector('#discModal', { state: 'hidden', timeout: 8000 });
  await see(pg, '#discLbl', ES.labelLocal);
  const freed = pg.waitForResponse((r) => /rpc\/descuento_liberar/.test(r.url()));
  await pg.click('#discX');
  await freed;
  return a;
}
/* the line holds its text: nothing cut off (spec 16) */
const fits = (pg) => pg.evaluate(() => { const e = document.getElementById('discErr'); return { sh: e.scrollHeight, ch: e.clientHeight }; });
async function lineSays(pg, want, what) {
  await see(pg, '#discErr', want);
  const f = await fits(pg);
  assert.ok(f.sh <= f.ch, 'the line holds «' + want + '» (' + what + '): ' + f.sh + ' > ' + f.ch);
}
/* «¿Qué dispositivo es este?»: its one read-only line (it asks the server, and comes back by the key first) */
async function stationLine(pg, want) {
  await pg.click('#stationBtn');
  await pg.waitForSelector('#stationModal:not([hidden])', { timeout: 5000 });
  await see(pg, '#stDisc', want, 10000);
  assert.ok(await pg.isVisible('#stDisc'), 'the line shows');
  assert.strictEqual(await pg.locator('#stationModal input[data-pin]').count(), 0, 'no PIN box in «¿Qué dispositivo es este?»');
  await pg.click('#stationForm button[type=submit]');
  await pg.waitForSelector('#stationModal', { state: 'hidden' });
}
const storedKey = (pg) => pg.evaluate(() => { try { return JSON.parse(localStorage.getItem('hg-disc-till') || 'null'); } catch (e) { return 'bad'; } });
/* the mark of a rebind or a registration whose answer may be lost (api-0038 §13 item 36): {login, what, at}, never a key or a PIN */
const pending = (pg) => pg.evaluate(() => { try { return JSON.parse(localStorage.getItem('hg-disc-till-pending') || 'null'); } catch (e) { return 'bad'; } });
/* the next c.left replies of a database function lost: the call reaches the server (it commits), the page never hears
   it; the lost answers kept, and the mark the page had written when the call went */
async function dropReplies(pg, fn) {
  const c = { left: 0, lost: [], marks: [] };
  await pg.route(new RegExp('/rest/v1/rpc/' + fn + '(\\?|$)'), async (r) => {
    if (r.request().method() !== 'POST' || c.left <= 0) return r.fallback();
    c.left--;
    c.marks.push(await pending(pg));
    const resp = await r.fetch();
    c.lost.push(await resp.json());
    return r.abort('failed');
  });
  return c;
}
/* a mark holds the login, what is pending and when; no key, no code */
function markOk(m, what, keys) {
  assert.ok(m && typeof m === 'object', 'a mark was written before the call went: ' + JSON.stringify(m));
  assert.deepStrictEqual(Object.keys(m).sort(), ['at', 'login', 'what'], 'the mark holds ids only: ' + JSON.stringify(m));
  assert.deepStrictEqual([m.login, m.what], [CAFE, what], 'this login, ' + what);
  const t = JSON.stringify(m);
  assert.deepStrictEqual(anyPin(t), [], 'no code in the mark');
  for (const k of keys.filter(Boolean)) assert.ok(!t.includes(k), 'no device key in the mark');
}
/* this page's sign-in id, as its token carries it */
async function signin(pg) {
  const s = await pg.evaluate((k) => JSON.parse(localStorage.getItem(k) || 'null'), AUTH_KEY);
  const c = JSON.parse(Buffer.from(s.access_token.split('.')[1], 'base64url').toString());
  return { token: s.access_token, sid: c.session_id, iat: c.iat };
}
/* a database function called with this page's own sign-in (and an unlock token when given), from the test */
async function rpcAs(pg, name, args, unlock) {
  const s = await pg.evaluate((k) => JSON.parse(localStorage.getItem(k) || 'null'), AUTH_KEY);
  const headers = { 'Content-Type': 'application/json', Authorization: 'Bearer ' + s.access_token };
  if (unlock) headers['x-hg-unlock'] = unlock;
  const r = await fetch(API + '/rest/v1/rpc/' + name, { method: 'POST', headers, body: JSON.stringify(args || {}) });
  const t = await r.text();
  if (!r.ok) throw new Error(name + ' ' + r.status + ' ' + t);
  return t ? JSON.parse(t) : null;
}
async function signOut(pg) {
  await pg.click('#outBtn');
  await pg.waitForSelector('#loginView:not([hidden])', { timeout: 10000 });
}
async function signIn(pg) {
  await pg.fill('#em', 'cafe@test.local');
  await pg.fill('#pw', 'test');
  await pg.click('#loginBtn');
  await posReady(pg);
}

/* Reloj de marcas › Horas y equipo with the owner areas open on this device (the person's own PIN in the unlock box) */
async function timeUnlock(pg, who) {
  await goto(pg, '/time');
  await until(async () => (await pg.locator('#staffGrid button').count()) > 0, 15000, 'the clock');
  await pg.click('#tabHours');
  await until(async () => (await pg.isVisible('#hoursPinModal')) || (await pg.isVisible('#dtBlock')), 10000, 'the PIN box or the log');
  if (await pg.isVisible('#hoursPinModal')) {
    await pg.selectOption('#hpWho', ID[who]);
    await pg.type('#hpPin', PIN[who]);
    await pg.click('#hoursPinForm button[type=submit]');
    await until(async () => pg.locator('#hoursPinModal').isHidden(), 8000, 'the owner areas opened by ' + who);
  }
  await pg.waitForSelector('#dtBlock:not([hidden])', { timeout: 10000 });
}
/* one place of «Cajas para descuentos»: its first line, its state line and its buttons */
const rowOf = (pg, slot) => pg.evaluate((n) => {
  const nz = (x) => String(x || '').replace(/[  ]/g, ' ').replace(/\s+/g, ' ').trim();
  const r = document.querySelector(`#dtList .dtrow[data-slot="${n}"]`);
  if (!r) return null;
  const l = r.querySelector('.dtl'), s = l.querySelector('.dts');
  return { head: nz([...l.childNodes].filter((c) => c !== s).map((c) => c.textContent).join('')), state: nz(s ? s.textContent : ''),
           buttons: [...r.querySelectorAll('.btns button')].map((b) => nz(b.textContent)) };
}, slot);
async function seeRow(pg, slot, want) {
  let last;
  await until(async () => {
    last = await rowOf(pg, slot);
    if (!last) return false;
    return Object.keys(want).every((k) => (want[k] instanceof RegExp ? want[k].test(last[k]) : JSON.stringify(want[k]) === JSON.stringify(last[k])));
  }, 10000, 'place ' + slot + ' to read ' + JSON.stringify(want, (k, v) => (v instanceof RegExp ? String(v) : v))).catch((e) => { e.message += ' (it reads ' + JSON.stringify(last) + ')'; throw e; });
  return last;
}
const rowButton = (pg, slot, label) => pg.locator(`#dtList .dtrow[data-slot="${slot}"] .btns button`, { hasText: label });
/* the log's own approval box: a manager picked from the list, their PIN */
async function lgApprove(pg, who, pin) {
  await pg.waitForSelector('#lgApprove:not([hidden])', { timeout: 5000 });
  await pg.selectOption('#lgMgr', ID[who]);
  assert.strictEqual(await pg.inputValue('#lgMgrPin'), '', 'the log\'s PIN box starts empty');
  await pg.type('#lgMgrPin', pin);
  await pg.click('#lgGo');
}
/* the approvals log's rows by their label */
const logLabels = (pg) => pg.evaluate(() => [...document.querySelectorAll('#logBody .lrow .what > b')].map((b) => b.textContent.trim()));
const logRows = (pg, label) => pg.evaluate((l) => [...document.querySelectorAll('#logBody .lrow')].filter((r) => (r.querySelector('.what > b') || {}).textContent === l)
  .map((r) => r.querySelector('.what').textContent.replace(/\s+/g, ' ').trim()), label);

/* the window's boxes (mecanismo §13.3 C-a: a message changes none of them) */
const boxes = (pg) => pg.evaluate(() => {
  const r = (el) => { const b = el.getBoundingClientRect(); return [b.left, b.top, b.width, b.height].map((v) => Math.round(v * 10) / 10); };
  const field = [document.getElementById('discPin'), document.getElementById('discText')].find((e) => !e.hidden);
  return { cats: [...document.querySelectorAll('#discForm [data-cat]')].map(r), field: r(field), pad: r(document.getElementById('discPad')),
           go: r(document.getElementById('discGo')), cancel: r(document.getElementById('discCancel')), box: r(document.getElementById('discForm')) };
});

/* a café sign-in whose token carries no session_id (a token older than 0033's sign-in ids): signed with the test secret */
function noSessionLogin() {
  const now = Math.floor(Date.now() / 1000), exp = now + 3600, email = 'cafe@test.local';
  const access = gw.sign({ sub: CAFE, role: 'authenticated', aud: 'authenticated', aal: 'aal1', email, iat: now, exp, amr: [{ method: 'password', timestamp: now }] });
  return JSON.stringify({ access_token: access, token_type: 'bearer', expires_in: 3600, expires_at: exp, refresh_token: 'no-refresh-402',
    user: { id: CAFE, aud: 'authenticated', role: 'authenticated', email, app_metadata: { provider: 'email' }, user_metadata: {}, factors: [], created_at: '2026-01-01T00:00:00Z' } });
}

/* ---------- the tests ---------- */
module.exports.tests = [
  {
    name: 'C-a, C-b, §10.2: A registered in Reloj de marcas by Ana (owner areas on that device): its key kept, «Descuentos: registrada (Ana, …).»; B not registered: «sin registrar», the window\'s text, Autorizar off, no code sent, every box as with no message at 1180 × 820 and 360 × 640; 2 wrong codes on A plain, the 3rd waits 30 s; B registered meanwhile approves Local with Ana\'s code',
    run: async ({ browser }) => {
      testMenu();
      const A = await posPage(browser, { station: { name: 'Caja A', main: true } });
      const sidA = (await signin(A)).sid;
      const panels = [];
      A.on('response', async (r) => { if (/rpc\/(descuento_cajas|descuento_estado)/.test(r.url())) panels.push(await r.text().catch(() => '')); });
      // C-a: registered through Reloj de marcas › Bitácora, with the owner areas open on A itself
      await timeUnlock(A, 'ana');
      await until(() => A.isVisible('#dtRegister'), 8000, '«Registrar este dispositivo para descuentos» on a device not registered');
      await see(A, '#dtRegister', ES.register);
      await A.click('#dtRegister');
      await see(A, '#dtMsg', ES.registered);
      const key = await storedKey(A);
      assert.strictEqual(key && key.login, CAFE, 'the device key is kept for this login');
      assert.match(key.key, /^[0-9a-f]{64}$/, 'the device key: 64 hex');
      const ta = tillAt(1);
      assert.ok(ta, 'A holds place 1');
      assert.deepStrictEqual([ta.station, ta.enrolled_by, ta.enrolled_by_name, ta.session_id], ['Caja A', STAFF.ana, 'Ana', sidA], 'A\'s till: its station, Ana, this sign-in');
      assert.strictEqual(ta.key_hash, sha256(key.key), 'the server keeps only the key\'s sha256');
      assert.strictEqual(sql(`select manager_name from audit_log where action = 'discount_till_enrolled'`), 'Ana', 'logged under Ana');
      await seeRow(A, 1, { head: `Puesto 1: Caja A · registrada por Ana, ${dmon(ta.since)}`, state: `${ES.wrongN(0)} · ${ES.active} · ${ES.here}` });
      await seeRow(A, 2, { head: 'Puesto 2: libre', state: `${ES.wrongN(0)} · ${ES.active}`, buttons: [] });
      await until(async () => A.isHidden('#dtRegister'), 5000, 'the register button gone once registered');
      // api-0038 §4.1, §4.9: no sign-in id, sign-in tag or device key leaves the server in the till's state or the panel
      const tag = 's' + sha256(sidA).slice(0, 7);
      assert.ok(panels.length >= 2 && panels.every((t) => !t.includes(sidA) && !t.includes(key.key) && !t.includes(ta.key_hash) && !t.includes(tag) && !/"session_id"|"key"/.test(t)),
        'no session id, tag or key in descuento_estado / descuento_cajas: ' + panels.join(' ').slice(0, 300));
      // §10.2: «Este dispositivo» in A's POS
      await goto(A, '/pos'); await posReady(A);
      await stationLine(A, ES.lineReg('Ana', dmon(ta.since)));
      assert.strictEqual(sent(A, 'descuento_caja_volver').length, 0, 'the same sign-in needs no key');
      // B: another device of the same login, not registered
      const B = await posPage(browser, { station: { name: 'Caja B', main: true } });
      await stationLine(B, ES.lineNot);
      for (const [w, h] of [[1180, 820], [360, 640]]) {
        await A.setViewportSize({ width: w, height: h }); await B.setViewportSize({ width: w, height: h });
        const size = w + '×' + h;
        await openWin(A);
        await see(A, '#discErr', '');
        const ref = await boxes(A);
        await cat(A, 'local');
        const refLocal = await boxes(A);
        await closeWin(A);
        await openWin(B);
        await lineSays(B, ES.notEnrolled, 'B not registered, ' + size);
        assert.ok(await B.isDisabled('#discGo'), 'Autorizar off on a till not registered (' + size + ')');
        assert.deepStrictEqual(await boxes(B), ref, 'the boxes as with no message (' + size + ')');
        await cat(B, 'local');
        await lineSays(B, ES.notEnrolled, 'B not registered, Local tapped, ' + size);
        assert.ok(await B.isDisabled('#discGo'), 'Autorizar still off after a category (' + size + ')');
        assert.deepStrictEqual(await boxes(B), refLocal, 'the boxes as with no message, Local tapped (' + size + ')');
        // a code typed and the form sent anyway (Enter, a script): nothing goes
        await typeCode(B, PIN.ana);
        await B.evaluate(() => document.getElementById('discForm').requestSubmit());
        await B.press('#discPin', 'Enter');
        await closeWin(B);
      }
      assert.strictEqual(sent(B, 'descuento_autorizar').length, 0, 'B sends no discount request at all');
      assert.deepStrictEqual(B.reqs.map((r) => anyPin(r.url + ' ' + r.body)).flat(), [], 'no request from B carries a code');
      // C-b: on A two wrong codes give the plain text, the third makes the till wait 30 seconds
      await A.setViewportSize({ width: 1180, height: 820 });
      await openWin(A);
      for (let i = 1; i <= 3; i++) {
        const a = await attempt(A, 'local', WRONG);
        assert.strictEqual(a.error, 'bad_pin', 'wrong code ' + i + ': ' + JSON.stringify(a));
        if (i < 3) {
          assert.strictEqual(a.blocked, null, 'wrong code ' + i + ' costs nothing');
          await lineSays(A, ES.badMgr, 'wrong code ' + i);
          assert.ok(!(await A.isDisabled('#discGo')), 'Autorizar still on after wrong code ' + i);
        } else {
          assert.deepStrictEqual([a.blocked, a.wait], ['wait', '30s'], 'the 3rd wrong code in an hour: a 30-second wait');
          await lineSays(A, ES.wait30, 'the 3rd wrong code');
          assert.ok(await A.isDisabled('#discGo'), 'Autorizar off while the till waits');
        }
      }
      await closeWin(A);
      // B registered meanwhile (Ana, on B) approves Local with Ana's code: another place, its own count
      await timeUnlock(B, 'ana');
      await B.click('#dtRegister');
      await see(B, '#dtMsg', ES.registered);
      const tb = tillAt(2);
      assert.ok(tb && tb.station === 'Caja B', 'B took the free place 2');
      await seeRow(B, 1, { head: new RegExp('^Puesto 1: Caja A · registrada por Ana, '), state: new RegExp('^' + ES.wrongN(3) + ' · ') });
      await seeRow(B, 2, { head: `Puesto 2: Caja B · registrada por Ana, ${dmon(tb.since)}`, state: `${ES.wrongN(0)} · ${ES.active} · ${ES.here}` });
      await goto(B, '/pos'); await posReady(B);
      const ok = await approveLocal(B, 'ana');
      assert.strictEqual(sql(`select till_id || '/' || approved_name from discount_approvals where id = '${ok.id}'`), tb.id + '/Ana', 'approved at B\'s till by Ana');
      assert.deepStrictEqual([wrongCount(1), wrongCount(2)], [3, 0], 'the wrong codes counted on A\'s place only');
      noCodeLeak(A); noCodeLeak(B);
      assert.deepStrictEqual(A.errors.concat(B.errors), []);
    }
  },
  {
    name: 'C-c: 10 wrong codes sent at once from A\'s page → at most 3 bad_pin, the rest till_wait; at most 3 rows for A\'s place, 0 for B\'s',
    run: async ({ browser }) => {
      testMenu();
      const A = await posPage(browser, { station: { name: 'Caja A', main: true } });
      const ra = await registerTill(A, { station: 'Caja A' });
      const B = await posPage(browser, { station: { name: 'Caja B', main: true } });
      const rb = await registerTill(B, { station: 'Caja B' });
      const answers = await A.evaluate((wrong) => Promise.all(Array.from({ length: 10 }, () =>
        db.rpc('descuento_autorizar', { p_category: 'local', p_pin: wrong, p_subtotal: 2000, p_request_id: uuid(), p_station: 'Caja A' })
          .then((r) => (r.data ? r.data.error : 'ERROR ' + (r.error && r.error.message))))), WRONG);
      const bad = answers.filter((x) => x === 'bad_pin').length;
      assert.ok(bad >= 1 && bad <= 3, 'at most 3 wrong codes tested: ' + answers.join(', '));
      assert.ok(answers.every((x) => x === 'bad_pin' || x === 'till_wait'), 'the others: the till waits: ' + answers.join(', '));
      assert.ok(wrongCount(ra.slot) <= 3, 'at most 3 rows for A\'s place: ' + wrongCount(ra.slot));
      assert.strictEqual(wrongCount(ra.slot), bad, 'one row per code tested');
      assert.strictEqual(wrongCount(rb.slot), 0, 'none for B\'s place');
      await approveLocal(B, 'ana');
      assert.deepStrictEqual(A.errors.concat(B.errors), []);
    }
  },
  {
    name: 'C-d, C-g (L1): a token refresh keeps A\'s till; «Cerrar sesión» sends no descuento_caja_cerrar and keeps hg-disc-till; the next sign-in comes back by the key (same place, a rebound row, a new key, no manager) and approves; without the key a new sign-in is «sin registrar»',
    run: async ({ browser }) => {
      testMenu();
      const A = await posPage(browser, { station: { name: 'Caja A', main: true } });
      const reg = await registerTill(A, { station: 'Caja A' });
      const t0 = tillAt(reg.slot), k0 = await storedKey(A), s0 = await signin(A);
      // C-d: a token refresh keeps the sign-in id, and so the registration (the test server stamps tokens by the second:
      // the refresh waits for the next one, so the new token differs)
      await until(async () => Math.floor(Date.now() / 1000) > s0.iat, 3000, 'the next second');
      const r0 = A.reqs.length;
      assert.ok(await A.evaluate(() => db.auth.refreshSession().then((r) => !r.error)), 'the token refreshed');
      assert.ok(A.reqs.slice(r0).some((r) => /\/auth\/v1\/token\?grant_type=refresh_token/.test(r.url)), 'a refresh asked of the server');
      const s1 = await signin(A);
      assert.notStrictEqual(s1.token, s0.token, 'a new token');
      assert.strictEqual(s1.sid, s0.sid, 'the same session_id');
      await stationLine(A, ES.lineReg('Ana', dmon(t0.since)));
      assert.strictEqual(sent(A, 'descuento_caja_volver').length, 0, 'no rebind after a refresh');
      assert.strictEqual(sql(`select count(*) from discount_tills`), '1', 'the same till row');
      // C-g as built (build-plan L1): «Cerrar sesión» calls no descuento_caja_cerrar and keeps the device key
      const n0 = A.reqs.length;
      await signOut(A);
      const out = A.reqs.slice(n0);
      assert.ok(out.some((r) => /\/auth\/v1\/logout/.test(r.url)), 'signed out on the server');
      assert.deepStrictEqual(out.filter((r) => /descuento_caja_cerrar/.test(r.url)).map((r) => r.url), [], 'no descuento_caja_cerrar call');
      assert.deepStrictEqual(await storedKey(A), k0, 'hg-disc-till is still in storage after «Cerrar sesión»');
      assert.strictEqual(sql(`select ended_at is null from discount_tills where id = '${t0.id}'`), 't', 'the till row stays live (no signed_out)');
      assert.strictEqual(sql(`select count(*) from audit_log where action = 'discount_till_signed_out'`), '0', 'no discount_till_signed_out row');
      // the next sign-in: a new session_id, back by the key to the same place, with nobody
      const unlocks0 = sql(`select count(*) from audit_log where action = 'access_open'`);
      await signIn(A);
      const s2 = await signin(A);
      assert.notStrictEqual(s2.sid, s0.sid, 'a new sign-in has a new session_id');
      await stationLine(A, ES.lineReg('Ana', dmon(t0.since)));
      assert.strictEqual(sent(A, 'descuento_caja_volver').length, 1, 'the page came back by its key (descuento_caja_volver)');
      const t1 = tillAt(reg.slot), k1 = await storedKey(A);
      assert.ok(t1 && t1.id !== t0.id, 'a new till row');
      assert.deepStrictEqual([t1.slot, t1.session_id, t1.rebound_from, t1.enrolled_by_name, t1.since], [t0.slot, s2.sid, t0.id, 'Ana', t0.since], 'the same place, this sign-in, the original registration');
      assert.strictEqual(sql(`select ended_how || '/' || (key_hash is null) from discount_tills where id = '${t0.id}'`), 'rebound/true', 'the old row ended «rebound», its key spent');
      assert.strictEqual(sql(`select count(*) || '/' || max(details ->> 'how') from audit_log where action = 'discount_till_rebound'`), '1/live', 'one discount_till_rebound row');
      assert.ok(k1 && k1.key !== k0.key && k1.login === CAFE, 'a new key in storage');
      assert.strictEqual(t1.key_hash, sha256(k1.key), 'the new key is the one the server keeps');
      assert.strictEqual(sql(`select count(*) from audit_log where action = 'access_open'`), unlocks0, 'no manager opened anything');
      const a = await approveLocal(A, 'ana');
      assert.strictEqual(sql(`select till_id from discount_approvals where id = '${a.id}'`), t1.id, 'the till approves from its place');
      // 6 rebinds of the place in the last hour (5 more as fixture rows): the next one is refused; the page keeps the key
      // and says «sin registrar» (api-0038 §10.3: rebind_limit is silent, the key kept); an hour later the key brings it back
      sql(`insert into public.audit_log (action, target_id, summary, details)
           select 'discount_till_rebound', '', 'fixture 402', jsonb_build_object('slot', ${reg.slot}, 'how', 'live') from generate_series(1, 5)`);
      await signOut(A);
      await signIn(A);
      let vr = A.waitForResponse((r) => /rpc\/descuento_caja_volver/.test(r.url()));
      await stationLine(A, ES.lineNot);
      assert.strictEqual((await (await vr).json()).error, 'rebind_limit', 'the 7th rebind in an hour is refused');
      assert.deepStrictEqual(await storedKey(A), k1, 'the key is kept after rebind_limit');
      sql(`update public.audit_log set at = at - interval '2 hours' where action = 'discount_till_rebound'`);
      vr = A.waitForResponse((r) => /rpc\/descuento_caja_volver/.test(r.url()));
      await stationLine(A, ES.lineReg('Ana', dmon(t0.since)));
      assert.ok((await (await vr).json()).ok, 'the kept key brings the till back once the hour is over');
      assert.strictEqual(tillAt(reg.slot).enrolled_by_name, 'Ana', 'still Ana\'s registration, in place ' + reg.slot);
      const rebounds = sql(`select count(*) from audit_log where action = 'discount_till_rebound'`);
      // without the key: a new sign-in is a device not registered
      await A.evaluate(() => localStorage.removeItem('hg-disc-till'));
      await signOut(A);
      const v0 = sent(A, 'descuento_caja_volver').length;
      await signIn(A);
      await stationLine(A, ES.lineNot);
      assert.strictEqual(sent(A, 'descuento_caja_volver').length, v0, 'no key, no rebind');
      await openWin(A);
      await lineSays(A, ES.notEnrolled, 'no key');
      await closeWin(A);
      assert.strictEqual(sql(`select count(*) from audit_log where action = 'discount_till_rebound'`), rebounds, 'no rebind without the key');
      noCodeLeak(A);
      assert.deepStrictEqual(A.errors, []);
    }
  },
  {
    name: 'C-e (rule 5): Ana, Bea and the owner locked by 5 wrong PINs each in the time clock\'s unlock box of a third device; at B Ana\'s code still approves Local and the owner\'s Guía, no 0033 counter written; the unlock box still says locked; after A and B sign in again they come back by key and Ana approves on each',
    run: async ({ browser }) => {
      testMenu(); addBea(); guiaOn();
      const A = await posPage(browser, { station: { name: 'Caja A', main: true } });
      await registerTill(A, { station: 'Caja A' });
      const B = await posPage(browser, { station: { name: 'Caja B', main: true } });
      const rb = await registerTill(B, { station: 'Caja B' });
      const tbId = tillAt(rb.slot).id;
      // a third device, not registered: 5 wrong PINs each in Reloj de marcas' unlock box
      const C = await page(browser, { login: 'cafe', lang: 'es', station: { name: 'Tableta C', main: false } });
      await goto(C, '/time');
      await until(async () => (await C.locator('#staffGrid button').count()) > 0, 15000, 'the clock');
      await C.click('#tabHours');
      await C.waitForSelector('#hoursPinModal:not([hidden])', { timeout: 10000 });
      for (const who of ['ana', 'bea', 'dueno']) {
        for (let i = 0; i < 5; i++) {
          await C.selectOption('#hpWho', ID[who]);
          await C.type('#hpPin', WRONG);
          const r = C.waitForResponse((x) => /rpc\/access_unlock/.test(x.url()));
          await C.click('#hoursPinForm button[type=submit]');
          assert.strictEqual((await (await r).json()).error, 'bad_pin', who + ', wrong PIN ' + (i + 1));
          await until(async () => (await C.inputValue('#hpPin')) === '', 5000, 'the PIN box emptied by the page');
        }
      }
      const locks = () => sql(`select string_agg(name || ':' || failed_pins || ':' || coalesce(locked_until::text, '-'), ' ' order by name) from staff where id in ('${STAFF.ana}', '${BEA.id}', '${STAFF.dueno}')`);
      assert.strictEqual(sql(`select count(*) from staff where id in ('${STAFF.ana}', '${BEA.id}', '${STAFF.dueno}') and locked_until > now()`), '3', 'Ana, Bea and the owner locked (0033)');
      const locked0 = locks();
      // at the registered till B: Ana's right code approves Local
      const a = await approveLocal(B, 'ana');
      assert.strictEqual(sql(`select till_id || '/' || approved_name from discount_approvals where id = '${a.id}'`), tbId + '/Ana', 'approved at B by Ana');
      assert.strictEqual(sql(`select details ->> 'person_locked' from audit_log where action = 'discount_approved' and target_id = '${a.id}'`), 'true', 'the approval says the PIN was locked');
      // and the owner's right code approves Guía Turista
      await openWin(B);
      const g = await attempt(B, 'guia', PIN.dueno, { company: 'Selvatura' });
      assert.ok(g.ok, 'Guía approved with the locked owner\'s code: ' + JSON.stringify(g));
      await B.waitForSelector('#discModal', { state: 'hidden', timeout: 8000 });
      await see(B, '#discLbl', 'Cortesía Guía Turista · Selvatura');
      assert.strictEqual(sql(`select details ->> 'person_locked' from audit_log where action = 'discount_approved' and target_id = '${g.id}'`), 'true');
      await B.click('#discX');
      assert.strictEqual(locks(), locked0, 'the window wrote no 0033 counter (no reset, no count)');
      assert.strictEqual(wrongCount(rb.slot), 0, 'nothing counted at B');
      // the unlock box with Ana's right PIN still says she is locked
      await C.selectOption('#hpWho', STAFF.ana);
      await C.type('#hpPin', PIN.ana);
      await C.click('#hoursPinForm button[type=submit]');
      await see(C, '#hpErr', ES.locked);
      assert.ok(await C.isVisible('#hoursPinModal'), 'the owner areas stay closed');
      // A and B sign out and in again while everyone is still locked: both come back by key, Ana approves on each
      for (const [pg, name] of [[A, 'A'], [B, 'B']]) {
        const before = tillAt(name === 'A' ? 1 : 2);
        await signOut(pg);
        await signIn(pg);
        await stationLine(pg, ES.lineReg('Ana', dmon(before.since)));
        const after = tillAt(before.slot);
        assert.ok(after.id !== before.id && after.rebound_from === before.id, name + ' came back by its key to place ' + before.slot);
        const x = await approveLocal(pg, 'ana');
        assert.strictEqual(sql(`select till_id from discount_approvals where id = '${x.id}'`), after.id, 'Ana\'s code approves at ' + name);
      }
      assert.strictEqual(sql(`select count(*) from staff where id in ('${STAFF.ana}', '${BEA.id}', '${STAFF.dueno}') and locked_until > now()`), '3', 'everyone still locked');
      // the approvals log (the owner's own login with the phone code: nobody can open the owner areas on a café device now)
      // marks each of these approvals (mecanismo §10.3: «(su PIN estaba bloqueado en las listas de nombres)»)
      const O = await page(browser, { login: 'owner', aal: 'aal2', lang: 'es' });
      await goto(O, '/time');
      await until(async () => (await O.locator('#staffGrid button').count()) > 0, 15000, 'the clock');
      await O.click('#tabHours');
      await O.waitForSelector('#dtBlock:not([hidden])', { timeout: 10000 });
      assert.ok(await O.isHidden('#hoursPinModal'), 'the phone code needs no PIN');
      let appr = [];
      await until(async () => (appr = await logRows(O, 'Descuento aprobado')).length === 4, 8000, 'the 4 approvals in the log');
      assert.ok(appr.every((r) => r.endsWith('(su PIN estaba bloqueado en las listas de nombres)')), 'each approval marked: ' + JSON.stringify(appr));
      assert.deepStrictEqual(A.errors.concat(B.errors, C.errors, O.errors), []);
    }
  },
  {
    name: 'C-f: A\'s place stopped by fixture rows; on B with Bea\'s unlock «Puesto 1: … Detenida…», «Reanudar descuentos» through the picker resumes it and A approves; a second resume → the resume_limit text, Bea\'s PIN not tested; a stopped free place shows «Puesto 3: libre … Detenida…» and its resume works',
    run: async ({ browser }) => {
      testMenu(); addBea();
      const A = await posPage(browser, { station: { name: 'Caja A', main: true } });
      const ra = await registerTill(A, { station: 'Caja A' });
      const ta = tillAt(ra.slot);
      wrongRows(ra.slot, times(12, 7200));
      await openWin(A);
      await lineSays(A, ES.stopped, 'A stopped');
      await closeWin(A);
      const B = await page(browser, { login: 'cafe', lang: 'es', station: { name: 'Caja B', main: true } });
      watch(B);
      await timeUnlock(B, 'bea');
      await seeRow(B, 1, { head: `Puesto 1: Caja A · registrada por Ana, ${dmon(ta.since)}`, state: `${ES.wrongN(12)} · ${ES.stoppedUntil(dayTime(stopAt(1)))}`,
                           buttons: [ES.resume, ES.remove] });
      await rowButton(B, 1, ES.resume).click();
      await see(B, '#lgWhat', 'Reanudar los descuentos del puesto 1');
      await lgApprove(B, 'bea', BEA.pin);
      await see(B, '#dtMsg', ES.resumed(1));
      assert.strictEqual(sql(`select manager_name || '/' || (details ->> 'how') || '/' || (details ->> 'till') from audit_log where action = 'discount_till_resumed' and details ->> 'how' = 'manager'`),
        'Bea/manager/' + ta.id, 'resumed by Bea, logged');
      await seeRow(B, 1, { state: `${ES.wrongN(12)} · ${ES.active}`, buttons: [ES.remove] });
      await approveLocal(A, 'ana');
      // stopped again: a second resume of the same place in 24 h is refused before the PIN (a wrong one here)
      wrongRows(ra.slot, times(12, 5400));
      await B.evaluate(() => loadLog());
      await seeRow(B, 1, { state: `${ES.wrongN(24)} · ${ES.stoppedUntil(dayTime(stopAt(1)))}`, buttons: [ES.resume, ES.remove] });
      const bea0 = sql(`select failed_pins || '/' || coalesce(locked_until::text, '-') from staff where id = '${BEA.id}'`);
      await rowButton(B, 1, ES.resume).click();
      await lgApprove(B, 'bea', WRONG);
      await see(B, '#lgErr', ES.resumeLimit(hhmm(stopAt(1), true)));
      assert.strictEqual(sql(`select failed_pins || '/' || coalesce(locked_until::text, '-') from staff where id = '${BEA.id}'`), bea0, 'Bea\'s PIN was not tested (her counter unchanged)');
      assert.strictEqual(sql(`select count(*) from audit_log where action = 'discount_till_resumed' and details ->> 'how' = 'manager'`), '1', 'no second resume');
      await B.click('#lgCancel');
      // a stopped place that no till holds: shown, and resumed
      wrongRows(3, times(12, 7200));
      await B.evaluate(() => loadLog());
      await seeRow(B, 3, { head: 'Puesto 3: libre', state: `${ES.wrongN(12)} · ${ES.stoppedUntil(dayTime(stopAt(3)))}`, buttons: [ES.resume] });
      await rowButton(B, 3, ES.resume).click();
      await lgApprove(B, 'bea', BEA.pin);
      await see(B, '#dtMsg', ES.resumed(3));
      assert.strictEqual(sql(`select manager_name || '/' || coalesce(details ->> 'till', '-') from audit_log where action = 'discount_till_resumed' and details ->> 'slot' = '3' and details ->> 'how' = 'manager'`), 'Bea/-', 'a free place resumed');
      await seeRow(B, 3, { head: 'Puesto 3: libre', state: `${ES.wrongN(12)} · ${ES.active}`, buttons: [] });
      await see(B, '#dtFoot', ES.foot(2, [0, 0, 0]));
      // a new registration goes to the most used free place (stopped first), never to a clean one, and says so
      // (mecanismo §1 item 3, §8, §10.3); the café's 2 resumes of the day are used: that place cannot be resumed now
      wrongRows(2, times(12, 7200));
      await B.evaluate(() => loadLog());
      await until(() => B.isVisible('#dtRegister'), 8000, 'the register button');
      await B.click('#dtRegister');
      await see(B, '#dtMsg', `Dispositivo registrado, pero los descuentos de este puesto están detenidos hasta ${dayTime(stopAt(2))}: reanúdelos aquí.`);
      assert.strictEqual(tillAt(2) && tillAt(2).station, 'Caja B', 'B went to the stopped place 2, not to the clean place 3');
      await seeRow(B, 2, { head: new RegExp('^Puesto 2: Caja B · registrada por Bea, '), state: `${ES.wrongN(12)} · ${ES.stoppedUntil(dayTime(stopAt(2)))} · ${ES.here}`,
                           buttons: [ES.resume, ES.remove] });
      await rowButton(B, 2, ES.resume).click();
      await lgApprove(B, 'bea', BEA.pin);
      await see(B, '#lgErr', ES.resumeLimit(hhmm(stopAt(2), true)));
      assert.strictEqual(sql(`select count(*) from audit_log where action = 'discount_till_resumed' and details ->> 'how' = 'manager'`), '2', 'the café\'s 2 resumes in 24 h');
      await B.click('#lgCancel');
      noCodeLeak(B);
      assert.deepStrictEqual(A.errors.concat(B.errors), []);
    }
  },
  {
    name: 'C-h: a station named <img src=x onerror=alert(1)> stays plain text in the panel, its messages and the log; no element, no dialog',
    run: async ({ browser }) => {
      testMenu();
      const XSS = '<img src=x onerror=alert(1)>', X24 = XSS.slice(0, 24);   // the POS keeps 24 characters of a device name
      const X = await posPage(browser, { station: { name: XSS, main: true } });
      const dialogs = []; X.onDialog = async (d) => { dialogs.push(d.message()); await d.dismiss(); };
      const noMarkup = async (where) => {
        const n = await X.evaluate(() => [document.querySelectorAll('img[src="x"]').length, document.querySelectorAll('[onerror]').length]);
        assert.deepStrictEqual(n, [0, 0], 'no element made from the station name (' + where + ')');
        assert.deepStrictEqual(dialogs, [], 'no dialog (' + where + ')');
      };
      await timeUnlock(X, 'ana');
      await X.click('#dtRegister');
      await see(X, '#dtMsg', ES.registered);
      const t = tillAt(1);
      assert.strictEqual(t.station, X24, 'the station kept as typed (24 characters)');
      await seeRow(X, 1, { head: `Puesto 1: ${X24} · registrada por Ana, ${dmon(t.since)}` });
      assert.strictEqual(await X.evaluate(() => document.querySelector('#dtList .dtrow[data-slot="1"] .dtl span[data-no-translate]').textContent), X24, 'the station as a text node');
      await noMarkup('the panel');
      // a wrong code at that till: the log shows the station twice (where typed, where registered)
      await goto(X, '/pos'); await posReady(X);
      await openWin(X);
      assert.strictEqual((await attempt(X, 'local', WRONG)).error, 'bad_pin');
      await closeWin(X);
      await noMarkup('the POS');
      await timeUnlock(X, 'ana');
      await until(async () => (await logRows(X, ES.log.wrong)).length === 1, 8000, 'the wrong code in the log');
      assert.ok((await logRows(X, ES.log.wrong))[0].includes(`${X24} · ${X24}`), 'the station as text in the wrong-code row: ' + (await logRows(X, ES.log.wrong))[0]);
      assert.ok((await logRows(X, ES.log.enrolled))[0].includes(`Puesto 1 · ${X24} · registrada por Ana`), 'the station as text in the registration row');
      await noMarkup('the log');
      // removed by Ana: the message and the log row name it as text
      await rowButton(X, 1, ES.remove).click();
      await see(X, '#lgWhat', `Quitar el registro de «${X24}»`);
      await lgApprove(X, 'ana', PIN.ana);
      await see(X, '#dtMsg', ES.removed(X24));
      await until(async () => (await logRows(X, ES.log.ended)).length === 1, 8000, 'the removal in the log');
      assert.ok((await logRows(X, ES.log.ended))[0].includes(`Puesto 1 · ${X24} · quitado por un encargado`), 'the station as text in the removal row: ' + (await logRows(X, ES.log.ended))[0]);
      await noMarkup('after the removal');
      assert.deepStrictEqual(X.errors, []);
    }
  },
  {
    name: 'C-i: at 360 × 640 every till-state, wait, stop and warning text fits the line (real server states and answers; the wrong-code + wait warnings the server never sends in one answer, mocked); precedence: the till\'s state over a category, a blocked answer shows only the wait or stop text',
    run: async ({ browser }) => {
      testMenu(); guiaOn();
      const V = { viewport: { width: 360, height: 640 } };
      const A = await posPage(browser, Object.assign({ station: { name: 'Caja A', main: true } }, V));
      const slot = (await registerTill(A, { station: 'Caja A' })).slot;
      let checked = 0;
      const said = async (want, what) => { await lineSays(A, want, what); checked++; };
      // (1) the till's own state when the window opens (descuento_estado), from fixture rows of the place
      const states = [
        ['wait 30 s', [600, 590, 2], 'wait', (u) => ES.wait30],
        ['wait 1 min', [600, 590, 580, 2], 'wait', (u) => ES.waitAt(hhmm(u, true))],
        ['wait 5 min', [600, 590, 580, 570, 2], 'wait', (u) => ES.waitAt(hhmm(u, true))],
        ['wait 10 min', [600, 590, 580, 570, 560, 2], 'wait', (u) => ES.waitAt(hhmm(u, true))],
        ['stopped', times(12, 7200), 'stopped', () => ES.stopped],
        ['ok, next mistake waits 1 min', [600, 590, 40], 'ok', () => ES.warn.wait_1m],
        ['ok, next mistake waits 5 min', [600, 590, 580, 70], 'ok', () => ES.warn.wait_5m],
        ['ok, next mistake waits 10 min', [600, 590, 580, 570, 360], 'ok', () => ES.warn.wait_10m],
        ['ok, next mistake stops', times(11, 7200), 'ok', () => ES.warn.stop]
      ];
      for (const [what, ages, state, want] of states) {
        freshPlace(slot); wrongRows(slot, ages);
        const est = nextEstado(A);
        await openWin(A);
        const e = await est;
        assert.strictEqual(e.till.state, state, what + ': ' + JSON.stringify(e.till));
        await said(want(ms(e.till.until)), 'estado ' + what);
        if (state === 'ok') {
          await cat(A, 'local');
          await see(A, '#discErr', '');
          assert.ok(!(await A.isDisabled('#discGo')), 'a warning alone leaves Autorizar on (' + what + ')');
        } else {
          for (const c of ['guia', 'local']) {
            await cat(A, c);
            await said(want(ms(e.till.until)), 'estado ' + what + ', ' + c + ' tapped');
            assert.ok(await A.isDisabled('#discGo'), 'Autorizar off (' + what + ', ' + c + ')');
          }
        }
        await closeWin(A);
      }
      // (3) real answers: each wrong-code text alone and with «stop», and each wait or stop it starts (only that text)
      const answers = [
        ['manager', 'local', [], null, ES.badMgr],
        ['owner', 'guia', [], null, ES.badOwner],
        ['employee', 'empleado', [], null, ES.badEmp],
        ['manager + stop', 'local', times(10, 7200), null, ES.badMgr + ' ' + ES.warn.stop],
        ['owner + stop (106 characters)', 'guia', times(10, 7200), null, ES.badOwner + ' ' + ES.warn.stop],
        ['employee + stop', 'empleado', times(10, 7200), null, ES.badEmp + ' ' + ES.warn.stop],
        ['blocked 30 s', 'local', [600, 590], 'wait', () => ES.wait30],
        ['blocked 1 min', 'local', [600, 590, 580], 'wait', (u) => ES.waitAt(hhmm(u, true))],
        ['blocked 5 min', 'local', [600, 590, 580, 570], 'wait', (u) => ES.waitAt(hhmm(u, true))],
        ['blocked 10 min', 'guia', [600, 590, 580, 570, 560], 'wait', (u) => ES.waitAt(hhmm(u, true))],
        ['blocked 10 min, employee step', 'empleado', [600, 590, 580, 570, 560], 'wait', (u) => ES.waitAt(hhmm(u, true))],
        ['blocked stop', 'local', times(11, 7200), 'stopped', () => ES.stopped],
        ['blocked stop, owner step', 'guia', times(11, 7200), 'stopped', () => ES.stopped]
      ];
      for (const [what, c, ages, blocked, want] of answers) {
        freshPlace(slot); wrongRows(slot, ages);
        await openWin(A);
        // the owner step tested with Ana's code (not the owner's), the employee step with a code nobody has
        const a = c === 'empleado' ? await attempt(A, c, PIN.ana, { employee: WRONG }) : await attempt(A, c, c === 'guia' ? PIN.ana : WRONG);
        assert.strictEqual(a.error, c === 'empleado' ? 'bad_employee' : 'bad_pin', what + ': ' + JSON.stringify(a));
        assert.strictEqual(a.blocked, blocked, what + ': blocked');
        if (!blocked) {
          assert.strictEqual(a.warn, ages.length ? 'stop' : null, what + ': warn');
          await said(want, 'answer ' + what);
          assert.ok(!(await A.isDisabled('#discGo')), 'Autorizar on after ' + what);
        } else {
          const w = want(ms(a.until));
          await said(w, 'answer ' + what);
          assert.ok(!(await text(A, '#discErr')).includes('no válido'), 'a blocked answer shows only the wait or stop text (' + what + ')');
          assert.ok(await A.isDisabled('#discGo'), 'Autorizar off after ' + what);
        }
        await closeWin(A);
      }
      // the wrong-code texts with a wait warning: never in one answer of the server (that code would start the wait),
      // but the line must hold them (mecanismo §10.1): the answer given by a route
      freshPlace(slot);
      let mock = null;
      await A.route(/\/rest\/v1\/rpc\/descuento_autorizar/, (r) => (mock ? r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(mock) }) : r.fallback()));
      for (const [c, step, base] of [['local', 'manager', ES.badMgr], ['guia', 'owner', ES.badOwner], ['empleado', 'employee', ES.badEmp]]) {
        for (const w of ['wait_1m', 'wait_5m', 'wait_10m']) {
          mock = { ok: false, error: c === 'empleado' ? 'bad_employee' : 'bad_pin', step, warn: w, blocked: null, until: null, wait: null, wait_s: null };
          await openWin(A);
          await attempt(A, c, PIN.ana, { employee: WRONG });
          await said(base + ' ' + ES.warn[w], 'answer ' + step + ' + ' + w);
          await closeWin(A);
        }
      }
      mock = null;
      await A.unroute(/\/rest\/v1\/rpc\/descuento_autorizar/);
      // (2) the category: Guía switched off, and no owner PIN; never over the till's own state
      sql(`delete from public.settings where key = 'pos_discount_guia'`);
      freshPlace(slot);
      await openWin(A);
      await cat(A, 'guia');
      await said(ES.guiaOff, 'Guía off');
      assert.ok(await A.isDisabled('#discGo'));
      await cat(A, 'local');
      await see(A, '#discErr', '');
      await closeWin(A);
      for (const [what, ages, want] of [['stopped', times(12, 7200), () => ES.stopped], ['waiting', [600, 590, 580, 2], (u) => ES.waitAt(hhmm(u, true))]]) {
        freshPlace(slot); wrongRows(slot, ages);
        const est = nextEstado(A);
        await openWin(A);
        const u = ms((await est).till.until);
        await said(want(u), what);
        await cat(A, 'guia');
        await said(want(u), what + ', Guía (off) tapped: the till\'s text, not Guía\'s');
        await cat(A, 'local');
        await said(want(u), what + ', then Local tapped');
        assert.ok(await A.isDisabled('#discGo'));
        await closeWin(A);
      }
      guiaOn();
      freshPlace(slot);
      sql(`update public.staff set pin_hash = null where role = 'owner'`);
      await openWin(A);
      await cat(A, 'guia');
      await said(ES.noOwner, 'no owner PIN');
      await closeWin(A);
      // (1) the till-state texts of a device: not registered, registration removed (its key forgotten), no sign-in id
      const N = await posPage(browser, Object.assign({ station: { name: 'Tableta N', main: false } }, V));
      await openWin(N);
      await lineSays(N, ES.notEnrolled, 'not registered'); checked++;
      assert.ok(await N.isDisabled('#discGo'));
      await closeWin(N);
      const E = await posPage(browser, Object.assign({ station: { name: 'Tableta E', main: false } }, V));
      const re = await registerTill(E, { station: 'Tableta E', by: 'ana' });
      const u = await rpcAs(E, 'access_unlock', { p_staff_id: STAFF.ana, p_pin: PIN.ana });
      const q = await rpcAs(E, 'descuento_caja_quitar', { p_till_id: sql(`select id from discount_tills where slot = ${re.slot} and ended_at is null`), p_manager_id: STAFF.ana, p_manager_pin: PIN.ana }, u.token);
      await rpcAs(E, 'access_lock', {}, u.token);
      assert.ok(q.ok, 'E\'s registration removed: ' + JSON.stringify(q));
      await openWin(E);
      await lineSays(E, ES.ended, 'registration removed'); checked++;
      assert.ok(await E.isDisabled('#discGo'));
      await closeWin(E);
      assert.strictEqual(await storedKey(E), null, 'a key the server calls invalid is forgotten (mecanismo §10.2)');
      await stationLine(E, ES.lineEnded);
      const S = await posPage(browser, Object.assign({ login: null, storage: { [AUTH_KEY]: noSessionLogin() }, station: { name: 'Tableta S', main: false } }, V));
      await openWin(S);
      await lineSays(S, ES.noSession, 'no sign-in id'); checked++;
      assert.ok(await S.isDisabled('#discGo'));
      await closeWin(S);
      await stationLine(S, ES.noSession);
      console.log('        C-i: ' + checked + ' texts checked at 360 × 640');
      noCodeLeak(A);
      assert.deepStrictEqual(A.errors.concat(N.errors, E.errors, S.errors), []);
    }
  },
  {
    name: 'C-l: with 30 discount_till_unknown, 30 discount_code_wrong and 10 pin_locked rows newer than them, a discount_till_stopped row and an order_void row still show in the approvals log; the buckets show 10, 5 and 10; «30 códigos escritos en dispositivos sin registrar en 24 h.»',
    run: async ({ browser }) => {
      // after every row the test database already has (its menu was entered in the log as it was built): the void and the
      // stop, then the 70 rows anyone can cause, all newer (base = the newest row, so the order does not depend on the clock)
      const base = `(select max(at) from public.audit_log)`;
      sql(`create temp table b402 as select ${base} as t;
           insert into public.audit_log (at, action, manager_id, manager_name, target_id, summary, details) values
             ((select t from b402) + interval '1 second', 'order_void', '${STAFF.ana}', 'Ana', '', 'anulación de prueba 402', '{"total_crc": 1300}'::jsonb),
             ((select t from b402) + interval '2 seconds', 'discount_till_stopped', null, null, '', 'discounts stopped on one till: 12 wrong codes in 24 hours',
              jsonb_build_object('slot', 2, 'till_station', 'Caja Vieja', 'until', now() + interval '20 hours', 'day_n', 12));
           insert into public.audit_log (at, action, target_id, summary, details)
             select (select t from b402) + make_interval(secs => 2 + g), 'discount_till_unknown', '', 'a discount code was typed on a device not registered for discounts',
                    jsonb_build_object('session_tag', 's' || lpad(g::text, 7, '0'), 'station', 'Tableta X')
               from generate_series(1, 30) g;
           insert into public.audit_log (at, action, target_id, summary, details)
             select (select t from b402) + make_interval(secs => 32 + g), 'discount_code_wrong', '', 'wrong discount code (manager)',
                    jsonb_build_object('slot', 3, 'step', 'manager', 'why', 'no_match', 'station', 'Caja Z', 'till_station', 'Caja Z')
               from generate_series(1, 30) g;
           insert into public.audit_log (at, action, manager_id, manager_name, target_id, summary, details)
             select (select t from b402) + make_interval(secs => 62 + g), 'pin_locked', '${STAFF.luis}', 'Luis', '', 'PIN locked for 10 minutes after 5 wrong tries',
                    jsonb_build_object('staff_name', 'Luis') from generate_series(1, 10) g`);
      assert.ok(Number(sql(`select count(*) from public.audit_log where at > (select at from public.audit_log where summary = 'anulación de prueba 402')`)) >= 70,
        'at least 70 rows newer than the void: one list of 40 would show only them');
      const pg = await page(browser, { login: 'cafe', lang: 'es' });
      await timeUnlock(pg, 'ana');
      await until(async () => (await logRows(pg, ES.log.voided)).some((r) => r.includes('anulación de prueba 402')), 10000, 'the void still in the log');
      await until(async () => (await logRows(pg, ES.log.stopped)).length === 1, 5000, 'the stop still in the log');
      assert.ok((await logRows(pg, ES.log.stopped))[0].includes('Puesto 2 · Caja Vieja'), 'the stop names its place and till');
      const labels = await logLabels(pg);
      const count = (l) => labels.filter((x) => x === l).length;
      assert.deepStrictEqual([count(ES.log.wrong), count(ES.log.unknown), count(ES.log.pinLocked)], [10, 5, 10], 'each bucket shows its own last rows (10 wrong codes, 5 unknown devices, 10 PIN locks)');
      await see(pg, '#dtNotes', ES.unknownN(30));
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'C-m: the wait timer follows the server: with the page\'s clock 5 minutes behind, then 5 minutes ahead, a 1-minute wait re-enables «Autorizar descuento» after wait_s and not before, and re-arms from the new wait_s while the server still says wait',
    run: async ({ browser }) => {
      testMenu();
      const A = await posPage(browser, { station: { name: 'Caja A', main: true }, clockAt: Date.now() - 300000 });
      const slot = (await registerTill(A, { station: 'Caja A' })).slot;
      const estados = () => sent(A, 'descuento_estado').length;
      const quiet = () => A.waitForTimeout(250);   // a fired timer would have sent its request by then
      const oneWait = async (label) => {
        freshPlace(slot); wrongRows(slot, [600, 590, 580]);
        await openWin(A);
        await lineSays(A, ES.warn.wait_1m, label + ': the next mistake waits 1 minute');
        const a = await attempt(A, 'local', WRONG);
        assert.deepStrictEqual([a.error, a.blocked, a.wait], ['bad_pin', 'wait', '1m'], label + ': a 1-minute wait');
        assert.ok(a.wait_s >= 55 && a.wait_s <= 61, label + ': wait_s by the server\'s clock: ' + a.wait_s);
        await lineSays(A, ES.waitAt(hhmm(ms(a.until), true)), label + ': {t} from the server\'s until, not this device\'s clock');
        assert.ok(await A.isDisabled('#discGo'), label + ': Autorizar off');
        await until(() => A.evaluate(() => !!disc.timer), 5000, label + ': the timer armed');
        // not before wait_s
        const n0 = estados();
        await A.clock.fastForward((a.wait_s - 3) * 1000);
        await quiet();
        assert.strictEqual(estados(), n0, label + ': no check before wait_s');
        assert.ok(await A.isDisabled('#discGo'), label + ': still off before wait_s');
        // at wait_s the page asks; the server still says wait (its clock barely moved): armed again from the new wait_s
        let est = nextEstado(A);
        await A.clock.fastForward(4000);
        const e2 = await est;
        assert.strictEqual(e2.till.state, 'wait', label + ': the server still waits');
        assert.ok(e2.till.wait_s >= 1 && e2.till.wait_s <= a.wait_s, label + ': a new wait_s ' + e2.till.wait_s);
        await until(() => A.evaluate(() => !!disc.timer), 5000, label + ': the timer armed again');
        assert.ok(await A.isDisabled('#discGo'), label + ': still off while the server waits');
        assert.strictEqual(estados(), n0 + 1);
        // the wait over on the server: the page knows only at the new wait_s
        shiftBack(slot, 120);
        await A.clock.fastForward(Math.max(0, e2.till.wait_s - 3) * 1000);
        await quiet();
        assert.strictEqual(estados(), n0 + 1, label + ': no check before the new wait_s');
        assert.ok(await A.isDisabled('#discGo'), label + ': off until the server is asked again');
        est = nextEstado(A);
        await A.clock.fastForward(4000);
        const e3 = await est;
        assert.strictEqual(e3.till.state, 'ok', label + ': the server says the wait is over');
        await until(async () => !(await A.isDisabled('#discGo')), 5000, label + ': Autorizar on again');
        await lineSays(A, ES.warn.wait_5m, label + ': what the next mistake costs');
        await closeWin(A);
      };
      const off = await A.evaluate(() => Date.now()) - Date.now();
      assert.ok(off < -280000 && off > -320000, 'the page\'s clock is 5 minutes behind: ' + off);
      await oneWait('clock 5 min behind');
      await A.clock.setSystemTime(Date.now() + 300000);
      const ahead = await A.evaluate(() => Date.now()) - Date.now();
      assert.ok(ahead > 280000 && ahead < 320000, 'the page\'s clock is 5 minutes ahead: ' + ahead);
      await oneWait('clock 5 min ahead');
      assert.deepStrictEqual(A.errors, []);
    }
  },
  {
    name: 'C-n: with the 3 places held, «Registrar este dispositivo» says till_full and offers «Reemplazar con este dispositivo» on each place; replacing one says «Dispositivo registrado en lugar de «…».»; a manager already holding 2 places sees person_limit and the button only on her own',
    run: async ({ browser }) => {
      addBea();
      sql(`insert into public.discount_tills (slot, session_id, login_id, station, enrolled_by, enrolled_by_name, key_hash, last_used_at) values
             (1, 'fixture-402-a', '${CAFE}', 'Caja A', '${STAFF.ana}', 'Ana', null, now() - interval '3 hours'),
             (2, 'fixture-402-b', '${CAFE}', 'Caja B', '${STAFF.ana}', 'Ana', null, null),
             (3, 'fixture-402-c', '${CAFE}', 'Caja C', '${BEA.id}', 'Bea', null, null)`);
      const lastA = sqlMs(`select last_used_at from discount_tills where slot = 1`);
      const D = await page(browser, { login: 'cafe', lang: 'es', station: { name: 'Caja D', main: true } });
      const asked = []; D.onDialog = async (d) => { asked.push(d.message()); await d.accept(); };
      await timeUnlock(D, 'bea');
      await D.click('#dtRegister');
      await see(D, '#dtMsg', ES.tillFull);
      for (const s of [1, 2, 3]) await seeRow(D, s, { buttons: [ES.remove, ES.replace] });
      const sinceA = sqlMs(`select enrolled_at from discount_tills where slot = 1`);
      await seeRow(D, 1, { head: `Puesto 1: Caja A · registrada por Ana, ${dmon(sinceA)} · ${lastUse(lastA)}` });
      assert.strictEqual(sql(`select count(*) from discount_tills where ended_at is null`), '3', 'nothing replaced by itself');
      await rowButton(D, 1, ES.replace).click();
      await see(D, '#dtMsg', ES.registeredIn('Caja A'));
      assert.deepStrictEqual(asked, [ES.replaceAsk('Caja A', dmon(lastA))], 'the confirmation names the till and its last use');
      const k = await storedKey(D), t1 = tillAt(1);
      assert.ok(k && k.key && sha256(k.key) === t1.key_hash, 'D keeps the key of place 1');
      assert.deepStrictEqual([t1.station, t1.enrolled_by_name], ['Caja D', 'Bea']);
      assert.strictEqual(sql(`select ended_how || '/' || ended_by_name from discount_tills where session_id = 'fixture-402-a'`), 'replaced/Bea', 'the replaced till ended «replaced» by Bea');
      await seeRow(D, 1, { head: new RegExp('^Puesto 1: Caja D · registrada por Bea, '), state: `${ES.wrongN(0)} · ${ES.active} · ${ES.here}`, buttons: [ES.remove] });
      // Bea now holds 2 places: on another device she may only replace one of hers
      const E = await page(browser, { login: 'cafe', lang: 'es', station: { name: 'Caja E', main: true } });
      const asked2 = []; E.onDialog = async (d) => { asked2.push(d.message()); await d.accept(); };
      await timeUnlock(E, 'bea');
      await see(E, '#dtFoot', ES.foot(0, [2, 1, 1]));
      await E.click('#dtRegister');
      await see(E, '#dtMsg', ES.personLimit);
      await seeRow(E, 1, { buttons: [ES.remove, ES.replace] });
      await seeRow(E, 2, { head: new RegExp('^Puesto 2: Caja B · registrada por Ana'), buttons: [ES.remove] });
      await seeRow(E, 3, { buttons: [ES.remove, ES.replace] });
      await rowButton(E, 3, ES.replace).click();
      await see(E, '#dtMsg', ES.registeredIn('Caja C'));
      assert.deepStrictEqual(asked2, ['¿Reemplazar «Caja C» (nunca usada) con este dispositivo?']);
      assert.strictEqual(tillAt(3).station, 'Caja E');
      await see(E, '#dtFoot', ES.foot(0, [2, 2, 2]));
      assert.deepStrictEqual(D.errors.concat(E.errors), []);
    }
  },
  {
    name: 'adjustment 2: one person at one tablet cannot stop the discounts of the other tills: 12 wrong codes typed at A stop A only (the café alert pauses nothing); B and C still approve; A signed in again comes back to its stopped place',
    run: async ({ browser }) => {
      testMenu();
      const A = await posPage(browser, { station: { name: 'Caja A', main: true } });
      const sa = (await registerTill(A, { station: 'Caja A' })).slot;
      const B = await posPage(browser, { station: { name: 'Caja B', main: true } });
      const sb = (await registerTill(B, { station: 'Caja B' })).slot;
      const C = await posPage(browser, { station: { name: 'Caja C', main: false } });
      const sc = (await registerTill(C, { station: 'Caja C', by: 'dueno' })).slot;   // Ana holds 2 places at most
      const got = [];
      for (let i = 1; i <= 12; i++) {
        await openWin(A);
        const a = await attempt(A, 'local', WRONG);
        assert.strictEqual(a.error, 'bad_pin', 'wrong code ' + i + ' tested: ' + JSON.stringify(a));
        got.push(a.blocked || '-');
        await closeWin(A);
        if (i < 12) shiftBack(sa, 660);    // as if 11 minutes had passed: every wait is over before the next code
      }
      assert.deepStrictEqual(got, ['-', '-', 'wait', 'wait', 'wait', 'wait', 'wait', 'wait', 'wait', 'wait', 'wait', 'stopped'], 'the ladder of one place, then the stop');
      await openWin(A);
      await lineSays(A, ES.stopped, 'A stopped');
      assert.ok(await A.isDisabled('#discGo'));
      await closeWin(A);
      assert.strictEqual(sql(`select count(*) from audit_log where action = 'discount_till_stopped' and details ->> 'slot' = '${sa}'`), '1', 'A\'s place stopped');
      assert.strictEqual(sql(`select count(*) from audit_log where action = 'discount_alert'`), '1', 'the café-wide alert written once');
      assert.deepStrictEqual([wrongCount(sb), wrongCount(sc)], [0, 0], 'nothing counted on the other places');
      await approveLocal(B, 'ana');
      await approveLocal(C, 'ana');
      // what the approvals log shows (mecanismo §10.3): the stopped place, the café alert that pauses nothing, the rows
      await timeUnlock(C, 'ana');
      await seeRow(C, sa, { head: new RegExp('^Puesto ' + sa + ': Caja A · registrada por Ana, '), state: new RegExp('^' + ES.wrongN(12) + ' · ' + ES.stoppedUntil(dayTime(stopAt(sa))) + '$'),
                            buttons: [ES.resume, ES.remove] });
      await seeRow(C, sb, { state: new RegExp('^' + ES.wrongN(0) + ' · ' + ES.active) });
      /* the alert's own figure and time (the 10th code wrote it), not the count now */
      const al = sqlJson(`select json_build_object('at', floor(extract(epoch from at) * 1000)::bigint, 'n', details -> 'cafe_24h') from audit_log where action = 'discount_alert'`);
      assert.strictEqual(al.n, 10, 'the alert counted 10 when it was written');
      await see(C, '#dtNotes', 'Alerta a las ' + hhmm(Number(al.at)) + ': 10 códigos de descuento equivocados en 24 horas en el café. No pausa nada; revise quién y dónde.');
      await until(async () => (await logRows(C, 'Muchos códigos de descuento equivocados')).length === 1, 8000, 'the alert in the log');
      assert.ok((await logRows(C, ES.log.stopped))[0].includes('Puesto ' + sa + ' · Caja A'), 'the stop in the log, with its place and till');
      assert.strictEqual((await logRows(C, ES.log.wrong)).length, 10, 'the wrong codes: their last 10');
      await goto(C, '/pos'); await posReady(C);
      await approveLocal(C, 'ana');
      // signing out and in again on A gives no fresh budget: back to its own stopped place
      await signOut(A);
      await signIn(A);
      await openWin(A);
      await lineSays(A, ES.stopped, 'A signed in again');
      await closeWin(A);
      assert.strictEqual(tillAt(sa).station, 'Caja A', 'A came back to place ' + sa);
      await approveLocal(B, 'ana');
      noCodeLeak(A); noCodeLeak(B);
      assert.deepStrictEqual(A.errors.concat(B.errors, C.errors), []);
    }
  },
  {
    name: 'api-0038 §13 item 36, the POS: the reply of descuento_caja_volver lost after a new sign-in: the rebind is marked pending first (the login, no key, no code), asked again a second later, and the server sends this same sign-in a new key (the lost one spent, no second rebound row); the page keeps it and the next sign-in comes back to the same place. Both replies lost: the mark stays, the page says «sin registrar» for now, and the next load sends the key again although the till reads registered, keeps the new key, clears the mark; the next sign-in comes back to the same place',
    run: async ({ browser }) => {
      testMenu();
      const A = await posPage(browser, { station: { name: 'Caja A', main: true } });
      const reg = await registerTill(A, { station: 'Caja A' });
      const t0 = tillAt(reg.slot), k0 = await storedKey(A);
      const drop = await dropReplies(A, 'descuento_caja_volver');
      const rebounds = () => sql(`select count(*) from audit_log where action = 'discount_till_rebound'`);
      // (a) one reply lost: the page asks again and keeps the key the retry brings
      await signOut(A);
      drop.left = 1;
      await signIn(A);
      const s1 = await signin(A);
      await stationLine(A, ES.lineReg('Ana', dmon(t0.since)));
      const v1 = sent(A, 'descuento_caja_volver');
      assert.strictEqual(v1.length, 2, 'the rebind and its one retry');
      assert.ok(v1.every((x) => JSON.parse(x.body).p_key === k0.key), 'both send the key this device holds');
      markOk(drop.marks[0], 'volver', [k0.key]);
      const lost = drop.lost[0];
      assert.ok(lost.ok && !lost.already && /^[0-9a-f]{64}$/.test(lost.key), 'the lost reply was the rebind itself: ' + JSON.stringify(Object.keys(lost)));
      const t1 = tillAt(reg.slot), k1 = await storedKey(A);
      assert.ok(k1 && k1.login === CAFE && k1.key !== k0.key && k1.key !== lost.key, 'a new key kept: neither the one sent nor the lost one');
      assert.strictEqual(t1.key_hash, sha256(k1.key), 'the kept key is the one the server holds: the lost one is spent');
      assert.deepStrictEqual([t1.slot, t1.session_id, t1.rebound_from, t1.enrolled_by_name, t1.since], [t0.slot, s1.sid, t0.id, 'Ana', t0.since], 'the same place, this sign-in, the original registration');
      assert.strictEqual(sql(`select count(*) from discount_tills`), '2', 'the first row and the rebound one: the retry made no third');
      assert.strictEqual(rebounds(), '1', 'one discount_till_rebound row: the key sent again writes none');
      assert.strictEqual(await pending(A), null, 'the mark cleared by the answer');
      await signOut(A);
      await signIn(A);
      await stationLine(A, ES.lineReg('Ana', dmon(t0.since)));
      const t2 = tillAt(reg.slot), k2 = await storedKey(A);
      assert.deepStrictEqual([t2.slot, t2.rebound_from, t2.enrolled_by_name], [t0.slot, t1.id, 'Ana'], 'the next sign-in came back to place ' + t0.slot + ' by the kept key');
      assert.strictEqual(t2.key_hash, sha256(k2.key), 'and keeps its new key');
      await approveLocal(A, 'ana');
      // (b) both replies lost: the mark stays until the next load
      await signOut(A);
      drop.left = 2;
      const n0 = sent(A, 'descuento_caja_volver').length;
      await signIn(A);
      const s3 = await signin(A);
      await stationLine(A, ES.lineNot);
      assert.strictEqual(sent(A, 'descuento_caja_volver').length - n0, 2, 'the rebind and its one retry, both lost');
      const [l1, l2] = drop.lost.slice(1);
      assert.ok(l1.ok && !l1.already && l2.ok && l2.already === true && /^[0-9a-f]{64}$/.test(l2.key), 'the server rebound at the first and sent this sign-in a new key at the retry: ' + JSON.stringify([Object.keys(l1), Object.keys(l2)]));
      const t3 = tillAt(reg.slot);
      assert.deepStrictEqual([t3.slot, t3.session_id, t3.rebound_from, t3.key_hash], [t0.slot, s3.sid, t2.id, sha256(l2.key)], 'on the server the till is back on this sign-in, holding the key of the retry\'s lost reply');
      assert.deepStrictEqual(await storedKey(A), k2, 'the page still holds the key it sent');
      const mk = await pending(A);
      markOk(mk, 'volver', [k2.key, l1.key, l2.key]);
      // the next load: the key sent again although the till reads registered (the same row, no new rebind)
      const n1 = sent(A, 'descuento_caja_volver').length, r0 = rebounds();
      await goto(A, '/pos'); await posReady(A);
      await until(async () => (await pending(A)) === null, 10000, 'the mark cleared at the next load');
      assert.strictEqual(sent(A, 'descuento_caja_volver').length - n1, 1, 'one call at the load, without anyone opening a window');
      const t4 = tillAt(reg.slot), k4 = await storedKey(A);
      assert.ok(k4 && k4.key !== k2.key && k4.key !== l2.key, 'a new key kept');
      assert.deepStrictEqual([t4.id, t4.key_hash], [t3.id, sha256(k4.key)], 'the same row, now holding the key the page keeps');
      assert.strictEqual(rebounds(), r0, 'no rebound row for a key sent again');
      await stationLine(A, ES.lineReg('Ana', dmon(t0.since)));
      await signOut(A);
      await signIn(A);
      await stationLine(A, ES.lineReg('Ana', dmon(t0.since)));
      const t5 = tillAt(reg.slot);
      assert.deepStrictEqual([t5.slot, t5.rebound_from, t5.key_hash], [t0.slot, t3.id, sha256((await storedKey(A)).key)], 'the next sign-in came back to the same place');
      await approveLocal(A, 'ana');
      noCodeLeak(A);
      assert.deepStrictEqual(A.errors, []);
    }
  },
  {
    name: 'api-0038 §13 item 36, Reloj de marcas: the reply of «Registrar este dispositivo para descuentos» lost: marked pending first, asked again with the owner areas still open on this sign-in; the server answers already with a new key (the lost one spent, one registration), the page keeps it and says «Dispositivo registrado para descuentos.»; the next sign-in comes back to the same place. Every reply lost (device B): «No se pudo guardar…», the mark stays through the log\'s own retry, and the next load of the log asks again and keeps the key; B\'s next sign-in comes back too',
    run: async ({ browser }) => {
      testMenu();
      const enrolled = () => sql(`select count(*) from audit_log where action = 'discount_till_enrolled'`);
      // A: one reply lost
      const A = await posPage(browser, { station: { name: 'Caja A', main: true } });
      const sidA = (await signin(A)).sid;
      await timeUnlock(A, 'ana');
      await until(() => A.isVisible('#dtRegister'), 8000, '«Registrar este dispositivo para descuentos»');
      const dA = await dropReplies(A, 'descuento_caja_registrar');
      dA.left = 1;
      await A.click('#dtRegister');
      await see(A, '#dtMsg', ES.registered, 10000);
      assert.strictEqual(sent(A, 'descuento_caja_registrar').length, 2, 'the registration and its one retry');
      markOk(dA.marks[0], 'registrar', []);
      const lostA = dA.lost[0];
      assert.ok(lostA.ok && !lostA.already && /^[0-9a-f]{64}$/.test(lostA.key), 'the lost reply was the registration itself');
      const kA = await storedKey(A), tA = tillAt(1);
      assert.ok(kA && kA.login === CAFE && kA.key !== lostA.key, 'a key kept, not the lost one');
      assert.deepStrictEqual([tA.station, tA.enrolled_by_name, tA.session_id, tA.key_hash], ['Caja A', 'Ana', sidA, sha256(kA.key)], 'A\'s till on this sign-in holds the kept key: the lost one is spent');
      assert.deepStrictEqual([sql(`select count(*) from discount_tills`), enrolled()], ['1', '1'], 'one registration, one discount_till_enrolled row');
      assert.strictEqual(await pending(A), null, 'the mark cleared by the answer');
      await until(async () => A.isHidden('#dtRegister'), 5000, 'the register button gone');
      await seeRow(A, 1, { head: `Puesto 1: Caja A · registrada por Ana, ${dmon(tA.since)}`, state: `${ES.wrongN(0)} · ${ES.active} · ${ES.here}` });
      await goto(A, '/pos'); await posReady(A);
      await signOut(A);
      await signIn(A);
      await stationLine(A, ES.lineReg('Ana', dmon(tA.since)));
      const tA1 = tillAt(1);
      assert.deepStrictEqual([tA1.slot, tA1.rebound_from, tA1.key_hash], [1, tA.id, sha256((await storedKey(A)).key)], 'A\'s next sign-in came back to place 1 by the kept key');
      await approveLocal(A, 'ana');
      // B: both replies lost
      const B = await posPage(browser, { station: { name: 'Caja B', main: true } });
      const sidB = (await signin(B)).sid;
      await timeUnlock(B, 'ana');
      await until(() => B.isVisible('#dtRegister'), 8000, '«Registrar este dispositivo para descuentos» on B');
      // every reply lost while the connection is bad: the tap and its retry, then the log read again at once (its
      // descuento_cajas answers) asks registrar twice more, lost too
      const dB = await dropReplies(B, 'descuento_caja_registrar');
      dB.left = 99;
      await B.click('#dtRegister');
      await see(B, '#dtMsg', 'No se pudo guardar. Revise la conexión e intente de nuevo.', 10000);
      await until(() => dB.lost.length === 4, 10000, 'the log asks again once the tap gave up');
      await new Promise((r) => setTimeout(r, 1500));
      assert.strictEqual(dB.lost.length, 4, 'no more than the tap, its retry, and the log\'s two');
      const [b1, ...bs] = dB.lost, bLast = bs[bs.length - 1];
      assert.ok(b1.ok && !b1.already && bs.every((x) => x.ok && x.already === true && /^[0-9a-f]{64}$/.test(x.key)), 'registered at the first, the key sent again after: ' + JSON.stringify(dB.lost.map((x) => Object.keys(x))));
      const tB = tillAt(2);
      assert.deepStrictEqual([tB.station, tB.session_id, tB.key_hash], ['Caja B', sidB, sha256(bLast.key)], 'on the server B is registered on this sign-in, holding the last lost key');
      assert.strictEqual(sql(`select count(*) from discount_tills where slot = 2`), '1', 'one registration');
      assert.strictEqual(await storedKey(B), null, 'B holds no key yet');
      markOk(await pending(B), 'registrar', dB.lost.map((x) => x.key));
      dB.left = 0;
      const e0 = enrolled(), n0 = sent(B, 'descuento_caja_registrar').length;
      await timeUnlock(B, 'ana');    // the log loaded again: the owner areas are open on this sign-in
      await until(async () => (await pending(B)) === null && !!(await storedKey(B)), 10000, 'the key kept and the mark cleared at the next load of the log');
      const kB = await storedKey(B), tB1 = tillAt(2);
      assert.strictEqual(sent(B, 'descuento_caja_registrar').length - n0, 1, 'asked once more');
      assert.ok(kB.login === CAFE && !dB.lost.some((x) => x.key === kB.key), 'a new key kept');
      assert.deepStrictEqual([tB1.id, tB1.key_hash], [tB.id, sha256(kB.key)], 'the same registration, now holding the key B keeps');
      assert.strictEqual(enrolled(), e0, 'no second discount_till_enrolled row');
      await seeRow(B, 2, { state: `${ES.wrongN(0)} · ${ES.active} · ${ES.here}` });
      assert.ok(await B.isHidden('#dtRegister'), 'no register button on a registered device');
      await goto(B, '/pos'); await posReady(B);
      await signOut(B);
      await signIn(B);
      await stationLine(B, ES.lineReg('Ana', dmon(tB.since)));
      const tB2 = tillAt(2);
      assert.deepStrictEqual([tB2.slot, tB2.rebound_from], [2, tB.id], 'B\'s next sign-in came back to place 2');
      await approveLocal(B, 'ana');
      noCodeLeak(A); noCodeLeak(B);
      assert.deepStrictEqual(A.errors.concat(B.errors), []);
    }
  }
  ,
  {
    name: 'mecanismo §10.3, the café alert in «Cajas para descuentos»: while it is up, its own figure and time, even once the codes behind it have aged out of the 24 hours (never «Alerta: 1 códigos…»)',
    run: async ({ browser }) => {
      testMenu();
      const A = await posPage(browser, { station: { name: 'Caja A', main: true } });
      const sa = (await registerTill(A, { station: 'Caja A' })).slot;
      /* a burst of ten wrong codes 24 hours ago wrote the alert at the tenth (23 h 55 min ago): nine have aged out of the
         24 hours, one is still in them */
      wrongRows(sa, times(9, 86400 + 240).concat([86100]));
      sql(`insert into public.audit_log (at, action, summary, details) values (now() - interval '86100 seconds', 'discount_alert',
           'many wrong discount codes across the café in 24 hours', jsonb_build_object('cafe_24h', 10))`);
      const at = sqlMs(`select at from public.audit_log where action = 'discount_alert'`);
      await timeUnlock(A, 'ana');
      await see(A, '#dtNotes', 'Alerta a las ' + hhmm(at) + ': 10 códigos de descuento equivocados en 24 horas en el café. No pausa nada; revise quién y dónde.');
      assert.ok(!/Alerta: 1 /.test(await text(A, '#dtNotes')), 'never «Alerta: 1 códigos…»');
      assert.deepStrictEqual(A.errors, []);
    }
  }
];
