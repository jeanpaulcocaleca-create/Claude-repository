/* Canopy OS · pantallas.html: the owner manages the customer TVs (docs/PANTALLAS.md, migrations 0036 and 0037).
   Only through those functions: pantallas_estado (read), pantalla_guardar, diapositiva_guardar, diapositiva_estado.
   The server checks the owner on every call (is_true_owner: the owner's PIN on this device, or the owner login with the
   phone code) and writes every change to screen_changes; this page only helps, it never decides.
   Prices and availability are never written here: a product slide, and every entry of a composition that names a
   product, reads them from the menu on every screen read (the page stores item ids, photos and framing only).
   v2 (0037): a menu TV's layout, density, English, promotions intercalated in the menu and, for a 32" at 3 m, the
   products it shows (item_ids: a summarised menu of chosen products; none = every product of its categories); slides of kind
   «composicion» (a template of 1 to 4 zones, each a fixed photo or a presentation of its own, edited in a visual
   editor with a live preview of the real TV page in a frame); «Programación sugerida» creates four paused ones.
   Spanish only, written here: the page root (#pg) carries data-no-translate; lang.js only translates the PIN screen.
   Tests may set window.PANTALLAS_TEST = {sinRevisar: true} to send a slide or a TV without the page's checks,
   {antesDeEnviar: fn} to alter a slide's payload before it goes, which proves the server refuses on its own what the
   page blocks, and {idleMs: n} to shorten the owner login's idle sign-out (read each time it is armed). */
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
    id: 'el identificador de la TV', kind: 'el tipo', name: 'el nombre', category_ids: 'las categorías', item_ids: 'los productos',
    inches: 'el tamaño', distance_m: 'la distancia', turn: 'la posición', scale_pct: 'la escala de letra', look: 'los colores',
    page_seconds: 'los segundos por página', slide_seconds: 'los segundos por diapositiva', sold_out: 'los agotados',
    on_from: 'el horario', on_to: 'el horario', active: 'activa',
    layout: 'la distribución', density: 'la densidad', english: 'el inglés', promo_mode: 'las promociones',
    promo_every: 'cada cuántos segundos van las promociones', promo_seconds: 'cuánto dura cada promoción',
    menu_item_id: 'el producto', photo_url: 'la foto', screen_ids: 'las TV', days: 'los días',
    kicker_es: 'la línea de arriba (español)', kicker_en: 'la línea de arriba (inglés)', title_es: 'el título (español)',
    title_en: 'el título (inglés)', body_es: 'el texto (español)', body_en: 'el texto (inglés)', link: 'el código QR',
    starts_at: 'el inicio', ends_at: 'el fin', from_time: 'las horas', to_time: 'las horas', sort: 'el orden',
    template: 'la plantilla', dwell_seconds: 'la permanencia', zones: 'las zonas'
  };
  /* a refused check constraint, said in Spanish (detail is the database's message) */
  function detailText(d) {
    d = String(d || '');
    if (/screens_hours/.test(d)) return 'El horario necesita la hora de encender y la de apagar, distintas (o ninguna: siempre encendida).';
    if (/screen_slides_dates/.test(d)) return 'El fin debe ser después del inicio, y a lo sumo un año después.';
    if (/screen_slides_hours/.test(d)) return 'Ponga las dos horas, distintas, o ninguna (todo el día).';
    if (/screen_slides_kind/.test(d)) return 'Falta el producto, el título en español, el código QR de la invitación, o la plantilla y sus zonas de la composición.';
    if (/screen_slides_days/.test(d)) return 'Revise los días.';
    if (/screen_slides_template/.test(d)) return 'Elija una de las seis plantillas.';
    if (/dwell_seconds/.test(d)) return 'La permanencia va de 10 a 600 segundos.';
    if (/promo_every/.test(d)) return 'Las promociones van cada 30 a 900 segundos.';
    if (/promo_seconds/.test(d)) return 'Cada promoción dura de 6 a 30 segundos.';
    if (/screens_(layout|density|english|promo_mode)/.test(d)) return 'Revise la distribución, la densidad, el inglés o las promociones de la TV.';
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
    if (d.error === 'invalid' || d.error === 'too_many') {
      if (d.field) return zoneText(d) || ((d.error === 'too_many' ? 'Demasiados elementos en ' : 'Revise ') + (FIELD[d.field] || d.field) + '.');
      return detailText(d.detail);
    }
    if (d.error === 'text_combo_descuento' && (d.field === 'menu_item_id' || /^zones\..*\.item$/.test(d.field || ''))) {
      var pre = zonePrefix(d.field);
      return pre ? pre + 'ese producto es de Extras & Combos: no se anuncia.' : 'Ese producto es de Extras & Combos: no se anuncia.';
    }
    if (/^text_/.test(d.error) && d.field) return (ERR[d.error] || 'Revise el texto.') + ' (' + (FIELD[d.field] || d.field) + ')';
    return ERR[d.error] || ('No se pudo guardar (' + d.error + ').');
  }
  /* a refused field inside a composition (zones.N…), said next to the zone and the entry it names */
  function zoneName(i) { return ED && ED.kind === 'composicion' ? placeName(ED.template, Number(i)) : 'zona ' + (Number(i) + 1); }
  function zonePrefix(field) {
    var m = /^zones\.(\d+)(?:\.entries\.(\d+))?/.exec(field || '');
    return m ? zoneName(m[1]) + (m[2] !== undefined ? ', entrada ' + (Number(m[2]) + 1) : '') + ': ' : '';
  }
  function zoneText(d) {
    var m = /^zones(?:\.(\d+))?(?:\.(mode|seconds|labels|fallback|entries))?(?:\.(\d+))?(?:\.(item|photo|focus|zoom))?$/.exec(d.field || '');
    if (!m) return null;
    var many = d.error === 'too_many';
    if (m[1] === undefined) return many ? 'A lo sumo 4 zonas.' : 'Revise las zonas: una por cada lugar de la plantilla.';
    var pre = zonePrefix(d.field);
    switch (m[4] || m[2]) {
      case 'mode': return pre + 'el modo es foto fija o presentación.';
      case 'seconds': return pre + 'los segundos van de 4 a 60.';
      case 'labels': return pre + 'revise «nombres y precios».';
      case 'fallback': return pre + 'la foto de respaldo no sirve (una dirección http(s) de a lo sumo 500 letras).';
      case 'entries': return m[3] !== undefined ? pre + 'lleva un producto del menú o una foto.'
        : pre + (many ? 'a lo sumo 12 entradas.' : 'una foto fija lleva exactamente una entrada; una presentación, de 1 a 12.');
      case 'item': return pre + 'ese producto ya no está en el menú.';
      case 'photo': return pre + 'la foto no sirve (una dirección http(s) de a lo sumo 500 letras).';
      case 'focus': return pre + 'el punto de enfoque va de 0 a 100.';
      case 'zoom': return pre + 'el tamaño va de 100 a 200 %.';
      default: return pre + 'revise la zona.';
    }
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
  var RX_COMBO = new RegExp(W0 + '(combos?|descuentos?|descuentazos?|discounts?|dos por uno|tres por dos|por el precio de|2 ?for ?1|two for one|bogo|gratis|gratuit[oa]s?|' +
    'de regalo|cortes[ií]a|sin (costo|cargo)|ofertas?|ofert[oó]n|ofertones|rebajas?|rebajad[oa]s?|por ciento|promo precio|precio especial|special price|happy hour|mitad de precio|' +
    'medio precio|half price)' + W1, 'iu');
  var NUM = '([1-9]|uno|una|dos|tres|cuatro|cinco)';
  var RX_NXM = new RegExp(W0 + NUM + ' *(?:x|×|por) *' + NUM + W1, 'giu');          /* 2x1, 3×2, 2 por 1, dos por uno: two different numbers */
  var RX_LLEVE = new RegExp(W0 + '(lleve|llev[aá]|pague|pag[aá]) *(\\d+|uno|una|dos|tres|cuatro)[^\\d\\n]{0,30}' + W0 + '(pague|pag[aá]|lleve|llev[aá]) *(\\d+|uno|una|dos|tres|cuatro)' + W1, 'iu');
  var RX_BOGO = new RegExp(W0 + 'buy *(one|\\d+),? *(and )?get *(one|\\d+)' + W1, 'iu');
  function fold(x) { return String(x).toLowerCase().replace(/[áéíóú]/g, function (c) { return 'aeiou'['áéíóú'.indexOf(c)]; }); }
  function nxm(s) { var m, r = new RegExp(RX_NXM.source, 'giu'); while ((m = r.exec(s))) { if (fold(m[2]) !== fold(m[3])) return true; } return false; }
  /* the text as the server sees it: format characters dropped, fullwidth folded, every blank a plain space */
  function norma(s) { return String(s).replace(/[\u00ad\u200b-\u200f\u2060\ufeff]/g, '').normalize('NFKC').replace(/\s+/g, ' '); }
  function textProblem(s) {
    s = s === null || s === undefined ? '' : String(s);
    if (!s.trim()) return null;
    if (Array.from(s.trim()).length > 140) return 'largo';      /* the page sends each text trimmed */
    s = norma(s);
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
    if (s.kind === 'composicion' && s.usable === false) return false;    /* no zone with anything to show */
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
  function offToday(s, tv, t) {
    /* the same rule the screen applies (live): the first moment after now, up to tomorrow's hour, at which it is off:
       its end, today's or tomorrow's closing hour, or midnight when tomorrow is not one of its days */
    var ds = dayStart(t), de = ds + DAY, c = [T(s.ends_at), de], to = hm(s.to_time);
    if (to !== null && hm(s.from_time) !== null) { c.push(ds + to * 60000); c.push(de + to * 60000); }
    c = c.filter(function (x) { return x > t; }).sort(function (a, b) { return a - b; });
    for (var i = 0; i < c.length; i++) if (!live(s, tv, c[i])) return c[i] <= de + DAY ? c[i] : null;
    return null;
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
  /* the owner login signs out by itself after 30 minutes without a touch; the café tablet never does (its PIN lasts 15).
     Like «Cerrar sesión», it first takes away the photos uploaded for a preview and never saved: no orphan file */
  var idleTimer = null;
  function armIdle() {
    clearTimeout(idleTimer);
    if (ACCOUNT !== 'owner' && ACCOUNT !== 'owner_needs_code') return;
    var test = window.PANTALLAS_TEST || {}, ms = Number(test.idleMs) > 0 ? Number(test.idleMs) : 30 * 60000;
    idleTimer = setTimeout(async function () {
      try { await dropUploaded(); } catch (e) {}
      await db.auth.signOut({ scope: 'local' }); location.reload();
    }, ms);
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
    stopPvInfo();
    S = null; ED = null; drafts = {}; previews = {}; prodsOpen = {};
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
  async function signOut() { shown = ''; await dropUploaded(); forget(); await db.auth.signOut({ scope: 'local' }); refreshAuth(); }
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
  var KIND_TV = { menu: 'El menú con precios (puede intercalar promociones)', promos: 'Promociones: productos, composiciones, la marca e invitaciones' };
  var TURN = [['no', 'Horizontal'], ['derecha', 'Vertical · el borde de arriba de la TV quedó a la izquierda'],
              ['izquierda', 'Vertical · el borde de arriba de la TV quedó a la derecha']];
  var LOOK = [['auto', 'Automáticos: claros de día, oscuros de noche'], ['dia', 'Siempre claros (día)'], ['noche', 'Siempre oscuros (noche)']];
  var SOLD = [['ocultar', 'Ocultarlos'], ['tachar', 'Mostrarlos tachados, sin precio']];
  /* the menu TV's v2 choices (0037): how the menu is laid out, how dense, where the English goes, and the promotions */
  var LAYOUT = [['auto', 'Automática: una sola pantalla si la letra alcanza; si no, páginas'],
                ['una-pantalla', 'Una sola pantalla (si la letra no alcanza, avisa en el diagnóstico y pagina)'],
                ['paginas', 'Páginas: las menos posibles, con la letra más grande (la regla de siempre; hoy da la misma pizarra que Automática)']];
  var DENSITY = [['normal', 'Normal'], ['compacta', 'Compacta: más líneas, menos aire']];
  var ENGLISH = [['debajo', 'Debajo del español'], ['en-linea', 'En la misma línea, en gris'], ['no', 'No se muestra: solo español']];
  var PROMO = [['no', 'No: el menú nunca se interrumpe'], ['intercalar', 'Intercalar las diapositivas asignadas a esta TV']];
  var NUM = {
    inches: { label: 'Tamaño', unit: 'pulgadas', min: 24, max: 110, step: '0.1' },
    distance_m: { label: 'Distancia de lectura', unit: 'metros', min: 1, max: 15, step: '0.1', hint: 'Hasta el cliente más lejano que debe leer.' },
    scale_pct: { label: 'Escala de letra', unit: '%', min: 70, max: 160, step: '1', hint: '100 % = 1 cm de mayúscula por metro de distancia.' },
    page_seconds: { label: 'Segundos por página', unit: 'segundos', min: 15, max: 60, step: '1' },
    slide_seconds: { label: 'Segundos por diapositiva', unit: 'segundos', min: 6, max: 30, step: '1' },
    promo_every: { label: 'Una promoción cada', unit: 'segundos', min: 30, max: 900, step: '1' },
    promo_seconds: { label: 'Cada promoción dura', unit: 'segundos', min: 6, max: 30, step: '1' }
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
             on_to: tv.on_to || '', category_ids: (tv.category_ids || []).map(String), item_ids: (tv.item_ids || []).map(String), active: tv.active !== false,
             layout: tv.layout || 'auto', density: tv.density || 'normal', english: tv.english || 'debajo', promo_mode: tv.promo_mode || 'no',
             promo_every: numStr(tv.promo_every === undefined || tv.promo_every === null ? 180 : tv.promo_every),
             promo_seconds: numStr(tv.promo_seconds === undefined || tv.promo_seconds === null ? 10 : tv.promo_seconds) };
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
    stopPvInfo();                                   /* an open preview is drawn again below, with a reading of its own */
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
        'Ninguna marcada = todas. Si el menú no cabe en una pantalla legible a esa distancia, pruebe la densidad compacta, el inglés en línea o menos categorías.', true));
      grid.appendChild(h('div', { class: 'wide' }, [prodsField(tv, f)]));
      grid.appendChild(field(h('label', { for: fid(tv, 'layout'), text: 'Distribución' }), selectOf(fid(tv, 'layout'), LAYOUT, f.layout),
        'Nunca se baja de la letra mínima legible para que quepa.', true));
      grid.appendChild(field(h('label', { for: fid(tv, 'density'), text: 'Densidad' }), selectOf(fid(tv, 'density'), DENSITY, f.density)));
      grid.appendChild(field(h('label', { for: fid(tv, 'english'), text: 'Inglés' }), selectOf(fid(tv, 'english'), ENGLISH, f.english)));
      grid.appendChild(field(h('label', { for: fid(tv, 'promo_mode'), text: 'Promociones' }), selectOf(fid(tv, 'promo_mode'), PROMO, f.promo_mode), null, true));
      grid.appendChild(numField(tv, 'promo_every', f.promo_every));
      grid.appendChild(numField(tv, 'promo_seconds', f.promo_seconds));
      grid.appendChild(h('p', { class: 'hint wide', text: 'Con «intercalar», cada tantos segundos la TV muestra una de las diapositivas de la pestaña Diapositivas asignadas a ella ' +
        '(o a todas) durante esos segundos, con fundido, y vuelve a la misma página del menú. Sin diapositivas vigentes, nada interrumpe el menú.' }));
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
  /* the products a menu TV shows (0037, item_ids): a summarised menu for a 32" at 3 m. Folded under a summary that
     counts the ticked ones; the products grouped under their categories in the Menu Manager's order (S.items comes
     so ordered), never Extras & Combos; none ticked = every product of the categories chosen above */
  var prodsOpen = {};
  function prodsField(tv, f) {
    var chosen = {};
    f.item_ids.forEach(function (id) { chosen[String(id).toLowerCase()] = true; });
    var box = h('details', { class: 'prods', open: !!prodsOpen[tv.id] });
    var sum = h('summary');
    box.appendChild(sum);
    S.categories.forEach(function (c) {
      if (c.name === 'Extras & Combos') return;
      var its = S.items.filter(function (it) { return it.category === c.name && it.category !== 'Extras & Combos'; });
      if (!its.length) return;
      box.appendChild(h('h3', { class: 'pcat', text: c.name }));
      var checks = h('div', { class: 'checks', role: 'group', 'aria-label': 'Productos de ' + c.name });
      its.forEach(function (it) {
        checks.appendChild(h('label', {}, [h('input', { type: 'checkbox', value: it.id, 'data-item': '1', checked: !!chosen[String(it.id).toLowerCase()] }),
          itemName(it) + (it.available === false ? ' (agotado)' : '')]));
      });
      box.appendChild(checks);
    });
    box.appendChild(h('p', { class: 'hint', text: 'Ninguno marcado = todos los productos de las categorías elegidas. ' +
      'En una TV de 32" a 3 m, con densidad compacta y sin inglés: 2 páginas ≈ 8–10 productos en 2–3 categorías, 3 páginas ≈ 12; ' +
      'con el inglés debajo, el doble y puede no caber. Un producto marcado cuya categoría no está marcada arriba no se muestra. ' +
      'El menú QR siempre lleva todos.' }));
    var ofrecidos = {};
    Array.prototype.forEach.call(box.querySelectorAll('input[data-item]'), function (c) { ofrecidos[String(c.value).toLowerCase()] = true; });
    var idos = f.item_ids.filter(function (id) { return !ofrecidos[String(id).toLowerCase()]; }).length;   /* saved, but no longer a product the card offers */
    function count() {
      var n = box.querySelectorAll('input[data-item]:checked').length;
      sum.textContent = 'Productos que muestra: ' + (n ? n + (n === 1 ? ' elegido' : ' elegidos') + (idos ? ' (' + idos + ' ya no existen)' : '')
                                                      : (idos ? 'todos (los ' + idos + ' elegidos ya no existen)' : 'todos'));
    }
    count();
    box.addEventListener('change', count);
    box.addEventListener('toggle', function () { prodsOpen[tv.id] = box.open; });
    return box;
  }
  function numField(tv, k, v) {
    var n = NUM[k];
    return field(h('label', { for: fid(tv, k) }, [n.label + ' ', h('span', { class: 'range', text: '(' + n.min + ' a ' + n.max + ' ' + n.unit + ')' })]),
      h('input', { id: fid(tv, k), type: 'number', inputmode: 'decimal', min: String(n.min), max: String(n.max), step: n.step, value: v }), n.hint);
  }
  function readTvForm(card) {
    var id = card.getAttribute('data-tv'), v = {}, tv = { id: id };
    ['name', 'inches', 'distance_m', 'turn', 'scale_pct', 'look', 'page_seconds', 'slide_seconds', 'sold_out', 'on_from', 'on_to',
     'layout', 'density', 'english', 'promo_mode', 'promo_every', 'promo_seconds'].forEach(function (k) {
      var e = $(fid(tv, k)); v[k] = e ? e.value : '';
    });
    v.category_ids = Array.prototype.map.call(card.querySelectorAll('input[data-cat]:checked'), function (c) { return c.value; });
    v.item_ids = Array.prototype.map.call(card.querySelectorAll('input[data-item]:checked'), function (c) { return c.value; });
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
    var nums = ['inches', 'distance_m', 'scale_pct'].concat(tv.kind === 'menu' ? ['page_seconds', 'promo_every', 'promo_seconds'] : ['slide_seconds']);
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
    var test = window.PANTALLAS_TEST || {};
    var f = readTvForm(card), bad = test.sinRevisar ? [] : checkTv(tv, f);   /* the tests prove the server refuses by itself */
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
    if (tv.kind === 'menu') {
      p.page_seconds = Number(f.page_seconds); p.sold_out = f.sold_out; p.category_ids = f.category_ids; p.item_ids = f.item_ids;
      p.layout = f.layout; p.density = f.density; p.english = f.english; p.promo_mode = f.promo_mode;
      p.promo_every = Number(f.promo_every); p.promo_seconds = Number(f.promo_seconds);
    } else p.slide_seconds = Number(f.slide_seconds);
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
    if (tv.kind === 'menu') {
      var line = h('p', { class: 'pvinfo', 'data-pvinfo': '1', role: 'status', text: 'Midiendo…' });
      box.appendChild(line);
      watchPvInfo(tv.id, fr, line);
    }
    box.appendChild(h('p', { class: 'hint', text: 'La página real de la TV, con lo guardado: un cambio se ve después de guardarlo. ' +
      (vertical ? 'Girada como cuelga la TV. ' : '') + 'Fuera de su horario queda negra.' }));
    fitPreview(pv);
    var b = card.querySelector('[data-preview]'); if (b) b.textContent = 'Cerrar la vista previa';
  }
  function closePreview(tv) {
    stopPvInfo(tv.id);
    delete previews[tv.id];
    var card = document.querySelector('article.tv[data-tv="' + tv.id + '"]'); if (!card) return;
    var box = card.querySelector('.preview'); clear(box); box.hidden = true;
    var b = card.querySelector('[data-preview]'); if (b) b.textContent = 'Vista previa';
  }
  /* a menu TV's preview says, under the frame, what the real page measured with the saved row (its own
     PANTALLA.info(), read in the same-origin frame every 2 s while the preview is open): its pages, columns and letter,
     or that it does not fit at the minimum letter. Nothing is said before the page has read its row and the menu */
  var pvInfo = {};
  function stopPvInfo(id) {
    if (id === undefined) { Object.keys(pvInfo).forEach(function (k) { stopPvInfo(k); }); return; }
    clearInterval(pvInfo[id]); delete pvInfo[id];
  }
  function cm2(n) { return Number(n).toFixed(2).replace('.', ','); }       /* 2,45: the Spanish decimal comma */
  function pvInfoText(i) {
    if (!i || i.fuente !== 'base' || i.estado === 'sin-verificar') return 'Midiendo…';
    if (i.apagado) return 'En la TV: ahora queda negra (fuera de su horario o desactivada): no hay páginas que medir.';
    if (i.paginas === 0) return 'En la TV: ningún producto que mostrar; pide consultar el menú en la caja.';
    if (!(i.paginas > 0) || !i.capCm) return 'Midiendo…';
    if (i.cabe === false) return 'NO CABE a la letra mínima: use densidad compacta y sin inglés, o menos productos';
    var s = Math.round(Number(i.paginaMs) / 1000);
    return 'En la TV: ' + (i.paginas === 1 ? 'una sola página' : i.paginas + ' páginas' + (s > 0 ? ' de ' + s + ' s' : '')) +
      ' · ' + i.columnas + (i.columnas === 1 ? ' columna' : ' columnas') + ' · letra ' + cm2(i.capCm) + ' cm (mínimo ' + cm2(i.minCm) + ')';
  }
  function watchPvInfo(id, fr, line) {
    stopPvInfo(id);
    function read() {
      if (!line.isConnected) { stopPvInfo(id); return; }
      var i = null;
      try { var w = fr.contentWindow; i = w && w.PANTALLA && typeof w.PANTALLA.info === 'function' ? w.PANTALLA.info() : null; } catch (e) { i = null; }
      var t = pvInfoText(i);
      if (line.textContent !== t) line.textContent = t;
      line.classList.toggle('bad', /^NO CABE/.test(t));
    }
    read();
    pvInfo[id] = setInterval(read, 2000);
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
  var KIND = { producto: 'Producto', marca: 'Marca', invitacion: 'Invitación', composicion: 'Composición' };
  var STATUS = { activa: ['Activa', 'c-ok'], pausada: ['Pausada', 'c-warn'], retirada: ['Retirada', 'c-mute'] };
  var LINK = [['resena', 'Reseña en Tripadvisor'], ['menu', 'El menú en el teléfono']];
  /* the templates of a composition (0037): id, name, the name of each place in the order the zones are listed (as the
     TV draws them: left to right, a column top to bottom, the 2 x 2 grid row by row), the CSS grid the editor lays
     the zone editors out with, and each place as fractions of the stage [x, y, w, h] (the same table as the TV) */
  var TEMPLATES = [
    ['1', 'Una zona', ['Toda la pantalla'], ['1fr', '"a"']],
    ['2-lado', 'Dos mitades', ['Izquierda', 'Derecha'], ['1fr 1fr', '"a b"']],
    ['3-grande-izq', 'Grande a la izquierda', ['Izquierda (grande)', 'Derecha arriba', 'Derecha abajo'], ['2fr 1fr', '"a b" "a c"']],
    ['3-grande-der', 'Grande a la derecha', ['Izquierda arriba', 'Izquierda abajo', 'Derecha (grande)'], ['1fr 2fr', '"a c" "b c"']],
    ['4-cuadricula', 'Cuadrícula 2 × 2', ['Arriba izquierda', 'Arriba derecha', 'Abajo izquierda', 'Abajo derecha'], ['1fr 1fr', '"a b" "c d"']],
    ['4-centro', 'Centro en dos', ['Izquierda', 'Centro arriba', 'Centro abajo', 'Derecha'], ['3fr 2fr 3fr', '"a b d" "a c d"']]
  ];
  var PLANTILLAS = {
    '1': [[0, 0, 1, 1]],
    '2-lado': [[0, 0, 0.5, 1], [0.5, 0, 0.5, 1]],
    '3-grande-izq': [[0, 0, 2 / 3, 1], [2 / 3, 0, 1 / 3, 0.5], [2 / 3, 0.5, 1 / 3, 0.5]],
    '3-grande-der': [[0, 0, 1 / 3, 0.5], [0, 0.5, 1 / 3, 0.5], [1 / 3, 0, 2 / 3, 1]],
    '4-cuadricula': [[0, 0, 0.5, 0.5], [0.5, 0, 0.5, 0.5], [0, 0.5, 0.5, 0.5], [0.5, 0.5, 0.5, 0.5]],
    '4-centro': [[0, 0, 3 / 8, 1], [3 / 8, 0, 2 / 8, 0.5], [3 / 8, 0.5, 2 / 8, 0.5], [5 / 8, 0, 3 / 8, 1]]
  };
  function tplOf(t) { return TEMPLATES.filter(function (x) { return x[0] === t; })[0] || null; }
  function tplLabel(t) { var x = tplOf(t); return x ? x[1] : String(t || ''); }
  function places(t) { var x = tplOf(t); return x ? x[2].length : 0; }
  function placeName(t, i) { var x = tplOf(t); return x && x[2][i] ? x[2][i] : 'Zona ' + (Number(i) + 1); }
  function zoneAspect(t, i) { var p = PLANTILLAS[t] && PLANTILLAS[t][i]; return p ? String(Math.round((p[2] * 16) / (p[3] * 9) * 1000) / 1000) : '1.778'; }
  var showRetired = false, confirming = null;
  function promosTvs() { return S.screens.filter(function (x) { return x.kind === 'promos'; }); }
  /* the TVs a slide can be assigned to: the promotions TVs, and the menu TVs that intercalate promotions (0037) */
  function slideTvs() { return S.screens.filter(function (x) { return x.kind === 'promos' || (x.kind === 'menu' && x.promo_mode === 'intercalar'); }); }
  function itemName(it) { return !it ? '' : it.name_es && it.name_es !== it.name ? it.name_es + ' · ' + it.name : it.name; }
  function slideTitle(s) {
    if (s.kind === 'composicion') return s.kicker_es || ('Composición · ' + tplLabel(s.template));
    return s.title_es || (s.item ? itemName(s.item) : '') || '(sin título)';
  }
  /* a composition's picture in the list: the first photo of its zones */
  function slidePhoto(s) {
    if (s.kind === 'composicion') {
      var url = null;
      (s.zones || []).some(function (z) {
        return (z.entries || []).some(function (e) { url = e.photo || (e.item && e.item.photo_url) || null; return !!url; });
      });
      return url;
    }
    return s.photo_url || (s.item && s.item.photo_url) || null;
  }
  /* one zone of a composition, said in a few words (z as the server gives it: entries' items resolved, and showable:
     whether any entry has something to show now). A zone with nothing to show says so, and what to do */
  function zoneSummary(z) {
    var en = z.entries || [], n = en.length;
    var what = n === 1 ? (en[0].item ? itemName(en[0].item) : 'una foto') : n + ' entradas';
    var agotados = n > 0 && en.every(function (e) { return e && e.item && e.item.sellable === false; });
    return (z.mode === 'auto' ? 'presentación cada ' + (z.seconds || 8) + ' s · ' : 'foto fija · ') + what + (z.labels === false ? ' · sin nombres ni precios' : '') +
      (z.showable !== false ? '' : agotados ? ' · NADA QUE MOSTRAR: sus productos están agotados o sin precio'
        : ' · NADA QUE MOSTRAR: suba fotos o active nombres y precios');
  }
  function zonesText(s) {
    return (s.zones || []).map(function (z, i) { return placeName(s.template, i) + ': ' + zoneSummary(z); }).join(' · ');
  }
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
    if (!ids || !ids.length) {
      var menus = slideTvs().some(function (x) { return x.kind === 'menu'; });
      return 'todas las TV de promociones' + (menus ? ' y las de menú que intercalan promociones' : '');
    }
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
    if (s.kind === 'composicion' && s.usable === false) return ['No sale: ninguna zona tiene qué mostrar', 'c-warn'];
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
    var row = h('article', { class: 'slide ' + s.status, 'data-slide': s.id, 'data-kind': s.kind });
    row.appendChild(thumb(slidePhoto(s)));
    var body = h('div');
    var sub = s.kind === 'producto' && s.item
      ? ' · Producto: ' + itemName(s.item) + (s.item.category ? ' · ' + s.item.category : '') + ' · ' + crc(s.item.price_crc) + ' en el menú' +
        (s.item.available ? '' : ' · agotado')
      : s.kind === 'composicion'
      ? ' · Composición · plantilla ' + tplLabel(s.template) + ' · ' + zonesText(s) + ' · se queda ' + (s.dwell_seconds || 60) + ' s'
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
    if (ED && ED.id === s.id && estado === 'retirada') { await dropUploaded(); closeEditor(); }
    await loadState();
    toast('Guardado');
  }
  $('newSlide').addEventListener('click', function () { openEditor(null); });
  $('newCompo').addEventListener('click', function () { openEditor(null, 'composicion'); });

  /* ---------- 9) the slide editor ---------- */
  var ED = null;
  var TEXTS = ['kicker_es', 'kicker_en', 'title_es', 'title_en', 'body_es', 'body_en'];
  var PAIRS = [
    ['kicker', 'Línea corta de arriba', 'Ej.: Recién hecho', 'Ej.: Freshly made'],
    ['title', 'Título', 'Ej.: Café de altura de Monteverde', 'Ej.: Highland coffee from Monteverde'],
    ['body', 'Texto', 'Ej.: Tostado aquí, en Santa Elena', 'Ej.: Roasted here, in Santa Elena']
  ];
  /* a menu item as the screens may show it (the TV's own rule, mirrored): on sale, a price, a name, never a till helper */
  function sellable(it) {
    return !!it && it.available === true && Number(it.price_crc) > 0 && String(it.name || '').trim() !== '' && it.category !== 'Extras & Combos';
  }
  /* the item of the menu with that id, from the state; else a stand-in built from what the server sent with the slide */
  function itemOf(id, from) {
    var it = id ? S.items.filter(function (x) { return x.id === id; })[0] : null;
    if (it || !id || !from) return it || null;
    return { id: id, name: from.name || 'producto', name_es: from.name_es || null, category: from.category || null,
             price_crc: from.price_crc || 0, available: !!from.available, photo_url: from.photo_url || null };
  }
  function clampN(v, lo, hi, def) { var n = Number(v); return isFinite(n) ? Math.min(hi, Math.max(lo, Math.round(n))) : def; }
  function newZone() { return { mode: 'auto', seconds: 8, labels: true, fallback: null, fbBlob: null, fbBlobUrl: null, fbUploaded: null, entries: [], pick: null, search: '' }; }
  function newEntry(it, photo) { return { item: it || null, photo: photo || null, blob: null, blobUrl: null, uploaded: null, focus: [50, 50], zoom: 100, lost: false }; }
  /* a zone as pantallas_estado gives it (entries' items resolved) -> the editor's zone */
  function zoneFromServer(z) {
    var out = newZone(); z = z || {};
    out.mode = z.mode === 'auto' ? 'auto' : 'fija';
    out.seconds = clampN(z.seconds, 4, 60, 8);
    out.labels = z.labels !== false;
    out.fallback = z.fallback || null;
    out.entries = (Array.isArray(z.entries) ? z.entries : []).map(function (e) {
      e = e || {};
      var en = newEntry(e.item ? itemOf(e.item.id, e.item) : null, e.photo || null);
      en.focus = Array.isArray(e.focus) && e.focus.length === 2 ? [clampN(e.focus[0], 0, 100, 50), clampN(e.focus[1], 0, 100, 50)] : [50, 50];
      en.zoom = clampN(e.zoom, 100, 200, 100);
      en.lost = !e.item && !e.photo;          /* its product left the menu: the owner takes it out or changes it */
      return en;
    });
    return out;
  }
  function entryPhoto(e) { return e.uploaded || e.photo || null; }
  function entryShown(e) { return e.blobUrl || entryPhoto(e) || (e.item && e.item.photo_url) || null; }   /* what its thumbnail shows */
  function entryShowable(e) { return e.item && !e.lost ? sellable(e.item) : !!(entryPhoto(e) || e.blob); }
  /* as many zones as the template has places: the ones taken away by a smaller template wait in a stash */
  function fitZones() {
    var n = places(ED.template) || 1;
    while (ED.zones.length < n) ED.zones.push(ED.stash.shift() || newZone());
    while (ED.zones.length > n) ED.stash.unshift(ED.zones.pop());
  }
  function openEditor(s, kind) {
    var t = Math.floor(nowMs() / 60000) * 60000;
    if (ED) { closeEdPreview(); dropUploaded(); }   /* photos uploaded for the preview of the editor being replaced */
    if (s) {
      var it = itemOf(s.menu_item_id, s.menu_item_id ? (s.item || {}) : null);
      ED = { id: s.id, kind: s.kind, item: it, link: s.link || 'resena', photoMode: s.photo_url ? 'propia' : (s.kind === 'producto' ? 'menu' : 'ninguna'),
             photo_url: s.photo_url || null, blob: null, uploaded: null, uploadedPaths: [], starts: T(s.starts_at), ends: T(s.ends_at),
             startsIso: s.starts_at, endsIso: s.ends_at,
             endTouched: true, days: (s.days && s.days.length ? s.days : [1, 2, 3, 4, 5, 6, 7]).slice(), from: s.from_time || '', to: s.to_time || '',
             screens: (s.screen_ids || []).slice(), sort: s.sort, texts: {},
             template: tplOf(s.template) ? s.template : '4-centro', zones: [], stash: [],
             dwell: s.dwell_seconds === null || s.dwell_seconds === undefined ? '' : String(s.dwell_seconds) };
      if (s.kind === 'composicion') ED.zones = (Array.isArray(s.zones) ? s.zones : []).map(zoneFromServer);
      TEXTS.forEach(function (k) { ED.texts[k] = s[k] || ''; });
    } else {
      ED = { id: null, kind: kind === 'composicion' ? 'composicion' : 'producto', item: null, link: 'resena', photoMode: 'menu', photo_url: null, blob: null,
             uploaded: null, uploadedPaths: [], starts: t, ends: t + 30 * DAY, endTouched: false, days: [1, 2, 3, 4, 5, 6, 7], from: '', to: '', screens: [], sort: 100,
             texts: {}, template: '4-centro', zones: [], stash: [], dwell: '' };
      TEXTS.forEach(function (k) { ED.texts[k] = ''; });
    }
    if (ED.kind === 'composicion') fitZones();
    renderEditor();
    setTab('slides');
    var f = $('slideForm'); if (f) { f.scrollIntoView({ block: 'start' }); }
  }
  function closeEditor() { closeEdPreview(); ED = null; clear($('editorHost')); }
  function renderEditor() {
    var host = clear($('editorHost'));
    var form = h('form', { class: 'card editor', id: 'slideForm', novalidate: true });
    form.appendChild(h('h2', { text: ED.id ? (ED.kind === 'composicion' ? 'Editar la composición' : 'Editar la diapositiva') : (ED.kind === 'composicion' ? 'Nueva composición' : 'Nueva diapositiva') }));

    /* kind */
    var kinds = h('div', { class: 'kinds' });
    [['producto', 'Un producto del menú, con su foto y su precio al día'], ['marca', 'Un mensaje de la casa'],
     ['invitacion', 'Una invitación con código QR: reseña o menú'],
     ['composicion', 'De 1 a 4 zonas: cada una, una foto fija o una presentación propia de productos y fotos']].forEach(function (k) {
      kinds.appendChild(h('label', {}, [h('input', { type: 'radio', name: 'edKind', value: k[0], checked: ED.kind === k[0], disabled: !!ED.id,
        on: { change: function () {
          ED.kind = k[0];
          if (!ED.blob && !ED.photo_url) ED.photoMode = k[0] === 'producto' ? 'menu' : 'ninguna';
          if (k[0] === 'composicion') fitZones();
          $('slideForm').querySelector('h2').textContent = k[0] === 'composicion' ? 'Nueva composición' : 'Nueva diapositiva';
          kindChanged();
        } } }),
        h('span', {}, [KIND[k[0]], h('small', { text: k[1] })])]));
    });
    form.appendChild(h('fieldset', {}, [h('legend', { text: 'Tipo' }), kinds,
      ED.id ? h('p', { class: 'hint', text: 'El tipo no cambia: para otro tipo, cree una diapositiva nueva.' }) : null]));

    /* the composition: its template and its zones (filled by renderCompo) */
    form.appendChild(h('fieldset', { id: 'edCompo' }));

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
        inp.addEventListener('input', function () { ED.texts[k] = inp.value; checkTexts(); edChanged(); });
        pair.appendChild(h('div', {}, [h('label', { for: id }, [p[1] + ' (' + l[1] + ')', h('span', { class: 'cnt', id: 'cnt-' + k })]), inp,
          h('p', { class: 'err', id: 'err-' + k, role: 'alert' })]));
      });
      tf.appendChild(pair);
    });
    tf.appendChild(h('p', { class: 'hint', id: 'edTitleHint' }));
    form.appendChild(tf);

    /* QR */
    var link = selectOf('edLink', LINK, ED.link);
    link.addEventListener('change', function () { ED.link = link.value; edChanged(); });
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
      edChanged();
    });
    end.addEventListener('input', function () { ED.endTouched = true; edChanged(); });
    var days = h('div', { class: 'days', role: 'group', 'aria-label': 'Días' });
    DIAS.forEach(function (d, i) {
      var b = h('button', { type: 'button', text: d, title: DIAS_LARGOS[i], 'aria-label': DIAS_LARGOS[i], 'data-day': String(i + 1), 'aria-pressed': String(ED.days.indexOf(i + 1) > -1) });
      b.addEventListener('click', function () {
        var on = ED.days.indexOf(i + 1) > -1;
        ED.days = on ? ED.days.filter(function (x) { return x !== i + 1; }) : ED.days.concat([i + 1]).sort();
        b.setAttribute('aria-pressed', String(!on));
        edChanged();
      });
      days.appendChild(b);
    });
    var from = h('input', { id: 'edFrom', type: 'time', value: ED.from }), to = h('input', { id: 'edTo', type: 'time', value: ED.to });
    from.addEventListener('input', edChanged); to.addEventListener('input', edChanged);
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
      h('p', { class: 'hint', text: 'Ninguna marcada = todas: las TV de promociones y las TV de menú que intercalan promociones, también las que se agreguen después.' })]));
    var sort = h('input', { id: 'edSort', type: 'number', inputmode: 'numeric', step: '1', min: '0', max: '9999', value: String(ED.sort) });
    sort.addEventListener('input', edChanged);
    form.appendChild(h('fieldset', {}, [h('legend', { text: 'Orden' }), h('div', { class: 'fields' }, [
      field(h('label', { for: 'edSort', text: 'Orden (menor sale primero)' }), sort),
      ED.id ? null : h('div', {}, [h('span', { class: 'lbl', text: 'Al guardar' }),
        h('label', { class: 'line' }, [h('input', { type: 'checkbox', id: 'edPaused' }), 'Guardarla en pausa (todavía no sale)'])])])]));

    /* the preview: the real TV page, framed, with what this form holds (nothing saved) */
    var tvs = promosTvs(), pvSel = selectOf('edPvTv', tvs.length ? tvs.map(function (tv) { return [tv.id, tv.name]; }) : [['', 'TV de promociones']], tvs.length ? tvs[0].id : '');
    pvSel.addEventListener('change', function () { if (pvOpen) openEdPreview(); });
    form.appendChild(h('fieldset', { id: 'edPvBox' }, [h('legend', { text: 'Vista previa' }),
      h('div', { class: 'fields' }, [field(h('label', { for: 'edPvTv', text: 'Como se vería en' }), pvSel),
        h('div', {}, [h('span', { class: 'lbl', text: ' ' }), h('button', { type: 'button', class: 'ghost', id: 'edPreviewBtn', text: 'Vista previa en la TV', on: { click: function () { if (pvOpen) closeEdPreview(); else openEdPreview(); } } })])]),
      h('div', { class: 'preview pvbox', id: 'edPreview', hidden: true }),
      h('p', { class: 'hint', text: 'La página real de la TV con lo que hay en este formulario, sin guardar: se actualiza con cada cambio, y las presentaciones se turnan como en la TV. Las fotos nuevas se suben al abrirla (si no guarda, se quitan).' })]));

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
    slideTvs().forEach(function (tv) {
      box.appendChild(h('label', {}, [h('input', { type: 'checkbox', value: tv.id, 'data-tv': '1', checked: ED.screens.indexOf(tv.id) > -1,
        on: { change: function () { ED.screens = Array.prototype.map.call(box.querySelectorAll('input:checked'), function (c) { return c.value; }); edChanged(); } } }),
        tv.name + (tv.kind === 'menu' ? ' (menú, con promociones)' : '') + (tv.active ? '' : ' (desactivada)')]));
    });
    if (!box.firstChild) box.appendChild(h('span', { class: 'hint', text: 'No hay TV de promociones.' }));
  }
  function kindChanged() {
    var k = ED.kind, compo = k === 'composicion';
    $('edProduct').hidden = k !== 'producto';
    $('edLinkBox').hidden = k !== 'invitacion';
    $('edCompo').hidden = !compo;
    $('edPhotoBox').hidden = compo;                     /* a composition's photos live in its zones */
    /* a product slide always shows the menu's name (so it matches the till): no title to type; a composition has no
       title nor text at all (only the short line above, optional) */
    $('pair-title').hidden = k === 'producto' || compo;
    $('pair-body').hidden = compo;
    if (k === 'producto' || compo) { ED.texts.title_es = ''; ED.texts.title_en = ''; $('ed-title_es').value = ''; $('ed-title_en').value = ''; }
    if (compo) { ED.texts.body_es = ''; ED.texts.body_en = ''; $('ed-body_es').value = ''; $('ed-body_en').value = ''; }
    $('edTitleHint').textContent = k === 'producto' ? 'El título es el nombre del producto en el menú, como lo cobra la Caja.'
      : compo ? 'Una composición no lleva título ni texto: solo la línea corta de arriba, si quiere, sobre las zonas.'
      : 'El título en español es obligatorio.';
    if (compo) renderCompo();
    renderPicker(); renderPhoto(); checkTexts();
    edChanged();
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
        on: { click: function () { ED.item = it; renderPicker(); renderPhoto(); edChanged(); } } },
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
        on: { change: function () { ED.photoMode = o[0]; renderPhoto(); edChanged(); } } }), o[1]]));
    });
    if (ED.photoMode === 'menu') {
      box.appendChild(thumb(ED.item && ED.item.photo_url, 'ph', ED.item ? 'el producto no tiene foto' : 'elija el producto'));
    } else if (ED.photoMode === 'propia') {
      var url = ED.blob ? ED.blobUrl : ED.photo_url;
      box.appendChild(thumb(url, 'ph', 'ninguna todavía'));
      box.appendChild(h('button', { type: 'button', class: 'ghost small', id: 'edPick', text: url ? 'Cambiar la foto' : 'Elegir una foto…',
        on: { click: function () { photoTarget = { own: true, ed: ED }; $('photoFile').click(); } } }));
    }
  }

  /* ----- the composition: template, zones laid out like the TV, each zone its own ordered list of entries ----- */
  function renderCompo() {
    var box = $('edCompo'); if (!box || ED.kind !== 'composicion') return;
    clear(box);
    box.appendChild(h('legend', { text: 'Composición' }));
    var tl = h('div', { class: 'tpls', id: 'edTemplates', role: 'group', 'aria-label': 'Plantilla' });
    TEMPLATES.forEach(function (t) {
      var mini = h('span', { class: 'mini', 'aria-hidden': 'true' });
      PLANTILLAS[t[0]].forEach(function (p) {
        var i = h('i');
        i.style.left = (p[0] * 100) + '%'; i.style.top = (p[1] * 100) + '%'; i.style.width = (p[2] * 100) + '%'; i.style.height = (p[3] * 100) + '%';
        mini.appendChild(i);
      });
      tl.appendChild(h('button', { type: 'button', class: 'tpl', 'data-template': t[0], 'aria-pressed': String(ED.template === t[0]), on: { click: function () { setTemplate(t[0]); } } },
        [mini, h('span', { text: t[1] })]));
    });
    box.appendChild(h('span', { class: 'lbl', text: 'Plantilla' }));
    box.appendChild(tl);
    box.appendChild(h('p', { class: 'hint', text: 'Las zonas se ven aquí como en una TV horizontal; en una TV vertical se apilan en este mismo orden. ' +
      'Cada zona es una presentación aparte: una foto fija, o varias entradas que se turnan a su propio ritmo, sin esperar a las otras.' }));
    var g = h('div', { class: 'zonesGrid', id: 'edZones' }), grid = tplOf(ED.template)[3];
    g.style.gridTemplateColumns = grid[0]; g.style.gridTemplateAreas = grid[1];
    ED.zones.forEach(function (z, i) { g.appendChild(zoneEditor(z, i)); });
    box.appendChild(g);
    var dwell = h('input', { id: 'edDwell', type: 'number', inputmode: 'numeric', min: '10', max: '600', step: '1', value: ED.dwell, placeholder: '60' });
    dwell.addEventListener('input', function () { ED.dwell = dwell.value; edChanged(); });
    box.appendChild(h('div', { class: 'fields', style: 'margin-top:.9rem' }, [
      field(h('label', { for: 'edDwell' }, ['Permanencia ', h('span', { class: 'range', text: '(10 a 600 segundos; vacío = 60)' })]), dwell,
        'Cuánto se queda esta composición cuando comparte la TV con otras diapositivas. Sola en su franja, se queda hasta que termine.', true)]));
  }
  function setTemplate(t) {
    if (!tplOf(t) || !ED) return;
    var old = ED.template, n = places(t) || 1;
    if (old !== t && ED.zones.length > n) {
      /* the places that keep their name (Izquierda, Derecha…) keep their zone; the rest go to the stash in order */
      var names = ED.zones.map(function (z, i) { return placeName(old, i); }), taken = [], kept = [];
      for (var j = 0; j < n; j++) { var k = names.indexOf(placeName(t, j)); if (k >= 0 && taken.indexOf(k) < 0) { taken.push(k); kept[j] = ED.zones[k]; } }
      for (var j2 = 0; j2 < n; j2++) if (!kept[j2]) { for (var k2 = 0; k2 < ED.zones.length; k2++) if (taken.indexOf(k2) < 0) { taken.push(k2); kept[j2] = ED.zones[k2]; break; } }
      var rest = ED.zones.filter(function (z, i) { return taken.indexOf(i) < 0; });
      ED.zones = kept; ED.stash = rest.concat(ED.stash);
    }
    ED.template = t; fitZones(); renderCompo(); edChanged();
  }
  function rerenderZone(i) {
    var old = document.querySelector('#edZones .zone[data-zone="' + i + '"]');
    if (old && ED.zones[i]) old.replaceWith(zoneEditor(ED.zones[i], i));
    edChanged();
  }
  function zoneMsg(i, text, ok) {
    var m = $('edZerr-' + i); if (!m) return;
    m.classList.toggle('ok', !!ok); m.textContent = text || '';
  }
  function zoneEditor(z, i) {
    var n = ED.zones.length, t = ED.template, name = placeName(t, i);
    var sec = h('section', { class: 'zone', 'data-zone': String(i), 'aria-label': name });
    sec.style.setProperty('--ga', 'abcd'[i]);
    var swaps = h('span', { class: 'swap' });
    if (i > 0) swaps.appendChild(h('button', { type: 'button', class: 'ghost small', 'data-act': 'swap-prev', text: '⇄ ' + placeName(t, i - 1),
      'aria-label': 'Intercambiar con ' + placeName(t, i - 1), on: { click: function () { swapZones(i, i - 1); } } }));
    if (i < n - 1) swaps.appendChild(h('button', { type: 'button', class: 'ghost small', 'data-act': 'swap-next', text: '⇄ ' + placeName(t, i + 1),
      'aria-label': 'Intercambiar con ' + placeName(t, i + 1), on: { click: function () { swapZones(i, i + 1); } } }));
    sec.appendChild(h('h3', {}, [h('span', { text: name }), swaps]));

    /* fixed photo or its own presentation */
    var modes = h('div', { class: 'checks', role: 'group', 'aria-label': 'Modo de ' + name });
    [['fija', 'Foto fija'], ['auto', 'Presentación']].forEach(function (m) {
      modes.appendChild(h('label', {}, [h('input', { type: 'radio', name: 'edZmode-' + i, id: 'edZ-' + i + '-mode-' + m[0], value: m[0], checked: z.mode === m[0],
        on: { change: function () { z.mode = m[0]; rerenderZone(i); } } }), m[1]]));
    });
    var seconds = h('input', { id: 'edZ-' + i + '-seconds', type: 'number', inputmode: 'numeric', min: '4', max: '60', step: '1', value: String(z.seconds) });
    seconds.addEventListener('input', function () { z.seconds = seconds.value; edChanged(); });
    var labels = h('input', { type: 'checkbox', id: 'edZ-' + i + '-labels', checked: z.labels });
    labels.addEventListener('change', function () { z.labels = labels.checked; rerenderZone(i); });
    sec.appendChild(h('div', { class: 'row' }, [h('div', {}, [h('span', { class: 'lbl', text: 'Modo' }), modes]),
      h('div', { hidden: z.mode !== 'auto' }, [h('label', { for: seconds.id }, ['Cambia cada ', h('span', { class: 'range', text: '(4 a 60 s)' })]), seconds])]));
    sec.appendChild(h('label', { class: 'line' }, [labels, 'Nombres y precios del menú (solo en las entradas con producto; siempre al día)']));

    /* the entries, in order */
    var ol = h('ol', { class: 'entries' });
    z.entries.forEach(function (e, j) { ol.appendChild(entryRow(z, i, e, j)); });
    if (!z.entries.length) ol.appendChild(h('li', { class: 'hint', text: 'Sin entradas todavía: agregue un producto del menú o suba una foto.' }));
    sec.appendChild(ol);
    sec.appendChild(h('div', { class: 'adds' }, [
      h('button', { type: 'button', class: 'ghost small', id: 'edZ-' + i + '-add', 'aria-pressed': String(z.pick === 'entry'), text: 'Agregar producto',
        on: { click: function () { z.pick = z.pick === 'entry' ? null : 'entry'; rerenderZone(i); } } }),
      h('button', { type: 'button', class: 'ghost small', 'data-act': 'subir', text: 'Subir foto',
        on: { click: function () { photoTarget = { zone: i, zoneObj: z, ed: ED }; $('photoFile').click(); } } })]));
    if (z.pick) sec.appendChild(zonePicker(z, i));

    /* the fallback photo */
    var fbUrl = z.fbBlobUrl || z.fbUploaded || z.fallback, fb = h('div', { class: 'fb', id: 'edZ-' + i + '-fallback' });
    fb.appendChild(thumb(fbUrl, 'ph', 'la marca'));
    fb.appendChild(h('span', { class: 'fbt' }, [h('b', { text: 'Foto de respaldo' }), h('small', { text: fbUrl ? 'Se ve cuando ninguna entrada de la zona se puede mostrar.'
      : 'Sin foto de respaldo: cuando ninguna entrada se puede mostrar (agotada, sin precio…), se ve el diseño de la marca.' })]));
    fb.appendChild(h('span', { class: 'eacts' }, [
      h('button', { type: 'button', class: 'ghost small', 'data-act': 'fb-subir', text: 'Subir foto', on: { click: function () { photoTarget = { zone: i, zoneObj: z, fallback: true, ed: ED }; $('photoFile').click(); } } }),
      h('button', { type: 'button', class: 'ghost small', 'data-act': 'fb-producto', text: 'Foto de un producto', on: { click: function () { z.pick = 'fallback'; rerenderZone(i); } } }),
      fbUrl ? h('button', { type: 'button', class: 'ghost small', 'data-act': 'fb-quitar', text: 'Quitar', on: { click: function () {
        if (z.fbBlobUrl) URL.revokeObjectURL(z.fbBlobUrl);
        z.fallback = null; z.fbBlob = null; z.fbBlobUrl = null; z.fbUploaded = null; rerenderZone(i);
      } } }) : null]));
    sec.appendChild(fb);
    sec.appendChild(h('p', { class: 'err', id: 'edZerr-' + i, role: 'alert' }));
    return sec;
  }
  function swapZones(a, b) {
    var x = ED.zones[a]; ED.zones[a] = ED.zones[b]; ED.zones[b] = x;
    renderCompo(); edChanged();
  }
  /* the product search of a zone: an entry, or the fallback photo (z.pick) */
  function zonePicker(z, i) {
    var box = h('div', { class: 'zpick' });
    var search = h('input', { id: 'edZ-' + i + '-search', type: 'search', placeholder: 'Buscar en el menú: nombre, nombre en español o categoría', autocomplete: 'off', value: z.search });
    var list = h('div', { class: 'picker', id: 'edZ-' + i + '-picker' });
    function fill() {
      clear(list);
      var q = norm(search.value).split(/\s+/).filter(Boolean), n = 0;
      S.items.filter(function (it) { return it.category !== 'Extras & Combos'; }).forEach(function (it) {
        var hay = norm([it.name, it.name_es, it.category].join(' '));
        if (q.some(function (w) { return hay.indexOf(w) < 0; }) || n >= 80) return;
        n++;
        list.appendChild(h('button', { type: 'button', class: 'pick', 'data-item': it.id, on: { click: function () { pickItem(z, i, it); } } },
          [thumb(it.photo_url), h('span', {}, [h('b', { text: itemName(it) }),
            h('small', { text: (it.category || '') + ' · ' + crc(it.price_crc) + (it.available ? '' : ' · agotado') + (it.photo_url ? '' : ' · sin foto') })])]));
      });
      if (!n) list.appendChild(h('p', { class: 'hint', text: 'Nada en el menú con esa búsqueda.' }));
    }
    search.addEventListener('input', function () { z.search = search.value; fill(); });
    fill();
    box.appendChild(h('label', { for: search.id, text: z.pick === 'fallback' ? 'Foto de respaldo: la foto de este producto del menú'
      : 'Agregar un producto del menú: su nombre, su foto y su precio salen del menú al día; Extras & Combos nunca se anuncia' }));
    box.appendChild(search); box.appendChild(list);
    box.appendChild(h('button', { type: 'button', class: 'ghost small', 'data-act': 'cerrar-busqueda', text: 'Cerrar la búsqueda', on: { click: function () { z.pick = null; rerenderZone(i); } } }));
    return box;
  }
  function pickItem(z, i, it) {
    if (z.pick === 'fallback') {
      if (!it.photo_url) { zoneMsg(i, 'Ese producto no tiene foto en el menú: elija otro o suba una foto.'); return; }
      if (z.fbBlobUrl) URL.revokeObjectURL(z.fbBlobUrl);
      z.fallback = it.photo_url; z.fbBlob = null; z.fbBlobUrl = null; z.fbUploaded = null; z.pick = null;
    } else {
      if (z.entries.length >= 12) { zoneMsg(i, 'A lo sumo 12 entradas por zona.'); return; }
      z.entries.push(newEntry(it, null));
    }
    rerenderZone(i);
  }
  function entryRow(z, i, e, j) {
    var li = h('li', { class: 'entry', 'data-entry': String(j) });
    var fr = frameOf(z, i, e);
    li.appendChild(fr);
    var info = h('div', { class: 'einfo' });
    var label = e.lost ? 'Producto que ya no está en el menú: quítelo o cámbielo'
      : e.item ? itemName(e.item) + ' · ' + crc(e.item.price_crc) + ' en el menú' + (sellable(e.item) ? '' : ' · agotado o sin precio: no sale hasta que vuelva')
      : 'Foto' + (e.blob ? ' (nueva)' : '');
    info.appendChild(h('b', { text: (j + 1) + '. ' + label }));
    info.appendChild(h('small', { class: 'focus' }));
    var zoom = h('input', { type: 'range', id: 'edZ-' + i + '-e-' + j + '-zoom', min: '100', max: '200', step: '1', value: String(e.zoom), 'aria-label': 'Tamaño de la foto' });
    var zv = h('span', { text: e.zoom + ' %' });
    zoom.addEventListener('input', function () { e.zoom = clampN(zoom.value, 100, 200, 100); zv.textContent = e.zoom + ' %'; applyFrame(fr, e); edChanged(); });
    info.appendChild(h('label', { class: 'zoom', for: zoom.id }, ['Tamaño', zoom, zv]));
    info.appendChild(h('div', { class: 'eacts' }, [
      h('button', { type: 'button', class: 'ghost small', 'data-act': 'arriba', text: '↑', 'aria-label': 'Subir en el orden', disabled: j === 0,
        on: { click: function () { z.entries.splice(j - 1, 0, z.entries.splice(j, 1)[0]); rerenderZone(i); } } }),
      h('button', { type: 'button', class: 'ghost small', 'data-act': 'abajo', text: '↓', 'aria-label': 'Bajar en el orden', disabled: j === z.entries.length - 1,
        on: { click: function () { z.entries.splice(j + 1, 0, z.entries.splice(j, 1)[0]); rerenderZone(i); } } }),
      /* another photo for this entry, in its place: a product keeps its product (its own photo wins over the menu's) */
      h('button', { type: 'button', class: 'ghost small', 'data-act': 'cambiar-foto', text: 'Cambiar foto',
        on: { click: function () { photoTarget = { zone: i, zoneObj: z, entryObj: e, ed: ED }; $('photoFile').click(); } } }),
      e.item && (e.photo || e.blob) ? h('button', { type: 'button', class: 'ghost small', 'data-act': 'foto-menu', text: 'Foto del menú',
        title: 'Quitar la foto propia: la entrada vuelve a la foto del producto en el menú', on: { click: function () {
          if (e.blobUrl) URL.revokeObjectURL(e.blobUrl);
          e.photo = null; e.blob = null; e.blobUrl = null; e.uploaded = null; e.focus = [50, 50]; e.zoom = 100;
          rerenderZone(i);
        } } }) : null,
      h('button', { type: 'button', class: 'danger small', 'data-act': 'quitar', text: 'Quitar',
        on: { click: function () { if (e.blobUrl) URL.revokeObjectURL(e.blobUrl); z.entries.splice(j, 1); rerenderZone(i); } } })]));
    li.appendChild(info);
    applyFrame(fr, e);
    return li;
  }
  /* the thumbnail with the framing the TV will use: a tap or a drag sets the focus point; the slider the zoom */
  function frameOf(z, i, e) {
    var src = entryShown(e);
    var fr = h('div', { class: 'frame', 'data-focus': '1', title: src ? 'Toque o arrastre para elegir el punto de enfoque' : null });
    fr.style.aspectRatio = zoneAspect(ED.template, i);
    if (src) {
      var img = h('img', { src: src, alt: '', draggable: 'false' });
      img.addEventListener('error', function () { img.remove(); fr.textContent = 'la foto no carga'; });
      fr.appendChild(img); fr.appendChild(h('i', { class: 'dot' }));
      /* the focus point from the keyboard too: arrows move it 5 %, with Shift 1 % */
      fr.setAttribute('tabindex', '0'); fr.setAttribute('role', 'img');
      fr.setAttribute('aria-label', 'Punto de enfoque: muévalo con las flechas (con Mayús, de 1 en 1)');
      fr.addEventListener('keydown', function (ev) {
        var d = ev.shiftKey ? 1 : 5, k = ev.key, f = e.focus || [50, 50];
        if (k === 'ArrowLeft') f = [f[0] - d, f[1]]; else if (k === 'ArrowRight') f = [f[0] + d, f[1]];
        else if (k === 'ArrowUp') f = [f[0], f[1] - d]; else if (k === 'ArrowDown') f = [f[0], f[1] + d]; else return;
        e.focus = [clampN(f[0], 0, 100, 50), clampN(f[1], 0, 100, 50)];
        applyFrame(fr, e); edChanged(); ev.preventDefault();
      });
    } else fr.textContent = e.item ? (z.labels !== false ? 'sin foto: el nombre sobre el fondo de la marca' : 'sin foto ni nombre: no se muestra; se verá el respaldo o la marca') : 'sin foto';
    var down = false;
    function at(ev) {
      var r = fr.getBoundingClientRect(); if (!r.width || !r.height) return;
      e.focus = [clampN((ev.clientX - r.left) / r.width * 100, 0, 100, 50), clampN((ev.clientY - r.top) / r.height * 100, 0, 100, 50)];
      applyFrame(fr, e); edChanged();
    }
    fr.addEventListener('pointerdown', function (ev) { if (!src) return; down = true; try { fr.setPointerCapture(ev.pointerId); } catch (x) {} at(ev); ev.preventDefault(); });
    fr.addEventListener('pointermove', function (ev) { if (down) at(ev); });
    ['pointerup', 'pointercancel'].forEach(function (k) { fr.addEventListener(k, function () { down = false; }); });
    return fr;
  }
  function applyFrame(fr, e) {
    var img = fr.querySelector('img'), dot = fr.querySelector('.dot'), f = e.focus;
    if (img) {
      img.style.objectPosition = f[0] + '% ' + f[1] + '%'; img.style.transformOrigin = f[0] + '% ' + f[1] + '%';
      img.style.transform = e.zoom !== 100 ? 'scale(' + (e.zoom / 100) + ')' : '';
    }
    if (dot) { dot.style.left = f[0] + '%'; dot.style.top = f[1] + '%'; }
    var ro = fr.parentNode ? fr.parentNode.querySelector('.focus') : null;
    if (ro) ro.textContent = 'Enfoque ' + f[0] + ' %, ' + f[1] + ' % · tamaño ' + e.zoom + ' %' + (img ? ' · toque o arrastre la miniatura' : '');
  }

  /* ----- the preview: the real pantalla-promos page in preview mode, told what this form holds ----- */
  var pvOpen = false, pvTimer = null;
  function edChanged() { clearTimeout(pvTimer); if (pvOpen) pvTimer = setTimeout(previewPost, 150); }
  function openEdPreview() {
    var box = $('edPreview'); if (!box || !ED) return;
    clear(box); box.hidden = false; pvOpen = true;
    var sel = $('edPvTv'), tv = S.screens.filter(function (x) { return x.id === sel.value; })[0] || promosTvs()[0] || { id: 'promos-1', kind: 'promos', name: 'TV de promociones', turn: 'no' };
    var vertical = tv.turn === 'derecha' || tv.turn === 'izquierda';
    var pv = h('div', { class: 'pv' + (vertical ? ' vertical' : ''), 'data-turn': tv.turn || 'no' });
    /* the real page reads nothing in preview mode: the TV's size, distance, scale, turn and look go in the address, so the
       letters, the places and the colours are the ones that TV will show */
    var q = '';
    [['pulgadas', tv.inches], ['distancia', tv.distance_m], ['escala', tv.scale_pct], ['giro', tv.turn], ['look', tv.look]].forEach(function (kv) {
      if (kv[1] !== undefined && kv[1] !== null && kv[1] !== '') q += '&' + kv[0] + '=' + encodeURIComponent(String(kv[1]));
    });
    var fr = h('iframe', { src: tvPath(tv) + '&preview=1' + q, title: 'Vista previa en ' + tv.name, tabindex: '-1' });
    fr.addEventListener('load', previewPost);
    pv.appendChild(fr); box.appendChild(pv);
    fitPreview(pv);
    $('edPreviewBtn').textContent = 'Cerrar la vista previa';
    previewPost();
  }
  function closeEdPreview() {
    pvOpen = false; clearTimeout(pvTimer);
    var box = $('edPreview'); if (box) { clear(box); box.hidden = true; }
    var b = $('edPreviewBtn'); if (b) b.textContent = 'Vista previa en la TV';
  }
  async function previewPost() {
    if (!pvOpen || !ED) return;
    var box = $('edPreview'), fr = box && box.querySelector('iframe');
    if (!fr || !fr.contentWindow) return;
    if (!(await ensureUploaded($('edErr')))) return;        /* a new photo must be somewhere the TV page can load it from */
    if (!pvOpen || !ED || !fr.contentWindow) return;
    fr.contentWindow.postMessage({ tipo: 'pantalla-preview', slide: previewSlide() }, location.origin);
  }
  function textOf(k) { var e = $('ed-' + k); return e && e.value.trim() ? e.value.trim() : null; }
  /* a menu item as pantalla_datos resolves it inside a slide */
  function itemJson(it) {
    return { id: it.id, name: it.name, name_es: it.name_es || null, price_crc: Number(it.price_crc) || 0, photo_url: it.photo_url || null,
             available: it.available === true, category: it.category || null, sellable: sellable(it) };
  }
  /* this form as pantalla_datos would give it to the TV (the same shape as _slide_json, nothing saved) */
  function previewSlide() {
    var a = edDate('start'), b = edDate('end'), t = nowMs(), so = parseInt($('edSort').value, 10);
    var s = { id: ED.id || 'previa', kind: ED.kind, menu_item_id: null, kicker_es: textOf('kicker_es'), kicker_en: textOf('kicker_en'),
              title_es: null, title_en: null, body_es: null, body_en: null, photo_url: null, link: null,
              screen_ids: ED.screens.length ? ED.screens.slice() : null,
              starts_at: new Date(a ? a.ms : t).toISOString(), ends_at: new Date(b ? b.ms : t + DAY).toISOString(),
              days: ED.days.length && ED.days.length < 7 ? ED.days.slice().sort() : null,
              from_time: $('edFrom').value || null, to_time: $('edTo').value || null, sort: isFinite(so) ? so : 100, status: 'activa',
              template: null, dwell_seconds: null, zones: [], usable: null, item: null };
    if (ED.kind === 'composicion') {
      var dw = parseInt($('edDwell').value, 10);
      s.template = ED.template; s.dwell_seconds = isFinite(dw) ? dw : null;
      s.zones = ED.zones.map(function (z) {
        var entries = z.entries.map(function (e) {
          return { item: e.item && !e.lost ? itemJson(e.item) : null, photo: entryPhoto(e), focus: e.focus.slice(), zoom: e.zoom };
        });
        return { mode: z.mode, seconds: z.mode === 'fija' ? 8 : Number(z.seconds) || 8, labels: !!z.labels, fallback: z.fbUploaded || z.fallback || null, entries: entries,
                 showable: z.entries.some(entryShowable) };
      });
      s.usable = s.zones.some(function (z) { return z.showable; });
    } else {
      s.title_es = textOf('title_es'); s.title_en = textOf('title_en'); s.body_es = textOf('body_es'); s.body_en = textOf('body_en');
      if (ED.kind === 'producto' && ED.item) { s.menu_item_id = ED.item.id; s.item = itemJson(ED.item); delete s.item.id; }
      if (ED.kind === 'invitacion') s.link = ED.link || null;
      if (ED.photoMode === 'propia') s.photo_url = ED.uploaded || ED.photo_url || null;
    }
    return s;
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
    if (ED.kind !== 'producto' && ED.kind !== 'composicion' && !$('ed-title_es').value.trim()) bad.push(['ed-title_es', 'Ponga el título en español.']);
    if (ED.kind === 'invitacion' && !ED.link) bad.push(['edLink', 'Elija a dónde lleva el código QR.']);
    if (ED.kind !== 'composicion' && ED.photoMode === 'propia' && !ED.blob && !ED.photo_url) bad.push(['edPick', 'Elija la foto, o marque la otra opción.']);
    if (ED.kind === 'composicion') {
      if (!tplOf(ED.template)) bad.push(['edTemplates', 'Elija la plantilla.']);
      ED.zones.forEach(function (z, i) {
        var name = placeName(ED.template, i), zid = 'edZerr-' + i, n = z.entries.length, sec = Number(z.seconds);
        if (!n) bad.push([zid, name + ': agregue al menos un producto o una foto.']);
        else if (z.mode === 'fija' && n !== 1) bad.push([zid, name + ': una foto fija lleva una sola entrada; quite las demás o pásela a presentación.']);
        else if (n > 12) bad.push([zid, name + ': a lo sumo 12 entradas.']);
        if (z.mode === 'auto' && (String(z.seconds).trim() === '' || !isFinite(sec) || sec < 4 || sec > 60 || Math.round(sec) !== sec)) {
          bad.push(['edZ-' + i + '-seconds', name + ': los segundos van de 4 a 60, sin decimales.']);
        }
        z.entries.forEach(function (e, j) {
          if (e.lost || (!e.item && !entryPhoto(e) && !e.blob)) bad.push([zid, name + ', entrada ' + (j + 1) + ': lleva un producto del menú o una foto.']);
        });
      });
      var dw = $('edDwell').value.trim();
      if (dw !== '' && !(/^\d{1,3}$/.test(dw) && Number(dw) >= 10 && Number(dw) <= 600)) bad.push(['edDwell', 'La permanencia va de 10 a 600 segundos (vacía = 60).']);
    }
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
    p.photo_url = ED.kind !== 'composicion' && ED.photoMode === 'propia' ? (ED.uploaded || (ED.blob ? '' : ED.photo_url) || '') : '';
    if (ED.kind === 'composicion') {
      /* the zones as they stand: the server is the judge (a fixed zone with more than one entry is refused there too) */
      p.template = ED.template;
      p.dwell_seconds = $('edDwell').value.trim();            /* empty: 60 on the TV */
      p.zones = ED.zones.map(function (z) {
        return { mode: z.mode, seconds: z.mode === 'fija' ? 8 : Number(z.seconds) || 8, labels: !!z.labels, fallback: z.fbUploaded || z.fallback || '',
                 entries: z.entries.map(function (e) {
                   return { item: e.item && !e.lost ? e.item.id : null, photo: entryPhoto(e), focus: [e.focus[0], e.focus[1]], zoom: e.zoom };
                 }) };
      });
    }
    var a = edDate('start'), b = edDate('end');
    p.starts_at = a === null ? '' : a.iso; p.ends_at = b === null ? '' : b.iso;
    p.days = ED.days.slice().sort();               /* all seven: the server keeps "every day" */
    p.from_time = $('edFrom').value || ''; p.to_time = $('edTo').value || '';
    p.screen_ids = ED.screens.slice();              /* none: every promotions TV */
    var so = parseInt($('edSort').value, 10); p.sort = isFinite(so) ? so : 100;
    if (!ED.id && $('edPaused') && $('edPaused').checked) p.status = 'pausada';
    return p;
  }
  /* a refused field, marked where the owner sees it: a text, a control, a zone or one of its entries */
  function markField(fld, msg) {
    if (!fld) return;
    var map = { menu_item_id: 'edSearch', link: 'edLink', sort: 'edSort', photo_url: 'edPick', template: 'edTemplates', dwell_seconds: 'edDwell' };
    var e2 = $('ed-' + fld) || $(map[fld]);
    if (e2) e2.classList.add('bad');
    var zm = /^zones\.(\d+)(?:\.(mode|seconds|labels|fallback|entries)(?:\.(\d+))?)?/.exec(fld);
    if (!zm) return;
    var sel = '#edZones .zone[data-zone="' + zm[1] + '"]', zone = document.querySelector(sel);
    zoneMsg(zm[1], msg);
    var li = zm[3] !== undefined ? document.querySelector(sel + ' .entry[data-entry="' + zm[3] + '"]') : null;
    if (li) li.classList.add('bad'); else if (zone) zone.classList.add('bad');
    if (zm[2] === 'seconds') { var s = $('edZ-' + zm[1] + '-seconds'); if (s) s.classList.add('bad'); }
  }
  var saving = false;
  async function saveSlide() {
    if (saving || !ED) return;
    var err = $('edErr'), test = window.PANTALLAS_TEST || {};
    document.querySelectorAll('#slideForm .bad').forEach(function (e) { if (!/^ed-/.test(e.id)) e.classList.remove('bad'); });
    document.querySelectorAll('#slideForm [id^="edZerr-"]').forEach(function (e) { e.textContent = ''; e.classList.remove('ok'); });
    err.textContent = '';
    if (!test.sinRevisar) {
      var bad = checkSlide();
      if (bad.length) {
        bad.forEach(function (b) {
          var e = b[0] && $(b[0]); if (!e) return;
          e.classList.add('bad');
          if (/^edZerr-/.test(b[0])) e.textContent = e.textContent ? e.textContent + ' ' + b[1] : b[1];
        });
        err.textContent = bad.map(function (b) { return b[1]; }).join(' ');
        var first = bad[0][0] && $(bad[0][0]); if (first && first.focus) first.focus();
        return;
      }
    }
    saving = true; BUSY++;
    var btn = $('edSave'); btn.disabled = true; btn.textContent = 'Guardando…';
    try {
      var pm = $('edPhotoMsg');
      if (ED.kind !== 'composicion' && ED.photoMode === 'propia' && ED.blob && !ED.uploaded && pm) { pm.classList.remove('ok'); pm.textContent = 'Subiendo la foto…'; }
      var up = await ensureUploaded(err);
      if (pm) pm.textContent = '';
      if (!up) return;
      var p = payload();
      if (typeof test.antesDeEnviar === 'function') p = test.antesDeEnviar(p) || p;   /* the tests send past the page what it blocks */
      var r;
      try { r = await db.rpc('diapositiva_guardar', { p: p }); } catch (e) { r = { error: e }; }
      if (r.error || !r.data || !r.data.ok) {
        if (r.data && r.data.error === 'owner_only') { await dropUploaded(); showOwnerOnly(); return; }
        err.textContent = errText(r);
        markField(r.data && r.data.field, err.textContent);
        if (r.data && r.data.error === 'dates_required') { $('edEnd').classList.add('bad'); }
        await dropUploaded();
        if (r.data && (r.data.error === 'not_found' || r.data.error === 'retired')) { closeEditor(); toast(err.textContent); await loadState(); }
        return;
      }
      await dropUnused(p);               /* the slide keeps its photos; one uploaded and then taken out of the form goes */
      closeEditor();
      await loadState();
      toast('Guardado');
    } finally {
      saving = false; BUSY--;
      var b2 = $('edSave'); if (b2) { b2.textContent = 'Guardar'; checkTexts(); }
    }
  }

  /* ----- «Programación sugerida»: four compositions for the day, paused, from the menu's own categories ----- */
  var SUGERIDAS = [
    { t: 'Desayuno', en: 'Breakfast', from: '06:00', to: '10:00', template: '4-centro', sort: 10, zones: ['reposteria', 'cafesFrios', 'cafesCalientes', 'sandwiches'] },
    { t: 'Almuerzo', en: 'Lunch', from: '10:00', to: '13:00', template: '3-grande-izq', sort: 20, zones: ['sandwiches', 'batidos', 'bebidasFrias'] },
    { t: 'Tarde', en: 'Afternoon', from: '13:00', to: '17:00', template: '2-lado', sort: 30, zones: ['cafesCalientes', 'reposteria'] },
    { t: 'Cena', en: 'Dinner', from: '17:00', to: '19:00', template: '1', sort: 40, zones: ['sandwiches'] }
  ];
  var RX_FRIO = /iced|fr[ií][oa]s?\b|helad[oa]s?\b/i;
  function catIs(it, rx) { return rx.test(String(it.category || '')); }
  function nameIs(it, rx) { return rx.test(String(it.name || '')) || rx.test(String(it.name_es || '')); }
  function firstOf(list, rx) { return list.filter(function (x) { return nameIs(x, rx); }).concat(list.filter(function (x) { return !nameIs(x, rx); })); }
  /* the menu's items by the groups the suggested day uses, matched by the categories' and items' names */
  function grupos() {
    var items = S.items.filter(function (it) { return it.category !== 'Extras & Combos' && Number(it.price_crc) > 0; });
    var coffee = items.filter(function (it) { return catIs(it, /coffee|caf[eé]s?\b/i); });
    var frios = coffee.filter(function (it) { return nameIs(it, RX_FRIO); }), calientes = coffee.filter(function (it) { return !nameIs(it, RX_FRIO); });
    var pastries = items.filter(function (it) { return catIs(it, /pastr|cake|repost|queque|postre/i); });
    var savory = items.filter(function (it) { return catIs(it, /savory|savoury|salad|bocas|sal[ae]d[oa]s?\b/i) && pastries.indexOf(it) < 0; });
    var cafesFrios = firstOf(frios, /iced latte|latte.*(fr[ií]o|helado)/i);
    return {
      reposteria: firstOf(pastries.concat(savory), /croissant|cruas[aá]n|cuernito/i),
      sandwiches: items.filter(function (it) { return catIs(it, /s[aá]ndwich/i); }),
      cafesFrios: cafesFrios,
      cafesCalientes: firstOf(firstOf(calientes, /caf[eé] con leche/i), /^latte$/i),
      batidos: items.filter(function (it) { return catIs(it, /smoothie|batido|licuado/i); }),
      bebidasFrias: cafesFrios.concat(items.filter(function (it) { return catIs(it, /other drinks|drinks|bebidas|refrescos/i); }))
    };
  }
  /* the owner (2026-11-02): the four start without names and prices; «Nombres y precios» per zone in the editor turns them on.
     Each window turns at a pace of its own, by its place in the template: at 3 m a window changing every 8 s, four of
     them, read as a fade every 2 s, and equal seconds make the windows change together. A template reduced for a
     group without products takes the smaller template's seconds */
  var SEGUNDOS = { '4-centro': [14, 16, 18, 20], '3-grande-izq': [12, 15, 18], '2-lado': [12, 15], '1': [10] };
  function zoneOfItems(list, i, tpl) {
    return { mode: 'auto', seconds: (SEGUNDOS[tpl] || [])[i] || 12, labels: false, fallback: '',
             entries: list.slice(0, 12).map(function (it) { return { item: it.id, photo: null, focus: [50, 50], zoom: 100 }; }) };
  }
  $('sugerir').addEventListener('click', async function () {
    if (!S) return;
    var btn = $('sugerir'), msg = $('sugerirMsg'), g = grupos();
    var existing = S.slides.filter(function (s) { return s.status !== 'retirada'; }).map(slideTitle);
    var t = Math.floor(nowMs() / 60000) * 60000, made = [], had = [], empty = [], failed = null;
    msg.textContent = ''; btn.disabled = true; BUSY++;
    try {
      for (var k = 0; k < SUGERIDAS.length; k++) {
        var plan = SUGERIDAS[k];
        if (existing.indexOf(plan.t) > -1) { had.push(plan.t); continue; }
        var lists = plan.zones.map(function (key) { return g[key] || []; }), kept = lists.filter(function (l) { return l.length; });
        if (!kept.length) { empty.push(plan.t); continue; }
        /* the server wants every zone with something in it: a group without products loses its place, and the
           owner fills a smaller template or changes it */
        var tpl = kept.length === lists.length ? plan.template : { 3: '3-grande-izq', 2: '2-lado', 1: '1' }[kept.length];
        var p = { kind: 'composicion', kicker_es: plan.t, kicker_en: plan.en, template: tpl, dwell_seconds: '', zones: kept.map(function (l, i) { return zoneOfItems(l, i, tpl); }),
                  starts_at: new Date(t).toISOString(), ends_at: new Date(t + 365 * DAY).toISOString(), days: [1, 2, 3, 4, 5, 6, 7],
                  from_time: plan.from, to_time: plan.to, screen_ids: [], sort: plan.sort, status: 'pausada' };
        var r;
        try { r = await db.rpc('diapositiva_guardar', { p: p }); } catch (e) { r = { error: e }; }
        if (r.error || !r.data || !r.data.ok) {
          if (r.data && r.data.error === 'owner_only') { showOwnerOnly(); return; }
          failed = 'No se pudo crear «' + plan.t + '»: ' + errText(r); break;
        }
        made.push(plan.t + ' (' + plan.from + '–' + plan.to + (tpl !== plan.template ? ', con ' + kept.length + (kept.length === 1 ? ' zona' : ' zonas') + ': faltan productos de alguna categoría' : '') + ')');
      }
    } finally { BUSY--; btn.disabled = false; }
    if (made.length) await loadState();
    msg.textContent = (made.length ? 'Se crearon en pausa: ' + made.join(', ') + '. Revíselas, ajústelas y actívelas cuando quiera: ninguna sale sola. ' +
                                     'Van sin nombres ni precios; actívelos por ventana en el editor. Un producto sin foto no se muestra mientras ' +
                                     'su ventana vaya sin nombres: súbale foto en el Gestor de menú o elija otra en el editor.' : 'No se creó nada.')
      + (had.length ? ' Ya existían: ' + had.join(', ') + '.' : '') + (empty.length ? ' Sin productos del menú para: ' + empty.join(', ') + '.' : '')
      + (failed ? ' ' + failed : '');
  });

  /* ---------- 10) a photo: made smaller here, then kept in Storage (menu-photos/pantallas/) ---------- */
  var MAX_BYTES = 8 * 1024 * 1024, MAX_W = 1600, MAX_H = 2400;
  var photoTarget = null;    /* where the next chosen file goes, always with the editor it was chosen in (ed): {own} = the
                                slide's own photo; {zone, zoneObj, fallback?} = a composition zone's new entry or fallback;
                                {zone, zoneObj, entryObj} = the photo of that entry, replaced in its place («Cambiar foto»).
                                A file that arrives after its editor was closed or replaced, or its zone or entry removed, goes nowhere */
  $('photoFile').addEventListener('change', async function () {
    var f = this.files && this.files[0], target = photoTarget; photoTarget = null;
    this.value = '';
    if (!target && ED) target = { own: true, ed: ED };      /* a file given to the input without its button: the slide's own photo */
    if (!f || !ED || target.ed !== ED) return;              /* the file belongs to the editor it was chosen in */
    var compo = ED.kind === 'composicion' && !target.own && ED.zones[target.zone];
    var msg = compo ? $('edZerr-' + target.zone) : $('edPhotoMsg');
    if (!msg) return;
    msg.classList.remove('ok');
    if (f.size > MAX_BYTES) { msg.textContent = 'La foto pesa más de 8 MB. Elija una más liviana.'; return; }
    if (f.type && !/^image\//.test(f.type)) { msg.textContent = 'Ese archivo no es una foto.'; return; }
    msg.textContent = 'Preparando la foto…';
    var out;
    try { out = await shrink(f); } catch (e) { msg.textContent = 'No se pudo leer esa foto. Pruebe con otra (JPEG o PNG).'; return; }
    if (!ED || target.ed !== ED) return;   /* that editor was closed or replaced while the photo was prepared */
    var ready = 'Lista: ' + out.w + ' × ' + out.h + ' px, ' + Math.max(1, Math.round(out.blob.size / 1024)) + ' KB.';
    if (compo) {
      var zi = target.zoneObj ? ED.zones.indexOf(target.zoneObj) : target.zone;
      if (zi < 0 && !target.entryObj) return;   /* its zone left the template while the photo was prepared */
      if (target.entryObj) {
        /* «Cambiar foto»: its entry found again where it is now (moved up or down, or its zone swapped, while the photo
           was being prepared); taken out, or in an editor closed meanwhile, the photo goes nowhere */
        if (target.ed !== ED) return;
        zi = ED.zones.indexOf(target.zoneObj);
        if (zi < 0 || target.zoneObj.entries.indexOf(target.entryObj) < 0) {
          zoneMsg(zi < 0 ? target.zone : zi, 'Esa entrada ya no está. Elija la foto otra vez.'); return;
        }
      }
      var z = ED.zones[zi], url = URL.createObjectURL(out.blob);
      if (target.fallback) {
        if (z.fbBlobUrl) URL.revokeObjectURL(z.fbBlobUrl);
        z.fbBlob = out.blob; z.fbBlobUrl = url; z.fbUploaded = null; z.fallback = null;
      } else if (target.entryObj) {
        /* the entry keeps its place and its product; a new picture, so the framing starts again */
        var was = target.entryObj;
        if (was.blobUrl) URL.revokeObjectURL(was.blobUrl);
        was.blob = out.blob; was.blobUrl = url; was.uploaded = null; was.photo = null; was.lost = false;
        was.focus = [50, 50]; was.zoom = 100;
      } else {
        if (z.entries.length >= 12) { URL.revokeObjectURL(url); msg.textContent = 'A lo sumo 12 entradas por zona.'; return; }
        var en = newEntry(null, null); en.blob = out.blob; en.blobUrl = url;
        z.entries.push(en);
      }
      rerenderZone(zi);
      zoneMsg(zi, ready + ' Se sube al guardar o al abrir la vista previa.', true);
      return;
    }
    if (ED.blobUrl) URL.revokeObjectURL(ED.blobUrl);
    ED.blob = out.blob; ED.blobUrl = URL.createObjectURL(out.blob); ED.uploaded = null; ED.photoMode = 'propia';
    renderPhoto();
    msg.classList.add('ok');
    msg.textContent = ready + ' Se sube al guardar.';
    edChanged();
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
    var url = db.storage.from('menu-photos').getPublicUrl(path).data.publicUrl;
    ED.uploadedPaths.push({ path: path, url: url });
    return url;
  }
  /* every photo of the form not yet in Storage goes up now (before a save, or before the preview can show it); one
     attempt at a time */
  var uploading = null;
  function ensureUploaded(err) {
    if (uploading) return uploading.then(function () { return ensureUploaded(err); });
    uploading = uploadAll(err);
    return uploading.then(function (ok) { uploading = null; return ok; }, function (e) { uploading = null; throw e; });
  }
  async function uploadAll(err) {
    try {
      /* an upload counts only for the photo it took: one replaced («Cambiar foto», another photo) or taken out («Foto del
         menú», Quitar) while it went up is not kept as the new one, which goes up in the next round. The late file stays
         in ED.uploadedPaths, so dropUnused / dropUploaded take it away. Rounds until one finds nothing new to upload */
      for (var more = true; more;) {
        more = false;
        if (!ED) return false;
        if (ED.kind !== 'composicion') {
          if (ED.photoMode === 'propia' && ED.blob && !ED.uploaded) {
            more = true; var b = ED.blob, u = await uploadPhoto(b); if (ED.blob === b) ED.uploaded = u;
          }
          continue;
        }
        for (var i = 0; i < ED.zones.length; i++) {
          var z = ED.zones[i];
          if (z.fbBlob && !z.fbUploaded) { more = true; var fb = z.fbBlob, fu = await uploadPhoto(fb); if (z.fbBlob === fb) z.fbUploaded = fu; }
          for (var j = 0; j < z.entries.length; j++) {
            var e = z.entries[j];
            if (e.blob && !e.uploaded) { more = true; var eb = e.blob, eu = await uploadPhoto(eb); if (e.blob === eb) e.uploaded = eu; }
          }
        }
      }
      return true;
    } catch (e) {
      var m = String((e && e.message) || e || '');
      if (err) {
        err.textContent = isOffline(m) ? OFFLINE : /row-level security|Unauthorized|403|permission/i.test(m)
          ? 'No se pudo subir la foto: el PIN venció o no alcanza. Vuelva a abrir con el PIN del dueño.'
          : 'No se pudo subir la foto. Vuelva a intentar.';
      }
      return false;
    }
  }
  /* the photos uploaded for a slide the server did not accept (or the owner gave up on) are taken away: no orphan file */
  async function dropUploaded() {
    if (!ED || !ED.uploadedPaths.length) return;
    var paths = ED.uploadedPaths.map(function (x) { return x.path; }); ED.uploadedPaths = [];
    ED.uploaded = null;
    ED.zones.forEach(function (z) { z.fbUploaded = null; z.entries.forEach(function (e) { e.uploaded = null; }); });
    try { await db.storage.from('menu-photos').remove(paths); } catch (e) {}
  }
  /* after a save: the photos the slide uses stay; one uploaded (for the preview) and then taken out of the form goes */
  async function dropUnused(p) {
    if (!ED || !ED.uploadedPaths.length) return;
    var used = [p.photo_url];
    (p.zones || []).forEach(function (z) { used.push(z.fallback); z.entries.forEach(function (e) { used.push(e.photo); }); });
    var gone = ED.uploadedPaths.filter(function (x) { return used.indexOf(x.url) < 0; }).map(function (x) { return x.path; });
    ED.uploadedPaths = [];
    if (gone.length) { try { await db.storage.from('menu-photos').remove(gone); } catch (e) {} }
  }

  /* ---------- 11) today on each promotions TV ---------- */
  /* a slide in today's list: its title, its kind (a composition with its zones) and when it goes off or comes on */
  function todayItem(s, when) {
    var kids = [h('b', { text: slideTitle(s) }), h('span', { text: (s.kind === 'composicion' ? 'Composición · ' + tplLabel(s.template) : KIND[s.kind]) + when })];
    if (s.kind === 'composicion') kids.push(h('span', { class: 'zs', text: zonesText(s) }));
    return h('li', { 'data-slide': s.id, 'data-kind': s.kind }, kids);
  }
  function renderToday() {
    var host = clear($('todayList')), tvs = slideTvs(), t = nowMs();
    if (!tvs.length) { host.appendChild(h('p', { class: 'empty', text: 'No hay TV de promociones.' })); return; }
    tvs.forEach(function (tv) {
      var card = h('article', { class: 'card today', 'data-today': tv.id });
      var on = tvOn(tv, t), chip = !tv.active ? ['Desactivada', 'c-bad']
        : !tv.on_from ? ['Encendida siempre', 'c-ok'] : on ? ['Encendida ahora (' + tv.on_from + '–' + tv.on_to + ')', 'c-ok']
        : ['Apagada por su horario (' + tv.on_from + '–' + tv.on_to + ')', 'c-mute'];
      card.appendChild(h('h2', {}, [h('span', { text: tv.name }), h('span', { class: 'chip ' + chip[1], text: chip[0] })]));
      card.appendChild(h('p', { class: 'hint', text: 'Hoy ' + fecha(t) + ' (hora del servidor, Costa Rica).' +
        (tv.kind === 'menu' ? ' TV de menú: las intercala cada ' + tv.promo_every + ' s, durante ' + tv.promo_seconds + ' s, entre las páginas del menú.' : '') }));
      var mine = S.slides.filter(function (s) { return s.status === 'activa' && forTv(s, tv); });
      var now = mine.filter(function (s) { return live(s, tv, t); });
      var later = mine.map(function (s) { return { s: s, at: laterToday(s, tv, t) }; }).filter(function (x) { return x.at; })
        .sort(function (a, b) { return a.at - b.at; });
      card.appendChild(h('h3', { text: 'Ahora' }));
      if (now.length) {
        card.appendChild(h('ol', { 'data-list': 'ahora' }, now.map(function (s) {
          var off = offToday(s, tv, t);
          return todayItem(s, off ? ' · hasta las ' + hora(off) : ' · todo el día');
        })));
      } else card.appendChild(h('p', { class: 'none', text: tv.kind === 'menu' ? 'Ninguna: el menú no se interrumpe.' : 'Ninguna: la TV muestra la presentación de la marca.' }));
      card.appendChild(h('h3', { text: 'Más tarde hoy' }));
      if (later.length) {
        card.appendChild(h('ol', { 'data-list': 'luego' }, later.map(function (x) { return todayItem(x.s, ' · desde las ' + hora(x.at)); })));
      } else card.appendChild(h('p', { class: 'none', text: 'Nada más hoy.' }));
      if (!tv.active || !on) card.appendChild(h('p', { class: 'hint', text: !tv.active ? 'Desactivada, esta TV no muestra nada de esto.' : 'Mientras esté apagada por su horario, no se ve nada.' }));
      host.appendChild(card);
    });
  }

  /* ---------- 12) the change log ---------- */
  var ACTION = { crear: 'Creó', cambiar: 'Cambió', pausar: 'Pausó', reanudar: 'Reanudó', retirar: 'Retiró' };
  var LABEL = {
    name: 'Nombre', kind: 'Tipo', inches: 'Tamaño (pulgadas)', distance_m: 'Distancia (m)', turn: 'Posición', scale_pct: 'Escala de letra (%)',
    look: 'Colores', page_seconds: 'Segundos por página', slide_seconds: 'Segundos por diapositiva', category_ids: 'Categorías', item_ids: 'Productos',
    sold_out: 'Agotados', on_from: 'Encendida desde', on_to: 'Encendida hasta', active: 'Activa', status: 'Estado',
    menu_item_id: 'Producto', kicker_es: 'Línea de arriba (es)', kicker_en: 'Línea de arriba (en)', title_es: 'Título (es)',
    title_en: 'Título (en)', body_es: 'Texto (es)', body_en: 'Texto (en)', photo_url: 'Foto', link: 'Código QR', screen_ids: 'TV',
    starts_at: 'Desde', ends_at: 'Hasta', days: 'Días', from_time: 'De las', to_time: 'A las', sort: 'Orden',
    layout: 'Distribución', density: 'Densidad', english: 'Inglés', promo_mode: 'Promociones', promo_every: 'Una promoción cada (s)',
    promo_seconds: 'Cada promoción dura (s)', template: 'Plantilla', zones: 'Zonas', dwell_seconds: 'Permanencia (s)'
  };
  var SKIP = { updated_at: 1, id: 1, item: 1, created_at: 1, usable: 1, tiles: 1 };
  function optLabel(table, v) { var o = table.filter(function (x) { return x[0] === v; })[0]; return o ? o[1] : v; }
  /* the zones of a composition as written in the log (ids and framing only): one line per zone */
  function zonesLog(v) {
    if (!Array.isArray(v)) return String(v);
    return v.map(function (z, i) {
      var en = Array.isArray(z && z.entries) ? z.entries : [];
      return (i + 1) + ') ' + (z && z.mode === 'auto' ? 'presentación cada ' + (z.seconds || 8) + ' s' : 'foto fija') + ' · ' +
        en.map(function (e) {
          var it = e && e.item ? (S.items || []).filter(function (x) { return x.id === e.item; })[0] : null;
          var what = it ? itemName(it) : e && e.item ? 'producto ' + String(e.item).slice(0, 8) : 'foto';
          var fr = e && Array.isArray(e.focus) ? ' (' + e.focus.join(' %, ') + ' %' + (e.zoom && e.zoom !== 100 ? ', ' + e.zoom + ' %' : '') + ')' : '';
          return what + fr;
        }).join(', ') + (z && z.labels === false ? ' · sin nombres' : '') + (z && z.fallback ? ' · con respaldo' : '');
    }).join(' / ');
  }
  function show(k, v) {
    if (v === null || v === undefined || v === '' || (Array.isArray(v) && !v.length)) {
      return k === 'category_ids' ? 'todas' : k === 'item_ids' ? 'todos' : k === 'screen_ids' ? 'todas' : k === 'days' ? 'todos' : k === 'dwell_seconds' ? '60' : '—';
    }
    if (typeof v === 'boolean') return v ? 'sí' : 'no';
    if (k === 'zones') return zonesLog(v);
    if (k === 'template') return tplLabel(v);
    if (k === 'layout') return optLabel(LAYOUT, v);
    if (k === 'density') return optLabel(DENSITY, v);
    if (k === 'english') return optLabel(ENGLISH, v);
    if (k === 'promo_mode') return optLabel(PROMO, v);
    if (k === 'starts_at' || k === 'ends_at') return fecha(T(v));
    if (k === 'days') return daysText(v);
    if (k === 'category_ids') return v.map(function (id) { var c = (S.categories || []).filter(function (x) { return x.id === id; })[0]; return c ? c.name : id; }).join(', ');
    if (k === 'menu_item_id') { var it = (S.items || []).filter(function (x) { return x.id === v; })[0]; return it ? itemName(it) : String(v); }
    if (k === 'item_ids') {
      return v.map(function (id) {
        var x = (S.items || []).filter(function (i) { return String(i.id).toLowerCase() === String(id).toLowerCase(); })[0];
        return x ? itemName(x) : String(id);
      }).join(', ');
    }
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
