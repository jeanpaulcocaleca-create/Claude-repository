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

-- Storage lines, read from the file's own result cell (kept in a temporary file between runs)
\set rc_file `mktemp`
\pset format unaligned
\pset tuples_only on
\o :rc_file
\ir ../../supabase/tools/release-check.sql
\o
\set rc `cat :'rc_file'`
select test.eq((:'rc'::jsonb) -> 'migrations_missing', '[]'::jsonb, 'every migration of this version is applied (0000 to the last one)');
select test.eq((:'rc'::jsonb) -> 'functions_missing', '[]'::jsonb, 'every function the pages need is there');
select test.eq((:'rc'::jsonb) -> 'storage_buckets_missing', '[]'::jsonb, 'storage: the receipts bucket is there (0015)');
select test.eq((:'rc'::jsonb) -> 'storage_policies_missing', '[]'::jsonb, 'storage: the receipts rules and the menu photos rules are there');
select test.eq((:'rc'::jsonb) -> 'menu_photos_bucket', 'true'::jsonb, 'storage: the menu photos bucket is reported');
select test.eq((:'rc'::jsonb) -> 'receipt_upload_rule_current', 'true'::jsonb, 'storage: the upload rule is the one from 0025');
-- 0015's looser upload rule left in place
drop policy "expense receipts add" on storage.objects;
create policy "expense receipts add" on storage.objects for insert to authenticated
  with check (bucket_id = 'expense-receipts' and (select public._receipts_allowed()));
\o :rc_file
\ir ../../supabase/tools/release-check.sql
\o
\set rc `cat :'rc_file'`
select test.eq((:'rc'::jsonb) -> 'receipt_upload_rule_current', 'false'::jsonb, 'storage: 0015''s upload rule is not current');
-- rules and the receipts bucket gone
drop policy "expense receipts add" on storage.objects;
drop policy "menu photos read" on storage.objects;
delete from storage.buckets where id = 'expense-receipts';
\o :rc_file
\ir ../../supabase/tools/release-check.sql
\o
\set rc `cat :'rc_file'`
select test.eq((:'rc'::jsonb) -> 'storage_buckets_missing', '["expense-receipts"]'::jsonb, 'storage: a missing receipts bucket is listed');
select test.eq((:'rc'::jsonb) -> 'storage_policies_missing', '["expense receipts add", "menu photos read"]'::jsonb, 'storage: missing rules are listed');
select test.eq((:'rc'::jsonb) -> 'receipt_upload_rule_current', 'false'::jsonb, 'storage: without an upload rule it is not current');
-- a project without the menu photos bucket (staging): its rules are not asked for (both receipt rules gone now,
-- so the step before 0015 below proves neither is asked for there)
delete from storage.buckets where id = 'menu-photos';
drop policy "expense receipts read" on storage.objects;
\o :rc_file
\ir ../../supabase/tools/release-check.sql
\o
\set rc `cat :'rc_file'`
select test.eq((:'rc'::jsonb) -> 'menu_photos_bucket', 'false'::jsonb, 'storage: no menu photos bucket is reported');
select test.eq((:'rc'::jsonb) -> 'storage_policies_missing', '["expense receipts add", "expense receipts read"]'::jsonb, 'storage: without that bucket its rules are not asked for');
-- before 0015 and 0025 nothing of theirs is asked for
delete from canopy.migrations where version >= 15;
\o :rc_file
\ir ../../supabase/tools/release-check.sql
\o
\set rc `cat :'rc_file'`
select test.eq((:'rc'::jsonb) -> 'storage_buckets_missing', '[]'::jsonb, 'storage: before 0015 no receipts bucket is asked for');
select test.eq((:'rc'::jsonb) -> 'storage_policies_missing', '[]'::jsonb, 'storage: before 0015 no receipts rule is asked for');
select test.eq((:'rc'::jsonb) -> 'receipt_upload_rule_current', 'null'::jsonb, 'storage: before 0025 the upload rule is not judged');
\set rc `rm -f :'rc_file'`
\pset tuples_only off
\pset format aligned
select test.done();
rollback;
