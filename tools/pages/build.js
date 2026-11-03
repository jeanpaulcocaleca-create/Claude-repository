#!/usr/bin/env node
/* Builds the search pages of hanginggardencafe.com from tools/pages/content.js
     node tools/pages/build.js
   Writes: website/coffee.html, website/best-coffee-monteverde.html, website/breakfast-monteverde.html,
           website/rainy-day-monteverde.html, website/menu.html and their Spanish twins under website/es/,
           the FAQ + guide cards + FAQ markup inside website/index.html (between the faq / guides markers),
           the FAQ dictionary block inside website/lang.js, and website/sitemap.xml.
   The menu page is read from the menu on the home page, so prices live in one place. */
'use strict';
const fs = require('fs');
const path = require('path');
const C = require('./content.js');

const ROOT = path.join(__dirname, '..', '..', 'website');
const read = f => fs.readFileSync(path.join(ROOT, f), 'utf8');
const write = (f, s) => { const p = path.join(ROOT, f); fs.mkdirSync(path.dirname(p), { recursive: true }); fs.writeFileSync(p, s); console.log('wrote', f, s.length); };
const esc = s => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const unesc = s => String(s).replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'");
const ld = o => '<script type="application/ld+json">\n' + JSON.stringify(o, null, 1).replace(/<\//g, '<\\/') + '\n</script>';

/* ---------- the dictionary in lang.js, for the Spanish menu ---------- */
const langSrc = read('lang.js');
const dStart = langSrc.indexOf('var D = {');
const dEnd = langSrc.indexOf('\n  };', dStart);
const D = new Function('return ' + langSrc.slice(dStart + 8, dEnd + 4))();
function es(k) {
  if (D[k]) return D[k];
  if (k.indexOf(' · ') > 0) { let any = false; const parts = k.split(' · ').map(p => { const x = D[p.trim()]; if (x) { any = true; return x; } return p; }); if (any) return parts.join(' · '); }
  const m = k.match(/^(.*?)( \(.*\))$/); if (m && D[m[1]]) return D[m[1]] + (D[m[2].trim()] ? ' ' + D[m[2].trim()] : m[2]);
  return k;
}

/* ---------- the menu, read from the home page ---------- */
const index = read('index.html');
const menu = [];
{
  const block = index.slice(index.indexOf('<div class="menu-grid part">'), index.indexOf('<div class="feature-row part">'));
  let cat = null;
  for (const line of block.split('\n')) {
    const h = line.match(/<\/svg>(.*?)<\/h3>/);
    if (h) { cat = { name: unesc(h[1].trim()), items: [] }; menu.push(cat); continue; }
    const nm = line.match(/<span class="nm">(.*?)<\/span>/);
    if (nm && cat) {
      const pr = line.match(/<span class="price">(.*?)<\/span>/);
      const ds = line.match(/<div class="ds">(.*?)<\/div>/);
      cat.items.push({ name: unesc(nm[1]), price: unesc(pr ? pr[1] : ''), desc: unesc(ds ? ds[1] : '') });
    }
  }
}
if (menu.length < 5) throw new Error('menu not found in index.html');
const priceNumber = p => (p.match(/[\d ]+/) || [''])[0].replace(/\s/g, '');

/* ---------- pieces ---------- */
function pageUrl(p, lang) { return C.SITE + '/' + p[lang].slug; }
function rel(lang, target) { return (lang === 'es' ? '../' : '') + target; }   /* from a page to a root file */

function nav(lang, self) {
  const u = C.UI[lang];
  const menuP = C.PAGES.find(p => p.key === 'menu'), coffeeP = C.PAGES.find(p => p.key === 'coffee');
  const home = rel(lang, 'index.html');
  return `<nav id="nav" class="solid">
  <a class="navlogo" href="${home}"><b>Hanging Garden</b><span>Café · Monteverde</span></a>
  <div class="navlinks">
    <a href="${rel(lang, menuP[lang].slug)}"${self === 'menu' ? ' aria-current="page"' : ''}>${u.menu}</a>
    <a href="${rel(lang, coffeeP[lang].slug)}"${self === 'coffee' ? ' aria-current="page"' : ''}>${u.coffee}</a>
    <a href="${home}#story">${u.story}</a>
    <a class="cta" href="${home}#visit">${u.visit}</a>
  </div>
</nav>`;
}

function footer(lang) {
  const u = C.UI[lang];
  const links = C.PAGES.map(p => `<a href="${rel(lang, p[lang].slug)}">${esc(p[lang].nav)}</a>`).join(' · ');
  return `<footer>
  <svg class="cup" viewBox="0 0 100 80" aria-hidden="true"><path d="M15 20h50v22a18 18 0 01-18 18H33a18 18 0 01-18-18zM65 26h9a9 9 0 010 18h-9" fill="none" stroke="currentColor" stroke-width="7"/><path d="M33 2c-2 5 2 7 0 12M47 2c-2 5 2 7 0 12" fill="none" stroke="currentColor" stroke-width="5" stroke-linecap="round" opacity=".6"/></svg>
  <p><b>${C.CAFE}</b> · Monteverde, Costa Rica · <a href="${C.WHATSAPP}" target="_blank" rel="noopener">${C.PHONE}</a></p>
  <p>${u.hours} · ${u.address}</p>
  <p>${u.footer1}</p>
  <p class="flinks">${links} · <a href="${C.REVIEW_URL}" target="_blank" rel="noopener">${u.review}</a></p>
  <p>${u.footer2}</p>
</footer>`;
}

function ctaBlock(lang, cta) {
  const u = C.UI[lang], menuP = C.PAGES.find(p => p.key === 'menu');
  return `<aside class="cta">
  <h2>${esc(cta.h)}</h2>
  <p>${esc(cta.p)}</p>
  <p class="btns"><a class="btn light" href="${rel(lang, menuP[lang].slug)}">${u.seeMenu}</a> <a class="btn wa" href="${C.WHATSAPP}" target="_blank" rel="noopener">${u.whatsapp}</a> <a class="btn ghost" href="${C.MAPS}" target="_blank" rel="noopener">${u.directions}</a></p>
</aside>`;
}

function readNext(lang, selfKey) {
  const u = C.UI[lang];
  const cards = C.PAGES.filter(p => p.key !== selfKey).map(p => {
    const L = p[lang];
    return `<a class="gcard" href="${rel(lang, L.slug)}"><span class="gk">${esc(L.kicker)}</span><strong>${esc(L.h1)}</strong><span class="gd">${esc(L.description.split('. ')[0])}.</span></a>`;
  }).join('\n    ');
  return `<section class="next">
  <p class="kicker mono">${u.readNext}</p>
  <div class="gcards">
    ${cards}
  </div>
</section>`;
}

function shell(p, lang, body, extraLd, ogImage) {
  const L = p[lang], A = p[lang === 'en' ? 'es' : 'en'], u = C.UI[lang];
  const self = pageUrl(p, lang), alt = pageUrl(p, lang === 'en' ? 'es' : 'en');
  const enUrl = pageUrl(p, 'en'), esUrl = pageUrl(p, 'es');
  const base = rel(lang, '');
  const img = C.SITE + '/' + (ogImage || C.IMG.building);
  const crumbs = ld({ '@context': 'https://schema.org', '@type': 'BreadcrumbList', itemListElement: [
    { '@type': 'ListItem', position: 1, name: C.CAFE, item: C.SITE + '/' },
    { '@type': 'ListItem', position: 2, name: L.h1, item: self }] });
  return `<!DOCTYPE html>
<html lang="${lang}">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${esc(L.title)}</title>
<meta name="description" content="${esc(L.description)}">
<link rel="canonical" href="${self}">
<link rel="alternate" hreflang="en" href="${enUrl}">
<link rel="alternate" hreflang="es" href="${esUrl}">
<link rel="alternate" hreflang="x-default" href="${enUrl}">
<meta name="theme-color" content="#F6F1E2">
<meta property="og:title" content="${esc(L.h1)} · ${C.CAFE}">
<meta property="og:description" content="${esc(L.description)}">
<meta property="og:url" content="${self}">
<meta property="og:image" content="${img}">
<meta property="og:type" content="article">
<meta property="og:site_name" content="${C.CAFE}">
<meta property="og:locale" content="${lang === 'es' ? 'es_CR' : 'en_US'}">
<meta property="og:locale:alternate" content="${lang === 'es' ? 'en_US' : 'es_CR'}">
<link rel="icon" type="image/png" href="${base}assets/logo-512.png">
<link rel="apple-touch-icon" href="${base}assets/logo-512.png">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Playfair+Display:wght@500;600;700&family=Figtree:wght@400;600&family=Dancing+Script:wght@600&family=Spline+Sans+Mono:wght@400&display=swap">
<link rel="stylesheet" href="${base}page.css">
${crumbs}
${extraLd}
<script>
/* This page exists in English and Spanish at two addresses. Honour the language chosen on the site. */
(function(){var P='${lang}',ALT='${rel(lang, A.slug)}';try{var s=localStorage.getItem('hg_lang');if(s&&s!==P){location.replace(ALT);return;}if(!s)localStorage.setItem('hg_lang',P);}catch(e){}
document.addEventListener('hg-lang',function(e){if(e.detail&&e.detail!==P)location.href=ALT;});})();
</script>
</head>
<body data-no-translate>
<a class="skip" href="#main">${lang === 'es' ? 'Ir al contenido' : 'Skip to content'}</a>
<div class="env" aria-hidden="true"></div>
${nav(lang, p.key)}
<main id="main" tabindex="-1">
${body}
${readNext(lang, p.key)}
</main>
${footer(lang)}
<script src="${base}lang.js"></script>
</body>
</html>
`;
}

/* ---------- article pages ---------- */
function article(p, lang) {
  const L = p[lang], u = C.UI[lang];
  const toc = L.sections.map(s => `<li><a href="#${s.id}">${esc(s.h)}</a></li>`).join('\n      ');
  const secs = L.sections.map(s => {
    const fig = s.img ? `\n    <figure><img src="${rel(lang, s.img.src)}" alt="${esc(s.img.alt)}" loading="lazy" width="1600" height="900"></figure>` : '';
    return `  <section id="${s.id}">
    <h2>${esc(s.h)}</h2>${fig}
    ${s.p.map(t => `<p>${esc(t)}</p>`).join('\n    ')}
  </section>`;
  }).join('\n');
  const qa = L.sections.filter(s => /\?$/.test(s.h)).map(s => ({ '@type': 'Question', name: s.h, acceptedAnswer: { '@type': 'Answer', text: s.p.join(' ') } }));
  const firstImg = (L.sections.find(s => s.img) || {}).img;
  const lds = [ld({ '@context': 'https://schema.org', '@type': 'Article', headline: L.h1, description: L.description, inLanguage: lang,
    image: C.SITE + '/' + (firstImg ? firstImg.src : C.IMG.building), datePublished: C.UPDATED, dateModified: C.UPDATED,
    author: { '@type': 'Organization', name: C.CAFE, url: C.SITE + '/' },
    publisher: { '@type': 'Organization', name: C.CAFE, logo: { '@type': 'ImageObject', url: C.SITE + '/assets/logo.png' } },
    mainEntityOfPage: pageUrl(p, lang), about: { '@type': 'CafeOrCoffeeShop', name: C.CAFE, url: C.SITE + '/' } })];
  if (qa.length) lds.push(ld({ '@context': 'https://schema.org', '@type': 'FAQPage', inLanguage: lang, mainEntity: qa }));
  const body = `<article class="post">
  <header class="phead">
    <p class="kicker mono">${esc(L.kicker)}</p>
    <h1>${esc(L.h1)}</h1>
    <p class="lede">${esc(L.lede)}</p>
    <p class="meta">${u.updated} <time datetime="${C.UPDATED}">${fmtDate(C.UPDATED, lang)}</time> · ${L.readTime} · <a href="${rel(lang, 'index.html')}">${u.backHome}</a></p>
  </header>
  <nav class="toc" aria-label="${u.inThisPage}">
    <p class="mono">${u.inThisPage}</p>
    <ol>
      ${toc}
    </ol>
  </nav>
${secs}
${ctaBlock(lang, L.cta)}
</article>`;
  return shell(p, lang, body, lds.join('\n'), firstImg && firstImg.src);
}
function fmtDate(iso, lang) {
  const [y, m, d] = iso.split('-').map(Number);
  const en = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  const esM = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'setiembre', 'octubre', 'noviembre', 'diciembre'];
  return lang === 'es' ? `${d} de ${esM[m - 1]} de ${y}` : `${en[m - 1]} ${d}, ${y}`;
}

/* ---------- menu page ---------- */
function menuPage(p, lang) {
  const L = p[lang], u = C.UI[lang];
  const t = lang === 'es' ? es : (k => k);
  const slug = s => s.toLowerCase().replace(/&amp;|&/g, 'and').replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '');
  const toc = menu.map(c => `<li><a href="#${slug(c.name)}">${esc(t(c.name))}</a></li>`).join('\n      ');
  const cats = menu.map(c => `  <section class="mcat" id="${slug(c.name)}">
    <h2>${esc(t(c.name))}</h2>
    <ul class="mlist">
      ${c.items.map(i => `<li><div class="row1"><span class="nm">${esc(i.name)}</span><span class="dots"></span><span class="price">${esc(i.price)}</span></div>${i.desc ? `<div class="ds">${esc(t(i.desc))}</div>` : ''}</li>`).join('\n      ')}
    </ul>
  </section>`).join('\n');
  const notes = L.notes.map(n => `<li>${esc(n)}</li>`).join('\n    ');
  const menuLd = ld({ '@context': 'https://schema.org', '@type': 'CafeOrCoffeeShop', name: C.CAFE, url: C.SITE + '/', telephone: C.PHONE,
    image: C.SITE + '/' + C.IMG.building, servesCuisine: ['Coffee', 'Costa Rican', 'Café'], priceRange: '₡₡', currenciesAccepted: 'CRC, USD',
    paymentAccepted: 'Cash, Credit Card, SINPE Móvil',
    address: { '@type': 'PostalAddress', streetAddress: C.STREET, addressLocality: 'Santa Elena, Monteverde', addressRegion: 'Puntarenas', postalCode: '60109', addressCountry: 'CR' },
    openingHoursSpecification: [{ '@type': 'OpeningHoursSpecification', dayOfWeek: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'], opens: '06:00', closes: '19:00' }],
    hasMenu: { '@type': 'Menu', '@id': pageUrl(p, lang) + '#menu', name: L.h1, url: pageUrl(p, lang), inLanguage: lang,
      hasMenuSection: menu.map(c => ({ '@type': 'MenuSection', name: t(c.name), hasMenuItem: c.items.map(i => {
        const o = { '@type': 'MenuItem', name: i.name };
        if (i.desc) o.description = t(i.desc);
        const n = priceNumber(i.price); if (n) o.offers = { '@type': 'Offer', price: n, priceCurrency: 'CRC' };
        return o; }) })) } });
  const body = `<article class="post menu" id="menu">
  <header class="phead">
    <p class="kicker mono">${esc(L.kicker)}</p>
    <h1>${esc(L.h1)}</h1>
    <p class="lede">${esc(L.lede)}</p>
    <p class="meta">${u.hours} · <a href="${rel(lang, 'index.html')}">${u.backHome}</a></p>
  </header>
  <nav class="toc" aria-label="${u.menuSections}">
    <p class="mono">${u.menuSections}</p>
    <ol>
      ${toc}
    </ol>
  </nav>
  <div class="mgrid">
${cats}
  </div>
  <ul class="mnotes">
    ${notes}
  </ul>
${ctaBlock(lang, L.cta)}
</article>`;
  return shell(p, lang, body, menuLd, C.IMG.cup);
}

/* ---------- home page: FAQ + guide cards + dictionary ---------- */
function between(src, start, end, inner, what) {
  const a = src.indexOf(start), b = src.indexOf(end);
  if (a < 0 || b < 0 || b < a) throw new Error('markers not found: ' + what);
  return src.slice(0, a + start.length) + '\n' + inner + '\n' + src.slice(b);
}
const live = C.FAQ.filter(f => !f.hold);
const faqHtml = live.map(f => `    <details class="faq"><summary>${esc(f.en.q)}</summary><div class="fa"><p>${esc(f.en.a)}</p></div></details>`).join('\n');
const faqLd = ld({ '@context': 'https://schema.org', '@type': 'FAQPage', inLanguage: 'en', mainEntity: live.map(f => ({ '@type': 'Question', name: f.en.q, acceptedAnswer: { '@type': 'Answer', text: f.en.a } })) });
const guideCards = C.PAGES.map(p => `    <a class="gcard part" href="${p.en.slug}"><span class="gk">${esc(p.en.kicker)}</span><strong>${esc(p.en.h1)}</strong><span class="gd">${esc(p.en.description.split('. ')[0])}.</span></a>`).join('\n');

let idx = index;
idx = between(idx, '<!-- faq:start -->', '<!-- faq:end -->', faqHtml, 'faq');
idx = between(idx, '<!-- faqld:start -->', '<!-- faqld:end -->', faqLd, 'faqld');
idx = between(idx, '<!-- guides:start -->', '<!-- guides:end -->', guideCards, 'guides');
if (idx !== index) write('index.html', idx);

/* dictionary: every English string the home page shows for the FAQ and guide cards */
const dict = {};
live.forEach(f => { dict[f.en.q] = f.es.q; dict[f.en.a] = f.es.a; });
C.PAGES.forEach(p => { dict[p.en.kicker] = p.es.kicker; dict[p.en.h1] = p.es.h1; dict[p.en.description.split('. ')[0] + '.'] = p.es.description.split('. ')[0] + '.'; dict[p.en.nav] = p.es.nav; });
['faqTitle', 'faqKicker', 'faqLede', 'guidesTitle', 'guidesKicker', 'review', 'coffee', 'guides', 'menuPage'].forEach(k => { dict[C.UI.en[k]] = C.UI.es[k]; });
const dictJs = Object.keys(dict).map(k => '    ' + JSON.stringify(k) + ': ' + JSON.stringify(dict[k]) + ',').join('\n');
let lj = langSrc;
lj = between(lj, '/* faq:start */', '/* faq:end */', dictJs, 'lang faq');
if (lj !== langSrc) write('lang.js', lj);

/* ---------- pages ---------- */
for (const p of C.PAGES) for (const lang of ['en', 'es']) write(p[lang].slug, p.type === 'menu' ? menuPage(p, lang) : article(p, lang));

/* ---------- sitemap ---------- */
const urls = [`  <url>
    <loc>${C.SITE}/</loc>
    <lastmod>${C.UPDATED}</lastmod>
    <changefreq>weekly</changefreq>
    <priority>1.0</priority>
  </url>`];
for (const p of C.PAGES) for (const lang of ['en', 'es']) urls.push(`  <url>
    <loc>${pageUrl(p, lang)}</loc>
    <lastmod>${C.UPDATED}</lastmod>
    <xhtml:link rel="alternate" hreflang="en" href="${pageUrl(p, 'en')}"/>
    <xhtml:link rel="alternate" hreflang="es" href="${pageUrl(p, 'es')}"/>
    <xhtml:link rel="alternate" hreflang="x-default" href="${pageUrl(p, 'en')}"/>
    <changefreq>monthly</changefreq>
    <priority>${p.key === 'menu' ? '0.9' : '0.8'}</priority>
  </url>`);
write('sitemap.xml', `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">
${urls.join('\n')}
</urlset>
`);
console.log('menu sections:', menu.map(c => c.name + ' (' + c.items.length + ')').join(', '));
