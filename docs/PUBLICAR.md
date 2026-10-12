# Publicar una versión en el café (y cómo volver atrás)

El sitio real del café (caja, cocina, TV, menú QR, áreas del dueño) **solo se publica a mano**, por usted,
desde una **versión aprobada**. Hacer *push* a una rama ya **no** publica nada (desde el 2026-10-12).

## Antes de publicar (lista de verificación)

1. **Pruebas automáticas en verde.** GitHub → Actions → "Tests" de la última versión: ✅.
2. **Revisada en pruebas (staging).** Ventas en efectivo y tarjeta, una cuenta abierta pagada en partes,
   un descuento con PIN, el cierre de caja, la cocina y el menú QR funcionan en `staging.hanginggardencafe.com`.
3. **Respaldo reciente.** La tarjeta **Respaldos** está en verde, o se pidió un respaldo inmediato
   (docs/RESPALDOS.md).
4. **Migraciones aplicadas primero.** Si la versión trae migraciones nuevas, péguelas en el SQL Editor de
   producción **antes** de publicar las páginas (docs/MIGRACIONES.md). Las páginas nuevas siempre funcionan
   con la base vieja, pero las funciones nuevas necesitan la base nueva.
5. **Fuera de horario.** Después del cierre de caja o antes de las 6:00.
6. **Sin ventas pendientes en las tabletas.** Ninguna tableta muestra "pendiente de enviar".

## Publicar

1. GitHub → **Releases → Draft a new release**.
2. Etiqueta `vAAAA.MM.DD-N` (por ejemplo `v2026.10.20-1`) sobre la rama aprobada → **Publish release**.
3. GitHub → **Actions → "Publish website (PRODUCTION · manual only)" → Run workflow**.
   - En **Use workflow from**, elija **Tags → la etiqueta nueva**.
   - Escriba **PUBLICAR** en la casilla.
   - Presione **Run workflow**.
4. En 2–10 minutos el sitio muestra la versión nueva. Las tabletas la cargan solas cuando están libres
   (sin una venta a medias). Si alguna no cambia, recárguela.

Si el trabajo no parte de una etiqueta `v…`, o la casilla no dice PUBLICAR, se detiene sin publicar nada.

## Volver a la versión anterior (rollback)

- **Páginas:** repita "Publicar" eligiendo la **etiqueta anterior**. Es la misma operación con una versión
  más vieja.
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
