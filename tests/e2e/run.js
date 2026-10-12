/* Canopy OS browser tests · runner.
   node tests/e2e/run.js [filter]
   Builds a throw-away database, starts PostgREST + the local Supabase stand-in, and runs every spec in
   tests/e2e/specs/ against the REAL pages in website/ (each spec gets a fresh copy of the database). */
'use strict';
const { spawnSync, spawn } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const ROOT = path.resolve(__dirname, '../..');

function pgEnv() {
  if (!process.env.PGHOST) {
    const r = spawnSync('bash', ['-c', 'source "' + ROOT + '/tests/pg.sh" && env | grep ^PG'], { encoding: 'utf8' });
    r.stdout.split('\n').forEach((l) => { const i = l.indexOf('='); if (i > 0) process.env[l.slice(0, i)] = l.slice(i + 1); });
  }
}
function psql(args) {
  const r = spawnSync('psql', ['-X', '-q', '-v', 'ON_ERROR_STOP=1'].concat(args), { encoding: 'utf8' });
  if (r.status !== 0) throw new Error(r.stderr);
  return r.stdout;
}
function postgrestBin() {
  const cands = [process.env.POSTGREST_BIN, path.join(__dirname, '.bin/postgrest')].filter(Boolean);
  for (const c of cands) if (fs.existsSync(c)) return c;
  // CI: fetch the pinned release (static Linux binary)
  fs.mkdirSync(path.join(__dirname, '.bin'), { recursive: true });
  const url = 'https://github.com/PostgREST/postgrest/releases/download/v12.2.3/postgrest-v12.2.3-linux-static-x64.tar.xz';
  const r = spawnSync('bash', ['-c', 'curl -fsSL "' + url + '" | tar -xJ -C "' + path.join(__dirname, '.bin') + '"'], { stdio: 'inherit' });
  if (r.status !== 0 || !fs.existsSync(path.join(__dirname, '.bin/postgrest'))) throw new Error('PostgREST binary not found (set POSTGREST_BIN)');
  return path.join(__dirname, '.bin/postgrest');
}
function playwright() {
  try { return require('playwright'); } catch (e) { return require('/opt/node22/lib/node_modules/playwright'); }
}

const children = new Set();
process.on('exit', () => { for (const c of children) { try { c.kill('SIGKILL'); } catch (e) {} } });
['SIGINT', 'SIGTERM'].forEach((sig) => process.on(sig, () => process.exit(130)));

async function startPostgrest(bin, db, port) {
  // a PostgREST left over from an interrupted run would answer with an old schema: refuse to test against it
  try { await fetch('http://127.0.0.1:' + port + '/'); throw new Error('port ' + port + ' is already in use (a leftover PostgREST?)'); }
  catch (e) { if (/already in use/.test(e.message)) throw e; }
  const conf = path.join(os.tmpdir(), 'canopy-postgrest-' + port + '.conf');
  const host = process.env.PGHOST || '127.0.0.1', pgport = process.env.PGPORT || '5432';
  fs.writeFileSync(conf, [
    `db-uri = "postgres://authenticator:authenticator@${host}:${pgport}/${db}"`,
    'db-schemas = "public"', 'db-anon-role = "anon"', 'db-pool = 4', 'db-max-rows = 1000',   // Supabase answers at most 1000 rows
    `jwt-secret = "${require('./gateway').SECRET}"`, 'server-port = ' + port, 'server-host = "127.0.0.1"', 'log-level = "error"'
  ].join('\n'));
  const p = spawn(bin, [conf], { stdio: ['ignore', 'ignore', 'pipe'] });
  children.add(p); p.on('exit', () => children.delete(p));
  let err = ''; p.stderr.on('data', (d) => { err += d; });
  for (let i = 0; i < 100; i++) {
    try { const r = await fetch('http://127.0.0.1:' + port + '/'); if (r.status < 500) return p; } catch (e) {}
    await new Promise((r) => setTimeout(r, 100));
  }
  p.kill(); throw new Error('PostgREST did not start: ' + err);
}

(async () => {
  pgEnv();
  const filter = process.argv[2] || '';
  const SUFFIX = process.env.E2E_SUFFIX || '';
  const TPL = 'canopy_e2e_tpl' + SUFFIX, DB = 'canopy_e2e' + SUFFIX;
  const SITE_PORT = Number(process.env.E2E_SITE_PORT || 8090), PGRST_PORT = Number(process.env.E2E_PGRST_PORT || 3013);
  process.env.CANOPY_E2E_DB = DB;
  const b = spawnSync('bash', [path.join(ROOT, 'tests/build-db.sh'), TPL], { encoding: 'utf8' });
  if (b.status !== 0) { console.error(b.stdout, b.stderr); process.exit(1); }
  const bin = postgrestBin();
  const gw = require('./gateway');
  const state = { offline: false, release: null };
  const server = await gw.start({ siteRoot: path.join(ROOT, 'website'), sitePort: SITE_PORT, postgrestPort: PGRST_PORT, offline: () => state.offline, release: () => state.release });
  const { chromium } = playwright();
  const browser = await chromium.launch(process.env.PW_CHROMIUM ? { executablePath: process.env.PW_CHROMIUM } : {});

  const specs = fs.readdirSync(path.join(__dirname, 'specs')).filter((f) => f.endsWith('.spec.js') && f.includes(filter)).sort();
  let pass = 0, fail = 0; const failed = [];
  for (const f of specs) {
    const spec = require(path.join(__dirname, 'specs', f));
    const tests = spec.tests || [{ name: f, run: spec.run }];
    for (const t of tests) {
      psql(['-d', 'postgres', '-c', `drop database if exists ${DB} with (force)`, '-c', `create database ${DB} template ${TPL}`]);
      const pgrst = await startPostgrest(bin, DB, PGRST_PORT);
      state.offline = false; state.release = null;
      const t0 = Date.now();
      try {
        await t.run({ browser, setOffline: (v) => { state.offline = !!v; }, setRelease: (r) => { state.release = r || null; } });
        pass++; console.log(`  ok    ${f} › ${t.name} (${((Date.now() - t0) / 1000).toFixed(1)}s)`);
      } catch (e) {
        fail++; failed.push(`${f} › ${t.name}`);
        console.log(`  FAIL  ${f} › ${t.name}\n        ${String(e && e.stack || e).split('\n').slice(0, 6).join('\n        ')}`);
      } finally {
        pgrst.kill();
        await new Promise((r) => { if (pgrst.exitCode !== null) r(); else pgrst.once('exit', r); });
        for (const c of browser.contexts()) await c.close().catch(() => {});
      }
    }
  }
  await browser.close(); server.close();
  psql(['-d', 'postgres', '-c', `drop database if exists ${DB} with (force)`, '-c', `drop database if exists ${TPL} with (force)`]);
  console.log(`Browser tests: ${pass} passed, ${fail} failed${fail ? ' (' + failed.join('; ') + ')' : ''}`);
  process.exit(fail ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
