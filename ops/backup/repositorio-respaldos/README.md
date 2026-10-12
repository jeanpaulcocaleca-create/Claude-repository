# canopy-respaldos (repositorio PRIVADO del dueño)

Este repositorio solo existe para el respaldo nocturno de la base de datos del café.
Debe ser **privado** y **no** debe conectarse a sesiones de asistentes de IA.

Contenido (copiado de `ops/backup/` del repositorio de desarrollo; actualícelo solo cuando
`docs/RESPALDOS.md` lo indique):

- `.github/workflows/respaldo.yml`: corre todas las noches y con el botón "Run workflow".
- `backup.sh`: hace el respaldo, la prueba de restauración, el cifrado y la subida.
- `restore-stub.sql`: imitación mínima de Supabase para la prueba de restauración.

Instalación paso a paso: `docs/RESPALDOS.md` del repositorio de desarrollo.
