#!/usr/bin/env python3
"""C16 — turn `_c16_enum.py`'s §16e EMIT_REMAINING stream into a gaps file.

Same record shape `_c14_gaps.py` produced (so `_c14_construct.py`,
`_c13_drive.sh` and `_c13_classify.py` read it verbatim), plus the three §16e
facts the enumerator now carries per cube:

  `sdig`      the CHECKER's own per-set key (coverage.py step 6 digests the
              same reordered group), so a cube joins to a coverage checkpoint
              by set without guessing;
  `a`         |profiles matching this leaf's gate prefix P|  (§16e's A);
  `cf`        the members P forecloses — dropped from this cube;
  `unmatched` A == 0: the demand STANDS, nothing was inferred, and the cube is
              booked in its OWN class (§13.3 multi-gate-unreachable).

The cube is `pre` ∪ `asg`, so the FULL prefix P is pinned in every cube — that
is exactly the new information §16e hands the constructor: a shorter member
list, and a gate prefix that is now known to be the whole of what the leaf
demands beyond it.
"""
import json, os, sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.environ.get("C16_REMAIN", os.path.join(HERE, "_c16_remaining.jsonl"))
OUT = os.environ.get("C14_GAPS", os.path.join(HERE, "_c16_gaps.json"))

gaps, groups, bad = [], {}, 0
per_set = Counter(); per_group = Counter(); widths = Counter()
reach = Counter(); cls = Counter()
for line in open(SRC):
    line = line.strip()
    if not line:
        continue
    try:
        r = json.loads(line)
    except Exception:
        bad += 1
        continue
    pre = r["pre"]; asg = r["asg"]
    gkey = (r["set"], tuple(sorted(pre.items())))
    gid = groups.setdefault(gkey, len(groups))
    cube = sorted(set(list(pre.items()) + list(asg.items())))
    gaps.append({
        "id": f"c{len(gaps):06d}",
        "set": r["set"], "sdig": r.get("sdig"), "group": gid,
        "set_capped": False,
        "width": len(cube), "surv": r.get("surv"),
        "reachable": bool(r.get("reachable")),
        "a": r.get("a", -1), "cf": r.get("cf") or [],
        "unmatched": bool(r.get("unmatched")),
        "pre": pre,
        "cube": [[e, bool(o)] for e, o in cube],
        "model": {},
    })
    per_set[r["set"]] += 1
    per_group[gid] += 1
    widths[len(cube)] += 1
    reach["reachable" if r.get("reachable") else "unreachable"] += 1
    cls["A=0 (unmatched gate conjunction)" if r.get("unmatched")
        else ("A>0, coarsened by §16e" if r.get("cf")
              else "A>0, no member foreclosed")] += 1

print(f"remaining cubes      : {len(gaps)}   (unparsed lines {bad})")
print(f"demand sets involved : {len(per_set)}")
print(f"leaf groups involved : {len(groups)}")
print(f"reachability         : {dict(reach)}")
print("§16e class of each cube:")
for k, v in cls.most_common():
    print(f"   {v:8d}  {k}")
print("cubes per SET   distribution: " + ", ".join(
    f"{k}:{v}" for k, v in sorted(Counter(per_set.values()).items())[:16]))
print(f"  top sets: {[c for _s, c in per_set.most_common(8)]}")
print("cubes per GROUP distribution: " + ", ".join(
    f"{k}:{v}" for k, v in sorted(Counter(per_group.values()).items())[:16]))
print("width histogram : " + ", ".join(f"{k}:{v}" for k, v in sorted(widths.items())))
ex = Counter(e for g in gaps for e, _ in g["cube"])
print(f"distinct expressions over all cubes: {len(ex)}")
json.dump(gaps, open(OUT, "w"))
print(f"C16-GAPS-DONE {OUT} ({os.path.getsize(OUT)/1e6:.1f} MB)")
