/* Proveedores (D-067) · the order document: «Pedido Nº n» and its pills; Copiar (the supplier's text: supplier, products,
   quantities, note; no prices, staff, SINPE or internal ids), PDF (a real PDF from the page's own writer: its bytes, its
   text, its pages) and Imprimir (window.print; printed as A4: one page for a short order, no blank page after a long
   one, nothing of the page around it); editing before and after a partial delivery (the audit history); «changed»
   from another device; cancel; close what is pending. */
'use strict';
const assert = require('assert');
const fs = require('fs');
const { goto, until, sql, SITE } = require('../lib');
const P = require('../prov');
const { V, I, text } = P;

function short() {
  P.asOwner(`select public.proveedor_guardar('{"id":"${V.lac}","sinpe":"8888 1111 Lácteos MV"}')`);
  return P.create(V.lac, [{ vi: P.vi(I.leche), packs: 2 }, { vi: P.vi(I.yogur), packs: 3 }, { vi: P.vi(I.queso), packs: 2.5 }], { note: 'Entregar por la puerta de atrás' });
}
/* the open document and its PDF bytes (the download the PDF button makes) */
async function pdfOf(pg) {
  const [dl] = await Promise.all([pg.waitForEvent('download', { timeout: 10000 }), pg.click('#docPdf')]);
  return { name: dl.suggestedFilename(), bytes: fs.readFileSync(await dl.path()) };
}
/* the page as the browser prints it (A4, the page's own @page rule) */
async function printed(pg) {
  await pg.emulateMedia({ media: 'print' });
  // what is laid out on paper: #printDoc and nothing else (the nav, the header, the buttons, the toast, the pill: none)
  const css = await pg.evaluate(() => ({
    shown: Array.prototype.filter.call(document.body.children, (e) => !/^(SCRIPT|STYLE|TEMPLATE)$/.test(e.tagName) && e.getClientRects().length > 0).map((e) => e.id || e.className || e.tagName),
    nav: document.querySelector('.pagenav').getClientRects().length,
    buttons: Array.prototype.filter.call(document.querySelectorAll('button, a'), (e) => e.getClientRects().length > 0).length
  }));
  const pdf = P.pdfRead(await pg.pdf({ preferCSSPageSize: true, printBackground: true }));
  await pg.emulateMedia({ media: 'screen' });
  return { css, pdf };
}

module.exports.tests = [
  {
    name: 'Copiar: the supplier\'s text only (no prices, staff, SINPE or ids); PDF: a real PDF with the lines; Imprimir: one A4 page, nothing around it',
    run: async ({ browser }) => {
      P.seed();
      const o = short();
      const pg = await P.owner(browser, { hash: '#pedido=' + o.id, wait: '#orderDoc' });
      await P.seen(pg.locator('#orderDoc .dh'), new RegExp('^Pedido Nº ' + o.po_number + ' Creado Pago pendiente$'), 'the number and the two pills, in Spanish', 5000);
      const doc = await text(pg.locator('#docLines'));
      assert.match(doc, /Leche entera cód\. LE-12 caja de 12 · 12 unidades 2 ₡10 200 ₡20 400/, doc);
      assert.match(doc, /Queso turrialba 1 kg 2,5 ₡5 200 ₡13 000/, doc);
      assert.match(await text(pg.locator('#orderDoc .tot')), /^Total estimado ₡46 900 sin IVA$/);
      // Copiar
      await pg.context().grantPermissions(['clipboard-read', 'clipboard-write'], { origin: SITE });
      await pg.click('#docCopy');
      await P.toasted(pg, /^Copiado$/, 'copied, in Spanish');
      const copied = await pg.evaluate(() => navigator.clipboard.readText());
      const fecha = sql(`select extract(day from now() at time zone 'America/Costa_Rica')::int || ' ' || (array['ene','feb','mar','abr','may','jun','jul','ago','set','oct','nov','dic'])[extract(month from now() at time zone 'America/Costa_Rica')::int] || ' ' || extract(year from now() at time zone 'America/Costa_Rica')::int`);
      assert.strictEqual(copied, [`Pedido Nº ${o.po_number} · Hanging Garden Café`, 'Proveedor: Lácteos Monteverde', 'Fecha: ' + fecha, '',
        '• 2 × caja de 12 — Leche entera (cód. LE-12)', '• 3 × paquete de 6 — Yogur natural', '• 2,5 kg — Queso turrialba', '',
        'Nota: Entregar por la puerta de atrás', '', `Por favor indique el Nº ${o.po_number} en la factura. Gracias.`].join('\n'));
      assert.doesNotMatch(copied, /₡|CRC|SINPE|8888 1111|Dueño|Ana|[0-9a-f]{8}-[0-9a-f]{4}-/, 'no prices, staff, SINPE or ids');
      // PDF
      const f = await pdfOf(pg);
      assert.strictEqual(f.name, `Pedido-${o.po_number}-lacteos-monteverde.pdf`);
      const pdf = P.pdfRead(f.bytes);
      assert.strictEqual(pdf.head, '%PDF-1.4');
      assert.ok(pdf.eof, 'ends with %%EOF');
      assert.strictEqual(pdf.pages.length, 1);
      const t = pdf.pages[0].text;
      for (const s of ['Hanging Garden Café', 'PEDIDO Nº ' + o.po_number, 'Proveedor: Lácteos Monteverde · Rosa Jiménez · 2645 1111 · ventas@lacteos.test',
                       'Leche entera (cód. LE-12)', 'caja de 12', 'CRC 10 200', 'CRC 20 400', 'Queso turrialba', '2,5', 'Total estimado (sin IVA): CRC 46 900',
                       'Nota: Entregar por la puerta de atrás', 'Página 1 de 1']) assert.ok(t.includes(s), 'the PDF says «' + s + '»:\n' + t);
      assert.doesNotMatch(t, /SINPE|8888 1111|Dueño|Creado|Pago pendiente/, 'no payment data, staff or pills');
      // without prices: the price columns and the total leave the PDF
      await pg.uncheck('#docPrices');
      const t2 = P.pdfRead((await pdfOf(pg)).bytes).pages[0].text;
      assert.ok(!/CRC/.test(t2) && t2.includes('Leche entera (cód. LE-12)'), 'no prices:\n' + t2);
      await pg.check('#docPrices');
      // Imprimir: the browser's print of #printDoc only, one A4 page
      await pg.click('#docPrint');
      assert.strictEqual(await pg.evaluate(() => window.__printed), 1, 'window.print called once');
      const pr = await printed(pg);
      assert.deepStrictEqual(pr.css, { shown: ['printDoc'], nav: 0, buttons: 0 }, 'only the order is printed');
      assert.strictEqual(pr.pdf.pages.length, 1, 'a short order is one page');
      assert.ok(pr.pdf.pages[0].drawsText);
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, []);
    }
  },
  {
    name: 'a long order: the PDF goes on with «Página n de m»; the print has no blank page at the end',
    run: async ({ browser }) => {
      P.seed();
      // 40 products in the catalog, all on one order
      sql(`insert into stock_items (id, name, unit, pack_label, pack_qty, cost_per_pack, vendor_id)
           select ('5a000000-0000-4000-8000-0000000b' || lpad(g::text, 4, '0'))::uuid, 'Producto de prueba número ' || g, 'unit', 'caja de ' || g, g, 1000 + g, '${V.fin}'
             from generate_series(1, 40) g`);
      const lines = sql(`select string_agg(id::text, ',' order by pack_qty) from vendor_items where vendor_id = '${V.fin}'`).split(',').map((vi, k) => ({ vi, packs: k + 1 }));
      const o = P.create(V.fin, lines);
      const pg = await P.owner(browser, { hash: '#pedido=' + o.id, wait: '#orderDoc' });
      const pdf = P.pdfRead((await pdfOf(pg)).bytes);
      assert.strictEqual(pdf.pages.length, 2);
      assert.ok(pdf.pages[0].text.includes('Página 1 de 2') && pdf.pages[1].text.includes('Página 2 de 2'));
      assert.ok(pdf.pages[1].text.includes('Producto de prueba número 40') && pdf.pages[1].text.includes('PEDIDO Nº ' + o.po_number), 'the header again on page 2');
      await pg.click('#docPrint');
      const pr = await printed(pg);
      assert.ok(pr.pdf.pages.length >= 2 && pr.pdf.pages.length <= 3, 'printed on ' + pr.pdf.pages.length + ' pages');
      assert.ok(pr.pdf.pages.every((p) => p.drawsText), 'no blank page (the last one included)');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'editing before receiving (quantity, price, a line off, a line added, the note), then after a partial delivery; the history; «changed» from another device',
    run: async ({ browser }) => {
      P.seed();
      const o = short();
      const pg = await P.owner(browser, { hash: '#pedido=' + o.id, wait: '#orderDoc' });
      await pg.click('#docEdit');
      await pg.waitForSelector('#orderEdit');
      assert.match(await text(pg.locator('#orderEdit h3')), /^Editar el pedido$/);
      await pg.fill('#oeQ0', '3');            // milk: 3 boxes
      await pg.fill('#oeP1', '4800');         // yogurt: a new price
      await pg.locator('#oeLines .prow', { hasText: 'Queso turrialba' }).locator('button', { hasText: '×' }).click();
      await pg.selectOption('#oeAdd', P.vi(I.mant));
      await pg.fill('#oeNote', 'Nueva nota');
      await pg.click('#oeGo');
      await P.toasted(pg, /^Cambios guardados$/, 'saved');
      assert.strictEqual(sql(`select string_agg(i.name || ':' || trim_scale(l.packs) || ':' || trim_scale(l.qty) || ':' || (l.removed_at is not null) || ':' || trim_scale(round(l.unit_cost * l.pack_qty, 2)), ', ' order by l.pos)
                                from purchase_lines l join stock_items i on i.id = l.item_id where l.po_id = '${o.id}'`),
        'Leche entera:3:36:false:10200, Yogur natural:3:18:false:4800, Queso turrialba:0:0:true:5200, Mantequilla:1:500:false:3100',
        'the removed line is kept (removed_at), never deleted');
      assert.strictEqual(sql(`select note from purchase_orders where id = '${o.id}'`), 'Nueva nota');
      assert.ok(Number(sql(`select count(*) from audit_log where action = 'po_edit'`)) >= 1, 'audited');
      await pg.waitForSelector('#orderDoc');
      await pg.locator('#main details summary', { hasText: 'Historial de cambios' }).click();
      const hist = await text(pg.locator('#main details'));
      assert.match(hist, new RegExp('Historial de cambios .* · pedido Nº ' + o.po_number + ': Queso turrialba quitado; Leche entera 2 → 3; Yogur natural precio ₡4500 → ₡4800; Mantequilla agregado \\(1\\); nota cambiada · owner'), hist);
      // a partial delivery: 2 of the 3 boxes of milk
      P.receive(o.id, [{ line: P.lineOf(o.id, I.leche), packs: 2 }]);
      await pg.reload({ waitUntil: 'domcontentloaded' });
      await pg.waitForSelector('#orderDoc');
      await P.seen(pg.locator('#orderDoc .dh'), /^Pedido Nº \d+ Parcialmente recibido Pago pendiente$/, 'partly received', 5000);
      await P.seen(pg.locator(`#docLines tr[data-line="${P.lineOf(o.id, I.leche)}"]`), /3 ₡10 200 ₡30 600 2 1$/, 'received 2, pending 1', 3000);
      await pg.click('#docEdit');
      await pg.waitForSelector('#orderEdit');
      assert.strictEqual(await pg.locator('#oeLines .prow', { hasText: 'Leche entera' }).locator('button', { hasText: '×' }).isDisabled(), true, 'a line with deliveries cannot be taken off');
      await pg.fill('#oeQ0', '1');
      await pg.click('#oeGo');
      await P.seen(pg.locator('#oeErr'), /^Es menos de lo que ya llegó\. · Leche entera$/, 'below what arrived', 3000);
      await pg.fill('#oeQ0', '4');
      // meanwhile another device changes the order: this one is told and shown the order as it is now
      const other = await P.owner(browser, { hash: '#pedido=' + o.id, wait: '#orderDoc' });
      await other.click('#docEdit'); await other.waitForSelector('#orderEdit');
      await other.fill('#oeNote', 'Del otro aparato'); await other.click('#oeGo');
      await P.toasted(other, /^Cambios guardados$/, 'the other device saved');
      await pg.click('#oeGo');
      await P.seen(pg.locator('#main'), /Alguien cambió este pedido hace un momento\. Aquí está como quedó: haga su cambio de nuevo\./, '«changed», in Spanish', 8000);
      assert.strictEqual(sql(`select trim_scale(packs) from purchase_lines where id = '${P.lineOf(o.id, I.leche)}'`), '3', 'nothing saved over the other change');
      await pg.click('#docEdit'); await pg.waitForSelector('#orderEdit');
      assert.strictEqual(await pg.inputValue('#oeNote'), 'Del otro aparato');
      await pg.fill('#oeQ0', '4'); await pg.click('#oeGo');
      await P.toasted(pg, /^Cambios guardados$/, 'saved after a partial delivery');
      assert.strictEqual(sql(`select trim_scale(packs) || ':' || trim_scale(qty) || ':' || trim_scale(received_qty) from purchase_lines where id = '${P.lineOf(o.id, I.leche)}'`), '4:48:24');
      for (const p of [pg, other]) { assert.deepStrictEqual(p.errors, []); assert.deepStrictEqual(p.apiErrors, []); }
    }
  },
  {
    name: 'cancel an order (once confirmed); close what is pending after a partial delivery (what did not arrive is shown as missing)',
    run: async ({ browser }) => {
      P.seed();
      const a = P.create(V.lac, [{ vi: P.vi(I.leche), packs: 2 }]);
      const b = P.create(V.lac, [{ vi: P.vi(I.leche), packs: 2 }, { vi: P.vi(I.yogur), packs: 4 }]);
      const pg = await P.owner(browser, { hash: '#pedido=' + a.id, wait: '#orderDoc' });
      const asked = []; pg.onDialog = async (d) => { asked.push(d.message()); await d.accept(d.defaultValue()); };
      await pg.locator('#docActs button', { hasText: 'Cancelar pedido' }).click();
      await P.toasted(pg, /^Pedido cancelado$/, 'cancelled');
      assert.deepStrictEqual(asked, ['¿Cancelar el pedido Nº ' + a.po_number + '?']);
      assert.strictEqual(sql(`select status from purchase_orders where id = '${a.id}'`), 'cancelled');
      await P.seen(pg.locator('#orderDoc .dh'), /Cancelado/, 'shown cancelled', 5000);
      assert.strictEqual(await pg.locator('#docActs button', { hasText: 'Cancelar pedido' }).count(), 0);
      // the other order: a partial delivery, then «Cerrar lo pendiente»
      P.receive(b.id, [{ line: P.lineOf(b.id, I.leche), rest: true }, { line: P.lineOf(b.id, I.yogur), packs: 1 }]);
      await goto(pg, '/proveedores#pedido=' + b.id);
      await P.seen(pg.locator('#orderDoc .dh'), /^Pedido Nº \d+ Parcialmente recibido Pago pendiente$/, 'partly received', 5000);
      assert.strictEqual(await pg.locator('#docActs button', { hasText: 'Cancelar pedido' }).count(), 0, 'an order with deliveries is not cancelled');
      await pg.locator('#docActs button', { hasText: 'Cerrar lo pendiente' }).click();
      await P.toasted(pg, /^Pedido cerrado$/, 'closed');
      assert.match(asked[1], /^¿Cerrar lo pendiente\? Lo que no llegó queda registrado como faltante\./);
      assert.strictEqual(sql(`select status || '|' || (received_at is not null) from purchase_orders where id = '${b.id}'`), 'received|true');
      await P.seen(pg.locator(`#docLines tr[data-line="${P.lineOf(b.id, I.yogur)}"]`), /4 ₡4 500 ₡18 000 1 3$/, 'what did not arrive', 5000);
      assert.match(await text(pg.locator('#docLines thead')), /Faltó/i);
      assert.strictEqual(await pg.locator(`#docLines tr.miss[data-line="${P.lineOf(b.id, I.yogur)}"]`).count(), 1, 'marked as missing');
      assert.ok(Number(sql(`select count(*) from audit_log where action = 'po_close'`)) === 1 && Number(sql(`select count(*) from audit_log where action = 'po_cancel'`)) === 1);
      assert.deepStrictEqual(pg.errors, []);
      assert.deepStrictEqual(pg.apiErrors, []);
    }
  }
];
