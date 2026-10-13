# Ingresos: separar los aparatos del café de su ingreso personal

**Por qué** (D-027, D-030): hoy los tres ingresos son de tipo dueño ("owner") y ninguno tiene código del teléfono.
Sin un PIN, un ingreso de tipo dueño funciona igual que uno del café (probado), pero en un aparato del café deja
abierto:
- **el código del teléfono**: quien tenga la sesión de la tableta, o la contraseña, puede activarlo y queda como dueño
  completo, sin PIN. Además, cada vez que se escribe el código de un ingreso, Supabase cierra las demás sesiones de
  ese ingreso que entraron sin código: la caja y la cocina se salen;
- **el primer dueño**: si nadie del equipo tiene el rol "dueño", un PIN de encargado puede crear uno;
- **la salida sola** a los 30 minutos sin uso (Reloj, Inicio, Menú, Ventas, Inventario).

Un ingreso del café nunca llega a dueño, ni con código. Las áreas del dueño se siguen abriendo con un PIN.

**Reglas para todos los casos**
- Nunca escriba una contraseña en el chat, en una captura ni en un grupo. Los resultados de abajo muestran correos
  enmascarados (`jo***@gmail.com`; una etiqueta como `+cafe` se ve: `jo***+cafe@gmail.com`) y la fecha de creación,
  que distingue dos ingresos que se ven iguales.
- Nunca borre un ingreso (Authentication → Users). Para quitar un acceso: `cafe-login.sql`, parte 2 (queda anotado y
  se revierte con `make_owner`).
- Hasta terminar: **nadie** toca «Cerrar sesión en todos lados» (saca la caja y la cocina), y nadie activa el código
  del teléfono. En las páginas de hoy el código se activa al tocar «Activar», sin aviso.

## Paso 1 · Saber qué ingreso usa cada aparato (solo lectura)

`supabase/tools/production-followup.sql` en el SQL Editor → pegar la celda (E-04). Muestra, por ingreso: tipo,
código del teléfono, PINs escritos en él (días) y sus sesiones abiertas por tipo de aparato (iPad, Windows, Android
teléfono o tablet, TV…), con el último uso. Si hace falta confirmarlo en el aparato: Inicio → un PIN de encargado →
la tarjeta "Ingreso del propietario" dice "Sesión iniciada como …" (luego vuelva a la Caja).

Con eso se elige el caso:
- **A**: todos los aparatos del café usan UN ingreso que usted no usa en su teléfono ni en su computadora.
- **B**: los aparatos del café usan su propio ingreso (el que usted usa también).
- **C**: los aparatos usan ingresos distintos, o alguno no se puede identificar, o algo no cuadra (un ingreso con
  código del teléfono, el ingreso que nunca entró ahora activo). En C no se cambia nada hasta aclararlo.

## Antes de cambiar nada (solo en el caso A, 2 minutos)

En su teléfono, en una ventana privada, entre con **su** ingreso personal (no el de los aparatos). Si no puede, no
siga: haga el caso B, pasos 1–3, que le da un ingreso personal nuevo. (En el caso B esta prueba no hace falta: en su
paso 3 usted ya entra con el nuevo antes de cambiar nada.)

**Nunca** use «¿Olvidó su contraseña?» ni cambie la contraseña de un ingreso que use un aparato del café: Supabase
cierra todas sus otras sesiones, y la caja y la cocina se salen en menos de una hora.

## Caso A · el ingreso es solo de los aparatos del café (10 minutos)

Ningún aparato se toca; nadie vuelve a entrar. Mejor después del cierre, aunque es seguro con el café abierto
(probado: la misma sesión sigue vendiendo y una venta guardada sin internet se sube después).

1. SQL Editor → New query → pegue **todo** `supabase/tools/cafe-login.sql` → en la línea `▶ PARTE 1` cambie
   `correo@ejemplo.com` por el correo de los aparatos y `AAAA-MM-DD` por su fecha "created" del paso 1 → Run. Debe
   decir `jo***@gmail.com (creado AAAA-MM-DD) → cafe`. Si la fecha no es la de ese correo (por ejemplo, escribió el
   otro correo que se ve igual), se niega sin cambiar nada; cualquier otro mensaje también: cópielo en el chat.
2. Vuelva a correr el paso 1: ese ingreso ahora es `cafe`; el suyo sigue `owner`.
3. Lo que cambia: corregir un turno en el Reloj pide el PIN de un encargado; la tableta ya no se sale sola; Inicio ya
   no muestra "Ingreso del propietario". Una página abierta desde antes puede salirse una última vez: se entra con el
   mismo correo.

Revertir: SQL Editor → `select public.make_owner('el correo');`. Los aparatos no se enteran.

Para el personal: «Desde hoy la caja, el iPad y la cocina usan el ingreso del café. Todo funciona igual. Para corregir
un turno en el Reloj se pide el PIN de un encargado.»

## Caso B · los aparatos usan su propio ingreso (15 minutos, recomendado)

Usted se hace un ingreso personal **nuevo** y el compartido pasa a ser el del café. No se toca ningún aparato ni se
cierra ninguna sesión de los aparatos del café, y no hace falta correo.

1. Supabase → **Authentication → Users → Add user → Create new user**: su Gmail con `+dueno` antes de la `@` (por
   ejemplo `nombre+dueno@gmail.com`), una contraseña **nueva** solo suya, **Auto confirm user** marcado → Create user.
   (Funciona con los registros públicos apagados.)
2. SQL Editor: `select public.make_owner('nombre+dueno@gmail.com');` → debe decir "Owner access is on for …" (ese
   resultado muestra el correo completo: no hace falta pegarlo en el chat).
3. En **su** teléfono: «Cerrar sesión» de arriba (nunca «Cerrar sesión en todos lados») y entre con el `+dueno`.
4. Caso A, pasos 1–3, con el correo **compartido**: los aparatos lo siguen usando, ahora como ingreso del café.
5. Desde ahora usted entra solo con el `+dueno`. Gmail entrega en su misma bandeja lo que llega a `+dueno`: antes de
   depender de eso, pruebe una vez «¿Olvidó su contraseña?» con el `+dueno` desde su teléfono, en una ventana privada
   (el enlace está en la pantalla de ingreso).

Si prefiere quedarse con su correo de siempre y darle a los aparatos uno nuevo (`+cafe`), se puede, pero hay que
cambiar cada aparato después del cierre (con internet, el aviso de arriba de la Caja en verde "en línea") y luego
cambiar su contraseña, lo que cierra sus otras sesiones en menos de una hora. Pídalo y se lo guío paso a paso.

## Caso C · aparatos con ingresos distintos o sin identificar

1. Identifique cada aparato (paso 1 y la tarjeta de Inicio). Anote aparato → correo (sin contraseñas).
2. Si uno de esos ingresos es solo de aparatos: caso A con ese, y los demás aparatos se pasan a él después del cierre
   (se guía uno por uno).
3. Si todos son ingresos personales: caso B con el que usa la caja.

## Después

- **Código del teléfono** (E-06): solo en su ingreso personal, desde su teléfono, cuando ningún aparato del café use
  ese ingreso. Nunca en el del café. Si un día todos los aparatos piden la contraseña a la vez, avise: puede ser un
  código activado en el ingreso del café (se quita en Users → el ingreso → Remove MFA factors).
- **El ingreso que nunca entró** (creado el 2026-09-16): si no es su correo, `cafe-login.sql` parte 2 le quita el
  acceso de dueño (anotado; reversible). Si en el caso B queda otro ingreso suyo de tipo dueño que ya no usa (no el de
  los aparatos), se le quita igual, siempre después del paso 4.
- **La contraseña del ingreso del café**: déjela por escrito en el café para los encargados (nunca por chat ni por
  grupo). Cambiarla saca a todos los aparatos del café: solo después del cierre. En el caso B es la que usted usaba:
  si la usa también en otro lado, cámbiela (después del cierre; los aparatos vuelven a entrar con la nueva).
- **Nunca** entre con su ingreso personal en un aparato del café: allí use su PIN.
- Si el paso 1 no muestra a nadie del equipo con el rol "dueño", créelo desde su ingreso personal (Reloj → Equipo).
