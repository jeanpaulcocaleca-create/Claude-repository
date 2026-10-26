# Activación de la Contabilidad nueva (D-057, migraciones 0034 y 0035) · E-37

**Estado (2026-10-26):** **migraciones 0034 y 0035 aplicadas en producción** por el dueño (sección 4, «Hecho»);
**la página nueva todavía no está publicada**: el procedimiento exacto está en la sección 4, «Publicación», y la vuelta
atrás en la sección 5 (D-059). La «Orden maestra de construcción» (2026-10-26) autoriza publicar solo si se confirman
todas las condiciones de su §10 (sección 1). Los pasos en producción los hace **solo el dueño** (Jean Paul): respaldo,
SQL Editor, etiqueta y publicación. Claude no publica, no crea etiquetas y no toca la base de producción (CLAUDE.md);
sí acompaña: lee resultados, compara celdas y prepara correcciones.

## Qué se activa

- **Página nueva** `contabilidad.html` (Resumen, Gastos, Proveedores, Ingresos, Compras, Banco y efectivo, Reportes,
  Contabilidad). La ficha «Contabilidad» de Inicio y el enlace de Información la abren; `accounting.html` sigue publicada
  y se abre desde «Página de contabilidad anterior» (la planilla vive allí).
- **0034 · lecturas y regla de gastos:** proveedores con lo habitual (categoría, IVA, forma de pago), historial e
  importes por proveedor, compras con su etapa, cobros por día y forma de pago, posición de efectivo, comparación de
  períodos, auditoría. **Registrar y listar gastos solo con dueño con código o contador**: una tableta del café con PIN
  de encargado ya no registra gastos (la orden del dueño). Facturas y pagos a proveedor desde Inventario no cambian.
- **0035 · gastos:** pagos de gastos a crédito (contra la misma cuenta 2101, anulables por reversión), cuentas recurrentes
  (recordatorio + formulario prellenado; nada se asienta solo) y el interruptor `expense_receipt_photos` (apagado).
- **Qué no se activa:** nómina, comprobantes electrónicos, reglas fiscales, MFA/PIN/ingresos, conexión bancaria. Nada
  de eso cambia.
- **Lo que producción ya tiene y no se toca:** los libros encendidos (`ledger_auto_post`) y el catálogo aprobado
  (`chart_of_accounts_approved`), registrados en producción (solo un dueño con el código desde la página, o un pegado en el
  SQL Editor, puede hacerlo; D-058). El dueño lo confirma en la bitácora de producción (acciones `compliance_confirm` y
  `setting_change`). Las migraciones 0034/0035 no los cambian; el ensayo los conserva y los informa; la página nueva marca
  «en libros» solo los días asentados.

## 1. Condiciones de la orden (§10) y qué falta confirmar

| Condición | Estado desde el desarrollo | Qué hace el dueño |
|---|---|---|
| Pruebas completas en verde | ✅ `tests/run.sh` en verde (SQL, respaldo, ensayo de migraciones, navegador) sobre el commit de D-057 y el de D-058. El «Ensayo en pruebas» del 2026-10-26 (ea6b449) copió, anonimizó y migró; se detuvo solo en la comparación, por los interruptores propios de producción (libros encendidos, catálogo aprobado), que la comparación ahora conserva e informa (D-058) | Comprobar «Tests» en verde **sobre la etiqueta** y repetir «Ensayo en pruebas» con esta versión |
| Migraciones sin conflictos | ✅ 0034/0035 numeradas tras comprobar que ninguna rama ni PR usa 0034; la de descuentos pendiente tomará 0036+ | – |
| Procedimiento de reversión probado | ✅ `reversion-0035.sql` y luego `reversion-0034.sql`: las funciones quedan byte por byte como en la 0033, ninguna fila se borra, se reaplican | Tenerlos a mano (sección 5) |
| Respaldo y restauración verificados | ✅ para las migraciones: «Respaldo inmediato» #21 en verde con la restauración verificada (2026-10-26, informe del dueño) | Para publicar: la tarjeta Respaldos en verde ese día (docs/PUBLICAR.md, punto 3) |
| Estado real de E-05 y sesiones activas | ❌ no verificable desde aquí | Confirmar qué ingreso usan las tabletas (E-04/E-05). La página nueva no toca `access.js` ni la transición de aparatos; abre solo a dueño con código y contador |
| Ninguna operación de Caja en riesgo | ✅ al aplicar las migraciones (Caja cerrada, cocina sin pedidos: informe del dueño); ❌ para publicar, no verificable desde aquí | Al publicar: Caja cerrada, cocina sin pedidos y, en cada Caja, el aviso de conexión «todo guardado» (docs/PUBLICAR.md, punto 6) |
| Ventana de baja actividad después del cierre | ❌ la fija el dueño | Después de cerrar, con el cierre de caja hecho |
| Fotos de recibos desde la página nueva | ⏸ dependen de E-17 | Dejar el interruptor apagado hasta verificar respaldo y restauración de los archivos privados |

## 2. Compatibilidad

- **Páginas de hoy con base 0034/0035:** iguales (las migraciones agregan funciones y columnas; `expense_save` conserva
  su firma y acepta lo que la página anterior envía). `accounting.html` no nota la diferencia, salvo que una tableta del
  café con PIN de encargado ya no puede registrar gastos (ve «Solo el dueño con el código y el contador»).
- **Página nueva con base 0033:** abre; Resumen, Ingresos, Reportes y Contabilidad funcionan con lo que ya existe; Gastos,
  Proveedores y Compras avisan «necesita la migración 0034» y los pagos de gastos a crédito y recurrencias «0035».
  Por eso el orden seguro es: **primero las migraciones, luego la publicación**.
- **Ventas sin conexión encoladas en la Caja:** no pasan por ninguna función cambiada.

## 3. Ensayo hecho en desarrollo (2026-10-26)

- Base construida desde cero con todas las migraciones y con la 0034/0035 aplicadas como no-superusuario (ensayo de
  `tests/rehearsal/run.sh`); páginas en vivo sobre la base migrada; páginas sobre el café vacío.
- Reversión: tras 0035 + 0034 revertidas, las 292 huellas de funciones coinciden con una base construida solo hasta la
  0033; las tablas y columnas nuevas quedan sin uso; ninguna fila cambia; las dos migraciones se vuelven a aplicar.
- Ensayo del dueño desde una copia de producción **después** del lanzamiento, con los libros encendidos y el catálogo
  aprobado (como producción el 2026-10-26): ninguna migración vuelve a correr, nada se marca, los dos se informan
  («production's own switches, unchanged by the window: ledger_auto_post True …; confirmations: chart_of_accounts_approved»).
- Intentos no autorizados comprobados: ingreso del café (con y sin PIN de encargado) y dueño sin código reciben
  `not_allowed` en `expense_save`, `expense_list`, `cash_position`, `acct_audit`, `vendor_defaults_save` y las
  funciones de la 0035; el contador no puede crear proveedores (`vendor_save`); `anon` no puede ejecutar ninguna.

## 4. Pasos (los ejecuta el dueño)

### Hecho (2026-10-26)

1. `anonimizar.sql` de D-057 en `canopy-respaldos` (E-38, ea6b449) y **«Ensayo en pruebas» #12 en verde**.
2. **«Respaldo inmediato» #21 en verde**, restauración verificada.
3. Caja cerrada y cocina sin pedidos; `0034_contabilidad_lecturas.sql` y luego `0035_contabilidad_gastos.sql` pegados
   completos en el SQL Editor, *Success* cada uno.
4. `release-check.sql` y `production-snapshot.sql` limpios: `functions_by_version` con 0034 = 11 y 0035 = 15,
   `functions_unknown` = `[]`, `tables_missing` = `[]`, `tables_columns_differ` = `{}`; `ledger_auto_post` sigue en
   `true`, `expense_receipt_photos` en `false` y `chart_of_accounts_approved` sigue confirmado. Desde ese momento una
   tableta del café con PIN de encargado ya no registra gastos (regla de la 0034, en la base, publique o no la página).

### Publicación

Qué se publica: la versión publicada hoy (`v2026.10.25-2`, commit 29bdde5, sitio cd62d0d) **más** solo la Contabilidad
nueva: `contabilidad.html`, `contabilidad.js`, `charts.js`, los textos en `lang.js` y el enlace de Inicio y de
Información. Ningún cambio de otra rama ni de un PR abierto (el PR #4, «quién cobra» sin conexión, D-054, **no** va);
nada de descuentos; las fotos de recibos siguen apagadas. El commit a etiquetar es el de **D-059** (el último de la
rama `claude/hanging-garden-coffee-proposal-1m8zd4`, con «Tests» en verde); su código completo lo da el informe de
Claude de ese día.

0. **Condiciones.** Fuera del horario y **no entre las 00:00 y las 05:00 de Costa Rica** (tres pruebas automáticas
   dependen de la hora y fallarían en la etiqueta). Las de docs/PUBLICAR.md, puntos 1 a 6: Caja cerrada, cocina sin
   pedidos, en cada Caja «Todo lo que se tomó en este dispositivo está guardado en el sistema.», ningún formulario a
   medio escribir. **Nadie sube nada a la rama** hasta que exista la etiqueta (no fusionar el PR #4).
1. **Guardar el sitio de hoy** (una vuelta atrás exacta que no depende de volver a descargar las fotos):
   Releases → **Draft a new release** → Choose a tag: `sitio-2026-10-26` → **Create new tag** → Target: rama
   **gh-pages** → **Publish release**. No use nunca `sitio-2026-10-25`: es el sitio del 21 de octubre, de antes de los PIN.
2. **Etiqueta:** Releases → **Draft a new release** → Choose a tag: `v2026.10.26-1` → **Create new tag** → Target: la
   rama `claude/hanging-garden-coffee-proposal-1m8zd4`, **después** de comprobar que su último commit es el de D-059 →
   **Publish release**. Luego, en **Tags**, `v2026.10.26-1` debe mostrar ese mismo commit. Si muestra otro: no publique;
   cree `v2026.10.26-2` en el commit correcto (una etiqueta nunca se mueve).
3. **Pruebas sobre la etiqueta:** Actions → **Tests** → la ejecución nueva de `v2026.10.26-1` (unos 12 minutos), en verde.
   Si empezó entre las 00:00 y las 05:00 y solo fallaron `080_open_local`, `310_recipes_sales` o `340_pin_autofill`,
   vuelva a correr una vez después de las 05:00. Cualquier otra falla: pare y avise.
4. **Publicar:** Actions → **Publish website (PRODUCTION · manual only)** → **Run workflow** → Use workflow from:
   **Tags → `v2026.10.26-1`** → casilla `PUBLICAR` → «restaurar» vacío → **Run workflow**.
5. **Comprobar la versión:** `https://hanginggardencafe.com/version.json?t=1` dice `"version":"v2026.10.26-1"` y el
   `sha` del commit de D-059. Las tabletas se recargan solas entre ventas (avisos «actualización lista»); si alguna no
   cambia en 15 minutos, recárguela.
6. **Comprobaciones sin crear registros de prueba** (10 minutos). Una venta, un gasto o una entrega de prueba en
   producción serían registros reales que solo se corrigen con otro registro (CLAUDE.md; docs/ACTIVACION-RECETAS.md):
   - Como dueño con el código (y como contador si hay ingreso de contador): `contabilidad.html` abre; las ocho secciones
     cargan; Resumen lista los días pendientes si los hay; Proveedores muestra la lista; un reporte se descarga en CSV.
   - Inicio en español: la ficha «Contabilidad» dice «Ingresos, gastos con sus comprobantes, proveedores…» y abre la
     página nueva; «Página de contabilidad anterior» abre `accounting.html`.
   - En una tableta del café: Inicio y la Caja cargan la versión nueva; la Contabilidad pide dueño con código o contador.
   - El primer gasto real con su comprobante, registrado con «Nuevo gasto», y la primera venta de la apertura son la
     comprobación final de escritura.

## 5. Cómo parar o revertir

- **Antes del paso 4 de «Publicación»:** no hay nada que revertir; el sitio sigue siendo `v2026.10.25-2`.
- **Volver al sitio anterior (si la página nueva da problemas):** Actions → **Publish website** → Use workflow from:
  **Tags → `v2026.10.25-2`** → `PUBLICAR` → «restaurar» vacío → Run workflow. `version.json` vuelve a decir
  `v2026.10.25-2` / 29bdde5…, y las tabletas se recargan solas. **La base se queda en 0035**: no hace falta revertirla.
  Ese sitio es el que hoy funciona en producción con la 0035, y el ensayo lo prueba sobre una copia migrada hasta la
  0035 (`tests/rehearsal/LIVE_PAGES` = cd62d0d, D-059). Vuelta exacta alternativa, sin descargar las fotos otra vez:
  Publish desde `v2026.10.26-1` con «restaurar» = `sitio-2026-10-26` (paso 1 de «Publicación»).
- **Lo que esa vuelta atrás no deshace** (todo vive en la base y se conserva):
  - los pagos de gastos a crédito hechos en la página nueva: la página anterior muestra el gasto por su monto completo,
    no puede anular el pago y tampoco el gasto mientras tenga pagos (`has_payments`); se corrige al volver a publicar la
    página nueva;
  - las cuentas recurrentes (la página anterior no las recuerda; nada se asienta solo), lo habitual de cada proveedor y
    las columnas nuevas;
  - la regla de la 0034: una tableta del café sigue sin poder registrar gastos;
  - `contabilidad.html` deja de existir en el sitio (lo que se esté escribiendo ahí se pierde).
- **Revertir la base** (solo por una falla de una función de la 0034/0035, nunca por un problema de la página):
  1. con la página nueva todavía publicada, anular primero en ella los pagos de gastos a crédito vigentes;
  2. volver al sitio anterior (arriba);
  3. `supabase/tools/reversion-0035.sql` completo en el SQL Editor. `reversion-0034.sql` solo si la falla es de la 0034:
     vuelve a abrir el registro de gastos a una tableta con PIN, contra la orden del dueño.
  Cada reversión se niega si hay una migración posterior aplicada (por ejemplo la de descuentos, 0036 o siguiente).
- **Criterios para detener o volver atrás:** «Tests» en rojo sobre la etiqueta por algo que no sea la hora;
  `version.json` con otro commit; la Contabilidad que no carga para el dueño con código; la Caja o la cocina que no
  cargan la versión nueva; cualquier recibo de un cliente que no se guarde.

## 6. Registros

- Decisión: `docs/DECISIONS.md` D-057, D-058 (el ensayo conserva los interruptores de producción) y D-059 (publicación
  preparada). Dependencias: E-37 (esta activación), E-38 (hecho) y E-17 (fotos de recibos).
- Migraciones: `docs/MIGRACIONES.md` (filas 0034 y 0035). Pruebas: `tests/sql/410_*`, `tests/sql/420_*`,
  `tests/e2e/specs/360_contabilidad.spec.js`.
