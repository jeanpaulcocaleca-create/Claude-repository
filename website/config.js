/* Canopy OS · which database this page talks to.
   Chosen by the web address the page was opened from, so the same files run in production, in staging and in
   tests without edits. Load it first, before supabase-js and the page script:  <script src="config.js"></script>
   The keys below are PUBLIC "anon" keys (they only allow what the database rules allow). Never put a
   service-role key, password or other secret in this file or anywhere in this repository. */
(function () {
  'use strict';
  var ENVS = {
    production: { url: 'https://nbvczarfweanoxvdqplk.supabase.co',
                  key: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5idmN6YXJmd2Vhbm94dmRxcGxrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODgxNzcxMDksImV4cCI6MjEwMzc1MzEwOX0._rzaF3tRbzZT9CIDn724O_yKE8zkYENhMDd9zrZYqhU' },
    /* the free staging project: filled in once the owner has created it (docs/DEPENDENCIES.md) */
    staging: { url: '', key: '' },
    /* automated tests only: a local stand-in for Supabase (tests/e2e/gateway.js) with a test-only key */
    local: { url: 'http://127.0.0.1:54321',
             key: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJjYW5vcHktbG9jYWwtdGVzdHMiLCJyb2xlIjoiYW5vbiIsImlhdCI6MTc2MDAwMDAwMCwiZXhwIjo0MTAyNDQ0ODAwfQ.gtdnO_4eGAyZAa4lbs2BxEF-RvQRSZ_j8WLD8G-DZc4' }
  };
  var HOSTS = {
    'hanginggardencafe.com': 'production', 'www.hanginggardencafe.com': 'production',
    'staging.hanginggardencafe.com': 'staging',
    '127.0.0.1': 'local', 'localhost': 'local'
  };
  /* staff pages (sales, money, people): they only run on a known address. Public pages (menu, website, room
     ordering, TV) fall back to production elsewhere, e.g. when a visitor uses a translation proxy. */
  var STAFF = /\/(pos|kitchen|time|home|sales|inventory|admin|reset|accounting|contabilidad)(\.html)?$/;
  var host = location.hostname, env = HOSTS[host] || 'unknown';
  var staffPage = STAFF.test(location.pathname);
  var cfg = ENVS[env] || ENVS.production;
  var blocked = env === 'unknown' && staffPage;
  if (env === 'staging' && !cfg.url) blocked = true;

  window.HG_CONFIG = Object.freeze({
    env: env,
    url: cfg.url,
    key: cfg.key,
    staffPage: staffPage,
    blocked: blocked
  });

  function notice(text, color) {
    var go = function () {
      var b = document.createElement('div');
      b.setAttribute('data-hg-env', env);
      b.style.cssText = 'position:fixed;left:8px;bottom:8px;z-index:2147483000;pointer-events:none;padding:.25rem .6rem;' +
        'border-radius:6px;font:700 12px/1.3 system-ui,sans-serif;color:#fff;background:' + color + ';opacity:.92';
      b.textContent = text;
      document.body.appendChild(b);
    };
    if (document.body) go(); else document.addEventListener('DOMContentLoaded', go);
  }
  if (blocked) {
    /* stop the page before it can talk to any database */
    document.addEventListener('DOMContentLoaded', function () {
      document.body.innerHTML = '<div style="max-width:30rem;margin:15vh auto;padding:1.5rem;font:16px/1.5 system-ui,sans-serif;' +
        'color:#1E4B33;background:#FCF8EC;border-radius:14px;text-align:center"><b>Esta copia de Canopy OS no está autorizada.</b><br>' +
        (env === 'staging' ? 'El proyecto de pruebas todavía no está configurado.' : 'Abra la caja desde hanginggardencafe.com.') + '</div>';
    });
    throw new Error('Canopy OS: environment not allowed here (' + host + ')');
  }
  if (env === 'staging') notice('PRUEBAS · no es la caja real', '#C2410C');
})();
