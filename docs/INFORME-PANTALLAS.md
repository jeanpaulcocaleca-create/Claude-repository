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
