/* The tribute to Gabriel Barboza Villalobos (D-068): https://hanginggardencafe.com/gabriel-barboza, the address the QR
   on the garden plaque opens (printed, so it can never change). One page, both full versions: Spanish and English.
   It opens straight at /gabriel-barboza (no redirect, as GitHub Pages serves gabriel-barboza.html there), follows the
   language the visitor chose anywhere on the site (lang.js, hg_lang) or else the device's, and switches with the site's
   ES/EN switch without reloading. Its text comes only from the tribute the owner approved; the claims the owner ruled out
   never appear, in either language. The owner's adjustments of 2026-11-09 (G9): about don Gabriel only (the café's owners
   never named), the owner's highlighted line, no promotion inside the tribute (no Basecamp anywhere; the site's usual
   footer only), a brief hero with the story below, the family's photograph unchanged. The home page links to it (story
   and footer) and the sitemap lists it. */
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
/* the family's photograph as it came in the approved tribute (sha-256 of website/assets/gabriel-barboza.jpg) */
const PHOTO_SHA = '148f96732fc065303caf889198c2fa71bf7bdd8f92232d175d74b44fc0c6827d';

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
      for (const width of [320, 360, 375]) for (const lang of ['es', 'en']) {
        const ctx = await browser.newContext({ viewport: { width, height: 740 }, isMobile: true, hasTouch: true,
                                               locale: lang === 'es' ? 'es-CR' : 'en-US', timezoneId: 'America/Costa_Rica' });
        const pg = await open(browser, { context: ctx, lang });
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
        const at = lang + ' at ' + width + ' px';
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
      /* (6) the address the QR opens */
      assert.strictEqual(new URL(pg.url()).pathname, '/gabriel-barboza');
      assert.ok(HTML.includes('<link rel="canonical" href="https://hanginggardencafe.com/gabriel-barboza">'));
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'G7: the home page leads to it (story and footer, in both languages) and the sitemap lists it once',
    run: async ({ browser }) => {
      const pg = await page(browser, { lang: 'es' });
      await goto(pg, '/');
      await until(() => pg.evaluate(() => document.documentElement.lang === 'es'), 5000, 'the home page in Spanish');
      const es = await pg.evaluate(() => [...document.querySelectorAll('a[href="gabriel-barboza"]')].map((a) => a.textContent.trim()));
      assert.deepStrictEqual(es, ['Gabriel Barboza Villalobos, el hombre de las orquídeas de Monteverde: su conocimiento, generosidad y amor por las orquídeas dejaron una huella que continúa floreciendo en nuestro jardín.',
        'Conozca su historia', 'Homenaje a Gabriel Barboza']);
      await pg.click('#story a.more');
      await pg.waitForURL(/\/gabriel-barboza$/);
      await pg.waitForLoadState('load');
      assert.strictEqual(await pg.title(), TITLE_ES);
      const en = await page(browser, { lang: 'en' });
      await goto(en, '/');
      const enLinks = await en.evaluate(() => [...document.querySelectorAll('a[href="gabriel-barboza"]')].map((a) => a.textContent.trim()));
      assert.deepStrictEqual(enLinks, ['Gabriel Barboza Villalobos, the orchid man of Monteverde: his knowledge, generosity and love of orchids left a mark that continues to bloom in our garden.',
        'Read his story', 'A tribute to Gabriel Barboza']);
      /* the home page names no owner for the tribute either */
      const story = await en.evaluate(() => document.querySelector('#story .tribute').textContent);
      assert.ok(!/owner|dueñ|propietari/i.test(story), 'the home line names no owner');
      const map = fs.readFileSync(path.join(ROOT, 'website/sitemap.xml'), 'utf8');
      assert.strictEqual((map.match(/<loc>https:\/\/hanginggardencafe\.com\/gabriel-barboza<\/loc>/g) || []).length, 1);
      assert.ok(!/href="https:\/\/hanginggardencafe\.com\/gabriel-barboza"/.test(map), 'no language alternates pointing at the one address');
      assert.deepStrictEqual(pg.errors.concat(en.errors), []);
    }
  }
];
