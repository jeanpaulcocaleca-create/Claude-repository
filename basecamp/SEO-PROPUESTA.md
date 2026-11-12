# SEO del sitio · propuesta (BD-027, prioridad 2)

Fecha: 2026-10-23 · Autor: Claude · Estado: **propuesta. Nada está implementado.** La vista previa sigue privada y las cinco guías siguen en TEST.

## Cómo se revisó

- Revisé 22 páginas en una copia local del build público, la que vería Google. Esa copia no se publica.
- Revisé además las 10 páginas de guías de la vista previa.
- En cada página revisé: el título, la descripción, los encabezados, la página canónica, hreflang, la imagen para compartir, los datos estructurados, los enlaces internos y las imágenes.

**Lo que ya está bien:**
- Cada página tiene su página gemela en el otro idioma, su página canónica y su imagen para compartir.
- No hay títulos ni descripciones repetidos.
- Cada página tiene un solo título principal.
- Todas las imágenes tienen descripción y tamaño.
- El mapa del sitio y `robots.txt` están listos para el lanzamiento, y la página de reservas no se indexa.
- Hay datos estructurados para el hospedaje, las habitaciones, las preguntas frecuentes, las guías y las migas de pan.

Cada punto tiene un código. Puede responder, por ejemplo, «SEO-1 aprobado, SEO-3 después».

---

## SEO-1 · Títulos más cortos para Google

Google corta los títulos de más de unos 60 caracteres. Hoy se pasan:
- la página de inicio: 65 caracteres en inglés y 82 en español;
- las tres habitaciones: de 60 a 74;
- cuatro de las cinco guías: de 66 a 115.

**Propuesta:**
- Un campo opcional **«Título para Google»** en guías, habitaciones y páginas. Si está vacío, se usa el título de siempre. El panel muestra la guía de 60 caracteres. El título visible de la página no cambia.
- Para la página de inicio, en lugar de un campo nuevo, se acorta la frase que acompaña al nombre.

| Página | Inglés (caracteres) | Español (caracteres) |
|---|---|---|
| Inicio | Basecamp Monteverde · Lodge in Santa Elena, Monteverde (54) | Basecamp Monteverde · Hospedaje en Santa Elena, Monteverde (58) |
| La Orquídea | The Orchid Room · Queen and single · Basecamp Monteverde (56) | La Orquídea · Queen e individual · Basecamp Monteverde (54) |
| El Quetzal | The Quetzal Room · Queen bed · Basecamp Monteverde (50) | El Quetzal · Cama queen · Basecamp Monteverde (45) |
| La Ceiba | The Ceiba Room · Two queen beds · Basecamp Monteverde (53) | La Ceiba · Dos camas queen · Basecamp Monteverde (48) |
| Guía 01 | Sin cambio (59) | Sin cambio (59) |
| Guía 02 | Monteverde Reserve at 7:00 AM · Basecamp Monteverde (51) | Reserva Monteverde a las 7:00 · Basecamp Monteverde (51) |
| Guía 03 | How Many Days to Stay in Monteverde · Basecamp Monteverde (57) | ¿Cuántos días quedarse en Monteverde? · Basecamp Monteverde (59) |
| Guía 04 | Best Time to Visit Monteverde · Basecamp Monteverde (51) | Mejor época para visitar Monteverde · Basecamp Monteverde (57) |
| Guía 05 | Where to Stay in Monteverde · Basecamp Monteverde (49) | Dónde hospedarse en Monteverde · Basecamp Monteverde (52) |

En las guías, los títulos visibles de Lapis no cambian; solo cambia lo que muestra Google.

## SEO-2 · Descripciones para Google de las habitaciones

Hoy cada habitación usa su resumen corto, de 70 a 96 caracteres. No dice dónde está el hospedaje ni menciona el baño privado ni el Wi-Fi. Propongo un campo **«Resumen para Google»** por habitación, como el que ya tienen las guías, con estos textos. Todos usan datos ya confirmados: camas, huéspedes, baño privado con agua caliente, Wi-Fi gratuito y el café en el mismo edificio.

| Habitación | Inglés | Español |
|---|---|---|
| La Orquídea | The Orchid Room in Santa Elena, Monteverde: a queen and a single bed for up to 3 guests, private bathroom with hot shower and free Wi-Fi. (137) | La Orquídea en Santa Elena, Monteverde: cama queen e individual para hasta 3 huéspedes, baño privado con agua caliente y Wi-Fi gratuito. (136) |
| El Quetzal | The Quetzal Room in Santa Elena, Monteverde: a queen bed for up to 2 guests, private bathroom with hot shower, free Wi-Fi and the café downstairs. (146) | El Quetzal en Santa Elena, Monteverde: cama queen para hasta 2 huéspedes, baño privado con agua caliente, Wi-Fi gratuito y el café en la planta baja. (149) |
| La Ceiba | The Ceiba Room in Santa Elena, Monteverde: two queen beds for up to 4 guests, private bathroom with hot shower and free Wi-Fi. Our only room for four. (150) | La Ceiba en Santa Elena, Monteverde: dos camas queen para hasta 4 huéspedes, baño privado con agua caliente y Wi-Fi gratuito. Nuestra única para cuatro. (152) |

## SEO-3 · Enlaces de las habitaciones a las guías

BD-028 pide enlaces entre guías, la página pilar, las habitaciones y el café. Hoy las guías ya enlazan a las habitaciones, pero las habitaciones no enlazan a ninguna guía.

**Propuesta:** un bloque corto «Planee su visita» en cada habitación y en La estadía, con hasta 3 guías y el enlace a la página de guías. Se elegirían primero las guías de los temas «Cómo llegar» y «Planificar la visita».

**Regla de seguridad:** en el sitio público solo aparecen guías confirmadas. Hoy no hay ninguna, así que en público el bloque no se vería hasta que usted confirme la primera. En la vista previa se ven las guías de muestra, con su etiqueta.

## SEO-4 · Página de guías vacía en el sitio público

Si el sitio se publicara hoy, la página de guías no tendría ninguna guía confirmada: solo unas 22 palabras y «Pronto habrá nuevas guías». Google puede tratarla como una página de poco valor.

**Propuesta:** mientras no haya guías confirmadas, esa página lleva «noindex» y queda fuera del mapa del sitio. Sigue siendo visible para quien llegue desde el menú. Al confirmar la primera guía, vuelve a indexarse sola.

Es el cambio más pequeño de esta lista y evita un problema el día del lanzamiento.

## SEO-5 · Datos del hospedaje para Google (ficha de LodgingBusiness)

Ya se envían a Google:
- el nombre, la dirección y el teléfono;
- los horarios de entrada y salida;
- las diez habitaciones;
- los idiomas.

**Faltan, y los aporta usted desde el panel («Información del hotel»):**
- **Coordenadas** (latitud y longitud) del hospedaje. Ayudan a Google Maps. El campo ya existe y está vacío.
- **Perfiles oficiales:** el perfil de Google del negocio (BQ-13), Instagram y Facebook, si existen. El campo ya existe y está vacío.

**Lo agrego yo, con datos ya confirmados:**
- el enlace al mapa;
- «no se aceptan mascotas» (BD-023);
- las comodidades generales del hospedaje: Wi-Fi gratuito, café en el mismo edificio, estacionamiento gratuito en la calle y guardado de equipaje.

No propongo agregar un rango de precios ni calificaciones: los precios vienen de Hotel Link y las reseñas no van por ahora (BD-027).

## SEO-6 · Texto de la página pilar (contenido, no código)

El mapa de Lapis define la página pilar: «Monteverde: la guía completa para planear su visita». Hoy la página de guías tiene solo su título y una frase.

**Propuesta:** Lapis escribe la introducción de la página pilar. Se carga en el panel, en «Página de guías», con el mismo sistema de marcas y de confirmación que las guías. No requiere código.

---

## Orden recomendado

| Orden | Punto | Cambio | Qué necesito de usted |
|---|---|---|---|
| 1 | SEO-4 | Pequeño, en el código | Solo la aprobación |
| 2 | SEO-1 y SEO-2 | Dos campos opcionales en el panel, más los textos de las tablas | Aprobar los textos |
| 3 | SEO-3 | Un bloque nuevo en habitaciones y La estadía | Aprobar la idea |
| 4 | SEO-5 | Pequeño, en el código, más datos del panel | Las coordenadas y los perfiles, cuando los tenga |
| 5 | SEO-6 | Solo contenido | El texto de Lapis |

En todos los casos:
- se mantiene el diseño actual;
- todo va en inglés y en español;
- se corren las pruebas, la revisión en navegador y la accesibilidad;
- la vista previa sigue privada;
- no se publica nada;
- no se agregan servicios ni suscripciones.

## Fuera del sitio (para el lanzamiento, sin cambios ahora)

- **Search Console y Bing:** ya decididos (BD-015, D-05). Los campos de verificación ya existen en el panel y se usan el día del lanzamiento.
- **Fotos reales:** las portadas de las guías 03 y 05, y las fotos de `docs/FOTOS-FALTANTES.md`. Las fotos son lo que más ayuda en Google Imágenes y en Maps.
- **Lote 2 de guías:** sigue el flujo aprobado (Lapis redacta, usted aprueba los datos), con la misma plantilla y el mismo bloqueo.
