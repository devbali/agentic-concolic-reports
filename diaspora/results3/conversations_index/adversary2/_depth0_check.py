#!/usr/bin/env python3
"""depth-0 target-call list of a real run vs the corpus's symbolic_call targets
(replacement for the removed concrete_checker.py; aliases applied both ways)."""
import json, glob, sys, collections
run, batch, aliases = sys.argv[1], sys.argv[2], sys.argv[3]
al = json.load(open(aliases))
corpus = collections.Counter()
for f in glob.glob(batch + "/dump_*.json"):
    try: d = json.load(open(f))
    except Exception: continue
    for ev in d.get("events", []):
        if ev.get("type") == "symbolic_call": corpus[ev.get("target")] += 1
def present(t):
    if t in corpus: return "present (%d corpus events)" % corpus[t]
    for a in al.get(t, []):
        if a in corpus: return "present via alias %s (%d)" % (a, corpus[a])
    m = t.rsplit(".", 1)[-1]
    same = [c for c in corpus if c.rsplit(".", 1)[-1] == m]
    if same: return "METHOD-NAME MATCH only: corpus has %s" % ", ".join(same)
    return "ABSENT FROM CORPUS"
for sc in json.load(open(run)):
    print("== scenario", sc["name"], "error=", sc.get("error"))
    top = collections.Counter(); nested = collections.Counter()
    for c in sc.get("target_calls", []):
        (top if (c.get("depth", 0) == 0) else nested)[c["target"].replace("#", ".")] += 1
    for t in sorted(set(top) | set(nested)):
        print("   %-70s top x%-3d nested x%-3d %s" % (t, top[t], nested[t], present(t)))
    stmts = sc.get("statements", [])
    outside = [s["sql"] for s in stmts if not s.get("under")]
    print("   statements:", len(stmts), "outside any frame:", len(outside))
    for s in sorted(set(outside)): print("      OUTSIDE:", s[:200])
