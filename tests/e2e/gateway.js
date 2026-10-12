/* Canopy OS browser tests · local stand-in for GitHub Pages + Supabase (no dependencies).
   - http://127.0.0.1:8090  serves website/ like GitHub Pages (pretty URLs: /pos -> pos.html)
   - http://127.0.0.1:54321 answers like Supabase:
       /rest/v1/*  -> PostgREST on the throw-away test database
       /auth/v1/*  -> sign-in for the test logins (cafe@ / owner@ / contador@test.local, password "test"),
                      sessions signed with the TEST secret only
       /storage/v1/* -> empty answers
   config.js maps 127.0.0.1 to the "local" environment, so the pages talk to this and never to Supabase. */
'use strict';
const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const SECRET = 'canopy-local-test-secret-not-for-production-0123';
const USERS = {
  'cafe@test.local': 'c0000000-0000-4000-8000-000000000001',
  'owner@test.local': '0e000000-0000-4000-8000-000000000002',
  'contador@test.local': 'ac000000-0000-4000-8000-000000000003'
};
const b64u = (x) => Buffer.from(x).toString('base64url');
function sign(payload) {
  const h = b64u(JSON.stringify({ alg: 'HS256', typ: 'JWT' })), p = b64u(JSON.stringify(payload));
  return h + '.' + p + '.' + crypto.createHmac('sha256', SECRET).update(h + '.' + p).digest('base64url');
}
function decode(tok) {
  try {
    const [h, p, s] = String(tok).split('.');
    if (crypto.createHmac('sha256', SECRET).update(h + '.' + p).digest('base64url') !== s) return null;
    return JSON.parse(Buffer.from(p, 'base64url').toString());
  } catch (e) { return null; }
}
function session(uid, email, aal) {
  const now = Math.floor(Date.now() / 1000), exp = now + 3600;
  const access = sign({ sub: uid, role: 'authenticated', aud: 'authenticated', aal: aal || 'aal1', email, iat: now, exp,
                        amr: [{ method: 'password', timestamp: now }], session_id: crypto.randomUUID() });
  const user = { id: uid, aud: 'authenticated', role: 'authenticated', email, app_metadata: { provider: 'email' },
                 user_metadata: {}, factors: [], created_at: '2026-01-01T00:00:00Z' };
  return { access_token: access, token_type: 'bearer', expires_in: 3600, expires_at: exp,
           refresh_token: b64u(JSON.stringify({ uid, email, aal: aal || 'aal1', n: crypto.randomUUID() })), user };
}
function sessionFor(email, aal) { return session(USERS[email], email, aal); }

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, prefer, x-client-info, accept-profile, content-profile, x-hg-unlock, range, x-supabase-api-version',
  'Access-Control-Allow-Methods': 'GET, POST, PATCH, PUT, DELETE, OPTIONS',
  'Access-Control-Expose-Headers': 'content-range, content-location, x-total-count'
};
function send(res, status, body, extra) {
  res.writeHead(status, Object.assign({ 'Content-Type': 'application/json' }, CORS, extra || {}));
  res.end(body === undefined ? '' : (typeof body === 'string' ? body : JSON.stringify(body)));
}
function readBody(req) {
  return new Promise((ok) => { const c = []; req.on('data', (d) => c.push(d)); req.on('end', () => ok(Buffer.concat(c))); });
}

function supabaseHandler(opts) {
  return async (req, res) => {
    const u = new URL(req.url, 'http://x');
    if (req.method === 'OPTIONS') return send(res, 204);
    if (opts.offline && opts.offline()) { req.socket.destroy(); return; }       // simulate "no internet"
    const body = await readBody(req);
    if (u.pathname.startsWith('/rest/v1/')) {
      const target = 'http://127.0.0.1:' + opts.postgrestPort + u.pathname.slice('/rest/v1'.length) + u.search;
      const headers = Object.assign({}, req.headers); delete headers.host; delete headers['content-length'];
      if (!headers.authorization || /^Bearer\s*$/.test(headers.authorization)) headers.authorization = 'Bearer ' + req.headers.apikey;
      try {
        const r = await fetch(target, { method: req.method, headers, body: ['GET', 'HEAD'].includes(req.method) ? undefined : body });
        const buf = Buffer.from(await r.arrayBuffer());
        const h = {}; r.headers.forEach((v, k) => { if (!['content-encoding', 'transfer-encoding', 'connection'].includes(k) && !k.startsWith('access-control-')) h[k] = v; });
        res.writeHead(r.status, Object.assign(h, CORS)); return res.end(buf);
      } catch (e) { return send(res, 503, { message: 'PostgREST unavailable: ' + e.message }); }
    }
    if (u.pathname === '/auth/v1/token') {
      let p = {}; try { p = JSON.parse(body.toString() || '{}'); } catch (e) {}
      const grant = u.searchParams.get('grant_type');
      if (grant === 'password') {
        if (!USERS[p.email] || p.password !== 'test') return send(res, 400, { error: 'invalid_grant', error_description: 'Invalid login credentials', code: 'invalid_credentials' });
        return send(res, 200, sessionFor(p.email));
      }
      if (grant === 'refresh_token') {
        try { const r = JSON.parse(Buffer.from(p.refresh_token, 'base64url').toString()); return send(res, 200, session(r.uid, r.email, r.aal)); }
        catch (e) { return send(res, 400, { error: 'invalid_grant', code: 'refresh_token_not_found' }); }
      }
      return send(res, 400, { error: 'unsupported_grant_type' });
    }
    if (u.pathname === '/auth/v1/user') {
      const claims = decode((req.headers.authorization || '').replace(/^Bearer\s+/i, ''));
      if (!claims || !claims.sub) return send(res, 401, { message: 'invalid JWT', code: 'bad_jwt' });
      return send(res, 200, { id: claims.sub, aud: 'authenticated', role: 'authenticated', email: claims.email, factors: [],
                              app_metadata: { provider: 'email' }, user_metadata: {} });
    }
    if (u.pathname === '/auth/v1/logout') return send(res, 204);
    if (u.pathname.startsWith('/auth/v1/')) return send(res, 200, {});
    if (u.pathname.startsWith('/storage/v1/object/list')) return send(res, 200, []);
    if (u.pathname.startsWith('/storage/v1/')) return send(res, 404, { message: 'not found (test storage)' });
    return send(res, 404, { message: 'unknown path ' + u.pathname });
  };
}

const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'application/javascript', '.css': 'text/css', '.json': 'application/json',
                '.svg': 'image/svg+xml', '.png': 'image/png', '.jpg': 'image/jpeg', '.webp': 'image/webp', '.ico': 'image/x-icon',
                '.txt': 'text/plain', '.xml': 'application/xml', '.mp4': 'video/mp4', '.woff2': 'font/woff2' };
function staticHandler(root) {
  return (req, res) => {
    let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
    if (p.endsWith('/')) p += 'index.html';
    let f = path.join(root, p);
    if (!f.startsWith(root)) { res.writeHead(403); return res.end(); }
    if (!fs.existsSync(f) && fs.existsSync(f + '.html')) f += '.html';
    if (!fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(404); return res.end('not found'); }
    res.writeHead(200, { 'Content-Type': TYPES[path.extname(f)] || 'application/octet-stream', 'Cache-Control': 'no-store' });
    fs.createReadStream(f).pipe(res);
  };
}

function start(opts) {
  const site = http.createServer(staticHandler(opts.siteRoot));
  const api = http.createServer(supabaseHandler(opts));
  return Promise.all([
    new Promise((ok) => site.listen(opts.sitePort || 8090, '0.0.0.0', ok)),
    new Promise((ok) => api.listen(54321, '127.0.0.1', ok))
  ]).then(() => ({ close: () => { site.close(); api.close(); } }));
}

module.exports = { start, sessionFor, sign, SECRET, USERS };
