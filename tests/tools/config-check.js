/* Canopy OS · which database each address talks to (website/config.js), checked without a browser.
   node tests/tools/config-check.js   — exits 1 on any wrong decision. */
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const vm = require('vm');
const { spawnSync } = require('child_process');
const ROOT = path.resolve(__dirname, '../..');
const SRC = fs.readFileSync(path.join(ROOT, 'website/config.js'), 'utf8');
const PROD = SRC.match(/production: \{ url: '([^']+)'/)[1];

function run(src, href) {
  const u = new URL(href);
  const ctx = { location: { hostname: u.hostname, pathname: u.pathname, port: u.port }, window: {},
                document: { body: null, addEventListener() {}, createElement() { return { style: {}, setAttribute() {} }; } } };
  try { vm.runInNewContext(src, ctx); } catch (e) { return { blocked: true, threw: true }; }
  return ctx.window.HG_CONFIG;
}
function staged(url, key) {   // config.js as the staging site's publishing leaves it
  const f = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'cfg-')), 'config.js');
  fs.writeFileSync(f, SRC);
  const r = spawnSync('python3', [path.join(ROOT, 'ops/staging/repositorio-pruebas/poner-pruebas.py'), f, url, key], { encoding: 'utf8' });
  return { ok: r.status === 0, out: r.stdout + r.stderr, src: fs.readFileSync(f, 'utf8') };
}
const jwt = (p) => 'eyJhbGciOiJIUzI1NiJ9.' + Buffer.from(JSON.stringify(p)).toString('base64url') + '.sig';
const fails = [];
const expect = (cond, msg) => { if (!cond) fails.push(msg); };

let c = run(SRC, 'https://hanginggardencafe.com/pos');
expect(c.env === 'production' && c.url === PROD && !c.blocked, 'the café domain uses production');
c = run(SRC, 'https://jeanpaulcocaleca-create.github.io/canopy-pruebas/pos');
expect(c.blocked, 'the staging address without its own project is blocked (never production)');
c = run(SRC, 'https://jeanpaulcocaleca-create.github.io/canopy-pruebas/m');
expect(c.blocked, 'even the public menu on the staging address is blocked until staging is set');
c = run(SRC, 'https://example.org/pos');
expect(c.blocked, 'a staff page on an unknown address is blocked');

let s = staged(PROD, jwt({ role: 'anon', ref: PROD.match(/https:\/\/([a-z0-9]+)/)[1] }));
expect(!s.ok && /PRODUCCIÓN/.test(s.out), 'staging publishing refuses the production project');
s = staged('https://abcdefghijklmnopqrst.supabase.co', jwt({ role: 'service_role', ref: 'abcdefghijklmnopqrst' }));
expect(!s.ok && /anon/.test(s.out), 'staging publishing refuses a service_role key');
s = staged('https://abcdefghijklmnopqrst.supabase.co', jwt({ role: 'anon', ref: 'zzzzzzzzzzzzzzzzzzzz' }));
expect(!s.ok, 'staging publishing refuses another project\'s key');
s = staged('https://abcdefghijklmnopqrst.supabase.co', jwt({ role: 'anon', ref: 'abcdefghijklmnopqrst' }));
expect(s.ok, 'staging publishing accepts the staging project and its anon key: ' + s.out);
c = run(s.src, 'https://jeanpaulcocaleca-create.github.io/canopy-pruebas/pos');
expect(c.env === 'staging' && c.url === 'https://abcdefghijklmnopqrst.supabase.co' && !c.blocked, 'the staging site talks to staging only');
c = run(s.src, 'https://hanginggardencafe.com/pos');
expect(c.env === 'production', 'the same files on the café domain still use production');
// someone pastes the production values by hand: the page itself refuses
const bad = SRC.replace("staging: { url: '', key: '' },", "staging: { url: '" + PROD + "', key: 'x' },");
c = run(bad, 'https://jeanpaulcocaleca-create.github.io/canopy-pruebas/pos');
expect(c.blocked, 'config.js itself refuses a staging entry that points at production');

if (fails.length) { fails.forEach((f) => console.log('  FAIL  config.js: ' + f)); process.exit(1); }
console.log('  ok    config.js environments (production, staging never on production data, unknown addresses blocked)');
