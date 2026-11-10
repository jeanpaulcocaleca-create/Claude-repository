/* The tribute to Gabriel Barboza Villalobos (D-068): https://hanginggardencafe.com/gabriel-barboza, the address the QR
   on the garden plaque opens (printed, so it can never change). One page, both full versions: Spanish and English.
   It opens straight at /gabriel-barboza (no redirect, as GitHub Pages serves gabriel-barboza.html there), follows the
   language the visitor chose anywhere on the site (lang.js, hg_lang) or else the device's, and switches with the site's
   ES/EN switch without reloading. Its text comes only from the tribute the owner approved; the claims the owner ruled out
   never appear, in either language. The owner's adjustments of 2026-11-09 (G9): about don Gabriel only (the café's owners
   never named), the owner's highlighted line, no promotion inside the tribute (no Basecamp anywhere; the site's usual
   footer only), a brief hero with the story below, the family's photograph unchanged. The sitemap lists it.
   The home page leads to it (D-069, the owner's request of 2026-11-10: the first link was too discreet): a small card at
   the end of «La historia», below the Monteverde timeline and the quetzal, with his photograph, the café's thanks for his
   help with the garden's decoration, his name, «Un hombre y sus orquídeas», the owner's line and «Conozca su historia»
   (G7 on a computer, G11 on phones); and the footer link. */
'use strict';
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const { page, goto, until, SITE, ROOT } = require('../lib');

/* the owner's SEO title, word for word, in both languages (D-068: no second, English title) */
const TITLE_ES = 'Gabriel Barboza Villalobos — El hombre de las orquídeas de Monteverde | Hanging Garden Café';
const TITLE_EN = TITLE_ES;
const HTML = fs.readFileSync(path.join(ROOT, 'website/gabriel-barboza.html'), 'utf8');
/* the owner's highlighted line (2026-11-09) and its English */
const LINE_ES = 'Su conocimiento, generosidad y amor por las orquídeas dejaron una huella que continúa floreciendo en este jardín.';
const LINE_EN = 'His knowledge, generosity and love of orchids left a mark that continues to bloom in this garden.';
/* the garden as the owner put it (2026-11-10): he contributed to its decoration and helped bring in plants and orchids;
   never that he alone designed or decorated it, or set all its plants */
const GARDEN_ES = 'Don Gabriel Barboza Villalobos contribuyó con su conocimiento y generosidad a la decoración del jardín de Hanging Garden Café, ayudando a incorporar plantas y orquídeas que hoy forman parte de este espacio. Su amor por la naturaleza dejó una huella que continúa floreciendo entre nosotros.';
const GARDEN_EN = 'Don Gabriel Barboza Villalobos contributed his knowledge and generosity to the decoration of the Hanging Garden Café garden, helping to bring in plants and orchids that are part of this space today. His love of nature left a mark that continues to bloom among us.';
const SOLE_DESIGNER = /diseñ\p{L}*|design\p{L}*|(él|he) (solo|alone)|(lo|la) decoró|decorated (it|the garden)|pobló|filled it|plantas que él dispuso|plants he arranged|sus guarias|his guarias|en su obra|in his work|creó (el|este) jardín|created (the|this) garden/iu;
const QR_URL = 'https://hanginggardencafe.com/gabriel-barboza';
const PLACA = path.join(ROOT, 'docs/placa-gabriel-barboza');
/* the family's photograph as it came in the approved tribute (sha-256 of website/assets/gabriel-barboza.jpg) */
const PHOTO_SHA = '148f96732fc065303caf889198c2fa71bf7bdd8f92232d175d74b44fc0c6827d';

/* the home page's card (D-069), word for word, in both languages */
const CARD = {
  es: { label: 'Homenaje a Gabriel Barboza', kicker: 'Homenaje',
        title: 'Hanging Garden se enorgullece de haber contado con la ayuda de don Gabriel en la decoración de nuestro jardín.',
        name: 'Gabriel Barboza Villalobos', sub: 'Un hombre y sus orquídeas', line: LINE_ES, cta: 'Conozca su historia',
        alt: 'Retrato de Gabriel Barboza sonriendo, con gorro de lana tejido y camiseta gris, frente al follaje verde de Monteverde',
        links: ['Conozca su historia', 'Homenaje a Gabriel Barboza'] },
  en: { label: 'A tribute to Gabriel Barboza', kicker: 'Tribute',
        title: "Hanging Garden is proud to have had Don Gabriel's help in decorating our garden.",
        name: 'Gabriel Barboza Villalobos', sub: 'One man and his orchids', line: LINE_EN, cta: 'Discover his story',
        alt: 'Portrait of Gabriel Barboza smiling, wearing a knitted wool cap and a grey T-shirt, in front of the green foliage of Monteverde',
        links: ['Discover his story', 'A tribute to Gabriel Barboza'] }
};
/* the home page in the given language (with an extra style sheet if given), the card shown (the story's reveal has run) */
async function homeCard(pg, lang, css) {
  await goto(pg, '/');
  if (css) await pg.addStyleTag({ content: css });
  await until(() => pg.evaluate((l) => document.documentElement.lang === l, lang), 5000, 'the home page in ' + lang);
  await pg.evaluate(() => document.querySelector('#story > .gbcard').scrollIntoView({ block: 'center' }));
  await until(() => pg.evaluate(() => { const c = getComputedStyle(document.querySelector('#story > .gbcard'));
    return c.opacity === '1' && c.transform === 'none' && document.querySelector('.gbphoto img').complete; }), 8000, 'the card shown');
}
/* the card as the reader sees it: its words, its links, its place, its size and its photograph */
const readCard = (pg) => pg.evaluate(() => {
  /* what is read out: the text without the parts hidden from screen readers (the button's arrow) */
  const said = (e) => { const k = e.cloneNode(true); k.querySelectorAll('[aria-hidden="true"]').forEach((h) => h.remove()); return k.textContent.replace(/\s+/g, ' ').trim(); };
  const c = document.querySelector('#story > .gbcard'), t = (s) => said(c.querySelector(s));
  const box = (e) => e.getBoundingClientRect(), img = c.querySelector('.gbphoto img'), ib = box(img), ic = getComputedStyle(img);
  /* the picture itself: its box less the white mat (border) and any padding */
  const iw = ib.width - parseFloat(ic.paddingLeft) - parseFloat(ic.paddingRight) - parseFloat(ic.borderLeftWidth) - parseFloat(ic.borderRightWidth);
  const ih = ib.height - parseFloat(ic.paddingTop) - parseFloat(ic.paddingBottom) - parseFloat(ic.borderTopWidth) - parseFloat(ic.borderBottomWidth);
  const altered = [];
  for (let e = img; e && e.id !== 'story'; e = e.parentElement) {
    const k = getComputedStyle(e);
    if (k.filter !== 'none' || k.transform !== 'none' || k.opacity !== '1' || k.mixBlendMode !== 'normal' || k.clipPath !== 'none') altered.push(e.tagName + '.' + e.className);
    /* nothing around it cuts it: a box that clips its overflow holds the whole photograph */
    const eb = box(e);
    if (e !== img && (k.overflowX !== 'visible' || k.overflowY !== 'visible') &&
        (eb.left > ib.left + 0.5 || eb.top > ib.top + 0.5 || eb.right < ib.right - 0.5 || eb.bottom < ib.bottom - 0.5)) altered.push('cut by ' + e.tagName + '.' + e.className);
  }
  /* its rounded corners stay within the mat, so they never round off the picture itself */
  for (const k of ['TopLeft', 'TopRight', 'BottomRight', 'BottomLeft']) {
    const r = parseFloat(ic['border' + k + 'Radius']), bw = Math.min(parseFloat(ic['border' + k.replace(/Left|Right/, '') + 'Width']), parseFloat(ic['border' + k.replace(/Top|Bottom/, '') + 'Width']));
    if (r > bw + 0.01) altered.push('corner ' + k + ' rounds the picture (' + r + ' px over a ' + bw + ' px mat)');
  }
  /* the page's thread (a line down the middle on computers) is painted behind the card, never across its text:
     the topmost thing at the thread's place, at three heights of the card, belongs to the card */
  const th = document.querySelector('.thread');
  let over = null;
  if (getComputedStyle(th).display !== 'none') {
    const tb = box(th), x = tb.left + tb.width / 2, cb = box(c), was = th.style.pointerEvents;
    th.style.pointerEvents = 'auto';
    over = [0.3, 0.5, 0.7].every((f) => { const top = document.elementFromPoint(x, cb.top + cb.height * f); return !!top && c.contains(top); });
    th.style.pointerEvents = was;
  }
  return { label: c.getAttribute('aria-label'), kicker: t('.kicker'), title: t('h3'), name: t('.gbname strong'), sub: t('.gbname em'), line: t('.gbline'),
    cta: t('a.btn'), alt: img.getAttribute('alt'), src: img.getAttribute('src'),
    hrefs: [...c.querySelectorAll('a[href]')].map((a) => a.getAttribute('href')),
    links: [...document.querySelectorAll('a[href="gabriel-barboza"]')].map(said), arrow: !!c.querySelector('a.btn [aria-hidden="true"]'),
    oneLine: (() => { const n = c.querySelector('.gbname'), dot = getComputedStyle(n.querySelector('em'), '::before').content;
      return { dot: dot !== 'none' && dot !== 'normal', same: Math.abs(box(n.querySelector('strong')).top - box(n.querySelector('em')).top) < 6 }; })(),
    words: c.innerText.replace(/\s+/g, ' '), afterStory: c.previousElementSibling === document.querySelector('#story > .storygrid'),
    last: c === document.getElementById('story').lastElementChild,
    top: box(c).top, bottom: box(c).bottom, h: box(c).height, gridBottom: box(document.querySelector('#story > .storygrid')).bottom,
    timelineBottom: box(document.querySelector('#story .timeline')).bottom, quetzalBottom: box(document.querySelector('#story .storyside')).bottom,
    over,
    ratio: iw / ih, objectFit: ic.objectFit, natural: img.naturalWidth / img.naturalHeight, loaded: img.complete && img.naturalWidth > 0, photoW: ib.width, altered };
});
const NO_OWNER = /owner|dueñ|propietari/i;
const NO_PROMO = /Basecamp|WhatsApp|promo|descuento|discount|oferta|offer|reserv|book|pedid|order|\$|₡/i;

/* what the reader sees: the text of the visible version */
const shown = (pg) => pg.evaluate(() => document.getElementById('main').innerText);
const state = (pg) => pg.evaluate(() => ({
  lang: document.documentElement.lang, data: document.documentElement.getAttribute('data-lang'), title: document.title,
  es: !!document.querySelector('#main > [data-l="es"]').getClientRects().length,
  en: !!document.querySelector('#main > [data-l="en"]').getClientRects().length,
  stored: localStorage.getItem('hg_lang')
}));

async function open(browser, opts) {
  const pg = await page(browser, opts);
  if (opts && opts.noChoice) await pg.addInitScript(() => { try { localStorage.removeItem('hg_lang'); } catch (e) {} });
  const res = await pg.goto(SITE + '/gabriel-barboza', { waitUntil: 'load' });
  pg.res = res;
  return pg;
}

module.exports.tests = [
  {
    name: 'G1: /gabriel-barboza opens directly in Spanish: title, description, canonical, portrait with its description, the highlighted line',
    run: async ({ browser }) => {
      const pg = await open(browser, { lang: 'es' });
      assert.strictEqual(pg.res.status(), 200, 'the address answers');
      assert.strictEqual(new URL(pg.url()).pathname, '/gabriel-barboza', 'no redirect: the address the QR opens stays');
      const s = await state(pg);
      assert.deepStrictEqual([s.lang, s.data, s.title, s.es, s.en], ['es', 'es', TITLE_ES, true, false]);
      const head = await pg.evaluate(() => ({
        desc: document.querySelector('meta[name=description]').content,
        canon: document.querySelector('link[rel=canonical]').href,
        og: document.querySelector('meta[property="og:image"]').content,
        ld: [...document.querySelectorAll('script[type="application/ld+json"]')].map((x) => JSON.parse(x.textContent)['@type'])
      }));
      assert.ok(head.desc.length >= 80 && head.desc.length <= 200 && /Gabriel Barboza Villalobos/.test(head.desc) && /jardín/.test(head.desc), 'short description of his story and the garden');
      assert.strictEqual(head.canon, 'https://hanginggardencafe.com/gabriel-barboza');
      assert.strictEqual(head.og, 'https://hanginggardencafe.com/assets/gabriel-barboza.jpg');
      assert.deepStrictEqual(head.ld, ['BreadcrumbList', 'Article'], 'structured data parses');
      const img = await pg.evaluate(() => { const i = document.querySelector('#main > [data-l="es"] .portrait img');
        return { alt: i.alt, w: i.naturalWidth, src: i.getAttribute('src') }; });
      assert.strictEqual(img.src, 'assets/gabriel-barboza.jpg');
      assert.ok(img.w > 0, 'the portrait loads');
      assert.match(img.alt, /^Retrato de Gabriel Barboza .*gorro de lana.*camiseta gris/, 'descriptive alt text');
      const t = await shown(pg);
      for (const want of ['Gabriel Barboza Villalobos', LINE_ES, 'Por qué este homenaje', 'Su historia', 'Cronología verificada', 'Fuentes',
        'Reserva Los Cusingos']) {
        assert.ok(t.includes(want), 'shows: ' + want);
      }
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'G2: the English version is complete: same sections, same facts, same links; the title stays the owner\'s',
    run: async ({ browser }) => {
      const pg = await open(browser, { lang: 'en' });
      const s = await state(pg);
      assert.deepStrictEqual([s.lang, s.data, s.title, s.es, s.en], ['en', 'en', TITLE_EN, false, true]);
      const t = await shown(pg);
      for (const want of [LINE_EN, 'Why this tribute', 'His story', 'Verified timeline', 'Sources', 'Los Cusingos Reserve',
        '“descubridor de seis” (“discoverer of six”)']) {
        assert.ok(t.includes(want), 'shows: ' + want);
      }
      const img = await pg.evaluate(() => document.querySelector('#main > [data-l="en"] .portrait img').alt);
      assert.match(img, /^Portrait of Gabriel Barboza .*knitted wool cap.*grey T-shirt/);
      /* both versions carry the same parts: sections, timeline years, achievements, species, sources and their links */
      const parity = await pg.evaluate(() => {
        const v = (l) => { const r = document.querySelector('#main > [data-l="' + l + '"]');
          return { sections: r.querySelectorAll('section').length, years: [...r.querySelectorAll('.tl .yr')].map((x) => x.textContent),
            logros: r.querySelectorAll('.logro').length, plates: [...r.querySelectorAll('.plate h3')].map((x) => x.textContent),
            links: [...r.querySelectorAll('a[href]')].map((a) => a.getAttribute('href')).filter((h) => !h.startsWith('#')) }; };
        return { es: v('es'), en: v('en') };
      });
      assert.deepStrictEqual(parity.en, parity.es);
      assert.deepStrictEqual(parity.es.years, ['1994', '1995', '1998', '1999', '2003', '2004', '2005', '2006', '2008', '2019']);
      assert.strictEqual(parity.es.sections, 7);
      /* «Logros documentados» in chronological order, one year per achievement, in both versions */
      const order = await pg.evaluate(() => ['es', 'en'].map((l) => [...document.querySelectorAll('#main > [data-l="' + l + '"] .logros > .logro .yr')]
        .map((y) => [...y.childNodes].filter((t) => t.nodeType === 3).map((t) => t.textContent.trim()).join(' '))));
      assert.deepStrictEqual(order[0], ['1994', '1995', '2003', '2003', '2004', '2005', '2006', '2019']);
      assert.deepStrictEqual(order[1], order[0]);
      const firsts = order[0].map((y) => +y.slice(0, 4));
      assert.deepStrictEqual(firsts, [...firsts].sort((a, b) => a - b), 'oldest first');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'G3: with no choice made yet, the device language decides (Spanish phone: Spanish; English phone: English)',
    run: async ({ browser }) => {
      const pes = await open(browser, { lang: 'es', noChoice: true });
      const a = await state(pes);
      assert.deepStrictEqual([a.data, a.title, a.es, a.en, a.stored], ['es', TITLE_ES, true, false, null]);
      const pen = await open(browser, { lang: 'en', noChoice: true });
      const b = await state(pen);
      assert.deepStrictEqual([b.data, b.title, b.es, b.en, b.stored], ['en', TITLE_EN, false, true, null]);
      assert.deepStrictEqual(pes.errors.concat(pen.errors), []);
    }
  },
  {
    name: 'G4: the site\'s ES/EN switch flips the whole page without reloading (the title stays the owner\'s), and remembers the choice',
    run: async ({ browser }) => {
      const pg = await open(browser, { lang: 'es' });
      await pg.waitForSelector('#nav .hg-lang button');
      await pg.evaluate(() => { window.__same = 1; });
      await pg.click('#nav .hg-lang button[lang=en]');
      await until(async () => (await state(pg)).data === 'en', 4000, 'English shown');
      const s = await state(pg);
      assert.deepStrictEqual([s.lang, s.title, s.es, s.en, s.stored], ['en', TITLE_EN, false, true, 'en']);
      assert.strictEqual(await pg.evaluate(() => window.__same), 1, 'no reload');
      await pg.click('#nav .hg-lang button[lang=es]');
      await until(async () => (await state(pg)).data === 'es', 4000, 'Spanish shown again');
      const s2 = await state(pg);
      assert.deepStrictEqual([s2.lang, s2.title, s2.es, s2.en, s2.stored], ['es', TITLE_ES, true, false, 'es']);
      /* the choice carries over to the next visit (a new tab on the same device: the test's page re-seeds hg_lang) */
      await pg.click('#nav .hg-lang button[lang=en]');
      await until(async () => (await state(pg)).stored === 'en', 4000, 'English remembered');
      const again = await pg.context().newPage();
      await again.goto(SITE + '/gabriel-barboza', { waitUntil: 'load' });
      assert.deepStrictEqual([(await state(again)).data, await again.title()], ['en', TITLE_EN]);
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'G5: none of the claims the owner ruled out appears, in either language (the whole file, hidden version included)',
    run: async () => {
      const text = HTML.replace(/<script[\s\S]*?<\/script>|<style[\s\S]*?<\/style>/g, ' ').replace(/<[^>]+>/g, ' ')
        .replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&').replace(/\s+/g, ' ');
      const ruledOut = [
        [/autodidact|self[- ]taught|sin (ninguna )?formaci[oó]n|formaci[oó]n acad[eé]mica|sin t[ií]tulos?|without (a |any )?(formal|academic|degree)|no (formal|academic) (training|education|degree)|never (studied|went to)/i, 'no lack-of-degrees framing'],
        [/(?<!\p{L})(naci[oó]|nacid[oa]|nacimiento|falleci\p{L}*|muri[oó]|q\.?\s?e\.?\s?p\.?\s?d|descanse en paz|born|died|death|passed away|in memoriam)(?!\p{L})|†|\(\s*\d{4}\s*[–-]\s*\d{4}\s*\)/iu, 'no birth or death dates'],
        [/an[aá]lisis floral|floral analys|disecci[oó]n|dissect/i, 'he drew the plant habits, not the floral analyses of Atwood 1994'],
        [/(gui[oó]|guided|guía)[^.]{0,120}(en|in) Monteverde[^.]{0,40}2019|2019[^.]{0,160}Selby[^.]{0,120}(en|in) Monteverde/i, '2019: the Selby tour was at Los Cusingos, not in Monteverde'],
        [/descubri[oó] seis|seis (nuevas )?especies nuevas|discovered six|six new species|seis especies nuevas para la ciencia/i, '«descubridor de seis» is quoted, never turned into «discovered six new species»']
      ];
      const about = text;
      /* what search results and link previews show too: the description, og tags, alt texts, labels and the structured data */
      const attrs = [...HTML.matchAll(/\b(?:content|alt|title|aria-label)="([^"]*)"/g)].map((x) => x[1]).join(' · ');
      const ld = [...HTML.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)].map((x) => x[1]).join(' · ');
      assert.ok(/Retrato de Gabriel Barboza/.test(attrs) && /"headline"/.test(ld), 'the attributes and the structured data are read');
      for (const [re, why] of ruledOut) {
        for (const [where, t] of [['text', about], ['attributes', attrs], ['structured data', ld]]) {
          const m = t.match(re); assert.ok(!m, why + ' (' + where + '): found «' + (m && m[0]) + '»');
        }
      }
      /* and no date of his life: every year on the page is one of the dated publications and events, or the check date */
      const years = [...new Set(text.match(/(?<!\d)(1[89]\d\d|20\d\d)(?!\d)/g))].sort();
      assert.deepStrictEqual(years, ['1994', '1995', '1996', '1998', '1999', '2001', '2002', '2003', '2004', '2005', '2006', '2008', '2019', '2026']);
      /* what the owner asked for instead is there, in both versions */
      assert.strictEqual((text.match(/Los Cusingos/g) || []).length, 2, 'Los Cusingos in both versions');
      assert.strictEqual((text.match(/«descubridor de seis»|“descubridor de seis”/g) || []).length, 2, 'the quote as Ambientico wrote it, in both versions');
      assert.strictEqual((text.match(/dibujó los hábitos|drew the habits/g) || []).length, 2, 'the drawings of the plant habits, in both versions');
    }
  },
  {
    name: 'G6: on phones from 320 px the page fits the screen and every card holds its text; the bar starts the page; the portrait comes first',
    run: async ({ browser }) => {
      /* page.css clips the page sideways (html,body overflow-x), so a too-wide box would not scroll: it would be cut off.
         So every box is measured: inside the screen, and inside the card (its padding) that holds it */
      /* and with wide fallback fonts forced (DejaVu, the default on GitHub's runner: there the bar did not fit at 320 px
         while this machine's narrower fallback fit; a phone whose web fonts do not load is in the same case) */
      const WIDE = 'body,body *:not(h1):not(h2):not(h3):not(b):not(.epithet):not(.destacado):not(.pull){font-family:"DejaVu Sans",sans-serif !important}' +
                   'h1,h2,h3,b,.epithet,.destacado,.pull{font-family:"DejaVu Serif",serif !important}';
      for (const fonts of ['default', 'wide']) for (const width of [320, 360, 375]) for (const lang of ['es', 'en']) {
        const ctx = await browser.newContext({ viewport: { width, height: 740 }, isMobile: true, hasTouch: true,
                                               locale: lang === 'es' ? 'es-CR' : 'en-US', timezoneId: 'America/Costa_Rica' });
        const pg = await open(browser, { context: ctx, lang });
        if (fonts === 'wide') { await pg.addStyleTag({ content: WIDE }); await pg.evaluate(() => window.dispatchEvent(new Event('resize'))); await pg.waitForTimeout(100); }
        const m = await pg.evaluate(() => {
          const r = document.querySelector('#main > [data-l="' + document.documentElement.getAttribute('data-lang') + '"]');
          const box = (e) => e.getBoundingClientRect(), name = (e) => e.tagName + '.' + String(e.className).trim();
          const visible = (e) => { const b = box(e); return b.width > 0 && b.height > 0; };
          const wide = [...document.body.querySelectorAll('*')].filter((e) => !e.closest('.skip') && visible(e) && box(e).right > innerWidth + 1).map(name);
          const spill = [];
          for (const card of r.querySelectorAll('.casa, .plate, .logro, .hero .wrap, .chips .wrap')) {
            const cb = box(card), cs = getComputedStyle(card), inner = cb.right - parseFloat(cs.paddingRight) + 1, left = cb.left + parseFloat(cs.paddingLeft) - 1;
            for (const e of card.querySelectorAll('*')) if (visible(e) && (box(e).right > inner || box(e).left < left)) spill.push(name(card) + ' > ' + name(e));
          }
          const fig = box(r.querySelector('.portrait')), h1 = box(r.querySelector('h1')), nav = box(document.getElementById('nav'));
          return { wide, spill, figTop: fig.top, h1Top: h1.top, figW: fig.width, nav: nav.height, heroTop: box(r.querySelector('.hero')).top };
        });
        const at = lang + ' at ' + width + ' px, ' + fonts + ' fonts';
        assert.deepStrictEqual(m.wide, [], at + ': nothing wider than the screen');
        assert.deepStrictEqual(m.spill, [], at + ': nothing outside its card');
        assert.ok(m.nav <= 80, at + ': the bar stays on one line (' + m.nav + ' px)');
        assert.ok(Math.abs(m.heroTop - m.nav) <= 1, at + ': the page starts where the bar ends');
        assert.ok(m.figTop >= m.nav && m.figTop < m.h1Top, at + ': the portrait below the bar and above his name');
        assert.ok(m.figW >= 240, at + ': the portrait is large enough');
        assert.deepStrictEqual(pg.errors, [], at);
        await ctx.close();
      }
    }
  },
  {
    name: 'G8: where the browser refuses storage the page and the site\'s switch agree (lang.js\'s rule: English), and the switch still works',
    run: async ({ browser }) => {
      const ctx = await browser.newContext({ viewport: { width: 1280, height: 860 }, locale: 'es-CR', timezoneId: 'America/Costa_Rica' });
      const pg = await ctx.newPage();
      pg.errors = []; pg.on('pageerror', (e) => pg.errors.push(e.message));
      await pg.route(/fonts\.(googleapis|gstatic)\.com/, (r) => r.abort());
      await pg.addInitScript(() => { Object.defineProperty(window, 'localStorage', { get() { throw new DOMException('blocked', 'SecurityError'); } }); });
      await pg.goto(SITE + '/gabriel-barboza', { waitUntil: 'load' });
      const read = () => pg.evaluate(() => ({ data: document.documentElement.getAttribute('data-lang'), lang: document.documentElement.lang, site: window.HG_LANG,
        on: [...document.querySelectorAll('#nav .hg-lang button.on')].map((b) => b.getAttribute('lang')), title: document.title }));
      assert.deepStrictEqual(await read(), { data: 'en', lang: 'en', site: 'en', on: ['en'], title: TITLE_ES });
      await pg.click('#nav .hg-lang button[lang=es]');
      await until(async () => (await read()).data === 'es', 4000, 'Spanish shown');
      assert.deepStrictEqual(await read(), { data: 'es', lang: 'es', site: 'es', on: ['es'], title: TITLE_ES });
      assert.deepStrictEqual(pg.errors, []);
      await ctx.close();
    }
  },
  {
    name: 'G9: the owner\'s adjustments: only don Gabriel (no owners), the owner\'s line, no promotion inside the tribute, the usual footer, a brief hero, the photo unchanged',
    run: async ({ browser }) => {
      const pg = await open(browser, { lang: 'es' });
      const m = await pg.evaluate(() => {
        const main = document.getElementById('main'), txt = (e) => e.textContent.replace(/\s+/g, ' ').trim();
        const hero = (l) => { const h = document.querySelector('#main > [data-l="' + l + '"] .hero');
          return { text: txt(h), lists: h.querySelectorAll('ul, ol, dl').length, links: h.querySelectorAll('a').length,
                   line: txt(h.querySelector('.destacado')), kicker: txt(h.querySelector('.kicker')) }; };
        const flinks = (l) => txt(document.querySelector('footer .flinks[data-l="' + l + '"]'));
        return { all: txt(main), hrefs: [...main.querySelectorAll('a[href]')].map((a) => a.getAttribute('href')), btns: main.querySelectorAll('.btn').length,
          ids: [...document.querySelectorAll('#main > [data-l="es"] > section')].map((x) => x.id),
          idsEn: [...document.querySelectorAll('#main > [data-l="en"] > section')].map((x) => x.id),
          heroEs: hero('es'), heroEn: hero('en'), footEs: flinks('es'), footEn: flinks('en') };
      });
      /* (1) only don Gabriel: the café's owners are never named (his own business, Orquídeas de Monteverde, is his) */
      const noOwnBusiness = m.all.replace(/propietario de Orquídeas de Monteverde/g, ' ').replace(/the owner of Orquídeas de Monteverde/g, ' ');
      const owners = noOwnBusiness.match(/dueñ\p{L}*|propietari\p{L}*|owners?\b|co-?owner|nuestra casa|historia de la casa|our house/iu);
      assert.ok(!owners, 'no owners named in the tribute: found «' + (owners && owners[0]) + '»');
      const ownersAttr = HTML.match(/\b(?:content|alt|title|aria-label)="[^"]*(dueñ|propietari|owners?\b|nuestra casa|our house)[^"]*"/i);
      assert.ok(!ownersAttr, 'no owners in the description, og tags or alt texts');
      const ownersHead = (HTML.match(/<title>[\s\S]*?<\/title>/)[0] + [...HTML.matchAll(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/g)].map((x) => x[1]).join(' '))
        .match(/dueñ|propietari|owners?\b|nuestra casa|our house|basecamp/i);
      assert.ok(!ownersHead, 'no owners or Basecamp in the title or the structured data');
      /* (2) the owner's highlighted line, word for word, and its English */
      assert.deepStrictEqual([m.heroEs.line, m.heroEn.line], [LINE_ES, LINE_EN]);
      /* (3) no promotion inside the tribute: no Basecamp anywhere on the page, no menu / WhatsApp / visit block, no buttons */
      assert.ok(!/basecamp/i.test(HTML), 'Basecamp nowhere on the page');
      const promo = m.all.match(/hospedaje|lodging|desayun\p{L}*|breakfast|reposter\p{L}*|pastr(y|ies)|WhatsApp|todos los días|every day|horario|opening hours|(?<!\p{L})venga a|come for|visítenos|visit us|(?<!\p{L})men[uú](?!\p{L})/iu);
      assert.ok(!promo, 'no promotional text inside the tribute: found «' + (promo && promo[0]) + '»');
      assert.deepStrictEqual([m.btns, m.hrefs.filter((h) => h === 'm' || /wa\.me|basecamp/.test(h))], [0, []]);
      /* the site's usual footer: the same links as the guide pages' (es/cafe.html, coffee.html) */
      const guideFoot = (f) => fs.readFileSync(path.join(ROOT, 'website', f), 'utf8').match(/<p class="flinks">([\s\S]*?)<\/p>/)[1]
        .replace(/<[^>]+>/g, '').replace(/\s+/g, ' ').trim();
      assert.deepStrictEqual([m.footEs, m.footEn], [guideFoot('es/cafe.html'), guideFoot('coffee.html')]);
      /* (4) brief and moving at the top, the story below: the hero holds the kicker, his name, the epithet, the line,
         one short paragraph and the photograph; no list, no link; then the house's reason, his story, achievements,
         species, the Lepanthes finding, the timeline and the sources, in that order */
      for (const h of [m.heroEs, m.heroEn]) {
        assert.deepStrictEqual([h.lists, h.links], [0, 0], 'no list or link in the hero');
        assert.ok(h.text.length <= 520, 'a brief hero (' + h.text.length + ' characters)');
      }
      assert.deepStrictEqual([m.heroEs.kicker, m.heroEn.kicker], ['Homenaje', 'Tribute']);
      assert.deepStrictEqual(m.ids, ['por-que', 'historia', 'logros', 'especies', 'lepanthes', 'cronologia', 'fuentes']);
      assert.deepStrictEqual(m.idsEn, ['why', 'story-en', 'achievements', 'species', 'lepanthes-en', 'timeline', 'sources']);
      /* (5) the family's photograph as it came: the same bytes, served as they are, shown whole (the image box has the
         photo's own proportions, so object-fit crops nothing: within 0.2 %) and unaltered (no filter, transform, opacity,
         blend or clip on it or around it), on phones and on a computer, in both languages */
      const file = fs.readFileSync(path.join(ROOT, 'website/assets/gabriel-barboza.jpg'));
      assert.strictEqual(require('crypto').createHash('sha256').update(file).digest('hex'), PHOTO_SHA, 'the photograph is the family\'s, unchanged');
      const served = await pg.request.get(SITE + '/assets/gabriel-barboza.jpg');
      assert.ok(Buffer.compare(await served.body(), file) === 0, 'served as it is');
      for (const width of [320, 375, 1280]) for (const lang of ['es', 'en']) {
        const ctx = await browser.newContext({ viewport: { width, height: 800 }, locale: lang === 'es' ? 'es-CR' : 'en-US' });
        const p2 = await open(browser, { context: ctx, lang });
        const ph = await p2.evaluate(() => {
          const img = document.querySelector('#main > [data-l="' + document.documentElement.getAttribute('data-lang') + '"] .portrait img');
          const cs = getComputedStyle(img), b = img.getBoundingClientRect();
          const w = b.width - parseFloat(cs.paddingLeft) - parseFloat(cs.paddingRight) - parseFloat(cs.borderLeftWidth) - parseFloat(cs.borderRightWidth);
          const h = b.height - parseFloat(cs.paddingTop) - parseFloat(cs.paddingBottom) - parseFloat(cs.borderTopWidth) - parseFloat(cs.borderBottomWidth);
          const altered = [];
          for (let e = img; e && e.id !== 'main'; e = e.parentElement) {
            const c = getComputedStyle(e);
            if (c.filter !== 'none' || c.transform !== 'none' || c.opacity !== '1' || c.mixBlendMode !== 'normal' || c.clipPath !== 'none') altered.push(e.tagName + '.' + e.className);
          }
          return { ratio: w / h, natural: img.naturalWidth / img.naturalHeight, loaded: img.complete && img.naturalWidth > 0, altered };
        });
        const at = lang + ' at ' + width + ' px';
        assert.ok(ph.loaded, at + ': the photograph loads');
        assert.ok(Math.abs(ph.ratio - ph.natural) / ph.natural < 0.002, at + ': shown whole, not cropped (' + ph.ratio.toFixed(4) + ' vs ' + ph.natural.toFixed(4) + ')');
        assert.deepStrictEqual(ph.altered, [], at + ': nothing alters the photograph');
        assert.deepStrictEqual(p2.errors, [], at);
        await ctx.close();
      }
      /* the garden as the owner put it, word for word in Spanish and its English; nowhere that he alone designed or
         decorated the garden or set all its plants: not in the page's text, attributes or structured data, nor the home line */
      const garden = await pg.evaluate(() => ['es', 'en'].map((l) => document.querySelector('#main > [data-l="' + l + '"] .casa .jardin').textContent.replace(/\s+/g, ' ').trim()));
      assert.deepStrictEqual(garden, [GARDEN_ES, GARDEN_EN]);
      const sole = [m.all, HTML.match(/<head>[\s\S]*<\/head>/)[0]].join(' ').match(SOLE_DESIGNER);
      assert.ok(!sole, 'nowhere the sole designer of the garden: found «' + (sole && sole[0]) + '»');
      const home = fs.readFileSync(path.join(ROOT, 'website/index.html'), 'utf8').match(/<aside class="gbcard part"[\s\S]*?<\/aside>/)[0];
      assert.ok(!SOLE_DESIGNER.test(home), 'the home page\'s card claims no design of the garden');
      /* (6) the address the QR opens */
      assert.strictEqual(new URL(pg.url()).pathname, '/gabriel-barboza');
      assert.ok(HTML.includes('<link rel="canonical" href="https://hanginggardencafe.com/gabriel-barboza">'));
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'G10: the plaque and its QR: the SVG, the PNG and the plaque carry exactly the code of the page\'s address, dark on light with a quiet zone; the plaque is brief',
    run: async ({ browser }) => {
      /* the expected code, made by the same library the café's screens use (qrcode-generator 1.4.4), level H */
      const qrcode = require('qrcode-generator');
      const q = qrcode(0, 'H'); q.addData(QR_URL, 'Byte'); q.make();
      const n = q.getModuleCount(), QUIET = 4, size = n + 2 * QUIET;
      const want = []; for (let r = 0; r < n; r++) { let row = ''; for (let c = 0; c < n; c++) row += q.isDark(r, c) ? '1' : '0'; want.push(row); }
      /* the dark modules of an SVG path made of «Mx y hW vH h-W z» rectangles, in a square of `size` modules at (ox, oy) */
      const fromPath = (d, ox, oy, unit) => {
        const g = Array.from({ length: n }, () => Array(n).fill('0'));
        for (const m of d.matchAll(/M([\d.]+) ([\d.]+)h([\d.]+)v([\d.]+)h-[\d.]+z/g)) {
          const r = Math.round((+m[2] - oy) / unit) - QUIET, c0 = Math.round((+m[1] - ox) / unit) - QUIET, w = Math.round(+m[3] / unit);
          assert.ok(r >= 0 && r < n && c0 >= 0 && c0 + w <= n, 'a module outside the code: the quiet zone is clear');
          for (let c = c0; c < c0 + w; c++) g[r][c] = '1';
        }
        return g.map((row) => row.join(''));
      };
      /* contrast of the ink on the paper (WCAG formula): a phone reads it easily from about 3 : 1, here far more */
      const lum = (hex) => { const v = hex.replace('#', '').match(/../g).map((x) => { const c = parseInt(x, 16) / 255; return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); });
        return 0.2126 * v[0] + 0.7152 * v[1] + 0.0722 * v[2]; };
      const contrast = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); };

      /* the QR as SVG */
      const svg = fs.readFileSync(path.join(PLACA, 'qr-gabriel-barboza.svg'), 'utf8');
      assert.ok(svg.includes(`viewBox="0 0 ${size} ${size}"`), 'one unit per module, with the 4-module quiet zone');
      const paperS = svg.match(/<rect width="\d+" height="\d+" fill="(#[0-9a-f]{6})"/i)[1], inkS = svg.match(/<path fill="(#[0-9a-f]{6})" d="([^"]+)"/i);
      assert.deepStrictEqual(fromPath(inkS[2], 0, 0, 1), want, 'the SVG holds exactly the code of ' + QR_URL);
      assert.ok(contrast(inkS[1], paperS) >= 7, 'dark ink on light paper (' + contrast(inkS[1], paperS).toFixed(1) + ' : 1)');

      /* the QR as PNG, read pixel by pixel in the browser */
      const pg = await page(browser, { lang: 'es' });
      const pngB64 = fs.readFileSync(path.join(PLACA, 'qr-gabriel-barboza.png')).toString('base64');
      const png = await pg.evaluate(async ([b64, size, n, QUIET]) => {
        const im = new Image(); im.src = 'data:image/png;base64,' + b64; await im.decode();
        const cv = document.createElement('canvas'); cv.width = im.width; cv.height = im.height; const x = cv.getContext('2d'); x.drawImage(im, 0, 0);
        const px = im.width / size, rows = [];
        const at = (r, c) => x.getImageData(Math.floor((c + 0.5) * px), Math.floor((r + 0.5) * px), 1, 1).data;
        for (let r = 0; r < n; r++) { let row = ''; for (let c = 0; c < n; c++) { const d = at(r + QUIET, c + QUIET); row += d[0] + d[1] + d[2] < 384 ? '1' : '0'; } rows.push(row); }
        let quietDark = 0;   /* every module of the 4-module margin, all around */
        for (let r = 0; r < size; r++) for (let c = 0; c < size; c++) if (r < QUIET || r >= QUIET + n || c < QUIET || c >= QUIET + n) { const d = at(r, c); if (d[0] + d[1] + d[2] < 384) quietDark++; }
        const hex = (d) => '#' + [d[0], d[1], d[2]].map((v) => v.toString(16).padStart(2, '0')).join('');
        let ink = null; for (let r = 0; r < n && !ink; r++) for (let c = 0; c < n && !ink; c++) { const d = at(r + QUIET, c + QUIET); if (d[0] + d[1] + d[2] < 384) ink = hex(d); }
        return { w: im.width, h: im.height, rows, quietDark, ink, paper: hex(at(0, 0)) };
      }, [pngB64, size, n, QUIET]);
      assert.strictEqual(png.w, png.h, 'square');
      assert.ok(png.w / size >= 10, 'at least 10 pixels per module for print (' + png.w + ' px)');
      assert.deepStrictEqual(png.rows, want, 'the PNG holds exactly the code of ' + QR_URL);
      assert.strictEqual(png.quietDark, 0, 'the quiet zone is clear');
      assert.ok(contrast(png.ink, png.paper) >= 7, 'dark on light (' + contrast(png.ink, png.paper).toFixed(1) + ' : 1)');

      /* the plaque: the same code, at least 5 cm, and brief: his name, the dedication, the invitation and the address */
      const placa = fs.readFileSync(path.join(PLACA, 'placa-gabriel-barboza.svg'), 'utf8');
      const box = placa.match(/<g id="qr">\s*<rect x="([\d.]+)" y="([\d.]+)" width="([\d.]+)" height="[\d.]+" fill="(#[0-9a-f]{6})"\/>\s*<path fill="(#[0-9a-f]{6})" shape-rendering="crispEdges" d="([^"]+)"/i);
      assert.ok(box, 'the plaque carries the QR');
      assert.ok(placa.includes('viewBox="0 0 300 400"') && /width="300mm" height="400mm"/.test(placa), '30 × 40 cm');
      assert.ok(+box[3] >= 50, 'the QR is at least 5 cm wide on the plaque (' + box[3] + ' mm)');
      assert.deepStrictEqual(fromPath(box[6], +box[1], +box[2], +box[3] / size), want, 'the plaque holds exactly the code of ' + QR_URL);
      assert.ok(contrast(box[5], box[4]) >= 7, 'dark on light on the plaque');
      const words = [...placa.matchAll(/<text[^>]*>([^<]*)<\/text>/g)].map((x) => x[1].replace(/&amp;/g, '&')).join(' ').replace(/\s+/g, ' ').trim();
      assert.strictEqual(words, 'HOMENAJE Gabriel Barboza Villalobos «' + LINE_ES.replace(/\.$/, '') + '» Conozca su historia / Discover his story hanginggardencafe.com/gabriel-barboza',
        'the plaque says only: Homenaje, his name, the dedication (the owner\'s line), the invitation and the address');
      assert.ok(!/Selby|Annals|Lepanthes|450|dueñ|propietari|Basecamp|diseñ|decor/i.test(words), 'no story, no owners, no promotion on the plaque');
      /* the plaque opens in a browser as an image */
      const ok = await pg.evaluate(async (b64) => { const im = new Image(); im.src = 'data:image/svg+xml;base64,' + b64; await im.decode(); return im.naturalWidth > 0; },
        Buffer.from(placa).toString('base64'));
      assert.ok(ok, 'the plaque file is a valid image');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'G7: the home page leads to it: a small card at the end of «La historia», below the timeline and the quetzal (his photograph, the café\'s thanks, the owner\'s line, «Conozca su historia»), and the footer; both languages; the sitemap lists it once',
    run: async ({ browser }) => {
      const pages = [];
      for (const lang of ['es', 'en']) {
        const pg = await page(browser, { lang });
        pages.push(pg);
        await homeCard(pg, lang);
        const c = await readCard(pg), want = CARD[lang];
        assert.deepStrictEqual([c.label, c.kicker, c.title, c.name, c.sub, c.line, c.cta, c.alt], [want.label, want.kicker, want.title, want.name, want.sub, want.line, want.cta, want.alt], lang + ': the card, word for word');
        assert.deepStrictEqual(c.links, want.links, lang + ': the home page leads to the tribute from the card and the footer, nowhere else');
        assert.deepStrictEqual(c.hrefs, ['gabriel-barboza'], lang + ': one link in the card, to the tribute');
        assert.ok(c.arrow, lang + ': the button\'s arrow is shown, and hidden from screen readers');
        assert.ok(c.oneLine.dot && c.oneLine.same, lang + ': on a computer his name and «' + want.sub + '» share one line, a dot between them');
        /* its place: the end of the story, after the timeline and the quetzal */
        assert.ok(c.afterStory && c.last, lang + ': the card closes «La historia», right after the timeline and the quetzal');
        assert.ok(c.top > c.gridBottom && c.top > c.timelineBottom && c.top > c.quetzalBottom, lang + ': below the timeline and the quetzal');
        assert.ok(c.over, lang + ': the card lies over the page\'s thread, as the canopy does (the line does not cross its text)');
        /* small but seen: shorter than a third of the screen on a computer */
        assert.ok(c.h <= 340, lang + ': a small card (' + Math.round(c.h) + ' px high)');
        /* the family's photograph, the same file as the tribute's, whole and unaltered */
        assert.strictEqual(c.src, 'assets/gabriel-barboza.jpg');
        assert.ok(c.loaded, lang + ': the photograph loads');
        assert.ok(Math.abs(c.ratio - c.natural) / c.natural < 0.002, lang + ': shown whole, not cropped (' + c.ratio.toFixed(4) + ' vs ' + c.natural.toFixed(4) + ')');
        assert.deepStrictEqual(c.altered, [], lang + ': nothing alters the photograph');
        assert.strictEqual(c.objectFit, 'fill', lang + ': the picture is scaled, never cut to fit');
        assert.ok(c.photoW >= 120, lang + ': the photograph is seen (' + Math.round(c.photoW) + ' px)');
        /* about don Gabriel only: no owners, no promotion, never the garden's sole designer */
        for (const [re, what] of [[NO_OWNER, 'no owners'], [NO_PROMO, 'no promotion'], [SOLE_DESIGNER, 'never the sole designer of the garden']]) {
          const m = c.words.match(re);
          assert.ok(!m, lang + ': ' + what + ' in the card: found «' + (m && m[0]) + '»');
        }
      }
      /* «Conozca su historia» opens the tribute */
      await pages[0].click('#story .gbcard a.btn');
      await pages[0].waitForURL(/\/gabriel-barboza$/);
      await pages[0].waitForLoadState('load');
      assert.strictEqual(await pages[0].title(), TITLE_ES);
      const map = fs.readFileSync(path.join(ROOT, 'website/sitemap.xml'), 'utf8');
      assert.strictEqual((map.match(/<loc>https:\/\/hanginggardencafe\.com\/gabriel-barboza<\/loc>/g) || []).length, 1);
      assert.ok(!/href="https:\/\/hanginggardencafe\.com\/gabriel-barboza"/.test(map), 'no language alternates pointing at the one address');
      assert.deepStrictEqual(pages[0].errors.concat(pages[1].errors), []);
    }
  },
  {
    name: 'G11: the home page\'s card on phones from 320 px (also with wide fallback fonts): it fits, holds its text, stays short, the photograph whole beside the title, «Conozca su historia» easy to tap',
    run: async ({ browser }) => {
      /* DejaVu: GitHub's runner's fallback, and a phone whose web fonts do not load (see G6) */
      const WIDE = 'body *{font-family:"DejaVu Sans",sans-serif !important}h1,h2,h3,.gbname em,.values{font-family:"DejaVu Serif",serif !important}';
      const runs = [];
      for (const width of [320, 360, 375, 390]) runs.push([width, 'default']);
      for (const width of [320, 375]) runs.push([width, 'wide']);
      for (const [width, fonts] of runs) for (const lang of ['es', 'en']) {
        const ctx = await browser.newContext({ viewport: { width, height: 740 }, isMobile: true, hasTouch: true,
                                               locale: lang === 'es' ? 'es-CR' : 'en-US', timezoneId: 'America/Costa_Rica' });
        const pg = await page(browser, { context: ctx, lang });
        await homeCard(pg, lang, fonts === 'wide' ? WIDE : null);
        const at = lang + ' at ' + width + ' px, ' + fonts + ' fonts';
        const c = await readCard(pg);
        assert.deepStrictEqual([c.title, c.line, c.cta], [CARD[lang].title, CARD[lang].line, CARD[lang].cta], at);
        const m = await pg.evaluate(() => {
          const card = document.querySelector('#story > .gbcard'), box = (e) => e.getBoundingClientRect(), cb = box(card), cs = getComputedStyle(card);
          const inner = cb.right - parseFloat(cs.paddingRight) + 1, left = cb.left + parseFloat(cs.paddingLeft) - 1;
          const spill = [...card.querySelectorAll('*')].filter((e) => { const b = box(e); return b.width > 0 && b.height > 0 && (b.right > inner || b.left < left); })
            .map((e) => e.tagName + '.' + String(e.className).trim());
          /* and each line of text within the card: no word or line runs past its box or out of the card */
          for (const e of card.querySelectorAll('.kicker, h3, .gbname strong, .gbname em, .gbline, a.btn')) {
            if (e.scrollWidth > e.clientWidth + 1) spill.push(e.tagName + '.' + String(e.className).trim() + ' overflows its box');
            const rg = document.createRange(); rg.selectNodeContents(e);
            if ([...rg.getClientRects()].some((r) => r.width > 0 && (r.right > inner || r.left < left))) spill.push(e.tagName + '.' + String(e.className).trim() + ' text outside the card');
          }
          const ph = box(card.querySelector('.gbphoto')), h3 = box(card.querySelector('h3')), k = box(card.querySelector('.kicker')), cta = box(card.querySelector('a.btn'));
          /* the arrow apart from the words (a touch screen's button is a flex box, which drops a space) */
          const a = card.querySelector('a.btn'), rg = document.createRange(); rg.selectNodeContents(a.firstChild);
          const words = [...rg.getClientRects()].pop(), arrow = box(a.querySelector('.arr'));
          return { spill, inScreen: cb.left >= 0 && cb.right <= innerWidth, beside: ph.right <= h3.left && ph.right <= k.left && Math.abs(ph.top - k.top) < 12,
                   ctaH: cta.height, ctaW: cta.width, h: cb.height, gap: arrow.left - words.right, coarse: matchMedia('(pointer:coarse)').matches };
        });
        assert.ok(m.inScreen, at + ': the card fits the screen');
        assert.deepStrictEqual(m.spill, [], at + ': nothing outside the card');
        assert.ok(m.beside, at + ': the photograph beside «Homenaje» and the title');
        assert.ok(m.h <= 480, at + ': a short card (' + Math.round(m.h) + ' px high)');
        assert.ok(m.coarse, at + ': measured as a touch screen');
        assert.ok(m.gap >= 3, at + ': the arrow stands apart from «' + CARD[lang].cta + '» (' + m.gap.toFixed(1) + ' px)');
        assert.ok(c.oneLine.same === false || !c.oneLine.dot, at + ': the dot never starts a line');
        assert.ok(m.ctaH >= 44 && m.ctaW >= 44, at + ': «Conozca su historia» easy to tap (' + Math.round(m.ctaW) + ' × ' + Math.round(m.ctaH) + ')');
        assert.ok(c.loaded && Math.abs(c.ratio - c.natural) / c.natural < 0.002, at + ': the photograph whole');
        assert.deepStrictEqual(c.altered, [], at + ': nothing alters the photograph');
        assert.ok(c.top > c.gridBottom, at + ': after the timeline and the quetzal');
        assert.deepStrictEqual(pg.errors, [], at);
        await ctx.close();
      }
    }
  },
  {
    name: 'G12: between phone and computer (561–1000 px, also with wide fonts) the dot sits between his name and «Un hombre y sus orquídeas» only on one line; on small and short screens every section of the home page, «La historia» and its card included, appears',
    run: async ({ browser }) => {
      const WIDE = 'body *{font-family:"DejaVu Sans",sans-serif !important}h1,h2,h3,.gbname em,.values{font-family:"DejaVu Serif",serif !important}';
      for (const fonts of ['default', 'wide']) for (const lang of ['es', 'en']) {
        const pg = await page(browser, { lang, viewport: { width: 1000, height: 800 } });
        await homeCard(pg, lang, fonts === 'wide' ? WIDE : null);
        const bad = [];
        for (let width = 561; width <= 1000; width += 13) {
          await pg.setViewportSize({ width, height: 800 });
          const o = (await readCard(pg)).oneLine;
          if (o.dot && !o.same) bad.push(width);
        }
        assert.deepStrictEqual(bad, [], lang + ', ' + fonts + ' fonts: widths where the dot starts a line');
        assert.deepStrictEqual(pg.errors, [], lang + ', ' + fonts + ' fonts');
        await pg.context().close();
      }
      /* small and short screens: a section taller than about six screens never reached the reveal's 15 % and stayed
         blank. On the published v2026.11.09-1 the whole «Menú» section never appeared at 320 × 568 (a small phone),
         844 × 390 (a phone held sideways) or 1280 × 400 (a short window), nor «La historia» at 640 × 280; now a section
         also appears when it fills half the screen. Scrolled through, the way a visitor does: every section appears */
      for (const [width, height] of [[320, 568], [640, 280], [740, 300], [568, 320], [844, 390], [1280, 400]]) for (const lang of ['es', 'en']) {
        const phone = width < 900;
        const ctx = await browser.newContext({ viewport: { width, height }, isMobile: phone, hasTouch: phone, locale: lang === 'es' ? 'es-CR' : 'en-US', timezoneId: 'America/Costa_Rica' });
        const pg = await page(browser, { context: ctx, lang });
        await goto(pg, '/');
        await until(() => pg.evaluate((l) => document.documentElement.lang === l, lang), 5000, 'the home page in ' + lang);
        const hidden = await pg.evaluate(async () => {
          document.documentElement.style.scrollBehavior = 'auto';
          const frame = () => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
          for (let y = 0; y < document.documentElement.scrollHeight; y += Math.round(innerHeight / 4)) { scrollTo(0, y); await frame(); }
          await new Promise((r) => setTimeout(r, 300));
          return [...document.querySelectorAll('.rev')].filter((s) => !s.classList.contains('in')).map((s) => s.id || s.className);
        });
        const at = lang + ' at ' + width + ' × ' + height;
        assert.deepStrictEqual(hidden, [], at + ': every section appears as it is scrolled through');
        await pg.evaluate(() => document.querySelector('#story > .gbcard').scrollIntoView({ block: 'center' }));
        await until(() => pg.evaluate(() => getComputedStyle(document.querySelector('#story > .gbcard')).opacity === '1'), 5000, at + ': the card shown');
        assert.deepStrictEqual(pg.errors, [], at);
        await ctx.close();
      }
    }
  }
];
