/* Proveedores (D-067, 0040) · payments: SINPE needs its confirmation number (refused without it; the same number twice
   is refused, also written with spaces or dashes); a card with an optional reference; partial → «Parcialmente pagado»,
   full → «Pagado»; a payment before receiving (an advance) that the invoice applies («Registrar factura» with the 13 % /
   «Sin IVA» buttons); over the balance: refused for a manager, the owner may record it in favour with a reason; a card
   payment just like the last one asks first; a payment voided by the books door; the employee never sees money; the
   accountant (the books door: Pagos first, no ordering, no PIN, the SINPE only in the supplier's edit). */
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
      assert.strictEqual(await pg.inputValue('#payAmt'), '20400', 'the balance proposed');
      assert.strictEqual(await pg.locator('#payMethod button[data-m=sinpe]').getAttribute('aria-pressed'), 'true', 'SINPE first');
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
      await P.toasted(pg, /^Pago guardado · ₡10 000 a favor$/, 'saved (no invoice yet: it waits in favour)');
      assert.strictEqual(advances(), 'sinpe:10000.00:12345678:-:false');
      assert.strictEqual(ledger('supadv:'), '1110:-10000.00,1160:10000.00', 'Dr 1160 anticipos / Cr 1110 bank');
      await P.seen(pg.locator('#orderDoc .dh'), /Parcialmente pagado$/, 'partly paid', 8000);
      // the same SINPE number again, with spaces and a dash: refused, it says where it is
      await pg.click('#docPay'); await payForm(pg);
      assert.strictEqual(await pg.inputValue('#payAmt'), '10400');
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
      await pg.fill('#payPin', PINS.ana);
      await save(pg);
      await P.toasted(pg, /^Pago guardado/, 'the card payment');
      assert.strictEqual(advances(), 'sinpe:10000.00:12345678:-:false,card_debit:10400.00:-:-:false');
      await P.seen(pg.locator('#orderDoc .dh'), /Recibido Pagado$/, 'paid', 8000);
      // more than the balance (the IVA allowance before the invoice: 20 400 × 13 % = ₡2 652): a manager cannot
      await pg.click('#docPay'); await payForm(pg);
      await pg.fill('#payAmt', '5000'); await pg.fill('#payRef', 'SNP-99881'); await pg.fill('#payPin', PINS.ana);
      await save(pg);
      await P.seen(pg.locator('#payErr'), /^Es más de lo que se debe: el saldo es ₡2 652\. Solo el dueño puede registrar un pago mayor que el saldo\.$/, 'over the balance', 8000);
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
      await P.toasted(pg, /^Pago guardado · ₡5 000 a favor$/, 'an advance before receiving');
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
  }
];
