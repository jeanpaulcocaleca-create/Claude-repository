# Asset manifest — The Hanging Garden website

Processed deploy assets (generated via Higgsfield, processed with ffmpeg per the scrub pipeline).
Permanent copies live in the owner's Higgsfield media library; for final deploy, download each
URL into `website/assets/` under the name in the left column.

| Deploy path | Source URL |
|---|---|
| assets/hero-scrub.mp4 (4.7 MB, 1920px, g=8) | https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/8c459e23-7d85-4b3d-a4ed-39939b00d720.mp4 |
| assets/hero-poster.jpg | https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/bd404324-1b90-48b8-84ee-8269cb1f21ed.jpg |
| assets/hero-ending.jpg | https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/754df0b9-0ebf-41fe-a832-86fae56f7024.jpg |
| assets/gal-1.jpg | https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/49b9d308-00fe-40ad-b29a-09809d8bcaae.jpg |
| assets/gal-2.jpg | https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/fcb7d720-2dbe-45f0-88e6-a641e8408aab.jpg |
| assets/gal-3.jpg | https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/f3bf5267-3592-44d3-9e8a-a491b69eff40.jpg |
| assets/gal-4.jpg | https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/ec6253b8-490a-4dab-9f41-46051d76e168.jpg |
| assets/logo.png (transparent, emblem only) | https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/f57bd646-807c-4a50-82af-e24392f87152.png |
| assets/quetzal.jpg (story section, soul_2 job 19052895) | https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/09b4a947-54f3-44ea-b6fe-cce8fbc9c427.jpg |
| assets/canopy.jpg (forest interlude, soul_2 job 73b333f8) | https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/cdf000bc-33ff-4d98-b457-c1726e4e4512.jpg |

Raw generations (hero film raw: Seedance 2.5 job 45c31024; 2K upscale job eec73cfb) remain in the
Higgsfield generation history and never ship.

Live preview (assets referenced by absolute URL, same origin):
https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/fe359cee-3c94-457d-8fb4-4a153a743a05.html

## Menu system pages (Supabase-backed, project nbvczarfweanoxvdqplk)

Current versions (v5 — forest/quetzal rebrand from the printed menu design; Playfair Display +
Dancing Script; full temporary menu; menu photos flow from the Menu Manager to website and TV):

- **Home (owner dashboard hub): https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/e05ea7ec-4823-4525-9da0-1ba7ddb8c41a.html**
- Website (cinematic, live menu): https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/a96264a1-da64-4c82-a903-5a3246ac575c.html
- Menu Manager: https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/718fac32-1172-464b-94ec-ec7cd54c65c3.html
- POS (record-only till + receipt printing): https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/cde84f85-bde9-4106-af9a-7cbdda64afcf.html
- Sales dashboard: https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/70aa55d9-3b24-43d8-8e20-c4375692a259.html
- Time clock (needs supabase/timeclock.sql run once): https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/323d7b1f-4cca-406c-8bc6-8df9b5ec7906.html
- TV menu board: https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/bf2bfa08-e7ce-40b0-b7aa-d20e25c8aaa7.html

The full temporary menu ships in supabase/menu-2026.sql (run once in the Supabase SQL Editor).
The website shows every category except Adventure Box (a designed card) and Extras & Combos
(till helpers); the TV board hides only Extras & Combos.

Superseded previews (CloudFront caches same-key re-uploads AND ignores query strings, so every
revision needs a fresh URL): 756a29eb/32ee9297/3769626f (v1), 5d922937/e907d1b9/e9976aac (v2),
0db18f7c/48814840/5b799ac5/69aece3e/27999e50 (v3 unannounced), e9fb8f71/9f36a846/0926d733/
582ea292/95e16564 (v3 announced), fe359cee/f96185d9 (site v1/v2), 965f0ba2 (TV v1),
73b7e5de/f3749faa/ecb46e99/14028c34/795bd8a7/fbc0633c (v4, superseded by the canopy legibility fix).
