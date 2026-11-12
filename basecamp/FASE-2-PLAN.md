# Fase 2 · Auditoría y plan (propuesta, sin implementar)

Fecha: 2026-10-21 · Autor: Claude · Pedido: mensaje de ChatGPT "Planning request, Phase 2", pegado por el propietario. **Nada de esto está autorizado todavía**: se ejecuta solo con un GO expreso del propietario.

Se mantienen el diseño actual, Cloudflare Pages, GitHub y el panel. Sin suscripciones ni pagos, sin tocar lo que ya pasó las pruebas, sin publicar y sin reservas reales.

## 1 · Estado actual del sitio

Vista previa privada: https://basecamp-website-b99.pages.dev (repositorio privado `basecamp-website`).

| Área | Completo | Provisional | Falta |
|---|---|---|---|
| Infraestructura | Repositorio privado; Cloudflare Pages gratis; contraseña; revisión de seguridad 91/91 en cada cambio; `noindex` | | Respaldo automático en la Mac (P-12) |
| Páginas (24, EN y ES) | Inicio, habitaciones (índice y 3 tipos), La estadía, guías (índice y 2), ubicación, reservar, privacidad, 404 | Todo el texto es de prueba; las guías usan datos públicos "a verificar" | Fotos (galería) y Grupos, previstas en el modelo de hotel (`CODEX.md` §4) |
| Diseño | Tipografía, colores, modo oscuro, logo, teléfono primero; 0 fallas de accesibilidad; sin desplazamiento lateral a 360 px | Ilustraciones hechas en código en lugar de fotos | Fotos reales; las 3 de Higgsfield sin descargar |
| Panel | Inicio, Habitaciones, Guías, Páginas, Información del hotel, Integración de reservas; EN y ES lado a lado; fotos a WebP; auditoría BD-019 PASS | | Promociones, Galería, Reseñas reales, Seguimiento (previstos en `ARCHITECTURE.md` §2.2) |
| Reservas | Adaptador con 4 modos; modos reales bloqueados; fechas corregidas | Modo "vista previa" | Conexión con Hotel Link (§3) |
| Medición | Capa de eventos con `event_id`, sin etiquetas | | Banner de consentimiento, GA4, Search Console y Pixel (D-05) |
| Legal | | Privacidad en borrador | Aviso de privacidad final y condiciones de reserva revisados por abogado (BQ-26) |

## 2 · Contenido real que falta (lo da el propietario, se carga en el panel)

| Dónde en el panel | Qué falta | Pregunta |
|---|---|---|
| Habitaciones, para cada uno de los 3 tipos | Nombre definitivo, descripción, baño, tamaño en m², comodidades, código del tipo de habitación en Hotel Link | BQ-02, BQ-19 |
| Habitaciones → Fotos | 3 a 6 fotos reales por tipo, sin personas reconocibles. **Reemplazar la foto de prueba de Queen Room** (muestra el café, con personas al fondo) | BQ-02, BQ-20 |
| Página principal | Foto principal real (o la de Higgsfield cuando se descargue) y los textos finales | BQ-06 |
| La estadía | Qué incluye la tarifa (¿desayuno?), qué se paga aparte, reglas de la casa (niños, mascotas, fumar, silencio), horarios de entrada y salida | BQ-14, BQ-19 |
| Información del hotel | Dirección exacta (¿mismo edificio que el café?), correo, ubicación exacta en el mapa, redes sociales | BQ-07, BQ-13 |
| Información del hotel | Página de tours y si sigue el transporte privado | BQ-03, BQ-04 |
| Guías | Confirmar o corregir horarios y tiempos de viaje; nuevos temas que preguntan los huéspedes | BD-007 |
| Reseñas | Enlaces a reseñas reales (Google, Booking.com, TripAdvisor, las de Orchid Lodge) | BQ-15 |

## 3 · Hotel Link: qué está listo y qué falta (sin tocar Hotel Link)

**Listo en el sitio:** el modo `hotel-link` del adaptador arma la dirección de reserva con `{checkin}`, `{checkout}`, `{guests}` y `{room}`; cada tipo de habitación tiene su campo "código en el sistema de reservas"; el botón Reservar ya registra la intención de reserva (`begin_checkout`); la construcción se niega a activar el modo real sin autorización.

**Falta, y depende de las respuestas de Hotel Link** (`HOTEL-LINK-PREGUNTAS.md`, que el propietario envía; no hay respuesta registrada):

| Necesitamos saber | Por qué |
|---|---|
| La dirección exacta del motor y los nombres de sus parámetros (fechas, huéspedes, tipo de habitación) y su formato de fecha | Para llenar la plantilla del adaptador |
| Si se puede abrir directo en español | Bilingüe de punta a punta |
| Si se puede pasar un código promocional por la dirección | Para las promociones (§4) |
| Si el motor se incrusta (iframe o script) o se abre aparte | Si se incrusta, la política de seguridad del sitio debe permitir ese dominio: un cambio pequeño pero obligatorio |
| Pregunta 13: medición en su pago y página de regreso tras reservar | Distinguir intención de reserva y reserva completada (D-05) |
| Cómo se ven sus condiciones de reserva | La página de condiciones debe coincidir palabra por palabra (BD-009, Ley 7472) |

Después de las respuestas, la prueba se hace en una rama de prueba, también protegida con contraseña, sin reservas reales. Activar reservas reales necesita otro GO.

## 4 · Promociones y descuentos en el panel (propuesta)

Regla de base (BD-011, D-04): **el precio y el descuento reales viven solo en Hotel Link.** El panel solo anuncia lo que ya existe allí.

- **Colección nueva "Promociones"**, con: título, texto y condiciones (obligatorias) en EN y ES; fecha de inicio y de fin; dónde se muestra (aviso superior, tarjeta en inicio, habitaciones elegidas); código promocional opcional; y la casilla **"Ya está configurada en Hotel Link"**.
- **Candados en la construcción:**
  - no se muestra si falta la casilla, las condiciones o un idioma;
  - no acepta montos escritos a mano ($, USD, ₡), solo porcentajes o beneficios ("cuarta noche gratis");
  - se oculta sola al pasar la fecha de fin, también en el navegador del visitante, sin servicios extra.
- **El botón** "Reservar con esta promoción" usa el adaptador. Si Hotel Link acepta el código en la dirección, va incluido; si no, el sitio muestra el código para copiarlo.
- **Costo:** $0. No cambia el diseño: usa las tarjetas y el aviso que ya existen.

## 5 · SEO, bilingüe y buscadores de IA

Revisado sobre el sitio construido el 2026-10-21.

| Punto | Estado |
|---|---|
| Título único por página | Bien: 24 de 24 |
| Gemela en el otro idioma y `hreflang` (en, es, x-default) | Bien: 24 de 24 |
| `canonical`, mapa del sitio con idiomas (24 direcciones), imagen para compartir | Bien |
| Descripción para Google | 11 páginas tienen menos de 70 caracteres (habitaciones, privacidad, reservar y otras); conviene 120 a 155 |
| Datos estructurados | Inicio: LodgingBusiness básico; guías: Article; La estadía: FAQPage. Faltan HotelRoom (sin precios) en habitaciones, BreadcrumbList, y en LodgingBusiness: coordenadas, horarios, comodidades y `sameAs` (Google, Booking.com, Airbnb, TripAdvisor) |
| Buscadores de IA | No hay `llms.txt`. Falta decidir si se permite a los rastreadores de IA (GPTBot, OAI-SearchBot, ClaudeBot, PerplexityBot, Google-Extended) al lanzar |
| Herramientas gratis | Google Search Console y Bing Webmaster Tools (la búsqueda de ChatGPT usa Bing), con IndexNow: se activan al lanzar |
| Contenido en español | Completo y nativo en estructura; falta que el propietario revise el tono final |
| Visibilidad fuera del sitio | Lo que más pesa para Google Maps y la IA: perfil de Google de Basecamp y renombrar las fichas de Orchid Lodge sin perder sus reseñas (BQ-13, BQ-15) |

Mientras sea vista previa, todo sigue bloqueado para buscadores, como corresponde.

## 6 · Plan por prioridades (para aprobar)

| Prioridad | Trabajo | Quién | Necesita |
|---|---|---|---|
| **1** | Cargar el contenido real del §2 en el panel | Propietario | Fotos y datos |
| **1** | Enviar `HOTEL-LINK-PREGUNTAS.md` a Hotel Link, agregando la pregunta del código promocional | Propietario | Nada |
| **2** | SEO técnico: descripciones, HotelRoom, BreadcrumbList, LodgingBusiness completo, `llms.txt` EN y ES generado del contenido | Claude | GO |
| **2** | Colección Promociones con sus candados (§4) | Claude | GO |
| **2** | Banner de consentimiento y medición preparados con los identificadores vacíos, apagados hasta el lanzamiento (D-05) | Claude | GO; luego los identificadores del propietario |
| **3** | Páginas Fotos (galería) y Grupos, con el diseño actual | Claude | GO; fotos del propietario |
| **3** | Respaldo automático en la Mac (P-12) y prueba de restauración | Claude prepara, propietario instala | GO |
| **3** | Endurecer la política de seguridad del panel `/admin/` | Claude | GO |
| **4** | Conexión con Hotel Link en una rama de prueba protegida | Claude | Respuestas de Hotel Link y GO |
| **4** | Aviso de privacidad y condiciones de reserva finales | Abogado, propietario | BQ-26 |
| Lanzamiento (GO aparte) | Redirecciones desde las direcciones viejas, perfil de Google, dominio y DNS, quitar la contraseña | Propietario y Claude | BQ-07, BQ-13, BQ-15, BQ-18 |

## 7 · Bloqueos actuales

- **Hotel Link:** sin respuestas (BQ-24, BQ-25).
- **Fotos y datos reales de las habitaciones:** propietario (BQ-02, BQ-19, BQ-20).
- **Imágenes de Higgsfield:** la red del entorno de Claude bloquea su servidor. Alternativa sin cambiar la red: el propietario las descarga desde Higgsfield y las sube por el panel. La portada y el quetzal esperan el límite de su cuenta.
- **Sitio actual `basecampmonteverde.com`:** bloqueado para Claude. Hace falta para la lista de direcciones a redirigir (BQ-18).
- **Revisión legal:** BQ-26.

## 8 · Decisiones BQ-37, BQ-38 y BQ-39 (detalle)

### BQ-37 · Promociones en el panel

- **Qué decide el propietario:** si se construye la sección "Promociones" del §4. Y si acepta la regla de que cada oferta exista primero en Hotel Link y que el sitio solo la anuncie.
- **Recomendación:** aprobar.
  - Empezar con el código promocional visible para copiar.
  - Pasarlo automáticamente al motor de reservas cuando Hotel Link confirme que se puede.
- **Por qué:**
  - Las ofertas propias son la mejor razón para reservar directo en lugar de por Booking.com.
  - Evita llevar precios en dos lugares (BD-011).
  - Los candados impiden anunciar una oferta que no existe, que ya venció o que no tiene condiciones. Así se cumple la obligación de informar condiciones claras y respetar lo anunciado (Ley 7472).
- **Costo:** $0. Una sesión de trabajo de Claude. El propietario configura cada oferta en Hotel Link, dentro del plan que ya paga.
- **Si se pospone:**
  - Se puede lanzar igual, y las ofertas se anuncian con el aviso superior que ya existe, pero sin fechas ni candados.
  - El riesgo es olvidar una oferta vencida en pantalla o anunciar algo distinto de lo que cobra Hotel Link.
  - Se puede agregar después del lanzamiento sin rediseñar nada.

### BQ-38 · Rastreadores de inteligencia artificial al lanzar

- **Qué decide el propietario:** si el `robots.txt` público permite o bloquea a los rastreadores de IA.
  - De búsqueda y respuesta: OAI-SearchBot y ChatGPT-User (ChatGPT), PerplexityBot, Claude-SearchBot y Claude-User.
  - De entrenamiento: GPTBot, ClaudeBot, Google-Extended (Gemini), CCBot.
- **Recomendación:** permitirlos todos y seguir bloqueando solo `/admin/`.
- **Por qué:**
  - Cada vez más viajeros planean con ChatGPT, Gemini o Perplexity.
  - El plan aprobado busca aparecer en esas respuestas (D-02).
  - El contenido del sitio es publicidad de Basecamp y no tiene nada privado.
  - Google-Extended no afecta el posicionamiento en Google; solo decide si Gemini puede usar el contenido.
  - Si el propietario prefiere que sus guías no se usen para entrenar modelos, la alternativa es permitir los de búsqueda y bloquear los de entrenamiento.
- **Costo:** $0. El tráfico extra es mínimo y Cloudflare no cobra por él.
- **Si se pospone:**
  - Durante la vista previa no cambia nada: todo sigue bloqueado.
  - Al lanzar, un `robots.txt` normal ya permite a todos los rastreadores, así que no decidir equivale a permitirlos.
  - Los nombres de estos rastreadores cambian a veces; Claude revisa la lista antes del lanzamiento.

### BQ-39 · Páginas Fotos y Grupos

- **Qué decide el propietario:** si se agregan en la Fase 2 dos páginas del modelo de hotel (BD-002):
  - **Fotos:** galería por álbumes (habitaciones, edificio, vistas, pueblo), editable en el panel.
  - **Grupos:** reservar varias habitaciones o todo el hospedaje (10 habitaciones, hasta 29 huéspedes), con solicitud por WhatsApp o correo.
- **Recomendación:** aprobar las dos.
  - **Grupos:** construirla ya, con su contenido marcado como pendiente hasta que el propietario defina las condiciones.
  - **Fotos:** mostrarla al público solo cuando haya al menos unas 12 fotos reales.
- **Por qué:**
  - Las fotos son lo primero que mira un huésped antes de reservar.
  - Grupos abre ingresos que hoy no tienen lugar en el sitio: familias grandes, grupos de tours, alquiler del hospedaje completo.
  - Las dos usan el diseño actual.
  - La solicitud de grupo va por WhatsApp o correo: un formulario necesitaría un servicio externo.
- **Costo:** $0.
- **Qué necesita del propietario:**
  - **Para Grupos:** mínimo de habitaciones, depósito y cancelación para grupos (se relaciona con R-01 a R-10), si alquila el hospedaje completo, y a quién llegan las solicitudes.
  - **Para Fotos:** las fotos.
- **Si se pospone:**
  - El sitio se lanza con fotos solo en cada habitación, y los grupos escriben por el WhatsApp general.
  - Se pueden agregar después sin rediseñar.
  - Sin la página de Grupos, esas consultas no se distinguen en la medición.
