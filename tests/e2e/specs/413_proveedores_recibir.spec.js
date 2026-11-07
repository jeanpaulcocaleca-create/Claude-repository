/* Proveedores (D-067) · receiving. An EMPLOYEE on shift receives without a further PIN: «Estoy en turno aquí» once
   (their own PIN, once per device per shift), or the POS's «¿Quién cobra?» on the same device (no PIN at all here); then
   «Todo recibido correctamente» in ONE tap (2 boxes of 12 → +24 units); a partial delivery (6 of 10, then the 4); the
   price the employee saw is noted, never booked, and the catalog price stays; more than ordered is reported, not booked;
   without a session there is only the guidance; another device's stale form is told «changed» (nothing twice); one
   receiver per device («¿No es usted? Cambiar»); «Salir de este aparato»; a new sign-in on the device takes the work
   session along (the token rotated) only after two quiet minutes. Management: presentations of grams, the invoice number,
   the price check, corrections by a new record. The speed target of a correct receipt (timed, taps counted). */
'use strict';
const assert = require('assert');
const { page, goto, until, settle, sql, STAFF, PINS } = require('../lib');
const gw = require('../gateway');
const P = require('../prov');
const { V, I, text } = P;

const onHand = (item) => sql(`select trim_scale(on_hand) from stock_items where id = '${item}'`);
async function openOrder(pg, po) {
  await pg.locator(`#main a[href="#recibir=${po}"]`).first().click();
  await pg.waitForSelector('#recvCard', { timeout: 10000 });
}
/* nothing about money, the supplier's contact or SINPE on an employee's screen */
async function noMoney(pg, where) {
  const t = await text(pg.locator('#appView'));
  assert.doesNotMatch(t, /Total|Saldo|Pagos?\b|Pagado|SINPE|Debe|2645 1111|8888|ventas@/, where + ': ' + t);
}

module.exports.tests = [
  {
    name: 'an employee says who they are once (their own PIN), then «Todo recibido correctamente» in one tap: 2 boxes of 12 → +24 (speed)',
    run: async ({ browser }) => {
      P.seed(); P.clockIn('luis');
      P.asOwner(`select public.proveedor_guardar('{"id":"${V.lac}","sinpe":"8888 1111 Lácteos MV"}')`);
      const o = P.create(V.lac, [{ vi: P.vi(I.leche), packs: 2 }]);
      const o2 = P.create(V.lac, [{ vi: P.vi(I.yogur), packs: 1 }]);
      const pg = await P.employee(browser, 'luis');
      await P.seen(pg.locator('#modeBar'), /^Recibe: Luis ¿No es usted\? Cambiar Salir de este aparato Abrir áreas de dueños$/, 'who receives, in Spanish', 5000);
      assert.ok((await pg.inputValue('#tqPin')) === '', 'the PIN box is emptied');   /* never prints the box */
      assert.strictEqual(sql(`select how || '|' || staff_name || '|' || (ended_at is null) from work_sessions`), 'pin|Luis|true');
      await P.seen(pg.locator('#main'), /Pedidos por recibir/, 'the orders to receive', 5000);
      await noMoney(pg, 'the list');
      // the speed target: from opening the order to «Recibido»
      let taps = 0;
      const t0 = await pg.evaluate(() => performance.now());
      await openOrder(pg, o.id); taps++;
      await noMoney(pg, 'the receive form');
      assert.match(await text(pg.locator('#recvCard .recvhead')), /Recibe: Luis/);
      await pg.click('#recvAll'); taps++;
      await pg.waitForSelector('#recvDone', { timeout: 10000 });
      const ms = Math.round((await pg.evaluate(() => performance.now())) - t0);
      console.log(`        speed · a correct receipt by an employee: ${taps} taps, ${ms} ms from opening the order to «Recibido»`);
      assert.match(await text(pg.locator('#recvDone')), /^Pedido recibido, existencias actualizadas 2 × Leche entera Recibir otro pedido$/);
      assert.strictEqual(onHand(I.leche), '30', '6 + 2 boxes of 12');
      assert.strictEqual(sql(`select status from purchase_orders where id = '${o.id}'`), 'received');
      assert.strictEqual(sql(`select by_name || '|' || (staff_id = '${STAFF.luis}') || '|' || (work_session_id is not null) || '|' || origin from purchase_receipts`), 'Luis (en turno)|true|true|proveedores');
      assert.strictEqual(sql(`select count(*) from stock_moves where kind = 'purchase'`), '1', 'one move');
      assert.ok(taps <= 2 && ms < 5000, taps + ' taps, ' + ms + ' ms');
      // the next order, still without a PIN; a reload keeps who receives
      await P.nav(pg, '#');
      await pg.reload({ waitUntil: 'domcontentloaded' });
      await P.seen(pg.locator('#modeBar'), /^Recibe: Luis/, 'still Luis after a reload', 8000);
      await openOrder(pg, o2.id);
      await pg.click('#recvAll');
      await pg.waitForSelector('#recvDone', { timeout: 10000 });
      assert.strictEqual(onHand(I.yogur), '46');
      assert.strictEqual(sql(`select count(*) from audit_log where action = 'work_session_start'`), '1', 'the PIN was typed once');
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, []);
    }
  },
  {
    name: 'the POS «¿Quién cobra?» on the same device gives the work session: Proveedores asks no PIN at all',
    run: async ({ browser }) => {
      P.seed(); P.clockIn('marta');
      const o = P.create(V.pan, [{ vi: P.vi(I.pan, V.pan), packs: 3 }]);
      sql(`insert into settings (key, value) values ('operator_mode', '"record"')`);
      const posPg = await require('../lib').pos(browser, { lang: 'es' });
      await posPg.waitForSelector('#opModal:not([hidden])', { timeout: 10000 });
      await settle(posPg);
      await posPg.locator('#opWho button', { hasText: 'Marta' }).click();
      await posPg.fill('#opPin', PINS.marta);
      await posPg.click('#opGo');
      await until(async () => (await posPg.locator('#opBtn').textContent()) === 'Marta', 8000, 'Marta rings up on the POS');
      // the same device (browser context) opens Proveedores
      const pg = P.watchApi(await page(browser, { context: posPg.context(), login: 'cafe', lang: 'es' }));
      await goto(pg, '/proveedores');
      await P.seen(pg.locator('#modeBar'), /^Recibe: Marta/, 'Marta receives, from the POS', 10000);
      assert.strictEqual(await pg.locator('#turnoView').isVisible(), false, 'no «¿Quién recibe?»');
      assert.strictEqual(sql(`select how || '|' || staff_name from work_sessions where ended_at is null`), 'caja|Marta');
      await openOrder(pg, o.id);
      await pg.click('#recvAll');
      await pg.waitForSelector('#recvDone', { timeout: 10000 });
      assert.strictEqual(onHand(I.pan), '30', '3 bags of 10');
      assert.strictEqual(sql(`select by_name from purchase_receipts`), 'Marta (en turno)');
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, []);
    }
  },
  {
    name: 'the answer of a saved delivery is lost: reopening the order says it was saved, and the rest goes as a new delivery (never a «repeat» that books nothing)',
    run: async ({ browser }) => {
      P.seed(); P.clockIn('luis');
      const o = P.create(V.lac, [{ vi: P.vi(I.yogur), packs: 10 }]);
      const pg = await P.employee(browser, 'luis', { hash: '#recibir=' + o.id });
      await pg.waitForSelector('#recvCard');
      await pg.fill('#rq0', '6');
      // the server saves the delivery, but its answer never reaches the tablet
      await pg.route('**/rest/v1/rpc/proveedor_recibir', async (route) => { await route.fetch(); await route.abort('connectionreset'); }, { times: 1 });
      await pg.click('#recvGo');
      await until(() => sql(`select count(*) from purchase_receipts where po_id = '${o.id}'`) === '1', 10000, 'the delivery is saved on the server');
      await P.seen(pg.locator('#rErr'), /.+/, 'the tablet says it could not confirm', 8000);
      assert.strictEqual(onHand(I.yogur), '76', '40 + 6 × 6');
      // the order opened again later on the same tablet
      await pg.reload({ waitUntil: 'domcontentloaded' });
      await pg.waitForSelector('#recvCard', { timeout: 15000 });
      await P.seen(pg.locator('#recvCard'), /Su entrega anterior ya quedó guardada/, 'told the earlier delivery was saved', 8000);
      assert.strictEqual(await pg.inputValue('#rq0'), '4', 'only the 4 pending are proposed');
      await pg.click('#recvAll');
      await pg.waitForSelector('#recvDone', { timeout: 10000 });
      assert.strictEqual(sql(`select status from purchase_orders where id = '${o.id}'`), 'received');
      assert.strictEqual(onHand(I.yogur), '100', '40 + 10 × 6: both deliveries booked, each once');
      assert.strictEqual(sql(`select count(*) from purchase_receipts where po_id = '${o.id}'`), '2', 'two deliveries');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'a partial delivery: 6 of 10 → «Parcialmente recibido», 4 pending; then the 4; never twice',
    run: async ({ browser }) => {
      P.seed(); P.clockIn('luis');
      const o = P.create(V.lac, [{ vi: P.vi(I.yogur), packs: 10 }]);
      const pg = await P.employee(browser, 'luis', { hash: '#recibir=' + o.id });
      await pg.waitForSelector('#recvCard');
      assert.strictEqual(await pg.inputValue('#rq0'), '10', 'the pending amount proposed');
      await pg.fill('#rq0', '6');
      await P.seen(pg.locator('#recvTable'), /Faltan 4/, 'short 4', 3000);
      await P.seen(pg.locator('#rShort'), /^Avisar que no llega el resto$/, 'the employee may tell the manager', 3000);
      assert.strictEqual(await pg.isChecked('#rClose'), false, 'the rest stays pending by default');
      await pg.click('#recvGo');
      await pg.waitForSelector('#recvDone', { timeout: 10000 });
      assert.match(await text(pg.locator('#recvDone')), /^Entrega recibida · el resto sigue pedido 6 × Yogur natural Faltan 4 · Yogur natural/);
      assert.strictEqual(sql(`select status from purchase_orders where id = '${o.id}'`), 'partially_received');
      assert.strictEqual(onHand(I.yogur), '76', '40 + 6 × 6');
      // the manager's document: «Parcialmente recibido», 4 pending
      const m = await P.owner(browser, { hash: '#pedido=' + o.id, wait: '#orderDoc' });
      await P.seen(m.locator('#orderDoc .dh'), /Parcialmente recibido/, 'partly received', 5000);
      await P.seen(m.locator('#docLines tbody tr'), /10 ₡4 500 ₡45 000 6 4$/, 'received 6, pending 4', 3000);
      // the rest arrives: the form proposes the 4
      await P.nav(pg, '#');
      await openOrder(pg, o.id);
      assert.strictEqual(await pg.inputValue('#rq0'), '4');
      assert.match(await text(pg.locator('#recvTable')), /ya llegaron 6 · pendiente 4|6 .*4/);
      await pg.click('#recvAll');
      await pg.waitForSelector('#recvDone', { timeout: 10000 });
      assert.strictEqual(sql(`select status from purchase_orders where id = '${o.id}'`), 'received');
      assert.strictEqual(onHand(I.yogur), '100', '40 + 10 × 6, once');
      // the received order is no longer offered
      await P.nav(pg, '#recibir=' + o.id);
      await P.seen(pg.locator('#main'), /Ese pedido no está esperando recepción\./, 'not offered again', 8000);
      assert.strictEqual(sql(`select count(*) from purchase_receipts`), '2');
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(m.errors, []);
    }
  },
  {
    name: 'the price the employee saw is noted, not booked (the catalog price stays); more than ordered is reported, not booked; the manager reviews both',
    run: async ({ browser }) => {
      P.seed(); P.clockIn('luis');
      const o = P.create(V.lac, [{ vi: P.vi(I.leche), packs: 2 }]);
      const pg = await P.employee(browser, 'luis', { hash: '#recibir=' + o.id });
      await pg.waitForSelector('#recvCard');
      assert.strictEqual(await pg.inputValue('#rp0'), '10200', 'the expected price proposed');
      await pg.fill('#rq0', '3');
      await P.seen(pg.locator('#recvTable'), /Llegó más de lo pedido: se anota para el encargado/, 'over: noted', 3000);
      await P.seen(pg.locator('#rOver'), /solo entra al inventario lo pedido/, 'not booked', 3000);
      await pg.fill('#rp0', '11000');
      await pg.click('#recvGo');
      await pg.waitForSelector('#recvDone', { timeout: 10000 });
      const done = await text(pg.locator('#recvDone'));
      assert.match(done, /2 × Leche entera Anotado para el encargado: 1 · Leche entera Precios distintos que vio \(el encargado los revisa\): Leche entera · ₡11 000 \(se esperaba ₡10 200\)/, done);
      assert.doesNotMatch(done, /Usar ₡/, 'the employee cannot change the usual price');
      assert.strictEqual(onHand(I.leche), '30', 'only what was ordered went into stock (6 + 24)');
      assert.strictEqual(sql(`select trim_scale(packs) || '|' || pack_price || '|' || observed_pack_price || '|' || trim_scale(extra_reported_packs) from purchase_receipt_lines`), '2|10200.00|11000.00|1');
      assert.strictEqual(sql(`select usual_price from vendor_items where id = '${P.vi(I.leche)}'`), '10200.00', 'the catalog price is unchanged');
      assert.strictEqual(sql(`select cost_per_pack from stock_items where id = '${I.leche}'`), '10200', 'the item\'s last price is untouched by an employee');
      assert.strictEqual(sql(`select round(unit_cost * 12, 2) from stock_moves where kind = 'purchase'`), '10200.00', 'booked at the expected price');
      // the manager sees both on the order and may take the new price as the usual one
      const m = await P.owner(browser, { hash: '#pedido=' + o.id, wait: '#orderDoc' });
      const rec = await text(m.locator('#main .rcpt'));
      assert.match(rec, /Luis \(en turno\).*2 × Leche entera · ₡10 200 · Precio visto: ₡11 000 \(se esperaba ₡10 200\) · Llegó de más: 1 \(anotado por el empleado\) Usar ₡11 000 como precio habitual$/, rec);
      await m.locator('#main .rcpt button', { hasText: 'Usar ₡11 000 como precio habitual' }).click();
      await P.toasted(m, /^Precio habitual guardado$/, 'the usual price saved by the manager');
      assert.strictEqual(sql(`select usual_price from vendor_items where id = '${P.vi(I.leche)}'`), '11000.00');
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(m.errors, []);
      assert.deepStrictEqual(m.apiErrors, []);
    }
  },
  {
    name: 'without a work session there is only the guidance; another device\'s stale form is told «changed»; one receiver per device; «Salir de este aparato»',
    run: async ({ browser }) => {
      P.seed(); P.clockIn('luis'); P.clockIn('marta');
      const o = P.create(V.lac, [{ vi: P.vi(I.leche), packs: 2 }]);
      // nobody has said who they are: the guidance, never the form
      const none = P.watchApi(await page(browser, { login: 'cafe', lang: 'es' }));
      await goto(none, '/proveedores#recibir=' + o.id);
      await none.waitForSelector('#turnoView:not([hidden])', { timeout: 10000 });
      await P.seen(none.locator('#turnoView'), /^¿Quién recibe\? Toque su nombre y escriba su propio PIN, una vez por turno en este aparato\. Después recibe pedidos sin PIN\. Luis Marta/, 'the guidance', 8000);
      assert.strictEqual(await none.locator('#recvCard, #recvAll').count(), 0, 'no receive form');
      // two devices, one person each, the same order open
      const a = await P.employee(browser, 'luis', { hash: '#recibir=' + o.id });
      const b = await P.employee(browser, 'marta', { hash: '#recibir=' + o.id });
      await a.waitForSelector('#recvCard'); await b.waitForSelector('#recvCard');
      // A records 1 of the 2 boxes; B, still showing 2 pending, taps «Todo recibido correctamente»
      await a.fill('#rq0', '1');
      await a.click('#recvGo');
      await a.waitForSelector('#recvDone', { timeout: 10000 });
      await b.click('#recvAll');
      await P.seen(b.locator('#recvCard'), /Otra persona registró una entrega de este pedido hace un momento\. Revise lo pendiente\./, 'B is told «changed»', 10000);
      assert.strictEqual(await b.inputValue('#rq0'), '1', 'B now proposes the 1 still pending');
      assert.strictEqual(onHand(I.leche), '18', 'nothing booked by the stale form (6 + 12)');
      await b.click('#recvAll');
      await b.waitForSelector('#recvDone', { timeout: 10000 });
      assert.strictEqual(onHand(I.leche), '30', 'each box once');
      assert.strictEqual(sql(`select count(*) || '|' || string_agg(by_name, ',' order by received_at) from purchase_receipts`), '2|Luis (en turno),Marta (en turno)');
      // a form left open on a received order: told so, nothing booked
      await P.nav(a, '#recibir=' + o.id);
      await P.seen(a.locator('#main'), /Ese pedido no está esperando recepción\.|ya se recibió/i, 'a received order is not offered', 8000);
      // one receiver per device: Marta takes over device A
      await a.locator('#modeBar button', { hasText: '¿No es usted? Cambiar' }).click();
      await P.iAmHere(a, 'marta');
      assert.strictEqual(sql(`select string_agg(staff_name || ':' || coalesce(ended_how, 'live'), ',' order by started_at) from work_sessions`), 'Luis:replaced,Marta:moved,Marta:live', 'Luis is replaced on this device; Marta\'s session on the other device (same login and station) moves here');
      // «Salir de este aparato»
      await a.locator('#modeBar button', { hasText: 'Salir de este aparato' }).click();
      await P.toasted(a, /^Listo: ya nadie recibe en este aparato\.$/, 'signed out of the device');
      await a.waitForSelector('#turnoView:not([hidden])');
      assert.strictEqual(sql(`select count(*) from work_sessions where ended_how = 'signed_out'`), '1');
      assert.strictEqual(await a.evaluate(() => localStorage.getItem('hg-turnos')), '{}', 'nothing kept on the device');
      for (const pg of [none, a, b]) assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'not clocked in: «Marcar entrada y empezar» with the PIN clocks the employee in; a shift open since an earlier day only shows the message',
    run: async ({ browser }) => {
      P.seed();
      const o = P.create(V.lac, [{ vi: P.vi(I.leche), packs: 1 }]);
      const pg = P.watchApi(await page(browser, { login: 'cafe', lang: 'es' }));
      await goto(pg, '/proveedores');
      await pg.waitForSelector('#turnoView:not([hidden])');
      await P.seen(pg.locator('#turnoWho'), /Nadie tiene la entrada marcada en este momento\./, 'nobody on shift', 5000);
      assert.strictEqual(await pg.locator('#turnoOthers').getAttribute('open'), '', 'the others are open');
      await pg.locator(`#turnoWhoOff button[data-staff="${STAFF.luis}"]`).click();
      await P.seen(pg.locator('#turnoGo'), /^Marcar entrada y empezar$/, 'the button offers to clock in', 3000);   // lang.js translates on the next frame
      await pg.fill('#tqPin', PINS.luis);
      await pg.click('#turnoGo');
      await P.seen(pg.locator('#modeBar'), /^Recibe: Luis/, 'clocked in and receiving', 8000);
      assert.strictEqual(sql(`select count(*) from time_entries where staff_id = '${STAFF.luis}' and clock_out is null`), '1', 'his shift started');
      // Marta's shift is open since yesterday: told to see a manager, no punch, no session
      sql(`insert into time_entries (staff_id, clock_in) values ('${STAFF.marta}', now() - interval '20 hours')`);
      await pg.locator('#modeBar button', { hasText: '¿No es usted? Cambiar' }).click();
      await pg.waitForSelector('#turnoView:not([hidden])');
      await settle(pg);
      // her open entry is older than 16 h: she is not «on shift»; she is under «¿Todavía no marcó entrada?»
      await pg.locator('#turnoOthers summary').click();
      await pg.locator(`#turnoWhoOff button[data-staff="${STAFF.marta}"]`).click();
      await pg.fill('#tqPin', PINS.marta);
      await pg.click('#turnoGo');
      await P.seen(pg.locator('#turnoErr'), /^Tiene un turno abierto desde .*; avise a un encargado\.$/, 'the stale shift', 8000);
      assert.strictEqual(sql(`select count(*) from work_sessions where staff_name = 'Marta'`), '0');
      assert.ok((await pg.inputValue('#tqPin')) === '', 'the PIN box emptied after the call');   /* never prints the box */
      assert.ok(o.id);
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'presentations of grams: 2,5 bars of 500 g arrive → +1 250 g; the half bar stays pending',
    run: async ({ browser }) => {
      P.seed();
      const o = P.create(V.lac, [{ vi: P.vi(I.mant), packs: 3 }]);
      const pg = await P.owner(browser, { hash: '#recibir=' + o.id, wait: '#recvCard' });
      assert.match(await text(pg.locator('#recvTable tbody')), /Mantequilla barra de 500 g · 500 g 3/);
      await pg.fill('#rq0', '2.5');
      await P.seen(pg.locator('#recvTable'), /Faltan 0,5/, 'half a bar short', 3000);
      await pg.click('#recvGo');
      await pg.waitForSelector('#recvDone', { timeout: 10000 });
      assert.strictEqual(onHand(I.mant), '5250', '4 000 g + 2,5 × 500 g');
      assert.strictEqual(sql(`select trim_scale(qty) || '|' || trim_scale(received_qty) from purchase_lines where po_id = '${o.id}'`), '1500|1250');
      assert.strictEqual(sql(`select status from purchase_orders where id = '${o.id}'`), 'partially_received');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'management: two deliveries with the supplier invoice, the same number twice refused; a typed price checked; a correction by a new record',
    run: async ({ browser }) => {
      P.seed();
      const o = P.create(V.lac, [{ vi: P.vi(I.leche), packs: 10 }]);
      const pg = await P.owner(browser, { hash: '#recibir=' + o.id, wait: '#recvCard', lang: 'en' });
      await pg.fill('#rq0', '6');
      await pg.fill('#rInv', 'F-200');
      await pg.click('#recvGo');
      await pg.waitForSelector('#recvDone', { timeout: 10000 });
      await P.seen(pg.locator('#recvDone'), /^Delivery received · the rest is still on order 6 × Leche entera Short 4 · Leche entera Received at cost ₡61 200/, 'part received, in English', 3000);
      assert.strictEqual(sql(`select status from purchase_orders where id = '${o.id}'`), 'partially_received');
      // the rest, with the same invoice number in other letters: refused, nothing booked
      await P.nav(pg, '#recibir=' + o.id, '#recvCard');
      assert.strictEqual(await pg.inputValue('#rq0'), '4', 'the rest is proposed');
      await pg.fill('#rInv', 'f-200');
      await pg.click('#recvGo');
      await P.seen(pg.locator('#rErr'), /^That invoice number is already registered for this supplier\.$/, 'the duplicate invoice', 8000);
      assert.strictEqual(sql(`select count(*) from purchase_receipts`), '1');
      // a price far from the expected one asks first
      await pg.fill('#rInv', 'F-212');
      await pg.fill('#rp0', '50000');
      await pg.click('#recvGo');
      await P.seen(pg.locator('#rPriceAsk'), /^Sure\? The expected price was ₡10 200 · Leche entera Yes, the price is right$/, 'the price check', 8000);
      await pg.fill('#rp0', '10500');
      await pg.click('#recvGo');
      await pg.waitForSelector('#recvDone', { timeout: 10000 });
      assert.match(await text(pg.locator('#recvDone')), /Price differences: Leche entera · ₡10 500 \(expected ₡10 200\) Use ₡10 500 as the usual price/);
      assert.strictEqual(sql(`select status from purchase_orders where id = '${o.id}'`), 'received');
      assert.strictEqual(onHand(I.leche), '126', '6 + 120');
      assert.strictEqual(sql(`select string_agg(invoice_no, ',' order by received_at) from purchase_receipts`), 'F-200,F-212');
      assert.strictEqual(sql(`select usual_price || '|' || (select trim_scale(cost_per_pack) from stock_items where id = '${I.leche}') from vendor_items where id = '${P.vi(I.leche)}'`), '10200.00|10500',
        'management\'s typed price is the item\'s last price; the supplier\'s catalog price is not touched');
      // a correction: one box of the first delivery did not come after all
      await P.nav(pg, '#pedido=' + o.id, '#orderDoc');
      await pg.locator('#docActs button', { hasText: 'Correct a delivery' }).click();
      await pg.waitForSelector('#fixModal:not([hidden])');
      await pg.selectOption('#fixRcpt', sql(`select id from purchase_receipts where invoice_no = 'F-200'`));
      await pg.fill('#fxL0', '−1');
      await pg.fill('#fixWhy', 'una caja venía rota');
      await pg.click('#fixGo');
      await P.toasted(pg, /^Correction saved$/, 'the correction');
      assert.strictEqual(sql(`select count(*) || '|' || string_agg(origin || ':' || (corrects is not null), ',' order by received_at) from purchase_receipts`), '3|proveedores:false,proveedores:false,correccion:true');
      assert.strictEqual(onHand(I.leche), '114', 'one box of 12 less, by a new move');
      assert.strictEqual(sql(`select count(*) from stock_moves where kind = 'purchase'`), '3', 'nothing deleted');
      assert.strictEqual(sql(`select status from purchase_orders where id = '${o.id}'`), 'partially_received', 'the order goes back to partly received');
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, []);
    }
  },
  {
    name: 'a new sign-in on the same device: the work session follows it (token rotated) after two quiet minutes; still in use elsewhere: asked again',
    run: async ({ browser }) => {
      P.seed(); P.clockIn('luis');
      const o = P.create(V.lac, [{ vi: P.vi(I.leche), packs: 2 }]);
      const pg = await P.employee(browser, 'luis');
      const before = await pg.evaluate(() => Object.values(JSON.parse(localStorage.getItem('hg-turnos')))[0].token);
      // the tablet signs in again (a new sign-in: another session id); the session was used just now: asked again
      const fresh = () => pg.evaluate((s) => localStorage.setItem('sb-127-auth-token', JSON.stringify(s)), gw.sessionFor('cafe@test.local'));
      await fresh();
      await pg.reload({ waitUntil: 'domcontentloaded' });
      await P.seen(pg.locator('#turnoView'), /Su turno se está usando en otro aparato ahora mismo\. Identifíquese de nuevo aquí\./, 'in use elsewhere', 10000);
      // two quiet minutes later, the next new sign-in takes it along: no PIN, the token rotated
      sql(`update work_sessions set last_used_at = now() - interval '3 minutes', started_at = started_at - interval '3 minutes'`);
      await P.iAmHere(pg, 'luis');
      sql(`update work_sessions set last_used_at = now() - interval '3 minutes'`);
      const mid = await pg.evaluate(() => Object.values(JSON.parse(localStorage.getItem('hg-turnos')))[0].token);
      await fresh();
      await pg.reload({ waitUntil: 'domcontentloaded' });
      await P.seen(pg.locator('#modeBar'), /^Recibe: Luis/, 'still Luis, without a PIN', 10000);
      const after = await pg.evaluate(() => Object.values(JSON.parse(localStorage.getItem('hg-turnos')))[0].token);
      assert.notStrictEqual(after, mid, 'the token rotated');
      assert.strictEqual(sql(`select count(*) from audit_log where action = 'work_session_rebound'`), '1');
      await pg.locator(`#main a[href="#recibir=${o.id}"]`).click();
      await pg.waitForSelector('#recvCard');
      await pg.click('#recvAll');
      await pg.waitForSelector('#recvDone', { timeout: 10000 });
      assert.strictEqual(sql(`select by_name from purchase_receipts`), 'Luis (en turno)');
      assert.ok(before);
      assert.deepStrictEqual(pg.errors, []);
    }
  }
];
