# Placa del jardín · Gabriel Barboza Villalobos (D-068)

La placa física del homenaje es breve: el nombre de Gabriel, una dedicatoria y el código QR con
«Conozca su historia / Discover his story». La historia completa está en la página web, no en la placa.

| Archivo | Para qué |
|---|---|
| `placa-gabriel-barboza.svg` | La placa completa, 30 × 40 cm (vertical). Contiene «Homenaje», el nombre, la dedicatoria del dueño, el QR, la invitación bilingüe y la dirección escrita debajo del QR. |
| `qr-gabriel-barboza.svg` | Solo el QR, vectorial (para la imprenta). |
| `qr-gabriel-barboza.png` | Solo el QR, 1176 × 1176 px (24 px por módulo, 300 ppp: unos 10 cm). |

**Dedicatoria** (la frase principal del homenaje, aprobada por el dueño el 2026-11-09):
«Su conocimiento, generosidad y amor por las orquídeas dejaron una huella que continúa floreciendo en este jardín»

## El código QR

- Abre exactamente **https://hanginggardencafe.com/gabriel-barboza**. Esa dirección no cambia nunca.
- Versión 6, corrección de errores **H**: se sigue leyendo aunque hasta un 30 % del código esté rayado o sucio.
- Margen blanco de 4 módulos alrededor (el estándar).
- Tinta verde oscuro `#17352a` sobre blanco: contraste de unos 13 : 1.
- En la placa mide **72 mm** (1,47 mm por módulo). Se lee cómodamente a unos 50–70 cm. Colóquela a la altura de la
  vista, donde la gente pueda acercarse.

**Verificado el 2026-11-10** con un lector independiente (jsQR), que leyó la dirección exacta en todos los casos:

- el SVG a 100, 160, 300 y 1176 px;
- el PNG a 100, 160, 300 y 1176 px;
- la placa completa renderizada a 600, 900 y 1400 px de ancho.

La prueba automática 420 (G10) comprueba en cada corrida tres cosas en los tres archivos: que contienen exactamente el
código de esa dirección, que el margen está limpio y que el contraste es suficiente. Falla si cambia un solo módulo.

## Para imprimir

- **Material de exterior:** aluminio compuesto o PVC con impresión UV, resistente a la humedad del bosque nuboso.
- **Tipografías:** Playfair Display, Figtree y Spline Sans Mono (Google Fonts, gratuitas). La imprenta debe
  instalarlas o convertir el texto a curvas, y no debe cambiar el QR (ni recolorearlo, ni reducirlo por debajo de 5 cm).
- **Antes de fijar la placa:** la página debe estar publicada. Abra la dirección en un teléfono y escanee una prueba
  impresa del QR.

## Regenerar

`node tools/placa/build.js` vuelve a escribir los tres archivos. Antes hay que instalar las herramientas de las
pruebas (`npm ci` en `tests/e2e`), porque el script usa la misma librería QR que las pantallas del café.
