/* Canopy OS · on-screen keypads for touch screens, and what makes a PIN box a PIN box.
   - PIN fields (input data-pin, or the older input type=password inputmode=numeric) and fields marked
     data-keypad="pin|amount|qty" get a large number pad right under them (data-keypad="off": the page has its own).
   - Text fields get a full Spanish keyboard (ñ, accents) only on a device where it was switched on
     (HG_KEYPAD.setText(true)): a register PC with a touch screen and no keyboard of its own.
   The pads only type into the field and fire the same "input" event a real keyboard does, so every page keeps
   working as before; a physical keyboard keeps working too. Per device: HG_KEYPAD.setMode('auto'|'on'|'off').
   - A PIN box (data-pin) is a plain box drawn as dots, so browsers and password managers never take it for a password:
     they do not offer to save one there and do not fill one in. Only a PIN a person types counts: a real key or a tap on
     the on-screen keys. Anything else that puts a PIN in (a saved entry, an extension) is wiped at once, and the form
     does not go. */
(function () {
  'use strict';
  var KEY = 'hg-keypad', TKEY = 'hg-keypad-text';
  function get(k, d) { try { return localStorage.getItem(k) || d; } catch (e) { return d; } }
  function set(k, v) { try { localStorage.setItem(k, v); } catch (e) {} }
  var touch = window.matchMedia ? window.matchMedia('(pointer: coarse)').matches : false;
  function numOn() { var m = get(KEY, 'auto'); return m === 'on' || (m === 'auto' && touch); }
  function textOn() { return get(TKEY, 'off') === 'on'; }

  var css = document.createElement('style');
  css.textContent =
    '.hg-pad{display:grid;gap:8px;margin:.6rem 0 .2rem;user-select:none;-webkit-user-select:none;touch-action:manipulation}' +
    '.hg-pad.num{grid-template-columns:repeat(3,1fr);max-width:340px}' +
    '.hg-pad button{all:unset;box-sizing:border-box;display:flex;align-items:center;justify-content:center;min-height:58px;border-radius:12px;' +
    'background:var(--panel,#fff);border:1.5px solid var(--muted,#C9CFB6);color:var(--ink,#1f2a24);font:700 1.45rem/1 system-ui,-apple-system,Segoe UI,Roboto,sans-serif;cursor:pointer}' +
    '.hg-pad button:active{background:var(--canvas,#F3EEE3);transform:scale(.97)}' +
    '.hg-pad button.ok{background:var(--accent,#1E4B33);border-color:var(--accent,#1E4B33);color:#fff}' +
    '.hg-pad button.fn{font-size:1.1rem}' +
    '.hg-pad button:focus-visible{outline:3px solid var(--gold,#B98A35);outline-offset:2px}' +
    '.hg-kb{position:fixed;left:0;right:0;bottom:0;z-index:2147482000;background:var(--canvas,#F3EEE3);border-top:1.5px solid var(--muted,#C9CFB6);' +
    'padding:8px 8px calc(8px + env(safe-area-inset-bottom));display:grid;gap:6px;box-shadow:0 -6px 24px rgba(0,0,0,.12)}' +
    '.hg-kb .row{display:flex;gap:6px;justify-content:center}' +
    '.hg-kb button{all:unset;box-sizing:border-box;flex:1;max-width:76px;min-height:54px;display:flex;align-items:center;justify-content:center;border-radius:10px;' +
    'background:var(--panel,#fff);border:1.5px solid var(--muted,#C9CFB6);color:var(--ink,#1f2a24);font:600 1.2rem/1 system-ui,sans-serif;cursor:pointer}' +
    '.hg-kb button.wide{max-width:none;flex:3}.hg-kb button.fn{max-width:120px;flex:1.6;font-size:1rem}' +
    '.hg-kb button.ok{background:var(--accent,#1E4B33);color:#fff;border-color:var(--accent,#1E4B33)}' +
    'input[data-pin]{-webkit-text-security:disc}' +
    '@media print{.hg-pad,.hg-kb{display:none}}';
  document.head.appendChild(css);

  function typeInto(input, fn) {
    var v = fn(input.value || '');
    var max = Number(input.getAttribute('maxlength')) || 0;
    if (max > 0 && v.length > max) return;
    input.__hgBefore = input.value;
    input.value = v;
    input.__hgKeyed = true;                          // a tap on the on-screen keys: a person typing
    input.dispatchEvent(new Event('input', { bubbles: true }));
  }
  function done(input) {
    var form = input.form;
    if (form && form.requestSubmit) { form.requestSubmit(); return; }
    var ok = input.getAttribute('data-keypad-ok');
    var btn = ok && document.querySelector(ok);
    if (btn) btn.click(); else input.blur();
  }
  function keep(e) { e.preventDefault(); }          // tapping the pad never takes the focus away from the field

  /* ---------- the number pad ---------- */
  function kindOf(input) {
    var k = input.getAttribute('data-keypad');
    if (k) return k === 'off' ? null : k;
    if (input.hasAttribute('data-pin')) return 'pin';
    if (input.type === 'password' && input.getAttribute('inputmode') === 'numeric') return 'pin';
    return null;
  }
  function numPad(input, kind) {
    var pad = document.createElement('div');
    pad.className = 'hg-pad num'; pad.setAttribute('data-no-translate', '');
    pad.setAttribute('role', 'group'); pad.setAttribute('aria-label', kind === 'pin' ? 'PIN keypad' : 'Number keypad');
    var keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9'];
    keys = keys.concat(kind === 'amount' ? ['000', '0', '⌫'] : kind === 'qty' ? ['.', '0', '⌫'] : ['⌫', '0', '✓']);
    keys.forEach(function (k) {
      var b = document.createElement('button'); b.type = 'button'; b.textContent = k;
      if (k === '⌫') { b.className = 'fn'; b.setAttribute('aria-label', 'Erase'); }
      if (k === '✓') { b.className = 'ok'; b.setAttribute('aria-label', 'Done'); }
      b.addEventListener('pointerdown', keep);
      b.addEventListener('click', function (e) {
        if (kind === 'pin' && k !== '✓' && !e.isTrusted) return;   // a PIN key pressed by a script types nothing
        if (k === '⌫') typeInto(input, function (v) { return v.slice(0, -1); });
        else if (k === '✓') done(input);
        else if (k === '.') typeInto(input, function (v) { return v.indexOf('.') > -1 ? v : (v || '0') + '.'; });
        else typeInto(input, function (v) { return v + k; });
      });
      pad.appendChild(b);
    });
    if (kind !== 'pin') {
      var clear = document.createElement('button'); clear.type = 'button'; clear.className = 'fn'; clear.textContent = 'C';
      clear.setAttribute('aria-label', 'Clear');
      clear.addEventListener('pointerdown', keep);
      clear.addEventListener('click', function () { typeInto(input, function () { return ''; }); });
      var ok = document.createElement('button'); ok.type = 'button'; ok.className = 'ok'; ok.textContent = '✓';
      ok.setAttribute('aria-label', 'Done'); ok.style.gridColumn = 'span 2';
      ok.addEventListener('pointerdown', keep);
      ok.addEventListener('click', function () { done(input); });
      pad.appendChild(clear); pad.appendChild(ok);
    }
    return pad;
  }
  function attachNum(input) {
    if (input.__hgPad !== undefined) return;
    var kind = kindOf(input);
    input.__hgPad = null;
    if (!kind) return;
    var pad = numPad(input, kind);
    pad.hidden = true;
    input.insertAdjacentElement('afterend', pad);
    input.__hgPad = pad;
    input.__hgMode = input.getAttribute('inputmode');
    input.addEventListener('blur', function () {
      pad.hidden = true;
      if (input.__hgMode === null) input.removeAttribute('inputmode'); else input.setAttribute('inputmode', input.__hgMode);
    });
  }
  function showNum(input) {
    if (!input.__hgPad || !numOn() || input.disabled || input.readOnly) return;
    input.setAttribute('inputmode', 'none');      // no phone keyboard on top of ours
    input.__hgPad.hidden = false;
  }

  /* ---------- the text keyboard (opt-in per device) ---------- */
  var kb = null, kbInput = null, shift = false;
  var ROWS = [['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'], ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
              ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', 'ñ'], ['⇧', 'z', 'x', 'c', 'v', 'b', 'n', 'm', '⌫'],
              ['á', 'é', 'í', 'ó', 'ú', ',', '.', '-', '@'], ['space', '✓']];
  function buildKb() {
    kb = document.createElement('div'); kb.className = 'hg-kb'; kb.hidden = true; kb.setAttribute('data-no-translate', '');
    kb.setAttribute('role', 'group'); kb.setAttribute('aria-label', 'Keyboard');
    ROWS.forEach(function (row) {
      var r = document.createElement('div'); r.className = 'row';
      row.forEach(function (k) {
        var b = document.createElement('button'); b.type = 'button';
        b.textContent = k === 'space' ? ' ' : k; b.dataset.k = k;
        if (k === 'space') { b.className = 'wide'; b.setAttribute('aria-label', 'Space'); }
        if (k === '⇧' || k === '⌫') b.className = 'fn';
        if (k === '✓') { b.className = 'fn ok'; b.setAttribute('aria-label', 'Done'); }
        b.addEventListener('pointerdown', keep);
        b.addEventListener('click', function () {
          if (!kbInput) return;
          if (k === '⇧') { shift = !shift; paintShift(); return; }
          if (k === '⌫') return typeInto(kbInput, function (v) { return v.slice(0, -1); });
          if (k === '✓') { var i = kbInput; hideKb(); if (i.tagName !== 'TEXTAREA') done(i); return; }
          var ch = k === 'space' ? ' ' : (shift ? k.toUpperCase() : k);
          typeInto(kbInput, function (v) { return v + ch; });
          if (shift) { shift = false; paintShift(); }
        });
        r.appendChild(b);
      });
      kb.appendChild(r);
    });
    document.body.appendChild(kb);
  }
  function paintShift() {
    kb.querySelectorAll('button').forEach(function (b) {
      var k = b.dataset.k; if (k.length === 1 && /[a-zñáéíóú]/.test(k)) b.textContent = shift ? k.toUpperCase() : k;
    });
  }
  function hideKb() { if (kb) kb.hidden = true; if (kbInput) restore(kbInput); kbInput = null; document.body.style.paddingBottom = ''; }
  function restore(i) { if (i.__hgTMode === null) i.removeAttribute('inputmode'); else i.setAttribute('inputmode', i.__hgTMode); }
  function isText(el) {
    if (!el || el.disabled || el.readOnly) return false;
    if (el.tagName === 'TEXTAREA') return true;
    return el.tagName === 'INPUT' && /^(text|search|email|tel|url|)$/.test(el.type || '') && !el.hasAttribute('data-keypad') && !el.hasAttribute('data-pin');
  }
  document.addEventListener('focusin', function (e) {
    var t = e.target;
    if (t && t.tagName === 'INPUT') { if (isPin(t)) { prepPin(t); if (!t.value) t.__hgSeen = ''; } attachNum(t); showNum(t); }
    if (!textOn() || !isText(t)) return;
    if (!kb) buildKb();
    if (kbInput && kbInput !== t) restore(kbInput);
    kbInput = t; t.__hgTMode = t.getAttribute('inputmode');
    t.setAttribute('inputmode', 'none');
    kb.hidden = false;
    document.body.style.paddingBottom = kb.offsetHeight + 'px';
    try { t.scrollIntoView({ block: 'center' }); } catch (x) {}
  });
  document.addEventListener('focusout', function (e) {
    if (e.target === kbInput) setTimeout(function () { if (document.activeElement !== kbInput) hideKb(); }, 0);
  });

  /* ---------- PIN boxes: only a PIN typed here, now, by a person ---------- */
  var dots = !(window.CSS && CSS.supports) || CSS.supports('-webkit-text-security', 'disc');
  function isPin(el) { return !!el && el.tagName === 'INPUT' && el.hasAttribute('data-pin'); }
  function prepPin(i) { if (!dots && i.type !== 'password') i.type = 'password'; }   // a browser that cannot draw the dots keeps a password box
  /* what a person does in a box: a key, a phone keyboard, Backspace, paste, drop, undo. Never "replace the text"
     (autofill, suggestions), and never an edit without a key (a script, an extension, a password manager) */
  var PERSON = /^(insertText|insertCompositionText|insertFromComposition|insertFromPaste|insertFromDrop|delete|history)/;
  var typing = null;                                 // the person's key changing a PIN box right now: {box, kind, text}
  document.addEventListener('beforeinput', function (e) {
    var i = e.target;
    typing = e.isTrusted && isPin(i) && PERSON.test(e.inputType || '') ? { box: i, kind: e.inputType, text: e.data } : null;
    if (!typing) return;
    i.__hgBefore = i.value;
    setTimeout(function () { typing = null; }, 0);   // a key that changes nothing (a 9th digit) leaves no mark behind
  }, true);
  document.addEventListener('keyup', function () { typing = null; }, true);
  document.addEventListener('input', function (e) {
    var i = e.target;
    if (!isPin(i)) return;
    /* exactly that key: the same box and kind, and for a typed key the same text (a paste may lose its line break, a
       phone keyboard may compose and uncompose the digit, so only their kind is compared) */
    var key = e.isTrusted && !!typing && typing.box === i && typing.kind === e.inputType &&
              (e.inputType !== 'insertText' || typing.text === e.data);
    var person = key || i.__hgKeyed, before = i.__hgBefore;
    typing = null; i.__hgKeyed = false; i.__hgBefore = undefined;
    if (person && !(before && before !== (i.__hgSeen || ''))) { i.__hgSeen = i.value; i.__hgWiped = false; return; }
    wipe(i);                                         // put in by anything but a person, or a key on top of that
  }, true);
  function wipe(i) { i.value = ''; i.__hgSeen = ''; i.__hgWiped = true; }
  /* a box this guard emptied, and nobody has typed in since: its form and its own button do not go with it empty
     either (an empty PIN sent to the database would read as a wrong try; 0033 no longer counts it, older ones do).
     Not a box that may stay empty (data-pin-optional: a person's new PIN when only the name changes) nor one not on
     screen: those never hold a form back */
  function emptyWiped(i) {
    return !i.value && !!i.__hgWiped && !i.hasAttribute('data-pin-optional') && i.getClientRects().length > 0;
  }
  function notTyped(i) {
    if (!i.value) { i.__hgSeen = ''; return false; }   // emptied (pages clear a PIN after each try): nothing typed is kept
    try { if (i.matches(':autofill')) return true; } catch (x) { try { if (i.matches(':-webkit-autofill')) return true; } catch (y) {} }
    return i.value !== (i.__hgSeen || '');           // changed without a key at all
  }
  function stopUnlessTyped(boxes, e) {
    var bad = boxes.filter(function (i) { return notTyped(i) || emptyWiped(i); });
    if (!bad.length) return;
    bad.forEach(wipe);
    e.preventDefault(); e.stopImmediatePropagation();
    try { bad[0].focus(); } catch (x) {}
  }
  document.addEventListener('submit', function (e) {
    if (e.target && e.target.querySelectorAll) stopUnlessTyped([].slice.call(e.target.querySelectorAll('input[data-pin]')), e);
  }, true);
  /* a button reads the PIN itself (data-keypad-ok, Void, Delete): a PIN nobody typed is wiped before any click, and a
     click in its own window, or on its own button, does not go, so not even an empty PIN (a wrong try) is sent */
  function scopeOf(i) { return i.closest('.modal, .hga-wrap, [role="dialog"]') || i.form; }
  document.addEventListener('click', function (e) {
    var all = [].slice.call(document.querySelectorAll('input[data-pin]')), bad = all.filter(notTyped);
    var t = e.target && e.target.closest ? e.target : null, b = t && t.closest('button[id]');
    var own = b ? all.filter(function (i) { return i.getAttribute('data-keypad-ok') === '#' + b.id && emptyWiped(i); }) : [];
    if (!bad.length && !own.length) return;
    var near = own.length > 0 || bad.some(function (i) { var s = scopeOf(i); return (s && t && s.contains(t)) || (b && i.getAttribute('data-keypad-ok') === '#' + b.id); });
    bad.forEach(wipe);
    if (near) { e.preventDefault(); e.stopImmediatePropagation(); try { (bad[0] || own[0]).focus(); } catch (x) {} }
  }, true);
  ['copy', 'cut', 'dragstart'].forEach(function (t) {   // the dots hide the PIN; it cannot be copied out either, as from a password box
    document.addEventListener(t, function (e) { if (isPin(e.target)) e.preventDefault(); }, true);
  });

  /* fields already on the page get their pad now, so a page that focuses a PIN box at once shows it too */
  function scan() { document.querySelectorAll('input').forEach(function (i) { if (isPin(i)) prepPin(i); if (kindOf(i)) attachNum(i); }); }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', scan); else scan();

  window.HG_KEYPAD = {
    mode: function () { return get(KEY, 'auto'); }, setMode: function (m) { set(KEY, m); },
    text: textOn, setText: function (on) { set(TKEY, on ? 'on' : 'off'); if (!on) hideKb(); },
    attach: attachNum,
    pinTyped: function (i, before) {                 // a page's own on-screen keys changed this PIN box (before: its text until then)
      if (!isPin(i)) return;
      if (before && before !== (i.__hgSeen || '')) wipe(i); else { i.__hgSeen = i.value; i.__hgWiped = false; }
    }
  };
})();
