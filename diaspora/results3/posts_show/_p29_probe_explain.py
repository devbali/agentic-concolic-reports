#!/usr/bin/env python3
"""P29 — the verdict of the RENDER_TEXT_SOURCE falsification probe.

PASS  = >= 200 constructed runs that RECORD the pair, 0 disagreements.
FAIL  = any run recording the two with different values (the falsifier fired).
"""
import glob, json, os, collections, hashlib

B = os.path.dirname(os.path.abspath(__file__))
ACT = ("SYM_RESULT_ActiveRecord__Relation_evilq_act_vis_1",
       "SYM_RESULT_ActiveRecord__Relation_evilq_act_author_1",
       "SYM_RESULT_ActiveRecord__Relation_evilq_act_public_1",
       "SYM_RESULT_ActiveRecord__Relation_findpublic_act_1")
P3 = "(SYM_RESULT_Anonymous_process_3 == '')"
P2 = "(SYM_RESULT_Anonymous_process_2 == '')"

files = sorted(glob.glob(os.path.join(B, "dump_*P29P*.json")))
print("probe dumps:", len(files))
prof = set(); both = 0; agree = 0; dis = []
p3only = 0; actonly = 0; neither = 0
p2p3 = 0; p2p3dis = 0
byact = collections.Counter(); byact_dis = collections.Counter()
joint = collections.Counter()
for f in files:
    try:
        d = json.load(open(f))
    except Exception:
        continue
    dec = collections.defaultdict(set)
    for ev in d.get("events") or ():
        if ev.get("type") == "path_condition":
            dec[str(ev.get("expr") or "")].add(bool(ev.get("taken")))
    prof.add(hashlib.blake2b(json.dumps(
        sorted((k, sorted(v)) for k, v in dec.items())).encode(), digest_size=12).hexdigest())
    a = next((x for x in ACT if "(%s_text_empty == True)" % x in dec), None)
    hp3 = P3 in dec
    if hp3 and P2 in dec:
        p2p3 += 1
        if dec[P3] != dec[P2]:
            p2p3dis += 1
    if hp3 and a:
        both += 1
        byact[a] += 1
        av = dec["(%s_text_empty == True)" % a]
        joint[(tuple(sorted(dec[P3])), tuple(sorted(av)), a.split("_")[-2])] += 1
        if dec[P3] == av:
            agree += 1
        else:
            byact_dis[a] += 1
            dis.append((os.path.basename(f), a, sorted(dec[P3]), sorted(av)))
    elif hp3:
        p3only += 1
    elif a:
        actonly += 1
    else:
        neither += 1

print("distinct outcome profiles produced :", len(prof))
print("runs recording BOTH the render decision and an act _text_empty:", both)
print("   AGREE   ", agree)
print("   DISAGREE", len(dis))
print("runs recording only the render decision:", p3only)
print("runs recording only an act _text_empty:", actonly)
print("runs recording neither:", neither)
print("runs recording process_2 AND process_3:", p2p3, " disagreements:", p2p3dis,
      "  (§79 RENDER_IDENTITY, re-tested for free)")
print("\nper act finder: recorded / disagreements")
for a in ACT:
    print("   %-58s %6d %6d" % (a[-54:], byact[a], byact_dis[a]))
print("\nJOINT OUTCOME TABLE  (render P3 sides, act _text_empty sides, finder)")
for k, n in sorted(joint.items()):
    print("   render=%-14s act_text_empty=%-14s %-14s %6d" % (k[0], k[1], k[2], n))
for d in dis[:20]:
    print("   FALSIFIER:", d)
verdict = "PASS" if (not dis and both >= 200) else ("FAIL" if dis else "INCONCLUSIVE")
print("\nVERDICT %s (>=200 recording runs and 0 disagreements required)" % verdict)
json.dump({"dumps": len(files), "profiles": len(prof), "both": both,
           "agree": agree, "disagree": len(dis), "examples": dis[:20],
           "by_act": dict(byact), "joint": {str(k): v for k, v in joint.items()},
           "p2p3": p2p3, "p2p3_disagree": p2p3dis, "verdict": verdict},
          open(B + "/_p29_probe_explain.json", "w"), indent=1)
print("P29-PROBE-EXPLAIN-DONE")
