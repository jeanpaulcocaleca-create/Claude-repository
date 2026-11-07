/* Canopy OS · proveedores.html: the suppliers' hub (D-067, migration 0039).
   One page for what Inventario's «Pedidos» and «Proveedores» did, plus what they never did: each supplier's own catalog,
   ordering with checkboxes (autosaved drafts), the order document (Copy / PDF / Print: the owner's three), receiving by
   management OR by any employee on shift (a work session on this device: «Recibe en este aparato»), supplier invoices
   and payments (SINPE with its confirmation number, or card) before or after receiving.
   * Every read and write goes through the 0039 functions (§4 of the build contract); the server checks every right, the
     page only shows what the answer allows (can_manage, can_pay, can_owner).
   * Two modes: management (owner/manager unlock on this device, the owner with the phone code, or the accountant) and
     receive (a café login without an unlock). When an unlock ends, management data leaves memory and the screen.
   * English source text; lang.js (loaded last) shows it in Spanish. What goes to a supplier (Copy, PDF, Print) is
     hard-coded Spanish. Every server string reaches the DOM through esc() or textContent.
   * Request ids are kept until the server answers (localStorage for the draft and the receive form, memory otherwise),
     so a lost answer never books anything twice. PIN boxes are emptied after every call and never kept.
   Tests may set window.PROV_TEST = {idleMs: n} before load. */
(function () {
  'use strict';
  var CFG = window.HG_CONFIG;
  if (!CFG || CFG.blocked || !CFG.url || !CFG.key) return;   /* config.js already stopped an unknown address */

  /* ---------- 1) small helpers ---------- */
  function $(id) { return document.getElementById(id); }
  function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
  /* a server string (a name, a note): escaped and never put through the dictionary (a product called "Milk" stays "Milk") */
  function nt(s) { return '<span data-no-translate>' + esc(s) + '</span>'; }
  function round(n, d) { var f = Math.pow(10, d == null ? 2 : d); return Math.round((Number(n) || 0) * f) / f; }
  function fmt(n) { return '₡' + Math.round(Number(n) || 0).toLocaleString('fr-FR'); }
  /* colones with cents only when there are cents */
  function fmtC(n) {
    var r = round(n, 2);
    return '₡' + (Math.abs(r - Math.round(r)) < 0.005 ? Math.round(r).toLocaleString('fr-FR') : r.toLocaleString('fr-FR', { minimumFractionDigits: 2, maximumFractionDigits: 2 }));
  }
  function num(n, d) { return (Number(n) || 0).toLocaleString('fr-FR', { maximumFractionDigits: d == null ? 3 : d }); }
  function plainNum(n) { return n == null || n === '' || !isFinite(Number(n)) ? '' : String(round(n, 3)); }
  /* a typed number: digits with one . or , (no letters, no signs); NaN otherwise */
  function parseNum(s) {
    s = String(s == null ? '' : s).trim().replace(/\s+/g, '').replace(',', '.');
    return /^\d+(\.\d+)?$|^\.\d+$/.test(s) ? Number(s) : NaN;
  }
  function decimals(n) { var s = String(n); return s.indexOf('.') < 0 ? 0 : s.split('.')[1].length; }
  function norm(s) { return String(s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, ''); }
  function uuid() {
    if (window.crypto && crypto.randomUUID) return crypto.randomUUID();
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) { var r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3 | 8)).toString(16); });
  }
  function isUuid(s) { return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(String(s || '')); }
  function two(n) { return String(n).padStart(2, '0'); }
  function hhmm(iso) { var d = new Date(iso); return isNaN(d) ? '' : two(d.getHours()) + ':' + two(d.getMinutes()); }
  function dateOf(iso) { if (!iso) return null; var d = new Date(String(iso).length === 10 ? iso + 'T12:00:00' : iso); return isNaN(d) ? null : d; }
  function fmtD(iso) { var d = dateOf(iso); return d ? d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' }) : ''; }
  function fmtDY(iso) { var d = dateOf(iso); return d ? d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }) : ''; }
  function fmtDT(iso) { var d = dateOf(iso); return d ? fmtD(iso) + ' ' + hhmm(iso) : ''; }
  function todayIso() { var d = new Date(); return new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 10); }
  function addDays(iso, n) { var d = new Date(iso + 'T12:00:00'); d.setDate(d.getDate() + n); return new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 10); }
  function daysAgo(iso) { var d = dateOf(iso); return d ? Math.max(0, Math.floor((Date.now() - d.getTime()) / 86400000)) : 0; }
  var UNIT = { unit: 'units', g: 'g', kg: 'kg', ml: 'ml', L: 'L' };
  function unitWord(u, n) { return u === 'unit' ? (Number(n) === 1 ? 'unit' : 'units') : (UNIT[u] || u || ''); }
  function qtyU(n, u) { return num(n, u === 'unit' ? 2 : 3) + ' ' + unitWord(u, n); }
  /* «caja de 12 · 12 units» (the label is data, the units are English for lang.js) */
  function presHtml(p) {
    var q = '<span>' + esc(qtyU(p.pack_qty, p.unit)) + '</span>';
    return p.pack_label ? nt(p.pack_label) + ' · ' + q : q;
  }
  function pname(p) { return p.label || p.item_name || ''; }
  function ls(k, v) {
    try {
      if (v === undefined) return JSON.parse(localStorage.getItem(k) || 'null');
      if (v === null) localStorage.removeItem(k); else localStorage.setItem(k, JSON.stringify(v));
    } catch (e) { return null; }
    return v;
  }
  var toastT = null;
  function toast(msg) { var t = $('toast'); t.textContent = msg; t.classList.add('on'); clearTimeout(toastT); toastT = setTimeout(function () { t.classList.remove('on'); }, 3200); }
  /* a small element builder for the pieces that carry listeners */
  function el(tag, cls, html) { var e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; }
  function btn(label, cls, fn, attrs) {
    var b = document.createElement('button'); b.type = 'button'; b.className = cls || ''; b.textContent = label;
    Object.keys(attrs || {}).forEach(function (k) { b.setAttribute(k, attrs[k]); });
    if (fn) b.addEventListener('click', fn);
    return b;
  }
  function link(label, href, cls) { var a = document.createElement('a'); a.href = href; a.className = cls || 'btnlink small'; a.textContent = label; return a; }
  function stationName() { var s = ls('hg-pos-station'); return s && s.name ? String(s.name).slice(0, 40) : null; }

  /* ---------- 2) the database client and the one way every call goes ---------- */
  var db = window.supabase.createClient(CFG.url, CFG.key, window.HG_LOGIN ? HG_LOGIN.options(HG_ACCESS.options()) : HG_ACCESS.options());
  function offlineErr(r) { return r && (r.status === 0 || (r.error && /Failed to fetch|NetworkError|Load failed|fetch failed|FetchError|TypeError|ERR_|aborted/i.test(String(r.error.message || '') + ' ' + String(r.error.details || '')))); }
  /* -> the answer of the function ({ok, …}), or {ok:false, error:'offline'|'signed_out'|'missing'|'server'} */
  async function call(name, args) {
    var r;
    try { r = await db.rpc(name, args || {}); } catch (e) { return { ok: false, error: 'offline', offline: true }; }
    if (r.error) {
      if (offlineErr(r)) return { ok: false, error: 'offline', offline: true };
      if (r.status === 401 || /jwt/i.test(r.error.message || '')) return { ok: false, error: 'signed_out', auth: true };
      if (r.error.code === 'PGRST202' || /could not find the function|schema cache/i.test(r.error.message || '')) return { ok: false, error: 'missing', missing: true };
      return { ok: false, error: 'server' };
    }
    var d = r.data;
    if (d && typeof d === 'object' && !Array.isArray(d)) return d.ok === false ? d : Object.assign({ ok: true }, d);
    return { ok: true, data: d };
  }
  var BUSY = 0;
  /* the page's calls: a closed owner area re-opens the gate and resumes; an employee whose sign-in moved is rebound once */
  async function rpc(name, args, retried) {
    BUSY++;
    var r;
    try { r = await call(name, args); } finally { BUSY--; }
    if (r.error === 'no_session' && MODE === 'receive' && args && args.p_token) {
      if (r.why === 'moved' && !retried && await checkTurno(true) && TURNO) { args.p_token = TURNO.token; return rpc(name, args, true); }
      if (r.why !== 'moved' || retried) dropTurno(r.why);
      r.handled = true;
    } else if (r.error === 'locked' && MODE === 'manage') {
      r.handled = true;
      onLocked();
    } else if (r.auth) {
      r.handled = true;
      keepDirty('signed_out');
      refreshAuth();
    }
    return r;
  }

  /* every error code of the 0039 functions, in English (lang.js has the Spanish) */
  var ERR = {
    offline: 'No connection: not saved. Try again.',
    server: 'Something went wrong. Reload the page and try again.',
    missing: 'This needs the database update of Proveedores (migration 0039). Tell the owner.',
    signed_out: 'The sign-in ended. Sign in again: what you typed is kept.',
    locked: 'The owner areas closed on this device. Type a manager PIN again.',
    no_session: 'Your shift on this device ended. Say who you are again.',
    not_found: 'That is no longer here. Reload the page.',
    bad_request: 'Something in the form is not right. Check it and try again.',
    changed: 'Someone changed this a moment ago. Check it and try again.',
    closed: 'This order is closed: only its note and its delivery date can change.',
    cancelled: 'This order has been cancelled.',
    already_received: 'This order has already been received.',
    empty: 'Nothing to save: type at least one quantity.',
    over_pending: 'That is more than what is still pending.',
    duplicate_line: 'That product is already on the order.',
    removed_line: 'That line was taken off the order.',
    bad_qty: 'Check the quantities: above zero, with at most 3 decimals.',
    bad_price: 'Check the prices: zero or more.',
    check_price: 'That price is very different from the expected one.',
    needs_price: 'Type the price of that product.',
    duplicate_name: 'There is already a supplier with that name.',
    duplicate_product: 'This supplier already has that product in that presentation.',
    duplicate_item: 'There is already an inventory item with that name.',
    vendor_inactive: 'This supplier is inactive. Activate it first.',
    item_inactive: 'That inventory item is inactive.',
    duplicate_invoice: 'That invoice number is already registered for this supplier.',
    needs_reference: 'Type the SINPE confirmation number.',
    bad_reference: 'The SINPE confirmation number does not look right: 4 to 40 letters or numbers.',
    duplicate_reference: 'That SINPE number is already registered.',
    possible_duplicate: 'A payment just like this one was registered a few minutes ago.',
    over_balance: 'That is more than what is owed.',
    needs_reason: 'Write the reason (at least 5 letters).',
    needs_owner: 'Only the owner can do that.',
    not_receiver: 'Receiving is done by the owner, a manager or the staff on shift.',
    busy: 'The stock of these products is being used by a sale right now. Try again in a moment.',
    credit_needs_owner: 'That would leave money in our favour with this supplier (a payment already made). Only the owner can do it.',
    bad_amount: 'Check the amount.',
    future_date: 'The date cannot be in the future.',
    bad_date: 'That date is too far back.',
    period_closed: 'That month is closed in the books.',
    bad_pin: 'That PIN is not right.',
    pin_locked: 'Too many wrong PINs. Wait 10 minutes and try again.',
    not_manager: 'That person is not a manager.',
    not_owner: 'That person is not an owner.',
    inactive: 'That person is not active on the team.',
    unknown_staff: 'Pick who you are.',
    has_receipts: 'This order already has deliveries.',
    has_payments: 'This already has payments.',
    below_received: 'That is less than what already arrived.',
    no_receipts: 'Nothing has arrived for this order yet.',
    not_clocked_in: 'You are not clocked in.',
    period_locked: 'That pay period is approved: you cannot clock in now. Tell a manager.',
    stale_shift: 'You have a shift open since an earlier day; tell a manager.',
    bad_rate: 'The exchange rate must be between 100 and 2000.',
    bad_receipts: 'Tick deliveries of this supplier that have no invoice yet.',
    payout_exceeds: 'The cash paid from the register is more than this invoice.',
    draft_changed: 'The draft changed on another device. Check it and create the order again.',
    draft_used: 'This draft already became an order.',
    invoiced: 'That delivery already has its invoice: it cannot be corrected here.',
    no_account: 'This login is not connected to the café yet.',
    unknown_account: 'An account of the books is missing. Tell the accountant.',
    bad_account: 'An account of the books is not valid. Tell the accountant.',
    in_use_elsewhere: 'Your shift is in use on another device right now. Say who you are again here.',
    too_many_rebinds: 'Too many sign-ins on this device in the last hour. Say who you are again.',
    device_taken: 'Someone else is already receiving on this device.'
  };
  /* why a work session is no longer valid (turno_estado, _prov_turno) */
  var WHY = {
    unknown: 'Your shift on this device ended. Say who you are again.',
    ended: 'Your shift on this device ended. Say who you are again.',
    expired: 'Your shift on this device ended. Say who you are again.',
    other_login: 'Your shift on this device ended. Say who you are again.',
    no_session: 'Your shift on this device ended. Say who you are again.',
    moved: 'This device signed in again. Say who you are again.',
    inactive: 'That person is not active on the team.',
    pin_changed: 'Your PIN changed. Say who you are again.',
    not_on_shift: 'You no longer have an open shift. Clock in to receive.',
    in_use_elsewhere: ERR.in_use_elsewhere, too_many_rebinds: ERR.too_many_rebinds, device_taken: ERR.device_taken
  };
  function errText(r) {
    if (!r) return ERR.server; if (r.offline) return ERR.offline;
    /* a cancel, an edit, a close or a correction that would turn a payment into money in our favour: the amount */
    if (r.error === 'credit_needs_owner' && Number(r.credit_crc) > 0) return 'That would leave {x} in our favour with this supplier (a payment already made). Only the owner can do it.'.replace('{x}', fmtC(r.credit_crc));
    return ERR[r.error] || ERR.server;
  }

  /* ---------- 3) who is signed in ---------- */
  var ACCOUNT = null, UID = null, ST = null, MODE = null, FLAGS = { can_manage: false, can_pay: false, can_owner: false };
  async function codeNeeded() {
    try { var r = await db.auth.mfa.getAuthenticatorAssuranceLevel(); return !r.error && !!r.data && r.data.nextLevel === 'aal2' && r.data.currentLevel !== 'aal2'; }
    catch (e) { return false; }
  }
  function isBooksDoor() { return ACCOUNT === 'accountant' || (ACCOUNT === 'owner' && ST && ST.via === 'phone'); }
  function ownerWithCode() { return ACCOUNT === 'owner' && ST && ST.via === 'phone'; }
  function noPinNeeded() { return ownerWithCode() || ACCOUNT === 'accountant'; }
  var idleTimer = null;
  function idleMs() { return (window.PROV_TEST && PROV_TEST.idleMs) || 30 * 60000; }
  /* the owner with the phone code and the accountant are signed out after 30 idle minutes; never a café tablet,
     never while something typed is not saved */
  function armIdle() {
    clearTimeout(idleTimer);
    if (ACCOUNT !== 'owner' && ACCOUNT !== 'accountant') return;
    if (ACCOUNT === 'owner' && !ownerWithCode()) return;
    idleTimer = setTimeout(async function () {
      if (isDirty()) { armIdle(); return; }
      await db.auth.signOut({ scope: 'local' }); location.reload();
    }, idleMs());
  }
  ['pointerdown', 'keydown', 'touchstart', 'scroll'].forEach(function (ev) { document.addEventListener(ev, armIdle, { passive: true }); });

  var AUTHING = false, AUTH_AGAIN = false;
  async function refreshAuth() {
    if (AUTHING) { AUTH_AGAIN = true; return; }
    AUTHING = true;
    try {
      var s = await db.auth.getSession();
      var sess = s.data && s.data.session, authed = !!sess;
      var needCode = authed && await codeNeeded();
      $('loginView').hidden = authed && !needCode;
      $('loginForm').hidden = needCode;
      $('codeForm').hidden = !needCode;
      $('cafeView').hidden = true;
      $('appView').hidden = !authed || needCode;
      if (needCode) { keepDirty('signed_out'); leaveMode(); $('codeIn').focus(); return; }
      if (!authed) { keepDirty('signed_out'); leaveMode(); return; }
      var newUid = sess.user && sess.user.id;
      if (UID && newUid !== UID) { leaveMode(); RESUME = null; keepResume(); }
      if (!UID && RESUME === null) { var kept = null; try { kept = JSON.parse(sessionStorage.getItem('hg-prov-resume') || 'null'); } catch (e) {} if (kept && kept.uid === newUid) RESUME = kept; }
      if (MODE && newUid === UID && ACCOUNT) return;   /* the same sign-in, already open: nothing to decide again */
      UID = newUid;
      var k = await call('account_kind');
      ACCOUNT = k.ok ? (k.data || 'none') : (k.offline ? ACCOUNT : null);
      if (k.offline && !ACCOUNT) { showMainError(ERR.offline, refreshAuth); return; }
      if (ACCOUNT === 'none' || ACCOUNT === null) { showCafeView(); return; }
      if (ACCOUNT === 'cafe' || ACCOUNT === 'none') document.querySelectorAll('[data-owner]').forEach(function (a) { a.hidden = true; });
      await decideMode();
      armIdle();
    } finally { AUTHING = false; if (AUTH_AGAIN) { AUTH_AGAIN = false; setTimeout(refreshAuth, 0); } }
  }
  function showCafeView() {
    leaveMode();
    $('cafeMsg').textContent = 'This login is not connected to the café yet. From the owner login, run the accounts script in Supabase (see the setup notes), then sign in again.';
    $('cafeView').hidden = false; $('appView').hidden = true;
  }
  $('codeForm').addEventListener('submit', async function (e) {
    e.preventDefault();
    var f = await db.auth.mfa.listFactors(), totp = f.data && f.data.totp && f.data.totp[0];
    var r = totp ? await db.auth.mfa.challengeAndVerify({ factorId: totp.id, code: $('codeIn').value.trim() }) : { error: true };
    $('codeIn').value = '';
    if (r.error) { $('codeErr').textContent = 'That code did not work. Codes change every 30 seconds, try the newest one.'; return; }
    refreshAuth();
  });
  $('loginForm').addEventListener('submit', async function (e) {
    e.preventDefault();
    var res = await HG_LOGIN.signIn(db);
    if (res.ok) refreshAuth();
  });
  $('loginForm').addEventListener('submit', function () { $('loginErr').classList.remove('ok'); }, true);
  async function signOut() { if (isDirty() && !confirm('Something typed is not saved yet. Sign out anyway?')) return; RESUME = null; keepResume(); OPEN_FORM = null; await db.auth.signOut({ scope: 'local' }); refreshAuth(); }
  $('outBtn').addEventListener('click', signOut);
  $('cafeOut').addEventListener('click', async function () { await db.auth.signOut({ scope: 'local' }); refreshAuth(); });
  db.auth.onAuthStateChange(function (ev) { if (ev === 'SIGNED_OUT' || ev === 'SIGNED_IN') setTimeout(refreshAuth, 0); });
  /* forgot password: Supabase emails a link that opens reset.html (as inventory.html) */
  $('forgotBtn').addEventListener('click', async function () {
    var b = this, msg = $('loginErr');
    var em = ($('em').value || '').trim();
    if (!em) { em = (prompt('Email of the login:') || '').trim(); if (!em) return; $('em').value = em; }
    var dir = location.href.replace(/[#?].*$/, '').replace(/[^\/]*$/, '');
    b.disabled = true;
    var r = await db.auth.resetPasswordForEmail(em, { redirectTo: dir + 'reset.html' });
    var limited = !!(r.error && (r.error.status === 429 || r.error.code === 'over_email_send_rate_limit' || /after \d+ seconds|security purposes/i.test(r.error.message || '')));
    msg.classList.toggle('ok', !r.error);
    msg.textContent = limited ? 'A link was already sent. Wait a minute and check the spam folder.'
      : r.error ? 'Could not send the email. Check the address and try again.'
      : 'If that email has a login, a link to set a new password is on its way. Check the spam folder too.';
    setTimeout(function () { b.disabled = false; }, (r.error && !limited) ? 0 : 60000);
  });

  /* ---------- 4) the two modes ---------- */
  var main = $('main');
  async function decideMode() {
    var st = await HG_ACCESS.load(db);
    HG_ACCESS.pill(db, { soft: true, host: $('pillHost') });   /* soft: the unlock's end never reloads (the watcher below acts) */
    if (st.missing) { showMainError('This needs the database update of manager mode. Tell the owner.'); return; }
    if (st.error) { showMainError(ERR.offline, refreshAuth); return; }
    ST = st;
    if (st.level || ACCOUNT === 'accountant') await enterManage(); else await enterReceive();
  }
  function leaveMode() { dropManagement(); MODE = null; $('modeBar').hidden = true; $('turnoView').hidden = true; clearTimeout(unlockTimer); }
  async function enterManage() {
    MODE = 'manage';
    $('turnoView').hidden = true;
    var bar = $('modeBar');
    if (ACCOUNT === 'accountant') { bar.innerHTML = '<span>Accounting: invoices and payments. Orders, products and suppliers are managed by the owner or a manager.</span>'; bar.hidden = false; }
    else bar.hidden = true;
    watchUnlock();
    await resumeOrRoute();
  }
  async function enterReceive() {
    dropManagement();
    MODE = 'receive';
    FLAGS = { can_manage: false, can_pay: false, can_owner: false };
    main.innerHTML = '<p class="loading">Loading…</p>';
    var ok = await checkTurno(false);
    if (MODE !== 'receive') return;
    if (!ok) { showPicker(TURNO_WHY ? (WHY[TURNO_WHY] || ERR.no_session) : null); return; }
    showTurnoBar();
    await route();
  }

  /* the unlock watcher: the soft pill (access.js) only redraws itself when the 15 minutes end or Lock is tapped; this page
     then drops every management answer from memory and the screen and goes to receive mode. Dirty form fields (never a
     PIN) are kept to resume after the PIN screen. */
  var unlockTimer = null;
  function watchUnlock() {
    clearTimeout(unlockTimer);
    if (MODE !== 'manage' || !ST || ST.via !== 'pin') return;
    var cur = HG_ACCESS.current();
    var ms = cur ? (cur.localUntil ? cur.localUntil - Date.now() : new Date(cur.until).getTime() - Date.now()) : 0;
    unlockTimer = setTimeout(unlockEnded, Math.max(0, Math.min(ms, 2147483000)) + 700);
  }
  document.addEventListener('click', function (e) {
    var t = e.target && e.target.closest ? e.target : null;
    if (t && t.closest('.hga-pill button') && MODE === 'manage') { keepDirty('lock'); dropManagement(); main.innerHTML = '<p class="loading">Locking…</p>'; setTimeout(unlockEnded, 60); }
    /* the PIN screen's «Back» while this page asked for it: back to receiving, without reloading */
    if (t && t.closest('.hga-wrap .hga-back') && GATE_OPEN) {
      e.preventDefault(); e.stopPropagation();
      var w = document.querySelector('.hga-wrap'); if (w) w.remove();
      GATE_OPEN = false;
      if (MODE !== 'receive') enterReceive(); else route();
    }
  }, true);
  async function unlockEnded(tries) {
    if (MODE !== 'manage' || !ST || ST.via !== 'pin') return;
    if (HG_ACCESS.current() && (tries || 0) < 40) { setTimeout(function () { unlockEnded((tries || 0) + 1); }, 100); return; }   /* Lock is still on its way */
    keepDirty('expired');
    var st = await HG_ACCESS.load(db);
    if (st && st.level) { ST = st; HG_ACCESS.pill(db); watchUnlock(); await resumeOrRoute(); return; }
    ST = st || {};
    await enterReceive();
  }
  var GATE_OPEN = false;
  function openGate(message) {
    GATE_OPEN = true;
    return HG_ACCESS.gate(db, { title: 'Suppliers · owners and managers', message: message || undefined, backLabel: 'Back to receiving', backHref: 'proveedores.html' })
      .then(async function (st) { GATE_OPEN = false; ST = st; await enterManage(); });
  }
  var LOCKING = false;
  async function onLocked() {
    if (LOCKING) return; LOCKING = true;
    try {
      /* the books door (the accountant) asked for what is management's: no unlock closed, nothing to type again and
         nothing to drop; it says so and goes back to where it was */
      if (isBooksDoor() && !FLAGS.can_manage) {
        closeAllModals();
        var q = parseHash();
        showMainError(ERR.needs_owner, function () { if (q.recibir) go('#pedido=' + q.recibir); else route(); }, 'Back');
        return;
      }
      keepDirty('locked');
      dropManagement();
      main.innerHTML = '';
      if (ACCOUNT === 'cafe' || ACCOUNT === 'owner_needs_code' || (ST && ST.via === 'pin')) { await openGate('The owner areas closed on this device. Type the PIN again to continue.'); }
      /* the same sign-in decided again (refreshAuth alone returns at once while the mode is open) */
      else { showMainError(ERR.locked, function () { leaveMode(); refreshAuth(); }); }
    } finally { LOCKING = false; }
  }

  /* what is kept across a closed owner area or an ended sign-in: the route and the dirty fields of the open form */
  var RESUME = null, OPEN_FORM = null;
  function formOpened(key, args, root, req) {
    OPEN_FORM = { key: key, args: args || [], root: root, dirty: false, req: req || null };
    root.addEventListener('input', function () { if (OPEN_FORM && OPEN_FORM.root === root) OPEN_FORM.dirty = true; });
    root.addEventListener('change', function () { if (OPEN_FORM && OPEN_FORM.root === root) OPEN_FORM.dirty = true; });
  }
  function formClosed(root) { if (OPEN_FORM && (!root || OPEN_FORM.root === root || (root.contains && root.contains(OPEN_FORM.root)))) OPEN_FORM = null; }
  /* the open form, while it is on the screen (a closed window's form stays in the page, hidden) */
  function liveForm() { return OPEN_FORM && OPEN_FORM.root && document.body.contains(OPEN_FORM.root) && OPEN_FORM.root.getClientRects().length ? OPEN_FORM : null; }
  function keepDirty(why) {
    if (MODE !== 'manage') return;
    var R = { hash: location.hash || '#', why: why };
    if (liveForm() && OPEN_FORM.dirty) {
      var vals = {};
      OPEN_FORM.root.querySelectorAll('input,select,textarea').forEach(function (i) {
        if (!i.id || i.hasAttribute('data-pin') || i.type === 'password') return;
        vals[i.id] = i.type === 'checkbox' || i.type === 'radio' ? i.checked : i.value;
      });
      R.key = OPEN_FORM.key; R.args = OPEN_FORM.args; R.vals = vals; R.req = OPEN_FORM.req;
      if (R.key === 'pay' && PAY) R.extra = { method: PAY.method, card: PAY.card };
    }
    R.uid = UID;
    RESUME = R; keepResume();
  }
  /* kept in this tab too, so a reload while signed out still brings it back (never a PIN; another login never sees it) */
  function keepResume() { try { if (RESUME && RESUME.key) sessionStorage.setItem('hg-prov-resume', JSON.stringify(RESUME)); else sessionStorage.removeItem('hg-prov-resume'); } catch (e) {} }
  async function resumeOrRoute() {
    var R = RESUME; RESUME = null; keepResume();
    if (R && R.uid && R.uid !== UID) R = null;
    if (R && R.hash && R.hash !== (location.hash || '#')) { SKIP_HASH = true; location.hash = R.hash; }
    await route();
    if (R && R.key && FORMS[R.key] && MODE === 'manage') {
      try {
        await FORMS[R.key].apply(null, (R.args || []).concat([{ req: R.req, extra: R.extra }]));
        Object.keys(R.vals || {}).forEach(function (id) {
          var i = $(id); if (!i || i.hasAttribute('data-pin')) return;
          if (i.type === 'checkbox' || i.type === 'radio') i.checked = !!R.vals[id]; else i.value = R.vals[id];
          i.dispatchEvent(new Event('input', { bubbles: true }));
          if (i.tagName === 'SELECT') i.dispatchEvent(new Event('change', { bubbles: true }));   /* e.g. the payment's order: its balance */
        });
        if (OPEN_FORM) OPEN_FORM.dirty = true;
        toast('What you typed is back. Check it and save.');
      } catch (e) {}
    }
  }
  var FORMS = {};   /* key -> function(args…, {req}) that opens that form again */

  /* management data out of memory and off the screen (the unlock ended, Lock, another login) */
  var CACHE = {};
  function dropManagement() {
    CACHE = {}; FICHA = null; ORDER = null; RECV = null; DRAFT = null; FLAGS = { can_manage: false, can_pay: false, can_owner: false };
    clearTimeout(draftTimer);
    ['payModal', 'voidModal', 'invModal', 'fixModal'].forEach(function (id) { closeModal(id, true); });
    ['invRecs', 'fixLines', 'fixRcpt', 'payPo', 'payWho', 'voidWho'].forEach(function (id) { var e = $(id); if (e) e.innerHTML = ''; });
    /* the windows keep their boxes in the page: empty them too (the supplier's SINPE, balances, amounts, references) */
    ['payModal', 'voidModal', 'invModal', 'fixModal'].forEach(function (id) {
      var m = $(id); if (!m) return;
      m.querySelectorAll('input,textarea').forEach(function (i) { if (i.type === 'checkbox' || i.type === 'radio') i.checked = false; else i.value = ''; });
    });
    ['payIntro', 'paySaldo', 'payErr', 'voidIntro', 'voidErr', 'invPayout', 'invTotal', 'invErr', 'fixErr'].forEach(function (id) { var e = $(id); if (e) e.textContent = ''; });
    PAY = null; INV = null; VOID = null; FIX = null; AFTER_PAY = null; PENDING_NEW = null; DUP = null; UNMATCHED = {};
    $('printDoc').innerHTML = '';
    formClosed();
    if (MODE === 'manage') main.innerHTML = '';
  }

  /* not safe to reload (version.js) while something typed is unsaved or a call is on its way */
  function isDirty() {
    if (BUSY > 0) return true;
    if (liveForm() && OPEN_FORM.dirty) return true;
    if (DRAFT && DRAFT.dirty && !DRAFT.stopped) return true;
    if (RECV && RECV.touched) return true;
    return false;
  }
  window.HG_SAFE_TO_RELOAD = function () { return !isDirty(); };

  function showMainError(msg, retry, label) {
    main.innerHTML = '';
    var c = el('div', 'card'); var p = el('p', 'note bad'); p.textContent = msg; c.appendChild(p);
    if (retry) c.appendChild(btn(label || 'Try again', 'small', function () { retry(); }));
    main.appendChild(c);
  }

  /* ---------- 5) the routes (version.js keeps the hash on its reload) ---------- */
  var GEN = 0, SKIP_HASH = false, PREV_HASH = location.hash;
  function parseHash() {
    var q = {};
    String(location.hash || '').replace(/^#/, '').split('&').forEach(function (p) {
      if (!p) return;
      var i = p.indexOf('='), k = i < 0 ? p : p.slice(0, i), v = i < 0 ? '' : p.slice(i + 1);
      try { v = decodeURIComponent(v); } catch (e) {}
      q[k] = v;
    });
    return q;
  }
  window.addEventListener('hashchange', function () {
    if (SKIP_HASH) { SKIP_HASH = false; PREV_HASH = location.hash; return; }
    if (liveForm() && OPEN_FORM.dirty && !confirm('Leave without saving what you typed?')) {
      SKIP_HASH = true; location.hash = PREV_HASH || '#'; return;
    }
    PREV_HASH = location.hash;
    route();
  });
  function go(hash) { if (location.hash === hash) route(); else location.hash = hash; }
  async function route() {
    var gen = ++GEN;
    if (!MODE) return;
    formClosed();
    closeAllModals();
    var q = parseHash();
    /* a receive form left for another route: its typed values wait in localStorage (hg-prov-recv:<po>), so it no longer
       holds the page back from a reload (version.js) or the idle sign-out */
    if (RECV && (q.recibir || (MODE === 'receive' && q.pedido)) !== RECV.po) RECV = null;
    window.scrollTo(0, 0);
    if (MODE === 'receive') {
      if (!TURNO) { showPicker(); return; }
      if (q.recibir || q.pedido) return viewRecibir(gen, q.recibir || q.pedido);
      if (q.p && isUuid(q.p)) return viewReceiveVendor(gen, q.p);
      return viewReceiveHome(gen);
    }
    if (q.pedido) return viewPedido(gen, q.pedido);
    if (q.recibir) return viewRecibir(gen, q.recibir);
    if (q.alerta) return viewAlerta(gen, q.alerta);
    if ('nuevo' in q) return viewNuevo(gen);
    if (q.p && 'edit' in q) {
      /* from the list's «Editar»: the file, then its form open (the hash loses «edit», so a reload does not reopen it) */
      return viewFicha(gen, q.p, q.t, q.item).then(function () {
        if (stale(gen) || !FICHA || FICHA.vendor.id !== q.p || !$('fEditBtn') || $('vendorForm')) return;
        SKIP_HASH = true; location.replace('#p=' + encodeURIComponent(q.p) + (q.t ? '&t=' + encodeURIComponent(q.t) : '')); PREV_HASH = location.hash;
        editVendor(FICHA.vendor);
      });
    }
    if (q.p) return viewFicha(gen, q.p, q.t, q.item);
    return viewHub(gen);
  }
  function stale(gen) { return gen !== GEN; }
  function crumbs(parts) {
    var c = el('nav', 'crumbs'); c.setAttribute('aria-label', 'Where you are');
    parts.forEach(function (p, i) {
      if (i) c.appendChild(el('span', 'hint', '›'));
      if (p.href) { var a = document.createElement('a'); a.href = p.href; a.innerHTML = p.html || esc(p.text); c.appendChild(a); }
      else c.appendChild(el('span', '', p.html || esc(p.text)));
    });
    return c;
  }
  function loadErr(gen, r, retry) {
    if (stale(gen) || r.handled) return;
    showMainError(errText(r), retry || route);
  }

  /* modals: Escape and a tap on the backdrop close them; the focus goes back where it was */
  var lastFocus = null;
  function openModal(id, first) {
    lastFocus = document.activeElement;
    $(id).hidden = false;
    setTimeout(function () { var f = first ? $(first) : $(id).querySelector('input,select,button'); if (f) try { f.focus(); } catch (e) {} }, 30);
  }
  function closeModal(id, quiet) {
    var m = $(id); if (!m || m.hidden) return;
    m.hidden = true;
    m.querySelectorAll('input[data-pin]').forEach(function (i) { i.value = ''; });
    formClosed(m);
    if (!quiet && lastFocus && document.body.contains(lastFocus)) try { lastFocus.focus(); } catch (e) {}
  }
  function closeAllModals() { ['payModal', 'voidModal', 'invModal', 'fixModal'].forEach(function (id) { closeModal(id, true); }); }
  document.querySelectorAll('.modalbg').forEach(function (m) {
    m.addEventListener('click', function (e) { if (e.target === m && !(liveForm() && OPEN_FORM.dirty)) closeModal(m.id); });
  });
  document.addEventListener('keydown', function (e) {
    if (e.key !== 'Escape') return;
    var open = ['payModal', 'voidModal', 'invModal', 'fixModal'].filter(function (id) { return !$(id).hidden; })[0];
    if (open) { e.preventDefault(); closeModal(open); }
  });
  /* the staff who can authorize (owners and managers), for the payment PIN; owners only for a void */
  async function staffList() {
    if (CACHE.staff) return CACHE.staff;
    var r = await db.from('staff').select('id,name,role').eq('active', true).in('role', ['owner', 'manager']).order('name');
    CACHE.staff = (r && !r.error && r.data) || [];
    return CACHE.staff;
  }
  function fillWho(sel, list, ownersOnly) {
    sel.innerHTML = '';
    var rows = list.filter(function (s) { return !ownersOnly || s.role === 'owner'; });
    rows.forEach(function (s) { var o = document.createElement('option'); o.value = s.id; o.textContent = s.name + (s.role === 'owner' ? ' · Owner' : ' · Manager'); sel.appendChild(o); });
    if (!rows.length) { var o2 = document.createElement('option'); o2.value = ''; o2.textContent = ownersOnly ? 'No owner set up yet' : 'No owner or manager set up yet'; sel.appendChild(o2); }
    var who = HG_ACCESS.who();
    if (who && rows.some(function (s) { return s.id === who; })) sel.value = who;
  }

  /* ---------- 6) receive mode: who receives on this device («Recibe en este aparato», §5) ----------
     localStorage['hg-turnos'] = {"<login id>": {token, staff_id, name}}: one person per login on this device, checked
     with turno_estado (which may rotate the token). None: the POS's «¿Quién cobra?» (turno_desde_caja, silent), then
     «¿Quién recibe?»: tap a name, type one's own PIN (turno_aqui). */
  var TURNO = null, TURNO_WHY = null;
  function turnosAll() { var v = ls('hg-turnos'); return v && typeof v === 'object' ? v : {}; }
  function turnoSave(t) {
    var all = turnosAll();
    if (t) all[UID] = { token: t.token, staff_id: t.staff_id, name: t.name }; else delete all[UID];
    ls('hg-turnos', all);
  }
  /* «Salir de este aparato» while the POS's «¿Quién cobra?» is signed in on this device: that operator does not come
     back here on the next load (turno_desde_caja) until the POS has another operator sign-in or someone types a PIN
     here. localStorage['hg-turnos-out'] = {"<login id>": a fingerprint of that operator token (never the token)} */
  function opMark(tok) { var h = 2166136261; tok = String(tok || ''); for (var i = 0; i < tok.length; i++) { h ^= tok.charCodeAt(i); h = Math.imul(h, 16777619) >>> 0; } return h.toString(16); }
  function outAll() { var v = ls('hg-turnos-out'); return v && typeof v === 'object' ? v : {}; }
  function leftMark() { return outAll()[UID] || null; }
  function setLeft(tok) { var all = outAll(); if (tok) all[UID] = opMark(tok); else delete all[UID]; ls('hg-turnos-out', all); }
  function dropTurno(why) {
    TURNO = null; TURNO_WHY = why || null; turnoSave(null);
    if (MODE === 'receive') showPicker(WHY[why] || ERR.no_session);
  }
  /* -> true when this device knows who receives for this login */
  async function checkTurno(onlyRebind) {
    var mine = turnosAll()[UID];
    TURNO_WHY = null;
    if (mine && mine.token) {
      var r = await call('turno_estado', { p_tokens: [mine.token] });
      var s = r.ok && r.sessions && r.sessions[0];
      if (s && s.ok) {
        TURNO = { token: s.token || mine.token, staff_id: s.staff_id || mine.staff_id, name: s.staff_name || mine.name, expires_at: s.expires_at };
        turnoSave(TURNO);
        return true;
      }
      if (r.offline) { TURNO = { token: mine.token, staff_id: mine.staff_id, name: mine.name }; return true; }
      TURNO = null; turnoSave(null); TURNO_WHY = (s && s.why) || (r.ok ? 'unknown' : null);
      if (onlyRebind) { if (MODE === 'receive') showPicker(WHY[TURNO_WHY] || ERR.no_session); return false; }
    }
    if (onlyRebind) return false;
    var op = ls('hg-pos-operator');
    var out = leftMark();
    if (out && (!op || !op.token || opMark(op.token) !== out)) { setLeft(null); out = null; }   /* the POS signed someone else in since */
    if (op && op.token && !out) {
      var c = await call('turno_desde_caja', { p_operator_token: String(op.token), p_station: stationName() });
      if (c.ok && c.token) { TURNO = { token: c.token, staff_id: c.staff_id, name: c.staff_name || op.name }; turnoSave(TURNO); TURNO_WHY = null; return true; }
    }
    TURNO = null;
    return false;
  }
  function showTurnoBar() {
    var bar = $('modeBar'); bar.innerHTML = ''; bar.hidden = false;
    var who = el('span'); who.innerHTML = '<span>Receiving:</span> <b>' + nt(TURNO.name) + '</b>';
    bar.appendChild(who);
    bar.appendChild(btn('Not you? Change', 'linkbtn', function () { showPicker(); }));
    bar.appendChild(btn('Leave this device', 'linkbtn', async function () {
      var r = await call('turno_terminar', { p_token: TURNO.token });
      if (!r.ok && r.offline) { toast(ERR.offline); return; }
      var op = ls('hg-pos-operator');
      if (op && op.token) setLeft(op.token);
      TURNO = null; turnoSave(null); showPicker();
      toast(op && op.token && op.name ? 'Done: nobody receives on this device now. {n} is still ringing up at the POS.'.replace('{n}', function () { return String(op.name).slice(0, 40); }) : 'Done: nobody receives on this device now.');
    }));
    bar.appendChild(el('span', 'sp'));
    bar.appendChild(btn('Open the owner areas', 'ghost small', function () { openGate(); }));
    $('turnoView').hidden = true;
  }
  var PICK = null;
  async function showPicker(msg) {
    if (MODE !== 'receive') return;
    GEN++;
    RECV = null;   /* a typed receive form left this way waits in localStorage too: it never holds back a reload */
    main.innerHTML = '';
    $('modeBar').hidden = true;
    var v = $('turnoView'); v.hidden = false;
    $('turnoForm').hidden = true; $('tqPin').value = '';
    var m = $('turnoMsg'); m.textContent = msg || ''; m.hidden = !msg;
    $('turnoWho').innerHTML = '<p class="loading">Loading…</p>'; $('turnoWhoOff').innerHTML = ''; $('turnoOthers').hidden = true;
    var since = new Date(Date.now() - 16 * 3600000).toISOString();
    var rs = await Promise.all([db.from('staff').select('id,name,role').eq('active', true).order('name'),
                                db.from('time_entries').select('staff_id,clock_in').is('clock_out', null).gt('clock_in', since)]);
    if (MODE !== 'receive') return;
    if (rs[0].error || rs[1].error) { $('turnoWho').innerHTML = ''; var p = el('p', 'err'); p.textContent = offlineErr(rs[0]) || offlineErr(rs[1]) ? ERR.offline : ERR.server; $('turnoWho').appendChild(p); $('turnoWho').appendChild(btn('Try again', 'small', function () { showPicker(msg); })); return; }
    var on = {}; (rs[1].data || []).forEach(function (e) { on[e.staff_id] = true; });
    var staff = rs[0].data || [];
    var inShift = staff.filter(function (s) { return on[s.id]; }), off = staff.filter(function (s) { return !on[s.id]; });
    var w = $('turnoWho'); w.innerHTML = '';
    if (!inShift.length) w.appendChild(el('p', 'hint', esc('Nobody is clocked in right now.')));
    inShift.forEach(function (s) { w.appendChild(btn(s.name, '', function () { pickPerson(s, false); }, { 'data-staff': s.id, 'data-no-translate': '' })); });
    var wo = $('turnoWhoOff'); wo.innerHTML = '';
    off.forEach(function (s) { wo.appendChild(btn(s.name, '', function () { pickPerson(s, true); }, { 'data-staff': s.id, 'data-no-translate': '' })); });
    $('turnoOthers').hidden = !off.length;
    $('turnoOthers').open = !inShift.length && !!off.length;
  }
  function pickPerson(s, clockIn) {
    PICK = { id: s.id, name: s.name, clockIn: !!clockIn };
    document.querySelectorAll('#turnoView .who button').forEach(function (b) { b.setAttribute('aria-pressed', String(b.getAttribute('data-staff') === s.id)); });
    $('turnoName').textContent = s.name;
    $('turnoGo').textContent = clockIn ? 'Clock in and start' : 'I am on shift here';
    $('turnoErr').textContent = '';
    $('turnoForm').hidden = false;
    $('tqPin').value = '';
    $('tqPin').focus();
  }
  $('turnoBack').addEventListener('click', function () { PICK = null; $('turnoForm').hidden = true; $('tqPin').value = ''; document.querySelectorAll('#turnoView .who button').forEach(function (b) { b.setAttribute('aria-pressed', 'false'); }); });
  $('turnoOwner').addEventListener('click', function () { openGate(); });
  var turnoBusy = false;
  $('turnoForm').addEventListener('submit', async function (e) {
    e.preventDefault();
    if (!PICK || turnoBusy) return;
    var pin = $('tqPin').value.trim();
    if (!pin) { $('turnoErr').textContent = 'Type your PIN.'; $('tqPin').focus(); return; }
    turnoBusy = true; $('turnoGo').disabled = true;
    var r = await call('turno_aqui', { p_staff_id: PICK.id, p_pin: pin, p_station: stationName(), p_clock_in: PICK.clockIn });
    $('tqPin').value = ''; turnoBusy = false; $('turnoGo').disabled = false;
    if (r.ok && r.token) {
      TURNO = { token: r.token, staff_id: r.staff_id || PICK.id, name: r.staff_name || PICK.name, expires_at: r.expires_at };
      turnoSave(TURNO); PICK = null; setLeft(null);
      toast(r.clocked_in ? 'Clocked in. You can receive now.' : 'Ready: you receive on this device.');
      showTurnoBar(); route();
      return;
    }
    if (r.error === 'not_clocked_in') {
      PICK.clockIn = true; $('turnoGo').textContent = 'Clock in and start';
      $('turnoErr').textContent = 'You are not clocked in. Type your PIN again to clock in and start.';
      $('tqPin').focus(); return;
    }
    if (r.error === 'stale_shift') { $('turnoErr').textContent = r.clock_in ? 'You have a shift open since ' + fmtDT(r.clock_in) + '; tell a manager.' : ERR.stale_shift; return; }
    $('turnoErr').textContent = r.error === 'no_session' ? (WHY[r.why] || ERR.no_session) : errText(r);
    $('tqPin').focus();
  });

  /* receive mode: the orders to receive */
  async function viewReceiveHome(gen) {
    main.innerHTML = '<p class="loading">Loading…</p>';
    var r = await rpc('proveedores_por_recibir', { p_token: TURNO.token });
    if (stale(gen)) return;
    if (!r.ok) return loadErr(gen, r);
    main.innerHTML = '';
    var c = el('section', 'card'); c.appendChild(el('h2', '', esc('Orders to receive')));
    c.appendChild(el('p', 'hint', esc('Tap the order that arrived. Check what came, then confirm.')));
    c.appendChild(orderRows(r.orders || [], true));
    main.appendChild(c);
  }
  async function viewReceiveVendor(gen, vid) {
    main.innerHTML = '<p class="loading">Loading…</p>';
    var r = await rpc('proveedor_ficha', { p_vendor_id: vid, p_token: TURNO.token });
    if (stale(gen)) return;
    if (!r.ok) return loadErr(gen, r);
    main.innerHTML = '';
    main.appendChild(crumbs([{ href: '#', text: 'Orders to receive' }, { html: nt(r.vendor && r.vendor.name) }]));
    var c = el('section', 'card'); c.appendChild(el('h2', '', nt(r.vendor && r.vendor.name)));
    c.appendChild(orderRows(r.orders || [], true));
    main.appendChild(c);
  }
  /* the por_recibir shape as rows: Nº, supplier, sent, expected, lines pending; Receive (and Open for management) */
  function orderRows(orders, receiveOnly) {
    var box = el('div', 'olist');
    if (!orders.length) { box.appendChild(el('p', 'empty', esc('Nothing to receive right now.'))); return box; }
    orders.forEach(function (o) {
      var row = el('div', 'orow');
      row.appendChild(el('span', 't', esc('Order Nº ' + (o.po_number || '')) ));
      var d = el('span', 'd');
      d.innerHTML = (o.vendor_name ? nt(o.vendor_name) : '<span>No supplier</span>') +
        (o.sent_at ? ' · <span>' + esc('sent ' + fmtD(o.sent_at)) + '</span>' : '') +
        (o.expected_on ? ' · <span>' + esc('expected ' + fmtD(o.expected_on)) + '</span>' : '') +
        (o.lines != null ? ' · <span>' + esc((o.pending_lines != null ? o.pending_lines : o.lines) + ' of ' + o.lines + ' lines pending') + '</span>' : '');
      row.appendChild(d);
      var acts = el('span', 'acts');
      if (!o.vendor_name && !receiveOnly && FLAGS.can_manage) acts.appendChild(btn('No supplier · Assign', 'ghost small', function () { assignInline(row, o); }));
      /* receiving is the owner's, a manager's or the staff on shift's (never the accountant's) */
      if (receiveOnly || FLAGS.can_manage) acts.appendChild(link('Receive', '#recibir=' + o.id, 'btnlink small solid'));
      if (!receiveOnly) acts.appendChild(link('Open', '#pedido=' + o.id));
      row.appendChild(acts);
      box.appendChild(row);
    });
    return box;
  }
  /* an order without supplier (made by the old Inventory page) gets one */
  async function assignInline(row, o, after) {
    if (row.querySelector('.assign')) return;
    var box = el('div', 'assign inline'); box.style.flexBasis = '100%';
    var lab = el('label', 'f', esc('Supplier')); lab.htmlFor = 'asg-' + o.id;
    var sel = document.createElement('select'); sel.id = 'asg-' + o.id;
    var lista = await vendorsLista();
    (lista || []).filter(function (v) { return v.active; }).forEach(function (v) { var op = document.createElement('option'); op.value = v.id; op.textContent = v.name; sel.appendChild(op); });
    var err = el('p', 'err');
    var go = btn('Assign', 'small', async function () {
      if (!sel.value) return;
      go.disabled = true;
      var p = o.version != null ? o : await rpc('proveedor_pedido', { p_po_id: o.id });
      var ver = o.version != null ? o.version : (p.ok && p.order ? p.order.version : null);
      if (ver == null) { go.disabled = false; err.textContent = errText(p); return; }
      var r = await rpc('proveedor_pedido_asignar', { p_po_id: o.id, p_version: ver, p_vendor_id: sel.value });
      go.disabled = false;
      if (!r.ok) { if (!r.handled) err.textContent = errText(r); return; }
      toast('Supplier assigned'); CACHE = {}; if (after) after(); else route();
    });
    box.appendChild(lab); box.appendChild(sel); var b = el('div', 'btns'); b.appendChild(btn('Cancel', 'ghost small', function () { box.remove(); })); b.appendChild(go); box.appendChild(b); box.appendChild(err);
    row.appendChild(box); sel.focus();
  }
  async function vendorsLista(force) {
    if (CACHE.lista && !force) return CACHE.lista.vendors;
    var r = await rpc('proveedores_lista', { p_inactivos: true });
    if (r.ok) { CACHE.lista = r; setFlags(r); }
    return r.ok ? r.vendors || [] : null;
  }
  /* the rights an answer states (a missing one is kept: proveedor_pedido does not say can_owner) */
  function setFlags(r) {
    if (!r || r.mode !== 'manage') return;
    ['can_manage', 'can_pay', 'can_owner'].forEach(function (k) { if (k in r) FLAGS[k] = !!r[k]; });
  }

  /* ---------- 7) the hub (management) ---------- */
  var HUB = { chip: 'active', q: '', allAlerts: false };
  var STATUS_TXT = { out: 'Out of stock', low: 'Low stock', soon: 'Running out' };
  async function viewHub(gen) {
    if (!main.querySelector('#hubVendors')) main.innerHTML = '<p class="loading">Loading…</p>';
    var rs = await Promise.all([rpc('proveedores_lista', { p_inactivos: true }), rpc('proveedores_por_recibir', {})]);
    if (stale(gen)) return;
    var L = rs[0], P = rs[1];
    /* the alerts come with the list (proveedores_alertas()->'items'); a list without them asks for them */
    var A = L.ok && Array.isArray(L.alerts) ? { ok: true, items: L.alerts, count: L.alerts.length } : await rpc('proveedores_alertas', {});
    if (stale(gen)) return;
    if (!L.ok) return loadErr(gen, L);
    CACHE.lista = L; setFlags(L);
    if (A.ok) CACHE.alertas = A;
    main.innerHTML = '';
    /* alerts on top: the 6 most urgent (the server sends them out → low → soon, then by days left), grouped by supplier;
       the groups keep that order (the group of the most urgent alert first) */
    if (A.ok && (A.items || []).length) {
      var ac = el('section', 'card'); ac.id = 'hubAlerts';
      var h = el('h2', '', esc('Before it runs out') + ' <span class="n">' + esc(A.count != null ? A.count : A.items.length) + '</span>');
      ac.appendChild(h);
      var items = A.items, rank = Object.create(null);
      items.forEach(function (i, k) { var vk = i.vendor_name || ''; if (!(vk in rank)) rank[vk] = k; });
      var shown = (HUB.allAlerts ? items : items.slice(0, 6)).map(function (i, k) { return { i: i, k: k }; })
        .sort(function (a, b) { return rank[a.i.vendor_name || ''] - rank[b.i.vendor_name || ''] || a.k - b.k; }).map(function (x) { return x.i; });
      var grid = el('div', 'alerts'), lastV = null;
      shown.forEach(function (i) {
        var vk = i.vendor_name || '';
        if (vk !== lastV) { grid.appendChild(el('div', 'agroup', vk ? nt(vk) : esc('No supplier'))); lastV = vk; }
        var a = document.createElement('a'); a.className = 'acard ' + esc(i.status); a.href = '#alerta=' + encodeURIComponent(i.item_id);
        a.setAttribute('data-item', i.item_id);
        var onOrder = Number(i.on_order) > 0;
        a.innerHTML = '<div class="t">' + nt(i.name) + '</div><div class="d"><span>' + esc(STATUS_TXT[i.status] || i.status) + '</span>' +
          (i.vendor_name ? ' · ' + nt(i.vendor_name) : ' · <span>No supplier</span>') + '</div>' +
          (onOrder ? '<div class="o"><span>' + esc('Already ordered:') + '</span> ' + onOrderText(i) + '</div>' : '');
        grid.appendChild(a);
      });
      ac.appendChild(grid);
      if (items.length > 6) ac.appendChild(btn(HUB.allAlerts ? 'Show fewer' : 'See all (' + items.length + ')', 'linkbtn', function () { HUB.allAlerts = !HUB.allAlerts; viewHub(++GEN); }));
      main.appendChild(ac);
    }
    /* suppliers */
    var vc = el('section', 'card');
    var vh = el('h2', '', esc('Suppliers') + ' <span class="sp"></span>');
    if (FLAGS.can_manage) vh.appendChild(link('Add supplier', '#nuevo', 'btnlink small solid'));
    vc.appendChild(vh);
    var tools = el('div', 'tools');
    var s = document.createElement('input'); s.type = 'search'; s.id = 'hubSearch'; s.placeholder = 'Search a supplier'; s.setAttribute('aria-label', 'Search a supplier'); s.value = HUB.q;
    tools.appendChild(s);
    var chips = el('div', 'chips'); chips.setAttribute('role', 'group'); chips.setAttribute('aria-label', 'Show');
    [['active', 'Active ones'], ['inactive', 'Inactive ones'], ['receive', 'To receive']].forEach(function (c) {
      chips.appendChild(btn(c[1], 'chip', function () { HUB.chip = c[0]; chips.querySelectorAll('.chip').forEach(function (x) { x.setAttribute('aria-pressed', String(x === this)); }, this); paintVendors(); }, { 'aria-pressed': String(HUB.chip === c[0]), 'data-chip': c[0] }));
    });
    tools.appendChild(chips);
    vc.appendChild(tools);
    var grid2 = el('div', 'vgrid'); grid2.id = 'hubVendors'; vc.appendChild(grid2);
    main.appendChild(vc);
    s.addEventListener('input', function () { HUB.q = s.value; paintVendors(); });
    function paintVendors() {
      grid2.innerHTML = '';
      var q = norm(HUB.q.trim());
      var rows = (L.vendors || []).filter(function (v) {
        if (HUB.chip === 'inactive' ? v.active : !v.active) return false;
        if (HUB.chip === 'receive' && !(Number(v.to_receive) > 0)) return false;
        return !q || norm([v.name, v.contact_name, v.phone, v.whatsapp, v.email].join(' ')).indexOf(q) > -1;
      });
      if (!rows.length) grid2.appendChild(el('p', 'empty', esc(HUB.chip === 'inactive' ? 'No inactive suppliers.' : q ? 'No supplier with that name.' : HUB.chip === 'receive' ? 'Nothing to receive right now.' : 'No suppliers yet. Add the people you buy from.')));
      rows.forEach(function (v) { grid2.appendChild(vendorCard(v)); });
    }
    paintVendors();
    /* everything to receive, oldest first */
    var rc = el('section', 'card'); rc.id = 'hubReceive';
    rc.appendChild(el('h2', '', esc('To receive')));
    if (P.ok) rc.appendChild(orderRows(P.orders || [], false)); else rc.appendChild(el('p', 'err', esc(errText(P))));
    main.appendChild(rc);
  }
  /* «2 × caja de 6 (Nº 41)»: html, the units in their own span for lang.js */
  function onOrderText(i) {
    var nums = (i.on_order_po_numbers || []).map(function (n) { return 'Nº ' + n; }).join(', ');
    var q = Number(i.pack_qty) > 0 ? esc(num(Number(i.on_order) / Number(i.pack_qty), 2)) + ' × ' + (i.pack_label ? nt(i.pack_label) : '<span>' + esc(qtyU(i.pack_qty, i.unit)) + '</span>') : '<span>' + esc(qtyU(i.on_order, i.unit)) + '</span>';
    return q + (nums ? ' ' + esc('(' + nums + ')') : '');
  }
  /* «Pago sin aplicar de hace 45 días»: the oldest unapplied advance older than 30 days (a count, a list or an age) */
  function staleDays(sa) {
    if (sa == null || sa === false) return 0;
    if (Array.isArray(sa)) return sa.reduce(function (m, a) { return Math.max(m, a && a.days != null ? Number(a.days) : daysAgo(a && (a.date || a.created_at))); }, 0) || (sa.length ? 31 : 0);
    if (typeof sa === 'object') return Number(sa.days) || daysAgo(sa.oldest || sa.date) || (Number(sa.count) > 0 ? 31 : 0);
    return Number(sa) > 0 ? -1 : 0;   /* only a count: older than 30 days */
  }
  function vendorCard(v) {
    var a = document.createElement('a'); a.className = 'vcard'; a.href = '#p=' + encodeURIComponent(v.id); a.setAttribute('data-vendor', v.id);
    var b = [];
    if (Number(v.to_receive) > 0) b.push('<span class="pill sent">' + esc(v.to_receive + ' to receive') + '</span>');
    if (Number(v.partial) > 0) b.push('<span class="pill partially_received">' + esc('Partially received: ' + v.partial) + '</span>');
    if (Number(v.drafts) > 0) b.push('<span class="pill draft">' + esc('Draft') + '</span>');
    if (Number(v.owed_crc) > 0.5) b.push('<span class="pill pay-pending">' + esc('Owed ' + fmt(v.owed_crc)) + '</span>');
    if (Number(v.credit_crc) > 0.5) b.push('<span class="pill pay-paid">' + esc('In favour ' + fmt(v.credit_crc)) + '</span>');
    var sd = staleDays(v.stale_advances);
    if (sd) b.push('<span class="pill gold">' + esc(sd > 0 ? 'Unapplied payment for ' + sd + ' days now' : 'Unapplied payment older than 30 days') + '</span>');
    if (!v.active) b.push('<span class="pill mute">' + esc('inactive') + '</span>');
    var contact = [v.contact_name, v.phone || v.whatsapp].filter(Boolean);
    a.innerHTML = '<span class="t" id="vn-' + esc(v.id) + '">' + nt(v.name) + '</span>' + (contact.length ? '<span class="d">' + contact.map(nt).join(' · ') + '</span>' : '') +
      (v.last_order_at ? '<span class="d">' + esc('Last order ' + fmtD(v.last_order_at)) + '</span>' : '') +
      (b.length ? '<span class="badges">' + b.join('') + '</span>' : '');
    if (!(FLAGS.can_manage || FLAGS.can_owner || isBooksDoor())) return a;
    /* «Editar» from the list (request §2): it opens the file with its «Editar proveedor» form, where «Desactivar» is */
    var w = el('div', 'vwrap'); w.appendChild(a);
    var e = document.createElement('a'); e.className = 'btnlink small vedit'; e.href = '#p=' + encodeURIComponent(v.id) + '&edit=1'; e.textContent = 'Edit';
    e.setAttribute('aria-describedby', 'vn-' + v.id);   /* «Editar» … which one: the card's name (no 'Edit {x}' pattern in lang.js) */
    w.appendChild(e);
    return w;
  }

  /* ---------- 8) «Asociar proveedor»: an alert whose item has no active preferred supplier ---------- */
  async function alertItem(itemId) {
    var A = CACHE.alertas;
    if (!A) { A = await rpc('proveedores_alertas', {}); if (A.ok) CACHE.alertas = A; }
    return A && A.ok ? (A.items || []).filter(function (i) { return i.item_id === itemId; })[0] || null : null;
  }
  async function viewAlerta(gen, itemId) {
    if (!isUuid(itemId)) { go('#'); return; }
    main.innerHTML = '<p class="loading">Loading…</p>';
    var it = await alertItem(itemId);
    if (stale(gen)) return;
    var vendors = await vendorsLista();
    if (stale(gen)) return;
    if (vendors === null) return loadErr(gen, { error: 'offline', offline: true });
    var vid = it ? it.vendor_id : null, name = it ? it.name : null, unit = it ? it.unit : null;
    if (!it) {   /* no longer low: the item's preferred supplier still decides */
      var sr = await db.from('stock_items').select('id,name,unit,vendor_id').eq('id', itemId).maybeSingle();
      if (stale(gen)) return;
      if (sr && sr.data) { vid = sr.data.vendor_id; name = sr.data.name; unit = sr.data.unit; }
    }
    var pv = vid ? vendors.filter(function (v) { return v.id === vid; })[0] : null;
    if (pv && pv.active) { SKIP_HASH = true; location.replace('#p=' + encodeURIComponent(vid) + '&item=' + encodeURIComponent(itemId)); PREV_HASH = location.hash; return viewFicha(gen, vid, 'pedir', itemId); }
    /* which suppliers already have it in their catalog: the alert says so (proveedores_alertas' suppliers, the smallest
       live presentation of each); no read per supplier. An item that is no longer an alert lists every active supplier. */
    var act = vendors.filter(function (v) { return v.active; });
    var has = [];
    ((it && it.suppliers) || []).forEach(function (s) {
      var v = act.filter(function (x) { return x.id === s.vendor_id; })[0];
      if (v && isUuid(s.vendor_item_id) && !has.some(function (x) { return x.v.id === v.id; }))
        has.push({ v: v, row: { id: s.vendor_item_id, pack_label: s.pack_label, pack_qty: s.pack_qty, unit: unit, usual_price: s.usual_price } });
    });
    main.innerHTML = '';
    main.appendChild(crumbs([{ href: '#', text: 'Suppliers' }, { text: 'Link a supplier' }]));
    var c = el('section', 'card');
    c.appendChild(el('h2', '', '<span>' + esc('Link a supplier') + '</span> · ' + nt(name || '')));
    c.appendChild(el('p', 'hint', esc(pv ? 'Its preferred supplier is inactive. Pick who you buy it from now.' : 'This item has no preferred supplier yet. Pick who you buy it from: the alert then opens that supplier.')));
    var list = el('div', 'olist');
    var pick = function (v, row) {
      return async function () {
        if (row) {
          var r = await rpc('proveedor_producto_guardar', { p_item: { id: row.id, preferred: true } });
          if (!r.ok) { if (!r.handled) toast(errText(r)); return; }
          CACHE = {}; toast('Preferred supplier saved');
          go('#p=' + encodeURIComponent(v.id) + '&item=' + encodeURIComponent(itemId));
        } else {
          PENDING_NEW = { vendor: v.id, item_id: itemId, name: name, unit: unit, preferred: true };
          go('#p=' + encodeURIComponent(v.id) + '&t=productos&item=' + encodeURIComponent(itemId));
        }
      };
    };
    if (has.length) {
      list.appendChild(el('p', 'agroup', esc('They have it in their catalog')));
      has.forEach(function (x) {
        var r = el('div', 'orow'); r.innerHTML = '<span class="t">' + nt(x.v.name) + '</span><span class="d">' + presHtml(x.row) + (x.row.usual_price != null ? ' · ' + esc(fmtC(x.row.usual_price)) : '') + '</span>';
        var a = el('span', 'acts'); a.appendChild(btn('Make preferred', 'small', pick(x.v, x.row))); r.appendChild(a); list.appendChild(r);
      });
    }
    var others = act.filter(function (v) { return !has.some(function (x) { return x.v.id === v.id; }); });
    if (others.length) {
      list.appendChild(el('p', 'agroup', esc(has.length ? 'Other suppliers' : 'Suppliers')));
      others.forEach(function (v) {
        var r = el('div', 'orow'); r.innerHTML = '<span class="t">' + nt(v.name) + '</span><span class="d">' + esc('Add it to this catalog') + '</span>';
        var a = el('span', 'acts'); a.appendChild(btn('Choose', 'ghost small', pick(v, null))); r.appendChild(a); list.appendChild(r);
      });
    }
    if (!act.length) list.appendChild(el('p', 'empty', esc('No suppliers yet. Add the people you buy from.')));
    c.appendChild(list);
    main.appendChild(c);
  }
  var PENDING_NEW = null;   /* a new catalog row to prefill when a supplier's Products open (from «Asociar proveedor» or «Añadir al catálogo») */

  /* ---------- 9) the supplier file (management): header, «Editar», tabs Pedir | Pedidos | Pagos | Productos ---------- */
  var FICHA = null;
  async function loadFicha(vid, force) {
    var c = CACHE['f:' + vid];
    if (c && !force && Date.now() - c.at < 60000) return c.r;
    var r = await rpc('proveedor_ficha', { p_vendor_id: vid });
    if (r.ok) { CACHE['f:' + vid] = { at: Date.now(), r: r }; setFlags(r); }
    return r;
  }
  function forgetFicha(vid) { delete CACHE['f:' + vid]; delete CACHE.lista; }
  var TABS = [['pedir', 'Place an order'], ['pedidos', 'Orders'], ['pagos', 'Payments'], ['productos', 'Products']];
  async function viewFicha(gen, vid, tab, itemId, force) {
    if (!isUuid(vid)) { go('#'); return; }
    if (!FICHA || FICHA.vendor.id !== vid) main.innerHTML = '<p class="loading">Loading…</p>';
    /* money and deliveries are read as they are now (another device may have received or paid a moment ago); the
       60-second copy only serves Pedir and Productos (the books door opens on Pagos) */
    var fresh = force || tab === 'pagos' || tab === 'pedidos' || (!tab && isBooksDoor() && !FLAGS.can_manage);
    var r = await loadFicha(vid, fresh);
    if (stale(gen)) return;
    if (!r.ok) return loadErr(gen, r);
    FICHA = r; setFlags(r);
    var V = r.vendor || {};
    if (!FLAGS.can_manage && (!tab || tab === 'pedir')) tab = 'pagos';
    tab = TABS.some(function (t) { return t[0] === tab; }) ? tab : 'pedir';
    main.innerHTML = '';
    main.appendChild(crumbs([{ href: '#', text: 'Suppliers' }, { html: nt(V.name) }]));
    var card = el('section', 'card'); card.id = 'ficha'; card.setAttribute('data-vendor', V.id);
    var head = el('div', 'fhead');
    var info = el('div', 'info');
    var links = [];
    if (V.phone) links.push('<a href="tel:' + esc(String(V.phone).replace(/[^0-9+]/g, '')) + '">' + nt(V.phone) + '</a>');
    if (V.whatsapp) links.push('<a href="https://wa.me/' + esc(String(V.whatsapp).replace(/[^0-9]/g, '')) + '" target="_blank" rel="noopener">WhatsApp ' + nt(V.whatsapp) + '</a>');
    if (V.email) links.push('<a href="mailto:' + esc(V.email) + '">' + nt(V.email) + '</a>');
    var sinpeRecent = V.sinpe_changed_at && daysAgo(V.sinpe_changed_at) <= 30;
    info.innerHTML = '<h2>' + nt(V.name) + (V.active === false ? ' <span class="pill mute">' + esc('inactive') + '</span>' : '') + '</h2>' +
      (V.contact_name ? '<div>' + nt(V.contact_name) + '</div>' : '') + (links.length ? '<div>' + links.join('') + '</div>' : '') +
      (V.sinpe ? '<div><span>SINPE:</span> <b class="mono">' + nt(V.sinpe) + '</b></div>' : '') +
      (sinpeRecent ? '<div class="note" style="margin:.3rem 0">' + esc('SINPE changed on ' + fmtD(V.sinpe_changed_at)) + (V.sinpe_changed_by ? ' · <span>' + esc('by') + '</span> ' + nt(V.sinpe_changed_by) : '') + '</div>' : '') +
      (V.payment_notes ? '<div><span>' + esc('How we pay (Accounting):') + '</span> ' + nt(V.payment_notes) + '</div>' : '') +
      (V.notes ? '<div>' + nt(V.notes) + '</div>' : '') +
      '<div>' + [V.order_days ? esc('Takes orders on') + ' ' + nt(V.order_days) : '', V.lead_days != null ? esc(Number(V.lead_days) === 1 ? '1 day to deliver' : V.lead_days + ' days to deliver') : '', V.credit_days != null ? esc(Number(V.credit_days) === 1 ? '1 day of credit' : V.credit_days + ' days of credit') : ''].filter(Boolean).join(' · ') + '</div>';
    head.appendChild(info);
    if (FLAGS.can_manage || FLAGS.can_owner || isBooksDoor()) head.appendChild(btn('Edit', 'ghost small', function () { editVendor(V); }, { id: 'fEditBtn' }));
    card.appendChild(head);
    var editBox = el('div'); editBox.id = 'fEdit'; card.appendChild(editBox);
    var nav = el('nav', 'ftabs'); nav.setAttribute('aria-label', 'Supplier file');
    TABS.forEach(function (t) {
      if (t[0] === 'pedir' && !FLAGS.can_manage) return;
      var a = document.createElement('a'); a.href = '#p=' + encodeURIComponent(V.id) + '&t=' + t[0]; a.textContent = t[1];
      if (t[0] === tab) a.setAttribute('aria-current', 'page');
      if (t[0] === 'pedidos') { var open = (r.orders || []).filter(function (o) { return /^(draft|sent|partially_received)$/.test(o.status); }).length; if (open) a.appendChild(el('span', 'n', esc(open))).style.marginLeft = '.4em'; }
      nav.appendChild(a);
    });
    card.appendChild(nav);
    var body = el('div'); body.id = 'fTab'; card.appendChild(body);
    main.appendChild(card);
    if (tab === 'pedir') renderPedir(body, r, itemId);
    else if (tab === 'pedidos') renderPedidos(body, r);
    else if (tab === 'pagos') renderPagos(body, r);
    else renderProductos(body, r, itemId);
  }
  function reloadFicha(keepTab) { if (!FICHA) return route(); var q = parseHash(); forgetFicha(FICHA.vendor.id); return viewFicha(++GEN, FICHA.vendor.id, keepTab || q.t, q.item, true); }

  /* «Editar proveedor», inline (SINPE only for the owner level or the books door; the accountant edits SINPE only) */
  FORMS.vendor = async function (vid, opts) {
    if (!FICHA || FICHA.vendor.id !== vid) { var r = await loadFicha(vid, true); if (!r.ok) return; FICHA = r; }
    editVendor(FICHA.vendor, opts);
  };
  function editVendor(V, opts) {
    var box = $('fEdit'); if (!box) return;
    if (box.firstChild) { box.innerHTML = ''; formClosed(); return; }
    var full = FLAGS.can_manage, sinpeOk = FLAGS.can_owner || isBooksDoor();
    /* under a PIN unlock the server asks an owner's PIN in the call itself to change the SINPE (never for the owner
       with the phone code or the accountant): the box shows once the SINPE typed differs from the saved one */
    var sinpePin = sinpeOk && !noPinNeeded();
    var f = el('form', 'inline form'); f.id = 'vendorForm'; f.setAttribute('autocomplete', 'off');
    var inp = function (id, label, val, max, type) { return '<div><label class="f" for="' + id + '">' + esc(label) + '</label><input id="' + id + '"' + (type ? ' type="' + type + '"' : '') + ' maxlength="' + max + '" value="' + esc(val == null ? '' : val) + '"></div>'; };
    f.innerHTML = '<h3 style="margin-top:0">' + esc('Edit supplier') + '</h3>' +
      (full ? inp('vfName', 'Name', V.name, 80) + '<div class="row">' + inp('vfContact', 'Contact person', V.contact_name, 80) + inp('vfPhone', 'Phone', V.phone, 40, 'tel') + '</div>' +
        '<div class="row">' + inp('vfWa', 'WhatsApp (with country code)', V.whatsapp, 40, 'tel') + inp('vfEmail', 'Email', V.email, 120, 'email') + '</div>' : '') +
      (sinpeOk ? inp('vfSinpe', 'SINPE (number and name for transfers)', V.sinpe, 120) +
        (sinpePin ? '<div id="vfPinBox" hidden><p class="hint">' + esc('Changing how this supplier is paid needs an owner\'s PIN.') + '</p><div class="row">' +
          '<div><label class="f" for="vfWho">' + esc('Owner') + '</label><select id="vfWho"></select></div>' +
          '<div><label class="f" for="vfPin">' + esc('Owner PIN') + '</label><input id="vfPin" type="text" data-pin inputmode="numeric" maxlength="8" autocomplete="off" data-1p-ignore data-lpignore="true" data-bwignore data-form-type="other"></div></div></div>' : '')
        : (V.sinpe ? '<p class="hint">' + esc('Only the owner or the accountant changes the SINPE.') + '</p>' : '')) +
      (full ? '<label class="f" for="vfNotes">' + esc('Notes') + '</label><textarea id="vfNotes" maxlength="500">' + esc(V.notes || '') + '</textarea>' +
        '<details><summary class="linkbtn">' + esc('More') + '</summary><div class="row">' + inp('vfDays', 'Takes orders on', V.order_days, 60) + inp('vfLead', 'Days to deliver', V.lead_days, 3, 'number') + '</div>' +
        '<div class="row">' + inp('vfCredit', 'Credit days (empty = 30)', V.credit_days, 3, 'number') + '<div></div></div></details>' : '') +
      '<p class="err" id="vfErr" role="alert"></p><div class="btns">' + '</div>';
    var btns = f.querySelector('.btns');
    if (full) btns.appendChild(btn(V.active === false ? 'Activate' : 'Deactivate', 'ghost small left' + (V.active === false ? '' : ' danger'), async function () {
      if (V.active !== false && !confirm('Deactivate ' + V.name + '? Its history stays.')) return;
      var r = await rpc('proveedor_guardar', { p_vendor: { id: V.id, active: V.active === false } });
      if (!r.ok) { if (!r.handled) $('vfErr').textContent = errText(r); return; }
      formClosed(f);
      toast(V.active === false ? 'Supplier activated' : (Number(r.open_orders) > 0 ? 'Supplier deactivated · ' + r.open_orders + ' open orders stay' : 'Supplier deactivated'));
      reloadFicha();
    }));
    btns.appendChild(btn('Cancel', 'ghost', function () { box.innerHTML = ''; formClosed(f); }));
    var save = btn('Save', '', null); save.type = 'submit'; btns.appendChild(save);
    box.appendChild(f);
    formOpened('vendor', [V.id], f);
    var first = f.querySelector('input'); if (first) first.focus();
    var sinpeIn = $('vfSinpe'), pinBox = $('vfPinBox'), whoFilled = false;
    function sinpeChanged() { return !!sinpeIn && sinpeIn.value.trim() !== (V.sinpe || ''); }
    if (sinpeIn && pinBox) sinpeIn.addEventListener('input', function () {
      pinBox.hidden = !sinpeChanged();
      if (!pinBox.hidden && !whoFilled) { whoFilled = true; staffList().then(function (l) { fillWho($('vfWho'), l, true); }); }
    });
    f.addEventListener('submit', async function (e) {
      e.preventDefault();
      var p = { id: V.id }, val = function (id) { var i = $(id); return i ? i.value.trim() : undefined; };
      var map = [['vfName', 'name'], ['vfContact', 'contact_name'], ['vfPhone', 'phone'], ['vfWa', 'whatsapp'], ['vfEmail', 'email'], ['vfNotes', 'notes'], ['vfDays', 'order_days'], ['vfSinpe', 'sinpe']];
      map.forEach(function (m) { var v = val(m[0]); if (v !== undefined && v !== (V[m[1]] || '')) p[m[1]] = v || null; });
      if ($('vfLead') && val('vfLead') !== String(V.lead_days == null ? '' : V.lead_days)) { var ld = parseNum(val('vfLead')); if (!(ld >= 0 && ld <= 60 && ld === Math.floor(ld))) { $('vfErr').textContent = 'Days to deliver: a whole number from 0 to 60.'; return; } p.lead_days = ld; }
      if ($('vfCredit') && val('vfCredit') !== String(V.credit_days == null ? '' : V.credit_days)) { var cd = val('vfCredit') === '' ? null : parseNum(val('vfCredit')); if (cd !== null && !(cd >= 0 && cd <= 180 && cd === Math.floor(cd))) { $('vfErr').textContent = 'Credit days: a whole number from 0 to 180, or empty.'; return; } p.credit_days = cd; }
      if ('name' in p && !p.name) { $('vfErr').textContent = 'The name cannot be empty.'; return; }
      if (Object.keys(p).length === 1) { box.innerHTML = ''; formClosed(f); return; }
      var args = { p_vendor: p };
      if ('sinpe' in p && pinBox) {
        var pin = $('vfPin').value.trim();
        if (!$('vfWho').value || !pin) { pinBox.hidden = false; $('vfErr').textContent = 'Pick the owner and type the PIN.'; (pin ? $('vfWho') : $('vfPin')).focus(); return; }
        args.p_staff_id = $('vfWho').value; args.p_pin = pin;
      }
      save.disabled = true;
      var r = await rpc('proveedor_guardar', args);
      if ($('vfPin')) $('vfPin').value = '';
      save.disabled = false;
      if (!r.ok) { if (!r.handled) $('vfErr').textContent = errText(r); return; }
      formClosed(f); toast('Supplier saved'); reloadFicha();
    });
  }
  /* «Añadir proveedor» (#nuevo): the request id is the new supplier's id; a repeat answers repeat:true */
  FORMS.nuevo = async function (opts) { NEW_REQ = (opts && opts.req) || NEW_REQ; };
  var NEW_REQ = null;
  async function viewNuevo(gen) {
    if (!CACHE.lista) await vendorsLista();
    if (stale(gen)) return;
    if (!FLAGS.can_manage) { showMainError(ERR.needs_owner); return; }
    NEW_REQ = NEW_REQ || uuid();
    main.innerHTML = '';
    main.appendChild(crumbs([{ href: '#', text: 'Suppliers' }, { text: 'Add supplier' }]));
    var c = el('section', 'card');
    var f = el('form', 'form'); f.id = 'newVendorForm'; f.setAttribute('autocomplete', 'off');
    f.innerHTML = '<h2>' + esc('Add supplier') + '</h2>' +
      '<label class="f" for="nvName">' + esc('Name') + '</label><input id="nvName" maxlength="80" required>' +
      '<div class="row"><div><label class="f" for="nvContact">' + esc('Contact person') + '</label><input id="nvContact" maxlength="80"></div><div><label class="f" for="nvPhone">' + esc('Phone') + '</label><input id="nvPhone" type="tel" maxlength="40"></div></div>' +
      '<div class="row"><div><label class="f" for="nvWa">' + esc('WhatsApp (with country code)') + '</label><input id="nvWa" type="tel" maxlength="40" placeholder="+506 8888 8888"></div><div><label class="f" for="nvEmail">' + esc('Email') + '</label><input id="nvEmail" type="email" maxlength="120"></div></div>' +
      '<div class="row"><div><label class="f" for="nvDays">' + esc('Takes orders on') + '</label><input id="nvDays" maxlength="60" placeholder="e.g. Mon, Thu"></div><div><label class="f" for="nvLead">' + esc('Days to deliver') + '</label><input id="nvLead" type="number" min="0" max="60" step="1" value="2"></div></div>' +
      '<label class="f" for="nvNotes">' + esc('Notes') + '</label><textarea id="nvNotes" maxlength="500"></textarea>' +
      '<p class="err" id="nvErr" role="alert"></p><div class="btns"><a class="btnlink" href="#">' + esc('Cancel') + '</a><button type="submit" id="nvGo">' + esc('Save supplier') + '</button></div>';
    c.appendChild(f); main.appendChild(c);
    formOpened('nuevo', [], f, NEW_REQ);
    $('nvName').focus();
    f.addEventListener('submit', async function (e) {
      e.preventDefault();
      var name = $('nvName').value.trim();
      if (!name) { $('nvErr').textContent = 'The name cannot be empty.'; return; }
      var lead = parseNum($('nvLead').value || '0');
      if (!(lead >= 0 && lead <= 60)) { $('nvErr').textContent = 'Days to deliver: a whole number from 0 to 60.'; return; }
      var p = { id: NEW_REQ, name: name, contact_name: $('nvContact').value.trim() || null, phone: $('nvPhone').value.trim() || null, whatsapp: $('nvWa').value.trim() || null,
        email: $('nvEmail').value.trim() || null, order_days: $('nvDays').value.trim() || null, lead_days: Math.floor(lead), notes: $('nvNotes').value.trim() || null };
      $('nvGo').disabled = true;
      var r = await rpc('proveedor_guardar', { p_vendor: p });
      $('nvGo').disabled = false;
      if (!r.ok) {
        if (r.handled) return;
        $('nvErr').textContent = errText(r);
        if (r.error === 'duplicate_name' && r.id) { var a = document.createElement('a'); a.href = '#p=' + encodeURIComponent(r.id); a.textContent = 'Open that supplier'; a.className = 'btnlink small'; $('nvErr').appendChild(document.createTextNode(' ')); $('nvErr').appendChild(a); }
        return;
      }
      var id = r.id || NEW_REQ; NEW_REQ = null; formClosed(f); delete CACHE.lista;
      toast(name + ' saved');
      SKIP_HASH = false; go('#p=' + encodeURIComponent(id) + '&t=productos');
    });
  }

  /* ---------- 10) «Pedir»: tick, quantity, untick, live total; the draft saves itself ----------
     local: localStorage['hg-prov-draft:<vendor>'] = {base_version, lines:[{vendor_item_id, packs, pack_price?}], note, dirty, req}
     server: proveedor_borrador_guardar 1.2 s after the last change and on pagehide; the server keeps [{vendor_item_id, packs}] */
  var DRAFT = null, draftTimer = null, PIN = null, UNMATCHED = {};
  function dkey(vid) { return 'hg-prov-draft:' + vid; }
  function draftSaveLocal() { if (!DRAFT) return; ls(dkey(DRAFT.vendor), { base_version: DRAFT.base_version, lines: DRAFT.lines, note: DRAFT.note, dirty: DRAFT.dirty, req: DRAFT.req || null }); }
  function cleanLines(lines) {
    var seen = {};
    return (Array.isArray(lines) ? lines : []).filter(function (l) {
      if (!l || !isUuid(l.vendor_item_id) || !(Number(l.packs) > 0) || seen[l.vendor_item_id]) return false;
      seen[l.vendor_item_id] = 1; return true;
    }).map(function (l) { var o = { vendor_item_id: l.vendor_item_id, packs: round(l.packs, 3) }; if (l.pack_price != null && isFinite(Number(l.pack_price))) o.pack_price = round(l.pack_price, 2); return o; });
  }
  /* the open rules: local dirty on the same version wins; a newer server draft wins (and says local changes were left) */
  function draftOpen(vid, server) {
    var loc = ls(dkey(vid)), sv = server ? Number(server.version) || 0 : 0;
    var d = { vendor: vid, base_version: sv, lines: cleanLines(server && server.lines), note: (server && server.note) || '', dirty: false, edits: 0,
              updated_at: server && server.updated_at, updated_by: server && server.updated_by, stopped: false, req: null, leftover: null, conflict: null };
    if (loc && typeof loc === 'object') {
      d.req = isUuid(loc.req) ? loc.req : null;
      var lines = cleanLines(loc.lines);
      if (loc.dirty && Number(loc.base_version || 0) === sv) { d.lines = lines; d.note = String(loc.note || '').slice(0, 500); d.dirty = true; }
      else if (loc.dirty && (lines.length || loc.note) && !sameDraft(server, { lines: lines, note: loc.note })) d.leftover = { lines: lines, note: String(loc.note || '').slice(0, 500) };
      else { /* a priced line typed on this device keeps its price on the server's lines */
        lines.forEach(function (l) { if (l.pack_price != null) d.lines.forEach(function (x) { if (x.vendor_item_id === l.vendor_item_id) x.pack_price = l.pack_price; }); });
      }
    }
    DRAFT = d; draftSaveLocal();
    if (d.dirty) draftSchedule();
    return d;
  }
  function dline(vi) { return DRAFT ? DRAFT.lines.filter(function (l) { return l.vendor_item_id === vi; })[0] || null : null; }
  function draftSet(vi, packs, price) {
    if (!DRAFT) return;
    var l = dline(vi);
    if (packs == null) { DRAFT.lines = DRAFT.lines.filter(function (x) { return x.vendor_item_id !== vi; }); }
    else if (l) { l.packs = round(packs, 3); if (price !== undefined) { if (price == null) delete l.pack_price; else l.pack_price = price; } }
    else { var n = { vendor_item_id: vi, packs: round(packs, 3) }; if (price != null) n.pack_price = price; DRAFT.lines.push(n); }
    draftTouched();
  }
  function draftTouched() { DRAFT.dirty = true; DRAFT.edits++; draftSaveLocal(); draftSchedule(); paintBar(); }
  function draftSchedule() { if (!DRAFT || DRAFT.stopped) return; clearTimeout(draftTimer); draftStatus('Saving…'); draftTimer = setTimeout(draftPush, 1200); }
  function draftStatus(t, cls) { var s = $('pStatus'); if (s) { s.textContent = t || ''; s.className = 'dstatus' + (cls ? ' ' + cls : ''); } }
  /* the server keeps [{vendor_item_id, packs}] of live catalog rows (a product retired meanwhile stays only on this device) */
  function serverLines() {
    var known = FICHA && DRAFT && FICHA.vendor.id === DRAFT.vendor ? liveProducts().map(function (p) { return p.id; }) : null;
    return DRAFT.lines.filter(function (l) { return !known || known.indexOf(l.vendor_item_id) > -1; }).map(function (l) { return { vendor_item_id: l.vendor_item_id, packs: l.packs }; });
  }
  var draftFlight = null;
  async function draftPush() {
    clearTimeout(draftTimer);
    var D = DRAFT;
    if (!D || D.stopped || !D.dirty) return;
    if (draftFlight) { D.again = true; return draftFlight; }
    if (!D.lines.length && !D.note && !D.base_version) { D.dirty = false; draftSaveLocal(); draftStatus(''); return; }
    var edits = D.edits, sent = { lines: serverLines(), note: D.note || null };
    draftFlight = rpc('proveedor_borrador_guardar', { p_vendor_id: D.vendor, p_lines: sent.lines, p_note: sent.note, p_version: D.base_version });
    var r = await draftFlight; draftFlight = null;
    if (DRAFT !== D) return;
    if (r.ok) {
      D.unanswered = null;
      D.base_version = r.discarded ? 0 : Number(r.version) || D.base_version;
      D.updated_at = r.updated_at || new Date().toISOString();
      if (D.edits === edits) D.dirty = false;
      draftSaveLocal();
      draftStatus(r.discarded ? '' : 'Draft saved ' + hhmm(D.updated_at));
      if (D.dirty || D.again) { D.again = false; draftSchedule(); }
      return;
    }
    if (r.offline) {
      /* it may have reached the server: what it sent is kept, so its version is recognised on the next answer */
      D.unanswered = (D.unanswered || []).concat([{ key: draftKey(sent.lines, sent.note), base: D.base_version }]).slice(-5);
      draftStatus('No connection: saved on this device', 'err'); clearTimeout(draftTimer); draftTimer = setTimeout(draftPush, 15000); return;
    }
    if (r.handled) return;
    /* «changed» with exactly what this device sent: its own earlier save got there (a lost answer, or the save made as
       the page went to the background), not another device: take that version and go on */
    if (r.error === 'changed' && r.draft && sameDraft(r.draft, sent)) {
      D.unanswered = null;
      D.base_version = Number(r.draft.version) || D.base_version; D.updated_at = r.draft.updated_at || D.updated_at;
      if (D.edits === edits) D.dirty = false;
      draftSaveLocal(); draftStatus('Draft saved ' + hhmm(D.updated_at));
      if (D.dirty || D.again) { D.again = false; draftSchedule(); }
      return;
    }
    /* «changed» with what an earlier save of this device sent, one version on: that save got there (its answer was lost)
       and the person changed more since; take that version and send what is ticked now */
    var mine = r.error === 'changed' && r.draft && (D.unanswered || []).filter(function (u) {
      return u.key === draftKey(r.draft.lines, r.draft.note) && Number(r.draft.version) === Number(u.base || 0) + 1; })[0];
    if (mine) {
      D.unanswered = null;
      D.base_version = Number(r.draft.version); D.updated_at = r.draft.updated_at || D.updated_at;
      D.dirty = true; draftSaveLocal(); draftSchedule();
      return;
    }
    if (r.error === 'changed' && r.draft) { D.stopped = true; D.conflict = r.draft; draftStatus(''); paintDraftNotes(); return; }
    if (r.error === 'draft_used') { D.stopped = true; D.used = r.po_id || true; draftStatus(''); paintDraftNotes(); return; }
    draftStatus(errText(r), 'err');
  }
  function draftKey(lines, note) {
    return JSON.stringify([(lines || []).map(function (l) { return [String(l.vendor_item_id), round(Number(l.packs) || 0, 3)]; }).sort(), note || null]);
  }
  function sameDraft(server, sent) { return !!server && draftKey(server.lines, server.note) === draftKey(sent.lines, sent.note); }
  /* the page goes away for good: what is not on the server yet goes with keepalive (the local copy is already saved);
     never beside a save already on its way */
  function draftBeacon() {
    var D = DRAFT;
    if (!D || D.stopped || !D.dirty || MODE !== 'manage' || draftFlight) return;
    if (!D.lines.length && !D.note && !D.base_version) return;
    try {
      var s = ls('sb-' + new URL(CFG.url).hostname.split('.')[0] + '-auth-token');
      if (!s || !s.access_token) return;
      var h = { 'Content-Type': 'application/json', apikey: CFG.key, Authorization: 'Bearer ' + s.access_token };
      var u = HG_ACCESS.current(); if (u && u.token) h['x-hg-unlock'] = u.token;
      fetch(CFG.url + '/rest/v1/rpc/proveedor_borrador_guardar', { method: 'POST', keepalive: true, headers: h,
        body: JSON.stringify({ p_vendor_id: D.vendor, p_lines: serverLines(), p_note: D.note || null, p_version: D.base_version }) }).catch(function () {});
    } catch (e) {}
  }
  window.addEventListener('pagehide', draftBeacon);
  /* switching apps: the ordinary save, tracked like any other (its answer moves the version on), not a blind beacon */
  document.addEventListener('visibilitychange', function () {
    if (!document.hidden || !DRAFT || DRAFT.stopped || !DRAFT.dirty || MODE !== 'manage') return;
    if (draftFlight) { DRAFT.again = true; return; }
    draftPush();
  });
  async function draftFlush() { clearTimeout(draftTimer); if (draftFlight) await draftFlight; if (DRAFT && DRAFT.dirty && !DRAFT.stopped) await draftPush(); }

  function prodById(id) { return FICHA ? (FICHA.products || []).filter(function (p) { return p.id === id; })[0] || null : null; }
  /* only a live catalog row (active, its inventory item active) is counted, shown or ordered */
  function liveById(id) { return liveProducts().filter(function (p) { return p.id === id; })[0] || null; }
  /* a ticked product retired from the catalog (or whose inventory item was switched off) since: off the draft, said once */
  function pruneDraft() {
    if (!DRAFT || !FICHA || FICHA.vendor.id !== DRAFT.vendor) return;
    var gone = DRAFT.lines.filter(function (l) { return !liveById(l.vendor_item_id); });
    if (!gone.length) return;
    DRAFT.lines = DRAFT.lines.filter(function (l) { return !!liveById(l.vendor_item_id); });
    DRAFT.removed = gone.map(function (l) { var p = prodById(l.vendor_item_id); return { name: p ? pname(p) : null, packs: l.packs, inactive: !!(p && p.item_active === false) }; });
    draftTouched();
  }
  function liveProducts() { return FICHA ? (FICHA.products || []).filter(function (p) { return p.active && p.item_active !== false; }) : []; }
  function suggestion(p) {
    if (PIN && PIN.vi === p.id && Number(PIN.suggest) > 0) return Number(PIN.suggest);
    return Number(p.usual_qty) > 0 ? Number(p.usual_qty) : Number(p.last_packs) > 0 ? Number(p.last_packs) : 1;
  }
  function priceOf(p, l) { return l && l.pack_price != null ? Number(l.pack_price) : p.usual_price != null ? Number(p.usual_price) : null; }
  async function renderPedir(body, F, itemId) {
    var V = F.vendor;
    if (!DRAFT || DRAFT.vendor !== V.id) draftOpen(V.id, F.draft);
    pruneDraft();
    PIN = null;
    if (itemId && isUuid(itemId)) {
      var A = await alertItem(itemId), rows = liveProducts().filter(function (p) { return p.item_id === itemId; });
      var row = (A && A.vendor_item_id && rows.filter(function (p) { return p.id === A.vendor_item_id; })[0]) || rows.sort(function (a, b) { return Number(a.pack_qty) - Number(b.pack_qty); })[0];
      if (row) PIN = { vi: row.id, item: itemId, suggest: A && A.vendor_id === V.id ? Number(A.suggest_packs) : 0 };
      else {
        var it = A || {};
        body.appendChild(el('p', 'note', esc('This supplier does not have that item in its catalog yet.')));
        PENDING_NEW = { vendor: V.id, item_id: itemId, name: it.name, unit: it.unit, preferred: false };
      }
    }
    body.insertAdjacentHTML('beforeend',
      '<div class="tools"><input type="search" id="pSearch" placeholder="Search a product" aria-label="Search a product">' +
      '<button type="button" class="ghost small" id="pRepeat">Repeat last order</button><button type="button" class="ghost small" id="pNew">+ New product</button></div>' +
      '<div id="pNotes"></div><div id="pNewBox"></div><div id="pUnmatched"></div><div id="pList"></div>' +
      '<label class="f" for="pNote">Note for the supplier</label><textarea id="pNote" maxlength="500" rows="2"></textarea>' +
      '<div class="dstatus" id="pStatus" role="status"></div>' +
      '<div class="bar" id="pBar"><span class="sum" id="pSum"></span><button type="button" id="pCreate">Create order</button></div>' +
      '<p class="err" id="pErr" role="alert"></p>');
    $('pNote').value = DRAFT.note || '';
    $('pNote').addEventListener('input', function () { DRAFT.note = $('pNote').value.slice(0, 500); draftTouched(); });
    $('pSearch').addEventListener('input', paintRows);
    $('pRepeat').addEventListener('click', repeatLast);
    $('pNew').addEventListener('click', function () { productForm($('pNewBox'), V.id, { tickAfter: true }); });
    $('pCreate').addEventListener('click', createOrder);
    if (!(F.orders || []).some(function (o) { return o.status !== 'cancelled'; })) $('pRepeat').hidden = true;
    var list = $('pList');
    list.addEventListener('click', onRowClick);
    list.addEventListener('input', onRowInput);
    list.addEventListener('change', onRowChange);
    /* the alert's prefilled suggestion: the first key typed replaces it (a keyboard or the on-screen pad, which adds to
       what is in the box), so typing 2 gives 2, never 62; the suggestion stays in sight as the box's placeholder and
       comes back if nothing is typed */
    list.addEventListener('focusin', function (e) { var t = e.target; if (t.matches('.step input.pre')) { t.placeholder = t.value; t.value = ''; } });
    list.addEventListener('focusout', function (e) { if (e.target.matches('.step input')) paintRow(e.target.closest('.prow')); });
    paintRows(); paintDraftNotes(); paintUnmatched();
    if (DUP) { var dp = DUP; DUP = null; orderToTicks(dp); }
    if (DRAFT.dirty) draftStatus('Saving…'); else if (DRAFT.base_version && DRAFT.updated_at) draftStatus('Draft saved ' + hhmm(DRAFT.updated_at));
    if (PIN) setTimeout(function () { var r = list.querySelector('.prow.pin'); if (r) try { r.scrollIntoView({ block: 'center' }); } catch (e) {} }, 50);
    if (PENDING_NEW && PENDING_NEW.vendor === V.id) { var pn = PENDING_NEW; PENDING_NEW = null; productForm($('pNewBox'), V.id, { item_id: pn.item_id, item_name: pn.name, unit: pn.unit, preferred: pn.preferred, tickAfter: true }); }
  }
  function orderedRows() {
    var ps = liveProducts().slice();
    ps.sort(function (a, b) {
      var pa = PIN && PIN.vi === a.id ? 0 : 1, pb = PIN && PIN.vi === b.id ? 0 : 1;
      if (pa !== pb) return pa - pb;
      var ha = Number(a.times_ordered) > 0 ? 0 : 1, hb = Number(b.times_ordered) > 0 ? 0 : 1;
      if (ha !== hb) return ha - hb;
      if (!ha && Number(b.times_ordered) !== Number(a.times_ordered)) return Number(b.times_ordered) - Number(a.times_ordered);
      if (!ha && (a.last_ordered_at || '') !== (b.last_ordered_at || '')) return (b.last_ordered_at || '') > (a.last_ordered_at || '') ? 1 : -1;
      return norm(pname(a)).localeCompare(norm(pname(b)));
    });
    return ps;
  }
  function paintRows() {
    var list = $('pList'); if (!list) return;
    var q = norm(($('pSearch') && $('pSearch').value || '').trim());
    list.innerHTML = '';
    var ps = orderedRows();
    if (!ps.length) { list.appendChild(el('p', 'empty', esc('This supplier has no products yet. Tap «+ New product» to add what you buy from them.'))); }
    var shown = 0;
    ps.forEach(function (p) {
      if (q && norm([pname(p), p.item_name, p.vendor_code, p.pack_label].join(' ')).indexOf(q) < 0) return;
      shown++;
      var r = el('div', 'prow'); r.setAttribute('data-vi', p.id);
      var tag = p.stock_status === 'out' ? '<span class="pill out">' + esc('Out of stock') + '</span>' : p.stock_status === 'low' ? '<span class="pill low">' + esc('Low') + '</span>' : '';
      var price = p.usual_price != null ? '<span>' + esc(fmtC(p.usual_price)) + '</span> <span>' + esc('without IVA') + '</span>' : '<span>' + esc('no usual price') + '</span>';
      var on = Number(p.on_order) > 0 ? ' · <span>' + esc('on order:') + '</span> <span>' + esc(qtyU(p.on_order, p.unit)) + '</span>' : '';
      r.innerHTML = '<label class="ck"><input type="checkbox" aria-label="Tick ' + esc(pname(p)) + '"></label>' +
        '<div><div class="nm">' + nt(pname(p)) + (p.vendor_code ? ' <span class="hint">(<span>' + esc('code') + '</span> ' + nt(p.vendor_code) + ')</span>' : '') + ' ' + tag + '</div>' +
        '<div class="ds">' + presHtml(p) + ' · ' + price + on + '</div></div>' +
        '<div class="st"><div class="step"><button type="button" data-a="minus" aria-label="One less">−</button>' +
        '<input type="text" inputmode="decimal" data-keypad="qty" maxlength="10" aria-label="How many of ' + esc(pname(p)) + '">' +
        '<button type="button" data-a="plus" aria-label="One more">+</button></div></div>' +
        (p.usual_price == null ? '<div class="px" hidden><label class="f" for="px-' + esc(p.id) + '">' + esc('Price per presentation without IVA (₡)') + '</label><input class="priceIn" id="px-' + esc(p.id) + '" type="text" inputmode="decimal" data-keypad="qty" maxlength="14" data-price></div>' : '');
      if (PIN && PIN.vi === p.id) r.classList.add('pin');
      list.appendChild(r);
      paintRow(r);
    });
    if (ps.length && !shown) list.appendChild(el('p', 'empty', esc('No product with that name.')));
    paintBar();
  }
  function paintRow(r) {
    if (!r) return;
    var vi = r.getAttribute('data-vi'), p = prodById(vi), l = dline(vi);
    var ck = r.querySelector('.ck input'), inp = r.querySelector('.step input');
    ck.checked = !!l;
    r.classList.toggle('on', !!l);
    if (document.activeElement !== inp) {
      if (l) { inp.value = plainNum(l.packs); inp.classList.remove('pre'); }
      else if (PIN && PIN.vi === vi && p) { inp.value = plainNum(suggestion(p)); inp.classList.add('pre'); }
      else { inp.value = ''; inp.classList.remove('pre'); inp.placeholder = p ? plainNum(suggestion(p)) : ''; }
    }
    var px = r.querySelector('.px');
    if (px) { px.hidden = !l; var pi = px.querySelector('input'); if (l && document.activeElement !== pi) pi.value = l.pack_price != null ? plainNum(l.pack_price) : ''; }
  }
  function onRowClick(e) {
    var b = e.target.closest('button[data-a]'); if (!b) return;
    var r = b.closest('.prow'), vi = r.getAttribute('data-vi'), p = prodById(vi), l = dline(vi);
    if (!p) return;
    if (b.getAttribute('data-a') === 'plus') draftSet(vi, l ? round(Number(l.packs) + 1, 3) : suggestion(p));
    else if (l) draftSet(vi, Number(l.packs) <= 1 ? null : Math.max(1, round(Number(l.packs) - 1, 3)));
    paintRow(r);
  }
  function onRowChange(e) {
    if (!e.target.matches('.ck input')) return;
    var r = e.target.closest('.prow'), vi = r.getAttribute('data-vi'), p = prodById(vi);
    if (!p) return;
    if (e.target.checked) {
      var inp = r.querySelector('.step input'), typed = parseNum(inp.value);
      draftSet(vi, typed > 0 && decimals(typed) <= 3 ? typed : suggestion(p));
    } else draftSet(vi, null);
    paintRow(r);
  }
  function onRowInput(e) {
    var t = e.target, r = t.closest('.prow'); if (!r) return;
    var vi = r.getAttribute('data-vi');
    if (t.hasAttribute('data-price')) {
      var pr = t.value.trim() === '' ? null : parseNum(t.value);
      t.classList.toggle('bad', pr !== null && !(pr >= 0 && pr <= 100000000));
      if (pr === null || (pr >= 0 && pr <= 100000000)) { var l = dline(vi); if (l) { if (pr === null) delete l.pack_price; else l.pack_price = round(pr, 2); draftTouched(); } if (pr !== null && $('pErr')) $('pErr').textContent = ''; }
      return;
    }
    if (!t.matches('.step input')) return;
    t.classList.remove('pre');
    if (t.value.trim() === '') { draftSet(vi, null); paintRow(r); return; }
    var v = parseNum(t.value);
    var ok = v > 0 && v <= 100000 && decimals(v) <= 3;
    t.setCustomValidity(ok ? '' : 'bad'); t.style.borderColor = ok ? '' : 'var(--bad)';
    if (ok) { draftSet(vi, v); var ck = r.querySelector('.ck input'); ck.checked = true; r.classList.add('on'); var px = r.querySelector('.px'); if (px) px.hidden = false; }
    else if (v === 0) { draftSet(vi, null); r.querySelector('.ck input').checked = false; r.classList.remove('on'); }
  }
  function draftTotals() {
    var n = 0, tot = 0, noPrice = 0;
    (DRAFT ? DRAFT.lines : []).forEach(function (l) {
      var p = liveById(l.vendor_item_id); if (!p) return;
      n++; var pr = priceOf(p, l);
      if (pr == null) noPrice++; else tot += pr * Number(l.packs);
    });
    return { n: n, total: round(tot, 2), noPrice: noPrice };
  }
  function paintBar() {
    var s = $('pSum'); if (!s) return;
    var t = draftTotals();
    s.innerHTML = '<span>' + esc(t.n === 1 ? '1 product' : t.n + ' products') + '</span> · <span>' + esc('Estimated total ' + fmtC(t.total)) + '</span>' +
      (t.noPrice ? ' · <span>' + esc(t.noPrice + ' without price') + '</span>' : '');
    /* a draft in conflict, or one another device already turned into an order: the choice above first */
    $('pCreate').disabled = !t.n || CREATING || !!(DRAFT && (DRAFT.conflict || DRAFT.used));
  }
  /* the notices above the list: local changes left by a newer server draft; a conflict; the draft became an order */
  function paintDraftNotes() {
    var box = $('pNotes'); if (!box || !DRAFT) return;
    box.innerHTML = '';
    paintBar();   /* «Crear pedido» follows the notices (off while one asks for a choice) */
    if (DRAFT.removed && DRAFT.removed.length) {
      var rm = el('div', 'note'); rm.setAttribute('role', 'status');
      rm.appendChild(el('p', '', esc('Taken off this order (no longer in the catalog, or the inventory item is inactive):')));
      var rl = el('ul', 'hist');
      DRAFT.removed.forEach(function (x) { rl.appendChild(el('li', '', (x.name ? nt(x.name) : esc('A product no longer in the catalog')) + ' · ' + esc(num(x.packs)) + (x.inactive ? ' · <span>' + esc('inventory item inactive') + '</span>' : ''))); });
      rm.appendChild(rl);
      var rb = el('div', 'btns'); rb.appendChild(btn('Understood', 'ghost small', function () { DRAFT.removed = null; paintDraftNotes(); })); rm.appendChild(rb);
      box.appendChild(rm);
    }
    if (DRAFT.leftover) {
      var n = el('div', 'note'); n.innerHTML = '<span>' + esc('There were unsaved changes on this device') + '</span>';
      var b = el('div', 'btns');
      b.appendChild(btn('See', 'ghost small', function () {
        var ul = el('ul', 'sumlist');
        DRAFT.leftover.lines.forEach(function (l) { var p = prodById(l.vendor_item_id); ul.appendChild(el('li', '', (p ? nt(pname(p)) : esc('A product no longer in the catalog')) + ' · ' + esc(num(l.packs)))); });
        if (DRAFT.leftover.note) ul.appendChild(el('li', '', esc('Note:') + ' ' + nt(DRAFT.leftover.note)));
        n.insertBefore(ul, b);
        b.insertBefore(btn('Use these', 'small', function () { DRAFT.lines = DRAFT.leftover.lines.filter(function (l) { return !!liveById(l.vendor_item_id); }); DRAFT.note = DRAFT.leftover.note || DRAFT.note; DRAFT.leftover = null; $('pNote').value = DRAFT.note || ''; draftTouched(); paintRows(); paintDraftNotes(); }), b.firstChild);
        this.remove();
      }));
      b.appendChild(btn('Discard', 'ghost small', function () { DRAFT.leftover = null; draftSaveLocal(); paintDraftNotes(); }));
      n.appendChild(b); box.appendChild(n);
    }
    if (DRAFT.conflict) {
      var c = el('div', 'note bad'); c.innerHTML = '<span>' + esc('This draft was changed on another device. Autosave is paused.') + '</span>';
      var cb = el('div', 'btns');
      cb.appendChild(btn('Use the other device\'s', 'small', function () {
        var s = DRAFT.conflict; DRAFT.lines = cleanLines(s.lines); DRAFT.note = s.note || ''; DRAFT.base_version = Number(s.version) || 0; DRAFT.updated_at = s.updated_at;
        DRAFT.dirty = false; DRAFT.stopped = false; DRAFT.conflict = null; draftSaveLocal(); $('pNote').value = DRAFT.note; paintRows(); paintDraftNotes(); draftStatus('Draft saved ' + hhmm(DRAFT.updated_at));
      }));
      cb.appendChild(btn('Merge', 'ghost small', function () {
        var s = DRAFT.conflict, map = {};
        cleanLines(s.lines).concat(DRAFT.lines).forEach(function (l) { var m = map[l.vendor_item_id]; if (!m || Number(l.packs) > Number(m.packs)) map[l.vendor_item_id] = Object.assign({}, m || {}, l); });
        DRAFT.lines = Object.keys(map).map(function (k) { return map[k]; });
        DRAFT.note = DRAFT.note || s.note || ''; DRAFT.base_version = Number(s.version) || 0; DRAFT.stopped = false; DRAFT.conflict = null;
        $('pNote').value = DRAFT.note; paintRows(); paintDraftNotes(); draftTouched();
      }));
      c.appendChild(cb); box.appendChild(c);
    }
    if (DRAFT.used) {
      var u = el('div', 'note'); u.innerHTML = '<span>' + esc(ERR.draft_used) + '</span>';
      var ub = el('div', 'btns');
      if (isUuid(DRAFT.used)) ub.appendChild(link('Open the order', '#pedido=' + DRAFT.used, 'btnlink small solid'));
      ub.appendChild(btn('Start a new draft with what is ticked', 'ghost small', function () { DRAFT.used = null; DRAFT.base_version = 0; DRAFT.stopped = false; paintDraftNotes(); draftTouched(); }));
      ub.appendChild(btn('Discard', 'ghost small', function () { ls(dkey(DRAFT.vendor), null); DRAFT = null; reloadFicha('pedir'); }));
      u.appendChild(ub); box.appendChild(u);
    }
  }
  /* «Repetir último pedido» and «Duplicar»: an order's lines become the ticks (one confirmation when something is ticked) */
  async function repeatLast() {
    var last = (FICHA.orders || []).filter(function (o) { return o.status !== 'cancelled'; }).sort(function (a, b) { return (b.created_at || '') > (a.created_at || '') ? 1 : -1; })[0];
    if (last) await orderToTicks(last.id);
  }
  async function orderToTicks(poId) {
    if (DRAFT && DRAFT.lines.length && !confirm('This replaces what is ticked. Continue?')) return;
    var r = await rpc('proveedor_pedido', { p_po_id: poId });
    if (!r.ok) { if (!r.handled) toast(errText(r)); return; }
    var ps = liveProducts(), lines = [], miss = [];
    (r.lines || []).forEach(function (l) {
      if (l.removed || !(Number(l.packs) > 0)) return;
      var p = ps.filter(function (x) { return x.id === l.vendor_item_id; })[0] ||
              ps.filter(function (x) { return x.item_id === l.item_id && Math.abs(Number(x.pack_qty) - Number(l.pack_qty)) < 1e-9; })[0];
      if (p && !lines.some(function (x) { return x.vendor_item_id === p.id; })) lines.push({ vendor_item_id: p.id, packs: round(l.packs, 3) });
      else if (!p) miss.push(l);
    });
    DRAFT.lines = lines; DRAFT.leftover = null;
    UNMATCHED[DRAFT.vendor] = miss;
    draftTouched(); paintRows(); paintUnmatched();
    toast(lines.length + ' products ticked from order Nº ' + (r.order && r.order.po_number));
  }
  function paintUnmatched() {
    var box = $('pUnmatched'); if (!box || !DRAFT) return;
    box.innerHTML = '';
    var miss = UNMATCHED[DRAFT.vendor] || [];
    if (!miss.length) return;
    var n = el('div', 'note'); n.innerHTML = '<span>' + esc('Not in this supplier\'s catalog yet:') + '</span>';
    var ul = el('ul', 'sumlist');
    miss.forEach(function (l, i) {
      var li = el('li', '', nt(pname(l)) + ' · ' + esc(num(l.packs)) + ' × ' + (l.pack_label ? nt(l.pack_label) : esc(qtyU(l.pack_qty, l.unit))) + ' ');
      li.appendChild(btn('Add to the catalog', 'linkbtn', function () {
        productForm($('pNewBox'), DRAFT.vendor, { item_id: l.item_id, item_name: l.item_name, unit: l.unit, pack_label: l.pack_label, pack_qty: l.pack_qty, usual_price: l.expected_pack_price, label: l.label, vendor_code: l.vendor_code, tickAfter: true, tickPacks: l.packs,
          done: function () { miss.splice(i, 1); paintUnmatched(); } });
      }));
      ul.appendChild(li);
    });
    n.appendChild(ul); box.appendChild(n);
  }
  /* «Crear pedido»: one request id kept until the server answers; the button waits for it */
  var CREATING = false;
  async function createOrder() {
    if (CREATING || !DRAFT || DRAFT.conflict || DRAFT.used) return;
    var err = $('pErr'); err.textContent = '';
    var D = DRAFT, lines = [], missing = null;
    D.lines.forEach(function (l) {
      var p = liveById(l.vendor_item_id); if (!p) return;
      var o = { vendor_item_id: l.vendor_item_id, packs: l.packs };
      if (l.pack_price != null) { o.pack_price = l.pack_price; if (Number(l.pack_price) === 0) o.free = true; }
      else if (p.usual_price == null) missing = missing || p;
      lines.push(o);
    });
    if (!lines.length) return;
    if (missing) { err.textContent = 'Type the price of ' + pname(missing) + '.'; var x = $('px-' + missing.id); if (x) x.focus(); return; }
    CREATING = true; paintBar();
    $('pCreate').textContent = 'Creating…';
    try {
      await draftFlush();
      if (DRAFT !== D) return;
      /* the flush itself may find that the draft became an order or changed on another device: that choice first */
      if (D.used || D.conflict) { paintDraftNotes(); return; }
      if (!D.req) { D.req = uuid(); draftSaveLocal(); }
      var r = await rpc('proveedor_pedido_crear', { p_vendor_id: D.vendor, p_lines: lines, p_note: D.note || null, p_request_id: D.req,
        p_draft_version: D.base_version > 0 ? D.base_version : null, p_expected_on: null });
      if (DRAFT !== D) return;
      if (r.ok) {
        ls(dkey(D.vendor), null); DRAFT = null; UNMATCHED[D.vendor] = [];
        forgetFicha(D.vendor);
        toast('Created order Nº ' + (r.po_number || ''));
        go('#pedido=' + (r.id || D.req));
        return;
      }
      if (r.handled) return;
      if (r.error === 'draft_used') { ls(dkey(D.vendor), null); DRAFT = null; forgetFicha(D.vendor); toast(ERR.draft_used); if (r.po_id) go('#pedido=' + r.po_id); else reloadFicha('pedir'); return; }
      if (r.error === 'draft_changed') {
        var s = r.draft || {};
        /* the id kept here already made an order (its answer was lost): these ticks are a new order with a new id */
        if (r.stale_request) D.req = uuid();
        D.lines = cleanLines(s.lines); D.note = s.note || ''; D.base_version = Number(s.version) || 0; D.dirty = false; D.stopped = false; D.conflict = null; draftSaveLocal();
        $('pNote').value = D.note; paintRows(); paintDraftNotes();
        err.textContent = r.stale_request ? 'This device already made order Nº {n} earlier. What is ticked now is a new order: check it and tap «Create order».'.replace('{n}', r.po_number || '') : ERR.draft_changed;
        return;
      }
      /* a product retired or switched off on another device a moment ago: off the order, said, never «reload» */
      if ((r.error === 'not_found' || r.error === 'item_inactive') && r.vendor_item_id && dline(r.vendor_item_id)) {
        var gp = prodById(r.vendor_item_id), gl = dline(r.vendor_item_id);
        if (gp) { if (r.error === 'item_inactive') gp.item_active = false; else gp.active = false; }   /* as the server has it now */
        D.lines = D.lines.filter(function (l) { return l.vendor_item_id !== r.vendor_item_id; });
        D.removed = (D.removed || []).concat([{ name: gp ? pname(gp) : null, packs: gl ? gl.packs : 0, inactive: r.error === 'item_inactive' }]);
        draftTouched(); paintRows(); paintDraftNotes();
        err.textContent = 'A product can no longer be ordered and was taken off the order. Check it and tap «Create order» again.';
        return;
      }
      err.textContent = errText(r) + (r.line_id || r.vendor_item_id ? ' ' : '');
      var bad = r.vendor_item_id && document.querySelector('.prow[data-vi="' + r.vendor_item_id + '"]'); if (bad) bad.classList.add('pin');
    } finally {
      CREATING = false; var b = $('pCreate'); if (b) { b.textContent = 'Create order'; paintBar(); }
    }
  }

  /* «+ Producto nuevo» / «Añadir producto» / «Añadir al catálogo»: an existing inventory item first («Usar este»), else a
     new one; the presentation, units per presentation and the usual price (per presentation, without IVA) */
  FORMS.product = async function (vid, pre, opts) {
    if (!FICHA || FICHA.vendor.id !== vid) return;
    var box = $('pNewBox') || $('prNewBox'); if (box) { box.innerHTML = ''; productForm(box, vid, Object.assign({}, pre || {}, { req: opts && opts.req })); }
  };
  async function stockItems() {
    if (CACHE.items) return CACHE.items;
    var r = await db.from('stock_items').select('id,name,unit,active,pack_label,pack_qty,vendor_id').eq('active', true).order('name');
    CACHE.items = r && !r.error ? r.data || [] : null;
    return CACHE.items;
  }
  function productForm(box, vid, pre) {
    pre = pre || {};
    box.innerHTML = '';
    var req = pre.req || uuid(), item = pre.item_id ? { id: pre.item_id, name: pre.item_name, unit: pre.unit } : null;
    var f = el('form', 'inline form'); f.id = 'productForm'; f.setAttribute('autocomplete', 'off');
    f.innerHTML = '<h3 style="margin-top:0">' + esc('New product for this supplier') + '</h3>' +
      '<div id="npItemBox"><label class="f" for="npFind">' + esc('Inventory item') + '</label><input id="npFind" type="search" placeholder="Search the inventory first" maxlength="80">' +
      '<div class="found" id="npFound"></div></div>' +
      '<div id="npChosen" class="note ok" hidden></div>' +
      '<div id="npNewItem" hidden><div class="row"><div><label class="f" for="npName">' + esc('New item name') + '</label><input id="npName" maxlength="80"></div>' +
      '<div><label class="f" for="npUnit">' + esc('Counted in') + '</label><select id="npUnit"><option value="unit">units</option><option value="g">grams</option><option value="kg">kilograms</option><option value="ml">millilitres</option><option value="L">litres</option></select></div></div>' +
      '<div class="row"><div><label class="f" for="npReorder">' + esc('Reorder point (alert at)') + '</label><input id="npReorder" type="text" inputmode="decimal" data-keypad="qty" value="0"></div>' +
      '<div><label class="f" for="npPar">' + esc('Par level (target after an order)') + '</label><input id="npPar" type="text" inputmode="decimal" data-keypad="qty" value="0"></div></div></div>' +
      '<div class="row"><div><label class="f" for="npPack">' + esc('Presentation') + '</label><input id="npPack" maxlength="60" placeholder="e.g. box of 12"></div>' +
      '<div><label class="f" for="npQty" id="npQtyLab">' + esc('Units per presentation') + '</label><input id="npQty" type="text" inputmode="decimal" data-keypad="qty" maxlength="12"></div></div>' +
      '<p class="hint" id="npHint"></p>' +
      '<div class="row"><div><label class="f" for="npPrice">' + esc('Usual price per presentation, without IVA (₡)') + '</label><input id="npPrice" type="text" inputmode="decimal" data-keypad="qty" maxlength="14"></div>' +
      '<div><label class="f" for="npUsual">' + esc('Usual quantity (optional)') + '</label><input id="npUsual" type="text" inputmode="decimal" data-keypad="qty" maxlength="10"></div></div>' +
      '<div class="row"><div><label class="f" for="npCode">' + esc('Supplier code (optional)') + '</label><input id="npCode" maxlength="40"></div>' +
      '<div><label class="f" for="npLabel">' + esc('Name at this supplier (optional)') + '</label><input id="npLabel" maxlength="80"></div></div>' +
      '<label class="checkline"><input type="checkbox" id="npPref"> <span>Preferred supplier of this item</span></label>' +
      '<p class="err" id="npErr" role="alert"></p><div class="btns"><button type="button" class="ghost" id="npCancel">Cancel</button><button type="submit" id="npGo">Save product</button></div>';
    box.appendChild(f);
    formOpened('product', [vid, { item_id: pre.item_id, item_name: pre.item_name, unit: pre.unit, tickAfter: pre.tickAfter }], f, req);
    var set = function (id, v) { if (v != null && v !== '') $(id).value = String(v); };
    set('npPack', pre.pack_label); set('npQty', pre.pack_qty != null ? plainNum(pre.pack_qty) : ''); set('npPrice', pre.usual_price != null ? plainNum(pre.usual_price) : '');
    set('npCode', pre.vendor_code); set('npLabel', pre.label);
    $('npPref').checked = !!pre.preferred;
    var unitNow = function () { return item ? item.unit : $('npUnit').value; };
    var hint = function () {
      var u = unitNow(), q = parseNum($('npQty').value);
      $('npQtyLab').textContent = u === 'unit' ? 'Units per presentation' : u === 'g' ? 'Grams per presentation' : u === 'kg' ? 'Kilograms per presentation' : u === 'ml' ? 'Millilitres per presentation' : 'Litres per presentation';
      var pk = $('npPack').value.trim();
      $('npHint').innerHTML = q > 0 ? '1 ' + (pk ? nt(pk) : '<span>' + esc('presentation') + '</span>') + ' = <span>' + esc(qtyU(q, u)) + '</span>' : '';
    };
    var choose = function (it) {
      item = it;
      $('npItemBox').hidden = !!it; $('npNewItem').hidden = true;
      var c = $('npChosen'); c.hidden = !it;
      if (it) { c.innerHTML = '<span>' + esc('Inventory item:') + '</span> <b>' + nt(it.name) + '</b> · <span>' + esc(unitWord(it.unit, 2)) + '</span> '; c.appendChild(btn('Change item', 'linkbtn', function () { choose(null); $('npFind').focus(); })); if (!$('npPack').value && it.pack_label) $('npPack').value = it.pack_label; if (!$('npQty').value && it.pack_qty) $('npQty').value = plainNum(it.pack_qty); }
      hint();
    };
    if (item) choose(item);
    var findT = null;
    $('npFind').addEventListener('input', function () {
      clearTimeout(findT);
      findT = setTimeout(async function () {
        var q = norm($('npFind').value.trim()), found = $('npFound'); found.innerHTML = '';
        if (!q) return;
        var items = await stockItems();
        if (items === null) { found.appendChild(el('p', 'err', esc(ERR.offline))); return; }
        var hits = items.filter(function (i) { return norm(i.name).indexOf(q) > -1; }).slice(0, 8);
        hits.forEach(function (i) { var b2 = btn('', '', function () { choose(i); }); b2.innerHTML = '<span>' + esc('Use this') + ':</span> <b>' + nt(i.name) + '</b> <span class="hint">' + esc(unitWord(i.unit, 2)) + '</span>'; found.appendChild(b2); });
        var nb = btn('', 'ghost small', function () { $('npItemBox').hidden = true; $('npNewItem').hidden = false; $('npName').value = $('npFind').value.trim(); $('npName').focus(); hint(); });
        nb.textContent = hits.length ? 'None of these: a new item' : 'Not in the inventory: a new item'; found.appendChild(nb);
      }, 200);
    });
    ['npQty', 'npPack', 'npUnit'].forEach(function (id) { $(id).addEventListener('input', hint); $(id).addEventListener('change', hint); });
    $('npCancel').addEventListener('click', function () { box.innerHTML = ''; formClosed(f); });
    (item ? $('npPack') : $('npFind')).focus();
    f.addEventListener('submit', async function (e) {
      e.preventDefault();
      var E = $('npErr'); E.textContent = '';
      var q = parseNum($('npQty').value), price = $('npPrice').value.trim() === '' ? null : parseNum($('npPrice').value), uq = $('npUsual').value.trim() === '' ? null : parseNum($('npUsual').value);
      var p = { id: req, vendor_id: vid, vendor_code: $('npCode').value.trim() || null, label: $('npLabel').value.trim() || null, pack_label: $('npPack').value.trim() || null,
                pack_qty: q, usual_price: price, usual_qty: uq, preferred: $('npPref').checked };
      if (item) p.item_id = item.id;
      else if (!$('npNewItem').hidden) {
        var nm = $('npName').value.trim(); if (!nm) { E.textContent = 'Type the name of the new item.'; return; }
        var ro = parseNum($('npReorder').value || '0'), pl = parseNum($('npPar').value || '0');
        if (!(ro >= 0) || !(pl >= 0)) { E.textContent = 'Check the reorder point and the par level.'; return; }
        p.new_item = { name: nm, unit: $('npUnit').value, category: 'other', reorder_point: ro, par_level: pl };
      } else { E.textContent = 'Pick the inventory item, or create a new one.'; $('npFind').focus(); return; }
      if (!(q > 0 && q < 1e9)) { E.textContent = 'Type how much one presentation holds.'; $('npQty').focus(); return; }
      if (price !== null && !(price >= 0 && price <= 100000000)) { E.textContent = ERR.bad_price; return; }
      if (uq !== null && !(uq > 0 && uq <= 100000)) { E.textContent = 'Check the usual quantity.'; return; }
      $('npGo').disabled = true;
      var r = await rpc('proveedor_producto_guardar', { p_item: p });
      $('npGo').disabled = false;
      if (!r.ok) {
        if (r.handled) return;
        E.textContent = errText(r);
        if (r.error === 'duplicate_item' && r.id) { var items = await stockItems(); var ex = (items || []).filter(function (i) { return i.id === r.id; })[0] || { id: r.id, name: p.new_item.name, unit: p.new_item.unit }; E.appendChild(document.createTextNode(' ')); E.appendChild(btn('Use that one', 'linkbtn', function () { choose(ex); E.textContent = ''; })); }
        return;
      }
      formClosed(f); box.innerHTML = '';
      delete CACHE.items; forgetFicha(vid);
      toast('Product saved');
      var nr = await loadFicha(vid, true);
      if (nr.ok) FICHA = nr;
      if (pre.done) pre.done();
      if (pre.tickAfter && DRAFT && DRAFT.vendor === vid && r.id) draftSet(r.id, Number(pre.tickPacks) > 0 ? Number(pre.tickPacks) : uq > 0 ? uq : 1);
      if (pre.item_id && pre.preferred) { go('#p=' + encodeURIComponent(vid) + '&item=' + encodeURIComponent(pre.item_id)); return; }
      var tb = $('fTab'); if (tb && parseHash().t !== 'productos') { tb.innerHTML = ''; renderPedir(tb, FICHA, null); } else reloadFicha('productos');
    });
  }

  /* ---------- 11) «Pedidos», «Pagos», «Productos» ---------- */
  var ST_TXT = { draft: 'Draft', sent: 'Created', partially_received: 'Partially received', received: 'Received', cancelled: 'Cancelled' };
  var PAY_TXT = { pending: 'Payment pending', partial: 'Partly paid', paid: 'Paid' };
  function statusPill(s) { return '<span class="pill ' + esc(s) + '">' + esc(ST_TXT[s] || s) + '</span>'; }
  function payPill(m) { return m && PAY_TXT[m.status] ? ' <span class="pill pay-' + esc(m.status) + '">' + esc(PAY_TXT[m.status]) + '</span>' : ''; }
  function orderCard(o, vid) {
    var row = el('div', 'orow'); row.setAttribute('data-po', o.id);
    row.appendChild(el('span', 't', esc('Order Nº ' + (o.po_number || ''))));
    var d = el('span', 'd');
    var tot = Number(o.received_total) > 0 ? 'received ' + fmt(o.received_total) : 'estimated ' + fmt(o.est_total);
    d.innerHTML = statusPill(o.status) + payPill(o.money) + ' · <span>' + esc(fmtD(o.created_at)) + '</span> · <span>' + esc(Number(o.lines) === 1 ? '1 line' : (o.lines || 0) + ' lines') + '</span>' +
      (Number(o.pending_lines) > 0 && o.status !== 'received' && o.status !== 'cancelled' ? ' · <span>' + esc(Number(o.pending_lines) === 1 ? '1 pending' : o.pending_lines + ' pending') + '</span>' : '') + ' · <span>' + esc(tot) + '</span>' +
      (o.close_requested ? ' · <span class="pill gold">' + esc('The rest is not coming') + '</span>' : '');
    row.appendChild(d);
    var a = el('span', 'acts');
    a.appendChild(link('Open', '#pedido=' + o.id));
    if (FLAGS.can_manage && /^(draft|sent|partially_received)$/.test(o.status)) a.appendChild(link('Receive', '#recibir=' + o.id, 'btnlink small solid'));
    if (FLAGS.can_manage && o.status !== 'cancelled') a.appendChild(btn('Duplicate', 'ghost small', function () { duplicateOrder(vid, o.id); }));
    row.appendChild(a);
    return row;
  }
  function duplicateOrder(vid, poId) {
    DUP = poId;
    go('#p=' + encodeURIComponent(vid) + '&t=pedir');
  }
  var DUP = null;
  function renderPedidos(body, F) {
    var V = F.vendor, open = [], closed = [];
    (F.orders || []).forEach(function (o) { (/^(draft|sent|partially_received)$/.test(o.status) ? open : closed).push(o); });
    body.appendChild(el('h3', '', esc('Open orders with this supplier')));
    var ol = el('div', 'olist'); open.forEach(function (o) { ol.appendChild(orderCard(o, V.id)); });
    if (!open.length) ol.appendChild(el('p', 'empty', esc('No open orders with this supplier.')));
    body.appendChild(ol);
    body.appendChild(el('h3', '', esc('History')));
    var hl = el('div', 'olist'); hl.id = 'hist';
    closed.forEach(function (o) { hl.appendChild(orderCard(o, V.id)); });
    if (!closed.length) hl.appendChild(el('p', 'empty', esc('Nothing received yet.')));
    body.appendChild(hl);
    var before = closed.length ? closed[closed.length - 1].created_at : null, beforeId = closed.length ? closed[closed.length - 1].id : null;
    if (closed.length >= 30) {
      var more = btn('See more', 'ghost small', async function () {
        more.disabled = true;
        var r = await rpc('proveedor_historial', { p_vendor_id: V.id, p_before: before, p_limit: 50, p_before_id: beforeId });
        more.disabled = false;
        if (!r.ok) { if (!r.handled) toast(errText(r)); return; }
        var rows = r.orders || [];
        rows.forEach(function (o) { hl.appendChild(orderCard(o, V.id)); });
        if (rows.length) { before = rows[rows.length - 1].created_at; beforeId = rows[rows.length - 1].id; }
        if (rows.length < 50) more.remove();
      });
      body.appendChild(more);
    }
  }
  function renderPagos(body, F) {
    var V = F.vendor, M = F.money || {};
    if (AFTER_PAY && (M.uninvoiced || []).some(function (u) { return u.po_id === AFTER_PAY; })) {
      var ap = el('div', 'note'), apo = AFTER_PAY; AFTER_PAY = null;
      ap.appendChild(el('span', '', esc('Payment saved. That order has deliveries without invoice: register it, with S/N if it has none.')));
      var ab = el('div', 'btns'); ab.appendChild(btn('Register the invoice (S/N if it has none)', 'small', function () { openInvoice(V.id, apo); })); ap.appendChild(ab);
      body.appendChild(ap);
    }
    var unappl = (M.advances || []).filter(function (a) { return !a.voided_at && Number(a.amount_crc) - Number(a.applied_crc || 0) > 0.005; });
    var k = el('div', 'kpis'); k.style.cssText = 'display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:.6rem';
    k.innerHTML = '<div class="inline" style="margin:0"><div class="hint">' + esc('Balance owed') + '</div><div class="mono" style="font-size:1.4rem" id="pgOwed">' + esc(fmt(M.owed_crc)) + '</div></div>' +
      '<div class="inline" style="margin:0"><div class="hint">' + esc('Balance in favour') + '</div><div class="mono" style="font-size:1.4rem" id="pgCredit">' + esc(fmt(M.credit_crc)) + '</div></div>';
    body.appendChild(k);
    var acts = el('div', 'btns');
    if (FLAGS.can_pay) acts.appendChild(btn('Register a payment', '', function () { openPay(V.id, null); }, { id: 'pgPay' }));
    if (FLAGS.can_pay && (M.uninvoiced || []).length) acts.appendChild(btn('Register the invoice', 'ghost', function () { openInvoice(V.id, null); }, { id: 'pgInv' }));
    if (FLAGS.can_pay && unappl.length && (M.open_invoices || []).length) acts.appendChild(btn('Apply to open invoices', 'ghost', async function () {
      var r = await rpc('proveedor_anticipos_aplicar', { p_vendor_id: V.id });
      if (!r.ok) { if (!r.handled) toast(errText(r)); return; }
      toast('Applied ' + fmtC(r.applied_crc != null ? r.applied_crc : r.applied || 0)); reloadFicha('pagos');
    }, { id: 'pgApply' }));
    body.appendChild(acts);
    /* each order still to pay */
    var dueOrders = (F.orders || []).filter(function (o) { return o.status !== 'cancelled' && o.money && (Number(o.money.due) > 0.5 || Number(o.money.paid) > 0.5) && o.money.status !== 'paid'; });
    body.appendChild(el('h3', '', esc('Orders')));
    var ol = el('div', 'olist');
    if (!dueOrders.length) ol.appendChild(el('p', 'empty', esc('Nothing pending to pay on the orders.')));
    dueOrders.forEach(function (o) {
      var m = o.money, tp = toPay(m), row = el('div', 'orow');
      row.innerHTML = '<span class="t">' + esc('Order Nº ' + o.po_number) + '</span><span class="d">' + payPill(m) + ' · <span>' + esc('to pay ' + fmtC(tp.v)) + '</span> · <span>' + esc('paid ' + fmtC(m.paid)) + '</span>' +
        (tp.est ? ' · <span>' + esc('estimated, IVA incl.') + '</span>' : '') + (m.invoice_missing ? ' · <span class="pill gold">' + esc('Invoice missing') + '</span>' : '') + '</span>';
      var a = el('span', 'acts');
      if (FLAGS.can_pay) a.appendChild(btn('Pay now', 'small', function () { openPay(V.id, o.id); }));
      a.appendChild(link('Open', '#pedido=' + o.id));
      row.appendChild(a); ol.appendChild(row);
    });
    body.appendChild(ol);
    if ((M.open_invoices || []).length) {
      body.appendChild(el('h3', '', esc('Open invoices')));
      var il = el('div', 'olist');
      M.open_invoices.forEach(function (i) {
        var row = el('div', 'orow');
        row.innerHTML = '<span class="t">' + nt(i.number) + '</span><span class="d"><span>' + esc(fmtD(i.date)) + '</span>' + (i.due_date ? ' · <span>' + esc('due ' + fmtD(i.due_date)) + '</span>' : '') +
          ' · <span>' + esc('total ' + fmtC(i.total_crc)) + '</span> · <b>' + esc('open ' + fmtC(i.open_crc)) + '</b></span>';
        if (ACCOUNT === 'accountant' || ownerWithCode()) { var a = el('span', 'acts'); a.appendChild(btn('Void invoice', 'ghost small danger', function () { voidInvoice(V.id, i); })); row.appendChild(a); }
        il.appendChild(row);
      });
      body.appendChild(il);
    }
    if ((M.uninvoiced || []).length) {
      body.appendChild(el('h3', '', esc('Deliveries without invoice')));
      var ul = el('div', 'olist');
      M.uninvoiced.forEach(function (u) {
        var row = el('div', 'orow');
        row.innerHTML = '<span class="t">' + esc('Order Nº ' + (u.po_number || '')) + '</span><span class="d"><span>' + esc(fmtD(u.received_at)) + '</span> · <span>' + esc('received ' + fmtC(u.total_crc)) + '</span>' +
          (u.invoice_no ? ' · <span>' + esc('invoice') + '</span> ' + nt(u.invoice_no) : '') + (Number(u.payout_crc) > 0 ? ' · <span>' + esc('Register cash paid ' + fmtC(u.payout_crc)) + '</span>' : '') + '</span>';
        ul.appendChild(row);
      });
      body.appendChild(ul);
    }
    body.appendChild(el('h3', '', esc('Payments')));
    var pl = el('div', 'olist');
    var METHOD = { sinpe: 'SINPE', card_debit: 'Debit card', card_credit: 'Credit card' };
    (M.advances || []).forEach(function (a) {
      var row = el('div', 'orow'), left = Number(a.amount_crc) - Number(a.applied_crc || 0);
      row.innerHTML = '<span class="t mono">' + esc(fmtC(a.amount_crc)) + '</span><span class="d"><span>' + esc(fmtD(a.date)) + '</span> · <span>' + esc(METHOD[a.method] || a.method) + '</span>' + (a.reference ? ' · ' + nt(a.reference) : '') +
        (a.po_number ? ' · <span>' + esc('order Nº ' + a.po_number) + '</span>' : '') +
        (a.voided_at ? ' · <span class="pill mute">' + esc('voided') + '</span>' : left > 0.005 ? ' · <span class="pill gold">' + esc('unapplied ' + fmtC(left)) + '</span>' : ' · <span class="pill pay-paid">' + esc('applied') + '</span>') + '</span>';
      if (!a.voided_at && (FLAGS.can_owner || isBooksDoor())) { var ac = el('span', 'acts'); ac.appendChild(btn('Void', 'ghost small danger', function () { openVoid(V.id, a); })); row.appendChild(ac); }
      pl.appendChild(row);
    });
    var PF = { cash: 'Cash from the safe', petty: 'Petty cash', bank: 'Bank transfer or SINPE', payout: 'Money taken from the register', card_debit: 'Debit card', card_credit: 'Credit card' };
    (M.other_payments || []).forEach(function (p) {
      var row = el('div', 'orow');
      row.innerHTML = '<span class="t mono">' + esc(fmtC(p.amount_crc)) + '</span><span class="d"><span>' + esc(fmtD(p.date)) + '</span> · <span>' + esc(PF[p.paid_from] || p.paid_from) + '</span>' + (p.reference ? ' · ' + nt(p.reference) : '') +
        ' · <span class="hint">' + esc('recorded in Accounting') + '</span>' + (p.voided_at ? ' · <span class="pill mute">' + esc('voided') + '</span>' : '') + '</span>';
      pl.appendChild(row);
    });
    if (!(M.advances || []).length && !(M.other_payments || []).length) pl.appendChild(el('p', 'empty', esc('No payments yet.')));
    body.appendChild(pl);
  }
  function renderProductos(body, F, itemId) {
    var V = F.vendor, ps = (F.products || []).slice().sort(function (a, b) { return (a.active === b.active ? 0 : a.active ? -1 : 1) || norm(pname(a)).localeCompare(norm(pname(b))); });
    var tools = el('div', 'tools');
    if (FLAGS.can_manage) tools.appendChild(btn('Add product', 'small', function () { productForm($('prNewBox'), V.id, {}); }, { id: 'prAdd' }));
    body.appendChild(tools);
    var nb = el('div'); nb.id = 'prNewBox'; body.appendChild(nb);
    var t = el('table', 'rt'); t.id = 'prTable';
    t.innerHTML = '<thead><tr><th>' + esc('Product') + '</th><th>' + esc('Presentation') + '</th><th class="num">' + esc('Usual price') + '</th><th class="num">' + esc('On hand') + '</th><th></th></tr></thead>';
    var tb = document.createElement('tbody');
    ps.forEach(function (p) {
      var tr = document.createElement('tr'); tr.setAttribute('data-vi', p.id);
      if (itemId && p.item_id === itemId) tr.className = 'pinline';
      var pref = p.preferred ? '<span class="pill ok">' + esc('Preferred') + '</span>' : p.preferred_vendor_name ? '<span class="hint">' + esc('Preferred:') + ' ' + nt(p.preferred_vendor_name) + '</span>' : '';
      tr.innerHTML = '<td><span class="lbl">' + esc('Product') + '</span><b>' + nt(pname(p)) + '</b>' + (p.label && p.item_name && p.label !== p.item_name ? '<span class="sub">' + esc('Inventory:') + ' ' + nt(p.item_name) + '</span>' : '') +
        (p.vendor_code ? '<span class="sub">' + esc('code') + ' ' + nt(p.vendor_code) + '</span>' : '') + '<span class="sub">' + pref + (p.active ? '' : ' <span class="pill mute">' + esc('retired') + '</span>') + '</span></td>' +
        '<td><span class="lbl">' + esc('Presentation') + '</span>' + '<span>1 </span>' + (p.pack_label ? nt(p.pack_label) : '<span>' + esc('presentation') + '</span>') + ' = <span>' + esc(qtyU(p.pack_qty, p.unit)) + '</span>' +
        (p.usual_qty ? '<span class="sub">' + esc('usually ' + num(p.usual_qty)) + '</span>' : '') + '</td>' +
        '<td class="num"><span class="lbl">' + esc('Usual price') + '</span>' + (p.usual_price != null ? esc(fmtC(p.usual_price)) + '<span class="sub">' + esc('without IVA') + '</span>' : '—') + '</td>' +
        '<td class="num"><span class="lbl">' + esc('On hand') + '</span>' + esc(qtyU(p.on_hand, p.unit)) + (p.stock_status && p.stock_status !== 'ok' ? '<span class="sub"><span class="pill ' + esc(p.stock_status) + '">' + esc(p.stock_status === 'out' ? 'Out of stock' : 'Low') + '</span></span>' : '') + '</td>';
      var td = document.createElement('td'); var a = el('div', 'btns'); a.style.marginTop = '0';
      if (FLAGS.can_manage) {
        a.appendChild(btn('Edit', 'ghost small', function () { editProduct(tr, p); }));
        if (p.active && !p.preferred) a.appendChild(btn('Make preferred', 'ghost small', function () { saveProduct({ id: p.id, preferred: true }, 'Preferred supplier saved'); }));
        a.appendChild(btn(p.active ? 'Retire' : 'Reactivate', 'ghost small' + (p.active ? ' danger' : ''), function () {
          if (p.active && !confirm('Retire ' + pname(p) + ' from this supplier? Its history stays.')) return;
          saveProduct({ id: p.id, active: !p.active }, p.active ? 'Product retired' : 'Product reactivated');
        }));
      }
      td.appendChild(a); tr.appendChild(td); tb.appendChild(tr);
    });
    t.appendChild(tb);
    if (!ps.length) body.appendChild(el('p', 'empty', esc('This supplier has no products yet.')));
    else body.appendChild(t);
    if (itemId) setTimeout(function () { var r = t.querySelector('tr.pinline'); if (r) try { r.scrollIntoView({ block: 'center' }); } catch (e) {} }, 50);
    if (PENDING_NEW && PENDING_NEW.vendor === V.id && FLAGS.can_manage) {
      var pn = PENDING_NEW; PENDING_NEW = null;
      productForm(nb, V.id, { item_id: pn.item_id, item_name: pn.name, unit: pn.unit, preferred: pn.preferred });
    }
  }
  async function saveProduct(p, msg) {
    var r = await rpc('proveedor_producto_guardar', { p_item: p });
    if (!r.ok) { if (!r.handled) toast(errText(r)); return r; }
    toast(msg || 'Product saved'); reloadFicha();
    return r;
  }
  function editProduct(tr, p) {
    if (tr.nextSibling && tr.nextSibling.classList && tr.nextSibling.classList.contains('editrow')) { tr.nextSibling.remove(); formClosed(); return; }
    var er = document.createElement('tr'); er.className = 'editrow';
    var td = document.createElement('td'); td.colSpan = 5;
    var f = el('form', 'inline form'); f.id = 'prodEdit'; f.setAttribute('autocomplete', 'off');
    var v = function (x) { return esc(x == null ? '' : plainNum(x) || x); };
    f.innerHTML = '<div class="row"><div><label class="f" for="peLabel">' + esc('Name at this supplier (optional)') + '</label><input id="peLabel" maxlength="80" value="' + esc(p.label || '') + '"></div>' +
      '<div><label class="f" for="peCode">' + esc('Supplier code (optional)') + '</label><input id="peCode" maxlength="40" value="' + esc(p.vendor_code || '') + '"></div></div>' +
      '<div class="row"><div><label class="f" for="pePack">' + esc('Presentation') + '</label><input id="pePack" maxlength="60" value="' + esc(p.pack_label || '') + '"></div>' +
      '<div><label class="f" for="peQty">' + esc(p.unit === 'unit' ? 'Units per presentation' : 'Quantity per presentation (' + unitWord(p.unit, 2) + ')') + '</label><input id="peQty" type="text" inputmode="decimal" data-keypad="qty" value="' + v(p.pack_qty) + '"></div></div>' +
      '<div class="row"><div><label class="f" for="pePrice">' + esc('Usual price per presentation, without IVA (₡)') + '</label><input id="pePrice" type="text" inputmode="decimal" data-keypad="qty" value="' + v(p.usual_price) + '"></div>' +
      '<div><label class="f" for="peUsual">' + esc('Usual quantity (optional)') + '</label><input id="peUsual" type="text" inputmode="decimal" data-keypad="qty" value="' + v(p.usual_qty) + '"></div></div>' +
      '<p class="err" id="peErr" role="alert"></p><div class="btns"><button type="button" class="ghost" id="peCancel">Cancel</button><button type="submit" id="peGo">Save</button></div>';
    td.appendChild(f); er.appendChild(td); tr.parentNode.insertBefore(er, tr.nextSibling);
    formOpened('prodEdit', [p.id], f);
    $('peLabel').focus();
    $('peCancel').addEventListener('click', function () { er.remove(); formClosed(f); });
    f.addEventListener('submit', async function (e) {
      e.preventDefault();
      var o = { id: p.id }, E = $('peErr');
      var lab = $('peLabel').value.trim(), code = $('peCode').value.trim(), pack = $('pePack').value.trim();
      if (lab !== (p.label || '')) o.label = lab || null;
      if (code !== (p.vendor_code || '')) o.vendor_code = code || null;
      if (pack !== (p.pack_label || '')) o.pack_label = pack || null;
      var q = parseNum($('peQty').value); if (!(q > 0 && q < 1e9)) { E.textContent = 'Type how much one presentation holds.'; return; }
      if (Math.abs(q - Number(p.pack_qty)) > 1e-9) o.pack_qty = q;
      var pr = $('pePrice').value.trim() === '' ? null : parseNum($('pePrice').value);
      if (pr !== null && !(pr >= 0 && pr <= 100000000)) { E.textContent = ERR.bad_price; return; }
      if ((pr === null) !== (p.usual_price == null) || (pr !== null && Math.abs(pr - Number(p.usual_price)) >= 0.005)) o.usual_price = pr;
      var uq = $('peUsual').value.trim() === '' ? null : parseNum($('peUsual').value);
      if (uq !== null && !(uq > 0 && uq <= 100000)) { E.textContent = 'Check the usual quantity.'; return; }
      if ((uq === null) !== (p.usual_qty == null) || (uq !== null && Math.abs(uq - Number(p.usual_qty)) > 1e-9)) o.usual_qty = uq;
      if (Object.keys(o).length === 1) { er.remove(); formClosed(f); return; }
      $('peGo').disabled = true;
      var r = await rpc('proveedor_producto_guardar', { p_item: o });
      $('peGo').disabled = false;
      if (!r.ok) { if (!r.handled) E.textContent = errText(r); return; }
      formClosed(f); toast('Product saved'); reloadFicha('productos');
    });
  }

  /* ---------- 12) payments: SINPE (confirmation number required) or card (reference optional) ----------
     proveedor_pago_registrar: the request id is kept until the answer; the PIN of who registers (owner or manager), not for
     the owner with the phone code nor the accountant; over_balance shows the balance, and the owner level may record it
     as a payment in favour with a reason; duplicate_reference / possible_duplicate ask before anything is sent again */
  var PAY = null;
  FORMS.pay = async function (vid, poId, opts) {
    await openPay(vid, poId, opts && opts.req);
    if (PAY && opts && opts.extra) { PAY.method = opts.extra.method === 'card' ? 'card' : 'sinpe'; PAY.card = opts.extra.card === 'card_credit' ? 'card_credit' : 'card_debit'; paintPayMethod(); }
  };
  async function openPay(vid, poId, req) {
    /* the supplier's money as it is now: read again (a delivery or a payment on another device is not in an older copy) */
    var fr = await loadFicha(vid, true); if (!fr.ok) { if (!fr.handled) toast(errText(fr)); return; } FICHA = fr;
    var F = FICHA, M = F.money || {};
    PAY = { vendor: vid, req: req || uuid(), method: 'sinpe', card: 'card_debit', excess: false, dup_ok: false };
    var sel = $('payPo'); sel.innerHTML = '';
    var o0 = document.createElement('option'); o0.value = ''; o0.textContent = 'No order (on account)'; sel.appendChild(o0);
    (F.orders || []).filter(function (o) { return o.status !== 'cancelled'; }).forEach(function (o) {
      var op = document.createElement('option'); op.value = o.id;
      var left = leftToPay(o.money);
      op.textContent = 'Order Nº ' + o.po_number + ' · ' + (ST_TXT[o.status] || o.status) + (left > 0.5 ? ' · owes ' + fmtC(left) : '');
      sel.appendChild(op);
    });
    sel.value = poId || '';
    $('payIntro').innerHTML = nt(F.vendor.name) + (F.vendor.sinpe ? ' · <span>SINPE</span> <b class="mono">' + nt(F.vendor.sinpe) + '</b>' : '');
    $('payDate').value = todayIso(); $('payDate').max = todayIso(); $('payDate').min = addDays(todayIso(), -366);
    $('payRef').value = ''; $('payRefC').value = ''; $('payErr').textContent = ''; $('payExcess').checked = false; $('payExcessWhy').value = ''; $('payExcessBox').hidden = true;
    paySaldo(); paintPayMethod();
    var pinNeeded = !noPinNeeded();
    $('payPinBox').hidden = !pinNeeded;
    if (pinNeeded) fillWho($('payWho'), await staffList(), false);
    $('payPin').value = '';
    openModal('payModal', 'payAmt');
    formOpened('pay', [vid, poId || null], $('payForm'), PAY.req);
  }
  /* what is left to pay: the server's saldo (with the IVA allowance before the invoice); an older server: due − paid */
  function leftToPay(m) { return !m ? 0 : m.saldo != null ? Math.max(0, Number(m.saldo) || 0) : Math.max(0, Number(m.due) - Number(m.paid)); }
  /* «to pay»: before the invoice the estimate with the IVA allowance, labelled; else what is due */
  function toPay(m) { var d = Number(m && m.due) || 0, di = Number(m && m.due_iva); return m && m.due_iva != null && di - d > 0.5 ? { v: di, est: true } : { v: d, est: false }; }
  function paySaldo() {
    var F = FICHA, po = $('payPo').value, M = F.money || {}, s;
    if (po) { var o = (F.orders || []).filter(function (x) { return x.id === po; })[0]; s = o ? leftToPay(o.money) : 0; }
    else s = M.saldo != null ? Math.max(0, Number(M.saldo) || 0) : Number(M.owed_crc) || 0;
    $('payAmt').value = s > 0 ? plainNum(round(s, 2)) : '';
    $('paySaldo').textContent = s > 0 ? (po ? 'Balance: ' : 'Balance of all orders: ') + fmtC(s) : 'Nothing owed right now: the payment stays in favour.';
  }
  $('payPo').addEventListener('change', function () { paySaldo(); PAY.dup_ok = false; });
  function paintPayMethod() {
    document.querySelectorAll('#payMethod button').forEach(function (b) { b.setAttribute('aria-pressed', String(b.getAttribute('data-m') === PAY.method)); });
    document.querySelectorAll('#payCardKind button').forEach(function (b) { b.setAttribute('aria-pressed', String(b.getAttribute('data-k') === PAY.card)); });
    $('payCardKind').hidden = PAY.method !== 'card';
    $('payRefSinpe').hidden = PAY.method !== 'sinpe'; $('payRefCard').hidden = PAY.method !== 'card';
  }
  $('payMethod').addEventListener('click', function (e) { var b = e.target.closest('button'); if (!b || !PAY) return; PAY.method = b.getAttribute('data-m'); PAY.dup_ok = false; paintPayMethod(); });
  $('payCardKind').addEventListener('click', function (e) { var b = e.target.closest('button'); if (!b || !PAY) return; PAY.card = b.getAttribute('data-k'); paintPayMethod(); });
  $('payCancel').addEventListener('click', function () { closeModal('payModal'); });
  var payBusy = false;
  $('payForm').addEventListener('submit', async function (e) {
    e.preventDefault();
    if (!PAY || payBusy) return;
    var E = $('payErr'); E.textContent = '';
    var amt = parseNum($('payAmt').value);
    if (!(amt > 0 && amt <= 100000000 && decimals(amt) <= 2)) { E.textContent = ERR.bad_amount; $('payAmt').focus(); return; }
    var date = $('payDate').value || todayIso();
    if (date > todayIso()) { E.textContent = ERR.future_date; return; }
    var ref = (PAY.method === 'sinpe' ? $('payRef').value : $('payRefC').value).trim().replace(/\s+/g, ' ');
    if (PAY.method === 'sinpe') {
      if (!ref) { E.textContent = ERR.needs_reference; $('payRef').focus(); return; }
      if (!/^[A-Za-z0-9][A-Za-z0-9 .\/-]{3,39}$/.test(ref)) { E.textContent = ERR.bad_reference; $('payRef').focus(); return; }
    }
    var excess = !$('payExcessBox').hidden && $('payExcess').checked, why = $('payExcessWhy').value.trim();
    if (excess && why.length < 5) { E.textContent = ERR.needs_reason; $('payExcessWhy').focus(); return; }
    var pinNeeded = !$('payPinBox').hidden, pin = $('payPin').value.trim(), who = $('payWho').value || null;
    if (pinNeeded && (!who || !pin)) { E.textContent = 'Pick who registers it and type their PIN.'; $('payPin').focus(); return; }
    var p = { vendor_id: PAY.vendor, po_id: $('payPo').value || null, date: date, amount: amt, method: PAY.method === 'sinpe' ? 'sinpe' : PAY.card, reference: ref || null };
    if (excess) { p.excess_ok = true; p.excess_reason = why; }
    if (PAY.dup_ok) p.duplicate_ok = true;
    payBusy = true; $('payGo').disabled = true; $('payGo').textContent = 'Saving…';
    var args = { p_payment: p, p_request_id: PAY.req };
    if (pinNeeded) { args.p_staff_id = who; args.p_pin = pin; }
    var r = await rpc('proveedor_pago_registrar', args);
    $('payPin').value = ''; payBusy = false; $('payGo').disabled = false; $('payGo').textContent = 'Save payment';
    if (r.ok) {
      var vid = PAY.vendor, po = p.po_id; PAY = null; closeModal('payModal'); forgetFicha(vid);
      /* «in favour» only when the supplier really holds money of ours beyond what is owed (an order paid ahead waits) */
      var cr = r.money ? Number(r.money.credit != null ? r.money.credit : r.money.credit_crc) || 0 : 0;
      toast(r.repeat ? 'That payment was already saved' : 'Payment saved' + (cr > 0.5 ? ' · ' + fmtC(cr) + ' in favour' : Number(r.unapplied_crc) > 0.005 ? ' · it waits for the invoice' : ''));
      var o = po && FICHA ? (FICHA.orders || []).filter(function (x) { return x.id === po; })[0] : null;
      if (o && FICHA && (FICHA.money.uninvoiced || []).some(function (u) { return u.po_id === po; })) AFTER_PAY = po;
      route();
      return;
    }
    if (r.handled) return;
    if (r.error === 'over_balance') {
      E.innerHTML = '<span>' + esc('That is more than what is owed: the balance is ' + fmtC(r.saldo) + '.') + '</span>';
      if (FLAGS.can_owner || noPinNeeded()) { $('payExcessBox').hidden = false; }
      else E.innerHTML += ' <span>' + esc('Only the owner can register a payment above the balance.') + '</span>';
      return;
    }
    if (r.error === 'duplicate_reference') { E.textContent = 'That SINPE number is already registered (' + [r.vendor_name, r.date ? fmtD(r.date) : '', r.amount != null ? fmtC(r.amount) : ''].filter(Boolean).join(', ') + ').'; $('payRef').focus(); return; }
    if (r.error === 'possible_duplicate') {
      E.innerHTML = '<span>' + esc(ERR.possible_duplicate) + '</span> <span>' + esc('Is it a different payment?') + '</span> ';
      E.appendChild(btn('Yes, it is another payment', 'small', function () { PAY.dup_ok = true; E.textContent = 'Type the PIN again and save.'; if (!$('payPinBox').hidden) $('payPin').focus(); else $('payForm').requestSubmit(); }));
      return;
    }
    E.textContent = errText(r);
  });
  var AFTER_PAY = null;   /* «Registrar factura (S/N si no trae)» after a payment on an order with deliveries without invoice */

  /* void a Proveedores payment: the books door without PIN, or an owner with an owner's PIN */
  var VOID = null;
  function openVoid(vid, a) {
    VOID = { vendor: vid, id: a.id };
    $('voidIntro').textContent = fmtC(a.amount_crc) + ' · ' + fmtD(a.date) + (a.reference ? ' · ' + a.reference : '');
    $('voidWhy').value = ''; $('voidErr').textContent = ''; $('voidPin').value = '';
    var pinNeeded = !noPinNeeded();
    $('voidPinBox').hidden = !pinNeeded;
    (pinNeeded ? staffList() : Promise.resolve([])).then(function (l) { if (pinNeeded) fillWho($('voidWho'), l, true); });
    openModal('voidModal', 'voidWhy');
  }
  $('voidCancel').addEventListener('click', function () { closeModal('voidModal'); });
  $('voidForm').addEventListener('submit', async function (e) {
    e.preventDefault();
    if (!VOID) return;
    var E = $('voidErr'), why = $('voidWhy').value.trim();
    if (why.length < 5) { E.textContent = ERR.needs_reason; $('voidWhy').focus(); return; }
    var args = { p_id: VOID.id, p_reason: why };
    if (!$('voidPinBox').hidden) { var pin = $('voidPin').value.trim(); if (!$('voidWho').value || !pin) { E.textContent = 'Pick the owner and type the PIN.'; return; } args.p_staff_id = $('voidWho').value; args.p_pin = pin; }
    $('voidGo').disabled = true;
    var r = await rpc('proveedor_pago_anular', args);
    $('voidPin').value = ''; $('voidGo').disabled = false;
    if (!r.ok) { if (!r.handled) E.textContent = errText(r); return; }
    var vid = VOID.vendor; VOID = null; closeModal('voidModal'); forgetFicha(vid); toast('Payment voided'); route();
  });
  async function voidInvoice(vid, inv) {
    var why = prompt('Why is this invoice voided?');
    if (!why) return;
    if (why.trim().length < 5) { toast(ERR.needs_reason); return; }
    var r = await rpc('proveedor_factura_anular', { p_invoice_id: inv.id, p_reason: why.trim() });
    if (!r.ok) { if (!r.handled) toast(errText(r)); return; }
    forgetFicha(vid); toast('Invoice voided'); route();
  }

  /* ---------- 13) the supplier invoice: tick deliveries, number (optional), date, subtotal, IVA (the person chooses) ---------- */
  var INV = null;
  FORMS.invoice = async function (vid, poId, opts) { await openInvoice(vid, poId, opts && opts.req); };
  async function openInvoice(vid, poId, req) {
    /* the deliveries without invoice as they are now: read again (one received on another device is not in an older copy) */
    var fr = await loadFicha(vid, true); if (!fr.ok) { if (!fr.handled) toast(errText(fr)); return; } FICHA = fr;
    var U = invRows((FICHA.money && FICHA.money.uninvoiced) || []);
    INV = { vendor: vid, req: req || uuid(), autoNum: '', autoNet: '' };
    var box = $('invRecs'); box.innerHTML = '';
    if (!U.length) box.appendChild(el('p', 'empty', esc('Every delivery of this supplier already has its invoice.')));
    U.forEach(function (u) {
      var l = el('label', 'checkline');
      var tick = poId ? u.po_id === poId : U.length === 1;
      /* a Proveedores correction goes with the delivery it corrects (the server invoices them together): shown inside it */
      var fixed = u.fixes.length ? ' · <span>' + esc('corrected') + '</span> <span class="mono">' + esc(fmtC(u.fix_crc)) + '</span> → <span class="mono">' + esc(fmtC(u.net_crc)) + '</span>' : '';
      l.innerHTML = '<input type="checkbox" id="invR-' + esc(u.receipt_id) + '" data-rec="' + esc(u.receipt_id) + '"' + (tick ? ' checked' : '') + '> <span><span>' + esc('Order Nº ' + (u.po_number || '')) + '</span> · <span>' + esc(fmtD(u.received_at)) + '</span> · <span class="mono">' + esc(fmtC(u.total_crc)) + '</span>' + fixed +
        (u.invoice_no ? ' · <span>' + esc('invoice') + '</span> ' + nt(u.invoice_no) : '') + (u.invoice_status === 'review' ? ' · <span class="pill gold">' + esc('to review') + '</span>' : '') + '</span>';
      box.appendChild(l);
    });
    $('invNum').value = ''; $('invNet').value = '';
    $('invDate').value = todayIso(); $('invDate').max = todayIso(); $('invDue').value = ''; $('invCur').value = 'CRC'; invCurNow = 'CRC'; $('invFx').value = ''; $('invFxBox').hidden = true;
    $('invIva').value = ''; $('invErr').textContent = '';
    invPrefill();
    openModal('invModal');
    formOpened('invoice', [vid, poId || null], $('invForm'), INV.req);
  }
  /* the deliveries waiting for their invoice, each with its Proveedores corrections (corrections of corrections too);
     a correction whose delivery is not in the list (already invoiced elsewhere) stands on its own */
  function invRows(list) {
    var by = {}, rows = [], at = {};
    list.forEach(function (u) { by[u.receipt_id] = u; });
    function root(u) { var r = u, n = 0; while (r.corrects && by[r.corrects] && n++ < 50) r = by[r.corrects]; return r; }
    list.forEach(function (u) {
      var r = root(u);
      if (!at[r.receipt_id]) { at[r.receipt_id] = Object.assign({}, r, { fixes: [], fix_crc: 0, net_crc: Number(r.total_crc) || 0 }); rows.push(at[r.receipt_id]); }
      if (r !== u) { var w = at[r.receipt_id]; w.fixes.push(u); w.fix_crc = round(w.fix_crc + (Number(u.total_crc) || 0), 2); w.net_crc = round(w.net_crc + (Number(u.total_crc) || 0), 2); }
    });
    return rows;
  }
  function invTicked() {
    var ids = Array.prototype.map.call(document.querySelectorAll('#invRecs [data-rec]:checked'), function (i) { return i.getAttribute('data-rec'); });
    var U = invRows((FICHA && FICHA.money && FICHA.money.uninvoiced) || []);
    return U.filter(function (u) { return ids.indexOf(u.receipt_id) > -1; });
  }
  function invPayoutPaint() {
    var payout = invTicked().reduce(function (s, u) { return s + (Number(u.payout_crc) || 0); }, 0);
    $('invPayout').textContent = payout > 0 ? 'Register cash paid ' + fmtC(payout) : '';
  }
  /* the number and the subtotal follow the ticked deliveries only while they still hold what the page itself filled in:
     a number or an amount the person typed is never overwritten (the delivery ticked after it, the currency switched) */
  function invPrefill() {
    var T = invTicked(), net = 0, nos = {};
    T.forEach(function (u) {
      var d = u.invoice_draft || null, dn = d ? Number(d.net != null ? d.net : d.net_crc != null ? d.net_crc : d.subtotal) : NaN;
      net += (u.invoice_status === 'review' && isFinite(dn) && dn > 0 ? dn : Number(u.total_crc) || 0) + (Number(u.fix_crc) || 0);
      if (u.invoice_no) nos[u.invoice_no] = 1;
    });
    var keys = Object.keys(nos), num = keys.length === 1 ? keys[0] : '';
    if (INV && ($('invNum').value.trim() === '' || $('invNum').value === INV.autoNum)) { $('invNum').value = num; INV.autoNum = num; }
    /* the received value is in colones: in dollars the subtotal is the one the person types, never ₡ read as $ */
    var nv = T.length ? plainNum(round(net, 2)) : '';
    if (INV && $('invCur').value !== 'USD' && ($('invNet').value.trim() === '' || $('invNet').value === INV.autoNet)) { $('invNet').value = nv; INV.autoNet = nv; }
    invPayoutPaint();
    invTotal();
  }
  function invTotal() {
    var n = parseNum($('invNet').value), i = $('invIva').value.trim() === '' ? NaN : parseNum($('invIva').value), cur = $('invCur').value;
    var t = (n >= 0 ? n : 0) + (i >= 0 ? i : 0);
    var fx = cur === 'USD' ? parseNum($('invFx').value) : NaN;
    $('invTotal').textContent = n >= 0 ? 'Total ' + (cur === 'USD' ? '$' + round(t, 2).toFixed(2) + (fx >= 100 && fx <= 2000 ? ' = ' + fmtC(round(round(n, 2) * fx, 2) + (i >= 0 ? round(round(i, 2) * fx, 2) : 0)) : '') : fmtC(t)) + (i >= 0 ? '' : ' · choose the IVA') : '';
  }
  $('invRecs').addEventListener('change', function () { invPrefill(); });
  $('invRecs').addEventListener('input', invPayoutPaint);   /* a form brought back ticks its deliveries with «input» only */
  ['invNet', 'invIva', 'invFx'].forEach(function (id) { $(id).addEventListener('input', invTotal); });
  $('invIva13').addEventListener('click', function () { var n = parseNum($('invNet').value); if (n >= 0) { $('invIva').value = plainNum(round(n * 0.13, 2)); invTotal(); } });
  $('invIva0').addEventListener('click', function () { $('invIva').value = '0'; invTotal(); });
  /* the prefilled subtotal is the received value in colones: in dollars the person types the invoice's own amounts
     (never ₡18 000 read as $18 000); back in colones the prefill returns */
  /* only a real switch acts: a form brought back (resume) fires «change» with the same currency and keeps what was typed */
  var invCurNow = 'CRC';
  $('invCur').addEventListener('change', function () {
    var cur = $('invCur').value; if (cur === invCurNow) return;
    invCurNow = cur;
    var usd = cur === 'USD';
    $('invFxBox').hidden = !usd;
    $('invIva').value = '';
    /* an amount typed in one currency means nothing in the other: the subtotal starts again (the number typed stays) */
    $('invNet').value = '';
    if (usd) invTotal(); else invPrefill();
  });
  $('invCancel').addEventListener('click', function () { closeModal('invModal'); });
  var invBusy = false;
  $('invForm').addEventListener('submit', async function (e) {
    e.preventDefault();
    if (!INV || invBusy) return;
    var E = $('invErr'); E.textContent = '';
    var T = invTicked();
    if (!T.length) { E.textContent = ERR.bad_receipts; return; }
    var net = parseNum($('invNet').value), iva = $('invIva').value.trim() === '' ? NaN : parseNum($('invIva').value), cur = $('invCur').value;
    if (!(net >= 0 && net <= 100000000)) { E.textContent = ERR.bad_amount; $('invNet').focus(); return; }
    if (!(iva >= 0 && iva <= 100000000)) { E.textContent = 'Choose the IVA: 13 %, no IVA, or type it.'; $('invIva').focus(); return; }
    var inv = { number: $('invNum').value.trim() || null, date: $('invDate').value || todayIso(), due_date: $('invDue').value || null, currency: cur, net: net, iva: iva };
    if (inv.date > todayIso()) { E.textContent = ERR.future_date; return; }
    if (cur === 'USD') { var fx = parseNum($('invFx').value); if (!(fx >= 100 && fx <= 2000)) { E.textContent = ERR.bad_rate; $('invFx').focus(); return; } inv.fx_rate = fx; }
    invBusy = true; $('invGo').disabled = true;
    var r = await rpc('proveedor_factura_registrar', { p_vendor_id: INV.vendor, p_receipt_ids: T.map(function (u) { return u.receipt_id; }), p_invoice: inv, p_request_id: INV.req });
    invBusy = false; $('invGo').disabled = false;
    if (!r.ok) { if (!r.handled) E.textContent = errText(r); return; }
    var vid = INV.vendor; INV = null; closeModal('invModal'); forgetFicha(vid);
    toast(r.repeat ? 'That invoice was already saved' : 'Invoice saved · ' + fmtC(r.total_crc) + (Number(r.applied_crc) > 0.005 ? ' · paid ' + fmtC(r.applied_crc) : '') + (Number(r.open_crc) > 0.005 ? ' · open ' + fmtC(r.open_crc) : ''));
    route();
  });

  /* ---------- 14) the order document (#pedido=): Copy | PDF | Print, then the actions ---------- */
  var ORDER = null;
  async function viewPedido(gen, poId, notice) {
    if (!isUuid(poId)) { go('#'); return; }
    if (!ORDER || ORDER.order.id !== poId) main.innerHTML = '<p class="loading">Loading…</p>';
    var r = await rpc('proveedor_pedido', { p_po_id: poId });
    if (stale(gen)) return;
    if (!r.ok) return loadErr(gen, r);
    setFlags(r);
    ORDER = r;
    var O = r.order, lines = (r.lines || []).slice().sort(function (a, b) { return (Number(a.pos) || 999) - (Number(b.pos) || 999); });
    var live = lines.filter(function (l) { return !l.removed; });
    var anyRecv = (r.receipts || []).length > 0 || live.some(function (l) { return Number(l.received_packs) > 0; });
    var open = /^(draft|sent|partially_received)$/.test(O.status);
    main.innerHTML = '';
    main.appendChild(crumbs([{ href: '#', text: 'Suppliers' }].concat(O.vendor_id ? [{ href: '#p=' + encodeURIComponent(O.vendor_id) + '&t=pedidos', html: nt(O.vendor_name) }] : []).concat([{ text: 'Order Nº ' + (O.po_number || '') }])));
    if (notice) { var nn = el('p', 'note'); nn.textContent = notice; main.appendChild(nn); }
    var c = el('section', 'card'); c.id = 'orderDoc';
    var d = el('div', 'doc');
    var dh = el('div', 'dh');
    dh.innerHTML = '<h2>' + esc('Order Nº ' + (O.po_number || '')) + '</h2>' + statusPill(O.status) + payPill(r.money);
    d.appendChild(dh);
    d.appendChild(el('div', 'hint', (O.vendor_name ? '<span>' + esc('Supplier:') + '</span> <b>' + nt(O.vendor_name) + '</b>' : '<span class="pill gold">' + esc('No supplier') + '</span>') +
      ' · <span>' + esc(fmtDY(O.created_at)) + '</span>' + (O.expected_on ? ' · <span>' + esc('expected ' + fmtD(O.expected_on)) + '</span>' : '') + (O.by_name ? ' · <span>' + esc('by') + '</span> ' + nt(O.by_name) : '')));
    var closeReq = (r.receipts || []).filter(function (x) { return x.close_requested; }).slice(-1)[0];
    if ((O.close_requested || closeReq) && O.status === 'partially_received') {
      var cr = el('div', 'note'); cr.innerHTML = '<span>' + nt(closeReq ? (closeReq.by_name || '').replace(/ \(en turno\)$/, '') : '') + ' ' + esc('said the rest is not coming') + '</span>';
      if (FLAGS.can_manage) { var cb = el('div', 'btns'); cb.appendChild(btn('Close what is pending', 'small', closePending)); cr.appendChild(cb); }
      d.appendChild(cr);
    }
    /* Copy | PDF | Print */
    var da = el('div', 'docacts'); var pr = el('div', 'primary');
    pr.appendChild(btn('Copy', '', copyOrder, { id: 'docCopy' }));
    pr.appendChild(btn('PDF', '', pdfOrder, { id: 'docPdf' }));
    pr.appendChild(btn('Print', '', printOrder, { id: 'docPrint' }));
    da.appendChild(pr);
    var lp = el('label', 'checkline'); lp.innerHTML = '<input type="checkbox" id="docPrices" checked> <span>Include prices</span>'; lp.style.marginTop = '0';
    da.appendChild(lp);
    d.appendChild(da);
    /* the lines */
    var t = el('table', 'rt'); t.id = 'docLines';
    t.innerHTML = '<thead><tr><th>' + esc('Product') + '</th><th>' + esc('Presentation') + '</th><th class="num">' + esc('Quantity') + '</th><th class="num">' + esc('Usual price') + '</th><th class="num">' + esc('Subtotal') + '</th>' +
      (anyRecv ? '<th class="num">' + esc('Received') + '</th><th class="num">' + esc(O.status === 'received' ? 'Did not arrive' : 'Pending') + '</th>' : '') + '</tr></thead>';
    var tb = document.createElement('tbody');
    live.forEach(function (l) {
      var tr = document.createElement('tr'); tr.setAttribute('data-line', l.id);
      var miss = Number(l.pending_packs) > 0.0005;
      if (O.status === 'received' && miss) tr.className = 'miss';
      tr.innerHTML = '<td><span class="lbl">' + esc('Product') + '</span><b>' + nt(pname(l)) + '</b>' + (l.vendor_code ? '<span class="sub">' + esc('code') + ' ' + nt(l.vendor_code) + '</span>' : '') + '</td>' +
        '<td><span class="lbl">' + esc('Presentation') + '</span>' + presHtml(l) + '</td>' +
        '<td class="num"><span class="lbl">' + esc('Quantity') + '</span>' + esc(num(l.packs)) + '</td>' +
        '<td class="num"><span class="lbl">' + esc('Usual price') + '</span>' + (l.expected_pack_price != null ? esc(fmtC(l.expected_pack_price)) : '—') + '</td>' +
        '<td class="num"><span class="lbl">' + esc('Subtotal') + '</span>' + (l.line_total_est != null ? esc(fmtC(l.line_total_est)) : '—') + '</td>' +
        (anyRecv ? '<td class="num"><span class="lbl">' + esc('Received') + '</span>' + esc(num(l.received_packs)) + '</td><td class="num"><span class="lbl">' + esc(O.status === 'received' ? 'Did not arrive' : 'Pending') + '</span>' + (miss ? esc(num(l.pending_packs)) : '—') + '</td>' : '');
      tb.appendChild(tr);
    });
    t.appendChild(tb);
    d.appendChild(t);
    if (!live.length) d.appendChild(el('p', 'empty', esc('No lines yet')));
    var tt = r.totals || {};
    d.appendChild(el('div', 'tot', '<span><span>' + esc('Estimated total') + '</span> <b>' + esc(fmtC(tt.estimated)) + '</b> <span class="hint">' + esc('without IVA') + '</span></span>' +
      (anyRecv ? '<span><span>' + esc('Received') + '</span> <b>' + esc(fmtC(tt.received_value)) + '</b></span>' : '')));
    if (O.note) { var np = el('p', '', '<span>' + esc('Note:') + '</span> ' + nt(O.note)); np.style.whiteSpace = 'pre-wrap'; d.appendChild(np); }
    c.appendChild(d);
    /* the actions */
    var acts = el('div', 'btns'); acts.id = 'docActs';
    if (open && FLAGS.can_manage) acts.appendChild(link('Receive', '#recibir=' + O.id, 'btnlink solid'));
    if (FLAGS.can_manage) {
      if (O.status === 'draft') acts.appendChild(btn('Confirm the order', 'ghost', confirmOrder));
      acts.appendChild(btn('Edit', 'ghost', function () { editOrder(); }, { id: 'docEdit' }));
      if ((O.status === 'draft' || O.status === 'sent') && !anyRecv) acts.appendChild(btn('Cancel order', 'ghost danger', cancelOrder));
      if (O.status === 'partially_received') acts.appendChild(btn('Close what is pending', 'ghost', closePending));
      if ((r.receipts || []).some(function (x) { return x.origin !== 'correccion'; })) acts.appendChild(btn('Correct a delivery', 'ghost', function () { openFix(); }));
      if (O.vendor_id && O.status !== 'cancelled') acts.appendChild(btn('Duplicate', 'ghost', function () { duplicateOrder(O.vendor_id, O.id); }));
      if (!O.vendor_id) acts.appendChild(btn('Assign a supplier', 'ghost', function () { assignInline(acts, { id: O.id, version: O.version }, function () { route(); }); }));
    }
    if (FLAGS.can_pay && O.vendor_id) {
      var M = r.money || {};
      if ((r.receipts || []).some(function (x) { return x.invoice_status !== 'confirmed'; }) || (M.invoice_missing && anyRecv)) acts.appendChild(btn(AFTER_PAY === O.id ? 'Register the invoice (S/N if it has none)' : 'Register the invoice', AFTER_PAY === O.id ? '' : 'ghost', function () { openInvoice(O.vendor_id, O.id); }, { id: 'docInv' }));
      if (O.status !== 'cancelled') acts.appendChild(btn('Register a payment', 'ghost', function () { openPay(O.vendor_id, O.id); }, { id: 'docPay' }));
    }
    c.appendChild(acts);
    var edit = el('div'); edit.id = 'docEditBox'; c.appendChild(edit);
    main.appendChild(c);
    if (AFTER_PAY === O.id) { var ap = el('p', 'note'); ap.textContent = 'Payment saved. This order has deliveries without invoice: register it, with S/N if it has none.'; c.insertBefore(ap, acts); AFTER_PAY = null; }
    /* deliveries, payments, history (management) */
    var dc = el('section', 'card'); dc.appendChild(el('h2', '', esc('Deliveries')));
    if (!(r.receipts || []).length) dc.appendChild(el('p', 'empty', esc('Nothing received yet.')));
    (r.receipts || []).forEach(function (x) { dc.appendChild(receiptBox(x)); });
    main.appendChild(dc);
    var M2 = r.money || {};
    var mc = el('section', 'card'); mc.id = 'docMoney'; mc.appendChild(el('h2', '', esc('Payment') + ' ' + payPill(M2)));
    var tp2 = toPay(M2);
    mc.appendChild(el('p', '', '<span>' + esc('To pay') + '</span> <b class="mono">' + esc(fmtC(tp2.v)) + '</b>' + (tp2.est ? ' <span class="hint">' + esc('estimated, IVA incl.') + '</span>' : '') +
      ' · <span>' + esc('Paid') + '</span> <b class="mono">' + esc(fmtC(M2.paid)) + '</b>' + (Number(M2.credit) > 0.5 ? ' · <span>' + esc('In favour ' + fmtC(M2.credit)) + '</span>' : '')));
    if (M2.invoice_missing && anyRecv) mc.appendChild(el('p', 'hint', esc('The invoice is missing.')));
    if (Number(M2.payout_crc) > 0) mc.appendChild(el('p', 'hint', esc('Register cash paid ' + fmtC(M2.payout_crc) + ' · the invoice is missing')));
    var ml = el('ul', 'hist');
    (M2.invoices || []).forEach(function (i) {
      var tot = i.currency === 'USD' && i.total_fx != null && i.fx_rate != null ? 'total $' + round(i.total_fx, 2).toFixed(2) + ' at ' + fmtC(i.fx_rate) + ' = ' + fmtC(i.total_crc) : 'total ' + fmtC(i.total_crc);
      ml.appendChild(el('li', '', '<span>' + esc('Invoice') + '</span> ' + nt(i.number) + ' · <span>' + esc(fmtD(i.date)) + '</span> · <span>' + esc(tot) + '</span>' + (Number(i.open_crc) > 0.005 ? ' · <span>' + esc('open ' + fmtC(i.open_crc)) + '</span>' : '')));
    });
    (M2.advances || []).forEach(function (a) { ml.appendChild(el('li', '', '<span>' + esc('Payment') + '</span> <span class="mono">' + esc(fmtC(a.amount_crc)) + '</span> · <span>' + esc(fmtD(a.date)) + '</span>' + (a.reference ? ' · ' + nt(a.reference) : '') + (a.voided_at ? ' · <span class="pill mute">' + esc('voided') + '</span>' : ''))); });
    if (ml.childNodes.length) mc.appendChild(ml);
    main.appendChild(mc);
    if ((r.history || []).length) {
      var hc = el('section', 'card'); var det = document.createElement('details');
      det.innerHTML = '<summary class="linkbtn">' + esc('History of changes') + '</summary>';
      var hl = el('ul', 'hist');
      r.history.forEach(function (h) { hl.appendChild(el('li', '', '<span class="mono">' + esc(fmtDT(h.at)) + '</span> · ' + nt(h.summary || h.action) + (h.by ? ' · ' + nt(h.by) : ''))); });
      det.appendChild(hl); hc.appendChild(det); main.appendChild(hc);
    }
  }
  /* one delivery: who, when, lines; an employee's observed price and extras are shown for review */
  function receiptBox(x) {
    var b = el('div', 'rcpt');
    var INVS = { pending: 'Invoice pending', review: 'Invoice to review', confirmed: 'Invoice confirmed' };
    b.innerHTML = '<div class="rh"><b class="mono">' + esc(fmtDT(x.received_at)) + '</b> · ' + nt(x.by_name || '') +
      (x.origin === 'correccion' ? ' <span class="pill gold">' + esc('Correction') + '</span>' : '') +
      (FLAGS.can_manage || FLAGS.can_pay ? ' · <span class="mono">' + esc(fmtC(x.total_crc)) + '</span>' : '') +
      (x.invoice_no ? ' · <span>' + esc('invoice') + '</span> ' + nt(x.invoice_no) : '') + (x.invoice_status ? ' · <span class="pill info">' + esc(INVS[x.invoice_status] || x.invoice_status) + '</span>' : '') +
      (x.final ? ' · <span>' + esc('closed the order') + '</span>' : '') + (x.close_requested ? ' · <span class="pill gold">' + esc('The rest is not coming') + '</span>' : '') + '</div>' +
      (x.note ? '<div class="hint">' + nt(x.note) + '</div>' : '');
    var ul = el('ul');
    (x.lines || []).forEach(function (l) {
      var li = el('li', '', esc(num(l.packs)) + ' × ' + nt(l.item_name || '') + (l.pack_price != null ? ' · <span class="mono">' + esc(fmtC(l.pack_price)) + '</span>' : ''));
      var seenDiff = l.observed_pack_price != null && (l.expected_pack_price == null || Math.abs(Number(l.observed_pack_price) - Number(l.expected_pack_price)) >= 0.005);
      if (seenDiff) li.insertAdjacentHTML('beforeend', ' · <span class="pill gold">' + esc('Price seen: ' + fmtC(l.observed_pack_price) + (l.expected_pack_price != null ? ' (expected ' + fmtC(l.expected_pack_price) + ')' : '')) + '</span>');
      if (Number(l.extra_reported_packs) > 0) li.insertAdjacentHTML('beforeend', ' · <span class="pill gold">' + esc('More than ordered arrived: ' + num(l.extra_reported_packs) + ' (noted by the employee)') + '</span>');
      /* the button last, appended as a node (an innerHTML += after it would drop its listener) */
      var line = seenDiff && ORDER && (ORDER.lines || []).filter(function (z) { return z.id === l.line_id; })[0];
      if (seenDiff && FLAGS.can_manage && line && line.vendor_item_id) { li.appendChild(document.createTextNode(' ')); li.appendChild(usePriceBtn(line.vendor_item_id, l.observed_pack_price)); }
      ul.appendChild(li);
    });
    b.appendChild(ul);
    return b;
  }
  function usePriceBtn(vi, price) {
    return btn('Use ' + fmtC(price) + ' as the usual price', 'linkbtn', async function () {
      var r = await rpc('proveedor_producto_guardar', { p_item: { id: vi, usual_price: round(price, 2) } });
      if (!r.ok) { if (!r.handled) toast(errText(r)); return; }
      this.disabled = true; CACHE = {}; toast('Usual price saved');
    });
  }
  async function confirmOrder() {
    var r = await rpc('proveedor_pedido_confirmar', { p_po_id: ORDER.order.id, p_version: ORDER.order.version });
    if (!r.ok) { if (!r.handled) { toast(errText(r)); if (r.error === 'changed') route(); } return; }
    toast('Order confirmed'); route();
  }
  async function cancelOrder() {
    if (!confirm('Cancel order Nº ' + ORDER.order.po_number + '?')) return;
    var r = await rpc('proveedor_pedido_cancelar', { p_po_id: ORDER.order.id, p_version: ORDER.order.version, p_reason: null });
    if (!r.ok) { if (!r.handled) { toast(errText(r)); if (r.error === 'changed') route(); } return; }
    if (ORDER.order.vendor_id) forgetFicha(ORDER.order.vendor_id);
    toast('Order cancelled'); route();
  }
  async function closePending() {
    var why = prompt('Close what is pending? What did not arrive stays recorded as missing. Why (optional):', '');
    if (why === null) return;
    var r = await rpc('proveedor_pedido_cerrar', { p_po_id: ORDER.order.id, p_version: ORDER.order.version, p_reason: why.trim() || null });
    if (!r.ok) { if (!r.handled) { toast(errText(r)); if (r.error === 'changed') route(); } return; }
    if (ORDER.order.vendor_id) forgetFicha(ORDER.order.vendor_id);
    toast('Order closed'); route();
  }

  /* «Editar»: quantities, prices, × per line, «+ Agregar producto», note and expected date; saved with the version */
  FORMS.orderEdit = async function (poId) { if (ORDER && ORDER.order.id === poId) await editOrder(true); };
  async function editOrder(force) {
    var box = $('docEditBox'); if (!box) return;
    if (box.firstChild && !force) { box.innerHTML = ''; formClosed(); return; }
    box.innerHTML = '';
    var O = ORDER.order, open = /^(draft|sent|partially_received)$/.test(O.status);
    var rows = (ORDER.lines || []).filter(function (l) { return !l.removed; }).map(function (l) {
      return { line_id: l.id, name: pname(l), pres: l, packs: Number(l.packs), price: l.expected_pack_price != null ? Number(l.expected_pack_price) : null, orig_packs: Number(l.packs),
               orig_price: l.expected_pack_price != null ? Number(l.expected_pack_price) : null, received: Number(l.received_packs) || 0, removed: false };
    });
    var cat = [];
    if (open && O.vendor_id) { var fr = await loadFicha(O.vendor_id); if (fr.ok) cat = (fr.products || []).filter(function (p) { return p.active && p.item_active !== false; }); }
    var f = el('form', 'inline form'); f.id = 'orderEdit'; f.setAttribute('autocomplete', 'off');
    f.innerHTML = '<h3 style="margin-top:0">' + esc('Edit the order') + '</h3>' + (open ? '' : '<p class="hint">' + esc(ERR.closed) + '</p>') +
      '<div id="oeLines"></div>' + (open && cat.length ? '<div class="row" style="margin-top:.6rem"><div><label class="f" for="oeAdd">' + esc('+ Add product') + '</label><select id="oeAdd"><option value="">—</option></select></div><div></div></div>' : '') +
      '<label class="f" for="oeNote">' + esc('Note for the supplier') + '</label><textarea id="oeNote" maxlength="500" rows="2"></textarea>' +
      '<div class="row"><div><label class="f" for="oeExp">' + esc('Expected delivery') + '</label><input id="oeExp" type="date"></div><div></div></div>' +
      '<p class="err" id="oeErr" role="alert"></p><div class="btns"><button type="button" class="ghost" id="oeCancel">Cancel</button><button type="submit" id="oeGo">Save changes</button></div>';
    box.appendChild(f);
    $('oeNote').value = O.note || ''; $('oeExp').value = O.expected_on || '';
    var addSel = $('oeAdd');
    function paintAdd() {
      if (!addSel) return;
      addSel.innerHTML = '<option value="">—</option>';
      cat.filter(function (p) { return !rows.some(function (r) { return !r.removed && (r.vendor_item_id === p.id || (r.pres && r.pres.vendor_item_id === p.id)); }); }).forEach(function (p) {
        var o = document.createElement('option'); o.value = p.id; o.textContent = pname(p) + ' · ' + (p.pack_label || qtyU(p.pack_qty, p.unit)) + (p.usual_price != null ? ' · ' + fmtC(p.usual_price) : ''); addSel.appendChild(o);
      });
    }
    function paintLines() {
      var L = $('oeLines'); L.innerHTML = '';
      rows.forEach(function (r, i) {
        if (r.removed) return;
        var d = el('div', 'prow'); d.style.gridTemplateColumns = 'minmax(0,1fr) auto';
        d.innerHTML = '<div><div class="nm">' + nt(r.name) + '</div><div class="ds">' + presHtml(r.pres) + (r.received ? ' · <span>' + esc('received ' + num(r.received)) + '</span>' : '') + '</div></div>';
        var right = el('div', 'btns'); right.style.marginTop = '0';
        if (open) {
          var q = document.createElement('input'); q.type = 'text'; q.inputMode = 'decimal'; q.setAttribute('data-keypad', 'qty'); q.maxLength = 10; q.value = plainNum(r.packs); q.style.width = '5.5em'; q.id = 'oeQ' + i; q.setAttribute('aria-label', 'Quantity of ' + r.name);
          q.addEventListener('input', function () { r.packs = parseNum(q.value); });
          var pp = document.createElement('input'); pp.type = 'text'; pp.inputMode = 'decimal'; pp.setAttribute('data-keypad', 'qty'); pp.maxLength = 14; pp.value = r.price != null ? plainNum(r.price) : ''; pp.className = 'priceIn'; pp.id = 'oeP' + i; pp.placeholder = '₡'; pp.setAttribute('aria-label', 'Price per presentation of ' + r.name);
          pp.addEventListener('input', function () { r.price = pp.value.trim() === '' ? null : parseNum(pp.value); });
          right.appendChild(q); right.appendChild(pp);
          var x = btn('×', 'ghost small x', function () { r.removed = true; paintLines(); paintAdd(); f.dispatchEvent(new Event('input')); }, { 'aria-label': 'Take ' + r.name + ' off the order' });
          if (r.received > 0) { x.disabled = true; x.title = 'It already has deliveries'; }
          right.appendChild(x);
        } else right.appendChild(el('span', 'mono', esc(num(r.packs))));
        d.appendChild(right); L.appendChild(d);
      });
    }
    paintLines(); paintAdd();
    if (addSel) addSel.addEventListener('change', function () {
      var p = cat.filter(function (x) { return x.id === addSel.value; })[0]; if (!p) return;
      rows.push({ vendor_item_id: p.id, name: pname(p), pres: p, packs: suggestion(p), price: p.usual_price != null ? Number(p.usual_price) : null, orig_price: p.usual_price != null ? Number(p.usual_price) : null, received: 0, removed: false, isNew: true });
      paintLines(); paintAdd();
    });
    formOpened('orderEdit', [O.id], f);
    $('oeCancel').addEventListener('click', function () { box.innerHTML = ''; formClosed(f); });
    f.addEventListener('submit', async function (e) {
      e.preventDefault();
      var E = $('oeErr'); E.textContent = '';
      var args = { p_po_id: O.id, p_version: O.version, p_lines: null, p_note: null, p_expected_on: null };
      var note = $('oeNote').value.trim();
      if (note !== (O.note || '')) args.p_note = note;   /* '' clears it */
      if (($('oeExp').value || '') !== (O.expected_on || '') && $('oeExp').value) args.p_expected_on = $('oeExp').value;
      if (open) {
        var changed = false, out = [];
        for (var i = 0; i < rows.length; i++) {
          var r = rows[i];
          if (r.removed) { if (!r.isNew) changed = true; continue; }
          if (!(r.packs > 0 && r.packs <= 100000 && decimals(r.packs) <= 3)) { E.textContent = ERR.bad_qty + ' · ' + r.name; return; }
          if (r.packs < r.received) { E.textContent = ERR.below_received + ' · ' + r.name; return; }
          if (r.price !== null && !(r.price >= 0 && r.price <= 100000000)) { E.textContent = ERR.bad_price + ' · ' + r.name; return; }
          var o = r.isNew ? { vendor_item_id: r.vendor_item_id, packs: r.packs } : { line_id: r.line_id, packs: r.packs };
          var priceChanged = r.isNew ? r.price !== null && (r.orig_price === null || Math.abs(r.price - r.orig_price) >= 0.005) : (r.price !== null && (r.orig_price === null || Math.abs(r.price - r.orig_price) >= 0.005));
          if (priceChanged) { o.pack_price = round(r.price, 2); if (r.price === 0) o.free = true; }
          if (r.isNew && r.price === null) { E.textContent = ERR.needs_price + ' · ' + r.name; return; }
          if (r.isNew || priceChanged || Math.abs(r.packs - r.orig_packs) > 1e-9) changed = true;
          out.push(o);
        }
        if (!out.length) { E.textContent = 'An order keeps at least one product. To drop it, cancel the order.'; return; }
        if (changed) args.p_lines = out;
      }
      if (args.p_lines === null && args.p_note === null && args.p_expected_on === null) { box.innerHTML = ''; formClosed(f); return; }
      $('oeGo').disabled = true;
      var res = await rpc('proveedor_pedido_editar', args);
      $('oeGo').disabled = false;
      if (!res.ok) {
        if (res.handled) return;
        if (res.error === 'changed') { formClosed(f); viewPedido(++GEN, O.id, 'Someone changed this order a moment ago. Here it is as it is now: make your change again.'); return; }
        E.textContent = errText(res); return;
      }
      formClosed(f); if (O.vendor_id) forgetFicha(O.vendor_id);
      toast('Changes saved'); route();
    });
  }

  /* «Corregir una entrega»: a new receipt with signed differences (never deleting the first one) */
  var FIX = null;
  function openFix() {
    var recs = (ORDER.receipts || []).filter(function (x) { return x.origin !== 'correccion'; });
    if (!recs.length) return;
    FIX = { req: uuid(), po: ORDER.order.id };
    var sel = $('fixRcpt'); sel.innerHTML = '';
    recs.forEach(function (x) { var o = document.createElement('option'); o.value = x.id; o.textContent = fmtDT(x.received_at) + ' · ' + (x.by_name || '') + (x.invoice_no ? ' · ' + x.invoice_no : ''); sel.appendChild(o); });
    sel.value = recs[recs.length - 1].id;
    paintFix();
    $('fixWhy').value = ''; $('fixExtra').checked = false; $('fixErr').textContent = '';
    openModal('fixModal', 'fixRcpt');
    formOpened('fix', [ORDER.order.id], $('fixForm'), FIX.req);
  }
  FORMS.fix = async function (poId, opts) { if (ORDER && ORDER.order.id === poId) { openFix(); if (opts && opts.req) FIX.req = opts.req; } };
  function paintFix() {
    var rid = $('fixRcpt').value, x = (ORDER.receipts || []).filter(function (r) { return r.id === rid; })[0], box = $('fixLines'); box.innerHTML = '';
    (x ? x.lines || [] : []).forEach(function (l, i) {
      var d = el('div', 'row');
      /* an old page's delivery that cannot be tied to one line of the order (the item is on several): not here */
      if (!l.line_id) { d.innerHTML = '<p class="hint">' + nt(l.item_name) + ' · <span>' + esc('This line of an old delivery cannot be corrected here.') + '</span></p>'; box.appendChild(d); return; }
      var ol = (ORDER.lines || []).filter(function (z) { return z.id === l.line_id; })[0];
      var pres = ol ? (ol.pack_label ? nt(ol.pack_label) : '<span>' + esc(qtyU(ol.pack_qty, ol.unit)) + '</span>') : '';
      d.innerHTML = '<div><label class="f" for="fxL' + i + '">' + nt(l.item_name) + ' · <span>' + esc('recorded ' + (l.packs != null ? num(l.packs) : num(l.qty))) + '</span>' + (pres && l.packs != null ? ' × ' + pres : '') + '</label></div>' +
        '<div><input id="fxL' + i + '" data-line="' + esc(l.line_id) + '" type="text" inputmode="decimal" maxlength="10" placeholder="−1 / +1"></div>';
      box.appendChild(d);
    });
  }
  $('fixRcpt').addEventListener('change', paintFix);
  $('fixCancel').addEventListener('click', function () { closeModal('fixModal'); });
  $('fixForm').addEventListener('submit', async function (e) {
    e.preventDefault();
    if (!FIX) return;
    var E = $('fixErr'); E.textContent = '';
    var lines = [], bad = false, extra = $('fixExtra').checked;
    document.querySelectorAll('#fixLines input[data-line]').forEach(function (i) {
      var s = i.value.trim().replace('−', '-').replace(',', '.'); if (!s) return;
      if (!/^[+-]?\d+(\.\d{1,3})?$/.test(s) || Number(s) === 0) { bad = true; return; }
      var o = { line_id: i.getAttribute('data-line'), packs_delta: Number(s) }; if (extra && Number(s) > 0) o.extra_ok = true; lines.push(o);
    });
    if (bad) { E.textContent = 'Type each difference as a number, like −2 or +1.'; return; }
    if (!lines.length) { E.textContent = 'Type at least one difference.'; return; }
    var why = $('fixWhy').value.trim(); if (why.length < 5) { E.textContent = ERR.needs_reason; $('fixWhy').focus(); return; }
    $('fixGo').disabled = true;
    var r = await rpc('proveedor_recepcion_corregir', { p_receipt_id: $('fixRcpt').value, p_request_id: FIX.req, p_lines: lines, p_reason: why });
    $('fixGo').disabled = false;
    if (!r.ok) { if (!r.handled) E.textContent = errText(r); return; }
    FIX = null; closeModal('fixModal'); if (ORDER.order.vendor_id) forgetFicha(ORDER.order.vendor_id);
    toast('Correction saved'); route();
  });

  /* ---------- 15) what goes to the supplier: hard-coded Spanish, no internal data ---------- */
  var MES = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'set', 'oct', 'nov', 'dic'];
  function fechaEs(iso) { var d = dateOf(iso) || new Date(); return d.getDate() + ' ' + MES[d.getMonth()] + ' ' + d.getFullYear(); }
  var UNI_ES = { unit: ['unidad', 'unidades'], g: ['g', 'g'], kg: ['kg', 'kg'], ml: ['ml', 'ml'], L: ['L', 'L'] };
  function numEs(n, d) { var r = round(n, d == null ? 3 : d), s = String(Math.abs(r)).split('.'); s[0] = s[0].replace(/\B(?=(\d{3})+(?!\d))/g, ' '); return (r < 0 ? '-' : '') + s[0] + (s[1] ? ',' + s[1] : ''); }
  function cantEs(n, u) { var w = UNI_ES[u] || [u || '', u || '']; return numEs(n) + ' ' + (Number(n) === 1 ? w[0] : w[1]); }
  function presEs(l) { return l.pack_label || cantEs(l.pack_qty, l.unit); }
  function crc(n) { return '₡' + numEs(round(n, 2), 2); }
  function docData() {
    var O = ORDER.order, lines = (ORDER.lines || []).filter(function (l) { return !l.removed && Number(l.packs) > 0; })
      .sort(function (a, b) { return (Number(a.pos) || 999) - (Number(b.pos) || 999); });
    return { n: O.po_number, vendor: O.vendor_name || '', contact: O.vendor_contact || '', phone: O.vendor_phone || '', email: O.vendor_email || '',
             date: fechaEs(O.sent_at || O.created_at), expected: O.expected_on ? fechaEs(O.expected_on) : '', note: O.note || '', lines: lines,
             total: (ORDER.totals && ORDER.totals.estimated) || 0 };
  }
  function lineEs(l) {
    var name = pname(l) + (l.vendor_code ? ' (cód. ' + l.vendor_code + ')' : '');
    if (!l.pack_label && Number(l.pack_qty) === 1) return '• ' + cantEs(l.packs, l.unit) + ' — ' + name;
    return '• ' + numEs(l.packs) + ' × ' + presEs(l) + ' — ' + name;
  }
  function copyText() {
    var d = docData();
    return ['Pedido Nº ' + d.n + ' · Hanging Garden Café', 'Proveedor: ' + d.vendor, 'Fecha: ' + d.date + (d.expected ? ' · Entrega: ' + d.expected : ''), '']
      .concat(d.lines.map(lineEs)).concat(d.note ? ['', 'Nota: ' + d.note] : []).concat(['', 'Por favor indique el Nº ' + d.n + ' en la factura. Gracias.']).join('\n');
  }
  async function copyOrder() {
    var t = copyText(), ok = false;
    try { if (navigator.clipboard && window.isSecureContext) { await navigator.clipboard.writeText(t); ok = true; } } catch (e) {}
    if (!ok) {
      var ta = document.createElement('textarea'); ta.value = t; ta.setAttribute('readonly', ''); ta.style.cssText = 'position:fixed;left:-9999px;top:0';
      document.body.appendChild(ta); ta.select(); try { ta.setSelectionRange(0, t.length); ok = document.execCommand('copy'); } catch (e) {} ta.remove();
    }
    toast(ok ? 'Copied' : 'Could not copy. Select the text and copy it by hand.');
  }
  function withPrices() { var c = $('docPrices'); return !c || c.checked; }
  function printHtml(prices) {
    var d = docData(), e = esc;
    var rows = d.lines.map(function (l) {
      return '<tr><td>' + e(pname(l)) + (l.vendor_code ? ' <span class="small">(cód. ' + e(l.vendor_code) + ')</span>' : '') + '</td><td>' + e(presEs(l)) + '</td><td class="n">' + e(numEs(l.packs)) + '</td>' +
        (prices ? '<td class="n">' + (l.expected_pack_price != null ? e(crc(l.expected_pack_price)) : '') + '</td><td class="n">' + (l.line_total_est != null ? e(crc(l.line_total_est)) : '') + '</td>' : '') + '</tr>';
    }).join('');
    return '<div class="ph"><div><h1>Hanging Garden Café</h1><div>Monteverde, Costa Rica</div></div><div class="pr"><b>PEDIDO Nº ' + e(d.n) + '</b><br>' + e(d.date) + (d.expected ? '<br>Entrega esperada: ' + e(d.expected) : '') + '</div></div>' +
      '<div><b>Proveedor:</b> ' + e(d.vendor) + [d.contact, d.phone, d.email].filter(Boolean).map(function (x) { return ' · ' + e(x); }).join('') + '</div>' +
      '<table><thead><tr><th>Producto</th><th>Presentación</th><th class="n">Cantidad</th>' + (prices ? '<th class="n">Precio sin IVA</th><th class="n">Subtotal</th>' : '') + '</tr></thead><tbody>' + rows + '</tbody>' +
      (prices ? '<tfoot><tr><td colspan="4" class="n"><b>Total estimado (sin IVA)</b></td><td class="n"><b>' + e(crc(d.total)) + '</b></td></tr></tfoot>' : '') + '</table>' +
      (d.note ? '<p><b>Nota:</b> ' + e(d.note) + '</p>' : '') +
      '<p class="foot">Por favor indique el Nº ' + e(d.n) + ' en la factura. Gracias.</p>';
  }
  function printOrder() {
    $('printDoc').innerHTML = printHtml(withPrices());
    window.print();
  }
  function pdfOrder() {
    var d = docData(), bytes = PDF.order(d, withPrices());
    var name = 'Pedido-' + d.n + '-' + (norm(d.vendor).replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 40) || 'proveedor') + '.pdf';
    var blob = new Blob([bytes], { type: 'application/pdf' }), file = null;
    try { file = new File([blob], name, { type: 'application/pdf' }); } catch (e) {}
    if (file && navigator.canShare && navigator.share) {
      try { if (navigator.canShare({ files: [file] })) { navigator.share({ files: [file], title: 'Pedido Nº ' + d.n }).catch(function () {}); return; } } catch (e) {}
    }
    var a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = name; document.body.appendChild(a); a.click();
    setTimeout(function () { URL.revokeObjectURL(a.href); a.remove(); }, 4000);
  }

  /* ---------- 16) receiving (#recibir=): management, or the employee on shift on this device ----------
     A table at 720 px and wider, cards below. «Todo recibido correctamente» = rest:true for every pending line at the
     expected prices, in one tap. The form survives a reload: localStorage['hg-prov-recv:<po>'] = {receipt_id, version,
     values, invoice_no, note, close, extra_ok}; the receipt id is kept until the server answers, so it is booked once. */
  var RECV = null;
  function rkey(po) { return 'hg-prov-recv:' + po; }
  /* who is typing this receive form on this device: the person on shift, or the management unlock (never a PIN) */
  function recvWho(emp) { return emp ? 'e:' + ((TURNO && TURNO.staff_id) || '') : 'm:' + (UID || '') + ':' + ((ST && (ST.staff_id || ST.name)) || ACCOUNT || ''); }
  function recvSave() {
    if (!RECV) return;
    var vals = {};
    RECV.lines.forEach(function (l) { if (l.typed !== undefined || l.price !== undefined) vals[l.id] = { packs: l.typed, price: l.price }; });
    ls(rkey(RECV.po), { who: RECV.who, receipt_id: RECV.receipt_id, version: RECV.version, values: vals, invoice_no: RECV.invoice_no || '', note: RECV.note || '', close: !!RECV.close, extra_ok: !!RECV.extra_ok });
  }
  async function viewRecibir(gen, poId) {
    if (!isUuid(poId)) { go('#'); return; }
    main.innerHTML = '<p class="loading">Loading…</p>';
    var emp = MODE === 'receive';
    var r = await rpc('proveedor_pedido', emp ? { p_po_id: poId, p_token: TURNO.token } : { p_po_id: poId });
    if (stale(gen)) return;
    if (!r.ok) {
      if (r.handled) return;
      if (r.error === 'not_found' && emp) { showMainError('That order is not waiting to be received.', function () { go('#'); }); return; }
      return loadErr(gen, r);
    }
    if (!emp) setFlags(r);
    var O = r.order;
    if (!emp && !FLAGS.can_manage) { showMainError(ERR.not_receiver, function () { go('#pedido=' + poId); }, 'Back'); return; }
    if (!/^(draft|sent|partially_received)$/.test(O.status) || (emp && O.status === 'draft')) {
      ls(rkey(poId), null);
      showMainError(O.status === 'received' ? ERR.already_received : O.status === 'cancelled' ? ERR.cancelled : 'That order is not waiting to be received.', function () { go(emp ? '#' : '#pedido=' + poId); });
      return;
    }
    var saved = ls(rkey(poId)) || {};
    /* the id kept for a delivery whose answer was lost: if that delivery is already among the order's receipts, it was
       saved; what is typed now is a new delivery with a new id (never a «repeat» that books nothing) */
    var spent = isUuid(saved.receipt_id) && (r.receipts || []).some(function (x) { return x && x.id === saved.receipt_id; });
    if (spent) { ls(rkey(poId), null); saved = {}; }
    /* what another person typed here (a person on shift who left, or before a manager's unlock) is never carried into this
       one's form: their counts and the prices an employee saw would go in under this person's name */
    var who = recvWho(emp);
    if (Object.keys(saved).length && saved.who !== who) {
      var hadTyped = Object.keys(saved.values || {}).length > 0 || !!saved.note || !!saved.invoice_no;
      ls(rkey(poId), null); saved = {};
      if (hadTyped) toast('What someone else typed on this device for this order was not kept. Count the delivery again.');
    }
    RECV = { po: poId, emp: emp, who: who, version: O.version, receipt_id: isUuid(saved.receipt_id) ? saved.receipt_id : uuid(), invoice_no: saved.invoice_no || '', note: saved.note || '',
             close: !!saved.close, extra_ok: !!saved.extra_ok, price_ok: false, touched: false, order: O, vendor_name: O.vendor_name, po_number: O.po_number,
             lines: (r.lines || []).filter(function (l) { return !l.removed; }).sort(function (a, b) { return (Number(a.pos) || 999) - (Number(b.pos) || 999); }).map(function (l) {
               var v = (saved.values || {})[l.id] || {};
               return { id: l.id, name: pname(l), code: l.vendor_code, l: l, pending: Math.max(0, Number(l.pending_packs) || 0), received: Number(l.received_packs) || 0, ordered: Number(l.packs) || 0,
                        pack_qty: Number(l.pack_qty) || 1, expected: l.expected_pack_price != null ? Number(l.expected_pack_price) : null, vendor_item_id: l.vendor_item_id,
                        seen: l.received_qty != null ? Number(l.received_qty) : (Number(l.received_packs) || 0) * (Number(l.pack_qty) || 1),
                        typed: v.packs !== undefined && v.packs !== null && isFinite(Number(v.packs)) ? Number(v.packs) : undefined, price: v.price !== undefined && v.price !== null && isFinite(Number(v.price)) ? Number(v.price) : undefined };
             }) };
    RECV.touched = RECV.lines.some(function (l) { return l.typed !== undefined || l.price !== undefined; }) || !!RECV.invoice_no || !!RECV.note;
    recvSave();
    paintRecv(spent ? 'Your earlier delivery was already saved. Check what is still pending.'
      : saved.version != null && saved.version !== O.version && RECV.touched ? 'This order changed since you started. Check what is pending and confirm again.' : null);
  }
  function rPacks(l) { return l.typed !== undefined ? l.typed : l.pending; }
  function rPrice(l) { return l.price !== undefined ? l.price : l.expected; }
  function paintRecv(msg) {
    var R = RECV; if (!R) return;
    main.innerHTML = '';
    main.appendChild(crumbs(R.emp ? [{ href: '#', text: 'Orders to receive' }, { text: 'Order Nº ' + (R.po_number || '') }]
      : [{ href: '#', text: 'Suppliers' }, { href: '#pedido=' + R.po, text: 'Order Nº ' + (R.po_number || '') }, { text: 'Receive' }]));
    var c = el('section', 'card'); c.id = 'recvCard';
    /* a person's name stays as typed; «the owner» (the phone code names nobody) is the page's own text, for lang.js */
    var who = R.emp ? nt(TURNO.name) : ST && ST.name ? nt(ST.name) : ACCOUNT === 'owner' ? '<span>' + esc('the owner') + '</span>' : '';
    c.appendChild(el('div', 'recvhead', '<h2 style="margin:0">' + esc('Receive order Nº ' + (R.po_number || '')) + '</h2>' + (R.vendor_name ? '<span class="hint">' + nt(R.vendor_name) + '</span>' : '') +
      '<span class="sp"></span><span class="hint"><span>' + esc('Receiving:') + '</span> <b>' + who + '</b></span>'));
    if (msg) { var m = el('p', 'note'); m.setAttribute('role', 'status'); m.textContent = msg; c.appendChild(m); }
    var pend = R.lines.filter(function (l) { return l.pending > 0.0005; });
    if (pend.length) {
      var big = btn('Everything arrived correctly', 'bigok', function () { recvSubmit(true); }, { id: 'recvAll' });
      c.appendChild(big);
      c.appendChild(el('p', 'hint', esc(R.emp ? 'One tap when the delivery matches the order. If something is different, change it below and confirm.' : 'One tap when the delivery matches the order, at the expected prices. If something is different, change it below and confirm.')));
    }
    var t = el('table', 'rt'); t.id = 'recvTable';
    t.innerHTML = '<thead><tr><th>' + esc('Product') + '</th><th class="num">' + esc('Ordered') + '</th><th>' + esc('Received') + '</th><th>' + esc('Price without IVA') + '</th></tr></thead>';
    var tb = document.createElement('tbody');
    R.lines.forEach(function (l, i) {
      var tr = document.createElement('tr'); tr.setAttribute('data-line', l.id);
      var done = l.pending <= 0.0005;
      tr.innerHTML = '<td><span class="lbl">' + esc('Product') + '</span><b>' + nt(l.name) + '</b>' + (l.code ? ' <span class="hint">(<span>' + esc('code') + '</span> ' + nt(l.code) + ')</span>' : '') + '<span class="sub">' + presHtml(l.l) + '</span></td>' +
        '<td class="num"><span class="lbl">' + esc('Ordered') + '</span>' + esc(num(l.ordered)) + (l.received > 0 ? '<span class="sub">' + esc('already in ' + num(l.received) + ' · pending ' + num(l.pending)) + '</span>' : '') + '</td>' +
        '<td><span class="lbl">' + esc('Received') + '</span>' + (done ? '<span class="pill ok">' + esc('Complete') + '</span>' :
          '<div class="step"><button type="button" data-a="minus" aria-label="One less">−</button><input id="rq' + i + '" type="text" inputmode="decimal" data-keypad="qty" maxlength="10" aria-label="Received of ' + esc(l.name) + '"><button type="button" data-a="plus" aria-label="One more">+</button></div><span class="sub rnote"></span>') + '</td>' +
        '<td><span class="lbl">' + esc('Price without IVA') + '</span>' + (done ? '' : '<input id="rp' + i + '" class="priceIn" type="text" inputmode="decimal" data-keypad="qty" maxlength="14" aria-label="Price of ' + esc(l.name) + '">' +
          '<span class="sub">' + esc('per') + ' ' + (l.l.pack_label ? nt(l.l.pack_label) : '<span>' + esc(qtyU(l.pack_qty, l.l.unit)) + '</span>') + (l.expected != null ? ' · <span>' + esc('expected ' + fmtC(l.expected)) + '</span>' : '') + '</span>') + '</td>';
      tb.appendChild(tr);
      if (!done) { tr.querySelector('#rq' + i).value = plainNum(rPacks(l)); tr.querySelector('#rp' + i).value = rPrice(l) != null ? plainNum(rPrice(l)) : ''; }
    });
    t.appendChild(tb);
    c.appendChild(t);
    var f = el('div', 'form');
    f.innerHTML = '<div class="row"><div><label class="f" for="rInv">' + esc('Invoice Nº (if it came with one)') + '</label><input id="rInv" maxlength="40" autocomplete="off"></div>' +
      '<div><label class="f" for="rNote">' + esc('Remarks') + '</label><input id="rNote" maxlength="500" autocomplete="off"></div></div>' +
      '<div id="rShort" hidden></div><div id="rOver" hidden></div><div id="rPriceAsk" hidden></div>' +
      '<p class="err" id="rErr" role="alert"></p>';
    c.appendChild(f);
    var go2 = el('div', 'btns'); go2.appendChild(R.emp ? link('Back', '#', 'btnlink') : link('Back', '#pedido=' + R.po, 'btnlink'));
    go2.appendChild(btn('Confirm reception', pend.length ? '' : 'ghost', function () { recvSubmit(false); }, { id: 'recvGo' }));
    c.appendChild(go2);
    main.appendChild(c);
    $('rInv').value = R.invoice_no; $('rNote').value = R.note;
    $('rInv').addEventListener('input', function () { R.invoice_no = $('rInv').value.trim(); R.touched = true; recvSave(); });
    $('rNote').addEventListener('input', function () { R.note = $('rNote').value; R.touched = true; recvSave(); });
    t.addEventListener('click', function (e) {
      var b = e.target.closest('button[data-a]'); if (!b) return;
      var tr = b.closest('tr'), l = R.lines.filter(function (x) { return x.id === tr.getAttribute('data-line'); })[0]; if (!l) return;
      var v = rPacks(l); v = b.getAttribute('data-a') === 'plus' ? round(v + 1, 3) : Math.max(0, round(v - 1, 3));
      l.typed = v; tr.querySelector('.step input').value = plainNum(v); R.touched = true; recvSave(); paintRecvNotes();
    });
    t.addEventListener('input', function (e) {
      var i = e.target, tr = i.closest('tr'); if (!tr) return;
      var l = R.lines.filter(function (x) { return x.id === tr.getAttribute('data-line'); })[0]; if (!l) return;
      var v = i.value.trim() === '' ? null : parseNum(i.value);
      if (i.closest('.step')) { l.typed = v === null ? 0 : v; i.style.borderColor = v === null || (v >= 0 && decimals(v) <= 3) ? '' : 'var(--bad)'; }
      else { l.price = v === null ? null : v; i.style.borderColor = v === null || v >= 0 ? '' : 'var(--bad)'; }
      R.touched = true; recvSave(); paintRecvNotes();
    });
    paintRecvNotes();
  }
  /* short: «¿Llega el resto después?»; over: the employee's extra is noted, management authorizes it */
  function paintRecvNotes() {
    var R = RECV; if (!R || !$('rShort')) return;
    var short = R.lines.some(function (l) { return l.pending > 0.0005 && rPacks(l) < l.pending - 0.0005; });
    var over = R.lines.some(function (l) { return l.pending > 0.0005 && rPacks(l) > l.pending + 0.0005; });
    document.querySelectorAll('#recvTable tr[data-line]').forEach(function (tr) {
      var l = R.lines.filter(function (x) { return x.id === tr.getAttribute('data-line'); })[0], n = tr.querySelector('.rnote'); if (!l || !n) return;
      var v = rPacks(l);
      n.textContent = v > l.pending + 0.0005 ? (R.emp ? 'More than ordered: noted for the manager' : 'More than what is pending') : v < l.pending - 0.0005 ? 'Short ' + num(round(l.pending - v, 3)) : '';
    });
    var s = $('rShort'); s.hidden = !short; s.innerHTML = '';
    if (short) {
      if (R.emp) {
        s.innerHTML = '<label class="checkline"><input type="checkbox" id="rClose"' + (R.close ? ' checked' : '') + '> <span>Tell the manager the rest is not coming</span></label>';
        $('rClose').addEventListener('change', function () { R.close = $('rClose').checked; recvSave(); });
      } else {
        s.appendChild(el('p', '', '<b>' + esc('Is the rest coming later?') + '</b>'));
        var ch = el('div', 'choice');
        ch.appendChild(btn('Yes, it stays pending', '', function () { R.close = false; recvSave(); paintRecvNotes(); }, { 'aria-pressed': String(!R.close), id: 'rRestYes' }));
        ch.appendChild(btn('No, close the order', '', function () { R.close = true; recvSave(); paintRecvNotes(); }, { 'aria-pressed': String(!!R.close), id: 'rRestNo' }));
        s.appendChild(ch);
      }
    }
    var o = $('rOver'); o.hidden = !over; o.innerHTML = '';
    if (over) {
      if (R.emp) o.appendChild(el('p', 'note', esc('More than ordered arrived: it is noted for the manager (only what was ordered goes into stock).')));
      else { o.innerHTML = '<label class="checkline"><input type="checkbox" id="rExtra"' + (R.extra_ok ? ' checked' : '') + '> <span>More than ordered arrived (I authorize it)</span></label>'; $('rExtra').addEventListener('change', function () { R.extra_ok = $('rExtra').checked; recvSave(); }); }
    }
  }
  var recvBusy = false;
  async function recvSubmit(all) {
    var R = RECV; if (!R || recvBusy) return;
    var E = $('rErr'); E.textContent = '';
    if (all && R.touched && R.lines.some(function (l) { return (l.typed !== undefined && Math.abs(l.typed - l.pending) > 0.0005) || (l.price !== undefined && l.price !== l.expected); }) &&
        !confirm('Record everything pending as received, at the expected prices? What you changed below is not used.')) return;
    var lines = [], bad = null;
    R.lines.forEach(function (l) {
      if (l.pending <= 0.0005 && !(l.typed > 0)) return;
      if (all) { if (l.pending > 0.0005) lines.push({ line_id: l.id, rest: true }); return; }
      var v = rPacks(l);
      if (!(v >= 0) || decimals(v) > 3) { bad = bad || l; return; }
      var o = Math.abs(v - l.pending) < 0.001 ? { line_id: l.id, rest: true } : { line_id: l.id, packs: v };
      var pr = l.price;
      if (pr !== undefined && pr !== null && !(pr >= 0)) { bad = bad || l; return; }
      if (pr != null && (l.expected == null || Math.abs(pr - l.expected) >= 0.005)) o.pack_price = round(pr, 2);
      if (v > 0 || o.rest) lines.push(o);
      else if (v === 0 && l.pending > 0) lines.push({ line_id: l.id, packs: 0 });
    });
    if (bad) { E.textContent = ERR.bad_qty + ' · ' + bad.name; return; }
    var anything = lines.some(function (l) { return l.rest || l.packs > 0; });
    if (!anything && (!R.close || R.emp)) { E.textContent = ERR.empty; return; }
    var args = { p_po_id: R.po, p_receipt_id: R.receipt_id, p_version: R.version, p_lines: lines.filter(function (l) { return l.rest || l.packs > 0; }),
                 p_close: !all && !!R.close, p_invoice_no: (R.invoice_no || '').trim() || null, p_note: (R.note || '').trim() || null,
                 p_extra_ok: !R.emp && !!R.extra_ok, p_price_ok: !R.emp && !!R.price_ok };
    if (R.emp) args.p_token = TURNO.token;
    recvBusy = true;
    ['recvAll', 'recvGo'].forEach(function (id) { var b = $(id); if (b) b.disabled = true; });
    var sent = JSON.parse(JSON.stringify(R.lines.map(function (l) { return { id: l.id, name: l.name, pending: l.pending, packs: all ? l.pending : rPacks(l), expected: l.expected, price: all ? l.expected : rPrice(l), vendor_item_id: l.vendor_item_id }; })));
    var r = await rpc('proveedor_recibir', args);
    recvBusy = false;
    ['recvAll', 'recvGo'].forEach(function (id) { var b = $(id); if (b) b.disabled = false; });
    if (RECV !== R) return;
    if (r.ok) { ls(rkey(R.po), null); R.touched = false; RECV = null; recvDone(R, r, sent, all); return; }
    if (r.handled) return;
    if (r.error === 'changed' && r.receipt_used) { R.touched = false; viewRecibir(++GEN, R.po); return; }   /* the id was spent: a new delivery, new id */
    if (r.error === 'changed' && r.order) {
      var moved = (r.order.lines || []).some(function (x) { var l = R.lines.filter(function (y) { return y.id === x.id; })[0]; return l && Math.abs(Number(x.received_qty || 0) - l.seen) > 1e-6; });
      if (moved) { R.touched = false; ls(rkey(R.po), { who: R.who, receipt_id: R.receipt_id }); toast('Someone else recorded a delivery of this order a moment ago. Check what is pending.'); viewRecibir(++GEN, R.po).then(function () { if (RECV) paintRecv('Someone else recorded a delivery of this order a moment ago. Check what is pending.'); }); return; }
      R.version = r.order.version;
      (r.order.lines || []).forEach(function (x) { var l = R.lines.filter(function (y) { return y.id === x.id; })[0]; if (l && x.pending_packs != null) l.pending = Math.max(0, Number(x.pending_packs)); });
      recvSave(); paintRecv('The order changed a moment ago. Check what is pending and confirm again.'); return;
    }
    if (r.error === 'over_pending') {
      var ol = R.lines.filter(function (l) { return l.id === r.line_id; })[0];
      E.textContent = ERR.over_pending + (ol ? ' · ' + ol.name + (r.pending_packs != null ? ' · ' + 'pending ' + num(r.pending_packs) : '') : '');
      R.extra_ok = false; paintRecvNotes(); var x = $('rExtra'); if (x) x.focus(); return;
    }
    if (r.error === 'check_price') {
      var pl = R.lines.filter(function (l) { return l.id === r.line_id; })[0], pa = $('rPriceAsk'); pa.hidden = false; pa.innerHTML = '';
      var ex = r.expected != null ? r.expected : r.expected_pack_price;   /* 0039 answers expected_pack_price */
      var n = el('div', 'note', esc('Sure? ' + (ex != null ? 'The expected price was ' + fmtC(ex) : ERR.check_price)) + (pl ? ' · ' + nt(pl.name) : ''));
      var b = el('div', 'btns'); b.appendChild(btn('Yes, the price is right', 'small', function () { R.price_ok = true; pa.hidden = true; recvSubmit(false); })); n.appendChild(b); pa.appendChild(n);
      return;
    }
    if (r.error === 'already_received' || r.error === 'cancelled') { ls(rkey(R.po), null); R.touched = false; showMainError(errText(r), function () { go(R.emp ? '#' : '#pedido=' + R.po); }); return; }
    var bl = r.line_id && R.lines.filter(function (l) { return l.id === r.line_id; })[0];
    E.textContent = errText(r) + (bl ? ' · ' + bl.name : '');
  }
  /* the summary: what came, what is short, the price differences (management: «Usar ₡X como precio habitual») and extras */
  function recvDone(R, r, sent, all) {
    main.innerHTML = '';
    var c = el('section', 'card'); c.id = 'recvDone';
    var full = r.status === 'received';
    c.appendChild(el('h2', '', esc(r.repeat ? 'That delivery was already saved' : full ? 'Order received, stock updated' : 'Delivery received · the rest is still on order')));
    var ul = el('ul', 'sumlist');
    sent.forEach(function (l) {
      var got = Math.min(l.packs, R.emp ? l.pending : l.packs), shortBy = l.pending - l.packs;
      if (got > 0.0005) ul.appendChild(el('li', '', esc(num(got)) + ' × ' + nt(l.name)));
      if (shortBy > 0.0005) ul.appendChild(el('li', '', esc('Short ' + num(round(shortBy, 3))) + ' · ' + nt(l.name)));
      if (l.packs > l.pending + 0.0005) ul.appendChild(el('li', '', esc((R.emp ? 'Noted for the manager: ' : 'Extra: ') + num(round(l.packs - l.pending, 3))) + ' · ' + nt(l.name)));
    });
    c.appendChild(ul);
    if (R.emp && r.close_requested) c.appendChild(el('p', 'note', esc('The manager will see that the rest is not coming.')));
    var diffs = all ? [] : sent.filter(function (l) { return l.price != null && l.expected != null && Math.abs(Number(l.price) - Number(l.expected)) >= 0.005; });
    if (diffs.length) {
      var d = el('div', 'note');
      d.appendChild(el('p', '', '<b>' + esc(R.emp ? 'Prices you saw that differ (the manager reviews them):' : 'Price differences:') + '</b>'));
      var dl = el('ul', 'sumlist');
      diffs.forEach(function (l) {
        var li = el('li', '', nt(l.name) + ' · ' + esc(fmtC(l.price) + ' (expected ' + fmtC(l.expected) + ')') + ' ');
        if (!R.emp && l.vendor_item_id) li.appendChild(usePriceBtn(l.vendor_item_id, l.price));
        dl.appendChild(li);
      });
      d.appendChild(dl); c.appendChild(d);
    }
    if (!R.emp && r.total_crc != null) c.appendChild(el('p', '', '<span>' + esc('Received at cost') + '</span> <b class="mono">' + esc(fmtC(r.total_crc)) + '</b>'));
    var b = el('div', 'btns');
    if (R.emp) { b.appendChild(link('Receive another order', '#', 'btnlink solid')); }
    else {
      var vid = R.order.vendor_id;
      b.appendChild(link('Open the order', '#pedido=' + R.po, 'btnlink'));
      if (vid && FLAGS.can_pay) {
        b.appendChild(btn('Register the invoice', 'ghost', async function () { forgetFicha(vid); await openInvoice(vid, R.po); }));
        b.appendChild(btn('Register a payment', 'ghost', async function () { forgetFicha(vid); await openPay(vid, R.po); }));
      }
      if (vid) forgetFicha(vid);
    }
    c.appendChild(b);
    main.appendChild(c);
    toast(r.repeat ? 'That delivery was already saved' : full ? 'Order received, stock updated' : 'Delivery received · the rest is still on order');
  }

  /* ---------- 17) a small PDF writer (no library: lint rule 13): PDF 1.4, A4, Helvetica / Helvetica-Bold with
     WinAnsiEncoding, the standard Helvetica widths for wrapping, \ ( ) escaped, a character outside WinAnsi → «?»,
     «₡» → «CRC», several pages with «Página n de m». The same content as the print. ---------- */
  var PDF = (function () {
    /* Helvetica and Helvetica-Bold widths (1/1000 em) for the characters 32–126 */
    var WR = [278,278,355,556,556,889,667,191,333,333,389,584,278,333,278,278,556,556,556,556,556,556,556,556,556,556,278,278,584,584,584,556,
              1015,667,667,722,722,667,611,778,722,278,500,667,556,833,722,778,667,778,722,667,611,722,667,944,667,667,611,278,278,278,469,556,
              333,556,556,500,556,556,278,556,556,222,222,500,222,833,556,556,556,556,333,500,278,556,500,722,500,500,500,334,260,334,584];
    var WB = [278,333,474,556,556,889,722,238,333,333,389,584,278,333,278,278,556,556,556,556,556,556,556,556,556,556,333,333,584,584,584,611,
              975,722,722,722,722,667,611,778,722,278,556,722,611,833,722,778,667,778,722,667,611,722,667,944,667,667,611,333,278,333,584,556,
              333,556,611,556,611,556,333,611,611,278,278,556,278,889,611,611,611,611,389,556,333,611,556,778,556,556,500,389,280,389,584];
    var WIN = { '€': 128, '‚': 130, '„': 132, '…': 133, '‘': 145, '’': 146, '“': 147, '”': 148, '•': 149, '–': 150, '—': 151, '™': 153 };
    var SPEC = { 128: 556, 130: 222, 132: 333, 133: 1000, 145: 222, 146: 222, 147: 333, 148: 333, 149: 350, 150: 556, 151: 1000, 153: 1000, 160: 278, 161: 333, 162: 556, 163: 556,
                 165: 556, 167: 556, 169: 737, 170: 370, 171: 556, 174: 737, 176: 400, 177: 584, 180: 333, 183: 278, 186: 365, 187: 556, 191: 611, 215: 584, 223: 611, 247: 584 };
    /* text → WinAnsi codes (one byte each) */
    function codes(s) {
      s = String(s == null ? '' : s).replace(/₡\s?/g, 'CRC ').replace(/[  -   　]/g, ' ').replace(/[​-‍⁠﻿­]/g, '');
      var out = [];
      for (var i = 0; i < s.length; i++) {
        var ch = s.charAt(i), c = s.charCodeAt(i);
        if (c >= 0xd800 && c <= 0xdbff) { out.push(63); i++; continue; }
        if (c >= 32 && c < 127) out.push(c);
        else if (c >= 160 && c <= 255) out.push(c);
        else if (WIN[ch]) out.push(WIN[ch]);
        else if (c === 9 || c === 10 || c === 13) out.push(32);
        else out.push(63);
      }
      return out;
    }
    function cw(c, bold) {
      if (c >= 32 && c < 127) return (bold ? WB : WR)[c - 32];
      if (SPEC[c]) return SPEC[c];
      var base = String.fromCharCode(c).normalize('NFD').charCodeAt(0);
      return base >= 32 && base < 127 ? (bold ? WB : WR)[base - 32] : 556;
    }
    function width(cs, bold, size) { var w = 0; for (var i = 0; i < cs.length; i++) w += cw(cs[i], bold); return w * size / 1000; }
    function str(cs) {
      var s = '';
      for (var i = 0; i < cs.length; i++) { var c = cs[i]; s += c === 92 ? '\\\\' : c === 40 ? '\\(' : c === 41 ? '\\)' : String.fromCharCode(c); }
      return '(' + s + ')';
    }
    /* lines of at most maxW points (words; a word longer than the line is cut) */
    function wrap(text, bold, size, maxW) {
      var words = codes(text).reduce(function (a, c) { if (c === 32) a.push([]); else a[a.length - 1].push(c); return a; }, [[]]).filter(function (w) { return w.length; });
      var lines = [], cur = [];
      words.forEach(function (w) {
        while (width(w, bold, size) > maxW) {
          var k = w.length; while (k > 1 && width(w.slice(0, k), bold, size) > maxW) k--;
          if (cur.length) { lines.push(cur); cur = []; }
          lines.push(w.slice(0, k)); w = w.slice(k);
        }
        var t = cur.length ? cur.concat([32], w) : w;
        if (width(t, bold, size) <= maxW) cur = t; else { lines.push(cur); cur = w; }
      });
      if (cur.length || !lines.length) lines.push(cur);
      return lines;
    }
    function fx(n) { return (Math.round(n * 100) / 100).toString(); }
    /* a text string of the document's Info (its title): PDF readers take it as PDFDocEncoding or UTF-16BE, never
       WinAnsi (where — “ ” would show as Š ﬁ ﬂ): UTF-16BE with its byte order mark, in hex (ASCII only in the file) */
    function utf16(s) {
      s = String(s == null ? '' : s).replace(/[\u0000-\u001f\u007f]/g, ' ');
      var h = '<FEFF';
      for (var i = 0; i < s.length; i++) h += ('000' + s.charCodeAt(i).toString(16).toUpperCase()).slice(-4);
      return h + '>';
    }
    function make() {
      var pages = [], ops = null;
      return {
        page: function () { ops = []; pages.push(ops); },
        text: function (x, y, s, o) {
          o = o || {}; var size = o.size || 10, cs = Array.isArray(s) ? s : codes(s);
          if (o.right) x -= width(cs, o.bold, size); else if (o.center) x -= width(cs, o.bold, size) / 2;
          ops.push((o.color || '0.122 0.165 0.141') + ' rg BT /' + (o.bold ? 'F2' : 'F1') + ' ' + fx(size) + ' Tf 1 0 0 1 ' + fx(x) + ' ' + fx(y) + ' Tm ' + str(cs) + ' Tj ET');
        },
        rule: function (x1, y, x2, w, gray) { ops.push(fx(w || 0.5) + ' w ' + (gray || '0.7 0.7 0.7') + ' RG ' + fx(x1) + ' ' + fx(y) + ' m ' + fx(x2) + ' ' + fx(y) + ' l S'); },
        pages: pages
      };
    }
    function build(pages, title) {
      var objs = [], n = pages.length;
      objs[1] = '<< /Type /Catalog /Pages 2 0 R >>';
      var kids = []; for (var i = 0; i < n; i++) kids.push((6 + i * 2) + ' 0 R');
      objs[2] = '<< /Type /Pages /Kids [' + kids.join(' ') + '] /Count ' + n + ' >>';
      objs[3] = '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>';
      objs[4] = '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>';
      objs[5] = '<< /Title ' + utf16(title) + ' /Producer (Canopy OS) >>';
      pages.forEach(function (p, i) {
        var stream = p.join('\n');
        objs[6 + i * 2] = '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595.28 841.89] /Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents ' + (7 + i * 2) + ' 0 R >>';
        objs[7 + i * 2] = '<< /Length ' + stream.length + ' >>\nstream\n' + stream + '\nendstream';
      });
      var out = '%PDF-1.4\n%âãÏÓ\n', offs = [];
      for (var k = 1; k < objs.length; k++) { offs[k] = out.length; out += k + ' 0 obj\n' + objs[k] + '\nendobj\n'; }
      var xref = out.length;
      out += 'xref\n0 ' + objs.length + '\n0000000000 65535 f \n';
      for (var j = 1; j < objs.length; j++) out += String(offs[j]).padStart(10, '0') + ' 00000 n \n';
      out += 'trailer\n<< /Size ' + objs.length + ' /Root 1 0 R /Info 5 0 R >>\nstartxref\n' + xref + '\n%%EOF\n';
      var bytes = new Uint8Array(out.length);
      for (var b = 0; b < out.length; b++) bytes[b] = out.charCodeAt(b) & 255;
      return bytes;
    }
    var ACC = '0.118 0.294 0.200', GREY = '0.33 0.33 0.33';
    /* the order: d = docData(); prices: with the price columns and the estimated total */
    function order(d, prices) {
      var P = make(), L = 40, R = 555.28, TOP = 801, BOTTOM = 62, y = 0;
      var cols = prices ? [{ x: L, w: 196 }, { x: L + 200, w: 116 }, { x: L + 375, right: true }, { x: L + 445, right: true }, { x: R, right: true }]
                        : [{ x: L, w: 276 }, { x: L + 280, w: 160 }, { x: R, right: true }];
      var heads = prices ? ['Producto', 'Presentación', 'Cantidad', 'Precio sin IVA', 'Subtotal'] : ['Producto', 'Presentación', 'Cantidad'];
      function header(first) {
        P.page(); y = TOP;
        P.text(L, y, 'Hanging Garden Café', { bold: true, size: first ? 16 : 12, color: ACC });
        P.text(R, y, 'PEDIDO Nº ' + d.n, { bold: true, size: first ? 13 : 11, right: true });
        y -= first ? 16 : 14;
        P.text(L, y, 'Monteverde, Costa Rica', { size: 9, color: GREY });
        P.text(R, y, d.date, { size: 9.5, right: true });
        if (first && d.expected) { y -= 12; P.text(R, y, 'Entrega esperada: ' + d.expected, { size: 9.5, right: true }); }
        y -= 9; P.rule(L, y, R, 1.2, ACC); y -= 16;
        if (first) {
          var who = [d.vendor].concat([d.contact, d.phone, d.email].filter(Boolean)).join(' · ');
          wrap('Proveedor: ' + who, false, 10, R - L).forEach(function (ln) { P.text(L, y, ln, { size: 10 }); y -= 13; });
          y -= 6;
        }
        heads.forEach(function (h, i) { var c = cols[i]; P.text(c.x, y, h, { bold: true, size: 8.5, color: GREY, right: !!c.right }); });
        y -= 5; P.rule(L, y, R, 0.8, '0.55 0.55 0.55'); y -= 12;
      }
      header(true);
      d.lines.forEach(function (l) {
        var name = wrap(pname(l) + (l.vendor_code ? ' (cód. ' + l.vendor_code + ')' : ''), false, 9.5, cols[0].w);
        var pres = wrap(presEs(l), false, 9.5, cols[1].w);
        var h = Math.max(name.length, pres.length) * 11.5 + 5;
        if (y - h < BOTTOM) header(false);
        name.forEach(function (ln, i) { P.text(cols[0].x, y - i * 11.5, ln, { size: 9.5 }); });
        pres.forEach(function (ln, i) { P.text(cols[1].x, y - i * 11.5, ln, { size: 9.5 }); });
        P.text(cols[2].x, y, numEs(l.packs), { size: 9.5, right: true });
        if (prices) {
          if (l.expected_pack_price != null) P.text(cols[3].x, y, crc(l.expected_pack_price), { size: 9.5, right: true });
          if (l.line_total_est != null) P.text(cols[4].x, y, crc(l.line_total_est), { size: 9.5, right: true });
        }
        y -= h - 9; P.rule(L, y, R, 0.4); y -= 12;
      });
      var tail = [];
      if (prices) tail.push({ t: 'Total estimado (sin IVA): ' + crc(d.total), bold: true, right: true });
      if (d.note) wrap('Nota: ' + d.note, false, 10, R - L).forEach(function (ln) { tail.push({ t: ln }); });
      wrap('Por favor indique el Nº ' + d.n + ' en la factura. Gracias.', false, 9.5, R - L).forEach(function (ln) { tail.push({ t: ln, grey: true }); });
      y -= 4;
      tail.forEach(function (t, i) {
        if (y < BOTTOM) header(false);
        if (t.right) P.text(R, y, t.t, { bold: true, size: 10.5, right: true }); else P.text(L, y, t.t, { size: t.grey ? 9.5 : 10, color: t.grey ? GREY : undefined });
        y -= i === 0 && prices ? 20 : 13;
      });
      var n = P.pages.length;
      P.pages.forEach(function (ops, i) { ops.push('0.4 0.4 0.4 rg BT /F1 8 Tf 1 0 0 1 ' + fx(R - width(codes('Página ' + (i + 1) + ' de ' + n), false, 8)) + ' 30 Tm ' + str(codes('Página ' + (i + 1) + ' de ' + n)) + ' Tj ET'); });
      return build(P.pages, 'Pedido Nº ' + d.n + ' · ' + d.vendor);
    }
    return { order: order, codes: codes, width: width, wrap: wrap };
  })();
  window.HG_PROV_PDF = PDF;   /* the tests read the writer's output */

  /* ---------- 18) start ---------- */
  refreshAuth();
})();
