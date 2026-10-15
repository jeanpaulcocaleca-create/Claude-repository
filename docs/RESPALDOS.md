# Respaldos de Canopy OS

## Cómo funciona

1. **Todas las noches a las 2:17 a. m.** un trabajo automático en un repositorio **privado** suyo de
   GitHub hace lo siguiente:
   - copia los datos del café y las fotos del menú (las cuentas de acceso no: vea "Qué no se respalda");
   - **la restaura en una base de prueba desechable** y verifica tabla por tabla que no falte nada;
   - la **cifra**;
   - la sube a un almacenamiento externo **protegido contra borrado**.
   - La hora es la programada: GitHub puede atrasarla varias horas (las dos primeras corridas automáticas, el 14 y
     el 15 de octubre de 2026, empezaron hacia las 7:30 a. m.). No pasa nada: la cuenta solo lee, la prueba de
     restauración usa una base desechable y la copia incluye el día anterior completo.
2. **Su computadora** trae esas copias cifradas a la carpeta `Documentos\HangingGarden-Respaldos`.
   - Revisa cada hora y al encender.
   - Si estuvo apagada varios días, al encender **trae todo lo que falta**. El café nunca depende de que
     esa computadora esté encendida.
3. **Una vez al mes**, copie la carpeta a una memoria USB y guárdela desconectada, fuera del café.
4. En **Inicio** (área del dueño), la tarjeta **Respaldos** muestra:
   - **verde**: respaldo verificado en las últimas 26 h;
   - **ámbar**: respaldo atrasado o con la prueba fallida;
   - **rojo**: más de 50 h sin respaldo.

   La tarjeta muestra lo que el respaldo anota de sí mismo. La prueba es el resumen verde de la corrida en GitHub
   o una restauración hecha por usted (vea "Prueba de restauración").
5. Si un respaldo falla, GitHub le envía un correo.

**Cifrado.** Los respaldos se cifran con `age` (gratuito) para **dos llaves**:

- la **suya**, guardada en su gestor de contraseñas;
- la **de recuperación**, impresa y guardada en un lugar seguro, como una caja fuerte.

Sin una de esas llaves **nadie** puede leer un respaldo, ni GitHub, ni el almacenamiento, ni yo.
**Si pierde ambas llaves, los respaldos no sirven.** Por eso son dos y una está en papel.

**Qué se respalda:**

- Toda la información del negocio: ventas, cuentas abiertas, pagos, caja, inventario, compras,
  horas, personal, contabilidad y bitácora de aprobaciones.
- La estructura de la base (esquema `public`; también `canopy` y `acct` cuando existan).
- Los PIN del personal (cifrados, en la tabla del personal).
- Las fotos del menú (depósito público `menu-photos`; hoy 8), cada una comprobada.
- Las facturas de gastos todavía no existen (llegan con la migración 0015); para copiarlas harán falta llaves S3 de
  Storage (E-17). Sin ellas no se copian y la corrida lo avisa.

**Qué no se respalda (está en otro lado o se vuelve a poner a mano):**

- **las cuentas de acceso** (correos, contraseñas cifradas, sesiones, enlaces de recuperación, código del teléfono):
  la cuenta de respaldo no puede leerlas, así que ni una contraseña de respaldo robada ni un respaldo robado sirven
  para entrar como nadie. Después de un desastre se crean otra vez a mano (vea "Cuentas de acceso");
- el código del sitio (está en GitHub);
- los secretos de Vault (token del BCCR y otros);
- la configuración de Supabase: inicio de sesión, y el depósito `menu-photos` con sus reglas (vea "Después de restaurar");
- las fotos del menú guardadas fuera de Supabase (una dirección de foto que no es la de su proyecto): siguen donde
  están, pero no van en el respaldo.

## Primer respaldo: ANTES de aplicar cualquier migración

El primer respaldo verificado se hace con la base tal como está hoy (sin la migración 0000). Para eso no hace
falta el almacenamiento externo del paso 1: la copia **cifrada** queda como archivo descargable de la corrida de
GitHub ("Artifacts", 14 días) y usted la guarda en su computadora.

Orden: paso 2 (cuenta de respaldo) → paso 3 (repositorio privado, sin los secretos `RCLONE_*`) → **Run workflow**
→ descargar el archivo → paso 1 y 4 cuando quiera (antes de dejar el respaldo nocturno solo).

Qué se verifica en cada respaldo (si algo no coincide, la corrida queda en **rojo**):

- la copia se restaura en una base desechable y **cada tabla tiene las mismas filas y el mismo contenido** (huella
  md5 de cada fila; las tablas que cambiaron durante la copia se revisan por cantidad de filas). El archivo guarda las
  filas y la huella de lo que la copia trae, y `restore.sh` las compara todas;
- **los mismos permisos**: quién puede ejecutar cada función y leer cada tabla, qué tablas tienen reglas de filas;
- **cada foto del menú** listada en Storage está en la copia, con el mismo tamaño.

Lo ve en el **resumen** de cada corrida (paso 3.6).

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

1. SQL Editor → New query → pegue **todo** `supabase/tools/backup-account.sql` → Run. Debe mostrar UNA fila:
   **"lista: la cuenta canopy_backup puede leer 26 tablas del café y la lista de fotos; no puede cambiar los datos
   del café ni leer las cuentas de acceso (aún no puede entrar: paso 3.4)"**.
   - Si sale un **ERROR**, no se cambió nada: copie el mensaje en el chat.
   - No necesita ninguna migración. No toca ventas, inventario, personal ni fotos, ni ningún ingreso: usted y Jorge
     siguen siendo dueños y el ingreso de los aparatos del café queda igual.
   - Quita a todas las cuentas (PUBLIC) el permiso de ejecutar las funciones internas de los disparadores del café
     (hoy 3); siguen funcionando igual. Con ese permiso, cualquier cuenta que entra a la base (también la de
     respaldo) podía usarlas para cambiar una venta.
   - La cuenta queda sin contraseña y sin poder entrar hasta el paso 3.4.
2. Después de cada tanda de migraciones, vuelva a ejecutarlo como revisión: debe decir otra vez "lista" (con más
   tablas, y sin "aún no puede entrar" si ya hizo el paso 3.4). Así la cuenta también lee las tablas nuevas.

### Paso 3 · Repositorio privado de respaldos (GitHub, gratis)

1. GitHub → **New repository** → nombre `canopy-respaldos` → **Private**.
   No lo conecte a sesiones de asistentes de IA.
2. En el repositorio vacío, el enlace **uploading an existing file** (después: **Add file → Upload files**): suba el contenido de la carpeta `ops/backup/repositorio-respaldos/` de este
   repositorio, **con la carpeta `.github`** (en Mac está oculta: Cmd+Shift+. la muestra). En **Actions** debe
   aparecer "Respaldo nocturno". (Si corre esa noche antes del punto 4, falla con "Falta …": no pasa nada.)
3. En su computadora, instale `age`: **Windows**, en PowerShell `winget install --id FiloSottile.age` (luego abra
   otra ventana); **Mac**, `brew install age`. Cree las dos llaves:
   ```
   age-keygen -o llave-dueno.txt
   age-keygen -o llave-recuperacion.txt
   ```
   - Cada una muestra `Public key: age1…` (unos 60 caracteres; no use la opción `-pq`).
   - Guarde `llave-dueno.txt` en su gestor de contraseñas.
   - **Imprima** `llave-recuperacion.txt`, guárdela en un lugar seguro, y luego **borre ese archivo de la
     computadora**.
4. `canopy-respaldos` → **Settings → Secrets and variables → Actions**:
   - Pestaña **Secrets** → **New repository secret**:
     - `AGE_RECIPIENTS`: las **dos** llaves públicas `age1…`, separadas por un espacio. Nunca la línea
       `AGE-SECRET-KEY-…`.
     - `CANOPY_DB_URL`, armada directamente en la casilla del secreto (nunca en un chat, un correo ni un archivo):
       1. Supabase → **Connect** (arriba) → en la conexión por dirección (URI), **Method: Session pooler**: copie la
          dirección y péguela en la casilla. No pulse «Reset database password»: cambia la contraseña de `postgres`,
          no la de esta cuenta.
       2. **Cambie la cuenta:** `postgres.` (justo después de `postgresql://`) por `canopy_backup.`. La casilla debe
          empezar con `postgresql://canopy_backup.nbvczarfweanoxvdqplk:`. Deje igual el resto, también `/postgres` al
          final (es el nombre de la base, no la cuenta). Si vuelve a pegar la dirección de Supabase, repita este punto.
       3. Supabase → SQL Editor → **New query** (pestaña nueva y vacía) → pegue **todo**
          `supabase/tools/backup-password.sql` → **Run**, sin nada seleccionado. Debe mostrar UNA fila con la celda
          **`contrasena`**: 64 caracteres hexadecimales (cifras 0-9 y letras a-f), generados por la base a partir de
          dos UUID aleatorios. Cópiela en lugar de `[YOUR-PASSWORD]`, sin dejar ningún corchete (no trae caracteres que
          haya que cambiar).
          - Solo cambia dos cosas, y solo de `canopy_backup`: puede entrar, y su contraseña. Nada más.
          - No hace falta guardarla en otro lado: si se pierde, repita este punto (cada ejecución reemplaza la
            contraseña anterior) y actualice el secreto.
          - No queda escrita en Supabase: no está en el texto de la consulta guardada, no la escribe el registro del
            servidor ni las estadísticas de consultas, y si algo falla el mensaje de error no la lleva (vea
            "Seguridad").
          - Si sale un **ERROR** (empiece o no con "NO SE CAMBIÓ NADA"): no se cambió nada; todo el pegado es una sola
            transacción. **No cambie ningún ajuste**: copie el mensaje en el chat. Las causas que el script mismo
            detecta y nombra: la cuenta no existe (paso 2); la base anotaría el texto de las órdenes internas y, con
            él, la contraseña (`pg_stat_statements.track = all`, `pgaudit.log` con `all` o `role`, `log_min_messages`
            en `debug`); una función de revisión de contraseñas (pg_tle); o no se pudo poner la contraseña (un
            bloqueo, un permiso que falta).
          - Si la fila empieza con **REVISAR**: no corrió como una sola ejecución (por ejemplo, con una parte
            seleccionada) y puede que se haya puesto una contraseña sin mostrarla. No pasa nada: ejecútelo otra vez,
            completo, sin seleccionar nada.
          - Después de pegarla en el secreto (punto 4): copie cualquier otra cosa para que salga del portapapeles y,
            en Windows con el historial del portapapeles (Win+V) activado, bórrelo. Nunca la pegue en el chat, en un
            correo ni en un archivo. Cierre la pestaña del SQL Editor.
          - Opcional, para comprobar la cuenta: `supabase/tools/backup-account-check.sql` (solo lectura; la celda no
            trae contraseñas, correos ni valores, puede copiarla en el chat) antes y después de este punto: la única
            diferencia debe ser `can_login`, de `false` a `true`.
       4. Agregue al final `?sslmode=require` (la dirección del Session pooler no trae `?`; si trajera algo después
          de un `?`, bórrelo: después del `?` solo puede ir `sslmode=require`). Antes de
          **Add secret**, mire el comienzo de la casilla: debe decir `postgresql://canopy_backup.` y **no**
          `postgresql://postgres.` (con `postgres.` el respaldo entra como la cuenta del dueño y falla con
          `password authentication failed for user "postgres"`, como el 2026-10-13). → **Add secret**.
     - `RCLONE_CONF` y `RCLONE_REMOTE`: solo con el almacenamiento externo (paso 1; plantilla abajo).
   - Pestaña **Variables** → **New repository variable**: `SUPABASE_URL` = la dirección `production` de
     `website/config.js` (hoy `https://nbvczarfweanoxvdqplk.supabase.co`; es pública).

   Por qué el Session pooler: GitHub solo tiene IPv4 y la conexión directa de Supabase es IPv6 (salvo con el
   complemento IPv4, que se paga). El Session pooler es gratis, usa IPv4 y, en modo sesión, admite `pg_dump`.
5. Primero, sin respaldar. Si el repositorio privado todavía tiene los archivos de antes del 2026-10-14, suba
   (**Add file → Upload files**, reemplazando) `backup.sh` y, dentro de `.github/workflows/`,
   `comprobar-conexion.yml`, los dos de `ops/backup/repositorio-respaldos/`. Luego **Actions → Comprobar la
   conexión (sin respaldo) → Run workflow → Run workflow**.
   Revisa los secretos sin mostrarlos, entra como `canopy_backup` y mira solo sus permisos; no copia nada. El
   resumen debe decir `conexión verificada: entró canopy_backup (PostgreSQL 17.…); lee 26 de 26 tablas del café y
   no puede cambiar ninguna. No se copió nada`. Si dice `ERROR en el paso: revisar el secreto …`, el mensaje nombra
   la parte de `CANOPY_DB_URL` (o de `AGE_RECIPIENTS`) que hay que corregir, sin mostrar valores: corríjala
   (punto 4) y vuelva a comprobar. Si dice `ERROR en el paso: conectar con la base: …`, la línea trae la respuesta
   del servidor y qué hacer: `password authentication failed for user "canopy_backup"` es una contraseña que no es la
   de la cuenta (o la anterior, que el pooler guarda hasta un día): paso 3.4, punto 3, y arme el secreto otra vez.
   Con el verde, **Actions → Respaldo nocturno → Run workflow → Run workflow**.
   Tarda unos 2 minutos; debe terminar en verde.
6. Abra la corrida:
   - El **resumen** debe decir `restauración verificada: … tablas, …; contenido idéntico en …` (hoy 26 tablas),
     `8 archivos verificados` y `listo: … restauración: passed`. Esas líneas no tienen datos privados: puede
     copiarlas en el chat. Un "aviso" no hace fallar la corrida, pero cópielo también.
   - Abajo, en **Artifacts**, descargue `respaldo-cifrado` (un .zip). Descomprímalo: dentro, en la carpeta del año y
     el mes (por ejemplo `2026/10/`), están el `canopy-respaldo-….tar.age` y su `.sha256`. Guárdelos en `Documentos/HangingGarden-Respaldos/antes-de-migraciones/`
     (fuera de `archivo`, así nunca se retira).
   - Compruebe que su llave lo abre: en la ventana del punto 3 escriba `age -d -i llave-dueno.txt -o NUL ` (Mac:
     `-o /dev/null `), arrastre el archivo `.tar.age` a la ventana y pulse Enter. Sin mensaje = bien. "no identity
     matched" = esa llave no es la de `AGE_RECIPIENTS`. Después borre `llave-dueno.txt` de la computadora (queda en
     su gestor de contraseñas).
   - Si la corrida dice "password authentication failed", vuelva a armar `CANOPY_DB_URL` (punto 4). Con
     `for user "postgres"`, la dirección quedó con la cuenta del dueño: cambie `postgres.` por `canopy_backup.`.
     Desde 2026-10-14 `backup.sh` revisa la dirección antes de conectar y lo dice así, sin intentar entrar. Un
     secreto no se puede leer: para armarlo otra vez hace falta la contraseña; si ya no la tiene, el paso 3.4
     (punto 3) genera otra.

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
   Escriba **RESTAURAR** cuando lo pida. Al final debe decir **OK: … filas iguales al respaldo**. Las fotos del
   menú quedan en la carpeta `fotos-restauradas-<fecha>`, junto al archivo del respaldo.
3. Abra el sitio de pruebas y revise las ventas de ayer y el inventario.
4. Esta prueba deja datos **reales** en pruebas. Al terminar: `canopy-respaldos` → **Ensayo en pruebas** con
   vaciar = `si`, y `supabase/tools/staging-logins.sql` en el SQL Editor de PRUEBAS, para que pruebas vuelva a la
   copia anonimizada (docs/PRUEBAS.md). Borre también la carpeta `fotos-restauradas-<fecha>`: no está cifrada y
   puede traer facturas (si quedó dentro de `archivo`, se iría sin cifrar a la memoria USB del paso 5).

**Una vez al año, haga la prueba con la llave de recuperación impresa**, para comprobar que sirve.

## Desastre: recuperar el café en otro proyecto

1. Cree un proyecto nuevo de Supabase.
2. Use `restore.sh` con el respaldo más reciente:
   ```
   bash ops/backup/restore.sh <archivo> <llave> "<conexión del proyecto NUEVO>"
   ```
   - El script **se niega** a restaurar encima de una base que ya tenga datos.
   - Las fotos del menú quedan en la carpeta `fotos-restauradas-<fecha>`, junto al archivo del respaldo. No está
     cifrada: bórrela cuando haya subido las fotos (vea "Después de restaurar").
   - Las cuentas de acceso no van en el respaldo: se crean a mano (vea "Cuentas de acceso").
3. Haga lo de "Después de restaurar" y "Cuentas de acceso".
4. Cambie la dirección del proyecto en `website/config.js` y publique la versión (`docs/PUBLICAR.md`).

Tiempo estimado: **menos de 2 horas**. Las ventas del día que quedaron en las tabletas sin internet se suben
solas cuando vuelven a conectarse.

### Después de restaurar

- **Authentication**: apague otra vez "Allow new users to sign up" y los ingresos anónimos; ponga la dirección del
  sitio (URL Configuration).
- **Fotos**: el depósito y sus reglas no van en el respaldo. SQL Editor del proyecto NUEVO:
  ```sql
  insert into storage.buckets (id, name, public) values ('menu-photos', 'menu-photos', true) on conflict do nothing;
  create policy "menu photos read" on storage.objects for select to anon, authenticated using (bucket_id = 'menu-photos');
  create policy "menu photos owner write" on storage.objects for all to authenticated
    using (bucket_id = 'menu-photos' and ((select public.is_owner()) or (select public._unlocked_any_device())))
    with check (bucket_id = 'menu-photos' and ((select public.is_owner()) or (select public._unlocked_any_device())));
  ```
  Luego suba la carpeta `menu-photos` (dentro de `fotos-restauradas-<fecha>`) a Storage → `menu-photos`, y después
  borre `fotos-restauradas-<fecha>` de la computadora (no está cifrada). Las fotos subidas guardan la dirección del
  proyecto viejo; en el SQL Editor del proyecto NUEVO (cambie `<viejo>` y `<nuevo>`
  por las dos direcciones de proyecto):
  ```sql
  update public.menu_items set photo_url = replace(photo_url, 'https://<viejo>.supabase.co/', 'https://<nuevo>.supabase.co/')
   where photo_url like 'https://<viejo>.supabase.co/%';
  ```
- **Facturas de gastos** (solo si ya aplicó la 0015): cree también el depósito `expense-receipts` y sus reglas con
  las líneas de `storage.` de las migraciones 0015 y 0025; los archivos se suben igual que las fotos.
- **Vault**: vuelva a poner los secretos (token del BCCR).
- **Respaldos**: en el proyecto nuevo, paso 2 y una contraseña nueva (paso 3.4); actualice `CANOPY_DB_URL` y
  `SUPABASE_URL` en `canopy-respaldos`.

### Cuentas de acceso

No van en el respaldo. En el proyecto NUEVO, en este orden:

1. Authentication → Users → **Add user**: su ingreso personal, el de Jorge y el de los aparatos del café, cada uno
   con una contraseña nueva.
2. SQL Editor: `select public.make_owner('<su correo>');` y `select public.make_owner('<correo de Jorge>');`. Los dos
   son dueños.
3. El ingreso de los aparatos del café: `supabase/tools/cafe-login.sql` con su correo y su fecha de creación en UTC
   (el día de la restauración; si lo creó después de las 6 p. m., es el día siguiente). Si responde «… (creado
   AAAA-MM-DD) no es el ingreso creado el …» y el correo que muestra es el de los aparatos, use la fecha entre
   paréntesis. Se niega si no hay otro dueño. Esto es solo para el proyecto NUEVO: el ingreso de hoy no se toca.
4. Cada aparato vuelve a iniciar sesión (en un proyecto nuevo pasa de todos modos: las sesiones nunca viajan).
5. El código del teléfono (2FA) se vuelve a activar, solo en el ingreso personal de cada dueño.
6. El contador (después de la 0025, primero active el código del teléfono en su ingreso personal): Inicio →
   Ingreso del propietario → Ingreso del contador → Dar acceso.

El personal **no** pierde sus PIN: están en la base.

## Quitar la cuenta de respaldo

Solo si deja de usar estos respaldos o sospecha de la cuenta. **Para una contraseña sospechosa no basta con generar
otra** (paso 3.4, punto 3): el pooler de Supabase guarda la contraseña anterior hasta un día y una conexión que ya
estaba abierta sigue viva. Haga esta reversión completa (cierra sus conexiones y quita la cuenta) y luego el paso 2, el
paso 3.4 y el secreto nuevo:

1. GitHub → `canopy-respaldos` → **Actions**: desactive "Respaldo nocturno", "Comprobar la conexión (sin respaldo)" y
   "Ensayo en pruebas" (**Disable workflow**).
2. SQL Editor → New query → pegue **todo** `supabase/tools/backup-account-rollback.sql` → Run. Debe decir
   **"listo: la cuenta canopy_backup ya no existe (…)"**. Si dice "REVISAR" o sale un **ERROR**, copie la fila o el
   mensaje en el chat; ejecutarlo otra vez no hace daño.
3. Borre el secreto `CANOPY_DB_URL` (ya no sirve).
4. **Nunca** borre la copia cifrada guardada ni las llaves age: sin ellas esa copia no se puede abrir.

No sirve `drop role canopy_backup` solo: falla en cuanto la cuenta tiene permisos y no cierra sus conexiones. El
historial de respaldos (la tarjeta de Inicio) no se borra. Para volver a tenerla: paso 2 y paso 3.4.
Tampoco devuelve a todas las cuentas el permiso de ejecutar las funciones internas de los disparadores que quitó el
paso 2: no hace falta, el café sigue funcionando igual.

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
| GitHub Actions en el repositorio privado: 1–3 min por corrida, unos 90 al mes de los 2 000 gratis; las copias de 14 días ocupan unos 60 MB de los 500 MB gratis. Sin tarjeta registrada GitHub no cobra: si se acabaran, detiene las corridas | $0 |
| Cloudflare R2 (dentro de los 10 GB gratis) | $0 |
| age, rclone, PostgreSQL | $0 (gratuitos) |
| Supabase Free: no da copias propias (por eso este respaldo); pausa solo proyectos sin uso por 7 días, no el del café | $0 |
| Supabase Pro (opcional: agrega copias propias de Supabase por 7 días, sin las fotos) | US$25/mes |

## Seguridad

- **`canopy_backup` no puede cambiar ni borrar los datos del café ni entrar como nadie**: no lee las cuentas de
  acceso (correos, contraseñas cifradas, sesiones, enlaces de recuperación) ni las contraseñas de la base. **Sí lee
  todos los datos del negocio** (ventas, personal y PIN cifrados, teléfonos de huéspedes): su contraseña solo vive en
  el secreto de GitHub. Si sospecha algo: "Quitar la cuenta de respaldo" (cierra sus conexiones), paso 2, paso 3.4 y
  el secreto nuevo.
- **La contraseña de respaldo no queda escrita en Supabase.** La genera la base dentro del pegado
  (`supabase/tools/backup-password.sql`) y se muestra una sola vez: no está en el texto de la consulta guardada, no la
  escribe el registro del servidor ni las estadísticas de consultas (medido en PostgreSQL 16 y 17 con los ajustes de
  Supabase; el script se niega, sin cambiar nada, si un ajuste sí la anotaría), y si algo falla el mensaje de error no
  la lleva. Queda solo en el secreto de GitHub (y en su portapapeles hasta que copie otra cosa).
- Como toda cuenta que entra a la base, con esa contraseña alguien también podría guardar objetos temporales (llenar
  el espacio de la base), enviar avisos internos o cambiar la contraseña de la propia cuenta (eso solo deja sin
  respaldo; el remedio es "Quitar la cuenta de respaldo"). Desde la 0002 anota sus respaldos, así que también
  podría poner verde la tarjeta de Inicio: la prueba es el resumen de la corrida en GitHub o su propia restauración.
- **Mantenga privado el repositorio `canopy-respaldos` y active el código del teléfono (2FA) en su cuenta de
  GitHub**: quien pueda cambiar ese repositorio puede usar el secreto.
- **GitHub y el almacenamiento solo tienen llaves públicas** (`age1…`). Pueden cifrar, nunca descifrar.
- **La llave de escritura del almacenamiento no puede borrar** respaldos bloqueados.
- **Con la contraseña de respaldos solo corre código del repositorio privado.** El "Ensayo en pruebas"
  (docs/PRUEBAS.md) usa las migraciones del repositorio público, pero solo contra el proyecto de PRUEBAS, enviadas
  como SQL puro (`psql -c`: ningún comando de terminal escrito en esos archivos se ejecuta), y la comparación final
  corre en un paso sin contraseñas.
- **Restaurar no abre permisos.** Supabase da a los visitantes acceso a cada función nueva; al restaurar, eso se
  apaga mientras se cargan las funciones y se comprueba que los permisos quedaron idénticos a los del respaldo.
- **Nunca envíe** contraseñas, llaves privadas ni direcciones de conexión por chat ni por correo.
