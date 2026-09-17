# Asset manifest — The Hanging Garden website

Processed deploy assets (generated via Higgsfield, processed with ffmpeg per the scrub pipeline).
Permanent copies live in the owner's Higgsfield media library; for final deploy, download each
URL into `website/assets/` under the name in the left column.

| Deploy path | Source URL |
|---|---|
| assets/hero-scrub.mp4 (14.1 MB, 1920px, g=8, quetzal flight v5: shorter, opens over the harvest, ends landing on the real mural) | https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/c7242b7d-2378-4e77-98ea-751d9dacaa45.mp4 |
| assets/hero-poster.jpg | https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/5231ff45-7b82-4a33-a099-6c1d17a0754b.jpg |
| assets/hero-ending.jpg (the real building, mural completed, quetzal on the branch) | https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/b3174e2b-3bbe-4fc6-9807-038d2e5fbc2f.jpg |
| assets/hero-mobile.mp4 (960px, plays once on phones, v5) | https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/94681e79-ff9d-42c8-82b9-28eaa5d6fca9.mp4 |
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

Hero film v4 = v3 plus a 6 s leg (Wan 3.0, job dbc7c832) in which the quetzal leaves the café and lands on the painted branch of the real mural (building photo 9b05502a, mural completed by gpt_image_2_5 jobs d3794447 -> d5da9bdc -> a7af0e18, outpainted to 16:9 as ab53b4f5).

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

Until the domain is live, the same v15 pages are also on CloudFront (built with absolute links
between them; these are the links to use today). Once the domain is live, reprint the room QR
cards and repoint the TV from the Menu Manager.

- Home (v15): https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/1d54a49b-96c1-4e99-9bcd-077c4fd90c44.html
- Website (v17, shorter film, ending block in the corner): https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/0ac0fce2-0486-4750-916a-e19d46fb631c.html
- Menu Manager (v15): https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/2c0985b0-f155-466a-a1b0-e96104a4f2e7.html
- POS (v15): https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/221d75a3-249b-4741-90b2-b091705ecd6e.html
- Sales (v15): https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/92f2e118-06a6-4e88-93ca-c49927cfa765.html
- Time clock (v15): https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/dc603426-4bbf-44a4-ba66-599640bddd7b.html
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
8b354dca/6c24cdd2/a36d277a/c6a12384/c0d4cb1e (v13 pages), f0de2adb (POS layout mockup), 7dfb3b81/f4716fc7/25da86f5/69e27445 (v14 QA), d8012aa6/5c5c6197/b24e3583/dcfa70ad/fe546b23/f7f2c256 (v15 QA), 36c139af/396bd665/5b0e86c6/ea738b4e/d1b560d3 (v14 pages), 6ef92316 (site v10), 4ddb50c9/9fd0edc0/9220fe24 (film v3 assets), 417a39e3/0b3250a2 (film v4), f0fe9ae6 (site v16), 3c90a450 (v17 QA),
bc00deeb/edb9e04d/00b4983e/7a0e2b48/ca89d0ef/c7309f20 (v10 pages), 3d6d6aed/8d1d85da (v12 QA slots),
a4be43a7/e42b0085/4a220491/7c2da9c5/d7fa2327 (v11 pages superseded by v12; tv 432efc2c and site 6ef92316 unchanged).
