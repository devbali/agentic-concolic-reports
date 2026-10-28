#!/usr/bin/env python3
"""C7 family fingerprint scanner (batch-local analysis tool).

For each of the 13 core length vars in the C7 clique, scan raw dumps'
symbolic_vars entries: the `len(SYM_RESULT_...)` entries carry a SQL note
identifying the statement family. Indices are per-run CALL ORDINALS, so a
var like CollectionProxy_records_4 may map to different families in
different runs. This scanner builds the var -> family multiset.

Usage: python3 _c7_family_scan.py [max_dumps]
"""
import json, sys, glob, os, re, collections

BATCH = "/home/dev/project/reports/diaspora/results3/notifications_index"

CORE_LEN = [
    "len(SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_1_rows)",
    "len(SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2_rows)",
    "len(SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_3_rows)",
    "len(SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_4_rows)",
    "len(SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_5_rows)",
    "len(SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_6_rows)",
    "len(SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_7_rows)",
    "len(SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_8_rows)",
    "len(SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_11_rows)",
    "len(SYM_RESULT_ActiveRecord__Relation_to_ary_1_rows)",
    "len(SYM_RESULT_ActiveRecord__Relation_to_ary_1_row_actors_row_rows)",
    "len(SYM_RESULT_ActiveRecord__Relation_records_1_rows)",
    "len(SYM_RESULT_ActiveRecord__Relation_records_2_rows)",
]

# Family classifier: table name (or special marker) -> family
def classify(note):
    if not note:
        return "NO_NOTE"
    if note.startswith("preloaded association"):
        return "PRELOADED_NO_STMT"
    if "WALL" in note or "wall" in note.lower():
        return "WALL"
    m = re.search(r'FROM\s+"?(\w+)"?', note)
    if not m:
        return "NO_FROM:" + note[:60]
    t = m.group(1).lower()
    if t == "notifications":
        if "unread" in note:
            return "notifications_unread"
        return "notifications"
    if t == "notification_actors":
        return "actors"
    if t == "people":
        return "people"
    if t == "mentions":
        return "mentions_container"
    if t == "aspects":
        return "aspects"
    if t == "services":
        return "services"
    if t == "tag_followings":
        return "tags_tag_followings"
    if t == "tags":
        return "tags"
    if t == "contacts":
        return "contacts"
    if t == "roles":
        return "roles"
    if t == "aspect_memberships":
        return "aspect_memberships"
    if t == "posts":
        return "posts"
    if t == "profiles":
        return "profiles"
    if t == "photos":
        return "photos"
    return "TBL:" + t


def main():
    max_dumps = int(sys.argv[1]) if len(sys.argv) > 1 else 400
    files = sorted(glob.glob(os.path.join(BATCH, "dump_*.json")))
    print("total dumps on disk:", len(files))
    if max_dumps and max_dumps < len(files):
        files = files[:max_dumps]
    print("scanning", len(files), "dumps...")

    fam = collections.defaultdict(collections.Counter)   # var -> family counter
    note_ex = collections.defaultdict(list)              # var -> example notes
    per_dump = collections.defaultdict(collections.Counter)  # var -> # dumps containing it
    len_values = collections.defaultdict(list)           # var -> observed len values

    n_err = 0
    for fp in files:
        try:
            with open(fp) as f:
                d = json.load(f)
        except Exception as e:
            n_err += 1
            continue
        sv = d.get("symbolic_vars") or []
        seen = set()
        for v in sv:
            n = v.get("name", "")
            if n in CORE_LEN:
                seen.add(n)
                note = v.get("note", "")
                fam[n][classify(note)] += 1
                if len(note_ex[n]) < 3:
                    note_ex[n].append(note[:200])
                len_values[n].append(v.get("value"))
        for n in seen:
            per_dump[n]["dumps"] += 1

    print("\n=== var -> family multiset (over %d dumps) ===" % len(files))
    for n in CORE_LEN:
        total = sum(fam[n].values())
        top = fam[n].most_common()
        print("\n%s" % n)
        print("  occurrences: %d  (in %d dumps)" % (total, per_dump[n]["dumps"]))
        for f, c in top:
            print("    %-28s %d" % (f, c))
        vals = len_values[n]
        if vals:
            vc = collections.Counter(vals)
            print("  len value distribution (sample):", dict(vc.most_common(6)))
    print("\nparse errors:", n_err)

    # Save a compact json for downstream
    out = {
        "scanned_dumps": len(files),
        "var_family": {n: dict(fam[n]) for n in CORE_LEN},
        "example_notes": {n: note_ex[n] for n in CORE_LEN},
    }
    with open(os.path.join(BATCH, "_c7_family_scan_out.json"), "w") as f:
        json.dump(out, f, indent=1)
    print("\nwrote _c7_family_scan_out.json")


if __name__ == "__main__":
    main()