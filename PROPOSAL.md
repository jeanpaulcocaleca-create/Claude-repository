# The Hanging Garden — "Canopy OS" Proposal

**An all-in-one system for a coffee experience in Monteverde, Costa Rica**

*Proposal v2 — updated with your answers. Still no code, as requested.*

---

## What changed in v2

Your answers locked in four things:

1. **Payments run through BAC San José (BAC Credomatic).** You already have a card terminal *and* a BAC payment link for online payments. Canopy OS is designed around both — no new processor needed.
2. **Hacienda invoicing status is in scope.** The system must be able to provide the invoicing status of any sale when asked — so electronic invoicing (factura electrónica) moves from "readiness" to a real module with per-invoice Hacienda status tracking.
3. **Team of 5 now, 10–15 later.** Time clock, roles, and payroll are sized for that growth from day one — nothing to migrate when you scale.
4. **Nora already exists.** She's your own WhatsApp system, already built, answering questions about menu, directions, hours, and more. We don't build an AI — we **integrate yours**: on the website, and fed by live data from Canopy OS so her answers are always current.

---

## 1. The Vision

The Hanging Garden isn't just a coffee shop — Monteverde sits on the tourist trail between the cloud forest, the hanging bridges, and the coffee farms. Visitors aren't buying a cup of coffee; they're buying a Costa Rican coffee *experience* they'll tell people about back home. The system reflects that split personality:

- **Outward-facing:** a beautiful bilingual website that ranks on Google, tells the story of the garden, and converts tourists planning their Monteverde days into visitors — with **Nora** greeting them in chat.
- **Inward-facing:** one operational backbone — POS, menu, orders, sales, staff time, payroll — so you run the whole business from a single tablet and a single source of truth, even when Monteverde's internet flickers.
- **Connecting both:** Nora, your existing WhatsApp assistant, wired into the website and into Canopy OS's live data.

---

## 2. The Modules

### A. Website & Google Presence — *"Be found, tell the story"*

- Bilingual (English/Spanish) site: story of the garden, the menu, photos, hours, location with Google Maps embed, and a "plan your visit" page aimed at tourists.
- **SEO built in from day one:** `CafeOrCoffeeShop` structured data (schema.org), proper meta tags, fast static pages, sitemap — the rich Google result with hours, photos, and reviews.
- **Google Business Profile** setup and sync — for a tourist-town café this drives more foot traffic than the website itself.
- Live menu on the site, fed directly from the menu manager (never out of date).
- **Nora on the site** (see module G): a chat widget plus a "chat on WhatsApp" button, so web visitors and WhatsApp users reach the same assistant.
- Review funnel: a QR code on receipts routes happy customers to your Google review page.

### B. Point of Sale — *"The counter tablet"*

- Tablet-based POS (a progressive web app — runs on any iPad/Android tablet, no app store needed).
- **Offline-first:** orders queue locally and sync when the connection returns. The POS never stops because the wifi did.
- Big-button menu grid with modifiers, order notes, and a kitchen/bar ticket view.
- **Payments, built around your BAC setup:**
  - Cash in CRC **and** USD with a live exchange rate (tourists pay in dollars constantly).
  - **Card via your existing BAC San José terminal** — the POS records the card payment against the order (amount, last digits/auth reference) so sales reports and the register always reconcile with your BAC statement.
  - **BAC payment link for anything online:** bookings, deposits, pickup orders. Canopy OS attaches your payment link to the order and marks it paid on confirmation, so online money shows up in the same sales reports as counter money.
  - **SINPE Móvil** with a QR + reference-matching flow.
- 13% IVA handled correctly on every receipt; printed or emailed receipts.
- Tips: recorded per order, pooled into the payroll module automatically.

### C. Menu Manager — *"One menu, everywhere"*

- Add, edit, remove, and reorder items from your phone in seconds: name (EN/ES), price, photo, category, modifiers, allergens.
- **Availability toggle** — "sold out of banana bread" hides it from the POS, the website, and Nora's answers instantly.
- Seasonal/scheduled items.
- The website, the POS, **and Nora** all read from this single source — change it once, it's changed everywhere.

### D. Sales, Orders & Electronic Invoicing — *"Know your business, prove it to Hacienda"*

- Live order board: open → preparing → served/picked up.
- Daily dashboard: revenue, order count, average ticket, payment-method mix, best sellers, sales by hour (so you see the tour-bus waves).
- Weekly/monthly reports, CSV export for your accountant, and season-over-season comparisons (high season vs. green season matters enormously in Monteverde).
- **Factura electrónica module:** every sale can be issued as an electronic invoice/tiquete under Hacienda's scheme (v4.4), and the system tracks each document's status — *sent, accepted, rejected* — so **when anyone asks for the Hacienda invoicing status of a sale, it's one lookup away**, with the XML/PDF on file. We'll confirm your régimen (tradicional vs. simplificado) before wiring the submission path, since it changes what must be filed.

### E. Team Time Clock — *"Clock in, clock out"*

- Each employee gets a PIN; clock in/out on the POS tablet (optional photo capture).
- Break tracking, shift notes, and a manager view of who's on the clock right now.
- Timesheets roll up automatically per pay period.
- **Sized for your growth:** built for the starting team of 5 and ready for 10–15 — roles (owner / manager / barista) and per-employee permissions exist from day one, and a simple shift schedule becomes available when the team grows past what fits in your head.

### F. Payroll & Internal Payments — *"Hours become paychecks"*

- Hourly rates per employee; the system computes each pay period from the time clock: regular hours, **overtime at 1.5× past 8 hours/day** (per Costa Rican labor law), and tip shares from the POS tip pool.
- Tracks the employer-side obligations you must plan for in Costa Rica: **CCSS contributions** and **aguinaldo accrual** (the mandatory 13th-month bonus) — increasingly important as the team triples.
- Generates a clear pay statement per employee per period; records payments (SINPE/bank transfer/cash) against them so you always know who's been paid what.
- *Honest scoping note:* this is a payroll **ledger and calculator** — it computes, records, and documents. Actual money movement stays in your bank/SINPE app at first; automating disbursement is a later phase, done carefully.

### G. Nora Integration — *"Your assistant, everywhere, always current"* ⭐

Nora is already built and already answers menu, directions, and hours questions on WhatsApp. The work here is **integration, not construction** — three connections:

1. **Nora on the website.** A chat widget on the site connected to your Nora system, plus a WhatsApp deep-link button for visitors who'd rather chat there. One assistant, two doors. (Exact wiring depends on what Nora is built on — see open questions.)
2. **Live data feed.** Canopy OS exposes a clean, read-only API for Nora: current menu with today's availability and prices, hours, holiday closures, directions, and booking availability. Nora stops needing manual updates — when you 86 the banana bread on the POS, her answer changes in the same minute.
3. **Nora takes action (later, optional).** With a write endpoint, Nora can go beyond answering: place a pickup order into the order board, or hold a booking. And since she already lives on WhatsApp — the channel you check anyway — she's the natural voice for an owner-side **morning briefing** (yesterday's sales, today's outlook, low stock), which Canopy OS can generate and send through her.

---

## 3. What I'd Add as Your Partner

1. **Coffee experience bookings.** Monteverde tourists plan by the hour. A booking page for tastings/tours/workshops — with deposits collected through your **existing BAC payment link** — turns the website into a revenue engine, not a brochure. My Phase-2 priority.
2. **Sell beans online**, paid by BAC payment link — the highest-margin repeat revenue a café can have.
3. **Loyalty via QR** — a digital "9th coffee free" card for locals and guides. Tour guides who drink free bring busloads.
4. **WhatsApp ordering through Nora** for locals ("the usual, ready at 8") — a natural extension of connection 3 above.
5. **Inventory & waste log** so shrinkage and waste show up in colones, not vibes.

---

## 4. Architecture (kept boring on purpose)

| Layer | Choice | Why |
|---|---|---|
| App | Next.js (one codebase: website + POS + admin) | Fast, SEO-friendly, installable as a tablet PWA |
| Database & auth | Supabase (Postgres, realtime, row-level security) | One source of truth; realtime order board; roles for a team growing 5 → 15 |
| Offline POS | Local-first queue with background sync | Survives Monteverde connectivity |
| Payments | Your BAC San José terminal + BAC payment link + SINPE | No new processor; online and counter sales reconcile in one report |
| Nora | Integration API (read: menu/hours; later write: orders/bookings) | Your existing system becomes the front door on web + WhatsApp |
| Hosting | Vercel + Supabase cloud | ~$0–45/month at café scale; no servers to babysit |

One system, one login, one database. No duct tape between five SaaS subscriptions — and no $300+/month stack of Square + Toast + Deputy + Gusto + a website builder.

---

## 5. Roadmap

| Phase | Delivers | Why this order |
|---|---|---|
| **1. Be found & sell** | Website + SEO + Google Business Profile; menu manager; POS with cash/BAC card/SINPE, IVA, receipts; **Nora on the website** (widget + WhatsApp button, live menu/hours feed) | Revenue and visibility first; Nora integrates early because she already exists |
| **2. Know the business** | Sales dashboard & reports; order board; **factura electrónica with Hacienda status tracking**; experience bookings paid via BAC payment link | Money and compliance visibility |
| **3. Run the team** | Time clock; timesheets; payroll ledger with CR labor rules; tip pooling; shift schedule as the team grows | Operational backbone, ready for 10–15 |
| **4. Nora acts & advises** | Nora places pickup orders/bookings; owner morning briefing via WhatsApp; inventory intelligence and forecasting | Built on the data phases 1–3 accumulate |

Each phase ships something you use on day one of that phase — no six-month wait for a big bang.

---

## 6. Remaining Questions Before We Code

1. **Nora's plumbing:** what is Nora built on (WhatsApp Business Cloud API, Twilio, a bot platform)? Does she have an API or webhook we can call, and can her engine also answer through a web chat widget — or should the website button hand off to WhatsApp only?
2. **BAC specifics:** is the terminal standalone (amount typed in by hand) or integrable? And for the payment link — is it generated manually in BAC's portal per sale, or is there an API to create links programmatically? Both work; it changes how automatic reconciliation can be.
3. **Hacienda régimen:** tradicional or simplificado? (This sets exactly what the factura electrónica module must file and store.)
4. **Hardware:** how many tablets/printers exist today, if any?

Answer those (or just say "go") and Phase 1 starts.
