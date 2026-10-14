# Ensayo en pruebas de Canopy OS (sin proyecto de pruebas)

**Para qué sirve:** ensayar, con una copia **anonimizada** de los datos reales, exactamente lo que usted hará en la
ventana del lanzamiento único (docs/LANZAMIENTO-UNICO.md, D-038): el reinicio operativo y las migraciones 0000–0028,
con los mismos archivos y en el mismo orden, antes de tocar producción. Producción solo se **lee**.

**Decisión del dueño (2026-10-14):** el café se queda con su proyecto actual de Supabase y su sitio actual; **no se
crea un segundo proyecto de Supabase** ni se migra la base a otro lado. Por eso el ensayo corre, por defecto, en una
**base temporal dentro del trabajo de GitHub** (destino `desechable`): un PostgreSQL que el propio trabajo levanta,
se hace parecer a Supabase (`restore-stub.sql`: cuentas anon/authenticated/service_role, esquemas auth y storage,
permisos por defecto) y desaparece al terminar. No hay nada que crear, pagar ni pausar, y no queda ninguna copia.

| | Producción | Ensayo (destino `desechable`) |
|---|---|---|
| Sitio | hanginggardencafe.com (no cambia) | ninguno: las páginas se prueban en CI contra la misma clase de copia (`tests/rehearsal/reset-pages.sh`) |
| Base | proyecto actual de Supabase (no cambia) | base «pruebas» en el PostgreSQL temporal del trabajo; desaparece al terminar |
| Datos | los reales | anonimizados: "Persona N", huéspedes sin nombre ni teléfono, sin notas ni ingresos; PIN 2468 |
| Quién la toca | usted, en la ventana | el trabajo de GitHub, con el botón; nadie entra ni ve la copia |

Cómo se garantiza que el ensayo no toque producción:

- `ensayo.sh` lee producción solo con la cuenta de **solo lectura** `canopy_backup` (se niega con cualquier cuenta
  que pudiera escribir) y se niega si la dirección de destino contiene el proyecto de producción o si la base
  desechable fuera un proyecto de Supabase.
- La copia se anonimiza en el PostgreSQL del trabajo **antes** de cargarse en cualquier parte (`anonimizar.sql`) y los
  archivos con datos reales se borran al terminar, también cuando un paso falla. El registro muestra pasos, cantidades
  y tiempos: ni filas, ni el PIN, ni contraseñas.
- Los archivos SQL del repositorio público (reinicio, migraciones, revisiones) llegan a la base como texto, con
  `psql -c`: ningún comando de psql ni de la terminal escrito en ellos se ejecuta en el trabajo.

Qué datos entran en la copia: montos, cantidades, fechas, menú e inventario, tal cual. Nombres del personal,
huéspedes, proveedores, teléfonos, correos, notas, motivos, descripciones, referencias, nombres de los aparatos,
ingresos y llaves se reemplazan antes (`anonimizar.sql`). Si una versión nueva agrega una columna de texto que
`anonimizar.sql` no conoce, el ensayo se detiene antes de copiar nada y la nombra.

## Cuándo

- **Después del primer respaldo verificado** (E-03): usa el mismo repositorio privado y su cuenta de solo lectura.
- **Antes de la ventana del lanzamiento único**, obligatorio, con `reinicio = si` y la etiqueta que se va a lanzar.
  Si la versión a lanzar cambia, se repite: cuesta unos cinco minutos y no deja nada.

## Instalación (una sola vez, unos 10 minutos)

Requisito: el repositorio privado `canopy-respaldos` con su respaldo en verde (docs/RESPALDOS.md). **No hace falta
ningún secreto nuevo**: producción se lee con `CANOPY_DB_URL` y la variable `SUPABASE_URL`, que ya están.

1. Suba (reemplazando) al repositorio privado estos archivos de `ops/backup/repositorio-respaldos/`:
   `.github/workflows/ensayo-pruebas.yml`, `ensayo.sh`, `anonimizar.sql` y `restore-stub.sql`. El flujo y `ensayo.sh`
   cambiaron el **2026-10-14** (la opción `reinicio` y el destino `desechable`); `anonimizar.sql` y
   `restore-stub.sql`, el 2026-10-13 (si los subió después de esa fecha, ya están al día).
2. Nada más. El secreto `STAGING_PIN` es opcional para este destino: sin él, todas las personas de la copia quedan con
   el PIN `2468` (en una base desechable nadie entra). `STAGING_DB_URL` solo existe para la última sección.

## Ensayo

`canopy-respaldos` → **Actions → Ensayo en pruebas → Run workflow** → versión: la etiqueta o rama a lanzar →
destino: `desechable` → vaciar: `no` → reinicio: `si`. Al terminar (unos 5 minutos) debe estar en **verde**.
(`vaciar` solo tiene sentido con un proyecto de pruebas: la base desechable nace vacía.)

Qué hace, en orden, dentro del trabajo:

1. Levanta un PostgreSQL 17 temporal, crea en él la base «pruebas» y la hace parecer a Supabase (`restore-stub.sql`;
   sin el depósito de fotos del menú, como un proyecto de pruebas).
2. Copia producción con la cuenta de solo lectura, la anonimiza en otra base del mismo servidor y carga la copia en
   «pruebas» con los permisos de producción (si quedaran distintos, se detiene). Toma la foto y la revisión de
   consistencia ANTES (`snapshot-before.json`, `consistency-before.json`).
3. Con reinicio = `si`, antes de las migraciones:
   - **cierra el café en la copia**: la copia se toma mientras el café trabaja, y el reinicio se niega con una venta o
     una marca del reloj de la última hora o una caja abierta (como hará en producción); en la copia, esas ventas y
     marcas se fechan dos horas antes y la caja abierta se cierra. El registro dice cuántas (`café cerrado en la copia:
     N venta(s)…, N caja(s)`);
   - guarda el **resumen del periodo para el contador** (`resumen-pruebas.sql` → `resumen.json`), como usted lo
     guardará con el respaldo antes del reinicio real;
   - ejecuta **`reinicio-operativo.sql` tal cual**, con la referencia `ensayo <fecha y hora UTC>` y la palabra
     `BORRAR PRUEBAS` en la última línea (lo mismo que usted escribirá a mano), enviado como una sola consulta; debe
     responder `reinicio hecho`, si no, el ensayo se detiene;
   - toma otra foto y revisión (`snapshot-after-reset.json`, `consistency-after-reset.json`).
4. Aplica las migraciones 0000–0028 una por una, como un pegado en el SQL Editor, y anota cuánto tardó cada una
   (`timings.txt`); foto y revisión DESPUÉS; `release-check.sql` (`release-check.json`).
5. Compara (`compare.py`, modo `reset`): lo que quedó **justo después del reinicio** debe ser idéntico a lo que hay
   **después de las migraciones** (ventas, caja, inventario en cero, horas, personal, bitácora), y la estructura, las
   reglas de filas, los permisos y los ajustes (regulados apagados) deben ser los esperados. Con reinicio = `no`
   compara ANTES con DESPUÉS y exige `unchanged: … original tables`.
6. El trabajo termina y el PostgreSQL temporal desaparece con la copia.

Qué leer, en el registro del paso «Copiar, anonimizar, cargar…»:

- `reinicio hecho · respaldo ensayo …`;
- `borrado: …`: filas borradas por tabla (`orders`, `order_items`, `register_days`, `time_entries`, `stock_moves`,
  `purchase_orders`…) y `stock_items_a_cero` (cuántos insumos tenían existencias y quedaron en 0);
- `conservado idéntico: …`: menú, recetas, insumos, proveedores, personal, ingresos, ajustes, pizarra, habitaciones y
  bitácora, con huellas iguales antes y después del reinicio;
- el tiempo de cada migración y, en el paso siguiente, la comparación (también en el resumen del trabajo).

En **Artifacts** (`ensayo-resultados-desechable`) quedan `resumen.json` (el resumen del periodo: cantidades y totales
por día y por medio de pago, sin nombres), `reinicio.txt` (la respuesta completa del reinicio), las fotos y revisiones
de antes, de después del reinicio y de después de las migraciones, `release-check.json` y `timings.txt`. Ninguno trae
datos de personas: solo cantidades, totales y huellas. Las cifras de `resumen.json` son las de la copia anonimizada
(los montos y las fechas son los reales; los nombres no viajan). Guarde `timings.txt`: es la referencia de cuánto
tardará cada pegado en la ventana.

Si queda en **rojo**: el mensaje en rojo dice el paso y nunca muestra datos; mándemelo tal cual.
Con `el reinicio operativo se negó en PRUEBAS`, la línea `ERROR` de arriba dice el motivo, el mismo que daría en
producción (ya migrada, ya hecho, una venta reciente, una caja abierta, una tabla conservada que cambiaría): en la copia
no cambió nada. Con `la copia en PRUEBAS ya tiene migraciones`, producción ya pasó la ventana: corra el ensayo con
reinicio = `no`. Con `anonimizar.sql no sabe si estas columnas guardan datos de personas: …`, la versión trae una
columna de texto nueva: no se copió nada; es trabajo mío, no suyo.

## Qué prueba este ensayo y qué no

Lo que **sí** prueba, sobre la copia anonimizada de los datos reales (CI lo prueba además en cada cambio sobre una
copia sintética de cuatro meses y 14 534 ventas, `tests/rehearsal/run.sh`):

- que `reinicio-operativo.sql` acepta la base real tal como está hoy (o dice por qué no, con el mismo mensaje que daría
  en producción), borra lo que debe y conserva idénticos menú, recetas, insumos, proveedores, personal, ingresos,
  ajustes, pizarra, habitaciones y bitácora;
- que las 29 migraciones corren en orden sobre esa base, cuánto tarda cada una, y que después de ellas nada de lo que
  quedó cambió (`compare.py`, modo `reset`);
- la estructura resultante, las reglas de filas (RLS) y los permisos de `anon`, `authenticated`, `service_role` y
  `canopy_backup` después de las migraciones (`release-check.sql`: `anon_can_run`, `tables_without_rls`…), y que lo
  regulado llega apagado;
- que la copia de producción se restaura con permisos idénticos a los de producción (si no, el ensayo se detiene),
  con la misma imitación de Supabase (`restore-stub.sql`) que verifica el respaldo nocturno.

Lo que un PostgreSQL local **no puede** probar; queda para la ventana y su verificación posterior
(docs/LANZAMIENTO-UNICO.md):

- **Supabase Auth** (GoTrue): los ingresos, la inscripción del código del teléfono (cierra las otras sesiones del
  mismo ingreso), el correo de recuperación, las sesiones reales de los iPads. La copia no trae `auth` (la cuenta de
  respaldo no lo lee).
- **Supabase Storage** por dentro (storage-api, los permisos `policy_grants` de supautils): en la base desechable las
  reglas de `storage.objects` las crea el superusuario del servidor temporal, que permite **más** que producción. Las
  sentencias de Storage de 0015 y 0025 son el riesgo residual; la consulta de seguimiento del 2026-10-13 confirmó que
  la cuenta de producción puede crear depósitos y reglas allí (`can_insert_buckets` y `policy_grants` verdaderos).
- La versión de **PostgREST** de Supabase y el tiempo que tarda en recargar su caché del esquema (las migraciones
  envían `notify pgrst`).
- El **SQL Editor**: cómo ejecuta un pegado y si corta por tiempo. Referencia: cada migración tardó menos de un segundo
  en el ensayo; el reinicio, unos 9 s sobre 14 534 ventas sintéticas, y producción tiene cerca de una semana.
- Los permisos por defecto del rol `supabase_admin` (la copia restaura solo los de `postgres`).
- **GitHub Pages**: el dominio hanginggardencafe.com y la caché del CDN después de publicar (la verja de versión
  `canopy_schema_version` hace que una página vieja diga que necesita actualizarse, sin romper nada).
- La llave `anon` real (pública, en `website/config.js`; no cambia).
- PostgreSQL **17.6** en Supabase frente a 17 en el trabajo de GitHub (16 en la computadora de desarrollo).
- En la base desechable las migraciones corren como **superusuario** del servidor temporal. Que corren también como
  la cuenta del SQL Editor, que no lo es, lo prueba CI en cada cambio (`tests/rehearsal/as-supabase.sql`).

## Si algún día quiere un proyecto de pruebas permanente

El dueño decidió el 2026-10-14 **no** crear un segundo proyecto de Supabase (la experiencia de cambiar de base en otro
proyecto pesó más que la comodidad). Esta sección queda por si cambia de idea: con un proyecto de pruebas, el mismo
ensayo corre con destino `proyecto-pruebas`, y además se puede navegar la copia desde un sitio de pruebas.

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
   no lo están) y **Enable automatic RLS** desmarcado, como producción (que se creó antes de estas opciones). La RLS
   automática agrega una función que producción no tiene y el ensayo se detendría: "PRUEBAS quedó con permisos
   distintos de producción".
5. En el proyecto nuevo: **Authentication → Sign In / Providers** → apague **Allow new users to sign up** y deje
   apagado **Allow anonymous sign-ins**.

(El plan gratuito pausa un proyecto después de una semana sin uso: se reactiva con **Restore** en el panel.)

### 2 · Secretos del ensayo (repositorio privado `canopy-respaldos`)

**Settings → Secrets and variables → Actions → New repository secret**:

- `STAGING_DB_URL`: proyecto de **PRUEBAS** → **Connect** → **Connection String** → **Session pooler** → copie la
  dirección (empieza con `postgresql://postgres.<ref-de-pruebas>:` y termina en `pooler.supabase.com:5432/postgres`),
  cambie `[YOUR-PASSWORD]` por la contraseña del punto 1.3 y agregue al final `?sslmode=require` (si ya trae un `?`:
  `&sslmode=require`). No la "Direct connection": GitHub no la alcanza (docs/RESPALDOS.md, paso 3.4).
- `STAGING_PIN`: un número de 4 a 8 dígitos que solo se usa en pruebas, distinto de todo PIN real (todas las
  personas lo tendrán allí). Con un proyecto de pruebas es obligatorio.

Primera copia: **Ensayo en pruebas** → destino `proyecto-pruebas` → vaciar `no` → reinicio `no`; debe quedar en verde
con **unchanged: … original tables**. Para repetir desde cero más adelante: vaciar = `si` (solo vacía **pruebas**).
Para el ensayo del lanzamiento: vaciar `si`, reinicio `si` (las dos opciones son independientes).

### 3 · Ingresos de pruebas

1. Proyecto de **PRUEBAS** → **Authentication → Users → Add user → Create new user**, marcando
   **Auto Confirm User**:
   - `cafe.pruebas@hanginggardencafe.com`
   - `dueno.pruebas@hanginggardencafe.com`
   (contraseñas nuevas, solo suyas)
2. Proyecto de **PRUEBAS** → **SQL Editor** → pegue todo `supabase/tools/staging-logins.sql` → Run.
   Si por error lo pega en producción, se niega (producción tiene nombres reales e ingresos que no son de pruebas).
   Cada copia llega sin ingresos: repítalo después de cada ensayo con ese destino.

### 4 · Sitio de pruebas

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

Garantías de ese sitio: `website/config.js` decide la base por la dirección del sitio y la dirección de pruebas
**solo** puede usar el proyecto de pruebas (si alguien pusiera ahí la dirección o la llave de producción, la página se
bloquea; `tests/tools/config-check.js`); el publicador de pruebas (`poner-pruebas.py`) se niega con la dirección de
producción, una llave que no sea la pública `anon` o la llave de otro proyecto. Las fotos del menú y los videos no se
copian: el menú de pruebas muestra las fotos públicas de producción y subir una foto allí no funciona. Pruebas no envía
nada a Hacienda. Con el sitio, la lista de verificación de docs/LANZAMIENTO.md se puede recorrer sobre el **café
vacío** que deja el reinicio: abrir la caja, una venta completa, un conteo de inventario, el reloj. La prueba de
restauración trimestral (docs/RESPALDOS.md) carga datos **reales** en pruebas: al terminarla, corra el ensayo con ese
destino y vaciar = `si`, y `staging-logins.sql`, para volver a la copia anonimizada.
