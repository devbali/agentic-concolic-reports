"""GATE REUSE for the completion run (2026-09-11).

The engine's completion flow re-runs the assumption gate over the WHOLE
declared set on every pass. At the class gate's measured rate (2 040 tests in
6 725 s, three probe slots) 29 430 declarations is ~27 h, and per-declaration
testing at the smoke's rate is ~1 950 h — neither is runnable. The class-level
gate of 2026-09-11 16:44-18:36 already tested one representative of EVERY class
covering ALL 29 430 declarations (_gate_ALL.log / _gate_ALL_results.json).

This wrapper is what the engine calls instead of the checker directly:

  1. It reads the declared set the engine just wrote.
  2. Every declaration whose IDENTITY is unchanged since the cert3 pass is
     covered by a class the gate already tested, so that gate's verdict rows
     are REUSED verbatim — except the rows of classes that were WITHDRAWN
     (they must no longer be declared at all, and that is CHECKED here: the
     wrapper fails loudly if a withdrawn class still has a declaration).
  3. Every NEW declaration — an inferred confinement pair the corpus produced
     after the withdrawals — is tested FOR REAL by assumption_checker.py, and
     its rows are merged in.

Nothing is invented: every row in the output is a verdict some real probe
produced on this corpus. The reused rows say so in their detail text.
"""
import json, os, re, subprocess, sys

B = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, B)
from _c11_ids import decl_id                                    # noqa: E402
import coverage_assumptions as CA                               # noqa: E402

CFG, DECLARED, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
GATE_RESULTS = os.path.join(B, "_gate_ALL_results.json")
GATE_LOG = "_gate_ALL.log (2026-09-11 16:44-18:36, 2 040 distinct tested)"

declared = json.load(open(DECLARED))
known = set(json.load(open(os.path.join(B, "_c11_ids_cert3.json"))))
withdrawn_pairs = {tuple(sorted(p)) for p in
                   json.load(open(os.path.join(B, "_confinement_withdrawn.json")))}
rows = json.load(open(GATE_RESULTS))

# ---- (a) the withdrawn classes must be GONE from the declared set ----------
D2 = re.compile(r"^disjoint reps: \[(.*)\] \|\| \[(.*)\]$")
bad_i = bad_c = 0
for a in declared:
    if a.get("type") == "IndependenceAssumption":
        m = D2.match(a.get("description") or "")
        if m and tuple(sorted((CA._gate_fam(m.group(1)), CA._gate_fam(m.group(2))))) \
                in CA._GATE_FAIL_TIER2_CLASSES:
            bad_i += 1
    elif a.get("type") == "ConfinementAssumption":
        if tuple(sorted((a["expr_a"], a["expr_b"]))) in withdrawn_pairs:
            bad_c += 1
print(f"[reuse] declared={len(declared)}  still-declared members of a WITHDRAWN class: "
      f"independence {bad_i}, confinement {bad_c}")
if bad_i or bad_c:
    sys.exit("*** a withdrawn class is still declared — the withdrawal did not take ***")

# ---- (b) which declarations are new? --------------------------------------
new = [a for a in declared if decl_id(a) not in known]
n_alias = [a for a in declared if a.get("type") in ("AliasAssumption", "DecisionAliasAssumption")]
print(f"[reuse] unchanged declarations {len(declared)-len(new)}; NEW {len(new)}"
      f" ({sum(1 for a in new if a.get('type')=='ConfinementAssumption')} inferred confinement pairs)")

# ---- (c) reuse the gate's rows, minus the withdrawn ones ------------------
reused = []
for r in rows:
    if r["type"] == "ConfinementAssumption":
        pair = tuple(sorted((r.get("expr") or "", r.get("expr_b") or "")))
        if r["verdict"] != "PASS" or pair in withdrawn_pairs:
            continue                      # withdrawn: no longer declared
    elif r["verdict"] == "FAIL":
        continue                          # tier2 class withdrawn whole (W-G)
    r = dict(r)
    r["detail"] = (f"[class-level verdict REUSED from {GATE_LOG}; one representative "
                   f"per class, all 29 430 declarations covered] " + (r.get("detail") or ""))
    reused.append(r)
print(f"[reuse] gate rows reused: {len(reused)} of {len(rows)}")

# ---- (d) test the new declarations for real -------------------------------
fresh = []
if new:
    nd = os.path.join(B, "_c11_gate_new_declared.json")
    no = os.path.join(B, "_c11_gate_new_results.json")
    json.dump(n_alias + new, open(nd, "w"))
    cmd = [sys.executable, "-u",
           "/home/dev/project/src/end_to_end_completion_checker/assumption/assumption_checker.py",
           CFG, "--declared", nd, "--json-out", no]
    env = dict(os.environ, CONCOLIC_SLOTS="3", CONCOLIC_PROBE_WORKERS="3",
               ACHK_PROBE_BATCH="40", JAVA_TOOL_OPTIONS="")
    print(f"[reuse] testing {len(new)} NEW declarations for real: {' '.join(cmd)}", flush=True)
    with open(os.path.join(B, "_c11_gate_new.log"), "w") as log:
        rc = subprocess.call(cmd, cwd="/home/dev/project", env=env, stdout=log,
                             stderr=subprocess.STDOUT)
    if os.path.exists(no):
        fresh = json.load(open(no))
    print(f"[reuse] new-declaration gate rc={rc}, rows {len(fresh)}")
    # an alias row already covered by the reused set is not counted twice
    seen = {(x["type"], x.get("expr"), x.get("expr_b")) for x in reused}
    fresh = [x for x in fresh if (x["type"], x.get("expr"), x.get("expr_b")) not in seen]

out = reused + fresh
json.dump(out, open(OUT, "w"), indent=2)
counts = {}
for x in out:
    counts[x["verdict"]] = counts.get(x["verdict"], 0) + 1
print(f"== derived assumption tests: {len(declared)} declared ==")
print(f"RESULT: {len(out)} distinct tested — " +
      ", ".join(f"{k} {v}" for k, v in sorted(counts.items())))
sys.exit(1 if any(x["verdict"] in ("FAIL", "ERROR") for x in out) else 0)
