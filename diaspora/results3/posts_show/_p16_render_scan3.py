#!/usr/bin/env python3
"""P16 / §79 part 3 — WHICH ordinals of Anonymous.process@264 share a message,
and which decide. The grouping signature per run, corpus-wide."""
import json, os, re, glob, hashlib, collections
from multiprocessing import Pool
B = os.path.dirname(os.path.abspath(__file__))
ORD = re.compile(r"SYM_RESULT_Anonymous_process_(\d+)")
PCRE = re.compile(r"^\(SYM_RESULT_Anonymous_process_(\d+) == ''\)$")

def one(path):
    try:
        d = json.load(open(path))
    except Exception:
        return None
    calls = {}
    for ev in d.get("events") or ():
        if ev.get("type") == "symbolic_call" and ev.get("target") == "Anonymous.process":
            m = ORD.fullmatch(str(ev.get("result_name") or ""))
            if m:
                a = json.dumps(ev.get("args"), sort_keys=True, default=str)
                calls[int(m.group(1))] = hashlib.blake2b(a.encode(), digest_size=6).hexdigest()
    if not calls:
        return None
    dec = set()
    for ev in d.get("events") or ():
        if ev.get("type") == "path_condition":
            m = PCRE.match(str(ev.get("expr") or ""))
            if m:
                dec.add(int(m.group(1)))
    groups = collections.defaultdict(list)
    for o, dg in calls.items():
        groups[dg].append(o)
    sig = "|".join(",".join(str(x) for x in sorted(v))
                   for v in sorted(groups.values(), key=lambda v: min(v)))
    return (sig, ",".join(str(x) for x in sorted(dec)))

def main():
    paths = sorted(glob.glob(os.path.join(B, "dump_*.json")))
    c = collections.Counter(); cd = collections.Counter()
    with Pool(4) as pool:
        for r in pool.imap_unordered(one, paths, chunksize=200):
            if r:
                c[r[0]] += 1; cd[(r[0], r[1])] += 1
    out = {"grouping_signature": dict(c.most_common(20)),
           "grouping_x_decided": {f"{a} :: decided[{b}]": n for (a, b), n in cd.most_common(30)}}
    json.dump(out, open(os.path.join(B, "_p16_render_scan3.json"), "w"), indent=1)
    print(json.dumps(out, indent=1)[:3000])
    print("P16-SCAN3-DONE")

if __name__ == "__main__":
    main()
