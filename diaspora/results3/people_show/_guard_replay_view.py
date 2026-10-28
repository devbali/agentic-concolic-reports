import json
import re
import os

HERE = os.path.dirname(os.path.abspath(__file__))
G = 'SYM_RESULT_ActiveRecord__FinderMethods_first_2_not_found'


def main():
    for f in ['dump_replay_063.json', 'dump_replay_052.json']:
        p = os.path.join(HERE, f)
        raw = json.load(open(p))
        print('==== %s  error=%s ====' % (f, bool(raw.get('error'))))
        n_pc = 0
        for ev in raw.get('events', []):
            if ev.get('type') != 'path_condition':
                continue
            expr = ev.get('expr', '')
            taken = ev.get('taken')
            if G in expr or '_2_' in expr or 'rows' in expr or 'records' in expr or 'diaspora_handle' in expr:
                n_pc += 1
                print('  T=%s  %s' % ('T' if taken else 'F', expr[:120]))
        print('  (matched PCs: %d)' % n_pc)
        print()


if __name__ == '__main__':
    main()