-- Canopy OS · The Hanging Garden Café
-- Manager authorization: run ONCE in Supabase (SQL Editor -> New query -> paste -> Run).
-- Safe to re-run. Run supabase/timeclock.sql first if you have not already.
--
-- After this script:
--   * Every team member has a role: "staff" or "manager".
--   * PINs are stored hashed and can never be read from the pages.
--   * Clocking in and out checks the PIN inside the database.
--   * Changing, adding or deleting a shift, managing the team, and voiding an
--     order all require a manager's PIN, and every approval is written to an
--     audit log (who approved it, when, what changed, and why).
--   * Orders are never deleted: a void keeps the record and marks it.
--   * The pages can no longer update or delete hours or orders directly.

create extension if not exists pgcrypto;

-- 1) Roles and hashed PINs ----------------------------------------------------
alter table public.staff add column if not exists role text not null default 'staff';
alter table public.staff add column if not exists pin_hash text;
alter table public.staff add column if not exists failed_pins int not null default 0;
alter table public.staff add column if not exists locked_until timestamptz;
alter table public.staff drop constraint if exists staff_role_check;
alter table public.staff add constraint staff_role_check check (role in ('staff', 'manager'));

-- move any plain-text PINs into hashes, then drop the plain column for good
do $$ begin
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'staff' and column_name = 'pin') then
    update public.staff set pin_hash = crypt(pin, gen_salt('bf'))
      where pin_hash is null and pin is not null and pin <> '';
    alter table public.staff drop column pin;
  end if;
end $$;

-- 2) Orders can be voided, never deleted ---------------------------------------
alter table public.orders add column if not exists voided_at timestamptz;
alter table public.orders add column if not exists voided_by uuid references public.staff(id) on delete set null;
alter table public.orders add column if not exists void_reason text;
create index if not exists orders_voided_idx on public.orders (voided_at) where voided_at is not null;

-- 3) Audit log -----------------------------------------------------------------
create table if not exists public.audit_log (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  action text not null,        -- shift_edit | shift_add | shift_delete | staff_save | order_void
  manager_id uuid,
  manager_name text,
  target_id text,
  summary text,
  details jsonb
);
create index if not exists audit_log_at_idx on public.audit_log (at desc);

-- 4) PIN check (internal) ------------------------------------------------------
-- Five wrong PINs in a row lock that person out for 10 minutes.
create or replace function public._verify_pin(p_staff_id uuid, p_pin text, p_need_manager boolean,
                                              out err text, out sid uuid, out sname text)
language plpgsql security definer set search_path = public as $$
declare s public.staff;
begin
  select * into s from public.staff where id = p_staff_id;
  if s.id is null then err := 'unknown_staff'; return; end if;
  if not s.active then err := 'inactive'; return; end if;
  if p_need_manager and s.role <> 'manager' then err := 'not_manager'; return; end if;
  if s.locked_until is not null and s.locked_until > now() then err := 'locked'; return; end if;
  if s.pin_hash is null or crypt(coalesce(p_pin, ''), s.pin_hash) <> s.pin_hash then
    update public.staff
      set failed_pins = failed_pins + 1,
          locked_until = case when failed_pins + 1 >= 5 then now() + interval '10 minutes' else locked_until end
      where id = s.id;
    err := 'bad_pin'; return;
  end if;
  update public.staff set failed_pins = 0, locked_until = null where id = s.id;
  sid := s.id; sname := s.name; err := null;
end $$;
revoke all on function public._verify_pin(uuid, text, boolean) from public, anon, authenticated;

-- 5) Clock in / out (any active team member, own PIN) --------------------------
create or replace function public.clock_punch(p_staff_id uuid, p_pin text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v record; e public.time_entries;
begin
  select * into v from public._verify_pin(p_staff_id, p_pin, false);
  if v.err is not null then return jsonb_build_object('ok', false, 'error', v.err); end if;
  select * into e from public.time_entries
    where staff_id = p_staff_id and clock_out is null order by clock_in desc limit 1;
  if e.id is not null then
    update public.time_entries set clock_out = now() where id = e.id;
    return jsonb_build_object('ok', true, 'action', 'out', 'clock_in', e.clock_in, 'clock_out', now());
  end if;
  insert into public.time_entries (staff_id, clock_in) values (p_staff_id, now()) returning * into e;
  return jsonb_build_object('ok', true, 'action', 'in', 'clock_in', e.clock_in);
end $$;

-- 6) Manager: add or edit a shift ----------------------------------------------
create or replace function public.manager_save_shift(p_manager_id uuid, p_manager_pin text,
    p_entry_id uuid, p_staff_id uuid, p_clock_in timestamptz, p_clock_out timestamptz, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v record; old public.time_entries; nid uuid; who text;
begin
  select * into v from public._verify_pin(p_manager_id, p_manager_pin, true);
  if v.err is not null then return jsonb_build_object('ok', false, 'error', v.err); end if;
  if p_clock_in is null then return jsonb_build_object('ok', false, 'error', 'missing_in'); end if;
  if p_clock_out is not null and p_clock_out <= p_clock_in then
    return jsonb_build_object('ok', false, 'error', 'bad_range'); end if;
  if coalesce(trim(p_reason), '') = '' then return jsonb_build_object('ok', false, 'error', 'missing_reason'); end if;
  if p_entry_id is not null then
    select * into old from public.time_entries where id = p_entry_id;
    if old.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
    update public.time_entries set clock_in = p_clock_in, clock_out = p_clock_out where id = p_entry_id;
    nid := p_entry_id;
    select name into who from public.staff where id = old.staff_id;
    insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
      values ('shift_edit', v.sid, v.sname, nid::text, trim(p_reason),
        jsonb_build_object('staff_id', old.staff_id, 'staff_name', who,
          'before', jsonb_build_object('clock_in', old.clock_in, 'clock_out', old.clock_out),
          'after',  jsonb_build_object('clock_in', p_clock_in, 'clock_out', p_clock_out)));
  else
    if p_staff_id is null then return jsonb_build_object('ok', false, 'error', 'missing_staff'); end if;
    insert into public.time_entries (staff_id, clock_in, clock_out)
      values (p_staff_id, p_clock_in, p_clock_out) returning id into nid;
    select name into who from public.staff where id = p_staff_id;
    insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
      values ('shift_add', v.sid, v.sname, nid::text, trim(p_reason),
        jsonb_build_object('staff_id', p_staff_id, 'staff_name', who,
          'after', jsonb_build_object('clock_in', p_clock_in, 'clock_out', p_clock_out)));
  end if;
  return jsonb_build_object('ok', true, 'id', nid);
end $$;

-- 7) Manager: delete a shift ---------------------------------------------------
create or replace function public.manager_delete_shift(p_manager_id uuid, p_manager_pin text,
    p_entry_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v record; old public.time_entries; who text;
begin
  select * into v from public._verify_pin(p_manager_id, p_manager_pin, true);
  if v.err is not null then return jsonb_build_object('ok', false, 'error', v.err); end if;
  if coalesce(trim(p_reason), '') = '' then return jsonb_build_object('ok', false, 'error', 'missing_reason'); end if;
  select * into old from public.time_entries where id = p_entry_id;
  if old.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  select name into who from public.staff where id = old.staff_id;
  delete from public.time_entries where id = p_entry_id;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('shift_delete', v.sid, v.sname, p_entry_id::text, trim(p_reason),
      jsonb_build_object('staff_id', old.staff_id, 'staff_name', who,
        'before', jsonb_build_object('clock_in', old.clock_in, 'clock_out', old.clock_out)));
  return jsonb_build_object('ok', true);
end $$;

-- 8) Manager: add or edit a team member ---------------------------------------
-- While no active manager exists yet, the first person saved becomes the manager
-- with no approval needed (one-time setup). After that, every change needs a
-- manager's PIN, and the last active manager can never be removed or demoted.
create or replace function public.manager_save_staff(p_manager_id uuid, p_manager_pin text,
    p_id uuid, p_name text, p_pin text, p_active boolean, p_role text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v record; bootstrap boolean; nid uuid; role_final text; old public.staff;
        managers_left int; msid uuid; msname text;
begin
  bootstrap := not exists (select 1 from public.staff where active and role = 'manager');
  if bootstrap then
    msid := null; msname := 'first setup';
  else
    select * into v from public._verify_pin(p_manager_id, p_manager_pin, true);
    if v.err is not null then return jsonb_build_object('ok', false, 'error', v.err); end if;
    msid := v.sid; msname := v.sname;
  end if;
  if coalesce(trim(p_name), '') = '' then return jsonb_build_object('ok', false, 'error', 'missing_name'); end if;
  if p_pin is not null and p_pin <> '' and p_pin !~ '^[0-9]{4,8}$' then
    return jsonb_build_object('ok', false, 'error', 'bad_pin_format'); end if;
  role_final := case when bootstrap then 'manager' when p_role = 'manager' then 'manager' else 'staff' end;

  if p_id is null then
    if p_pin is null or p_pin = '' then return jsonb_build_object('ok', false, 'error', 'missing_pin'); end if;
    insert into public.staff (name, pin_hash, active, role)
      values (trim(p_name), crypt(p_pin, gen_salt('bf')), coalesce(p_active, true), role_final)
      returning id into nid;
  else
    select * into old from public.staff where id = p_id;
    if old.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
    -- never remove or demote the last active manager
    if old.role = 'manager' and old.active and (role_final <> 'manager' or not coalesce(p_active, true)) then
      select count(*) into managers_left from public.staff
        where active and role = 'manager' and id <> old.id;
      if managers_left = 0 then return jsonb_build_object('ok', false, 'error', 'last_manager'); end if;
    end if;
    update public.staff set
      name = trim(p_name),
      pin_hash = case when p_pin is not null and p_pin <> '' then crypt(p_pin, gen_salt('bf')) else pin_hash end,
      failed_pins = case when p_pin is not null and p_pin <> '' then 0 else failed_pins end,
      locked_until = case when p_pin is not null and p_pin <> '' then null else locked_until end,
      active = coalesce(p_active, active),
      role = role_final
      where id = p_id;
    nid := p_id;
  end if;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('staff_save', msid, msname, nid::text,
      case when p_id is null then 'added ' else 'updated ' end || trim(p_name),
      jsonb_build_object('name', trim(p_name), 'active', coalesce(p_active, true), 'role', role_final,
                         'pin_changed', (p_pin is not null and p_pin <> ''), 'first_setup', bootstrap));
  return jsonb_build_object('ok', true, 'id', nid, 'role', role_final, 'first_setup', bootstrap);
end $$;

-- 9) Manager: void an order ----------------------------------------------------
create or replace function public.manager_void_order(p_manager_id uuid, p_manager_pin text,
    p_order_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v record; o public.orders; items text;
begin
  select * into v from public._verify_pin(p_manager_id, p_manager_pin, true);
  if v.err is not null then return jsonb_build_object('ok', false, 'error', v.err); end if;
  if coalesce(trim(p_reason), '') = '' then return jsonb_build_object('ok', false, 'error', 'missing_reason'); end if;
  select * into o from public.orders where id = p_order_id;
  if o.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if o.voided_at is not null then return jsonb_build_object('ok', false, 'error', 'already_voided'); end if;
  update public.orders set voided_at = now(), voided_by = v.sid, void_reason = trim(p_reason) where id = p_order_id;
  select string_agg(qty || 'x ' || item_name, ', ') into items from public.order_items where order_id = p_order_id;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('order_void', v.sid, v.sname, p_order_id::text, trim(p_reason),
      jsonb_build_object('total_crc', o.total_crc, 'payment_method', o.payment_method,
                         'created_at', o.created_at, 'items', items));
  return jsonb_build_object('ok', true);
end $$;

-- 10) Who may call what --------------------------------------------------------
revoke all on function public.clock_punch(uuid, text) from public, anon;
revoke all on function public.manager_save_shift(uuid, text, uuid, uuid, timestamptz, timestamptz, text) from public, anon;
revoke all on function public.manager_delete_shift(uuid, text, uuid, text) from public, anon;
revoke all on function public.manager_save_staff(uuid, text, uuid, text, text, boolean, text) from public, anon;
revoke all on function public.manager_void_order(uuid, text, uuid, text) from public, anon;
grant execute on function public.clock_punch(uuid, text) to authenticated;
grant execute on function public.manager_save_shift(uuid, text, uuid, uuid, timestamptz, timestamptz, text) to authenticated;
grant execute on function public.manager_delete_shift(uuid, text, uuid, text) to authenticated;
grant execute on function public.manager_save_staff(uuid, text, uuid, text, text, boolean, text) to authenticated;
grant execute on function public.manager_void_order(uuid, text, uuid, text) to authenticated;

-- 11) Lock the tables down ----------------------------------------------------
-- The pages read with the café login; every write below goes through the functions.
revoke all on public.staff from anon, authenticated;
grant select (id, name, active, role, created_at) on public.staff to authenticated;
revoke all on public.time_entries from anon, authenticated;
grant select on public.time_entries to authenticated;
revoke all on public.orders from anon, authenticated;
grant select, insert on public.orders to authenticated;
revoke all on public.order_items from anon, authenticated;
grant select, insert on public.order_items to authenticated;
revoke all on public.audit_log from anon, authenticated;
grant select on public.audit_log to authenticated;

alter table public.staff enable row level security;
alter table public.time_entries enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.audit_log enable row level security;

do $$ declare p record; begin
  for p in select tablename, policyname from pg_policies
           where schemaname = 'public'
             and tablename in ('staff', 'time_entries', 'orders', 'order_items', 'audit_log') loop
    execute format('drop policy if exists %I on public.%I', p.policyname, p.tablename);
  end loop;
end $$;

create policy "staff read for signed-in" on public.staff for select to authenticated using (true);
create policy "time entries read for signed-in" on public.time_entries for select to authenticated using (true);
create policy "orders read for signed-in" on public.orders for select to authenticated using (true);
create policy "orders add for signed-in" on public.orders for insert to authenticated with check (true);
create policy "order items read for signed-in" on public.order_items for select to authenticated using (true);
create policy "order items add for signed-in" on public.order_items for insert to authenticated with check (true);
create policy "audit read for signed-in" on public.audit_log for select to authenticated using (true);

notify pgrst, 'reload schema';
