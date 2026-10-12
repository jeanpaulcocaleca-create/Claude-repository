# Ambiente de pruebas (staging) de Canopy OS

**Para qué sirve:** probar cada versión nueva con una copia **anonimizada** de los datos reales, antes de tocar
producción. El sitio de pruebas **nunca** se conecta a la base de producción.

| | Producción | Pruebas |
|---|---|---|
| Sitio | hanginggardencafe.com | jeanpaulcocaleca-create.github.io/canopy-pruebas |
| Base | proyecto actual de Supabase | proyecto nuevo y gratuito "canopy-pruebas" |
| Datos | los reales | copia anonimizada: "Persona N", sin teléfonos de huéspedes, otro PIN |
| Quién publica | usted, con una etiqueta y PUBLICAR | usted, con un botón en el repositorio canopy-pruebas |

Cómo se garantiza que pruebas no toque producción:

- `website/config.js` decide la base por la dirección del sitio. La dirección de pruebas **solo** puede usar el
  proyecto de pruebas. Si alguien pusiera ahí la dirección o la llave de producción, la página se bloquea
  (probado en cada cambio: `tests/tools/config-check.js`).
- La publicación de pruebas (`poner-pruebas.py`) se niega si le dan la dirección de producción, una llave que no
  sea la pública "anon", o la llave de otro proyecto.
- El ensayo (`ensayo.sh`) lee producción con la cuenta de **solo lectura** y se niega si la dirección de pruebas
  es la de producción.

## Instalación (una sola vez, unos 40 minutos)

Requisito: el repositorio privado `canopy-respaldos` ya instalado (docs/RESPALDOS.md).

### 1 · Proyecto de pruebas en Supabase (gratis)

1. supabase.com → **New project** → nombre `canopy-pruebas`, plan **Free**, la misma región que producción.
2. Contraseña de la base: use **Generate a password** y guárdela en su gestor de contraseñas. No la comparta.
3. En el proyecto nuevo: **Authentication → Sign In / Providers** → apague **Allow new users to sign up**.

(El plan gratuito pausa un proyecto después de una semana sin uso: se reactiva con **Restore** en el panel.)

### 2 · Secretos del ensayo (repositorio privado `canopy-respaldos`)

1. Suba al repositorio privado los archivos nuevos de `ops/backup/repositorio-respaldos/`:
   `ensayo.sh`, `anonimizar.sql`, `.github/workflows/ensayo-pruebas.yml` (y las versiones nuevas de `backup.sh`,
   `restore-stub.sql`, `.github/workflows/respaldo.yml`).
2. **Settings → Secrets and variables → Actions → New repository secret**:
   - `STAGING_DB_URL`: proyecto de **PRUEBAS** → **Connect** → **Session pooler** → copie la dirección, ponga la
     contraseña del punto 1.2 y agregue `?sslmode=require` al final.
   - `STAGING_PIN`: un número de 4 a 8 dígitos que solo se usa en pruebas (todas las personas lo tendrán allí).

### 3 · Primera copia y ensayo

`canopy-respaldos` → **Actions → Ensayo en pruebas → Run workflow** → versión: la rama de desarrollo →
vaciar: `no`. Al terminar (unos 5 minutos) debe estar en verde y el resumen dice **unchanged: … original tables**.

Qué hace: copia producción (solo lectura) → la anonimiza en una base desechable → la carga en pruebas → aplica las
migraciones nuevas en pruebas → compara antes y después (ventas, partes de cuentas, anulaciones, descuentos, caja,
inventario, horas, personal y bitácora deben quedar idénticos; permisos y reglas, los esperados).
Para repetirlo desde cero más adelante: vaciar = `si` (solo vacía **pruebas**).

### 4 · Ingresos de pruebas

1. Proyecto de **PRUEBAS** → **Authentication → Users → Add user → Create new user**, marcando
   **Auto Confirm User**:
   - `cafe.pruebas@hanginggardencafe.com`
   - `dueno.pruebas@hanginggardencafe.com`
   (contraseñas nuevas, solo suyas)
2. Proyecto de **PRUEBAS** → **SQL Editor** → pegue todo `supabase/tools/staging-logins.sql` → Run.
   Si por error lo pega en producción, se niega (producción tiene nombres reales).

### 5 · Sitio de pruebas

1. GitHub → **New repository** → `canopy-pruebas` → **Public** (GitHub Pages gratis lo pide; solo contiene
   código que ya es público).
2. Suba el contenido de `ops/staging/repositorio-pruebas/` (incluida la carpeta `.github`).
3. **Settings → Secrets and variables → Actions → Variables** (no son secretas):
   - `STAGING_SUPABASE_URL`: proyecto de PRUEBAS → **Project Settings → API** → *Project URL*.
   - `STAGING_SUPABASE_ANON_KEY`: en la misma página, la llave **anon public**. (Nunca la *service_role*.)
4. **Actions → Publicar el sitio de PRUEBAS → Run workflow** (versión: la rama de desarrollo).
5. **Settings → Pages** → Source: **Deploy from a branch** → `gh-pages` / `(root)` → Save.
6. Abra `https://jeanpaulcocaleca-create.github.io/canopy-pruebas/pos`: abajo a la izquierda debe verse la
   etiqueta naranja **PRUEBAS · no es la caja real**. Entre con `cafe.pruebas@…`.

## Uso

- **Antes de cada lanzamiento:** Ensayo en pruebas (vaciar = `si`) → Publicar el sitio de PRUEBAS con la misma
  versión → la lista de verificación de `docs/LANZAMIENTO.md` en el sitio de pruebas.
- Las fotos del menú y los videos no se copian a pruebas (las páginas funcionan sin ellos).
- Pruebas no envía correos, ni comprobantes, ni nada a Hacienda.
