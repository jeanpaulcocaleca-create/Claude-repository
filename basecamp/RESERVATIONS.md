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
| Payment method: capture card details and process manually. Visa and Mastercard on. Hotel Link Pay not activated. Tilopay listed among integration options. | Owner screenshots, as reported by ChatGPT on 2026-10-20. Claude has not seen them. |
| **Booking conditions since 2026-10-22 (BD-024):** no advance deposit; the card is held as a guarantee and the guest pays on arrival. Free cancellation more than 1 day before arrival. Late cancellation or no-show: one night. 13% IVA shown separately and calculated correctly. Engine checked in Spanish. Where the 1-day cutoff falls relative to the 15:00 check-in is not verified. | Owner, in Claude's chat after reviewing with ChatGPT. Claude has not seen the extranet. |
| Earlier conditions, replaced: 50% deposit and a full-stay penalty within 22 days of arrival. Not to be implemented. | Owner screenshots, as reported by ChatGPT on 2026-10-20 |

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
| Card details captured, charged at the lodge on the local terminal | Local terminal fees only | **Enabled today** (owner screenshots). Vendor doc. Simplest. Staff handle cards, so the PCI rules for the lodge apply. |
| PayPal through Hotel Link | PayPal's rates | PayPal works in Costa Rica. Exact rates to confirm. |
| Stripe through Hotel Link | Stripe's rates | Whether a Costa Rican business can open a Stripe account is unconfirmed. |
| Hotel Link Pay | Hotel Link's rates | **Not activated** (owner screenshots). Costa Rica availability unconfirmed. Pages are dated. |
| Tilopay, Costa Rican gateway | 4.25% + $0.35, no monthly fee ([Tilopay](https://tilopay.com/en/tarifas)) | **Listed among Hotel Link's integration options** (owner screenshots). Integration cost and automatic charging to confirm with Hotel Link. |

Booking conditions are proposed in section 9.

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

A ready-to-send message in Spanish and English, with question 13 first, is in [`HOTEL-LINK-PREGUNTAS.md`](HOTEL-LINK-PREGUNTAS.md).

1. Is Spanish available for the booking engine and widget, and can a link open it in Spanish?
2. What is the link format for passing dates, guests, language and a specific room type to the widget?
3. How does the engine handle two guests booking the last room at the same moment?
4. Which payment gateways can a business registered in Costa Rica use: Hotel Link Pay, Stripe, PayPal, Tilopay?
5. Can you share your current PCI DSS v4.0 attestation?
6. Does the current plan include the booking engine, the widget, the channel manager and Google Free Booking Links with no extra fees?
7. Is there an uptime commitment or a status page?
8. Can the booking page run on our own web address?
9. Can a cancellation or no-show penalty be set as a number of nights, such as one night?
10. How is "1 day before arrival" counted: from midnight or from the check-in time, and in which time zone?
11. When is a stored security code deleted, what are the card viewing rules, and is card storage PCI DSS v4.0 compliant?
12. What does the Tilopay integration cost, and would it allow automatic deposit and penalty charges?
13. **PRIORITY, business-critical for any paid campaign** (`STRATEGY-REVIEW.md` section 11):
    a. Can the booking engine and checkout carry our Google Analytics 4 and Meta Pixel IDs, and report completed bookings as conversions, including the booking value?
    b. Does it support cross-domain tracking with our website?
    c. After a booking, can the guest be sent back to a thank-you page on our own website?
    d. Is the traffic source, such as UTM tags or a promo code, saved with each booking and shown in reports or exports?
    e. Can a live "from" price for a room be shown on our own page?

---

## 9. Booking conditions · proposal (BQ-14, BQ-09)

**Status: PROPOSAL.** The owner's preferences are recorded below. The configuration is Claude's proposal, building on ChatGPT's recommendation. Nothing is approved and no Hotel Link setting has been changed.

### 9.1 Owner preferences (2026-10-20, in ChatGPT's message pasted by the owner)

- Industry-standard hotel terms.
- Keep the ability to ask for a 50% deposit, without requiring it on every booking.
- A credit card is required as a guarantee.
- Free cancellation up to 24 hours before check-in.
- A fair penalty for late cancellation or no-show.

### 9.2 What Hotel Link supports

| # | Question | Finding | Evidence |
|---|---|---|---|
| 1 | Card guarantee with no deposit | Yes. Deposit type "No deposit" with the payment method "capture credit card details and process manually" lets the guest book without paying. The card is stored with the booking. | Vendor doc: [booking conditions](https://help.hotellinksolutions.com/booking-conditions-and-cancellation-rules), [payment method link](https://help.hotellinksolutions.com/booking-conditions-payment-method-connection) |
| 2 | 0% deposit | "No deposit" is one of five deposit types: no deposit, full amount, percentage, fixed amount, nights. | Vendor doc |
| 3 | First-night penalty | Deposits can be set in nights. Cancellation penalties use a separate rule, and the documented example uses percentages of the booking amount. A penalty of "1 night" is not documented. Fallback that works today: staff mark the booking "Cancelled With Penalty" and enter the first-night amount. | Vendor doc: [cancelling a booking](https://help.hotellinksolutions.com/how-to-cancel-a-booking). Nights penalty: Unknown |
| 4 | 24-hour deadline | Rules are set in days before arrival ("more than 1 day", "less than 1 day"). The exact cutoff hour, and whether it counts from midnight or from check-in time, is not documented. | Vendor doc. Cutoff hour: Unknown |
| 5 | Flexible and deposit rate plans side by side | Yes. General booking conditions cover all rate plans, and a rate plan set to "Custom" overrides them. | Vendor doc |
| 6 | Secure card handling | With manual capture, Hotel Link stores the cardholder name, number, security code and expiry. PCI DSS forbids keeping the security code after a payment is authorised. Card viewing rules exist but are not public. | Vendor doc: [payment methods](https://help.hotellinksolutions.com/payment-methods-in-hotel-link). [PCI SSC FAQ](https://blog.pcisecuritystandards.org/faq-can-cvc-be-stored-for-card-on-file-or-recurring-transactions). Retention: Unknown |
| 7 | Written confirmation of the conditions | The cancellation text the guest sees when booking is the same on the voucher and in the confirmation email. Confirmations include dates, items, policies and payment status. | Vendor doc: [confirmations](https://help.hotellinksolutions.com/sending-booking-confirmation-and-voucher-to-guests) |

### 9.3 Card-network rules

- Visa lets lodging merchants charge **one night** for a no-show on a guaranteed reservation, when the cancellation policy was disclosed at booking and restated in the confirmation. Merchants may set their own cancellation deadlines. ([Visa merchant guide](https://usa.visa.com/dam/VCOM/download/merchants/Guaranteed%20Reservations%20for%20Merchants%20VBS%2018.AUG.15.pdf), 2015)
- Mastercard cardholders can dispute a no-show charge when they cancelled in time, the fee was not disclosed, or it exceeds the quoted rate. ([third-party summary](https://chargebacks911.com/chargeback-reason-codes/mastercard/4853-no-show-hotel-charge/))
- **Consequence:** a first-night penalty matches the card rules. Charging the full stay to a card held only as a guarantee goes beyond the one-night no-show charge Visa describes, which raises chargeback risk. A larger penalty belongs on a rate where the guest pays a deposit up front.
- Charging a stored card later is a key-entered, card-not-present charge. The lodge's bank must allow this on its terminal (BQ-27).

### 9.4 Booking.com and Airbnb work differently

| Channel | Who sets the policy | Who charges the guest | Notes |
|---|---|---|---|
| Direct, Hotel Link | Hotel Link booking conditions | The lodge, on its terminal | The proposal below. |
| Booking.com | Booking.com's extranet: a policy attached to each rate plan, penalties in percent or nights ([Booking.com](https://partner.booking.com/en-us/help/policies-payments/policies/setting-cancellation-policies)) | The lodge or Booking.com, depending on the payment setup | Set separately from Hotel Link. Align it with the direct terms. |
| Airbnb | Airbnb's standard policies: Flexible, full refund to 24 h before check-in; Moderate, 5 days; Limited, 14 days; Firm, 30 days. A 24-hour grace period after booking cannot be turned off. ([third-party summary](https://www.hostfully.com/blog/airbnb-cancellation-policy/)) | Airbnb collects and pays the host | The lodge cannot charge Airbnb guests' cards. "Flexible" matches the direct 24-hour rule. |

### 9.5 Costa Rica requirements found (not legal advice, BQ-26)

- **Final prices.** Prices shown must be final, with all taxes included ([Ley 7472](https://www.asamblea.go.cr/sd/Documents/BIBLIOTECADIGITAL/DOCUMENTOS/LEYES/LEY%207472-PROMOCION%20DE%20LA%20COMPETENCIA%20Y%20DEFENSA%20EFECTIVA%20DEL%20CONSUMIDOR.pdf), [regulation](https://pgrweb.go.cr/scij/Busqueda/Normativa/Normas/nrm_texto_completo.aspx?nValor1=1&nValor2=75696)). The site and booking engine show totals with the 13% IVA included, not "plus tax".
- **IVA and invoices.** Lodging carries 13% IVA, and each stay needs an electronic invoice ([third-party](https://siemprealdia.co/costa-rica/impuestos/impuesto-sobre-el-valor-agregado-iva/), [third-party](https://taxlawyercr.com/airbnb-en-costa-rica-lo-que-todo-anfitrion-debe-saber-para-cumplir-con-la-ley/)). Whether a penalty or a kept deposit carries IVA and needs its own invoice was not found: a question for the accountant.
- **Right to withdraw.** Ley 7472 article 40 and the regulation's e-commerce chapter give an 8-day right to withdraw from distance sales. The exceptions found do not mention dated lodging ([analysis](https://www.lexology.com/library/detail.aspx?g=5af69811-8359-4b4c-a3f0-855cb54a219c)). Whether this limits a non-refundable deposit is a question for a lawyer.
- **Personal data.** Ley 8968 requires informed, express consent to process personal data ([third-party guide](https://www.recordinglaw.com/es/world-laws/world-data-privacy-laws/costa-rica-data-privacy-laws/)). The site and booking engine need a privacy notice.

### 9.6 Proposed configuration (not applied)

**General**
- Keep the payment method "capture credit card details and process manually", with Visa and Mastercard.
- Leave Hotel Link Pay and Tilopay off for now. Revisit if charging by hand becomes a burden (BQ-09).
- Replace the current 50% deposit on every booking and the full-stay penalty within 22 days.

**Rate plan A · Flexible** (default, listed first)

| Setting | Value |
|---|---|
| Deposit type | No deposit |
| Balance due | 0: paid at the property |
| Guarantee | Valid Visa or Mastercard, stored, not charged at booking |
| Free cancellation | Until the cutoff one day before arrival; hour to confirm |
| Late cancellation | First night: room rate plus 13% IVA |
| No-show | First night: room rate plus 13% IVA. The other nights are released. |
| Changes | Same deadline as cancellations |

**Rate plan B · Advance deposit** (optional)

| Setting | Value |
|---|---|
| Deposit type | Percentage: 50% |
| How it is charged | Staff charge it on the terminal right after booking. Automatic charging needs Hotel Link Pay or Tilopay. |
| Balance | At the property |
| Cancellation | Owner decides: deposit refundable until a set number of days before arrival, or non-refundable in exchange for a lower price |
| When it applies | Owner decides: peak dates, groups and whole-lodge bookings, or as a cheaper prepaid choice |

**Draft guest wording for rate plan A** (owner and a lawyer to approve)

> **EN:** Free cancellation until [time] Costa Rica time on the day before arrival. After that, or if you do not arrive, we charge the first night, with 13% VAT included, to the card you gave us. Nothing is charged when you book. The rest of your stay is paid at the lodge.
>
> **ES:** Cancelación gratuita hasta las [hora], hora de Costa Rica, del día anterior a su llegada. Después de esa hora, o si no se presenta, cobramos la primera noche, con el 13% de IVA incluido, a la tarjeta registrada. No cobramos nada al reservar. El resto de la estadía se paga en el hotel.

**Staff procedure** (written in Phase 1): who may view card details; penalties charged on the terminal only; card numbers never copied to paper, WhatsApp or email; every charge recorded on the booking; a receipt and electronic invoice sent to the guest; the booking record and confirmation email kept for disputes.

### 9.7 Needs the owner

1. Approve rate plan A as the default, and the removal of the current 50%-everywhere and 22-day full-stay terms.
2. Check-in and check-out times, and the exact cancellation cutoff hour.
3. Whether to offer rate plan B, its refund rule, any discount, and when it applies.
4. The rule for leaving early: charge the unused nights, one night, or nothing.
5. Align Booking.com's policy and choose Airbnb's "Flexible", or keep stricter terms on those channels.
6. Who on staff may view card details.
7. BQ-26: a Costa Rican lawyer and the accountant review the final terms.
8. BQ-27: ask the bank whether its terminal allows card-not-present charges for guarantees.
9. Send Hotel Link questions 9 to 12 in section 8 with the others (BQ-24).
