/* Turning on the phone code warns first: each time the code is typed, Supabase signs out every other session of that
   login without it (the POS and the kitchen on a shared login), so a cancelled warning never starts the enrolment. */
'use strict';
const assert = require('assert');
const { page, goto, until } = require('../lib');

/* counts the enrolments the page starts (POST /auth/v1/factors) and keeps every dialog it opens */
function watch(pg) {
  pg.enrolls = 0; pg.dialogs = [];
  pg.on('request', (r) => { if (r.method() === 'POST' && /\/auth\/v1\/factors$/.test(new URL(r.url()).pathname)) pg.enrolls++; });
  pg.answer = (ok) => { pg.onDialog = async (d) => { pg.dialogs.push(d.type() + ': ' + d.message()); if (ok || d.type() === 'alert') await d.accept(); else await d.dismiss(); }; };
}

module.exports.tests = [
  {
    name: 'Home: the warning comes in Spanish before the phone code starts; cancelled, nothing is enrolled',
    run: async ({ browser }) => {
      const pg = await page(browser, { login: 'owner', aal: 'aal2', lang: 'es' });
      watch(pg);
      await goto(pg, '/home');
      await until(async () => (await pg.locator('#codeBtn').isVisible()) && (await pg.locator('#codeBtn').textContent()) === 'Activar', 10000, 'the button to turn the code on');
      pg.answer(false);
      await pg.click('#codeBtn');
      await until(() => pg.dialogs.length === 1, 5000, 'the warning');
      assert.strictEqual(pg.dialogs[0], 'confirm: Solo en su propio teléfono y con su propio ingreso. Al escribir este código se cierra la sesión en todos los demás dispositivos que usan este ingreso, incluidas las tabletas del café. ¿Continuar?');
      assert.strictEqual(pg.enrolls, 0, 'no enrolment after Cancel');
      assert.strictEqual(await pg.locator('#enrollBox').isHidden(), true, 'no QR code after Cancel');
      // accepted, the enrolment starts (the local stand-in has no TOTP, so the page then says it could not start)
      pg.answer(true);
      await pg.click('#codeBtn');
      await until(() => pg.dialogs.length === 3, 5000, 'the warning, then the answer');
      assert.match(pg.dialogs[1], /^confirm: Solo en su propio teléfono/);
      assert.match(pg.dialogs[2], /^alert: No se pudo iniciar el código del teléfono/);
      assert.strictEqual(pg.enrolls, 1, 'one enrolment, only after the warning was accepted');
      assert.deepStrictEqual(pg.errors, []);
    }
  },
  {
    name: 'Accounting: the same warning before the phone code starts; cancelled, no QR code',
    run: async ({ browser }) => {
      const pg = await page(browser, { login: 'accountant', aal: 'aal1', lang: 'en' });
      watch(pg);
      await goto(pg, '/accounting');
      await pg.waitForSelector('#enrollStart:visible', { timeout: 15000 });
      pg.answer(false);
      await pg.click('#enrollStart');
      await until(() => pg.dialogs.length === 1, 5000, 'the warning');
      assert.strictEqual(pg.dialogs[0], 'confirm: Only on your own phone and your own login. Typing this code signs out every other device that uses this login, including café tablets. Continue?');
      assert.strictEqual(pg.enrolls, 0, 'no enrolment after Cancel');
      assert.strictEqual(await pg.locator('#enrollBox').isHidden(), true, 'no QR code after Cancel');
      assert.strictEqual(await pg.locator('#enrollStart').isVisible(), true, 'the button stays');
      pg.answer(true);
      await pg.click('#enrollStart');
      await until(async () => /^Could not start the phone code/.test(await pg.locator('#enrollErr').textContent()), 5000, 'the enrolment was tried');
      assert.strictEqual(pg.dialogs.length, 2);
      assert.strictEqual(pg.enrolls, 1, 'one enrolment, only after the warning was accepted');
      assert.deepStrictEqual(pg.errors, []);
    }
  }
];
