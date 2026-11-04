# Ensayo en pruebas de Canopy OS (sin proyecto de pruebas)

**Para qué sirve:** ensayar, con una copia **anonimizada** de los datos reales, exactamente lo que usted hará en la
ventana del lanzamiento único (docs/LANZAMIENTO-UNICO.md, D-038): el reinicio operativo (solo en una copia de antes de la 0000) y las migraciones que falten
(hoy producción tiene 0000–0029; la versión a ensayar trae la 0030, la 0031 y la 0032), con los mismos archivos y en el mismo
orden, antes de tocar producción. Producción solo se **lee**.

**Decisión del dueño (2026-10-14):** el café se queda con su proyecto actual de Supabase y su sitio actual; **no se
crea un segundo proyecto de Supabase** ni se migra la base a otro lado. Por eso el ensayo corre, por defecto, en una
**base temporal dentro del trabajo de GitHub** (destino `desechable`): un PostgreSQL que el propio trabajo levanta,
se hace parecer a Supabase (`restore-stub.sql`: cuentas anon/authenticated/service_role, esquemas auth y storage,
permisos por defecto) y desaparece al terminar. No hay nada que crear, pagar ni pausar, y no queda ninguna copia.

| | Producción | Ensayo (destino `desechable`) |
|---|---|---|
| Sitio | hanginggardencafe.com (no cambia) | ninguno: las páginas se prueban en CI contra la misma clase de copia (`tests/rehearsal/reset-pages.sh`) |
| Base | proyecto actual de Supabase (no cambia) | base «pruebas» en el PostgreSQL temporal del trabajo; desaparece al terminar |
| Datos | los reales | anonimizados: "Persona N", huéspedes sin nombre ni teléfono, sin notas ni ingresos; PIN 2468 |
| Quién la toca | usted, en la ventana | el trabajo de GitHub, con el botón; nadie entra ni ve la copia |

Cómo se garantiza que el ensayo no toque producción:

- `ensayo.sh` lee producción solo con la cuenta de **solo lectura** `canopy_backup` (se niega con cualquier cuenta
  que pudiera escribir) y se niega si la dirección de destino contiene el proyecto de producción o si la base
  desechable fuera un proyecto de Supabase.
- La copia se anonimiza en el PostgreSQL del trabajo **antes** de cargarse en cualquier parte (`anonimizar.sql`) y los
  archivos con datos reales se borran al terminar, también cuando un paso falla. El registro muestra pasos, cantidades
  y tiempos: ni filas, ni el PIN, ni contraseñas.
- Los archivos SQL del repositorio público (reinicio, migraciones, revisiones) llegan a la base como texto, con
  `psql -c`: ningún comando de psql ni de la terminal escrito en ellos se ejecuta en el trabajo.

Qué datos entran en la copia: montos, cantidades, fechas, menú e inventario, tal cual. Nombres del personal,
huéspedes, proveedores, teléfonos, correos, notas, motivos, descripciones, referencias, nombres de los aparatos,
ingresos y llaves se reemplazan antes (`anonimizar.sql`). Si una versión nueva agrega una columna de texto que
`anonimizar.sql` no conoce, el ensayo se detiene antes de copiar nada y la nombra.

## Cuándo

- **Después del primer respaldo verificado** (E-03): usa el mismo repositorio privado y su cuenta de solo lectura.
- **Antes de la ventana del lanzamiento único**, obligatorio, con `reinicio = si` y la etiqueta que se va a lanzar.
  Si la versión a lanzar cambia, se repite: cuesta unos cinco minutos y no deja nada.

## Instalación (una sola vez, unos 10 minutos)

Requisito: el repositorio privado `canopy-respaldos` con su respaldo en verde (docs/RESPALDOS.md). **No hace falta
ningún secreto nuevo**: producción se lee con `CANOPY_DB_URL` y la variable `SUPABASE_URL`, que ya están.

1. Suba (reemplazando) al repositorio privado estos archivos de `ops/backup/repositorio-respaldos/`:
   `.github/workflows/ensayo-pruebas.yml`, `ensayo.sh`, `anonimizar.sql` y `restore-stub.sql`. El flujo y `ensayo.sh`
   cambiaron el **2026-10-14** (la opción `reinicio` y el destino `desechable`); `anonimizar.sql`, también el
   **2026-10-14** (las columnas de planilla de la 0026; la copia que usted subió esa noche, antes de la corrida #2, ya
   es esa); `restore-stub.sql`, el 2026-10-13 (si los subió después de esas fechas, ya están al día). `ensayo.sh` cambió otra vez
   la **noche del 2026-10-14**, después del primer ensayo con los datos reales: solo su registro (sin las líneas `grep:
   write error: Broken pipe` ni los avisos de la base auxiliar donde se anonimiza; los `NOTICE: … does not exist,
   skipping` de las migraciones siguen y son normales); el flujo no cambió. La comparación (`compare.py`) viene del
   repositorio público en la versión que usted elige: no hay que subirla.
2. Nada más. El secreto `STAGING_PIN` es opcional para este destino: sin él, todas las personas de la copia quedan con
   el PIN `2468` (en una base desechable nadie entra). `STAGING_DB_URL` solo existe para la última sección.

## Ensayo

`canopy-respaldos` → **Actions → Ensayo en pruebas → Run workflow** → versión: la etiqueta o rama a lanzar →
destino: `desechable` → vaciar: `no` → reinicio: `no` (desde el lanzamiento la copia ya está migrada; `si` solo valía
para una copia anterior al reinicio, D-038, y el guion se detiene si se elige con una copia migrada). Al terminar (unos
5 minutos) debe estar en **verde**.
(`vaciar` solo tiene sentido con un proyecto de pruebas: la base desechable nace vacía.)

Qué hace, en orden, dentro del trabajo:

1. Levanta un PostgreSQL 17 temporal, crea en él la base «pruebas» y la hace parecer a Supabase (`restore-stub.sql`;
   sin el depósito de fotos del menú, como un proyecto de pruebas).
2. Copia producción con la cuenta de solo lectura, la anonimiza en otra base del mismo servidor y carga la copia en
   «pruebas» con los permisos de producción (si quedaran distintos, se detiene). Toma la foto y la revisión de
   consistencia ANTES (`snapshot-before.json`, `consistency-before.json`).
3. Con reinicio = `si`, antes de las migraciones:
   - **cierra el café en la copia**: la copia se toma mientras el café trabaja, y el reinicio se niega con una venta o
     una marca del reloj de la última hora o una caja abierta (como hará en producción); en la copia, esas ventas y
     marcas se fechan dos horas antes y la caja abierta se cierra. El registro dice cuántas (`café cerrado en la copia:
     N venta(s)…, N caja(s)`);
   - guarda el **resumen del periodo para el contador** (`resumen-pruebas.sql` → `resumen.json`), como usted lo
     guardará con el respaldo antes del reinicio real;
   - ejecuta **`reinicio-operativo.sql` tal cual**, con la referencia `ensayo <fecha y hora UTC>` y la palabra
     `BORRAR PRUEBAS` en la última línea (lo mismo que usted escribirá a mano), enviado como una sola consulta; debe
     responder `reinicio hecho`, si no, el ensayo se detiene;
   - toma otra foto y revisión (`snapshot-after-reset.json`, `consistency-after-reset.json`).
4. Aplica las migraciones que falten (hoy 0030–0032; en la copia de antes del lanzamiento, 0000–0032) una por una, como un pegado en el SQL Editor, y anota cuánto tardó cada una
   (`timings.txt`); foto y revisión DESPUÉS; `release-check.sql` (`release-check.json`).
5. Compara (`compare.py`, modo `reset`): las 14 tablas que el reinicio borra deben quedar **vacías**, las 10 que conserva
   **idénticas** (huella por huella), las existencias en cero y la bitácora con una línea más; luego, lo que quedó
   **justo después del reinicio** debe ser idéntico a lo que hay **después de las migraciones** (ventas, caja, inventario
   en cero, horas, personal, bitácora), y la estructura, las reglas de filas, los permisos y los interruptores deben ser
   los esperados (todo lo regulado apagado y sin confirmaciones: la copia del reinicio es siempre de antes de la 0000).
   Una tabla que en producción **nunca tuvo filas** (por ejemplo `order_part_lines`
   si ninguna cuenta se dividió por platos, o `tab_adds`) no es un error: la comparación la nombra en su línea `reset:`
   («no rows in the copy of production, nothing to clear»), igual que las tres tablas de llaves de desbloqueo que
   `anonimizar.sql` vacía antes de que la copia salga del trabajo. Que el reinicio borre de verdad cada una de las 14
   tablas lo prueba CI sobre la copia sintética, donde todas tienen filas (`compare.py … reset fixture`). Con
   reinicio = `no` compara ANTES con DESPUÉS y exige `unchanged: … original tables`; sobre una copia de producción ya
   migrada conserva e informa los interruptores de producción («production's own switches, unchanged by the window: …»,
   los libros encendidos y el catálogo aprobado incluidos) y solo cuenta un cambio ocurrido en la ventana (D-058).
6. El trabajo termina y el PostgreSQL temporal desaparece con la copia.

Qué leer, en el registro del paso «Copiar, anonimizar, cargar…»:

- `reinicio hecho · respaldo ensayo …`;
- `borrado: …`: filas borradas por tabla (`orders`, `order_items`, `register_days`, `time_entries`, `stock_moves`,
  `purchase_orders`…) y `stock_items_a_cero` (cuántos insumos tenían existencias y quedaron en 0);
- `conservado idéntico: …`: menú, recetas, insumos, proveedores, personal, ingresos, ajustes, pizarra, habitaciones y
  bitácora, con huellas iguales antes y después del reinicio;
- el tiempo de cada migración (las líneas `NOTICE: … does not exist, skipping` entre una y otra son normales: cada
  migración quita antes lo que va a crear, y en una copia nueva no existe) y, en el paso siguiente, la comparación
  (también en el resumen del trabajo): `reset: 14
  tables cleared (N had rows; …), 10 kept byte for byte, N stock items at zero, N log lines (one new); then the
  migrations:` y debajo `unchanged: …`. El paréntesis dice cuántas tablas tenían filas y nombra las que no: las que el
  café nunca usó («no rows in the copy of production») y las tres de llaves que vacía `anonimizar.sql`.

En **Artifacts** (`ensayo-resultados-desechable`) quedan `resumen.json` (el resumen del periodo: cantidades y totales
por día y por medio de pago, sin nombres), `reinicio.txt` (la respuesta completa del reinicio), las fotos y revisiones
de antes, de después del reinicio y de después de las migraciones, `release-check.json` y `timings.txt`. Ninguno trae
datos de personas: solo cantidades, totales y huellas. Las cifras de `resumen.json` son las de la copia anonimizada
(los montos y las fechas son los reales; los nombres no viajan). Guarde `timings.txt`: es la referencia de cuánto
tardará cada pegado en la ventana.

Si queda en **rojo**: el mensaje en rojo dice el paso y nunca muestra datos; mándemelo tal cual. Si el paso rojo es la
comparación, cada línea `DIFFERENCE: …` es una diferencia concreta (una tabla que debía quedar vacía y no quedó, una
conservada que cambió, una migración que cambió algo): mándemelas todas. (El primer ensayo con los datos reales, el
2026-10-14, se detuvo aquí por una expectativa de la copia sintética, no por un fallo del reinicio: `order_part_lines`
no tenía filas en producción; desde esa noche eso se informa y no detiene.)
Con `el reinicio operativo se negó en PRUEBAS`, la línea `ERROR` de arriba dice el motivo, el mismo que daría en
producción (ya migrada, ya hecho, una venta reciente, una caja abierta, una tabla conservada que cambiaría): en la copia
no cambió nada. Con `la copia en PRUEBAS ya tiene migraciones`, producción ya pasó la ventana: corra el ensayo con
reinicio = `no`. Con `anonimizar.sql no sabe si estas columnas guardan datos de personas: …`, la versión trae una
columna de texto nueva: no se copió nada; es trabajo mío, no suyo.

## Qué prueba este ensayo y qué no

Lo que **sí** prueba, sobre la copia anonimizada de los datos reales (CI lo prueba además en cada cambio sobre una
copia sintética de cuatro meses y 14 534 ventas, `tests/rehearsal/run.sh`):

- que `reinicio-operativo.sql` acepta la base real tal como está hoy (o dice por qué no, con el mismo mensaje que daría
  en producción), borra lo que debe y conserva idénticos menú, recetas, insumos, proveedores, personal, ingresos,
  ajustes, pizarra, habitaciones y bitácora (que borra de verdad cada una de las 14 tablas, también las que en
  producción están vacías, lo prueba CI, donde la copia sintética las tiene todas con filas);
- que las 29 migraciones corren en orden sobre esa base, cuánto tarda cada una, y que después de ellas nada de lo que
  quedó cambió (`compare.py`, modo `reset`);
- la estructura resultante, las reglas de filas (RLS) y los permisos de `anon`, `authenticated`, `service_role` y
  `canopy_backup` después de las migraciones (`release-check.sql`: `anon_can_run`, `tables_without_rls`…), y que lo
  regulado llega apagado (la copia del reinicio es siempre de antes de la 0000; con reinicio = `no` sobre producción
  ya migrada, los interruptores de producción se conservan e informan, D-058);
- que la copia de producción se restaura con permisos idénticos a los de producción (si no, el ensayo se detiene),
  con la misma imitación de Supabase (`restore-stub.sql`) que verifica el respaldo nocturno.

Lo que un PostgreSQL local **no puede** probar; queda para la ventana y su verificación posterior
(docs/LANZAMIENTO-UNICO.md):

- **Supabase Auth** (GoTrue): los ingresos, la inscripción del código del teléfono (cierra las otras sesiones del
  mismo ingreso), el correo de recuperación, las sesiones reales de los iPads. La copia no trae `auth` (la cuenta de
  respaldo no lo lee).
- **Supabase Storage** por dentro (storage-api, los permisos `policy_grants` de supautils): en la base desechable las
  reglas de `storage.objects` las crea el superusuario del servidor temporal, que permite **más** que producción. Las
  sentencias de Storage de 0015 y 0025 son el riesgo residual; la consulta de seguimiento del 2026-10-13 confirmó que
  la cuenta de producción puede crear depósitos y reglas allí (`can_insert_buckets` y `policy_grants` verdaderos).
- La versión de **PostgREST** de Supabase y el tiempo que tarda en recargar su caché del esquema (las migraciones
  envían `notify pgrst`).
- El **SQL Editor**: cómo ejecuta un pegado y si corta por tiempo. Referencia: cada migración tardó menos de un segundo
  en el ensayo; el reinicio, unos 9 s sobre 14 534 ventas sintéticas y menos de un segundo con las 35 ventas reales
  (corrida del 2026-10-14); producción tiene cerca de una semana.
- Los permisos por defecto del rol `supabase_admin` (la copia restaura solo los de `postgres`).
- **GitHub Pages**: el dominio hanginggardencafe.com y la caché del CDN después de publicar (la verja de versión
  `canopy_schema_version` hace que una página vieja diga que necesita actualizarse, sin romper nada).
- La llave `anon` real (pública, en `website/config.js`; no cambia).
- PostgreSQL **17.6** en Supabase frente a 17 en el trabajo de GitHub (16 en la computadora de desarrollo).
- En la base desechable las migraciones corren como **superusuario** del servidor temporal. Que corren también como
  la cuenta del SQL Editor, que no lo es, lo prueba CI en cada cambio (`tests/rehearsal/as-supabase.sql`).

## Pruebas automáticas de los descuentos de Caja (0038, D-065)

No son parte del ensayo: corren con `tests/run.sh` (y en GitHub en cada cambio) sobre la base de prueba local, nunca
sobre producción. Una línea por archivo:

- `tests/sql/480_descuentos.test.sql`: las cuatro categorías con la tasa y el nombre que fija el servidor y la regla de
  la tabla que impide otra; la identificación solo por el código; Empleado con los dos códigos en una llamada, nunca
  para sí mismo ni para el dueño; Guía Turista apagada (y encendida solo en la prueba), solo con el código del dueño,
  que no abre las áreas del dueño ni toca ningún contador de PIN (ajuste 1); un código compartido no autoriza a nadie;
  la ventana anterior detrás de `pos_free_discount` y los motivos que se leen como una categoría; permisos; los datos
  viejos intactos.
- `tests/sql/482_descuentos_cupo.test.sql`: el descuento diario de Empleado (ajuste 3): la venta cobrada lo gasta y
  vuelve solo con una anulación válida; «Devolver el cupo del día» solo para uno que no cobró nada (y cada negativa);
  una autorización sin usar vence a los 30 minutos o se suelta (y si una venta marcada `discount_daily_twice` esperaba
  ese día, lo toma ella); cancelar o quitarlo de una cuenta sin pagos no lo devuelve por sí solo (espera «Devolver el
  cupo del día», también si la cuenta se anula después), con pagos o con un reembolso nunca vuelve; un error dentro del
  disparador no hace fallar una anulación, un pago, una cancelación ni la cocina (un error de candado sí: la anulación
  se deshace entera y se repite, `concurrency-descuentos.sh` 5).
- `tests/sql/484_descuentos_cuentas.test.sql`: el descuento en una cuenta abierta (toda la cuenta, solo antes de
  cualquier pago, nunca sobre un combo ni sobre otro descuento), el mismo pedido enviado dos veces, quitarlo sin pago y
  después de un pago (PIN de encargado), la × de la página anterior (W3), quitar un descuento tardío solo si la cuenta
  todavía lo lleva (no el que otra tableta puso después); en el ticket, una venta que no coincide queda registrada con
  una marca, nunca rechazada.
- `tests/sql/485_descuentos_cajas.test.sql`: el control de códigos equivocados («Cajas registradas en puestos», ajuste
  2): solo una caja registrada prueba códigos; tres puestos con su propia cuenta, las esperas y la detención con 12 en
  24 horas (también después de una primera detención: nunca más de 12 en 24 horas); reanudar con los topes; la llave
  del aparato después de cerrar sesión, también cuando se perdió la respuesta; los topes por persona; una persona
  bloqueada en las listas de nombres sigue autorizando en la ventana (regla 5); un texto larguísimo no cuesta más que
  uno corto (un límite de tiempo no distingue un código correcto de uno equivocado); ningún PIN, código ni llave en la
  bitácora (y quién comparte un código, solo para el dueño: un encargado no lo lee en la bitácora); una simulación de
  24 horas.
- `tests/sql/486_descuentos_informe.test.sql`: el informe `descuentos_informe`: quién lo puede leer (también el
  contador), el estado de cada descuento, lo cobrado y los productos cubiertos, los totales, las cortesías por tasa de
  IVA (solo información) y el bloque «Códigos equivocados»; el valor de lista según las líneas que quedan en la cuenta
  (una línea quitada lo baja); el descuento que conservó una cuenta al quitárselo después de un pago (valor de lista
  − descuento = cobrado); las ventas sin verificar con su estado, su caja y lo que de verdad cobraron; y que el
  informe busque las quitas después de un pago por su índice (nunca recorre todo el registro por cada aprobación).
- `tests/sql/490_descuentos_iva.test.sql`: el IVA y la contabilidad: la cortesía a ₡0 con su valor de lista (IVA 0,
  neto 0), la caja, los asientos, los reportes de IVA, la anulación y el reembolso; una venta sin verificar conserva su
  descuento real; la 0038 no toca ninguna regla fiscal.
- `tests/sql/500_reversion_0038.test.sql`: `reversion-0038.sql` (las tres funciones anteriores idénticas, ningún dato
  borrado, la 38 fuera del registro) y la 0038 aplicada otra vez (las cajas vuelven con sus puestos, llaves y cuentas).
- `tests/sql/concurrency-descuentos.sh`: con dos conexiones a la vez, en una base propia: diez códigos equivocados
  simultáneos de una caja (se prueban exactamente tres); con los candados de los puestos ocupados, una caja detenida,
  un aparato sin registrar y otro puesto contestan igual; ningún bloqueo mutuo entre la ventana, `pin_lock_clear` y dos
  cajas; el único que queda (`tab_remove_item` contra un descuento en la misma cuenta, con el mismo código de
  encargado) termina una de las dos llamadas con 40P01, que se deshace entera, y el segundo intento pasa; una anulación
  toma el candado del empleado antes que el inventario. Lo corre `tests/run-sql.sh` después de los archivos SQL cuando
  no se le da un patrón.
- `tests/e2e/specs/400_descuentos.spec.js`: la ventana «Aplicar descuento» en una caja registrada: su diseño fijo en
  cuatro tamaños de pantalla y en los dos idiomas, cada mensaje de su línea a 360 × 640, los códigos (solo puntos,
  nunca guardados ni enviados vacíos), los cuatro descuentos de punta a punta (el ticket, el total, la venta ligada en
  el servidor), Guía Turista apagada, nunca dos descuentos, las líneas fijas, una cuenta, una recarga, y el ajuste 1:
  el código del dueño para una cortesía no abre nada.
- `tests/e2e/specs/401_descuentos_cuentas.spec.js`: los descuentos en cuentas («Cobrar después»): toda la cuenta,
  quitarlo sin nada pagado y después de un pago, «Devolver el cupo del día», un encargado que es el beneficiado, una
  parte pagada en otro aparato, la cortesía a ₡0, una cuenta cobrada, anulada y cancelada, y respuestas perdidas o
  lentas; el cupo de Empleado sigue usado hasta una anulación válida o la devolución de un encargado (ajuste 3); y un
  interbloqueo (40P01) en una cuenta: autorizar, × y «quitar uno» se mandan una vez más tras una espera corta y pasan;
  dos seguidos muestran el error de siempre sin cambiar nada. También: después de Cancelar, el segundo intento va sin
  códigos; una cuenta cuya respuesta se perdió no recibe un intento nuevo mientras su repetición no tenga respuesta;
  una respuesta tardía en una tableta no quita el descuento que otra tableta puso en la misma cuenta; lo tocado para
  una cuenta que se cerró no se suma a un pedido con descuento; y «Devolver el cupo del día» sigue a mano con más de
  40 filas nuevas en la bitácora.
- `tests/e2e/specs/402_descuentos_cajas.spec.js`: las cajas registradas (ajuste 2): registrar un aparato en la
  Bitácora, la llave que lo trae de vuelta a su puesto sin PIN, la línea de «¿Qué dispositivo es este?», la cuenta de
  códigos equivocados de cada puesto (las esperas, la detención, reanudar), la regla 5, los topes por persona
  («Reemplazar con este dispositivo»), cada texto de estado y de espera a 360 × 640, que una persona en una tableta
  no pueda detener los descuentos de las demás cajas, la alerta del café con su propia hora y cuenta, y la respuesta
  perdida de la vuelta por la llave o de «Registrar este dispositivo»: la página lo marca pendiente (sin PIN ni
  llave), pregunta otra vez, guarda la llave nueva y el próximo ingreso vuelve al mismo puesto.
- `tests/e2e/specs/403_descuentos_informes.spec.js`: los descuentos en los informes, los libros y el inventario: lo
  escrito (la empresa del guía) queda como texto en Ventas, la bitácora y los CSV; «Descuentos por categoría» con sus
  resúmenes, la línea de las cortesías por tasa de IVA y cada estado; lo que ve el contador; los dos ajustes en Inicio
  (Guía Turista apagada, con su candado); una venta sin verificar con su caja y su día de Costa Rica (una venta a las
  18:30 no pasa al día siguiente), y lo que de verdad cobró una venta sin verificar anulada o cancelada (₡0); un
  informe que no responde a tiempo lo dice en Ventas y en el paquete del contador (`descuentos-NO-INCLUIDO.txt`); y
  una venta con descuento y una cortesía frente a la misma venta sin descuento: los mismos movimientos de inventario,
  el cierre de caja (la cortesía como «otro» en ₡0), el asiento diario todavía apagado (A-07) y el IVA sobre el monto
  con descuento.
- `tests/e2e/specs/404_descuentos_red.spec.js`: los descuentos con mala red, sin conexión y en carreras: sin conexión
  la ventana se niega y nada se aplica; una venta guardada sin conexión con su descuento sube ligada (también tras una
  recarga) y nunca se suelta; una respuesta perdida se pregunta otra vez con el mismo número de solicitud, y si se
  pierden las dos la aprobación se suelta por ese número; dos cajas a la vez con Empleado para la misma persona (una
  sola aprobada); una anulación en Pedidos devuelve el día; un intento mandado dos veces a la vez da la misma
  aprobación; una respuesta lenta que llega después de Cancelar nunca llega al ticket; y sin descuento la Caja vende
  con y sin conexión como antes, y el servidor nunca rechaza dinero cobrado. También: dos pestañas de la Caja en el
  mismo aparato nunca sueltan el descuento vivo de la otra, y un pedido «Cobrar después» cobrado en el aparato imprime
  el nombre de su categoría.

Las pruebas SQL corren en el servidor local con el idioma `C.UTF-8`; GitHub usa `postgres:17`, que ordena el texto en
`en_US.UTF-8` (otro orden para `_`). Para correrlas igual que GitHub, en un servidor propio de prueba:
`CANOPY_PG_DIR=/tmp/canopy-test-pg-en CANOPY_PG_PORT=55433 CANOPY_PG_LOCALE=en_US.UTF-8 tests/run-sql.sh` (las listas
que comparan las pruebas van en orden de bytes, `collate "C"`; `tests/lint.sh` regla 16 lo revisa en
`release-check.sql`).

En el ensayo de CI (`tests/rehearsal/after-window.sql`), el día después de la ventana con la 0038: la ventana anterior
con el ajuste encendido, un motivo que se lee como categoría rechazado, una caja registrada, un descuento de categoría
cobrado tarde (con su marca) y el ajuste apagado y encendido con las dos herramientas del dueño; `compare.py` espera
`pos_free_discount` encendido y `pos_discount_guia` apagado.

## Si algún día quiere un proyecto de pruebas permanente

El dueño decidió el 2026-10-14 **no** crear un segundo proyecto de Supabase (la experiencia de cambiar de base en otro
proyecto pesó más que la comodidad). Esta sección queda por si cambia de idea: con un proyecto de pruebas, el mismo
ensayo corre con destino `proyecto-pruebas`, y además se puede navegar la copia desde un sitio de pruebas.

### 1 · Proyecto de pruebas en Supabase (gratis)

1. Vea el plan de la organización del café (Supabase → la organización → **Billing**; E-10):
   - **Free**: el plan gratis da **dos proyectos gratis activos**, sumando todas las organizaciones donde usted es
     Owner o Administrator (los pausados no cuentan). Pruebas es el segundo: si ya tiene otro proyecto gratis
     activo (que no sea el del café), páuselo antes o Supabase no deja crear este. **Nunca pause el proyecto del café**:
     la caja dejaría de guardar ventas en el sistema.
   - **Pro** (u otro de pago): cada proyecto de esa organización se cobra aparte (unos US$10 al mes). Cree primero
     una organización nueva en plan **Free** (por ejemplo `canopy-pruebas`) y el proyecto dentro de ella.
2. **New project** → nombre `canopy-pruebas`, la **misma región** que producción (la muestra el proyecto de
   producción en **Project Settings → General**).
3. Contraseña de la base: use **Generate a password** (solo letras y números; una propia con `@ # / ? %` rompe la
   dirección del paso 2) y guárdela en su gestor de contraseñas. No la comparta.
4. **Security**: compruebe que **Enable Data API** y **Automatically expose new tables** estén marcados (márquelos si
   no lo están) y **Enable automatic RLS** desmarcado, como producción (que se creó antes de estas opciones). La RLS
   automática agrega una función que producción no tiene y el ensayo se detendría: "PRUEBAS quedó con permisos
   distintos de producción".
5. En el proyecto nuevo: **Authentication → Sign In / Providers** → apague **Allow new users to sign up** y deje
   apagado **Allow anonymous sign-ins**.

(El plan gratuito pausa un proyecto después de una semana sin uso: se reactiva con **Restore** en el panel.)

### 2 · Secretos del ensayo (repositorio privado `canopy-respaldos`)

**Settings → Secrets and variables → Actions → New repository secret**:

- `STAGING_DB_URL`: proyecto de **PRUEBAS** → **Connect** → **Connection String** → **Session pooler** → copie la
  dirección (empieza con `postgresql://postgres.<ref-de-pruebas>:` y termina en `pooler.supabase.com:5432/postgres`),
  cambie `[YOUR-PASSWORD]` por la contraseña del punto 1.3 y agregue al final `?sslmode=require` (si ya trae un `?`:
  `&sslmode=require`). No la "Direct connection": GitHub no la alcanza (docs/RESPALDOS.md, paso 3.4).
- `STAGING_PIN`: un número de 4 a 8 dígitos que solo se usa en pruebas, distinto de todo PIN real (todas las
  personas lo tendrán allí). Con un proyecto de pruebas es obligatorio.

Primera copia: **Ensayo en pruebas** → destino `proyecto-pruebas` → vaciar `no` → reinicio `no`; debe quedar en verde
con **unchanged: … original tables**. Para repetir desde cero más adelante: vaciar = `si` (solo vacía **pruebas**).
Para el ensayo del lanzamiento: vaciar `si`, reinicio `si` (las dos opciones son independientes).

### 3 · Ingresos de pruebas

1. Proyecto de **PRUEBAS** → **Authentication → Users → Add user → Create new user**, marcando
   **Auto Confirm User**:
   - `cafe.pruebas@hanginggardencafe.com`
   - `dueno.pruebas@hanginggardencafe.com`
   (contraseñas nuevas, solo suyas)
2. Proyecto de **PRUEBAS** → **SQL Editor** → pegue todo `supabase/tools/staging-logins.sql` → Run.
   Si por error lo pega en producción, se niega (producción tiene nombres reales e ingresos que no son de pruebas).
   Cada copia llega sin ingresos: repítalo después de cada ensayo con ese destino.

### 4 · Sitio de pruebas

1. GitHub → **New repository** → `canopy-pruebas` → **Public** (GitHub Pages gratis lo pide; solo contiene
   código que ya es público).
2. Suba el contenido de `ops/staging/repositorio-pruebas/` (incluida la carpeta `.github`).
3. **Settings → Secrets and variables → Actions**:
   - pestaña **Variables** → `STAGING_SUPABASE_URL`: proyecto de PRUEBAS → **Connect** → *Project URL*
     (`https://<ref-de-pruebas>.supabase.co`).
   - pestaña **Secrets** → `STAGING_SUPABASE_ANON_KEY`: proyecto de PRUEBAS → **Project Settings → API Keys**,
     pestaña *Legacy* → **anon public** (empieza con `eyJ`). Nunca la *service_role* ni una *secret*
     (`sb_secret_…`). Va como secreto aunque es pública: así no aparece en el registro, que aquí ve cualquiera.
4. **Actions → Publicar el sitio de PRUEBAS → Run workflow** (versión: la rama de desarrollo): crea `gh-pages`.
5. **Settings → Pages** → Source: **Deploy from a branch** → `gh-pages` / `(root)` → Save.
6. Corra el paso 4 **otra vez**: la primera publicación con la llave de GitHub no enciende el sitio.
7. Abra `https://jeanpaulcocaleca-create.github.io/canopy-pruebas/pos`: abajo a la izquierda debe verse la
   etiqueta naranja **PRUEBAS · no es la caja real**. Entre con `cafe.pruebas@…`.

Garantías de ese sitio: `website/config.js` decide la base por la dirección del sitio y la dirección de pruebas
**solo** puede usar el proyecto de pruebas (si alguien pusiera ahí la dirección o la llave de producción, la página se
bloquea; `tests/tools/config-check.js`); el publicador de pruebas (`poner-pruebas.py`) se niega con la dirección de
producción, una llave que no sea la pública `anon` o la llave de otro proyecto. Las fotos del menú y los videos no se
copian: el menú de pruebas muestra las fotos públicas de producción y subir una foto allí no funciona. Pruebas no envía
nada a Hacienda. Con el sitio, la lista de verificación de docs/LANZAMIENTO.md se puede recorrer sobre el **café
vacío** que deja el reinicio: abrir la caja, una venta completa, un conteo de inventario, el reloj. La prueba de
restauración trimestral (docs/RESPALDOS.md) carga datos **reales** en pruebas: al terminarla, corra el ensayo con ese
destino y vaciar = `si`, y `staging-logins.sql`, para volver a la copia anonimizada.
