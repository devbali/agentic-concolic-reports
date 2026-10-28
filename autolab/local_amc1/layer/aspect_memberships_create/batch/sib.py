import json, glob, sys, collections
from concolic.corpus.load import canon, access_trace
B = sys.argv[1]
runs = []
for f in sorted(glob.glob(B + "/dump_*.json")):
    d = json.load(open(f))
    pcs = tuple((canon(e["expr"]), bool(e["taken"])) for e in d["events"] if e["type"] == "path_condition")
    runs.append((f, pcs, frozenset(access_trace(d)), d))
short = {}
def S(x):
    if x not in short: short[x] = "E%02d" % len(short)
    return short[x]
stats = collections.defaultdict(lambda: [0, 0, []])
idx = collections.defaultdict(list)
for i, (f, pcs, tr, d) in enumerate(runs):
    for k in range(len(pcs)):
        key = (pcs[:k], pcs[k][0], pcs[k+1:])  # differ only at k (outcome)
        idx[key].append((pcs[k][1], i))
for (pre, x, post), lst in idx.items():
    ts = [i for t, i in lst if t]; fs = [i for t, i in lst if not t]
    for a in ts:
        for b in fs:
            st = stats[x]; st[0] += 1
            if runs[a][2] != runs[b][2]:
                st[1] += 1
                if len(st[2]) < 2: st[2].append((sorted(runs[a][2] ^ runs[b][2])[:3]))
# sibling pairs with only X flipped and SAME later PC list (rare); also report prefix-only siblings
for x, (n, nd, ex) in sorted(stats.items(), key=lambda kv: kv[0]):
    print(S(x), "exact-sibling pairs", n, "trace-differs", nd, x[:150]); 
    for e in ex: print("     ", [str(t)[:140] for t in e])
