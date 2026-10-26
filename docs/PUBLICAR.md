# Publicar una versión en el café (y cómo volver atrás)

El sitio real del café (caja, cocina, TV, menú QR, áreas del dueño) **solo se publica a mano**, por usted,
desde una **versión aprobada**. Hacer *push* a una rama ya **no** publica nada (desde el 2026-10-12).

## Antes de publicar (lista de verificación)

1. **Pruebas automáticas en verde.** GitHub → Actions → "Tests" de la última versión: ✅.
2. **Ensayo en pruebas en verde.** En `canopy-respaldos` → Actions → "Ensayo en pruebas", con la rama o la etiqueta
   que se va a publicar, destino `desechable`, vaciar `no`, reinicio `no` (docs/PRUEBAS.md). Ya no hay sitio de pruebas
   (D-039): las páginas se prueban en las pruebas automáticas.
3. **Respaldo reciente.** La tarjeta **Respaldos** está en verde, o se pidió un respaldo inmediato
   (docs/RESPALDOS.md).
4. **Migraciones aplicadas primero.** Si la versión trae migraciones nuevas, péguelas en el SQL Editor de
   producción **antes** de publicar las páginas (docs/MIGRACIONES.md). Las páginas nuevas siempre funcionan
   con la base vieja, pero las funciones nuevas necesitan la base nueva.
5. **Fuera de horario.** Después del cierre de caja o antes de las 6:00.
6. **Sin ventas pendientes en las tabletas.** En cada Caja el aviso de conexión dice «en línea» y, al tocarlo, «Todo lo
   que se tomó en este dispositivo está guardado en el sistema.». Si dice «guardando N…», «N sin guardar todavía»,
   «sin conexión · N en este dispositivo» o «no guardado en este dispositivo», espere a que se vacíe. «Hoy en el
   mostrador» cerrado (la Caja puede recargarse aunque esa ventana esté abierta, y se pierde lo escrito en ella) y
   ningún formulario a medio escribir en ninguna pantalla del personal (Inventario, Contabilidad, Inicio, Gestor del
   menú, Reloj…).

## Una sola vez, antes de la primera versión (hecho el 2026-10-15, E-19)

El sitio que está hoy en el café no salió de una versión aprobada (se publicó solo, el 2026-10-09). Para poder
volver a él si la primera versión fallara, guárdelo con un nombre:

1. GitHub → **Releases → Draft a new release**.
2. **Choose a tag** → escriba `sitio-2026-10-09` → **Create new tag**. En **Target** elija la rama **gh-pages**.
3. Título: "Sitio del café antes de las versiones". Marque **Set as a pre-release** → **Publish release**.

Recomendado también (Settings → Environments → **production**):

- **Required reviewers**: usted. Cada publicación espera su aprobación con un clic, aunque alguien más la inicie.
- **Deployment branches and tags** → *Selected* → agregue la regla de etiqueta `v*`.

**El flujo debe estar en la rama predeterminada.** GitHub solo muestra el botón **Run workflow** de un flujo que exista
en la rama predeterminada del repositorio (hoy `claude/festive-galileo-0twc1p`), aunque «Use workflow from» permita
elegir después cualquier etiqueta. La noche del lanzamiento (2026-10-15 UTC) el botón no aparecía porque esa rama no
tenía la carpeta `.github/workflows/`; con la aprobación del dueño se subió allí solo `pages.yml`, idéntico al de la
etiqueta (`c1ffbf1`), y el botón apareció. Si algún día cambia la rama predeterminada, el archivo debe existir también
en la nueva.

## Publicar

1. GitHub → **Releases → Draft a new release**.
2. Etiqueta `vAAAA.MM.DD-N` (por ejemplo `v2026.10.20-1`) sobre la rama aprobada → **Publish release**. Antes, compruebe
   que el último commit de la rama es el aprobado (nadie sube nada a la rama mientras tanto); después, en **Tags**, que la
   etiqueta muestra ese commit. Si muestra otro, no publique: cree la siguiente (`…-2`) en el commit correcto; una
   etiqueta nunca se mueve. Conviene también guardar el sitio de hoy como `sitio-AAAA-MM-DD` (sección «Una sola vez»,
   con Target = **gh-pages**) para tener una vuelta atrás exacta.
3. GitHub → **Actions → "Publish website (PRODUCTION · manual only)" → Run workflow**.
   - En **Use workflow from**, elija **Tags → la etiqueta nueva**.
   - Escriba **PUBLICAR** en la casilla.
   - Presione **Run workflow**.
4. En 2–10 minutos el sitio muestra la versión nueva. Las tabletas la cargan solas cuando están libres:
   la caja muestra **"actualización lista"** en el aviso de conexión y se recarga sola entre ventas (nunca con
   una venta a medias ni con ventas sin subir); las demás pantallas muestran un aviso arriba con el botón
   **Actualizar ahora**. Revisan cada 5 minutos. Si alguna no cambia en 15 minutos, recárguela.

Si el trabajo no parte de una etiqueta `v…`, o la casilla no dice PUBLICAR, se detiene sin publicar nada.

**Comprobar:** abra `https://hanginggardencafe.com/version.json`: debe decir la etiqueta nueva. Además, cada
prueba automática revisa que lo publicado sea una versión aprobada (`tests/tools/live-site-check.sh`) y se pone
en rojo si alguna vez no lo es.

## Volver a la versión anterior (rollback)

- **Páginas:** repita "Publicar" eligiendo la **etiqueta anterior**. Es la misma operación con una versión
  más vieja.
- **Volver al sitio de antes de la primera versión:** "Publicar" desde la etiqueta de la versión actual, con
  PUBLICAR y, en la casilla **restaurar**, `sitio-2026-10-09`. Se publica esa copia tal como estaba.
  Las páginas viejas funcionan con la base nueva (probado en el ensayo: `tests/rehearsal/live-pages.sh`).
- **Base de datos:** las migraciones **no** se deshacen borrando. Si una migración causó un problema:
  1. Avíseme con el mensaje de error.
  2. Preparo una **migración de corrección** (el siguiente número) que se aplica igual que las demás.
  3. Cada migración trae al final una sección **Reversión** que explica qué hacer.
- **Funciones nuevas que se pueden apagar:** varias funciones nuevas tienen un interruptor en la base
  (por ejemplo, "precios sin IVA", "exigir empleado en cada venta", "facturación electrónica"). Apagarlo
  vuelve al comportamiento anterior sin publicar nada.
- **Último recurso:** restaurar un respaldo (docs/RESPALDOS.md). Solo con su autorización expresa.

## Opción fuerte recomendada: un repositorio solo suyo para publicar

Hoy el flujo de publicación vive en este repositorio, al que también tienen acceso las sesiones de
asistentes de IA (con permisos de administrador de su cuenta). Las reglas (`CLAUDE.md`) les prohíben
publicar. Para que sea **imposible**:

1. Cree un repositorio **privado** nuevo, por ejemplo `canopy-produccion`, y **no lo conecte** a sesiones de
   IA.
2. Muévale el dominio `hanginggardencafe.com` (Settings → Pages). Desde ahí se publica una etiqueta del
   repositorio de desarrollo con un botón.
3. Este repositorio queda para desarrollo y pruebas (`staging.hanginggardencafe.com`).

Le preparo el flujo de ese repositorio cuando decida hacerlo. Está en `docs/DEPENDENCIES.md`.
