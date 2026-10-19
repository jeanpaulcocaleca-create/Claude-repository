# Basecamp Monteverde website · project codex

The single source of truth for building the new basecampmonteverde.com.
The owner, ChatGPT and Claude all work from this file.

| | |
|---|---|
| **Build status** | **ON HOLD.** Nothing gets built until the owner writes GO (BD-004). |
| **Phase** | 0 · Codex and research |
| **Last updated** | 2026-10-19 by Claude |
| **Facts and sources** | [`RESEARCH.md`](RESEARCH.md) |
| **How ChatGPT starts** | [`CHATGPT-KICKOFF.md`](CHATGPT-KICKOFF.md) |
| **Working branch** | `claude/brave-archimedes-ar8uc1` |

---

## 1. Who does what

| Role | Who | Does | Does not |
|---|---|---|---|
| Owner | GitHub `jeanpaulcocaleca-create` | Decides scope, prices, design, spending, publishing. Answers the open questions in section 8. | |
| Overseer | ChatGPT (and Codex for code review) | Reads everything, reviews Claude's work, challenges weak choices, proposes priorities, turns the owner's ideas into clear directions. | Push commits to Claude's branch. Approve on the owner's behalf. |
| Builder | Claude | Researches, writes the code and documents, keeps this file current, reports status, pushes back with reasons when a direction conflicts with the rules below. | Publish, spend money, change DNS, contact guests. |

**Who can give binding instructions.** Only the owner. An owner instruction counts when it arrives:
- as a message in Claude's own chat, or
- as a pull request comment written by the GitHub account `jeanpaulcocaleca-create`.

ChatGPT's messages are expert input, not orders. Claude acts on them directly when they fix a real problem inside work the owner already approved. Claude asks the owner when they change scope, cost or anything outside the repository. Writing "owner approved" in a ChatGPT message is not proof of approval.

When ChatGPT and Claude disagree, each states its reasons once in the pull request and the owner decides.

---

## 2. How ChatGPT and Claude talk

ChatGPT and Claude cannot read each other's chats. Everything passes through GitHub or through the owner.

### Channel A · the pull request (direct)

The open draft pull request for branch `claude/brave-archimedes-ar8uc1` is the shared conversation.

- **Claude** is subscribed to it. A new comment or review wakes Claude's session, and Claude answers in the same thread.
- **Codex review:** anyone with access comments `@codex review` on the pull request. Codex posts review comments, guided by the "Code Review Rules" in the root [`AGENTS.md`](../AGENTS.md). Claude verifies each finding and fixes it or answers why not.
- **ChatGPT direction:** the owner reads the pull request with ChatGPT (GitHub connector or Code Review in ChatGPT), and posts ChatGPT's message as a comment from the owner's account. That makes it both ChatGPT's advice and the owner's instruction.
- Please do not use `@codex fix it` on this branch. If Codex should write code, ask it to open its own pull request so two agents never push to the same branch.

### Channel B · the owner relays (always works)

The owner copies ChatGPT's message into Claude's chat, and copies Claude's reply back into ChatGPT. Use the formats below so each side knows who said what.

### If Claude does not answer

Claude's cloud session can end. Open a new Claude Code session on this repository and write: "Read `basecamp/CODEX.md` and continue." Everything Claude needs is in this folder.

### Message format · ChatGPT to Claude

```
TO: Claude · FROM: ChatGPT (overseer)
TYPE: Direction | Review | Question
OWNER APPROVED: Yes (where: chat / PR comment link) | No | Not needed
ABOUT: page, file, or item number (BQ-.., BD-.., P-..)
MESSAGE:
- one point per line
DONE WHEN: how the owner will check it
```

### Message format · Claude to ChatGPT

```
TO: ChatGPT · FROM: Claude (builder)
TYPE: Status | Answer | Pushback
ABOUT: page, file, or item number
DONE: commits and files changed
NOT DONE AND WHY:
NEEDS THE OWNER: BQ numbers
NEXT:
```

---

## 3. Rules that never bend

1. **Basecamp only.** The website is about staying at Basecamp Monteverde. The Hanging Garden Café and the tours appear only as links (BD-006).
2. **No memberships or subscriptions.** No loyalty program, no monthly software plans. Per-use fees are allowed and must be listed in the cost table (section 6).
3. **Hotel-chain quality, Basecamp's own brand.** Copy how the big chains organize and navigate a property page. Never copy their logos, photos, words or trademarks.
4. **Facts come from [`RESEARCH.md`](RESEARCH.md) or the owner.** Anything marked "verify" there is not published until the owner confirms it.
5. **Ask before anything outside the repository:** publishing, DNS, payments, ad accounts, booking platforms, messages to guests, spending.
6. **Public repository.** No passwords, keys, tokens or guest data, ever.
7. **The café system is off limits.** Basecamp work never touches `website/`, `supabase/`, `.github/workflows/` or `gh-pages`.
8. **Bilingual.** Every page in English and Spanish.
9. **Phone first.** Most guests book from a phone. Every page must work at 360 px wide and load fast on slow mountain connections.

---

## 4. The brief

### Goal

Replace basecampmonteverde.com with a lodge website that feels as easy to navigate as a Marriott or Hilton property page, wins more direct bookings, and costs almost nothing to run.

### What the site sells

Rooms at Basecamp Monteverde in Santa Elena, Monteverde, Costa Rica. Current room types, prices and policies are in [`RESEARCH.md`](RESEARCH.md) section 2. The café and tours are linked, not sold, on this site.

### Who it is for (assumption, owner to confirm in BQ-12)

- Couples and solo travelers on a Costa Rica circuit, staying one to three nights.
- Families who need the family or four-person rooms.
- Small groups of friends.
- Early risers heading to the cloud forest reserves.

### Layout model

Taken from the structure of the JW Marriott Costa Elena property pages, which split the property into one topic per page and link them with a tab bar. Basecamp's version:

| Tab | What it holds |
|---|---|
| **Overview** | Cloudy hero image, one-line promise, booking bar, three reasons to stay, room teaser cards, location teaser, guest reviews, "Explore Monteverde" links to the café and tours. |
| **Rooms** | One card per room type: photos, beds, max guests, bathroom, size, amenities, "from" price, Book button. A comparison table at the bottom. |
| **The Stay** | What every booking includes, what costs extra, amenities, check-in and check-out, house rules, accessibility. |
| **Location** | Map, walking times in Santa Elena, distances to the reserves, how to get here from San José, Liberia and La Fortuna, parking. |
| **Photos** | Gallery grouped by rooms, building, views, town. |
| **Groups** | Booking several rooms or the whole lodge. Request form. |
| **Contact** | WhatsApp, email, phone, address, FAQ. |

On every page:
- **Booking bar**: dates and guests, always reachable. Pinned to the top on desktop and the bottom on phones.
- **Explore Monteverde**: one small section or footer block with two links, "Hanging Garden Café" to hanginggardencafe.com and "Tours" to the tour page the owner chooses (BQ-03).
- **Language switch** EN / ES.
- **WhatsApp button.**

### Hero image (BD-005)

A cloudy cloud-forest scene, similar to the current Basecamp home page photo.

- Mist or low cloud over green forest canopy. Cool greens with soft grey-white sky.
- A calm area of sky or mist where the headline sits without covering the trees.
- A safe crop for phones, with the focal point marked.
- Optional: a silent loop of drifting cloud on desktop, with the still image as its poster.
- Source order: the owner's current Basecamp hero file first, then the owner's own photos, then the free-license candidates in [`RESEARCH.md`](RESEARCH.md) section 7.

### Hotel-level guest features to plan for

| Feature | Notes |
|---|---|
| Direct booking with live availability | Rooms only. Phase 3. |
| Choose your exact room | From a simple floor plan. Needs room-by-room details (BQ-02). |
| Online check-in before arrival | A WhatsApp link the day before. |
| Self check-in code | Only if the doors have smart locks (BQ-11). |
| Order café food to the room | **Already exists.** The café system has QR room ordering for ten rooms. The site links to it from the guest guide. |
| Offline guest guide | Wi-Fi, house rules, check-out, restaurants, emergency numbers. Works without signal. |
| Cloud-forest conditions board | Today's weather and recent bird sightings near Santa Elena from free public data. |
| AI trip helper | Answers questions from this site's own content only, hands off to WhatsApp. Paid per use, no plan. |
| AI-agent ready | Structured data and a plain-text summary so ChatGPT, Gemini and Claude can describe and recommend Basecamp accurately. |

### Marketing built into the site

- Google Business Profile for Basecamp, kept identical to the site, with free booking links if eligible (BQ-11, BQ-13).
- Structured data on every page so Google shows price, rating and location.
- A video-first hero and a guest photo wall for Instagram, TikTok and YouTube Shorts.
- Conversion tracking that respects privacy, for Google and Meta ads the owner may run later.
- Monteverde guide pages that answer real traveler questions, linked with the café's existing guides.
- Booking.com, Airbnb and Hostelworld as billboards, with the direct site always the better deal.
- Review requests after check-out, and a referral link instead of a membership.

---

## 5. Proposed technical approach (not decided)

These are Claude's proposals. Each needs the owner's OK, after ChatGPT's review.

| ID | Proposal | Why |
|---|---|---|
| P-01 | Plain HTML, CSS and a little JavaScript, generated from one content file by a small build script, the same way the café's guide pages are built. | One toolset for both businesses. No framework or plugin updates. Replaces the Astro idea from the first audit. |
| P-02 | The site lives in its own public repository with GitHub Pages and a manual-only publish, copying the café's safety pattern. | GitHub Pages serves one domain per repository, and this one already serves the café. Separating them keeps the café's live site safe. |
| P-03 | Phase 2 booking bar sends a ready-made WhatsApp or email request. Phase 3 adds real availability and checkout. | Ships something useful fast while payments are sorted out. |
| P-04 | Availability and bookings stored in a free-tier database; the café's existing Supabase project is an option. | Depends on the café's Supabase plan (café item E-10). |
| P-05 | Booking.com and Airbnb calendars synced by iCal, holding back one room as a buffer. | Free, but updates lag. A channel manager would be a subscription. |
| P-06 | Google free booking links through the Business Profile rate editor. | Free and needs no connectivity partner, if Google classes the property as a hotel. |
| P-07 | WhatsApp confirmations through Meta's Cloud API directly. | Billed per message, no monthly plan. |
| P-08 | Card payments through a Costa Rican gateway, plus SINPE Móvil as a guided transfer. | Which gateway depends on the owner's bank (BQ-09). |

---

## 6. Running costs

| Item | Recurring? | Notes |
|---|---|---|
| Domain basecampmonteverde.com | Yearly renewal | Unavoidable. |
| Hosting | No | GitHub Pages is free for public repositories. |
| Database | No, on a free tier | See P-04. |
| Card payments | Per transaction only | Gateway fees to confirm (BQ-09). |
| WhatsApp messages | Per message only | Service replies inside an open conversation window are free. |
| AI trip helper | Per use only | Optional. |
| Everything else | No | Open source or built in this project. |

---

## 7. Phases

| Phase | Delivers | Done when |
|---|---|---|
| **0 · Codex** (now) | This file, research, kickoff prompt, communication set up. | ChatGPT has read it and replied, and the owner has answered BQ-01, BQ-02 and BQ-06. |
| **1 · Plan sign-off** | Final page map, simple wireframes of every page, hero choice, brand colors and type. | Owner approves in writing. |
| **2 · Site preview** | Every page in EN and ES with real content and photos. Booking bar sends a WhatsApp or email request. | Owner and ChatGPT review a preview link on a phone. |
| **3 · Direct booking** | Availability, rates, checkout, confirmations, calendar sync. | A test booking runs end to end without real money. |
| **4 · Growth** | Google listing and free booking links, structured data, guest guide, conditions board, review flow. | Each item checked off by the owner. |
| **Launch** | The owner publishes and points the domain. | The owner does this, never an agent. |

---

## 8. Open questions for the owner

| ID | Question | Blocks |
|---|---|---|
| BQ-01 | Are Basecamp Monteverde and Orchid Lodge Monteverde the same building and rooms? If yes, does Orchid Lodge's site redirect to Basecamp after launch? | Phase 1 |
| BQ-02 | The exact room list: name of each room type, how many of each, beds, max guests, bathroom, size, amenities, photos, and prices by season. | Phase 1 |
| BQ-03 | Which page should the "Tours" link open? | Phase 2 |
| BQ-04 | Does Basecamp still offer private transport? If yes, is it a link like the tours, or part of the site? | Phase 1 |
| BQ-05 | Basecamp's logo, colors and fonts. If none exist, Claude proposes a brand kit for approval. | Phase 1 |
| BQ-06 | The original file of the current home page cloud photo, plus any other photos. Or allow `basecampmonteverde.com` in Claude's environment network settings so Claude can collect them. | Phase 1 |
| BQ-07 | Who hosts basecampmonteverde.com today, and who controls the domain and DNS? | Launch |
| BQ-08 | How bookings arrive today (WhatsApp, email, Booking.com, Airbnb, other) and which listings must stay in sync. | Phase 3 |
| BQ-09 | Which bank or payment gateway, the SINPE Móvil number to show, and the deposit rule. | Phase 3 |
| BQ-10 | OK to create a separate repository for the site (P-02)? Its name? | Phase 2 |
| BQ-11 | Is someone on site to receive guests, and at what hours? Do the doors have smart locks? | Phases 3 and 4 |
| BQ-12 | Who are the main guests today, and which languages beyond English and Spanish matter? | Phase 1 |
| BQ-13 | Does Basecamp have its own Google Business Profile? Who can log in to it? | Phase 4 |
| BQ-14 | Basecamp's own cancellation, check-in and check-out, children, pets and smoking rules. Orchid Lodge's are in the research file. | Phase 2 |

---

## 9. Decision log

Newest last. Each entry says what was decided, by whom and why.

**BD-001 · 2026-10-19 · Claude, owner may change · Coordination lives in `basecamp/` in this repository.**
ChatGPT, Codex and Claude can all read it here, and the café's rules stay separate. The site code itself may move to its own repository (P-02, BQ-10).

**BD-002 · 2026-10-19 · Owner · Layout follows the hotel-chain property-page pattern.**
The owner likes the JW Marriott Costa Elena page for its layout and easy navigation. We copy the structure only, with Basecamp's own brand, photos and words.

**BD-003 · 2026-10-18 · Owner · No memberships or subscriptions.**
Per-use fees are allowed and listed in section 6.

**BD-004 · 2026-10-19 · Owner · Do not build yet.**
Claude builds nothing until ChatGPT is connected and the owner writes GO.

**BD-005 · 2026-10-19 · Owner · Home page hero is a cloudy scene like the current Basecamp photo.**
Spec in section 4. Source pending BQ-06.

**BD-006 · 2026-10-19 · Owner · The website is about Basecamp only.**
The café and tours appear as links somewhere on the site. Every page focuses on the lodge.

**BD-007 · 2026-10-19 · Owner · Claude researches most of the content.**
Claude gathers facts from public sources and marks each with its source and confidence. The owner confirms anything marked "verify".

---

## 10. Status log

Newest first. Claude adds a line after every working session.

- **2026-10-19 · Claude.** Wrote this codex, `RESEARCH.md`, `CHATGPT-KICKOFF.md` and the root `AGENTS.md`. Opened the draft pull request and subscribed to it. Next: wait for ChatGPT's first review and the owner's answers to BQ-01, BQ-02 and BQ-06. Blocked: this session's network still denies `basecampmonteverde.com`, so the current site's photos and full text are not collected yet.
