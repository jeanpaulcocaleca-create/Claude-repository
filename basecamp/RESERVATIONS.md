# Reservation architecture · proposal for review

**Status: PROPOSAL.** Nothing here is approved. The owner approved the booking model only (BD-009), not a provider, architecture, payment processor or any development. Build status stays ON HOLD.

Written 2026-10-19 by Claude for ChatGPT's review and the owner's decision. Prices are from vendor pages or third-party reviews, marked as such, and need written quotes before anyone relies on them.

---

## 1. The requirements (BD-009)

Real-time availability · room and date selection · accurate prices, 13% VAT and totals · immediate confirmation · unique confirmation number · no two direct guests in the same room · automatic confirmation message · staff reservation management · cancellations and changes · clear handling of payment and sync failures · Airbnb and Booking.com stay in step.

Inventory to manage (owner-confirmed): 10 rooms in 3 types. Seven sleep 3, two sleep 2, one sleeps 4.

---

## 2. Facts that decide the architecture

| Fact | Source |
|---|---|
| Booking.com does not accept direct connections from individual properties. Properties connect through a certified channel manager. | [Booking.com Connectivity Portal](https://connect.booking.com/) (page may be dated) |
| Airbnb's API is not open to new partners; Airbnb invites partners. | Third-party guides, e.g. [Hospitable](https://hospitable.com/airbnb-partnerships) |
| iCal sync moves availability only, with delays reported from 30 minutes to 12 hours. It cannot prevent double bookings. | Vendor guides, e.g. [Rental Ninja](https://try.rental-ninja.com/how-to-sync-your-airbnb-and-booking-com-calendars-without-a-channel-manager-using-ical-avoiding-overbookings) |
| Supabase free projects pause after one week without activity, so the free tier cannot hold live bookings. | [Third-party 2026 guide](https://automationatlas.io/answers/supabase-free-tier-limits-2026/) |
| Channex, the main channel API for custom engines, sells only to software companies: $130 per month platform fee plus $7 per property. | [Channex llms.txt](https://channex.io/llms.txt) |

**Consequence:** live, reliable sync with Booking.com and Airbnb is only possible through a certified channel manager, and every certified channel manager found charges a monthly fee. Instant confirmed booking plus both platforms cannot be done reliably at zero monthly cost.

---

## 3. Options compared

| | A. All-in-one hotel software | B. Low-cost channel manager with booking engine | C. Custom engine plus Channex | D. Fully custom plus iCal | E. Open-source QloApps, self-hosted |
|---|---|---|---|---|---|
| Example | Little Hotelier, Cloudbeds | Beds24 | Our code plus Channex API | Our code and database | QloApps |
| Booking.com and Airbnb | Official API | Official API. Vendor states Booking.com Premier Connectivity Partner and Airbnb Preferred+ Software Partner. | Official API through Channex | iCal only, delayed | Paid add-on module |
| Direct double-booking protection | Vendor handles | Vendor handles (behaviour to confirm in writing) | We build it | We build it: database exclusion constraint per room and dates | Built in, behaviour to confirm |
| OTA double-booking risk | Low | Low | Low | **High** with 10 rooms on two platforms | Depends on add-on |
| Staff tools, emails, cancellations | Included | Included | We build | We build | Included |
| Google free booking links | Through vendor | Through vendor, only if its engine is the website's engine | Not available | Rate editor only, if eligible | Not available |
| Monthly cost | Little Hotelier $29 to €119 plus a 1% booking fee in some plans (sources conflict). Cloudbeds quote-only, estimated $150 to $200. | From €15.50 base plus €0.55 per room type per channel; no commission per vendor FAQ. Estimated low tens of euros. **Quote needed.** | $137 or more, B2B only | Paid database needed for reliability | Server, backups and add-on fees |
| Setup and upkeep | Low | Low to medium | High | High, and ongoing | High: updates and security fall on the owner |
| Fit for a 10-room lodge | Good, highest cost | **Best cost for full reliability** | Poor: priced for software companies | Poor: fails the reliability requirement | Poor: maintenance burden |

Pricing sources: [Beds24 pricing](https://www.beds24.com/pricing.html), [Beds24 FAQ](https://beds24.com/faq.html), [Little Hotelier vs Cloudbeds comparison](https://hoteltechreport.com/compare/cloudbeds-hms-vs-little-hotelier), [booking engine pricing guide](https://www.stayntouch.com/articles/hotel-booking-engine-pricing-2026), [QloApps overview](https://blog.brightcoding.dev/2026/10/06/qloappsqloapps-self-hosted-hotel-booking-platform-in-php).

---

## 4. Recommendation: "own the website, rent the inventory engine"

**Option B.** One low-cost certified channel manager, with Beds24 as the leading candidate, becomes the single source of truth for rooms, rates, availability and every booking. Our own fast, bilingual website does the selling. The checkout runs on the channel manager's booking engine, styled to match our site.

```
Guest on basecampmonteverde.com (our static site: rooms, photos, location)
        │  "Book" with dates and room
        ▼
Channel manager booking engine, styled to match ──► confirmation number, email to guest
        │
        ├── single inventory: 10 rooms, 3 types, rates, 13% VAT
        ├── pushes availability to Booking.com and Airbnb (official API)
        ├── sends prices to Google (free booking links, if eligible)
        └── staff calendar and app: check-ins, changes, cancellations
```

### How each requirement is met

| Requirement | How |
|---|---|
| Real-time availability, room and date choice | Booking engine reads live inventory. |
| Prices, VAT, totals | Configured once in the channel manager; tax rules set per rate. |
| Immediate confirmation and confirmation number | Booking engine issues both and emails the guest. |
| Two direct guests, one room | The engine commits one booking at a time. Get this in writing from the vendor (section 6). |
| Direct guest versus OTA guest | Each booking closes the dates on every channel through the API. A window of seconds to minutes remains, so the last room can be held back from the OTAs if the owner wants zero risk. |
| Staff management, cancellations, changes | Vendor calendar and mobile app. |
| Payment failure | Booking stays unconfirmed, or is confirmed on a card guarantee, depending on the policy the owner picks (section 5). |
| Sync failure | Vendor alerts. Staff compare the channel manager with each OTA extranet every morning, using a written procedure. |
| Vendor outage | The site switches its Book button to WhatsApp and phone until service returns. |

### Why not the others

- **D, fully custom with iCal**, meets every rule on cost but fails the reliability requirement. With 10 rooms on two platforms and hours of iCal delay, double bookings will happen.
- **C** is priced and contracted for software companies.
- **A** works but costs several times more for features a 10-room lodge does not need.
- **E** moves security updates and backups onto the owner.

### Possible later step, not proposed now

Beds24 has a documented API: live offers, booking creation that closes dates on all channels, and webhooks. A fully custom booking screen could sit on top of it later. Two catches: concurrency behaviour on the API must be verified first, and Beds24 says Google Hotel Ads through Beds24 require its own booking engine on the website. [API V2 docs](https://wiki.beds24.com/index.php/Category:API_V2), [Google via Beds24](https://wiki.beds24.com/index.php/Google_Hotel_Ads_&_Google_for_Vacation_Rentals).

---

## 5. Payments (P-08)

"Instant confirmed" does not require taking the full payment at booking. Hotels commonly confirm on a card guarantee or a deposit.

| Option | Fees | Notes |
|---|---|---|
| Card guarantee, pay at the lodge | Local card terminal fees | Simplest. No-show risk is managed by policy. |
| Deposit or prepayment through PayPal or Stripe inside the booking engine | About 2.9% + €0.30 (third-party figure) | Integrated with Beds24. Whether the owner's business can hold a Stripe account in Costa Rica is unconfirmed. |
| Tilopay | 4.25% + $0.35 per transaction, no monthly or yearly fee ([Tilopay pricing](https://tilopay.com/en/tarifas)) | Local cards and SINPE Móvil. Not a listed Beds24 gateway, so it would need custom glue later. |

---

## 6. To verify before any decision

1. A written Beds24 quote for 10 rooms, 3 room types, Booking.com and Airbnb, plus Google: base fee, link fees, and confirmation that no per-booking commission applies.
2. In writing: how the booking engine and API handle two guests trying to book the last room at the same moment.
3. Card storage and PCI responsibilities on the plan chosen.
4. Booking engine in Spanish and English, styling limits, and use on our own domain without the paid subdomain add-on.
5. Which payment gateways the owner's business can actually open in Costa Rica.
6. A comparable written quote from one alternative, such as Little Hotelier, so the choice is not single-sourced.

---

## 7. Owner decisions this needs

| ID | Decision |
|---|---|
| BQ-23 | Accept one exception to the no-subscription rule (BD-003) for the booking system, or keep the rule and accept option D's double-booking risk. |
| BQ-08, BQ-16 | Which platforms stay connected (Booking.com, Airbnb, others), and confirm the channel manager becomes the single calendar everyone uses. |
| BQ-09 | Payment model: card guarantee, deposit, or full prepayment, and which processor. |
| BQ-24 | Approve asking Beds24, and one alternative, for written quotes and answers to section 6. Claude does not contact vendors; the owner or ChatGPT can send the questions. |
