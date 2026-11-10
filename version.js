/* Canopy OS · device version check.
   Each published page carries its build in <meta name="hg-build">; /version.json says what is published now.
   When they differ, the page reloads itself at a safe moment, so a tablet left open for days never keeps running
   an old version after a release. A page can say when it is safe with window.HG_SAFE_TO_RELOAD = function(){…}
   (the POS: no sale in progress, nothing waiting to upload), and show the notice itself with
   window.HG_VERSION_NOTICE = function(build){…}. Text is English like every page; lang.js shows it in Spanish.
   Development copies (build "__BUILD__") never reload. */
(function () {
  'use strict';
  var meta = document.querySelector('meta[name="hg-build"]');
  var mine = meta ? meta.content : '';
  var api = window.HG_VERSION = { build: mine, pending: null, check: check, tick: tick, quietMs: 20000, idleMs: 120000 };
  if (!mine || mine.indexOf('__') === 0) return;

  var EVERY = 5 * 60 * 1000, lastTouch = Date.now(), bar = null;
  ['pointerdown', 'keydown', 'touchstart'].forEach(function (ev) {
    document.addEventListener(ev, function () { lastTouch = Date.now(); }, { passive: true, capture: true });
  });

  function idle() {
    var a = document.activeElement, tag = a && a.tagName;
    if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return false;
    return Date.now() - lastTouch > api.idleMs;
  }
  function safe() {
    try {
      if (typeof window.HG_SAFE_TO_RELOAD === 'function') return !!window.HG_SAFE_TO_RELOAD() && Date.now() - lastTouch > api.quietMs;
    } catch (e) { return false; }
    return document.hidden || idle();
  }
  function reload(build) {
    // at most twice per new build on this tab: a stale cache can never cause a reload loop
    var k = 'hg-reload-' + build, n = 0;
    try { n = Number(sessionStorage.getItem(k) || 0); sessionStorage.setItem(k, String(n + 1)); } catch (e) {}
    if (n >= 2) return;
    var u = new URL(location.href);
    u.searchParams.set('v', build);            // a new address: the browser cannot answer from its old copy
    location.replace(u.toString());
  }
  function banner() {
    try { if (typeof window.HG_VERSION_NOTICE === 'function') { window.HG_VERSION_NOTICE(api.pending); return; } } catch (e) {}
    if (bar || !document.body) return;
    bar = document.createElement('div');
    bar.setAttribute('role', 'status');
    bar.style.cssText = 'position:fixed;left:50%;top:8px;transform:translateX(-50%);z-index:99999;display:flex;gap:10px;align-items:center;' +
      'padding:10px 14px;border-radius:12px;background:#1f2a24;color:#fff;font:600 14px/1.3 system-ui,sans-serif;box-shadow:0 6px 24px rgba(0,0,0,.25);max-width:calc(100% - 32px)';
    var t = document.createElement('span');
    t.textContent = 'A new version is ready. It updates by itself when you finish what you are doing.';
    var b = document.createElement('button');
    b.type = 'button'; b.textContent = 'Update now';
    b.style.cssText = 'min-height:44px;padding:0 14px;border-radius:10px;border:0;background:#fff;color:#1f2a24;font:700 14px system-ui,sans-serif;cursor:pointer';
    b.addEventListener('click', function () {
      var ok = true;
      try { if (typeof window.HG_SAFE_TO_RELOAD === 'function') ok = !!window.HG_SAFE_TO_RELOAD(); } catch (e) { ok = false; }
      if (ok) reload(api.pending);
      else t.textContent = 'Finish the sale in progress first, or wait until the pending sales are saved.';
    });
    bar.appendChild(t); bar.appendChild(b);
    document.body.appendChild(bar);
  }
  async function check() {
    if (navigator.onLine === false) return null;
    try {
      var r = await fetch('/version.json?t=' + Date.now(), { cache: 'no-store' });
      if (!r.ok) return null;
      var v = await r.json();
      if (v && v.build && v.build !== mine) { api.pending = v.build; banner(); }
      return v;
    } catch (e) { return null; }
  }
  setInterval(check, EVERY);
  function tick() { if (api.pending && safe()) { reload(api.pending); return true; } return false; }
  setInterval(tick, 15000);
  api.update = function () { return api.pending ? (reload(api.pending), true) : false; };
  document.addEventListener('visibilitychange', function () { if (!document.hidden) check(); });
  setTimeout(check, 20000);
})();
