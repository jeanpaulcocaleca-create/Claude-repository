# The Hanging Garden — "Canopy OS" Proposal (v4, Final)

**An all-in-one system for a coffee experience in Monteverde, Costa Rica**

**Status: GO — approved with Phase 0 diligence.** No code yet; Phase 0 (discovery) is the next step.

---

## What's new in v4

Engineering review adopted in full:

- **Load & resilience test plan** written in Phase 0, executed as a launch gate at the end of each phase — POS sync edge cases, Nora feed performance, backup/restore speed.
- **Supplier view added to the inventory schema** — supplier contacts, reorder thresholds, and per-ingredient cost history, enabling gross-margin tracking.
- **POS "lite mode"** for days when Monteverde's internet is spotty at the DNS/CDN level, not just slow.
- **Design QA checklist** so the cinematic site is also a usable one: mobile-first pass, iOS Safari scroll handling, and accessibility-tested palette.

---

## 1. The Vision

Monteverde sits on the tourist trail between the cloud forest, the hanging bridges, and the coffee farms. Visitors aren't buying a cup of coffee — they're buying a Costa Rican coffee *experience*. Canopy OS reflects that:

- **Outward:** a one-of-a-kind cinematic website that ranks on Google and turns tourists planning their Monteverde days into visitors — with Nora greeting them in chat.
- **Inward:** one operational backbone — POS, menu, orders, sales, time clock, payroll — running from a single tablet, surviving Monteverde's internet.
- **Connecting both:** Nora, our existing WhatsApp assistant, integrated on the website and fed live data.

---

## 2. The Website — One of a Kind

### Toolchain

- Built on the **10K Websites** cinematic scroll-driven workflow (hero video, scroll choreography, deploy pipeline).
- **Higgsfield generates the visual world:** the hero film, vintage-style illustrations, textures, and section imagery — custom-made for The Hanging Garden, owned by us, impossible to find on another site.

### The signature moment: *La Gota* (the drip)

The homepage opens on a **chorreador** — the traditional Costa Rican wooden brewing stand with its cloth *bolsita*. As you scroll, a single thread of coffee begins to drip from it and **travels down the page with you**: it becomes the line that connects every section, pooling and pouring past the story, the menu, the experiences — until at the final section it lands in a waiting cup, filling it as the page ends at "visit us." One continuous pour, top to bottom.

Craft notes: scroll-linked SVG path + canvas fluid effects choreographed with GSAP ScrollTrigger; a calm static version for `prefers-reduced-motion` and low-power phones; the drip never blocks reading or drags the page below Google's Core Web Vitals bar — the SEO promise survives the cinema.

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
- **1953:** They found the cheese factory that sustains the community — and deliberately protect the forested watershed above their farms instead of clearing it.
- **1966:** Herpetologist Jay Savage describes the **golden toad**, found nowhere on Earth but the Monteverde ridge. Scientists pour in from around the world.
- **1972:** The **Monteverde Cloud Forest Reserve** is founded, growing into one of Costa Rica's most treasured protected areas; children worldwide later fund the **Bosque Eterno de los Niños**, the Children's Eternal Rainforest.
- **1989:** The golden toad is seen for the last time — Monteverde's standing reminder of why stewardship matters.

**The area's ideologies become the brand's stated values:** *peace* (founded by people who refused war, in a country that disarmed), *simplicity* (Quaker plainness — honest coffee, honest prices), *stewardship* (protect the watershed, waste nothing), and *community* (cooperatives, neighbors, and tour guides all drinking at the same counter). The Hanging Garden's own hanging plants tie the garden into the canopy story.

Everything bilingual (EN/ES), structured data for Google rich results, Google Business Profile sync, and a receipt-QR review funnel — the beauty serves the SEO, never replaces it.

### Design QA checklist (launch gate for the site)

1. **Mobile-first test pass is mandatory** — the site is designed and reviewed at phone width first (that's where tourists are), then enhanced upward; every scroll scene must earn its place on a small screen or degrade to a still.
2. **iOS Safari scroll bugs pre-empted by architecture:** no scroll-jacking — native scrolling always, with animations driven *by* scroll position (transform/opacity only, off the main thread where possible); tested against rubber-band overscroll, the collapsing address bar (`svh`/`dvh` units, never bare `100vh`), and momentum-scroll jumps on ScrollTrigger pins.
3. **Golden-toad palette accessibility-tested:** every text/background pair checked to WCAG AA contrast — the gold is decoration and large display type only, never body text on mist; states and links never rely on color alone.
4. **Performance budget enforced:** Core Web Vitals green on a mid-range Android over throttled 3G; hero video lazy/poster-first; reduced-motion honored.

---

## 3. The Operating System — Modules

**A. Website & Google** — as above, plus the live menu fed from the menu manager and Nora's chat widget + WhatsApp button.

**B. Point of Sale** — offline-first tablet PWA; cash in CRC and USD with live exchange rate; **card via our existing BAC San José terminal** (payments recorded against orders so reports reconcile with the BAC statement); **BAC payment link for everything online** (bookings, deposits, pickup orders — marked paid on confirmation, landing in the same reports as counter money); **SINPE Móvil** with QR + reference matching; 13% IVA on every receipt; tips pooled into payroll.

**Low-bandwidth by design, plus a "lite mode":** the POS is an installed PWA, so its entire shell — screens, menu grid, logic — lives on the tablet and never depends on a CDN or DNS at ring-up time; the only network need is one sync endpoint, retried with backoff. On top of that, a **lite mode** (automatic when the connection degrades, or toggled by hand): photos off, text-only menu grid, receipts queued for email instead of printed graphics, sync batched to whatever window of connectivity appears. A visible status chip — *online / offline / degraded* — so staff always know which world they're in.

**C. Menu Manager** — one source of truth for POS, website, and Nora. Bilingual items, photos, modifiers, availability toggles ("86 the banana bread" updates everywhere within a minute), seasonal scheduling.

**D. Sales & Electronic Invoicing** — live order board; daily dashboard (revenue, average ticket, payment mix, best sellers, sales by hour); season-over-season reports and accountant CSV exports; **factura electrónica module (Hacienda v4.4)** with per-document status tracking — *sent / accepted / rejected* — so any sale's Hacienda invoicing status is one lookup away, XML/PDF on file.

**E. Time Clock** — PIN clock in/out on the tablet with optional photo; breaks, shift notes, live "who's on"; automatic timesheets per pay period; **sized for 5 now and 10–15 later**, with roles and a shift schedule ready as we grow.

**F. Payroll Ledger** — pay computed from the clock under Costa Rican rules (overtime 1.5× past 8 hrs/day), tip shares, **CCSS contributions and aguinaldo accrual** tracked so December never surprises us; pay statements with payments recorded against them. (Ledger and calculator — money moves through the bank app at first; automated disbursement is a careful later phase.)

**G. Nora Integration** — she's already built; the work is three connections: (1) **website chat widget + WhatsApp deep link** — one assistant, two doors; (2) a **live read-only data feed** from Canopy OS (menu, availability, prices, hours, closures, bookings) so her answers are always current; (3) later, a **write endpoint** so she can place pickup orders and holds — and deliver the owner's morning briefing over WhatsApp, where she already lives.

---

## 4. Inventory & Supplier Schema (from day one)

The database is born with the full commercial picture, so later intelligence is a feature flip, not a migration:

- `ingredients` — with **minimum reorder threshold and lead time** per ingredient, so "low stock" means *reorder now or run out*, not a guess.
- `recipes` — menu item → ingredient quantities (a latte = beans + milk), driving auto-deduction on every sale.
- `stock_movements` and a **waste log** with reasons — shrinkage visible in colones, not vibes.
- `suppliers` — **contacts (name, WhatsApp, delivery days, payment terms)** linked to the ingredients they provide, so a reorder alert comes with the person to message.
- `purchase_history` — **cost per ingredient per purchase**, building a cost curve over time. Combined with recipes, this yields **gross margin per menu item** and true margin trends as supplier prices move — the foundation for forecasting and pricing decisions in Phases 2–3.

Phase 2 ships the daily habits: receive stock, auto-deduct on sale, log waste, reorder alerts with supplier contact attached.

---

## 5. Reliability: Backups, Recovery & Load Testing

**Disaster recovery (small, real, rehearsed):** automatic nightly database backups with point-in-time recovery; a one-tap **"export everything"** button (sales, timesheets, payroll, invoices → CSV/JSON to email or Drive); the POS offline cache doubling as a same-day buffer; a laminated **tablet restore runbook** at the counter (any spare tablet becomes the POS in under 5 minutes); a quarterly restore drill.

**Load & resilience test plan — written in Phase 0, executed as a launch gate at the end of each phase** (a test needs a built thing to break, so authorship and execution are split):

1. **POS offline-to-online sync edge cases** (gate for Phase 1): scripted synthetic scenarios — two tablets selling the same last item offline; a sync interrupted mid-batch and resumed; overlapping edits to one order; device clock drift; duplicate-receipt prevention on retry; a full day's orders (several hundred) accumulated offline and flushed at once. Pass = zero lost or duplicated orders in every scenario.
2. **Nora's update feed performance** (gate for Phase 1): the read API is cached and CDN-fronted with stale-while-revalidate; synthetic burst tests (a tour bus of phones asking Nora about the menu at once) must hold p95 response under ~300 ms, and a menu change must propagate to her answers within 60 seconds.
3. **Backup/restore speed under load** (gate for Phase 2, re-run quarterly): timed restore drill against a database seeded with a full high season of synthetic sales while synthetic traffic runs. Pass = documented restore time under 30 minutes, measured not assumed.

---

## 6. Security & Accountability

Immutable audit log on every sensitive action (who/what/when/before/after): price changes, menu edits, refunds and voids, shift edits, payroll adjustments, role changes. Granular roles (owner / manager / barista with per-permission overrides) — essential at 10–15 staff. **Optional MFA (TOTP app or WhatsApp code) for owner and manager accounts**; PIN-only baristas can't touch pricing, payroll, or exports; refunds/voids above a threshold require a manager PIN.

---

## 7. Architecture

| Layer | Choice | Why |
|---|---|---|
| Website build | 10K Websites cinematic workflow + Higgsfield assets | One-of-a-kind scroll site; custom-generated imagery we own |
| App | Next.js — one codebase: website, POS, admin | Fast, SEO-friendly, installs as a tablet PWA |
| Data & auth | Supabase (Postgres, realtime, RLS) + nightly backups | One source of truth; roles for 5 → 15; DR built in |
| Offline POS | Local-first PWA, single sync endpoint, lite mode | No CDN/DNS dependency at ring-up; survives spotty Monteverde internet |
| Payments | BAC terminal + BAC payment link + SINPE Móvil | No new processor; manual → automatic upgrade path |
| Nora | Integration API — cached read feed now, write later | Our existing assistant becomes the front door |
| Audit & security | Immutable audit log; granular roles; optional MFA | Accountability as the team grows |
| Hosting | Vercel + Supabase cloud | ~$0–45/month at café scale; no servers to babysit |

---

## 8. Roadmap

| Phase | Delivers |
|---|---|
| **0 · Discovery (1–2 weeks)** | Nora technical questionnaire; BAC executive conversation — gateway API + reconciliation reports; SINPE notification test; Hacienda régimen confirmation; hardware inventory; **load & resilience test plan authored**; design QA checklist finalized |
| **1 · Be found & sell** | Cinematic website with *La Gota* scroll + the Monteverde story chapter (10K Websites + Higgsfield), shipped through the design QA gate; SEO + Google Business Profile; menu manager; POS with cash/BAC/SINPE, IVA, receipts, **lite mode**; **Nora on the website** (cached feed, perf-gated); backups + export + restore runbook; audit-log foundation. **Gates: POS sync stress test, Nora feed burst test, design QA checklist** |
| **2 · Know the business** | Sales dashboard & reports; order board; factura electrónica with Hacienda status tracking; experience bookings paid by BAC link; **stock deduction, waste log, supplier reorder alerts, cost history → gross margin per item**. **Gate: timed backup/restore drill under load** |
| **3 · Run the team** | Time clock; timesheets; payroll ledger with Costa Rican labor rules; tip pooling; shift schedule; granular roles + optional MFA |
| **4 · Nora acts & advises** | Nora places pickup orders and bookings; owner morning briefing via WhatsApp; forecast-driven inventory and prep suggestions built on the cost/margin data |

---

## 9. Sources & further reading

- Friends Journal — *The Quaker Stewards of Costa Rica's Monteverde Cloud Forest*: https://www.friendsjournal.org/the-quaker-stewards-of-costa-ricas-monteverde-cloud-forest/
- Wikipedia — *Quakers in Costa Rica*: https://en.wikipedia.org/wiki/Quakers_in_Costa_Rica
- Wikipedia — *Monteverde Cloud Forest Reserve*: https://en.wikipedia.org/wiki/Monteverde_Cloud_Forest_Reserve
- Vacations Costa Rica — *History of Monteverde*: https://www.vacationscostarica.com/monteverde/history/
- Monteverde Tours — *History of Monteverde and the Quakers*: https://monteverdetours.com/history-of-monteverde.html
- BAC Credomatic — *Compra Click*: https://www.baccredomatic.com/es-cr/pymes/compra-click

---

*Verdict recorded: GO, with Phase 0 diligence. Phase 0 starts on your word.*
