# Pantallas nuevas para los clientes: la Pantalla A (menú) y la Pantalla B (promociones)

Estado al 2026-10-31 (D-061 fase 0 y prototipo; D-062 la versión completa):
- **Nada publicado y ninguna migración aplicada en producción.** Todo está construido, probado e integrado en una sola
  versión, lista para que el dueño la active con `docs/ACTIVACION-PANTALLAS.md`.
- **Tres páginas nuevas** en `website/`: `pantalla-menu.html` (Pantalla A), `pantalla-promos.html` (Pantalla B) y
  `pantallas.html` (la gestión, solo con el PIN del dueño). **Ningún archivo existente cambió** (sección 5).
- **Una migración nueva**, `0036_pantallas.sql`, con su reversión `supabase/tools/reversion-0036.sql`.
- La fase 0 sigue vigente para el dueño y el técnico: formulario, prueba de letra impresa y revisión del menú.

Plan aprobado («Dirección aprobada»): el plan «Dos pantallas nuevas para los clientes» que Claude presentó, con las 10 condiciones del dueño del 2026-10-31.

## 1. Las condiciones del dueño y cómo se cumplen hoy

| # | Condición (2026-10-31) | Cómo se cumple en esta entrega |
|---|---|---|
| 1 | Primero la Pantalla A, en vista privada; nada de producción sin autorización | La Pantalla A se entregó primero como prototipo privado con su demostración (D-061). Después, por orden del dueño del 2026-10-31 («continúa con todo el proyecto»), se construyó el resto. Nada se publicó ni se aplicó: lo hace el dueño con `docs/ACTIVACION-PANTALLAS.md` |
| 2 | Caja, Cocina, Contabilidad, menú QR y TV actual intactos, verificado con comparación de archivos y pruebas | `tests/pantallas/no-tocar.sh`: los 43 archivos de `website/`, las 36 migraciones y `pages.yml` son byte por byte los de la versión publicada `v2026.10.26-1` (comprueba también que la etiqueta siga apuntando a ese commit); solo admite los 5 archivos nuevos de las pantallas. Corre en cada prueba y en la integración continua. Además, la suite completa de siempre y el ensayo con la copia de producción (las páginas publicadas hoy sobre la base con la 0036) |
| 3 | Precios y disponibilidad leídos solo del menú existente, sin escribir | Las TV solo hacen lecturas `GET`: el menú (`menu_categories` con sus productos, como la TV actual y el menú QR) y `pantalla_datos` (sus ajustes y diapositivas). Ninguna función de las pantallas escribe en el menú ni en ninguna tabla existente; la prueba SQL 440 compara huellas de esas tablas antes y después de 35 escrituras |
| 4 | Política segura ante pérdida de conexión y datos viejos; nunca promociones vencidas ni precios no verificados como actuales | Sección 4.4: precios solo de una lectura correcta, con su edad contada desde que empezó la petición y con dos relojes; a los 10 min ningún precio. Cada diapositiva tiene fin obligatorio y se apaga sola con la hora estimada del servidor, también sin internet. Nada se guarda en el aparato salvo nombres. Pruebas A4–A6, B8, B11, P5, P7–P9, P13, P16 |
| 5 | Lectura a distancia, precios grandes, sin exceso de información | Mayúscula de 1 cm por metro (mínimo 0,8), precio del tamaño del nombre y en negrita; en la Pantalla B el precio 1,5 cm por metro. Sin descripciones, reloj ni recomendados. Pruebas A2, B9 y P11 en 7 tamaños y giros |
| 6 | Sin suscripciones, servicios ni aparatos nuevos sin demostrar que hacen falta y sin aprobación | Solo el sitio, Supabase con la clave pública y el navegador de la TV. La app de quiosco sigue pendiente de la prueba en la TV real (P-09). Consumo en 4.7 |
| 7 | Combos y descuentos reservados hasta que la Caja los cobre exactamente como se anuncian | Las TV nunca muestran «Extras & Combos» ni un precio cero o negativo. El servidor rechaza cualquier texto de diapositiva con precios (₡, $, %, colones, dólares…) o con palabras de combo o descuento (combo, descuento, 2x1, 3x2, 2 por 1, gratis, oferta, rebaja, mitad de precio…); la página lo avisa antes de enviar. Una diapositiva de producto no guarda precio: lo lee del menú |
| 8 | Gestión con PIN de propietario, permisos del servidor y registro de cambios | `pantallas.html` abre solo con el PIN de una persona con puesto **dueño** (`is_true_owner()`), o con el ingreso del dueño y el código del teléfono; el PIN de un encargado recibe `owner_only` del servidor en cada función. Cada cambio queda en `screen_changes` con quién, cuándo, antes y después; dos disparadores impiden modificarlo o borrarlo, también al dueño |
| 9 | Ninguna migración ni cambio de configuración de Supabase sin aprobación expresa | La 0036 está preparada y ensayada, **no aplicada**. La aplica el dueño (guía, sección 2). No cambia ninguna configuración de Supabase |
| 10 | Pruebas y demostración privada antes de pedir autorización para cada publicación | Pruebas en la sección 5; demostración de la Pantalla A en la sección 6; capturas de las tres páginas en el informe de D-062. La autorización para publicar la pide esta entrega con `docs/ACTIVACION-PANTALLAS.md` |

## 2. Fase 0 · lo que necesitamos del local (dueño y técnico)

### 2.1 Formulario por cada TV nueva
Una copia por TV. Las fotos se toman desde donde estará el cliente más lejano que debe leer.

| Dato | TV A (menú) | TV B (promociones) |
|---|---|---|
| Marca y modelo exactos (etiqueta de atrás) | | |
| Tamaño (pulgadas, diagonal) | | |
| Tipo de panel (LED/IPS, VA u OLED) y brillo si se conoce | | |
| Posición: horizontal o vertical. Si es vertical, ¿el borde de arriba quedó a la izquierda o a la derecha? | | |
| Altura del borde inferior sobre el piso (cm) e inclinación | | |
| Distancia (m) al punto **más lejano** desde donde un cliente debe leerla (final de la fila, mesa más lejana) | | |
| Ventanas o luces que se reflejan en ella (foto con la TV apagada, de día) | | |
| Reproductor: Google TV / Android TV integrado, Fire TV, otro aparato o navegador integrado | | |
| ¿La TV vuelve encendida sola después de un corte de luz? (probarlo: desenchufar 1 min) | | |
| ¿Se puede desactivar el apagado automático y el modo ahorro? | | |
| Red: cable o Wi-Fi; si es Wi-Fi, ¿cuál red, y llega bien a ese lugar? | | |
| Horario en que debe estar encendida | | |
| Resultado de la prueba de letra (2.2): tamaño más pequeño que se lee **sin esfuerzo** y desde cuántos metros | | |
| Tiempo que espera un cliente en la fila en hora pico (minutos) | | |
| Fotos: el lugar, la pared y la vista desde el punto más lejano | | |

### 2.2 Prueba de letra impresa
- Archivo: `docs/pantallas/prueba-de-letra-pantalla-a.pdf`, también enviado al dueño el 2026-10-31.
  - Son 4 hojas tamaño carta horizontal, con mayúsculas de 2, 3, 4 y 5 cm: «Café con leche ₡1 700» y «Latte ₡2 200».
- Imprimir al 100 % («tamaño real», sin «ajustar a la página»). La barra de cada hoja debe medir 10 cm; si mide otra cosa, la impresora cambió el tamaño.
- Pegar las hojas donde irá la TV, a la altura de la pantalla.
- Pararse en el punto más lejano del formulario. Anotar la hoja más pequeña que se lee sin esfuerzo, mejor con una persona de más de 60 años o con lentes.
- **Regla:** la mayúscula mide 1 cm por metro de distancia (meta) y nunca menos de 0,8 cm por metro.
  - Ejemplo: a 3 m, la meta es 3 cm y el mínimo 2,4 cm.
  - Si la prueba dice que hace falta más, el técnico sube `escala` en la dirección de la TV (sección 4.2).

### 2.3 Revisión del menú real (solo lectura)
- Supabase → SQL Editor → New query → pegar **todo** `supabase/tools/menu-pantallas.sql` → Run → copiar la celda `menu_pantallas` y pasarla a Claude.
  - No cambia nada: su primera línea pone la consulta en modo de solo lectura.
  - No muestra personas, ventas ni claves; la prueba `430_menu_pantallas` lo comprueba.
- Devuelve:
  - por categoría, lo que la Pantalla A mostraría y lo agotado;
  - el nombre en español escrito en el Gestor del menú (`name_es`);
  - los precios escritos a mano en descripciones;
  - las líneas de «Extras & Combos», que nunca se muestran;
  - los nombres más largos.

### 2.4 Lo que ya se ve con la copia del menú del repositorio (`supabase/menu-2026.sql`)
El menú real puede ser distinto; por eso hace falta la revisión de 2.3.
- **Lo que se muestra:**
  - 41 productos en 8 categorías;
  - nunca las 5 líneas de «Extras & Combos»: shot de sabor ₡400, jamón ₡500, leche en batidos ₡300 y ₡400, combo −₡500.
- **Nombres en español:**
  - ningún producto tiene `name_es`, así que el español sale del diccionario del sitio, como en el menú QR;
  - 21 nombres son iguales o sin traducción en los dos idiomas y salen una sola vez: Espresso, Latte, Tres Leches, los 11 batidos con nombre de flor, Mano de Piedra, Monteverde y otros.
- **Precios escritos a mano en descripciones:** 8, por ejemplo «Golden Passion Bloom: (₡3 500 in milk)» y «Monteverde: add ham +₡500».
  - La Pantalla A no muestra descripciones, así que esos precios no salen.
  - Si se quieren, son la decisión P-06.
- **El menú completo no cabe en 2 páginas a distancia de fila.** Con letra medida para lectura a distancia, el prototipo calcula cuántas páginas necesita la copia del menú (41 productos, bilingüe):

| TV horizontal | 2 m | 3 m | 4 m | 5 m |
|---|---|---|---|---|
| 43" | 3 | 8 | 15 | no cabe |
| 50" | 2 | 6 | 10 | no cabe |
| 55" | 2 | 4 | 9 | 15 |
| 65" | 2 | 3 | 6 | 10 |
| 75" | 2 | 2 | 4 | 7 |

  - En vertical, a 3 m: 55" 4 páginas, 65" 3 y 75" 2.
  - Cada página dura 28 s, así que 4 páginas son casi 2 minutos de ciclo.
  - Por eso la decisión P-02 (qué muestra la Pantalla A) depende de la distancia y del tamaño reales.

## 3. Dónde está cada cosa
| Archivo | Qué es |
|---|---|
| `website/pantalla-menu.html` | Pantalla A: el menú con precios. Dirección en la TV: `pantalla-menu?tv=menu-1` |
| `website/pantalla-promos.html` | Pantalla B: diapositivas de producto, marca e invitación. Dirección: `pantalla-promos?tv=promos-1` |
| `website/pantallas.html`, `website/pantallas.js` | La gestión del dueño: cada TV, las diapositivas, «Hoy en pantalla» y el registro de cambios |
| `supabase/migrations/0036_pantallas.sql` | Las tablas `screens`, `screen_slides` y `screen_changes`; la lectura pública `pantalla_datos`; la gestión `pantallas_estado`, `pantalla_guardar`, `diapositiva_guardar`, `diapositiva_estado` |
| `supabase/tools/reversion-0036.sql` | La reversión: quita las funciones, deja las tablas con lo que tengan y el registro protegido |
| `tests/sql/440_pantallas.test.sql`, `450_reversion_0036.test.sql` | 181 + 40 comprobaciones de permisos, reglas, registro, lectura de las TV, Storage y reversión |
| `tests/e2e/specs/370_pantalla_menu.spec.js`, `380_pantalla_promos.spec.js`, `390_pantallas_admin.spec.js` | 20 + 17 + 14 pruebas de navegador |
| `tests/pantallas/no-tocar.sh`, `tests/pantallas/BASE` | La comparación con la versión publicada (condición 2) |
| `supabase/tools/menu-pantallas.sql`, `tests/sql/430_menu_pantallas.test.sql` | La revisión del menú, de solo lectura, y su prueba |
| `docs/ACTIVACION-PANTALLAS.md` | Los pasos exactos del dueño: ensayo, migración, publicación, configuración, aceptación, vuelta atrás |
| `docs/INSTALACION-TV.md` | La guía del técnico |

`tests/run.sh` y la integración continua («Tests») corren todo esto en cada envío.

## 4. Cómo funciona

### 4.1 Pantalla A: el menú con precios
- Las categorías y productos **disponibles con precio mayor que cero**, en el orden del Gestor del menú. Nunca «Extras & Combos», ni un precio cero o negativo. (El menú QR y la TV actual siguen mostrando un producto a ₡0; esta regla es nueva de la Pantalla A.)
- **Español primero; el inglés debajo, al 75 %.** El español sale como en el menú QR: `name_es` del Gestor; si no hay, el diccionario del sitio; si no hay, el nombre una vez. Un nombre igual en los dos idiomas se escribe una vez.
- **El precio va pegado al nombre**, en negrita y del tamaño del nombre; el «₡» al 80 %.
- Al pie: «Precios en colones, IVA incluido · Prices in colones, tax (IVA) included» (D-011; redacción a confirmar con el contador, P-10).
- **Páginas:** una categoría nunca se parte, salvo que sola sea más larga que una página; «1/3»; 3 o 2 columnas en horizontal, 1 o 2 en vertical.
- **Agotados:** ocultos, o tachados con «Agotado · Sold out» y nunca con precio, según la TV (`pantallas.html`).
- **Categorías:** cada TV muestra todas, o solo las que el dueño elija, en el orden del Gestor.
- **Sin** descripciones, fotos, recomendados, reloj, promociones ni combos.

### 4.2 Pantalla B: productos, marca e invitaciones
- Tres clases de diapositiva:
  - **producto**: la foto, el nombre y el precio **se leen del menú en cada lectura**; no se escribe título. Desaparece sola si el producto se agota, queda sin precio o pasa a Extras & Combos. «Pídalo en la caja · Order at the counter».
  - **marca**: título y texto en español e inglés, foto opcional, nunca un precio.
  - **invitación**: título y un código QR a la reseña de Tripadvisor (E-35) o al menú QR, con la dirección corta escrita debajo. El QR mide al menos distancia ÷ 10.
- **Vigencia obligatoria**: inicio y fin (a lo sumo un año), días de la semana y horas de Costa Rica; orden; estado activa, pausada o retirada. Nunca se borra: se retira.
- Cada TV de promociones muestra todas las diapositivas o solo las que el dueño le asigne.
- Sin nada vigente: la presentación de la marca «Hanging Garden Café · Monteverde, Costa Rica».
- La letra: título 1,2 cm por metro, precio 1,5, textos 0,8; un título largo baja hasta 1,0 y luego se parte.

### 4.3 La gestión (`pantallas.html`)
- Abre con el ingreso del café o del dueño y el **PIN del dueño** (o el ingreso del dueño con el código del teléfono). Un PIN de encargado ve «Solo el dueño puede cambiar las pantallas».
- **Pantallas:** por cada TV, tamaño, distancia, posición, escala de letra, colores, segundos, categorías (menú), agotados (menú), horario, activa; la dirección para la TV con un botón de copiar; una vista previa a escala; agregar una TV.
- **Diapositivas:** lista con estado y «en pantalla ahora»; editor con buscador de productos (nunca Extras & Combos), textos con contador y aviso de precios o combos, foto (del producto o subida, reducida a 1600 px), fechas obligatorias, días, horas, TV y orden; pausar, reanudar, retirar (con confirmación en la página).
  - Las fotos subidas van al depósito existente `menu-photos`, carpeta `pantallas/`, que la 0036 deja solo al dueño (PIN de dueño de la misma sesión, o ingreso del dueño con código); un encargado sigue cambiando las fotos del menú como hoy. Si el servidor rechaza la diapositiva, la página borra la foto recién subida. Una foto reemplazada o quitada de una diapositiva guardada queda en la carpeta: se borra a mano, nunca una que use una diapositiva activa o pausada.
- **Hoy en pantalla:** qué sale ahora y qué empieza más tarde hoy en cada TV de promociones, con la hora del servidor.
- **Registro de cambios:** los últimos 200, con fecha de Costa Rica, quién, qué, antes y después. No se puede modificar ni borrar.
- Escrita directamente en español (P-18 resuelta así): no agrega textos a `lang.js`, que solo se carga para la ventana del PIN. No tiene casilla de PIN propia (usa la del sitio).
- Se niega a funcionar en una dirección que no sea la del café, antes de hablar con cualquier base de datos.

### 4.4 Conexión, hora y datos viejos (condición 4)
- Las dos TV leen cada **30 s**. Un precio cambiado o un agotado del Gestor del menú se ve en la lectura siguiente: en menos de 1 minuto.
- **Edad de los precios:** tiempo desde que **empezó** la última petición correcta, con dos relojes (el del aparato y uno que no se mueve aunque cambien la hora) y cuenta el mayor; después de dormir, de volver a mostrarse o de un salto de reloj, los precios cuentan como no verificados hasta la lectura siguiente, que se hace de inmediato.

| Edad de la última lectura correcta | Pantalla A | Pantalla B |
|---|---|---|
| hasta 2 min | precios | el precio del producto |
| de 2 a 10 min | precios con «Precios por confirmar en caja · Please confirm prices at the counter» | el precio con «Precio por confirmar en caja» |
| más de 10 min, o ninguna | **ningún precio**: los nombres y «Consulte los precios en la caja · Please ask for prices at the counter» | **ninguna diapositiva de producto**; las de marca e invitación siguen mientras estén vigentes |

- **Hora de las diapositivas:** la Pantalla B estima la hora del servidor desde la última respuesta y cuenta el tiempo con los dos relojes: el mayor para el fin (nunca termina tarde) y el menor para el inicio (nunca empieza antes). Una diapositiva vence sola, con el router desconectado; cambiar la hora de la TV no la revive.
- **Arranque sin internet:** la Pantalla A guarda **solo los nombres** del último menú y los ajustes de la TV, 3 días, nunca precios; muestra los nombres sin precios y el aviso, o la bienvenida. La Pantalla B no guarda nada: muestra la marca y sigue intentando.
- **Horario y apagado:** fuera del horario de la TV, o si el dueño la desmarca como activa, la pantalla queda **negra** (sin texto ni precio), con la hora de Costa Rica del servidor.
- **Sin la migración 0036** (o revertida): la Pantalla A funciona con los ajustes de su dirección; la Pantalla B muestra la marca; la gestión dice qué migración falta.

### 4.5 Ajustes de cada TV
- En `pantallas.html`, con los rangos de la migración: pulgadas 24–110, distancia 1–15 m, giro no/derecha/izquierda, escala 70–160 %, look auto/día/noche, página 15–60 s, diapositiva 6–30 s, horario, categorías, agotados, activa.
- La TV solo lleva `?tv=menu-1` en su dirección y toma los cambios sola en menos de un minuto.
- El técnico puede corregir una TV desde la dirección (`&pulgadas=65&distancia=4&giro=derecha&escala=110&look=dia&pagina=30&diag=1`), que manda sobre la base, ajuste por ajuste. `&diag=1` muestra el cuadro de diagnóstico; sin él, no se ve.
- **Letra:** mide la letra que de verdad usa (Figtree, o la de la TV); meta 1 cm por metro; baja hacia 0,8 solo si ahorra una página; títulos 1,5 veces (una palabra que no cabe en su columna baja hasta 1,25).

### 4.6 Lo que no hace (decisiones del dueño)
- Fotos o recomendados en la Pantalla A, línea de extras, dólares, «sin cargo de servicio» (P-05, P-06, P-11).
- Combos y descuentos: reservados (condición 7).
- App de quiosco: solo si la prueba en la TV real la pide (P-09).

### 4.7 Consumo
- Cada lectura pesa unos 4 KB (menos de 1 KB comprimida); dos lecturas cada 30 s por TV. Las dos TV, 13 horas al día: unos 150 MB al mes. Dentro del plan de Supabase del café. Ningún servicio nuevo.

## 5. Pruebas
`tests/run.sh` corre todo; en cada envío lo corre también la integración continua («Tests»). Nunca toca Supabase.

| Prueba | Qué demuestra |
|---|---|
| no tocar | `website/` (43 archivos), `supabase/migrations/` (36) y `pages.yml` iguales byte por byte a `v2026.10.26-1` (334624c), en el árbol y en el índice; la etiqueta sigue apuntando a ese commit; solo los 5 archivos nuevos de las pantallas |
| SQL 440 (181) | Permisos: un visitante solo lee `pantalla_datos`; el café sin PIN, un PIN de encargado, el contador y el dueño sin código reciben `owner_only`; el PIN del dueño y el dueño con código abren. Textos con precios o combos rechazados por campo; 140 letras; fechas obligatorias y hasta 366 días; la clase no cambia; una retirada no se edita; producto de Extras & Combos rechazado. Cada escritura deja una fila en el registro; el registro no se modifica ni se borra. Lo que lee cada TV: vigentes o por empezar en 24 h, por TV, sin pausadas, retiradas ni vencidas; agotado o sin precio oculta el producto; TV apagada = `tv_apagada`. Ninguna tabla existente se escribe (huellas iguales antes y después) |
| SQL 450 (40) | La reversión se niega si falta la 0036 o hay una posterior; quita las funciones, deja las tablas y sus filas y el registro protegido; la 0036 se vuelve a aplicar |
| SQL 430 (15), 240, 340–420 | La revisión del menú sigue de solo lectura y cuenta como la pantalla; las cadenas de reversión empiezan en la 0036; la lista de funciones públicas es exacta |
| Ensayo | La copia de producción con la 0036: 26 tablas originales iguales, 27 comprobaciones de negocio, respaldo y restauración, anonimizador, las páginas publicadas hoy sobre la copia migrada, el café vacío con las páginas nuevas |
| A1–A9 (370) | La Pantalla A como el prototipo: contenido, orden, exclusiones, legibilidad en 7 tamaños y giros, agotados, conexión, relojes, arranque sin internet, columna `name_es` ausente, recarga tras publicación, ajustes del técnico |
| B1–B11 (370) | Ajustes desde la base y desde la dirección; sin migración o TV desconocida; TV apagada en negro; categorías; agotados tachados; horario; look por hora de Costa Rica; reloj atrasado no detiene las lecturas; sin precio tras dormir; títulos y aviso en TV girada; tablero nunca en blanco; edad desde el inicio de la petición |
| P1–P17 (380) | Marca sin diapositivas; producto con precio y foto al día; marca e invitación con QR; pausadas, retiradas, vencidas, de otra TV y productos no vendibles ocultos; vence y empieza sola sin internet; días y horas de Costa Rica; política de precios sin conexión; arranque sin internet; relojes; horario; legibilidad; sin migración; reanudar; ajustes; TV apagada; edad de la lectura; recarga tras publicación |
| 390 (14) | Dirección desconocida rechazada; ingreso; PIN de encargado rechazado; PIN del dueño y dueño con código abren; TV guardada y registrada; tres diapositivas; precio o combo bloqueado en la página y rechazado por el servidor; fechas obligatorias; pausar, reanudar, retirar; foto reducida y guardada; Hoy en pantalla; vista previa; de la página a lo que lee la TV; sin migración |
| 340 | Las páginas nuevas no agregan ninguna casilla de PIN (siguen 19) |

## 6. Demostración privada
- Simulador de la Pantalla A con el menú de muestra del repositorio (no son los precios reales), con tamaño, distancia, giro, look, agotados, precios y corte de conexión: https://claude.ai/artifact/6R3r3hBSyXCNcRX2V7q9tX
- Capturas de las tres páginas en el informe de D-062.

## 7. Decisiones del dueño
Lo que el dueño decidió el 2026-10-31 ya está construido: combos y descuentos reservados (P-13), gestión con PIN de dueño, permisos del servidor y registro (P-14), ninguna migración sin aprobación (P-15), Pantalla B (P-16), publicación solo con su autorización (P-17), gestión en español sin `lang.js` (P-18).

Lo que sigue en manos del dueño, y cómo lo hace:

| # | Decisión | Dónde |
|---|---|---|
| P-01 | Lugar, tamaño, giro, altura y distancia de lectura de cada TV (formulario 2.1) | `pantallas.html` → Pantallas; el técnico con `docs/INSTALACION-TV.md` |
| P-02 | Si el menú completo no cabe en 2 páginas a la distancia real (tabla 2.4): más páginas, o elegir las categorías de esa TV | `pantallas.html` → Pantallas → Categorías que muestra |
| P-03 | Límites de la política de conexión (2 min / 10 min / 3 días de nombres) | Son los construidos; si quiere otros, se cambian con una versión nueva |
| P-04 | Agotados ocultos o tachados | `pantallas.html` → Pantallas → Productos agotados |
| P-05 | Fotos o recomendados en la Pantalla A | No construido; se decide después de ver la TV real |
| P-06 | Línea de «Extras» y descripciones con precios a mano (también en el menú QR) | No construido; el Gestor del menú para las descripciones |
| P-07 | Look automático o fijo por TV | `pantallas.html` → Pantallas → Colores |
| P-08 | Horario de cada TV | `pantallas.html` → Pantallas → Encendida desde / hasta; el apagado real, con el temporizador de la TV |
| P-09 | App de quiosco, solo si la prueba de 8 horas y la de corte de luz la piden | Prueba en la TV real (`docs/INSTALACION-TV.md` §6) y aprobación del dueño |
| P-10 | Redacción del pie «Precios en colones, IVA incluido», con el contador | Hoy coherente con D-011; cambiarla es una versión nueva |
| P-11 | Dólares y «sin cargo de servicio» | No construido (A-05, A-06) |
| P-12 | Nombres en español | Gestor del menú → `name_es` (cambia también el menú QR), o el diccionario del sitio |
| P-19 | Presupuesto: pantallas, soportes, cable, supresores, técnico; licencias solo si P-09 lo pide | – |
| P-20 | Lugar de la Pantalla B; enlace de reseña de Google (solo Tripadvisor está aprobado); la medición de 6 semanas y quién la anota | `pantallas.html` para el contenido; lo demás, decisión |

## 8. Activar
Los pasos exactos, en orden, con las comprobaciones y la vuelta atrás: `docs/ACTIVACION-PANTALLAS.md`. La publicación la hace el dueño; esta versión la deja lista.
