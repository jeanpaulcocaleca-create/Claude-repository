-- Canopy OS rehearsal · the accountant books the last 30 days of the OLD history (sales rung before the
-- migrations, without tax stamps) on the migrated copy. The books must balance and tie to the sales.
\set ON_ERROR_STOP on
insert into auth.users (id, email) values ('ac000000-0000-4000-8000-000000000003', 'contador@test.local') on conflict do nothing;
insert into public.app_accounts (user_id, kind, label) values ('ac000000-0000-4000-8000-000000000003', 'accountant', 'contador@test.local')
  on conflict (user_id) do update set kind = excluded.kind;
select (public.cr_today() - 30)::text as d0, (public.cr_today() - 1)::text as d1 \gset
select set_config('request.jwt.claims', '{"sub":"ac000000-0000-4000-8000-000000000003","role":"authenticated","aal":"aal2"}', false);
set role authenticated;
select public.acct_post_days(:'d0', :'d1') as posted \gset
set constraints all immediate;
set constraints all deferred;
select public.acct_trial_balance(:'d0', :'d1') as tb \gset
select public.acct_income_statement(:'d0', :'d1') as inc \gset
reset role;
select set_config('request.jwt.claims', '', false);
\echo :posted
do $$
declare n int; unbalanced int; dr numeric; cr numeric; sales numeric; books numeric;
begin
  select count(*) into n from acct.entries where source = 'day';
  if n < 28 then raise exception 'books: only % days posted', n; end if;
  select count(*) into unbalanced from (select entry_id from acct.lines group by entry_id having sum(debit) <> sum(credit)) u;
  if unbalanced > 0 then raise exception 'books: % unbalanced entries', unbalanced; end if;
  select sum(debit), sum(credit) into dr, cr from acct.lines;
  if dr <> cr then raise exception 'books: debits % <> credits %', dr, cr; end if;
  -- what the days owe the café (cash, card, SINPE…) equals the sales of those days, colón for colón
  select coalesce(sum(total_crc), 0) into sales from public.orders
   where paid and voided_at is null and business_date between public.cr_today() - 30 and public.cr_today() - 1;
  select coalesce(sum(l.credit - l.debit), 0) into books from acct.lines l join acct.entries e on e.id = l.entry_id
    join acct.accounts a on a.code = l.account
   where e.source = 'day' and (a.code like '41%' or a.code = '2110');
  raise warning 'books: % days, debits = credits = %, sales %, revenue + tax in the books %', n, dr, sales, books;
  if abs(sales - books) > 1 then raise exception 'books: sales % but revenue + IVA %', sales, books; end if;
end $$;
