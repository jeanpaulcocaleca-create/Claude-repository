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

## Live pages (v15 — owner and café logins, sales behind a PIN, published from the repo)

The website and every staff page now publish from this repository: the `Publish website`
workflow copies `website/` to the `gh-pages` branch on every push. GitHub Pages serves that
branch, first at https://jeanpaulcocaleca-create.github.io/Claude-repository/ and then at
https://hanginggardencafe.com once the domain points at GitHub (see the DNS notes in the
last report). Pages link each other by file name, so the same build works on both hosts:

- Home (owner dashboard): home.html
- Website: index.html (the root)
- Menu Manager: admin.html
- POS: pos.html
- Sales (manager PIN to open): sales.html
- Time clock: time.html
- Kitchen screen: kitchen.html
- Room ordering page: room.html?r=<room code>
- TV menu board: tv.html

The CloudFront copies below stay online but no longer receive updates. Once the domain is
live, reprint the room QR cards and repoint the TV from the Menu Manager.

- Home (v14): https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/36c139af-dfa0-4c37-b761-3c00b6700a07.html
- Website (v10): https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/6ef92316-c4ae-4815-8315-2b67f4ac4717.html
- Menu Manager (v14): https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/5b0e86c6-6fad-40a6-bd0b-660f00113a29.html
- POS (v14): https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/ea738b4e-a3e3-4192-943b-82b095f3f36e.html
- Sales (v14): https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/396bd665-30dd-47d0-a8da-838852a9f23e.html
- Time clock (v14): https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/d1b560d3-bc8e-4d2b-8da1-47329d437f1f.html
- Kitchen screen (v13): https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/6bb9c8f9-ebbd-4f20-917b-87b802cc47dd.html
- Room ordering page (v13): https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/b789e964-09c1-4c83-ad9d-db2fb9557f76.html
- TV menu board: https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/432efc2c-ae0d-4121-b1b7-a445dda3ba7b.html

Supabase (project nbvczarfweanoxvdqplk) SQL to run once in the SQL Editor:
- supabase/menu-2026.sql — full temporary menu (until then pages show the old menu)
- supabase/chatbox.sql — chat_questions table (Garden Guide question logging)
- supabase/timeclock.sql — staff + time_entries (time clock)
- supabase/tvboard.sql — TV Board 2.0 (board settings, featured stars, starter product photos)
- supabase/groupslides.sql — combined slides (several menu items shown together in one picture)
- supabase/authorization.sql — manager roles, hashed PINs, approval functions, audit log, order voids
- supabase/kitchen-rooms.sql — order status + pickup numbers, kitchen switches per category, settings, rooms with private codes, guest ordering functions
- supabase/pos-layout.sql — category and item colors, per-item Quick tab setting, quick_items best-seller function
- supabase/accounts.sql — owner vs café login, sales behind a manager PIN, hours by PIN, menu audit, owner-only writes; then `select public.make_owner('<owner email>');`
- supabase/authorization.sql — manager roles, hashed PINs, approval functions, audit log, table lockdown (run after timeclock.sql)

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
5a312371/1115a36b (v9 unannounced), 328ef81a (TV scrim QA slot),
06dd0092/4ebea556 (combined-slide previews), cca7165f/b3780112 (v11 QA slots), 3d6d6aed/8d1d85da (v12 QA),
acc489ae/492eb1b6/9bddf539/e85d9893/5bcd69c6 (v12 pages), 1134c843/097c9722/192daf95/34c1b399/8faa2c9c (v13 QA),
8b354dca/6c24cdd2/a36d277a/c6a12384/c0d4cb1e (v13 pages), f0de2adb (POS layout mockup), 7dfb3b81/f4716fc7/25da86f5/69e27445 (v14 QA), d8012aa6/5c5c6197/b24e3583/dcfa70ad/fe546b23/f7f2c256 (v15 QA),
bc00deeb/edb9e04d/00b4983e/7a0e2b48/ca89d0ef/c7309f20 (v10 pages), 3d6d6aed/8d1d85da (v12 QA slots),
a4be43a7/e42b0085/4a220491/7c2da9c5/d7fa2327 (v11 pages superseded by v12; tv 432efc2c and site 6ef92316 unchanged).
