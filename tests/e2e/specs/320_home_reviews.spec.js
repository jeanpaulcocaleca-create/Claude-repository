/* The home page's review section ("Loved Your Visit?"): two plain links to each platform's own review form, opened in a
   new tab without our page as opener or referrer; no form, widget or third-party script; keyboard focus visible;
   phone layout; Spanish. The platforms themselves are never reached: their pages are answered locally. */
'use strict';
const assert = require('assert');
const { page, goto, until } = require('../lib');

const GOOGLE = 'https://g.page/r/CfHitxq6bJ3AEBM/review';
/* D-048 / E-35: Tripadvisor's write-a-review page of location 34058072 (the path of the owner's official widget and of
   the Content API's write_review link), opened and approved by the owner on 2026-10-19 */
const TRIPADVISOR = 'https://www.tripadvisor.com/UserReview-g951347-d34058072-The_hanging_garden_cafe-Monteverde_Province_of_Puntarenas.html';

async function home(browser, opts) {
  const pg = await page(browser, { lang: opts.lang, viewport: opts.viewport, context: opts.context });
  pg.outside = [];
  /* the review platforms answer locally (a stub page) so a click can be followed without the internet */
  await pg.context().route(/^https:\/\/(g\.page|www\.tripadvisor\.com)\//, (r) => {
    pg.outside.push(r.request().url());
    r.fulfill({ status: 200, contentType: 'text/html', body: '<!doctype html><title>review form</title><p>stub</p>' });
  });
  await goto(pg, '/');
  await pg.locator('#reviews').scrollIntoViewIfNeeded();
  await until(() => pg.evaluate(() => document.getElementById('reviews').classList.contains('in')), 8000, 'the section came in');
  return pg;
}
const links = (pg) => pg.evaluate(() => [...document.querySelectorAll('#reviews a')].map((a) => ({
  name: a.textContent.replace(/\s+/g, ' ').trim(), href: a.getAttribute('href'), target: a.getAttribute('target'),
  rel: (a.getAttribute('rel') || '').split(/\s+/).sort().join(' ') })));

module.exports.tests = [
  {
    name: 'R1: desktop in English: the section sits last before the footer, says what it is, and links to the two review forms',
    run: async ({ browser }) => {
      const pg = await home(browser, { lang: 'en', viewport: { width: 1280, height: 860 } });
      const order = await pg.evaluate(() => [...document.querySelectorAll('main > section')].map((s) => s.id || '-'));
      assert.strictEqual(order[order.length - 1], 'reviews', 'the last section of the page, right before the footer');
      assert.strictEqual(await pg.textContent('#reviews h2'), 'Loved Your Visit?');
      assert.strictEqual(await pg.getAttribute('#reviews', 'aria-labelledby'), 'reviewsTitle', 'the section is named by its heading');
      const lede = (await pg.textContent('#reviews .lede')).replace(/\s+/g, ' ').trim();
      assert.strictEqual(lede, 'Your experience means the world to us! Share your visit and help other travelers discover Hanging Garden Café in the heart of Monteverde.');
      assert.deepStrictEqual(await links(pg), [
        { name: 'Review Us on Google (opens in a new tab)', href: GOOGLE, target: '_blank', rel: 'noopener noreferrer' },
        { name: 'Review Us on Tripadvisor (opens in a new tab)', href: TRIPADVISOR, target: '_blank', rel: 'noopener noreferrer' }
      ]);
      for (const n of ['Review Us on Google (opens in a new tab)', 'Review Us on Tripadvisor (opens in a new tab)'])
        assert.strictEqual(await pg.locator('#reviews').getByRole('link', { name: n, exact: true }).count(), 1, 'accessible name: ' + n);
      /* reviews are written on Google and Tripadvisor, never here: no form, no widget, no outside script or frame */
      assert.strictEqual(await pg.locator('#reviews form, #reviews input, #reviews iframe, #reviews script').count(), 0);
      const outside = await pg.evaluate(() => [...document.querySelectorAll('script[src], iframe[src]')].map((e) => e.src).filter((s) => /tripadvisor|jscache|tacdn/.test(s)));
      assert.deepStrictEqual(outside, [], 'no Tripadvisor widget script on the page');
      /* no ratings or review markup made up for search engines */
      const ld = await pg.evaluate(() => [...document.querySelectorAll('script[type="application/ld+json"]')].map((s) => s.textContent).join(' '));
      assert.ok(!/aggregateRating|"Review"/.test(ld), 'no rating or review schema');
      /* both buttons on one row, the same height */
      const boxes = await pg.evaluate(() => [...document.querySelectorAll('#reviews .btn')].map((a) => { const r = a.getBoundingClientRect(); return { top: Math.round(r.top), h: Math.round(r.height) }; }));
      assert.strictEqual(boxes[0].top, boxes[1].top, 'side by side on a wide screen');
      assert.strictEqual(boxes[0].h, boxes[1].h);
      const std = await pg.evaluate(() => Math.round(document.querySelector('#visit .visit-btns .btn').getBoundingClientRect().height));
      assert.strictEqual(boxes[0].h, std, 'as tall as the other buttons of the page (' + boxes[0].h + ' vs ' + std + ')');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'R2: each button opens its review form in a new tab, with no way back to our page (noopener, noreferrer)',
    run: async ({ browser }) => {
      const pg = await home(browser, { lang: 'en', viewport: { width: 1280, height: 860 } });
      for (const [label, url] of [['Review Us on Google', GOOGLE], ['Review Us on Tripadvisor', TRIPADVISOR]]) {
        const [tab] = await Promise.all([pg.context().waitForEvent('page'), pg.locator('#reviews a', { hasText: label }).click()]);
        await tab.waitForLoadState('domcontentloaded');
        assert.strictEqual(tab.url(), url, label + ' opens ' + url);
        assert.strictEqual(await tab.evaluate(() => window.opener), null, label + ': the new tab cannot reach our page');
        assert.strictEqual(await tab.evaluate(() => document.referrer), '', label + ': no referrer sent');
        await tab.close();
      }
      assert.strictEqual(pg.url().replace(/#.*$/, '').replace(/\/(index\.html)?$/, ''), require('../lib').SITE, 'our page stays where it was');
      assert.deepStrictEqual(pg.outside.sort(), [GOOGLE, TRIPADVISOR].sort(), 'the two review forms, each asked for once');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'R3: keyboard: Tab reaches both buttons in order with the site\'s visible focus ring; Enter opens the review form',
    run: async ({ browser }) => {
      const pg = await home(browser, { lang: 'en', viewport: { width: 1280, height: 860 } });
      await pg.focus('#chatSectionOpen');
      const seen = [];
      for (let i = 0; i < 2; i++) {
        await pg.keyboard.press('Tab');
        seen.push(await pg.evaluate(() => {
          const a = document.activeElement, cs = getComputedStyle(a);
          return { href: a.getAttribute('href'), focusVisible: a.matches(':focus-visible'), outline: cs.outlineStyle + ' ' + cs.outlineWidth };
        }));
      }
      assert.deepStrictEqual(seen.map((s) => s.href), [GOOGLE, TRIPADVISOR], 'Google, then Tripadvisor');
      for (const s of seen) {
        assert.ok(s.focusVisible, 'focus is visible');
        assert.strictEqual(s.outline, 'solid 3px', 'the same gold focus ring as every other link on the page');
      }
      const [tab] = await Promise.all([pg.context().waitForEvent('page'), pg.keyboard.press('Enter')]);
      await tab.waitForLoadState('domcontentloaded');
      assert.strictEqual(tab.url(), TRIPADVISOR, 'Enter on the focused button opens its review form');
      await tab.close();
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'R4: a phone in Spanish: the buttons stack full width, big enough to tap, nothing wider than the screen; the words in Spanish',
    run: async ({ browser }) => {
      const ctx = await browser.newContext({ viewport: { width: 375, height: 740 }, isMobile: true, hasTouch: true, locale: 'es-CR', timezoneId: 'America/Costa_Rica' });
      const pg = await home(browser, { lang: 'es', context: ctx });
      assert.strictEqual(await pg.textContent('#reviews h2'), '¿Le gustó su visita?');
      assert.strictEqual(await pg.textContent('#reviews .kicker'), 'Reseñas');
      assert.match((await pg.textContent('#reviews .lede')).replace(/\s+/g, ' '), /^¡Su experiencia significa muchísimo para nosotros! .*Hanging Garden Café en el corazón de Monteverde\.$/);
      assert.deepStrictEqual((await links(pg)).map((l) => l.name), [
        'Déjenos una reseña en Google (se abre en una pestaña nueva)', 'Déjenos una reseña en Tripadvisor (se abre en una pestaña nueva)']);
      assert.deepStrictEqual((await links(pg)).map((l) => l.href), [GOOGLE, TRIPADVISOR], 'the same destinations in Spanish');
      for (const n of ['Déjenos una reseña en Google (se abre en una pestaña nueva)', 'Déjenos una reseña en Tripadvisor (se abre en una pestaña nueva)'])
        assert.strictEqual(await pg.locator('#reviews').getByRole('link', { name: n, exact: true }).count(), 1, 'accessible name: ' + n);
      const m = await pg.evaluate(() => {
        const card = document.querySelector('#reviews .reviews').getBoundingClientRect();
        const b = [...document.querySelectorAll('#reviews .btn')].map((a) => a.getBoundingClientRect());
        return { overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
                 tops: b.map((r) => Math.round(r.top)), heights: b.map((r) => r.height), widths: b.map((r) => Math.round(r.width)),
                 inside: b.every((r) => r.left >= card.left - 0.5 && r.right <= card.right + 0.5) };
      });
      assert.strictEqual(m.overflow, 0, 'no sideways scrolling');
      assert.ok(m.tops[1] > m.tops[0], 'stacked one under the other');
      assert.ok(m.heights.every((h) => h >= 44), 'each at least 44 px tall: ' + m.heights);
      assert.strictEqual(m.widths[0], m.widths[1], 'the same width');
      assert.ok(m.inside, 'inside the card');
      assert.deepStrictEqual(pg.errors, []);
      await ctx.close();
    }
  }
];
