#!/usr/bin/env python3
"""F3 chain tracer (CHECKS.md Part III).

    python3 bind_chain.py <dump.json> <var_or_substring>

Traces a $$-bind's producer chain through one dump: find the var, print
the note (the SQL that minted it), extract that note's own $$-binds,
recurse. MULTIPLE producers for one name = ambiguous naming — the fold
must guess and cannot be trusted for that chain (the owner-colliding
`assoc_profile` defect, violation 5).
"""
import json
import re
import sys

BIND_RE = re.compile(r"\$\$\((\w+)\)")


def producers_for(name, svars, events):
    out = []
    for sv in svars:
        if sv.get("name") == name:
            out.append(("var", sv.get("name"), str(sv.get("note") or "")))
    for ev in events:
        if ev.get("type") == "symbolic_call" and ev.get("result_name") == name:
            out.append(("event", ev.get("result_name"), str(ev.get("note") or "")))
    if not out:
        parts = name.split("_")
        for k in range(len(parts) - 1, 0, -1):
            prefix = "_".join(parts[:k])
            hits = [("var", sv.get("name"), str(sv.get("note") or ""))
                    for sv in svars if sv.get("name") == prefix]
            hits += [("event", ev.get("result_name"), str(ev.get("note") or ""))
                     for ev in events
                     if ev.get("type") == "symbolic_call" and ev.get("result_name") == prefix]
            if hits:
                out.extend(hits)
                break
    return out


def trace(name, depth, seen, svars, events):
    if name in seen or depth > 8:
        return
    seen.add(name)
    prods = producers_for(name, svars, events)
    indent = "  " * depth
    if not prods:
        print(f"{indent}{name}  (no producer found — free/seed var)")
        return
    if len(prods) > 1:
        print(f"{indent}{name}  <-- AMBIGUOUS: {len(prods)} producers "
              "(fold must guess — naming defect)")
    for kind, pname, note in prods[:3]:
        print(f"{indent}{name}  [{kind} {pname}]")
        print(f"{indent}  note: {re.sub(r'\s+', ' ', note)[:140]}")
        for b in dict.fromkeys(BIND_RE.findall(note)):
            trace(b, depth + 1, seen, svars, events)


def main():
    if len(sys.argv) < 3:
        sys.exit("usage: bind_chain.py <dump.json> <var_or_substring>")
    d = json.load(open(sys.argv[1]))
    target = sys.argv[2]
    svars = d.get("symbolic_vars") or []
    events = d.get("events") or []
    seeds = list(dict.fromkeys(sv["name"] for sv in svars
                               if target in str(sv.get("name") or ""))) or [target]
    for s in seeds[:5]:
        print(f"== chain for {s} ==")
        trace(s, 0, set(), svars, events)
        print()


if __name__ == "__main__":
    main()
