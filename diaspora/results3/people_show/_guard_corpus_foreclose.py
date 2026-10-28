import glob
import json
import re
import os

HERE = os.path.dirname(os.path.abspath(__file__))
GUARDS = [
    'SYM_RESULT_ActiveRecord__FinderMethods_first_2_not_found',
    'SYM_RESULT_ActiveRecord__FinderMethods_first_2_closed_account',
    'SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_2_not_found',
    'SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found',
    'SYM_RESULT_ActiveRecord__FinderMethods_first_1_closed_account',
    'SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_1_not_found',
    'SYM_PERSON_via_user_closed_account',
    'SYM_RESULT_ActiveRecord__Core__ClassMethods_find_by_2_closed_account',
    'SYM_RESULT_ActiveRecord__Factory_girl_create_2_closed_account',
]

# downstream-demand indicator: any of these var families recorded taken=True
ROWS = re.compile(r'_rows\b|row_|to_a_|records_')
HANDLE = re.compile(r'diaspora_handle|_guid|comments_count|provider_display_name|public\b|nsfw')


def guard_true_runs(g):
    """Return list of (dump_basename, has_downstream_any, has_handle) where g taken True."""
    hits = []
    for p in sorted(glob.glob(os.path.join(HERE, 'dump_*.json'))):
        try:
            raw = json.load(open(p))
        except Exception:
            continue
        if raw.get('error'):
            continue
        g_true = False
        has_down = False
        has_handle = False
        for ev in raw.get('events', []):
            if ev.get('type') != 'path_condition':
                continue
            expr = ev.get('expr', '')
            taken = ev.get('taken')
            if g in expr:
                if taken is True:
                    g_true = True
            elif taken is True:
                if ROWS.search(expr):
                    has_down = True
                if HANDLE.search(expr):
                    has_handle = True
        if g_true:
            hits.append((os.path.basename(p), has_down, has_handle))
    return hits


def main():
    dumps = glob.glob(os.path.join(HERE, 'dump_*.json'))
    print('dumps:', len(dumps))
    for g in GUARDS:
        hits = guard_true_runs(g)
        total = len(hits)
        with_down = sum(1 for _, d, _ in hits if d)
        with_handle = sum(1 for _, _, h in hits if h)
        short_only = sum(1 for _, d, h in hits if not d and not h)
        print('%s' % g)
        print('   guard==True runs: %d  (with downstream-data bytes: %d, with handle-split: %d, guard-only/short: %d)'
              % (total, with_down, with_handle, short_only))
        if total and total <= 5:
            for b, d, h in hits:
                print('      %s  downstream=%s handle=%s' % (b, d, h))


if __name__ == '__main__':
    main()