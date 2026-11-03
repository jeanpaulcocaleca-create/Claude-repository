# Pantallas nuevas para los clientes: la Pantalla A (menú) y la Pantalla B (promociones)

Estado al 2026-11-02 (D-061 fase 0 y prototipo; D-062 la versión 1; D-063 su activación; D-064 la versión 2):
- **La versión 1 está publicada** (`v2026.11.02-1`, 3273743) con la migración 0036 aplicada por el dueño (D-063). El dueño
  no da por aprobado su diseño: pidió la **versión 2** (sección 1.1), que está construida, probada y revisada en esta
  entrega, **sin publicar y sin tocar producción**. La activa el dueño con `docs/ACTIVACION-PANTALLAS-V2.md` (aprobada técnicamente el 2026-11-03).
- **Tres páginas** en `website/`: `pantalla-menu.html` (Pantalla A), `pantalla-promos.html` (Pantalla B) y `pantallas.html`
  + `pantallas.js` (la gestión, solo con el PIN del dueño). En la v2 cambian solo esas cuatro; **ningún otro archivo
  cambió** (sección 5).
- **Dos migraciones**: `0036_pantallas.sql` (aplicada) y `0037_pantallas_v2.sql` (preparada, aditiva, con su reversión
  `supabase/tools/reversion-0037.sql`). La 0036 **no se vuelve a ejecutar**.
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

### 1.1 La versión 2 (pedida el 2026-11-02) y cómo se cumple

| Pedido del dueño | Cómo se cumple en la v2 |
|---|---|
| Pantalla A: el menú completo en una sola pantalla horizontal, sin reducir la letra en exceso | Viabilidad medida con el menú real (sección 4.1): a 3 m cabe en una pantalla legible solo en 75" sin inglés o en más de 85"; a 2–2,5 m cabe en 55–65" con la densidad compacta. La página muestra **una pantalla siempre que la mayúscula se quede en o sobre el mínimo (0,8 cm por metro)** y, si no, las menos páginas posibles con la letra más grande. Nunca baja del mínimo para que quepa |
| Títulos de categoría siempre arriba, nunca entre productos de otra categoría | Cada categoría es un bloque (título y luego solo sus productos) en columnas explícitas; toda columna empieza con un título; un bloque cortado sigue arriba de la columna siguiente con «(continúa)», y solo se corta cuando las dos partes conservan dos productos o más |
| Columnas y bloques equilibrados, sin espacios vacíos | Las columnas de cada página se llenan hasta casi la misma altura y ninguna guarda un hueco que la pieza siguiente pudiera llenar (prueba B12) |
| Precios legibles a la distancia real | Igual que la v1: mayúscula 1 cm por metro, mínimo 0,8; el precio del tamaño del nombre y en negrita |
| Dos modos: solo menú, o menú con promociones de duración configurable | Por TV: `Promociones` **no** / **intercalar**, «una promoción cada» 30–900 s y «cada promoción dura» 6–30 s. La promoción se dibuja exactamente como en la Pantalla B y el menú vuelve a la misma página |
| Selección de categorías y varias páginas cuando la legibilidad lo requiera | Se conservan; además `Distribución` auto / una pantalla / páginas, `Densidad` normal / compacta e `Inglés` debajo / en línea / no, por TV. **Menú resumido (pedido el 2026-11-02 para las TV de 32" a 3 m):** por TV, «Productos que muestra» (`item_ids`): solo esos productos, bajo sus categorías; nada marcado = todos los de las categorías elegidas; a 3 m, 2 páginas ≈ 8–10 productos en 2–3 categorías y 3 páginas ≈ 12 productos (hasta 5 categorías) o 15 en 3; el menú QR lleva siempre todos (B24) |
| Pantalla B: programación por franjas y días, hora de Costa Rica; dueño cambia horarios, productos, fotos, orden y duración | Cada composición tiene su vigencia (fechas, días, horas de Costa Rica) como cualquier diapositiva. «Programación sugerida» crea con un clic las cuatro franjas sugeridas (06–10 desayunos, 10–13 almuerzos, 13–17 cafés y repostería, 17–19 sándwiches), **pausadas**, para que el dueño las revise |
| 2 a 4 fotos simultáneas en composición adaptable; varios grupos con rotación; una sola foto | Plantillas 1, 2 lado a lado, 3 (grande a la izquierda o a la derecha), 4 en cuadrícula y 4 centro (izquierda 3/8, centro dos apiladas 2/8, derecha 3/8); varias composiciones rotan con `dwell_seconds`; una sola queda fija |
| Precios solo del menú real, nunca escritos a mano | Cada entrada guarda solo el id del producto; nombre, foto y precio se leen del menú en cada lectura (0037, `_slide_json`); el servidor sigue rechazando cualquier texto con precio |
| Editor visual, solo dueño: plantillas, qué foto en cada posición, encuadre y tamaño, vista previa fiel, composiciones por horario, fotos del menú o subidas | Sección 4.3: el editor de composiciones con el punto de enfoque (clic o arrastre) y el zoom 100–200 %, «Vista previa en la TV» (la página real de la TV dentro del panel, en modo vista previa, que no lee ni escribe nada) |
| Cuatro ventanas con presentaciones independientes: foto fija o presentación propia por zona, segundos por zona, mezcla libre, 1–4 zonas, lista ordenada por zona, nombres y precios reales cuando el dueño lo active, transiciones suaves sin negros, respaldo cuando una zona no tiene nada | Cada zona: **Foto fija** o **Presentación** con sus propios segundos (4–60), su lista ordenada (hasta 12 entradas), «Nombres y precios» sí/no y una foto de respaldo (o el diseño de la marca). Cada zona tiene su propio reloj; la primera vuelta de cada zona dura un poco más según su posición (1 + 0,25·i vueltas), en **cada** arranque de la composición, también cuando vuelve tras otra diapositiva o en otro intermedio (y entonces sigue en la foto siguiente a la última mostrada), así nunca cambian todas juntas (P28). Fundido entre dos capas con la foto siguiente ya cargada: nunca un cuadro vacío ni negro |
| Conservar la identidad visual, no tocar el resto, nada en producción sin autorización, sin servicios de pago, una sola versión con pruebas, revisión independiente y vista previa | Mismos colores, tipografías y hoja; `no-tocar.sh` (solo las 4 páginas de las pantallas y la 0037); nada publicado ni aplicado; ningún servicio nuevo; pruebas en la sección 5, revisión en D-064, vista previa en la sección 6 |

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
| `supabase/migrations/0036_pantallas.sql` | Las tablas `screens`, `screen_slides` y `screen_changes`; la lectura pública `pantalla_datos`; la gestión `pantallas_estado`, `pantalla_guardar`, `diapositiva_guardar`, `diapositiva_estado` (aplicada en producción el 2026-11-02) |
| `supabase/migrations/0037_pantallas_v2.sql` | La v2 (aditiva): seis ajustes nuevos por TV (distribución, densidad, inglés, promociones y sus tiempos) y la lista de productos del menú resumido (`item_ids`), la clase «composicion» (plantilla, zonas, permanencia), las ayudas `_screen_item_json` y `_screen_template_places`, y las funciones de la 0036 vueltas a crear con lo nuevo |
| `supabase/tools/reversion-0036.sql`, `reversion-0037.sql` | Las reversiones: la de la 0037 vuelve las seis funciones al texto de la 0036 y deja columnas y filas; la de la 0036 quita las funciones y deja las tablas con lo que tengan y el registro protegido |
| `tests/sql/440_pantallas.test.sql`, `450_reversion_0036.test.sql`, `460_pantallas_v2.test.sql`, `470_reversion_0037.test.sql` | 181 + 40 + 136 + 73 comprobaciones de permisos, reglas, registro, lectura de las TV, Storage y reversiones |
| `tests/e2e/specs/370_pantalla_menu.spec.js`, `380_pantalla_promos.spec.js`, `390_pantallas_admin.spec.js` | 31 + 26 + 20 pruebas de navegador |
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
- **La pizarra (v2):** cada categoría es un bloque (su título y luego solo sus productos) en columnas explícitas: 3, 4 o 5 en horizontal (2 solo cuando las demás no caben o paginan más: TV pequeñas o muy lejos), 1 o 2 en vertical. Toda columna empieza con un título. Un bloque que no cabe en lo que queda de la columna se corta ahí y sigue arriba de la siguiente con su título «(continúa)», solo si las dos partes conservan dos productos o más; si no, pasa entero. Un bloque de tres productos más alto que una columna va 2 + 1 (la columna más llena primero). Las columnas de cada página terminan casi a la misma altura, sin huecos: las piezas que el primer llenado puso en la página se reparten de nuevo, en orden, por un reparto exacto en dos pasos (se prueban todos): primero la columna más alta lo más baja posible y, bajo ella, el que deja menos pizarra vacía bajo las columnas; el equilibrio nunca añade un corte a un bloque que el primer llenado dejó entero, nunca usa menos columnas que él, y corta un bloque que él ya cortó solo donde quedan dos productos a cada lado (uno, solo si nada más conserva las columnas); lo que sobra se reparte como separación entre bloques.
- **Una pantalla o páginas:** la letra se busca entre el mínimo (0,8 cm por metro) y 1,25 veces la meta, con 2, 3, 4 o 5 columnas: una sola pantalla siempre que la mayúscula se quede en o sobre el mínimo; si no, las menos páginas con la letra más grande («1/3»). Nunca baja del mínimo para que quepa. Con el menú real de hoy (7 categorías, 39 productos, inglés debajo): una pantalla en 75" a 2 m; a 3 m en 55" hacen falta páginas.
  - `Distribución` por TV: **auto** (lo anterior), **una pantalla** (igual, y el diagnóstico avisa «NO CABE EN UNA PANTALLA AL MÍNIMO» cuando tuvo que paginar) o **páginas** (la misma regla; queda como nombre explícito).
  - **TV de 32 pulgadas (las dos del café, 2026-11-02):** una 32" mide 70,8 × 39,8 cm; a 1 cm de mayúscula por metro caben pocas líneas por columna, así que el menú completo va en páginas y la letra nunca baja del mínimo. Medido con el menú real (39 productos) en 1920 × 1080:

    | Distancia | Normal, inglés debajo | Compacta | Compacta, inglés en línea | Compacta, sin inglés |
    |---|---|---|---|---|
    | 1,5 m | 3 páginas (letra 87 %) | 3 (97 %) | 2 (83 %) | **2 (90 %)** |
    | 2 m | 6 (89 %) | 4 (81 %) | 4 (81 %) | **3 (81 %)** |
    | 2,5 m | 9 (80 %) | 7 (83 %) | 7 (85 %) | 6 (83 %) |
    | 3 m | 14 y palabras cortadas (no cabe al mínimo) | 11 (80 %) | 10 (80 %) | 8 (80 %) |

    **A 3 m, la distancia real (confirmada por el dueño el 2026-11-02; medido con la letra del navegador de pruebas: con otra letra puede haber una página más o menos, y la vista previa del panel dice la cuenta real de la TV):** el menú completo necesita 8 páginas o más. Con el **menú resumido** («Productos que muestra»), medido con el menú real, compacta y sin inglés: 12 productos de una categoría = 2 páginas (letra 2,66 cm, 89 % de la meta); con varias categorías cada título y cada nombre de dos renglones cuestan más: 8–10 productos en 2–3 categorías = 2 páginas, 12 en 5 categorías = 3, 15 en 3 = 3, 15 en 5 = 4; con inglés debajo, 12 = 4 (2,50 cm). Regla práctica: 2 páginas ≈ 8–10 productos, 3 páginas ≈ 12, y menos categorías = menos páginas; el resto sigue en el menú QR.

    Regla práctica: con una 32", el cliente más lejano a **1,5–2 m** y **densidad compacta sin inglés** (o con inglés en línea) el menú completo cabe en 2–3 páginas de 28 s; a 2,5 m o más, elegir las categorías de esa TV (P-02) o aceptar 6 páginas o más. A 3 m con inglés debajo la 32" no alcanza ni al mínimo: el diagnóstico lo avisa y la página corta palabras («NO CABE»).
  - `Densidad` **normal** o **compacta** (títulos 1,3 veces, renglones más juntos, inglés al 72 %): cabe más.
  - `Inglés` **debajo** (como la v1), **en línea** (después del nombre, en gris y más pequeño) o **no**.
- **Promociones intercaladas (v2):** con `Promociones = intercalar`, cada «una promoción cada» segundos (30–900) la TV muestra una de sus diapositivas vigentes, por turno, durante «cada promoción dura» segundos (6–30), con fundido, y vuelve a la misma página del menú (la página espera). Una diapositiva se dibuja exactamente como en la Pantalla B (mismo código copiado: producto, marca, invitación con QR y composiciones con sus zonas); sus precios siguen la regla de frescura, contada desde la más vieja de las dos lecturas (la del menú y la de las diapositivas): si una falla y la otra sigue, el precio de la promoción pasa a «por confirmar» y luego desaparece como el de la pizarra; un producto agotado o sin precio no sale. Sin diapositivas vigentes, o con `Promociones = no`, nada interrumpe. Las diapositivas viven solo en memoria; el aparato nunca las guarda.
- **Agotados:** ocultos, o tachados con «Agotado · Sold out» y nunca con precio, según la TV (`pantallas.html`).
- **Categorías:** cada TV muestra todas, o solo las que el dueño elija, en el orden del Gestor.
- **Sin** descripciones, fotos, recomendados, reloj ni combos.

### 4.2 Pantalla B: productos, marca e invitaciones
- Tres clases de diapositiva:
  - **producto**: la foto, el nombre y el precio **se leen del menú en cada lectura**; no se escribe título. Desaparece sola si el producto se agota, queda sin precio o pasa a Extras & Combos. «Pídalo en la caja · Order at the counter».
  - **marca**: título y texto en español e inglés, foto opcional, nunca un precio.
  - **invitación**: título y un código QR a la reseña de Tripadvisor (E-35) o al menú QR, con la dirección corta escrita debajo. El QR mide al menos distancia ÷ 10.
  - **composición (v2)**: nada encima de las zonas, ni el nombre de la franja ni la línea de la marca (ajuste final del dueño, 2026-11-03: los productos y las fotos se explican solos; la «Línea corta de arriba» es solo el nombre de la composición en el panel). Una plantilla (1 · 2 lado a lado · 3 grande a la izquierda · 3 grande a la derecha · 4 en cuadrícula · 4 centro: izquierda 3/8, centro dos apiladas 2/8, derecha 3/8) y una **zona** por lugar. Cada zona es, a elección del dueño, una **foto fija** o una **presentación** propia: su lista ordenada de productos o fotos (hasta 12), sus segundos (4–60), si escribe los **nombres y precios** del menú, y una foto de respaldo (o el diseño de la marca) para cuando no le queda nada que mostrar. Cada entrada guarda el producto (nombre, foto y precio se leen del menú en cada lectura: un producto agotado o sin precio desaparece solo de su zona) o solo una foto subida, con su encuadre (punto de enfoque y zoom). Si un producto se borra del Gestor y su entrada tiene foto propia, la foto queda como foto sola, sin nombre ni precio; sin foto propia, la entrada desaparece. Cada zona tiene su propio reloj; la primera vuelta de cada zona dura un poco más según su posición, así las zonas con los mismos segundos nunca cambian juntas. El cambio es un fundido entre dos capas: la foto siguiente ya está cargada y la vieja queda opaca hasta que la nueva es del todo visible; nunca un cuadro negro. Una foto que no responde en 12 s cuenta como fallida (la zona sigue: el producto con su nombre y sin foto, una foto sola se salta) y una foto fallida se vuelve a pedir pasado un minuto, en la lectura siguiente. Un producto sin foto (ni propia ni del menú) solo se muestra en una zona con nombres y precios; sin ellos no habría nada que dibujar, y el servidor y la página lo cuentan igual (la lista del panel dice «NADA QUE MOSTRAR» en esa zona). Los nombres y precios van en la mitad baja, sobre un velo oscuro que empieza hacia el 22 % de la zona; si no caben a la letra de la distancia, la zona quita primero el inglés y solo después achica el nombre y el precio (P29). La línea de la marca y el rótulo de la franja se achican juntos hasta 0,85; si aún no caben, la línea de la marca se quita y el rótulo conserva el mayor tamaño que quepa. En una TV vertical las zonas se apilan. Una composición cuenta solo mientras alguna zona tenga algo que mostrar; sola en su franja se queda; con otras diapositivas se queda `dwell_seconds` (10–600, por omisión 60). En el registro de cambios quedan las zonas con los ids, nunca un nombre ni un precio.
- **Vigencia obligatoria**: inicio y fin (a lo sumo un año), días de la semana y horas de Costa Rica; orden; estado activa, pausada o retirada. Nunca se borra: se retira.
- Cada TV de promociones muestra todas las diapositivas o solo las que el dueño le asigne.
- Sin nada vigente: la presentación de la marca «Hanging Garden Café · Monteverde, Costa Rica».
- La letra: título 1,2 cm por metro, precio 1,5, textos 0,8; un título largo baja hasta 1,0 y luego se parte.

### 4.3 La gestión (`pantallas.html`)
- Abre con el ingreso del café o del dueño y el **PIN del dueño** (o el ingreso del dueño con el código del teléfono). Un PIN de encargado ve «Solo el dueño puede cambiar las pantallas».
- **Pantallas:** por cada TV, tamaño, distancia, posición, escala de letra, colores, segundos, categorías (menú), productos que muestra (menú: el resumen; nada = todos), agotados (menú), horario, activa; la dirección para la TV con un botón de copiar; una vista previa a escala; agregar una TV. **v2, en una TV de menú:** `Distribución`, `Densidad`, `Inglés` y `Promociones` (no / intercalar, «una promoción cada» 30–900 s, «cada promoción dura» 6–30 s). Una TV de menú con promociones aparece en «Hoy en pantalla» y como destino de las diapositivas.
- **Diapositivas:** lista con estado y «en pantalla ahora»; editor con buscador de productos (nunca Extras & Combos), textos con contador y aviso de precios o combos, foto (del producto o subida, reducida a 1600 px), fechas obligatorias, días, horas, TV y orden; pausar, reanudar, retirar (con confirmación en la página).
  - Las fotos subidas van al depósito existente `menu-photos`, carpeta `pantallas/`, que la 0036 deja solo al dueño (PIN de dueño de la misma sesión, o ingreso del dueño con código); un encargado sigue cambiando las fotos del menú como hoy. Si el servidor rechaza la diapositiva, la página borra la foto recién subida. Una foto reemplazada o quitada de una diapositiva guardada queda en la carpeta: se borra a mano, nunca una que use una diapositiva activa o pausada.
- **Composiciones (v2):** «Nueva composición» abre el editor visual: seis plantillas con su esquema; las zonas dispuestas como en la TV (izquierda, centro arriba, centro abajo, derecha…); por zona, **Foto fija** o **Presentación**, los segundos, «Nombres y precios», la foto de respaldo (subida, la de un producto o ninguna = la marca) y la lista ordenada de entradas desde el buscador de productos (nunca Extras & Combos) o «Subir foto»; cada miniatura se ve encuadrada como en la TV y el **punto de enfoque** se fija con un clic o arrastrando, el **zoom** con un deslizador (100–200 %); subir y bajar, **«Cambiar foto»** (reemplaza la foto de esa posición sin moverla: un producto conserva su producto con una foto propia; «Foto del menú» vuelve a la del producto), quitar, intercambiar zonas (al pasar a una plantilla con menos zonas, se conservan las del mismo lugar: Izquierda, Derecha…); un rótulo opcional (con la regla de textos), la permanencia y la vigencia como cualquier diapositiva. **«Vista previa en la TV»** muestra la página real de la TV (`pantalla-promos?tv=…&preview=1`, con el tamaño, la distancia, la escala, el giro y el look de esa TV en la dirección, porque en ese modo la página no lee nada) dentro del panel con la composición tal como se guardaría, en vivo mientras se edita; en ese modo la página no lee ni escribe nada y solo acepta mensajes del panel en la misma dirección. Cada error del servidor se escribe junto a la zona o la entrada que lo causó. Las fotos subidas se borran si se cancela o si el servidor rechaza la diapositiva. **«Programación sugerida»** crea las cuatro composiciones de las franjas sugeridas, **pausadas** y para cada día, con los productos que el menú tenga en cada categoría (Desayuno 06–10 con cuatro zonas de 14, 16, 18 y 20 s; Almuerzo 10–13 con tres de 12, 15 y 18 s; Tarde 13–17 con dos de 12 y 15 s; Cena 17–19 con una de 10 s), **sin nombres ni precios** (se activan por zona en el editor); si ya existen no crea nada; el dueño las revisa, ajusta y reanuda.
- **Vista previa de la TV de menú:** la página real con lo guardado y, debajo, lo que la TV calcula: «En la TV: N páginas de S s · columnas · letra X cm (mínimo Y)» o «NO CABE a la letra mínima…», leído de la propia página de la vista previa cada 2 s.
- **Hoy en pantalla:** qué sale ahora y qué empieza más tarde hoy en cada TV de promociones (y en una TV de menú con promociones), con la hora del servidor; una composición, con sus zonas.
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
- **Sin la migración 0036** (o revertida): la Pantalla A funciona con los ajustes de su dirección; la Pantalla B muestra la marca; la gestión dice qué migración falta. **Con la 0036 pero sin la 0037** (o con la 0037 revertida): las páginas v2 funcionan como la v1 (los seis ajustes nuevos valen por omisión, el servidor ignora los que no conoce y rechaza una composición con `invalid/kind`); una composición ya guardada queda en la base y la lectura de la 0036 la devuelve sin zonas, así que las TV no la muestran (el panel v1 la lista con rótulos vacíos: pausarla o retirarla desde el panel v2 antes de volver a la v1).

### 4.5 Ajustes de cada TV
- En `pantallas.html`, con los rangos de la migración: pulgadas 24–110, distancia 1–15 m, giro no/derecha/izquierda, escala 70–160 %, look auto/día/noche, página 15–60 s, diapositiva 6–30 s, horario, categorías, agotados, activa; **v2 (0037):** distribución auto/una pantalla/páginas, densidad normal/compacta, inglés debajo/en línea/no, promociones no/intercalar, una promoción cada 30–900 s, cada promoción dura 6–30 s.
- La TV solo lleva `?tv=menu-1` en su dirección y toma los cambios sola en menos de un minuto.
- El técnico puede corregir una TV desde la dirección (`&pulgadas=65&distancia=4&giro=derecha&escala=110&look=dia&pagina=30&diag=1`; v2: `&densidad=compacta&ingles=en-linea|no&layout=una-pantalla|paginas&promo=no&promo_cada=120&promo_seg=8`), que manda sobre la base, ajuste por ajuste. `&diag=1` muestra el cuadro de diagnóstico (v2: también la línea «Maqueta», con columnas y «cabe en una pantalla: sí/no (letra X % de la meta)», y «Promos»); sin él, no se ve. `promo=intercalar` desde la dirección no enciende las promociones de una TV cuya fila dice **no** (el servidor solo entrega las diapositivas cuando la fila lo dice); sí las apaga o cambia sus tiempos.
- **Letra:** mide la letra que de verdad usa (Figtree, o la de la TV); meta 1 cm por metro; baja hacia 0,8 solo si ahorra una página; títulos 1,5 veces (1,3 compacta; una palabra que no cabe en su columna baja hasta 1,25).

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
| no tocar | v3: `website/` (47 archivos), `supabase/migrations/` (37) y `pages.yml` iguales byte por byte a la versión publicada `v2026.11.02-1` (3273743), en el árbol y en el índice; la etiqueta sigue apuntando a ese commit; solo cambian las 4 páginas de las pantallas y solo es nueva la 0037 |
| SQL 440 (181) | Permisos: un visitante solo lee `pantalla_datos`; el café sin PIN, un PIN de encargado, el contador y el dueño sin código reciben `owner_only`; el PIN del dueño y el dueño con código abren. Textos con precios o combos rechazados por campo; 140 letras; fechas obligatorias y hasta 366 días; la clase no cambia; una retirada no se edita; producto de Extras & Combos rechazado. Cada escritura deja una fila en el registro; el registro no se modifica ni se borra. Lo que lee cada TV: vigentes o por empezar en 24 h, por TV, sin pausadas, retiradas ni vencidas; agotado o sin precio oculta el producto; TV apagada = `tv_apagada`. Ninguna tabla existente se escribe (huellas iguales antes y después) |
| SQL 450 (40) | La reversión se niega si falta la 0036 o hay una posterior; quita las funciones, deja las tablas y sus filas y el registro protegido; la 0036 se vuelve a aplicar (la cadena empieza por la reversión de la 0037) |
| SQL 460 (136) | La 0037: las seis columnas con sus valores por omisión y sus reglas; las ayudas cerradas a visitantes e ingresos; `pantalla_guardar` rechaza por campo cada ajuste fuera de rango (16 casos) y registra los seis; `diapositiva_guardar` acepta las seis plantillas con su número de zonas y rechaza, con la ruta exacta (`zones.N.entries.M.item`…), 46 casos de plantilla, zona y entrada, un producto de Extras & Combos, un rótulo con precio; valores por omisión y redondeos; una TV de menú como destino; pausar y reanudar una composición con su resumen; solo el dueño; lo que lee cada TV (una de menú con promociones recibe sus diapositivas, con cada entrada resuelta en vivo y `usable`); ninguna escritura fuera de las tres tablas; cambios del menú (agotado, precio, nombre, foto, borrado, categoría) reflejados en la lectura siguiente sin escribir |
| SQL 470 (73) | La reversión de la 0037 se niega si falta o hay una posterior; vuelve las seis funciones a la 0036 (por comportamiento y por texto, `_slide_json` con escapes y sin caracteres invisibles), quita `_screen_item_json`, deja `_screen_template_places`, columnas, filas (la composición incluida), reglas de Storage y registro; `release-check` ve `[37]` faltante; la 0037 se vuelve a aplicar y encuentra todo |
| SQL 430 (15), 240, 340–420 | La revisión del menú sigue de solo lectura y cuenta como la pantalla; las cadenas de reversión empiezan en la 0036; la lista de funciones públicas es exacta |
| Ensayo | La copia de producción con la 0036: 26 tablas originales iguales, 27 comprobaciones de negocio, respaldo y restauración, anonimizador, las páginas publicadas hoy sobre la copia migrada, el café vacío con las páginas nuevas |
| A1–A9 (370) | La Pantalla A como el prototipo: contenido, orden, exclusiones, legibilidad en 7 tamaños y giros, agotados, conexión, relojes, arranque sin internet, columna `name_es` ausente, recarga tras publicación, ajustes del técnico |
| B1–B11 (370) | Ajustes desde la base y desde la dirección; sin migración o TV desconocida; TV apagada en negro; categorías; agotados tachados; horario; look por hora de Costa Rica; reloj atrasado no detiene las lecturas; sin precio tras dormir; títulos y aviso en TV girada; tablero nunca en blanco; edad desde el inicio de la petición |
| B12–B24 (370, v2) | La pizarra: bloques por categoría en columnas explícitas, toda columna empieza con un título, cortes solo con dos productos a cada lado y «(continúa)», columnas tan parejas como permiten los cortes (la más alta no puede pasar un producto a su vecina y quedar más baja; la más baja a menos de una pieza), nada desborda (B12); el menú real cabe en una pantalla en 75" a 2 m y pagina en 55" a 3 m sin bajar del mínimo; una pantalla / páginas (B13); densidad compacta (B14); inglés debajo / en línea / no (B15); promociones intercaladas con sus tiempos, por turno, fundido, la misma página vuelve, nada en el aparato (B16); nada vigente o `no`: nunca interrumpe (B17); agotado fuera (B18); frescura de precios en la promoción (B19); ajustes desde la dirección (B20); una composición dibujada como en la Pantalla B, zonas independientes, fundido, precio reescrito en vivo (B21); la frescura de la promoción contada desde su propia lectura: con la lectura de diapositivas caída y la del menú viva, «por confirmar» y luego sin precio, nunca el precio viejo como actual (B22); los intermedios siguen donde quedó el anterior: la presentación de una zona arranca en la entrada siguiente a la última mostrada, con la primera vuelta escalonada en cada arranque (B23); los productos de la TV (`item_ids`): solo esos bajo sus categorías, una categoría sin producto elegido desaparece, un id que ya no existe se salta y se cuenta, ninguno = todos y el diagnóstico lo dice, la copia del aparato lo conserva; 12 productos del menú real (5 categorías) en 2–3 páginas a 32"/3 m compacta sin inglés (B24) |
| P1–P17 (380) | Marca sin diapositivas; producto con precio y foto al día; marca e invitación con QR; pausadas, retiradas, vencidas, de otra TV y productos no vendibles ocultos; vence y empieza sola sin internet; días y horas de Costa Rica; política de precios sin conexión; arranque sin internet; relojes; horario; legibilidad; sin migración; reanudar; ajustes; TV apagada; edad de la lectura; recarga tras publicación |
| P18–P29 (380, v2) | Las seis plantillas y su geometría, también en TV vertical (P18); zona fija y zonas automáticas con relojes independientes (P19); nombres y precios sí/no, encuadre, precio en vivo, frescura sin conexión dentro de una zona (P20); producto no vendible saltado, respaldo, marca, la composición sale y vuelve, diagnóstico (P21); la página rechaza por sí misma una composición inutilizable, vacía, con zonas de más o de clase desconocida (P22); permanencia con otras diapositivas y sola (P23); modo vista previa: sin red, solo mensajes del panel en la misma dirección, reemplazo (P24); fundido con las dos capas, la foto cargada y opaca en cada muestra, el orden (P25); una foto que nunca responde cuenta como fallida a los 12 s y la zona sigue, una foto fallida se vuelve a pedir pasado un minuto y vuelve a su turno (P26); una composición que vuelve tras otra diapositiva sigue en la entrada siguiente a la que mostraba al salir, con la primera vuelta escalonada en cada arranque (P27); ventanas con los mismos segundos nunca cambian juntas, tampoco al volver la composición: la primera vuelta se escalona en cada arranque (P28); una ventana pequeña que no puede con el nombre, el inglés y el precio quita el inglés antes de achicar (P29) |
| 390 (27) | Dirección desconocida rechazada; ingreso; PIN de encargado rechazado; PIN del dueño y dueño con código abren; TV guardada y registrada; tres diapositivas; precio o combo bloqueado en la página y rechazado por el servidor; fechas obligatorias; pausar, reanudar, retirar; foto reducida y guardada; Hoy en pantalla; vista previa; de la página a lo que lee la TV; sin migración. **v2:** los seis ajustes de la TV guardados, registrados y leídos por la TV, con su comprobación en la página y el rechazo del servidor por campo; una composición 4 centro construida en el editor (fija + tres presentaciones, buscador, foto subida, enfoque y zoom, respaldo) guardada y releída exacta, reeditada conservando orden y foto; rechazos del servidor escritos junto a la zona o la entrada; la vista previa dibuja la composición enviada sin leer nada y sigue los cambios; una foto subida para la vista previa se borra al cancelar; «Programación sugerida» crea cuatro composiciones pausadas con sus plantillas y productos, y la segunda vez nada; «Hoy en pantalla» con sus zonas; los productos que muestra la TV de menú: tres marcados, guardados, registrados y leídos por la TV, la ficha los vuelve a mostrar marcados, ninguno = todos, nunca un producto de Extras & Combos; la «Programación sugerida» nace sin nombres ni precios; la programación sugerida con segundos distintos por ventana y la plantilla reducida; la línea «En la TV: N páginas…» o «NO CABE» bajo la vista previa de la TV de menú, y que su lectura cada 2 s se detiene al cerrar, al guardar y al cerrar sesión; «Cambiar foto» sigue a su entrada aunque se mueva, gana a una subida en curso y borra la foto anterior; «Foto del menú»; el cierre por inactividad borra las fotos de vista previa abandonadas |
| 340 | Las páginas nuevas no agregan ninguna casilla de PIN (siguen 19) |

## 6. Demostración privada
- Simulador de la Pantalla A v1 con el menú de muestra del repositorio (no son los precios reales), con tamaño, distancia, giro, look, agotados, precios y corte de conexión: https://claude.ai/artifact/6R3r3hBSyXCNcRX2V7q9tX
- Capturas de las tres páginas v1 en el informe de D-062. La vista previa privada de la v2 (pizarra en 75"/2 m, 65"/2,5 m y 55"/3 m, TV vertical, composiciones, panel y editor): https://claude.ai/artifact/V7sLCV4wHUmquYPYgZcYnx; en las TV de 32" del café: https://claude.ai/artifact/DUkFT3ujwoPZCar4K64sdm (`docs/INFORME-PANTALLAS.md` §V2.6).

## 7. Decisiones del dueño
Lo que el dueño decidió el 2026-10-31 ya está construido: combos y descuentos reservados (P-13), gestión con PIN de dueño, permisos del servidor y registro (P-14), ninguna migración sin aprobación (P-15), Pantalla B (P-16), publicación solo con su autorización (P-17), gestión en español sin `lang.js` (P-18).

Lo que sigue en manos del dueño, y cómo lo hace:

| # | Decisión | Dónde |
|---|---|---|
| P-01 | Lugar, tamaño, giro, altura y distancia de lectura de cada TV (formulario 2.1) | `pantallas.html` → Pantallas; el técnico con `docs/INSTALACION-TV.md` |
| P-02 | Si el menú completo no cabe en una pantalla a la distancia real (sección 1.1 y 4.1): páginas, densidad compacta, inglés en línea o no, o elegir las categorías de esa TV | `pantallas.html` → Pantallas → Distribución, Densidad, Inglés, Categorías que muestra, Productos que muestra |
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
