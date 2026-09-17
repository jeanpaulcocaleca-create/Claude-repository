-- Canopy OS · The Hanging Garden Café
-- Combined slides: run ONCE in Supabase (SQL Editor -> New query -> paste -> Run).
-- Safe to re-run. Lets the TV show several menu items together in one picture.
-- The pictures are built automatically from the item photos you already have,
-- so there is nothing to upload. Build the slides in the Menu Manager.

create table if not exists public.board_group_slides (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  kicker text,
  item_ids text[] not null default '{}',
  sort int not null default 1,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.board_group_slides enable row level security;

-- The TV reads the slides with the public key; only signed-in accounts change them.
drop policy if exists "group slides public read" on public.board_group_slides;
create policy "group slides public read" on public.board_group_slides
  for select to anon, authenticated using (true);

drop policy if exists "group slides staff write" on public.board_group_slides;
create policy "group slides staff write" on public.board_group_slides
  for all to authenticated using (true) with check (true);
