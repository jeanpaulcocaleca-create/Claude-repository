-- Hanging Garden Café · access and PINs
-- Run ONCE in Supabase: SQL Editor -> New query -> paste -> Run. Safe to run again.
-- Run supabase/authorization.sql and supabase/accounts.sql first (already done on this project).
--
-- What changes
--   * The owner login manages the team and shifts directly. It no longer needs a manager's PIN,
--     so forgetting every PIN can never lock the owner out again: the owner resets PINs from Time clock.
--     When a manager PIN is given anyway, it is still checked and logged as before.
--   * PINs that are too easy to guess (0000, 1111, 1234, 4321...) are refused.
--   * The owner login opens the Sales reports directly, like it already opens Inventory.
--     The café login (the tablet) still needs a manager PIN for 15 minutes of access.
--   * One rescue line for a lost phone (2FA) code, runnable only from this SQL editor:
--       select public.owner_reset_phone_code('owner@email');

create extension if not exists pgcrypto;

-- 0) Helpers ------------------------------------------------------------------
-- Which owner login acted, for the approvals log ("owner login · name@email").
create or replace function public._owner_label()
returns text language plpgsql stable security definer set search_path = public as $$
declare em text;
begin
  begin
    select email into em from auth.users where id = auth.uid();
  exception when others then em := null;
  end;
  return 'owner login' || coalesce(' · ' || em, '');
end $$;
revoke all on function public._owner_label() from public, anon, authenticated;

-- PINs anyone would guess: one repeated digit, runs (1234, 4321, 7890), repeated pairs (1212, 1122),
-- keypad lines (2580, 1470, 3690...), years (1900-2030) and the usual favourites.
create or replace function public._weak_pin(p text)
returns boolean language sql immutable as $$
  select p ~ '^(\d)\1+$'
      or '01234567890123456789' like '%' || p || '%'
      or '98765432109876543210' like '%' || p || '%'
      or p ~ '^(\d\d)\1+$'
      or p ~ '^(\d)\1(\d)\2$'
      or p in ('2580','0852','1470','0741','3690','0963','1357','7531','2468','8642','1004','2000','2001','6969','1010','1020','1230','0007','1313','4545','1122','1212','0101','2020','2022','2023','2024','2025','2026')
      or (length(p) = 4 and p::int between 1900 and 2030);
$$;
grant execute on function public._weak_pin(text) to authenticated;

-- 1) Team: owner login acts directly ------------------------------------------
create or replace function public.manager_save_staff(p_manager_id uuid, p_manager_pin text,
    p_id uuid, p_name text, p_pin text, p_active boolean, p_role text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v record; bootstrap boolean; nid uuid; role_final text; old public.staff;
        managers_left int; msid uuid; msname text;
begin
  if not public.is_owner() then return jsonb_build_object('ok', false, 'error', 'owner_only'); end if;
  bootstrap := not exists (select 1 from public.staff where active and role = 'manager');
  if bootstrap then
    msid := null; msname := 'first setup';
  elsif p_manager_id is null and coalesce(p_manager_pin, '') = '' then
    msid := null; msname := public._owner_label();                      -- the owner needs nobody's approval
  else
    select * into v from public._verify_pin(p_manager_id, p_manager_pin, true);
    if v.err is not null then return jsonb_build_object('ok', false, 'error', v.err); end if;
    msid := v.sid; msname := v.sname;
  end if;
  if coalesce(trim(p_name), '') = '' then return jsonb_build_object('ok', false, 'error', 'missing_name'); end if;
  if p_pin is not null and p_pin <> '' then
    if p_pin !~ '^[0-9]{4,8}$' then return jsonb_build_object('ok', false, 'error', 'bad_pin_format'); end if;
    if public._weak_pin(p_pin) then return jsonb_build_object('ok', false, 'error', 'weak_pin'); end if;
  end if;
  role_final := case when bootstrap then 'manager' when p_role = 'manager' then 'manager' else 'staff' end;

  if p_id is null then
    if p_pin is null or p_pin = '' then return jsonb_build_object('ok', false, 'error', 'missing_pin'); end if;
    insert into public.staff (name, pin_hash, active, role)
      values (trim(p_name), crypt(p_pin, gen_salt('bf')), coalesce(p_active, true), role_final)
      returning id into nid;
  else
    select * into old from public.staff where id = p_id;
    if old.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
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

-- 2) Shifts: the owner login edits directly; the café login still needs a manager PIN ----
create or replace function public.manager_save_shift(p_manager_id uuid, p_manager_pin text,
    p_entry_id uuid, p_staff_id uuid, p_clock_in timestamptz, p_clock_out timestamptz, p_reason text)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v record; old public.time_entries; nid uuid; who text; msid uuid; msname text;
begin
  if public.is_owner() and p_manager_id is null and coalesce(p_manager_pin, '') = '' then
    msid := null; msname := public._owner_label();
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
declare v record; old public.time_entries; who text; msid uuid; msname text;
begin
  if public.is_owner() and p_manager_id is null and coalesce(p_manager_pin, '') = '' then
    msid := null; msname := public._owner_label();
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

-- 3) Sales: the owner login is always in; the café login unlocks with a manager PIN ----
create or replace function public.sales_open()
returns boolean language sql stable security definer set search_path = public as $$
  select public.is_owner()
      or exists (select 1 from public.sales_unlocks where user_id = auth.uid() and expires_at > now());
$$;
create or replace function public.sales_unlocked()
returns timestamptz language sql stable security definer set search_path = public as $$
  select case when public.is_owner() then now() + interval '10 years'
              else (select expires_at from public.sales_unlocks where user_id = auth.uid() and expires_at > now()) end;
$$;

-- 4) Lost phone code: only from the SQL editor, never from a page --------------------
create or replace function public.owner_reset_phone_code(p_email text)
returns text language plpgsql security definer set search_path = public as $$
declare uid uuid; n int;
begin
  select id into uid from auth.users where lower(email) = lower(trim(p_email));
  if uid is null then return 'No login with that email.'; end if;
  begin
    delete from auth.mfa_factors where user_id = uid;
    get diagnostics n = row_count;
  exception when others then
    return 'This editor may not remove factors here (' || sqlerrm || '). Do it in the dashboard instead: Authentication > Users > the owner > Multi-factor, remove the factor.';
  end;
  return 'Phone code removed (' || n || ' factor(s)). Sign in with the password alone, then turn the code on again from Home.';
end $$;
revoke all on function public.owner_reset_phone_code(text) from public, anon, authenticated;

notify pgrst, 'reload schema';
