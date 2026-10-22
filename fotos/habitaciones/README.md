# Fotos de habitaciones (retocadas) — 22 de octubre de 2026

Cinco fotos distintas de las habitaciones, retocadas con `mejorar_fotos.py` (sombras
levantadas, balance de blancos neutro, luces protegidas, claridad, vibrance y enfoque
suaves). Mismo tamaño que las originales: 1100 × 828 px.

El dueño envió ocho archivos; tres eran repetidos (el 3 es igual al 2, el 6 igual al 5 y el 8
igual al 1).

Las fotos viven en la biblioteca de medios de Higgsfield, como el resto de los activos del
sitio (ver `website/ASSETS.md` en la rama del sitio). Las filas de abajo están en el mismo
formato que ese manifiesto, listas para copiarlas cuando se decida dónde van en el sitio.

| Deploy path | Source URL |
|---|---|
| assets/hab-1.jpg (dos camas, pared de madera y saco de café El Trapiche; enviada como 1 y 8) | https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/cc7cbdcc-b353-4616-9b7a-2fed0896c2b2.png |
| assets/hab-2.jpg (cama junto a la ventana con vista al valle, espejo redondo; enviada como 2 y 3) | https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/cd4aa66d-f3a1-4e21-b97e-7d466e6c9151.png |
| assets/hab-4.jpg (cama de lado, rama de flores rosadas, puerta al balcón) | https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/873c6a71-0c14-4089-8bcc-e895e747334a.png |
| assets/hab-5.jpg (dos camas, cuadro de tucán, rosas rojas; enviada como 5 y 6) | https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/517f1805-f45e-41b5-bd5d-3a933fb9f265.png |
| assets/hab-7.jpg (cama grande, cuadro de orquídeas y piedras, saco de café) | https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/ead0c588-ee59-4453-be28-fa89bab95c8b.png |

Notas:

- La biblioteca nombra las importaciones con extensión `.png`, pero los bytes son los JPEG
  originales (verificado el 22 de octubre de 2026: 1100 × 828, JPEG, mismo tamaño de archivo).
  El nombre de despliegue (columna izquierda) decide la extensión con la que se guarda en
  `website/assets/`.
- IDs de medio en Higgsfield, por si hay que buscarlas: `cc7cbdcc` (1), `cd4aa66d` (2),
  `873c6a71` (4), `517f1805` (5), `ead0c588` (7).
- Las fotos se subieron por importación desde una URL pública de este repositorio (commit
  `175a27d`), porque la red de la sesión no permitía la carga directa. Los JPEG se quitaron de
  la rama después; siguen disponibles en ese commit si hiciera falta reimportar.
- Para retocar más fotos con el mismo criterio:
  `python3 mejorar_fotos.py foto1.webp foto2.jpg --out salida/`.
