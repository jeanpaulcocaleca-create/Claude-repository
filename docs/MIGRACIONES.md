# Migraciones de la base de datos (Canopy OS)

Todos los cambios a la base de datos de Supabase se hacen con **archivos numerados** en
`supabase/migrations/`, en orden: `0000_…`, `0001_…`, `0002_…`.

Los 18 archivos sueltos de `supabase/` (timeclock.sql, pos-tabs.sql, menu-2026.sql…) son **historia**.
Ya no se ejecutan: después de la migración 0000 se detienen solos en la primera línea.

## Cómo aplicar una migración (dueño)

1. **Respaldo primero.** Pida uno ahora (docs/RESPALDOS.md → "Respaldo inmediato") y espere el verde. Antes de la
   0002 no hay tarjeta en Inicio: el verde de GitHub es la prueba.
2. **Primero en pruebas.** "Ensayo en pruebas" en verde con la misma versión (docs/PRUEBAS.md), que aplica la
   migración en una copia anonimizada de producción y compara antes y después.
3. **Foto antes y después.** `supabase/tools/production-snapshot.sql` (solo lectura) antes y después; para la
   ventana grande también `supabase/tools/consistency-check.sql`: los valores de "kept" deben salir iguales.
4. **Luego en producción.** Hágalo fuera del horario de atención (antes de las 6:00 o después del cierre de caja):
   1. Supabase → **SQL Editor** → **New query**.
   2. Abra el archivo en GitHub, botón **Raw**, copie **todo** y péguelo.
   3. Presione **Run**.
5. **Revise el resultado**: debe decir *Success*. Para ver lo aplicado:
   ```sql
   select * from canopy.migrations order by version desc limit 5;
   ```

### Si sale un error

- **"ya estaba aplicada"**: no pasó nada; esa migración ya estaba.
- **"Falta aplicar antes la migración N"**: aplique primero la N y luego esta.
- **"must be owner of table objects" en la 0015 o la 0025**: no se aplicó nada de ese archivo. Detenga la ventana
  ahí: las páginas que se usan hoy siguen funcionando (probado con la base en la 0014 y en la 0025; en la 0024 no se
  probó aparte: la 0025 solo restringe, y aun con ella esas páginas funcionan). No publique las páginas
  nuevas y mantenga las reglas provisionales: sin acceso del contador, el PIN del dueño nunca se escribe en la
  tableta, y no se cambian ajustes, confirmaciones ni tarifas de impuestos. Copie el mensaje y avíselo, para que
  llegue pronto una migración corregida.
- **Cualquier otro error**: el archivo completo se deshace solo (corre como una sola transacción).
  Nada queda a medias. Copie el mensaje y avíselo.

### Reglas que siguen las migraciones

- **Una sola transacción.** Si algo falla, nada se aplica.
- **Primero solo agregan.** Columnas nuevas, funciones nuevas, parámetros opcionales. Las tabletas con la
  página vieja abierta y las ventas guardadas sin internet siguen funcionando.
- **Restricciones después.** Volver obligatorio algo, o quitar lo viejo, va en una migración posterior,
  cuando todas las tabletas ya tienen la versión nueva.
- **Nunca borran ni reescriben registros del negocio** (ventas, pagos, inventario, horas, contabilidad).
- **Cada archivo explica en español** qué hace, por qué, y cómo revertirlo si aplica.
- **Solo SQL.** Ningún comando de psql (líneas que empiezan con `\`): el SQL Editor no los entiende y el ensayo en
  pruebas los rechaza (lo revisa `tests/lint.sh`).
- **Solo caracteres visibles.** Ningún carácter Unicode invisible escrito tal cual (espacio duro, separadores de línea,
  marca de orden de bytes…): al copiar y pegar en el SQL Editor el navegador los normaliza o los cambia, y el texto
  guardado deja de coincidir con el archivo (pasó con `_slide_json` de la 0036, D-063). En una expresión regular se
  escriben como `\uXXXX`. Lo revisa `tests/lint.sh` (regla 14).
- **Menos de 128 KiB.** Cada migración y cada herramienta de `supabase/tools/` pesa menos de 131 072 bytes: el «Ensayo
  en pruebas» la manda como un solo argumento de `psql -c`, igual que una pegada en el SQL Editor, y Linux rechaza un
  argumento de 128 KiB o más («Argument list too long»; pasó con la 0038, que quedó en 130 558 bytes acortando sus
  comentarios). Lo revisa `tests/lint.sh` (regla 15).
- **Se ensaya antes de llegar aquí.** `tests/run.sh rehearsal` aplica todas las migraciones sobre una copia con la
  estructura de producción y meses de historia, como una cuenta que no es superusuario, y compara los datos
  (D-023).

## Línea base: la estructura real de producción

Las tablas `orders`, `order_items`, `menu_items` y `menu_categories` se crearon antes de que existiera este
repositorio. Por eso las pruebas usan una reconstrucción (`tests/db/01_base_tables.sql`). Para usar la
estructura exacta:

Primero, la foto (`supabase/tools/production-snapshot.sql`) dice si hace falta: si `functions_changed`,
`functions_unknown`, `tables_columns_differ` y `triggers_differ` salen vacíos, producción es igual a la
reconstrucción. (La foto del 2026-10-12 mostró `audit_menu()` distinta y la columna `orders.note` de más, D-027.
El seguimiento del 2026-10-13 explicó las dos, D-031: `audit_menu()` es la del repositorio sin un comentario, y
quedó aceptada sin migración; `orders.note` nunca se usó, y ya está en la reconstrucción. Con eso la foto debe
salir vacía, y la exportación de abajo es opcional: sirve solo para tener las definiciones exactas de las cuatro
tablas.)

1. Supabase → SQL Editor → pegue `supabase/tools/catalog-export.sql` → **Run**.
   Es solo lectura: no muestra ventas, nombres, PINs ni contraseñas.
2. En la única celda del resultado: clic derecho → **Copy cell**.
3. En GitHub, en la rama de desarrollo: **Add file → Create new file** →
   `supabase/baseline/production-schema.sql` → pegue → **Commit**.

Con ese archivo comparo la estructura real contra la reconstrucción.

## Pendientes de aplicar en producción (hoy en la 0037)

La 0029 (recibir un pedido con la factura y el pago, D-041) la aplicó el dueño el 2026-10-15 (E-25); las 0030–0032
(recetas, D-043/D-044) el 2026-10-18 (E-29/E-30, D-047). Las filas de 0030–0032 quedan abajo como referencia.
Las 0034 y 0035 (Contabilidad nueva, D-057) las aplicó el dueño el 2026-10-26, después del «Ensayo en pruebas» #12 y del
«Respaldo inmediato» #21, con `release-check.sql` y la foto limpios (E-37, D-059).
La 0036 (pantallas, D-062) la aplicó el dueño el 2026-11-01 (E-40, D-063) y la 0037 (pantallas v2, D-064) el
2026-11-03, con la publicación de `v2026.11.03-1` (E-41). La 0038 (descuentos de Caja, D-065) está en la rama
`claude/descuentos-caja`: no se ha aplicado.

| Archivo | Qué trae | Cómo se aplica |
|---|---|---|
| `0033_pines_seguros.sql` | PIN más seguros (D-053): el editor del equipo ya no deja averiguar PIN (máximo 10 PIN por hora y cuenta, y cada «ya lo usa alguien» queda anotado); un PIN vacío no cuenta como intento; cada bloqueo queda anotado y otro encargado lo quita con su PIN; volver a activar a alguien pide un PIN nuevo; cada apertura de las áreas de dueño queda atada a la sesión que la hizo (otro aparato de la misma cuenta no la usa, tampoco para las fotos del menú) y, con las páginas nuevas, cerrar sesión la termina en el servidor. Solo funciones y una columna nueva; ningún registro cambia | Como cualquier migración (pasos 1–5), **fuera del horario de atención**, después de la 0032. Después: en una tableta, abrir las áreas de dueño con un PIN y cambiar una foto del menú (comprueba la sesión en Supabase). Reversión: `supabase/tools/reversion-0033.sql`. Guía completa (orden, verificaciones, simulacro de reversión, recuperación): `docs/ACTIVACION-PINES.md` |
| `0034_contabilidad_lecturas.sql` | Contabilidad nueva, 1 de 2 (D-057): lecturas para `contabilidad.html` (proveedores con lo habitual, historial e importes por proveedor, compras con su etapa, cobros por día y forma de pago, posición de efectivo, comparación de períodos, auditoría) y la regla de gastos más estricta: registrar y listar gastos, y el depósito privado de recibos, solo con **dueño con código o contador** (una tableta del café con PIN de encargado ya no registra gastos; facturas y pagos a proveedor desde Inventario siguen igual). Seis columnas nuevas en `vendors` (cédula, días de crédito, categoría, forma de pago y tarifa de IVA habituales, notas de pago). Ningún registro cambia | Como cualquier migración (pasos 1–5), **fuera del horario de atención**, después de la 0033. Después: `release-check.sql` con `functions_missing` = `[]`. Reversión: `supabase/tools/reversion-0034.sql` (deja `expense_save`, `expense_list` y `_receipts_allowed` byte por byte como en la 0033; las columnas quedan sin uso). Guía: `docs/ACTIVACION-CONTABILIDAD.md` |
| `0035_contabilidad_gastos.sql` | Contabilidad nueva, 2 de 2 (D-057): pagos de gastos a crédito contra la misma cuenta por pagar (2101), con anulación por reversión; cuentas recurrentes como **recordatorio con formulario prellenado** (nunca asiento automático; id determinista por período, así que un doble toque no duplica); `ap_aging`, `cash_payouts` y `cash_position` los tienen en cuenta; `expense_void` no anula un gasto a crédito con pagos vigentes (`has_payments`) y devuelve al recordatorio el período de un gasto anulado; las cuentas automáticas (diferencias de caja, mermas, conteos, diferencias de precio) no se aceptan en gastos a mano; el interruptor `expense_receipt_photos` (apagado) para fotos de comprobantes desde la página nueva (E-17). Dos tablas nuevas (`expense_payments`, `expense_schedules`) y dos columnas en `expenses`. Ningún registro cambia | Después de la 0034, en la misma ventana. Reversión: `supabase/tools/reversion-0035.sql` (primero esta, luego la 0034; las tablas y lo escrito en ellas quedan). Aviso dentro del archivo si ya hubiera pagos de gastos a crédito hechos |
| `0036_pantallas.sql` | Pantallas para los clientes (D-062): tres tablas nuevas (las TV, las diapositivas de la Pantalla B con vigencia obligatoria, y un registro de cambios que no se puede modificar), la lectura pública `pantalla_datos` (los ajustes de una TV y sus diapositivas vigentes con el precio y la disponibilidad que tiene el menú en ese momento) y la gestión solo con el PIN del dueño (`pantallas_estado`, `pantalla_guardar`, `diapositiva_guardar`, `diapositiva_estado`). Los textos no admiten precios ni combos o descuentos. Ninguna tabla, función ni fila existente cambia; la regla de Storage «menu photos owner write» (0033) se vuelve a crear sin la carpeta `pantallas/`, que queda solo para el dueño con una regla nueva | Como cualquier migración (pasos 1–5), después de la 0035; no bloquea ventas. Antes: `anonimizar.sql` nuevo en `canopy-respaldos` y «Ensayo en pruebas» en verde. Después: `release-check.sql` con `migrations_missing` y `functions_missing` vacíos y `anon_can_run` con `pantalla_datos`. Reversión: `supabase/tools/reversion-0036.sql` (quita las funciones; las tablas quedan con lo que tengan). Guía completa: `docs/ACTIVACION-PANTALLAS.md` |
| `0037_pantallas_v2.sql` | Pantallas v2 (D-064): seis ajustes nuevos por TV con valor por omisión (distribución del menú `layout`, densidad, inglés, promociones intercaladas en la Pantalla A y sus tiempos), la lista de productos de la TV de menú (`item_ids`: el menú resumido para las TV de 32" a 3 m; nada = todos los de las categorías elegidas), la clase de diapositiva «composicion» (plantilla de 1 a 4 zonas; cada zona una foto fija o una presentación propia con su lista ordenada de productos o fotos, sus segundos, nombres y precios del menú en vivo o no, y una foto de respaldo), `dwell_seconds`; `pantalla_datos` da también sus diapositivas a una TV de menú con promociones; `_slide_json` reescrita con escapes `\uXXXX` (D-063). Ninguna tabla, función ni fila existente fuera de las tres de las pantallas cambia; las filas de las pantallas conservan sus valores | Paso a paso en `docs/ACTIVACION-PANTALLAS-V2.md` (etapas 1 y 2), después de la 0036; no bloquea ventas. Antes: el `anonimizar.sql` de esta versión en `canopy-respaldos` (todo ensayo posterior lo necesita), «Ensayo en pruebas» en verde con la versión, el respaldo y `production-snapshot.sql` guardado. Después: `release-check.sql` (`migrations_missing` = `[]`, serie hasta la 37; `anon_can_run` las mismas cinco) y `production-snapshot.sql` (`0036` = 7 y `0037` = 8: seis funciones de la 0036 pasan a contar bajo la 0037; `functions_total` + 2; `data_fingerprint` y `anon_can_run` iguales a los de antes). Reversión: `supabase/tools/reversion-0037.sql` (vuelve las funciones a la 0036; columnas y filas quedan; después `migrations_missing` = `[37]`, `0036` = 13 y `0037` = 1); siempre después de volver las páginas a `v2026.11.02-1` |
| `0038_descuentos_caja.sql` | Descuentos de Caja (D-065): cuatro descuentos con la tasa fijada por el servidor (Empleado 30 %, Local 10 %, Huésped 10 % y Guía Turista 100 %, una cortesía a ₡0 con su valor de lista y ninguna regla fiscal activada), autorizados solo con el código, sin lista de nombres: el de un encargado (o del dueño); para Empleado también el del empleado, los dos en una sola llamada y nunca para sí mismo; para Guía solo el del dueño, que no abre las áreas del dueño ni toca el contador de PIN de nadie. Un descuento de Empleado por empleado y por día de Costa Rica (vuelve solo con una anulación válida o con «Devolver el cupo del día»). Solo las cajas que un encargado registró en ese mismo aparato prueban códigos: tres puestos, cada uno con su cuenta de códigos equivocados (esperas desde el tercero en una hora, la caja se detiene con 12 en 24 horas, las demás siguen), sin pausa para todo el café. La ventana anterior queda detrás del ajuste `pos_free_discount` (encendido) y Guía Turista apagada detrás de `pos_discount_guia` (hasta que el contador confirme el IVA, A-13). Trece columnas nuevas en `discount_approvals` con su regla, las tablas `discount_tills` y `discount_pin_shared` (quién comparte un código, solo para el dueño), 41 funciones nuevas (entre ellas el informe `descuentos_informe`) y tres reemplazadas en su lugar con el mismo nombre (`approve_discount`, `tab_set_discount`, `_order_discount_check`), tres disparadores en `orders`. Ningún registro existente cambia (las aprobaciones viejas quedan con la categoría vacía); una venta con descuento nunca se rechaza por él: queda con lo cobrado y una marca para el gerente | Paso a paso en `docs/ACTIVACION-DESCUENTOS.md` (E-42), después de la 0037, **fuera del horario de atención**; no bloquea ventas. Antes: la línea del dueño sobre la regla 5 (E-42), el `anonimizar.sql` de esta versión en `canopy-respaldos`, «Ensayo en pruebas» en verde con la versión (reinicio = `no`), «Respaldo nocturno» y `production-snapshot.sql` guardado. Después: `release-check.sql` (`migrations_missing` y `functions_missing` = `[]`, serie hasta la 38; `anon_can_run` las mismas cinco) y `production-snapshot.sql` (`0038` = 44: las 41 nuevas y las tres reemplazadas, que dejan de contar en `legacy` (el de antes − 3); `functions_total` + 41; `functions_changed` y `functions_unknown` vacíos; `data_fingerprint` y `anon_can_run` iguales; `pos_free_discount` = on, `pos_discount_guia` = off); luego, con las páginas nuevas publicadas, cada caja que da descuentos se registra en Reloj de marcas → Bitácora de aprobaciones. El ajuste `pos_free_discount` queda encendido: lo apaga el dueño cuando él decida (Inicio → Ajustes del sistema con el código del teléfono, o `supabase/tools/descuento-libre-apagar.sql`). Herramientas del dueño para el SQL Editor: `descuento-libre-apagar.sql`, `descuento-libre-encender.sql`, `descuento-cajas-reanudar.sql`, `descuento-cajas-quitar-todas.sql` y `pines-desbloquear.sql`. Reversión: `supabase/tools/reversion-0038.sql`, solo por una falla de una función, siempre después de volver las páginas a `v2026.11.03-1` y con `pos_free_discount` encendido (las columnas, las dos tablas y los dos ajustes quedan; después `migrations_missing` = `[38]`) |

| Archivo | Qué trae | Cómo se aplica |
|---|---|---|
| `0030_recetas_seguras.sql` | Recetas, etapa 1A (D-043): cada cambio de receta se guarda de una vez con el PIN de un encargado o del dueño, queda en un historial que no se puede borrar (quién, cuándo, por qué, qué cambió y el costo antes → después), cantidades en gramos o mililitros, un solo costo (el promedio) y el costo de ingredientes comparado con las ventas sin IVA. Las recetas de hoy quedan como «versión inicial»; el editor publicado hoy sigue guardando (queda como «cambio directo») | Como cualquier migración (pasos 1–5 de arriba), **fuera del horario de atención**: agregar los disparadores bloquea la tabla de recetas un instante y en ese instante una venta espera. Requiere la 0029. Reversión: `supabase/tools/reversion-0030.sql` |

| `0031_recetas_ventas_exactas.sql` | Recetas, etapa 1B (D-044): cada venta descuenta la receta y el costo vigentes cuando se cobró (también si llegó tarde por falta de internet); lo agregado sin internet a un pedido toma la receta de cuando se agregó; quitar un producto de una cuenta devuelve exactamente lo que salió; nunca rechaza una venta | Igual, **fuera del horario de atención**, después de la 0030. Reversión: `supabase/tools/reversion-0031.sql` (después de revertir la 0032) |
| `0032_recetas_solo_con_pin.sql` | Recetas, etapa 1B (D-044): ninguna página escribe recetas directamente; solo el editor con PIN. La Caja no cambia | Igual, después de la 0031, en la misma ventana. Reversión: `supabase/tools/reversion-0032.sql` |

La guía completa (orden, verificaciones, reversión) está en `docs/ACTIVACION-RECETAS.md`.

No confundir con la antigua «0030 facturas_archivo» (archivos de facturas en Storage): se eliminó antes de publicarse
(D-042) y nunca se aplicó; el número 0030 es ahora el de las recetas.

Antes: «Ensayo en pruebas» en verde con la versión (con **reinicio = no**: producción ya pasó la ventana) y «Respaldo
inmediato» en verde. Después: `supabase/tools/release-check.sql` debe mostrar `migrations_missing` y `functions_missing`
vacíos.

## Plantilla de una migración nueva

```sql
-- ===========================================================================
-- Canopy OS · migración NNNN · <título en español>
-- Pegar TODO en Supabase → SQL Editor → New query → Run.  Requiere: NNNN-1.
-- Qué hace / por qué / qué cambia para el personal / reversión
-- ===========================================================================
select canopy.migration_begin(NNNN, 'nombre_corto');

-- ... cambios (solo agregar en la primera fase) ...

select canopy.migration_end(NNNN, 'nombre_corto');
notify pgrst, 'reload schema';
```

## Para desarrolladores

`tests/build-db.sh` construye una base de prueba en este orden:

1. imitación de Supabase;
2. tablas base;
3. los 18 archivos históricos (en el orden de `tests/db/legacy-order.txt`);
4. todas las migraciones, cada una con `--single-transaction`, igual que el SQL Editor;
5. datos de prueba.

`tests/run.sh` corre todas las pruebas. No se sube nada que no pase.
