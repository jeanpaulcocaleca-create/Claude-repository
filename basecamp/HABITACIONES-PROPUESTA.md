# Fotos y páginas de habitaciones · propuesta (BD-027, prioridad 1)

Fecha: 2026-10-23 · Autor: Claude · Estado: **A y B aprobadas e implementadas** (commit `84f1bfd` de `basecamp-website`). **C y D siguen como propuesta**, sin implementar.

Se conservan los colores, las tipografías, el logo, los textos y las fotos originales. No se agregan servicios externos y todo funciona también sin JavaScript. El sitio sigue en vista previa privada.

## 1 · Diagnóstico

Medido en la vista previa construida el 2026-10-23: teléfono de 390 × 844 px y escritorio de 1280 px.

| # | Dónde | Qué pasa hoy |
|---|---|---|
| D1 | Habitación, teléfono | Las fotos se apilan una debajo de otra. Con 2 fotos, el nombre de la habitación empieza a 676 px y el resumen queda debajo de la barra fija. Con las 5 fotos que pide la lista, el nombre bajaría a unos 1.400 px, casi dos pantallas. |
| D2 | Habitación, teléfono | La caja de reserva aparece a 1.827 px, después de los datos y las comodidades. |
| D3 | Habitación | Las camas y los huéspedes se repiten cuatro veces: subtítulo, resumen, fila de datos y sección «Datos de la habitación». |
| D4 | Habitación, escritorio, 2 fotos | La segunda foto se recorta a una franja vertical angosta. Las fotos son horizontales (4:3) y se pierde la mitad. |
| D5 | Habitación, escritorio, 1 foto (El Quetzal) | La foto se recorta a 21:9: se pierde el 43 % de su altura y se amplía más allá de sus 1100 px, así que se ve suave. |
| D6 | Habitación | No hay forma de ver una foto en grande. |
| D7 | Caja de reserva | Repite el nombre de la habitación y el texto del botón. No da ningún dato útil antes de reservar. |
| D8 | Habitaciones, teléfono | La tabla comparativa necesita desplazamiento lateral (se corta la columna de huéspedes) y repite lo que ya dicen las tarjetas. |
| D9 | «Otras habitaciones», teléfono | Dos tarjetas grandes: unos 1.100 px de desplazamiento al final de cada habitación. |
| D10 | Panel | Las fotos pueden guardarse con descripciones vacías de sentido (ya pasó: «space»). |

Lo que ya funciona bien:
- la primera foto carga con prioridad y las demás de forma diferida;
- cada foto tiene nombre descriptivo y descripción en ambos idiomas;
- la barra fija del teléfono lleva a la reserva de esa habitación;
- no hay desplazamiento lateral, salvo la tabla de D8;
- no hay fallas de accesibilidad.

## 2 · Propuestas

### A · Galería de cada habitación (D1, D4, D5, D6)

- **A1 · Teléfono: carrusel deslizable.**
  - Una foto a la vez, en su proporción real 4:3, sin recortes.
  - Contador «1 / 3», puntos y botones anterior y siguiente.
  - No avanza solo.
  - Sin JavaScript, el desplazamiento horizontal funciona igual.
  - El nombre de la habitación queda en la primera pantalla.
- **A2 · Escritorio: mosaico según el número de fotos.**
  - 1 foto: grande, sin recortar, junto al nombre y la caja de reserva.
  - 2 fotos: dos mitades iguales.
  - 3 o más: una grande y dos chicas, con el botón «Ver las N fotos».
- **A3 · Visor a pantalla completa.**
  - Se abre al tocar cualquier foto.
  - Se desliza o se usa con flechas; Esc o un botón lo cierran.
  - Muestra el contador y la descripción como pie de foto.
  - Usa la versión más grande disponible de cada foto.
  - Hecho con el elemento nativo del navegador (`<dialog>`), sin librerías y accesible con teclado y lector de pantalla.

### B · Página de la habitación (D2, D3, D7)

- **B1 · Ficha compacta bajo el nombre.** Una sola fila de datos con íconos: camas, huéspedes, baño privado con agua caliente, Wi-Fi gratuito y número de habitaciones de este tipo. Se quita la sección repetida «Datos de la habitación».
- **B2 · Orden en teléfono.** Fotos, nombre y ficha, caja de reserva, descripción, comodidades y otras habitaciones. Así la reserva queda en la primera o la segunda pantalla.
- **B3 · Caja de reserva.** En lugar de repetir el nombre y el texto del botón, una línea útil con el texto de pago ya aprobado (BD-024, BD-025): «No se cobra nada al reservar · paga al llegar». Las condiciones de cancelación siguen apagadas hasta BQ-26.
- **B4 · «Bueno saber».** Un bloque corto con datos ya confirmados y enlace a La estadía:
  - entrada desde las 15:00 y salida hasta las 11:00;
  - desayuno en Hanging Garden Café desde las 6:00, no incluido;
  - estacionamiento gratuito en la calle;
  - guardado de equipaje.
- **B5 · Otras habitaciones, en teléfono.** Tarjetas compactas: foto pequeña a la izquierda, nombre y subtítulo a la derecha.

### C · Página Habitaciones y tarjetas (D8)

- **C1 · Comparación en teléfono.** Filas apiladas sin desplazamiento lateral, o se quita la tabla en teléfono porque las tarjetas ya dicen lo mismo. En escritorio queda igual.
- **C2 · Tarjetas.**
  - Toda la tarjeta se puede tocar.
  - Muestran un pequeño contador «N fotos» sobre la imagen.
  - Los botones quedan alineados abajo.

### D · Panel (D10)

- **D1 · Ayuda en el campo Fotos.**
  - El orden recomendado: vista general, camas, baño, ventana, detalle.
  - La meta de 5 fotos por habitación.
- **D2 · Descripciones de las fotos.** La publicación se detiene, con un mensaje claro, si una descripción tiene menos de tres palabras.
- **D3 (opcional) · Página Fotos.** Las fotos de las habitaciones cuentan para las 12 que la página necesita, en un álbum «Habitaciones», sin volver a subirlas.

## 3 · Orden propuesto y verificación

1. A, galería y visor: el mayor cambio visible.
2. B, página de la habitación.
3. C y D.

En cada paso:
- se corren las pruebas automáticas;
- se revisa la accesibilidad (axe) y que no haya desplazamiento lateral a 360 px;
- se prueba con teclado y con lector de pantalla;
- se comparan capturas de antes y después en teléfono y escritorio.

Se agregan pruebas que verifican que ninguna foto se recorta en el visor y que la galería funciona sin JavaScript.

## 4 · Límite de las fotos actuales

Las fotos miden 1100 px de ancho. Se ven bien en teléfono, pero en el visor de escritorio y en pantallas de alta resolución se verán algo suaves. No se retocan. Las fotos nuevas de 2400 px o más (`docs/FOTOS-FALTANTES.md` en `basecamp-website`) lo resuelven.
