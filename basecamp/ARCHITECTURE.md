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
| Two sign-in methods. **Access token:** no server at all, using a fine-grained token limited to the Basecamp repository; recommended in section 11. **GitHub button:** needs a small OAuth helper, `sveltia-cms-auth`, on Cloudflare's free Workers plan, and for a private repository it asks for the broad `repo` permission. | Doc: [GitHub backend](https://sveltiacms.app/en/docs/backends/github), [Open Authoring](https://sveltiacms.app/en/docs/workflows/open), [sveltia-cms-auth](https://github.com/sveltia/sveltia-cms-auth) |
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
| **Guides** (from the Muse plan, BQ-34) | Write and publish Knowledge Hub guides from templates in EN and ES: destination, seasons, getting here, packing, activities, niche guides, itineraries, local stories, FAQ. | Each guide has its FAQ block, links to room pages and its own WhatsApp message. |
| **Reviews** (from the Muse plan) | Add real guest quotes, each with its source link, and choose which ones appear beside Book buttons. | No star markup for our own reviews; `STRATEGY-REVIEW.md` section 5. |
| **Tracking** (BQ-36) | Analytics and pixel IDs, and the WhatsApp message for each page. | Public IDs only. Tags load only after visitor consent. |

### 2.3 Who can do what (proposal, BQ-29)

| Role | Who | Can |
|---|---|---|
| Owner | `jeanpaulcocaleca-create` | Edit and publish everything. Add and remove people. Approve agent work. |
| Editor | Staff the owner chooses, later | Prepare changes as drafts for the owner to publish. **Not enforceable on a free private repository**: anyone with write access can publish (section 11). Start with owner-only. |
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
| Domain | The main domain needs its nameservers moved to Cloudflare's free DNS ([Doc](https://developers.cloudflare.com/pages/configuration/custom-domains/)). Any email records must be copied across first. | A DNS record at the current registrar |

Either way the Basecamp site gets **its own repository**, separate from the café's, because one repository serves one domain (P-02).

### 6.2 What must stay online, and where things live

| Question | Answer |
|---|---|
| What must stay online for the site to work? | The static host and Hotel Link. The dashboard also needs GitHub. With access-token sign-in there is no sign-in helper to keep running. |
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
| Dashboard sign-in helper (Cloudflare Worker) | | | **$0** | Not needed with access-token sign-in. Only for the GitHub button: free plan, 100,000 requests a day ([Doc](https://developers.cloudflare.com/workers/platform/limits)). |
| Database | | | **$0** | None needed. |
| Photo and content storage | | | **$0** | In the repository, within free limits. |
| Builds and image optimization | | | **$0** | Included in the host's free builds. |
| Backups | Optional USB drive | | **$0** | Owner's own computer. |
| Hotel Link | | | Existing plan | Already paid; not additional. Amount Unknown (BQ-25). |
| Analytics, Search Console, Meta Pixel | | | **$0** | Free Google and Meta tools (BQ-36). |
| Conversions API helper (Cloudflare Worker) | | | **$0** | Postponed by BD-015 (D-05). Free plan if activated later. |
| Consent banner | | | **$0** | Open source. |
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
| Access control | The owner is the only person with write access at launch. Branch protection cannot be used: on GitHub Free it exists only for public repositories ([Doc](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches)). Agents act through the owner's GitHub identity, as the café's D-001 notes, so no repository setting can stop them. The control is the owner's choice of which repositories each agent session can reach, and whether read-only or with push. |
| Protected credentials | With access-token sign-in, the token lives only in the owner's browser, reaches only the Basecamp repository, and can be revoked on GitHub at any time. If the GitHub button is used instead, its secret lives in Cloudflare's secret store. No keys or passwords in the repository or the dashboard. Hotel Link logins are never stored anywhere in this project. |
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

---

## 11. Feasibility check (2026-10-20)

Requested by ChatGPT for the preferred candidate: **Cloudflare Pages, a private GitHub repository, Sveltia CMS, and Hotel Link as source of truth.** Desk research only. Nothing was installed, created or configured. Anything marked "test in Phase 2" can only be proven after the owner writes GO.

### 11.1 How the owner would use it

| Step | What the owner does | Evidence |
|---|---|---|
| Sign in | Opens `basecampmonteverde.com/admin` on phone or Mac. The first time on each device, pastes a personal access key from GitHub, limited to the Basecamp repository only. It stays signed in on that device after that. | Doc: [GitHub backend](https://sveltiacms.app/en/docs/backends/github) |
| Edit text | Opens, for example, Rooms, then Family room. English and Spanish fields sit side by side. | Doc: multilingual content ([sveltiacms.app](https://sveltiacms.app/en/)) |
| Change a photo | Taps the photo field, picks a picture from the phone. The dashboard shrinks it and converts it to WebP before uploading. The owner adds alt text in both languages. | Doc: [internal media and optimizer](https://sveltiacms.app/en/docs/media/internal) |
| Preview | Taps Save. The change goes to its own draft copy, never the live site. Cloudflare builds a preview of the whole site at a private address for that draft. | Doc: [Sveltia preview workflow](https://sveltiacms.app/en/docs/workflows/preview), [Cloudflare preview deployments](https://developers.cloudflare.com/pages/configuration/preview-deployments/). Whether the dashboard shows the preview link by itself: test in Phase 2 |
| Publish | Taps Publish. The draft merges into the live site, and Cloudflare rebuilds it, usually within minutes. | Doc: preview workflow |
| Undo | Opens the history and restores the earlier version (11.3). | Git history |

### 11.2 Sign-in: what is needed

| Option | Extra services | Permission reach | Recommendation |
|---|---|---|---|
| **Fine-grained access token** | None | Only the Basecamp repository; content and pull requests, read and write | **Recommended.** No helper to run. Renew it before it expires. |
| GitHub sign-in button | A free OAuth helper on Cloudflare Workers | For a private repository Sveltia asks for the `repo` permission, which reaches **every** repository on the owner's account, including the café system ([Doc](https://sveltiacms.app/en/docs/workflows/open)) | Not recommended for this account. |

GitHub added PKCE sign-in in July 2025, but a browser-only app still needs a server-held secret in practice ([GitHub changelog](https://github.blog/changelog/2025-07-14-pkce-support-for-oauth-and-github-app-authentication/), [discussion](https://github.com/orgs/community/discussions/15752)). So the button cannot work without the helper.

**Evidence for D-08, requested by the owner in BD-015.**
- GitHub's fine-grained tokens let the owner choose exactly which repositories the token can reach, with a permission level for each kind of access, including Contents and Pull requests ([GitHub Docs](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)).
- Expiry is configurable, from 1 to 366 days or none; the default is 30 days ([GitHub credential types](https://docs.github.com/en/organizations/managing-programmatic-access-to-your-organization/github-credential-types)).
- Sveltia's token sign-in needs only Contents read and write, plus Pull requests read and write for drafts ([Sveltia](https://sveltiacms.app/en/docs/backends/github)).
- No OAuth app and no helper are involved, so nothing can request broad permissions.
- **One honest caveat:** every fine-grained token also gets read-only access to all *public* repositories. The café's repository is public, so the token could read it. Its content is already public, and the token cannot write to it.

**Concrete solution, to be proven in the first step after GO**
1. The owner creates the token on GitHub: owner account; repository access "Only select repositories" with the Basecamp repository alone; Contents read and write; Pull requests read and write; expiry 366 days, with a reminder two weeks before.
2. The owner pastes it once into `/admin` on each device. It is stored only in that browser.
3. The `/admin` page carries no analytics or pixel, uses a strict Content-Security-Policy allowing only our own files and GitHub's API, and loads a pinned copy of Sveltia kept in the repository. No outside script can run there to read the token.
4. If a phone is lost, the owner revokes the token on GitHub in one click and creates a new one.
5. **Proof:** with the token, writing to any other repository must fail, and reading and writing the Basecamp repository must work. The results are recorded before final approval.
6. AI agents never receive this token.

**Free today is not free forever.** GitHub Free, Cloudflare Pages Free and Cloudflare Workers Free carry no promise of permanence. The design keeps an exit for each: the files move to GitHub Pages; the access token needs no Cloudflare at all.

### 11.3 Mac backup workflow (BQ-30)

| Piece | How | When the Mac is off or asleep |
|---|---|---|
| Automatic copy | A macOS background job like the café's installer, which runs at login with `RunAtLoad`. Unlike the café job, it uses an hourly calendar schedule rather than a fixed one-hour timer. It downloads every new change from the Basecamp repository into `Documents/Basecamp-Website`, using a read-only key kept in the macOS Keychain. | Asleep: an hourly calendar job runs on wake ([Apple](https://developer.apple.com/library/mac/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/ScheduledJobs.html)). Off: missed runs are skipped, and the job runs again at the next login. The website is never affected. |
| Offline copy | Time Machine, built into macOS, onto an external drive. A second drive is swapped in monthly and kept away from the lodge. | Runs whenever the drive is connected. |
| Full-size originals | Kept in a `Photos-Originals` folder on the Mac, which Time Machine also covers. | |
| Restore one change | Free GitHub Desktop app: History, choose the change, "Revert changes in commit", Push. The live site rebuilds. | |
| Restore everything | Upload the Mac copy to a new private repository and reconnect Cloudflare Pages. About an hour. Rehearsed in Phase 4. | |

### 11.4 Hotel Link widget

- The widget runs in every visitor's browser, so its embed code can only hold public identifiers. Hotel Link's guides copy it straight from the Booking Widget tab (Doc). Confirm by reading the actual code once the owner shares it; it is public, so it can be shared safely. No extranet login ever goes into the website.
- Prices and availability come live from Hotel Link's booking engine ([Doc](https://help.hotellinksolutions.com/how-to-embed-the-search-widget)). With no "from" prices on room cards (BQ-31), the website copies no prices at all.

### 11.5 Provider-switching screen (dashboard, Integrations)

```
INTEGRATIONS · BOOKING
Active booking system:   ( ) Hotel Link   ( ) Booking link only   ( ) Contact only

Hotel Link                 (shown when chosen)
  Property code            [            ]   copied from Hotel Link's widget code
  Open Hotel Link extranet (link)

Booking link only          (shown when chosen)
  Booking page address     [ https://   ]

Always shown
  Fallback WhatsApp        [ +506       ]
  Fallback phone           [            ]

NOTE: This only changes where Book buttons send guests. It does not move
reservations, rates, or Booking.com and Airbnb connections. Follow the
switching checklist (section 5.3) and check the preview before publishing.

[ Save draft ]   [ Open preview ]   [ Publish ]
```

Only the three listed choices exist. A new provider appears in the list only after its documentation has been checked and its adapter built and tested.

### 11.6 CONFIRMED, from documentation

1. Sveltia works with private GitHub repositories, by token or by OAuth with the `repo` permission.
2. Sveltia is a static page, so it runs on any static host, Cloudflare Pages included.
3. Each saved draft gets its own branch and draft pull request. Publishing merges it.
4. Cloudflare Pages builds previews for branches that are not the live branch, at their own address, without touching production.
5. The image optimizer converts uploads to WebP with size and quality limits. It works only with the built-in Git media library.
6. Storage limits are far above a 10-room lodge's needs. On GitHub, keep the repository under 1 GB, and well under 5 GB. Files over 100 MiB are blocked. On Cloudflare Pages, the limits are 25 MiB per file, 20,000 files and 500 builds a month.
7. Branch protection and rulesets are not available for private repositories on GitHub Free.
8. A main-domain address on Cloudflare Pages needs the domain's nameservers on Cloudflare.
9. Hotel Link's widget shows live rates and availability.

### 11.7 UNVERIFIED, test in Phase 2 or ask

1. Whether the dashboard shows Cloudflare's preview link by itself. One documented setup needed a small GitHub Actions step. Fallback: open the branch's preview address directly.
2. How mature Sveltia's draft and publish workflow is. It shipped in September 2026; one review still calls the product beta.
3. How easy Sveltia is to use on the owner's own phone.
4. Expiry options for fine-grained tokens, and a renewal reminder.
5. That Hotel Link's embed code holds only public identifiers. Read it when the owner shares it.
6. Generating responsive image sizes at build time within Cloudflare's 20-minute build limit. Expected to be easy at this scale.
7. Free notice to the owner when a Cloudflare build fails.
8. Hotel Link's Spanish and its link format, which are still open with Hotel Link support.

### 11.8 RISKS

| Risk | Likelihood | Effect | Mitigation |
|---|---|---|---|
| Broad GitHub permission reaches the café system | High if the GitHub button is used | A dashboard compromise could touch café code | Use the repository-limited token |
| No enforceable approvals on a free private repository | Certain | Anyone with write access can publish | Owner-only write at launch. Editors later only with trust, a public repository, or a paid plan (owner's choice) |
| Agents act as the owner on GitHub | Certain | An agent with push access could publish | Owner grants agent sessions read-only access to the Basecamp repository, or none |
| Free plan ends or changes | Low to medium over years | Hosting must move | Plain files; GitHub Pages as a same-day fallback |
| Account lockout on GitHub or Cloudflare | Low | No edits until recovered; site stays up | Printed recovery codes; a second trusted admin |
| Domain lapses | Low | Site and email go dark | Auto-renew, registrar lock, a calendar reminder (BQ-07) |
| Email breaks when nameservers move | Medium if rushed | Lost email | Copy every existing DNS record to Cloudflare before switching |
| Small open-source project with few maintainers | Medium over years | CMS updates stop | Pin the version and keep a copy in the repository. Config is Decap-compatible, so Decap is a fallback |
| A failed build | Low | Edits saved but not live | Build-failure notice, and the last good site stays online |
| Mac off for weeks | Medium | Local copy goes stale | No effect on the site. The copy catches up at login |
| Hotel Link changes its widget, as in 2025 | Low to medium | Booking buttons need an update | The adapter isolates the change to one place |

### 11.9 Dependencies that could stop the dashboard working

GitHub's service and API · a valid access token · the Sveltia file, pinned and kept in the repository rather than loaded from a CDN · Cloudflare Pages builds for publishing, though not for saving · a modern browser on the owner's phone. None of these needs a paid plan.

### 11.10 RECOMMENDATION

Keep the candidate, with three changes from the first draft:
1. **Sign in with a repository-limited access token**, not the GitHub button. That removes the sign-in helper and keeps the café system out of reach.
2. **Owner-only publishing at launch**, because a free private repository cannot enforce approvals.
3. **Mac backup**: the café-style automatic copy plus Time Machine on a rotating offline drive.

New recurring cost stays **$0**. The first job after GO is a short proof on a private preview with sample content. It confirms items 1 to 7 in 11.7 before any real content moves.

### 11.11 OWNER DECISIONS NEEDED

| ID | Decision | ChatGPT's recommendation, not an approval |
|---|---|---|
| BQ-28 | Option A, including a free Cloudflare account and moving the domain's nameservers to Cloudflare at launch | Option A, pending verification |
| BQ-29 | Owner-only publishing at launch | Yes; consider editors later |
| BQ-30 | Mac for backups, plus an offline drive | Yes |
| BQ-31 | No hand-typed "from" prices | Yes; live prices only |
| BQ-32 | Sign-in by repository-limited access token, or the GitHub button with a sign-in helper | Not yet reviewed |
| BQ-33 | Agent access to the future Basecamp repository: none, read-only, or push | Not yet reviewed |
| BQ-07 | Registrar, and whether the domain carries email, before any DNS move | Open |
