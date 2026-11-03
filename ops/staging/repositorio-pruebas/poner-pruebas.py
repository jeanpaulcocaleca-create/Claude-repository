"""Canopy OS · point a copy of website/config.js at the STAGING project (used by publicar-pruebas.yml).
python3 poner-pruebas.py <config.js> <staging url> <staging anon key>
Refuses: an address that is not https://<project>.supabase.co, the production project, and any key that is not the
project's PUBLIC "anon" key (a service_role key would give the pages full access: it never goes in a page)."""
import base64
import json
import re
import sys

path, url, key = sys.argv[1], sys.argv[2].strip().rstrip('/'), sys.argv[3].strip()


def fail(msg):
    print('::error::' + msg)
    sys.exit(1)


src = open(path, encoding='utf-8').read()
m = re.match(r'^https://([a-z0-9]{10,40})\.supabase\.co$', url)
if not m:
    fail('STAGING_SUPABASE_URL debe ser https://<proyecto>.supabase.co')
ref = m.group(1)
prod = re.search(r"production: \{ url: 'https://([a-z0-9]+)\.supabase\.co'", src)
if not prod:
    fail('no se encontró la dirección de producción en config.js')
if ref == prod.group(1):
    fail('ESA ES LA BASE DE PRODUCCIÓN. El sitio de pruebas nunca se conecta a producción. No se publicó nada.')
# Supabase's newer keys: a secret one must never reach a page; these pages (supabase-js 2.49) use the anon key
if key.startswith('sb_secret_'):
    fail('ESA ES UNA LLAVE SECRETA (sb_secret_…): nunca va en una página. Ponga la llave anon en su lugar. No se publicó nada.')
if key.startswith('sb_publishable_'):
    fail('STAGING_SUPABASE_ANON_KEY: use la llave "anon" (empieza con eyJ): Project Settings → API Keys, '
         'pestaña Legacy → anon public')
try:
    payload = json.loads(base64.urlsafe_b64decode(key.split('.')[1] + '=' * (-len(key.split('.')[1]) % 4)))
except Exception:  # noqa: BLE001
    payload = None
if not payload or payload.get('role') != 'anon':
    fail('STAGING_SUPABASE_ANON_KEY debe ser la llave pública "anon" del proyecto de pruebas (nunca la service_role)')
if payload.get('ref') and payload['ref'] != ref:
    fail('la llave anon no es del proyecto de pruebas indicado')
line = "staging: { url: '', key: '' },"
if src.count(line) != 1:
    fail('config.js cambió: no se encontró la línea de pruebas')
src = src.replace(line, "staging: { url: '%s', key: '%s' }," % (url, key))
open(path, 'w', encoding='utf-8').write(src)
print('config.js apunta al proyecto de pruebas ' + ref)
