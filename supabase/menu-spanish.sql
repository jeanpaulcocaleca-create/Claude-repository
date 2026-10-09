-- Hanging Garden Café · Spanish names and descriptions for menu items (optional)
-- Run ONCE in Supabase: SQL Editor -> New query -> paste -> Run. Safe to run again.
--
-- The Menu Manager then shows two more boxes when an item is edited: "Name in Spanish" and
-- "Description in Spanish". The menu at the tables (website/m.html, opened by the QR code) shows them when
-- a guest picks ES. When they are empty it uses the website's dictionary (website/lang.js), and otherwise the
-- English text. Anyone can read the menu, and only the owner areas can change it (the existing rules on
-- menu_items cover these columns too).

alter table public.menu_items add column if not exists name_es text;
alter table public.menu_items add column if not exists description_es text;

notify pgrst, 'reload schema';
