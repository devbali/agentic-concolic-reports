#!/usr/bin/env python3
"""Replace every TODO(drive) in POLICY_HEADER.txt with a MEASURED fact.

Inputs, all of which must exist — this script FAILS rather than shipping a
header with a TODO or a guessed number:
  coverage_summary.json                    the final pass's own verdict
  ../queries_from_runs/_summary_posts_show.json   the shipped extraction
  _residual_classes.json                   the four residual classes (§76.2)
Writes POLICY_HEADER.txt in place (a .pre_fill backup first).
"""
import json, os, shutil, sys
HERE = os.path.dirname(os.path.abspath(__file__))
Q = "/home/dev/project/reports/diaspora/results3/queries_from_runs"
P = os.path.join(HERE, "POLICY_HEADER.txt")

def need(p):
    if not os.path.exists(p):
        sys.exit(f"REFUSING to fill the header: {p} does not exist")
    return json.load(open(p))

# THE PASS THIS HEADER QUOTES. Preference order, and the header SAYS which one
# it got — a verdict from a different population is not the same fact as a
# verdict from this one, and the difference may not be silent.
#   1. coverage_summary.json  — tonight's pass on the CURRENT population
#   2. _cov_p2_pins.json      — the last pass that completed on this endpoint
#                               (2026-09-11 01:58, the 14 806-profile p2 list)
_cur = os.path.join(HERE, "coverage_summary.json")
if os.path.exists(_cur):
    cov = json.load(open(_cur))
    COV_SRC = ("tonight's pass on THIS population", "coverage_summary.json", True)
else:
    cov = need(os.path.join(HERE, "_cov_p2_pins.json"))
    COV_SRC = ("the LAST PASS THAT COMPLETED on this endpoint, on an EARLIER "
               "population", "_cov_p2_pins.json / _covB2_p2_20260910.log", False)
ext = need(os.path.join(Q, "_summary_posts_show.json"))["posts_show"]
res = need(os.path.join(HERE, "_residual_classes.json"))

def g(d, *ks, default="n/a"):
    for k in ks:
        if isinstance(d, dict) and k in d:
            d = d[k]
        else:
            return default
    return d

ov = cov.get("complete")
comp = g(cov, "completion", "complete")
lines = []
A = lines.append
A("-- ============================================================================")
A("-- STANDING OF THIS FILE  (READ THIS BEFORE USING IT)")
A("-- ============================================================================")
A("-- THE ENGINE VERDICT THIS FILE QUOTES, verbatim, and WHICH PASS IT IS:")
A(f"--   source: {COV_SRC[0]}")
A(f"--   file  : {COV_SRC[1]}")
if COV_SRC[2]:
    A(f"-- Run {res['pass_date']} with the shipped engine (coverage.py md5")
    A(f"-- {res['engine_md5']}), OR-monotone confinement ON, on the pruned")
    A(f"-- DUMP_LIST of {res['snapshot_profiles']} outcome profiles of {res['corpus_dumps']} dumps.")
else:
    A("-- ** NO PASS COULD BE RUN ON THE CURRENT POPULATION. ** The box was")
    A("-- memory-constrained all night by an editor language server outside the")
    A("-- experiment's cgroup (~6 GB and growing); the coordinator lowered the")
    A("-- cage to MemoryMax=4G/MemoryHigh=3G at 19:4x and nothing over ~3 G")
    A("-- could be launched. The pass is QUEUED behind a `free -g >= 6` gate")
    A("-- (_p13c.sh) and will produce the verdict for this population when the")
    A("-- box returns. The verdict below is therefore from an EARLIER, SMALLER")
    A(f"-- population ({cov.get('total_runs')} runs), not from the {res['corpus_dumps']}-dump")
    A("-- corpus this file is extracted from. It is quoted because a real")
    A("-- verdict from a named population is a fact; a blank is not.")
A("--")
A(f"--     OVERALL_COMPLETE={ov}")
A(f"--     COMPLETION={comp}")
A(f"--     COMPLETE={g(cov,'complete_coverage', default=g(cov,'coverage','complete'))}"
  f"  NODES={g(cov,'nodes')}  MISSING={g(cov,'missing')}"
  f"  BLOCKING={g(cov,'blocking_count', default=len(g(cov,'blocking',default=[]) or []))}")
A(f"--     GENUINE={g(cov,'genuine')}  TRUNCATED={g(cov,'truncated')}"
  f"  SOLVER_LOST={g(cov,'solver_lost')}  UNEVALUABLE={g(cov,'unevaluable')}")
A("--")
A("-- **`OVERALL_COMPLETE` IS THE LINE ABOVE AND IT IS NOT `True`.** What stands")
A("-- between this endpoint and a `True` is a MEASURED residual, in four classes,")
A("-- each with its own number and its own reason (_COMPLETION_20260910.md §76):")
A("--")
for k in res["classes"]:
    c = res["classes"][k]
    A(f"--   ({k}) {c['name']}")
    for l in c["lines"]:
        A(f"--       {l}")
A("--")
A("-- NONE of the four is closed by extracting this file; they bound what the")
A("-- CHECKER can assert about the corpus, not what the statements below say.")
lines_std = "\n".join(lines)

ex = []
B = ex.append
B("-- ============================================================================")
B("-- EXTRACTION STANDING")
B("-- ============================================================================")
B(f"-- FULL-CORPUS extraction of {res['extract_date']} — not a sample.")
B(f"--   dumps                 {ext['n_dumps']}   (runs loaded {ext['n_runs_loaded']})")
B(f"--   views                 {ext['n_queries_final']}   "
  f"({ext['n_queries_raw']} raw -> {ext['n_queries_deduped']} distinct"
  f" -> {ext['n_queries_final']} after subsumption)")
_unp = [e for e in (ext.get("errors") or []) if "unparseable note" in e]
B(f"--   unparseable notes     {len(_unp)}     (E11 RED "
  f"{'FIRED — see the log' if _unp else 'silent'})")
_rot = res.get("rotation_residue", 0)
B(f"--   rotation residue      {_rot}     (R1 RED {'FIRED' if _rot else 'silent'})")
ph = list(ext.get("placeholders") or ())
B(f"--   placeholders          {len(ph)} families, NAMED:")
for p in ph:
    B(f"--                           {p}")
B(f"--   flags                 " + ", ".join(f"{k} {v}" for k, v in
                                            sorted((ext.get("flags") or {}).items())))
st = ext.get("subsume_state", ext.get("subsume_ran"))
B(f"--   subsumption           state={st!r}  "
  f"(True=ran, False=attempted and FAILED, None=never attempted)")
B(f"--                         verdict tally  subsumed(true)={res['subsume_true']}"
  f"  not-subsumed(false)={res['subsume_false']}"
  f"  UNDECIDED(null)={res['subsume_null']}")
B(f"--                         {res['subsume_note']}")
lines_ext = "\n".join(ex)

s = open(P).read()
shutil.copy(P, P + ".pre_fill_20260911")

# 1. the TEMPLATE banner goes: this is now a closed-endpoint header.
i = s.find("-- ####")
j = s.rfind("-- ####")
if i != -1 and j != -1:
    s = s[:i] + s[j + len(s[j:].split("\n")[0]) + 1:]

def cut(text, start_marker, end_marker):
    a = text.index(start_marker)
    b = text.index(end_marker, a)
    return a, b

a, b = cut(s, "-- ============================================================================\n-- STANDING OF THIS FILE",
           "-- THE NAMED DEFECT:")
s = s[:a] + lines_std + "\n--\n" + s[b:]
a, b = cut(s, "-- ============================================================================\n-- EXTRACTION STANDING",
           "-- ============================================================================\n-- DECLARED WALLS")
s = s[:a] + lines_ext + "\n--\n" + s[b:]
open(P, "w").write(s)
left = s.count("TODO(drive)")
print(f"header filled; TODO(drive) remaining: {left}")
if left:
    sys.exit(f"REFUSING: {left} TODO(drive) still in POLICY_HEADER.txt")
print("FILL HEADER DONE")
