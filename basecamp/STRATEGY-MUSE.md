# Strategy plan by Muse · source document

Provided by the owner in Claude's chat on 2026-10-20 and shared with ChatGPT the same day. Written by Muse. Kept as received; only the Markdown layout was tidied. The owner asked Claude to analyse and incorporate it (BD-014 in `CODEX.md`). Claude's review, including where it conflicts with earlier owner decisions, is in [`STRATEGY-REVIEW.md`](STRATEGY-REVIEW.md).

---

# STRATEGY PLAN — How to Build a Small Hotel Website That Is a Marketing Monster

For the AI builders (ChatGPT / Claude). This document contains strategy and structure only — zero business data. No names, numbers, prices, schedules, offers or contact details. You are building the machine; the data gets poured in later. Wherever content is needed, build the template, the field and the slot — not the content.

The goal: when a traveler searches for lodging in the destination — or anything related to staying there, visiting there, or vacationing in the country — this site is option #1 or #2, and converting that visitor into a direct conversation takes under 60 seconds.

## 1. THE CORE PHILOSOPHY

A normal hotel website is a brochure. A monster is four machines in one site:

1. A booking machine — converts visitors into direct chats/bookings with zero friction.
2. A search machine — dozens of pages engineered to capture searches the hotel's homepage can never rank for.
3. A trust machine — proof, story and reviews that make choosing this property feel obvious.
4. An ads machine (dormant) — tracking and landing structure built now, so paid campaigns later plug in without a rebuild.

Build all four from day one, even if only the first ships first.

## 2. ARCHITECTURE

- One site, four sections: Lodging / On-site food & drink / Experiences (tours/activities) / Knowledge Hub (guides & Q&A). The lodging brand is the umbrella; the other sections are ranking and cross-sell engines, not decorations.
- One URL per sellable unit. Every room type gets its own page. Never one shared "rooms" page — individual pages rank, convert and serve as ad landings; a gallery page does none of those.
- One URL per experience. Each tour/activity gets its own page, never a single list page.
- Fully bilingual, properly: two complete language versions of every page with correct hreflang pairing — not a machine-translation toggle widget.
- Mobile-first design. Most travel searches happen on a phone, often on a weak connection. Design the phone experience first; desktop is the adaptation.
- A real visual concept, not a template. Distinctive identity (editorial/naturalist/field-journal style direction), consistent art direction, strong typography. Template-looking sites convert like template-looking sites.

## 3. TECHNICAL FOUNDATION (the invisible ranking layer)

- Speed is a ranking feature: Core Web Vitals green on mobile (LCP < 2.5s, INP < 200ms, CLS < 0.1). Image pipeline: modern formats (WebP/AVIF), responsive sizes, lazy loading below the fold, no page heavier than ~1.5 MB.
- Structured data everywhere (schema.org): LodgingBusiness/Hotel on the business pages, a room/offer type per room page, a food-establishment type for the café section, FAQPage on every FAQ block, Article on every guide, BreadcrumbList site-wide, Organization with sameAs social/profile links. AggregateRating markup only from real, on-page reviews — never fabricated.
- Crawl hygiene: XML sitemap, sane robots.txt, canonical URLs, clean semantic HTML (one H1 per page, logical heading order), descriptive keyword-bearing URLs in both languages.
- Redirect discipline: any pre-existing URLs on the domain get a 301 map to the new structure. Nothing indexed is allowed to 404.
- AI-search readiness: an `llms.txt` file at the root and one plain-language, fact-dense "about the business" page written so AI assistants can quote it accurately. AI answer engines are a growing discovery channel; sites with clean structured facts get cited.
- Analytics from day one: GA4 + Search Console wired before launch, with a defined event taxonomy (Section 7).

## 4. THE KNOWLEDGE HUB — the actual monster

Homepages rank for almost nothing. The traffic — and the future guests — are captured by a library of pages that each answer one real question a traveler types into Google or asks an AI. Design the hub as a system:

- Page types to build as reusable templates:
  - Destination guide (the complete pillar page)
  - Seasonal/weather guide (when to come, month by month)
  - Transport guide (how to get here from each major gateway)
  - Comparison/explainer pages (concepts travelers confuse)
  - Packing & preparation guides
  - Activity explainers (one per experience type, from the visitor's point of view)
  - Niche guides the big competitors ignore (families, pets, budget, accessibility — whoever the property genuinely serves)
  - Town/neighborhood practical guide
  - Itinerary pages (how the destination fits a multi-stop country trip, at several trip lengths)
  - Local-story pages (the place's own people, nature, craft — unique content no competitor can copy)
  - One master FAQ page + an FAQ block on every commercial page
- Every guide follows the same conversion skeleton: answer the question completely in the first third → local-expert depth nobody else has → photos → internal links to the relevant room/activity page → soft chat CTA ("ask a local, we answer fast") → FAQ schema block.
- Internal linking is engineered, not accidental: hub pages link down to money pages; money pages link up to the hub; every page is within 3 clicks of home.
- Publishing system: templates and components ready so new guides ship at a steady cadence (e.g. 2/month) without developer help each time.

## 5. SEARCH STRATEGY (how it becomes option 1–2)

- Keyword layering: exact-intent terms on money pages ("hotel in [destination]", "where to stay in [destination]", per-niche variants) and question/long-tail terms on hub pages. Title and meta templates per page type: keyword + differentiator + reason to click.
- Local-search alignment: the site is the canonical source the map/business profiles mirror — identical name/address/phone strings everywhere on-site, an embedded map, and a dedicated "find us / getting here" page written in landmark language (how humans actually navigate).
- Review flywheel (design for it): the site must actively help generate reviews — review-profile links in the footer and post-booking copy, a dedicated reviews page that aggregates real guest words with outbound links to the source profiles. Review volume and rating are ranking fuel for both Google and AI answers.
- Entity building: consistent business entity across the site, the sister businesses' sites, directories and profiles (sameAs, cross-links), so search engines and AIs resolve it as one known entity.
- Link earning: the hub's unique local content (data, stories, guides) is the linkable asset; the structure must make guides easy to cite and share.

## 6. CONVERSION ENGINEERING

- One primary action everywhere: a click-to-chat messaging button (deep link with a different prefilled message per page, so the business knows where each conversation started). Secondary action: email/contact form. No competing CTAs.
- Persistent mobile action bar: the chat button is always one thumb-scroll away, on every page, including guides.
- Decision-point design: price transparency early (price + what it includes, near the top of money pages), a "why book direct" block at every decision point, and a trust stack beside every CTA: real photos, real reviews, real people, low-risk payment policy messaging.
- Friction audit as a feature: from landing to chat-open in under 60 seconds on a slow connection; every form field that isn't essential is removed; nothing requires an account.
- Social proof placement: short review excerpts near CTAs (linked to source), not buried on one testimonials page.

## 7. PAID-MEDIA READINESS (build now, spend later)

- Meta Pixel + Conversions API installed and verified from day one, on a verified domain. Event taxonomy defined in code: PageView, ViewContent (per room/activity), and a Lead event fired on the chat-button click — the money event. Documented UTM convention for all future campaigns.
- Ad-landing capability: every room page and the main lodging landing must function standalone as an ad landing page (message match with ad copy, key info above the fold, chat CTA visible without scrolling, fast load).
- Remarketing pools from day one: analytics + pixel audiences segmented by intent (room viewers vs. café viewers vs. guide readers), so the first paid campaign starts with warm audiences instead of zero history.
- Source attribution baked in: per-page prefilled chat messages and UTM capture so every conversation can be traced to the page/campaign that produced it.

## 8. MEASUREMENT

Track outcomes, not vanity: chat conversations started (by source page), calls, direction requests, review-link clicks — plus organic sessions by section and the top non-brand queries in Search Console. The dashboard question is never "how much traffic?" but "which pages produce conversations, and which searches are we winning that we didn't before?"

## 9. BUILD ORDER

1. Foundation (speed, schema framework, analytics, pixel) + homepage + one page per room + chat funnel.
2. Café section + one page per experience + location page + master FAQ.
3. Knowledge Hub templates + the first 5–6 guides (destination pillar, seasonal, transport, packing, flagship activity, niche guide).
4. Reviews page + review-generation hooks.
5. Hub expansion at a steady cadence thereafter.

## 10. ANTI-PATTERNS (what makes it NOT a monster)

- A single-page site, however pretty. One page cannot rank for fifty questions.
- A generic template aesthetic. Forgettable design = forgettable brand = no direct bookings.
- Generated/stock imagery presented as the property itself. (Atmosphere backgrounds are fine; the product must be real photography — build the galleries and slots for real photos.)
- A booking flow that depends on a third-party engine the business doesn't have. The conversion is a conversation; design for that.
- Publishing thin guides. One excellent answer outranks ten shallow ones; each hub page must be the best answer on the internet for its question.
- Tracking installed "later." Retrofitting measurement loses the entire history; it ships in version one.
