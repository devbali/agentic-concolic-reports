#!/usr/bin/env python3
import re, os
ROOT = "/home/dev/project"
NEW_DIR = ROOT + "/reports/diaspora/results3/queries_from_runs"
OLD_DIR = ROOT + "/ruby_examples/dse-apps/policies/extracted/diaspora/per-endpoint"
EPS = {
    "comments_index": ("comments_index.sql", "comments-index.sql"),
    "conversations_index": ("conversations_index.sql", "conversations-index.sql"),
}
def parse(path):
    out = []
    for line in open(path):
        s = line.strip()
        if not s or s.startswith("--"):
            continue
        out.append(s.rstrip(";").strip())
    return [s for s in out if s.upper().startswith("SELECT")]
def tables(q):
    m = re.search(r"\bFROM\s+(.*?)(?:\bWHERE\b|$)", q, re.S)
    if not m:
        return set()
    return set(re.findall(r"`([a-z_][a-z0-9_]*)`", m.group(1)))
for ep, (nf, of) in EPS.items():
    newq = parse(os.path.join(NEW_DIR, nf))
    oldq = parse(os.path.join(OLD_DIR, of))
    v = [(i, tables(q)) for i, q in enumerate(newq)]
    union = set().union(*(t for _, t in v)) if v else set()
    print(f"\n=== {ep}: NEW={len(newq)} OLD={len(oldq)} ===")
    for oi, oq in enumerate(oldq):
        ot = tables(oq)
        miss = ot - union
        if miss:
            cls = "PROVABLY-NOT"
            det = "tables never read by any new view: " + str(sorted(miss))
        else:
            ss = [(i, t) for i, t in v if ot <= t]
            if ss:
                cls = "CANDIDATE-EXISTS"
                det = str(len(ss)) + " new view(s) read all " + str(len(ot)) + " tables"
            else:
                best = max((len(ot & t) for _, t in v), default=0)
                cls = "NO-SUPERSET"
                det = "best overlap " + str(best) + "/" + str(len(ot)) + " tables"
        print("  OLD#%2d %-14s | %s | %s" % (oi, cls, det, oq[:90]))