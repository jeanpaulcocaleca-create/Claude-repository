/* Hanging Garden Café · English / Español switch
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
    'Home': 'Inicio', 'Address': 'Dirección', 'Menu': 'Menú', 'POS': 'Caja', 'Sales': 'Ventas', 'Time clock': 'Reloj de marcas',
    'TV board': 'Pantalla TV', 'Menu Manager': 'Gestor del menú', 'Kitchen screen': 'Pantalla de cocina',
    'Kitchen': 'Cocina', 'Website': 'Sitio web', 'Loading…': 'Cargando…', 'Signing in…': 'Ingresando…',
    'Manager': 'Encargado', 'PIN': 'PIN', 'Manager PIN': 'PIN del encargado', 'Approved by': 'Aprobado por',
    'Reason': 'Motivo', 'Name': 'Nombre', 'Role': 'Puesto', 'Team': 'Equipo', 'Hours': 'Horas',
    'Today': 'Hoy', 'This week': 'Esta semana', 'Last week': 'Semana pasada', 'This month': 'Este mes',
    'Last 7 days': 'Últimos 7 días', 'Last 30 days': 'Últimos 30 días', 'Download CSV': 'Descargar CSV',
    'That login did not work.': 'Ese ingreso no funcionó.',
    'That login did not work. Check the email and password.': 'Ese ingreso no funcionó. Revise el correo y la contraseña.',
    /* sign-in on a tablet (login.js): say why it failed */
    'Show': 'Mostrar', 'Hide': 'Ocultar', 'Show password': 'Mostrar contraseña', 'Hide password': 'Ocultar contraseña',
    'The email or the password is not right. Tap Show to check the password.': 'El correo o la contraseña no son correctos. Toque Mostrar para revisar la contraseña.',
    'This login is not activated yet. The owner must confirm it in Supabase.': 'Este ingreso todavía no está activado. El dueño tiene que confirmarlo en Supabase.',
    'Too many tries. Wait 5 minutes, then try again.': 'Demasiados intentos. Espere 5 minutos y vuelva a intentarlo.',
    'This login is blocked. Ask the owner.': 'Este ingreso está bloqueado. Consulte con el dueño.',
    'This device has no internet. Check the Wi-Fi and try again.': 'Este dispositivo no tiene internet. Revise el wifi e intente de nuevo.',
    'Could not reach the sign-in server. Check the Wi-Fi, and the date and time of this device.': 'No se pudo conectar con el servidor de ingreso. Revise el wifi y la fecha y hora de este dispositivo.',
    'The sign-in server is not answering. Wait a minute and try again.': 'El servidor de ingreso no responde. Espere un minuto e intente de nuevo.',
    'Email sign-in is switched off in Supabase. Ask the owner.': 'El ingreso con correo está desactivado en Supabase. Consulte con el dueño.',
    'Supabase asks for a captcha that this page does not have. The owner must switch it off.': 'Supabase pide un captcha que esta página no tiene. El dueño tiene que desactivarlo.',
    'The password cannot start or end with a space.': 'La contraseña no puede empezar ni terminar con un espacio.',
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

    /* Canopy OS · Phase 0: updates, refunds, inventory history */
    'A new version is ready. It updates by itself when you finish what you are doing.': 'Hay una versión nueva. Se actualiza sola cuando termine lo que está haciendo.',
    'Update now': 'Actualizar ahora', 'update ready': 'actualización lista',
    'A new version is ready. It updates by itself between sales.': 'Hay una versión nueva. Se actualiza sola entre ventas.',
    'Finish the sale in progress first, or wait until the pending sales are saved.': 'Termine primero la venta en curso, o espere a que se guarden las ventas pendientes.',
    'Money goes back as': 'El dinero se devuelve en', 'Put the items back in stock (unopened, still good)': 'Devolver los productos al inventario (sin abrir, en buen estado)',
    'Refund · money given back': 'Devolución · dinero devuelto', 'Refund today': 'Devolver hoy',
    'That day was already closed at the register, so the sale stays on it. The money is given back today: type the PIN again.':
      'Ese día ya se cerró en caja, así que la venta se queda en ese día. El dinero se devuelve hoy: escriba el PIN otra vez.',
    'That sale was already refunded.': 'Esa venta ya se devolvió.', 'A refund cannot be voided. Ring up a new sale instead.': 'Una devolución no se anula. Registre una venta nueva.',
    'This day is still open: void the sale instead.': 'Este día sigue abierto: anule la venta.',
    'This bill was paid in parts: give each payment back from the bill.': 'Esta cuenta se pagó por partes: devuelva cada pago desde la cuenta.',
    'That bill was not paid.': 'Esa cuenta no se pagó.', 'Pick how the money goes back.': 'Elija cómo se devuelve el dinero.',
    'Refunded {x}': 'Devuelto {x}', 'items back in stock': 'productos de vuelta al inventario',
    'This item has history (sales, counts or orders), so it is kept. Untick Active to hide it.': 'Este producto tiene historial (ventas, conteos o pedidos), por eso se conserva. Desmarque Activo para ocultarlo.',
    'This vendor has purchase orders, so it is kept. Untick Active to hide it.': 'Este proveedor tiene órdenes de compra, por eso se conserva. Desmarque Activo para ocultarlo.',
    'Delete "{n}"? Items with history cannot be deleted: untick Active instead.': '¿Eliminar "{n}"? Los productos con historial no se eliminan: desmarque Activo.',
    'This order was already received.': 'Esta orden ya se recibió.', 'This order was cancelled.': 'Esta orden se canceló.',
    'Quantities and costs cannot be negative.': 'Las cantidades y los costos no pueden ser negativos.',
    'Could not check the PIN. Check the connection and try again.': 'No se pudo revisar el PIN. Revise la conexión e intente de nuevo.',
    'Who is ringing up?': '¿Quién cobra?', 'Who is ringing up': 'Quién cobra', 'Start': 'Empezar', 'Clock in and start': 'Marcar entrada y empezar',
    'Start without internet (checked later)': 'Empezar sin internet (se revisa después)', 'End my turn': 'Terminar mi turno', 'Not now': 'Ahora no',
    'Ringing up now: {n}': 'Cobrando ahora: {n}', '{n} is ringing up': '{n} está cobrando', '{n} is ringing up · not clocked in': '{n} está cobrando · sin marcar entrada',
    '{n} has not clocked in. Clock in to start.': '{n} no ha marcado entrada. Marque entrada para empezar.', 'not checked': 'sin revisar',
    'Pick your name.': 'Elija su nombre.', 'Could not start. Try again.': 'No se pudo empezar. Intente de nuevo.',
    'Choose who is ringing up first.': 'Primero elija quién cobra.', 'Type the PIN.': 'Escriba el PIN.',
    'System settings': 'Ajustes del sistema', 'Who rings up each sale': 'Quién cobra cada venta', 'Off (as before)': 'Apagado (como antes)',
    'Record who rings up': 'Registrar quién cobra', 'Require clock-in to ring up': 'Exigir marcar entrada para cobrar', 'On': 'Encendido',
    'Only the owner login, with the phone code, can change settings.': 'Solo el ingreso del dueño, con el código del teléfono, puede cambiar los ajustes.',
    'That value is not allowed.': 'Ese valor no está permitido.', 'Locked: record the confirmation of this rule first.': 'Con candado: primero registre la confirmación de esta regla.',
    'Settings with a lock follow a legal rule (taxes, payroll, electronic invoices). They switch on only after the rule is confirmed by your accountant or an official source. Record who confirmed it and with which document:':
      'Los ajustes con candado siguen una regla legal (impuestos, planilla, factura electrónica). Solo se encienden después de que su contador o una fuente oficial confirme la regla. Registre quién la confirmó y con qué documento:',
    'Confirmed by (name)': 'Confirmado por (nombre)', 'Document or reference': 'Documento o referencia', 'Record the confirmation': 'Registrar la confirmación',
    'Rule': 'Regla', 'Saved.': 'Guardado.', 'Confirmation recorded.': 'Confirmación registrada.', 'Write who confirmed it and the document.': 'Escriba quién lo confirmó y el documento.',
    'Before IVA': 'Sin IVA', 'Includes IVA {r}': 'Incluye IVA {r}', 'IVA {r}': 'IVA {r}',
    'IVA rate': 'Tarifa de IVA', 'CABYS code (13 digits, from your accountant)': 'Código CABYS (13 dígitos, de su contador)',
    'Price before IVA, in colones (the menu, website and TV show it with IVA)': 'Precio sin IVA, en colones (el menú, el sitio y la TV lo muestran con IVA)',
    'The CABYS code has 13 digits.': 'El código CABYS tiene 13 dígitos.',
    'Cash received': 'Efectivo recibido', 'To pay': 'A pagar', 'Colones': 'Colones', 'Dollars': 'Dólares', 'Received': 'Recibido', 'Change': 'Vuelto',
    'Exact amount': 'Monto exacto', 'Start over': 'Empezar de nuevo', 'Charge': 'Cobrar', 'Add': 'Agregar',
    'Other amount in colones': 'Otro monto en colones', 'Missing {x}': 'Faltan {x}', 'Change to give: {x}': 'Vuelto: {x}', 'Change photo': 'Cambiar foto', 'Change photo for {n}': 'Cambiar la foto de {n}',
    '· no rate today': '· sin tipo de cambio hoy', '(old rate)': '(tipo de cambio viejo)', 'In dollars': 'En dólares',
    'Dollars in the float ($)': 'Dólares en el fondo ($)', 'Dollars in the drawer, float included ($)': 'Dólares en la caja, con el fondo ($)',
    'Expected dollars in the drawer': 'Dólares esperados en la caja', 'Expected dollars': 'Dólares esperados', 'Dollars counted': 'Dólares contados',
    'Dollar difference': 'Diferencia en dólares',
    'Exchange rate for dollars': 'Tipo de cambio para dólares', 'Prices at the POS': 'Precios en la caja', 'Buy rate of the day': 'Tipo de compra del día',
    'Sell rate of the day': 'Tipo de venta del día', 'IVA included (as today)': 'Con IVA incluido (como hoy)', 'Before IVA, IVA added at checkout': 'Sin IVA, el IVA se suma al cobrar',
    'Search earlier sales · reprint · refund': 'Buscar ventas anteriores · reimprimir · devolver', 'Search sales': 'Buscar ventas',
    'Receipt Nº, item, name or cashier': 'Nº de recibo, producto, nombre o cajero', 'Amount ₡': 'Monto ₡', 'Search': 'Buscar', 'Day': 'Día',
    'Open earlier days with a manager PIN': 'Abrir días anteriores con el PIN de un encargado', 'No sales found.': 'No se encontraron ventas.',
    'Earlier days are sales history: a manager opens them with a PIN.': 'Los días anteriores son historial de ventas: un encargado los abre con su PIN.',
    'Searching earlier sales switches on with the next database update.': 'La búsqueda de ventas anteriores se activa con la próxima actualización de la base de datos.',
    'Could not search. Check the connection and try again.': 'No se pudo buscar. Revise la conexión e intente de nuevo.', 'Could not search. Try again.': 'No se pudo buscar. Intente de nuevo.',
    'Reprint': 'Reimprimir', 'Refund': 'Devolver', 'Void': 'Anular', 'Confirm': 'Confirmar', 'Refunded {d}': 'Devuelto {d}', 'Refund {x}': 'Devolver {x}', 'Void {x}': 'Anular {x}',
    'Sales history · managers': 'Historial de ventas · encargados', 'Back': 'Volver',
    'Receive a delivery': 'Recibir una entrega', 'Supplier invoice Nº': 'Nº de factura del proveedor', 'Invoice date': 'Fecha de la factura',
    'Type what arrived in this delivery. If part of the order comes later, receive it again then. Costs update the item\'s price.':
      'Escriba lo que llegó en esta entrega. Si parte del pedido llega después, recíbala de nuevo entonces. Los costos actualizan el precio del producto.',
    'Ordered': 'Pedido', 'Already in': 'Ya recibido', 'This delivery': 'Esta entrega', 'Nothing more is coming: close the order': 'No llegará nada más: cerrar el pedido',
    'Partly received': 'Recibido en parte', 'Receive': 'Recibir', 'Share': 'Compartir', 'Copy text': 'Copiar texto', 'Print / PDF': 'Imprimir / PDF',
    'Create all orders': 'Crear todos los pedidos', '1 order created': '1 pedido creado', '{n} orders created': '{n} pedidos creados', 'Order text copied': 'Texto del pedido copiado',
    'That invoice of this supplier was already entered.': 'Esa factura de este proveedor ya se registró.', 'Delivery received · the rest is still on order': 'Entrega recibida · el resto sigue pedido',
    'Allow pop-ups to print the order.': 'Permita ventanas emergentes para imprimir el pedido.',
    'This needs a database update: apply the pending migrations (docs/MIGRACIONES.md), then reload this page.': 'Esto necesita una actualización de la base de datos: aplique las migraciones pendientes (docs/MIGRACIONES.md) y recargue esta página.',
    'Spanish names and descriptions for the QR menu need a database update: apply the pending migrations (docs/MIGRACIONES.md).': 'Los nombres y descripciones en español del menú QR necesitan una actualización de la base de datos: aplique las migraciones pendientes (docs/MIGRACIONES.md).',
    'Saved. To keep the look, apply the pending database migrations (docs/MIGRACIONES.md).': 'Guardado. Para conservar el estilo, aplique las migraciones pendientes de la base de datos (docs/MIGRACIONES.md).',
    'Apply the pending database migrations, in order, as described in docs/MIGRACIONES.md.': 'Aplique las migraciones pendientes de la base de datos, en orden, como se explica en docs/MIGRACIONES.md.',
    'Approve with a manager PIN.': 'Apruebe con el PIN de un encargado.',
    'Locked until the rule is confirmed': 'Con candado hasta que se confirme la regla',
    "Accounting · owner and accountant": "Contabilidad · dueño y contador",
    "Accounting": "Contabilidad",
    "This page is for the owner (with the phone code) and the accountant.": "Esta página es para el dueño (con el código del teléfono) y el contador.",
    "Accountant": "Contador",
    "Owner": "Dueño",
    "Before the books run by themselves": "Antes de que los libros funcionen solos",
    "The chart of accounts below is a proposal. Once your accountant approves it (and the first day to post), the register close posts each day automatically. Until then a day can be posted here to review it.": "El catálogo de cuentas de abajo es una propuesta. Cuando su contador lo apruebe (y el primer día a asentar), el cierre de caja asienta cada día solo. Mientras tanto, aquí se puede asentar un día para revisarlo.",
    "Approved by (accountant)": "Aprobado por (contador)",
    "First day to post": "Primer día a asentar",
    "Approve and switch on": "Aprobar y activar",
    "Closed days not in the books yet": "Días cerrados que todavía no están en los libros",
    "Post these days": "Asentar estos días",
    "Summary": "Resumen",
    "Journal": "Diario",
    "Reports": "Reportes",
    "Expenses": "Gastos",
    "Accounts": "Cuentas",
    "Periods": "Periodos",
    "Month": "Mes",
    "Revenue": "Ingresos",
    "Costs and expenses": "Costos y gastos",
    "Net income": "Utilidad neta",
    "Cash and bank": "Caja y bancos",
    "IVA payable": "IVA por pagar",
    "From the entries in the books. Days not posted yet are not included.": "Según los asientos en los libros. Los días sin asentar no se incluyen.",
    "+ New entry": "+ Asiento nuevo",
    "From": "Desde",
    "To": "Hasta",
    "Account": "Cuenta",
    "All accounts": "Todas las cuentas",
    "Account…": "Cuenta…",
    "Date": "Fecha",
    "Description": "Descripción",
    "Opening balances": "Saldos iniciales",
    "+ Line": "+ Línea",
    "Post the entry": "Registrar el asiento",
    "Debit": "Debe",
    "Credit": "Haber",
    "Remove the line": "Quitar la línea",
    "Report": "Reporte",
    "Trial balance": "Balanza de comprobación",
    "Income statement": "Estado de resultados",
    "Balance sheet": "Balance general",
    "Cash flow": "Flujo de efectivo",
    "Show": "Mostrar",
    "Print": "Imprimir",
    "New expense": "Gasto nuevo",
    "Supplier": "Proveedor",
    "What was it?": "¿Qué fue?",
    "Total paid, IVA included (₡)": "Total pagado, con IVA (₡)",
    "Creditable IVA (₡)": "IVA acreditable (₡)",
    "Paid from": "Pagado con",
    "The register (colones)": "La caja (colones)",
    "Petty cash": "Caja chica",
    "Bank or company card": "Banco o tarjeta de la empresa",
    "On credit (to pay later)": "A crédito (se paga después)",
    "Invoice Nº": "Nº de factura",
    "Save the expense": "Guardar el gasto",
    "Supplier · description": "Proveedor · descripción",
    "Invoice": "Factura",
    "Chart of accounts": "Catálogo de cuentas",
    "+ Account": "+ Cuenta",
    "Code": "Código",
    "Type": "Tipo",
    "Asset": "Activo",
    "Liability": "Pasivo",
    "Equity": "Patrimonio",
    "Cost or expense": "Costo o gasto",
    "Cash or bank": "Caja o banco",
    "Inactive": "Inactiva",
    "Where the automatic entries go": "A dónde van los asientos automáticos",
    "Line": "Línea",
    "Close a month when its books are complete: nothing more can be dated in it (the accountant can reopen it). Lock it when it is filed: then it never changes again.": "Cierre un mes cuando sus libros estén completos: ya no se puede registrar nada con fecha de ese mes (el contador puede reabrirlo). Bloquéelo cuando esté declarado: entonces nunca vuelve a cambiar.",
    "Status": "Estado",
    "Changed": "Cambio",
    "No entries yet.": "Todavía no hay asientos.",
    "Open for entries": "Abierto",
    "Closed": "Cerrado",
    "Locked": "Bloqueado",
    "Close": "Cerrar",
    "Reopen": "Reabrir",
    "Lock": "Bloquear",
    "Lock this month for good? It can never change again.": "¿Bloquear este mes para siempre? Nunca podrá volver a cambiar.",
    "Reversed": "Revertido",
    "Reverse": "Revertir",
    "Manual": "Manual",
    "Day": "Día",
    "Expense": "Gasto",
    "Reversal": "Reversión",
    "Opening": "Apertura",
    "Payroll": "Planilla",
    "Suppliers": "Proveedores",
    "Bank": "Banco",
    "No entries in these days.": "No hay asientos en estos días.",
    "Why is entry Nº {n} reversed?": "¿Por qué se revierte el asiento Nº {n}?",
    "Reversal posted": "Reversión registrada",
    "Entry Nº {n} posted": "Asiento Nº {n} registrado",
    "Write a description.": "Escriba una descripción.",
    "An entry needs at least two lines.": "Un asiento necesita al menos dos líneas.",
    "Total revenue": "Total de ingresos",
    "Total costs and expenses": "Total de costos y gastos",
    "Assets": "Activos",
    "Liabilities": "Pasivos",
    "Total assets": "Total de activos",
    "Total liabilities": "Total de pasivos",
    "Results not yet closed": "Resultados sin cerrar",
    "Total liabilities and equity": "Total de pasivo y patrimonio",
    "The balance sheet does not balance: tell the accountant.": "El balance no cuadra: avísele al contador.",
    "Cash and bank at the start": "Caja y bancos al inicio",
    "Cash and bank at the end": "Caja y bancos al final",
    "Closing": "Cierre",
    "Why is this expense voided?": "¿Por qué se anula este gasto?",
    "Expense voided": "Gasto anulado",
    "Write what it was and the total.": "Escriba qué fue y el total.",
    "Expense saved and posted": "Gasto guardado y asentado",
    "Account saved": "Cuenta guardada",
    "Voided": "Anulado",
    "Only the owner (with the phone code) and the accountant can do this.": "Solo el dueño (con el código del teléfono) y el contador pueden hacer esto.",
    "Debits and credits must be equal.": "El debe y el haber deben ser iguales.",
    "That month is closed. Use a date in an open month.": "Ese mes está cerrado. Use una fecha de un mes abierto.",
    "One of the accounts does not exist or is not active.": "Una de las cuentas no existe o no está activa.",
    "That entry was already reversed.": "Ese asiento ya se revirtió.",
    "A reversal is not reversed again: post a new entry.": "Una reversión no se revierte: registre un asiento nuevo.",
    "That month is locked.": "Ese mes está bloqueado.",
    "Close the earlier months first.": "Cierre primero los meses anteriores.",
    "A later month is locked.": "Un mes posterior está bloqueado.",
    "Check the values.": "Revise los valores.",
    "This account has entries: its type cannot change.": "Esta cuenta tiene asientos: su tipo no puede cambiar.",
    "The automatic entries use this account: it stays active.": "Los asientos automáticos usan esta cuenta: queda activa.",
    "Pick an expense account.": "Elija una cuenta de gasto.",
    "The date cannot be in the future.": "La fecha no puede ser futura.",
    "Record the approval first.": "Registre primero la aprobación.",
    "Only the owner can switch this on.": "Solo el dueño puede activar esto.",
    "Write who approved it and the document.": "Escriba quién lo aprobó y el documento.",
    "Pick at most three months.": "Elija como máximo tres meses.",
    "Write the reason.": "Escriba el motivo.",
    "Already voided.": "Ya está anulado.",
    "Write who approved it, the document and the first day.": "Escriba quién lo aprobó, el documento y el primer día.",
    "The books now post each day at the register close": "Los libros ahora asientan cada día al cerrar la caja",
    "{n} entries posted": "{n} asientos registrados",
    "The accounting needs a database update: apply the pending migrations (docs/MIGRACIONES.md).": "La contabilidad necesita una actualización de la base de datos: aplique las migraciones pendientes (docs/MIGRACIONES.md).",
    "Debit {a} · Credit {b}": "Debe {a} · Haber {b}",
    "difference {x}": "diferencia {x}",
    "The books: the day's entries, expenses, reports and exports for the accountant.": 'Los libros: los asientos del día, gastos, reportes y archivos para el contador.',
    'Accountant login': 'Ingreso del contador', "accountant's email": 'correo del contador', "Accountant's email": 'Correo del contador', 'Give access': 'Dar acceso',
    'First create their login in Supabase → Authentication → Add user. They see only the accounting, never the POS or the inventory.':
      'Primero cree su ingreso en Supabase → Authentication → Add user. Solo ve la contabilidad, nunca la caja ni el inventario.',
    'There is no login with that email yet: create it in Supabase → Authentication first.': 'Todavía no hay un ingreso con ese correo: créelo primero en Supabase → Authentication.',
    'That is an owner login.': 'Ese es un ingreso de dueño.', 'Only the owner login can do this.': 'Solo el ingreso del dueño puede hacer esto.', 'Done: {e} can open the accounting.': 'Listo: {e} puede abrir la contabilidad.',
    'Attach invoice': 'Adjuntar factura', 'Invoice attached': 'Factura adjunta', 'Could not save the file. Try again.': 'No se pudo guardar el archivo. Intente de nuevo.',
    'Photo or PDF of the invoice': 'Foto o PDF de la factura', "Month's package (ZIP)": 'Paquete del mes (ZIP)',
    'Expense saved, but the invoice file was not: attach it again from the list': 'Gasto guardado, pero el archivo de la factura no: adjúntelo de nuevo desde la lista',
    'Could not open the file. Try again.': 'No se pudo abrir el archivo. Intente de nuevo.', 'Could not build the package. Check the connection and try again.': 'No se pudo armar el paquete. Revise la conexión e intente de nuevo.',
    'PIN keypad': 'Teclado del PIN', 'Number keypad': 'Teclado numérico', 'Keyboard': 'Teclado', 'Erase': 'Borrar', 'Done': 'Listo', 'Clear': 'Limpiar', 'Space': 'Espacio',
    'Backups': 'Respaldos', 'Backups OK': 'Respaldos al día', 'Backups are not running yet': 'Los respaldos todavía no están funcionando',
    'No verified backup in 2 days': 'Sin respaldo verificado en 2 días', 'The backup is late': 'El respaldo está atrasado',
    'Last verified copy': 'Última copia verificada', 'restore test passed': 'prueba de restauración aprobada', 'Last attempt failed': 'El último intento falló',
    '{n} failed this week': '{n} fallaron esta semana', 'see docs/RESPALDOS.md': 'vea docs/RESPALDOS.md',
    'Set up the nightly backup: see docs/RESPALDOS.md.': 'Configure el respaldo nocturno: vea docs/RESPALDOS.md.',
    'less than an hour ago': 'hace menos de una hora', '{n} h ago': 'hace {n} h', '{n} days ago': 'hace {n} días',

    /* accounting: suppliers (0016) */
    'What is owed to suppliers': 'Lo que se debe a proveedores', 'Not due yet': 'Sin vencer', '1–30 days late': '1–30 días vencido', '31–60 days late': '31–60 días vencido',
    'Over 60 days late': 'Más de 60 días vencido', 'New supplier invoice': 'Factura de proveedor nueva', 'Due date': 'Fecha de vencimiento',
    'Amount before IVA (₡)': 'Monto sin IVA (₡)', 'IVA on the invoice (₡)': 'IVA de la factura (₡)', 'What was it for (no delivery)': 'Para qué fue (sin entrega)',
    'Deliveries of this supplier waiting for their invoice (tick the ones on it)': 'Entregas de este proveedor que esperan su factura (marque las que incluye)',
    'Save the invoice': 'Guardar la factura', 'Pay a supplier': 'Pagar a un proveedor', 'Amount (₡)': 'Monto (₡)', 'Bank transfer or SINPE': 'Transferencia o SINPE',
    'Reference': 'Referencia', 'Invoice to pay first': 'Factura que se paga primero', 'Record the payment': 'Registrar el pago',
    'Invoices of the last 3 months': 'Facturas de los últimos 3 meses', 'Payments of the last 3 months': 'Pagos de los últimos 3 meses',
    'Due': 'Vence', 'Still owed': 'Pendiente', 'Invoices': 'Facturas', 'Amount': 'Monto', 'Register': 'Caja', 'The oldest first': 'La más antigua primero',
    'Pick the supplier.': 'Elija el proveedor.', 'None: this invoice is for something else (a service, equipment…).': 'Ninguna: esta factura es por otra cosa (un servicio, equipo…).',
    'Received at cost {x}': 'Recibido al costo {x}', 'difference with the invoice {x}': 'diferencia con la factura {x}',
    'Owed to this supplier: {x}': 'Se le debe a este proveedor: {x}',
    "Fill in from the supplier's electronic invoice (XML file)": 'Llenar con la factura electrónica del proveedor (archivo XML)',
    'That file is not an XML file.': 'Ese archivo no es un archivo XML.',
    'That file is not an electronic invoice from Hacienda.': 'Ese archivo no es una factura electrónica de Hacienda.',
    'That is a credit or debit note, not an invoice: record it by hand with the accountant.': 'Es una nota de crédito o débito, no una factura: regístrela a mano con el contador.',
    'This invoice is in {x}. Invoices in dollars are not recorded here yet: ask the accountant.': 'Esta factura está en {x}. Las facturas en dólares todavía no se registran aquí: consulte al contador.',
    'Read from the XML: {x}, total {y}.': 'Leído del XML: {x}, total {y}.',
    'Pick the supplier: no single supplier in the list has that name.': 'Elija el proveedor: ningún proveedor de la lista coincide con ese nombre (o coinciden varios).',
    'The invoice also has other charges of {x} (not IVA): check them with the accountant.': 'La factura también trae otros cargos por {x} (no son IVA): revíselos con el contador.',
    'It includes other taxes of {x} that are not IVA: they were left out of the IVA.': 'Incluye otros impuestos por {x} que no son IVA: se dejaron fuera del IVA.',
    'Its total does not add up ({a} + {b} + {c}): check the invoice.': 'Su total no cuadra ({a} + {b} + {c}): revise la factura.',
    'Check the amounts, tick the deliveries on it, then save.': 'Revise los montos, marque las entregas que incluye y guarde.',
    'Accounts payable in the books {a} = open invoices {b} + received not invoiced {c} + expenses on credit {d}':
      'Cuentas por pagar en los libros {a} = facturas pendientes {b} + recibido sin factura {c} + gastos a crédito {d}',
    'Difference {x}: days not posted yet, or entries by hand.': 'Diferencia {x}: días sin asentar todavía, o asientos a mano.',
    'Suppliers need a database update (migration 0016).': 'Proveedores necesita una actualización de la base de datos (migración 0016).',
    'One of those deliveries is of another supplier or already has its invoice. Refresh and try again.': 'Una de esas entregas es de otro proveedor o ya tiene su factura. Actualice e intente de nuevo.',
    'That is more than is owed to this supplier.': 'Eso es más de lo que se le debe a este proveedor.', 'This invoice has payments: void the payments first.': 'Esta factura tiene pagos: anule primero los pagos.',
    'Pick the supplier and write the invoice number and amount.': 'Elija el proveedor y escriba el número y el monto de la factura.',
    'Pick the supplier and write the amount.': 'Elija el proveedor y escriba el monto.', 'Pick what the invoice was for.': 'Elija para qué fue la factura.',
    'Why is this invoice voided?': '¿Por qué se anula esta factura?', 'Why is this payment voided?': '¿Por qué se anula este pago?',
    'Invoice voided': 'Factura anulada', 'Payment voided': 'Pago anulado', 'Invoice saved': 'Factura guardada', 'Payment recorded': 'Pago registrado',

    /* accounting: IVA of the period, inventory valuation, profit by product (0017) */
    'IVA of the period (draft)': 'IVA del período (borrador)', 'Inventory at average cost': 'Inventario a costo promedio', 'Profit by product': 'Rentabilidad por producto',
    'Draft for the accountant, not the return: they review it, apply the proportional credit if it applies, and file it.':
      'Borrador para el contador, no es la declaración: él la revisa, aplica la proporcionalidad del crédito si corresponde y la presenta.',
    'IVA on sales': 'IVA de las ventas', 'Refunds': 'Devoluciones', 'Total IVA on sales': 'Total IVA de las ventas', 'Creditable IVA on purchases': 'IVA acreditable de las compras',
    'Expenses ({n})': 'Gastos ({n})', 'Supplier invoices ({n})': 'Facturas de proveedores ({n})', 'Total creditable IVA': 'Total IVA acreditable',
    'IVA to pay': 'IVA por pagar', 'Credit balance for the next period': 'Saldo a favor para el siguiente período', 'In the books': 'En los libros',
    'IVA payable posted (2110)': 'IVA por pagar asentado (2110)', 'IVA credit posted (1140)': 'IVA crédito fiscal asentado (1140)',
    '{n} closed days not in the books yet: post them so the books match.': '{n} días cerrados todavía sin asentar: asiéntelos para que los libros coincidan.',
    '{n} sales recorded before the IVA update have no IVA detail: {x} (left out of the totals).': '{n} ventas registradas antes de la actualización del IVA no tienen el detalle del IVA: {x} (fuera de los totales).',
    'Purchase documents': 'Documentos de compra', 'Base': 'Base', 'Average cost': 'Costo promedio', 'Below zero': 'Bajo cero',
    'Inventory in the books (1150)': 'Inventario en los libros (1150)',
    'Difference with the books {x}: counts or receipts of days not posted yet, or the opening entry.': 'Diferencia con los libros {x}: conteos o recibos de días sin asentar, o el asiento de apertura.',
    'The books have no days posted yet.': 'Los libros todavía no tienen días asentados.',
    "Sales that stand (not voided or refunded), net of IVA and discounts. Cost: what the stock cost at the moment of each sale. Recipe: today's cost and price.":
      'Ventas firmes (sin anuladas ni devueltas), sin IVA y con descuentos. Costo: lo que costó el inventario en el momento de cada venta. Receta: costo y precio de hoy.',
    'Product': 'Producto', 'Sold, no IVA': 'Vendido, sin IVA', 'Margin': 'Margen', 'Food cost': 'Costo de alimentos', 'Recipe cost': 'Costo de la receta',
    'Margin per unit': 'Margen por unidad', 'No recipe': 'Sin receta',
    'E-invoices': 'Comprobantes', 'Electronic documents': 'Comprobantes electrónicos', 'Receipt': 'Recibo', 'Document': 'Documento', 'Missing': 'Falta',
    'Ticket': 'Tiquete', 'Credit note': 'Nota de crédito', 'Waiting': 'En espera', 'Queued': 'En cola', 'Sent': 'Enviado', 'Accepted': 'Aceptado', 'Rejected': 'Rechazado',
    'Contingency': 'Contingencia', "the sale's document": 'el documento de la venta', 'CABYS: {x}': 'CABYS: {x}',
    'Recording only: each sale and refund records its document here to check the data. Nothing is sent to Hacienda or to any provider.':
      'Solo registro: cada venta y devolución registra aquí su documento para revisar los datos. No se envía nada a Hacienda ni a ningún proveedor.',
    'Off: nothing is recorded or sent. To check the data before choosing a provider, the owner switches on "Record only" in Home → Settings.':
      'Apagado: no se registra ni se envía nada. Para revisar los datos antes de elegir proveedor, el dueño activa "Solo registrar" en Inicio → Ajustes.',
    '{n} products on sale have no CABYS code yet (Admin → Menu).': '{n} productos a la venta todavía no tienen código CABYS (Admin → Menú).',
    'Electronic documents need a database update (migration 0018).': 'Los comprobantes necesitan una actualización de la base de datos (migración 0018).',
    /* accounting: cash (0019) */
    'Cash': 'Efectivo', 'Cash by day': 'Efectivo por día', 'Float': 'Fondo', 'Cash sales': 'Ventas en efectivo', 'Money in': 'Entradas', 'Money out': 'Salidas',
    'Expected': 'Esperado', 'Counted': 'Contado', 'Difference': 'Diferencia', 'not counted': 'sin contar', 'Still open': 'Abierta todavía',
    'Payouts from the register waiting for their invoice': 'Pagos con dinero de la caja que esperan su factura',
    'Money a manager took from the drawer to pay a purchase. File its invoice as an expense or a supplier payment "paid with money taken from the register".':
      'Dinero que un encargado sacó de la gaveta para pagar una compra. Registre su factura como gasto o pago a proveedor "pagado con dinero sacado de la caja".',
    'What for': 'Para qué', 'Who': 'Quién', 'Filed': 'Registrado', 'File its invoice': 'Registrar su factura',
    'Money taken from the register (recorded at the POS)': 'Dinero sacado de la caja (registrado en el POS)', 'Cash from the safe (not the register drawer)': 'Efectivo de la caja fuerte (no de la gaveta)',
    'Which payout': 'Cuál retiro', 'Not recorded at the POS': 'No se registró en el POS', 'Safe': 'Caja fuerte', 'Register payout': 'Retiro de la caja',
    'That payout is not available: refresh and pick it again.': 'Ese retiro no está disponible: actualice y elíjalo de nuevo.',
    'Cash needs a database update (migration 0019).': 'Efectivo necesita una actualización de la base de datos (migración 0019).',
    /* accounting: bank (0020) */
    'Bank accounts': 'Cuentas bancarias', '+ Bank account': '+ Cuenta bancaria', 'Last 4 digits': 'Últimos 4 dígitos', 'Account in the books': 'Cuenta en los libros',
    'No bank accounts yet': 'Todavía no hay cuentas bancarias', 'Import a statement': 'Importar un estado de cuenta',
    "Download the movements from the bank's website as CSV (or Excel saved as CSV) and pick the file. Importing the same movements again adds nothing.":
      'Descargue los movimientos del sitio del banco en CSV (o Excel guardado como CSV) y elija el archivo. Importar los mismos movimientos otra vez no agrega nada.',
    'Statement file (CSV)': 'Archivo del estado de cuenta (CSV)', 'Date column': 'Columna de la fecha', 'Description column': 'Columna de la descripción',
    'Reference column': 'Columna de la referencia', 'Amount column (+ in, − out)': 'Columna del monto (+ entra, − sale)', 'Or: money out column': 'O: columna de lo que sale',
    'and money in column': 'y columna de lo que entra', 'Balance column': 'Columna del saldo', 'Dates are written': 'Las fechas están escritas',
    'day/month/year': 'día/mes/año', 'year-month-day': 'año-mes-día', 'month/day/year': 'mes/día/año', 'Import these movements': 'Importar estos movimientos',
    'Reconcile': 'Conciliar', 'Match automatically': 'Unir automáticamente', 'Movement': 'Movimiento', 'In the books, not on the statement': 'En los libros, no en el estado de cuenta',
    'Entry': 'Asiento', 'None': 'Ninguna', 'Column {n}': 'Columna {n}', 'Post…': 'Asentar…', 'Ignore': 'Ignorar', 'Undo': 'Deshacer', 'Ignored: {x}': 'Ignorado: {x}',
    'Posted': 'Asentado', 'Matched': 'Unido', 'Match: Nº {x}': 'Unir: Nº {x}', 'Why is it left out?': '¿Por qué se deja fuera?', 'Second account (optional)': 'Segunda cuenta (opcional)',
    'Post': 'Asentar', 'The parts must add up to {x}.': 'Las partes deben sumar {x}.', '{n} matched': '{n} unidos', 'Bank account saved': 'Cuenta bancaria guardada',
    'Books {x}': 'Libros {x}', 'statement {x} ({d})': 'estado de cuenta {x} ({d})', 'to reconcile on the statement {x}': 'por conciliar en el estado de cuenta {x}',
    'in the books only {x}': 'solo en los libros {x}', 'That file has no rows.': 'Ese archivo no tiene filas.', '{n} movements': '{n} movimientos',
    '{n} rows left out (titles, totals or blank)': '{n} filas dejadas fuera (títulos, totales o vacías)', 'No movements found: check the columns.': 'No se encontraron movimientos: revise las columnas.',
    'Some rows could not be read: check the date format and the columns.': 'Algunas filas no se pudieron leer: revise el formato de la fecha y las columnas.',
    '{n} new movements · {m} already there': '{n} movimientos nuevos · {m} ya estaban', 'Pick a cash or bank account of the books.': 'Elija una cuenta de caja o bancos de los libros.',
    "Pick the accounts (never the bank's own account).": 'Elija las cuentas (nunca la propia cuenta del banco).',
    'That movement was already reconciled. Refresh.': 'Ese movimiento ya se concilió. Actualice.', 'The amounts are not the same.': 'Los montos no son iguales.',
    'That entry is already matched to another movement.': 'Ese asiento ya está unido a otro movimiento.', "The parts must add up to the bank's amount.": 'Las partes deben sumar el monto del banco.',
    'The bank needs a database update (migration 0020).': 'El banco necesita una actualización de la base de datos (migración 0020).', 'Description': 'Descripción', 'Name': 'Nombre',
    /* insights (0023) */
    'Insights': 'Información', 'Trends month by month, busy hours, what each product leaves, suppliers and what to order soon.':
      'Tendencias mes a mes, horas de más movimiento, lo que deja cada producto, proveedores y qué pedir pronto.',
    'Today': 'Hoy', 'Sales without IVA': 'Ventas sin IVA', 'Same day last week': 'El mismo día la semana pasada', 'To look at': 'Para revisar',
    'Final': 'Final', 'Estimate': 'Estimado', 'Register not opened': 'Caja sin abrir', 'with IVA {x}': 'con IVA {x}', 'average {x}': 'promedio {x}',
    'whole day': 'todo el día', 'up to this time': 'hasta esta hora', '▲ {x} more today': '▲ {x} más hoy', '▼ {x} less today': '▼ {x} menos hoy', 'Nothing': 'Nada',
    '{n} voided ({x})': '{n} anulados ({x})', '{n} not paid yet ({x})': '{n} sin pagar todavía ({x})', 'cash over {x}': 'sobrante de efectivo {x}', 'cash short {x}': 'faltante de efectivo {x}',
    'card terminal differs by {x}': 'el datáfono difiere en {x}',
    "The register is closed: these are the day's final numbers.": 'La caja está cerrada: estos son los números finales del día.',
    'Until the register is closed these numbers can still change (sales on their way from the tablets, bills not paid yet).':
      'Hasta que se cierre la caja estos números aún pueden cambiar (ventas que vienen de las tabletas, cuentas sin pagar).',
    'Last 4 weeks': 'Últimas 4 semanas', 'Last 13 weeks': 'Últimas 13 semanas', 'Month by month': 'Mes a mes', 'See the numbers': 'Ver los números',
    'Food cost': 'Costo de alimentos', 'Prime cost (food + labor)': 'Costo primo (alimentos + mano de obra)', 'Prime cost': 'Costo primo',
    'Average order': 'Pedido promedio', 'Cost of sales': 'Costo de ventas', 'Expenses': 'Gastos', 'Purchases': 'Compras', 'Month': 'Mes',
    'When people buy': 'Cuándo compra la gente', 'Average sales of each weekday and hour, with IVA. Darker is busier.': 'Ventas promedio de cada día de la semana y hora, con IVA. Más oscuro es más movimiento.',
    'Products': 'Productos', 'Categories': 'Categorías', 'Stock to order': 'Inventario por pedir', 'When': 'Cuándo', 'Days left': 'Días restantes', 'Use per day': 'Uso por día',
    'To order': 'Por pedir', "From the use of the last 4 weeks (the last week weighs as much as the month), what is on its way, and the supplier's delivery days.":
      'Según el uso de las últimas 4 semanas (la última semana pesa tanto como el mes), lo que ya viene en camino y los días de entrega del proveedor.',
    'Suppliers': 'Proveedores', 'Received': 'Recibido', 'Deliveries': 'Entregas', 'Days to deliver': 'Días para entregar', 'Owed': 'Se debe', 'Price changes': 'Cambios de precio',
    'Money that leaks': 'Dinero que se escapa', 'Discounts': 'Descuentos', 'Refunded': 'Devuelto', '{n} orders': '{n} pedidos', '{n} sales': '{n} ventas',
    'No sales in these days.': 'No hay ventas en estos días.', 'No purchases in these days.': 'No hay compras en estos días.', 'Nothing needs ordering in the next days.': 'No hace falta pedir nada en los próximos días.',
    'Order now': 'Pedir ya', 'Order within 3 days': 'Pedir en 3 días', 'Fine': 'Bien', 'Not used lately': 'Sin uso reciente',
    'The 12 that left the most.': 'Los 12 que más dejaron.', '{n} with food cost over 35 % (▲).': '{n} con costo de alimentos de más de 35 % (▲).',
    '{n} sold without a recipe: their cost is unknown.': '{n} vendidos sin receta: su costo es desconocido.',
    'Insights need a database update (migration 0023).': 'Información necesita una actualización de la base de datos (migración 0023).',
    'This page is for the owner and managers with access to the sales.': 'Esta página es para el dueño y los encargados con acceso a las ventas.',
    /* the Home subtitle, whole and in its shorter forms, before the generic pattern (a pattern listed earlier wins) */
    'Estimate · without IVA {x} · {y} vs last week': 'Estimado · sin IVA {x} · {y} contra la semana pasada', 'Final · without IVA {x} · {y} vs last week': 'Final · sin IVA {x} · {y} contra la semana pasada',
    'Estimate · without IVA {x}': 'Estimado · sin IVA {x}', 'Final · without IVA {x}': 'Final · sin IVA {x}', '{x} · without IVA {y}': '{x} · sin IVA {y}',
    '▲ {n} % vs last week': '▲ {n} % contra la semana pasada', '▼ {n} % vs last week': '▼ {n} % contra la semana pasada', '{n} late': '{n} tarde',
    'without IVA {x}': 'sin IVA {x}', '{x} on average': '{x} en promedio', 'no sales': 'sin ventas', '{x} without IVA': '{x} sin IVA',
    'Food cost {x}': 'Costo de alimentos {x}', 'Labor {x}': 'Mano de obra {x}', 'Prime cost (food + labor) {x}': 'Costo primo (alimentos + mano de obra) {x}',
    'Below zero: count it': 'Bajo cero: cuéntelo', 'Mon': 'lun', 'Tue': 'mar', 'Wed': 'mié', 'Thu': 'jue', 'Fri': 'vie', 'Sat': 'sáb', 'Sun': 'dom',
    /* security hardening (0025) */
    'This manager may not see the sales of earlier days. Type the receipt number to find one sale, or ask a manager allowed to see sales.':
      'Este encargado no puede ver las ventas de días anteriores. Escriba el número de recibo para encontrar una venta, o pida a un encargado con permiso de ventas.',
    'Turn on the phone code': 'Activar el código del teléfono',
    'The books open only with the code from your phone. Turn it on once; then every sign-in asks for the code.':
      'Los libros solo se abren con el código de su teléfono. Actívelo una vez; después cada ingreso pide el código.',
    'Could not start the phone code. Ask the owner to check that Supabase → Authentication → Multi-Factor → TOTP is on.':
      'No se pudo activar el código del teléfono. Pida al dueño revisar que Supabase → Authentication → Multi-Factor → TOTP esté activo.',
    'Only on your own phone and your own login. Typing this code signs out every other device that uses this login, including café tablets. Continue?':
      'Solo en su propio teléfono y con su propio ingreso. Al escribir este código se cierra la sesión en todos los demás dispositivos que usan este ingreso, incluidas las tabletas del café. ¿Continuar?',
    'Dollar accounts come later: their movements must be valued in colones first.': 'Las cuentas en dólares vienen después: primero hay que valorar sus movimientos en colones.',
    'The hours changed since this payroll was prepared: prepare it again.': 'Las horas cambiaron desde que se preparó esta planilla: prepárela otra vez.',
    'Someone would be paid less than zero: check the deductions.': 'A alguien le quedaría un pago menor que cero: revise las deducciones.',
    "That is the café tablet's login: create a separate login for the accountant.": 'Ese es el ingreso de la tableta del café: cree un ingreso aparte para el contador.',
    'That rate is far from the last one: the owner with the phone code can set it.': 'Ese tipo de cambio está lejos del anterior: el dueño con el código del teléfono puede ponerlo.',
    /* accounting: payroll (0021, 0022) */
    'Pay periods': 'Periodos de pago', '+ Period': '+ Periodo', 'Create': 'Crear', 'Period': 'Periodo', 'No pay periods yet': 'Todavía no hay periodos de pago',
    'Hours of the period': 'Horas del periodo', 'Approve the hours': 'Aprobar las horas', 'Person': 'Persona', 'Shifts': 'Turnos', 'To check': 'Para revisar',
    'Prepare the payroll': 'Preparar la planilla', 'Rate': 'Tarifa', 'Gross': 'Bruto', 'Deductions': 'Deducciones', 'Other deductions': 'Otras deducciones',
    'Employer charges': 'Cargas del patrono', 'Net': 'Neto', 'Mark as reviewed (accountant)': 'Marcar como revisada (contador)', 'Back to draft': 'Volver a borrador',
    'Post to the books': 'Asentar en los libros', 'Pay rates': 'Tarifas de pago', 'Pay': 'Pago', 'Since': 'Desde', 'By the hour': 'Por hora',
    'A fixed amount per pay period': 'Un monto fijo por periodo de pago', 'Deductions and employer charges': 'Deducciones y cargas del patrono', '+ Rule': '+ Regla',
    'None come built in. Each one is entered with who confirmed it (your accountant) and the document. Until then the payroll only works out the gross pay.':
      'No viene ninguna incluida. Cada una se registra con quién la confirmó (su contador) y el documento. Mientras tanto la planilla solo calcula el salario bruto.',
    'Who pays it': 'Quién la paga', 'Confirmed by': 'Confirmado por', 'Taken from the pay': 'Se rebaja del salario', 'Paid by the business on top': 'La paga el negocio aparte',
    'Percent of the gross pay': 'Porcentaje del salario bruto', 'Hours not approved yet': 'Horas sin aprobar', 'Hours approved': 'Horas aprobadas',
    'Reviewed by the accountant': 'Revisada por el contador', '{n} without clock-out': '{n} sin salida', '{n} over 12 h': '{n} de más de 12 h', '{n} overlapping': '{n} que se cruzan',
    '{n} changed by hand': '{n} cambiados a mano',
    'Check the hours (shifts are changed in Time clock with a manager PIN), then the owner approves them. Approved hours can no longer change.':
      'Revise las horas (los turnos se corrigen en Reloj marcador con PIN de encargado); luego el dueño las aprueba. Las horas aprobadas ya no cambian.',
    'The period has not ended yet.': 'El periodo todavía no ha terminado.', 'Approved by {x}: these hours no longer change.': 'Aprobadas por {x}: estas horas ya no cambian.',
    'The payroll is prepared once the owner approves the hours.': 'La planilla se prepara cuando el dueño aprueba las horas.', 'Not prepared yet.': 'Todavía no se ha preparado.',
    'reviewed by {x}': 'revisada por {x}', 'no deductions or charges confirmed: gross pay only': 'sin deducciones ni cargas confirmadas: solo el bruto',
    'No pay rate': 'Sin tarifa', '{x} per hour': '{x} por hora', '{x} per pay period': '{x} por periodo de pago', 'from {d}: {x}': 'desde {d}: {x}',
    'No rules confirmed yet.': 'Todavía no hay reglas confirmadas.', 'Approved: these hours no longer change.': 'Aprobadas: estas horas ya no cambian.',
    'Approve these hours? They can no longer change, unless the owner reopens the period.': '¿Aprobar estas horas? Ya no podrán cambiar, salvo que el dueño reabra el periodo.',
    'Why is the period reopened?': '¿Por qué se reabre el periodo?', 'Post this payroll to the books? It can no longer change.': '¿Asentar esta planilla en los libros? Ya no podrá cambiar.',
    'Period reopened': 'Periodo reabierto', 'Payroll prepared': 'Planilla preparada', 'Reviewed': 'Revisada', 'Payroll posted': 'Planilla asentada',
    'Pay period created': 'Periodo de pago creado', 'Pay rate saved': 'Tarifa guardada', 'Rule saved': 'Regla guardada',
    'That period overlaps another one.': 'Ese periodo se cruza con otro.', 'Some shifts have no clock-out: fix them in Time clock first.': 'Hay turnos sin salida: corríjalos primero en Reloj marcador.',
    'Only the owner approves the hours.': 'Solo el dueño aprueba las horas.', 'The owner approves the hours first.': 'Primero el dueño aprueba las horas.',
    'This payroll is no longer a draft.': 'Esta planilla ya no es un borrador.', 'Only the accountant marks it as reviewed.': 'Solo el contador la marca como revisada.',
    'Someone has no pay rate: set it in Pay rates and prepare the payroll again.': 'Alguien no tiene tarifa: póngala en Tarifas de pago y prepare la planilla otra vez.',
    'Nobody to pay in this period.': 'Nadie a quien pagar en este periodo.', 'The accountant reviews it first.': 'Primero la revisa el contador.', 'Post it first.': 'Primero asiéntela.',
    'Its payroll is already posted: the hours stay.': 'Su planilla ya está asentada: las horas quedan.',
    'A posted payroll used this rate: the change starts after that period.': 'Una planilla asentada usó esta tarifa: el cambio empieza después de ese periodo.',
    'That was already done. Refresh the page.': 'Eso ya se hizo. Actualice la página.',
    'Payroll needs a database update (migrations 0021, 0022).': 'Planilla necesita una actualización de la base de datos (migraciones 0021 y 0022).',
    'Labor cost': 'Costo de mano de obra', 'Labor': 'Mano de obra', 'Labor %': '% mano de obra',
    "An estimate: the hours worked at each person's rate (fixed pay spread over its pay period), against sales without IVA.":
      'Un estimado: las horas trabajadas a la tarifa de cada persona (el pago fijo repartido en su periodo), contra las ventas sin IVA.',
    'Some people worked without a pay rate: set it in Payroll → Pay rates.': 'Algunas personas trabajaron sin tarifa: póngala en Planilla → Tarifas de pago.',
    'That pay period is approved: its hours can no longer change. Ask the owner to reopen it.': 'Ese periodo de pago está aprobado: sus horas ya no pueden cambiar. Pida al dueño que lo reabra.',
    /* accounting: Costa Rican payroll (0026) */
    'Extra pay': 'Pago extra', 'Income tax': 'Impuesto sobre la renta', 'Payslip': 'Colilla', 'Profile': 'Perfil', 'No ID number': 'Sin cédula',
    'tax off': 'renta apagada', 'no tax table': 'sin tabla de renta', 'not confirmed': 'sin confirmar',
    'Pay taken to a month of 30 days, taxed, brought back to the period of {n} days': 'Salario llevado a un mes de 30 días, gravado, devuelto al periodo de {n} días',
    'income tax withholding is on but there is no tax table: enter it in Costa Rican rules, or switch it off': 'la retención de renta está encendida pero no hay tabla: regístrela en Reglas de Costa Rica, o apáguela',
    'income tax withheld': 'con retención de renta', 'aguinaldo provisioned': 'aguinaldo provisionado',
    'Income tax withholding is on but there is no confirmed tax table: enter it in Costa Rican rules, or switch it off in Home → Settings.':
      'La retención de renta está encendida pero no hay una tabla confirmada: regístrela en Reglas de Costa Rica, o apáguela en Inicio → Ajustes.',
    'Not found. Refresh the page.': 'No se encontró. Actualice la página.', 'That setting does not exist.': 'Ese ajuste no existe.',
    'CCSS': 'CCSS', 'INS (occupational risk policy)': 'INS (póliza de riesgos del trabajo)', 'Other': 'Otro',
    'ID number (cédula or DIMEX)': 'Cédula o DIMEX', 'Hired on': 'Fecha de ingreso', 'Last day (if they left)': 'Último día (si ya salió)', 'Contract': 'Contrato',
    'Open-ended': 'Indefinido', 'Fixed term': 'A plazo fijo', 'Children (tax credit)': 'Hijos (crédito de renta)', 'Spouse (tax credit)': 'Cónyuge (crédito de renta)',
    'Save the profile': 'Guardar el perfil', 'Profile saved': 'Perfil guardado',
    'Costa Rican rules: CCSS, INS, income tax, aguinaldo, vacations': 'Reglas de Costa Rica: CCSS, INS, renta, aguinaldo, vacaciones',
    'What is arithmetic (hours × rate, salaries ÷ 12, averages) is always worked out. What the law sets (percentages, the tax table, vacation days, notice and severance) is entered by your accountant with the document, and the owner records the confirmation "payroll_cr_rules" in Home → Settings. Until then everything here is an estimate marked as not confirmed, and nothing is withheld, provisioned or posted.':
      'Lo que es aritmética (horas × tarifa, salarios ÷ 12, promedios) siempre se calcula. Lo que fija la ley (porcentajes, la tabla de renta, los días de vacaciones, preaviso y cesantía) lo registra su contador con el documento, y el dueño anota la confirmación «payroll_cr_rules» en Inicio → Ajustes. Hasta entonces todo esto es un estimado marcado como sin confirmar, y no se retiene, provisiona ni asienta nada.',
    'Confirmation "payroll_cr_rules" recorded': 'Confirmación «payroll_cr_rules» anotada',
    'Confirmation "payroll_cr_rules" not recorded yet (Home → Settings): estimates only; nothing is withheld, provisioned or posted': 'Confirmación «payroll_cr_rules» todavía sin anotar (Inicio → Ajustes): solo estimados; no se retiene, provisiona ni asienta nada',
    'Income tax withholding on': 'Retención de renta encendida', 'Income tax withholding off': 'Retención de renta apagada', 'Aguinaldo provision on': 'Provisión del aguinaldo encendida', 'Aguinaldo provision off': 'Provisión del aguinaldo apagada',
    'Income tax table (monthly brackets)': 'Tabla del impuesto sobre la renta (tramos mensuales)', 'valid from {d}': 'vigente desde {d}',
    'No tax table yet: with the withholding on, the payroll cannot be reviewed until the accountant enters it here (the monthly brackets Hacienda publishes for the year)':
      'Todavía no hay tabla de renta: con la retención encendida, la planilla no se puede revisar hasta que el contador la registre aquí (los tramos mensuales que Hacienda publica para el año)',
    'Up to (₡ a month; empty = no limit)': 'Hasta (₡ al mes; vacío = sin límite)', 'Up to': 'Hasta', 'Percent': 'Porcentaje', 'no limit': 'sin límite', '+ Bracket': '+ Tramo',
    'Credit per child (₡ a month)': 'Crédito por hijo (₡ al mes)', 'Credit for the spouse (₡ a month)': 'Crédito por cónyuge (₡ al mes)', 'Periods shorter than a month': 'Periodos menores que un mes',
    'Take the pay to a month, tax it, bring the tax back to the period': 'Llevar el salario a un mes, gravarlo y devolver el impuesto al periodo', 'Apply the table to the pay as it is': 'Aplicar la tabla al salario tal cual',
    'Confirmed by {x}': 'Confirmado por {x}',
    'Valid from': 'Vigente desde', 'Save the tax table': 'Guardar la tabla de renta', 'Tax table saved': 'Tabla de renta guardada',
    'Vacation days': 'Días de vacaciones', 'Days earned per month worked': 'Días que se ganan por mes trabajado', 'Save the vacation rule': 'Guardar la regla de vacaciones', 'Vacation rule saved': 'Regla de vacaciones guardada',
    'Not confirmed: the law as written, for the estimates': 'Sin confirmar: la ley tal como está escrita, para los estimados',
    'Notice and severance table': 'Tabla de preaviso y cesantía', 'Confirm the table as written': 'Confirmar la tabla tal como está', 'Table confirmed': 'Tabla confirmada',
    'Aguinaldo': 'Aguinaldo', 'Year': 'Año', 'Months': 'Meses', 'Salaries': 'Salarios', 'Provisioned': 'Provisionado', 'Prepare the aguinaldo': 'Preparar el aguinaldo', 'Aguinaldo prepared': 'Aguinaldo preparado',
    'Aguinaldo posted': 'Aguinaldo asentado', 'Post the aguinaldo to the books? It can no longer change.': '¿Asentar el aguinaldo en los libros? Ya no podrá cambiar.',
    'Salaries posted from {a} to {b}, divided by twelve; to be paid by {c}': 'Salarios asentados del {a} al {b}, entre doce; se paga a más tardar el {c}',
    'Not confirmed: an estimate; nothing is posted until the owner records the confirmation': 'Sin confirmar: un estimado; nada se asienta hasta que el dueño anote la confirmación',
    'paid so far {x} in {n} run(s)': 'pagado hasta hoy {x} en {n} corrida(s)',
    'before 30 November it is posted only with a written reason (an advance, someone leaving); the rest comes later as a new run':
      'antes del 30 de noviembre solo se asienta con un motivo escrito (un adelanto, una salida); lo que falte viene después como una corrida nueva',
    'Why is the aguinaldo posted before 30 November? (an advance, someone leaving)': '¿Por qué se asienta el aguinaldo antes del 30 de noviembre? (un adelanto, una salida)',
    'Before 30 November the aguinaldo is posted only with a written reason.': 'Antes del 30 de noviembre el aguinaldo solo se asienta con un motivo escrito.',
    'A pay period of the year has no posted payroll yet: post it first (or prepare the aguinaldo again after).': 'Un periodo de pago del año todavía no tiene planilla asentada: asiéntela primero (o prepare el aguinaldo de nuevo después).',
    '{n} pay period(s) of the year without a posted payroll: their salaries are missing here': '{n} periodo(s) de pago del año sin planilla asentada: sus salarios faltan aquí',
    'Vacations': 'Vacaciones', 'See the balance': 'Ver el saldo', 'Days': 'Días', 'What': 'Qué', 'Days taken': 'Días disfrutados', 'Days paid instead of taken': 'Días pagados en vez de disfrutados', 'Record': 'Registrar',
    'Vacation recorded': 'Vacaciones registradas', 'Record voided': 'Registro anulado', 'Why is this record voided?': '¿Por qué se anula este registro?',
    'Since {d}: {n} months': 'Desde el {d}: {n} meses', 'No start date: set the hire date in the profile': 'Sin fecha de ingreso: póngala en el perfil',
    'earned {n} days ({m} a month)': '{n} días ganados ({m} por mes)', 'taken {n}': '{n} disfrutados', 'remaining {n}': '{n} pendientes',
    'daily pay average {x} (last 50 weeks of posted payrolls)': 'salario diario promedio {x} (últimas 50 semanas de planillas asentadas)', 'value {x}': 'valor {x}',
    'no posted payroll yet for the daily pay average': 'todavía no hay planilla asentada para el salario diario promedio', 'an estimate: rule not confirmed': 'un estimado: regla sin confirmar',
    'Settlement estimate (when someone leaves)': 'Estimado de liquidación (cuando alguien sale)', 'Last day': 'Último día',
    'Dismissal without cause (notice and severance owed)': 'Despido sin causa (con preaviso y cesantía)', 'Dismissal with cause': 'Despido con causa', 'Resignation': 'Renuncia', 'End of a fixed-term contract': 'Fin de un contrato a plazo fijo',
    'Concept': 'Concepto', 'Legal basis': 'Base legal', 'Notice': 'Preaviso', 'Severance': 'Cesantía', 'Proportional aguinaldo': 'Aguinaldo proporcional', 'Unused vacations': 'Vacaciones no disfrutadas', 'Does not apply': 'No aplica',
    'daily pay average of the last six months of posted payrolls {x}': 'salario diario promedio de los últimos seis meses de planillas asentadas {x}',
    'no posted payroll in the last six months: the amounts cannot be worked out': 'sin planillas asentadas en los últimos seis meses: no se pueden calcular los montos',
    'the notice and severance table is the law as written, not confirmed': 'la tabla de preaviso y cesantía es la ley tal como está escrita, sin confirmar',
    'Month for the CCSS and the INS': 'Mes para la CCSS y el INS', 'ID number': 'Cédula', 'Salary': 'Salario', 'CCSS (employee)': 'CCSS (trabajador)', 'CCSS (employer)': 'CCSS (patrono)', 'INS': 'INS', 'Other charges': 'Otras cargas',
    'Payrolls posted whose period ends in the month': 'Planillas asentadas cuyo periodo termina en el mes', '{n} payroll(s) of the month not posted yet': '{n} planilla(s) del mes sin asentar',
    '{n} period(s) without a payroll': '{n} periodo(s) sin planilla', 'no ID number on file (Pay rates → Profile): {x}': 'sin cédula registrada (Tarifas de pago → Perfil): {x}',
    'rules not confirmed: the figures are what the payrolls applied': 'reglas sin confirmar: las cifras son lo que aplicaron las planillas',
    /* who took the money, End my turn clocks out (0027) */
    'End your turn. Also clock out of the time clock?': 'Termina su turno. ¿Marcar también la salida en el reloj?',
    '{x}: clocked out': '{x}: salida marcada', '{x}: turn ended · not clocked out: use the Time clock': '{x}: turno terminado · sin marcar la salida: use el Reloj de marcas',
    'Sales by cashier': 'Ventas por cajero', 'Nobody signed in': 'Nadie con sesión', '{n} sales · {x}': '{n} ventas · {x}',
    'Who took the money: a bill paid later counts for the person who closed it, not who opened it. Sales rung with nobody signed in on the device are listed as such.':
      'Quién cobró: una cuenta pagada después cuenta para quien la cerró, no para quien la abrió. Las ventas hechas sin nadie con sesión en el aparato se listan así.',
    /* review fixes (0028): Home switches and sales tiles, Insights for the accountant, the journal and the cash by day */
    'Income tax withheld from pay': 'Retención de renta en la planilla', 'Aguinaldo provisioned every payroll': 'Aguinaldo provisionado en cada planilla',
    'Insights open only with the code from your phone. Turn it on once in Accounting; then every sign-in asks for the code.':
      'Información se abre solo con el código de su teléfono. Actívelo una vez en Contabilidad; después cada ingreso pide el código.',
    "Labor % and prime cost need the owner's phone code or the accountant login.": 'El % de mano de obra y el costo primo necesitan el código del teléfono del dueño o el ingreso del contador.',
    'undo from its document': 'se deshace desde su documento',
    'This entry came from a document (expense, supplier, bank, payroll, day): undo it from that document.': 'Este asiento vino de un documento (gasto, proveedor, banco, planilla, día): deshágalo desde ese documento.',
    'Only an asset account can be cash or bank.': 'Solo una cuenta de activo puede ser caja o banco.', 'IVA payable (net)': 'IVA por pagar (neto)',
    'register not opened': 'caja sin abrir',
    'Days with sales and no register: {x}. They are posted from the sales alone.': 'Días con ventas y sin caja: {x}. Se asientan solo con las ventas.',
    /* POS: money in or out of the drawer (0019) */
    'Money in or out of the drawer': 'Entrada o salida de dinero de la caja', 'What is it?': '¿Qué es?',
    'Out: deposit at the bank': 'Sale: depósito en el banco', 'Out: paying a purchase or a supplier': 'Sale: pago de una compra o a un proveedor',
    'Out: to petty cash': 'Sale: a caja chica', 'Out: the owner takes it': 'Sale: lo retira el dueño', 'In: change from the bank': 'Entra: cambio traído del banco',
    'In: back from petty cash': 'Entra: devuelto de caja chica', 'In: the owner puts it in': 'Entra: lo pone el dueño', 'Currency': 'Moneda',
    'Colones (₡)': 'Colones (₡)', 'Dollars ($)': 'Dólares ($)', 'What for (keep the receipt)': 'Para qué (guarde el comprobante)', 'Record it': 'Registrar',
    'Deposit at the bank': 'Depósito en el banco', 'Paid a purchase': 'Pago de una compra', 'To petty cash': 'A caja chica', 'The owner took it': 'Lo retiró el dueño',
    'Change from the bank': 'Cambio traído del banco', 'Back from petty cash': 'Devuelto de caja chica', 'The owner put it in': 'Lo puso el dueño',
    'Pick the manager and type the PIN below, then tap Void again.': 'Elija al encargado y escriba el PIN abajo; luego toque Anular otra vez.',
    'Why is it voided?': '¿Por qué se anula?', 'Type the amount.': 'Escriba el monto.', 'Recorded: the drawer expects it': 'Registrado: la caja ya lo cuenta',
    'Write what it is for.': 'Escriba para qué es.', 'Check the amount.': 'Revise el monto.',
    'There is no dollar rate yet: the owner or a manager types it on Home → System settings.': 'Todavía no hay tipo de cambio: el dueño o un encargado lo escribe en Inicio → Ajustes del sistema.',
    'Dollar exchange rate': 'Tipo de cambio del dólar', 'Buy': 'Compra', 'Sell': 'Venta', 'Buy rate': 'Tipo de compra', 'Sell rate': 'Tipo de venta', "Save today's rate": 'Guardar el tipo de hoy',
    "Used by the POS for payments in dollars. Type the bank's rate of the day when the official one has not arrived; it never replaces an official rate.":
      'La caja lo usa para los pagos en dólares. Escriba el tipo del banco del día cuando el oficial no ha llegado; nunca reemplaza un tipo oficial.',
    'No rate yet': 'Todavía sin tipo de cambio', 'typed': 'escrito a mano', 'official': 'oficial', 'old': 'viejo', 'Type the buy and sell rates.': 'Escriba el tipo de compra y el de venta.',
    'The official rate of today is already in: it is used as it is.': 'El tipo oficial de hoy ya está: se usa tal cual.',
    'Check the rates: buy is the lower one, sell the higher one.': 'Revise los tipos: compra es el menor, venta el mayor.',
    'That day is closed: it can no longer be voided.': 'Ese día está cerrado: ya no se puede anular.',
    'Its invoice is already filed: the accountant voids it there.': 'Su factura ya está registrada: el contador la anula allí.',
    'Electronic invoices (Hacienda)': 'Comprobantes electrónicos (Hacienda)', 'Record only, send nothing (to check the data)': 'Solo registrar, sin enviar nada (para revisar los datos)',
    '{n} products on the menu have no recipe yet: their cost is unknown (Inventory → Recipes).': '{n} productos del menú todavía no tienen receta: su costo es desconocido (Inventario → Recetas).',

    /* website: the film */
    '1,400 metres above the sea.': 'A 1 400 metros sobre el mar.', 'Monteverde, Costa Rica': 'Monteverde, Costa Rica',
    'Cool nights ripen the cherry slowly.': 'Las noches frías maduran el fruto despacio.',
    'Picked by hand, only when it turns deep red.': 'Recolectado a mano, solo cuando está rojo intenso.',
    'Locally roasted to perfection.': 'Tostado localmente a la perfección.',
    'And here, ground fresh and poured with care, for you.': 'Y aquí, molido al momento y servido con cariño, para usted.',
    'Monteverde, Costa Rica.': 'Monteverde, Costa Rica.', 'See the menu': 'Ver el menú', 'Skip': 'Saltar', 'Replay': 'Repetir', 'Play the film': 'Ver el video',
    'A quetzal flies from the cloud forest down through the coffee plants to Hanging Garden Café': 'Un quetzal vuela desde el bosque nuboso, baja por los cafetales y llega a Hanging Garden Café',

    /* website: nav + hero */
    'Skip to content': 'Ir al contenido', 'Story': 'Historia', 'Gallery': 'Galería', 'Ask us': 'Pregúntenos',
    'Plan your visit': 'Planee su visita', 'Café · Monteverde': 'Café · Monteverde',
    'Follow the quetzal.': 'Siga al quetzal.', 'Through the coffee harvest.': 'Por la cosecha de café.',
    'Home to the garden.': 'De vuelta al jardín.',
    'Coffee, garden, and cloud. Monteverde, Costa Rica.': 'Café, jardín y nubes. Monteverde, Costa Rica.',
    'Hanging Garden Café · Monteverde, Costa Rica': 'Hanging Garden Café · Monteverde, Costa Rica',

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
    'Hanging Garden continues the story: slow coffee, hanging plants, and a table waiting for you between the clouds.':
      'Hanging Garden continúa la historia: café sin prisa, plantas colgantes y una mesa que lo espera entre las nubes.',
    'Peace. Simplicity. Stewardship. Community.': 'Paz. Sencillez. Cuidado. Comunidad.',
    'The jewel of the cloud forest, and our neighbor.': 'La joya del bosque nuboso, y nuestro vecino.',
    'from Monteverde, for the adventure ahead': 'desde Monteverde, para la aventura que viene',
    'Grown in the clouds': 'Cultivado entre las nubes',
    '100% Costa Rican coffee, locally sourced. Thank you for supporting our community and our forest.':
      'Café 100% costarricense, de productores locales. Gracias por apoyar a nuestra comunidad y a nuestro bosque.',

    /* website: menu (between the two markers: the only entries the menu at the tables uses for dish text) */
    '\u0000menu-start': '',
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
    'Cappuccino Small': 'Capuchino pequeño', 'Cappuccino Large': 'Capuchino grande', 'Cappuchino Large': 'Capuchino grande',
    'Triple Chocolate Croissant': 'Croissant de triple chocolate',
    'Adventure Box · Ham & Cheese or Monteverde': 'Adventure Box · Jamón y queso o Monteverde',
    'Adventure Box · Mano de Piedra or Chicken Pesto': 'Adventure Box · Mano de Piedra o Pollo al pesto',
    'Sandwich + fresh fruit + sweet treat + bottled water + napkin. Pre-order by 8 pm, pickup from 6:30 am.':
      'Sándwich + fruta fresca + algo dulce + agua embotellada + servilleta. Pídala antes de las 8 pm y recójala desde las 6:30 am.',
    '\u0000menu-end': '',
    /* the menu at the tables (m.html, opened by the QR code) */
    'Proudly serving locally grown coffee from El Trapiche Monteverde. Prices in colones; we also take dollars, cards and SINPE Móvil at the counter.':
      'Servimos con orgullo café de El Trapiche Monteverde. Precios en colones; también recibimos dólares, tarjetas y SINPE Móvil en el mostrador.',
    'This is the last menu saved on this phone. It updates by itself when the connection is back.':
      'Este es el último menú guardado en este teléfono. Se actualiza solo cuando vuelva la conexión.',
    'Try again': 'Intentar de nuevo', 'Allergies? Ask our team before you order.': '¿Alergias? Pregunte a nuestro equipo antes de pedir.',
    'Every day 6:00 – 19:00': 'Todos los días 6:00 – 19:00', 'Sections': 'Secciones',
    'The menu · Hanging Garden Café': 'El menú · Hanging Garden Café',
    /* the menu QR code: print page (qr.html) and Menu Manager */
    'Menu QR code': 'Código QR del menú', '← Menu Manager': '← Gestor del menú',
    "Guests scan this code with the phone's camera and the menu opens": 'Los clientes escanean este código con la cámara del teléfono y se abre el menú',
    'The menu behind it is read from the Menu Manager, so prices, new items, photos and sold-out items update by themselves within a minute. The code never changes: print it once.':
      'El menú se lee del Gestor del menú, así que los precios, los productos nuevos, las fotos y los agotados se actualizan solos en menos de un minuto. El código nunca cambia: imprímalo una sola vez.',
    'What to print': 'Qué imprimir', 'Table tent (fold in half)': 'Tarjeta de mesa (doblar a la mitad)', '4 cards per page': '4 tarjetas por hoja',
    '12 stickers per page': '12 calcomanías por hoja', 'Download the QR code (PNG)': 'Descargar el código QR (PNG)', 'For a print shop (SVG, 4 cm)': 'Para una imprenta (SVG, 4 cm)',
    'Print at actual size (100%, no "fit to page") on the paper picked above, on matte paper. Keep the white border around the code, print it dark on light, and test one with a phone before printing many.':
      'Imprima a tamaño real (100 %, sin "ajustar a la página") en el papel elegido arriba, en papel mate. Deje el borde blanco alrededor del código, imprímalo oscuro sobre claro y pruebe uno con un teléfono antes de imprimir muchos.',
    'Paper': 'Papel', 'Letter paper (Carta)': 'Papel carta', 'A4 paper': 'Papel A4',
    'Menu at the tables (QR code)': 'Menú en las mesas (código QR)', 'QR code of the menu': 'Código QR del menú',
    'Guests scan it to see this menu on their phone. Prices, new items, photos and sold-out items show there within a minute. The code never changes: print it once.':
      'Los clientes lo escanean para ver este menú en su teléfono. Los precios, los productos nuevos, las fotos y los agotados aparecen ahí en menos de un minuto. El código nunca cambia: imprímalo una sola vez.',
    'Open the menu': 'Abrir el menú', 'Print table cards': 'Imprimir tarjetas para las mesas',
    'To give each item a Spanish name and description for the QR menu, run supabase/menu-spanish.sql once in Supabase.':
      'Para darle a cada producto un nombre y una descripción en español en el menú QR, ejecute supabase/menu-spanish.sql una vez en Supabase.',
    'Name in Spanish (optional, for the QR menu)': 'Nombre en español (opcional, para el menú QR)', 'Description in Spanish (optional)': 'Descripción en español (opcional)',
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
    'Ask a question': 'Hacer una pregunta', 'Garden Guide': 'Guía del Jardín', 'Hanging Garden · English y español': 'Hanging Garden · español e inglés',
    'Ask the Garden Guide a question': 'Hacer una pregunta a la Guía del Jardín', 'Garden Guide chat': 'Chat de la Guía del Jardín',
    'Close chat': 'Cerrar el chat', 'Your question': 'Su pregunta', 'Send': 'Enviar',
    'What are your hours?': '¿Cuál es el horario?', 'How to find us': 'Cómo llegar', 'How do I get there?': '¿Cómo llego?',
    'How can I contact you?': '¿Cómo los contacto?', 'What is the Adventure Box?': '¿Qué es la Adventure Box?',
    'Weather': 'Clima', 'What is the weather like?': '¿Cómo está el clima?', 'Quetzals': 'Quetzales', 'Where can I see a quetzal?': '¿Dónde puedo ver un quetzal?',
    '· Monteverde, Costa Rica': '· Monteverde, Costa Rica',
    '100% Costa Rican coffee · Locally sourced · Proudly serving coffee from El Trapiche Monteverde': 'Café 100% costarricense · De productores locales · Servimos con orgullo café de El Trapiche Monteverde',
    'Thank you for supporting our community and our forest. Pura vida.': 'Gracias por apoyar a nuestra comunidad y a nuestro bosque. Pura vida.',
    'Gallery imagery is AI generated for now and will be replaced with photos of the real café. Website by Hanging Garden.':
      'Las imágenes de la galería son generadas con IA por ahora y se cambiarán por fotos del café real. Sitio web de Hanging Garden.',
    'A resplendent quetzal perched on a mossy branch in the Monteverde cloud forest': 'Un quetzal posado en una rama con musgo en el bosque nuboso de Monteverde',
    'The Monteverde cloud forest': 'El bosque nuboso de Monteverde', 'Coffee served at the garden': 'Café servido en el jardín',
    'Fresh pastries': 'Repostería fresca', 'Coffee pouring': 'Café sirviéndose', 'Garden seating among hanging plants': 'Mesas del jardín entre plantas colgantes',
    'Map of Hanging Garden Café, Monteverde': 'Mapa de Hanging Garden Café, Monteverde',

    /* owner home */
    'Owner dashboard · Monteverde, Costa Rica': 'Panel del propietario · Monteverde, Costa Rica', 'Owner dashboard · Monteverde': 'Panel del propietario · Monteverde',
    'Home · Hanging Garden': 'Inicio · Hanging Garden', 'Revenue today': 'Ingresos de hoy', 'Orders today': 'Pedidos de hoy',
    'On the clock': 'En turno', 'Sold out': 'Agotado', 'Nobody in': 'Nadie en turno',
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
    'Menu Manager · Hanging Garden': 'Gestor del menú · Hanging Garden',
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
    /* menu manager with price_mode 'exclusive' (0009): the editor and the new-item prompt ask for the price before IVA
       and show the final price that is stored */
    'Price before IVA (numbers only)': 'Precio sin IVA (solo números)', 'Price before IVA (numbers only):': 'Precio sin IVA (solo números):',
    '= {x} with IVA': '= {x} con IVA',

    /* POS */
    'Hanging Garden POS': 'Caja Hanging Garden', 'POS · Hanging Garden': 'Caja · Hanging Garden',
    'Time': 'Reloj', 'Orders': 'Pedidos', 'Loading the menu…': 'Cargando el menú…', 'Order': 'Pedido', 'Tap items to add them.': 'Toque los productos para agregarlos.',
    'Includes IVA 13%': 'Incluye IVA 13%', 'Total': 'Total', 'Cash ₡': 'Efectivo ₡', 'Cash $': 'Efectivo $', 'Card': 'Tarjeta', 'SINPE': 'SINPE', 'Other': 'Otro',
    'Clear order': 'Vaciar pedido', 'Print receipt': 'Imprimir recibo',
    'Today at the counter': 'Hoy en el mostrador', 'Cash counted:': 'Efectivo contado:',
    "Today's orders": 'Pedidos de hoy',
    "Voiding an order needs a manager's PIN and a reason. The order stays on record, marked as voided, and the approval is logged.": 'Anular un pedido necesita el PIN de un encargado y un motivo. El pedido queda registrado como anulado y la aprobación se guarda en la bitácora.',
    'Void this order': 'Anular este pedido', 'Which number stand?': '¿Qué número de mesa?',
    'Tap the number you are handing to the customer. Greyed numbers are in use.': 'Toque el número que le entrega al cliente. Los números en gris están en uso.',
    'No number': 'Sin número', 'Paid and picked up': 'Pagado y entregado', 'Paid & picked up': 'Pagado y entregado', 'Picked up': 'Entregado',
    'e.g. rang up twice': 'ej. se cobró dos veces',
    'No connection and no saved menu yet. Connect once and it will work offline after that.': 'Sin conexión y sin menú guardado todavía. Conéctese una vez y después funcionará sin conexión.',
    'your best sellers, updated from Sales · set Always or Never per item in the Menu Manager': 'sus productos más vendidos, según Ventas · marque Siempre o Nunca por producto en el Gestor del menú',
    'One less': 'Uno menos', 'One more': 'Uno más', '{n} item ·': '{n} producto ·', '{n} items ·': '{n} productos ·',
    'The order is empty.': 'El pedido está vacío.', '· number {n}': '· número {n}', 'Paid by {x}': 'Pagado con {x}', 'offline · {n} on this device': 'sin conexión · {n} en este dispositivo',
    /* the register: open with the float, close against the card terminal and the drawer */
    'Open the register': 'Abrir caja', 'Close the register': 'Cerrar caja', 'Who is opening': 'Quién abre', 'Who is closing': 'Quién cierra',
    'Cash float received (₡)': 'Fondo de caja recibido (₡)', 'Card terminal total for today (₡)': 'Total del datáfono de hoy (₡)',
    'Cash in the drawer, float included (₡)': 'Efectivo en la caja, con el fondo incluido (₡)', 'Notes (optional)': 'Notas (opcional)',
    'e.g. ₡2 000 short, tip jar': 'ej. faltan ₡2 000, propinas', 'No team members yet': 'Todavía no hay personal',
    'The register has not been opened today.': 'La caja no se ha abierto hoy.',
    'Opened at {t} by {n} · float {f}': 'Abierta a las {t} por {n} · fondo {f}', 'Closed at {t} by {n}': 'Cerrada a las {t} por {n}',
    'Expected in the drawer (float + cash)': 'Debe haber en la caja (fondo + efectivo)', 'Float': 'Fondo', 'Cash sales': 'Ventas en efectivo',
    'Expected cash': 'Efectivo esperado', 'Cash counted': 'Efectivo contado', 'Cash difference': 'Diferencia en efectivo',
    'Card sales': 'Ventas con tarjeta', 'Card terminal': 'Datáfono', 'Card difference': 'Diferencia en tarjeta', 'SINPE (check the phone)': 'SINPE (revise el teléfono)',
    'exact': 'exacto', '+{x} over': '+{x} sobra', '−{x} short': '−{x} falta', 'Card sales {a} ·': 'Ventas con tarjeta {a} ·', 'Expected {a} ·': 'Esperado {a} ·', 'Day': 'Día', 'still open': 'todavía abierta',
    'Close again (late sale)': 'Cerrar de nuevo (venta tardía)', 'Register closed again': 'Caja cerrada de nuevo',
    'The register of {d} is still open. Close it first.': 'La caja del {d} sigue abierta. Ciérrela primero.', 'Close the register of the previous day first.': 'Primero cierre la caja del día anterior.',
    'The sales of that day are added up when you close it. Then open today.': 'Las ventas de ese día se suman al cerrarla. Después abra la de hoy.',
    'Pick who is opening or closing. If the list is empty, add the team in the Time clock first.': 'Elija quién abre o cierra. Si la lista está vacía, agregue al equipo en el Reloj de marcas primero.',
    'Could not check the register. Check the connection and try again.': 'No se pudo revisar la caja. Revise la conexión e intente de nuevo.',
    'Could not load the team. Reopen Today to try again.': 'No se pudo cargar el equipo. Vuelva a abrir Hoy para intentar de nuevo.',
    'Register opened': 'Caja abierta', 'Register closed': 'Caja cerrada',
    '{n} sales are waiting to sync. Connect to the internet before closing.': '{n} ventas esperan sincronizarse. Conéctese a internet antes de cerrar.',
    'Sales rung up after closing are not in this count.': 'Las ventas hechas después del cierre no están en este conteo.',
    'The register was already opened today.': 'La caja ya se abrió hoy.', 'The register is already closed for today.': 'La caja ya está cerrada por hoy.',
    'Open the register first.': 'Primero abra la caja.', 'Type both amounts.': 'Escriba los dos montos.', 'Type the float received.': 'Escriba el fondo recibido.',
    'Run supabase/register.sql in Supabase to open and close the register here.': 'Ejecute supabase/register.sql en Supabase para abrir y cerrar la caja desde aquí.',
    'Register closings': 'Cierres de caja', 'Opened by': 'Abrió', 'Closed by': 'Cerró', 'Expected': 'Esperado', 'Counted': 'Contado', 'Cash ±': 'Efectivo ±', 'Card ±': 'Tarjeta ±', 'Terminal': 'Datáfono',
    'Float handed over in the morning, cash and card terminal typed at closing, and the differences against what the POS recorded.': 'Fondo entregado en la mañana, efectivo y datáfono escritos al cierre, y las diferencias contra lo que registró la caja.',
    'No closings in this period yet.': 'Todavía no hay cierres en este periodo.',
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
    'Sales · Hanging Garden': 'Ventas · Hanging Garden', 'Lock now': 'Bloquear ahora', 'Sales are locked': 'Las ventas están bloqueadas',
    'Type a manager PIN to open the reports for 15 minutes. Every opening is written to the approvals log.': 'Escriba un PIN de encargado para abrir los reportes por 15 minutos. Cada apertura se anota en la bitácora de aprobaciones.',
    'Open the sales reports': 'Abrir los reportes de ventas', 'Revenue': 'Ingresos', 'Average order': 'Pedido promedio', 'Revenue by day': 'Ingresos por día',
    'How people paid': 'Cómo pagaron', 'Best sellers': 'Más vendidos', 'Transactions': 'Transacciones', 'When': 'Cuándo', 'Items': 'Productos',
    'Revenue by day bar chart': 'Gráfico de barras de ingresos por día', 'Pick the manager.': 'Elija al encargado.',
    'This manager may not open the sales reports. The owner can allow it in the Time clock, Team section.': 'Este encargado no puede abrir los reportes de ventas. El propietario puede permitirlo en el Reloj de marcas, sección Equipo.',
    'Could not check the PIN. Check the connection.': 'No se pudo verificar el PIN. Revise la conexión.', 'Could not open the reports.': 'No se pudieron abrir los reportes.',
    'Nothing in this period yet.': 'Todavía no hay nada en este periodo.', '{n} sold ·': '{n} vendidos ·',
    'No sales in this period yet. Ring one up on the POS and refresh.': 'Todavía no hay ventas en este periodo. Cobre una en la caja y actualice.',

    /* time clock */
    /* access: start from zero, keypad, PIN confirmation, forgot password */
    'Start here: set up the team': 'Empiece aquí: arme el equipo',
    'There is no manager yet. Three steps and the clock is ready:': 'Todavía no hay encargado. Tres pasos y el reloj queda listo:',
    'Add the first manager (GM) with a name and a PIN. No approval is needed for this one.': 'Agregue al primer encargado (GM) con nombre y PIN. Para este no se necesita aprobación.',
    'Add each team member with their own PIN, under Hours & team.': 'Agregue a cada miembro del equipo con su propio PIN, en Horas y equipo.',
    'To clock in, each person taps their name and types their PIN on the keypad.': 'Para marcar, cada persona toca su nombre y escribe su PIN en el teclado.',
    'Forgot a PIN later? The owner login changes any PIN from Hours & team, no other PIN needed.': '¿Se olvida un PIN después? El ingreso del propietario cambia cualquier PIN desde Horas y equipo, sin pedir otro PIN.',
    'Add the first manager': 'Agregar al primer encargado', 'Keypad': 'Teclado', 'Delete the last digit': 'Borrar el último dígito',
    'Type the new PIN.': 'Escriba el PIN nuevo.', '{n} clocked in at {t}': '{n} marcó entrada a las {t}', '{n} clocked out · {t} this shift': '{n} marcó salida · {t} en este turno',
    '{n} is now the manager': '{n} ahora es el encargado', '{n} saved': '{n} guardado',
    'Type the PIN again': 'Escriba el PIN otra vez', 'Numbers only. Not 1234, 0000 or a birthday everyone knows.': 'Solo números. No 1234, 0000 ni un cumpleaños que todos conozcan.',
    'Manager / GM (approves changes with their PIN)': 'Encargado / GM (aprueba cambios con su PIN)',
    'Owner login: saved directly and written to the approvals log.': 'Ingreso del propietario: se guarda directo y queda en la bitácora de aprobaciones.',
    'That PIN is too easy to guess (like 1234 or 0000). Pick another.': 'Ese PIN es muy fácil de adivinar (como 1234 o 0000). Elija otro.',
    'Pick the person.': 'Elija a la persona.', 'The two PINs do not match.': 'Los dos PIN no coinciden.',
    'Approve with a manager PIN, or run supabase/access.sql once so the owner login does not need one.': 'Apruebe con el PIN de un encargado, o ejecute supabase/access.sql una vez para que el ingreso del propietario no lo necesite.',
    'Reset PIN': 'Nuevo PIN', 'New PIN · {n}': 'Nuevo PIN · {n}', 'New PIN (4–8 digits)': 'Nuevo PIN (4 a 8 dígitos)',
    'Forgot your password?': '¿Olvidó su contraseña?', 'Email of the login:': 'Correo del ingreso:',
    'If that email has a login, a link to set a new password is on its way. Check the spam folder too.': 'Si ese correo tiene un ingreso, ya va en camino un enlace para poner una contraseña nueva. Revise también el correo no deseado.',
    'Could not send the email. Check the address and try again.': 'No se pudo enviar el correo. Revise la dirección e intente de nuevo.',
    'Set a new password': 'Poner una contraseña nueva', 'New password · Hanging Garden': 'Contraseña nueva · Hanging Garden', 'Checking the link…': 'Revisando el enlace…',
    'New password': 'Contraseña nueva', 'Type it again': 'Escríbala otra vez',
    "At least 8 characters. Use something you can remember, or save it in your phone's password manager.": 'Al menos 8 caracteres. Use algo que recuerde, o guárdela en el gestor de contraseñas del teléfono.',
    'Save the new password': 'Guardar la contraseña nueva', 'At least 8 characters.': 'Al menos 8 caracteres.', 'The two passwords do not match.': 'Las dos contraseñas no coinciden.',
    'That is the same password as before. Pick a new one.': 'Es la misma contraseña de antes. Elija una nueva.',
    'Could not save the password. Ask for a new link and try again.': 'No se pudo guardar la contraseña. Pida un enlace nuevo e intente otra vez.',
    'Password changed. You can sign in now.': 'Contraseña cambiada. Ya puede ingresar.', 'Go to Home': 'Ir al inicio',
    'This link has expired or was already used. Ask for a new one from the sign-in page.': 'Este enlace venció o ya se usó. Pida uno nuevo desde la página de ingreso.',
    'Back to sign in': 'Volver al ingreso',
    'A link was already sent. Wait a minute and check the spam folder.': 'Ya se envió un enlace. Espere un minuto y revise el correo no deseado.',
    'Your login has a phone code. Type it to continue.': 'Su ingreso tiene código del teléfono. Escríbalo para continuar.',
    'If you no longer have the phone, the owner must first remove the phone code in Supabase (owner_reset_phone_code).': 'Si ya no tiene el teléfono, el propietario debe quitar primero el código del teléfono en Supabase (owner_reset_phone_code).',
    'Type the code from your phone app first.': 'Primero escriba el código de la app de su teléfono.',
    'That password is too easy to guess. Use at least 8 characters and mix letters and numbers.': 'Esa contraseña es muy fácil de adivinar. Use al menos 8 caracteres y mezcle letras y números.',
    'That password is too long. Use 72 characters or fewer.': 'Esa contraseña es muy larga. Use 72 caracteres o menos.',
    'Open this page from the link in the email. If the link opened a different address, the Supabase Site URL must be set to hanginggardencafe.com.': 'Abra esta página desde el enlace del correo. Si el enlace abrió otra dirección, el Site URL de Supabase debe ser hanginggardencafe.com.',
    'Could not reach the server. Check your connection and reload this page.': 'No se pudo conectar con el servidor. Revise su conexión y recargue esta página.', 'Reload': 'Recargar',
    'Time clock · Hanging Garden': 'Reloj de marcas · Hanging Garden', 'One-time setup needed': 'Falta una configuración inicial',
    'The time clock needs its tables and the manager-approval functions in Supabase. It takes about a minute:': 'El reloj de marcas necesita sus tablas y las funciones de aprobación en Supabase. Toma como un minuto:',
    'Open your Supabase project →': 'Abra su proyecto de Supabase →', 'SQL Editor': 'SQL Editor', 'New query': 'New query', 'Paste and run': 'Pegue y ejecute',
    ', then paste and run': ', luego pegue y ejecute', 'Come back here, reload, and make yourself the first manager under': 'Vuelva aquí, recargue y hágase el primer encargado en',
    'Hours & team': 'Horas y equipo', 'Clock in · out': 'Entrada · salida',
    "Tap your name, type your PIN. Green means you're on the clock.": 'Toque su nombre y escriba su PIN. Verde significa que está en turno.',
    "Shifts count on the day they start. Weeks run Monday to Sunday. Any change to a shift needs a manager's PIN and is written to the approvals log.": 'Los turnos cuentan el día en que empiezan. Las semanas van de lunes a domingo. Cualquier cambio a un turno necesita el PIN de un encargado y se anota en la bitácora.',
    'No manager yet. The first person you save becomes the manager (no approval needed this one time). Do this now.': 'Todavía no hay encargado. La primera persona que guarde será el encargado (sin aprobación esta única vez). Hágalo ahora.',
    '+ Add person': '+ Agregar persona', 'Approvals log': 'Bitácora de aprobaciones',
    'Every shift change, team change and voided order, with who approved it and why.': 'Cada cambio de turno, cambio de equipo y pedido anulado, con quién lo aprobó y por qué.',
    'Every shift change, team change, voided order and discount, with who approved it and why.': 'Cada cambio de turno, cambio de equipo, pedido anulado y descuento, con quién lo aprobó y por qué.',
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
    'In since {t}': 'En turno desde {t}', 'Forgot to clock out? Fix it in Hours.': '¿Olvidó marcar la salida? Corríjalo en Horas.',
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
    'Kitchen · Hanging Garden': 'Cocina · Hanging Garden', 'One step before the kitchen screen works': 'Falta un paso para que funcione la pantalla de cocina',
    'Run': 'Ejecute', 'once in Supabase (SQL Editor → New query → paste → Run), then reload this page.': 'una vez en Supabase (SQL Editor → New query → pegar → Run) y recargue esta página.',
    'Hanging Garden · tickets appear here as they come in': 'Hanging Garden · las comandas aparecen aquí al llegar',
    'Sound: on': 'Sonido: activado', 'Sound: off': 'Sonido: apagado', 'Nothing to prepare right now.': 'Nada que preparar por ahora.',
    'Ready, waiting for pickup': 'Listos, esperando entrega', 'Front counter': 'Mostrador', 'Start': 'Empezar', 'Done': 'Listo',

    /* TV board */
    'Menu Board · Hanging Garden': 'Pantalla del menú · Hanging Garden', 'Monteverde, Costa Rica · made for the cloud forest': 'Monteverde, Costa Rica · hecho para el bosque nuboso',
    'Pura vida': 'Pura vida', 'The menu board lost its connection.': 'La pantalla del menú perdió la conexión.', 'It will keep trying by itself.': 'Seguirá intentando por su cuenta.',

    /* small words and lines the pages build on the fly */
    'everything is available': 'todo está disponible', 'on': 'activado', 'off': 'apagado',
    'Your café, one tap away': 'Su café, a un toque', 'Hanging Garden Café emblem': 'Emblema de Hanging Garden Café',
    'Good question, and I want to get it right. I saved it for the café team. Meanwhile, ask at the counter when you visit, or try one of the buttons below.':
      'Buena pregunta, y quiero responderla bien. La guardé para el equipo del café. Mientras tanto, pregunte en el mostrador cuando nos visite, o pruebe uno de los botones de abajo.',
    'and closes': 'y cierra', 'Open': 'Abrir', 'Available': 'Disponible', 'none': 'ninguno',
    'Out': 'Fuera', '{t} today': '{t} hoy', '{n} shift': '{n} turno', '{n} shifts': '{n} turnos',
    'online': 'en línea', 'offline': 'sin conexión', '{n} items': '{n} productos', '{n} item': '{n} producto',
    'updated {x}': 'actualizó a {x}', 'added {x}': 'agregó a {x}', 'opened the sales reports': 'abrió los reportes de ventas',
    'voided order {x}': 'anuló el pedido {x}', 'changed shift {x}': 'cambió el turno {x}', 'added shift {x}': 'agregó el turno {x}',
    'deleted shift {x}': 'eliminó el turno {x}', 'sales access on for {x}': 'acceso a ventas activado para {x}', 'sales access off for {x}': 'acceso a ventas desactivado para {x}',

    /* inventory */
    'Inventory': 'Inventario', 'Inventory · Hanging Garden': 'Inventario · Hanging Garden', 'Inventory · Monteverde, Costa Rica': 'Inventario · Monteverde, Costa Rica',
    'What you have, what you sell, what to order': 'Lo que tiene, lo que vende, lo que hay que pedir',
    'One step before the inventory works': 'Falta un paso para que funcione el inventario',
    'Inventory is locked': 'El inventario está bloqueado',
    'Type a manager PIN to open the inventory for 15 minutes. Every opening is written to the approvals log.': 'Escriba un PIN de encargado para abrir el inventario por 15 minutos. Cada apertura se anota en la bitácora de aprobaciones.',
    'Open the inventory': 'Abrir el inventario', 'Open inventory': 'Abrir inventario', 'Could not open the inventory.': 'No se pudo abrir el inventario.',
    'Could not load the inventory. Check the connection.': 'No se pudo cargar el inventario. Revise la conexión.',
    'The inventory is locked. Type a manager PIN again.': 'El inventario está bloqueado. Escriba de nuevo un PIN de encargado.',
    'What is on the shelf, what each sale uses, and what to order before it runs out.': 'Lo que hay en el estante, lo que usa cada venta y lo que hay que pedir antes de que se acabe.',
    'Stock': 'Existencias', 'Recipes': 'Recetas', 'Vendors': 'Proveedores', 'History': 'Historial', 'By month': 'Por mes',
    'Items tracked': 'Productos controlados', 'Need attention': 'Requieren atención', 'Expiring soon': 'Por vencer', 'within 3 days': 'en 3 días',
    'Stock value': 'Valor en existencias', 'at last purchase cost': 'al último costo de compra', 'Before it runs out': 'Antes de que se acabe',
    'Build the order': 'Armar el pedido', 'Ingredients used': 'Ingredientes usados', 'Waste': 'Merma', 'all good': 'todo bien',
    '{n} out · {m} low · {k} running out': '{n} agotados · {m} bajos · {k} por acabarse', '{n} vendors': '{n} proveedores',
    '{p}% of sales': '{p}% de las ventas', '{p}% of what was used': '{p}% de lo usado', '{p}% of the price': '{p}% del precio',
    'Ingredient cost follows the recipes: link each menu item to what it uses in the Recipes tab and this becomes your real food cost.': 'El costo de ingredientes sigue las recetas: enlace cada producto del menú con lo que usa en la pestaña Recetas y esto será su costo real de comida.',
    'Nothing is running out. Enjoy the calm.': 'Nada se está acabando. Disfrute la calma.',
    '{q} on hand': '{q} en existencia', '{q} on hand · about {n} days left': '{q} en existencia · unos {n} días', '{q} on hand · about {n} days left · {v}': '{q} en existencia · unos {n} días · {v}', '{q} on hand · {v}': '{q} en existencia · {v}',
    'about {n} days left': 'unos {n} días', 'Out of stock': 'Agotado', 'Low': 'Bajo', 'Running out': 'Por acabarse', 'OK': 'Bien', 'Expiring': 'Por vencer', 'Expires {d}': 'Vence {d}',
    '+ Add item': '+ Agregar producto', 'Add item': 'Agregar producto', 'Search…': 'Buscar…', 'All categories': 'Todas las categorías', 'Everything': 'Todo',
    'Needs attention': 'Requiere atención', 'Inactive items': 'Productos inactivos', 'Item': 'Producto', 'On hand': 'En existencia', 'Par · reorder': 'Par · reorden',
    'Use / day': 'Uso / día', 'Days left': 'Días restantes', 'Vendor': 'Proveedor', 'Value': 'Valor',
    'No items yet. Tap + Add item, or start with the coffee, milk and pastries you buy every week.': 'Todavía no hay productos. Toque + Agregar producto, o empiece con el café, la leche y la repostería que compra cada semana.',
    'Suggested order': 'Pedido sugerido', "based on the last 30 days of sales and each vendor's lead time": 'según los últimos 30 días de ventas y el plazo de entrega de cada proveedor',
    '+ Blank order': '+ Pedido en blanco', 'Received orders': 'Pedidos recibidos', 'What each menu item uses': 'Lo que usa cada producto del menú',
    'Link same-name items': 'Enlazar por nombre', 'Pick a menu item, then list what goes out of stock each time it sells. A croissant you buy ready-made is simply 1 croissant. A latte is grams of coffee and millilitres of milk. Sales then take stock out by themselves.':
      'Elija un producto del menú y anote lo que sale de existencias cada vez que se vende. Un croissant que compra ya hecho es simplemente 1 croissant. Un latte son gramos de café y mililitros de leche. Las ventas descuentan las existencias solas.',
    'Recipe': 'Receta', '+ Ingredient': '+ Ingrediente', 'Save recipe': 'Guardar receta', 'Recipe saved': 'Receta guardada', 'Could not save the recipe. Try again.': 'No se pudo guardar la receta. Intente de nuevo.',
    'Could not link. Try again.': 'No se pudo enlazar. Intente de nuevo.', '{n} linked': '{n} enlazados', 'not linked': 'sin enlazar', '{n} ingredient': '{n} ingrediente', '{n} ingredients': '{n} ingredientes',
    'Pick a stock item': 'Elija un producto de existencias', 'Remove': 'Quitar', 'Ingredients {c} per sale': 'Ingredientes {c} por venta', 'Ingredients {c} per sale · {p}% of the price': 'Ingredientes {c} por venta · {p}% del precio',
    '+ Add vendor': '+ Agregar proveedor', 'Add vendor': 'Agregar proveedor', 'Contact': 'Contacto', 'Orders on': 'Pide los', 'Lead days': 'Días de entrega', 'Items': 'Productos',
    'No vendors yet. Add the people you buy from, with their WhatsApp, and orders go out in one tap.': 'Todavía no hay proveedores. Agregue a quienes les compra, con su WhatsApp, y los pedidos salen con un toque.',
    'Contact person': 'Persona de contacto', 'Phone': 'Teléfono', 'WhatsApp (with country code)': 'WhatsApp (con código de país)', 'Lead days (order to delivery)': 'Días de entrega (del pedido a la entrega)',
    'Takes orders on': 'Recibe pedidos los', 'Active': 'Activo', 'Delete vendor': 'Eliminar proveedor', 'Vendor deleted': 'Proveedor eliminado', 'inactive': 'inactivo',
    'Delete "{x}"? Its items stay, without a vendor.': '¿Eliminar "{x}"? Sus productos se quedan, sin proveedor.',
    'Every movement': 'Cada movimiento', 'All items': 'Todos los productos', 'All kinds': 'Todos los tipos', 'Received': 'Recibido', 'Sold': 'Vendido', 'Returned (void)': 'Devuelto (anulación)',
    'Returned': 'Devuelto', 'Count adjustments': 'Ajustes de conteo', 'Adjustment': 'Ajuste', 'Kind': 'Tipo', 'Qty': 'Cant.', 'Unit cost': 'Costo unitario', 'Note': 'Nota', 'By': 'Por', 'Nothing yet.': 'Todavía nada.',
    'per pack': 'por paquete', 'expires {d}': 'vence {d}',
    'What came in, what went out through sales, what was wasted, and what is on the shelf right now.': 'Lo que entró, lo que salió por ventas, lo que se desperdició y lo que hay en el estante ahora.',
    'Ordered': 'Pedido', 'Cost': 'Costo', 'Count adj.': 'Ajuste conteo', 'In stock now': 'En existencia ahora', 'Total spent': 'Total gastado', 'Nothing in this month.': 'Nada en este mes.',
    'Previous month': 'Mes anterior', 'Next month': 'Mes siguiente',
    'Category': 'Categoría', 'Dairy': 'Lácteos', 'Bakery': 'Panadería', 'Sandwich': 'Sándwich', 'Produce': 'Frutas y verduras', 'Drinks': 'Bebidas', 'Packaging': 'Empaques', 'Cleaning': 'Limpieza',
    'Counted in': 'Se cuenta en', 'units': 'unidades', 'grams': 'gramos', 'kilograms': 'kilogramos', 'millilitres': 'mililitros', 'litres': 'litros',
    'What you buy': 'Lo que compra', 'Units per pack': 'Unidades por paquete', 'Cost per pack (₡)': 'Costo por paquete (₡)', 'No vendor': 'Sin proveedor', 'No vendor set': 'Sin proveedor asignado',
    'Par level (target after an order)': 'Nivel par (meta después de un pedido)', 'Reorder point (alert at)': 'Punto de reorden (alerta en)', 'Shelf life (days, optional)': 'Vida útil (días, opcional)',
    'Starting stock (new items)': 'Existencia inicial (productos nuevos)', 'Notes': 'Notas', 'Active (counted and ordered)': 'Activo (se cuenta y se pide)', 'Delete item': 'Eliminar producto', 'Item deleted': 'Producto eliminado',
    'Delete "{x}" and its history? If you only stopped buying it, untick Active instead.': '¿Eliminar "{x}" y su historial? Si solo dejó de comprarlo, mejor desmarque Activo.',
    'e.g. Whole milk': 'ej. Leche entera', 'e.g. bottle 1 L': 'ej. botella 1 L', 'e.g. Mon, Thu': 'ej. lun, jue', 'starting stock': 'existencia inicial',
    'Count': 'Contar', 'Receive': 'Recibir', 'Count · {x}': 'Contar · {x}', 'Receive · {x}': 'Recibir · {x}', 'Waste · {x}': 'Merma · {x}', 'Counted now': 'Contado ahora',
    'On the books: {q}. Type what you actually see; the difference is logged.': 'En los libros: {q}. Escriba lo que ve en realidad; la diferencia queda anotada.',
    'Add what just arrived. Packs or units, either one.': 'Agregue lo que acaba de llegar. Paquetes o unidades, cualquiera de los dos.',
    'Add what just arrived. Packs or units, either one. One pack = {x}.': 'Agregue lo que acaba de llegar. Paquetes o unidades, cualquiera de los dos. Un paquete = {x}.',
    'Take out what was thrown away, spilled or expired.': 'Descuente lo que se botó, se derramó o se venció.', 'Packs': 'Paquetes', 'Units': 'Unidades', 'Expires on': 'Vence el', 'Expires': 'Vence',
    'optional': 'opcional', 'Type the quantity you counted.': 'Escriba la cantidad que contó.', 'Type a quantity above zero.': 'Escriba una cantidad mayor que cero.',
    '{x} counted': '{x} contado', '{x} received': '{x} recibido', '{x} waste logged': 'merma de {x} anotada',
    'Nothing needs ordering right now.': 'No hay nada que pedir por ahora.', 'orders on {d}': 'pide los {d}', '{n} day lead': '{n} días de entrega', 'Par': 'Par', 'Packs to order': 'Paquetes a pedir',
    'pack of {q}': 'paquete de {q}', 'Create order': 'Crear pedido', 'Nothing to order.': 'Nada que pedir.', 'No open orders.': 'No hay pedidos abiertos.', 'Nothing received yet.': 'Todavía no se ha recibido nada.',
    'No lines yet': 'Sin líneas todavía', '+ Add line': '+ Agregar línea', 'Send by WhatsApp': 'Enviar por WhatsApp', 'Print': 'Imprimir', 'Mark received': 'Marcar recibido', 'Cancel order': 'Cancelar pedido',
    'Cancel this order?': '¿Cancelar este pedido?', 'Could not create the order. Try again.': 'No se pudo crear el pedido. Intente de nuevo.', 'Could not add the lines. Try again.': 'No se pudieron agregar las líneas. Intente de nuevo.',
    'Order created': 'Pedido creado', 'Draft': 'Borrador', 'Sent': 'Enviado', 'Cancelled': 'Cancelado', 'Add to order': 'Agregar al pedido', '1 pack = {x}': '1 paquete = {x}',
    'Pick an item and a number of packs.': 'Elija un producto y un número de paquetes.', 'Mark as received': 'Marcar como recibido',
    "Change any quantity that arrived short or long. Costs update the item's price.": 'Cambie cualquier cantidad que llegó de menos o de más. Los costos actualizan el precio del producto.',
    'Cost / pack': 'Costo / paquete', 'Add to stock': 'Agregar a existencias', 'Order received, stock updated': 'Pedido recibido, existencias actualizadas', 'per sale': 'por venta',
    'open until {t}': 'abierto hasta las {t}', '{n} units': '{n} unidades', 'received': 'recibido', 'owner': 'dueño', 'POS': 'Caja', 'about {n} days left': 'unos {n} días',
    /* owner areas behind a PIN (access.js) */
    'Owners and managers only': 'Solo dueños y encargados', 'owners and managers': 'dueños y encargados', 'Owner': 'Dueño',
    'Type the PIN of an owner, GM or manager. It stays open on this device for 15 minutes, or until someone taps Lock.':
      'Escriba el PIN de un dueño, GM o encargado. Queda abierto en este dispositivo por 15 minutos, o hasta que alguien toque Bloquear.',
    'Back to the POS': 'Volver a la caja', 'No owner or manager set up yet': 'Todavía no hay dueño ni encargado', 'Lock': 'Bloquear',
    'Needs the PIN of an owner, GM or manager': 'Necesita el PIN de un dueño, GM o encargado',
    'Owner areas open': 'Áreas de dueños abiertas', 'until {t}': 'hasta las {t}',
    'Only an owner, GM or manager can open this area.': 'Solo un dueño, GM o encargado puede abrir esta área.',
    'Pick who is opening.': 'Elija quién abre.',
    'Could not open. Try again.': 'No se pudo abrir. Intente de nuevo.',
    'The PIN was right, but this device could not confirm it. Reload the page and try again.': 'El PIN era correcto, pero este dispositivo no pudo confirmarlo. Recargue la página e intente de nuevo.',
    'This manager may not open the sales reports. The owner can allow it in the Time clock, Team section. Or someone else can open them.':
      'Este encargado no puede abrir los reportes de ventas. El dueño lo puede permitir en el Reloj de marcas, sección Equipo. O que los abra otra persona.',
    'Owner (full access)': 'Dueño (acceso total)', 'Only an owner can add or change an owner.': 'Solo un dueño puede agregar o cambiar a un dueño.',
    'Team changes need the PIN of an owner, GM or manager.': 'Los cambios del equipo necesitan el PIN de un dueño, GM o encargado.',
    '{n} (owner)': '{n} (dueño)', '{n} (manager)': '{n} (encargado)',
    'Owner areas opened': 'Áreas de dueños abiertas', 'Discount approved': 'Descuento aprobado', 'Inventory opened': 'Inventario abierto',
    'Unpaid order cancelled': 'Pedido sin pagar cancelado',
    /* POS: discounts approved with a PIN */
    'Discount': 'Descuento', 'Discount approved by {n}': 'Descuento aprobado por {n}', 'Discount {a}': 'Descuento {a}', 'Subtotal': 'Subtotal', 'Remove the discount': 'Quitar el descuento',
    'Approved by {x}': 'Aprobado por {x}', 'approved by {x}': 'aprobado por {x}', 'New total {a}': 'Nuevo total {a}',
    'A discount needs a reason and the PIN of an owner, GM or manager. It is saved with the order.':
      'Un descuento necesita un motivo y el PIN de un dueño, GM o encargado. Queda guardado con el pedido.',
    'How much': 'Cuánto', 'Or an amount in colones': 'O un monto en colones', 'Pick a reason': 'Elija un motivo',
    'Regular customer': 'Cliente frecuente', 'Team member': 'Miembro del equipo', 'Courtesy for a mistake or a wait': 'Cortesía por un error o una espera',
    'Promotion': 'Promoción', 'Details (needed for Other)': 'Detalles (necesarios para Otro)', 'Details': 'Detalles',
    'Approve the discount': 'Aprobar el descuento',
    'Only an owner, GM or manager can approve a discount.': 'Solo un dueño, GM o encargado puede aprobar un descuento.',
    'Pick who is approving the discount.': 'Elija quién aprueba el descuento.', 'Pick the reason for the discount.': 'Elija el motivo del descuento.',
    'Pick a percentage or type an amount.': 'Elija un porcentaje o escriba un monto.', 'The discount is bigger than the order.': 'El descuento es mayor que el pedido.',
    'Write the reason in Details.': 'Escriba el motivo en Detalles.', 'Type the PIN.': 'Escriba el PIN.', 'Could not approve. Try again.': 'No se pudo aprobar. Intente de nuevo.',
    'Discounts switch on once supabase/pos-stations.sql is run in Supabase.': 'Los descuentos se activan cuando se ejecute supabase/pos-stations.sql en Supabase.',
    'A discount needs the internet to check the PIN.': 'Un descuento necesita internet para revisar el PIN.',
    'Discount removed': 'Descuento quitado',
    'Recorded {x}': 'Registrado {x}', 'number {n}': 'número {n}',
    /* POS: devices (front register, iPad) */
    'This device': 'Este dispositivo', 'Which device is this?': '¿Qué dispositivo es este?',
    'Every order keeps the name of the device that took it. Every device shows the orders still to deliver at the top, and the orders still to charge under the menu.':
      'Cada pedido guarda el nombre del dispositivo que lo tomó. Todos los dispositivos muestran arriba los pedidos por entregar, y debajo del menú las órdenes por cobrar.',
    'Main register': 'Caja principal', 'The front counter, with the cash drawer. Charges the orders sent from other devices.':
      'El mostrador del frente, con la gaveta del efectivo. Cobra los pedidos enviados desde otros dispositivos.',
    'Second device': 'Segundo dispositivo', 'The iPad or a phone. Takes orders and sends them to the register, or charges them here.':
      'El iPad o un teléfono. Toma pedidos y los envía a la caja, o los cobra aquí.',
    'Name of this device': 'Nombre de este dispositivo', 'e.g. Front register, iPad': 'p. ej. Caja del frente, iPad',
    'Type a name for this device.': 'Escriba un nombre para este dispositivo.', 'Front register': 'Caja del frente',
    'Name or table (optional)': 'Nombre o mesa (opcional)', 'Name or table': 'Nombre o mesa',
    'Pay later': 'Cobrar después', 'Send to the register': 'Enviar a la caja', 'Sent to the register': 'Enviado a la caja',
    'Run supabase/pos-stations.sql in Supabase to send orders between devices.': 'Ejecute supabase/pos-stations.sql en Supabase para enviar pedidos entre dispositivos.',
    'Not paid': 'Sin pagar', 'Delivered': 'Entregado', 'Charge': 'Cobrar',
    'Cancel this order? It was not paid, so nothing is charged.': '¿Cancelar este pedido? No se pagó, así que no se cobra nada.',
    'It was already paid. A manager can void it from Orders.': 'Ya estaba pagado. Un encargado lo puede anular desde Pedidos.',
    'It was already delivered. Charge it, or a manager voids it from Orders.': 'Ya se entregó. Cóbrelo, o que un encargado lo anule desde Pedidos.',
    'Order cancelled': 'Pedido cancelado', 'Already charged on another device.': 'Ya se cobró en otro dispositivo.',
    'That order was cancelled.': 'Ese pedido fue cancelado.', 'Cancelled before payment': 'Cancelado antes de pagar',
    'Not paid yet (not counted)': 'Sin pagar todavía (no se cuenta)',
    'One order is not paid yet ({x}). Charge it or cancel it before closing: unpaid orders are not counted.':
      'Un pedido todavía no está pagado ({x}). Cóbrelo o cancélelo antes de cerrar: los pedidos sin pagar no se cuentan.',
    '{n} orders are not paid yet ({x}). Charge them or cancel them before closing: unpaid orders are not counted.':
      '{n} pedidos todavía no están pagados ({x}). Cóbrelos o cancélelos antes de cerrar: los pedidos sin pagar no se cuentan.',
    'Discounts given': 'Descuentos dados',
    "Only an owner can change another manager's PIN, role or status.": 'Solo un dueño puede cambiar el PIN, el puesto o el estado de otro encargado.',
    'The discount approval is more than {n} minutes old. Ask for it again.': 'La aprobación del descuento tiene más de {n} minutos. Pídala de nuevo.',
    'Sending to the register needs the internet. Charge it here or try again.': 'Enviar a la caja necesita internet. Cóbrelo aquí o intente de nuevo.',
    'Already done on another device.': 'Ya se hizo en otro dispositivo.',
    'not verified': 'sin verificar',
    /* TV board */
    "Vertical · the TV's top edge is on the left": 'Vertical · el borde de arriba del televisor quedó a la izquierda',
    "Vertical · the TV's top edge is on the right": 'Vertical · el borde de arriba del televisor quedó a la derecha',
    "The TV's top edge is the side where its browser bar or its brand logo ended up. If the menu shows upside down, pick the other vertical option.":
      'El borde de arriba es el lado donde quedó la barra del navegador o el logo de la marca del televisor. Si el menú sale de cabeza, elija la otra opción vertical.',
    'Look': 'Apariencia', 'Automatic: bright by day, dark at night (recommended behind a window)': 'Automática: clara de día, oscura de noche (recomendada detrás de una ventana)',
    'Always bright (easiest to read with reflections)': 'Siempre clara (la más fácil de leer con reflejos)', 'Always dark': 'Siempre oscura',
    'Saved. To keep the look, run supabase/tv-board-look.sql once in Supabase.': 'Guardado. Para guardar la apariencia, ejecute supabase/tv-board-look.sql una vez en Supabase.',
    'Press OK on the remote for full screen': 'Presione OK en el control para pantalla completa',
    /* POS: open bills (pay later), items added later, split payments */
    'Open bill': 'Abrir cuenta', 'Adding to the bill': 'Añadiendo a la cuenta', 'Add to the bill': 'Añadir a la cuenta',
    'Name or table, to find the bill later': 'Nombre o mesa, para encontrar la cuenta después', 'e.g. Ana, table 3': 'p. ej. Ana, mesa 3',
    'Whole bill': 'Toda la cuenta', 'By item': 'Por producto', 'Equal parts': 'Partes iguales', 'An amount': 'Un monto',
    'To pay now': 'A cobrar ahora', 'To pay now (closes the bill)': 'A cobrar ahora (cierra la cuenta)', 'Paid in full': 'Pagada por completo',
    'This bill was already delivered, so a manager approves taking an item off.': 'Esta cuenta ya se entregó, así que un encargado aprueba quitar un producto.',
    'e.g. the guest changed their mind': 'p. ej. el cliente cambió de opinión', 'Take it off': 'Quitarlo', 'Add items': 'Añadir productos',
    'Print the bill': 'Imprimir la cuenta', 'Take off': 'Quitar', 'Opening a bill needs the internet.': 'Abrir una cuenta necesita internet.',
    'Could not open the bill. Check the connection.': 'No se pudo abrir la cuenta. Revise la conexión.',
    'That order is no longer open.': 'Ese pedido ya no está abierto.', 'That order was cancelled.': 'Ese pedido fue cancelado.',
    'That bill was already paid.': 'Esa cuenta ya fue pagada.', 'The bill changed on another device. Check it and try again.': 'La cuenta cambió en otro dispositivo. Revísela e intente de nuevo.',
    'Nothing left to pay on this bill.': 'No queda nada por pagar en esta cuenta.', 'Type an amount no bigger than what is owed.': 'Escriba un monto que no pase de lo que se debe.',
    'Pick how they paid.': 'Elija cómo pagó.', 'Something on the order is not on the menu any more.': 'Algo del pedido ya no está en el menú.',
    'Add fewer items at a time.': 'Añada menos productos a la vez.', 'That is the last thing on the bill. Cancel the order instead.': 'Es lo último de la cuenta. Mejor cancele el pedido.',
    'This bill was already delivered. A manager approves taking an item off.': 'Esta cuenta ya se entregó. Un encargado aprueba quitar un producto.',
    'Write the reason.': 'Escriba el motivo.', 'Only an owner, GM or manager can approve this.': 'Solo un dueño, gerente o encargado puede aprobar esto.',
    'Pick who is approving.': 'Elija quién aprueba.', 'Open bills switch on once supabase/pos-tabs.sql is run in Supabase.': 'Las cuentas abiertas se activan cuando se ejecute supabase/pos-tabs.sql en Supabase.',
    'New': 'Nuevo', 'In the kitchen': 'En cocina', 'Preparing': 'Preparando', 'Paid': 'Pagado', 'Opened {t}': 'Abierta {t}', 'Paid by': 'Pagado con',
    'No items on this bill.': 'No hay productos en esta cuenta.', 'Added to the order': 'Añadido al pedido', 'Added to {x}': 'Añadido a {x}', 'Added {t}': 'Añadido {t}',
    '1 paid': '1 pagado', '{n} paid': '{n} pagados', 'This person pays': 'Esta persona paga', 'One less {x}': 'Uno menos de {x}', 'One more {x}': 'Uno más de {x}',
    'Take one {x} off the bill': 'Quitar un {x} de la cuenta', 'Paid in parts {x}': 'Pagado en partes {x}', 'still to pay {x}': 'falta {x}',
    'Paid {t}': 'Pagado {t}', 'voided': 'anulado', 'Last payment': 'Último pago', 'Still to pay': 'Por pagar',
    'Their items: {x}': 'Sus productos: {x}', 'less the discount': 'menos el descuento',
    'Tap + on what this person pays. Each person pays in turn.': 'Toque + en lo que paga esta persona. Cada persona paga a su turno.',
    '{n} people still to pay, the same part each.': 'Faltan {n} personas por pagar, la misma parte cada una.',
    'The last person pays what is left.': 'La última persona paga lo que queda.', 'How many people pay?': '¿Cuántas personas pagan?',
    'Amount this person pays (₡)': 'Monto que paga esta persona (₡)', 'One payment for everything still owed.': 'Un solo pago por todo lo que se debe.',
    'That is more than what is owed ({x}).': 'Es más de lo que se debe ({x}).',
    'Charging a bill needs the internet. Try again in a moment.': 'Cobrar una cuenta necesita internet. Intente de nuevo en un momento.',
    'Could not record the payment. Check the connection and try again.': 'No se pudo registrar el pago. Revise la conexión e intente de nuevo.',
    'Bill paid': 'Cuenta pagada', 'Part paid': 'Parte pagada', 'Name or table for this bill:': 'Nombre o mesa para esta cuenta:', 'Could not save.': 'No se pudo guardar.',
    'Take 1× {x} off the bill?': '¿Quitar 1× {x} de la cuenta?', 'Take 1× {x} off the bill': 'Quitar 1× {x} de la cuenta',
    'This needs the internet. Try again in a moment.': 'Esto necesita internet. Intente de nuevo en un momento.',
    'Could not take it off. Try again.': 'No se pudo quitar. Intente de nuevo.', 'Taken off': 'Quitado', 'the bill is settled': 'la cuenta quedó saldada',
    'Tap the items to add to {x}': 'Toque los productos para añadir a {x}', 'Adding to a bill needs the internet. Try again in a moment.': 'Añadir a una cuenta necesita internet. Intente de nuevo en un momento.',
    'Could not add. Check the connection and try again.': 'No se pudo añadir. Revise la conexión e intente de nuevo.', 'Could not add. Try again.': 'No se pudo añadir. Intente de nuevo.',
    'sent to the kitchen': 'enviado a cocina', 'Part of {x}': 'Parte de la cuenta {x}',
    'Part of this bill was paid. Take items off one by one instead.': 'Parte de esta cuenta ya se pagó. Quite los productos uno por uno.',
    'Item taken off a bill': 'Producto quitado de una cuenta', 'Paid in parts {x} · this is the last payment': 'Pagado en partes {x} · este es el último pago',
    'this is the last payment': 'este es el último pago',     'only these': 'solo esto', 'Something was just added to this order. Check the ticket.': 'Se acaba de añadir algo a este pedido. Revise el ticket.',
    'Something was added · check the ticket': 'Se añadió algo · revise el ticket', 'Paid earlier': 'Pagado antes',
    'Part of this bill was already paid on account. A manager voids (or gives back) that payment in Orders first, then try again.': 'Parte de esta cuenta ya se pagó a cuenta. Un encargado anula (o devuelve) ese pago en Pedidos primero; luego intente de nuevo.',
    'Take off the combo discount line first.': 'Primero quite la línea de descuento del combo.', 'That would take the bill below zero.': 'Eso dejaría la cuenta por debajo de cero.',
    'Finish adding to No number first: tap Add to the bill or Cancel.': 'Termine de añadir a la cuenta sin número primero: toque Añadir a la cuenta o Cancelar.',
    'Finish adding to {x} first: tap Add to the bill or Cancel.': 'Termine de añadir a {x} primero: toque Añadir a la cuenta o Cancelar.',
    'Added to No number': 'Añadido a la cuenta sin número', 'Tap the items to add to No number': 'Toque los productos para añadir a la cuenta sin número',
    'Saving': 'Guardando', 'ordered from the room': 'pedido desde la habitación',
    'The clock of this device is off by {x}': 'El reloj de este dispositivo está desfasado por {x}',
    'Set the date and time to automatic in the device settings.': 'Ponga la fecha y la hora en automático en los ajustes del dispositivo.',
    'The session ended because it could not be renewed. Sign in again.': 'La sesión terminó porque no se pudo renovar. Vuelva a ingresar.',
    'Void': 'Anular', 'Void {x}': 'Anular {x}', 'not paid yet': 'sin pagar todavía', 'Accept': 'Aceptar',
    'Give back': 'Devolver', 'Give back {x}': 'Devolver {x}', 'Give it back': 'Devolverlo', 'Given back {t}': 'Devuelto {t}',
    'Money given back': 'Dinero devuelto', 'given back': 'devuelto', 'it is back on the bill': 'vuelve a la cuenta',
    'Payment given back': 'Pago devuelto', 'Given back': 'Devuelto',
    'Some of these were already added to {x}. Check the bill and add what is missing.': 'Parte de esto ya se había añadido a {x}. Revise la cuenta y añada lo que falte.',
    'That is the last thing on the bill. A manager voids it from Orders.': 'Es lo último de la cuenta. Un encargado lo anula desde Pedidos.',
    'That bill is closed.': 'Esa cuenta está cerrada.', 'The items stay on the ticket to charge as a new sale.': 'Los productos quedan en el pedido para cobrarlos como una venta nueva.',
    /* POS: open orders under the menu, sales kept on this device, a discount on a bill */
    'Open orders': 'Órdenes abiertas', '1 order · {x} to collect': '1 orden · {x} por cobrar', '{n} orders · {x} to collect': '{n} órdenes · {x} por cobrar',
    'Tap one to add items, give a discount or charge it.': 'Toque una para añadir productos, dar un descuento o cobrarla.',
    'None right now. An order charged later stays here until it is paid.': 'Ninguna por ahora. Una orden para cobrar después queda aquí hasta que se pague.',
    'Adding items': 'Añadiendo productos', 'Not saved yet': 'Sin guardar todavía', 'See why': 'Ver por qué',
    'Sales saved on this device': 'Ventas guardadas en este dispositivo', 'Saved on this device': 'Guardado en este dispositivo',
    'Try again now': 'Intentar de nuevo ahora', '{n} not saved yet': '{n} sin guardar todavía', 'saving {n}': 'guardando {n}',
    /* an open order still only on this device (pos.html, its own window) */
    'Open this order ›': 'Abrir esta orden ›', 'Trying now': 'Intentando ahora', 'Tried at {t}': 'Intentado a las {t}',
    'Tried at {t} · still not saved': 'Intentado a las {t} · sigue sin guardar',   /* before the shorter ones below */
    '1 saved now': '1 guardada ahora', '{n} saved now': '{n} guardadas ahora',
    'everything is saved': 'todo está guardado', 'still not saved': 'sigue sin guardar',
    'Only on this device': 'Solo en este dispositivo', 'Paid here': 'Pagada aquí', 'not in the system yet': 'todavía no está en el sistema',
    'Items added and the payment taken here go to the system by themselves, right after the order. Do not ring it again.':
      'Los productos añadidos y el pago cobrado aquí suben al sistema solos, justo después de la orden. No la vuelva a marcar.',
    'Discount, splitting the bill and taking an item off work once the order is in the system.':
      'El descuento, dividir la cuenta y quitar un producto funcionan cuando la orden ya esté en el sistema.',
    'It is in the system now.': 'Ya está en el sistema.', 'It goes to the system with the order.': 'Sube al sistema con la orden.',
    'This order has a discount: add items once it is in the system.': 'Esta orden tiene descuento: añada productos cuando ya esté en el sistema.',
    'Check this': 'Revise esto', 'OK, checked': 'Listo, revisado', 'Not added to No number': 'No se añadió a Sin número', 'Not added to {x}': 'No se añadió a {x}',
    'Already paid here with the bill: ring these as a new sale with the same payment, without charging the customer again.':
      'Ya se cobraron aquí con la cuenta: regístrelos como una venta nueva con el mismo pago, sin cobrarle otra vez al cliente.',
    'The bill changed on another device.': 'La cuenta cambió en otro dispositivo.',
    'Not on the list of No number': 'No está en la lista de Sin número', 'Not on the list of {x}': 'No está en la lista de {x}',
    'The bill’s total counts them. Tell the manager.': 'El total de la cuenta los incluye. Avise al encargado.',
    'Record what was taken on the bill in the system (pay by amount), then charge the rest.': 'Registre lo cobrado en la cuenta en el sistema (pago por monto) y luego cobre el resto.',
    'Charge these as a new sale if the customer has them.': 'Cóbrelos como una venta nueva si el cliente los tiene.',
    'Payment not recorded': 'Pago no registrado', 'Taken on this device': 'Cobrado en este dispositivo',
    'Check the money: give it back if the customer paid.': 'Revise el dinero: devuélvalo si el cliente pagó.',
    'Paid twice?': '¿Pagado dos veces?', 'It was already paid in the system': 'Ya estaba pagada en el sistema',
    'If the customer paid twice, give one payment back.': 'Si el cliente pagó dos veces, devuelva uno de los pagos.',
    'No internet on this device. It saves by itself when the internet is back.': 'Este dispositivo no tiene internet. Se guarda solo cuando vuelva el internet.',
    'The sign-in must be renewed. If it does not save within a minute, tap Sign out and sign in again.': 'Hay que renovar el ingreso. Si no se guarda en un minuto, toque Cerrar sesión y vuelva a ingresar.',
    'This login is not connected to the café in the system. The owner must connect it in Supabase.': 'Este ingreso no está conectado al café en el sistema. El dueño tiene que conectarlo en Supabase.',
    'The system refused this sale.': 'El sistema rechazó esta venta.',
    'Everything taken on this device is saved in the system.': 'Todo lo que se tomó en este dispositivo está guardado en el sistema.',
    'These sales are kept on this device until they reach the system, and they go by themselves. The other devices, the register and the open orders see them once they are saved. Nothing is lost: do not clear this browser’s data.':
      'Estas ventas se guardan en este dispositivo hasta que lleguen al sistema, y se envían solas. Los otros dispositivos, la caja y las órdenes abiertas las ven cuando ya están guardadas. No se pierde nada: no borre los datos de este navegador.',
    'Discount on the bill': 'Descuento en la cuenta', 'Still to pay {x}': 'Por pagar {x}',
    'On the items of this bill not paid yet ({x}). It needs a reason and the PIN of an owner, GM or manager.':
      'Sobre los productos de esta cuenta que aún no se pagan ({x}). Necesita un motivo y el PIN de un dueño, GM o encargado.',
    'The discount is bigger than what is still to pay.': 'El descuento es mayor que lo que falta por pagar.',
    'That approval was not found. Ask for the discount again.': 'No se encontró esa aprobación. Pida el descuento de nuevo.',
    'That approval was already used on another order. Ask for the discount again.': 'Esa aprobación ya se usó en otro pedido. Pida el descuento de nuevo.',
    'A discount on a bill switches on once the new part of supabase/pos-tabs.sql is run in Supabase.': 'El descuento en una cuenta se activa cuando se ejecute la parte nueva de supabase/pos-tabs.sql en Supabase.',
    'Could not save the discount. Check the connection and try again.': 'No se pudo guardar el descuento. Revise la conexión e intente de nuevo.',
    'Could not save the discount. Try again.': 'No se pudo guardar el descuento. Intente de nuevo.',
    'Take the discount off this bill?': '¿Quitar el descuento de esta cuenta?', 'Discount taken off what is still to pay': 'Descuento quitado de lo que falta por pagar',
    'Discount taken off a bill': 'Descuento quitado de una cuenta',
    'Login type changed': 'Tipo de ingreso cambiado', 'Owner access removed': 'Acceso de dueño quitado',
    '{n} sales are not saved yet. Tap the red sign at the top to see why, before closing.': '{n} ventas no se han guardado todavía. Toque el aviso rojo de arriba para ver por qué, antes de cerrar.',
    'One sale is not saved yet. Tap the red sign at the top to see why, before closing.': 'Una venta no se ha guardado todavía. Toque el aviso rojo de arriba para ver por qué, antes de cerrar.',
    'One sale is waiting to sync. Connect to the internet before closing.': 'Una venta espera sincronizarse. Conéctese a internet antes de cerrar.',
    'not kept on this device': 'no guardado en este dispositivo',
    'The system is not answering right now. It saves by itself when it is back: do not ring the sale again.': 'El sistema no responde en este momento. Se guarda solo cuando vuelva: no cobre la venta otra vez.',
    'This device’s storage is full or blocked, so these sales are only on this page. Do not close or reload it until they are saved.': 'El almacenamiento de este dispositivo está lleno o bloqueado, así que estas ventas solo están en esta página. No la cierre ni la recargue hasta que se guarden.',
    'Could not update the list. Check the internet, or sign out and sign in again.': 'No se pudo actualizar la lista. Revise el internet, o cierre sesión y vuelva a ingresar.',
    'Could not load the open orders. Check the internet, or sign out and sign in again.': 'No se pudieron cargar las órdenes abiertas. Revise el internet, o cierre sesión y vuelva a ingresar.',
    /* POS · review fixes (migration 0028): a negative total, the dollars at closing */
    'The total cannot be negative.': 'El total no puede ser negativo.',
    'This sale has a negative total and was not accepted.': 'Esta venta tiene un total negativo y no se aceptó.',
    'Type the dollars in the drawer: the day expects {x}.': 'Escriba los dólares que hay en la caja: el día espera {x}.',
    /* faq:start */
    "Where is the best coffee in Monteverde?": "¿Dónde está el mejor café de Monteverde?",
    "Ask ten guides in Santa Elena and you get ten answers, so here is ours: the best coffee in Monteverde is grown here, roasted here and brewed slowly. At Hanging Garden Café we pour coffee from El Trapiche, a family farm on this mountain, roasted locally and ground for each cup. Read how we choose it on our coffee page.": "Pregunte a diez guías en Santa Elena y tendrá diez respuestas, así que aquí va la nuestra: el mejor café de Monteverde se cultiva aquí, se tuesta aquí y se prepara sin prisa. En Hanging Garden Café servimos café de El Trapiche, una finca familiar de esta montaña, tostado localmente y molido para cada taza. Lea cómo lo elegimos en nuestra página del café.",
    "What time do you open? I want coffee before the cloud forest reserve.": "¿A qué hora abren? Quiero café antes de la reserva del bosque nuboso.",
    "We open at 6:00 every day, one hour before the Monteverde Cloud Forest Reserve opens its gate at 7:00. Coffee, a warm croissant or an empanada, and you are on the trail before the crowds. We close at 19:00.": "Abrimos a las 6:00 todos los días, una hora antes de que la Reserva del Bosque Nuboso Monteverde abra su portón a las 7:00. Un café, un croissant caliente o una empanada, y está en el sendero antes que todos. Cerramos a las 19:00.",
    "Where can I have breakfast in Santa Elena before a tour?": "¿Dónde puedo desayunar en Santa Elena antes de un tour?",
    "Right here, from 6:00. Sandwiches such as the Mano de Piedra with Costa Rican beef, empanadas, croissants, banana bread and a chorreado coffee. Leaving before dawn? Order an Adventure Box by 20:00 the night before and pick it up from 6:30.": "Aquí mismo, desde las 6:00. Sándwiches como el Mano de Piedra con carne costarricense, empanadas, croissants, pan de banano y un café chorreado. ¿Sale antes del amanecer? Pida una Adventure Box antes de las 20:00 la noche anterior y recójala desde las 6:30.",
    "Where is Hanging Garden Café, and how far is it from the reserve?": "¿Dónde queda Hanging Garden Café y a qué distancia está de la reserva?",
    "We are 50 metres south and 50 metres east of the church in Santa Elena, Monteverde, Puntarenas, Costa Rica. The Monteverde Cloud Forest Reserve is about 10 minutes away by car, and the centre of Santa Elena is a short walk. Tap \"Get directions\" in the visit section and Google Maps takes you to the door.": "Estamos 50 metros sur y 50 metros este de la Iglesia de Santa Elena, Monteverde, Puntarenas, Costa Rica. La Reserva del Bosque Nuboso Monteverde queda a unos 10 minutos en carro, y el centro de Santa Elena a una caminata corta. Toque \"Cómo llegar\" en la sección de visita y Google Maps lo lleva a la puerta.",
    "Is Monteverde coffee really that good?": "¿De verdad es tan bueno el café de Monteverde?",
    "Yes, and there is a reason. Monteverde sits at about 1,400 metres, where cool nights make the coffee cherry ripen slowly and build sugar. That is why a Monteverde cup tastes sweet and clean, with chocolate and citrus notes. Our coffee page explains altitude, harvest and roast in plain words.": "Sí, y hay una razón. Monteverde está a unos 1 400 metros, donde las noches frías hacen que el fruto madure despacio y acumule azúcar. Por eso una taza de Monteverde sabe dulce y limpia, con notas de chocolate y cítricos. Nuestra página del café explica altitud, cosecha y tueste en palabras sencillas.",
    "Is there a coffee tour near Santa Elena, and how long does it take?": "¿Hay un tour de café cerca de Santa Elena y cuánto dura?",
    "Yes. Several family farms around Monteverde run coffee tours of two to three hours, from the plant to the roaster, usually with sugar cane and chocolate too. If you only have twenty minutes, come and taste the same mountain in a cup: we serve El Trapiche coffee and are happy to tell you how it is made.": "Sí. Varias fincas familiares alrededor de Monteverde hacen tours de café de dos a tres horas, de la planta al tostador, casi siempre con caña de azúcar y chocolate también. Si solo tiene veinte minutos, venga a probar la misma montaña en una taza: servimos café de El Trapiche y con gusto le contamos cómo se hace.",
    "Can I buy Monteverde coffee beans to take home?": "¿Puedo comprar café de Monteverde en grano para llevar a casa?",
    "Ask at the counter. We sell what we brew when we have it, whole bean or ground, and we can tell you which farm it comes from and when it was roasted. It packs flat in a suitcase and it is the souvenir people write to us about.": "Pregunte en el mostrador. Vendemos lo mismo que servimos cuando lo tenemos, en grano o molido, y le decimos de qué finca viene y cuándo se tostó. Cabe plano en la maleta y es el recuerdo por el que la gente nos escribe.",
    "What can I do in Monteverde when it rains?": "¿Qué puedo hacer en Monteverde cuando llueve?",
    "Let it rain, this is a cloud forest. A hot chocolate or a Cloud Forest Latte under the hanging plants is the local way to wait it out, and the forest is at its greenest right after. Our rainy day guide lists what stays open and what is better in the mist.": "Que llueva, esto es un bosque nuboso. Un chocolate caliente o un Cloud Forest Latte bajo las plantas colgantes es la forma local de esperar, y el bosque está más verde justo después. Nuestra guía de días de lluvia dice qué sigue abierto y qué es mejor con neblina.",
    "Do you have garden seating or a view?": "¿Tienen mesas en el jardín o vista?",
    "Our tables sit under hanging plants, ferns and flowers, with the cloud forest air coming through. It is a garden more than a view: hummingbirds visit, and on clear afternoons the light comes in sideways through the mist.": "Nuestras mesas están bajo plantas colgantes, helechos y flores, con el aire del bosque nuboso entrando. Es más jardín que vista: los colibríes visitan, y en las tardes despejadas la luz entra de lado a través de la neblina.",
    "Is Monteverde cold? What should I wear?": "¿Hace frío en Monteverde? ¿Qué debo llevar?",
    "Cool, not cold: about 15 to 22 °C most of the year, with mist and wind. Bring layers and a light rain jacket even on sunny mornings. Then come in for something hot; we have coffee, tea and Costa Rican hot chocolate.": "Fresco, no frío: unos 15 a 22 °C casi todo el año, con neblina y viento. Lleve capas y una capa ligera de lluvia incluso en mañanas soleadas. Luego pase por algo caliente; tenemos café, té y chocolate caliente costarricense.",
    "Do you accept credit cards, US dollars and colones?": "¿Aceptan tarjetas, dólares y colones?",
    "Yes to all three. Prices are in colones; we also take dollars at the counter, cards, and SINPE Móvil. Change is given in colones.": "Sí, los tres. Los precios están en colones; también aceptamos dólares en el mostrador, tarjetas y SINPE Móvil. El vuelto se da en colones.",
    "Do you have wifi? Can I work on my laptop?": "¿Tienen wifi? ¿Puedo trabajar con mi computadora?",
    "Yes, there is free wifi for guests; ask at the counter for the password. You are welcome to work a while. Mornings are the quietest and there are some outlets.": "Sí, hay wifi gratis para visitantes; pida la clave en el mostrador. Puede venir a trabajar un rato. Las mañanas son lo más tranquilo y hay algunos enchufes.",
    "Do you have oat milk, almond milk or lactose free milk?": "¿Tienen leche de avena, de almendra o deslactosada?",
    "We have lactose free milk for any coffee or hot chocolate, just ask. We do not stock oat or almond milk. Every smoothie can be made in water instead of milk.": "Tenemos leche deslactosada para cualquier café o chocolate caliente, solo pídala. No tenemos leche de avena ni de almendra. Todos los batidos se pueden hacer en agua en vez de leche.",
    "Do you have decaf?": "¿Tienen descafeinado?",
    "No, we do not serve decaf. Our coffee is arabica from Monteverde, which is naturally lower in caffeine than most supermarket blends. For no caffeine at all, try the tea, the Costa Rican hot chocolate or a garden smoothie.": "No, no servimos descafeinado. Nuestro café es arábica de Monteverde, que por naturaleza tiene menos cafeína que la mayoría de las mezclas de supermercado. Si no quiere nada de cafeína, pruebe el té, el chocolate caliente costarricense o un batido del jardín.",
    "Do you have gluten free, vegan or vegetarian options?": "¿Tienen opciones sin gluten, veganas o vegetarianas?",
    "Vegetarian, yes: the Monteverde sandwich, most pastries, drinks and smoothies. Vegan: smoothies in water, americano, tea and the sweet cane drink. Our kitchen is small, so we cannot promise zero contact with gluten; tell the team when you order and they will guide you.": "Vegetarianas, sí: el sándwich Monteverde, casi toda la repostería, las bebidas y los batidos. Veganas: batidos en agua, americano, té y agua dulce. Nuestra cocina es pequeña, así que no podemos prometer cero contacto con gluten; avise al equipo al ordenar y le orientan.",
    "Is the café dog friendly?": "¿Se puede ir con perro?",
    "Well behaved dogs are welcome at the garden tables, and we will find them a bowl of water.": "Los perros educados son bienvenidos en las mesas del jardín, y les buscamos un tazón de agua.",
    "Is it good for kids?": "¿Es bueno para niños?",
    "Very. The garden gives children room to look at plants and hummingbirds, and the Costa Rican hot chocolate was practically made for them.": "Mucho. El jardín les da espacio para mirar plantas y colibríes, y el chocolate caliente costarricense es casi para ellos.",
    "Is there parking?": "¿Hay parqueo?",
    "Yes, free street parking right by the café. Mornings before 7:00 are the easiest time to find a spot.": "Sí, hay parqueo gratis en la calle junto al café. Antes de las 7:00 es la hora más fácil para encontrar campo.",
    "Can I book a table, or bring a group?": "¿Puedo reservar mesa o venir en grupo?",
    "No reservation needed, just come in. For groups of eight or more, or a small celebration, message us on WhatsApp a day ahead and we will set the garden for you.": "No necesita reserva, solo llegue. Para grupos de ocho o más, o una celebración pequeña, escríbanos por WhatsApp un día antes y le acomodamos el jardín.",
    "Do you do takeaway, and can I order on WhatsApp?": "¿Tienen para llevar y puedo pedir por WhatsApp?",
    "Everything on the menu travels well; just ask for it to go. To order ahead, write to us on WhatsApp at +506 6400 6601 and tell us when you will pick it up.": "Todo el menú viaja bien; solo pídalo para llevar. Para pedir con anticipación, escríbanos por WhatsApp al +506 6400 6601 y díganos a qué hora lo recoge.",
    "Are you open on Sundays and holidays?": "¿Abren domingos y feriados?",
    "Yes. We open every day of the week, 6:00 to 19:00, holidays included. If a storm or a special day changes that, we post it on our Google profile first.": "Sí. Abrimos todos los días de la semana, de 6:00 a 19:00, feriados incluidos. Si una tormenta o un día especial cambia eso, lo publicamos primero en nuestro perfil de Google.",
    "Is there a bathroom?": "¿Hay baño?",
    "Yes, we have restrooms for guests.": "Sí, tenemos baños para visitantes.",
    "Is tipping expected in Costa Rica?": "¿Se deja propina en Costa Rica?",
    "Tips are never expected in Costa Rica and always appreciated. If someone made your morning, a small extra says so.": "La propina nunca es obligatoria en Costa Rica y siempre se agradece. Si alguien le alegró la mañana, un poco extra lo dice.",
    "Do you speak English?": "¿Hablan inglés?",
    "English y español, con mucho gusto. The menu, this website and our team speak both.": "English y español, con mucho gusto. El menú, este sitio y nuestro equipo hablan los dos.",
    "Our coffee": "Nuestro café",
    "Why coffee from 1,400 metres tastes sweeter": "Por qué el café de 1 400 metros sabe más dulce",
    "What makes Monteverde coffee taste the way it does: 1,400 metres of altitude, hand picking, honey and washed processing, local roasting, and the chorreado.": "Qué hace que el café de Monteverde sepa como sabe: 1 400 metros de altura, recolección a mano, proceso honey y lavado, tueste local y el chorreado.",
    "Monteverde guide": "Guía de Monteverde",
    "Looking for the best coffee in Monteverde, Costa Rica? Five signs of a great cup, where the coffee comes from, what to order, and why Hanging Garden Café opens at 6:00 for it..": "¿Busca el mejor café de Monteverde, Costa Rica? Cinco señales de una gran taza, de dónde viene el café, qué pedir y por qué Hanging Garden Café abre a las 6:00 para eso..",
    "Best coffee in Monteverde": "El mejor café de Monteverde",
    "Breakfast in Santa Elena before the cloud forest": "Desayuno en Santa Elena antes del bosque nuboso",
    "Where to have breakfast in Santa Elena, Monteverde before the cloud forest reserve, the hanging bridges or a sunrise tour.": "Dónde desayunar en Santa Elena, Monteverde antes de la reserva del bosque nuboso, los puentes colgantes o un tour al amanecer.",
    "Breakfast before the reserve": "Desayuno antes de la reserva",
    "What to do in Monteverde when it rains": "Qué hacer en Monteverde cuando llueve",
    "Rain in Monteverde is normal and the forest is better for it.": "Llover en Monteverde es normal y el bosque está mejor así.",
    "Rainy day in Monteverde": "Día de lluvia en Monteverde",
    "Specialty coffee · Fresh food": "Café de especialidad · Comida fresca",
    "The menu": "El menú",
    "The full menu of Hanging Garden Café in Monteverde, Costa Rica with prices in colones: specialty coffee from El Trapiche, chorreado, sandwiches, empanadas, pastries, Costa Rican favourites and garden smoothies.": "El menú completo de Hanging Garden Café en Monteverde, Costa Rica con precios en colones: café de especialidad de El Trapiche, chorreado, sándwiches, empanadas, repostería, favoritos costarricenses y batidos del jardín.",
    "Menu": "Menú",
    "Questions people ask before they visit": "Preguntas que la gente hace antes de visitar",
    "Good to know": "Bueno saberlo",
    "Hours, coffee, payment, what to wear: the answers we give at the counter, here before you arrive.": "Horario, café, pagos, qué ponerse: las respuestas que damos en el mostrador, aquí antes de que llegue.",
    "Read before you come": "Lea antes de venir",
    "Monteverde guides": "Guías de Monteverde",
    "Leave a review on Google": "Deje una reseña en Google",
    "Open the menu as its own page": "Abrir el menú en su propia página",
/* faq:end */
  };

  /* ---------- pattern entries ({x} placeholders) ---------- */
  var PAT = [];
  Object.keys(D).forEach(function (k) {
    if (k.indexOf('{') < 0) return;
    var names = [];
    var re = '^' + k.replace(/[.*+?^$()|[\]\\]/g, '\\$&').replace(/\{(\w+)\}/g, function (_, n) { names.push(n); return '(.+?)'; }) + '$';
    PAT.push({ re: new RegExp(re), names: names, es: D[k], sep: k.indexOf(' · ') > -1,
               head: /^\{\w+\}/.test(k), tail: /\{\w+\}$/.test(k) });
  });

  function lookup(k) {
    if (D.hasOwnProperty(k)) return D[k];
    for (var i = 0; i < PAT.length; i++) {
      var m = k.match(PAT[i].re);
      /* an open-ended entry never swallows a " · " it does not have itself: "Recorded {x}" must not eat
         "₡5 000 · Cash ₡ · number 3"; such a line is translated part by part below */
      if (m && !PAT[i].sep && ((PAT[i].head && m[1].indexOf(' · ') > -1) || (PAT[i].tail && m[m.length - 1].indexOf(' · ') > -1))) continue;
      if (m) {
        var out = PAT[i].es;
        PAT[i].names.forEach(function (n, j) { out = out.replace('{' + n + '}', function () { return m[j + 1]; }); });
        return out;
      }
    }
    return null;
  }
  /* short English day and month names the pages print next to numbers */
  var DAYS = { Mon: 'lun', Tue: 'mar', Wed: 'mié', Thu: 'jue', Fri: 'vie', Sat: 'sáb', Sun: 'dom' };
  var MONTHS = { Jan: 'ene', Feb: 'feb', Mar: 'mar', Apr: 'abr', May: 'may', June: 'jun', Jun: 'jun', July: 'jul', Jul: 'jul', Aug: 'ago', Sept: 'set', Sep: 'set', Oct: 'oct', Nov: 'nov', Dec: 'dic' };
  var LONG = { January: 'enero', February: 'febrero', March: 'marzo', April: 'abril', May: 'mayo', June: 'junio', July: 'julio', August: 'agosto', September: 'setiembre', October: 'octubre', November: 'noviembre', December: 'diciembre' };
  function esDates(str) {
    return str.replace(/\b(January|February|March|April|May|June|July|August|September|October|November|December)(?= \d{4}\b)/g, function (m) { return LONG[m]; })
              .replace(/\b(Mon|Tue|Wed|Thu|Fri|Sat|Sun)(?= \d)/g, function (d) { return DAYS[d]; })
              .replace(/(?<=\d )(Jan|Feb|Mar|Apr|May|June|Jun|July|Jul|Aug|Sept|Sep|Oct|Nov|Dec)\b/g, function (m) { return MONTHS[m]; });
  }
  function tr(text) {
    var k = text.replace(/\s+/g, ' ').trim();
    if (!k || !/[A-Za-z]/.test(k)) return null;
    var t = lookup(k);
    if (t !== null) return esDates(t);
    var dated = esDates(k);
    if (dated !== k) { var t2 = lookup(dated); return t2 !== null ? t2 : dated; }
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
  /* staff screens start in Spanish; public pages follow the visitor's device */
  if (lang !== 'en' && lang !== 'es') lang = (window.HG_CONFIG && HG_CONFIG.staffPage) || /^es/i.test(navigator.language || '') ? 'es' : 'en';
  window.HG_LANG = lang;
  /* exact dictionary entries only, for text typed in the Menu Manager (the QR menu, m.html): a dish name is
     never put through the patterns or word-by-word rules, so 'Float' or 'Baked fresh today' stay as typed */
  var MENU = {};
  (function () {
    var keys = Object.keys(D), a = keys.indexOf('\u0000menu-start'), b = keys.indexOf('\u0000menu-end');
    for (var i = a + 1; a > -1 && i < b; i++) MENU[keys[i]] = 1;
  })();
  window.HG_EXACT = function (k) {
    k = String(k == null ? '' : k).replace(/\s+/g, ' ').trim();
    return k && MENU.hasOwnProperty(k) && D[k] ? D[k] : null;
  };

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
               document.querySelector('header.top') || document.getElementById('soundBtn') ||
               document.querySelector('.app .topbar') || false;
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
