# Informe · Pantallas para los clientes · versión 2 (D-064) · 2026-11-02

Para: Jean Paul, dueño de Hanging Garden Café.
De: Claude. La versión 1 está publicada (`v2026.11.02-1`) con la migración 0036 aplicada por usted. La **versión 2** que
pidió el 2026-11-02 está construida, probada y revisada en la rama `claude/hanging-garden-coffee-proposal-1m8zd4`
(PR #1), el último commit de la rama (D-064). **Nada está publicado ni aplicado en producción**: lo hace usted con
`docs/ACTIVACION-PANTALLAS-V2.md` (su aprobación técnica del 2026-11-03: primero la prueba visual en las TV reales, sin
tocar producción). La 0036 no se vuelve a ejecutar.

## V2.1 Viabilidad: el menú completo en una sola pantalla

Medido con el menú real de la página pública (7 categorías, 39 productos; 46 renglones en un idioma, 85 con el inglés
debajo) y las métricas de la Pantalla A (mayúscula 0,70 del cuerpo, Figtree ≈ 0,56 em por letra, 16:9). La meta es
1 cm de mayúscula por metro de distancia; el mínimo legible, 80 % de la meta.

| TV y distancia | Estilo actual, inglés debajo | Compacto, inglés debajo | Compacto, solo español |
|---|---|---|---|
| 55" a 2 m | 71 % | 81 % | 90 % |
| 55" a 3 m | 47 % | – | – |
| 65" a 2,5 m | 67 % | 77 % | 85 % |
| 75" a 3 m | 64 % | 74 % | 82 % |

Sin los batidos (28 productos), compacto con inglés: 65"/2,5 m 90 %, 75"/3 m 87 %. Solo bebidas y repostería (24),
compacto con inglés: 55"/2,5 m 83 %, 65"/3 m 82 %.

**Veredicto:** a la distancia de la fila (3 m) el menú completo cabe en una pantalla legible solo en una TV de 75" sin
inglés, o de más de 85". A 2–2,5 m cabe en 55–65" con el estilo compacto.

**Las dos TV reales son de 32"** (su aviso del 2026-11-02): en una 32" (70,8 × 39,8 cm) el menú completo nunca cabe en una
pantalla legible; la Pantalla A lo reparte en páginas sin bajar la letra del mínimo. Medido con el menú real en 1920 × 1080:

| 32" a | Normal, inglés debajo | Compacta | Compacta, inglés en línea | Compacta, sin inglés |
|---|---|---|---|---|
| 1,5 m | 3 páginas (87 %) | 3 (97 %) | 2 (83 %) | **2 (90 %)** |
| 2 m | 6 (89 %) | 4 (81 %) | 4 (81 %) | **3 (81 %)** |
| 2,5 m | 9 (80 %) | 7 (83 %) | 7 (85 %) | 6 (83 %) |
| 3 m | 14, con palabras cortadas | 11 (80 %) | 10 (80 %) | 8 (80 %) |

Recomendación para 32": el cliente más lejano a 1,5–2 m, densidad **compacta** y **sin inglés** (o en línea): 2–3 páginas de
28 s. A 2,5 m o más, elegir las categorías de esa TV o aceptar 6 páginas o más; a 3 m con inglés debajo la letra mínima ya no
cabe en dos columnas (el diagnóstico lo dice). Las capturas a 32" están en la vista previa (V2.6).

**A 3 m, la distancia real (su confirmación del 2026-11-02):** el menú completo no baja de 8 páginas. Por eso la v2 añade el
**menú resumido**: por TV, «Productos que muestra» (`item_ids`); medido con el menú real a 32"/3 m, compacta y sin inglés:
12 productos de una categoría (Café) = 2 páginas (letra 2,66 cm, 89 % de la meta), 16 = 4, 20 = 5; con varias categorías
cada título y cada nombre de dos renglones cuestan más: 8–10 productos en 2–3 categorías = 2 páginas; 12 en 5 categorías = 3;
15 en 3 categorías = 3; 15 en 5 = 4; con inglés debajo, 12 = 4. Regla: **2 páginas ≈ 8–10 productos, 3 páginas ≈ 12; menos
categorías, menos páginas**; el menú QR lleva siempre todos. Estas cuentas se midieron con la letra del navegador de pruebas; en el navegador de GitHub, con letras algo más anchas, 12 productos en 5 categorías dieron 4 páginas: con la letra real de la TV puede haber una página más o menos, y **la vista previa del panel dice debajo la cuenta real de la TV**. V2.10 trae la configuración inicial recomendada y V2.9 su validación. Por eso la Pantalla A muestra **una sola
pantalla siempre que la mayúscula quede en o sobre el mínimo** y, si no, las menos páginas posibles con la letra más
grande; **nunca reduce la letra bajo el mínimo** para que quepa. Usted elige por TV la distribución, la densidad, el
inglés y las categorías. En la prueba con el menú real: una pantalla en 75" a 2 m; páginas en 55" a 3 m.

## V2.2 Qué se entrega

| Pieza | Archivo | Qué hace |
|---|---|---|
| Pantalla A v2 | `website/pantalla-menu.html` | Bloques por categoría (título siempre arriba, nunca entre productos de otra), columnas explícitas llenas hasta casi la misma altura y sin huecos, cortes solo limpios con «(continúa)»; una pantalla cuando la letra lo permite; distribución, densidad e inglés por TV; **promociones intercaladas** (cada N s durante M s, dibujadas exactamente como en la Pantalla B) o solo menú; el **menú resumido** por TV (solo los productos elegidos, bajo sus categorías; B24) |
| Pantalla B v2 | `website/pantalla-promos.html` | **Composiciones** de 1 a 4 zonas con seis plantillas (incluida «4 centro»: izquierda y derecha grandes, centro dos apiladas). Cada zona: foto fija o presentación propia con sus segundos, su lista ordenada, nombres y precios del menú en vivo o no, foto de respaldo o diseño de la marca. Relojes independientes por zona; fundido entre dos capas con la foto ya cargada: nunca un cuadro negro. Modo vista previa para el panel |
| Gestión v2 | `website/pantallas.html` + `pantallas.js` | Los ajustes nuevos de la TV de menú y sus **productos que muestra** (el menú resumido); el **editor visual** de composiciones (plantillas, zonas, productos o fotos subidas, encuadre con clic o arrastre y zoom, orden, intercambio de zonas, rótulo, permanencia, vigencia); **«Vista previa en la TV»** con la página real; **«Programación sugerida»** (cuatro composiciones pausadas por franja); errores escritos junto a la zona o la entrada; «Hoy en pantalla» y el registro con lo nuevo |
| Migración | `supabase/migrations/0037_pantallas_v2.sql` | Aditiva: seis ajustes por TV con valor por omisión, la lista de productos de la TV de menú (`item_ids`, nada = todos), la clase «composicion» (plantilla, zonas, permanencia), dos ayudas cerradas, las funciones de la 0036 vueltas a crear con lo nuevo. Ninguna fila existente cambia |
| Reversión | `supabase/tools/reversion-0037.sql` | Vuelve las seis funciones al texto de la 0036 y deja columnas y filas; se niega si falta la 0037 o hay una posterior |
| Guías | `docs/ACTIVACION-PANTALLAS-V2.md`, `docs/INSTALACION-TV.md` | Sus pasos exactos; la guía del técnico con el diagnóstico nuevo |
| Descripción completa | `docs/PANTALLAS.md` | Cómo funciona todo, pedido por pedido (§1.1) y prueba por prueba (§5) |

**Lo que no se tocó (comprobado en cada prueba, `tests/pantallas/no-tocar.sh` v3):** de los 47 archivos de `website/`
solo cambian los cuatro de las pantallas; las 37 migraciones anteriores y `pages.yml` son byte por byte los de
`v2026.11.02-1`; solo es nueva la 0037. Caja, Cocina, Contabilidad, inventario, ventas, reservas, menú QR y TV actual
siguen exactamente iguales. Ningún servicio nuevo ni de pago. Ninguna regla de Storage ni derecho cambia.

## V2.3 Decisiones técnicas que tomé (y por qué)

1. **Bloques por categoría con cortes limpios, no bloques indivisibles.** La primera construcción trataba cada categoría
   como indivisible: dejaba media columna vacía en 75" y páginas al 70 % en 55"/3 m, contra su pedido «sin espacios
   vacíos». La regla final: un bloque que no cabe se corta donde termina la columna y sigue arriba de la siguiente con
   su título «(continúa)», solo si las dos partes conservan dos productos o más; si no, pasa entero. Toda columna
   empieza con un título y las columnas de cada página terminan casi a la misma altura (prueba B12).
2. **Una pantalla solo con la letra en o sobre el mínimo.** Con «una pantalla» el diagnóstico avisa cuando tuvo que
   paginar; «auto» y «páginas» dan la misma pizarra (la regla de siempre ya elige una pantalla cuando cabe).
3. **La promoción en la Pantalla A se dibuja con el mismo código de la Pantalla B** (copiado función por función, sin un
   archivo nuevo: las páginas no cargan JS externo salvo Supabase y el QR). Una composición se ve igual en las dos TV.
4. **Cada zona guarda solo el id del producto**; nombre, foto y precio se leen del menú en cada lectura. Un producto
   agotado, sin precio o pasado a Extras & Combos sale solo de su zona en la lectura siguiente. El servidor sigue
   rechazando cualquier texto con precio o combo.
5. **La vista previa es la página real de la TV** en modo `preview=1`: no lee ni escribe nada y solo acepta mensajes
   del panel en la misma dirección (`window.parent`, mismo origen). Lo que ve en el panel es lo que verá la TV.
6. **«Programación sugerida» crea composiciones pausadas**: nada sale en una TV por sí solo; usted las revisa y las
   reanuda. Si una categoría no tiene productos, la composición usa la plantilla menor y lo dice.
7. **El fundido entre fotos espera a que la capa nueva esté del todo visible** antes de retirar la vieja (no solo el
   reloj): en un navegador de TV lento el fundido puede empezar tarde y, con el reloj solo, se veía un leve bajón.
8. **La 0037 vuelve a crear también `diapositiva_estado`**, para que pausar, reanudar o retirar una composición deje su
   plantilla como resumen en el registro (la 0036 solo conocía títulos y productos).
9. **Combos y descuentos siguen reservados** (su condición 7): nada de eso entra en la v2.

## V2.4 Resultados de las pruebas

Suite completa (`tests/run.sh`) en verde en el árbol final: lint, no tocar (v3), 47 archivos SQL y las pruebas de
navegador. Lo nuevo de la v2:

| Prueba | Qué demuestra | Resultado |
|---|---|---|
| SQL 460 | La 0037: columnas, reglas, ayudas cerradas, 18 rechazos de ajustes por campo, 10 de la lista de productos (`item_ids`), 51 rechazos de plantilla, zona y entrada con la ruta exacta (ids que no son uuid incluidos), valores por omisión, pausar y reanudar una composición con su resumen, solo el dueño, lo que lee cada TV con cada entrada resuelta en vivo (un producto sin foto ni rótulos no se muestra), ninguna escritura fuera de las tres tablas, cambios del menú reflejados sin escribir | 136 comprobaciones |
| SQL 470 | La reversión de la 0037: se niega sin la 0037 o con una posterior; vuelve las seis funciones a la 0036 (por comportamiento y por texto), deja columnas, filas, reglas de Storage y registro; la 0037 se vuelve a aplicar y encuentra todo | 73 comprobaciones |
| SQL 440 y 450 | La 0036 bajo la 0037 y su reversión (la cadena empieza por la reversión de la 0037) | 181 + 40 |
| Navegador 370 | Pantalla A: las 20 pruebas de la v1 y 13 nuevas (B12–B24; la B22 por la revisión: la frescura de la promoción cuenta desde su propia lectura; la B23 por la validación final: los intermedios siguen donde quedó el anterior; la B24 por el menú resumido): bloques, cortes limpios, columnas llenas y parejas, el menú real en una pantalla en 75"/2 m y en páginas en 55"/3 m, densidad, inglés, promociones intercaladas con sus tiempos y su fundido, nada vigente, agotados, frescura, ajustes por dirección, una composición dibujada como en la Pantalla B, los productos de la TV | 33 pruebas |
| Navegador 380 | Pantalla B: las 17 de la v1 y 12 nuevas (P18–P29; la P26 por la revisión: foto que no responde y foto reintentada; la P27 por la validación final: una composición que vuelve sigue donde iba; la P28 y la P29 por la validación a 32" y 3 m: ventanas con los mismos segundos nunca cambian juntas, y una ventana pequeña quita el inglés antes de achicar): plantillas y geometría, relojes independientes, nombres y precios, respaldo y marca, rechazo propio de composiciones inválidas, permanencia, modo vista previa, fundido con dos capas | 29 pruebas |
| Navegador 390 | Panel: las 14 de la v1 y 13 nuevas: ajustes de la TV, los productos que muestra, composición armada en el editor y guardada exacta, rechazos junto a la zona, vista previa sin leer nada, programación sugerida idempotente (sin nombres ni precios, segundos distintos por ventana, plantilla reducida), la línea de páginas y letra bajo la vista previa de la TV de menú (y que su lectura se detiene al cerrar), «Cambiar foto» y «Foto del menú» (también con una subida en curso), el cierre por inactividad que borra las fotos abandonadas, «Hoy en pantalla» | 27 pruebas |
| no tocar v3 | Solo cambian las cuatro páginas de las pantallas; solo es nueva la 0037; lo demás byte por byte `v2026.11.02-1` | ok |

Dos pruebas de fundido fallaron al correr dos navegadores a la vez bajo carga; la causa era real y quedó corregida
(V2.3 punto 7). La prueba P11 de la v1 (legibilidad en 4K) fallaba de vez en cuando bajo carga porque la regla de
«pausa» de la TV (un tic retrasado cuenta como TV dormida y quita los productos hasta la lectura siguiente) se
disparaba entre dos pasos de la prueba; la prueba ahora espera precios verificados, como haría la TV. La huella de
producción (`production-snapshot.sql`) está regenerada: tras la 0037 cuenta `0036` = 7 y `0037` = 8 (seis funciones de
la 0036 se vuelven a crear y pasan a la 0037).

## V2.5 Revisión independiente

Revisión adversarial de solo lectura con seis lentes (seguridad y permisos; precios, disponibilidad y frescura; maqueta
de la Pantalla A; composiciones de la Pantalla B; el editor del dueño; la migración 0037 y su reversión). Cada uno de
los **28 hallazgos** fue juzgado por un escéptico independiente que intentó refutarlo reproduciéndolo: **22 confirmados,
6 rechazados**. Los 22 confirmados quedaron corregidos y con pruebas (las de regresión nuevas: SQL 460 +7 comprobaciones,
navegador P26 y B22), salvo dos mejoras de pruebas anotadas como pendientes. Lo importante:

| Hallazgo confirmado | Gravedad | Corrección |
|---|---|---|
| En la Pantalla A, el precio de una promoción envejecía con la lectura del menú y no con la de las diapositivas: si la lectura de diapositivas fallaba y la del menú seguía, un precio viejo salía como actual junto al precio nuevo de la pizarra | alta | La promoción es tan fresca como la más vieja de las dos lecturas: «por confirmar» a los 2 min y sin precio a los 10 min, contados desde la última lectura buena de diapositivas (prueba B22) |
| Una foto que nunca respondía dejaba la zona esperando para siempre: ni un agotado ni un cambio de precio llegaban a ella | alta | Una foto sin respuesta en 12 s cuenta como fallida; la zona sigue (el producto con su nombre y sin foto) y las lecturas la alcanzan (prueba P26) |
| Una foto que fallaba una vez no se volvía a pedir en todo el día | media | Se vuelve a pedir pasado un minuto, en la lectura siguiente; al llegar, las zonas la vuelven a mostrar (P26) |
| El equilibrio de columnas partía en piezas de un producto una categoría que cabía entera (TV con pocas categorías); y dejaba columnas medio vacías por llenar «de izquierda a derecha» | media | El equilibrio nunca añade un corte que el primer llenado no tenía; las piezas de cada página se reparten en orden por el reparto que deja menos pizarra vacía bajo las columnas (se prueban todos, no uno a ojo), nunca con menos columnas que el primer llenado; un bloque de tres más alto que una columna va 2 + 1 (B12). La validación final del dueño encontró que la versión anterior (bisección de un límite de altura) hundía el límite hasta la pieza más pequeña (32"/2 m compacta sin inglés: «Café» 4 | 8) y dejaba una columna vacía al partir un bloque de tres en 1 + 1 + 1: corregido con este reparto |
| Se perdió la opción de dos columnas de la v1: en TV pequeñas o lejanas (43"/3 m, 55"/3,5 m) la v2 cortaba palabras | media | Dos columnas vuelven a ser una opción (se usan solo cuando las demás no caben o paginan más); clave para las TV de 32" |
| Las letras de una zona se medían también sobre la capa saliente: tras un nombre largo, uno corto salía pequeño toda su vuelta | media | Las letras se ajustan solo sobre la capa que se dibuja |
| La vista previa del editor no usaba el tamaño, la distancia, la escala, el giro ni el look de la TV elegida | media | La dirección de la vista previa lleva esos cinco ajustes de la TV |
| Un producto sin foto en una zona sin nombres ni precios «se mostraba» sin dibujar nada | baja | El servidor y la página solo lo cuentan si hay nombres o alguna foto; el editor lo avisa |
| Un id de producto de 36 caracteres que no era un uuid daba un error crudo en vez de «invalid/zones.N.entries.M.item» | baja | Solo se acepta la forma canónica de uuid; 460 lo prueba con cinco variantes |
| `pantalla_guardar` aceptaba un null como «dejar igual» en los segundos de promoción pero no en las cuatro palabras | baja | El null se rechaza por nombre en los seis ajustes (460) |
| Fotos subidas para la vista previa quedaban en Storage al abrir otro editor, retirar la diapositiva en edición o cerrar sesión | baja | Se borran en los tres casos |
| Al pasar a una plantilla con menos zonas se perdía «Derecha» y subía una vacía | baja | Se conservan las zonas del mismo lugar (Izquierda, Derecha…) |
| El punto de enfoque solo se movía con el puntero | baja | También con las flechas del teclado (Mayús: de 1 en 1) |
| La guía decía esperar `0036` = 13 tras la 0037 (la huella cuenta `0036` = 7 y `0037` = 8); la vuelta atrás de la v1 nombraba la 0037 como «descuentos» | baja | Guías corregidas, con el orden de las reversiones |
| El panel v1 (vuelta atrás) no «ignora» una composición: la lista con rótulos vacíos | baja | Documentado: pausar o retirar las composiciones antes de volver a la v1 |
| La prueba B21 era sensible a la carga de la máquina | baja | Espera a que las zonas estén quietas y al fundido real |

Rechazados por el escéptico (no son defectos): una dirección de foto con usuario y contraseña (`https://u:p@…`) se publica tal cual
(el contrato la admite; el dueño es el único que la escribe); un producto borrado del Gestor con foto propia sigue como foto sola
(documentado); «páginas» y «automática» dan la misma pizarra (documentado en el panel); el costo de volver a maquetar
(~0,2 s en un navegador de escritorio, solo cuando algo cambia); dos hallazgos que ya estaban corregidos en el árbol
(segundos ocultos de una zona fija; el orden de los cafés fríos en la programación sugerida).

Pendiente, anotado: una prueba que aplique la 0037 sobre una base con filas de la 0036 y que corra la huella tras la
reversión (470); el ensayo de migración ya aplica la 0037 sobre la copia anonimizada de producción.

## V2.6 Vista previa privada

Capturas reales de las páginas de la v2 con el menú real (fotos de color en lugar de las del café, que el navegador
de pruebas no alcanza): https://claude.ai/artifact/V7sLCV4wHUmquYPYgZcYnx · **En las TV de 32" del café**, con la tabla de
páginas por distancia y las cuatro ventanas con y sin rótulos: https://claude.ai/artifact/DUkFT3ujwoPZCar4K64sdm

- Pantalla A: 75"/2 m una pantalla (día y noche); 65"/2,5 m compacta con inglés en línea (2 páginas); 55"/3 m
  (4 páginas) con y sin el diagnóstico; 55"/3 m compacta sin inglés (3 páginas); TV vertical.
- Pantalla B: Desayuno (4 centro), Almuerzo (3 grande a la izquierda), Tarde (2 lado a lado); la misma composición
  intercalada en la Pantalla A.
- Panel: la ficha de la TV del menú con los ajustes nuevos; la lista tras «Programación sugerida»; el editor de la
  composición Desayuno con sus cuatro zonas y la vista previa.

## V2.7 Riesgos reales que debe conocer

| Riesgo | Qué pasa | Qué hacer |
|---|---|---|
| El menú real no cabe en una pantalla a 3 m en una TV de 55" o 65" | La Pantalla A pagina (la letra nunca baja del mínimo). Es física, no un defecto: la tabla de V2.1 | Una TV de 75" o más, o densidad compacta e inglés en línea o sin inglés, o menos categorías en esa TV, o aceptar páginas |
| Los nombres largos pesan | Un nombre de dos renglones ocupa el doble; los batidos (11 nombres largos) son la categoría más cara | Nombres más cortos en el Gestor (`name_es`) ayudan a toda la pizarra |
| Composición sin precio verificado | Sin conexión más de 10 min (o tras dormir la TV), una composición sigue con fotos y nombres **sin precio**; un producto agotado entre tanto sigue con su foto hasta la lectura siguiente (≤ 30 s al volver la conexión). Una diapositiva de producto sola, en cambio, desaparece | Es la regla de frescura de siempre aplicada a cada zona; si prefiere que la composición entera desaparezca sin precio verificado, es un cambio pequeño en una versión nueva |
| Las zonas pueden coincidir por aritmética | Dos zonas con 4 s y 8 s cambian juntas cada 8 s (la primera vuelta de cada arranque solo separa los ritmos iguales) | Segundos distintos y no múltiplos (por ejemplo 7, 9, 11) |
| TV vertical con composición | Las zonas se apilan en bandas de igual altura (en 1080×1920, cuatro bandas de 480 px): legible, pero no es su diseño horizontal | Composiciones de 1 o 2 zonas en una TV vertical |
| La «Programación sugerida» reconoce categorías y productos por nombre | Si cambia el nombre de una categoría o de un producto en el Gestor, la sugerencia agrupa distinto (siempre pausada: usted la revisa) | Revisar las cuatro composiciones antes de reanudarlas |
| La vista previa necesita subir las fotos nuevas | Una foto recién elegida se sube a `menu-photos/pantallas/` para que la TV de la vista previa pueda mostrarla; si cancela o el servidor rechaza, se borra | Nada; es automático |
| (Ya no aplica desde su ajuste del 2026-11-03: sobre una composición no hay rótulo ni línea de la marca) El rótulo y la línea de la marca tapan la esquina superior de las zonas de arriba | Los nombres y precios van abajo, así que no chocan; una foto con el tema en la esquina superior puede quedar tapada | El punto de enfoque y el zoom en el editor |
| Navegador de TV lento | La maqueta de la Pantalla A mide el menú hasta unas 30 veces por rediseño (tres opciones de columnas); en una TV lenta puede tardar unas décimas de segundo, una vez por cambio | Nada; la pizarra anterior sigue en pantalla mientras tanto |
| Con la 0036 pero sin la 0037 | Las páginas v2 funcionan como la v1; una composición no se puede guardar («Revise el tipo») | Aplicar la 0037 antes de publicar, como dice la guía |
| La marca asoma al cambiar de franja | En el instante en que una franja termina y la siguiente empieza, la Pantalla B puede mostrar la marca hasta un segundo (la regla de vigencia de siempre) | Nada; si prefiere un cambio directo, es un ajuste pequeño de la regla de vigencia en una versión nueva |
| Fotos pesadas del Gestor de menú | El Gestor sube la foto del producto tal cual (una de teléfono pesa 3–5 MB); la TV la descarga entera: al encender puede tardar más de 12 s, contar como fallida y verse el respaldo o la marca hasta el reintento del minuto | Subir al Gestor fotos de ≤ 1 MB en JPEG; las que suba desde Pantallas ya se reducen solas. Reducirlas también en el Gestor es un cambio fuera de las pantallas (no se tocó por su condición) |
| Inglés debajo a 3 m en 32" | Con el inglés debajo, el resumen de 12 productos no cabe a la letra mínima y corta renglones; el panel lo avisa en la vista previa («NO CABE») | Densidad compacta e inglés no (o en línea), como en V2.10 |
| Una categoría de dos productos con nombres largos | A 3 m «Repostería y queques» con «Croissant de mantequilla» y «Croissant de chocolate» es más alta que una columna y se parte 1 + 1 con «(continúa)» | Nombres en español más cortos en el Gestor (`name_es`), o 3 o más productos de esa categoría |
| Páginas desiguales por bloques enteros | Una página cuyas categorías van enteras (sin cortes) puede quedar desigual (la última página, por ejemplo 90/44 %): el equilibrio no corta una categoría que el primer llenado dejó entera | Es la regla «sin cortes nuevos»; categorías más cortas o menos categorías por TV emparejan más |

## V2.8 Validación final de los seis puntos (2026-11-02)

Cinco validadores independientes, cada uno con un punto suyo, con las páginas de la rama, el menú real y pruebas
ejecutadas aparte (capturas en el adjunto de esta sesión); el sexto punto es este informe. Veredictos y lo que corregí:

| Punto | Veredicto | Evidencia y correcciones |
|---|---|---|
| 1. Cuatro ventanas simultáneas, fotos distintas, tiempos independientes, fijas y rotativas mezcladas | **Confirmado** | Composición 4 cuadrícula con una zona fija y tres presentaciones a 4, 7 y 11 s: cada zona cambia a su ritmo, nunca dos a la vez salvo por aritmética, la fija nunca cambia, sin cuadro vacío (P19, P25, B21). Dos notas corregidas: al cambiar de foto, los rótulos salientes se apagaban al ritmo del fundido (dos precios visibles ~0,4 s): ahora se apagan en 0,3 s; en la Pantalla A cada intermedio reiniciaba las presentaciones desde la primera foto, así que en una zona lenta las últimas fotos no salían nunca: ahora cada zona sigue en la entrada siguiente a la que mostraba al terminar el intermedio, también en la Pantalla B cuando la composición vuelve tras otra diapositiva (B23, P27) |
| 2. Elegir y reemplazar cada fotografía desde el panel | **Confirmado** | Por posición: buscador del menú (foto del producto), foto subida, foto de respaldo, enfoque y zoom, intercambio de posiciones; reemplazar es elegir otra en la misma posición (no hay un botón «reemplazar» aparte; el marco dice qué muestra) (390) |
| 3. Cuatro franjas horarias y hora de Costa Rica | **Confirmado** | Desayuno 06–10, Almuerzo 10–13, Tarde 13–17, Cena 17–19 con el reloj del servidor en UTC−6, sin horario de verano, fin de semana y noche de por medio (P6, P7, B6, B7). Nota: en el instante del cambio de franja la marca puede verse hasta un segundo (la regla de vigencia de siempre: una diapositiva sale en cuanto pudo terminar y entra cuando seguro empezó); no lo cambio porque usted pidió conservar las reglas de vigencia |
| 4. Legibilidad y distribución de la Pantalla A en las TV reales | **Defecto corregido** | El equilibrio anterior (bisección de un límite de altura) hundía el límite hasta la pieza más pequeña y descompensaba columnas («Café» 4 productos frente a 8 en 32"/2 m compacta sin inglés) y, al partir un bloque de tres en 1 + 1 + 1, dejaba una columna vacía en una página intermedia. Nuevo reparto: las piezas de cada página se reparten en orden por un reparto exacto (se prueban todos): primero la columna más alta lo más baja posible y luego el que deja menos pizarra vacía, sin cortes nuevos, nunca con menos columnas que el primer llenado, y un bloque de tres más alto que una columna va 2 + 1. Con el menú real a 32": 2 m compacta sin inglés 3 páginas al 100/87, 97/97 y 93/76 %; ninguna columna vacía en ninguna de las 20 combinaciones medidas (B12, matriz de V2.1). Nota: el navegador de pruebas mide con Inter en lugar de Figtree; la TV mide su propia letra al cargar (B10) |
| 5. Fotos, precios y disponibilidad del menú real | **Confirmado** | Cada zona y cada diapositiva de producto resuelve en vivo nombre, precio y disponibilidad desde `menu_items` con la misma regla de frescura del menú; agotado o sin precio desaparece en la lectura siguiente; foto del producto desde `photo_url` o la elegida en el editor; nunca un precio escrito a mano (A3, B5, B18, B19, P20, P21, 460) |
| 6. Resumen de archivos, migraciones, pruebas y riesgos | Este informe (V2.2 archivos, V2.4 pruebas, V2.7 riesgos) y `docs/ACTIVACION-PANTALLAS-V2.md` (la 0037, nunca la 0036 otra vez) | |

**Su mensaje posterior (32" a 3 m, menú resumido, ventanas sin rótulos):** construido el mismo día (V2.10) y revisado
otra vez de forma adversarial (el reparto de columnas probado además con 50 000 páginas al azar): 1 hallazgo medio y 6
bajos, todos corregidos (una pieza de un producto en medio de un bloque repartido en tres columnas; dos bloques pequeños
apilados junto a una columna vacía; la página sin reparto posible sin sus medidas; una composición reconstruida en su
sitio perdía la memoria de sus zonas; el diagnóstico del arranque en frío; «N en pantalla» cuando un producto elegido
existe pero no se muestra; «ya no existen» en el resumen del panel).

## V2.9 Validación a 32" y 3 m: legibilidad, tiempos, fotografías y panel (2026-11-02)

Cuatro validadores independientes, de solo lectura, con el código, las capturas a 32"/3 m (medidas en píxeles: 27,1 px por cm)
y las pruebas: **legibilidad, fotografías y panel confirmados con notas; tiempos: un defecto, corregido**. Lo que encontraron y lo que hice:

| Punto | Veredicto | Evidencia y correcciones |
|---|---|---|
| Legibilidad | **Confirmado con notas** | Resumen de 12 a 3 m: mayúscula medida 2,44 cm (0,81 cm por metro), precios del mismo tamaño, títulos 3,25 cm; equivale a la regla de rotulación «1 pulgada por cada 10 pies» y queda sobre el mínimo legible, por debajo de la meta cómoda de 1 cm por metro (para 3 cm: «Escala de letra» 120–125 % en la ficha, a costa de más páginas). Contraste de la pizarra 7:1 a 15:1 de día y de noche. Corregido: en una ventana pequeña con nombres y precios, el inglés se quita antes de achicar el nombre y el precio (antes bajaban a 1,9 cm); el velo oscuro bajo los rótulos empieza más arriba (el primer renglón tenía contraste 2:1–3:1 sobre fotos claras); la línea de la marca se quita antes de achicar el rótulo de la franja bajo 0,85 (antes llegaba a 1,44 cm). Notas: con **inglés debajo** el resumen de 12 a 3 m no cabe al mínimo y corta renglones: la configuración debe ser compacta y sin inglés (V2.10), y la ficha ahora lo dice; las filas de las TV nacen con 55" y 3 m hasta que usted ponga 32" |
| Tiempos | **Defecto corregido** | Páginas de 28 s (ciclo de 84 s con 3 páginas; 15–60 s permitido); fundido de 0,6 s; una lectura no reinicia la página. **Defecto:** una composición que volvía (al día siguiente en la Pantalla B, en el segundo intermedio en la Pantalla A) arrancaba sin escalonar sus ventanas, y con segundos iguales las cuatro cambiaban a la vez. Ahora la primera vuelta se escalona en cada arranque (ventana i: 1 + 0,25·i vueltas), siguiendo en la foto siguiente a la última mostrada (prueba P28); y «Programación sugerida» da segundos distintos a cada ventana: 4 centro 14/16/18/20 s, 3 grande 12/15/18 s, 2 lado a lado 12/15 s, 1 ventana 10 s (antes 8 s en todas: un fundido cada 2 s, inquieto a 3 m). Notas: al cambiar de franja (10:00, 13:00, 17:00) el paso es un corte limpio, nunca negro; con promociones intercaladas en la Pantalla A use «cada promoción dura» de 20 s o más si intercala composiciones |
| Fotografías | **Confirmado con notas** | Cada ventana usa la foto del producto del menú en vivo o la que usted suba por posición (reducida en el navegador a ≤ 1600 × 2400 px, ~200–500 KB); encuadre y zoom iguales en el editor y en la TV; sin rótulos la foto llena la ventana; foto que cuelga: 12 s y reintento al minuto; agotado: sale de su ventana. En «4 centro» las ventanas laterales son verticales (26,5 × 39,8 cm, 2:3) y las del centro casi cuadradas (17,6 × 19,8 cm): una foto horizontal 4:3 pierde la mitad de los lados en las laterales. Corregido: el cierre por inactividad borra las fotos de vista previa abandonadas. **Riesgo fuera de las pantallas:** el Gestor de menú sube la foto del producto sin reducir; una foto de teléfono de 3–5 MB tarda en la TV y puede contar como fallida al encender (12 s) hasta el reintento: suba al Gestor fotos de ≤ 1 MB, en JPEG (no HEIC). Las capturas usan fotos de prueba: el recorte real se comprueba con «Vista previa en la TV» y las fotos del café |
| Panel | **Confirmado con notas** | Todo el recorrido existe y lo prueba la 390: PIN del dueño, ficha con 32" y 3 m, densidad, inglés, distribución, categorías y «Productos que muestra», guardado con su revisión por campo, la TV cambia en ≤ 30 s, «Programación sugerida» en pausa y sin rótulos, editor, «Hoy en pantalla», registro; el menú QR, la TV actual y el Gestor no cambian (byte por byte). Corregido: la vista previa de la TV de menú dice ahora debajo «En la TV: N páginas · columnas · letra» o «NO CABE»; «Cambiar foto» reemplaza la foto de una posición sin moverla (y «Foto del menú» vuelve a la del producto); una ventana sin nada que mostrar (sin foto y sin nombres) lo dice en la lista; la pista de productos dice sus supuestos y que un producto de una categoría no marcada no sale |


## V2.10 Configuración inicial recomendada para las dos TV de 32" a 3 m (su mensaje del 2026-11-02)

Nada de esto se aplica solo: lo hace usted en `pantallas.html` después de publicar (V2.11); la página vuelve a dibujar
cada TV en menos de 30 s.

| TV | Ajuste | Valor inicial | Dónde |
|---|---|---|---|
| Pantalla A (menú) | Distancia · Pulgadas | 3 · 32 (las filas nacen con 55"; sin esto la letra se calcula para 55") | Ficha de la TV |
| Pantalla A | Densidad · Inglés | compacta · no | Ficha de la TV |
| Pantalla A | Distribución | auto (2–3 páginas de 28 s con el resumen: un ciclo de 56–84 s) | Ficha de la TV |
| Pantalla A | Categorías que muestra | todas (ninguna marcada) | Ficha de la TV |
| Pantalla A | **Productos que muestra** | **unos 10–12 productos principales** (ajuste hasta que la vista previa diga 2 o 3 páginas), por ejemplo 5 cafés, 2 batidos, 2 sándwiches, 2 de repostería y 1 favorito costarricense (medido: 3 páginas de 28 s, letra 2,45 cm); para 2 páginas, 8–10 productos en 2–3 categorías (por ejemplo 5 cafés y 3 de repostería) | Ficha de la TV → «Productos que muestra» |
| Pantalla A | Promociones | no (o intercalar, cada 180 s durante 10 s, con la composición de la franja) | Ficha de la TV |
| Pantalla B (promos) | Composiciones | «Programación sugerida»: Desayuno 06–10 (4 centro, ventanas cada 14/16/18/20 s), Almuerzo 10–13 (3 grande izq., 12/15/18 s), Tarde 13–17 (2 lado a lado, 12/15 s), Cena 17–19 (1 ventana, 10 s); nacen **pausadas** y **sin nombres ni precios** | Diapositivas |
| Pantalla B | Nombres y precios | apagados en las cuatro ventanas; se activan por ventana en el editor cuando usted quiera | Editor → cada zona |
| Pantalla B | Fotos | las del menú (foto del producto) o las que suba por posición («Cambiar foto» reemplaza sin mover; «Foto del menú» vuelve a la del producto); encuadre y zoom por foto; verticales 2:3 para las ventanas laterales de 4 centro, cuadradas o 3:4 para las del centro, el plato al centro con aire alrededor | Editor → cada entrada |
| Pantalla B | Horarios | editables por composición (días, horas de Costa Rica, fechas) | Editor → vigencia |
| Menú QR | — | sin cambios: todos los productos | — |

## V2.11 Qué sigue (en sus manos)

**Su aprobación técnica (2026-11-03).** Usted aprobó técnicamente la V2 y pidió verla en las TV reales de 32" antes de
activar producción. Los pasos exactos, en orden, con las comprobaciones y la vuelta atrás, están en
**`docs/ACTIVACION-PANTALLAS-V2.md`**: (0) la prueba visual en las TV reales con una página privada que corre las páginas
de la V2 sobre una copia del menú, sin tocar producción (https://claude.ai/artifact/HJDYiJ8PG285kUhwUo4Sib); (1) la
preparación (pruebas, el archivo del ensayo, el ensayo, la etiqueta y sus pruebas, el mismo día); (2) el respaldo, la
foto de antes, la 0037, `release-check.sql` y la foto de después, con los valores exactos; (3) guardar el sitio de hoy y
la publicación; (4) la
configuración inicial de V2.10 campo por campo; (5) la verificación en las TV con los datos reales, con el café cerrado,
para seguir o volver atrás; (6) la vuelta atrás: las páginas a `v2026.11.02-1` (probado en el ensayo: las pantallas v1
sobre la base con la 0037) y, solo por una falla de una función, `reversion-0037.sql`, con sus valores comprobados en una
copia. **No publique ni aplique nada hasta decidirlo**; esta entrega no lo hace.

Medido con la letra real de las TV (Figtree, la que carga la página; el navegador de las pruebas automáticas mide con
Inter y da 8 páginas en el menú completo): a 32" y 3 m, compacta y sin inglés, el resumen de 12 productos en 5
categorías da 3 páginas con mayúscula de 2,48 cm, el de 9 productos 2 páginas (2,40 cm) y el menú completo 10 páginas.

Las secciones 1 a 4 de abajo son la entrega de la v1 (D-062, ya activada). Su «Si algo sale mal» vuelve a
`v2026.10.26-1`, que hoy quitaría las pantallas: para la V2 vale solo la guía nueva.

---

# Informe final · Pantallas para los clientes (D-062) · 2026-10-31, verificación final 2026-11-01

Para: Jean Paul, dueño de Hanging Garden Café.
De: Claude. Todo lo descrito está construido, probado e integrado en una sola versión en la rama
`claude/hanging-garden-coffee-proposal-1m8zd4` (PR #1). **Nada está publicado ni aplicado en producción**: lo hace
usted con los pasos de la sección 4.

## 1. Qué se entrega

| Pieza | Archivo | Qué hace |
|---|---|---|
| Pantalla A | `website/pantalla-menu.html` | El menú con precios para la fila. Español primero, inglés debajo. La letra se calcula con el tamaño de la TV y la distancia del cliente más lejano (1 cm de mayúscula por metro, mínimo 0,8). Precios solo de una lectura verificada: hasta 2 min normales, hasta 10 min con «Precios por confirmar en caja», después ningún precio. Categorías por TV, agotados ocultos o tachados, horario, pantalla negra si la apaga |
| Pantalla B | `website/pantalla-promos.html` | Diapositivas de **producto** (nombre, foto y precio leídos del menú en cada lectura), de **marca** y de **invitación** (QR a la reseña de Tripadvisor o al menú QR). Inicio y fin obligatorios, días y horas de Costa Rica. Vence sola, también sin internet. Sin nada vigente, la marca |
| Gestión | `website/pantallas.html` + `pantallas.js` | Solo con el **PIN del dueño** (o su ingreso con el código del teléfono). Cada TV, las diapositivas, «Hoy en pantalla», vista previa y el **registro de cambios** que nadie puede borrar. Escrita en español |
| Migración | `supabase/migrations/0036_pantallas.sql` | Tres tablas nuevas, una lectura pública para las TV y cuatro funciones de gestión. Los textos no admiten precios ni combos o descuentos: el servidor los rechaza |
| Reversión | `supabase/tools/reversion-0036.sql` | Quita las funciones y deja las tablas con lo que tengan |
| Guías | `docs/ACTIVACION-PANTALLAS.md`, `docs/INSTALACION-TV.md` | Sus pasos exactos; la guía del técnico |
| Descripción completa | `docs/PANTALLAS.md` | Cómo funciona todo, prueba por prueba |

Sus condiciones del 2026-10-31, una por una y cómo se cumplen: `docs/PANTALLAS.md` §1.

**Lo que no se tocó (comprobado en cada prueba):** los 43 archivos de `website/`, las 36 migraciones y `pages.yml`
son byte por byte los de la versión publicada `v2026.10.26-1`. Caja, Cocina, Contabilidad, menú QR y TV actual siguen
exactamente iguales. La única regla existente que la migración toca es la de las fotos del menú en Storage: se vuelve a
crear igual, pero la carpeta nueva `pantallas/` queda solo para el dueño (un encargado sigue cambiando las fotos del
menú como hoy).

## 2. Resultados de las pruebas

Suite completa (`tests/run.sh`), en verde en el árbol final y en la integración continua de GitHub («Tests»):

| Prueba | Resultado |
|---|---|
| Lint (secretos, reglas de publicación, migraciones) | ok |
| SQL: 45 archivos, entre ellos **440_pantallas (181 comprobaciones)** y **450_reversion_0036 (40)** | 45 / 45 |
| Respaldos (copia, cifrado, restauración) | ok |
| Ensayo con la copia de producción: 37 migraciones, 26 tablas originales iguales, 27 comprobaciones de negocio, anonimizador, 5 copias de pruebas | ok |
| Páginas publicadas hoy sobre la base con la 0036 | 8 / 8 |
| Café vacío (reinicio) con las páginas nuevas | 8 + 2 |
| Navegador: 159 pruebas de siempre + **51 nuevas** (Pantalla A 20, Pantalla B 17, gestión 14) | 210 / 210 |
| «No tocar»: `website/`, migraciones y `pages.yml` iguales a `v2026.10.26-1` (etiqueta comprobada en GitHub) | ok |

Lo que prueban las nuevas, en pocas palabras:
- **Permisos:** un visitante solo lee `pantalla_datos`; el café sin PIN, un PIN de encargado, el contador y el dueño sin
  código reciben `owner_only` en las cuatro funciones de gestión; ninguna función escribe en el menú ni en ninguna
  tabla existente (huellas iguales antes y después de 37 escrituras).
- **Textos:** ₡, ¢, $, %, €, colones, dólares, montos con miles (4.500), combo, descuento, 2x1, 3×2, «lleve 2 y pague 1»,
  gratis, de regalo, cortesía, sin costo, buy one get one: rechazados campo por campo. «Tour en 4x4», «gluten-free» y
  «¿Sale temprano mañana? Pida su Adventure Box»: aceptados.
- **Precios y vigencia:** sin conexión, los precios siguen 2 min, luego «por confirmar», a los 10 min ninguno; una
  diapositiva vence y empieza sola con el router apagado; mover el reloj de la TV no revive nada vencido; tras dormir, sin
  precio hasta la lectura siguiente.
- **Legibilidad:** 960×540, 1280×720, 1920×1080 y 4K, horizontal y girada a cada lado: mayúscula medida en pantalla,
  nada cortado.
- **Gestión:** dirección desconocida rechazada; PIN de encargado rechazado; PIN del dueño abre; cada cambio queda en el
  registro con «Dueño (owner)»; foto reducida y guardada; lo creado en la página es lo que lee la TV.

**Falla previa diagnosticada (su punto 1):** la prueba 070 Q-b de la Caja falló una vez en este contenedor porque las
herramientas de prueba se habían reinstalado con un navegador distinto al que espera la versión fijada; con el navegador
correcto pasa siempre (8 de 8 corridas, también sobre la versión publicada). **No es una regresión**; la Caja no se
tocó. En GitHub, que instala el navegador correcto, nunca falló.

**Revisión independiente (su punto 2):** un equipo de revisores de solo lectura revisó la migración, las tres
páginas, las pruebas, la comprobación de «no tocar» y los documentos, y cada hallazgo pasó por un escéptico. Resultado:
23 hallazgos, **11 corregidos** antes de este commit (los demás descartados por el escéptico). Los más importantes:
- el filtro de textos no reconocía el signo de colón que se escribe en un teclado tico (¢) ni «lleve 2 y pague 1»;
- un encargado con su PIN podía cambiar la foto de una diapositiva en Storage (ahora solo el dueño);
- una TV que usted desactiva se quedaba con el menú en vez de ponerse en negro (ahora se pone en negro, y al reiniciar
  sin internet también);
- la página decía «Reseña en Google» donde el QR lleva a Tripadvisor (el único enlace aprobado).
Detalle en D-062 (`docs/DECISIONS.md`).

**Verificación final (2026-11-01, después de su ensayo #13):** una segunda revisión independiente, con cinco lentes
(seguridad, permisos, fotografías, programación y reversión), comprobó una por una 72 propiedades del sistema:
**72 verificadas, ninguna rechazada, 10 hallazgos menores, todos corregidos y probados** en esta versión:
- el filtro de textos limpia caracteres invisibles, dígitos de ancho completo y espacios raros antes de revisar, y
  también rechaza «dos por uno», «por ciento» y «rebajado»;
- las listas de categorías, de TV y de días admiten 50 entradas a lo sumo y cada una cuenta una vez;
- las horas se validan como HH:MM antes de guardarlas (24:00, 7:00 o segundos se rechazan con el campo);
- la lectura de las TV llena sus 60 lugares primero con las diapositivas vigentes y después con las que empiezan;
- el registro nombra el derecho que abrió la gestión («owner login · correo» o «Nombre (owner)»);
- la gestión borra una foto recién subida si el servidor rechaza la diapositiva, y calcula «termina hoy» con la hora
  del servidor;
- la reversión quita las 13 funciones de la 0036 (incluidas las internas).

**Ensayo de reversión en los dos sentidos**, sobre la copia de producción del ensayo: revertida → libro en 35, las
8 páginas publicadas hoy pasan sus pruebas sobre la copia revertida, la Pantalla A sigue desde su dirección, la B
muestra la marca y la gestión dice qué migración falta; aplicada de nuevo → 36, todo vuelve.

## 3. Riesgos pendientes (lo que ninguna prueba automática puede cerrar)

| Riesgo | Qué hacer |
|---|---|
| **La TV no vuelve sola a la página después de un corte de luz**, o se duerme a las 8 horas. Depende de cada TV. | Las pruebas del técnico (`INSTALACION-TV.md` §6). Si fallan, una app de quiosco con licencia necesita su aprobación (condición 6) |
| **El menú completo no cabe en 2 páginas a distancia de fila** (55" a 3 m: 4 páginas, casi 2 minutos de ciclo) | En `pantallas.html`, elegir las categorías de la fila para la Pantalla A; el resto queda en el menú QR |
| **Lectura real:** la letra está calculada, no vista por personas de verdad | La prueba de aceptación: tres personas, una con lentes o mayor de 60, desde el punto más lejano |
| **Foto de diapositiva desde la tableta del café:** Storage no recibe el token del PIN, solo la sesión; funciona con la apertura del dueño de la misma sesión (regla nueva de la 0036, solo el dueño). Probado en SQL, no en una tableta real. Una foto reemplazada queda en Storage hasta borrarla a mano | La primera foto la sube usted desde la tableta con su PIN; si Storage la rechaza, cámbiela desde su ingreso con el código y avise |
| **Redacción del pie «Precios en colones, IVA incluido»** y las reglas de la Ley 7472 | Confirmar con el contador (P-10) |
| **Sin la migración**, las páginas funcionan (A desde su dirección, B solo marca) pero sin gestión | Aplicar la 0036 antes de configurar |
| **Costo:** dos TV leyendo cada 30 s, 13 h/día: unos 150 MB/mes de Supabase. Dentro del plan | Nada; vigilar el uso el primer mes |

Decisiones que siguen siendo suyas (P-05 fotos en la Pantalla A, P-06 línea de extras, P-11 dólares, P-19 presupuesto):
`docs/PANTALLAS.md` §7.

## 4. Pasos exactos para activar las dos pantallas

Todo esto lo hace usted; la guía larga con cada comprobación es `docs/ACTIVACION-PANTALLAS.md`.

**Antes**
1. Confirmar que «Tests» está en verde en el último commit de la rama (el de D-062).
2. Subir el nuevo `ops/backup/repositorio-respaldos/anonimizar.sql` a `canopy-respaldos` (como en E-38).
3. «Ensayo en pruebas» en verde con esta versión, **reinicio = no**.
4. «Respaldo inmediato» en verde.

**La migración (no bloquea ventas; mejor fuera del horario)**
5. Supabase → SQL Editor → New query → pegar **todo** `supabase/migrations/0036_pantallas.sql` → Run → *Success*.
6. Pegar `supabase/tools/release-check.sql` → Run: `migrations_missing` = `[]`, `functions_missing` = `[]`,
   `anon_can_run` gana solo `pantalla_datos`, `storage_policies_missing` = `[]`.
7. Pegar `supabase/tools/production-snapshot.sql` → Run: `functions_unknown` = `[]`, `functions_by_version` con
   `0036` = 13 y `functions_changed` = `[]`. (Su primera corrida, 2026-11-01, dio `0036` = 12 y `_slide_json`
   cambiada: el navegador normalizó un carácter invisible al pegar la 0036. Investigado, probado inofensivo y
   registrado como variante conocida en D-063; con esta versión del archivo da 13 y `[]`. Producción no cambió.)

**Publicar (una sola versión; no entre las 00:00 y las 05:00 de Costa Rica)**
8. Releases → **Draft a new release** → tag `sitio-AAAA-MM-DD` → Target **gh-pages** → Publish (el sitio de hoy, para
   volver atrás).
9. Releases → **Draft a new release** → tag `vAAAA.MM.DD-1` → Target la rama
   `claude/hanging-garden-coffee-proposal-1m8zd4` (compruebe que su último commit es el de D-062) → Publish. En
   **Tags**, la etiqueta debe mostrar ese commit; si no, cree `-2` en el correcto.
10. Actions → **Tests** sobre la etiqueta, en verde.
11. Actions → **Publish website (PRODUCTION · manual only)** → Run workflow → Use workflow from: **Tags → la etiqueta**
    → `PUBLICAR` → «restaurar» vacío → Run.
12. `https://hanginggardencafe.com/version.json?t=1` muestra la etiqueta y el commit de D-062. En una tableta, Caja,
    Cocina y TV actual cargan como siempre.

**Configurar (unos 20 minutos)**
13. `https://hanginggardencafe.com/pantallas` → ingresar → PIN del dueño.
14. **Pantallas → Pantalla A · menú:** tamaño, distancia al cliente más lejano, posición, categorías de la fila, horario
    → Vista previa → Guardar. Copiar la dirección de la TV con el botón.
15. **Pantallas → Pantalla B · promociones:** lo mismo, y los segundos por diapositiva (8–10).
16. **Diapositivas:** 5 o 6 de todo el año (producto Cloud Forest Latte, marca «Café de altura de Monteverde»,
    invitación con el QR de Tripadvisor…) y 1 o 2 de temporada; todas con fin.
17. **Hoy en pantalla:** comprobar qué sale ahora en cada TV.

**Instalar (técnico, `docs/INSTALACION-TV.md`)**
18. Montaje, ajustes de la TV (sin apagado automático, sin protector, que vuelva encendida tras un corte).
19. En el navegador de cada TV, la dirección copiada en el paso 14/15; OK para pantalla completa.
20. Con `&diag=1` al final, comprobar «Precios: al-dia» y la medida de letra; quitar `&diag=1`.

**Aceptación**
21. Tres personas leen 5 precios desde el punto más lejano. Un «Agotado» del Gestor del menú desaparece de las dos TV
    en menos de 1 minuto. Una diapositiva con fin en 5 minutos desaparece sola con el router apagado. La TV pasa 8
    horas sin tocar el control y vuelve sola tras desenchufarla 1 minuto.

**Si algo sale mal**
- Una TV: desmarcar **Activa** en `pantallas.html` (queda en negro), apagarla o cambiarle la dirección.
- Una diapositiva: **Pausar** o **Retirar**.
- Las páginas nuevas: Publish website desde **Tags → `v2026.10.26-1`** (la base se queda en la 0036: las páginas de hoy
  funcionan con ella, probado).
- La base, solo por una falla de una función: `supabase/tools/reversion-0036.sql` completo en el SQL Editor.
