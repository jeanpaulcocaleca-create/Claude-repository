# Activación de los PIN más seguros (D-052 + D-053, migración 0033) · E-36

**Estado:** preparación aprobada por el dueño el 2026-10-25; **nada aplicado ni publicado**. El simulacro de reversión
que el dueño pidió antes de publicar está hecho (sección 3) sobre una copia de pruebas con datos representativos, no
sobre producción. La fecha de la ventana la fija el dueño.

Los pasos en producción los hace **solo el dueño** (Jean Paul): crear la etiqueta, usar el SQL Editor y publicar. Claude
no publica, no crea etiquetas `v*` y no toca la base de producción (CLAUDE.md); sí acompaña: lee resultados, compara
celdas, analiza errores y prepara correcciones.

- **Versión a publicar:** el commit de la rama `claude/hanging-garden-coffee-proposal-1m8zd4` que se etiquete, con
  «Tests» en verde **sobre la etiqueta**. Sus `website/` y `supabase/` deben ser idénticos a `3d80f30` (D-052 + D-053,
  «Tests» #151 en verde); los commits posteriores cumplen eso (solo cambian `docs/` y `tests/`).
  - La etiqueta `v2026.10.25-1` (= `e03071e`) **no se publica**: su «Tests» #157 salió rojo por una condición de carrera
    de una prueba de navegador (D-056; el mismo flujo de pruebas había dado verde a ese commit en #155). La etiqueta se queda
    donde está, sin borrar ni mover; la ventana usa una etiqueta nueva sobre el commit con la prueba corregida.
  - Base de datos: `supabase/migrations/0033_pines_seguros.sql`. Solo funciones y una columna nueva; ningún registro
    cambia.
  - Páginas: D-052 (las casillas de PIN) y D-053, en `access.js`, `keypad.js`, `lang.js`, `pos.html`, `inventory.html`,
    `sales.html` y `time.html`.
- **No incluye:** la transición de tabletas (E-05, sigue detenida), el código del teléfono (E-06) ni ningún cambio de
  cuentas, PIN o permisos existentes.
- **Punto de partida y de regreso:** la base en la migración 0032 y el sitio en `v2026.10.21-1` (commit `c1d9fb5`,
  `gh-pages` `0ad8c88`).

Monteverde está en UTC−6 todo el año: a las 19:45 del día D en Monteverde son las 01:45 UTC del día D+1. La etiqueta
lleva la fecha D; los registros en UTC llevan D+1. Para las horas use la que da la base (paso 4.2.4), no el reloj de la
computadora (en D-052 estaba 2 horas adelantado) ni el de GitHub.

## Qué se activa

| Pieza | Qué hace | Archivo |
|---|---|---|
| 0033 · PIN más seguros (D-053) | El editor del equipo ya no deja averiguar PIN (toda otra negativa va antes; máximo 10 PIN por hora y cuenta, también si se envían juntos; cada «ya lo usa alguien» queda anotado); un PIN vacío no cuenta como intento; cada bloqueo queda anotado y otro encargado lo quita con su PIN (2 veces al día por persona; el de alguien con puesto de dueño, solo con el código del teléfono); volver a activar a alguien pide un PIN nuevo; cada apertura de las áreas de dueño queda atada al inicio de sesión que la hizo (otro aparato de la misma cuenta no la usa, tampoco para las fotos del menú); cerrar sesión la termina en el servidor | `supabase/migrations/0033_pines_seguros.sql` |
| Páginas D-052 | Las casillas de PIN no son casillas de contraseña: se ven como puntos, el navegador no ofrece guardarlas y un PIN que rellene el navegador se borra y no se envía; solo se envía un PIN escrito | `website/keypad.js`, `access.js`, las páginas con PIN |
| Páginas D-053 | «Cerrar sesión» termina la apertura en el servidor antes de salir; «Equipo» avisa «Ese PIN ya lo usa otra persona. Elija otro.», muestra los bloqueos en la bitácora y ofrece «Quitar el bloqueo del PIN» con el PIN de otro encargado | `website/time.html`, `access.js`, `lang.js` |
| Reversión | Deja las seis funciones byte a byte como en la 0032, quita las tres nuevas y la fila 33 del registro; conserva la columna y todas las anotaciones | `supabase/tools/reversion-0033.sql` |

## 1. Decisiones del dueño (2026-10-25)

1. **Ventana:** después del cierre del café, con la caja cerrada. El café abre de 6:00 a 19:00; propuesta: empezar a
   las 19:45 y reservar 90 minutos. No antes de las 6:00: el «Respaldo nocturno» automático está programado a las 2:17
   y GitHub lo ha retrasado hasta las 7:30, y un respaldo en curso hace fallar el pegado de la 0033 (sin cambiar nada).
2. **Presentes:** Jean Paul (GitHub y Supabase) y **un** encargado con su PIN. Consecuencias:
   - la prueba de la foto (4.2.6) y las pruebas B, E, F y G las hace ese mismo encargado con su PIN; su cuenta de intentos
     debe estar en 0;
   - la prueba D (un miembro del equipo que no sea encargado) se hace **al día siguiente**;
   - esa noche no hay «otro encargado» para «Quitar el bloqueo del PIN»: si el PIN del encargado se bloquea durante las
     pruebas, se esperan 10 minutos (sección 6). Por eso cada PIN se escribe con calma y una sola vez.
3. **Simulacro de reversión antes de publicar:** hecho el 2026-10-25 sobre una copia de pruebas con datos
   representativos (sección 3). Opcional, si el dueño quiere además la versión con datos reales en su Mac: sección 3.5.
4. **Copia guardada del sitio actual:** sí (paso 4.1.3).
5. **Este procedimiento** queda en `docs/ACTIVACION-PINES.md`, con el estado de E-36 corregido en `docs/DEPENDENCIES.md`
   (commit solo de documentos, autorizado; el PR #1 no se fusiona). La etiqueta va sobre ese commit.
6. **Si falla la prueba de la foto del menú (4.2.6): detener el procedimiento y diagnosticar** antes de decidir si se
   sigue o se revierte. Mientras se diagnostica, la base queda en 0033 con las páginas de hoy: estado probado (8 de 8
   en el simulacro con la publicada `0ad8c88`; CI prueba la anterior, `2ade5f6`, idéntica salvo la marca de build), el
   café puede abrir así al día siguiente.

Además, antes de la ventana:
- **Foto para la prueba:** la foto actual de un producto, para que el menú público no cambie. En la misma tableta que
  hará 4.2.6: abrir `https://hanginggardencafe.com/m`, mantener el dedo sobre la foto del producto → «Guardar en Fotos»
  (iPad) o «Descargar imagen», comprobar que quedó guardada y anotar el producto.
- **Lista de aparatos:** cada aparato, su navegador y las páginas que usa (Caja del frente; iPad, Safari; cocina; Reloj;
  TV). Cada aparato con la Caja guarda su propia cola de ventas sin conexión.

## 2. Compatibilidad entre páginas y base, y la secuencia segura de recuperación

Las dos capas se publican y se revierten por separado, y **cualquier combinación funciona**. Probado el 2026-10-25 en
un navegador real sobre la copia de pruebas, con las páginas publicadas hoy (`gh-pages` `0ad8c88`, `v2026.10.21-1`) y
las nuevas (`website/` en `3d80f30`):

| Páginas \ Base | 0032 (hoy) | 0033 | 0033 revertida |
|---|---|---|---|
| Publicadas hoy (`v2026.10.21-1`) | producción hoy | 8 de 8 (`tests/rehearsal/live-pages.sh` con `LIVE_PAGES_SHA` = `0ad8c88`, la publicada; CI prueba la anterior, `2ade5f6` de `v2026.10.20-1`, cuyas páginas del personal solo difieren en la marca de build) | 8 de 8 |
| Nuevas (D-052 + D-053) | igual que «revertida»: la estructura solo difiere en una columna sin uso | 149 de 149 («Tests» #151) | toda la batería de navegador (sección 3.3): funciona todo salvo lo que la 0033 trae, con mensaje y sin errores |

Con las páginas de hoy sobre la 0033 hay tres diferencias, todas inocuas: el PIN número 11 en una hora muestra «No se
pudo guardar»; volver a activar a alguien sin PIN muestra «Una persona nueva necesita un PIN»; la bitácora muestra los
códigos `pin_locked`, `pin_in_use` y `pin_lock_cleared` sin traducir. Con las páginas nuevas sobre la base revertida:
«Quitar el bloqueo del PIN» contesta «Quitar un bloqueo de PIN necesita la última actualización de la base de datos.
Consulte al dueño.» y «Cerrar sesión» sigue terminando la apertura del aparato (la función de antes de la 0033, la de
`supabase/manager-mode.sql`); nada más cambia.

**Transiciones con tabletas abiertas** (siete pruebas, `scratchpad` del simulacro; cada venta quedó guardada una sola
vez, con sus líneas):

| Situación | Resultado |
|---|---|
| **La noche de E-36 en su orden:** Caja de hoy abierta sobre 0032, una venta sin conexión esperando en la tableta; se aplica la 0033 debajo; se publican las páginas nuevas; vuelve la conexión | La venta sube con sus líneas a la 0033; la tableta **no** se recarga mientras tenga ventas por subir; después se recarga sola a las páginas nuevas y vende |
| **Volver a las páginas de hoy** con una venta sin conexión esperando en las páginas nuevas | La venta sube por las páginas nuevas; la tableta se recarga a las de hoy entre ventas y sigue vendiendo sobre la 0033 |
| Lo mismo, pero la tableta se cierra y se vuelve a abrir **a mano** todavía sin conexión | Las páginas de hoy leen la cola que dejaron las nuevas (mismo formato) y la suben al volver la conexión |
| **Revertir la 0033** debajo de las páginas nuevas, con una venta sin conexión esperando | La venta sube; la apertura hecha bajo la 0033 sigue abriendo (nadie vuelve a escribir el PIN); el reloj marca; una anulación con PIN funciona; «Cerrar sesión» termina la apertura; «Quitar el bloqueo del PIN» explica; las únicas llamadas rechazadas son `access_lock_all` y `pin_lock_clear` (dos de las tres funciones que la reversión quita; la tercera, `_jwt_session`, es interna y ninguna página la llama) |
| **Las dos reversiones juntas** con una venta esperando | La venta sube; las páginas de hoy venden y marcan sobre la base revertida |
| **Una venta a medias** cuando cambian las páginas | La tableta nunca se recarga con productos en el ticket: muestra «actualización lista», cobra la venta y después se recarga |
| **Aperturas (PIN de encargado)** al cambiar de páginas | Hecha en las páginas nuevas, sigue abierta en las de hoy. Hecha en las páginas de hoy, las nuevas **piden el PIN otra vez** (D-052: las nuevas olvidan una apertura que no quedó firmada por su inicio de sesión); la fila del servidor queda hasta que vence (15 min) o la cuenta cierra sesión, y no abre nada en otro aparato |

**Reglas que hacen segura la recuperación:**

1. **Nunca** restaurar un respaldo encima de producción, borrar registros ni repetir una venta. Una venta cobrada que
   todavía no subió vive **solo** en la cola de su tableta (`localStorage`): no cerrar la pestaña de la Caja a la
   fuerza para «limpiar», no borrar datos del sitio en el navegador, no cambiar de navegador en ese aparato.
2. **La base y las páginas se recuperan por separado**, en el orden que convenga, con el café abierto si hace falta:
   - **Páginas:** «Publish website (PRODUCTION · manual only)» desde `v2026.10.21-1` (o desde la etiqueta nueva con
     «restaurar» = la copia `sitio-…` de 4.1.3). Toma de 2 a 10 minutos. Las tabletas se recargan solas **entre
     ventas y con la cola vacía**; recargar a mano solo cuando el chip diga «en línea» y no haya ticket. Comprobar en
     `version.json` que `build` es `c1d9fb5099ad` (con la copia `sitio-…`, la versión que esa copia muestre).
   - **Base:** `reversion-0033.sql`, un pegado de segundos (42–47 ms en el simulacro). Se niega si la 0033 no está
     aplicada, si se pega dos veces o si hubiera una migración posterior, y en esos casos no cambia nada. No necesita
     que los aparatos se detengan (en el simulacro corrió con una venta en curso y 133 comprobaciones de PIN
     simultáneas, sin un error), pero se hace fuera del horario salvo urgencia.
3. **Comprobar después:** `release-check.sql` (revertida: `migrations_missing` = `[33]`, `functions_missing` =
   `["access_lock_all", "pin_lock_clear"]`; 0033: `[]` y `[]`), `version.json`, en cada Caja el chip «en línea» y, al
   tocarlo, «Todo lo que se tomó en este dispositivo está guardado en el sistema.», y Ventas del día contra los tickets.
4. Las dos reversiones juntas devuelven el funcionamiento de hoy (0032 + `v2026.10.21-1`). Quedan, sin uso ni efecto:
   la columna `session_id`, las anotaciones nuevas de la bitácora y la foto de la prueba.

## 3. Simulacro de reversión (2026-10-25)

Hecho en el entorno de pruebas de Claude, no en producción ni con datos reales: la copia «producción como está hoy» de
`tests/rehearsal/run.sh` (el esquema histórico más la deriva real de `audit_menu`, unos 4 meses de historia: 14 534
ventas, 38 280 líneas, 60 548 movimientos de inventario, 482 turnos, 7 personas), con las migraciones 0000–0032
aplicadas como las aplica el SQL Editor (cuenta no superusuaria `rehearsal_editor`, una transacción por archivo, 3,8 s
en total) y `operator_mode` = `record` como en producción.

**3.1 Base de datos** (`scratchpad/sim/run.sh`; cada paso con `production-snapshot.sql`, `consistency-check.sql`,
`release-check.sql`, la huella de las nueve funciones con su cuerpo, seguridad, `search_path`, dueño y permisos, una
firma de toda la estructura y la huella de todas las filas de las 66 tablas):

| Paso | Resultado |
|---|---|
| A · 0032 | `release-check`: `migrations_missing` = `[33]`, `functions_missing` = `["access_lock_all", "pin_lock_clear"]` |
| B · 0033 (46 ms) | `compare.py after` de A a B: 26 tablas originales idénticas, 27 comprobaciones de negocio, 11 reglas abiertas (las revisadas), `"0033": 9`. Ninguna fila de ninguna tabla cambió; la estructura solo cambió en las 9 funciones y la columna `session_id` |
| Trabajo bajo la 0033 | Apertura atada a la sesión de una tableta; Luis bloqueado con 5 PIN equivocados (`pin_locked` anotado); un intento de dar a alguien nuevo el PIN de Luis (`pin_in_use` anotado); una venta a la manera de las páginas nuevas; una marca de reloj |
| C · **reversión** como la envía el SQL Editor (todo el archivo en una sola consulta, cuenta no superusuaria; **42 ms**) | Versión 32; las tres funciones nuevas desaparecen; las **seis funciones son byte a byte las de la 0032** (cuerpo, `security definer`, `search_path`, dueño, permisos, volatilidad); la estructura difiere de la 0032 **solo** en la columna `session_id` (sin uso); **ninguna fila borrada ni cambiada** (bitácora, bloqueo, aperturas y ventas del periodo 0033 incluidos); en la foto de producción las listas de `schema` son idénticas a las de A: `functions_changed` y `functions_unknown` vacíos y en `functions_missing_legacy` las mismas cinco firmas de antes del lanzamiento (retiradas por 0005/0010, las esperadas desde D-047) |
| El café en la base revertida | La apertura hecha bajo la 0033 sigue abriendo las áreas de dueño sin volver a escribir el PIN; una venta a la manera de las páginas de hoy (pedido y luego líneas) y una a la de las nuevas (una sola llamada), las dos guardadas y marcadas `no_operator` porque no dicen quién cobró (modo `record`, como en producción); un PIN equivocado y luego el correcto en el reloj; el editor del equipo guarda una persona nueva; una segunda tableta abre con el PIN y «Bloquear» termina solo la suya; el bloqueo de Luis sigue como estaba |
| D · 0033 otra vez (50 ms) | Las nueve funciones byte a byte las de la primera 0033; ninguna fila cambió; la apertura de la primera 0033 (con sesión) abre; una apertura hecha mientras estaba revertida (sin sesión) también la acepta la 0033 |
| E · negativas | Sobre 0032 sin la 0033: «La migración 0033 no está aplicada: no hay nada que revertir»; pegada dos veces: la misma negativa; con una migración 34 presente: «Hay migraciones posteriores a la 0033». En los tres casos ninguna fila ni la estructura cambió |
| F · `psql --single-transaction -f` | Mismo resultado que el pegado |
| G · con el café trabajando | Una venta con su transacción abierta durante la reversión se guardó con su línea; 133 comprobaciones de PIN durante la reversión, ninguna falló; 44 ms |

Las pruebas de navegador (3.2 a 3.4) corrieron sobre copias con `operator_mode` = `off`, el valor por defecto (producción
tiene `record` desde el 2026-10-15): no pasaron por la ventana «¿Quién cobra?» de la Caja. Ese flujo lo cubre
`120_operators.spec.js` en la batería completa, en verde sobre la 0033 («Tests» #151) y sobre la base revertida (3.3).

**3.2 Páginas de hoy** (`tests/rehearsal/live-pages.sh` con `LIVE_PAGES_SHA` = `0ad8c88`, la publicada): 8 de 8 sobre
la copia en 0032, 8 de 8 sobre 0033 y 8 de 8 sobre la revertida (todas las páginas cargan sin errores ni llamadas
rechazadas; vende; guarda sin internet y sube; sube una venta guardada tres días; el reloj; «Horas y equipo» con PIN
equivocado, PIN de encargado y una persona nueva; el Menú; el editor de recetas con PIN).

**3.3 Páginas nuevas sobre la base revertida** (toda la batería `tests/e2e/specs`, 149 pruebas, sobre la base de
pruebas con la reversión aplicada): **143 de 149**. Las 6 que no pasan son exactamente lo que la 0033 trae y la
reversión quita, sin errores en pantalla: «Cerrar sesión en todos lados» no termina las aperturas de los otros aparatos
de la cuenta (no existe `access_lock_all`; «Cerrar sesión» sí termina la del aparato); un token copiado a otra tableta
de la misma cuenta abre allí (como antes de la 0033); un bloqueo no queda anotado y no hay «Quitar el bloqueo del PIN»
(la página explica que falta la actualización); no hay límite de 10 PIN por hora; y la prueba de la cadena de
reversiones 0033→0030 se detiene en la primera porque la 0033 ya no está (la negativa correcta del propio archivo). Todo
lo demás (Caja, ventas sin internet, cuentas, anulaciones, reloj, inventario, recetas, Menú, fotos, contabilidad)
funciona igual.

**3.4 Transiciones:** las siete de la sección 2.

**3.5 Lo que el simulacro no prueba:** Supabase Storage (la foto se prueba en producción, 4.2.6) y los datos reales. Si el
dueño quiere además la reversión con datos reales, es el mismo simulacro de restauración de `docs/RESPALDOS.md` (Docker
con PostgreSQL 17 en su Mac): restaurar el último respaldo → `production-snapshot.sql` («copia antes») → 0033 con
`psql --single-transaction` → `release-check.sql` y `production-snapshot.sql` → `reversion-0033.sql` con
`--single-transaction` → `production-snapshot.sql` y comparar con la «copia antes» (`schema` y `data_fingerprint`
iguales) → 0033 otra vez → borrar el contenedor. Unos 30 minutos; Claude escribe antes los comandos exactos si lo pide.

## 4. Pasos (los ejecuta el dueño)

### 4.1 Antes de la ventana (el mismo día, con el café abierto; nada de esto cambia producción)

1. **«Tests» en verde** sobre el commit que se va a etiquetar (el de este documento, o `3d80f30`).
2. **Crear la etiqueta** (por la tarde; no publica nada).
   1. GitHub → Releases → Draft a new release → etiqueta `vAAAA.MM.DD-1`, con la fecha de la ventana en Monteverde.
   2. **Target:** la rama `claude/hanging-garden-coffee-proposal-1m8zd4`, no la predeterminada (el formulario propone la
      predeterminada y nada avisaría del error).
   3. Comprobar que el commit que muestra es el aprobado. Si no aparece, no crear la etiqueta y avisar.
   4. Publish release. Abrir la etiqueta y confirmar a qué commit señala.
   5. La etiqueta dispara «Tests» (unos 10 minutos): debe terminar en verde. Si sale rojo, no empezar la ventana: copiar
      el nombre del paso y de la prueba en rojo y pasarlo a Claude. «Re-run all jobs» solo si Claude confirma que es el
      ritmo de las pruebas y que no hay nada que corregir; con un segundo rojo se pospone. (Los rojos de #149 y de #157
      también fueron de ritmo y se resuelven con un commit nuevo (y, para #157, una etiqueta nueva), no con un re-run: si
      Claude pide corregir una prueba, no se re-ejecuta, se pospone.)
   6. **Nunca borrar ni mover la etiqueta.** Si la ventana no se completa, otra noche se publica la misma etiqueta,
      repitiendo ese día el ensayo y el respaldo.
3. **Copia guardada del sitio actual** (decisión 4): Releases → Draft a new release → etiqueta `sitio-AAAA-MM-DD`
   (fecha de hoy) → **Target: la rama `gh-pages`**, que debe mostrar `0ad8c88` → marcar «Set as a pre-release» →
   Publish release. Es el procedimiento E-19 de `docs/PUBLICAR.md`.
4. **«Ensayo en pruebas»** en `canopy-respaldos` → Actions → Run workflow: versión = la etiqueta nueva, destino =
   `desechable`, vaciar = `no`, reinicio = `no`. Unos 5 minutos, en verde. En el resumen debe aparecer «the copy already
   had migrations 0000-0032» y en `timings.txt` (zip `ensayo-resultados-desechable`) la línea `0033_pines_seguros … ms`.
   Si sale rojo, aunque el mensaje parezca ajeno a la 0033, no empezar la ventana y pasar el mensaje a Claude (no
   contiene datos).
5. **Lectura previa** (solo lectura). Cada archivo por su dirección con la etiqueta y el botón «Raw»:
   `https://github.com/jeanpaulcocaleca-create/Claude-repository/blob/<etiqueta>/supabase/tools/release-check.sql`
   (la portada del repositorio muestra la rama predeterminada, que no tiene `supabase/`). Cmd+A, Cmd+C → Supabase →
   SQL Editor → New query → pegar → Run. Esperado: `migrations_missing` = `[33]`; `functions_missing` =
   `["access_lock_all", "pin_lock_clear"]`; en `settings`, `operator_mode` = `record`. Guardar la celda completa.
6. **Respaldos:** la tarjeta «Respaldos» de Inicio en verde. Las llaves privadas ya están comprobadas (E-24).
7. **Avisar al equipo:** las casillas de PIN se ven como puntos y el navegador ya no ofrece guardarlas; la primera vez
   después de la actualización hay que escribir el PIN otra vez; las listas «Quién abre» y «Quién cierra» empiezan
   arriba una vez: elegir su propio nombre antes de escribir el PIN (un PIN escrito con otro nombre cuenta como intento
   equivocado de esa otra persona); hay mensajes nuevos en «Equipo».

### 4.2 La ventana (café cerrado, caja cerrada, ningún aparato vendiendo)

1. **Aparatos en reposo.** En cada aparato con la Caja abierta, el chip dice «en línea» y, al tocarlo, «Todo lo que se
   tomó en este dispositivo está guardado en el sistema.» No hay cuentas abiertas ni tickets en cocina; «Hoy en el
   mostrador» cerrado y la ventana «¿Quién cobra?» cerrada con «Ahora no» (mientras está abierta, la Caja no se
   actualiza sola); ningún formulario a medias; fecha y hora automáticas sin aviso de reloj; una pestaña por página. Si
   el chip dice otra cosa («guardando N…», «N sin guardar todavía», «sin conexión · N en este dispositivo», «no
   guardado en este dispositivo»), **no seguir** hasta que se vacíe. Durante la ventana, dejar cada aparato en la Caja
   o en la cocina: con el ingreso compartido, Reloj, Inicio, Menú, Ventas e Inventario cierran la sesión solos a los 30
   minutos sin uso y el aparato pide correo y contraseña.
2. **Respaldo inmediato.** `canopy-respaldos` → Actions → «Respaldo nocturno» → Run workflow (unos 2 minutos, en verde;
   el resumen dice «restauración verificada … contenido idéntico» y «restauración: passed»). Luego confirmar que no
   queda nada corriendo: en Actions ninguna corrida de «Respaldo nocturno» ni de «Ensayo en pruebas» en curso o en
   cola; en el SQL Editor `select count(*) from pg_stat_activity where usename = 'canopy_backup';` → `0`.
3. **Foto «antes».** Pegar `production-snapshot.sql` (de la etiqueta, Raw) y guardar la celda. Una foto tomada con el
   café abierto no sirve: cada venta, marca o apertura cambia las huellas.
4. **Aplicar la 0033.** SQL Editor → New query → pegar **todo**
   `…/blob/<etiqueta>/supabase/migrations/0033_pines_seguros.sql` (Raw). Antes de Run: la segunda línea (debajo de
   «=====») dice «Canopy OS · migración 0033 · PIN más seguros…» y la última línea pegada es
   `notify pgrst, 'reload schema';`. Run → *Success*. Luego
   `select version, name, applied_at from canopy.migrations order by version desc limit 2;` → `33 pines_seguros` y
   `32`; `applied_at` es la hora UTC del pegado: anotarla. Si dice *Success* pero no aparece la 33, no publicar: volver
   a pegar la 0033 completa y repetir la consulta. (En el simulacro: 46 ms.)
5. **Comprobación.** Pegar `release-check.sql`: `migrations_missing` = `[]` y `functions_missing` = `[]`;
   `anon_can_run` y `tables_without_rls` iguales a la celda de 4.1.5. **Foto «después»:** pegar
   `production-snapshot.sql` y guardar la celda **antes de tocar los aparatos**: `functions_by_version` con
   `"0033": 9`; `functions_changed` y `functions_unknown` sin entradas nuevas; `data_fingerprint` y
   `storage_fingerprint` iguales a los de 4.2.3. Si algo difiere, no publicar y pasar las dos celdas a Claude.
6. **Prueba de la foto del menú** (con las páginas de hoy, antes de publicar, para separar la base de las páginas).
   1. En la tableta preparada, con su ingreso de siempre (sin código del teléfono): Caja → «Menú».
   2. Si «Menú» no pide PIN, o abajo dice «Áreas de dueños abiertas», tocar «Bloquear» y volver a «Menú». Debe pedir
      el PIN: una apertura de antes de la 0033 no sirve para fotos.
   3. El encargado escribe su PIN → tocar el cuadro de foto del producto → subir la foto guardada.

   | Mensaje | Qué significa | Qué hacer |
   |---|---|---|
   | «Foto actualizada» | Correcto | Tocar «Bloquear» y seguir |
   | «La foto se guardó pero el menú no se actualizó. Intente de nuevo.» | Storage aceptó la foto: la 0033 funciona | Subirla una vez más; si se repite, anotar y avisar. No es el caso de la decisión 6 |
   | «Esa foto es muy grande…» | — | Elegir otra de menos de 8 MB |
   | «No se pudo subir la foto. Intente de nuevo.» | Falla | Repetir una vez desde «Bloquear» con un PIN recién escrito. Si vuelve a fallar: **decisión 6, detenerse y diagnosticar** (sección 5) |

   Después, dejar la tableta otra vez en la Caja.
7. **Publicar las páginas.** GitHub → Actions → «Publish website (PRODUCTION · manual only)» → Run workflow → Use
   workflow from → **Tags** → la etiqueta nueva → escribir `PUBLICAR`, «restaurar» vacío → antes de «Run workflow»
   confirmar que «Use workflow from» dice la etiqueta nueva. Como E-20 está abierta, no hay segunda confirmación (si
   estuviera configurada, la corrida esperaría en «Review deployments»: aprobar solo si es la de la etiqueta nueva).
   Esperar el verde de la corrida y el de «pages build and deployment» (de 2 a 10 minutos); anotar ambos números.
8. **Confirmar la versión.** `https://hanginggardencafe.com/version.json` en una ventana privada: `"version"` = la
   etiqueta y `"build"` = los 12 primeros caracteres del commit etiquetado. Si sigue la anterior, es caché: esperar y
   volver a mirar, no volver a publicar. Anotar el commit nuevo de `gh-pages` («Publish website <etiqueta> <commit>»).
9. **Actualizar los aparatos.** Recargar a mano cada página de cada aparato, incluida la TV. La Caja se recarga sola
   cuando está libre; si a los 15 minutos sigue en «actualización lista», recargarla a mano. Al terminar, dejar abiertas
   solo las páginas que cada aparato usa en servicio.

### 4.3 Pruebas inmediatas (sin ventas de prueba)

**No hacer ventas, anulaciones, marcas de reloj, aperturas de caja ni recepciones de prueba:** con la caja cerrada no se
pueden deshacer y quedarían como registros reales (D-044, CLAUDE.md). Esas funciones las cubren las pruebas automáticas
y se comprueban con los primeros eventos reales del día siguiente. Las pruebas siguientes solo dejan anotaciones en la
bitácora. Cada PIN se escribe una sola vez y con calma: esa noche no hay otro encargado que quite un bloqueo.

| # | Área | Qué hacer | Correcto si |
|---|---|---|---|
| A | Todas | En cada aparato, abrir la pantalla de PIN de «Menú», de «Inventario» o de «Ver horas», escribir 4 números y borrarlos con ⌫, **sin tocar ✓, OK ni «Abrir»**. Nunca en el teclado de «Entrada · salida» ni en «Abrir caja»: su OK marca o abre de verdad | Se ven puntos y el navegador no propone una contraseña guardada. Si un iPad o Firefox ofrece guardar o rellena un PIN, tocar «Nunca», anotarlo y avisar: el PIN rellenado se borra y no se envía. No es motivo para revertir |
| B | PIN | Reloj → «Horas y equipo». El encargado de 4.2.6 (su cuenta de intentos está en 0): un PIN equivocado una vez y en seguida el correcto | Primero «Ese PIN no es correcto.»; luego abre y abajo dice «Áreas de dueños abiertas · (nombre) · hasta las HH:MM», ahora + 15 min. Si la hora no cuadra, el reloj o la zona del aparato está mal (como en D-052): corregirlo en Ajustes; no es falla de la versión |
| C | Personal | Ahí mismo: «Equipo» → «Editar» en una persona → solo mirar → «Cancelar». Luego «Bitácora de aprobaciones». Al final, «Bloquear» en el aviso | Sin errores y la bitácora en español. **No escribir PIN en «Equipo»**: cuentan para el límite de 10 por hora |
| D | PIN | **Al día siguiente:** un miembro del equipo que no sea encargado elige su nombre, escribe su PIN → «Ver horas» | Ve solo sus horas. No deja registro |
| E | Ventas | Caja → «Pedidos» → «Buscar ventas anteriores…» → un día anterior → «Abrir días anteriores con el PIN de un encargado» → PIN | Abre. Si dice «Este encargado no puede ver las ventas de días anteriores…», la apertura funcionó igual. Luego «Bloquear» en la barra |
| F | Inventario | Inventario → PIN → «Recetas» → un producto que ya tenga receta **con cantidades enteras** → sin cambiar nada → «Guardar receta» → PIN correcto, una sola vez. Luego «Bloquear» | «La receta no cambió» (no deja versión ni anotación). Si dice «Receta guardada · versión N», detenerse y revisar Inventario → Historial: quedó una versión real, que no se borra |
| G | Fotos | (Opcional) Repetir 4.2.6 con las páginas nuevas, con la misma foto | «Foto actualizada» |

**Consultas finales** (solo lectura; cada una en su propio «New query», porque el SQL Editor muestra solo el último
resultado):

```sql
select at, action, manager_name, details->>'session_bound' as atada_a_sesion, summary
  from public.audit_log
 where action in ('access_open','pin_locked','pin_in_use','pin_lock_cleared')
 order by at desc limit 15;
```
Esperado: cada `access_open` posterior a la hora de 4.2.4 tiene `atada_a_sesion` = `true`, y no hay ningún `pin_locked`
inesperado.

```sql
select count(*) as abiertas from public.access_unlocks where expires_at > now();
```
Esperado: `0` después de «Bloquear» en cada aparato donde se escribió un PIN, o 15 minutos después de la última
apertura. Una apertura hecha con las páginas de hoy antes de publicar queda en el servidor hasta que vence (la tableta la
olvida al tomar las páginas nuevas, como dice el aviso al equipo); no abre nada en otro aparato.

**Nunca, en las tabletas del café:** «Cerrar sesión en todos lados» (saca la Caja y la cocina y termina todas las
aperturas de la cuenta), «Activar» el código del teléfono, «¿Olvidó su contraseña?». Probar «Cerrar sesión» solo en un
aparato donde el dueño pueda volver a escribir la contraseña.

**Al terminar:** cada aparato vuelve a su página de trabajo; se cierran las pestañas de Inicio, Menú, Ventas e
Inventario abiertas para las pruebas; cada Caja dice «en línea», con la sesión iniciada. **Al día siguiente** se
comprueban los primeros eventos reales: la apertura de caja con PIN, las primeras ventas en efectivo y con tarjeta, la
primera marca de reloj, la primera anulación o el primer movimiento de caja si ocurren, «Ventas», la bitácora y la
prueba D.

## 5. Criterios para detener o revertir

| Momento | Señal | Qué hacer |
|---|---|---|
| Antes | «Tests» de la etiqueta no está verde, el ensayo está rojo, el respaldo está rojo, una Caja tiene ventas sin guardar, o hay un respaldo o ensayo corriendo | **No empezar.** Nada cambió |
| 4.2.4 | «lock timeout» | Nada cambió: esperar un minuto y volver a pegar. Si pasa por segunda vez, no pegar una tercera: revisar Actions y la consulta de 4.2.2. Con 0 corridas y 0 conexiones, detenerse y avisar |
| 4.2.4 | Cualquier otro error | **Detenerse:** copiar el mensaje completo y no publicar. La base sigue en 0032, con las páginas de hoy |
| 4.2.5 | `release-check` no da `[]` y `[]`; cambiaron `anon_can_run` o `tables_without_rls`; o las huellas de datos difieren | **No publicar.** Pasar las celdas a Claude. Si la 0033 quedó mal, `reversion-0033.sql` |
| 4.2.6 | La foto falla dos veces | **Decisión 6: detener el procedimiento y diagnosticar.** No publicar las páginas esa noche. Mandar a Claude el mensaje exacto, la hora, el producto y una foto de la pantalla (sin PIN); dejar la tableta en la Caja. La base queda en 0033 con las páginas de hoy: estado probado; el café puede abrir así. Con el diagnóstico, el dueño decide: seguir (publicar otra noche, con la prueba de la foto repetida si hubo corrección) o revertir la 0033 (sección 2) |
| 4.2.7 | La corrida «Publish website» falla | El sitio no cambió y las páginas de hoy funcionan sobre la 0033. Detenerse y reportar; no repetir a ciegas |
| 4.2.8 | `version.json` no cambia en 15 minutos, con la corrida en verde | Revisar «pages build and deployment». No volver a publicar |
| 4.3 | Una página no carga, la Caja no muestra productos, un PIN correcto no abre en ninguna tableta, o aparecen errores en pantalla. **Excepto** el mensaje de bloqueo («Demasiados PIN incorrectos. Espere 10 minutos e intente de nuevo.»): es el bloqueo de 5 intentos, igual en todas las tabletas; esperar 10 minutos (sección 6) y no revertir nada | **Volver a las páginas de hoy** (sección 2, páginas). La base se queda en 0033: las páginas de hoy funcionan con ella |
| 4.3 o después | El problema sigue con las páginas de hoy: PIN correctos rechazados en todas partes (sin el mensaje de bloqueo), el desbloqueo no abre nada, errores que nombran funciones de PIN | **`reversion-0033.sql`** (sección 2, base), fuera del horario de atención; si ocurre de día, la sección 6 hasta el cierre, salvo que el dueño decida otra cosa |
| Siempre | Cualquier duda sobre el dinero | Detenerse. Nunca restaurar un respaldo encima de producción y nunca borrar registros |

**Cómo correr `reversion-0033.sql`:** SQL Editor → pegar **todo** el archivo (de la etiqueta, Raw) → si el editor pide
confirmar una «destructive operation», es lo esperado (quita funciones y la fila 33 del registro): «Run this query» →
debe terminar con «listo: la 0033 se revirtió…» → `release-check` muestra otra vez `migrations_missing` = `[33]` y los
dos nombres de 4.1.5. Nadie tiene que volver a escribir su PIN: las aperturas hechas bajo la 0033 siguen abriendo.

**Lo que se pierde al revertir.** La 0033: vuelven los problemas que corrige (se pueden averiguar PIN; un PIN vacío
cuenta como intento; los bloqueos no se anotan; se puede reactivar a alguien con un PIN que ya usa otra persona; con
una apertura en un aparato se pueden cambiar fotos desde cualquier otro aparato de la cuenta). Las páginas de hoy:
vuelven las casillas de PIN tipo contraseña (D-052); por eso la transición de tabletas sigue detenida.

## 6. Cómo mantener el café funcionando si algo falla

- **Las ventas no se detienen.** La Caja está en «Registrar quién cobra»: al abrir pregunta «¿Quién cobra?»; si el PIN
  no funciona, «Ahora no» y vender (la venta queda sin cajero, marcada para revisar). Sin internet, la Caja guarda cada
  venta en el aparato y la sube después: **nunca repetir una venta**; mantener abierta la pestaña de la Caja. El
  servidor nunca rechaza dinero ya cobrado.
- **Abrir la caja sin PIN:** cerrar «Hoy en el mostrador» y vender; anotar el fondo en papel y abrir la caja con PIN
  apenas funcione.
- **Descuentos:** sin PIN no se dan; precio completo o esperar al encargado. **Anulaciones:** en papel (qué, cuánto,
  quién, por qué) y registrarlas con PIN antes de cerrar la caja ese mismo día (después del cierre quedan como
  devolución del día en que se registran). **Movimientos de caja:** en cuanto el PIN funcione. **Reloj:** una hoja con
  la hora de entrada y de salida; el encargado lo corrige después en «Horas y equipo», con el motivo.
- **PIN bloqueado:** esperar 10 minutos; a un miembro del equipo, cualquier encargado le pone un «Nuevo PIN»; a un
  encargado, mejor que se lo cambie él mismo después de los 10 minutos (si otro encargado se lo pone, se le apaga «Puede
  abrir los reportes de ventas con su PIN»; así es mientras nadie del equipo tenga puesto de dueño, como hoy; si lo
  hubiera, la página lo rechaza con «Solo un dueño puede cambiar el PIN, el puesto o el estado de otro encargado.» y lo
  cambia el dueño); con las páginas nuevas, «Quitar el bloqueo del PIN» con el PIN de **otro**
  encargado, 2 veces al día por persona; el bloqueo de alguien con puesto de dueño solo se puede esperar (E-06); cada
  PIN nuevo cuenta para el límite de 10 por hora de la cuenta, que comparten todas las tabletas.
- **Un aparato que pide el PIN otra vez:** recargar y volver a escribirlo. Inicio a veces dibuja la pantalla de PIN dos
  veces al abrir, y un PIN escrito en el primer segundo puede perderse.
- **Un aparato que pide correo y contraseña:** si quedó más de 30 minutos en Reloj, Inicio, Menú, Ventas o Inventario,
  es la salida automática, no la versión; vuelve a entrar un dueño, o un encargado que tenga la contraseña por escrito en
  el café; nunca mandar la contraseña por chat; detenerse y avisar solo si la piden aparatos que no quedaron así.
- **Tiempos:** volver a las páginas de hoy, de 2 a 10 minutos más hasta 15 para que las tabletas se actualicen
  (recargarlas a mano, entre ventas); revertir la 0033, un pegado de segundos; restaurar un respaldo **no** es una
  reversión: último recurso, en un proyecto nuevo, solo con autorización expresa (menos de 2 horas; se pierde lo
  posterior al respaldo).
- **Para reportar un fallo:** la página, la hora, el aparato, el mensaje exacto (una foto de la pantalla sin PIN ni
  contraseñas) y qué se estaba haciendo. Claude lo analiza y prepara la corrección; decide el dueño.

## 7. Registros

**Durante la ventana, anotar** (sin PIN ni contraseñas): número y hora de «Tests» de la etiqueta, del ensayo y del
respaldo con sus líneas de resumen; el `applied_at` de la 0033; las celdas de `release-check` (antes y después) y de
`production-snapshot` (4.2.3 y 4.2.5); los números de «Publish website» y de «pages build and deployment»; el commit
nuevo de `gh-pages` y `version.json`; el producto de la foto; el resultado de A a G.

**Después**, en un commit normal con autorización del dueño: D-053 y E-36 (que E-36 pase a cerrada);
`docs/MIGRACIONES.md` («hoy en la 0033»); `docs/CHECKLIST.md` (la fila del procedimiento de publicación y las filas
D-052/D-053); `docs/PRODUCTION-READINESS.md`, `docs/PRUEBAS.md` y `tests/rehearsal/LIVE_PAGES` (con el nuevo
`gh-pages`). Ese commit dispara «Tests», cuyo paso «The live site is an approved release» comprueba el sitio publicado.

**Con las páginas nuevas ya publicadas, en otro momento:** en la computadora y el navegador donde apareció la apertura
inesperada (según D-052, una ventana privada en la computadora del dueño, no una tableta): Ajustes del navegador →
Contraseñas → `hanginggardencafe.com` → borrar toda entrada que no sea la del correo del ingreso. Y Jorge abre «Horas y
equipo» con su propio PIN y se pone él mismo un PIN nuevo («Nuevo PIN» en su fila): conserva el acceso a ventas; cuenta 1
de los 10 por hora.

La transición de tabletas (E-05) sigue detenida hasta que el dueño decida.
