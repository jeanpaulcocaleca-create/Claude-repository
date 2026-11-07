/* Canopy OS browser tests · helpers shared by the specs. */
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const gw = require('./gateway');

const ROOT = path.resolve(__dirname, '../..');
const SITE = 'http://127.0.0.1:' + (process.env.E2E_SITE_PORT || 8090);
const SBJS = fs.readFileSync(require.resolve('@supabase/supabase-js/dist/umd/supabase.js'), 'utf8');
const STORAGE_KEY = 'sb-127-auth-token';   // supabase-js storage key for the local API (host 127.0.0.1)
const STAFF = {
  ana: 'a1000000-0000-4000-8000-000000000001', luis: 'a1000000-0000-4000-8000-000000000002',
  marta: 'a1000000-0000-4000-8000-000000000003', dueno: 'a1000000-0000-4000-8000-000000000004'
};
const PINS = { ana: '4826', luis: '5284', marta: '6173', dueno: '7391' };
const LOGINS = { cafe: 'cafe@test.local', owner: 'owner@test.local', accountant: 'contador@test.local' };

function sql(q, db) {
  const r = spawnSync('psql', ['-X', '-At', '-v', 'ON_ERROR_STOP=1', '-d', db || process.env.CANOPY_E2E_DB, '-c', q], { encoding: 'utf8' });
  if (r.status !== 0) throw new Error('SQL failed: ' + r.stderr + '\n' + q);
  return r.stdout.trim();
}
function sqlJson(q, db) { const out = sql(q, db); return out ? JSON.parse(out) : null; }

/* a page on its own "device" (browser context) with the chosen login already signed in */
async function page(browser, opts) {
  opts = opts || {};
  const ctx = opts.context || await browser.newContext({ viewport: opts.viewport || { width: 1280, height: 860 },
                                                         locale: opts.lang === 'en' ? 'en-US' : 'es-CR', timezoneId: 'America/Costa_Rica' });
  const pg = await ctx.newPage();
  pg.errors = [];
  pg.supabaseHits = 0;
  pg.on('pageerror', (e) => pg.errors.push(e.message));
  pg.on('dialog', async (d) => { if (pg.onDialog) await pg.onDialog(d); else await d.accept(); });
  // page.css scrolls smoothly; a button inside a wide table never settles for Playwright's stability check while the
  // table scrolls it into view (a known Playwright gotcha), so the tests scroll instantly
  await pg.addInitScript(() => { document.addEventListener('DOMContentLoaded', () => { document.documentElement.style.scrollBehavior = 'auto'; }); });
  await pg.route(/fonts\.(googleapis|gstatic)\.com/, (r) => r.abort());
  await pg.route(/cdn\.jsdelivr\.net\/npm\/@supabase\/supabase-js/, (r) => r.fulfill({ contentType: 'application/javascript', body: SBJS }));
  // the real Supabase must never be reached from a test
  await pg.route(/\.supabase\.co\//, (r) => { pg.supabaseHits++; return r.abort(); });
  await pg.route(/cloudfront\.net|unsplash|higgsfield/, (r) => r.abort());
  const sess = opts.login ? gw.sessionFor(LOGINS[opts.login] || opts.login, opts.aal) : null;
  await pg.addInitScript(([key, s, station, lang, extra]) => {
    try {
      if (s && !sessionStorage.getItem('__seeded')) { localStorage.setItem(key, JSON.stringify(s)); sessionStorage.setItem('__seeded', '1'); }
      if (station && !localStorage.getItem('hg-pos-station')) localStorage.setItem('hg-pos-station', JSON.stringify(station));
      if (lang) localStorage.setItem('hg_lang', lang);
      Object.keys(extra || {}).forEach((k) => localStorage.setItem(k, extra[k]));
    } catch (e) {}
    window.print = function () {
      window.__printed = (window.__printed || 0) + 1;
      const r = document.getElementById('receipt'); window.__printedHTML = r ? r.innerHTML : document.body.innerHTML;
    };
  }, [STORAGE_KEY, sess, opts.station === undefined ? { name: 'Caja', main: true } : opts.station, opts.lang || 'es', opts.storage || {}]);
  return pg;
}

async function goto(pg, p) {
  await pg.goto(SITE + p, { waitUntil: 'domcontentloaded' });
}

/* waits until fn() (evaluated in Node) is truthy */
async function until(fn, ms, what) {
  const end = Date.now() + (ms || 8000);
  let last;
  while (Date.now() < end) {
    try { last = await fn(); if (last) return last; } catch (e) { last = e; }
    await new Promise((r) => setTimeout(r, 120));
  }
  throw new Error('timed out waiting for ' + (what || 'condition') + (last instanceof Error ? ': ' + last.message : ''));
}

/* before a test goes offline: the page's own requests answered. The POS checks the sign-in, its settings, the register
   and the people two or three times as it opens (once at load, once per sign-in event). A check the test cuts off by
   going offline first is a check without internet to the page, which does what it does offline: the Today window opens
   by itself (the register looks unopened), the people are not saved for offline use yet, or a late answer brings back
   a window the test has just closed (each seen with every answer delayed 0-400 ms, as on a slow machine; D-054, ported
   from PR #4's test-only part: GitHub's runner hit the Today window in 020 on 2026-11-02, D-064). */
async function settle(pg) {
  await pg.waitForLoadState('networkidle');
}

/* the day's register already opened (most POS tests start mid-day) */
function openRegister(floatCrc) {
  sql(`insert into public.register_days (business_date, opened_by, opened_by_name, float_crc)
       values (public.cr_today(), '${STAFF.ana}', 'Ana', ${floatCrc || 50000}) on conflict (business_date) do nothing`);
}

/* the POS with the menu loaded and the register open */
async function pos(browser, opts) {
  opts = Object.assign({ login: 'cafe', lang: 'en' }, opts || {});
  if (opts.register !== false) openRegister();
  const pg = await page(browser, opts);
  await goto(pg, '/pos');
  await pg.waitForSelector('.pbtn', { timeout: 15000 });
  return pg;
}

/* this page's sign-in registered as a till for discounts (migration 0038), the way a manager does it in Reloj de marcas ›
   Bitácora: the owner areas opened with a manager's PIN on this same sign-in (access_unlock), descuento_caja_registrar,
   and the device key kept as the POS keeps it (localStorage 'hg-disc-till', {login, key}). The owner areas are closed
   again at once (access_lock ends every unlock of this sign-in), so the page holds no unlock. Call it after the page has
   loaded (it reads the page's own session). Every spec that gives a discount registers its till first. */
async function registerTill(pg, opts) {
  opts = opts || {};
  const by = opts.by || 'ana';
  const read = () => pg.evaluate((k) => { try { return JSON.parse(localStorage.getItem(k) || 'null'); } catch (e) { return null; } }, STORAGE_KEY);
  await until(async () => { const s = await read(); return !!(s && s.access_token); }, 10000, 'the page signed in');
  const sess = await read();
  const api = 'http://127.0.0.1:' + (Number(process.env.E2E_SITE_PORT || 8090) + 1000) + '/rest/v1/rpc/';
  const call = async (name, args, unlock) => {
    const headers = { 'Content-Type': 'application/json', Authorization: 'Bearer ' + sess.access_token };
    if (unlock) headers['x-hg-unlock'] = unlock;
    const r = await fetch(api + name, { method: 'POST', headers, body: JSON.stringify(args || {}) });
    const t = await r.text();
    if (!r.ok) throw new Error(name + ' ' + r.status + ' ' + t);
    return t ? JSON.parse(t) : null;
  };
  const u = await call('access_unlock', { p_staff_id: STAFF[by], p_pin: PINS[by] });
  if (!u || !u.ok) throw new Error('access_unlock for the till: ' + JSON.stringify(u));
  let reg;
  try { reg = await call('descuento_caja_registrar', { p_station: opts.station || 'Caja' }, u.token); }
  finally { await call('access_lock', {}, u.token).catch(() => {}); }
  if (!reg || !reg.ok) throw new Error('descuento_caja_registrar: ' + JSON.stringify(reg));
  if (reg.key) await pg.evaluate((v) => localStorage.setItem('hg-disc-till', JSON.stringify(v)), { login: sess.user && sess.user.id, key: reg.key });
  return reg;
}

/* the tour guide courtesy switched on, as the test superuser (it ships off: owner's adjustment 4, A-13): the compliance
   confirmation its guard asks for, then the setting */
function guiaOn() {
  sql(`insert into public.compliance_confirmations (key, confirmed_by, reference) values ('courtesy_iva_confirmed', 'test', 'test') on conflict (key) do nothing;
       insert into public.settings (key, value) values ('pos_discount_guia', '"on"') on conflict (key) do update set value = excluded.value`);
}

/* one tap on a touch screen (touch events, not a mouse) and what the target saw of it: for the tap's pointerdown,
   mousedown, mouseup and click, whether the event reached the target and where the target's top was at that moment.
   D-068: a number pad that closed as the tap moved the focus away moved a button between the tap's press and its
   release, so its click went elsewhere. -> [{ t, on, top }] */
async function tapOnce(loc) {
  const h = await loc.elementHandle();
  await h.evaluate((b) => {
    const log = b.__hgTapLog = [];
    ['pointerdown', 'mousedown', 'mouseup', 'click'].forEach((t) => document.addEventListener(t, (e) => {
      log.push({ t, on: b === e.target || b.contains(e.target), top: Math.round(b.getBoundingClientRect().top) });
    }, { capture: true, once: true }));
  });
  await loc.tap();
  return h.evaluate((b) => b.__hgTapLog);
}
/* the tap of tapOnce() landed on its target, and the target did not move while it did */
function tapLanded(log, what) {
  const tops = log.map((x) => x.top);
  assert.ok(log.length === 4 && log.every((x) => x.on) && tops.every((y) => y === tops[0]),
    (what || 'the tap') + ' landed on its target, which stayed in place: ' + log.map((x) => x.t + (x.on ? '' : ' (elsewhere)') + ' @' + x.top).join(', '));
}

/* a cash payment opens the cash window (migration 0010): pay the exact amount */
async function cashExact(pg) {
  await pg.waitForSelector('#cashModal:not([hidden])', { timeout: 5000 });
  await pg.click('#cashExact');
}

module.exports = { page, goto, until, settle, sql, sqlJson, openRegister, pos, cashExact, registerTill, guiaOn, tapOnce, tapLanded, SITE, STAFF, PINS, LOGINS, ROOT };
