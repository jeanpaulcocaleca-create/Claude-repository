# Instalar las TV de los clientes (guía para el técnico)

Hay dos TV nuevas:
- **Pantalla A:** el menú con precios.
- **Pantalla B:** productos, marca e invitaciones.

Cada una abre una página del sitio del café en su navegador. No hace falta ninguna app, cuenta ni servicio nuevo.

> **Antes de ir al café:** el dueño ya publicó las páginas nuevas y aplicó la migración 0036
> (`docs/ACTIVACION-PANTALLAS.md`, pasos 1 a 3). Si no, la TV no encuentra la página.

## 1. Montaje

| | Pantalla A (menú) | Pantalla B (promociones) |
|---|---|---|
| Altura | Borde de abajo a unos **2 m**, inclinada 5 a 10° hacia abajo | Centro a **1,5 – 1,8 m** |
| Dónde | Visible desde la fila, antes de llegar a la caja | Donde la gente espera o se sienta |
| Evitar | Una ventana enfrente (refleja), vapor de la máquina de espresso, la puerta abierta a la neblina | Lo mismo |
| Tipo de pantalla | **No OLED**: el encabezado y las columnas quedan fijos muchas horas y marcarían la pantalla | Cualquiera |

- Supresor de picos para la TV y el router.
- Cable de red si se puede. Si es Wi-Fi, que sea de 5 GHz y que llegue bien a ese lugar: mida con un teléfono antes.
- **Sin sonido.**

## 2. Ajustes de la TV (Google TV / Android TV)

Los nombres cambian un poco según la marca; busque estas opciones en **Ajustes**:

1. **Apagado automático / Ahorro de energía / Eco:** desactivado. Si la TV se apaga sola al no tocar el control, la
   pantalla queda negra.
2. **Protector de pantalla / Modo ambiente:** desactivado, o el tiempo más largo posible.
3. **Encendido después de un corte de luz** (a veces «Comportamiento al encender»: *último estado* o *encendido*):
   que vuelva **encendida**.
4. **Fecha y hora:** automáticas, zona de **Costa Rica**. Las páginas usan la hora del servidor, pero ayuda.
5. **Imagen:** brillo alto si hay ventana; modo «Estándar».
6. **Sonido:** en cero.

## 3. Abrir la página en la TV

1. Abra el navegador de la TV (Chrome si está instalado).
2. Escriba la dirección **exacta**. El dueño la ve en `pantallas.html`, en la tarjeta de cada TV, con un botón para
   copiarla:
   - Pantalla A: `https://hanginggardencafe.com/pantalla-menu?tv=menu-1`
   - Pantalla B: `https://hanginggardencafe.com/pantalla-promos?tv=promos-1`
3. Presione **OK** en el control: la página pasa a pantalla completa. Al abrir, un aviso lo recuerda durante 12 segundos.
4. Guarde la dirección como marcador o página de inicio, para volver a abrirla rápido.

**Si la TV está vertical:** las TV de Google no giran la imagen, así que la gira la página. El dueño lo cambia en
`pantallas.html` → la TV → **Posición**:
- **derecha**: el borde de arriba de la TV quedó a la **izquierda**;
- **izquierda**: el borde de arriba quedó a la **derecha**.

La TV toma el cambio sola en menos de un minuto.

## 4. Comprobar con el diagnóstico

1. Agregue `&diag=1` al final de la dirección, por ejemplo
   `https://hanginggardencafe.com/pantalla-menu?tv=menu-1&diag=1`.
2. Abajo a la derecha aparece un cuadro con:
   - la TV y sus ajustes, y de dónde salen;
   - la mayúscula en centímetros (con su mínimo);
   - las páginas;
   - el estado de los precios y la edad de la última lectura;
   - la versión.
3. Debe decir **Precios: al-dia**. En la Pantalla A, desde la v2 también dice **«cabe en una pantalla: sí/no»** con la
   letra como % de la meta: si dice «no», la TV pagina (nunca achica la letra bajo el mínimo); el dueño puede elegir en
   `pantallas.html` la densidad compacta, el inglés en línea o solo español, o menos categorías para esa TV.
4. Abra otra vez la dirección **sin** `&diag=1`. El cuadro no debe quedar a la vista de los clientes.

### 4.1 Las TV de 32 pulgadas del café
Las dos TV reales miden 32" (70,8 × 39,8 cm). A esa medida el menú completo **nunca cabe en una pantalla legible**: la
Pantalla A lo reparte en páginas y nunca achica la letra bajo el mínimo (0,8 cm de mayúscula por metro). Medido con el
menú real: a 1,5 m, 3 páginas (2 con densidad compacta y sin inglés); a 2 m, 6 páginas (3 compacta sin inglés); a 2,5 m,
9 (6); a 3 m con inglés debajo la letra mínima ya no cabe en dos columnas y el diagnóstico dice «NO CABE». Por eso:
- El dueño confirmó (2026-11-02) que los clientes quedan a unos **3 m**: a esa distancia el menú completo necesita 8
  páginas o más, así que la TV del menú muestra el **menú resumido**: en Pantallas → «Productos que muestra», unos 12
  productos elegidos por el dueño (3 páginas de 28 s; 8–10 en 2–3 categorías para 2 páginas; letra de 2,4–2,7 cm), con **Densidad: compacta** e **Inglés: no**;
  el menú completo sigue en el QR. Si la TV queda a 1,5–2 m, el menú completo cabe en 2–3 páginas con esos mismos ajustes.
- En la Pantalla B, las composiciones de 4 ventanas se ven bien a 1,5–2 m; con nombres y precios los rótulos ocupan la
  mitad baja de cada ventana pequeña: el dueño puede quitarlos por ventana («Nombres y precios») para que manden las fotos.

## 5. Prueba de letra en el lugar

1. Párese en el punto **más lejano** desde donde un cliente debe leer.
2. Si cuesta leer los precios, el dueño sube **Escala de letra** en `pantallas.html` (110 %, 120 %…).
3. Si la Pantalla A queda con demasiadas páginas, el dueño elige qué **categorías** muestra esa TV. Lo demás queda en el
   menú QR.

## 6. Pruebas de aceptación (anótelas para el dueño)

| Prueba | Se acepta si |
|---|---|
| Lectura | Tres personas, una de más de 60 años o con lentes, leen 5 precios al azar desde el punto más lejano, sin error |
| Agotado | El dueño marca un producto «Agotado» en el Gestor del menú: desaparece de la Pantalla A, y de la B si tenía diapositiva, en **menos de 1 minuto** |
| Precio | El dueño cambia un precio en el Gestor del menú: el nuevo sale en las dos TV en menos de 1 minuto |
| 8 horas | La TV pasa 8 horas sin tocar el control: sin protector, sin avisos, sin apagarse |
| Corte de luz | Desenchufe la TV 1 minuto: vuelve sola a la página en menos de 3 minutos |
| Sin internet | Desconecte el router: a los 2 min la Pantalla A dice «Precios por confirmar en caja»; a los 10 min ya no muestra ningún precio; al volver internet, todo vuelve solo |

Si la prueba del **corte de luz** falla, porque la TV no vuelve a la página sola: avise al dueño. Una app de quiosco
cuesta una licencia y solo se compra si él la aprueba (su condición 6). No instale apps sin su autorización.

## 7. Si algo no se ve bien

| Lo que se ve | Qué pasa y qué hacer |
|---|---|
| «Consulte los precios en la caja» | La TV no lee el menú hace más de 10 minutos: revise el internet de la TV |
| «Precios por confirmar en caja» | Lleva más de 2 minutos sin leer el menú: revise el internet |
| Pantalla negra | Está fuera del **horario** de esa TV, o el dueño la desmarcó como **Activa** (las dos cosas en `pantallas.html`), o la TV no tiene corriente |
| Solo «Hanging Garden Café · Monteverde» en la Pantalla B | No hay diapositivas vigentes para esa TV, o no hay internet desde que encendió |
| La imagen sale de lado | Cambie **Posición** en `pantallas.html` |
| Letra pequeña o páginas de más | **Escala de letra**, **Distancia**, **Tamaño**, **Categorías**, **Densidad** o **Inglés** en `pantallas.html` |
| Una zona de la Pantalla B muestra la hoja y el nombre del café | Esa zona no tiene nada que mostrar ahora (productos agotados o sin precio) y no tiene foto de respaldo: el dueño la revisa en `pantallas.html` |
| La página de error de GitHub («404 · File not found») | La dirección está mal escrita, o las páginas no se han publicado |
| Pide OK cada vez que enciende | Es normal en el navegador de la TV; anótelo para el dueño (ver la prueba del corte de luz) |

## 8. Lo que no se debe hacer

- No use la dirección de la TV actual (`tv.html`) en las TV nuevas: es otro sistema, con otra posición y otro trabajo.
- No comparta la dirección `pantallas.html`. Es la gestión del dueño y pide su PIN.
- No instale apps ni cree cuentas en la TV sin la autorización del dueño.
