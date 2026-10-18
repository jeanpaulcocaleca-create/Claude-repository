# Activación de las recetas, etapas 1A + 1B

**Estado:** aprobada técnicamente (LISTO PARA PRODUCCIÓN, D-045) y en preparación paso a paso con el dueño; nada
aplicado ni publicado hasta que el dueño ejecute la ventana. Las cantidades del recetario siguen siendo propuestas:
esta activación no carga ninguna receta. **Versión a publicar:** un commit de la rama aprobada cuyos `website/` y
`supabase/migrations/` sean idénticos a 9b33273 (el ensayado el 2026-10-17 en «Ensayo en pruebas» #6) y con CI en
verde; si se etiqueta otro commit, repetir el ensayo sobre él (unos 5 minutos). La revisión independiente de preparación
(cuatro lentes, cada hallazgo serio atacado por dos verificadores) no encontró bloqueos.

## Qué se activa

| Pieza | Qué hace | Archivo |
|---|---|---|
| 0030 · recetas seguras (1A, D-043) | Cada cambio de receta se guarda de una vez con el PIN de un encargado o del dueño; historial que no se puede borrar; gramos y mililitros; un solo costo (el promedio); costo de ingredientes contra ventas sin IVA | `supabase/migrations/0030_recetas_seguras.sql` |
| 0031 · ventas exactas (1B, D-044) | Cada venta descuenta la receta y el costo vigentes **cuando se cobró** (también si llegó tarde por falta de internet); quitar un producto de una cuenta devuelve **exactamente** lo que salió; una cuenta pagada por partes y anulada deja fuera solo lo consumido | `supabase/migrations/0031_recetas_ventas_exactas.sql` |
| 0032 · recetas solo con PIN (1B, D-044) | Ninguna página puede escribir recetas directamente: ni las versiones anteriores del Inventario guardadas en un aparato, ni una consulta directa. Solo el editor nuevo, con PIN | `supabase/migrations/0032_recetas_solo_con_pin.sql` |
| Páginas nuevas | Editor de recetas con PIN, historial y versión para teléfono; conteo y recepción por bolsas; etiquetas | `website/` (publicación con etiqueta) |

## Por qué es seguro para la Caja

- **La Caja publicada hoy y la cocina no cambian lo que envían.** Todo lo nuevo ocurre en el servidor; la Caja nueva
  solo agrega, de forma opcional, la hora de lo que se agregó sin internet a un pedido. Las páginas publicadas hoy
  (v2026.10.15-1, y también v2026.10.14-1 y la de antes del lanzamiento) se probaron sobre una copia con 0030-0032:
  venden, guardan sin internet y suben después, marcan horas y editan el menú igual que antes.
- **La Caja nunca escribe recetas.** El bloqueo de la 0032 solo afecta al editor de recetas: una página vieja del
  Inventario que intente guardar una receta ve «No se pudo guardar la receta» y la receta queda como estaba.
- **Nunca se rechaza una venta.** Si algo impide descontar el inventario de una venta (por ejemplo, un ingrediente de
  una receta vieja que ya no existe), la venta se guarda igual y queda marcada para el encargado.
- **Ventas pendientes de sincronizar:** al llegar, toman la receta y el costo de cuando se cobraron (las de antes de
  la 0030 toman la receta con que empezó el historial y el primer costo conocido). Lo agregado en la caja a un pedido
  antes de que subiera toma la receta y el costo de cuando se agregó.
- **Un producto borrado y vuelto a crear con el mismo nombre:** una caja con el menú viejo descuenta la receta del
  producto nuevo; una venta cobrada antes del borrado, la del producto viejo.
- **Cuentas abiertas al momento de activar:** siguen funcionando. Si se quita un producto de una cuenta abierta antes
  de la 0031, se devuelve la parte de lo que sigue fuera con ese nombre en esa cuenta (incluye lo devuelto antes), sin
  recalcular con la receta de hoy.

## Pasos (una sola ventana, con el café cerrado)

**Si el café está operando, se espera al cierre.** La 0030 bloquea un instante la tabla de recetas y la 0031 las de
líneas y movimientos: una venta en ese instante espera o el pegado se detiene sin cambiar nada (lock timeout de 8 s).
La publicación recarga las páginas solo cuando están libres, pero la ventana entera se hace con los aparatos quietos.

1. **Antes de la ventana** (puede hacerse con el café abierto; nada de esto cambia producción)
   - E-28 hecho el 2026-10-17: los archivos del repositorio privado son idénticos a los de la versión, y «Ensayo en
     pruebas» #6 terminó en verde sobre 9b33273 (destino `desechable`, vaciar `no`, reinicio `no`: aplica 0030, 0031 y
     0032 sobre una copia anonimizada de producción y compara).
   - Llaves de los respaldos comprobadas: las dos abren el respaldo y la copia restaurada es igual a producción (E-24,
     D-046).
   - Decisiones del dueño, registradas antes de la ventana: la 0030 fija **una sola vez** el costo promedio de los
     ingredientes creados con precio y nunca recibidos (hoy ₡0 en cada venta; aprobado en D-043); ninguna reversión lo
     deshace, solo el respaldo lo tendría. Los encargados con PIN autorizan cambios de receta hasta que exista un perfil
     de dueño (D-043). Qué encargado hará el paso 2.11 con su PIN. La regla de parada de abajo.
   - Solo lectura, en el SQL Editor, con los archivos **de la versión** (Raw en GitHub): `supabase/tools/release-check.sql`
     → `migrations_missing` = `[30, 31, 32]` y `functions_missing` = `[recipe_save, recipes_autolink_pin]`;
     `supabase/tools/production-snapshot.sql` → guardar la celda (foto «antes»; es la base para comprobar una reversión).
2. **En la ventana** (café cerrado; ningún aparato vendiendo)
   1. **Los tres aparatos**, con sesión iniciada: la Caja muestra el chip «en línea» y, al tocarlo, «Todo lo que se tomó
      en este dispositivo está guardado en el sistema.»; el panel de pedidos abiertos no tiene cuentas por pagar; la
      cocina no tiene tickets; fecha y hora automáticas y sin aviso de reloj; una sola pestaña por página. La cola de
      ventas sin conexión existe solo en cada aparato: no se puede ver desde la base. Cualquier otro texto del chip
      («guardando N…», «N sin guardar todavía», «sin conexión · N en este dispositivo») detiene la ventana hasta que
      se vacíe.
   2. «Respaldo inmediato» en verde, **justo antes** de la 0030 (uno de la mañana no cuenta si hubo ventas después). En
      Actions no debe quedar ninguna corrida de respaldo en curso al pegar: un respaldo abierto haría fallar la 0031 por
      lock timeout (sin cambiar nada).
   3. SQL Editor → New query: pegar **todo** `0030_recetas_seguras.sql` de la versión (primera línea: «migración 0030 ·
      Recetas seguras») → *Success*.
   4. Pegar `0031_recetas_ventas_exactas.sql` → *Success*.
   5. Pegar `0032_recetas_solo_con_pin.sql` → *Success*.
   6. Pegar `release-check.sql`: `migrations_missing` = `[]`, `functions_missing` = `[]`; `anon_can_run` y
      `tables_without_rls` iguales a la celda de antes.
   7. Pegar `production-snapshot.sql` → guardar la celda (foto «después»).
   8. **Etiqueta y publicación.** Releases → Draft a new release → etiqueta `vAAAA.MM.DD-N` → **Target: la rama
      aprobada**, no la predeterminada (el formulario propone la predeterminada y nada avisaría del error) → comprobar
      que el commit que muestra es el aprobado → Publish release. Luego Actions → «Publish website (PRODUCTION · manual
      only)» → Use workflow from → Tags → la etiqueta nueva → casilla PUBLICAR → Run workflow. Si el entorno
      `production` tiene revisores requeridos (E-20), la corrida espera su clic en Review deployments → Approve; si no,
      como en las dos publicaciones anteriores, publica en cuanto pasan sus dos controles.
   9. Abrir `https://hanginggardencafe.com/version.json` en una ventana privada: debe mostrar la etiqueta y el commit
      **antes** de tocar los aparatos.
   10. En los tres aparatos: recargar cada página cuando esté libre (la Caja se recarga sola sin ticket, sin cuenta
       abierta y con la cola vacía; si tras 15 minutos sigue en «actualización lista», recargar a mano); cerrar
       pestañas sobrantes y dejar una por página, con sesión.
   11. Inventario → Recetas, con el PIN de un encargado: abrir un producto que **ya tenga receta con cantidades
       enteras**, no cambiar nada y guardar → «La receta no cambió». No escribe versión ni bitácora; teclear el PIN
       correcto una sola vez (uno equivocado cuenta para el bloqueo). Si dice «Receta guardada · versión 2», detenerse y
       revisar Inventario → Historial. **No** hacer una venta de prueba en producción: con la caja ya cerrada no se puede
       anular (quedaría una venta y una devolución en un día cerrado). Las ventas, devoluciones y anulaciones se prueban
       en el «Ensayo en pruebas» y en las pruebas automáticas; en producción se revisan con las primeras ventas reales
       (ver «Después»).

   **Regla de parada.** Un pegado que se detiene por «lock timeout» no cambió nada: se vuelve a pegar. Cualquier **otro**
   error: detenerse, copiar el mensaje completo, no pegar el archivo siguiente y **no publicar**. La base queda en la
   versión alcanzada (0030 sola, o 0030 + 0031), estados probados con las páginas publicadas hoy. Cada archivo es una
   sola transacción, exige la anterior y rechaza repetirse.
3. **Después**
   - Los aparatos toman las páginas nuevas solos al quedar libres (sin venta en curso ni cuenta abierta en pantalla).
     No hace falta esperar una semana: la Caja no depende de esto.
   - El primer día, la primera vez que se quite un producto de una cuenta: en Inventario → Historial aparece como
     «Quitado de una cuenta» con la misma cantidad que salió con la venta.
   - La primera semana, en Ventas: una venta con el aviso «Inventario no descontado» o «Un ingrediente de su receta quedó
     fuera» se revisa con el encargado (la venta quedó guardada; solo el inventario necesita revisión).
   - Una pestaña de cocina o de Caja que quedó en la pantalla de inicio de sesión sigue consultando los pedidos cada
     pocos segundos y deja errores 401 en el registro de Supabase, sin exponer nada: cerrarla o iniciar sesión. Nunca
     conceder permisos sobre `orders` al rol `anon`; la corrección de una línea va en la primera versión posterior.
   - Anotar en `docs/DECISIONS.md` y `docs/DEPENDENCIES.md` la etiqueta, la hora UTC de cada pegado, las celdas de
     release-check y version.json y el resultado del paso 2.11; actualizar `tests/rehearsal/LIVE_PAGES` con el nuevo
     commit de `gh-pages` (un commit normal, no esa noche).

## Relojes de los aparatos y ventas que llegan tarde (revisión final, 2026-10-17)

- **Hora de cada venta:** es la del reloj del aparato (como hoy). Cada aparato mide su desfase contra la hora del servidor
  al renovar su sesión (cada hora) y, si pasa de 2 minutos, muestra «El reloj de este dispositivo está desfasado por …»:
  poner fecha y hora **automáticas** en cada aparato del café y atender ese aviso antes de seguir vendiendo. El servidor
  marca `clock_ahead` (más de 10 min adelantado) y `late_sync` (llegó más de 12 h tarde) y, si el día ya cerró caja,
  `after_close` con una línea en la bitácora; desde esta versión **Ventas muestra esas marcas** en cada venta (y el CSV
  las exporta). Un reloj adelantado toma la receta y el costo de ahora; uno atrasado, los del momento que marca.
- **No se corrige la hora en el servidor:** se evaluó una corrección automática (comparar la hora del aparato al enviar
  con la del servidor) y se descartó: corregiría mal las ventas de un aparato cuyo reloj cambió entre cobrar y enviar
  (por ejemplo, una batería agotada que reinicia la hora), y hoy no hay evidencia de relojes mal puestos en el café.
- **Un aparato sin conexión varios días** (ensayado sobre una copia detenida en 0029, con recetas cambiadas, 0030–0032
  aplicadas y la caja de ese día cerrada): sube todas sus ventas sin perder ninguna, descuenta la receta con que empezó el
  historial y el primer costo conocido, las marca `late_sync` y `after_close`, mantiene al operador y el descuento, y los
  productos agregados a cuentas ya cobradas o canceladas avisan a la caja sin reintentar para siempre. La cola de ventas
  del aparato sobrevive al cambio de versión de la página y a tener que iniciar sesión de nuevo. Dejar la pestaña de la
  Caja **abierta** mientras no hay internet: una pestaña cerrada y vuelta a abrir sin conexión pide iniciar sesión hasta
  que vuelva la conexión (nada se pierde).
- **Descuentos con reloj desfasado:** un reloj más de 10 min atrasado o 30 min adelantado hace que un descuento aprobado
  en línea se registre «sin verificar» (el dinero queda bien; el descuento no consta). Riesgo previo a esta etapa; Ventas
  lo muestra ahora.

## Si algo sale mal (reversión, en este orden)

1. `supabase/tools/reversion-0032.sql` — devuelve los permisos de antes (las páginas viejas vuelven a poder guardar
   recetas, anotado en el historial).
2. `supabase/tools/reversion-0031.sql` — las ventas vuelven a descontar la receta del momento de llegar.
3. `supabase/tools/reversion-0030.sql` — quita el PIN y el historial nuevo (el historial ya guardado se conserva).

Cada archivo es una sola transacción, se niega si el orden no es el correcto y deja las funciones exactamente como
estaban (misma huella en la foto de producción). Ninguna reversión borra ventas, movimientos ni recetas.
La reversión de la 0030 tampoco devuelve a ₡0 el costo promedio que esa migración dio una vez (D-043): ese dato queda,
y solo el respaldo lo tendría. Las páginas vuelven con «Publicar» desde la etiqueta anterior (`v2026.10.15-1`), que
funciona sobre la base con las tres migraciones y también después de cualquiera de las reversiones.

## Resultado · 2026-10-18

- La activación se hizo la noche del 2026-10-17 en Monteverde (madrugada del 2026-10-18 UTC): 0030, 0031 y 0032 aplicadas,
  release-check limpio; en la foto «después» (`production-snapshot.sql`) las cinco firmas en `functions_missing_legacy` son
  las de antes del lanzamiento, retiradas por 0005/0010: esperadas; etiqueta
  `v2026.10.17-1` (= `671fc0e`), «Publish website» #51 a las 02:08 UTC, `gh-pages` `1daae6f`, version.json confirmado en el
  dominio por el dueño (E-29, E-30 cerradas; D-047).
- El paso 2.11 (guardar sin cambios con PIN) quedó cubierto el mismo día por la carga de las primeras recetas: siete
  `recipe_save` con PIN de encargado en producción, autorizados por Jorge, verificados por el dueño con una consulta de solo
  lectura (D-047). Las comprobaciones en los aparatos del café (paso 2.10) siguen pendientes del reporte del dueño.
- `tests/rehearsal/LIVE_PAGES` apunta ahora al `gh-pages` publicado (`1daae6f`), en un commit normal como pedía la guía; la
  prueba del editor de recetas en vivo distingue desde entonces el editor con PIN (guarda una versión `editor` con el PIN
  de una encargada) del editor anterior (guardaba hasta la 0031 y la 0032 lo rechaza).
- Recetas iniciales cargadas (7) y lo que queda pendiente (Macchiato, chocolate y sabores, tamaños, las dos leches): D-047 y
  E-31 a E-34 en `docs/DEPENDENCIES.md`. Leche entera: se compra en paquetes de 10 cajas de 946 ml (9 460 ml), punto de
  reorden deseado 9 460 ml, las recetas descuentan en ml; compras y recetas deben usar el mismo artículo (`Leche entera 2`).
  Configuración y verificación pendientes (E-34): no se da por hecha en producción.

## Qué queda para después

- **Etapa 1C:** personalizaciones (tipo y cantidad de leche, azúcar, agua) que cambian lo que se descuenta.
- **Límites conocidos:**
  - La hora de una venta es la del reloj del aparato: un reloj atrasado puede tomar la receta anterior a un cambio de ese
    mismo momento.
  - Los movimientos de una venta que llega tarde quedan con la fecha de llegada (como hoy); las cantidades y los costos
    son los del momento de la venta.
  - Una cuenta abierta antes de la 0031 reparte por nombre del producto lo devuelto (y, si se anula con pagos por
    producto, lo consumido), al costo promedio con que salió.
  - Lo agregado sin internet a un pedido con la Caja publicada hoy (antes de que el aparato tome la Caja nueva) toma la
    hora del pedido si sube junto con él (mismo día, pedido todavía no enviado); si sube después, como paso aparte, toma
    la receta y el costo del momento en que llega, como antes de la 0031.
  - Una venta de antes de la activación que llegue después descuenta la receta y el costo que había al activar (lo único
    que se conoce de entonces); queda guardada y marcada `late_sync`.
  - Si se revierte la 0031 y luego se vuelve a aplicar, hacerlo con las cuentas abiertas ya cobradas o anuladas.
