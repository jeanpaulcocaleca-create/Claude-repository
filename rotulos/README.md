# Rótulos exteriores — Hanging Garden Café

Dos rótulos de **70 cm × 110 cm** (vertical) para colocar fuera del local.

| Rótulo | Contenido | Archivos listos para imprenta |
|---|---|---|
| Menú | Menú general con las 12 fotos de productos (desayunos, pastelería, café, batidos) | `salida/menu-70x110cm.pdf` · `salida/menu-70x110cm.png` |
| Promocional | Rótulo estilo Starbucks: foto grande + 3 desayunos, 3 pastelería, 3 batidos | `salida/promo-70x110cm.pdf` · `salida/promo-70x110cm.png` |

Las vistas previas pequeñas (`salida/*-preview.jpg`) son solo para revisar en pantalla, no para imprimir.

## Especificaciones para la imprenta

- Tamaño final: 700 mm × 1100 mm, sin sangrado (los fondos llegan hasta el borde).
- El PDF está a tamaño real, con texto vectorial y fotos incrustadas.
- El PNG está a 5292 × 8316 px (≈192 ppp a tamaño real) por si la imprenta prefiere imagen plana.
- Márgenes de seguridad: todo el texto queda a más de 30 mm del borde.
- Si la imprenta pide sangrado (normalmente 3–5 mm), se puede regenerar con sangrado cambiando `W_MM`/`H_MM` en `render.js` y el tamaño en `base.css`.

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

- Playfair Display (SIL Open Font License, ver `fonts/OFL.txt`) para títulos.
- Inter para nombres de productos y textos.
