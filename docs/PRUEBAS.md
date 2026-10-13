# Ambiente de pruebas (staging) de Canopy OS

**Para qué sirve:** probar cada versión nueva con una copia **anonimizada** de los datos reales, antes de tocar
producción. El sitio de pruebas **nunca** se conecta a la base de producción.

| | Producción | Pruebas |
|---|---|---|
| Sitio | hanginggardencafe.com | jeanpaulcocaleca-create.github.io/canopy-pruebas |
| Base | proyecto actual de Supabase | proyecto nuevo y gratuito "canopy-pruebas" |
| Datos | los reales | anonimizados: "Persona N", huéspedes sin nombre ni teléfono, sin notas ni ingresos; otro PIN |
| Quién publica | usted, con una etiqueta y PUBLICAR | usted, con un botón en el repositorio canopy-pruebas |

Cómo se garantiza que pruebas no toque producción:

- `website/config.js` decide la base por la dirección del sitio. La dirección de pruebas **solo** puede usar el
  proyecto de pruebas. Si alguien pusiera ahí la dirección o la llave de producción, la página se bloquea
  (probado en cada cambio: `tests/tools/config-check.js`).
- La publicación de pruebas (`poner-pruebas.py`) se niega si le dan la dirección de producción, una llave que no
  sea la pública "anon", o la llave de otro proyecto.
- El ensayo (`ensayo.sh`) lee producción solo con la cuenta de **solo lectura** (se niega con cualquier otra) y se
  niega si la dirección de pruebas es la de producción.

Qué datos llegan a pruebas: montos, cantidades, fechas, menú e inventario, tal cual. Nombres del personal,
huéspedes, proveedores, teléfonos, correos, notas, motivos, descripciones, referencias, nombres de los aparatos,
ingresos y llaves se reemplazan **antes** de salir del trabajo de GitHub (`anonimizar.sql`). Si una versión nueva
agrega una columna de texto que `anonimizar.sql` no conoce, el ensayo se detiene antes de copiar nada y la nombra.
Cuando haya planillas, las tarifas y los montos de pago también llegan, con nombres "Persona N": solo usted ve
pruebas.

## Cuándo

- **Después del primer respaldo verificado** (usa el mismo repositorio privado y su cuenta de solo lectura):
  docs/PRODUCTION-READINESS.md sección 8, paso C; docs/LANZAMIENTO.md, ola 0, paso 4.
- **Antes de la ventana 0003–0025**, obligatorio. La ola 0 (0000–0002) no lo espera: es urgente y ya se ensayó
  con la copia representativa. Si pruebas se arma después de la ola 0, el ensayo aplica solo las que faltan.

## Instalación (una sola vez, unos 40 minutos)

Requisito: el repositorio privado `canopy-respaldos` instalado y su primer respaldo en verde (docs/RESPALDOS.md).

### 1 · Proyecto de pruebas en Supabase (gratis)

1. Vea el plan de la organización del café (Supabase → la organización → **Billing**; E-10):
   - **Free**: el plan gratis da **dos proyectos gratis activos**, sumando todas las organizaciones donde usted es
     Owner o Administrator (los pausados no cuentan). Pruebas es el segundo: si ya tiene otro proyecto gratis
     activo (que no sea el del café), páuselo antes o Supabase no deja crear este. **Nunca pause el proyecto del café**:
     la caja dejaría de guardar ventas en el sistema.
   - **Pro** (u otro de pago): cada proyecto de esa organización se cobra aparte (unos US$10 al mes). Cree primero
     una organización nueva en plan **Free** (por ejemplo `canopy-pruebas`) y el proyecto dentro de ella.
2. **New project** → nombre `canopy-pruebas`, la **misma región** que producción (la muestra el proyecto de
   producción en **Project Settings → General**).
3. Contraseña de la base: use **Generate a password** (solo letras y números; una propia con `@ # / ? %` rompe la
   dirección del paso 2) y guárdela en su gestor de contraseñas. No la comparta.
4. **Security**: compruebe que **Enable Data API** y **Automatically expose new tables** estén marcados (márquelos si
   no lo están) y **Enable automatic RLS** desmarcado, como producción (que se creó antes de estas opciones). La RLS automática agrega una función que
   producción no tiene y el ensayo se detendría: "PRUEBAS quedó con permisos distintos de producción".
5. En el proyecto nuevo: **Authentication → Sign In / Providers** → apague **Allow new users to sign up** y deje
   apagado **Allow anonymous sign-ins**.

(El plan gratuito pausa un proyecto después de una semana sin uso: se reactiva con **Restore** en el panel.)

### 2 · Secretos del ensayo (repositorio privado `canopy-respaldos`)

1. Suba al repositorio privado los archivos nuevos de `ops/backup/repositorio-respaldos/`:
   `ensayo.sh`, `anonimizar.sql`, `.github/workflows/ensayo-pruebas.yml` (y las versiones nuevas de `backup.sh`,
   `restore-stub.sql`, `.github/workflows/respaldo.yml`).
   Si los subió antes, vuelva a subir esos tres: cambiaron el 2026-10-13. Ahora anonimizan todo texto libre, los
   nombres de los aparatos, los enlaces de seguimiento y los códigos QR de habitación; se detienen ante una columna
   de texto desconocida; leen producción solo con la cuenta de solo lectura; y un paso que falle no deja datos ni
   escribe en el registro ninguna fila, el PIN de pruebas ni contraseñas.
2. **Settings → Secrets and variables → Actions → New repository secret**:
   - `STAGING_DB_URL`: proyecto de **PRUEBAS** → **Connect** → **Connection String** → **Session pooler** →
     copie la dirección (empieza con `postgresql://postgres.<ref-de-pruebas>:` y termina en
     `pooler.supabase.com:5432/postgres`), cambie `[YOUR-PASSWORD]` por la contraseña del punto 1.3 y agregue al
     final `?sslmode=require` (si ya trae un `?`: `&sslmode=require`). No la "Direct connection": GitHub no la
     alcanza (docs/RESPALDOS.md, paso 3.4).
   - `STAGING_PIN`: un número de 4 a 8 dígitos que solo se usa en pruebas, distinto de todo PIN real (todas las
     personas lo tendrán allí).
   - `CANOPY_DB_URL` y la variable `SUPABASE_URL` ya están, del respaldo: el ensayo lee producción con ellas.

### 3 · Primera copia y ensayo

`canopy-respaldos` → **Actions → Ensayo en pruebas → Run workflow** → versión: la rama de desarrollo →
vaciar: `no`. Al terminar (unos 5 minutos) debe estar en verde y el resumen dice **unchanged: … original tables**.

Qué hace: copia producción (solo lectura) → la anonimiza en una base desechable → la carga en pruebas → aplica
las migraciones nuevas en pruebas → compara antes y después (ventas, partes de cuentas, anulaciones, descuentos,
caja, inventario, horas, personal y bitácora deben quedar idénticos; permisos y reglas, los esperados).
Para repetirlo desde cero más adelante: vaciar = `si` (solo vacía **pruebas**).
Si queda en rojo: el mensaje en rojo dice el paso y nunca muestra datos; mándemelo tal cual.

### 4 · Ingresos de pruebas

1. Proyecto de **PRUEBAS** → **Authentication → Users → Add user → Create new user**, marcando
   **Auto Confirm User**:
   - `cafe.pruebas@hanginggardencafe.com`
   - `dueno.pruebas@hanginggardencafe.com`
   (contraseñas nuevas, solo suyas)
2. Proyecto de **PRUEBAS** → **SQL Editor** → pegue todo `supabase/tools/staging-logins.sql` → Run.
   Si por error lo pega en producción, se niega (producción tiene nombres reales e ingresos que no son de pruebas).

### 5 · Sitio de pruebas

1. GitHub → **New repository** → `canopy-pruebas` → **Public** (GitHub Pages gratis lo pide; solo contiene
   código que ya es público).
2. Suba el contenido de `ops/staging/repositorio-pruebas/` (incluida la carpeta `.github`).
3. **Settings → Secrets and variables → Actions**:
   - pestaña **Variables** → `STAGING_SUPABASE_URL`: proyecto de PRUEBAS → **Connect** → *Project URL*
     (`https://<ref-de-pruebas>.supabase.co`).
   - pestaña **Secrets** → `STAGING_SUPABASE_ANON_KEY`: proyecto de PRUEBAS → **Project Settings → API Keys**,
     pestaña *Legacy* → **anon public** (empieza con `eyJ`). Nunca la *service_role* ni una *secret*
     (`sb_secret_…`). Va como secreto aunque es pública: así no aparece en el registro, que aquí ve cualquiera.
4. **Actions → Publicar el sitio de PRUEBAS → Run workflow** (versión: la rama de desarrollo): crea `gh-pages`.
5. **Settings → Pages** → Source: **Deploy from a branch** → `gh-pages` / `(root)` → Save.
6. Corra el paso 4 **otra vez**: la primera publicación con la llave de GitHub no enciende el sitio.
7. Abra `https://jeanpaulcocaleca-create.github.io/canopy-pruebas/pos`: abajo a la izquierda debe verse la
   etiqueta naranja **PRUEBAS · no es la caja real**. Entre con `cafe.pruebas@…`.

## Uso

- **Antes de cada lanzamiento:** Ensayo en pruebas (vaciar = `si`) → `staging-logins.sql` otra vez (paso 4.2: cada
  copia llega sin ingresos) → Publicar el sitio de PRUEBAS con la misma versión → la lista de verificación de
  `docs/LANZAMIENTO.md` en el sitio de pruebas.
- La prueba de restauración trimestral (docs/RESPALDOS.md) carga datos **reales** en pruebas: al terminarla,
  corra el Ensayo en pruebas con vaciar = `si` y `staging-logins.sql`, y pruebas vuelve a la copia anonimizada.
- Las fotos del menú y los videos no se copian a pruebas: el menú de pruebas muestra las fotos públicas de
  producción (como cualquier visitante) y subir una foto en pruebas no funciona.
- Pruebas no envía comprobantes ni nada a Hacienda.
