# canopy-respaldos (repositorio PRIVADO del dueño)

Este repositorio existe para el respaldo nocturno de la base de datos del café y para el ensayo en PRUEBAS.
Debe ser **privado** y **no** debe conectarse a sesiones de asistentes de IA.

Contenido (copiado de `ops/backup/` del repositorio de desarrollo; actualícelo solo cuando
`docs/RESPALDOS.md` o `docs/PRUEBAS.md` lo indiquen):

- `.github/workflows/respaldo.yml`: respaldo todas las noches y con el botón "Run workflow".
- `backup.sh`: respaldo, prueba de restauración (filas, contenido y permisos), cifrado y subida.
- `restore-stub.sql`: imitación mínima de Supabase para la prueba de restauración.
- `.github/workflows/ensayo-pruebas.yml`, `ensayo.sh`, `anonimizar.sql`: copia anonimizada de producción en el
  proyecto de PRUEBAS y ensayo de las migraciones (solo con el botón).

Instalación paso a paso: `docs/RESPALDOS.md` y `docs/PRUEBAS.md` del repositorio de desarrollo. Secretos y
variables que usa el respaldo: comentario al comienzo de `respaldo.yml`. Contraseñas y llaves van solo en
**Settings → Secrets and variables → Actions**, nunca en archivos de este repositorio.

Cada corrida deja un **resumen** con lo verificado: `restauración verificada: …`, `… archivos verificados` y
`listo: … restauración: passed`. La copia cifrada está abajo, en **Artifacts** (`respaldo-cifrado`, 14 días).
