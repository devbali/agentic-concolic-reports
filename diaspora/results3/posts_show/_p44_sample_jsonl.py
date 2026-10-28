#!/usr/bin/env python3
"""P44 — reservoir-sample N streamed cubes from an emission jsonl, so a drive
can be run against a RANDOM slice of the real residue rather than the head of
the file (DISCIPLINE 14: never a sorted prefix)."""
import json, os, random, sys
src, dst, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
rnd = random.Random(int(os.environ.get("P44_SEED", "20260915")))
res = []
seen = 0
with open(src) as fh:
    for line in fh:
        if not line.strip():
            continue
        seen += 1
        if len(res) < n:
            res.append(line)
        else:
            j = rnd.randrange(seen)
            if j < n:
                res[j] = line
with open(dst, "w") as fh:
    fh.writelines(res)
print(f"sampled {len(res)} of {seen} streamed cubes -> {os.path.basename(dst)}")
from collections import Counter
c = Counter(json.loads(l)["clique"] for l in res)
print(f"  distinct demand sets in the sample: {len(c)}")
print("P44-SAMPLE-DONE")
