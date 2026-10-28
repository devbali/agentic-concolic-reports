import json, glob, sys, collections
from concolic.corpus.load import canon, access_trace
B = sys.argv[1]
runs = []
for f in sorted(glob.glob(B + "/dump_*.json")):
    d = json.load(open(f))
    pcs = tuple((canon(e["expr"]), bool(e["taken"])) for e in d["events"] if e["type"] == "path_condition")
    runs.append((f, pcs, frozenset(access_trace(d)), d))
groups = {
 "devise_lang": "devise_user_first_1_language", "fb_user_lang": "find_by_1_user_language",
 "fb_owner_lang": "find_by_1_person_owner_language", "assoc_owner_lang": "assoc_person_owner_language",
}
for g, tok in groups.items():
    buckets = collections.defaultdict(list)
    for i, (f, pcs, tr, d) in enumerate(runs):
        rest = tuple(p for p in pcs if tok not in p[0])
        arm = tuple(p for p in pcs if tok in p[0])
        armn = "pl" if arm and arm[0][1] else ("xx" if len(arm) > 1 and arm[1][1] else ("en" if arm else "-"))
        buckets[rest].append((armn, i))
    n = nd = 0; ex = []
    arms = collections.Counter()
    for rest, lst in buckets.items():
        for a in range(len(lst)):
            for b in range(a+1, len(lst)):
                if lst[a][0] != lst[b][0]:
                    n += 1; arms[(lst[a][0], lst[b][0])] += 1
                    ta, tb = runs[lst[a][1]][2], runs[lst[b][1]][2]
                    if ta != tb:
                        nd += 1
                        if len(ex) < 2: ex.append((lst[a][0], lst[b][0], [str(t)[:120] for t in sorted(ta ^ tb)[:3]], len(runs[lst[a][1]][1]), len(runs[lst[b][1]][1])))
    print(g, "pairs", n, "differ", nd, dict(arms)); [print("   ", e) for e in ex]
# terminals: last event per run
term = collections.Counter()
for f, pcs, tr, d in runs:
    langs = [p for p in pcs if "language" in p[0] and p[1]]
    last = d["events"][-1]
    term[(last["type"], str(last.get("target") or last.get("expr"))[:60], tuple(sorted(set(x[0].split('"sym":"')[1].split('"')[0] + ':' + x[0].split('"value":"')[1][:2] for x in langs))))] += 1
for k, v in term.most_common(15): print(v, k)
