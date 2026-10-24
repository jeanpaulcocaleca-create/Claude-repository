/* Recipes saved with a PIN, with history (migration 0030): grams and millilitres on items counted in kg or litres,
   the average cost and the price without IVA, a wrong PIN and the lockout, two devices saving the same recipe,
   a draft that survives a reload (never its PIN), the old save on a database without 0030, frozen fruit counted
   and received in bags, and the guards around items and products that have a recipe. */
'use strict';
const assert = require('assert');
const { spawnSync } = require('child_process');
const path = require('path');
const { page, goto, until, sql, STAFF, PINS, ROOT } = require('../lib');

const CAFE = '5a000000-0000-4000-8000-000000e30001', LECHE = '5a000000-0000-4000-8000-000000e30002';
const ALMENDRA = '5a000000-0000-4000-8000-000000e30003', FRESA = '5a000000-0000-4000-8000-000000e30004';
/* coffee by the kilo, milk in 940 ml cartons, almond milk by the litre, strawberries in 1 kg bags */
function setup() {
  sql(`insert into stock_items (id, name, unit, pack_qty, pack_label, cost_per_pack) values
         ('${CAFE}', 'Café grano', 'kg', 1, 'bolsa 1 kg', 12000),
         ('${LECHE}', 'Leche entera', 'ml', 940, 'caja 940 ml', 1100),
         ('${ALMENDRA}', 'Leche almendra', 'L', 1, 'caja 1 L', 2400),
         ('${FRESA}', 'Fresa congelada', 'g', 1000, 'bolsa 1 kg', 4000)`);
}
const latte = () => sql(`select id from menu_items where name = 'Latte'`);
const plain = (s) => String(s || '').replace(/\s+/g, ' ').trim();   // the page's money uses narrow no-break spaces
const text = async (loc) => plain(await loc.textContent());
const toast = async (pg) => text(pg.locator('#toast'));
const recipeOf = (mi) => sql(`select string_agg(s.name || '=' || trim_scale(r.qty)::text, ' ' order by s.name)
                              from recipes r join stock_items s on s.id = r.stock_item_id where r.menu_item_id = '${mi}'`);
const versions = (mi) => sql(`select string_agg(version || ':' || source || ':' || coalesce(by_name, ''), ' ' order by version)
                              from recipe_versions where menu_item_id = '${mi}'`);

async function inventory(browser, opts) {
  opts = Object.assign({ login: 'owner', aal: 'aal2', lang: 'en' }, opts || {});
  const pg = await page(browser, opts);
  await goto(pg, '/inventory');
  if (opts.login === 'cafe') {
    await pg.waitForSelector('#hgaPin', { timeout: 8000 });
    await pg.selectOption('#hgaWho', STAFF.ana);
    await pg.fill('#hgaPin', PINS.ana);
    await pg.click('.hga-go');
  }
  await until(async () => (await pg.locator('#kItems').textContent()) !== '–', 15000, 'inventory loaded');
  return pg;
}
async function recipesTab(pg) {
  await pg.click('#tabs [data-view=recipes]');
  await until(async () => (await pg.locator('#menuList button').count()) > 0, 10000, 'menu listed');
}
/* opens a product by its exact name ("Latte", not "Iced Latte") */
async function openProduct(pg, name) {
  const i = await pg.evaluate((n) => Array.prototype.findIndex.call(document.querySelectorAll('#menuList button'),
    (b) => b.firstChild && b.firstChild.firstChild && b.firstChild.firstChild.textContent === n), name);
  assert.ok(i >= 0, name + ' is listed');
  await pg.locator('#menuList button').nth(i).click();
  await pg.waitForSelector('#recipeCard:not([hidden])', { timeout: 5000 });
}
const row = (pg, n) => pg.locator('#recipeRows .recipe-row').nth(n);
async function setLine(pg, n, item, qty, unit) {
  if (item) await row(pg, n).locator('select').first().selectOption(item);
  if (qty !== undefined) await row(pg, n).locator('input').fill(String(qty));
  if (unit) await row(pg, n).locator('select').nth(1).selectOption(unit);
}
async function pinSave(pg, who, pin, reason) {
  await pg.click('#recipeSave');
  await pg.waitForSelector('#recPinModal:not([hidden])', { timeout: 5000 });
  if (who) await pg.selectOption('#recMgr', who);
  if (reason !== undefined) await pg.fill('#recReason', reason);
  await pg.fill('#recPin', pin);
  await pg.click('#recPinGo');
}
async function pinAgain(pg, pin) { await pg.fill('#recPin', pin); await pg.click('#recPinGo'); }
async function toasted(pg, re, what) {
  try { await until(async () => re.test(await toast(pg)), 8000, what); }
  catch (e) { throw new Error(e.message + ' · toast: ' + (await toast(pg)) + ' · PIN window: ' + (await text(pg.locator('#recPinErr'))) + ' · recipe: ' + (await text(pg.locator('#recipeErr')))); }
}
async function pinError(pg, re, what) {
  await until(async () => re.test(await text(pg.locator('#recPinErr'))), 8000, what + ' (shown: ' + (await text(pg.locator('#recPinErr'))) + ')');
}
/* nothing a page keeps on the device holds a PIN */
async function noPinStored(pg) {
  const all = await pg.evaluate(() => JSON.stringify([Object.assign({}, localStorage), Object.assign({}, sessionStorage)]));
  for (const p of Object.values(PINS)) assert.ok(all.indexOf(p) < 0, 'no PIN kept on the device');
}

module.exports.tests = [
  {
    name: 'owner: a recipe in g and ml on kg and ml items, a wrong PIN, a manager PIN; average cost and price without IVA; history',
    run: async ({ browser }) => {
      setup();
      const mi = latte();
      const pg = await inventory(browser);
      await recipesTab(pg);
      await openProduct(pg, 'Latte');
      await setLine(pg, 0, CAFE, 18);
      assert.strictEqual(await row(pg, 0).locator('select').nth(1).inputValue(), 'g', 'coffee counted in kg is typed in grams');
      await pg.click('#recipeAddRow');
      await setLine(pg, 1, LECHE, 200);
      // 18 g × ₡12 000/kg = ₡216; 200 ml × ₡1 100/940 ml = ₡234.04; Latte ₡2 200 with IVA = ₡1 946.90 without IVA
      await until(async () => /^Estimated cost ₡450 \(average cost\) · 23,1% of the price without IVA$/.test(await text(pg.locator('#recipeCost'))), 5000, 'the cost');
      assert.match(await text(pg.locator('#recipeCost2')), /Price without IVA: ₡1 947/);
      assert.strictEqual(await text(row(pg, 0).locator('.lc')), '₡216');
      await pinSave(pg, STAFF.ana, '0000');
      await pinError(pg, /^That PIN is not right\.$/, 'a wrong PIN');
      assert.strictEqual(sql(`select failed_pins from staff where id = '${STAFF.ana}'`), '1', 'the wrong PIN is counted');
      assert.strictEqual(recipeOf(mi), '', 'nothing saved with a wrong PIN');
      await pinAgain(pg, PINS.ana);
      await toasted(pg, /^Recipe saved · version 1$/, 'saved');
      assert.ok(await pg.locator('#recPinModal').isHidden(), 'the PIN window closes');
      assert.strictEqual(recipeOf(mi), 'Café grano=0.018 Leche entera=200', 'grams stored as kg, millilitres as they are');
      assert.strictEqual(versions(mi), '1:editor:Ana');
      assert.strictEqual(sql(`select cost_crc from recipe_versions where menu_item_id = '${mi}'`), '450.04');
      assert.strictEqual(sql(`select manager_name || ' · ' || summary from audit_log where action = 'recipe_change'`), 'Ana · Latte · versión 1 · costo ₡0 → ₡450');
      assert.strictEqual(sql(`select failed_pins from staff where id = '${STAFF.ana}'`), '0');
      // the history shows the version, who and what
      await until(async () => (await pg.locator('#recipeHist .rv-item').count()) === 1, 5000, 'one version');
      const v1 = await text(pg.locator('#recipeHist .rv-item').first());
      assert.match(v1, /Version 1/); assert.match(v1, /Saved with PIN/); assert.match(v1, /Ana/);
      assert.match(v1, /Café grano 18 g/); assert.match(v1, /Leche entera 200 ml/);
      assert.strictEqual(await row(pg, 0).locator('input').inputValue(), '18', 'the saved recipe shows grams again');
      assert.match(await text(pg.locator('#menuList button.on')), /2 ingredients/);

      // substitute the milk (same family: the 200 ml stay), take the coffee out, save with the owner's PIN
      await setLine(pg, 1, ALMENDRA);
      assert.strictEqual(await row(pg, 1).locator('input').inputValue(), '200');
      assert.strictEqual(await row(pg, 1).locator('select').nth(1).inputValue(), 'ml');
      await row(pg, 0).locator('button', { hasText: 'Remove' }).click();
      await until(async () => (await pg.locator('#recipeRows .recipe-row').count()) === 1, 3000, 'one line left');
      await until(async () => /^Estimated cost ₡480 /.test(await text(pg.locator('#recipeCost'))), 5000, 'the new cost');
      await pinSave(pg, STAFF.dueno, PINS.dueno, 'leche de almendra');
      await toasted(pg, /^Recipe saved · version 2$/, 'version 2');
      assert.strictEqual(recipeOf(mi), 'Leche almendra=0.2', '200 ml stored as 0.2 L');
      assert.strictEqual(versions(mi), '1:editor:Ana 2:editor:Dueño');
      assert.strictEqual(sql(`select cost_before_crc || ' → ' || cost_crc || ' · ' || reason from recipe_versions where menu_item_id = '${mi}' and version = 2`), '450.04 → 480.00 · leche de almendra');
      await until(async () => (await pg.locator('#recipeHist .rv-item').count()) === 2, 5000, 'two versions');
      const v2 = await text(pg.locator('#recipeHist .rv-item').first());
      assert.match(v2, /Version 2/); assert.match(v2, /Dueño/); assert.match(v2, /₡450 → ₡480/); assert.match(v2, /leche de almendra/);
      assert.match(v2, /\+ Leche almendra 200 ml/); assert.match(v2, /− Café grano 18 g/); assert.match(v2, /− Leche entera 200 ml/);
      // saving the same again changes nothing
      await pinSave(pg, STAFF.ana, PINS.ana);
      await toasted(pg, /^Nothing changed in the recipe$/, 'unchanged');
      assert.strictEqual(versions(mi), '1:editor:Ana 2:editor:Dueño');
      await noPinStored(pg);
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'two devices: the second save is refused and keeps its draft; a draft survives a reload without its PIN',
    run: async ({ browser }) => {
      setup();
      const mi = latte();
      sql(`insert into recipes (menu_item_id, stock_item_id, qty) values ('${mi}', '${LECHE}', 200)`);   // version 1, a direct write
      assert.strictEqual(versions(mi), '1:direct:sistema');
      const a = await inventory(browser), b = await inventory(browser);
      await recipesTab(a); await recipesTab(b);
      await openProduct(a, 'Latte'); await openProduct(b, 'Latte');
      await setLine(a, 0, null, 250);
      await setLine(b, 0, null, 300);
      await pinSave(a, STAFF.ana, PINS.ana);
      await toasted(a, /^Recipe saved · version 2$/, 'the first device saves');
      await pinSave(b, STAFF.ana, PINS.ana);
      await until(async () => /^Someone else saved this recipe meanwhile \(now version 2\)\./.test(await text(b.locator('#recipeErr'))), 8000, 'the second is refused');
      assert.ok(await b.locator('#recPinModal').isHidden());
      assert.strictEqual(await row(b, 0).locator('input').inputValue(), '300', 'its draft is still on screen');
      assert.strictEqual(recipeOf(mi), 'Leche entera=250', 'the first save stands');
      assert.strictEqual(versions(mi), '1:direct:sistema 2:editor:Ana');
      await openProduct(b, 'Latte');
      assert.strictEqual(await row(b, 0).locator('input').inputValue(), '250', 'opened again: the version saved by the other device');

      // a draft (never the PIN) survives a reload, e.g. when the 15-minute unlock ends
      await setLine(b, 0, null, 275);
      await b.reload({ waitUntil: 'domcontentloaded' });
      await until(async () => (await b.locator('#kItems').textContent()) !== '–', 15000, 'reloaded');
      await recipesTab(b);
      await until(async () => /^Unsaved draft: Latte/.test(await text(b.locator('#draftNote'))), 5000, 'the draft is announced');
      await b.locator('#draftNote button').click();
      await b.waitForSelector('#recipeNote:not([hidden])');
      assert.match(await text(b.locator('#recipeNote')), /^Unsaved draft recovered\./);
      assert.strictEqual(await row(b, 0).locator('input').inputValue(), '275');
      await pinSave(b, STAFF.ana, PINS.ana);
      await toasted(b, /^Recipe saved · version 3$/, 'the recovered draft saved');
      assert.strictEqual(recipeOf(mi), 'Leche entera=275');
      assert.ok(await b.locator('#draftNote').isHidden(), 'the draft is gone once saved');
      assert.match(await text(b.locator('#recipeNote')), /^Recipe saved · version 3 · Ana$/, 'a confirmation that stays on screen');
      assert.strictEqual(await b.evaluate(() => sessionStorage.getItem('hg-recipe-draft')), null);
      // a draft older than the saved version is dropped, not offered
      await setLine(a, 0, null, 999);
      sql(`update recipes set qty = 280 where menu_item_id = '${mi}'`);   // version 4, written by an older page
      await a.reload({ waitUntil: 'domcontentloaded' });
      await until(async () => (await a.locator('#kItems').textContent()) !== '–', 15000, 'reloaded');
      await recipesTab(a);
      assert.ok(await a.locator('#draftNote').isHidden(), 'the stale draft is not offered');
      await openProduct(a, 'Latte');
      assert.strictEqual(await row(a, 0).locator('input').inputValue(), '280', 'the stale draft is not restored');
      assert.ok(await a.locator('#recipeNote').isHidden());
      await until(async () => /Version 4.*Direct change/.test(await text(a.locator('#recipeHist .rv-item').first())), 5000, 'the direct change in the history');
      await noPinStored(a); await noPinStored(b);
      assert.deepStrictEqual(a.errors.concat(b.errors), []);
    }
  },
  {
    name: 'café device in Spanish: the manager unlocks; five wrong PINs lock that manager out, the owner\'s PIN saves; an empty recipe needs a reason',
    run: async ({ browser }) => {
      setup();
      const mi = latte();
      const pg = await inventory(browser, { login: 'cafe', lang: 'es' });
      await recipesTab(pg);
      await openProduct(pg, 'Latte');
      await setLine(pg, 0, FRESA, 120);
      // 120 g × ₡4 000/kg = ₡480; 480 / 1 946,90 = 24,7 %
      await until(async () => (await text(pg.locator('#recipeCost'))) === 'Costo estimado ₡480 (costo promedio) · 24,7% del precio sin IVA', 5000, 'the cost line, in Spanish: ' + (await text(pg.locator('#recipeCost'))));
      assert.strictEqual(await text(pg.locator('#recipeCost2')), 'Precio sin IVA: ₡1 947');
      await pg.click('#recipeSave');
      await pg.waitForSelector('#recPinModal:not([hidden])');
      await until(async () => (await text(pg.locator('#recPinTitle'))) === 'Guardar la receta · Latte', 5000, 'the title, in Spanish');
      assert.strictEqual(await pg.locator('#recMgr').inputValue(), STAFF.ana, 'whoever unlocked the device is proposed');
      const names = await pg.locator('#recMgr option').allTextContents();
      assert.deepStrictEqual(names, ['Ana', 'Dueño'], 'only managers and owners can authorize');
      for (let k = 1; k <= 5; k++) {
        await pinAgain(pg, '1111');
        await pinError(pg, /^Ese PIN no es correcto\.$/, 'wrong PIN ' + k);
        await until(async () => sql(`select failed_pins from staff where id = '${STAFF.ana}'`) === String(k), 3000, 'counted ' + k);
        await pg.locator('#recPinErr').evaluate((e) => { e.textContent = ''; });
      }
      await pinAgain(pg, PINS.ana);
      await pinError(pg, /^Demasiados PIN incorrectos\. Espere 10 minutos e intente de nuevo\.$/, 'locked out, even with the right PIN');
      assert.strictEqual(recipeOf(mi), '', 'nothing saved');
      await pg.selectOption('#recMgr', STAFF.dueno);
      await pinAgain(pg, PINS.dueno);
      await toasted(pg, /^Receta guardada · versión 1$/, 'saved with the owner\'s PIN, in Spanish');
      assert.strictEqual(recipeOf(mi), 'Fresa congelada=120');
      assert.strictEqual(versions(mi), '1:editor:Dueño');
      await until(async () => /Guardada con PIN/.test(await text(pg.locator('#recipeHist'))), 5000, 'the history, in Spanish');

      // leaving the product without ingredients asks first, then needs a reason
      await row(pg, 0).locator('button').click();
      const dialogs = []; pg.onDialog = async (d) => { dialogs.push(d.message()); await d.accept(); };
      await pg.click('#recipeSave');
      await pg.waitForSelector('#recPinModal:not([hidden])');
      assert.match(dialogs[0] || '', /sin ingredientes/, 'a confirmation in Spanish: ' + dialogs[0]);
      await pg.selectOption('#recMgr', STAFF.dueno);
      await pinAgain(pg, PINS.dueno);
      await pinError(pg, /^Para dejar un producto sin ingredientes, escriba el motivo\.$/, 'the reason is required');
      await pg.fill('#recReason', 'ya no se vende con fruta');
      await pinAgain(pg, PINS.dueno);
      await toasted(pg, /^Receta guardada · versión 2$/, 'version 2');
      assert.strictEqual(recipeOf(mi), '');
      assert.strictEqual(sql(`select jsonb_array_length(lines) || ' · ' || reason from recipe_versions where menu_item_id = '${mi}' and version = 2`), '0 · ya no se vende con fruta');
      await until(async () => /ya no se vende con fruta/.test(await text(pg.locator('#recipeHist'))), 5000, 'the reason in the history');
      await noPinStored(pg);
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'a database without 0030 (or after its rollback): the page saves recipes the old way, without PIN or history',
    run: async ({ browser }) => {
      setup();
      // newest first: 0032, 0031, then 0030
      for (const f of ['reversion-0033.sql', 'reversion-0032.sql', 'reversion-0031.sql', 'reversion-0030.sql']) {
        const r = spawnSync('psql', ['-X', '-q', '-v', 'ON_ERROR_STOP=1', '--single-transaction', '-d', process.env.CANOPY_E2E_DB,
          '-f', path.join(ROOT, 'supabase/tools', f)], { encoding: 'utf8' });
        assert.strictEqual(r.status, 0, 'the rollback ' + f + ' runs: ' + r.stderr);
      }
      assert.strictEqual(sql(`select canopy_schema_version()`), '29');
      const mi = latte();
      const pg = await inventory(browser);
      await recipesTab(pg);
      await openProduct(pg, 'Latte');
      await setLine(pg, 0, CAFE, 18);
      await pg.click('#recipeSave');
      await toasted(pg, /^Recipe saved$/, 'the old save');
      assert.ok(await pg.locator('#recPinModal').isHidden(), 'no PIN asked');
      assert.ok(await pg.locator('#recipeHistBox').isHidden(), 'no history shown');
      assert.strictEqual(recipeOf(mi), 'Café grano=0.018', 'grams are still converted to the item\'s kg');
      assert.strictEqual(sql(`select count(*) from recipe_versions`), '0', 'nothing written to the history');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'frozen fruit by the bag: a count in closed bags plus loose grams; a delivery in bags or grams; the pack hint',
    run: async ({ browser }) => {
      setup();
      const VENDOR = '5b000000-0000-4000-8000-000000e30001', PO = '9a000000-0000-4000-8000-000000e30001';
      sql(`insert into vendors (id, name) values ('${VENDOR}', 'Finca Fresa');
           update stock_items set vendor_id = '${VENDOR}' where id = '${FRESA}';
           insert into purchase_orders (id, vendor_id, status) values ('${PO}', '${VENDOR}', 'sent');
           insert into purchase_lines (po_id, item_id, packs, qty, unit_cost) values ('${PO}', '${FRESA}', 2, 2000, 4)`);
      const pg = await inventory(browser);
      await pg.click('#tabs [data-view=stock]');
      const fresa = pg.locator('#stockTable tr', { hasText: 'Fresa congelada' });
      await fresa.locator('button', { hasText: 'Count' }).click();
      await pg.waitForSelector('#moveModal:not([hidden])');
      assert.ok(await pg.locator('#mvCountPackRow').isVisible(), 'bags and loose grams for an item bought in bags');
      assert.strictEqual(await text(pg.locator('#mvCountLooseLabel')), 'Loose (g)');
      await pg.fill('#mvCountPacks', '3');
      await pg.fill('#mvCountLoose', '250');
      assert.strictEqual(await pg.locator('#mvCounted').inputValue(), '3250', '3 bags of 1000 g + 250 g');
      await pg.locator('#moveForm button[type=submit]').click();
      await until(async () => sql(`select coalesce(sum(qty), 0) from stock_moves where item_id = '${FRESA}'`) === '3250', 8000, 'counted 3250 g');
      // typing the total by hand clears the bags
      await fresa.locator('button', { hasText: 'Count' }).click();
      await pg.waitForSelector('#moveModal:not([hidden])');
      await pg.fill('#mvCountPacks', '1');
      await pg.fill('#mvCounted', '900');
      assert.strictEqual(await pg.locator('#mvCountPacks').inputValue(), '');
      await pg.click('#mvCancel');
      // coffee bought one bag = one kg: no bag row
      await pg.locator('#stockTable tr', { hasText: 'Café grano' }).locator('button', { hasText: 'Count' }).click();
      await pg.waitForSelector('#moveModal:not([hidden])');
      assert.ok(await pg.locator('#mvCountPackRow').isHidden());
      await pg.click('#mvCancel');

      // receiving: bags fill the grams and grams fill the bags
      await pg.click('#tabs [data-view=orders]');
      const card = pg.locator('#poList .po').first();
      await until(async () => (await card.count()) > 0, 8000, 'order listed');
      await card.locator('button', { hasText: /^Receive$/ }).click();
      await pg.waitForSelector('#recvModal:not([hidden])');
      const packs = pg.locator('#recvTable [data-f=packs]'), qty = pg.locator('#recvTable [data-f=qty]');
      assert.strictEqual(await packs.inputValue(), '2'); assert.strictEqual(await qty.inputValue(), '2000');
      await packs.fill('3');
      assert.strictEqual(await qty.inputValue(), '3000');
      await qty.fill('1500');
      assert.strictEqual(await packs.inputValue(), '1.5');
      await pg.click('#recvCancel');

      // a new item: the hint says what "units per pack" means for grams
      await pg.click('#tabs [data-view=stock]');
      await pg.click('#addItemBtn');
      await pg.waitForSelector('#itemModal:not([hidden])');
      await pg.selectOption('#itUnit', 'g');
      assert.match(await text(pg.locator('#itPackHint')), /usable grams in one pack \(a 1 kg bag of frozen fruit = 1000\)/);
      await pg.selectOption('#itUnit', 'ml');
      assert.match(await text(pg.locator('#itPackHint')), /940 ml carton of milk = 940/);
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'guards: an item in a recipe keeps its unit and is not deleted; the menu warns before deleting a product with a recipe; the approvals log',
    run: async ({ browser }) => {
      setup();
      const mi = latte();
      sql(`insert into recipes (menu_item_id, stock_item_id, qty) values ('${mi}', '${CAFE}', 0.018)`);
      const pg = await inventory(browser);
      await pg.click('#tabs [data-view=stock]');
      await pg.locator('#stockTable tr', { hasText: 'Café grano' }).locator('button', { hasText: 'Edit' }).click();
      await pg.waitForSelector('#itemModal:not([hidden])');
      await pg.selectOption('#itUnit', 'g');
      await pg.locator('#itemForm button[type=submit]').click();
      await until(async () => /its unit stays/.test(await text(pg.locator('#itErr'))), 8000, 'the unit is kept');
      assert.strictEqual(sql(`select unit from stock_items where id = '${CAFE}'`), 'kg');
      await pg.click('#itDelete');
      await until(async () => /This item is in a recipe\./.test(await text(pg.locator('#itErr'))), 8000, 'not deleted');
      assert.strictEqual(sql(`select count(*) from stock_items where id = '${CAFE}'`), '1');
      await pg.click('#itCancel');
      // a recipe saved with a PIN shows in the approvals log of the time clock
      await recipesTab(pg);
      await openProduct(pg, 'Latte');
      await setLine(pg, 0, null, 20);
      await pinSave(pg, STAFF.ana, PINS.ana);
      await toasted(pg, /^Recipe saved · version 2$/, 'saved');

      const tm = await page(browser, { login: 'owner', aal: 'aal2', lang: 'en' });
      await goto(tm, '/time');
      await tm.click('#tabHours');
      await until(async () => /Recipe changed · approved by Ana/.test(await text(tm.locator('#logBody'))), 15000, 'the approvals log');
      assert.match(await text(tm.locator('#logBody')), /Latte · versión 2 · costo ₡216 → ₡240/);

      // deleting a product with a recipe: first a warning (Sold out keeps it), cancelling keeps the product
      const ad = await page(browser, { login: 'owner', aal: 'aal2', lang: 'en' });
      await goto(ad, '/admin');
      await until(async () => (await ad.locator('.item').count()) > 0, 15000, 'menu loaded');
      const item = ad.locator('.item', { has: ad.locator('text=/^Latte$/') }).first();
      await item.locator('button', { hasText: 'Edit' }).click();
      const seen = [];
      ad.onDialog = async (d) => { seen.push(d.message()); await d.dismiss(); };
      await item.locator('.editbox [data-del]').click();
      await until(async () => seen.length > 0, 5000, 'a warning');
      assert.match(seen[0], /"Latte" has a recipe\. To stop selling it for a while, tap Sold out instead/);
      await new Promise((r) => setTimeout(r, 300));
      assert.strictEqual(seen.length, 1, 'cancelled at the first question');
      assert.strictEqual(sql(`select count(*) from menu_items where id = '${mi}'`), '1', 'the product stays');
      // a product without a recipe gets only the usual question
      const esp = ad.locator('.item', { has: ad.locator('text=/^Espresso$/') }).first();
      await esp.locator('button', { hasText: 'Edit' }).click();
      seen.length = 0;
      await esp.locator('.editbox [data-del]').click();
      await until(async () => seen.length > 0, 5000, 'the usual question');
      assert.match(seen[0], /^Delete "Espresso" from the menu\?/);
      assert.deepStrictEqual(pg.errors.concat(tm.errors, ad.errors), []);
    }
  },
  {
    name: 'on a phone (390 px): find a product, edit the recipe by touch, see the costs, save with the PIN and read the history, nothing scrolls sideways',
    run: async ({ browser }) => {
      setup();
      const mi = latte();
      const shots = process.env.E2E_SHOTS;   // a folder: screenshots of the phone screens are saved there (for the owner to look at)
      const pg = await page(browser, { login: 'owner', aal: 'aal2', lang: 'es', viewport: { width: 390, height: 844 } });
      await goto(pg, '/inventory');
      await until(async () => (await pg.locator('#kItems').textContent()) !== '–', 15000, 'inventory loaded');
      /* nothing wider than the screen, and every control a finger wide and inside it */
      async function fits(what) {
        const m = await pg.evaluate(() => {
          const w = window.innerWidth, out = { scrollW: Math.max(document.documentElement.scrollWidth, document.body.scrollWidth), w: w, bad: [] };
          document.querySelectorAll('#view-recipes select, #view-recipes input, #view-recipes button, #recPinModal:not([hidden]) select, #recPinModal:not([hidden]) input, #recPinModal:not([hidden]) button').forEach((el) => {
            const r = el.getBoundingClientRect();
            if (!r.width || el.closest('[hidden]')) return;
            if (r.left < 0 || r.right > w + 0.5 || r.height < 44) out.bad.push((el.id || el.className || el.tagName) + ' ' + Math.round(r.left) + '-' + Math.round(r.right) + ' h' + Math.round(r.height));
          });
          return out;
        });
        assert.ok(m.scrollW <= m.w, what + ': the page scrolls sideways (' + m.scrollW + ' > ' + m.w + ')');
        assert.deepStrictEqual(m.bad, [], what + ': controls outside the screen or too small for a finger');
      }
      await pg.click('#tabs [data-view=recipes]');
      await until(async () => (await pg.locator('#menuList button').count()) > 0, 10000, 'menu listed');
      assert.strictEqual(await pg.locator('#menuFind').getAttribute('placeholder'), 'Buscar un producto');
      await pg.fill('#menuFind', 'latte');
      await until(async () => (await pg.locator('#menuList button').count()) === 3, 5000, 'three lattes');
      await pg.fill('#menuFind', 'zzzz');
      await until(async () => /Ningún producto coincide/.test(await text(pg.locator('#menuList'))), 5000, 'no match');
      await pg.fill('#menuFind', 'Latte');
      await openProduct(pg, 'Latte');
      await fits('the editor');
      await setLine(pg, 0, CAFE, 18);
      await pg.click('#recipeAddRow');
      await setLine(pg, 1, LECHE, 200);
      await until(async () => /^Costo estimado ₡450 \(costo promedio\) · 23,1% del precio sin IVA$/.test(await text(pg.locator('#recipeCost'))), 5000, 'the cost');
      assert.ok(await row(pg, 0).locator('.lc').isVisible(), 'the cost of each line is shown on the phone');
      assert.strictEqual(await text(row(pg, 0).locator('.lc')), '₡216');
      assert.strictEqual(await text(row(pg, 0).locator('button')), 'Quitar');
      await fits('two ingredients');
      // substitute by touch: the almond milk keeps the 200 ml; take the coffee out; then put it back
      await setLine(pg, 1, ALMENDRA);
      assert.strictEqual(await row(pg, 1).locator('input').inputValue(), '200');
      await row(pg, 0).locator('button').click();
      await until(async () => (await pg.locator('#recipeRows .recipe-row').count()) === 1, 3000, 'one line');
      await pg.click('#recipeAddRow');
      await setLine(pg, 1, CAFE, 18);
      await until(async () => /^Costo estimado ₡696 /.test(await text(pg.locator('#recipeCost'))), 5000, 'the cost follows');
      if (shots) await pg.screenshot({ path: shots + '/telefono-receta.png' });
      await pg.click('#recipeSave');
      await pg.waitForSelector('#recPinModal:not([hidden])', { timeout: 5000 });
      await fits('the PIN window');
      const box = await pg.locator('#recPinForm').boundingBox();
      assert.ok(box.x >= 0 && box.x + box.width <= 390, 'the PIN window fits the screen');
      await pg.selectOption('#recMgr', STAFF.ana);
      await pg.fill('#recPin', '0000');
      if (shots) await pg.screenshot({ path: shots + '/telefono-pin.png' });
      await pg.click('#recPinGo');
      await pinError(pg, /^Ese PIN no es correcto\.$/, 'a wrong PIN, in Spanish');
      assert.ok(await pg.locator('#recPinErr').isVisible(), 'the message is on screen');
      await pinAgain(pg, PINS.ana);
      await toasted(pg, /^Receta guardada · versión 1$/, 'saved');
      await until(async () => (await text(pg.locator('#recipeNote'))) === 'Receta guardada · versión 1 · Ana', 5000, 'a confirmation that stays on screen');
      assert.ok(await pg.locator('#recipeNote').isVisible());
      assert.strictEqual(recipeOf(mi), 'Café grano=0.018 Leche almendra=0.2');
      await until(async () => (await pg.locator('#recipeHist .rv-item').count()) === 1, 5000, 'the history');
      assert.match(await text(pg.locator('#recipeHist .rv-item').first()), /Versión 1.*Guardada con PIN.*Ana/);
      await fits('after saving, with the history');
      if (shots) await pg.screenshot({ path: shots + '/telefono-guardado.png' });
      // an error the server refuses: clear, on screen
      await setLine(pg, 0, null, 50000);     // 50 kg of coffee in one latte
      await pg.click('#recipeSave');
      await pg.waitForSelector('#recPinModal:not([hidden])', { timeout: 5000 });
      await pg.fill('#recPin', PINS.ana); await pg.click('#recPinGo');
      await pinError(pg, /^La cantidad de Café grano es demasiado grande para una porción\. Revise la unidad\.$/, 'too much, in Spanish');
      await pg.click('#recPinCancel');
      await noPinStored(pg);
      assert.deepStrictEqual(pg.errors, []);
    }
  }
];
