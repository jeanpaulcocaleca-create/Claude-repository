/* The menu at the tables (/m, m.html): live from the database, updates by itself, Spanish, offline, photos, phones.
   Ported from the e2e3 suite m-e2e.js (its screenshots for a visual review are left out: they checked nothing). */
'use strict';
const assert = require('assert');
const { page, goto, until, sql } = require('../lib');
const gw = require('../gateway');

const API = 'http://127.0.0.1:' + (Number(process.env.E2E_SITE_PORT || 8090) + 1000);
/* a small real image for every menu photo (the photos live on a CDN the tests never reach) */
const PHOTO = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAQAAAADCAIAAAA7ljmRAAAAEElEQVR4nGOQ8zaGIwacHACNwwdR68r19QAAAABJRU5ErkJggg==', 'base64');

/* the café menu as the tests want it: a few items get photos and a star, two hidden, prices known */
function setup() {
  sql(`update menu_items set photo_url = 'https://d2ol7oe51mr4n9.cloudfront.net/x/' || id || '.jpg' where name in ('Cappuccino', 'Latte', 'Ham & Cheese', 'Carrot Cake', 'Tres Leches');
       update menu_items set featured = (name in ('Latte', 'Ham & Cheese', 'Tres Leches'));
       update menu_items set available = true where name in ('Mocha', 'Tea');
       update menu_items set price_crc = 2200 where name = 'Latte';
       delete from menu_items where name in ('Float', 'Canela Cloud');`);
}
/* the page as a guest's phone sees it (no sign-in); counts the menu reads */
async function guest(browser, opts) {
  opts = opts || {};
  const pg = await page(browser, { lang: opts.lang || 'en', viewport: opts.viewport || { width: 390, height: 844 } });
  pg.reads = 0;
  pg.on('request', (r) => { if (/\/rest\/v1\/menu_categories/.test(r.url()) && r.method() === 'GET') pg.reads++; });
  await pg.route(/cloudfront\.net/, (r) => r.fulfill({ status: 200, contentType: 'image/png', body: PHOTO }));
  if (opts.go !== false) {
    await goto(pg, '/m');
    await pg.waitForSelector('#menu .cat', { timeout: 15000 });
  }
  return pg;
}
const texts = (pg, sel) => pg.evaluate((s) => [...document.querySelectorAll(s)].map((e) => e.textContent.replace(/\s+/g, ' ').trim()), sel);
const flat = (s) => String(s || '').replace(/[  ]/g, ' ');
/* the page asks again (as it does every minute, or when the connection comes back) and has drawn what it got:
   it keeps each menu it reads on the phone (with the time) and draws it in the same step */
const savedAt = (pg) => pg.evaluate(() => { try { return JSON.parse(localStorage.getItem('hg-menu-m')).at || 0; } catch (e) { return 0; } });
async function refresh(pg) {
  const n = pg.reads, a0 = await savedAt(pg);
  await pg.evaluate(() => window.dispatchEvent(new Event('online')));
  await until(async () => pg.reads > n && (await savedAt(pg)) > a0, 8000, 'the menu read again');
}
const lit = (pg) => pg.evaluate(() => { const a = document.querySelector('#chips a[aria-current="true"]'); return a ? a.textContent : ''; });
const LIVE = `select string_agg(c.name, '|' order by c.sort) from menu_categories c
  where c.name <> 'Extras & Combos' and exists (select 1 from menu_items i where i.category_id = c.id and i.available and i.price_crc >= 0)`;

module.exports.tests = [
  {
    name: 'M1: a phone in English: the sections in order, every available item, prices, photos, favorites, the language switch in the header',
    run: async ({ browser }) => {
      setup();
      const pg = await guest(browser);
      /* the favorites row is at the top: its photos load (a photo that fails to load is taken off the page) */
      await until(() => pg.evaluate(() => { const im = [...document.querySelectorAll('.fav img')]; return im.length === 3 && im.every((i) => i.complete && i.naturalWidth > 0); }), 8000, 'the favorite photos loaded');
      const cats = await texts(pg, '#menu .cat h2');
      const dbCats = sql(LIVE).split('|');
      assert.deepStrictEqual(cats, dbCats, 'sections in the Menu Manager order, Extras & Combos hidden');
      assert.deepStrictEqual(await texts(pg, '#chips a'), dbCats, 'one chip per section');
      const nItems = await pg.locator('#menu .cat .it').count();
      const dbItems = sql(`select count(*) from menu_items i join menu_categories c on c.id = i.category_id where c.name <> 'Extras & Combos' and i.available and i.price_crc >= 0`);
      assert.strictEqual(String(nItems), dbItems, 'every available item shows');
      const latte = flat(await pg.locator('#menu .cat .it', { hasText: /^Latte/ }).first().textContent());
      assert.match(latte, /Latte\s*₡2\s?200/, 'price formatted like the rest of the site');
      assert.strictEqual(await pg.locator('#menu .it .ph').count(), 5, 'photos on the 5 items that have one');
      assert.deepStrictEqual(await texts(pg, '.fav .fn'), ['Latte', 'Ham & Cheese', 'Tres Leches'], 'Our favorites: the starred items with a photo');
      assert.strictEqual(await pg.textContent('.intro h1'), 'The menu', 'page text in English');
      assert.match(await pg.textContent('footer'), /Pura vida/);
      const sw = await pg.evaluate(() => { const s = document.querySelector('.hg-lang'); return s ? s.parentNode.tagName + (s.classList.contains('fixed') ? ' fixed' : '') : 'none'; });
      assert.strictEqual(sw, 'HEADER', 'the EN | ES switch sits in the header');
      assert.strictEqual(pg.supabaseHits, 0, 'the real Supabase was never contacted');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'M2: the section chips jump to their section and follow the scroll',
    run: async ({ browser }) => {
      setup();
      const pg = await guest(browser);
      await pg.locator('#chips a', { hasText: 'Sandwiches' }).click();
      await until(async () => /Sandwiches/.test(await lit(pg)), 8000, 'its chip lit');
      const top = await pg.evaluate(() => { const s = [...document.querySelectorAll('#menu .cat')].find((x) => /Sandwiches/.test(x.querySelector('h2').textContent)); return Math.round(s.getBoundingClientRect().top); });
      const bar = await pg.evaluate(() => Math.round(document.getElementById('chips').getBoundingClientRect().bottom));
      assert.ok(top >= bar - 2 && top <= bar + 30, 'the chip jumps to Sandwiches, just under the bars (' + top + ' vs ' + bar + ')');
      await pg.evaluate(() => { const s = [...document.querySelectorAll('#menu .cat')].find((x) => /Pastries/.test(x.querySelector('h2').textContent)); window.scrollTo(0, s.offsetTop - 60); });
      await until(async () => /Pastries/.test(await lit(pg)), 8000, 'scrolling lights the section on screen');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'M3: a change in the Menu Manager shows on the open page without losing the guest\'s place; nothing new, nothing redrawn',
    run: async ({ browser }) => {
      setup();
      const pg = await guest(browser);
      await pg.evaluate(() => { const s = [...document.querySelectorAll('#menu .cat')].find((x) => /Pastries/.test(x.querySelector('h2').textContent)); window.scrollTo(0, s.offsetTop - 60); });
      await until(async () => /Pastries/.test(await lit(pg)), 8000, 'scrolled to Pastries');
      const y0 = await pg.evaluate(() => window.scrollY);
      sql(`update menu_items set price_crc = 2300 where name = 'Latte';
           update menu_items set available = false where name = 'Mocha';
           insert into menu_items (category_id, name, description, price_crc, sort, available) select id, 'Canela Cloud', 'Cinnamon foam · espresso', 2900, 99, true from menu_categories where name = 'Coffee';`);
      await refresh(pg);
      await until(async () => (await pg.locator('#menu .it', { hasText: 'Canela Cloud' }).count()) === 1, 8000, 'the new item shows');
      assert.match(flat(await pg.locator('#menu .cat .it', { hasText: /^Latte/ }).first().textContent()), /₡2 ?300/, 'the new price shows');
      assert.strictEqual(await pg.locator('#menu .it', { hasText: /^Mocha/ }).count(), 0, 'the sold-out item is gone');
      const y1 = await pg.evaluate(() => window.scrollY);
      assert.ok(Math.abs(y1 - y0) < 140, 'the guest keeps their place (' + y0 + ' -> ' + y1 + ')');
      /* asked again with nothing new: the same page, not drawn again */
      await refresh(pg);
      const html1 = await pg.evaluate(() => document.getElementById('menu').innerHTML);
      await pg.evaluate(() => { window.__redrawn = 0; new MutationObserver(() => { window.__redrawn++; }).observe(document.getElementById('menu'), { childList: true, subtree: true }); });
      await refresh(pg);
      assert.strictEqual(await pg.evaluate(() => window.__redrawn), 0, 'nothing new, nothing redrawn');
      assert.strictEqual(await pg.evaluate(() => document.getElementById('menu').innerHTML), html1);
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'M4: a photo opens large with the name and price; Escape and Close shut it; a favorite opens too',
    run: async ({ browser }) => {
      setup();
      const pg = await guest(browser);
      await until(async () => (await pg.locator('#menu .it .ph').count()) === 5, 8000, 'the photos');
      await pg.locator('#menu .it .ph').first().click();
      await pg.waitForSelector('#lb:not([hidden])');
      assert.match(await pg.textContent('#lbPrice'), /₡/, 'a photo opens large with the price');
      assert.ok((await pg.textContent('#lbName')).length > 0, 'and the name');
      await pg.keyboard.press('Escape');
      await pg.waitForSelector('#lb', { state: 'hidden' });
      await pg.locator('.fav .fcard').first().click();
      await pg.waitForSelector('#lb:not([hidden])');
      assert.strictEqual(await pg.textContent('#lbName'), 'Latte', 'a favorite opens too');
      await pg.click('#lbClose');
      await pg.waitForSelector('#lb', { state: 'hidden' });
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'M5: Spanish: page text, dish names by exact menu entries only, Spanish typed in the Menu Manager first',
    run: async ({ browser }) => {
      setup();
      sql(`insert into menu_items (category_id, name, description, price_crc, sort, available) select id, 'Canela Cloud', 'Cinnamon foam · espresso', 2900, 99, true from menu_categories where name = 'Coffee';`);
      const pg = await guest(browser);
      await pg.click('.hg-lang button[lang="es"]');
      await until(async () => (await pg.textContent('.intro h1')) === 'El menú', 8000, 'the page in Spanish');
      const catsEs = await texts(pg, '#menu .cat h2');
      assert.ok(catsEs.includes('Café') && catsEs.includes('Sándwiches') && catsEs.includes('Repostería y queques'), 'sections in Spanish: ' + catsEs.join(', '));
      assert.ok((await pg.locator('#menu .it', { hasText: 'Capuchino' }).count()) >= 1, 'Cappuccino in Spanish');
      assert.strictEqual(await pg.locator('#menu .it .nm', { hasText: /^Jamón y queso$/ }).count(), 1, 'Ham & Cheese in Spanish');
      assert.strictEqual(await pg.locator('#menu .it', { hasText: 'Canela Cloud' }).count(), 1, 'a dish with no Spanish stays as typed');
      assert.match(await pg.textContent('footer'), /¿Alergias\?/, 'footer in Spanish');
      assert.match(await pg.textContent('.fav h2'), /Nuestros favoritos/, 'favorites in Spanish');
      assert.ok((await texts(pg, '#chips a')).includes('Sándwiches'), 'chips in Spanish');
      /* a dish named like a word of the staff screens is not translated */
      sql(`insert into menu_items (category_id, name, price_crc, sort, available) select id, 'Float', 1800, 98, true from menu_categories where name = 'Other Drinks';`);
      await refresh(pg);
      await until(async () => (await pg.locator('#menu .it .nm', { hasText: /^Float$/ }).count()) === 1, 8000, '"Float" on the menu');
      assert.strictEqual(await pg.locator('#menu .it .nm', { hasText: 'Fondo' }).count(), 0, '"Float" stays "Float" (not the register\'s "Fondo")');
      /* Spanish typed in the Menu Manager wins (the name_es / description_es columns of supabase/menu-spanish.sql,
         already in the test database: the open page picks them up on its next look, a new visit too) */
      sql(`update menu_items set name_es = 'Nube de canela', description_es = 'Espuma de canela · espresso' where name = 'Canela Cloud';`);
      await refresh(pg);
      await until(async () => (await pg.locator('#menu .it', { hasText: 'Nube de canela' }).count()) === 1, 8000, 'the open page shows the Spanish name');
      const pg2 = await guest(browser, { lang: 'es' });
      await until(async () => (await pg2.locator('#menu .it', { hasText: 'Nube de canela' }).count()) === 1, 8000, 'a new visit shows the Spanish name');
      assert.strictEqual(await pg2.locator('#menu .it', { hasText: 'Espuma de canela · espresso' }).count(), 1, 'and the Spanish description');
      await pg2.click('.hg-lang button[lang="en"]');
      await until(async () => (await pg2.locator('#menu .it', { hasText: 'Canela Cloud' }).count()) === 1, 8000, 'back to English');
      assert.deepStrictEqual(pg.errors.concat(pg2.errors), []);
    }
  },
  {
    name: 'M6: no signal: the last menu on the phone shows and says so; with none saved, a clear message and Try again',
    run: async ({ browser, setOffline }) => {
      setup();
      const pg3 = await guest(browser);
      setOffline(true);
      await pg3.reload({ waitUntil: 'domcontentloaded' });
      await pg3.waitForSelector('#menu .cat', { timeout: 8000 });
      await pg3.waitForSelector('#offlineNote:not([hidden])', { timeout: 8000 });
      assert.ok((await pg3.locator('#menu .it').count()) > 10, 'offline: the saved menu shows, with the note');
      setOffline(false);
      await pg3.evaluate(() => window.dispatchEvent(new Event('online')));
      await pg3.waitForSelector('#offlineNote', { state: 'hidden', timeout: 8000 });

      setOffline(true);
      const pg4 = await guest(browser, { go: false });
      await goto(pg4, '/m');
      await pg4.waitForSelector('#failed:not([hidden])', { timeout: 15000 });
      assert.match(await pg4.textContent('#failed'), /Could not load the menu/, 'nothing saved and no signal: a clear message');
      assert.ok(!(await pg4.isVisible('#status')), 'no "Loading" left behind');
      setOffline(false);
      await pg4.click('#retry');
      await pg4.waitForSelector('#menu .cat', { timeout: 8000 });
      assert.ok(!(await pg4.isVisible('#failed')), 'Try again loads it');
      assert.deepStrictEqual(pg3.errors.concat(pg4.errors), []);
    }
  },
  {
    name: 'M7: before menu-spanish.sql (no Spanish columns) the menu still loads, in Spanish from the dictionary',
    run: async ({ browser }) => {
      setup();
      sql(`insert into menu_items (category_id, name, description, price_crc, sort, available) select id, 'Canela Cloud', 'Cinnamon foam · espresso', 2900, 99, true from menu_categories where name = 'Coffee';
           alter table menu_items drop column name_es; alter table menu_items drop column description_es; notify pgrst, 'reload schema';`);
      const anon = gw.sign({ role: 'anon', iss: 'canopy-local-tests', exp: Math.floor(Date.now() / 1000) + 600 });
      await until(async () => (await fetch(API + '/rest/v1/menu_items?select=name_es&limit=1', { headers: { Authorization: 'Bearer ' + anon } })).status === 400, 10000, 'the API without the columns');
      const pg5 = await guest(browser, { lang: 'es' });
      await until(async () => (await pg5.locator('#menu .it').count()) > 10, 8000, 'the menu');
      assert.strictEqual(await pg5.locator('#menu .it', { hasText: 'Canela Cloud' }).count(), 1, 'without the Spanish columns the menu loads (dictionary and English)');
      assert.ok(await pg5.locator('#menu .it', { hasText: 'Capuchino' }).count() >= 1, 'known dishes still in Spanish');
      assert.deepStrictEqual(pg5.errors, []);
    }
  },
  {
    name: 'M8: a small Android, an iPhone SE, an iPad: nothing wider than the screen',
    run: async ({ browser }) => {
      setup();
      for (const [name, vp] of [['android-360', { width: 360, height: 740 }], ['ipad-820', { width: 820, height: 1180 }], ['iphone-se', { width: 320, height: 568 }]]) {
        const p = await guest(browser, { viewport: vp });
        await until(async () => (await p.locator('#menu .it .ph img').count()) === 5, 8000, 'the photos');
        const over = await p.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
        assert.ok(over <= 0, name + ': no sideways scrolling (' + over + ')');
        assert.deepStrictEqual(p.errors, [], name + ': no page errors');
        await p.context().close();
      }
    }
  }
];
