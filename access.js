/* Hanging Garden Café · owner areas behind a PIN ("manager mode"), shared by the staff pages.
   Load it after supabase-js and before the page script, then create the client with
     window.supabase.createClient(URL, KEY, HG_ACCESS.options())
   so every database request from this device carries its unlock token (header x-hg-unlock).
   The database (supabase/manager-mode.sql) keeps only a hash of the token, ties it to this login,
   and opens the owner areas for 15 minutes after the PIN of an owner, GM or manager.
   Unlocking one device never unlocks another one, and an unlock belongs to the login that made it: signing out, or
   signing in with another login, takes the notice down and forgets the unlock and the people remembered (LOGIN below). */
(function () {
  'use strict';
  var KEY = 'hg-unlock', WHO = 'hg-unlock-who', LOGIN = 'hg-unlock-login', REG = 'hg-pos-reg-staff';
  var state = null, pillTimer = null, pillEl = null, uid = null, watching = [];

  /* the database's 15 minutes in this device's time: a tablet whose clock is off (login.js measures by how much,
     in seconds, device minus server) would otherwise drop the unlock at once, or keep it too long */
  function skewMs() {
    try { var v = JSON.parse(localStorage.getItem('hg-clock-skew') || 'null'); return v && typeof v.s === 'number' ? v.s * 1000 : 0; } catch (e) { return 0; }
  }
  function leftMs(until) { return new Date(until).getTime() + skewMs() - Date.now(); }
  /* the database always opens for 15 minutes: counted on this device from the moment it said yes (localUntil);
     an unlock saved by an older version of this file falls back to the server's time and the measured difference */
  function left(v) { return v.localUntil ? v.localUntil - Date.now() : leftMs(v.until); }
  function read() {
    try {
      var v = JSON.parse(localStorage.getItem(KEY) || 'null');
      if (v && v.token && v.until && left(v) > 0) return v;
    } catch (e) {}
    return null;
  }
  function save(v) { try { localStorage.setItem(KEY, JSON.stringify(v)); } catch (e) {} }
  function clear() { try { localStorage.removeItem(KEY); } catch (e) {} }

  /* the unlock and the people remembered on this device (who opened the owner areas last, who opened or closed the
     register last: REG, pos.html) belong to the login signed in when they were kept (LOGIN). With any other login, or
     nobody, signed in, they are all forgotten and the notice goes: nothing of one login shows or is offered on another */
  function loginOwner() { try { return localStorage.getItem(LOGIN) || ''; } catch (e) { return ''; } }
  function hidePill() { if (pillEl) { pillEl.remove(); pillEl = null; } clearTimeout(pillTimer); }
  function forget() {
    clear(); hidePill(); state = null;
    try { [WHO, REG, LOGIN].forEach(function (k) { localStorage.removeItem(k); }); } catch (e) {}
  }
  function onLogin(id) {
    var prev = uid;
    uid = id || null;
    if (loginOwner() !== (uid || '')) forget();
    else if (prev && prev !== uid) { hidePill(); state = null; }   /* another tab already forgot: this page's notice still goes */
    if (uid) try { localStorage.setItem(LOGIN, uid); } catch (e) {}
  }
  /* the login signed in now: its id, null when nobody is, undefined when it cannot tell (then nothing is forgotten) */
  async function loginOf(db) {
    try {
      var r = await db.auth.getSession();
      if (r.error) return undefined;
      return (r.data && r.data.session && r.data.session.user && r.data.session.user.id) || null;
    } catch (e) { return undefined; }
  }
  function watch(db) {
    if (watching.indexOf(db) > -1 || !db.auth || !db.auth.onAuthStateChange) return;
    watching.push(db);
    db.auth.onAuthStateChange(function (ev, session) {
      if (ev === 'SIGNED_OUT') onLogin(null);
      else if (session && session.user) onLogin(session.user.id);
    });
  }
  /* the person who opened last on this device, offered first in the list, only for the login that saved it */
  function lastWho() {
    if (!uid || loginOwner() !== uid) return '';
    try { return localStorage.getItem(WHO) || ''; } catch (e) { return ''; }
  }

  /* signing out ends this device's unlock on the server first (migration 0033: access_lock also ends every unlock of
     this sign-in; «sign out everywhere» ends all of this login's). A plain fetch, never db.rpc: the client is in the
     middle of signing out and would wait for itself. At most 2.5 s, and a failure never stops the sign-out. */
  function lockBeforeSignOut(url, init) {
    var m = /\/auth\/v1\/logout(\?|$)/.test(url) ? ((url.match(/[?&]scope=([a-z]+)/) || [])[1] || 'global') : null;
    if (!m || m === 'others') return null;
    var h = new Headers((init && init.headers) || {}), auth = h.get('Authorization'), key = h.get('apikey');
    if (!auth || !key) return null;
    var tok = ''; try { tok = (JSON.parse(localStorage.getItem(KEY) || 'null') || {}).token || ''; } catch (e) {}
    var hdr = { Authorization: auth, apikey: key, 'Content-Type': 'application/json' };
    if (tok) hdr['x-hg-unlock'] = tok;
    var base = url.slice(0, url.indexOf('/auth/v1/')) + '/rest/v1/rpc/';
    var calls = [fetch(base + 'access_lock', { method: 'POST', headers: hdr, body: '{}' }).catch(function () {})];
    if (m === 'global') calls.push(fetch(base + 'access_lock_all', { method: 'POST', headers: hdr, body: '{}' }).catch(function () {}));
    return Promise.race([Promise.all(calls), new Promise(function (r) { setTimeout(r, 2500); })]);
  }

  /* only database requests carry the token, never sign-in or storage requests */
  function fetchWithUnlock(input, init) {
    var url = typeof input === 'string' ? input : (input && input.url) || '';
    var first = lockBeforeSignOut(url, init);
    if (first) return first.then(function () { return fetch(input, init); });
    var v = read();
    if (v && url.indexOf('/rest/v1/') > -1) {
      var h = new Headers((init && init.headers) || (input && input.headers) || {});
      h.set('x-hg-unlock', v.token);
      init = Object.assign({}, init || {}, { headers: h });
    }
    return fetch(input, init);
  }

  function roleName(r) { return r === 'owner' ? 'Owner' : r === 'manager' ? 'Manager' : ''; }
  function hhmm(iso) { var d = new Date(iso); return String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0'); }
  function missing(err) { return /access_state|access_unlock|schema cache|could not find the function/i.test((err && err.message) || ''); }

  /* where this request stands: {level: 'owner'|'manager'|null, via, name, role, until, sales} */
  async function load(db) {
    watch(db);
    var id = await loginOf(db);
    if (id !== undefined) onLogin(id);
    var mine = uid;
    var r = await db.rpc('access_state');
    if (r.error) return missing(r.error) ? { missing: true } : { error: true };
    if (mine && uid !== mine) return r.data || {};             /* signed out, or another login, meanwhile: nothing shown */
    state = r.data || {};
    if (!state.level && read()) clear();                       /* expired or locked elsewhere */
    if (state.via !== 'pin') hidePill();
    decorateNav();
    return state;
  }
  function decorateNav() {
    if (!state) return;
    css();
    document.querySelectorAll('[data-owner]').forEach(function (a) {
      a.hidden = false;
      a.classList.toggle('hga-locked', !state.level);
      if (!state.level) a.title = 'Needs the PIN of an owner, GM or manager';
      else a.removeAttribute('title');
    });
  }

  var CSS =
    '.hga-wrap{position:fixed;inset:0;z-index:2147482000;background:rgba(20,40,28,.55);display:flex;align-items:center;justify-content:center;padding:1rem}' +
    '.hga-box{background:var(--panel,#FCF8EC);color:var(--ink,#26392C);border-radius:16px;padding:1.4rem;max-width:400px;width:100%;box-shadow:0 18px 50px rgba(8,20,13,.3);font-family:Figtree,system-ui,sans-serif}' +
    '.hga-box h2{font-family:"Playfair Display",Georgia,serif;font-weight:400;font-size:1.35rem;margin:0 0 .4rem}' +
    '.hga-box p{font-size:.9rem;color:var(--sec,#54634F);margin:.2rem 0 0;line-height:1.45}' +
    '.hga-box .hga-msg{color:var(--bad,#A8402F);margin-top:.6rem}' +
    '.hga-box label{display:block;font-size:.85rem;color:var(--sec,#54634F);margin:.9rem 0 .25rem}' +
    '.hga-box select,.hga-box input{font:inherit;color:inherit;background:#fff;border:1.5px solid var(--muted,#C9CFB6);border-radius:10px;padding:.55em .7em;width:100%;box-sizing:border-box}' +
    '.hga-box input{font-size:1.4rem;letter-spacing:.35em;text-align:center;font-family:"Spline Sans Mono",monospace}' +
    '.hga-box input[data-pin]{-webkit-text-security:disc}' +
    '.hga-box .hga-err{color:var(--bad,#A8402F);font-size:.9rem;min-height:1.2em;margin:.6rem 0 0}' +
    '.hga-box .hga-row{display:flex;gap:.6rem;margin-top:1rem}' +
    '.hga-box .hga-row>*{flex:1;min-height:46px;border-radius:10px;font:inherit;font-weight:600;cursor:pointer;display:inline-flex;align-items:center;justify-content:center;text-decoration:none}' +
    '.hga-box button.hga-go{background:var(--accent,#1E4B33);color:#fff;border:none}' +
    '.hga-box .hga-back{background:transparent;color:var(--accent,#1E4B33);border:1.5px solid var(--muted,#C9CFB6)}' +
    '.hga-pill{position:fixed;left:.7rem;bottom:.7rem;z-index:2147481000;display:flex;align-items:center;gap:.5rem;background:var(--ink,#26392C);color:#FCF8EC;border-radius:99px;padding:.35rem .4rem .35rem .9rem;font:600 .78rem/1.2 Figtree,system-ui,sans-serif;box-shadow:0 6px 20px rgba(8,20,13,.25)}' +
    '.hga-pill button{all:unset;cursor:pointer;background:#FCF8EC;color:var(--ink,#26392C);border-radius:99px;padding:.35em .8em;font-weight:700}' +
    '.hga-pill button:focus-visible{outline:2px solid var(--gold,#B98A35);outline-offset:2px}' +
    '.hga-pill.inline{position:static;box-shadow:none;padding:.2rem .25rem .2rem .7rem;font-size:.72rem}' +
    'a.hga-locked::after{content:" \\1F512";font-size:.85em}' +
    '@media print{.hga-pill,.hga-wrap{display:none !important}}';
  function css() {
    if (document.querySelector('style[data-hga]')) return;
    var s = document.createElement('style'); s.setAttribute('data-hga', ''); s.textContent = CSS; document.head.appendChild(s);
  }

  var ERR = {
    bad_pin: 'That PIN is not right.', locked: 'Too many wrong PINs. Wait 10 minutes and try again.',
    not_manager: 'Only an owner, GM or manager can open this area.', inactive: 'That person is not active on the team.',
    unknown_staff: 'Pick who is opening.', no_account: 'This login is not connected to the café yet.'
  };

  /* PIN of an owner, GM or manager -> {ok, state} or {ok:false, message} */
  async function unlock(db, staffId, pinValue) {
    var r = await db.rpc('access_unlock', { p_staff_id: staffId || null, p_pin: String(pinValue || '').trim() });
    if (r.error || !r.data || !r.data.ok) {
      return { ok: false, message: r.error ? 'Could not check the PIN. Check the connection.' : (ERR[r.data.error] || 'Could not open. Try again.') };
    }
    var id = await loginOf(db);
    if (id === undefined) id = uid;
    save({ token: r.data.token, until: r.data.until, localUntil: Date.now() + 15 * 60000 - 5000, name: r.data.name, role: r.data.role });
    try { localStorage.setItem(WHO, staffId); if (id) localStorage.setItem(LOGIN, id); } catch (e) {}
    var st = await load(db);
    if (!st || !st.level) {
      clear();
      return { ok: false, message: 'The PIN was right, but this device could not confirm it. Reload the page and try again.' };
    }
    return { ok: true, state: st };
  }

  /* the PIN screen; resolves with the new state once the owner areas are open on this device */
  function gate(db, opts) {
    opts = opts || {};
    css();
    return new Promise(function (resolve) {
      var old = document.querySelector('.hga-wrap'); if (old) old.remove();
      var wrap = document.createElement('div'); wrap.className = 'hga-wrap';
      wrap.setAttribute('role', 'dialog'); wrap.setAttribute('aria-modal', 'true'); wrap.setAttribute('aria-labelledby', 'hgaTitle');
      wrap.innerHTML =
        '<form class="hga-box" autocomplete="off">' +
          '<h2 id="hgaTitle"></h2>' +
          '<p class="hga-sub"></p>' +
          '<p class="hga-msg" hidden></p>' +
          '<label for="hgaWho">Who is opening</label><select id="hgaWho"></select>' +
          '<label for="hgaPin">PIN</label><input id="hgaPin" type="text" data-pin inputmode="numeric" maxlength="8" required' +
            ' autocomplete="off" data-1p-ignore data-lpignore="true" data-bwignore data-form-type="other">' +
          '<p class="hga-err" role="alert"></p>' +
          '<div class="hga-row"><a class="hga-back"></a><button type="submit" class="hga-go">Open</button></div>' +
        '</form>';
      wrap.querySelector('h2').textContent = opts.title || 'Owners and managers only';
      wrap.querySelector('.hga-sub').textContent = 'Type the PIN of an owner, GM or manager. It stays open on this device for 15 minutes, or until someone taps Lock.';
      if (opts.message) { var m = wrap.querySelector('.hga-msg'); m.textContent = opts.message; m.hidden = false; }
      var back = wrap.querySelector('.hga-back');
      back.textContent = opts.backLabel || 'Back to the POS'; back.href = opts.backHref || 'pos.html';
      document.body.appendChild(wrap);
      var sel = wrap.querySelector('#hgaWho'), pin = wrap.querySelector('#hgaPin'), err = wrap.querySelector('.hga-err');
      db.from('staff').select('id,name,role').eq('active', true).in('role', ['owner', 'manager']).order('name').then(function (r) {
        var list = (r && !r.error && r.data) || [];
        sel.textContent = '';
        list.forEach(function (s) { var o = document.createElement('option'); o.value = s.id; o.textContent = s.name + (s.role === 'owner' ? ' · Owner' : ' · Manager'); sel.appendChild(o); });
        if (!list.length) { var o2 = document.createElement('option'); o2.value = ''; o2.textContent = 'No owner or manager set up yet'; sel.appendChild(o2); }
        var who = lastWho();
        if (who && list.some(function (s) { return s.id === who; })) sel.value = who;
        pin.focus();
      });
      wrap.querySelector('form').addEventListener('submit', async function (e) {
        e.preventDefault();
        err.textContent = '';
        var go = wrap.querySelector('.hga-go'); go.disabled = true;
        var res = await unlock(db, sel.value, pin.value);
        pin.value = ''; go.disabled = false;
        if (!res.ok) { err.textContent = res.message; pin.focus(); return; }
        wrap.remove();
        pill(db);
        resolve(res.state);
      });
    });
  }

  /* "Owner areas open · Ana · until 10:32 · Lock", bottom left, while a PIN unlock is active.
     opts.host: put it inside that element instead (the POS top bar, so it never covers the order buttons).
     opts.soft: never reload the page (the POS keeps the open order); the links just lock again. */
  var pillOpts = {};
  function pill(db, opts) {
    css();
    pillOpts = opts || pillOpts || {};
    hidePill();
    if (!state || state.via !== 'pin' || !state.until) return;
    pillEl = document.createElement('div'); pillEl.className = 'hga-pill' + (pillOpts.host ? ' inline' : '');
    var t = document.createElement('span');
    var cur = read();
    var end = cur && cur.localUntil ? cur.localUntil : new Date(state.until).getTime() + skewMs();   /* in this device's time */
    t.textContent = 'Owner areas open · ' + (state.name || '') + ' · until ' + hhmm(new Date(end));
    var b = document.createElement('button'); b.type = 'button'; b.textContent = 'Lock';
    b.addEventListener('click', function () { lock(db); });
    pillEl.appendChild(t); pillEl.appendChild(b);
    (pillOpts.host || document.body).appendChild(pillEl);
    var ms = end - Date.now();
    if (ms > 0 && ms < 2147483000) pillTimer = setTimeout(function () {
      clear();
      if (pillOpts.soft) { load(db).then(function () { pill(db); }); } else location.reload();
    }, ms + 500);
  }

  async function lock(db) {
    try { await db.rpc('access_lock'); } catch (e) {}
    clear();
    if (pillOpts.soft) { await load(db); pill(db); } else location.reload();
  }

  window.HG_ACCESS = {
    options: function () { return { global: { fetch: fetchWithUnlock } }; },
    load: load, gate: gate, unlock: unlock, pill: pill, lock: lock, current: read, roleName: roleName, who: lastWho,
    state: function () { return state; }
  };
})();
