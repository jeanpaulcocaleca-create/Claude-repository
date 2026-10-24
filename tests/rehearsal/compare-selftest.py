"""Canopy OS rehearsal · compare.py's reset mode, checked on crafted copies of run.sh step 10's files.
python3 compare-selftest.py <out-dir>      (the folder with reset-*.json; exit 1 on the first case that misbehaves)
Each case copies the real files under the plain names (as the owner's "Ensayo en pruebas" writes them), changes one thing
and runs compare.py: the owner's run passes and reports what had rows; a table production never wrote to is reported,
not a difference (2026-10-14: the first real-data rehearsal stopped on order_part_lines); the anonymizer's emptied tables
are told apart; with 'fixture' the seeded copy must give the reset a row in every table; and what must still fail, fails
(a cleared table left with rows, a preserved table changed, a copy with nothing to clear, the reset on a migrated
database, the log without its new line, a snapshot missing one of the 26 tables)."""
import json
import os
import shutil
import subprocess
import sys
import tempfile

out = sys.argv[1]
HERE = os.path.dirname(os.path.abspath(__file__))
NAMES = ('snapshot-before', 'snapshot-after-reset', 'snapshot-after', 'consistency-before', 'consistency-after-reset',
         'consistency-after', 'release-check')
ZERO = {'order_part_lines': ('part_lines',), 'orders': ('orders', 'orders_paid_not_voided', 'orders_open_bills', 'orders_voided'),
        'register_days': ('register_days',), 'stock_moves': ('stock_moves',), 'time_entries': ('time_entries',)}
cases = 0


def zero(files, *tables):  # the table had no rows before the reset (as production's order_part_lines on 2026-10-14)
    for t in tables:
        files['snapshot-before']['data_fingerprint'][t] = '0:-'
        for k in ZERO.get(t, ()):
            files['consistency-before']['kept'][k] = 0


def case(name, args, edit, want_exit, want_text, mode='reset'):
    global cases
    d = tempfile.mkdtemp(prefix='compare-selftest-')
    try:
        files = {n: json.load(open(os.path.join(out, f'reset-{n}.json'))) for n in NAMES}
        edit(files)
        for n, v in files.items():
            with open(os.path.join(d, f'{n}.json'), 'w') as f:
                json.dump(v, f)
        r = subprocess.run([sys.executable, os.path.join(HERE, 'compare.py'), d, mode, *args], capture_output=True, text=True)
        if r.returncode != want_exit or want_text not in r.stdout:
            print(f'    FAIL  compare.py self-test · {name}: expected exit {want_exit} saying "{want_text}", got exit {r.returncode}:')
            print(r.stdout + r.stderr)
            sys.exit(1)
        cases += 1
    finally:
        shutil.rmtree(d, ignore_errors=True)


def fp(files, which, table, value):
    files[which]['data_fingerprint'][table] = value


# the owner's run on a copy where every cleared table had rows (the seeded copy as it is)
case("the owner's run passes and says every cleared table had rows", [], lambda f: None, 0, 'reset: 14 tables cleared (14 had rows)')
# a table the café never wrote to: empty before, empty after, reported by name (not a difference)
case('a table production never wrote to is reported, not a difference', [], lambda f: zero(f, 'order_part_lines', 'tab_adds'), 0,
     'order_part_lines, tab_adds: no rows in the copy of production, nothing to clear')
case("the anonymizer's emptied tables are told apart", [], lambda f: zero(f, 'access_unlocks', 'sales_unlocks', 'inventory_unlocks'), 0,
     'access_unlocks, inventory_unlocks, sales_unlocks: unlock tokens, emptied by anonimizar.sql before the copy left the job')
# the seeded copy of run.sh step 10 must exercise the clearing of every table
case('with fixture, a table without rows is a difference', ['fixture'], lambda f: zero(f, 'order_part_lines'), 1,
     'order_part_lines had nothing to clear in the rehearsal: 0:-')
# what must still fail, on the owner's run too
case('a cleared table left with rows is a difference', [], lambda f: fp(f, 'snapshot-after-reset', 'orders', '3:' + '0' * 32), 1,
     'orders not cleared: 3:' + '0' * 32)
case('a preserved table changed by the reset is a difference', [], lambda f: fp(f, 'snapshot-after-reset', 'menu_items', '5:' + 'f' * 32), 1,
     'the reset changed menu_items:')
case('a copy with nothing to clear is a difference', [], lambda f: zero(f, 'orders', 'register_days', 'stock_moves', 'time_entries'), 1,
     'nothing to clear in the copy: no sales, register days, shifts or stock moves before the reset')
case('the reset on a migrated database is a difference', [], lambda f: f['snapshot-after-reset'].__setitem__('migrations_applied', '0000-0028'), 1,
     'the reset ran on a migrated database: 0000-0028')
case('the log without its new line is a difference', [],
     lambda f: fp(f, 'snapshot-after-reset', 'audit_log', f['snapshot-before']['data_fingerprint']['audit_log']), 1,
     'the log should have one line more:')
case('a snapshot without one of the 26 tables is a difference, not a crash', [],
     lambda f: [f[n]['data_fingerprint'].pop('tab_adds') for n in ('snapshot-before', 'snapshot-after-reset')], 1,
     "the original tables are not the reset's 14 cleared + 12 kept: ['tab_adds']")
# the 'after' mode on the same copy (the state right after the reset stands for production before the migrations)
def after_copy(f, had=None, **settings):
    f['snapshot-before'], f['consistency-before'] = f['snapshot-after-reset'], f['consistency-after-reset']
    if had is not None:   # production after the launch: the copy already had migrations, settings of its own, no Storage
        f['snapshot-before']['migrations_applied'] = had
        f['release-check'].update(storage_buckets_missing=['expense-receipts'], storage_policies_missing=['expense receipts add', 'expense receipts read'],
                                  receipt_upload_rule_current=False)
    f['release-check']['settings'].update(settings)
case('a copy from before the launch passes the after mode', [], after_copy, 0, 'storage: receipts bucket and rules in place', mode='after')
case('a copy from before the launch with a switch already on is a difference', [], lambda f: after_copy(f, operator_mode='record'), 1,
     "setting operator_mode should be 'off'", mode='after')
case("a copy of production after the launch keeps the owner's operational switches; its Storage is not in the copy", [],
     lambda f: after_copy(f, list(range(29)), operator_mode='record'), 0, 'the copy already had migrations 0000-0028 (production after the launch)', mode='after')
case('a copy of production after the launch with automatic books on is still a difference', [],
     lambda f: after_copy(f, list(range(29)), ledger_auto_post=True), 1, 'setting ledger_auto_post should be False', mode='after')
print(f'    compare.py self-test: {cases} cases behave (the owner-run report, the fixture coverage, six differences still caught, '
      f'the after mode on a copy from before and after the launch)')
