# Muse strategy plan · Claude's review

**Status: REVIEW AND PROPOSAL.** The owner asked Claude to analyse and incorporate the Muse plan ([`STRATEGY-MUSE.md`](STRATEGY-MUSE.md)), recorded as BD-014. Where the plan conflicts with an earlier owner decision, the earlier decision stands until the owner chooses (BQ-34 to BQ-36). Build status stays ON HOLD. No code.

Written 2026-10-20 by Claude.

---

## 1. Verdict

A strong, professional plan. About four fifths of it matches what is already planned. It adds three things this project lacked, and those should be adopted:
1. a **Knowledge Hub**, a content engine of guides that answers real traveller questions;
2. a **measurement and ads layer** wired in from day one;
3. **one page per room type**, built to double as an ad landing page.

It also has three problems:
- It assumes the business has no booking engine. Basecamp has Hotel Link, and the owner chose instant confirmed booking (BD-009).
- It adds café and tour sections, which conflicts with the owner's Basecamp-only decision (BD-006).
- A few of its technical promises are stronger than the evidence (section 5).

---

## 2. Already in the plan

| Muse item | Where it already is |
|---|---|
| Fully bilingual with hreflang, not a translate widget | `CODEX.md` rule 8; `ARCHITECTURE.md` P-01 |
| Mobile first, weak connections | `CODEX.md` rule 9; acceptance criteria in the first review |
| Core Web Vitals green, modern images, light pages | Proposed criteria: LCP 2.5 s or less, INP 200 ms or less, CLS 0.1 or less, first load under 1 MB. Muse allows about 1.5 MB, so ours is stricter. |
| Real visual concept, not a template | Brand kit question BQ-05. The café already uses a naturalist engraving style that fits Muse's "field journal" direction. |
| Structured data, llms.txt, fact-dense about page | `CODEX.md` section 4, "AI-agent ready" |
| 301 map for old URLs | BQ-18, launch phase |
| Persistent mobile action bar | Booking bar pinned to the bottom on phones |
| Real photos for the product, atmosphere images fine | Hero rules in `RESEARCH.md` section 7 |
| Review flywheel, Google profile, entity cross-links | `CODEX.md` marketing list; BQ-13, BQ-15 |
| Templates, fields and slots instead of content | The Owner Dashboard (BD-010, `ARCHITECTURE.md` section 2) |

---

## 3. New, and proposed for adoption

| Item | How it fits | Cost |
|---|---|---|
| **One page per room type**, three pages plus a short overview that links to them | Replaces the single Rooms tab. Each page carries photos, beds, guests, inclusions, a Book button and a WhatsApp button. Each can serve as an ad landing page. | $0 |
| **Knowledge Hub** with reusable templates: destination pillar, seasons, getting here, packing, activity explainers, niche guides, town guide, itineraries, local stories, master FAQ | A new **Guides** section in the dashboard, so the owner can publish without a developer. Links back to the café's existing guides rather than duplicating them. | $0 |
| **Guide skeleton**: full answer in the first third, local depth, photos, links to room pages, a soft WhatsApp prompt, FAQ block with markup | Built into the guide template | $0 |
| **Per-page prefilled WhatsApp message** | Each page sends a different first line, so staff know where every chat started | $0 |
| **"Find us" page in landmark language** | Matches the café's existing address style: "50 m south and 50 m east of the church" | $0 |
| **Reviews page** quoting real guest words, each linked to its source profile, and short quotes beside every Book button | A **Reviews** section in the dashboard | $0 |
| **Measurement from day one**: Google Analytics 4, Search Console, an event list | Page views, room views, Book clicks, WhatsApp clicks, calls, directions, review-link clicks | $0 |
| **Meta Pixel and Conversions API** for future ads, with a written UTM convention | The Conversions API needs a small server piece, which can run on Cloudflare's free Workers plan (BQ-36) | $0 |
| **60-second friction test**: from landing to an open chat or booking screen in under 60 seconds on a slow phone connection | Added to the acceptance criteria | $0 |
| **Title and description templates** per page type, in both languages | Part of each template. The Spanish versions are written natively for Spanish searches, never translated from English (Muse). | $0 |

---

## 4. Conflicts with earlier owner decisions

| Muse says | Owner decision so far | Claude's recommendation | Decision |
|---|---|---|---|
| Four sections: lodging, on-site food and drink, experiences, Knowledge Hub | BD-006: Basecamp only; café and tours as links | **Keep Basecamp at the centre and add the Knowledge Hub.** Treat activities as visitor guides that link to the tour business the owner chooses (BQ-03), not as products sold here. Give the café **a full section of the lodge experience, not a passing mention**, as Muse added (section 10). Write it from the guest's side, using confirmed facts: open from 6:00, an hour before the reserve, and ordering from the room by QR card. Link to hanginggardencafe.com for the menu and its guides rather than copying them, so the two sites do not compete for the same searches. | BQ-34 |
| "The conversion is a conversation"; one primary action, the chat button; no competing calls to action | BD-009: instant confirmed direct reservations through Hotel Link | **Pick the primary action by page type.** Room pages: Book now, with WhatsApp beside it as the second choice. Guides and the home page: WhatsApp first, Book second. Track both. | BQ-35 |
| Price and what it includes near the top of every room page | BQ-31: ChatGPT recommends live prices only, never typed by hand | **Ask Hotel Link whether a live "from" price can be shown on the page** (question 13). If not, show what the rate includes plus a "See today's price" button that opens the booking widget on that room. | BQ-31 |
| Anti-pattern: "a booking flow that depends on a third-party engine the business doesn't have" | Basecamp has Hotel Link | Does not apply. The concern behind it still holds: **WhatsApp must always work, even if the booking engine fails.** That is already the fallback. | None |

---

## 5. Corrections to the plan, with evidence

| Muse claim | What the evidence says | Adjustment |
|---|---|---|
| Be option #1 or #2 for searches like "hotel in [destination]" | Head terms are dominated by booking sites and Google's own hotel results. A search for "hotels in Monteverde" for this review returned almost only Expedia pages ([example](https://www.expedia.es/en/Monteverde.dx6046749)). | Set realistic goals: the local map results, long-tail guide searches, AI-assistant answers, and direct conversations (section 7). |
| AggregateRating markup from on-page reviews | Google does not show review stars for a business's reviews of itself on its own site, which covers LocalBusiness and its subtypes, hotels included ([Google, 2019](https://developers.google.com/search/blog/2019/09/making-review-rich-results-more-helpful)). | Show real reviews with source links. Do not count on stars in search results. Google Business Profile reviews are unaffected. |
| llms.txt helps AI assistants cite the site | Log studies found that 97% of llms.txt files received no AI requests, and Google says it does not use the file ([PPC Land summary of Ahrefs data](https://ppc.land/llms-txt-adoption-rises-8-8x-but-97-of-files-get-zero-ai-requests/)). | Keep it, since it costs nothing, but rely on the fact-dense about page and structured data. |
| Conversions API "from day one" | It sends events from a server, so it needs a server piece | A free Cloudflare Worker, only if the owner approves BQ-36 |
| Pixel and analytics everywhere | Costa Rica's Ley 8968 requires informed consent to process personal data, and many visitors come from countries with consent rules for cookies | An open-source consent banner. Ads and analytics tags load only after consent. |
| Track bookings | Hotel Link's checkout runs on Hotel Link's page, so the website cannot see a completed booking by itself | Ask Hotel Link whether its engine accepts Google Analytics and Meta Pixel IDs and reports completed bookings (question 13) |
| Guides at a steady cadence | Thin or generic text harms rankings, as Muse itself warns | Claude researches and drafts; the owner or staff add local knowledge and check every fact before publishing |

---

## 6. What changes in the architecture

All still at **$0 new monthly cost**.

- **Dashboard:** new **Guides**, **Reviews** and **Tracking** sections. Tracking holds only public IDs, such as the analytics ID and pixel ID. Every page gets a field for its own WhatsApp message.
- **Room pages:** three pages plus an overview, in each language.
- **Consent banner:** open source, both languages, nothing loaded before consent.
- **Conversions API helper:** optional free Worker. Its access token lives in Cloudflare's secret store, never in the repository.
- **Speed:** analytics and pixel load after consent and after the page is usable, so they do not slow the first view.

---

## 7. Realistic search goals (input for BQ-21)

Numbers are left out on purpose; the owner sets them.
1. In the top three of Google's map results for lodging searches in Santa Elena.
2. Ranking for a growing list of guide questions. Each guide is tracked in Search Console.
3. Named correctly by AI assistants when asked where to stay in Santa Elena or Monteverde.
4. More WhatsApp conversations and direct bookings each month, by source page.
5. A rising share of bookings that come direct rather than through booking sites.

---

## 8. Combined build order (proposal; replaces `ARCHITECTURE.md` section 10 once approved)

| Phase | Delivers |
|---|---|
| 1 · Plan review (no code) | This review; owner decisions; dashboard and page sketches; brand |
| 2 · Foundations | Templates, dashboard, image pipeline, consent banner, analytics, event list, structured-data framework, home page, three room pages, WhatsApp funnel; private preview |
| 3 · Booking and location | Hotel Link adapter, "find us" page, master FAQ, about page, rate check |
| 4 · Hardening | Security headers, backups, restore drill, 60-second friction test, staff guide |
| 5 · Launch | Owner points the domain; 301 map; old Orchid domain forwarded |
| 6 · Knowledge Hub | Guide templates and the first five or six guides; reviews page and review prompts |
| 7 · Growth | Steady guide cadence; Google Free Booking Links; ads only when the owner decides |

---

## 9. Owner decisions

| ID | Decision |
|---|---|
| BQ-34 | Scope. Keep Basecamp-only plus the Knowledge Hub, as recommended, or add full café and experience sections as Muse proposes. |
| BQ-35 | Primary action. Choose by page type, as recommended: Book first on room pages, WhatsApp first on guides. Or make WhatsApp the only primary action everywhere. |
| BQ-36 | Measurement stack. Google Analytics 4, Search Console, Meta Pixel, and the Conversions API helper as a free Worker, all behind a consent banner. All free. |
| BQ-31 | Price display, updated. A live "from" price from Hotel Link if it exists; otherwise inclusions plus a "See today's price" button. |

---

## 10. Muse's response to this review (2026-10-20, relayed by the owner)

Muse is the owner's marketing advisor and wrote the source plan. Its positions are advice, not owner approvals.

| Point | Muse's position | Status |
|---|---|---|
| Head terms against booking sites | Accepts the correction. New ambition: first or second in the map results, long-tail searches, AI answers and direct conversations. | Goal in section 7 matches |
| No review stars for own reviews | Accepts. The reviews page serves trust and the human reader. | Matches section 5 |
| llms.txt | Accepts. Kept at no cost; the about page and structured data carry the weight. | Matches section 5 |
| Conversions API server piece and consent banner | Accepts with no objection. | Matches BQ-36 |
| BQ-34 scope | Agrees with Basecamp plus the Knowledge Hub, tours as guides linking to what Muse calls the sister tour business; which business that is remains open (BQ-03). **Nuance: the café must be a full section, not a decorative block,** because it is a real reason to book direct: "wake up with this coffee downstairs." | Incorporated in section 4 |
| BQ-35 primary action | Agrees with the hybrid. Book first on room pages with WhatsApp visible as the human backup; WhatsApp first on guides; let the data decide. The original "the conversation is the conversion" assumed no booking engine. | Matches section 4 |
| BQ-31 price | Agrees. Live "from" price if Hotel Link gives one, otherwise inclusions plus "See today's price". Never hide the price until the end. | Matches section 4 |
| BQ-36 measurement | First message: not judged. **Audit: recommends approval with two conditions.** (1) The event map is fixed now and never renamed. (2) The Conversions API helper sends server events with deduplication IDs matching the browser Pixel. | Conditions built into section 12. Owner approval still needed. |
| Hotel Link question 13 | **Critical, a business question.** If bookings finish on Hotel Link's site and it rejects our tags, paid campaigns cannot be measured. | Raised to priority, section 11 |
| Fallback order (audit) | C, the return to our thank-you page, is best. B, per-campaign promo codes, is the attribution backup. A, the Book click, is the acceptable floor. Adds a weekly manual reconciliation. | Added as option F in section 11 |
| Spanish titles and descriptions (audit) | Write them natively in Spanish, never translated from English. | Added to section 3 |
| Guide facts (audit) | Muse keeps a base of verified facts and can draft guides; the owner validates local facts before publishing. | Agreed. One fact base only: Muse's verified facts go into `RESEARCH.md` through the owner, labelled like every other fact. |
| Search goal numbers (audit) | The owner sets them at launch, not before. | Agreed, section 7 |
| Overall (audit) | Audit complete; no further marketing objections. BQ-31, BQ-34 and BQ-35 carry matching recommendations from Claude and Muse; the final word is the owner's. | Recorded |

The audit was signed "Lapis (marketing lead)". This file assumes Lapis is the same advisor the owner calls Muse.

---

## 11. Measuring bookings when checkout runs on Hotel Link (question 13, priority)

**Why it matters.** Guests choose dates on our site but pay on Hotel Link's page. If that page cannot carry our Google Analytics and Meta Pixel tags, no campaign can be credited with a booking. The site works either way, and ads stay dormant until the owner decides. But this answer decides whether paid campaigns can ever be judged on bookings rather than clicks.

**Ask Hotel Link first** (`RESERVATIONS.md` section 8, question 13 and its sub-questions).

**If the answer is no, these fallbacks exist.** None is verified with Hotel Link yet.

| Option | How it works | Cost | Evidence |
|---|---|---|---|
| A. Count "Book" clicks on our site as the conversion | The last step we control is tracked as the success event | $0 | Ours, works for sure, but measures intent, not payment |
| B. A promo code per campaign | Each campaign advertises its own Hotel Link promo code; booking reports show which code was used | $0 | Promo codes in Hotel Link and per-campaign reporting: Unknown, sub-question 13d |
| C. Return to our own thank-you page | If Hotel Link can send the guest back to an address we choose after booking, that page records the conversion | $0 | Unknown, sub-question 13c |
| D. Upload completed bookings to Google and Meta | A monthly export from Hotel Link, matched to campaigns and uploaded to the ad platforms, which accept offline conversions | $0, manual work | Inferred; Hotel Link export: Unknown |
| E. Change booking provider | Choose a provider that supports the tags, using the adapter (BD-012) | Depends | Last resort; only on the owner's explicit decision |
| F. Weekly manual reconciliation (added by Muse) | Each week, compare Hotel Link's booking report with the spend of each campaign. Even if everything automatic fails, we are never fully blind. | $0, manual work | Ours. The Owner Dashboard edits content and cannot hold reports, so this lives in a free spreadsheet. |

**Order of preference** (Muse): C, then B, then A as the floor, with F always running once ads start. D is an extra if Hotel Link exports bookings with their source.

**Recommendation.** Ask now, before Phase 2. Design the site so options A and B work from day one whatever Hotel Link answers. Add C or D once Hotel Link's answer is known.

---

## 12. Event map v1 (proposal, fixed once BQ-36 is approved)

Muse's first condition: these names and meanings are set now and **never renamed or reused**, so the history stays comparable. New events may be added later; existing ones never change. Google Analytics 4 recommended event names and Meta standard event names are used wherever one fits, because the ad platforms optimise best on their own standard events.

| Visitor action | Meaning | Google Analytics 4 | Meta | Where |
|---|---|---|---|---|
| Opens any page | Page view | `page_view` (automatic) | `PageView` | Every page |
| Views a room page | Interest in a specific room | `view_item` | `ViewContent` | Each room page |
| Clicks **Book** or **See today's price** | **Booking intent**, the floor conversion (option A) | `begin_checkout` | `InitiateCheckout` | Room pages, booking bar, home |
| Clicks **WhatsApp** | **Lead**, the conversation | `generate_lead` | `Lead` | Every page |
| Clicks call | Lead by phone | `phone_call` (custom) | `Contact` | Every page |
| Clicks directions | Intent to visit | `get_directions` (custom) | none | "Find us" page, footer |
| Clicks a review link | Trust and review flywheel | `review_link_click` (custom) | none | Reviews page, footer |
| Lands on our thank-you page after paying, only if Hotel Link allows it | **Completed booking** (option C) | `purchase` with value | `Purchase` with value | Thank-you page |

**Details carried with every event:** page address, page type, room type if any, language, and the campaign tags in the address, if any. The WhatsApp event also carries the ID of the prefilled message, so each conversation maps to its source page.

**Deduplication, Muse's second condition.** For each Meta event, the browser creates one random event ID. The Pixel sends it, and the Conversions API helper sends the same event name with the same ID from the server. Meta then counts one conversion, not two. The helper sends nothing for visitors who declined consent. Its Meta access token lives in Cloudflare's secret store.

**Naming rule** for the future: lower-case words joined by underscores in Google Analytics, Meta's own spelling for Meta, and a new row here before any new event goes live.
