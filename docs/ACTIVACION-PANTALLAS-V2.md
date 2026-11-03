# Activar Pantallas V2 en el café (D-064, migración 0037) · E-41

Esta guía la sigue el dueño, paso a paso. Claude la preparó y la probó en desarrollo; **no aplicó nada en producción ni
publicó nada**. Cada paso que cambia producción lo hace usted, cuando lo decida.

**Qué se activa:** las cuatro páginas de las pantallas de la V2 (`pantalla-menu.html`, `pantalla-promos.html`,
`pantallas.html`, `pantallas.js`) y la migración **0037** (aditiva). Ninguna otra página cambia: la Caja, la Cocina, el
menú QR, la TV actual y las demás quedan byte por byte como en la versión publicada hoy (`v2026.11.02-1`); lo comprueba
`tests/pantallas/no-tocar.sh` en cada prueba. La 0036 ya está aplicada: **no se vuelve a pegar**.

**La versión:** el último commit de la rama `claude/hanging-garden-coffee-proposal-1m8zd4`, con «Tests» en verde. Su
código se lo doy en el informe y está en el PR #1. La 0037 es la misma desde `83b3dcd`; las páginas llevan su ajuste final
del 2026-11-03 (ningún título de franja ni línea de la marca sobre las composiciones).

**Estado:** usted hizo la prueba visual en las TV de 32" (etapa 0) y aprobó la V2 el 2026-11-03 con ese ajuste final.
Lo que sigue (etapas 1 a 5) lo hace usted; las reglas del repositorio (`CLAUDE.md`) no me dejan publicar ni tocar la
base de producción. Pégueme cada resultado que pide la guía y yo lo compruebo antes de que siga.

**En orden:**

| Etapa | Qué | ¿Toca producción? | Cuándo | Tiempo |
|---|---|---|---|---|
| 0 | Prueba visual en las TV reales de 32" | No | Cuando quiera, antes de todo | 30–45 min |
| 1 | Preparación: pruebas, archivo del ensayo, ensayo, etiqueta y sus pruebas | No | El día de la activación, entre las 05:00 y las 23:00 | 45 min |
| 2 | Respaldo, la 0037 y sus comprobaciones | Sí (la base) | Café cerrado, desde las 19:30 | 15 min |
| 3 | Guardar el sitio de hoy y publicar | Sí (las páginas) | Seguido de la etapa 2 | 20 min |
| 4 | Configuración inicial en `pantallas.html` | Sí (sus ajustes) | Seguido de la etapa 3 | 20 min |
| 5 | Verificación en las TV reales con los datos reales: sigue o vuelve atrás | No | Seguido de la etapa 4 | 30 min |
| 6 | Vuelta atrás (solo si la necesita) | Sí | Antes de abrir el café | 10–20 min |

**Detenga y avíseme** si algo sale distinto de lo que dice la guía: copie el resultado (texto o captura) y no siga.

---

## Etapa 0 · Prueba visual en las TV reales, sin tocar producción (hecha el 2026-11-03: aprobada)

Antes de cambiar nada, mire la V2 en las dos TV de 32" del café con una página de prueba privada:
**https://claude.ai/artifact/HJDYiJ8PG285kUhwUo4Sib**

- Son las **dos páginas reales de la V2** (las mismas de esta versión, con una sola línea distinta: en vez de leer la
  base del café, contestan con una copia del menú tomada en la base de pruebas con la 0037). La letra, las columnas,
  las páginas, los tiempos, las cuatro ventanas y el aspecto de día y de noche son los de la V2.
- **No lee ni cambia nada de producción.** Las TV del café siguen con la versión publicada.
- Lo que no es real: las **fotos** (de muestra, con el nombre del producto) y los **precios** (los de la copia de
  pruebas; pueden no ser los de hoy). Sus fotos y precios se ven en la etapa 5.

**Cómo ponerla en la TV**
1. **Con una laptop y un cable HDMI (recomendado):** conecte la laptop a la TV, elija esa entrada en la TV, y que la TV
   sea la única pantalla de la laptop (o la principal) a su resolución normal. Abra el enlace en Chrome, en la TV.
2. **Con el navegador de la TV:** abra el enlace en la TV. Pide iniciar sesión en claude.ai; si prefiere no hacerlo en
   la TV, compártala con enlace desde el botón «Compartir» («Share») de la página (no contiene datos privados: solo el menú y fotos de
   muestra). Si la TV no pasa a pantalla completa, use la laptop: la letra se calcula para la pantalla entera.
3. Elija una prueba: pasa a pantalla completa. Para volver: **Esc** (o el botón «Volver» al mover el mouse). Pantalla
   completa de verdad quiere decir sin ninguna barra del navegador ni de claude.ai a la vista; en la TV, el modo de
   imagen sin recorte de bordes («Ajustar a pantalla», «Just scan» o «16:9»). Con una barra o con los bordes recortados,
   la letra y las páginas cambian.
4. **Al terminar, vuelva a poner cada TV en su página real** (`pantalla-menu?tv=menu-1` y `pantalla-promos?tv=promos-1`,
   `docs/INSTALACION-TV.md` §3) y, si inició sesión en claude.ai en la TV, ciérrela. La página de prueba tiene precios de
   una copia: no debe quedar a la vista de los clientes.
5. En la página de prueba, el cuadro de diagnóstico dice «Origen: base de datos …» y «Versión: __BUILD__»: es la copia de
   pruebas que lleva dentro, no la base del café, y la versión de una copia de desarrollo. Es normal.

**Qué mirar, de pie en el punto más lejano (unos 3 m)**

| Prueba (en la página) | Debe verse | Medido en desarrollo con la letra real |
|---|---|---|
| Pantalla A · «Recomendado: 12 productos» | 3 páginas que cambian cada 28 s; cada categoría con su título arriba; columnas parejas | 3 páginas, mayúscula 2,48 cm (mínimo 2,4) |
| Pantalla A · «Más corto: 9 productos» | 2 páginas | 2 páginas, 2,40 cm |
| Pantalla A · «Menú completo» | Muchas páginas: por eso se recomienda el resumido | 10 páginas |
| Pantalla A · con «Con el cuadro de diagnóstico» | Abajo a la derecha: las páginas, la mayúscula en cm con su mínimo, «Precios: al-dia» | — |
| Pantalla B · Desayuno, Almuerzo, Tarde, Cena | Cada zona cambia a su ritmo (Desayuno 14 · 16 · 18 · 20 s; la primera vez cada zona tarda un poco más según su lugar, unos 14, 20, 27 y 35 s, para que nunca cambien juntas), nunca un cuadro negro, nada encima de las fotos | — |
| Pantalla B · con «Con nombres y precios» | Nombre y precio se leen desde 3 m; en las zonas chicas se quita el inglés | — |

- **Legibilidad:** tres personas (una mayor de 60 años o con lentes) leen 5 nombres y 5 precios al azar sin error.
- **Con una regla en la TV:** una mayúscula (por ejemplo la «C» de «Capuchino») mide **unos 2,4 cm** (2,3 cm o más con
  la regla: la página calcula con la medida nominal de 32" y el panel real puede ser un poco menor; la medida exacta la
  dice el diagnóstico).
- Anote lo que no le convenza (TV, prueba, qué se ve). Se ajusta **antes** de activar; si todo está bien, siga con la
  etapa 1 el día que elija.

---

## Etapa 1 · Preparación (no toca producción)

1. **«Tests» en verde en la versión.** GitHub → **Actions** → **Tests** → la ejecución del último commit de la rama:
   ✅. Su código debe ser el que le di. (En la misma lista puede ver otra fila gris, «skipped», con el nombre del PR #1:
   es normal, no es una falla.)
2. **Subir `anonimizar.sql` de esta versión a `canopy-respaldos`, antes del ensayo** (como en E-38): el archivo
   `ops/backup/repositorio-respaldos/anonimizar.sql` de esta versión, en la raíz de `canopy-respaldos`, reemplazando el
   que está. Conoce las columnas de las pantallas (0036 y 0037). No hay registro de que el de la 0036 se haya subido: si
   `canopy-respaldos` todavía tiene uno anterior a las pantallas, el ensayo se detiene antes de copiar nada («anonimizar.sql
   no sabe si estas columnas guardan datos de personas…»), como está diseñado. Y **todo ensayo después de la 0037**
   (por ejemplo el de los descuentos, 0038) lo necesita.
3. **«Ensayo en pruebas» en verde.** `canopy-respaldos` → **Actions** → **Ensayo en pruebas** → **Run workflow**:
   - «Rama o etiqueta del repositorio de desarrollo a ensayar»: el código completo del commit que le di (o la rama);
   - destino `desechable`, vaciar `no`, reinicio `no` → **Run workflow**.
   - Unos 5 minutos. Verde quiere decir: copió producción, la anonimizó y aplicó **solo la 0037**. El resumen dice
     «the copy already had migrations 0000-0036 (production after the launch) …» y «unchanged: … original tables …», sin
     ninguna línea «DIFFERENCE:»; `timings.txt` en el resultado `ensayo-resultados-desechable` dice
     «0037_pantallas_v2 … ms».
4. **La etiqueta (el mismo día que va a publicar, antes de las 23:00).** No depende de producción, así que se hace antes
   de la ventana: GitHub → **Releases** → **Draft a new release** → **Choose a tag**: `vAAAA.MM.DD-1` con la fecha de hoy
   (si ya existe una de hoy, `-2`) → **Create new tag** → **Target**: la rama `claude/hanging-garden-coffee-proposal-1m8zd4`.
   Antes, compruebe que su último commit es el que le di. → **Publish release**. En **Tags**, la etiqueta debe mostrar
   ese mismo commit; si muestra otro, **no publique** y cree `-2` en el commit correcto (una etiqueta nunca se mueve).
   Desde ahora y hasta publicar, nadie sube nada a la rama.
5. **Pruebas sobre la etiqueta.** **Actions** → **Tests** → la ejecución con el nombre de la etiqueta → en verde. Tarda
   15 a 19 minutos. **No entre las 00:00 y las 05:00 de Costa Rica**: tres pruebas dependen de la hora y saldrían en
   rojo.

---

## Etapa 2 · Respaldo, la 0037 y sus comprobaciones (café cerrado)

**Condiciones:**
- **Después del cierre (19:00), desde las 19:30**, con la etapa 1 en verde (la etiqueta y sus pruebas incluidas). No de
  madrugada: el respaldo nocturno corre desde las 02:17 (GitHub lo atrasa a veces hasta las 7:30) y un respaldo en curso
  puede hacer fallar la pegada.
- **Caja:** en cada tableta el aviso de conexión dice «en línea» y, al tocarlo, «Todo lo que se tomó en este dispositivo
  está guardado en el sistema.». Si dice «guardando N…», «N sin guardar todavía», «sin conexión · N en este
  dispositivo» o «no guardado en este dispositivo», espere a que se vacíe. «Hoy en el mostrador» cerrado y ningún
  formulario a medio escribir en las pantallas del personal. La cocina sin pedidos.
- **Nadie usa ningún aparato entre la foto de antes (paso 2) y la de después (paso 5)**: ni ventas, ni marcas en el
  Reloj, ni el PIN de las áreas del dueño, ni el Gestor del menú. Deje cada aparato en la Caja o en la Cocina: con el
  ingreso compartido, el Reloj, Inicio, el Menú, Ventas e Inventario cierran la sesión solos a los 30 minutos, y eso
  también cambia las huellas. Haga los pasos 2 a 5 seguidos.
- Los archivos que se pegan son los de esta versión: en GitHub, en la rama `claude/hanging-garden-coffee-proposal-1m8zd4`,
  abra cada uno con el botón **Raw** y copie **todo** cada vez.

1. **Respaldo.** `canopy-respaldos` → **Actions** → **Respaldo nocturno** → **Run workflow** → **Run workflow**. Unos 2
   minutos, en verde; el resumen dice «restauración: passed».
2. **La foto de antes.** Supabase → **SQL Editor** → **New query** → pegar `supabase/tools/production-snapshot.sql` →
   **Run**. Guarde el resultado (copiar todo a un archivo «snapshot-antes»). Con el archivo de esta versión debe decir:
   `migrations_applied` termina en `36`; en `schema`, `functions_by_version` con `"0036": 13` y sin `"0037"`,
   `functions_changed` = `[]`, `functions_unknown` = `[]`.
3. **La migración.** **New query** → pegar **todo** `supabase/migrations/0037_pantallas_v2.sql`. Antes de **Run**, baje al
   final del texto pegado: las dos últimas líneas son `select canopy.migration_end(37, 'pantallas_v2');` y
   `notify pgrst, 'reload schema';` (si no están, el texto quedó cortado: borre y pegue de nuevo). → **Run** → debe decir
   **Success** (sin filas). Una sola vez.
   - «La migración 37 (pantallas_v2) ya estaba aplicada: no se cambió nada.» → ya estaba; no pasó nada; siga con el paso 4.
   - «Falta aplicar antes la migración 36…» → **deténgase y avíseme** (no pasó nada).
   - «canceling statement due to lock timeout» → no se aplicó nada: algo tenía tomadas esas tablas más de 8 segundos,
     casi siempre un respaldo en curso. Mire en `canopy-respaldos` → **Actions** que ningún respaldo ni ensayo esté
     corriendo, espere a que termine y pegue de nuevo.
4. **`release-check.sql`.** **New query** → pegar `supabase/tools/release-check.sql` → **Run**. Debe decir:
   - `migrations_missing` = `[]` (la serie llega a 37) y `functions_missing` = `[]`. Si dice `[37]`, la pegada quedó
     incompleta: **deténgase y avíseme**;
   - `anon_can_run` = `["canopy_schema_version", "order_status", "pantalla_datos", "place_room_order", "room_lookup"]`
     (igual que antes: la 0037 no da nada nuevo a un visitante);
   - `storage_policies_missing` = `[]`, `tables_without_rls` = `[]`, en `ledger` `unbalanced` = `0`.
5. **La foto de después.** **New query** → `production-snapshot.sql` otra vez → **Run**. Debe decir:
   - `migrations_applied` termina en `37`;
   - en `schema`: `functions_by_version` con `"0036": 7` y `"0037": 8` (la 0037 vuelve a crear seis funciones de la
     0036 y agrega dos), sin la clave `"?"`; `functions_changed` = `[]`; `functions_unknown` = `[]`;
     `tables_missing` = `[]`; `functions_total` = el de antes **+ 2**;
   - `data_fingerprint` y `security` → `anon_can_run` **idénticos** a los de «snapshot-antes» (la 0037 no cambia
     ninguna fila ni ningún permiso existente). Si una tabla de `data_fingerprint` cambió, **no vuelva a pegar la 0037**:
     deténgase y avíseme con las dos fotos (casi siempre es un aparato que se usó en medio).

Hasta publicar (etapa 3), **las TV siguen igual**: las páginas v1 ignoran los campos nuevos y nunca muestran una
composición (lo prueban las pruebas automáticas, «Tests», en cada ejecución: las páginas publicadas hoy sobre una copia
con la 0037 y una composición guardada).

---

## Etapa 3 · Guardar el sitio de hoy y publicar

1. **Guardar el sitio de hoy (la vuelta atrás exacta).** GitHub → **Releases** → **Draft a new release** → **Choose a
   tag**: `sitio-AAAA-MM-DD` con la **fecha de hoy** → **Create new tag** → **Target**: la rama **gh-pages** → título
   «Sitio con las pantallas v1» → marque **Set as a pre-release** → **Publish release**. En **Tags** debe mostrar el
   commit `7d87c81` («Publish website v2026.11.02-1 …»). Si muestra otro (por ejemplo porque el Target quedó en otra
   rama): **Releases** → esa versión → **Delete**, y **Tags** → esa etiqueta → **Delete tag**; después créela otra vez con
   Target **gh-pages**. (Esta etiqueta guarda una copia del sitio, no es una versión: borrarla no toca nada publicado.)
   - **No use `sitio-2026-11-02`**: ya existe y es el sitio de **antes** de las pantallas (`v2026.10.26-1`).
     Restaurarlo quitaría las dos pantallas (las TV mostrarían el error 404 de GitHub).
2. **Publicar** (con la etiqueta de la etapa 1, sus pruebas en verde). **Actions** → **Publish website (PRODUCTION · manual only)** → **Run workflow**:
   - **Use workflow from** → **Tags** → la etiqueta nueva;
   - en «Escriba PUBLICAR para publicar esta versión en el sitio real del café»: `PUBLICAR`;
   - «Solo para volver a un sitio guardado (sitio-AAAA-MM-DD). Vacío = publicar esta versión»: **vacío**;
   - **Run workflow**. Tarda un par de minutos. (Si GitHub pide aprobar el despliegue, apruébelo.)
3. **Comprobar la versión.** Abra `https://hanginggardencafe.com/version.json?t=` seguido de la hora (por ejemplo
   `?t=2015`, un número nuevo cada vez): debe decir `"version"` = la etiqueta, `"build"` = los 12 primeros caracteres
   del commit y `"sha"` = el commit. Si todavía dice `v2026.11.02-1`, espere (la red de GitHub tarda hasta 10 minutos);
   **no vuelva a publicar**.
4. **Los aparatos se actualizan solos.** Las TV cargan la V2 solas en unos 5 minutos (sin aviso a los clientes). La
   Caja dice «actualización lista» y se recarga entre ventas; las demás pantallas muestran «Actualizar ahora». Si una
   TV no cambia en 15 minutos, recárguela a mano (o apáguela y enciéndala).
5. **Comprobaciones rápidas:**
   - la Caja, la Cocina y la TV actual (`tv.html`) cargan como siempre;
   - `https://hanginggardencafe.com/pantalla-menu?tv=menu-1&diag=1`: el cuadro dice «Versión» con el build nuevo;
   - `https://hanginggardencafe.com/pantallas` abre el panel: pide el ingreso si no ha ingresado en ese aparato y, con la
     cuenta del café, el PIN del dueño; con su propia cuenta pide el código del teléfono y ningún PIN.

---

## Etapa 4 · Configuración inicial (en `pantallas.html`, con el PIN del dueño)

Nada de esto se aplica solo. Cada TV vuelve a dibujarse con lo guardado en menos de 30 segundos.

1. Abra `https://hanginggardencafe.com/pantallas`:
   - con la **cuenta del café**: abra con el **PIN del dueño** (el de un encargado no alcanza: «Solo el dueño puede
     cambiar las pantallas…»). El PIN queda abierto 15 minutos: **guarde cada tarjeta antes** (lo que no se guardó se
     pierde al cerrarse);
   - con **su propia cuenta** y el código del teléfono: no pide PIN; la página cierra la sesión sola tras 30 minutos sin
     tocarla.
2. Pestaña **Pantallas** → la tarjeta **Pantalla A · menú** (`menu-1`):

   | Campo | Valor inicial | Por qué |
   |---|---|---|
   | Tamaño (24 a 110 pulgadas) | **32** | Las filas nacen con 55": sin esto la letra se calcula para otra TV |
   | Distancia de lectura (1 a 15 metros) | **3** | El cliente más lejano que debe leer |
   | Posición | Horizontal | Salvo que la TV esté vertical |
   | Escala de letra (70 a 160 %) | 100 | A 3 m: mínimo 2,40 cm de mayúscula, meta 3 cm. Subirla sube también el mínimo y da más páginas (120 % → mínimo 2,88 cm) |
   | Segundos por página (15 a 60 segundos) | 28 | 3 páginas = una vuelta de 84 s |
   | Colores | Automáticos: claros de día, oscuros de noche | |
   | Productos agotados | Ocultarlos | |
   | Categorías que muestra | ninguna marcada (= todas) | Las decide «Productos que muestra»: una categoría sin producto marcado no sale |
   | **Productos que muestra** | **sus 12 productos destacados** (los que usted elija; el ejemplo medido: 5 cafés, 2 batidos, 2 sándwiches, 2 de repostería y 1 favorito costarricense) | Medido con la letra de la TV: ese ejemplo = 3 páginas, mayúscula 2,48 cm (mínimo 2,40). Otra mezcla puede dar 2, 3 o 4 páginas: la cuenta la dicen la vista previa y el diagnóstico en la TV; con 4 páginas o «NO CABE», quite 1 o 2 productos. Una categoría con solo 2 productos de nombre largo se parte en dos columnas: mejor 3 o más. El menú QR sigue con todos |
   | Distribución | Automática: una sola pantalla si la letra alcanza; si no, páginas | Nunca baja de la letra mínima |
   | Densidad | **Compacta**: más líneas, menos aire | |
   | Inglés | **No se muestra: solo español** | Con el inglés debajo, los mismos 12 productos dan 4 páginas |
   | Promociones | No: el menú nunca se interrumpe | Para empezar. Si después intercala, «Cada promoción dura» 20 s o más con composiciones |
   | Encendida desde … hasta | **vacío por ahora** (= siempre encendida) | Fuera del horario la TV queda negra, también la vista previa: esta noche la necesita encendida. Ponga el horario (por ejemplo 06:00 a 19:00) al terminar la etapa 5 |
   | Activa | marcada | |

   «Productos que muestra» es un bloque que se abre con un toque («Productos que muestra: todos» o «N elegidos»): un
   título por categoría con el nombre del Gestor (por ejemplo «Coffee», «Pastries & Cake») y una casilla por producto.
   **Guardar** → «Guardado». Después de guardar, la tarjeta sigue diciendo «Compacta» y «No se muestra: solo español»:
   esa es la prueba de que la 0037 está activa (sin ella volverían a «Normal» y «Debajo del español»).
   Luego **Vista previa** (muestra lo guardado; fuera del horario de la TV queda negra): debajo dice «En la TV: …» con
   las páginas y la letra, o «NO CABE a la letra mínima…» (entonces quite productos o categorías). La vista previa corre
   en su aparato; la cuenta real de la TV la da el diagnóstico en la TV (etapa 5).
3. La tarjeta **Pantalla B · promociones** (`promos-1`): **Tamaño 32** y **Distancia de lectura 3** (también nace con
   55": los nombres, los precios, el QR y la «Vista previa en la TV» del editor se calculan con ellos), Posición
   Horizontal, Escala 100, Colores automáticos, «Segundos por diapositiva» 10 (para las diapositivas de producto, marca e
   invitación; las composiciones tienen sus propios tiempos), «Encendida desde … hasta» **vacío por ahora** y **Activa**
   → **Guardar**.
4. Pestaña **Diapositivas** → **Programación sugerida**. Debe decir «Se crearon en pausa: Desayuno (06:00–10:00),
   Almuerzo (10:00–13:00), Tarde (13:00–17:00), Cena (17:00–19:00). Revíselas …». Son cuatro composiciones **pausadas**,
   todos los días por un año, en todas las TV de promociones, **sin nombres ni precios**, cada zona con sus segundos: Desayuno «Centro en dos» 14/16/18/20 s; Almuerzo
   «Grande a la izquierda» 12/15/18; Tarde «Dos mitades» 12/15; Cena «Una zona» 10. Toma los productos del menú por el
   nombre de su categoría (sin mirar si tienen foto). Si la pide otra vez, no repite las que ya existen con el mismo
   nombre. **Sobre una composición la TV no muestra nada encima de las fotos**: ni el nombre de la franja (Desayuno,
   Almuerzo, Tarde, Cena) ni la línea de la marca (su ajuste final del 2026-11-03). Ese nombre, la «Línea corta de
   arriba» del editor, queda solo como el nombre de la composición en el panel; los horarios siguen cambiando las
   composiciones solos.
5. En cada composición → **Editar**:
   - cada zona: los productos y sus fotos (la del menú, o **Cambiar foto** para subir otra en esa posición; **Foto del
     menú** vuelve a la del producto), el encuadre (un toque o arrastre sobre la foto) y el «Tamaño» (el zoom);
   - «Nombres y precios del menú (solo en las entradas con producto; siempre al día)»: apagado al empezar; lo puede
     encender por zona;
   - «Cuándo sale»: **Desde (obligatorio)** y **Hasta (obligatorio)**, **Días**, **De las … a las** (hora de Costa Rica);
   - «En qué TV»: ninguna marcada = todas las de promociones;
   - **Vista previa en la TV** (la página real, sin guardar) → **Guardar**.
   Si la lista dice «NADA QUE MOSTRAR: suba fotos o active nombres y precios» en una zona, esos productos no tienen foto
   en el Gestor de menú: súbales una (JPEG de 1 MB o menos), elija otra en el editor o encienda los nombres y precios.
6. **Reanudar** en las composiciones que quiera en pantalla. Las diapositivas de la v1 siguen como estaban: las que
   estén vigentes para la Pantalla B (sin TV asignada o asignadas a ella) se turnan con la composición de la franja
   (cada una los «Segundos por diapositiva» de la TV, 10 s; la composición, su «Permanencia», 60 s si está vacía). Si
   prefiere solo las composiciones, pause esas diapositivas.
7. **Hoy en pantalla**: qué sale ahora y más tarde en cada TV. **Registro de cambios**: cada cambio con su nombre.

---

## Etapa 5 · Verificación en las TV reales con los datos reales: sigue o vuelve atrás

Con el café todavía cerrado, desde el punto más lejano:

1. **Pantalla A** (la del menú), con sus precios reales:
   - las mismas comprobaciones de la etapa 0: 5 nombres y 5 precios al azar, la mayúscula de unos 2,4 cm con una regla
     (2,3 cm o más), cada categoría con su título arriba, las páginas cambian cada 28 s;
   - con el diagnóstico (agregue `&diag=1` a la dirección en la TV, `docs/INSTALACION-TV.md` §4; al cambiar la dirección
     la página se recarga y sale de pantalla completa: presione **OK** otra vez antes de leer el cuadro, y otra vez al
     volver a la dirección sin `&diag=1`): «TV: menu-1 · 32" ·
     3 m …», «productos elegidos (12)», «Letra: mayúscula 2.48 cm (mínimo 2.40, meta 3.00)» o parecido (con punto
     decimal), «Páginas: 3 …» (con 3 páginas agrega «MÁS DE 2: menos productos o TV más grande»: es un aviso, no un
     error), «Precios: al-dia» y la «Versión» nueva. **Deje `&diag=1` puesto para la prueba siguiente**;
   - **Agotado:** en el Gestor del menú toque el botón «Disponible» de uno de los productos elegidos: pasa a «Agotado» y
     sale de la Pantalla A en menos de 1 minuto (el diagnóstico dice entonces «productos elegidos (12, 11 en
     pantalla)» y puede tener una página menos: es normal). Tóquelo otra vez: vuelve. **Ahora quite `&diag=1`** de la
     dirección y presione **OK**: el cuadro no debe quedar a la vista de los clientes.
2. **Pantalla B** (las ventanas):
   - de noche ninguna de las cuatro composiciones está en su horario (06:00–19:00): la TV muestra la marca o las
     diapositivas de la v1 vigentes. **Para verlas esta noche:** en una composición → **Editar** → «a las» más tarde
     (por ejemplo Cena de las 17:00 a las 23:59) → **Guardar** (y **Reanudar** si está pausada). Mírela en la TV (menos de
     30 s); al terminar vuelva «a las» a 19:00 → **Guardar**. O mírelas mañana desde las 06:00;
   - la TV debe estar sin horario («Encendida desde … hasta» vacío, etapa 4): con horario, de noche queda negra;
   - **qué mirar:** sus fotos llenan cada zona sin deformarse y con el plato visible (si no, el encuadre y el «Tamaño»
     en el editor; en «Centro en dos» las zonas de los lados son verticales: fotos 2:3); cada zona cambia a su ritmo,
     nunca dos a la vez al empezar; nunca un cuadro negro; **ningún título de franja ni línea de la marca encima de
     las fotos**; una zona con la hoja y el nombre del café no tiene qué mostrar (productos sin foto o agotados); con
     nombres y precios, se leen desde 3 m.
3. **Decida:**
   - todo bien → ponga el horario de cada TV si lo quiere (por ejemplo 06:00 a 19:00) → **Guardar**, anótelo en el
     registro y abra el café como siempre;
   - algo de ajustes (letra, productos, fotos, tiempos) → cámbielo en `pantallas.html` y mire otra vez;
   - la V2 no le convence o algo falla → la etapa 6, **antes de abrir el café**.
4. Mañana, en la apertura: a las 06:00 debe salir el Desayuno en la Pantalla B (si lo reanudó).

---

## Etapa 6 · Vuelta atrás

| Qué pasa | Qué hacer |
|---|---|
| Una TV se ve mal pero el resto está bien | Ajústela en `pantallas.html`, o desmarque **Activa** en su tarjeta (queda en negro en menos de 1 minuto) |
| Una composición se ve mal | **Pausar** en Diapositivas (sale de la TV en menos de 30 s) |
| La V2 no le convence o sus páginas fallan | **6.1** (las páginas vuelven a la v1; la base se queda con la 0037) |
| Falla una función de la 0037 (por ejemplo el panel no guarda una TV con un error del servidor) | **6.1** y después **6.2**, y avíseme |
| La Caja, la Cocina o la TV actual no cargan después de publicar | **6.1** de inmediato y avíseme (esas páginas no cambian; sería otra cosa) |

### 6.1 Las páginas vuelven a la v1 (la base se queda en la 0037)

Si la Caja, la Cocina o la TV actual no cargan, o el panel no abre, **vaya directo al paso 3**: los pasos 1 y 2 se
pueden hacer después, también desde el panel v1 (que tiene **Pausar** y «Categorías que muestra»).

1. En `pantallas.html` → **Diapositivas** → en cada composición **Pausar**. **Nunca «Retirar»**: retirar no tiene vuelta.
   (La TV v1 nunca muestra una composición, pero el panel v1 la listaría como «(sin título)» y «En pantalla ahora».)
2. Recomendado: la tarjeta **Pantalla A · menú** → «Categorías que muestra»: marque 2 o 3 (con el nombre del Gestor, por
   ejemplo «Coffee» y «Pastries & Cake») → **Guardar**. La v1 no conoce «Productos que muestra», la densidad ni el inglés:
   a 32" y 3 m mostraría todo el menú con el inglés debajo, en muchas páginas.
3. **Actions** → **Publish website (PRODUCTION · manual only)** → **Run workflow** → **Use workflow from** → **Tags** →
   `v2026.11.02-1` → `PUBLICAR` en la primera casilla → la segunda **vacía** → **Run workflow**.
   - Solo si esa publicación falla (por ejemplo no puede bajar las fotos y el video del sitio): la copia exacta del sitio
     guardado en la etapa 3, paso 1. **Use workflow from** → **Tags** → la etiqueta de la V2 (la de hoy), `PUBLICAR` en la
     primera casilla y en la segunda `sitio-AAAA-MM-DD` (la fecha de la etapa 3). **Revise que la segunda casilla no
     quede vacía**: vacía, publicaría la V2 otra vez. **Nunca `sitio-2026-11-02`** (quitaría las pantallas).
4. `version.json?t=…` dice `"version": "v2026.11.02-1"` y `"build": "3273743dcbe0"` (con la copia exacta, el
   `version.json` guardado de esa versión).
5. Las TV vuelven solas a la v1 en unos 5 minutos; si una no cambia en 15, recárguela a mano.
6. La base se queda en la 0037 y las páginas v1 funcionan con ella: lo prueban las pruebas automáticas («Tests») en
   cada ejecución (las páginas publicadas hoy, pantallas incluidas, sobre una copia con la 0037 y una composición
   guardada). Lo guardado con la V2 (ajustes, composiciones, registro) queda. Si vuelve a publicar la V2 más adelante,
   vuelven los ajustes y las composiciones, pero las composiciones siguen **pausadas** (en Diapositivas, **Reanudar** en
   las que quiera) y las categorías que marcó en el paso 2 siguen marcadas: desmárquelas, o la V2 ocultaría los productos
   elegidos de las demás categorías.

### 6.2 La base (solo por una falla de una función de la 0037, y después de 6.1)

Nunca revierta solo la base con las páginas V2 publicadas: la Pantalla A dejaría de recibir el menú resumido, la
densidad y el inglés y mostraría todo el menú con el inglés debajo (a 32" y 3 m, unas 14 páginas con palabras cortadas).
Por eso primero 6.1.

1. **Respaldo nocturno** → **Run workflow** → en verde.
2. Los archivos de este paso y de los siguientes son los de **la etiqueta de la V2** (la que creó en la etapa 1, paso 4):
   GitHub → **Tags** → esa etiqueta → el archivo → **Raw**. No los de la rama (después de publicar puede tener cambios
   nuevos) ni los de `v2026.11.02-1`: esos no conocen la 0037 y sus resultados no coincidirían.
   **SQL Editor** → **New query** → pegar **todo** `supabase/tools/reversion-0037.sql`. Antes de **Run**, baje al final del
   texto pegado: las dos últimas líneas son `delete from canopy.migrations where version = 37;` y
   `notify pgrst, 'reload schema';` (si no están, el texto quedó cortado: borre y pegue de nuevo). → **Run** → **Success**
   (sin filas).
   - «La migración 0037 no está aplicada: no hay nada que revertir. No se cambió nada.» → ya estaba revertida.
   - «Hay una migración posterior a la 0037 aplicada (…): revierta esa primero. No se cambió nada.» → por ejemplo,
     después de aplicar los descuentos (0038): **avíseme**; primero se revierte esa.
3. `release-check.sql`: `migrations_missing` = `[37]`, `functions_missing` = `[]`, `anon_can_run` = las mismas cinco
   de la etapa 2, `storage_policies_missing` = `[]`.
4. `production-snapshot.sql`: `migrations_applied` termina en `36`; `functions_by_version` con `"0036": 13` y
   `"0037": 1` (queda `_screen_template_places`, que usa una regla de las diapositivas: es normal); `functions_changed` =
   `[]`; `functions_unknown` = `[]`; `functions_total` = el de «snapshot-antes» **+ 1**. (Comprobado el 2026-11-03 en una
   copia: después de la 0037 y después de esta reversión, con estos mismos archivos.)
5. Qué queda: las columnas nuevas y todas las filas (los ajustes de la V2, las composiciones, el registro). Al volver a
   aplicar la 0037 más adelante, todo aparece como estaba. Mientras tanto el panel V2 no puede guardar composiciones.
6. **No pegue `reversion-0036.sql`** por un problema de la V2: quitaría también las pantallas v1.

### 6.3 Deténgase y avíseme si

- «Tests» queda en rojo sobre la etiqueta;
- `version.json` muestra otro commit pasados 10 minutos;
- la Caja, la Cocina o la TV actual no cargan;
- una TV muestra un precio distinto al del Gestor del menú;
- cualquier comprobación de esta guía dice otra cosa.

---

## Registro

| Fecha y hora | Etapa y paso | Resultado (o lo que se vio) |
|---|---|---|
| | | |
