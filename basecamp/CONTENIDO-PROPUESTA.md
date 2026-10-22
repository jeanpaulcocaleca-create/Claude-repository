# Contenido confirmado · cambios propuestos para aprobar

Fecha: 2026-10-22 · Autor: Claude · Fuente: memo «Contenido confirmado del sitio», del propietario, revisado por Lapis y enviado por ChatGPT.

**Estado: aprobada (BD-023) e implementada en la vista previa privada**, commit `1dc9b5e` de `basecamp-website`, con las decisiones de C-01 a C-13 tal como las fijó el GO. El informe está en `docs/CONSOLIDACION-INFORME.md` de ese repositorio. Las fotos, las reservas, el dominio y los servicios externos no se tocaron.

Comparé el memo con el contenido actual de la vista previa (commit `efc48fc`, que incluye los últimos guardados del propietario en el panel).

---

## 1 · Resumen

- **Datos del memo que el sitio no tiene:**
  - las comodidades de las habitaciones, que hoy dicen «pendiente»;
  - los horarios de entrada, salida y recepción;
  - el estacionamiento, el equipaje y el agua;
  - las reglas de la casa;
  - las preguntas frecuentes y la ubicación exacta.
- **Afirmaciones que se retiran:**
  - el servicio a la habitación con tarjeta QR;
  - «café hermano». El café es de la casa, en el mismo edificio; la empresa hermana es Costa Rica Access Travel, de tours.
- **Antes de publicar las condiciones de reserva:** la última configuración conocida de Hotel Link no coincide con el memo (§3, punto 1). Esas condiciones no se publican hasta que Hotel Link las tenga iguales.
- **Mascotas:** no se escribe nada hasta que el propietario confirme.
- **Requieren código, con autorización aparte (§5):**
  - mostrar la bebida por noche de la reserva directa y la cancelación gratuita junto a los botones de reservar;
  - quitar las etiquetas de prueba fijas.
- **Lo demás es contenido:** se cambia en los archivos del panel, sin tocar el diseño.

---

## 2 · Decisiones del propietario antes de editar

| # | Decisión | Recomendación de Claude |
|---|---|---|
| C-01 | **Mascotas:** (a) el hotel no acepta y el jardín del café sí, o (b) no se aceptan en ninguna área | Confirmar; mientras tanto no se publica nada |
| C-02 | **Trato en español:** el sitio usa «usted»; los ejemplos de Lapis usan «vos» («pedinos», «quedate») | Un solo trato en todo el sitio. Propongo mantener «usted», que sirve también a visitantes de otros países; los textos de abajo lo usan. Si eligen «vos», Claude adapta todo el sitio |
| C-03 | **Salida tardía de $15:** una regla del proyecto prohíbe montos escritos en el sitio (BD-011, sobre tarifas) | Aceptar una excepción solo para cargos fijos de servicio, como la salida tardía, y ajustar esa prueba. Si no, escribir «por una tarifa fija» sin monto |
| C-04 | **Bebida de reserva directa:** ¿una por habitación o por huésped, cada noche? ¿Cualquier bebida del menú o cualquier artículo? ¿Cómo verifica el personal que la reserva fue directa? | Escribirlo sin ambigüedad: lo anunciado debe cumplirse tal cual (Ley 7472). Propuesta: «una bebida a su elección del menú de Hanging Garden Café por habitación, por cada noche», con la fuente de la reserva en Hotel Link como prueba |
| C-05 | **Condiciones de reserva (§3 del memo):** no coinciden con la última configuración conocida de Hotel Link | El propietario actualiza Hotel Link y lo confirma. Recién entonces se publican. Booking.com y Airbnb tienen sus propias condiciones |
| C-06 | **Dirección exacta:** las fichas del café dicen «50 m sur y 50 m este de la iglesia»; el memo dice «a 50 m de la iglesia» | Confirmar cuál publicar |
| C-07 | **Horario de cierre del café (19:00) y café «El Trapiche»:** están en el sitio pero no en el memo | Confirmar o retirar; mientras tanto solo «abre a las 6:00» |
| C-08 | **Alquiler del hospedaje completo para grupos:** hoy se ofrece «todo el hospedaje»; el memo solo da la capacidad total | Confirmar si se alquila en exclusiva; si no, «varias habitaciones, hasta las diez» |
| C-09 | **Accesibilidad:** el memo pide no anunciar habitaciones adaptadas | Decirlo con honestidad en una pregunta frecuente: ninguna está adaptada para silla de ruedas |
| C-10 | **Dirección web de Costa Rica Access Travel** para el enlace de tours | La envía el propietario |
| C-11 | **Afirmaciones de los textos de habitaciones (BD-021) que el memo no confirma:** «la favorita de las parejas», «la más pedida», «un lugar tranquilo», «el jardín de orquídeas» | El memo confirma el jardín del café; las orquídeas y el resto siguen por confirmar |
| C-12 | **Error en el subtítulo de portada que escribió el propietario:** «nuestro propia cafeteria» | Corregir a «nuestra propia cafetería» |
| C-13 | **Preguntas frecuentes:** en La estadía con datos de preguntas para Google ahora, y páginas propias en las guías más adelante | Sí, empezar en La estadía |

---

## 3 · Contradicciones, textos provisionales y afirmaciones sin confirmar

| # | Dónde | Dice hoy | Según el memo | Propuesta |
|---|---|---|---|---|
| 1 | **Hotel Link** (fuera del sitio) | Última configuración conocida (`RESERVATIONS.md` §2): depósito del 50 %; penalidad de la estadía completa dentro de 22 días | Cancelación gratuita hasta 24 h; luego una noche | **Reportar la diferencia.** No publicar las condiciones hasta que coincidan (C-05) |
| 2 | Inicio, razón 3 | «pueden pedir a la habitación con una tarjeta QR» | No confirmado | Retirar |
| 3 | Inicio, café | «un menú que puede pedir desde su habitación» | No confirmado | Retirar |
| 4 | La estadía, pregunta del desayuno | QR y «si el desayuno está incluido, pendiente» | No incluido; se compra en el café desde las 6:00 | Texto nuevo (§4.4) |
| 5 | Inicio, título del café; preguntas | «nuestro café hermano / sister café» | El café es de la casa, en el mismo edificio | «Hanging Garden Café, en el mismo edificio» |
| 6 | `llms.txt` (código) | «Sister café» | Igual que el punto 5 | Cambio de código (§5) |
| 7 | Pie de página (código) | «Tours y actividades: vea nuestras guías» | Tours de Costa Rica Access Travel, empresa hermana | Enlazar la empresa cuando llegue su dirección (C-10) |
| 8 | Información del hotel | Horas de entrada y salida vacías | 15:00 y 11:00 | Completar |
| 9 | Información del hotel | «Dirección exacta pendiente» | Centro de Santa Elena, a 50 m de la iglesia | Completar (C-06) |
| 10 | Ubicación (texto) | «Contenido de prueba… pendiente» | Recepción, estacionamiento, equipaje | Texto nuevo (§4.5) |
| 11 | Habitaciones: baño y comodidades | «Pendiente de confirmación» | Lista confirmada | Completar (§4.3) |
| 12 | Habitaciones: tamaño | «Pendiente» | No viene en el memo | Sigue pendiente; propongo ocultar esa fila cuando esté vacía (§5) |
| 13 | La estadía: incluido, extras, reglas | Vacíos («pendiente») | Lista confirmada | Completar (§4.4) |
| 14 | La estadía: horarios | «Pendiente de confirmación» | 15:00 y 11:00 | Texto nuevo |
| 15 | La estadía, pregunta de reservar | Explica que la vista previa no está conectada | Incentivo de reserva directa | Texto nuevo, pendiente de C-04 |
| 16 | Inicio, presentación | «Este párrafo es texto de prueba» | Ubicación céntrica, todo a pie | Texto nuevo (§4.1) |
| 17 | Inicio, guías | «Guías de muestra para la vista previa» | Sin cambios en el memo | Quitar la frase cuando se confirmen las guías |
| 18 | Grupos | «Contenido de prueba»; «todo el hospedaje» | 10 habitaciones, 29 huéspedes | Texto nuevo (C-08) |
| 19 | Bus a la reserva | «cinco veces al día» | Corroborado; mantener | Mantener; la recepción confirma los horarios antes del lanzamiento. No mezclar con la Reserva Santa Elena |
| 20 | Guía «Cómo llegar» | Tiempos de traslado de fuentes públicas | Traslados SJO y LIR con costo adicional | Agregar que Basecamp los coordina; los tiempos siguen por verificar |
| 21 | Subtítulo de portada | «nuestro propia cafeteria» | — | Corregir (C-12) |

Ningún texto actual menciona mascotas, televisión, aire acondicionado, vistas ni sistemas de seguridad. Nada que retirar ahí.

---

## 4 · Textos propuestos

Sin rayas largas (regla de estilo del sitio). Sin montos, salvo lo que decida C-03. **[C-xx]** marca lo que depende de una decisión.

### 4.1 · Página principal

**Subtítulo de portada** (texto del propietario, con correcciones mínimas)
- **EN:** Ten rooms in the center of Santa Elena, Monteverde, with our own café downstairs pouring coffee from 6:00, an hour before the reserve opens.
- **ES:** Diez habitaciones en el centro de Santa Elena, Monteverde, con nuestra propia cafetería abajo, sirviendo café desde las 6:00, una hora antes de que abra la reserva.

**Bajo la barra de búsqueda** (necesita código, §5) [C-04]
- **EN:** Book direct and get a drink of your choice at Hanging Garden Café for every night of your stay.
- **ES:** Reserve directo y reciba una bebida a su elección en Hanging Garden Café por cada noche de su estadía.

**Presentación** (título «Small on purpose / Pequeño a propósito», se mantiene)
- **EN:** Basecamp Monteverde is a ten-room lodge in the center of Santa Elena, 50 meters from the church. Restaurants, shops and tour offices are all within walking distance, and our own café opens downstairs at 6:00. Leave your bags with us on your first and last day and make the most of both.
- **ES:** Basecamp Monteverde es un hospedaje de diez habitaciones en el centro de Santa Elena, a 50 metros de la iglesia. Restaurantes, tiendas y oficinas de tours quedan a pocos pasos, y nuestra propia cafetería abre abajo a las 6:00. Déjenos su equipaje el primer y el último día, y aproveche los dos.

**Tres razones**
1. **In the center of Santa Elena / En el centro de Santa Elena**
   - **EN:** 50 meters from the church, with everything in town on foot. The public bus to the Monteverde Cloud Forest Reserve leaves from Santa Elena five times a day.
   - **ES:** A 50 metros de la iglesia, con todo el pueblo a pie. El bus público a la Reserva Biológica Bosque Nuboso Monteverde sale de Santa Elena cinco veces al día.
2. **Rooms for two, three or four / Habitaciones para dos, tres o cuatro**
   - **EN:** The Quetzal Room for two, The Orchid Room for up to three and The Ceiba Room for four. Every room has a private bathroom with a hot shower and free Wi-Fi.
   - **ES:** El Quetzal para dos, La Orquídea para hasta tres y La Ceiba para cuatro. Todas tienen baño privado con agua caliente y Wi-Fi gratuito.
3. **Coffee from 6:00 / Café desde las 6:00**
   - **EN:** Hanging Garden Café is in the same building and opens at 6:00, an hour before the reserve. Breakfast isn't included in the rate, so have it there before you head out.
   - **ES:** Hanging Garden Café está en el mismo edificio y abre a las 6:00, una hora antes que la reserva. El desayuno no está incluido en la tarifa: desayune allí antes de salir.

**Sección del café**
- **Título EN:** Hanging Garden Café, in the same building
- **Título ES:** Hanging Garden Café, en el mismo edificio
- **EN:** Our own café, downstairs. Breakfast and coffee from 6:00, and a garden you're welcome to enjoy any time, no purchase needed.
- **ES:** Nuestra propia cafetería, abajo. Desayunos y café desde las 6:00, y un jardín que puede disfrutar cuando quiera, sin obligación de consumir.
- Se retiran «El Trapiche» y el cierre a las 19:00 hasta que se confirmen [C-07].

**Ubicación**
- **EN:** In the center of Santa Elena, 50 meters from the church, the town at the edge of the Monteverde cloud forest, at about 1,300 to 1,440 m above sea level. Arrive early or leave late: we keep your bags before check-in and after check-out.
- **ES:** En el centro de Santa Elena, a 50 metros de la iglesia, el pueblo a la orilla del bosque nuboso de Monteverde, entre unos 1300 y 1440 m sobre el nivel del mar. Llegue temprano o váyase tarde: le guardamos el equipaje antes de la entrada y después de la salida.

### 4.2 · Información del hotel (panel)

| Campo | EN | ES |
|---|---|---|
| Nota de dirección [C-06] | In the center of Santa Elena, 50 m south and 50 m east of the church. | Centro de Santa Elena, 50 m sur y 50 m este de la iglesia. |
| Hora de entrada | 15:00 | 15:00 |
| Hora de salida | 11:00 | 11:00 |

### 4.3 · Habitaciones (las tres, campos del panel)

Los nombres y descripciones aprobados (BD-021) no cambian.

| Campo | EN | ES |
|---|---|---|
| Baño | Private, with mirror and hot-water shower | Privado, con espejo y ducha con agua caliente |

**Comodidades** (en este orden):

| EN | ES |
|---|---|
| Free Wi-Fi | Wi-Fi gratuito |
| Windows to the outside | Ventanas al exterior |
| Towels and bed linen | Toallas y ropa de cama |
| Soap and toilet paper | Jabón y papel higiénico |
| Space to store or hang your clothes | Espacio para guardar o colgar la ropa |
| Bedside table | Mesita de noche |
| Power outlets | Tomacorrientes |
| Curtains or blinds | Cortinas o persianas |
| Your own lock and key | Cerradura individual con llave |

«Ventanas al exterior» tal como dice el memo: el memo no confirma que se abran, así que no se agrega.

### 4.4 · La estadía

**Texto**
- **EN:** Everything on this page is confirmed by Basecamp. If something you need isn't listed, ask us on WhatsApp before you book.
- **ES:** Todo lo de esta página está confirmado por Basecamp. Si algo que necesita no aparece, pregúntenos por WhatsApp antes de reservar.

**Incluido en cada estadía**

| EN | ES |
|---|---|
| Private bathroom with mirror and hot-water shower | Baño privado con espejo y ducha con agua caliente |
| Free Wi-Fi | Wi-Fi gratuito |
| Towels, bed linen, soap and toilet paper | Toallas, ropa de cama, jabón y papel higiénico |
| Free drinking water to refill your bottle | Agua potable gratuita para rellenar su botella |
| Luggage storage before check-in and after check-out | Guardado de equipaje antes de la entrada y después de la salida |
| The Hanging Garden Café garden, no purchase needed | Acceso al jardín de Hanging Garden Café, sin obligación de consumir |
| Free parking on the public street in front of the lodge | Estacionamiento gratuito en la vía pública, frente al hospedaje |
| Free early check-in when your room is ready | Entrada anticipada gratuita si su habitación está lista |
| Direct bookings: a drink at the café for every night [C-04] | Reservas directas: una bebida en el café por cada noche [C-04] |

**Con costo adicional**

| EN | ES |
|---|---|
| Breakfast at Hanging Garden Café, from 6:00 | Desayuno en Hanging Garden Café, desde las 6:00 |
| Late check-out until 13:00, subject to availability [C-03] | Salida tardía hasta las 13:00, sujeta a disponibilidad [C-03] |
| Transfers from San José (SJO) and Liberia (LIR) airports | Traslados desde los aeropuertos de San José (SJO) y Liberia (LIR) |
| Private or shared transport to other destinations, booked in advance | Transporte privado o compartido a otros destinos, con reservación anticipada |
| Tours and custom packages with Costa Rica Access Travel [C-10] | Tours y paquetes a la medida con Costa Rica Access Travel [C-10] |

**Reglas de la casa**

| EN | ES |
|---|---|
| Check-in from 15:00, check-out by 11:00 | Entrada desde las 15:00, salida hasta las 11:00 |
| Reception is open 7:00 to 21:00; later arrivals are arranged in advance | Recepción de 7:00 a 21:00; las llegadas más tarde se coordinan con anticipación |
| Come and go as you please | Entre y salga cuando quiera |
| No smoking in the rooms; there is no smoking area | No se fuma en las habitaciones; no hay área para fumar |
| Children of all ages are welcome; we don't have cribs | Niños de todas las edades bienvenidos; no tenemos cunas |

**Preguntas frecuentes** (con datos de preguntas para Google; reemplazan las 5 actuales)

1. **How many rooms does Basecamp have? / ¿Cuántas habitaciones tiene Basecamp?**
   - **EN:** Ten, for up to 29 guests in total: seven Orchid Rooms with a queen and a single bed for up to three, two Quetzal Rooms with a queen bed for two, and one Ceiba Room with two queen beds for four.
   - **ES:** Diez, para hasta 29 huéspedes en total: siete habitaciones La Orquídea con una cama queen y una individual para hasta tres, dos El Quetzal con una cama queen para dos y una La Ceiba con dos camas queen para cuatro.
2. **Is breakfast included? / ¿El desayuno está incluido?**
   - **EN:** No, breakfast isn't included in the rate. Hanging Garden Café, in the same building, opens at 6:00, an hour before the Monteverde reserve, so you can have breakfast there before heading out.
   - **ES:** No, el desayuno no está incluido en la tarifa. Hanging Garden Café, en el mismo edificio, abre a las 6:00, una hora antes que la Reserva Monteverde, así que puede desayunar allí antes de salir.
3. **What are the check-in and check-out times? / ¿Cuáles son los horarios de entrada y salida?**
   - **EN:** Check-in is from 15:00 and check-out is by 11:00. If your room is ready earlier, early check-in is free. You can also stay until 13:00 for a fixed fee, subject to availability. [C-03]
   - **ES:** La entrada es desde las 15:00 y la salida hasta las 11:00. Si su habitación está lista antes, la entrada anticipada es gratuita. También puede quedarse hasta las 13:00 por una tarifa fija, sujeto a disponibilidad. [C-03]
4. **Can I leave my luggage before check-in? / ¿Puedo dejar el equipaje antes de la entrada?**
   - **EN:** Yes, before check-in and after check-out. Enjoy your first and last day in Monteverde without carrying your bags.
   - **ES:** Sí, antes de la entrada y después de la salida. Disfrute su primer y su último día en Monteverde sin cargar las maletas.
5. **Is there parking? / ¿Hay estacionamiento?**
   - **EN:** Yes, free parking on the public street in front of the lodge. It isn't a private lot.
   - **ES:** Sí, estacionamiento gratuito en la vía pública, frente al hospedaje. No es un parqueo privado.
6. **What if I arrive after 21:00? / ¿Y si llego después de las 21:00?**
   - **EN:** Reception is open from 7:00 to 21:00. If you'll arrive later, write to us on WhatsApp in advance and we'll arrange your check-in.
   - **ES:** La recepción abre de 7:00 a 21:00. Si llega más tarde, escríbanos antes por WhatsApp y coordinamos su entrada.
7. **Can I book just one night? / ¿Puedo reservar una sola noche?**
   - **EN:** Yes, one-night stays are welcome.
   - **ES:** Sí, aceptamos estadías de una noche.
8. **How can I pay? / ¿Cómo puedo pagar?**
   - **EN:** In advance or on arrival, depending on your booking conditions. At the lodge we accept cash in colones or US dollars, and credit and debit cards.
   - **ES:** Por adelantado o al llegar, según las condiciones de su reserva. En el hospedaje aceptamos efectivo en colones o dólares, y tarjetas de crédito y débito.
9. **Can I cancel or change my dates? / ¿Puedo cancelar o cambiar mis fechas?** [C-05: solo cuando Hotel Link coincida]
   - **EN:** Cancellation is free until 24 hours before check-in; later cancellations and no-shows are charged one night. You can change your dates at no charge until 24 hours before check-in, subject to availability. If the new rate is higher you pay the difference, and if it's lower the difference is refunded as agreed.
   - **ES:** La cancelación es gratuita hasta 24 horas antes de la entrada; las cancelaciones posteriores y la no presentación tienen un cargo de una noche. Puede cambiar sus fechas sin penalidad hasta 24 horas antes, sujeto a disponibilidad. Si la nueva tarifa es mayor, paga la diferencia; si es menor, se le devuelve según lo acordado.
10. **Do you clean the room every day? / ¿Limpian la habitación todos los días?**
    - **EN:** We don't come into your room every day: it's your space. Ask us for fresh towels or anything else you need, and we'll bring it.
    - **ES:** No entramos a su habitación todos los días: es su espacio. Pídanos toallas limpias o lo que necesite, y se lo llevamos.
11. **Are children welcome? / ¿Se aceptan niños?**
    - **EN:** Children of all ages are welcome. We don't have cribs.
    - **ES:** Los niños de todas las edades son bienvenidos. No tenemos cunas.
12. **Do you have accessible rooms? / ¿Tienen habitaciones accesibles?** [C-09]
    - **EN:** None of our rooms is adapted for wheelchair users. If you have questions about access, write to us before you book.
    - **ES:** Ninguna de nuestras habitaciones está adaptada para silla de ruedas. Si tiene preguntas sobre el acceso, escríbanos antes de reservar.
13. **How do I get to the Monteverde reserve? / ¿Cómo llego a la Reserva Monteverde?**
    - **EN:** The public bus to the Monteverde Cloud Forest Reserve leaves from Santa Elena five times a day. Ask at reception for today's times.
    - **ES:** El bus público a la Reserva Biológica Bosque Nuboso Monteverde sale de Santa Elena cinco veces al día. Pregunte en recepción los horarios del día.
14. **Can you arrange transfers and tours? / ¿Pueden organizar traslados y tours?** [C-10]
    - **EN:** Yes. We arrange transfers from San José (SJO) and Liberia (LIR) airports at extra cost, and private or shared transport to other destinations booked in advance. For tours and custom packages, our sister company Costa Rica Access Travel has its office in the same building, open 7:00 to 21:00, or write to us on WhatsApp.
    - **ES:** Sí. Coordinamos traslados desde los aeropuertos de San José (SJO) y Liberia (LIR) con costo adicional, y transporte privado o compartido a otros destinos con reservación anticipada. Para tours y paquetes a la medida, nuestra empresa hermana Costa Rica Access Travel tiene su oficina en el mismo edificio, de 7:00 a 21:00, o escríbanos por WhatsApp.
15. **Why book directly with Basecamp? / ¿Por qué reservar directo con Basecamp?** [C-04]
    - **EN:** Booking on this website is booking straight with us, and every direct booking includes a drink of your choice at Hanging Garden Café for each night of your stay.
    - **ES:** Reservar en este sitio es reservar directamente con nosotros, y cada reserva directa incluye una bebida a su elección en Hanging Garden Café por cada noche de estadía.

No hay pregunta sobre mascotas hasta C-01.

### 4.5 · Ubicación y contacto

- **EN:** Basecamp Monteverde is in the center of Santa Elena, 50 meters from the church, so restaurants, shops and tour offices are all within walking distance. Reception is open from 7:00 to 21:00; if you arrive later, let us know on WhatsApp in advance and we'll arrange your check-in. Free parking is on the public street in front of the lodge. You can leave your bags with us before check-in and after check-out.
- **ES:** Basecamp Monteverde está en el centro de Santa Elena, a 50 metros de la iglesia, así que restaurantes, tiendas y oficinas de tours quedan a pocos pasos. La recepción abre de 7:00 a 21:00; si llega más tarde, avísenos antes por WhatsApp y coordinamos su entrada. El estacionamiento gratuito está en la vía pública, frente al hospedaje. Puede dejarnos el equipaje antes de la entrada y después de la salida.

### 4.6 · Grupos [C-08]

**Descripción para Google**
- **EN:** Book several rooms, up to all ten for 29 guests, for family, friends or a tour group in the center of Santa Elena, Monteverde.
- **ES:** Reserve varias habitaciones, hasta las diez para 29 huéspedes, para familia, amigos o un grupo de tour en el centro de Santa Elena, Monteverde.

**Texto**
- **EN:** Traveling as a group? Basecamp has ten rooms for up to 29 guests in total, including The Ceiba Room, our one room for four. Tell us your dates and how many you are, and we'll reply on WhatsApp with availability and a quote. We can also arrange airport transfers and tours.
- **ES:** ¿Viaja en grupo? Basecamp tiene diez habitaciones para hasta 29 huéspedes en total, incluida La Ceiba, nuestra única habitación para cuatro. Cuéntenos sus fechas y cuántos son, y le respondemos por WhatsApp con disponibilidad y una cotización. También coordinamos traslados desde el aeropuerto y tours.

Las condiciones para grupos siguen «pendientes» hasta que el propietario las escriba.

### 4.7 · Guías (siguen como muestra hasta verificarlas)

- **Cómo llegar a Monteverde:** agregar al final.
  - **EN:** We arrange transfers from SJO and LIR at extra cost. Ask us on WhatsApp.
  - **ES:** Coordinamos traslados desde SJO y LIR con costo adicional. Escríbanos por WhatsApp.
- **Reserva temprano:** se mantiene «cinco veces al día». La recepción confirma los horarios antes del lanzamiento, sin mezclarlos con los de la Reserva Santa Elena.

### 4.8 · Pagos (estado «Información», en la página de reserva)

- **EN:** Pay in advance or on arrival, depending on your booking conditions. At the lodge we accept cash in colones or US dollars, and credit and debit cards.
- **ES:** Pague por adelantado o al llegar, según las condiciones de su reserva. En el hospedaje aceptamos efectivo en colones o dólares, y tarjetas de crédito y débito.

---

## 5 · Cambios que necesitan código (autorización aparte)

| # | Cambio | Por qué |
|---|---|---|
| K-1 | Campo «Beneficio de reservar directo» (EN y ES) en el panel, mostrado bajo la barra de búsqueda de la portada, junto al botón de las habitaciones y en la página de reserva | Pedido de mercadeo (memo §4). Depende de C-04 |
| K-2 | Campo «Condiciones destacadas» (por ejemplo, «Cancelación gratuita hasta 24 horas antes») junto a los botones de reservar | Pedido de mercadeo (memo §3). Se activa solo cuando Hotel Link coincida (C-05) |
| K-3 | Campo «Estado» en La estadía, Ubicación, Privacidad y Grupos, para quitar la etiqueta «Contenido de prueba» al confirmarlas | Hoy esa etiqueta está fija en el código (auditoría de lanzamiento) |
| K-4 | Textos del código: «Sister café» en `llms.txt` y la etiqueta de tours del pie de página | Memo §5 (C-10) |
| K-5 | Ocultar la fila «Tamaño» de la habitación cuando esté vacía | Evita «pendiente» en la página pública |
| K-6 | Ajustar la prueba de «sin precios escritos» si se aprueba C-03 | Regla del proyecto |

---

## 6 · Qué no se toca

- Fotografías.
- Los nombres y descripciones de las habitaciones (BD-021).
- El diseño.
- Hotel Link, Booking.com y Airbnb.
- El motor de reservas (sigue en Prueba).
- El dominio y el DNS.
- Ningún detalle de sistemas o equipos de seguridad: la cerradura con llave se lista como comodidad de la habitación, como dice el memo.

## 7 · Cómo se aplicaría, con autorización

1. **Contenido (§4):** Claude edita los archivos de contenido en inglés y en español, sin tocar el diseño. Corre las pruebas y las revisiones de navegador y publica en la vista previa privada. El propietario revisa en la vista previa y puede corregir cualquier texto desde el panel.
2. **Código (§5):** solo con la autorización que corresponda.
3. **Condiciones de reserva y mascotas:** solo después de C-05 y C-01.
