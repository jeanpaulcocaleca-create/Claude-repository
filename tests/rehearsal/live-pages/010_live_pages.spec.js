/* Canopy OS rehearsal · the pages that are LIVE on hanginggardencafe.com today (the gh-pages build named in
   tests/rehearsal/LIVE_PAGES), on the copy of production after every migration (0000-0030 today). Until the new pages are
   published, the café keeps using these: they must load and work exactly as before. Also run on the reset copy
   (tests/rehearsal/reset-pages.sh): nothing here assumes earlier sales, so the same checks hold on the empty café. */
'use strict';
const assert = require('assert');
const { page, goto, until, sql } = require('../../e2e/lib');

/* the local stand-in for Supabase answers on the site port + 1000 (tests/e2e/gateway.js; live-pages.sh points the pages there) */
const API = 'http://127.0.0.1:' + (Number(process.env.E2E_SITE_PORT || 8090) + 1000);
function watchApi(pg) {
  pg.apiErrors = [];
  pg.on('response', (r) => {
    if (r.url().startsWith(API + '/') && r.status() >= 400) pg.apiErrors.push(r.status() + ' ' + r.request().method() + ' ' + r.url().slice(API.length));
  });
  return pg;
}
const quiet = (ms) => new Promise((r) => setTimeout(r, ms));
/* on a day with no register opened yet, the live POS opens its Today panel once by itself (a nudge to open the register)
   over the product grid; a cashier closes it and sells, the register is opened by the manager (the empty café after
   the reset, tests/rehearsal/reset-pages.sh) */
async function closeDayNudge(pg) {
  await quiet(800);
  if (await pg.locator('#dayModal').isVisible()) await pg.click('#dayClose');
}
/* sales saved with their lines (the old POS writes the order, then its lines, in two requests) */
const withLines = () => Number(sql(`select count(*) from public.orders o where exists (select 1 from public.order_items i where i.order_id = o.id)`));

module.exports.tests = [
  {
    name: 'every live page loads on the migrated database: no script errors, no refused API call, nothing sent to the real Supabase',
    run: async ({ browser }) => {
      sql(`update public.app_settings set room_orders_enabled = true, room_open = '00:00', room_close = '23:59' where id = 1`);
      const room = sql(`select code from public.rooms where active order by number limit 1`);
      const pages = [
        ['cafe', '/pos.html'], ['cafe', '/kitchen.html'], ['cafe', '/time.html'], ['cafe', '/sales.html'],
        ['owner', '/home.html'], ['owner', '/inventory.html'], ['owner', '/admin.html'], ['owner', '/qr.html'],
        // an owner login without the phone code enrolled signs in at aal1
        ['owner1', '/home.html'], ['owner1', '/inventory.html'], ['owner1', '/admin.html'],
        [null, '/index.html'], [null, '/m.html'], [null, '/menu.html'], [null, '/tv.html'], [null, '/room.html?r=' + room],
        [null, '/es/menu.html']
      ];
      const problems = [];
      for (const [login, path] of pages) {
        const pg = watchApi(await page(browser, { login: login ? login.replace('owner1', 'owner') : undefined, aal: login === 'owner' ? 'aal2' : undefined }));
        await goto(pg, path);
        await quiet(2500);
        const where = (login || 'visitor') + ' ' + path;
        if (pg.errors.length) problems.push(where + ' script errors: ' + pg.errors.join(' | '));
        if (pg.apiErrors.length) problems.push(where + ' API: ' + pg.apiErrors.join(' | '));
        if (pg.supabaseHits) problems.push(where + ' tried the real Supabase');
        await pg.context().close();
      }
      assert.deepStrictEqual(problems, []);
    }
  },
  {
    name: 'the live POS rings a sale; the new database numbers it, dates it and stamps its tax',
    run: async ({ browser }) => {
      const pg = watchApi(await page(browser, { login: 'cafe' }));
      await goto(pg, '/pos.html');
      await until(async () => (await pg.locator('#menuGrid .pbtn').count()) > 1, 15000, 'the menu');
      await closeDayNudge(pg);
      const before = withLines();
      await pg.locator('#menuGrid .pbtn').nth(0).click();
      await pg.locator('#menuGrid .pbtn').nth(1).click();
      await pg.click('[data-pay=card]');
      if (await pg.locator('#numModal').isVisible()) await pg.click('#numNone');
      await until(() => withLines() === before + 1, 10000, 'the sale saved with its lines');
      const o = sql(`select business_date = public.cr_today(), receipt_no is not null, location_id is not null, payment_method,
                            (select count(*) from public.order_items i where i.order_id = o.id and i.net_crc is not null and i.tax_rate is not null)
                       from public.orders o order by created_at desc limit 1`);
      assert.match(o, /^t\|t\|t\|card\|[12]$/, 'sale of the old page: ' + o);
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, []);
    }
  },
  {
    name: 'the live POS keeps a sale taken without internet and uploads it when the connection is back',
    run: async ({ browser, setOffline }) => {
      const pg = watchApi(await page(browser, { login: 'cafe' }));
      await goto(pg, '/pos.html');
      await until(async () => (await pg.locator('#menuGrid .pbtn').count()) > 0, 15000, 'the menu');
      await closeDayNudge(pg);
      const before = Number(sql(`select count(*) from public.orders`)), beforeLines = withLines();
      setOffline(true);
      await pg.locator('#menuGrid .pbtn').nth(0).click();
      await pg.click('[data-pay=cash_crc]');
      // a build with the cash window (0010; v2026.10.14-1 on) asks what was handed over: the exact amount
      await quiet(400);
      if (await pg.locator('#cashModal').isVisible()) await pg.click('#cashExact');
      if (await pg.locator('#numModal').isVisible()) await pg.click('#numNone');
      await quiet(1500);
      assert.strictEqual(Number(sql(`select count(*) from public.orders`)), before, 'nothing reached the database while offline');
      setOffline(false);
      await until(() => withLines() === beforeLines + 1, 70000, 'the offline sale uploaded with its lines');
      assert.strictEqual(Number(sql(`select count(*) from public.orders`)), before + 1, 'saved once');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'the live time clock punches with a PIN',
    run: async ({ browser }) => {
      const pg = watchApi(await page(browser, { login: 'cafe' }));
      await goto(pg, '/time.html');
      await until(async () => (await pg.locator('#staffGrid button', { hasText: 'Marta' }).count()) > 0, 15000, 'the staff');
      const before = Number(sql(`select count(*) from public.time_entries`));
      await pg.locator('#staffGrid button', { hasText: 'Marta' }).first().click();
      await pg.fill('#pinInput', '6173');
      await pg.click('#pinGo');
      await until(() => Number(sql(`select count(*) from public.time_entries`)) === before + 1, 10000, 'the punch');
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, []);
    }
  },
  {
    name: 'the live Menu Manager still recolors a category and moves it to the kitchen (owner login)',
    run: async ({ browser }) => {
      const pg = watchApi(await page(browser, { login: 'owner', aal: 'aal2' }));
      await goto(pg, '/admin.html');
      await until(async () => (await pg.locator('#cats input[type=color]').count()) > 0, 15000, 'the categories');
      const id = sql(`select id from public.menu_categories order by sort, name limit 1`);
      await pg.locator('#cats input[type=color]').first().evaluate((el) => { el.value = '#3b6ea8'; el.dispatchEvent(new Event('change')); });
      await until(() => sql(`select color from public.menu_categories where id = '${id}'`) === '#3b6ea8', 8000, 'the color saved');
      const k = sql(`select kitchen from public.menu_categories where id = '${id}'`);
      await pg.locator('#cats input[type=checkbox]').first().click();
      await until(() => sql(`select kitchen from public.menu_categories where id = '${id}'`) !== k, 8000, 'the kitchen switch saved');
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, []);
    }
  },
  {
    // migration 0030 keeps the live editor working (it deletes the recipe and inserts it again, without a PIN);
    // the history records that write as a direct change until the new page with the PIN is published
    name: 'the live recipe editor still saves a recipe; since 0030 the change is kept in the recipe history',
    run: async ({ browser }) => {
      const stock = sql(`select id from public.stock_items where active order by name limit 1`);
      let mi = sql(`select menu_item_id from public.recipes order by menu_item_id limit 1`);
      if (!mi) {   // a copy without recipes: give one product a line first
        mi = sql(`select id from public.menu_items order by name limit 1`);
        sql(`insert into public.recipes (menu_item_id, stock_item_id, qty) values ('${mi}', '${stock}', 1)`);
      }
      const name = sql(`select name from public.menu_items where id = '${mi}'`);
      const v30 = Number(sql(`select public.canopy_schema_version()`)) >= 30;
      const versions = () => Number(sql(`select count(*) from public.recipe_versions where menu_item_id = '${mi}'`));
      const before = v30 ? versions() : 0;
      // in English: the Spanish page translates product names, and the product is found by its stored name
      const pg = watchApi(await page(browser, { login: 'owner', aal: 'aal2', lang: 'en' }));
      await goto(pg, '/inventory.html');
      await until(async () => (await pg.locator('#kItems').textContent()) !== '–', 15000, 'inventory loaded');
      await pg.click('#tabs [data-view=recipes]');
      await until(async () => (await pg.locator('#menuList button').count()) > 0, 10000, 'the menu listed');
      const i = await pg.evaluate((n) => Array.prototype.findIndex.call(document.querySelectorAll('#menuList button'),
        (b) => b.firstChild && b.firstChild.firstChild && b.firstChild.firstChild.textContent === n), name);
      assert.ok(i >= 0, name + ' is listed');
      await pg.locator('#menuList button').nth(i).click();
      await pg.waitForSelector('#recipeCard:not([hidden])', { timeout: 5000 });
      const line = pg.locator('#recipeRows .recipe-row').first();
      const item = await line.locator('select').inputValue();
      const qty = Number(await line.locator('input').inputValue());
      await line.locator('input').fill(String(qty + 1));
      await pg.click('#recipeSave');
      await until(async () => /Recipe saved|Receta guardada/.test(await pg.locator('#toast').textContent()), 8000, 'saved');
      assert.strictEqual(Number(sql(`select qty from public.recipes where menu_item_id = '${mi}' and stock_item_id = '${item}'`)), qty + 1, 'the new quantity is saved');
      if (v30) {
        // the live page deletes, then inserts: two direct versions (the recipe emptied, then the new one)
        await until(() => versions() === before + 2, 5000, 'two versions more');
        assert.strictEqual(sql(`select string_agg(source || ':' || jsonb_array_length(lines), ' ' order by version) from (select * from public.recipe_versions
                                 where menu_item_id = '${mi}' order by version desc limit 2) v`), 'direct:0 direct:' + sql(`select count(*) from public.recipes where menu_item_id = '${mi}'`));
      }
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, []);
    }
  }
];
