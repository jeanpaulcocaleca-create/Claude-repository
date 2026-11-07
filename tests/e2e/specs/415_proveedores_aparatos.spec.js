/* Proveedores (D-067) · devices: without internet «Sin conexión…» and nothing is lost (a receipt and an order go once
   the connection is back); an expired sign-in shows the login view and the typed form comes back afterwards (never the
   PIN); when the unlock ends (the pill's Lock) every piece of management data leaves the screen; a phone (360×740), a
   tablet (820×1180) and a desktop (1280×860): no sideways scroll, 44 px targets, and on the two touch screens the key
   actions tapped (a tick, the stepper's «+», a keypad digit, «Estoy en turno aquí» on the PIN pad, «Todo recibido
   correctamente»); the idle sign-out only for the owner with the phone code (never while a form is dirty, never on the
   café tablet). */
'use strict';
const assert = require('assert');
const { page, goto, until, settle, sql, STAFF, PINS } = require('../lib');
const P = require('../prov');
const { V, I, text } = P;

async function device(browser, size, opts) {
  const touch = size.width < 1024;
  const ctx = await browser.newContext({ viewport: size, hasTouch: touch, isMobile: touch, locale: 'es-CR', timezoneId: 'America/Costa_Rica' });
  return P.watchApi(await page(browser, Object.assign({ context: ctx, lang: 'es' }, opts)));
}

module.exports.tests = [
  {
    name: 'without internet: the receipt and the order say «Sin conexión…», keep what was typed, and go once the connection is back',
    run: async ({ browser, setOffline }) => {
      P.seed(); P.clockIn('luis');
      const o = P.create(V.lac, [{ vi: P.vi(I.leche), packs: 2 }]);
      const pg = await P.employee(browser, 'luis', { hash: '#recibir=' + o.id });
      await pg.waitForSelector('#recvCard');
      await pg.fill('#rq0', '1');
      await pg.fill('#rNote', 'una caja mojada');
      setOffline(true);
      await pg.click('#recvGo');
      await P.seen(pg.locator('#rErr'), /^Sin conexión: no se guardó\. Intente de nuevo\.$/, 'offline, in Spanish', 10000);
      assert.strictEqual(await pg.inputValue('#rq0'), '1', 'the typed quantity is kept');
      assert.strictEqual(sql(`select count(*) from purchase_receipts`), '0');
      // a reload while offline keeps the form on this device (localStorage), with its receipt id
      const saved = JSON.parse(await pg.evaluate((k) => localStorage.getItem(k), 'hg-prov-recv:' + o.id));
      assert.strictEqual(saved.note, 'una caja mojada');
      setOffline(false);
      await pg.reload({ waitUntil: 'domcontentloaded' });
      await pg.waitForSelector('#recvCard', { timeout: 15000 });
      assert.strictEqual(await pg.inputValue('#rq0'), '1', 'back after a reload');
      assert.strictEqual(await pg.inputValue('#rNote'), 'una caja mojada');
      await pg.click('#recvGo');
      await pg.waitForSelector('#recvDone', { timeout: 10000 });
      assert.strictEqual(sql(`select count(*) || '|' || string_agg(id::text, ',') || '|' || string_agg(note, ',') from purchase_receipts`), `1|${saved.receipt_id}|una caja mojada`, 'booked once, with the receipt id kept from before');
      // an order created without internet: the request id waits for the connection
      const m = await P.owner(browser, { hash: '#p=' + V.lac, wait: '#pList .prow' });
      await m.locator(`#pList .prow[data-vi="${P.vi(I.yogur)}"] .ck input`).check();
      await P.seen(m.locator('#pStatus'), /^Borrador guardado/, 'the draft saved', 8000);
      setOffline(true);
      await m.click('#pCreate');
      await P.seen(m.locator('#pErr'), /^Sin conexión: no se guardó\. Intente de nuevo\.$/, 'the order waits', 15000);
      assert.strictEqual(await m.locator(`#pList .prow[data-vi="${P.vi(I.yogur)}"] .ck input`).isChecked(), true, 'the ticks are kept');
      setOffline(false);
      await m.click('#pCreate');
      await m.waitForSelector('#orderDoc', { timeout: 10000 });
      assert.strictEqual(sql(`select count(*) from purchase_orders where vendor_id = '${V.lac}'`), '2', 'one new order');
      for (const p of [pg, m]) assert.deepStrictEqual(p.errors, []);
    }
  },
  {
    name: 'an expired sign-in: the login view; after signing in and opening the owner areas the typed payment is back (never its PIN)',
    run: async ({ browser }) => {
      P.seed();
      const o = P.create(V.lac, [{ vi: P.vi(I.leche), packs: 2 }]);
      P.receive(o.id, [{ line: P.lineOf(o.id, I.leche), rest: true }]);
      const pg = await P.cafeManager(browser, { hash: '#pedido=' + o.id, wait: '#orderDoc' });
      await pg.click('#docPay');
      await pg.waitForSelector('#payModal:not([hidden])');
      await pg.fill('#payAmt', '7000');
      await pg.fill('#payRef', 'SNP-4455');
      await pg.fill('#payPin', PINS.ana);
      // the sign-in ends (another device signed this login out, or it expired): the next call is refused
      await pg.route('**/rest/v1/rpc/proveedor_pago_registrar', (r) => r.fulfill({ status: 401, contentType: 'application/json', body: '{"code":"PGRST301","message":"JWT expired"}' }), { times: 1 });
      await pg.evaluate(() => localStorage.removeItem('sb-127-auth-token'));
      await pg.click('#payGo');
      await pg.waitForSelector('#loginView:not([hidden])', { timeout: 10000 });
      assert.strictEqual(await pg.locator('#appView').isVisible(), false);
      const kept = await pg.evaluate(() => sessionStorage.getItem('hg-prov-resume'));
      assert.match(kept, /SNP-4455/, 'what was typed is kept in this tab');
      assert.ok(!kept.includes(PINS.ana), 'never the PIN');   /* a failure never prints it */
      assert.strictEqual(sql(`select count(*) from supplier_advances`), '0');
      // sign in again: a new sign-in has no unlock, so the owner areas are opened again; then the form is back
      await pg.fill('#em', 'cafe@test.local');
      await pg.fill('#pw', 'test');
      await pg.click('#loginForm button[type=submit]');
      await pg.waitForSelector('#turnoView:not([hidden])', { timeout: 10000 });
      await pg.click('#turnoOwner');
      await P.gate(pg, 'ana');
      await pg.waitForSelector('#payModal:not([hidden])', { timeout: 10000 });
      assert.strictEqual(await pg.inputValue('#payAmt'), '7000');
      assert.strictEqual(await pg.inputValue('#payRef'), 'SNP-4455');
      assert.ok((await pg.inputValue('#payPin')) === '', 'the PIN is typed again');   /* never prints the box */
      await P.toasted(pg, /^Lo que escribió volvió\. Revíselo y guarde\.$|volvió/, 'told', 5000);
      await pg.fill('#payPin', PINS.ana);
      await pg.click('#payGo');
      try { await until(() => sql(`select count(*) || '|' || string_agg(amount_crc::text, ',') from supplier_advances`) === '1|7000.00', 8000, 'the payment saved once'); }
      catch (e) {   /* say what the window showed (never the PIN box) */
        throw new Error(e.message + ' · window open: ' + (await pg.locator('#payModal').isVisible()) + ' · its message: «' + (await text(pg.locator('#payErr'))) + '» · toast: «' + (await text(pg.locator('#toast')).catch(() => '')) + '» · api errors: ' + JSON.stringify(pg.apiErrors) + ' · page errors: ' + JSON.stringify(pg.errors));
      }
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'the unlock ends (the pill\'s Lock): every piece of management data leaves the screen; the tablet goes back to receiving',
    run: async ({ browser }) => {
      P.seed();
      P.asOwner(`select public.proveedor_guardar('{"id":"${V.lac}","sinpe":"8888 1111 Lácteos MV"}')`);
      const o = P.create(V.lac, [{ vi: P.vi(I.leche), packs: 2 }]);
      const pg = await P.cafeManager(browser, { hash: '#pedido=' + o.id, wait: '#orderDoc' });
      await pg.click('#docPrint');
      await pg.click('#docPay');
      await pg.waitForSelector('#payModal:not([hidden])');
      assert.match(await text(pg.locator('#payIntro')), /SINPE 8888 1111 Lácteos MV/);
      await pg.click('#payCancel');
      await pg.locator('.hga-pill button').click();
      await pg.waitForSelector('#turnoView:not([hidden])', { timeout: 10000 });
      const left = await pg.evaluate(() => ({ html: document.body.innerHTML, print: document.getElementById('printDoc').innerHTML, po: document.getElementById('payPo').innerHTML, intro: document.getElementById('payIntro').textContent }));
      assert.doesNotMatch(left.html, /8888 1111|₡20 400|₡10 200|Pedido Nº|Rosa Jiménez|ventas@lacteos/, 'no management data left in the page');
      assert.strictEqual(left.print, '', 'the printable order is gone');
      assert.strictEqual(left.po, '', 'the payment window\'s orders are gone');
      assert.strictEqual(sql(`select count(*) from access_unlocks where expires_at > now()`), '0', 'the unlock ended on the server too');
      assert.strictEqual(await pg.inputValue('#payAmt'), '', 'the payment window is empty');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'phone, tablet and desktop: no sideways scroll and 44 px targets on the hub, the file, the order, the receive form and the payment window',
    run: async ({ browser }) => {
      P.seed(); P.clockIn('luis');
      const o = P.create(V.lac, [{ vi: P.vi(I.leche), packs: 2 }, { vi: P.vi(I.crema), packs: 3 }]);
      P.receive(o.id, [{ line: P.lineOf(o.id, I.leche), rest: true }]);
      for (const size of [{ width: 360, height: 740 }, { width: 820, height: 1180 }, { width: 1280, height: 860 }]) {
        const w = size.width + '×' + size.height;
        /* the phone and the tablet have a touch screen (device()): there the key actions are taps, touch events rather
           than mouse clicks (audit 15.I5), and their results are checked */
        const touch = size.width < 1024;
        const pg = await device(browser, size, { login: 'owner', aal: 'aal2' });
        await goto(pg, '/proveedores');
        await pg.waitForSelector('#hubVendors .vcard');
        await P.layoutOk(pg, w + ' hub');
        await P.nav(pg, '#p=' + V.lac, '#pList .prow');
        const milk = pg.locator(`#pList .prow[data-vi="${P.vi(I.leche)}"]`), yog = pg.locator(`#pList .prow[data-vi="${P.vi(I.yogur)}"]`);
        if (touch) {
          await P.seen(pg.locator('#pSum'), /^0 productos · Total estimado ₡0$/, w + ': nothing ticked yet', 3000);
          await milk.locator('.ck input').tap();
          await P.seen(pg.locator('#pSum'), /^1 producto · Total estimado ₡20 400$/, w + ': a tap on the box ticks the milk (the last order\'s 2 boxes)', 3000);
          await milk.locator('button[data-a=plus]').tap();
          await P.seen(pg.locator('#pSum'), /^1 producto · Total estimado ₡30 600$/, w + ': the stepper\'s «+» tapped: three boxes', 3000);
          assert.strictEqual(await milk.locator('.step input').inputValue(), '3', w);
        } else await milk.locator('.ck input').check();
        await P.layoutOk(pg, w + ' file');
        if (touch) {
          /* the number pad under the yogurt's box: a tapped digit is the quantity and ticks it; its ✓ closes the pad */
          await yog.locator('.step input').tap();
          const pad = yog.locator('.hg-pad');
          await pad.waitFor({ state: 'visible', timeout: 3000 });
          await pad.locator('button', { hasText: /^3$/ }).tap();
          assert.strictEqual(await yog.locator('.step input').inputValue(), '3', w + ': the keypad\'s 3');
          assert.strictEqual(await yog.locator('.ck input').isChecked(), true, w + ': typing on the pad ticks it');
          await P.seen(pg.locator('#pSum'), /^2 productos · Total estimado ₡44 100$/, w + ': 30 600 + 3 × 4 500', 3000);
          await pad.locator('.ok').tap();
          await pad.waitFor({ state: 'hidden', timeout: 3000 });
          /* untick both with a tap: the next device opens this supplier with an empty draft */
          await yog.locator('.ck input').tap();
          await milk.locator('.ck input').tap();
          await P.seen(pg.locator('#pSum'), /^0 productos · Total estimado ₡0$/, w + ': a tap unticks', 3000);
          /* an emptied draft is discarded on the server: nothing ticked waits there for the next device */
          await until(async () => !/Guardando|Saving/.test(await text(pg.locator('#pStatus'))) &&
                                  sql(`select count(*) from purchase_drafts where vendor_id = '${V.lac}' and status = 'open' and jsonb_array_length(lines) > 0`) === '0', 8000, w + ': the emptied draft saved');
        }
        for (const t of ['pedidos', 'pagos', 'productos']) { await P.nav(pg, '#p=' + V.lac + '&t=' + t, '#fTab > *'); await P.layoutOk(pg, w + ' ' + t); }
        await P.nav(pg, '#pedido=' + o.id, '#orderDoc');
        await P.layoutOk(pg, w + ' order');
        /* «Editar»: each line's «×» (one with deliveries, disabled; one without) is a 44 px target too */
        await pg.click('#docEdit'); await pg.waitForSelector('#orderEdit');
        assert.strictEqual(await pg.locator('#oeLines button', { hasText: '×' }).count(), 2);
        await P.layoutOk(pg, w + ' order editor');
        await pg.click('#oeCancel');
        await pg.click('#docPay'); await pg.waitForSelector('#payModal:not([hidden])');
        await P.layoutOk(pg, w + ' payment window');
        await pg.click('#payCancel');
        await P.nav(pg, '#recibir=' + o.id, '#recvCard');
        await P.layoutOk(pg, w + ' receive (management)');
        const emp = await device(browser, size, { login: 'cafe' });
        await goto(emp, '/proveedores');
        const since = sql(`select now()::text`);
        await P.iAmHere(emp, 'luis', { tap: touch });   /* on a touch screen: the name, the PIN pad's digits and its ✓ tapped */
        if (touch) {
          await P.seen(emp.locator('#modeBar'), /^Recibe: Luis/, w + ': Luis receives on this device', 3000);
          assert.strictEqual(sql(`select count(*) from work_sessions where staff_id = '${STAFF.luis}' and ended_at is null and how = 'pin' and started_at >= '${since}'`), '1',
                             w + ': the server started his work session with the PIN');
        }
        await P.layoutOk(emp, w + ' receive list (employee)');
        await P.nav(emp, '#recibir=' + o.id, '#recvCard');
        await P.layoutOk(emp, w + ' receive form (employee)');
        const big = await emp.locator('#recvAll').boundingBox();
        assert.ok(big.height >= 60, w + ': «Todo recibido correctamente» is a big button (' + big.height + ')');
        if (touch) {
          /* «Todo recibido correctamente» tapped, on a delivery of its own (the order above stays for the next device) */
          const t = P.create(V.lac, [{ vi: P.vi(I.leche), packs: 2 }]);
          const stock = () => Number(sql(`select on_hand from stock_items where id = '${I.leche}'`));
          const before = stock();
          await P.nav(emp, '#recibir=' + t.id, '#recvAll');
          await P.seen(emp.locator('#recvAll'), /^Todo recibido correctamente$/, w + ': the big button, in Spanish', 3000);
          await emp.locator('#recvAll').tap();
          await emp.waitForSelector('#recvDone', { timeout: 10000 });
          await P.seen(emp.locator('#recvDone'), /^Pedido recibido, existencias actualizadas 2 × Leche entera Recibir otro pedido$/, w + ': received', 3000);
          assert.strictEqual(stock() - before, 24, w + ': 2 boxes of 12 into stock, once');
          assert.strictEqual(sql(`select o.status || '|' || count(r.*) || '|' || string_agg(r.by_name, ',') from purchase_orders o join purchase_receipts r on r.po_id = o.id where o.id = '${t.id}' group by o.status`),
                             'received|1|Luis (en turno)', w + ': one delivery, by Luis');
        }
        for (const p of [pg, emp]) { assert.deepStrictEqual(p.errors, [], w); assert.deepStrictEqual(p.apiErrors, [], w); await p.context().close(); }
      }
    }
  },
  {
    name: 'idle sign-out: the owner with the phone code after the idle time (never while a form is dirty); never the café tablet',
    run: async ({ browser }) => {
      P.seed();
      const own = P.watchApi(await page(browser, { login: 'owner', aal: 'aal2', lang: 'es' }));
      await own.addInitScript(() => { window.PROV_TEST = { idleMs: 1500 }; });
      await goto(own, '/proveedores#p=' + V.lac);
      await own.waitForSelector('#ficha');
      await own.click('#fEditBtn');
      await own.fill('#vfPhone', '2645 0000');
      await own.waitForTimeout(2500);
      assert.strictEqual(await own.locator('#appView').isVisible(), true, 'a dirty form keeps the sign-in');
      await own.locator('#vendorForm button', { hasText: 'Cancelar' }).click();
      await own.waitForSelector('#loginView:not([hidden])', { timeout: 8000 });
      const cafe = P.watchApi(await page(browser, { login: 'cafe', lang: 'es' }));
      await cafe.addInitScript(() => { window.PROV_TEST = { idleMs: 1000 }; });
      await goto(cafe, '/proveedores');
      await cafe.waitForSelector('#turnoView:not([hidden])');
      await cafe.waitForTimeout(2500);
      assert.strictEqual(await cafe.locator('#loginView').isVisible(), false, 'the café tablet stays signed in');
      for (const p of [own, cafe]) assert.deepStrictEqual(p.errors, []);
    }
  }
];
