-- Migration 0002: backup account, backup log and the owner's backup tile.
begin;

select test.ok((select rolbypassrls from pg_roles where rolname = 'canopy_backup'), 'the backup account reads past row rules (complete dumps)');
select test.ok(pg_has_role('canopy_backup', 'pg_read_all_data', 'member'), 'the backup account can read every table');
select test.ok(not has_table_privilege('canopy_backup', 'public.orders', 'insert,update,delete'), 'the backup account cannot change sales');
select test.ok(not has_table_privilege('canopy_backup', 'public.staff', 'update'), 'the backup account cannot change staff');

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
