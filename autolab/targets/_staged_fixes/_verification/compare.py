#!/usr/bin/env python3
"""
compare.py — the SET differential over differential.rb's output.

Reads the JSON produced by differential.rb and reports, per case and in
aggregate:

  LOST        a statement the REAL run issued that NO note carries
  FABRICATED  a statement a note carries that the REAL run never issued

NORMALISATION — where the line is drawn, and why.

The real statement comes from `sql.active_record` with every value as a
bind placeholder `?`; a note carries values as `$$(SYM_x)` refs or as
literals.  Those differ harmlessly.  What must NOT be normalised away is
the COLUMN SET, the TABLE, the VERB, and the columns named in SET/WHERE —
those are exactly what D1 (a spurious `sharing` column), D2 (two missing
timestamp columns), D3/D4 (a missing or fabricated SET list) and D5 (the
wrong verb) are about.

So the normaliser:
  * lowercases and collapses whitespace                 (harmless)
  * drops table qualifiers:  "contacts"."receiving" -> "receiving"
    (AR writes the bare column in an INSERT/UPDATE SET and the qualified
    one in a WHERE; the note is not consistent either — this is style)
  * strips identifier quoting/backticks                 (style)
  * collapses VALUE tokens only — `?`, `$$(...)`, quoted strings, numbers,
    true/false/null — to a single `?`                   (bind style)
  * collapses a parenthesised list of placeholders `(?, ?, ?)` to `(?)`
    ONLY inside `IN (...)`, never inside an INSERT VALUES list, so an
    INSERT that names 5 columns can never compare equal to one naming 3
  * leaves every identifier, keyword, operator and the column order alone

Consequence, stated so it can be checked: two statements compare equal iff
they have the same verb, the same table, the same identifiers in the same
order, and the same ARITY of value lists.  A missing `created_at` column
changes the identifier sequence -> not equal.  A spurious `sharing` column
changes it -> not equal.  A SELECT vs an UPDATE -> not equal.
"""
import json
import re
import sys
from collections import defaultdict

# a value token: bind, symbolic ref, quoted string, number, boolean, null
_SYMREF = re.compile(r"\$\$\([^)]*\)")
_STR = re.compile(r"'(?:[^']|'')*'")
_NUM = re.compile(r"\b\d+(?:\.\d+)?\b")
_BOOLNULL = re.compile(r"\b(?:true|false|null)\b")
_QUOTED_ID = re.compile(r'[`"\[]([A-Za-z_][A-Za-z0-9_$]*)[`"\]]')
_QUALIFIED = re.compile(r"\b([A-Za-z_][A-Za-z0-9_$]*)\.([A-Za-z_][A-Za-z0-9_$]*)\b")
_IN_LIST = re.compile(r"\bin\s*\(\s*\?(?:\s*,\s*\?)*\s*\)")
_COMMENT = re.compile(r"/\*.*?\*/", re.S)


def normalize(sql):
    s = str(sql or "")
    s = _COMMENT.sub(" ", s)
    s = _SYMREF.sub("?", s)  # symbolic ref -> placeholder
    s = _QUOTED_ID.sub(r"\1", s)  # "contacts" -> contacts
    s = _STR.sub("?", s)  # 'f' -> ?
    s = s.lower()
    s = _QUALIFIED.sub(r"\2", s)  # contacts.receiving -> receiving
    s = _BOOLNULL.sub("?", s)
    s = _NUM.sub("?", s)
    s = re.sub(r"\s+", " ", s).strip().rstrip(";")
    s = _IN_LIST.sub("in (?)", s)  # IN-list arity is not a column set
    s = re.sub(r"\s*([(),])\s*", r"\1", s)
    return s


DML = ("SELECT", "INSERT", "UPDATE", "DELETE", "WITH", "REPLACE")


def is_dml(s):
    return str(s or "").lstrip().upper().startswith(DML)


def note_statements(note):
    """A note may legitimately carry SEVERAL statements (a destroy cascade, an
    autosave INSERT alongside the owner's).  They are separated by ';\\n'."""
    out = []
    for part in re.split(r";\s*\n", str(note or "")):
        part = part.strip().rstrip(";").strip()
        if part and is_dml(part):
            out.append(part)
    return out


def analyse(path, dml_only=True):
    d = json.load(open(path))
    cases = d["cases"]
    lost_agg, fab_agg, ok_agg = [], [], []
    per_case = []
    for c in cases:
        if "real" not in c:
            continue
        real = [s for s in c["real"] if (is_dml(s) if dml_only else True)]
        if dml_only:
            real = [s for s in real if not s.lstrip().upper().startswith("SELECT")] \
                if c.get("_writes_only") else real
        notes = c.get("notes") or []
        recorded = []
        for tgt, n in notes:
            for st in note_statements(n):
                recorded.append((tgt, st))
        rn = {normalize(s) for _t, s in recorded}
        realn = defaultdict(list)
        for s in real:
            realn[normalize(s)].append(s)
        lost = [(k, v[0]) for k, v in realn.items() if k not in rn]
        fab = [(normalize(s), s, t) for t, s in recorded if normalize(s) not in realn]

        # VALIDATION-BLOCKED, not fabricated.
        #
        # A write scenario whose REAL run issued validation SELECTs and then
        # no write at all did not "issue nothing"; ActiveRecord DECIDED not
        # to, because a validation failed on the junk fixture row. The mock
        # models the SUCCESS arm on purpose (`<name>_<op>_ok` is seeded true
        # and stays a flippable decision), so counting its note as a
        # fabrication would be scoring the mock against an arm it is not
        # claiming. These are reported in their own bucket and NEVER folded
        # into either side: tuning them away would be the exact failure the
        # brief warns about, and hiding them would be worse.
        WRITE_SCENARIOS = ("save_new", "save_changed", "update",
                           "update_attribute", "proxy_create",
                           "autosave_collection")
        def _head(x):
            return str(x).strip().split(None, 1)[0].upper().lstrip("(")
        real_writes = [s for s in real if _head(s) not in ("SELECT", "WITH")]
        real_reads = [s for s in real if _head(s) in ("SELECT", "WITH")]
        blocked = (c["scenario"] in WRITE_SCENARIOS and not real_writes
                   and (real_reads or "raised" in str(c.get("real_status"))))
        if blocked:
            fab_blocked = [x for x in fab if _head(x[1]) not in ("SELECT", "WITH")]
            fab = [x for x in fab if _head(x[1]) in ("SELECT", "WITH")]
        else:
            fab_blocked = []
        rec = {
            "model": c["model"], "scenario": c["scenario"],
            "real_status": c.get("real_status"), "mock_status": c.get("mock_status"),
            "n_real": len(real), "n_recorded": len(recorded),
            "lost": lost, "fabricated": fab, "blocked": fab_blocked,
            "validation_blocked": bool(blocked),
            "real_all": real, "recorded_all": recorded,
        }
        per_case.append(rec)
        lost_agg += [x[1] for x in lost]
        fab_agg += [x[1] for x in fab]
        if not lost and not fab and real:
            ok_agg.append((c["model"], c["scenario"]))
    return d, per_case, lost_agg, fab_agg, ok_agg


def main():
    path = sys.argv[1]
    verbose = "-v" in sys.argv
    d, per_case, lost, fab, ok = analyse(path)
    nb = len([c for c in per_case if c["n_real"]])
    print(f"== {path}  stack={d['stack']} env={d['rails_env']} AR={d['ar']}")
    print(f"   cases with at least one real statement: {nb}")
    print(f"   cases fully MATCHED (no lost, no fabricated): {len(ok)}")
    print(f"   LOST statements (real, carried by no note): {len(lost)}")
    print(f"   FABRICATED statements (noted, never issued): {len(fab)}")

    def shape(s):
        s = normalize(s)
        return re.sub(r"\b(where|values|set)\b.*", r"\1 ...", s)[:120]

    agg = defaultdict(int)
    for s in lost:
        agg[shape(s)] += 1
    print(f"\n-- LOST by shape ({len(agg)} shapes) --")
    for k, v in sorted(agg.items(), key=lambda x: -x[1]):
        print(f"  {v:5d}  {k}")
    agg = defaultdict(int)
    for s in fab:
        agg[shape(s)] += 1
    print(f"\n-- FABRICATED by shape ({len(agg)} shapes) --")
    for k, v in sorted(agg.items(), key=lambda x: -x[1]):
        print(f"  {v:5d}  {k}")

    print("\n-- per scenario --")
    byscen = defaultdict(lambda: [0, 0, 0, 0])
    for c in per_case:
        b = byscen[c["scenario"]]
        b[0] += 1
        b[1] += len(c["lost"])
        b[2] += len(c["fabricated"])
        b[3] += 1 if (not c["lost"] and not c["fabricated"] and c["n_real"]) else 0
    print(f"  {'scenario':22s} {'cases':>6s} {'lost':>6s} {'fabr':>6s} {'clean':>6s}")
    for s, b in sorted(byscen.items()):
        print(f"  {s:22s} {b[0]:6d} {b[1]:6d} {b[2]:6d} {b[3]:6d}")

    if verbose:
        print("\n-- per case detail --")
        for c in per_case:
            if not c["lost"] and not c["fabricated"]:
                continue
            print(f"\n  {c['model']}.{c['scenario']}  real={c['real_status']} mock={c['mock_status']}")
            for s in c["real_all"]:
                print(f"      REAL  {s[:160]}")
            for t, s in c["recorded_all"]:
                print(f"      NOTE  [{t}] {s[:160]}")
            for _k, s in c["lost"]:
                print(f"      LOST  {s[:160]}")
            for _k, s, t in c["fabricated"]:
                print(f"      FABR  [{t}] {s[:160]}")


if __name__ == "__main__":
    main()
