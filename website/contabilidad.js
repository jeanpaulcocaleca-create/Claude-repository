/* Canopy OS · Contabilidad (the accounting page, redesign of 2026-10): one page for the owner with the phone code and the
   accountant. Everything it shows comes from the functions the books already have (migrations 0013–0033) plus the read
   functions of 0034/0035; nothing is typed twice and sales reach the books only through the day's entry (D-013).
   Sections: Overview, Expenses, Suppliers, Income, Purchases, Bank and cash, Reports, Books. English source text; lang.js
   shows it in Spanish. */
var db = window.supabase.createClient(HG_CONFIG.url, HG_CONFIG.key, window.HG_LOGIN ? HG_LOGIN.options(window.HG_ACCESS ? HG_ACCESS.options() : undefined) : undefined);
function $(id){ return document.getElementById(id); }
function fmt(n){ var v = Number(n) || 0; return (v < 0 ? '−' : '') + '₡' + Math.abs(Math.round(v * 100) / 100).toLocaleString('fr-FR', {minimumFractionDigits: 0, maximumFractionDigits: 2}); }
function fmtUsd(n){ var v = Number(n) || 0; return (v < 0 ? '−' : '') + '$' + Math.abs(v).toFixed(2); }
function pct(n){ return (n > 0 ? '+' : n < 0 ? '−' : '') + Math.abs(Math.round(n * 10) / 10).toLocaleString('fr-FR') + ' %'; }
function esc(s){ var e = document.createElement('span'); e.textContent = s == null ? '' : String(s); return e.innerHTML; }
function toast(t){ var e = $('toast'); e.textContent = t; e.classList.add('on'); clearTimeout(e._t); e._t = setTimeout(function(){ e.classList.remove('on'); }, 2800); }
function uuid(){
  if (window.crypto && crypto.randomUUID) return crypto.randomUUID();
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c){ var r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3 | 8)).toString(16); });
}
function today(){ var d = new Date(Date.now() - 6 * 3600000); return d.toISOString().slice(0, 10); }   /* Costa Rica (UTC−6), the business day */
function monthStart(d){ return d.slice(0, 8) + '01'; }
function monthEnd(d){ var x = new Date(d.slice(0, 7) + '-01T12:00:00Z'); x.setUTCMonth(x.getUTCMonth() + 1); x.setUTCDate(0); return x.toISOString().slice(0, 10); }
function addDays(d, n){ var x = new Date(d + 'T12:00:00Z'); x.setUTCDate(x.getUTCDate() + n); return x.toISOString().slice(0, 10); }
function addMonths(d, n){ var x = new Date(d.slice(0, 7) + '-01T12:00:00Z'); x.setUTCMonth(x.getUTCMonth() + n); return x.toISOString().slice(0, 10); }
function daysBetween(a, b){ return Math.round((new Date(b + 'T12:00:00Z') - new Date(a + 'T12:00:00Z')) / 86400000); }
var MONTHS_EN = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'], MONTHS_ES = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'set', 'oct', 'nov', 'dic'];
function isEs(){ return (window.HG_LANG || 'es') === 'es'; }
function mlabel(ym){ var m = +ym.slice(5, 7) - 1; return (isEs() ? MONTHS_ES : MONTHS_EN)[m] + ' ' + ym.slice(2, 4); }   /* "oct 26" */
function dlabel(d){ return d.slice(8, 10) + '/' + d.slice(5, 7); }   /* "25/10" */
/* a timestamp from the server, as the Costa Rican day (no summer time there) and as day + time; a plain date stays as it is */
function crMs(v){ var x = String(v == null ? '' : v); if (x.length <= 10 || x.indexOf('T') < 0) return NaN; if (!/[Zz]|[+-]\d\d:?\d\d$/.test(x)) x += 'Z'; return new Date(x).getTime() - 6 * 3600000; }
function crDate(v){ var ms = crMs(v); return isNaN(ms) ? String(v == null ? '' : v).slice(0, 10) : new Date(ms).toISOString().slice(0, 10); }
function crTime(v){ var ms = crMs(v); return isNaN(ms) ? String(v == null ? '' : v).slice(0, 16).replace('T', ' ') : new Date(ms).toISOString().slice(0, 16).replace('T', ' '); }
function num(v, dec){ return Number(v || 0).toLocaleString('fr-FR', {maximumFractionDigits: dec == null ? 2 : dec}); }
function csvSafe(s){ return /^[=+\-@\t\r]/.test(s) && !/^-?\d+([.,]\d+)?$/.test(s) ? "'" + s : s; }   /* a cell never starts a spreadsheet formula */
function csvText(rows){ return '﻿' + rows.map(function(r){ return r.map(function(c){ var t = csvSafe(c == null ? '' : String(c)); return /[",\n;]/.test(t) ? '"' + t.replace(/"/g, '""') + '"' : t; }).join(','); }).join('\r\n'); }
function download(name, rows){
  var a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([csvText(rows)], {type: 'text/csv;charset=utf-8'})); a.download = name; a.click();
  setTimeout(function(){ URL.revokeObjectURL(a.href); }, 2000);
}
function sum(arr, f){ return (arr || []).reduce(function(t, x){ return t + Number(f ? f(x) : x) || 0; }, 0); }
function by(arr, key){ var m = {}; (arr || []).forEach(function(x){ m[x[key]] = x; }); return m; }
function debounce(fn, ms){ var t; return function(){ var a = arguments, s = this; clearTimeout(t); t = setTimeout(function(){ fn.apply(s, a); }, ms); }; }

/* what the server's refusals mean, in words */
var ERR = {not_allowed: 'Only the owner (with the phone code) and the accountant can do this.', unbalanced: 'Debits and credits must be equal.',
  period_closed: 'That month is closed. Use a date in an open month.', unknown_account: 'One of the accounts does not exist or is not active.',
  already_reversed: 'That entry was already reversed.', is_reversal: 'A reversal is not reversed again: post a new entry.', locked: 'That month is locked.',
  earlier_open: 'Close the earlier months first.', later_locked: 'A later month is locked.', bad_value: 'Check the values.', type_in_use: 'This account has entries: its type cannot change.',
  system_account: 'The automatic entries use this account: it stays active.', duplicate_invoice: 'That invoice of this supplier was already entered.',
  bad_account: 'Pick an expense account.', future_date: 'The date cannot be in the future.', needs_confirmation: 'Record the approval first.',
  owner_only: 'Only the owner can do this.', missing_reference: 'Write who approved it and the document.', bad_range: 'Pick at most three months.',
  missing_reason: 'Write the reason.', already_voided: 'Already voided.', no_vendor: 'Pick the supplier.', bad_request: 'Could not save. Refresh the page and try again.',
  bad_receipts: 'One of those deliveries is of another supplier or already has its invoice. Refresh and try again.',
  more_than_owed: 'That is more than is owed.', bad_payout: 'That payout is not available: refresh and pick it again.',
  not_open: 'That was already done. Refresh the page.', no_match: 'The amounts are not the same.', already_matched: 'That entry is already matched to another movement.',
  parts_differ: 'The parts must add up to the bank\'s amount.', bad_rows: 'Some rows could not be read: check the date format and the columns.',
  usd_not_supported: 'Dollar accounts come later: their movements must be valued in colones first.', not_found: 'Not found. Refresh the page.',
  unknown_setting: 'That setting does not exist.', use_document: 'This entry came from a document (expense, supplier, bank, payroll, day): undo it from that document.',
  cash_not_asset: 'Only an asset account can be cash or bank.', has_payments: 'It has payments standing: void the payments first.',
  needs_account: 'Pick the category of this expense.', needs_paid_from: 'Say where the money came from.', needs_iva: 'Write the IVA (0 if there is none).',
  duplicate_name: 'A supplier with that name already exists.', missing_name: 'Write the supplier\'s name.', bad_schedule: 'That recurring bill no longer exists: refresh the page.',
  not_credit: 'This expense was not on credit: there is nothing to pay.', bad_path: 'Could not save the file.', already_attached: 'This expense already has its file.',
  unknown_key: 'That line does not exist.', no_account: 'Sign in again.', missing_migration: 'The accounting needs a database update: apply the pending migrations (docs/MIGRACIONES.md).'};
var GUARD_ERR = {payroll_cr_rules: 'Record the confirmation "payroll_cr_rules" in Home → Settings first.'};
function errText(r){
  if (r && r.error && /Could not find the function|schema cache/i.test(r.error.message || '')) return ERR.missing_migration;
  if (r && r.error && /Failed to fetch|NetworkError|Load failed|network/i.test(r.error.message || '')) return 'No connection. Check the Wi-Fi and try again.';
  if (r && r.error) return 'Could not save. Check the connection and try again.';
  var d = (r && r.data) || {};
  if (d.error === 'needs_confirmation' && typeof d.guard === 'string' && GUARD_ERR[d.guard]) return GUARD_ERR[d.guard];
  return ERR[d.error] || 'Could not save. Try again.';
}
/* one call to the server; a refusal or a network error is thrown as the whole answer, so a screen can show errText(e) */
async function rpc(name, args){
  var r = await db.rpc(name, args || {});
  if (r.error || !r.data || r.data.ok === false) throw r;
  return r.data;
}
/* answers kept for a moment: the sections share the same reads, and the period buttons must not hit the server twice */
var CACHE = {};
function cached(key, ms, fn){
  var c = CACHE[key];
  if (c && Date.now() - c.at < ms) return c.p;
  var p = fn().catch(function(e){ delete CACHE[key]; throw e; });
  CACHE[key] = {at: Date.now(), p: p};
  return p;
}
function forget(prefix){ Object.keys(CACHE).forEach(function(k){ if (!prefix || k.indexOf(prefix) === 0) delete CACHE[k]; }); }
/* a long range is asked in pieces the functions accept (92, 366 or 400 days) */
function chunks(from, to, max){
  var out = [], a = from;
  while (a <= to){ var b = addDays(a, max - 1); if (b > to) b = to; out.push([a, b]); a = addDays(b, 1); }
  return out;
}

/* ---------- sign in: the owner (phone code) or the accountant; the same door as accounting.html ---------- */
var KIND = null, OV = null, BUSY = 0, RECEIPTS = false;
/* receipt photos and files from this page: an owner's switch (Home → Settings · expense_receipt_photos, migration 0035), off until the
   nightly copy of the private files is verified (E-17). Opening a receipt that already exists is always possible. */
async function receiptsOn(){ try { var r = await db.rpc('setting', {p_key: 'expense_receipt_photos'}); return !r.error && r.data === true; } catch (e){ return false; } }
var idleTimer = null;
function armIdle(){
  clearTimeout(idleTimer);
  if (!/^(owner|accountant)/.test(KIND || '')) return;
  idleTimer = setTimeout(async function(){ await db.auth.signOut({scope: 'local'}); location.reload(); }, 30 * 60000);
}
['pointerdown', 'keydown', 'touchstart', 'scroll'].forEach(function(ev){ document.addEventListener(ev, armIdle, {passive: true}); });
async function codeNeeded(){
  try { var r = await db.auth.mfa.getAuthenticatorAssuranceLevel(); return !r.error && !!r.data && r.data.nextLevel === 'aal2' && r.data.currentLevel !== 'aal2'; }
  catch (e){ return false; }
}
async function refreshAuth(){
  var s = await db.auth.getSession(), authed = !!(s.data && s.data.session);
  var needCode = authed && await codeNeeded();
  $('loginView').hidden = authed && !needCode; $('loginForm').hidden = needCode; $('codeForm').hidden = !needCode;
  $('appView').hidden = true; $('noView').hidden = true;
  if (needCode){ $('codeIn').focus(); return; }
  if (!authed) return;
  var k = await db.rpc('account_kind'); KIND = k.error ? null : k.data;
  armIdle();
  var r = await db.rpc('acct_overview');
  if (r.error || !r.data || !r.data.ok){
    var needs = KIND === 'accountant_needs_code' || KIND === 'owner' || KIND === 'owner_needs_code';
    $('noWhy').textContent = r.error && /acct_overview|Could not find/i.test(r.error.message || '') ? ERR.missing_migration
      : needs ? 'The books open only with the code from your phone. Turn it on once; then every sign-in asks for the code.'
      : 'This page is for the owner (with the phone code) and the accountant.';
    $('enrollWrap').hidden = !(needs && !r.error);
    $('noView').hidden = false; return;
  }
  OV = r.data; forget();
  RECEIPTS = await receiptsOn();
  $('appView').hidden = false;
  $('ownerLinks').hidden = KIND !== 'owner';
  $('whoSub').textContent = KIND === 'accountant' ? 'Accountant' : 'Owner · with the code';
  $('whoIni').textContent = KIND === 'accountant' ? 'C' : 'D';
  go((location.hash || '#resumen').slice(1), true);
}
$('loginForm').addEventListener('submit', async function(e){ e.preventDefault(); var res = await HG_LOGIN.signIn(db); if (res.ok) refreshAuth(); });
$('codeForm').addEventListener('submit', async function(e){
  e.preventDefault();
  var f = await db.auth.mfa.listFactors(), t = f.data && f.data.totp && f.data.totp[0];
  var r = t ? await db.auth.mfa.challengeAndVerify({factorId: t.id, code: $('codeIn').value.trim()}) : {error: {}};
  $('codeIn').value = '';
  if (r.error){ $('codeErr').textContent = 'That code did not work. Codes change every 30 seconds, try the newest one.'; return; }
  refreshAuth();
});
var enrollId = null;
$('enrollStart').addEventListener('click', async function(){
  $('enrollErr').textContent = '';
  /* each time the code is typed, Supabase signs out every other session of this login without it: never on the café tablets' login */
  if (!confirm('Only on your own phone and your own login. Typing this code signs out every other device that uses this login, including café tablets. Continue?')) return;
  var f = await db.auth.mfa.listFactors(), all = (f.data && f.data.all) || [];
  for (var i = 0; i < all.length; i++){ if (all[i].factor_type === 'totp' && all[i].status !== 'verified') await db.auth.mfa.unenroll({factorId: all[i].id}); }
  var e = await db.auth.mfa.enroll({factorType: 'totp', friendlyName: 'Phone'});
  if (e.error || !e.data || !e.data.totp){ $('enrollErr').textContent = 'Could not start the phone code. Ask the owner to check that Supabase → Authentication → Multi-Factor → TOTP is on.'; return; }
  enrollId = e.data.id; $('enrollQr').src = e.data.totp.qr_code; $('enrollSecret').textContent = e.data.totp.secret;
  $('enrollBox').hidden = false; $('enrollStart').hidden = true; $('enrollCode').focus();
});
$('enrollForm').addEventListener('submit', async function(ev){
  ev.preventDefault();
  if (!enrollId) return;
  var r = await db.auth.mfa.challengeAndVerify({factorId: enrollId, code: $('enrollCode').value.trim()});
  $('enrollCode').value = '';
  if (r.error){ $('enrollErr').textContent = 'That code did not match. Wait for the next code and try again.'; return; }
  enrollId = null; $('enrollBox').hidden = true; $('enrollStart').hidden = false; refreshAuth();
});
['outBtn', 'noOut'].forEach(function(id){ $(id).addEventListener('click', async function(){ await db.auth.signOut({scope: 'local'}); location.reload(); }); });
db.auth.onAuthStateChange(function(ev){ if (ev === 'SIGNED_OUT') refreshAuth(); });
/* a tablet never reloads for a new version while a drawer is open or something is being saved (version.js) */
window.HG_SAFE_TO_RELOAD = function(){ return !$('drawer').classList.contains('open') && BUSY === 0; };
async function reloadOverview(){ var r = await db.rpc('acct_overview'); if (!r.error && r.data && r.data.ok){ OV = r.data; } return OV; }
function accountName(code){ var a = ((OV && OV.accounts) || []).filter(function(x){ return x.code === code; })[0]; return a ? a.name : ''; }
function mapped(key, fallback){ var m = ((OV && OV.mappings) || []).filter(function(x){ return x.key === key; })[0]; return (m && m.account) || fallback; }
function expenseAccounts(){ return ((OV && OV.accounts) || []).filter(function(a){ return a.active && a.type === 'expense'; }); }

/* ---------- the period: this month, last month, three months, the year; always the previous one too ---------- */
var PERIOD = 'month';
function range(){
  var t = today(), from, to, pfrom, pto;
  if (PERIOD === 'month'){ from = monthStart(t); to = t; pfrom = addMonths(from, -1); pto = monthEnd(pfrom); }
  else if (PERIOD === 'last'){ from = addMonths(monthStart(t), -1); to = monthEnd(from); pfrom = addMonths(from, -1); pto = monthEnd(pfrom); }
  else if (PERIOD === 'quarter'){ from = addMonths(monthStart(t), -2); to = t; pfrom = addMonths(from, -3); pto = addDays(from, -1); }
  else { from = t.slice(0, 4) + '-01-01'; to = t; pfrom = (t.slice(0, 4) - 1) + '-01-01'; pto = (t.slice(0, 4) - 1) + '-12-31'; }
  return {from: from, to: to, pfrom: pfrom, pto: pto, key: PERIOD + ':' + from + ':' + to};
}
function rangeLabel(r){ return r.from + ' → ' + r.to; }
document.querySelectorAll('#period button').forEach(function(b){ b.addEventListener('click', function(){ PERIOD = b.dataset.p; document.querySelectorAll('#period button').forEach(function(x){ x.setAttribute('aria-pressed', String(x === b)); }); Object.keys(TBL).forEach(function(k){ if (TBL[k].dated){ var r = range(); TBL[k].from = r.from; TBL[k].to = r.to; TBL[k].touched = false; TBL[k].page = 1; } }); REP_RANGE = null; render(); }); });

/* ---------- the drawer: every detail and every form opens here ---------- */
function openDrawer(title, body, foot){
  $('drawerTitle').textContent = title; $('drawerBody').innerHTML = body; $('drawerFoot').innerHTML = foot || '';
  $('drawer').classList.add('open'); $('drawer').setAttribute('aria-hidden', 'false'); $('scrim').classList.add('on');
  $('drawerBody').querySelectorAll('a[href^="#"]').forEach(function(a){ a.addEventListener('click', function(){ closeDrawer(); }); });
  HG_CHARTS.mount($('drawerBody'));
  var first = $('drawerBody').querySelector('input:not([type=hidden]):not([type=file]),select,textarea');
  if (first && !first.disabled) { try { first.focus({preventScroll: true}); } catch (e) {} } else $('drawerClose').focus();
}
function closeDrawer(){ $('drawer').classList.remove('open'); $('drawer').setAttribute('aria-hidden', 'true'); $('scrim').classList.remove('on'); $('side').classList.remove('open'); document.querySelectorAll('tbody tr[aria-selected]').forEach(function(r){ r.removeAttribute('aria-selected'); }); }
$('drawerClose').addEventListener('click', closeDrawer);
$('scrim').addEventListener('click', closeDrawer);
document.addEventListener('keydown', function(e){ if (e.key === 'Escape') closeDrawer(); });
$('menuBtn').addEventListener('click', function(){ var open = $('side').classList.toggle('open'); $('menuBtn').setAttribute('aria-expanded', String(open)); if (!$('drawer').classList.contains('open')) $('scrim').classList.toggle('on', open); });
/* a button in a drawer footer that saves: disabled while it runs; the error goes to the footer */
function footErr(msg){ var e = $('drawerFoot').querySelector('.err'); if (!e){ e = document.createElement('p'); e.className = 'err'; $('drawerFoot').insertBefore(e, $('drawerFoot').firstChild); } e.textContent = msg || ''; }
async function busy(btn, fn){
  if (btn) btn.disabled = true; BUSY++;
  try { return await fn(); }
  finally { BUSY--; if (btn) btn.disabled = false; }
}
function linesTable(lines){
  var d = sum(lines, function(l){ return l.debit; }), c = sum(lines, function(l){ return l.credit; });
  return '<div class="tbox"><table class="narrow"><thead><tr><th>Account</th><th class="num">Debit</th><th class="num">Credit</th></tr></thead><tbody>' +
    (lines || []).map(function(l){ return '<tr><td>' + esc(l.account + ' · ' + (l.name || accountName(l.account))) + (l.memo ? '<span class="sub">' + esc(l.memo) + '</span>' : '') + '</td><td class="num mono">' + (Number(l.debit) ? fmt(l.debit) : '') + '</td><td class="num mono">' + (Number(l.credit) ? fmt(l.credit) : '') + '</td></tr>'; }).join('') +
    '</tbody><tfoot><tr><td>Total ' + (Math.abs(d - c) < 0.005 ? '✓' : '✗') + '</td><td class="num mono">' + fmt(d) + '</td><td class="num mono">' + fmt(c) + '</td></tr></tfoot></table></div>';
}
function pill(kind, text){ return '<span class="pill ' + kind + '">' + esc(text) + '</span>'; }
function tag(kind, text){ return '<span class="tag ' + (kind || '') + '">' + esc(text) + '</span>'; }
var STATE_TAG = {estimate: ['est', 'estimate'], final: ['final', 'closed, from the register'], books: ['final', 'in the books'], empty: ['', 'no data'], docs: ['', 'from the documents'], register: ['', 'from the register'], draft: ['est', 'draft'], bank: ['', 'from the bank']};
function stateTag(k){ var s = STATE_TAG[k] || ['', k]; return tag(s[0], s[1]); }
var PREV_ACTIVE = true;   /* set per view: did the previous period record anything at all? */
function delta(cur, prev, inverse){
  if (prev == null || !PREV_ACTIVE) return '<span>no previous period</span>';
  if (!Number(prev)) return '<span>' + (Number(cur) ? 'from 0' : 'both 0') + '</span><span>vs. previous period</span>';
  var d = ((Number(cur) - Number(prev)) / Math.abs(Number(prev))) * 100;
  return '<span class="' + ((d >= 0) !== !!inverse ? 'up' : 'down') + '">' + pct(d) + '</span><span>vs. previous period</span>';
}
function kpi(label, value, cur, prev, state, extra, inverse){ return '<div class="kpi"><div class="l">' + esc(label) + '</div><div class="v">' + value + '</div><div class="d">' + (prev !== undefined ? delta(cur, prev, inverse) : '') + (state ? stateTag(state) : '') + (extra || '') + '</div></div>'; }

/* ---------- the table: instant search, filters, sortable columns, pages, a detail per row, CSV ----------
   opts: id, rows, columns [{key, label, num, nw, sort, sortVal, text, render}], filters [{key, label, options [[v, label]]}],
   dateKey, defaultSort, pageSize, search, csv (name → rows), foot(rows) → cells, onRow(row), onAct(name, row), after(host, rows) */
var TBL = {};
/* the range a dated table loads: the period, widened to the dates typed in the table (so «Desde» last month shows last month) */
function tableRange(id, r){ var st = TBL[id]; if (!st || !st.touched) return {from: r.from, to: r.to}; return {from: st.from && st.from < r.from ? st.from : r.from, to: st.to && st.to > r.to ? st.to : r.to}; }
function table(opts){
  var st = TBL[opts.id] || (TBL[opts.id] = {q: '', f: {}, sort: opts.defaultSort || null, dir: -1, page: 1, size: opts.pageSize || 10, from: '', to: '', dated: !!opts.dated});
  if (opts.dated && !st.from && !st.to && !st.touched){ var r0 = range(); st.from = r0.from; st.to = r0.to; }
  var host = document.createElement('div'); host.className = 'tbl'; host.id = 'tbl-' + opts.id;
  var cols = opts.columns;
  function value(c, r){ return c.text ? c.text(r) : r[c.key]; }
  function draw(){
    var rows = opts.rows.slice();
    if (st.q){ var q = st.q.toLowerCase(); rows = rows.filter(function(r){ return cols.some(function(c){ var v = value(c, r); return String(v == null ? '' : v).toLowerCase().indexOf(q) >= 0; }); }); }
    Object.keys(st.f).forEach(function(k){ if (st.f[k] !== ''){ var f = (opts.filters || []).filter(function(x){ return x.key === k; })[0]; rows = rows.filter(function(r){ var v = f && f.value ? f.value(r) : r[k]; return String(v) === st.f[k]; }); } });
    if (opts.dateKey && st.from) rows = rows.filter(function(r){ return crDate(r[opts.dateKey]) >= st.from; });
    if (opts.dateKey && st.to) rows = rows.filter(function(r){ return crDate(r[opts.dateKey]) <= st.to; });
    if (st.sort){ var c = cols.filter(function(x){ return x.key === st.sort; })[0]; if (c) rows.sort(function(a, b){ var va = c.sortVal ? c.sortVal(a) : a[st.sort], vb = c.sortVal ? c.sortVal(b) : b[st.sort]; if (va == null) va = ''; if (vb == null) vb = ''; return (va > vb ? 1 : va < vb ? -1 : 0) * st.dir; }); }
    var total = rows.length, pages = Math.max(1, Math.ceil(total / st.size)); if (st.page > pages) st.page = pages;
    var slice = rows.slice((st.page - 1) * st.size, st.page * st.size);
    var h = '<div class="tools noprint">';
    if (opts.search !== false) h += '<div class="grow search"><label for="q-' + opts.id + '">Search</label><svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="11" cy="11" r="7"/><path d="M20 20l-4-4"/></svg><input id="q-' + opts.id + '" data-q placeholder="Search…" value="' + esc(st.q) + '"></div>';
    (opts.filters || []).forEach(function(f){ h += '<div><label for="f-' + opts.id + '-' + f.key + '">' + esc(f.label) + '</label><select id="f-' + opts.id + '-' + f.key + '" data-f="' + f.key + '"><option value="">All</option>' + f.options.map(function(o){ return '<option value="' + esc(o[0]) + '"' + (st.f[f.key] === String(o[0]) ? ' selected' : '') + '>' + esc(o[1]) + '</option>'; }).join('') + '</select></div>'; });
    if (opts.dateKey) h += '<div><label for="from-' + opts.id + '">From</label><input type="date" id="from-' + opts.id + '" data-from value="' + st.from + '"></div><div><label for="to-' + opts.id + '">To</label><input type="date" id="to-' + opts.id + '" data-to value="' + st.to + '"></div>';
    h += '<div><button type="button" class="ghost small" data-clear>Clear filters</button></div>' + (opts.csv ? '<div><button type="button" class="ghost small" data-csv>Download CSV</button></div>' : '') + (opts.toolsExtra || '') + '</div>';
    h += '<div class="tbox"><table><thead><tr>' + cols.map(function(c){ return '<th class="' + (c.num ? 'num ' : '') + (c.sort !== false ? 'sortable' : '') + '"' + (c.sort !== false ? ' data-sort="' + c.key + '" aria-sort="' + (st.sort === c.key ? (st.dir > 0 ? 'ascending' : 'descending') : 'none') + '"' : '') + '>' + c.label + (st.sort === c.key ? '<span class="arr">' + (st.dir > 0 ? '▲' : '▼') + '</span>' : '') + '</th>'; }).join('') + '</tr></thead><tbody>';
    if (!slice.length) h += '<tr><td colspan="' + cols.length + '"><div class="empty">' + (opts.empty || 'Nothing to show with these filters.') + '</div></td></tr>';
    slice.forEach(function(r, i){ h += '<tr class="' + (opts.onRow ? 'row' : '') + '" data-i="' + i + '"' + (opts.onRow ? ' tabindex="0"' : '') + '>' + cols.map(function(c){ return '<td class="' + (c.num ? 'num ' : '') + (c.nw ? 'nw' : '') + '">' + (c.render ? c.render(r) : esc(r[c.key])) + '</td>'; }).join('') + '</tr>'; });
    h += '</tbody>' + (opts.foot ? '<tfoot><tr>' + opts.foot(rows).map(function(x, i){ return '<td class="' + (cols[i] && cols[i].num ? 'num' : '') + '">' + x + '</td>'; }).join('') + '</tr></tfoot>' : '') + '</table></div>';
    h += '<div class="pager noprint"><span><span class="mono">' + total + '</span> rows</span><div class="btns"><select data-size aria-label="Rows per page">' + [10, 25, 50, 100].map(function(n){ return '<option' + (st.size === n ? ' selected' : '') + '>' + n + '</option>'; }).join('') + '</select><button type="button" class="ghost small" data-pg="-1" ' + (st.page <= 1 ? 'disabled' : '') + ' aria-label="Previous page">‹</button><span class="mono">' + st.page + ' / ' + pages + '</span><button type="button" class="ghost small" data-pg="1" ' + (st.page >= pages ? 'disabled' : '') + ' aria-label="Next page">›</button></div></div>';
    host.innerHTML = h;
    var qi = host.querySelector('[data-q]'); if (qi) qi.addEventListener('input', function(e){ st.q = e.target.value; st.page = 1; var pos = e.target.selectionStart; draw(); var q = host.querySelector('[data-q]'); q.focus(); try { q.setSelectionRange(pos, pos); } catch (x) {} });
    host.querySelectorAll('[data-f]').forEach(function(s){ s.addEventListener('change', function(e){ st.f[e.target.dataset.f] = e.target.value; st.page = 1; draw(); }); });
    var r1 = range();
    var fr = host.querySelector('[data-from]'); if (fr) fr.addEventListener('change', function(e){ st.from = e.target.value; st.touched = true; st.page = 1; if (opts.dated && st.from && st.from < r1.from) render(); else draw(); });
    var to = host.querySelector('[data-to]'); if (to) to.addEventListener('change', function(e){ st.to = e.target.value; st.touched = true; st.page = 1; if (opts.dated && st.to && st.to > r1.to) render(); else draw(); });
    host.querySelector('[data-clear]').addEventListener('click', function(){ st.q = ''; st.f = {}; st.from = ''; st.to = ''; st.touched = false; st.page = 1; if (opts.dated) render(); else draw(); });
    var cb = host.querySelector('[data-csv]'); if (cb) cb.addEventListener('click', function(){ var out = opts.csv(rows); if (out) download(out[0], out[1]); });
    host.querySelectorAll('[data-sort]').forEach(function(th){ th.addEventListener('click', function(){ var k = th.dataset.sort; if (st.sort === k) st.dir = -st.dir; else { st.sort = k; st.dir = -1; } draw(); }); });
    host.querySelector('[data-size]').addEventListener('change', function(e){ st.size = +e.target.value; st.page = 1; draw(); });
    host.querySelectorAll('[data-pg]').forEach(function(b){ b.addEventListener('click', function(){ st.page += +b.dataset.pg; draw(); }); });
    host.querySelectorAll('tbody tr[data-i]').forEach(function(tr){
      var open = function(){ host.querySelectorAll('tr[aria-selected]').forEach(function(x){ x.removeAttribute('aria-selected'); }); tr.setAttribute('aria-selected', 'true'); if (opts.onRow) opts.onRow(slice[+tr.dataset.i]); };
      tr.addEventListener('click', function(e){ if (e.target.closest('button') || e.target.closest('a') || e.target.closest('input,select')) return; open(); });
      tr.addEventListener('keydown', function(e){ if (e.key === 'Enter' && e.target === tr) open(); });
    });
    host.querySelectorAll('[data-act]').forEach(function(b){ b.addEventListener('click', function(e){ e.stopPropagation(); var r = slice[+b.closest('tr').dataset.i]; if (opts.onAct) opts.onAct(b.dataset.act, r, b); }); });
    if (opts.after) opts.after(host, rows);
  }
  draw(); return host;
}

/* ---------- the router: one section at a time, the section in the address (#gastos), charts drawn after ---------- */
var VIEW = {}, current = 'resumen', renderSeq = 0;
var TITLES = {resumen: ['Overview', 'What came in, what went out and what is pending'], gastos: ['Expenses', 'Each expense with its receipt and its IVA'],
  proveedores: ['Suppliers', 'One list, shared with Inventory'], ingresos: ['Income', 'Sales come from the register close. Nothing is typed here.'],
  compras: ['Purchases', 'Orders, deliveries and invoices, tied to Inventory'], banco: ['Bank and cash', 'Cash by day and the bank statement reconciled'],
  reportes: ['Reports', 'To decide, not only to file'], contabilidad: ['Books', 'Journal, accounts, periods and what is regulated']};
function go(v, keep){
  if (!TITLES[v]) v = 'resumen';
  current = v; closeDrawer();
  if (!keep && (location.hash || '#resumen').slice(1) !== v) location.hash = v;
  render(); window.scrollTo({top: 0});
}
async function render(){
  if (!OV) return;
  var v = current, mine = ++renderSeq, box = $('view');
  document.querySelectorAll('#nav a').forEach(function(a){ if (a.dataset.view === v) a.setAttribute('aria-current', 'page'); else a.removeAttribute('aria-current'); });
  $('title').textContent = TITLES[v][0]; $('subtitle').textContent = TITLES[v][1];
  box.innerHTML = '<div class="loading">Loading…</div>';
  try {
    var out = await VIEW[v]();
    if (mine !== renderSeq) return;
    box.replaceChildren(); if (typeof out === 'string') box.innerHTML = out; else box.appendChild(out);
    HG_CHARTS.mount(box);
  } catch (e){
    if (mine !== renderSeq) return;
    box.innerHTML = '<div class="banner bad"><b>Could not load this section.</b><span class="hint">' + esc(errText(e)) + '</span><span class="sp"></span><button type="button" class="ghost small" id="retryBtn">Try again</button></div>';
    $('retryBtn').addEventListener('click', function(){ forget(); render(); });
    if (window.console) console.error(e);
  }
}
window.addEventListener('hashchange', function(){ if (OV) go((location.hash || '#resumen').slice(1), true); });
document.addEventListener('hg-lang', function(){ if (OV) render(); });   /* chart labels and month names follow the language */
HG_CHARTS.money(fmt);

/* ---------- reads: each one asks the server once per period and keeps the answer for a moment ---------- */
var TTL = 60000, MIG = {v34: true, v35: true};
function missing(e){ return !!(e && e.error && /Could not find the function|schema cache/i.test(e.error.message || '')); }
async function merged(key, from, to, max, name, args, field){
  return cached(key + ':' + from + ':' + to, TTL, async function(){
    var out = [];
    for (var i = 0, cs = chunks(from, to, max); i < cs.length; i++){ var d = await rpc(name, Object.assign({p_from: cs[i][0], p_to: cs[i][1]}, args || {})); out = out.concat(d[field] || []); }
    return out;
  });
}
function loadCompare(r){ return cached('compare:' + r.from + r.to, TTL, function(){ return rpc('period_compare', {p_from: r.from, p_to: r.to}); }); }
function loadTrends(){ return cached('trends', TTL, function(){ return rpc('trends_monthly', {p_months: 12}); }); }
function loadDashboard(){ return cached('dash', 20000, function(){ return rpc('dashboard_today'); }); }
function loadCashPosition(){ return cached('cashpos', TTL, function(){ return rpc('cash_position'); }); }
function loadAP(){ return cached('ap', TTL, function(){ return rpc('ap_aging', {p_as_of: null}); }); }
function loadVendors(){ return cached('vendors', TTL, function(){ return rpc('vendors_list'); }); }
function loadPayouts(){ return cached('payouts', TTL, async function(){ return (await rpc('cash_payouts', {p_from: null, p_to: null})).payouts; }); }
function loadDue(){ return cached('due', TTL, async function(){ try { return (await rpc('expense_due', {p_days: 7})).due; } catch (e){ if (missing(e)){ MIG.v35 = false; return []; } throw e; } }); }
function loadSchedules(){ return cached('schedules', TTL, async function(){ try { return (await rpc('expense_schedules_list')).schedules; } catch (e){ if (missing(e)){ MIG.v35 = false; return []; } throw e; } }); }
function loadExpenses(from, to){ return merged('expenses', from, to, 400, 'expense_list', null, 'expenses'); }
function loadSalesByMethod(from, to){ return merged('sbm', from, to, 366, 'sales_by_method', null, 'days'); }
function loadCashDays(from, to){ return merged('cash', from, to, 92, 'cash_reconciliation', null, 'days'); }
function loadPatterns(from, to){ return merged('patterns', from, to, 366, 'sales_patterns', null, 'days'); }
function loadPurchases(from, to){ return merged('purchases', from, to, 400, 'purchases_list', {p_vendor_id: null}, 'orders'); }
function loadJournal(from, to, acct){ return merged('journal:' + (acct || ''), from, to, 400, 'acct_journal', {p_account: acct || null}, 'entries'); }
function loadAudit(from, to){ return merged('audit', from, to, 400, 'acct_audit', null, 'rows'); }
function loadEdocs(from, to){ return cached('edocs:' + from + to, TTL, function(){ return rpc('einvoice_list', {p_from: from, p_to: to}); }); }
function loadVendorHistory(id, from, to){ return cached('vh:' + id + from + to, TTL, function(){ return rpc('vendor_history', {p_vendor_id: id, p_from: from, p_to: to}); }); }
function loadBank(id, from, to){ return cached('bank:' + (id || '') + from + to, TTL, function(){ return rpc('bank_overview', {p_account_id: id || null, p_from: from, p_to: to}); }); }
/* the IVA draft of a long range: the function takes 92 days at a time; the pieces add up */
function loadIva(from, to){
  return cached('iva:' + from + to, TTL, async function(){
    var out = null;
    for (var i = 0, cs = chunks(from, to, 92); i < cs.length; i++){
      var d = await rpc('iva_report', {p_from: cs[i][0], p_to: cs[i][1]});
      if (!out){ out = d; continue; }
      d.sales.by_rate.forEach(function(x){ var y = out.sales.by_rate.filter(function(z){ return z.code === x.code; })[0]; if (y){ y.lines = +y.lines + +x.lines; y.gross_crc = +y.gross_crc + +x.gross_crc; y.net_crc = +y.net_crc + +x.net_crc; y.tax_crc = +y.tax_crc + +x.tax_crc; } else out.sales.by_rate.push(x); });
      out.sales.refunds_tax_crc = +out.sales.refunds_tax_crc + +d.sales.refunds_tax_crc; out.sales.tax_crc = +out.sales.tax_crc + +d.sales.tax_crc;
      out.sales.without_tax_detail.orders = +out.sales.without_tax_detail.orders + +d.sales.without_tax_detail.orders; out.sales.without_tax_detail.total_crc = +out.sales.without_tax_detail.total_crc + +d.sales.without_tax_detail.total_crc;
      out.credits.documents = out.credits.documents.concat(d.credits.documents); out.credits.iva_crc = +out.credits.iva_crc + +d.credits.iva_crc;
      out.net_crc = +out.net_crc + +d.net_crc; out.ledger.iva_out_crc = +out.ledger.iva_out_crc + +d.ledger.iva_out_crc; out.ledger.iva_in_crc = +out.ledger.iva_in_crc + +d.ledger.iva_in_crc;
      out.ledger.pending_days = +out.ledger.pending_days + +d.ledger.pending_days;
    }
    return out;
  });
}
/* the state of a range from its months: an open day makes it an estimate; every closed day posted makes it "in the books" */
function rangeState(cmp){
  var ms = (cmp.months || []).map(function(m){ return m.state; }).filter(function(s){ return s !== 'empty'; });
  if (!ms.length) return 'empty';
  if (ms.indexOf('estimate') >= 0) return 'estimate';
  if (ms.every(function(s){ return s === 'books'; })) return 'books';
  return 'final';
}
function emptyMonths(cmp){ return (cmp.months || []).filter(function(m){ return m.state === 'empty'; }).map(function(m){ return mlabel(m.month); }); }
function costs(f){ return Number(f.cogs) + Number(f.waste) + Number(f.expenses); }
/* supplier invoices that were a service (an expense account, no delivery): they count as expenses of their account, like in _period_figures */
function serviceInvoices(docs){ return (docs || []).filter(function(x){ return x.source !== 'expense' && x.account && !x.voided; }); }
function methodTotals(days){ var t = {cash_crc: 0, cash_usd: 0, card: 0, sinpe: 0, other: 0}; days.forEach(function(d){ Object.keys(t).forEach(function(k){ t[k] += Number(d[k]) || 0; }); }); return t; }
function isPending(day){ return ((OV && OV.pending_days) || []).indexOf(day) >= 0; }
async function postDays(days, btn){
  if (!days.length) return;
  var sorted = days.slice().sort(), n = 0;
  await busy(btn, async function(){
    for (var i = 0, cs = chunks(sorted[0], sorted[sorted.length - 1], 92); i < cs.length; i++){
      var r = await db.rpc('acct_post_days', {p_from: cs[i][0], p_to: cs[i][1]});
      if (r.error || !r.data || !r.data.ok){ toast(errText(r)); return; }
      n += Number(r.data.entries) || 0;
    }
    toast(n + ' entries posted');
  });
  await reloadOverview(); forget(); render();
}
function overdueInvoices(ap){ var t = today(), n = 0; (ap.vendors || []).forEach(function(v){ (v.invoices || []).forEach(function(i){ if (Number(i.open) > 0 && (i.due_date || addDays(i.date, 30)) < t) n++; }); }); return n; }
function openPayouts(ps){ return (ps || []).filter(function(p){ return Number(p.amount_crc) - Number(p.documented_crc) > 0.5; }); }

/* ---------- Overview ---------- */
VIEW.resumen = async function(){
  var r = range();
  var res = await Promise.all([loadCompare(r), loadTrends(), loadCashPosition(), loadAP(), loadPayouts(), loadExpenses(r.from, r.to), loadDue(), loadSalesByMethod(r.from, r.to)]);
  var cmp = res[0], tr = res[1], cp = res[2], ap = res[3], payouts = res[4], exps = res[5], due = res[6], sbm = res[7];
  var cur = cmp.current, prev = cmp.previous, st = rangeState(cmp), empties = emptyMonths(cmp);
  var cashBooks = sum(cp.accounts, function(a){ return a.balance; });
  var stmt = cp.accounts.filter(function(a){ return a.bank && a.bank.statement_balance != null; });
  var L = ap.ledger, owed = Number(L.invoices_open) + Number(L.received_not_invoiced) + Number(L.expenses_on_credit);
  var ivaNet = Number(cur.iva_out) - Number(cur.iva_in);
  var ivaDocs = []; try { ivaDocs = (await loadIva(r.from, r.to)).credits.documents; } catch (e) {}
  var profit = Number(cur.net) - costs(cur), pprofit = Number(prev.net) - costs(prev);
  PREV_ACTIVE = Number(prev.days_with_sales) > 0 || Number(prev.expenses) > 0 || Number(prev.purchases) > 0 || Number(prev.days_closed) > 0;
  var h = '';
  if (empties.length) h += '<div class="banner"><b>Months without data: ' + esc(empties.join(', ')) + '</b><span class="hint">Nothing was sold or recorded in them; they are not zeros.</span></div>';
  if (!MIG.v35) h += '<div class="banner bad"><b>The database needs migration 0035.</b><span class="hint">Recurring bills and payments of credit expenses are not available until it is applied.</span></div>';
  h += '<div class="grid kpis">' +
    kpi('Revenue, no IVA', fmt(cur.net), cur.net, prev.net, st === 'empty' ? 'empty' : 'register') +
    kpi('Costs and expenses', fmt(costs(cur)), costs(cur), costs(prev), 'estimate', '', true) +
    kpi('Profit', fmt(profit), profit, pprofit, 'estimate') +
    kpi('Cash and bank', fmt(cashBooks), undefined, undefined, 'books', stmt.length ? '<span class="hint">statement ' + esc(fmt(sum(stmt, function(a){ return a.bank.statement_balance; }))) + '</span>' : '') +
    kpi('Owed to suppliers', fmt(owed), undefined, undefined, 'docs') +
    kpi('IVA, net of the period', fmt(ivaNet), undefined, undefined, 'draft') +
    kpi('Credit expenses open', fmt(L.expenses_on_credit), undefined, undefined, 'docs') + '</div>';
  var months = tr.months || [], labels = months.map(function(m){ return mlabel(m.month); });
  var inc = months.map(function(m){ return Number(m.net); }), out = months.map(function(m){ return Number(m.cogs) + Number(m.waste) + Number(m.expenses); });
  var mt = methodTotals(sbm), parts = [['Cash ₡', mt.cash_crc], ['Cash $', mt.cash_usd], ['Card', mt.card], ['SINPE', mt.sinpe], ['Other', mt.other]].filter(function(p){ return p[1] > 0; }), colors = ['var(--c1)', 'var(--c5)', 'var(--c3)', 'var(--c2)', 'var(--c4)'];
  var byCat = {}; exps.filter(function(e){ return !e.voided_at; }).forEach(function(e){ byCat[e.account] = (byCat[e.account] || 0) + Number(e.amount_crc) - Number(e.iva_crc); });
  serviceInvoices(ivaDocs).forEach(function(x){ byCat[x.account] = (byCat[x.account] || 0) + Number(x.base_crc); });
  if (Number(cur.cogs)) byCat[mapped('cogs', '5101')] = (byCat[mapped('cogs', '5101')] || 0) + Number(cur.cogs);
  if (Number(cur.waste)) byCat[mapped('waste', '5102')] = (byCat[mapped('waste', '5102')] || 0) + Number(cur.waste);
  var cats = Object.keys(byCat).map(function(k){ return [k + ' · ' + accountName(k), byCat[k]]; }).sort(function(a, b){ return b[1] - a[1]; }).slice(0, 8);
  h += '<div class="grid two" style="margin-top:1rem">' +
    '<div class="card"><h2>Revenue and costs by month</h2>' + HG_CHARTS.box(function(W){ return HG_CHARTS.bar([inc, out], labels, ['var(--c1)', 'var(--c2)'], 220, W); }) + HG_CHARTS.legend([['Revenue, no IVA', 'var(--c1)'], ['Costs and expenses', 'var(--c2)']]) + '</div>' +
    '<div class="card"><h2>Profit by month ' + stateTag('estimate') + '</h2>' + HG_CHARTS.box(function(W){ return HG_CHARTS.line(inc.map(function(v, i){ return v - out[i]; }), labels, 'var(--c3)', 220, true, W); }) + '</div>' +
    '<div class="card"><h2>Sales by payment method ' + stateTag('register') + '</h2>' + (parts.length ? '<div style="display:flex;gap:1rem;align-items:center;flex-wrap:wrap">' + HG_CHARTS.donut(parts, colors) + '<ul class="list" style="flex:1;min-width:180px">' + parts.map(function(p, i){ return '<li style="padding:.3rem .5rem"><span class="t"><i style="display:inline-block;width:10px;height:10px;border-radius:2px;background:' + colors[i] + ';margin-right:.4rem"></i>' + esc(p[0]) + '</span><span class="mono">' + fmt(p[1]) + '</span></li>'; }).join('') + '</ul></div>' : '<p class="hint">No sales in this period.</p>') + '</div>' +
    '<div class="card"><h2>Expenses by category ' + stateTag('docs') + '</h2>' + (cats.length ? HG_CHARTS.hbars(cats, 'var(--c2)') : '<p class="hint">No expenses in this period.</p>') + '</div></div>';
  var pend = (OV.pending_days || []), noRec = exps.filter(function(e){ return !e.receipt_path && !e.voided_at; }).length, toRec = sum(cp.accounts, function(a){ return a.bank ? a.bank.open_lines : 0; });
  var items = [
    [overdueInvoices(ap), 'overdue supplier invoice', 'overdue supplier invoices', '#proveedores', ''],
    [pend.length, 'closed day not in the books', 'closed days not in the books', '#ingresos', pend.length ? '<button type="button" class="small" id="postBtn">Post ' + pend.length + ' days</button>' : ''],
    [openPayouts(payouts).length, 'register payout waiting for its invoice', 'register payouts waiting for their invoice', '#gastos', ''],
    [toRec, 'bank movement to reconcile', 'bank movements to reconcile', '#banco', ''],
    [noRec, 'expense without a receipt', 'expenses without a receipt', '#gastos', ''],
    [due.length, 'recurring bill due this week', 'recurring bills due this week', '#gastos', '']];
  var open = items.filter(function(p){ return Number(p[0]) > 0; });
  h += '<div class="card" style="margin-top:1rem"><h2>Pending</h2>' + (open.length ? '<ul class="list">' + open.map(function(p){ return '<li><span class="t"><span class="mono">' + p[0] + '</span> ' + esc(p[0] === 1 ? p[1] : p[2]) + '</span>' + p[4] + '<a href="' + p[3] + '">See ›</a></li>'; }).join('') + '</ul>' : '<p class="hint">Nothing pending: the days are posted, the receipts are in, the bank is reconciled.</p>') + '</div>';
  var host = document.createElement('div'); host.innerHTML = h;
  var pb = host.querySelector('#postBtn'); if (pb) pb.addEventListener('click', function(){ postDays(pend, pb); });
  return host;
};

/* ---------- Income: what the register already knows, day by day; the only write is «Post» ---------- */
function dayDetail(d){
  openDrawer('Day ' + d.date, '<div class="loading">Loading…</div>', '');
  Promise.all([loadJournal(d.date, d.date, null), d.pending ? Promise.resolve(null) : null]).then(function(res){
    var entries = (res[0] || []).filter(function(e){ return e.source === 'day'; });
    var body = '<dl class="dl"><dt>Orders</dt><dd class="mono">' + esc(d.orders == null ? '—' : d.orders) + '</dd><dt>Collected</dt><dd class="mono">' + fmt(d.gross) + '</dd><dt>Revenue, no IVA</dt><dd class="mono">' + fmt(d.net) + '</dd>' +
      '<dt>Cash ₡</dt><dd class="mono">' + fmt(d.cash_crc) + '</dd><dt>Cash $ (in colones)</dt><dd class="mono">' + fmt(d.cash_usd) + '</dd><dt>Card</dt><dd class="mono">' + fmt(d.card) + '</dd><dt>SINPE</dt><dd class="mono">' + fmt(d.sinpe) + '</dd>' +
      '<dt>Float</dt><dd class="mono">' + fmt(d.float_crc) + '</dd><dt>Expected cash</dt><dd class="mono">' + fmt(d.expected_crc) + '</dd><dt>Counted</dt><dd class="mono">' + (d.counted_crc == null ? 'not counted' : fmt(d.counted_crc)) + '</dd><dt>Difference</dt><dd class="mono ' + (Number(d.diff_crc) < 0 ? 'down' : '') + '">' + (d.diff_crc == null ? '—' : fmt(d.diff_crc)) + '</dd>' +
      (Number(d.float_usd) || Number(d.sales_usd) || d.counted_usd != null ? '<dt>Dollars</dt><dd class="mono">float ' + fmtUsd(d.float_usd) + ' · sales ' + fmtUsd(d.sales_usd) + ' · counted ' + (d.counted_usd == null ? '—' : fmtUsd(d.counted_usd)) + '</dd>' : '') +
      '<dt>Status</dt><dd>' + dayPill(d) + '</dd></dl>' +
      (entries.length ? entries.map(function(e){ return '<h3>Entry Nº ' + esc(e.entry_no) + ' <span class="hint">' + esc(e.memo) + '</span></h3>' + linesTable(e.lines); }).join('') : '<p class="note">' + (d.pending ? 'This day is closed but not in the books yet.' : d.closed ? 'No entry for this day.' : 'The register is still open: the entry is made when it closes and is posted.') + '</p>');
    $('drawerBody').innerHTML = body;
    $('drawerFoot').innerHTML = d.pending ? '<button type="button" class="small" id="postOne">Post this day</button>' : '';
    var b = $('postOne'); if (b) b.addEventListener('click', function(){ closeDrawer(); postDays([d.date], null); });
  }).catch(function(e){ $('drawerBody').innerHTML = '<p class="err">' + esc(errText(e)) + '</p>'; });
}
function dayPill(d){ return d.opened === false ? pill('p-mute', 'no register') : !d.closed ? pill('p-info', 'open') : d.pending ? pill('p-warn', 'to post') : pill('p-ok', 'posted'); }
VIEW.ingresos = async function(){
  var r = range(), t = today(), last28 = addDays(t, -27);
  var tr = tableRange('dias', r);
  var res = await Promise.all([loadCompare(r), loadDashboard().catch(function(){ return null; }), loadCashDays(tr.from, tr.to), loadSalesByMethod(tr.from, tr.to), loadPatterns(tr.from < last28 ? tr.from : last28, t)]);
  var cmp = res[0], dash = res[1], cash = res[2], sbm = res[3], pat = res[4];
  var cur = cmp.current, prev = cmp.previous, st = rangeState(cmp);
  var bym = by(sbm, 'day'), byp = by(pat, 'day'), pend = OV.pending_days || [];
  var days = cash.map(function(d){ var m = bym[d.date] || {}, p = byp[d.date] || {}; return Object.assign({}, d, {cash_crc: Number(m.cash_crc) || 0, cash_usd: Number(m.cash_usd) || 0, card: Number(m.card) || 0, sinpe: Number(m.sinpe) || 0, other: Number(m.other) || 0, gross: Number(p.gross) || Number(m.total) || 0, net: Number(p.net) || 0, orders: p.orders, pending: isPending(d.date)}); });
  /* days with sales and no register still count (0028): they come from the patterns, not the register */
  pat.forEach(function(p){ if (p.day >= tr.from && p.day <= tr.to && !days.some(function(d){ return d.date === p.day; })){ var m = bym[p.day] || {}; days.push({date: p.day, opened: false, closed: true, gross: Number(p.gross), net: Number(p.net), orders: p.orders, cash_crc: Number(m.cash_crc) || 0, cash_usd: Number(m.cash_usd) || 0, card: Number(m.card) || 0, sinpe: Number(m.sinpe) || 0, other: Number(m.other) || 0, pending: isPending(p.day)}); } });
  var h = '';
  if (dash) h += '<div class="banner"><b>Today' + (dash.state === 'no_register' ? ' (no register yet)' : dash.state === 'estimate' ? ' (register open)' : ' (register closed)') + '</b><span class="mono">' + fmt(dash.today.gross) + '</span><span class="hint">' + esc(dash.today.orders) + ' orders · collected so far; it can still change</span><span class="sp"></span>' + stateTag(dash.state === 'final' ? 'final' : 'estimate') + '</div>';
  if (pend.length) h += '<div class="banner"><b><span class="mono">' + pend.length + '</span> ' + (pend.length === 1 ? 'closed day not in the books yet' : 'closed days not in the books yet') + '</b><span class="hint">Posting adds only what is missing, never twice (acct_post_days).</span><span class="sp"></span><button type="button" class="small" id="postAll">Post ' + pend.length + ' days</button></div>';
  h += '<div class="grid kpis">' + kpi('Collected (money received)', fmt(cur.gross), cur.gross, prev.gross, 'register') + kpi('Revenue, no IVA', fmt(cur.net), cur.net, prev.net, st === 'empty' ? 'empty' : st === 'books' ? 'books' : 'estimate') +
    kpi('IVA on sales', fmt(cur.iva_out), undefined, undefined, 'draft') + '<div class="kpi"><div class="l">Orders</div><div class="v">' + esc(num(cur.orders, 0)) + '</div><div class="d">' + delta(cur.orders, prev.orders) + '</div></div>' +
    kpi('Average order', fmt(Number(cur.orders) ? Number(cur.gross) / Number(cur.orders) : 0), Number(cur.orders) ? Number(cur.gross) / Number(cur.orders) : 0, Number(prev.orders) ? Number(prev.gross) / Number(prev.orders) : 0) +
    kpi('Discounts', fmt(cur.discounts), undefined, undefined, 'register') + kpi('Refunds', fmt(cur.refunds), undefined, undefined, 'register') + '</div>';
  var series = pat.filter(function(p){ return p.day >= last28; }).sort(function(a, b){ return a.day < b.day ? -1 : 1; });
  h += '<div class="card" style="margin-top:1rem"><h2>Sales by day <span class="hint">· last 4 weeks, no IVA</span></h2>' + (series.length ? HG_CHARTS.box(function(W){ return HG_CHARTS.line(series.map(function(p){ return Number(p.net); }), series.map(function(p){ return dlabel(p.day); }), 'var(--c1)', 210, true, W); }) : '<p class="hint">No sales in the last four weeks.</p>') + '</div>';
  h += '<div class="card" style="margin-top:1rem"><h2>Register days</h2><p class="hint" style="margin:0 0 .6rem">Each closed day appears here once. Posting it brings to the books: sales without IVA, refunds, IVA, money by payment method, advances on open bills, the cash difference, the cost of what was sold, waste and adjustments, and the deliveries received. Card and SINPE are what the register recorded (sales_by_method).</p><div id="daysBox"></div></div>';
  if (KIND === 'owner') h += '<div class="card" style="margin-top:1rem"><h2>Find a receipt <span class="hint">· owner only</span></h2><div class="tools"><div class="grow"><label for="osText">Text or guest</label><input id="osText" placeholder="e.g. mocha, Pedro"></div><div><label for="osNo">Receipt Nº</label><input id="osNo" inputmode="numeric"></div><div><label for="osFrom">From</label><input type="date" id="osFrom" value="' + addDays(t, -30) + '"></div><div><label for="osTo">To</label><input type="date" id="osTo" value="' + t + '"></div><div><button type="button" class="small" id="osGo">Search</button></div></div><div id="osOut"></div></div>';
  else h += '<p class="note">The per-receipt list (order_search) is for the owner; the accountant works with the days and the totals.</p>';
  var host = document.createElement('div'); host.innerHTML = h;
  host.querySelector('#daysBox').appendChild(table({id: 'dias', rows: days, dateKey: 'date', dated: true, defaultSort: 'date', search: false, pageSize: 10, onRow: dayDetail,
    columns: [{key: 'date', label: 'Day', nw: true, render: function(x){ return '<span class="mono">' + esc(x.date) + '</span>'; }}, {key: 'orders', label: 'Orders', num: true, render: function(x){ return esc(x.orders == null ? '—' : x.orders); }},
      {key: 'gross', label: 'Collected', num: true, render: function(x){ return '<span class="mono">' + fmt(x.gross) + '</span>'; }}, {key: 'net', label: 'No IVA', num: true, render: function(x){ return '<span class="mono">' + fmt(x.net) + '</span>'; }},
      {key: 'cash_crc', label: 'Cash ₡', num: true, render: function(x){ return '<span class="mono">' + fmt(x.cash_crc) + '</span>'; }}, {key: 'cash_usd', label: 'Cash $', num: true, render: function(x){ return '<span class="mono">' + fmt(x.cash_usd) + '</span>'; }},
      {key: 'card', label: 'Card', num: true, render: function(x){ return '<span class="mono">' + fmt(x.card) + '</span>'; }}, {key: 'sinpe', label: 'SINPE', num: true, render: function(x){ return '<span class="mono">' + fmt(x.sinpe) + '</span>'; }},
      {key: 'diff_crc', label: 'Difference', num: true, render: function(x){ return x.diff_crc == null ? '<span class="hint">—</span>' : '<span class="mono ' + (Number(x.diff_crc) < 0 ? 'down' : Number(x.diff_crc) > 0 ? 'up' : '') + '">' + fmt(x.diff_crc) + '</span>'; }},
      {key: 'status', label: 'Status', nw: true, sort: false, text: function(x){ return x.pending ? 'to post' : x.closed ? 'posted' : 'open'; }, render: dayPill}],
    filters: [{key: 'status', label: 'Status', value: function(x){ return x.pending ? 'pending' : x.closed ? 'posted' : 'open'; }, options: [['posted', 'posted'], ['pending', 'to post'], ['open', 'open']]}],
    csv: function(rows){ return ['ingresos-' + r.from + '-' + r.to + '.csv', [['day', 'orders', 'collected_crc', 'net_crc', 'cash_crc', 'cash_usd_crc', 'card_crc', 'sinpe_crc', 'float_crc', 'expected_crc', 'counted_crc', 'diff_crc', 'status']].concat(rows.map(function(x){ return [x.date, x.orders, x.gross, x.net, x.cash_crc, x.cash_usd, x.card, x.sinpe, x.float_crc, x.expected_crc, x.counted_crc, x.diff_crc, x.pending ? 'to post' : x.closed ? 'posted' : 'open']; }))]; }}));
  var pa = host.querySelector('#postAll'); if (pa) pa.addEventListener('click', function(){ postDays(pend, pa); });
  var og = host.querySelector('#osGo');
  if (og) og.addEventListener('click', async function(){
    var out = host.querySelector('#osOut'); out.innerHTML = '<div class="loading">Searching…</div>';
    var rr = await db.rpc('order_search', {p_from: host.querySelector('#osFrom').value, p_to: host.querySelector('#osTo').value, p_text: host.querySelector('#osText').value.trim() || null, p_receipt: host.querySelector('#osNo').value ? Number(host.querySelector('#osNo').value) : null, p_limit: 100});
    if (rr.error || !rr.data || !rr.data.ok){ out.innerHTML = '<p class="err">' + esc(rr.data && rr.data.error === 'locked' ? 'Earlier days open with the sales permission.' : errText(rr)) + '</p>'; return; }
    var os = rr.data.orders || [];
    out.innerHTML = os.length ? '<div class="tbox"><table><thead><tr><th>Receipt</th><th>When</th><th>Items</th><th>Method</th><th>Who rang it up</th><th class="num">Total</th></tr></thead><tbody>' + os.map(function(o){ return '<tr><td class="mono">' + esc(o.receipt_no || '') + (o.voided_at ? ' ' + tag('rev', 'voided') : o.refund_of ? ' ' + tag('', 'refund') : '') + '</td><td class="mono nw">' + esc(crTime(o.created_at)) + '</td><td>' + esc((o.items || []).map(function(i){ return i.qty + '× ' + i.name; }).join(', ')) + '</td><td>' + esc(PM_SALE[o.payment_method] || o.payment_method || '') + '</td><td>' + esc(o.operator_name || '') + '</td><td class="num mono">' + fmt(o.total_crc) + '</td></tr>'; }).join('') + '</tbody></table></div>' : '<p class="hint">No receipts match.</p>';
  });
  return host;
};

/* ---------- Expenses ---------- */
var PM_SALE = {cash: 'Cash', cash_crc: 'Cash ₡', cash_usd: 'Cash $', card: 'Card', sinpe: 'SINPE', other: 'Other', split: 'Split', mixed: 'Mixed'};
var PM_SHORT = {payout: 'Register payout', petty: 'Petty cash', bank: 'Bank or SINPE', credit: 'On credit', cash: 'Cash', card_debit: 'Debit card', card_credit: 'Credit card'};
var PM_NAME = {payout: 'Money taken from the register', petty: 'Petty cash', bank: 'Bank transfer or SINPE', credit: 'On credit (to pay later)', cash: 'Cash from the safe', card_debit: 'Debit card', card_credit: 'Credit card'};
var PM_EXPENSE = ['bank', 'petty', 'payout', 'cash', 'credit'], PM_PAY = ['bank', 'payout', 'petty', 'cash', 'card_debit', 'card_credit'];
var IVA_RATES = [['0.13', '13 %'], ['0.04', '4 %'], ['0.02', '2 %'], ['0.01', '1 %'], ['0', '0 % (exempt)']];
function pmName(k){ return PM_NAME[k] || k; }
function ivaOf(total, rate){ return Math.round((total - total / (1 + Number(rate))) * 100) / 100; }
function expenseStatus(e){ return e.voided_at ? 'voided' : e.paid_from === 'credit' ? (Number(e.open_crc == null ? e.amount_crc : e.open_crc) > 0.005 ? 'credit' : 'paid_credit') : 'paid'; }
function expensePill(e){ var s = expenseStatus(e); return s === 'voided' ? pill('p-mute', 'voided') : s === 'credit' ? pill('p-warn', 'on credit · owes ' + fmt(e.open_crc == null ? e.amount_crc : e.open_crc)) : s === 'paid_credit' ? pill('p-ok', 'credit, paid') : pill('p-ok', 'paid'); }
function vendorOptions(){ return '<datalist id="vendorList">' + VEND.map(function(v){ return '<option value="' + esc(v.name) + '">'; }).join('') + '</datalist>'; }
function vendorByName(name){ var n = plain(name); if (!n) return null; return VEND.filter(function(v){ return plain(v.name) === n; })[0] || null; }
function accountOptions(sel){ return expenseAccounts().map(function(a){ return '<option value="' + esc(a.code) + '"' + (a.code === sel ? ' selected' : '') + '>' + esc(a.code + ' · ' + a.name) + '</option>'; }).join(''); }
function pmOptions(list, sel){ return list.map(function(p){ return '<option value="' + p + '"' + (p === sel ? ' selected' : '') + '>' + esc(pmName(p)) + '</option>'; }).join(''); }
function rateOptions(sel){ return IVA_RATES.map(function(r){ return '<option value="' + r[0] + '"' + (sel != null && Number(sel) === Number(r[0]) ? ' selected' : '') + '>' + r[1] + '</option>'; }).join(''); }
function payoutOptions(ps, sel){ return '<option value="">Not recorded at the POS</option>' + openPayouts(ps).map(function(p){ return '<option value="' + esc(p.id) + '"' + (p.id === sel ? ' selected' : '') + '>' + esc(p.date + ' · ' + p.reason + ' · ' + fmt(Number(p.amount_crc) - Number(p.documented_crc))) + '</option>'; }).join(''); }
var VEND = [];
async function ensureVendors(){ try { VEND = (await loadVendors()).vendors; } catch (e){ if (missing(e)){ MIG.v34 = false; VEND = []; } else throw e; } return VEND; }
/* the quick form: supplier, amount, date, a note and the receipt; category, IVA and where the money came from follow the
   supplier's confirmed habits. What is missing is asked, only that. «More details» holds the rest. */
async function expenseForm(prefill){
  prefill = prefill || {};
  await ensureVendors(); var payouts = await loadPayouts();
  var req = prefill.request_id || uuid(), t = today();
  var v0 = prefill.vendor_id ? VEND.filter(function(x){ return x.id === prefill.vendor_id; })[0] : null;
  var h = '<form id="expForm" class="form one">' +
    '<p class="hint" style="margin:0">For the usual bills: supplier, amount, done. The rest comes from what is habitual for that supplier.</p>' +
    '<div><label for="ef-vendor">Supplier</label><div style="display:flex;gap:.4rem"><input id="ef-vendor" list="vendorList" autocomplete="off" placeholder="Search supplier…" value="' + esc(v0 ? v0.name : (prefill.vendor_name || '')) + '">' + (KIND === 'owner' ? '<button type="button" class="ghost small" id="ef-addv" style="white-space:nowrap">+ Add</button>' : '') + '</div>' + vendorOptions() + '</div>' +
    '<div><label for="ef-total">Amount, IVA included (₡)</label><input id="ef-total" class="big" type="number" inputmode="decimal" min="0" step="any" data-keypad="amount" placeholder="₡" value="' + (prefill.amount_crc ? esc(prefill.amount_crc) : '') + '"></div>' +
    '<div class="form"><div><label for="ef-date">Date</label><input type="date" id="ef-date" value="' + esc(prefill.date || t) + '" max="' + t + '"></div><div><label for="ef-desc">Note (optional)</label><input id="ef-desc" maxlength="200" value="' + esc(prefill.description || '') + '"></div></div>' +
    (RECEIPTS ? '<div><label>Receipt (optional)</label><div class="attach"><button type="button" class="ghost small" id="ef-photo">Take a photo</button><button type="button" class="ghost small" id="ef-file">Attach image or PDF</button><span class="hint" id="ef-fname">No file yet</span><input type="file" id="ef-cam" accept="image/*" capture="environment"><input type="file" id="ef-doc" accept="image/*,application/pdf"></div></div>' : '<p class="hint" id="ef-noreceipt" style="margin:0">Receipt photos from this page are off until the backup of the private files is verified (E-17, Home → Settings). Until then, attach the file from the previous accounting page.</p>') +
    '<div class="resolved" id="ef-resolved"></div>' +
    '<div id="ef-ask" class="form" hidden></div>' +
    '<label class="check" id="ef-rememberBox" hidden><input type="checkbox" id="ef-remember" checked> <span id="ef-rememberText">Remember these for this supplier (it will not ask again)</span></label>' +
    '<details class="more" id="ef-more"><summary>More details</summary><div class="form">' +
      '<div><label for="ef-inv">Invoice Nº</label><input id="ef-inv" maxlength="40" value="' + esc(prefill.invoice_no || '') + '"></div><div><label for="ef-invdate">Invoice date</label><input type="date" id="ef-invdate" value="' + esc(prefill.invoice_date || '') + '"></div>' +
      '<div id="ef-catBox"><label for="ef-cat">Category</label><select id="ef-cat"><option value="">—</option>' + accountOptions(prefill.account || (v0 && v0.default_account) || '') + '</select></div>' +
      '<div id="ef-rateBox"><label for="ef-rate">IVA rate</label><select id="ef-rate"><option value="">—</option>' + rateOptions(prefill.iva_rate != null ? prefill.iva_rate : (v0 ? v0.default_iva_rate : null)) + '</select></div>' +
      '<div><label for="ef-iva">IVA amount (₡)</label><input id="ef-iva" type="number" inputmode="decimal" min="0" step="any" placeholder="from the rate" value="' + (prefill.iva_crc != null ? esc(prefill.iva_crc) : '') + '"></div>' +
      '<div id="ef-pmBox"><label for="ef-pm">Paid with</label><select id="ef-pm"><option value="">—</option>' + pmOptions(PM_EXPENSE, prefill.paid_from || (v0 && v0.default_paid_from) || '') + '</select></div>' +
      '<div id="ef-payoutBox" hidden><label for="ef-payout">Which payout</label><select id="ef-payout">' + payoutOptions(payouts, prefill.payout_id) + '</select></div>' +
      (prefill.schedule_id ? '' : '<div><label for="ef-rec">Repeats</label><select id="ef-rec"><option value="">No</option><option value="week">Every week, this weekday</option><option value="month">Every month, this day</option></select></div>') +
    '</div><p class="hint" id="ef-creditNote" hidden>On credit: the expense goes to accounts payable (2101) and is paid later from its row.</p></details></form>';
  openDrawer(prefill.schedule_id ? 'Recurring bill' : 'New expense', h, '<button type="button" class="ghost small" id="ef-cancel">Cancel</button><button type="button" id="ef-save">Save expense</button>');
  var B = $('drawerBody'), f = {};
  ['ef-vendor', 'ef-total', 'ef-date', 'ef-desc', 'ef-cam', 'ef-doc', 'ef-fname', 'ef-resolved', 'ef-ask', 'ef-rememberBox', 'ef-remember', 'ef-inv', 'ef-invdate', 'ef-cat', 'ef-rate', 'ef-iva', 'ef-pm', 'ef-payout', 'ef-payoutBox', 'ef-creditNote', 'ef-more'].forEach(function(id){ f[id.slice(3)] = B.querySelector('#' + id); });
  var file = null;
  if (RECEIPTS){
    B.querySelector('#ef-photo').addEventListener('click', function(){ f.cam.click(); });
    B.querySelector('#ef-file').addEventListener('click', function(){ f.doc.click(); });
    [f.cam, f.doc].forEach(function(i){ i.addEventListener('change', function(){ file = i.files && i.files[0] ? i.files[0] : file; f.fname.textContent = file ? file.name : 'No file yet'; }); });
  }
  var av = B.querySelector('#ef-addv'); if (av) av.addEventListener('click', function(){ vendorForm(null, function(v){ expenseForm(Object.assign({}, prefill, {vendor_id: v.id, amount_crc: f.total.value, date: f.date.value, description: f.desc.value, request_id: req})); }); });
  /* what the supplier's habits give, what the person must still say */
  function vendor(){ return vendorByName(f.vendor.value); }
  function resolved(){
    var v = vendor(), total = Number(f.total.value) || 0;
    var acc = f.cat.value || (v && v.default_account) || '', pm = f.pm.value || (v && v.default_paid_from) || '';
    var rate = f.rate.value !== '' ? Number(f.rate.value) : (v && v.default_iva_rate != null ? Number(v.default_iva_rate) : null);
    var iva = f.iva.value !== '' ? Number(f.iva.value) : rate != null ? ivaOf(total, rate) : null;
    return {v: v, acc: acc, pm: pm, rate: rate, iva: iva, total: total, fromHabit: {acc: !f.cat.value && !!(v && v.default_account), pm: !f.pm.value && !!(v && v.default_paid_from), iva: f.iva.value === '' && f.rate.value === '' && !!(v && v.default_iva_rate != null)},
            /* what was chosen by hand this time and the supplier has no habit of yet: worth remembering */
            fresh: !!v && ((!!f.cat.value && f.cat.value !== v.default_account) || (!!f.pm.value && f.pm.value !== v.default_paid_from) || (f.rate.value !== '' && (v.default_iva_rate == null || Number(v.default_iva_rate) !== Number(f.rate.value))))};
  }
  function refresh(){
    var x = resolved(), ask = [];
    if (!x.acc) ask.push('cat'); if (x.iva == null) ask.push('rate'); if (!x.pm) ask.push('pm');
    f.ask.hidden = !ask.length;
    if (ask.length){
      /* the boxes are moved, never rebuilt: the same selects keep their values and listeners */
      var hint = f.ask.querySelector('.ask-hint'); if (!hint){ hint = document.createElement('p'); hint.className = 'hint full ask-hint'; hint.style.margin = '0'; f.ask.insertBefore(hint, f.ask.firstChild); }
      hint.innerHTML = '<span>' + (x.v ? 'This supplier has no habit yet for:' : 'Say:') + '</span> ' + ask.map(function(k){ return '<span>' + {cat: 'category', rate: 'IVA', pm: 'paid with'}[k] + '</span>'; }).join(', ');
      ask.forEach(function(k){ var box = B.querySelector('#ef-' + k + 'Box'); if (box && box.parentNode !== f.ask) f.ask.appendChild(box); });
    }
    ['cat', 'rate', 'pm'].forEach(function(k){ if (ask.indexOf(k) < 0){ var box = B.querySelector('#ef-' + k + 'Box'); if (box && box.parentNode !== f.more.querySelector('.form')) f.more.querySelector('.form').insertBefore(box, f.more.querySelector('#ef-inv').parentNode.nextSibling.nextSibling); } });
    f.rememberBox.hidden = !(x.v && (ask.length || x.fresh));
    /* first time for this supplier: remembered unless unticked; a change to what it already has: only if asked for */
    var firstTime = !!(x.v && !x.v.default_account && !x.v.default_paid_from && x.v.default_iva_rate == null);
    if (f.rememberBox.hidden !== f._rememberWas){ f.remember.checked = firstTime; f._rememberWas = f.rememberBox.hidden; }
    B.querySelector('#ef-rememberText').textContent = firstTime ? 'Remember these for this supplier (it will not ask again)' : 'Use this as the habit of this supplier from now on';
    f.payoutBox.hidden = x.pm !== 'payout'; f.creditNote.hidden = x.pm !== 'credit';
    var typed = f.vendor.value.trim();
    f.resolved.innerHTML = (typed && !x.v ? '<span class="hint">' + esc(typed) + ' <span>is not on the supplier list: only the name is kept with this expense</span>' + (KIND === 'owner' ? ' <span>(or add the supplier with «+ Add»)</span>' : ' <span>(only the owner adds suppliers)</span>') + '</span><br>' : '') + (x.total > 0 ? '<span class="hint"><span>Amount read:</span> <b class="mono">' + fmt(x.total) + '</b></span><br>' : '') + (x.acc || x.pm || x.iva != null ? 'Will be recorded as: <b>' + esc(x.acc ? x.acc + ' · ' + accountName(x.acc) : '…') + '</b> · IVA <b class="mono">' + (x.iva != null ? fmt(x.iva) : '…') + '</b>' + (x.rate != null && f.iva.value === '' ? ' <span class="hint">(' + Math.round(x.rate * 100) + ' %)</span>' : '') + ' · <b>' + esc(x.pm ? pmName(x.pm) : '…') + '</b>' + ((x.fromHabit.acc || x.fromHabit.pm || x.fromHabit.iva) && !x.fresh ? ' <span class="hint">· from the supplier\'s habits</span>' : '') : '<span class="hint">Pick the supplier, or say the category, the IVA and where the money came from.</span>');
  }
  ['vendor', 'total', 'cat', 'rate', 'iva', 'pm'].forEach(function(k){ f[k].addEventListener('input', refresh); f[k].addEventListener('change', refresh); });
  refresh();
  B.querySelector('#expForm').addEventListener('submit', function(e){ e.preventDefault(); $('ef-save').click(); });
  $('ef-cancel').addEventListener('click', closeDrawer);
  $('ef-save').addEventListener('click', function(){
    var x = resolved();
    footErr('');
    if (!(x.total > 0)){ footErr('Write the amount.'); f.total.focus(); return; }
    if (!x.v && !f.vendor.value.trim() && !f.desc.value.trim()){ footErr('Pick the supplier or write a note.'); f.vendor.focus(); return; }
    if (!x.acc || x.iva == null || !x.pm){ f.more.open = true; refresh(); footErr('Say what is missing (category, IVA or paid with).'); return; }
    if (x.iva >= x.total){ footErr('IVA must be less than the total.'); return; }
    var p = {date: f.date.value, vendor_id: x.v ? x.v.id : null, vendor_name: x.v ? null : (f.vendor.value.trim() || null), description: f.desc.value.trim() || null,
             account: x.acc, amount_crc: x.total, iva_crc: x.iva, paid_from: x.pm, invoice_no: f.inv.value.trim() || null, invoice_date: f.invdate.value || null,
             payout_id: x.pm === 'payout' ? (f.payout.value || null) : null, schedule_id: prefill.schedule_id || null, period_key: prefill.period_key || null};
    busy(this, async function(){
      var r = await db.rpc('expense_save', {p_expense: p, p_request_id: req});
      if (r.error || !r.data || !r.data.ok){ footErr(errText(r)); if (r.data && /^needs_/.test(r.data.error || '')){ f.more.open = true; } return; }
      var notes = [];
      if (x.v && x.fresh && f.remember.checked){
        var d = await db.rpc('vendor_defaults_save', {p_vendor_id: x.v.id, p_defaults: {account: x.acc, paid_from: x.pm, iva_rate: f.iva.value !== '' ? (x.v.default_iva_rate != null ? String(x.v.default_iva_rate) : null) : (x.rate != null ? String(x.rate) : null), payment_notes: x.v.payment_notes || null}});
        if (d.error || !d.data || !d.data.ok) notes.push('the supplier\'s habits were not saved'); else { forget('vendors'); forget('vh:'); }
      }
      if (file){
        var path = r.data.id + '/' + (file.name || 'factura').replace(/[^A-Za-z0-9._-]+/g, '_').slice(-80);
        var up = await db.storage.from('expense-receipts').upload(path, file, {contentType: file.type || 'application/octet-stream'});
        var at = up.error ? null : await db.rpc('expense_attach', {p_id: r.data.id, p_path: path});
        if (up.error || !at || at.error || !at.data || !at.data.ok) notes.push('the receipt file was not saved: attach it from the list');
      }
      var rec = B.querySelector('#ef-rec');
      if (rec && rec.value){
        var dt = new Date(f.date.value + 'T12:00:00Z'), dow = dt.getUTCDay() || 7;
        var s = await db.rpc('expense_schedule_save', {p_schedule: {vendor_id: x.v ? x.v.id : null, description: f.desc.value.trim() || (x.v ? x.v.name : 'Expense'), account: x.acc, amount_crc: x.total, iva_crc: x.iva, paid_from: x.pm, every: rec.value, day_of: rec.value === 'week' ? dow : dt.getUTCDate()}});
        if (s.error || !s.data || !s.data.ok) notes.push('the recurring bill was not created'); else { notes.push('it will be reminded ' + (rec.value === 'week' ? 'every week' : 'every month')); forget('due'); forget('schedules'); }
      }
      closeDrawer(); forget();
      toast('Expense saved and posted' + (notes.length ? ' · ' + notes.join(' · ') : ''));
      render();
    });
  });
}
async function expenseDetail(e){
  openDrawer('Expense · ' + e.date, '<div class="loading">Loading…</div>', '');
  var entries = []; try { entries = await loadJournal(e.date, e.date, null); } catch (x) {}
  var entry = entries.filter(function(j){ return j.id === e.entry_id; })[0];
  var s = expenseStatus(e);
  var body = '<dl class="dl"><dt>Supplier</dt><dd>' + (e.vendor_id ? '<a href="#proveedores" data-vendor="' + esc(e.vendor_id) + '">' + esc(e.vendor_name || '') + '</a>' : esc(e.vendor_name || '—')) + '</dd><dt>What</dt><dd>' + esc(e.description) + '</dd>' +
    '<dt>Category</dt><dd>' + esc(e.account + ' · ' + (e.account_name || accountName(e.account))) + '</dd><dt>Total, IVA included</dt><dd class="mono">' + fmt(e.amount_crc) + '</dd><dt>IVA</dt><dd class="mono">' + fmt(e.iva_crc) + '</dd>' +
    '<dt>Paid with</dt><dd>' + esc(pmName(e.paid_from)) + '</dd><dt>Status</dt><dd>' + expensePill(e) + (e.voided_at ? ' <span class="hint">' + esc(crDate(e.voided_at) + ' · ' + (e.void_reason || '')) + '</span>' : '') + '</dd>' +
    '<dt>Invoice Nº</dt><dd>' + esc(e.invoice_no || '—') + '</dd><dt>Invoice date</dt><dd class="mono">' + esc(e.invoice_date || '—') + '</dd><dt>Recorded by</dt><dd>' + esc(e.created_by || '') + '</dd>' + (e.schedule_id ? '<dt>Recurring bill</dt><dd><span>Period</span> <span class="mono">' + esc(e.period_key) + '</span></dd>' : '') + '</dl>';
  body += '<h3>Receipt</h3>' + (e.receipt_path ? '<div class="attach"><span class="mono" style="overflow-wrap:anywhere">' + esc(e.receipt_path.split('/').pop()) + '</span><span style="flex:1"></span><button type="button" class="ghost small" id="xd-open">Open</button></div>' : e.voided_at ? '<p class="hint">No receipt.</p>' : RECEIPTS ? '<div class="attach"><span class="pill p-bad">no receipt</span><button type="button" class="ghost small" id="xd-attach">Attach image or PDF</button><input type="file" id="xd-file" accept="image/*,application/pdf"></div>' : '<div class="attach"><span class="pill p-bad">no receipt</span><span class="hint">Receipt files from this page are off until the backup of the private files is verified (E-17, Home → Settings).</span></div>');
  if ((e.payments || []).length) body += '<h3>Payments</h3><ul class="list">' + e.payments.map(function(p){ return '<li><span class="t"><span class="mono">' + esc(p.date) + '</span> · ' + esc(pmName(p.paid_from)) + (p.reference ? ' · ' + esc(p.reference) : '') + (p.voided_at ? ' ' + tag('rev', 'voided') : '') + '</span><span class="mono">' + fmt(p.amount_crc) + '</span>' + (p.voided_at ? '' : '<button type="button" class="ghost small" data-voidpay="' + esc(p.id) + '">Void</button>') + '</li>'; }).join('') + '</ul>';
  if (entry) body += '<h3>Entry Nº ' + esc(entry.entry_no) + (entry.reversed ? ' ' + tag('rev', 'reversed') : '') + '</h3>' + linesTable(entry.lines);
  $('drawerBody').innerHTML = body;
  $('drawerFoot').innerHTML = (e.voided_at ? '' : '<button type="button" class="danger small" id="xd-void">Void</button>') + '<button type="button" class="ghost small" id="xd-dup">Duplicate</button>' + (s === 'credit' ? '<button type="button" class="small" id="xd-pay">Record payment · ' + fmt(e.open_crc) + '</button>' : '');
  var B = $('drawerBody');
  B.querySelectorAll('[data-vendor]').forEach(function(a){ a.addEventListener('click', function(ev){ ev.preventDefault(); var id = a.dataset.vendor; closeDrawer(); location.hash = 'proveedores'; setTimeout(function(){ ensureVendors().then(function(){ var v = VEND.filter(function(x){ return x.id === id; })[0]; if (v) vendorCard(v); }); }, 150); }); });
  var op = B.querySelector('#xd-open'); if (op) op.addEventListener('click', async function(){ var w = window.open('', '_blank'); var su = await db.storage.from('expense-receipts').createSignedUrl(e.receipt_path, 120); if (su.error || !su.data){ if (w) w.close(); toast('Could not open the file. Try again.'); return; } if (w) w.location = su.data.signedUrl; else window.open(su.data.signedUrl, '_blank', 'noopener'); });
  var at = B.querySelector('#xd-attach'), fi = B.querySelector('#xd-file');
  if (at) { at.addEventListener('click', function(){ fi.click(); }); fi.addEventListener('change', async function(){ var file = fi.files && fi.files[0]; if (!file) return;
    var path = e.id + '/' + (file.name || 'factura').replace(/[^A-Za-z0-9._-]+/g, '_').slice(-80);
    var up = await db.storage.from('expense-receipts').upload(path, file, {contentType: file.type || 'application/octet-stream'});
    var r = up.error ? null : await db.rpc('expense_attach', {p_id: e.id, p_path: path});
    if (up.error || !r || r.error || !r.data || !r.data.ok){ toast('Could not save the file. Try again.'); return; }
    toast('Receipt attached'); closeDrawer(); forget('expenses'); render(); }); }
  B.querySelectorAll('[data-voidpay]').forEach(function(b){ b.addEventListener('click', async function(){ var why = prompt('Why is this payment voided?'); if (!why) return; var r = await db.rpc('expense_payment_void', {p_id: b.dataset.voidpay, p_reason: why}); if (r.error || !r.data || !r.data.ok){ toast(errText(r)); return; } toast('Payment voided'); closeDrawer(); forget(); render(); }); });
  var vb = $('xd-void'); if (vb) vb.addEventListener('click', async function(){ var why = prompt('Why is this expense voided?'); if (!why) return; var r = await busy(vb, function(){ return db.rpc('expense_void', {p_id: e.id, p_reason: why}); }); if (r.error || !r.data || !r.data.ok){ footErr(errText(r)); return; } toast('Expense voided'); closeDrawer(); forget(); render(); });
  $('xd-dup').addEventListener('click', function(){ expenseForm({vendor_id: e.vendor_id, vendor_name: e.vendor_name, amount_crc: e.amount_crc, description: e.description, account: e.account, paid_from: e.paid_from, iva_crc: e.iva_crc}); });
  var pb = $('xd-pay'); if (pb) pb.addEventListener('click', function(){ payExpenseForm(e); });
}
async function payExpenseForm(e){
  var payouts = await loadPayouts(), t = today(), req = uuid();
  openDrawer('Pay credit expense', '<form id="payForm" class="form"><div class="full resolved">' + esc(e.description) + (e.vendor_name ? ' · ' + esc(e.vendor_name) : '') + ' · owes <b class="mono">' + fmt(e.open_crc) + '</b></div>' +
    '<div><label for="pf-amt">Amount (₡)</label><input id="pf-amt" class="big" type="number" inputmode="decimal" min="0" step="any" data-keypad="amount" value="' + esc(e.open_crc) + '"></div><div><label for="pf-date">Date</label><input type="date" id="pf-date" value="' + t + '" max="' + t + '"></div>' +
    '<div><label for="pf-pm">Paid with</label><select id="pf-pm">' + pmOptions(PM_PAY, 'bank') + '</select></div><div id="pf-payoutBox" hidden><label for="pf-payout">Which payout</label><select id="pf-payout">' + payoutOptions(payouts) + '</select></div>' +
    '<div class="full"><label for="pf-ref">Reference (optional)</label><input id="pf-ref" maxlength="80"></div></form>', '<button type="button" class="ghost small" id="pf-cancel">Cancel</button><button type="button" id="pf-save">Record payment</button>');
  var B = $('drawerBody');
  B.querySelector('#pf-pm').addEventListener('change', function(){ B.querySelector('#pf-payoutBox').hidden = this.value !== 'payout'; });
  $('pf-cancel').addEventListener('click', function(){ expenseDetail(e); });
  $('pf-save').addEventListener('click', function(){
    var amt = Number(B.querySelector('#pf-amt').value); if (!(amt > 0)){ footErr('Write the amount.'); return; }
    busy(this, async function(){
      var r = await db.rpc('expense_pay', {p_payment: {expense_id: e.id, amount_crc: amt, paid_from: B.querySelector('#pf-pm').value, date: B.querySelector('#pf-date').value, reference: B.querySelector('#pf-ref').value.trim() || null, payout_id: B.querySelector('#pf-pm').value === 'payout' ? (B.querySelector('#pf-payout').value || null) : null}, p_request_id: req});
      if (r.error || !r.data || !r.data.ok){ footErr(errText(r)); return; }
      closeDrawer(); forget(); toast('Payment recorded · still owes ' + fmt(r.data.open_crc)); render();
    });
  });
}
/* recurring bills: a template that reminds; a person registers each one */
async function schedulesDrawer(){
  var ss = await loadSchedules(); await ensureVendors();
  var body = '<p class="hint">A recurring bill reminds you when it is due and pre-fills «New expense». Nothing is posted on its own: you confirm each one.</p>' +
    (ss.length ? '<ul class="list">' + ss.map(function(s){ return '<li><span class="t"><b>' + esc(s.description) + '</b>' + (s.vendor ? ' · ' + esc(s.vendor) : '') + '<span class="sub">' + esc(s.every === 'week' ? 'every week' : 'every month') + ' · next ' + esc(s.next_due) + ' · ' + esc(s.account + ' · ' + (s.account_name || '')) + ' · ' + esc(pmName(s.paid_from)) + (s.active ? '' : ' · inactive') + '</span></span><span class="mono">' + fmt(s.amount_crc) + '</span>' + (s.active ? '<button type="button" class="ghost small" data-edit="' + esc(s.id) + '">Edit</button><button type="button" class="ghost small" data-off="' + esc(s.id) + '">Deactivate</button>' : '') + '</li>'; }).join('') + '</ul>' : '<p class="hint">No recurring bills yet.</p>');
  openDrawer('Recurring bills', body, '<button type="button" class="ghost small" id="sc-close">Close</button><button type="button" class="small" id="sc-new">+ Recurring bill</button>');
  $('sc-close').addEventListener('click', closeDrawer);
  $('sc-new').addEventListener('click', function(){ scheduleForm(null); });
  $('drawerBody').querySelectorAll('[data-edit]').forEach(function(b){ b.addEventListener('click', function(){ scheduleForm(ss.filter(function(s){ return s.id === b.dataset.edit; })[0]); }); });
  $('drawerBody').querySelectorAll('[data-off]').forEach(function(b){ b.addEventListener('click', async function(){ var why = prompt('Why is this recurring bill deactivated?'); if (!why) return; var r = await db.rpc('expense_schedule_void', {p_id: b.dataset.off, p_reason: why}); if (r.error || !r.data || !r.data.ok){ toast(errText(r)); return; } forget('schedules'); forget('due'); toast('Recurring bill deactivated'); schedulesDrawer(); }); });
}
async function scheduleForm(s){
  s = s || {}; await ensureVendors(); var v0 = s.vendor_id ? VEND.filter(function(x){ return x.id === s.vendor_id; })[0] : null;
  openDrawer(s.id ? 'Edit recurring bill' : 'New recurring bill', '<form id="scForm" class="form">' +
    '<div class="full"><label for="sc-vendor">Supplier (optional)</label><input id="sc-vendor" list="vendorList" autocomplete="off" value="' + esc(v0 ? v0.name : '') + '">' + vendorOptions() + '</div>' +
    '<div class="full"><label for="sc-desc">What</label><input id="sc-desc" maxlength="200" value="' + esc(s.description || '') + '"></div>' +
    '<div><label for="sc-cat">Category</label><select id="sc-cat">' + accountOptions(s.account || (v0 && v0.default_account) || '') + '</select></div><div><label for="sc-pm">Paid with</label><select id="sc-pm">' + pmOptions(PM_EXPENSE, s.paid_from || (v0 && v0.default_paid_from) || 'bank') + '</select></div>' +
    '<div><label for="sc-amt">Amount, IVA included (₡)</label><input id="sc-amt" type="number" inputmode="decimal" min="0" step="any" data-keypad="amount" value="' + esc(s.amount_crc || '') + '"></div><div><label for="sc-iva">IVA (₡)</label><input id="sc-iva" type="number" inputmode="decimal" min="0" step="any" value="' + esc(s.iva_crc != null ? s.iva_crc : '') + '"></div>' +
    '<div><label for="sc-every">Repeats</label><select id="sc-every"><option value="month"' + (s.every !== 'week' ? ' selected' : '') + '>Every month</option><option value="week"' + (s.every === 'week' ? ' selected' : '') + '>Every week</option></select></div><div><label for="sc-day">Day (1–31, or 1 = Monday … 7 = Sunday)</label><input id="sc-day" type="number" inputmode="numeric" min="1" max="31" value="' + esc(s.day_of || 1) + '"></div>' +
    '<div class="full"><label for="sc-next">Next due</label><input type="date" id="sc-next" value="' + esc(s.next_due || '') + '"></div></form>', '<button type="button" class="ghost small" id="sc-back">Back</button><button type="button" id="sc-save">Save</button>');
  var B = $('drawerBody');
  $('sc-back').addEventListener('click', schedulesDrawer);
  $('sc-save').addEventListener('click', function(){
    var v = vendorByName(B.querySelector('#sc-vendor').value);
    busy(this, async function(){
      var r = await db.rpc('expense_schedule_save', {p_schedule: {id: s.id || null, vendor_id: v ? v.id : null, description: B.querySelector('#sc-desc').value.trim(), account: B.querySelector('#sc-cat').value, amount_crc: Number(B.querySelector('#sc-amt').value), iva_crc: Number(B.querySelector('#sc-iva').value) || 0, paid_from: B.querySelector('#sc-pm').value, every: B.querySelector('#sc-every').value, day_of: Number(B.querySelector('#sc-day').value), next_due: B.querySelector('#sc-next').value || null}});
      if (r.error || !r.data || !r.data.ok){ footErr(errText(r)); return; }
      forget('schedules'); forget('due'); toast('Recurring bill saved · next ' + r.data.next_due); schedulesDrawer();
    });
  });
}
VIEW.gastos = async function(){
  var r = range();
  var tr = tableRange('gastos', r);
  var res = await Promise.all([loadExpenses(tr.from, tr.to), loadPayouts(), loadDue(), ensureVendors()]);
  var exps = res[0], payouts = res[1], due = res[2], open = openPayouts(payouts);
  var host = document.createElement('div'), h = '';
  h += '<div class="tools"><div class="grow"><span class="hint">Bank and SINPE expenses later match the bank import; those paid with a register payout close that payout; credit expenses are paid from their row.</span></div><div><button type="button" class="ghost small" id="btnSched">Recurring bills</button></div><div><button type="button" id="btnNew">+ New expense</button></div></div>';
  if (!MIG.v34) h += '<div class="banner bad"><b>The database needs migration 0034.</b><span class="hint">Suppliers and their habits are not available until it is applied.</span></div>';
  if (due.length) h += '<div class="card" style="margin-bottom:1rem"><h2>Recurring bills due</h2><ul class="list">' + due.map(function(d){ return '<li><span class="t"><span class="mono">' + esc(d.next_due) + '</span> · ' + esc(d.description) + (d.vendor ? ' · ' + esc(d.vendor) : '') + (d.overdue ? ' ' + pill('p-bad', 'overdue') : '') + '</span><span class="mono">' + fmt(d.amount_crc) + '</span><button type="button" class="small" data-due="' + esc(d.id) + '">Register now</button></li>'; }).join('') + '</ul></div>';
  if (open.length) h += '<div class="card" style="margin-bottom:1rem"><h2>Register payouts waiting for their invoice</h2><p class="hint" style="margin:0 0 .5rem">Money a manager took from the drawer to pay a purchase. File its invoice as an expense (or as a supplier payment from Suppliers).</p><ul class="list">' + open.map(function(p){ var left = Number(p.amount_crc) - Number(p.documented_crc); return '<li><span class="t"><span class="mono">' + esc(p.date) + '</span> · ' + esc(p.reason) + ' <span class="hint">· ' + esc(p.staff_name) + '</span></span><span class="mono">' + fmt(left) + '</span><button type="button" class="small" data-payout="' + esc(p.id) + '">New expense</button></li>'; }).join('') + '</ul></div>';
  h += '<div id="xTable"></div>';
  host.innerHTML = h;
  var vendorFilter = VEND.filter(function(v){ return exps.some(function(e){ return e.vendor_id === v.id; }); }).map(function(v){ return [v.id, v.name]; });
  host.querySelector('#xTable').appendChild(table({id: 'gastos', rows: exps, dateKey: 'date', dated: true, defaultSort: 'date', pageSize: 10, onRow: expenseDetail,
    columns: [{key: 'date', label: 'Date', nw: true, render: function(x){ return '<span class="mono">' + esc(x.date) + '</span>'; }},
      {key: 'vendor_name', label: 'Supplier', text: function(x){ return (x.vendor_name || '') + ' ' + x.description; }, sortVal: function(x){ return (x.vendor_name || '') + ' ' + x.description; }, render: function(x){ return '<span>' + esc(x.vendor_name || '—') + '</span><span class="sub">' + esc(x.description) + '</span>'; }},
      {key: 'account', label: 'Category', nw: true, text: function(x){ return x.account + ' ' + (x.account_name || ''); }, render: function(x){ return tag('', x.account) + ' <span title="' + esc(x.account_name || '') + '">' + esc((x.account_name || '').length > 22 ? (x.account_name || '').slice(0, 21) + '…' : (x.account_name || '')) + '</span>'; }},
      {key: 'amount_crc', label: 'Total', num: true, sortVal: function(x){ return Number(x.amount_crc); }, render: function(x){ return '<span class="mono">' + fmt(x.amount_crc) + '</span>'; }},
      {key: 'iva_crc', label: 'IVA', num: true, sortVal: function(x){ return Number(x.iva_crc); }, render: function(x){ return '<span class="mono">' + fmt(x.iva_crc) + '</span>'; }},
      {key: 'paid_from', label: 'Paid with', text: function(x){ return pmName(x.paid_from); }, render: function(x){ return esc(PM_SHORT[x.paid_from] || pmName(x.paid_from)); }},
      {key: 'status', label: 'Status', nw: true, text: function(x){ return expenseStatus(x); }, sortVal: function(x){ return expenseStatus(x); }, render: expensePill},
      {key: 'receipt_path', label: 'Receipt', sort: false, render: function(x){ return x.receipt_path ? pill('p-ok', '✓') : x.voided_at ? '' : pill('p-bad', 'none'); }},
      {key: 'acc', label: '', sort: false, render: function(x){ return '<div class="actions">' + (expenseStatus(x) === 'credit' ? '<button type="button" class="small" data-act="pay">Pay now</button>' : '') + '</div>'; }}],
    filters: [{key: 'account', label: 'Category', options: expenseAccounts().map(function(a){ return [a.code, a.code + ' · ' + a.name]; })}, {key: 'vendor_id', label: 'Supplier', options: vendorFilter},
      {key: 'paid_from', label: 'Paid with', options: PM_EXPENSE.map(function(p){ return [p, pmName(p)]; })}, {key: 'status', label: 'Status', value: expenseStatus, options: [['paid', 'paid'], ['credit', 'on credit, open'], ['paid_credit', 'credit, paid'], ['voided', 'voided']]}],
    foot: function(rows){ var live = rows.filter(function(x){ return !x.voided_at; }); return ['', '', 'Total', '<span class="mono">' + fmt(sum(live, function(x){ return x.amount_crc; })) + '</span>', '<span class="mono">' + fmt(sum(live, function(x){ return x.iva_crc; })) + '</span>', '', '', '', '']; },
    onAct: function(act, x){ if (act === 'pay') payExpenseForm(x); },
    csv: function(rows){ return ['gastos-' + r.from + '-' + r.to + '.csv', [['date', 'supplier', 'description', 'account', 'total', 'iva', 'paid_from', 'status', 'open', 'invoice', 'invoice_date', 'voided', 'invoice_file']].concat(rows.map(function(x){ return [x.date, x.vendor_name, x.description, x.account, x.amount_crc, x.iva_crc, x.paid_from, expenseStatus(x), x.open_crc, x.invoice_no, x.invoice_date, x.voided_at ? 'yes' : '', x.receipt_path || '']; }))]; }}));
  host.querySelector('#btnNew').addEventListener('click', function(){ expenseForm(); });
  host.querySelector('#btnSched').addEventListener('click', function(){ schedulesDrawer(); });
  host.querySelectorAll('[data-payout]').forEach(function(b){ b.addEventListener('click', function(){ var p = payouts.filter(function(x){ return x.id === b.dataset.payout; })[0]; expenseForm({paid_from: 'payout', payout_id: p.id, description: p.reason, amount_crc: Math.round((Number(p.amount_crc) - Number(p.documented_crc)) * 100) / 100, date: p.date}); }); });
  host.querySelectorAll('[data-due]').forEach(function(b){ b.addEventListener('click', function(){ var d = due.filter(function(x){ return x.id === b.dataset.due; })[0]; expenseForm({schedule_id: d.id, period_key: d.period_key, request_id: d.request_id, vendor_id: d.vendor_id, description: d.description, account: d.account, amount_crc: d.amount_crc, iva_crc: d.iva_crc, paid_from: d.paid_from, date: today()}); }); });
  return host;
};

/* ---------- Suppliers: one list shared with Inventory; the card with contact, habits, balances and history ---------- */
function owedOf(v){ return Number(v.owed_invoices) + Number(v.owed_expenses); }
function vendorStatus(v){ return v.overdue ? 'overdue' : owedOf(v) > 0.005 ? 'current' : 'none'; }
function vendorPill(v){ var s = vendorStatus(v); return s === 'overdue' ? pill('p-bad', 'overdue') : s === 'current' ? pill('p-ok', 'current') : '<span class="hint">—</span>'; }
function habitText(v){ return (v.default_account ? v.default_account + ' · ' + (v.default_account_name || accountName(v.default_account)) : '—') + ' · IVA ' + (v.default_iva_rate != null ? Math.round(Number(v.default_iva_rate) * 100) + ' %' : '—') + ' · ' + (v.default_paid_from ? pmName(v.default_paid_from) : '—'); }
async function vendorCard(v){
  openDrawer(v.name, '<div class="loading">Loading…</div>', '');
  var t = today(), from = addDays(t, -365), vh;
  try { vh = await loadVendorHistory(v.id, from, t); } catch (e){ $('drawerBody').innerHTML = '<p class="err">' + esc(errText(e)) + '</p>'; return; }
  var V = vh.vendor, canEdit = KIND === 'owner';
  var li = function(a, b, c){ return '<li><span class="t">' + a + '</span><span class="mono">' + b + '</span>' + (c || '') + '</li>'; };
  var body = '<dl class="dl"><dt>Contact</dt><dd>' + esc([V.contact_name, V.phone, V.whatsapp ? 'WhatsApp ' + V.whatsapp : '', V.email].filter(Boolean).join(' · ') || '—') + '</dd>' +
    '<dt>ID number</dt><dd>' + esc(V.tax_id || '—') + '</dd><dt>Credit days</dt><dd>' + esc(V.credit_days != null ? V.credit_days : '30 (default)') + '</dd><dt>Delivery</dt><dd><span>' + esc((V.lead_days || 0) + ' days') + '</span>' + (V.order_days ? ' · <span>orders on</span> ' + esc(V.order_days) : '') + '</dd>' +
    (V.notes ? '<dt>Notes</dt><dd>' + esc(V.notes) + '</dd>' : '') + (V.payment_notes ? '<dt>How we pay</dt><dd>' + esc(V.payment_notes) + '</dd>' : '') + (V.active ? '' : '<dt>Status</dt><dd>' + pill('p-mute', 'inactive') + '</dd>') + '</dl>' +
    '<div class="tools" style="margin:.6rem 0 0">' + (canEdit ? '<div><button type="button" class="ghost small" id="vc-edit">Edit supplier</button></div>' : '') + '<div><button type="button" class="ghost small" id="vc-habits">Habits: ' + esc(habitText(V)) + '</button></div></div>';
  var ag = vh.aging || {};
  body += '<h3>Owed</h3><div class="grid kpis" style="gap:.5rem">' + [['Not due yet', ag.current, ''], ['1–30 days late', ag.d30, 'down'], ['31–60 days late', ag.d60, 'down'], ['Over 60 days late', ag.older, 'down']].map(function(b){ return '<div class="kpi" style="box-shadow:none;background:var(--row);padding:.6rem .7rem"><div class="l">' + esc(b[0]) + '</div><div class="v ' + (Number(b[1]) > 0 ? b[2] : '') + '" style="font-size:1.05rem">' + fmt(b[1]) + '</div></div>'; }).join('') + '</div>' +
    (Number(V.owed_expenses) > 0.005 ? '<p class="hint" style="margin:.5rem 0 0">Credit expenses still open: <span class="mono">' + fmt(V.owed_expenses) + '</span> (paid from <a href="#gastos">Expenses</a>).</p>' : '');
  body += '<h3>Last 12 months <span class="hint">· invoiced ' + fmt(vh.totals.invoiced) + ' · paid ' + fmt(vh.totals.paid) + ' · expenses ' + fmt(vh.totals.expenses) + ' · received ' + fmt(vh.totals.received) + '</span></h3>';
  if (vh.invoices.length) body += '<div class="eyebrow" style="margin:.4rem 0 .2rem">Invoices</div><ul class="list">' + vh.invoices.slice(0, 8).map(function(i){ return li('<span class="mono">' + esc(i.date) + '</span> · ' + esc(i.number) + ' <span class="hint">· due ' + esc(i.due_date) + (i.deliveries ? ' · ' + i.deliveries + ' deliveries' : '') + '</span>', fmt(i.total), i.voided ? pill('p-mute', 'voided') : Number(i.open) > 0.005 ? (i.due_date < t ? pill('p-bad', 'overdue') : pill('p-warn', 'owes ' + fmt(i.open))) + (canEdit || KIND === 'accountant' ? '<button type="button" class="ghost small" data-voidinv="' + esc(i.id) + '">Void</button>' : '') : pill('p-ok', 'paid')); }).join('') + '</ul>';
  if (vh.payments.length) body += '<div class="eyebrow" style="margin:.6rem 0 .2rem">Payments</div><ul class="list">' + vh.payments.slice(0, 8).map(function(p){ return li('<span class="mono">' + esc(p.date) + '</span> · ' + esc(pmName(p.paid_from)) + (p.reference ? ' <span class="hint">· ' + esc(p.reference) + '</span>' : '') + (p.invoices ? ' <span class="hint">· ' + esc(p.invoices) + '</span>' : ''), fmt(p.amount), p.voided ? pill('p-mute', 'voided') : '<button type="button" class="ghost small" data-voidpay="' + esc(p.id) + '">Void</button>'); }).join('') + '</ul>';
  if (vh.expenses.length) body += '<div class="eyebrow" style="margin:.6rem 0 .2rem">Expenses</div><ul class="list">' + vh.expenses.slice(0, 8).map(function(e){ return li('<span class="mono">' + esc(e.date) + '</span> · ' + esc(e.description), fmt(e.amount_crc), expensePill(e)); }).join('') + '</ul>';
  if (vh.orders.length) body += '<div class="eyebrow" style="margin:.6rem 0 .2rem">Orders</div><ul class="list">' + vh.orders.slice(0, 6).map(function(o){ return li('<span class="mono">' + esc(crDate(o.created_at)) + '</span> · Nº ' + esc(o.po_number || '') + ' <span class="hint">· ' + esc(o.lines) + ' lines' + (o.invoice_no ? ' · ' + esc(o.invoice_no) : '') + '</span>', fmt(o.received_crc || o.ordered_crc), tag('', o.status)); }).join('') + '<li><span class="t"></span><a href="#compras">Purchases ›</a></li></ul>';
  $('drawerBody').innerHTML = body;
  $('drawerFoot').innerHTML = '<button type="button" class="ghost small" id="vc-inv">New invoice</button><button type="button" class="ghost small" id="vc-exp">New expense</button>' + (Number(V.owed_invoices) > 0.005 ? '<button type="button" class="small" id="vc-pay">Record payment · ' + fmt(V.owed_invoices) + '</button>' : '');
  var B = $('drawerBody');
  var ed = B.querySelector('#vc-edit'); if (ed) ed.addEventListener('click', function(){ vendorForm(V, function(){ forget('vendors'); forget('vh'); ensureVendors().then(function(){ render(); vendorCard(VEND.filter(function(x){ return x.id === V.id; })[0] || V); }); }); });
  B.querySelector('#vc-habits').addEventListener('click', function(){ vendorDefaultsForm(V); });
  B.querySelectorAll('[data-voidinv]').forEach(function(b){ b.addEventListener('click', async function(){ var why = prompt('Why is this invoice voided?'); if (!why) return; var r = await db.rpc('supplier_invoice_void', {p_id: b.dataset.voidinv, p_reason: why}); if (r.error || !r.data || !r.data.ok){ toast(errText(r)); return; } toast('Invoice voided'); forget(); render(); vendorCard(V); }); });
  B.querySelectorAll('[data-voidpay]').forEach(function(b){ b.addEventListener('click', async function(){ var why = prompt('Why is this payment voided?'); if (!why) return; var r = await db.rpc('supplier_payment_void', {p_id: b.dataset.voidpay, p_reason: why}); if (r.error || !r.data || !r.data.ok){ toast(errText(r)); return; } toast('Payment voided'); forget(); render(); vendorCard(V); }); });
  $('vc-inv').addEventListener('click', function(){ invoiceForm(V); });
  $('vc-exp').addEventListener('click', function(){ expenseForm({vendor_id: V.id}); });
  var pb = $('vc-pay'); if (pb) pb.addEventListener('click', function(){ paymentForm(V); });
}
function vendorForm(v, done){
  v = v || {};
  openDrawer(v.id ? 'Edit supplier' : 'New supplier', '<form id="vfForm" class="form"><div class="full"><label for="vf-name">Name</label><input id="vf-name" maxlength="80" value="' + esc(v.name || '') + '"></div>' +
    '<div><label for="vf-contact">Contact person</label><input id="vf-contact" maxlength="80" value="' + esc(v.contact_name || '') + '"></div><div><label for="vf-phone">Phone</label><input id="vf-phone" inputmode="tel" maxlength="40" value="' + esc(v.phone || '') + '"></div>' +
    '<div><label for="vf-wa">WhatsApp</label><input id="vf-wa" inputmode="tel" maxlength="40" value="' + esc(v.whatsapp || '') + '"></div><div><label for="vf-email">Email</label><input id="vf-email" inputmode="email" maxlength="120" value="' + esc(v.email || '') + '"></div>' +
    '<div><label for="vf-tax">ID number (cédula)</label><input id="vf-tax" maxlength="30" value="' + esc(v.tax_id || '') + '"></div><div><label for="vf-credit">Credit days (empty = 30)</label><input id="vf-credit" type="number" inputmode="numeric" min="0" max="180" value="' + esc(v.credit_days != null ? v.credit_days : '') + '"></div>' +
    '<div><label for="vf-lead">Days to deliver</label><input id="vf-lead" type="number" inputmode="numeric" min="0" max="60" value="' + esc(v.lead_days != null ? v.lead_days : 2) + '"></div><div><label for="vf-days">Order days</label><input id="vf-days" maxlength="60" placeholder="Mon, Thu" value="' + esc(v.order_days || '') + '"></div>' +
    '<div class="full"><label for="vf-notes">Notes</label><textarea id="vf-notes" maxlength="500">' + esc(v.notes || '') + '</textarea></div>' + (v.id ? '<label class="check full"><input type="checkbox" id="vf-active"' + (v.active !== false ? ' checked' : '') + '> Active</label>' : '') + '</form><p class="hint">The same supplier Inventory uses to order: one record, seen from both sides. Only the owner with the phone code adds or changes suppliers.</p>',
    '<button type="button" class="ghost small" id="vf-cancel">Cancel</button><button type="button" id="vf-save">Save supplier</button>');
  var B = $('drawerBody');
  $('vf-cancel').addEventListener('click', function(){ if (v.id) vendorCard(v); else closeDrawer(); });
  $('vf-save').addEventListener('click', function(){
    busy(this, async function(){
      var act = B.querySelector('#vf-active');
      var r = await db.rpc('vendor_save', {p_vendor: {id: v.id || null, name: B.querySelector('#vf-name').value.trim(), contact_name: B.querySelector('#vf-contact').value, phone: B.querySelector('#vf-phone').value, whatsapp: B.querySelector('#vf-wa').value, email: B.querySelector('#vf-email').value, tax_id: B.querySelector('#vf-tax').value, credit_days: B.querySelector('#vf-credit').value === '' ? null : Number(B.querySelector('#vf-credit').value), lead_days: Number(B.querySelector('#vf-lead').value) || 0, order_days: B.querySelector('#vf-days').value, notes: B.querySelector('#vf-notes').value, active: act ? act.checked : true}});
      if (r.error || !r.data || !r.data.ok){ footErr(errText(r)); return; }
      forget('vendors'); forget('ap'); forget('vh'); toast('Supplier saved');
      await ensureVendors();
      var nv = VEND.filter(function(x){ return x.id === r.data.id; })[0];
      if (done) done(nv || {id: r.data.id, name: B.querySelector('#vf-name').value.trim()}); else { render(); if (nv) vendorCard(nv); else closeDrawer(); }
    });
  });
}
function vendorDefaultsForm(v){
  openDrawer('Habits of ' + v.name, '<form id="vdForm" class="form"><p class="hint full" style="margin:0">What «New expense» fills in by itself for this supplier. Leave a field empty and the form will ask for it each time.</p>' +
    '<div><label for="vd-cat">Category</label><select id="vd-cat"><option value="">— ask each time</option>' + accountOptions(v.default_account || '') + '</select></div>' +
    '<div><label for="vd-rate">IVA rate</label><select id="vd-rate"><option value="">— ask each time</option>' + rateOptions(v.default_iva_rate) + '</select></div>' +
    '<div><label for="vd-pm">Paid with</label><select id="vd-pm"><option value="">— ask each time</option>' + pmOptions(PM_EXPENSE, v.default_paid_from || '') + '</select></div>' +
    '<div class="full"><label for="vd-notes">How we pay this supplier (optional)</label><input id="vd-notes" maxlength="200" value="' + esc(v.payment_notes || '') + '"></div></form>',
    '<button type="button" class="ghost small" id="vd-cancel">Cancel</button><button type="button" id="vd-save">Save</button>');
  var B = $('drawerBody');
  $('vd-cancel').addEventListener('click', function(){ vendorCard(v); });
  $('vd-save').addEventListener('click', function(){
    busy(this, async function(){
      var r = await db.rpc('vendor_defaults_save', {p_vendor_id: v.id, p_defaults: {account: B.querySelector('#vd-cat').value || null, paid_from: B.querySelector('#vd-pm').value || null, iva_rate: B.querySelector('#vd-rate').value || null, payment_notes: B.querySelector('#vd-notes').value.trim() || null}});
      if (r.error || !r.data || !r.data.ok){ footErr(errText(r)); return; }
      forget('vendors'); forget('vh'); toast('Habits saved'); await ensureVendors(); render(); vendorCard(VEND.filter(function(x){ return x.id === v.id; })[0] || v);
    });
  });
}
/* the supplier's electronic invoice (Hacienda XML, versions 4.3 and 4.4): it only fills in the form; the person checks and saves. Read as data. */
function eInvoiceRead(text){
  var doc = new DOMParser().parseFromString(text, 'application/xml');
  if (doc.getElementsByTagName('parsererror').length) return {error: 'not_xml'};
  var root = doc.documentElement, kind = root ? root.localName : '';
  var one = function(el, name){ var n = el ? el.getElementsByTagNameNS('*', name) : []; return n.length ? n[0].textContent.trim() : ''; };
  var num = function(v){ var x = Number(String(v || '').replace(',', '.')); return isFinite(x) ? x : 0; };
  if (!/^(FacturaElectronica|TiqueteElectronico|NotaCreditoElectronica|NotaDebitoElectronica|FacturaElectronicaCompra)$/.test(kind)) return {error: 'not_einvoice'};
  var emisor = root.getElementsByTagNameNS('*', 'Emisor')[0], resumen = root.getElementsByTagNameNS('*', 'ResumenFactura')[0];
  var other = 0;
  Array.prototype.forEach.call(resumen ? resumen.getElementsByTagNameNS('*', 'TotalDesgloseImpuesto') : [], function(d){ if (one(d, 'Codigo') && one(d, 'Codigo') !== '01') other += num(one(d, 'TotalMontoImpuesto')); });
  return {kind: kind, key: one(root, 'Clave'), number: one(root, 'NumeroConsecutivo'), date: one(root, 'FechaEmision').slice(0, 10), vendor: one(emisor, 'Nombre'), vendorId: one(emisor, 'Numero'),
          currency: one(resumen, 'CodigoMoneda') || 'CRC', net: num(one(resumen, 'TotalVentaNeta')), tax: num(one(resumen, 'TotalImpuesto')), total: num(one(resumen, 'TotalComprobante')), charges: num(one(resumen, 'TotalOtrosCargos')), otherTax: other};
}
function plain(t){ return String(t || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/\b(s\.?\s?a|s\.?r\.?l|ltda|limitada|sociedad anonima)\b\.?/g, '').replace(/[^a-z0-9]+/g, ' ').trim(); }
async function invoiceForm(v){
  var ap = await loadAP(), req = uuid(), t = today();
  var recs = (ap.uninvoiced || []).filter(function(r){ return r.vendor_id === v.id; });
  openDrawer('New invoice · ' + v.name, '<form id="viForm" class="form">' +
    '<div class="full"><label>Fill in from the supplier\'s electronic invoice (XML file)</label><div class="attach"><button type="button" class="ghost small" id="vi-xmlBtn">Choose XML</button><span class="hint" id="vi-xmlMsg"></span><input type="file" id="vi-xml" accept=".xml,text/xml,application/xml"></div></div>' +
    '<div><label for="vi-num">Invoice Nº</label><input id="vi-num" maxlength="50"></div><div><label for="vi-date">Invoice date</label><input type="date" id="vi-date" value="' + t + '" max="' + t + '"></div>' +
    '<div><label for="vi-due">Due date</label><input type="date" id="vi-due" value="' + addDays(t, Number(v.credit_days != null ? v.credit_days : 30)) + '"></div><div></div>' +
    '<div><label for="vi-net">Amount before IVA (₡)</label><input id="vi-net" type="number" inputmode="decimal" min="0" step="any" data-keypad="amount"></div><div><label for="vi-iva">IVA on the invoice (₡)</label><input id="vi-iva" type="number" inputmode="decimal" min="0" step="any" value="0"></div>' +
    '<div class="full"><label>Deliveries of this supplier waiting for their invoice (tick the ones on it)</label>' + (recs.length ? recs.map(function(r){ return '<label class="check"><input type="checkbox" value="' + esc(r.id) + '" data-rec> ' + esc(crDate(r.received_at) + (r.po_number ? ' · Nº ' + r.po_number : '') + (r.invoice_no ? ' · ' + r.invoice_no : '') + ' · ' + fmt(r.total_crc)) + '</label>'; }).join('') : '<p class="hint" style="margin:0">None: this invoice is for something else (a service, equipment…).</p>') + '<p class="hint mono" id="vi-diff" style="margin:.3rem 0 0"></p></div>' +
    '<div class="full" id="vi-acctBox"><label for="vi-acct">What was it for (no delivery)</label><select id="vi-acct">' + (ap.accounts || []).map(function(a){ return '<option value="' + esc(a.code) + '"' + (a.code === v.default_account ? ' selected' : '') + '>' + esc(a.code + ' · ' + a.name) + '</option>'; }).join('') + '</select></div></form>',
    '<button type="button" class="ghost small" id="vi-cancel">Cancel</button><button type="button" id="vi-save">Save invoice</button>');
  var B = $('drawerBody');
  function checked(){ return Array.prototype.map.call(B.querySelectorAll('[data-rec]:checked'), function(i){ return i.value; }); }
  function diff(){ var ids = checked(), rec = 0; recs.forEach(function(r){ if (ids.indexOf(r.id) >= 0) rec += Number(r.total_crc); }); B.querySelector('#vi-acctBox').hidden = ids.length > 0; var net = Number(B.querySelector('#vi-net').value) || 0; B.querySelector('#vi-diff').textContent = ids.length ? 'Received at cost ' + fmt(rec) + (net ? ' · difference with the invoice ' + fmt(net - rec) : '') : ''; }
  B.querySelectorAll('[data-rec]').forEach(function(c){ c.addEventListener('change', diff); }); B.querySelector('#vi-net').addEventListener('input', diff); diff();
  B.querySelector('#vi-xmlBtn').addEventListener('click', function(){ B.querySelector('#vi-xml').click(); });
  B.querySelector('#vi-xml').addEventListener('change', async function(){
    var f = this.files && this.files[0], msg = B.querySelector('#vi-xmlMsg'); msg.textContent = ''; if (!f) return;
    var x = f.size > 2000000 ? {error: 'not_einvoice'} : eInvoiceRead(await f.text()); this.value = '';
    if (x.error){ msg.textContent = x.error === 'not_xml' ? 'That file is not an XML file.' : 'That file is not an electronic invoice from Hacienda.'; return; }
    if (x.kind === 'NotaCreditoElectronica' || x.kind === 'NotaDebitoElectronica'){ msg.textContent = 'That is a credit or debit note, not an invoice: record it by hand with the accountant.'; return; }
    if (x.currency !== 'CRC'){ msg.textContent = 'This invoice is in ' + x.currency + '. Invoices in dollars are recorded from Inventario → Pedidos → Recibir, with their exchange rate.'; return; }
    B.querySelector('#vi-num').value = x.number || x.key; if (x.date) B.querySelector('#vi-date').value = x.date;
    B.querySelector('#vi-net').value = x.net; B.querySelector('#vi-iva').value = x.tax - x.otherTax;
    var notes = ['Read from the XML: ' + x.vendor + (x.vendorId ? ' (' + x.vendorId + ')' : '') + ', total ' + fmt(x.total) + '.'];
    if (plain(x.vendor) && plain(v.name) && plain(x.vendor).indexOf(plain(v.name)) < 0 && plain(v.name).indexOf(plain(x.vendor)) < 0) notes.push('The issuer does not look like this supplier: check it.');
    if (x.charges) notes.push('The invoice also has other charges of ' + fmt(x.charges) + ' (not IVA): check them with the accountant.');
    if (x.otherTax) notes.push('It includes other taxes of ' + fmt(x.otherTax) + ' that are not IVA: they were left out of the IVA.');
    if (Math.abs(x.net + x.tax + x.charges - x.total) > 1) notes.push('Its total does not add up: check the invoice.');
    notes.push('Check the amounts, tick the deliveries on it, then save.'); msg.innerHTML = notes.map(function(n){ return '<span>' + esc(n) + '</span>'; }).join(' '); diff();
  });
  $('vi-cancel').addEventListener('click', function(){ vendorCard(v); });
  $('vi-save').addEventListener('click', function(){
    var ids = checked(), x = {vendor_id: v.id, number: B.querySelector('#vi-num').value.trim(), date: B.querySelector('#vi-date').value, due_date: B.querySelector('#vi-due').value || null, net_crc: B.querySelector('#vi-net').value === '' ? null : Number(B.querySelector('#vi-net').value), iva_crc: Number(B.querySelector('#vi-iva').value) || 0, receipt_ids: ids, account: ids.length ? null : B.querySelector('#vi-acct').value};
    if (!x.number || x.net_crc == null){ footErr('Write the invoice number and amount.'); return; }
    busy(this, async function(){
      var r = await db.rpc('supplier_invoice_save', {p_invoice: x, p_request_id: req});
      if (r.error || !r.data || !r.data.ok){ footErr(r.data && r.data.error === 'bad_account' ? 'Pick what the invoice was for.' : errText(r)); return; }
      forget(); toast('Invoice saved'); render(); vendorCard(v);
    });
  });
}
async function paymentForm(v){
  var ap = await loadAP(), payouts = await loadPayouts(), req = uuid(), t = today();
  var av = (ap.vendors || []).filter(function(x){ return x.vendor_id === v.id; })[0], invs = av ? av.invoices.filter(function(i){ return Number(i.open) > 0; }) : [], owed = av ? Number(av.total) : 0;
  openDrawer('Pay ' + v.name, '<form id="vpForm" class="form"><div class="full resolved">Owed to this supplier: <b class="mono">' + fmt(owed) + '</b> · never more than what is owed</div>' +
    '<div><label for="vp-amt">Amount (₡)</label><input id="vp-amt" class="big" type="number" inputmode="decimal" min="0" step="any" data-keypad="amount" value="' + esc(invs[0] ? invs[0].open : owed) + '"></div><div><label for="vp-date">Date</label><input type="date" id="vp-date" value="' + t + '" max="' + t + '"></div>' +
    '<div><label for="vp-pm">Paid with</label><select id="vp-pm">' + pmOptions(PM_PAY, 'bank') + '</select></div><div id="vp-payoutBox" hidden><label for="vp-payout">Which payout</label><select id="vp-payout">' + payoutOptions(payouts) + '</select></div>' +
    '<div><label for="vp-ref">Reference</label><input id="vp-ref" maxlength="80"></div><div><label for="vp-inv">Invoice to pay first</label><select id="vp-inv"><option value="">The oldest first</option>' + invs.map(function(i){ return '<option value="' + esc(i.id) + '">' + esc(i.number + ' · ' + fmt(i.open)) + '</option>'; }).join('') + '</select></div></form>',
    '<button type="button" class="ghost small" id="vp-cancel">Cancel</button><button type="button" id="vp-save">Record payment</button>');
  var B = $('drawerBody');
  B.querySelector('#vp-pm').addEventListener('change', function(){ B.querySelector('#vp-payoutBox').hidden = this.value !== 'payout'; });
  $('vp-cancel').addEventListener('click', function(){ vendorCard(v); });
  $('vp-save').addEventListener('click', function(){
    var amt = Number(B.querySelector('#vp-amt').value); if (!(amt > 0)){ footErr('Write the amount.'); return; }
    busy(this, async function(){
      var r = await db.rpc('supplier_payment_save', {p_payment: {vendor_id: v.id, amount_crc: amt, paid_from: B.querySelector('#vp-pm').value, date: B.querySelector('#vp-date').value, reference: B.querySelector('#vp-ref').value.trim() || null, invoice_ids: B.querySelector('#vp-inv').value ? [B.querySelector('#vp-inv').value] : [], payout_id: B.querySelector('#vp-pm').value === 'payout' ? (B.querySelector('#vp-payout').value || null) : null}, p_request_id: req});
      if (r.error || !r.data || !r.data.ok){ footErr(errText(r)); return; }
      forget(); toast('Payment recorded'); render(); vendorCard(v);
    });
  });
}
VIEW.proveedores = async function(){
  var res = await Promise.all([loadVendors(), loadAP()]), vl = res[0], ap = res[1];
  VEND = vl.vendors; var L = ap.ledger, parts = Number(L.invoices_open) + Number(L.received_not_invoiced) + Number(L.expenses_on_credit);
  var host = document.createElement('div');
  var agRows = (ap.vendors || []).filter(function(v){ return Number(v.total) > 0.005; });
  var tot = {current: 0, d30: 0, d60: 0, older: 0, total: 0}; agRows.forEach(function(v){ ['current', 'd30', 'd60', 'older', 'total'].forEach(function(k){ tot[k] += Number(v[k]); }); });
  host.innerHTML = '<div class="tools"><div class="grow"><span class="hint">The same list Inventory uses to order: one record, seen from both sides. Tap a supplier for its card, history and balances.</span></div>' + (vl.can_edit ? '<div><button type="button" id="btnVendor">+ Add supplier</button></div>' : '') + '</div><div id="vTable"></div>' +
    '<p class="note mono">Accounts payable in the books ' + esc(fmt(L.ap_balance)) + ' = open invoices ' + esc(fmt(L.invoices_open)) + ' + received not invoiced ' + esc(fmt(L.received_not_invoiced)) + ' + credit expenses open ' + esc(fmt(L.expenses_on_credit)) + (Math.abs(Number(L.ap_balance) - parts) < 0.5 ? ' ✓' : ' · <span>difference</span> ' + esc(fmt(Number(L.ap_balance) - parts)) + ': <span>days not posted yet, or entries by hand</span>') + '</p>';
  host.insertAdjacentHTML('beforeend', '<div class="card" style="margin-top:1rem"><h2>Owed by supplier, by age<span class="sp"></span><button type="button" class="ghost small" id="agCsv">Download CSV</button></h2>' +
    (agRows.length ? '<div class="tbox"><table class="narrow"><thead><tr><th>Supplier</th><th class="num">Not due yet</th><th class="num">1–30 days late</th><th class="num">31–60 days late</th><th class="num">Over 60 days late</th><th class="num">Total</th></tr></thead><tbody>' +
      agRows.map(function(v){ return '<tr><td>' + esc(v.name) + '</td>' + ['current', 'd30', 'd60', 'older', 'total'].map(function(k){ return '<td class="num mono">' + fmt(v[k]) + '</td>'; }).join('') + '</tr>'; }).join('') +
      '<tr class="total"><td>Total</td>' + ['current', 'd30', 'd60', 'older', 'total'].map(function(k){ return '<td class="num mono">' + fmt(tot[k]) + '</td>'; }).join('') + '</tr></tbody></table></div>' : '<p class="hint">Nothing owed on supplier invoices.</p>') + '</div>' +
    '<div class="card" style="margin-top:1rem"><h2>Invoices of the last 3 months</h2>' + ((ap.recent_invoices || []).length ? '<div class="tbox"><table><thead><tr><th>Date</th><th>Supplier</th><th>Invoice</th><th>Due</th><th class="num">Total</th><th class="num">Still owed</th><th></th></tr></thead><tbody>' +
      ap.recent_invoices.map(function(x){ return '<tr><td class="mono">' + esc(x.date) + '</td><td>' + esc(x.vendor) + '</td><td class="mono">' + esc(x.number) + (x.voided ? ' ' + tag('rev', 'voided') : '') + '</td><td class="mono">' + esc(x.due_date || '') + '</td><td class="num mono">' + fmt(x.total) + '</td><td class="num mono">' + (x.voided ? '' : fmt(x.open)) + '</td><td>' + (x.voided ? '' : '<button type="button" class="ghost small" data-voidinv="' + esc(x.id) + '">Void</button>') + '</td></tr>'; }).join('') + '</tbody></table></div>' : '<p class="hint">No invoices in the last three months.</p>') +
    '<h3>Payments of the last 3 months</h3>' + ((ap.payments || []).length ? '<div class="tbox"><table><thead><tr><th>Date</th><th>Supplier</th><th>Paid with</th><th>Reference</th><th>Invoices</th><th class="num">Amount</th><th></th></tr></thead><tbody>' +
      ap.payments.map(function(x){ return '<tr><td class="mono">' + esc(x.date) + '</td><td>' + esc(x.vendor) + '</td><td>' + esc(pmName(x.paid_from)) + '</td><td>' + esc(x.reference || '') + '</td><td class="mono">' + esc(x.invoices || '') + '</td><td class="num mono">' + fmt(x.amount) + '</td><td><button type="button" class="ghost small" data-voidpay="' + esc(x.id) + '">Void</button></td></tr>'; }).join('') + '</tbody></table></div>' : '<p class="hint">No payments in the last three months.</p>') + '</div>');
  host.querySelector('#agCsv').addEventListener('click', function(){ var out = [['supplier', 'not_due', 'late_1_30', 'late_31_60', 'late_over_60', 'total']].concat(agRows.map(function(v){ return [v.name, v.current, v.d30, v.d60, v.older, v.total]; })); (ap.vendors || []).forEach(function(v){ (v.invoices || []).forEach(function(i){ if (Number(i.open) > 0) out.push([v.name + ' · ' + i.number, i.date, i.due_date, '', '', i.open]); }); }); download('cuentas-por-pagar-' + (ap.as_of || today()) + '.csv', out); });
  host.querySelectorAll('[data-voidinv]').forEach(function(b){ b.addEventListener('click', async function(){ var why = prompt('Why is this invoice voided?'); if (!why) return; var r2 = await db.rpc('supplier_invoice_void', {p_id: b.dataset.voidinv, p_reason: why}); if (r2.error || !r2.data || !r2.data.ok){ toast(errText(r2)); return; } toast('Invoice voided'); forget(); render(); }); });
  host.querySelectorAll('[data-voidpay]').forEach(function(b){ b.addEventListener('click', async function(){ var why = prompt('Why is this payment voided?'); if (!why) return; var r2 = await db.rpc('supplier_payment_void', {p_id: b.dataset.voidpay, p_reason: why}); if (r2.error || !r2.data || !r2.data.ok){ toast(errText(r2)); return; } toast('Payment voided'); forget(); render(); }); });
  host.querySelector('#vTable').appendChild(table({id: 'prov', rows: VEND, defaultSort: 'owed', pageSize: 25, onRow: vendorCard,
    columns: [{key: 'name', label: 'Supplier', text: function(v){ return v.name + ' ' + (v.contact_name || ''); }, render: function(v){ return '<b>' + esc(v.name) + '</b>' + (v.active ? '' : ' ' + tag('', 'inactive')) + (v.contact_name ? '<span class="sub">' + esc(v.contact_name) + '</span>' : ''); }},
      {key: 'phone', label: 'Contact', text: function(v){ return [v.phone, v.whatsapp, v.email].filter(Boolean).join(' '); }, render: function(v){ return esc(v.phone || v.whatsapp || '—') + (v.email ? '<span class="sub">' + esc(v.email) + '</span>' : ''); }},
      {key: 'owed', label: 'Owed', num: true, sortVal: owedOf, render: function(v){ return '<span class="mono">' + fmt(owedOf(v)) + '</span>'; }},
      {key: 'status', label: 'Status', nw: true, text: vendorStatus, sortVal: vendorStatus, render: vendorPill},
      {key: 'last_purchase', label: 'Last purchase', nw: true, render: function(v){ return '<span class="mono">' + esc(v.last_purchase || '—') + '</span>'; }},
      {key: 'bought_12m', label: 'Bought, 12 months', num: true, sortVal: function(v){ return Number(v.bought_12m); }, render: function(v){ return '<span class="mono">' + fmt(v.bought_12m) + '</span>'; }},
      {key: 'credit_days', label: 'Credit days', num: true, render: function(v){ return esc(v.credit_days != null ? v.credit_days : '30'); }},
      {key: 'default_account', label: 'Habits', text: function(v){ return habitText(v); }, render: function(v){ return v.default_account || v.default_paid_from || v.default_iva_rate != null ? '<span class="hint">' + esc(habitText(v)) + '</span>' : '<span class="hint">—</span>'; }}],
    filters: [{key: 'status', label: 'Status', value: vendorStatus, options: [['overdue', 'overdue'], ['current', 'current'], ['none', 'nothing owed']]}, {key: 'active', label: 'Active', options: [['true', 'active'], ['false', 'inactive']]}],
    csv: function(rows){ return ['proveedores-' + today() + '.csv', [['name', 'contact', 'phone', 'whatsapp', 'email', 'tax_id', 'credit_days', 'owed_invoices', 'owed_expenses', 'last_purchase', 'bought_12m', 'default_account', 'default_paid_from', 'default_iva_rate', 'active']].concat(rows.map(function(v){ return [v.name, v.contact_name, v.phone, v.whatsapp, v.email, v.tax_id, v.credit_days, v.owed_invoices, v.owed_expenses, v.last_purchase, v.bought_12m, v.default_account, v.default_paid_from, v.default_iva_rate, v.active ? 'yes' : 'no']; }))]; }}));
  var bv = host.querySelector('#btnVendor'); if (bv) bv.addEventListener('click', function(){ vendorForm(null); });
  return host;
};

/* ---------- Purchases: orders with their deliveries, invoices and payments, as Inventory records them ---------- */
var STAGE = {draft: ['p-mute', 'draft'], sent: ['p-info', 'sent'], received: ['p-warn', 'received, no invoice'], invoiced: ['p-warn', 'invoiced'], paid: ['p-ok', 'paid'], cancelled: ['p-mute', 'cancelled']};
function stagePill(o){ var s = STAGE[o.stage] || ['p-mute', o.stage]; return pill(s[0], s[1]); }
function poDetail(o){
  var body = '<dl class="dl"><dt>Order</dt><dd>Nº ' + esc(o.po_number || '—') + ' · ' + esc(o.status) + '</dd><dt>Supplier</dt><dd>' + esc(o.vendor || '—') + '</dd><dt>Created</dt><dd class="mono">' + esc(crDate(o.created_at)) + (o.by_name ? ' · ' + esc(o.by_name) : '') + '</dd>' +
    (o.sent_at ? '<dt>Sent</dt><dd class="mono">' + esc(crDate(o.sent_at)) + '</dd>' : '') + (o.expected_on ? '<dt>Expected</dt><dd class="mono">' + esc(o.expected_on) + '</dd>' : '') +
    '<dt>Items</dt><dd>' + esc(o.items || '—') + (o.lines > 4 ? ' … (' + o.lines + ' lines)' : '') + '</dd><dt>Ordered at cost</dt><dd class="mono">' + fmt(o.ordered_crc) + '</dd><dt>Received at cost</dt><dd class="mono">' + fmt(o.received_crc) + '</dd>' + (o.note ? '<dt>Note</dt><dd>' + esc(o.note) + '</dd>' : '') + '<dt>Stage</dt><dd>' + stagePill(o) + '</dd></dl>';
  body += '<h3>Deliveries</h3>' + (o.receipts.length ? '<ul class="list">' + o.receipts.map(function(r){ return '<li><span class="t"><span class="mono">' + esc(crDate(r.received_at)) + '</span>' + (r.by_name ? ' · ' + esc(r.by_name) : '') + ' <span class="hint">· <span>' + esc({pending: 'invoice pending', confirmed: 'invoice confirmed', waiting: 'invoice waiting'}[r.invoice_status] || r.invoice_status) + '</span>' + (r.invoice_no ? ' · ' + esc(r.invoice_no) : '') + (r.settled_at ? ' · <span>settled</span>' : '') + '</span></span><span class="mono">' + fmt(r.total_crc) + '</span></li>'; }).join('') + '</ul>' : '<p class="hint">Not received yet. Receiving (with the PIN) stays in Inventory.</p>');
  body += '<h3>Invoices</h3>' + (o.invoices.length ? '<ul class="list">' + o.invoices.map(function(i){ return '<li><span class="t">' + esc(i.number) + ' <span class="hint">· ' + esc(i.date) + ' · due ' + esc(i.due_date) + '</span></span><span class="mono">' + fmt(i.total_crc) + '</span>' + (i.voided ? pill('p-mute', 'voided') : Number(i.open_crc) > 0.005 ? pill('p-warn', 'owes ' + fmt(i.open_crc)) : pill('p-ok', 'paid')) + '</li>'; }).join('') + '</ul>' : '<p class="hint">' + (o.receipts.length ? 'Waiting for the invoice: the delivery is owed until it arrives (D-014).' : '—') + '</p>');
  if (Number(o.paid_crc) > 0) body += '<p class="note"><span>Paid on these invoices:</span> <span class="mono">' + fmt(o.paid_crc) + '</span></p>';
  body += '<p class="hint">What Inventory receives is owed until its invoice arrives; the invoice settles the delivery and price differences never touch the inventory account.</p>';
  openDrawer('Order Nº ' + (o.po_number || ''), body, o.stage === 'received' ? '<button type="button" class="small" id="po-inv">New invoice</button>' : o.stage === 'invoiced' ? '<button type="button" class="small" id="po-pay">Record payment</button>' : (o.stage === 'sent' || o.stage === 'draft') && KIND === 'owner' ? '<a class="ghost small" href="inventory.html" style="display:inline-flex;align-items:center;padding:.4em .9em;border:1.5px solid var(--muted);border-radius:10px;text-decoration:none">Receive in Inventory →</a>' : '');
  var vi = $('po-inv'), vp = $('po-pay');
  if (vi) vi.addEventListener('click', function(){ ensureVendors().then(function(){ var v = VEND.filter(function(x){ return x.id === o.vendor_id; })[0]; if (v) invoiceForm(v); else toast(ERR.no_vendor); }); });
  if (vp) vp.addEventListener('click', function(){ ensureVendors().then(function(){ var v = VEND.filter(function(x){ return x.id === o.vendor_id; })[0]; if (v) paymentForm(v); else toast(ERR.no_vendor); }); });
}
VIEW.compras = async function(){
  var r = range(), tr = tableRange('po', r), orders = await loadPurchases(tr.from, tr.to); await ensureVendors();
  var host = document.createElement('div');
  host.innerHTML = '<div class="banner"><b>Purchases ↔ Suppliers ↔ Inventory</b><span class="hint">Orders and deliveries are made in Inventory (with the PIN). Here each order shows its deliveries, invoice and payments; the invoice and the payment can be recorded from here.</span></div><div id="poTable"></div>';
  host.querySelector('#poTable').appendChild(table({id: 'po', rows: orders, dateKey: 'created_at', dated: true, defaultSort: 'created_at', pageSize: 10, onRow: poDetail,
    columns: [{key: 'po_number', label: 'Order', nw: true, sortVal: function(o){ return Number(o.po_number) || 0; }, render: function(o){ return '<b class="mono">' + esc(o.po_number || '—') + '</b>'; }},
      {key: 'created_at', label: 'Date', nw: true, render: function(o){ return '<span class="mono">' + esc(crDate(o.created_at)) + '</span>'; }},
      {key: 'vendor', label: 'Supplier', text: function(o){ return (o.vendor || '') + ' ' + (o.items || ''); }, render: function(o){ return esc(o.vendor || '—') + '<span class="sub">' + esc(o.items || '') + '</span>'; }},
      {key: 'received_crc', label: 'Total', num: true, sortVal: function(o){ return Number(o.received_crc) || Number(o.ordered_crc); }, render: function(o){ return '<span class="mono">' + fmt(Number(o.received_crc) || Number(o.ordered_crc)) + '</span>'; }},
      {key: 'receipts', label: 'Inventory', nw: true, sort: false, render: function(o){ return o.receipts.length ? pill('p-ok', 'received') : o.stage === 'cancelled' ? '' : pill('p-mute', 'pending'); }},
      {key: 'invoices', label: 'Invoice', nw: true, sort: false, render: function(o){ return o.invoices.length ? '<span class="mono">' + esc(o.invoices.map(function(i){ return i.number; }).join(', ')) + '</span>' : '<span class="hint">—</span>'; }},
      {key: 'stage', label: 'Stage', nw: true, render: stagePill},
      {key: 'acc', label: '', sort: false, render: function(o){ return '<div class="actions">' + (o.stage === 'received' ? '<button type="button" class="small" data-act="inv">New invoice</button>' : o.stage === 'invoiced' ? '<button type="button" class="small" data-act="pay">Pay now</button>' : '') + '</div>'; }}],
    filters: [{key: 'stage', label: 'Stage', options: Object.keys(STAGE).map(function(k){ return [k, STAGE[k][1]]; })}, {key: 'vendor_id', label: 'Supplier', options: VEND.filter(function(v){ return orders.some(function(o){ return o.vendor_id === v.id; }); }).map(function(v){ return [v.id, v.name]; })}],
    onAct: function(act, o){ var v = VEND.filter(function(x){ return x.id === o.vendor_id; })[0]; if (!v){ toast(ERR.no_vendor); return; } if (act === 'inv') invoiceForm(v); else paymentForm(v); },
    csv: function(rows){ return ['compras-' + r.from + '-' + r.to + '.csv', [['order', 'date', 'supplier', 'items', 'ordered_crc', 'received_crc', 'invoices', 'paid_crc', 'stage']].concat(rows.map(function(o){ return [o.po_number, crDate(o.created_at), o.vendor, o.items, o.ordered_crc, o.received_crc, o.invoices.map(function(i){ return i.number; }).join(' '), o.paid_crc, o.stage]; }))]; }}));
  return host;
};

/* ---------- Bank and cash ---------- */
var BANK_SUB = 'cash', BANK_ACCT = null;
VIEW.banco = async function(){
  var host = document.createElement('div');
  host.innerHTML = '<div class="subtabs" id="bankTabs"><button type="button" data-s="cash" aria-pressed="' + (BANK_SUB === 'cash') + '">Cash by day</button><button type="button" data-s="bank" aria-pressed="' + (BANK_SUB === 'bank') + '">Bank accounts</button></div><div id="bankBody"><div class="loading">Loading…</div></div>';
  host.querySelectorAll('#bankTabs button').forEach(function(b){ b.addEventListener('click', function(){ BANK_SUB = b.dataset.s; host.querySelectorAll('#bankTabs button').forEach(function(x){ x.setAttribute('aria-pressed', String(x === b)); }); drawBankBody(host.querySelector('#bankBody')); }); });
  await drawBankBody(host.querySelector('#bankBody'));
  return host;
};
async function drawBankBody(box){
  var mine = box._seq = (box._seq || 0) + 1;   /* two quick taps: only the last one draws */
  box.innerHTML = '<div class="loading">Loading…</div>';
  try { if (BANK_SUB === 'cash') await drawCash(box, mine); else await drawBank(box, mine); if (mine !== box._seq) return; HG_CHARTS.mount(box); }
  catch (e){ if (mine !== box._seq) return; box.innerHTML = '<div class="banner bad"><b>Could not load.</b><span class="hint">' + esc(errText(e)) + '</span><span class="sp"></span><button type="button" class="ghost small" data-retry>Try again</button></div>'; box.querySelector('[data-retry]').addEventListener('click', function(){ forget('bank:'); forget('cash'); drawBankBody(box); }); }
}
async function drawCash(box, mine){
  var r = range(), tr = tableRange('cash', r), days = await loadCashDays(tr.from, tr.to), moves = null;
  if (KIND === 'owner'){ try { moves = await rpc('register_cash_moves'); } catch (e){ moves = null; } }
  var rows = days.map(function(d){ return Object.assign({}, d, {pending: isPending(d.date)}); });
  var h = '<div class="card"><h2>Cash by day <span class="hint">· the drawer in colones and dollars</span></h2><div id="cashT"></div></div>';
  if (moves && moves.moves) h += '<div class="card" style="margin-top:1rem"><h2><span>Drawer movements of</span> <span class="mono">' + esc(moves.business_date || today()) + '</span> <span class="hint">· owner only</span></h2>' + (moves.moves.length ? '<ul class="list">' + moves.moves.map(function(m){ return '<li><span class="t"><span class="mono">' + esc(String(m.at).slice(11, 16)) + '</span> · ' + esc(m.purpose) + (m.reason ? ' · ' + esc(m.reason) : '') + (m.staff_name ? ' <span class="hint">· ' + esc(m.staff_name) + '</span>' : '') + (m.voided_at ? ' ' + tag('rev', 'voided') : '') + '</span><span class="mono">' + (m.direction === 'out' ? '−' : '') + (m.currency === 'USD' ? fmtUsd(m.amount) : fmt(m.amount)) + '</span></li>'; }).join('') + '</ul>' : '<p class="hint">No drawer movements today.</p>') + '</div>';
  if (mine !== undefined && mine !== box._seq) return;   /* a later tap on the other tab wins */
  box.innerHTML = h;
  var money = function(v){ return v == null ? '<span class="hint">—</span>' : '<span class="mono">' + fmt(v) + '</span>'; };
  box.querySelector('#cashT').appendChild(table({id: 'cash', rows: rows, dateKey: 'date', dated: true, defaultSort: 'date', search: false, pageSize: 10, onRow: dayDetail,
    columns: [{key: 'date', label: 'Day', nw: true, render: function(d){ return '<span class="mono">' + esc(d.date) + '</span>' + (d.opened === false ? ' ' + tag('', 'no register') : !d.closed ? ' ' + tag('est', 'open') : ''); }},
      {key: 'float_crc', label: 'Float', num: true, render: function(d){ return money(d.float_crc); }}, {key: 'sales_crc', label: 'Cash sales', num: true, render: function(d){ return money(d.sales_crc); }},
      {key: 'in_crc', label: 'Money in', num: true, render: function(d){ return money(d.in_crc); }}, {key: 'out_crc', label: 'Money out', num: true, render: function(d){ return money(d.out_crc); }},
      {key: 'expected_crc', label: 'Expected', num: true, render: function(d){ return money(d.expected_crc); }}, {key: 'counted_crc', label: 'Counted', num: true, render: function(d){ return d.opened === false ? '' : d.counted_crc == null ? '<span class="hint">not counted</span>' : money(d.counted_crc); }},
      {key: 'diff_crc', label: 'Difference', num: true, render: function(d){ return !d.closed || d.diff_crc == null ? '' : '<span class="mono ' + (Math.abs(Number(d.diff_crc)) >= 1 ? (Number(d.diff_crc) < 0 ? 'down' : 'up') : '') + '">' + fmt(d.diff_crc) + '</span>'; }},
      {key: 'usd', label: 'Dollars', sort: false, nw: true, render: function(d){ return Number(d.float_usd) || Number(d.sales_usd) || d.counted_usd != null ? '<span class="mono">' + fmtUsd(d.sales_usd) + (d.diff_usd != null ? ' · diff ' + fmtUsd(d.diff_usd) : '') + '</span>' : '<span class="hint">—</span>'; }}],
    csv: function(rows){ return ['caja-' + r.from + '-' + r.to + '.csv', [['day', 'closed', 'float_crc', 'cash_sales_crc', 'in_crc', 'out_crc', 'expected_crc', 'counted_crc', 'diff_crc', 'float_usd', 'cash_sales_usd', 'in_usd', 'out_usd', 'expected_usd', 'counted_usd', 'diff_usd', 'fx_rate']].concat(rows.map(function(d){ return [d.date, d.closed ? 'yes' : 'no', d.float_crc, d.sales_crc, d.in_crc, d.out_crc, d.expected_crc, d.counted_crc, d.diff_crc, d.float_usd, d.sales_usd, d.in_usd, d.out_usd, d.expected_usd, d.counted_usd, d.diff_usd, d.fx_rate]; }))]; }}));
}
function bkMoney(acct, v){ return acct && acct.currency === 'USD' ? fmtUsd(v) : fmt(v); }
async function drawBank(box, mine){
  var r = range(), from = r.from < addDays(today(), -60) ? r.from : addDays(today(), -60), B = await loadBank(BANK_ACCT, from, today());
  var accts = B.accounts || [];
  if (!BANK_ACCT && accts.length){ BANK_ACCT = accts[0].id; forget('bank:'); B = await loadBank(BANK_ACCT, from, today()); }
  var A = B.account, S = B.summary || {};
  var h = '<div class="banner"><b>Bank accounts</b><span class="hint">There is no connection to the bank: the statement is imported from the CSV the bank itself gives, and the system suggests which payment or deposit each movement matches.</span></div>';
  h += '<div class="tools"><div><label for="bkAcct">Account</label><select id="bkAcct">' + (accts.length ? accts.map(function(a){ return '<option value="' + esc(a.id) + '"' + (a.id === BANK_ACCT ? ' selected' : '') + '>' + esc(a.name + (a.last4 ? ' ·· ' + a.last4 : '') + (a.currency === 'USD' ? ' ($)' : '')) + '</option>'; }).join('') : '<option value="">No bank accounts yet</option>') + '</select></div>' +
    (A ? '<div><button type="button" class="small" id="bkImportBtn">Import the bank\'s CSV</button></div><div><button type="button" class="ghost small" id="bkAuto">Match automatically</button></div>' : '') + '<div><button type="button" class="ghost small" id="bkNew">+ Bank account</button></div></div>';
  if (A) h += '<div class="grid kpis" style="margin-bottom:1rem">' + kpi(A.name + (A.last4 ? ' ·· ' + A.last4 : ''), bkMoney(A, S.statement_balance), undefined, undefined, 'bank', '<span class="hint">' + (S.statement_balance == null ? 'no statement yet' : 'statement of ' + esc(S.statement_day)) + '</span>') + kpi('In the books · ' + A.gl_account, bkMoney(A, S.book_balance), undefined, undefined, 'books') + kpi('To reconcile on the statement', bkMoney(A, S.open_statement)) + kpi('In the books only', bkMoney(A, S.book_only)) + '</div>';
  h += '<div class="card"><h2>Movements</h2><p class="hint" style="margin:0 0 .6rem">Match joins a bank line with what is already in the books; Post creates the entry that is missing (a fee, a deposit); Ignore leaves it out with a note; Undo reverses what was posted or reopens what was matched.</p><div id="bkT"></div></div>';
  if (A) h += '<div class="card" style="margin-top:1rem"><h2>In the books, not on the statement</h2>' + ((B.book_only || []).length ? '<ul class="list">' + B.book_only.map(function(x){ return '<li><span class="t"><span class="mono">' + esc(x.date) + '</span> · Nº ' + esc(x.entry_no) + ' · ' + esc(x.memo) + '</span><span class="mono">' + bkMoney(A, x.amount) + '</span><span class="hint">waiting for the next statement</span></li>'; }).join('') + '</ul>' : '<p class="hint">Nothing: every entry of the period appears on the statement.</p>') + '</div>';
  if (mine !== undefined && mine !== box._seq) return;   /* a later tap on the other tab wins */
  box.innerHTML = h;
  var lines = (B.lines || []).map(function(l){ return Object.assign({}, l, {amountN: Number(l.amount)}); });
  box.querySelector('#bkT').appendChild(table({id: 'bank', rows: lines, dateKey: 'date', defaultSort: 'date', pageSize: 10, empty: A ? 'No movements in this range: import the statement.' : 'Add a bank account first.', onRow: function(l){ bankLineDetail(A, l); },
    columns: [{key: 'date', label: 'Date', nw: true, render: function(l){ return '<span class="mono">' + esc(l.date) + '</span>'; }},
      {key: 'description', label: 'Movement', text: function(l){ return l.description + ' ' + (l.reference || ''); }, render: function(l){ return esc(l.description) + (l.reference ? '<span class="sub">' + esc(l.reference) + '</span>' : ''); }},
      {key: 'amountN', label: 'Amount', num: true, render: function(l){ return '<span class="mono ' + (l.amountN < 0 ? 'down' : '') + '">' + bkMoney(A, l.amount) + '</span>'; }},
      {key: 'suggest', label: 'In the books', sort: false, render: function(l){ return l.status === 'open' ? ((l.suggest || []).length ? '<span class="hint">suggested: ' + esc((l.suggest || []).map(function(s){ return 'Nº ' + s.entry_no + ' · ' + s.memo; }).join(' | ')) + '</span>' : '<span class="hint">nothing in the books · post it</span>') : l.status === 'ignored' ? '<span class="hint">' + esc(l.note || '') + '</span>' : (l.ledger ? '<span class="hint">Nº ' + esc(l.ledger.entry_no) + ' · ' + esc(l.ledger.memo) + '</span>' : ''); }},
      {key: 'status', label: 'Status', nw: true, text: function(l){ return l.status; }, render: function(l){ return l.status === 'open' ? pill('p-warn', 'to reconcile') : l.status === 'ignored' ? pill('p-mute', 'ignored') : pill('p-ok', l.status === 'posted' ? 'posted' : 'matched'); }},
      {key: 'acc', label: '', sort: false, render: function(l){ return '<div class="actions">' + (l.status === 'open' ? ((l.suggest || []).length ? '<button type="button" class="small" data-act="match">Match</button>' : '') + '<button type="button" class="ghost small" data-act="post">Post…</button><button type="button" class="ghost small" data-act="ignore">Ignore</button>' : '<button type="button" class="ghost small" data-act="undo">Undo</button>') + '</div>'; }}],
    filters: [{key: 'status', label: 'Status', options: [['open', 'to reconcile'], ['matched', 'matched'], ['posted', 'posted'], ['ignored', 'ignored']]}],
    onAct: function(act, l, btn){ bankAct(A, l, act, btn); },
    csv: function(rows){ return ['banco-' + (A ? A.name.replace(/\s+/g, '_') : '') + '-' + today() + '.csv', [['date', 'description', 'reference', 'amount', 'status', 'entry', 'note']].concat(rows.map(function(l){ return [l.date, l.description, l.reference, l.amount, l.status, l.ledger ? l.ledger.entry_no : '', l.note || '']; }))]; }}));
  box.querySelector('#bkAcct').addEventListener('change', function(){ BANK_ACCT = this.value || null; forget('bank:'); drawBankBody(box); });
  var ib = box.querySelector('#bkImportBtn'); if (ib) ib.addEventListener('click', function(){ bankImportDrawer(A, box); });
  var ab = box.querySelector('#bkAuto'); if (ab) ab.addEventListener('click', function(){ busy(ab, async function(){ var r2 = await db.rpc('bank_auto_match', {p_account_id: A.id}); if (r2.error || !r2.data || !r2.data.ok){ toast(errText(r2)); return; } toast(r2.data.matched + ' matched'); forget('bank:'); forget('cashpos'); drawBankBody(box); }); });
  box.querySelector('#bkNew').addEventListener('click', function(){ bankAccountForm(B, box); });
}
function bankLineDetail(A, l){
  openDrawer(l.description, '<dl class="dl"><dt>Date</dt><dd class="mono">' + esc(l.date) + '</dd><dt>Amount</dt><dd class="mono">' + bkMoney(A, l.amount) + '</dd>' + (l.reference ? '<dt>Reference</dt><dd>' + esc(l.reference) + '</dd>' : '') + (l.balance != null ? '<dt>Balance after</dt><dd class="mono">' + bkMoney(A, l.balance) + '</dd>' : '') + '<dt>Status</dt><dd>' + esc(l.status) + (l.ledger ? ' · Nº ' + esc(l.ledger.entry_no) + ' · ' + esc(l.ledger.memo) : '') + (l.note ? ' · ' + esc(l.note) : '') + '</dd>' + (l.done_by ? '<dt>By</dt><dd>' + esc(l.done_by) + '</dd>' : '') + '</dl>' +
    (l.status === 'open' && (l.suggest || []).length ? '<h3>Suggested matches</h3><ul class="list">' + l.suggest.map(function(s){ return '<li><span class="t">Nº ' + esc(s.entry_no) + ' · <span class="mono">' + esc(s.date) + '</span> · ' + esc(s.memo) + '</span><button type="button" class="small" data-match="' + esc(s.line_id) + '">Match</button></li>'; }).join('') + '</ul>' : ''),
    l.status === 'open' ? '<button type="button" class="ghost small" data-act="ignore">Ignore</button><button type="button" class="small" data-act="post">Post…</button>' : '<button type="button" class="ghost small" data-act="undo">Undo</button>');
  $('drawerBody').querySelectorAll('[data-match]').forEach(function(b){ b.addEventListener('click', function(){ busy(b, async function(){ var r = await db.rpc('bank_match', {p_line_id: l.id, p_ledger_line_id: Number(b.dataset.match)}); if (r.error || !r.data || !r.data.ok){ footErr(errText(r)); return; } toast('Matched'); closeDrawer(); forget('bank:'); forget('cashpos'); render(); }); }); });
  $('drawerFoot').querySelectorAll('[data-act]').forEach(function(b){ b.addEventListener('click', function(){ bankAct(A, l, b.dataset.act, b); }); });
}
async function bankAct(A, l, act, btn){
  if (act === 'match'){ var s = (l.suggest || [])[0]; if (!s) return; await busy(btn, async function(){ var r = await db.rpc('bank_match', {p_line_id: l.id, p_ledger_line_id: s.line_id}); if (r.error || !r.data || !r.data.ok){ toast(errText(r)); return; } toast('Matched'); }); }
  else if (act === 'ignore'){ var why = prompt('Why is it left out?'); if (!why) return; await busy(btn, async function(){ var r = await db.rpc('bank_ignore', {p_line_id: l.id, p_note: why}); if (r.error || !r.data || !r.data.ok){ toast(errText(r)); return; } toast('Ignored'); }); }
  else if (act === 'undo'){ await busy(btn, async function(){ var r = await db.rpc('bank_undo', {p_line_id: l.id}); if (r.error || !r.data || !r.data.ok){ toast(errText(r)); return; } toast('Undone'); }); }
  else if (act === 'post'){ bankPostForm(A, l); return; }
  closeDrawer(); forget('bank:'); forget('cashpos'); forget('journal'); render();
}
/* post a movement the books do not have: one account, or two (a card deposit: the card sales and the fee) */
async function bankPostForm(A, l){
  var B = await loadBank(A.id, addDays(today(), -1), today()), opts = (B.post_accounts || []).map(function(a){ return '<option value="' + esc(a.code) + '">' + esc(a.code + ' · ' + a.name) + '</option>'; }).join('');
  openDrawer('Post from the bank', '<form id="bpForm" class="form"><div class="full resolved"><span class="mono">' + esc(l.date) + '</span> · ' + esc(l.description) + ' · <b class="mono">' + bkMoney(A, l.amount) + '</b></div>' +
    '<div><label for="bp-a1">Account</label><select id="bp-a1"><option value="">—</option>' + opts + '</select></div><div><label for="bp-v1">Amount</label><input id="bp-v1" type="number" step="any" value="' + esc(l.amount) + '"></div>' +
    '<div><label for="bp-a2">Second account (optional)</label><select id="bp-a2"><option value="">—</option>' + opts + '</select></div><div><label for="bp-v2">Amount</label><input id="bp-v2" type="number" step="any"></div>' +
    '<div class="full"><label for="bp-memo">Description</label><input id="bp-memo" maxlength="200" value="' + esc(l.description) + '"></div><p class="hint full" style="margin:0">A fee or a service paid from the bank can also be recorded as an expense with its receipt: the bank line then matches it. The parts must add up to the bank\'s amount.</p></form>',
    '<button type="button" class="ghost small" id="bp-cancel">Cancel</button><button type="button" class="ghost small" id="bp-expense">Record as expense</button><button type="button" id="bp-save">Post</button>');
  var D = $('drawerBody');
  $('bp-cancel').addEventListener('click', closeDrawer);
  $('bp-expense').addEventListener('click', function(){ expenseForm({paid_from: 'bank', amount_crc: Math.abs(Number(l.amount)), date: l.date, description: l.description}); });
  $('bp-save').addEventListener('click', function(){
    var parts = [{account: D.querySelector('#bp-a1').value, amount: Number(D.querySelector('#bp-v1').value)}];
    if (D.querySelector('#bp-a2').value) parts.push({account: D.querySelector('#bp-a2').value, amount: Number(D.querySelector('#bp-v2').value)});
    if (Math.abs(sum(parts, function(p){ return p.amount; }) - Number(l.amount)) > 0.001){ footErr('The parts must add up to ' + bkMoney(A, l.amount) + '.'); return; }
    busy(this, async function(){ var r = await db.rpc('bank_post', {p_line_id: l.id, p_parts: parts, p_memo: D.querySelector('#bp-memo').value.trim() || null}); if (r.error || !r.data || !r.data.ok){ footErr(r.data && r.data.error === 'bad_account' ? 'Pick the accounts (never the bank\'s own account).' : errText(r)); return; } toast('Posted'); closeDrawer(); forget('bank:'); forget('cashpos'); forget('journal'); render(); });
  });
}
function bankAccountForm(B, box){
  openDrawer('New bank account', '<form id="bkForm" class="form"><div><label for="bk-name">Name</label><input id="bk-name" maxlength="60" placeholder="BCR colones"></div><div><label for="bk-bank">Bank</label><input id="bk-bank" maxlength="60"></div><div><label for="bk-cur">Currency</label><select id="bk-cur"><option value="CRC">Colones (₡)</option></select></div><div><label for="bk-last4">Last 4 digits</label><input id="bk-last4" inputmode="numeric" maxlength="4"></div><div class="full"><label for="bk-gl">Account in the books</label><select id="bk-gl">' + (B.gl_accounts || []).map(function(a){ return '<option value="' + esc(a.code) + '">' + esc(a.code + ' · ' + a.name) + '</option>'; }).join('') + '</select></div><p class="hint full" style="margin:0">Dollar accounts come later (A-06): their movements must be valued in colones first.</p></form>', '<button type="button" class="ghost small" id="bk-cancel">Cancel</button><button type="button" id="bk-save">Save</button>');
  var D = $('drawerBody'); $('bk-cancel').addEventListener('click', closeDrawer);
  $('bk-save').addEventListener('click', function(){ busy(this, async function(){ var r = await db.rpc('bank_account_save', {p_account: {name: D.querySelector('#bk-name').value.trim(), bank: D.querySelector('#bk-bank').value.trim(), currency: D.querySelector('#bk-cur').value, last4: D.querySelector('#bk-last4').value.trim(), gl_account: D.querySelector('#bk-gl').value}}); if (r.error || !r.data || !r.data.ok){ footErr(r.data && r.data.error === 'bad_account' ? 'Pick a cash or bank account of the books.' : errText(r)); return; } BANK_ACCT = r.data.id; closeDrawer(); forget('bank:'); forget('cashpos'); toast('Bank account saved'); drawBankBody(box); }); });
}
/* the bank's CSV, read here: separator and decimal style found from the file; the columns are picked once per account */
function csvParse(text){
  var first = text.split(/\r?\n/).slice(0, 5).join('\n'), seps = [';', ',', '\t'], sep = seps.reduce(function(b, c){ return first.split(c).length > first.split(b).length ? c : b; }, ',');
  var rows = [], row = [], cur = '', q = false;
  for (var i = 0; i < text.length; i++){
    var ch = text[i];
    if (q){ if (ch === '"'){ if (text[i + 1] === '"'){ cur += '"'; i++; } else q = false; } else cur += ch; continue; }
    if (ch === '"') q = true;
    else if (ch === sep){ row.push(cur); cur = ''; }
    else if (ch === '\n' || ch === '\r'){ if (ch === '\r' && text[i + 1] === '\n') i++; row.push(cur); rows.push(row); row = []; cur = ''; }
    else cur += ch;
  }
  if (cur !== '' || row.length){ row.push(cur); rows.push(row); }
  return rows.filter(function(r){ return r.some(function(c){ return c.trim() !== ''; }); });
}
function bkNum(s){
  if (s == null) return null;
  var t = String(s).replace(/[₡$\s ]|CRC|USD/g, ''), neg = /^\(.*\)$/.test(t) || /-$/.test(t);
  t = t.replace(/[()]/g, '').replace(/-$/, '');
  if (t === '') return null;
  var lc = t.lastIndexOf(','), ld = t.lastIndexOf('.');
  if (lc > ld) t = t.replace(/\./g, '').replace(',', '.'); else t = t.replace(/,/g, '');
  var n = Number(t); if (!isFinite(n)) return null;
  return neg ? -Math.abs(n) : n;
}
function bkDate(s, fmtK){
  var m = String(s || '').trim().match(/^(\d{1,4})[\/\-.](\d{1,2})[\/\-.](\d{1,4})/); if (!m) return null;
  var a = +m[1], b = +m[2], c = +m[3], y, mo, d;
  if (m[1].length === 4){ y = a; mo = b; d = c; } else if (fmtK === 'mdy'){ mo = a; d = b; y = c; } else { d = a; mo = b; y = c; }
  if (y < 100) y += 2000;
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  return y + '-' + String(mo).padStart(2, '0') + '-' + String(d).padStart(2, '0');
}
function bankImportDrawer(A, box){
  var raw = null, head = false, rows = null, req = uuid(), fileName = null;
  openDrawer('Import the bank\'s CSV', '<p class="hint">Download the movements from the bank\'s website as CSV (or Excel saved as CSV) and pick the file. Importing the same movements again adds nothing.</p><div class="attach"><button type="button" class="ghost small" id="bk-pick">Choose the statement file (CSV)</button><span class="hint" id="bk-fname">No file yet</span><input type="file" id="bk-file" accept=".csv,.txt,text/csv,text/plain"></div><div id="bk-map" class="form" style="margin-top:.8rem" hidden></div><div class="tbox" id="bk-prevBox" style="margin-top:.6rem" hidden><table id="bkPrev"><thead><tr><th>Date</th><th>Description</th><th>Reference</th><th class="num">Amount</th><th class="num">Balance</th></tr></thead><tbody></tbody></table></div><p class="hint mono" id="bk-note"></p>', '<button type="button" class="ghost small" id="bk-cancel">Cancel</button><button type="button" id="bk-import" disabled>Import these movements</button>');
  var D = $('drawerBody'), K = ['mDate', 'mDesc', 'mRef', 'mAmt', 'mOut', 'mIn', 'mBal', 'mFmt'];
  $('bk-cancel').addEventListener('click', closeDrawer);
  D.querySelector('#bk-pick').addEventListener('click', function(){ D.querySelector('#bk-file').click(); });
  D.querySelector('#bk-file').addEventListener('change', async function(){
    var file = this.files && this.files[0]; if (!file) return; fileName = file.name; D.querySelector('#bk-fname').textContent = file.name;
    var buf = await file.arrayBuffer(), text = new TextDecoder('utf-8').decode(buf);
    if (text.indexOf('�') >= 0) text = new TextDecoder('windows-1252').decode(buf);
    raw = csvParse(text.replace(/^﻿/, ''));
    if (raw.length < 1){ footErr('That file has no rows.'); return; }
    var width = raw.reduce(function(w, r){ return Math.max(w, r.length); }, 0);
    head = !raw[0].some(function(c){ return bkDate(c, 'dmy'); });
    var names = []; for (var i = 0; i < width; i++) names.push(head && raw[0][i] ? raw[0][i].trim() : 'Column ' + (i + 1));
    var opt = function(none){ return (none ? '<option value="">None</option>' : '') + names.map(function(n, i){ return '<option value="' + i + '">' + esc(n) + '</option>'; }).join(''); };
    D.querySelector('#bk-map').innerHTML = [['mDate', 'Date column', false], ['mDesc', 'Description column', false], ['mRef', 'Reference column', true], ['mAmt', 'Amount column (+ in, − out)', true], ['mOut', 'Or: money out column', true], ['mIn', 'and money in column', true], ['mBal', 'Balance column', true]].map(function(c){ return '<div><label for="' + c[0] + '">' + c[1] + '</label><select id="' + c[0] + '">' + opt(c[2]) + '</select></div>'; }).join('') + '<div><label for="mFmt">Dates are written</label><select id="mFmt"><option value="dmy">day/month/year</option><option value="ymd">year-month-day</option><option value="mdy">month/day/year</option></select></div>';
    var saved = null; try { saved = JSON.parse(localStorage.getItem('hg-bank-map-' + A.id) || 'null'); } catch (e) {}
    function guess(re){ for (var i = 0; i < names.length; i++) if (re.test(names[i])) return String(i); return ''; }
    var g = saved || {mDate: guess(/fecha|date/i) || '0', mDesc: guess(/descrip|concepto|detalle|description/i) || '1', mRef: guess(/refer|documento|comprobante/i), mAmt: guess(/^monto$|importe|amount/i), mOut: guess(/d[eé]bito|cargo|retiro|debit/i), mIn: guess(/cr[eé]dito|abono|dep[oó]sito|credit/i), mBal: guess(/saldo|balance/i), mFmt: 'dmy'};
    K.forEach(function(k){ var el = D.querySelector('#' + k); if (el && g[k] != null && (k === 'mFmt' || el.querySelector('option[value="' + g[k] + '"]'))) el.value = g[k]; });
    D.querySelector('#bk-map').hidden = false; D.querySelector('#bk-prevBox').hidden = false;
    K.forEach(function(k){ D.querySelector('#' + k).addEventListener('change', preview); });
    preview();
  });
  function preview(){
    if (!raw) return;
    var col = function(id){ var v = D.querySelector('#' + id).value; return v === '' ? null : +v; }, fm = D.querySelector('#mFmt').value, out = [], skipped = 0;
    raw.slice(head ? 1 : 0).forEach(function(r){
      var d = bkDate(r[col('mDate')], fm), amt = null;
      if (col('mAmt') != null) amt = bkNum(r[col('mAmt')]);
      else { var o = col('mOut') != null ? bkNum(r[col('mOut')]) : null, n = col('mIn') != null ? bkNum(r[col('mIn')]) : null; if (o != null || n != null) amt = (n || 0) - Math.abs(o || 0); }
      var desc = (r[col('mDesc')] || '').trim();
      if (!d || amt == null || amt === 0 || !desc){ skipped++; return; }
      out.push({date: d, description: desc, reference: col('mRef') != null ? (r[col('mRef')] || '').trim() : '', amount: Math.round(amt * 100) / 100, balance: col('mBal') != null ? bkNum(r[col('mBal')]) : null});
    });
    rows = out;
    D.querySelector('#bkPrev tbody').innerHTML = out.slice(0, 5).map(function(x){ return '<tr><td class="mono">' + esc(x.date) + '</td><td>' + esc(x.description) + '</td><td>' + esc(x.reference) + '</td><td class="num mono">' + bkMoney(A, x.amount) + '</td><td class="num mono">' + (x.balance == null ? '' : bkMoney(A, x.balance)) + '</td></tr>'; }).join('');
    D.querySelector('#bk-note').textContent = out.length + ' movements' + (skipped ? ' · ' + skipped + ' rows left out (titles, totals or blank)' : '');
    $('bk-import').disabled = !out.length;
  }
  $('bk-import').addEventListener('click', function(){
    if (!rows || !rows.length){ footErr('No movements found: check the columns.'); return; }
    var map = {}; K.forEach(function(k){ map[k] = D.querySelector('#' + k).value; });
    try { localStorage.setItem('hg-bank-map-' + A.id, JSON.stringify(map)); } catch (e) {}
    busy(this, async function(){
      var r = await db.rpc('bank_import', {p_account_id: A.id, p_file_name: fileName, p_rows: rows, p_request_id: req});
      if (r.error || !r.data || !r.data.ok){ footErr(errText(r)); return; }
      toast(r.data.added + ' new movements · ' + r.data.skipped + ' already there'); closeDrawer(); forget('bank:'); forget('cashpos'); drawBankBody(box);
    });
  });
}

/* ---------- Reports: a gallery of ten, each with its state, a table, a chart, CSV and print; the month's ZIP ---------- */
var REPORT_CUR = 'is', REPORT_ROWS = null, REP_RANGE = null;   /* REP_RANGE: a range typed for the reports, instead of the period */
var REPORTS = [['is', 'Income statement', 'Revenue, costs and expenses of the period, next to the previous one.'], ['cf', 'Cash flow', 'Where the money came from and where it went.'], ['iva', 'IVA of the period', 'IVA charged on sales, IVA credit on purchases, the balance. A draft for the accountant.'],
  ['cat', 'Expenses by category', 'Where the money goes, month by month.'], ['prime', 'Prime cost', 'Food cost plus labour, against sales.'], ['pp', 'Profit by product', 'Margin per product, with its recipe.'], ['bs', 'Balance sheet', 'What is owned and what is owed, at the close.'],
  ['prov', 'Purchases by supplier', 'Who we buy most from and how their prices move.'], ['tb', 'Trial balance', 'Every account: opening, debits, credits, closing.'], ['inv', 'Inventory at average cost', 'What is on the shelf, valued, against the books.'],
  ['labor', 'Labour cost by day', 'The hours worked at each person\'s rate, against sales without IVA.']];
function repState(k, cmp){ return k === 'labor' ? 'estimate' : k === 'iva' ? 'draft' : k === 'bs' || k === 'tb' ? 'books' : k === 'cat' || k === 'prov' ? 'docs' : k === 'inv' ? 'estimate' : rangeState(cmp) === 'books' ? 'books' : 'estimate'; }
function trRow(cells, cls){ return '<tr' + (cls ? ' class="' + cls + '"' : '') + '>' + cells.map(function(c, i){ return '<td' + (i && typeof c === 'number' ? ' class="num mono"' : '') + '>' + (typeof c === 'number' ? fmt(c) : c) + '</td>'; }).join('') + '</tr>'; }
function cmpTable(rows){ return '<div class="tbox"><table class="narrow"><thead><tr><th></th><th class="num">Current</th><th class="num">Previous</th><th class="num">Δ</th></tr></thead><tbody>' + rows.map(function(r){ var v = Number(r[1]), p = Number(r[2]); return '<tr' + (r[3] ? ' class="total"' : '') + '><td>' + esc(r[0]) + '</td><td class="num mono">' + fmt(v) + '</td><td class="num mono hint">' + fmt(p) + '</td><td class="num mono ' + (v - p >= 0 ? 'up' : 'down') + '">' + (p ? pct(((v - p) / Math.abs(p)) * 100) : '—') + '</td></tr>'; }).join('') + '</tbody></table></div>'; }
VIEW.reportes = async function(){
  var r = REP_RANGE ? {from: REP_RANGE.from, to: REP_RANGE.to} : range(), cmp = await loadCompare(r);
  var host = document.createElement('div');
  host.innerHTML = '<div class="tools noprint"><div><label for="rpFrom">From</label><input type="date" id="rpFrom" value="' + esc(r.from) + '"></div><div><label for="rpTo">To</label><input type="date" id="rpTo" value="' + esc(r.to) + '"></div><div><button type="button" class="ghost small" id="rpGo">Show these dates</button></div>' + (REP_RANGE ? '<div><button type="button" class="ghost small" id="rpReset">Back to the period</button></div>' : '') + '<div class="grow"><span class="hint">«Year» is built in pieces: several functions take at most 92 days (cash, IVA) or 400 (journal) per call; a range longer than a year is not read.</span></div></div><div class="grid fichas noprint" id="repGrid">' + REPORTS.map(function(x){ return '<button type="button" class="rep" data-r="' + x[0] + '" aria-pressed="' + (REPORT_CUR === x[0]) + '"><h3>' + esc(x[1]) + '</h3><p>' + esc(x[2]) + '</p><div style="margin-top:.4rem">' + stateTag(repState(x[0], cmp)) + '</div></button>'; }).join('') + '</div><div class="card" style="margin-top:1rem" id="repBody"><div class="loading">Loading…</div></div>';
  host.querySelector('#rpGo').addEventListener('click', function(){ var a = host.querySelector('#rpFrom').value, b2 = host.querySelector('#rpTo').value; if (!a || !b2 || b2 < a){ toast('Pick a start and an end, in that order.'); return; } if (daysBetween(a, b2) > 366){ toast('Pick at most a year.'); return; } REP_RANGE = {from: a, to: b2}; render(); });
  var rr = host.querySelector('#rpReset'); if (rr) rr.addEventListener('click', function(){ REP_RANGE = null; render(); });
  host.querySelectorAll('.rep').forEach(function(b){ b.addEventListener('click', function(){ REPORT_CUR = b.dataset.r; host.querySelectorAll('.rep').forEach(function(x){ x.setAttribute('aria-pressed', String(x === b)); }); drawReport(host.querySelector('#repBody'), r, cmp); }); });
  await drawReport(host.querySelector('#repBody'), r, cmp);
  return host;
};
async function drawReport(box, r, cmp){
  var k = REPORT_CUR, meta = REPORTS.filter(function(x){ return x[0] === k; })[0], cur = cmp.current, prev = cmp.previous;
  var mine = box._seq = (box._seq || 0) + 1;
  box.innerHTML = '<div class="loading">Loading…</div>'; REPORT_ROWS = null;
  var head = '<h2>' + esc(meta[1]) + ' ' + stateTag(repState(k, cmp)) + '<span class="sp"></span><span class="hint mono">' + esc(k === 'bs' ? 'as of ' + r.to : k === 'inv' ? 'today' : r.from + ' → ' + r.to) + '</span><button type="button" class="ghost small" id="rCsv">Download CSV</button><button type="button" class="ghost small" id="rPrint">Print</button><button type="button" class="ghost small" id="rPack">Month\'s package (ZIP)</button></h2>';
  var h = '', rows = [];
  try {
    if (k === 'is'){
      var tr = await loadTrends(), months = tr.months || [];
      PREV_ACTIVE = Number(prev.days_with_sales) > 0 || Number(prev.expenses) > 0 || Number(prev.purchases) > 0 || Number(prev.days_closed) > 0;
      h = '<div class="grid two"><div>' + cmpTable([['Revenue, no IVA (refunds already deducted)', cur.net, prev.net], ['Cost of sales and waste', -(Number(cur.cogs) + Number(cur.waste)), -(Number(prev.cogs) + Number(prev.waste))], ['Gross margin', Number(cur.net) - Number(cur.cogs) - Number(cur.waste), Number(prev.net) - Number(prev.cogs) - Number(prev.waste), true], ['Operating expenses', -cur.expenses, -prev.expenses], ['Profit', Number(cur.net) - costs(cur), Number(prev.net) - costs(prev), true]]) +
        (Number(cur.refunds) || Number(prev.refunds) ? '<p class="note">Refunds inside the revenue line, no IVA: ' + esc(fmt(cur.refunds)) + ' (previous ' + esc(fmt(prev.refunds)) + ').</p>' : '') +
        (cur.books ? '<p class="note">In the books (posted days only): revenue ' + esc(fmt(cur.books.revenue)) + ' · expenses ' + esc(fmt(cur.books.expenses)) + ' · net income ' + esc(fmt(cur.books.net_income)) + '.</p>' : '') + '</div><div>' +
        HG_CHARTS.box(function(W){ return HG_CHARTS.bar([months.map(function(m){ return Number(m.net); }), months.map(function(m){ return Number(m.cogs) + Number(m.waste); }), months.map(function(m){ return Number(m.expenses); })], months.map(function(m){ return mlabel(m.month); }), ['var(--c1)', 'var(--c2)', 'var(--c5)'], 240, W); }) + HG_CHARTS.legend([['Revenue, no IVA', 'var(--c1)'], ['Cost of sales', 'var(--c2)'], ['Operating expenses', 'var(--c5)']]) + '</div></div>';
      rows = [['line', 'current', 'previous'], ['revenue_net', cur.net, prev.net], ['refunds_memo_already_in_revenue', cur.refunds, prev.refunds], ['cogs', cur.cogs, prev.cogs], ['waste', cur.waste, prev.waste], ['expenses', cur.expenses, prev.expenses], ['profit', Number(cur.net) - costs(cur), Number(prev.net) - costs(prev)]];
    } else if (k === 'cf'){
      var cf = await rpc('acct_cash_flow', {p_from: r.from, p_to: r.to});
      h = '<p class="hint" style="margin:0 0 .6rem">Direct method from the books: the cash and bank accounts, by what moved them. Days not posted yet are not here.</p><div class="tbox"><table class="narrow"><tbody>' + trRow(['Cash and bank at the start', Number(cf.opening)], 'total') + (cf.rows || []).map(function(x){ return trRow([esc(x.group), Number(x.amount)]); }).join('') + trRow(['Cash and bank at the end', Number(cf.closing)], 'total') + '</tbody></table></div>';
      rows = [['group', 'amount'], ['opening', cf.opening]].concat((cf.rows || []).map(function(x){ return [x.group, x.amount]; }), [['closing', cf.closing]]);
    } else if (k === 'iva'){
      var d = await loadIva(r.from, r.to), S = d.sales, C = d.credits, L = d.ledger, exp = C.documents.filter(function(x){ return x.source === 'expense'; }), inv = C.documents.filter(function(x){ return x.source !== 'expense'; });
      var sIva = function(xs){ return sum(xs, function(x){ return x.iva_crc; }); };
      h = '<p class="hint" style="margin:0 0 .6rem">Draft for the accountant, not the return: they review it, apply the proportional credit if it applies, and file it.</p><div class="grid three">' + kpi('IVA charged on sales', fmt(S.tax_crc)) + kpi('IVA credit on purchases', fmt(C.iva_crc)) + kpi(Number(d.net_crc) >= 0 ? 'IVA to pay' : 'Credit balance for the next period', fmt(Math.abs(Number(d.net_crc))), undefined, undefined, 'draft') + '</div>' +
        '<div class="tbox" style="margin-top:.8rem"><table class="narrow"><tbody><tr class="head"><td colspan="2">IVA on sales</td></tr>' + S.by_rate.map(function(x){ return trRow([esc((/^IVA\d/.test(x.code || '') ? 'IVA ' : x.code + ' · ') + (Math.round(Number(x.rate) * 1000) / 10) + ' %') + ' <span class="hint">base ' + esc(fmt(x.net_crc)) + '</span>', Number(x.tax_crc)]); }).join('') + trRow(['Refunds', Number(S.refunds_tax_crc)]) + trRow(['Total IVA on sales', Number(S.tax_crc)], 'total') +
        '<tr class="head"><td colspan="2">Creditable IVA on purchases</td></tr>' + trRow(['Expenses (' + exp.length + ')', sIva(exp)]) + trRow(['Supplier invoices (' + inv.length + ')', sIva(inv)]) + trRow(['Total creditable IVA', Number(C.iva_crc)], 'total') +
        '<tr class="head"><td colspan="2">In the books</td></tr>' + trRow(['IVA payable posted (2110)', Number(L.iva_out_crc)]) + trRow(['IVA credit posted (1140)', Number(L.iva_in_crc)]) + '</tbody></table></div>' +
        (Number(L.pending_days) ? '<p class="err">' + esc(L.pending_days + ' closed days not in the books yet: post them so the books match.') + '</p>' : '') + (Number(S.without_tax_detail.orders) ? '<p class="hint">' + esc(S.without_tax_detail.orders + ' sales recorded before the IVA update have no IVA detail: ' + fmt(S.without_tax_detail.total_crc) + ' (left out of the totals).') + '</p>' : '') +
        '<h3>Purchase documents</h3><div class="tbox"><table><thead><tr><th>Date</th><th>Supplier</th><th>Invoice</th><th class="num">Base</th><th class="num">IVA</th></tr></thead><tbody>' + C.documents.map(function(x){ return '<tr><td class="mono">' + esc(x.date) + '</td><td>' + esc(x.supplier || '') + '</td><td>' + esc(x.number || '') + '</td><td class="num mono">' + fmt(x.base_crc) + '</td><td class="num mono">' + fmt(x.iva_crc) + '</td></tr>'; }).join('') + '</tbody></table></div>';
      rows = [['section', 'item', 'base_crc', 'iva_crc']].concat(S.by_rate.map(function(x){ return ['sales', x.code + ' ' + Math.round(Number(x.rate) * 1000) / 10 + ' %', x.net_crc, x.tax_crc]; }), [['sales', 'refunds', '', S.refunds_tax_crc], ['sales', 'total', '', S.tax_crc], ['credits', 'expenses', '', sIva(exp)], ['credits', 'supplier invoices', '', sIva(inv)], ['credits', 'total', '', C.iva_crc], ['net', Number(d.net_crc) >= 0 ? 'to pay' : 'credit balance', '', d.net_crc], ['ledger', '2110', '', L.iva_out_crc], ['ledger', '1140', '', L.iva_in_crc], ['', '', '', '']], [['date', 'supplier', 'invoice', 'base_crc', 'iva_crc', 'source']], C.documents.map(function(x){ return [x.date, x.supplier, x.number, x.base_crc, x.iva_crc, x.source]; }));
    } else if (k === 'cat'){
      var exps = await loadExpenses(r.from, r.to), tr2 = await loadTrends(), mm = tr2.months || [], byCat = {};
      exps.filter(function(e){ return !e.voided_at; }).forEach(function(e){ byCat[e.account] = (byCat[e.account] || 0) + Number(e.amount_crc) - Number(e.iva_crc); });
      serviceInvoices((await loadIva(r.from, r.to)).credits.documents).forEach(function(x){ byCat[x.account] = (byCat[x.account] || 0) + Number(x.base_crc); });
      if (Number(cur.cogs)) byCat[mapped('cogs', '5101')] = (byCat[mapped('cogs', '5101')] || 0) + Number(cur.cogs);
      if (Number(cur.waste)) byCat[mapped('waste', '5102')] = (byCat[mapped('waste', '5102')] || 0) + Number(cur.waste);
      var cats = Object.keys(byCat).map(function(c){ return [c + ' · ' + accountName(c), byCat[c], c]; }).sort(function(a, b){ return b[1] - a[1]; });
      h = '<div class="grid two"><div>' + (cats.length ? HG_CHARTS.hbars(cats, 'var(--c2)') : '<p class="hint">No expenses in this period.</p>') + '</div><div>' + HG_CHARTS.box(function(W){ return HG_CHARTS.bar([mm.map(function(m){ return Number(m.cogs) + Number(m.waste); }), mm.map(function(m){ return Number(m.expenses); })], mm.map(function(m){ return mlabel(m.month); }), ['var(--c2)', 'var(--c5)'], 240, W); }) + HG_CHARTS.legend([['Cost of sales and waste', 'var(--c2)'], ['Operating expenses', 'var(--c5)']]) + '</div></div>';
      rows = [['account', 'name', 'amount_no_iva']].concat(cats.map(function(c){ return [c[2], accountName(c[2]), c[1]]; }));
    } else if (k === 'prime'){
      var tr3 = await loadTrends(), m3 = tr3.months || [];
      var food = m3.map(function(m){ return Number(m.food_cost_pct) || 0; }), lab = m3.map(function(m){ return m.labor_pct == null ? 0 : Number(m.labor_pct); }), last = m3[m3.length - 1] || {};
      h = '<p class="hint" style="margin:0 0 .8rem">Food cost from the recipes and stock moves; labour from the hours and pay rates' + (tr3.labor_visible ? '' : ' (labour is visible only with the books)') + '. An estimate until the month closes.</p><div class="grid three">' + ['Food cost %', 'Labour %', 'Prime cost %'].map(function(l, i){ var v = i === 0 ? last.food_cost_pct : i === 1 ? last.labor_pct : last.prime_pct; return '<div class="kpi"><div class="l">' + esc(l) + '</div><div class="v">' + (v == null ? '—' : esc(num(v, 1)) + ' %') + '</div><div class="d"><span>' + esc(last.month ? mlabel(last.month) : '') + '</span></div></div>'; }).join('') + '</div><div style="margin-top:1rem">' +
        HG_CHARTS.box(function(W){ return HG_CHARTS.bar([food, lab], m3.map(function(m){ return mlabel(m.month); }), ['var(--c2)', 'var(--c3)'], 220, W, function(v){ return Math.round(v) + ' %'; }); }) + HG_CHARTS.legend([['Food cost %', 'var(--c2)'], ['Labour %', 'var(--c3)']]) + '</div>';
      rows = [['month', 'net', 'cogs', 'food_cost_pct', 'labor', 'labor_pct', 'prime_pct']].concat(m3.map(function(m){ return [m.month, m.net, m.cogs, m.food_cost_pct, m.labor, m.labor_pct, m.prime_pct]; }));
    } else if (k === 'pp'){
      var pp = await rpc('product_profitability', {p_from: r.from, p_to: r.to}), ppr = (pp.rows || []).filter(function(x){ return Number(x.units) || x.has_recipe; });
      h = '<p class="hint" style="margin:0 0 .6rem">Sales that stand (not voided or refunded), net of IVA and discounts. Cost: what the stock cost at the moment of each sale. Recipe: today\'s cost and price.</p><div class="tbox"><table><thead><tr><th>Product</th><th class="num">Units</th><th class="num">Sold, no IVA</th><th class="num">Cost</th><th class="num">Margin</th><th class="num">Food cost</th><th class="num">Margin per unit</th></tr></thead><tbody>' +
        ppr.map(function(x){ return '<tr><td>' + esc(x.name) + (x.has_recipe ? '' : ' ' + tag('rev', 'no recipe')) + '</td><td class="num mono">' + esc(num(x.units, 3)) + '</td><td class="num mono">' + fmt(x.net_crc) + '</td><td class="num mono">' + fmt(x.cost_crc) + '</td><td class="num mono">' + fmt(x.margin_crc) + '</td><td class="num mono">' + (x.food_cost_pct == null ? '' : esc(num(x.food_cost_pct, 1)) + ' %') + '</td><td class="num mono">' + (x.on_menu && x.has_recipe ? fmt(x.unit_margin_crc) + ' · ' + esc(num(x.unit_margin_pct, 1)) + ' %' : '') + '</td></tr>'; }).join('') +
        '<tr class="total"><td>Total</td><td class="num mono">' + esc(num(pp.totals.units, 3)) + '</td><td class="num mono">' + fmt(pp.totals.net_crc) + '</td><td class="num mono">' + fmt(pp.totals.cost_crc) + '</td><td class="num mono">' + fmt(pp.totals.margin_crc) + '</td><td class="num mono">' + (Number(pp.totals.net_crc) > 0 ? esc(num(100 * Number(pp.totals.cost_crc) / Number(pp.totals.net_crc), 1)) + ' %' : '') + '</td><td></td></tr></tbody></table></div>';
      var noRecipe = (pp.rows || []).filter(function(x){ return x.on_menu && !x.has_recipe; }).length; if (noRecipe) h += '<p class="hint">' + esc(noRecipe + ' products on the menu have no recipe yet: their cost is unknown (Inventory → Recipes).') + '</p>';
      rows = [['product', 'units', 'net_crc', 'cost_crc', 'margin_crc', 'food_cost_pct', 'recipe_cost_crc', 'unit_margin_crc', 'unit_margin_pct', 'has_recipe']].concat((pp.rows || []).map(function(x){ return [x.name, x.units, x.net_crc, x.cost_crc, x.margin_crc, x.food_cost_pct, x.recipe_cost_crc, x.unit_margin_crc, x.unit_margin_pct, x.has_recipe ? 'yes' : 'no']; }));
    } else if (k === 'bs'){
      var bs = await rpc('acct_balance_sheet', {p_as_of: r.to});
      var part = function(type, title){ var xs = bs.rows.filter(function(x){ return x.type === type; }); return '<tr class="head"><td colspan="2">' + title + '</td></tr>' + xs.map(function(x){ return trRow([esc(x.code + ' · ' + x.name), Number(x.amount)]); }).join(''); };
      h = '<div class="grid two"><div class="tbox"><table class="narrow"><tbody>' + part('asset', 'Assets') + trRow(['Total assets', Number(bs.assets)], 'total') + '</tbody></table></div><div class="tbox"><table class="narrow"><tbody>' + part('liability', 'Liabilities') + trRow(['Total liabilities', Number(bs.liabilities)], 'total') + part('equity', 'Equity') + trRow(['Results not yet closed', Number(bs.current_earnings)]) + trRow(['Total liabilities and equity', Number(bs.liabilities) + Number(bs.equity) + Number(bs.current_earnings)], 'total') + '</tbody></table></div></div>' + (bs.balanced ? '' : '<p class="err">The balance sheet does not balance: tell the accountant.</p>');
      rows = [['code', 'account', 'type', 'amount']].concat(bs.rows.map(function(x){ return [x.code, x.name, x.type, x.amount]; }), [['', 'results not yet closed', '', bs.current_earnings]]);
    } else if (k === 'prov'){
      var si = await rpc('supplier_insights', {p_from: r.from, p_to: r.to}), vs = (si.vendors || []).filter(function(v){ return Number(v.received) > 0 || Number(v.owed) > 0 || (v.prices || []).length; });
      h = (vs.length ? HG_CHARTS.hbars(vs.slice().sort(function(a, b){ return Number(b.received) - Number(a.received); }).map(function(v){ return [v.name, Number(v.received)]; }), 'var(--c1)') : '<p class="hint">No deliveries in this period.</p>') +
        '<div class="tbox" style="margin-top:.8rem"><table><thead><tr><th>Supplier</th><th class="num">Received</th><th class="num">Deliveries</th><th class="num">Days to deliver</th><th class="num">Late</th><th class="num">Owed</th><th>Price changes</th></tr></thead><tbody>' + vs.map(function(v){ return '<tr><td>' + esc(v.name) + '</td><td class="num mono">' + fmt(v.received) + '</td><td class="num mono">' + esc(v.deliveries) + '</td><td class="num mono">' + (v.avg_days == null ? '' : esc(num(v.avg_days, 1))) + '</td><td class="num mono">' + esc(v.late) + '</td><td class="num mono">' + fmt(v.owed) + '</td><td>' + esc((v.prices || []).filter(function(p){ return p.change_pct != null && Math.abs(Number(p.change_pct)) >= 1; }).map(function(p){ return p.item + ' ' + (Number(p.change_pct) > 0 ? '+' : '') + num(p.change_pct, 1) + ' %'; }).join(', ')) + '</td></tr>'; }).join('') + '</tbody></table></div>';
      rows = [['supplier', 'received_crc', 'deliveries', 'avg_days', 'late', 'owed_crc']].concat(vs.map(function(v){ return [v.name, v.received, v.deliveries, v.avg_days, v.late, v.owed]; }));
    } else if (k === 'tb'){
      var tb = await rpc('acct_trial_balance', {p_from: r.from, p_to: r.to}), td = 0, tc = 0;
      h = '<div class="tbox"><table><thead><tr><th>Account</th><th class="num">Opening</th><th class="num">Debit</th><th class="num">Credit</th><th class="num">Closing</th></tr></thead><tbody>' + tb.rows.map(function(x){ td += Number(x.debit); tc += Number(x.credit); return '<tr><td>' + esc(x.code + ' · ' + x.name) + '</td><td class="num mono">' + fmt(x.opening) + '</td><td class="num mono">' + fmt(x.debit) + '</td><td class="num mono">' + fmt(x.credit) + '</td><td class="num mono">' + fmt(x.closing) + '</td></tr>'; }).join('') + '<tr class="total"><td>Total</td><td></td><td class="num mono">' + fmt(td) + '</td><td class="num mono">' + fmt(tc) + '</td><td></td></tr></tbody></table></div>';
      rows = [['code', 'account', 'opening', 'debit', 'credit', 'closing']].concat(tb.rows.map(function(x){ return [x.code, x.name, x.opening, x.debit, x.credit, x.closing]; }));
    } else if (k === 'labor'){
      var lc = await rpc('labor_cost', {p_from: r.from, p_to: r.to}), th = 0, tl = 0, ts = 0, miss = false;
      h = '<p class="hint" style="margin:0 0 .6rem">An estimate: the hours worked at each person\'s rate (fixed pay spread over its pay period), against sales without IVA.</p><div class="tbox"><table><thead><tr><th>Day</th><th class="num">Hours</th><th class="num">Labour</th><th class="num">Sales, no IVA</th><th class="num">Labour %</th></tr></thead><tbody>' +
        (lc.days || []).map(function(x){ th += Number(x.hours); tl += Number(x.labor_crc); ts += Number(x.sales_net_crc); miss = miss || x.missing_rates; return '<tr><td class="mono">' + esc(x.day) + (x.missing_rates ? ' ' + tag('rev', 'no pay rate') : '') + '</td><td class="num mono">' + esc(num(x.hours, 2)) + '</td><td class="num mono">' + fmt(x.labor_crc) + '</td><td class="num mono">' + fmt(x.sales_net_crc) + '</td><td class="num mono">' + (x.pct == null ? '' : esc(num(x.pct, 1)) + ' %') + '</td></tr>'; }).join('') +
        '<tr class="total"><td>Total</td><td class="num mono">' + esc(num(Math.round(th * 100) / 100, 2)) + '</td><td class="num mono">' + fmt(tl) + '</td><td class="num mono">' + fmt(ts) + '</td><td class="num mono">' + (ts > 0 ? esc(num(Math.round(1000 * tl / ts) / 10, 1)) + ' %' : '') + '</td></tr></tbody></table></div>' + (miss ? '<p class="err">Some people worked without a pay rate: set it in Payroll → Pay rates.</p>' : '');
      rows = [['day', 'hours', 'labor_crc', 'sales_net_crc', 'pct', 'missing_rates']].concat((lc.days || []).map(function(x){ return [x.day, x.hours, x.labor_crc, x.sales_net_crc, x.pct, x.missing_rates ? 'yes' : '']; }));
    } else if (k === 'inv'){
      var iv = await rpc('inventory_valuation'), dif = Number(iv.ledger_crc) - Number(iv.total_crc);
      h = '<div class="tbox"><table><thead><tr><th>Item</th><th class="num">On hand</th><th class="num">Average cost</th><th class="num">Value</th></tr></thead><tbody>' + iv.items.map(function(x){ return '<tr><td>' + esc(x.name) + (x.negative ? ' ' + tag('rev', 'below zero') : '') + '</td><td class="num mono">' + esc(num(x.on_hand, 3) + ' ' + x.unit) + '</td><td class="num mono">' + fmt(x.avg_cost) + '</td><td class="num mono">' + fmt(x.value_crc) + '</td></tr>'; }).join('') + '<tr class="total"><td>Total</td><td></td><td></td><td class="num mono">' + fmt(iv.total_crc) + '</td></tr><tr><td>Inventory in the books (1150)</td><td></td><td></td><td class="num mono">' + fmt(iv.ledger_crc) + '</td></tr></tbody></table></div>' + (iv.posted ? (Math.abs(dif) >= 1 ? '<p class="hint">' + esc('Difference with the books ' + fmt(dif) + ': counts or receipts of days not posted yet, or the opening entry.') + '</p>' : '') : '<p class="hint">The books have no days posted yet.</p>');
      rows = [['item', 'category', 'on_hand', 'unit', 'avg_cost', 'value_crc']].concat(iv.items.map(function(x){ return [x.name, x.category, x.on_hand, x.unit, x.avg_cost, x.value_crc]; }), [['total', '', '', '', '', iv.total_crc], ['books 1150', '', '', '', '', iv.ledger_crc]]);
    }
  } catch (e){ if (mine !== box._seq) return; box.innerHTML = '<h2>' + esc(meta[1]) + '</h2><div class="banner bad"><b>Could not load.</b><span class="hint">' + esc(errText(e)) + '</span><span class="sp"></span><button type="button" class="ghost small" data-retry>Try again</button></div>'; box.querySelector('[data-retry]').addEventListener('click', function(){ forget(); drawReport(box, r, cmp); }); return; }
  if (mine !== box._seq) return;
  box.innerHTML = head + h; REPORT_ROWS = rows; HG_CHARTS.mount(box);
  if (window.innerWidth <= 640) box.scrollIntoView({block: 'start', behavior: 'smooth'});   /* on a phone the ten cards sit above the report */
  box.querySelector('#rCsv').addEventListener('click', function(){ if (REPORT_ROWS) download({is: 'estado-resultados', cf: 'flujo-efectivo', iva: 'iva-periodo', cat: 'gastos-por-categoria', prime: 'costo-primo', pp: 'rentabilidad-productos', bs: 'balance-general', prov: 'compras-por-proveedor', tb: 'balanza', inv: 'inventario-valorado', labor: 'costo-mano-de-obra'}[k] + '-' + (k === 'inv' ? today() : r.to) + '.csv', REPORT_ROWS); });
  box.querySelector('#rPrint').addEventListener('click', function(){ window.print(); });
  box.querySelector('#rPack').addEventListener('click', function(){ monthPackage(r, this); });
}
/* the month for the accountant in one file: journal, trial balance, income statement, balance sheet, cash flow, expenses,
   sales IVA by rate, purchase IVA documents and today's inventory valuation, each a CSV inside a ZIP (built here, nothing is sent) */
var CRC_T = (function(){ var t = []; for (var n = 0; n < 256; n++){ var c = n; for (var k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; } return t; })();
function crc32(b){ var c = 0xFFFFFFFF; for (var i = 0; i < b.length; i++) c = CRC_T[(c ^ b[i]) & 255] ^ (c >>> 8); return (c ^ 0xFFFFFFFF) >>> 0; }
function zip(files){
  var enc = new TextEncoder(), parts = [], central = [], off = 0;
  files.forEach(function(f){
    var name = enc.encode(f.name), data = enc.encode(f.text), crc = crc32(data);
    var h = new DataView(new ArrayBuffer(30));
    h.setUint32(0, 0x04034b50, true); h.setUint16(4, 20, true); h.setUint16(6, 0x0800, true); h.setUint16(8, 0, true);
    h.setUint32(14, crc, true); h.setUint32(18, data.length, true); h.setUint32(22, data.length, true); h.setUint16(26, name.length, true);
    parts.push(new Uint8Array(h.buffer), name, data);
    var c = new DataView(new ArrayBuffer(46));
    c.setUint32(0, 0x02014b50, true); c.setUint16(4, 20, true); c.setUint16(6, 20, true); c.setUint16(8, 0x0800, true);
    c.setUint32(16, crc, true); c.setUint32(20, data.length, true); c.setUint32(24, data.length, true); c.setUint16(28, name.length, true); c.setUint32(42, off, true);
    central.push(new Uint8Array(c.buffer), name);
    off += 30 + name.length + data.length;
  });
  var csize = central.reduce(function(t, x){ return t + x.length; }, 0), e = new DataView(new ArrayBuffer(22));
  e.setUint32(0, 0x06054b50, true); e.setUint16(8, files.length, true); e.setUint16(10, files.length, true); e.setUint32(12, csize, true); e.setUint32(16, off, true);
  return new Blob(parts.concat(central, [new Uint8Array(e.buffer)]), {type: 'application/zip'});
}
async function monthPackage(r, btn){
  var m = r.to.slice(0, 7), from = m + '-01', to = monthEnd(from);
  await busy(btn, async function(){
    var res = await Promise.all([db.rpc('acct_journal', {p_from: from, p_to: to}), db.rpc('acct_trial_balance', {p_from: from, p_to: to}), db.rpc('acct_income_statement', {p_from: from, p_to: to}), db.rpc('acct_balance_sheet', {p_as_of: to}), db.rpc('acct_cash_flow', {p_from: from, p_to: to}), db.rpc('expense_list', {p_from: from, p_to: to}), db.rpc('tax_summary', {p_from: from, p_to: to}), db.rpc('iva_report', {p_from: from, p_to: to}), db.rpc('inventory_valuation')]);
    if (res.some(function(x){ return x.error || !x.data || x.data.ok === false; })){ toast('Could not build the package. Check the connection and try again.'); return; }
    var j = [['entry_no', 'date', 'source', 'memo', 'account', 'account_name', 'debit', 'credit']];
    res[0].data.entries.forEach(function(e){ (e.lines || []).forEach(function(l){ j.push([e.entry_no, e.date, e.source, e.memo, l.account, l.name, l.debit, l.credit]); }); });
    var tb = [['code', 'account', 'opening', 'debit', 'credit', 'closing']].concat(res[1].data.rows.map(function(x){ return [x.code, x.name, x.opening, x.debit, x.credit, x.closing]; }));
    var is = [['code', 'account', 'type', 'amount']].concat(res[2].data.rows.map(function(x){ return [x.code, x.name, x.type, x.amount]; }), [['', 'net income', '', res[2].data.net_income]]);
    var bs = [['code', 'account', 'type', 'amount']].concat(res[3].data.rows.map(function(x){ return [x.code, x.name, x.type, x.amount]; }), [['', 'results not yet closed', '', res[3].data.current_earnings]]);
    var cf = [['group', 'amount'], ['opening', res[4].data.opening]].concat(res[4].data.rows.map(function(x){ return [x.group, x.amount]; }), [['closing', res[4].data.closing]]);
    var ex = [['date', 'supplier', 'description', 'account', 'total', 'iva', 'paid_from', 'open', 'invoice', 'invoice_date', 'voided', 'invoice_file']].concat(res[5].data.expenses.map(function(x){ return [x.date, x.vendor_name, x.description, x.account, x.amount_crc, x.iva_crc, x.paid_from, x.open_crc, x.invoice_no, x.invoice_date, x.voided_at ? 'yes' : '', x.receipt_path || '']; }));
    var iva = [['code', 'rate', 'lines', 'gross_crc', 'net_crc', 'tax_crc']].concat(res[6].data.by_rate.map(function(x){ return [x.code, x.rate, x.lines, x.gross_crc, x.net_crc, x.tax_crc]; }), [['refunds', '', '', '', '', res[6].data.refunds_tax_crc], ['sales without tax detail (before 0009)', '', res[6].data.without_tax_detail.orders, res[6].data.without_tax_detail.total_crc, '', '']]);
    var ivc = [['date', 'supplier', 'invoice', 'base_crc', 'iva_crc', 'source', 'account']].concat(res[7].data.credits.documents.map(function(x){ return [x.date, x.supplier, x.number, x.base_crc, x.iva_crc, x.source, x.account]; }), [['', 'total', '', '', res[7].data.credits.iva_crc, '', '']]);
    var stk = [['item', 'category', 'on_hand', 'unit', 'avg_cost', 'value_crc']].concat(res[8].data.items.map(function(x){ return [x.name, x.category, x.on_hand, x.unit, x.avg_cost, x.value_crc]; }), [['total', '', '', '', '', res[8].data.total_crc], ['books 1150', '', '', '', '', res[8].data.ledger_crc]]);
    var blob = zip([{name: 'diario.csv', text: csvText(j)}, {name: 'balanza.csv', text: csvText(tb)}, {name: 'estado-resultados.csv', text: csvText(is)}, {name: 'balance-general.csv', text: csvText(bs)}, {name: 'flujo-efectivo.csv', text: csvText(cf)}, {name: 'gastos.csv', text: csvText(ex)}, {name: 'iva-ventas.csv', text: csvText(iva)}, {name: 'iva-compras.csv', text: csvText(ivc)}, {name: 'inventario-valorado-' + today() + '.csv', text: csvText(stk)}]);
    var a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = 'contabilidad-' + m + '.zip'; a.click();
    setTimeout(function(){ URL.revokeObjectURL(a.href); }, 2000);
  });
}

/* ---------- Books: the journal, accounts, mappings, periods, electronic documents, payroll, audit and activation ---------- */
var BOOKS_SUB = 'diario';
var SRC = {manual: 'Manual', day: 'Day', expense: 'Expense', reversal: 'Reversal', opening: 'Opening', payroll: 'Payroll', ap: 'Suppliers', bank: 'Bank'};
var TYPE = {asset: 'Asset', liability: 'Liability', equity: 'Equity', revenue: 'Revenue', expense: 'Cost or expense'};
var PSTATUS = {open: 'Open for entries', closed: 'Closed', locked: 'Locked'};
var E_KIND = {TE: 'Ticket', FE: 'Invoice', NC: 'Credit note'},
    E_STATUS = {pending: 'Waiting', queued: 'Queued', sent: 'Sent', accepted: 'Accepted', rejected: 'Rejected', error: 'Error', contingency: 'Contingency', cancelled: 'Voided'};
function acctOptions(sel, onlyActive, types){ return ((OV && OV.accounts) || []).filter(function(a){ return (!onlyActive || a.active) && (!types || types.indexOf(a.type) >= 0); }).map(function(a){ return '<option value="' + esc(a.code) + '"' + (a.code === sel ? ' selected' : '') + '>' + esc(a.code + ' · ' + a.name) + '</option>'; }).join(''); }
VIEW.contabilidad = async function(){
  var tabs = [['diario', 'Journal'], ['cuentas', 'Accounts'], ['mapeos', 'Mappings'], ['periodos', 'Periods'], ['einv', 'Electronic documents'], ['planilla', 'Payroll'], ['audit', 'Audit'], ['act', 'Activation']];
  if (KIND !== 'owner') tabs = tabs.filter(function(t){ return t[0] !== 'act'; });
  var host = document.createElement('div');
  host.innerHTML = '<div class="subtabs" id="bookTabs">' + tabs.map(function(t){ return '<button type="button" data-s="' + t[0] + '" aria-pressed="' + (BOOKS_SUB === t[0]) + '">' + t[1] + '</button>'; }).join('') + '</div><div id="bookBody"><div class="loading">Loading…</div></div>';
  host.querySelectorAll('#bookTabs button').forEach(function(b){ b.addEventListener('click', function(){ BOOKS_SUB = b.dataset.s; host.querySelectorAll('#bookTabs button').forEach(function(x){ x.setAttribute('aria-pressed', String(x === b)); }); drawBooks(host.querySelector('#bookBody')); }); });
  await drawBooks(host.querySelector('#bookBody'));
  return host;
};
async function drawBooks(box){
  var mine = box._seq = (box._seq || 0) + 1;
  box.innerHTML = '<div class="loading">Loading…</div>';
  try {
    var f = {diario: drawJournal, cuentas: drawAccounts, mapeos: drawMappings, periodos: drawPeriods, einv: drawEdocs, planilla: drawPayroll, audit: drawAudit, act: drawActivation}[BOOKS_SUB] || drawJournal;
    var out = await f();
    if (mine !== box._seq) return;
    box.replaceChildren(); if (typeof out === 'string') box.innerHTML = out; else box.appendChild(out);
    HG_CHARTS.mount(box);
  } catch (e){ if (mine !== box._seq) return; box.innerHTML = '<div class="banner bad"><b>Could not load.</b><span class="hint">' + esc(errText(e)) + '</span><span class="sp"></span><button type="button" class="ghost small" data-retry>Try again</button></div>'; box.querySelector('[data-retry]').addEventListener('click', function(){ forget('journal'); forget('audit'); forget('edocs'); drawBooks(box); }); }
}
/* the journal: every entry of the period, by source and account; the detail shows its lines and, for a manual one, the reversal */
async function drawJournal(){
  var st = TBL.diario, r = range(), from = st && st.touched && st.from ? st.from : r.from, to = st && st.touched && st.to ? st.to : r.to;
  var entries = await loadJournal(from, to, null);
  var host = document.createElement('div');
  var pend = (OV.pending_days || []).length;
  host.innerHTML = (pend ? '<div class="banner"><b>' + esc(pend + ' closed days are not in the books yet.') + '</b><span class="hint">The journal shows only what is posted. Income → "Post the pending days".</span><span class="sp"></span><button type="button" class="small" id="jPost">Post the pending days</button></div>' : '') +
    '<div class="card"><h2>Journal <span class="hint">' + esc(entries.length + ' entries') + '</span><span class="sp"></span><button type="button" class="small" id="jNew">New entry</button></h2><div id="jTable"></div></div>';
  var t = table({id: 'diario', dated: true, rows: entries, dateKey: 'date', defaultSort: 'entry_no', pageSize: 25, empty: 'No entries in these days.',
    columns: [{key: 'entry_no', label: 'Nº', num: true, render: function(e){ return '<span class="mono">' + esc(e.entry_no) + '</span>'; }}, {key: 'date', label: 'Date', nw: true, render: function(e){ return '<span class="mono">' + esc(e.date) + '</span>'; }},
      {key: 'memo', label: 'Description', render: function(e){ return esc(e.memo) + (e.reversed ? ' ' + tag('rev', 'reversed') : '') + (e.reverses ? ' ' + tag('', 'reverses Nº ' + e.reverses) : ''); }},
      {key: 'source', label: 'Source', render: function(e){ return tag('', SRC[e.source] || e.source); }, text: function(e){ return SRC[e.source] || e.source; }},
      {key: 'amount', label: 'Amount', num: true, sortVal: function(e){ return sum(e.lines || [], function(l){ return l.debit; }); }, render: function(e){ return '<span class="mono">' + fmt(sum(e.lines || [], function(l){ return l.debit; })) + '</span>'; }},
      {key: 'created_by', label: 'By', render: function(e){ return '<span class="hint">' + esc(e.created_by || '') + '</span>'; }}],
    filters: [{key: 'source', label: 'Source', options: Object.keys(SRC).map(function(k){ return [k, SRC[k]]; })}, {key: 'account', label: 'Account', value: function(e){ return (e.lines || []).some(function(l){ return l.account === (TBL.diario.f.account || ''); }) ? TBL.diario.f.account : ''; }, options: ((OV && OV.accounts) || []).map(function(a){ return [a.code, a.code + ' · ' + a.name]; })}],
    onRow: entryDetail,
    csv: function(rows){ var out = [['entry_no', 'date', 'source', 'memo', 'account', 'account_name', 'debit', 'credit', 'line_memo']]; rows.forEach(function(e){ (e.lines || []).forEach(function(l){ out.push([e.entry_no, e.date, e.source, e.memo, l.account, l.name, l.debit, l.credit, l.memo || '']); }); }); return ['diario-' + from + '-' + to + '.csv', out]; }});
  host.querySelector('#jTable').appendChild(t);
  /* dates typed in the table reload from the server */
  ['from', 'to'].forEach(function(k){ var i = t.querySelector('[data-' + k + ']'); if (i) i.addEventListener('change', function(){ forget('journal'); drawBooks(host.parentNode); }); });
  var jp = host.querySelector('#jPost'); if (jp) jp.addEventListener('click', function(){ postDays(OV.pending_days, jp).then(function(){ forget('journal'); drawBooks(host.parentNode); }); });
  host.querySelector('#jNew').addEventListener('click', function(){ entryForm(); });
  return host;
}
function entryDetail(e){
  var canRev = !e.reversed && (e.source === 'manual' || e.source === 'opening');
  openDrawer('Entry Nº ' + e.entry_no,
    '<dl class="dl"><dt>Date</dt><dd class="mono">' + esc(e.date) + '</dd><dt>Source</dt><dd>' + esc(SRC[e.source] || e.source) + '</dd><dt>Description</dt><dd>' + esc(e.memo) + '</dd><dt>By</dt><dd>' + esc(e.created_by || '') + '</dd>' +
    (e.reverses ? '<dt>Reverses</dt><dd>Nº ' + esc(e.reverses) + '</dd>' : '') + (e.reversed ? '<dt>State</dt><dd>' + tag('rev', 'reversed by a later entry') + '</dd>' : '') + '</dl>' + linesTable(e.lines || []) +
    (!e.reversed && !canRev && e.source !== 'reversal' ? '<p class="note">This entry came from a document (a day, an expense, a supplier, the bank, a payroll): undo it from that document and the books follow.</p>' : '') +
    (canRev ? '<div class="form one" style="margin-top:.8rem"><div><label for="rv-why">Why is it reversed?</label><input id="rv-why" maxlength="200" placeholder="Reason (required)"></div></div>' : ''),
    canRev ? '<button type="button" class="ghost" id="rv-cancel">Close</button><button type="button" class="danger" id="rv-go">Reverse this entry</button>' : '<button type="button" class="ghost" id="rv-cancel">Close</button>');
  $('rv-cancel').addEventListener('click', closeDrawer);
  var g = $('rv-go'); if (g) g.addEventListener('click', function(){
    var why = $('rv-why').value.trim(); if (!why){ footErr('Write the reason.'); return; }
    busy(g, async function(){ try { await rpc('acct_journal_reverse', {p_entry_id: e.id, p_date: today(), p_memo: why}); toast('Reversal posted'); closeDrawer(); forget('journal'); reloadOverview().then(render); } catch (x){ footErr(errText(x)); } });
  });
}
/* a manual entry: at least two lines, debits = credits; the server checks the period and the accounts */
function entryForm(){
  var req = uuid();
  function lrow(acc, d, c){ return '<div class="lrow"><select aria-label="Account"><option value="">Account…</option>' + acctOptions(acc || '', true) + '</select><input type="number" min="0" step="any" placeholder="Debit" data-keypad="amount" aria-label="Debit" value="' + (d || '') + '"><input type="number" min="0" step="any" placeholder="Credit" data-keypad="amount" aria-label="Credit" value="' + (c || '') + '"><button type="button" class="ghost small" data-x aria-label="Remove the line">×</button></div>'; }
  openDrawer('New entry',
    '<div class="form"><div><label for="ne-date">Date</label><input type="date" id="ne-date" value="' + today() + '"></div><div class="full"><label for="ne-memo">Description</label><input id="ne-memo" maxlength="200" placeholder="What this entry records"></div>' +
    '<div class="full lines" id="ne-lines">' + lrow() + lrow() + '</div><div class="full"><button type="button" class="ghost small" id="ne-add">Add a line</button> <span class="hint mono" id="ne-sum"></span></div>' +
    '<div class="full"><label><input type="checkbox" id="ne-opening"> Opening balances (one time, when the books start)</label></div></div>',
    '<button type="button" class="ghost" id="ne-cancel">Cancel</button><button type="button" id="ne-save">Post the entry</button>');
  function readLines(){ return Array.prototype.map.call($('ne-lines').querySelectorAll('.lrow'), function(r){ var f = r.querySelectorAll('select,input'); return {account: f[0].value, debit: Number(f[1].value) || 0, credit: Number(f[2].value) || 0}; }).filter(function(l){ return l.account && (l.debit || l.credit); }); }
  function sumLines(){ var ls = readLines(), d = sum(ls, function(l){ return l.debit; }), c = sum(ls, function(l){ return l.credit; }); $('ne-sum').textContent = 'Debit ' + fmt(d) + ' · Credit ' + fmt(c) + (Math.round(d * 100) === Math.round(c * 100) ? '' : ' · difference ' + fmt(d - c)); }
  function wire(){ $('ne-lines').querySelectorAll('[data-x]').forEach(function(x){ x.onclick = function(){ x.closest('.lrow').remove(); sumLines(); }; }); $('ne-lines').querySelectorAll('input').forEach(function(i){ i.oninput = sumLines; }); }
  wire(); sumLines();
  $('ne-add').addEventListener('click', function(){ $('ne-lines').insertAdjacentHTML('beforeend', lrow()); wire(); });
  $('ne-cancel').addEventListener('click', closeDrawer);
  $('ne-save').addEventListener('click', function(){
    var ls = readLines(), memo = $('ne-memo').value.trim();
    if (!memo){ footErr('Write a description.'); return; }
    if (ls.length < 2){ footErr('An entry needs at least two lines.'); return; }
    busy(this, async function(){ try { var d = await rpc('acct_entry_post', {p_date: $('ne-date').value, p_memo: memo, p_lines: ls, p_request_id: req, p_opening: $('ne-opening').checked}); toast('Entry Nº ' + d.entry_no + ' posted'); closeDrawer(); forget('journal'); reloadOverview().then(render); } catch (x){ footErr(errText(x)); } });
  });
}
/* the chart of accounts: codes, names, types; cash or bank marks the accounts the cash position reads */
function drawAccounts(){
  var host = document.createElement('div');
  host.innerHTML = '<div class="card"><h2>Chart of accounts<span class="sp"></span><button type="button" class="small" id="aNew">New account</button></h2><p class="hint">' + esc(OV.approved ? 'Approved by the accountant.' : 'A proposal until the accountant approves it (Activation).') + '</p><div id="aTable"></div></div>';
  var t = table({id: 'cuentas', rows: OV.accounts || [], defaultSort: 'code', pageSize: 50, search: true,
    columns: [{key: 'code', label: 'Code', nw: true, render: function(a){ return '<span class="mono">' + esc(a.code) + '</span>'; }}, {key: 'name', label: 'Name', render: function(a){ return esc(a.name) + (a.cash ? ' ' + tag('', 'cash or bank') : '') + (a.active ? '' : ' ' + tag('rev', 'inactive')); }},
      {key: 'type', label: 'Type', render: function(a){ return esc(TYPE[a.type] || a.type); }, text: function(a){ return TYPE[a.type] || a.type; }},
      {key: 'act', label: '', sort: false, render: function(){ return '<button type="button" class="ghost small" data-act="edit">Edit</button>'; }}],
    filters: [{key: 'type', label: 'Type', options: Object.keys(TYPE).map(function(k){ return [k, TYPE[k]]; })}, {key: 'active', label: 'State', options: [['true', 'Active'], ['false', 'Inactive']]}],
    onAct: function(act, a){ accountForm(a); },
    csv: function(rows){ return ['catalogo-cuentas.csv', [['code', 'name', 'type', 'cash', 'active']].concat(rows.map(function(a){ return [a.code, a.name, a.type, a.cash ? 'yes' : 'no', a.active ? 'yes' : 'no']; }))]; }});
  host.querySelector('#aTable').appendChild(t);
  host.querySelector('#aNew').addEventListener('click', function(){ accountForm(null); });
  return host;
}
function accountForm(a){
  openDrawer(a ? 'Account ' + a.code : 'New account',
    '<div class="form"><div><label for="ac-code">Code (4 to 8 digits)</label><input id="ac-code" inputmode="numeric" maxlength="8" value="' + esc(a ? a.code : '') + '"' + (a ? ' disabled' : '') + '></div><div class="full"><label for="ac-name">Name</label><input id="ac-name" maxlength="80" value="' + esc(a ? a.name : '') + '"></div>' +
    '<div><label for="ac-type">Type</label><select id="ac-type">' + Object.keys(TYPE).map(function(k){ return '<option value="' + k + '"' + ((a ? a.type : 'expense') === k ? ' selected' : '') + '>' + esc(TYPE[k]) + '</option>'; }).join('') + '</select></div>' +
    '<div><label><input type="checkbox" id="ac-cash"' + (a && a.cash ? ' checked' : '') + '> Cash or bank account</label></div><div><label><input type="checkbox" id="ac-active"' + (!a || a.active ? ' checked' : '') + '> Active</label></div></div>',
    '<button type="button" class="ghost" id="ac-cancel">Cancel</button><button type="button" id="ac-save">Save</button>');
  function cashOnlyAsset(){ var asset = $('ac-type').value === 'asset'; $('ac-cash').disabled = !asset; if (!asset) $('ac-cash').checked = false; }
  cashOnlyAsset(); $('ac-type').addEventListener('change', cashOnlyAsset);
  $('ac-cancel').addEventListener('click', closeDrawer);
  $('ac-save').addEventListener('click', function(){
    busy(this, async function(){ try { await rpc('acct_account_save', {p_code: $('ac-code').value.trim(), p_name: $('ac-name').value.trim(), p_type: $('ac-type').value, p_cash: $('ac-cash').checked, p_active: $('ac-active').checked}); toast('Account saved'); closeDrawer(); forget(); reloadOverview().then(render); } catch (x){ footErr(errText(x)); } });
  });
}
/* mappings: which account each automatic posting uses */
function drawMappings(){
  var host = document.createElement('div');
  host.innerHTML = '<div class="card"><h2>Mappings</h2><p class="hint">Which account each automatic entry uses (sales, IVA, each payment method, cost of sales…). Changing one affects the entries from now on; the ones already posted stay.</p><div class="tbox"><table class="narrow"><thead><tr><th>Posting</th><th>Account</th></tr></thead><tbody>' +
    (OV.mappings || []).map(function(m){ return '<tr><td>' + esc(m.label) + '<span class="sub mono">' + esc(m.key) + '</span></td><td><select data-key="' + esc(m.key) + '" aria-label="' + esc(m.label) + '">' + acctOptions(m.account, true) + '</select></td></tr>'; }).join('') + '</tbody></table></div><p class="err" id="mErr"></p></div>';
  host.querySelectorAll('select[data-key]').forEach(function(s){
    var was = s.value;
    s.addEventListener('change', async function(){ try { await rpc('acct_mapping_set', {p_key: s.dataset.key, p_account: s.value}); was = s.value; $('mErr').textContent = ''; toast('Saved'); forget(); reloadOverview(); } catch (x){ $('mErr').textContent = errText(x); s.value = was; } });
  });
  return host;
}
/* periods: a month closes when its entries are done, locks when it was filed */
function drawPeriods(){
  var host = document.createElement('div'), ps = OV.periods || [], pend = OV.pending_days || [];
  host.innerHTML = '<div class="card"><h2>Periods</h2><p class="hint">Open: entries can be posted. Closed: nothing more is posted until it is reopened. Locked: it was filed and never changes again.</p>' +
    (pend.length ? '<div class="banner"><b>' + esc(pend.length + ' closed days are not in the books yet') + '</b><span class="hint">' + esc('from ' + pend[0] + ' to ' + pend[pend.length - 1] + '. Post them before closing their month.') + '</span></div>' : '') +
    '<div class="tbox"><table class="narrow"><thead><tr><th>Month</th><th>State</th><th>Changed</th><th></th></tr></thead><tbody>' +
    (ps.length ? ps.map(function(p){ var m = String(p.id), inMonth = pend.filter(function(d){ return d.slice(0, 7) === m.slice(0, 4) + '-' + m.slice(4); }).length; return '<tr><td class="mono">' + m.slice(0, 4) + '-' + m.slice(4) + (inMonth ? ' ' + tag('est', inMonth + ' days not posted') : '') + '</td><td>' + esc(PSTATUS[p.status] || p.status) + '</td><td class="hint">' + esc(p.changed_by ? p.changed_by + ' · ' + crDate(p.changed_at) : '') + '</td><td class="nw">' +
      (p.status === 'open' ? '<button type="button" class="ghost small" data-p="' + p.id + '" data-to="closed">Close</button>' : '') + (p.status === 'closed' ? '<button type="button" class="ghost small" data-p="' + p.id + '" data-to="open">Reopen</button> <button type="button" class="ghost small" data-p="' + p.id + '" data-to="locked" data-ask="1">Lock</button>' : '') + '</td></tr>'; }).join('') : '<tr><td colspan="4" class="hint">No entries yet.</td></tr>') +
    '</tbody></table></div><p class="err" id="pErr"></p></div>';
  host.querySelectorAll('button[data-p]').forEach(function(b){
    b.addEventListener('click', function(){
      if (b.dataset.ask && !confirm('Lock this month for good? It can never change again.')) return;
      busy(b, async function(){ try { await rpc('acct_period_set', {p_period: Number(b.dataset.p), p_status: b.dataset.to}); $('pErr').textContent = ''; toast('Saved'); forget(); await reloadOverview(); render(); } catch (x){ $('pErr').textContent = errText(x); } });
    });
  });
  return host;
}
/* electronic documents: what would be sent, once there is a provider; nothing is sent from here */
async function drawEdocs(){
  var r = range(), from = r.from, to = r.to, d;
  try { d = await loadEdocs(from, to); } catch (x){ if (missing(x)) return '<p class="hint">Electronic documents need a database update (migration 0018).</p>'; throw x; }
  var mode = d.mode === 'shadow' || d.mode === '"shadow"' ? 'shadow' : 'off', host = document.createElement('div');
  host.innerHTML = '<div class="card"><h2>Electronic documents ' + tag(mode === 'shadow' ? 'est' : '', mode === 'shadow' ? 'recording only' : 'off') + '</h2><p class="hint">' + esc(mode === 'shadow' ? 'Recording only: each sale and refund records its document here to check the data. Nothing is sent to Hacienda or to any provider.' : 'Off: nothing is recorded or sent. To check the data before choosing a provider, the owner switches on "Record only" in Home → Settings.') + '</p>' +
    '<p class="hint">' + Object.keys(d.counts || {}).map(function(k){ return esc((E_STATUS[k] || k) + ' ' + d.counts[k]); }).join(' · ') + '</p>' +
    ((d.products_without_cabys || []).length ? '<details class="more"><summary class="err">' + esc(d.products_without_cabys.length + ' products on sale have no CABYS code yet (Admin → Menu)') + '</summary><p class="hint">' + esc(d.products_without_cabys.join(', ')) + '</p></details>' : '') + '<div id="eTable"></div></div>';
  var t = table({id: 'edocs', rows: d.documents || [], defaultSort: 'created_at', pageSize: 25, empty: 'No documents in these days.',
    columns: [{key: 'internal_no', label: 'Internal Nº', nw: true, render: function(x){ return '<span class="mono">' + esc(x.internal_no) + '</span>'; }}, {key: 'created_at', label: 'When', nw: true, render: function(x){ return '<span class="mono">' + esc(crTime(x.created_at)) + '</span>'; }},
      {key: 'receipt_no', label: 'Receipt', render: function(x){ return '<span class="mono">' + esc(x.receipt_no || '') + '</span>'; }}, {key: 'kind', label: 'Kind', render: function(x){ return esc(E_KIND[x.kind] || x.kind) + (x.receiver ? ' · ' + esc(x.receiver.name) : ''); }, text: function(x){ return (E_KIND[x.kind] || x.kind) + ' ' + (x.receiver ? x.receiver.name : ''); }},
      {key: 'total_crc', label: 'Total', num: true, render: function(x){ return '<span class="mono">' + fmt(x.total_crc) + '</span>'; }}, {key: 'tax_crc', label: 'IVA', num: true, render: function(x){ return '<span class="mono">' + (x.tax_crc == null ? '' : fmt(x.tax_crc)) + '</span>'; }},
      {key: 'status', label: 'State', render: function(x){ return tag(x.status === 'rejected' || x.status === 'error' ? 'rev' : '', E_STATUS[x.status] || x.status); }, text: function(x){ return E_STATUS[x.status] || x.status; }},
      {key: 'missing', label: 'Missing', sort: false, render: function(x){ return '<span class="hint">' + esc((x.missing || []).map(function(m){ return m === 'reference' ? 'the sale\'s document' : m.replace(/^cabys:/, 'CABYS: '); }).join(', ')) + '</span>'; }}],
    filters: [{key: 'kind', label: 'Kind', options: Object.keys(E_KIND).map(function(k){ return [k, E_KIND[k]]; })}, {key: 'status', label: 'State', options: Object.keys(E_STATUS).map(function(k){ return [k, E_STATUS[k]]; })}],
    csv: function(rows){ return ['documentos-electronicos-' + from + '-' + to + '.csv', [['internal_no', 'created_at', 'receipt_no', 'kind', 'receiver', 'total_crc', 'tax_crc', 'status', 'missing']].concat(rows.map(function(x){ return [x.internal_no, x.created_at, x.receipt_no, x.kind, x.receiver ? x.receiver.name : '', x.total_crc, x.tax_crc, x.status, (x.missing || []).join(' ')]; }))]; }});
  host.querySelector('#eTable').appendChild(t);
  return host;
}
/* payroll stays where it is: its screens, rules and confirmations are untouched by this redesign */
function drawPayroll(){
  return '<div class="card"><h2>Payroll</h2><p class="hint">The payroll (periods, approved hours, pay rates, Costa Rican rules, aguinaldo and vacations) keeps its own screens. Nothing changes there with this page.</p>' +
    '<p><a class="btn" href="accounting.html#payroll">Open the payroll</a></p><p class="note">What the law sets (percentages, the tax table, vacation days) is entered by your accountant with the document. Until confirmed, everything there is an estimate and nothing is withheld, provisioned or posted.</p></div>';
}
/* audit: who did what in the books, suppliers, expenses and the bank */
async function drawAudit(){
  var st = TBL.audit, r = range(), from = st && st.touched && st.from ? st.from : r.from, to = st && st.touched && st.to ? st.to : r.to, rows;
  try { rows = await loadAudit(from, to); } catch (x){ if (missing(x)){ MIG.v34 = false; return '<div class="banner bad"><b>The audit needs migration 0034.</b><span class="hint">The owner applies it in Supabase → SQL Editor after the backup.</span></div>'; } throw x; }
  var host = document.createElement('div'); host.innerHTML = '<div class="card"><h2>Audit <span class="hint">' + esc(rows.length + ' actions' + (rows.length >= 500 ? ' (the first 500)' : '')) + '</span></h2><div id="auTable"></div></div>';
  var acts = {}; rows.forEach(function(x){ acts[x.action] = true; });
  var t = table({id: 'audit', dated: true, rows: rows, dateKey: 'at', defaultSort: 'at', pageSize: 25, empty: 'No actions in these days.',
    columns: [{key: 'at', label: 'When', nw: true, render: function(x){ return '<span class="mono">' + esc(crTime(x.at)) + '</span>'; }}, {key: 'action', label: 'Action', render: function(x){ return tag('', x.action); }},
      {key: 'who', label: 'Who', render: function(x){ return esc(x.who || ''); }}, {key: 'summary', label: 'What', render: function(x){ return esc(x.summary || ''); }}, {key: 'target', label: 'Record id', render: function(x){ return '<span class="hint mono">' + esc(x.target || '') + '</span>'; }}],
    filters: [{key: 'action', label: 'Action', options: Object.keys(acts).sort().map(function(k){ return [k, k]; })}],
    onRow: function(x){ openDrawer(x.action, '<dl class="dl"><dt>When</dt><dd class="mono">' + esc(crTime(x.at)) + '</dd><dt>Who</dt><dd>' + esc(x.who || '') + '</dd><dt>What</dt><dd>' + esc(x.summary || '') + '</dd><dt>Record id</dt><dd class="mono">' + esc(x.target || '') + '</dd></dl>' + (x.details && Object.keys(x.details).length ? '<pre class="mono" style="font-size:.78rem;white-space:pre-wrap;margin-top:.8rem">' + esc(JSON.stringify(x.details, null, 1)) + '</pre>' : ''), '<button type="button" class="ghost" id="au-close">Close</button>'); $('au-close').addEventListener('click', closeDrawer); },
    csv: function(rs){ return ['auditoria-' + from + '-' + to + '.csv', [['at', 'action', 'who', 'summary', 'target']].concat(rs.map(function(x){ return [x.at, x.action, x.who, x.summary, x.target]; }))]; }});
  host.querySelector('#auTable').appendChild(t);
  ['from', 'to'].forEach(function(k){ var i = t.querySelector('[data-' + k + ']'); if (i) i.addEventListener('change', function(){ forget('audit'); drawBooks(host.parentNode); }); });
  return host;
}
/* activation: the accountant approves the chart of accounts and the first day; then the register close posts each day (owner only) */
function drawActivation(){
  var auto = OV.auto_post === true || OV.auto_post === 'true', host = document.createElement('div');
  host.innerHTML = '<div class="card"><h2>Activation ' + tag(auto ? 'final' : 'est', auto ? 'posting each day' : 'not activated') + '</h2>' +
    (auto ? '<p class="hint">' + esc('The books post each day at the register close' + (OV.start_date ? ', from ' + String(OV.start_date).replace(/"/g, '') : '') + '. Approved by the accountant: yes.') + '</p>' :
    '<p class="hint">The chart of accounts is a proposal. Once your accountant approves it (and the first day to post), the register close posts each day automatically. Until then a day can be posted by hand to review it.</p>' +
    '<div class="form"><div><label for="ap-who">Approved by (accountant)</label><input id="ap-who" maxlength="80"></div><div><label for="ap-ref">Document or reference</label><input id="ap-ref" maxlength="120"></div><div><label for="ap-start">First day to post</label><input id="ap-start" type="date" value="' + monthStart(today()) + '"></div></div>' +
    '<p class="err" id="ap-err"></p><p><button type="button" id="ap-go">Record the approval and activate</button></p>') +
    '<h3>What stays off</h3><p class="hint">Electronic invoicing to Hacienda, payroll withholdings and the automatic IVA return stay off until each one has its confirmation, its provider or its accountant\'s rules (Home → Settings). This page activates nothing of that.</p></div>';
  var g = host.querySelector('#ap-go'); if (g) g.addEventListener('click', function(){
    var who = $('ap-who').value.trim(), ref = $('ap-ref').value.trim(), start = $('ap-start').value;
    if (!who || !ref || !start){ $('ap-err').textContent = 'Write who approved it, the document and the first day.'; return; }
    busy(g, async function(){ try { await rpc('compliance_confirm', {p_key: 'chart_of_accounts_approved', p_confirmed_by: who, p_reference: ref}); await rpc('setting_set', {p_key: 'ledger_start_date', p_value: start}); await rpc('setting_set', {p_key: 'ledger_auto_post', p_value: true}); toast('The books now post each day at the register close'); forget(); await reloadOverview(); render(); } catch (x){ $('ap-err').textContent = errText(x); } });
  });
  return host;
}

/* ---------- a drawer that reads before it opens never fails in silence: without connection it says so ---------- */
function guarded(fn){ return function(){ var r; try { r = fn.apply(this, arguments); } catch (e){ toast(errText(e)); return; } if (r && typeof r.then === 'function') return r.catch(function(e){ toast(errText(e)); }); return r; }; }
expenseForm = guarded(expenseForm); expenseDetail = guarded(expenseDetail); payExpenseForm = guarded(payExpenseForm); schedulesDrawer = guarded(schedulesDrawer); scheduleForm = guarded(scheduleForm);
vendorCard = guarded(vendorCard); invoiceForm = guarded(invoiceForm); paymentForm = guarded(paymentForm); bankPostForm = guarded(bankPostForm); bankLineDetail = guarded(bankLineDetail);

/* ---------- boot ---------- */
refreshAuth();
