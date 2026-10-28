import json, glob, re, collections
B = "/home/dev/project/reports/diaspora/results3/notifications_index"
pat = re.compile(r'^len\((SYM_RESULT_[^(]+)_rows\)$')
counts = collections.Counter()
multi = 0
findby_notes = collections.defaultdict(list)
ndump = 0
for fp in sorted(glob.glob(B + "/dump_*.json"))[:800]:
    try:
        with open(fp) as f: d = json.load(f)
    except Exception:
        continue
    ndump += 1
    m2 = collections.defaultdict(set)
    for v in d.get("symbolic_vars") or []:
        nm = v.get("name", "")
        m = pat.match(nm)
        if not m:
            continue
        stem = m.group(1)
        if ("CollectionProxy_records" in stem or "Relation_to_ary_1" in stem
                or "Relation_records" in stem or "find_by" in stem):
            note = v.get("note", "")
            mm = re.search(r'FROM\s+"?(\w+)"?', note)
            fam = mm.group(1) if mm else "NONE"
            m2[stem].add(fam)
            if "find_by" in stem and note and len(findby_notes[stem]) < 3:
                findby_notes[stem].append((note[:160], fp.split("/")[-1]))
    for stem, fams in m2.items():
        counts[stem] += 1
        if len(fams) > 1:
            multi += 1
            if multi <= 8:
                print("MULTI:", stem, fams, fp.split("/")[-1])
print("dumps scanned:", ndump)
print("stems with >1 family within ONE dump:", multi)
print()
print("=== find_by notes (sample) ===")
for stem, lst in sorted(findby_notes.items()):
    print(stem, "->", len(lst))
    for note, fp in lst[:2]:
        print("   ", note, "<", fp, ">")