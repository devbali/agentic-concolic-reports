#!/usr/bin/env python3
"""Extract the COMPLETION VERDICT from a coverage_summary.json, by FIELD.

    usage: _p48_verdict.py [coverage_summary.json ...]

WHY THIS EXISTS. Two reasons, both of which have burned this campaign.

1. THE PRINTED `OVERALL_COMPLETE=` LINE IS NOT THE VERDICT. It is emitted by
   the runner around the completion section and has repeatedly been stale or
   preliminary relative to what actually landed in the JSON. The verdict is
   `completion.complete` / `completion.blocking` / `assumptions.verdict_counts`
   in the file. Read the file, never the scrollback.

2. `json.load()` ON THIS FILE IS NOT SAFE TO DO CASUALLY. posts_show's
   coverage_summary.json is ~500 MB — dominated by `missing[]` and the
   assumption records — and fully parsing it costs many GB of RSS. Doing that
   NEXT TO a 40 GB coverage pass or another endpoint's live gate is how a box
   with 68 GB gets an OOM kill that takes out somebody else's job.

So this scans the file for the TOP-LEVEL keys it wants and decodes ONLY those
sub-objects with `raw_decode`, which stops at the end of the value.

Stated honestly, because an over-claim here is the kind of thing that gets
trusted next to a 40 GB job: peak RSS is ABOUT ONE COPY OF THE FILE (the raw
text is held as a Python str) PLUS the decoded sub-objects — roughly 1x the
file, against the ~10-20x that `json.load` costs on a structure this deeply
nested. On posts_show's ~500 MB summary that is ~0.6 GB instead of ~10 GB. It
is cheap enough to run beside a live pass; it is not free.

The scan is brace/bracket-depth aware and string-aware (quotes and backslash
escapes), so a `"completion"` appearing inside a nested object or inside a
string value is not mistaken for the top-level key.
"""
import json
import os
import sys

WANT = ("completion", "assumptions", "coverage", "corpus", "provenance")


def top_level_keys(path, want):
    """Yield (key, decoded_value) for each wanted TOP-LEVEL key.

    Single forward pass. Only the wanted values are decoded.
    """
    out = {}
    with open(path, "r") as fh:
        buf = fh.read()  # the raw text; the parse is what we are avoiding
    n = len(buf)
    i = 0
    # find the opening brace of the top-level object
    while i < n and buf[i] not in "{[":
        i += 1
    if i >= n or buf[i] != "{":
        raise SystemExit(f"{path}: top level is not a JSON object")
    i += 1
    depth = 0
    dec = json.JSONDecoder()
    while i < n:
        c = buf[i]
        if c == '"' and depth == 0:
            # a key at top level (depth 0 inside the root object)
            key, j = dec.raw_decode(buf, i)
            # skip whitespace and the colon
            while j < n and buf[j] in " \t\r\n":
                j += 1
            if j < n and buf[j] == ":":
                j += 1
            while j < n and buf[j] in " \t\r\n":
                j += 1
            if key in want:
                val, j = dec.raw_decode(buf, j)
                out[key] = val
                i = j
            else:
                # skip the value without decoding it
                i = _skip_value(buf, j)
            continue
        if c in "{[":
            depth += 1
        elif c in "}]":
            if depth == 0:
                break
            depth -= 1
        elif c == '"':
            i = _skip_string(buf, i)
            continue
        i += 1
    return out


def _skip_string(buf, i):
    i += 1
    while i < len(buf):
        if buf[i] == "\\":
            i += 2
            continue
        if buf[i] == '"':
            return i + 1
        i += 1
    return i


def _skip_value(buf, i):
    n = len(buf)
    if i >= n:
        return i
    if buf[i] == '"':
        return _skip_string(buf, i)
    if buf[i] in "{[":
        depth = 0
        while i < n:
            c = buf[i]
            if c == '"':
                i = _skip_string(buf, i)
                continue
            if c in "{[":
                depth += 1
            elif c in "}]":
                depth -= 1
                if depth == 0:
                    return i + 1
            i += 1
        return i
    # a bare scalar: run to the next comma or closing brace at this level
    while i < n and buf[i] not in ",}]":
        i += 1
    return i


def report(path):
    print(f"===== {path}")
    if not os.path.exists(path):
        print("  MISSING")
        return
    st = os.stat(path)
    print(f"  size={st.st_size/1e6:.1f} MB  mtime={__import__('time').ctime(st.st_mtime)}")
    got = top_level_keys(path, WANT)

    comp = got.get("completion")
    if comp is None:
        print("  completion: ABSENT (a SKIP_COMPLETION / coverage-only pass)")
    elif isinstance(comp, dict):
        print(f"  completion.complete = {comp.get('complete')!r}")
        blocking = comp.get("blocking")
        if isinstance(blocking, list):
            print(f"  completion.blocking = {len(blocking)} item(s)")
            for b in blocking[:40]:
                print(f"      - {b if isinstance(b,str) else json.dumps(b)[:300]}")
            if len(blocking) > 40:
                print(f"      ... and {len(blocking)-40} more")
        else:
            print(f"  completion.blocking = {blocking!r}")
        for k in sorted(comp):
            if k in ("complete", "blocking"):
                continue
            v = comp[k]
            s = json.dumps(v) if not isinstance(v, str) else v
            print(f"  completion.{k} = {s[:240]}")
    else:
        print(f"  completion = {comp!r}")

    asm = got.get("assumptions")
    if isinstance(asm, dict):
        vc = asm.get("verdict_counts")
        print(f"  assumptions.verdict_counts = {json.dumps(vc)}")
        for k in ("verdict", "total", "tested", "untested"):
            if k in asm:
                print(f"  assumptions.{k} = {json.dumps(asm[k])[:240]}")
    elif asm is not None:
        print(f"  assumptions = {json.dumps(asm)[:240]}")

    cov = got.get("coverage")
    if isinstance(cov, dict):
        for k in ("missing", "missing_count", "tree_missing", "demand_sets",
                  "runs", "nodes", "complete"):
            if k in cov:
                v = cov[k]
                v = len(v) if isinstance(v, list) else v
                print(f"  coverage.{k} = {json.dumps(v)[:240]}")


if __name__ == "__main__":
    args = sys.argv[1:] or [os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                         "coverage_summary.json")]
    for p in args:
        report(p)
