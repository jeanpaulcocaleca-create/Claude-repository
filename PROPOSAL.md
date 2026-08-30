# The Hanging Garden — "Canopy OS" Proposal

**An all-in-one system for a coffee experience in Monteverde, Costa Rica**

*Proposal v1 — no code yet, as requested. This is the system I would build if this were my coffee place too.*

---

## 1. The Vision

The Hanging Garden isn't just a coffee shop — Monteverde sits on the tourist trail between the cloud forest, the hanging bridges, and the coffee farms. Visitors there aren't buying a cup of coffee; they're buying a Costa Rican coffee *experience* they'll tell people about back home. The system should reflect that split personality:

- **Outward-facing:** a beautiful bilingual website that ranks on Google, tells the story of the garden, and converts tourists planning their Monteverde days into visitors (and later, into online bean buyers).
- **Inward-facing:** one operational backbone — POS, menu, orders, sales, staff time, payroll — so you run the whole business from a single tablet and a single source of truth, even when Monteverde's internet flickers.
- **On top of both:** **Nora**, an AI operations brain (inspired by [Nory](https://www.nory.ai/), the AI restaurant operating system) that watches your sales, forecasts demand, and tells you each morning what to prep, what to order, and who to schedule.

I'm calling the whole thing **Canopy OS** — everything under one roof, like the garden itself.

---

## 2. The Modules

### A. Website & Google Presence — *"Be found, tell the story"*

- Bilingual (English/Spanish) site: story of the garden, the menu, photos, hours, location with Google Maps embed, and a "plan your visit" page aimed at tourists.
- **SEO built in from day one:** `LocalBusiness`/`CafeOrCoffeeShop` structured data (schema.org), proper meta tags, fast static pages, sitemap — this is what gets you the rich result on Google with hours, photos, and reviews.
- **Google Business Profile** setup and sync (hours, menu highlights, photos, posts) — for a tourist-town café this drives more foot traffic than the website itself, since visitors search "coffee near me" from the trail.
- Live menu on the site, fed directly from the menu manager (never out of date).
- Review funnel: a QR code on receipts that routes happy customers to your Google review page.

### B. Point of Sale — *"The counter tablet"*

- Tablet-based POS (a progressive web app — runs on any iPad/Android tablet, no app store needed).
- **Offline-first:** orders queue locally and sync when the connection returns. In Monteverde this is non-negotiable — the POS must never stop because the wifi did.
- Big-button menu grid with modifiers (milk type, size, "para llevar"), order notes, and a kitchen/bar ticket view.
- **Payments the Costa Rican way:** cash (CRC **and** USD with live exchange rate — tourists pay in dollars constantly), cards via a local processor/terminal, and **SINPE Móvil** (with a QR + reference-matching flow, since locals live on SINPE).
- 13% IVA handled correctly on every receipt; printed or emailed receipts.
- Architected so **factura electrónica** (Hacienda's mandatory e-invoicing, v4.4) can be plugged in — receipts carry all required fields from day one.
- Tips: recorded per order, pooled into the payroll module automatically.

### C. Menu Manager — *"One menu, everywhere"*

- Add, edit, remove, and reorder items from your phone in seconds: name (EN/ES), price, photo, category, modifiers, allergens.
- **Availability toggle** — "sold out of banana bread" hides it from the POS and website instantly.
- Seasonal/scheduled items (a rainy-season special that appears automatically).
- The website menu and the POS both read from this single source — change it once, it's changed everywhere.

### D. Sales & Orders — *"Know your business"*

- Live order board: open → preparing → served/picked up.
- Daily dashboard: revenue, order count, average ticket, payment-method mix, best sellers, sales by hour (so you see the tour-bus waves).
- Weekly/monthly reports, CSV export for your accountant, month-over-month and season-over-season comparisons (high season vs. green season matters enormously in Monteverde).

### E. Team Time Clock — *"Clock in, clock out"*

- Each employee gets a PIN; clock in/out on the POS tablet (optional photo capture for accountability).
- Break tracking, shift notes, and a manager view of who's on the clock right now.
- Timesheets roll up automatically per pay period — no more paper hour sheets.

### F. Payroll & Internal Payments — *"Hours become paychecks"*

- Hourly rates per employee; the system computes each pay period from the time clock: regular hours, **overtime at 1.5× past 8 hours/day** (per Costa Rican labor law), and tip shares from the POS tip pool.
- Tracks the employer-side obligations you must plan for in Costa Rica: **CCSS contributions** and **aguinaldo accrual** (the mandatory 13th-month bonus), so December never surprises you.
- Generates a clear pay statement per employee per period; records payments (SINPE/bank transfer/cash) against them so you always know who's been paid what.
- *Honest scoping note:* this is a payroll **ledger and calculator** — it computes, records, and documents. Actual money movement stays in your bank/SINPE app at first; automating disbursement is a later phase, done carefully.

### G. Nora — *"The AI that runs the back office"* ⭐

This is the Nory-inspired layer, and it's where partnering with me pays off — Nora is powered by Claude and gets smarter because every other module feeds it data:

- **Morning briefing** (WhatsApp or email, 6am): "Yesterday: ₡412,000, 118 orders. Today looks like a high-traffic day (dry season Saturday). Prep extra: iced lattes, gallo pinto. You're low on oat milk — order today. Andrea and Luis are scheduled; consider a third person 10am–1pm."
- **Demand forecasting** from your own sales history + day-of-week + season (tourist patterns are highly predictable in Monteverde) — the same forecasting-driven approach Nory uses to cut food waste ~50% for its customers.
- **Recipe-level inventory:** each menu item depletes ingredients (a latte = 18g beans + 240ml milk), so Nora knows stock levels from sales alone and drafts your supplier orders.
- **Labor suggestions:** matches staffing to forecasted demand — the biggest controllable cost in any café.
- **Ask Nora anything:** "What was our best-selling pastry last month?" "How much did we pay in tips in July?" — plain-language questions over your own data, in English or Spanish.
- **Customer-facing Nora (later):** an assistant on the website that answers "do you have oat milk?", "are you open Sunday?", "can I book the coffee experience at 2pm?" in the visitor's language.

---

## 3. What I'd Add as Your Partner

Things you didn't ask for but I'd want in *our* coffee place:

1. **Coffee experience bookings.** Monteverde tourists plan by the hour. A booking page for tastings/tours/workshops (with deposit via card) turns the website into a revenue engine, not a brochure. This would be my Phase-2 priority.
2. **Sell beans online.** Tourists who fell in love at the counter should be able to reorder bags from home — the highest-margin repeat revenue a café can have.
3. **Loyalty via QR** — a digital "9th coffee free" card for locals and guides. Tour guides who drink free bring busloads.
4. **WhatsApp ordering** for locals ("the usual, ready at 8") — WhatsApp is the default channel in Costa Rica.
5. **Inventory & waste log** feeding Nora, so shrinkage and waste show up in pesos, not vibes.

---

## 4. Architecture (kept boring on purpose)

| Layer | Choice | Why |
|---|---|---|
| App | Next.js (one codebase: website + POS + admin) | Fast, SEO-friendly, installable as a tablet PWA |
| Database & auth | Supabase (Postgres, realtime, row-level security) | One source of truth; realtime order board; roles (owner / manager / barista) for free |
| Offline POS | Local-first queue with background sync | Survives Monteverde connectivity |
| AI | Claude API | Powers Nora's briefings, forecasts, and Q&A |
| Hosting | Vercel + Supabase cloud | ~$0–45/month at café scale; no servers to babysit |

One system, one login, one database. No duct tape between five SaaS subscriptions — that's the "all-in-one" promise, and it's also what keeps monthly costs near zero compared to Square + Toast + Deputy + Gusto + a website builder (~$300+/month).

---

## 5. Roadmap

| Phase | Delivers | Why this order |
|---|---|---|
| **1. Be found & sell** | Website + SEO + Google Business Profile; Menu manager; POS with cash/card/SINPE, IVA, receipts | Revenue and visibility first |
| **2. Know the business** | Sales dashboard & reports; order board; coffee-experience bookings | Data starts accumulating for Nora |
| **3. Run the team** | Time clock; timesheets; payroll ledger with CR labor rules; tip pooling | Operational backbone |
| **4. Nora** | Morning briefings, forecasting, inventory intelligence, ask-anything; customer-facing assistant | AI is only as good as the data from phases 1–3 |

Each phase ships something you use on day one of that phase — no six-month wait for a big bang.

---

## 6. Open Questions Before We Code

1. **Nora/Nory:** I've assumed you meant [Nory](https://www.nory.ai/)-style AI operations built in (rather than integrating with Nory itself, which targets multi-site chains and is priced that way). Naming our built-in AI "Nora" keeps the homage. Confirm?
2. **Card payments:** do you already have a card terminal / processor (BAC, BN, Tilopay, ONVO)? That decides the card integration path.
3. **Factura electrónica:** are you invoicing through Hacienda today (régimen tradicional vs. simplificado)? Determines whether e-invoicing lands in Phase 1 or later.
4. **Hardware:** how many tablets/printers exist today, if any?
5. **Team size** and whether employees are hourly, salaried, or mixed.

Answer those (or just say "go") and Phase 1 starts.
