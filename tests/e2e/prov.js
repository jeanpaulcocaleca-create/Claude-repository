/* Canopy OS browser tests · Proveedores (D-067, migrations 0039/0040): the data and the ways in shared by the 41x specs.
   seed() inserts two suppliers with their catalogs (as the superuser, the way 160/290 seed theirs); the page is then opened
   as management (the owner with the phone code, or a café device unlocked with a manager's PIN through access.js's gate)
   or as an employee on shift (a work session on this device: «Estoy en turno aquí» with the PIN once, or the POS's
   «¿Quién cobra?»). PINs come from lib.js by reference and are never printed. */
'use strict';
const assert = require('assert');
const { spawnSync } = require('child_process');
const zlib = require('zlib');
const { page, goto, until, settle, sql, STAFF, PINS } = require('./lib');

const V = { lac: '5b000000-0000-4000-8000-00000000a410', pan: '5b000000-0000-4000-8000-00000000a411', fin: '5b000000-0000-4000-8000-00000000a412' };
const I = {
  leche: '5a000000-0000-4000-8000-00000000a401', yogur: '5a000000-0000-4000-8000-00000000a402', queso: '5a000000-0000-4000-8000-00000000a403',
  mant: '5a000000-0000-4000-8000-00000000a404', crema: '5a000000-0000-4000-8000-00000000a405', natilla: '5a000000-0000-4000-8000-00000000a406',
  pan: '5a000000-0000-4000-8000-00000000a407', croissant: '5a000000-0000-4000-8000-00000000a408', azucar: '5a000000-0000-4000-8000-00000000a409'
};
/* the catalog rows the item trigger makes (one per item with a preferred supplier) are read back by item; these are the
   extra ones: Panadería Sol also sells milk by the half box, and sugar (which has no preferred supplier) by the 5 kg sack */
const VI = { lecheMedia: '5c000000-0000-4000-8000-00000000a420', azucarSaco: '5c000000-0000-4000-8000-00000000a421' };

function seed() {
  sql(`insert into vendors (id, name, contact_name, phone, whatsapp, email, lead_days, order_days, notes) values
         ('${V.lac}', 'Lácteos Monteverde', 'Rosa Jiménez', '2645 1111', '+506 8888 1111', 'ventas@lacteos.test', 2, 'lun, jue', 'Entregan antes de las 9'),
         ('${V.pan}', 'Panadería Sol', 'Don Mario', '2645 2222', null, null, 1, null, null),
         ('${V.fin}', 'Finca La Fresa', null, null, null, null, 3, null, null);
       insert into stock_items (id, name, category, unit, pack_label, pack_qty, cost_per_pack, avg_cost, vendor_id, on_hand, reorder_point, par_level) values
         ('${I.leche}', 'Leche entera', 'dairy', 'unit', 'caja de 12', 12, 10200, 850, '${V.lac}', 6, 24, 72),
         ('${I.yogur}', 'Yogur natural', 'dairy', 'unit', 'paquete de 6', 6, 4500, 750, '${V.lac}', 40, 12, 36),
         ('${I.queso}', 'Queso turrialba', 'dairy', 'kg', null, 1, 5200, 5200, '${V.lac}', 3, 2, 6),
         ('${I.mant}', 'Mantequilla', 'dairy', 'g', 'barra de 500 g', 500, 3100, 6.2, '${V.lac}', 4000, 1000, 5000),
         ('${I.crema}', 'Crema dulce', 'dairy', 'ml', 'cartón de 946 ml', 946, 2100, 2.22, '${V.lac}', 9000, 2000, 10000),
         ('${I.natilla}', 'Natilla', 'dairy', 'unit', 'paquete de 12', 12, 6000, 500, '${V.lac}', 30, 12, 36),
         ('${I.pan}', 'Pan baguette', 'bakery', 'unit', 'bolsa de 10', 10, 3000, 300, '${V.pan}', 0, 10, 40),
         ('${I.croissant}', 'Croissant', 'bakery', 'unit', 'caja de 24', 24, 9600, 400, '${V.pan}', 50, 12, 48),
         ('${I.azucar}', 'Azúcar', 'dry', 'kg', null, 1, 900, 900, null, 1, 5, 20);
       insert into vendor_items (id, vendor_id, item_id, pack_label, pack_qty, usual_price, created_by) values
         ('${VI.lecheMedia}', '${V.pan}', '${I.leche}', 'media caja de 6', 6, 5400, 'test'),
         ('${VI.azucarSaco}', '${V.pan}', '${I.azucar}', 'saco de 5 kg', 5, 4300, 'test');
       update vendor_items set vendor_code = 'LE-12' where item_id = '${I.leche}' and vendor_id = '${V.lac}'`);
}
/* the live catalog row of an item at a supplier (made by the item trigger, smallest pack first) */
function vi(item, vendor) {
  return sql(`select id from vendor_items where item_id = '${item}' and vendor_id = '${vendor || V.lac}' and active order by pack_qty limit 1`);
}
/* an order made through the 0039 function as the superuser would make it from the page (management) */
function order(vendor, lines, opts) {
  opts = opts || {};
  const id = opts.id || sql(`select gen_random_uuid()`);
  const js = JSON.stringify(lines.map((l) => Object.assign({ vendor_item_id: l.vi, packs: l.packs }, l.price != null ? { pack_price: l.price } : {})));
  // the function's gate is is_owner(): the test superuser has no JWT, so the order is inserted the way the function would
  sql(`insert into purchase_orders (id, vendor_id, status, sent_at, note, by_name) values ('${id}', '${vendor}', 'sent', now() - interval '${opts.ago || '1 hour'}', ${opts.note ? `'${opts.note}'` : 'null'}, 'Dueño');
       insert into purchase_lines (po_id, item_id, packs, qty, unit_cost, ordered_unit_cost, vendor_item_id, pack_label, pack_qty, pos)
       select '${id}', v.item_id, (l->>'packs')::numeric, round((l->>'packs')::numeric * v.pack_qty, 4),
              round(coalesce((l->>'pack_price')::numeric, v.usual_price) / v.pack_qty, 6), round(coalesce((l->>'pack_price')::numeric, v.usual_price) / v.pack_qty, 6),
              v.id, v.pack_label, v.pack_qty, o.n
         from jsonb_array_elements('${js}'::jsonb) with ordinality o(l, n) join vendor_items v on v.id = (l->>'vendor_item_id')::uuid`);
  return id;
}
/* a 0039/0040 function called as the owner with the phone code (the way the page calls it from the owner's phone): the
   test superuser takes the owner's claims and the authenticated role for this one statement; -> the jsonb answer */
function asOwner(q) {
  const claims = JSON.stringify({ sub: '0e000000-0000-4000-8000-000000000002', role: 'authenticated', aal: 'aal2', session_id: 'e2e-setup' });
  const r = spawnSync('psql', ['-X', '-q', '-At', '-v', 'ON_ERROR_STOP=1', '-d', process.env.CANOPY_E2E_DB,
    '-c', `select set_config('request.jwt.claims', '${claims}', false) is null; set role authenticated; ${q}`], { encoding: 'utf8' });
  if (r.status !== 0) throw new Error('SQL failed: ' + r.stderr + '\n' + q);
  const out = r.stdout.trim().split('\n').slice(1).join('\n');
  try { return JSON.parse(out); } catch (e) { return out; }
}
/* an order made through proveedor_pedido_crear as the owner: lines [{vi, packs, price?}] -> {id, po_number, version} */
function create(vendor, lines, opts) {
  opts = opts || {};
  const id = opts.id || sql(`select gen_random_uuid()`);
  const js = JSON.stringify(lines.map((l) => Object.assign({ vendor_item_id: l.vi, packs: l.packs }, l.price != null ? { pack_price: l.price } : {})));
  const r = asOwner(`select public.proveedor_pedido_crear('${vendor}', '${js}'::jsonb, ${opts.note ? `'${opts.note}'` : 'null'}, '${id}')`);
  if (!r || !r.ok) throw new Error('proveedor_pedido_crear: ' + JSON.stringify(r));
  return r;
}
/* a delivery booked through proveedor_recibir as the owner: lines [{line, packs} | {line, rest:true}] */
function receive(po, lines, opts) {
  opts = opts || {};
  const ver = sql(`select version from purchase_orders where id = '${po}'`);
  const js = JSON.stringify(lines.map((l) => Object.assign({ line_id: l.line }, l.rest ? { rest: true } : { packs: l.packs }, l.price != null ? { pack_price: l.price } : {})));
  const r = asOwner(`select public.proveedor_recibir('${po}', gen_random_uuid(), ${ver}, '${js}'::jsonb, null, ${!!opts.close}, ${opts.invoice ? `'${opts.invoice}'` : 'null'})`);
  if (!r || !r.ok) throw new Error('proveedor_recibir: ' + JSON.stringify(r));
  return r;
}
function lineOf(po, item) { return sql(`select id from purchase_lines where po_id = '${po}' and item_id = '${item}' and removed_at is null`); }

/* a small PDF reader for the tests (no library): the pages in order, each with its content stream (inflated when it is
   compressed, as Chromium's are) and the text of its (…) Tj strings (the page's own writer, WinAnsi) */
function pdfRead(buf) {
  const s = buf.toString('latin1'), objs = {};
  const re = /(\d+) 0 obj\b/g; let m;
  while ((m = re.exec(s))) {
    const start = m.index + m[0].length, end = s.indexOf('endobj', start);
    if (end < 0) break;
    objs[m[1]] = { start, body: s.slice(start, end) };
    re.lastIndex = end;
  }
  const dict = (id) => { const o = objs[id]; if (!o) return ''; const i = o.body.indexOf('stream'); return i < 0 ? o.body : o.body.slice(0, i); };
  function stream(id) {
    const o = objs[id]; if (!o) return '';
    const i = o.body.indexOf('stream'); if (i < 0) return '';
    let k = i + 6; if (o.body[k] === '\r') k++; if (o.body[k] === '\n') k++;
    const d = dict(id), lm = /\/Length\s+(\d+)(\s+0\s+R)?/.exec(d);
    let len = lm ? Number(lm[1]) : o.body.lastIndexOf('endstream') - k;
    if (lm && lm[2]) len = Number((objs[lm[1]] || { body: '0' }).body.trim());
    let data = buf.slice(o.start + k, o.start + k + len);
    if (/\/FlateDecode/.test(d)) { try { data = zlib.inflateSync(data); } catch (e) { data = Buffer.from(''); } }
    return data.toString('latin1');
  }
  const root = Object.keys(objs).find((k) => /\/Type\s*\/Catalog\b/.test(dict(k)));
  const rootPages = /\/Pages\s+(\d+)\s+0\s+R/.exec(dict(root))[1];
  const pages = [];
  (function walk(id) {
    const d = dict(id);
    if (/\/Type\s*\/Pages\b/.test(d)) { const kids = /\/Kids\s*\[([^\]]*)\]/.exec(d)[1].match(/\d+(?=\s+0\s+R)/g) || []; kids.forEach(walk); return; }
    const c = /\/Contents\s*(\[[^\]]*\]|\d+\s+0\s+R)/.exec(d);
    const ids = c ? (c[1].match(/\d+(?=\s+0\s+R)/g) || []) : [];
    const ops = ids.map(stream).join('\n');
    const strs = [];
    ops.replace(/\(((?:\\.|[^\\)])*)\)\s*Tj/g, (x, t) => { strs.push(t.replace(/\\([\\()])/g, '$1')); return x; });
    pages.push({ ops, text: strs.join('\n'), drawsText: /\bT[jJ]\b/.test(ops) });
  })(rootPages);
  return { pages, head: s.slice(0, 8), eof: /%%EOF\s*$/.test(s) };
}
function clockIn(who, minutesAgo) {
  sql(`insert into time_entries (staff_id, clock_in) values ('${STAFF[who]}', now() - interval '${minutesAgo == null ? 60 : minutesAgo} minutes')`);
}
const plain = (s) => String(s == null ? '' : s).replace(/\s+/g, ' ').trim();   // the page's money uses narrow no-break spaces
/* what a person reads (innerText: the layout's own breaks between blocks), on one line */
const text = async (loc) => plain(await loc.innerText());
/* waits until the text of loc matches re; a timeout says what was there */
async function seen(loc, re, what, ms) {
  let last = '';
  try { await until(async () => re.test(last = await text(loc)), ms || 8000, what); }
  catch (e) { throw new Error(e.message + ' · it said: «' + last.slice(0, 600) + '»'); }
  return last;
}

/* every RPC answer of the page with an HTTP error (a 4xx/5xx is a bug: the 0039 functions answer {ok:false}) */
function watchApi(pg) {
  pg.apiErrors = [];
  pg.on('response', (r) => {
    if (/\/rest\/v1\//.test(r.url()) && r.status() >= 400) pg.apiErrors.push(r.status() + ' ' + r.url().replace(/^.*\/rest\/v1\//, ''));
  });
  return pg;
}
/* to a route of the page in the same document (a hashchange); the same route again: through the hub, so it renders anew */
async function nav(pg, hash, sel) {
  const same = await pg.evaluate((h) => location.hash === h, hash);
  if (same) { await pg.evaluate(() => { location.hash = '#'; }); await pg.waitForTimeout(150); }
  await pg.evaluate((h) => { location.hash = h; }, hash);
  if (sel) await pg.waitForSelector(sel, { timeout: 10000 });
}
async function loaded(pg, sel) {
  await pg.waitForSelector(sel || '#hubVendors, #ficha, #orderDoc, #recvCard, #turnoView:not([hidden])', { timeout: 15000 });
}
/* management: the owner with the phone code (the books door too) on this device */
async function owner(browser, opts) {
  opts = opts || {};
  const pg = watchApi(await page(browser, Object.assign({ login: 'owner', aal: 'aal2', lang: 'es' }, opts)));
  await goto(pg, '/proveedores' + (opts.hash || ''));
  await loaded(pg, opts.wait);
  return pg;
}
/* management on the café tablet: the owner areas opened with a manager's PIN (access.js's gate) */
async function gate(pg, who) {
  await pg.waitForSelector('#hgaPin', { timeout: 10000 });
  await pg.selectOption('#hgaWho', STAFF[who || 'ana']);
  await pg.fill('#hgaPin', PINS[who || 'ana']);
  await pg.click('.hga-go');
}
async function cafeManager(browser, opts) {
  opts = opts || {};
  const pg = watchApi(await page(browser, Object.assign({ login: 'cafe', lang: 'es' }, opts)));
  await goto(pg, '/proveedores' + (opts.hash || ''));
  await pg.waitForSelector('#turnoView:not([hidden]), #modeBar:not([hidden])', { timeout: 15000 });
  await pg.click(await pg.locator('#turnoView').isVisible() ? '#turnoOwner' : '#modeBar button:has-text("áreas de dueños"), #modeBar button:has-text("owner areas")');
  await gate(pg, opts.who);
  await loaded(pg, opts.wait);
  return pg;
}
/* an employee says who receives on this device: tap the name, type their own PIN once */
async function iAmHere(pg, who, opts) {
  opts = opts || {};
  await pg.waitForSelector('#turnoView:not([hidden])', { timeout: 15000 });
  await settle(pg);
  const name = { ana: 'Ana', luis: 'Luis', marta: 'Marta', dueno: 'Dueño' }[who];
  await pg.locator(`#turnoView .who button[data-staff="${STAFF[who]}"]`).click();
  await pg.locator('#tqPin').pressSequentially(PINS[who]);   /* typed key by key: keypad.js wipes a PIN that was not typed */
  /* on a touch screen the PIN pad is open under the box: its ✓ sends the form (a tap elsewhere first closes the pad) */
  const ok = pg.locator('#tqPin + .hg-pad .ok');
  if (await ok.isVisible()) await ok.click(); else await pg.click('#turnoGo');
  if (opts.wait !== false) {
    try { await until(async () => plain(await pg.locator('#modeBar').textContent()).includes(name), 10000, name + ' receives on this device'); }
    catch (e) { throw new Error(e.message + ' · the PIN box said: «' + plain(await pg.locator('#turnoErr').textContent()) + '» · ' + plain(await pg.locator('#turnoView').innerText()).slice(0, 300)); }
  }
}
async function employee(browser, who, opts) {
  opts = opts || {};
  const pg = watchApi(await page(browser, Object.assign({ login: 'cafe', lang: 'es' }, opts)));
  await goto(pg, '/proveedores' + (opts.hash || ''));
  await iAmHere(pg, who, opts);
  return pg;
}
const toast = async (pg) => plain(await pg.locator('#toast').textContent());
/* the toast emptied, so the next toasted() waits for a new one (a toast stays 3 s) */
async function untoast(pg) { await pg.evaluate(() => { const t = document.getElementById('toast'); if (t) t.textContent = ''; }); }
async function toasted(pg, re, what, ms) {
  try { await until(async () => re.test(await toast(pg)), ms || 10000, what); }
  catch (e) { throw new Error(e.message + ' · toast: «' + (await toast(pg)) + '» · main: ' + plain(await pg.locator('#main').textContent()).slice(0, 400)); }
}
/* no horizontal page scroll; every visible button / link / input / select of the page at least 44 px high (and wide,
   for buttons and the checkboxes' targets) */
async function layoutOk(pg, where) {
  const r = await pg.evaluate(() => {
    const out = { scroll: document.documentElement.scrollWidth - document.documentElement.clientWidth, small: [] };
    document.querySelectorAll('#appView button, #appView a.btnlink, #appView .ftabs a, #appView input:not([type=checkbox]):not([type=radio]), #appView select, #appView .prow .ck, .modalbg:not([hidden]) button, .modalbg:not([hidden]) input:not([type=checkbox]), .modalbg:not([hidden]) select').forEach((e) => {
      const b = e.getBoundingClientRect();
      if (!b.width || !b.height || e.closest('[hidden]') || getComputedStyle(e).visibility === 'hidden') return;
      if (e.closest('.hga-pill') || e.closest('.hg-lang')) return;   /* access.js's pill and lang.js's EN/ES switch: the site's own, on every page */
      if (b.height < 43.5 || (e.tagName === 'BUTTON' && b.width < 43.5)) out.small.push((e.id || e.className || e.tagName) + ' «' + (e.textContent || e.value || '').trim().slice(0, 30) + '» ' + Math.round(b.width) + '×' + Math.round(b.height));
    });
    return out;
  });
  assert.ok(r.scroll <= 0, (where || '') + ': the page scrolls sideways by ' + r.scroll + ' px');
  assert.deepStrictEqual(r.small, [], (where || '') + ': targets under 44 px');
}

module.exports = { V, I, VI, seed, vi, order, asOwner, create, receive, lineOf, pdfRead, clockIn, plain, text, watchApi, loaded, owner, gate, cafeManager, iAmHere, employee, toast, untoast, toasted, layoutOk, seen, nav };
