#!/usr/bin/env python3
"""C29 — whole-corpus `dump_errors` census, re-measured on the corpus of record,
plus the ROUTING-shape differential POLICY_HEADER's claim needs.

For every dump: the error type, a normalised message, the first traceback frame,
the scenario, the drive tag, and the recorded VALUE of every
`*_username` symbolic var (the route's dynamic segment). The differential asks
the one question the header cannot answer by assertion: does the
`No route matches` arm follow the VALUE (empty -> the route's own
`/[^\\/]+/` constraint rejects it, which a real Rails app does too) or the
symbolic WRAPPER (in which case a non-empty symbolic username would fail too,
and the shape is a rig artefact)?

  usage: DUMP_LIST=.. OUT=.. [WORKERS=4] python3 -u _c29_errcensus.py
Read-only.
"""
import json, os, re, sys, time, collections
from multiprocessing import Pool

HERE = os.path.dirname(os.path.abspath(__file__))
LIST = os.environ.get("DUMP_LIST", os.path.join(HERE, "_snapshot_c27_R8.txt"))
OUT = os.environ.get("OUT", os.path.join(HERE, "_c29_errcensus.json"))
WORKERS = int(os.environ.get("WORKERS", "4"))
_TAG = re.compile(r"^dump_(.+?)_dse\d+_(.+)\.json$")
_SYM = re.compile(r"<Sym\w+ [^>]*>")

FILES = [l.strip() for l in open(LIST) if l.strip()]
N = len(FILES)


def norm(msg):
    return _SYM.sub("<SYM>", str(msg))[:160]


def one(p):
    try:
        d = json.load(open(p))
    except Exception:
        return None
    err = d.get("error") or {}
    if isinstance(err, str):
        err = {"type": err, "message": err, "traceback": ""}
    sc = (d.get("concolic_scenario") or {}).get("name") or ""
    m = _TAG.match(os.path.basename(p))
    tag = m.group(2) if m else ""
    unames = {}
    for v in (d.get("symbolic_vars") or []):
        n = v.get("name") or ""
        if n.endswith("_username"):
            unames[n] = v.get("value")
    tb = str(err.get("traceback") or "")
    frame = tb.split("\n")[0] if tb else ""
    # every APPLICATION frame of the traceback, for the site census
    app = [f for f in tb.split("\n") if "/apps/diaspora/" in f]
    return (err.get("type") or "", norm(err.get("message") or ""), frame,
            sc, tag, unames, app[0] if app else "")


if __name__ == "__main__":
    t0 = time.time()
    bytype = collections.Counter(); bymsg = collections.Counter()
    byframe = collections.Counter(); byappframe = collections.Counter()
    route_user = collections.Counter(); other_user = collections.Counter()
    route_by_scen = collections.Counter(); scen_tot = collections.Counter()
    mobile_uname = collections.Counter()
    msg_scen = collections.defaultdict(collections.Counter)
    with Pool(WORKERS) as pool:
        for i, r in enumerate(pool.imap(one, FILES, chunksize=400)):
            if r is None:
                continue
            t, msg, frame, sc, tag, unames, appframe = r
            bytype[t] += 1; scen_tot[sc] += 1
            if t:
                bymsg[msg] += 1; byframe[frame] += 1; byappframe[appframe] += 1
                msg_scen[msg][sc] += 1
            isroute = "No route matches" in msg
            if isroute:
                route_by_scen[sc] += 1
            for n, v in unames.items():
                key = ("EMPTY" if v == "" else
                       "NONEMPTY:%s" % str(v)[:20] if v is not None else "NONE")
                (route_user if isroute else other_user)[(n.split("_")[-2:][0] + "_username", key)] += 1
                if sc.startswith("mobile"):
                    mobile_uname[(key, "ROUTE-ERR" if isroute else
                                  ("OTHER-ERR" if t else "NO-ERR"))] += 1
            if (i + 1) % 20000 == 0:
                print(f"  {i+1}/{N}  {time.time()-t0:.0f}s", flush=True)
    res = {"n": N, "list": LIST,
           "by_type": bytype.most_common(), "by_msg": bymsg.most_common(),
           "by_frame": byframe.most_common(), "by_app_frame": byappframe.most_common(),
           "route_username": [[list(k), v] for k, v in route_user.most_common()],
           "other_username": [[list(k), v] for k, v in other_user.most_common()],
           "route_by_scenario": route_by_scen.most_common(),
           "scenario_totals": scen_tot.most_common(),
           "mobile_username_x_outcome": [[list(k), v] for k, v in mobile_uname.most_common()],
           "msg_by_scenario": {k: v.most_common() for k, v in msg_scen.items()}}
    json.dump(res, open(OUT, "w"), indent=1)
    print("\n-- error TYPE --")
    for k, v in bytype.most_common():
        print(f"{v:9d}  {k or '<none>'}")
    print("\n-- normalised MESSAGE --")
    for k, v in bymsg.most_common():
        print(f"{v:9d}  {k}")
    print("\n-- first APPLICATION frame --")
    for k, v in byappframe.most_common():
        print(f"{v:9d}  {k.strip() or '<none - no application frame>'}")
    print("\n-- mobile: username value x outcome --")
    for k, v in mobile_uname.most_common():
        print(f"{v:9d}  {k}")
    print("\n-- routing errors by scenario --")
    for k, v in route_by_scen.most_common():
        print(f"{v:9d}  {k}   (scenario total {scen_tot[k]})")
    print(f"\nwall {time.time()-t0:.0f}s")
    print("C29-ERRCENSUS-DONE", flush=True)
