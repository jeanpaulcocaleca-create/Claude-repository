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

Raw generations (hero film raw: Seedance 2.5 job 45c31024; 2K upscale job eec73cfb) remain in the
Higgsfield generation history and never ship.

Live preview (assets referenced by absolute URL, same origin):
https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/fe359cee-3c94-457d-8fb4-4a153a743a05.html

## Menu system pages (Supabase-backed, project nbvczarfweanoxvdqplk)

Current versions (v3 — owner home, time clock, receipt printing, full cross-page link bar):

- **Home (owner dashboard hub): https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/e9fb8f71-0543-442f-a5d4-fbb8be7ef5b5.html**
- Menu Manager: https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/0926d733-d99c-4ab5-b9e9-b8342ca86ff7.html
- POS (record-only till + receipt printing): https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/582ea292-85cb-48de-91f0-d0dd094e867e.html
- Sales dashboard: https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/95e16564-e6bb-4240-9f18-f84cd74d7aba.html
- Time clock (needs supabase/timeclock.sql run once): https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/9f36a846-6b6a-4fe5-aa5c-08b7ed1359f5.html
- TV menu board: https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/965f0ba2-6869-475a-8251-f433db23fdec.html
- Site preview v2 (live menu): https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/f96185d9-bf92-4f6a-911e-5ae77ac38f5e.html

Superseded previews (CloudFront caches same-key re-uploads, so each revision gets a fresh URL):
756a29eb (dashboard v1), 32ee9297 (POS v1), 3769626f (sales v1), 5d922937/e907d1b9/e9976aac (v2),
0db18f7c/48814840/5b799ac5/69aece3e/27999e50 (v3 pre-receipt, never announced).
