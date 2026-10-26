/* The bank (migration 0020): an account, a statement imported from the bank's CSV, matching and posting. */
'use strict';
const assert = require('assert');
const { page, goto, until, sql, crToday } = require('../lib');

function dmy(iso) { const [y, m, d] = iso.split('-'); return d + '/' + m + '/' + y; }

module.exports.tests = [
  {
    name: 'a Costa Rican bank CSV (semicolons, day/month/year, 1.234,56) is imported once; the deposit matches; the fee is posted',
    run: async ({ browser }) => {
      sql(`select acct.post(cr_today() - 1, 'Depósito de la caja', 'manual', 'e2e:dep', '[{"account":"1110","debit":30000},{"account":"1101","credit":30000}]'::jsonb, null, 'prueba')`);
      const pg = await page(browser, { login: 'accountant', aal: 'aal2', lang: 'es' });
      await goto(pg, '/accounting');
      await pg.waitForSelector('#appView:not([hidden])', { timeout: 15000 });
      await pg.click('#tabs [data-view=bank]');
      await pg.click('#bkNew');
      await pg.fill('#bkName', 'BCR colones');
      await pg.fill('#bkLast4', '3456');
      await pg.selectOption('#bkGl', '1110');
      await pg.click('#bkSave');
      await until(() => sql(`select name || ':' || gl_account from bank_accounts`) === 'BCR colones:1110', 8000, 'account saved');
      await until(async () => pg.locator('#bkFile').isVisible(), 8000, 'import card');
      const csv = '﻿Fecha;Descripción;Referencia;Débito;Crédito;Saldo\n' +
        dmy(crToday(-1)) + ';DEPOSITO EFECTIVO;1001;;30.000,00;130.000,00\n' +
        dmy(crToday(0)) + ';"COMISION; MANTENIMIENTO";1002;350,00;;129.650,00\n' +
        ';;;;Total;\n';
      await pg.setInputFiles('#bkFile', { name: 'bcr-octubre.csv', mimeType: 'text/csv', buffer: Buffer.from(csv, 'utf8') });
      await until(async () => /2 movimientos · 1 filas dejadas fuera/.test(await pg.locator('#bkPrevNote').textContent()), 8000, 'preview: 2 movements, the total row left out');
      assert.match((await pg.locator('#bkPrev tbody').innerText()).replace(/\s+/g, ' '), /COMISION; MANTENIMIENTO 1002 −₡350/, 'debit column read as money out');
      await pg.click('#bkImport');
      await until(() => sql(`select count(*) from bank_lines`) === '2', 8000, 'imported');
      // the same file again adds nothing
      await pg.setInputFiles('#bkFile', { name: 'bcr-octubre.csv', mimeType: 'text/csv', buffer: Buffer.from(csv, 'utf8') });
      await until(async () => !(await pg.locator('#bkMap').isHidden()), 8000, 'preview again');
      await pg.click('#bkImport');
      await until(async () => /0 movimientos nuevos · 2 ya estaban/.test(await pg.locator('#toast').textContent()), 8000, 'nothing new');
      // the deposit matches the books; the fee is posted to bank charges
      await until(async () => (await pg.locator('#bkTable button', { hasText: /^Unir: Nº/ }).count()) === 1, 8000, 'a suggestion for the deposit');
      await pg.click('#bkAuto');
      await until(() => sql(`select status from bank_lines where amount = 30000`) === 'matched', 8000, 'matched');
      await until(async () => (await pg.locator('#bkTable button', { hasText: 'Asentar…' }).count()) === 1, 8000, 'the fee is still open');
      await pg.locator('#bkTable button', { hasText: 'Asentar…' }).click();
      await pg.locator('#bkTable select.pa1').selectOption('6208');
      await pg.locator('#bkTable button', { hasText: /^Asentar$/ }).click();
      await until(() => sql(`select string_agg(l.account || ':' || (l.debit - l.credit), ',' order by l.account) from acct.lines l join acct.entries e on e.id = l.entry_id where e.source = 'bank'`)
                    === '1110:-350.00,6208:350.00', 8000, 'fee posted');
      await until(async () => /Libros ₡29 650/.test(await pg.locator('#bkSum').textContent()), 8000, 'books balance shown');
      assert.deepStrictEqual(pg.errors, []);
    }
  }
];
