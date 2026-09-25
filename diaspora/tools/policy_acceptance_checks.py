"""The three acceptance checks a rebuilt `policy_example.txt` must pass.

    policy_acceptance_checks.py POLICY.txt [POLICY.txt …]

They were run by hand the first time (`results4/aspect_memberships_create/
REPORT.md` §7.3: "no undefined name (0), no `opaque` in the IR (0 — two
occurrences remain in the header's historical prose), no id column compared
to a non-bind (0, was 97 lines)"). Three hand-run greps are three numbers
nobody can reproduce, so this file is what they were, written down.

WHAT IS AND IS NOT THE IR. Everything from the first `entry` or `sig` line
onward is the printed policy; everything before it is the `--header`
preamble, which is PROSE and is allowed to discuss `opaque` and to quote old
defects. Check 2 is exactly the check that went looking in the prose the
first time and had to be reported with a parenthesis; here the boundary is
drawn in code and the parenthesis is unnecessary.

THE CHECKS

1. NO UNDEFINED NAME. Every `cN` an atom reads is bound by an earlier line
   of the SAME atom, and every `$NAME` is an entrypoint symbol. An atom that
   reads a name nothing defines is §10.2 rule 1's failure -- a trace whose
   own references do not resolve -- and it is the check that catches a
   builder that merged two runs' positional `cN` identities.

2. NO `opaque` IN THE IR. `opaque` is a DECLARATION (§5.0, revised
   2026-09-25): "I examined this value and it has no §5 structure". Nothing
   in either runtime mints one any more, so one in a printed policy means an
   inference path invented it.

3. NO ID COLUMN COMPARED TO A NON-BIND. In a rendered note, `"t"."id" = '5'`
   means the value reached SQL as a LITERAL: the producer relation was lost
   somewhere between the mock and the note, and the policy states a constant
   where it should state a reference (REPORT.md D6). A bind is `$$(…)`.

Each check prints its count and the first few offending lines. Exit 0 only
when all three are zero on every file.
"""
import re
import sys

#: The first line of the IR proper. `--header` prose precedes it.
_IR_START = re.compile(r"^(entry|sig|atom|policy)\b")

#: `c12`, and `c12.field` — a call variable, §10.2's positional identity.
_CVAR = re.compile(r"\bc(\d+)\b")

#: A binding line: `c7 = …` or `access c7 = …`.
_BIND = re.compile(r"^\s*(?:access\s+)?c(\d+)\s*=")

#: An entrypoint / free symbol reference.
_SYM = re.compile(r"\$([A-Za-z_][A-Za-z0-9_]*)")

#: An id column and whatever it is tested against.
#:
#: The comparand is CAPTURED and inspected rather than excluded by a
#: lookahead: `\s*(?!\$\$\()` looks like it rules out a bind and does not,
#: because `\s*` backtracks to zero width and the lookahead then reads the
#: space. That spelling reported 709 hits on a policy with none.
_ID_COLUMN = re.compile(r'"[A-Za-z_][A-Za-z0-9_]*"\."(?:id|[A-Za-z0-9_]+_id)"'
                        r'\s*(?:=|IN)\s*(\S+)')

#: `opaque` as a token of the type language, not inside a word.
_OPAQUE = re.compile(r"(?<![A-Za-z_])opaque(?![A-Za-z_])")


def _ir_lines(text):
    """The printed policy, with the `--header` prose dropped.

    Comment lines inside the IR (`#`) stay: the printer does not emit any,
    so one there came from the header and the split below has already
    removed it -- but if that ever changes, a comment is still not the IR
    and a check that read it would be measuring prose.
    """
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if _IR_START.match(line):
            return [(i + 1, l) for i, l in enumerate(lines[i:], start=i)
                    if not l.lstrip().startswith("#")]
    return []


def check_undefined_names(lines):
    """Every `cN` read is bound earlier in its own atom."""
    bad = []
    bound = set()
    entry_syms = set()
    for no, line in lines:
        if line.startswith(("entry", "sig")):
            entry_syms.update(_SYM.findall(line))
            continue
        if line.startswith("atom"):
            bound = set()
            continue
        m = _BIND.match(line)
        read = set(_CVAR.findall(line))
        if m:
            # The variable being BOUND is not a read of itself.
            read.discard(m.group(1))
        missing = sorted(read - bound, key=int)
        if missing:
            bad.append((no, line.strip(), [f"c{n}" for n in missing]))
        if m:
            bound.add(m.group(1))
    return bad


def check_opaque(lines):
    return [(no, line.strip()) for no, line in lines if _OPAQUE.search(line)]


def check_id_literals(lines):
    """An id column compared to anything but a `$$(…)` bind.

    A literal there means the producer relation was lost between the mock
    and the note, so the policy states a constant where it should state a
    reference (REPORT.md D6).
    """
    bad = []
    for no, line in lines:
        for comparand in _ID_COLUMN.findall(line):
            if not comparand.startswith("$$("):
                bad.append((no, line.strip()))
                break
    return bad


CHECKS = (("no undefined name", check_undefined_names),
          ("no `opaque` in the IR", check_opaque),
          ("no id column compared to a non-bind", check_id_literals))


def main() -> int:
    paths = sys.argv[1:]
    if not paths:
        print(__doc__)
        return 2
    failed = 0
    for path in paths:
        with open(path) as fh:
            lines = _ir_lines(fh.read())
        print(f"{path}  ({len(lines)} IR lines)")
        if not lines:
            print("  NO IR FOUND -- no `entry`/`sig`/`atom`/`policy` line")
            failed += 1
            continue
        for name, fn in CHECKS:
            hits = fn(lines)
            print(f"  {name}: {len(hits)}")
            for hit in hits[:3]:
                print(f"      line {hit[0]}: {hit[1][:150]}")
            if hits:
                failed += 1
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
