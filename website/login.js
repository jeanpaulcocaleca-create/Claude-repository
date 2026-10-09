/* Hanging Garden Café · staff sign-in, shared by pos, kitchen, sales, time, inventory, admin and home
   (reset.html uses the Show button only). Load it after supabase-js: <script src="login.js"></script>
   Page handler:  var res = await HG_LOGIN.signIn(db); if (res.ok) refreshAuth();

   On a tablet a login fails for reasons the page used to hide behind one sentence: a word the keyboard
   capitalised or corrected, a space after a suggested word, a saved password filled in by the tablet,
   a login that was never confirmed, too many tries from the café's connection, or no internet.
   The fields stay plain, Show lets the person read the password, and the message says which it was. */
(function () {
  'use strict';
  var MSG = {
    invalid: 'The email or the password is not right. Tap Show to check the password.',
    unconfirmed: 'This login is not activated yet. The owner must confirm it in Supabase.',
    limited: 'Too many tries. Wait 5 minutes, then try again.',
    banned: 'This login is blocked. Ask the owner.',
    offline: 'This device has no internet. Check the Wi-Fi and try again.',
    network: 'Could not reach the sign-in server. Check the Wi-Fi, and the date and time of this device.',
    server: 'The sign-in server is not answering. Wait a minute and try again.',
    disabled: 'Email sign-in is switched off in Supabase. Ask the owner.',
    captcha: 'Supabase asks for a captcha that this page does not have. The owner must switch it off.',
    other: 'That login did not work.'
  };
  var EDGE = /^[\s​-‍﻿]+|[\s​-‍﻿]+$/g;

  function why(e) {
    var c = String(e.code || '').toLowerCase(), m = String(e.message || ''), s = Number(e.status) || 0, n = e.name || '';
    if (c === 'invalid_credentials' || c === 'validation_failed' || /invalid login credentials/i.test(m)) return 'invalid';
    if (c === 'email_not_confirmed' || /email not confirmed/i.test(m)) return 'unconfirmed';
    if (c === 'over_request_rate_limit' || s === 429 || /rate limit/i.test(m)) return 'limited';
    if (c === 'user_banned' || /banned/i.test(m)) return 'banned';
    if (c === 'email_provider_disabled' || /logins are disabled/i.test(m)) return 'disabled';
    if (c === 'captcha_failed' || /captcha/i.test(m)) return 'captcha';
    if (n === 'AuthRetryableFetchError' && !s) return navigator.onLine === false ? 'offline' : 'network';
    if (n === 'AuthRetryableFetchError' || n === 'AuthUnknownError' || s >= 500) return 'server';
    return 'other';
  }

  function css() {
    if (document.querySelector('style[data-hgl]')) return;
    var s = document.createElement('style'); s.setAttribute('data-hgl', '');
    s.textContent = '.hgl-row{display:flex;gap:.4rem;align-items:stretch}.hgl-row input{flex:1 1 auto;min-width:0}' +
      'button.hgl-show{width:auto !important;flex:none !important;margin:0 !important;min-height:44px !important;padding:0 .9em !important;' +
      'background:transparent !important;color:inherit !important;border:1.5px solid rgba(120,120,110,.45) !important;border-radius:10px !important;font-weight:600 !important}' +
      'button.hgl-show:hover{background:rgba(0,0,0,.05) !important}' +
      '.hgl-clock{position:fixed;right:.7rem;bottom:.7rem;z-index:2147481500;max-width:340px;display:flex;gap:.6rem;align-items:flex-start;' +
      'background:#FFF4D6;color:#5A3E00;border:1.5px solid #E2B550;border-radius:12px;padding:.6rem .7rem .6rem .9rem;' +
      'font:600 .85rem/1.35 Figtree,system-ui,sans-serif;box-shadow:0 6px 20px rgba(8,20,13,.2)}' +
      '.hgl-clock button{all:unset;cursor:pointer;font-size:1.2rem;line-height:1;padding:0 .2rem}' +
      '@media print{.hgl-clock{display:none !important}}';
    document.head.appendChild(s);
  }
  function plain(el) {
    if (!el) return;
    el.setAttribute('autocapitalize', 'none'); el.setAttribute('autocorrect', 'off'); el.setAttribute('spellcheck', 'false');
  }
  function setShow(pw, b, show) {
    pw.type = show ? 'text' : 'password'; b.textContent = show ? 'Hide' : 'Show';
    b.setAttribute('aria-label', show ? 'Hide password' : 'Show password');
  }
  function addShow(pw) {
    if (!pw || !pw.parentNode || pw.parentNode.classList.contains('hgl-row')) return;
    css(); plain(pw);
    var row = document.createElement('div'); row.className = 'hgl-row';
    pw.parentNode.insertBefore(row, pw); row.appendChild(pw);
    var b = document.createElement('button'); b.type = 'button'; b.className = 'hgl-show'; b.setAttribute('aria-controls', pw.id);
    setShow(pw, b, false);
    b.addEventListener('click', function () { setShow(pw, b, pw.type === 'password'); pw.focus(); });
    row.appendChild(b);
  }

  var busy = false;
  async function signIn(db) {
    var em = document.getElementById('em'), pw = document.getElementById('pw'), err = document.getElementById('loginErr');
    var btn = document.querySelector('#loginForm button[type=submit]');
    if (busy) return { ok: false, reason: 'busy' };
    var email = em.value.replace(/\s+/g, '').toLowerCase(), pass = pw.value;
    em.value = email; err.classList.remove('ok'); err.textContent = '';
    busy = true; if (btn){ btn.disabled = true; btn.textContent = 'Signing in…'; }
    try {
      var r = await db.auth.signInWithPassword({ email: email, password: pass });
      var trimmed = pass.replace(EDGE, '');
      if (r.error && why(r.error) === 'invalid' && trimmed && trimmed !== pass) {   /* a space before or after: one more try without it */
        var r2 = await db.auth.signInWithPassword({ email: email, password: trimmed });
        if (!r2.error || why(r2.error) !== 'invalid') r = r2;
      }
      if (r.error) {
        var k = why(r.error);
        err.textContent = MSG[k];
        /* the technical reason, small, for whoever helps on the phone */
        var d = document.createElement('small'); d.setAttribute('data-no-translate', '');
        d.style.cssText = 'display:block;opacity:.7;margin-top:.3rem';
        d.textContent = '(' + (r.error.code || r.error.name || 'error') + (r.error.status ? ' · ' + r.error.status : '') + ')';
        err.appendChild(d);
        if (k === 'invalid') pw.focus();
        return { ok: false, reason: k, error: r.error };
      }
      pw.value = '';
      var sb = pw.parentNode.querySelector('.hgl-show'); if (sb) setShow(pw, sb, false);
      return { ok: true };
    } catch (e) {
      err.textContent = MSG.other; return { ok: false, reason: 'other', error: e };
    } finally {
      busy = false; if (btn){ btn.disabled = false; btn.textContent = 'Sign in'; }   /* English: lang.js translates it again */
    }
  }

  /* ---------- a device whose clock is off ----------
     The sign-in library decides when a token expires with the server's expiry time and this device's clock.
     A tablet whose clock (or time zone) is an hour or more ahead sees every new token as already expired,
     renews it on every request and is signed out within seconds when the server refuses one more renewal;
     one that is behind keeps an expired token and every request fails. So a new token's expiry is stored in
     this device's own time, and the page says the clock is off (times on receipts and offline orders
     come from it too). */
  var SKEW = 'hg-clock-skew', mem = {};
  var ls = (function () { try { var k = '__hg_ls'; localStorage.setItem(k, '1'); localStorage.removeItem(k); return localStorage; } catch (e) { return null; } })();
  function rawGet(k) { if (ls) { try { return ls.getItem(k); } catch (e) {} } return Object.prototype.hasOwnProperty.call(mem, k) ? mem[k] : null; }
  function rawSet(k, v) { if (ls) { try { ls.setItem(k, v); return; } catch (e) {} } mem[k] = v; }
  function rawDel(k) { if (ls) { try { ls.removeItem(k); } catch (e) {} } delete mem[k]; }
  function claims(t) {
    try { var p = t.split('.')[1].replace(/-/g, '+').replace(/_/g, '/'); while (p.length % 4) p += '='; return JSON.parse(atob(p)); } catch (e) { return null; }
  }
  var storage = {
    getItem: rawGet,
    removeItem: rawDel,
    setItem: function (k, v) {
      try {
        var s = JSON.parse(v);
        if (s && typeof s === 'object' && s.access_token && s.expires_at && s.expires_in) {
          var old = null; try { old = JSON.parse(rawGet(k) || 'null'); } catch (e) {}
          var c = claims(s.access_token), now = Math.floor(Date.now() / 1000);
          if (old && old.access_token === s.access_token && old.expires_at) s.expires_at = old.expires_at;   /* the same token saved again */
          else if (c && c.iat && c.exp && Math.abs(s.expires_in - (c.exp - c.iat)) <= 2) {                 /* a token just issued */
            var skew = now - c.iat;
            noteSkew(skew);
            if (Math.abs(skew) > 60) s.expires_at = c.exp + skew;
          }
          v = JSON.stringify(s);
        }
      } catch (e) {}
      rawSet(k, v);
    }
  };
  function noteSkew(s) {
    try { localStorage.setItem(SKEW, JSON.stringify({ s: s, at: Date.now() })); } catch (e) {}
    clockNote();
  }
  function dur(sec) {
    sec = Math.abs(sec); var h = Math.floor(sec / 3600), m = Math.round((sec % 3600) / 60);
    if (m === 60) { h++; m = 0; }
    return h ? h + ' h' + (m ? ' ' + m + ' min' : '') : m + ' min';
  }
  function clockNote() {
    var v = null; try { v = JSON.parse(localStorage.getItem(SKEW) || 'null'); } catch (e) {}
    var el = document.getElementById('hglClock');
    if (!v || Math.abs(v.s) <= 120 || Date.now() - v.at > 86400000) { if (el) el.remove(); return; }
    if (!document.body) return;
    if (!el) {
      css();
      el = document.createElement('div'); el.id = 'hglClock'; el.className = 'hgl-clock'; el.setAttribute('role', 'status');
      var t = document.createElement('span'); var x = document.createElement('button'); x.type = 'button'; x.textContent = '×';
      x.setAttribute('aria-label', 'Close'); x.addEventListener('click', function () { el.remove(); });
      el.appendChild(t); el.appendChild(x); document.body.appendChild(el);
    }
    el.firstChild.textContent = 'The clock of this device is off by ' + dur(v.s) + ' · Set the date and time to automatic in the device settings.';
  }

  /* a session that ends by itself: the sign-in box says why, so it can be fixed */
  function noteEnded(why) {
    setTimeout(function () {
      var f = document.getElementById('loginForm'), err = document.getElementById('loginErr');
      if (!f || !err || !f.offsetParent) return;
      err.classList.remove('ok');
      err.textContent = 'The session ended because it could not be renewed. Sign in again.';
      var d = document.createElement('small'); d.setAttribute('data-no-translate', '');
      d.style.cssText = 'display:block;opacity:.7;margin-top:.3rem'; d.textContent = '(' + why + ')';
      err.appendChild(d);
    }, 800);
  }

  function expireStored(url) {
    try {
      var key = 'sb-' + new URL(url).hostname.split('.')[0] + '-auth-token';   /* the library's storage key */
      var s = JSON.parse(rawGet(key) || 'null');
      if (s && s.expires_at) { s.expires_at = Math.floor(Date.now() / 1000) - 1; rawSet(key, JSON.stringify(s)); }
    } catch (e) {}
  }

  /* createClient(URL, KEY, HG_LOGIN.options(other options)) */
  function options(base) {
    var o = Object.assign({}, base || {});
    o.auth = Object.assign({ storage: storage }, o.auth || {});
    var g = Object.assign({}, o.global || {});
    var inner = g.fetch || function (a, b) { return window.fetch(a, b); };
    g.fetch = function (input, init) {
      var url = typeof input === 'string' ? input : (input && input.url) || '';
      var p = inner(input, init);
      /* the database says the token expired (the clock was changed since it was stored): renew it on the next request */
      if (/\/rest\/v1\//.test(url)) {
        p.then(function (res) {
          if (res.status !== 401) return;
          res.clone().json().then(function (b) {
            if (b && (b.code === 'PGRST301' || /jwt expired/i.test(b.message || ''))) expireStored(url);
          }, function () {});
        }, function () {});
      }
      if (/\/auth\/v1\/token\?grant_type=refresh_token/.test(url)) {
        p.then(function (res) {
          if (res.ok) return;
          res.clone().json().then(function (b) { noteEnded(((b && (b.error_code || b.code)) || 'error') + ' · ' + res.status); },
                                  function () { noteEnded(String(res.status)); });
        }, function () {});
      }
      return p;
    };
    o.global = g;
    return o;
  }

  function setup() {
    var em = document.getElementById('em');
    if (em && document.getElementById('loginForm')) { plain(em); em.setAttribute('inputmode', 'email'); }
    if (document.getElementById('loginForm')) addShow(document.getElementById('pw'));
    var le = document.getElementById('loginErr'); if (le) le.setAttribute('role', 'alert');
    clockNote();
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', setup); else setup();
  window.HG_LOGIN = { signIn: signIn, addShow: addShow, why: why, options: options, storage: storage };
})();
