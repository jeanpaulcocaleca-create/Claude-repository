# Website architecture · proposal for review

**Status: PROPOSAL.** Nothing here is approved. Build status stays ON HOLD until the owner writes GO in Claude's chat. No accounts, repositories, services or subscriptions have been created. Hotel Link has not been touched.

Written 2026-10-20 by Claude, answering ChatGPT's requirements review of the same day. It covers the owner's four requirements, BD-010 to BD-013 in `CODEX.md`:
- an owner dashboard;
- Hotel Link as the only source of rates and bookings;
- freedom to change booking provider later;
- no additional monthly subscriptions.

Evidence labels: **Doc** (vendor or official documentation), **Claim** (vendor marketing), **Third-party**, **Inferred**, **Unknown**.

---

## 1. Recommended architecture in one picture

```
                OWNER (phone or computer)
                       │  signs in with GitHub (two-factor)
                       ▼
         Owner Dashboard  ·  /admin  ·  Sveltia CMS (free, open source)
                       │  every save = a dated, signed change ("commit")
                       ▼
   Basecamp content repository on GitHub  ◄──── automatic copy ───► owner's computer (backup)
   (text EN/ES, room details, photos, settings)
                       │  each change triggers a free build (images resized, pages generated)
                       ▼
   Static website on a free host  ·  basecampmonteverde.com
                       │  "Book" buttons go through the booking adapter
                       ▼
   Booking adapter  ──►  Hotel Link widget and secure checkout (today)
                    ──►  another provider later, by changing one setting
                    ──►  WhatsApp and phone fallback if the provider is down
```

**Why this shape**

| Goal | How the design meets it |
|---|---|
| No new subscriptions | Open-source dashboard, free static hosting, no database, photos stored with the content. |
| Easy for the owner | A form-based dashboard that works on a phone. No code, no Claude needed for routine changes. |
| Fast and reliable | Plain pages served from a global network. Nothing to crash at night. |
| Safe | No guest data and no card data on the website. Two-factor sign-in. Every change recorded and reversible. |
| Provider independence | Design and content never depend on Hotel Link. Only the adapter does. |

---

## 2. Owner Dashboard

### 2.1 Recommended tool: Sveltia CMS

| Fact | Evidence |
|---|---|
| Free and open source. It edits content files in a Git repository; there is no separate CMS database. | Doc: [sveltiacms.app](https://sveltiacms.app/en/) |
| Works with GitHub, GitLab, Gitea and Forgejo. Sign-in by GitHub OAuth or access token. | Doc: [npm readme](https://www.npmjs.com/package/@sveltia/cms?activeTab=readme) |
| Multilingual content, interface in 25+ languages, built-in image optimizer that converts uploads to WebP. | Doc and [maintainer post](https://github.com/sveltia/sveltia-cms/discussions/957) |
| Editorial workflow, meaning drafts, review and publish, shipped in September 2026. | Maintainer post. One review still calls it beta; **Unknown** whether 1.0 is final. |
| Friendlier GitHub sign-in uses a small free Cloudflare Worker (`sveltia-cms-auth`). Without it, sign-in uses an access token. | Doc: [sveltia-cms-auth](https://github.com/sveltia/sveltia-cms-auth) |
| Uses the same configuration format as Decap CMS, so we can switch tools without redoing content. | Maintainer post, Inferred |

**Alternatives considered**
- **Decap CMS**: mature, but GitHub sign-in needs a separate OAuth server or a hosted helper, and development has slowed ([Decap docs](https://decapcms.org/docs/github-backend/), [2026 review](https://www.luckymedia.dev/insights/decap-cms)).
- **Pages CMS**: free and MIT licensed, but self-hosting needs a PostgreSQL database and a GitHub App ([docs](https://pagescms.org/docs/)), which adds upkeep.

### 2.2 Dashboard sections

| Section | What the owner can do | Notes |
|---|---|---|
| **Home** | Change the hero photo and its focal point, headline, intro text and highlights, in EN and ES. | The cloudy hero spec from `CODEX.md` is the starting point. |
| **Rooms** | Edit room-type names, descriptions, beds, capacity, amenities, size and how many rooms of each type. Upload, replace, remove and reorder photos, with alt text in EN and ES. | **No prices here.** Prices come from Hotel Link (section 3). |
| **Gallery** | Albums such as rooms, building, views and town. Add, remove and reorder photos with captions. | |
| **Announcements and offers** | Site-wide banner with on and off switch, start and end dates, EN and ES text, and a link. Featured offer cards. | An offer's real price or discount must exist in Hotel Link. The card only advertises it. |
| **Pages** | Edit The Stay, Location, Groups, Contact, FAQ and the booking-terms page, in EN and ES. | Booking terms must match Hotel Link's conditions word for word (BD-009, Ley 7472). |
| **Hotel information** | Name, address, WhatsApp, phone, email, check-in and check-out times, map position, social links. | Used across every page and in structured data for Google. |
| **Integrations** | See and change the active booking provider and its public settings, such as property ID or booking link. Choose the fallback contact. Open Hotel Link's extranet. | Public identifiers only. No passwords or keys ever (section 7). |
| **Users and history** | Links to GitHub's settings page for people and permissions, and to the change history. | User management happens on GitHub, not inside the dashboard. Shown honestly as a link. |

### 2.3 Who can do what (proposal, BQ-29)

| Role | Who | Can |
|---|---|---|
| Owner | `jeanpaulcocaleca-create` | Edit and publish everything. Add and remove people. Approve agent work. |
| Editor | Staff the owner chooses | Prepare changes as drafts. The owner publishes them. |
| AI agents | Claude, Codex | Work on separate branches through pull requests. Never publish. Never get the dashboard login. |

---

## 3. Basecamp and Hotel Link: who owns what (BD-011)

| Owned by the website and dashboard | Owned by Hotel Link, the source of truth |
|---|---|
| Design, layout, photos, all text in EN and ES | Nightly rates and seasonal prices |
| Room-type descriptions, beds, capacity, amenities | Availability, closures and maintenance blocks |
| Announcements, offer cards, guides | Rate plans, discounts, promo codes |
| Hotel information, policies page text | Reservations, confirmations, changes, cancellations |
| Which booking provider is active | Booking conditions, deposits, card capture |
| | Booking.com and Airbnb sync, Google Free Booking Links |

**Prices on the website.** Live prices appear only inside Hotel Link's widget, which reads current rates and availability (Doc: [search widget](https://help.hotellinksolutions.com/how-to-embed-the-search-widget)). Room cards show "See prices and availability" rather than a fixed price, so a rate change in Hotel Link never leaves an out-of-date number on the site. A hand-typed "from" price is possible but discouraged (BQ-31).

**What the dashboard cannot do.** It cannot change rates, availability, reservations or booking conditions, and it does not show Hotel Link data. Hotel Link's API is meant for property-management systems and travel sites, to exchange availability and reservations, not for a website dashboard (Doc: [API scope](https://help.hotellinksolutions.com/process-connecting-with-hotel-link-via-api)). The dashboard links to the Hotel Link extranet for all of that.

**Check that Hotel Link changes reach the site** (Phase 3 acceptance test, no settings changed): pick three dates, compare the rate and availability in the extranet with what the website widget shows, in EN and ES.

---

## 4. Hotel Link capabilities: verified and unknown

Full detail and sources: `RESERVATIONS.md` sections 3 and 9.

| Verified in Hotel Link's own documentation | Still unknown, needs Hotel Link or the owner |
|---|---|
| Embedded widget, standalone link and search widget; old widget code must be replaced | Spanish in the booking engine and widget |
| Widget colors, rate-plan order, default dates and currency adjustable | Link format to pass dates, guests, language and room type |
| "No deposit" plus card capture; separate conditions per rate plan | Behaviour when two guests book the last room at the same moment |
| Policy text identical at booking, on the voucher and in the confirmation | Whether a penalty can be set as "1 night"; the exact cutoff hour |
| Booking.com and Airbnb connection steps | How long the security code is stored; PCI DSS v4.0 status |
| Inventory deducted on every channel per confirmation (Claim) | Uptime commitment; booking page on our own domain; Tilopay cost |

---

## 5. Changing booking provider later (BD-012)

### 5.1 The booking adapter

Every "Book" button and date form on the site calls one small piece of code, the adapter. The adapter reads the provider chosen in the dashboard's Integrations section. Nothing else in the site knows which provider is used.

| Adapter | What it does | Status |
|---|---|---|
| `hotel-link` | Embedded widget on `/book` and `/es/reservar`, plus our date form handing off to it | Primary. Link format to confirm. |
| `link-only` | Sends guests to any provider's public booking page, passing dates if that provider documents how | Works with most providers, with fewer features |
| `contact` | WhatsApp, phone and email, with a prefilled message | Always available; the automatic fallback during an outage |
| Others, such as Beds24 | Added only after that provider's documentation is verified | Candidates only. **No promise that any provider connects automatically.** |

### 5.2 API, iCal and credentials

- **API integrations** need a provider with a public booking API, for example Beds24's API V2 ([docs](https://wiki.beds24.com/index.php/Category:API_V2)). They also need a small server function and a secret key. Hotel Link's API is not of this kind (section 3).
- **iCal** moves availability only, with delays from 30 minutes to many hours. It never syncs prices and cannot prevent double bookings. Use it only as a temporary bridge, never as the main sync.
- **Credentials.** Widgets need only public IDs. Any API key goes in the hosting platform's secret store, never in the repository or the dashboard. Only the owner can see or rotate it.

### 5.3 Switching safely (owner authorization required at every step)

1. **Prepare in parallel.** Set up the new provider's rooms, rates and conditions while Hotel Link stays live.
2. **Preview.** Build a preview of the site using the new adapter, on a private address.
3. **Test.** Make test bookings in the new provider's test mode, in EN and ES, on a phone.
4. **Move future reservations.** Export them from Hotel Link and enter them in the new system, then check the count matches.
5. **Move the OTAs.** On Booking.com, change the connectivity provider in its extranet. On Airbnb, disconnect Hotel Link and authorise the new provider. Hotel Link warns that an Airbnb disconnection cannot be undone from Airbnb's side ([Doc](https://help.hotellinksolutions.com/how-to-connect-with-airbnb)).
6. **Short sales freeze.** For about an hour in low season, close sales in both systems so no booking lands in the wrong one.
7. **Flip.** Change the provider in the dashboard. That is one recorded change.
8. **Watch for 48 hours.** Compare bookings and availability in the new system against each OTA every day.
9. **Rollback.** Undo the dashboard change and reconnect the OTAs to Hotel Link. Keep the Hotel Link plan active until the new provider has run cleanly for an agreed period.

**Golden rule:** only one system may be connected to each OTA listing at any moment. Hotel Link's Airbnb guide requires removing any other channel manager first.

---

## 6. Hosting, content, database and backups (BD-013)

### 6.1 Two zero-cost hosting options (owner decision, BQ-28)

| | A. Cloudflare Pages with a private GitHub repository (recommended) | B. GitHub Pages with a public repository |
|---|---|---|
| Monthly cost | $0 | $0 |
| Drafts and unpublished content | Private | Visible to anyone who opens the repository |
| Security headers (CSP, HSTS) | Yes, through a `_headers` file ([Doc](https://developers.cloudflare.com/pages/configuration/headers/)) | No custom headers; page-level settings only |
| Limits | 500 builds a month, 20,000 files, 25 MiB per file, 100 custom domains ([Doc](https://developers.cloudflare.com/pages/platform/limits/)) | 1 GB site, 100 GB a month soft bandwidth limit ([Doc](https://docs.github.com/en/pages/getting-started-with-github-pages/github-pages-limits)) |
| Private repository possible for free | Yes ([Doc](https://developers.cloudflare.com/pages/get-started/git-integration/)) | No. Pages from a private repository needs a paid GitHub plan ([Doc](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages)) |
| New account needed | A free Cloudflare account | None |
| Domain | The main domain is most easily served if its DNS moves to Cloudflare's free DNS (Inferred, verify) | A DNS record at the current registrar |

Either way the Basecamp site gets **its own repository**, separate from the café's, because one repository serves one domain (P-02).

### 6.2 What must stay online, and where things live

| Question | Answer |
|---|---|
| What must stay online for the site to work? | The static host and Hotel Link. The sign-in helper is needed only to log in to the dashboard. |
| Where are edited text and photos stored? | In the Basecamp repository on GitHub, as files with full history, plus a copy on the owner's computer. |
| Where are full-size originals kept? | On the owner's computer. The repository keeps web-sized versions, about 2,000 px, so it stays small. |
| Is there a database? | No. The website keeps no guest data, no reservations and no card data. |
| What if the owner's computer is off? | Nothing changes for guests. The dashboard still works from a phone. The backup catches up when the computer is next on. |
| What if GitHub is unreachable? | The site keeps running from the host's last build. Only dashboard edits wait. |

### 6.3 Backups and restore

| Layer | How | Restore |
|---|---|---|
| Version history | Every dashboard save is a recorded version of every file | Undo any change from the history, in seconds |
| Owner's computer | An automatic copy of the repository, hourly and at login, reusing the café project's backup installer pattern for Mac and Windows | If GitHub were lost: upload the copy to a new repository and reconnect the host, in under an hour |
| Monthly USB copy | The owner copies the folder to a USB drive | Same as above |
| Hotel Link data | Reservations live in Hotel Link. Whether it offers an export for its own backup is **Unknown**; ask Hotel Link. | Hotel Link's responsibility |

A restore drill runs once before launch and then every six months.

### 6.4 Free-tier limits and risks

- **No service-level guarantee** on free plans. The site is static, so even a short outage at the host is rare and recovers by itself.
- **Terms can change.** If a free tier ends, the same files move to the other option in section 6.1 within a day.
- **Account lockout** is the biggest practical risk. Keep two-factor recovery codes printed and stored offline. Add a second owner-trusted admin.
- **Repository growth** from photos: the optimizer and the 2,000 px rule keep it far below limits. A ten-room lodge needs a few hundred photos at most.
- **Build cap** on option A: 500 builds a month. Each published dashboard change uses one, far below a lodge's needs.

---

## 7. Cost analysis

| Item | One-time | Yearly | Monthly | Notes |
|---|---|---|---|---|
| Domain basecampmonteverde.com | | Renewal, already paid today | | Unavoidable. |
| Hosting | | | **$0** | Free tier, option A or B. |
| Owner Dashboard (Sveltia CMS) | | | **$0** | Open source. |
| Dashboard sign-in helper (Cloudflare Worker) | | | **$0** | Free plan: 100,000 requests a day ([Doc](https://developers.cloudflare.com/workers/platform/limits)). |
| Database | | | **$0** | None needed. |
| Photo and content storage | | | **$0** | In the repository, within free limits. |
| Builds and image optimization | | | **$0** | Included in the host's free builds. |
| Backups | Optional USB drive | | **$0** | Owner's own computer. |
| Hotel Link | | | Existing plan | Already paid; not additional. Amount Unknown (BQ-25). |
| Card processing | | | Per transaction | Existing terminal fees. |
| Lawyer and accountant review | Owner's choice | | | BQ-26. |
| Professional photos | Optional | | | Owner's choice. |
| **New recurring cost** | | | **$0** | |

Nothing in this design requires buying storage or a subscription. If a future feature ever did, it would come to the owner first, with the reason it cannot be avoided.

---

## 8. Security and reliability

| Requirement | How |
|---|---|
| Secure sign-in | GitHub accounts with two-factor authentication or passkeys. No shared passwords. |
| Access control | Owner is admin. Editors draft, the owner publishes. Branch protection on the live branch. Agents never publish. The café's D-001 warning applies here too: an agent credential with admin rights can bypass in-repository gates, so the owner should limit agent access on the Basecamp repository. |
| Protected credentials | The sign-in helper's secret lives in Cloudflare's secret store. No keys or passwords in the repository or the dashboard. Hotel Link logins are never stored anywhere in this project. |
| Safe image uploads | JPEG, PNG and WebP only, no SVG; size cap; every image re-encoded at build time, which strips location data and hidden content; file names cleaned. |
| Audit history | Every change records who, what and when. Visible from the dashboard's history link, reversible at any time. |
| No card data | The website never sees card numbers. Checkout happens on Hotel Link's secure page. |
| Browser protections | Content-Security-Policy that allows only our own files and Hotel Link's widget, with HSTS and frame protections, on option A. |
| Outage fallback | If the booking page fails to load, the "Book" button switches to WhatsApp and phone. |
| Monitoring | A free scheduled check of the home page and booking page that emails the owner if either fails (Inferred, built on the host's free tooling). |

---

## 9. Reservation policy decisions still open

From `RESERVATIONS.md` section 9. The flexible model is the preferred direction, **not an approval**. The current 50% deposit and 22-day full-stay terms stay in place until the owner decides.

Verify first:
1. Hotel Link's exact cancellation cutoff (question 10).
2. Whether a first-night penalty can be automatic (question 9).
3. Security-code storage and PCI status (question 11).
4. The bank allows card-not-present charges (BQ-27).
5. Booking terms and confirmation emails exist in Spanish (question 1).
6. Professional review of tax, privacy and consumer rules (BQ-26).
7. The same terms appear on the site, in the widget, in the confirmation, on Booking.com and on Airbnb.

Owner decisions: the default rate plan; check-in, check-out and cutoff times; whether to offer the deposit plan and its refund rule; early departures; channel alignment; who may view card details.

---

## 10. Proposed phases (replaces `CODEX.md` section 7 once approved)

| Phase | Delivers | Done when |
|---|---|---|
| **1 · Plan review** (no code, now) | This plan reviewed; dashboard sketches; page map; hero and brand; hosting choice; Hotel Link's answers; policy decisions | Owner approves the plan and writes GO in Claude's chat |
| **2 · Foundations** | New Basecamp repository; EN and ES page templates; content model; dashboard; image pipeline; private preview address | Owner edits a room and a photo from a phone and sees it on the preview |
| **3 · Booking** | Hotel Link adapter on the preview; contact fallback; rate and availability check (section 3); booking terms matched | Owner approves the booking flow on a phone, in both languages |
| **4 · Hardening** | Security headers; backups to the owner's computer; restore drill; monitoring; staff guide in Spanish and English | Restore drill passes; owner signs off |
| **5 · Launch** | The owner points the domain; old WordPress addresses forward to the new pages; the old Orchid domain forwards (BQ-15) | The owner does this, never an agent |
| **6 · Growth** | Google Business Profile and Free Booking Links, structured data, guides, review flow | Each item checked off by the owner |
