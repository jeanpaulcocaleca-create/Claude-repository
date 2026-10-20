# Decisiones pendientes del propietario · tabla consolidada

**Estado: ON HOLD, sin GO.** Esta tabla reúne todo lo que espera la palabra del propietario. Las recomendaciones son de Claude, con los aportes de Muse (Lapis) y ChatGPT donde los hay. **Ninguna recomendación es una aprobación.** Solo cuenta lo que el propietario escriba en el chat de Claude.

Preparada el 2026-10-20 a pedido de ChatGPT. Fuentes: `CODEX.md` sección 8, `RESERVATIONS.md` §9.7, `ARCHITECTURE.md` §11, `STRATEGY-REVIEW.md`.

**Costo mensual nuevo de todo lo recomendado: $0.** Los únicos costos son los que ya existen (dominio, Hotel Link, comisiones de tarjeta) y, si se aprueban, gastos únicos opcionales: revisión legal y contable, y un disco externo para respaldos.

---

## Estado después de la dirección del propietario (BD-015, 2026-10-20)

El propietario adoptó la estrategia de Muse y Lapis integrada con la arquitectura de Claude. **Es dirección de planificación, no el GO.**

**1. Decisiones de planificación aprobadas**
- **D-01:** la arquitectura, como dirección.
- **D-02:** el alcance.
- **D-03:** la conversión.
- **D-04:** los precios.
- **D-05:** la medición, con cambios: el píxel desde el lanzamiento con consentimiento y la API de Conversiones pospuesta.
- **D-07:** el repositorio, que se crea solo en la fase de construcción.
- **D-09:** la política de acceso de los asistentes de IA, sin acceso concedido todavía.
- **D-10:** solo el propietario publica.
- **D-11:** el mensaje para Hotel Link, que está listo para enviar.
- **D-12:** el kit de marca, construido sobre la identidad que ya existe.

**2. Opciones técnicas pendientes de verificación**
- **D-06:** Cloudflare Pages con repositorio privado, que es la preferida.
- **D-08:** la entrada al panel con una clave limitada. La evidencia está en `ARCHITECTURE.md` §11.2 y la prueba se hace al empezar el GO.
- **La selección técnica final de D-01:** Sveltia CMS y las vistas previas.
- **La API de Conversiones,** pospuesta.

**3. Políticas operativas todavía no aprobadas**
- **R-01 a R-10.** Las políticas actuales de Hotel Link no se cambian.

**4. Acciones reservadas para después del GO**
- Crear el repositorio.
- Crear la cuenta gratuita de Cloudflare.
- Dar acceso de escritura a Claude solo en ese repositorio.
- Hacer la prueba del panel y de la vista previa.
- Programar el sitio y la medición.

Las tablas de abajo se conservan como referencia del momento en que se prepararon.

---

## Cómo aprobar

Escriba en el chat de Claude una línea como esta:

> Apruebo D-01 a D-12 y R-01 a R-10 según la recomendación de Claude, excepto: …

Aprobar estas decisiones **no es el GO** para construir. El GO se da por separado.

---

## A. Esenciales antes del GO

Definen cómo se construye. Sin ellas no se puede empezar.

| Ref | Pregunta | Opciones | Recomendación y por qué | Costos, riesgos, consecuencias | ¿Quién decide? |
|---|---|---|---|---|---|
| **D-01** | ¿Aprueba la arquitectura general: sitio estático bilingüe, Owner Dashboard con Sveltia CMS, adaptador de reservas, respaldos en su Mac y los criterios de calidad propuestos? | Aprobar · Pedir cambios | **Aprobar.** Cumple sus cuatro requisitos: panel propio, Hotel Link como fuente de verdad, cambiar de proveedor sin rehacer el sitio, y cero suscripciones nuevas. | $0 al mes. Depende de servicios gratuitos que pueden cambiar sus condiciones; cada uno tiene una salida (`ARCHITECTURE.md` §11.8). | Propietario |
| **D-02** · BQ-34 | ¿Qué alcance tiene el sitio? | (a) Basecamp más una biblioteca de guías; tours como guías que enlazan al operador; el café como sección completa de la experiencia del hotel, enlazada a su propio sitio · (b) Secciones separadas de café y tours dentro del sitio, como proponía Muse al inicio | **(a).** Claude y Muse coinciden. Las guías traen búsquedas nuevas. El café vende la estadía sin competir con su propio sitio por las mismas búsquedas. | $0. La opción (b) cambiaría su decisión BD-006 y duplicaría contenido del sitio del café. | Propietario |
| **D-03** · BQ-35 | ¿Cuál es el botón principal? | (a) Por tipo de página: **Reservar** primero en habitaciones, **WhatsApp** primero en guías · (b) Solo WhatsApp en todo el sitio | **(a).** Claude y Muse coinciden. Usted ya tiene reserva instantánea; en las guías la gente pregunta antes de comprar. Se miden los dos. | $0. Con (b) se desaprovecha la reserva instantánea que usted eligió (BD-009). | Propietario |
| **D-04** · BQ-31 | ¿Cómo se muestran los precios? | (a) Precio "desde" en vivo de Hotel Link si lo permite; si no, qué incluye la tarifa más un botón "Ver precio de hoy" · (b) Precio escrito a mano en el panel | **(a).** Claude, Muse y ChatGPT coinciden. El precio nunca queda desactualizado, y la ley 7472 exige precios finales correctos. | $0. Con (b), cada cambio de tarifa en Hotel Link deja un precio viejo en el sitio. | Propietario |
| **D-05** · BQ-36 | ¿Se instala la medición desde el primer día? | (a) Google Analytics 4, Search Console, píxel de Meta y la API de Conversiones en un servidor gratuito de Cloudflare, todo tras un aviso de cookies, con el mapa de eventos permanente y sin conteos dobles · (b) Sin medición por ahora · (c) Solo Google Analytics y Search Console | **(a).** Muse lo recomienda con esas dos condiciones, y ya están en el plan. Medir después pierde todo el historial. | $0. Exige el aviso de consentimiento (ley 8968). Las reservas completadas solo se miden si Hotel Link lo permite (D-11). | Propietario |
| **D-06** · BQ-28 | ¿Dónde se aloja el sitio? | (a) Cloudflare Pages con repositorio privado · (b) GitHub Pages con repositorio público | **(a).** ChatGPT también. Los borradores quedan privados y el sitio recibe protecciones de seguridad del navegador. | $0. Requiere una cuenta gratuita de Cloudflare y, al lanzar, pasar el DNS del dominio a Cloudflare, copiando antes los registros del correo. | Propietario |
| **D-07** · BQ-10 | ¿Se crea un repositorio nuevo, separado del café? ¿Con qué nombre? | Sí, con nombre propuesto `basecamp-website` · Otro nombre · No | **Sí, privado, en su cuenta de GitHub.** Un repositorio sirve un solo dominio, y separarlo protege el sitio del café. Se crea después del GO, por usted o por Claude con su permiso. | $0. | Propietario |
| **D-08** · BQ-32 | ¿Cómo entra usted al panel? | (a) Una clave de acceso de GitHub limitada al repositorio de Basecamp · (b) El botón "Entrar con GitHub" | **(a).** Con (b), el panel tendría acceso a todos sus repositorios, incluido el sistema del café, y necesitaría un servicio extra. | $0. Con (a) se pega la clave una vez por dispositivo y se renueva antes de que venza. | Propietario |
| **D-09** · BQ-33 | ¿Qué acceso tienen los asistentes de IA, como Claude o Codex, al repositorio de Basecamp? | Ninguno · Solo lectura · Escritura | **Escritura solo durante la construcción**, mientras el dominio aún no apunta al sitio nuevo, trabajando en ramas que usted aprueba. **Después del lanzamiento, solo lectura** por defecto, y escritura únicamente para una tarea concreta. | $0. Los asistentes actúan con su identidad de GitHub, así que este permiso es el único control real. | Propietario |
| **D-10** · BQ-29 | ¿Quién más puede editar el sitio? | Solo usted · Usted más personal de confianza | **Solo usted al inicio.** ChatGPT coincide. En un repositorio privado gratuito no se puede obligar a que otro editor espere su aprobación. | $0. Agregar editores después requiere confianza, un repositorio público o un plan pagado. | Propietario |
| **D-11** · BQ-24 | ¿Se envían ya las 13 preguntas a Hotel Link (`RESERVATIONS.md` §8)? | Sí, ahora · Más adelante | **Sí, ahora.** La pregunta 13, sobre medir reservas en su página de pago, es de negocio según Muse y condiciona cualquier campaña pagada. | $0. Claude no contacta proveedores; las envía usted o ChatGPT. | Propietario |
| **D-12** · BQ-05 | ¿Tiene Basecamp logo, colores y tipografía? Si no, ¿autoriza a Claude a proponer un kit de marca? | Usar la marca actual · Que Claude proponga uno para su aprobación | **Que Claude proponga**, salvo que ya exista una marca. Dirección naturalista tipo cuaderno de campo, como pide el plan de Muse y en armonía con el café. | $0. Diseño sin marca definida termina pareciendo plantilla, y Muse lo marca como antipatrón. | Propietario |

---

## B. Reservaciones, antes de conectar las reservas (fase 3)

Nada de esto cambia Hotel Link todavía. El propietario hace los cambios en Hotel Link cuando lo decida, después de las verificaciones.

| Ref | Pregunta | Opciones | Recomendación y por qué | Costos, riesgos, consecuencias | ¿Quién decide? |
|---|---|---|---|---|---|
| **R-01** · §9.7-1 | ¿Se adopta la tarifa flexible como estándar y se retiran las condiciones actuales, que son 50% de depósito siempre y penalidad de toda la estadía dentro de 22 días? | Sí · No · Sí con cambios | **Sí, pero aplicarla solo después de confirmar** con Hotel Link la hora límite y la penalidad por noches, y con el banco el cobro sin tarjeta presente. Es lo que usted pidió, y se ajusta a las reglas de Visa: una noche por no presentarse. | La política actual invita a disputas de cargos. La flexible puede subir un poco las cancelaciones. | Propietario |
| **R-02** · §9.7-2 | ¿A qué hora son la entrada y la salida, y a qué hora exacta vence la cancelación gratuita? | Las que usted indique | **Hora límite: la misma hora de entrada, el día anterior a la llegada.** Así "24 horas" queda escrito como una hora exacta y sin dudas. | Ninguno. Debe coincidir con lo que Hotel Link aplica de verdad. | Propietario |
| **R-03** · §9.7-3 | ¿Se ofrece la tarifa con 50% de depósito? ¿Cuándo, con qué reembolso y con descuento o no? | No ofrecerla · Solo en fechas pico y grupos · Siempre como opción prepagada más barata | **Solo en fechas pico y para grupos, con depósito reembolsable** hasta los días que usted fije. Una tarifa no reembolsable, solo después de la revisión legal (R-07). | Exige cobrar el depósito a mano en la terminal, porque el cobro automático necesita Hotel Link Pay o Tilopay. | Propietario |
| **R-04** · §9.7-4 | Si un huésped se va antes, ¿qué se cobra? | Las noches no usadas · Una noche · Nada | **Una noche**, si no avisó con la misma anticipación de la cancelación. Es coherente con la penalidad de la primera noche y fácil de explicar. | Ninguno importante. Debe aparecer escrito en las condiciones. | Propietario |
| **R-05** · §9.7-5 | ¿Se alinean Booking.com y Airbnb con las mismas condiciones? | Iguales en todos los canales · Más estrictas en los canales | **Iguales.** En Booking.com, cancelación gratuita hasta un día antes y primera noche por no presentarse. En Airbnb, la política "Flexible". Menos confusión y menos disputas. | Las cancelaciones en los canales pueden subir un poco. | Propietario |
| **R-06** · §9.7-6 | ¿Quién del personal puede ver los datos de tarjeta en Hotel Link? | Solo usted · Usted y un encargado | **Usted y una sola persona de confianza.** Nunca anotar tarjetas en papel, WhatsApp ni correo. | Menos personas significa menos riesgo de fraude. | Propietario |
| **R-07** · BQ-26 | ¿Contrata una revisión de abogado y contador de las condiciones finales? | Sí · No | **Sí, antes de publicar las condiciones.** Hay dudas reales: el derecho de retracto de 8 días, el IVA de penalidades y depósitos, la factura electrónica y el aviso de privacidad. | Gasto único, no mensual. Sin revisión, el riesgo es legal y fiscal. | Propietario |
| **R-08** · BQ-27 | ¿Consulta al banco si su terminal acepta cobros con la tarjeta no presente para penalidades? | Sí · No | **Sí, ahora.** Sin eso, la penalidad de una noche no se puede cobrar. | $0, salvo la comisión del banco. | Propietario, gestión |
| **R-09** · BQ-14 | ¿Siguen vigentes estas reglas de la casa: menores de 12 gratis compartiendo camas, sin mascotas salvo animales de servicio, no fumar adentro, silencio de 22:00 a 7:00? | Sí · Cambiar alguna | **Mantenerlas si siguen siendo ciertas.** Venían del sitio anterior de Orchid Lodge. | Ninguno. | Propietario |
| **R-10** · BQ-09 | ¿Se mantiene el cobro actual: captura de tarjeta y cobro manual con Visa y Mastercard, sin Hotel Link Pay ni Tilopay por ahora? | Mantener · Activar Hotel Link Pay o Tilopay | **Mantener.** Ya funciona y no agrega costos. Revisarlo si cobrar a mano se vuelve pesado. | $0 nuevo. Tilopay cobra 4,25% + $0,35 por transacción, sin mensualidad. | Propietario |

---

## C. Pueden esperar: información o fases posteriores

| Ref | Qué falta | Para cuándo | Recomendación |
|---|---|---|---|
| BQ-02, BQ-19 | Nombre de cada tipo de habitación, baño, tamaño, amenidades, fotos y **qué incluye la tarifa, por ejemplo si hay desayuno** | Contenido de la fase 2 | Enviar cuando pueda; mientras tanto se usan espacios vacíos |
| BQ-06 | Archivo original de la foto de nubes, u otorgar acceso de red al sitio actual | Diseño, fase 2 | Cualquiera de los dos |
| BQ-30 | Respaldos en su Mac con Time Machine y un segundo disco fuera del hotel | Fase 4 | ChatGPT y Claude coinciden: la Mac. Puede aprobarlo ya |
| BQ-07 | Quién es el registrador del dominio y si el dominio tiene correo | Antes del lanzamiento | Necesario antes de mover el DNS |
| BQ-15 | Acceso al dominio y a las fichas viejas de Orchid Lodge | Lanzamiento | Renombrar las fichas para conservar las reseñas |
| BQ-13 | Perfil de Google de Basecamp y quién lo administra | Fases 4 y 6 | |
| BQ-03 | A qué página de tours se enlaza | Fase 2 | |
| BQ-04 | Si el transporte privado sigue | Fase 2 | |
| BQ-08 | Otros canales de reserva además de Booking.com y Airbnb | Fase 3 | |
| BQ-11 | Horario de recepción y si hay cerraduras inteligentes | Fases 3 y 4 | |
| BQ-12 | Tipo de huéspedes y otros idiomas | Fase 2 | |
| BQ-20 | Derechos de uso de fotos y reseñas | Fase 2 | |
| BQ-21 | Números de las metas | Al lanzar, como sugiere Muse | |
| BQ-25 | Plan y precio de Hotel Link, y las capturas para Claude | Fase 3 | Enviarlas en el chat, nunca al repositorio público |

---

## D. Las resuelve Claude, sin decisión del propietario

Claude las prepara y las muestra; el propietario solo las revisa.

- **BQ-18:** mapa de redirecciones de las direcciones actuales. Necesita acceso de red al sitio actual o una exportación de WordPress.
- **BQ-22:** procedimientos ante reservas simultáneas, fallas de calendario y caídas, como borrador para su revisión.
- Configuración del panel, cadena de imágenes, protecciones de seguridad, herramienta del aviso de cookies, mapa de eventos ya fijado (`STRATEGY-REVIEW.md` §12) y pruebas técnicas pendientes (`ARCHITECTURE.md` §11.7).

---

## E. Ya decidido; no se vuelve a preguntar

| Decisión | Qué dice |
|---|---|
| BD-003, BD-013 | Cero suscripciones mensuales nuevas |
| BD-004 | Nada se construye sin GO |
| BD-006 | El sitio es de Basecamp; café y tours como enlaces. D-02 solo afina cómo se presentan |
| BD-008 | Orchid Lodge fue el nombre anterior del hotel |
| BD-009 | Reserva directa con confirmación instantánea |
| BD-010 | Owner Dashboard privado y fácil |
| **BD-011** | **Hotel Link es la fuente de verdad de tarifas, disponibilidad y reservas. Esto responde la BQ-16.** |
| BD-012 | Poder cambiar de proveedor de reservas |
| BD-014 | El plan de Muse forma parte del proyecto |
| Confirmados | 10 habitaciones (7 para 3, 2 para 2, 1 para 4); café de 6:00 a 19:00 |
