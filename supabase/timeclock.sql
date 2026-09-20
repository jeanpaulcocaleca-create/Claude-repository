-- Canopy OS · The Hanging Garden Café
-- Time clock schema: run ONCE in Supabase (SQL Editor -> New query -> paste -> Run).
-- Safe to re-run: everything is IF NOT EXISTS / drop-then-create for policies.

create table if not exists public.staff (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  pin text not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.time_entries (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references public.staff(id) on delete cascade,
  clock_in timestamptz not null default now(),
  clock_out timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists time_entries_staff_idx
  on public.time_entries (staff_id, clock_in desc);
create index if not exists time_entries_open_idx
  on public.time_entries (clock_out) where clock_out is null;

-- Row Level Security: signed-in café accounts only. The public (anon) key
-- embedded in the pages can NOT read or write any of this.
alter table public.staff enable row level security;
alter table public.time_entries enable row level security;

drop policy if exists "staff full access for signed-in" on public.staff;
create policy "staff full access for signed-in" on public.staff
  for all to authenticated using (true) with check (true);

drop policy if exists "time entries full access for signed-in" on public.time_entries;
create policy "time entries full access for signed-in" on public.time_entries
  for all to authenticated using (true) with check (true);
