# The Hanging Garden — "Canopy OS" Proposal (v3, Final)

**An all-in-one system for a coffee experience in Monteverde, Costa Rica**

*Still no code — this is the final pre-build proposal.*

---

## What's new in v3

- **Design toolchain locked in:** the website will be built with the **10K Websites** cinematic scroll workflow, with all imagery, textures, and hero video generated through **Higgsfield** — a one-of-a-kind site, not a template.
- **Signature scroll animation:** *La Gota* — coffee drips from the hero and travels with you down the page, connecting every section until it fills the cup.
- **Monteverde's real history and ideologies woven into the site** — the Quaker founding, the peace heritage, the cloud forest, the golden toad — modern page, vintage soul.
- **All five of your reviewer suggestions (A–E) confirmed and incorporated**, including a new Phase 0 discovery sprint, disaster recovery, early inventory schema, and audit logs with role granularity.

---

## 1. The Vision

Monteverde sits on the tourist trail between the cloud forest, the hanging bridges, and the coffee farms. Visitors aren't buying a cup of coffee — they're buying a Costa Rican coffee *experience*. Canopy OS reflects that:

- **Outward:** a one-of-a-kind cinematic website that ranks on Google and turns tourists planning their Monteverde days into visitors — with Nora greeting them in chat.
- **Inward:** one operational backbone — POS, menu, orders, sales, time clock, payroll — running from a single tablet, surviving Monteverde's internet.
- **Connecting both:** Nora, your existing WhatsApp assistant, integrated on the website and fed live data.

---

## 2. The Website — One of a Kind

### Toolchain

- Built on the **10K Websites** cinematic scroll-driven workflow (hero video, scroll choreography, deploy pipeline).
- **Higgsfield generates the visual world:** the hero film, vintage-style illustrations, textures, and section imagery — custom-made for The Hanging Garden, owned by you, impossible to find on another site.

### The signature moment: *La Gota* (the drip)

The homepage opens on a **chorreador** — the traditional Costa Rican wooden brewing stand with its cloth *bolsita*. As you scroll, a single thread of coffee begins to drip from it and **travels down the page with you**: it becomes the line that connects every section, pooling and pouring past the story, the menu, the experiences — until at the final section it lands in a waiting cup, filling it as the page ends at "visit us." One continuous pour, top to bottom.

Craft notes (for when we build): scroll-linked SVG path + canvas fluid effects choreographed with GSAP ScrollTrigger; a lightweight static version for `prefers-reduced-motion` and low-power phones; the drip is decoration that never blocks reading or slows the page below Google's Core Web Vitals bar — the SEO promise survives the cinema.

### Art direction: modern page, vintage soul

Modern layout, typography, and speed underneath; the decoration layer is vintage Costa Rica:

- **Naturalist engraving style** — quetzals, orchids, coffee branches drawn like 19th-century botanical plates.
- **Sarchí oxcart motifs** — the hand-painted *carreta* patterns (UNESCO-recognized) that once hauled Costa Rican coffee to port, used as borders and section ornaments.
- **Aged-paper textures, vintage stamps and postal marks** framing photos and menu cards.
- A muted cloud-forest palette: mist, moss, espresso, and one golden accent — for the golden toad.

### Monteverde's story, told on the page

A scroll chapter of the site — researched, real, and unique to this place:

- **Early 1900s:** Costa Rican farming families settle the green mountain, planting coffee and raising dairy on the slopes.
- **1948:** Costa Rica abolishes its army — a nation chooses peace.
- **1949–1951:** In Fairhope, Alabama, four young Quakers are jailed for refusing the military draft. On release, about 44 Quakers leave the U.S. and choose Costa Rica *because* it has no army. They buy ~1,400 hectares in the cloud forest and name it **Monteverde** — green mountain.
- **1953:** They found the cheese factory that sustains the community — and deliberately set aside the forested watershed above their farms rather than clear it.
- **1966:** Herpetologist Jay Savage describes the **golden toad**, found nowhere on Earth but the Monteverde ridge. Scientists pour in.
- **1972:** The **Monteverde Cloud Forest Reserve** is founded, growing into one of Costa Rica's most treasured protected areas; later, children around the world fund the **Bosque Eterno de los Niños**, the Children's Eternal Rainforest.
- **1989:** The golden toad is seen for the last time — Monteverde's reminder of why stewardship matters.

**The ideologies of the area become the brand's values, stated on the site:** *peace* (a community founded by people who refused war, in a country that disarmed), *simplicity* (Quaker plainness — honest coffee, honest prices), *stewardship* (protect the watershed, waste nothing), and *community* (cooperatives, neighbors, tour guides — everyone drinks at the same counter). The Hanging Garden's own hanging plants tie the garden itself into the canopy story.

Everything bilingual (EN/ES), structured data for Google's rich results, Google Business Profile synced, and a receipt-QR review funnel — the beauty serves the SEO, not instead of it.

---

## 3. The Operating System — Modules

**A. Website & Google** — as above, plus live menu fed from the menu manager and Nora's chat widget + WhatsApp button.

**B. Point of Sale** — offline-first tablet PWA; cash in CRC and USD with live exchange rate; **card via your existing BAC San José terminal** (payments recorded against orders so reports reconcile with your BAC statement); **BAC payment link for everything online** (bookings, deposits, pickup orders — marked paid on confirmation, landing in the same reports as counter money); **SINPE Móvil** with QR + reference matching; 13% IVA on every receipt; tips pooled into payroll.

**C. Menu Manager** — one source of truth for POS, website, and Nora. Bilingual items, photos, modifiers, availability toggles ("86 the banana bread" updates everywhere in a minute), seasonal scheduling.

**D. Sales & Electronic Invoicing** — live order board; daily dashboard (revenue, average ticket, payment mix, best sellers, sales by hour); season-over-season reports and accountant CSV exports; **factura electrónica module (Hacienda v4.4)** with per-document status tracking — *sent / accepted / rejected* — so any sale's Hacienda invoicing status is one lookup away, XML/PDF on file.

**E. Time Clock** — PIN clock in/out on the tablet with optional photo; breaks, shift notes, live "who's on"; timesheets per pay period; **sized for 5 now and 10–15 later** with roles and a shift schedule ready when you grow.

**F. Payroll Ledger** — pay computed from the clock under Costa Rican rules (overtime 1.5× past 8 hrs/day), tip shares, **CCSS contributions and aguinaldo accrual** tracked so December never surprises you; pay statements with payments recorded against them. (Ledger and calculator — money still moves through your bank app at first.)

**G. Nora Integration** — she's already built; the work is three connections: (1) **website chat widget + WhatsApp deep link** — one assistant, two doors; (2) **live read-only data feed** from Canopy OS (menu, availability, prices, hours, closures, bookings) so her answers are always current; (3) later, a **write endpoint** so she can place pickup orders and holds — and deliver your owner morning briefing over WhatsApp, where she already lives.

---

## 4. Your Five Suggestions — Analyzed & Adopted

**A. Clarify Nora's API capabilities early — ✅ Adopted, moved to Phase 0.** Agreed, this is the integration that everything customer-facing leans on. Before any build: what is Nora built on (WhatsApp Business Cloud API, Twilio, bot platform)? Does she expose an API/webhook for reads (menu, hours) and writes (orders)? Can her engine answer through a web widget, or does the site hand off to WhatsApp? A short technical questionnaire in Phase 0 settles the architecture.

**B. Explore BAC & SINPE APIs — ✅ Adopted, with research done and realistic fallbacks.** Initial findings: BAC's **Compra Click** payment links are generated from BAC's merchant portal (≈$50 setup, $25/month, $0.11 + IVA per transaction per BAC's published terms) with no public link-generation API documented — but BAC does offer full e-commerce gateway products, so Phase 0 includes one conversation with your BAC commercial executive asking for: (1) e-commerce/gateway API access for dynamic payment creation, (2) settlement/reconciliation reports (even daily CSV) for terminal payments. **SINPE Móvil has no public merchant API**, so the plan is honest: automatic reconciliation via bank notification parsing where possible, and a fast manual reference-matching screen in the POS as the guaranteed path. The system is designed so any of these can upgrade from manual → automatic without rework.

**C. Minimal disaster recovery — ✅ Adopted as a real (small) module.** New "keep the shop alive" checklist: automatic nightly database backups with point-in-time recovery (Supabase built-in); a one-tap **export everything** button (sales, timesheets, payroll, invoices → CSV/JSON to email or Drive); the POS offline cache doubles as a same-day buffer; a laminated **tablet restore runbook** at the counter (any spare tablet becomes the POS in under 5 minutes — log in, install PWA, done); quarterly restore drill. Informal, cheap, and it means a stolen tablet or a dead database costs you minutes, not weeks.

**D. Future-proof for inventory — ✅ Adopted, schema from day one.** The database is born with `ingredients`, `recipes` (menu item → ingredient quantities), `stock_movements`, and a **waste log** — and Phase 2 ships the simple habits: receive stock, auto-deduct on each sale, log waste with a reason. That makes shrinkage visible early and means the later intelligence phase (forecast-driven ordering) is a feature flip, not a migration.

**E. Audit logs & role granularity — ✅ Adopted.** Every sensitive action is logged immutably with who/what/when/before/after: price changes, menu edits, refunds and voids, shift edits, payroll adjustments, role changes. Roles get granular (owner / manager / barista, per-permission overrides) — essential at 10–15 staff. **Optional MFA (TOTP app or WhatsApp code) for owner and manager accounts**, and PIN-only baristas can't touch pricing, payroll, or exports. Refund/void thresholds require a manager PIN.

---

## 5. Architecture

| Layer | Choice | Why |
|---|---|---|
| Website build | 10K Websites cinematic workflow + Higgsfield imagery/video | One-of-a-kind scroll site; assets custom-generated and owned |
| App | Next.js — one codebase: website, POS, admin | Fast, SEO-friendly, installs as tablet PWA |
| Data & auth | Supabase (Postgres, realtime, RLS) + nightly backups | One source of truth; roles for 5 → 15; DR built in |
| Offline POS | Local-first queue with background sync | Survives Monteverde connectivity; doubles as backup buffer |
| Payments | BAC terminal + BAC payment link + SINPE Móvil | No new processor; manual → automatic upgrade path |
| Nora | Integration API — read now, write later | Your existing assistant becomes the front door |
| Audit & security | Immutable audit log; granular roles; optional MFA | Accountability as the team grows |
| Hosting | Vercel + Supabase cloud | ~$0–45/month at café scale |

---

## 6. Roadmap

| Phase | Delivers |
|---|---|
| **0 · Discovery (1–2 weeks)** | Nora technical questionnaire (A); BAC executive conversation — gateway API + reconciliation reports (B); SINPE notification test; Hacienda régimen confirmation; hardware inventory |
| **1 · Be found & sell** | Cinematic website with *La Gota* scroll + Monteverde story chapter (10K Websites + Higgsfield); SEO + Google Business Profile; menu manager; POS with cash/BAC/SINPE, IVA, receipts; **Nora on the website**; backups + export + restore runbook (C); audit log foundation (E) |
| **2 · Know the business** | Sales dashboard & reports; order board; factura electrónica with Hacienda status; bookings paid by BAC link; **stock deduction + waste log** (D) |
| **3 · Run the team** | Time clock; timesheets; payroll ledger (CR labor rules); tip pooling; shift schedule; granular roles + optional MFA (E) |
| **4 · Nora acts & advises** | Nora places orders/bookings; owner morning briefing via WhatsApp; forecast-driven inventory & prep suggestions |

---

## 7. Sources & further reading

- Friends Journal — *The Quaker Stewards of Costa Rica's Monteverde Cloud Forest*: https://www.friendsjournal.org/the-quaker-stewards-of-costa-ricas-monteverde-cloud-forest/
- Wikipedia — *Quakers in Costa Rica*: https://en.wikipedia.org/wiki/Quakers_in_Costa_Rica
- Wikipedia — *Monteverde Cloud Forest Reserve*: https://en.wikipedia.org/wiki/Monteverde_Cloud_Forest_Reserve
- Vacations Costa Rica — *History of Monteverde*: https://www.vacationscostarica.com/monteverde/history/
- Monteverde Tours — *History of Monteverde and the Quakers*: https://monteverdetours.com/history-of-monteverde.html
- BAC Credomatic — *Compra Click*: https://www.baccredomatic.com/es-cr/pymes/compra-click

---

*Say "go" and Phase 0 starts.*
