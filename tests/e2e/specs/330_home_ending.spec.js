/* The building photo the home film ends on (assets/hero-ending.jpg, D-050): on upright screens (phones, a tablet held
   upright) it is framed left of centre so the mural's quetzal, the café logo and the order window stay in view; wide
   screens keep the centred framing. Reduced motion shows the ending straight away. The photo itself is not in git (it
   is fetched at publish time from website/ASSETS.md), so this checks the framing and the file the page asks for. */
'use strict';
const assert = require('assert');
const { page, goto, until } = require('../lib');

async function ending(browser, viewport, mobile) {
  const ctx = await browser.newContext({ viewport, reducedMotion: 'reduce', isMobile: mobile, hasTouch: mobile,
                                         locale: 'es-CR', timezoneId: 'America/Costa_Rica' });
  const pg = await page(browser, { context: ctx, lang: 'es' });
  await goto(pg, '/');
  await until(() => pg.evaluate(() => document.getElementById('top').classList.contains('ended')), 8000, 'the ending is shown');
  const st = await pg.evaluate(() => {
    const cs = getComputedStyle(document.getElementById('still'));
    return { pos: cs.backgroundPosition, size: cs.backgroundSize, img: cs.backgroundImage, opacity: cs.opacity };
  });
  return { pg, ctx, st };
}

module.exports.tests = [
  {
    name: 'E1: upright screens frame the ending photo left of centre; wide screens keep it centred',
    run: async ({ browser }) => {
      for (const [label, viewport, mobile, pos] of [
        ['phone', { width: 390, height: 844 }, true, '30% 50%'], ['small phone', { width: 375, height: 667 }, true, '30% 50%'],
        ['tablet upright', { width: 820, height: 1180 }, false, '30% 50%'], ['tablet sideways', { width: 1180, height: 820 }, false, '50% 50%'],
        ['computer', { width: 1440, height: 900 }, false, '50% 50%']]) {
        const { pg, ctx, st } = await ending(browser, viewport, mobile);
        assert.strictEqual(st.pos, pos, label + ': framing');
        assert.strictEqual(st.size, 'cover', label + ': the photo still covers the screen');
        assert.match(st.img, /assets\/hero-ending\.jpg/, label + ': the ending photo');
        assert.deepStrictEqual(pg.errors, [], label);
        await ctx.close();
      }
    }
  }
];
