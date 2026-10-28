#!/usr/bin/env python3
"""test_inventory.py -- the inventory is internally consistent and not stale.

This is the companion to test/test_install.rb, which is the one that actually
installs the library. This file checks the PAPERWORK: that manifest, partition,
conflicts, candidates and registry agree with each other, and that regenerating
them from the corpus changes nothing. A stale manifest is a test failure here
rather than a surprise later.

Run:  /home/dev/project/venvs/queries_from_runs/bin/python3 test/test_inventory.py
"""
import collections
import json
import os
import shutil
import subprocess
import sys
import tempfile

LAB = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INV = os.path.join(LAB, "inventory")
PY = sys.executable

FAILS = []
N = 0


def check(name, cond, detail=""):
    global N
    N += 1
    if cond is True:
        print("  ok   %s" % name)
    else:
        FAILS.append("%s: %s" % (name, detail or cond))
        print("  FAIL %s: %s" % (name, detail or cond))


def load(n):
    return json.load(open(os.path.join(INV, n)))


def main():
    manifest = load("manifest.json")
    partition = load("partition.json")
    conflicts = load("conflicts.json")
    candidates = load("candidates.json")
    registry = json.load(open(os.path.join(LAB, "targets", "registry.json")))
    D = manifest["declarations"]

    print("\n== 1. manifest is self-consistent")
    core_rows = [d for d in D if d["layer"] == "core"]
    per_ep = collections.Counter(d["endpoint"] for d in core_rows)
    check("the core declares the same set in every endpoint",
          len(set(per_ep.values())) == 1, dict(per_ep))
    c = manifest["counts"]
    n_core = len({d["target"] for d in core_rows})
    check("core_declarations matches the rows",
          n_core == c["core_declarations"], "%d vs %d" % (n_core, c["core_declarations"]))
    check("core TF + core SHIM == core_declarations",
          c["core_target_function"] + c["core_shim"] == c["core_declarations"])
    check("every row has a kind of target_function or shim",
          all(d["kind"] in ("target_function", "shim") for d in D))
    check("every row has a non-empty type", all(bool(d["type"]) for d in D))
    check("declare_target_sites_total is the sum of the per-file counts",
          manifest["declare_target_sites_total"] ==
          sum(manifest["declare_target_sites"].values()),
          manifest["declare_target_sites_total"])
    check("statically resolvable + loop bound == total sites",
          manifest["declare_target_sites_statically_resolvable"] +
          manifest["declare_target_sites_loop_bound"] ==
          manifest["declare_target_sites_total"])
    # NOT pinned to a magic number -- the gold files change. What must hold is
    # that loop-bound sites EXIST, because they are the reason this manifest is
    # measured by installing rather than by parsing: their receiver and method
    # are block variables and nothing resolves them from the call site.
    check("there ARE loop-bound sites (a manifest built by parsing would miss them)",
          manifest["declare_target_sites_loop_bound"] > 0,
          manifest["declare_target_sites_loop_bound"])
    check("every loop-bound site is recorded individually",
          len(manifest["loop_bound_sites"]) ==
          manifest["declare_target_sites_loop_bound"])
    check("declarations exceed sites, because of those loops",
          n_core > manifest["declare_target_sites"][
              "reports/diaspora/results4/aspect_memberships_create/concolic_targets.rb"])

    print("\n== 2. `opaque` is an admission, never on a TARGET_FUNCTION")
    op = [d for d in D if d["type"].rstrip("?") == "opaque"]
    check("the corpus has opaque uses to check", len(op) > 0, len(op))
    bad = [d["target"] for d in op if d["kind"] != "shim"]
    check("every opaque is behind a SHIM", bad == [], bad)

    print("\n== 3. partition covers the corpus exactly")
    ptargets = {r["target"] for r in partition["targets"]}
    core_t = {d["target"] for d in D if d["layer"] == "core"}
    local_new = {d["target"] for d in D if d["layer"] == "local"
                 and not d["redeclares_core"]}
    check("partition assigns every core target", core_t <= ptargets,
          sorted(core_t - ptargets))
    check("partition assigns every locally-invented target", local_new <= ptargets,
          sorted(local_new - ptargets))
    check("partition assigns nothing that is not in the corpus",
          ptargets <= (core_t | local_new), sorted(ptargets - core_t - local_new))
    kinds = {d["target"]: d["kind"] for d in D}
    mism = [r["target"] for r in partition["targets"] if r["kind"] != kinds[r["target"]]]
    check("partition kinds match the manifest", mism == [], mism)
    tiers = {r["target"]: r["tier"] for r in partition["targets"]}
    check("every core-layer target is tier core",
          all(tiers[t] == "core" for t in core_t),
          [t for t in sorted(core_t) if tiers[t] != "core"])
    check("every tier is a declared tier",
          set(tiers.values()) <= set(partition["tiers"]),
          set(tiers.values()) - set(partition["tiers"]))
    check("every non-core tier row carries a rationale",
          all(r.get("rationale") for r in partition["targets"]))
    check("every core-eligible row names its blocker",
          all(r.get("blocker") for r in partition["targets"]
              if r["tier"] == "core-eligible"),
          [r["target"] for r in partition["targets"]
           if r["tier"] == "core-eligible" and not r.get("blocker")])

    print("\n== 4. the ruling holds: TF standard, SHIM mostly common")
    x = manifest["cross_endpoint"]
    check("no target function is unique to aspect_memberships_create",
          x["target_function"]["only_aspect_memberships_create"] == [],
          x["target_function"]["only_aspect_memberships_create"])
    check("every shared shim agrees on kind AND type",
          x["shim"]["in_both"] == x["shim"]["in_both_identical_kind_and_type"],
          "%d shared, %d identical" % (x["shim"]["in_both"],
                                       x["shim"]["in_both_identical_kind_and_type"]))
    check("exactly one target's kind disagrees across endpoints",
          x["kind_disagrees"] == ["User#blocks"], x["kind_disagrees"])
    check("exactly one target's type disagrees across endpoints",
          x["type_disagrees"] == ["ActiveRecord::FinderMethods#exists?"],
          x["type_disagrees"])

    print("\n== 5. conflicts.json enumerates, and rules where it takes a side")
    check("every C1 contract conflict carries a ruling",
          all(r.get("ruling") for r in conflicts["C1_contract"]))
    c1 = {r["target"] for r in conflicts["C1_contract"]}
    expect = set(x["kind_disagrees"]) | set(x["type_disagrees"])
    check("C1 is exactly the measured disagreements", c1 == expect,
          sorted(c1 ^ expect))
    n_redecl = sum(1 for d in D if d["layer"] == "local" and d["redeclares_core"])
    n_c1_local = sum(1 for d in D if d["layer"] == "local" and d["redeclares_core"]
                     and (d["kind"], d["type"]) != next(
                         (e["kind"], e["type"]) for e in D
                         if e["layer"] == "core" and e["target"] == d["target"]))
    check("C2 + the contract-changing redeclarations == all redeclarations",
          conflicts["counts"]["C2_body_override"] + n_c1_local == n_redecl,
          "%d + %d != %d" % (conflicts["counts"]["C2_body_override"],
                             n_c1_local, n_redecl))
    check("C5 is exactly candidates.json",
          conflicts["counts"]["C5_unmigrated"] == len(candidates["candidates"]))
    check("results3 is recorded as carrying no contract at all",
          candidates["legacy_declarations_missing_kind_and_type"] ==
          candidates["legacy_declarations_total"] > 0,
          "%s of %s" % (candidates["legacy_declarations_missing_kind_and_type"],
                        candidates["legacy_declarations_total"]))
    r3 = {r["target"] for r in candidates["candidates"]}
    check("no candidate is already declared in results4",
          r3 & {d["target"] for d in D} == set(),
          sorted(r3 & {d["target"] for d in D}))

    print("\n== 6a. MAXIMAL vs OBSERVED is stated, not conflated")
    rec = manifest.get("app_reconciliation", {})
    check("the manifest carries an app reconciliation", "dormant_in_app" in rec, rec.keys())
    dormant = set(rec.get("dormant_in_app", {}))
    check("exactly one core declaration is dormant in the app",
          dormant == {"ActionController::Metal#head"}, dormant)
    check("the dormant one is declared in the core (so it IS a real site)",
          dormant <= {d["target"] for d in D if d["layer"] == "core"})
    check("its harmless twin ActionController::Head#head is also declared",
          "ActionController::Head#head" in {d["target"] for d in D if d["layer"] == "core"})
    sizes = {int(k): v for k, v in rec.get("observed_table_sizes", {}).items()}
    check("159 core-only real runs, all at maximal-minus-one",
          sizes.get(c["core_declarations"] - 1) == 159, sizes)
    for ep in registry["endpoints"]:
        sp = registry["endpoints"][ep]
        check("%s: observed == maximal - 1" % ep,
              sp["total_declared_observed_in_app"] == sp["total_declared_maximal"] - 1,
              sp)
        check("%s: a real run confirms the observed count" % ep,
              sizes.get(sp["total_declared_observed_in_app"], 0) >= 1, sizes)
    ar = os.path.join(INV, "app_reconciliation.json")
    check("inventory/app_reconciliation.json exists", os.path.exists(ar))
    if os.path.exists(ar):
        a = json.load(open(ar))
        check("its verdict is that nothing unexpected differs",
              a["verdict"].startswith("the only difference"), a["verdict"])
        check("the probe declares no NAME twice (rules out the call-vs-name reading)",
              a["probe_core_declarations"] == c["core_declarations"],
              "%s vs %s" % (a["probe_core_declarations"], c["core_declarations"]))

    print("\n== 6b. the two D7a reclassifications are argued, not just recorded")
    for t in ("ActiveRecord::Associations::CollectionProxy#create",
              "PostService#mark_user_notifications"):
        row = [r for r in partition["targets"] if r["target"] == t]
        check("%s is partitioned" % t, len(row) == 1, row)
        if row:
            r0 = row[0]
            check("%s is now a target_function" % t, r0["kind"] == "target_function", r0["kind"])
            check("%s records the reclassification" % t, "reclassified" in r0, sorted(r0))
            check("%s is not still in a SHIM triage group" % t,
                  r0["group"] not in ("association_plumbing", "write_path_walls"), r0["group"])
    hr = [r for r in partition["targets"]
          if r["target"] == "PostService#mark_user_notifications"]
    check("the app-specific core target function says it is unhomed",
          bool(hr) and "homeless" in hr[0], sorted(hr[0]) if hr else None)
    check("...and names its open question", bool(hr) and "open_question" in hr[0])

    print("\n== 6. registry agrees with the manifest")
    check("registry lists exactly the endpoints the manifest measured",
          set(registry["endpoints"]) == {d["endpoint"] for d in D},
          set(registry["endpoints"]) ^ {d["endpoint"] for d in D})
    for ep, spec in registry["endpoints"].items():
        m = manifest["counts"]["per_endpoint"][ep]
        check("%s: registry counts match" % ep,
              spec["declarations"] == m["local_declarations"] and
              spec["total_declared_maximal"] == m["total_declared"],
              "%s vs %s" % (spec, m))
        check("%s: every module it names appears in the manifest" % ep,
              set(spec["modules"]) <= {d["module"] for d in D if d["endpoint"] == ep},
              set(spec["modules"]) - {d["module"] for d in D if d["endpoint"] == ep})
    check("registry core counts match the manifest",
          registry["core"]["declarations_maximal"] == c["core_declarations"] and
          registry["core"]["maximal_target_function"] == c["core_target_function"] and
          registry["core"]["maximal_shim"] == c["core_shim"],
          registry["core"])
    check("registry names the dormant declaration too",
          set(registry["core"]["dormant_in_app"]) == dormant,
          registry["core"]["dormant_in_app"].keys())
    check("core module list matches the manifest",
          set(registry["core"]["modules"]) == {d["module"] for d in D
                                               if d["layer"] == "core"})

    print("\n== 6c. the prose's file:line citations still land")
    rc = subprocess.run([PY, os.path.join(LAB, "tools", "check_citations.py")],
                        capture_output=True, text=True, cwd=LAB)
    check("every README/CONFLICTS citation lands on its registered pattern",
          rc.returncode == 0, rc.stdout.strip().split("\n")[-6:])
    cj = os.path.join(INV, "citations.json")
    check("inventory/citations.json exists", os.path.exists(cj))
    if os.path.exists(cj):
        cd = json.load(open(cj))
        check("no citation pattern is missing or ambiguous",
              cd["unresolvable_patterns"] == [], cd["unresolvable_patterns"])
        check("the prose cites something at all", len(cd["resolved"]) > 10,
              len(cd["resolved"]))

    print("\n== 7. regenerating the inventory changes nothing (it is not stale)")
    with tempfile.TemporaryDirectory() as tmp:
        backup = os.path.join(tmp, "inv")
        shutil.copytree(INV, backup)
        for script in ("build_inventory.py", "build_partition.py",
                       "build_conflicts.py", "reconcile_with_app.py",
                       "check_citations.py"):
            r = subprocess.run([PY, os.path.join(LAB, "tools", script)],
                               capture_output=True, text=True, cwd=LAB)
            check("%s reruns cleanly" % script, r.returncode == 0,
                  (r.stdout + r.stderr)[-500:])
        for f in sorted(os.listdir(backup)):
            a = json.load(open(os.path.join(backup, f)))
            b = json.load(open(os.path.join(INV, f)))
            check("%s is up to date" % f, a == b, "regenerating it changed it")

    print("\n%d/%d checks passed" % (N - len(FAILS), N))
    if FAILS:
        print("FAILURES:")
        for f in FAILS:
            print("  - %s" % f)
        return 1
    print("OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
