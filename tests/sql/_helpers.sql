-- Canopy OS SQL tests · tiny assertion library (no extensions needed).
-- Each test file: begin; ... assertions ...; select test.done(); rollback;
-- Switch identity with:  select test.login('cafe'|'owner'|'accountant'|'anon'|uuid, aal, headers); set role authenticated;
-- and go back with:      reset role;
create schema if not exists test;
grant usage on schema test to public;

create table if not exists test.results (
  n serial primary key, ok boolean not null, label text not null, detail text
);
grant all on test.results to public;
grant usage on sequence test.results_n_seq to public;

create or replace function test.ok(cond boolean, label text, detail text default null)
returns boolean language plpgsql as $$
begin
  insert into test.results (ok, label, detail) values (coalesce(cond, false), label, case when coalesce(cond, false) then null else coalesce(detail, 'condition was ' || coalesce(cond::text, 'null')) end);
  return coalesce(cond, false);
end $$;

create or replace function test.eq(got anyelement, want anyelement, label text)
returns boolean language plpgsql as $$
begin
  return test.ok(got is not distinct from want, label, 'got ' || coalesce(got::text, 'null') || ', want ' || coalesce(want::text, 'null'));
end $$;

-- runs sql in a subtransaction; passes when it raises an error matching pattern (regex, case-insensitive)
create or replace function test.throws(sql text, pattern text, label text)
returns boolean language plpgsql as $$
begin
  begin
    execute sql;
  exception when others then
    return test.ok(sqlerrm ~* pattern, label, 'raised "' || sqlerrm || '" (wanted /' || pattern || '/)');
  end;
  return test.ok(false, label, 'no error raised (wanted /' || pattern || '/)');
end $$;

-- passes when sql runs without error
create or replace function test.lives(sql text, label text)
returns boolean language plpgsql as $$
begin
  begin
    execute sql;
  exception when others then
    return test.ok(false, label, 'raised "' || sqlerrm || '"');
  end;
  return test.ok(true, label);
end $$;

-- sets the JWT claims and request headers PostgREST would set for that login (session-wide)
create or replace function test.login(who text, aal text default 'aal1', headers jsonb default '{}'::jsonb)
returns uuid language plpgsql as $$
declare uid uuid;
begin
  uid := case who when 'cafe' then 'c0000000-0000-4000-8000-000000000001'::uuid
                  when 'owner' then '0e000000-0000-4000-8000-000000000002'::uuid
                  when 'accountant' then 'ac000000-0000-4000-8000-000000000003'::uuid
                  when 'anon' then null
                  else who::uuid end;
  if uid is null then
    perform set_config('request.jwt.claims', '{"role":"anon"}', false);
  else
    perform set_config('request.jwt.claims', jsonb_build_object('sub', uid, 'role', 'authenticated', 'aal', aal)::text, false);
  end if;
  perform set_config('request.jwt.claim.sub', coalesce(uid::text, ''), false);
  perform set_config('request.headers', headers::text, false);
  return uid;
end $$;

create or replace function test.done()
returns text language plpgsql as $$
declare r record; total int; bad int;
begin
  select count(*), count(*) filter (where not ok) into total, bad from test.results;
  for r in select * from test.results where not ok order by n loop
    raise warning 'FAIL #%: % — %', r.n, r.label, r.detail;
  end loop;
  if bad > 0 then raise exception '% of % assertions failed', bad, total; end if;
  if total = 0 then raise exception 'no assertions ran'; end if;
  return total || ' passed';
end $$;

-- staff ids used by the seed
create or replace function test.staff(name text) returns uuid language sql immutable as $$
  select case name when 'ana' then 'a1000000-0000-4000-8000-000000000001'::uuid
                   when 'luis' then 'a1000000-0000-4000-8000-000000000002'::uuid
                   when 'marta' then 'a1000000-0000-4000-8000-000000000003'::uuid
                   when 'dueno' then 'a1000000-0000-4000-8000-000000000004'::uuid end
$$;

-- opens the owner areas on this "device" with a manager/owner PIN, like access.js does; returns the headers
create or replace function test.unlock(staff uuid, pin text)
returns jsonb language plpgsql as $$
declare r jsonb; h jsonb;
begin
  r := public.access_unlock(staff, pin);
  if not coalesce((r->>'ok')::boolean, false) then raise exception 'unlock failed: %', r; end if;
  h := jsonb_build_object('x-hg-unlock', r->>'token');
  perform set_config('request.headers', h::text, false);
  return h;
end $$;

-- the sign-in this request comes from (the session_id claim every Supabase token carries; one per device sign-in).
-- test.login resets the claims, so call this after it.
create or replace function test.session(sid text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', (coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb
                                            || jsonb_build_object('session_id', sid))::text, false);
end $$;

-- 0038 (registered tills): time travel for the discount window. now() is fixed inside one transaction, so a test moves
-- the rows back instead: every discount% / pin_duplicate audit row and every discount_tills time (never deleting a
-- row; an approval's created_at is moved by the test itself where it matters). Call it as the test superuser (reset role first).
create or replace function test.back(d interval) returns void language plpgsql as $$
begin
  update public.audit_log set at = at - d where action like 'discount%' or action = 'pin_duplicate';
  if to_regclass('public.discount_tills') is not null then
    execute 'update public.discount_tills set enrolled_at = enrolled_at - $1, last_used_at = last_used_at - $1, ended_at = ended_at - $1' using d;
  end if;
end $$;

-- 0038: makes the sign-in set by test.login + test.session a registered till without going through the owner areas
-- (a fixture for the tests that only need a till; 485 registers through descuento_caja_registrar). Returns its place.
-- Call it as the test superuser (reset role first), after test.login and test.session; it reuses a live row of that
-- sign-in and refuses when the 3 places are taken.
create or replace function test.till(station text default 'Caja de prueba') returns int language plpgsql as $$
declare sid text := current_setting('request.jwt.claims', true)::jsonb ->> 'session_id';
        uid uuid := nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'sub', '')::uuid; n int;
begin
  if sid is null or uid is null then raise exception 'test.till: call test.login and test.session first'; end if;
  select slot into n from public.discount_tills where session_id = sid and ended_at is null;
  if n is not null then return n; end if;
  select g into n from generate_series(1, 3) g
   where not exists (select 1 from public.discount_tills t where t.slot = g and t.ended_at is null) order by g limit 1;
  if n is null then raise exception 'test.till: the 3 places are taken'; end if;
  insert into public.discount_tills (slot, session_id, login_id, station, enrolled_by_name)
    values (n, sid, uid, station, 'test fixture');
  return n;
end $$;

-- 0039 (Proveedores): «Recibe en este aparato» for that person on the sign-in set by test.login + test.session (clocking
-- them in when they are not on shift yet), as the page does with turno_aqui; returns the work-session token
create or replace function test.turno(staff uuid, pin text, station text default 'Recibo de prueba') returns text language plpgsql as $$
declare r jsonb;
begin
  r := public.turno_aqui(staff, pin, station, true);
  if not coalesce((r->>'ok')::boolean, false) then raise exception 'turno failed: %', r; end if;
  return r->>'token';
end $$;
