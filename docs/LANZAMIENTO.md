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
2. **Primero en pruebas (staging)**: la misma ola completa, con la lista de verificación de abajo (E-13, E-14).
3. **Fuera de horario**, después del cierre de caja. Ninguna tableta con ventas "pendientes de enviar".
4. **Primero la base, después las páginas.** Las páginas nuevas funcionan con la base vieja (muestran "necesita
   una actualización"), pero las funciones nuevas necesitan la base nueva.
5. **Comprobar**: `supabase/tools/release-check.sql` (solo lectura). Debe mostrar:
   - `migrations_missing` vacío hasta la ola aplicada;
   - `functions_missing` vacío (después de la ola 5);
   - `anon_can_run` solo `canopy_schema_version`, `order_status`, `place_room_order` y `room_lookup`;
   - `tables_without_rls` vacío;
   - `ledger.unbalanced` en 0.
6. **Observar 1 a 3 días** antes de la ola siguiente.

## Ola 0 · Seguridad y respaldos (urgente, ya se puede)

| Paso | Qué | Quién |
|---|---|---|
| 1 | Migraciones **0000** (registro) y **0001** (cierra el hueco de los pedidos de habitación) | Usted (E-01) |
| 2 | Supabase → Authentication → apagar "Allow new users to sign up" | Usted (E-02) |
| 3 | Migración **0002** e instalación de respaldos (unos 60 minutos, docs/RESPALDOS.md) | Usted (E-03) |

- **Comprobar**: el primer respaldo nocturno sale bien. La tarjeta Respaldos está en verde.
- **Volver atrás**: no hace falta: solo agregan revisiones de permiso y el registro.

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

## Ola 5 · Información del negocio (Fase 5)

- **Migraciones**: 0023 y 0024, más la página Información.
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
   cambios posteriores al respaldo; por eso se aplica cada ola justo después de un respaldo verificado.

| Migración | Reversión (también al inicio de cada archivo) |
|---|---|
| 0000, 0001, 0024 | No hace falta |
| 0002 | `drop role canopy_backup; drop table canopy.backup_runs` |
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

## Capacitación recomendada

| Quién | Qué | Tiempo |
|---|---|---|
| Cajeros | Ventana de efectivo (billetes, vuelto, dólares); recibo con número; reimprimir COPIA; qué hacer sin internet (la venta queda guardada) | 20 min |
| Encargados | Lo de los cajeros, más: anular con PIN y motivo; devolver una venta de un día cerrado; **entrada o salida de dinero** (depósito, cambio, pago de una compra: guardar el comprobante); abrir y cerrar la caja en ₡ y $; recibir entregas en partes con la factura | 45 min |
| Dueño | Inicio → Ajustes (interruptores, confirmaciones, tipo de cambio); Información; aprobar las horas del periodo; tarifas de pago; publicar una versión y volver atrás; tarjeta de respaldos y prueba de restauración trimestral | 90 min |
| Contador | Contabilidad: aprobar el catálogo y la fecha de inicio; días pendientes; gastos con foto; proveedores; IVA del período; banco (CSV y conciliación); planilla (reglas confirmadas, revisión, asiento); paquete del mes | 2 h |

Sugerencia: la primera semana de cada ola, el encargado revisa en Información → "Para revisar" y en
Contabilidad → Efectivo que las diferencias de caja sean las de siempre.
