-- Hanging Garden Café · owner areas behind a PIN (manager mode), and the owner role
-- Run ONCE in Supabase: SQL Editor -> New query -> paste -> Run. Safe to run again.
-- Run after supabase/access.sql. If you ever re-run accounts.sql, authorization.sql, access.sql or
-- inventory.sql, run this script again afterwards: it is the one that decides who opens the owner areas.
--
-- What changes
--   * Three roles on the team: staff (team member), manager (GM / encargado), owner (dueño).
--   * The owner areas (Home, Sales, Menu Manager, Inventory, Hours & team, approvals log) open only with the
--     PIN of an owner, GM or manager, on that device, for 15 minutes or until someone taps Lock.
--     A team member's PIN never opens them. Unlocking the front register does not unlock the iPad.
--     The owner login with the phone code (2FA) typed this session also counts as an authorized code.
--   * Sales reports: owners always; a manager only if the owner switched "may open sales" on for them.
--   * Only an owner can add, edit or promote owners. The owner login may name the first owner.
--   * Every unlock is written to the approvals log.
-- How the device is recognised: the page receives a long random token when the PIN is accepted and sends
-- it with every request (header x-hg-unlock). The database keeps only its SHA-256 hash.

create extension if not exists pgcrypto;

-- 1) Roles --------------------------------------------------------------------------------------
alter table public.staff drop constraint if exists staff_role_check;
alter table public.staff add constraint staff_role_check check (role in ('staff', 'manager', 'owner'));

-- "Manager" approvals (voids, shifts, discounts, unlocks) accept managers and owners.
create or replace function public._verify_pin(p_staff_id uuid, p_pin text, p_need_manager boolean,
                                              out err text, out sid uuid, out sname text)
language plpgsql security definer set search_path = public, extensions as $$
declare s public.staff;
begin
  select * into s from public.staff where id = p_staff_id;
  if s.id is null then err := 'unknown_staff'; return; end if;
  if not s.active then err := 'inactive'; return; end if;
  if p_need_manager and s.role not in ('manager', 'owner') then err := 'not_manager'; return; end if;
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

-- 2) Manager mode, per device ---------------------------------------------------------------------
create table if not exists public.access_unlocks (
  token_hash text primary key,
  user_id uuid not null,
  staff_id uuid references public.staff(id) on delete cascade,
  staff_name text,
  staff_role text,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null
);
create index if not exists access_unlocks_user_idx on public.access_unlocks (user_id);
alter table public.access_unlocks enable row level security;
revoke all on public.access_unlocks from anon, authenticated;

-- the token this request carries, hashed; null when there is none
create or replace function public._unlock_token_hash()
returns text language plpgsql stable set search_path = public, extensions as $$
declare h text; t text;
begin
  h := nullif(current_setting('request.headers', true), '');
  if h is null then return null; end if;
  begin
    t := nullif(trim(h::json ->> 'x-hg-unlock'), '');
  exception when others then return null;
  end;
  if t is null then return null; end if;
  return encode(digest(t, 'sha256'), 'hex');
end $$;

-- the unlock this device holds right now, with the unlocking person's current role
create or replace function public._unlock_staff(out staff_id uuid, out staff_name text, out staff_role text,
                                                out expires_at timestamptz, out can_see_sales boolean)
language sql stable security definer set search_path = public, extensions as $$
  select s.id, s.name, s.role, u.expires_at, s.can_see_sales
    from public.access_unlocks u join public.staff s on s.id = u.staff_id
   where u.token_hash = public._unlock_token_hash() and u.user_id = auth.uid() and u.expires_at > now()
     and s.active and s.role in ('manager', 'owner')
   limit 1;
$$;

-- 'owner' | 'manager' | null: how far this request may go
create or replace function public.access_level()
returns text language plpgsql stable security definer set search_path = public, extensions as $$
declare k text; r record;
begin
  k := public.account_kind();
  if k is null then return null; end if;
  if k = 'owner' and coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2' then return 'owner'; end if;
  select * into r from public._unlock_staff();
  return r.staff_role;
end $$;

-- is_owner() now means "the owner areas are open on this request" (owner or manager level).
-- Every table rule and function that already asks is_owner() follows the new meaning at once.
create or replace function public.is_owner()
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select coalesce(public.access_level() is not null, false);
$$;
create or replace function public.is_true_owner()
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select coalesce(public.access_level() = 'owner', false);
$$;
revoke all on function public._unlock_token_hash(), public._unlock_staff() from public, anon, authenticated;
revoke all on function public.access_level(), public.is_owner(), public.is_true_owner() from public, anon;
grant execute on function public.access_level(), public.is_owner(), public.is_true_owner() to authenticated;

-- who acted, for the approvals log
create or replace function public._owner_label()
returns text language plpgsql stable security definer set search_path = public, extensions as $$
declare r record; em text;
begin
  select * into r from public._unlock_staff();
  if r.staff_id is not null then
    return r.staff_name || case r.staff_role when 'owner' then ' (owner)' else ' (manager)' end;
  end if;
  begin
    select email into em from auth.users where id = auth.uid();
  exception when others then em := null;
  end;
  return 'owner login' || coalesce(' · ' || em, '');
end $$;
revoke all on function public._owner_label() from public, anon, authenticated;

create or replace function public.access_unlock(p_staff_id uuid, p_pin text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v record; s public.staff; tok text; until timestamptz;
begin
  if not public.is_cafe() then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  select * into v from public._verify_pin(p_staff_id, p_pin, true);
  if v.err is not null then return jsonb_build_object('ok', false, 'error', v.err); end if;
  select * into s from public.staff where id = v.sid;
  delete from public.access_unlocks where expires_at < now() - interval '1 day';
  delete from public.access_unlocks where token_hash = public._unlock_token_hash();
  tok := encode(gen_random_bytes(24), 'hex');
  until := now() + interval '15 minutes';
  insert into public.access_unlocks (token_hash, user_id, staff_id, staff_name, staff_role, expires_at)
    values (encode(digest(tok, 'sha256'), 'hex'), auth.uid(), s.id, s.name, s.role, until);
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('access_open', s.id, s.name, auth.uid()::text, 'opened the owner areas',
            jsonb_build_object('role', s.role, 'until', until, 'account', public.account_kind()));
  return jsonb_build_object('ok', true, 'token', tok, 'until', until, 'name', s.name, 'role', s.role,
                            'sales', s.role = 'owner' or s.can_see_sales);
end $$;

create or replace function public.access_lock()
returns void language sql security definer set search_path = public, extensions as $$
  delete from public.access_unlocks where token_hash = public._unlock_token_hash() and user_id = auth.uid();
$$;

create or replace function public.access_state()
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare r record; lvl text;
begin
  lvl := public.access_level();
  select * into r from public._unlock_staff();
  return jsonb_build_object(
    'login', public.account_kind(),
    'level', lvl,
    'via', case when lvl is null then null when r.staff_id is not null then 'pin' else 'phone' end,
    'name', r.staff_name, 'role', coalesce(r.staff_role, case when lvl = 'owner' then 'owner' end),
    'until', r.expires_at,
    'sales', public.sales_open(),
    'token_seen', public._unlock_token_hash() is not null);
end $$;
revoke all on function public.access_unlock(uuid, text), public.access_lock(), public.access_state() from public, anon;
grant execute on function public.access_unlock(uuid, text), public.access_lock(), public.access_state() to authenticated;

-- 3) Sales and inventory follow manager mode ------------------------------------------------------
-- (the older per-login unlocks are no longer honoured: they opened every device of the café login at once)
create or replace function public.sales_open()
returns boolean language plpgsql stable security definer set search_path = public, extensions as $$
declare lvl text; r record;
begin
  lvl := public.access_level();
  if lvl = 'owner' then return true; end if;
  if lvl = 'manager' then
    select * into r from public._unlock_staff();
    return coalesce(r.can_see_sales, false);
  end if;
  return false;
end $$;
create or replace function public.sales_unlocked()
returns timestamptz language plpgsql stable security definer set search_path = public, extensions as $$
declare r record;
begin
  if not public.sales_open() then return null; end if;
  select * into r from public._unlock_staff();
  return coalesce(r.expires_at, now() + interval '10 years');
end $$;
create or replace function public.inventory_open()
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select public.is_owner();
$$;
create or replace function public.inventory_unlocked()
returns timestamptz language plpgsql stable security definer set search_path = public, extensions as $$
declare r record;
begin
  if not public.is_owner() then return null; end if;
  select * into r from public._unlock_staff();
  return coalesce(r.expires_at, now() + interval '10 years');
end $$;
create or replace function public._inv_actor()
returns text language sql stable security definer set search_path = public, extensions as $$
  select public._owner_label();
$$;

-- 4) Team: owner areas open, and only owners touch owners ----------------------------------------
create or replace function public.manager_save_staff(p_manager_id uuid, p_manager_pin text,
    p_id uuid, p_name text, p_pin text, p_active boolean, p_role text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v record; u record; lvl text; bootstrap boolean; owners_exist boolean; nid uuid; role_final text;
        old public.staff; managers_left int; msid uuid; msname text;
begin
  lvl := public.access_level();
  bootstrap := not exists (select 1 from public.staff where active and role in ('manager', 'owner'));
  if bootstrap then
    if lvl is null and public.account_kind() is distinct from 'owner' then
      return jsonb_build_object('ok', false, 'error', 'owner_only'); end if;
    msid := null; msname := 'first setup';
  elsif lvl is null then
    return jsonb_build_object('ok', false, 'error', 'owner_only');
  elsif p_manager_id is not null or coalesce(p_manager_pin, '') <> '' then
    select * into v from public._verify_pin(p_manager_id, p_manager_pin, true);   -- an extra approval, if given
    if v.err is not null then return jsonb_build_object('ok', false, 'error', v.err); end if;
    msid := v.sid; msname := v.sname;
  else
    select * into u from public._unlock_staff();
    msid := u.staff_id; msname := public._owner_label();
  end if;
  if coalesce(trim(p_name), '') = '' then return jsonb_build_object('ok', false, 'error', 'missing_name'); end if;
  if p_pin is not null and p_pin <> '' then
    if p_pin !~ '^[0-9]{4,8}$' then return jsonb_build_object('ok', false, 'error', 'bad_pin_format'); end if;
    if public._weak_pin(p_pin) then return jsonb_build_object('ok', false, 'error', 'weak_pin'); end if;
  end if;
  role_final := case when p_role in ('owner', 'manager') then p_role else 'staff' end;
  if bootstrap and role_final = 'staff' then role_final := 'manager'; end if;
  if p_id is not null then
    select * into old from public.staff where id = p_id;
    if old.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  end if;
  owners_exist := exists (select 1 from public.staff where active and role = 'owner');
  if (role_final = 'owner' or old.role = 'owner')
     and not (lvl = 'owner' or bootstrap or (not owners_exist and public.account_kind() = 'owner')) then
    return jsonb_build_object('ok', false, 'error', 'owner_role_only');
  end if;

  if p_id is null then
    if p_pin is null or p_pin = '' then return jsonb_build_object('ok', false, 'error', 'missing_pin'); end if;
    insert into public.staff (name, pin_hash, active, role)
      values (trim(p_name), crypt(p_pin, gen_salt('bf')), coalesce(p_active, true), role_final)
      returning id into nid;
  else
    if old.role in ('manager', 'owner') and old.active and (role_final = 'staff' or not coalesce(p_active, true)) then
      select count(*) into managers_left from public.staff
        where active and role in ('manager', 'owner') and id <> old.id;
      if managers_left = 0 then return jsonb_build_object('ok', false, 'error', 'last_manager'); end if;
    end if;
    update public.staff set
      name = trim(p_name),
      pin_hash = case when p_pin is not null and p_pin <> '' then crypt(p_pin, gen_salt('bf')) else pin_hash end,
      failed_pins = case when p_pin is not null and p_pin <> '' then 0 else failed_pins end,
      locked_until = case when p_pin is not null and p_pin <> '' then null else locked_until end,
      active = coalesce(p_active, active),
      role = role_final,
      can_see_sales = case when role_final = 'manager' then can_see_sales else false end
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

-- the "may open sales" switch for a manager: owners only
create or replace function public.owner_set_sales_access(p_staff_id uuid, p_allowed boolean)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare s public.staff;
begin
  if not public.is_true_owner() then return jsonb_build_object('ok', false, 'error', 'owner_role_only'); end if;
  select * into s from public.staff where id = p_staff_id;
  if s.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if s.role <> 'manager' and coalesce(p_allowed, false) then
    return jsonb_build_object('ok', false, 'error', 'not_manager'); end if;
  update public.staff set can_see_sales = coalesce(p_allowed, false) where id = p_staff_id;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('sales_access', null, public._owner_label(), p_staff_id::text,
            case when coalesce(p_allowed, false) then 'may now open sales: ' else 'can no longer open sales: ' end || s.name,
            jsonb_build_object('allowed', coalesce(p_allowed, false)));
  return jsonb_build_object('ok', true);
end $$;

-- 5) Shifts: open owner areas act directly; otherwise a manager or owner PIN ---------------------
create or replace function public.manager_save_shift(p_manager_id uuid, p_manager_pin text,
    p_entry_id uuid, p_staff_id uuid, p_clock_in timestamptz, p_clock_out timestamptz, p_reason text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v record; u record; old public.time_entries; nid uuid; who text; msid uuid; msname text;
begin
  if public.is_owner() and p_manager_id is null and coalesce(p_manager_pin, '') = '' then
    select * into u from public._unlock_staff();
    msid := u.staff_id; msname := public._owner_label();
  else
    select * into v from public._verify_pin(p_manager_id, p_manager_pin, true);
    if v.err is not null then return jsonb_build_object('ok', false, 'error', v.err); end if;
    msid := v.sid; msname := v.sname;
  end if;
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
      values ('shift_edit', msid, msname, nid::text, trim(p_reason),
        jsonb_build_object('staff_id', old.staff_id, 'staff_name', who,
          'before', jsonb_build_object('clock_in', old.clock_in, 'clock_out', old.clock_out),
          'after',  jsonb_build_object('clock_in', p_clock_in, 'clock_out', p_clock_out)));
  else
    if p_staff_id is null then return jsonb_build_object('ok', false, 'error', 'missing_staff'); end if;
    insert into public.time_entries (staff_id, clock_in, clock_out)
      values (p_staff_id, p_clock_in, p_clock_out) returning id into nid;
    select name into who from public.staff where id = p_staff_id;
    insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
      values ('shift_add', msid, msname, nid::text, trim(p_reason),
        jsonb_build_object('staff_id', p_staff_id, 'staff_name', who,
          'after', jsonb_build_object('clock_in', p_clock_in, 'clock_out', p_clock_out)));
  end if;
  return jsonb_build_object('ok', true, 'id', nid);
end $$;

create or replace function public.manager_delete_shift(p_manager_id uuid, p_manager_pin text,
    p_entry_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v record; u record; old public.time_entries; who text; msid uuid; msname text;
begin
  if public.is_owner() and p_manager_id is null and coalesce(p_manager_pin, '') = '' then
    select * into u from public._unlock_staff();
    msid := u.staff_id; msname := public._owner_label();
  else
    select * into v from public._verify_pin(p_manager_id, p_manager_pin, true);
    if v.err is not null then return jsonb_build_object('ok', false, 'error', v.err); end if;
    msid := v.sid; msname := v.sname;
  end if;
  if coalesce(trim(p_reason), '') = '' then return jsonb_build_object('ok', false, 'error', 'missing_reason'); end if;
  select * into old from public.time_entries where id = p_entry_id;
  if old.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  select name into who from public.staff where id = old.staff_id;
  delete from public.time_entries where id = p_entry_id;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('shift_delete', msid, msname, p_entry_id::text, trim(p_reason),
      jsonb_build_object('staff_id', old.staff_id, 'staff_name', who,
        'before', jsonb_build_object('clock_in', old.clock_in, 'clock_out', old.clock_out)));
  return jsonb_build_object('ok', true);
end $$;

-- 6) Own hours with a team member's PIN; everyone's with a manager or owner PIN -----------------
create or replace function public.hours_report(p_staff_id uuid, p_pin text, p_from timestamptz, p_to timestamptz)
returns setof public.time_entries language plpgsql stable security definer set search_path = public, extensions as $$
declare v record; is_mgr boolean;
begin
  if not public.is_cafe() then return; end if;
  select * into v from public._verify_pin(p_staff_id, p_pin, false);
  if v.err is not null then raise exception 'pin:%', v.err using errcode = 'P0001'; end if;
  select role in ('manager', 'owner') into is_mgr from public.staff where id = v.sid;
  return query
    select * from public.time_entries t
    where t.clock_in >= p_from and t.clock_in < p_to
      and (is_mgr or t.staff_id = v.sid)
    order by t.clock_in;
end $$;

-- 7) Menu photos: the storage service may not pass the device token, so it accepts an open unlock on
--    any device of this login (photos only)
create or replace function public._unlocked_any_device()
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from public.access_unlocks u join public.staff s on s.id = u.staff_id
                  where u.user_id = auth.uid() and u.expires_at > now() and s.active and s.role in ('manager', 'owner'));
$$;
revoke all on function public._unlocked_any_device() from public, anon;
grant execute on function public._unlocked_any_device() to authenticated;
drop policy if exists "menu photos owner write" on storage.objects;
create policy "menu photos owner write" on storage.objects for all to authenticated
  using (bucket_id = 'menu-photos' and ((select public.is_owner()) or (select public._unlocked_any_device())))
  with check (bucket_id = 'menu-photos' and ((select public.is_owner()) or (select public._unlocked_any_device())));

-- 8) Make sure the menu tables enforce their rules: everyone reads (website, TV, POS, room ordering),
--    only open owner areas change them. Harmless if they were already on.
alter table public.menu_categories enable row level security;
alter table public.menu_items enable row level security;

notify pgrst, 'reload schema';
