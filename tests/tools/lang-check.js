/* lint: the Spanish dictionary (website/lang.js) must not give one English text two different translations
   (the later one would silently win everywhere). */
'use strict';
const fs = require('fs');
const path = require('path');
const src = fs.readFileSync(path.join(__dirname, '../../website/lang.js'), 'utf8');
const start = src.indexOf('var D = {'), end = src.indexOf('\n  };', start);
const body = src.slice(start, end);
const seen = new Map(), bad = [];
const pair = /('(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*")\s*:\s*\n?\s*('(?:[^'\\]|\\.)*'|"(?:[^"\\]|\\.)*")/g;
let m;
while ((m = pair.exec(body))) {
  const k = m[1].slice(1, -1), v = m[2].slice(1, -1);
  if (seen.has(k) && seen.get(k) !== v) bad.push(`"${k}": "${seen.get(k)}" vs "${v}"`);
  seen.set(k, v);
}
if (bad.length) { console.error('lang.js has conflicting translations:\n  ' + bad.join('\n  ')); process.exit(1); }
