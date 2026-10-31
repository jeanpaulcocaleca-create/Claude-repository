/* Canopy OS · pantallas.html: the owner manages the customer TVs (docs/PANTALLAS.md, migration 0036).
   Only through the 0036 functions: pantallas_estado (read), pantalla_guardar, diapositiva_guardar, diapositiva_estado.
   The server checks the owner on every call (is_true_owner: the owner's PIN on this device, or the owner login with the
   phone code) and writes every change to screen_changes; this page only helps, it never decides.
   Prices and availability are never written here: a product slide reads them from the menu on every screen read.
   Spanish only, written here: the page root (#pg) carries data-no-translate; lang.js only translates the PIN screen.
   Tests may set window.PANTALLAS_TEST = {sinRevisar: true} to send a slide without the page's checks, which proves the
   server refuses on its own what the page blocks. */
(function () {
  'use strict';

  /* ---------- 0) only on a known address, before any client exists ----------
     config.js does not list this page among the staff pages, so on an unknown address (a copy, a proxy) it would hand
     out production's address: refuse here, like config.js does for the staff pages */
  try { if (!localStorage.getItem('hg_lang')) localStorage.setItem('hg_lang', 'es'); } catch (e) {}   /* the shared PIN screen (lang.js) in Spanish */
  var CFG = window.HG_CONFIG || null;
  if (!CFG || CFG.env === 'unknown' || CFG.blocked || !CFG.url || !CFG.key) {
    document.body.innerHTML = '<div style="max-width:30rem;margin:15vh auto;padding:1.5rem;font:16px/1.5 system-ui,sans-serif;' +
      'color:#1E4B33;background:#FCF8EC;border-radius:14px;text-align:center"><b>Esta copia de Canopy OS no está autorizada.</b><br>' +
      'Abra las pantallas desde hanginggardencafe.com.</div>';
    throw new Error('Canopy OS: environment not allowed here (' + location.hostname + ')');
  }

  function $(id) { return document.getElementById(id); }
  /* a small element builder: props.text, props.class, props.on {event: fn}, booleans as properties, the rest attributes */
  function h(tag, props, kids) {
    var e = document.createElement(tag);
    Object.keys(props || {}).forEach(function (k) {
      var v = props[k];
      if (v === null || v === undefined || v === false) return;
      if (k === 'text') e.textContent = v;
      else if (k === 'class') e.className = v;
      else if (k === 'on') Object.keys(v).forEach(function (ev) { e.addEventListener(ev, v[ev]); });
      else if (v === true && k in e) e[k] = true;
      else e.setAttribute(k, v === true ? '' : String(v));
    });
    (kids || []).forEach(function (c) {
      if (c === null || c === undefined || c === false) return;
      e.appendChild(typeof c === 'string' || typeof c === 'number' ? document.createTextNode(String(c)) : c);
    });
    return e;
  }
  function clear(e) { while (e.firstChild) e.removeChild(e.firstChild); return e; }

  if (!window.supabase || !window.HG_ACCESS || !window.HG_LOGIN) {
    $('noMsg').textContent = 'No se pudo cargar la página completa. Revise la conexión y vuelva a abrirla.';
    $('noView').hidden = false; $('noOut').hidden = true;
    return;
  }
  var db = window.supabase.createClient(CFG.url, CFG.key, HG_LOGIN.options(HG_ACCESS.options()));

  /* ---------- 1) messages ---------- */
  var OFFLINE = 'Sin conexión. Revise el wifi y vuelva a intentar.';
  var MISSING = 'Falta aplicar la migración 0036 (docs/ACTIVACION-PANTALLAS.md).';
  var OWNER_ONLY = 'Solo el dueño puede cambiar las pantallas. Abra con el PIN del dueño.';
  var NO_END = 'Ponga la fecha de inicio y la de fin: una diapositiva sin fin no se publica.';
  var TEXT_MSG = {
    precio: 'Sin precios en el texto (₡, $, %, colones, dólares): el precio sale solo del menú, siempre al día.',
    combo_descuento: 'Sin combos ni descuentos (combo, descuento, 2x1, gratis, oferta, rebaja…): están reservados hasta que la Caja los cobre igual a como se anuncian.',
    largo: 'Máximo 140 letras.'
  };
  var ERR = {
    owner_only: OWNER_ONLY,
    not_found: 'Esa diapositiva ya no existe. La lista se volvió a cargar.',
    retired: 'Esa diapositiva está retirada: no se edita ni vuelve a salir. Cree una nueva.',
    dates_required: NO_END,
    text_precio: TEXT_MSG.precio,
    text_combo_descuento: TEXT_MSG.combo_descuento,
    text_largo: 'Un texto tiene más de 140 letras. Acórtelo.',
    unknown_tv: 'Esa TV no existe.', tv_apagada: 'Esa TV está apagada en Pantallas.'
  };
  var FIELD = {
    id: 'el identificador de la TV', kind: 'el tipo', name: 'el nombre', category_ids: 'las categorías',
    inches: 'el tamaño', distance_m: 'la distancia', turn: 'la posición', scale_pct: 'la escala de letra', look: 'los colores',
    page_seconds: 'los segundos por página', slide_seconds: 'los segundos por diapositiva', sold_out: 'los agotados',
    on_from: 'el horario', on_to: 'el horario', active: 'activa',
    menu_item_id: 'el producto', photo_url: 'la foto', screen_ids: 'las TV', days: 'los días',
    kicker_es: 'la línea de arriba (español)', kicker_en: 'la línea de arriba (inglés)', title_es: 'el título (español)',
    title_en: 'el título (inglés)', body_es: 'el texto (español)', body_en: 'el texto (inglés)', link: 'el código QR',
    starts_at: 'el inicio', ends_at: 'el fin', from_time: 'las horas', to_time: 'las horas', sort: 'el orden'
  };
  /* a refused check constraint, said in Spanish (detail is the database's message) */
  function detailText(d) {
    d = String(d || '');
    if (/screens_hours/.test(d)) return 'El horario necesita la hora de encender y la de apagar, distintas (o ninguna: siempre encendida).';
    if (/screen_slides_dates/.test(d)) return 'El fin debe ser después del inicio, y a lo sumo un año después.';
    if (/screen_slides_hours/.test(d)) return 'Ponga las dos horas, distintas, o ninguna (todo el día).';
    if (/screen_slides_kind/.test(d)) return 'Falta el producto, el título en español o el código QR de la invitación.';
    if (/screen_slides_days/.test(d)) return 'Revise los días.';
    if (/inches/.test(d)) return 'El tamaño va de 24 a 110 pulgadas.';
    if (/distance_m/.test(d)) return 'La distancia va de 1 a 15 metros.';
    if (/scale_pct/.test(d)) return 'La escala de letra va de 70 % a 160 %.';
    if (/page_seconds/.test(d)) return 'Los segundos por página van de 15 a 60.';
    if (/slide_seconds/.test(d)) return 'Los segundos por diapositiva van de 6 a 30.';
    if (/screens_name_check|name/.test(d)) return 'El nombre lleva de 1 a 60 letras.';
    if (/time|date|timestamp/i.test(d)) return 'Revise las fechas y las horas.';
    return 'Revise los datos.';
  }
  function isMissing(m) { return /Could not find the function|schema cache/i.test(m); }
  function isOffline(m) { return /Failed to fetch|NetworkError|Load failed|fetch failed|Network request failed|ERR_|ECONN/i.test(m) || navigator.onLine === false; }
  /* {error, data} of a call -> the sentence the owner reads */
  function errText(r) {
    if (r && r.error) {
      var m = String(r.error.message || r.error || '');
      if (isMissing(m)) return MISSING;
      if (isOffline(m)) return OFFLINE;
      if (/jwt|JWT|permission denied/.test(m)) return 'La sesión venció o no alcanza. Vuelva a ingresar.';
      return 'No se pudo completar. Vuelva a intentar. (' + (r.error.code || 'error') + ')';
    }
    var d = r && r.data;
    if (!d || typeof d !== 'object') return 'El servidor no respondió como se esperaba. Vuelva a intentar.';
    if (d.error === 'invalid') {
      if (d.field) return 'Revise ' + (FIELD[d.field] || d.field) + '.';
      return detailText(d.detail);
    }
    if (d.error === 'text_combo_descuento' && d.field === 'menu_item_id') return 'Ese producto es de Extras & Combos: no se anuncia.';
    if (/^text_/.test(d.error) && d.field) return (ERR[d.error] || 'Revise el texto.') + ' (' + (FIELD[d.field] || d.field) + ')';
    return ERR[d.error] || ('No se pudo guardar (' + d.error + ').');
  }
  var toastTimer = null;
  function toast(msg) {
    var t = $('toast'); t.textContent = msg; t.classList.add('show');
    clearTimeout(toastTimer); toastTimer = setTimeout(function () { t.classList.remove('show'); }, 2800);
  }
  function pageErr(msg) { var b = $('pageErr'); b.textContent = msg || ''; b.hidden = !msg; }

  /* ---------- 2) the rules the server applies to every text (0036, _screen_text_problem), checked while typing ---------- */
  var W0 = '(^|[^\\p{L}\\p{N}_])', W1 = '(?=$|[^\\p{L}\\p{N}_])';
  var RX_PRECIO = new RegExp('[₡¢₵€＄％﹩﹪$%]|' + W0 + '(usd|crc|col[oó]n|colones|d[oó]lar|d[oó]lares|dollars?|euros?)' + W1 +
    '|' + W0 + '\\d{1,3}[.,]\\d{3}' + W1, 'iu');
  var RX_COMBO = new RegExp(W0 + '(combos?|descuentos?|discounts?|dos por uno|tres por dos|2 for 1|two for one|bogo|gratis|gratuit[oa]s?|' +
    'de regalo|cortes[ií]a|sin (costo|cargo)|ofertas?|rebajas?|promo precio|precio especial|special price|happy hour|mitad de precio|' +
    'medio precio|half price)' + W1, 'iu');
  var RX_NXM = new RegExp(W0 + '([1-9]) *(?:x|×|por) *([1-9])' + W1, 'giu');          /* 2x1, 3×2, 2 por 1: two different numbers */
  var RX_LLEVE = new RegExp(W0 + '(lleve|llev[aá]|pague|pag[aá]) *\\d+[^\\d\\n]{0,30}' + W0 + '(pague|pag[aá]|lleve|llev[aá]) *\\d+' + W1, 'iu');
  var RX_BOGO = new RegExp(W0 + 'buy *(one|\\d+),? *(and )?get *(one|\\d+)' + W1, 'iu');
  function nxm(s) { var m, r = new RegExp(RX_NXM.source, 'giu'); while ((m = r.exec(s))) { if (m[2] !== m[3]) return true; } return false; }
  function textProblem(s) {
    s = s === null || s === undefined ? '' : String(s);
    if (!s.trim()) return null;
    if (Array.from(s.trim()).length > 140) return 'largo';      /* the page sends each text trimmed */
    if (RX_PRECIO.test(s)) return 'precio';
    if (RX_COMBO.test(s) || nxm(s) || RX_LLEVE.test(s) || RX_BOGO.test(s)) return 'combo_descuento';
    return null;
  }

  /* ---------- 3) time: the server's, in Costa Rica (UTC-6 all year) ---------- */
  var CR = 6 * 3600000, DAY = 86400000;
  var srv = null;   /* {ms, perf, wall}: the server's time when pantallas_estado answered */
  function nowMs() {
    if (!srv) return Date.now();
    var a = performance.now() - srv.perf, b = Date.now() - srv.wall;
    return srv.ms + Math.max(a, b >= 0 ? b : 0);
  }
  function cr(ms) { return new Date(ms - CR); }               /* read with getUTC* */
  /* a timestamp from the server (microseconds: some browsers read at most milliseconds) */
  function T(s) { return Date.parse(String(s || '').replace(/(\.\d{3})\d+/, '$1')); }
  function pad(n) { return String(n).padStart(2, '0'); }
  var DIAS = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
  var DIAS_LARGOS = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
  var MESES = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'set', 'oct', 'nov', 'dic'];
  function isoDay(ms) { var d = cr(ms).getUTCDay(); return d === 0 ? 7 : d; }   /* 1 lunes … 7 domingo */
  function hora(ms) { var d = cr(ms); return pad(d.getUTCHours()) + ':' + pad(d.getUTCMinutes()); }
  function fecha(ms) {
    var d = cr(ms);
    return DIAS[isoDay(ms) - 1] + ' ' + d.getUTCDate() + ' ' + MESES[d.getUTCMonth()] + ' ' + d.getUTCFullYear() + ', ' + hora(ms);
  }
  function toInput(ms) { return cr(ms).toISOString().slice(0, 16); }
  function fromInput(v) {
    if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?$/.test(v || '')) return null;
    var ms = Date.parse(v.slice(0, 16) + ':00-06:00');
    return isFinite(ms) ? ms : null;
  }
  function dayStart(ms) { return ms - ((((ms - CR) % DAY) + DAY) % DAY); }
  function minuteOf(ms) { return Math.floor((((ms - CR) % DAY) + DAY) % DAY / 60000); }
  function hm(s) { var m = /^(\d{1,2}):(\d{2})/.exec(s || ''); return m ? Number(m[1]) * 60 + Number(m[2]) : null; }
  function inHours(from, to, minute) {
    if (from === null || to === null || from === to) return true;
    return from < to ? minute >= from && minute < to : minute >= from || minute < to;   /* past midnight */
  }
  function crc(n) { return '₡' + String(Math.round(Number(n) || 0)).replace(/\B(?=(\d{3})+(?!\d))/g, ' '); }

  /* the screen's rules (pantalla_datos + Screen B): a slide is on TV tv at time t */
  function forTv(s, tv) { return !tv || !s.screen_ids || !s.screen_ids.length || s.screen_ids.indexOf(tv.id) > -1; }
  function live(s, tv, t) {
    if (s.status !== 'activa' || !forTv(s, tv)) return false;
    if (!(t >= T(s.starts_at) && t < T(s.ends_at))) return false;
    if (s.days && s.days.length && s.days.indexOf(isoDay(t)) < 0) return false;
    if (!inHours(hm(s.from_time), hm(s.to_time), minuteOf(t))) return false;
    if (s.kind === 'producto' && !(s.item && s.item.sellable)) return false;
    return true;
  }
  /* the next moment later today (Costa Rica) when it goes on: its start, or its daily hour */
  function laterToday(s, tv, t) {
    var ds = dayStart(t), de = ds + DAY, f = hm(s.from_time), c = [T(s.starts_at)];
    if (f !== null) c.push(ds + f * 60000);
    c = c.filter(function (x) { return x > t && x < de; }).sort(function (a, b) { return a - b; });
    for (var i = 0; i < c.length; i++) if (live(s, tv, c[i])) return c[i];
    return null;
  }
  /* when it goes off, if that is today */
  function offToday(s, t) {
    var ds = dayStart(t), de = ds + DAY, c = [T(s.ends_at)], to = hm(s.to_time);
    if (to !== null && hm(s.from_time) !== null) { c.push(ds + to * 60000); c.push(ds + DAY + to * 60000); }
    c = c.filter(function (x) { return x > t; }).sort(function (a, b) { return a - b; });
    /* the slide's own hours may end after midnight: that end counts; only ends_at is cut at the day's end */
    if (!c.length) return null;
    return c[0] < de || (to !== null && (c[0] - ds) % DAY === to * 60000) ? c[0] : null;
  }
  function tvOn(tv, t) {
    var a = hm(tv.on_from), b = hm(tv.on_to);
    return a === null || b === null || a === b ? true : inHours(a, b, minuteOf(t));
  }

  /* ---------- 4) sign in (as admin.html): login, phone code, the owner's PIN ---------- */
  /* login.js writes its own words in English; this page is Spanish only and lang.js does not touch it */
  var LOGIN_ES = {
    'Sign in': 'Ingresar', 'Signing in…': 'Ingresando…', 'Show': 'Mostrar', 'Hide': 'Ocultar',
    'Show password': 'Mostrar contraseña', 'Hide password': 'Ocultar contraseña',
    'The email or the password is not right. Tap Show to check the password.': 'El correo o la contraseña no son correctos. Toque Mostrar para revisar la contraseña.',
    'This login is not activated yet. The owner must confirm it in Supabase.': 'Esta cuenta todavía no está activada. El dueño debe confirmarla en Supabase.',
    'Too many tries. Wait 5 minutes, then try again.': 'Demasiados intentos. Espere 5 minutos y vuelva a intentar.',
    'This login is blocked. Ask the owner.': 'Esta cuenta está bloqueada. Consulte al dueño.',
    'This device has no internet. Check the Wi-Fi and try again.': 'Este aparato no tiene internet. Revise el wifi y vuelva a intentar.',
    'Could not reach the sign-in server. Check the Wi-Fi, and the date and time of this device.': 'No se pudo llegar al servidor de ingreso. Revise el wifi, y la fecha y la hora de este aparato.',
    'The sign-in server is not answering. Wait a minute and try again.': 'El servidor de ingreso no responde. Espere un minuto y vuelva a intentar.',
    'Email sign-in is switched off in Supabase. Ask the owner.': 'El ingreso con correo está apagado en Supabase. Consulte al dueño.',
    'Supabase asks for a captcha that this page does not have. The owner must switch it off.': 'Supabase pide un captcha que esta página no tiene. El dueño debe apagarlo.',
    'That login did not work.': 'Ese ingreso no funcionó.',
    'The session ended because it could not be renewed. Sign in again.': 'La sesión terminó porque no se pudo renovar. Ingrese de nuevo.'
  };
  function loginEs() {
    var root = $('loginView'), w = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null), n;
    while ((n = w.nextNode())) {
      var k = n.nodeValue.trim();
      if (k && Object.prototype.hasOwnProperty.call(LOGIN_ES, k)) n.nodeValue = n.nodeValue.replace(k, LOGIN_ES[k]);
    }
    root.querySelectorAll('[aria-label]').forEach(function (e) {
      var v = e.getAttribute('aria-label');
      if (Object.prototype.hasOwnProperty.call(LOGIN_ES, v)) e.setAttribute('aria-label', LOGIN_ES[v]);
    });
  }
  new MutationObserver(loginEs).observe($('loginView'), { subtree: true, childList: true, characterData: true, attributes: true, attributeFilter: ['aria-label'] });

  var ACCOUNT = null;
  async function whoami() { var r = await db.rpc('account_kind'); ACCOUNT = r.error ? null : (r.data || 'none'); return ACCOUNT; }
  async function codeNeeded() {
    try {
      var r = await db.auth.mfa.getAuthenticatorAssuranceLevel();
      return !r.error && !!r.data && r.data.nextLevel === 'aal2' && r.data.currentLevel !== 'aal2';
    } catch (e) { return false; }
  }
  async function verifyCode(code) {
    var f = await db.auth.mfa.listFactors();
    var totp = f.data && f.data.totp && f.data.totp[0];
    if (!totp) return { error: { message: 'no factor' } };
    return db.auth.mfa.challengeAndVerify({ factorId: totp.id, code: code });
  }
  /* the owner login signs out by itself after 30 minutes without a touch; the café tablet never does (its PIN lasts 15) */
  var idleTimer = null;
  function armIdle() {
    clearTimeout(idleTimer);
    if (ACCOUNT !== 'owner' && ACCOUNT !== 'owner_needs_code') return;
    idleTimer = setTimeout(async function () { await db.auth.signOut({ scope: 'local' }); location.reload(); }, 30 * 60000);
  }
  ['pointerdown', 'keydown', 'touchstart', 'scroll'].forEach(function (ev) { document.addEventListener(ev, armIdle, { passive: true }); });

  var VIEWS = ['loginView', 'noView', 'ownerOnlyView', 'appView'];
  function showOnly(id) { VIEWS.forEach(function (v) { $(v).hidden = v !== id; }); }
  function showLogin(needCode) {
    showOnly('loginView');
    $('loginForm').hidden = needCode; $('codeForm').hidden = !needCode;
    if (needCode) $('codeIn').focus();
  }
  function showNo(msg, retry) {
    forget();
    $('noMsg').textContent = msg; $('noRetry').hidden = !retry; $('noOut').hidden = false;
    showOnly('noView');
  }
  /* nothing of the screens stays on the page once the server said no */
  function forget() {
    S = null; ED = null; drafts = {}; previews = {};
    ['tvList', 'slideList', 'todayList', 'logList', 'editorHost', 'who'].forEach(function (id) { clear($(id)); });
  }
  function showOwnerOnly() { forget(); showOnly('ownerOnlyView'); }

  var gateOpen = false;
  function openGate() {
    if (gateOpen && document.querySelector('.hga-wrap')) return;
    gateOpen = true;
    HG_ACCESS.gate(db, { title: 'Pantallas · solo el dueño', message: 'Abra con el PIN del dueño.', backLabel: 'Volver a Inicio', backHref: 'home.html' })
      .then(function () { gateOpen = false; refreshAuth(); });
  }
  function closeGate() { var w = document.querySelector('.hga-wrap'); if (w) w.remove(); gateOpen = false; }

  /* one check at a time; a call meanwhile runs once more after it */
  var running = null, again = false, shown = '';
  function refreshAuth() {
    if (running) { again = true; return running; }
    running = (async function () {
      try { do { again = false; await checkAuth(); } while (again); }
      catch (e) { showNo(OFFLINE, true); }
      finally { running = null; }
    })();
    return running;
  }
  async function checkAuth() {
    var s = await db.auth.getSession();
    var sess = s.data && s.data.session;
    if (!sess) { shown = ''; closeGate(); forget(); showLogin(false); return; }
    if (await codeNeeded()) { shown = ''; forget(); showLogin(true); return; }
    await whoami();
    if (ACCOUNT === 'none') { shown = ''; showNo('Esta cuenta todavía no está conectada al café. El dueño la conecta desde Supabase; después vuelva a ingresar.'); return; }
    if (ACCOUNT === 'accountant' || ACCOUNT === 'accountant_needs_code') {
      shown = ''; showNo('Esta es la cuenta del contador. Las pantallas las cambia solo el dueño.'); return;
    }
    var st = await HG_ACCESS.load(db);
    if (st.error) { shown = ''; showNo(OFFLINE, true); return; }
    if (st.missing) { shown = ''; showNo('Faltan migraciones en la base de datos (docs/MIGRACIONES.md).', true); return; }
    if (!st.level) { shown = ''; forget(); VIEWS.forEach(function (v) { $(v).hidden = true; }); openGate(); return; }
    HG_ACCESS.pill(db);
    armIdle();
    var key = sess.user.id + '|' + st.level + '|' + (st.via || '') + '|' + (st.name || '');
    if (key === shown && S) return;                 /* a token renewed: nothing to load again */
    shown = key;
    await loadState(true);
  }

  $('loginForm').addEventListener('submit', async function (e) {
    e.preventDefault();
    var res = await HG_LOGIN.signIn(db);   /* login.js: says why a sign-in failed (put in Spanish above) */
    if (res.ok) refreshAuth();
  });
  $('codeForm').addEventListener('submit', async function (e) {
    e.preventDefault();
    var r = await verifyCode($('codeIn').value.trim());
    $('codeIn').value = '';
    if (r.error) { $('codeErr').textContent = 'Ese código no sirvió. Los códigos cambian cada 30 segundos: use el más nuevo.'; return; }
    $('codeErr').textContent = '';
    refreshAuth();
  });
  async function signOut() { shown = ''; forget(); await db.auth.signOut({ scope: 'local' }); refreshAuth(); }
  $('outBtn').addEventListener('click', signOut);
  $('noOut').addEventListener('click', signOut);
  $('noRetry').addEventListener('click', function () { shown = ''; refreshAuth(); });
  /* ends this device's unlock on the server (access_lock) and reloads: the PIN screen comes back */
  $('ownerOnlyLock').addEventListener('click', function () { $('ownerOnlyLock').disabled = true; HG_ACCESS.lock(db); });
  /* forgotten password: Supabase e-mails a link to reset.html (as admin.html; no browser dialog) */
  $('forgotBtn').addEventListener('click', async function () {
    var b = this, msg = $('loginErr'), em = ($('em').value || '').replace(/\s+/g, '').toLowerCase();
    msg.classList.remove('ok');
    if (!em) { msg.textContent = 'Escriba primero, arriba, el correo de la cuenta.'; $('em').focus(); return; }
    b.disabled = true;
    var r = await db.auth.resetPasswordForEmail(em, { redirectTo: siteDir() + 'reset.html' });
    var limited = !!(r.error && (r.error.status === 429 || r.error.code === 'over_email_send_rate_limit' || /after \d+ seconds|security purposes/i.test(r.error.message || '')));
    msg.classList.toggle('ok', !r.error);
    msg.textContent = limited ? 'Ya se envió un enlace. Espere un minuto y revise también el correo no deseado.'
      : r.error ? 'No se pudo enviar el correo. Revise la dirección y vuelva a intentar.'
      : 'Si ese correo tiene una cuenta, va en camino un enlace para poner una contraseña nueva. Revise también el correo no deseado.';
    setTimeout(function () { b.disabled = false; }, (r.error && !limited) ? 0 : 60000);
  });
  $('loginForm').addEventListener('submit', function () { $('loginErr').classList.remove('ok'); }, true);
  db.auth.onAuthStateChange(function (ev) {
    /* never call the client inside this callback (supabase-js): a moment later */
    if (ev === 'SIGNED_OUT' || ev === 'SIGNED_IN' || ev === 'MFA_CHALLENGE_VERIFIED') setTimeout(refreshAuth, 0);
  });

  /* ---------- 5) the state, always from the server ---------- */
  var S = null, BUSY = 0;
  async function loadState(first) {
    BUSY++;
    var r;
    try { r = await db.rpc('pantallas_estado'); } catch (e) { r = { error: e }; } finally { BUSY--; }
    if (r.error || !r.data) {
      var m = errText(r.error ? r : { error: { message: 'empty' } });
      if (first || !S) showNo(m, true); else pageErr(m);
      return false;
    }
    if (!r.data.ok) {
      if (r.data.error === 'owner_only') { showOwnerOnly(); return false; }
      showNo(errText(r), true); return false;
    }
    srv = { ms: T(r.data.now), perf: performance.now(), wall: Date.now() };
    S = r.data;
    ['screens', 'slides', 'changes', 'categories', 'items'].forEach(function (k) { if (!Array.isArray(S[k])) S[k] = []; });
    pageErr('');
    showOnly('appView');
    renderAll();
    return true;
  }
  function renderAll() {
    var who = $('who'); clear(who);
    var name = String(S.who || '').replace(/^owner login/, 'Ingreso del dueño');
    who.appendChild(h('i', { text: (name.trim()[0] || '?').toUpperCase() }));
    who.appendChild(h('span', { text: 'Abierto por ' + name }));
    /* on the café tablet, signing out would sign the Caja out too: the PIN's «Bloquear» closes this page there */
    $('outBtn').hidden = ACCOUNT === 'cafe';
    renderTvs(); renderSlides(); renderToday(); renderLog();
    if (ED) renderEditorTvs();
    setTab(TAB);
  }
  window.HG_SAFE_TO_RELOAD = function () { return !ED && !Object.keys(drafts).length && !BUSY; };

  /* ---------- 6) tabs ---------- */
  var TABS = ['tvs', 'slides', 'today', 'log'], TAB = 'tvs';
  try { var saved = localStorage.getItem('hg-pantallas-tab'); if (TABS.indexOf(saved) > -1) TAB = saved; } catch (e) {}
  function setTab(t) {
    TAB = TABS.indexOf(t) > -1 ? t : 'tvs';
    TABS.forEach(function (k) {
      var b = $('tab-' + k);
      b.setAttribute('aria-selected', String(k === TAB)); b.tabIndex = k === TAB ? 0 : -1;
      $('sec-' + k).hidden = k !== TAB;
    });
    if (TAB === 'today' && S) renderToday();
    if (TAB === 'tvs') document.querySelectorAll('.pv').forEach(fitPreview);   /* a frame drawn while hidden had no width */
    try { localStorage.setItem('hg-pantallas-tab', TAB); } catch (e) {}
  }
  TABS.forEach(function (k, i) {
    var b = $('tab-' + k);
    b.addEventListener('click', function () { setTab(k); });
    b.addEventListener('keydown', function (e) {
      if (e.key !== 'ArrowRight' && e.key !== 'ArrowLeft') return;
      var n = TABS[(i + (e.key === 'ArrowRight' ? 1 : TABS.length - 1)) % TABS.length];
      setTab(n); $('tab-' + n).focus();
    });
  });
  /* "now" moves: the time chips and today's list follow it */
  setInterval(function () { if (S && !document.hidden) { renderToday(); if (TAB === 'slides' && !confirming) renderSlides(); } }, 30000);

  /* ---------- 7) the TVs ---------- */
  var KIND_TV = { menu: 'El menú con precios', promos: 'Promociones: productos, la marca e invitaciones' };
  var TURN = [['no', 'Horizontal'], ['derecha', 'Vertical · el borde de arriba de la TV quedó a la izquierda'],
              ['izquierda', 'Vertical · el borde de arriba de la TV quedó a la derecha']];
  var LOOK = [['auto', 'Automáticos: claros de día, oscuros de noche'], ['dia', 'Siempre claros (día)'], ['noche', 'Siempre oscuros (noche)']];
  var SOLD = [['ocultar', 'Ocultarlos'], ['tachar', 'Mostrarlos tachados, sin precio']];
  var NUM = {
    inches: { label: 'Tamaño', unit: 'pulgadas', min: 24, max: 110, step: '0.1' },
    distance_m: { label: 'Distancia de lectura', unit: 'metros', min: 1, max: 15, step: '0.1', hint: 'Hasta el cliente más lejano que debe leer.' },
    scale_pct: { label: 'Escala de letra', unit: '%', min: 70, max: 160, step: '1', hint: '100 % = 1 cm de mayúscula por metro de distancia.' },
    page_seconds: { label: 'Segundos por página', unit: 'segundos', min: 15, max: 60, step: '1' },
    slide_seconds: { label: 'Segundos por diapositiva', unit: 'segundos', min: 6, max: 30, step: '1' }
  };
  var drafts = {}, previews = {};
  function siteDir() { return location.href.replace(/[#?].*$/, '').replace(/[^\/]*$/, ''); }
  function tvPath(tv) { return (tv.kind === 'menu' ? 'pantalla-menu' : 'pantalla-promos') + '?tv=' + encodeURIComponent(tv.id); }
  function numStr(v) { return v === null || v === undefined || v === '' ? '' : String(Number(v)); }
  /* what a card shows: the unsaved changes typed in it, or the saved TV */
  function tvForm(tv) {
    var d = drafts[tv.id];
    if (d) return d;
    return { name: tv.name || '', inches: numStr(tv.inches), distance_m: numStr(tv.distance_m), turn: tv.turn || 'no',
             scale_pct: numStr(tv.scale_pct), look: tv.look || 'auto', page_seconds: numStr(tv.page_seconds),
             slide_seconds: numStr(tv.slide_seconds), sold_out: tv.sold_out || 'ocultar', on_from: tv.on_from || '',
             on_to: tv.on_to || '', category_ids: (tv.category_ids || []).map(String), active: tv.active !== false };
  }
  function fid(tv, k) { return 'tv-' + tv.id + '-' + k; }
  function field(label, input, hint, wide) {
    return h('div', { class: wide ? 'wide' : null }, [label, input, hint ? h('p', { class: 'hint', text: hint }) : null]);
  }
  function selectOf(id, opts, val) {
    var s = h('select', { id: id });
    opts.forEach(function (o) { s.appendChild(h('option', { value: o[0], text: o[1] })); });
    s.value = val;
    return s;
  }
  function renderTvs() {
    var host = clear($('tvList'));
    if (!S.screens.length) { host.appendChild(h('p', { class: 'empty', text: 'Todavía no hay TV. Agregue una abajo.' })); return; }
    S.screens.forEach(function (tv) { host.appendChild(tvCard(tv)); });
    Object.keys(previews).forEach(function (id) {
      var tv = S.screens.filter(function (x) { return x.id === id; })[0];
      if (tv) openPreview(tv); else delete previews[id];
    });
  }
  function tvCard(tv) {
    var f = tvForm(tv), menu = tv.kind === 'menu';
    var card = h('article', { class: 'card tv', 'data-tv': tv.id });
    card.appendChild(h('h2', {}, [h('span', { text: tv.name }),
      h('span', { class: 'chip ' + (tv.active ? 'c-ok' : 'c-bad'), text: tv.active ? 'Activa' : 'Desactivada' }),
      h('span', { class: 'chip plain mono', text: tv.id })]));
    card.appendChild(h('p', { class: 'kind', text: KIND_TV[tv.kind] || tv.kind }));
    var form = h('form', { novalidate: true });
    var grid = h('div', { class: 'fields' });
    grid.appendChild(field(h('label', { for: fid(tv, 'name'), text: 'Nombre' }),
      h('input', { id: fid(tv, 'name'), maxlength: '60', value: f.name, 'data-k': 'name' }), null, true));
    ['inches', 'distance_m'].forEach(function (k) { grid.appendChild(numField(tv, k, f[k])); });
    grid.appendChild(field(h('label', { for: fid(tv, 'turn'), text: 'Posición' }), selectOf(fid(tv, 'turn'), TURN, f.turn), null, true));
    grid.appendChild(numField(tv, 'scale_pct', f.scale_pct));
    grid.appendChild(numField(tv, menu ? 'page_seconds' : 'slide_seconds', f[menu ? 'page_seconds' : 'slide_seconds']));
    grid.appendChild(field(h('label', { for: fid(tv, 'look'), text: 'Colores' }), selectOf(fid(tv, 'look'), LOOK, f.look), null, true));
    if (menu) {
      grid.appendChild(field(h('label', { for: fid(tv, 'sold_out'), text: 'Productos agotados' }), selectOf(fid(tv, 'sold_out'), SOLD, f.sold_out), null, true));
      var cats = h('div', { class: 'checks', role: 'group', 'aria-label': 'Categorías que muestra' });
      S.categories.forEach(function (c) {
        cats.appendChild(h('label', {}, [h('input', { type: 'checkbox', value: c.id, 'data-cat': '1', checked: f.category_ids.indexOf(String(c.id)) > -1 }), c.name]));
      });
      grid.appendChild(field(h('span', { class: 'lbl', text: 'Categorías que muestra' }), cats,
        'Ninguna marcada = todas. Si el menú no cabe en 2 páginas a esa distancia, elija las de la fila.', true));
    }
    grid.appendChild(field(h('label', { for: fid(tv, 'on_from'), text: 'Encendida desde' }), h('input', { id: fid(tv, 'on_from'), type: 'time', value: f.on_from })));
    grid.appendChild(field(h('label', { for: fid(tv, 'on_to'), text: 'hasta' }), h('input', { id: fid(tv, 'on_to'), type: 'time', value: f.on_to })));
    grid.appendChild(h('p', { class: 'hint wide', text: 'Hora de Costa Rica. Vacío = siempre encendida; fuera del horario la pantalla queda negra. Si «hasta» es antes que «desde», sigue después de medianoche.' }));
    grid.appendChild(h('div', { class: 'wide' }, [h('label', { class: 'line' }, [h('input', { type: 'checkbox', id: fid(tv, 'active'), checked: f.active }),
      'Activa (desactivada, la TV queda en negro)'])]));
    form.appendChild(grid);

    var addr = siteDir() + tvPath(tv);
    form.appendChild(h('div', { class: 'addr' }, [h('code', { text: addr, 'data-addr': '1' }),
      h('button', { type: 'button', class: 'ghost small', text: 'Copiar', on: { click: function () { copy(addr); } } })]));
    form.appendChild(h('p', { class: 'hint', text: 'La dirección para escribir en el navegador de esta TV (docs/INSTALACION-TV.md).' }));

    var dirty = h('span', { class: 'dirty', text: 'Cambios sin guardar', hidden: !drafts[tv.id] });
    var save = h('button', { type: 'submit', text: 'Guardar' });
    var pvBtn = h('button', { type: 'button', class: 'ghost', text: previews[tv.id] ? 'Cerrar la vista previa' : 'Vista previa', 'data-preview': '1',
      on: { click: function () { if (previews[tv.id]) closePreview(tv); else openPreview(tv); } } });
    form.appendChild(h('div', { class: 'acts' }, [dirty, h('span', { class: 'sp' }), pvBtn, save]));
    var err = h('p', { class: 'err', role: 'alert' });
    form.appendChild(err);
    form.appendChild(h('div', { class: 'preview', hidden: true }));
    form.addEventListener('input', function () { drafts[tv.id] = readTvForm(card); dirty.hidden = false; });
    form.addEventListener('change', function () { drafts[tv.id] = readTvForm(card); dirty.hidden = false; });
    form.addEventListener('submit', function (e) { e.preventDefault(); saveTv(tv, card, save, err); });
    card.appendChild(form);
    return card;
  }
  function numField(tv, k, v) {
    var n = NUM[k];
    return field(h('label', { for: fid(tv, k) }, [n.label + ' ', h('span', { class: 'range', text: '(' + n.min + ' a ' + n.max + ' ' + n.unit + ')' })]),
      h('input', { id: fid(tv, k), type: 'number', inputmode: 'decimal', min: String(n.min), max: String(n.max), step: n.step, value: v }), n.hint);
  }
  function readTvForm(card) {
    var id = card.getAttribute('data-tv'), v = {}, tv = { id: id };
    ['name', 'inches', 'distance_m', 'turn', 'scale_pct', 'look', 'page_seconds', 'slide_seconds', 'sold_out', 'on_from', 'on_to'].forEach(function (k) {
      var e = $(fid(tv, k)); v[k] = e ? e.value : '';
    });
    v.category_ids = Array.prototype.map.call(card.querySelectorAll('input[data-cat]:checked'), function (c) { return c.value; });
    v.active = $(fid(tv, 'active')).checked;
    return v;
  }
  /* the server's rules for a TV, said before sending */
  function checkTv(tv, f) {
    var bad = [];
    var name = f.name.trim();
    if (!name) bad.push(['name', 'Ponga un nombre.']);
    else if (Array.from(name).length > 60) bad.push(['name', 'El nombre lleva a lo sumo 60 letras.']);
    else if (textProblem(name)) bad.push(['name', 'El nombre: ' + TEXT_MSG[textProblem(name)]]);
    var nums = ['inches', 'distance_m', 'scale_pct', tv.kind === 'menu' ? 'page_seconds' : 'slide_seconds'];
    nums.forEach(function (k) {
      var n = NUM[k], x = Number(String(f[k]).replace(',', '.'));
      if (String(f[k]).trim() === '' || !isFinite(x) || x < n.min || x > n.max || (n.step === '1' && Math.round(x) !== x)) {
        bad.push([k, n.label + ': de ' + n.min + ' a ' + n.max + ' ' + n.unit + (n.step === '1' ? ', sin decimales' : '') + '.']);
      }
    });
    if (!!f.on_from !== !!f.on_to) bad.push([f.on_from ? 'on_to' : 'on_from', 'El horario necesita las dos horas, o ninguna (siempre encendida).']);
    else if (f.on_from && f.on_from === f.on_to) bad.push(['on_to', 'Las dos horas del horario no pueden ser iguales.']);
    return bad;
  }
  async function saveTv(tv, card, btn, err) {
    var f = readTvForm(card), bad = checkTv(tv, f);
    card.querySelectorAll('.bad').forEach(function (e) { e.classList.remove('bad'); });
    err.textContent = '';
    if (bad.length) {
      bad.forEach(function (b) { var e = $(fid(tv, b[0])); if (e) e.classList.add('bad'); });
      err.textContent = bad.map(function (b) { return b[1]; }).join(' ');
      var first = $(fid(tv, bad[0][0])); if (first) first.focus();
      return;
    }
    var p = { id: tv.id, name: f.name.trim(), inches: Number(String(f.inches).replace(',', '.')), distance_m: Number(String(f.distance_m).replace(',', '.')),
              turn: f.turn, scale_pct: Number(f.scale_pct), look: f.look, on_from: f.on_from || '', on_to: f.on_to || '', active: f.active };
    if (tv.kind === 'menu') { p.page_seconds = Number(f.page_seconds); p.sold_out = f.sold_out; p.category_ids = f.category_ids; }
    else p.slide_seconds = Number(f.slide_seconds);
    btn.disabled = true; BUSY++;
    var r;
    try { r = await db.rpc('pantalla_guardar', { p: p }); } catch (e) { r = { error: e }; } finally { BUSY--; btn.disabled = false; }
    if (r.error || !r.data || !r.data.ok) {
      if (r.data && r.data.error === 'owner_only') { showOwnerOnly(); return; }
      err.textContent = errText(r);
      if (r.data && r.data.field) { var e = $(fid(tv, r.data.field)); if (e) e.classList.add('bad'); }
      return;
    }
    delete drafts[tv.id];
    await loadState();
    toast('Guardado');
  }
  /* a new TV: its id and what it shows; everything else starts with the prudent values of 0036 */
  $('addTv').addEventListener('submit', async function (e) {
    e.preventDefault();
    var err = $('addTvErr'), id = $('newId').value.trim().toLowerCase(), kind = $('newKind').value, name = $('newName').value.trim();
    err.textContent = ''; $('newId').classList.remove('bad'); $('newName').classList.remove('bad');
    if (!/^[a-z0-9][a-z0-9-]{1,29}$/.test(id)) {
      $('newId').classList.add('bad');
      err.textContent = 'El identificador lleva de 2 a 30 minúsculas, números o guiones, y empieza con una letra o un número (por ejemplo promos-2).';
      return;
    }
    if (S.screens.some(function (x) { return x.id === id; })) { $('newId').classList.add('bad'); err.textContent = 'Ya hay una TV con ese identificador.'; return; }
    if (textProblem(name) || Array.from(name).length > 60) { $('newName').classList.add('bad'); err.textContent = 'El nombre: ' + (TEXT_MSG[textProblem(name)] || 'a lo sumo 60 letras.'); return; }
    var p = { id: id, kind: kind }; if (name) p.name = name;
    var b = $('addTvBtn'); b.disabled = true; BUSY++;
    var r;
    try { r = await db.rpc('pantalla_guardar', { p: p }); } catch (x) { r = { error: x }; } finally { BUSY--; b.disabled = false; }
    if (r.error || !r.data || !r.data.ok) {
      if (r.data && r.data.error === 'owner_only') { showOwnerOnly(); return; }
      err.textContent = errText(r); return;
    }
    $('addTv').reset();
    await loadState();
    toast('Guardado');
  });
  async function copy(text) {
    var ok = false;
    try { if (navigator.clipboard && window.isSecureContext) { await navigator.clipboard.writeText(text); ok = true; } } catch (e) {}
    if (!ok) {
      var t = h('textarea', { style: 'position:fixed;left:-9999px;top:0', readonly: true }); t.value = text;
      document.body.appendChild(t); t.select();
      try { ok = document.execCommand('copy'); } catch (e) {}
      t.remove();
    }
    toast(ok ? 'Dirección copiada' : 'No se pudo copiar: mantenga apretada la dirección para copiarla.');
  }

  /* the real TV page in a frame of 1920 x 1080, scaled to the card and turned like the TV hangs */
  function openPreview(tv) {
    var card = document.querySelector('article.tv[data-tv="' + tv.id + '"]');
    if (!card) return;
    previews[tv.id] = true;
    var box = card.querySelector('.preview'); clear(box); box.hidden = false;
    var vertical = tv.turn === 'derecha' || tv.turn === 'izquierda';
    var pv = h('div', { class: 'pv' + (vertical ? ' vertical' : ''), 'data-turn': tv.turn });
    var fr = h('iframe', { src: tvPath(tv), title: 'Vista previa de ' + tv.name, tabindex: '-1', loading: 'lazy' });
    pv.appendChild(fr); box.appendChild(pv);
    box.appendChild(h('p', { class: 'hint', text: 'La página real de la TV, con lo guardado: un cambio se ve después de guardarlo. ' +
      (vertical ? 'Girada como cuelga la TV. ' : '') + 'Fuera de su horario queda negra.' }));
    fitPreview(pv);
    var b = card.querySelector('[data-preview]'); if (b) b.textContent = 'Cerrar la vista previa';
  }
  function closePreview(tv) {
    delete previews[tv.id];
    var card = document.querySelector('article.tv[data-tv="' + tv.id + '"]'); if (!card) return;
    var box = card.querySelector('.preview'); clear(box); box.hidden = true;
    var b = card.querySelector('[data-preview]'); if (b) b.textContent = 'Vista previa';
  }
  function fitPreview(pv) {
    var turn = pv.getAttribute('data-turn'), vertical = turn === 'derecha' || turn === 'izquierda';
    var w = pv.parentNode.clientWidth - 6; if (vertical) w = Math.min(w, 294);
    if (w <= 0) return;
    var s = w / (vertical ? 1080 : 1920), fr = pv.querySelector('iframe');
    pv.style.width = (w + 6) + 'px'; pv.style.height = ((vertical ? 1920 : 1080) * s + 6) + 'px';
    /* derecha: the page turns its picture right for a TV whose top edge is on the left; the frame turns it back */
    fr.style.transform = !vertical ? 'scale(' + s + ')'
      : turn === 'derecha' ? 'translate(0px,' + (1920 * s) + 'px) rotate(-90deg) scale(' + s + ')'
      : 'translate(' + (1080 * s) + 'px,0px) rotate(90deg) scale(' + s + ')';
  }
  window.addEventListener('resize', function () { document.querySelectorAll('.pv').forEach(fitPreview); });

  /* ---------- 8) the slides ---------- */
  var KIND = { producto: 'Producto', marca: 'Marca', invitacion: 'Invitación' };
  var STATUS = { activa: ['Activa', 'c-ok'], pausada: ['Pausada', 'c-warn'], retirada: ['Retirada', 'c-mute'] };
  var LINK = [['resena', 'Reseña en Tripadvisor'], ['menu', 'El menú en el teléfono']];
  var showRetired = false, confirming = null;
  function promosTvs() { return S.screens.filter(function (x) { return x.kind === 'promos'; }); }
  function itemName(it) { return !it ? '' : it.name_es && it.name_es !== it.name ? it.name_es + ' · ' + it.name : it.name; }
  function slideTitle(s) { return s.title_es || (s.item ? itemName(s.item) : '') || '(sin título)'; }
  function slidePhoto(s) { return s.photo_url || (s.item && s.item.photo_url) || null; }
  function thumb(url, cls, none) {
    var box = h('div', { class: cls || 'ph' });
    if (url) {
      var img = h('img', { src: url, alt: '', loading: 'lazy' });
      img.addEventListener('error', function () { img.remove(); box.textContent = 'sin foto'; });
      box.appendChild(img);
    } else box.textContent = none || 'sin foto';
    return box;
  }
  function daysText(days) {
    if (!days || !days.length || days.length === 7) return 'todos los días';
    return days.slice().sort().map(function (d) { return DIAS[d - 1]; }).join(', ');
  }
  function hoursText(s) { return s.from_time && s.to_time ? 'de ' + s.from_time + ' a ' + s.to_time : 'todo el día'; }
  function tvsText(ids) {
    if (!ids || !ids.length) return 'todas las TV de promociones';
    return ids.map(function (id) { var t = S.screens.filter(function (x) { return x.id === id; })[0]; return t ? t.name : id; }).join(', ');
  }
  /* where a slide stands now, as the screens see it */
  function timeChip(s) {
    if (s.status === 'retirada') return null;
    var t = nowMs();
    if (t >= T(s.ends_at)) return ['Vencida', 'c-mute'];
    if (t < T(s.starts_at)) return ['Programada', 'c-info'];
    if (s.status !== 'activa') return null;
    if (s.kind === 'producto' && !(s.item && s.item.sellable)) return ['No sale: producto agotado o sin precio', 'c-warn'];
    if (live(s, null, t)) return ['En pantalla ahora', 'c-ok'];
    return ['Vigente · fuera de su día u hora', 'c-mute'];
  }
  function renderSlides() {
    var host = clear($('slideList')), all = S.slides;
    var kept = all.filter(function (s) { return s.status !== 'retirada'; }), gone = all.length - kept.length;
    $('nSlides').textContent = kept.length ? String(kept.length) : '';
    var sr = $('showRetired');
    sr.hidden = !gone; sr.setAttribute('aria-pressed', String(showRetired));
    sr.textContent = showRetired ? 'Ocultar las retiradas' : 'Ver las retiradas (' + gone + ')';
    var list = showRetired ? all : kept;
    if (!list.length) {
      host.appendChild(h('p', { class: 'empty', text: 'Todavía no hay diapositivas. Sin diapositivas, la TV de promociones muestra la presentación de la marca.' }));
      return;
    }
    list.forEach(function (s) { host.appendChild(slideRow(s)); });
  }
  $('showRetired').addEventListener('click', function () { showRetired = !showRetired; renderSlides(); });
  function slideRow(s) {
    var st = STATUS[s.status] || [s.status, 'c-mute'], tc = timeChip(s);
    var row = h('article', { class: 'slide ' + s.status, 'data-slide': s.id });
    row.appendChild(thumb(slidePhoto(s)));
    var body = h('div');
    var sub = s.kind === 'producto' && s.item
      ? ' · Producto: ' + itemName(s.item) + (s.item.category ? ' · ' + s.item.category : '') + ' · ' + crc(s.item.price_crc) + ' en el menú' +
        (s.item.available ? '' : ' · agotado')
      : ' · ' + (KIND[s.kind] || s.kind) + (s.kind === 'invitacion' && s.link ? ' · QR: ' + (s.link === 'resena' ? 'reseña' : 'menú') : '');
    body.appendChild(h('div', { class: 't' }, [slideTitle(s), h('small', { text: sub })]));
    body.appendChild(h('div', { class: 'chips' }, [h('span', { class: 'chip ' + st[1], 'data-status': s.status, text: st[0] }),
      tc ? h('span', { class: 'chip ' + tc[1], 'data-when': '1', text: tc[0] }) : null]));
    body.appendChild(h('div', { class: 'meta' }, [
      h('span', { text: 'Del ' + fecha(T(s.starts_at)) + ' al ' + fecha(T(s.ends_at)) }),
      h('span', { text: cap(daysText(s.days)) + ' · ' + hoursText(s) }),
      h('span', { text: 'TV: ' + tvsText(s.screen_ids) + ' · orden ' + s.sort })]));
    if (s.status === 'retirada') {
      body.appendChild(h('p', { class: 'hint', text: 'Retirada: no se edita ni vuelve a salir. Queda en el registro.' }));
    } else {
      var acts = h('div', { class: 'acts' });
      acts.appendChild(h('button', { type: 'button', class: 'ghost small', text: 'Editar', 'data-act': 'editar', on: { click: function () { openEditor(s); } } }));
      if (s.status === 'activa') acts.appendChild(h('button', { type: 'button', class: 'ghost small', text: 'Pausar', 'data-act': 'pausar', on: { click: function () { setStatus(s, 'pausada', this); } } }));
      else acts.appendChild(h('button', { type: 'button', class: 'ghost small', text: 'Reanudar', 'data-act': 'reanudar', on: { click: function () { setStatus(s, 'activa', this); } } }));
      acts.appendChild(h('button', { type: 'button', class: 'danger small', text: 'Retirar', 'data-act': 'retirar', on: { click: function () { confirming = s.id; renderSlides(); } } }));
      body.appendChild(acts);
      if (confirming === s.id) {
        body.appendChild(h('div', { class: 'confirm', role: 'alert' }, [
          h('span', { text: '¿Retirar «' + slideTitle(s) + '» para siempre? No vuelve a salir y no se puede editar; queda en el registro.' }),
          h('button', { type: 'button', class: 'danger small', text: 'Sí, retirar', 'data-act': 'confirmar', on: { click: function () { confirming = null; setStatus(s, 'retirada', this); } } }),
          h('button', { type: 'button', class: 'ghost small', text: 'No', 'data-act': 'no', on: { click: function () { confirming = null; renderSlides(); } } })]));
      }
    }
    row.appendChild(body);
    return row;
  }
  function cap(s) { return s ? s[0].toUpperCase() + s.slice(1) : s; }
  async function setStatus(s, estado, btn) {
    if (btn) btn.disabled = true;
    BUSY++;
    var r;
    try { r = await db.rpc('diapositiva_estado', { p_id: s.id, p_estado: estado }); } catch (e) { r = { error: e }; } finally { BUSY--; }
    if (r.error || !r.data || !r.data.ok) {
      if (r.data && r.data.error === 'owner_only') { showOwnerOnly(); return; }
      if (btn) btn.disabled = false;
      var m = errText(r); pageErr(m); toast(m);
      if (r.data && (r.data.error === 'not_found' || r.data.error === 'retired')) await loadState();
      return;
    }
    if (ED && ED.id === s.id && estado === 'retirada') closeEditor();
    await loadState();
    toast('Guardado');
  }
  $('newSlide').addEventListener('click', function () { openEditor(null); });

  /* ---------- 9) the slide editor ---------- */
  var ED = null;
  var TEXTS = ['kicker_es', 'kicker_en', 'title_es', 'title_en', 'body_es', 'body_en'];
  var PAIRS = [
    ['kicker', 'Línea corta de arriba', 'Ej.: Recién hecho', 'Ej.: Freshly made'],
    ['title', 'Título', 'Ej.: Café de altura de Monteverde', 'Ej.: Highland coffee from Monteverde'],
    ['body', 'Texto', 'Ej.: Tostado aquí, en Santa Elena', 'Ej.: Roasted here, in Santa Elena']
  ];
  function openEditor(s) {
    var t = Math.floor(nowMs() / 60000) * 60000;
    if (s) {
      var it = S.items.filter(function (x) { return x.id === s.menu_item_id; })[0] ||
        (s.menu_item_id ? { id: s.menu_item_id, name: (s.item && s.item.name) || 'producto', name_es: s.item && s.item.name_es,
                            category: s.item && s.item.category, price_crc: s.item ? s.item.price_crc : 0,
                            available: !!(s.item && s.item.available), photo_url: s.item && s.item.photo_url } : null);
      ED = { id: s.id, kind: s.kind, item: it, link: s.link || 'resena', photoMode: s.photo_url ? 'propia' : (s.kind === 'producto' ? 'menu' : 'ninguna'),
             photo_url: s.photo_url || null, blob: null, uploaded: null, starts: T(s.starts_at), ends: T(s.ends_at),
             startsIso: s.starts_at, endsIso: s.ends_at,
             endTouched: true, days: (s.days && s.days.length ? s.days : [1, 2, 3, 4, 5, 6, 7]).slice(), from: s.from_time || '', to: s.to_time || '',
             screens: (s.screen_ids || []).slice(), sort: s.sort, texts: {} };
      TEXTS.forEach(function (k) { ED.texts[k] = s[k] || ''; });
    } else {
      ED = { id: null, kind: 'producto', item: null, link: 'resena', photoMode: 'menu', photo_url: null, blob: null, uploaded: null,
             starts: t, ends: t + 30 * DAY, endTouched: false, days: [1, 2, 3, 4, 5, 6, 7], from: '', to: '', screens: [], sort: 100, texts: {} };
      TEXTS.forEach(function (k) { ED.texts[k] = ''; });
    }
    renderEditor();
    setTab('slides');
    var f = $('slideForm'); if (f) { f.scrollIntoView({ block: 'start' }); }
  }
  function closeEditor() { ED = null; clear($('editorHost')); }
  function renderEditor() {
    var host = clear($('editorHost'));
    var form = h('form', { class: 'card editor', id: 'slideForm', novalidate: true });
    form.appendChild(h('h2', { text: ED.id ? 'Editar la diapositiva' : 'Nueva diapositiva' }));

    /* kind */
    var kinds = h('div', { class: 'kinds' });
    [['producto', 'Un producto del menú, con su foto y su precio al día'], ['marca', 'Un mensaje de la casa'],
     ['invitacion', 'Una invitación con código QR: reseña o menú']].forEach(function (k) {
      kinds.appendChild(h('label', {}, [h('input', { type: 'radio', name: 'edKind', value: k[0], checked: ED.kind === k[0], disabled: !!ED.id,
        on: { change: function () { ED.kind = k[0]; if (!ED.blob && !ED.photo_url) ED.photoMode = k[0] === 'producto' ? 'menu' : 'ninguna'; kindChanged(); } } }),
        h('span', {}, [KIND[k[0]], h('small', { text: k[1] })])]));
    });
    form.appendChild(h('fieldset', {}, [h('legend', { text: 'Tipo' }), kinds,
      ED.id ? h('p', { class: 'hint', text: 'El tipo no cambia: para otro tipo, cree una diapositiva nueva.' }) : null]));

    /* product */
    var search = h('input', { id: 'edSearch', type: 'search', placeholder: 'Buscar en el menú: nombre, nombre en español o categoría', autocomplete: 'off' });
    search.addEventListener('input', renderPicker);
    form.appendChild(h('fieldset', { id: 'edProduct' }, [h('legend', { text: 'Producto' }),
      h('label', { for: 'edSearch', text: 'Buscar' }), search, h('div', { class: 'chosen', id: 'edChosen' }), h('div', { class: 'picker', id: 'edPicker' }),
      h('p', { class: 'hint', text: 'El nombre, la foto y el precio salen del menú en cada lectura de la TV. Si el producto se agota o no tiene precio, la diapositiva no sale. Extras & Combos nunca se anuncia.' })]));

    /* texts */
    var tf = h('fieldset', {}, [h('legend', { text: 'Textos' }),
      h('p', { class: 'rule' }, [h('b', { text: 'Sin precios, combos ni descuentos. ' }),
        'Los precios salen solos del menú y siempre al día: no los escriba (₡, $, %, colones, dólares). Los combos y los descuentos ' +
        'no se anuncian: están reservados hasta que la Caja los cobre igual a como se anuncian. Primero en español, después en inglés; ' +
        'cada texto lleva a lo sumo 140 letras.'])]);
    PAIRS.forEach(function (p) {
      var pair = h('div', { class: 'pair', id: 'pair-' + p[0] });
      [['es', 'español', 2], ['en', 'inglés', 3]].forEach(function (l) {
        var k = p[0] + '_' + l[0], id = 'ed-' + k;
        var inp = p[0] === 'body' ? h('textarea', { id: id, rows: '2', placeholder: p[l[2]] }) : h('input', { id: id, placeholder: p[l[2]], autocomplete: 'off' });
        inp.value = ED.texts[k];
        inp.addEventListener('input', function () { ED.texts[k] = inp.value; checkTexts(); });
        pair.appendChild(h('div', {}, [h('label', { for: id }, [p[1] + ' (' + l[1] + ')', h('span', { class: 'cnt', id: 'cnt-' + k })]), inp,
          h('p', { class: 'err', id: 'err-' + k, role: 'alert' })]));
      });
      tf.appendChild(pair);
    });
    tf.appendChild(h('p', { class: 'hint', id: 'edTitleHint' }));
    form.appendChild(tf);

    /* QR */
    var link = selectOf('edLink', LINK, ED.link);
    link.addEventListener('change', function () { ED.link = link.value; });
    form.appendChild(h('fieldset', { id: 'edLinkBox' }, [h('legend', { text: 'Código QR' }), h('label', { for: 'edLink', text: 'A dónde lleva' }), link,
      h('p', { class: 'hint', text: 'El QR solo sirve si el cliente está a 3 m o menos de la TV.' })]));

    /* photo */
    form.appendChild(h('fieldset', { id: 'edPhotoBox' }, [h('legend', { text: 'Foto' }), h('div', { class: 'checks', id: 'edPhotoModes' }),
      h('div', { class: 'photo', id: 'edPhoto' }), h('p', { class: 'err', id: 'edPhotoMsg', role: 'status' }),
      h('p', { class: 'hint', text: 'Una foto subida se achica en este aparato a 1600 px de ancho como máximo (JPEG) antes de subirla. Máximo 8 MB.' })]));

    /* when */
    var start = h('input', { id: 'edStart', type: 'datetime-local', required: true, value: toInput(ED.starts) });
    var end = h('input', { id: 'edEnd', type: 'datetime-local', required: true, value: toInput(ED.ends) });
    start.addEventListener('input', function () {
      var a = fromInput(start.value);
      if (a !== null && !ED.endTouched && !ED.id) end.value = toInput(a + 30 * DAY);
    });
    end.addEventListener('input', function () { ED.endTouched = true; });
    var days = h('div', { class: 'days', role: 'group', 'aria-label': 'Días' });
    DIAS.forEach(function (d, i) {
      var b = h('button', { type: 'button', text: d, title: DIAS_LARGOS[i], 'aria-label': DIAS_LARGOS[i], 'data-day': String(i + 1), 'aria-pressed': String(ED.days.indexOf(i + 1) > -1) });
      b.addEventListener('click', function () {
        var on = ED.days.indexOf(i + 1) > -1;
        ED.days = on ? ED.days.filter(function (x) { return x !== i + 1; }) : ED.days.concat([i + 1]).sort();
        b.setAttribute('aria-pressed', String(!on));
      });
      days.appendChild(b);
    });
    var from = h('input', { id: 'edFrom', type: 'time', value: ED.from }), to = h('input', { id: 'edTo', type: 'time', value: ED.to });
    form.appendChild(h('fieldset', {}, [h('legend', { text: 'Cuándo sale' }),
      h('div', { class: 'fields' }, [
        field(h('label', { for: 'edStart', text: 'Desde (obligatorio)' }), start),
        field(h('label', { for: 'edEnd', text: 'Hasta (obligatorio)' }), end),
        h('p', { class: 'hint wide', text: 'Hora de Costa Rica. Toda diapositiva tiene inicio y fin: sin fin no se publica. A lo sumo un año; ' +
          'para una de todo el año, ponga el fin a 12 meses y renuévela. Vencida, sale sola de la pantalla, también sin internet.' }),
        field(h('span', { class: 'lbl', text: 'Días' }), days, null, true),
        field(h('label', { for: 'edFrom', text: 'De las' }), from),
        field(h('label', { for: 'edTo', text: 'a las' }), to),
        h('p', { class: 'hint wide', text: 'Vacías = todo el día. Si «a las» es antes que «de las», sigue después de medianoche.' })])]));

    /* TVs and order */
    form.appendChild(h('fieldset', {}, [h('legend', { text: 'En qué TV' }), h('div', { class: 'checks', id: 'edTvs', role: 'group', 'aria-label': 'En qué TV' }),
      h('p', { class: 'hint', text: 'Ninguna marcada = todas las TV de promociones, también las que se agreguen después.' })]));
    var sort = h('input', { id: 'edSort', type: 'number', inputmode: 'numeric', step: '1', min: '0', max: '9999', value: String(ED.sort) });
    form.appendChild(h('fieldset', {}, [h('legend', { text: 'Orden' }), h('div', { class: 'fields' }, [
      field(h('label', { for: 'edSort', text: 'Orden (menor sale primero)' }), sort),
      ED.id ? null : h('div', {}, [h('span', { class: 'lbl', text: 'Al guardar' }),
        h('label', { class: 'line' }, [h('input', { type: 'checkbox', id: 'edPaused' }), 'Guardarla en pausa (todavía no sale)'])])])]));

    form.appendChild(h('div', { class: 'acts' }, [h('button', { type: 'submit', id: 'edSave', text: 'Guardar' }),
      h('button', { type: 'button', class: 'ghost', id: 'edCancel', text: 'Cancelar', on: { click: function () { dropUploaded(); closeEditor(); } } }), h('span', { class: 'sp' })]));
    form.appendChild(h('p', { class: 'err', id: 'edErr', role: 'alert' }));
    form.addEventListener('submit', function (e) { e.preventDefault(); saveSlide(); });
    host.appendChild(form);
    renderEditorTvs(); kindChanged();
  }
  function renderEditorTvs() {
    var box = $('edTvs'); if (!box) return;
    clear(box);
    promosTvs().forEach(function (tv) {
      box.appendChild(h('label', {}, [h('input', { type: 'checkbox', value: tv.id, 'data-tv': '1', checked: ED.screens.indexOf(tv.id) > -1,
        on: { change: function () { ED.screens = Array.prototype.map.call(box.querySelectorAll('input:checked'), function (c) { return c.value; }); } } }),
        tv.name + (tv.active ? '' : ' (desactivada)')]));
    });
    if (!box.firstChild) box.appendChild(h('span', { class: 'hint', text: 'No hay TV de promociones.' }));
  }
  function kindChanged() {
    var k = ED.kind;
    $('edProduct').hidden = k !== 'producto';
    $('edLinkBox').hidden = k !== 'invitacion';
    /* a product slide always shows the menu's name (so it matches the till): no title to type */
    $('pair-title').hidden = k === 'producto';
    if (k === 'producto') { ED.texts.title_es = ''; ED.texts.title_en = ''; $('ed-title_es').value = ''; $('ed-title_en').value = ''; }
    $('edTitleHint').textContent = k === 'producto' ? 'El título es el nombre del producto en el menú, como lo cobra la Caja.'
      : 'El título en español es obligatorio.';
    renderPicker(); renderPhoto(); checkTexts();
  }
  function norm(s) { return String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase(); }
  function renderPicker() {
    var box = $('edPicker'); if (!box || ED.kind !== 'producto') return;
    clear(box);
    var q = norm($('edSearch').value).split(/\s+/).filter(Boolean), n = 0;
    S.items.filter(function (it) { return it.category !== 'Extras & Combos'; }).forEach(function (it) {
      var hay = norm([it.name, it.name_es, it.category].join(' '));
      if (q.some(function (w) { return hay.indexOf(w) < 0; }) || n >= 80) return;
      n++;
      box.appendChild(h('button', { type: 'button', class: 'pick', 'data-item': it.id, 'aria-pressed': String(!!ED.item && ED.item.id === it.id),
        on: { click: function () { ED.item = it; renderPicker(); renderPhoto(); } } },
        [thumb(it.photo_url), h('span', {}, [h('b', { text: itemName(it) }),
          h('small', { text: (it.category || '') + ' · ' + crc(it.price_crc) + (it.available ? '' : ' · agotado') })])]));
    });
    if (!n) box.appendChild(h('p', { class: 'hint', text: 'Nada en el menú con esa búsqueda.' }));
    var ch = clear($('edChosen'));
    ch.appendChild(ED.item ? h('span', {}, ['Elegido: ', h('b', { text: itemName(ED.item) }), ' · ' + (ED.item.category || '') + ' · ' + crc(ED.item.price_crc) +
      ' (precio del menú; la TV lo lee al día)' + (ED.item.available ? '' : ' · agotado: no sale hasta que vuelva')]) : h('span', { class: 'hint', text: 'Ningún producto elegido todavía.' }));
  }
  function renderPhoto() {
    var modes = $('edPhotoModes'), box = $('edPhoto'); if (!modes) return;
    clear(modes); clear(box);
    var opts = ED.kind === 'producto' ? [['menu', 'La foto del producto en el menú'], ['propia', 'Otra foto']] : [['ninguna', 'Sin foto'], ['propia', 'Una foto']];
    if (!opts.some(function (o) { return o[0] === ED.photoMode; })) ED.photoMode = opts[0][0];
    opts.forEach(function (o) {
      modes.appendChild(h('label', {}, [h('input', { type: 'radio', name: 'edPhotoMode', value: o[0], checked: ED.photoMode === o[0],
        on: { change: function () { ED.photoMode = o[0]; renderPhoto(); } } }), o[1]]));
    });
    if (ED.photoMode === 'menu') {
      box.appendChild(thumb(ED.item && ED.item.photo_url, 'ph', ED.item ? 'el producto no tiene foto' : 'elija el producto'));
    } else if (ED.photoMode === 'propia') {
      var url = ED.blob ? ED.blobUrl : ED.photo_url;
      box.appendChild(thumb(url, 'ph', 'ninguna todavía'));
      box.appendChild(h('button', { type: 'button', class: 'ghost small', id: 'edPick', text: url ? 'Cambiar la foto' : 'Elegir una foto…',
        on: { click: function () { $('photoFile').click(); } } }));
    }
  }
  /* counters and the live check of every text, as the server will check it */
  function checkTexts() {
    var any = false;
    TEXTS.forEach(function (k) {
      var inp = $('ed-' + k); if (!inp) return;
      var v = inp.value, n = Array.from(v.trim()).length, p = textProblem(v);
      var c = $('cnt-' + k); c.textContent = n + '/140'; c.classList.toggle('over', n > 140);
      $('err-' + k).textContent = p ? TEXT_MSG[p] : '';
      inp.classList.toggle('bad', !!p);
      if (p) any = true;
    });
    var save = $('edSave'); if (save) save.disabled = any;
    return !any;
  }
  /* the start or the end as typed: {ms, iso} or null. A date left as it was stays exactly what the server sent (the
     field shows minutes, the server keeps seconds): editing a text never moves a slide's dates */
  function edDate(which) {
    var v = $(which === 'start' ? 'edStart' : 'edEnd').value, ms = fromInput(v);
    if (ms === null) return null;
    var iso = ED[which + 'sIso'], was = ED[which + 's'];
    if (iso && v === toInput(was)) return { ms: T(iso), iso: iso };
    return { ms: ms, iso: new Date(ms).toISOString() };
  }
  /* everything the server requires, said before sending */
  function checkSlide() {
    var bad = [];
    if (!checkTexts()) bad.push(['', 'Corrija los textos marcados.']);
    if (ED.kind === 'producto' && !ED.item) bad.push(['edSearch', 'Elija el producto.']);
    if (ED.kind !== 'producto' && !$('ed-title_es').value.trim()) bad.push(['ed-title_es', 'Ponga el título en español.']);
    if (ED.kind === 'invitacion' && !ED.link) bad.push(['edLink', 'Elija a dónde lleva el código QR.']);
    if (ED.photoMode === 'propia' && !ED.blob && !ED.photo_url) bad.push(['edPick', 'Elija la foto, o marque la otra opción.']);
    var da = edDate('start'), db2 = edDate('end'), a = da && da.ms, b = db2 && db2.ms;
    if (da === null || db2 === null) bad.push([da === null ? 'edStart' : 'edEnd', NO_END]);
    else if (b <= a) bad.push(['edEnd', 'El fin debe ser después del inicio.']);
    else if (b > a + 366 * DAY) bad.push(['edEnd', 'A lo sumo un año entre el inicio y el fin.']);
    if (!ED.days.length) bad.push(['', 'Elija al menos un día.']);
    var f = $('edFrom').value, t = $('edTo').value;
    if (!!f !== !!t) bad.push([f ? 'edTo' : 'edFrom', 'Ponga las dos horas, o ninguna (todo el día).']);
    else if (f && f === t) bad.push(['edTo', 'Las dos horas no pueden ser iguales.']);
    var so = $('edSort').value.trim();
    if (so !== '' && !/^\d{1,4}$/.test(so)) bad.push(['edSort', 'El orden es un número entero de 0 a 9999.']);
    return bad;
  }
  function payload() {
    var p = { kind: ED.kind };
    if (ED.id) p.id = ED.id;
    if (ED.kind === 'producto') p.menu_item_id = ED.item ? ED.item.id : '';
    TEXTS.forEach(function (k) { p[k] = $('ed-' + k).value.trim(); });
    p.link = ED.kind === 'invitacion' ? (ED.link || '') : '';
    p.photo_url = ED.photoMode === 'propia' ? (ED.uploaded || (ED.blob ? '' : ED.photo_url) || '') : '';
    var a = edDate('start'), b = edDate('end');
    p.starts_at = a === null ? '' : a.iso; p.ends_at = b === null ? '' : b.iso;
    p.days = ED.days.slice().sort();               /* all seven: the server keeps "every day" */
    p.from_time = $('edFrom').value || ''; p.to_time = $('edTo').value || '';
    p.screen_ids = ED.screens.slice();              /* none: every promotions TV */
    var so = parseInt($('edSort').value, 10); p.sort = isFinite(so) ? so : 100;
    if (!ED.id && $('edPaused') && $('edPaused').checked) p.status = 'pausada';
    return p;
  }
  var saving = false;
  async function saveSlide() {
    if (saving || !ED) return;
    var err = $('edErr'), test = window.PANTALLAS_TEST || {};
    document.querySelectorAll('#slideForm .bad').forEach(function (e) { if (!/^ed-/.test(e.id)) e.classList.remove('bad'); });
    err.textContent = '';
    if (!test.sinRevisar) {
      var bad = checkSlide();
      if (bad.length) {
        bad.forEach(function (b) { var e = b[0] && $(b[0]); if (e) e.classList.add('bad'); });
        err.textContent = bad.map(function (b) { return b[1]; }).join(' ');
        var first = bad[0][0] && $(bad[0][0]); if (first && first.focus) first.focus();
        return;
      }
    }
    saving = true; BUSY++;
    var btn = $('edSave'); btn.disabled = true; btn.textContent = 'Guardando…';
    try {
      if (ED.photoMode === 'propia' && ED.blob && !ED.uploaded) {
        $('edPhotoMsg').classList.remove('ok'); $('edPhotoMsg').textContent = 'Subiendo la foto…';
        try { ED.uploaded = await uploadPhoto(ED.blob); $('edPhotoMsg').textContent = ''; }
        catch (e) {
          var m = String((e && e.message) || e || '');
          err.textContent = isOffline(m) ? OFFLINE : /row-level security|Unauthorized|403|permission/i.test(m)
            ? 'No se pudo subir la foto: el PIN venció o no alcanza. Vuelva a abrir con el PIN del dueño.'
            : 'No se pudo subir la foto. Vuelva a intentar.';
          $('edPhotoMsg').textContent = '';
          return;
        }
      }
      var r;
      try { r = await db.rpc('diapositiva_guardar', { p: payload() }); } catch (e) { r = { error: e }; }
      if (r.error || !r.data || !r.data.ok) {
        if (r.data && r.data.error === 'owner_only') { showOwnerOnly(); return; }
        err.textContent = errText(r);
        var fld = r.data && r.data.field;
        var map = { menu_item_id: 'edSearch', link: 'edLink', sort: 'edSort', photo_url: 'edPick' };
        var e2 = fld && ($('ed-' + fld) || $(map[fld]));
        if (e2) e2.classList.add('bad');
        if (r.data && r.data.error === 'dates_required') { $('edEnd').classList.add('bad'); }
        await dropUploaded();
        if (r.data && (r.data.error === 'not_found' || r.data.error === 'retired')) { closeEditor(); toast(err.textContent); await loadState(); }
        return;
      }
      ED.uploadedPath = null;          /* the slide keeps it */
      closeEditor();
      await loadState();
      toast('Guardado');
    } finally {
      saving = false; BUSY--;
      var b2 = $('edSave'); if (b2) { b2.textContent = 'Guardar'; checkTexts(); }
    }
  }

  /* ---------- 10) a photo: made smaller here, then kept in Storage (menu-photos/pantallas/) ---------- */
  var MAX_BYTES = 8 * 1024 * 1024, MAX_W = 1600, MAX_H = 2400;
  $('photoFile').addEventListener('change', async function () {
    var f = this.files && this.files[0], msg = $('edPhotoMsg');
    this.value = '';
    if (!f || !ED || !msg) return;
    msg.classList.remove('ok');
    if (f.size > MAX_BYTES) { msg.textContent = 'La foto pesa más de 8 MB. Elija una más liviana.'; return; }
    if (f.type && !/^image\//.test(f.type)) { msg.textContent = 'Ese archivo no es una foto.'; return; }
    msg.textContent = 'Preparando la foto…';
    var out;
    try { out = await shrink(f); } catch (e) { msg.textContent = 'No se pudo leer esa foto. Pruebe con otra (JPEG o PNG).'; return; }
    if (!ED) return;
    if (ED.blobUrl) URL.revokeObjectURL(ED.blobUrl);
    ED.blob = out.blob; ED.blobUrl = URL.createObjectURL(out.blob); ED.uploaded = null; ED.photoMode = 'propia';
    renderPhoto();
    msg.classList.add('ok');
    msg.textContent = 'Lista: ' + out.w + ' × ' + out.h + ' px, ' + Math.max(1, Math.round(out.blob.size / 1024)) + ' KB. Se sube al guardar.';
  });
  async function shrink(file) {
    var url = URL.createObjectURL(file);
    try {
      var img = await new Promise(function (ok, no) { var i = new Image(); i.onload = function () { ok(i); }; i.onerror = no; i.src = url; });
      var w = img.naturalWidth, hh = img.naturalHeight;
      if (!w || !hh) throw new Error('empty image');
      var s = Math.min(1, MAX_W / w, MAX_H / hh), cw = Math.max(1, Math.round(w * s)), ch = Math.max(1, Math.round(hh * s));
      var c = document.createElement('canvas'); c.width = cw; c.height = ch;
      var x = c.getContext('2d');
      x.fillStyle = '#FFFFFF'; x.fillRect(0, 0, cw, ch);           /* JPEG has no transparency */
      x.imageSmoothingEnabled = true; x.imageSmoothingQuality = 'high';
      x.drawImage(img, 0, 0, cw, ch);
      var blob = await new Promise(function (ok) { c.toBlob(ok, 'image/jpeg', 0.82); });
      if (!blob) throw new Error('no jpeg');
      return { blob: blob, w: cw, h: ch };
    } finally { URL.revokeObjectURL(url); }
  }
  function uuid() {
    if (window.crypto && crypto.randomUUID) return crypto.randomUUID();
    var b = crypto.getRandomValues(new Uint8Array(16)); b[6] = (b[6] & 15) | 64; b[8] = (b[8] & 63) | 128;
    var x = Array.prototype.map.call(b, function (v) { return (v + 256).toString(16).slice(1); }).join('');
    return x.slice(0, 8) + '-' + x.slice(8, 12) + '-' + x.slice(12, 16) + '-' + x.slice(16, 20) + '-' + x.slice(20);
  }
  async function uploadPhoto(blob) {
    var path = 'pantallas/' + uuid() + '.jpg';
    var up = await db.storage.from('menu-photos').upload(path, blob, { upsert: false, contentType: 'image/jpeg' });
    if (up.error) throw up.error;
    ED.uploadedPath = path;
    return db.storage.from('menu-photos').getPublicUrl(path).data.publicUrl;
  }
  /* a photo uploaded for a slide the server did not accept (or the owner gave up on) is taken away: no orphan file */
  async function dropUploaded() {
    if (!ED || !ED.uploadedPath) return;
    var path = ED.uploadedPath; ED.uploadedPath = null; ED.uploaded = null;
    try { await db.storage.from('menu-photos').remove([path]); } catch (e) {}
  }

  /* ---------- 11) today on each promotions TV ---------- */
  function renderToday() {
    var host = clear($('todayList')), tvs = promosTvs(), t = nowMs();
    if (!tvs.length) { host.appendChild(h('p', { class: 'empty', text: 'No hay TV de promociones.' })); return; }
    tvs.forEach(function (tv) {
      var card = h('article', { class: 'card today', 'data-today': tv.id });
      var on = tvOn(tv, t), chip = !tv.active ? ['Desactivada', 'c-bad']
        : !tv.on_from ? ['Encendida siempre', 'c-ok'] : on ? ['Encendida ahora (' + tv.on_from + '–' + tv.on_to + ')', 'c-ok']
        : ['Apagada por su horario (' + tv.on_from + '–' + tv.on_to + ')', 'c-mute'];
      card.appendChild(h('h2', {}, [h('span', { text: tv.name }), h('span', { class: 'chip ' + chip[1], text: chip[0] })]));
      card.appendChild(h('p', { class: 'hint', text: 'Hoy ' + fecha(t) + ' (hora del servidor, Costa Rica).' }));
      var mine = S.slides.filter(function (s) { return s.status === 'activa' && forTv(s, tv); });
      var now = mine.filter(function (s) { return live(s, tv, t); });
      var later = mine.map(function (s) { return { s: s, at: laterToday(s, tv, t) }; }).filter(function (x) { return x.at; })
        .sort(function (a, b) { return a.at - b.at; });
      card.appendChild(h('h3', { text: 'Ahora' }));
      if (now.length) {
        card.appendChild(h('ol', { 'data-list': 'ahora' }, now.map(function (s) {
          var off = offToday(s, t);
          return h('li', { 'data-slide': s.id }, [h('b', { text: slideTitle(s) }), h('span', { text: KIND[s.kind] + (off ? ' · hasta las ' + hora(off) : ' · todo el día') })]);
        })));
      } else card.appendChild(h('p', { class: 'none', text: 'Ninguna: la TV muestra la presentación de la marca.' }));
      card.appendChild(h('h3', { text: 'Más tarde hoy' }));
      if (later.length) {
        card.appendChild(h('ol', { 'data-list': 'luego' }, later.map(function (x) {
          return h('li', { 'data-slide': x.s.id }, [h('b', { text: slideTitle(x.s) }), h('span', { text: KIND[x.s.kind] + ' · desde las ' + hora(x.at) })]);
        })));
      } else card.appendChild(h('p', { class: 'none', text: 'Nada más hoy.' }));
      if (!tv.active || !on) card.appendChild(h('p', { class: 'hint', text: !tv.active ? 'Desactivada, esta TV no muestra nada de esto.' : 'Mientras esté apagada por su horario, no se ve nada.' }));
      host.appendChild(card);
    });
  }

  /* ---------- 12) the change log ---------- */
  var ACTION = { crear: 'Creó', cambiar: 'Cambió', pausar: 'Pausó', reanudar: 'Reanudó', retirar: 'Retiró' };
  var LABEL = {
    name: 'Nombre', kind: 'Tipo', inches: 'Tamaño (pulgadas)', distance_m: 'Distancia (m)', turn: 'Posición', scale_pct: 'Escala de letra (%)',
    look: 'Colores', page_seconds: 'Segundos por página', slide_seconds: 'Segundos por diapositiva', category_ids: 'Categorías',
    sold_out: 'Agotados', on_from: 'Encendida desde', on_to: 'Encendida hasta', active: 'Activa', status: 'Estado',
    menu_item_id: 'Producto', kicker_es: 'Línea de arriba (es)', kicker_en: 'Línea de arriba (en)', title_es: 'Título (es)',
    title_en: 'Título (en)', body_es: 'Texto (es)', body_en: 'Texto (en)', photo_url: 'Foto', link: 'Código QR', screen_ids: 'TV',
    starts_at: 'Desde', ends_at: 'Hasta', days: 'Días', from_time: 'De las', to_time: 'A las', sort: 'Orden'
  };
  var SKIP = { updated_at: 1, id: 1, item: 1, created_at: 1 };
  function show(k, v) {
    if (v === null || v === undefined || v === '' || (Array.isArray(v) && !v.length)) {
      return k === 'category_ids' ? 'todas' : k === 'screen_ids' ? 'todas' : k === 'days' ? 'todos' : '—';
    }
    if (typeof v === 'boolean') return v ? 'sí' : 'no';
    if (k === 'starts_at' || k === 'ends_at') return fecha(T(v));
    if (k === 'days') return daysText(v);
    if (k === 'category_ids') return v.map(function (id) { var c = (S.categories || []).filter(function (x) { return x.id === id; })[0]; return c ? c.name : id; }).join(', ');
    if (k === 'menu_item_id') { var it = (S.items || []).filter(function (x) { return x.id === v; })[0]; return it ? itemName(it) : String(v); }
    if (k === 'turn') { var t = TURN.filter(function (x) { return x[0] === v; })[0]; return t ? t[1] : v; }
    if (k === 'look') { var l = LOOK.filter(function (x) { return x[0] === v; })[0]; return l ? l[1] : v; }
    if (k === 'sold_out') { var so = SOLD.filter(function (x) { return x[0] === v; })[0]; return so ? so[1] : v; }
    if (k === 'kind') return KIND[v] || KIND_TV[v] || v;
    if (k === 'status') return (STATUS[v] || [v])[0];
    if (k === 'link') return v === 'resena' ? 'reseña' : v === 'menu' ? 'menú' : v;
    if (Array.isArray(v)) return v.join(', ');
    return String(v);
  }
  function whoText(by) { return String(by || '—').replace(/^owner login/, 'ingreso del dueño'); }
  function renderLog() {
    var host = clear($('logList'));
    if (!S.changes.length) { host.appendChild(h('p', { class: 'empty', text: 'Todavía no hay cambios.' })); return; }
    S.changes.forEach(function (c) {
      var what = c.target_kind === 'tv'
        ? 'la TV ' + c.target_id
        : 'la diapositiva «' + (c.summary || 'sin título') + '»';
      var row = h('article', { class: 'chg', 'data-action': c.action, 'data-target': c.target_kind + ':' + c.target_id });
      row.appendChild(h('div', { class: 'l1' }, [h('span', { class: 'when', text: fecha(T(c.at)) }),
        h('b', { text: (ACTION[c.action] || c.action) + ' ' + what }), h('span', { class: 'by', text: 'por ' + whoText(c.by) })]));
      if (c.target_kind === 'tv' && c.summary) row.appendChild(h('div', { class: 'hint', text: 'Nombre: ' + c.summary }));
      var before = c.before || {}, after = c.after || {}, keys = [];
      Object.keys(after).concat(Object.keys(before)).forEach(function (k) {
        if (SKIP[k] || keys.indexOf(k) > -1) return;
        if (c.before && JSON.stringify(before[k]) === JSON.stringify(after[k])) return;
        keys.push(k);
      });
      if (keys.length) {
        var tb = h('tbody');
        keys.forEach(function (k) {
          tb.appendChild(h('tr', { 'data-k': k }, [h('td', { class: 'k', text: LABEL[k] || k }),
            h('td', { class: 'was', text: c.before ? show(k, before[k]) : '—' }), h('td', { class: 'now', text: show(k, after[k]) })]));
        });
        row.appendChild(h('details', {}, [h('summary', { text: 'Detalles: antes y después' }),
          h('table', {}, [h('thead', {}, [h('tr', {}, [h('th', { text: 'Dato' }), h('th', { text: 'Antes' }), h('th', { text: 'Después' })])]), tb])]));
      }
      host.appendChild(row);
    });
  }

  /* ---------- 13) start ---------- */
  setTab(TAB);
  refreshAuth();
})();
