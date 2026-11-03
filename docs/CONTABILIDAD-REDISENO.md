# Rediseño de Contabilidad · análisis y diseño (primera entrega)

**Estado:** propuesta para revisión del dueño. **Nada de esto está implementado.** No se ejecutó SQL en producción, no se publicó
nada, no se cambió ningún permiso y el código de `website/accounting.html` sigue igual. Este documento, el prototipo privado y el
plan son la primera entrega pedida el 2026-10-25 (noche), después de E-36 y aparte de E-05. El 2026-10-26 un panel de crítica
independiente (cuatro lentes y seis escépticos) revisó prototipo y documento; sus hallazgos confirmados están incorporados.

- **Prototipo navegable (privado, datos ficticios):** https://claude.ai/artifact/XgrRSRBesPavkTndnqgUyH — una franja dorada fija
  arriba de todas las pantallas dice «PROTOTIPO · DATOS FICTICIOS · NADA SE GUARDA» y la barra lateral lo repite; ningún número es
  real y nada se guarda. Secciones: `#resumen`, `#gastos`, `#proveedores`, `#ingresos`, `#compras`, `#banco`, `#reportes`,
  `#contabilidad`. Arriba a la derecha: período, **Ver como Dueño | Contador** (para revisar qué vería cada uno) y ES | EN;
  funciona en computadora, tableta (barra de iconos) y teléfono (menú). Es privado: solo lo abre quien usted autorice desde el
  menú Compartir de la página; si lo comparte con enlace público, cualquiera con el enlace lo verá (los datos son ficticios, pero
  conviene compartirlo por persona).
- **Capturas de referencia:** las cuatro capturas adjuntas (contabilidad actual y tres de QuickBooks) no llegaron a este entorno; el
  análisis de la página actual se hizo sobre el código y sobre capturas propias tomadas en una copia local (todas las pestañas, la
  versión de tableta, Información e Inventario → Proveedores / Pedidos). Las referencias de QuickBooks se tomaron de su diseño
  conocido (barra lateral, panel con tarjetas y gráficos, tablas con búsqueda, filtros, orden, paginación y detalle por fila).
- **Fuentes:** `website/accounting.html` (2 093 líneas), las migraciones 0009–0029 que crean el libro mayor, gastos, proveedores,
  compras, caja, banco, IVA, nómina e Información, `website/insights.html`, `website/sales.html`, `website/inventory.html`,
  `docs/DECISIONS.md` (D-011 a D-020, D-037, D-041/042), `docs/CHECKLIST.md` (fases 2–5) y `docs/DEPENDENCIES.md` (A-01…A-12,
  E-16/17/18). Cada afirmación de este documento se verificó en el código o en una base local construida con las migraciones
  0000–0033; cuando se cita una línea es de la versión en producción (`v2026.10.25-2`, commit `29bdde5`).

## Resumen en una página

- **Lo que hay funciona y es sólido:** libro mayor de doble partida con asientos inmutables y balanceados por la base de datos,
  cierre de caja que asienta cada día «por diferencias» (D-013), gastos con IVA acreditable y comprobante en carpeta privada,
  facturas y pagos a proveedores con antigüedad de saldos, compras unidas al inventario (0012, 0029), caja por día con dos
  monedas, importación del CSV del banco y conciliación, IVA del período en borrador, nómina costarricense (apagada hasta que el
  contador confirme), e Información con series mensuales. **66 funciones** y la carpeta privada de comprobantes sirven a la página de
  hoy; todas existen en producción.
- **Lo que falla es la experiencia:** una sola columna con **11 pestañas** sin agrupar, formularios siempre abiertos, listas sin
  búsqueda ni orden ni paginación, sin gráficos, sin detalle por fila, sin estado en la URL, proveedor escrito a mano aunque la
  tabla de proveedores existe, IVA digitado en vez de calculado, nada de recurrencia, y Ventas/Información/Contabilidad repartidas
  en tres páginas.
- **La propuesta:** una página nueva con barra lateral permanente (Resumen, Gastos, Proveedores, Ingresos, Compras, Banco y
  efectivo, Reportes, Contabilidad), construida **encima de las mismas funciones** (la fase 1 es casi toda presentación: 1a solo
  lectura, 1b los formularios que ya existen), con
  datos ficticios en el prototipo y, en la fase real, con las mismas puertas de acceso de hoy (dueño con código del teléfono o
  contador). Nada se borra ni se reescribe; las correcciones siguen siendo reversiones.
- **Lo que sí necesita desarrollo nuevo (todo aditivo, migraciones 0034+):** gastos recurrentes (tabla de plantillas +
  recordatorio, nunca asiento automático), ficha e historial por proveedor (una función de lectura), lista de compras y lista de
  proveedores legibles por el contador (funciones de lectura), ventas por forma de pago por rango, posición de efectivo y
  comparación de períodos en una llamada (funciones de solo lectura), columnas opcionales en proveedores (cédula, plazo de crédito,
  cuenta habitual).
- **Decisiones que necesito antes de programar:** 8, listadas al final (quién registra gastos, recurrencia, gastos a crédito,
  qué ve el contador —4a proveedores y compras, 4b transacciones de ventas—, fuente del panel antes de A-07, período por día de
  negocio, mantener o reescribir las pruebas, quién abrirá la página).

## A. Inventario de lo que existe

### A.1 Módulos y dónde viven

| Módulo | Qué hace hoy | Dónde (código) | Página que lo usa | Estado |
|---|---|---|---|---|
| Libro mayor (`acct`) | Catálogo (53 cuentas), mapeos (42 claves), períodos, asientos y líneas inmutables, asiento del día por diferencias, reportes | `0013_ledger.sql`, `0019`, `0028` | Contabilidad → Resumen, Diario, Reportes, Cuentas, Periodos | Vivo; **asiento automático apagado** hasta A-07 (el contador aprueba el catálogo) |
| Gastos | `expense_save/void/list/attach`; IVA acreditable; pagado con caja/caja chica/banco/crédito/retiro de caja; una foto o PDF por gasto en carpeta privada | `0014`, `0015`, `0019` | Contabilidad → Gastos | Vivo |
| Proveedores | Tabla `vendors` (nombre, contacto, WhatsApp, correo, plazo de entrega, días de pedido, notas, activo) | `supabase/inventory.sql` (histórico) | **Inventario → Proveedores** (no Contabilidad) | Vivo; solo con áreas de dueño o PIN de encargado |
| Cuentas por pagar | Facturas de proveedor (liquidan entregas ya debidas, D-014), pagos con aplicación a facturas, anulaciones, antigüedad `ap_aging` con cuadre contra 2101 | `0016`, `0025`, `0029` | Contabilidad → Proveedores | Vivo |
| Compras | Pedidos, líneas, entregas (`purchase_receipts`), recibir + factura + pago en una transacción (0029), historial y pendientes por pedido | `0012`, `0029`, `inventory.sql` | **Inventario → Pedidos** | Vivo; `po_pending/po_history` cerrados al contador |
| Ingresos (POS) | Ventas, líneas con IVA sellado, tenders en dos monedas, cuentas abiertas y pagos parciales, devoluciones; el día cerrado llega a los libros por `acct.post_day` | `0003/0004/0006/0009/0010/0027`, `pos-tabs.sql`, `register.sql` | Caja, Ventas, Información, Inicio | Vivo |
| Caja por día | Apertura/cierre con fondo y conteo en ₡ y $, movimientos de gaveta (depósito, caja chica, retiro, dueño), retiros por documentar (1104, D-017) | `0010`, `0019`, `0028` | Caja (POS), Contabilidad → Efectivo | Vivo |
| Banco | Cuentas (solo ₡ por ahora, A-06), importación del CSV del banco con mapeo de columnas, conciliar / asentar / ignorar / deshacer | `0020`, `0025` | Contabilidad → Banco | Vivo; **sin conexión bancaria por diseño (D-018)** |
| IVA | Tasas confirmadas, IVA por línea de venta, `iva_report` del período (borrador, D-015), `tax_summary` | `0009`, `0017`, `0025` | Contabilidad → Reportes | Vivo; el contador declara fuera del sistema |
| Comprobantes electrónicos | Registro en modo `off` / `shadow`; nada se envía | `0018` | Contabilidad → Comprobantes | Andamio, apagado |
| Nómina | Períodos, horas aprobadas, planilla, CCSS/INS/renta/aguinaldo/vacaciones/liquidación, asiento y pago | `0021`, `0022`, `0026` | Contabilidad → Planilla | Construido; **reglas legales apagadas** hasta que el contador confirme (A-08) |
| Información | `dashboard_today`, `trends_monthly`, `sales_patterns`, `product_profitability`, `labor_cost`, `supplier_insights`, `stock_forecast`, `inventory_valuation` | `0017`, `0023`, `0028` | Información (insights.html) | Vivo; gráficos SVG propios (D-020) |
| Permisos | `acct.can_read()` = dueño con código **o** contador; `_books_allowed` = permiso de ventas o libros; `_ap_allowed` = áreas de dueño o libros; `inventory_open` = áreas de dueño o PIN | `0013`, `0016`, `0017`, `0025`, `manager-mode.sql` | Todas | Vivo |

### A.2 Tablas que importan para el rediseño (todas existen; ninguna se toca)

- **Libros:** `acct.accounts`, `acct.mappings`, `acct.periods`, `acct.entries`, `acct.lines` (sin acceso directo desde la API:
  solo por funciones; inmutables; balanceadas al confirmar).
- **Gastos y proveedores:** `public.expenses` (incluye `vendor_id`, `receipt_path`, `payout_id`), `public.vendors`,
  `public.supplier_invoices` (moneda y tipo de cambio desde 0029), `public.supplier_payments`, `public.supplier_payment_allocations`.
- **Compras e inventario:** `public.purchase_orders`, `public.purchase_lines`, `public.purchase_receipts` (estado de factura desde
  0029), `public.stock_moves` (compras al costo), `public.stock_items.vendor_id`.
- **Ingresos y caja:** `public.orders`, `public.order_items` (IVA por línea), `public.cash_tenders`, `public.register_days`,
  `public.cash_movements`, `public.fx_rates`.
- **Banco:** `public.bank_accounts`, `public.bank_imports`, `public.bank_lines` (huella para no duplicar).
- **Auditoría y ajustes:** `public.audit_log` (solo se agrega), `compliance_confirmations`, `settings` (`ledger_auto_post`,
  `ledger_start_date`, `einvoice_mode`, `fx_rate_kind`…).

### A.3 Funciones que la nueva página reutiliza tal cual (sin cambios)

| Pantalla nueva | Funciones existentes que la alimentan |
|---|---|
| Resumen | `acct_overview` (días sin asentar, períodos, catálogo), `acct_income_statement`, `acct_cash_flow`, `acct_balance_sheet` (libros); `dashboard_today`, `trends_monthly`, `sales_patterns` (operativo, siempre al día); `ap_aging.ledger` y `cash_payouts` (pendientes) |
| Gastos | `expense_list`, `expense_save` (ya acepta `vendor_id`), `expense_attach`, `expense_void`, `cash_payouts` («archivar su factura») |
| Proveedores | `ap_aging` (lista de proveedores activos, saldos por antigüedad, facturas abiertas, entregas sin factura, 92 días de facturas y pagos), `supplier_invoice_save`, `supplier_payment_save`, sus anulaciones, `supplier_insights`; la tabla `vendors` se lee y se da de alta directamente por PostgREST como hace Inventario (solo con áreas de dueño; el contador la ve con `vendors_list`, fase 2) |
| Ingresos | `cash_reconciliation` (día por día, dos monedas), `tax_summary` (ventas sin IVA / IVA), `sales_patterns.days`, `acct_post_days` («Asentar estos días»: la única escritura de la pantalla), `order_search` (solo dueño); tarjeta y SINPE por día salen de las líneas 1120/1110 del asiento de cada día asentado (`acct_journal`); por rango hace falta `sales_by_method` (fase 2) |
| Compras | Lecturas directas de `purchase_orders`, `purchase_lines` y `purchase_receipts` por PostgREST (políticas de áreas de dueño) más `po_history`; las acciones (`po_receive_and_settle`, `po_receipt_settle`, `po_receipt_pay`) siguen en Inventario; para el contador, `purchases_list` (fase 2) |
| Banco y efectivo | `cash_reconciliation`, `register_cash_moves` (**solo dueño**: exige ingreso del café o áreas de dueño), `bank_overview`, `bank_import`, `bank_auto_match`, `bank_match`, `bank_post`, `bank_ignore`, `bank_undo` (sin motivo; se mantiene así), `bank_account_save`, `fx_today` (**solo dueño**). Los retiros por documentar (`cash_payouts`) viven en Gastos |
| Reportes | `acct_trial_balance`, `acct_income_statement`, `acct_balance_sheet`, `acct_cash_flow`, `iva_report`, `inventory_valuation`, `product_profitability`, `labor_cost`, `trends_monthly`, `supplier_insights` |
| Contabilidad | `acct_journal`, `acct_entry_post`, `acct_journal_reverse`, `acct_period_set`, `acct_account_save`, `acct_mapping_set`, `compliance_confirm`, `setting_set`, `einvoice_list`, y todas las de nómina |

### A.4 Flujos de hoy (y qué es manual que el sistema ya sabe)

1. **Asentar las ventas.** La caja cierra → el día aparece en «Días cerrados sin asentar» → clic en «Asentar estos días» →
   un asiento por día con todo lo que `acct.day_target` (0019) calcula para esa fecha: dinero por forma de pago (1101 efectivo ₡
   neto de vueltos, 1102 dólares al tipo de cambio, 1120 tarjetas, 1110 SINPE, 1130 otros), ventas sin IVA 4101 y devoluciones
   4102, IVA 2110, anticipos de cuentas abiertas 2120, diferencia de caja 6211, costo de lo vendido 5101 contra inventario 1150,
   mermas 5102 y ajustes 5103, entregas recibidas 1150 contra proveedores 2101, y los movimientos de gaveta (retiros por
   documentar 1104, caja chica 1103, depósitos 1110) contra 1101. *Manual hoy:* el clic, porque el asiento automático espera la
   aprobación del catálogo (A-07). Nunca se vuelve a digitar una venta.
2. **Registrar un gasto.** Formulario siempre abierto: fecha, proveedor **a mano**, descripción, cuenta, total con IVA, IVA
   **a mano**, pagado con, Nº y fecha de factura, foto. `expense_save` asienta de inmediato. *Manual que sobra:* proveedor (hay
   tabla), IVA (13 % calculable), recurrencia (alquiler, luz, internet se digitan cada mes), sin botón «Nuevo gasto».
3. **Retiro de la gaveta → su factura.** Encargado saca dinero con PIN en la Caja → Contabilidad → Efectivo lo lista →
   «Archivar su factura» salta al formulario de gasto prellenado. Es el único atajo entre pestañas que existe.
4. **Factura de proveedor.** Con XML de Hacienda o a mano; se marcan las entregas que cubre; la diferencia de precio va a 5103;
   nunca toca inventario (D-014). *Dos puertas:* también se registra al recibir en Inventario (0029).
5. **Pagar a un proveedor.** Proveedor, monto, pagado con, factura a pagar primero; nunca más de lo debido.
6. **Caja por día y banco.** Tabla de días (fondo, efectivo neto recibido, entradas, salidas, esperado, contado, diferencia);
   importar CSV del banco, conciliar sugerencias, asentar lo que falta, ignorar, deshacer.
7. **Reportes.** Un selector con 8 reportes en tabla, CSV, imprimir, «Paquete del mes (ZIP)» con 9 CSV para el contador.
8. **Cierre de mes.** Cerrar (nada más con esa fecha; el contador puede reabrir) y bloquear (definitivo).
9. **Nómina.** Período → horas aprobadas (dueño) → preparar → revisar (contador) → asentar → pagar; aguinaldo, vacaciones,
   liquidación. Todo marcado «estimado» hasta confirmar las reglas.

### A.5 Reglas que el rediseño no puede romper (verificadas en el código)

- **Nada se edita ni se borra:** `acct._immutable` rechaza `update/delete` de asientos y líneas incluso al superusuario;
  gastos, facturas, pagos y líneas de banco se **anulan por reversión** con motivo. No habrá botones «Editar» ni «Eliminar» sobre
  documentos asentados; habrá «Anular y volver a registrar».
- **Cada asiento cuadra** (triggers diferidos) y **solo `acct.post` escribe**; el esquema `acct` no se alcanza desde la API.
- **Las ventas llegan a los libros solo por el asiento del día** (por diferencias, idempotente). La pantalla Ingresos **lee**; su
  única escritura es el botón «Asentar» (`acct_post_days`, el mismo de hoy); jamás crea asientos ni «ingresos» a mano.
- **Puertas de acceso:** los libros abren solo para el dueño **con código del teléfono** o para el contador; el ingreso del café y
  los PIN de encargado nunca (prueba SQL 140). Dueño-solo: aprobar el catálogo, aprobar horas, dar acceso al contador.
  Contador-solo: revisar nómina.
- **Lo regulado sigue apagado y rotulado:** comprobantes electrónicos `off`, nómina «estimado» hasta `payroll_cr_rules`, IVA
  «borrador», asiento automático detrás de `chart_of_accounts_approved`.
- **Idempotencia:** cada formulario manda un `p_request_id` único por intento y lo reutiliza al reintentar (doble toque sin
  duplicar).
- **Fechas:** día de negocio de Costa Rica; nada con fecha futura ni en mes cerrado; anulaciones con fecha de hoy.
- **Banco sin conexión** (D-018): CSV del banco, huella anti-duplicados; nada de «sincronizar con el banco».
- **Texto bilingüe por diccionario** (`website/lang.js`, inglés → español); **estilo** (`:root` de la página, Figtree / Playfair /
  Spline Sans Mono); **pruebas** (`tests/run.sh`) antes de cada commit; **migraciones aditivas** numeradas desde 0034.

### A.6 Topes de rango que la nueva página debe respetar (están en las funciones; no se cambian)

| Función | Tope | Qué hace la página |
|---|---|---|
| `cash_reconciliation`, `iva_report`, `acct_post_days` | ≤ 92 días por llamada | «Año» se arma con cuatro llamadas de ≤ 92 días y se suma en el navegador |
| `order_search` | ≤ 92 días y 200 filas por consulta | Lista por recibo del dueño con «cargar más» por fechas; nunca se promete «todo el año» |
| `acct_journal` | ≤ 400 días | «Año» cabe en una llamada; el diario se pagina en el navegador |
| `sales_patterns`, `product_profitability`, `labor_cost` | ≤ 366 días | Una llamada por período |
| `trends_monthly` | ≤ 24 meses | Gráficos mensuales de hasta dos años |
| `ap_aging` | facturas y pagos de los últimos 92 días | El historial completo por proveedor es `vendor_history` (fase 2) |

Las comparaciones «actual vs anterior» de la fase 1 son dos rangos (dos llamadas); `period_compare` (fase 2) las deja en una.

## B. Navegación y estructura de cada pantalla

### B.1 La barra lateral (permanente en computadora, de iconos en tableta, menú en teléfono)

| Entrada | Agrupa lo que hoy es | Para quién | Hoy el contador… |
|---|---|---|---|
| **Resumen** | Pestaña Resumen + lo útil de Información + «días sin asentar» | Dueño con código, contador | ve todo (libros, `dashboard_today`, `trends_monthly`, `ap_aging`); no ve `cash_payouts` ni `register_cash_moves` (solo dueño) |
| **Gastos** | Pestaña Gastos + «retiros de caja por documentar» | Dueño con código, contador (decisión 1: ¿también PIN de encargado?) | registra, anula y adjunta gastos (`_ap_allowed`); la lista de retiros de caja es solo dueño |
| **Proveedores** | Pestaña Proveedores + Inventario → Proveedores (ficha, contacto, historial, saldos) | Dueño con código, contador (lectura; alta y edición: decisión 4a) | ve saldos y facturas (`ap_aging`); **no** ve contacto ni plazo (tabla `vendors`, áreas de dueño) hasta `vendors_list` (fase 2) |
| **Ingresos** | Nuevo: lo que la Caja ya sabe, día por día, sin digitar nada | Dueño con código, contador | ve días y totales (`cash_reconciliation`, `tax_summary`); **no** `order_search` (decisión 4b) |
| **Compras** | Inventario → Pedidos visto desde la contabilidad (pedido → entrega → factura → pago) | Dueño; contador con `purchases_list` (fase 2, decisión 4a) | no ve nada: pedidos, entregas y `po_history` exigen áreas de dueño; la sección se le muestra atenuada |
| **Banco y efectivo** | Pestañas Efectivo + Banco | Dueño con código, contador | ve caja por día y banco completo; no los movimientos de gaveta ni `fx_today` |
| **Reportes** | Pestaña Reportes + gráficos de Información | Dueño con código, contador (mano de obra solo con libros) | ve los ocho reportes |
| **Contabilidad** | Diario, Catálogo de cuentas, Mapeos, Períodos, Comprobantes electrónicos (apagado), Planilla (enlace a la pantalla actual), Auditoría, Activación | Dueño con código, contador | diario, catálogo, mapeos y períodos sí; Auditoría no (`audit_log` es áreas de dueño) hasta `acct_audit` (fase 2); Activación es solo dueño |

Arriba, en todas las pantallas: selector de período (Este mes · Mes pasado · 3 meses · Año), ES | EN, quién está dentro
(«Dueño · con código» / «Contador»). La sección activa queda en la dirección (`#gastos`), así que se puede guardar o compartir
el enlace de una pantalla. La barra lateral oculta lo que el tipo de cuenta no puede hacer (igual que hoy `KIND === 'owner'`).

### B.2 Cada pantalla, bloque por bloque (y de dónde sale cada dato)

**Resumen**
- Siete tarjetas: Ingresos sin IVA, Gastos y costos, Utilidad, Efectivo y bancos, Por pagar a proveedores, IVA neto y Gastos a
  crédito sin pago (esta última depende de la decisión 3). Cada una con
  la variación contra el período anterior y una etiqueta honesta: **«según la caja»** (operativo, siempre al día,
  `dashboard_today` / `sales_patterns` / `trends_monthly`), **«estimado»** (día abierto o mes sin cerrar) o **«en libros»**
  (`acct_income_statement` / `acct_balance_sheet`, solo días asentados). Hasta que A-07 active el asiento automático, el titular
  sale de la caja y los libros se muestran como segunda lectura; si no, el panel leería cero.
- Gráficos: ingresos y gastos por mes (barras), utilidad por mes (línea), ventas por forma de pago (dona: por día solo para días
  asentados, leyendo 1101/1102/1120/1110 del asiento; por rango necesita `sales_by_method`, fase 2), gastos por categoría (barras
  horizontales). Todos en SVG propio, como Información (D-020), sin librería externa.
- «Pendientes»: facturas de proveedor vencidas (`ap_aging`), días cerrados sin asentar (`acct_overview.pending_days`, con el
  botón «Asentar» de siempre), retiros de caja sin factura (`cash_payouts`), movimientos del banco por conciliar
  (`bank_overview`), gastos sin comprobante (`expense_list`), recurrentes que vencen (nuevo). Cada línea lleva a su pantalla.
- No hay «cuentas por cobrar»: Canopy no factura a clientes. La tarjeta honesta es «cuentas abiertas» (`dashboard_today.unpaid`)
  y «tarjetas por liquidar» (1120).

**Gastos**
- Botón destacado **«Nuevo gasto»** → cajón lateral con el formulario: fecha, proveedor (buscador sobre la lista de proveedores,
  con «agregar nuevo»), ¿qué fue?, categoría (= cuenta de gasto activa; 5101, 5102, 6201–6299, los códigos del catálogo real),
  total con IVA, IVA acreditable con botón **«Calcular 13 %»** (y tasas reducidas), pagado con (dinero sacado de la caja → elige el
  retiro; caja chica; transferencia o SINPE; a crédito; efectivo de la caja fuerte — los cinco que `expense_save` acepta), Nº de
  factura, **se repite** (no / cada semana / cada mes + día; fase 3), comprobante (foto desde la tableta o PDF; carpeta privada
  actual).
- Tabla QuickBooks: búsqueda instantánea, filtros (categoría, proveedor, pagado con, estado), columnas ordenables, 10/25/50 por
  página, totales al pie, acciones claras (Duplicar; «Registrar pago» sobre un gasto a crédito **queda fuera de la fase 1**:
  depende de la decisión 3). Clic en la fila → detalle: todos los
  campos, comprobante (enlace firmado de 120 s, como hoy), **el asiento en los libros** (Debe/Haber), acciones Anular (reversión)
  y Duplicar. Todo sobre `expense_list` en el navegador (volumen de cafetería: cientos de filas por año).
- «Retiros de caja que esperan su factura» (hoy en Efectivo) pasa a vivir aquí, con el salto prellenado que ya existe.
- Lo que cambia en el servidor: **nada** para la primera fase; el proveedor viaja como `vendor_id` (la función ya lo acepta).
  Recurrencia = fase 2 (tabla de plantillas; **nunca** asiento automático: recordatorio + formulario prellenado + clic humano).

**Proveedores**
- Tabla con búsqueda y botón **«Agregar proveedor»** (en fase 1 escribe en la tabla `vendors` desde la sesión del dueño, igual que
  Inventario; el contador no lo ve hasta la decisión 4a): proveedor (y qué provee), contacto (WhatsApp / teléfono / correo), saldo
  pendiente, estado (al día / vencida), última compra, compras 12 meses, plazo. Fuente: `ap_aging` (saldos, lista) +
  `supplier_insights` (compras, entregas, cambios de precio) + `vendors` (contacto y plazo; hoy solo lo lee quien tiene áreas de
  dueño, así que para el contador esas columnas llegan con `vendors_list` en fase 2).
- Ficha al hacer clic: datos de contacto, saldos por antigüedad (sin vencer / 1–30 / 31–60 / más de 60), historial (facturas,
  pagos, pedidos, gastos), botones Nueva factura, Nuevo gasto, Registrar pago (reutilizan `supplier_invoice_save`, `expense_save`,
  `supplier_payment_save`).
- Mismo registro que usa Inventario para pedir: una sola tabla `vendors`, vista desde los dos lados. Columnas nuevas propuestas
  (aditivas, fase 2): cédula, plazo de crédito (hoy 30 días fijos), cuenta habitual, notas de pago.

**Ingresos**
- Banda «Hoy (caja abierta)» con el monto hasta esta hora y la etiqueta «estimado» (`dashboard_today`).
- Tarjetas: **Cobros (dinero recibido)** y **Ventas sin IVA** por separado (una cuenta abierta se cobra en partes antes de
  reconocerse como venta, D-013), IVA, pedidos, ticket promedio, descuentos y cortesías, devoluciones.
- Gráfico de ventas por día (4 semanas) y tabla de **días de caja**: día, pedidos, cobros, ventas sin IVA, IVA, efectivo,
  tarjeta y SINPE (por día solo en días asentados, del asiento; por rango `sales_by_method`, fase 2), diferencia de caja, estado
  (asentado / por asentar / abierto). Clic → detalle del día con el asiento que generó y, si falta, el botón «Asentar el día».
  Fuente: `cash_reconciliation` + `tax_summary` + `acct_overview`. La única escritura de la pantalla es «Asentar» (`acct_post_days`).
- Para el dueño, además, la lista de transacciones con buscador (`order_search`: recibo, hora, ítems, forma de pago, cajero; ≤ 92
  días y 200 filas por consulta); para el contador esa función está cerrada hoy (decisión 4b).

**Compras**
- Aviso fijo: «Lo que Inventario recibe queda por pagar hasta que llega la factura; la factura liquida la entrega y las
  diferencias nunca tocan la cuenta de inventario» (D-014).
- Tabla: pedido, fecha, proveedor, qué se pidió, total, inventario (ingresado / pendiente), factura, estado (enviado / recibido /
  facturado / pagado; los estados reales son más finos y se resumen en esos cuatro), acción siguiente («Recibir en Inventario →»
  enlaza a la tableta de Inventario; «Nueva factura» y «Registrar pago» abren los formularios de Proveedores). Clic → detalle con
  entregas, factura y pagos (`po_history`). «Recibir» y «Pagar» con PIN siguen en Inventario (no se duplica esa pantalla).
- Fuente para el dueño (fase 1): lecturas directas de `purchase_orders`, `purchase_lines` y `purchase_receipts` (políticas de
  áreas de dueño) más `po_history`. Para que el **contador** vea esta lista hace falta `purchases_list(desde, hasta, proveedor?)`,
  solo lectura, con `_ap_allowed()` (fase 2, decisión 4a); hasta entonces la sección se le muestra atenuada, como en el prototipo.

**Banco y efectivo**
- Pestaña **Efectivo**: tabla por día (fondo, **efectivo neto recibido**, entradas, salidas, esperado, contado, diferencia; dos
  monedas) y movimientos de gaveta del día (solo dueño: `register_cash_moves` exige ingreso del café o áreas de dueño). Los
  retiros por documentar viven en Gastos. Fuente: `cash_reconciliation`, `register_cash_moves`.
- Pestaña **Banco**: tarjeta por cuenta (saldo según la última importación, saldo en libros 1110, caja chica 1103 «en libros»),
  botón **«Importar CSV del banco»** (el mismo asistente de mapeo de columnas de hoy, re-vestido) y la tabla de movimientos con
  búsqueda, filtro por estado (conciliado / por conciliar / ignorado), la **sugerencia** de con qué cuadra y las cuatro acciones
  (Conciliar; Asentar, que abre «Nuevo gasto» prellenado y pagado con banco, como `bank_post` hoy; Ignorar; Deshacer, que en
  `bank_undo` no pide motivo y se mantiene así). Además la lista «en los libros, no en el estado de cuenta». Aviso fijo: «No hay
  conexión con el banco». Solo cuentas en colones hasta A-06: la cuenta en dólares se muestra deshabilitada con ese aviso.

**Reportes**
- Galería de 8 fichas, cada una con la etiqueta que le toca según el estado del período (estimado / en libros / borrador / según
  documentos): Estado de resultados (actual vs anterior, con barras por mes), Flujo de efectivo, IVA del mes (borrador: cobrado,
  acreditable, saldo), Gastos por categoría, Costo primo (alimentos + mano de obra), Productos que más dejan, Balance general,
  Compras por proveedor. Cada reporte: tabla + gráfico + CSV + Imprimir; el «Paquete del mes (ZIP)» queda junto a los reportes.
  El balance de comprobación y la valoración de inventario (hoy en el selector de la página actual) no están dibujados en la
  galería del prototipo y se conservan en la fase 1 (Contabilidad → Diario y Reportes, respectivamente).
- Fuente: las funciones de hoy. Lo nuevo es solo la presentación y las comparaciones; para «actual vs anterior» se llaman dos
  rangos (o, fase 2, una función de comparación en una llamada).

**Contabilidad** (lo técnico, agrupado y fuera del camino diario)
- Diario con búsqueda, filtro por origen y detalle de líneas; «Revertir» solo en manuales y de apertura (`acct_journal_reverse`);
  los demás enlazan a su documento y lo ya revertido lo dice. Catálogo de cuentas (agregar / renombrar; nunca borrar). Mapeos
  (clave → cuenta, `acct_mapping_set`). Períodos (cerrar / reabrir / bloquear; aviso cuando el mes tiene días sin asentar, porque
  «Asentar» fallaría con `period_closed`). Comprobantes electrónicos (modo `off`; en `shadow` solo registraría localmente; desde
  Canopy nunca se envía nada a Hacienda; con la lista de productos sin CABYS). Planilla (enlace; no se toca). Auditoría (lectura
  de `audit_log`: hoy solo áreas de dueño; para el contador necesita `acct_audit`, fase 2). Activación (el cuadro «Antes de que los
  libros funcionen solos» con aprobado por / documento / primer día, hoy en la cabecera de todas las pestañas; solo dueño).

### B.3 Lo que no aparece en la propuesta, a propósito

- Conexión bancaria, lectura automática de facturas, envío a Hacienda, cuentas por cobrar a clientes, asientos automáticos
  de gastos recurrentes, cambio de reglas de IVA o de precios: **no existen y no se inventan**. Donde el sistema no sabe algo, la
  pantalla lo dice («no hay conexión con el banco», «borrador para el contador», «estimado»).
- Lo que la página de hoy tiene y el prototipo **no dibuja** (se conserva igual en la fase 1): balance de comprobación, valoración
  de inventario, el asistente de columnas al importar el CSV del banco, la pantalla completa de nómina (queda enlazada), la vista
  de inscripción del código del teléfono con su advertencia (D-027) y el cierre por inactividad.

## C. El prototipo

- **Dónde:** https://claude.ai/artifact/XgrRSRBesPavkTndnqgUyH (artefacto privado de claude.ai; solo quien usted autorice puede
  abrirlo desde el menú Compartir de la página). No está en el sitio del café ni en GitHub.
- **Qué es:** un archivo HTML sin conexión a Supabase, con datos ficticios generados siempre iguales (6 meses de caja, 76
  gastos, 13 proveedores con nombres como «Lácteos Ejemplo S.A.», 26 pedidos con 25 facturas y 20 pagos, 2 cuentas bancarias con
  42 líneas de estado de cuenta, 300 asientos derivados que cuadran uno por uno, personas como «Encargada ejemplo»). Nada se
  guarda: cada «Guardar» muestra el aviso «Prototipo: nada se guarda». El conmutador **Ver como Dueño | Contador** atenúa y rotula
  lo que el contador no puede leer hoy.
- **Qué se puede probar:** las ocho secciones; búsqueda instantánea, filtros, orden por columna, paginación y detalle por fila en
  Gastos, Proveedores, Ingresos, Compras, Banco y Diario; el formulario «Nuevo gasto» (cálculo del 13 %, recurrencia, comprobante);
  la ficha de proveedor; los ocho reportes con sus gráficos; el selector de período; ES | EN; tableta y teléfono; modo oscuro.
- **Qué es fiel a la realidad:** las 53 cuentas del catálogo con sus códigos y nombres (1101…6299), 23 de los 42 mapeos, las cinco
  formas de pago de un gasto, la composición del asiento del día, el flujo pedido → entrega → factura → pago (D-014), las
  etiquetas «según la caja / estimado / en libros / borrador / según documentos», las reglas (anular, no editar; reversión solo de
  manuales y apertura; «no hay conexión con el banco»; comprobantes electrónicos apagados; planilla intacta) y las puertas por
  tipo de cuenta.
- **Qué está simplificado:** los estados de pedido, factura y período se resumen en pocos valores (los reales son más finos); el
  prototipo muestra 8 reportes de los que la página real tendrá 10 (ver B.2); el asistente de columnas del CSV y el formulario de
  asiento manual no están dibujados, solo descritos.
- **Qué es solo ilustrativo:** las cifras, los productos del reporte de rentabilidad, el porcentaje de mano de obra y los nombres
  de proveedores y personas. El estilo (tipografías Playfair / Figtree / Spline Sans Mono, verdes y cremas del sitio) es el de las páginas
  actuales. El modo oscuro existe solo porque el visor de artefactos puede estar en oscuro; el sitio del café es de tema claro y
  la página real seguirá igual.
- **Aviso sobre la historia real:** producción se reinició el 2026-10-15 (D-038/D-040), así que la página real tendrá pocas
  semanas de datos: las comparaciones «mes contra mes» del prototipo (seis meses ficticios) se verán vacías o parciales hasta
  bien entrado 2027. Las tarjetas y tablas funcionan desde el primer día; los gráficos largos se llenan con el tiempo.
- **Cómo se verificó:** los datos ficticios se generan con una comprobación de que los 300 asientos cuadran (Debe = Haber); dos
  recorridos automáticos en Chromium (las ocho secciones; búsqueda «Alquiler» → 6 filas; orden por total en los dos sentidos;
  filtro de estado; página 2; cajones de gasto, proveedor, pedido, día de caja, línea del banco y asiento; «Asentar desde el
  banco» que abre el gasto prellenado; formulario con IVA 13 000 sobre 113 000; los 8 reportes; las 8 subpestañas de
  Contabilidad; «Ver como Contador» en todas las secciones; EN completo; períodos «3 meses» y «Año»; 1366, 1024 × 1366, 820 × 1180
  y 400 × 800 sin desplazamiento horizontal; modo oscuro) sin errores de consola salvo las fuentes bloqueadas en el entorno local;
  y un panel de crítica independiente cuyos hallazgos confirmados (asientos del día sin contrapartida de caja, anulación modelada
  como borrado, crédito confundido con factura, entregas como gastos, cuenta en dólares, colores que no seguían el tema) se
  corrigieron antes de esta versión.

## D. Plan por fases, riesgos, pruebas y preservación

### D.0 Requisitos previos que no dependen del código

- **Quién podrá abrir la página real.** Los libros abren solo para el dueño **con el código del teléfono** (aal2) o para el
  contador (D-022). Según `docs/DEPENDENCIES.md`, E-06 (código del teléfono en el ingreso personal del dueño) y E-18 (ingreso del
  contador) siguen **abiertos**; el ingreso del 16/09 tiene autenticador (su lectura del 23/10), pero es el compartido que E-05
  retira de los aparatos. Sin cerrar E-06 o E-18, nadie puede usar ni la página de hoy ni la rediseñada en producción.
- **Respaldo de los comprobantes.** Los archivos de la carpeta privada de gastos no entran al respaldo nocturno hasta que se
  completen las llaves S3 (E-17). Conviene cerrarlo antes de hacer más visible el «comprobante adjunto».
- **Catálogo aprobado (A-07).** Mientras el contador no apruebe el catálogo, el asiento automático sigue apagado y los libros solo
  tienen los días asentados a mano; por eso el panel usa primero las cifras operativas.

### D.1 Fases (cada una se aprueba, se prueba y se publica por separado; ninguna toca datos históricos)

| Fase | Qué entrega | Base de datos | Páginas | Riesgo |
|---|---|---|---|---|
| **0 · Decisiones** (esta entrega) | Prototipo aprobado con cambios; las 8 decisiones de abajo registradas en `docs/DECISIONS.md` | — | — | Ninguno |
| **1a · La nueva página, solo lectura** (≈ 60–70 % del trabajo de la fase 1) | `website/contabilidad.html` (nueva, junto a la actual; en su propia rama, sin mezclarse con E-05) con barra lateral, Resumen, Gastos (lista y detalle), Proveedores (lectura + saldos), Ingresos, Compras (dueño), Banco y efectivo (lectura), Reportes y Contabilidad (lectura) **sobre las 66 funciones de hoy**; `website/charts.js` compartido (SVG extraído de Información y Ventas) y el componente de tabla; textos en `lang.js`; `accounting.html` queda intacta y enlazada desde Contabilidad hasta que la nueva la reemplace; la nueva página conserva tal cual el ingreso, el pedido del código del teléfono y la vista de inscripción con su advertencia (D-027), el cierre por inactividad de 30 min y avisa a `version.js` (`HG_SAFE_TO_RELOAD`) para no recargar con un cajón abierto; el nombre `contabilidad.html` ya está permitido por `config.js` | **Ninguna migración** | 1 nueva + `lang.js` + `charts.js` | Bajo: misma puerta de acceso, mismas funciones, ninguna escritura |
| **1b · Los formularios que ya existen** (≈ 15 %) | «Nuevo gasto» (proveedor por `vendor_id`, «Calcular 13 %», comprobante, «Asentar desde el banco» prellenado), anular gasto, factura y pago de proveedor, «Agregar proveedor» (escritura directa en `vendors` desde la sesión del dueño, como Inventario), «Asentar N días», importar CSV / conciliar / asentar / ignorar / deshacer, cerrar / reabrir / bloquear mes, asiento manual y reversión, catálogo y mapeos, activación; cada uno llama a la misma función con el mismo `p_request_id` por intento | **Ninguna migración** | La misma página | Medio: son escrituras reales aunque con funciones ya probadas; pruebas de navegador por formulario (guardar, doble toque, error de red) antes de publicar |
| **1 · Pruebas y cierre** (≈ 15 % pruebas, ≈ 5 % documentación) | `tests/e2e/specs/360_contabilidad.spec.js`, `lang.js` completo, D-0xx en `DECISIONS.md`, `CHECKLIST.md`, ensayo en pruebas con la etiqueta | — | — | — |
| **2 · Lecturas que faltan** (migración 0034, solo funciones de lectura y columnas opcionales) | `vendor_history(vendor_id, desde, hasta)`, `vendors_list()`, `purchases_list(desde, hasta, proveedor?)`, `sales_by_method(desde, hasta)`, `cash_position()`, `period_compare(desde, hasta)` con estado estimado/final/en libros por mes, `acct_audit(desde, hasta)`; columnas opcionales en `vendors` (cédula, plazo de crédito, cuenta habitual, notas de pago) y vencimiento por defecto desde el plazo **solo para facturas nuevas** (las existentes no cambian) | Aditiva (0034): funciones `security definer` con las guardas de la tabla de abajo y columnas `null` por defecto; cada función nueva se agrega a `release-check.sql` y al inventario de `snapshot-known.sh`; reversión = `drop function` / columnas quedan | Compras y proveedores completos para el contador, ficha completa de proveedor, forma de pago por rango, tarjetas de posición de efectivo y comparaciones en una llamada, Auditoría | Bajo-medio: sin cambios de escritura; pruebas SQL nuevas (410) |
| **3 · Recurrencia y crédito** (migración 0035) | Tabla `expense_schedules` (proveedor, descripción, cuenta, monto, IVA, pagado con, periodicidad, próximo vencimiento, activa) con `expense_schedule_save/void` detrás de `acct.can_read()` + `expense_due()` + «Registrar ahora» que prellena y guarda por `expense_save` con id determinista plantilla + período + intento (un doble toque no duplica; un reintento tras un error sí vuelve a guardar; `repeat` se trata como el mismo intento); política para gastos a crédito (decisión 3) | Aditiva (0035) | Avisos de «vencen esta semana», botón en Gastos | Medio: nueva tabla; **ningún asiento automático** (fechas futuras y meses cerrados siguen prohibidos) |
| **4 · Reemplazo** | `contabilidad.html` pasa a ser la página enlazada desde Inicio; `accounting.html` se conserva un ciclo como respaldo y luego se retira; pruebas de navegador reescritas sobre la nueva página | — | Enlaces en Inicio | Bajo si las fases 1–3 llevan semanas en uso |

Guardas de la fase 2 (cada función nueva lleva la suya y una prueba de «quién puede»):

| Función nueva | Guarda | Quién pasa |
|---|---|---|
| `vendor_history`, `vendors_list`, `purchases_list` | `_ap_allowed()` | dueño con áreas, dueño con código, contador |
| `sales_by_method`, `cash_position`, `period_compare`, `acct_audit` | `acct.can_read()` | dueño con código, contador |
| mano de obra dentro de `period_compare` | `_pay_staff_allowed()` además | solo quien hoy ve `labor_cost` |

Fuera de alcance (y así se dirá en la página): conexión bancaria, cuentas por cobrar a clientes, envío de comprobantes
electrónicos, cuentas bancarias en dólares (A-06), cierre anual (D-037: antes de los libros 2027, decisión aparte), rol de
contador de solo lectura.

### D.2 Riesgos y cómo se controlan

| Riesgo | Control |
|---|---|
| Mostrar en el panel números que luego cambian (día abierto, mes sin asentar) y que el dueño decida con ellos | Etiquetas obligatorias «según la caja / estimado / en libros» en cada tarjeta; banner de «días sin asentar»; hasta A-07 el titular es operativo (D-020) |
| Duplicar ventas o ingresos | La pantalla Ingresos no escribe; el único camino a los libros sigue siendo el asiento del día por diferencias (D-013); prueba SQL 140 y el ensayo `books.sql` lo verifican |
| Abrir puertas que hoy están cerradas (contador leyendo Inventario, PIN de encargado registrando gastos desde Contabilidad) | Fase 1 no cambia ningún permiso; en fase 2 cada función nueva lleva la guarda explícita y una prueba de «quién puede» (dueño con código, contador, café + PIN, café solo) |
| Romper las 22 pruebas de navegador que localizan `accounting.html` por ids | La nueva página es un archivo nuevo; las pruebas viejas siguen pasando; las nuevas se escriben con el mismo arnés (`tests/e2e`, logins dueño/contador/café, aal2) y en 1366 y 820 px |
| Doble guardado en conexiones lentas | Mismo patrón de `p_request_id` por intento; en recurrentes id determinista |
| Texto en inglés que se cuela (diccionario incompleto) | Cada cadena nueva en `lang.js`; prueba de navegador que afirma los textos en español (como 180/290) |
| Mezclar con E-05 / E-36 | Ningún cambio en `access.js`, `keypad.js`, `login.js`, PIN ni ingresos; la nueva página solo carga esos archivos como hoy; el código de la fase 1 va en su propia rama y se publica en su propia etiqueta, en otra ventana, cuando E-05 esté cerrado |
| Que un gráfico «invente» | Todas las series salen de funciones existentes; mismo SVG de D-020; cada gráfico con su tabla y su CSV |
| Dependencia externa nueva | La regla 13 de `tests/lint.sh` solo permite `supabase-js` 2.49.1 y `qrcode-generator` 1.4.4 desde internet: los gráficos y la tabla se escriben a mano, como Información; nada de librerías por CDN |
| Perder un formulario a medio escribir cuando una tableta se actualiza | `window.HG_SAFE_TO_RELOAD` en falso mientras un cajón está abierto; `version.js` espera |

### D.3 Pruebas

- **SQL (`tests/sql`)**: las suites 140 (libro), 150 (gastos), 160 (comprobantes), 170 (proveedores), 180 (IVA), 200 (caja),
  210 (banco), 230 (Información), 310 y 320 siguen siendo la red; fase 2 agrega `410_contabilidad_lecturas.test.sql` (shapes,
  rangos, guardas por tipo de cuenta) y fase 3 `420_recurrentes.test.sql` (id determinista, nunca fecha futura ni mes cerrado,
  nunca asiento sin clic). Las suites SQL van hoy por la 400.
- **Navegador (`tests/e2e`)**: `360_contabilidad.spec.js` (los specs van por el 350) con el arnés actual: puerta (café rechazado, contador entra sin
  botones de dueño), cada sección carga, tabla busca/ordena/pagina, «Nuevo gasto» guarda con `vendor_id` y adjunta, ficha de
  proveedor, «Asentar estos días», importar CSV, conciliar, reportes con sus CSV, ES/EN, tableta 820 px. Las 22 pruebas de
  `accounting.html` no se tocan hasta la fase 4.
- **Ensayo**: «Ensayo en pruebas» con la versión (reinicio = `no`) antes de cada etiqueta, como en E-36; para las migraciones
  0034/0035, el simulacro en la copia representativa (aplicar, usar, revertir) antes de pedir la ventana.
- **Revisión independiente**: panel de crítica antes de cada fase (integridad de doble partida, permisos, UX bilingüe/tableta,
  reutilización).

### D.4 Cómo se preservan datos y funciones

- Ninguna migración modifica ni borra filas; solo agrega funciones de lectura, una tabla nueva y columnas opcionales.
- Ninguna función existente cambia de firma: la página actual, las pruebas y el respaldo nocturno siguen funcionando.
- Las reversiones de cada migración se escriben con la migración (como `reversion-0033.sql`) y se ensayan.
- `accounting.html` queda publicada junto a la nueva hasta la fase 4; si algo falla, se vuelve al enlace anterior sin tocar la
  base.
- El respaldo verificado (E-03) y el ensayo con datos anonimizados siguen siendo requisito antes de cada ventana.

## E. Qué funciona, qué se reutiliza y qué es desarrollo nuevo (por punto del pedido)

| Punto | Ya funciona hoy | Se reutiliza tal cual | Desarrollo nuevo | Tamaño |
|---|---|---|---|---|
| 1 · Barra lateral permanente | No (11 pestañas) | Puerta de acceso, `lang.js`, tokens de estilo | Página nueva con barra, rutas `#`, versión tableta/teléfono | Página (fase 1) |
| 2 · Panel con ingresos, gastos, utilidad, efectivo, pendientes y comparaciones | 5 tarjetas de un mes, sin gráficos | `acct_*`, `dashboard_today`, `trends_monthly`, `sales_patterns`, `ap_aging`, `cash_payouts`, `acct_overview.pending_days` | Composición + gráficos SVG (fase 1); `period_compare` y `cash_position` en una llamada (fase 2) | Página + 2 funciones de lectura |
| 3 · Tablas tipo QuickBooks | No | Los arreglos que ya devuelven las funciones | Componente de tabla (búsqueda, filtros, orden, paginación, detalle) en el navegador; paginación en servidor solo si el volumen lo pide | Página |
| 4 · Gastos: «Nuevo gasto», formulario simple, impuestos, comprobante, recurrencia | Formulario completo, comprobante, anulación por reversión | `expense_save` (acepta `vendor_id`), `expense_attach`, `expense_void`, `expense_list`, `cash_payouts` | Botón y cajón, buscador de proveedor, «Calcular 13 %» (fase 1); **recurrencia** = tabla + recordatorio (fase 3); «tarjeta» como forma de pago de un gasto requiere 2 mapeos (decisión) | Página + 1 tabla |
| 5 · Proveedores: tabla, «Agregar proveedor», ficha, historial, saldos | Saldos por antigüedad; alta/edición solo en Inventario | `ap_aging`, `supplier_insights`, `vendors` (lectura y alta directas, áreas de dueño), `supplier_*_save` | Tabla y ficha (fase 1 con lo que `ap_aging` da; «Agregar proveedor» desde la sesión del dueño); `vendor_history`, `vendors_list` y columnas opcionales (fase 2); quién edita desde Contabilidad (decisión 4a) | Página + 2 funciones + columnas |
| 6 · Ingresos desde la Caja sin duplicar | Sí, en los libros por el asiento del día | `cash_reconciliation`, `tax_summary`, `sales_patterns`, `acct_post_days`, `order_search` (dueño) | Solo la pantalla (fase 1); tarjeta y SINPE por rango = `sales_by_method` (fase 2); lista de transacciones para el contador = decisión 4b | Página + 1 función |
| 7 · Compras unidas a proveedores e inventario | Sí, en Inventario (0012, 0029) | Lecturas de `purchase_orders/lines/receipts`, `po_history`, `po_receive_and_settle`, `po_receipt_settle`, `po_receipt_pay` | Vista desde Contabilidad (fase 1 para el dueño); `purchases_list` para el contador (fase 2, decisión 4a) | Página + 1 función |
| 8 · Reportes visuales | 8 reportes en tabla + ZIP | Todas las funciones de reporte e Información | Gráficos y comparaciones; `charts.js` compartido | Página |
| 9 · Identidad, bilingüe, tableta | Sí (tokens, `lang.js`), tableta regular | Todo | Diseño responsivo nuevo, entradas nuevas en el diccionario, pruebas a 820 px | Página |

Notas de vocabulario: el diccionario ya tiene 'New expense' → «Gasto nuevo» (el pedido dice «Nuevo gasto»: se cambia la
traducción o se agrega la clave) y ya existen 'Expenses', 'Purchases', 'Suppliers', 'Cost of sales', 'Average order', 'Received',
'Deliveries', 'Owed'; «Banco y efectivo», «Ingresos» (sección), «Agregar proveedor», «según la caja / estimado / en libros /
borrador / según documentos» y los textos de los cajones entran como pares nuevos.
La «Auditoría» de la sección Contabilidad necesita una función de lectura (hoy `audit_log` solo lo lee quien tiene áreas de
dueño; el contador no), o se arma desde las columnas de anulación y autor que los documentos ya traen.

Defectos pequeños encontrados de paso (se corrigen en la fase 1 sin tocar la base): clave `owner_only` duplicada en el
diccionario de errores de `accounting.html` (líneas 625 y 631: el aviso de la activación mostraría el texto de nómina), cinco
cadenas sin traducir («Balance», «Sales, no IVA», «Error», « · from {date}: », «X /h»), y en el flujo de efectivo una
reversión cae en «Otros movimientos» en vez de restar a su grupo (ajuste SQL opcional en 0034).

## F. Decisiones que necesito (antes de programar la fase 1)

1. **Quién registra gastos desde la nueva Contabilidad:** solo dueño con código y contador (la puerta de hoy) o también una
   tableta del café con PIN de encargado (el servidor ya lo permite para `expense_save`; cambiaría qué página aloja la pantalla y
   obligaría a tocar la puerta de `access.js`, que no se toca mientras E-05 no esté cerrado). *Recomiendo:* mantener la puerta de
   hoy en fase 1 y volver a esta opción después de E-05.
2. **Recurrencia:** recordatorio + formulario prellenado que una persona confirma cada vez (compatible con «sin automatizaciones
   inventadas» y con los meses cerrados) **o** asiento automático en la fecha (nueva automatización). *Recomiendo:* la primera.
3. **Gastos a crédito:** hoy un gasto «a crédito» no se puede pagar desde su pantalla (asiento manual). Opciones: (a) encaminar
   todo crédito a «factura de proveedor sin entrega» (pagadera y con antigüedad hoy, sin cambios de base; **pierde** el comprobante
   adjunto y la categoría de gasto salvo que se agregue a `supplier_invoices` una columna de adjunto y la factura lleve la cuenta
   de gasto en su línea) **o** (b) construir pagos sobre gastos (`expense_payments`, tabla pequeña + una función + mapeo a 2101:
   más código, pero el gasto conserva comprobante, categoría e historial). *Recomiendo:* (a) solo si acepta esas dos pérdidas;
   si no, (b) en la fase 3. Hasta decidirlo, «Registrar pago» no aparece sobre gastos a crédito.
4. **Qué ve y edita el contador** (hoy todo esto está detrás de «áreas de dueño»):
   - **4a · Proveedores y Compras:** lectura por funciones nuevas con `_ap_allowed` (`vendors_list`, `purchases_list`,
     `vendor_history`); alta y edición de proveedores solo dueño. *Recomiendo:* sí, en fase 2.
   - **4b · Transacciones de ventas (`order_search`) para el contador:** abrir esa función al contador cambia una guarda que hoy
     es «dueño o café»; es una decisión de privacidad operativa, no técnica. *Recomiendo:* no por ahora; el contador tiene los días
     y los totales.
5. **Fuente del panel hasta A-07:** titulares operativos («según la caja») con los libros como segunda lectura, o esperar a que
   el contador apruebe el catálogo. *Recomiendo:* operativo etiquetado, como Información.
6. **Período:** día de negocio de Costa Rica en toda la página (coincide con cierres y libros; Ventas hoy agrupa por reloj del
   aparato). *Recomiendo:* día de negocio.
7. **Pruebas:** página nueva en paralelo (las 22 pruebas actuales intactas; reescritura en fase 4) **o** reemplazar
   `accounting.html` desde la fase 1 (reescribir pruebas ya). *Recomiendo:* en paralelo.
8. **Quién abrirá la página:** cerrar E-06 (código en su ingreso personal del 31/08, desde su teléfono, cuando ningún aparato
   lo use) y/o E-18 (ingreso del contador) antes de publicar la fase 1; si no, la página queda publicada pero nadie entra.

Pendientes del contador que condicionan lo que se podrá mostrar como «final»: A-07 (catálogo y primer día de asiento), A-06 (tipo
de cambio y cuentas en dólares), A-01/A-04 (régimen de IVA y códigos CABYS), A-08 (reglas de nómina). Ninguno bloquea las
fases 1 y 2.

---

## Estado de construcción (2026-10-26, D-057)

Construido completo en la rama de desarrollo, **sin aplicar ni publicar** (condiciones en `docs/ACTIVACION-CONTABILIDAD.md`, E-37):

- **Página:** `website/contabilidad.html` + `contabilidad.js` + `charts.js`, con el diseño del prototipo (v5) y las ocho
  secciones. La ficha de Inicio y el enlace de Información abren la página nueva; `accounting.html` queda tal cual y se abre
  desde «Página de contabilidad anterior» (la planilla sigue allí).
- **Migraciones:** `0034_contabilidad_lecturas.sql` (lecturas, lo habitual por proveedor, gastos solo con la puerta de los
  libros) y `0035_contabilidad_gastos.sql` (pagos de gastos a crédito, cuentas recurrentes, interruptor de fotos). Reversión:
  `supabase/tools/reversion-0035.sql` y luego `reversion-0034.sql` (probadas: las funciones vuelven byte por byte a la 0033).
- **Diferencias respecto al prototipo:** (1) las fotos y archivos de recibos desde la página nueva esperan a E-17 detrás del
  interruptor `expense_receipt_photos` (Inicio → Ajustes); abrir un recibo existente sí se puede, y adjuntar desde la página
  anterior sigue igual. (2) El gasto recurrente que se registra desde el recordatorio lleva la fecha del día (el servidor no
  acepta fechas futuras), no la del vencimiento; si se anula, el recordatorio vuelve a ofrecer ese período. (3) «Pagar» de un gasto a crédito sale en la fila y en su detalle; en la ficha
  del proveedor los gastos a crédito abiertos se listan y se pagan desde Gastos. (4) El cobro por recibo (`order_search`) sigue
  siendo solo del dueño (decisión 4b).
- **Decisiones delegadas, como se aprobaron:** recurrencia = recordatorio + formulario prellenado; crédito = flujo completo
  registrar + pagar (opción b); contador lee proveedores, compras y contabilidad, no transacciones por recibo; panel con datos
  operativos etiquetados; día de negocio de Costa Rica; página en paralelo; solo Supabase; numeración 0034/0035 comprobada libre.
- **Pruebas:** SQL `410_contabilidad_lecturas` y `420_contabilidad_gastos` (guardas por tipo de cuenta, incluida la tableta del
  café con PIN que ya no registra gastos; doble partida; idempotencia; pagos; recurrencias; reversión y reaplicación);
  navegador `360_contabilidad` (puerta, secciones, gasto rápido con lo habitual y recibo, crédito, proveedores, banco,
  reportes y ZIP, libros, español/inglés, tableta y teléfono, red caída).

