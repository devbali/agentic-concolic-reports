#!/usr/bin/env python3
"""check_doc_links.py -- verify every markdown link in `src_new/` resolves.

WHY THIS REPLACES `check_section_citations.py` AS THE CITATION CHECK.
---------------------------------------------------------------------
Citations used to be bare section numbers: `DESIGN_SWEEP §5.2`, or just
`§5.2`. That scheme cannot be checked, and it misleads readers, for one
reason: THE SAME NUMBER MEANS DIFFERENT THINGS IN DIFFERENT DOCUMENTS.

    DESIGN_IR         §5.2  "Fixed and unfixed, for both containers"
    DESIGN_SWEEP      §5.2  "The pre-gate before check ..."
    DESIGN_ONE_STACK  §5.2  "Verified, not believed ..."

A bare `§5.2` is resolvable only relative to a path-prefix table nobody reads,
and `§16.2` tells a reader nothing about what it says. Owner ruling: stop
resolving by number; link by heading. A markdown anchor either resolves or it
does not, which is mechanical, and the link text says what the section is
about, which is the readability win.

So, and the scheme is now ONE scheme in markdown and in code:

  * In markdown, cite with a real anchor link --
    `[the config](DESIGN.md#4-the-config)`. `--check` CHECKS THOSE.
  * In a comment or a docstring, cite with the same relative path and the
    same anchor, without the brackets: `../DESIGN.md#4-the-config`. The
    anchor already carries the heading's words, so a markdown label would
    repeat them at twice the width. `--code` CHECKS THOSE THE SAME WAY --
    the file must exist and the anchor must match a heading.
  * The path is relative to the CITING FILE's own directory, so it differs
    per file and is computed, never templated.
  * Two kinds of citation cannot be a path, and stay the NAMED prose form
    `(DISCIPLINE, "the heading")`, which `--code` also resolves: the
    application-side documents under `reports/<app>/docs/`, because a
    relative path to one would write the application's directory name into
    the engine tree, and the one DESIGN_ONE_STACK heading that names the
    application, because its anchor does too. `domains/` has a test that
    forbids that name in any `.py` there.
  * Section NUMBERS stay on the headings as a stable identifier kept as
    data, and the `section` field on the wire is data too. Neither is a
    citation form any more: a `§N` in a comment or a docstring is an ERROR
    (`_KEPT_NUMBERED` lists the handful left, each with its reason), and a
    `§N` inside any other string literal is REPORTED and left alone, because
    such a string is compared, matched or emitted.

MODES
-----
    --check      (default) every markdown link in the tree resolves: the file
                 exists, and an `#anchor` matches a heading in it. Also that
                 NO numbered citation is left in markdown PROSE -- a heading
                 keeps its number (that is the identifier every anchor is
                 derived from) and a `§` inside a fence is example text, but
                 anywhere else in a markdown file a number is an error, the
                 same rule `--code` applies to comments. Exit 0 only if both
                 hold.
    --map        the number -> heading map for the four design documents.
    --dangling   every `§N` citation that resolves to NO heading in the
                 document the old prefix rule says it means, with where the
                 number DOES exist. These are real broken citations, most of
                 them from before this change.
    --ambiguous  numbers that map to MORE THAN ONE heading in one document.
    --code       the citations in `.py` / `.rb` / `.txt` / `.java`, three checks in
                 one pass:
                   * every `path.md#anchor` LINK in a comment or docstring
                     resolves -- the file exists relative to the citing
                     file, and the anchor matches a heading in it;
                   * every bare `SOMETHING.md` named in a comment or
                     docstring still exists somewhere in the project, which
                     is the check that a deleted document cannot leave
                     silent references behind;
                   * every NAMED prose citation resolves against a real
                     heading, exactly or by a unique prefix (never
                     ambiguously).
                 The LINK check also covers `.java`; the numbered-form
                 check does not, because there is no Java comment parser here
                 and the rule is about comments only.
                 A NUMBERED `§N` citation in a comment or docstring is an
                 ERROR. One inside any other string literal is reported, not
                 an error: that string is compared, matched or emitted, so
                 it is out of scope for a documentation pass. Exit 0 only if
                 nothing is broken and no numbered citation survives outside
                 `_KEPT_NUMBERED`.

ANCHORS ARE GITHUB-FLAVOURED. Lowercase, strip anything that is not a word
character / space / hyphen, spaces to hyphens, NO collapsing of runs -- so
`## 5.3 What the pre-gate does NOT ask - the gap rows` (with an em dash)
anchors as `53-what-the-pre-gate-does-not-ask--the-gap-rows`, two hyphens.
Duplicate headings get `-1`, `-2`, ... as GitHub does.
"""
import argparse
import ast
import collections
import io
import os
import re
import sys
import tokenize

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
TREE = os.environ.get("DOC_LINK_TREE") or os.path.join(PROJECT, "src_new")
APP_DOCS = os.path.join(PROJECT, "reports", "diaspora", "docs")

#: The four design documents, by the citation KEY that names them. These keys
#: outlive the files' paths and are what a docstring should say.
DOCS = {
    # One document per module: each module's design IS its README, and the
    # KEY outlives the path, which is the point of this map.
    "DESIGN_ONE_STACK":    "concolic/README.md",
    "DESIGN_SWEEP":        "sweep/README.md",
    "DESIGN_IR":           "dumps_to_policy/README.md",
    "DESIGN_DOMAIN_LAYER": "domains/README.md",
    "DESIGN_SLICE":        "dumps_to_slice/README.md",
    # Not a "design document" in the four-document sense, but it DOES carry
    # numbered sections (`3a`, `3c`, ...) that are cited from `sweep/`, and a
    # bare `§3c` inside it used to resolve against DESIGN_SWEEP and dangle.
    "GCP_PREREQUISITES":   "sweep/GCP_PREREQUISITES.md",
}

#: Application-side documents, outside this tree, cited by name.
APP = {
    "DISCIPLINE": "DISCIPLINE.md", "RUNBOOK": "RUNBOOK.md",
    "CHECKS": "CHECKS.md", "TARGET_FUNCTIONS": "TARGET_FUNCTIONS.md",
    "ADVERSARY_WINS": "ADVERSARY_WINS.md",
    "CONCRETE_CHECKER": "CONCRETE_CHECKER.md",
}

#: Which document a BARE `§` in a subtree used to resolve against. Kept ONLY
#: so `--dangling` can report the old scheme's holes; it is not how anything
#: should be cited from here.
OWNERS = [
    # NOTE `sweep/GCP_PREREQUISITES.md` is deliberately NOT given itself as
    # its owner, even though it has numbered sections of its own. Its bare
    # `§N` citations are to DESIGN_SWEEP §8.4 (it is a cross-check OF that
    # section), and its two references to its own `3c` are anchor links.
    ("sweep/", "DESIGN_SWEEP"), ("tests/", "DESIGN_SWEEP"),
    ("concolic/model/", "DESIGN_IR"), ("concolic/", "DESIGN_ONE_STACK"),
    ("dumps_to_policy/", "DESIGN_IR"), ("runtimes/", "DESIGN_IR"),
    ("domains/", "DESIGN_DOMAIN_LAYER"), ("trace_replay/", "DESIGN_ONE_STACK"),
    ("testdata/", "DESIGN_IR"), ("resource_knobs.py", "DESIGN_SWEEP"),
    ("NOTES_generic_vs_sql.md", "DESIGN_DOMAIN_LAYER"),
]

_SKIP_DIRS = {".git", "__pycache__", ".pytest_cache", "node_modules",
              "venvs", "dist", "java", "classes", "blockaid"}

_HEADING = re.compile(r"^(#{1,6})\s+(.*?)\s*$")
_NUM = re.compile(r"^§?\s*([0-9]+[A-Za-z]?(?:\.[0-9]+[a-z]?)*)\.?(?:\s+|$)")
#: `[text](target)`, target not starting with a scheme. Reference-style and
#: bare autolinks are not used in this tree.
_LINK = re.compile(r"\[(?P<text>(?:[^\[\]]|\[[^\]]*\])*)\]"
                   r"\((?P<href>[^()\s]*(?:\([^()]*\)[^()\s]*)*)\)")
_CITE = re.compile(
    r"(?:\b(DESIGN_[A-Z_]+|DISCIPLINE|RUNBOOK|CHECKS|TARGET_FUNCTIONS"
    r"|ADVERSARY_WINS|CONCRETE_CHECKER|GCP_PREREQUISITES"
    r"|[Oo]ne[- ][Ss]tack)"
    r"(?:\.md)?(?:'s)?[\s'\"`)\]>]{0,6})?"
    r"§\s*([0-9]+[A-Za-z]?(?:\.[0-9]+[a-z]?)*)")
_ALIASES = {"one-stack": "DESIGN_ONE_STACK", "one stack": "DESIGN_ONE_STACK"}
#: A top-level ordered-list item, which these documents DO cite as a section
#: (the seventh principle under `## 3. Principles` is cited as 3.7).
_LIST_ITEM = re.compile(r"^\*{0,2}([0-9]{1,2})\.\s+(.*)")

#: THE CITATION FORM FOR CODE. A docstring cannot carry a markdown link, so it
#: names the document and the heading in prose: `(DESIGN_IR, "A standardised
#: dump IR")`. Either quote style, optional surrounding parens, and the
#: document name may be backticked. This is what `--code` checks, and it is
#: the target form the `§N` citations in `.py`/`.rb` are being converted to.
#:
#: The heading may be an UNNUMBERED one, and may be cited by a UNIQUE PREFIX
#: of itself -- which is not only a convenience: `domains/` has a test that
#: forbids the application's name in any `.py` there, and one heading of
#: DESIGN_ONE_STACK contains it, so a prefix is the only legal citation at
#: that site. An AMBIGUOUS prefix is rejected: that is the failure the
#: numbered scheme had, and it is not being reintroduced.
#:
#: A quoted heading MAY WRAP ONCE. Docstrings wrap at 79 columns and several
#: of these headings are long, so a citation that had to fit on one line
#: would be a citation people silently break -- and a broken one is invisible
#: to this check, which is worse than a long line. One continuation only, with
#: an optional `#`/`#:` comment marker, and `_norm` collapses the whitespace.
_DOCKEYS = (r"`?\b(DESIGN_[A-Z_]+|DISCIPLINE|RUNBOOK|CHECKS|TARGET_FUNCTIONS"
            r"|ADVERSARY_WINS|CONCRETE_CHECKER|GCP_PREREQUISITES)`?\s*,\s*")


def _quoted(group, bad):
    """A quoted heading that may wrap ONCE, excluding only its own CLOSING
    delimiter.

    Excluding only the closer is what lets a heading with an APOSTROPHE be
    cited in full inside double quotes. `In Stage 1, the note is part of an
    event's identity` is a real heading, and a scheme that could not name it
    would push every such citation back to a vague prefix -- which is the
    readability the named scheme exists to buy.
    """
    return (r"(?P<%s>[^%s\n]{3,160}"
            r"(?:\n[ \t]*(?:\#:?[ \t]*)?[^%s\n]{0,160})?)"
            % (group, bad, bad))


_NAMED = re.compile(
    _DOCKEYS + "(?:"
    + '["\u201c]' + _quoted("h1", '"\u201d') + '["\u201d]'
    + "|"
    + "['\u2018]" + _quoted("h2", "'\u2019") + "['\u2019]"
    + ")")


def _norm(text):
    """A heading reduced to what a citation has to get right: the words.

    Markdown marks, the section number, surrounding punctuation and runs of
    whitespace are all noise -- a docstring quoting "The note envelope" must
    match `### 4.1.1c The note envelope`, and must NOT have to reproduce the
    number it is deliberately replacing.
    """
    t = re.sub(r"<[^>]+>", "", text.strip())
    # A citation that wrapped carries its continuation line's scaffolding
    # INSIDE the quotes: a comment marker (`"...prefix of a\n#: leaf group"`)
    # or a Python implicit-string-concatenation boundary (`"...one "\n"base
    # class..."`). Strip the scaffolding, not just the whitespace, or the wrap
    # silently changes the words. The optional quote either side of the break
    # must be followed by the break itself, so an apostrophe INSIDE a word
    # (`an event's identity`) is never touched.
    t = re.sub(r"[\"'’”]?[ \t]*\n[ \t]*"
               r"(?:#+:?|//+|--|\*)?[ \t]*[\"'‘“]?", " ", t)
    t = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", t)   # links keep their text
    t = re.sub(r"[`*_~]", "", t)
    t = re.sub(r"^§?\s*[0-9]+[A-Za-z]?(?:\.[0-9]+[a-z]?)*\.?\s*", "", t)
    t = re.sub(r"\s+", " ", t)
    return t.strip(" .:—-").lower()


def slug(text):
    """A GitHub-flavoured heading anchor. No run collapsing: that is what
    GitHub does, and getting it wrong here would pass links that 404."""
    t = text.strip().lower()
    t = re.sub(r"<[^>]+>", "", t)                 # inline html
    t = re.sub(r"[`*_~]", "", t)                  # md emphasis/code marks
    t = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", t)   # links keep their text
    t = re.sub(r"[^\w\s-]", "", t, flags=re.UNICODE)
    return t.replace(" ", "-")


def anchors_of(path):
    """Every anchor a markdown file offers, GitHub's duplicate rule applied."""
    try:
        body = open(path, errors="replace").read()
    except OSError:
        return None
    out, seen, fence = set(), collections.Counter(), False
    for line in body.split("\n"):
        if line.startswith("```") or line.startswith("~~~"):
            fence = not fence
            continue
        if fence:
            continue
        m = _HEADING.match(line)
        if not m:
            continue
        base = slug(m.group(2))
        n = seen[base]
        seen[base] += 1
        out.add(base if n == 0 else "%s-%d" % (base, n))
    return out


def sections_of(path):
    """number -> [heading text, ...] for one document."""
    out = collections.defaultdict(list)
    try:
        body = open(path, errors="replace").read()
    except OSError:
        return out
    fence, cur = False, None
    for n, line in enumerate(body.split("\n"), 1):
        if line.startswith("```") or line.startswith("~~~"):
            fence = not fence
            continue
        if fence:
            continue
        m = _HEADING.match(line)
        if m:
            nm = _NUM.match(m.group(2))
            if nm:
                rest = m.group(2)[nm.end():].strip() or m.group(2).strip()
                out[nm.group(1)].append((rest, n, slug(m.group(2))))
                cur = nm.group(1)
            else:
                cur = None
            continue
        if cur and "." not in cur:
            li = _LIST_ITEM.match(line)
            if li:
                txt = re.sub(r"\*\*", "", li.group(2)).strip()
                txt = txt.split(".")[0].split(" — ")[0][:72]
                out["%s.%d" % (cur, int(li.group(1)))].append((txt, n, None))
    return out


def headings_of(path):
    """EVERY heading text a document offers, numbered or not.

    `sections_of` is keyed on the leading section NUMBER and therefore cannot
    see a heading that has none -- but the named scheme cites by heading, so
    an unnumbered heading is just as citable, and `--code` must be able to
    resolve one. Returns [heading text, ...] in document order.
    """
    out = []
    try:
        body = open(path, errors="replace").read()
    except OSError:
        return out
    fence = False
    for line in body.split("\n"):
        if line.startswith("```") or line.startswith("~~~"):
            fence = not fence
            continue
        if fence:
            continue
        m = _HEADING.match(line)
        if m:
            out.append(m.group(2))
    return out


def doc_path(key):
    if key in DOCS:
        return os.path.join(TREE, DOCS[key])
    if key in APP:
        return os.path.join(APP_DOCS, APP[key])
    return None


def owner_of(rel):
    best = None
    for p, d in OWNERS:
        if rel == p or rel.startswith(p):
            if best is None or len(p) > len(best[0]):
                best = (p, d)
    return best


def files(exts):
    out = []
    for root, dirs, fs in os.walk(TREE):
        dirs[:] = [d for d in dirs if d not in _SKIP_DIRS]
        for f in fs:
            if f.endswith(exts):
                out.append(os.path.relpath(os.path.join(root, f), TREE))
    return sorted(out)


# ---------------------------------------------------------------------------
# CODE CITATIONS
#
# A code citation is a LINK, exactly as a markdown one is: a path relative to
# the citing FILE's own directory, plus an anchor that must match a heading.
# `#` comments and docstrings carry them; nothing else may be rewritten, so a
# citation inside any other string literal is reported and left alone.
# ---------------------------------------------------------------------------

#: `../DESIGN.md#the-heading`, as it appears in a comment. No brackets: the
#: anchor already carries the heading's words, and a markdown label would
#: repeat them at twice the width.
_CODE_LINK = re.compile(r"(?<![\w#\-])((?:\.\./)*[\w][\w./-]*\.md)#([\w-]+)")
#: a markdown file named WITHOUT an anchor. Checked for existence only -- a
#: reference to a file that no longer exists is the failure that deleting a
#: document used to cause silently.
_CODE_FILE = re.compile(r"(?<![\w./-])([\w][\w.-]*\.md)\b")

#: The numbered citations deliberately left in a comment, each with its
#: reason. A `§N` anywhere else in a comment or docstring is an ERROR: the
#: conversion is done, and the old form is no longer a backlog.
_KEPT_NUMBERED = {
    ("concolic/check.py", "16b"):
        "a verbatim quote, inside a comment that says so, of the output "
        "string this line used to emit; rewriting the quote would misreport "
        "what the string said",
    ("TODO.txt", "6.2"):
        "a verbatim quote of `sweep/agentd/fileproto.py`'s live refusal "
        "string, which is emitted output and so is itself not rewritten",
    ("TODO.txt", "9"):
        "names a section of an application-side `targets.rb`, not of a "
        "design document -- there is no heading in this tree to link",
    ("TODO.txt", "5"):
        "names a section of `reports/autolab/docs/LAUNCH_SWEEP.md`, which is "
        "outside the documents this scheme covers",
    ("TODO.txt", "8"):
        "the second half of the same `LAUNCH_SWEEP.md` reference",
}

#: How many sites `_KEPT_NUMBERED` is allowed to excuse. The list is keyed on
#: (file, section) rather than on a line, so without a count a SECOND `§16b`
#: appearing in `concolic/check.py` would be waved through by the entry
#: written for the first one. Raising this number is a decision, which is the
#: point of having to raise it.
_KEPT_NUMBERED_SITES = 5


def _py_regions(src):
    """Char spans of every COMMENT and every DOCSTRING in a Python source."""
    lines = src.split("\n")
    starts = [0]
    for ln in lines:
        starts.append(starts[-1] + len(ln) + 1)

    def off(lineno, col):
        return starts[lineno - 1] + col

    out = []
    try:
        toks = list(tokenize.generate_tokens(io.StringIO(src).readline))
    except (tokenize.TokenError, IndentationError, SyntaxError):
        return None
    for t in toks:
        if t.type == tokenize.COMMENT:
            out.append((off(t.start[0], t.start[1]), off(t.end[0], t.end[1])))
    try:
        tree = ast.parse(src)
    except SyntaxError:
        return None
    for node in ast.walk(tree):
        if not isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef,
                                 ast.AsyncFunctionDef)):
            continue
        body = getattr(node, "body", None)
        if not body:
            continue
        first = body[0]
        if (isinstance(first, ast.Expr)
                and isinstance(first.value, ast.Constant)
                and isinstance(first.value.value, str)):
            c = first.value
            out.append((off(c.lineno, c.col_offset),
                        off(c.end_lineno, c.end_col_offset)))
    return sorted(out)


def _rb_regions(src):
    """Char spans of Ruby comments: a `#` that is not inside a string, to the
    end of its line, plus `=begin`/`=end` blocks."""
    out, pos, block = [], 0, False
    for line in src.split("\n"):
        n, s = len(line), line.strip()
        if s == "=begin":
            block = True
        elif s == "=end":
            block = False
        elif block:
            out.append((pos, pos + n))
        else:
            i, quote = 0, None
            while i < n:
                ch = line[i]
                if quote:
                    if ch == "\\":
                        i += 2
                        continue
                    if ch == quote:
                        quote = None
                elif ch in "\"'":
                    quote = ch
                elif ch == "#":
                    out.append((pos + i, pos + n))
                    break
                i += 1
        pos += n + 1
    return out


def code_regions(rel, src):
    if rel.endswith(".py"):
        return _py_regions(src)
    if rel.endswith(".rb"):
        return _rb_regions(src)
    return [(0, len(src))]


def _md_basenames():
    """Every markdown file in the project, by basename -- what a bare
    `SOMETHING.md` in a comment is allowed to mean."""
    out = collections.defaultdict(list)
    for f in sorted(os.listdir(PROJECT)):
        if f.endswith(".md"):
            out[f].append(os.path.join(PROJECT, f))
    for root in (TREE, os.path.join(PROJECT, "reports")):
        for d, dirs, fs in os.walk(root):
            dirs[:] = [x for x in dirs if x not in _SKIP_DIRS]
            for f in fs:
                if f.endswith(".md"):
                    out[f].append(os.path.join(d, f))
    return out


def check_code_links():
    """Every code citation resolved as a LINK, and the numbered form treated
    as an error rather than a backlog.

    Returns (counts, broken, numbered_bad, numbered_in_strings) where
    `counts` carries the totals and each list holds (rel, line, what, why).
    """
    cache, names = {}, _md_basenames()

    def anchors(path):
        if path not in cache:
            cache[path] = anchors_of(path)
        return cache[path]

    counts = collections.Counter()
    broken, num_bad, num_str = [], [], []
    for rel in files((".py", ".rb", ".txt", ".java")):
        path = os.path.join(TREE, rel)
        src = open(path, errors="replace").read()
        regs = code_regions(rel, src)
        if regs is None:
            broken.append((rel, 0, "", "could not be parsed"))
            continue

        def inside(a, b):
            return any(s <= a and b <= e for s, e in regs)

        def line_of(p):
            return src.count("\n", 0, p) + 1

        for m in _CODE_LINK.finditer(src):
            if not inside(m.start(), m.end()):
                continue
            counts["links"] += 1
            filepart, frag = m.group(1), m.group(2)
            target = os.path.normpath(
                os.path.join(os.path.dirname(path), filepart))
            if not os.path.exists(target):
                broken.append((rel, line_of(m.start()), m.group(0),
                               "no such file"))
                continue
            a = anchors(target)
            if a is None:
                broken.append((rel, line_of(m.start()), m.group(0),
                               "target unreadable"))
            elif frag in a:
                counts["links_ok"] += 1
            else:
                broken.append((rel, line_of(m.start()), m.group(0),
                               "no heading in %s anchors to #%s"
                               % (filepart, frag)))
        for m in _CODE_FILE.finditer(src):
            if not inside(m.start(), m.end()):
                continue
            if m.end() < len(src) and src[m.end()] == "#":
                continue                      # the anchored form, done above
            counts["files"] += 1
            base = m.group(1)
            here = os.path.normpath(
                os.path.join(os.path.dirname(path), base))
            if os.path.exists(here) or base in names:
                counts["files_ok"] += 1
            else:
                broken.append((rel, line_of(m.start()), base,
                               "no file of that name anywhere in the project"))
        if rel.endswith(".java"):
            # NO NUMBERED-FORM SCAN HERE. `code_regions` has a Python and a
            # Ruby comment parser and no Java one, so for `.java` it returns
            # the whole file and cannot tell a comment from a string literal
            # -- and "the numbered form is an error" is a claim about comments
            # only. The LINK scan above IS sound for Java: a path plus anchor
            # either resolves or it does not, wherever it sits.
            continue
        for m in _CITE.finditer(src):
            sid = m.group(2)
            if not inside(m.start(), m.end()):
                counts["numbered_in_string"] += 1
                num_str.append((rel, line_of(m.start()),
                                src[m.start():m.end()].replace("\n", " "),
                                "in a string: compared, matched or emitted"))
                continue
            why = _KEPT_NUMBERED.get((rel, sid))
            if why:
                counts["numbered_kept"] += 1
                continue
            counts["numbered_bad"] += 1
            num_bad.append((rel, line_of(m.start()),
                            src[m.start():m.end()].replace("\n", " "),
                            "the numbered form is no longer a citation form"))
    return counts, broken, num_bad, num_str


def md_prose_regions(src):
    """Everything in a markdown file outside a fenced code block and outside a
    HEADING -- the part of a markdown file where a citation may appear.

    A heading keeps its section number: that number is the stable identifier,
    and it is what every anchor is derived from, so rewriting it would destroy
    the thing citations resolve against. A `§` inside a fence is example text.
    """
    out, pos, fence = [], 0, False
    for line in src.split("\n"):
        n = len(line)
        if line.startswith("```") or line.startswith("~~~"):
            fence = not fence
        elif not fence and not line.startswith("#"):
            out.append((pos, pos + n))
        pos += n + 1
    return out


def numbered_in_markdown():
    """Numbered citations left in markdown PROSE, which are an error: markdown
    has had anchor links available all along."""
    bad = []
    for rel in files((".md",)):
        src = open(os.path.join(TREE, rel), errors="replace").read()
        regs = md_prose_regions(src)
        for m in _CITE.finditer(src):
            if any(s <= m.start() and m.end() <= e for s, e in regs):
                bad.append((rel, src.count("\n", 0, m.start()) + 1,
                            m.group(0).replace("\n", " ")))
    return bad


def check_links():
    cache = {}

    def anchors(path):
        if path not in cache:
            cache[path] = anchors_of(path)
        return cache[path]

    checked = ok = 0
    broken = []          # (rel, line, text, href, why)
    for rel in files((".md",)):
        path = os.path.join(TREE, rel)
        body = open(path, errors="replace").read()
        for m in _LINK.finditer(body):
            href = m.group("href").strip()
            if (not href or href.startswith(("http://", "https://", "mailto:"))
                    or href.startswith("<")):
                continue
            line = body.count("\n", 0, m.start()) + 1
            checked += 1
            filepart, _, frag = href.partition("#")
            target = (path if not filepart
                      else os.path.normpath(
                          os.path.join(os.path.dirname(path), filepart)))
            if not os.path.exists(target):
                broken.append((rel, line, m.group("text"), href,
                               "no such file"))
                continue
            if not frag:
                ok += 1
                continue
            if not target.endswith(".md"):
                ok += 1          # an anchor into a non-markdown file: skip
                continue
            a = anchors(target)
            if a is None:
                broken.append((rel, line, m.group("text"), href,
                               "target unreadable"))
            elif frag in a:
                ok += 1
            else:
                broken.append((rel, line, m.group("text"), href,
                               "no heading anchors to #%s" % frag))
    return checked, ok, broken


def check_code(secs):
    """Every NAMED citation in code, resolved against a heading.

    Returns (checked, ok, bad, backlog) where `bad` is
    (rel, line, key, quoted, why) and `backlog` counts the `§N` citations
    still left in `.py`/`.rb`/`.txt`, by top-level module.
    """
    # key -> {normalised heading: the heading as written}. Built from EVERY
    # heading, not from `secs`: `sections_of` is keyed on the section number
    # and so omits every unnumbered heading, which the named scheme can cite.
    index = {}
    for key in list(DOCS) + list(APP):
        path = doc_path(key)
        h = {}
        for text in headings_of(path) if path else []:
            h.setdefault(_norm(text), text)
        index[key] = h

    checked = ok = 0
    bad = []
    backlog = collections.Counter()
    for rel in files((".py", ".rb", ".txt", ".java")):
        body = open(os.path.join(TREE, rel), errors="replace").read()
        regs = code_regions(rel, body)
        for m in _NAMED.finditer(body):
            if regs is not None and not any(
                    s <= m.start() and m.end() <= e for s, e in regs):
                backlog["(named, inside a string)"] += 1
                continue
            key = m.group(1)
            quoted = m.group("h1") or m.group("h2")
            line = body.count("\n", 0, m.start()) + 1
            checked += 1
            if key not in index:
                bad.append((rel, line, key, quoted, "no such document"))
                continue
            want = _norm(quoted)
            if want in index[key]:
                ok += 1
                continue
            # A unique prefix is accepted: a long heading may be cited by its
            # first clause. Ambiguity is NOT accepted -- that is the exact
            # failure the numbered scheme had.
            hits = [v for k, v in index[key].items() if k.startswith(want)]
            if len(hits) == 1:
                ok += 1
            elif len(hits) > 1:
                bad.append((rel, line, key, quoted,
                            "matches %d headings: %s" % (
                                len(hits), " | ".join(h[:40] for h in hits[:3]))))
            else:
                bad.append((rel, line, key, quoted,
                            "no heading in %s reads like this" % key))
        own = owner_of(rel)
        for m in _CITE.finditer(body):
            name = m.group(1)
            if name:
                name = _ALIASES.get(name.lower(), name)
            if name or own:
                backlog[rel.split("/")[0]] += 1
    return checked, ok, bad, backlog


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--map", action="store_true",
                    help="the number -> heading map for the four documents")
    ap.add_argument("--dangling", action="store_true",
                    help="every section number cited that has no heading")
    ap.add_argument("--ambiguous", action="store_true",
                    help="numbers that map to more than one heading")
    ap.add_argument("--code", action="store_true",
                    help="named citations in .py/.rb/.txt/.java resolve")
    ap.add_argument("--check", action="store_true", help="(default)")
    args = ap.parse_args(argv[1:])

    secs = {k: sections_of(doc_path(k)) for k in list(DOCS) + list(APP)}

    if args.map:
        for key in DOCS:
            print("== %s  (%s)" % (key, DOCS[key]))
            for sid in sorted(secs[key], key=_sortkey):
                for text, line, anch in secs[key][sid]:
                    print("  %-10s %-72s %s"
                          % (sid, text[:72], ("#" + anch) if anch else
                             "(list item, no anchor)"))
            print()
        return 0

    if args.ambiguous:
        bad = 0
        for key in DOCS:
            for sid, v in sorted(secs[key].items(), key=lambda kv: _sortkey(kv[0])):
                if len(v) > 1:
                    bad += 1
                    print("%-20s §%-10s -> %s" % (key, sid, " | ".join(
                        "%r@%d" % (t[:46], ln) for t, ln, _ in v)))
        print("\n%d ambiguous number(s)" % bad)
        return 0 if not bad else 1

    if args.dangling:
        dang = collections.defaultdict(lambda: collections.defaultdict(list))
        total = 0
        for rel in files((".py", ".rb", ".md", ".txt")):
            own = owner_of(rel)
            body = open(os.path.join(TREE, rel), errors="replace").read()
            for m in _CITE.finditer(body):
                name, sid = m.group(1), m.group(2)
                if name:
                    name = _ALIASES.get(name.lower(), name)
                key = name or (own[1] if own else None)
                if key is None or key not in secs:
                    continue
                total += 1
                if sid not in secs[key]:
                    dang[key][sid].append(
                        "%s:%d" % (rel, body.count("\n", 0, m.start()) + 1))
        n = 0
        for key in sorted(dang):
            print("== %s" % key)
            for sid in sorted(dang[key], key=_sortkey):
                sites = dang[key][sid]
                n += len(sites)
                elsewhere = [(k, secs[k][sid][0][0]) for k in secs
                             if k != key and sid in secs[k]]
                print("  §%-10s x%-5d %s" % (sid, len(sites), sites[0]))
                for k, t in elsewhere:
                    print("        the number exists in %-20s %r" % (k, t[:58]))
                if not elsewhere:
                    print("        NOWHERE: no document in the project "
                          "declares this number")
            print()
        print("%d of %d numbered citations resolve to no heading" % (n, total))
        return 0 if not n else 1

    if args.code:
        checked, ok, bad, _backlog = check_code(secs)
        counts, broken, num_bad, num_str = check_code_links()
        print("CODE CITATIONS, AS LINKS")
        print("  path.md#anchor links checked : %d" % counts["links"])
        print("  resolved                     : %d" % counts["links_ok"])
        print("  markdown files named         : %d" % counts["files"])
        print("  which exist                  : %d" % counts["files_ok"])
        print("  broken                       : %d" % len(broken))
        for rel, line, what, why in broken:
            print("    %s:%d  %s  -- %s" % (rel, line, what, why))
        print()
        print("CODE CITATIONS, NAMED PROSE FORM (the two path-free cases)")
        print("  in a comment or docstring    : %d" % checked)
        print("  resolved                     : %d" % ok)
        print("  unresolved                   : %d" % len(bad))
        print("  inside a string (left alone) : %d"
              % _backlog.get("(named, inside a string)", 0))
        for rel, line, key, quoted, why in bad:
            print("    %s:%d  (%s, %r)  -- %s"
                  % (rel, line, key, quoted[:48], why))
        print()
        print("THE NUMBERED FORM, WHICH IS NOW AN ERROR")
        print("  in a comment or docstring    : %d  (must be 0)"
              % counts["numbered_bad"])
        for rel, line, what, why in num_bad:
            print("    %s:%d  %s  -- %s" % (rel, line, what, why))
        over = counts["numbered_kept"] - _KEPT_NUMBERED_SITES
        print("  deliberately kept            : %d  (allowed %d)"
              % (counts["numbered_kept"], _KEPT_NUMBERED_SITES))
        if over > 0:
            print("    %d MORE SITE(S) than the allow-list accounts for: the "
                  "list is keyed on (file, section), so a new citation at an "
                  "already-excused pair is otherwise invisible" % over)
        for (rel, sid), why in sorted(_KEPT_NUMBERED.items()):
            print("    %s  §%s  -- %s" % (rel, sid, why))
        print("  inside a non-docstring string: %d  (left by design)"
              % counts["numbered_in_string"])
        by = collections.Counter(r.split("/")[0] for r, _l, _w, _y in num_str)
        for mod in sorted(by):
            print("    %-24s %d" % (mod, by[mod]))
        print()
        failures = (len(broken) + len(bad) + counts["numbered_bad"]
                    + max(0, over))
        print("verdict: %s" % (
            "every code citation resolves as a link, and no numbered "
            "citation survives" if not failures
            else "%d CODE CITATION FAILURE(S)" % failures))
        return 0 if not failures else 1

    checked, ok, broken = check_links()
    numbered = numbered_in_markdown()
    print("markdown links checked : %d" % checked)
    print("resolved               : %d" % ok)
    print("broken                 : %d" % len(broken))
    if broken:
        print()
        for rel, line, text, href, why in broken:
            print("  %s:%d  [%s](%s)  -- %s"
                  % (rel, line, text[:40], href, why))
    print()
    print("numbered citations left in markdown prose : %d  (must be 0)"
          % len(numbered))
    for rel, line, what in numbered:
        print("  %s:%d  %s" % (rel, line, what))
    print()
    failures = len(broken) + len(numbered)
    print("verdict: %s" % (
        "every markdown link resolves, and no numbered citation survives"
        if not failures else "%d MARKDOWN CITATION FAILURE(S)" % failures))
    return 0 if not failures else 1


def _sortkey(sid):
    return [int(x) if x.isdigit() else x
            for x in re.split(r"(\d+)", sid) if x]


if __name__ == "__main__":
    sys.exit(main(sys.argv))
