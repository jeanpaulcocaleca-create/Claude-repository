-- Canopy OS · The Hanging Garden Café
-- TV Board 2.0: run ONCE in Supabase (SQL Editor -> New query -> paste -> Run).
-- Safe to re-run. Adds: board settings (mode, orientation, timing, tagline),
-- a "featured" star per menu item (shows it in the TV slideshow), and the
-- starter set of product photos generated for the advertising board.

-- 1) Featured star on menu items -------------------------------------------
alter table public.menu_items add column if not exists featured boolean not null default false;

-- 2) TV board settings (single row, id = 1) ---------------------------------
create table if not exists public.board_settings (
  id int primary key,
  mode text not null default 'cycle',          -- cycle | menu | promo
  rotation text not null default 'auto',       -- auto | landscape | portrait_left | portrait_right
  menu_seconds int not null default 25,
  slide_seconds int not null default 8,
  tagline text,
  updated_at timestamptz not null default now()
);

insert into public.board_settings (id, tagline)
  values (1, 'coffee + pastry save ₡500 · sandwich + coffee save ₡500')
  on conflict (id) do nothing;

alter table public.board_settings enable row level security;

-- The TV reads the settings with the public key; only signed-in accounts change them.
drop policy if exists "board settings public read" on public.board_settings;
create policy "board settings public read" on public.board_settings
  for select to anon, authenticated using (true);

drop policy if exists "board settings staff write" on public.board_settings;
create policy "board settings staff write" on public.board_settings
  for all to authenticated using (true) with check (true);

-- 3) Starter product photos + first slideshow line-up -----------------------
-- (replace any photo later from the Menu Manager; un-star with the ☆ TV button)
update public.menu_items set featured = true,
  photo_url = coalesce(photo_url, 'https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/e9863237-62a2-49a4-a63b-367c4a8f5efa.jpg')
  where name = 'Cloud Forest Latte';
update public.menu_items set featured = true,
  photo_url = coalesce(photo_url, 'https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/574b4dfb-ca7c-4fee-b069-ccce677c3d97.jpg')
  where name = 'Cappuccino';
update public.menu_items set featured = true,
  photo_url = coalesce(photo_url, 'https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/ae462fb2-15f7-4c39-9063-4c3fd2addd33.jpg')
  where name = 'Golden Passion Bloom';
update public.menu_items set featured = true,
  photo_url = coalesce(photo_url, 'https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/c7e68f2c-530a-4561-a094-4b7763ab3fa4.jpg')
  where name = 'Berry Violet Blossom';
update public.menu_items set featured = true,
  photo_url = coalesce(photo_url, 'https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/df5479cc-e700-4161-9895-dfa51d99cef1.jpg')
  where name = 'Chocolate Croissant';
update public.menu_items set featured = true,
  photo_url = coalesce(photo_url, 'https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/e1bda9ca-d285-4bbf-ad31-e82672a9e958.jpg')
  where name = 'Carrot Cake';
update public.menu_items set featured = true,
  photo_url = coalesce(photo_url, 'https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/4f9edb15-11a3-454f-9d86-c1fc0ed481a4.jpg')
  where name = 'Mano de Piedra';
update public.menu_items set featured = true,
  photo_url = coalesce(photo_url, 'https://d2ol7oe51mr4n9.cloudfront.net/user_3H6COw6NT5LgBi3taquUkfS2Dxz/e2cbc800-55bc-4466-800a-012db2290e14.jpg')
  where name = 'Tres Leches';
