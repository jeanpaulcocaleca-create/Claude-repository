-- =====================================================================================================
-- Canopy OS · migración 0020 · Cuentas bancarias, estados de cuenta importados y conciliación bancaria
-- Pegar TODO en Supabase → SQL Editor → New query → Run.  Requiere: 0019.
--
-- Qué hace
--   * public.bank_accounts: cada cuenta del negocio (nombre, banco, moneda, últimos 4 dígitos — nunca el
--     número completo) unida a su cuenta contable de bancos.
--   * public.bank_lines: los movimientos del estado de cuenta que el contador o el dueño importa desde el
--     archivo CSV del banco. Importar el mismo archivo dos veces, o dos estados que se traslapan, no duplica.
--   * Conciliar: cada movimiento del banco se une a su línea en los libros (con sugerencias por monto y
--     fecha), o se asienta si los libros no lo tenían (comisiones, intereses, liquidaciones de tarjetas con su
--     comisión), o se marca como ignorado con una nota. Deshacer un asiento hecho aquí lo revierte.
--   * bank_overview: saldo del banco contra saldo en libros, partidas en tránsito y lo que falta conciliar.
--   * Lo usan el dueño (con el código del teléfono) y el contador; un encargado con PIN no lo ve.
-- Qué cambia para el personal: nada.
-- Reversión: drop function bank_* (las tablas y los asientos quedan).
-- =====================================================================================================
select canopy.migration_begin(20, 'bank');

create table if not exists public.bank_accounts (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  bank        text,
  currency    text not null default 'CRC' check (currency in ('CRC', 'USD')),
  last4       text check (last4 is null or last4 ~ '^[0-9]{4}$'),
  gl_account  text not null references acct.accounts(code),
  active      boolean not null default true,
  created_at  timestamptz not null default now()
);
create table if not exists public.bank_imports (
  id          uuid primary key,                         -- the page's request id
  account_id  uuid not null references public.bank_accounts(id),
  file_name   text,
  rows        int not null,
  added       int not null,
  skipped     int not null,
  date_from   date,
  date_to     date,
  imported_by text not null,
  at          timestamptz not null default now()
);
create table if not exists public.bank_lines (
  id             bigint generated always as identity primary key,
  account_id     uuid not null references public.bank_accounts(id),
  import_id      uuid references public.bank_imports(id),
  date           date not null,
  description    text not null,
  reference      text,
  amount         numeric(14,2) not null check (amount <> 0),   -- + into the account, − out of it
  balance        numeric(14,2),
  fingerprint    text not null,
  status         text not null default 'open' check (status in ('open', 'matched', 'posted', 'ignored')),
  ledger_line_id bigint unique references acct.lines(id),
  note           text,
  done_by        text,
  done_at        timestamptz,
  unique (account_id, fingerprint)
);
create index if not exists bank_lines_account_date_idx on public.bank_lines (account_id, date);
alter table public.bank_accounts enable row level security;
alter table public.bank_imports enable row level security;
alter table public.bank_lines enable row level security;
revoke all on public.bank_accounts, public.bank_imports, public.bank_lines from anon, authenticated;

-- 1) accounts -----------------------------------------------------------------------------------------------------
create or replace function public.bank_account_save(p_account jsonb)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare a acct.accounts; v_id uuid; l4 text;
begin
  if not acct.can_read() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  select * into a from acct.accounts where code = p_account->>'gl_account';
  if a.code is null or not a.active or not a.cash then return jsonb_build_object('ok', false, 'error', 'bad_account'); end if;
  l4 := nullif(right(regexp_replace(coalesce(p_account->>'last4', ''), '[^0-9]', '', 'g'), 4), '');
  if coalesce(trim(p_account->>'name'), '') = '' or (l4 is not null and length(l4) <> 4)
     or coalesce(p_account->>'currency', 'CRC') not in ('CRC', 'USD') then
    return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  v_id := nullif(p_account->>'id', '')::uuid;
  if v_id is null then
    insert into public.bank_accounts (name, bank, currency, last4, gl_account)
      values (left(trim(p_account->>'name'), 60), nullif(left(trim(coalesce(p_account->>'bank', '')), 60), ''), coalesce(p_account->>'currency', 'CRC'), l4, a.code)
      returning bank_accounts.id into v_id;
  else
    update public.bank_accounts set name = left(trim(p_account->>'name'), 60), bank = nullif(left(trim(coalesce(p_account->>'bank', '')), 60), ''),
           last4 = l4, gl_account = a.code, active = coalesce((p_account->>'active')::boolean, active)
     where bank_accounts.id = v_id;
    if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- 2) import a statement: rows as read from the bank's CSV by the page --------------------------------------------
create or replace function public.bank_import(p_account_id uuid, p_file_name text, p_rows jsonb, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare b public.bank_accounts; i public.bank_imports; v_n int; v_added int; d0 date; d1 date;
begin
  if not acct.can_read() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if p_request_id is null then return jsonb_build_object('ok', false, 'error', 'bad_request'); end if;
  select * into i from public.bank_imports where id = p_request_id;
  if i.id is not null then return jsonb_build_object('ok', true, 'repeat', true, 'added', i.added, 'skipped', i.skipped); end if;
  select * into b from public.bank_accounts where id = p_account_id and active;
  if b.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) = 0 or jsonb_array_length(p_rows) > 5000 then
    return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  -- every row must read as a date, a description and an amount that is not zero
  begin
    create temp table _rows on commit drop as
      select ord, (r->>'date')::date as date, left(trim(r->>'description'), 200) as description,
             nullif(left(trim(coalesce(r->>'reference', '')), 60), '') as reference,
             round((r->>'amount')::numeric, 2) as amount, round(nullif(r->>'balance', '')::numeric, 2) as balance
        from jsonb_array_elements(p_rows) with ordinality as x(r, ord);
  exception when others then
    return jsonb_build_object('ok', false, 'error', 'bad_rows');
  end;
  if exists (select 1 from _rows where date is null or amount is null or amount = 0 or coalesce(description, '') = ''
                                   or date > public.cr_today() + 1 or date < date '2000-01-01') then
    drop table _rows;
    return jsonb_build_object('ok', false, 'error', 'bad_rows'); end if;
  select count(*), min(date), max(date) into v_n, d0, d1 from _rows;
  insert into public.bank_imports (id, account_id, file_name, rows, added, skipped, date_from, date_to, imported_by)
    values (p_request_id, b.id, left(p_file_name, 120), v_n, 0, 0, d0, d1, acct.actor());
  -- the same movement in two files (or the same file twice) has the same fingerprint: its date, amount,
  -- text and reference, and which repetition it is among identical ones of that statement
  with keyed as (
    select r.*, r.date || '|' || r.amount || '|' || lower(regexp_replace(r.description, '\s+', ' ', 'g')) || '|' || coalesce(r.reference, '') as k
      from _rows r),
  numbered as (select k.*, k.k || '|' || row_number() over (partition by k.k order by k.ord) as fp from keyed k),
  ins as (
    insert into public.bank_lines (account_id, import_id, date, description, reference, amount, balance, fingerprint)
      select b.id, p_request_id, date, description, reference, amount, balance, fp from numbered order by ord
      on conflict (account_id, fingerprint) do nothing
      returning 1)
  select count(*) into v_added from ins;
  update public.bank_imports set added = v_added, skipped = v_n - v_added where id = p_request_id;
  drop table _rows;
  return jsonb_build_object('ok', true, 'rows', v_n, 'added', v_added, 'skipped', v_n - v_added, 'from', d0, 'to', d1);
end $$;

-- 3) reconcile -----------------------------------------------------------------------------------------------------
-- the books' side: a line on the bank's account, not yet tied to a statement line
create or replace function public._bank_free(p_line_id bigint) returns boolean language sql stable security definer set search_path = public as $$
  select not exists (select 1 from public.bank_lines where ledger_line_id = p_line_id);
$$;
revoke all on function public._bank_free(bigint) from public, anon, authenticated;

create or replace function public.bank_match(p_line_id bigint, p_ledger_line_id bigint)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare bl public.bank_lines; b public.bank_accounts; l acct.lines;
begin
  if not acct.can_read() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  select * into bl from public.bank_lines where id = p_line_id for update;
  if bl.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if bl.status <> 'open' then return jsonb_build_object('ok', false, 'error', 'not_open'); end if;
  select * into b from public.bank_accounts where id = bl.account_id;
  select * into l from acct.lines where id = p_ledger_line_id;
  if l.id is null or l.account <> b.gl_account or (l.debit - l.credit) <> bl.amount then return jsonb_build_object('ok', false, 'error', 'no_match'); end if;
  if not public._bank_free(l.id) then return jsonb_build_object('ok', false, 'error', 'already_matched'); end if;
  update public.bank_lines set status = 'matched', ledger_line_id = l.id, done_by = acct.actor(), done_at = now() where id = bl.id;
  return jsonb_build_object('ok', true);
end $$;

-- the same amount on the bank's account within 5 days, used by nothing else, and the only such pair: matched
create or replace function public.bank_auto_match(p_account_id uuid)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare b public.bank_accounts; n int := 0; rec record;
begin
  if not acct.can_read() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  select * into b from public.bank_accounts where id = p_account_id;
  if b.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  for rec in
    with cand as (
      select bl.id as bid, l.id as lid
        from public.bank_lines bl
        join acct.lines l on l.account = b.gl_account and (l.debit - l.credit) = bl.amount
        join acct.entries e on e.id = l.entry_id and abs(e.date - bl.date) <= 5
       where bl.account_id = b.id and bl.status = 'open' and public._bank_free(l.id))
    select c.bid, c.lid from cand c
     where (select count(*) from cand c2 where c2.bid = c.bid) = 1 and (select count(*) from cand c3 where c3.lid = c.lid) = 1
  loop
    update public.bank_lines set status = 'matched', ledger_line_id = rec.lid, done_by = acct.actor(), done_at = now() where id = rec.bid;
    n := n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'matched', n);
end $$;

-- a statement line the books do not have yet: posted against the accounts given (a card deposit: the card
-- sales account and the fee; a bank charge: the fees account). The parts add up to the bank's amount.
create or replace function public.bank_post(p_line_id bigint, p_parts jsonb, p_memo text)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare bl public.bank_lines; b public.bank_accounts; total numeric; lines jsonb; eid bigint; lid bigint;
begin
  if not acct.can_read() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  select * into bl from public.bank_lines where id = p_line_id for update;
  if bl.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if bl.status <> 'open' then return jsonb_build_object('ok', false, 'error', 'not_open'); end if;
  select * into b from public.bank_accounts where id = bl.account_id;
  if jsonb_typeof(p_parts) <> 'array' or jsonb_array_length(p_parts) = 0 then return jsonb_build_object('ok', false, 'error', 'bad_value'); end if;
  if exists (select 1 from jsonb_array_elements(p_parts) x left join acct.accounts a on a.code = x->>'account'
              where a.code is null or not a.active or a.code = b.gl_account or nullif(x->>'amount', '') is null) then
    return jsonb_build_object('ok', false, 'error', 'bad_account'); end if;
  select sum(round((x->>'amount')::numeric, 2)) into total from jsonb_array_elements(p_parts) x;
  if total <> bl.amount then return jsonb_build_object('ok', false, 'error', 'parts_differ', 'parts', total, 'amount', bl.amount); end if;
  -- the bank's line first (debit when money came in), then each part on the other side
  select jsonb_build_array(jsonb_build_object('account', b.gl_account, 'debit', bl.amount, 'memo', left(bl.description, 200)))
         || jsonb_agg(jsonb_build_object('account', x->>'account', 'debit', -round((x->>'amount')::numeric, 2), 'memo', nullif(x->>'memo', '')))
    into lines from jsonb_array_elements(p_parts) x;
  begin
    eid := acct.post(bl.date, coalesce(nullif(trim(p_memo), ''), 'Banco: ' || bl.description), 'bank', 'bank:' || bl.id, lines, null, acct.actor());
  exception when others then
    if sqlerrm ~ 'period_closed' then return jsonb_build_object('ok', false, 'error', 'period_closed'); end if;
    raise;
  end;
  select id into lid from acct.lines where entry_id = eid and account = b.gl_account order by id limit 1;
  update public.bank_lines set status = 'posted', ledger_line_id = lid, done_by = acct.actor(), done_at = now() where id = bl.id;
  return jsonb_build_object('ok', true, 'entry_id', eid);
end $$;

create or replace function public.bank_ignore(p_line_id bigint, p_note text)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
begin
  if not acct.can_read() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if coalesce(trim(p_note), '') = '' then return jsonb_build_object('ok', false, 'error', 'missing_reason'); end if;
  update public.bank_lines set status = 'ignored', note = left(trim(p_note), 200), done_by = acct.actor(), done_at = now()
   where id = p_line_id and status = 'open';
  if not found then return jsonb_build_object('ok', false, 'error', 'not_open'); end if;
  return jsonb_build_object('ok', true);
end $$;

-- undo: a match or an ignore is simply undone; a line posted here has its entry reversed
create or replace function public.bank_undo(p_line_id bigint)
returns jsonb language plpgsql security definer set search_path = public, acct as $$
declare bl public.bank_lines; r jsonb;
begin
  if not acct.can_read() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  select * into bl from public.bank_lines where id = p_line_id for update;
  if bl.id is null or bl.status = 'open' then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if bl.status = 'posted' then
    r := public.acct_entry_reverse((select entry_id from acct.lines where id = bl.ledger_line_id), public.cr_today(), 'movimiento del banco deshecho');
    if not coalesce((r->>'ok')::boolean, false) then return r; end if;
  end if;
  update public.bank_lines set status = 'open', ledger_line_id = null, note = null, done_by = acct.actor(), done_at = now() where id = bl.id;
  return jsonb_build_object('ok', true);
end $$;

-- 4) the account's statement against the books ---------------------------------------------------------------------
create or replace function public.bank_overview(p_account_id uuid, p_from date, p_to date)
returns jsonb language plpgsql stable security definer set search_path = public, acct as $$
declare b public.bank_accounts; first_day date; book numeric; stmt numeric; stmt_day date;
begin
  if not acct.can_read() then return jsonb_build_object('ok', false, 'error', 'not_allowed'); end if;
  if p_account_id is null then
    return jsonb_build_object('ok', true, 'accounts', (select coalesce(jsonb_agg(to_jsonb(a) order by a.name), '[]') from public.bank_accounts a),
      'gl_accounts', (select coalesce(jsonb_agg(jsonb_build_object('code', code, 'name', name) order by code), '[]') from acct.accounts where cash and active));
  end if;
  select * into b from public.bank_accounts where id = p_account_id;
  if b.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if p_from is null or p_to is null or p_to < p_from or p_to - p_from > 370 then return jsonb_build_object('ok', false, 'error', 'bad_range'); end if;
  select min(date) into first_day from public.bank_lines where account_id = b.id;
  select coalesce(sum(l.debit - l.credit), 0) into book from acct.lines l join acct.entries e on e.id = l.entry_id where l.account = b.gl_account and e.date <= p_to;
  select balance, date into stmt, stmt_day from public.bank_lines where account_id = b.id and date <= p_to and balance is not null order by date desc, id desc limit 1;
  return jsonb_build_object('ok', true, 'account', to_jsonb(b),
    'accounts', (select coalesce(jsonb_agg(to_jsonb(a) order by a.name), '[]') from public.bank_accounts a),
    'gl_accounts', (select coalesce(jsonb_agg(jsonb_build_object('code', code, 'name', name) order by code), '[]') from acct.accounts where cash and active),
    'post_accounts', (select coalesce(jsonb_agg(jsonb_build_object('code', code, 'name', name) order by code), '[]') from acct.accounts where active and code <> b.gl_account),
    'lines', (select coalesce(jsonb_agg(jsonb_build_object('id', bl.id, 'date', bl.date, 'description', bl.description, 'reference', bl.reference,
                       'amount', bl.amount, 'balance', bl.balance, 'status', bl.status, 'note', bl.note,
                       'ledger', (select jsonb_build_object('entry_no', e.entry_no, 'date', e.date, 'memo', e.memo) from acct.lines l join acct.entries e on e.id = l.entry_id where l.id = bl.ledger_line_id),
                       'suggest', case when bl.status = 'open' then (
                          select coalesce(jsonb_agg(jsonb_build_object('line_id', s.id, 'entry_no', s.entry_no, 'date', s.date, 'memo', s.memo) order by s.gap, s.id), '[]')
                            from (select l.id, e.entry_no, e.date, e.memo, abs(e.date - bl.date) as gap
                                    from acct.lines l join acct.entries e on e.id = l.entry_id
                                   where l.account = b.gl_account and (l.debit - l.credit) = bl.amount and abs(e.date - bl.date) <= 10 and public._bank_free(l.id)
                                   order by abs(e.date - bl.date), l.id limit 3) s) end)
                     order by bl.date, bl.id), '[]')
                from public.bank_lines bl where bl.account_id = b.id and bl.date between p_from and p_to),
    -- in the books, not on any statement yet (deposits in transit, payments not cleared), since the first statement
    'book_only', (select coalesce(jsonb_agg(jsonb_build_object('line_id', l.id, 'entry_no', e.entry_no, 'date', e.date, 'memo', e.memo, 'amount', l.debit - l.credit) order by e.date), '[]')
                    from acct.lines l join acct.entries e on e.id = l.entry_id
                   where l.account = b.gl_account and first_day is not null and e.date >= first_day and e.date <= p_to and public._bank_free(l.id)),
    'summary', jsonb_build_object('book_balance', book, 'statement_balance', stmt, 'statement_day', stmt_day,
      'open_statement', (select coalesce(sum(amount), 0) from public.bank_lines where account_id = b.id and status = 'open' and date <= p_to),
      'book_only', (select coalesce(sum(l.debit - l.credit), 0) from acct.lines l join acct.entries e on e.id = l.entry_id
                     where l.account = b.gl_account and first_day is not null and e.date >= first_day and e.date <= p_to and public._bank_free(l.id))),
    'imports', (select coalesce(jsonb_agg(to_jsonb(i) order by i.at desc), '[]') from (select * from public.bank_imports where account_id = b.id order by at desc limit 10) i));
end $$;

revoke all on function public.bank_account_save(jsonb), public.bank_import(uuid, text, jsonb, uuid), public.bank_match(bigint, bigint),
                       public.bank_auto_match(uuid), public.bank_post(bigint, jsonb, text), public.bank_ignore(bigint, text), public.bank_undo(bigint),
                       public.bank_overview(uuid, date, date) from public, anon;
grant execute on function public.bank_account_save(jsonb), public.bank_import(uuid, text, jsonb, uuid), public.bank_match(bigint, bigint),
                          public.bank_auto_match(uuid), public.bank_post(bigint, jsonb, text), public.bank_ignore(bigint, text), public.bank_undo(bigint),
                          public.bank_overview(uuid, date, date) to authenticated;

select canopy.migration_end(20, 'bank');
notify pgrst, 'reload schema';
