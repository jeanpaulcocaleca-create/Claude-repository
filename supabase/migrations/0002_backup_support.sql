-- =====================================================================================================
-- Canopy OS · migración 0002 · Respaldos: cuenta de solo lectura y registro de respaldos
-- Pegar TODO en Supabase → SQL Editor → New query → Run.  Requiere: 0001.
--
-- Qué hace
--   * Crea la cuenta "canopy_backup": puede LEER toda la base para respaldarla y no puede cambiar nada,
--     salvo anotar "respaldo hecho" en el registro. Se crea SIN contraseña y sin poder entrar: el dueño le
--     pone contraseña después con una sola línea (docs/RESPALDOS.md, paso 2). La contraseña nunca va en GitHub.
--   * canopy.backup_runs: cada respaldo (de la nube o de la computadora) anota cuándo, tamaño, filas por
--     tabla y si la prueba de restauración pasó.
--   * public.backup_status(): la tarjeta "Respaldos" del Inicio del dueño lee esto (solo áreas del dueño).
-- Qué cambia para el personal: nada.
-- Reversión: drop role canopy_backup; drop table canopy.backup_runs; (no toca datos del negocio).
-- =====================================================================================================
select canopy.migration_begin(2, 'backup_support');

-- the backup account: reads everything (bypassing row rules, so the dump is complete), writes nothing
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'canopy_backup') then
    create role canopy_backup nologin bypassrls;
  else
    alter role canopy_backup bypassrls;
  end if;
end $$;
grant pg_read_all_data to canopy_backup;
grant usage on schema canopy to canopy_backup;

create table if not exists canopy.backup_runs (
  id           bigint generated always as identity primary key,
  source       text not null check (source in ('cloud', 'computer', 'manual')),
  status       text not null check (status in ('ok', 'failed')),
  started_at   timestamptz,
  finished_at  timestamptz not null default now(),
  size_bytes   bigint,
  file_name    text,
  restore_test text check (restore_test in ('passed', 'failed', 'skipped')),
  row_counts   jsonb,
  detail       text
);
create index if not exists backup_runs_finished_idx on canopy.backup_runs (finished_at desc);
revoke all on canopy.backup_runs from public;

-- the backup job reports each run here (the only write the backup account can make)
create or replace function canopy.backup_report(p_source text, p_status text, p_started_at timestamptz, p_size_bytes bigint,
                                                p_file_name text, p_restore_test text, p_row_counts jsonb, p_detail text)
returns bigint language plpgsql security definer set search_path = canopy, public as $$
declare nid bigint;
begin
  insert into canopy.backup_runs (source, status, started_at, size_bytes, file_name, restore_test, row_counts, detail)
    values (p_source, p_status, p_started_at, p_size_bytes, left(p_file_name, 200), p_restore_test, p_row_counts, left(p_detail, 2000))
    returning id into nid;
  delete from canopy.backup_runs where finished_at < now() - interval '400 days';
  return nid;
end $$;
revoke all on function canopy.backup_report(text, text, timestamptz, bigint, text, text, jsonb, text) from public;
grant execute on function canopy.backup_report(text, text, timestamptz, bigint, text, text, jsonb, text) to canopy_backup;

-- for the owner's Home tile: last good backup, last attempt, and whether it is late
create or replace function public.backup_status()
returns jsonb language plpgsql stable security definer set search_path = canopy, public as $$
declare last_ok canopy.backup_runs; last_any canopy.backup_runs; fails int;
begin
  if not public.is_owner() then return jsonb_build_object('ok', false, 'error', 'not_owner'); end if;
  select * into last_ok from canopy.backup_runs where status = 'ok' order by finished_at desc limit 1;
  select * into last_any from canopy.backup_runs order by finished_at desc limit 1;
  select count(*) into fails from canopy.backup_runs where status = 'failed' and finished_at > now() - interval '7 days';
  return jsonb_build_object(
    'ok', true,
    'last_ok_at', last_ok.finished_at,
    'last_ok_size', last_ok.size_bytes,
    'last_ok_restore_test', last_ok.restore_test,
    'last_ok_source', last_ok.source,
    'last_attempt_at', last_any.finished_at,
    'last_attempt_status', last_any.status,
    'last_attempt_detail', case when last_any.status = 'failed' then last_any.detail end,
    'failures_7d', fails,
    -- green: a verified backup in the last 26 h · amber: older than 26 h · red: none in 50 h or never
    'health', case when last_ok.id is null then 'red'
                   when last_ok.finished_at < now() - interval '50 hours' then 'red'
                   when last_ok.finished_at < now() - interval '26 hours' or last_ok.restore_test <> 'passed' then 'amber'
                   else 'green' end);
end $$;
revoke all on function public.backup_status() from public, anon;
grant execute on function public.backup_status() to authenticated;

select canopy.migration_end(2, 'backup_support');
notify pgrst, 'reload schema';
