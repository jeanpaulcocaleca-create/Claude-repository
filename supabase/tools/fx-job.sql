-- Canopy OS · tipo de cambio automático (Hacienda), para después de activar las extensiones.
-- 1) Supabase → Database → Extensions: active "http" y "pg_cron".
-- 2) SQL Editor → New query → pegue TODO este archivo → Run. Se puede correr más de una vez.
-- 3) Revise: select * from canopy.fx_fetch_log order by id desc limit 5;  y  select * from public.fx_rates order by day desc limit 3;
-- Es la misma parte de la migración 0010 que crea la consulta y la programa (06:10 y 17:40 hora de Costa Rica).
do $fx$
begin
  if exists (select 1 from pg_extension where extname = 'http') then
    execute $f$
      create or replace function canopy.fx_fetch()
      returns void language plpgsql security definer set search_path = public, canopy, extensions as $b$
      declare r record;
      begin
        select status, content into r from http_get('https://api.hacienda.go.cr/indicadores/tc/dolar');
        if r.status <> 200 then raise exception 'fx_http_%', r.status; end if;
        perform canopy.fx_record_hacienda(r.content::jsonb);
      exception when others then
        insert into canopy.fx_fetch_log (ok, detail) values (false, left(sqlerrm, 300));
      end $b$;
    $f$;
    execute 'revoke all on function canopy.fx_fetch() from public';
  end if;
  if exists (select 1 from pg_extension where extname = 'pg_cron') and to_regprocedure('canopy.fx_fetch()') is not null then
    perform cron.schedule('canopy-fx-morning', '10 12 * * *', 'select canopy.fx_fetch()');   -- 06:10 Costa Rica
    perform cron.schedule('canopy-fx-evening', '40 23 * * *', 'select canopy.fx_fetch()');   -- 17:40 Costa Rica
  end if;
end $fx$;
-- the first rate, now
do $now$ begin
  if to_regprocedure('canopy.fx_fetch()') is not null then perform canopy.fx_fetch(); end if;
end $now$;
