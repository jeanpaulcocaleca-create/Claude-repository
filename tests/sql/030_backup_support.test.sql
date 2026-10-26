-- Migration 0002: backup account, backup log and the owner's backup tile.
begin;

select test.ok((select rolbypassrls from pg_roles where rolname = 'canopy_backup'), 'the backup account reads past row rules (complete dumps)');
select test.ok(not pg_has_role('canopy_backup', 'pg_read_all_data', 'member'), 'the backup account is not given pg_read_all_data (it would read the logins)');
select test.eq((select count(*)::int from pg_auth_members where member = 'canopy_backup'::regrole), 0, 'the backup account belongs to no role');
select test.eq((select count(*)::int from pg_class c
                 where c.relnamespace in (select oid from pg_namespace where nspname in ('public', 'canopy', 'acct'))
                   and c.relkind in ('r', 'p', 'S') and not has_table_privilege('canopy_backup', c.oid, 'select')), 0,
               'the backup account can read every table and sequence of the café (public, canopy, acct)');
select test.ok(not has_table_privilege('canopy_backup', 'auth.users', 'select'), 'the backup account cannot read the logins');
select test.ok(not has_column_privilege('canopy_backup', 'pg_authid', 'rolpassword', 'select'), 'the backup account cannot read the database passwords');
select test.ok(not has_table_privilege('canopy_backup', 'public.orders', 'insert,update,delete'), 'the backup account cannot change sales');
select test.ok(not has_table_privilege('canopy_backup', 'public.staff', 'update'), 'the backup account cannot change staff');
select test.eq((select coalesce(string_agg(p.oid::regprocedure::text, ', ' order by 1), '') from pg_proc p
                 where p.prosecdef and p.prorettype <> 'event_trigger'::regtype   -- trigger functions count: any login can attach one to a temporary table
                   and has_schema_privilege('canopy_backup', p.pronamespace, 'usage') and has_function_privilege('canopy_backup', p.oid, 'execute')
                   and p.oid <> 'canopy.backup_report(text,text,timestamptz,bigint,text,text,jsonb,text)'::regprocedure), '',
               'the backup account can run no owner-rights function except backup_report');
-- the same owner-rights code reached without naming the function (supabase/tools/backup-account.sql check 6d')
select test.eq((select coalesce(string_agg(distinct f.oid::regprocedure || ' via ' || x.via, ', '), '')
                  from (select a.aggfnoid::regprocedure::text as via, c.fn, false as needs_execute
                          from pg_aggregate a join pg_proc ap on ap.oid = a.aggfnoid
                          cross join lateral unnest(array[a.aggtransfn, a.aggfinalfn, a.aggcombinefn, a.aggserialfn, a.aggdeserialfn,
                                                          a.aggmtransfn, a.aggminvtransfn, a.aggmfinalfn]::oid[]) as c(fn)
                         where has_schema_privilege('canopy_backup', ap.pronamespace, 'usage') and has_function_privilege('canopy_backup', ap.oid, 'execute')
                        union all
                        select o.oid::regoperator::text, c.fn, c.fn = o.oprcode from pg_operator o
                          cross join lateral unnest(array[o.oprcode, o.oprrest, o.oprjoin]::oid[]) as c(fn)
                         where has_schema_privilege('canopy_backup', o.oprnamespace, 'usage')
                        union all
                        select c.castsource::regtype || ' -> ' || c.casttarget::regtype, c.castfunc, true from pg_cast c where c.castfunc <> 0
                        union all
                        select v.oid::regclass::text, d.refobjid, true
                          from pg_class v join pg_rewrite w on w.ev_class = v.oid
                          join pg_depend d on d.classid = 'pg_rewrite'::regclass and d.objid = w.oid and d.refclassid = 'pg_proc'::regclass
                         where v.relkind = 'v' and has_schema_privilege('canopy_backup', v.relnamespace, 'usage') and has_table_privilege('canopy_backup', v.oid, 'select')) x
                  join pg_proc f on f.oid = x.fn
                 where f.prosecdef and f.oid <> 'canopy.backup_report(text,text,timestamptz,bigint,text,text,jsonb,text)'::regprocedure
                   and (not x.needs_execute or has_function_privilege('canopy_backup', f.oid, 'execute'))), '',
               'no owner-rights function reachable through an aggregate, operator, cast or view');
-- every auth relation (tables, views, columns) and every view built on auth, not only auth.users
select test.eq((select coalesce(string_agg(c.oid::regclass::text, ', ' order by 1), '') from pg_class c
                 where c.relnamespace = 'auth'::regnamespace and c.relkind in ('r', 'p', 'v', 'm', 'f', 'S')
                   and (has_table_privilege('canopy_backup', c.oid, 'select') or has_any_column_privilege('canopy_backup', c.oid, 'select'))), '',
               'the backup account can read nothing in auth (sessions, tokens, MFA secrets included)');
select test.eq((select coalesce(string_agg(v.oid::regclass::text, ', ' order by 1), '')
                  from pg_class v where v.relkind in ('v', 'm') and has_table_privilege('canopy_backup', v.oid, 'select')
                   and exists (with recursive dep(rel) as (
                                 select d.refobjid from pg_rewrite w
                                   join pg_depend d on d.classid = 'pg_rewrite'::regclass and d.objid = w.oid and d.refclassid = 'pg_class'::regclass
                                  where w.ev_class = v.oid and d.refobjid <> v.oid
                                 union
                                 select d.refobjid from dep join pg_rewrite w on w.ev_class = dep.rel
                                   join pg_depend d on d.classid = 'pg_rewrite'::regclass and d.objid = w.oid and d.refclassid = 'pg_class'::regclass
                                  where d.refobjid <> w.ev_class)
                               select 1 from dep join pg_class t on t.oid = dep.rel where t.relnamespace = 'auth'::regnamespace)), '',
               'the backup account can read no view built on auth (also a view on a view, at any depth)');
-- 0002/0013's default rights also cover future views: none of the café's views shows what the account cannot read
select test.eq((select coalesce(string_agg(distinct v.oid::regclass || ' -> ' || t.oid::regclass, ', '), '')
                  from pg_class v join pg_rewrite w on w.ev_class = v.oid
                  join pg_depend d on d.classid = 'pg_rewrite'::regclass and d.objid = w.oid and d.refclassid = 'pg_class'::regclass
                  join pg_class t on t.oid = d.refobjid
                 where v.relnamespace in (select oid from pg_namespace where nspname in ('public', 'canopy', 'acct'))
                   and v.relkind in ('v', 'm') and t.oid <> v.oid
                   and has_table_privilege('canopy_backup', v.oid, 'select') and not has_table_privilege('canopy_backup', t.oid, 'select')), '',
               'no view of the café shows the backup account a table it cannot read itself');
-- nothing writable anywhere, and later tables only ever get SELECT
select test.eq((select coalesce(string_agg(c.oid::regclass::text, ', ' order by 1), '') from pg_class c
                 where c.relkind in ('r', 'p', 'v', 'm', 'f') and c.oid <> 'pg_catalog.pg_settings'::regclass
                   and c.relnamespace not in (select oid from pg_namespace where nspname ~ '^pg_(toast_)?temp_' or nspname = 'test')  -- test: these assertions' own table
                   and (has_table_privilege('canopy_backup', c.oid, 'insert, update, delete, truncate, references, trigger')
                        or has_any_column_privilege('canopy_backup', c.oid, 'insert, update, references'))), '',
               'the backup account can write to no table, view or column');
select test.eq((select count(*)::int from pg_default_acl d cross join lateral aclexplode(d.defaclacl) a
                 where a.grantee = 'canopy_backup'::regrole and a.privilege_type <> 'SELECT'), 0,
               'default privileges give the backup account SELECT only');

-- nobody else can write the backup log
select test.login('cafe'); set role authenticated;
select test.throws($$select canopy.backup_report('cloud','ok',now(),1,'x','passed','{}'::jsonb,'fake')$$, 'permission denied',
                   'the café login cannot fake a backup');
select test.eq(public.backup_status()->>'error', 'not_owner', 'the café login cannot read backup status');
reset role;
-- the tile: red with no backups, green after a verified one, amber when old or unverified
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.backup_status()->>'health', 'red', 'no backup yet: red');
reset role;
set role canopy_backup;
select canopy.backup_report('cloud', 'ok', now() - interval '5 minutes', 480000, 'canopy-respaldo-x.tar.age', 'passed', '{"public.orders": 3}', 'ok');
reset role;
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.backup_status()->>'health', 'green', 'a verified backup in the last day: green');
reset role;
update canopy.backup_runs set finished_at = now() - interval '30 hours';
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.backup_status()->>'health', 'amber', 'last good backup older than 26 h: amber');
reset role;
update canopy.backup_runs set finished_at = now() - interval '60 hours';
set role canopy_backup;
select canopy.backup_report('cloud', 'failed', now(), null, 'x', 'skipped', '{}', 'falló en: volcar la base');
reset role;
select test.login('owner', 'aal2'); set role authenticated;
select test.eq(public.backup_status()->>'health', 'red', 'older than 50 h: red');
select test.eq(public.backup_status()->>'last_attempt_detail', 'falló en: volcar la base', 'the tile shows why the last attempt failed');
reset role;

select test.done();
rollback;
