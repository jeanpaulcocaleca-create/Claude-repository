-- Migration 0039 (Proveedores, D-067): «Recibe en este aparato». An employee on shift receives without any PIN in the
-- receive call, through a work session the server checks at every use: this person typed their own PIN (turno_aqui, or
-- the POS's «¿Quién cobra?» on the same device, turno_desde_caja) on this device sign-in during their open shift. It stops
-- working at the clock-out, after 16 hours, on another login, on another device sign-in (until turno_estado moves it and
-- rotates the token), on a PIN change or a deactivation, and 15 minutes after the PIN or the last delivery recorded with it
-- (owner, 2026-11-07: the person types their PIN again; nobody receives as the last person who identified on a shared
-- device); one receiver per device sign-in. What an employee may do:
-- receive (never more than pending, prices never booked), report extras and «no llega el resto»; nothing else (the
-- delivery recorded and its stock moves cannot be changed or deleted from the café login).
begin;
insert into public.vendors (id, name) values ('5b000000-0000-4000-8000-000000051301', 'Lácteos Monteverde');
insert into public.stock_items (id, name, unit, pack_qty, cost_per_pack) values ('5a000000-0000-4000-8000-000000051301', 'Leche', 'unit', 1, 1000),
                                                                              ('5a000000-0000-4000-8000-000000051302', 'Queso', 'g', 500, 1750);
insert into public.vendor_items (id, vendor_id, item_id, pack_label, pack_qty, usual_price) values
  ('5c000000-0000-4000-8000-000000051301', '5b000000-0000-4000-8000-000000051301', '5a000000-0000-4000-8000-000000051301', 'caja de 12', 12, 12000),
  ('5c000000-0000-4000-8000-000000051302', '5b000000-0000-4000-8000-000000051301', '5a000000-0000-4000-8000-000000051302', 'bloque de 2 kg', 2000, 7000);
insert into public.purchase_orders (id, vendor_id, status) values ('9a000000-0000-4000-8000-000000051309', '5b000000-0000-4000-8000-000000051301', 'draft');
insert into public.purchase_lines (po_id, item_id, packs, qty, unit_cost) values ('9a000000-0000-4000-8000-000000051309', '5a000000-0000-4000-8000-000000051301', 1, 12, 1000);
-- (read as the test superuser: a café device without the owner areas sees no order table; the page gets them from proveedor_pedido)
create function test.v513(o text) returns int language sql security definer as $$ select version from public.purchase_orders where id = o::uuid $$;
create function test.line513(o text, p int default 1) returns text language sql security definer as $$ select id::text from public.purchase_lines where po_id = o::uuid and pos = p $$;
create function test.why513(tok text) returns text language sql as $$
  select coalesce((public.turno_estado(array[tok]) #>> '{sessions,0,why}'), 'ok') $$;
-- management orders 10 boxes of milk and 4 blocks of cheese
select test.login('cafe'); select test.session('dev-513-m'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051301', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051301","packs":10},
         {"vendor_item_id":"5c000000-0000-4000-8000-000000051302","packs":4}]', null, '9a000000-0000-4000-8000-000000051301') ->> 'ok' as c1 \gset
reset role;

-- 1) «Estoy en turno aquí» --------------------------------------------------------------------------------------------------
select test.login('accountant', 'aal2'); set role authenticated;
select test.eq(public.turno_aqui(test.staff('luis'), '5284') ->> 'error', 'no_account', '1 not from the accountant''s login');
select test.login('cafe'); set role authenticated;
select test.eq(public.turno_aqui(test.staff('luis'), '5284', null, true), '{"ok":false,"error":"no_session","why":"no_session"}'::jsonb,
               '1 not without a device sign-in (no session id): never a shared session');
select test.session('dev-513-a');
select test.eq(public.turno_aqui(test.staff('luis'), '0000'), '{"ok":false,"error":"not_clocked_in"}'::jsonb, '1 Luis is not clocked in: said before any PIN is tried');
reset role;
select test.eq((select failed_pins from public.staff where id = test.staff('luis')), 0, '1 so the wrong PIN was not counted');
insert into public.time_entries (staff_id, clock_in) values (test.staff('marta'), now() - interval '20 hours');
set role authenticated;
select test.eq(public.turno_aqui(test.staff('marta'), '6173', null, true) ->> 'error', 'stale_shift', '1 Marta''s shift open since yesterday (20 h): «avise a un encargado», no punch');
select test.eq(public.turno_aqui(test.staff('luis'), '9999', null, true) ->> 'error', 'bad_pin', '1 a wrong PIN with «Marcar entrada y empezar»');
reset role;
select test.eq((select failed_pins from public.staff where id = test.staff('luis')) || ' ' || (select count(*) from public.time_entries where staff_id = test.staff('luis')), '1 0',
               '1 counted, and no clock-in');
set role authenticated;
select test.eq(public.turno_aqui(test.staff('luis'), '6173', null, true) ->> 'error', 'bad_pin', '1 another person''s PIN never opens Luis''s session');
select public.turno_aqui(test.staff('luis'), '5284', 'Bodega', true) as t1 \gset
select test.eq((:'t1'::jsonb) ->> 'ok' || ' ' || ((:'t1'::jsonb) ->> 'staff_name') || ' ' || ((:'t1'::jsonb) ->> 'clocked_in') || ' ' || ((:'t1'::jsonb) ->> 'token' ~ '^[0-9a-f]{64}$'),
               'true Luis true true', '1 his own PIN: clocked in and a session for this device (a 32-byte token, returned once)');
select (:'t1'::jsonb) ->> 'token' as tok_luis \gset
reset role;
select test.eq((select how || ' ' || station || ' ' || (session_id = 'dev-513-a') || ' ' || (pin_fp = encode(extensions.digest(s.pin_hash, 'sha256'), 'hex'))
                       || ' ' || (token_hash = encode(extensions.digest(:'tok_luis', 'sha256'), 'hex')) || ' ' || (expires_at = e.clock_in + interval '16 hours')
                  from public.work_sessions w join public.staff s on s.id = w.staff_id join public.time_entries e on e.id = w.time_entry_id where w.staff_id = test.staff('luis')),
               'pin Bodega true true true true', '1 bound to this sign-in, his PIN as it is now, his open shift (16 hours); only the token''s sha256 is kept');
select test.eq((select count(*)::int from public.audit_log where action = 'work_session_start' and details ->> 'session_tag' ~ '^s[0-9a-f]{7}$'
                  and details::text !~ 'dev-513-a' and details::text !~ :'tok_luis'), 1, '1 logged with a tag of the sign-in, never its id or the token');
update public.staff set locked_until = now() + interval '5 minutes' where id = test.staff('marta');
set role authenticated;
select test.eq(public.turno_aqui(test.staff('marta'), '6173', null, true) ->> 'error', 'stale_shift', '1 (the stale shift is said first)');
reset role;
update public.time_entries set clock_out = now() where staff_id = test.staff('marta');
set role authenticated;
select test.eq(public.turno_aqui(test.staff('marta'), '6173', null, true) ->> 'error', 'pin_locked', '1 a PIN locked by wrong tries: «pin_locked» (never «locked»)');
reset role;
update public.staff set locked_until = null where id = test.staff('marta');

-- 2) the employee receives without a PIN ---------------------------------------------------------------------------------
set role authenticated;
select test.eq(public.proveedor_pedido('9a000000-0000-4000-8000-000000051301', :'tok_luis') ->> 'mode', 'receive', '2 Luis reads the order in receive mode');
select test.eq(public.proveedor_pedido('9a000000-0000-4000-8000-000000051309', :'tok_luis') ->> 'error', 'not_found', '2 not a draft order');
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051309', '7e000000-0000-4000-8000-000000051309', 1, '[]', :'tok_luis') ->> 'error', 'not_found',
               '2 and cannot receive it');
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051301', '7e000000-0000-4000-8000-000000051301', test.v513('9a000000-0000-4000-8000-000000051301'), '[]') ->> 'error',
               'locked', '2 without his session and without the owner areas: «locked»');
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051301', '7e000000-0000-4000-8000-000000051301', test.v513('9a000000-0000-4000-8000-000000051301'), '[]', 'abc'),
               '{"ok":false,"error":"no_session","why":"unknown"}'::jsonb, '2 a token that is no session: «no_session»');
-- 6 of 10 boxes, 12 boxes reported for the cheese (4 ordered), a price seen on the invoice
select public.proveedor_recibir('9a000000-0000-4000-8000-000000051301', '7e000000-0000-4000-8000-000000051301', test.v513('9a000000-0000-4000-8000-000000051301'),
         jsonb_build_array(jsonb_build_object('line_id', test.line513('9a000000-0000-4000-8000-000000051301', 1), 'packs', 6, 'pack_price', 12900),
                           jsonb_build_object('line_id', test.line513('9a000000-0000-4000-8000-000000051301', 2), 'packs', 6)),
         :'tok_luis', false, 'F-77', 'Una caja golpeada') as r1 \gset
select test.eq((select string_agg(k, ' ' order by k collate "C") from jsonb_object_keys(:'r1'::jsonb) k),
               'close_requested extra_reported fresh_until lines observed_diffs ok receipt_id short status version', '2 his answer carries no money (exactly these keys; fresh_until: until when his PIN counts)');
select test.eq((:'r1'::jsonb) ->> 'status' || ' ' || ((:'r1'::jsonb) #>> '{extra_reported,0,packs}') || ' ' || ((:'r1'::jsonb) #>> '{observed_diffs,0,observed_pack_price}'),
               'partially_received 2.0000 12900.00', '2 received; 2 blocks of cheese beyond the order reported, the price he saw listed');
reset role;
select test.eq((select on_hand from public.stock_items where id = '5a000000-0000-4000-8000-000000051301') || ' ' || (select on_hand from public.stock_items where id = '5a000000-0000-4000-8000-000000051302'),
               '72.0000 8000.0000', '2 stock: 6 boxes of milk, and only the 4 blocks of cheese ordered (the extras are never booked by an employee)');
select test.eq((select string_agg(coalesce(unit_cost::text, '-') || ' ' || coalesce(observed_pack_price::text, '-') || ' ' || coalesce(extra_reported_packs::text, '-'), ' | ' order by pack_qty)
                  from public.purchase_receipt_lines where receipt_id = '7e000000-0000-4000-8000-000000051301'),
               '1000.000000 12900.00 - | 3.500000 - 2.0000', '2 booked at the expected prices; what he saw and the extras kept apart for the manager');
select test.eq((select cost_per_pack from public.stock_items where id = '5a000000-0000-4000-8000-000000051301'), 1000::numeric, '2 the item''s price is never touched by an employee');
select test.eq((select by_name || ' ' || (staff_id = test.staff('luis')) || ' ' || (work_session_id is not null) || ' ' || invoice_no || ' ' || note || ' ' || close_requested
                  from public.purchase_receipts where id = '7e000000-0000-4000-8000-000000051301'), 'Luis (en turno) true true F-77 Una caja golpeada false',
               '2 the delivery says who received it, through which session');
select test.eq((select manager_name || ' ' || (details ->> 'station') || ' ' || (details ->> 'shared_device') || ' ' || (details ->> 'session_tag' ~ '^s[0-9a-f]{7}$')
                  from public.audit_log where action = 'stock_receive' and details ->> 'receipt_id' = '7e000000-0000-4000-8000-000000051301'),
               'Luis (en turno) Bodega false true', '2 the log: who, where, a tag of the sign-in, one person on this login');
-- the delivery is written once: the café login, with Luis's session on it, has no way to change or remove it by hand
select (select md5(r::text) from public.purchase_receipts r where r.id = '7e000000-0000-4000-8000-000000051301') as rc513,
       (select count(*) || ':' || md5(string_agg(m::text, '|' order by m.id)) from public.stock_moves m where m.receipt_id = '7e000000-0000-4000-8000-000000051301') as mv513 \gset
set role authenticated;
select test.throws($$delete from public.purchase_receipts where id = '7e000000-0000-4000-8000-000000051301'$$, 'permission denied',
                   '2 the café login (Luis on shift) cannot delete the delivery he recorded');
select test.throws($$update public.purchase_receipts set total_crc = 0, lines = 0, note = 'nada' where id = '7e000000-0000-4000-8000-000000051301'$$, 'permission denied',
                   '2 nor change it');
select test.throws($$delete from public.stock_moves where receipt_id = '7e000000-0000-4000-8000-000000051301'$$, 'permission denied',
                   '2 nor delete its stock moves');
select test.throws($$update public.stock_moves set qty = 0 where receipt_id = '7e000000-0000-4000-8000-000000051301'$$, 'permission denied',
                   '2 nor change them');
reset role;
select test.eq((select md5(r::text) from public.purchase_receipts r where r.id = '7e000000-0000-4000-8000-000000051301') || ' '
               || (select count(*) || ':' || md5(string_agg(m::text, '|' order by m.id)) from public.stock_moves m where m.receipt_id = '7e000000-0000-4000-8000-000000051301'),
               :'rc513' || ' ' || :'mv513', '2 the delivery and its 2 moves are exactly as recorded');
select test.eq(split_part(:'mv513', ':', 1), '2', '2 (its 2 moves: milk and cheese)');
set role authenticated;
-- «Avisar que no llega el resto»: only a request
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051301', '7e000000-0000-4000-8000-000000051302', test.v513('9a000000-0000-4000-8000-000000051301'),
                 '[]', :'tok_luis', true) ->> 'error', 'locked', '2 an employee cannot close an order with nothing delivered');
select public.proveedor_recibir('9a000000-0000-4000-8000-000000051301', '7e000000-0000-4000-8000-000000051302', test.v513('9a000000-0000-4000-8000-000000051301'),
         jsonb_build_array(jsonb_build_object('line_id', test.line513('9a000000-0000-4000-8000-000000051301', 1), 'packs', 1)), :'tok_luis', true) as r2 \gset
select test.eq((:'r2'::jsonb) ->> 'status' || ' ' || ((:'r2'::jsonb) ->> 'close_requested'), 'partially_received true',
               '2 one more box and «no llega el resto»: the order stays open, the request is recorded');
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051301', '7e000000-0000-4000-8000-000000051303', test.v513('9a000000-0000-4000-8000-000000051301'),
                 jsonb_build_array(jsonb_build_object('line_id', test.line513('9a000000-0000-4000-8000-000000051301', 1), 'packs', 9)), :'tok_luis') #>> '{extra_reported,0,packs}',
               '6.0000', '2 9 boxes where 3 are pending: 3 booked, 6 reported');
select test.unlock(test.staff('ana'), '4826');
select test.eq(public.proveedor_pedido('9a000000-0000-4000-8000-000000051301') #>> '{order,status}', 'received', '2 (with a manager''s unlock on the device, his token still wins in the reads)');
select test.login('cafe'); select test.session('dev-513-a'); set role authenticated;

-- 3) when the session stops working ---------------------------------------------------------------------------------------
select test.eq(test.why513(:'tok_luis'), 'ok', '3 Luis''s session is good on this device');
select test.login('owner'); select test.session('dev-513-a');
select test.eq(test.why513(:'tok_luis'), 'other_login', '3 not on another login (even with the same sign-in id)');
select test.login('cafe'); select test.session('dev-513-b');
select test.eq(test.why513(:'tok_luis'), 'in_use_elsewhere', '3 another sign-in of the café login while it was used a moment ago: not moved');
reset role;
update public.work_sessions set last_used_at = now() - interval '3 minutes' where staff_id = test.staff('luis');
set role authenticated;
select public.turno_estado(array[:'tok_luis', 'nada']) as st \gset
select test.eq((:'st'::jsonb) #>> '{sessions,0,ok}' || ' ' || ((:'st'::jsonb) #>> '{sessions,0,token}' ~ '^[0-9a-f]{64}$') || ' ' || ((:'st'::jsonb) #>> '{sessions,0,token}' <> :'tok_luis')
               || ' ' || ((:'st'::jsonb) #>> '{sessions,1,i}') || ' ' || ((:'st'::jsonb) #>> '{sessions,1,why}'), 'true true true 1 unknown',
               '3 after a sign-out and sign-in on the same device: turno_estado moves it and gives a new token (each token by its place)');
select (:'st'::jsonb) #>> '{sessions,0,token}' as tok_luis2 \gset
select test.eq(test.why513(:'tok_luis'), 'unknown', '3 the old token stops working (a copy of the device''s storage is no use)');
select test.eq(test.why513(:'tok_luis2'), 'ok', '3 the new one works here');
select test.login('cafe'); select test.session('dev-513-a');
select test.eq(test.why513(:'tok_luis2'), 'in_use_elsewhere', '3 and on the first sign-in it is now «moved», refused while just used');
reset role;
insert into public.audit_log (action, target_id, at) select 'work_session_rebound', w.id::text, now() - interval '10 minutes' from public.work_sessions w, generate_series(1, 5)
 where w.staff_id = test.staff('luis') and w.ended_at is null;
update public.work_sessions set last_used_at = now() - interval '3 minutes' where staff_id = test.staff('luis');
set role authenticated;
select test.eq(test.why513(:'tok_luis2'), 'too_many_rebinds', '3 at most 6 moves in an hour');
reset role;
-- clock-out, a stale shift, a new PIN, a deactivation
select test.login('cafe'); select test.session('dev-513-b'); set role authenticated;
select test.eq(public.clock_punch(test.staff('luis'), '5284') ->> 'action', 'out', '3 (Luis clocks out on the Reloj)');
select test.eq(test.why513(:'tok_luis2'), 'ended', '3 the clock-out ends his session');
reset role;
select test.eq((select ended_how from public.work_sessions where staff_id = test.staff('luis') and session_id = 'dev-513-b'), 'clock_out', '3 ended by the clock-out (kept, never deleted)');
set role authenticated;
select test.turno(test.staff('luis'), '5284') as tok_luis3 \gset
reset role;
update public.time_entries set clock_in = now() - interval '17 hours' where staff_id = test.staff('luis') and clock_out is null;
set role authenticated;
select test.eq(test.why513(:'tok_luis3'), 'not_on_shift', '3 a shift open for more than 16 hours carries no session');
reset role;
update public.time_entries set clock_in = now() where staff_id = test.staff('luis') and clock_out is null;
update public.work_sessions set pin_fp = 'otro' where token_hash = encode(extensions.digest(:'tok_luis3', 'sha256'), 'hex');
set role authenticated;
select test.eq(test.why513(:'tok_luis3'), 'pin_changed', '3 checked at every use: a different PIN than at issue');
reset role;
update public.work_sessions w set pin_fp = encode(extensions.digest(s.pin_hash, 'sha256'), 'hex') from public.staff s
 where s.id = w.staff_id and w.token_hash = encode(extensions.digest(:'tok_luis3', 'sha256'), 'hex');
update public.staff set pin_hash = extensions.crypt('2468', extensions.gen_salt('bf')) where id = test.staff('luis');
select test.eq((select ended_how from public.work_sessions where token_hash = encode(extensions.digest(:'tok_luis3', 'sha256'), 'hex')), 'pin_changed',
               '3 a new PIN ends his sessions at once');
select test.login('cafe'); select test.session('dev-513-c'); set role authenticated;
select test.turno(test.staff('marta'), '6173') as tok_marta \gset
reset role;
update public.staff set active = false where id = test.staff('marta');
select test.eq((select ended_how from public.work_sessions where staff_id = test.staff('marta')), 'inactive', '3 deactivating someone ends theirs');
update public.work_sessions set ended_at = null, ended_how = null where staff_id = test.staff('marta');
set role authenticated;
select test.eq(test.why513(:'tok_marta'), 'inactive', '3 and the check refuses an inactive person anyway');
reset role;
update public.staff set active = true where id = test.staff('marta');
update public.work_sessions set ended_at = now(), ended_how = 'inactive' where staff_id = test.staff('marta') and ended_at is null;

-- 4) one receiver per device sign-in; «Salir de este aparato»; the POS's «¿Quién cobra?» -----------------------------------
select test.login('cafe'); select test.session('dev-513-d'); set role authenticated;
select test.turno(test.staff('ana'), '4826', 'Caja') as tok_ana \gset
select public.turno_aqui(test.staff('marta'), '6173', 'Caja') ->> 'ok' as m1 \gset
select test.eq(:'m1' || ' ' || test.why513(:'tok_ana'), 'true ended', '4 Marta identifies on the same device: Ana''s session there ends (one receiver per sign-in)');
reset role;
select test.eq((select ended_how from public.work_sessions where token_hash = encode(extensions.digest(:'tok_ana', 'sha256'), 'hex')), 'replaced', '4 «replaced»');
select test.eq((select count(*)::int from public.work_sessions where session_id = 'dev-513-d' and ended_at is null), 1, '4 one live session on that sign-in');
select (select encode(extensions.digest(gen_random_uuid()::text, 'sha256'), 'hex')) as dummy \gset
select test.login('owner'); set role authenticated;
select test.eq(public.turno_terminar(:'tok_ana'), '{"ok":true}'::jsonb, '4 an ended token: nothing to do');
select test.login('cafe'); select test.session('dev-513-d'); set role authenticated;
select (select x.token from (select test.turno(test.staff('ana'), '4826', 'Caja') as token) x) as tok_ana2 \gset
select test.login('owner'); set role authenticated;
select test.eq(public.turno_terminar(:'tok_ana2'), '{"ok":false,"error":"locked"}'::jsonb, '4 another login cannot end it');
select test.login('cafe'); select test.session('dev-513-d'); set role authenticated;
select test.eq(public.turno_terminar(:'tok_ana2'), '{"ok":true}'::jsonb, '4 «Salir de este aparato»');
select test.eq(test.why513(:'tok_ana2'), 'ended', '4 ended');
reset role;
select test.eq((select ended_how from public.work_sessions where token_hash = encode(extensions.digest(:'tok_ana2', 'sha256'), 'hex')), 'signed_out', '4 «signed_out»');
-- the POS on device E: Ana rings up; the receiving page there gets her session without typing anything
select test.login('cafe'); select test.session('dev-513-e'); set role authenticated;
select public.pos_operator_start(test.staff('ana'), '4826', 'Caja 2') ->> 'token' as op_ana \gset
select public.turno_desde_caja(:'op_ana', 'Caja 2') as dc \gset
select test.eq((:'dc'::jsonb) ->> 'ok' || ' ' || ((:'dc'::jsonb) ->> 'staff_name'), 'true Ana', '4 the POS''s «¿Quién cobra?» on this device: a session for Ana, no PIN typed');
select test.eq(public.turno_desde_caja(:'op_ana', 'Caja 2'), '{"ok":false,"error":"no_session","why":"device_taken"}'::jsonb, '4 not twice on one sign-in');
select test.session('dev-513-f');
select test.eq(public.turno_desde_caja('no-es-un-token'), '{"ok":false,"error":"no_session","why":"unknown"}'::jsonb, '4 an unknown operator token: nothing');
select test.login('owner'); select test.session('dev-513-g');
select test.eq(public.turno_desde_caja(:'op_ana') ->> 'why', 'unknown', '4 the POS token of another login: nothing');
select test.login('cafe'); select test.session('dev-513-g');
select public.pos_operator_start(test.staff('marta'), '6173', 'Caja 3') ->> 'token' as op_marta \gset
reset role;
update public.time_entries set clock_out = now() where staff_id = test.staff('marta') and clock_out is null;
set role authenticated;
select test.eq(public.turno_desde_caja(:'op_marta') ->> 'why', 'not_on_shift', '4 a cashier who is not on shift gets none');
-- the identification must be of this shift: Marta's POS session from her earlier shift, then a new shift opened later
reset role;
update public.operator_sessions set started_at = now() - interval '3 hours' where token_hash = encode(extensions.digest(:'op_marta', 'sha256'), 'hex');
insert into public.time_entries (staff_id, clock_in) values (test.staff('marta'), now() - interval '1 hour');
set role authenticated;
select test.eq(public.turno_desde_caja(:'op_marta') ->> 'why', 'not_on_shift', '4 a POS identification from before the open shift (an earlier shift''s) gives none');
-- and of the person's current PIN: Luis (PIN 2468 since section 3) identifies on the POS, then his PIN is changed again
select test.login('cafe'); select test.session('dev-513-h'); set role authenticated;
select public.pos_operator_start(test.staff('luis'), '2468', 'Caja 4') ->> 'token' as op_luis \gset
reset role;
update public.operator_sessions set started_at = now() - interval '10 minutes' where token_hash = encode(extensions.digest(:'op_luis', 'sha256'), 'hex');
update public.time_entries set clock_in = now() - interval '20 minutes' where staff_id = test.staff('luis') and clock_out is null;
update public.staff_pin_changes set changed_at = now() - interval '30 minutes' where staff_id = test.staff('luis');   -- section 3's change came before
update public.staff set pin_hash = extensions.crypt('9999', extensions.gen_salt('bf')) where id = test.staff('luis');
select test.eq((select count(*)::int from public.staff_pin_changes where staff_id = test.staff('luis')), 2, '4 each PIN change is recorded (append-only)');
set role authenticated;
select test.eq(public.turno_desde_caja(:'op_luis') ->> 'why', 'pin_changed', '4 a POS identification from before a PIN change gives none');
reset role;
select test.eq((select count(*)::int from public.work_sessions where staff_id = test.staff('luis') and ended_at is null), 0, '4 and Luis has no live session');
-- the positive control: identified during the shift and after every PIN change
update public.staff_pin_changes set changed_at = now() - interval '30 minutes' where staff_id = test.staff('luis');
set role authenticated;
select test.eq(public.turno_desde_caja(:'op_luis', 'Caja 4') ->> 'staff_name', 'Luis', '4 identified during the shift and after the PIN changes: a session');
select test.throws($$select count(*) from public.staff_pin_changes$$, 'permission denied', '4 a page cannot read the PIN-change record');
reset role;
select test.eq((select how from public.work_sessions where token_hash = encode(extensions.digest((:'dc'::jsonb) ->> 'token', 'sha256'), 'hex')), 'caja', '4 (made «caja»)');
select test.eq((select count(*)::int from public.work_sessions), (select count(*)::int from public.audit_log where action = 'work_session_start'),
               '4 every session is logged when made; none is ever deleted');

-- 5) the identification lasts 15 minutes without a PIN or a delivery (owner, 2026-11-07) --------------------------------------
-- a device left on the counter identifies nobody: after 15 minutes without that person's PIN or a delivery recorded
-- with it, every use answers «idle» and the page asks the same person's PIN again; one PIN covers one visit's deliveries
select test.login('cafe'); select test.session('dev-513-m2'); select test.unlock(test.staff('ana'), '4826'); set role authenticated;
select public.proveedor_pedido_crear('5b000000-0000-4000-8000-000000051301', '[{"vendor_item_id":"5c000000-0000-4000-8000-000000051301","packs":3}]', null,
                                     '9a000000-0000-4000-8000-000000051305') ->> 'ok' as c5 \gset
select test.login('cafe'); select test.session('dev-513-i'); set role authenticated;
select public.turno_aqui(test.staff('luis'), '9999', 'Bodega') as t5 \gset
select test.eq((:'t5'::jsonb) ->> 'ok' || ' ' || (((:'t5'::jsonb) ->> 'fresh_until')::timestamptz between now() + interval '14 minutes' and now() + interval '15 minutes'),
               'true true', '5 «Estoy en turno aquí»: his PIN counts for 15 minutes (fresh_until, for the bar)');
select (:'t5'::jsonb) ->> 'token' as tok5 \gset
select test.eq(test.why513(:'tok5'), 'ok', '5 good now');
reset role;
update public.work_sessions set confirmed_at = now() - interval '14 minutes' where token_hash = encode(extensions.digest(:'tok5', 'sha256'), 'hex');
set role authenticated;
select test.eq(test.why513(:'tok5'), 'ok', '5 at minute 14: still good');
reset role;
update public.work_sessions set confirmed_at = now() - interval '15 minutes' where token_hash = encode(extensions.digest(:'tok5', 'sha256'), 'hex');
set role authenticated;
select public.turno_estado(array[:'tok5']) -> 'sessions' -> 0 as s5 \gset
select test.eq((:'s5'::jsonb) ->> 'why' || ' ' || ((:'s5'::jsonb) ->> 'staff_name') || ' ' || ((:'s5'::jsonb) ->> 'staff_id' = test.staff('luis')::text) || ' ' || ((:'s5'::jsonb) ? 'token'),
               'idle Luis true false', '5 at minute 15: «idle», with his name and id so the page offers him first, no token');
select test.eq(public.proveedores_por_recibir(:'tok5') ->> 'why', 'idle', '5 the list of orders to receive refuses it');
select test.eq(public.proveedor_pedido('9a000000-0000-4000-8000-000000051305', :'tok5') ->> 'why', 'idle', '5 an order too');
select test.eq(public.proveedor_recibir('9a000000-0000-4000-8000-000000051305', '7e000000-0000-4000-8000-000000051351', test.v513('9a000000-0000-4000-8000-000000051305'),
                 jsonb_build_array(jsonb_build_object('line_id', test.line513('9a000000-0000-4000-8000-000000051305', 1), 'packs', 1)), :'tok5') ->> 'why', 'idle',
               '5 and a delivery: refused');
reset role;
select test.eq((select count(*)::int from public.purchase_receipts where po_id = '9a000000-0000-4000-8000-000000051305'), 0, '5 nothing booked');
select test.eq((select ended_at is null from public.work_sessions where token_hash = encode(extensions.digest(:'tok5', 'sha256'), 'hex')), true,
               '5 the session is not ended, only stale: the same PIN starts over');
-- a delivery recorded with it extends the 15 minutes from that delivery
update public.work_sessions set confirmed_at = now() - interval '14 minutes' where token_hash = encode(extensions.digest(:'tok5', 'sha256'), 'hex');
set role authenticated;
select public.proveedor_recibir('9a000000-0000-4000-8000-000000051305', '7e000000-0000-4000-8000-000000051351', test.v513('9a000000-0000-4000-8000-000000051305'),
         jsonb_build_array(jsonb_build_object('line_id', test.line513('9a000000-0000-4000-8000-000000051305', 1), 'packs', 1)), :'tok5') as r5 \gset
select test.eq((:'r5'::jsonb) ->> 'ok' || ' ' || (((:'r5'::jsonb) ->> 'fresh_until')::timestamptz between now() + interval '14 minutes' and now() + interval '15 minutes'),
               'true true', '5 a delivery at minute 14: booked, and 15 more minutes from it');
reset role;
update public.work_sessions set confirmed_at = now() - interval '40 minutes', last_receipt_at = now() - interval '14 minutes'
 where token_hash = encode(extensions.digest(:'tok5', 'sha256'), 'hex');
set role authenticated;
select test.eq(test.why513(:'tok5'), 'ok', '5 the PIN 40 minutes ago, the last delivery 14 minutes ago: still good');
reset role;
update public.work_sessions set last_receipt_at = now() - interval '15 minutes' where token_hash = encode(extensions.digest(:'tok5', 'sha256'), 'hex');
set role authenticated;
select test.eq(test.why513(:'tok5'), 'idle', '5 the last delivery 15 minutes ago: «idle»');
select test.session('dev-513-i2');
select test.eq(test.why513(:'tok5'), 'idle', '5 «idle» is said before «moved»: a new sign-in gets no stale session rebound');
select test.session('dev-513-i');
-- the same person types their PIN again: a new session, the old one ended «replaced»
select public.turno_aqui(test.staff('luis'), '9999', 'Bodega') as t5b \gset
select test.eq((:'t5b'::jsonb) ->> 'ok' || ' ' || test.why513((:'t5b'::jsonb) ->> 'token') || ' ' || test.why513(:'tok5'), 'true ok ended',
               '5 his PIN again: a fresh session, the stale one ended');
reset role;
select test.eq((select ended_how from public.work_sessions where token_hash = encode(extensions.digest(:'tok5', 'sha256'), 'hex')), 'replaced', '5 «replaced»');
-- the POS's «¿Quién cobra?» counts like a PIN typed here, for the same 15 minutes: older, the cashier types it here
select test.login('cafe'); select test.session('dev-513-j'); set role authenticated;
select public.pos_operator_start(test.staff('ana'), '4826', 'Caja 5') as ops5 \gset
select test.eq((:'ops5'::jsonb) ->> 'ok', 'true', '5 (Ana signs in at the POS of another device: ' || (:'ops5'::jsonb)::text || ')');
select (:'ops5'::jsonb) ->> 'token' as op_ana5 \gset
reset role;
-- (now() is one instant in this transaction: her shift is moved an hour back, so a POS PIN of 15 minutes ago is inside it)
update public.time_entries set clock_in = now() - interval '1 hour' where staff_id = test.staff('ana') and clock_out is null;
update public.operator_sessions set started_at = now() - interval '15 minutes' where token_hash = encode(extensions.digest(:'op_ana5', 'sha256'), 'hex');
set role authenticated;
select public.turno_desde_caja(:'op_ana5', 'Caja 5') as dc5 \gset
select test.eq((:'dc5'::jsonb) ->> 'error' || ' ' || ((:'dc5'::jsonb) ->> 'why') || ' ' || ((:'dc5'::jsonb) ->> 'staff_name') || ' ' || ((:'dc5'::jsonb) ->> 'staff_id' = test.staff('ana')::text) || ' ' || ((:'dc5'::jsonb) ? 'token'),
               'no_session confirm Ana true false', '5 her PIN at the POS 15 minutes ago: «confirm» with her name, no session');
reset role;
update public.operator_sessions set started_at = now() - interval '14 minutes' where token_hash = encode(extensions.digest(:'op_ana5', 'sha256'), 'hex');
set role authenticated;
select public.turno_desde_caja(:'op_ana5', 'Caja 5') as dc5b \gset
select test.eq((:'dc5b'::jsonb) ->> 'ok' || ' ' || (((:'dc5b'::jsonb) ->> 'fresh_until')::timestamptz between now() + interval '30 seconds' and now() + interval '1 minute'),
               'true true', '5 14 minutes ago: a session that counts from the POS PIN (about 1 minute left)');
reset role;
select test.eq((select (confirmed_at = o.started_at)::text from public.work_sessions w join public.operator_sessions o on o.token_hash = encode(extensions.digest(:'op_ana5', 'sha256'), 'hex')
                 where w.token_hash = encode(extensions.digest((:'dc5b'::jsonb) ->> 'token', 'sha256'), 'hex')), 'true', '5 (its PIN moment is the POS''s)');
-- a stale session on this sign-in (Ana's, past its 15 minutes) does not keep the POS cashier out: a fresh POS PIN
-- replaces it, as a PIN typed here would; a fresh one still does («device_taken»)
update public.work_sessions set confirmed_at = now() - interval '20 minutes' where token_hash = encode(extensions.digest((:'dc5b'::jsonb) ->> 'token', 'sha256'), 'hex');
update public.operator_sessions set started_at = now() - interval '2 minutes' where token_hash = encode(extensions.digest(:'op_ana5', 'sha256'), 'hex');
set role authenticated;
select public.turno_desde_caja(:'op_ana5', 'Caja 5') as dc5c \gset
select test.eq((:'dc5c'::jsonb) ->> 'ok' || ' ' || test.why513((:'dc5b'::jsonb) ->> 'token'), 'true ended', '5 a stale session on the sign-in: the fresh POS PIN takes over, the stale one ends');
select test.eq(public.turno_desde_caja(:'op_ana5', 'Caja 5') ->> 'why', 'device_taken', '5 a fresh one on the sign-in still takes the device');
reset role;
select test.eq((select ended_how from public.work_sessions where token_hash = encode(extensions.digest((:'dc5b'::jsonb) ->> 'token', 'sha256'), 'hex')), 'replaced', '5 («replaced»)');
set role authenticated;

select test.done();
rollback;
