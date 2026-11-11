#!/usr/bin/env node
/* The garden plaque for Gabriel Barboza Villalobos (D-068): its QR code and its artwork, written to
   docs/placa-gabriel-barboza/:
     qr-gabriel-barboza.svg   the QR as vector (for the printer)
     qr-gabriel-barboza.png   the same QR as a raster, 24 px per module (1176 × 1176 px)
     placa-gabriel-barboza.svg  the plaque, 300 × 400 mm: «Homenaje», his name, the dedication, the QR with
                                «Conozca su historia / Discover his story» and the address under it
   The QR opens exactly https://hanginggardencafe.com/gabriel-barboza (the tribute page; the address never changes):
   error correction H (30 % of the code can be scratched or dirty and it still reads), the standard 4-module quiet
   zone, dark green ink on white (contrast about 13 : 1). The plaque carries no story: the page tells it.
     node tools/placa/build.js
   It uses qrcode-generator 1.4.4, the copy the browser tests install (tests/e2e: npm ci). Browser test 420 (G10)
   checks that the committed files hold exactly this code. */
'use strict';
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const qrcode = require(path.join(__dirname, '../../tests/e2e/node_modules/qrcode-generator'));

const URL_ = 'https://hanginggardencafe.com/gabriel-barboza';
const OUT = path.join(__dirname, '../../docs/placa-gabriel-barboza');
const INK = '#17352a', PAPER = '#ffffff', QUIET = 4;

/* the code: version chosen by the library for the address at level H */
const q = qrcode(0, 'H');
q.addData(URL_, 'Byte');
q.make();
const n = q.getModuleCount(), size = n + 2 * QUIET;

/* one path for the dark modules, row by row (runs of dark modules as rectangles) */
function modulesPath(ox, oy, unit) {
  let d = '';
  for (let r = 0; r < n; r++) {
    for (let c = 0; c < n; c++) {
      if (!q.isDark(r, c)) continue;
      let e = c; while (e + 1 < n && q.isDark(r, e + 1)) e++;
      const x = +(ox + (c + QUIET) * unit).toFixed(3), y = +(oy + (r + QUIET) * unit).toFixed(3), w = +((e - c + 1) * unit).toFixed(3), h = +unit.toFixed(3);
      d += `M${x} ${y}h${w}v${h}h${-w}z`;
      c = e;
    }
  }
  return d;
}

/* QR alone, one unit per module */
const qrSvg = `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${size * 12}" height="${size * 12}" viewBox="0 0 ${size} ${size}" shape-rendering="crispEdges">
<title>QR: ${URL_}</title>
<rect width="${size}" height="${size}" fill="${PAPER}"/>
<path fill="${INK}" d="${modulesPath(0, 0, 1)}"/>
</svg>
`;

/* the same code as a PNG (8-bit RGB, written here with zlib: no image library) */
function png(px) {
  const w = size * px, raw = Buffer.alloc((w * 3 + 1) * w);
  const ink = [0x17, 0x35, 0x2a], paper = [0xff, 0xff, 0xff];
  for (let y = 0; y < w; y++) {
    const row = y * (w * 3 + 1); raw[row] = 0;
    const r = Math.floor(y / px) - QUIET;
    for (let x = 0; x < w; x++) {
      const c = Math.floor(x / px) - QUIET;
      const dark = r >= 0 && r < n && c >= 0 && c < n && q.isDark(r, c);
      const col = dark ? ink : paper, o = row + 1 + x * 3;
      raw[o] = col[0]; raw[o + 1] = col[1]; raw[o + 2] = col[2];
    }
  }
  const crcTable = []; for (let k = 0; k < 256; k++) { let c = k; for (let j = 0; j < 8; j++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; crcTable[k] = c >>> 0; }
  const crc = (b) => { let c = 0xffffffff; for (const v of b) c = crcTable[(c ^ v) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
  const chunk = (type, data) => { const t = Buffer.from(type), len = Buffer.alloc(4), cr = Buffer.alloc(4);
    len.writeUInt32BE(data.length); cr.writeUInt32BE(crc(Buffer.concat([t, data]))); return Buffer.concat([len, t, data, cr]); };
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(w, 4); ihdr[8] = 8; ihdr[9] = 2; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  const phys = Buffer.alloc(9); phys.writeUInt32BE(11811, 0); phys.writeUInt32BE(11811, 4); phys[8] = 1;   /* 300 dpi */
  return Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), chunk('IHDR', ihdr), chunk('pHYs', phys),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0))]);
}

/* the plaque, in millimetres: cream with a gold rule, the site's colours and type */
const esc = (t) => t.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
/* the owner's line as the owner quoted it: in guillemets, no full stop */
const DEDICATION = ['Su conocimiento, generosidad y amor', 'por las orquídeas dejaron una huella', 'que continúa floreciendo', 'en este jardín'];
const qrMm = 72, qrUnit = qrMm / size, qrX = (300 - qrMm) / 2, qrY = 245;
const plaque = `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="300mm" height="400mm" viewBox="0 0 300 400">
<title>Placa · Gabriel Barboza Villalobos</title>
<desc>Homenaje a Gabriel Barboza Villalobos. Dedicatoria y código QR a ${URL_}. Tipografías: Playfair Display, Figtree y Spline Sans Mono (Google Fonts, gratuitas): la imprenta las instala o convierte el texto a curvas.</desc>
<rect width="300" height="400" fill="#FCF8EC"/>
<rect x="12" y="12" width="276" height="376" fill="none" stroke="#B98A35" stroke-width="0.8"/>
<rect x="16" y="16" width="268" height="368" fill="none" stroke="#B98A35" stroke-width="0.3"/>
<g text-anchor="middle" fill="#1E4B33">
<text x="150" y="66" font-family="'Spline Sans Mono', 'Courier New', monospace" font-size="6.2" letter-spacing="2.6" fill="#B98A35">HOMENAJE</text>
<text x="150" y="101" font-family="'Playfair Display', Georgia, serif" font-weight="600" font-size="21">Gabriel Barboza</text>
<text x="150" y="127" font-family="'Playfair Display', Georgia, serif" font-weight="600" font-size="21">Villalobos</text>
<line x1="135" y1="144" x2="165" y2="144" stroke="#B98A35" stroke-width="0.8"/>
${DEDICATION.map((l, i) => `<text x="150" y="${171 + i * 13}" font-family="'Playfair Display', Georgia, serif" font-style="italic" font-size="9.6" fill="#26392C">${i === 0 ? '«' : ''}${esc(l)}${i === DEDICATION.length - 1 ? '»' : ''}</text>`).join('\n')}
</g>
<g id="qr">
<rect x="${qrX}" y="${qrY}" width="${qrMm}" height="${qrMm}" fill="${PAPER}"/>
<path fill="${INK}" shape-rendering="crispEdges" d="${modulesPath(qrX, qrY, qrUnit)}"/>
</g>
<g text-anchor="middle">
<text x="150" y="${qrY + qrMm + 16}" font-family="Figtree, Arial, sans-serif" font-weight="600" font-size="8.6" fill="#1E4B33">Conozca su historia / Discover his story</text>
<text x="150" y="${qrY + qrMm + 27}" font-family="'Spline Sans Mono', 'Courier New', monospace" font-size="5" letter-spacing="0.3" fill="#54634F">hanginggardencafe.com/gabriel-barboza</text>
</g>
</svg>
`;

fs.mkdirSync(OUT, { recursive: true });
fs.writeFileSync(path.join(OUT, 'qr-gabriel-barboza.svg'), qrSvg);
fs.writeFileSync(path.join(OUT, 'qr-gabriel-barboza.png'), png(24));
fs.writeFileSync(path.join(OUT, 'placa-gabriel-barboza.svg'), plaque);
console.log('QR version', (n - 17) / 4, 'level H,', n, 'modules +', QUIET, 'quiet;', 'plaque QR', qrMm, 'mm (', qrUnit.toFixed(2), 'mm per module )');
