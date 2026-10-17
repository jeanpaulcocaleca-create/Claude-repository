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

- **La Caja y la cocina no cambian lo que envían.** Todo lo nuevo ocurre en el servidor. Las páginas publicadas hoy
  (v2026.10.15-1, y también v2026.10.14-1 y la de antes del lanzamiento) se probaron sobre una copia con 0030-0032:
  venden, guardan sin internet y suben después, marcan horas y editan el menú igual que antes.
- **La Caja nunca escribe recetas.** El bloqueo de la 0032 solo afecta al editor de recetas: una página vieja del
  Inventario que intente guardar una receta ve «No se pudo guardar la receta» y la receta queda como estaba.
- **Nunca se rechaza una venta.** Si algo impide descontar el inventario de una venta (por ejemplo, un ingrediente de
  una receta vieja que ya no existe), la venta se guarda igual y queda marcada para el encargado.
- **Ventas pendientes de sincronizar:** al llegar, toman la receta y el costo de cuando se cobraron (las de antes de
  la 0030 toman la receta con que empezó el historial).
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
   7. En un aparato del café: Inventario → Recetas, abrir un producto, cambiar nada y guardar con PIN («La receta no
      cambió»), y una venta de prueba que luego se anula (la anulación devuelve lo mismo que salió).
   Si un pegado se detiene por «lock timeout» (una venta llegó en ese instante), no cambió nada: se vuelve a pegar.
3. **Después**
   - Los aparatos toman las páginas nuevas solos al quedar libres (sin venta en curso ni cuenta abierta en pantalla).
     No hace falta esperar una semana: la Caja no depende de esto.
   - La primera semana, en Inventario → Historial, lo devuelto al quitar de una cuenta aparece como «Quitado de una
     cuenta»; en Ventas, una venta marcada `stock_not_taken` o `recipe_item_missing` se revisa con el encargado.

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
  - Lo agregado sin internet a un pedido que sube junto con lo agregado (el sistema nunca lo tuvo) toma la hora del
    pedido, del mismo día. Lo agregado después de un primer envío sin respuesta toma su propia hora.
  - La hora de una venta es la del reloj del aparato: un reloj atrasado puede tomar la receta anterior a un cambio de ese
    mismo momento.
  - Los movimientos de una venta que llega tarde quedan con la fecha de llegada (como hoy); las cantidades y los costos
    son los del momento de la venta.
  - Una cuenta abierta antes de la 0031 reparte lo devuelto por nombre del producto, al costo promedio con que salió.
  - Si se revierte la 0031 y luego se vuelve a aplicar, hacerlo con las cuentas abiertas ya cobradas o anuladas.
