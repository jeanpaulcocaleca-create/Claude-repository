# Motor de reservas independiente y futura pasarela bancaria · plan para aprobar

Fecha: 2026-10-21 · Autor: Claude · Pedido: ChatGPT, "Solicitud de diseño e implementación limitada", pegado por el propietario en el chat de Claude.

**Estado: propuesta. No se ha cambiado código.** Claude espera la aprobación expresa del propietario (BQ-40) antes de programar. Durante esta fase no se conecta Hotel Link ni ningún banco, no se escriben enlaces ni códigos reales y las reservas reales siguen apagadas.

Se apoya en decisiones ya tomadas: Hotel Link es la fuente de verdad (BD-011), el proveedor debe poder cambiarse (BD-012), $0 en suscripciones (BD-013), y el adaptador de reservas de `ARCHITECTURE.md` §5.

---

## 1 · Resumen y recomendación

- El sitio **nunca reserva, nunca cobra y nunca confirma**. Solo lleva al huésped, con sus fechas, al sistema que sí lo hace.
- Una sección nueva del panel, **«Motor de reservas»**, guarda uno o varios proveedores y cuál está activo. Cambiar o apagar un proveedor es un guardado en el panel, sin tocar código.
- **Recomendación:** empezar con Hotel Link como **enlace con parámetros**, no como widget incrustado. Un enlace no carga código de terceros en nuestras páginas ni cambia la seguridad del sitio, y casi cualquier motor lo admite.
- Tres estados: **Apagado** (hoy), **Prueba** (el sitio muestra el enlace que abriría, sin enviar al huésped) y **Activo** (sigue bloqueado hasta su autorización en Cloudflare).
- Pagos: se reserva una sección **apagada**. El sitio no maneja tarjetas, montos ni estados de pago.
- Costo: $0. Tiempo: una sesión de trabajo de Claude después de la aprobación.

---

## 2 · Reglas que el diseño no rompe

1. El sitio no guarda inventario, no tiene calendario propio y no calcula disponibilidad.
2. El sitio no muestra «reserva confirmada» ni «pagado». Esas palabras solo las dice el motor de reservas, el banco o el personal.
3. El panel guarda solo datos públicos: direcciones, códigos públicos e idiomas. Nunca contraseñas, tokens privados, llaves de API ni datos bancarios.
4. No se pega código HTML ni JavaScript en el panel. Un widget de terceros solo entra con un adaptador revisado por Claude (§4).
5. Las reservas reales necesitan dos llaves del propietario: el estado «Activo» en el panel **y** `BASECAMP_LIVE_BOOKING=authorized` en Cloudflare. Sin la segunda, el sitio no se publica y avisa por correo.
6. Siempre hay respaldo: WhatsApp y teléfono.

---

## 3 · Arquitectura

```
Página de Basecamp (nuestro diseño, EN y ES)
  │  formulario de fechas, huéspedes y habitación
  ▼
/book  y  /es/reservar
  │  lee la sección «Motor de reservas»
  ▼
Adaptador (un solo lugar del código)
  ├── Apagado ─────► vista previa o WhatsApp con el mensaje armado
  ├── Prueba  ─────► muestra el enlace que se abriría; no envía a nadie
  └── Activo  ─────► abre el motor del proveedor con fechas, idioma y habitación
                         │
                         ▼
               Motor del proveedor (Hotel Link u otro)
               disponibilidad, precio, reserva, cobro, confirmación
                         │
                         ▼
               Correo de confirmación del proveedor al huésped
```

**Qué es nuestro y qué es del proveedor**

| Nuestro (panel y sitio) | Del proveedor |
|---|---|
| Diseño, textos, fotos, habitaciones | Disponibilidad y precios |
| Formulario de fechas | Reserva y número de confirmación |
| Cuál proveedor está activo y en qué estado | Cobro o garantía con tarjeta |
| Códigos públicos de idioma y de habitación | Cancelaciones y cambios |
| Texto «Cómo se paga» | Sincronización con Booking.com y Airbnb |

---

## 4 · Qué motores se cambian con configuración y cuáles necesitan desarrollo

| Tipo | Cómo funciona | Se configura en el panel | Necesita desarrollo |
|---|---|---|---|
| **Contacto** | WhatsApp y teléfono con el mensaje armado | Sí, ya existe | No |
| **Enlace fijo** | Un botón abre la página de reservas del proveedor, sin fechas | Sí: solo la dirección | No |
| **Enlace con parámetros** | Abre la página del proveedor con fechas, huéspedes, idioma y habitación en la dirección | Sí: dirección con marcadores, formato de fecha, códigos de idioma y de habitación | No, **si el proveedor documenta cómo recibe esos datos**. Si no, se usa como enlace fijo |
| **Widget incrustado** | El buscador o la reserva del proveedor aparece dentro de nuestra página | Solo el código público de la propiedad, después del adaptador | Sí, una vez por proveedor: adaptador, permiso de seguridad (CSP) para su dominio y revisión de sus cookies (consentimiento) |
| **API** | Nuestro sitio consulta disponibilidad y crea reservas por su cuenta | No | Sí, grande: función en el servidor, llave secreta en Cloudflare, manejo de errores y de reservas simultáneas, y pruebas con el proveedor. **No recomendado** |

No se promete que cualquier motor funcione sin código. Cada proveedor nuevo se prueba en estado «Prueba» antes de activarse.

Ejemplos que publican una página de reservas con enlace propio: Hotel Link, Cloudbeds, Little Hotelier, SiteMinder y Beds24. Si aceptan fechas en la dirección, y con qué nombres, se confirma con la documentación de cada uno antes de usarlo.

---

## 5 · Sección del panel «Motor de reservas» (inicialmente apagada)

Reemplaza la sección actual «Integración de reservas» y conserva sus opciones «Vista previa» y «Contacto».

```
MOTOR DE RESERVAS

Estado          (•) Apagado: los botones llevan a la vista previa o a WhatsApp
                ( ) Prueba: el sitio muestra el enlace, sin enviar al huésped
                ( ) Activo: bloqueado hasta la autorización del propietario
Proveedor activo   [ Hotel Link ▾ ]     (elige de la lista de abajo)
Si el proveedor falla   ( ) Contacto por WhatsApp   (siempre disponible)

PROVEEDORES GUARDADOS
  Nombre                     Hotel Link
  Tipo                       Enlace con parámetros ▾   (Enlace fijo · Enlace con parámetros)
  Dirección de reserva       https://…?llegada={checkin}&salida={checkout}&adultos={guests}&idioma={lang}&habitacion={room}
  Formato de fecha           AAAA-MM-DD ▾   (DD/MM/AAAA · MM/DD/AAAA)
  Código del idioma inglés   [   ]
  Código del idioma español  [   ]
  Códigos de habitación      El Quetzal → [   ]  La Orquídea → [   ]  La Ceiba → [   ]
  Acceso al extranet         https://…   (solo un acceso directo para el propietario)
  Nota interna               …

PAGOS (reservado, apagado)   ver §7
```

**Marcadores permitidos en la dirección:** `{checkin}`, `{checkout}`, `{nights}`, `{guests}`, `{room}`, `{lang}` y `{promo}`. Cualquier otro detiene la publicación con un mensaje claro.

Los códigos de habitación pasan de la ficha de cada habitación a cada proveedor. Así, al cambiar de proveedor, cada uno conserva los suyos.

---

## 6 · Validaciones y seguridad

Antes de publicar, el sitio revisa la sección. Si algo falla, no publica, la vista previa conserva su última versión buena y GitHub avisa por correo.

| Revisión | Qué evita |
|---|---|
| Solo `https://`, sin usuario ni contraseña dentro de la dirección, sin `javascript:` ni direcciones IP | Enlaces inseguros o engañosos |
| Rechaza parámetros con nombres como `token`, `key`, `secret`, `password`, `api_key` o `auth` | Que alguien pegue una credencial privada |
| Códigos públicos: solo letras, números, `-` y `_`, hasta 64 caracteres | Códigos mal pegados o con espacios |
| Marcadores conocidos solamente; formato de fecha de la lista | Enlaces que el proveedor no entiende |
| «Activo» exige `BASECAMP_LIVE_BOOKING=authorized` en Cloudflare | Activar reservas reales por un clic en el panel |
| El tipo «enlace» no cambia la política de seguridad de la página ni carga scripts de terceros | Código ajeno en Basecamp |
| La prueba «sin secretos en el repositorio» también revisa el contenido del panel | Credenciales guardadas por error |

---

## 7 · Pagos bancarios: separar reserva, pago y confirmación

**No se asume** que el banco tenga API, avisos automáticos ni confirmación instantánea. Hoy la garantía es la tarjeta capturada en Hotel Link (`RESERVATIONS.md` §2).

| Paso | Quién lo hace y lo registra | Qué muestra el sitio |
|---|---|---|
| 1. Búsqueda | El huésped, en nuestro sitio | «Ver precios y disponibilidad» |
| 2. Reserva | El motor del proveedor; da el número | Nada propio; el motor muestra su página |
| 3. Pago o garantía | Proveedor, banco o personal, según las condiciones del propietario | Solo el texto «Cómo se paga» |
| 4. Confirmación | El motor, o el personal cuando la condición es un depósito | Nada; el huésped recibe el correo del motor |

**Sección «Pagos», reservada y apagada.**
- Estado: Apagado o Información.
- Texto «Cómo se paga» en EN y ES.
- Método previsto: enlace de pago que el personal envía por reserva, página de pago del banco, o SINPE Móvil.
- Opcional: la dirección de la página de pago del banco, con la misma validación del §6.

Reglas:
- El sitio no calcula ni muestra montos (BD-011).
- El sitio no recibe datos de tarjetas.
- El sitio no marca nada como pagado.
- El estado del pago vive en el motor o en el registro del personal.

**Antes de activar pagos, preguntas para el banco** (las envía el propietario):
- ¿Ofrecen enlaces de pago por monto y referencia?
- ¿La página de pago es del banco?
- ¿Envían comprobante al comercio y al cliente?
- ¿Tienen avisos automáticos o API?
- ¿Qué comisiones cobran?
- ¿Aceptan cargos en dólares?

---

## 8 · Prevención de sobreventa

- El inventario vive solo en el motor del proveedor, que ya sincroniza Booking.com y Airbnb.
- El sitio no copia disponibilidad ni usa calendarios iCal para decidir nada.
- En modo Contacto, el mensaje dice que Basecamp confirmará la disponibilidad. El personal revisa Hotel Link antes de responder.
- Al cambiar de proveedor, solo uno puede estar conectado a cada OTA (`ARCHITECTURE.md` §5.3).
- El tipo API, si algún día se pide, no se activa sin documentación escrita del proveedor sobre retención y confirmación de habitaciones y sin pruebas.

---

## 9 · Hotel Link: pasos para conectar y desconectar (borrador para el propietario)

Se completa cuando Hotel Link responda cómo recibe fechas, idioma y habitación en la dirección (`HOTEL-LINK-PREGUNTAS.md`). Hasta entonces el sitio no tiene datos reales.

**Conectar en prueba (el propietario, sin Claude)**
1. En el extranet de Hotel Link, abra «Booking Engine» y luego «Booking Widget». Copie la dirección de la página de reservas (es pública).
2. En el panel, abra «Motor de reservas» y luego «Proveedores guardados», y agregue «Hotel Link».
3. Pegue la dirección y cambie las fechas de ejemplo por `{checkin}` y `{checkout}`, según el formato que indique Hotel Link. Complete los códigos de idioma y de habitación.
4. Ponga el estado en «Prueba» y guarde. En uno o dos minutos la vista previa se actualiza.
5. En la vista previa, elija fechas y toque «Ver precios y disponibilidad». El sitio muestra el enlace que abriría.
6. Abra ese enlace y revise que Hotel Link muestre las mismas fechas, huéspedes, idioma y habitación. **No complete el pago:** sería una reserva real.
7. Repítalo en español y en el teléfono.

**Activar (solo con autorización y en el lanzamiento)**
1. El propietario autoriza por escrito.
2. En Cloudflare, el propietario agrega `BASECAMP_LIVE_BOOKING=authorized`.
3. En el panel, el estado pasa a «Activo».

**Desconectar o volver atrás (en cualquier momento, en un minuto)**
1. En el panel, ponga el estado en «Apagado» o elija «Contacto» y guarde. Los botones vuelven a WhatsApp.
2. Si algo salió mal, cada guardado queda en el historial de GitHub y se puede deshacer.
3. Las reservas ya hechas siguen en Hotel Link: apagar el sitio no las borra ni las cambia.

---

## 10 · Pruebas previstas, sin reservas reales

- Cada estado: Apagado (vista previa y Contacto), Prueba (muestra el enlace y no redirige) y Activo (redirige solo con la llave de Cloudflare, en una copia de prueba con un proveedor ficticio `booking.example.com`).
- Enlaces armados en EN y ES: fechas en los tres formatos, huéspedes, idioma, habitación y código promocional, bien codificados.
- La validación rechaza `http://`, credenciales en la dirección, parámetros prohibidos, marcadores desconocidos y códigos con espacios.
- Desconectar devuelve WhatsApp en todas las páginas.
- El sitio no muestra «confirmada» ni «pagado» y no carga scripts de terceros con el tipo enlace.
- Pagos apagados no muestran nada; en modo Información muestran solo el texto.
- Accesibilidad, 360 px y control de seguridad de la vista previa, como en la Fase 2.
- El panel de demostración permite agregar un proveedor ficticio, ponerlo en Prueba y volver a Apagado.

---

## 11 · Alcance

**Entra, si se aprueba:**
- La sección del panel apagada.
- El adaptador genérico de enlace.
- El estado Prueba.
- Las validaciones.
- La sección Pagos reservada.
- Las instrucciones para el propietario en `basecamp-website`.
- Las pruebas.

**No entra:**
- Datos reales de Hotel Link.
- El widget incrustado de Hotel Link.
- APIs.
- Pagos activos.
- Calendarios o disponibilidad propios.
- Cambios en Hotel Link, Booking.com o Airbnb.
- Lanzamiento.
- Cambios de DNS.

---

## 12 · Riesgos

| Riesgo | Probabilidad | Mitigación |
|---|---|---|
| Hotel Link no acepta fechas en la dirección | Media | Se usa como enlace fijo; el huésped elige fechas en Hotel Link |
| Una prueba termina en una reserva real | Baja | Instrucción explícita; preguntar a Hotel Link si tiene modo de prueba |
| Error al pegar datos en el panel | Media | Validación, estado Prueba e historial de GitHub |
| El widget incrustado se pide más adelante | Media | Adaptador aparte; revisar sus cookies con el aviso de consentimiento |
| El banco no tiene enlaces ni avisos | Media | Pagos queda como información; el personal concilia en el banco |
| Expectativa de que cualquier motor funcione sin código | Media | Tabla del §4 en el panel y en las instrucciones |

---

## 13 · Decisiones del propietario

| ID | Decisión | Recomendación de Claude |
|---|---|---|
| BQ-40 | Aprobar este plan y su alcance (§11) | Aprobar |
| BQ-40a | El estado «Prueba» solo muestra el enlace y no envía al huésped | Sí |
| BQ-40b | Hotel Link primero como enlace con parámetros y no como widget incrustado | Sí; revisar el widget cuando Hotel Link responda |
| BQ-40c | La sección Pagos se reserva apagada, solo con información | Sí; el banco se elige después |
