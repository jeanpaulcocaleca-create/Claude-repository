# Migraciones de la base de datos (Canopy OS)

Todos los cambios a la base de datos de Supabase se hacen con **archivos numerados** en
`supabase/migrations/`, en orden: `0000_…`, `0001_…`, `0002_…`.

Los 18 archivos sueltos de `supabase/` (timeclock.sql, pos-tabs.sql, menu-2026.sql…) son **historia**.
Ya no se ejecutan: después de la migración 0000 se detienen solos en la primera línea.

## Cómo aplicar una migración (dueño)

1. **Respaldo primero.** Confirme que el respaldo de esta noche salió bien (tarjeta "Respaldos" en Inicio),
   o pida uno ahora (docs/RESPALDOS.md → "Respaldo inmediato").
2. **Primero en pruebas.** Aplíquela en el proyecto de **pruebas (staging)** y revise el sitio de pruebas.
3. **Luego en producción.** Hágalo fuera del horario de atención (antes de las 6:00 o después del cierre de caja):
   1. Supabase → **SQL Editor** → **New query**.
   2. Abra el archivo en GitHub, botón **Raw**, copie **todo** y péguelo.
   3. Presione **Run**.
4. **Revise el resultado**: debe decir *Success*. Para ver lo aplicado:
   ```sql
   select * from canopy.migrations order by version desc limit 5;
   ```

### Si sale un error

- **"ya estaba aplicada"**: no pasó nada; esa migración ya estaba.
- **"Falta aplicar antes la migración N"**: aplique primero la N y luego esta.
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

## Línea base: la estructura real de producción

Las tablas `orders`, `order_items`, `menu_items` y `menu_categories` se crearon antes de que existiera este
repositorio. Por eso las pruebas usan una reconstrucción (`tests/db/01_base_tables.sql`). Para usar la
estructura exacta:

1. Supabase → SQL Editor → pegue `supabase/tools/catalog-export.sql` → **Run**.
   Es solo lectura: no muestra ventas, nombres, PINs ni contraseñas.
2. En la única celda del resultado: clic derecho → **Copy cell**.
3. En GitHub, en la rama de desarrollo: **Add file → Create new file** →
   `supabase/baseline/production-schema.sql` → pegue → **Commit**.

Con ese archivo comparo la estructura real contra lo esperado y preparo la migración de conciliación.

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
