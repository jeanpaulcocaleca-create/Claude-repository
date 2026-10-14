"""Canopy OS rehearsal · compare the read-only checks taken before and after the migrations.
python3 compare.py <out-dir> after|day-after|reset     (exit 1 on any unexpected difference)
  after      the main copy: snapshot and consistency before -> after the migrations, release check
  day-after  the main copy after a day of work on the old and the new pages
  reset      the copy that went through the one-time reset (run.sh step 10, reset-*.json): the reset kept what it must
             and cleared the rest, then the migrations changed nothing of what was left"""
import json
import os
import sys

out, mode = sys.argv[1], sys.argv[2]
load = lambda n: json.load(open(os.path.join(out, n)))
errors = []
MIGRATIONS = len([f for f in os.listdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../supabase/migrations')) if f.endswith('.sql')])


def check(cond, msg):
    if not cond:
        errors.append(msg)


# what may run without signing in, and the signed-in functions that need no account check (all reviewed: menu,
# room orders, schema version, small helpers used inside triggers and rules; docs/DECISIONS.md D-022, D-023)
OPEN_POLICIES = {
    'app_settings · settings read · SELECT · anon,authenticated', 'board_group_slides · group slides read · SELECT · anon,authenticated',
    'board_settings · board settings read · SELECT · anon,authenticated', 'chat_questions · visitors can ask · INSERT · anon,authenticated',
    'locations · locations read · SELECT · authenticated', 'menu_categories · menu categories read · SELECT · anon,authenticated',
    'menu_items · menu items read · SELECT · anon,authenticated', 'objects · menu photos read · SELECT · anon,authenticated',
    'order_items · order items read · SELECT · authenticated', 'order_part_lines · part lines read · SELECT · authenticated',
    'tax_rates · tax rates read · SELECT · authenticated'}
ANON_DEFINER = ['canopy_schema_version', 'order_status', 'place_room_order', 'room_lookup']
# the one-time reset (supabase/tools/reinicio-operativo.sql, D-038): the original tables it clears, the ones it keeps byte
# for byte, and the two it writes (every stock item's on_hand to 0, one line in the log)
CLEARED = ('order_part_lines', 'tab_adds', 'order_items', 'orders', 'discount_approvals', 'register_days', 'time_entries', 'stock_moves',
           'purchase_lines', 'purchase_orders', 'access_unlocks', 'sales_unlocks', 'inventory_unlocks', 'chat_questions')
PRESERVED = ('menu_categories', 'menu_items', 'recipes', 'vendors', 'staff', 'app_accounts', 'app_settings', 'board_settings', 'board_group_slides', 'rooms')
rows = lambda fp: int(fp.split(':')[0])   # a data fingerprint is 'rows:md5 of every original column'


def migrated(sb, sa, cb, ca, rc):
    """the migrations changed nothing that existed and left the structure, the security and the switches as expected:
    sb/sa the snapshots before and after them, cb/ca the consistency checks, rc the release check; returns what to print"""
    check(sa['migrations_applied'] == list(range(MIGRATIONS)), f"migrations applied: {sa['migrations_applied']}")
    sc, sb_sc = sa['schema'], sb['schema']
    # production may differ from the repository before the window (found by the snapshot, e.g. a function body or an
    # extra column): that is allowed only if the migrations leave it exactly as it was; anything new is an error
    for k in ('functions_unknown', 'functions_changed'):
        new = sorted(set(sc[k]) - set(sb_sc[k]))
        check(not new, f'{k} after the migrations (not there before): {new}')
    for k in ('tables_missing', 'live_pages_rpc_missing'):
        check(sc[k] == [], f'{k}: {sc[k]}')
    # over the tables different before or after, so drift that disappears is reported here too
    db, da = sb_sc['tables_columns_differ'], sc['tables_columns_differ']
    moved = {t: da.get(t) for t in sorted(set(db) | set(da)) if db.get(t) != da.get(t)}
    check(not moved, f"original tables changed type or lost columns: {moved}")
    # the original tables' triggers: what differed before (production drift) must still differ the same way
    check(sc.get('triggers_differ', {}) == sb_sc.get('triggers_differ', {}),
          f"triggers on the original tables changed: {sb_sc.get('triggers_differ')} -> {sc.get('triggers_differ')}")
    drift = sorted(set(sb_sc['functions_changed']) | set(sb_sc['functions_unknown'])) + sorted(sb_sc['tables_columns_differ']) + \
            [f'trigger {k}: {t}' for k, ts in sorted(sb_sc.get('triggers_differ', {}).items()) for t in ts]
    sec = sa['security']
    check(sec['tables_without_rls'] == [], f"tables without RLS: {sec['tables_without_rls']}")
    extra = sorted(set(sec['policies_without_account_check']) - OPEN_POLICIES)
    check(not extra, f'open rules not reviewed: {extra}')
    # the data that existed before: every original column of every original table, byte for byte
    fb, fa = sb['data_fingerprint'], sa['data_fingerprint']
    for t in sorted(fb):
        check(fa.get(t) == fb[t], f'data changed in {t}: {fb[t]} -> {fa.get(t)}')
    check(sb['storage_fingerprint'] == sa['storage_fingerprint'], 'storage listing changed')
    # business invariants
    for k, v in cb['kept'].items():
        check(ca['kept'].get(k) == v, f'kept.{k}: {v} -> {ca["kept"].get(k)}')
    for k, v in cb['problems'].items():
        check(ca['problems'].get(k) == v, f'problems.{k}: {v} -> {ca["problems"].get(k)}')
    af = ca['after']
    for k in ('ledger_unbalanced', 'receipt_numbers_repeated', 'paid_orders_without_business_date', 'rows_without_location'):
        check(af.get(k) == '0', f'after.{k} = {af.get(k)}')
    check(rc['functions_missing'] == [], f"functions the pages need: {rc['functions_missing']}")
    check(rc['anon_can_run'] == ANON_DEFINER, f"anonymous visitors can run: {rc['anon_can_run']}")
    check(rc['tables_without_rls'] == [], 'release check: tables without RLS')
    check(rc['ledger']['unbalanced'] == 0, 'release check: ledger unbalanced')
    # regulated features arrive switched OFF (CLAUDE.md): prices as today, no automatic books, no e-invoices,
    # nobody's confirmation recorded on their behalf
    st = rc['settings']
    for k, v in (('price_mode', 'inclusive'), ('ledger_auto_post', False), ('einvoice_mode', 'off'), ('operator_mode', 'off'),
                 ('payroll_renta_withhold', False), ('payroll_accrue_aguinaldo', False)):
        check(st.get(k) == v, f'setting {k} should be {v!r} after the window, is {st.get(k)!r}')
    check(rc['confirmations'] == [], f"no confirmation may exist before the owner/accountant gives it: {rc['confirmations']}")
    # Storage: the receipts bucket and its two rules (0015), the upload rule of 0025; the menu photos rules are
    # listed by the release check only where the menu-photos bucket exists (a staging project never gets it)
    check(rc['storage_buckets_missing'] == [], f"storage buckets missing: {rc['storage_buckets_missing']}")
    check(rc['storage_policies_missing'] == [], f"storage rules missing: {rc['storage_policies_missing']}")
    check(rc['receipt_upload_rule_current'] is True, f"receipt upload rule current: {rc['receipt_upload_rule_current']}")
    return dict(drift=drift, tables=len(fb), checks=len(cb['kept']), open_rules=len(sec['policies_without_account_check']),
                functions=sc['functions_by_version'], rc=rc, rights=sb.get('storage_rights') or {}, af=af)


def report(r):
    if r['drift']:
        print(f"    already different from the repository before the window, left as it was: {', '.join(r['drift'])}")
    print(f"    unchanged: {r['tables']} original tables (every original column, md5), {r['checks']} business checks; "
          f"open rules {r['open_rules']} (all reviewed); functions: {r['functions']}")
    print(f"    storage: receipts bucket and rules in place, upload rule current; menu photos bucket "
          f"{'and its rules present' if r['rc']['menu_photos_bucket'] else 'absent (not checked)'}")
    # on a staging project these are Supabase's real rights: compare them with production's (follow-up query);
    # expected in production: can_insert_buckets true, member_of_storage_owner false, policy_grants_storage_objects true
    print(f"    rights of this account in Storage: " + ', '.join(f'{k} {r["rights"].get(k)}' for k in
          ('can_insert_buckets', 'member_of_storage_owner', 'policy_grants_storage_objects')))
    if r['af'].get('orders_business_date_not_sale_day') not in (None, '0'):
        print(f"    note: {r['af']['orders_business_date_not_sale_day']} sales belong to another business day than their clock time (bills paid later, by design)")


if mode == 'after':
    r = migrated(load('snapshot-before.json'), load('snapshot-after.json'), load('consistency-before.json'), load('consistency-after.json'), load('release-check.json'))
    if not errors:
        report(r)
elif mode == 'day-after':
    before_c, cd = load('consistency-before.json'), load('consistency-day-after.json')
    for k, v in before_c['problems'].items():
        check(cd['problems'].get(k) == v, f'after a day of work, problems.{k}: {v} -> {cd["problems"].get(k)}')
    af = cd['after']
    for k in ('ledger_unbalanced', 'receipt_numbers_repeated', 'paid_orders_without_business_date', 'rows_without_location'):
        check(af.get(k) == '0', f'after a day of work, after.{k} = {af.get(k)}')
    check(cd['kept']['orders'] == before_c['kept']['orders'] + 4, f"orders: {before_c['kept']['orders']} + 4 new -> {cd['kept']['orders']}")
    if not errors:
        print('    old pages, an offline sale from before the window, new pages, room order, stock, register close: all recorded; no new problems')
else:
    # before the reset (today's schema, the test period's history) -> right after it (today's schema, empty café) -> after the migrations
    # run.sh step 10 shares one folder with the main copy and prefixes its files 'reset-'; the owner's staging rehearsal
    # (ensayo.sh with REINICIO=si) has a folder of its own and writes the plain names
    pre = 'reset-' if os.path.exists(os.path.join(out, 'reset-snapshot-before.json')) else ''
    s0, s1, s2 = load(f'{pre}snapshot-before.json'), load(f'{pre}snapshot-after-reset.json'), load(f'{pre}snapshot-after.json')
    c0, c1, c2 = load(f'{pre}consistency-before.json'), load(f'{pre}consistency-after-reset.json'), load(f'{pre}consistency-after.json')
    f0, f1 = s0['data_fingerprint'], s1['data_fingerprint']
    check(s1['migrations_applied'] == 'none: 0000 not applied', f"the reset ran on a migrated database: {s1['migrations_applied']}")
    # the reset's lists and the snapshot's original tables are the same 26: a table one of them forgets is caught here
    check(set(f0) == set(f1) == set(CLEARED) | set(PRESERVED) | {'stock_items', 'audit_log'},
          f"the original tables are not the reset's {len(CLEARED)} cleared + {len(PRESERVED) + 2} kept: {sorted(set(f0) ^ (set(CLEARED) | set(PRESERVED) | {'stock_items', 'audit_log'}))}")
    for t in CLEARED:
        check(rows(f0[t]) > 0 or t in ('tab_adds', 'access_unlocks', 'sales_unlocks', 'inventory_unlocks'), f'{t} had nothing to clear in the rehearsal: {f0[t]}')
        check(f1[t] == '0:-', f'{t} not cleared: {f1[t]}')
    for t in PRESERVED:
        check(f1[t] == f0[t], f'the reset changed {t}: {f0[t]} -> {f1[t]}')
    check(rows(f1['stock_items']) == rows(f0['stock_items']) > 0, f"stock items: {f0['stock_items']} -> {f1['stock_items']}")
    check(rows(f1['audit_log']) == rows(f0['audit_log']) + 1, f"the log should have one line more: {f0['audit_log']} -> {f1['audit_log']}")
    k0, k1 = c0['kept'], c1['kept']
    for k in ('orders', 'orders_paid_not_voided', 'orders_open_bills', 'orders_voided', 'items', 'bill_parts', 'part_lines', 'register_days',
              'stock_moves', 'purchase_orders', 'time_entries'):
        check(k1[k] == 0, f'after the reset kept.{k} should be 0, is {k1[k]}')
    for k in ('stock_items', 'staff', 'staff_md5', 'logins', 'menu_md5'):
        check(k1[k] == k0[k], f'the reset changed kept.{k}: {k0[k]} -> {k1[k]}')
    check(k1['audit_log'] == k0['audit_log'] + 1, f"kept.audit_log: {k0['audit_log']} -> {k1['audit_log']}")
    for k, v in c1['problems'].items():
        check(v == 0, f'after the reset problems.{k} should be 0, is {v}')
    # then the migrations, checked exactly as on the main copy, against the state right after the reset
    r = migrated(s1, s2, c1, c2, load(f'{pre}release-check.json'))
    if not errors:
        print(f"    reset: {len(CLEARED)} tables cleared, {len(PRESERVED)} kept byte for byte, {rows(f1['stock_items'])} stock items at zero, "
              f"{rows(f1['audit_log'])} log lines (one new); then the migrations:")
        report(r)

for e in errors:
    print('    DIFFERENCE:', e)
sys.exit(1 if errors else 0)
