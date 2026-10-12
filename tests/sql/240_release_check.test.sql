-- The release check (supabase/tools/release-check.sql) runs, and its security lines stay as expected.
begin;
-- run the real file (its output is not needed here)
\o /dev/null
\ir ../../supabase/tools/release-check.sql
\o
select test.ok(true, 'the release check runs');
-- the same checks, asserted
select test.eq((select coalesce(jsonb_agg(p.proname order by p.proname), '[]')
                  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'public' and p.prokind = 'f' and p.prorettype <> 'trigger'::regtype
                   and has_function_privilege('anon', p.oid, 'execute') and p.prosecdef),
               '["canopy_schema_version", "order_status", "place_room_order", "room_lookup"]'::jsonb,
               'without signing in, only the menu and room-order functions run with the owner''s rights');
select test.eq((select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
                 where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity), 0, 'every table has row security');
select test.eq((select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'public' and p.prosecdef and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')), 0,
               'every owner-rights function fixes its search path');
select test.done();
rollback;
