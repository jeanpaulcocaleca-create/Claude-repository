-- The Hanging Garden Café · temporary menu (from the owner's printed menu design)
-- Run ONCE in Supabase: SQL Editor -> New query -> paste -> Run.
-- Replaces the current menu entirely. Photos added later through the Menu Manager survive
-- only for items that keep the same row, so this wipe-and-reload is meant for the switchover.

delete from public.menu_items;
delete from public.menu_categories;

insert into public.menu_categories (id, name, sort) values
  ('a0000000-0000-4000-8000-000000000001', 'Coffee', 1),
  ('a0000000-0000-4000-8000-000000000002', 'Other Drinks', 2),
  ('a0000000-0000-4000-8000-000000000003', 'Smoothies', 3),
  ('a0000000-0000-4000-8000-000000000004', 'Sandwiches', 4),
  ('a0000000-0000-4000-8000-000000000005', 'Savory', 5),
  ('a0000000-0000-4000-8000-000000000006', 'Pastries & Cake', 6),
  ('a0000000-0000-4000-8000-000000000007', 'Costa Rican Favorites', 7),
  ('a0000000-0000-4000-8000-000000000008', 'Adventure Box', 8),
  ('a0000000-0000-4000-8000-000000000009', 'Extras & Combos', 9);

insert into public.menu_items (category_id, name, description, price_crc, sort) values
  -- Coffee
  ('a0000000-0000-4000-8000-000000000001', 'Espresso', null, 1300, 1),
  ('a0000000-0000-4000-8000-000000000001', 'Americano', null, 1500, 2),
  ('a0000000-0000-4000-8000-000000000001', 'Macchiato', null, 1800, 3),
  ('a0000000-0000-4000-8000-000000000001', 'Cappuccino', null, 2000, 4),
  ('a0000000-0000-4000-8000-000000000001', 'Latte', null, 2200, 5),
  ('a0000000-0000-4000-8000-000000000001', 'Flat White', null, 2200, 6),
  ('a0000000-0000-4000-8000-000000000001', 'Mocha', 'Costa Rican chocolate', 2400, 7),
  ('a0000000-0000-4000-8000-000000000001', 'Café con Leche', 'Traditional chorreado coffee + warm milk', 1700, 8),
  ('a0000000-0000-4000-8000-000000000001', 'Cloud Forest Latte', 'El Trapiche espresso · milk · Costa Rican honey · cinnamon · hot or iced', 2600, 9),
  ('a0000000-0000-4000-8000-000000000001', 'Iced Americano', null, 1500, 10),
  ('a0000000-0000-4000-8000-000000000001', 'Iced Latte', null, 2200, 11),
  ('a0000000-0000-4000-8000-000000000001', 'Iced Mocha', 'Costa Rican chocolate', 2400, 12),

  -- Other Drinks
  ('a0000000-0000-4000-8000-000000000002', 'Costa Rican Hot Chocolate', null, 1500, 1),
  ('a0000000-0000-4000-8000-000000000002', 'Tea', null, 1000, 2),
  ('a0000000-0000-4000-8000-000000000002', 'Sweet Cane Drink', null, 1500, 3),

  -- Smoothies
  ('a0000000-0000-4000-8000-000000000003', 'Golden Passion Bloom', 'Mango · pineapple · passion fruit (₡3 500 in milk)', 3200, 1),
  ('a0000000-0000-4000-8000-000000000003', 'Berry Violet Blossom', 'Strawberry · blackberry · ice cream (only in milk)', 3500, 2),
  ('a0000000-0000-4000-8000-000000000003', 'White Plumeria Cream', 'Pineapple · coconut cream · ice cream (only in milk)', 3500, 3),
  ('a0000000-0000-4000-8000-000000000003', 'Sunflower Citrus Bloom', 'Watermelon · pineapple · orange juice (only in water)', 2700, 4),
  ('a0000000-0000-4000-8000-000000000003', 'Green Jasmine Mint', 'Pineapple · lemon · spearmint (only in water)', 2700, 5),
  ('a0000000-0000-4000-8000-000000000003', 'Coral Rose Splash', 'Strawberry · watermelon · orange juice (only in water)', 2700, 6),
  ('a0000000-0000-4000-8000-000000000003', 'Pink Dahlia Delight', 'Strawberry · mango (₡2 800 in milk)', 2500, 7),
  ('a0000000-0000-4000-8000-000000000003', 'Emerald Orchid', 'Kiwi · strawberry (₡3 100 in milk)', 2700, 8),
  ('a0000000-0000-4000-8000-000000000003', 'Lemon Rose Blossom', 'Strawberry · lemon (only in water)', 2700, 9),
  ('a0000000-0000-4000-8000-000000000003', 'Fresh Water Lily', 'Melon · watermelon (₡2 500 in milk)', 2200, 10),
  ('a0000000-0000-4000-8000-000000000003', 'Golden Magnolia', 'Papaya · mango (₡2 800 in milk)', 2500, 11),

  -- Sandwiches
  ('a0000000-0000-4000-8000-000000000004', 'Ham & Cheese', 'Quality ham · local cheese · house sauce', 4000, 1),
  ('a0000000-0000-4000-8000-000000000004', 'Mano de Piedra', 'Traditional Costa Rican beef · frijoles molidos · local cheese · tomato · house sauce', 4500, 2),
  ('a0000000-0000-4000-8000-000000000004', 'Chicken Pesto', 'Chicken breast · pesto · local cheese · tomato', 4500, 3),
  ('a0000000-0000-4000-8000-000000000004', 'Monteverde', 'Frijoles molidos · local cheese · tomato · house sauce · vegetarian, add ham +₡500', 3750, 4),

  -- Savory
  ('a0000000-0000-4000-8000-000000000005', 'Chicken Empanada', null, 1800, 1),
  ('a0000000-0000-4000-8000-000000000005', 'Beef Empanada', null, 1800, 2),
  ('a0000000-0000-4000-8000-000000000005', 'Ham & Cheese Croissant', 'Warm it up? Absolutely.', 2500, 3),

  -- Pastries & Cake
  ('a0000000-0000-4000-8000-000000000006', 'Butter Croissant', null, 1500, 1),
  ('a0000000-0000-4000-8000-000000000006', 'Chocolate Croissant', null, 1800, 2),
  ('a0000000-0000-4000-8000-000000000006', 'Banana Bread', null, 1500, 3),
  ('a0000000-0000-4000-8000-000000000006', 'Carrot Cake', null, 2000, 4),

  -- Costa Rican Favorites
  ('a0000000-0000-4000-8000-000000000007', 'Tres Leches', 'Classic three-milk cake', 2500, 1),
  ('a0000000-0000-4000-8000-000000000007', 'Tamal Asado', 'Traditional Costa Rican baked corn cake', 1500, 2),

  -- Adventure Box (pre-order by 8 pm, early pickup from 6:30 am)
  ('a0000000-0000-4000-8000-000000000008', 'Adventure Box · Ham & Cheese or Monteverde', 'Sandwich + fresh fruit + sweet treat + bottled water + napkin. Pre-order by 8 pm, pickup from 6:30 am.', 6500, 1),
  ('a0000000-0000-4000-8000-000000000008', 'Adventure Box · Mano de Piedra or Chicken Pesto', 'Sandwich + fresh fruit + sweet treat + bottled water + napkin. Pre-order by 8 pm, pickup from 6:30 am.', 7000, 2),

  -- Extras & Combos (till helpers; hidden on the public website)
  ('a0000000-0000-4000-8000-000000000009', 'Flavor shot', 'Vanilla · caramel · hazelnut', 400, 1),
  ('a0000000-0000-4000-8000-000000000009', 'Add ham', null, 500, 2),
  ('a0000000-0000-4000-8000-000000000009', 'Smoothie milk upgrade', 'Most smoothies · Emerald Orchid uses the +₡400 line', 300, 3),
  ('a0000000-0000-4000-8000-000000000009', 'Smoothie milk upgrade · Emerald Orchid', null, 400, 4),
  ('a0000000-0000-4000-8000-000000000009', 'Combo discount · coffee + pastry', 'Also sandwich + coffee. Save ₡500.', -500, 5);
