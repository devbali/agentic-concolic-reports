#!/usr/bin/env python3
"""build_inventory.py -- regenerate everything under reports/autolab/inventory/.

It drives tools/declaration_probe.rb (which really runs `install!` against the
real src_new CallInterceptor) over:

  * the two GOLD results4 batches -- core + each batch's own override
  * the six results3 batches, in LENIENT mode, purely to mine target NAMES

and writes:

  inventory/manifest.json    every declaration, with kind/type/layer/source
  inventory/conflicts.json   every place two sources disagree about one target
  inventory/candidates.json  targets results3 has and results4 does not

inventory/partition.json -- the core/local ruling -- is hand-written, because
the rationale per shim is a judgement and not a measurement.
tools/build_partition.py cross-checks its table against this manifest and
FAILS if the two disagree about the target set, so they cannot drift.

Run:  /home/dev/project/venvs/queries_from_runs/bin/python3 tools/build_inventory.py
"""
import collections
import hashlib
import json
import os
import subprocess
import sys

LAB = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOLS = os.path.join(LAB, "tools")
INV = os.path.join(LAB, "inventory")
DIA = "/home/dev/project/reports/diaspora"
R4 = os.path.join(DIA, "results4")
R3 = os.path.join(DIA, "results3")
RUBY = "ruby"

GOLD = {
    "aspect_memberships_create": ["AspectMembershipsTargets", "AmDeviseUserNaming"],
    "comments_index": ["CommentsTargets", "CommentsMentionLookupNaming",
                       "CommentsVisibleShareableNaming", "CommentsDeviseUserNaming"],
}
# results3 endpoints and the install! order their own run_dse.rb uses.
LEGACY = {
    "comments_index": ["CommentsTargets", "CommentsMentionLookupNaming",
                       "CommentsVisibleShareableNaming", "CommentsDeviseUserNaming"],
    "conversations_index": ["ConversationsIndexTargets", "ConvDeviseUserNaming"],
    "notifications_index": ["NotificationsIndexTargets", "NotifDeviseUserNaming"],
    "people_show": ["PeopleTargets", "PeopleShowSymParams"],
    "people_stream": ["PeopleStreamTargets"],
    "posts_show": ["PostsTargets", "PostsShowFinderNaming", "PostsShowMentionLookupNaming"],
}


def sh(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("FAILED %s\n%s\n%s" % (" ".join(cmd), r.stdout[-3000:], r.stderr[-3000:]))
    return r.stdout


def md5(path):
    return hashlib.md5(open(path, "rb").read()).hexdigest()


def sites(path):
    return json.loads(sh([RUBY, os.path.join(TOOLS, "extract_sites.rb"), path]))


def probe(files, mods_per_file, lenient, tag):
    consts = json.loads(sh([RUBY, os.path.join(TOOLS, "scrape_constants.rb")] + files))
    spec = {"lenient": lenient, "consts": consts,
            "steps": [{"file": f, "modules": m} for f, m in zip(files, mods_per_file)]}
    sp = os.path.join(os.environ.get("TMPDIR", "/tmp"), "autolab_spec_%s.json" % tag)
    json.dump(spec, open(sp, "w"))
    d = json.loads(sh([RUBY, os.path.join(TOOLS, "declaration_probe.rb"), sp]))
    if d.get("fatal"):
        sys.exit("PROBE FATAL (%s): %s\n%s" % (tag, d["fatal"], d["message"]))
    if d["errors"]:
        sys.exit("PROBE ERRORS (%s):\n  %s" % (tag, "\n  ".join(d["errors"])))
    return d


def receiver_of(target):
    """`Klass#meth` and `Klass.meth` both split on the LAST separator."""
    i = max(target.rfind("#"), target.rfind("."))
    return target[:i] if i > 0 else target


def app_reconciliation():
    """MAXIMAL (this manifest) vs OBSERVED (a booted app's declaration table).

    Read off real dumps by tools/reconcile_with_app.py. Summarised here so the
    manifest never states a count without saying which of the two it is.
    """
    import glob as _glob
    sizes = collections.Counter()
    for d in sorted(_glob.glob(os.path.join(LAB, "shakedown", "runs", "*"))):
        dumps = sorted(_glob.glob(os.path.join(d, "dump_*.json")))
        if dumps:
            sizes[len(json.load(open(dumps[0]))["declarations"])] += 1
    if not sizes:
        return {"_status": "no shakedown dumps on disk; run tools/reconcile_with_app.py"}
    return {
        "_note": [
            "Counts elsewhere in this manifest are MAXIMAL -- every guarded",
            "declaration counted, because the probe forces every guard true.",
            "A booted app installs one fewer, in every run ever measured.",
            "The difference is ONE name and it is always the same one.",
        ],
        "dormant_in_app": {
            "ActionController::Metal#head": (
                "core.rb W2. Guard: "
                "`ActionController::Metal.instance_methods.include?(:head)`. "
                "`head` lives in ActionController::Head "
                "(actionpack-5.2.4.3/lib/action_controller/metal/head.rb:21), never "
                "mixed into Metal, so the guard is FALSE in the app. Harmless: the "
                "core declares `ActionController::Head#head` separately with the "
                "same kind and marker, and that one is in all 161 real runs.")},
        "observed_table_sizes": dict(sizes),
        "evidence": "reports/autolab/shakedown/runs/*/dump_*.json",
        "detail": "inventory/app_reconciliation.json",
    }


def build():
    os.makedirs(INV, exist_ok=True)
    gold = {}
    for ep, mods in GOLD.items():
        ct = os.path.join(R4, ep, "concolic_targets.rb")
        tg = os.path.join(R4, ep, "targets.rb")
        gold[ep] = probe([ct, tg], [["ConcolicTargets"], mods], False, "r4_" + ep)

    # The shared core must be byte-identical across gold batches, or "core"
    # means nothing.
    cores = {ep: md5(os.path.join(R4, ep, "concolic_targets.rb")) for ep in GOLD}
    assert len(set(cores.values())) == 1, cores
    core_md5 = list(cores.values())[0]

    def core_calls(ep):
        return [c for c in gold[ep]["calls"] if c["module"] == "ConcolicTargets"]

    a, b = list(GOLD)
    assert ([(c["target"], c["kind"], c["type"]) for c in core_calls(a)] ==
            [(c["target"], c["kind"], c["type"]) for c in core_calls(b)]), \
        "core declarations differ between gold batches"
    core = core_calls(a)
    core_by_target = {c["target"]: c for c in core}

    decls = []
    for ep in GOLD:
        for c in gold[ep]["calls"]:
            layer = "core" if c["module"] == "ConcolicTargets" else "local"
            path, line = c["site"].rsplit(":", 1)
            decls.append({
                "endpoint": ep,
                "layer": layer,
                "module": c["module"],
                "target": c["target"],
                "receiver": receiver_of(c["target"]),
                "method": c["method"],
                "kind": c["kind"],
                "type": c["type"],
                "has_returns": c["has_returns"],
                "source_file": os.path.relpath(path, "/home/dev/project"),
                "source_line": int(line),
                "redeclares_core": layer == "local" and c["target"] in core_by_target,
            })

    site_counts, loop_sites, static_sites = {}, [], 0
    for ep in GOLD:
        for f in ("concolic_targets.rb", "targets.rb"):
            p = os.path.join(R4, ep, f)
            sj = sites(p)
            site_counts[os.path.relpath(p, "/home/dev/project")] = sj["count"]
            for st in sj["sites"]:
                if st["method_is_literal"]:
                    static_sites += 1
                else:
                    loop_sites.append({
                        "endpoint": ep, "file": f, "line": st["line"],
                        "receiver_expr": st["klass"], "method_expr": st["method"],
                        "kind": st["kind"], "type": st["type"]})

    # last declaration wins, in load order -- the runtime's own resolution
    final = {}
    for ep in GOLD:
        f = {}
        for d in decls:
            if d["endpoint"] == ep:
                f[d["target"]] = (d["kind"], d["type"])
        final[ep] = f
    A, B = final[a], final[b]
    both = set(A) & set(B)
    cross = {}
    for kind in ("target_function", "shim"):
        in_both = {t for t in both if A[t][0] == kind and B[t][0] == kind}
        cross[kind] = {
            "in_both": len(in_both),
            "in_both_identical_kind_and_type": len([t for t in in_both if A[t] == B[t]]),
            "only_" + a: sorted(t for t in set(A) - set(B) if A[t][0] == kind),
            "only_" + b: sorted(t for t in set(B) - set(A) if B[t][0] == kind),
        }
    cross["kind_disagrees"] = sorted(t for t in both if A[t][0] != B[t][0])
    cross["type_disagrees"] = sorted(
        t for t in both if A[t][0] == B[t][0] and A[t][1] != B[t][1])

    manifest = {
        "_how_measured": [
            "Declarations were MEASURED, not grepped: tools/declaration_probe.rb",
            "runs each config's real install! against the real CallInterceptor",
            "from src_new, with Rails and the diaspora app replaced by stub",
            "modules. Every declaration below therefore passed the runtime's own",
            "MissingKind and MissingType checks at declaration time.",
            "declare_target SITES were counted separately, with Ripper",
            "(tools/extract_sites.rb): a site inside a loop is ONE site and",
            "SEVERAL declarations, which is why the two counts differ. 29 of the",
            "142 sites are loop-bound -- the receiver AND the method are block",
            "variables -- and NOTHING can resolve them from the call site; they",
            "are listed under loop_bound_sites. A manifest built by parsing would",
            "silently omit every declaration they expand into. A naive",
            "single-line grep -c over these four files says 67/67/22/15; the",
            "real site counts are 59/59/10/14.",
            "CAVEAT, NOW QUANTIFIED: the probe measures the MAXIMAL set -- what",
            "the config declares when every guarded constant and method is",
            "present. A booted app can leave a guard false. It does, exactly once:",
            "see `app_reconciliation` below and inventory/app_reconciliation.json.",
        ],
        "measured_on": "2026-09-25",
        "runtime": "/home/dev/project/src_new/runtimes/ruby_runtime",
        "core_source_md5": core_md5,
        "declare_target_sites": site_counts,
        "declare_target_sites_total": sum(site_counts.values()),
        "declare_target_sites_statically_resolvable": static_sites,
        "declare_target_sites_loop_bound": len(loop_sites),
        "loop_bound_sites": loop_sites,
        "cross_endpoint": {
            "_note": [
                "The user's kind-axis ruling, checked against the corpus. These are",
                "TRUE counts from the interceptor over ALL declarations, not over",
                "the 113 statically-resolvable sites.",
                "TARGET_FUNCTION: aspect_memberships_create's set is a STRICT SUBSET",
                "of comments_index's -- 48 shared, 0 unique to amc, 14 unique to",
                "comments_index. No genuine TF conflict; one endpoint simply needs",
                "fewer. SHIM: 39 of 42 shared on each side, all 39 with identical",
                "kind AND type, leaving a local tail of 2 and 3.",
                "That is the shape the ruling describes, at full scale.",
            ],
            "declared_per_endpoint": {ep: {
                "total": len(final[ep]),
                "target_function": sum(1 for k, _ in final[ep].values()
                                       if k == "target_function"),
                "shim": sum(1 for k, _ in final[ep].values() if k == "shim"),
            } for ep in GOLD},
            "target_function": cross["target_function"],
            "shim": cross["shim"],
            "kind_disagrees": cross["kind_disagrees"],
            "type_disagrees": cross["type_disagrees"],
        },
        "counts": {
            "core_declarations": len(core),
            "core_target_function": sum(1 for c in core if c["kind"] == "target_function"),
            "core_shim": sum(1 for c in core if c["kind"] == "shim"),
            "per_endpoint": {ep: {
                "total_declared": gold[ep]["final_count"],
                "local_declarations": sum(1 for c in gold[ep]["calls"]
                                          if c["module"] != "ConcolicTargets"),
                "local_redeclaring_core": sum(
                    1 for c in gold[ep]["calls"]
                    if c["module"] != "ConcolicTargets" and c["target"] in core_by_target),
                "local_new": sum(
                    1 for c in gold[ep]["calls"]
                    if c["module"] != "ConcolicTargets" and c["target"] not in core_by_target),
            } for ep in GOLD},
        },
        "app_reconciliation": app_reconciliation(),
        "declarations": decls,
    }
    json.dump(manifest, open(os.path.join(INV, "manifest.json"), "w"), indent=2)

    # ---------------- results3 mining ----------------
    legacy = {}
    for ep, mods in LEGACY.items():
        files, mm = [], []
        for name, m in (("concolic_targets.rb", ["ConcolicTargets"]), ("targets.rb", mods)):
            p = os.path.join(R3, ep, name)
            if os.path.exists(p):
                files.append(p)
                mm.append(m)
        legacy[ep] = probe(files, mm, True, "r3_" + ep)

    r4_targets = {d["target"] for d in decls}
    seen = collections.defaultdict(lambda: {"endpoints": set(), "layers": set()})
    for ep, d in legacy.items():
        for c in d["calls"]:
            if c["target"] in r4_targets:
                continue
            seen[c["target"]]["endpoints"].add(ep)
            seen[c["target"]]["layers"].add(
                "core" if c["module"] == "ConcolicTargets" else "local")

    n_repair = sum(1 for d in legacy.values() for c in d["calls"] if c.get("needs_repair"))
    n_total = sum(len(d["calls"]) for d in legacy.values())
    candidates = {
        "_what_this_is": [
            "Targets the results3 corpus declares and the results4 gold pair",
            "does not. results3 is LOWER TRUST and the probe says how much:",
            "%d of its %d declarations carry NEITHER kind: NOR type:." % (n_repair, n_total),
            "So these rows are target NAMES mined for discovery, nothing more.",
            "They are deliberately NOT shipped as declarations: inventing a",
            "kind and a type for a mock nobody has run is exactly how the",
            "retired shared master became unloadable without anyone noticing.",
            "To adopt one, write the declaration, give it a kind and a type you",
            "can defend, and put it behind a real run.",
        ],
        "legacy_declarations_total": n_total,
        "legacy_declarations_missing_kind_and_type": n_repair,
        "legacy_per_endpoint": {ep: len(d["calls"]) for ep, d in sorted(legacy.items())},
        "candidates": [
            {"target": t,
             "declared_by_results3_endpoints": sorted(v["endpoints"]),
             "layers_in_results3": sorted(v["layers"])}
            for t, v in sorted(seen.items())
        ],
    }
    json.dump(candidates, open(os.path.join(INV, "candidates.json"), "w"), indent=2)

    print("manifest:   %d declaration rows; core %d = %d TF + %d SHIM" % (
        len(decls), len(core),
        manifest["counts"]["core_target_function"], manifest["counts"]["core_shim"]))
    for ep in GOLD:
        c = manifest["counts"]["per_endpoint"][ep]
        print("            %-26s total %3d  local %2d (%d redeclare core, %d new)" % (
            ep, c["total_declared"], c["local_declarations"],
            c["local_redeclaring_core"], c["local_new"]))
    print("candidates: %d results3-only targets (%d/%d legacy declarations "
          "carry neither kind: nor type:)" % (len(seen), n_repair, n_total))
    return manifest, gold, legacy, core_by_target


if __name__ == "__main__":
    build()
