"""Canopy OS rehearsal · compare the read-only checks taken before and after the migrations.
python3 compare.py <out-dir> after|day-after     (exit 1 on any unexpected difference)"""
import json
import os
import sys

out, mode = sys.argv[1], sys.argv[2]
load = lambda n: json.load(open(os.path.join(out, n)))
errors = []


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

before_c = load('consistency-before.json')
if mode == 'after':
    sb, sa = load('snapshot-before.json'), load('snapshot-after.json')
    ca, rc = load('consistency-after.json'), load('release-check.json')
    n = len([f for f in os.listdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../supabase/migrations')) if f.endswith('.sql')])
    check(sa['migrations_applied'] == list(range(n)), f"migrations applied: {sa['migrations_applied']}")
    sc = sa['schema']
    for k in ('functions_unknown', 'functions_changed', 'tables_missing', 'live_pages_rpc_missing'):
        check(sc[k] == [], f'{k}: {sc[k]}')
    check(sc['tables_columns_differ'] == {}, f"original tables changed type or lost columns: {sc['tables_columns_differ']}")
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
    for k, v in before_c['kept'].items():
        check(ca['kept'].get(k) == v, f'kept.{k}: {v} -> {ca["kept"].get(k)}')
    for k, v in before_c['problems'].items():
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
    for k, v in (('price_mode', 'inclusive'), ('ledger_auto_post', False), ('einvoice_mode', 'off'), ('operator_mode', 'off')):
        check(st.get(k) == v, f'setting {k} should be {v!r} after the window, is {st.get(k)!r}')
    check(rc['confirmations'] == [], f"no confirmation may exist before the owner/accountant gives it: {rc['confirmations']}")
    if not errors:
        print(f"    unchanged: {len(fb)} original tables (every original column, md5), {len(before_c['kept'])} business checks; "
              f"open rules {len(sec['policies_without_account_check'])} (all reviewed); functions: {sc['functions_by_version']}")
        if af.get('orders_business_date_not_sale_day') not in (None, '0'):
            print(f"    note: {af['orders_business_date_not_sale_day']} sales belong to another business day than their clock time (bills paid later, by design)")
else:
    cd = load('consistency-day-after.json')
    for k, v in before_c['problems'].items():
        check(cd['problems'].get(k) == v, f'after a day of work, problems.{k}: {v} -> {cd["problems"].get(k)}')
    af = cd['after']
    for k in ('ledger_unbalanced', 'receipt_numbers_repeated', 'paid_orders_without_business_date', 'rows_without_location'):
        check(af.get(k) == '0', f'after a day of work, after.{k} = {af.get(k)}')
    check(cd['kept']['orders'] == before_c['kept']['orders'] + 4, f"orders: {before_c['kept']['orders']} + 4 new -> {cd['kept']['orders']}")
    if not errors:
        print('    old pages, an offline sale from before the window, new pages, room order, stock, register close: all recorded; no new problems')

for e in errors:
    print('    DIFFERENCE:', e)
sys.exit(1 if errors else 0)
