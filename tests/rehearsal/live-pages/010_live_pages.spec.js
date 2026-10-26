/* Canopy OS rehearsal · the pages that are LIVE on hanginggardencafe.com today (the gh-pages build named in
   tests/rehearsal/LIVE_PAGES), on the copy of production after every migration (0000-0033 today). Until the new pages are
   published, the café keeps using these: they must load and work exactly as before. Also run on the reset copy
   (tests/rehearsal/reset-pages.sh): nothing here assumes earlier sales, so the same checks hold on the empty café. */
'use strict';
const assert = require('assert');
const { page, goto, until, sql, registerSettled, STAFF } = require('../../e2e/lib');

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
   over the product grid, once it has asked for the register; a cashier closes it and sells, the register is opened by
   the manager (the empty café after the reset, tests/rehearsal/reset-pages.sh) */
async function closeDayNudge(pg) {
  await registerSettled(pg);
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
    // a device that stayed offline for days while recipes changed and 0030-0032 were applied: the sale it kept (dated
    // before the window) uploads untouched, takes the recipe the history started with and the first cost it knows, and
    // is flagged for a manager (0003); nothing is lost and nothing of today's recipe is deducted
    name: 'the live POS uploads a sale it kept for three days (rung before 0030, recipe and cost changed meanwhile): the starting recipe, the first cost, late_sync and after_close',
    run: async ({ browser }) => {
      const MI = '1c000000-0000-4000-8000-00000000c001', FR = '5c000000-0000-4000-8000-00000000c001', LE = '5c000000-0000-4000-8000-00000000c002';
      const SALE = '0c000000-0000-4000-8000-00000000c001', LINE = '0e000000-0000-4000-8000-00000000c001';
      const cat = sql(`select id from public.menu_categories order by sort, name limit 1`);
      // the product had its recipe before the window (no history: written with the triggers off); 0030 wrote the starting
      // version today; since then the recipe changed (a direct change, which 0030 records) and dearer strawberries arrived;
      // the register of the sale's day is closed
      sql(`insert into public.menu_items (id, category_id, name, price_crc) values ('${MI}', '${cat}', 'Batido ensayo', 3000);
           insert into public.stock_items (id, name, unit, pack_qty, cost_per_pack) values ('${FR}', 'Fresa ensayo', 'g', 1000, 4000), ('${LE}', 'Leche ensayo', 'ml', 1000, 1000);
           set session_replication_role = replica;
           insert into public.recipes (menu_item_id, stock_item_id, qty) values ('${MI}', '${FR}', 120), ('${MI}', '${LE}', 100);
           set session_replication_role = origin;
           select canopy.recipe_baseline();
           update public.recipes set qty = 150 where menu_item_id = '${MI}' and stock_item_id = '${FR}';
           insert into public.stock_moves (item_id, kind, qty, unit_cost) values ('${FR}', 'purchase', 5000, 6);
           insert into public.register_days (business_date, opened_by, opened_by_name, float_crc, closed_at, closed_by, closed_by_name)
             values (((now() - interval '3 days') at time zone 'America/Costa_Rica')::date, '${STAFF.ana}', 'Ana', 50000, now() - interval '2 days 10 hours', '${STAFF.ana}', 'Ana')
             on conflict (business_date) do update set closed_at = coalesce(public.register_days.closed_at, excluded.closed_at)`);
      // the sale exactly as the live recordSale() keeps it in localStorage 'hg-pos-queue', dated three days ago
      const kept = { local_id: 'o1760000000000abcde', id: SALE, none: true, created_at: new Date(Date.now() - 3 * 86400e3).toISOString(), total_crc: 6000,
                     payment_method: 'card', pickup_number: null, needs_kitchen: false, status: 'done', paid: true, station: 'Caja', guest_name: null,
                     items: [{ id: LINE, item_name: 'Batido ensayo', price_crc: 3000, qty: 2, menu_item_id: MI }] };
      const pg = watchApi(await page(browser, { login: 'cafe', storage: { 'hg-pos-queue': JSON.stringify([kept]) } }));
      await goto(pg, '/pos.html');
      await until(() => Number(sql(`select count(*) from public.order_items where order_id = '${SALE}'`)) === 1, 70000, 'the old sale uploaded with its line');
      await until(async () => (await pg.evaluate(() => JSON.parse(localStorage.getItem('hg-pos-queue') || '[]').length)) === 0, 10000, 'the device let it go');
      // (on the reset copy the sale is also from before the reset: 0028 adds before_reset, nothing else)
      const o = sql(`select (flags @> '{late_sync,after_close}' and flags <@ '{late_sync,after_close,before_reset}') || '|' || flags::text || '|'
                            || (business_date = ((now() - interval '3 days') at time zone 'America/Costa_Rica')::date) || '|' || (rung_at = created_at)
                       from public.orders where id = '${SALE}'`);
      assert.match(o, /^true\|\{[a-z_,]+\}\|true\|true$/, 'flagged late_sync and after_close, counted on its own day, rung_at kept: ' + o);
      assert.strictEqual(sql(`select v.source || ' v' || v.version || '|' || (i.stock_time = o.created_at) from public.order_items i join public.orders o on o.id = i.order_id
                                join public.recipe_versions v on v.id = i.recipe_version_id where i.id = '${LINE}'`), 'baseline v1|true', 'the line names the starting version and its own moment');
      assert.strictEqual(sql(`select string_agg(s.name || ':' || trim_scale(m.qty) || '@' || trim_scale(m.unit_cost), ' ' order by s.name)
                                from public.stock_moves m join public.stock_items s on s.id = m.item_id where m.order_id = '${SALE}'`),
                         'Fresa ensayo:-240@4 Leche ensayo:-200@1', 'the recipe of before (120 g) at the cost of before (₡4), not 150 g at ₡6');
      assert.strictEqual(sql(`select count(*) from public.audit_log where action = 'late_sale_after_close' and target_id = '${SALE}'`), '1', 'the manager log names it');
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, []);
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
    // 0033 (D-053) changed every PIN check and the team editor underneath the live pages: a wrong PIN, the manager PIN
    // that opens Hours, and adding a person with a free PIN must behave exactly as before
    name: 'the live Hours and team editor: a wrong PIN, the manager PIN, and a new person with a free PIN',
    run: async ({ browser }) => {
      const level = Number(sql(`select public.canopy_schema_version()`));
      const pg = watchApi(await page(browser, { login: 'cafe', lang: 'en' }));
      await goto(pg, '/time.html');
      await until(async () => (await pg.locator('#staffGrid button').count()) > 0, 15000, 'the clock');
      await pg.click('#tabHours');
      await pg.waitForSelector('#hoursPinModal:not([hidden])', { timeout: 10000 });
      await pg.selectOption('#hpWho', STAFF.ana);
      await pg.fill('#hpPin', '1111');
      await pg.click('#hoursPinForm button[type=submit]');
      await until(async () => /not right/.test(await pg.locator('#hpErr').textContent()), 8000, 'a wrong PIN is refused');
      await pg.fill('#hpPin', '4826');
      await pg.click('#hoursPinForm button[type=submit]');
      await until(async () => pg.locator('#hoursPinModal').isHidden(), 8000, 'the manager PIN opens Hours');
      await pg.click('#addStaffBtn');
      await pg.waitForSelector('#staffModal:not([hidden])', { timeout: 5000 });
      await pg.fill('#stName', 'Ensayo Equipo');
      await pg.fill('#stPin', '9264');
      await pg.fill('#stPin2', '9264');
      await pg.click('#staffForm button[type=submit]');
      await until(() => sql(`select count(*) from public.staff where name = 'Ensayo Equipo' and active`) === '1', 8000, 'the new person saved');
      if (level >= 33) assert.strictEqual(sql(`select details->>'by_login' is not null from public.audit_log where action = 'staff_save' order by id desc limit 1`), 't', 'logged with the login (0033)');
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
    // Two live editors are possible. The pre-1A editor (published until v2026.10.15-1) deletes the recipe and inserts
    // it again without a PIN: on 0030 and 0031 that works and the history records it as a direct change; from 0032 it is
    // refused and nothing changes. The editor published with 0030-0032 (v2026.10.17-1 and later) asks for a manager's
    // PIN and saves through recipe_save: one new version, source editor (on a database without 0030 it saves the old way).
    name: 'the live recipe editor: the PIN editor saves a version with a manager PIN; the old one saves up to 0031 and is refused from 0032',
    run: async ({ browser }) => {
      const stock = sql(`select id from public.stock_items where active order by name limit 1`);
      let mi = sql(`select menu_item_id from public.recipes order by menu_item_id limit 1`);
      if (!mi) {   // a copy without recipes: give one product a line first
        mi = sql(`select id from public.menu_items order by name limit 1`);
        sql(`insert into public.recipes (menu_item_id, stock_item_id, qty) values ('${mi}', '${stock}', 1)`);
      }
      const name = sql(`select name from public.menu_items where id = '${mi}'`);
      const level = Number(sql(`select public.canopy_schema_version()`)), v30 = level >= 30, locked = level >= 32;
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
      const item = await line.locator('select').first().inputValue();   // the ingredient; the PIN editor adds a unit select
      const qty = Number(await line.locator('input').inputValue());
      await line.locator('input').fill(String(qty + 1));
      await pg.click('#recipeSave');
      const pinEditor = (await pg.locator('#recPinForm').count()) > 0;
      if (pinEditor && v30) {
        // the editor published with 0030-0032: a manager (Ana, seeded with her test PIN) authorizes; recipe_save writes one version
        await pg.waitForSelector('#recPinModal:not([hidden])', { timeout: 5000 });
        await pg.selectOption('#recMgr', 'a1000000-0000-4000-8000-000000000001');
        await pg.fill('#recPin', '4826');
        await pg.click('#recPinGo');
        try { await until(async () => /Recipe saved|Receta guardada/.test(await pg.locator('#toast').textContent()), 8000, 'saved with the PIN'); }
        catch (e) { throw new Error(e.message + ' · PIN window: ' + (await pg.locator('#recPinErr').textContent()) + ' · recipe: ' + (await pg.locator('#recipeErr').textContent())); }
        assert.strictEqual(Number(sql(`select qty from public.recipes where menu_item_id = '${mi}' and stock_item_id = '${item}'`)), qty + 1, 'the new quantity is saved');
        await until(() => versions() === before + 1, 5000, 'one version more');
        assert.strictEqual(sql(`select source || ':' || coalesce(by_name, '') from public.recipe_versions where menu_item_id = '${mi}' order by version desc limit 1`),
          'editor:Ana', 'recorded as an editor version authorized by Ana');
        assert.deepStrictEqual(pg.errors, []);
        assert.deepStrictEqual(pg.apiErrors, []);
        return;
      }
      if (locked) {
        await until(async () => /Could not save the recipe/.test(await pg.locator('#toast').textContent()), 8000, 'refused');
        assert.strictEqual(Number(sql(`select qty from public.recipes where menu_item_id = '${mi}' and stock_item_id = '${item}'`)), qty, 'the recipe is unchanged');
        assert.strictEqual(versions(), before, 'and nothing was recorded');
        assert.deepStrictEqual(pg.errors, []);
        assert.ok(pg.apiErrors.length >= 1 && pg.apiErrors.every((e) => /^40[13] DELETE \/rest\/v1\/recipes/.test(e)), 'only the refused delete: ' + pg.apiErrors.join(' | '));
        return;
      }
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
