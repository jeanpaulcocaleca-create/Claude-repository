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
      'button.hgl-show:hover{background:rgba(0,0,0,.05) !important}';
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

  function setup() {
    var em = document.getElementById('em');
    if (em && document.getElementById('loginForm')) { plain(em); em.setAttribute('inputmode', 'email'); }
    if (document.getElementById('loginForm')) addShow(document.getElementById('pw'));
    var le = document.getElementById('loginErr'); if (le) le.setAttribute('role', 'alert');
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', setup); else setup();
  window.HG_LOGIN = { signIn: signIn, addShow: addShow, why: why };
})();
