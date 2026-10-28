#!/usr/bin/env python3
"""The app-tree digest the pre-gate's step 3 compares against the pin.

DESIGN_SWEEP 5.2.1: "the pin is an input nobody computes. Nothing in this tree
measures an application tree, so unless a caller hands the `Coordinator` an
`app_tree_digest=` the comparison reports NOT CONFIGURED -- recorded as a gap
on every attempt, never as a match." This file is that caller's measurement,
and it is in the campaign directory rather than in `src_new/` precisely because
WHAT COUNTS AS THE APP is a property of this application, not of the engine.

WHAT IS DIGESTED, and why not the whole checkout. The claim the digest has to
support is "the behaviour under test is the pinned behaviour", so it covers the
application's own source and its pinned dependency and schema versions:

    app/  lib/  config/  db/schema.rb  Gemfile  Gemfile.lock

and nothing else. The rest of the checkout is either not behaviour (AUTHORS,
graphics/, docker/), or is written DURING a run by the thing under test
(log/, tmp/, public/assets/, hs_err_pid*.log, stray dump_*.json at the root --
all of which are present in this checkout right now), and a digest that moved
because Rails wrote a log line would refuse an attempt for an app change
nobody made. A narrower pin is a weaker claim and is stated as one: an edit
outside those paths is not caught here.

Both the coordinator and the batch agent run THIS script, so the comparison is
between two runs of one measurement rather than between two definitions.

    python3 app_tree_digest.py [<app-root>]        -> the bare 64-hex digest
"""
from __future__ import annotations

import hashlib
import os
import sys

DEFAULT_ROOT = "/home/dev/project/ruby_examples/dse-apps/apps/diaspora"
TREES = ("app", "lib", "config")
FILES = ("db/schema.rb", "Gemfile", "Gemfile.lock")


def digest(root: str = DEFAULT_ROOT) -> str:
    rows: list[tuple[str, str]] = []
    for tree in TREES:
        base = os.path.join(root, tree)
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames.sort()
            for name in sorted(filenames):
                p = os.path.join(dirpath, name)
                if os.path.islink(p) or not os.path.isfile(p):
                    continue
                rows.append((os.path.relpath(p, root), _file_sha(p)))
    for rel in FILES:
        p = os.path.join(root, rel)
        if os.path.isfile(p):
            rows.append((rel, _file_sha(p)))
    rows.sort()
    h = hashlib.sha256()
    for rel, sha in rows:
        h.update(rel.encode())
        h.update(b"\0")
        h.update(sha.encode())
        h.update(b"\n")
    return h.hexdigest()


def _file_sha(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


if __name__ == "__main__":
    print(digest(sys.argv[1] if len(sys.argv) > 1 else DEFAULT_ROOT))
