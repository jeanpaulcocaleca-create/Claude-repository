-- Canopy OS · The Hanging Garden Café
-- POS layout 2.0: run ONCE in Supabase (SQL Editor -> New query -> paste -> Run). Safe to re-run.
-- Adds a color per category and per item (empty = automatic), a "Quick tab" setting per item
-- (auto / always / never), and a function the POS uses to find the best sellers of the last days.

alter table public.menu_categories add column if not exists color text;
alter table public.menu_items add column if not exists color text;
alter table public.menu_items add column if not exists quick text not null default 'auto';
alter table public.menu_items drop constraint if exists menu_items_quick_check;
alter table public.menu_items add constraint menu_items_quick_check check (quick in ('auto', 'always', 'never'));

drop policy if exists "categories color for signed-in" on public.menu_categories;
create policy "categories color for signed-in" on public.menu_categories
  for update to authenticated using (true) with check (true);
grant update (color) on public.menu_categories to authenticated;

-- Best sellers: item names with quantity sold in the last p_days days, paid orders only, voids excluded.
create or replace function public.quick_items(p_days int default 30, p_limit int default 12)
returns table (item_name text, qty bigint)
language sql security definer set search_path = public stable as $$
  select oi.item_name, sum(oi.qty)::bigint as qty
  from public.order_items oi
  join public.orders o on o.id = oi.order_id
  where o.created_at >= now() - make_interval(days => greatest(coalesce(p_days, 30), 1))
    and o.voided_at is null
    and coalesce(o.paid, true)
  group by oi.item_name
  order by qty desc, oi.item_name
  limit least(greatest(coalesce(p_limit, 12), 1), 30);
$$;
revoke all on function public.quick_items(int, int) from public, anon;
grant execute on function public.quick_items(int, int) to authenticated;

notify pgrst, 'reload schema';
