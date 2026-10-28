#!/usr/bin/env python3
"""check_verification.py — judge the 6-endpoint trial against
VERIFICATION_CHECKLIST.md, which was written BEFORE the trial ran.

Prints PASS/FAIL per expectation. Exits non-zero if any expectation fails, so
the full sweep is not launched on a bad fix set.
"""
from __future__ import annotations
import json, os, sys

E2E = "/home/dev/project/reports/autolab/e2e"
R1 = os.path.join(E2E, "_round1")


def load(base, eid, what):
    p = os.path.join(base, what, eid + (".json" if what == "results" else ""))
    if what == "runs":
        p = os.path.join(base, "runs", eid, "exploration_summary.json")
    try:
        return json.load(open(p))
    except Exception:
        return None


def stops(summary):
    out = []
    for r in (summary or {}).get("terminal_rows", []):
        t = r.get("terminal") or {}
        out.append((t.get("type"), t.get("raising_frame") or "", t.get("missing_name"),
                    (t.get("handler") or {}).get("status")))
    return out


def main():
    fails = []

    def check(name, ok, detail):
        print(f"  [{'PASS' if ok else 'FAIL'}] {name}: {detail}")
        if not ok:
            fails.append(name)

    print("== admin_pods_index — FIX-1/3/4/7/9 ==")
    r = load(E2E, "admin_pods_index", "results")
    s = load(E2E, "admin_pods_index", "runs")
    if r is None:
        check("admin_pods_index ran", False, "no result json")
    else:
        u = r.get("reach_union") or []
        check("reach >= 3", (r.get("reach_best") or 0) >= 3,
              f"reach_best={r.get('reach_best')} union={u}")
        check("devise_user_first reached",
              any("devise_user_first" in t for t in u), str(u))
        check("Relation#records reached", any("records" in t for t in u), str(u))
        bad = [x for x in stops(s) if x[2] == "len_var_name"
               or "SymbolicList#each" in str(x[0]) or "list.rb:305" in x[1]]
        check("no len_var_name / SymbolicList#each stop", not bad, str(bad[:2]) or "none")

    print("== sessions_new — FIX-2 ==")
    s = load(E2E, "sessions_new", "runs")
    bad = [x for x in stops(s) if "parameter_sanitizer.rb:158" in x[1]]
    check("past extract_auth_keys", not bad, str(bad[:1]) or "no such stop")

    print("== likes_index — FIX-5/6 ==")
    s = load(E2E, "likes_index", "runs")
    st = stops(s)
    ok = any(x[0] == "AutolabDSE::AuthenticationRequired" for x in st) or \
         any(x[0] == "Diaspora::NonPublic" and x[3] and "RAISED" in str(x[3]) for x in st)
    check("named auth outcome or a handler-RAISED record", ok, str(st[:2]))

    print("== comments_index — FIX-11 ==")
    r = load(E2E, "comments_index", "results")
    if r is None:
        check("comments_index ran", False, "no result json")
    else:
        refused = [d["file"] for d in (r.get("per_dump") or []) if d.get("ir") != "ok"]
        check("every dump accepted", not refused,
              f"{len(r.get('per_dump') or [])} dumps, refused={refused}")

    print("== links_resolve — FIX-8 ==")
    cfg = os.path.join("/home/dev/project/reports/autolab/entrypoints/scaffold",
                       "links_resolve", "config.json")
    names = sorted(i["name"] for i in (json.load(open(cfg)).get("inputs") or []))
    check("config lists :q", "q" in names, str(names))
    s = load(E2E, "links_resolve", "runs")
    bad = [x for x in stops(s) if "strong_parameters.rb:445" in x[1]]
    check("no ParameterMissing stop", not bad, str(bad[:1]) or "none")

    print("== manifest_show / home_show — FIX-12 (asset helpers) ==")
    for eid in ("manifest_show", "home_show"):
        ss = load(E2E, eid, "runs")
        bad = [x for x in stops(ss) if "underscore" in str(x) or "sprockets" in x[1].lower()
               or "assets/config/manifest.js" in x[1]]
        check(f"{eid}: no Sprockets asset stop", not bad, str(bad[:1]) or "none")

    print("== diaspora_federation_receive_public — FIX-8 (:xml) ==")
    cfgp = ("/home/dev/project/reports/autolab/entrypoints/scaffold/"
            "diaspora_federation_receive_public/config.json")
    nm = sorted(i["name"] for i in (json.load(open(cfgp)).get("inputs") or []))
    check("config lists :xml", "xml" in nm, str(nm))
    ss = load(E2E, "diaspora_federation_receive_public", "runs")
    bad = [x for x in stops(ss) if "CGIEscape" in x[1]]
    check("no CGI.unescape(nil) stop", not bad,
          str(bad[:1]) or "none  (a DIFFERENT stop here is a finding, not a failure)")

    print("== contacts_index — no regression ==")
    a = load(R1, "contacts_index", "results")
    b = load(E2E, "contacts_index", "results")
    if a and b:
        check("verdict not worse", not (a.get("verdict") == "ran_clean"
                                        and b.get("verdict") != "ran_clean"),
              f"{a.get('verdict')} -> {b.get('verdict')}")
        check("reach not lower", (b.get("reach_best") or 0) >= (a.get("reach_best") or 0),
              f"{a.get('reach_best')} -> {b.get('reach_best')}")
    else:
        check("contacts_index comparable", False, "missing a round-1 or round-2 result")

    print("== corpus-wide on the trial ==")
    for eid in ("admin_pods_index", "sessions_new", "likes_index", "comments_index",
                "links_resolve", "contacts_index", "manifest_show", "home_show",
                "diaspora_federation_receive_public"):
        r = load(E2E, eid, "results")
        if r is None:
            continue
        st = r.get("stages") or {}
        missing = [k for k, v in st.items() if v not in ("ok",)]
        check(f"{eid}: every stage returned", not missing, str(missing) or "all ok")
        op = ((r.get("policy") or {}).get("opaque") or {}).get("defects")
        check(f"{eid}: no opaque defect", not op, str(op) or "none")
        m = None
        for line in open(os.path.join(E2E, "manifest.jsonl")):
            row = json.loads(line)
            if row["endpoint"] == eid:
                m = row
        if m is not None:
            check(f"{eid}: limits from config.json",
                  m.get("limits_overridden") is False,
                  f"max_runs={m.get('max_runs')} config={m.get('config_max_runs')} "
                  f"overridden={m.get('limits_overridden')}")

    print()
    if fails:
        print(f"{len(fails)} EXPECTATION(S) FAILED: {fails}")
        return 1
    print("every expectation met — the full sweep may proceed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
