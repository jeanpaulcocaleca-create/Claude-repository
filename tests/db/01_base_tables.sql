-- Canopy OS test database · the four base tables that were created in production before the
-- repository kept SQL scripts (orders, order_items, menu_categories, menu_items).
-- RECONSTRUCTED from how the code uses them; the real definitions come from the production schema
-- export (supabase/tools/catalog-export.sql). Replace this file with the exported definitions once
-- the owner has run that export (see docs/DEPENDENCIES.md).

create table if not exists public.menu_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  sort int not null default 0
);

create table if not exists public.menu_items (
  id uuid primary key default gen_random_uuid(),
  category_id uuid references public.menu_categories(id) on delete cascade,
  name text not null,
  description text,
  price_crc int not null default 0,
  photo_url text,
  available boolean not null default true,
  sort int not null default 0,
  updated_at timestamptz not null default now()   -- written by the Menu Manager (admin.html)
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  total_crc int not null default 0,
  payment_method text not null default 'cash_crc'
);

create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  item_name text not null,
  qty int not null default 1,
  price_crc int not null default 0
);
