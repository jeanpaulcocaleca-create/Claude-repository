# Pantallas nuevas para los clientes · fase 0 y prototipo de la Pantalla A

Estado al 2026-10-31 (D-060):
- **Nada publicado** y **ninguna migración**.
- **La Pantalla B no se empezó.**
- La fase 0 está lista para el dueño y el técnico: formulario, prueba de letra impresa y revisión del menú (solo lectura).
- El prototipo privado de la Pantalla A existe, con sus pruebas, en `prototipos/pantalla-menu/pantalla-menu.html`.
  - Vive **fuera** de `website/`, así que ninguna publicación lo lleva al sitio: `pages.yml` publica solo `website/`.
  - Publicarlo requiere la autorización expresa del dueño (sección 8).

Plan aprobado («Dirección aprobada»): el plan «Dos pantallas nuevas para los clientes» que Claude presentó, con las 10 condiciones del dueño del 2026-10-31.

## 1. Las condiciones del dueño y cómo se cumplen hoy

| # | Condición (2026-10-31) | Cómo se cumple en esta entrega |
|---|---|---|
| 1 | Primero la Pantalla A, en vista privada; nada de producción sin autorización | El prototipo está fuera de `website/`. No se creó ninguna etiqueta `v*` ni se ejecutó «Publish website». La Pantalla B no se empezó |
| 2 | Caja, Cocina, Contabilidad, menú QR y TV actual intactos, verificado con comparación de archivos y pruebas | `tests/prototipos/no-tocar.sh` compara `website/`, `supabase/migrations/` y `pages.yml` con la versión publicada (`v2026.10.26-1`, commit en `tests/prototipos/BASE`); falla si cambia, aparece o desaparece un solo archivo. Además corre la suite completa de siempre (Caja, Cocina, Contabilidad, menú QR, TV actual) |
| 3 | Precios y disponibilidad leídos solo del menú existente, sin escribir | La página hace una sola consulta de lectura: `GET menu_categories` con sus productos, como la TV actual y el menú QR. No inicia sesión ni llama funciones. La prueba A1 registra cada llamada y solo admite esa lectura |
| 4 | Política segura ante pérdida de conexión y datos viejos; nunca promociones vencidas ni precios no verificados como actuales | Sección 4.3: precios solo de la última lectura correcta, con su edad medida. Por encima de 10 min no se muestra ningún precio. Los precios nunca se guardan en el aparato. Pruebas A4, A5 y A6. La Pantalla A no muestra promociones |
| 5 | Lectura a distancia, precios grandes, sin exceso de información | Mayúscula de 1 cm por metro de distancia (mínimo 0,8), con el precio tan grande como el nombre y en negrita. Sin descripciones, fotos, reloj ni recomendados. Prueba A2 en 7 tamaños y giros |
| 6 | Sin suscripciones, servicios ni aparatos nuevos sin demostrar que hacen falta y sin aprobación | El prototipo usa solo lo que ya existe: el sitio, Supabase con la clave pública y el navegador de la TV. La app de quiosco queda pendiente de prueba (P-09). Consumo estimado de datos en la sección 4.6 |
| 7 | Combos y descuentos reservados hasta que la Caja los cobre exactamente como se anuncian | La pantalla nunca muestra «Extras & Combos» ni un precio cero o negativo (prueba A1). No hay texto libre con precios |
| 8 | Gestión con PIN de propietario, permisos del servidor y registro de cambios | La Pantalla A de la fase 1 no tiene gestión: sus ajustes van en la dirección de cada TV. La página de gestión (fase 2) se hará así, y no antes de que el dueño la apruebe |
| 9 | Ninguna migración ni cambio de configuración de Supabase sin aprobación expresa | Ninguno. La Pantalla A no necesita migración. La revisión del menú (`supabase/tools/menu-pantallas.sql`) es de solo lectura y la corre el dueño |
| 10 | Pruebas y demostración privada antes de pedir autorización para cada publicación | Pruebas en la sección 5 y demostración privada en la sección 6. Esta entrega **no** pide autorización para publicar: faltan los datos de la fase 0 y las decisiones de la sección 7 |

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
| `prototipos/pantalla-menu/pantalla-menu.html` | El prototipo de la Pantalla A. Nunca se publica desde ahí |
| `tests/prototipos/run.sh` | Corre la prueba de «no tocar» y las pruebas del prototipo. Sirve el prototipo junto a una copia de `website/` sobre la base de pruebas, en puertos propios |
| `tests/prototipos/no-tocar.sh`, `tests/prototipos/BASE` | La comparación con la versión publicada |
| `tests/prototipos/specs/010_pantalla_menu.spec.js` | Las 9 pruebas de navegador de la Pantalla A |
| `supabase/tools/menu-pantallas.sql`, `tests/sql/430_menu_pantallas.test.sql` | La revisión del menú, de solo lectura, y su prueba |

`tests/run.sh` (todo, o `tests/run.sh prototipos`) y la integración continua («Tests») corren estas pruebas en cada envío.

## 4. El prototipo de la Pantalla A

### 4.1 Qué muestra
- Las categorías y productos **disponibles con precio mayor que cero**, en el orden del Gestor del menú.
  - Nunca «Extras & Combos», ni un precio cero o negativo, ni un agotado: igual que la TV actual y el menú QR.
- **Español primero; el inglés debajo, al 75 %.**
  - El español sale como en el menú QR: `name_es` del Gestor del menú; si no hay, el diccionario del sitio; si no hay, el nombre una vez.
  - Un nombre igual en los dos idiomas (Espresso, Latte, Tres Leches) se escribe una vez.
- **El precio va pegado al nombre**, en negrita y del mismo tamaño que el nombre; el «₡» al 80 %.
- Al pie: «Precios en colones, IVA incluido · Prices in colones, tax (IVA) included».
  - Coincide con D-011: `price_crc` es el precio final con IVA.
  - La redacción se confirma con el contador (P-10).
- **Páginas:**
  - una categoría nunca se parte entre páginas, salvo que sola sea más larga que una página, y entonces sus partes van seguidas;
  - cada página dura 28 s y se indica «1/3»;
  - 3 o 2 columnas en horizontal, 1 o 2 en vertical.
- **Sin** descripciones, fotos, recomendados, reloj, promociones ni combos.

### 4.2 Ajustes de cada TV, en su dirección
El técnico los escribe una vez al instalar. Ejemplo:
`https://hanginggardencafe.com/pantalla-menu?tv=menu-1&pulgadas=55&distancia=3&giro=no`

| Ajuste | Valores | Para qué |
|---|---|---|
| `tv` | un nombre corto | Identifica la TV en el diagnóstico |
| `pulgadas` | 24 a 110 (si falta: 55) | Diagonal de la pantalla; con ella la página sabe cuántos píxeles son un centímetro |
| `distancia` | 1 a 15 m (si falta: 3) | Distancia al cliente más lejano que debe leer |
| `giro` | `no`, `derecha`, `izquierda` | TV vertical. `derecha` gira la imagen a la derecha, para una TV cuyo borde de arriba quedó a la izquierda (igual que la TV actual) |
| `escala` | 70 a 160 (%) | Corrección según la prueba de letra en el lugar |
| `look` | `auto`, `dia`, `noche` | Claro de 6:00 a 18:00 y oscuro de noche, o uno fijo |
| `pagina` | 15 a 60 (s, si falta: 28) | Tiempo de cada página |
| `diag` | `1` | Muestra al técnico un cuadro con la medida de letra, las páginas, la edad de los precios, la versión y los ajustes no válidos. Sin `diag`, no se ve |

- Un valor no válido se ignora (queda el valor por omisión) y el diagnóstico lo nombra.
- **Letra:**
  - la página mide la letra que de verdad usa: Figtree, o la letra de la TV si Figtree no carga;
  - usa la meta de 1 cm por metro;
  - baja hacia 0,8 cm por metro **solo si eso ahorra una página**, y sube hasta 1,25 cm por metro si sobra espacio;
  - los títulos de categoría van a 1,5 veces; si una palabra no cabe en su columna («costarricenses»), solo ese título baja, nunca a menos de 1,25 veces.

### 4.3 Conexión y datos viejos (condición 4)
- La pantalla lee el menú **cada 30 s**. Un precio cambiado o un producto marcado «Agotado» en el Gestor del menú se ve en la lectura siguiente, sin esperar el cambio de página: en menos de 1 minuto.
- **Edad de los precios:**
  - es el tiempo desde la última lectura correcta;
  - se mide con dos relojes y cuenta el mayor: el reloj de la TV y un reloj que no se mueve aunque alguien cambie la hora;
  - así, una TV que se durmió o una hora adelantada nunca hacen pasar precios viejos por actuales; una hora atrasada tampoco, porque cuenta el otro reloj.

| Edad de la última lectura correcta | Lo que muestra |
|---|---|
| hasta 2 min | Precios normales |
| de 2 a 10 min | Precios con el aviso «Precios por confirmar en caja · Please confirm prices at the counter» |
| más de 10 min, o ninguna lectura todavía | **Ningún precio** (ni un «₡» en la pantalla), los nombres y «Consulte los precios en la caja · Please ask for prices at the counter» |

- **Arranque sin internet** (por ejemplo después de un corte de luz):
  - la TV guarda **solo los nombres** del último menú leído, nunca los precios, y por 3 días como máximo;
  - si hay copia, muestra esos nombres sin precios y con el aviso;
  - si no hay copia, muestra «Hanging Garden Café · Consulte el menú y los precios en la caja»;
  - cuando vuelve la conexión, los precios regresan solos.
- Una respuesta vacía o extraña no cuenta como lectura correcta: queda lo que había, con su edad.
- Los límites de 2 y 10 minutos son una propuesta (P-03).

### 4.4 Actualizaciones y funcionamiento sin atender
- Después de cada publicación, la página se recarga sola con sus ajustes, con el mecanismo del sitio (`version.js`) y **sin el aviso en inglés** que ven los encargados (prueba A8).
- Como en la TV actual, pide a la TV que no apague la pantalla y entra a pantalla completa con OK en el control. Un aviso bilingüe lo recuerda durante 12 s al abrir.
- La app de quiosco solo se propondrá si la prueba de 8 horas y la de corte de luz en la TV real demuestran que hace falta (P-09).

### 4.5 Lo que no hace (por decisión pendiente o por fase)
- Fotos, recomendados, línea de extras, dólares, horario de apagado: decisiones P-04 a P-11.
- Gestión, promociones y combos: fase 2, con la aprobación previa del dueño.

### 4.6 Consumo
- Una lectura del menú pesa unos 4 KB (menos de 1 KB comprimida).
- Cada 30 s durante 13 horas son unos 70 MB al mes, y unos 130 MB si la TV queda encendida las 24 horas. Está dentro del plan de Supabase del café.
- No hace falta ningún servicio nuevo.

## 5. Pruebas
- `bash tests/prototipos/run.sh` es la prueba de «no tocar» más 9 pruebas de navegador, sobre una base de pruebas desechable. Nunca toca Supabase: el navegador bloquea `*.supabase.co`.

| Prueba | Qué demuestra |
|---|---|
| no tocar | `website/` (43 archivos), `supabase/migrations/` (36) y `pages.yml` iguales a la versión publicada `334624c` (`v2026.10.26-1`) |
| A1 | Todo lo disponible con su precio y en orden; nada de Extras & Combos, de agotados ni de precio cero; español primero y una vez si es igual; la nota del IVA; solo lecturas `GET` del menú; los precios nunca guardados en el aparato; tiempos reales: 30 s, 2 min, 10 min, 28 s |
| A2 | 960×540, 1280×720, 1920×1080 y 3840×2160, en horizontal y girada a cada lado: mayúscula de al menos 0,8 cm por metro (medida en la pantalla), títulos 1,5 veces, inglés al 75 % o más, precios del tamaño del nombre, nada cortado, cada producto una vez |
| A3 | Un agotado sale solo; un precio nuevo se ve solo; un producto que vuelve aparece |
| A4 | Sin conexión: precios hasta el límite, luego «por confirmar», luego ninguno; vuelven solos |
| A5 | TV dormida (reloj adelantado) y reloj atrasado: nunca precios viejos como actuales |
| A6 | Arranque sin internet: nombres de la copia sin precios; sin copia, o con una copia de más de 3 días: pantalla de bienvenida sin precios |
| A7 | Sin la columna `name_es` (si `menu-spanish.sql` no se aplicó), el menú sigue saliendo |
| A8 | Recarga sola después de una publicación, con sus ajustes y sin aviso al cliente |
| A9 | Look de día y de noche, diagnóstico solo con `diag=1`, ajustes no válidos nombrados |

Además: la suite completa de siempre (`tests/run.sh`), que incluye la Caja, la Cocina, la Contabilidad, el menú QR y la TV actual, y la prueba SQL `430_menu_pantallas`.

## 6. Demostración privada
- Es una página privada de Claude con un simulador de la Pantalla A, usando **el menú de muestra del repositorio, no los precios reales**.
- El dueño puede elegir:
  - el tamaño de la TV, la distancia, el giro y el look;
  - marcar un producto agotado o cambiar un precio;
  - cortar la conexión y ver los avisos, con los tiempos acelerados (el aviso lo dice).
- Enlace (privado, solo lo abre el dueño): https://claude.ai/artifact/6R3r3hBSyXCNcRX2V7q9tX
- Se construye con el archivo del prototipo, el `lang.js` del sitio y el menú de muestra. No usa `config.js` ni
  `version.js`, y no habla con ninguna base de datos.

## 7. Decisiones del dueño
Cada función espera la decisión del dueño antes de construirse.

| # | Decisión | Estado | Mientras tanto, el prototipo… |
|---|---|---|---|
| P-01 | Lugar, tamaño, giro, altura y distancia de lectura de cada TV (formulario 2.1, con fotos) | Pendiente | usa 55" a 3 m si la dirección no dice otra cosa, y el diagnóstico lo marca como supuesto |
| P-02 | Si el menú completo no cabe en 2 páginas a la distancia real (tabla de 2.4): (a) aceptar más páginas, (b) elegir qué categorías muestra la Pantalla A (por ejemplo, las bebidas y la repostería) y llevar el resto a otra pantalla o al menú QR, (c) TV más grande, o (d) leer de más cerca | Pendiente | muestra todo, en las páginas que hagan falta |
| P-03 | Límites de la política de conexión: 2 min con precios, hasta 10 min «por confirmar», después sin precios; nombres guardados 3 días | Pendiente de confirmar | aplica esta propuesta |
| P-04 | Agotados: ocultarlos (como hoy en la TV y el menú QR) o mostrarlos tachados con «Agotado» | Pendiente | los oculta |
| P-05 | Fotos pequeñas y «Recomendado · Our pick» en 2 o 3 productos | Pendiente | ninguno |
| P-06 | Una línea de «Extras» con los precios leídos de la Caja (leche en batidos, jamón, shot); y si se corrigen las descripciones con precios a mano, que también salen en el menú QR | Pendiente | ninguna; no muestra descripciones |
| P-07 | Look: automático por hora (claro 6:00–18:00) o fijo para cada TV según su luz | Pendiente | automático |
| P-08 | Horario: pantalla negra fuera de las horas del café y apagado con el temporizador de la TV | Pendiente | siempre encendida |
| P-09 | Reproductor: el navegador de la TV (OK para pantalla completa, como la TV actual) o una app de quiosco con licencia, que solo se propone si la prueba de 8 horas y la de corte de luz demuestran que hace falta (condición 6) | Pendiente | funciona en el navegador de la TV |
| P-10 | Redacción del pie «Precios en colones, IVA incluido», confirmada con el contador (Ley 7472: precio final con impuestos) | Pendiente | muestra esa nota, coherente con D-011 |
| P-11 | Dólares: nada, o «Aceptamos dólares al tipo de cambio del día» (depende de A-06); «sin cargo de servicio» (A-05) | Pendiente | nada |
| P-12 | Nombres en español: llenar `name_es` en el Gestor del menú (cambia también el menú QR) o quedarse con el diccionario | Pendiente | `name_es`, si no el diccionario, si no el nombre una vez |
| P-13 | Combos y descuentos | **Decidido** (condición 7): reservados hasta que la Caja los cobre exactamente como se anuncian | nunca los muestra |
| P-14 | Acceso a la gestión | **Decidido** (condición 8): PIN de propietario, permisos del servidor y registro de cambios | no hay gestión en la fase 1 |
| P-15 | Migraciones y configuración de Supabase | **Decidido** (condición 9): ninguna sin aprobación expresa | no necesita ninguna |
| P-16 | Pantalla B | **Decidido**: no avanzar todavía | no existe |
| P-17 | Publicación | **Decidido** (condición 10): cada una con pruebas, demostración y autorización del dueño | no se publica |
| P-18 | Página de gestión escrita directamente en español, sin `lang.js` (excepción a una regla del proyecto) | Pendiente (fase 2) | – |
| P-19 | Presupuesto: pantallas, soportes, cable, supresores, técnico; licencias solo si P-09 lo pide | Pendiente | – |
| P-20 | Fase 2 y siguientes: lugar de la Pantalla B, fotos de promociones (dónde se guardan y su respaldo), enlace de reseña de Google, medición de 6 semanas y quién la anota, qué muestra la TV actual durante la medición | Pendiente | – |

## 8. Antes de pedir autorización para publicar la Pantalla A
1. **Datos:** el formulario 2.1 lleno y la revisión 2.3 corrida en producción.
2. **Decisiones:** P-01 a P-12 decididas, por lo menos P-01, P-02, P-03, P-04 y P-10. Cada cambio que pidan se construye y se prueba.
3. **Prueba en la TV real**, con la página privada abierta desde la dirección de pruebas del técnico. Se acepta si:
   - tres personas, una de más de 60 años o con lentes, leen 5 precios al azar desde el punto más lejano;
   - un agotado sale en menos de 1 minuto;
   - la TV pasa 8 horas sin tocar el control;
   - después de un corte de luz vuelve sola en menos de 3 minutos.
4. **Pruebas automáticas** completas en verde y una demostración nueva.
5. **Solicitud de autorización:**
   - se publica copiando `pantalla-menu.html` a `website/` en un commit propio;
   - `tests/prototipos/BASE` pasa a esa versión solo después de que el dueño la publique;
   - la solicitud dice qué otros cambios llevaría la etiqueta: una etiqueta publica todo el sitio de la rama, y por ejemplo el PR #4, que cambia la Caja, no debe entrar sin decirlo;
   - etiqueta y publicación las hace el dueño, con `docs/PUBLICAR.md`.
6. **Vuelta atrás:**
   - apagar la TV nueva o cambiarle la dirección no afecta nada más;
   - retirar la página es publicar otra vez la versión anterior.
