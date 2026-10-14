# Lanzamiento único · Canopy OS (reinicio operativo, migraciones y páginas en una ventana, en el mismo proyecto)

**Estado: preparado y ensayado; nada ejecutado en producción.** Decisión del dueño del 2026-10-14 (D-038) y su revisión
de esa misma noche (D-039): **el mismo proyecto de Supabase y el mismo sitio; ningún segundo proyecto.** Este documento
es el guion operativo de la ventana. `docs/LANZAMIENTO.md` sigue valiendo para las reglas, la tabla de reversión por
migración y las olas de activación y capacitación; `docs/PRODUCTION-READINESS.md` §8 conserva la secuencia anterior.
Documentos: `docs/RESPALDOS.md` (respaldo, pasos 3.5–3.6, y restauración), `docs/PRUEBAS.md` (el ensayo con los datos
reales en una base desechable), `docs/PUBLICAR.md` (publicar y volver atrás), `docs/INGRESOS.md` (ingreso del café),
`docs/MIGRACIONES.md`. Scripts: `supabase/tools/reinicio-operativo.sql` (el reinicio, una sola vez) y
`supabase/tools/resumen-pruebas.sql` (el resumen del periodo para el contador, solo lectura).

## 1. La decisión

Un solo lanzamiento: la base pasa de la base de hoy a las migraciones 0000–0028 y las páginas nuevas se publican en
la misma ventana, en vez de olas separadas. Antes de la primera migración se hace, **una sola vez**, el reinicio
operativo: se borran las ventas, los días de caja, los turnos, los movimientos de inventario y los pedidos del periodo
de prueba, y el café empieza de cero con su menú, recetas, insumos, proveedores, personal e ingresos intactos. El
periodo de prueba no se pierde: queda en el respaldo cifrado verificado de esa noche y en el resumen para el contador.

El inventario empieza en **cero**: no se arrastran las cantidades del periodo de prueba; las existencias reales se
cargan la mañana siguiente, después del conteo físico, con «Contar» en Inventario. Lo regulado queda **apagado**:
precios con IVA incluido (`price_mode` inclusive), asientos automáticos (`ledger_auto_post` false), comprobantes
electrónicos (`einvoice_mode` off), «quién cobra» (`operator_mode` off), planilla sin reglas confirmadas; no se
registra ninguna confirmación de cumplimiento. Cada interruptor se enciende después, por separado, con la
confirmación que le corresponde (`docs/DEPENDENCIES.md`, A-01…A-10).

**Todo ocurre en el proyecto de Supabase de hoy y en el sitio de hoy** (D-039). La dirección `production` de
`website/config.js` (hoy `https://nbvczarfweanoxvdqplk.supabase.co`, pública), el identificador del proyecto y la llave
pública `anon` no cambian; el sitio sigue en `hanginggardencafe.com`. Ningún dato se mueve a otra base: el reinicio y
las migraciones corren **dentro** de la base actual. **No se crea ningún segundo proyecto** ni un sitio de pruebas (E-13
y E-14 retiradas): el ensayo con los datos reales corre en una base temporal que vive lo que dura el trabajo de GitHub
que la crea (sección 3). Razón del dueño: lo vivido en Proyecto NORA al cambiar de base y de entorno; aquí hay un
proyecto, un sitio y una ventana. El **primer respaldo cifrado está hecho y verificado** (E-03, 2026-10-14).

## 2. Qué se conserva y qué se borra

**Se borra** (es historia de prueba; el respaldo cifrado la conserva):
- ventas y sus líneas (`orders`, `order_items`), partes de cuentas y sus líneas (`order_part_lines`), adiciones a
  cuentas abiertas (`tab_adds`); con ellas las anulaciones y los pedidos de habitación, que son ventas;
- descuentos aprobados (`discount_approvals`); días de caja (`register_days`); turnos del reloj (`time_entries`);
- movimientos de inventario (`stock_moves`); las existencias (`stock_items.on_hand`) quedan en 0;
- pedidos a proveedores y sus líneas (`purchase_orders`, `purchase_lines`);
- sesiones de PIN de caja, ventas e inventario (`access_unlocks`, `sales_unlocks`, `inventory_unlocks`); preguntas de
  visitantes (`chat_questions`);
- los bloqueos de PIN por intentos fallidos del periodo (`staff.failed_pins`, `locked_until` vuelven a cero: nadie
  empieza el primer día bloqueado; los PIN no cambian).

**Se conserva, byte por byte** (el reinicio toma una huella antes y después, y se niega si algo cambiaría):
- categorías y platos del menú (`menu_categories`, `menu_items`: precios, fotos, textos); recetas (`recipes`);
- insumos (`stock_items`: nombre, empaque, costo, proveedor, nivel deseado, punto de pedido; todo salvo la cantidad en
  existencia y su fecha de cambio); proveedores (`vendors`);
- personal (`staff`: nombres, puestos, PINs); ingresos y permisos (`app_accounts`, `auth.users`: los dos dueños y el
  ingreso de los aparatos);
- ajustes del café (`app_settings`); pizarra de TV y sus diapositivas (`board_settings`, `board_group_slides`);
  habitaciones y sus códigos QR (`rooms`);
- la bitácora (`audit_log`), que recibe UNA línea `reinicio_operativo` con las cantidades borradas, la huella (md5) del
  resumen y la referencia del respaldo. Las cifras del resumen no van a la bitácora (la lee cualquier encargado): van en
  la celda de resultado que usted guarda, y su huella debe ser la misma `huella` del `resumen-pruebas.sql` guardado antes.

Los aparatos del café no se salen: las sesiones no se tocan. Mientras corre el reinicio (segundos) nadie puede anotar
ventas, preguntas ni marcas: entran después, al café limpio. Una venta que una tableta tuviera «sin guardar todavía»
desde antes del reinicio entra después marcada `before_reset` (la revisión de consistencia la cuenta en
`orders_before_reset`): el encargado la anula; por eso ninguna tableta debe tener pendientes al empezar la ventana.

**Registros que se conservan por obligación legal.** El respaldo cifrado de la ventana es el archivo del periodo de
prueba: guárdelo durante el plazo de conservación tributaria (el Código de Normas y Procedimientos Tributarios obliga
a conservar los registros por el plazo de prescripción; se citan cuatro años, y diez en algunos casos: **confirmar
con el contador**, A-11), junto con el resumen de `resumen-pruebas.sql` (cantidades y totales por día y por medio de
pago, anulaciones, descuentos, cajas, turnos, compras; sin nombres). Si alguna venta del periodo fue real (se cobró a
un cliente), el contador decide con ese resumen cómo se declara (A-11). Si algún turno fue de un trabajador real (el
personal nuevo desde el 2026-10-15), es un registro laboral: el respaldo lo conserva con todo el detalle, y antes de
la ventana el encargado anota las horas por persona (Reloj → «Horas y equipo») para la planilla. La bitácora queda en
la base. Los pagos con tarjeta viven en el banco y en el datáfono, no en la caja: la caja solo anota el medio y el
monto.

## 3. Ensayo: qué se prueba y dónde

Dos capas; ninguna toca producción ni necesita otro proyecto de Supabase.

**(a) El ensayo automático, en cada cambio** (`tests/run.sh rehearsal`, en CI con cada push), sobre una copia sintética
pero realista de la base de hoy (`tests/rehearsal/seed-legacy.sql`: unos 4 meses, 14 534 ventas), como una cuenta que
**no** es superusuario, igual que el `postgres` del SQL Editor (`tests/rehearsal/as-supabase.sql`): (1) el esquema de
hoy con la deriva real de producción; (2) foto y consistencia antes; (3) respaldo con prueba de restauración; (4) las 29
migraciones, una transacción por archivo; (5) foto y consistencia después: nada de lo que existía cambió; (6) el día
siguiente con las páginas de hoy, una venta guardada sin internet y las páginas nuevas; (7) los libros de 30 días cuadran
colón por colón; (8) respaldo y restauración de la copia migrada; (9) la copia tal como la hace `ensayo.sh`: anonimizada
y cargada en una base **vacía** que `restore-stub.sql` deja igual a un proyecto de Supabase, otra vez vaciándola antes, y
otra vez con reinicio = `si`; (10) el pase del reinicio sobre una segunda copia de la base de hoy: seis negativas que no
cambian nada, el reinicio como UNA consulta, lo borrado vacío, las existencias en cero, lo conservado idéntico, la
bitácora con la huella del resumen, las migraciones después y `compare.py reset`; luego `tests/rehearsal/reset-pages.sh`:
las páginas de hoy y las nuevas, en un navegador real, sobre el café vacío y su primer día.

**(b) Su ensayo con los datos reales, de un botón**: `canopy-respaldos` → Actions → **Ensayo en pruebas** → versión: la
etiqueta a lanzar → **destino = `desechable`**, vaciar = `no`, **reinicio = `si`** (docs/PRUEBAS.md). Copia producción con
la cuenta de **solo lectura** del respaldo, la anonimiza en el servidor desechable del trabajo (`anonimizar.sql`), la carga
en una base PostgreSQL 17 **temporal dentro del propio trabajo** (ningún proyecto de Supabase; desaparece al terminar),
cierra el café en la copia, guarda el resumen, ejecuta `reinicio-operativo.sql` **tal cual**, toma la foto de después,
aplica 0000–0028 y compara. Debe terminar en **verde** con `reinicio hecho · respaldo ensayo …`, `borrado: …` (filas por
tabla y `stock_items_a_cero`), `conservado idéntico: …` (los 13 nombres), cada migración con su tiempo y la comparación
`reset` sin diferencias; los archivos (`ensayo-resultados-desechable`) traen solo cantidades y huellas; `timings.txt` es
la referencia de cuánto tardará cada pegado. Allí las migraciones corren como superusuario del servidor temporal: que
corren también como la cuenta del SQL Editor, que no lo es, lo prueba (a). Si cambia la versión, se repite. No hay sitio
de pruebas: las páginas se prueban en (a) sobre el café vacío; con los datos reales las ve usted en la ventana.

**Qué se verifica en local y qué solo se verifica en Supabase**, con lo que cubre cada hueco en la ventana:

| Tema | Verificado en local (CI y la base desechable) | Solo en Supabase | Cómo se cubre en la ventana |
|---|---|---|---|
| Migraciones, RLS y permisos | En CI, las 29 como una cuenta no superusuario con los roles de Supabase y sus privilegios por defecto (en la base desechable, como superusuario, sobre los datos reales); `release-check.sql`: `anon_can_run` solo las 4 funciones públicas, `tables_without_rls` vacío | Los privilegios por defecto de `supabase_admin` y el `postgres` real del Editor | `release-check.sql` después de la 0028 con esos mismos valores; una diferencia = parar y enviármela |
| Ingresos (Auth) | Las páginas con y sin código; `cafe-login.sql` en la copia (la sesión del aparato sigue vendiendo) | Que activar el código cierre las otras sesiones del mismo ingreso; el correo de «olvidé mi contraseña»; las sesiones reales de los iPads | INGRESOS caso B: ingresos personales confirmados antes; el ingreso del café se convierte **antes** de cualquier código; el código solo en el ingreso personal, desde el propio teléfono; ni el reinicio ni `cafe-login.sql` tocan sesiones |
| Storage (fotos, facturas) | Las líneas `storage.` de 0015 y 0025 con un rol sustituto (`rehearsal_storage_admin`) que permite **más** que producción; el lint solo deja crear el depósito y sus reglas | storage-api y `policy_grants` de supautils | Derechos confirmados por la consulta de seguimiento (2026-10-13: `can_insert_buckets` y `policy_grants` true); `storage_buckets_missing` y `storage_policies_missing` vacíos, `receipt_upload_rule_current` true; si la 0015 fallara no aplica nada y la ventana para en la 0014, donde las páginas de hoy funcionan (probado) |
| PostgREST | Un PostgREST local en las pruebas de navegador; la puerta de versión de las páginas | La versión de Supabase y cuándo recarga su caché del esquema | Cada migración termina con `notify pgrst`; las páginas leen `canopy_schema_version` y dicen «necesita una actualización» en vez de fallar: una recarga |
| SQL Editor | Cada archivo como UNA transacción (`psql -c`, el pegado entero como una consulta) | Cómo ejecuta el Editor y si hay un tiempo máximo por consulta | Cada pegado es pequeño: cada migración tardó menos de un segundo; el reinicio, unos 9 s con 14 534 ventas (producción tiene cerca de una semana). Un pegado que falla no aplica nada |
| Páginas y sitio | Las páginas de hoy y las nuevas, en navegador, contra la copia migrada y la reiniciada | GitHub Pages en `hanginggardencafe.com`, la caché del CDN tras publicar, la recarga de cada aparato | `version.json` muestra la etiqueta; los aparatos se recargan solos (hasta 15 min) o con una recarga; la llave `anon` es pública y no cambia (`config-check` en el lint) |
| Versión del servidor | PostgreSQL 17 en CI y en la base desechable (16 en local) | 17.6 en Supabase | La misma versión mayor; SQL llano; la foto de después se compara con la del ensayo |
| Respaldo y anonimización | Cada respaldo se restaura en una base desechable y se compara; `anonimizar.sql` se detiene ante una columna que no conoce | — | El respaldo de la ventana debe decir `restauración verificada` antes de seguir |

## 4. Antes de la ventana

1. ~~Primer respaldo verificado~~ **Hecho 2026-10-14** (E-03; RESPALDOS 3.5–3.6): «Respaldo» en verde, `respaldo-cifrado`
   descargado a `Documentos/HangingGarden-Respaldos/antes-de-migraciones/`, su llave lo abre. El **de la ventana**, esa noche.
2. **Guardar el sitio de hoy** como la versión `sitio-2026-10-09` sobre la rama `gh-pages` (E-19; PUBLICAR, «Una sola vez»).
3. **Entorno `production`** en GitHub: Required reviewers = usted; etiquetas `v*` (E-20).
4. **El ensayo con los datos reales** (sección 3b): subir al repositorio privado los archivos que cambiaron (PRUEBAS los
   nombra); «Ensayo en pruebas» con la versión a lanzar, destino = `desechable`, reinicio = `si` → verde con `reinicio
   hecho`, `borrado`, `conservado idéntico` y `reset` limpio. Si la versión cambia, se repite. No hay proyecto ni sitio
   de pruebas que crear (E-13, E-14 retiradas, D-039).
5. **Ingresos personales** (INGRESOS, caso B, «Primero»): cada dueño entra con su propio ingreso en una ventana privada
   de su teléfono y cierra sesión del ingreso compartido en sus propios aparatos (nunca en los del café). Si uno no puede
   entrar, su `+dueno` con `make_owner` (pasos 1–2).
6. **El contador** confirma por escrito que el respaldo cifrado más el resumen bastan como archivo del periodo de prueba,
   cuánto tiempo guardarlos, y si alguna venta fue real y debe declararse (A-11). Mientras no responda se puede ensayar;
   el reinicio no se hace.
7. **Horas reales**, si las hubo: el encargado guarda las horas por persona desde el 2026-10-15 (sección 2).
8. **Fecha de la ventana y del conteo físico** (E-22): la ventana una noche después del cierre, con los dos dueños (cada
   uno activa su código desde su teléfono); el conteo físico de todos los insumos la mañana siguiente, antes de abrir,
   con la lista de Inventario → Existencias a mano.
9. **Las aprobaciones de la sección 8** con fecha. Yo propongo la etiqueta (`vAAAA.MM.DD-1`) sobre la versión que pasó
   las pruebas automáticas y el ensayo; usted la crea.

**Preflight (la noche misma, antes de empezar).** Si una línea no se cumple, la ventana se pasa a otra noche:
- ☐ el café cerrado y la caja cerrada en la Caja («Cerrar caja»): ningún día de caja abierto;
- ☐ ninguna venta «sin guardar todavía» en ningún aparato: abrir la Caja en cada uno, con internet, y esperar a que
  diga «todo está guardado» (el reinicio no puede ver las tabletas);
- ☐ ninguna venta ni marca del reloj en los últimos 60 minutos (el reinicio se niega si no: se espera);
- ☐ los dos dueños presentes o al teléfono, cada uno con su ingreso personal probado (punto 5) y su teléfono a mano;
- ☐ `canopy-respaldos` → Actions: la última corrida de «Respaldo» en verde (si pasaron días, «Comprobar la conexión
  (sin respaldo)» en verde esa tarde);
- ☐ las tres herramientas de solo lectura pegadas y guardadas como consultas con nombre en el SQL Editor
  (`production-snapshot.sql`, `consistency-check.sql`, `resumen-pruebas.sql`), de la versión a lanzar;
- ☐ un archivo de texto abierto para guardar cada celda con su hora; la versión a lanzar es la que pasó el ensayo.

## 5. La ventana (unos 45 minutos, después del cierre)

Todo se pega en Supabase → SQL Editor → New query, un archivo entero por consulta (GitHub → el archivo de la versión
a lanzar → Raw → copiar todo). Guarde cada celda de resultado en un archivo de texto con la hora: ninguna trae
nombres, PINs ni contraseñas. El orden es fijo: respaldo → tres celdas → reinicio → foto de después → migraciones →
revisión → ingreso del café → códigos → publicar → aparatos.

| Min | Paso | Qué hacer | Qué debe salir |
|---|---|---|---|
| 0–5 | Respaldo | `canopy-respaldos` → Actions → Respaldo → Run workflow. Esperar el verde; descargar `respaldo-cifrado`; `age -d` con su llave (RESPALDOS 3.6). Anotar la fecha y hora del trabajo (p. ej. `2026-10-16 03:12 UTC`): es la **referencia del respaldo** | Resumen: `restauración verificada: … 26 tablas`, `8 archivos verificados`, `listo: … passed`. Rojo = no se sigue |
| 5–8 | Tres celdas de antes | `production-snapshot.sql`, `consistency-check.sql` y `resumen-pruebas.sql` (los tres solo lectura) | Tres celdas guardadas: foto A, consistencia A y el **resumen** (va con el respaldo, para el contador; `cuadre_con_caja.diferencia_crc` debe ser 0) |
| 8–12 | **Reinicio** | Pegar todo `reinicio-operativo.sql`. En la última línea cambiar `RESPALDO-AAAA-MM-DD HH:MM` por la referencia del respaldo y `escriba BORRAR PRUEBAS` por `BORRAR PRUEBAS`, así: `select pg_temp.canopy_reinicio('2026-10-16 03:12 UTC', 'BORRAR PRUEBAS');` → Run | UNA celda: `reinicio hecho · respaldo …`; `borrado: …` (filas por tabla y `stock_items_a_cero`); `conservado idéntico: …` (13 nombres); `resumen del periodo …` (debe coincidir con el resumen guardado). Guardarla. Un ERROR = no cambió nada (tabla abajo) |
| 12–14 | Foto de después | `production-snapshot.sql` y `consistency-check.sql` otra vez | En `data_fingerprint` las tablas borradas dicen `0:-`; las conservadas (`menu_categories`, `menu_items`, `recipes`, `vendors`, `staff`, `app_accounts`, `app_settings`, `board_settings`, `board_group_slides`, `rooms`) tienen **la misma huella** que en la foto A; `stock_items` cambia (existencias a 0) y `audit_log` tiene una fila más; `orders_span` dice `- → -`. En consistencia, `kept`: `orders`, `items`, `bill_parts`, `part_lines`, `register_days`, `stock_moves`, `purchase_orders`, `time_entries` en 0; `staff`, `logins` y la cantidad de `stock_items` iguales |
| 14–27 | Migraciones | **0000**, 0001, 0002, … **0028**: una por consulta, en orden, cada archivo completo. Esperar *Success* antes de la siguiente | Cada una *Success* (menos de un segundo). Al **primer error**: parar, copiar el mensaje y enviármelo; ese archivo no aplicó nada (una sola transacción) y las anteriores quedan bien. «ya estaba aplicada» = seguir con la siguiente |
| 27–29 | Revisión de la versión | `release-check.sql` | `migrations_applied` de 0 a 28 (la 28 es la última), `migrations_missing`, `functions_missing` y `tables_without_rls` vacíos, `ledger.unbalanced` 0, `anon_can_run` solo `canopy_schema_version`, `order_status`, `place_room_order` y `room_lookup`; `storage_*_missing` vacíos y `receipt_upload_rule_current` true; en `settings`, lo regulado apagado (sección 1) y `confirmations` sin ninguna |
| 29–32 | Ingreso del café | `cafe-login.sql`, caso B (E-05; INGRESOS): en la línea `▶ PARTE 1` el correo **compartido** de los aparatos y su fecha `created` del seguimiento → Run | `ca***@gmail.com (creado AAAA-MM-DD) → cafe`. Los aparatos no se salen. Cualquier otro mensaje = no cambió nada: enviármelo |
| 32–35 | Código del teléfono | Cada dueño, desde **su** teléfono, en **su** ingreso personal: Inicio → tarjeta «Ingreso del propietario» → Activar (E-06). Nunca en el ingreso del café. El ingreso del contador, otro día (E-18) | El código entra; la caja y la cocina siguen con su sesión |
| 35–42 | Publicar | Releases → etiqueta `vAAAA.MM.DD-1` sobre la versión aprobada → Actions → «Publish website (PRODUCTION · manual only)» → esa etiqueta → `PUBLICAR` → aprobar la publicación (PUBLICAR). El mismo sitio y la misma dirección de siempre | `hanginggardencafe.com/version.json` muestra la etiqueta. Las tabletas se actualizan solas (hasta 15 min) o con una recarga |
| 42–45 | Aparatos | Solo mirar: la Caja carga el menú y dice «en línea» (sin vender); la pantalla de cocina abre vacía; la TV muestra la pizarra; el menú QR desde un teléfono; en el Reloj un encargado marca entrada y salida con su PIN (el único registro que deja, y es real) | Todo carga sin «necesita una actualización». La Caja no muestra ninguna venta ni ningún día de caja |

Si el reinicio responde ERROR, no cambió nada. Qué significa cada mensaje:

| Mensaje | Qué pasó | Qué hacer |
|---|---|---|
| `Esta base ya tiene migraciones aplicadas…` | Ya se pasó la 0000 | El reinicio ya no se hace; seguir con las migraciones y avisarme |
| `El reinicio operativo ya se hizo (…)` | Es la segunda vez | Nada: ya está hecho; seguir con la foto de después |
| `Falta la referencia del respaldo verificado…` | La última línea sigue con `RESPALDO-AAAA…` o vacía | Escribir la fecha y hora del trabajo «Respaldo» y Run |
| `La palabra de confirmación debe ser exactamente BORRAR PRUEBAS` | Quedó `escriba BORRAR PRUEBAS` u otra palabra | Escribir `BORRAR PRUEBAS` tal cual |
| `Hay N venta(s) de los últimos 60 minutos…` | Alguien vendió hace poco, una tableta subió una venta pendiente, o un aparato con la hora adelantada fechó una venta en el futuro | Esperar a que pase la hora, revisar las tabletas, repetir |
| `Alguien marcó en el reloj hace menos de una hora…` | Una entrada o salida en el Reloj hace poco | Esperar a que pase la hora y repetir |
| `Hay una caja abierta…` | El día no se cerró en la Caja | «Cerrar caja» en la Caja y repetir |
| `No había ventas, cajas, turnos ni movimientos de inventario que borrar…` | La base ya estaba vacía: no es la base de hoy, o el periodo ya se borró | No repetir: copiar el mensaje y enviármelo |
| `Una tabla conservada cambiaría (…)`, `La tabla … no quedó vacía`, `Un inventario no quedó en cero` | Una revisión interna del reinicio falló | No repetir: copiar el mensaje y enviármelo |

## 6. Verificación después de publicar

**Esa misma noche** (minutos 35–45 y lo que sigue):
1. `https://hanginggardencafe.com/version.json` muestra la etiqueta nueva (si muestra la vieja, esperar unos minutos:
   es la caché del CDN; no se vuelve a publicar).
2. Cada aparato se actualiza solo y **conserva su sesión**: la Caja muestra «actualización lista» y se recarga entre
   ventas; las demás pantallas, el aviso «Actualizar ahora». Si uno dice «necesita una actualización», una recarga
   (la base ya está en la 0028). Si **todos** los aparatos pidieran la contraseña a la vez, parar y avisarme (INGRESOS,
   «Después»: puede ser un código activado en el ingreso del café).
3. La Caja carga el menú y dice «en línea», sin ventas ni días de caja; la cocina abre vacía; la TV muestra la
   pizarra; el menú QR abre desde un teléfono; en el Reloj un encargado marca entrada y salida con su PIN.
4. Las celdas de la noche guardadas (foto A, consistencia A, resumen, reinicio, foto B, consistencia B, revisión).

**La mañana siguiente, antes de abrir**: (5) `release-check.sql` otra vez: el mismo resultado que en la ventana;
(6) `consistency-check.sql`: `orders_before_reset` = 0; si es mayor, una tableta subió una venta guardada desde antes
del reinicio: el encargado la anula (con PIN y motivo) y me dice de qué aparato salió; (7) el **conteo físico** y luego,
en Inventario → Existencias → «Contar», la cantidad real de cada insumo (están en 0 hasta ahí). Lo hace un encargado
con su PIN; cada conteo queda como ajuste en el historial.

**El primer día (la prueba de operación, con el café real)**:
8. **Abrir la caja** con el fondo contado: Caja → «Abrir caja» → «Fondo de caja recibido (₡)» (y dólares, si hay) →
   «Quién abre» con PIN. **Tipo de cambio** del día en Inicio → Ajustes (hasta que E-16 lo automatice).
9. **Las primeras ventas reales son la prueba**: una en efectivo con vuelto (la ventana de billetes), una con tarjeta,
   una con un billete de dólar; la cocina recibe los tiques y los marca; la pizarra de TV sigue. Una **cuenta abierta
   pagada en partes**; un **descuento con PIN** y motivo; una **anulación con PIN** y motivo (del mismo día; una venta
   de un día ya cerrado se «Devuelve»). Reimprimir un recibo (COPIA). Si una tableta pierde internet, la venta se
   guarda y se sube al volver: nunca repetirla.
10. **Cerrar la caja** en ₡ y $: efectivo con el fondo, total del datáfono, dólares; la diferencia debe ser la esperada.
11. **Por la noche**: Inicio muestra «Final» con las ventas del día; Información → «Para revisar» (las marcas del día:
    ventas sin nombre, métodos o estados desconocidos, cuentas sin pagar, diferencias de caja) y Contabilidad →
    Efectivo. Planilla, libros y Hacienda siguen apagados: nada se asienta ni se envía.
12. **El encargado vigila** cada día de la primera semana: «Para revisar» en Información, la diferencia de caja al
    cierre y los turnos abiertos en el Reloj. **Para avisar de un fallo**: la página, la hora, el aparato, el mensaje
    exacto (una foto de la pantalla, sin PINs ni contraseñas) y qué se estaba haciendo. Una venta ya tomada nunca se
    pierde: el servidor la anota y la marca para el encargado. Me lo envía y preparo la corrección (una migración
    nueva o una versión nueva); nunca un borrado.

## 7. Cómo volver atrás

En este plan **no hay un segundo proyecto**: todo pasa en la base de hoy y en el sitio de hoy, y cada paso tiene su
propia vuelta atrás sin mover datos a ningún lado.

- **Antes del reinicio** (respaldo, tres celdas): nada cambió en producción. Se puede parar sin consecuencias.
- **Un reinicio que respondió ERROR**: no cambió nada (una sola transacción). Se corrige la causa o se para.
- **Después del reinicio**: los datos de prueba solo vuelven restaurando el respaldo de la ventana en un proyecto
  **NUEVO y temporal**, que se borra después (RESPALDOS, «Desastre»; nunca encima de producción). Nadie lo necesita
  para operar: son datos de prueba, y el respaldo queda como archivo. Las existencias en 0 se cargan con el conteo.
- **Una migración que falló**: ese archivo no aplicó nada; las anteriores quedan y las páginas de hoy funcionan con
  ellas (probado con la base en la 0014 y en la 0025). Me envía el mensaje y preparo la corrección. La tabla
  «Reversión» de `docs/LANZAMIENTO.md` dice cómo quitar cada una si hiciera falta; nunca borrando datos.
- **Las páginas**: publicar la etiqueta anterior o, para el sitio de hoy, `restaurar = sitio-2026-10-09` (PUBLICAR,
  «Volver a la versión anterior»). Las páginas de hoy funcionan con la base migrada y vacía (ensayo). La dirección del
  sitio no cambia en ningún caso.
- **El ingreso del café**: `select public.make_owner('el correo');` lo devuelve a dueño (INGRESOS). Los interruptores
  regulados ya están apagados: no hay nada que apagar.
- **Desastre** (el último recurso, que este plan está hecho para no necesitar nunca): solo si producción se perdiera,
  el respaldo cifrado se restaura en un proyecto **NUEVO** (RESPALDOS, «Desastre»: los ingresos se crean a mano, luego
  `website/config.js` y publicar), y solo con su autorización expresa. Ningún paso de la ventana lo requiere.

## 8. Aprobaciones del dueño

Cada línea se aprueba por separado y por escrito (en el chat basta), con fecha. Nada de la sección 5 se ejecuta sin
la suya; yo no toco producción ni publico nada.

| # | Aprobación | Qué autoriza | Fecha |
|---|---|---|---|
| 1 | El reinicio operativo y la excepción a la regla «nunca borrar registros» (CLAUDE.md, D-038); el mismo proyecto y el mismo sitio, sin segundo proyecto (D-039) | Preparar y ensayar el reinicio; que usted lo ejecute una vez en la ventana, en la base de hoy | ☑ 2026-10-14 (la decisión y su revisión) |
| 2 | Los respaldos | El primer respaldo verificado (E-03), descargado y comprobado con su llave; el respaldo de la ventana, igual, esa noche | ☑ 2026-10-14 el primero · ☐ el de la ventana |
| 3 | El pegado del reinicio | `reinicio-operativo.sql` en producción, con la referencia del respaldo y `BORRAR PRUEBAS`, después del resumen | ☐ |
| 4 | Las migraciones 0000–0028 | Una por una en el SQL Editor de producción, en la misma ventana | ☐ |
| 5 | El ingreso del café | `cafe-login.sql`, caso B, sobre el ingreso compartido (E-05) | ☐ |
| 6 | Los códigos del teléfono | Cada dueño en su ingreso personal, desde su teléfono (E-06) | ☐ |
| 7 | Publicar la etiqueta | Crear `vAAAA.MM.DD-1` y correr «Publish website» con PUBLICAR; usted aprueba la publicación (E-20) | ☐ |

Pendiente de terceros: la confirmación del contador (A-11) y la fecha de la ventana y del conteo físico (E-22). El
ensayo con los datos reales (sección 3b) lo corre usted cuando quiera: lee producción con la cuenta de solo lectura,
como el respaldo, y no deja nada fuera del trabajo.
