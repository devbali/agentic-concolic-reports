#!/usr/bin/env python3
"""C7 family fingerprint scanner v2 (batch-local analysis tool).

Scans ALL len(SYM_RESULT_..._rows) vars in raw dumps, classifies each by its
SQL note (statement family), and reports:
  - the 13 core vars -> family multiset (indices are per-run call ordinals)
  - the full universe of len vars (to see the "13 + 1 extra" signatures)
  - len value polarity per core var (for the H4 question)

Usage: python /path/_c7_family_scan2.py [max_dumps]
"""
import json, sys, glob, os, re, collections

BATCH = "/home/dev/project/reports/diaspora/results3/notifications_index"

CORE_STEMS = [
    "SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_1",
    "SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_2",
    "SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_3",
    "SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_4",
    "SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_5",
    "SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_6",
    "SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_7",
    "SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_8",
    "SYM_RESULT_ActiveRecord__Associations__CollectionProxy_records_11",
    "SYM_RESULT_ActiveRecord__Relation_to_ary_1",
    "SYM_RESULT_ActiveRecord__Relation_to_ary_1_row_actors_row",
    "SYM_RESULT_ActiveRecord__Relation_records_1",
    "SYM_RESULT_ActiveRecord__Relation_records_2",
]


def classify(note):
    if not note:
        return "NO_NOTE"
    if note.startswith("preloaded association"):
        return "PRELOADED_NO_STMT"
    if "WALL" in note:
        return "WALL"
    m = re.search(r'FROM\s+"?(\w+)"?', note)
    if not m:
        return "NO_FROM:" + note[:60]
    t = m.group(1).lower()
    if t == "notifications":
        return "notifications_unread" if "unread" in note else "notifications"
    if t == "notification_actors":
        return "actors"
    if t == "people":
        return "people"
    if t == "mentions":
        return "mentions_container"
    if t == "aspects":
        return "aspects"
    if t == "aspect_memberships":
        return "aspect_memberships"
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
    if t == "posts":
        return "posts"
    if t == "profiles":
        return "profiles"
    if t == "photos":
        return "photos"
    if t == "users":
        return "users"
    return "TBL:" + t


LEN_RE = re.compile(r'^len\((SYM_RESULT_[^(]+)_rows\)$')


def main():
    max_dumps = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    files = sorted(glob.glob(os.path.join(BATCH, "dump_*.json")))
    total_files = len(files)
    if max_dumps and max_dumps < total_files:
        files = files[:max_dumps]
    print("scanning", len(files), "of", total_files, "dumps...")

    fam = collections.defaultdict(collections.Counter)     # stem -> family counter
    note_ex = collections.defaultdict(list)                # stem -> example notes
    len_vals = collections.defaultdict(collections.Counter)  # stem -> value counter
    stem_pres = collections.defaultdict(int)               # stem -> # dumps
    all_families = collections.Counter()
    n_err = 0

    for fp in files:
        try:
            with open(fp) as f:
                d = json.load(f)
        except Exception:
            n_err += 1
            continue
        sv = d.get("symbolic_vars") or []
        seen = set()
        for v in sv:
            n = v.get("name", "")
            m = LEN_RE.match(n)
            if not m:
                continue
            stem = m.group(1)
            seen.add(stem)
            f = classify(v.get("note", ""))
            all_families[f] += 1
            fam[stem][f] += 1
            if len(note_ex[stem]) < 2:
                note_ex[stem].append(v.get("note", "")[:220])
            len_vals[stem][v.get("value")] += 1
        for s in seen:
            stem_pres[s] += 1

    print("\n=== family universe (all len vars) ===")
    for f, c in all_families.most_common():
        print("  %-28s %d" % (f, c))

    print("\n=== CORE vars -> family multiset ===")
    for stem in CORE_STEMS:
        tot = sum(fam[stem].values())
        print("\n%s" % stem)
        print("  occurrences: %d  in %d dumps" % (tot, stem_pres[stem]))
        if len_vals[stem]:
            print("  len value distribution:", dict(len_vals[stem].most_common(8)))
        for f, c in fam[stem].most_common() if False else fam[stem].most_common():
            print("    %-28s %d" % (f, c))
        if note_ex[stem]:
            print("  example note[0]:", note_ex[stem][0][:180])

    print("\n=== NON-core len stems seen (top 40 by dump-presence) ===")
    core_set = set(CORE_STEMS)
    for s, c in sorted(stem_pres.items(), key=lambda kv: -kv[1])[:40]:
        if s not in core_set:
            fs = "/".join(sorted(fam[s]))
            print("  %-90s dumps=%4d fam=%s" % (s, c, fs))

    out = {
        "scanned_dumps": len(files),
        "core_family": {s: dict(fam[s]) for s in CORE_STEMS},
        "core_values": {s: dict(len_vals[s]) for s in CORE_STEMS},
        "example_notes": {s: note_ex[s] for s in CORE_STEMS},
        "noncore": {s: dict(fam[s]) for s in stem_pres if s not in core_set},
    }
    with open(os.path.join(BATCH, "_c7_family_scan2_out.json"), "w") as f:
        json.dump(out, f, indent=1)
    print("\nwrote _c7_family_scan2_out.json")


if __name__ == "__main__":
    main()