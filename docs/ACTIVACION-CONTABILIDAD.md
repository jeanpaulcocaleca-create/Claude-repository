# Activación de la Contabilidad nueva (D-057, migraciones 0034 y 0035) · E-37

**Estado:** construida, probada y ensayada en la rama de desarrollo; **nada aplicado ni publicado**. La «Orden maestra
de construcción» (2026-10-26) autoriza publicar solo si se confirman todas las condiciones de su §10; varias no se
pueden confirmar desde el entorno de desarrollo (sección 1), así que el sistema queda listo y los pasos en producción
los hace **solo el dueño** (Jean Paul): respaldo, SQL Editor, etiqueta y publicación. Claude no publica, no crea
etiquetas `v*` y no toca la base de producción (CLAUDE.md); sí acompaña: lee resultados, compara celdas y prepara
correcciones.

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

## 1. Condiciones de la orden (§10) y qué falta confirmar

| Condición | Estado desde el desarrollo | Qué hace el dueño |
|---|---|---|
| Pruebas completas en verde | ✅ `tests/run.sh` en verde (SQL, respaldo, ensayo de migraciones, navegador) sobre el commit de D-057 | Comprobar «Tests» en verde **sobre la etiqueta** |
| Migraciones sin conflictos | ✅ 0034/0035 numeradas tras comprobar que ninguna rama ni PR usa 0034; la de descuentos pendiente tomará 0036+ | – |
| Procedimiento de reversión probado | ✅ `reversion-0035.sql` y luego `reversion-0034.sql`: las funciones quedan byte por byte como en la 0033, ninguna fila se borra, se reaplican | Tenerlos a mano (sección 5) |
| Respaldo y restauración verificados | ❌ no verificable desde aquí | «Respaldo inmediato» en verde el mismo día y comprobar que la clave del dueño abre el archivo (docs/RESPALDOS.md) |
| Estado real de E-05 y sesiones activas | ❌ no verificable desde aquí | Confirmar qué ingreso usan las tabletas (E-04/E-05). La página nueva no toca `access.js` ni la transición de aparatos; abre solo a dueño con código y contador |
| Ninguna operación de Caja en riesgo | ❌ no verificable desde aquí | Caja cerrada y cocina sin pedidos al aplicar (las migraciones solo cambian funciones y agregan tablas; la Caja no las usa) |
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
- Intentos no autorizados comprobados: ingreso del café (con y sin PIN de encargado) y dueño sin código reciben
  `not_allowed` en `expense_save`, `expense_list`, `cash_position`, `acct_audit`, `vendor_defaults_save` y las
  funciones de la 0035; el contador no puede crear proveedores (`vendor_save`); `anon` no puede ejecutar ninguna.

## 4. Pasos (los ejecuta el dueño)

1. Subir `ops/backup/repositorio-respaldos/anonimizar.sql` de esta versión al repositorio privado `canopy-respaldos` (E-38: conoce las columnas nuevas de 0034/0035; sin él el ensayo se detiene antes de copiar nada). Luego **«Ensayo en pruebas»** (GitHub → Actions) con la versión a publicar, reinicio = `no`: en verde.
2. **«Respaldo inmediato»** en verde; descargar el archivo y comprobar que la clave lo abre.
3. **Fuera del horario**, Caja cerrada: Supabase → SQL Editor → New query → pegar **todo**
   `supabase/migrations/0034_contabilidad_lecturas.sql` → Run → *Success*. Luego igual con
   `0035_contabilidad_gastos.sql`. Si una falla, no cambia nada (cada una es una transacción); copiar el error y parar.
4. `supabase/tools/release-check.sql` en el SQL Editor: `migrations_missing` = `[]`, `functions_missing` = `[]`.
5. Etiqueta `v*` sobre el commit (con «Tests» en verde sobre la etiqueta) y «Publish website (PRODUCTION · manual only)».
6. **Después de publicar (10 minutos):**
   - Abrir `contabilidad.html` como contador y como dueño: las ocho secciones cargan; Resumen muestra los días cerrados
     pendientes si los hay.
   - Registrar un gasto de un proveedor conocido con «Nuevo gasto» y comprobarlo en Gastos y en el diario.
   - En una tableta del café: la Caja cobra, la cocina ve el pedido, Inventario recibe un pedido con el PIN.
   - Recargar a mano cada pestaña de personal (o esperar la recarga segura de `version.js`).

## 5. Cómo parar o revertir

- **Antes del paso 3:** no hay nada que revertir.
- **Después de las migraciones, antes de publicar:** opcional revertir con `supabase/tools/reversion-0035.sql` y luego
  `supabase/tools/reversion-0034.sql` (cada uno pegado completo en el SQL Editor; una transacción cada uno). Las tablas
  `expense_payments` y `expense_schedules`, las columnas nuevas y lo escrito en ellas quedan sin uso; ninguna fila se
  borra. Aviso: si ya se pagó un gasto a crédito con `expense_pay`, su asiento sigue en los libros y la antigüedad vuelve
  a contar ese gasto por su monto completo hasta reaplicar la 0035 (el archivo lo explica).
- **Después de publicar:** las páginas publicadas funcionan con la base revertida (la nueva avisa qué migración falta; la
  anterior no cambia). Si hay que volver atrás el sitio, publicar la etiqueta anterior.
- **Criterios para detener:** un *Success* que no llega, `release-check.sql` con algo faltante, la Caja sin cobrar en la
  prueba del paso 6, o cualquier recibo de un cliente que no se guarde.

## 6. Registros

- Decisión: `docs/DECISIONS.md` D-057. Dependencias: E-37 (esta activación) y E-17 (fotos de recibos).
- Migraciones: `docs/MIGRACIONES.md` (filas 0034 y 0035). Pruebas: `tests/sql/410_*`, `tests/sql/420_*`,
  `tests/e2e/specs/360_contabilidad.spec.js`.
