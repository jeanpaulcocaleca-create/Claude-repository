# Activar Proveedores (D-067, migraciones 0039 y 0040) · E-43

Esta guía la sigue el dueño, paso a paso. Claude preparó y probó todo en desarrollo, en la base de pruebas local;
**no aplicó nada en producción ni publicó nada**. Cada paso que cambia producción lo hace usted, cuando lo decida. Las
reglas del repositorio (`CLAUDE.md`) no me dejan publicar, crear etiquetas `v*` ni tocar la base de producción. Pégueme
cada resultado que pide la guía y yo lo compruebo antes de que siga.

**Qué se activa:** la página nueva **Proveedores**, que reúne lo que hacían Inventario → «Pedidos» e Inventario →
«Proveedores» y agrega lo que faltaba: el catálogo de cada proveedor, pedir con casillas, el documento del pedido
(Copiar, PDF, Imprimir), recibir por **cualquier persona en turno sin otro PIN por entrega** («Recibe en este aparato»:
su propio PIN en ese aparato, que vale 15 minutos), las
facturas, los pagos por **SINPE** (con su número de confirmación) o **tarjeta**, antes o después de recibir, y las
alertas de inventario bajo que abren al proveedor preferido. Llegan con las migraciones **0039** y **0040**, que se
pegan una después de la otra en la misma noche. La Caja, la Cocina, el menú QR, la TV, las pantallas y los descuentos
quedan byte por byte como en la versión publicada hoy (`v2026.11.04-1`); de lo compartido solo cambian el diccionario
(`lang.js`, con los textos nuevos) y `config.js` (la dirección nueva). Lo comprueba «Tests» en cada ejecución.

| Pieza | Qué hace | Archivo |
|---|---|---|
| 0039 · Proveedores, 1 de 2 | El catálogo de cada proveedor (presentación, unidades por presentación, precio habitual sin IVA, código; un artículo puede venir de varios proveedores; el preferido sigue siendo el proveedor del artículo en Inventario), borradores de pedido, pedidos con número y versión, edición con historial, cancelar, cerrar lo pendiente; la recepción por línea (lo pedido, lo recibido, el precio), entregas parciales, nunca dos veces, correcciones como entregas nuevas; «Recibe en este aparato» (la sesión de turno que el servidor revisa en cada llamada: su propio PIN en ese aparato, que vale 15 minutos y que cada entrega extiende; después, su PIN otra vez); las alertas con la regla de siempre; nadie deja un saldo a favor del café sin el nivel de dueño. Siete tablas nuevas, columnas nuevas en `purchase_orders`, `purchase_lines`, `purchase_receipts` y `supplier_payments`, siete disparadores y 56 funciones nuevas (17 que llama la página, 39 internas). Copia al catálogo el proveedor de cada artículo y lo pedido antes, **solo en tablas nuevas**. Ninguna función, regla ni registro existente cambia | `supabase/migrations/0039_proveedores.sql` |
| 0040 · Proveedores, 2 de 2 | Lo que lee la página (la lista, la ficha, el pedido, lo que falta por recibir, el historial; a quien está en turno solo lo que necesita para recibir), las facturas desde Proveedores (por `supplier_invoice_save`, como siempre), los pagos por SINPE o tarjeta y su aplicación a las facturas, el estado de pago de cada pedido. Revisa que la cuenta **1160 «Anticipos a proveedores»** exista (está en el plan aprobado desde la 0013) y le agrega dos mapeos; la regla `supplier_payments_paid_from_check` acepta además `'advance'` (los pagos aplicados). 23 funciones nuevas (11 que llama la página, entre ellas la bitácora de Proveedores para Contabilidad; 12 internas) y dos disparadores de última defensa (una factura nunca recibe aplicaciones por más de su total; un pago de Proveedores nunca se aplica por más de su monto). **Tres funciones existentes cambian**: `supplier_invoice_save` (la que guarda toda factura de proveedor, también desde Contabilidad y la página anterior) toma primero los pedidos de esas entregas y lleva con su entrega una corrección de Proveedores todavía sin factura; y, por su corrección del 2026-11-07, `supplier_payment_save` (la que registra todo pago a proveedor en Contabilidad y en la página de Inventario anterior) aplica primero lo pagado en Proveedores a las facturas de ese proveedor, solo acepta lo que se debe después y niega un número SINPE ya registrado en Proveedores, y `expense_pay` niega ese número en el pago por banco de un gasto; lo demás lo hacen igual, y la reversión les devuelve su texto exacto de la 0025, la 0029 y la 0035 (decisión 8). Ningún registro existente cambia | `supabase/migrations/0040_proveedores_pagos.sql` |
| La página Proveedores | El centro (alertas, proveedores, por recibir), la ficha de cada proveedor (Pedir, Pedidos, Pagos, Productos), el documento del pedido, la recepción, las ventanas de pago, de factura, de corrección y de anulación | `website/proveedores.html`, `website/proveedores.js`, `website/lang.js` |
| Inventario | Las pestañas «Pedidos» y «Proveedores» llevan a Proveedores; desaparecen «Pedido sugerido» y «Crear todos los pedidos»; «Pedir a proveedores →» y un «Pedir» en cada fila de «Antes de que se acabe»; «Proveedores» en el menú de arriba. Existencias, Recetas, Historial y Por mes no cambian | `website/inventory.html` |
| Inicio | El recuadro «Proveedores»; las filas de «Antes de que se acabe» abren al proveedor; «Pedir a proveedores» junto a «Abrir inventario» | `website/home.html` |
| Reloj de marcas | Solo el enlace «Proveedores» arriba; las marcas no cambian | `website/time.html` |
| Contabilidad | «Abrir en Proveedores →» en Compras, «Abrir en Proveedores» en la tarjeta del proveedor, el aviso de las facturas en dólares, el nombre «Pago aplicado (Proveedores)»; al guardar una factura, y antes de registrar un pago, aplica primero lo pagado en Proveedores (desde su corrección del 2026-11-07, el servidor lo hace por su cuenta en todo pago, decisión 8); anular un pago de Proveedores ya aplicado pide confirmación; la pestaña «Auditoría» muestra también la bitácora de Proveedores (decisión 8) | `website/contabilidad.js` |
| Dirección de la página | `proveedores.html` entre las páginas del personal (la protección de D-005) | `website/config.js` |
| Herramientas del dueño (SQL Editor) | `release-check.sql` (serie hasta la 40 y las 28 funciones nuevas), `production-snapshot.sql` (las funciones y disparadores de la 0039 y la 0040), `consistency-check.sql` (ocho revisiones nuevas de Proveedores, cada una debe dar 0) | `supabase/tools/` |
| Ensayo | `anonimizar.sql` conoce las columnas nuevas (el SINPE se vacía, las referencias de pago se reemplazan, las sesiones de turno se vacían) | `ops/backup/repositorio-respaldos/anonimizar.sql` |
| Reversión | Primero la 0040 y luego la 0039: quitan solo sus funciones y disparadores y devuelven a su texto anterior las tres funciones que la 0040 redefine; no borran ningún dato | `supabase/tools/reversion-0040.sql`, `supabase/tools/reversion-0039.sql` |

**No incluye (y no se enciende con esta guía):** pagos en **efectivo** en Proveedores (decisión 2: el efectivo sigue en
Contabilidad, como hoy); enviar el pedido por WhatsApp o correo desde el sistema (se copia o se manda el PDF a mano);
fotos, archivos o lectura automática de facturas (D-042: la factura se escribe a mano); la aceptación de comprobantes
electrónicos de Hacienda (A-02, A-10); ninguna regla de IVA (lo que se calcula antes de la factura es solo un tope, A-15);
la recepción sin pedido de Inventario → Existencias → «Recibir», que se queda como está (decisión 4); las alertas de la
etapa 3 de recetas (por ventas y merma, CHECKLIST fila 119); ningún cambio de ingresos, PIN ni permisos fuera de
Proveedores (E-05 y E-06 siguen como están); la ventana anterior de descuentos, que retira una migración posterior
cuando usted lo decida (Q5, D-066).

**La versión:** el último commit de la rama `claude/proveedores`, con «Tests» en verde (PR #8, en borrador): el que le
paso en el chat, con su código completo, cuando le pida aprobarlo (1.1). **Punto de partida y de regreso:** la base en
la 0038 y el sitio en `v2026.11.04-1` (commit `9d3f6ad`, `gh-pages` `77a5fb1`).

**Qué se probó (en desarrollo, nunca en producción):** las pruebas SQL `510_proveedores_catalogo`,
`511_proveedores_pedidos`, `512_proveedores_recibir`, `513_proveedores_turnos`, `514_proveedores_pagos`,
`515_proveedores_alertas`, `516_proveedores_lecturas`, `517_proveedores_saldo_favor`, `518_proveedores_revision`,
`520_reversion_0039` y `525_reversion_0040` (799 comprobaciones),
las pruebas con dos conexiones a la vez (`tests/sql/concurrency-proveedores.sh`, 30 comprobaciones: dos entregas del
mismo pedido a la vez, el mismo pago dos veces, el mismo SINPE para dos proveedores, un pago y una entrega del mismo
pedido, una entrega y una venta de los mismos artículos, y un pago por banco de Contabilidad y un SINPE de Proveedores
del mismo pedido en el mismo instante), las de navegador de la página nueva (`410_proveedores_centro`,
`411_proveedores_pedir`, `412_proveedores_documento`, `413_proveedores_recibir`, `414_proveedores_pagos` y
`415_proveedores_aparatos`: 68 pruebas), las de compras y recepción de antes rehechas sobre Proveedores (`160`, `290`) y
toda la batería de «Tests» (en desarrollo, el 2026-11-07, después de las dos correcciones del dueño: 68 de 68 archivos de pruebas SQL y 383 de 383 pruebas de navegador),
con el ensayo de las páginas publicadas hoy (`77a5fb1`, su pestaña «Pedidos» incluida) sobre una copia con la 0039 y la
0040.

**Qué no se pudo probar en desarrollo y qué riesgo queda:**
- **El iPad con Safari y su hoja de compartir.** Las pruebas de navegador corren en Chromium, con pantalla táctil y
  tamaños de teléfono, tableta y computadora simulados. El riesgo: que en el iPad el PDF se comparta o se vea distinto, o
  que un toque se comporte diferente. Lo cubre la etapa 1.4 (la vista previa en el iPad) y la 5.F.
- **Una impresora real.** La prueba comprueba una sola hoja A4 sin menús en la vista de impresión de Chromium. El riesgo:
  márgenes o una segunda hoja en la impresora del café. Lo cubre la 5.F (ver la vista previa y cancelar).
- **El ensayo sobre la copia de producción.** Solo usted lo corre (CLAUDE.md). El riesgo: datos de producción que el
  ensayo de desarrollo no tiene. Lo cubren las etapas 1.3 y 3.10.

**En orden:**

| Etapa | Qué | ¿Toca producción? | Cuándo | Tiempo |
|---|---|---|---|---|
| 0 | Qué cambia para el personal: leerlo y avisar al equipo | No | Antes de todo | 20 min |
| 1 | Antes: pruebas, archivo del ensayo, ensayo, vista previa, **sus decisiones** | No | Días antes o el mismo día | 1–2 h |
| 2 | La etiqueta y sus pruebas | No | El día de la activación, entre las 05:00 y las 23:00 | 35 min |
| 3 | Después del cierre: respaldo, fotos, la 0039, la 0040 y sus comprobaciones | Sí (la base) | Café cerrado, desde las 19:30 | 30 min |
| 4 | **Primero guardar el sitio de hoy**, después publicar | Sí | Seguido de la etapa 3 | 20 min |
| 5 | Comprobaciones en el café, sin pedidos, entregas ni pagos de prueba | No | Seguido de la etapa 4, y al día siguiente | 15 min |
| 6 | Vuelta atrás (solo si la necesita) | Sí | Antes de abrir el café | 10–20 min |

Monteverde está en UTC−6 todo el año: a las 19:45 del día D en Monteverde son las 01:45 UTC del día D+1. La etiqueta
lleva la fecha D; los registros en UTC llevan D+1. Para las horas use la que da la base, no el reloj de la computadora.

**Detenga y avíseme** si algo sale distinto de lo que dice la guía: copie el resultado (texto o captura sin PIN ni
contraseñas) y no siga.

---

## 0 · Qué cambia para el personal

Léalo al equipo antes de publicar. Hasta que publique (etapa 4), Inventario sigue exactamente como hoy.

**Una página nueva: Proveedores.** Se abre desde Inicio (el recuadro «Proveedores», «Pedidos, recepción y pagos a
proveedores»), desde Inventario (las pestañas «Pedidos» y «Proveedores» llevan ahí) y desde el menú de arriba de
Inventario y del Reloj (en la Caja: «Reloj» → «Proveedores»). La guía completa de la página está en `docs/PROVEEDORES.md`.

**En Inventario:**
- las pestañas «Pedidos» y «Proveedores» ya no se abren dentro de Inventario: llevan a Proveedores. **Desaparecen
  «Pedido sugerido» y «Crear todos los pedidos»**: se pide por proveedor, en su ficha;
- en «Hoy», «Antes de que se acabe» trae «Pedir a proveedores →», y cada artículo un botón «Pedir», que abre la ficha de
  su proveedor preferido con el artículo marcado en dorado y la cantidad sugerida, **sin marcar la casilla** (se marca
  al tocarla);
- en la ventana de un artículo, junto al proveedor: «Presentaciones y precios por proveedor: en Proveedores»;
- **sin cambios:** Existencias (Contar, **Recibir** y Merma), Recetas, Historial y Por mes. Lo que llega **sin pedido**
  (por ejemplo, una compra en el mercado) se sigue recibiendo en Existencias → «Recibir», con el PIN del encargado, como
  hoy (decisión 4).

**En Inicio:** el recuadro «Proveedores»; cada fila de «Antes de que se acabe» abre al proveedor de ese artículo;
«Pedir a proveedores» junto a «Abrir inventario».
**En el Reloj:** solo el enlace «Proveedores» arriba. **Marcar entrada y salida no cambia.**
**En Contabilidad:** en Compras, «Abrir en Proveedores →» en lugar de «Recibir en Inventario →»; en la tarjeta del
proveedor, «Abrir en Proveedores»; las facturas en dólares se registran en Proveedores (Pagos › Registrar factura).

**Recibir un pedido: cualquier persona en turno, sin otro PIN («Recibe en este aparato»).**
1. Cuando llega un pedido, en un aparato del café (la Caja, el iPad o la tableta del Reloj) abra «Proveedores»: el enlace
   de arriba del Reloj o de Inventario, o el recuadro de Inicio (en la Caja: «Reloj» → «Proveedores»). Sin las áreas de dueños
   abiertas, la página abre para recibir.
2. Si ese aparato ya sabe quién recibe, arriba dice «Recibe: (nombre) · PIN vigente hasta las HH:MM · ¿No es usted?
   Cambiar · Salir de este aparato» y abajo «Pedidos por recibir». Lo sabe cuando, **en ese mismo aparato y hace menos
   de 15 minutos**, la persona escribió su PIN en «¿Quién cobra?» de la Caja (después de marcar la entrada; entonces no
   escribe nada más), hizo el paso 3, o registró una entrega con esa identificación.
3. Si no lo sabe, la página pregunta «¿Quién recibe?» con las personas que tienen la entrada marcada: la persona toca
   **su** nombre, escribe **su propio** PIN y toca «Estoy en turno aquí». Su PIN vale **15 minutos** y cada entrega que
   registra lo extiende otros 15 (la barra dice hasta qué hora); pasado ese tiempo sin su PIN ni una entrega, la página
   dice «Pasaron más de 15 minutos desde su PIN o su última entrega. Escriba su PIN otra vez para seguir recibiendo.» y
   vuelve a «¿Quién recibe?» con su nombre ya elegido: solo escribe su PIN (lo que tenía escrito en una entrega vuelve).
   **El PIN es personal y no se comparte** (indicación del dueño, 2026-11-08): cada recepción queda a nombre de quien la
   registra, y un PIN compartido solo haría que figure otra persona.
   Quien todavía no marcó entrada está debajo, en «¿Todavía no marcó entrada?»: su nombre → su PIN → «Marcar entrada y
   empezar» (con el mismo PIN marca la entrada del Reloj y empieza a recibir).
4. Toque el pedido que llegó. Se abre «Recibir el pedido Nº n» con cada producto: lo pedido, lo que ya llegó antes, lo
   pendiente y el precio esperado. Si todo vino como se pidió: **«Todo recibido correctamente»** (un toque). Si algo es
   distinto: la cantidad recibida de cada producto con − y +, y si la factura trae otro precio, escríbalo en «Precio sin
   IVA»; después «Confirmar recepción». «Nº de factura (si la trae)» y «Observaciones» son opcionales.
5. **Si llegó menos**, lo que falta queda pendiente para otra entrega. Si el proveedor dijo que no llega el resto:
   «Avisar que no llega el resto»; el encargado lo ve en el pedido («(nombre) indicó que no llega el resto · Cerrar lo
   pendiente») y lo cierra él.
6. **Si llegó más** de lo pedido: «Llegó más de lo pedido: se anota para el encargado». Al inventario entra solo lo
   pedido; el encargado decide sobre lo demás.
7. **Un precio distinto** que escriba quien recibe se anota para que el encargado lo revise. **No cambia** el costo del
   inventario ni el precio del proveedor.
8. Si otra persona va a recibir en ese aparato: «¿No es usted? Cambiar». «Salir de este aparato» termina la sesión en
   el acto. Al marcar la salida en el Reloj termina sola; también si su PIN cambia, si la desactivan, si otra persona se
   identifica en ese aparato, o 16 horas después de su entrada. A los 15 minutos sin su PIN ni una entrega no termina:
   vuelve a pedir el PIN de esa misma persona.
9. Si la página dice «La Caja está usando esos productos en este momento. Intente de nuevo en un momento.», no se guardó
   nada: toque otra vez en unos segundos (la entrega le cede el paso a la venta). Si dice «Su entrega anterior ya quedó
   guardada. Revise lo que falta.», la entrega de antes sí quedó (por ejemplo, se fue el internet justo después):
   reciba solo lo que falte.

**Lo que ve quien recibe:** los pedidos por recibir (número, proveedor, fecha) y, en cada uno, los productos con lo
pedido, lo que ya llegó, lo pendiente y el precio esperado por presentación. **No ve** totales, pagos, el contacto del
proveedor ni su SINPE, y no puede pedir, editar, cancelar ni cerrar pedidos. Cada entrega queda con su nombre y «(en
turno)», el aparato y la hora.

**Ojo con quién tiene el aparato:** la página recibe solo a nombre de quien escribió **su propio** PIN en ese aparato
hace menos de 15 minutos (o registró una entrega en ese tiempo). Pasados los 15 minutos, nadie recibe en ese aparato
sin escribir su PIN: un aparato que quedó en el mostrador no identifica a nadie. Dentro de esos 15 minutos, si Luis se
identificó en el iPad y Marta recibe ahí sin cambiar el nombre, la entrega queda a nombre de Luis: quien recibe mira el
nombre de arriba («Recibe: Luis · PIN vigente hasta las 10:45») y, si no es el suyo, toca «¿No es usted? Cambiar». En la
Caja, el nombre es el de quien escribió su PIN en «¿Quién cobra?» hace menos de 15 minutos; más viejo, Proveedores le
pide su PIN con su nombre ya elegido («Escriba su PIN para recibir en este aparato.»); si después cambia quien cobra,
Proveedores sigue con la persona anterior mientras sus 15 minutos sigan vigentes (decisión 1).

**Los encargados** (con su PIN en «Abrir áreas de dueños», 15 minutos, como en Inventario): todo lo de antes en un solo
lugar. Pedir con casillas en la ficha del proveedor (la casilla, la cantidad, el total estimado en vivo, «Crear
pedido»); el pedido con su número y **Copiar, PDF e Imprimir** (ya no los botones de WhatsApp y correo: se copia el
texto, o se manda el PDF, que en el iPad abre la hoja para compartirlo); editar el pedido antes y después de una entrega
(queda en «Historial de cambios»); recibir (también lo que llegó de más, con «Llegó de más (lo autorizo)»); corregir una
entrega con un registro nuevo («Corregir una entrega», nada se borra); registrar la factura; registrar pagos.

**Pagos a proveedores: solo SINPE y tarjeta.**
- **SINPE:** el «Número de confirmación SINPE» es **obligatorio** y no se puede registrar dos veces, ni para otro
  proveedor ni escrito con espacios o guiones («Ese número de SINPE ya está registrado (…)»).
- **Tarjeta:** «Tarjeta de débito» o «Tarjeta de crédito», con una referencia opcional.
- Se puede pagar **antes o después** de recibir y antes o después de la factura; cada pedido muestra «Pago pendiente»,
  «Parcialmente pagado» o «Pagado».
- Lo registra un encargado con **su** PIN en «Quién lo registra» (usted con el código del teléfono, o el contador, sin
  PIN). Más de lo que se debe solo lo registra el dueño (decisión 6). Un pago antes de la factura dice «Pago guardado ·
  queda esperando la factura»; cuando la factura se registra (en Proveedores o en Contabilidad), el pago se le aplica
  solo.
- Lo que dejaría dinero a favor del café (cancelar un pedido ya pagado, bajarle cantidades, cerrar lo pendiente o
  corregir una entrega a menos) solo lo hace el dueño: «Eso dejaría ₡X a nuestro favor con este proveedor (un pago ya
  hecho). Solo el dueño puede hacerlo.» (decisión 6).
- **Nunca dos veces, tampoco desde Contabilidad:** un pago registrado en Contabilidad («Registrar pago», también el de
  la página de Inventario anterior y cualquier llamada directa) aplica primero en el servidor lo ya pagado en
  Proveedores a las facturas de ese proveedor y solo acepta lo que se debe después («{x} pagados en Proveedores se
  aplicaron primero…»); un número SINPE ya registrado en Proveedores se niega también allí, y en el pago por banco de
  un gasto («Ese número de SINPE ya está registrado en Proveedores: la misma transferencia no se registra dos veces.»)
  (decisión 8).
- **El efectivo ya no se ofrece en Proveedores** (ni «Efectivo de la caja registradora» al recibir, que era la opción de
  la ventana de Inventario, ni la caja fuerte ni la caja chica). Un pago en efectivo se registra en Contabilidad, como hoy
  (decisión 2).

**El SINPE del proveedor** («SINPE (número y nombre para transferencias)») se ve en la ficha a los encargados; solo lo
cambian quien tiene puesto de dueño con su PIN, usted con el código del teléfono o el contador, y queda anotado («SINPE
cambiado el … por …», decisión 3).

---

## 1 · Antes (no toca producción)

1. **«Tests» en verde.** GitHub → **Actions** → **Tests** → la ejecución del último commit de la rama
   `claude/proveedores`: ✅. Su código debe ser el que le di.
2. **Subir `anonimizar.sql` de esta versión a `canopy-respaldos`, antes del ensayo** (como en E-38, E-41 y E-42): el
   archivo `ops/backup/repositorio-respaldos/anonimizar.sql` de esta versión, en la raíz de `canopy-respaldos`,
   reemplazando el que está. Conoce las columnas de la 0039: el SINPE de cada proveedor se vacía, el número de
   confirmación o la referencia de cada pago pasa a «texto N» (uno distinto por pago), las notas de borradores y entregas
   y los motivos pasan a «texto», quién hizo cada cosa a «Persona», y se vacían las tablas nuevas de las sesiones «Recibe en
   este aparato» (`work_sessions`) y de los cambios de PIN (`staff_pin_changes`). El catálogo (códigos, nombres y presentaciones de los productos) se conserva: es del
   negocio, no de personas. Con el de la 0038 el ensayo se detiene antes de copiar nada («anonimizar.sql no sabe si estas
   columnas guardan datos de personas…»), como está diseñado.
3. **«Ensayo en pruebas» en verde.** `canopy-respaldos` → **Actions** → **Ensayo en pruebas** → **Run workflow**:
   - «Rama o etiqueta del repositorio de desarrollo a ensayar»: el código completo del commit que le di (o la rama
     `claude/proveedores`);
   - destino `desechable`, vaciar `no`, reinicio `no` → **Run workflow**.
   - Unos 5 minutos. Verde quiere decir: copió producción, la anonimizó y aplicó **solo la 0039 y la 0040**. El resumen
     dice «the copy already had migrations 0000-0038 (production after the launch) …» y «unchanged: … original tables
     …», sin ninguna línea «DIFFERENCE:»; `timings.txt` en el resultado `ensayo-resultados-desechable` dice
     «0039_proveedores … ms» y «0040_proveedores_pagos … ms».
   - **Guarde `consistency-after.json`** del mismo resultado: la etapa 3.10 compara con él las tres revisiones de
     Proveedores que miran lo ya registrado.
   - **Las páginas publicadas hoy sobre la 0039 y la 0040** las prueba «Tests» (paso «Migration rehearsal…»), en cada
     ejecución: sobre una copia como producción con todas las migraciones hasta la 0040, la pestaña «Pedidos» de
     Inventario publicado (`77a5fb1`) crea un pedido, le agrega una línea y lo recibe en el navegador con la factura por
     venir, y Proveedores lo lee como lo que se debe; la factura confirmada con un pago por banco, por la misma llamada
     que hace esa página (`po_receive_and_settle`), la comprueba `after-window.sql` (5b) en el mismo paso; también un pedido de la página anterior pagado por banco mientras el
     proveedor tiene un pago de Proveedores sin aplicar, y un retiro de la gaveta de la página anterior que la factura de
     Proveedores documenta.
4. **La vista previa privada, aprobada:** el enlace que le paso en el chat (una página privada de claude.ai, con datos
   inventados). No lee ni cambia nada de producción. Mírela en el iPad (Safari) y en la Caja del frente: el centro, la
   ficha de un proveedor, pedir con casillas, el documento con Copiar / PDF / Imprimir, recibir con «Todo recibido
   correctamente», un pago por SINPE. Anote lo que quiera cambiar: se ajusta antes de activar.
5. **La cuenta 1160 y quién tiene puesto de dueño (solo lectura):** Supabase → **SQL Editor** → **New query** →
   `select code, name, type, active from acct.accounts where code = '1160';` → **Run**. Lo esperado: una fila `1160 ·
   Anticipos a proveedores · asset · true` (o ninguna: la 0040 la crea). Con otro nombre, otro tipo o `false`, la 0040 se
   negaría (3.5): avíseme antes de seguir. El ensayo (1.3) ya lo comprueba sobre la copia. Y, también solo lectura:
   `select count(*) as duenos_con_pin from public.staff where active and role = 'owner' and pin_hash is not null;`. Si es
   `0`, mientras E-06 siga abierta solo el contador (E-18) podrá cambiar el SINPE de un proveedor, registrar un pago
   mayor que el saldo o anular un pago de Proveedores (decisiones 3 y 6). No detiene la activación.
6. **El registro de los descuentos (E-42), pendiente** (D-066): la 0038 está instalada según usted, pero su registro de
   activación no está escrito. No detiene esta activación; recomiendo darlo ahora, para que el commit de después
   («Registro») cierre las dos. Pegue (solo lectura)
   `select version, name, applied_at from canopy.migrations where version >= 37 order by version;` y dígame, sin PIN:
   qué aparatos quedaron registrados para descuentos (puesto, nombre, encargado), si apagó la ventana anterior
   (`pos_free_discount`) y cuándo, y el resultado de las comprobaciones A a E de esa guía.
7. **Sus decisiones, por escrito en el chat, antes de la etapa 3** (sección «Lo que usted debe aprobar o decidir»,
   puntos 1 a 8). La condición es la **1**, la garantía de «Recibe en este aparato»; sin ella no se activa. La línea que
   pido:

   > Apruebo que cualquier persona en turno reciba pedidos sin otro código por entrega, identificándose con su propio
   > PIN en ese aparato (o con el PIN que escribió en «¿Quién cobra?» de la Caja hace menos de 15 minutos): la
   > identificación vale 15 minutos y se extiende con cada entrega que registra; pasado ese tiempo nadie recibe en ese
   > aparato sin su propio PIN, sabiendo que dentro de esos 15 minutos (que cada entrega renueva) el aparato sigue a
   > nombre de esa persona.

   Se copia palabra por palabra en `docs/DEPENDENCIES.md` (E-43) en el commit de después de la activación («Registro»),
   o en un commit antes de la etiqueta con «Tests» corrido otra vez sobre él. Nunca en un commit entre la etiqueta y la
   publicación (2.1).
8. **Avisar al equipo** con la sección 0.
9. **Quiénes están esa noche:** usted (GitHub y Supabase), un encargado con su PIN (5.B) y una persona del equipo con la
   entrada marcada (5.D), si la hay; si no, 5.D se hace al día siguiente.

---

## 2 · La etiqueta y sus pruebas (no toca producción)

1. **La etiqueta (el mismo día que va a publicar, antes de las 23:00).** GitHub → **Releases** → **Draft a new release**
   → **Choose a tag**: `vAAAA.MM.DD-1` con la fecha de hoy (si ya existe una de hoy, `-2`) → **Create new tag** →
   **Target**: la rama `claude/proveedores` (el formulario propone la predeterminada y nada avisaría del error). Antes,
   compruebe que su último commit es el que le di. → **Publish release**. En **Tags**, la etiqueta debe mostrar ese
   mismo commit; si muestra otro, **no publique** y cree `-2` en el commit correcto. **Una etiqueta nunca se borra ni se
   mueve.** Desde ahora y hasta publicar, nadie sube nada a la rama.
2. **Pruebas sobre la etiqueta.** **Actions** → **Tests** → la ejecución con el nombre de la etiqueta → en verde. Tarda
   unos 30 minutos. **No entre las 00:00 y las 05:00 de Costa Rica**: hay pruebas que dependen de la hora y saldrían en
   rojo. Si sale rojo, no siga: copie el nombre del paso y de la prueba y páseme el mensaje.

---

## 3 · Después del cierre: respaldo, fotos, la 0039, la 0040 y sus comprobaciones

**Condiciones:**
- **Después del cierre (19:00), desde las 19:30**, con las etapas 1 y 2 en verde y su línea de 1.7 dada. No de
  madrugada: el respaldo nocturno corre desde las 02:17 (GitHub lo atrasa a veces hasta las 7:30) y un respaldo en curso
  puede hacer fallar la pegada.
- **Caja:** en cada tableta el aviso de conexión dice «en línea» y, al tocarlo, «Todo lo que se tomó en este dispositivo
  está guardado en el sistema.». Si dice «guardando N…», «N sin guardar todavía», «sin conexión · N en este
  dispositivo» o «no guardado en este dispositivo», espere a que se vacíe. Ningún ticket a medias; «Hoy en el mostrador»
  cerrado; la cocina sin pedidos.
- **Inventario:** nadie con un pedido abierto, ni la ventana «Recibir» de un pedido a medias.
- **Nadie usa ningún aparato entre la foto de antes (paso 2) y la de después (paso 8)**: ni ventas, ni marcas en el
  Reloj (la 0039 agrega un disparador a las marcas: una marca en ese instante esperaría o haría fallar la pegada), ni el
  PIN de las áreas del dueño. Deje cada aparato en la Caja o en la Cocina (el Reloj, Inicio, el Menú, Ventas e
  Inventario cierran la sesión solos a los 30 minutos, y eso también cambia las huellas). Haga los pasos 2 a 11
  seguidos.
- Los archivos que se pegan son los de **la etiqueta**: GitHub → **Tags** → la etiqueta → el archivo → **Raw**, y copie
  **todo** cada vez. Cada consulta en su propio **New query** (el SQL Editor muestra solo el último resultado).

1. **Respaldo.** `canopy-respaldos` → **Actions** → **Respaldo nocturno** → **Run workflow** → **Run workflow**. Unos 2
   minutos, en verde; el resumen dice «restauración: passed». Luego, que no quede nada corriendo: en Actions ninguna
   corrida de «Respaldo nocturno» ni de «Ensayo en pruebas» en curso o en cola, y en el SQL Editor
   `select count(*) from pg_stat_activity where usename = 'canopy_backup';` → `0`.
2. **Las fotos de antes** (guarde cada resultado completo en un archivo):
   - `supabase/tools/production-snapshot.sql` → «snapshot-antes». Debe decir: `migrations_applied` termina en `38`; en
     `schema`, `functions_by_version` sin las claves `"0039"` ni `"0040"`, `functions_changed` = `[]`,
     `functions_unknown` = `[]`;
   - `supabase/tools/release-check.sql` → «release-antes»: `migrations_missing` = `[39, 40]`; `functions_missing` = los 28
     nombres que empiezan por `proveedor_`, `proveedores_` o `turno_`. Si `migrations_missing` dice `[38, 39, 40]`, la
     0038 no está aplicada: **deténgase y avíseme**;
   - `supabase/tools/consistency-check.sql` → «consistencia-antes» (todavía sin las revisiones de Proveedores en
     `after`).
3. **La 0039.** **New query** → pegar **todo** `supabase/migrations/0039_proveedores.sql`. Antes de **Run**: la segunda
   línea (debajo de «=====») dice «Canopy OS · migración 0039 · Proveedores: catálogo de cada proveedor, pedidos,
   recepción por el personal en turno…», y al bajar al final del texto pegado las dos últimas líneas son
   `select canopy.migration_end(39, 'proveedores');` y `notify pgrst, 'reload schema';` (si no están, el texto quedó
   cortado: borre y pegue de nuevo). → **Run** → debe decir **Success** (sin filas). Una sola vez.
   - Si el editor pide confirmar una «destructive operation», es lo esperado: la 0039 usa `drop … if exists` en sus siete
     disparadores y en cinco reglas suyas de columnas nuevas, antes de crearlos (en producción todavía no existen); no
     borra datos → «Run this query».
   - «La migración 39 (proveedores) ya estaba aplicada: no se cambió nada.» → ya estaba; siga con el paso 4.
   - «Falta aplicar antes la migración 38…» → **deténgase y avíseme** (no pasó nada).
   - «canceling statement due to lock timeout» → no se aplicó nada: algo tenía tomadas esas tablas más de 8 segundos,
     casi siempre un respaldo en curso o un aparato en uso. Revise el paso 1 y las condiciones, espere y pegue de nuevo.
     Si pasa dos veces, no pegue una tercera: avíseme.
   - Cualquier otro error: **deténgase**, copie el mensaje completo y no publique. La base sigue en la 0038.
4. **El registro.** `select version, name, applied_at from canopy.migrations order by version desc limit 2;` →
   `39 proveedores` y `38 descuentos_caja`. Anote el `applied_at` (hora UTC). Si dijo *Success* pero no aparece la 39, no
   siga: avíseme.
5. **La 0040.** **New query** → pegar **todo** `supabase/migrations/0040_proveedores_pagos.sql`. Antes de **Run**: la
   segunda línea dice «Canopy OS · migración 0040 · Proveedores: lo que lee la página nueva, facturas, pagos por SINPE o
   tarjeta y…», y las dos últimas líneas son `select canopy.migration_end(40, 'proveedores_pagos');` y
   `notify pgrst, 'reload schema';`. → **Run** → **Success** (sin filas). Una sola vez.
   - Si el editor pide confirmar una «destructive operation», es lo esperado: la 0040 quita y vuelve a crear, en la misma
     transacción, la regla `supplier_payments_paid_from_check`, ahora con `'advance'` además de las seis formas de pago
     de siempre; no borra datos → «Run this query».
   - «La migración 40 (proveedores_pagos) ya estaba aplicada: no se cambió nada.» → ya estaba; siga con el paso 6.
   - «Falta aplicar antes la migración 39…» → la 0039 no quedó aplicada: **deténgase y avíseme**.
   - «La cuenta 1160 ya existe con otro nombre o tipo…» o «La cuenta 1160 «Anticipos a proveedores» está inactiva…» →
     no se cambió nada: **deténgase y avíseme** (1.5).
   - «canceling statement due to lock timeout» → como en el paso 3.
   - Cualquier otro error: **deténgase**, copie el mensaje y **no publique**. La base queda en la 0039, que no cambia nada
     de lo que usan las páginas publicadas hoy; lo vemos juntos antes de pegar otra cosa.
6. **El registro otra vez:** la misma consulta del paso 4 → `40 proveedores_pagos` y `39 proveedores`.
7. **`release-check.sql`.** Debe decir:
   - `migrations_missing` = `[]` y `functions_missing` = `[]`. Si dice `[40]`, la pegada de la 0040 quedó incompleta:
     **deténgase y avíseme**;
   - `anon_can_run` = `["canopy_schema_version", "order_status", "pantalla_datos", "place_room_order", "room_lookup"]`
     (igual que antes: ni la 0039 ni la 0040 dan nada a un visitante);
   - `settings` y `confirmations` iguales a los de «release-antes» (Proveedores no agrega ningún ajuste);
   - `tables_without_rls` = `[]`, `storage_policies_missing` = `[]`, en `ledger` `unbalanced` = `0`.
8. **La foto de después.** `production-snapshot.sql` otra vez → «snapshot-después», **antes de tocar los aparatos**.
   Debe decir:
   - `migrations_applied` termina en `40` (con la `39` antes);
   - en `schema`: `functions_by_version` con `"0039": 56` y `"0040": 26` (las 23 nuevas y `supplier_invoice_save`,
     `supplier_payment_save` y `expense_pay`, redefinidas), `"0025"`, `"0029"` y `"0035"` uno menos cada una que en
     «snapshot-antes» (esas tres funciones ahora son las de la 0040) y las demás claves (también `"legacy"`)
     iguales, sin la clave `"?"`; `functions_changed` = `[]`; `functions_unknown` = `[]`; `tables_missing` = `[]`;
     `functions_total` = el de antes + 79; `tables_other` incluye `public.purchase_drafts`,
     `public.purchase_receipt_lines`, `public.staff_pin_changes`, `public.supplier_advances`, `public.vendor_items`,
     `public.vendor_pay_info` y `public.work_sessions`; `tables_columns_differ` y `triggers_differ` iguales a los de
     antes;
   - `data_fingerprint` y `security` → `anon_can_run` **idénticos** a los de «snapshot-antes» (las migraciones no cambian
     ninguna fila de las tablas de siempre ni ningún permiso existente: lo copiado al catálogo va a tablas nuevas);
     `switches` igual. Si una tabla de `data_fingerprint` cambió, **no vuelva a pegar nada**: deténgase y avíseme con las
     dos fotos (casi siempre es un aparato que se usó en medio).
9. **La cuenta de respaldo.** `supabase/tools/backup-account.sql` → **Run** → una fila que empieza con «lista: la
   cuenta canopy_backup puede leer … tablas del café…» (ahora también las siete tablas nuevas). Si dice «REVISAR» o un
   error, copie el mensaje y avíseme; no publique.
10. **Consistencia.** `consistency-check.sql` otra vez:
    - todo `kept` idéntico a «consistencia-antes», y `problems` igual que antes;
    - en `after`, nueve celdas nuevas. Seis miran lo que solo Proveedores registra, que todavía no existe, y deben dar
      `0`: `sinpe_payments_without_reference`, `payments_applied_above_amount`, `advances_ledger_vs_unapplied`,
      `vendors_unapplied_with_open_invoices`, `advances_unapplied_over_30_days` y `proveedores_dangling_references`
      (una corrección cuya entrega, o un pago cuyo pedido, no existe);
    - las otras tres miran lo que ya se había registrado antes de la 0039 (`receipts_total_vs_moves`,
      `purchase_moves_at_zero_cost`, `posted_days_with_purchases_not_posted`): anote cada número; deben ser los mismos
      de `consistency-after.json` del ensayo (1.3). Si alguno es distinto (por ejemplo, porque entre el
      ensayo y hoy se recibió algo después del cierre), no es motivo para revertir: anótelo y avíseme antes de publicar.
11. **El catálogo inicial (solo lectura):**

    ```sql
    -- solo lectura: lo que la 0039 copió al catálogo nuevo
    select (select count(*) from public.vendor_items where created_by = 'migración 0039') as catalogo_inicial,
           (select count(*) from public.stock_items where vendor_id is not null) as articulos_con_proveedor,
           (select count(*) from public.purchase_receipt_lines) as lineas_de_entregas;
    ```
    Lo esperado: `catalogo_inicial` mayor o igual que `articulos_con_proveedor` (una fila por artículo con su proveedor,
    más una por cada otro proveedor o presentación de los pedidos de antes); `lineas_de_entregas`, las líneas de las
    entregas de antes que se pudieron asignar a su línea del pedido. Anote los tres números.

Hasta publicar (etapa 4), **Inventario sigue igual**: las páginas de hoy pidiendo, recibiendo y pagando como siempre
sobre la 0039 y la 0040 (lo prueba «Tests», 1.3). Lo que hagan esa noche o al día siguiente queda también en Proveedores
cuando lo publique.

---

## 4 · Guardar el sitio de hoy, publicar y comprobar la versión

1. **Primero, guardar el sitio de hoy (la vuelta atrás exacta). No se salte este paso:** en la publicación de los
   descuentos no se hizo (D-066) y por eso no existe una copia guardada de `44a0dab`. GitHub → **Releases** → **Draft a
   new release** → **Choose a tag**: `sitio-AAAA-MM-DD` con la **fecha de hoy** → **Create new tag** → **Target**: la
   rama **gh-pages** → título «Sitio antes de Proveedores» → marque **Set as a pre-release** → **Publish release**. En
   **Tags** debe mostrar el commit `77a5fb1` («Publish website v2026.11.04-1 9d3f6ad…»). Si muestra otro: **Releases** →
   esa versión → **Delete**, y **Tags** → esa etiqueta → **Delete tag**; después créela otra vez con Target **gh-pages**
   (esta etiqueta guarda una copia del sitio, no es una versión). Si ya existe una `sitio-` con la fecha de hoy, no la
   toque y avíseme. **No publique (paso 2) hasta que esta etiqueta muestre `77a5fb1`.**
   - **No use `sitio-2026-11-03` ni ninguna `sitio-` anterior:** son sitios de antes de los descuentos (y de antes de las
     pantallas V2); restaurarlos los quitaría.
2. **Publicar.** **Actions** → **Publish website (PRODUCTION · manual only)** → **Run workflow**:
   - **Use workflow from** → **Tags** → la etiqueta nueva;
   - en «Escriba PUBLICAR para publicar esta versión en el sitio real del café»: `PUBLICAR`;
   - «Solo para volver a un sitio guardado (sitio-AAAA-MM-DD). Vacío = publicar esta versión»: **vacío**;
   - **Run workflow**. Espere el verde de la corrida y el de «pages build and deployment» (de 2 a 10 minutos). (Si GitHub
     pide aprobar el despliegue, apruébelo solo si es el de la etiqueta nueva.)
3. **Comprobar la versión.** `https://hanginggardencafe.com/version.json?t=` seguido de la hora (por ejemplo
   `?t=2015`, un número nuevo cada vez): `"version"` = la etiqueta, `"build"` = los 12 primeros caracteres del commit y
   `"sha"` = el commit. Si todavía dice `v2026.11.04-1`, espere (hasta 10 minutos); **no vuelva a publicar**.
4. **Las páginas se actualizan solas.** La Caja dice «actualización lista» y se recarga sola entre ventas (nunca con
   productos en el ticket); las demás páginas, al volver a abrirlas. Si a los 15 minutos un aparato sigue igual,
   recárguelo a mano. Inventario → «Pedidos» debe llevar a Proveedores.

---

## 5 · Comprobaciones en el café (sin pedidos, entregas ni pagos de prueba)

**No haga pedidos, entregas, facturas ni pagos de prueba**: quedarían como registros reales que no se borran
(CLAUDE.md): una entrega sube el inventario y entra en el asiento del día; un pago va a los libros. Los caminos completos
los prueban las pruebas automáticas. Lo de abajo solo **mira**.

| # | Qué hacer | Correcto si |
|---|---|---|
| A | Inicio → el recuadro «Proveedores». Inventario → pestaña «Pedidos» | Las dos llevan a Proveedores. En una tableta sin áreas de dueños abiertas, Proveedores abre para recibir («¿Quién recibe?» o «Recibe: …») |
| B | Un encargado, en una tableta del café: Proveedores → «Abrir áreas de dueños» → su nombre y su PIN. Mire el centro, abra un proveedor con artículos: pestañas «Pedir», «Pedidos», «Pagos», «Productos». Al terminar, «Bloquear» | Arriba «Antes de que se acabe» (si hay artículos bajos), la lista de proveedores con sus insignias («N por recibir», «Debe ₡X»…); en «Pedir» y «Productos», los artículos de ese proveedor que copió la 0039, con su presentación y su precio habitual «sin IVA» (del proveedor preferido, el «Costo por paquete» de Inventario; de otro proveedor, el del último pedido); en «Pedidos», los pedidos de antes con su Nº; ningún mensaje de error. Al bloquear, la página vuelve a recibir y no queda ningún monto en pantalla |
| C | Con las áreas abiertas: tocar una alerta de «Antes de que se acabe» (en Proveedores, en Inicio o el «Pedir» de Inventario → Hoy). **No cree el pedido** salvo que sea uno real | Abre la ficha del proveedor preferido de ese artículo, con el artículo marcado en dorado y la cantidad sugerida, **sin la casilla marcada**. Un artículo sin proveedor (o con uno inactivo) abre «Asociar proveedor» |
| D | Una persona con la entrada marcada, en la tableta del Reloj o el iPad (sin áreas abiertas): Proveedores → «¿Quién recibe?» → su nombre → su PIN → «Estoy en turno aquí» | «Listo: usted recibe en este aparato.», arriba «Recibe: (nombre) · PIN vigente hasta las HH:MM» (15 minutos después de su PIN), abajo «Pedidos por recibir» (o «Nada por recibir en este momento.»). **No reciba nada que no haya llegado.** Luego «Salir de este aparato» → «Listo: ya nadie recibe en este aparato.» |
| E | En la Caja donde alguien escribió su PIN en «¿Quién cobra?» hace menos de 15 minutos: «Reloj» → «Proveedores» (arriba) | «Recibe: (esa persona) · PIN vigente hasta las HH:MM» sin pedir ningún PIN (el aparato conoce a su cajero sin PIN solo durante los 15 minutos que siguen al PIN de la Caja). Si ese PIN es de hace más de 15 minutos, pide su PIN con su nombre ya elegido («Escriba su PIN para recibir en este aparato.»): también es correcto. Vuelva a la Caja («Caja», arriba) |
| F | Con las áreas abiertas, en un pedido abierto que exista: «Copiar» y pegar en las notas del teléfono; «PDF»; «Imprimir» → ver la vista previa → cancelar. **No lo mande al proveedor** salvo que sea real | El texto empieza «Pedido Nº … · Hanging Garden Café», trae proveedor, fecha, productos y cantidades, sin precios, nombres del personal ni SINPE; el PDF se llama «Pedido-…-(proveedor).pdf»; la impresión muestra solo el documento |
| G | Si alguien entra a Contabilidad: Compras → un pedido abierto | «Abrir en Proveedores →» abre ese pedido |
| H | **Al día siguiente:** el primer pedido real con casillas («Crear pedido»), mandado con Copiar o PDF; la primera entrega real recibida por una persona en turno con «Todo recibido correctamente»; el primer pago real por SINPE con su número | El pedido con su Nº; la entrega sube el inventario una vez («Parcialmente recibido» o «Recibido»); el pago queda en «Pagos» y el pedido pasa a «Parcialmente pagado» o «Pagado» |

**Consultas finales** (solo lectura; cada una en su propio «New query»):

```sql
select at, action, manager_name, summary
  from public.audit_log
 where action like 'work_session_%'
 order by at desc limit 20;
```
Esperado: un `work_session_start` por cada persona de D y E («Recibe en este aparato: (nombre)»), un `work_session_end`
del «Salir de este aparato» de D («… · salió de este aparato»). Ninguna fila trae un PIN ni un código de sesión.

```sql
select (select count(*) from public.supplier_advances) as pagos_en_proveedores,
       (select count(*) from public.purchase_receipts where origin is not null) as entregas_en_proveedores;
```
Esperado: `0` y `0` la noche de la activación (las comprobaciones no registran nada); después, los pagos y las entregas
reales.

**Nunca, en las tabletas del café:** «Cerrar sesión en todos lados» (saca la Caja y la cocina), «Activar» el código del
teléfono, «¿Olvidó su contraseña?», borrar los datos del sitio (también borraría quién recibe en ese aparato y la cola de
ventas sin internet).

---

## 6 · Vuelta atrás

| Qué pasa | Qué hacer |
|---|---|
| Alguien no puede recibir («¿Quién recibe?» no lo deja: «No tiene la entrada marcada.», «Tiene un turno abierto desde …; avise a un encargado.») | No es una vuelta atrás: que marque la entrada (o «Marcar entrada y empezar»), que un encargado corrija el turno abierto en el Reloj, o que reciba un encargado con su PIN |
| Una entrega o un pago quedó mal | No es una vuelta atrás: un encargado la corrige con «Corregir una entrega» (un registro nuevo; nada se borra); un pago lo anula el dueño o el contador («Anular», con el motivo) |
| Proveedores no le convence o falla en los aparatos | **6.1** (las páginas vuelven; la base se queda en la 0040) |
| Falla una función de la 0039 o la 0040 (errores del servidor que nombran `proveedor_…`, `proveedores_…` o `turno_…`) | **6.1** y después **6.2**, y avíseme |
| Inventario, Inicio o la Caja no cargan después de publicar | **6.1** de inmediato y avíseme |

### 6.1 Las páginas vuelven a `v2026.11.04-1` (la base se queda en la 0040)

1. **Actions** → **Publish website (PRODUCTION · manual only)** → **Run workflow** → **Use workflow from** → **Tags** →
   `v2026.11.04-1` → `PUBLICAR` en la primera casilla → la segunda **vacía** → **Run workflow**.
   - Solo si esa publicación falla: la copia exacta guardada en 4.1. **Use workflow from** → **Tags** → la etiqueta de
     Proveedores (la de hoy), `PUBLICAR` en la primera casilla y en la segunda `sitio-AAAA-MM-DD` (la fecha de 4.1).
     **Revise que la segunda casilla no quede vacía**: vacía, publicaría Proveedores otra vez. **Nunca
     `sitio-2026-11-03` ni otra anterior** (quitarían los descuentos).
2. `version.json?t=…` dice `"version": "v2026.11.04-1"` y `"build": "9d3f6ad1e0e4"` (con la copia exacta, el
   `version.json` guardado de esa versión).
3. Las páginas se recargan solas (la Caja, entre ventas); si una no cambia en 15 minutos, recárguela a mano.
4. **Avise al equipo:**
   - Inventario → «Pedidos» y «Proveedores» vuelven a ser como antes: recibir pide el PIN del encargado, y la ventana de
     recibir vuelve a ofrecer «Efectivo de la caja registradora»;
   - lo hecho en Proveedores **se queda**: los pedidos creados ahí aparecen en «Pedidos» con su Nº (una línea que se
     quitó en Proveedores aparece con 0), las entregas y las facturas cuentan, los borradores quedan guardados sin verse;
   - **los pagos registrados en Proveedores se quedan.** Uno que todavía no se aplicó a una factura (pagado antes de la
     factura) queda en la cuenta 1160 y las páginas anteriores **no lo muestran**, ni Inventario ni Contabilidad; pero
     la base sí lo tiene en cuenta: con la 0040 aplicada, un pago registrado en la Contabilidad o en el Inventario
     anteriores aplica primero por su cuenta ese pago a las facturas de ese proveedor y niega un número SINPE ya
     registrado en Proveedores (decisión 8), así que no se paga dos veces aunque la página no lo vea. La consulta de
     abajo queda como comprobación para el contador y los encargados (qué pagos esperan su factura), ya no como la única
     defensa. **Dígaselo al contador directamente**, no solo al equipo. Y una nota: si esa página paga por banco una factura a la que el servidor acaba de aplicar un pago de Proveedores, su aviso y su línea de auditoría pueden decir un «saldo» viejo (la factura, los libros y Proveedores están bien);
   - «Recibe en este aparato» deja de usarse (sus sesiones terminan solas).
5. La base se queda en la 0040 y las páginas anteriores funcionan con ella: lo prueba «Tests» en cada ejecución (las
   páginas publicadas `77a5fb1`, con su pestaña «Pedidos», sobre una copia con la 0040). Si más adelante vuelve a
   publicar Proveedores, todo está ahí.

```sql
-- solo lectura: pagos registrados en Proveedores que todavía no se aplicaron a una factura
select v.name as proveedor, a.date as fecha, a.amount_crc as monto, a.method as forma,
       a.amount_crc - coalesce((select sum(p.amount_crc) from public.supplier_payments p
                                 where p.advance_id = a.id and p.voided_at is null), 0) as sin_aplicar
  from public.supplier_advances a join public.vendors v on v.id = a.vendor_id
 where a.voided_at is null
   and a.amount_crc > coalesce((select sum(p.amount_crc) from public.supplier_payments p
                                 where p.advance_id = a.id and p.voided_at is null), 0)
 order by a.date;
```

### 6.2 La base (solo por una falla de una función de la 0039 o la 0040, y después de 6.1)

Nunca revierta solo la base con Proveedores publicado: la página diría «Esto necesita la actualización de la base de
datos de Proveedores (migración 0039). Avise al dueño.» y nadie podría pedir ni recibir ahí. Por eso primero 6.1. Fuera
del horario de atención, salvo urgencia. **Primero la 0040, después la 0039** (al revés se niega).

1. **Respaldo nocturno** → **Run workflow** → en verde.
2. Los archivos de este paso y de los siguientes son los de **la etiqueta de Proveedores** (la de la etapa 2), no los de
   la rama ni los de `v2026.11.04-1`. **SQL Editor** → **New query** → pegar **todo** `supabase/tools/reversion-0040.sql`.
   Antes de **Run**, baje al final del texto pegado: las dos últimas líneas son
   `delete from canopy.migrations where version = 40;` y `notify pgrst, 'reload schema';` (si no están, el texto quedó
   cortado: borre y pegue de nuevo). Si el editor pide confirmar una «destructive operation», es lo esperado (quita las 23
   funciones y los dos disparadores de la 0040, devuelve `supplier_invoice_save`, `supplier_payment_save` y `expense_pay`
   a sus textos de la 0025, la 0029 y la 0035, y quita la fila 40 del registro; no borra datos) → **Run** → **Success**
   (sin filas).
   - «La migración 0040 no está aplicada: no hay nada que revertir. No se cambió nada.» → ya estaba revertida.
   - «Hay una migración posterior a la 0040 aplicada (…): revierta esa primero. No se cambió nada.» → avíseme.
3. `release-check.sql`: `migrations_missing` = `[40]`; `functions_missing` = los 11 de la 0040
   (`proveedor_anticipos_aplicar`, `proveedor_factura_anular`, `proveedor_factura_registrar`, `proveedor_ficha`,
   `proveedor_historial`, `proveedor_pago_anular`, `proveedor_pago_registrar`, `proveedor_pedido`, `proveedores_bitacora`,
   `proveedores_lista`, `proveedores_por_recibir`). Si yo le dije que la falla es solo de la 0040 (pagos o lecturas), deténgase aquí.
4. **New query** → pegar **todo** `supabase/tools/reversion-0039.sql`. Las dos últimas líneas:
   `delete from canopy.migrations where version = 39;` y `notify pgrst, 'reload schema';`. «Destructive operation»: es lo
   esperado (quita los siete disparadores, las 56 funciones de la 0039 y la fila 39; no borra datos) → **Run** →
   **Success**.
   - «La migración 0039 no está aplicada: no hay nada que revertir. No se cambió nada.» → ya estaba revertida.
   - «Hay una migración posterior a la 0039 aplicada (40): revierta esa primero. No se cambió nada.» → falta el paso 2.
5. `release-check.sql`: `migrations_missing` = `[39, 40]`, `functions_missing` = los 28 nombres de 3.2, `anon_can_run`
   = las mismas cinco de 3.7.
6. `production-snapshot.sql`: `migrations_applied` termina en `38`; `functions_changed` = `[]`; `functions_unknown` =
   `[]`; `functions_by_version` y `functions_total` iguales a los de «snapshot-antes» (sin las claves `"0039"` ni
   `"0040"`, y `"0025"` otra vez como antes); `tables_other` sigue con las siete tablas nuevas (quedan, sin uso).
7. **Qué queda:** las siete tablas con sus filas (el catálogo, los borradores, las líneas de las entregas, los pagos de
   Proveedores, el SINPE de cada proveedor, las sesiones, los cambios de PIN), las columnas nuevas, la cuenta 1160 con sus dos mapeos y la
   regla de pagos con `'advance'`; los pagos aplicados y sus asientos (Contabilidad los sigue viendo como pagos a
   proveedor, y el libro sigue cuadrado). **Un pago que todavía no se aplicó queda en la 1160** hasta que se vuelvan a
   aplicar las migraciones o el contador lo resuelva (A-15). Al aplicar otra vez la 0039 y después la 0040, todo vuelve
   como estaba, y lo que la página anterior hizo mientras tanto se copia a las tablas nuevas.
8. **No pegue `reversion-0038.sql`** por un problema de Proveedores: quitaría los descuentos.

### 6.3 Deténgase y avíseme si

- «Tests» queda en rojo sobre la etiqueta, o el ensayo o el respaldo están en rojo;
- la etiqueta `sitio-` de 4.1 no muestra `77a5fb1`;
- `version.json` muestra otro commit pasados 10 minutos;
- la Caja, la Cocina, Inventario o Inicio no cargan;
- una Caja deja ventas «sin guardar todavía» que no se vacían (nunca borren los datos del sitio: esas ventas están en
  la tableta);
- una entrega sube el inventario dos veces, o un pago aparece dos veces;
- una persona con la entrada marcada no puede identificarse con su PIN correcto, o la página recibe a nombre de alguien
  que no está en turno;
- cualquier comprobación de esta guía dice otra cosa.

---

## Lo que usted debe aprobar o decidir

**Hecho el 2026-11-08:** las decisiones 1 a 8 constan por escrito en el chat y en E-43 (`docs/DEPENDENCIES.md`): la 1
palabra por palabra, con dos indicaciones suyas al equipo (cada recepción queda a nombre de quien la registra; los PIN
no se comparten); la 4 como **A**; la 7 aprueba el procedimiento sin autorizar todavía la instalación; el contador conserva el nivel dueño de la 3 y la 6.
El mismo día: la vista previa aprobada (versión 4, 1.4) y el equipo avisado (1.8). Quedan 9 a 16; la etiqueta (11)
espera su autorización.

1. **La garantía de «Recibe en este aparato» y su límite (la condición, 1.7).** Lo construido y probado, con su
   corrección del 2026-11-07: una persona en turno recibe sin escribir un código en cada entrega, pero la identificación
   es individual y corta. **Su propio PIN en ese aparato** («Estoy en turno aquí»; si todavía no marcó entrada, el mismo
   PIN la marca), o el PIN que escribió en «¿Quién cobra?» de la Caja de ese aparato **hace menos de 15 minutos**, vale
   **15 minutos** y se extiende con cada entrega que registra. Pasado ese tiempo, el servidor contesta «idle» a
   cualquier uso (las listas, abrir un pedido, recibir) y la página vuelve a pedir el PIN **de esa misma persona** (su
   nombre ya elegido; lo que tenía escrito vuelve). El servidor comprueba en cada entrega que **esa** persona escribió
   **su propio** PIN en **ese** inicio de sesión del aparato durante **su** turno abierto (que su PIN no cambió, que
   sigue activa, que no marcó la salida, que no pasaron 16 horas) y que su PIN o su última entrega es de hace menos de
   15 minutos. Un «¿Quién cobra?» escrito antes de marcar la entrada, antes de un cambio de PIN o hace más de 15 minutos
   no sirve. Nadie recibe porque otra persona tenga el turno abierto, y **nadie recibe a nombre de la última persona que
   se identificó en un aparato compartido**. **El límite que queda:** dentro de esos 15 minutos, un aparato que se dejó
   en el mostrador sigue siendo esa persona (la barra la nombra: «Recibe: Luis · PIN vigente hasta las 10:45», y «¿No es
   usted? Cambiar» está a un toque); después, nadie. Recomendado: aprobarlo, con la costumbre de mirar el nombre de
   arriba. Esto reemplaza la regla de D-041 (recibir con el PIN de un encargado).
2. **El efectivo ya no se ofrece en Proveedores.** Sus dos formas de pago son SINPE y tarjeta (débito o crédito). La
   ventana de recibir de Inventario ofrecía «Efectivo de la caja registradora» (un retiro de la gaveta documentado con la
   factura) y
   Contabilidad ofrecía además caja fuerte y caja chica; Contabilidad las sigue teniendo, como hoy. Los retiros de la
   gaveta que la página anterior hizo al recibir y todavía no tienen factura se documentan solos al registrar esa
   factura en Proveedores («Pagado en caja ₡X»). **El riesgo:** si alguien paga en efectivo desde la Caja («Entrada o
   salida de dinero de la caja» → «Sale: pago de una compra o a un proveedor»), Proveedores no lo sabe y el pedido sigue
   en «Pago pendiente» hasta que ese pago se registre en Contabilidad: nadie debe pagarlo otra vez por SINPE.
   Recomendado: aprobarlo así; si el efectivo hace falta en Proveedores, es una versión nueva.
3. **El SINPE del proveedor, visible a los encargados.** D-057 sacó los datos de pago de la tableta del encargado. El
   campo nuevo «SINPE (número y nombre para transferencias)» se ve en la ficha con un PIN de encargado (para pagar hace
   falta) y en la ventana de pago, nunca en la lista; solo lo cambian un PIN con puesto de dueño, usted con el código del
   teléfono o el contador, y cada cambio queda anotado con el antes y el después («SINPE cambiado el … por …», 30 días en
   la ficha). Las «notas de pago» de Contabilidad («Cómo se le paga (Contabilidad)») siguen solo para el contador y para
   usted con el código. Si nadie del equipo tiene puesto de dueño con PIN (1.5), hoy solo el contador puede escribirlo:
   mientras tanto la ficha no muestra SINPE y los pagos funcionan igual. Recomendado: aprobarlo.
4. **La recepción sin pedido se queda en Inventario.** Existencias → «Recibir» (algo que llegó sin pedido, con el PIN
   del encargado) sigue igual. Con la contabilidad automática encendida, esa entrada le debe al proveedor en los libros sin
   una entrega que se pueda facturar en Proveedores (el hueco conocido de D-037). **A**, construido: dejarla como está.
   **B**: llamarla «Entrada sin pedido» y explicar que las compras a proveedores van por Proveedores (un cambio pequeño en
   una versión nueva). **C**: quitarla (todo por pedido). Recomendado: A por ahora; B si se usa para compras a
   proveedores.
5. **Los libros: la cuenta 1160 y la entrega después del cierre (A-15, información para el contador).** Cada pago de
   Proveedores pasa primero por 1160 «Anticipos a proveedores» y se aplica a la factura cuando existe; una entrega
   registrada en Proveedores después de cerrar la caja del día entra en el asiento de ese día en el acto (solo con la
   contabilidad automática encendida). No es una condición (D-042): compártalo con el contador cuando quiera, con la
   lista «Lo que debe confirmar el contador» de abajo.
6. **Más de lo que se debe, solo el dueño.** Un encargado no puede registrar un pago mayor que el saldo (con la
   tolerancia de IVA antes de la factura, más ₡1): contesta con el saldo. Solo un PIN con puesto de dueño, usted con el
   código del teléfono o el contador pueden registrarlo, con un motivo («Es un pago de más (queda a favor)»), y queda «a
   favor». Lo mismo para **anular** un pago de Proveedores, y para todo lo que dejaría al proveedor debiéndole al café
   (cancelar un pedido ya pagado, bajarle cantidades, cerrar lo pendiente o corregir una entrega a menos): un encargado
   recibe «Eso dejaría ₡X a favor del café…» y no cambia nada. Una factura la anulan solo usted con el código o el
   contador.
   Hoy, con E-06 abierta y si nadie del equipo tiene puesto de dueño con PIN (E-42 1.7), en la práctica solo el contador
   (E-18). Recomendado: aprobarlo así.
7. **Dos migraciones en lugar de una.** Una sola 0039 pesaba más de los 128 KiB que el ensayo acepta, así que va
   partida: la 0039 (catálogo, pedidos, recepción, sesiones, alertas) y la 0040 (lecturas, facturas, pagos, 1160), una
   después de la otra en la misma noche (3.3 y 3.5); cada una con su reversión, que se pegan al revés (6.2). Recomendado:
   aprobarlo.
8. **Contabilidad, solo lo necesario para que Proveedores cuadre con ella.** Usted pidió no tocar contabilidad fuera de
   lo estrictamente necesario; esto es lo necesario, y nada más cambia ahí: (a) `supplier_invoice_save`, la función que
   guarda las facturas de proveedor, la redefine la 0040 con dos pasos más: espera a que termine una corrección de
   entrega en curso, y si una entrega tiene una corrección de Proveedores todavía sin factura, la factura la lleva con
   ella (si no, esa corrección quedaría sin factura para siempre); la reversión de la 0040 le devuelve su texto exacto;
   (b) en la página de Contabilidad, al guardar una factura y antes de registrar un pago se aplica primero lo pagado en
   Proveedores (para no pagar dos veces), anular un pago de Proveedores ya aplicado pide confirmación, y la pestaña
   «Auditoría» muestra también lo que se hizo en Proveedores con dinero (facturas, pagos, SINPE); (c) por su corrección
   del 2026-11-07, las guardas en el servidor en **todas** las rutas de pago: `supplier_payment_save` (la función que
   registra todo pago a proveedor: el «Registrar pago» de Contabilidad, el recibir-y-pagar de la página de Inventario
   anterior y cualquier llamada directa) la redefine la 0040 con el texto de la 0029 más tres pasos (niega un número
   SINPE vivo de Proveedores; aplica primero a las facturas de ese proveedor lo ya pagado en Proveedores; el tope es lo
   que se debe después de eso), y `expense_pay` (el pago de un gasto a crédito) con el texto de la 0035 más un paso
   (niega ese número SINPE en un pago por banco); dos disparadores son la última defensa, escriba lo que escriba: una
   factura nunca recibe aplicaciones por más de su total y un pago de Proveedores nunca se aplica por más de su monto.
   La reversión de la 0040 devuelve los textos exactos de la 0029 y la 0035 y quita los dos disparadores. Lo que la
   página de Contabilidad hace antes de llamar (b) queda como comodidad: el servidor lo hace de todos modos.
   Recomendado: aprobarlo.
9. **El registro de los descuentos (E-42)**, que sigue pendiente (1.6, D-066).
10. La vista previa privada (1.4).
11. Aprobar el commit de la versión y crear su etiqueta (2.1).
12. Elegir la noche de la activación y quiénes están (1.9).
13. Subir `anonimizar.sql` a `canopy-respaldos` y correr «Ensayo en pruebas» (1.2, 1.3).
14. Aplicar la 0039 y la 0040 en producción con el SQL Editor (3.3, 3.5).
15. Guardar el sitio y publicar la etiqueta con «Publish website» (4.1, 4.2).
16. Solo si hace falta: la vuelta atrás (6.1, y 6.2 solo por una falla de una función).

---

## Lo que debe confirmar el contador

Información (A-15; no es una condición, D-042): compártala con el contador cuando quiera. Lo que debe confirmar:

1. La cuenta **1160 «Anticipos a proveedores»** es de activo y está activa (está en el plan aprobado desde la 0013; la
   0040 se niega si tiene otro nombre, otro tipo o está inactiva, 1.5).
2. Cada pago registrado en Proveedores asienta en su fecha **Dr 1160 / Cr 1110 Banco** (SINPE o tarjeta de débito) o
   **Cr 2160 Tarjeta de crédito por pagar** (tarjeta de crédito), clave `supadv:<id>`.
3. Cuando la factura existe, su aplicación asienta **Dr 2101 Compras por pagar / Cr 1160** el día que se aplica (clave
   `suppay:<id>`); Contabilidad la muestra como «Pago aplicado (Proveedores)».
4. **El saldo de la 1160 = los pagos de Proveedores todavía sin aplicar** (`consistency-check.sql`,
   `advances_ledger_vs_unapplied` = 0; la primera consulta de abajo).
5. Una anulación (de un pago o de una factura) se revierte con asientos nuevos; nada se borra. Una factura anulada
   devuelve a la 1160 las aplicaciones que tenía.
6. El número de SINPE lo escribe quien registra el pago: **no es una verificación del banco**. La transferencia se
   confirma al conciliar el estado de cuenta (Contabilidad → Banco y efectivo).
7. El IVA acreditable (1140) se asienta **solo con la factura**; lo que se calcula antes de la factura es un tope para
   el pago, no una regla de impuestos.
8. Un cierre de mes con saldo en la 1160 es normal: son pagos adelantados a facturas que todavía no llegan (la segunda
   consulta lista los de más de 30 días).
9. Los pagos propios de Contabilidad («Registrar pago», `supplier_payment_save`) aplican primero lo pagado en
   Proveedores a las facturas de ese proveedor y niegan un número SINPE ya registrado allí; también el pago por banco
   de un gasto con ese número (`expense_pay`; decisión 8). Un pago en efectivo desde la Caja no lo ve Proveedores hasta
   que se registre en Contabilidad (decisión 2).

Las dos consultas (solo lectura; SQL Editor, cada una en su «New query»):

```sql
-- solo lectura: el saldo de la 1160 en los libros frente a los pagos de Proveedores sin aplicar (deben ser iguales)
select (select coalesce(sum(l.debit - l.credit), 0) from acct.lines l where l.account = '1160') as saldo_1160,
       (select coalesce(sum(a.amount_crc - coalesce((select sum(p.amount_crc) from public.supplier_payments p
                                                       where p.advance_id = a.id and p.voided_at is null), 0)), 0)
          from public.supplier_advances a where a.voided_at is null) as pagos_sin_aplicar;
```
Esperado: los dos números iguales (`0` y `0` la noche de la activación). Distintos solo si alguien asentó a mano en la
1160, que hoy nadie usa: avíseme.

```sql
-- solo lectura: pagos registrados en Proveedores hace más de 30 días y todavía sin aplicar a una factura
select v.name as proveedor, a.date as fecha, a.amount_crc as monto, a.method as forma, a.reference as referencia,
       a.amount_crc - coalesce((select sum(p.amount_crc) from public.supplier_payments p
                                 where p.advance_id = a.id and p.voided_at is null), 0) as sin_aplicar
  from public.supplier_advances a join public.vendors v on v.id = a.vendor_id
 where a.voided_at is null and a.created_at < now() - interval '30 days'
   and a.amount_crc > coalesce((select sum(p.amount_crc) from public.supplier_payments p
                                 where p.advance_id = a.id and p.voided_at is null), 0)
 order by a.date;
```
Esperado: ninguna fila, o los pagos adelantados cuya factura todavía no se registró (se registra en Proveedores o en
Contabilidad y el pago se le aplica solo).

---

## Registro

**Durante la activación, anote** (sin PIN ni contraseñas): número y hora de «Tests» de la etiqueta, del ensayo y del
respaldo con sus líneas de resumen; el `applied_at` de la 0039 y de la 0040; las celdas de `release-check` (antes y
después), de `production-snapshot` (antes y después), de `backup-account` y de `consistency-check` (antes y después,
con las ocho de Proveedores); los tres números de 3.11; la etiqueta `sitio-` y su commit; los números de «Publish
website» y de «pages build and deployment»; el commit nuevo de `gh-pages` y `version.json`; el resultado de A a H.

**Después**, en un commit normal con su autorización: D-067 y E-43 (que E-43 pase a cerrada), su línea de 1.7 en E-43
(si no entró ya en el commit aprobado), E-42 si me dio su registro (1.6), `docs/MIGRACIONES.md` («hoy en la 0040»),
`docs/CHECKLIST.md`, `docs/PRODUCTION-READINESS.md`, `docs/PRUEBAS.md`, `tests/rehearsal/LIVE_PAGES` (con el nuevo
`gh-pages`) y `tests/pantallas/BASE` con las listas de `tests/pantallas/no-tocar.sh` vacías (la nueva versión pasa a ser
la base, como en D-066). Ese commit dispara «Tests», cuyo paso «The live site is an approved release» comprueba el sitio
publicado.

| Fecha y hora | Etapa y paso | Resultado (o lo que se vio) |
|---|---|---|
| | | |
