"""Reproduce the gate's CLASS key from the declarations, verify it against
_gate_classes_ALL_meta.json (ground truth: the key string AND the cover count
of every one of the 2021 tested classes), then expand the gate's FAIL /
NOT-COMPARABLE verdicts to the FULL membership of their classes.

Writes small artefacts only:
  _c11_withdraw_indep.json   tier2 classes refuted by the gate + every pair in them
  _c11_withdraw_conf.json    confinement classes refuted / unverified + every pair
  _c11_notcomparable.json    the 34 NOT-COMPARABLE verdicts, with reasons
"""
import json, re, collections, os

B = os.path.dirname(os.path.abspath(__file__))


def _stream(path):
    """Yield the top-level objects of a JSON array without loading the file
    (the 630 MB declaration dump; the box's cage is 6 G and shared)."""
    f = open(path, encoding="utf-8")
    while f.read(1) != "[":
        pass
    depth, in_str, esc, buf = 0, False, False, []
    while True:
        chunk = f.read(1 << 20)
        if not chunk:
            return
        start = 0
        for n, c in enumerate(chunk):
            if in_str:
                if esc:
                    esc = False
                elif c == "\\":
                    esc = True
                elif c == '"':
                    in_str = False
                continue
            if c == '"':
                in_str = True
            elif c in "[{":
                if depth == 0:
                    start = n
                depth += 1
            elif c in "]}":
                depth -= 1
                if depth == 0:
                    buf.append(chunk[start:n + 1])
                    yield json.loads("".join(buf))
                    buf = []
                    start = n + 1
        if depth:
            buf.append(chunk[start:])


def _slim(a):
    """Keep only what the class key and the withdrawal lists need."""
    t = a.get("type")
    if t == "ConfinementAssumption":
        return {"type": t, "expr_a": a["expr_a"], "expr_b": a["expr_b"],
                "footprint_a": a.get("footprint_a") or [],
                "footprint_b": a.get("footprint_b") or []}
    if t == "IndependenceAssumption":
        return {"type": t, "expr_a": a.get("expr_a"), "expr_b": a.get("expr_b"),
                "description": a.get("description") or ""}
    return None


A = [x for x in (_slim(a) for a in _stream(os.path.join(B, "_assumptions_declared_cert3.json"))) if x]
D = json.load(open(os.path.join(B, "_gate_classes_ALL.json")))
M = json.load(open(os.path.join(B, "_gate_classes_ALL_meta.json")))
R = json.load(open(os.path.join(B, "_gate_ALL_results.json")))

HEX = re.compile(r"_(?:[0-9a-f]{8})(?=_|$)")


def fam(v):
    """tier2 rep FAMILY (the coarse key §21.3 chose)."""
    v = re.sub(r"^SYM_(?:RESULT|LEN)_", "", v)
    v = re.sub(r"^SYM_RESULT_", "", v)
    v = re.sub(r"^ActiveRecord__", "", v)
    v = re.sub(r"^[A-Za-z0-9]+__", "", v)
    v = re.sub(r"^(?:Relation_|FinderMethods_|Calculations_)", "", v)
    v = re.sub(r"^SYM_", "", v)
    v = HEX.sub("", v)
    v = re.sub(r"_\d+$", "", v)
    return v[:48]


TBL = re.compile(r"(?:records|to_ary)_([a-z_]+?)_[0-9a-f]{8}")


def side_key(expr, footprint):
    if footprint:
        return tuple(sorted(s[:60] for s in footprint))
    m = TBL.search(expr)
    return (m.group(1),) if m else (expr[:60],)


D2 = re.compile(r"^disjoint reps: \[(.*)\] \|\| \[(.*)\]$")


def class_of(a):
    """The gate's class key for one declaration, by tier."""
    t = a["type"]
    if t == "ConfinementAssumption":
        ka = side_key(a["expr_a"], a.get("footprint_a") or [])
        kb = side_key(a["expr_b"], a.get("footprint_b") or [])
        return "confinement", str(tuple(sorted((ka, kb))))
    if t == "IndependenceAssumption":
        desc = a.get("description") or ""
        g = D2.match(desc)
        if g:
            return "tier2", str(tuple(sorted((fam(g.group(1)), fam(g.group(2))))))
        return None, None
    return None, None


# ---- 1. VERIFY against the meta of the classes actually tested -------------
ok = bad = skip = 0
mismatch = []
for i, dec in enumerate(D[2:]):
    meta = M[i]
    tier, key = class_of(dec)
    if tier is None or meta["tier"] not in ("tier2", "confinement"):
        skip += 1
        continue
    if tier == meta["tier"] and key == meta["class"]:
        ok += 1
    else:
        bad += 1
        if len(mismatch) < 5:
            mismatch.append((meta["tier"], meta["class"][:90], tier, (key or "")[:90]))
print(f"[verify] class key reproduced on tested reps: ok={ok} bad={bad} (other tiers skipped={skip})")
for x in mismatch:
    print("   MISMATCH", x)

# ---- 2. partition ALL declarations by class, check the cover counts --------
part = collections.defaultdict(list)
for a in A:
    tier, key = class_of(a)
    if tier:
        part[(tier, key)].append(a)
cov_ok = cov_bad = 0
for i, dec in enumerate(D[2:]):
    meta = M[i]
    if meta["tier"] not in ("tier2", "confinement"):
        continue
    n = len(part.get((meta["tier"], meta["class"]), ()))
    if n == meta["covers"]:
        cov_ok += 1
    else:
        cov_bad += 1
        if cov_bad <= 5:
            print("   COVER MISMATCH", meta["tier"], meta["class"][:80], "mine", n, "meta", meta["covers"])
print(f"[verify] cover counts match: {cov_ok} classes, mismatched {cov_bad}")

# ---- 3. map results -> declared rep -> class -------------------------------
idx = {}
for i, x in enumerate(D):
    if x["type"] in ("IndependenceAssumption", "ConfinementAssumption"):
        k = (x["type"], x["expr_a"], x["expr_b"])
    elif x["type"] == "AliasAssumption":
        k = (x["type"], x.get("result_pattern"), None)
    else:
        k = (x["type"], x["expr"], None)
    idx.setdefault(k, []).append(i)

out_i, out_c, out_nc = [], [], []
for res in R:
    k = (res["type"], res.get("expr"), res.get("expr_b"))
    ii = idx.get(k)
    if not ii or ii[0] < 2:
        if res["verdict"] != "PASS":
            out_nc.append({"type": res["type"], "verdict": res["verdict"],
                           "expr": res.get("expr"), "expr_b": res.get("expr_b"),
                           "detail": res.get("detail"), "class": "(alias derived test)"})
        continue
    i = ii[0]
    dec, meta = D[i], M[i - 2]
    if res["verdict"] == "PASS":
        continue
    members = part.get((meta["tier"], meta["class"]), [])
    row = {"verdict": res["verdict"], "type": res["type"], "tier": meta["tier"],
           "class": meta["class"], "covers": meta["covers"], "members": len(members),
           "rep_a": res.get("expr"), "rep_b": res.get("expr_b"),
           "detail": res.get("detail"),
           "pairs": [[a["expr_a"], a["expr_b"]] for a in members]}
    if res["verdict"] == "NOT-COMPARABLE":
        out_nc.append({kk: row[kk] for kk in ("verdict", "type", "tier", "class", "covers",
                                              "members", "rep_a", "rep_b", "detail")})
    if res["type"] == "IndependenceAssumption" and res["verdict"] == "FAIL":
        out_i.append(row)
    elif res["type"] == "ConfinementAssumption" and res["verdict"] != "PASS":
        out_c.append(row)

json.dump(out_i, open(os.path.join(B, "_c11_withdraw_indep.json"), "w"), indent=1)
json.dump(out_c, open(os.path.join(B, "_c11_withdraw_conf.json"), "w"), indent=1)
json.dump(out_nc, open(os.path.join(B, "_c11_notcomparable.json"), "w"), indent=1)

print(f"[indep] FAIL classes {len(out_i)}  declarations withdrawn {sum(r['members'] for r in out_i)}"
      f"  (gate covers {sum(r['covers'] for r in out_i)})")
print(f"[conf ] non-PASS classes {len(out_c)}  pairs withdrawn {sum(r['members'] for r in out_c)}"
      f"  (gate covers {sum(r['covers'] for r in out_c)})")
byv = collections.Counter((r["type"], r["verdict"]) for r in out_c)
print("[conf ] by verdict:", dict(byv))
print(f"[nc   ] NOT-COMPARABLE rows {len(out_nc)}")
