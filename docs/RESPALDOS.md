# Respaldos de Canopy OS

## Cómo funciona

1. **Todas las noches a las 2:17 a. m.** un trabajo automático en un repositorio **privado** suyo de
   GitHub hace lo siguiente:
   - copia la base de datos completa y las fotos del menú;
   - **la restaura en una base de prueba desechable** y verifica tabla por tabla que no falte nada;
   - la **cifra**;
   - la sube a un almacenamiento externo **protegido contra borrado**.
2. **Su computadora** trae esas copias cifradas a la carpeta `Documentos\HangingGarden-Respaldos`.
   - Revisa cada hora y al encender.
   - Si estuvo apagada varios días, al encender **trae todo lo que falta**. El café nunca depende de que
     esa computadora esté encendida.
3. **Una vez al mes**, copie la carpeta a una memoria USB y guárdela desconectada, fuera del café.
4. En **Inicio** (área del dueño), la tarjeta **Respaldos** muestra:
   - **verde**: respaldo verificado en las últimas 26 h;
   - **ámbar**: respaldo atrasado o con la prueba fallida;
   - **rojo**: más de 50 h sin respaldo.
5. Si un respaldo falla, GitHub le envía un correo.

**Cifrado.** Los respaldos se cifran con `age` (gratuito) para **dos llaves**:

- la **suya**, guardada en su gestor de contraseñas;
- la **de recuperación**, impresa y guardada en un lugar seguro, como una caja fuerte.

Sin una de esas llaves **nadie** puede leer un respaldo, ni GitHub, ni el almacenamiento, ni yo.
**Si pierde ambas llaves, los respaldos no sirven.** Por eso son dos y una está en papel.

**Qué se respalda:**

- Toda la información del negocio: ventas, cuentas abiertas, pagos, caja, inventario, compras,
  horas, personal, contabilidad y bitácora de aprobaciones.
- La estructura de la base.
- Las cuentas de acceso.
- Las fotos del menú.

**Qué no se respalda (está en otro lado o se vuelve a poner a mano):**

- el código del sitio (está en GitHub);
- los secretos de Vault (token del BCCR y otros);
- la configuración de inicio de sesión de Supabase.

## Primer respaldo: ANTES de aplicar cualquier migración

El primer respaldo verificado se hace con la base tal como está hoy (sin la migración 0000). Para eso no hace
falta el almacenamiento externo del paso 1: la copia **cifrada** queda como archivo descargable de la corrida de
GitHub ("Artifacts", 14 días) y usted la guarda en su computadora.

Orden: paso 2 (cuenta de respaldo) → paso 3 (repositorio privado, sin los secretos `RCLONE_*`) → **Run workflow**
→ descargar el archivo → paso 1 y 4 cuando quiera (antes de dejar el respaldo nocturno solo).

Qué se verifica en cada respaldo (si algo no coincide, la corrida queda en **rojo**):

- la copia se restaura en una base desechable y **cada tabla tiene las mismas filas y el mismo contenido** (huella
  md5 de cada fila; las tablas que cambiaron durante la copia se revisan por cantidad de filas);
- **los mismos permisos**: quién puede ejecutar cada función y leer cada tabla, qué tablas tienen reglas de filas;
- **cada foto del menú** listada en Storage está en la copia, con el mismo tamaño.

## Instalación (una sola vez, aprox. 1 hora)

### Paso 1 · Almacenamiento externo con protección contra borrado

Recomendado: **Cloudflare R2**, gratis hasta 10 GB (los respaldos del café ocupan mucho menos).
Pide una tarjeta para abrir la cuenta. Alternativa: Backblaze B2.

1. Cree la cuenta y **active el código del teléfono (2FA)**.
2. Cree un *bucket* llamado `canopy-respaldos`.
3. En el bucket, cree una regla de **bloqueo (bucket lock)** de **45 días**. Así nadie puede borrar un
   respaldo de menos de 45 días, ni con una contraseña robada.
4. Cree **dos llaves de API** limitadas a ese bucket:
   - **Escritura** (*Object Write*), para GitHub.
   - **Solo lectura** (*Object Read*), para su computadora.

### Paso 2 · Base de datos (Supabase)

1. SQL Editor → New query → pegue **todo** `supabase/tools/backup-account.sql` → Run. Debe decir
   **"lista: la cuenta canopy_backup puede leer todo y no puede cambiar nada"**. No necesita ninguna migración y
   no toca datos del negocio. (Si ya aplicó la 0002, la cuenta ya existe: el script no cambia nada.)
2. Invente una contraseña larga (por ejemplo, 30 letras y números al azar de su gestor de contraseñas) y
   ejecute en el SQL Editor:
   ```sql
   alter role canopy_backup with login password 'LA-CONTRASEÑA-LARGA';
   ```
   La cuenta `canopy_backup` **solo puede leer**. No puede cambiar ni borrar nada.
   Después de ejecutarla, **borre esa consulta** de la lista de consultas guardadas del SQL Editor (tiene la
   contraseña).
3. Ejecute `select version();` y anote el número (por ejemplo 17.x).
4. Supabase → **Connect** → **Session pooler**. Copie la dirección y cambie:
   - el usuario `postgres.<proyecto>` por `canopy_backup.<proyecto>`;
   - la contraseña por la del punto 2.

   Agregue al final `?sslmode=require`. Eso es `CANOPY_DB_URL`. **No la pegue en ningún chat.**

### Paso 3 · Repositorio privado de respaldos (GitHub, gratis)

1. GitHub → **New repository** → nombre `canopy-respaldos` → **Private**.
   No lo conecte a sesiones de asistentes de IA.
2. Suba el contenido de la carpeta `ops/backup/repositorio-respaldos/` de este repositorio.
   Incluye la carpeta `.github`.
3. En su computadora, instale `age` (https://age-encryption.org) y cree las dos llaves:
   ```
   age-keygen -o llave-dueno.txt
   age-keygen -o llave-recuperacion.txt
   ```
   - Guarde `llave-dueno.txt` en su gestor de contraseñas.
   - **Imprima** `llave-recuperacion.txt`, guárdela en un lugar seguro, y luego **borre ese archivo de la
     computadora**.
   - Cada archivo muestra una línea `public key: age1...`.
4. `canopy-respaldos` → **Settings → Secrets and variables → Actions**:
   - Secreto `CANOPY_DB_URL`: la dirección del paso 2.
   - Secreto `AGE_RECIPIENTS`: las **dos** llaves públicas `age1...`, separadas por un espacio.
   - Secreto `RCLONE_CONF`: la configuración de rclone con la llave de **escritura** (plantilla abajo).
     *(Opcional para el primer respaldo.)*
   - Secreto `RCLONE_REMOTE`: `offsite:canopy-respaldos` *(opcional para el primer respaldo)*
   - Variable `SUPABASE_URL`: `https://<proyecto>.supabase.co`
5. **Actions → Respaldo nocturno → Run workflow**. Debe terminar en verde. Abra la corrida y, abajo, en
   **Artifacts**, descargue `respaldo-cifrado`: guárdelo en su computadora (es el respaldo cifrado).
   Cuando ya esté aplicada la migración 0002, la tarjeta Respaldos de Inicio también queda verde.

Plantilla `RCLONE_CONF` para Cloudflare R2:

```
[offsite]
type = s3
provider = Cloudflare
access_key_id = <llave de ESCRITURA>
secret_access_key = <secreto de ESCRITURA>
endpoint = https://<cuenta>.r2.cloudflarestorage.com
no_check_bucket = true
```

### Paso 4 · Su computadora

1. Instale **rclone** (https://rclone.org/downloads).
2. Cree el destino de **solo lectura**: `rclone config` → nombre `offsite` → el mismo tipo de la plantilla,
   pero con la llave de **solo lectura**.
3. Archivo de configuración:
   - **Windows**: cree `canopy-respaldos.conf.ps1` en su carpeta de usuario con
     `$REMOTE = "offsite:canopy-respaldos"`.
   - **Mac**: cree `~/.canopy-respaldos.conf` con `REMOTE="offsite:canopy-respaldos"`.
4. Instale la tarea automática:
   - **Windows**: `powershell -ExecutionPolicy Bypass -File ops\backup\computer\instalar-windows.ps1`
   - **Mac**: `bash ops/backup/computer/instalar-mac.sh`
5. Revise `Documentos/HangingGarden-Respaldos/ESTADO.txt`. Debe decir **Estado: BIEN**.

### Paso 5 · Copia sin conexión (mensual)

El primer día de cada mes, copie la carpeta `HangingGarden-Respaldos/archivo` a una memoria USB.
Desconéctela y guárdela fuera del café. Con dos memorias que se turnan, mejor.

## Uso diario

- **No hay que hacer nada.** Mire la tarjeta **Respaldos** de vez en cuando.
- **Respaldo inmediato** (por ejemplo, antes de aplicar una migración):
  `canopy-respaldos` → Actions → Respaldo nocturno → **Run workflow**. Espere el verde.
- **Si la tarjeta está ámbar o roja**, o llega un correo de falla: abra la corrida en GitHub
  Actions y lea el paso en rojo. Los mensajes están en español.

## Prueba de restauración (cada 3 meses, 30 minutos)

Cada noche el respaldo se restaura solo en una base desechable. Además, cada 3 meses:

1. En el proyecto de **PRUEBAS** (nunca en producción), vacíe la base con el SQL Editor:
   ```sql
   drop schema if exists acct cascade; drop schema if exists canopy cascade;
   drop schema public cascade; create schema public;
   grant usage on schema public to anon, authenticated, service_role;
   grant all on schema public to postgres, service_role;
   ```
2. En su computadora, con `pg_restore` y `age` instalados:
   ```
   bash ops/backup/restore.sh <archivo.tar.age> llave-dueno.txt "<conexión del proyecto de PRUEBAS>"
   ```
   Escriba **RESTAURAR** cuando lo pida. Al final debe decir **OK: … filas iguales al respaldo**.
3. Abra el sitio de pruebas y revise las ventas de ayer y el inventario.

**Una vez al año, haga la prueba con la llave de recuperación impresa**, para comprobar que sirve.

## Desastre: recuperar el café en otro proyecto

1. Cree un proyecto nuevo de Supabase.
2. Use `restore.sh` con el respaldo más reciente:
   ```
   bash ops/backup/restore.sh <archivo> <llave> "<conexión del proyecto NUEVO>" --auth
   ```
   - `--auth` intenta recuperar las cuentas de acceso.
   - El script **se niega** a restaurar encima de una base que ya tenga datos.
3. Suba las fotos del menú: carpeta `storage/menu-photos` del respaldo → Storage → bucket `menu-photos`
   (público).
4. Vuelva a poner los secretos de Vault (token del BCCR) y la configuración de Authentication: dirección del
   sitio y código del teléfono.
5. Si no se pudieron recuperar las cuentas de acceso, créelas de nuevo en Authentication → Users (la del café,
   la suya y la del contador). Luego ejecute:
   ```sql
   select public.make_owner('su-correo');
   ```
   El personal **no** pierde sus PIN: están en la base.
6. Cambie la dirección del proyecto en `website/config.js` y publique la versión (`docs/PUBLICAR.md`).

Tiempo estimado: **menos de 2 horas**. Las ventas del día que quedaron en las tabletas sin internet se suben
solas cuando vuelven a conectarse.

## Cuánto se guarda

- **Almacenamiento externo**: 45 días bloqueados contra borrado. Después, el bucket puede borrarlos.
  Sugerido: borrar después de 120 días.
- **Su computadora**:
  - todo lo de los últimos 14 días;
  - uno por semana por 8 semanas;
  - uno por mes por 24 meses;
  - uno por año para siempre.

La ley exige guardar los registros contables y tributarios varios años. Plan: al menos 10 años, a confirmar
con su contador. Los respaldos anuales y la base misma cubren ese período.

## Costos

| Concepto | Costo |
|---|---|
| GitHub Actions en el repositorio privado (unos 5–8 min por noche de 2 000 gratis al mes) | $0 |
| Cloudflare R2 (dentro de los 10 GB gratis) | $0 |
| age, rclone, PostgreSQL | $0 (gratuitos) |
| Supabase Pro (opcional: agrega copias propias de Supabase por 7 días) | US$25/mes |

## Seguridad

- **`canopy_backup` solo lee.** Si alguien robara su contraseña, no podría cambiar ni borrar nada.
  Igual cámbiela si sospecha algo:
  ```sql
  alter role canopy_backup with password '...';
  ```
  Y actualice el secreto en GitHub.
- **GitHub y el almacenamiento solo tienen llaves públicas** (`age1…`). Pueden cifrar, nunca descifrar.
- **La llave de escritura del almacenamiento no puede borrar** respaldos bloqueados.
- **Con la contraseña de respaldos solo corre código del repositorio privado.** El "Ensayo en pruebas"
  (docs/PRUEBAS.md) usa las migraciones del repositorio público, pero solo contra el proyecto de PRUEBAS, enviadas
  como SQL puro (`psql -c`: ningún comando de terminal escrito en esos archivos se ejecuta), y la comparación final
  corre en un paso sin contraseñas.
- **Restaurar no abre permisos.** Supabase da a los visitantes acceso a cada función nueva; al restaurar, eso se
  apaga mientras se cargan las funciones y se comprueba que los permisos quedaron idénticos a los del respaldo.
- **Nunca envíe** contraseñas, llaves privadas ni direcciones de conexión por chat ni por correo.
