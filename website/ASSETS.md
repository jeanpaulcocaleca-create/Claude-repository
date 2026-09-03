# Asset manifest — The Hanging Garden website

Processed deploy assets (generated via Higgsfield, processed with ffmpeg per the scrub pipeline).
Permanent copies live in the owner's Higgsfield media library; for final deploy, download each
URL into `website/assets/` under the name in the left column.

| Deploy path | Source URL |
|---|---|
| assets/hero-scrub.mp4 (6.4 MB, 1920px, g=8, quetzal flight v3) | https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/4ddb50c9-7270-4a37-91f5-ffcd445e8ed5.mp4 |
| assets/hero-poster.jpg | https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/5231ff45-7b82-4a33-a099-6c1d17a0754b.jpg |
| assets/hero-ending.jpg | https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/9220fe24-1b88-491d-a4d7-1acc9a17e1bb.jpg |
| assets/hero-mobile.mp4 (960px, plays once on phones) | https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/9fd0edc0-6ebb-4d97-8f84-ecf072ef6483.mp4 |
| assets/gal-1.jpg | https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/49b9d308-00fe-40ad-b29a-09809d8bcaae.jpg |
| assets/gal-2.jpg | https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/fcb7d720-2dbe-45f0-88e6-a641e8408aab.jpg |
| assets/gal-3.jpg | https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/f3bf5267-3592-44d3-9e8a-a491b69eff40.jpg |
| assets/gal-4.jpg | https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/ec6253b8-490a-4dab-9f41-46051d76e168.jpg |
| assets/logo-badge.svg (round green badge, cup + steam, used site-wide) | https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/62fce9c4-ecce-4fff-a738-2844085bd420.svg |
| assets/deco-sprig.png (foliage page framing) | https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/a7a774e2-b2ff-49db-bb82-9621dba3a00c.png |
| assets/deco-quetzal.png (bird page framing + chat avatar) | https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/5f81fe73-ded5-4ef6-84ff-47c01b39abcd.png |
| assets/quetzal.jpg (story section, soul_2 job 19052895) | https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/09b4a947-54f3-44ea-b6fe-cce8fbc9c427.jpg |
| assets/canopy.jpg (forest interlude + TV board backdrop) | https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/cdf000bc-33ff-4d98-b457-c1726e4e4512.jpg |
| product photos (soul_2, 1200px, for the TV slideshow; attach via supabase/tvboard.sql or the Menu Manager) | Cloud Forest Latte e9863237 · Cappuccino 574b4dfb · Golden Passion ae462fb2 · Berry Violet c7e68f2c · Choc Croissant df5479cc · Carrot Cake e1bda9ca · Mano de Piedra 4f9edb15 · Tres Leches e2cbc800 (all .jpg on the same CDN base) |

Hero film v3 story: quetzal over the misty Monteverde canopy at dawn, dive through coffee
plants with red cherries, through an old-fashioned beneficio (beans pouring into burlap
sacks), then into the garden café where it lands beside the espresso machine and cup.
Raw generations (Seedance 2.5 job 05f0dba2 from realistic start frame 9c0ac672; 2K upscale
job aec12a92) remain in the Higgsfield generation history and never ship.

## Live pages (v10 — TV Board 2.0: Starbucks-style board + product slideshow, portrait/rotation modes, board settings and featured stars in the Menu Manager)

- **Home (owner dashboard hub): https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/00b4983e-71f2-40e2-919d-0f8be81b1e6f.html**
- Website (cinematic, live menu, chatbox): https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/6ef92316-c4ae-4815-8315-2b67f4ac4717.html
- Menu Manager: https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/edb9e04d-5d83-4aa4-ba1f-2eb40eac2084.html
- POS (record-only till + receipt printing): https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/ca89d0ef-b599-4a5a-9eed-7d90a57d3c17.html
- Sales dashboard: https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/c7309f20-e294-4fa8-86d4-0dfb8923b6d7.html
- Time clock (needs supabase/timeclock.sql run once): https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/7a0e2b48-a331-4ef1-8d16-766799de9cb3.html
- TV menu board 2.0 (needs supabase/tvboard.sql run once): https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/bc00deeb-a6eb-469a-b5fc-ef7a8689bafb.html

Supabase (project nbvczarfweanoxvdqplk) SQL to run once in the SQL Editor:
- supabase/menu-2026.sql — full temporary menu (until then pages show the old menu)
- supabase/chatbox.sql — chat_questions table (Garden Guide question logging)
- supabase/timeclock.sql — staff + time_entries (time clock)
- supabase/tvboard.sql — TV Board 2.0 (board settings, featured stars, starter product photos)

The website shows every category except Adventure Box (a designed card) and Extras & Combos
(till helpers); the TV board hides only Extras & Combos.

Superseded previews (CloudFront caches same-key re-uploads AND ignores query strings, so every
revision needs a fresh URL): 756a29eb/32ee9297/3769626f (v1), 5d922937/e907d1b9/e9976aac (v2),
0db18f7c/48814840/5b799ac5/69aece3e/27999e50 (v3 unannounced), e9fb8f71/9f36a846/0926d733/
582ea292/95e16564 (v3 announced), fe359cee/f96185d9 (site v1/v2), 965f0ba2 (TV v1),
73b7e5de/f3749faa/ecb46e99/14028c34/795bd8a7/fbc0633c (v4), a96264a1/e05ea7ec/323d7b1f/
718fac32/cde84f85/70aa55d9/bf2bfa08 (v5), 99b9d598/ea6e71bb/bd461b37/890421f9 (v6/v7 QA slots),
78e8bd19/20c14b46/52ed91bd/66ffec4e/976e9488/86dd6477 (v7 pages superseded by v8),
48045a64/3beadfaf/260e3ab9/2b01e1b2/08cbee36/82459b8d (v8), 7d24c6e8/bb79d408/5b1fa682/149efdb0/
5a312371/1115a36b (v9 unannounced), 328ef81a (TV scrim QA slot).
