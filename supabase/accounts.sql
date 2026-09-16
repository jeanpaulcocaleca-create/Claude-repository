-- Canopy OS · The Hanging Garden Café
-- Owner and café accounts: run ONCE in Supabase (SQL Editor -> New query -> paste -> Run).
-- Safe to re-run. Run supabase/authorization.sql and supabase/kitchen-rooms.sql first.
--
-- What this does
--   * Two kinds of login. The "café" login (the one on the shop tablet) reaches the POS,
--     the time clock and the kitchen screen only. The "owner" login reaches everything.
--   * Every login that exists today becomes a café login. Turn your own login into the
--     owner login with:  select public.make_owner('you@example.com');
--   * Sales history opens only after a manager PIN (15 minutes), on any account.
--     A manager on site may unlock it only if the owner switched that on for them.
--   * Menu, TV board, rooms, pickup settings, team changes and menu photos: owner only.
--   * The café login sees today's orders and today's punches only.
--   * Menu changes and sales views land in the approvals log.
--   * If the owner login has a phone code (2FA) enrolled, owner powers need the code.

create extension if not exists pgcrypto;

-- 1) Accounts -----------------------------------------------------------------
create table if not exists public.app_accounts (
  user_id uuid primary key,
  kind text not null check (kind in ('cafe', 'owner')),
  label text,
  created_at timestamptz not null default now()
);
alter table public.app_accounts enable row level security;
revoke all on public.app_accounts from anon, authenticated;
grant select on public.app_accounts to authenticated;
drop policy if exists "see own account" on public.app_accounts;
create policy "see own account" on public.app_accounts
  for select to authenticated using (user_id = auth.uid());

-- every login that exists today is the café tablet login (make_owner upgrades yours)
insert into public.app_accounts (user_id, kind, label)
  select id, 'cafe', coalesce(email, 'café login') from auth.users
  on conflict (user_id) do nothing;

-- 2) Who is asking? -----------------------------------------------------------
-- True when the session carries a verified phone code, or when this login never
-- enrolled one. If the factor table cannot be read, no code is required.
create or replace function public.mfa_ok()
returns boolean language plpgsql stable security definer set search_path = public as $$
declare enrolled boolean := false;
begin
  if coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2' then return true; end if;
  begin
    select exists (select 1 from auth.mfa_factors
                   where user_id = auth.uid() and status = 'verified') into enrolled;
  exception when others then enrolled := false;
  end;
  return not enrolled;
end $$;

create or replace function public.account_kind()
returns text language sql stable security definer set search_path = public as $$
  select case when a.kind = 'owner' and public.mfa_ok() then 'owner'
              when a.kind = 'owner' then 'owner_needs_code'
              else a.kind end
  from public.app_accounts a where a.user_id = auth.uid();
$$;
create or replace function public.is_owner()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.account_kind() = 'owner', false);
$$;
create or replace function public.is_cafe()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.account_kind() in ('cafe', 'owner', 'owner_needs_code'), false);
$$;
revoke all on function public.mfa_ok(), public.account_kind(), public.is_owner(), public.is_cafe() from public, anon;
grant execute on function public.mfa_ok(), public.account_kind(), public.is_owner(), public.is_cafe() to authenticated;

-- Start of today in Monteverde, whatever the server clock says.
create or replace function public.cr_today_start()
returns timestamptz language sql stable as $$
  select (date_trunc('day', now() at time zone 'America/Costa_Rica')) at time zone 'America/Costa_Rica';
$$;
grant execute on function public.cr_today_start() to anon, authenticated;

-- Only runnable from the SQL Editor (never from a page).
create or replace function public.make_owner(p_email text)
returns text language plpgsql security definer set search_path = public as $$
declare uid uuid;
begin
  select id into uid from auth.users where lower(email) = lower(trim(p_email));
  if uid is null then
    return 'No login with that email yet. Create it under Authentication > Users, then run this line again.';
  end if;
  insert into public.app_accounts (user_id, kind, label) values (uid, 'owner', lower(trim(p_email)))
    on conflict (user_id) do update set kind = 'owner', label = excluded.label;
  return 'Owner access is on for ' || lower(trim(p_email));
end $$;
revoke all on function public.make_owner(text) from public, anon, authenticated;

-- 3) Sales behind a PIN ---------------------------------------------------------
alter table public.staff add column if not exists can_see_sales boolean not null default false;
grant select (can_see_sales) on public.staff to authenticated;

create table if not exists public.sales_unlocks (
  user_id uuid primary key,
  staff_id uuid,
  staff_name text,
  expires_at timestamptz not null
);
alter table public.sales_unlocks enable row level security;
revoke all on public.sales_unlocks from anon, authenticated;

create or replace function public.sales_open()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.sales_unlocks
                 where user_id = auth.uid() and expires_at > now());
$$;
revoke all on function public.sales_open() from public, anon;
grant execute on function public.sales_open() to authenticated;

create or replace function public.sales_unlock(p_staff_id uuid, p_pin text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v record; kind text; allowed boolean; until timestamptz;
begin
  kind := public.account_kind();
  if kind is null then return jsonb_build_object('ok', false, 'error', 'no_account'); end if;
  select * into v from public._verify_pin(p_staff_id, p_pin, true);
  if v.err is not null then return jsonb_build_object('ok', false, 'error', v.err); end if;
  select (kind = 'owner') or can_see_sales into allowed from public.staff where id = v.sid;
  if not coalesce(allowed, false) then return jsonb_build_object('ok', false, 'error', 'no_sales_access'); end if;
  until := now() + interval '15 minutes';
  insert into public.sales_unlocks (user_id, staff_id, staff_name, expires_at)
    values (auth.uid(), v.sid, v.sname, until)
    on conflict (user_id) do update set staff_id = excluded.staff_id, staff_name = excluded.staff_name,
                                        expires_at = excluded.expires_at;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('sales_view', v.sid, v.sname, auth.uid()::text, 'opened the sales reports',
            jsonb_build_object('account', kind, 'until', until));
  return jsonb_build_object('ok', true, 'until', until);
end $$;

create or replace function public.sales_lock()
returns void language sql security definer set search_path = public as $$
  delete from public.sales_unlocks where user_id = auth.uid();
$$;

create or replace function public.sales_unlocked()
returns timestamptz language sql stable security definer set search_path = public as $$
  select expires_at from public.sales_unlocks where user_id = auth.uid() and expires_at > now();
$$;

-- Owner switches "may unlock sales" on or off for a manager.
create or replace function public.owner_set_sales_access(p_staff_id uuid, p_allowed boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare s public.staff;
begin
  if not public.is_owner() then return jsonb_build_object('ok', false, 'error', 'owner_only'); end if;
  select * into s from public.staff where id = p_staff_id;
  if s.id is null then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;
  if s.role <> 'manager' and coalesce(p_allowed, false) then
    return jsonb_build_object('ok', false, 'error', 'not_manager'); end if;
  update public.staff set can_see_sales = coalesce(p_allowed, false) where id = p_staff_id;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('sales_access', null, 'owner login', p_staff_id::text,
            case when coalesce(p_allowed, false) then 'may now open sales: ' else 'can no longer open sales: ' end || s.name,
            jsonb_build_object('allowed', coalesce(p_allowed, false)));
  return jsonb_build_object('ok', true);
end $$;

revoke all on function public.sales_unlock(uuid, text), public.sales_lock(), public.sales_unlocked(),
                       public.owner_set_sales_access(uuid, boolean) from public, anon;
grant execute on function public.sales_unlock(uuid, text), public.sales_lock(), public.sales_unlocked(),
                          public.owner_set_sales_access(uuid, boolean) to authenticated;

-- 4) Hours report with a PIN (café login) ------------------------------------
-- A manager PIN returns everyone's hours; a staff PIN returns that person's own hours.
create or replace function public.hours_report(p_staff_id uuid, p_pin text, p_from timestamptz, p_to timestamptz)
returns setof public.time_entries language plpgsql stable security definer set search_path = public as $$
declare v record; is_mgr boolean;
begin
  if not public.is_cafe() then return; end if;
  select * into v from public._verify_pin(p_staff_id, p_pin, false);
  if v.err is not null then raise exception 'pin:%', v.err using errcode = 'P0001'; end if;
  select role = 'manager' into is_mgr from public.staff where id = v.sid;
  return query
    select * from public.time_entries t
    where t.clock_in >= p_from and t.clock_in < p_to
      and (is_mgr or t.staff_id = v.sid)
    order by t.clock_in;
end $$;
revoke all on function public.hours_report(uuid, text, timestamptz, timestamptz) from public, anon;
grant execute on function public.hours_report(uuid, text, timestamptz, timestamptz) to authenticated;

-- 5) Team changes: owner login only ------------------------------------------
create or replace function public.manager_save_staff(p_manager_id uuid, p_manager_pin text,
    p_id uuid, p_name text, p_pin text, p_active boolean, p_role text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v record; bootstrap boolean; nid uuid; role_final text; old public.staff;
        managers_left int; msid uuid; msname text;
begin
  if not public.is_owner() then return jsonb_build_object('ok', false, 'error', 'owner_only'); end if;
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

-- 6) Menu changes go to the approvals log ------------------------------------
create or replace function public.audit_menu()
returns trigger language plpgsql security definer set search_path = public as $$
declare who text; what text;
begin
  who := coalesce(auth.jwt() ->> 'email', 'owner login');
  if tg_op = 'UPDATE' and row(old.name, old.price_crc, old.available, old.description, old.category_id)
       is not distinct from row(new.name, new.price_crc, new.available, new.description, new.category_id) then
    return new;  -- photo, star, color or quick-tab changes are not worth a log line
  end if;
  what := case tg_op when 'INSERT' then 'added ' || new.name
                     when 'DELETE' then 'removed ' || old.name
                     else 'changed ' || new.name end;
  insert into public.audit_log (action, manager_id, manager_name, target_id, summary, details)
    values ('menu_change', null, who, coalesce(new.id::text, old.id::text), what,
      case when tg_op = 'UPDATE' then jsonb_build_object(
        'before', jsonb_build_object('name', old.name, 'price_crc', old.price_crc, 'available', old.available),
        'after',  jsonb_build_object('name', new.name, 'price_crc', new.price_crc, 'available', new.available))
      when tg_op = 'INSERT' then jsonb_build_object('price_crc', new.price_crc)
      else jsonb_build_object('price_crc', old.price_crc) end);
  return coalesce(new, old);
end $$;
drop trigger if exists menu_items_audit on public.menu_items;
create trigger menu_items_audit after insert or update or delete on public.menu_items
  for each row execute function public.audit_menu();

-- 7) What the owner page can ask about its own session ------------------------
create or replace function public.security_status()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare enrolled boolean := null;
begin
  begin
    select exists (select 1 from auth.mfa_factors where user_id = auth.uid() and status = 'verified') into enrolled;
  exception when others then enrolled := null;
  end;
  return jsonb_build_object(
    'kind', public.account_kind(),
    'aal', coalesce(auth.jwt() ->> 'aal', 'aal1'),
    'code_enrolled', enrolled,
    'code_enforced', enrolled is not null,
    'sales_until', public.sales_unlocked());
end $$;
revoke all on function public.security_status() from public, anon;
grant execute on function public.security_status() to authenticated;

-- 8) Table rules ---------------------------------------------------------------
do $$ declare p record; begin
  for p in select tablename, policyname from pg_policies
           where schemaname = 'public'
             and tablename in ('staff', 'time_entries', 'orders', 'order_items', 'audit_log',
                               'menu_categories', 'menu_items', 'board_settings', 'board_group_slides',
                               'app_settings', 'rooms', 'chat_questions') loop
    execute format('drop policy if exists %I on public.%I', p.policyname, p.tablename);
  end loop;
end $$;

-- team list: both logins (names and roles only; PIN hashes are never readable)
create policy "staff read" on public.staff for select to authenticated using ((select public.is_cafe()));

-- punches: café login sees who is in and today's punches; owner sees all
create policy "time entries read" on public.time_entries for select to authenticated
  using ((select public.is_owner())
         or ((select public.is_cafe()) and (clock_out is null or clock_in >= public.cr_today_start())));

-- orders: today for the café login; older ones only while sales are unlocked
create policy "orders read" on public.orders for select to authenticated
  using ((select public.is_cafe()) and (created_at >= public.cr_today_start() or (select public.sales_open())));
create policy "orders add" on public.orders for insert to authenticated with check ((select public.is_cafe()));
create policy "orders progress" on public.orders for update to authenticated
  using ((select public.is_cafe())) with check ((select public.is_cafe()));
create policy "order items read" on public.order_items for select to authenticated
  using (exists (select 1 from public.orders o where o.id = order_id));
create policy "order items add" on public.order_items for insert to authenticated with check ((select public.is_cafe()));

-- approvals log: owner only
create policy "audit read" on public.audit_log for select to authenticated using ((select public.is_owner()));

-- menu: everyone reads (website, TV, room ordering); only the owner changes it
create policy "menu categories read" on public.menu_categories for select to anon, authenticated using (true);
create policy "menu categories owner write" on public.menu_categories for all to authenticated
  using ((select public.is_owner())) with check ((select public.is_owner()));
create policy "menu items read" on public.menu_items for select to anon, authenticated using (true);
create policy "menu items owner write" on public.menu_items for all to authenticated
  using ((select public.is_owner())) with check ((select public.is_owner()));

-- TV board, combined slides, pickup settings: everyone reads, owner writes
create policy "board settings read" on public.board_settings for select to anon, authenticated using (true);
create policy "board settings owner write" on public.board_settings for all to authenticated
  using ((select public.is_owner())) with check ((select public.is_owner()));
create policy "group slides read" on public.board_group_slides for select to anon, authenticated using (true);
create policy "group slides owner write" on public.board_group_slides for all to authenticated
  using ((select public.is_owner())) with check ((select public.is_owner()));
create policy "settings read" on public.app_settings for select to anon, authenticated using (true);
create policy "settings owner write" on public.app_settings for all to authenticated
  using ((select public.is_owner())) with check ((select public.is_owner()));

-- rooms: both logins read (the POS shows room numbers); owner changes them
create policy "rooms read" on public.rooms for select to authenticated using ((select public.is_cafe()));
create policy "rooms owner write" on public.rooms for all to authenticated
  using ((select public.is_owner())) with check ((select public.is_owner()));

-- website questions: visitors write, owner reads
create policy "visitors can ask" on public.chat_questions for insert to anon, authenticated with check (true);
create policy "owner reads questions" on public.chat_questions for select to authenticated using ((select public.is_owner()));

-- menu photos (storage bucket menu-photos): everyone views, owner uploads
do $$ declare p record; begin
  for p in select policyname from pg_policies
           where schemaname = 'storage' and tablename = 'objects'
             and (coalesce(qual, '') ilike '%menu-photos%' or coalesce(with_check, '') ilike '%menu-photos%') loop
    execute format('drop policy if exists %I on storage.objects', p.policyname);
  end loop;
end $$;
create policy "menu photos read" on storage.objects for select to anon, authenticated
  using (bucket_id = 'menu-photos');
create policy "menu photos owner write" on storage.objects for all to authenticated
  using (bucket_id = 'menu-photos' and (select public.is_owner()))
  with check (bucket_id = 'menu-photos' and (select public.is_owner()));

notify pgrst, 'reload schema';
