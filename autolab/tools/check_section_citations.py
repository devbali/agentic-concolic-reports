#!/usr/bin/env python3
"""check_section_citations.py -- keep the `§N.N` citations in src_new honest.

SUPERSEDED FOR NEW CITATIONS, 2026-10-05, by `check_doc_links.py` in this
directory. Owner ruling: stop resolving by number, link by heading. Every
markdown document in `src_new/` has been converted -- the four design
documents moved out of their READMEs into `<module>/DESIGN.md` and every `§`
in a `.md` file became an anchor link, which `check_doc_links.py` verifies.

THIS TOOL STAYS because ~6,900 `§` citations in `.py`, `.rb` and `TODO.txt`
have NOT been converted, and they still resolve the old way: the section
numbers remain on the headings as a stable identifier kept as data. Run this
to keep those honest until they are converted; run `check_doc_links.py --map`
to get the number -> heading map that conversion needs, and
`check_doc_links.py --dangling` for the ones that point at nothing.

`check_doc_links.py --code` IS THE CHECK FOR THE CONVERTED ONES (added
2026-10-05), and it also prints the remaining numbered backlog per module, so
that is the one to read for progress. Note the two tools DISAGREE on a few
counts by design: `check_doc_links.py` knows `GCP_PREREQUISITES` as a citable
document and this one does not, and the two `OWNERS` tables are not identical.
Where they differ, `check_doc_links.py` is the authority -- it is the scheme
in force.

THE DOCUMENTS THEY CITE NO LONGER EXIST AS FILES. On 2026-09-29 each
`DESIGN_*.md` was merged into the README of the module it designs -- as
"PART 2" of that file, every section number unchanged -- and the standalone
file was deleted. `DESIGN_SWEEP`, `DESIGN_ONE_STACK`, `DESIGN_IR` and
`DESIGN_DOMAIN_LAYER` are now NAMES a citation uses, not paths, and `NAMED`
below is the only place that maps a name to the file currently holding it.
That indirection is the point: the citations outlived one move and should
outlive the next.

These citations are far more fragile than they look, because THE SAME NUMBER
MEANS DIFFERENT THINGS IN DIFFERENT DOCUMENTS:

    DESIGN_IR         §5.2  "Fixed and unfixed, for both containers"
    DESIGN_SWEEP      §5.2  "Review before check -- a cost decision ..."
    DESIGN_ONE_STACK  §5.2  "Verified, not believed ..."

So a bare `§5.2` is only resolvable relative to something. THE RULE, settled
2026-09-29 and stated at the top of each merged document:

    A bare `§N.N` is a section of the CITING FILE'S OWN MODULE DOCUMENT.
    A citation to another module's document NAMES it: `DESIGN_SWEEP §5.2`.

`OWNERS` below is that rule made executable: it maps a path prefix to the
document a bare citation in that subtree resolves against. It is the single
place the mapping is written down in checkable form, and the READMEs state
the same thing in prose.

    --check  (default)  fail if any citation resolves to a section that does
                        not exist, or sits in a subtree with no owning
                        document
    --list-unresolved   print every unresolved citation with file:line
    --premerge          resolve against the standalone `DESIGN_*.md` files as
                        they were before 2026-09-29, for a BEFORE number
    --json PATH         write the full unresolved list

Exit status is 0 only when every citation resolves.

WHAT THIS CANNOT CATCH, stated so nobody reads a green run as more than it is:
a bare `§2` in `domains/` that MEANT DESIGN_IR §2 resolves silently to
DESIGN_DOMAIN_LAYER §2, because both documents have a §2. The check proves
every citation lands on a section that EXISTS in the document the rule says it
means; it cannot prove the author meant that document. That is precisely why
the rule is "a citation that leaves its module names the document" -- the
naming is what makes the intent checkable, and this tool only verifies the
half that a machine can see.
"""
import argparse
import collections
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
TREE = os.environ.get("SECTION_CITATION_TREE") or os.path.join(PROJECT, "src_new")
APP_DOCS = os.path.join(PROJECT, "reports", "diaspora", "docs")

#: Path prefix (relative to `src_new/`) -> the document a BARE `§` in that
#: subtree resolves against. Longest prefix wins, so `concolic/model/` may
#: differ from `concolic/`. Each target is the file the document now LIVES
#: IN after the 2026-09-29 merge of `DESIGN_*.md` into module READMEs.
OWNERS = [
    ("sweep/",              "sweep/DESIGN.md"),
    ("tests/",              "sweep/DESIGN.md"),
    ("concolic/model/",     "dumps_to_policy/DESIGN.md"),
    ("concolic/",           "concolic/DESIGN.md"),
    ("dumps_to_policy/",    "dumps_to_policy/DESIGN.md"),
    ("runtimes/",           "dumps_to_policy/DESIGN.md"),
    ("domains/",            "domains/DESIGN.md"),
    ("trace_replay/",       "concolic/DESIGN.md"),
    ("testdata/",           "dumps_to_policy/DESIGN.md"),
    # The top-level README spans every module, so it has NO owning
    # document and every citation in it must NAME one. The file says so.
    ("README.md",           None),
    ("resource_knobs.py",   "sweep/DESIGN.md"),
    ("NOTES_generic_vs_sql.md", "domains/DESIGN.md"),
    ("TODO.txt",            None),
    # There are deliberately NO `DESIGN_*.md` entries here. The four
    # standalone documents were merged into the READMEs above and DELETED on
    # 2026-09-29; `DESIGN_SWEEP` and friends are now citation NAMES (see
    # `NAMED`), not paths. If one ever reappears as a file, it is a mistake,
    # and a bare `§` inside it would land in no owning subtree -- which this
    # tool reports rather than guesses at.
]

#: A citation may NAME its document. These are the names in use, mapped to
#: the file that now holds those sections. The `DESIGN_*` spellings are kept
#: working after the merge precisely so that ~350 existing qualified
#: citations do not have to be rewritten.
NAMED = {
    "DESIGN_SWEEP":        "sweep/DESIGN.md",
    "DESIGN_ONE_STACK":    "concolic/DESIGN.md",
    "DESIGN_IR":           "dumps_to_policy/DESIGN.md",
    "DESIGN_DOMAIN_LAYER": "domains/DESIGN.md",
    # App-side documents, outside this tree. They are cited from `concolic/`
    # and are NOT part of the merge; listed so a qualified citation to one
    # resolves rather than being reported as a hole.
    "DISCIPLINE":          "@app/DISCIPLINE.md",
    "RUNBOOK":             "@app/RUNBOOK.md",
    "CHECKS":              "@app/CHECKS.md",
    "TARGET_FUNCTIONS":    "@app/TARGET_FUNCTIONS.md",
    "ADVERSARY_WINS":      "@app/ADVERSARY_WINS.md",
    "CONCRETE_CHECKER":    "@app/CONCRETE_CHECKER.md",
}

#: A heading that DECLARES a section: `## 4.1.1c Something`, `### 3A.2 ...`,
#: `## 16b. ...`. The trailing period is optional, the id may carry a letter
#: suffix at any level.
_HEADING = re.compile(
    r"^#{1,6}\s+§?\s*([0-9]+[A-Za-z]?(?:\.[0-9]+[a-z]?)*)\.?(?:\s|$)")

#: A citation. Group 1 is an optional document name; group 2 is the id.
#: `§§` ranges and `§5.2-5.4` are handled by scanning every `§`-prefixed id.
#: The gap between the name and the `§` tolerates the tail of a markdown link
#: a line wrap, and a blockquote's `> ` continuation --
#: ``[`dumps_to_policy/README.md`](dumps_to_policy/README.md) §4`` and
#: ``DESIGN_IR\n§4.1.1f`` are both one qualified citation to a reader. The gap
#: is capped at six characters so a name cannot capture a `§` a clause away.
_CITE = re.compile(
    r"(?:\b(DESIGN_[A-Z_]+|DISCIPLINE|RUNBOOK|CHECKS|TARGET_FUNCTIONS"
    r"|ADVERSARY_WINS|CONCRETE_CHECKER|[Oo]ne[- ][Ss]tack)"
    r"(?:\.md)?(?:'s)?[\s'\"`)\]>]{0,6})?"
    r"§\s*([0-9]+[A-Za-z]?(?:\.[0-9]+[a-z]?)*)")

#: Prose names a document too. `DESIGN_SWEEP` writes "one-stack §17.0" and
#: "One-stack's §12.6" throughout, which NAMES the document as surely as the
#: filename does, so the check honours it rather than forcing a rewrite of
#: readable prose into filenames.
_ALIASES = {"one-stack": "DESIGN_ONE_STACK", "one stack": "DESIGN_ONE_STACK"}


def _canon(name):
    return _ALIASES.get(name.lower(), name)

_SKIP_DIRS = {".git", "__pycache__", ".pytest_cache", "node_modules",
              "venvs", "dist", "java", "classes", "blockaid"}


#: A top-level ordered-list item, unindented, in either of the two forms these
#: documents use: `7. **Omission is a red ...` and `**4. The profile is a
#: separate input ...`. They ARE cited as sections -- DESIGN_ONE_STACK §3.7 is
#: the seventh principle in §3 and §11.4 the fourth decision in §11 -- so an
#: extractor that reads only headings reports ~250 false holes.
_LIST_ITEM = re.compile(r"^\*{0,2}([0-9]{1,2})\.\s")


def _read(path):
    """The document's text. Under `--premerge` a `git:<rel>` pseudo-path is
    read out of a git ref, so the BEFORE and AFTER numbers are produced by one
    identical checker rather than two."""
    if path.startswith("git:"):
        import subprocess
        r = subprocess.run(["git", "show", "%s:%s" % (_premerge_ref, path[4:])],
                           cwd=TREE, capture_output=True, text=True)
        return r.stdout if r.returncode == 0 else None
    if not os.path.exists(path):
        return None
    return open(path, errors="replace").read()


def sections_of(path):
    """Every section id a document declares: headings, plus the numbered
    list items directly under a top-level heading (see `_LIST_ITEM`)."""
    body = _read(path)
    if body is None:
        return None
    out = set()
    fence = False
    current = None
    for line in body.split("\n"):
        if line.startswith("```"):
            fence = not fence
            continue
        if fence:
            continue
        m = _HEADING.match(line)
        if m:
            out.add(m.group(1))
            current = m.group(1)
            continue
        if current and "." not in current:
            li = _LIST_ITEM.match(line)
            if li:
                out.add("%s.%d" % (current, int(li.group(1))))
    return out


#: `--premerge` reads the same sections out of the standalone `DESIGN_*.md`
#: files they lived in before 2026-09-29. It exists for exactly one purpose:
#: producing a BEFORE number, so a citation that was already broken can be
#: reported separately from one the merge broke.
#:
#: THOSE FILES ARE DELETED. The mode therefore only works against a git ref
#: that PREDATES the merge (`--premerge-ref`, default HEAD), and `main()`
#: refuses to run rather than resolving nothing and reporting that every
#: citation is broken -- which is the failure mode this whole tool exists to
#: prevent, one level up.
PREMERGE = {
    "sweep/DESIGN.md":           "DESIGN_SWEEP.md",
    "concolic/DESIGN.md":        "DESIGN_ONE_STACK.md",
    "dumps_to_policy/DESIGN.md": "DESIGN_IR.md",
    "domains/DESIGN.md":         "DESIGN_DOMAIN_LAYER.md",
}

#: In `--premerge` mode the standalone documents still exist, so a bare `§`
#: inside one is a self-citation and the file owns itself. These entries are
#: added to `OWNERS` only in that mode; the merged tree has no such files.
PREMERGE_OWNERS = [(doc, readme) for readme, doc in PREMERGE.items()]
_premerge = False
_premerge_ref = "HEAD"


def doc_path(token):
    """Resolve an OWNERS/NAMED value to a filesystem path."""
    if token is None:
        return None
    if token.startswith("@app/"):
        return os.path.join(APP_DOCS, token[len("@app/"):])
    if _premerge and token in PREMERGE:
        # Prefer a standalone document if this tree still has a real one
        # (a redirect stub was ~19 lines); otherwise read it out of the ref.
        cand = os.path.join(TREE, PREMERGE[token])
        if os.path.exists(cand) and sum(1 for _ in open(cand)) > 50:
            return cand
        return "git:" + PREMERGE[token]
    return os.path.join(TREE, token)


def owner_of(rel):
    """The document a BARE citation in `rel` resolves against."""
    best = None
    for prefix, doc in OWNERS:
        if rel == prefix or rel.startswith(prefix):
            if best is None or len(prefix) > len(best[0]):
                best = (prefix, doc)
    return best


def source_files():
    out = []
    for root, dirs, files in os.walk(TREE):
        dirs[:] = [d for d in dirs if d not in _SKIP_DIRS]
        for f in files:
            if f.endswith((".py", ".rb", ".md")):
                out.append(os.path.relpath(os.path.join(root, f), TREE))
    return sorted(out)


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--list-unresolved", action="store_true")
    ap.add_argument("--json", metavar="PATH")
    ap.add_argument("--premerge", action="store_true",
                    help="resolve against the pre-2026-09-29 standalone "
                         "documents, for a BEFORE number")
    ap.add_argument("--premerge-ref", default="HEAD", metavar="REF",
                    help="the git ref --premerge reads those documents from; "
                         "it must predate the merge (default HEAD)")
    args = ap.parse_args(argv[1:])
    global _premerge, _premerge_ref
    _premerge, _premerge_ref = args.premerge, args.premerge_ref
    if _premerge:
        OWNERS.extend(PREMERGE_OWNERS)

    if _premerge:
        # Refuse rather than resolve nothing. Without this, a ref in which the
        # documents are already deleted makes every citation "unresolved",
        # which reads exactly like catastrophe and means nothing.
        missing = [d for d in sorted(PREMERGE)
                   if not (sections_of(doc_path(d)) or ())]
        if missing:
            print("--premerge cannot run against %r.\n" % _premerge_ref)
            print("It needs the standalone DESIGN_*.md documents, which were")
            print("merged into the module READMEs and DELETED on 2026-09-29.")
            print("These did not resolve: %s" % ", ".join(
                PREMERGE[d] for d in missing))
            print("\nPass --premerge-ref <commit-before-the-merge>. If no such")
            print("commit exists in this repository, the before/after")
            print("comparison is NOT reproducible and no number should be")
            print("quoted for it.")
            return 2

    cache = {}

    def secs(token):
        if token not in cache:
            cache[token] = sections_of(doc_path(token))
        return cache[token]

    checked = resolved = 0
    unresolved = []          # (rel, lineno, raw, doc, why)
    no_owner = []
    per_doc = collections.Counter()

    for rel in source_files():
        own = owner_of(rel)
        text = open(os.path.join(TREE, rel), errors="replace").read()
        # Scanned as WHOLE TEXT, not line by line: prose wraps, and
        # `DESIGN_IR\n\u00a74.1.1f` is one qualified citation to a reader.
        for m in _CITE.finditer(text):
            if True:
                n = text.count("\n", 0, m.start()) + 1
                name, sid = m.group(1), m.group(2)
                if name:
                    name = _canon(name)
                checked += 1
                if name:
                    token, kind = NAMED.get(name), "named"
                else:
                    token, kind = (own[1] if own else None), "bare"
                    if own is None:
                        no_owner.append((rel, n, m.group(0)))
                        unresolved.append((rel, n, m.group(0), "-",
                                           "no owning document for this subtree"))
                        continue
                if token is None:
                    unresolved.append((rel, n, m.group(0), name or "-",
                                       "document not in the ownership table"))
                    continue
                s = secs(token)
                if s is None:
                    unresolved.append((rel, n, m.group(0), token,
                                       "document file not found"))
                    continue
                if sid in s:
                    resolved += 1
                    per_doc[(token, kind)] += 1
                else:
                    unresolved.append((rel, n, m.group(0), token,
                                       "no section %s in that document" % sid))

    print("citations checked            : %d" % checked)
    print("resolved                     : %d" % resolved)
    print("unresolved                   : %d" % len(unresolved))
    print("  of which: no owning doc    : %d" % len(no_owner))
    print()
    print("resolved, by document:")
    for token in sorted({t for t, _ in per_doc}):
        print("  %-34s bare=%-6d named=%d"
              % (token, per_doc[(token, "bare")], per_doc[(token, "named")]))

    if unresolved:
        print()
        by_reason = collections.Counter(u[4] for u in unresolved)
        for r, c in by_reason.most_common():
            print("  %-46s %d" % (r, c))
        print()
        grouped = collections.Counter((u[0], u[2], u[3], u[4]) for u in unresolved)
        print("unresolved citations, grouped (%d distinct):" % len(grouped))
        for (f, raw, doc, why), c in sorted(grouped.items()):
            print("  %-56s %-22s x%-4d %s" % (f, raw.strip(), c, why))

    if args.list_unresolved:
        print()
        for f, n, raw, doc, why in unresolved:
            print("  %s:%d  %s  -> %s  (%s)" % (f, n, raw.strip(), doc, why))

    if args.json:
        json.dump({"checked": checked, "resolved": resolved,
                   "unresolved": [{"file": f, "line": n, "cite": raw,
                                   "doc": d, "why": w}
                                  for f, n, raw, d, w in unresolved]},
                  open(args.json, "w"), indent=2)

    print()
    print("verdict: %s" % ("every citation resolves" if not unresolved
                           else "%d CITATIONS DO NOT RESOLVE" % len(unresolved)))
    return 0 if not unresolved else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
