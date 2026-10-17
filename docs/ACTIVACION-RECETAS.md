# Activación de las recetas, etapas 1A + 1B (propuesta)

**Estado:** propuesta para aprobación del dueño. Nada de esto está aplicado ni publicado. Las cantidades del
recetario siguen siendo propuestas: esta activación no carga ninguna receta.

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

## Pasos propuestos (una sola ventana, fuera del horario de atención)

1. **Antes de la ventana**
   - Subir `ops/backup/repositorio-respaldos/anonimizar.sql` de esta versión al repositorio privado `canopy-respaldos`
     (E-28).
   - «Ensayo en pruebas» con esta rama o su etiqueta, **reinicio = no**: debe terminar en verde (aplica 0030, 0031 y
     0032 sobre una copia anonimizada de producción y compara).
2. **En la ventana** (café cerrado; ningún aparato vendiendo)
   1. «Respaldo inmediato» en verde.
   2. SQL Editor: pegar `0030_recetas_seguras.sql` → *Success*.
   3. Pegar `0031_recetas_ventas_exactas.sql` → *Success*.
   4. Pegar `0032_recetas_solo_con_pin.sql` → *Success*.
   5. Pegar `supabase/tools/release-check.sql`: `migrations_missing` = `[]` y `functions_missing` = `[]`.
   6. Crear la etiqueta `v…` y ejecutar «Publish website (PRODUCTION · manual only)».
   7. En un aparato del café: Inventario → Recetas, abrir un producto, no cambiar nada y guardar con PIN («La receta no
      cambió»). **No** hacer una venta de prueba en producción: con la caja ya cerrada no se puede anular (quedaría una
      venta y una devolución en un día cerrado). Las ventas, devoluciones y anulaciones se prueban en el «Ensayo en
      pruebas» y en las pruebas automáticas; en producción se revisan con las primeras ventas reales (ver «Después»).
   Si un pegado se detiene por «lock timeout» (algo usaba esas tablas en ese instante), no cambió nada: se vuelve a
   pegar.
3. **Después**
   - Los aparatos toman las páginas nuevas solos al quedar libres (sin venta en curso ni cuenta abierta en pantalla).
     No hace falta esperar una semana: la Caja no depende de esto.
   - El primer día, la primera vez que se quite un producto de una cuenta: en Inventario → Historial aparece como
     «Quitado de una cuenta» con la misma cantidad que salió con la venta.
   - La primera semana, en Ventas: una venta con el aviso «Inventario no descontado» o «Un ingrediente de su receta quedó
     fuera» se revisa con el encargado (la venta quedó guardada; solo el inventario necesita revisión).

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
