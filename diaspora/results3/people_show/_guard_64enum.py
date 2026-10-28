import glob
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
G = 'SYM_RESULT_ActiveRecord__FinderMethods_first_2_not_found'


def main():
    rows = []
    for p in sorted(glob.glob(os.path.join(HERE, 'dump_*.json'))):
        try:
            raw = json.load(open(p))
        except Exception:
            continue
        if raw.get('error'):
            continue
        pcs = [(ev.get('expr', ''), ev.get('taken')) for ev in raw.get('events', [])
               if ev.get('type') == 'path_condition']
        for expr, taken in pcs:
            if G in expr and taken is True:
                rows.append((os.path.basename(p), len(pcs), pcs))
                break
    print('guard-True dumps:', len(rows))
    for name, npc, pcs in rows:
        other = [(e[:90], t) for e, t in pcs if G not in e]
        print('%s  totalPCS=%d  other=%s' % (name, npc, other[:6]))


if __name__ == '__main__':
    main()