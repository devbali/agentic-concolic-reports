import glob
import json
import re
import os

HERE = os.path.dirname(os.path.abspath(__file__))
G = 'SYM_RESULT_ActiveRecord__FinderMethods_first_2_not_found'


def main():
    shown = 0
    for p in sorted(glob.glob(os.path.join(HERE, 'dump_*.json'))):
        try:
            raw = json.load(open(p))
        except Exception:
            continue
        if raw.get('error'):
            continue
        g_true = False
        pcs = []
        for ev in raw.get('events', []):
            if ev.get('type') != 'path_condition':
                continue
            pcs.append((ev.get('expr', ''), ev.get('taken')))
            if ev.get('expr', '') == G + ' == True' and ev.get('taken'):
                g_true = True
        if g_true:
            shown += 1
            if shown > 6:
                break
            print('=== %s g_true with these PC exprs (taken=T/F):' % os.path.basename(p))
            for expr, taken in pcs:
                if G in expr or 'diaspora_handle' in expr or 'rows' in expr or 'records' in expr:
                    print('   %s  %s' % ('T' if taken else 'F', expr[:110]))
            print()


if __name__ == '__main__':
    main()