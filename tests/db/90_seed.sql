-- Canopy OS test database · fake people and logins (test-only PINs; never used anywhere real).
--   Café tablet login  c0000000-0000-4000-8000-000000000001  cafe@test.local
--   Owner login        0e000000-0000-4000-8000-000000000002  owner@test.local
--   Accountant login   ac000000-0000-4000-8000-000000000003  contador@test.local (role added by migrations)
--   Staff PINs: Ana (manager) 4826 · Luis (staff) 5284 · Marta (staff) 6173 · Dueño (owner) 7391
insert into auth.users (id, email) values
  ('c0000000-0000-4000-8000-000000000001', 'cafe@test.local'),
  ('0e000000-0000-4000-8000-000000000002', 'owner@test.local'),
  ('ac000000-0000-4000-8000-000000000003', 'contador@test.local')
on conflict (id) do nothing;

insert into public.app_accounts (user_id, kind, label) values
  ('c0000000-0000-4000-8000-000000000001', 'cafe', 'cafe@test.local'),
  ('0e000000-0000-4000-8000-000000000002', 'owner', 'owner@test.local')
on conflict (user_id) do update set kind = excluded.kind;

insert into public.staff (id, name, role, active, pin_hash) values
  ('a1000000-0000-4000-8000-000000000001', 'Ana', 'manager', true, extensions.crypt('4826', extensions.gen_salt('bf'))),
  ('a1000000-0000-4000-8000-000000000002', 'Luis', 'staff', true, extensions.crypt('5284', extensions.gen_salt('bf'))),
  ('a1000000-0000-4000-8000-000000000003', 'Marta', 'staff', true, extensions.crypt('6173', extensions.gen_salt('bf'))),
  ('a1000000-0000-4000-8000-000000000004', 'Dueño', 'owner', true, extensions.crypt('7391', extensions.gen_salt('bf')))
on conflict (id) do nothing;
