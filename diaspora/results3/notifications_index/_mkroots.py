#!/usr/bin/env python3
"""Build ONE roots file per variant from the corpus's OWN variable names.

Why: a JRuby LAUNCH costs ~2.3 minutes (boot + app load) while the exploration
itself costs ~10 seconds, so the generation plan is launch-bound. The suffix
scenarios (`SEED_SUFFIXES`) are env-level — one scenario per launch — which is
what made the plan 131 launches. A suffix scenario only ever means "seed the
DIMENSION whatever call ordinal carries it", and the ordinals are now KNOWN:
they are in the corpus. So expand every suffix scenario into exact-name
assignments against the corpus's variable table, cross them with the context
roots (type dispatch, list lengths), and hand the whole product to ONE launch
per variant as EXTRA_SEEDS_JSON roots.
"""
import glob, json, os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
VARIANTS = ("html_plain", "html_typed", "json_plain", "json_typed",
            "mobile_plain", "mobile_typed", "xml_plain")

SUFFIX_SCENARIOS = [
    {"_disp_has_dlink": True},
    {"_text_has_dlink": True},
    {"_rows)": 3},
    {"_rows)": 3, "_text_has_mention": True},
    {"_rows)": 3, "_persisted": True, "_text_nil": True},
    {"_rows)": 0, "_text_nil": True},
    {"_rows)": 0, "_guid": ""},
    {"_rows)": 1, "_guid": "gg", "_persisted": False},
    {"_persisted": False, "_guid": ""},
    {"_person_id": 77, "_persisted": True},
    {"_person_id": 77, "_persisted": False},
    {"_target_is_photo": True, "_text_nil": True},
    {"_not_found": True},
    {"_profile_not_found": True},
    {"_profile_not_found": True, "_text_nil": True},
    {"_row_person_not_found": True},
    {"_status_message_not_found": True, "_target_is_photo": True},
    {"_recipient_not_found": True},
    {"_target_author_not_found": True, "_target_is_photo": True},
    {"_profile_first_name": "", "_profile_last_name": ""},
    {"_profile_first_name": "", "_public_details": True},
    {"_row_first_name": "", "_row_last_name": "", "_guid": ""},
    {"_text_has_mention": True, "_mention_inline_name": True},
    {"_text_has_mention": True, "_mention_inline_name": False, "_persisted": True},
    {"_birthday_year": 900, "_public_details": True},
    {"_disp_has_dlink": True, "_sharing": True},
    {"_disp_has_dlink": True, "_sharing": False},
    {"_stale_language": True},
    {"_target_not_found": True, "_text_has_mention": True},
    {"_public_details": True, "_birthday_year": 900, "_profile_first_name": ""},
    {"_text_dlink_is_post": False, "_text_has_dlink": True},
    {"_disp_dlink_is_post": False, "_disp_has_dlink": True},
    {"_exists": True},
    {"_sharing": True, "_receiving": True},
]

# every variable name the corpus has minted (and every seed key it has used)
names = set()
for p in sorted(glob.glob(os.path.join(HERE, "dump_*.json"))):
    try:
        d = json.load(open(p))
    except Exception:
        continue
    for sv in d.get("symbolic_vars") or ():
        n = sv.get("name")
        if n:
            names.add(n)
    for k in (d.get("concolic_seeds") or {}):
        names.add(k)
print(f"corpus variable names: {len(names)}")


def expand(scn):
    """suffix map -> exact-name assignment over every matching variable."""
    out = {}
    for suf, val in scn.items():
        pat = suf[:-1] if suf.endswith(")") else suf   # "_rows)" -> "_rows"
        hits = [n for n in names if n.endswith(pat) or n.endswith(pat + ")")]
        for n in hits:
            out[n] = val
    return out


def load(fn):
    p = os.path.join(HERE, fn)
    return json.load(open(p)) if os.path.exists(p) else []


contexts = []
for k in range(8):
    contexts += load(f"_seed_type{k}.json")
contexts += load("_seed_dims.json")
contexts += load("_seed_multirow.json")
contexts.append({})
print(f"context roots: {len(contexts)}")

roots, seen = [], set()
for scn in SUFFIX_SCENARIOS:
    ex = expand(scn)
    if not ex:
        print(f"  (no corpus variable matches {scn})")
        continue
    for ctx in contexts:
        r = dict(ctx)
        r.update(ex)
        key = json.dumps(r, sort_keys=True)
        if key in seen:
            continue
        seen.add(key)
        roots.append(r)
# the context roots on their own, too
for ctx in contexts:
    key = json.dumps(ctx, sort_keys=True)
    if key not in seen and ctx:
        seen.add(key)
        roots.append(ctx)
out = os.path.join(HERE, "_roots6.json")
json.dump(roots, open(out, "w"))
print(f"wrote {out}: {len(roots)} roots")
