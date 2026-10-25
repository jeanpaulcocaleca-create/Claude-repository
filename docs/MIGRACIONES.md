# Migraciones de la base de datos (Canopy OS)

Todos los cambios a la base de datos de Supabase se hacen con **archivos numerados** en
`supabase/migrations/`, en orden: `0000_…`, `0001_…`, `0002_…`.

Los 18 archivos sueltos de `supabase/` (timeclock.sql, pos-tabs.sql, menu-2026.sql…) son **historia**.
Ya no se ejecutan: después de la migración 0000 se detienen solos en la primera línea.

## Cómo aplicar una migración (dueño)

1. **Respaldo primero.** Pida uno ahora (docs/RESPALDOS.md → "Respaldo inmediato") y espere el verde. Antes de la
   0002 no hay tarjeta en Inicio: el verde de GitHub es la prueba.
2. **Primero en pruebas.** "Ensayo en pruebas" en verde con la misma versión (docs/PRUEBAS.md), que aplica la
   migración en una copia anonimizada de producción y compara antes y después.
3. **Foto antes y después.** `supabase/tools/production-snapshot.sql` (solo lectura) antes y después; para la
   ventana grande también `supabase/tools/consistency-check.sql`: los valores de "kept" deben salir iguales.
4. **Luego en producción.** Hágalo fuera del horario de atención (antes de las 6:00 o después del cierre de caja):
   1. Supabase → **SQL Editor** → **New query**.
   2. Abra el archivo en GitHub, botón **Raw**, copie **todo** y péguelo.
   3. Presione **Run**.
5. **Revise el resultado**: debe decir *Success*. Para ver lo aplicado:
   ```sql
   select * from canopy.migrations order by version desc limit 5;
   ```

### Si sale un error

- **"ya estaba aplicada"**: no pasó nada; esa migración ya estaba.
- **"Falta aplicar antes la migración N"**: aplique primero la N y luego esta.
- **"must be owner of table objects" en la 0015 o la 0025**: no se aplicó nada de ese archivo. Detenga la ventana
  ahí: las páginas que se usan hoy siguen funcionando (probado con la base en la 0014 y en la 0025; en la 0024 no se
  probó aparte: la 0025 solo restringe, y aun con ella esas páginas funcionan). No publique las páginas
  nuevas y mantenga las reglas provisionales: sin acceso del contador, el PIN del dueño nunca se escribe en la
  tableta, y no se cambian ajustes, confirmaciones ni tarifas de impuestos. Copie el mensaje y avíselo, para que
  llegue pronto una migración corregida.
- **Cualquier otro error**: el archivo completo se deshace solo (corre como una sola transacción).
  Nada queda a medias. Copie el mensaje y avíselo.

### Reglas que siguen las migraciones

- **Una sola transacción.** Si algo falla, nada se aplica.
- **Primero solo agregan.** Columnas nuevas, funciones nuevas, parámetros opcionales. Las tabletas con la
  página vieja abierta y las ventas guardadas sin internet siguen funcionando.
- **Restricciones después.** Volver obligatorio algo, o quitar lo viejo, va en una migración posterior,
  cuando todas las tabletas ya tienen la versión nueva.
- **Nunca borran ni reescriben registros del negocio** (ventas, pagos, inventario, horas, contabilidad).
- **Cada archivo explica en español** qué hace, por qué, y cómo revertirlo si aplica.
- **Solo SQL.** Ningún comando de psql (líneas que empiezan con `\`): el SQL Editor no los entiende y el ensayo en
  pruebas los rechaza (lo revisa `tests/lint.sh`).
- **Se ensaya antes de llegar aquí.** `tests/run.sh rehearsal` aplica todas las migraciones sobre una copia con la
  estructura de producción y meses de historia, como una cuenta que no es superusuario, y compara los datos
  (D-023).

## Línea base: la estructura real de producción

Las tablas `orders`, `order_items`, `menu_items` y `menu_categories` se crearon antes de que existiera este
repositorio. Por eso las pruebas usan una reconstrucción (`tests/db/01_base_tables.sql`). Para usar la
estructura exacta:

Primero, la foto (`supabase/tools/production-snapshot.sql`) dice si hace falta: si `functions_changed`,
`functions_unknown`, `tables_columns_differ` y `triggers_differ` salen vacíos, producción es igual a la
reconstrucción. (La foto del 2026-10-12 mostró `audit_menu()` distinta y la columna `orders.note` de más, D-027.
El seguimiento del 2026-10-13 explicó las dos, D-031: `audit_menu()` es la del repositorio sin un comentario, y
quedó aceptada sin migración; `orders.note` nunca se usó, y ya está en la reconstrucción. Con eso la foto debe
salir vacía, y la exportación de abajo es opcional: sirve solo para tener las definiciones exactas de las cuatro
tablas.)

1. Supabase → SQL Editor → pegue `supabase/tools/catalog-export.sql` → **Run**.
   Es solo lectura: no muestra ventas, nombres, PINs ni contraseñas.
2. En la única celda del resultado: clic derecho → **Copy cell**.
3. En GitHub, en la rama de desarrollo: **Add file → Create new file** →
   `supabase/baseline/production-schema.sql` → pegue → **Commit**.

Con ese archivo comparo la estructura real contra la reconstrucción.

## Pendientes de aplicar en producción (hoy en la 0032)

La 0029 (recibir un pedido con la factura y el pago, D-041) la aplicó el dueño el 2026-10-15 (E-25); las 0030–0032
(recetas, D-043/D-044) el 2026-10-18 (E-29/E-30, D-047). Las filas de 0030–0032 quedan abajo como referencia.

| Archivo | Qué trae | Cómo se aplica |
|---|---|---|
| `0033_pines_seguros.sql` | PIN más seguros (D-053): el editor del equipo ya no deja averiguar PIN (máximo 10 PIN por hora y cuenta, y cada «ya lo usa alguien» queda anotado); un PIN vacío no cuenta como intento; cada bloqueo queda anotado y otro encargado lo quita con su PIN; volver a activar a alguien pide un PIN nuevo; cada apertura de las áreas de dueño queda atada a la sesión que la hizo (otro aparato de la misma cuenta no la usa, tampoco para las fotos del menú) y, con las páginas nuevas, cerrar sesión la termina en el servidor. Solo funciones y una columna nueva; ningún registro cambia | Como cualquier migración (pasos 1–5), **fuera del horario de atención**, después de la 0032. Después: en una tableta, abrir las áreas de dueño con un PIN y cambiar una foto del menú (comprueba la sesión en Supabase). Reversión: `supabase/tools/reversion-0033.sql`. Guía completa (orden, verificaciones, simulacro de reversión, recuperación): `docs/ACTIVACION-PINES.md` |

| Archivo | Qué trae | Cómo se aplica |
|---|---|---|
| `0030_recetas_seguras.sql` | Recetas, etapa 1A (D-043): cada cambio de receta se guarda de una vez con el PIN de un encargado o del dueño, queda en un historial que no se puede borrar (quién, cuándo, por qué, qué cambió y el costo antes → después), cantidades en gramos o mililitros, un solo costo (el promedio) y el costo de ingredientes comparado con las ventas sin IVA. Las recetas de hoy quedan como «versión inicial»; el editor publicado hoy sigue guardando (queda como «cambio directo») | Como cualquier migración (pasos 1–5 de arriba), **fuera del horario de atención**: agregar los disparadores bloquea la tabla de recetas un instante y en ese instante una venta espera. Requiere la 0029. Reversión: `supabase/tools/reversion-0030.sql` |

| `0031_recetas_ventas_exactas.sql` | Recetas, etapa 1B (D-044): cada venta descuenta la receta y el costo vigentes cuando se cobró (también si llegó tarde por falta de internet); lo agregado sin internet a un pedido toma la receta de cuando se agregó; quitar un producto de una cuenta devuelve exactamente lo que salió; nunca rechaza una venta | Igual, **fuera del horario de atención**, después de la 0030. Reversión: `supabase/tools/reversion-0031.sql` (después de revertir la 0032) |
| `0032_recetas_solo_con_pin.sql` | Recetas, etapa 1B (D-044): ninguna página escribe recetas directamente; solo el editor con PIN. La Caja no cambia | Igual, después de la 0031, en la misma ventana. Reversión: `supabase/tools/reversion-0032.sql` |

La guía completa (orden, verificaciones, reversión) está en `docs/ACTIVACION-RECETAS.md`.

No confundir con la antigua «0030 facturas_archivo» (archivos de facturas en Storage): se eliminó antes de publicarse
(D-042) y nunca se aplicó; el número 0030 es ahora el de las recetas.

Antes: «Ensayo en pruebas» en verde con la versión (con **reinicio = no**: producción ya pasó la ventana) y «Respaldo
inmediato» en verde. Después: `supabase/tools/release-check.sql` debe mostrar `migrations_missing` y `functions_missing`
vacíos.

## Plantilla de una migración nueva

```sql
-- ===========================================================================
-- Canopy OS · migración NNNN · <título en español>
-- Pegar TODO en Supabase → SQL Editor → New query → Run.  Requiere: NNNN-1.
-- Qué hace / por qué / qué cambia para el personal / reversión
-- ===========================================================================
select canopy.migration_begin(NNNN, 'nombre_corto');

-- ... cambios (solo agregar en la primera fase) ...

select canopy.migration_end(NNNN, 'nombre_corto');
notify pgrst, 'reload schema';
```

## Para desarrolladores

`tests/build-db.sh` construye una base de prueba en este orden:

1. imitación de Supabase;
2. tablas base;
3. los 18 archivos históricos (en el orden de `tests/db/legacy-order.txt`);
4. todas las migraciones, cada una con `--single-transaction`, igual que el SQL Editor;
5. datos de prueba.

`tests/run.sh` corre todas las pruebas. No se sube nada que no pase.
