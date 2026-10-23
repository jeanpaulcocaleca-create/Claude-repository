# Revisión visual final · Basecamp Monteverde (BD-040)

Fecha: 2026-10-23 · Autor: Claude · Estado: **hallazgos para el propietario.**

- No se cambió nada del sitio.
- No se modificó, sustituyó ni generó ninguna imagen.

## Cómo se revisó

- **Páginas:** las 35 páginas de la vista previa (`basecamp-website` en `cb62155`), en inglés y en español, más la página de error.
- **Tamaños:**
  - teléfono de 360 y 390 px;
  - tableta de 768 px;
  - computadora de 1000 a 1440 px;
  - modo oscuro en teléfono.
- **Versión pública:** se revisó también la versión pública local, sin publicarla.
- **Método:**
  - capturas de pantalla página por página;
  - mediciones automáticas: contenido más ancho que la pantalla, texto cortado, botones pequeños, imágenes agrandadas o rotas, barra inferior tapando contenido, largo de las líneas.
- **No son problemas:**
  - las etiquetas de muestra, las marcas [POR VERIFICAR] y la cinta de vista previa, porque no salen en el sitio público;
  - la página Fotos sin las 12 fotos, porque en el sitio público está oculta y ningún enlace la muestra.

## Hallazgos, de mayor a menor importancia

La imagen `revision-visual-evidencia.jpg` muestra los puntos 1, 2, 4, 7 y 8.

### Importancia alta

**1 · La portada en el teléfono se ve borrosa y casi no muestra la habitación.**
- **Qué pasa:**
  - en el teléfono, la foto de 1600 × 900 px se recorta a un marco vertical de unos 390 × 636 px y se cubre con un velo blanco;
  - solo se ve la esquina de una cama y el piso, aumentados unas 2,1 veces, en todos los teléfonos;
  - en computadora se ve bien: la habitación completa, la puerta y el baño.
- **Dónde:** página principal, inglés y español.
- **Corrección recomendada, sin tocar la foto:** en teléfonos, mostrar la foto en su forma original (una franja horizontal de unos 220 px de alto, sin velo blanco) arriba del titular, con el titular y el formulario de reserva debajo.
  - La computadora no cambia.
  - Con esto la foto se ve completa y nítida.
  - Además, se corrige una indicación técnica para que los teléfonos descarguen la versión de 1600 px.
- **Alternativa:** mantener el marco a pantalla completa, más bajo (unos 420 px) y con el velo más suave. Mejora, pero la foto sigue algo aumentada.
- **Más adelante:** si llega el original de 2400 px o más, o la foto de la fachada o de la neblina, se puede volver al formato de pantalla completa.

**2 · En «Reservar», el campo «Habitación» queda fuera de la tarjeta, debajo del botón.**
- **Qué pasa:**
  - el huésped llena fechas y huéspedes, toca «Ver precios y disponibilidad», y el campo de la habitación queda abajo, separado;
  - en el teléfono, además, el texto de la opción se corta: «La Orquídea (Queen + individual · hasta».
  - El campo funciona: pertenece al mismo formulario. El problema es solo dónde aparece y qué tan largo es el texto.
- **Dónde:** `/book/` y `/es/reservar/`, en teléfono y computadora.
- **Corrección recomendada:**
  - mover «Habitación» dentro de la tarjeta, después de «Huéspedes» y antes del botón;
  - acortar las opciones a nombre y capacidad, por ejemplo «La Orquídea · hasta 3 huéspedes».

**3 · En el sitio público, el menú lleva a una página de guías vacía.**
- **Qué pasa:**
  - mientras no haya guías confirmadas, la página de guías solo dice «Pronto habrá nuevas guías», pero el menú principal muestra «Guías» en todas las páginas, en el teléfono y en la computadora;
  - la portada y el pie de página ya la ocultan; el menú no.
- **Corrección recomendada:**
  - ocultar «Guías» del menú en el sitio público hasta que exista al menos una guía confirmada, como ya se hace con «Fotos»;
  - en la vista previa sigue visible;
  - vuelve sola con la primera guía confirmada.

### Importancia media

**4 · «La estadía» en computadora: las listas quedan en columnas muy angostas.**
- **Qué pasa:**
  - «Incluido en cada estadía», «Con costo adicional» y «Reglas de la casa» van lado a lado, y cada una se divide en dos columnas internas;
  - cada punto ocupa de 3 a 5 renglones;
  - en español, a 1040 px, una marca de verificación queda sola encima de la palabra «Estacionamiento».
  - En el teléfono se lee bien.
- **Corrección recomendada:** quitar las dos columnas internas, para que cada lista ocupe su columna completa. Alternativa: poner las tres listas una debajo de otra, a todo el ancho y con dos columnas cada una.

**5 · Páginas de texto en computadora: el título y el texto no empiezan en la misma línea.**
- **Qué pasa:**
  - en «Privacidad», la etiqueta y el título empiezan en el borde izquierdo de la página, pero el texto empieza más a la derecha, en una columna más angosta;
  - en las guías pasa lo mismo con la ruta de navegación («Guías / …»), que queda a la izquierda mientras el artículo está centrado.
- **Corrección recomendada:** alinear el título, la etiqueta y la ruta de navegación con la columna del texto.

**6 · Guías en computadora: renglones algo largos.**
- **Qué pasa:**
  - a 1280 y 1440 px, los párrafos de las guías tienen de 88 a 99 caracteres por renglón;
  - lo cómodo es 80 o menos.
  - Las guías están en TEST, pero la plantilla es la definitiva.
- **Corrección recomendada:** reducir un poco el ancho de la columna de texto del artículo, a unos 68 caracteres, sin cambiar la letra.

### Importancia baja

**7 · Encabezado a 360 px: el nombre casi toca el ícono de idioma.**
- **Qué pasa:** en teléfonos pequeños, «BASECAMP MONTEVERDE» queda a unos 2 px del ícono de «Español» / «English». A 390 px hay espacio.
- **Corrección recomendada:** por debajo de 380 px, reducir un poco el espacio entre letras del nombre, o dejar más margen.

**8 · «Otras habitaciones» en el teléfono: tarjetas desparejas.**
- **Qué pasa:**
  - las dos tarjetas tienen fotos de distinto ancho;
  - el texto se corta raro («Queen · up / to 2 guests»);
  - en una tarjeta el nombre ocupa dos renglones y en la otra uno.
- **Corrección recomendada:** el mismo ancho de foto en todas las tarjetas, y la capacidad en su propio renglón.

**9 · «Ubicación»: los enlaces de WhatsApp y teléfono son pequeños para tocar.**
- **Qué pasa:** miden 20 px de alto. Lo mínimo recomendado es 24 px, y en el teléfono lo ideal son 44 px.
- **Corrección recomendada:** más espacio alrededor de cada enlace, sin cambiar su aspecto.

**10 · Pie de página: «Privacidad» no está alineado con los demás enlaces.**
- **Qué pasa:** es el único sin ícono, así que su texto empieza más a la izquierda que el de los otros.
- **Corrección recomendada:** darle un ícono como a los demás, o el mismo margen.

## Depende de las fotos, no del sitio (sin acción ahora)

- **Pantallas de alta densidad:** en computadoras como las Mac, la portada (1600 px) y la foto de El Quetzal (1100 px) se ven algo menos nítidas que el resto. Se resuelve con los originales pedidos en BD-039, sin editarlos.
- **Café:** sigue con su ilustración y su nota. La foto del mostrador no se usa (BD-040).

## Lo que se verificó y está bien

- **Medidas:** en las 35 páginas, en ambos idiomas y a 360, 390, 768, 1280 y 1440 px:
  - nada más ancho que la pantalla;
  - ningún texto cortado;
  - ninguna imagen rota ni deformada.
- **Barra de «Reservar / WhatsApp»:** nunca tapa el pie de página ni el contenido final.
- **Menú de computadora:** cabe completo en español desde 1040 px.
- **Modo oscuro:** coherente y legible en todas las páginas revisadas.
- **Ilustraciones:** todas conservan su nota.
- **Versión pública:**
  - sin etiquetas de prueba;
  - sin marcas;
  - sin enlaces a guías de muestra ni a la página Fotos.
- **Pestañas de la portada:** en la versión pública caben completas a 360 px. En la vista previa la última se corta porque hay una pestaña más, la de «Guías».

## Lo que necesito de usted

- **Qué corregir:** cuáles de los puntos 1 a 10 autoriza. Puede ser todos, solo los de importancia alta, o una selección.
- **Para el punto 1:** la corrección recomendada (franja horizontal en teléfonos) o la alternativa (marco más bajo).

Nada se implementa hasta su autorización. Las cinco guías siguen en TEST y el sitio en vista previa privada.
