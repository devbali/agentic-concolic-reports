#!/usr/bin/env python3
"""P29 — classify a pass's MISSING WITNESSES by decision family, so two passes
can be compared per class. Reads the step-6 coverage checkpoint (where the
witnesses live) exactly as §79.4 read them."""
import json, os, re, sys, collections

B = os.path.dirname(os.path.abspath(__file__))
_FAM = [(r"as_api_response_\d+_row_guid", "guid"),
        (r"SYM_LEN_.*_comments_[0-9a-f]{8}_rows != 0", "length gate: comments"),
        (r"SYM_LEN_.*_mentions_[0-9a-f]{8}_rows != 0", "length gate: mentions"),
        (r"SYM_LEN_.*_photos_[0-9a-f]{8}_rows != 0", "length gate: photos"),
        (r"SYM_LEN_.*_rows != 0", "length gate: other"),
        (r"SYM_LEN_.*_ids != 0", "length gate (ids)"),
        (r"Anonymous_process_\d+ == ''", "text (rendered)"),
        (r"_text_empty == True", "text (empty)"),
        (r"_text_has_mention == True", "text (has_mention)"),
        (r"find_by_\d+_not_found", "find_by not_found"),
        (r"findpublic_.*_not_found", "findpublic not_found"),
        (r"findpublic_.*_public == True", "public gate"),
        (r"_not_found == True", "evilq not_found"),
        (r"CollectionProxy_size_\d+_size", "size gate"),
        (r"assoc_profile_nsfw", "nsfw gate"),
        (r"Length\(SYM_PARAM_id\)", "param id length"),
        (r"_row_status_message_guid !=", "guid self-compare")]


def fam(e):
    for p, n in _FAM:
        if re.search(p, e):
            return n
    return "other"


def classify(path):
    tot = 0
    lit = collections.Counter()
    hasfam = collections.Counter()
    render = collections.Counter()
    for line in open(path):
        try:
            r = json.loads(line)
        except Exception:
            continue
        v = r.get("v")
        if not isinstance(v, dict):
            continue
        for combo in v.get("combos") or ():
            tot += 1
            fams = set()
            rl = []
            for e, o in combo:
                f = fam(e)
                lit[f] += 1
                fams.add(f)
                if f == "text (rendered)":
                    rl.append(o)
            for f in fams:
                hasfam[f] += 1
            render[tuple(sorted(rl))] += 1
    return tot, lit, hasfam, render


for p in sys.argv[1:]:
    tot, lit, hasfam, render = classify(p)
    print("\n=== %s   witnesses(combos)=%d" % (os.path.basename(p), tot))
    print("  witnesses CONTAINING a literal of family:")
    for f, n in hasfam.most_common():
        print("     %-28s %6d   (literals %d)" % (f, n, lit[f]))
    print("  render literals per witness:", dict(render.most_common(6)))
