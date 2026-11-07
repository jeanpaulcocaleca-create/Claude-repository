# Proveedores: cómo funciona la página (D-067)

Guía para el dueño, los encargados y el personal. La página **Proveedores** (`proveedores.html`) reúne lo que hacían
Inventario → «Pedidos» e Inventario → «Proveedores», y agrega lo que faltaba: el catálogo de cada proveedor, pedir con
casillas, el documento del pedido (Copiar, PDF, Imprimir), recibir por cualquier persona en turno, las facturas y los
pagos por SINPE o tarjeta. Llega con las migraciones 0039 y 0040; hasta que el dueño la active y la publique
(`docs/ACTIVACION-PROVEEDORES.md`, E-43), Inventario sigue como hoy.

Se abre desde Inicio (el recuadro «Proveedores»), desde Inventario (las pestañas «Pedidos» y «Proveedores», el botón
«Pedir a proveedores →» y el «Pedir» de cada artículo de «Antes de que se acabe») y desde el menú de arriba de
Inventario y del Reloj (en la Caja: «Reloj» → «Proveedores»). Necesita internet: sin conexión dice «Sin conexión: no
se guardó. Intente de nuevo.» y conserva lo escrito (solo la Caja vende sin internet).

## 1 · Quién hace qué

| Quién | Cómo entra | Puede | No puede |
|---|---|---|---|
| **Persona en turno** (cualquier puesto) | «Recibe en este aparato» (sección 2): su PIN en «¿Quién cobra?» de la Caja de ese aparato, o en «Estoy en turno aquí», una vez por aparato y por turno | Ver los pedidos por recibir y recibirlos; anotar lo que llegó de más, un precio distinto, el Nº de factura y observaciones; avisar que no llega el resto | Ver totales, pagos, el contacto del proveedor o su SINPE; pedir, editar, cancelar o cerrar pedidos; pagar |
| **Encargado** | En el aparato: «Abrir áreas de dueños» → su nombre y su PIN (15 minutos, como en Inventario) | Todo lo de pedidos: añadir, editar y desactivar proveedores; el catálogo; pedir; el documento; editar, cancelar y cerrar pedidos; recibir (también de más); corregir una entrega; registrar facturas; registrar pagos con **su** PIN hasta lo que se debe; aplicar pagos a facturas; ver el SINPE | Cambiar el SINPE; pagar más de lo que se debe; dejar un pago a favor (cancelar, recortar o cerrar lo pendiente de un pedido ya pagado); anular un pago o una factura |
| **Puesto de dueño con su PIN** | Igual que el encargado, con su PIN | Lo del encargado, y además cambiar el SINPE, registrar un pago mayor que el saldo (con motivo) y anular un pago de Proveedores, con su PIN; dejar un pago a favor (sección 11) | Anular una factura |
| **El dueño con el código del teléfono** | Su ingreso personal con el código | Todo; los pagos sin PIN; anular facturas | – |
| **El contador** | Su ingreso con el código | Pagos: facturas, pagos sin PIN, anular pagos y facturas, cambiar el SINPE; ve «Cómo se le paga (Contabilidad)» | Pedidos, productos y proveedores (la pestaña «Pedir» no aparece) |

En una tableta del café, sin las áreas de dueños abiertas, la página abre **para recibir**. «Abrir áreas de dueños» pide
el PIN de un encargado o del dueño; al terminar toque «Bloquear». Cuando las áreas se cierran (al bloquear o a los 15
minutos) los montos y los datos del proveedor salen de la pantalla y la página vuelve a recibir; lo que estaba escribiendo
(nunca un PIN) vuelve después de escribir el PIN otra vez. En su propio aparato con el código del teléfono, y para el
contador, la sesión se cierra sola a los 30 minutos sin uso (nunca con algo escrito sin guardar); en las tabletas del
café no se cierra sola.

## 2 · Recibir un pedido (cualquier persona en turno)

1. En un aparato del café → «Proveedores» (en la Caja: «Reloj» → «Proveedores»).
2. **Si el aparato ya la conoce en este turno**, arriba dice «Recibe: (nombre) · ¿No es usted? Cambiar · Salir de este
   aparato». La conoce si en **ese mismo aparato**, durante este turno (después de marcar la entrada), escribió su PIN en
   «¿Quién cobra?» de la Caja (no escribe nada más) o ya hizo el paso 3. Nadie recibe porque otra persona tenga el turno
   abierto.
3. **Si no**, «¿Quién recibe?» muestra a quienes tienen la entrada marcada: toque **su** nombre → **su propio** PIN →
   «Estoy en turno aquí» («Listo: usted recibe en este aparato.»). Si todavía no marcó entrada, su nombre está debajo, en
   «¿Todavía no marcó entrada?»: su PIN → «Marcar entrada y empezar» (marca la entrada del Reloj con el mismo PIN).
   - «Tiene un turno abierto desde …; avise a un encargado.»: quedó abierto un turno de otro día; un encargado lo corrige
     en el Reloj. No marca nada.
4. «Pedidos por recibir» → toque el pedido que llegó → «Recibir el pedido Nº n». Cada producto con lo pedido, lo que ya
   llegó, lo pendiente y el precio esperado por presentación («por caja de 12 · esperado ₡…»).
5. **Todo vino bien:** «Todo recibido correctamente» (un toque).
   **Algo distinto:** la cantidad recibida de cada producto con − y + (viene con lo pendiente), el precio de la factura en
   «Precio sin IVA» si es otro, «Nº de factura (si la trae)» y «Observaciones» → «Confirmar recepción».
6. **Llegó menos:** lo que falta queda pendiente («Parcialmente recibido») para otra entrega. Si el proveedor dijo que no
   llega el resto: «Avisar que no llega el resto»; el encargado ve «(nombre) indicó que no llega el resto · Cerrar lo
   pendiente».
7. **Llegó más:** «Llegó más de lo pedido: se anota para el encargado». Entra al inventario solo lo pedido.
8. **Otro precio:** queda anotado para el encargado («Precios distintos que vio (el encargado los revisa)»). No cambia
   el costo del inventario ni el precio del proveedor.
9. Al final, un resumen: lo recibido, lo que faltó, lo anotado. «Recibir otro pedido» para seguir.

**Nunca dos veces:** si otra persona registró una entrega del mismo pedido en otro aparato un momento antes, la página
dice «Otra persona registró una entrega de este pedido hace un momento. Revise lo pendiente.» y muestra lo que queda.
Un toque doble o una conexión que se corta guarda una sola entrega. Lo escrito se conserva si la página se recarga. Si
la conexión se cortó justo después de guardar, al volver dice «Su entrega anterior ya quedó guardada. Revise lo que
falta.»: reciba solo lo pendiente. Si dice «La Caja está usando esos productos en este momento. Intente de nuevo en un
momento.», no se guardó nada: toque otra vez en unos segundos (la entrega le cede el paso a la venta).

**Cuándo vuelve a pedir el PIN:** al marcar la salida, si su PIN cambió o la desactivaron, si otra persona se identificó
en ese aparato («¿No es usted? Cambiar»), 16 horas después de su entrada, o con «Salir de este aparato». Si el aparato
cierra la sesión y vuelve a entrar con la contraseña del café, la página recupera sola a quien recibía (no si se usó en
otro aparato en los últimos 2 minutos, ni más de 6 veces en una hora).

**El límite (una decisión del dueño, E-43):** la página recibe a nombre de la **última persona que se identificó en ese
aparato**. Antes de recibir, mire el nombre de arriba; si no es el suyo, «¿No es usted? Cambiar». En la Caja, si cambia
quien cobra, Proveedores sigue con la persona anterior hasta que ella marque la salida o alguien toque «¿No es usted?
Cambiar».

## 3 · El centro (la primera pantalla de los encargados)

- **«Antes de que se acabe»:** las alertas de inventario (las 6 más urgentes, agrupadas por proveedor; «Ver todas (n)»): el
  artículo, su estado («Agotado», «Inventario bajo», «Por acabarse») y su proveedor preferido, o «Sin proveedor». Si ya
  está pedido: «Ya pedido: 2 × caja de 12 (Nº 41)». Al tocarla se abre la ficha del proveedor preferido con el artículo
  marcado en dorado y la cantidad sugerida, **sin marcar la casilla** (se marca al tocarla). Sin proveedor, o con uno
  inactivo: «Asociar proveedor» (elija a quién se lo compra; la alerta abrirá ese proveedor).
- «Buscar un proveedor», «Añadir proveedor», y los filtros «Activos», «Inactivos» y «Por recibir».
- Cada proveedor: nombre, contacto, teléfono y sus avisos: «N por recibir», «Parcialmente recibidos: N», «Borrador»,
  «Debe ₡X», «Saldo a favor ₡X», «Pago sin aplicar de hace más de 30 días».
- «Por recibir»: todos los pedidos que esperan entrega. Un pedido viejo sin proveedor: «Sin proveedor · Asignar».

## 4 · La ficha del proveedor

Arriba: el nombre, el contacto, el teléfono (toque para llamar), WhatsApp (abre el chat; el pedido no se manda solo),
el correo, el **SINPE** y, durante 30 días después de un cambio, «SINPE cambiado el … por …», las notas y «Editar».
El contador ve además «Cómo se le paga (Contabilidad):».

**Editar:** nombre, contacto, teléfono, WhatsApp, correo, SINPE (solo el puesto de dueño, el dueño con el código o el
contador: «Solo el dueño o el contador cambian el SINPE.»; en la tableta, aunque las áreas de dueños estén abiertas con el
PIN de un dueño, al cambiar el SINPE aparecen «Dueño» y «PIN del dueño»: «Cambiar cómo se le paga a este proveedor pide
el PIN de un dueño.»; el cambio queda en la bitácora a nombre de ese dueño), notas y, en «Más», días de pedido, días para entregar y días
de crédito (vacío = 30). «Desactivar»: «¿Desactivar (nombre)? Su historial se conserva.»; sus pedidos abiertos siguen.
Dos proveedores activos no pueden tener el mismo nombre.

Cuatro pestañas: **Pedir** (la primera), **Pedidos**, **Pagos** y **Productos**.

## 5 · Productos: el catálogo de cada proveedor

Cada proveedor tiene su propia lista. Cada producto: el artículo del inventario, el nombre en ese proveedor (opcional),
su código (opcional), la **presentación** («caja de 12»), cuánto trae una presentación («1 caja = 12 unidades»; en
gramos, kilos, mililitros o litros según el artículo), el **precio habitual por presentación, sin IVA**, la cantidad
habitual (opcional) y si es el **preferido**.

- **Un artículo puede venir de varios proveedores, y del mismo en varias presentaciones** (caja de 12 y caja de 24). El
  inventario siempre cuenta en la unidad del artículo: 2 cajas de 12 = 24 unidades.
- **Preferido:** el proveedor que abren las alertas. Es uno por artículo, el mismo «Proveedor» de la ventana del
  artículo en Inventario. «Preferido» en otro proveedor lo cambia (la ficha dice cuál era).
- **«Añadir producto»** (o «+ Producto nuevo» en Pedir): «Busque primero en el inventario» → «Usar este»; si no está,
  «No está en el inventario: un artículo nuevo» (nombre y unidad; se crea en Inventario con existencias 0). Después la
  presentación, cuánto trae y el precio.
- **«Retirar»** saca el producto de ese proveedor (su historial se conserva); «Reactivar» lo devuelve.
- **El precio habitual cambia solo aquí** (o con «Usar ₡X como precio habitual» después de una entrega). Recibir nunca lo
  cambia.

## 6 · Pedir con casillas

En la pestaña **Pedir**: primero lo que se pide seguido, después de la A a la Z; «Buscar un producto».

1. **Marque la casilla** de cada producto: se pone la cantidad sugerida (la de la alerta, si no la habitual, si no la
   del último pedido, si no 1). Cambie la cantidad con − y + o escribiéndola (escribir una cantidad marca la casilla).
   «−» en la mínima desmarca; una cantidad vacía no se pide.
2. Abajo, siempre a la vista: «3 productos · Total estimado ₡45 200 · Crear pedido». El total es sin IVA, a los precios
   habituales. Un producto sin precio habitual pide el suyo («Escriba el precio de …»).
3. Opcional: «Nota para el proveedor»; «+ Producto nuevo» (sin perder lo marcado); **«Repetir último pedido»** (marca lo
   del último pedido no cancelado; si ya hay algo marcado, pregunta «Esto reemplaza lo marcado. ¿Seguir?»; lo que ya no
   está en el catálogo aparece con «Añadir al catálogo»).
4. **«Crear pedido»** → el pedido con su número, abierto como documento. Un toque doble crea uno solo.

**El borrador se guarda solo:** en el aparato al instante y en el servidor un momento después («Borrador guardado
10:42», «Guardando…», «Sin conexión: guardado en este aparato»). Hay un borrador por proveedor, el mismo en todos los
aparatos. Si otro aparato lo cambió: «Este borrador se cambió en otro aparato. El guardado automático está en pausa.» →
«Usar el del otro aparato» o «Unir» (junta los dos, con la cantidad mayor).

## 7 · El pedido

«Pedido Nº 123», el proveedor, la fecha, el estado («Creado», «Parcialmente recibido», «Recibido», «Cancelado»; un
borrador de la página anterior dice «Borrador» y se confirma con «Confirmar el pedido») y, aparte, el pago («Pago
pendiente», «Parcialmente pagado», «Pagado»). Cada línea: producto, presentación, cantidad, precio habitual y subtotal;
después de una entrega también lo recibido y lo pendiente (o «Faltó»). El total estimado y el recibido; la nota.

**Copiar | PDF | Imprimir** (lo que se manda al proveedor, siempre en español):
- **Copiar:** el texto «Pedido Nº 123 · Hanging Garden Café», «Proveedor: …», «Fecha: …», una línea por producto («• 10 ×
  caja de 12 — Leche entera (cód. LE-12)»), la nota y «Por favor indique el Nº 123 en la factura. Gracias.». **Sin
  precios**, sin nombres del personal, sin SINPE ni datos internos. Péguelo en WhatsApp o en un correo («Copiado»).
- **PDF:** el archivo «Pedido-123-(proveedor).pdf» (en el iPad se abre la hoja para compartirlo); en varias páginas si
  hace falta, con «Página n de m».
- **Imprimir:** solo el documento, en A4.
- «Incluir precios» (encendido) decide si el PDF y la impresión llevan precios y total. Ninguno lleva el estado, el pago,
  quién lo pidió ni las entregas.

**Editar** (encargados): cantidades, precios, la × para quitar una línea, «+ Agregar producto», la nota y la entrega
esperada → «Guardar cambios». Después de una entrega se puede cambiar lo pendiente, nunca por debajo de lo que llegó
(«Es menos de lo que ya llegó.»); una línea que ya tuvo entregas no se quita («Ya tiene entregas»). Un pedido recibido o
cancelado solo cambia la nota y la fecha. Si otro aparato lo cambió: «Alguien cambió este pedido hace un momento. Aquí
está como quedó: haga su cambio de nuevo.». Cada cambio queda en «Historial de cambios».

Además: «Recibir», «Cancelar pedido» (solo sin entregas), «Cerrar lo pendiente» (lo que no llegó queda registrado como
faltante; si ya se pagó lo que no llegó, ver «Saldo a favor» abajo), «Corregir una entrega», «Registrar pago», «Duplicar» (abre «Pedir» con lo de ese pedido marcado, para revisarlo y crear uno nuevo) y, para un pedido viejo sin
proveedor, «Asignar proveedor». Abajo: las entregas, los pagos y el historial.

## 8 · Recibir (encargados) y corregir

La misma pantalla de la sección 2, con su nombre. Además:
- el precio que escribe **se registra** como el costo de esa entrega; si es muy distinto del esperado: «¿Seguro? Se
  esperaba ₡X» → «Sí, el precio es correcto»;
- **más de lo pedido:** «Llegó de más (lo autorizo)» lo registra;
- **lo que falta:** «¿Llega el resto después?» → «Sí, queda pendiente» o «No, cerrar el pedido»;
- al final: el resumen con las diferencias de precio («Usar ₡X como precio habitual»), «Registrar factura» y
  «Registrar pago».

**Corregir una entrega** (si se contó mal): en el pedido, «Corregir una entrega» → la entrega → la diferencia por línea
(−2 si llegaron 2 menos de lo registrado, +1 si llegó uno más) → el motivo → «Guardar la corrección». Es una entrega
nueva con la diferencia: nada se borra. Solo mientras esas entregas no tengan factura («Esa entrega ya tiene su factura:
no se puede corregir aquí.»).

## 9 · Precios

- **El precio habitual** del catálogo (sin IVA) es el que usa el pedido; **recibir nunca lo cambia**.
- **El precio de la entrega** es el que entra al costo del inventario: el esperado, o el que escribió un encargado. Si un
  encargado escribe otro precio, el «Costo por paquete» del artículo en Inventario pasa a ese último precio, como antes.
- **El precio que escribe una persona en turno** solo se anota para el encargado: no entra al costo ni cambia nada.
  Lo que una persona escribió en el formulario de recibir y dejó sin confirmar no pasa al formulario de otra (otro
  empleado, o un encargado que abre las áreas después en ese aparato): empieza desde el pedido, con el aviso «Lo que otra
  persona escribió en este aparato para este pedido no se usó. Cuente la entrega otra vez.».
- Para cambiar el precio habitual: Productos, o «Usar ₡X como precio habitual» en el resumen de la entrega.

## 10 · Facturas

En **Pagos** (o desde el resumen de una entrega): «Registrar factura» → marque las entregas que trae la factura (una
corrección de una entrega aparece dentro de ella, «corregido −₡X → ₡Y», y va con ella; nunca con otra entrega del mismo
pedido) → el Nº (si lo escribe antes de marcar las entregas, se queda) (el que se escribió al recibir, o vacío: queda «S/N» con la fecha) →
la fecha → la moneda (colones, o dólares con su tipo de cambio de 100 a 2000) → el **subtotal sin IVA** (viene con el
valor recibido) → el **IVA**: «13 %», «Sin IVA» o escrito; **usted elige**, el sistema no decide el IVA → el
vencimiento (por omisión, la fecha más los días de crédito del proveedor, o 30) → «Guardar factura».
- Si la página anterior pagó esas entregas con efectivo de la caja registradora: «Pagado en caja ₡X»; ese retiro queda
  documentado con esta factura.
- La diferencia entre lo recibido y la factura va a «Ajustes de inventario» como siempre (D-014); el IVA, al crédito
  fiscal, solo con la factura.
- **Anular una factura:** solo el dueño con el código o el contador («Anular factura»). Los pagos de Proveedores que
  tenía vuelven a quedar sin aplicar (y no se vuelven a aplicar a esa factura); un pago hecho en Contabilidad se anula
  primero allá.

## 11 · Pagos

En **Pagos**: «Saldo pendiente» o «Saldo a favor», cada pedido con lo que se debe y lo pagado, las facturas abiertas, las
entregas sin factura y la lista de pagos (los de Contabilidad aparecen también, solo para ver).

**«Registrar pago»:**
1. **Pedido:** el elegido, otro, o «Sin pedido (a cuenta)».
2. **Cómo se pagó:** **SINPE** o **Tarjeta** («Tarjeta de débito» o «Tarjeta de crédito»). **El efectivo no está aquí:**
   se registra en Contabilidad, como hoy.
3. **Monto** (viene con el saldo) y **fecha** (hoy; hasta un año atrás, nunca adelante).
4. **SINPE:** el «Número de confirmación SINPE» es obligatorio (de 4 a 40 letras o números). El mismo número no se
   registra dos veces, ni para otro proveedor ni escrito con espacios o guiones: «Ese número de SINPE ya está registrado
   (proveedor, fecha, monto).». **Tarjeta:** «Referencia (opcional)»; un pago igual a uno de hace unos minutos pregunta
   «¿Es otro pago distinto?» → «Sí, es otro pago».
5. **Quién lo registra:** su nombre y su PIN (encargados y puesto de dueño). El dueño con el código y el contador no
   escriben PIN.
6. «Guardar pago». Si todavía no hay factura: «Pago guardado · queda esperando la factura»; cuando la factura se
   registra, aquí o en Contabilidad, el pago se le aplica solo.

- **Antes o después** de recibir y de la factura. Antes de la factura, el saldo incluye una tolerancia de IVA (la tarifa
  habitual del proveedor, o 13 %): dice «estimado, IVA incl.». No es una regla de impuestos: el IVA real llega con la
  factura.
- **Más de lo que se debe:** «Es más de lo que se debe: el saldo es ₡X.». Solo el puesto de dueño con su PIN, el dueño
  con el código o el contador pueden marcar «Es un pago de más (queda a favor)» con un motivo; queda como «Saldo a favor».
- **Saldo a favor por cancelar o recortar:** si un pedido ya pagado se cancela, se le baja la cantidad o el precio, se
  cierra lo pendiente o se corrige una entrega hacia abajo, ese pago puede quedar a favor del café con el proveedor. Eso
  también es del dueño: un encargado ve «Eso dejaría ₡X a nuestro favor con este proveedor (un pago ya hecho). Solo el
  dueño puede hacerlo.» y no cambia nada. Se mide con todo lo del proveedor: si otra factura abierta absorbe ese pago, no
  queda nada a favor y el encargado sí puede. La bitácora guarda cuánto quedó a favor.
- Cada pedido: «Pago pendiente», «Parcialmente pagado» o «Pagado».
- Después de pagar un pedido con entregas sin factura: «Registrar factura (S/N si no trae)».
- **Cómo queda en los libros:** el pago entra primero a la cuenta 1160 «Anticipos a proveedores» en su fecha (contra
  Bancos, o la tarjeta), y se aplica a la factura de su pedido cuando la factura existe (contra Compras por pagar). Un
  pago sin pedido se aplica a las facturas abiertas más antiguas. Si hay pagos sin aplicar y facturas abiertas (por
  ejemplo, una factura guardada en Contabilidad): «Aplicar a facturas abiertas».
- **Anular un pago:** «Anular» en la lista, con el motivo: el puesto de dueño con su PIN, o el dueño con el código o el
  contador sin PIN. Se revierte con asientos nuevos; nada se borra.

## 12 · Alertas de inventario

Salen de los niveles de siempre de cada artículo (el punto de reorden y el nivel par de Inventario, con el uso de los
últimos 30 días y los días para entregar del proveedor): «Agotado», «Inventario bajo», «Por acabarse». La cantidad
sugerida es la de esa misma regla menos lo que ya está pedido a cualquier proveedor, en presentaciones (redondeada hacia
arriba); si lo ya pedido cubre lo que hace falta, sugiere 0. Lo pedido se muestra como «Ya pedido: … (Nº …)». Un
artículo agotado o bajo sin nada pedido sugiere al menos su cantidad habitual (o 1). Las ven los encargados, no la
persona en turno.

## 13 · Qué queda registrado

- **En la bitácora:** cada cambio de un proveedor (antes y después; el SINPE aparte), de un producto (precio,
  presentación, activo), del preferido; cada pedido creado, editado, cancelado, cerrado o confirmado; **cada entrega**
  (quién, con «(en turno)» si fue una persona en turno, el aparato, lo pedido, lo recibido antes y ahora, lo pendiente,
  los precios esperado, registrado y visto, lo que llegó de más); cada corrección, factura, pago, aplicación y anulación;
  cada sesión «Recibe en este aparato» (cuándo empezó y terminó, nunca el PIN ni el código de la sesión).
- **Nada se borra:** un pedido cancelado, un producto retirado o un proveedor desactivado se conservan; una corrección es
  una entrega nueva; una anulación, un asiento nuevo.
- **El inventario** sube solo con las entregas, nunca dos veces.
- **Los libros, como hoy:** las entregas entran en el asiento del día (inventario contra compras por pagar) al cerrar la
  caja; una entrega registrada en Proveedores después de cerrar la caja del día entra en ese asiento en el acto (con la
  contabilidad automática encendida). La factura asienta el IVA y la diferencia de precio; los pagos, por la 1160 (A-15).

## 14 · Límites

- Necesita internet.
- «Recibe en este aparato» recibe a nombre de la última persona que se identificó en ese aparato (sección 2).
- El efectivo no se registra en Proveedores: va por Contabilidad. Un pago en efectivo desde la Caja («Entrada o salida
  de dinero de la caja» → «Sale: pago de una compra o a un proveedor») no aparece en Proveedores hasta que se registre en
  Contabilidad: no lo pague otra vez por SINPE.
- Lo que llega **sin pedido** se recibe en Inventario → Existencias → «Recibir», como hoy; no aparece como pedido aquí.
- No hay fotos, archivos ni lectura automática de facturas (D-042); el pedido no se manda solo por WhatsApp ni por
  correo: se copia o se manda el PDF.
- Una fecha de entrega esperada se puede cambiar, no borrar.
- Una entrega que ya tiene factura no se corrige aquí: primero se anula la factura (el dueño con el código o el
  contador).
- Una entrega de la página anterior de un artículo que estaba en dos líneas del mismo pedido no se corrige aquí («Esta
  línea de una entrega antigua no se puede corregir aquí.»); una corrección a menos no pasa de lo que trajo esa entrega.
- Si una venta está usando esos productos justo en ese momento, la entrega contesta «La Caja está usando esos productos
  en este momento…» y se toca otra vez.
