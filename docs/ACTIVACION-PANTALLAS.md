# Activación de las pantallas para los clientes (D-062, migración 0036) · E-40

Esta guía la sigue el dueño. Claude la preparó y la probó en desarrollo; **no aplicó nada en producción ni publicó
nada**.

## Versión 2 (D-064, 2026-11-02): qué cambia y cómo se activa · E-41

La v1 ya está publicada (`v2026.11.02-1`) y la 0036 aplicada. La v2 cambia solo los cuatro archivos de las pantallas y
agrega la migración **0037** (aditiva; la 0036 **no se vuelve a pegar**).

**Qué trae**
- **Pantalla A:** cada categoría es un bloque con su título arriba (nunca un título entre productos de otra); columnas
  equilibradas; el menú completo en **una pantalla** siempre que la letra quede en o sobre el mínimo (0,8 cm por metro),
  y páginas solo cuando no cabe. Por TV: distribución (auto · una pantalla · páginas), densidad (normal · compacta),
  inglés (debajo · en línea · no), los **productos que muestra** (el menú resumido para las TV de 32" a 3 m: nada
  marcado = todos los de las categorías elegidas) y, si quiere, **promociones intercaladas** (cada N s, durante M s) o solo menú.
- **Pantalla B:** **composiciones** de 1 a 4 zonas (plantillas: 1, dos lados, grande + dos, cuadrícula, centro = izquierda
  grande, centro dos apiladas, derecha grande). Cada zona es una **foto fija** o una **presentación propia** (su lista
  ordenada de productos o fotos, sus segundos, nombres y precios del menú en vivo o no, una foto de respaldo). Franjas
  por días y horas de Costa Rica, como las diapositivas.
- **Gestión (`pantallas.html`):** editor visual de composiciones (plantilla, zonas, productos y fotos, encuadre y zoom,
  orden), **vista previa fiel** (la página real de la TV) antes de guardar, y **«Programación sugerida»**: crea cuatro
  composiciones **pausadas** (desayuno 06–10, almuerzo 10–13, tarde 13–17, cena 17–19) con productos del menú por
  nombre y **sin nombres ni precios** (los activa por ventana en el editor), para que usted las revise, las ajuste y las active.
- Lo que no cambia: precios solo del menú (nunca escritos), vigencia obligatoria, PIN de dueño, registro inmutable,
  frescura (2 / 10 min), sin conexión, Caja, Cocina, Contabilidad, menú QR y TV actual (lo comprueba «no tocar»).

**Pasos (en este orden)**
1. «Tests» en verde en el commit de D-064 (el informe dice cuál).
2. **«Ensayo en pruebas»** en verde con esa versión, reinicio = no. (`anonimizar.sql` de esta versión conoce las
   columnas nuevas; súbalo a `canopy-respaldos` como en E-38 si el ensayo lo pide.)
3. **«Respaldo inmediato»** en verde.
4. Supabase → SQL Editor → New query → pegar **todo** `supabase/migrations/0037_pantallas_v2.sql` → Run → *Success*.
   Una sola vez. No pegue la 0036.
5. `release-check.sql`: `migrations_missing` = `[]` (serie hasta la 37), `functions_missing` = `[]`, `anon_can_run`
   sin cambios (solo `pantalla_datos` nueva desde la 0036), `storage_policies_missing` = `[]`.
6. `production-snapshot.sql`: `functions_unknown` = `[]`, `functions_changed` = `[]`, `functions_by_version` con
   `0036` = 7 y `0037` = 8 (la 0037 vuelve a crear seis funciones de la 0036, que la huella cuenta bajo la 0037),
   `tables_missing` = `[]`. Hasta publicar, las TV siguen igual: las páginas v1 ignoran los
   campos nuevos y no muestran composiciones.
7. Releases → `sitio-AAAA-MM-DD` sobre **gh-pages**; luego `vAAAA.MM.DD-1` sobre la rama con el commit de D-064;
   «Tests» en verde sobre la etiqueta; **Publish website** desde la etiqueta con `PUBLICAR`; `version.json` muestra
   la etiqueta y ese commit; Caja, Cocina y TV actual cargan como siempre.
8. En `pantallas.html` con su PIN: **Pantalla A** → para las TV de 32" a 3 m: **Pulgadas 32** y **Distancia 3** (las filas
   nacen con 55"), **Densidad compacta**, **Inglés no**,
   **Productos que muestra** con unos 12 productos (3 páginas de 28 s; 8–10 en 2–3 categorías para 2 páginas; los demás siguen en el menú QR); distribución y
   promociones; «Vista previa» (debajo dice las páginas y la letra que calcula la TV, o «NO CABE»).
   **Diapositivas** → «Programación sugerida» → revise cada composición (zonas, productos, fotos, encuadre), «Vista
   previa en la TV», guarde y **reanude** las que quiera en pantalla. Las diapositivas de la v1 siguen como estaban.
9. Aceptación en las TV: desde el punto más lejano se leen 5 precios; la Pantalla A muestra una pantalla o páginas según
   la letra (el diagnóstico `&diag=1` dice «cabe en una pantalla: sí/no»); en la Pantalla B cada zona cambia a su ritmo
   sin negros; un producto marcado «Agotado» sale de su zona en menos de 1 minuto; sin internet, los precios siguen las
   mismas reglas de siempre.

**Vuelta atrás**
- Las páginas: Publish website desde **Tags → `v2026.11.02-1`**. La base se queda en la 0037: las páginas v1 funcionan con
  ella (los campos nuevos sobran y las dos TV ignoran una composición; el panel v1 la lista con rótulos vacíos y la
  cuenta como «en pantalla»: antes de volver a la v1, pause o retire las composiciones desde el panel v2).
- La base (solo por una falla de una función de la 0037): `supabase/tools/reversion-0037.sql` completo. Vuelve las
  funciones a la 0036 y deja las columnas y las filas; las composiciones guardadas quedan, sin mostrarse, hasta volver a
  aplicar la 0037.

---

## Qué se activa

- **Pantalla A** (`pantalla-menu.html?tv=menu-1`): el menú con precios para la fila.
  - Español primero, inglés debajo.
  - La letra se calcula con el tamaño de la TV y la distancia del cliente más lejano.
  - Los precios y los agotados salen del Gestor del menú, se leen cada 30 s y nunca se escriben a mano.
  - Sin conexión: a los 2 min dice «Precios por confirmar en caja»; a los 10 min ya no muestra ningún precio.
- **Pantalla B** (`pantalla-promos.html?tv=promos-1`): diapositivas de producto, de marca y de invitación.
  - La de producto lee el nombre, la foto y el precio del menú, y desaparece sola si el producto se agota.
  - Cada diapositiva tiene inicio y fin obligatorios, días y horas de Costa Rica, y se apaga sola al vencer, también
    sin internet.
  - Sin diapositivas vigentes, la TV muestra la presentación de la marca.
- **Gestión** (`pantallas.html`): solo con el **PIN del dueño**, o con el ingreso del dueño y el código del teléfono.
  El PIN de un encargado no alcanza.
  - Por cada TV: tamaño, distancia, posición, escala de letra, colores, tiempos, categorías, agotados y horario.
  - Diapositivas: crear, editar, pausar, reanudar y retirar. No se borran.
  - Vista previa de cada TV y «Hoy en pantalla».
  - **Registro de cambios** propio: cada cambio con quién, cuándo, antes y después. No se puede borrar.
- **Migración `0036_pantallas.sql`**:
  - tres tablas nuevas: las TV, las diapositivas y el registro;
  - una lectura pública, `pantalla_datos`;
  - cuatro funciones de gestión, solo para el dueño, y ocho internas (13 en total: las que cuenta
    `production-snapshot.sql`).

## Lo que NO cambia (comprobado)

- **Páginas:** ningún archivo existente de `website/` cambia. Caja, Cocina, Contabilidad, menú QR, TV actual, Inicio,
  `config.js`, `lang.js`, `access.js` y `version.js` quedan byte por byte como en la versión publicada `v2026.10.26-1`.
  Lo comprueba `tests/pantallas/no-tocar.sh` en cada prueba: solo admite los archivos nuevos de las pantallas.
- **Base de datos:** ninguna tabla, función ni fila existente cambia. La única regla existente que se toca es la de
  Storage «menu photos owner write» (0033): se vuelve a crear igual pero sin la carpeta `pantallas/`, y una regla nueva
  deja esa carpeta solo al dueño. Un encargado sigue cambiando las fotos del menú como hoy (la prueba SQL 440 lo
  comprueba). La reversión la deja como en la 0033.
  - El ensayo con la copia de producción lo compara antes y después.
  - Las páginas publicadas hoy pasan sus pruebas sobre la copia migrada.
- **Promociones y combos:** las pantallas no anuncian combos ni descuentos (su condición 7). El servidor rechaza un
  texto con precios (₡, $, %, colones, dólares) o con palabras de combo o descuento.

## 1. Antes (en este orden)

1. **«Tests» en verde** en el commit que se va a etiquetar: el último de la rama
   `claude/hanging-garden-coffee-proposal-1m8zd4`, el de D-062. Su código está en el informe de Claude.
2. **Subir `anonimizar.sql` nuevo a `canopy-respaldos`.** El archivo es
   `ops/backup/repositorio-respaldos/anonimizar.sql` de esta versión: ya conoce las columnas de las tres tablas nuevas.
   Se sube como en E-38. Sin el archivo nuevo, el ensayo se detiene antes de copiar nada, como está diseñado.
3. **«Ensayo en pruebas»** en verde, con esta versión y **reinicio = no**.
4. **«Respaldo inmediato»** en verde.

## 2. La migración 0036 en producción

No bloquea ventas: crea tablas nuevas y no toca ninguna existente. Aun así, mejor fuera del horario.

1. Supabase → **SQL Editor** → **New query** → pegar **todo** `supabase/migrations/0036_pantallas.sql` (botón **Raw** en
   GitHub) → **Run**. Debe decir *Success*.
2. Pegar `supabase/tools/release-check.sql` → Run.
   - `migrations_missing` = `[]` y `functions_missing` = `[]`;
   - `anon_can_run` gana una sola función: `pantalla_datos`;
   - `storage_policies_missing` = `[]` (la regla nueva «screen photos owner write» está).
3. Pegar `supabase/tools/production-snapshot.sql` → Run.
   - `functions_unknown` = `[]`;
   - `functions_by_version` muestra `0036` = 13 y `functions_changed` = `[]`. (Con el archivo anterior a D-063 decía
     `0036` = 12 y `_slide_json · c1da988bed4c` en `functions_changed`: es el texto que quedó en producción al pegar,
     con un carácter invisible normalizado por el navegador; está explicado y aceptado en D-063, sin cambio en
     producción.)
   - `tables_missing` = `[]`.

Si algo sale distinto, no siga: copie el resultado y avíselo. Antes del paso 3 de la sección 3, la migración sola no
cambia nada visible: las tablas nuevas no las lee ninguna página publicada.

## 3. Publicar (una sola versión)

**Qué se publica:**
- la versión publicada hoy (`v2026.10.26-1`) **más** solo `pantalla-menu.html`, `pantalla-promos.html`,
  `pantallas.html` y `pantallas.js`, que son nuevos;
- ningún cambio de otra rama ni de un PR abierto: los PR #4 y #5 **no** van;
- nada de descuentos.

0. **Condiciones:**
   - fuera del horario y **no entre las 00:00 y las 05:00 de Costa Rica**, porque algunas pruebas dependen de la hora;
   - Caja cerrada y cocina sin pedidos;
   - nadie sube nada a la rama hasta que exista la etiqueta.
1. **Guardar el sitio de hoy:** Releases → **Draft a new release** → Choose a tag: `sitio-AAAA-MM-DD` (la fecha de hoy) →
   **Create new tag** → Target: rama **gh-pages** → **Publish release**.
2. **Etiqueta:** Releases → **Draft a new release** → Choose a tag: `vAAAA.MM.DD-1` → **Create new tag** → Target: la rama
   `claude/hanging-garden-coffee-proposal-1m8zd4`. Antes, compruebe que su último commit es el de D-062. Después →
   **Publish release**.
   - En **Tags**, la etiqueta debe mostrar ese mismo commit.
   - Si muestra otro: no publique y cree `-2` en el commit correcto. Una etiqueta nunca se mueve.
3. **Pruebas sobre la etiqueta:** Actions → **Tests** → la ejecución de la etiqueta, en verde.
4. **Publicar:** Actions → **Publish website (PRODUCTION · manual only)** → **Run workflow** → Use workflow from:
   **Tags → la etiqueta** → casilla `PUBLICAR` → «restaurar» vacío → **Run workflow**.
5. **Comprobar la versión:** `https://hanginggardencafe.com/version.json?t=1` dice la etiqueta y el commit de D-062.
6. **Comprobaciones sin registros de prueba:**
   - en una tableta, la Caja, la Cocina y la TV actual cargan como siempre;
   - `https://hanginggardencafe.com/pantalla-menu?tv=menu-1` muestra el menú con precios;
   - `https://hanginggardencafe.com/pantalla-promos?tv=promos-1` muestra la presentación de la marca, porque todavía no
     hay diapositivas;
   - `https://hanginggardencafe.com/pantallas` pide el ingreso y después el PIN del dueño.

## 4. Configurar (en `pantallas.html`, unos 20 minutos)

1. Ingresar con la cuenta del café o la del dueño y abrir con el **PIN del dueño**.
2. **Pantallas → Pantalla A · menú:**
   - tamaño en pulgadas, distancia al cliente más lejano y posición (horizontal o vertical);
   - las **categorías** que muestra: si el menú completo necesita más de 2 páginas a esa distancia, elija las de la
     fila, por ejemplo cafés, otras bebidas y repostería;
   - el horario, por ejemplo 06:00 a 19:00;
   - mire la **vista previa** y guarde.
3. **Pantallas → Pantalla B · promociones:** lo mismo, y los segundos por diapositiva (8 a 10).
4. **Diapositivas:** empiece con 5 o 6 que sirven todo el año, y 1 o 2 de temporada. Todas con su fin; para las de
   todo el año, un fin a 12 meses que se renueva. Ejemplos:
   - **producto** Cloud Forest Latte, con la línea de arriba «Recién hecho · Freshly made»: la TV muestra el nombre del menú (en español si el Gestor lo tiene), la foto y el precio al día; no se le escribe título;
   - **producto** Adventure Box con la línea de arriba «¿Sale temprano mañana? Pídala hoy · Leaving early tomorrow? Order it today», de 15:00 a 19:00;
   - **marca** «Café de altura de Monteverde · Highland coffee from Monteverde»;
   - **invitación** «¿Le gustó su visita? · Loved your visit?» con el QR de reseña en Tripadvisor (el único enlace de
     reseña aprobado, E-35). El QR solo sirve si el cliente está a 3 m o menos.
5. **Hoy en pantalla:** compruebe qué sale ahora en cada TV.
   - Una foto que usted reemplaza o quita de una diapositiva queda guardada en Storage (`menu-photos`, carpeta
     `pantallas/`). Se borra solo a mano, desde Supabase → Storage, y nunca una que todavía use una diapositiva activa
     o pausada.
6. **Registro de cambios:** cada cambio aparece con su nombre.

## 5. Instalar las TV

Siga `docs/INSTALACION-TV.md` (para el técnico): montaje, ajustes de la TV, la dirección, el diagnóstico, la prueba de
letra y las pruebas de aceptación.

## 6. Comprobación final (aceptación)

- Tres personas, una de más de 60 años o con lentes, leen 5 precios al azar desde el punto más lejano.
- Un producto marcado «Agotado» en el Gestor del menú desaparece de las dos TV en menos de 1 minuto. Un precio cambiado
  sale en menos de 1 minuto.
- Una diapositiva con fin dentro de 5 minutos desaparece sola, también con el router desconectado.
- La TV pasa 8 horas sin tocar el control, y vuelve sola a la página después de desenchufarla 1 minuto. Si no vuelve,
  anótelo: la app de quiosco necesita su aprobación, por su condición 6.
- La Caja, la Cocina y la TV actual siguen igual.

## 7. Cómo parar o revertir

- **Una TV:** desmarque **Activa** en `pantallas.html` (la TV queda en negro en menos de un minuto), apáguela o cámbiele la dirección. Nada más se entera.
- **Una diapositiva:** **Pausar** o **Retirar** en `pantallas.html`. La TV la quita en el siguiente cambio, en menos de
  30 s.
- **Las páginas nuevas:** Actions → **Publish website** → Use workflow from: **Tags → `v2026.10.26-1`** → `PUBLICAR` →
  Run workflow.
  - Las TV nuevas muestran la página de error de GitHub (en inglés: «404 · File not found») hasta volver a publicar.
  - La base se queda en la 0036: las páginas publicadas hoy funcionan con ella, y el ensayo lo prueba.
- **La base de datos** (solo por una falla de una función de la 0036): `supabase/tools/reversion-0036.sql` completo en el
  SQL Editor.
  - Quita las funciones y deja la regla de Storage como en la 0033; las tablas quedan con lo que tengan, sin uso.
  - La Pantalla A sigue funcionando con los ajustes de su dirección (`?tv=menu-1&pulgadas=55&distancia=3`).
  - La Pantalla B muestra solo la marca.
  - Se niega si hay una migración posterior aplicada: con la 0037 (Pantallas v2) aplicada, primero
    `supabase/tools/reversion-0037.sql` y después esta, en ese orden (así lo hacen las cadenas de las pruebas).
- **Detenga y avise si:**
  - «Tests» queda en rojo sobre la etiqueta;
  - `version.json` muestra otro commit;
  - la Caja, la Cocina o la TV actual no cargan;
  - una TV muestra un precio distinto al del Gestor del menú.

## 8. Registros

| Fecha | Paso | Resultado |
|---|---|---|
| | | |
