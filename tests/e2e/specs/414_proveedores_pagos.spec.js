/* Proveedores (D-067, 0040) · payments: SINPE needs its confirmation number (refused without it; the same number twice
   is refused, also written with spaces or dashes); a card with an optional reference; partial → «Parcialmente pagado»,
   full → «Pagado»; a payment before receiving (an advance) that the invoice applies («Registrar factura» with the 13 % /
   «Sin IVA» buttons); over the balance: refused for a manager, the owner may record it in favour with a reason; a card
   payment just like the last one asks first; a payment voided by the books door; the employee never sees money; the
   accountant (the books door: Pagos first, no ordering, no PIN, the SINPE only in the supplier's edit). 8.27 (owner,
   2026-11-07): the server itself applies the Proveedores payments first and refuses their SINPE numbers on every route
   (Contabilidad's «Registrar pago» without its own pre-apply, a bank payment with that number, Gastos). */
'use strict';
const assert = require('assert');
const { page, goto, until, sql, STAFF, PINS } = require('../lib');
const P = require('../prov');
const { V, I, text } = P;

async function payForm(pg) { await pg.waitForSelector('#payModal:not([hidden])', { timeout: 8000 }); }
async function save(pg) { await P.untoast(pg); await pg.click('#payGo'); }
const err = (pg) => text(pg.locator('#payErr'));
const advances = () => sql(`select coalesce(string_agg(method || ':' || amount_crc || ':' || coalesce(reference, '-') || ':' || coalesce(excess_reason, '-') || ':' || (voided_at is not null), ',' order by created_at), '') from supplier_advances`);
function ledger(prefix) {
  return sql(`select coalesce(string_agg(l.account || ':' || (l.debit - l.credit), ',' order by e.id, l.account), '') from acct.lines l join acct.entries e on e.id = l.entry_id where e.source_key like '${prefix}%'`);
}
/* 8.26 · Proveedores' money as Contabilidad meets it: a SINPE recorded in Proveedores (the owner with the phone code) for
   an order of Lácteos Monteverde -> its supplier_advances id; an invoice saved by SQL (supplier_invoice_save, which applies
   nothing by itself); what is open of an invoice; what is not applied of a payment */
function sinpe(po, amount, ref) {
  const r = P.asOwner(`select public.proveedor_pago_registrar('{"vendor_id":"${V.lac}","po_id":"${po}","amount":${amount},"method":"sinpe","reference":"${ref}"}', gen_random_uuid())`);
  if (!r || !r.ok) throw new Error('proveedor_pago_registrar: ' + JSON.stringify(r));
  return r.id;
}
function invoiceBySql(po, num, net, iva) {
  const rc = sql(`select id from purchase_receipts where po_id = '${po}'`);
  const r = P.asOwner(`select public.supplier_invoice_save(jsonb_build_object('vendor_id', '${V.lac}', 'number', '${num}', 'date', public.cr_today(), 'net_crc', ${net}, 'iva_crc', ${iva}, 'receipt_ids', jsonb_build_array('${rc}')), gen_random_uuid())`);
  if (!r || !r.ok) throw new Error('supplier_invoice_save: ' + JSON.stringify(r));
}
const openOf = (num) => sql(`select public._invoice_open(id) from supplier_invoices where number = '${num}'`);
const unapplied = (id) => sql(`select public._prov_unapplied('${id}')`);
const bankPays = () => sql(`select coalesce(string_agg(amount_crc::text, ',' order by created_at), '') from supplier_payments where paid_from = 'bank'`);
/* Contabilidad's drawer open and loaded */
const drawer = (pg) => until(() => pg.evaluate(() => document.getElementById('drawer').classList.contains('open') && !document.querySelector('#drawerBody .loading')), 8000, 'the drawer open');
/* Contabilidad › Proveedores › the card of Lácteos Monteverde, signed in with the phone code as who (the owner or the accountant) */
async function contab(browser, who) {
  const pg = P.watchApi(await page(browser, { login: who || 'owner', aal: 'aal2', lang: 'es' }));
  await goto(pg, '/contabilidad');
  await pg.waitForSelector('#appView:not([hidden])', { timeout: 15000 });
  await pg.evaluate(() => { location.hash = 'proveedores'; });
  await until(async () => (await pg.locator('#tbl-prov tbody tr.row', { hasText: 'Lácteos Monteverde' }).count()) === 1, 10000, 'the supplier listed');
  await pg.locator('#tbl-prov tbody tr.row', { hasText: 'Lácteos Monteverde' }).click();
  await drawer(pg);
  return pg;
}

module.exports.tests = [
  {
    name: 'a manager on the café tablet: SINPE needs its number; the same number twice is refused (spaces, dashes); a card; partial, then paid; over the balance refused',
    run: async ({ browser }) => {
      P.seed();
      const o = P.create(V.lac, [{ vi: P.vi(I.leche), packs: 2 }]);
      P.receive(o.id, [{ line: P.lineOf(o.id, I.leche), rest: true }]);
      const pg = await P.cafeManager(browser, { hash: '#pedido=' + o.id, wait: '#orderDoc' });
      await P.seen(pg.locator('#orderDoc .dh'), /^Pedido Nº \d+ Recibido Pago pendiente$/, 'received, payment pending', 5000);
      await pg.click('#docPay');
      await payForm(pg);
      assert.strictEqual(await pg.inputValue('#payPo'), o.id, 'this order');
      assert.strictEqual(await pg.inputValue('#payAmt'), '23052', 'the server\'s balance proposed: ₡20 400 with the IVA allowance before the invoice (13 %)');
      await P.seen(pg.locator('#docMoney'), /A pagar ₡23 052 estimado, IVA incl\./, 'the document shows the estimate with IVA, labelled, in Spanish', 3000);
      assert.strictEqual(await pg.locator('#payMethod button[data-m=sinpe]').getAttribute('aria-pressed'), 'true', 'SINPE first');
      // 8.23: under the SINPE number, what it is (typed by whoever records the payment) and who checks it (Contabilidad)
      await P.seen(pg.locator('#payRefNote'), /^El número lo escribe quien registra el pago: no es una verificación del banco\. Contabilidad lo comprueba al conciliar el estado de cuenta\.$/, 'the SINPE number hint, in Spanish', 3000);
      assert.ok(await pg.locator('#payRefNote').isVisible(), 'shown with the SINPE number');
      assert.strictEqual(await pg.getAttribute('#payRef', 'aria-describedby'), 'payRefNote', 'read out with the number box');
      assert.strictEqual(await pg.inputValue('#payWho'), STAFF.ana, 'who registers: the manager who opened the owner areas');
      // no confirmation number: refused before anything is sent
      await pg.fill('#payAmt', '10000');
      await save(pg);
      await P.seen(pg.locator('#payErr'), /^Escriba el número de confirmación SINPE\.$/, 'the number is required', 3000);
      await pg.fill('#payRef', 'AB');
      await save(pg);
      await P.seen(pg.locator('#payErr'), /^El número de confirmación SINPE no parece correcto: de 4 a 40 letras o números\.$/, 'too short', 3000);
      assert.strictEqual(advances(), '');
      await pg.fill('#payRef', '12345678');
      await pg.fill('#payPin', PINS.ana);
      await save(pg);
      await P.toasted(pg, /^Pago guardado · queda esperando la factura$/, 'saved (no invoice yet: it waits for the invoice)');
      assert.strictEqual(advances(), 'sinpe:10000.00:12345678:-:false');
      assert.strictEqual(ledger('supadv:'), '1110:-10000.00,1160:10000.00', 'Dr 1160 anticipos / Cr 1110 bank');
      await P.seen(pg.locator('#orderDoc .dh'), /Parcialmente pagado$/, 'partly paid', 8000);
      // the same SINPE number again, with spaces and a dash: refused, it says where it is
      await pg.click('#docPay'); await payForm(pg);
      assert.strictEqual(await pg.inputValue('#payAmt'), '13052', 'what is left of the server\'s balance');
      await pg.fill('#payRef', ' 1234-5678 ');
      await pg.fill('#payPin', PINS.ana);
      await save(pg);
      await P.seen(pg.locator('#payErr'), /^Ese número de SINPE ya está registrado \(Lácteos Monteverde, \d+ [a-z]+, ₡10 000\)\.$/, 'the duplicate SINPE', 8000);
      assert.ok((await pg.inputValue('#payPin')) === '', 'the PIN box emptied after the call');   /* never prints the box */
      await pg.fill('#payRef', '1234 5678');
      await pg.fill('#payPin', PINS.ana);
      await save(pg);
      await P.seen(pg.locator('#payErr'), /ya está registrado/, 'with spaces too', 8000);
      assert.strictEqual(sql(`select count(*) from supplier_advances`), '1');
      // the rest by debit card, no reference
      await pg.locator('#payMethod button[data-m=card]').click();
      assert.strictEqual(await pg.locator('#payCardKind button[data-k=card_debit]').getAttribute('aria-pressed'), 'true');
      assert.ok(await pg.locator('#payRefC').isVisible() && !(await pg.locator('#payRef').isVisible()), 'the reference is optional for a card');
      assert.strictEqual(await pg.locator('#payRefNote').isVisible(), false, 'the SINPE number hint goes with the SINPE number');
      await pg.fill('#payPin', PINS.ana);
      await save(pg);
      await P.toasted(pg, /^Pago guardado/, 'the card payment');
      assert.strictEqual(advances(), 'sinpe:10000.00:12345678:-:false,card_debit:13052.00:-:-:false');
      await P.seen(pg.locator('#orderDoc .dh'), /Recibido Pagado$/, 'paid', 8000);
      // more than the balance (nothing is left of it, the IVA allowance included): a manager cannot
      await pg.click('#docPay'); await payForm(pg);
      await pg.fill('#payAmt', '5000'); await pg.fill('#payRef', 'SNP-99881'); await pg.fill('#payPin', PINS.ana);
      await save(pg);
      await P.seen(pg.locator('#payErr'), /^Es más de lo que se debe: el saldo es ₡0\. Solo el dueño puede registrar un pago mayor que el saldo\.$/, 'over the balance', 8000);
      assert.strictEqual(await pg.locator('#payExcessBox').isVisible(), false, 'no overpayment box for a manager');
      assert.strictEqual(sql(`select count(*) from supplier_advances`), '2');
      // a wrong PIN: refused and counted
      await pg.fill('#payAmt', '1000'); await pg.fill('#payPin', '0000');
      await save(pg);
      await P.seen(pg.locator('#payErr'), /^Ese PIN no es correcto\.$/, 'the wrong PIN', 8000);
      assert.strictEqual(sql(`select failed_pins from staff where id = '${STAFF.ana}'`), '1', 'the wrong try is counted');
      assert.strictEqual(sql(`select count(*) from supplier_advances`), '2');
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, []);
    }
  },
  {
    name: 'the owner: a payment before receiving waits in favour; the invoice (Sin IVA / 13 %) applies it; a twin card payment asks first; in favour with a reason; a void',
    run: async ({ browser }) => {
      P.seed();
      const o = P.create(V.lac, [{ vi: P.vi(I.yogur), packs: 4 }]);
      const pg = await P.owner(browser, { hash: '#p=' + V.lac + '&t=pagos', wait: '#pgPay' });
      await pg.click('#pgPay'); await payForm(pg);
      assert.strictEqual(await pg.locator('#payPinBox').isVisible(), false, 'no PIN for the owner with the phone code');
      await pg.selectOption('#payPo', o.id);
      await pg.fill('#payAmt', '5000'); await pg.fill('#payRef', 'SNP-777');
      await save(pg);
      await P.toasted(pg, /^Pago guardado · queda esperando la factura$/, 'an advance before receiving');
      assert.strictEqual(sql(`select po_id from supplier_advances`), o.id);
      // the goods arrive; the invoice: «Sin IVA», then «13 %» (the person chooses); it applies the advance
      P.receive(o.id, [{ line: P.lineOf(o.id, I.yogur), rest: true }]);
      await pg.reload({ waitUntil: 'domcontentloaded' });
      await pg.waitForSelector('#pgInv');
      await P.seen(pg.locator('#fTab'), /Entregas sin factura Pedido Nº \d+ .* recibido ₡18 000/i, 'the delivery without invoice', 5000);
      await pg.click('#pgInv');
      await pg.waitForSelector('#invModal:not([hidden])');
      assert.strictEqual(await pg.locator('#invRecs input:checked').count(), 1, 'the only delivery ticked');
      assert.strictEqual(await pg.inputValue('#invNet'), '18000', 'the received value');
      await pg.click('#invIva0');
      await P.seen(pg.locator('#invTotal'), /^Total ₡18 000$/, 'no IVA', 3000);
      await pg.click('#invIva13');
      assert.strictEqual(await pg.inputValue('#invIva'), '2340');
      await P.seen(pg.locator('#invTotal'), /^Total ₡20 340$/, 'with 13 %', 3000);
      await pg.click('#invGo');
      await P.toasted(pg, /^Factura guardada · ₡20 340 · pagado ₡5 000 · pendiente ₡15 340$/, 'the invoice applied the advance');
      assert.strictEqual(sql(`select number like 'S/N-%' from supplier_invoices`), 't', 'no number: S/N');
      assert.strictEqual(sql(`select paid_from || ':' || amount_crc from supplier_payments`), 'advance:5000.00', 'applied as a payment from the advance');
      assert.strictEqual(ledger('suppay:'), '1160:-5000.00,2101:5000.00', 'Dr 2101 / Cr 1160');
      // a card payment, then one just like it: asked first
      for (let k = 0; k < 2; k++) {
        await pg.waitForSelector('#pgPay'); await pg.click('#pgPay'); await payForm(pg);
        await pg.selectOption('#payPo', o.id);
        await pg.locator('#payMethod button[data-m=card]').click();
        await pg.fill('#payAmt', '1000');
        await save(pg);
        if (k === 1) {
          await P.seen(pg.locator('#payErr'), /^Hace unos minutos se registró un pago igual a este\. ¿Es otro pago distinto\? Sí, es otro pago$/, 'a twin payment', 8000);
          assert.strictEqual(sql(`select count(*) from supplier_advances where method = 'card_debit'`), '1');
          await P.untoast(pg);
          await pg.locator('#payErr button', { hasText: 'Sí, es otro pago' }).click();
        }
        await P.toasted(pg, /^Pago guardado/, 'card payment ' + (k + 1));
      }
      assert.strictEqual(sql(`select count(*) from supplier_advances where method = 'card_debit'`), '2');
      // over the balance: the owner records it in favour, with a reason
      await pg.waitForSelector('#pgPay'); await pg.click('#pgPay'); await payForm(pg);
      await pg.selectOption('#payPo', o.id);
      await pg.fill('#payAmt', '20000'); await pg.fill('#payRef', 'SNP-778');
      await save(pg);
      await P.seen(pg.locator('#payErr'), /^Es más de lo que se debe: el saldo es ₡13 340\.$/, 'the balance shown', 8000);
      await pg.check('#payExcess');
      await save(pg);
      await P.seen(pg.locator('#payErr'), /^Escriba el motivo/, 'the reason is required', 3000);
      await pg.fill('#payExcessWhy', 'adelanto del próximo pedido');
      await save(pg);
      await P.toasted(pg, /^Pago guardado · ₡6 660 a favor$/, 'in favour');
      assert.match(advances(), /sinpe:20000\.00:SNP-778:adelanto del próximo pedido:false$/);
      await P.seen(pg.locator('#pgCredit'), /^₡6 660$/, 'the balance in favour', 8000);
      await P.nav(pg, '#', `#hubVendors .vcard[data-vendor="${V.lac}"]`);
      await P.seen(pg.locator(`#hubVendors .vcard[data-vendor="${V.lac}"]`), /Saldo a favor ₡6 660/, 'the hub badge «Saldo a favor»', 8000);
      await P.nav(pg, '#p=' + V.lac + '&t=pagos', '#pgPay');
      // the books door voids the SINPE payment in favour (no PIN): its entries are reversed, nothing deleted
      await pg.locator('#fTab .orow', { hasText: 'SNP-778' }).locator('button', { hasText: 'Anular' }).click();
      await pg.waitForSelector('#voidModal:not([hidden])');
      assert.strictEqual(await pg.locator('#voidPinBox').isVisible(), false);
      await pg.fill('#voidWhy', 'se registró dos veces');
      await pg.click('#voidGo');
      await P.toasted(pg, /^Pago anulado$/, 'voided');
      assert.match(advances(), /SNP-778:adelanto del próximo pedido:true$/);
      assert.strictEqual(sql(`select count(*) from supplier_advances`), '4', 'nothing deleted');
      await P.seen(pg.locator('#pgCredit'), /^₡0$/, 'nothing in favour now', 8000);
      await P.nav(pg, '#', `#hubVendors .vcard[data-vendor="${V.lac}"]`);
      await P.seen(pg.locator(`#hubVendors .vcard[data-vendor="${V.lac}"]`), /Debe ₡13 340/, 'the hub badge «Debe»', 8000);
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, []);
    }
  },
  {
    name: 'deliveries recorded on another device a moment ago: Pagos, the payment window and the invoice window read them (no 60-second old copy)',
    run: async ({ browser }) => {
      P.seed();
      const o1 = P.create(V.lac, [{ vi: P.vi(I.yogur), packs: 4 }]), o2 = P.create(V.lac, [{ vi: P.vi(I.yogur), packs: 2 }]), o3 = P.create(V.lac, [{ vi: P.vi(I.natilla), packs: 1 }]);
      const pg = await P.owner(browser, { hash: '#p=' + V.lac + '&t=pagos', wait: '#pgPay' });
      assert.strictEqual(await pg.locator('#pgInv').count(), 0, 'nothing received yet');
      // the door tablet receives order 1; the owner looks at it, then goes back to Pagos
      P.receive(o1.id, [{ line: P.lineOf(o1.id, I.yogur), rest: true }]);
      await P.nav(pg, '#pedido=' + o1.id, '#orderDoc');
      await P.nav(pg, '#p=' + V.lac + '&t=pagos', '#pgPay');
      await P.seen(pg.locator('#fTab'), new RegExp('Entregas sin factura Pedido Nº ' + o1.po_number + ' .* recibido ₡18 000'), 'Pagos shows the new delivery', 5000);
      assert.strictEqual(await pg.locator('#pgInv').count(), 1, '«Registrar factura» is offered');
      // order 2 arrives elsewhere: the payment window opened from its document knows it was received
      P.receive(o2.id, [{ line: P.lineOf(o2.id, I.yogur), rest: true }]);
      await P.nav(pg, '#pedido=' + o2.id, '#orderDoc');
      await pg.click('#docPay');
      await pg.waitForSelector('#payModal:not([hidden])');
      /* read once lang.js has translated the list (the page writes it in English first) */
      await until(async () => new RegExp('^Pedido Nº ' + o2.po_number + ' · Recibido').test(await pg.locator(`#payPo option[value="${o2.id}"]`).textContent()), 3000, 'the order as it is now, in Spanish: «Pedido Nº ' + o2.po_number + ' · Recibido»');
      await pg.click('#payCancel');
      // order 3 arrives elsewhere: the invoice window opened from its document has that delivery, ticked
      P.receive(o3.id, [{ line: P.lineOf(o3.id, I.natilla), rest: true }]);
      await P.nav(pg, '#pedido=' + o3.id, '#docInv');
      await pg.click('#docInv');
      await pg.waitForSelector('#invModal:not([hidden])');
      await P.seen(pg.locator('#invRecs'), new RegExp('Pedido Nº ' + o3.po_number + ' · '), 'the new delivery is listed', 3000);
      assert.strictEqual(await pg.locator('#invRecs input:checked').count(), 1, 'ticked');
      assert.strictEqual(await pg.inputValue('#invNet'), '6000', 'its received value');
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, []);
    }
  },
  {
    name: 'an invoice in dollars: the colones prefill leaves the boxes (typed in dollars, with the rate); back in colones it returns; every error has a text',
    run: async ({ browser }) => {
      P.seed();
      const o = P.create(V.lac, [{ vi: P.vi(I.yogur), packs: 4 }]);
      P.receive(o.id, [{ line: P.lineOf(o.id, I.yogur), rest: true }]);
      const pg = await P.owner(browser, { hash: '#p=' + V.lac + '&t=pagos', wait: '#pgInv' });
      await pg.click('#pgInv');
      await pg.waitForSelector('#invModal:not([hidden])');
      assert.strictEqual(await pg.inputValue('#invNet'), '18000', 'the received value in colones');
      await pg.click('#invIva13');
      assert.strictEqual(await pg.inputValue('#invIva'), '2340');
      await pg.selectOption('#invCur', 'USD');
      assert.strictEqual(await pg.inputValue('#invNet'), '', 'no colones amount left to read as dollars');
      assert.strictEqual(await pg.inputValue('#invIva'), '');
      await P.seen(pg.locator('#invFxBox'), /Escriba los montos de la factura en dólares\./, 'told to type the dollar amounts, in Spanish', 3000);
      await pg.fill('#invNet', '34.62');
      await pg.fill('#invFx', '520');
      await pg.click('#invIva13');
      assert.strictEqual(await pg.inputValue('#invIva'), '4.5');
      await P.seen(pg.locator('#invTotal'), /^Total \$39\.12 = ₡20 342,40$/, 'the dollar total and its colones', 3000);
      await pg.selectOption('#invCur', 'CRC');
      assert.strictEqual(await pg.inputValue('#invNet'), '18000', 'the colones prefill is back');
      assert.strictEqual(await pg.inputValue('#invIva'), '', 'the IVA is chosen again');
      assert.strictEqual(await pg.locator('#invFxBox').isVisible(), false);
      // an error code of the books (bad_account) has its own text, not «Algo salió mal»
      await pg.click('#invIva0');
      await pg.route('**/rest/v1/rpc/proveedor_factura_registrar', (r) => r.fulfill({ status: 200, contentType: 'application/json', body: '{"ok":false,"error":"bad_account"}' }), { times: 1 });
      await pg.click('#invGo');
      await P.seen(pg.locator('#invErr'), /^Una cuenta de la contabilidad no es válida\. Avise al contador\.$/, 'bad_account, in Spanish', 5000);
      assert.strictEqual(sql(`select count(*) from supplier_invoices`), '0');
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, []);
    }
  },
  {
    name: 'dollars chosen before the deliveries: ticking one never puts the colones total in the dollar subtotal, and the dollars typed stay',
    run: async ({ browser }) => {
      P.seed();
      const o1 = P.create(V.lac, [{ vi: P.vi(I.yogur), packs: 4 }]), o2 = P.create(V.lac, [{ vi: P.vi(I.natilla), packs: 1 }]);
      P.receive(o1.id, [{ line: P.lineOf(o1.id, I.yogur), rest: true }]);
      P.receive(o2.id, [{ line: P.lineOf(o2.id, I.natilla), rest: true }]);
      const pg = await P.owner(browser, { hash: '#p=' + V.lac + '&t=pagos', wait: '#pgInv' });
      await pg.click('#pgInv');
      await pg.waitForSelector('#invModal:not([hidden])');
      assert.strictEqual(await pg.locator('#invRecs input:checked').count(), 0, 'two deliveries: none ticked at first');
      await pg.selectOption('#invCur', 'USD');
      await pg.fill('#invFx', '520');
      await pg.locator('#invRecs input[type=checkbox]').first().check();
      assert.strictEqual(await pg.inputValue('#invNet'), '', 'ticked in dollars: no colones amount in the dollar box');
      await pg.fill('#invNet', '34.62');
      await pg.locator('#invRecs input[type=checkbox]').nth(1).check();
      assert.strictEqual(await pg.inputValue('#invNet'), '34.62', 'the dollars typed stay when another delivery is ticked');
      await pg.click('#invIva13');
      await P.seen(pg.locator('#invTotal'), /^Total \$39\.12 = ₡20 342,40$/, 'the dollar total and its colones', 3000);
      await pg.selectOption('#invCur', 'CRC');
      assert.strictEqual(await pg.inputValue('#invNet'), '24000', 'back in colones: the two deliveries\' received value');
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, []);
    }
  },
  {
    name: 'an invoice form typed in colones, and one in dollars, come back after the sign-in ends with the number, the amounts and the currency typed',
    run: async ({ browser }) => {
      P.seed();
      const o = P.create(V.lac, [{ vi: P.vi(I.yogur), packs: 4 }]);
      P.receive(o.id, [{ line: P.lineOf(o.id, I.yogur), rest: true }]);
      for (const usd of [false, true]) {
        const pg = await P.cafeManager(browser, { hash: '#p=' + V.lac + '&t=pagos', wait: '#pgInv' });
        await pg.click('#pgInv');
        await pg.waitForSelector('#invModal:not([hidden])');
        if (usd) { await pg.selectOption('#invCur', 'USD'); await pg.fill('#invFx', '520'); }
        await pg.fill('#invNum', usd ? 'INV-77' : 'F-1234');
        await pg.fill('#invNet', usd ? '34.62' : '17500');
        await pg.click('#invIva13');
        const iva = await pg.inputValue('#invIva');
        await pg.route('**/rest/v1/rpc/proveedor_factura_registrar', (r) => r.fulfill({ status: 401, contentType: 'application/json', body: '{"code":"PGRST301","message":"JWT expired"}' }), { times: 1 });
        await pg.evaluate(() => { for (const k of Object.keys(localStorage)) if (/^sb-.*-auth-token$/.test(k)) localStorage.removeItem(k); });
        await pg.click('#invGo');
        await pg.waitForSelector('#loginView:not([hidden])', { timeout: 10000 });
        await pg.fill('#em', 'cafe@test.local');
        await pg.fill('#pw', 'test');
        await pg.click('#loginForm button[type=submit]');
        await pg.waitForSelector('#turnoView:not([hidden])', { timeout: 10000 });
        await pg.click('#turnoOwner');
        await P.gate(pg, 'ana');
        await pg.waitForSelector('#invModal:not([hidden])', { timeout: 10000 });
        await P.toasted(pg, /volvió/, 'told what came back', 5000);
        const got = [await pg.inputValue('#invCur'), await pg.inputValue('#invNum'), await pg.inputValue('#invNet'), await pg.inputValue('#invIva'), usd ? await pg.inputValue('#invFx') : '-'];
        assert.deepStrictEqual(got, usd ? ['USD', 'INV-77', '34.62', iva, '520'] : ['CRC', 'F-1234', '17500', iva, '-'], (usd ? 'dollars' : 'colones') + ': everything typed is back, the number too');
        assert.strictEqual(sql(`select count(*) from supplier_invoices`), '0', 'nothing saved meanwhile');
        assert.deepStrictEqual(pg.errors, []);
        await pg.close();
      }
    }
  },
  {
    name: 'the invoice window: a Proveedores correction is shown inside the delivery it corrects (one row, its net value), and the invoice takes both; a number typed before ticking stays; with two deliveries both ticks come back after an expired sign-in',
    run: async ({ browser }) => {
      P.seed();
      const o = P.create(V.lac, [{ vi: P.vi(I.leche), packs: 2 }]);
      P.receive(o.id, [{ line: P.lineOf(o.id, I.leche), rest: true }]);
      const rc = sql(`select id from purchase_receipts where po_id = '${o.id}'`);
      P.asOwner(`select public.proveedor_recepcion_corregir('${rc}', gen_random_uuid(), jsonb_build_array(jsonb_build_object('line_id', '${P.lineOf(o.id, I.leche)}', 'packs_delta', -1)), 'Una caja venía vacía')`);
      const o2 = P.create(V.lac, [{ vi: P.vi(I.yogur), packs: 4 }]);
      P.receive(o2.id, [{ line: P.lineOf(o2.id, I.yogur), rest: true }]);
      const pg = await P.cafeManager(browser, { hash: '#p=' + V.lac + '&t=pagos', wait: '#pgInv' });
      await pg.click('#pgInv');
      await pg.waitForSelector('#invModal:not([hidden])');
      assert.strictEqual(await pg.locator('#invRecs [data-rec]').count(), 2, 'two deliveries; the correction is not a row of its own');
      await P.seen(pg.locator('#invRecs label').first(), /^Pedido Nº \d+ · .+ · ₡20 400 · corregido ₡-10 200 → ₡10 200$/, 'the correction inside its delivery', 3000);
      await pg.fill('#invNum', 'F-9');
      await pg.locator('#invRecs [data-rec]').first().check();
      assert.strictEqual(await pg.inputValue('#invNum'), 'F-9', 'the number typed before ticking stays');
      assert.strictEqual(await pg.inputValue('#invNet'), '10200', 'the delivery net of its correction');
      await pg.locator('#invRecs [data-rec]').nth(1).check();
      assert.strictEqual(await pg.inputValue('#invNet'), '28200', 'both deliveries');
      await pg.fill('#invNet', '28000');
      await pg.click('#invIva13');
      const iva = await pg.inputValue('#invIva');
      // the sign-in ends on «Guardar»: everything comes back, both ticks too
      await pg.route('**/rest/v1/rpc/proveedor_factura_registrar', (r) => r.fulfill({ status: 401, contentType: 'application/json', body: '{"code":"PGRST301","message":"JWT expired"}' }), { times: 1 });
      await pg.evaluate(() => { for (const k of Object.keys(localStorage)) if (/^sb-.*-auth-token$/.test(k)) localStorage.removeItem(k); });
      await pg.click('#invGo');
      await pg.waitForSelector('#loginView:not([hidden])', { timeout: 10000 });
      await pg.fill('#em', 'cafe@test.local'); await pg.fill('#pw', 'test');
      await pg.click('#loginForm button[type=submit]');
      await pg.waitForSelector('#turnoView:not([hidden])', { timeout: 10000 });
      await pg.click('#turnoOwner');
      await P.gate(pg, 'ana');
      await pg.waitForSelector('#invModal:not([hidden])', { timeout: 10000 });
      await P.toasted(pg, /volvió/, 'told what came back', 5000);
      assert.deepStrictEqual([await pg.locator('#invRecs [data-rec]:checked').count(), await pg.inputValue('#invNum'), await pg.inputValue('#invNet'), await pg.inputValue('#invIva')],
        [2, 'F-9', '28000', iva], 'both ticks, the number, the subtotal and the IVA are back');
      await pg.click('#invGo');
      await until(() => sql(`select count(*) from supplier_invoices`) === '1', 8000, 'the invoice saved');
      assert.strictEqual(sql(`select cardinality(receipt_ids) || '|' || received_crc from supplier_invoices`), '3|28200.00', 'the two deliveries and the correction, received ₡28 200');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'Contabilidad: the invoice form counts a Proveedores correction with its delivery (no false difference shown), and the supplier card names its payments in Spanish',
    run: async ({ browser }) => {
      P.seed();
      const o = P.create(V.lac, [{ vi: P.vi(I.leche), packs: 2 }]);
      P.receive(o.id, [{ line: P.lineOf(o.id, I.leche), rest: true }]);
      const rc = sql(`select id from purchase_receipts where po_id = '${o.id}'`);
      P.asOwner(`select public.proveedor_recepcion_corregir('${rc}', gen_random_uuid(), jsonb_build_array(jsonb_build_object('line_id', '${P.lineOf(o.id, I.leche)}', 'packs_delta', -1)), 'Una caja venía vacía')`);
      const drawer = (pg) => until(() => pg.evaluate(() => document.getElementById('drawer').classList.contains('open') && !document.querySelector('#drawerBody .loading')), 8000, 'the drawer open');
      const open = async () => {
        const pg = P.watchApi(await page(browser, { login: 'owner', aal: 'aal2', lang: 'es' }));
        await goto(pg, '/contabilidad');
        await pg.waitForSelector('#appView:not([hidden])', { timeout: 15000 });
        await pg.evaluate(() => { location.hash = 'proveedores'; });
        await until(async () => (await pg.locator('#tbl-prov tbody tr.row', { hasText: 'Lácteos Monteverde' }).count()) === 1, 10000, 'the supplier listed');
        await pg.locator('#tbl-prov tbody tr.row', { hasText: 'Lácteos Monteverde' }).click();
        await drawer(pg);
        return pg;
      };
      const pg = await open();
      await pg.click('#vc-inv');
      await drawer(pg);
      await until(() => pg.evaluate(() => !!document.querySelector('#drawerBody [data-rec]')), 8000, 'the delivery offered');
      assert.strictEqual(await pg.locator('#drawerBody [data-rec]').count(), 1, 'one row: the delivery (its correction goes with it)');
      await P.seen(pg.locator('#drawerBody label.check').first(), /₡20 400 · corregido −₡10 200 → ₡10 200$/, 'the correction shown inside the delivery, in Spanish', 3000);
      await pg.check('#drawerBody [data-rec]');
      await pg.fill('#vi-num', 'F-CORR'); await pg.fill('#vi-net', '10200'); await pg.fill('#vi-iva', '0');
      await P.seen(pg.locator('#vi-diff'), /^Recibido al costo ₡10 200 · diferencia con la factura ₡0$/, 'what the server will book: no difference', 3000);
      await pg.click('#vi-save');
      await until(() => sql(`select count(*) from supplier_invoices`) === '1', 8000, 'the invoice saved');
      assert.strictEqual(sql(`select cardinality(receipt_ids) || '|' || received_crc from supplier_invoices`), '2|10200.00', 'the delivery and its correction');
      assert.strictEqual(sql(`select count(*) from acct.lines l join acct.entries e on e.id = l.entry_id where e.source_key like 'supinv:%' and l.account = acct.map('price_variance')`), '0', 'no 5103');
      await pg.close();
      // a bank payment recorded in Contabilidad: the card's payments in Spanish
      P.asOwner(`select public.supplier_payment_save(jsonb_build_object('vendor_id', '${V.lac}', 'amount_crc', 10200, 'paid_from', 'bank', 'date', public.cr_today(), 'reference', 'TR-1'), gen_random_uuid())`);
      const p2 = await open();
      await P.seen(p2.locator('#drawerBody'), /Transferencia o SINPE/, 'the payment method in Spanish', 5000);
      assert.doesNotMatch(await text(p2.locator('#drawerBody')), /Bank transfer or SINPE/);
      assert.deepStrictEqual(pg.errors.concat(p2.errors), []);
    }
  },
  {
    name: '8.26 Contabilidad takes what was paid in Proveedores: «Nueva factura» applies a SINPE paid before it; «Registrar pago» applies one first and reopens the form (nothing paid twice); when that check fails, nothing is recorded and an invoice says they are still to be applied',
    run: async ({ browser }) => {
      P.seed();
      // (i) a SINPE recorded in Proveedores before the invoice (₡18 000 received + 13 %): it waits for the invoice
      const o1 = P.create(V.lac, [{ vi: P.vi(I.yogur), packs: 4 }]);
      P.receive(o1.id, [{ line: P.lineOf(o1.id, I.yogur), rest: true }]);
      const a1 = sinpe(o1.id, 20340, 'SNP-82601');
      assert.strictEqual(unapplied(a1), '20340.00', 'it waits for the invoice');
      let pg = await contab(browser);
      await pg.click('#vc-inv');
      await drawer(pg);
      await until(() => pg.evaluate(() => !!document.querySelector('#drawerBody [data-rec]')), 8000, 'the delivery offered');
      await pg.check('#drawerBody [data-rec]');
      await pg.fill('#vi-num', 'F-8261'); await pg.fill('#vi-net', '18000'); await pg.fill('#vi-iva', '2340');
      await P.untoast(pg);
      await pg.click('#vi-save');
      await P.toasted(pg, /^Factura guardada · ₡20 340 pagados en Proveedores aplicados a ella$/, 'the invoice took the SINPE, in Spanish');
      assert.strictEqual(openOf('F-8261'), '0.00', 'nothing left open on that invoice');
      assert.strictEqual(unapplied(a1), '0.00', 'the SINPE is all applied');
      assert.strictEqual(sql(`select paid_from || ':' || amount_crc from supplier_payments`), 'advance:20340.00', 'applied from the SINPE: no other payment');
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, []);
      await pg.close();
      // (ii) a SINPE of order 2, then its invoice saved by SQL (nothing applied it): «Registrar pago» applies it first
      const o2 = P.create(V.lac, [{ vi: P.vi(I.natilla), packs: 1 }]);
      P.receive(o2.id, [{ line: P.lineOf(o2.id, I.natilla), rest: true }]);
      const a2 = sinpe(o2.id, 5000, 'SNP-82602');
      invoiceBySql(o2.id, 'F-8262', 6000, 780);
      assert.strictEqual(unapplied(a2) + '|' + openOf('F-8262'), '5000.00|6780.00', 'a payment not applied and an open invoice');
      pg = await contab(browser);
      await pg.click('#vc-pay');
      await drawer(pg);
      await pg.waitForSelector('#vp-save');
      assert.strictEqual(await pg.inputValue('#vp-amt'), '6780', 'the open invoice proposed');
      await P.untoast(pg);
      await pg.click('#vp-save');
      await P.toasted(pg, /^₡5 000 pagados en Proveedores se aplicaron primero a las facturas de este proveedor\. Revise lo que todavía se debe\.$/, 'applied first, in Spanish');
      await until(async () => (await pg.locator('#vp-amt').count()) === 1 && (await pg.inputValue('#vp-amt')) === '1780', 8000, 'the payment form reopened with what is still owed (₡1 780)');
      await P.seen(pg.locator('#drawerTitle'), /^Pagar a Lácteos Monteverde$/, 'the payment form, in Spanish', 3000);
      assert.strictEqual(bankPays(), '', 'nothing recorded from the bank yet');
      assert.strictEqual(unapplied(a2) + '|' + openOf('F-8262'), '0.00|1780.00', 'the SINPE went to the invoice');
      // the rest, recorded from the reopened form: once
      await P.untoast(pg);
      await pg.click('#vp-save');
      await P.toasted(pg, /^Pago registrado$/, 'the payment recorded');
      assert.strictEqual(bankPays(), '1780.00', 'one bank payment, of what was still owed');
      assert.strictEqual(openOf('F-8262'), '0.00');
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, []);
      await pg.close();
      // (iii) Proveedores' check fails (500): «Registrar pago» records nothing; an invoice saved meanwhile says so
      const o3 = P.create(V.lac, [{ vi: P.vi(I.queso), packs: 1 }]);
      P.receive(o3.id, [{ line: P.lineOf(o3.id, I.queso), rest: true }]);
      const a3 = sinpe(o3.id, 3000, 'SNP-82603');
      invoiceBySql(o3.id, 'F-8263', 5200, 0);
      const o4 = P.create(V.lac, [{ vi: P.vi(I.crema), packs: 1 }]);
      P.receive(o4.id, [{ line: P.lineOf(o4.id, I.crema), rest: true }]);
      pg = await contab(browser);
      const FAIL = '**/rest/v1/rpc/proveedor_anticipos_aplicar';
      await pg.route(FAIL, (r) => r.fulfill({ status: 500, contentType: 'application/json', body: '{"code":"XX000","details":null,"hint":null,"message":"prueba: el servidor falló"}' }));
      await pg.click('#vc-pay');
      await drawer(pg);
      await pg.waitForSelector('#vp-save');
      const rows = sql(`select count(*) from supplier_payments`);
      await pg.click('#vp-save');
      await P.seen(pg.locator('#drawerFoot .err'), /^No se pudieron revisar los pagos hechos en Proveedores, así que no se registró nada\. Intente de nuevo\.$/, 'the payment stops, in Spanish', 8000);
      assert.strictEqual(sql(`select count(*) from supplier_payments`), rows, 'nothing recorded');
      assert.strictEqual(bankPays(), '1780.00', 'no new bank payment');
      assert.strictEqual(unapplied(a3) + '|' + openOf('F-8263'), '3000.00|5200.00', 'nothing applied either');
      await pg.click('#vp-cancel');
      await pg.waitForSelector('#vc-inv');
      await drawer(pg);
      await pg.click('#vc-inv');
      await drawer(pg);
      await until(() => pg.evaluate(() => !!document.querySelector('#drawerBody [data-rec]')), 8000, 'the delivery offered');
      assert.strictEqual(await pg.locator('#drawerBody [data-rec]').count(), 1, 'order 4\'s delivery only');
      await pg.check('#drawerBody [data-rec]');
      await pg.fill('#vi-num', 'F-8264'); await pg.fill('#vi-net', '2100'); await pg.fill('#vi-iva', '273');
      await P.untoast(pg);
      await pg.click('#vi-save');
      await P.toasted(pg, /^Factura guardada · los pagos hechos en Proveedores todavía no se pudieron aplicar: se aplican en la próxima factura o pago de este proveedor$/, 'the invoice saved, its Proveedores payments still to apply, in Spanish');
      assert.strictEqual(openOf('F-8264'), '2373.00', 'the invoice is saved, not failed');
      assert.strictEqual(unapplied(a3), '3000.00', 'still to be applied');
      assert.ok(pg.apiErrors.length === 2 && pg.apiErrors.every((e) => /^500 rpc\/proveedor_anticipos_aplicar$/.test(e)), 'only the two failed checks: ' + pg.apiErrors.join('; '));
      // Proveedores answers again: the next payment applies the SINPE first
      await pg.unroute(FAIL);
      await pg.waitForSelector('#vc-pay');
      await drawer(pg);
      await pg.click('#vc-pay');
      await drawer(pg);
      await pg.waitForSelector('#vp-save');
      await P.untoast(pg);
      await pg.click('#vp-save');
      await P.toasted(pg, /^₡3 000 pagados en Proveedores se aplicaron primero a las facturas de este proveedor\./, 'applied on the next payment');
      assert.strictEqual(unapplied(a3) + '|' + openOf('F-8263') + '|' + bankPays(), '0.00|2200.00|1780.00', 'to its order\'s invoice; still no new bank payment');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: '8.26 without Proveedores\' function (before 0040 is applied, or after reversion-0040.sql with these pages published): Contabilidad records a payment and an invoice as before (PostgREST\'s 404 PGRST202, then its 42883)',
    run: async ({ browser }) => {
      P.seed();
      const o1 = P.create(V.lac, [{ vi: P.vi(I.yogur), packs: 1 }]);
      P.receive(o1.id, [{ line: P.lineOf(o1.id, I.yogur), rest: true }]);
      invoiceBySql(o1.id, 'F-8271', 4500, 585);
      const o2 = P.create(V.lac, [{ vi: P.vi(I.natilla), packs: 1 }]);
      P.receive(o2.id, [{ line: P.lineOf(o2.id, I.natilla), rest: true }]);
      const pg = await contab(browser);
      const FN = '**/rest/v1/rpc/proveedor_anticipos_aplicar';
      const missing = (code, message, hint) => (r) => r.fulfill({ status: 404, contentType: 'application/json', body: JSON.stringify({ code, details: null, hint, message }) });
      await pg.route(FN, missing('PGRST202', 'Could not find the function public.proveedor_anticipos_aplicar(p_vendor_id) in the schema cache', null));
      await pg.click('#vc-pay');
      await drawer(pg);
      await pg.waitForSelector('#vp-save');
      assert.strictEqual(await pg.inputValue('#vp-amt'), '5085', 'the open invoice proposed');
      await P.untoast(pg);
      await pg.click('#vp-save');
      await P.toasted(pg, /^Pago registrado$/, 'the payment recorded as before 0040, in Spanish');
      assert.strictEqual(bankPays(), '5085.00', 'one bank payment');
      assert.strictEqual(openOf('F-8271'), '0.00', 'the invoice paid');
      // the function missing while PostgREST's schema cache is still stale: 42883
      await pg.unroute(FN);
      await pg.route(FN, missing('42883', 'function public.proveedor_anticipos_aplicar(p_vendor_id => uuid) does not exist', 'No function matches the given name and argument types. You might need to add explicit type casts.'));
      await pg.waitForSelector('#vc-inv');
      await drawer(pg);
      await pg.click('#vc-inv');
      await drawer(pg);
      await until(() => pg.evaluate(() => !!document.querySelector('#drawerBody [data-rec]')), 8000, 'the delivery offered');
      await pg.check('#drawerBody [data-rec]');
      await pg.fill('#vi-num', 'F-8272'); await pg.fill('#vi-net', '6000'); await pg.fill('#vi-iva', '780');
      await P.untoast(pg);
      await pg.click('#vi-save');
      await P.toasted(pg, /^Factura guardada$/, 'the invoice saved as before 0040 (no «todavía no se pudieron aplicar»)');
      assert.strictEqual(openOf('F-8272'), '6780.00', 'the invoice is open');
      assert.deepStrictEqual(pg.apiErrors, ['404 rpc/proveedor_anticipos_aplicar', '404 rpc/proveedor_anticipos_aplicar'], 'only the two checks answered «missing»');
      assert.deepStrictEqual(pg.errors, []);
      await pg.close();
    }
  },
  {
    name: '8.26 voiding in Contabilidad a payment applied from Proveedores asks first (only the application is undone): dismissed → nothing voided; accepted, with the reason → voided, the Proveedores payment stays',
    run: async ({ browser }) => {
      P.seed();
      const o = P.create(V.lac, [{ vi: P.vi(I.yogur), packs: 4 }]);
      P.receive(o.id, [{ line: P.lineOf(o.id, I.yogur), rest: true }]);
      const a = sinpe(o.id, 20340, 'SNP-82604');
      invoiceBySql(o.id, 'F-8265', 18000, 2340);
      assert.strictEqual(P.asOwner(`select public.proveedor_anticipos_aplicar('${V.lac}')`).applied_crc, 20340, 'applied to the invoice');
      const sp = sql(`select id from supplier_payments where paid_from = 'advance'`);
      const pg = await contab(browser, 'accountant');
      const voidBtn = pg.locator(`#drawerBody [data-voidpay="${sp}"]`);
      assert.strictEqual(await voidBtn.getAttribute('data-adv'), '1', 'marked as applied from Proveedores');
      const asked = [];
      pg.onDialog = async (d) => { asked.push(d.type() + ': ' + d.message()); await d.dismiss(); };
      await voidBtn.click();
      await until(() => asked.length === 1, 5000, 'the confirm');
      await pg.waitForTimeout(400);
      const ADV = 'confirm: Esto solo deshace la aplicación: el pago de Proveedores queda sin aplicar y no vuelve a esta factura. Para anular el pago mismo, use Proveedores › Pagos.';
      assert.deepStrictEqual(asked, [ADV], 'asked first, in Spanish; dismissed: no reason asked');
      assert.strictEqual(sql(`select (voided_at is null) || '|' || public._invoice_open('${sql(`select id from supplier_invoices where number = 'F-8265'`)}') from supplier_payments where id = '${sp}'`), 'true|0.00', 'nothing voided');
      // accepted, and the reason given
      pg.onDialog = async (d) => { asked.push(d.type() + ': ' + d.message()); if (d.type() === 'prompt') await d.accept('aplicado a la factura equivocada'); else await d.accept(); };
      await P.untoast(pg);
      await voidBtn.click();
      await P.toasted(pg, /^Pago anulado$/, 'voided, in Spanish');
      assert.deepStrictEqual(asked, [ADV, ADV, 'prompt: ¿Por qué se anula este pago?']);
      assert.strictEqual(sql(`select (voided_at is not null) || '|' || void_reason from supplier_payments where id = '${sp}'`), 'true|aplicado a la factura equivocada');
      // only the application is undone: the Proveedores payment stays live and unapplied, the invoice is owed again, and the
      // payment never goes back to that invoice
      assert.strictEqual(sql(`select voided_at is null from supplier_advances where id = '${a}'`), 't', 'the Proveedores payment is not voided');
      assert.strictEqual(unapplied(a) + '|' + openOf('F-8265'), '20340.00|20340.00');
      assert.strictEqual(P.asOwner(`select public.proveedor_anticipos_aplicar('${V.lac}')`).applied_crc, 0, 'not to that invoice again');
      assert.strictEqual(sql(`select count(*) from supplier_payments`), '1', 'nothing deleted');
      await until(async () => (await pg.locator(`#drawerBody [data-voidpay="${sp}"]`).count()) === 0, 8000, 'the card shows it voided');
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, []);
    }
  },
  {
    name: 'the employee never sees money or SINPE: their supplier view lists only the orders to receive',
    run: async ({ browser }) => {
      P.seed(); P.clockIn('luis');
      P.asOwner(`select public.proveedor_guardar('{"id":"${V.lac}","sinpe":"8888 1111 Lácteos MV"}')`);
      const o = P.create(V.lac, [{ vi: P.vi(I.leche), packs: 2 }]);
      P.receive(o.id, [{ line: P.lineOf(o.id, I.leche), packs: 1 }]);
      P.asOwner(`select public.proveedor_pago_registrar('{"vendor_id":"${V.lac}","po_id":"${o.id}","amount":5000,"method":"sinpe","reference":"SNP-1"}', gen_random_uuid())`);
      const pg = await P.employee(browser, 'luis', { hash: '#p=' + V.lac });
      await P.seen(pg.locator('#main'), /^Pedidos por recibir › Lácteos Monteverde Lácteos Monteverde Pedido Nº \d+ Lácteos Monteverde · enviado .* · 1 de 1 líneas pendientes Recibir$/, 'only the orders', 8000);
      await pg.click(`#main a[href="#recibir=${o.id}"]`);
      await pg.waitForSelector('#recvCard');
      const t = await text(pg.locator('#appView'));
      assert.doesNotMatch(t, /SINPE|8888|Pagos|Pagado|Saldo|Total|₡5 000|₡20 400|Registrar pago|Registrar factura/, t);
      // and the server answers money questions with «locked» to the work session
      const tok = await pg.evaluate(() => Object.values(JSON.parse(localStorage.getItem('hg-turnos')))[0].token);
      const r = await pg.evaluate(async ([tk, vid]) => {
        const cfg = window.HG_CONFIG, s = JSON.parse(localStorage.getItem('sb-127-auth-token'));
        const call = async (fn, body) => (await fetch(cfg.url + '/rest/v1/rpc/' + fn, { method: 'POST', headers: { 'Content-Type': 'application/json', apikey: cfg.key, Authorization: 'Bearer ' + s.access_token }, body: JSON.stringify(body) })).json();
        return { ficha: await call('proveedor_ficha', { p_vendor_id: vid, p_token: tk }), pay: await call('proveedor_pago_registrar', { p_payment: { vendor_id: vid, amount: 1, method: 'card_debit' }, p_request_id: crypto.randomUUID() }) };
      }, [tok, V.lac]);
      assert.deepStrictEqual(Object.keys(r.ficha).sort(), ['mode', 'ok', 'orders', 'vendor']);
      assert.deepStrictEqual(Object.keys(r.ficha.vendor).sort(), ['id', 'name']);
      assert.strictEqual(r.pay.error, 'locked');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'the accountant (the books door): Pagos first, no Pedir; payments and invoices without PIN; the supplier edit is the SINPE only',
    run: async ({ browser }) => {
      P.seed();
      const o = P.create(V.lac, [{ vi: P.vi(I.leche), packs: 1 }]);
      P.receive(o.id, [{ line: P.lineOf(o.id, I.leche), rest: true }]);
      const pg = P.watchApi(await page(browser, { login: 'accountant', aal: 'aal2', lang: 'es' }));
      await goto(pg, '/proveedores#p=' + V.lac);
      await pg.waitForSelector('#pgPay', { timeout: 15000 });
      assert.match(await text(pg.locator('#modeBar')), /^Contabilidad: facturas y pagos\./);
      assert.deepStrictEqual(await pg.locator('.ftabs a').allInnerTexts(), ['Pedidos', 'Pagos', 'Productos']);
      await pg.click('#fEditBtn');
      assert.deepStrictEqual(await pg.locator('#vendorForm input').evaluateAll((l) => l.map((i) => i.id)), ['vfSinpe']);
      await pg.fill('#vfSinpe', '8888 2222 Lácteos');
      await pg.click('#vendorForm button[type=submit]');
      await P.toasted(pg, /^Proveedor guardado$/, 'the SINPE saved by the accountant');
      assert.strictEqual(sql(`select sinpe from vendor_pay_info where vendor_id = '${V.lac}'`), '8888 2222 Lácteos');
      await pg.waitForSelector('#pgInv');
      await pg.click('#pgInv');
      await pg.waitForSelector('#invModal:not([hidden])');
      await pg.click('#invIva13');
      await pg.click('#invGo');
      await P.toasted(pg, /^Factura guardada · ₡11 526 · pendiente ₡11 526$/, 'the invoice');
      await pg.waitForSelector('#pgPay'); await pg.click('#pgPay');
      await pg.waitForSelector('#payModal:not([hidden])');
      assert.strictEqual(await pg.locator('#payPinBox').isVisible(), false, 'no PIN: no staff identity at the books door');
      await pg.selectOption('#payPo', o.id);
      assert.strictEqual(await pg.inputValue('#payAmt'), '11526');
      await pg.fill('#payRef', 'BN-2026-1105');
      await pg.click('#payGo');
      await P.toasted(pg, /^Pago guardado$/, 'paid');
      assert.strictEqual(sql(`select public._invoice_open(id) from supplier_invoices`), '0.00');
      // ordering is management's: the accountant cannot create an order
      const r = await pg.evaluate(async (vid) => {
        const cfg = window.HG_CONFIG, s = JSON.parse(localStorage.getItem('sb-127-auth-token'));
        return (await fetch(cfg.url + '/rest/v1/rpc/proveedor_pedido_crear', { method: 'POST', headers: { 'Content-Type': 'application/json', apikey: cfg.key, Authorization: 'Bearer ' + s.access_token },
          body: JSON.stringify({ p_vendor_id: vid, p_lines: [], p_note: null, p_request_id: crypto.randomUUID() }) })).json();
      }, V.lac);
      assert.strictEqual(r.error, 'locked');
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, []);
    }
  },
  {
    name: '8.27 the server itself (0040) applies the Proveedores payments first and refuses their SINPE numbers, whatever calls it: «Registrar pago» without the page\'s own pre-apply (404 PGRST202, a page from before this version) still never pays twice; a bank payment with a Proveedores SINPE number is refused, nothing recorded',
    run: async ({ browser }) => {
      P.seed();
      // (i) a SINPE of ₡5 000 recorded in Proveedores for order 1 (₡6 000 + 13 %), its invoice saved by SQL: nothing applied it
      const o1 = P.create(V.lac, [{ vi: P.vi(I.natilla), packs: 1 }]);
      P.receive(o1.id, [{ line: P.lineOf(o1.id, I.natilla), rest: true }]);
      const a1 = sinpe(o1.id, 5000, 'SNP-82701');
      invoiceBySql(o1.id, 'F-8271', 6000, 780);
      assert.strictEqual(unapplied(a1) + '|' + openOf('F-8271'), '5000.00|6780.00', 'a payment not applied and an open invoice');
      let pg = await contab(browser);
      // this page's own pre-apply does nothing (the function «missing», as a page from before this version sees it)
      const FN = '**/rest/v1/rpc/proveedor_anticipos_aplicar';
      await pg.route(FN, (r) => r.fulfill({ status: 404, contentType: 'application/json', body: JSON.stringify({ code: 'PGRST202', details: null, hint: null, message: 'Could not find the function public.proveedor_anticipos_aplicar(p_vendor_id) in the schema cache' }) }));
      await pg.click('#vc-pay');
      await drawer(pg);
      await pg.waitForSelector('#vp-save');
      assert.strictEqual(await pg.inputValue('#vp-amt'), '6780', 'the whole invoice proposed: this page knows nothing of the SINPE');
      await P.untoast(pg);
      await pg.click('#vp-save');
      await P.toasted(pg, /^₡5 000 pagados en Proveedores se aplicaron primero a las facturas de este proveedor\. Revise lo que todavía se debe\.$/, 'the SERVER applied the SINPE first, in Spanish');
      await until(async () => (await pg.locator('#vp-amt').count()) === 1 && (await pg.inputValue('#vp-amt')) === '1780', 8000, 'the payment form reopened with the remainder (₡1 780)');
      await P.seen(pg.locator('#drawerTitle'), /^Pagar a Lácteos Monteverde$/, 'the payment form, in Spanish', 3000);
      assert.strictEqual(bankPays(), '', 'no bank row: the ₡6 780 were not paid again');
      assert.strictEqual(unapplied(a1) + '|' + openOf('F-8271'), '0.00|1780.00', 'the SINPE went to the invoice');
      assert.strictEqual(ledger('suppay:'), '1160:-5000.00,2101:5000.00', 'Dr 2101 / Cr 1160, by the server');
      // the remainder, from the reopened form: once
      await P.untoast(pg);
      await pg.click('#vp-save');
      await P.toasted(pg, /^Pago registrado$/, 'the remainder recorded');
      assert.strictEqual(bankPays() + '|' + openOf('F-8271'), '1780.00|0.00', 'one bank payment, of what was still owed');
      assert.deepStrictEqual(pg.apiErrors, ['404 rpc/proveedor_anticipos_aplicar', '404 rpc/proveedor_anticipos_aplicar'], 'only the two pre-applies answered «missing»');
      assert.deepStrictEqual(pg.errors, []);
      await pg.close();
      // (ii) order 2's invoice; a bank payment whose reference is that SINPE number (other letters, a space): refused by the
      // server, nothing recorded; with its own number it goes through
      const o2 = P.create(V.lac, [{ vi: P.vi(I.queso), packs: 1 }]);
      P.receive(o2.id, [{ line: P.lineOf(o2.id, I.queso), rest: true }]);
      invoiceBySql(o2.id, 'F-8272', 5200, 0);
      pg = await contab(browser);
      await pg.click('#vc-pay');
      await drawer(pg);
      await pg.waitForSelector('#vp-save');
      assert.strictEqual(await pg.inputValue('#vp-amt'), '5200', 'the open invoice proposed');
      await pg.fill('#vp-ref', 'snp 82701');
      await pg.click('#vp-save');
      await P.seen(pg.locator('#drawerFoot .err'), /^Ese número de SINPE ya está registrado en Proveedores: la misma transferencia no se registra dos veces\.$/, 'refused, in Spanish', 8000);
      assert.strictEqual(bankPays() + '|' + openOf('F-8272'), '1780.00|5200.00', 'nothing recorded');
      assert.strictEqual(sql(`select count(*) from supplier_payments`), '2', 'the applied SINPE and the one bank payment, nothing more');
      await pg.fill('#vp-ref', 'TR-8272');
      await P.untoast(pg);
      await pg.click('#vp-save');
      await P.toasted(pg, /^Pago registrado$/, 'with its own reference');
      assert.strictEqual(bankPays() + '|' + openOf('F-8272'), '1780.00,5200.00|0.00');
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, []);
    }
  },
  {
    name: '8.27 Gastos: paying a credit expense by bank with a number that is a Proveedores SINPE is refused by the server (expense_pay, 0040), nothing recorded; with its own reference it goes through',
    run: async ({ browser }) => {
      P.seed();
      const o = P.create(V.lac, [{ vi: P.vi(I.natilla), packs: 1 }]);
      P.receive(o.id, [{ line: P.lineOf(o.id, I.natilla), rest: true }]);
      sinpe(o.id, 5000, 'SNP-82702');
      // a credit expense of the same supplier, recorded by the owner with the phone code as the page would
      const made = P.asOwner(`select public.expense_save(jsonb_build_object('vendor_id', '${V.lac}', 'description', 'Hielo', 'account', '5101', 'amount_crc', 5000, 'iva_crc', 0, 'paid_from', 'credit', 'date', public.cr_today()::text), gen_random_uuid())`);
      assert.ok(made && made.ok, 'expense_save: ' + JSON.stringify(made));
      const pg = P.watchApi(await page(browser, { login: 'owner', aal: 'aal2', lang: 'es' }));
      await goto(pg, '/contabilidad');
      await pg.waitForSelector('#appView:not([hidden])', { timeout: 15000 });
      await pg.evaluate(() => { location.hash = 'gastos'; });
      await until(async () => (await pg.locator('#tbl-gastos [data-act=pay]').count()) === 1, 10000, 'the credit expense with its «Pagar»');
      await pg.click('#tbl-gastos [data-act=pay]');
      await drawer(pg);
      await pg.waitForSelector('#pf-save');
      await P.seen(pg.locator('#drawerTitle'), /^Pagar gasto a crédito$/, 'the form, in Spanish', 3000);
      assert.strictEqual(await pg.inputValue('#pf-amt'), '5000', 'what is owed proposed');
      await pg.selectOption('#pf-pm', 'bank');
      await pg.fill('#pf-ref', 'SNP-82702');
      await pg.click('#pf-save');
      await P.seen(pg.locator('#drawerFoot .err'), /^Ese número de SINPE ya está registrado en Proveedores: la misma transferencia no se registra dos veces\.$/, 'refused, in Spanish', 8000);
      assert.strictEqual(sql(`select count(*) from expense_payments`), '0', 'nothing recorded');
      assert.strictEqual(sql(`select count(*) from acct.entries where source_key like 'exppay:%'`), '0', 'no entry');
      assert.strictEqual(sql(`select public._expense_open(id) from expenses`), '5000.00', 'still owed');
      await pg.fill('#pf-ref', 'TR-82702');
      await P.untoast(pg);
      await pg.click('#pf-save');
      await P.toasted(pg, /^Pago registrado/, 'recorded with its own reference, in Spanish');
      assert.strictEqual(sql(`select count(*) || '|' || string_agg(paid_from || ':' || reference, ',') from expense_payments`), '1|bank:TR-82702');
      assert.strictEqual(sql(`select public._expense_open(id) from expenses`), '0.00', 'settled');
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, []);
    }
  }
];
