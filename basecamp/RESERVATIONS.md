# Reservation architecture · proposal for review

**Status: PROPOSAL.** Nothing here is approved. The owner approved the booking model only (BD-009): instant confirmed direct reservations. No provider, architecture, payment processor, purchase or development is approved. No additional subscription is approved. Build status stays ON HOLD.

Revised 2026-10-19 by Claude after the owner confirmed that Basecamp already uses Hotel Link.

Evidence labels used below:

| Label | Meaning |
|---|---|
| **Owner** | Confirmed by the owner. |
| **Vendor doc** | Hotel Link's help center describing how a feature works. |
| **Vendor claim** | Hotel Link marketing. Not independently checked. |
| **Inferred** | Claude's conclusion from the evidence. |
| **Unknown** | Not found. Ask the owner or Hotel Link (section 8). |

---

## 1. Requirements (BD-009)

Real-time availability · room and date selection · accurate prices, 13% VAT and totals · immediate confirmation · unique confirmation number · no two direct guests in the same room · automatic confirmation message · staff reservation management · cancellations and changes · clear handling of payment and sync failures · Booking.com and Airbnb stay in step.

Inventory (Owner): 10 rooms in 3 types. Seven sleep 3, two sleep 2, one sleeps 4.

## 2. Current setup

| Fact | Evidence |
|---|---|
| Basecamp Monteverde already uses Hotel Link for reservations. | Owner |
| Hotel Link is connected to Booking.com and Airbnb. | Owner |
| Which Hotel Link modules are active (booking engine, channel manager, Hotel Link Pay, Google Free Booking Links), the plan and its monthly price. | Unknown (BQ-25) |
| Whether the current website already uses the Hotel Link booking widget, and which version. | Unknown. The current site has "check availability" buttons per room (indexed); where they point is not visible from here. |

---

## 3. Hotel Link findings

| # | Question | Finding | Evidence |
|---|---|---|---|
| 1 | Booking engine and website integration | The Hotel Link Booking Engine plugs into any website through **Booking Widget** codes: an **embedded widget** that starts the booking on our own page and finishes checkout on Hotel Link's secure page; a **standalone code** for a "Book now" link that opens the booking page; and a **search widget** whose date fields can sit on any page and pass the dates to the booking widget through the web address. Widget code installed before 2025 must be replaced with the new version. | Vendor doc: [integration guide](https://help.hotellinksolutions.com/link-the-booking-engine-to-your-website), [search widget](https://help.hotellinksolutions.com/how-to-embed-the-search-widget), [2025 widget redesign](https://blog.hotellinksolutions.com/boost-your-hotel-revenue-with-the-redesigned-booking-widget) |
| 2 | Instant confirmed reservations | A confirmed booking on any channel, direct included, deducts inventory and updates every other channel. The help center has settings for booking conditions, deposits and balance due. Instant confirmation is the normal mode for this kind of engine, but no page says so in those words. | Vendor claim: [overbooking guide](https://blog.hotellinksolutions.com/what-is-overbooking-how-can-it-be-automatically-managed-with-a-channel-manager). Vendor doc: [booking conditions](https://help.hotellinksolutions.com/booking-conditions-payment-method-connection). Confirmation: Inferred, verify with a real confirmation email (section 8). |
| 3 | English and Spanish | Hotel Link says its products come in more than 10 languages. Each language is switched on under Booking Engine, then Set Up, then Languages, with its own content. A July 2026 update fixed a message that was stuck in English. **Spanish is not named in anything found.** Whether a link can open the engine directly in Spanish is not documented. | Vendor claim: [multi-property page](https://www.hotellinksolutions.com/multi-property-hotel-management-system/). Vendor doc: [language settings](https://help.hotellinksolutions.com/language-settings-in-the-booking-engine), [July 2026 release note](https://help.hotellinksolutions.com/02-july-2026-release-note-0). Spanish: Unknown. |
| 4 | Branding and embedding | Widget colors, shown rate plans, default dates and currency are set in Booking Widget Customization. Rooms or rate plans can be hidden. Checkout itself runs on Hotel Link's page. A booking page on our own web address was not found. | Vendor doc: [widget customization](https://help.hotellinksolutions.com/how-to-customize-your-booking-widgets-settings). Own address: Unknown. |
| 5 | Website bookings sync to Booking.com and Airbnb | Booking.com: Hotel Link states it has been a Premier Partner since 2020 and pushes availability, rates and restrictions 720 days ahead. Airbnb: connected by authorising Hotel Link inside Airbnb and mapping each listing to a rate plan, which points to a direct connection rather than calendar-link (iCal) sync. A direct booking deducts inventory everywhere. | Vendor doc: [Booking.com](https://help.hotellinksolutions.com/how-to-connect-to-booking.com), [Airbnb](https://help.hotellinksolutions.com/how-to-connect-with-airbnb). Airbnb connection type: Inferred. Both connected: Owner. |
| 6 | Payments for a Costa Rican hotel | Three routes. (a) A third-party gateway: Hotel Link lists Stripe, PayPal, Mollie, iPay88, Red-Pay and many regional providers; the hotel opens its own merchant account. (b) Hotel Link Pay, its own processor, which stores the card as a token; its pages list USD among supported currencies and say "globally", but they date from 2021 and 2022. (c) Capture card details and charge them manually at the lodge. Tilopay, a Costa Rican gateway, is not in the list found. Whether Stripe or Hotel Link Pay accept a Costa Rican business is unconfirmed. PayPal is available in Costa Rica. | Vendor doc: [payment methods](https://help.hotellinksolutions.com/payment-methods-in-hotel-link), [gateway list](https://www.hotellinksolutions.com/ota-pms-integrations), [Hotel Link Pay FAQ](https://www.hotellinksolutions.com/hotel-link-pay-faqs). Costa Rica eligibility: Unknown. |
| 7 | Extra fees | No commission on direct bookings, and free setup. Google Free Booking Links are free and need the booking engine and channel manager switched on. Since 2025, new hotels that need Hotel Link's team to install the widget may pay a service fee; we would install it ourselves. Gateway fees are separate. Third-party listings put Hotel Link around $45 to $50 per month for small hotels, which the owner already pays in some form. | Vendor claim: [booking engine](https://www.hotellinksolutions.com/hotel-marketing-solutions/booking-engine), [Google Free Booking Links](https://www.hotellinksolutions.com/premium-services/google-free-booking-links-for-hotels/). Vendor doc: widget fee in [2025 blog](https://blog.hotellinksolutions.com/boost-your-hotel-revenue-with-the-redesigned-booking-widget). Price: third-party ([Capterra](https://www.capterra.com/p/128749/Hotel-Link-Solutions/)). Owner's plan: Unknown. |
| 8 | Security, availability, double bookings | Hotel Link Pay tokenises cards and calls itself PCI DSS Level 1, but the page cites version 3.2.2, which has been replaced by version 4.0. How two guests booking the last room at the same moment is handled is not documented. "Eliminates overbooking" appears only in marketing. No public uptime commitment was found. Rooms can show "sold out" because of stop-sell, closed-to-arrival or departure, release period, channel override or automatic-close rules. | Vendor claim: [Hotel Link Pay](https://www.hotellinksolutions.com/hotel-link-pay/). Vendor doc: [sold-out cases](https://help.hotellinksolutions.com/sold-out-cases-on-booking-widget). Concurrency and uptime: Unknown. |

---

## 4. Recommendation: keep Hotel Link, wrap it in Basecamp's design

Hotel Link stays the single source of truth for rooms, rates, availability and every booking, direct or from Booking.com and Airbnb. The new website does the selling and hands guests to Hotel Link's booking widget for the final steps. **No new subscription and no new channel manager.**

```
basecamp-monteverde site (ours: design, photos, rooms, location, EN and ES)
   │
   │  our own date and guest form, in our design
   ▼
/book (EN) and /es/reservar (ES): Hotel Link embedded booking widget, colors matched
   │
   ▼
Hotel Link secure checkout ──► confirmation number and email to the guest
   │
Hotel Link extranet: one inventory for 10 rooms
   ├── Booking.com (Premier connection, per vendor)
   ├── Airbnb (direct connection, inferred)
   ├── Google Free Booking Links (if switched on)
   └── staff: bookings, changes, cancellations
```

### What stays ours, and what is Hotel Link's

| Ours, full control | Hotel Link's, limited to its settings |
|---|---|
| Every page, layout, photo and word. The tab bar, booking bar and date picker look. Room cards and comparison table. EN and ES pages. Speed and accessibility. | Room and rate selection inside the widget, the checkout page, payment form, confirmation email and confirmation number. Colors are adjustable; layout is not. |

The design break happens at checkout only, which is where guests expect a secure payment page.

### How each requirement is met

| Requirement | How | Evidence |
|---|---|---|
| Real-time availability, room and date choice | Hotel Link widget reads live inventory. | Vendor doc |
| Prices, VAT, totals | Set once in the Hotel Link extranet. | Inferred, check in screenshots |
| Immediate confirmation, confirmation number, email | Hotel Link issues them. | Inferred, check a real confirmation |
| Two direct guests, one room | Hotel Link deducts inventory on each confirmation. Simultaneous last-room bookings not documented. | Unknown, ask in writing |
| Direct guest versus OTA guest | Each confirmation updates every channel. A short window remains; Hotel Link can allocate rooms per channel if the owner wants the last room held back. | Vendor claim |
| Staff management, cancellations, changes | Hotel Link extranet. | Vendor doc |
| Payment failure | Per the booking conditions the owner sets: unconfirmed, or confirmed on a card guarantee or deposit. | Vendor doc, policy is the owner's |
| Sync failure | Hotel Link channel status, plus a written daily check of each OTA extranet against Hotel Link. | Procedure to write in Phase 1 |
| Hotel Link outage | Our site switches its Book button to WhatsApp and phone. | Ours |

### Open technical points for Phase 1

1. The exact web-address format that carries dates, guests and language from our form into the Hotel Link widget.
2. Whether a link can open the booking page on a specific room type, for the "Book this room" buttons.
3. Whether Spanish is live in Basecamp's account, and whether the widget follows the page language.
4. Whether the current website uses widget code from before 2025, which must be replaced.

---

## 5. Payments (P-08, BQ-09)

Instant confirmation does not require full payment at booking. Confirming on a card guarantee or a deposit is normal for hotels.

| Option inside Hotel Link | Fees | Status |
|---|---|---|
| Card details captured, charged at the lodge on the local terminal | Local terminal fees only | Vendor doc. Simplest. Staff handle cards, so the PCI rules for the lodge apply. |
| PayPal through Hotel Link | PayPal's rates | PayPal works in Costa Rica. Exact rates to confirm. |
| Stripe through Hotel Link | Stripe's rates | Whether a Costa Rican business can open a Stripe account is unconfirmed. |
| Hotel Link Pay | Hotel Link's rates | Costa Rica availability unconfirmed. Pages are dated. |
| Tilopay, Costa Rican gateway | 4.25% + $0.35, no monthly fee ([Tilopay](https://tilopay.com/en/tarifas)) | Not in Hotel Link's gateway list found. Ask Hotel Link. |

The Orchid Lodge site, now historical, asked a 50% deposit at booking with the balance at check-in. The owner decides Basecamp's rule (BQ-14).

---

## 6. Costs

| Item | Recurring? | Notes |
|---|---|---|
| Hotel Link | Existing plan, already paid | Modules and price to confirm (BQ-25). No new subscription proposed. |
| Direct-booking commission | None, per Hotel Link | Vendor claim. |
| Widget installation | None if we install it | Hotel Link's team may charge new hotels that need help. |
| Google Free Booking Links | None, per Hotel Link | Needs the booking engine and channel manager switched on. |
| Payment processing | Per transaction | Depends on the gateway chosen. |

---

## 7. Comparison only: other options

Kept for reference. **Not recommended while Hotel Link meets the requirements.** Revisit only if Hotel Link fails a must-have: Spanish, instant confirmation, embedding, or a workable Costa Rican payment route.

| Option | Monthly cost | Why not now |
|---|---|---|
| Beds24, low-cost channel manager | From €15.50 base plus €0.55 per room type per channel ([Beds24 pricing](https://www.beds24.com/pricing.html)) | Would add a second subscription and a migration away from a working setup. |
| Little Hotelier or Cloudbeds | Little Hotelier $29 to €119 plus a 1% fee on some plans; Cloudbeds quote-only, estimated $150 to $200 | Higher cost, same job. |
| Custom engine with Channex | $130 platform plus $7 per property, sold to software companies only ([Channex](https://channex.io/llms.txt)) | Wrong contract type, high build effort. |
| Fully custom engine with iCal | No subscription, but needs a paid database | iCal cannot prevent double bookings. Booking.com accepts no direct connections from individual properties ([Booking.com](https://connect.booking.com/)), and Airbnb's API is closed to new partners. |

---

## 8. What we need

### From the owner (BQ-25)

Screenshots from the Hotel Link extranet. Hide guest names, card numbers and passwords. Never send logins.

1. The list of active products or the current plan and its monthly price.
2. Booking Engine, Set Up, Languages: which languages are live.
3. Booking Widget Customization: colors, currency and the embed-code section.
4. Channel Manager: Booking.com and Airbnb shown as connected, with their room mapping.
5. Rates and Availability for one month: room type names and prices. This also answers BQ-02.
6. Booking conditions and payment methods: deposit, cancellation, which gateway is set up.
7. One recent direct-booking confirmation email, with guest details hidden.
8. The public booking-page link guests see today.

### Questions for Hotel Link support (BQ-24; the owner or ChatGPT sends them, Claude does not contact vendors)

1. Is Spanish available for the booking engine and widget, and can a link open it in Spanish?
2. What is the link format for passing dates, guests, language and a specific room type to the widget?
3. How does the engine handle two guests booking the last room at the same moment?
4. Which payment gateways can a business registered in Costa Rica use: Hotel Link Pay, Stripe, PayPal, Tilopay?
5. Can you share your current PCI DSS v4.0 attestation?
6. Does the current plan include the booking engine, the widget, the channel manager and Google Free Booking Links with no extra fees?
7. Is there an uptime commitment or a status page?
8. Can the booking page run on our own web address?
