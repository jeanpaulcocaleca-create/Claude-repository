# Imagen en el historial público · propuesta para retirarla (BD-041)

Fecha: 2026-10-23 · Autor: Claude · Estado: **propuesta. No se reescribió nada ni se hizo force-push.** Se necesita la autorización expresa del propietario.

## Qué pasó

- **El archivo:** `basecamp/revision-visual-evidencia.jpg`, de 174 KB.
- **Cuándo:**
  - se agregó en el commit `ae25900` (BD-040);
  - se quitó minutos después en el commit `6bda16f`.
- **Dónde está:**
  - solo en la historia de la rama `claude/brave-archimedes-ar8uc1`, la del PR #2, abierto como borrador;
  - no está en `main`, ni en `gh-pages` (el sitio del café), ni en el repositorio del sitio de Basecamp.
- **Qué contiene:** recortes de capturas de la vista previa privada: la portada con la foto de una habitación, la tarjeta de reserva, La estadía, el encabezado y las tarjetas de «Otras habitaciones», con fotos reales ya aprobadas.
- **Qué no contiene:**
  - datos de huéspedes ni personas;
  - la foto del café;
  - cámaras ni detalles de seguridad;
  - contraseñas ni datos privados.
- **Quién puede verlo hoy:**
  - cualquiera que abra ese commit en GitHub, en la lista de commits del PR #2 o en un enlace directo al archivo;
  - cualquiera que haya descargado la rama después de las 16:00 del 2026-10-23, por ejemplo, otro agente.

## Opciones

### A · Dejarlo como está

- **Riesgo:** bajo. El archivo ya no está en la versión actual. Solo lo ve quien busque en ese commit antiguo.
- **Consecuencias:** ninguna.

### B · Reescribir el historial de esa rama (la propuesta)

Quita el archivo de la historia de la rama, sin cambiar ningún otro contenido.

**Pasos:**
1. **Respaldo local:** un archivo de la rama actual, guardado solo en el entorno de Claude. No se sube a GitHub, porque un respaldo en GitHub mantendría la imagen pública.
2. **Reescritura:** se rehacen desde `00f5f24` los commits que siguen, con el mismo contenido, pero sin la imagen:
   - `ae25900`, el que la agregó;
   - `6bda16f`, el que la quitó;
   - los commits posteriores.
3. **Verificación antes de subir:**
   - la versión final queda idéntica a la actual: la comparación no da diferencias;
   - el archivo no aparece en ningún commit de la rama.
4. **Subida protegida:** `git push --force-with-lease`. Si alguien hubiera subido algo en ese momento, la subida se cancela sola y no se pierde nada.
5. **Referencias:** se actualizan en el CODEX los identificadores de los commits que cambian.
6. **GitHub (solo el propietario puede hacerlo):** GitHub conserva por un tiempo los commits viejos, accesibles por enlace directo, y el PR muestra el aviso «force-pushed».
   - Para borrarlos del todo, el propietario pide a GitHub Support que elimine las vistas en caché, según su guía para quitar datos sensibles de un repositorio.
   - Claude puede redactar ese mensaje.

**Riesgos y consecuencias:**
- **Identificadores:** cambian los de `ae25900` en adelante. Los enlaces a esos commits en el chat o en el CODEX dejan de funcionar; los del CODEX se corrigen en el mismo paso.
- **Otros agentes:** quien tenga una copia de la rama, como ChatGPT o Codex, debe actualizarla con `git fetch` y `git reset --hard`. Si subiera su copia vieja, la imagen volvería; por eso se le avisa antes.
- **PR #2:**
  - sigue abierto, con sus comentarios;
  - algún comentario sobre esos commits podría marcarse como desactualizado;
  - muestra el aviso «force-pushed».
- **Copias ya descargadas:** no se borran.
- **Lo que no se toca:** `main`, `gh-pages` (el sitio del café), el repositorio del sitio de Basecamp y la configuración de GitHub.
- **Regla del repositorio:** dice «nunca force-push en una rama donde trabaja otro agente». En esta rama solo sube Claude; ChatGPT la lee. Por eso solo se hace con su autorización expresa.

### C · Hacer privado el repositorio (no recomendado)

- **Riesgo:** el repositorio publica el sitio del café con GitHub Pages. En el plan gratuito, hacerlo privado puede dejar ese sitio fuera de línea.
- **Además:** cambiar la configuración de GitHub le corresponde al propietario, no a Claude.

## Recomendación

- **Por el contenido:** son fotos ya aprobadas, sin datos personales, y la exposición fue breve. Por eso la opción A es aceptable.
- **Si usted prefiere retirarla:** la opción B es la forma segura. Solo afecta a esta rama, la subida se protege con `--force-with-lease` y el contenido final no cambia. Lo ideal es completarla con la solicitud a GitHub Support.

## Lo que necesito de usted

- **Para la opción B:** escribir «Autorizo reescribir el historial de la rama claude/brave-archimedes-ar8uc1 y hacer force-push para quitar la imagen».
- **Para la solicitud a GitHub Support:** decir si quiere que Claude la redacte.
- **Si prefiere la opción A:** basta con decirlo, y no se hace nada más.
