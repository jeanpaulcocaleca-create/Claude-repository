-- The production follow-up (supabase/tools/production-followup.sql): its first statement makes the whole paste a
-- read-only transaction, and its "devices" section says which kind of device and browser each login's sessions are
-- on (Costa Rica time), never an IP, a full device string, a session id, a token key or an email in clear.
begin;
-- Supabase Auth's session table as current Supabase has it (supabase/auth migrations: 20220811173540,
-- 20221003041400, 20221114143122, 20231027141322, 20231114161723, 20250904133000, 20251007112900, 20251111201300)
do $$ begin
  if to_regtype('auth.aal_level') is null then create type auth.aal_level as enum ('aal1', 'aal2', 'aal3'); end if;
  if to_regclass('auth.sessions') is null then
    create table auth.sessions (
      id uuid primary key, user_id uuid not null references auth.users(id) on delete cascade,
      created_at timestamptz, updated_at timestamptz, factor_id uuid, aal auth.aal_level, not_after timestamptz,
      refreshed_at timestamp without time zone, user_agent text, ip inet, tag text, oauth_client_id uuid,
      refresh_token_hmac_key text, refresh_token_counter bigint, scopes text);
    alter table auth.sessions enable row level security;
  end if;
end $$;

-- Supabase's auth.users has last_sign_in_at (the test stub does not)
alter table auth.users add column if not exists last_sign_in_at timestamptz;

insert into auth.users (id, email, created_at, last_sign_in_at) values
  ('b2700000-0000-4000-8000-000000000001', 'Tablet.Cafe@Example.com', '2026-08-20 12:00+00', '2026-09-04 13:00+00'),   -- the café devices' login, owner kind today
  ('b2700000-0000-4000-8000-000000000002', 'dueno.personal@example.com', '2026-08-21 12:00+00', '2026-10-13 02:00+00'), -- the owner's own login, with a phone code
  ('b2700000-0000-4000-8000-000000000003', 'jh.nadie+cafe@example.com', '2026-09-16 13:00+00', null),                  -- never signed in; a +label stays visible
  ('b2700000-0000-4000-8000-000000000004', 'muchas@example.com', '2026-08-22 12:00+00', '2026-09-11 05:00+00'),        -- more sessions than the list shows
  -- like production: two logins whose masks are the same (je***@...), told apart only by their dates
  ('b2700000-0000-4000-8000-000000000005', 'je.uno@example.com', '2026-08-31 12:00+00', '2026-09-29 12:00+00'),        -- café devices: PINs, iPad, kitchen tablet
  ('b2700000-0000-4000-8000-000000000006', 'je.dos@example.com', '2026-09-16 12:00+00', '2026-10-12 12:00+00');        -- personal: a Mac and an iPhone
insert into public.app_accounts (user_id, kind, label) values
  ('b2700000-0000-4000-8000-000000000001', 'owner', 'tablet.cafe@example.com'),
  ('b2700000-0000-4000-8000-000000000002', 'owner', 'dueno.personal@example.com'),
  ('b2700000-0000-4000-8000-000000000003', 'owner', 'jh.nadie+cafe@example.com'),
  ('b2700000-0000-4000-8000-000000000005', 'owner', 'je.uno@example.com'),
  ('b2700000-0000-4000-8000-000000000006', 'owner', 'je.dos@example.com');
insert into auth.mfa_factors (user_id, status, factor_type) values ('b2700000-0000-4000-8000-000000000002', 'verified', 'totp');
-- PINs typed on the café devices' login (access_unlock, sales_unlock and inventory_unlock log target_id = the login)
insert into public.audit_log (at, action, manager_name, target_id) values
  ('2026-10-10 15:00+00', 'access_open', 'Ana', 'b2700000-0000-4000-8000-000000000001'),
  ('2026-10-11 16:00+00', 'access_open', 'Ana', 'b2700000-0000-4000-8000-000000000001'),
  ('2026-10-11 16:05+00', 'sales_view', 'Ana', 'b2700000-0000-4000-8000-000000000001'),
  ('2026-10-11 16:10+00', 'inventory_view', 'Luis', 'b2700000-0000-4000-8000-000000000001'),
  ('2026-10-05 16:00+00', 'access_open', 'Ana', 'b2700000-0000-4000-8000-000000000005'),
  ('2026-10-05 16:30+00', 'sales_view', 'Ana', 'b2700000-0000-4000-8000-000000000005');

-- refreshed_at is UTC without a time zone (auth models/sessions.go:170-175); Costa Rica is UTC-6
insert into auth.sessions (id, user_id, created_at, updated_at, refreshed_at, not_after, aal, user_agent, ip, tag, refresh_token_hmac_key) values
  -- the café's iPad: Safari asks for the desktop site by default, so it says Macintosh
  ('51270000-0000-4000-8000-000000000001', 'b2700000-0000-4000-8000-000000000001', '2026-09-01 14:00+00', '2026-09-01 14:00+00', '2026-10-12 03:30:00', null, 'aal1',
   'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15', '190.10.20.30', 'tag-270-a', 'hmac-secret-270-a'),
  -- the front register: Windows with Chrome; updated_at is later than refreshed_at
  ('51270000-0000-4000-8000-000000000002', 'b2700000-0000-4000-8000-000000000001', '2026-09-02 15:00+00', '2026-10-11 20:00+00', '2026-10-11 19:00:00', null, 'aal1',
   'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36', '201.200.1.2', null, 'hmac-secret-270-b'),
  -- the kitchen screen: a Fire TV with Silk (device-detector Tests/fixtures/tv-1.yml:5563)
  ('51270000-0000-4000-8000-000000000003', 'b2700000-0000-4000-8000-000000000001', '2026-09-03 12:00+00', '2026-09-03 12:00+00', '2026-10-11 18:10:00', null, null,
   'Mozilla/5.0 (Linux; Android 9; AFTKA) AppleWebKit/537.36 (KHTML, like Gecko) Silk/96.2.18 like Chrome/96.0.4664.175 Safari/537.36', '2803:9800:a00b::17', null, null),
  -- an Android tablet with Samsung Internet
  ('51270000-0000-4000-8000-000000000004', 'b2700000-0000-4000-8000-000000000001', '2026-09-04 13:00+00', '2026-09-04 13:00+00', '2026-10-10 16:00:00', null, 'aal1',
   'Mozilla/5.0 (Linux; Android 14; SM-X200) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/26.0 Chrome/122.0.0.0 Safari/537.36', '190.10.20.31', null, null),
  -- an expired session (a timeboxed one past its not_after): listed, not valid
  ('51270000-0000-4000-8000-000000000005', 'b2700000-0000-4000-8000-000000000001', '2026-08-31 16:00+00', '2026-08-31 16:00+00', '2026-09-01 16:00:00', now() - interval '1 day', 'aal1',
   'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36 Edg/129.0.2792.79', '10.0.0.7', null, null),
  -- the owner's iPhone: Safari earlier, then Chrome signed in with the phone code (aal2); signed in at 20:00 Costa Rica time
  ('51270000-0000-4000-8000-000000000006', 'b2700000-0000-4000-8000-000000000002', '2026-08-31 18:00+00', '2026-08-31 18:00+00', '2026-09-29 22:00:00', null, 'aal1',
   'Mozilla/5.0 (iPhone; CPU iPhone OS 17_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Mobile/15E148 Safari/604.1', '186.15.1.1', null, null),
  ('51270000-0000-4000-8000-000000000007', 'b2700000-0000-4000-8000-000000000002', '2026-10-13 02:00+00', '2026-10-13 02:30+00', null, now() + interval '30 days', 'aal2',
   'Mozilla/5.0 (iPhone; CPU iPhone OS 17_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/129.0.6668.69 Mobile/15E148 Safari/604.1', '186.15.1.2', null, null),
  -- the twins. Café: Chrome on an iPad asks for the desktop site and keeps CriOS (uap-core tests/test_ua.yaml:9294);
  -- a large Android tablet's Chrome asks for the desktop site and says X11; Linux (Chromium user_agent_utils.cc:287-292)
  ('51270000-0000-4000-8000-000000000008', 'b2700000-0000-4000-8000-000000000005', '2026-09-01 12:00+00', '2026-09-01 12:00+00', '2026-10-05 18:00:00', null, 'aal1',
   'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/129.0.6668.69 Version/17.6 Safari/605.1.15', '190.10.20.40', null, null),
  ('51270000-0000-4000-8000-000000000009', 'b2700000-0000-4000-8000-000000000005', '2026-09-01 12:30+00', '2026-09-01 12:30+00', '2026-10-05 17:00:00', null, 'aal1',
   'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36', '190.10.20.41', null, null),
  -- personal: Chrome on the owner's Mac (Blink: AppleWebKit/537.36, never an iPad) and Safari on an iPhone
  ('51270000-0000-4000-8000-000000000010', 'b2700000-0000-4000-8000-000000000006', '2026-09-16 12:00+00', '2026-09-16 12:00+00', '2026-10-12 20:00:00', null, 'aal1',
   'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36', '186.15.1.40', null, null),
  ('51270000-0000-4000-8000-000000000011', 'b2700000-0000-4000-8000-000000000006', '2026-10-12 12:00+00', '2026-10-12 12:00+00', '2026-10-12 15:00:00', null, 'aal1',
   'Mozilla/5.0 (iPhone; CPU iPhone OS 17_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Mobile/15E148 Safari/604.1', '186.15.1.41', null, null);
-- 17 sessions on one login: the list stops at 15 and says how many more; the other device and browser kinds
insert into auth.sessions (id, user_id, created_at, updated_at, refreshed_at, aal, user_agent, ip)
select ('52270000-0000-4000-8000-0000000000' || lpad(i::text, 2, '0'))::uuid, 'b2700000-0000-4000-8000-000000000004',
       timestamptz '2026-09-10 12:00+00' + i * interval '1 hour', timestamptz '2026-09-10 12:00+00' + i * interval '1 hour',
       timestamp '2026-09-20 12:00' + i * interval '1 hour', 'aal1',
       (array['Mozilla/5.0 (X11; Linux x86_64; rv:131.0) Gecko/20100101 Firefox/131.0',
              'Mozilla/5.0 (X11; CrOS x86_64 14541.0.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36',
              'Mozilla/5.0 (Linux; Android 13; SM-A536E Build/TP1A.220624.014; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/129.0.6668.81 Mobile Safari/537.36 [FB_IAB/FB4A;FBAV/484.0.0.53.105;]',
              'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/129.0.6668.69 Version/17.6 Safari/605.1.15',
              'Mozilla/5.0 (iPad; CPU OS 17_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Mobile/15E148 Safari/604.1',
              'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Mobile Safari/537.36',
              null,
              'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:131.0) Gecko/20100101 Firefox/131.0',
              'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36 Edg/129.0.2792.79',
              'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/26.0 Chrome/122.0.0.0 Safari/537.36'])[1 + i % 10],
       ('172.16.0.' || i)::inet
  from generate_series(1, 17) i;

-- 1) the file as shipped, in a savepoint, with a session time zone far from UTC
\set rc_file `mktemp`
\pset format unaligned
\pset tuples_only on
savepoint tool_run;
set local timezone = 'Asia/Tokyo';
\o :rc_file
\ir ../../supabase/tools/production-followup.sql
\o
-- still inside the tool's transaction: the database refuses any write
select current_setting('transaction_read_only') as read_only_after \gset
\set ON_ERROR_STOP 0
\set ON_ERROR_ROLLBACK on
insert into public.audit_log (action, summary) values ('t270_write', 'must be refused');
\set ON_ERROR_ROLLBACK off
\set ON_ERROR_STOP 1
rollback to savepoint tool_run;
\set rc `cat :'rc_file'`
select test.eq(:'read_only_after'::text, 'on', 'after the tool ran, the transaction is read only');
select test.ok(:'LAST_ERROR_SQLSTATE' = '25006' and :'LAST_ERROR_MESSAGE' ~ 'cannot execute INSERT in a read-only transaction',
               'after the tool ran, a write is refused by the database');
select test.eq((select count(*)::int from public.audit_log where action = 't270_write'), 0, 'nothing was written');
create temp table t270 as select :'rc'::jsonb as rc;

-- the logins, most recent activity first; masked; created, last sign-in, kind and phone code as in the logins section
select test.eq((select string_agg((d ->> 'login') || ' ' || (d ->> 'created'), ', ' order by o)
                  from t270, jsonb_array_elements(rc -> 'devices') with ordinality x(d, o) where o <= 6),
               'du***@example.com 2026-08-21, je***@example.com 2026-09-16, Ta***@Example.com 2026-08-20, je***@example.com 2026-08-31, mu***@example.com 2026-08-22, jh***+cafe@example.com 2026-09-16',
               'devices: logins masked like the logins section, most recent activity first');
select test.eq((select jsonb_agg(k order by k) from t270, jsonb_array_elements(rc -> 'devices') d, jsonb_object_keys(d) k where d ->> 'login' = 'Ta***@Example.com'),
               '["created", "kind", "last_sign_in", "login", "more_sessions", "phone_code_verified", "sessions", "valid_sessions"]'::jsonb, 'devices: the fields of a login');
select test.eq((select d - 'sessions' from t270, jsonb_array_elements(rc -> 'devices') d where d ->> 'login' = 'Ta***@Example.com'),
               '{"login": "Ta***@Example.com", "created": "2026-08-20", "last_sign_in": "2026-09-04", "kind": "owner", "phone_code_verified": false,
                 "valid_sessions": 4, "more_sessions": 0}'::jsonb,
               'devices: the café login has 4 valid sessions (the expired one does not count)');
select test.eq((select string_agg((s ->> 'device') || ' · ' || (s ->> 'browser') || case when (s ->> 'valid')::boolean then '' else ' (expired)' end, ', ' order by o)
                  from t270, jsonb_array_elements(rc -> 'devices') d, jsonb_array_elements(d -> 'sessions') with ordinality y(s, o)
                 where d ->> 'login' = 'Ta***@Example.com'),
               'iPad or Mac · Safari, Windows · Chrome, TV · Silk, Android tablet · Samsung Internet, Windows · Edge (expired)',
               'devices: the café devices, last used first (iPad in desktop mode, register, Fire TV, Android tablet)');
select test.eq((select d -> 'sessions' -> 0 from t270, jsonb_array_elements(rc -> 'devices') d where d ->> 'login' = 'Ta***@Example.com'),
               '{"device": "iPad or Mac", "browser": "Safari", "valid": true, "with_phone_code": false, "signed_in": "2026-09-01", "last_active": "2026-10-11 21h"}'::jsonb,
               'devices: one session in full; refreshed_at is read as UTC and shown in Costa Rica time');
select test.eq((select string_agg((s ->> 'signed_in') || ' → ' || (s ->> 'last_active'), ', ' order by o)
                  from t270, jsonb_array_elements(rc -> 'devices') d, jsonb_array_elements(d -> 'sessions') with ordinality y(s, o)
                 where d ->> 'login' = 'Ta***@Example.com'),
               '2026-09-01 → 2026-10-11 21h, 2026-09-02 → 2026-10-11 14h, 2026-09-03 → 2026-10-11 12h, 2026-09-04 → 2026-10-10 10h, 2026-08-31 → 2026-09-01 10h',
               'devices: last active is the later of refreshed_at and updated_at');
select test.eq((select d from t270, jsonb_array_elements(rc -> 'devices') d where d ->> 'login' = 'du***@example.com'),
               '{"login": "du***@example.com", "created": "2026-08-21", "last_sign_in": "2026-10-13", "kind": "owner", "phone_code_verified": true,
                 "valid_sessions": 2, "more_sessions": 0, "sessions": [
                  {"device": "iPhone", "browser": "Chrome", "valid": true, "with_phone_code": true, "signed_in": "2026-10-12", "last_active": "2026-10-12 20h"},
                  {"device": "iPhone", "browser": "Safari", "valid": true, "with_phone_code": false, "signed_in": "2026-08-31", "last_active": "2026-09-29 16h"}]}'::jsonb,
               'devices: a personal login on a phone only, one session with the phone code (aal2)');
select test.eq((select d -> 'sessions' from t270, jsonb_array_elements(rc -> 'devices') d where d ->> 'login' = 'jh***+cafe@example.com'), '[]'::jsonb,
               'devices: a login that never signed in has no sessions');
select test.eq((select jsonb_array_length(d -> 'sessions') || ' listed, ' || (d ->> 'more_sessions') || ' more, ' || (d ->> 'valid_sessions') || ' valid'
                  from t270, jsonb_array_elements(rc -> 'devices') d where d ->> 'login' = 'mu***@example.com'),
               '15 listed, 2 more, 17 valid', 'devices: at most 15 sessions per login, and how many more');
select test.eq((select string_agg(k, ', ' order by k collate "C") from (select distinct (s ->> 'device') || ' · ' || (s ->> 'browser') as k   -- byte order: CI sorts case-insensitively
                  from t270, jsonb_array_elements(rc -> 'devices') d, jsonb_array_elements(d -> 'sessions') s where d ->> 'login' = 'mu***@example.com') q),
               'Android phone · Chrome, Android phone · in-app/other, ChromeOS · Chrome, Linux or Android tablet · Firefox, Linux or Android tablet · Samsung Internet, '
               'Mac · Edge, Mac · Firefox, iPad · Chrome, iPad · Safari, other · in-app/other',
               'devices: the other device and browser kinds (Chrome of an iPad in desktop mode is an iPad, Firefox and Edge of a Mac are a Mac; '
               'an app''s own browser and a missing device text are in-app/other)');
-- two logins with the same mask (production has two je***@gmail.com): created tells them apart, and it is the same
-- date as in the logins section, so the one PINs were typed on is the one with the café's devices
select test.eq((select string_agg((d ->> 'created') || ' ' || (d ->> 'last_sign_in') || ': ' ||
                                  (select string_agg((s ->> 'device') || ' · ' || (s ->> 'browser'), ', ' order by o) from jsonb_array_elements(d -> 'sessions') with ordinality y(s, o)),
                                  '; ' order by d ->> 'created')
                  from t270, jsonb_array_elements(rc -> 'devices') d where d ->> 'login' = 'je***@example.com'),
               '2026-08-31 2026-09-29: iPad · Chrome, Linux or Android tablet · Chrome; 2026-09-16 2026-10-12: Mac · Chrome, iPhone · Safari',
               'devices: two logins with the same mask differ in created and last sign-in (café iPad and Android tablet; the owner''s Mac and iPhone)');
select test.eq((select string_agg(l ->> 'created' || ' → ' ||
                                  (select string_agg(s ->> 'device', ', ' order by o) from jsonb_array_elements(d -> 'sessions') with ordinality y(s, o)), '; ')
                  from t270, jsonb_array_elements(rc -> 'logins_that_typed_pins') l
                  join jsonb_array_elements(rc -> 'devices') d on d ->> 'login' = l ->> 'login' and d ->> 'created' = l ->> 'created'
                 where l ->> 'login' = 'je***@example.com' and l -> 'pins' <> '{}'),
               '2026-08-31 → iPad, Linux or Android tablet',
               'devices: matched by login and created, the je*** login PINs were typed on is the one on the café iPad and tablet');
select test.eq((select jsonb_agg(x order by x) from t270, jsonb_array_elements(rc -> 'devices') d, lateral (select d - 'sessions' - 'valid_sessions' - 'more_sessions' as x) y),
               (select jsonb_agg(x order by x) from t270, jsonb_array_elements(rc -> 'logins_that_typed_pins') l, lateral (select l - 'pins' as x) y
                 where l ->> 'login' <> '(deleted login)'),
               'devices: every entry has the login, created, last sign-in, kind and phone code of exactly one logins_that_typed_pins entry');
select test.ok((select bool_and(array(select jsonb_object_keys(s) order by 1) = array['browser', 'device', 'last_active', 'signed_in', 'valid', 'with_phone_code'])
                  from t270, jsonb_array_elements(rc -> 'devices') d, jsonb_array_elements(d -> 'sessions') s),
               'devices: every session shows only device, browser, valid, phone code and two dates');

-- nothing private leaves the database: no IP, device text, session id, token key or email in clear, anywhere in the cell
select test.eq((select count(*)::int from auth.sessions s, t270
                 where position(host(s.ip) in rc::text) > 0 or position(s.id::text in rc::text) > 0
                    or position(coalesce(s.user_agent, '-no-ua-') in rc::text) > 0
                    or position(coalesce(s.refresh_token_hmac_key, '-no-key-') in rc::text) > 0
                    or position(coalesce(s.tag, '-no-tag-') in rc::text) > 0), 0,
               'no IP, full device text, session id, token key or tag of any session appears');
select test.ok((select (rc -> 'devices')::text !~ '([0-9]{1,3}\.){3}[0-9]{1,3}|[0-9a-f]{1,4}::|Mozilla|AppleWebKit|KHTML|Gecko|AFTKA|SM-X200|15E148|[0-9a-f]{8}-[0-9a-f]{4}-' from t270),
               'the devices section has no IP-like text, device text fragments, model codes or ids');
select test.eq((select count(*)::int from auth.users u, t270 where position(lower(u.email) in lower(rc::text)) > 0), 0, 'no email appears in clear');
-- the logins section, unchanged, agrees: the café devices' login is the one PINs were typed on
select test.eq((select l -> 'pins' -> 'access_open' ->> 'n' || ' · ' || (l -> 'pins' -> 'inventory_view' ->> 'last')
                  from t270, jsonb_array_elements(rc -> 'logins_that_typed_pins') l where l ->> 'login' = 'Ta***@Example.com'),
               '2 · 2026-10-11', 'logins_that_typed_pins: the PINs typed on the café devices'' login');

-- 2) without the Auth session table (an older or non-Supabase database): devices is null, the rest still runs
alter table auth.sessions rename to sessions_270_away;
savepoint tool_run;
\o :rc_file
\ir ../../supabase/tools/production-followup.sql
\o
rollback to savepoint tool_run;
\set rc `cat :'rc_file'`
select test.ok(jsonb_typeof((:'rc'::jsonb) -> 'devices') = 'null' and (:'rc'::jsonb) ? 'logins_that_typed_pins',
               'without auth.sessions: devices is null and the other sections still answer');
alter table auth.sessions_270_away rename to sessions;

-- 3) an SQL Editor account that cannot read the session table: "not readable" instead of an error
select 't270_editor_' || current_database() as editor \gset
create role :"editor" nologin bypassrls;
grant usage on schema auth, storage, extensions to :"editor";
grant select on auth.users, auth.mfa_factors, public.audit_log, public.app_accounts, public.staff, public.orders to :"editor";
savepoint tool_run;
set local role :"editor";
\o :rc_file
\ir ../../supabase/tools/production-followup.sql
\o
rollback to savepoint tool_run;
\set rc `cat :'rc_file'`
select test.eq((:'rc'::jsonb) -> 'devices', '"not readable"'::jsonb, 'without the right to read auth.sessions: "not readable"');
-- and one subject to the table's row security (no BYPASSRLS): it would see no session, so it says so
alter role :"editor" nobypassrls;
grant select on auth.sessions to :"editor";
grant authenticated to :"editor";
savepoint tool_run;
set local role :"editor";
\o :rc_file
\ir ../../supabase/tools/production-followup.sql
\o
rollback to savepoint tool_run;
\set rc `cat :'rc_file'`
select test.eq((:'rc'::jsonb) -> 'devices', '"hidden by row security"'::jsonb, 'with row security in the way: "hidden by row security"');
\set rc_removed `rm -f :'rc_file'`
select test.done();
rollback;
