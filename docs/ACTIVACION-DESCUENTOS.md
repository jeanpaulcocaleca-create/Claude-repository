# Activar los descuentos de Caja (D-065, migración 0038) · E-42

Esta guía la sigue el dueño, paso a paso. Claude preparó y probó todo en desarrollo, en la base de pruebas local;
**no aplicó nada en producción ni publicó nada**. Cada paso que cambia producción lo hace usted, cuando lo decida. Las
reglas del repositorio (`CLAUDE.md`) no me dejan publicar, crear etiquetas `v*` ni tocar la base de producción. Pégueme
cada resultado que pide la guía y yo lo compruebo antes de que siga.

**Qué se activa:** la ventana de descuentos nueva de la Caja, como en su imagen (cuatro botones, teclado fijo,
«Autorizar descuento»), las cajas registradas para descuentos, el informe «Descuentos por categoría» y la migración
**0038**. La Cocina, el menú QR, la TV, las pantallas V2 y las demás páginas quedan byte por byte como en la versión
publicada hoy (`v2026.11.03-1`); lo comprueba «Tests» en cada ejecución.

| Pieza | Qué hace | Archivo |
|---|---|---|
| 0038 · descuentos de Caja | Cuatro descuentos con la tasa fijada por el servidor (Empleado 30 %, Local 10 %, Huésped 10 %, Guía Turista 100 %); se autorizan solo con el código, sin lista de nombres; un descuento de Empleado por persona y por día; solo las cajas registradas prueban códigos, cada una con su propia cuenta de errores; la ventana anterior queda detrás del ajuste `pos_free_discount` (encendido); Guía Turista detrás de `pos_discount_guia` (apagado, A-13). Agrega columnas, dos tablas (`discount_tills` y `discount_pin_shared`) y funciones; reemplaza en su lugar `approve_discount`, `tab_set_discount` y `_order_discount_check`. **Ningún registro existente cambia**, ni los impuestos, las tarifas o la contabilidad; ninguna regla fiscal se activa | `supabase/migrations/0038_descuentos_caja.sql` |
| La Caja | La ventana «Aplicar descuento», el ticket y el recibo sin porcentaje, las cuentas («Cobrar después»), «Registrar cortesía», la línea de descuentos en «¿Qué dispositivo es este?» | `website/pos.html`, `website/lang.js` |
| Reloj de marcas → Bitácora de aprobaciones | El bloque «Cajas para descuentos» (registrar, reanudar, quitar, reemplazar), «Devolver el cupo del día», las líneas nuevas de la bitácora | `website/time.html` |
| Ventas | «Descuentos por categoría» y «Descargar descuentos (CSV)» | `website/sales.html` |
| Inicio → Ajustes del sistema | Los dos ajustes nuevos con su nombre en español | `website/home.html` |
| Contabilidad | `descuentos.csv` en el paquete del mes (una base sin la 0038 lo omite; si los descuentos no se pueden leer, el paquete lleva `descuentos-NO-INCLUIDO.txt` en su lugar y la pantalla lo dice) | `website/contabilidad.js` |
| Herramientas del dueño (SQL Editor) | Apagar o encender la ventana anterior; reanudar todas las cajas; quitar todos los registros; quitar todos los bloqueos de PIN | `supabase/tools/descuento-libre-apagar.sql`, `descuento-libre-encender.sql`, `descuento-cajas-reanudar.sql`, `descuento-cajas-quitar-todas.sql`, `pines-desbloquear.sql` |
| Reversión | Devuelve las tres funciones a su texto anterior y quita las nuevas; no borra ningún dato | `supabase/tools/reversion-0038.sql` |

**No incluye (y no se enciende con esta guía):** la cortesía Guía Turista, que nace **apagada** hasta la respuesta del
contador (A-13, sección 7); apagar la ventana de descuento anterior, que es **su** último paso y cuando usted quiera
(4.6); una migración posterior que más adelante retira esa ventana (D-066: la 0039 es la de Proveedores); ningún cambio de cuentas de ingreso, PIN o permisos
(E-05 y E-06 siguen como están); nada de impuestos, facturación electrónica ni planilla.

**La versión:** el último commit de la rama `claude/descuentos-caja`, con «Tests» en verde (PR #7, en borrador): el
que le paso en el chat, con su código completo, cuando le pida aprobarlo (1.1). **Punto de partida y de regreso:** la
base en la 0037 y el sitio en `v2026.11.03-1` (commit `adb19ee`, `gh-pages` `44a0dab`).

**Qué se probó (en desarrollo, nunca en producción):** las pruebas SQL `480_descuentos`, `481_descuentos_regla5`,
`482_descuentos_cupo`, `484_descuentos_cuentas`, `485_descuentos_cajas`, `486_descuentos_informe`, `490_descuentos_iva`
y `500_reversion_0038` (2270 comprobaciones), las pruebas con dos conexiones a la vez
(`tests/sql/concurrency-descuentos.sh`, 53 comprobaciones), las de navegador de la ventana nueva (`400_descuentos`,
`401_descuentos_cuentas`, `402_descuentos_cajas`, `403_descuentos_informes` y `404_descuentos_red`: 63 pruebas) y toda
la batería de «Tests» (en desarrollo, el 2026-11-04: 56 de 56 pruebas SQL, que son los 55 archivos y la de dos
conexiones, y las 315 pruebas de navegador: en la última corrida completa una de recetas falló una vez por una
comprobación intermitente ya conocida y pasó las tres veces que se repitió), con el ensayo de la ventana anterior y de las páginas publicadas hoy
sobre una copia con la 0038.

**En orden:**

| Etapa | Qué | ¿Toca producción? | Cuándo | Tiempo |
|---|---|---|---|---|
| 0 | Qué cambia para el personal: leerlo y avisar al equipo | No | Antes de todo | 20 min |
| 1 | Antes: pruebas, archivo del ensayo, ensayo, vista previa, PIN, **su confirmación de la regla 5** | No | Días antes o el mismo día | 1–2 h |
| 2 | La etiqueta y sus pruebas | No | El día de la activación, entre las 05:00 y las 23:00 | 30 min |
| 3 | Después del cierre: respaldo, fotos, la 0038 y sus comprobaciones | Sí (la base) | Café cerrado, desde las 19:30 | 20 min |
| 4 | Guardar el sitio, publicar, registrar cada caja; al final y cuando usted quiera, apagar la ventana anterior | Sí | Seguido de la etapa 3 | 30–45 min |
| 5 | Comprobaciones en el café, sin ventas de prueba | No | Seguido de la etapa 4, y al día siguiente | 15 min |
| 6 | Vuelta atrás (solo si la necesita) | Sí | Antes de abrir el café | 10–20 min |
| 7 | Guía Turista, más adelante (A-13) | Sí (un ajuste) | Cuando responda el contador | 10 min |
| 8 | Herramientas del dueño y procedimiento E-lock (solo si pasa) | Sí | Si hace falta | — |

Monteverde está en UTC−6 todo el año: a las 19:45 del día D en Monteverde son las 01:45 UTC del día D+1. La etiqueta
lleva la fecha D; los registros en UTC llevan D+1. Para las horas use la que da la base, no el reloj de la computadora.

**Detenga y avíseme** si algo sale distinto de lo que dice la guía: copie el resultado (texto o captura sin PIN ni
contraseñas) y no siga.

---

## 0 · Qué cambia para el personal

Léalo al equipo antes de publicar. Hasta que publique (etapa 4), la Caja sigue exactamente como hoy.

**La ventana nueva** (como en su imagen). En la Caja, el botón «Descuento» del ticket, o «Descuento» en una cuenta
abierta, abre «Aplicar descuento»:
- arriba: «Seleccione el tipo de descuento y autorícelo con el código de encargado.» (con Guía Turista: «…con el código
  del dueño.») y una línea pequeña con el pedido («Pedido ₡12 500») o la cuenta;
- a la izquierda, **cuatro botones**: «Empleado», «Local», «Huésped» y «Guía Turista». **Ningún porcentaje** en la
  pantalla, el ticket ni el recibo: la tasa la fija el servidor. El botón elegido se pone verde;
- a la derecha: el paso («Elija el descuento», «Código de empleado», «Código de encargado», «Empresa del guía
  turístico», «Código del dueño»), la casilla del código (solo puntos) y el **teclado fijo** 1–9, 0 y ⌫ (borra un
  número; no hay «Limpiar»);
- abajo, siempre en el mismo lugar: «Cancelar» (no aplica nada) y **«Autorizar descuento»** (también Enter). En el
  primer paso de Empleado y de Guía, «Autorizar descuento» solo pasa al paso siguiente: todavía no envía nada;
- una sola línea de mensajes, en rojo, debajo de la casilla. Nada se mueve en la ventana;
- para volver al primer paso se toca otra vez la categoría (no hay botón «Volver»).

**Quién autoriza cada uno** (el código es el mismo PIN que cada persona usa en el Reloj):

| Descuento | Pasos | Autoriza |
|---|---|---|
| Empleado | 1 «Código de empleado»: el empleado escribe el suyo → «Autorizar descuento» · 2 «Código de encargado» → «Autorizar descuento». **Los dos códigos** van juntos en una sola consulta al servidor | Un encargado (o el dueño), nunca para sí mismo: «Un encargado no puede autorizar su propio descuento.» El dueño no recibe el descuento de empleado |
| Local | «Código de encargado» → «Autorizar descuento» | Un encargado o el dueño |
| Huésped | Igual que Local | Un encargado o el dueño |
| Guía Turista | **Apagada** por ahora: al tocarla dice «La cortesía Guía Turista espera la confirmación del IVA por el contador (A-13).» y no envía nada. Cuando se encienda (sección 7): 1 «Empresa del guía turístico» (con el teclado del aparato; el teclado numérico queda atenuado) → 2 «Código del dueño» | Solo el dueño |

**Lo que no cambia para nadie:** sin un descuento se vende igual que hoy, también sin internet. Un descuento necesita
internet para revisar los códigos («Un descuento necesita internet para revisar los códigos.»); sin internet se cobra
a precio completo. Un descuento ya autorizado en el ticket viaja con la venta guardada sin internet.

**Con un descuento puesto:**
- el ticket muestra «Descuento Empleado» (con el nombre del empleado), «Descuento Local», «Descuento Huésped» o
  «Cortesía Guía Turista» (con la empresa) y el monto; el recibo dice, en los dos idiomas, por ejemplo «Descuento Local ·
  Local discount», sin porcentaje;
- **las líneas del pedido quedan fijas**: cambiar algo dice «Quite el descuento para cambiar el pedido.»; la × del
  descuento lo quita y libera las líneas. Nunca dos descuentos: «Este pedido ya tiene un descuento. Quítelo primero.»;
- la autorización dura 25 minutos en la Caja (30 en el servidor): después dice «La aprobación del descuento tiene más
  de 25 minutos. Pídala de nuevo.»;
- **«Registrar cortesía»** (solo con Guía Turista encendida): el pedido entero queda en ₡0 y se cierra con ese botón,
  sin cobro; el recibo dice «Cortesía · Courtesy»;
- con un pedido con descuento en el ticket, si se toca «Agregar» en una cuenta abierta y esa cuenta se cierra mientras
  tanto (por ejemplo, se paga en otro aparato), el pedido con descuento vuelve tal como se autorizó y lo tocado **no se
  le suma**: «Esa cuenta ya fue pagada. · Este pedido tiene un descuento, así que los productos no se agregaron:
  cóbrelos después de esta venta.» Cobre ese pedido y después toque esos productos en una venta nueva (usted puede
  elegir otra manera: «Lo que usted debe aprobar o decidir», punto 16).

**Cuentas («Cobrar después»):** el descuento cubre la cuenta entera y **solo antes de cualquier pago** («Un descuento
cubre toda la cuenta: solo se da antes de cualquier pago.»). Lo que se agregue después se cobra completo («Lo nuevo se
cobra completo. Para incluirlo, quite el descuento y autorícelo de nuevo.»); una cuenta de cortesía no acepta nada más
(«Esta cuenta es una cortesía: cobre lo nuevo en otro pedido.»). Quitar el descuento («Quitar el descuento») sin nada
pagado: se confirma «¿Quitar el descuento de esta cuenta?», sin PIN. Después de un pago: «Quitar el descuento de una
cuenta pagada en parte», con el motivo, el encargado y su PIN; con Empleado la Caja dice «Descuento quitado. El cupo
del empleado sigue usado hoy: ya se hizo un pago, así que no se puede devolver.»

**El cupo diario del descuento de Empleado (su ajuste 3):**
- uno por persona y por día de Costa Rica. Un segundo intento dice «Descuento diario ya utilizado» (y, si el primero
  todavía no se usó, «Sin usar todavía en (aparato): se libera a las HH:MM.»);
- **una venta cobrada lo gasta**, y entonces el cupo vuelve **solo** con una **anulación válida** de esa venta: la hace
  un encargado que no es el beneficiado y no quedan partes pagadas. El cupo vuelve solo, y el siguiente descuento de ese
  día avisa «Segundo descuento de empleado hoy para (nombre): el anterior lo anuló (encargado).» Una anulación hecha por
  el mismo beneficiado, una con partes pagadas, o una devolución de dinero, no devuelven el cupo; para una venta cobrada
  tampoco aparece «Devolver el cupo del día»;
- **no gastan el cupo:** una autorización que nunca se usó (vence a los 30 minutos, o la suelta la Caja: con la ×,
  con «Vaciar pedido», o al intentar cobrarla después de 25 minutos, cuando dice «La aprobación del descuento tiene más
  de 25 minutos. Pídala de nuevo.»);
- **sí lo gastan, hasta «Devolver el cupo del día»:** un descuento que no cobró nada, es decir, quitar el descuento de
  una cuenta sin nada pagado, o cancelar esa cuenta sin nada pagado. Al quitarlo, la Caja lo dice: «Descuento quitado.
  El cupo del empleado sigue usado hoy; un encargado puede devolverlo en la bitácora de aprobaciones.» Solo en estos dos
  casos, Reloj de marcas → Bitácora de aprobaciones muestra la línea «El descuento de empleado sigue contando» con «un
  encargado puede devolverlo» y el botón **«Devolver el cupo del día»**: un encargado elige **su propio nombre** y
  escribe su PIN (nunca el beneficiado: «El empleado no puede devolverse su propio cupo.»), o usted con el código del
  teléfono. Solo el mismo día («Ese día ya terminó.»); para cualquier otro descuento el servidor contesta «Este
  descuento no puede devolver el cupo.». Queda anotado quién lo hizo.

**Cajas registradas (su ajuste 2; reemplaza la pausa para todo el café, que usted rechazó):**
- **solo una caja registrada prueba códigos.** Una caja es una tableta (un inicio de sesión) que un encargado registró
  una vez en Reloj de marcas → Bitácora (sección 4.5). En otro aparato la ventana dice «Esta caja no está registrada para
  descuentos. Un encargado la registra en Reloj de marcas › Bitácora.» y no envía ningún código. La cocina, la TV y los
  teléfonos no se registran;
- la tableta registrada guarda una llave propia: si se cierra la sesión, o vence, al volver a entrar regresa sola a su
  puesto, sin PIN. Solo una tableta nueva, una a la que se le borraron los datos del sitio en el navegador, o una que un
  encargado quitó o reemplazó, necesita registrarse otra vez. **Nunca borren los datos del sitio en una tableta**
  (tampoco por la cola de ventas sin internet);
- **cada caja lleva su propia cuenta de códigos equivocados**, también el código de empleado mal escrito:

  | Códigos equivocados en esa caja | Qué pasa en esa caja |
  |---|---|
  | 1.º y 2.º en una hora | Nada, solo el mensaje («Código de encargado no válido.», «Código de empleado no válido. Escríbalo de nuevo.», «Solo el dueño autoriza este descuento: código no válido.») |
  | 3.º en una hora | Espera **30 segundos**: «Demasiados códigos equivocados en esta caja. Intente de nuevo en 30 segundos.» |
  | 4.º, 5.º, 6.º y siguientes | Espera **1 minuto, 5 minutos, 10 minutos** cada uno: «Demasiados códigos equivocados en esta caja. Próximo intento a las HH:MM; puede cobrar sin descuento.» |
  | **12 en 24 horas** | **Se detienen los descuentos en esa caja**: «Descuentos detenidos en esta caja por códigos equivocados. Un encargado la reanuda en la bitácora.» |

  Desde el 3.º, cuando termina la espera, el mensaje avisa lo que costaría el error siguiente: «Un error más y esta caja
  espera 1 minuto.» (o 5 o 10 minutos), o «Un error más detiene los descuentos en esta caja.». Mientras espera o está
  detenida, «Autorizar descuento» queda apagado y no se envía ningún código. **Las demás cajas
  siguen dando descuentos y todas siguen vendiendo.** Un código correcto no borra la cuenta; las ventanas son de 60
  minutos y de 24 horas corridas (no se reinician a medianoche). Las esperas terminan solas; una caja detenida la reanuda
  **cualquier encargado** en Reloj de marcas → Bitácora → «Cajas para descuentos» → «Reanudar descuentos», con su nombre
  y su PIN (una vez por puesto y dos por café en 24 horas), o usted (sección 8);
- **el código del dueño para Guía Turista no abre nada (su ajuste 1):** solo autoriza esa cortesía. No abre las áreas
  del dueño, no deja ninguna apertura en la tableta, no toca la cuenta de intentos del PIN de nadie; el Reloj, Inicio,
  Ventas e Inventario siguen pidiendo el PIN como antes;
- **ojo con quién mira:** ese código se escribe en el teclado de la Caja, a la vista del personal y del guía. Quien lo
  vea puede escribirlo, con el nombre del dueño, en la casilla de PIN que abre las áreas del dueño en cualquier tableta
  del café, y abrir esas áreas y Ventas durante 15 minutos, también poner PIN nuevos a los encargados en «Equipo» (no
  los ajustes del sistema, que piden su ingreso con el código del teléfono). Algo parecido pasa con el código de un
  encargado escrito en la ventana: abre lo que abre su PIN. Escríbalo sin que lo vean y use un PIN de 6 números (1.5);
- **la regla 5, en sus dos mitades** (usted la confirma en 1.8):
  - **un bloqueo temporal no detiene los descuentos.** Cinco PIN equivocados en una casilla con lista de nombres
    bloquean ese PIN 10 minutos («Demasiados PIN incorrectos. Espere 10 minutos e intente de nuevo.»). En la ventana de
    descuentos el código correcto de esa persona sigue sirviendo en todas las cajas registradas, y la ventana no cuenta
    ni borra ese bloqueo. Las casillas con lista de nombres (también la ventana anterior mientras `pos_free_discount`
    esté encendido) siguen como hoy: ahí ese PIN espera sus 10 minutos;
  - **un PIN revocado o sin permiso nunca aprueba.** El código de una persona desactivada, un PIN cambiado (el
    anterior) o quitado, el de alguien a quien se le bajó el puesto o que no tiene el puesto necesario (un miembro del
    equipo para autorizar; quien no es dueño para Guía Turista) o un código que comparten dos personas no aprueba nada
    en la ventana: cuenta como un código equivocado de esa caja, también si el cambio se guarda en «Equipo» en el mismo
    instante en que se escribe el código. En la bitácora de aprobaciones, donde se elige el nombre, tampoco sirven una
    persona desactivada, un PIN anterior o quitado ni un puesto bajado, y desde la 0033 «Equipo» no deja que dos
    personas activas tengan el mismo PIN (el paso 1.6 cambia los que quedaron de antes). Un PIN nuevo o quitado cierra
    además, en el acto, las áreas del dueño que esa persona tuviera abiertas en otras tabletas;
- si dos personas tienen el mismo PIN (posible solo para quienes se reactivaron entre las versiones 0028 y 0033), cada
  código de ellas cuenta como equivocado, y la bitácora avisa «Código compartido por dos personas: asigne PIN nuevos en
  Equipo.» Por eso el paso 1.6.

**La ventana anterior** (porcentajes y montos, «Aprobar el descuento») sigue funcionando en una tableta que todavía no
se recargó mientras el ajuste `pos_free_discount` esté encendido, igual que hoy, con una diferencia: un motivo que diga
una de las cuatro categorías («Local», «Empleado», «Huésped», «Guía Turista», solo o después de « · ») contesta «Elija
el motivo del descuento.» (sección 6.1, paso 5).

---

## 1 · Antes (no toca producción)

1. **«Tests» en verde.** GitHub → **Actions** → **Tests** → la ejecución del último commit de la rama
   `claude/descuentos-caja`: ✅. Su código debe ser el que le di.
2. **Subir `anonimizar.sql` de esta versión a `canopy-respaldos`, antes del ensayo** (como en E-38 y E-41): el archivo
   `ops/backup/repositorio-respaldos/anonimizar.sql` de esta versión, en la raíz de `canopy-respaldos`, reemplazando el
   que está. Conoce las columnas de la 0038: el nombre del empleado pasa a «Persona», la empresa del guía a «texto», se
   vacía el inicio de sesión de cada aprobación, y se vacían las dos tablas nuevas (`discount_tills`, las cajas
   registradas, y `discount_pin_shared`, quién comparte un código). Con el de la 0037 el ensayo se detiene antes de
   copiar nada («anonimizar.sql no sabe si estas columnas guardan datos de personas…»), como está diseñado.
3. **«Ensayo en pruebas» en verde.** `canopy-respaldos` → **Actions** → **Ensayo en pruebas** → **Run workflow**:
   - «Rama o etiqueta del repositorio de desarrollo a ensayar»: el código completo del commit que le di (o la rama
     `claude/descuentos-caja`);
   - destino `desechable`, vaciar `no`, reinicio `no` → **Run workflow**.
   - Unos 5 minutos. Verde quiere decir: copió producción, la anonimizó y aplicó **solo la 0038**. El resumen dice «the
     copy already had migrations 0000-0037 (production after the launch) …» y «unchanged: … original tables …», sin
     ninguna línea «DIFFERENCE:»; `timings.txt` en el resultado `ensayo-resultados-desechable` dice
     «0038_descuentos_caja … ms». La comparación también exige `pos_free_discount` = `on` y `pos_discount_guia` = `off`.
   - **Las páginas publicadas hoy sobre la 0038** las prueba «Tests» (paso «Migration rehearsal…»), en cada ejecución:
     sobre una copia como producción con todas las migraciones hasta la 0038, la ventana anterior aprueba con el ajuste
     encendido, rechaza un motivo que dice una categoría, se niega con el ajuste apagado, una venta vieja guardada sin
     internet llega con el ajuste apagado y se registra como hoy, un descuento Local en una caja registrada queda ligado
     y marcado si llega tarde, el ajuste vuelve a encendido, y luego las páginas publicadas (`44a0dab`) venden, guardan
     sin internet y marcan sobre esa copia.
4. **La vista previa privada, aprobada** (usted la aprobó el 2026-11-04; queda la prueba en el iPad de abajo): el enlace que le paso en el chat (una página privada de claude.ai). No lee
   ni cambia nada de producción. Mírela en el iPad (Safari) y en la Caja del frente: los cuatro botones, el teclado, los
   mensajes, y **en el iPad, el campo de la empresa de Guía Turista**: acepta texto con el teclado del iPad y ese teclado
   no tapa «Autorizar descuento». Para esto último use la **página de prueba de la ventana** (otro enlace privado que le
   paso en el chat): es la misma ventana, con el mismo diseño, sin servidor; no envía nada y no revisa códigos. Toque
   «Guía Turista», escriba una empresa con el teclado del iPad y mire que «Autorizar descuento» se vea y se pueda tocar.
   Anote lo que quiera cambiar: se ajusta antes de activar.
5. **Recomendado: PIN de 6 números** para los encargados y para quien tenga puesto de dueño (Q6). Cada uno se pone el
   suyo: Reloj de marcas → «Horas y equipo» → con su propio PIN → «Equipo» → «Nuevo PIN» en su propia fila. Un PIN de 6
   números divide por cien la probabilidad de acertar uno, y la página rechaza un PIN que ya use otra persona o uno
   demasiado fácil. (Si otro encargado se lo cambia, se le apaga «Puede abrir los reportes de ventas con su PIN»,
   `docs/ACTIVACION-PINES.md` §6.) Cada PIN nuevo cuenta para el límite de 10 por hora de la cuenta del café.
6. **PIN nuevos para quienes se reactivaron entre las versiones 0028 y 0033 sin PIN nuevo** (podrían compartir el PIN
   con otra persona). Supabase → **SQL Editor** → **New query** → pegar → **Run** (solo lectura; no muestra ningún PIN):

   ```sql
   -- solo lectura: personas activas hoy que se volvieron a activar entre la 0028 y la 0033 sin PIN nuevo,
   -- y que tampoco recibieron un PIN nuevo después
   with g as (
     select a.id, a.at, a.target_id, a.details ->> 'name' as nombre,
            (a.details ->> 'active')::boolean as activa,
            coalesce((a.details ->> 'pin_changed')::boolean, false) as pin_nuevo,
            lag((a.details ->> 'active')::boolean) over (partition by a.target_id order by a.at, a.id) as estaba_activa
       from public.audit_log a
      where a.action = 'staff_save'
   )
   select g.at as reactivada, g.nombre
     from g join public.staff s on s.id::text = g.target_id and s.active
    where g.activa and g.estaba_activa = false and not g.pin_nuevo
      and g.at >= (select applied_at from canopy.migrations where version = 28)
      and g.at <  (select applied_at from canopy.migrations where version = 33)
      and not exists (select 1 from public.audit_log b
                       where b.action = 'staff_save' and b.target_id = g.target_id and b.at > g.at
                         and coalesce((b.details ->> 'pin_changed')::boolean, false))
    order by g.at;
   ```
   Sin filas: no hay nada que hacer. Con filas: a cada persona de la lista, «Nuevo PIN» en «Equipo» (a un miembro del
   equipo se lo pone un encargado; un encargado se lo pone él mismo), antes de la etapa 3.
7. **Guía Turista, para más adelante (solo lectura):**
   `select count(*) as duenos_con_pin from public.staff where active and role = 'owner' and pin_hash is not null;`
   Si es `0`, Guía Turista no podrá usarse ni cuando se encienda, hasta que usted active el código del teléfono en su
   ingreso personal (E-06) y, en «Equipo» con ese código, le dé PIN a un miembro con puesto de dueño. No detiene esta
   activación: Guía Turista queda apagada de todos modos (sección 7).
8. **Su confirmación de la regla 5, en una línea, antes de la etapa 3** (sin ella no se activa). **Hecho: usted la dio
   el 2026-11-04** y quedó copiada palabra por palabra en `docs/DEPENDENCIES.md` (E-42). La línea que se pedía:

   > Confirmo: un PIN bloqueado temporalmente por intentos fallidos en otra pantalla sigue sirviendo en la ventana de
   > descuentos, que no cuenta ni borra ese bloqueo; un PIN de una persona desactivada, cambiado, quitado, o de alguien
   > sin el puesto necesario, nunca aprueba un descuento.

   Por qué: sin esta regla, una sola persona con la contraseña del café podría bloquear a todos los encargados en las
   listas de nombres y así convertir sus códigos correctos en errores en todas las cajas: justo lo que su ajuste 2
   prohíbe. La otra opción (rechazar ese código sin contarlo) le diría a quien adivina que el código es correcto. Si no
   la confirma, no active: la 0038 tendría que rehacerse con la regla anterior, que vuelve a permitir un bloqueo de todo
   el café. La segunda mitad no depende de una elección: está construida y probada (`481_descuentos_regla5` y
   `concurrency-descuentos.sh` 6, también cuando el cambio en «Equipo» se guarda en el mismo instante en que alguien
   escribe el código); su línea confirma que así lo quiere. **Cuándo y dónde:** me la da por escrito en el chat antes
   de la etapa 3; esa es la condición. Se copia palabra por palabra en `docs/DEPENDENCIES.md` (E-42) en el commit de
   después de la activación («Registro»). Si me la da antes de que yo le pase el commit para aprobar (1.1), puede ir ya
   en ese commit, y «Tests» corre sobre él. Nunca en un commit entre la etiqueta y la publicación (2.1).
9. **Avisar al equipo** con la sección 0.
10. **Lista de aparatos que dan descuentos** (normalmente la Caja del frente y el iPad), cada uno con su nombre en
    «Este dispositivo» de la Caja (es el nombre que mostrará la bitácora), y **quién registra**: un encargado registra
    como mucho 2 cajas; para una tercera hace falta otro encargado. Esa noche: usted (GitHub y Supabase) y el encargado o
    los encargados que registren, cada uno con su PIN.

---

## 2 · La etiqueta y sus pruebas (no toca producción)

1. **La etiqueta (el mismo día que va a publicar, antes de las 23:00).** GitHub → **Releases** → **Draft a new release**
   → **Choose a tag**: `vAAAA.MM.DD-1` con la fecha de hoy (si ya existe una de hoy, `-2`) → **Create new tag** →
   **Target**: la rama `claude/descuentos-caja` (el formulario propone la predeterminada y nada avisaría del error).
   Antes, compruebe que su último commit es el que le di. → **Publish release**. En **Tags**, la etiqueta debe mostrar
   ese mismo commit; si muestra otro, **no publique** y cree `-2` en el commit correcto. **Una etiqueta nunca se borra ni
   se mueve.** Desde ahora y hasta publicar, nadie sube nada a la rama.
2. **Pruebas sobre la etiqueta.** **Actions** → **Tests** → la ejecución con el nombre de la etiqueta → en verde. Tarda
   unos 30 minutos (sin los descuentos eran 18 a 19). **No entre las 00:00 y las 05:00 de Costa Rica**: hay
   pruebas que dependen de la hora y saldrían en rojo. Si sale rojo, no siga: copie el nombre del paso y de la prueba y
   páseme el mensaje.

---

## 3 · Después del cierre: respaldo, fotos, la 0038 y sus comprobaciones

**Condiciones:**
- **Después del cierre (19:00), desde las 19:30**, con las etapas 1 y 2 en verde y su línea de 1.8 dada. No de
  madrugada: el respaldo nocturno corre desde las 02:17 (GitHub lo atrasa a veces hasta las 7:30) y un respaldo en curso
  puede hacer fallar la pegada.
- **Caja:** en cada tableta el aviso de conexión dice «en línea» y, al tocarlo, «Todo lo que se tomó en este dispositivo
  está guardado en el sistema.». Si dice «guardando N…», «N sin guardar todavía», «sin conexión · N en este
  dispositivo» o «no guardado en este dispositivo», espere a que se vacíe. Ningún ticket a medias ni ventana de
  descuento abierta; «Hoy en el mostrador» cerrado; la cocina sin pedidos.
- **Nadie usa ningún aparato entre la foto de antes (paso 2) y la de después (paso 6)**: ni ventas, ni marcas en el
  Reloj, ni el PIN de las áreas del dueño. Deje cada aparato en la Caja o en la Cocina (el Reloj, Inicio, el Menú,
  Ventas e Inventario cierran la sesión solos a los 30 minutos, y eso también cambia las huellas). Haga los pasos 2 a 8
  seguidos.
- Los archivos que se pegan son los de **la etiqueta**: GitHub → **Tags** → la etiqueta → el archivo → **Raw**, y copie
  **todo** cada vez. Cada consulta en su propio **New query** (el SQL Editor muestra solo el último resultado).

1. **Respaldo.** `canopy-respaldos` → **Actions** → **Respaldo nocturno** → **Run workflow** → **Run workflow**. Unos 2
   minutos, en verde; el resumen dice «restauración: passed». Luego, que no quede nada corriendo: en Actions ninguna
   corrida de «Respaldo nocturno» ni de «Ensayo en pruebas» en curso o en cola, y en el SQL Editor
   `select count(*) from pg_stat_activity where usename = 'canopy_backup';` → `0`.
2. **Las fotos de antes** (guarde cada resultado completo en un archivo):
   - `supabase/tools/production-snapshot.sql` → «snapshot-antes». Debe decir: `migrations_applied` termina en `37`; en
     `schema`, `functions_by_version` sin la clave `"0038"`, `functions_changed` = `[]`, `functions_unknown` = `[]`;
   - `supabase/tools/release-check.sql` → «release-antes»: `migrations_missing` = `[38]`; `functions_missing` = los 11
     nombres que empiezan por `descuento`; en `settings` todavía no aparecen `pos_free_discount` ni `pos_discount_guia`;
   - `supabase/tools/consistency-check.sql` → «consistencia-antes».
3. **La migración.** **New query** → pegar **todo** `supabase/migrations/0038_descuentos_caja.sql`. Antes de **Run**:
   la segunda línea (debajo de «=====») dice «Canopy OS · migración 0038 · Descuentos de Caja: cuatro categorías con
   código, cajas registradas para…», y al bajar al final del texto pegado las dos últimas líneas son
   `select canopy.migration_end(38, 'descuentos_caja');` y `notify pgrst, 'reload schema';` (si no están, el texto quedó
   cortado: borre y pegue de nuevo). → **Run** → debe decir **Success** (sin filas). Una sola vez.
   - Si el editor pide confirmar una «destructive operation», es lo esperado: la 0038 usa `drop … if exists` en tres
     funciones y cuatro disparadores suyos y en cinco reglas de la tabla de aprobaciones (las crea de nuevo, salvo una que
     deja fuera a propósito y que en producción no existe); no borra datos → «Run this query».
   - «La migración 38 (descuentos_caja) ya estaba aplicada: no se cambió nada.» → ya estaba; siga con el paso 4.
   - «Falta aplicar antes la migración 37…» → **deténgase y avíseme** (no pasó nada).
   - «canceling statement due to lock timeout» → no se aplicó nada: algo tenía tomadas esas tablas más de 8 segundos,
     casi siempre un respaldo en curso. Revise el paso 1, espere y pegue de nuevo. Si pasa dos veces, no pegue una
     tercera: avíseme.
   - Cualquier otro error: **deténgase**, copie el mensaje completo y no publique. La base sigue en la 0037.
4. **El registro.** `select version, name, applied_at from canopy.migrations order by version desc limit 2;` →
   `38 descuentos_caja` y `37 pantallas_v2`. `applied_at` es la hora UTC del pegado: anótela. Si dijo *Success* pero no
   aparece la 38, no publique: avíseme.
5. **`release-check.sql`.** Debe decir:
   - `migrations_missing` = `[]` y `functions_missing` = `[]`. Si dice `[38]`, la pegada quedó incompleta: **deténgase y
     avíseme**;
   - `anon_can_run` = `["canopy_schema_version", "order_status", "pantalla_datos", "place_room_order", "room_lookup"]`
     (igual que antes: la 0038 no da nada a un visitante);
   - en `settings`: `"pos_free_discount": "on"` y `"pos_discount_guia": "off"`; `confirmations` igual que en
     «release-antes» (no aparece `courtesy_iva_confirmed`);
   - `tables_without_rls` = `[]`, `storage_policies_missing` = `[]`, en `ledger` `unbalanced` = `0`.
6. **La foto de después.** `production-snapshot.sql` otra vez → «snapshot-después», **antes de tocar los aparatos**. Debe
   decir:
   - `migrations_applied` termina en `38`;
   - en `schema`: `functions_by_version` con `"0038": 45` (las 42 funciones nuevas y las tres reemplazadas) y `"legacy"`
     = el de «snapshot-antes» menos 3 (las tres funciones reemplazadas, `approve_discount`, `tab_set_discount` y
     `_order_discount_check`, pasan de «legacy» a «0038»), sin la clave `"?"`; `functions_changed` = `[]`;
     `functions_unknown` = `[]`; `tables_missing` = `[]`; `functions_total` = el de antes + 42; `tables_other` incluye
     `public.discount_tills` y `public.discount_pin_shared`;
   - `data_fingerprint` y `security` → `anon_can_run` **idénticos** a los de «snapshot-antes» (la 0038 no cambia
     ninguna fila ni ningún permiso existente); en `switches.settings` aparecen `pos_free_discount` `"on"` y
     `pos_discount_guia` `"off"`. Si una tabla de `data_fingerprint` cambió, **no vuelva a pegar la 0038**: deténgase y
     avíseme con las dos fotos (casi siempre es un aparato que se usó en medio).
7. **La cuenta de respaldo.** `supabase/tools/backup-account.sql` → **Run** → una fila que empieza con «lista: la
   cuenta canopy_backup puede leer … tablas del café…» (ahora también las dos tablas nuevas de la 0038). Si dice
   «REVISAR» o un error, copie el mensaje y avíseme; no publique.
8. **Consistencia.** `consistency-check.sql` otra vez: todo `kept` idéntico a «consistencia-antes», también
   `discounts_md5` (ningún descuento ya dado cambió), y `problems` igual que antes.

Hasta publicar (etapa 4), **las Cajas siguen igual**: las páginas de hoy funcionan sobre la 0038 con el ajuste encendido;
la única diferencia es que la ventana anterior rechaza un motivo que diga una de las cuatro categorías.

---

## 4 · Guardar el sitio, publicar y registrar cada caja

1. **Guardar el sitio de hoy (la vuelta atrás exacta).** GitHub → **Releases** → **Draft a new release** → **Choose a
   tag**: `sitio-AAAA-MM-DD` con la **fecha de hoy** → **Create new tag** → **Target**: la rama **gh-pages** → título
   «Sitio antes de los descuentos» → marque **Set as a pre-release** → **Publish release**. En **Tags** debe mostrar el
   commit `44a0dab` («Publish website v2026.11.03-1 …»). Si muestra otro: **Releases** → esa versión → **Delete**, y
   **Tags** → esa etiqueta → **Delete tag**; después créela otra vez con Target **gh-pages** (esta etiqueta guarda una
   copia del sitio, no es una versión). Si ya existe una `sitio-` con la fecha de hoy, no la toque y avíseme.
   - **No use `sitio-2026-11-03`**: es el sitio de **antes** de las pantallas V2 (`v2026.11.02-1`, `7d87c81`);
     restaurarlo quitaría la V2. Tampoco las anteriores.
2. **Publicar.** **Actions** → **Publish website (PRODUCTION · manual only)** → **Run workflow**:
   - **Use workflow from** → **Tags** → la etiqueta nueva;
   - en «Escriba PUBLICAR para publicar esta versión en el sitio real del café»: `PUBLICAR`;
   - «Solo para volver a un sitio guardado (sitio-AAAA-MM-DD). Vacío = publicar esta versión»: **vacío**;
   - **Run workflow**. Espere el verde de la corrida y el de «pages build and deployment» (de 2 a 10 minutos). (Si GitHub
     pide aprobar el despliegue, apruébelo solo si es el de la etiqueta nueva.)
3. **Comprobar la versión.** `https://hanginggardencafe.com/version.json?t=` seguido de la hora (por ejemplo
   `?t=2015`, un número nuevo cada vez): `"version"` = la etiqueta, `"build"` = los 12 primeros caracteres del commit y
   `"sha"` = el commit. Si todavía dice `v2026.11.03-1`, espere (hasta 10 minutos); **no vuelva a publicar**.
4. **Cada Caja con la ventana nueva.** La Caja dice «actualización lista» y se recarga sola entre ventas (nunca con
   productos en el ticket); si a los 15 minutos sigue igual, recárguela a mano. En cada Caja: toque un producto (no lo
   cobre) → «Descuento» → debe abrirse «Aplicar descuento» con los cuatro botones. **Todavía dirá** «Esta caja no está
   registrada para descuentos…»: es lo esperado. → «Cancelar» → «Vaciar pedido».
5. **Registrar cada caja que da descuentos**, una por una, con ese aparato en la mano (no se escribe ningún PIN en la
   Caja; el registro usa la apertura del encargado en ese mismo aparato):
   1. En la Caja, el botón de arriba con el nombre del aparato (o «Este dispositivo») muestra cómo se llama: debe ser
      el de su lista (1.10). Si no, corríjalo ahí → «Guardar».
   2. En ese mismo aparato: «Reloj» → Reloj de marcas → «Horas y equipo» → en «¿Quién consulta?», «Nombre» = el
      encargado → su «PIN» → «Ver horas». Abajo debe decir «Áreas de dueños abiertas · (nombre) · hasta las HH:MM».
   3. Baje hasta «Bitácora de aprobaciones» → el bloque **«Cajas para descuentos»**: tres filas, algo como «Puesto 1:
      libre · 0 códigos equivocados en 24 h · Activa», y lo mismo para los puestos 2 y 3.
   4. **«Registrar este dispositivo para descuentos»** → debe decir «Dispositivo registrado para descuentos.», y la fila
      del puesto pasa a algo como «Puesto 1: Caja del frente · registrada por (encargado), 4 nov 19:52 · 0 códigos
      equivocados en 24 h · Activa · este dispositivo». Abajo: «Reanudaciones en 24 h: 0 de 2 · Usted: 1 de 2 cajas
      registradas, 0 de 3 registros quitados o reemplazados, 1 de 6 dispositivos registrados en 24 h».
      - «Usted ya tiene 2 cajas registradas. Reemplace una de las suyas, o que otro encargado registre este
        dispositivo.» → que lo registre otro encargado (pasos 2 a 4 con su PIN).
      - «No se pudo identificar este dispositivo. Cierre sesión y vuelva a entrar.» → **deténgase y avíseme** (sería que
        los accesos de producción no traen el identificador de sesión; nada cambió).
      - «Este dispositivo ya está registrado.» → ya estaba; siga.
      - «No se pudo guardar. Revise la conexión e intente de nuevo.» → con el aviso de conexión «en línea», vuelva a
        abrir la Bitácora: si el registro llegó al servidor, la página lo recupera sola y guarda la llave; si no, el
        botón «Registrar este dispositivo para descuentos» sigue ahí y lo toca otra vez.
   5. Toque **«Bloquear»** en el aviso «Áreas de dueños abiertas».
   6. Vuelva a la Caja → el botón con el nombre del aparato → «¿Qué dispositivo es este?»: debajo del nombre debe decir
      **«Descuentos: registrada (encargado, 4 nov 19:52).»** (con su nombre y la hora). Esto también prueba que los
      accesos de producción traen el identificador de sesión. → «Guardar» sin cambiar nada. Si dice «Descuentos: sin
      registrar…», repita desde el paso 2; si dice «No se pudo identificar esta caja. Cierre sesión y vuelva a entrar.»,
      deténgase y avíseme.
   7. **En un solo aparato**, donde usted pueda volver a escribir la contraseña del café: «Cerrar sesión» → volver a
      entrar → el botón del aparato → debe seguir diciendo «Descuentos: registrada (…).» (la llave lo trajo de vuelta a
      su puesto, sin PIN). Si dice «sin registrar», avíseme antes de registrar otra vez.
   8. Repita los pasos 1 a 6 en cada aparato de la lista. **Respaldo:** si solo un aparato da descuentos, registre un
      segundo (por ejemplo el iPad): si una caja se detiene, la otra sigue. No registre la cocina, la TV ni teléfonos.
6. **Apagar la ventana anterior: su último paso, opcional y cuando usted quiera.** No hay plazo. Mientras esté
   encendida, una tableta que no se recargó todavía puede usar la ventana anterior, y cualquier inicio de sesión puede
   probar ahí PIN con lista de nombres al ritmo de la 0033 (unos 150 al día por persona, la misma cuenta que la casilla
   de abrir las áreas del dueño). Recomendamos apagarla cuando todas las Cajas muestren la ventana nueva y los primeros
   descuentos reales salgan bien (sección 5). Dos maneras, cualquiera:
   - **SQL Editor:** pegar `supabase/tools/descuento-libre-apagar.sql` (de la etiqueta) → **Run** → una celda
     `pos_free_discount` = `"off"`. Es la única manera mientras E-06 esté abierta;
   - **Inicio → «Ajustes del sistema»**, solo en su ingreso personal con el código del teléfono: «Ventana anterior de
     descuento libre (cajas aún sin recargar)» → «Apagada (solo los cuatro descuentos)» → «Guardado.». Con otro ingreso
     contesta «Solo el ingreso del dueño, con el código del teléfono, puede cambiar los ajustes.» (un PIN de dueño en
     una tableta no cambia ajustes).

   Después, una tableta con la página vieja que intente aprobar muestra «Esto necesita una actualización de la base de
   datos: aplique las migraciones pendientes (docs/MIGRACIONES.md) y recargue esta página.»: recargarla trae la ventana
   nueva. Las aprobaciones viejas ya dadas (hasta 30 minutos) y las ventas guardadas sin internet con ellas se registran
   como hoy. Para encenderla otra vez: `supabase/tools/descuento-libre-encender.sql` → `"on"`.

---

## 5 · Comprobaciones en el café (sin ventas de prueba)

**No haga ventas, anulaciones ni cortesías de prueba**: quedarían como registros reales que no se borran (CLAUDE.md).
**Nunca escriba un código equivocado a propósito**: cuenta en esa caja durante 24 horas. Las esperas, las detenciones y
el cupo los prueban las pruebas automáticas.

| # | Qué hacer | Correcto si |
|---|---|---|
| A | En cada Caja registrada: un producto en el ticket (sin cobrar) → «Descuento» → tocar «Empleado», «Local», «Huésped» y «Guía Turista», sin escribir ningún código → «Cancelar» → «Vaciar pedido» | Empleado pide «Código de empleado»; Local y Huésped «Código de encargado»; Guía Turista dice «La cortesía Guía Turista espera la confirmación del IVA por el contador (A-13).» con «Autorizar descuento» apagado. Ningún mensaje de registro, espera ni detención. Nada se mueve en la ventana |
| B | Reloj de marcas → «Horas y equipo» | Pide el PIN (no quedó nada abierto). Luego «Cancelar» |
| C | Una tableta que no se recargó (si queda alguna) | Muestra la ventana anterior y, con el ajuste encendido, funciona como hoy; recárguela |
| D | (Opcional: prueba el camino completo sin venta.) En una Caja registrada: un producto → «Descuento» → «Local» → el encargado escribe su código → «Autorizar descuento» → el ticket muestra «Descuento Local» y el monto → la × del descuento → «Descuento quitado» → «Vaciar pedido». **Nunca lo cobre** | «Descuento aprobado por (encargado)». Queda una línea «Liberado» en el informe y «Descuento liberado» en la bitácora; ninguna venta ni dinero |
| E | **Al día siguiente, al abrir:** en cada Caja, la primera venta normal en efectivo y la primera con tarjeta (sin descuento); después, el primer descuento real de cada tipo (Empleado, Local, Huésped) → Ventas → «Descuentos por categoría» | Las ventas normales: al tocar el aviso de conexión dice «Todo lo que se tomó en este dispositivo está guardado en el sistema.» y aparecen en Ventas; si quedan «sin guardar todavía», vea la sección 6. Cada descuento con el estado «Usado», quién lo autorizó, el empleado (en Empleado), los productos cubiertos y lo cobrado; el recibo sin porcentaje |

**Consultas finales** (solo lectura; cada una en su propio «New query»):

```sql
select at, action, manager_name, details ->> 'slot' as puesto, details ->> 'till_station' as caja
  from public.audit_log
 where action like 'discount_till_%' or action in ('discount_code_wrong', 'discount_alert', 'pin_duplicate')
 order by at desc limit 20;
```
Esperado: un `discount_till_enrolled` por cada aparato registrado, con el nombre del encargado y su puesto; un
`discount_till_rebound` del aparato que cerró sesión en 4.5.7; ningún `discount_code_wrong` ni `pin_duplicate` salvo
que alguien haya escrito un código equivocado (a lo sumo un `discount_till_unknown` si alguien escribió un código antes
de registrar). Ninguna fila trae un PIN ni un código.

```sql
select count(*) as abiertas from public.access_unlocks where expires_at > now();
```
Esperado: `0` después de «Bloquear» en cada aparato, o 15 minutos después de la última apertura.

**Nunca, en las tabletas del café:** «Cerrar sesión en todos lados» (saca la Caja y la cocina; solo en el procedimiento
E-lock, sección 8), «Activar» el código del teléfono, «¿Olvidó su contraseña?», borrar los datos del sitio.

---

## 6 · Vuelta atrás

| Qué pasa | Qué hacer |
|---|---|
| Una caja espera o está detenida | No es una vuelta atrás: las demás cajas siguen; espere, o «Reanudar descuentos» (sección 0), o la sección 8 |
| Una caja dice «Esta caja no está registrada…» o «Se quitó el registro de esta caja…» | Registrarla (4.5) |
| La ventana nueva no le convence o falla en las Cajas | **6.1** (las páginas vuelven; la base se queda en la 0038) |
| Falla una función de la 0038 (errores del servidor que nombran `descuento_…`) | **6.1** y después **6.2**, y avíseme |
| La Caja no carga después de publicar | **6.1** de inmediato y avíseme |
| Una Caja deja ventas normales «sin guardar todavía» (o «guardando N…») que no se vacían, con internet | **Avíseme de inmediato.** Las ventas quedan en la tableta y la Caja sigue vendiendo; **nadie borra los datos del sitio** (sección 0), porque se perderían. Lo vemos juntos: 6.1 si la causa son las páginas nuevas, 6.2 solo conmigo |

### 6.1 Las páginas vuelven a `v2026.11.03-1` (la base se queda en la 0038)

1. **Si apagó la ventana anterior, enciéndala primero:** `supabase/tools/descuento-libre-encender.sql` → `"on"`. Sin
   esto las páginas anteriores no dan ningún descuento.
2. **Actions** → **Publish website (PRODUCTION · manual only)** → **Run workflow** → **Use workflow from** → **Tags** →
   `v2026.11.03-1` → `PUBLICAR` en la primera casilla → la segunda **vacía** → **Run workflow**.
   - Solo si esa publicación falla: la copia exacta guardada en 4.1. **Use workflow from** → **Tags** → la etiqueta de
     los descuentos (la de hoy), `PUBLICAR` en la primera casilla y en la segunda `sitio-AAAA-MM-DD` (la fecha de 4.1).
     **Revise que la segunda casilla no quede vacía**: vacía, publicaría los descuentos otra vez. **Nunca
     `sitio-2026-11-03`** (quitaría las pantallas V2).
3. `version.json?t=…` dice `"version": "v2026.11.03-1"` y `"build": "adb19eefb0ef"` (con la copia exacta, el
   `version.json` guardado de esa versión).
4. Las Cajas se recargan solas entre ventas; si una no cambia en 15 minutos, recárguela a mano entre ventas.
5. **Avise al equipo** de lo que ven en la ventana anterior:
   - «Descuento» abre la ventana de antes (porcentajes o monto, «Motivo», «Aprobado por», PIN, «Aprobar el descuento»).
     **Un motivo o un detalle que diga una de las cuatro categorías** («Local», «Empleado», «Huésped», «Guía Turista»,
     en mayúsculas o minúsculas, con o sin tilde, solo o después de « · », por ejemplo «Otro» con el detalle «Local»)
     contesta «Elija el motivo del descuento.» aunque se haya elegido un motivo. Escríbalo con otras palabras, por
     ejemplo «Cliente de la zona». Los motivos de la lista («Cliente frecuente», «Miembro del equipo», «Cortesía por un
     error o una espera», «Promoción») funcionan como antes;
   - **una cuenta que todavía lleve uno de los cuatro descuentos:** la × anterior («Quitar el descuento») lo quita
     mientras no haya nada pagado; el cupo de un empleado queda usado ese día (las páginas anteriores no tienen
     «Devolver el cupo del día»). Después de un pago, la página anterior contesta «Esto necesita una actualización de la
     base de datos: aplique las migraciones pendientes (docs/MIGRACIONES.md) y recargue esta página.» y no lo quita: la
     cuenta se cobra con el descuento, o un encargado la anula;
   - un descuento de la ventana nueva que ya estaba en un ticket (hasta 30 minutos) y las ventas guardadas sin internet
     con él se registran como siempre: la base los revisa.
6. La base se queda en la 0038 y las páginas anteriores funcionan con ella: lo prueba «Tests» en cada ejecución (las
   páginas publicadas `44a0dab` sobre una copia con la 0038). Las cajas registradas quedan registradas, sin uso: si
   vuelve a publicar los descuentos más adelante, regresan solas a su puesto (salvo una tableta a la que se le borraron
   los datos del sitio).

### 6.2 La base (solo por una falla de una función de la 0038, y después de 6.1)

Nunca revierta solo la base con las páginas nuevas publicadas: la ventana nueva diría «Los descuentos necesitan una
actualización de la base de datos. Avise al dueño.» y no daría ningún descuento. Por eso primero 6.1. Fuera del horario
de atención, salvo urgencia.

1. **Respaldo nocturno** → **Run workflow** → en verde.
2. `supabase/tools/descuento-libre-encender.sql` → `"on"` (sin la 0038 nadie lo lee; al aplicar la 0038 otra vez vale
   lo que quedó).
3. Los archivos de este paso y de los siguientes son los de **la etiqueta de los descuentos** (la de la etapa 2), no los
   de la rama ni los de `v2026.11.03-1`. **SQL Editor** → **New query** → pegar **todo**
   `supabase/tools/reversion-0038.sql`. Antes de **Run**, baje al final del texto pegado: las dos últimas líneas son
   `delete from canopy.migrations where version = 38;` y `notify pgrst, 'reload schema';` (si no están, el texto quedó
   cortado: borre y pegue de nuevo). Si el editor pide confirmar una «destructive operation», es lo esperado (quita
   los cuatro disparadores, las funciones nuevas y la fila 38 del registro; no borra datos) → **Run** → **Success** (sin
   filas).
   - «La migración 0038 no está aplicada: no hay nada que revertir. No se cambió nada.» → ya estaba revertida.
   - «Hay una migración posterior a la 0038 aplicada (…): revierta esa primero. No se cambió nada.» → avíseme.
4. `release-check.sql`: `migrations_missing` = `[38]`, `functions_missing` = los 11 nombres que empiezan por
   `descuento`, `anon_can_run` = las mismas cinco de 3.5; los dos ajustes siguen en `settings` (quedan, sin uso).
5. `production-snapshot.sql`: `migrations_applied` termina en `37`; `functions_changed` = `[]`; `functions_unknown` =
   `[]`; `functions_by_version` y `functions_total` iguales a los de «snapshot-antes» (las tres funciones vuelven a
   contar como «legacy», sin la clave `"0038"`); `tables_other` sigue con `public.discount_tills` y
   `public.discount_pin_shared` (quedan, sin uso).
6. Qué queda: las columnas nuevas, las dos tablas nuevas (las cajas registradas y quién comparte un código), los dos
   ajustes y **todas las filas** (aprobaciones, bitácora). Una aprobación de categoría todavía sin usar que llegue con
   una venta se revisa como una de la ventana anterior (su porcentaje fijo, 30 minutos). Al aplicar la 0038 otra vez,
   todo vuelve como estaba.
7. **No pegue `reversion-0037.sql`** por un problema de los descuentos: quitaría la V2 de las pantallas.

### 6.3 Deténgase y avíseme si

- «Tests» queda en rojo sobre la etiqueta, o el ensayo o el respaldo están en rojo;
- `version.json` muestra otro commit pasados 10 minutos;
- la Caja o la Cocina no cargan;
- una Caja deja ventas «sin guardar todavía» que no se vacían (nunca borren los datos del sitio: esas ventas están en
  la tableta);
- una caja dice «No se pudo identificar esta caja…» después de cerrar sesión y volver a entrar;
- un código correcto se rechaza en una caja registrada sin espera ni detención;
- cualquier comprobación de esta guía dice otra cosa.

---

## 7 · Guía Turista, más adelante (no forma parte de esta activación)

Guía Turista queda **apagada** (`pos_discount_guia` = `off`) hasta que el contador confirme el tratamiento del IVA de
las cortesías al 100 % (A-13; su ajuste 4). Mientras tanto el botón sigue a la vista y, al tocarlo, explica «La
cortesía Guía Turista espera la confirmación del IVA por el contador (A-13).»; el servidor la rechaza antes de probar
cualquier código (nada se cuenta). No hay ningún archivo del SQL Editor para encenderla, a propósito: es una regla fiscal
que solo usted enciende, con la respuesta del contador.

**Lo que hace falta:** (1) la respuesta escrita del contador (A-13), y que **confirme que la cortesía va sin IVA, como
está construida**: el pedido en ₡0 con la forma de pago «otro» y sin cobro, IVA 0 y neto 0, ningún ingreso en los
libros, y el valor de lista solo como información. Si la respuesta dice otra cosa (por ejemplo, IVA por autoconsumo o
por entrega gratuita), **no registre la confirmación ni la encienda**: avíseme; primero hace falta una versión nueva que
la registre como diga el contador (A-13); (2) el código del teléfono en su ingreso personal (E-06); (3) un miembro del
equipo con puesto de dueño y PIN (la consulta de 1.7 debe dar `1` o más; ese puesto y su PIN solo los da usted, en
«Equipo», con el código del teléfono). Sin (3), el botón dice «Guía Turista necesita el PIN del dueño. El dueño lo
agrega en Equipo.»

**Los pasos (en su ingreso personal con el código del teléfono, en su propio aparato; nunca en una tableta del café):**
1. Inicio → «Ajustes del sistema» → en el recuadro de confirmaciones: «Regla» = `courtesy_iva_confirmed` → «Confirmado
   por (nombre)»: el contador → «Documento o referencia»: su documento → «Registrar la confirmación» → aceptar →
   «Confirmación registrada.».
2. La fila «Cortesía Guía Turista 100 % (necesita la confirmación del IVA por el contador, A-13)» → «Encendida (IVA
   confirmado por el contador)» → «Guardado.». Sin el paso 1 contesta «Con candado: primero registre la confirmación de
   esta regla.».
3. **Antes, sepa esto:** el código del dueño se escribe en el teclado de la Caja, a la vista del personal y del guía.
   Quien lo vea puede escribirlo en la casilla de PIN que abre las áreas del dueño en cualquier tableta del café, y abrir
   esas áreas y Ventas durante 15 minutos, también poner PIN nuevos a los encargados en «Equipo» (sección 0). Escríbalo
   sin que lo vean y use un PIN de 6 números (1.5); encender Guía Turista es aceptar ese riesgo.
   Con el primer guía real: en una Caja registrada, «Descuento» → «Guía Turista» → «Empresa del guía turístico»: la
   empresa → «Autorizar descuento» → «Código del dueño»: quien tenga el puesto de dueño escribe su código → «Autorizar
   descuento» → el ticket dice «Cortesía Guía Turista · (empresa)» con total ₡0 → «Registrar cortesía» (el recibo dice
   «Cortesía · Courtesy»).
4. **Su ajuste 1, comprobado en la tableta:** después, en esa Caja no aparece «Áreas de dueños abiertas», y Reloj de
   marcas → «Horas y equipo», Inicio, Ventas e Inventario siguen pidiendo el PIN.
5. Para apagarla: la misma fila → «Apagada (hasta que el contador confirme el IVA)».

En Ventas → «Descuentos por categoría», la línea «Cortesías: valor de lista por tasa de IVA (informativo, pendiente del
contador · A-13)» da al contador el valor de lista de lo regalado; ningún impuesto se calcula ni se registra por ella.

---

## 8 · Herramientas del dueño y procedimiento E-lock

**Lo normal lo hacen los encargados en la bitácora** (Reloj de marcas → «Horas y equipo» → su PIN → «Bitácora de
aprobaciones» → «Cajas para descuentos»): «Reanudar descuentos» en un puesto detenido (con o sin caja), «Quitar
registro» de una caja (por ejemplo una tableta que ya no se usa), y «Reemplazar con este dispositivo» cuando los 3
puestos están ocupados («Los 3 puestos están ocupados. Elija abajo qué caja reemplaza este dispositivo (cuenta en sus 3
del día).»). Cada acción abre «Aprobación del encargado»: «Aprobado por» (su propio nombre) → «PIN del encargado» →
«Confirmar». Cada encargado: como mucho 2 cajas registradas a su nombre, 3 registros quitados o reemplazados y 6
aparatos registrados en 24 horas; las reanudaciones, una por puesto y dos por café en 24 horas. Todo queda con su
nombre, y otro encargado puede deshacerlo.

**Las herramientas del SQL Editor** (solo usted; de la etiqueta, Raw; cada una es una sola transacción y se niega si
la 0038 no está aplicada; las de cajas y PIN, `descuento-cajas-reanudar.sql`, `descuento-cajas-quitar-todas.sql` y
`pines-desbloquear.sql`, terminan con un resumen por puesto: estado, códigos equivocados en 24 horas, la caja que lo
ocupa y quién la registró; las dos de la ventana anterior, con una celda con el valor del ajuste):

| Archivo | Cuándo | Resultado esperado | Después |
|---|---|---|---|
| `descuento-cajas-reanudar.sql` | Una caja detenida y la bitácora ya contesta «Ese puesto ya se reanudó en las últimas 24 horas, o el café ya usó sus 2. Vuelve solo a las HH:MM.», o no hay un encargado. **Antes**, mire en la bitácora quién y desde qué aparato escribió los códigos («Código de descuento equivocado») | `resumed` = los puestos reanudados; en `places`, cada uno con `state` `ok`. Queda una línea por puesto a nombre de «owner (SQL Editor)», fuera del tope | Si los códigos eran de alguien que prueba PIN, cámbiele el PIN o desactívelo en «Equipo» |
| `descuento-cajas-quitar-todas.sql` | Una tableta perdida o robada, una sesión o una llave copiada, o una persona que abusa de los registros (antes, en «Equipo», cámbiele el PIN o desactívela). Para una sola tableta basta «Quitar registro» en la bitácora | `ended` = cajas quitadas, `keys_spent` = llaves gastadas; en `places`, los 3 con `held` = `false` | Ninguna tableta da descuentos hasta que un encargado la registre otra vez (4.5). Si la contraseña del café pudo filtrarse, cámbiela (E-lock, paso 1) |
| `pines-desbloquear.sql` | Solo en el procedimiento E-lock, abajo | `cleared` = bloqueos quitados, `still_locked` = `0` | Repetirlo una hora después |
| `descuento-libre-apagar.sql` / `descuento-libre-encender.sql` | 4.6 / 6.1 | `"off"` / `"on"` | — |

**Procedimiento E-lock** (alguien mantiene bloqueados a los encargados con la contraseña del café). Señal: el PIN de
cada encargado contesta «Demasiados PIN incorrectos. Espere 10 minutos e intente de nuevo.» en las casillas con lista
de nombres una y otra vez, también después de esperar, y la bitácora se llena de «PIN bloqueado». Mientras tanto **las
cajas registradas siguen dando descuentos** (regla 5) y vuelven solas después de cerrar sesión (la llave); lo que espera
es registrar aparatos nuevos, reanudar y «Quitar el bloqueo del PIN». Después del cierre si se puede:
1. **Cambie la contraseña del ingreso del café**: en su computadora, en una ventana privada, la página de ingreso de
   Inicio → «¿Olvidó su contraseña?» → el correo del ingreso del café → el enlace del correo → «Poner una contraseña
   nueva». Supabase cierra las otras sesiones de ese ingreso: todos los aparatos del café piden la contraseña. **Esta
   vez no la deje escrita en el café**: quien bloqueaba pudo sacar la anterior de ahí. Entre usted mismo en cada tableta
   (paso 4) y désela en persona solo a los encargados de confianza; nunca por chat ni por grupo (`docs/INGRESOS.md`). Si
   sospecha de alguien del equipo, en cuanto se pueda (después del paso 3) cámbiele el PIN o desactívelo en «Equipo».
2. En un aparato del café, ya con la contraseña nueva: Inicio → «Ingreso del propietario» → **«Cerrar sesión en todos
   lados»** → aceptar. Revoca todas las sesiones de ese ingreso, también las de quien bloqueaba. (Ese recuadro aparece
   mientras el ingreso del café sea de tipo dueño, como hoy con E-05 abierta; si no aparece, siga: el paso 1 ya cerró
   las otras sesiones.)
3. **SQL Editor:** `supabase/tools/pines-desbloquear.sql` → `still_locked` = `0`.
4. Entre en cada tableta con la contraseña nueva: las cajas registradas vuelven solas a su puesto. Compruébelo en el
   botón del aparato: «Descuentos: registrada (…).»
5. **Una hora después**, `pines-desbloquear.sql` otra vez: un acceso ya emitido dura hasta una hora y Supabase no lo
   puede revocar antes.

Solo, sin los pasos 1 y 2, `pines-desbloquear.sql` lo deshacen los próximos 15 intentos. Después, avíseme: con la
bitácora vemos desde dónde y cuándo.

**Otros avisos de la bitácora:**
- «Alerta a las HH:MM: N códigos de descuento equivocados en 24 horas en el café. No pausa nada; revise quién y dónde.»:
  es solo una línea (la hora y la cuenta son las del aviso, que queda 24 horas); mire en «Código de descuento
  equivocado» el paso, el aparato y la hora;
- «Código compartido por dos personas: asigne PIN nuevos en Equipo.» (con los dos nombres solo cuando usted la mira con
  puesto de dueño, en «Cajas para descuentos»; un encargado ve el aviso sin nombres, también en el registro): «Nuevo
  PIN» a las dos personas;
- «N códigos escritos en dispositivos sin registrar en 24 h.»: alguien escribió códigos en un aparato no registrado;
  ninguno se probó.

---

## Lo que usted debe aprobar o decidir

1. **Hecho el 2026-11-04:** su línea de confirmación de la regla 5 (1.8), con sus dos mitades (un PIN bloqueado
   temporalmente por intentos fallidos en otra pantalla sigue sirviendo en la ventana de descuentos, que no cuenta ni
   borra ese bloqueo; un PIN de una persona desactivada, cambiado, quitado, o de alguien sin el puesto necesario, nunca
   aprueba un descuento), copiada en E-42.
2. La vista previa privada: **aprobada el 2026-11-04** para seguir con la preparación; falta la prueba del campo de la
   empresa en el iPad (1.4).
3. Aprobar el commit de la versión y crear su etiqueta (2.1).
4. Elegir la noche de la activación y quiénes están (usted y uno o dos encargados con su PIN).
5. Subir `anonimizar.sql` a `canopy-respaldos` y correr «Ensayo en pruebas» (1.2, 1.3).
6. Aplicar la 0038 en producción con el SQL Editor (3.3).
7. Publicar la etiqueta con «Publish website» (4.2).
8. Decidir qué aparatos se registran para descuentos y cuál es el de respaldo (1.10, 4.5).
9. Decidir si los encargados y quien tenga puesto de dueño pasan a PIN de 6 números (recomendado, 1.5).
10. Dar PIN nuevos a quienes salgan en la lista de reactivaciones (1.6).
11. Decidir cuándo apagar la ventana anterior, `pos_free_discount`: es su último paso, opcional y sin plazo (4.6).
12. Guía Turista: pedir al contador la respuesta de A-13. Solo si confirma que la cortesía va sin IVA, como está
    construida (₡0, IVA 0, valor de lista solo informativo), y con E-06 y un PIN con puesto de dueño: registrar la
    confirmación y encenderla (sección 7), aceptando que el código del dueño se escribe a la vista en la Caja y que quien
    lo vea puede abrir con él las áreas del dueño y Ventas durante 15 minutos en cualquier tableta. Si el contador dice
    otra cosa, no la encienda: avíseme; primero hace falta una versión nueva (A-13). No forma parte de esta activación.
13. Preguntar al contador si el 30 % de Empleado es salario en especie (A-14); no hay nada construido para eso.
14. Revisar en el informe, después de unas semanas, si alguna caja honesta se detuvo; cambiar un límite necesita una
    migración nueva.
15. Aprobar más adelante una migración posterior que retire la ventana anterior (Q5; la 0039 es la de Proveedores, D-066).
16. Decidir, sin apuro (no detiene la activación), qué hace la Caja con los productos tocados para una cuenta que se
    cerró mientras tanto cuando el pedido del ticket tiene un descuento (sección 0, «Con un descuento puesto»). Lo
    construido y probado es **A**: no los suma y avisa «… cóbrelos después de esta venta.»; nada se cobra de más ni de
    menos sobre lo autorizado, y el riesgo es olvidar cobrar lo tocado. **B** soltaría el descuento (como la ×),
    sumaría lo tocado y pediría autorizarlo de nuevo (no se olvida nada, pero el cliente pierde el descuento hasta otra
    autorización y un Empleado soltado deja el cupo libre). **C** guardaría el pedido con descuento aparte y dejaría
    lo tocado como un pedido nuevo (lo más completo, pero cambia la Caja y necesita más pruebas). Recomendado: A por
    ahora; si en la práctica se olvidan productos, B es un cambio pequeño.
17. Solo si hace falta: la vuelta atrás (6.1, y 6.2 solo por una falla de una función) o el procedimiento E-lock (8).

---

## Registro

**Durante la activación, anote** (sin PIN ni contraseñas): número y hora de «Tests» de la etiqueta, del ensayo y del
respaldo con sus líneas de resumen; el `applied_at` de la 0038; las celdas de `release-check` (antes y después), de
`production-snapshot` (antes y después), de `backup-account` y de `consistency-check` (antes y después); los números de
«Publish website» y de «pages build and deployment»; el commit nuevo de `gh-pages` y `version.json`; cada aparato
registrado (puesto, nombre, encargado, hora); si apagó la ventana anterior y cuándo; el resultado de A a E.

**Después**, en un commit normal con su autorización: D-065 y E-42 (que E-42 pase a cerrada), su línea de la regla 5 en
E-42 (si no entró ya en el commit aprobado, 1.8), `docs/MIGRACIONES.md` («hoy en la 0038»), `docs/CHECKLIST.md`,
`docs/PRODUCTION-READINESS.md`, `docs/PRUEBAS.md` y `tests/rehearsal/LIVE_PAGES` (con el nuevo `gh-pages`). Ese commit
dispara «Tests», cuyo paso «The live site is an approved release» comprueba el sitio publicado.

| Fecha y hora | Etapa y paso | Resultado (o lo que se vio) |
|---|---|---|
| | | |
