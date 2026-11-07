/* Proveedores (D-067) · ordering with checkboxes: tick, untick, quantities, the live total, «+ Producto nuevo» without
   losing the ticks, «Crear pedido» (a double tap makes ONE order; 2 boxes of 12 are 24 units on the order); the draft
   saves itself (a reload brings it back; another device opens the server's; a stale device is told «changed» and may
   take the other's or merge; the base_version rules on open); «Repetir último pedido» and «Duplicar»; an order made
   with the keyboard only; and the speed target of a habitual order (timed, taps counted). */
'use strict';
const assert = require('assert');
const { page, goto, until, sql } = require('../lib');
const P = require('../prov');
const { V, I, text } = P;

const row = (pg, item, vendor) => pg.locator(`#pList .prow[data-vi="${P.vi(item, vendor)}"]`);
const sum = (pg) => text(pg.locator('#pSum'));
async function saved(pg, what) { await P.seen(pg.locator('#pStatus'), /^Borrador guardado \d\d:\d\d$/, what || 'the draft saved on the server', 8000); }
function draft(vendor) { return sql(`select version || '|' || lines::text || '|' || coalesce(note, '') from purchase_drafts where vendor_id = '${vendor || V.lac}' and status = 'open'`); }
function linesOf(vendor) {
  return sql(`select coalesce(string_agg(v.vendor_item_id::text || ':' || trim_scale(x.value::numeric)::text, ',' order by v.vendor_item_id), '')
                from purchase_drafts d cross join lateral jsonb_array_elements(d.lines) e cross join lateral (select e ->> 'vendor_item_id' as vendor_item_id) v
                cross join lateral (select e -> 'packs' as value) x where d.vendor_id = '${vendor || V.lac}' and d.status = 'open'`);
}

module.exports.tests = [
  {
    name: 'tick, quantities, untick, the live total; «+ Producto nuevo» keeps the ticks; a double tap on «Crear pedido» makes one order',
    run: async ({ browser }) => {
      P.seed();
      const pg = await P.owner(browser, { hash: '#p=' + V.lac, wait: '#pList .prow' });
      assert.match(await sum(pg), /^0 productos · Total estimado ₡0$/);
      assert.strictEqual(await pg.locator('#pCreate').isDisabled(), true, 'nothing to create yet');
      // tick: the suggestion (no usual quantity, never ordered: 1)
      await row(pg, I.leche).locator('.ck input').check();
      await P.seen(pg.locator('#pSum'), /^1 producto · Total estimado ₡10 200$/, 'one box', 3000);
      await row(pg, I.leche).locator('button[data-a=plus]').click();
      await P.seen(pg.locator('#pSum'), /^1 producto · Total estimado ₡20 400$/, 'two boxes', 3000);
      // typing a quantity ticks the row; kilograms take decimals
      await row(pg, I.yogur).locator('.step input').fill('3');
      assert.strictEqual(await row(pg, I.yogur).locator('.ck input').isChecked(), true, 'typing ticks it');
      await row(pg, I.queso).locator('.step input').fill('2.5');
      await P.seen(pg.locator('#pSum'), /^3 productos · Total estimado ₡46 900$/, '20 400 + 3 × 4 500 + 2,5 × 5 200', 3000);
      // «−» down to the minimum unticks (it never shows 0); an emptied box unticks
      const q = row(pg, I.queso);
      await q.locator('button[data-a=minus]').click();
      assert.strictEqual(await q.locator('.step input').inputValue(), '1.5');
      await q.locator('button[data-a=minus]').click();
      assert.strictEqual(await q.locator('.step input').inputValue(), '1');
      await q.locator('button[data-a=minus]').click();
      assert.strictEqual(await q.locator('.ck input').isChecked(), false, 'unticked at the minimum');
      assert.notStrictEqual(await q.locator('.step input').inputValue(), '0', 'never shows 0');
      await row(pg, I.yogur).locator('.step input').fill('');
      assert.strictEqual(await row(pg, I.yogur).locator('.ck input').isChecked(), false, 'an emptied box is unticked');
      await row(pg, I.yogur).locator('.step input').fill('3');
      await P.seen(pg.locator('#pSum'), /^2 productos · Total estimado ₡33 900$/, 'milk and yogurt', 3000);
      // «+ Producto nuevo»: a new inventory item, its presentation and price; it is ticked, the other ticks stay
      await pg.click('#pNew');
      await pg.fill('#npFind', 'Cajeta');
      await pg.locator('#npFound button', { hasText: 'No está en el inventario: un artículo nuevo' }).click();
      assert.strictEqual(await pg.inputValue('#npName'), 'Cajeta');
      await pg.fill('#npPack', 'frasco de 500 g');
      await pg.selectOption('#npUnit', 'g');
      await pg.fill('#npQty', '500');
      await P.seen(pg.locator('#npHint'), /^1 frasco de 500 g = 500 g$/, 'what one presentation holds', 3000);
      await pg.fill('#npPrice', '2500');
      await pg.click('#npGo');
      await P.seen(pg.locator('#pSum'), /^3 productos · Total estimado ₡36 400$/, 'the new product ticked, the others kept', 8000);
      const cajeta = sql(`select id from stock_items where name = 'Cajeta'`);
      assert.strictEqual(sql(`select unit || '|' || on_hand || '|' || vendor_id from stock_items where id = '${cajeta}'`), `g|0|${V.lac}`, 'a new item: its first supplier is the preferred one');
      assert.strictEqual(sql(`select pack_label || '|' || trim_scale(pack_qty) || '|' || usual_price from vendor_items where item_id = '${cajeta}'`), 'frasco de 500 g|500|2500.00');
      await pg.fill('#pNote', 'Por favor antes de las 9');
      // a double tap: one order (the request id is kept until the answer)
      await pg.evaluate(() => { const b = document.getElementById('pCreate'); b.click(); b.click(); });
      await pg.waitForSelector('#orderDoc', { timeout: 10000 });
      assert.match(pg.url(), /#pedido=[0-9a-f-]{36}$/);
      assert.strictEqual(sql(`select count(*) from purchase_orders`), '1', 'exactly one order');
      assert.strictEqual(sql(`select status || '|' || note || '|' || (sent_at is not null) from purchase_orders`), 'sent|Por favor antes de las 9|true');
      assert.strictEqual(sql(`select string_agg(i.name || ':' || trim_scale(l.packs) || ':' || trim_scale(l.qty) || ':' || trim_scale(round(l.unit_cost * l.pack_qty, 2)), ', ' order by l.pos)
                                from purchase_lines l join stock_items i on i.id = l.item_id`),
        'Leche entera:2:24:10200, Yogur natural:3:18:4500, Cajeta:1:500:2500', '2 boxes of 12 are 24 units; the price per presentation is kept');
      assert.strictEqual(sql(`select string_agg(status, ',') from purchase_drafts`), 'used', 'the draft became the order');
      await P.toasted(pg, /^Pedido Nº \d+ creado$/, 'the toast, in Spanish');
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, []);
    }
  },
  {
    name: 'the alert\'s highlighted row shows its suggestion; the first key typed replaces it (keyboard and the tablet\'s keypad): 2 is 2, never 62',
    run: async ({ browser }) => {
      P.seed();
      // a keyboard: the box focused and left alone keeps the suggestion; typed, the typed number is the quantity
      const pg = await P.owner(browser, { hash: '#alerta=' + I.leche, wait: '#pList .prow.pin' });
      const pin = pg.locator('#pList .prow.pin'), box = pin.locator('.step input');
      assert.strictEqual(await box.inputValue(), '6', 'the suggestion is shown');
      await box.click();
      await pg.locator('#pSearch').click();   /* left without typing */
      assert.strictEqual(await box.inputValue(), '6', 'the suggestion comes back');
      assert.strictEqual(await pin.locator('.ck input').isChecked(), false, 'still not ticked');
      await box.click();
      await pg.keyboard.type('2');
      assert.strictEqual(await box.inputValue(), '2', 'the first key replaced the suggestion');
      await P.seen(pg.locator('#pSum'), /^1 producto · Total estimado ₡20 400$/, 'two boxes, ticked', 3000);
      assert.strictEqual(await pin.locator('.ck input').isChecked(), true);
      assert.deepStrictEqual(pg.errors, []);
      // the café tablet's on-screen keypad adds to what is in the box: its first key replaces the suggestion too
      const ctx = await browser.newContext({ viewport: { width: 820, height: 1180 }, hasTouch: true, isMobile: true, locale: 'es-CR', timezoneId: 'America/Costa_Rica' });
      const tab = P.watchApi(await page(browser, { context: ctx, login: 'owner', aal: 'aal2', lang: 'es' }));
      await goto(tab, '/proveedores#p=' + V.pan + '&item=' + I.pan);
      const tpin = tab.locator('#pList .prow.pin');
      await tpin.waitFor({ timeout: 10000 });
      const tbox = tpin.locator('.step input');
      const sug = await tbox.inputValue();
      assert.ok(Number(sug) > 0, 'a suggestion is shown: ' + sug);
      await tbox.click();
      const pad = tpin.locator('.hg-pad');
      await pad.waitFor({ state: 'visible', timeout: 3000 });
      await pad.locator('button', { hasText: /^2$/ }).click();
      assert.strictEqual(await tbox.inputValue(), '2', 'the keypad\'s 2 replaced the suggestion ' + sug + ' (not ' + sug + '2)');
      await P.seen(tab.locator('#pSum'), /^1 producto · Total estimado ₡6 000$/, 'two bags of bread', 3000);
      assert.deepStrictEqual(tab.errors, []);
      assert.deepStrictEqual(tab.apiErrors, []);
      await ctx.close();
    }
  },
  {
    name: 'the draft saves itself: a reload brings it back; a second device opens it; a stale device gets «changed» and merges',
    run: async ({ browser }) => {
      P.seed();
      const a = await P.owner(browser, { hash: '#p=' + V.lac, wait: '#pList .prow' });
      await row(a, I.leche).locator('.step input').fill('2');
      await saved(a);
      assert.match(draft(), /^1\|\[\{"packs": 2, "vendor_item_id": "[0-9a-f-]+"\}\]\|$/, 'the server keeps [{vendor_item_id, packs}] only');
      assert.strictEqual(JSON.parse(await a.evaluate((k) => localStorage.getItem(k), 'hg-prov-draft:' + V.lac)).base_version, 1);
      await a.reload({ waitUntil: 'domcontentloaded' });
      await a.waitForSelector('#pList .prow');
      assert.strictEqual(await row(a, I.leche).locator('.step input').inputValue(), '2', 'back after a reload');
      assert.strictEqual(await row(a, I.leche).locator('.ck input').isChecked(), true);
      // a second device: the server's draft; it adds the yogurt
      const b = await P.owner(browser, { hash: '#p=' + V.lac, wait: '#pList .prow' });
      assert.strictEqual(await row(b, I.leche).locator('.step input').inputValue(), '2', 'the other device sees the draft');
      await row(b, I.yogur).locator('.ck input').check();
      await saved(b, 'the second device saved');
      assert.match(draft(), /^2\|/);
      // the first device, still on version 1, changes the milk: the server says «changed»; autosave pauses
      await row(a, I.leche).locator('button[data-a=plus]').click();
      await P.seen(a.locator('#pNotes'), /Este borrador se cambió en otro aparato\. El guardado automático está en pausa\. Usar el del otro aparato Unir/, 'the conflict, in Spanish', 8000);
      assert.match(draft(), /^2\|/, 'the other device\'s draft is not overwritten');
      await a.locator('#pNotes button', { hasText: 'Unir' }).click();
      await saved(a, 'the merge saved');
      assert.strictEqual(linesOf(), [P.vi(I.leche) + ':3', P.vi(I.yogur) + ':1'].sort().join(','), 'the union, the larger quantity of each');
      assert.match(draft(), /^3\|/);
      // the second device now has the stale one; it takes the other device's draft
      await row(b, I.natilla).locator('.ck input').check();
      await P.seen(b.locator('#pNotes'), /Usar el del otro aparato/, 'the second device is told', 8000);
      await b.locator('#pNotes button', { hasText: 'Usar el del otro aparato' }).click();
      assert.strictEqual(await row(b, I.leche).locator('.step input').inputValue(), '3');
      assert.strictEqual(await row(b, I.natilla).locator('.ck input').isChecked(), false, 'its own change is dropped');
      for (const pg of [a, b]) { assert.deepStrictEqual(pg.errors, []); assert.deepStrictEqual(pg.apiErrors, []); }
    }
  },
  {
    name: 'two devices on one draft: when the other device already made the order, or changed the draft, «Crear pedido» waits for the choice; never a second order of the same things',
    run: async ({ browser }) => {
      P.seed();
      const orders = () => sql(`select count(*) from purchase_orders where vendor_id = '${V.lac}' and status <> 'cancelled'`);
      const n0 = orders();
      const a = await P.owner(browser, { hash: '#p=' + V.lac, wait: '#pList .prow' });
      await row(a, I.leche).locator('.ck input').check();
      await saved(a);
      const b = await P.owner(browser, { hash: '#p=' + V.lac, wait: '#pList .prow' });
      assert.strictEqual(await row(b, I.leche).locator('.ck input').isChecked(), true, 'the other device has the draft');
      // A makes the order; B, still showing the draft, ticks the yogurt
      await a.click('#pCreate');
      await a.waitForSelector('#orderDoc', { timeout: 10000 });
      assert.strictEqual(orders(), String(Number(n0) + 1));
      await row(b, I.yogur).locator('.ck input').check();
      await P.seen(b.locator('#pNotes'), /Este borrador ya se convirtió en un pedido/, 'B is told the draft became an order', 8000);
      assert.strictEqual(await b.locator('#pCreate').isDisabled(), true, '«Crear pedido» waits for the choice');
      assert.strictEqual(orders(), String(Number(n0) + 1), 'no second order');
      await b.locator('#pNotes button', { hasText: 'Empezar otro borrador con lo marcado' }).click();
      await saved(b, 'B\'s new draft saved');
      assert.strictEqual(await b.locator('#pCreate').isDisabled(), false, 'the choice made: «Crear pedido» again');
      // A opens the supplier again and changes the new draft; B, on the older version, ticks more and taps at once
      await P.nav(a, '#p=' + V.lac, '#pList .prow');
      await row(a, I.queso).locator('.ck input').check();
      await saved(a, 'A changed the new draft');
      await row(b, I.natilla).locator('.ck input').check();
      await b.click('#pCreate');
      await P.seen(b.locator('#pNotes'), /Este borrador se cambió en otro aparato/, 'B is told the draft changed elsewhere', 8000);
      assert.strictEqual(orders(), String(Number(n0) + 1), 'still no second order from a draft in conflict');
      assert.strictEqual(await b.locator('#pCreate').isDisabled(), true);
      await b.locator('#pNotes button', { hasText: 'Unir' }).click();
      await saved(b, 'the union saved');
      await b.click('#pCreate');
      await b.waitForSelector('#orderDoc', { timeout: 10000 });
      assert.strictEqual(orders(), String(Number(n0) + 2), 'one order from the union');
      assert.strictEqual(sql(`select count(*) from purchase_drafts where vendor_id = '${V.lac}' and status = 'open'`), '0', 'the draft it used is closed');
      for (const pg of [a, b]) assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'the answer of «Crear pedido» is lost: the supplier opened again with other ticks makes a new order (the old id is not taken for a «repeat»), and says which order was already made',
    run: async ({ browser }) => {
      P.seed();
      const orders = () => sql(`select count(*) from purchase_orders where vendor_id = '${V.lac}' and status <> 'cancelled'`);
      const n0 = Number(orders());
      const a = await P.owner(browser, { hash: '#p=' + V.lac, wait: '#pList .prow' });
      await row(a, I.leche).locator('.ck input').check();
      await saved(a);
      await a.route('**/rest/v1/rpc/proveedor_pedido_crear', async (route) => { await route.fetch(); await route.abort('connectionreset'); }, { times: 1 });
      await a.click('#pCreate');
      await until(() => Number(orders()) === n0 + 1, 10000, 'the order is made on the server');
      const first = sql(`select po_number from purchase_orders where vendor_id = '${V.lac}' order by created_at desc limit 1`);
      await P.seen(a.locator('#pErr'), /.+/, 'the tablet could not confirm it', 8000);
      // later: the supplier opened again, the yogurt ticked
      await a.reload({ waitUntil: 'domcontentloaded' });
      await a.waitForSelector('#pList .prow', { timeout: 15000 });
      await row(a, I.yogur).locator('.ck input').check();
      await saved(a, 'the new draft saved');
      await a.click('#pCreate');
      await P.seen(a.locator('#pErr'), new RegExp('Este aparato ya había hecho el pedido Nº ' + first + '\\. Lo marcado ahora es un pedido nuevo'), 'told which order was already made', 8000);
      assert.strictEqual(Number(orders()), n0 + 1, 'nothing taken as a «repeat», nothing made twice');
      await a.click('#pCreate');
      await a.waitForSelector('#orderDoc', { timeout: 10000 });
      assert.strictEqual(Number(orders()), n0 + 2, 'the new ticks are a new order');
      assert.match(await text(a.locator('#orderDoc')), /Yogur/);
      assert.deepStrictEqual(a.errors, []);
    }
  },
  {
    name: 'switching apps right after a tick (the page hidden while its save waits): no false «changed», the draft keeps saving, and the order uses it',
    run: async ({ browser }) => {
      P.seed();
      const a = await P.owner(browser, { hash: '#p=' + V.lac, wait: '#pList .prow' });
      const hide = (h) => a.evaluate((hidden) => {
        Object.defineProperty(document, 'hidden', { configurable: true, get: () => hidden });
        Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => (hidden ? 'hidden' : 'visible') });
        document.dispatchEvent(new Event('visibilitychange'));
      }, h);
      await row(a, I.leche).locator('.ck input').check();
      await hide(true); await a.waitForTimeout(150); await hide(false);       /* WhatsApp for a moment, within the 1.2 s */
      await saved(a, 'the draft saved');
      await a.waitForTimeout(1500);                                          /* the debounced save fires too */
      assert.doesNotMatch(await text(a.locator('#pNotes')), /se cambió en otro aparato/, 'no conflict with itself');
      await row(a, I.yogur).locator('.ck input').check();
      await saved(a, 'it keeps saving');
      assert.strictEqual(linesOf(), [P.vi(I.leche) + ':1', P.vi(I.yogur) + ':1'].sort().join(','), 'the server has both ticks');
      await a.click('#pCreate');
      await a.waitForSelector('#orderDoc', { timeout: 10000 });
      assert.strictEqual(sql(`select count(*) from purchase_drafts where vendor_id = '${V.lac}' and status = 'open'`), '0', 'the order used the draft');
      await P.nav(a, '#p=' + V.lac, '#pList .prow');
      assert.strictEqual(await row(a, I.leche).locator('.ck input').isChecked(), false, 'reopened: nothing ticked again');
      assert.deepStrictEqual(a.errors, []);
    }
  },
  {
    name: 'a ticked product retired from the catalog (or its inventory item switched off) leaves the draft with a notice; the order goes with the rest, never blocked by a line nobody can see',
    run: async ({ browser }) => {
      P.seed();
      const a = await P.owner(browser, { hash: '#p=' + V.lac, wait: '#pList .prow' });
      await row(a, I.leche).locator('.ck input').check();
      await row(a, I.natilla).locator('.ck input').check();
      await row(a, I.yogur).locator('.ck input').check();
      await saved(a);
      // another device retires the natilla; this one opens the supplier again
      P.asOwner(`select public.proveedor_producto_guardar('{"id":"${P.vi(I.natilla)}","active":false}')`);
      await a.reload({ waitUntil: 'domcontentloaded' });
      await a.waitForSelector('#pList .prow', { timeout: 15000 });
      await P.seen(a.locator('#pNotes'), /Se quitó de este pedido.*Natilla/, 'the notice names it', 8000);
      await P.seen(a.locator('#pSum'), /^2 productos/, 'the bar counts what can be ordered', 3000);
      await saved(a, 'the draft saved without it');
      assert.strictEqual(linesOf(), [P.vi(I.leche) + ':1', P.vi(I.yogur) + ':1'].sort().join(','), 'the server draft without it (a reload does not bring it back)');
      // the yogurt's inventory item switched off a moment before «Crear pedido»
      sql(`update stock_items set active = false where id = '${I.yogur}'`);
      await a.click('#pCreate');
      await P.seen(a.locator('#pErr'), /Un producto ya no se puede pedir y se quitó del pedido/, 'said, never «reload»', 8000);
      await P.seen(a.locator('#pSum'), /^1 producto/, 'one left', 3000);
      await a.click('#pCreate');
      await a.waitForSelector('#orderDoc', { timeout: 10000 });
      assert.strictEqual(sql(`select count(*) from purchase_lines l join purchase_orders o on o.id = l.po_id where o.vendor_id = '${V.lac}' and o.created_at > now() - interval '1 minute'`), '1',
                         'the order with the milk only');
      assert.deepStrictEqual(a.errors, []);
    }
  },
  {
    name: 'on open: unsaved changes on the same version win; a newer server draft wins and the local changes are offered (Ver · Descartar)',
    run: async ({ browser, setOffline }) => {
      P.seed();
      const a = await P.owner(browser, { hash: '#p=' + V.lac, wait: '#pList .prow' });
      await row(a, I.leche).locator('.step input').fill('2');
      await saved(a);
      // no internet: the change stays on this device
      setOffline(true);
      await row(a, I.leche).locator('.step input').fill('5');
      await P.seen(a.locator('#pStatus'), /^Sin conexión: guardado en este aparato$/, 'saved on this device only', 10000);
      assert.match(draft(), /^1\|.*"packs": 2/, 'the server still has 2');
      setOffline(false);
      await a.reload({ waitUntil: 'domcontentloaded' });
      await a.waitForSelector('#pList .prow');
      assert.strictEqual(await row(a, I.leche).locator('.step input').inputValue(), '5', 'the unsaved change on the same version wins');
      await saved(a, 'and goes to the server');
      assert.match(draft(), /^2\|.*"packs": 5/);
      // a dirty copy on an older version: the server's newer draft wins, the local changes are offered
      await a.evaluate((k) => { const d = JSON.parse(localStorage.getItem(k)); d.base_version = 1; d.dirty = true; d.lines = d.lines.concat([]); d.note = 'de este aparato'; localStorage.setItem(k, JSON.stringify(d)); }, 'hg-prov-draft:' + V.lac);
      await a.reload({ waitUntil: 'domcontentloaded' });
      await a.waitForSelector('#pList .prow');
      await P.seen(a.locator('#pNotes'), /^Había cambios sin guardar en este aparato Ver Descartar$/, 'the local changes offered', 5000);
      assert.strictEqual(await a.inputValue('#pNote'), '', 'the server\'s note');
      await a.locator('#pNotes button', { hasText: 'Ver' }).click();
      await P.seen(a.locator('#pNotes'), /Leche entera · 5 Nota: de este aparato Usar estos Descartar/, 'what they were', 3000);
      await a.locator('#pNotes button', { hasText: 'Usar estos' }).click();
      assert.strictEqual(await a.inputValue('#pNote'), 'de este aparato');
      await saved(a, 'the local changes taken and saved');
      assert.match(draft(), /^3\|.*\|de este aparato$/);
      assert.deepStrictEqual(a.errors, []);
    }
  },
  {
    name: 'a draft save whose answer is lost, then one more change on the same device (an untick): that save is recognised, never «changed on another device», and what was unticked stays off',
    run: async ({ browser }) => {
      P.seed();
      const a = await P.owner(browser, { hash: '#p=' + V.lac, wait: '#pList .prow' });
      await row(a, I.leche).locator('.ck input').check();
      await saved(a, 'v1 saved');
      // the next save reaches the server but its answer is lost (café Wi-Fi, or the tablet suspending the page)
      await a.route('**/rest/v1/rpc/proveedor_borrador_guardar', async (route) => { await route.fetch(); await route.abort('connectionreset'); }, { times: 1 });
      await row(a, I.yogur).locator('.ck input').check();
      await P.seen(a.locator('#pStatus'), /conexi/i, 'the lost answer reads as no connection', 8000);
      await until(() => linesOf().includes(P.vi(I.yogur)), 5000, 'that save did reach the server');
      await row(a, I.yogur).locator('.ck input').uncheck();
      await saved(a, 'the untick saved on the version that lost save made');
      assert.strictEqual(await text(a.locator('#pNotes')), '', 'no conflict with itself');
      assert.strictEqual(await a.locator('#pCreate').isDisabled(), false, '«Crear pedido» stays on');
      assert.strictEqual(await row(a, I.yogur).locator('.ck input').isChecked(), false, 'the yogurt stays unticked');
      assert.ok(linesOf().includes(P.vi(I.leche)) && !linesOf().includes(P.vi(I.yogur)), 'the server holds what is ticked now: ' + linesOf());
      assert.strictEqual(draft().split('|')[0], '3', 'one version on from the lost save');
      assert.deepStrictEqual(a.errors, []);
    }
  },
  {
    name: '«Repetir último pedido» and «Duplicar» tick an order\'s lines (one confirmation); a line no longer in the catalog is offered «Añadir al catálogo»',
    run: async ({ browser }) => {
      P.seed();
      P.order(V.lac, [{ vi: P.vi(I.leche), packs: 2 }, { vi: P.vi(I.natilla), packs: 1 }, { vi: P.vi(I.crema), packs: 3 }], { ago: '3 days' });
      const no = sql(`select po_number from purchase_orders`);
      sql(`update vendor_items set active = false where id = '${P.vi(I.natilla)}'`);
      const pg = await P.owner(browser, { hash: '#p=' + V.lac, wait: '#pList .prow' });
      // habitual first (ordered in the last 120 days), then A–Z
      const order = await pg.locator('#pList .prow .nm').allInnerTexts();
      assert.deepStrictEqual(order.map((t) => t.replace(/\s*\(.*$|\s+(Bajo|Agotado)$/g, '').trim()), ['Crema dulce', 'Leche entera', 'Mantequilla', 'Queso turrialba', 'Yogur natural']);
      await row(pg, I.yogur).locator('.ck input').check();
      const asked = []; pg.onDialog = async (d) => { asked.push(d.message()); await d.accept(); };
      await pg.click('#pRepeat');
      await P.toasted(pg, new RegExp('^2 productos marcados del pedido Nº ' + no + '$'), 'ticked from the last order');
      assert.deepStrictEqual(asked, ['Esto reemplaza lo marcado. ¿Seguir?'], 'one confirmation, because something was ticked');
      assert.strictEqual(await row(pg, I.yogur).locator('.ck input').isChecked(), false, 'the ticks were replaced');
      assert.strictEqual(await row(pg, I.leche).locator('.step input').inputValue(), '2');
      assert.strictEqual(await row(pg, I.crema).locator('.step input').inputValue(), '3');
      await P.seen(pg.locator('#pUnmatched'), /^Todavía no están en el catálogo de este proveedor: Natilla · 1 × paquete de 12 Añadir al catálogo$/, 'the retired line is not dropped', 3000);
      await pg.locator('#pUnmatched button', { hasText: 'Añadir al catálogo' }).click();
      assert.strictEqual(await pg.inputValue('#npPack'), 'paquete de 12', 'prefilled');
      assert.strictEqual(await pg.inputValue('#npPrice'), '6000');
      await pg.click('#npCancel');
      // «Duplicar» from the Orders tab: the same, without asking when nothing is ticked
      await row(pg, I.leche).locator('.ck input').uncheck();
      await row(pg, I.crema).locator('.ck input').uncheck();
      await pg.locator('.ftabs a', { hasText: 'Pedidos' }).click();
      await pg.locator(`#fTab .orow`).first().locator('button', { hasText: 'Duplicar' }).click();
      await P.toasted(pg, new RegExp('^2 productos marcados del pedido Nº ' + no + '$'), 'duplicated');
      assert.strictEqual(asked.length, 1, 'no confirmation: nothing was ticked');
      await P.seen(pg.locator('#pSum'), /^2 productos · Total estimado ₡26 700$/, '2 × 10 200 + 3 × 2 100', 3000);
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, []);
    }
  },
  {
    name: 'an order with the keyboard only: Tab to the product, Space ticks, type the quantity, Enter on «Crear pedido»',
    run: async ({ browser }) => {
      P.seed();
      const pg = await P.owner(browser, { hash: '#p=' + V.lac, wait: '#pList .prow' });
      await pg.focus('#pSearch');
      await pg.keyboard.type('leche');
      const ck = row(pg, I.leche).locator('.ck input');
      for (let i = 0; i < 8 && !(await ck.evaluate((e) => e === document.activeElement)); i++) await pg.keyboard.press('Tab');
      assert.ok(await ck.evaluate((e) => e === document.activeElement), 'the checkbox is reached with Tab');
      await pg.keyboard.press('Space');
      assert.strictEqual(await ck.isChecked(), true);
      await pg.keyboard.press('Tab');   // «−»
      await pg.keyboard.press('Tab');   // the quantity
      assert.ok(await row(pg, I.leche).locator('.step input').evaluate((e) => e === document.activeElement), 'the quantity box is next');
      await pg.keyboard.press('Control+A');
      await pg.keyboard.type('4');
      const create = pg.locator('#pCreate');
      for (let i = 0; i < 12 && !(await create.evaluate((e) => e === document.activeElement)); i++) await pg.keyboard.press('Tab');
      assert.ok(await create.evaluate((e) => e === document.activeElement), '«Crear pedido» is reached with Tab');
      await pg.keyboard.press('Enter');
      await pg.waitForSelector('#orderDoc', { timeout: 10000 });
      assert.strictEqual(sql(`select string_agg(trim_scale(packs) || ':' || trim_scale(qty), ',') from purchase_lines`), '4:48');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'speed: a habitual order of 6 products, from opening the supplier\'s file to the order document (timed, taps counted)',
    run: async ({ browser }) => {
      P.seed();
      P.order(V.lac, [I.leche, I.yogur, I.queso, I.mant, I.crema, I.natilla].map((it, k) => ({ vi: P.vi(it), packs: k + 1 })), { ago: '7 days' });
      sql(`update purchase_orders set status = 'received', received_at = now() - interval '6 days'`);
      const pg = await P.owner(browser, { wait: '#hubVendors .vcard' });
      let taps = 0;
      const t0 = await pg.evaluate(() => performance.now());
      await pg.click(`#hubVendors .vcard[data-vendor="${V.lac}"]`); taps++;
      await pg.click('#pRepeat'); taps++;
      await P.seen(pg.locator('#pSum'), /^6 productos · /, 'six ticked', 5000);
      await pg.click('#pCreate'); taps++;
      await pg.waitForSelector('#orderDoc', { timeout: 10000 });
      const ms = Math.round((await pg.evaluate(() => performance.now())) - t0);
      console.log(`        speed · habitual order of 6 products: ${taps} taps, ${ms} ms from opening the file to the document`);
      assert.strictEqual(sql(`select count(*) from purchase_lines l join purchase_orders o on o.id = l.po_id where o.status = 'sent'`), '6');
      assert.ok(taps <= 3, 'three taps');
      assert.ok(ms < 6000, 'under 6 s on the test machine: ' + ms);
      assert.deepStrictEqual(pg.errors, []);
    }
  }
];
