# Plan de lanzamiento a producción · Canopy OS

**Estado: nada de esto está en producción.** Todo está en la rama de desarrollo y probado en la base de
pruebas. Pasar a producción **requiere su aprobación expresa**, ola por ola. Este documento dice qué se
aplica en cada ola, cómo comprobarlo y cómo volver atrás.

Documentos relacionados:
- `docs/MIGRACIONES.md`: cómo aplicar una migración.
- `docs/PUBLICAR.md`: cómo publicar las páginas y volver a la versión anterior.
- `docs/RESPALDOS.md`: respaldos y recuperación.
- `docs/DEPENDENCIES.md`: lo que falta de usted o del contador.

## Reglas para todas las olas

1. **Respaldo verificado del mismo día** (tarjeta Respaldos en verde, o respaldo inmediato). Sin respaldo, no
   se aplica nada (E-03).
2. **Primero el ensayo con la copia real**: «Ensayo en pruebas» con destino `desechable` y reinicio `si` (docs/PRUEBAS.md; sin segundo proyecto de Supabase, D-039), y la lista de verificación de abajo en el café el primer día. La ola 0
   es la excepción: es urgente, ya se ensayó con la copia representativa y puede ir antes de que exista pruebas
   (docs/PRUEBAS.md, «Cuándo»).
3. **Fuera de horario**, después del cierre de caja. Ninguna tableta con ventas "pendientes de enviar".
4. **Primero la base, después las páginas.** Las páginas nuevas funcionan con la base vieja (muestran "necesita
   una actualización"), pero las funciones nuevas necesitan la base nueva.
5. **Comprobar**: `supabase/tools/release-check.sql` (solo lectura). Debe mostrar:
   - `migrations_missing` vacío hasta la ola aplicada;
   - `functions_missing` vacío (después de la ola 5);
   - `migrations_applied` hasta la 28;
   - `anon_can_run` solo `canopy_schema_version`, `order_status`, `place_room_order` y `room_lookup`;
   - `tables_without_rls` vacío;
   - `ledger.unbalanced` en 0;
   - `storage_buckets_missing` y `storage_policies_missing` vacíos, y `receipt_upload_rule_current` en `true`
     (después de la 0025); en producción `menu_photos_bucket` sale `true` (en pruebas, `false`).
6. **Observar 1 a 3 días** antes de la ola siguiente.

## Ensayo (hecho el 2026-10-12)

`tests/run.sh rehearsal` (también en cada cambio, en GitHub): base igual a producción hoy (los 18 archivos
históricos) con unos 4 meses de historia (14 534 ventas, 38 280 líneas, 60 548 movimientos de inventario, 250
pagos parciales, 208 anulaciones, 420 descuentos, 291 pedidos de habitación, 121 días de caja), migraciones
0000 → 0028 aplicadas como la cuenta del SQL Editor (no superusuario):

- **2,1 segundos en total** (la más lenta, 0004: 0,5 s);
- **nada de lo que existía cambió**: las 26 tablas originales (cada columna original, huella md5) y 27 revisiones
  del negocio idénticas antes y después;
- las **páginas que hoy están en el sitio** siguen funcionando contra la base migrada (venta, venta sin internet
  que se sube después, reloj, Administrador del menú, todas las páginas sin errores);
- una venta tomada sin internet **antes** de la ventana y subida después se guarda en su día y queda marcada para
  el encargado (nunca se rechaza);
- el contador asienta 30 días de la historia vieja: cuadra y coincide con las ventas colón por colón;
- respaldo y restauración antes y después: contenido y permisos idénticos.

Con los datos reales, el mismo ensayo se repite antes de la ventana en una base desechable del repositorio privado
(docs/PRUEBAS.md; D-039: sin proyecto de pruebas).

## Recomendación: la base en una sola ventana, el uso por olas

**Decisión del dueño (2026-10-14, D-038): un solo lanzamiento con reinicio operativo.** La base de hoy se reinicia una
vez (se borran las transacciones del periodo de prueba y se conserva todo lo demás; el inventario empieza en cero y se
carga tras el conteo físico) y en la misma ventana se aplican 0000–0028 y se publican las páginas. El guion operativo
es `docs/LANZAMIENTO-UNICO.md`; las olas de abajo quedan como plan de activación y capacitación, y las reglas, la tabla
de reversión y la lista de verificación de este documento siguen valiendo. **Revisión de esa noche (D-039):** el mismo
proyecto de Supabase y el mismo sitio; ningún segundo proyecto (E-13 y E-14 retiradas). Donde este documento dice
«pruebas (staging)», hoy es el ensayo con los datos reales en una base desechable (docs/PRUEBAS.md).

La migración **0025** corrige lo que encontró la revisión de seguridad en todas las fases. Depende de todas las
anteriores, así que va de última.

Para que no quede ningún periodo con una corrección pendiente:
- **Ola 0** (urgente) se aplica ya, sola.
- **Las migraciones 0003 a 0028** se aplican juntas, en **una sola ventana** fuera de horario, después del ensayo
  completo en pruebas (staging).
- Todo lo regulado queda **apagado**. Las páginas se publican en esa misma ventana.
- Las olas 1 a 5 de abajo se convierten en **activación y capacitación**: qué se revisa, qué se enciende y qué
  aprende el personal, una ola por semana.

Si prefiere aplicar la base por olas, aplique **0025 a 0028 junto con la ola 5**. Hasta entonces:
- no dé acceso de contador;
- no escriba el PIN del dueño en la tableta.

## Ola 0 · Verificar, respaldar y cerrar los huecos (urgente)

En este orden. Cada paso es de solo lectura o se puede deshacer.

| Paso | Qué | Cambia producción | Quién |
|---|---|---|---|
| 1 | **Foto de producción**: `supabase/tools/production-snapshot.sql` (solo lectura) y pegar el resultado. **Hecho el 2026-10-12** (D-027) | No | Usted (E-00) |
| 2 | Apagar **Allow new users to sign up** (y revisar que los ingresos anónimos estén apagados). Los ingresos de la foto ya se revisaron: ninguno ajeno. **Hecho el 2026-10-12** | Ajuste reversible, sin datos | Usted (E-02) |
| 3 | **Seguimiento** (solo lectura): `supabase/tools/production-followup.sql`, pegar el resultado (muestra qué ingreso usa cada aparato del café) y decir de quién es el ingreso que nunca entró. **Hecho el 2026-10-13** (D-031): caso B; dos dueños, cada uno con su ingreso personal | No | Usted (E-04) |
| 4 | **Respaldo verificado** antes de cualquier migración: `supabase/tools/backup-account.sql`, repositorio privado, primer respaldo y descarga (docs/RESPALDOS.md) | Solo crea la cuenta de lectura | Usted (E-03) |
| 5 | Guardar el sitio de hoy como `sitio-2026-10-09` (docs/PUBLICAR.md) | No | Usted (E-19) |
| 6 | **Ingreso del café** para los aparatos del café, separado de los de los dueños: `docs/INGRESOS.md` (caso A o B; y, si un ingreso no es de nadie, la parte 2 de `cafe-login.sql`) | Caso A: una fila de permisos, anotada en el registro. Caso B: lo mismo; los ingresos personales de los dueños siguen de dueño; solo si un dueño no puede entrar con el suyo, uno nuevo (+dueno) con acceso de dueño (`make_owner`, sin anotación) | Usted (E-05) |
| 7 | Migraciones **0000**, **0001** y **0002**, una por una, con la foto antes y después | Sí (solo agrega revisiones) | Usted (E-01) |

- **Qué cierra la 0001**: un ingreso ajeno ya no puede cancelar o marcar pagados los pedidos de habitación,
  cambiar el código QR de una habitación, ver las ventas por producto, ni **probar PINs** del reloj y de las
  anulaciones. El pedido desde la habitación vuelve a funcionar (encuentra `gen_random_bytes`). (Las categorías
  del menú: la foto mostró que en producción ese hueco no existe; la 0001 lo cierra donde exista, D-027.)
- **Qué NO cambia para el personal**: nada. Probado con las páginas que están hoy en el sitio (ensayo, D-023).
- **Comprobar después del paso 2**: la tableta sigue con su sesión; usted puede entrar; "olvidé mi contraseña"
  sigue enviando el correo. **Después del paso 7**: el pedido de habitación funciona (lo repara la 0001).
- **Comprobar después del paso 6**: la tableta sigue con su sesión y vende; el reloj marca con PIN; las áreas del
  dueño piden un PIN. El código del teléfono va **solo** en el ingreso personal de cada dueño, desde su teléfono
  (E-06).
- **Volver atrás**: paso 2, volver a encender el ajuste. Paso 6: `select public.make_owner('el correo');` (en el caso B
  los ingresos personales siguen como dueños; si un +dueno nuevo hiciera falta quitárselo: parte 2 de
  `cafe-login.sql`). Paso 7: no hace falta (solo agrega revisiones); si algo fallara, restaurar el respaldo del paso 4
  en PRUEBAS para investigar, nunca encima de producción (después: «Ensayo en pruebas» con vaciar = `si` y
  `staging-logins.sql`, para que pruebas vuelva a la copia anonimizada).

## Ola 1 · Integridad de las ventas y la caja (Fases 0–1)

- **Migraciones**: 0003 a 0012.
- **Páginas**: publicar la etiqueta de la versión (POS, inventario, historial, ventas, reloj, inicio, administrador).
- **Qué ve el personal**:
  - la ventana de efectivo (billetes y vuelto);
  - "Buscar ventas anteriores", con reimpresión COPIA;
  - "Devolver" en lugar de "Anular" cuando el día ya cerró;
  - recibir una entrega en partes, con la factura del proveedor;
  - el teclado numérico en las tabletas;
  - todo en español.
- **Todo lo regulado queda APAGADO**: precios sin IVA (A-03), "quién cobra" (`operator_mode = off`), tipo de cambio
  automático (E-16).
- **Lista de verificación en pruebas y luego en producción**:
  1. Una venta en efectivo con vuelto.
  2. Una con tarjeta.
  3. Una con un billete de dólar: antes, escriba el tipo de cambio en Inicio → Ajustes.
  4. Una cuenta abierta pagada en dos partes.
  5. Un descuento con PIN.
  6. Una anulación con PIN.
  7. Abrir y cerrar la caja: la diferencia en ₡ y en $ es la esperada.
  8. Una devolución de una venta de ayer.
  9. Reimprimir un recibo.
  10. Recibir media entrega.
  11. El menú QR y la cocina siguen iguales.
  12. Una tableta sin internet guarda una venta y la sube al volver.
- **Volver atrás**:
  - páginas: publicar la etiqueta anterior;
  - base: cada migración trae su "Reversión" (tabla al final);
  - nada de esto borra ventas.

## Ola 2 · Contabilidad (Fase 2)

- **Migraciones**: 0013, 0014 y 0015, más la página Contabilidad.
- **Los asientos automáticos quedan APAGADOS** hasta que el contador apruebe el catálogo (A-07).
- **Antes**:
  - cree el ingreso del contador (E-18);
  - si quiere respaldo de las fotos de facturas, las llaves S3 (E-17).
- **Comprobar**:
  - el contador entra con su ingreso;
  - asienta un día de prueba;
  - la balanza cuadra;
  - registra un gasto con foto;
  - descarga el paquete del mes.
- **Volver atrás**: apagar `ledger_auto_post`. Los asientos nunca se borran: se revierten.

## Ola 3 · IVA y proveedores (Fase 3)

- **Migraciones**: 0016, 0017 y 0018.
- **Comprobantes electrónicos**: el registro queda en `off`. "Solo registrar" sirve para revisar que cada producto
  tenga su CABYS; no envía nada. El envío real necesita proveedor y credenciales (A-02, A-10). No está construido.
- **Comprobar**:
  - una factura de proveedor unida a su entrega;
  - un pago;
  - el reporte "IVA del período" frente a la balanza.
- **Volver atrás**: quitar las funciones nuevas. Las tablas y los asientos quedan.

## Ola 4 · Efectivo, bancos y planilla (Fase 4)

- **Migraciones**: 0019, 0020, 0021 y 0022.
- **Qué ve el personal**: en la ventana de la caja, el botón **"Entrada o salida de dinero"** (con PIN de encargado).
- **Antes**: capacitar a los encargados (abajo).
- **Planilla**: las deducciones y cargas no traen ningún porcentaje (A-08). Hasta que el contador los registre,
  la planilla calcula solo el bruto.
- **Comprobar**:
  - un depósito al banco desde la caja: el cierre cuadra;
  - importar el CSV real de su banco y conciliar;
  - crear un periodo de pago, aprobar las horas y preparar la planilla (sin asentar en producción hasta que el
    contador lo revise).
- **Volver atrás**:
  - quitar las funciones nuevas;
  - quitar el candado de horas (`drop trigger time_entries_period_lock`).

## Ola 5 · Información del negocio (Fase 5) y endurecimiento de seguridad

- **Migraciones**: 0023, 0024, **0025** (endurecimiento de seguridad, D-022), **0026** (planilla de Costa Rica, D-035: todo apagado hasta la confirmación `payroll_cr_rules`) **0027** (quién cobra una cuenta abierta, «Terminar mi turno» marca la salida, D-036) y **0028** (correcciones de la revisión: total negativo, pedidos de habitación pagados otro día, días sin caja, reversiones del diario, PIN repetido, puesto de dueño con código, D-037), más la página Información.
- **Después de 0025**:
  - el dueño entra a Contabilidad e Información con **su** ingreso y el código del teléfono;
  - el contador activa su código del teléfono en su primer ingreso;
  - un encargado necesita el permiso de ventas para ver Información.
- Solo lectura; 0024 agrega una columna con valor fijo (el local de hoy).
- **Comprobar**:
  - Información carga;
  - Inicio muestra "Estimado" o "Final".
- **Volver atrás**: no hace falta.

## Cómo volver atrás, en orden de preferencia

1. **Apagar el interruptor** de la función (Inicio → Ajustes): precios, quién cobra, comprobantes, asientos
   automáticos.
2. **Publicar la etiqueta anterior** de las páginas (docs/PUBLICAR.md).
3. **Migración de corrección**: la siguiente en número. Yo la preparo con el mensaje de error; nunca se
   borran ventas ni asientos.
4. **Restaurar un respaldo** (docs/RESPALDOS.md → "Desastre"). Solo con su autorización expresa. Se pierden los
   cambios posteriores al respaldo; por eso se aplica cada ola justo después de un respaldo verificado. (Las cuentas
   de acceso no van en el respaldo: se crean otra vez a mano, RESPALDOS → Cuentas de acceso, y cada aparato vuelve a
   iniciar sesión.)

| Migración | Reversión (también al inicio de cada archivo) |
|---|---|
| 0000, 0001, 0024 | No hace falta |
| 0002 | `supabase/tools/backup-account-rollback.sql` (no borrar `canopy.backup_runs`) |
| 0003 | `drop trigger order_times_ins / order_times_upd` |
| 0004 | `drop function pos_record_sale` (la caja vuelve sola al guardado en dos pasos) |
| 0005 | `drop trigger stock_item_history_guard / stock_items_protect / stock_move_cost / purchase_order_status` |
| 0006 | Volver a ejecutar `manager_void_order` de authorization.sql; `drop function manager_refund_order` |
| 0007 | `grant execute on function hours_report(...) to authenticated` (no recomendado) |
| 0008 | `operator_mode = off` |
| 0009 | `drop trigger order_items_tax_ins/_upd/_del, order_tax_discount, order_item_tax_stamp, order_refund_tax` |
| 0010 | La caja vieja funciona igual (parámetros opcionales) |
| 0011 | `drop function order_search, order_reprint; drop trigger order_receipt_no` |
| 0012 | `drop function po_receive_delivery` |
| 0013 | `ledger_auto_post = false` |
| 0014–0017, 0019, 0020, 0022, 0023 | `drop function` de las funciones nuevas (las tablas y los asientos quedan) |
| 0015 | `drop policy "expense receipts read" / "expense receipts add"` |
| 0018 | `einvoice_mode = off; drop trigger order_e_document` |
| 0021 | `drop trigger time_entries_period_lock` |
| 0025 | Volver a aplicar la migración anterior de cada función (no toca datos). Nunca quitarla por comodidad: corrige fallas de seguridad |
| 0026 | `drop function` de las funciones nuevas y volver a crear las de planilla de la 0025 (no toca datos; las tablas nuevas y los asientos quedan) |
| 0027 | `drop trigger order_zz_operator_upd`; volver a crear `tab_pay` de pos-tabs.sql y `pos_operator_end` de la 0008 (las columnas quedan) |
| 0028 | `drop trigger order_zz_till_guard, chat_questions_guard`; volver a crear las funciones anteriores (0001, 0013, 0018, 0019, 0022, manager-mode.sql); no toca datos |
| 0029 | `drop trigger purchase_receipts_invoice_status on purchase_receipts`; `drop function` de `po_receive_and_settle`, `po_receipt_settle`, `po_receipt_pay`, `po_history`, `po_pending` y sus auxiliares `_settle_*`, `_receipt_invoice_status`; volver a crear `supplier_payment_save` de la 0025 (las columnas y los estados de factura quedan; no toca datos; no hay archivo de reversión, a diferencia de 0030–0032) |
| 0033 | `supabase/tools/reversion-0033.sql` (funciones de PIN y de aperturas byte a byte como antes; la columna `session_id` y lo anotado quedan; vuelven los problemas que corrige, D-053; revertir 0030–0032 obliga a revertir antes esta) |
| 0032 | `supabase/tools/reversion-0032.sql`, después de la 0033 (devuelve los permisos de antes; una sola transacción; se niega en orden incorrecto) |
| 0031 | `supabase/tools/reversion-0031.sql`, después de la 0032 (funciones byte a byte como antes; las columnas nuevas, el historial de costos y los movimientos ya hechos quedan) |
| 0030 | `supabase/tools/reversion-0030.sql`, después de la 0031 (quita el PIN y los disparadores de historial; `recipe_versions` y sus versiones quedan; **no deshace** el costo promedio que la 0030 dio una vez a los ingredientes con precio y sin compras, D-043) |

## Capacitación recomendada

| Quién | Qué | Tiempo |
|---|---|---|
| Cajeros | Ventana de efectivo (billetes, vuelto, dólares); recibo con número; reimprimir COPIA; qué hacer sin internet (la venta queda guardada) | 20 min |
| Encargados | Lo de los cajeros, más: anular con PIN y motivo; devolver una venta de un día cerrado; **entrada o salida de dinero** (depósito, cambio, pago de una compra: guardar el comprobante); abrir y cerrar la caja en ₡ y $; recibir entregas en partes con la factura | 45 min |
| Dueño | Inicio → Ajustes (interruptores, confirmaciones, tipo de cambio); Información; aprobar las horas del periodo; tarifas de pago; publicar una versión y volver atrás; tarjeta de respaldos y prueba de restauración trimestral | 90 min |
| Contador | Contabilidad: aprobar el catálogo y la fecha de inicio; días pendientes; gastos con foto; proveedores; IVA del período; banco (CSV y conciliación); planilla (reglas confirmadas, revisión, asiento); paquete del mes | 2 h |

Sugerencia: la primera semana de cada ola, el encargado revisa en Información → "Para revisar" y en
Contabilidad → Efectivo que las diferencias de caja sean las de siempre.
