import glob
import json
import collections
import os

HERE = os.path.dirname(os.path.abspath(__file__))
G = 'SYM_RESULT_ActiveRecord__FinderMethods_first_2_not_found'


def main():
    forms = collections.Counter()
    example_dump = {}
    for p in sorted(glob.glob(os.path.join(HERE, 'dump_*.json'))):
        try:
            raw = json.load(open(p))
        except Exception:
            continue
        if raw.get('error'):
            continue
        for ev in raw.get('events', []):
            if ev.get('type') != 'path_condition':
                continue
            expr = ev.get('expr', '')
            if G in expr:
                taken = ev.get('taken')
                forms[(expr, taken)] += 1
                example_dump[(expr, taken)] = os.path.basename(p)
    for (expr, taken), n in sorted(forms.items(), key=lambda x: -x[1]):
        print('%5d  T=%s  %s   [e.g. %s]' % (n, taken, expr[:140], example_dump[(expr, taken)]))


if __name__ == '__main__':
    main()