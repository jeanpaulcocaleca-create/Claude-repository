/* Hanging Garden Café · content for the search pages
   Everything Google reads lives here once, in English and Spanish:
   the home page FAQ, the "Our coffee" page, the three Monteverde guides,
   and the words around the menu page. Edit this file, then run
       node tools/pages/build.js
   and the pages, the home page FAQ, the dictionary and the sitemap are rebuilt. */

'use strict';

const SITE = 'https://hanginggardencafe.com';
const CAFE = 'Hanging Garden Café';
const WHATSAPP = 'https://wa.me/50664006601';
const PHONE = '+506 6400 6601';
const MAPS = 'https://www.google.com/maps/search/Hanging+Garden+Cafe+Monteverde';
/* The short "write a review" link from the Google Business Profile (Business Profile → Ask for reviews). */
const REVIEW_URL = 'https://g.page/r/CfHitxq6bJ3AEBM/review';
const UPDATED = '2026-09-29';

/* ------------------------------------------------------------------ */
/*  Home page FAQ: the questions people type before they visit          */
/*  `hold: true` keeps a question out of the site until the owner       */
/*  confirms the answer.                                                */
/* ------------------------------------------------------------------ */
const FAQ = [
  { id: 'best', en: { q: 'Where is the best coffee in Monteverde?',
      a: 'Ask ten guides in Santa Elena and you get ten answers, so here is ours: the best coffee in Monteverde is grown here, roasted here and brewed slowly. At Hanging Garden Café we pour coffee from El Trapiche, a family farm on this mountain, roasted locally and ground for each cup. Read how we choose it on our coffee page.' },
    es: { q: '¿Dónde está el mejor café de Monteverde?',
      a: 'Pregunte a diez guías en Santa Elena y tendrá diez respuestas, así que aquí va la nuestra: el mejor café de Monteverde se cultiva aquí, se tuesta aquí y se prepara sin prisa. En Hanging Garden Café servimos café de El Trapiche, una finca familiar de esta montaña, tostado localmente y molido para cada taza. Lea cómo lo elegimos en nuestra página del café.' } },
  { id: 'hours', en: { q: 'What time do you open? I want coffee before the cloud forest reserve.',
      a: 'We open at 6:00 every day, one hour before the Monteverde Cloud Forest Reserve opens its gate at 7:00. Coffee, a warm croissant or an empanada, and you are on the trail before the crowds. We close at 19:00.' },
    es: { q: '¿A qué hora abren? Quiero café antes de la reserva del bosque nuboso.',
      a: 'Abrimos a las 6:00 todos los días, una hora antes de que la Reserva del Bosque Nuboso Monteverde abra su portón a las 7:00. Un café, un croissant caliente o una empanada, y está en el sendero antes que todos. Cerramos a las 19:00.' } },
  { id: 'breakfast', en: { q: 'Where can I have breakfast in Santa Elena before a tour?',
      a: 'Right here, from 6:00. Sandwiches such as the Mano de Piedra with Costa Rican beef, empanadas, croissants, banana bread and a chorreado coffee. Leaving before dawn? Order an Adventure Box by 20:00 the night before and pick it up from 6:30.' },
    es: { q: '¿Dónde puedo desayunar en Santa Elena antes de un tour?',
      a: 'Aquí mismo, desde las 6:00. Sándwiches como el Mano de Piedra con carne costarricense, empanadas, croissants, pan de banano y un café chorreado. ¿Sale antes del amanecer? Pida una Adventure Box antes de las 20:00 la noche anterior y recójala desde las 6:30.' } },
  { id: 'where', en: { q: 'Where is Hanging Garden Café, and how far is it from the reserve?',
      a: 'We are in Monteverde, on the road through Santa Elena, Puntarenas, Costa Rica. The Monteverde Cloud Forest Reserve is about 10 minutes away by car, and the centre of Santa Elena is a short walk. Tap "Get directions" in the visit section and Google Maps takes you to the door.' },
    es: { q: '¿Dónde queda Hanging Garden Café y a qué distancia está de la reserva?',
      a: 'Estamos en Monteverde, sobre la carretera que atraviesa Santa Elena, Puntarenas, Costa Rica. La Reserva del Bosque Nuboso Monteverde queda a unos 10 minutos en carro, y el centro de Santa Elena a una caminata corta. Toque "Cómo llegar" en la sección de visita y Google Maps lo lleva a la puerta.' } },
  { id: 'why', en: { q: 'Is Monteverde coffee really that good?',
      a: 'Yes, and there is a reason. Monteverde sits at about 1,400 metres, where cool nights make the coffee cherry ripen slowly and build sugar. That is why a Monteverde cup tastes sweet and clean, with chocolate and citrus notes. Our coffee page explains altitude, harvest and roast in plain words.' },
    es: { q: '¿De verdad es tan bueno el café de Monteverde?',
      a: 'Sí, y hay una razón. Monteverde está a unos 1 400 metros, donde las noches frías hacen que el fruto madure despacio y acumule azúcar. Por eso una taza de Monteverde sabe dulce y limpia, con notas de chocolate y cítricos. Nuestra página del café explica altitud, cosecha y tueste en palabras sencillas.' } },
  { id: 'tour', en: { q: 'Is there a coffee tour near Santa Elena, and how long does it take?',
      a: 'Yes. Several family farms around Monteverde run coffee tours of two to three hours, from the plant to the roaster, usually with sugar cane and chocolate too. If you only have twenty minutes, come and taste the same mountain in a cup: we serve El Trapiche coffee and are happy to tell you how it is made.' },
    es: { q: '¿Hay un tour de café cerca de Santa Elena y cuánto dura?',
      a: 'Sí. Varias fincas familiares alrededor de Monteverde hacen tours de café de dos a tres horas, de la planta al tostador, casi siempre con caña de azúcar y chocolate también. Si solo tiene veinte minutos, venga a probar la misma montaña en una taza: servimos café de El Trapiche y con gusto le contamos cómo se hace.' } },
  { id: 'beans', en: { q: 'Can I buy Monteverde coffee beans to take home?',
      a: 'Ask at the counter. We sell what we brew when we have it, whole bean or ground, and we can tell you which farm it comes from and when it was roasted. It packs flat in a suitcase and it is the souvenir people write to us about.' },
    es: { q: '¿Puedo comprar café de Monteverde en grano para llevar a casa?',
      a: 'Pregunte en el mostrador. Vendemos lo mismo que servimos cuando lo tenemos, en grano o molido, y le decimos de qué finca viene y cuándo se tostó. Cabe plano en la maleta y es el recuerdo por el que la gente nos escribe.' } },
  { id: 'rain', en: { q: 'What can I do in Monteverde when it rains?',
      a: 'Let it rain, this is a cloud forest. A hot chocolate or a Cloud Forest Latte under the hanging plants is the local way to wait it out, and the forest is at its greenest right after. Our rainy day guide lists what stays open and what is better in the mist.' },
    es: { q: '¿Qué puedo hacer en Monteverde cuando llueve?',
      a: 'Que llueva, esto es un bosque nuboso. Un chocolate caliente o un Cloud Forest Latte bajo las plantas colgantes es la forma local de esperar, y el bosque está más verde justo después. Nuestra guía de días de lluvia dice qué sigue abierto y qué es mejor con neblina.' } },
  { id: 'view', en: { q: 'Do you have garden seating or a view?',
      a: 'Our tables sit under hanging plants, ferns and flowers, with the cloud forest air coming through. It is a garden more than a view: hummingbirds visit, and on clear afternoons the light comes in sideways through the mist.' },
    es: { q: '¿Tienen mesas en el jardín o vista?',
      a: 'Nuestras mesas están bajo plantas colgantes, helechos y flores, con el aire del bosque nuboso entrando. Es más jardín que vista: los colibríes visitan, y en las tardes despejadas la luz entra de lado a través de la neblina.' } },
  { id: 'cold', en: { q: 'Is Monteverde cold? What should I wear?',
      a: 'Cool, not cold: about 15 to 22 °C most of the year, with mist and wind. Bring layers and a light rain jacket even on sunny mornings. Then come in for something hot; we have coffee, tea and Costa Rican hot chocolate.' },
    es: { q: '¿Hace frío en Monteverde? ¿Qué debo llevar?',
      a: 'Fresco, no frío: unos 15 a 22 °C casi todo el año, con neblina y viento. Lleve capas y una capa ligera de lluvia incluso en mañanas soleadas. Luego pase por algo caliente; tenemos café, té y chocolate caliente costarricense.' } },

  /* practical */
  { id: 'pay', en: { q: 'Do you accept credit cards, US dollars and colones?',
      a: 'Yes to all three. Prices are in colones; we also take dollars at the counter, cards, and SINPE Móvil. Change is given in colones.' },
    es: { q: '¿Aceptan tarjetas, dólares y colones?',
      a: 'Sí, los tres. Los precios están en colones; también aceptamos dólares en el mostrador, tarjetas y SINPE Móvil. El vuelto se da en colones.' } },
  { id: 'wifi', en: { q: 'Do you have wifi? Can I work on my laptop?',
      a: 'Yes, there is free wifi for guests; ask at the counter for the password. You are welcome to work a while. Mornings are the quietest and there are some outlets.' },
    es: { q: '¿Tienen wifi? ¿Puedo trabajar con mi computadora?',
      a: 'Sí, hay wifi gratis para visitantes; pida la clave en el mostrador. Puede venir a trabajar un rato. Las mañanas son lo más tranquilo y hay algunos enchufes.' } },
  { id: 'milk', en: { q: 'Do you have oat milk, almond milk or lactose free milk?',
      a: 'We have lactose free milk for any coffee or hot chocolate, just ask. We do not stock oat or almond milk. Every smoothie can be made in water instead of milk.' },
    es: { q: '¿Tienen leche de avena, de almendra o deslactosada?',
      a: 'Tenemos leche deslactosada para cualquier café o chocolate caliente, solo pídala. No tenemos leche de avena ni de almendra. Todos los batidos se pueden hacer en agua en vez de leche.' } },
  { id: 'decaf', en: { q: 'Do you have decaf?',
      a: 'No, we do not serve decaf. Our coffee is arabica from Monteverde, which is naturally lower in caffeine than most supermarket blends. For no caffeine at all, try the tea, the Costa Rican hot chocolate or a garden smoothie.' },
    es: { q: '¿Tienen descafeinado?',
      a: 'No, no servimos descafeinado. Nuestro café es arábica de Monteverde, que por naturaleza tiene menos cafeína que la mayoría de las mezclas de supermercado. Si no quiere nada de cafeína, pruebe el té, el chocolate caliente costarricense o un batido del jardín.' } },
  { id: 'diet', en: { q: 'Do you have gluten free, vegan or vegetarian options?',
      a: 'Vegetarian, yes: the Monteverde sandwich, most pastries, drinks and smoothies. Vegan: smoothies in water, americano, tea and the sweet cane drink. Our kitchen is small, so we cannot promise zero contact with gluten; tell the team when you order and they will guide you.' },
    es: { q: '¿Tienen opciones sin gluten, veganas o vegetarianas?',
      a: 'Vegetarianas, sí: el sándwich Monteverde, casi toda la repostería, las bebidas y los batidos. Veganas: batidos en agua, americano, té y agua dulce. Nuestra cocina es pequeña, así que no podemos prometer cero contacto con gluten; avise al equipo al ordenar y le orientan.' } },
  { id: 'dogs', en: { q: 'Is the café dog friendly?',
      a: 'Well behaved dogs are welcome at the garden tables, and we will find them a bowl of water.' },
    es: { q: '¿Se puede ir con perro?',
      a: 'Los perros educados son bienvenidos en las mesas del jardín, y les buscamos un tazón de agua.' } },
  { id: 'kids', en: { q: 'Is it good for kids?',
      a: 'Very. The garden gives children room to look at plants and hummingbirds, and the Costa Rican hot chocolate was practically made for them.' },
    es: { q: '¿Es bueno para niños?',
      a: 'Mucho. El jardín les da espacio para mirar plantas y colibríes, y el chocolate caliente costarricense es casi para ellos.' } },
  { id: 'parking', en: { q: 'Is there parking?',
      a: 'Yes, free street parking right by the café. Mornings before 7:00 are the easiest time to find a spot.' },
    es: { q: '¿Hay parqueo?',
      a: 'Sí, hay parqueo gratis en la calle junto al café. Antes de las 7:00 es la hora más fácil para encontrar campo.' } },
  { id: 'book', en: { q: 'Can I book a table, or bring a group?',
      a: 'No reservation needed, just come in. For groups of eight or more, or a small celebration, message us on WhatsApp a day ahead and we will set the garden for you.' },
    es: { q: '¿Puedo reservar mesa o venir en grupo?',
      a: 'No necesita reserva, solo llegue. Para grupos de ocho o más, o una celebración pequeña, escríbanos por WhatsApp un día antes y le acomodamos el jardín.' } },
  { id: 'togo', en: { q: 'Do you do takeaway, and can I order on WhatsApp?',
      a: 'Everything on the menu travels well; just ask for it to go. To order ahead, write to us on WhatsApp at +506 6400 6601 and tell us when you will pick it up.' },
    es: { q: '¿Tienen para llevar y puedo pedir por WhatsApp?',
      a: 'Todo el menú viaja bien; solo pídalo para llevar. Para pedir con anticipación, escríbanos por WhatsApp al +506 6400 6601 y díganos a qué hora lo recoge.' } },
  { id: 'sunday', en: { q: 'Are you open on Sundays and holidays?',
      a: 'Yes. We open every day of the week, 6:00 to 19:00, holidays included. If a storm or a special day changes that, we post it on our Google profile first.' },
    es: { q: '¿Abren domingos y feriados?',
      a: 'Sí. Abrimos todos los días de la semana, de 6:00 a 19:00, feriados incluidos. Si una tormenta o un día especial cambia eso, lo publicamos primero en nuestro perfil de Google.' } },
  { id: 'bath', en: { q: 'Is there a bathroom?',
      a: 'Yes, we have restrooms for guests.' },
    es: { q: '¿Hay baño?',
      a: 'Sí, tenemos baños para visitantes.' } },
  { id: 'tip', en: { q: 'Is tipping expected in Costa Rica?',
      a: 'Tips are never expected in Costa Rica and always appreciated. If someone made your morning, a small extra says so.' },
    es: { q: '¿Se deja propina en Costa Rica?',
      a: 'La propina nunca es obligatoria en Costa Rica y siempre se agradece. Si alguien le alegró la mañana, un poco extra lo dice.' } },
  { id: 'english', en: { q: 'Do you speak English?',
      a: 'English y español, con mucho gusto. The menu, this website and our team speak both.' },
    es: { q: '¿Hablan inglés?',
      a: 'English y español, con mucho gusto. El menú, este sitio y nuestro equipo hablan los dos.' } }
];

/* ------------------------------------------------------------------ */
/*  Pages                                                               */
/*  Each page: slug per language, title, description, kicker, h1,      */
/*  lede, sections [{ id, h, p: [..], img?: {src, alt} }],             */
/*  and optional faq (question sections are also written as FAQ).      */
/* ------------------------------------------------------------------ */

const IMG = {
  canopy: 'assets/canopy.jpg',
  quetzal: 'assets/quetzal.jpg',
  cup: 'assets/gal-1.jpg',
  pastry: 'assets/gal-2.jpg',
  pour: 'assets/gal-3.jpg',
  garden: 'assets/gal-4.jpg',
  building: 'assets/hero-ending.jpg',
  poster: 'assets/hero-poster.jpg'
};

const PAGES = [
  /* ---------------- OUR COFFEE ---------------- */
  {
    key: 'coffee', type: 'article',
    en: {
      slug: 'coffee.html', nav: 'Our coffee',
      title: 'Our coffee: why Monteverde altitude makes it sweeter · Hanging Garden Café',
      description: 'What makes Monteverde coffee taste the way it does: 1,400 metres of altitude, hand picking, honey and washed processing, local roasting, and the chorreado. Plain answers from Hanging Garden Café.',
      kicker: 'Our coffee', h1: 'Why coffee from 1,400 metres tastes sweeter',
      lede: 'Every cup at Hanging Garden Café comes from this mountain. Here are the questions people ask us at the counter, answered the way we answer them there: short, honest, and with the farm in mind.',
      readTime: '7 min read',
      sections: [
        { id: 'altitude', h: 'Why does altitude make coffee sweeter?', img: { src: IMG.canopy, alt: 'Mist moving through the Monteverde cloud forest canopy at dawn' },
          p: ['Monteverde sits at about 1,400 metres above the sea. Up here nights are cool, so the coffee cherry ripens slowly, sometimes over nine months instead of six. A slow cherry has time to build sugar and acidity, and the bean inside grows dense and hard.',
              'In the cup that means sweetness, a clean finish, and flavours that stay separate instead of blurring together: chocolate, orange, sometimes a little honey. Low grown coffee, by comparison, tends to taste flat and heavy.'] },
        { id: 'shb', h: 'What does SHB, strictly hard bean, mean?',
          p: ['SHB is the top grade of Costa Rican coffee. It is given to beans grown above roughly 1,200 metres, where the slow ripening makes them hard and dense. Hard beans roast more evenly and carry more flavour.',
              'Monteverde is well above that line, so the coffee we serve qualifies. When you see SHB on a bag of Costa Rican coffee, it is telling you where the farm sits, not how it was roasted.'] },
        { id: 'harvest', h: 'How and when is the coffee harvested?', img: { src: IMG.poster, alt: 'Red coffee cherries on the plant in Monteverde, ready to be picked by hand' },
          p: ['By hand, one cherry at a time. On the steep slopes of Monteverde a machine would be useless anyway, so pickers walk the rows several times between roughly December and March and take only the cherries that have turned deep red.',
              'A green cherry picked early tastes sour; an overripe one tastes like fermentation. Picking only the red ones is slow and expensive, and it is the single biggest reason a small farm coffee tastes better than a supermarket blend.'] },
        { id: 'process', h: 'Washed, honey or natural: what does the process change?',
          p: ['After picking, the fruit has to come off the bean. Washed coffee has the pulp and the sticky layer removed with water before drying: the cleanest, brightest cup. Natural coffee dries inside the whole cherry: fruity, heavy, wine like.',
              'Honey process, which Costa Rica made famous, is in between. The skin comes off but some of the sticky "honey" stays on the bean while it dries, giving sweetness and body without losing clarity. Ask which process the coffee of the day went through; we like to tell you.'] },
        { id: 'roast', h: 'Light, medium or dark roast: which do you serve and why?', img: { src: IMG.cup, alt: 'A freshly brewed cup of Monteverde coffee served at the garden' },
          p: ['Medium, most of the time. A light roast can taste sharp for coffee this bright, and a dark roast burns away the sweetness the mountain worked nine months to build. Medium keeps the chocolate and the citrus and still feels like coffee at six in the morning.',
              'Our coffee is roasted locally, in small batches, close to the farm it came from. Local roasting means we never serve a bag that has been sitting in a warehouse for a year.'] },
        { id: 'fresh', h: 'How fresh is the coffee, and where is it roasted?',
          p: ['We buy from El Trapiche, a family farm in Monteverde, and we grind for each cup. Coffee is at its best between one and four weeks after roasting; ground coffee starts losing aroma within minutes. That is why you will not find a pre ground pot waiting for you.'] },
        { id: 'arabica', h: 'Arabica or robusta, and why does it matter?',
          p: ['Arabica. For decades Costa Rican law allowed only arabica to be planted, and the mountains are still almost entirely arabica. Arabica has about half the caffeine of robusta and far more sweetness and aroma; robusta is the bitter, rubbery taste in cheap instant coffee.'] },
        { id: 'monteverde-tarrazu', h: 'What is the difference between Monteverde and Tarrazú coffee?',
          p: ['Tarrazú is the famous one: a big region south of San José, very high, with a bright, wine like acidity that wins competitions. Monteverde is a small region with fewer, smaller farms, grown in cloud forest weather.',
              'The difference in the cup is balance. Monteverde coffee tends to be rounder and sweeter, with chocolate and soft citrus, where Tarrazú can be sharper. Neither is better; Monteverde is simply rarer, because so little of it leaves the mountain.'] },
        { id: 'famous', h: 'Why is Costa Rican coffee famous?',
          p: ['Three reasons. Volcanic soil and mountain altitude, a two hundred year tradition of small family farms, and quality rules stricter than almost anywhere: only arabica, graded by altitude, with the honey process invented here. Costa Rica grows less than one percent of the world’s coffee, and most of it is very good.'] },
        { id: 'chorreado', h: 'What is a chorreado, and how is it made?', img: { src: IMG.pour, alt: 'Hot water poured slowly over coffee grounds in a cloth chorreador filter' },
          p: ['A chorreado is coffee made in a chorreador: a simple wooden stand holding a cloth bag. Ground coffee goes in the bag, hot water just off the boil is poured slowly over it, and the coffee drips into the cup below. The name comes from chorrear, to drip.',
              'Costa Ricans have brewed this way for two hundred years, and the cloth gives a cup that is softer and rounder than paper filter coffee, with more body. Our Café con Leche is a chorreado with warm milk. The cloth bag is never washed with soap, only rinsed; every Tica grandmother will tell you why.'] },
        { id: 'caffeine', h: 'How much caffeine is in a cup of coffee compared with an espresso?',
          p: ['A regular brewed cup of about 240 ml has around 95 mg of caffeine. A single espresso shot has around 63 mg, less than the cup, but in a fraction of the volume. A latte or cappuccino made with one shot therefore has less caffeine than an americano made with two. Decaf still carries a few milligrams.'] },
        { id: 'drinks', h: 'What is the difference between a latte, a cappuccino and a flat white?',
          p: ['All three are espresso and milk. A cappuccino is smaller, with a thick layer of foam on top. A latte is larger, mostly steamed milk with a thin foam. A flat white sits between them: espresso with velvety, barely foamed milk in a smaller cup, so the coffee comes through stronger.',
              'Our Cloud Forest Latte adds Costa Rican honey and cinnamon, hot or iced, and is the drink people come back for.'] },
        { id: 'cold', h: 'Do you serve iced coffee, and does it have more caffeine?',
          p: ['Yes: iced americano, iced latte and iced mocha. Iced coffee has the same caffeine as its hot version, because it is the same espresso poured over ice. Cold brew, which steeps for hours, can carry more; we brew fresh instead.'] },
        { id: 'home', h: 'How do I brew Costa Rican coffee at home, and how do I store the beans?',
          p: ['Buy whole beans, grind just before brewing, and use water just off the boil, about 93 °C. For a chorreador or a pour over, use about 60 grams of coffee per litre of water and pour slowly. Keep the beans in a closed container away from light and heat, never in the fridge, and finish the bag within a month of the roast date.'] }
      ],
      cta: { h: 'Taste it before you read more', p: 'We open at 6:00 every day. Come for a chorreado, a Cloud Forest Latte or a bag of beans to take home.' }
    },
    es: {
      slug: 'es/cafe.html', nav: 'Nuestro café',
      title: 'Nuestro café: por qué la altura de Monteverde lo hace más dulce · Hanging Garden Café',
      description: 'Qué hace que el café de Monteverde sepa como sabe: 1 400 metros de altura, recolección a mano, proceso honey y lavado, tueste local y el chorreado. Respuestas claras de Hanging Garden Café.',
      kicker: 'Nuestro café', h1: 'Por qué el café de 1 400 metros sabe más dulce',
      lede: 'Cada taza de Hanging Garden Café viene de esta montaña. Estas son las preguntas que nos hacen en el mostrador, respondidas como las respondemos ahí: cortas, honestas y pensando en la finca.',
      readTime: '7 min de lectura',
      sections: [
        { id: 'altura', h: '¿Por qué la altura hace el café más dulce?', img: { src: IMG.canopy, alt: 'Neblina moviéndose entre el dosel del bosque nuboso de Monteverde al amanecer' },
          p: ['Monteverde está a unos 1 400 metros sobre el mar. Aquí arriba las noches son frías, así que el fruto del café madura despacio, a veces nueve meses en vez de seis. Un fruto lento tiene tiempo de acumular azúcar y acidez, y el grano adentro crece denso y duro.',
              'En la taza eso significa dulzura, un final limpio y sabores que se mantienen separados en vez de mezclarse: chocolate, naranja, a veces un poco de miel. El café de zonas bajas, en cambio, suele saber plano y pesado.'] },
        { id: 'shb', h: '¿Qué significa SHB, strictly hard bean?',
          p: ['SHB es el grado más alto del café de Costa Rica. Se da a granos cultivados por encima de unos 1 200 metros, donde la maduración lenta los hace duros y densos. Los granos duros se tuestan más parejo y llevan más sabor.',
              'Monteverde está muy por encima de esa línea, así que el café que servimos califica. Cuando vea SHB en una bolsa de café costarricense, le está diciendo dónde queda la finca, no cómo se tostó.'] },
        { id: 'cosecha', h: '¿Cómo y cuándo se cosecha el café?', img: { src: IMG.poster, alt: 'Frutos rojos de café en la planta en Monteverde, listos para recolectarse a mano' },
          p: ['A mano, fruto por fruto. En las laderas empinadas de Monteverde una máquina no serviría de todos modos, así que los recolectores recorren las hileras varias veces entre diciembre y marzo, más o menos, y toman solo los frutos que están rojo intenso.',
              'Un fruto verde recogido antes de tiempo sabe ácido; uno pasado sabe a fermento. Recoger solo los rojos es lento y caro, y es la razón principal por la que el café de una finca pequeña sabe mejor que una mezcla de supermercado.'] },
        { id: 'proceso', h: 'Lavado, honey o natural: ¿qué cambia el proceso?',
          p: ['Después de la cosecha hay que quitarle la fruta al grano. En el café lavado se retira la pulpa y la capa pegajosa con agua antes de secar: la taza más limpia y brillante. El natural se seca dentro del fruto entero: afrutado, pesado, con algo de vino.',
              'El proceso honey, que Costa Rica hizo famoso, está en medio. Se quita la cáscara pero parte de la "miel" pegajosa se queda en el grano mientras seca, dando dulzura y cuerpo sin perder claridad. Pregunte por cuál proceso pasó el café del día; nos gusta contarlo.'] },
        { id: 'tueste', h: 'Tueste claro, medio u oscuro: ¿cuál sirven y por qué?', img: { src: IMG.cup, alt: 'Una taza de café de Monteverde recién preparada, servida en el jardín' },
          p: ['Medio, casi siempre. Un tueste claro puede saber filoso en un café tan brillante, y uno oscuro quema la dulzura que la montaña tardó nueve meses en construir. El medio conserva el chocolate y los cítricos y aun así se siente como café a las seis de la mañana.',
              'Nuestro café se tuesta localmente, en lotes pequeños, cerca de la finca de donde vino. Tostar aquí significa que nunca servimos una bolsa que pasó un año en una bodega.'] },
        { id: 'fresco', h: '¿Qué tan fresco es el café y dónde se tuesta?',
          p: ['Compramos a El Trapiche, una finca familiar de Monteverde, y molemos para cada taza. El café está en su mejor punto entre una y cuatro semanas después del tueste; el café molido empieza a perder aroma en minutos. Por eso no encontrará una jarra molida de antemano esperándolo.'] },
        { id: 'arabica', h: '¿Arábica o robusta, y por qué importa?',
          p: ['Arábica. Durante décadas la ley costarricense solo permitió sembrar arábica, y las montañas siguen siendo casi por completo arábica. El arábica tiene cerca de la mitad de la cafeína del robusta y mucha más dulzura y aroma; el robusta es el sabor amargo y a hule del café instantáneo barato.'] },
        { id: 'monteverde-tarrazu', h: '¿Cuál es la diferencia entre el café de Monteverde y el de Tarrazú?',
          p: ['Tarrazú es el famoso: una región grande al sur de San José, muy alta, con una acidez brillante, como de vino, que gana concursos. Monteverde es una región pequeña con menos fincas y más chicas, cultivada con el clima del bosque nuboso.',
              'La diferencia en la taza es el balance. El café de Monteverde tiende a ser más redondo y dulce, con chocolate y cítricos suaves, mientras que el de Tarrazú puede ser más filoso. Ninguno es mejor; Monteverde simplemente es más raro, porque muy poco sale de la montaña.'] },
        { id: 'famoso', h: '¿Por qué es famoso el café de Costa Rica?',
          p: ['Tres razones. Suelo volcánico y altura de montaña, doscientos años de tradición de fincas familiares pequeñas, y reglas de calidad más estrictas que casi en cualquier otro lugar: solo arábica, clasificado por altura, y el proceso honey inventado aquí. Costa Rica produce menos del uno por ciento del café del mundo, y casi todo es muy bueno.'] },
        { id: 'chorreado', h: '¿Qué es un chorreado y cómo se hace?', img: { src: IMG.pour, alt: 'Agua caliente vertida despacio sobre el café en la bolsa de tela de un chorreador' },
          p: ['Un chorreado es café hecho en un chorreador: un soporte de madera sencillo que sostiene una bolsa de tela. El café molido va en la bolsa, el agua recién hervida se vierte despacio encima, y el café gotea a la taza de abajo. El nombre viene de chorrear.',
              'Los costarricenses preparan café así desde hace doscientos años, y la tela da una taza más suave y redonda que el filtro de papel, con más cuerpo. Nuestro Café con Leche es un chorreado con leche caliente. La bolsa nunca se lava con jabón, solo se enjuaga; cualquier abuela tica le dirá por qué.'] },
        { id: 'cafeina', h: '¿Cuánta cafeína tiene una taza de café comparada con un espresso?',
          p: ['Una taza normal de unos 240 ml tiene cerca de 95 mg de cafeína. Un espresso sencillo tiene unos 63 mg, menos que la taza, pero en una fracción del volumen. Un latte o un capuchino con un solo shot tiene entonces menos cafeína que un americano con dos. El descafeinado todavía lleva unos pocos miligramos.'] },
        { id: 'bebidas', h: '¿Cuál es la diferencia entre un latte, un capuchino y un flat white?',
          p: ['Los tres son espresso con leche. El capuchino es más pequeño, con una capa gruesa de espuma encima. El latte es más grande, casi todo leche vaporizada con poca espuma. El flat white está en medio: espresso con leche aterciopelada, apenas espumada, en una taza más pequeña, así que el café se siente más fuerte.',
              'Nuestro Cloud Forest Latte agrega miel costarricense y canela, caliente o frío, y es la bebida por la que la gente vuelve.'] },
        { id: 'frio', h: '¿Sirven café frío y tiene más cafeína?',
          p: ['Sí: americano frío, latte frío y moca frío. El café frío tiene la misma cafeína que su versión caliente, porque es el mismo espresso servido sobre hielo. El cold brew, que reposa por horas, puede llevar más; nosotros preparamos fresco.'] },
        { id: 'casa', h: '¿Cómo preparo café costarricense en casa y cómo guardo el grano?',
          p: ['Compre grano entero, muela justo antes de preparar y use agua recién hervida, a unos 93 °C. Para chorreador o pour over, use unos 60 gramos de café por litro de agua y vierta despacio. Guarde el grano en un recipiente cerrado, lejos de la luz y el calor, nunca en la refrigeradora, y termine la bolsa antes de un mes desde la fecha de tueste.'] }
      ],
      cta: { h: 'Pruébelo antes de seguir leyendo', p: 'Abrimos a las 6:00 todos los días. Venga por un chorreado, un Cloud Forest Latte o una bolsa de grano para llevar a casa.' }
    }
  },

  /* ---------------- BEST COFFEE IN MONTEVERDE ---------------- */
  {
    key: 'best', type: 'article',
    en: {
      slug: 'best-coffee-monteverde.html', nav: 'Best coffee in Monteverde',
      title: 'Best coffee in Monteverde: how to find a great cup in Santa Elena · Hanging Garden Café',
      description: 'Looking for the best coffee in Monteverde, Costa Rica? Five signs of a great cup, where the coffee comes from, what to order, and why Hanging Garden Café opens at 6:00 for it.',
      kicker: 'Monteverde guide', h1: 'Where is the best coffee in Monteverde?',
      lede: 'Monteverde grows some of the best coffee in Costa Rica, and Santa Elena has more cafés per block than almost any town in the country. Here is how to tell a great cup from a tourist cup, and what to order once you find one.',
      readTime: '5 min read',
      sections: [
        { id: 'signs', h: 'Five signs you are about to drink a great cup', img: { src: IMG.pour, alt: 'Coffee being poured slowly at Hanging Garden Café in Monteverde' },
          p: ['One: they can name the farm. Coffee that is "from Monteverde" is fine; coffee from a farm they can point to on the mountain is better. Two: they grind for each cup. A pot of pre ground coffee waiting on a hot plate has lost most of its aroma.',
              'Three: the roast is recent, weeks not months, and they will tell you the date if you ask. Four: they offer a chorreado, the cloth filter brew Costa Ricans have used for two hundred years. Five: the milk is steamed for your drink, not poured from a jug that has been foamed three times.'] },
        { id: 'ours', h: 'What we pour at Hanging Garden Café',
          p: ['We buy from El Trapiche, a family farm here in Monteverde, roasted locally in small batches. We grind for each cup, brew chorreado or espresso, and steam milk to order. That is the whole secret; the mountain does the rest.',
              'Try the Café con Leche if you want the Costa Rican classic, the Cloud Forest Latte with honey and cinnamon if you want ours, or a plain americano if you want to taste the farm with nothing in the way.'] },
        { id: 'why', h: 'Why Monteverde coffee tastes different',
          p: ['Altitude. At 1,400 metres the cherry ripens slowly and builds sugar, so the cup is sweet and clean with chocolate and citrus. Monteverde is also a small region: few farms, small harvests, and almost nothing exported, so a cup here is genuinely something you cannot buy at home. Our coffee page explains it in detail.'] },
        { id: 'tours', h: 'Coffee tours near Santa Elena', img: { src: IMG.canopy, alt: 'Cloud forest slopes above Santa Elena where Monteverde coffee farms sit' },
          p: ['If you have half a day, several family farms run coffee tours around Monteverde, usually two to three hours, often combined with sugar cane and chocolate. You will walk the plants, see the drying patios and the roaster, and taste at the end. Most hotels book them; go in the morning when it is drier.',
              'If you have twenty minutes, come and taste the same mountain here. We are happy to explain what you are drinking.'] },
        { id: 'early', h: 'The best coffee is the one you get before the reserve',
          p: ['The Monteverde Cloud Forest Reserve opens at 7:00, and the best birding is in the first hour. Most cafés in Santa Elena open at 7:00 or later. We open at 6:00 every day, so you can have a proper coffee and something warm, and still be at the gate when it opens.'] },
        { id: 'beans', h: 'Taking Monteverde coffee home',
          p: ['Ask at the counter for beans. Whole bean keeps better than ground; buy the smallest bag you will finish within a month, keep it sealed and out of the light, and grind just before brewing. It packs flat and it is the souvenir that gets used.'] }
      ],
      cta: { h: 'Come and judge for yourself', p: 'Every day from 6:00 to 19:00, on the road through Santa Elena. Coffee, breakfast and a garden between the clouds.' }
    },
    es: {
      slug: 'es/mejor-cafe-monteverde.html', nav: 'El mejor café de Monteverde',
      title: 'El mejor café de Monteverde: cómo encontrar una gran taza en Santa Elena · Hanging Garden Café',
      description: '¿Busca el mejor café de Monteverde, Costa Rica? Cinco señales de una gran taza, de dónde viene el café, qué pedir y por qué Hanging Garden Café abre a las 6:00 para eso.',
      kicker: 'Guía de Monteverde', h1: '¿Dónde está el mejor café de Monteverde?',
      lede: 'Monteverde produce parte del mejor café de Costa Rica, y Santa Elena tiene más cafeterías por cuadra que casi cualquier pueblo del país. Aquí le decimos cómo distinguir una gran taza de una taza para turistas, y qué pedir cuando la encuentre.',
      readTime: '5 min de lectura',
      sections: [
        { id: 'senales', h: 'Cinco señales de que va a tomar una gran taza', img: { src: IMG.pour, alt: 'Café servido despacio en Hanging Garden Café en Monteverde' },
          p: ['Uno: pueden decirle el nombre de la finca. Un café "de Monteverde" está bien; un café de una finca que pueden señalar en la montaña está mejor. Dos: muelen para cada taza. Una jarra de café molido de antemano sobre una plancha caliente ya perdió casi todo el aroma.',
              'Tres: el tueste es reciente, semanas y no meses, y le dicen la fecha si pregunta. Cuatro: ofrecen chorreado, el café de bolsa de tela que los costarricenses usan desde hace doscientos años. Cinco: la leche se vaporiza para su bebida, no se sirve de una jarra espumada tres veces.'] },
        { id: 'nuestro', h: 'Lo que servimos en Hanging Garden Café',
          p: ['Compramos a El Trapiche, una finca familiar aquí en Monteverde, tostado localmente en lotes pequeños. Molemos para cada taza, preparamos chorreado o espresso y vaporizamos la leche al momento. Ese es todo el secreto; la montaña hace el resto.',
              'Pruebe el Café con Leche si quiere el clásico costarricense, el Cloud Forest Latte con miel y canela si quiere el nuestro, o un americano solo si quiere probar la finca sin nada en medio.'] },
        { id: 'porque', h: 'Por qué el café de Monteverde sabe diferente',
          p: ['Altura. A 1 400 metros el fruto madura despacio y acumula azúcar, así que la taza es dulce y limpia, con chocolate y cítricos. Monteverde además es una región pequeña: pocas fincas, cosechas chicas y casi nada de exportación, así que una taza aquí es de verdad algo que no puede comprar en casa. Nuestra página del café lo explica con detalle.'] },
        { id: 'tours', h: 'Tours de café cerca de Santa Elena', img: { src: IMG.canopy, alt: 'Laderas de bosque nuboso sobre Santa Elena donde están las fincas de café de Monteverde' },
          p: ['Si tiene medio día, varias fincas familiares hacen tours de café alrededor de Monteverde, normalmente de dos a tres horas, muchas veces combinados con caña de azúcar y chocolate. Caminará entre las plantas, verá los patios de secado y el tostador, y probará al final. Casi todos los hoteles los reservan; vaya en la mañana, cuando está más seco.',
              'Si tiene veinte minutos, venga a probar la misma montaña aquí. Con gusto le explicamos qué está tomando.'] },
        { id: 'temprano', h: 'El mejor café es el que toma antes de la reserva',
          p: ['La Reserva del Bosque Nuboso Monteverde abre a las 7:00, y la mejor hora para ver aves es la primera. Casi todas las cafeterías de Santa Elena abren a las 7:00 o después. Nosotros abrimos a las 6:00 todos los días, así que puede tomar un café como debe ser y algo caliente, y aun así estar en el portón cuando abre.'] },
        { id: 'grano', h: 'Llevarse café de Monteverde a casa',
          p: ['Pida grano en el mostrador. El grano entero se conserva mejor que el molido; compre la bolsa más pequeña que vaya a terminar en un mes, manténgala sellada y lejos de la luz, y muela justo antes de preparar. Cabe plano en la maleta y es el recuerdo que sí se usa.'] }
      ],
      cta: { h: 'Venga y juzgue usted mismo', p: 'Todos los días de 6:00 a 19:00, sobre la carretera que atraviesa Santa Elena. Café, desayuno y un jardín entre las nubes.' }
    }
  },

  /* ---------------- BREAKFAST BEFORE THE RESERVE ---------------- */
  {
    key: 'breakfast', type: 'article',
    en: {
      slug: 'breakfast-monteverde.html', nav: 'Breakfast before the reserve',
      title: 'Breakfast in Santa Elena before the cloud forest reserve, from 6:00 · Hanging Garden Café',
      description: 'Where to have breakfast in Santa Elena, Monteverde before the cloud forest reserve, the hanging bridges or a sunrise tour. Hanging Garden Café opens at 6:00 with coffee, sandwiches, empanadas and an Adventure Box to go.',
      kicker: 'Monteverde guide', h1: 'Breakfast in Santa Elena before the cloud forest',
      lede: 'The reserve gate opens at 7:00 and the quetzals do not wait. Here is how to eat well, early, and still be first on the trail.',
      readTime: '4 min read',
      sections: [
        { id: 'timing', h: 'When does the reserve open, and when should I leave Santa Elena?', img: { src: IMG.canopy, alt: 'Early morning mist over the Monteverde Cloud Forest Reserve' },
          p: ['The Monteverde Cloud Forest Reserve opens at 7:00 and is about ten minutes from Santa Elena by car or shuttle; the Santa Elena Reserve is a little further the other way. Birds are most active in the first two hours, and the mist usually lifts mid morning.',
              'Leave the centre of Santa Elena by 6:40 and you are at the gate when it opens. That leaves time for a real breakfast if the café opens early enough, which is the whole reason we open at 6:00.'] },
        { id: 'what', h: 'What to eat before a forest walk', img: { src: IMG.pastry, alt: 'Fresh pastries baked in the morning at Hanging Garden Café' },
          p: ['Something warm and something that lasts. A Café con Leche and a ham and cheese croissant, or a Mano de Piedra sandwich with Costa Rican beef and frijoles molidos if you want a proper Tico start. Empanadas travel well in a jacket pocket. Banana bread and a Costa Rican hot chocolate work for children who are not awake yet.',
              'Coffee and pastry, or sandwich and coffee, come as a combo and save ₡500.'] },
        { id: 'box', h: 'Leaving before we open? The Adventure Box',
          p: ['Sunrise tours and early shuttles leave before 6:00. Order an Adventure Box by 20:00 the night before, on WhatsApp or at the counter, and pick it up from 6:30: your sandwich, fresh fruit, a sweet treat, bottled water and a napkin, packed for the trail. Ham and Cheese or Monteverde ₡6,500; Mano de Piedra or Chicken Pesto ₡7,000.'] },
        { id: 'bridges', h: 'Breakfast before the hanging bridges or a zip line',
          p: ['The hanging bridges and the zip line parks are on the road out of Santa Elena and most open at 7:00 or 7:30. Same plan: a coffee and a sandwich here from 6:00, or an Adventure Box to eat at the park. Hot chocolate is the local cure for the cold on a 7:00 bridge.'] },
        { id: 'wear', h: 'What to wear at 6:00 in Monteverde',
          p: ['Layers. Mornings are about 15 °C with wind and mist, warming to 22 °C by midday. A light rain jacket, closed shoes, and a small bag for the layers you will take off. Our coffee is the other layer.'] },
        { id: 'after', h: 'And after the walk',
          p: ['Come back for the second coffee. The garden is warmest in the early afternoon, the smoothies are made with fruit from the lowlands, and the Tres Leches is the reward for having got up at 5:30.'] }
      ],
      cta: { h: 'Open at 6:00, every day', p: 'On the road through Santa Elena, ten minutes from the reserve. Message us on WhatsApp to order an Adventure Box for tomorrow.' }
    },
    es: {
      slug: 'es/desayuno-monteverde.html', nav: 'Desayuno antes de la reserva',
      title: 'Desayuno en Santa Elena antes de la reserva del bosque nuboso, desde las 6:00 · Hanging Garden Café',
      description: 'Dónde desayunar en Santa Elena, Monteverde antes de la reserva del bosque nuboso, los puentes colgantes o un tour al amanecer. Hanging Garden Café abre a las 6:00 con café, sándwiches, empanadas y una Adventure Box para llevar.',
      kicker: 'Guía de Monteverde', h1: 'Desayuno en Santa Elena antes del bosque nuboso',
      lede: 'El portón de la reserva abre a las 7:00 y los quetzales no esperan. Así se come bien, temprano, y se llega de primero al sendero.',
      readTime: '4 min de lectura',
      sections: [
        { id: 'hora', h: '¿A qué hora abre la reserva y a qué hora salgo de Santa Elena?', img: { src: IMG.canopy, alt: 'Neblina de la mañana sobre la Reserva del Bosque Nuboso Monteverde' },
          p: ['La Reserva del Bosque Nuboso Monteverde abre a las 7:00 y está a unos diez minutos de Santa Elena en carro o en transporte; la Reserva de Santa Elena queda un poco más lejos hacia el otro lado. Las aves están más activas en las primeras dos horas, y la neblina suele levantarse a media mañana.',
              'Salga del centro de Santa Elena a las 6:40 y está en el portón cuando abre. Eso deja tiempo para un desayuno de verdad si la cafetería abre lo bastante temprano, que es justo la razón por la que abrimos a las 6:00.'] },
        { id: 'que', h: 'Qué comer antes de una caminata en el bosque', img: { src: IMG.pastry, alt: 'Repostería fresca horneada en la mañana en Hanging Garden Café' },
          p: ['Algo caliente y algo que dure. Un Café con Leche y un croissant de jamón y queso, o un sándwich Mano de Piedra con carne costarricense y frijoles molidos si quiere un arranque bien tico. Las empanadas viajan bien en el bolsillo de la jacket. El pan de banano y un chocolate caliente costarricense funcionan para los niños que todavía no despiertan.',
              'Café con repostería, o sándwich con café, vienen en combo y ahorran ₡500.'] },
        { id: 'caja', h: '¿Sale antes de que abramos? La Adventure Box',
          p: ['Los tours al amanecer y los transportes tempranos salen antes de las 6:00. Pida una Adventure Box antes de las 20:00 la noche anterior, por WhatsApp o en el mostrador, y recójala desde las 6:30: su sándwich, fruta fresca, algo dulce, agua embotellada y servilleta, empacados para el sendero. Jamón y queso o Monteverde ₡6 500; Mano de Piedra o Chicken Pesto ₡7 000.'] },
        { id: 'puentes', h: 'Desayuno antes de los puentes colgantes o el canopy',
          p: ['Los puentes colgantes y los parques de canopy están sobre la carretera de salida de Santa Elena y casi todos abren a las 7:00 o 7:30. Mismo plan: un café y un sándwich aquí desde las 6:00, o una Adventure Box para comer en el parque. El chocolate caliente es la cura local para el frío en un puente a las 7:00.'] },
        { id: 'ropa', h: 'Qué ponerse a las 6:00 en Monteverde',
          p: ['Capas. Las mañanas están a unos 15 °C con viento y neblina, y suben a 22 °C al mediodía. Una capa ligera de lluvia, zapatos cerrados y un bolso pequeño para las capas que se va a quitar. Nuestro café es la otra capa.'] },
        { id: 'despues', h: 'Y después de la caminata',
          p: ['Vuelva por el segundo café. El jardín está más cálido a primera hora de la tarde, los batidos se hacen con fruta de las tierras bajas, y el Tres Leches es el premio por haberse levantado a las 5:30.'] }
      ],
      cta: { h: 'Abierto a las 6:00, todos los días', p: 'Sobre la carretera que atraviesa Santa Elena, a diez minutos de la reserva. Escríbanos por WhatsApp para pedir una Adventure Box para mañana.' }
    }
  },

  /* ---------------- RAINY DAY ---------------- */
  {
    key: 'rain', type: 'article',
    en: {
      slug: 'rainy-day-monteverde.html', nav: 'Rainy day in Monteverde',
      title: 'What to do in Monteverde when it rains: a cloud forest rainy day guide · Hanging Garden Café',
      description: 'Rain in Monteverde is normal and the forest is better for it. What stays open, what to wear, when it rains most, and where to sit with a hot chocolate while it passes: a rainy day guide from Hanging Garden Café.',
      kicker: 'Monteverde guide', h1: 'What to do in Monteverde when it rains',
      lede: 'It is called a cloud forest for a reason. Rain here is not bad luck, it is the point; here is how to enjoy the wet days instead of waiting them out in a hotel room.',
      readTime: '5 min read',
      sections: [
        { id: 'when', h: 'When does it rain in Monteverde?', img: { src: IMG.canopy, alt: 'Rain clouds and mist over the Monteverde cloud forest' },
          p: ['The rainy season runs from about May to November, with the heaviest afternoons in September and October. December to April is drier but windy, with mist blowing sideways through the trees, which locals call pelo de gato, cat hair rain.',
              'Most days, even in the wet season, the morning is clear and the rain arrives after lunch. Plan the forest for the morning and the café, the shops and the museums for the afternoon.'] },
        { id: 'forest', h: 'Should I still walk the reserve in the rain?',
          p: ['Yes. The trails are well kept and the canopy takes most of it. The forest is at its greenest, the frogs are out, and the crowds are not. Wear a rain jacket and closed shoes, put your phone in a bag, and walk slowly. Rain usually thins to mist within an hour.'] },
        { id: 'indoor', h: 'What stays open and dry',
          p: ['The hanging bridges and the zip lines run in the rain unless there is lightning. The butterfly and hummingbird gardens, the frog pond, the bat jungle and the orchid garden are mostly covered. A coffee or chocolate tour spends much of its time under a roof, which makes a rainy afternoon a good time for one.'] },
        { id: 'cafe', h: 'The Tico way: wait it out with something hot', img: { src: IMG.garden, alt: 'Tables under hanging plants and ferns at Hanging Garden Café, sheltered from the rain' },
          p: ['Costa Ricans do not fight the rain, they sit it out with a cafecito. Our tables sit under the hanging garden with the rain on the leaves around you. Order a Costa Rican hot chocolate, a Cloud Forest Latte with honey and cinnamon, or a Café con Leche and a warm empanada, and give it forty minutes. It nearly always passes.',
              'Children get the hot chocolate. Adults who have been on a cold bridge get the Tres Leches as well.'] },
        { id: 'wear', h: 'What to wear on a rainy day',
          p: ['A real rain jacket, not an umbrella; the wind makes umbrellas useless. Quick drying trousers, closed shoes with grip, and a dry layer in a bag for after. A small towel is the thing nobody packs and everybody wants.'] },
        { id: 'after', h: 'After the rain',
          p: ['The hour after a shower is the best hour in Monteverde: the light comes in low under the clouds, the hummingbirds return to the garden, and the air smells of wet forest and coffee. Stay for the second cup.'] }
      ],
      cta: { h: 'Rain or shine, 6:00 to 19:00', p: 'Under the hanging plants, on the road through Santa Elena. Come in wet, leave warm.' }
    },
    es: {
      slug: 'es/dia-de-lluvia-monteverde.html', nav: 'Día de lluvia en Monteverde',
      title: 'Qué hacer en Monteverde cuando llueve: guía para un día de lluvia en el bosque nuboso · Hanging Garden Café',
      description: 'Llover en Monteverde es normal y el bosque está mejor así. Qué sigue abierto, qué ponerse, cuándo llueve más y dónde sentarse con un chocolate caliente mientras pasa: una guía de días de lluvia de Hanging Garden Café.',
      kicker: 'Guía de Monteverde', h1: 'Qué hacer en Monteverde cuando llueve',
      lede: 'Se llama bosque nuboso por algo. La lluvia aquí no es mala suerte, es la gracia; así se disfrutan los días mojados en vez de esperarlos en el cuarto del hotel.',
      readTime: '5 min de lectura',
      sections: [
        { id: 'cuando', h: '¿Cuándo llueve en Monteverde?', img: { src: IMG.canopy, alt: 'Nubes de lluvia y neblina sobre el bosque nuboso de Monteverde' },
          p: ['La época lluviosa va más o menos de mayo a noviembre, con las tardes más fuertes en setiembre y octubre. De diciembre a abril es más seco pero con viento, con neblina que atraviesa los árboles de lado, lo que aquí se llama pelo de gato.',
              'Casi todos los días, incluso en época lluviosa, la mañana está despejada y la lluvia llega después del almuerzo. Planee el bosque para la mañana y la cafetería, las tiendas y los museos para la tarde.'] },
        { id: 'bosque', h: '¿Vale la pena caminar la reserva con lluvia?',
          p: ['Sí. Los senderos están bien cuidados y el dosel detiene casi toda el agua. El bosque está en su punto más verde, las ranas salen y la gente no. Lleve capa de lluvia y zapatos cerrados, guarde el teléfono en una bolsa y camine despacio. La lluvia casi siempre se vuelve neblina en una hora.'] },
        { id: 'techo', h: 'Qué sigue abierto y bajo techo',
          p: ['Los puentes colgantes y el canopy funcionan con lluvia a menos que haya rayos. Los jardines de mariposas y colibríes, el ranario, la jungla de murciélagos y el jardín de orquídeas están casi todos cubiertos. Un tour de café o de chocolate pasa buena parte del tiempo bajo techo, así que una tarde lluviosa es buen momento para uno.'] },
        { id: 'cafe', h: 'A lo tico: esperar con algo caliente', img: { src: IMG.garden, alt: 'Mesas bajo plantas colgantes y helechos en Hanging Garden Café, protegidas de la lluvia' },
          p: ['Los costarricenses no pelean con la lluvia, la esperan con un cafecito. Nuestras mesas están bajo el jardín colgante, con la lluvia sobre las hojas alrededor. Pida un chocolate caliente costarricense, un Cloud Forest Latte con miel y canela, o un Café con Leche con una empanada caliente, y dele cuarenta minutos. Casi siempre pasa.',
              'A los niños, chocolate caliente. A los adultos que vienen de un puente frío, también el Tres Leches.'] },
        { id: 'ropa', h: 'Qué ponerse en un día de lluvia',
          p: ['Una capa de lluvia de verdad, no sombrilla; el viento las vuelve inútiles. Pantalón de secado rápido, zapatos cerrados con agarre, y una muda seca en una bolsa para después. Una toalla pequeña es lo que nadie empaca y todos quieren.'] },
        { id: 'despues', h: 'Después de la lluvia',
          p: ['La hora después de un aguacero es la mejor hora de Monteverde: la luz entra baja bajo las nubes, los colibríes vuelven al jardín y el aire huele a bosque mojado y a café. Quédese para la segunda taza.'] }
      ],
      cta: { h: 'Llueva o no, de 6:00 a 19:00', p: 'Bajo las plantas colgantes, sobre la carretera que atraviesa Santa Elena. Entre mojado, salga caliente.' }
    }
  },

  /* ---------------- MENU ---------------- */
  {
    key: 'menu', type: 'menu',
    en: {
      slug: 'menu.html', nav: 'Menu',
      title: 'Menu and prices · Hanging Garden Café, Monteverde',
      description: 'The full menu of Hanging Garden Café in Monteverde, Costa Rica with prices in colones: specialty coffee from El Trapiche, chorreado, sandwiches, empanadas, pastries, Costa Rican favourites and garden smoothies. Open 6:00 to 19:00.',
      kicker: 'Specialty coffee · Fresh food', h1: 'The menu',
      lede: 'Proudly serving locally grown coffee from El Trapiche Monteverde. Prices in colones; we also take dollars, cards and SINPE Móvil at the counter.',
      notes: [
        'Coffee + pastry, or sandwich + coffee: save ₡500 as a combo.',
        'Adventure Box for the trail: your sandwich, fresh fruit, a sweet treat, bottled water and a napkin. Order by 20:00, pick up from 6:30. Ham & Cheese or Monteverde ₡6,500 · Mano de Piedra or Chicken Pesto ₡7,000.',
        'Today’s Garden Special changes with the season. Ask what is blooming today.'
      ],
      cta: { h: 'Order ahead on WhatsApp', p: 'Write to us at +506 6400 6601 with your order and the time you will pick it up.' }
    },
    es: {
      slug: 'es/menu.html', nav: 'Menú',
      title: 'Menú y precios · Hanging Garden Café, Monteverde',
      description: 'El menú completo de Hanging Garden Café en Monteverde, Costa Rica con precios en colones: café de especialidad de El Trapiche, chorreado, sándwiches, empanadas, repostería, favoritos costarricenses y batidos del jardín. Abierto de 6:00 a 19:00.',
      kicker: 'Café de especialidad · Comida fresca', h1: 'El menú',
      lede: 'Servimos con orgullo café cultivado localmente en El Trapiche Monteverde. Precios en colones; también aceptamos dólares, tarjetas y SINPE Móvil en el mostrador.',
      notes: [
        'Café + repostería, o sándwich + café: ahorre ₡500 en combo.',
        'Adventure Box para el sendero: su sándwich, fruta fresca, algo dulce, agua embotellada y servilleta. Pídala antes de las 20:00 y recójala desde las 6:30. Jamón y queso o Monteverde ₡6 500 · Mano de Piedra o Chicken Pesto ₡7 000.',
        'El Especial del Jardín de hoy cambia con la temporada. Pregunte qué está floreciendo hoy.'
      ],
      cta: { h: 'Pida con anticipación por WhatsApp', p: 'Escríbanos al +506 6400 6601 con su pedido y la hora a la que lo recoge.' }
    }
  }
];

/* words the templates need in both languages */
const UI = {
  en: {
    home: 'Home', menu: 'Menu', coffee: 'Our coffee', story: 'Story', visit: 'Plan your visit', guides: 'Monteverde guides',
    inThisPage: 'In this page', updated: 'Updated', readNext: 'Read next', backHome: 'Back to the café',
    seeMenu: 'See the menu', whatsapp: 'Message us on WhatsApp', directions: 'Get directions', review: 'Leave a review on Google',
    hours: 'Every day 6:00 – 19:00', address: 'Monteverde, on the road through Santa Elena, Puntarenas, Costa Rica',
    footer1: '100% Costa Rican coffee · Locally sourced · Proudly serving coffee from El Trapiche Monteverde',
    footer2: 'Thank you for supporting our community and our forest. Pura vida.',
    faqTitle: 'Questions people ask before they visit', faqKicker: 'Good to know',
    faqLede: 'Hours, coffee, payment, what to wear: the answers we give at the counter, here before you arrive.',
    guidesTitle: 'Read before you come', guidesKicker: 'Monteverde guides',
    langAlt: 'Versión en español', menuSections: 'Sections', backTop: 'Back to top', menuPage: 'Open the menu as its own page'
  },
  es: {
    home: 'Inicio', menu: 'Menú', coffee: 'Nuestro café', story: 'Historia', visit: 'Planee su visita', guides: 'Guías de Monteverde',
    inThisPage: 'En esta página', updated: 'Actualizado', readNext: 'Siga leyendo', backHome: 'Volver al café',
    seeMenu: 'Ver el menú', whatsapp: 'Escríbanos por WhatsApp', directions: 'Cómo llegar', review: 'Deje una reseña en Google',
    hours: 'Todos los días 6:00 – 19:00', address: 'Monteverde, sobre la carretera que atraviesa Santa Elena, Puntarenas, Costa Rica',
    footer1: 'Café 100 % costarricense · De origen local · Servimos con orgullo café de El Trapiche Monteverde',
    footer2: 'Gracias por apoyar a nuestra comunidad y a nuestro bosque. Pura vida.',
    faqTitle: 'Preguntas que la gente hace antes de visitar', faqKicker: 'Bueno saberlo',
    faqLede: 'Horario, café, pagos, qué ponerse: las respuestas que damos en el mostrador, aquí antes de que llegue.',
    guidesTitle: 'Lea antes de venir', guidesKicker: 'Guías de Monteverde',
    langAlt: 'English version', menuSections: 'Secciones', backTop: 'Volver arriba', menuPage: 'Abrir el menú en su propia página'
  }
};

module.exports = { SITE, CAFE, WHATSAPP, PHONE, MAPS, REVIEW_URL, UPDATED, FAQ, PAGES, UI, IMG };
