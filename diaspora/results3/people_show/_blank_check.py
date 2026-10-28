import json, glob

corpus = "reports/diaspora/results3/people_show/dump_*.json"
runs = []
for f in sorted(glob.glob(corpus)):
    try:
        runs.append(json.load(open(f)))
    except Exception:
        pass

# handle blank shapes only (split-crash family)
HANDLE_BLANKS = [
    "SubString(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle, 0, 1) == ''",
    "SubString(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle, 0, 2) == ''",
    "SubString(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle, 0, Length(SYM_RESULT_ActiveRecord__FinderMethods_first_1_diaspora_handle) - 0) == ''",
    "SubString(SYM_PERSON_via_user_diaspora_handle, 0, 1) == ''",
    "SubString(SYM_PERSON_via_user_diaspora_handle, 0, 2) == ''",
    "SubString(SYM_PERSON_via_user_diaspora_handle, 0, Length(SYM_PERSON_via_user_diaspora_handle) - 0) == ''",
]

taken = 0
not_taken = 0
taken_samples = []
for d in runs:
    for ev in d.get("events", []):
        if ev.get("type") != "path_condition":
            continue
        e = ev.get("expr", "")
        if any(h in e for h in HANDLE_BLANKS):
            if ev.get("taken"):
                taken += 1
                if len(taken_samples) < 3:
                    taken_samples.append((d.get("label"), e[:100]))
            else:
                not_taken += 1
            break
print("handle-blank T (empty) runs:", taken)
print("handle-blank F (non-empty) runs:", not_taken)
for s in taken_samples:
    print("  T sample:", s)

# error dumps (split crash evidence)
errs = {}
for d in runs:
    e = d.get("error") or {}
    t = e.get("type", "none")
    errs[t] = errs.get(t, 0) + 1
print("dump errors:", errs)

# empty-handle symbolic vars among error dumps
empty_handle_err = 0
for d in runs:
    e = d.get("error") or {}
    if "Template" in e.get("type", ""):
        for v in d.get("symbolic_vars", []):
            if "diaspora_handle" in v.get("name", "") and v.get("value") == "":
                empty_handle_err += 1
                break
print("Template::Error dumps with empty handle seed:", empty_handle_err)