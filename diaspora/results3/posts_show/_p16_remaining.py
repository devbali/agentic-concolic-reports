#!/usr/bin/env python3
"""§79 — classify the witnesses that REMAIN in a checkpoint, per key.

For each witness (one per gap-set, MAX_MISSING_PER_CLIQUE=1) join every cube
literal to the P15 explain families and report:
  * which families the witness pins at all,
  * and — the number that decides what to do next — the family of the literal
    the last driven round could NOT make the run evaluate, per
    `_p15_explain_<TAG>.json`'s first-failing-literal where the gap is one the
    round drove.
usage: P16_CKPT=<ckpt> [P16_EXPLAIN=<explain.json>] python3 _p16_remaining.py
"""
import json, os, re, sys, collections
HERE = os.path.dirname(os.path.abspath(__file__))
# NOTE: _p15_explain.py calls main() at import time, so its family table is
# COPIED here verbatim rather than imported (importing it re-ran the P15A
# explanation and overwrote its artefact once — restored from the round-1
# archives; do not import that module).
_FAM = [(r"as_api_response_\d+_row_guid", "guid"),
        (r"^\(SYM_LEN_.*_rows != 0\)$", "length gate (rows)"),
        (r"^\(SYM_LEN_.*_ids != 0\)$", "length gate (ids)"),
        (r"_text_empty == True", "text (empty)"),
        (r"_text_has_mention == True", "text (has_mention)"),
        (r"find_by_\d+_not_found", "find_by not_found"),
        (r"findpublic_.*_not_found", "findpublic not_found"),
        (r"findpublic_.*_public == True", "public gate"),
        (r"_not_found == True", "evilq not_found"),
        (r"CollectionProxy_size_\d+_size", "size gate"),
        (r"Anonymous_process_\d+ == ''", "text (rendered)"),
        (r"assoc_profile_nsfw", "nsfw gate"),
        (r"Length\(SYM_PARAM_id\)", "param id length"),
        (r"_row_status_message_guid !=", "guid self-compare"),
        (r"_row_pending", "pending gate"),
        (r"_row_public", "public row gate")]


def family(e):
    for pat, name in _FAM:
        if re.search(pat, e):
            return name
    return "other"

CK = os.environ.get("P16_CKPT", os.path.join(HERE, "_cov_p16.ckpt.jsonl"))
EX = os.environ.get("P16_EXPLAIN", "")

wit = []
for l in open(CK):
    d = json.loads(l)
    if "v" not in d:
        continue
    for combo in d["v"]["combos"]:
        wit.append(combo)
print(f"{CK}: {len(wit)} witnesses")

RP = re.compile(r"SYM_RESULT_Anonymous_process_(\d+)")
cls = collections.Counter()
famset = collections.Counter()
for combo in wit:
    fams = collections.Counter(family(e) for e, o in combo)
    rl = sorted((RP.search(e).group(1), o) for e, o in combo if RP.search(e))
    if len(rl) == 2 and rl[0][1] != rl[1][1]:
        k = "A  render ordinals DISAGREE"
    elif len(rl) == 2:
        k = "A' render ordinals AGREE (pinned, both)"
    elif len(rl) == 1:
        k = "B  exactly one render ordinal pinned"
    else:
        k = "C  no render literal"
    cls[k] += 1
    famset[(k, " + ".join(sorted(f for f in fams if f in
            ("guid", "text (has_mention)", "text (empty)", "guid self-compare",
             "text (rendered)"))))] += 1
print()
for k, v in cls.most_common():
    print(f"  {v:5d}  {k}")
print("\n  by blocking-family signature (guid / has_mention / text_empty / self-compare / rendered):")
for (k, s), v in famset.most_common(25):
    print(f"  {v:5d}  {k:42s} {s}")

if EX and os.path.exists(EX):
    ex = json.load(open(EX))
    per = ex["per_gap"] if isinstance(ex, dict) and "per_gap" in ex else ex
    c = collections.Counter()
    for gid, r in (per.items() if isinstance(per, dict) else []):
        if r.get("walked"):
            continue
        fb = r.get("first_bad")
        if fb:
            c[(r.get("first_bad_v"), family(fb))] += 1
    print("\n  last round's FIRST FAILING LITERAL over the gaps it drove:")
    for (v, f), n in c.most_common(12):
        print(f"  {n:5d}  {v:16s} {f}")
