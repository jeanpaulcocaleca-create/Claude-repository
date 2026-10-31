// Renderiza los rótulos HTML a PDF (tamaño real 700 × 1100 mm) y PNG de alta resolución.
// Uso: node render.js [menu|promo ...]   (sin argumentos renderiza los dos)
const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

const MM_TO_PX = 96 / 25.4;            // 1 mm = 3.7795 px CSS
const W_MM = 700, H_MM = 1100;
const SCALE = 2;                        // PNG a ~192 ppp (5292 × 8315 px)

(async () => {
  const names = process.argv.slice(2).length ? process.argv.slice(2) : ['menu', 'promo'];
  const browser = await chromium.launch();
  for (const name of names) {
    const file = path.resolve(__dirname, `${name}.html`);
    if (!fs.existsSync(file)) { console.error(`No existe ${file}`); continue; }
    const page = await browser.newPage({
      viewport: { width: Math.round(W_MM * MM_TO_PX), height: Math.round(H_MM * MM_TO_PX) },
      deviceScaleFactor: SCALE,
    });
    await page.goto('file://' + file);
    await page.evaluate(() => document.fonts.ready);
    await page.evaluate(() => Promise.all(
      Array.from(document.images).map(img => img.complete ? null : new Promise(r => { img.onload = img.onerror = r; }))
    ));
    await page.waitForTimeout(300);

    const out = path.resolve(__dirname, 'salida');
    fs.mkdirSync(out, { recursive: true });

    await page.locator('.sign').screenshot({ path: path.join(out, `${name}-70x110cm.png`), type: 'png' });
    await page.pdf({
      path: path.join(out, `${name}-70x110cm.pdf`),
      width: `${W_MM}mm`, height: `${H_MM}mm`,
      printBackground: true, preferCSSPageSize: true,
      margin: { top: 0, right: 0, bottom: 0, left: 0 },
    });
    console.log(`OK ${name}`);
    await page.close();
  }
  await browser.close();
})();
