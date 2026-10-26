/* Canopy OS browser tests · helpers shared by the specs. */
'use strict';
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

/* Costa Rica's business day (UTC−6 all year), counted as pos.html (crTodayStr, crDay) and supabase/register.sql
   (cr_today, cr_day_start) count it. A spec builds the moments it seeds from it, never from the wall clock alone: run
   right after midnight, "15 minutes ago" is yesterday's business day, and the till sends what was added to or paid on
   a bill of another day as separate steps (D-060) */
function crToday(days) { return new Date(Date.now() - 6 * 3600000 + (days || 0) * 86400000).toISOString().slice(0, 10); }
function crDayStart(days) { return new Date(crToday(days) + 'T00:00:00-06:00'); }
/* `minutes` ago, but no earlier than the start of today's business day */
function earlierToday(minutes) { return new Date(Math.max(Date.now() - minutes * 60000, crDayStart().getTime())).toISOString(); }
/* yesterday's business day, `minutes` before midnight */
function lastNight(minutes) { return new Date(crDayStart().getTime() - minutes * 60000).toISOString(); }

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

/* the day's register already opened (most POS tests start mid-day) */
function openRegister(floatCrc) {
  sql(`insert into public.register_days (business_date, opened_by, opened_by_name, float_crc)
       values (public.cr_today(), '${STAFF.ana}', 'Ana', ${floatCrc || 50000}) on conflict (business_date) do nothing`);
}

/* The POS asks for today's register while the menu loads (loadRegister) and, on a main register, opens the Today
   window by itself when no day is open or a day from before midnight is still open (nudgeRegister). The answer can
   come after the products are drawn: a spec that looked for the window as soon as they showed could miss it, and the
   window then took the till's clicks (the runs of 2026-10-26 around midnight, D-060). This waits for that decision. */
async function registerLoaded(pg) {
  await until(() => pg.evaluate(() => REG !== null || !REG_SUPPORT || REG_CHECK_FAILED || !(STATION && STATION.main)
                                       || localStorage.getItem('hg-pos-reg-nudge') === todayKey()), 15000, 'the register to load');
}
/* ...and closes the Today window when the POS opened it */
async function registerSettled(pg) {
  await registerLoaded(pg);
  if (await pg.isVisible('#dayModal')) await pg.click('#dayClose');
}

/* the POS with the menu loaded and the register open, its Today window closed */
async function pos(browser, opts) {
  opts = Object.assign({ login: 'cafe', lang: 'en' }, opts || {});
  if (opts.register !== false) openRegister();
  const pg = await page(browser, opts);
  await goto(pg, '/pos');
  await pg.waitForSelector('.pbtn', { timeout: 15000 });
  await registerSettled(pg);
  return pg;
}

/* a cash payment opens the cash window (migration 0010): pay the exact amount */
async function cashExact(pg) {
  await pg.waitForSelector('#cashModal:not([hidden])', { timeout: 5000 });
  await pg.click('#cashExact');
}

module.exports = { page, goto, until, sql, sqlJson, openRegister, registerLoaded, registerSettled, pos, cashExact,
                   crToday, crDayStart, earlierToday, lastNight, SITE, STAFF, PINS, LOGINS, ROOT };
