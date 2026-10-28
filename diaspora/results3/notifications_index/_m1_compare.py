"""M-SNAP before/after on the two coverage checkpoints (2026-09-12, §26).

Counts, on each checkpoint: demand sets with a gap, distinct witness leaves,
and how many of those leaves demand `(len > 1)=True AND (len > 3)=False` on an
actors-list length -- the cube the mock's codomain forbids.
"""
import json, re, sys, collections

def read(p):
    sets, leaves, keys = 0, [], []
    for i, line in enumerate(open(p)):
        d = json.loads(line)
        if i == 0:
            continue
        cs = d['v'].get('combos') or []
        if cs:
            sets += 1
        for c in cs:
            leaves.append(tuple((e, bool(o)) for e, o in c))
            keys.append(d['k'])
    return sets, leaves, keys

_B = re.compile(r'^\((.*?) (==|>|<|>=|<=|!=) (.*)\)$')
def contradicted(leaf):
    st = {}
    for e, o in leaf:
        m = _B.match(e)
        if m and 'row_actors_row_rows' in m.group(1) and m.group(2) == '>':
            st.setdefault(m.group(1), {})[int(m.group(3))] = o
    return any(d.get(1) is True and d.get(3) is False for d in st.values())

for tag, p in (("BEFORE", sys.argv[1]), ("AFTER", sys.argv[2])):
    s, lv, ks = read(p)
    dl = set(lv)
    print(f"{tag:7} {p}")
    print(f"        sets with a gap {s}   witness leaves {len(lv)} ({len(dl)} distinct)"
          f"   contradiction-shaped {sum(1 for x in dl if contradicted(x))} distinct"
          f" / {sum(1 for x in lv if contradicted(x))} occurrences")
    globals()[tag] = (s, dl, set(ks), {k for k, x in zip(ks, lv) if contradicted(x)})

sb, lb, kb, cb = BEFORE
sa, la, ka, ca = AFTER
print(f"\nset keys with a gap: before {len(kb)}  after {len(ka)}  "
      f"still-gapped intersection {len(kb & ka)}  closed {len(kb - ka)}  new {len(ka - kb)}")
print(f"the {len(cb)} contradiction-carrying set keys: "
      f"{len(cb & ka)} still have a gap, {len(cb - ka)} closed")
