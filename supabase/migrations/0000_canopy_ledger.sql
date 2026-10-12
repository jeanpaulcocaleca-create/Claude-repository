-- =====================================================================================================
-- Canopy OS · migración 0000 · Registro de migraciones (ledger)
-- Pegar TODO en Supabase → SQL Editor → New query → Run.  Requiere: nada.  Seguro de ejecutar una sola vez.
--
-- Qué hace
--   * Crea el esquema interno "canopy" (no visible desde la API pública).
--   * Crea canopy.migrations: cada migración se anota aquí al aplicarse. Una migración se niega a correr
--     dos veces o fuera de orden, así que pegar el archivo equivocado no cambia nada.
--   * public.canopy_schema_version(): las páginas y la publicación consultan qué versión tiene la base.
--   * Desde ahora los 18 archivos históricos de supabase/ se niegan a correr (traen un guardia al inicio).
-- Reversión: no hace falta; no toca datos del negocio.
-- =====================================================================================================

create schema if not exists canopy;
revoke all on schema canopy from public;

create table if not exists canopy.migrations (
  version     int primary key,
  name        text not null,
  applied_at  timestamptz not null default now(),
  applied_by  text not null default current_user
);
revoke all on canopy.migrations from public;

-- Every migration starts with canopy.migration_begin(N, 'name') and ends with canopy.migration_end(N, 'name').
-- The whole paste runs as one transaction, so a refusal here means nothing in the file was applied.
create or replace function canopy.migration_begin(p_version int, p_name text)
returns void language plpgsql as $$
declare last int;
begin
  perform pg_advisory_xact_lock(hashtext('canopy.migrations'));
  -- never wait long for a lock on a busy table: fail fast instead of freezing the tills
  perform set_config('lock_timeout', '8s', true);
  perform set_config('statement_timeout', '300s', true);
  if exists (select 1 from canopy.migrations where version = p_version) then
    raise exception 'La migración % (%) ya estaba aplicada: no se cambió nada.', p_version, p_name;
  end if;
  select max(version) into last from canopy.migrations;
  if p_version > 0 and coalesce(last, -1) <> p_version - 1 then
    raise exception 'Falta aplicar antes la migración %. Esta es la %; la última aplicada es %. No se cambió nada.',
      p_version - 1, p_version, coalesce(last::text, 'ninguna');
  end if;
end $$;

create or replace function canopy.migration_end(p_version int, p_name text)
returns void language plpgsql as $$
begin
  insert into canopy.migrations (version, name) values (p_version, p_name);
end $$;
revoke all on function canopy.migration_begin(int, text), canopy.migration_end(int, text) from public;

-- Which schema version is installed (read by pages and by the publishing checklist; no secrets).
create or replace function public.canopy_schema_version()
returns int language sql stable security definer set search_path = canopy, public as $$
  select coalesce(max(version), -1) from canopy.migrations;
$$;
revoke all on function public.canopy_schema_version() from public;
grant execute on function public.canopy_schema_version() to anon, authenticated;

select canopy.migration_begin(0, 'canopy_ledger');
select canopy.migration_end(0, 'canopy_ledger');
notify pgrst, 'reload schema';
