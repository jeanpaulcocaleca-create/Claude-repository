-- Hanging Garden Café · TV menu board: the "Look" setting (bright by day, dark at night)
-- Run ONCE in Supabase: SQL Editor -> New query -> paste -> Run. Safe to run again.
-- Run after supabase/tvboard.sql (already done on this project).
--   auto  = bright from 6:00 to 18:00, dark at night (default)
--   day   = always bright: easiest to read behind a window with reflections
--   night = always dark (the original look)
alter table public.board_settings add column if not exists theme text not null default 'auto';
alter table public.board_settings drop constraint if exists board_settings_theme_check;
alter table public.board_settings add constraint board_settings_theme_check check (theme in ('auto', 'day', 'night'));
notify pgrst, 'reload schema';
