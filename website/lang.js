/* The Hanging Garden Café · English / Español switch
   One small script shared by every page. It adds a visible EN | ES control,
   remembers the choice, and swaps the words on the page from the dictionary
   below without touching how any page works. Text the dictionary does not
   know (names, numbers, menu items typed later) stays exactly as it is. */
(function () {
  'use strict';
  var KEY = 'hg_lang';

  /* ---------- dictionary: English → Spanish ---------- */
  var D = {
    /* shared */
    'Email': 'Correo electrónico', 'Password': 'Contraseña', 'Sign in': 'Ingresar', 'Sign out': 'Cerrar sesión',
    'Cancel': 'Cancelar', 'Save': 'Guardar', 'Delete': 'Eliminar', 'Close': 'Cerrar', 'Confirm': 'Confirmar',
    'Home': 'Inicio', 'Menu': 'Menú', 'POS': 'Caja', 'Sales': 'Ventas', 'Time clock': 'Reloj de marcas',
    'TV board': 'Pantalla TV', 'Menu Manager': 'Gestor del menú', 'Kitchen screen': 'Pantalla de cocina',
    'Kitchen': 'Cocina', 'Website': 'Sitio web', 'Loading…': 'Cargando…', 'Signing in…': 'Ingresando…',
    'Manager': 'Encargado', 'PIN': 'PIN', 'Manager PIN': 'PIN del encargado', 'Approved by': 'Aprobado por',
    'Reason': 'Motivo', 'Name': 'Nombre', 'Role': 'Puesto', 'Team': 'Equipo', 'Hours': 'Horas',
    'Today': 'Hoy', 'This week': 'Esta semana', 'Last week': 'Semana pasada', 'This month': 'Este mes',
    'Last 7 days': 'Últimos 7 días', 'Last 30 days': 'Últimos 30 días', 'Download CSV': 'Descargar CSV',
    'That login did not work.': 'Ese ingreso no funcionó.',
    'That login did not work. Check the email and password.': 'Ese ingreso no funcionó. Revise el correo y la contraseña.',
    'Could not save. Try again.': 'No se pudo guardar. Intente de nuevo.',
    'Could not save. Check the connection.': 'No se pudo guardar. Revise la conexión.',
    'Could not save. Check the connection and try again.': 'No se pudo guardar. Revise la conexión e intente de nuevo.',
    'Could not save:': 'No se pudo guardar:',
    'That PIN is not right.': 'Ese PIN no es correcto.',
    'Too many wrong PINs. Wait 10 minutes and try again.': 'Demasiados PIN incorrectos. Espere 10 minutos e intente de nuevo.',
    'That person is not a manager.': 'Esa persona no es encargada.',
    'That person is not active on the team.': 'Esa persona no está activa en el equipo.',
    'This login is not connected to the café yet.': 'Este ingreso todavía no está conectado al café.',
    'This login is not connected to the café yet. From the owner login, run the accounts script in Supabase (see the setup notes), then sign in again.':
      'Este ingreso todavía no está conectado al café. Desde el ingreso del propietario, ejecute el script de cuentas en Supabase (vea las notas de instalación) y vuelva a ingresar.',
    'This is the café login. It opens the POS, the time clock and the kitchen screen. This page needs the owner login.':
      'Este es el ingreso del café. Abre la caja, el reloj de marcas y la pantalla de cocina. Esta página necesita el ingreso del propietario.',
    'Open the POS': 'Abrir la caja', 'Code from your phone app': 'Código de la app de su teléfono', '6-digit code': 'Código de 6 dígitos',
    'That code did not work. Codes change every 30 seconds, try the newest one.': 'Ese código no funcionó. Los códigos cambian cada 30 segundos; pruebe el más reciente.',
    'Nothing to print yet.': 'Todavía no hay nada que imprimir.',

    /* website: nav + hero */
    'Skip to content': 'Ir al contenido', 'Story': 'Historia', 'Gallery': 'Galería', 'Ask us': 'Pregúntenos',
    'Plan your visit': 'Planee su visita', 'Café · Monteverde': 'Café · Monteverde',
    'Follow the quetzal.': 'Siga al quetzal.', 'Through the coffee harvest.': 'Por la cosecha de café.',
    'Home to the garden.': 'De vuelta al jardín.',
    'Coffee, garden, and cloud. Monteverde, Costa Rica.': 'Café, jardín y nubes. Monteverde, Costa Rica.',
    'The Hanging Garden Café · Monteverde, Costa Rica': 'The Hanging Garden Café · Monteverde, Costa Rica',

    /* website: story */
    'The story': 'La historia', 'A green mountain, a cup of peace': 'Una montaña verde, una taza de paz',
    'Monteverde was not built for hurry. Every cup we pour carries a century of this mountain: farmers, pacifists, scientists, and a forest that drinks from the clouds.':
      'Monteverde no se hizo para las prisas. Cada taza que servimos lleva un siglo de esta montaña: campesinos, pacifistas, científicos y un bosque que bebe de las nubes.',
    'The first farms': 'Las primeras fincas',
    'Costa Rican families settle the green mountain, planting coffee and raising dairy on slopes that touch the clouds.':
      'Familias costarricenses se asientan en la montaña verde, sembrando café y criando ganado lechero en laderas que tocan las nubes.',
    'A nation chooses peace': 'Un país elige la paz',
    'Costa Rica abolishes its army. The country puts down its weapons for good.': 'Costa Rica abole su ejército. El país deja las armas para siempre.',
    'The Quakers arrive': 'Llegan los cuáqueros',
    'Forty four Quakers leave Alabama, choosing Costa Rica because it has no army. They buy land in the cloud forest and name it Monteverde, the green mountain.':
      'Cuarenta y cuatro cuáqueros dejan Alabama y eligen Costa Rica porque no tiene ejército. Compran tierra en el bosque nuboso y la llaman Monteverde, la montaña verde.',
    'The forest protected': 'El bosque protegido',
    'The Monteverde Cloud Forest Reserve is founded. The community protects the watershed instead of clearing it, and the world comes to walk under its canopy.':
      'Se funda la Reserva Biológica Bosque Nuboso Monteverde. La comunidad protege la cuenca en vez de talarla, y el mundo viene a caminar bajo su dosel.',
    'Your cup': 'Su taza',
    'The Hanging Garden continues the story: slow coffee, hanging plants, and a table waiting for you between the clouds.':
      'The Hanging Garden continúa la historia: café sin prisa, plantas colgantes y una mesa que lo espera entre las nubes.',
    'Peace. Simplicity. Stewardship. Community.': 'Paz. Sencillez. Cuidado. Comunidad.',
    'The jewel of the cloud forest, and our neighbor.': 'La joya del bosque nuboso, y nuestro vecino.',
    'from Monteverde, for the adventure ahead': 'desde Monteverde, para la aventura que viene',
    'Grown in the clouds': 'Cultivado entre las nubes',
    '100% Costa Rican coffee, locally sourced. Thank you for supporting our community and our forest.':
      'Café 100% costarricense, de productores locales. Gracias por apoyar a nuestra comunidad y a nuestro bosque.',

    /* website: menu */
    'Specialty coffee · Fresh food': 'Café de especialidad · Comida fresca', 'The menu': 'El menú',
    'made for the cloud forest': 'hecho para el bosque nuboso',
    'Proudly serving locally grown coffee from El Trapiche Monteverde. Prices in colones; we also take dollars at the counter.':
      'Servimos con orgullo café de El Trapiche Monteverde. Precios en colones; también recibimos dólares en el mostrador.',
    'Coffee': 'Café', 'Espresso': 'Espresso', 'Americano': 'Americano', 'Macchiato': 'Macchiato', 'Cappuccino': 'Capuchino',
    'Latte': 'Latte', 'Flat White': 'Flat White', 'Mocha': 'Moca', 'Costa Rican chocolate': 'Chocolate costarricense',
    'Café con Leche': 'Café con leche', 'Traditional chorreado coffee + warm milk': 'Café chorreado tradicional + leche caliente',
    'Cloud Forest Latte': 'Latte del Bosque Nuboso',
    'El Trapiche espresso · milk · Costa Rican honey · cinnamon · hot or iced': 'Espresso de El Trapiche · leche · miel costarricense · canela · caliente o frío',
    'Iced Americano': 'Americano frío', 'Iced Latte': 'Latte frío', 'Iced Mocha': 'Moca frío',
    'Other Drinks': 'Otras bebidas', 'Costa Rican Hot Chocolate': 'Chocolate caliente costarricense', 'Tea': 'Té',
    'Sweet Cane Drink': 'Agua dulce', 'Sandwiches': 'Sándwiches', 'Ham & Cheese': 'Jamón y queso',
    'Quality ham · local cheese · house sauce': 'Jamón de calidad · queso local · salsa de la casa',
    'Mano de Piedra': 'Mano de Piedra',
    'Traditional Costa Rican beef · frijoles molidos · local cheese · tomato · house sauce': 'Carne tradicional costarricense · frijoles molidos · queso local · tomate · salsa de la casa',
    'Chicken Pesto': 'Pollo al pesto', 'Chicken breast · pesto · local cheese · tomato': 'Pechuga de pollo · pesto · queso local · tomate',
    'Frijoles molidos · local cheese · tomato · house sauce · vegetarian, add ham +₡500': 'Frijoles molidos · queso local · tomate · salsa de la casa · vegetariano, con jamón +₡500',
    'Savory': 'Salado', 'Chicken Empanada': 'Empanada de pollo', 'Beef Empanada': 'Empanada de carne',
    'Ham & Cheese Croissant': 'Croissant de jamón y queso', 'Warm it up? Absolutely.': '¿Calentito? Por supuesto.',
    'Pastries & Cake': 'Repostería y queques', 'Butter Croissant': 'Croissant de mantequilla', 'Chocolate Croissant': 'Croissant de chocolate',
    'Banana Bread': 'Pan de banano', 'Carrot Cake': 'Queque de zanahoria', 'Costa Rican Favorites': 'Favoritos costarricenses',
    'Tres Leches': 'Tres leches', 'Classic three-milk cake': 'El clásico queque de tres leches', 'Tamal Asado': 'Tamal asado',
    'Traditional Costa Rican baked corn cake': 'Tradicional queque de maíz horneado', 'Smoothies': 'Batidos',
    'Mango · pineapple · passion fruit (₡3 500 in milk)': 'Mango · piña · maracuyá (₡3 500 en leche)',
    'Strawberry · blackberry · ice cream (only in milk)': 'Fresa · mora · helado (solo en leche)',
    'Pineapple · coconut cream · ice cream (only in milk)': 'Piña · crema de coco · helado (solo en leche)',
    'Watermelon · pineapple · orange juice (only in water)': 'Sandía · piña · jugo de naranja (solo en agua)',
    'Pineapple · lemon · spearmint (only in water)': 'Piña · limón · hierbabuena (solo en agua)',
    'Strawberry · watermelon · orange juice (only in water)': 'Fresa · sandía · jugo de naranja (solo en agua)',
    'Strawberry · mango (₡2 800 in milk)': 'Fresa · mango (₡2 800 en leche)',
    'Kiwi · strawberry (₡3 100 in milk)': 'Kiwi · fresa (₡3 100 en leche)',
    'Strawberry · lemon (only in water)': 'Fresa · limón (solo en agua)',
    'Melon · watermelon (₡2 500 in milk)': 'Melón · sandía (₡2 500 en leche)',
    'Papaya · mango (₡2 800 in milk)': 'Papaya · mango (₡2 800 en leche)',
    'House signature': 'Sello de la casa',
    'El Trapiche espresso, milk, Costa Rican honey, and cinnamon. Hot or iced.': 'Espresso de El Trapiche, leche, miel costarricense y canela. Caliente o frío.',
    'For the trail': 'Para el sendero', 'Adventure Box': 'Adventure Box',
    'Your sandwich + fresh fruit + a sweet treat + bottled water + napkin. Order by 8 pm tonight, pick it up from 6:30 am.':
      'Su sándwich + fruta fresca + algo dulce + agua embotellada + servilleta. Pídala antes de las 8 pm y recójala desde las 6:30 am.',
    'Ham & Cheese or Monteverde ₡6 500 · Mano de Piedra or Chicken Pesto ₡7 000': 'Jamón y queso o Monteverde ₡6 500 · Mano de Piedra o Pollo al pesto ₡7 000',
    'Make it a combo': 'Hágalo combo', 'Coffee + pastry ·': 'Café + repostería ·', 'save ₡500': 'ahorre ₡500',
    'Sandwich + coffee ·': 'Sándwich + café ·', 'Extras & Combos': 'Extras y combos',
    "Today's Garden Special": 'Especial del jardín de hoy', "Ask what's blooming today.": 'Pregunte qué está floreciendo hoy.',
    'Sweet Favorites': 'Favoritos dulces', 'From the pastry case': 'De la vitrina de repostería',
    'coffee + pastry save ₡500 · sandwich + coffee save ₡500': 'café + repostería ahorre ₡500 · sándwich + café ahorre ₡500',

    /* website: brew, gallery, visit, chat, footer */
    'Try it yourself': 'Pruébelo usted', 'Hold to brew': 'Mantenga presionado para preparar',
    'Press and hold the cup. Good coffee cannot be rushed.': 'Mantenga presionada la taza. El buen café no se apura.',
    'Press and hold to fill the cup': 'Mantenga presionado para llenar la taza',
    'Brewed. That patience is the whole secret.': 'Listo. Esa paciencia es todo el secreto.',
    'A table between the clouds': 'Una mesa entre las nubes', 'Morning chorreado': 'Chorreado de la mañana',
    'Baked this morning': 'Horneado esta mañana', 'Poured slow': 'Servido sin prisa', 'The hanging garden': 'El jardín colgante',
    'These images are AI generated placeholders. Photos of the real garden are coming soon.': 'Estas imágenes son provisionales, generadas con IA. Pronto habrá fotos del jardín real.',
    'Visit us': 'Visítenos',
    'Find us in Monteverde, on the road through Santa Elena, Puntarenas, Costa Rica. Come before the forest walk or after the hanging bridges. The coffee waits either way.':
      'Estamos en Monteverde, sobre el camino de Santa Elena, Puntarenas, Costa Rica. Venga antes de la caminata por el bosque o después de los puentes colgantes. El café espera igual.',
    'Every day': 'Todos los días', 'Get directions': 'Cómo llegar', 'Message us on WhatsApp': 'Escríbanos por WhatsApp',
    'Questions?': '¿Preguntas?', 'Ask the Garden Guide': 'Pregunte a la Guía del Jardín',
    'Hours, prices, what to wear in the cloud forest, where the quetzals are: our little guide answers right here on the page, in English y en español.':
      'Horario, precios, qué ponerse en el bosque nuboso, dónde están los quetzales: nuestra guía responde aquí mismo, en español y en inglés.',
    'Ask a question': 'Hacer una pregunta', 'Garden Guide': 'Guía del Jardín', 'The Hanging Garden · English y español': 'The Hanging Garden · español e inglés',
    'Ask the Garden Guide a question': 'Hacer una pregunta a la Guía del Jardín', 'Garden Guide chat': 'Chat de la Guía del Jardín',
    'Close chat': 'Cerrar el chat', 'Your question': 'Su pregunta', 'Send': 'Enviar',
    'What are your hours?': '¿Cuál es el horario?', 'How to find us': 'Cómo llegar', 'How do I get there?': '¿Cómo llego?',
    'How can I contact you?': '¿Cómo los contacto?', 'What is the Adventure Box?': '¿Qué es la Adventure Box?',
    'Weather': 'Clima', 'What is the weather like?': '¿Cómo está el clima?', 'Quetzals': 'Quetzales', 'Where can I see a quetzal?': '¿Dónde puedo ver un quetzal?',
    '· Monteverde, Costa Rica': '· Monteverde, Costa Rica',
    '100% Costa Rican coffee · Locally sourced · Proudly serving coffee from El Trapiche Monteverde': 'Café 100% costarricense · De productores locales · Servimos con orgullo café de El Trapiche Monteverde',
    'Thank you for supporting our community and our forest. Pura vida.': 'Gracias por apoyar a nuestra comunidad y a nuestro bosque. Pura vida.',
    'Gallery imagery is AI generated for now and will be replaced with photos of the real café. Website by The Hanging Garden.':
      'Las imágenes de la galería son generadas con IA por ahora y se cambiarán por fotos del café real. Sitio web de The Hanging Garden.',
    'A resplendent quetzal perched on a mossy branch in the Monteverde cloud forest': 'Un quetzal posado en una rama con musgo en el bosque nuboso de Monteverde',
    'The Monteverde cloud forest': 'El bosque nuboso de Monteverde', 'Coffee served at the garden': 'Café servido en el jardín',
    'Fresh pastries': 'Repostería fresca', 'Coffee pouring': 'Café sirviéndose', 'Garden seating among hanging plants': 'Mesas del jardín entre plantas colgantes',
    'Map of The Hanging Garden Café, Monteverde': 'Mapa de The Hanging Garden Café, Monteverde',

    /* owner home */
    'Owner dashboard · Monteverde, Costa Rica': 'Panel del propietario · Monteverde, Costa Rica', 'Owner dashboard · Monteverde': 'Panel del propietario · Monteverde',
    'Home · The Hanging Garden': 'Inicio · The Hanging Garden', 'Revenue today': 'Ingresos de hoy', 'Orders today': 'Pedidos de hoy',
    'On the clock': 'En turno', 'Sold out': 'Agotados', 'Nobody in': 'Nadie en turno',
    'Ring up sales at the counter — cash, card or SINPE, recorded instantly.': 'Cobre en el mostrador: efectivo, tarjeta o SINPE, registrado al instante.',
    'What you sold today, this week, this month — best sellers and CSV for the accountant.': 'Lo vendido hoy, esta semana y este mes: los más vendidos y CSV para el contador.',
    'Change prices, photos and items — updates the website and TV board in a minute.': 'Cambie precios, fotos y productos; el sitio web y la pantalla TV se actualizan en un minuto.',
    "The team clocks in and out with a PIN; you see everyone's hours.": 'El equipo marca entrada y salida con un PIN; usted ve las horas de todos.',
    'The live menu screen — open this on the TV in the café.': 'La pantalla del menú en vivo: ábrala en el televisor del café.',
    'Tickets for the back — open this on the tablet or screen in the kitchen.': 'Las comandas para atrás: ábrala en la tableta o pantalla de la cocina.',
    'What your guests see — the cinematic Monteverde story with the live menu.': 'Lo que ven sus clientes: la historia cinematográfica de Monteverde con el menú en vivo.',
    'Owner login': 'Ingreso del propietario', 'Signed in as': 'Sesión iniciada como', 'Sign out everywhere': 'Cerrar sesión en todos lados',
    'Phone code (2FA):': 'Código del teléfono (2FA):', 'Turn on': 'Activar', 'Turn off': 'Desactivar', 'Owner phone': 'Teléfono del propietario',
    'Scan this with Google Authenticator, Microsoft Authenticator or 1Password on your phone, then type the 6-digit code it shows.':
      'Escanee esto con Google Authenticator, Microsoft Authenticator o 1Password en su teléfono y escriba el código de 6 dígitos que muestra.',
    'Or type this key by hand:': 'O escriba esta clave a mano:', 'QR code for the authenticator app': 'Código QR para la app de autenticación',
    'Every sign-in with the owner login asks for the code from your phone. Without it, the session only gets café-level access.':
      'Cada ingreso del propietario pide el código de su teléfono. Sin él, la sesión solo tiene acceso de nivel café.',
    'Recommended: with a phone code, your password alone is not enough to reach sales, menu and team settings.':
      'Recomendado: con un código del teléfono, la contraseña sola no basta para llegar a ventas, menú y equipo.',
    'Turn the phone code off? Your password alone will open the owner login again.': '¿Desactivar el código del teléfono? La contraseña sola volverá a abrir el ingreso del propietario.',
    'Could not turn it off. Sign out, sign in again with the code, then try once more.': 'No se pudo desactivar. Cierre sesión, vuelva a ingresar con el código e intente otra vez.',
    'Could not start the phone code. In Supabase, check that Authentication > Multi-Factor > TOTP is switched on.': 'No se pudo iniciar el código del teléfono. En Supabase, revise que Authentication > Multi-Factor > TOTP esté activado.',
    'That code did not match. Wait for the next code and try again.': 'Ese código no coincidió. Espere el siguiente e intente de nuevo.',
    'Sign the owner login out on every device, including this one?': '¿Cerrar la sesión del propietario en todos los dispositivos, incluido este?',
    'Run supabase/accounts.sql once to switch on the owner and café logins.': 'Ejecute supabase/accounts.sql una vez para activar los ingresos de propietario y café.',

    /* menu manager */
    'Menu Manager · The Hanging Garden': 'Gestor del menú · The Hanging Garden',
    "Changes save instantly and show on the website and the TV board within a minute. Tap a photo square to change an item's picture. Star an item to feature it in the TV slideshow, or combine several items into one slide below.":
      'Los cambios se guardan al instante y aparecen en el sitio web y la pantalla TV en un minuto. Toque el cuadro de foto para cambiar la imagen de un producto. Marque con estrella un producto para destacarlo en la presentación del TV, o combine varios en una sola diapositiva abajo.',
    'Run the TV board SQL once in Supabase and these controls switch on.': 'Ejecute el SQL de la pantalla TV una vez en Supabase y estos controles se activan.',
    'What the TV shows': 'Qué muestra el TV', 'Menu + product slideshow (recommended)': 'Menú + presentación de productos (recomendado)',
    'Menu only': 'Solo el menú', 'Product slideshow only': 'Solo la presentación de productos', 'Screen direction': 'Orientación de la pantalla',
    'Automatic (follows the screen)': 'Automática (según la pantalla)', 'Always horizontal': 'Siempre horizontal',
    'Vertical · TV turned to the left': 'Vertical · TV girado a la izquierda', 'Vertical · TV turned to the right': 'Vertical · TV girado a la derecha',
    'Menu stays for (seconds)': 'El menú se queda (segundos)', 'Each slide stays for (seconds)': 'Cada diapositiva se queda (segundos)',
    'Message at the bottom of the menu': 'Mensaje al pie del menú', 'Save TV board settings': 'Guardar ajustes de la pantalla TV',
    'Combined slides': 'Diapositivas combinadas',
    'Pick 2 to 8 items and the TV shows them together in one picture, built from their photos. Nothing to upload.': 'Elija de 2 a 8 productos y el TV los muestra juntos en una sola imagen, armada con sus fotos. No hay que subir nada.',
    'Run the combined slides SQL once in Supabase and this section switches on.': 'Ejecute el SQL de diapositivas combinadas una vez en Supabase y esta sección se activa.',
    '+ New combined slide': '+ Nueva diapositiva combinada', 'Slide title': 'Título de la diapositiva',
    'Small line above the title (optional)': 'Línea pequeña sobre el título (opcional)', 'Pick 2 to 8 items': 'Elija de 2 a 8 productos',
    'Save slide': 'Guardar diapositiva', 'Kitchen, pickup numbers and rooms': 'Cocina, números de entrega y habitaciones',
    'Run the kitchen and rooms SQL once in Supabase and this section switches on.': 'Ejecute el SQL de cocina y habitaciones una vez en Supabase y esta sección se activa.',
    'Each category below has a "prepared in the kitchen" switch. Orders with kitchen items show on the Kitchen screen.': 'Cada categoría de abajo tiene un interruptor "se prepara en cocina". Los pedidos con productos de cocina aparecen en la pantalla de cocina.',
    'Number stands you own (1 to…)': 'Números de mesa que tiene (del 1 al…)', 'Out of service (e.g. 4, 9)': 'Fuera de servicio (ej. 4, 9)',
    'Guests can order from their rooms': 'Los huéspedes pueden pedir desde su habitación', 'Room ordering opens': 'Pedidos desde habitación abren',
    'Save settings': 'Guardar ajustes', 'Room cards': 'Tarjetas de habitación',
    'Each room has a private code inside its QR. If a card gets photographed or lost, tap New code and reprint that one card.': 'Cada habitación tiene un código privado dentro de su QR. Si una tarjeta se fotografía o se pierde, toque Nuevo código y reimprima solo esa tarjeta.',
    'Print all room cards': 'Imprimir todas las tarjetas', 'New code': 'Nuevo código', 'No rooms yet.': 'Todavía no hay habitaciones.',
    'Could not load the menu. Check your connection.': 'No se pudo cargar el menú. Revise su conexión.',
    'Could not save the settings. Try again.': 'No se pudieron guardar los ajustes. Intente de nuevo.',
    'Settings saved. The POS and room pages follow within a minute.': 'Ajustes guardados. La caja y las páginas de habitación se actualizan en un minuto.',
    'Give room {n} a new code? The card in that room stops working until you reprint it.': '¿Dar un nuevo código a la habitación {n}? La tarjeta de esa habitación deja de funcionar hasta que la reimprima.',
    'Could not change the code. Try again.': 'No se pudo cambiar el código. Intente de nuevo.',
    'Room {n} has a new code. Reprint its card.': 'La habitación {n} tiene un nuevo código. Reimprima su tarjeta.',
    'QR code for room {n}': 'Código QR de la habitación {n}', 'Room {n}': 'Habitación {n}',
    'Scan to see the menu and order from your room.': 'Escanee para ver el menú y pedir desde su habitación.',
    'Pay at the window when you pick up.': 'Pague en la ventanilla al recoger.',
    'No combined slides yet.': 'Todavía no hay diapositivas combinadas.',
    'Add a photo to a few items first, then they show up here.': 'Primero agregue foto a algunos productos y aparecerán aquí.',
    'A combined slide holds up to 8 items.': 'Una diapositiva combinada admite hasta 8 productos.',
    '{n} item picked · pick at least 2': '{n} producto elegido · elija al menos 2', '{n} items picked · pick at least 2': '{n} productos elegidos · elija al menos 2',
    '{n} items picked': '{n} productos elegidos', '{n} item picked': '{n} producto elegido',
    'Delete this combined slide?': '¿Eliminar esta diapositiva combinada?', 'Could not delete that slide. Try again.': 'No se pudo eliminar esa diapositiva. Intente de nuevo.',
    'Combined slide deleted.': 'Diapositiva combinada eliminada.', 'Give the slide a title.': 'Póngale un título a la diapositiva.',
    'Pick at least 2 items.': 'Elija al menos 2 productos.', 'Could not save that slide. Try again.': 'No se pudo guardar esa diapositiva. Intente de nuevo.',
    'Combined slide saved. The TV follows within a minute.': 'Diapositiva combinada guardada. El TV se actualiza en un minuto.',
    'Could not save the TV settings. Try again.': 'No se pudieron guardar los ajustes del TV. Intente de nuevo.',
    'TV board updated. The screen follows within a minute.': 'Pantalla TV actualizada. La pantalla se actualiza en un minuto.',
    'Prepared in the kitchen (shows on the Kitchen screen)': 'Se prepara en cocina (aparece en la pantalla de cocina)',
    'Could not save the color. Try again.': 'No se pudo guardar el color. Intente de nuevo.',
    '{cat} color saved. The POS follows on its next refresh.': 'Color de {cat} guardado. La caja lo toma al actualizarse.',
    'Category color on the POS (tab and button tint)': 'Color de la categoría en la caja (pestaña y botones)',
    '+ Add item to {cat}': '+ Agregar producto a {cat}', 'Change photo': 'Cambiar foto', 'Change photo for {item}': 'Cambiar la foto de {item}',
    '★ On TV': '★ En TV', '☆ TV': '☆ TV', 'Feature this item in the TV slideshow': 'Destacar este producto en la presentación del TV',
    '{item} removed from the TV slideshow': '{item} quitado de la presentación del TV', '{item} will star in the TV slideshow': '{item} saldrá en la presentación del TV',
    'Price in colones (numbers only)': 'Precio en colones (solo números)', 'Price in colones (numbers only):': 'Precio en colones (solo números):',
    'Description (optional)': 'Descripción (opcional)', 'Side color on the POS': 'Color lateral en la caja', 'Quick tab': 'Pestaña rápida',
    'Automatic (top sellers)': 'Automática (los más vendidos)', 'Always show': 'Mostrar siempre', 'Never show': 'Nunca mostrar',
    'Delete item': 'Eliminar producto', 'Delete "{item}" from the menu? This cannot be undone.': '¿Eliminar "{item}" del menú? Esto no se puede deshacer.',
    'Could not delete. Try again.': 'No se pudo eliminar. Intente de nuevo.', 'Name of the new item in {cat}': 'Nombre del nuevo producto en {cat}',
    'That price did not look like a number.': 'Ese precio no parece un número.', 'Could not add it. Try again.': 'No se pudo agregar. Intente de nuevo.',
    'That photo is too big. Pick one under 8 MB.': 'Esa foto es muy grande. Elija una de menos de 8 MB.', 'Uploading photo…': 'Subiendo la foto…',
    'Photo upload failed. Try again.': 'No se pudo subir la foto. Intente de nuevo.',
    'Photo saved but the menu did not update. Try again.': 'La foto se guardó pero el menú no se actualizó. Intente de nuevo.',
    'Photo updated': 'Foto actualizada',

    /* POS */
    'The Hanging Garden POS': 'Caja The Hanging Garden', 'POS · The Hanging Garden': 'Caja · The Hanging Garden',
    'Time': 'Reloj', 'Orders': 'Pedidos', 'Loading the menu…': 'Cargando el menú…', 'Order': 'Pedido', 'Tap items to add them.': 'Toque los productos para agregarlos.',
    'Includes IVA 13%': 'Incluye IVA 13%', 'Total': 'Total', 'Cash ₡': 'Efectivo ₡', 'Cash $': 'Efectivo $', 'Card': 'Tarjeta', 'SINPE': 'SINPE', 'Other': 'Otro',
    'Clear order': 'Vaciar pedido', 'Print receipt': 'Imprimir recibo', 'Today at the counter': 'Hoy en el mostrador', 'Cash counted:': 'Efectivo contado:',
    "Today's orders": 'Pedidos de hoy',
    "Voiding an order needs a manager's PIN and a reason. The order stays on record, marked as voided, and the approval is logged.": 'Anular un pedido necesita el PIN de un encargado y un motivo. El pedido queda registrado como anulado y la aprobación se guarda en la bitácora.',
    'Void this order': 'Anular este pedido', 'Which number stand?': '¿Qué número de mesa?',
    'Tap the number you are handing to the customer. Greyed numbers are in use.': 'Toque el número que le entrega al cliente. Los números en gris están en uso.',
    'No number': 'Sin número', 'Paid and picked up': 'Pagado y entregado', 'Paid & picked up': 'Pagado y entregado', 'Picked up': 'Entregado',
    'e.g. rang up twice': 'ej. se cobró dos veces',
    'No connection and no saved menu yet. Connect once and it will work offline after that.': 'Sin conexión y sin menú guardado todavía. Conéctese una vez y después funcionará sin conexión.',
    'your best sellers, updated from Sales · set Always or Never per item in the Menu Manager': 'sus productos más vendidos, según Ventas · marque Siempre o Nunca por producto en el Gestor del menú',
    'One less': 'Uno menos', 'One more': 'Uno más', '{n} item ·': '{n} producto ·', '{n} items ·': '{n} productos ·',
    'The order is empty.': 'El pedido está vacío.', '· number {n}': '· número {n}', 'Paid by {x}': 'Pagado con {x}', 'offline · {x}': 'sin conexión · {x}',
    'Adding it up…': 'Sumando…', 'Could not load today. Check the connection.': 'No se pudo cargar el día. Revise la conexión.',
    'Voided (not counted)': 'Anulados (no cuentan)',
    'Compare the card total with the BAC terminal batch. Count the drawer and type it below.': 'Compare el total de tarjeta con el cierre del datáfono BAC. Cuente la caja y escríbalo abajo.',
    'Pick the manager who is approving this.': 'Elija al encargado que aprueba esto.', 'Write the reason for the void.': 'Escriba el motivo de la anulación.',
    'That order no longer exists.': 'Ese pedido ya no existe.', 'That order was already voided.': 'Ese pedido ya estaba anulado.',
    'No manager set up yet': 'Todavía no hay encargado', 'Could not load the orders. Check the connection.': 'No se pudieron cargar los pedidos. Revise la conexión.',
    'Voiding switches on once the manager approval setup is run in Supabase.': 'Las anulaciones se activan cuando se ejecute la configuración de aprobaciones en Supabase.',
    '{n} still saving from offline. They show here once synced.': '{n} todavía guardándose desde sin conexión. Aparecen aquí al sincronizar.',
    'No orders yet today.': 'Todavía no hay pedidos hoy.', 'Voided · {x}': 'Anulado · {x}',
    'Could not void. Check the connection and try again.': 'No se pudo anular. Revise la conexión e intente de nuevo.', 'Could not void. Try again.': 'No se pudo anular. Intente de nuevo.',
    'Order voided · {x}': 'Pedido anulado · {x}', 'No show': 'No llegó', 'Cancel this room order? (guest never came)': '¿Cancelar este pedido de habitación? (el huésped nunca llegó)',
    'In kitchen · Ready': 'En cocina · Listo', 'Could not cancel. Try again.': 'No se pudo cancelar. Intente de nuevo.', 'Room order cancelled': 'Pedido de habitación cancelado',
    'Could not record the payment. Try again.': 'No se pudo registrar el pago. Intente de nuevo.',
    'Ready': 'Listo', 'Room': 'Habitación', 'Cash': 'Efectivo',

    /* sales */
    'Sales · The Hanging Garden': 'Ventas · The Hanging Garden', 'Lock now': 'Bloquear ahora', 'Sales are locked': 'Las ventas están bloqueadas',
    'Type a manager PIN to open the reports for 15 minutes. Every opening is written to the approvals log.': 'Escriba un PIN de encargado para abrir los reportes por 15 minutos. Cada apertura se anota en la bitácora de aprobaciones.',
    'Open the sales reports': 'Abrir los reportes de ventas', 'Revenue': 'Ingresos', 'Average order': 'Pedido promedio', 'Revenue by day': 'Ingresos por día',
    'How people paid': 'Cómo pagaron', 'Best sellers': 'Más vendidos', 'Transactions': 'Transacciones', 'When': 'Cuándo', 'Items': 'Productos',
    'Revenue by day bar chart': 'Gráfico de barras de ingresos por día', 'Pick the manager.': 'Elija al encargado.',
    'This manager may not open the sales reports. The owner can allow it in the Time clock, Team section.': 'Este encargado no puede abrir los reportes de ventas. El propietario puede permitirlo en el Reloj de marcas, sección Equipo.',
    'Could not check the PIN. Check the connection.': 'No se pudo verificar el PIN. Revise la conexión.', 'Could not open the reports.': 'No se pudieron abrir los reportes.',
    'Nothing in this period yet.': 'Todavía no hay nada en este periodo.', '{n} sold ·': '{n} vendidos ·',
    'No sales in this period yet. Ring one up on the POS and refresh.': 'Todavía no hay ventas en este periodo. Cobre una en la caja y actualice.',

    /* time clock */
    'Time clock · The Hanging Garden': 'Reloj de marcas · The Hanging Garden', 'One-time setup needed': 'Falta una configuración inicial',
    'The time clock needs its tables and the manager-approval functions in Supabase. It takes about a minute:': 'El reloj de marcas necesita sus tablas y las funciones de aprobación en Supabase. Toma como un minuto:',
    'Open your Supabase project →': 'Abra su proyecto de Supabase →', 'SQL Editor': 'SQL Editor', 'New query': 'New query', 'Paste and run': 'Pegue y ejecute',
    ', then paste and run': ', luego pegue y ejecute', 'Come back here, reload, and make yourself the first manager under': 'Vuelva aquí, recargue y hágase el primer encargado en',
    'Hours & team': 'Horas y equipo', 'Clock in · out': 'Entrada · salida',
    "Tap your name, type your PIN. Green means you're on the clock.": 'Toque su nombre y escriba su PIN. Verde significa que está en turno.',
    "Shifts count on the day they start. Weeks run Monday to Sunday. Any change to a shift needs a manager's PIN and is written to the approvals log.": 'Los turnos cuentan el día en que empiezan. Las semanas van de lunes a domingo. Cualquier cambio a un turno necesita el PIN de un encargado y se anota en la bitácora.',
    'No manager yet. The first person you save becomes the manager (no approval needed this one time). Do this now.': 'Todavía no hay encargado. La primera persona que guarde será el encargado (sin aprobación esta única vez). Hágalo ahora.',
    '+ Add person': '+ Agregar persona', 'Approvals log': 'Bitácora de aprobaciones',
    'Every shift change, team change and voided order, with who approved it and why.': 'Cada cambio de turno, cambio de equipo y pedido anulado, con quién lo aprobó y por qué.',
    'Edit shift': 'Editar turno', 'Clock in': 'Entrada', 'Clock out (leave empty if still working)': 'Salida (déjelo vacío si sigue trabajando)',
    'Reason for the change': 'Motivo del cambio', 'Manager approval': 'Aprobación del encargado', 'Who is looking?': '¿Quién consulta?',
    'A manager PIN shows everyone\'s hours. Your own PIN shows only yours.': 'Un PIN de encargado muestra las horas de todos. Su propio PIN muestra solo las suyas.',
    'Show hours': 'Ver horas', 'Add person': 'Agregar persona', "PIN (4–8 digits, they'll type it to clock in)": 'PIN (4 a 8 dígitos; lo escribirá para marcar)',
    'Team member (clock in and out)': 'Miembro del equipo (marca entrada y salida)', 'Manager (can approve changes with their PIN)': 'Encargado (aprueba cambios con su PIN)',
    'Currently works here (shows on the clock screen)': 'Trabaja aquí actualmente (aparece en la pantalla del reloj)',
    'May open the sales reports with their PIN': 'Puede abrir los reportes de ventas con su PIN',
    'First setup: this person becomes the manager and no approval is needed this one time.': 'Primera configuración: esta persona será el encargado y no se necesita aprobación esta única vez.',
    'e.g. forgot to clock out': 'ej. olvidó marcar la salida', 'Only the owner login can change the team.': 'Solo el ingreso del propietario puede cambiar el equipo.',
    'That person is not a manager. Ask a manager to approve this.': 'Esa persona no es encargada. Pida a un encargado que apruebe esto.',
    'Pick who is approving this.': 'Elija quién aprueba esto.', 'Write the reason for the change.': 'Escriba el motivo del cambio.',
    'Clock in time is required.': 'La hora de entrada es obligatoria.', 'Clock out must be after clock in.': 'La salida debe ser después de la entrada.',
    'The name cannot be empty.': 'El nombre no puede estar vacío.', 'A new person needs a PIN.': 'Una persona nueva necesita un PIN.',
    'The PIN must be 4 to 8 digits, numbers only.': 'El PIN debe tener de 4 a 8 dígitos, solo números.',
    'This is the only active manager. Make someone else a manager first.': 'Es el único encargado activo. Primero haga encargado a alguien más.',
    'That record no longer exists. Reload the page.': 'Ese registro ya no existe. Recargue la página.',
    'The manager approval setup has not been run in Supabase yet.': 'La configuración de aprobaciones todavía no se ha ejecutado en Supabase.',
    'No manager on the team yet': 'Todavía no hay encargado en el equipo', 'Could not load the team. Check the connection.': 'No se pudo cargar el equipo. Revise la conexión.',
    'Former team member': 'Exmiembro del equipo', 'Could not load the clock. Check the connection.': 'No se pudo cargar el reloj. Revise la conexión.',
    'No one on the team yet.': 'Todavía no hay nadie en el equipo.', 'Go to': 'Vaya a', 'and tap': 'y toque',
    'In since {t}': 'Desde las {t}', 'Forgot to clock out? Fix it in Hours.': '¿Olvidó marcar la salida? Corríjalo en Horas.',
    'Type your PIN to clock OUT.': 'Escriba su PIN para marcar la SALIDA.', 'Type your PIN to clock IN.': 'Escriba su PIN para marcar la ENTRADA.',
    'clocked out · {t}': 'salida marcada · {t}', 'Could not load the hours. Check the connection.': 'No se pudieron cargar las horas. Revise la conexión.',
    'This week · from {d}': 'Esta semana · desde el {d}', 'Last week · from {d}': 'Semana pasada · desde el {d}', 'This month · from {d}': 'Este mes · desde el {d}',
    'Shift changed': 'Turno cambiado', 'Shift added': 'Turno agregado', 'Shift deleted': 'Turno eliminado', 'Team updated': 'Equipo actualizado',
    'Order voided': 'Pedido anulado', 'Menu changed': 'Menú cambiado', 'Sales opened': 'Ventas abiertas', 'Sales access changed': 'Acceso a ventas cambiado',
    'The approvals log switches on once the manager approval setup is run.': 'La bitácora de aprobaciones se activa cuando se ejecute la configuración de aprobaciones.',
    'Nothing approved yet.': 'Todavía no hay aprobaciones.', '· approved by {x}': '· aprobado por {x}',
    'No team members yet — add people below.': 'Todavía no hay miembros del equipo; agregue personas abajo.', '+ Add shift': '+ Agregar turno',
    'still in · {t}': 'todavía en turno · {t}', 'Edit shift · {x}': 'Editar turno · {x}', 'Add shift · {x}': 'Agregar turno · {x}',
    'Shift saved and logged': 'Turno guardado y anotado', 'Delete this shift? A manager PIN and a reason are required, and it is logged.': '¿Eliminar este turno? Se necesita el PIN de un encargado y un motivo, y queda anotado.',
    'Shift deleted and logged': 'Turno eliminado y anotado',
    'Nobody yet. Add the team with the button below — each person picks a PIN to type when clocking in.': 'Todavía nadie. Agregue al equipo con el botón de abajo; cada persona elige un PIN para marcar.',
    'Team changes are made from the owner login.': 'Los cambios de equipo se hacen desde el ingreso del propietario.',
    'Edit · {x}': 'Editar · {x}', 'New PIN (leave empty to keep the current one)': 'Nuevo PIN (déjelo vacío para conservar el actual)',
    'Saved, but the sales access did not change. Try again from the owner login.': 'Se guardó, pero el acceso a ventas no cambió. Intente de nuevo desde el ingreso del propietario.',
    '{x} saved': '{x} guardado', '{x} is now the manager': '{x} ahora es el encargado', 'active': 'activo', 'inactive': 'inactivo', 'manager': 'encargado', 'sales': 'ventas',
    'no shifts': 'sin turnos', 'Edit': 'Editar',

    /* kitchen */
    'Kitchen · The Hanging Garden': 'Cocina · The Hanging Garden', 'One step before the kitchen screen works': 'Falta un paso para que funcione la pantalla de cocina',
    'Run': 'Ejecute', 'once in Supabase (SQL Editor → New query → paste → Run), then reload this page.': 'una vez en Supabase (SQL Editor → New query → pegar → Run) y recargue esta página.',
    'The Hanging Garden · tickets appear here as they come in': 'The Hanging Garden · las comandas aparecen aquí al llegar',
    'Sound: on': 'Sonido: activado', 'Sound: off': 'Sonido: apagado', 'Nothing to prepare right now.': 'Nada que preparar por ahora.',
    'Ready, waiting for pickup': 'Listos, esperando entrega', 'Front counter': 'Mostrador', 'Start': 'Empezar', 'Done': 'Listo',

    /* TV board */
    'Menu Board · The Hanging Garden': 'Pantalla del menú · The Hanging Garden', 'Monteverde, Costa Rica · made for the cloud forest': 'Monteverde, Costa Rica · hecho para el bosque nuboso',
    'Pura vida': 'Pura vida', 'The menu board lost its connection.': 'La pantalla del menú perdió la conexión.', 'It will keep trying by itself.': 'Seguirá intentando por su cuenta.'
  };

  /* ---------- pattern entries ({x} placeholders) ---------- */
  var PAT = [];
  Object.keys(D).forEach(function (k) {
    if (k.indexOf('{') < 0) return;
    var names = [];
    var re = '^' + k.replace(/[.*+?^$()|[\]\\]/g, '\\$&').replace(/\{(\w+)\}/g, function (_, n) { names.push(n); return '(.+?)'; }) + '$';
    PAT.push({ re: new RegExp(re), names: names, es: D[k] });
  });

  function lookup(k) {
    if (D.hasOwnProperty(k)) return D[k];
    for (var i = 0; i < PAT.length; i++) {
      var m = k.match(PAT[i].re);
      if (m) {
        var out = PAT[i].es;
        PAT[i].names.forEach(function (n, j) { out = out.replace('{' + n + '}', m[j + 1]); });
        return out;
      }
    }
    return null;
  }
  function tr(text) {
    var k = text.replace(/\s+/g, ' ').trim();
    if (!k || !/[A-Za-z]/.test(k)) return null;
    var t = lookup(k);
    if (t !== null) return t;
    /* "Label:" or "Label…" */
    var m = k.match(/^(.*?)([:…]|\.\.\.)$/);
    if (m && (t = lookup(m[1].trim())) !== null) return t + m[2];
    /* "part · part" */
    if (k.indexOf(' · ') > 0) {
      var any = false;
      var parts = k.split(' · ').map(function (p) { var x = lookup(p.trim()); if (x !== null) { any = true; return x; } return p; });
      if (any) return parts.join(' · ');
    }
    return null;
  }

  /* ---------- state ---------- */
  var lang = 'en';
  try { lang = localStorage.getItem(KEY) || ''; } catch (e) {}
  if (lang !== 'en' && lang !== 'es') lang = /^es/i.test(navigator.language || '') ? 'es' : 'en';
  window.HG_LANG = lang;

  var ATTRS = ['placeholder', 'title', 'aria-label', 'alt'];

  function setText(node, value) { if (node.nodeValue !== value) node.nodeValue = value; node.__hgLast = value; }

  function handleText(node) {
    var p = node.parentNode;
    if (!p || p.nodeType !== 1) return;
    var tag = p.tagName;
    if (tag === 'SCRIPT' || tag === 'STYLE' || tag === 'NOSCRIPT' || tag === 'TEXTAREA') return;
    if (p.closest && p.closest('[data-no-translate],[data-split]')) return;
    var cur = node.nodeValue;
    if (node.__hgLast === undefined || cur !== node.__hgLast) node.__hgEn = cur;   /* fresh English from the page or its scripts */
    var en = node.__hgEn;
    if (lang === 'es') {
      var t = tr(en);
      if (t !== null) {
        var lead = en.match(/^\s*/)[0], tail = en.match(/\s*$/)[0];
        setText(node, lead + t + tail); return;
      }
    }
    setText(node, en);
  }

  function handleAttr(el, a) {
    var cur = el.getAttribute(a);
    if (cur === null) return;
    el.__hgA = el.__hgA || {};
    var rec = el.__hgA[a];
    if (!rec || cur !== rec.last) rec = el.__hgA[a] = { en: cur, last: cur };
    var want = rec.en;
    if (lang === 'es') { var t = tr(rec.en); if (t !== null) want = t; }
    if (cur !== want) el.setAttribute(a, want);
    rec.last = want;
  }

  /* headline words split into spans by the home page: translate the whole line, then re-split */
  function handleSplit(el) {
    var en = el.__hgSplitEn || (el.__hgSplitEn = el.getAttribute('aria-label') || el.textContent);
    var spans = el.querySelectorAll('.w');
    if (!spans.length) return;
    var want = lang === 'es' ? (tr(en) || en) : en;
    if (el.__hgSplitLast === want) return;
    el.__hgSplitLast = want;
    var words = want.split(' ');
    if (words.length === spans.length) { spans.forEach(function (s, i) { s.textContent = words[i]; }); }
    else { spans.forEach(function (s, i) { s.textContent = i === 0 ? want : ''; }); }
  }

  var swHost = null;
  function visible(el) { return !!(el && el.getClientRects().length); }
  function placeSwitch() {
    if (!sw) return;
    if (swHost === null) {
      swHost = document.querySelector('#nav .navlinks') || document.querySelector('nav.pagenav') ||
               document.querySelector('header.top') || document.getElementById('soundBtn') || false;
    }
    var host = swHost;
    if (host && visible(host)) {
      if (sw.parentNode === host.parentNode && host.id === 'soundBtn') return;
      if (sw.parentNode === host) return;
      sw.classList.remove('fixed'); sw.style.marginLeft = '';
      if (host.id === 'soundBtn') { host.parentNode.insertBefore(sw, host); }
      else if (host.tagName === 'HEADER') { var ob = host.querySelector('#outBtn'); sw.style.marginLeft = 'auto'; if (ob) { ob.style.marginLeft = '0'; host.insertBefore(sw, ob); } else host.appendChild(sw); }
      else if (host.classList.contains('pagenav')) { sw.style.marginLeft = 'auto'; host.appendChild(sw); }
      else { host.appendChild(sw); }
      if (!document.getElementById('nav')) sw.classList.remove('dark');
    } else {
      if (sw.parentNode === document.body && sw.classList.contains('fixed')) return;
      sw.classList.add('fixed'); sw.style.marginLeft = '';
      document.body.appendChild(sw);
      if (document.body.classList.contains('tv') || document.getElementById('board')) sw.classList.add('dark');
    }
  }

  var busy = false;
  function applyAll() {
    if (busy) return; busy = true;
    try {
      var root = document.documentElement;
      var w = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null);
      var n; while ((n = w.nextNode())) handleText(n);
      var all = root.querySelectorAll('[placeholder],[title],[aria-label],[alt],input[type=button],input[type=submit]');
      for (var i = 0; i < all.length; i++) {
        var el = all[i];
        for (var j = 0; j < ATTRS.length; j++) if (el.hasAttribute(ATTRS[j])) handleAttr(el, ATTRS[j]);
        if (el.tagName === 'INPUT' && (el.type === 'button' || el.type === 'submit')) handleAttr(el, 'value');
      }
      var splits = root.querySelectorAll('[data-split]');
      for (var s = 0; s < splits.length; s++) handleSplit(splits[s]);
      root.lang = lang;
    } finally { busy = false; }
    placeSwitch();
    syncSwitch();
  }

  /* native dialogs built by the pages' own scripts */
  ['alert', 'confirm', 'prompt'].forEach(function (fn) {
    var orig = window[fn];
    if (typeof orig !== 'function') return;
    window[fn] = function (msg, dflt) {
      var m = (lang === 'es' && typeof msg === 'string') ? (tr(msg) || msg) : msg;
      return fn === 'prompt' ? orig.call(window, m, dflt) : orig.call(window, m);
    };
  });

  /* ---------- the visible switch ---------- */
  var sw;
  function syncSwitch() {
    if (!sw) return;
    var bs = sw.querySelectorAll('button');
    bs[0].classList.toggle('on', lang === 'en'); bs[0].setAttribute('aria-pressed', lang === 'en');
    bs[1].classList.toggle('on', lang === 'es'); bs[1].setAttribute('aria-pressed', lang === 'es');
  }
  function setLang(l) {
    if (l === lang) return;
    lang = l; window.HG_LANG = l;
    try { localStorage.setItem(KEY, l); } catch (e) {}
    applyAll();
    try { document.dispatchEvent(new CustomEvent('hg-lang', { detail: l })); } catch (e) {}
  }
  function buildSwitch() {
    var css = document.createElement('style');
    css.setAttribute('data-hg-lang', '');
    css.textContent =
      '.hg-lang{display:inline-flex;align-items:center;gap:0;border:1.5px solid rgba(120,120,110,.45);border-radius:99px;padding:2px;' +
      'font:600 .72rem/1 system-ui,-apple-system,Segoe UI,Roboto,sans-serif;letter-spacing:.06em;background:rgba(255,255,255,.55);' +
      'backdrop-filter:blur(6px);-webkit-backdrop-filter:blur(6px);flex:none;text-shadow:none}' +
      '.hg-lang button{all:unset;cursor:pointer;padding:.42em .7em;border-radius:99px;color:#4a5a4e;min-height:0;line-height:1}' +
      '.hg-lang button.on{background:#1E4B33;color:#fff}' +
      '.hg-lang button:focus-visible{outline:2px solid #1E4B33;outline-offset:2px}' +
      '.hg-lang.fixed{position:fixed;top:.6rem;right:.7rem;z-index:2147483000}' +
      '.hg-lang.dark{background:rgba(0,0,0,.35);border-color:rgba(255,255,255,.45)}.hg-lang.dark button{color:#F6EFE3}.hg-lang.dark button.on{background:#F6EFE3;color:#1E4B33}' +
      '@media print{.hg-lang{display:none}}';
    document.head.appendChild(css);
    sw = document.createElement('div');
    sw.className = 'hg-lang'; sw.setAttribute('data-no-translate', ''); sw.setAttribute('role', 'group'); sw.setAttribute('aria-label', 'Language / Idioma');
    sw.innerHTML = '<button type="button" lang="en">EN</button><button type="button" lang="es">ES</button>';
    sw.querySelectorAll('button')[0].addEventListener('click', function () { setLang('en'); });
    sw.querySelectorAll('button')[1].addEventListener('click', function () { setLang('es'); });
    placeSwitch();
    if (document.getElementById('nav')) {
      /* the website's bar swaps colours over the film; follow it */
      var nav = document.getElementById('nav');
      var follow = function () { sw.classList.toggle('dark', nav.classList.contains('on-video')); };
      new MutationObserver(follow).observe(nav, { attributes: true, attributeFilter: ['class'] }); follow();
    }
    syncSwitch();
  }

  function start() {
    buildSwitch();
    applyAll();
    var pending = false;
    new MutationObserver(function () {
      if (busy || pending) return;
      pending = true;
      requestAnimationFrame(function () { pending = false; applyAll(); });
    }).observe(document.documentElement, { childList: true, subtree: true, characterData: true, attributes: true, attributeFilter: ATTRS.concat(['value']) });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();
})();
