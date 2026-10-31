# Rótulos exteriores — Hanging Garden Café

Dos rótulos de **70 cm × 110 cm** (vertical) para colocar fuera del local, cerca de la acera.

| Rótulo | Contenido | Archivos listos para imprenta |
|---|---|---|
| Menú | El menú completo de hanginggardencafe.com (8 categorías, con precios en colones, sin Adventure Box) con las 12 fotos de productos, el logo real y el marco de acuarela de la web | `salida/menu-70x110cm.pdf` · `salida/menu-70x110cm.png` |
| Promocional | Rótulo estilo Starbucks: foto grande + 3 desayunos, 3 pastelería, 3 batidos | `salida/promo-70x110cm.pdf` · `salida/promo-70x110cm.png` |

Las vistas previas pequeñas (`salida/*-preview.jpg`) son solo para revisar en pantalla, no para imprimir.

## De dónde sale el contenido del menú

La red de la sesión en la que se hicieron los rótulos no permitía abrir hanginggardencafe.com ni la base de
datos del gestor de menú (Supabase), así que la lista se reconstruyó a partir de la rama `gh-pages` del
repositorio (menú incrustado en `index.html`) y de `supabase/menu-photos.sql` (lista de productos del gestor
de menú con foto), más los productos nuevos que el dueño indicó con sus fotos (Bun & Roll Breakfast, Bagel,
The Hanging Stack, Cortado, Canela Cloud Latte, Menti Verde, Cinnamon Roll, Triple Chocolate Croissant).

Se excluyen a propósito **Adventure Box** (a petición del dueño) y **Extras & Combos** (ayudas de caja que la
web tampoco muestra).

Los precios son los publicados en la web. Nueve productos nuevos no tienen precio en el repositorio y llevan el
marcador **₡ ?** en dorado hasta que el dueño los confirme: Bun & Roll Breakfast, Bagel, The Hanging Stack,
Cortado, Canela Cloud Latte, Menti Verde, Triple Chocolate Croissant, Cinnamon Roll y Flauta de Chocolate.
Los precios de batidos son en agua; la nota bajo la lista indica el recargo con leche.

Marca: logo `marca/logo.png`, acuarelas `marca/deco-sprig.png` y `marca/deco-quetzal.png`, paleta y
tipografías (`Playfair Display`, `Figtree`, `Dancing Script`, `Spline Sans Mono`) tomadas de `page.css` de la web.

## Especificaciones para la imprenta

- Tamaño final: 700 mm × 1100 mm, sin sangrado (los fondos llegan hasta el borde).
- El PDF está a tamaño real, con texto vectorial y fotos incrustadas.
- El PNG está a 5292 × 8316 px (≈192 ppp a tamaño real) por si la imprenta prefiere imagen plana.
- Márgenes de seguridad: todo el texto queda a más de 30 mm del borde.
- Si la imprenta pide sangrado (normalmente 3–5 mm), se puede regenerar cambiando `W_MM`/`H_MM` en `render.js`
  y el tamaño en `base.css`.

## Cómo regenerar

Los diseños son HTML/CSS (`menu.html`, `promo.html`, `base.css`) y se renderizan con Chromium vía Playwright:

```bash
cd rotulos
node render.js            # genera los dos
node render.js promo      # solo uno
python3 preview.py menu promo   # vistas previas JPG
```

Para cambiar un nombre, una foto o el recorte de una foto, editar el HTML correspondiente
(cada `<img>` tiene su `object-position` para ajustar el encuadre) y volver a renderizar.

## Créditos tipográficos

Playfair Display, Figtree, Dancing Script y Spline Sans Mono, todas bajo la SIL Open Font License
(ver `fonts/OFL.txt`).
