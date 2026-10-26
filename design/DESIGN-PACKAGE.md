# The Hanging Garden — Design Package (Tier 1, "La Gota")

## 1. Brand premise

One word: **la gota** — the drop. Monteverde coffee is slow coffee: cloud water gathered by the forest, one drop at a time, into one cup. The whole site performs this idea — the hero follows a single drop from the chorreador into the cup, and a thin coffee line (the drop's path) threads the entire page top to bottom, connecting every section until it ends in a small cup at the footer.

## 2. Palette (direction; exact tokens finalized from approved footage)

Sampled from the logo and the footage's world. This is deliberately the cafe's own material world — brown on cream is the brand's real ground (the logo is literally espresso brown on cream), earned by sampling from the brand's own assets, not a default reach.

```css
:root{
  --canvas:#F4EDE1;        /* warm cream, tinted toward the logo's paper ground */
  --panel:#FBF7EF;         /* raised cards */
  --ink:#3E2A1B;           /* deep espresso text */
  --accent:#6B4222;        /* logo brown: CTA, the drip thread */
  --accent-hover:#54331B;
  --accent-muted:#C9B39F;  /* whisper level: borders, particles */
  --mist:#9BA795;          /* cloud-forest green-grey, section tints */
  --gold:#C89B4B;          /* one golden highlight: focus states, rare emphasis */
  --text-secondary:#7A5844;
}
```

## 3. Type trio

- **Display:** Young Serif (400) — warm, chunky, botanical-vintage.
- **Body:** Figtree (400/600) — quiet, rounded like the logo's lettering.
- **Labels/mono:** Spline Sans Mono (400) — timetable, prices, small caps labels.

## 4. Band map (6s shot, ~400vh hero; ranges are starting points, flick-test validated later)

| Band | Range | Footage moment | Copy (verbatim) | Entrance |
|---|---|---|---|---|
| 1 | 0.00–0.16 | Chorreador close, drop forming on the cloth | "Born in the cloud forest." | blur-to-sharp (mist clearing) |
| 2 | 0.22–0.40 | The drop falls through mist | "One drop at a time." | drift-down (echoes the fall) |
| 3 | 0.46–0.64 | Falling past hanging plants, counter rising into view | "Monteverde in every cup." | approach-from-depth |
| 4 | 0.72–1.00 | The drop lands; cup settled, steam rising | "The Hanging Garden Café" / subline: "Coffee, garden, and cloud. Monteverde, Costa Rica." / CTA: "Plan your visit" | word-by-word rise, staged settle |

Captions flank the center action lane, alternating left and right. Per-band scrims per the legibility system.

## 5. Static-hero copy block (phones, reduced motion)

Composed over the ending frame (settled cup): headline "The Hanging Garden Café", subline "Coffee, garden, and cloud. Monteverde, Costa Rica.", CTA "Plan your visit".

## 6. Below-fold outline (one CTA: Plan your visit → #visit)

1. **The story** — Monteverde chapter with engraving-style ornaments: early farmers, 1948 (a nation chooses peace), 1951 Quakers name the green mountain, 1972 the cloud forest reserve, the golden toad. Values line: "Peace. Simplicity. Stewardship. Community."
2. **The menu** — categories with items and prices in mono; sourced from the menu manager later, hand-written for launch.
3. **La galería** — the gallery the owner asked for: realistic coffee and pastry imagery generated in the hero's world now, built to swap in real photos later (same slots, same sizes).
4. **The interactive moment** — press-and-hold the chorreador illustration to "brew": progress fills a cup while held, easing back if released; completing it lights the menu highlights in sequence. Reduced motion gets the finished state.
5. **Visit** (#visit) — hours, map embed, directions from Santa Elena, the one CTA target.
6. **Nora** — chat with Nora on the site + "chat on WhatsApp" button (integration per Canopy OS proposal).
7. **Footer** — logo, hours, the drip thread ends in a small cup. Imagery disclosure: photos are AI-generated placeholders until the cafe's own photos replace them.

No form and no payments: the site's conversion is a visit, a WhatsApp chat, or directions. (Payments are out of system scope by owner decision.)

## 7. Vector layer plan

- **The drip thread:** a 2px SVG path in --accent running from the hero's settle point through every section to the footer cup, drawing itself with scroll (stroke-dashoffset), delta-gated. THE signature element.
- Engraving-style leaf/bean corner ornaments (drawn SVG, whisper opacity) framing sections — the plants that left the logo live here.
- Whisper particles: slow-drifting mist dots at the story section, 60s+ cycle, paused off-screen.
- All honor reduced motion: final states, drives stopped.

## 8. Engineering list

Full standard per scrub-pipeline: Blob fetch with loading ring, dt-normalized lerp, gated seeks, delta-gated DOM writes, band pacing + flick test, four-layer legibility with worst-frame audit, five static-hero gates live in CSS and JS, complete-without-video, quality floor, whole-site-animated standard.

## 9. Copy gate

Every viewer-facing line above ships verbatim. The built page passes the grep gate (zero em dashes, zero stock words) and the AI-tell sweep before anyone sees it. "Peace. Simplicity. Stewardship. Community." is a designed device and stays.
