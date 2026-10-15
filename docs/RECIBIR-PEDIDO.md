# Recibir pedido con factura y pago · diagnóstico y propuesta (2026-10-15)

Pedido del dueño: en **Inventario → Pedidos → Recibir**, registrar en un solo paso la recepción, la factura del
proveedor (foto, imagen o PDF, con lectura automática confirmable), el pago (efectivo de la caja, SINPE o
transferencia, tarjeta, crédito del proveedor; parcial o combinado) y lo que queda pendiente, sin tocar el resto
del sistema, sin duplicar asientos ni gastos, y sin activar ninguna contabilización automática global.

Estado: **aprobada por el dueño el 2026-10-15 e implementada en la rama de desarrollo** (D-041; sección 5). Nada
está aplicado en producción ni publicado: eso espera la aprobación explícita del dueño (E-25). Las referencias
`archivo:línea` de las secciones 1–3 son del código anterior (commit 415b476).

## 1. Lo que ya existe

| Pieza | Dónde | Qué hace hoy |
|---|---|---|
| La pantalla de pedidos | `website/inventory.html` 876–885 | Los cinco botones (+ Agregar línea, Compartir, Imprimir / PDF, Recibir, Cancelar pedido) y los estados borrador → enviado → recibido en parte → recibido. Un pedido queda abierto hasta que llega la mercadería |
| «Recibir» | `website/inventory.html` 418–430 y 973–1010; `supabase/migrations/0012_purchasing.sql` 81–136 | Cuadro con cada línea (pedido, ya recibido, esta entrega, costo por paquete, vence), Nº y fecha de la factura y «No llegará nada más». Llama a `po_receive_delivery`: entregas parciales, existencias y costo actualizados, una fila por entrega en `purchase_receipts`, misma factura del mismo proveedor rechazada, **repetir el envío no duplica** (el id de la entrega lo genera la página al abrir el cuadro), fila de auditoría. Requiere Inventario abierto con PIN de encargado (prueba `tests/sql/130_purchasing.test.sql` 50–51) |
| Facturas de proveedor y cuentas por pagar | `0016_payables.sql`; versión vigente en `0025_security_hardening.sql` 397–450 | `supplier_invoices` (número, fecha, **vencimiento**, monto sin IVA, IVA, entregas vinculadas), `supplier_invoice_save` (vincula las entregas, asienta el IVA acreditable y la diferencia de precio a 5103, rechaza la factura duplicada, repetir no duplica). Un dispositivo del café con PIN de encargado **ya puede** registrarlas (prueba `170_payables.test.sql` 13–17); anular solo el dueño con código o el contador |
| Pagos a proveedores | `0025_security_hardening.sql` 453–494 | `supplier_payment_save`: **pagos parciales**, aplicados a la factura elegida o a la más antigua, nunca más de lo que se debe, referencia, origen `cash` (caja fuerte), `petty` (caja chica), `bank` (banco o SINPE) o `payout` (dinero sacado de la gaveta) |
| Lo que se debe a cada proveedor | `0016_payables.sql` 223–240 | `ap_aging`: por proveedor, al día / 1–30 / 31–60 / más de 60 días. Visible con PIN de encargado, pero la página que lo muestra es Contabilidad |
| Dinero de la caja registradora | `0019_cash_movements.sql` 87–120 y 68–85 | `register_cash_move` (PIN de encargado, **caja abierta**, motivo): el efectivo esperado en la gaveta ya lo descuenta y el cierre lo cuadra; en libros queda en 1104 «Pagos de caja por documentar» hasta que un pago a proveedor lo documenta con `paid_from = 'payout'` y `payout_id`. Así el gasto no se cuenta dos veces |
| Archivos de facturas | `0015_receipts_package.sql` 15–45; `0025` 518–524; `website/accounting.html` 1085–1136 | Depósito privado `expense-receipts` **solo para gastos**: carpeta = id del gasto, un archivo por gasto, nadie borra ni reemplaza, se ve con un enlace firmado de 120 s; la cámara del teléfono con `capture="environment"`. No hay archivo para entregas ni facturas de proveedor. **Detalle que manda en el diseño:** el PIN de encargado viaja en un encabezado (`x-hg-unlock`) que solo ve PostgREST (`supabase/manager-mode.sql` 75–78 y `website/access.js` 32–42); Storage no lo recibe, así que hoy desde el ingreso del café con PIN **no se puede subir ni ver** un archivo: solo el dueño con código o el contador |
| Lectura de la factura | `website/accounting.html` 1228–1262 | La **factura electrónica de Hacienda (XML 4.3/4.4)** llena el formulario: número, fecha, montos, proveedor. No hay lectura de fotos ni PDF en ninguna página |
| Libros | `0013_ledger.sql` 353–358 y 258–296 | Las compras de insumos van a **Inventario 1150 contra Compras por pagar 2101 al costo**, en el asiento del día (no como gasto); el costo de lo vendido se reconoce por recetas al cerrar la caja. Ese asiento del día solo corre con `ledger_auto_post` = true (hoy apagado, A-07). La factura (IVA, diferencia de precio) y el pago asientan por su propia clave: nunca dos veces |
| Pruebas e infraestructura | `tests/sql/130, 170, 200`; `tests/e2e/specs/160, 180, 210`; `tests/e2e/gateway.js` 96–134 | Cubren entregas, facturas, pagos y retiros de caja. El gateway de pruebas **emula Storage** (subidas en memoria, enlaces firmados), así que subir un archivo se prueba en el navegador |

## 2. Lo que falta

1. **Todo está repartido en dos páginas.** Recibir está en Inventario; la factura, el pago y «lo que debo» están en
   Contabilidad, que el personal no abre. Hoy un encargado recibe y nadie registra la factura ni el pago hasta que el
   dueño entra a Contabilidad.
2. **Cuatro llamadas separadas** (entrega, factura, retiro de caja, pago): si una falla a medias, queda registro
   incompleto. Hace falta una sola operación que haga todo o nada y que repetirla no duplique.
3. **Métodos de pago:** no existe «tarjeta»; `cash` significa la caja fuerte, no la gaveta de la caja registradora.
4. **Archivo de la factura de una entrega:** no hay depósito ni columna; el de gastos exige un id de gasto.
5. **Lectura automática de fotos y PDF:** no existe; sí la del XML.
6. **Vencimiento por proveedor:** no hay plazo de crédito guardado (`vendors`, `supabase/inventory.sql` 34–46);
   `ap_aging` asume 30 días cuando la factura no trae vencimiento.
7. **Respaldo de los archivos privados:** el respaldo nocturno copia `menu-photos`; los depósitos privados esperan las
   llaves S3 (E-17). Aplica también al depósito nuevo.
8. **Pedido sin proveedor:** la página permite crear un pedido en blanco sin proveedor (`inventory.html` 891); una
   entrega así no se puede facturar ni pagar por cuentas por pagar (`supplier_invoice_save` exige que las entregas
   sean del proveedor de la factura).
9. **Id de la entrega por apertura del cuadro:** cada vez que se abre «Recibir» se genera un id nuevo
   (`inventory.html` 973); si la red falla a medias y la persona cierra y vuelve a abrir, puede guardar la misma
   entrega dos veces. Hoy solo el pedido ya cerrado está protegido.
10. **Historial corto:** «Pedidos recibidos» muestra 12 tarjetas, sin entregas, facturas ni archivos; las facturas
   de proveedor no se pueden leer directo desde la página (solo por `ap_aging`).
11. **Sin factura no hay pago:** `supplier_payment_save` rechaza pagar más de lo que se debe, y lo que se debe nace
   con la factura; un anticipo o un pago contra entrega sin factura no tiene camino hoy (la cuenta 1160 «Anticipos a
   proveedores» existe y nadie la usa). El pago «con retiro de caja» acepta un retiro vacío y no compara montos.
12. **Dos números de factura sin unir:** el que se escribe en «Recibir» (`purchase_receipts.invoice_no`) y el de la
   factura de proveedor (`supplier_invoices.number`) solo se unen cuando el contador vincula las entregas; nada
   comprueba que coincidan. Una entrega vacía (todo en 0) hoy pasa el pedido a «recibido en parte».

## 3. Propuesta

### 3.1 Base de datos · migración 0029 (solo agrega; la página de hoy sigue funcionando)

- **`po_receipt_settle(p_receipt_id, p_invoice jsonb, p_payments jsonb, p_manager_id, p_pin)`**: para una entrega ya
  guardada, registra la factura (número, fecha, vencimiento, monto sin IVA, IVA) y los pagos, **en una sola
  transacción**, llamando a las funciones existentes (`supplier_invoice_save`, `register_cash_move`,
  `supplier_payment_save`). Ids derivados del id de la entrega (la factura usa el mismo id; cada pago y el retiro de
  caja, un id calculado a partir de él): repetir devuelve lo ya guardado; cualquier error deja todo como estaba.
- **`po_receive_and_settle(p_po_id, p_lines, p_receipt_id, p_final, p_invoice, p_payments, p_manager_id, p_pin)`**:
  `po_receive_delivery` + `po_receipt_settle` en la misma transacción. Es lo que llama el botón «Confirmar recepción».
  Como las funciones de hoy devuelven `{ok:false, error}` en vez de fallar, la envoltura **lanza el error** para que
  Postgres deshaga todo (entrega, factura, retiro y pago) y luego lo devuelve a la página con el mismo formato. El
  número de factura queda **uno solo**: la envoltura escribe el mismo número en la entrega y en la factura de
  proveedor y las une en el acto. Una entrega con todo en 0 se rechaza salvo que diga «No llegará nada más».
- **Quién puede:** el mismo nivel de hoy, un encargado con PIN (recibe, registra factura y pago); anular sigue
  siendo del dueño con código o del contador. Si prefiere que el dinero exija el código del dueño, es un cambio de
  una línea.
- **Reglas del pago:** la suma de los pagos no pasa del total de la factura; el saldo queda en cuentas por pagar con
  su vencimiento. «Efectivo de caja registradora» exige el **PIN del encargado y la caja abierta**: crea el retiro
  (`payout`, motivo «Pedido Nº … · proveedor») y el pago `from_payout`, así el esperado de la gaveta baja y el
  cierre cuadra, y el gasto no se cuenta dos veces. «SINPE / transferencia» → `bank` con referencia. «Tarjeta» →
  valor nuevo `card` con mapeo contable `from_card` (por defecto la cuenta de banco 1110; el contador puede apuntarlo
  a una cuenta de tarjeta de crédito desde Contabilidad, como el resto de mapeos). «Crédito del proveedor» → sin
  pago; la factura queda abierta con vencimiento. El pago se aplica **a esta factura** (no a las más viejas del
  proveedor), el retiro de caja se crea siempre con su id y por el mismo monto que el pago, y la factura se guarda
  **antes** del pago en la misma transacción (sin factura no se puede pagar).
- **Mercadería pagada con dinero de la caja pero todavía sin factura:** se guarda la entrega y el retiro de caja
  (`payout`, que queda «por documentar» en 1104, como hoy en el POS); la factura y el pago se registran después
  desde el historial y documentan ese retiro. Pagos por banco o tarjeta sin factura no se admiten: se registran
  cuando llegue la factura.
- **Costos completos y sin IVA:** si alguna línea recibida no tiene costo, el cuadro lo pide antes de registrar la
  factura (un costo en cero inflaría la diferencia que va a 5103). El cuadro dice en claro que «Costo / paquete» va
  **sin IVA** (hoy no lo dice): el inventario y el costo promedio se llevan sin IVA, y el IVA entra solo por la
  factura. Un pago combinado se guarda como **una fila de pago por método**, todas aplicadas a esta factura.
- **Comprobante sin número** (un tiquete del mercado): la factura se registra con «S/N» más la fecha y el id corto
  de la entrega, para que el pago tenga contra qué aplicarse; el dueño o el contador lo corrigen si llega el número.
- **`vendors.tax_id`** (opcional, cédula del proveedor): permite que el XML de Hacienda encuentre al proveedor por su
  cédula y no solo por el nombre exacto.
- **Factura opcional en la entrega.** Si la mercadería llega sin factura, se recibe como hoy y la factura y el pago
  se agregan después desde el historial del pedido con `po_receipt_settle`.
- **Archivo (en su propia migración, 0030, para que un fallo de permisos de Storage no detenga la 0029):**
  depósito privado `purchase-invoices`; columna `purchase_receipts.document_path`;
  `purchase_doc_attach(p_receipt_id, p_path)` (una sola vez, ruta `<id de la entrega>/<archivo>`); sin borrar ni
  reemplazar (el mismo patrón de `expense-receipts`; las reglas leen la carpeta con `split_part`, como la 0025, porque
  las funciones `storage.foldername…` no existen en la base de pruebas). **Permiso sin encabezado:** como Storage no ve el PIN, la regla
  nueva `_login_unlocked()` acepta al dueño con código, al contador, o un ingreso que tenga **un desbloqueo con PIN
  vigente** (fila en `access_unlocks` del mismo ingreso, de encargado o dueño, no vencida); subir, además, solo en la
  carpeta de una entrega de las últimas 24 horas que aún no tiene archivo. Las dos políticas se escriben en las
  formas exactas que acepta `tests/lint.sh` (una línea `create policy … on storage.objects …`, un
  `insert into storage.buckets … on conflict …`), como la 0015 y la 0025. El depósito nace con **límite de tamaño
  (10 MB) y de tipos (imagen y PDF)** en esa misma línea, cosa que el de gastos no tiene. Se admiten **hasta 3
  archivos por entrega** (una factura de varias páginas fotografiada hoja por hoja): tabla `purchase_receipt_files`
  en lugar de una sola columna. **Por qué un depósito nuevo y no el de gastos:** reutilizar `expense-receipts`
  obligaría a ampliar quién puede ver las facturas de gastos (la regla de lectura es de todo el depósito), y el
  dueño pidió no tocar otras secciones. El costo del depósito nuevo es la lista de lugares que lo deben conocer:
  `release-check.sql`, `production-snapshot.sql`, `tests/rehearsal/compare.py`, `anonimizar.sql` y `ensayo.sh` (los
  nombres de archivo pueden llevar el nombre del proveedor), `ops/backup/backup.sh` (`PRIVATE_BUCKETS`, con copia
  que el dueño vuelve a subir al repositorio privado) y `docs/RESPALDOS.md`. Hasta que existan las llaves S3
  (E-17) ningún depósito privado entra en el respaldo nocturno.
- **Lo que toda migración nueva debe actualizar** (la CI lo exige): `release-check.sql` (serie de migraciones y lista
  de funciones), las listas conocidas de `production-snapshot.sql` (`tests/tools/snapshot-known.sh`), y los textos
  «0000–0028» de `tests/rehearsal/run.sh`, `compare.py`, `compare-selftest.py`, la prueba de páginas en vivo y
  `docs/PRUEBAS.md`.
- **Proveedor obligatorio** para registrar factura o pago: si el pedido no tiene proveedor, el cuadro pide elegirlo
  antes (se guarda en el pedido).
- **Id de la entrega por pedido, no por apertura:** la página guarda el id en el dispositivo hasta que el servidor
  confirma, así cerrar y volver a abrir el cuadro después de una falla no duplica la entrega.
- **`vendors.credit_days`** (opcional): plazo del proveedor para prellenar el vencimiento. También opcional:
  `purchase_receipts.location_id` (D-021) y ofrecer «Efectivo de la caja fuerte» (origen `cash`, que ya existe en
  Contabilidad) como quinto método.
- **`po_history(p_po_id)`**: entregas con su factura, pagos, saldo y archivo, para el historial del pedido (las
  facturas de proveedor no se leen directo desde la página; esta función las entrega solo para ese pedido y con
  Inventario abierto). El historial deja de cortarse en 12 tarjetas: búsqueda por proveedor y mes.
- `supabase/tools/release-check.sql`: funciones nuevas y migraciones 0–29 como obligatorias; el depósito y sus
  políticas (0030) se reportan aparte, como opcionales, hasta que el dueño la aplique.

### 3.2 Página Inventario · solo la sección Recibir y el historial del pedido

- Los cinco botones y el cuadro actual **quedan iguales**. Debajo de las líneas se agrega una sección plegable
  **«Factura y pago»**: proveedor, total del pedido (sin IVA, lo que ya se calcula), archivo (botón de cámara en
  teléfono o iPad, o imagen, PDF o XML), «Leer la factura» que prellena número, fecha, subtotal, IVA y total y dice
  de dónde salió cada dato; todos los campos editables; comparación entre el subtotal de la factura y lo recibido
  (la diferencia va a 5103 como hoy); pagos en líneas (método, monto, referencia; «Agregar otro pago»); **Total de
  la factura · Pagado · Saldo pendiente · Fecha de recepción · Vencimiento**; el PIN del encargado solo si hay
  efectivo de la caja; botón **«Confirmar recepción»**.
- Las fotos se **reducen en el dispositivo** antes de subirlas (lado mayor 1 600 px, JPEG): una foto de iPad pesa
  5–12 MB y bastan 300–600 KB para leer una factura.
- Dos botones, **«Tomar foto»** y **«Elegir archivo»** (uno solo con `capture` abre la cámara y no deja elegir un PDF
  en los teléfonos). El nombre del archivo en el depósito se deriva del id de la entrega y de la página (1, 2, 3), así
  un reintento que encuentra el archivo ya subido sigue adelante y lo registra en vez de fallar.
- Después de guardar se sube el archivo; si la subida falla (sin internet), el historial muestra «Adjuntar factura».
- «Ver factura» abre el archivo con un enlace firmado de dos minutos en un enlace preparado de antemano (no con
  una ventana emergente, que el iPad suele bloquear).
- «Efectivo de caja registradora» aparece deshabilitado, con el motivo, cuando **no hay un día de caja abierto**
  (regla de `register_cash_move`): entonces se paga por otro método o queda pendiente.
- Una factura que cubre todo el pedido cuando solo llegó una parte: el cuadro avisa la diferencia y ofrece
  **registrar la factura en la última entrega** (la función une varias entregas a una factura, `receipt_ids`);
  la comparación siempre es subtotal de la factura contra el costo de las entregas que une.
- **Historial del pedido:** cada entrega con su factura, pagos, saldo y «Ver factura».
- **Panel «Por pagar a proveedores»** en Pedidos: lo que se debe a cada uno (`ap_aging`) y «Registrar pago» con los
  mismos métodos, para las facturas pendientes.
- Textos como el resto del sitio: inglés en la página, español en `website/lang.js`. Diseño con las clases que ya
  usa la página (`.modal`, `.row`, `.tablewrap`, `.pill`, `.hint`, `.err`).
- La página nueva sin la 0029 cae al flujo de hoy («Agregar a existencias»); la página vieja con la 0029 sigue igual.

### 3.3 Lectura automática de la factura

| Fuente | Herramienta | Costo | Confiabilidad | Recomendación |
|---|---|---|---|---|
| XML de Hacienda (factura electrónica) | el analizador que ya existe en Contabilidad | ninguno | exacta | **sí**, primero |
| PDF digital (con texto) | pdf.js (Mozilla) desde el mismo CDN del que ya se carga supabase-js, versión fija, más patrones para Nº, fecha, subtotal, IVA y total | ninguno | buena en facturas generadas por sistema; nula en PDF escaneados | **sí** |
| Foto de factura o tiquete | tesseract.js (OCR en el navegador, español) desde el mismo CDN; descarga de unos megas la primera vez, después queda en caché; varios segundos en un iPad | ninguno | **irregular**: un tiquete térmico arrugado o con poca luz suele leerse mal; se prellena solo lo que encuentra | **sí, como ayuda**, nunca sin confirmar |
| Modelo de visión (Claude, Google Document AI u otro) en una Edge Function de Supabase | servicio externo; la llave queda en Supabase, nunca en el repositorio | **centavos por factura** | alta, también en fotos malas | **solo con su autorización**, después de medir cuánto acierta lo gratuito |

En todos los casos la regla es la misma: **los datos leídos se muestran, se corrigen y se confirman antes de
guardar**; nada entra a libros sin esa confirmación. Los tamaños y tiempos del OCR son conocimiento general, no se
midieron en este repositorio.

Detalles que fijan el diseño de la lectura:

- El analizador del XML vive dentro de `accounting.html`; Inventario recibe **una copia** en su propia página (la
  de Contabilidad no se toca); unirlas en un archivo compartido queda para después. El XML da los **totales**
  (neto, IVA, total, otros cargos), no las líneas: la comparación es contra el total del pedido, no línea por línea.
- Las librerías de lectura se cargan **solo cuando alguien toca «Leer la factura»** (versión fija, el mismo CDN que
  ya usa el sitio); si el CDN no responde, el cuadro sigue funcionando y se escribe a mano. Hoy las páginas del
  personal ya dependen de ese CDN para `supabase-js`.
- Meta del OCR en fotos: leer primero lo que tiene **forma fija** (la clave de 50 dígitos, el consecutivo de 20, la
  fecha y el total); lo demás se escribe. Es mucho más fiable en papel térmico que intentar todos los campos. La
  foto se reduce en el dispositivo antes de leerla (misma reducción que para subirla), para no agotar la memoria
  de la tableta.
- pdf.js lee solo el texto del PDF: un PDF escaneado o hecho con una foto da «no se encontró nada» y se escribe a
  mano (en esta versión no se encadena OCR sobre el PDF).
- La opción con costo necesita además lo que hoy no existe: una Edge Function en Supabase (no hay ninguna, ni
  herramienta en la CI para desplegarla) y una llave del servicio guardada por usted en Supabase, nunca en el
  repositorio. Por eso es la última opción y solo con su autorización.

### 3.4 Contabilidad

- No se activa nada: `ledger_auto_post` sigue como esté. Las compras siguen entrando a **inventario** (1150 / 2101)
  en el asiento del día, no como gasto; la factura asienta su IVA y la diferencia de precio; el pago descarga la
  cuenta por pagar contra caja fuerte, caja chica, banco, tarjeta o el retiro de caja (1104). Todo con las funciones
  de hoy.
- No se adelanta el asiento de la compra (Inventario 1150 / Por pagar 2101) al momento de recibir: seguiría siendo el
  asiento del día, como decidió D-014; hacerlo inmediato sería activar contabilización, y eso es del contador.
- **Correcciones:** una entrega mal recibida no se borra ni se deshace (no existe «anular entrega»): se anula el pago
  (dueño con código o contador), luego la factura, y las existencias se corrigen con un ajuste o un conteo, como
  hoy. Un «anular entrega» con su contra-movimiento queda fuera de este alcance; se puede proponer aparte.
- Sin duplicados: ids derivados del id de la entrega; cada asiento tiene su clave (`source_key`); repetir devuelve lo
  ya guardado; reabrir un pedido recibido no muestra «Recibir».
- **Nota para el contador (no cambia con esto):** mientras `ledger_auto_post` esté apagado, las facturas y los pagos a
  proveedores sí asientan (0016/0019) y las compras al costo no (van en el asiento del día). Es el diseño vigente
  desde la 0016: se cuadra cuando el contador apruebe el catálogo (A-07) o con su asiento de apertura.

### 3.5 Pruebas (antes de cualquier pedido real)

- SQL `320_receive_settle.test.sql`: recepción con factura y pago combinado (efectivo de caja + crédito); el mismo id
  dos veces guarda una vez; pago mayor que la factura rechazado; caja cerrada rechazada; PIN equivocado; tarjeta;
  factura después de la entrega; políticas de Storage (carpeta ajena, segundo archivo, borrar); el esperado de la
  gaveta y la conciliación; `ap_aging` y un pago posterior; fecha futura y mes cerrado por el contador
  rechazados; retiro con otro monto rechazado; pago aplicado a esta factura y no a una más vieja; `release-check` sin
  faltantes. Políticas de Storage probadas en SQL como se hace con el resto de reglas (hoy la del depósito de gastos
  solo se comprueba por su texto).
- Navegador `290_receive.spec.js`: el cuadro completo en tableta en español **con el ingreso del café y el PIN de
  encargado** (hoy todas las pruebas de Inventario entran como dueño con código, y ese es el caso real del café);
  XML que prellena; adjuntar y ver; doble clic en «Confirmar»; historial del pedido; «Por pagar» y pago desde
  Inventario; el cierre de caja con el retiro. Las librerías de lectura (pdf.js, tesseract.js) se sirven desde la
  carpeta de pruebas, no desde internet, con versión fija; el OCR se prueba con una imagen pequeña o se omite en la
  CI si alarga la corrida (tope de 40 minutos).
- Ensayo: el camino recibir + factura + pago también corre sobre la copia con forma de producción
  (`tests/rehearsal/after-window.sql`) y sobre el café vacío (`reset-pages`), no solo en la base sintética.
- Numeración: SQL `320` (0029) y `330` (0030, Storage); navegador `290`.
- `tests/lint.sh` gana una regla: toda etiqueta `<script src="https://…">` debe estar en una lista de direcciones
  permitidas con versión fija (hoy nada revisa el origen de los scripts externos).
- `tests/run.sh` completo (lint, SQL, respaldo, ensayo con la 0029 sobre la copia de producción, navegador) y la
  CI en verde antes de cada commit.

### 3.6 Entrega y aprobaciones

Rama `claude/hanging-garden-coffee-proposal-1m8zd4` (PR #1). Necesitan **su aprobación explícita**:

1. La migración **0029** en producción (después del «Ensayo en pruebas» en verde con esa versión y un respaldo).
2. La publicación de la versión del sitio con la página nueva (etiqueta `v…`, flujo manual).
3. Cualquier servicio con costo para leer facturas (sección 3.3, última fila).
4. El método «tarjeta» y su cuenta por defecto (que el contador confirme el mapeo).
5. Opcional: `vendors.credit_days`, `purchase_receipts.location_id`, el método «caja fuerte».
6. La 0030 (Storage) se aplica después de la 0029 y puede esperar: sin ella todo funciona menos adjuntar el archivo.

## 4. Preguntas (bastan respuestas cortas)

1. ¿Quién paga normalmente al proveedor en la entrega: el encargado con dinero de la gaveta, o usted por SINPE?
   (Define qué método aparece primero.)
2. ¿«Tarjeta» es la tarjeta de débito de la cuenta del banco, o una tarjeta de crédito del negocio? (Define la cuenta
   contable por defecto.)
3. ¿Hay facturas de proveedor en dólares? (Hoy todo el módulo de proveedores trabaja en colones.)
4. ¿Con qué aparato se fotografiará la factura al recibir: las tabletas Android del café, el iPad, o el teléfono de
   quien recibe? (Decide el peso aceptable de la lectura automática y las pruebas que se hacen.)
5. ¿Sus proveedores le mandan la factura electrónica (XML) al correo del café, y qué parte son informales (feria,
   productores sin factura electrónica)? (Decide cuánto resuelve la lectura exacta y gratuita del XML.)

## 5. Decisiones del dueño y lo implementado (2026-10-15)

**Decisiones (mensaje de aprobación):** 1) los pagos los registra un encargado autorizado con su PIN; 2) tarjeta de
débito y tarjeta de crédito como métodos separados; 3) facturas en colones y en dólares, con el tipo de cambio
anotado; 4) la factura se fotografía desde cualquier teléfono o iPad autorizado; 5) el XML de Hacienda se acepta
cuando exista, sin ser obligatorio. Además: una recepción puede quedar con la factura **pendiente** (no llegó) o
**por revisar** (capturada, sin confirmar) sin perder la mercadería recibida; el sistema señala lo pendiente y no
registra impuestos ni pagos sin confirmar. Las cinco opciones del pedido y el diseño se conservan.

**Lo que trae esta versión (detalle en `docs/DECISIONS.md`, D-041):**
- `supabase/migrations/0029_recibir_pago.sql` (solo agrega) y `0030_facturas_archivo.sql` (Storage, opcional).
- `website/inventory.html`: en **Recibir**, la sección «Factura y pago» (estado de la factura, foto / archivo / XML,
  «Leer la factura» con corrección a mano, moneda y tipo de cambio, subtotal e IVA frente al costo recibido, uno o
  varios pagos, encargado y PIN); la tarjeta «Pendiente con proveedores»; «Detalles» en los pedidos recibidos
  (entregas, factura, pagos, retiro de caja, archivos, adjuntar, registrar la factura, registrar un pago); búsqueda de
  pedidos recibidos por proveedor y mes. `website/accounting.html` solo nombra los dos métodos de tarjeta;
  `website/lang.js` trae los textos en español.
- Pruebas: SQL `320_receive_settle` (83) y `330_purchase_docs` (31), `240_release_check` ampliada; navegador
  `290_receive` (4 escenarios); ensayo de migraciones con 0029 y 0030; `anonimizar.sql`, `backup.sh` y `ensayo.sh`
  del kit privado actualizados (E-26).

**Cómo funciona el dinero:** un pago en efectivo de la caja es un retiro (`payout`) del día abierto, con PIN, igual
que en el POS; si la factura todavía no está, queda anotado en la entrega y se documenta al confirmar. Bancos y
tarjetas solo con la factura confirmada. Confirmar asienta la factura como hasta hoy (IVA a 1140, diferencia de
precio a 5103, proveedor en 2101) y cada pago desde su cuenta (1104 caja, 1110 banco, 2120 tarjeta de crédito).
Todo lo de una recepción se guarda en **una** transacción con el id de la entrega: un doble toque o un reintento no
duplica nada, y un rechazo (caja cerrada, PIN malo, pago mayor que la factura, factura repetida) no guarda nada.

**Límites (ver también D-041):** las versiones de las librerías de lectura se fijaron sin poder alcanzar el CDN
desde el entorno de desarrollo (E-27 las comprueba; si una falta, solo se apaga «Leer la factura» y se escribe a
mano); la lectura de fotos descarga su modelo en español la primera vez en cada aparato; una factura en dólares se
paga en colones al tipo de cambio de la factura (sin diferencia cambiaria hasta A-06); desde esta página no se anula
una entrega ni una factura confirmada (reversiones desde Contabilidad); máximo 3 archivos de 10 MB por entrega, sin
reemplazo ni borrado.

**Pasos para aprobar el despliegue (en este orden; nada de esto lo ejecuta el desarrollo):**
1. Revisar la rama `claude/hanging-garden-coffee-proposal-1m8zd4` (PR #1) con CI en verde y responder «apruebo».
2. «Ensayo en pruebas» con esa versión: destino `desechable`, vaciar `no`, **reinicio `no`** (producción ya pasó la
   ventana); debe terminar en verde aplicando 0029 y 0030 (docs/PRUEBAS.md).
3. «Respaldo inmediato» en verde (y, si ya se resolvió, la llave privada de E-24 confirmada).
4. SQL Editor, fuera de horario: pegar `0029_recibir_pago.sql` → *Success*; luego `0030_facturas_archivo.sql` →
   *Success* (si dice "must be owner of table objects", parar ahí: todo funciona menos adjuntar el archivo).
5. `supabase/tools/release-check.sql`: `migrations_optional_missing` = `[]`, `purchase_upload_rule_current` = `true`,
   `functions_missing` = `[]`.
6. Crear la etiqueta `v…` sobre el commit aprobado y correr «Publish website (PRODUCTION · manual only)»
   (docs/PUBLICAR.md). Recargar Inventario en una tableta: debe aparecer «Pendiente con proveedores».
7. Subir a `canopy-respaldos` los tres archivos de `ops/backup/repositorio-respaldos/` (E-26) y comprobar las dos
   direcciones de las librerías (E-27); pedir al contador la confirmación de las cuentas de tarjeta (A-12).
