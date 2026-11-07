/* Proveedores (D-067, migrations 0039/0040) · the hub: a manager opens the owner areas on the café tablet (access.js's
   gate); alerts on top; the suppliers with their badges, search and chips; add, edit, SINPE, deactivate; the low-stock
   alerts on Home and in Inventario open the preferred supplier's file with the item highlighted and NOT ticked until
   tapped; «Asociar proveedor» for an item without supplier (the suppliers whose catalog has it come with the alert: no
   read per supplier); Inventario's old Orders / Vendors tabs lead here; Productos (preferred, usual price, retire); an
   old page's order without supplier gets one («Sin proveedor · Asignar»). */
'use strict';
const assert = require('assert');
const { page, goto, until, sql, STAFF, PINS } = require('../lib');
const P = require('../prov');
const { V, I, VI, text, plain } = P;

module.exports.tests = [
  {
    name: 'café tablet + a manager PIN: alerts on top, suppliers with badges, search and chips, what is to be received (Spanish)',
    run: async ({ browser }) => {
      P.seed();
      const po = P.order(V.lac, [{ vi: P.vi(I.leche), packs: 2 }, { vi: P.vi(I.yogur), packs: 1 }]);
      const no = sql(`select po_number from purchase_orders where id = '${po}'`);
      const d = P.asOwner(`select public.proveedor_borrador_guardar('${V.pan}', '[{"vendor_item_id":"${P.vi(I.croissant, V.pan)}","packs":2}]', null, 0)`);
      assert.strictEqual(d.ok, true, JSON.stringify(d));
      const pg = await P.cafeManager(browser);
      await P.seen(pg.locator('#hubAlerts h2'), /Antes de que se acabe/, 'the alerts, in Spanish', 8000);
      const alerts = await text(pg.locator('#hubAlerts'));
      assert.match(alerts, /Leche entera Inventario bajo · Lácteos Monteverde Ya pedido: 2 × caja de 12 \(Nº /, alerts);
      assert.match(alerts, new RegExp('\\(Nº ' + no + '\\)'));
      assert.match(alerts, /Pan baguette Agotado · Panadería Sol/);
      assert.match(alerts, /Azúcar Inventario bajo · Sin proveedor/);
      // the supplier cards and their badges
      const lac = pg.locator(`#hubVendors .vcard[data-vendor="${V.lac}"]`), pan = pg.locator(`#hubVendors .vcard[data-vendor="${V.pan}"]`);
      assert.match(await text(lac), /^Lácteos Monteverde Rosa Jiménez · 2645 1111 .*1 por recibir/);
      assert.match(await text(pan), /Borrador/);
      assert.doesNotMatch(await text(pan), /por recibir/);
      // search: by name, by contact; nothing found
      await pg.fill('#hubSearch', 'pana');
      await until(async () => (await pg.locator('#hubVendors .vcard').count()) === 1, 3000, 'one supplier found');
      assert.strictEqual(await pg.locator('#hubVendors .vcard').getAttribute('data-vendor'), V.pan);
      await pg.fill('#hubSearch', 'rosa');
      await until(async () => (await pg.locator('#hubVendors .vcard').getAttribute('data-vendor')) === V.lac, 3000, 'found by the contact person');
      await pg.fill('#hubSearch', 'xyz');
      await P.seen(pg.locator('#hubVendors'), /Ningún proveedor con ese nombre/, 'nothing found, in Spanish', 3000);
      await pg.fill('#hubSearch', '');
      await pg.click('.chip[data-chip=receive]');
      await until(async () => (await pg.locator('#hubVendors .vcard').count()) === 1, 3000, 'only the supplier with something to receive');
      assert.strictEqual(await pg.locator('#hubVendors .vcard').getAttribute('data-vendor'), V.lac);
      // everything to receive
      const rec = await text(pg.locator('#hubReceive'));
      assert.match(rec, new RegExp('Pedido Nº ' + no + ' Lácteos Monteverde · enviado .* · 2 de 2 líneas pendientes Recibir Abrir'), rec);
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, []);
      assert.strictEqual(pg.supabaseHits, 0);
    }
  },
  {
    name: 'the hub\'s six alerts are the most urgent ones (out of stock first), grouped by supplier in that order; «Ver todas» shows the rest',
    run: async ({ browser }) => {
      P.seed();
      // six low fruits from Finca La Fresa (a supplier that sorts before Panadería Sol): the out-of-stock bread still shows
      sql(`insert into stock_items (id, name, category, unit, pack_qty, cost_per_pack, avg_cost, vendor_id, on_hand, reorder_point, par_level)
           select ('5a000000-0000-4000-8000-0000000c' || lpad(g::text, 4, '0'))::uuid, 'Fruta ' || g, 'produce', 'kg', 1, 1000, 1000, '${V.fin}', 1, 5, 20
             from generate_series(1, 6) g`);
      const server = P.asOwner(`select public.proveedores_alertas()`).items;
      assert.strictEqual(server[0].item_id, I.pan, 'the server sends the out-of-stock bread first');
      const pg = await P.owner(browser);
      await P.seen(pg.locator('#hubAlerts h2'), /Antes de que se acabe 9$/, 'nine alerts', 8000);
      const cards = () => pg.locator('#hubAlerts a.acard').evaluateAll((l) => l.map((a) => a.getAttribute('data-item')));
      const shown = await cards();
      assert.deepStrictEqual(shown.slice().sort(), server.slice(0, 6).map((i) => i.item_id).sort(), 'the six most urgent, in the server\'s order');
      assert.strictEqual(shown[0], I.pan, 'the out-of-stock bread is the first card, not behind «Ver todas»');
      assert.deepStrictEqual(await pg.locator('#hubAlerts .agroup').allTextContents(), ['Panadería Sol', 'Sin proveedor', 'Finca La Fresa'], 'the group of the most urgent alert first');
      assert.match(await text(pg.locator(`#hubAlerts a.acard[data-item="${I.pan}"]`)), /^Pan baguette Agotado · Panadería Sol$/);
      // «Ver todas (9)»: every alert, still grouped in the order of each supplier's most urgent one
      await pg.locator('#hubAlerts button', { hasText: 'Ver todas (9)' }).click();
      await until(async () => (await cards()).length === 9, 5000, 'all nine alerts');
      assert.deepStrictEqual(await pg.locator('#hubAlerts .agroup').allTextContents(), ['Panadería Sol', 'Sin proveedor', 'Finca La Fresa', 'Lácteos Monteverde']);
      const all = await cards();
      assert.deepStrictEqual(all.slice(0, 2), [I.pan, I.azucar]);
      assert.strictEqual(all[8], I.leche, 'Lácteos (its milk ranks last) comes last');
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, []);
    }
  },
  {
    name: 'add, edit (SINPE by the owner) and deactivate a supplier; a repeated save adds one; a duplicate name is refused (English)',
    run: async ({ browser }) => {
      P.seed();
      const pg = await P.owner(browser, { lang: 'en' });
      await pg.click('a[href="#nuevo"]');
      await pg.waitForSelector('#newVendorForm');
      await pg.fill('#nvName', 'Lácteos monteverde ');
      await pg.click('#nvGo');
      await P.seen(pg.locator('#nvErr'), /There is already a supplier with that name\. Open that supplier/, 'the duplicate name refused', 8000);
      await pg.fill('#nvName', 'Frutas Don Beto');
      await pg.fill('#nvContact', 'Beto');
      await pg.fill('#nvPhone', '8811 2233');
      // a double tap saves one supplier (the request id is the new supplier's id)
      await pg.evaluate(() => { const b = document.getElementById('nvGo'); b.click(); b.click(); });
      await until(async () => /&t=productos$/.test(pg.url()), 8000, 'the new supplier opens on its products');
      assert.strictEqual(sql(`select count(*) || '|' || string_agg(contact_name || ' ' || phone, ',') from vendors where name = 'Frutas Don Beto'`), '1|Beto 8811 2233');
      const id = sql(`select id from vendors where name = 'Frutas Don Beto'`);
      await pg.waitForSelector('#ficha');
      // edit: the phone and the SINPE (the owner with the phone code may change it)
      await pg.click('#fEditBtn');
      await pg.fill('#vfPhone', '8811 0000');
      await pg.fill('#vfSinpe', '8811 0000 Beto Rojas');
      await pg.click('#vendorForm button[type=submit]');
      await P.toasted(pg, /Supplier saved/, 'saved');
      assert.strictEqual(sql(`select v.phone || '|' || p.sinpe from vendors v join vendor_pay_info p on p.vendor_id = v.id where v.id = '${id}'`), '8811 0000|8811 0000 Beto Rojas');
      assert.strictEqual(sql(`select count(*) from audit_log where action = 'vendor_sinpe'`), '1', 'the SINPE change is audited');
      await P.seen(pg.locator('#ficha .fhead'), /SINPE: 8811 0000 Beto Rojas SINPE changed on .* by /, 'the SINPE and when it changed', 8000);
      // deactivate: it leaves the active list, stays in the inactive one
      await pg.click('#fEditBtn');
      await pg.locator('#vendorForm button', { hasText: 'Deactivate' }).click();
      await P.toasted(pg, /Supplier deactivated/, 'deactivated');
      assert.strictEqual(sql(`select active from vendors where id = '${id}'`), 'f');
      await goto(pg, '/proveedores#');
      await pg.waitForSelector('#hubVendors .vcard');
      assert.strictEqual(await pg.locator(`#hubVendors .vcard[data-vendor="${id}"]`).count(), 0, 'not among the active ones');
      await pg.click('.chip[data-chip=inactive]');
      await P.seen(pg.locator(`#hubVendors .vcard[data-vendor="${id}"]`), /Frutas Don Beto.*inactive/, 'among the inactive ones', 3000);
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, []);
    }
  },
  {
    name: 'a manager sees the SINPE but cannot change it; the employee view never shows it',
    run: async ({ browser }) => {
      P.seed();
      P.asOwner(`select public.proveedor_guardar('{"id":"${V.lac}","sinpe":"8888 1111 Lácteos MV"}')`);
      const pg = await P.cafeManager(browser, { hash: '#p=' + V.lac });
      await P.seen(pg.locator('#ficha .fhead'), /SINPE: 8888 1111 Lácteos MV/, 'the SINPE shown to a manager', 8000);
      await pg.click('#fEditBtn');
      assert.strictEqual(await pg.locator('#vfSinpe').count(), 0, 'no SINPE box for a manager');
      /* lang.js translates the new form on its next frame */
      await P.seen(pg.locator('#vendorForm'), /Solo el dueño o el contador cambian el SINPE/, 'the hint, in Spanish', 3000);
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'the owner areas opened with the owner\'s PIN on the café tablet: changing a SINPE asks an owner\'s PIN in the call (a wrong one refused and counted), saved under that owner',
    run: async ({ browser }) => {
      P.seed();
      P.asOwner(`select public.proveedor_guardar('{"id":"${V.lac}","sinpe":"8888 1111 Lácteos MV"}')`);
      const pg = await P.cafeManager(browser, { hash: '#p=' + V.lac, who: 'dueno' });
      await P.seen(pg.locator('#ficha .fhead'), /SINPE: 8888 1111 Lácteos MV/, 'the SINPE shown', 8000);
      await pg.click('#fEditBtn');
      await pg.waitForSelector('#vfSinpe');
      assert.strictEqual(await pg.locator('#vfPinBox').isVisible(), false, 'no PIN box while the SINPE is unchanged');
      await pg.fill('#vfSinpe', '8888 0000 Otra cuenta');
      await pg.locator('#vfPinBox').waitFor({ state: 'visible', timeout: 3000 });
      await P.seen(pg.locator('#vfPinBox'), /pide el PIN de un dueño/, 'why the PIN is asked, in Spanish', 3000);
      await until(async () => (await pg.locator('#vfWho option[value]:not([value=""])').count()) > 0, 5000, 'the owners to pick are loaded');
      const owners = await pg.locator('#vfWho option').allTextContents();
      assert.ok(owners.length >= 1 && owners.every((o) => !/Ana|Luis|Marta/.test(o)), 'only owners to pick: ' + owners.join(', '));
      await pg.click('#vendorForm button[type=submit]');
      await P.seen(pg.locator('#vfErr'), /Elija al dueño y escriba el PIN/, 'no PIN typed: nothing sent', 3000);
      assert.strictEqual(sql(`select sinpe from vendor_pay_info where vendor_id = '${V.lac}'`), '8888 1111 Lácteos MV');
      await pg.selectOption('#vfWho', STAFF.dueno);
      await pg.locator('#vfPin').pressSequentially('0000');
      await pg.click('#vendorForm button[type=submit]');
      await P.seen(pg.locator('#vfErr'), /PIN no es correcto/, 'a wrong owner PIN refused', 5000);
      assert.strictEqual(await pg.locator('#vfPin').inputValue(), '', 'the PIN box is cleared after the answer');
      assert.strictEqual(sql(`select failed_pins from staff where id = '${STAFF.dueno}'`), '1', 'the wrong try is counted');
      assert.strictEqual(sql(`select sinpe from vendor_pay_info where vendor_id = '${V.lac}'`), '8888 1111 Lácteos MV', 'nothing changed');
      await pg.locator('#vfPin').pressSequentially(PINS.dueno);
      await pg.click('#vendorForm button[type=submit]');
      await P.toasted(pg, /Proveedor guardado/, 'saved with the owner\'s PIN');
      assert.strictEqual(sql(`select sinpe || ' · ' || updated_by from vendor_pay_info where vendor_id = '${V.lac}'`), '8888 0000 Otra cuenta · Dueño');
      assert.strictEqual(sql(`select manager_id || ' ' || manager_name from audit_log where action = 'vendor_sinpe' order by id desc limit 1`), STAFF.dueno + ' Dueño',
                         'logged under the owner of the PIN');
      assert.strictEqual(sql(`select failed_pins from staff where id = '${STAFF.dueno}'`), '0');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'a low-stock alert on Home and in Inventario opens the preferred supplier\'s file: the item highlighted, not ticked until tapped',
    run: async ({ browser }) => {
      P.seed();
      const pg = await page(browser, { login: 'owner', aal: 'aal2', lang: 'es' });
      P.watchApi(pg);
      await goto(pg, '/home');
      const row = pg.locator(`a.invrow[href="proveedores.html#alerta=${I.leche}"]`);
      await row.waitFor({ timeout: 15000 });
      await row.click();
      await until(async () => pg.url().endsWith(`#p=${V.lac}&item=${I.leche}`), 10000, 'the preferred supplier\'s file, with the item');
      const pin = pg.locator('#pList .prow.pin');
      await pin.waitFor({ timeout: 8000 });
      assert.strictEqual(await pin.getAttribute('data-vi'), P.vi(I.leche));
      assert.strictEqual(await pg.locator('#pList .prow').first().getAttribute('data-vi'), P.vi(I.leche), 'pinned first');
      assert.strictEqual(await pin.locator('.ck input').isChecked(), false, 'not ticked');
      // the suggestion: inventory_stats' suggested quantity (par 72 − on hand 6 = 66 units) in boxes of 12 → 6, shown, not sent
      assert.strictEqual(await pin.locator('.step input').inputValue(), '6');
      assert.match(await text(pg.locator('#pSum')), /^0 productos · Total estimado ₡0$/);
      await pin.locator('.ck input').check();
      await P.seen(pg.locator('#pSum'), /^1 producto · Total estimado ₡61 200$/, 'ticked at the suggestion', 3000);
      // Inventario: «Pedir» on its Today alert row, and its old Orders / Vendors tabs lead to Proveedores
      await goto(pg, '/inventory');
      const pedir = pg.locator(`a[href="proveedores.html#alerta=${I.pan}"]`);
      await pedir.waitFor({ timeout: 15000 });
      assert.strictEqual(await pg.locator('a.tablink[href^="proveedores.html"]').count(), 2, 'the Orders and Vendors tabs are links to Proveedores');
      assert.strictEqual(await pg.locator('#allPoBtn, #poList, #recvModal, #pendCard').count(), 0, 'nothing of the old Orders tab is left');
      await pedir.click();
      await until(async () => pg.url().endsWith(`#p=${V.pan}&item=${I.pan}`), 10000, 'Panadería Sol\'s file, with the bread');
      await pg.locator('#pList .prow.pin').waitFor({ timeout: 8000 });
      assert.strictEqual(await pg.locator('#pList .prow.pin').getAttribute('data-vi'), P.vi(I.pan, V.pan));
      assert.strictEqual(await pg.locator('#pList .prow.pin .ck input').isChecked(), false);
      await goto(pg, '/inventory');
      await pg.locator('a.tablink', { hasText: /^Pedidos$/ }).click();
      await until(async () => /\/proveedores(\.html)?#?$/.test(pg.url()), 10000, 'the Orders tab opens Proveedores');
      await pg.waitForSelector('#hubVendors');
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, []);
    }
  },
  {
    name: 'Productos: another supplier made preferred (the old one is shown); a usual price edited inline; a product retired (history kept)',
    run: async ({ browser }) => {
      P.seed();
      const pg = await P.owner(browser, { hash: '#p=' + V.pan + '&t=productos', wait: '#prTable' });
      const milk = pg.locator(`#prTable tr[data-vi="${VI.lecheMedia}"]`);
      await P.seen(milk, /Leche entera .*Preferido: Lácteos Monteverde .*1 media caja de 6 = 6 unidades ₡5 400 sin IVA/, 'the other supplier is the preferred one', 5000);
      await milk.locator('button', { hasText: 'Hacer preferido' }).click();
      await P.toasted(pg, /^Proveedor preferido guardado$/, 'preferred');
      assert.strictEqual(sql(`select vendor_id from stock_items where id = '${I.leche}'`), V.pan);
      await P.seen(pg.locator(`#prTable tr[data-vi="${VI.lecheMedia}"]`), /Preferido/, 'shown as preferred', 5000);
      // the usual price of the croissant, inline: the authorized way to change a catalog price
      const croissant = P.vi(I.croissant, V.pan), cr = () => pg.locator(`#prTable tr[data-vi="${croissant}"]`);
      await cr().locator('button', { hasText: 'Editar' }).click();
      await pg.waitForSelector('#prodEdit');
      assert.strictEqual(await pg.inputValue('#pePrice'), '9600');
      await pg.fill('#pePrice', '9900');
      await pg.click('#peGo');
      await P.toasted(pg, /^Producto guardado$/, 'saved');
      assert.strictEqual(sql(`select usual_price from vendor_items where id = '${croissant}'`), '9900.00');
      assert.strictEqual(sql(`select count(*) from audit_log where action = 'vendor_item_save'`), '1', 'audited with before/after');
      // retire it: kept, marked retired, no longer offered to order
      const asked = []; pg.onDialog = async (d) => { asked.push(d.message()); await d.accept(); };
      await cr().locator('button', { hasText: 'Retirar' }).click();
      await P.toasted(pg, /^Producto retirado$/, 'retired');
      assert.deepStrictEqual(asked, ['¿Retirar Croissant de este proveedor? Su historial se conserva.']);
      assert.strictEqual(sql(`select active from vendor_items where id = '${croissant}'`), 'f');
      await P.seen(cr(), /retirado .*Reactivar/, 'shown retired', 5000);
      await P.nav(pg, '#p=' + V.pan + '&t=pedir', '#pList .prow');
      assert.strictEqual(await pg.locator(`#pList .prow[data-vi="${croissant}"]`).count(), 0, 'not offered to order');
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, []);
    }
  },
  {
    name: '«Asociar proveedor»: the suppliers that carry the item come with the alert (no read per supplier); one becomes preferred',
    run: async ({ browser }) => {
      P.seed();
      const pg = await P.owner(browser);
      const fichas = []; pg.on('request', (r) => { if (/rpc\/proveedor_ficha/.test(r.url())) fichas.push(r.url()); });
      await pg.locator(`#hubAlerts a.acard[data-item="${I.azucar}"]`).click();
      await P.seen(pg.locator('#main'), /Asociar proveedor · Azúcar/, 'the link-a-supplier page', 8000);
      const body = await text(pg.locator('#main'));
      assert.match(body, /Este artículo todavía no tiene proveedor preferido/);
      assert.match(body, /Lo tienen en su catálogo Panadería Sol saco de 5 kg · 5 kg · ₡4 300 Hacer preferido Otros proveedores Finca La Fresa Añadirlo a este catálogo Elegir Lácteos Monteverde Añadirlo a este catálogo Elegir$/i, body);
      assert.deepStrictEqual(fichas, [], 'no supplier file was read to find who carries it');
      await pg.locator('#main .orow', { hasText: 'Panadería Sol' }).locator('button').click();
      await until(async () => pg.url().endsWith(`#p=${V.pan}&item=${I.azucar}`), 10000, 'Panadería Sol\'s file with the sugar');
      assert.strictEqual(sql(`select vendor_id from stock_items where id = '${I.azucar}'`), V.pan, 'the preferred supplier saved');
      await P.seen(pg.locator('#ficha .fhead'), /^Panadería Sol Don Mario 2645 2222 1 día para entregar Editar$/, 'its header (one day, singular)', 5000);
      await pg.locator('#pList .prow.pin').waitFor({ timeout: 8000 });
      assert.strictEqual(await pg.locator('#pList .prow.pin').getAttribute('data-vi'), VI.azucarSaco);
      // a supplier without it in its catalog: its Products open with the new product prefilled
      sql(`update stock_items set vendor_id = null where id = '${I.azucar}'`);
      await goto(pg, '/proveedores#alerta=' + I.azucar);
      await pg.reload({ waitUntil: 'domcontentloaded' });   /* the change above was made behind the page's back */
      await P.seen(pg.locator('#main'), /Asociar proveedor · Azúcar/, 'the link-a-supplier page again', 8000);
      await pg.locator('#main .orow', { hasText: 'Lácteos Monteverde' }).locator('button').click();
      await pg.waitForSelector('#productForm');
      assert.match(await text(pg.locator('#npChosen')), /Artículo del inventario: Azúcar/);
      assert.strictEqual(await pg.locator('#npPref').isChecked(), true);
      await pg.fill('#npPack', 'bolsa de 2 kg'); await pg.fill('#npQty', '2'); await pg.fill('#npPrice', '1900');
      await pg.click('#npGo');
      await until(() => sql(`select vendor_id from stock_items where id = '${I.azucar}'`) === V.lac, 8000, 'the new row is the preferred one');
      assert.strictEqual(sql(`select pack_label || '|' || pack_qty || '|' || usual_price from vendor_items where vendor_id = '${V.lac}' and item_id = '${I.azucar}'`), 'bolsa de 2 kg|2|1900.00');
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, []);
    }
  },
  {
    name: 'an order the old page made without a supplier: «Sin proveedor · Asignar» on the hub gives it one',
    run: async ({ browser }) => {
      P.seed();
      sql(`insert into purchase_orders (id, vendor_id, status) values ('9a000000-0000-4000-8000-00000000a499', null, 'sent');
           insert into purchase_lines (po_id, item_id, packs, qty, unit_cost) values ('9a000000-0000-4000-8000-00000000a499', '${I.queso}', 2, 2, 5200)`);
      const pg = await P.owner(browser);
      const row = pg.locator('#hubReceive .orow');
      await P.seen(row, /^Pedido Nº \d+ Sin proveedor · .*Sin proveedor · Asignar Recibir Abrir$/, 'the order without supplier', 5000);
      await row.locator('button', { hasText: 'Sin proveedor · Asignar' }).click();
      await row.locator('select').selectOption(V.lac);
      await row.locator('button', { hasText: /^Asignar$/ }).click();
      await P.toasted(pg, /^Proveedor asignado$/, 'assigned');
      assert.strictEqual(sql(`select vendor_id from purchase_orders where id = '9a000000-0000-4000-8000-00000000a499'`), V.lac);
      await P.seen(pg.locator('#hubReceive .orow'), /Lácteos Monteverde/, 'now with its supplier', 5000);
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, []);
    }
  }
];
