"""Policy IR text for a corpus that cannot be merged into ONE policy.

SUPERSEDED FOR `aspect_memberships_create` (2026-09-24). The reason that
corpus needed splitting was a defect in `dumps_to_policy/build.py` -- the
corpus-wide §5.4 type table keyed call-result observations by the POSITIONAL
`cN` identity, which is run-local -- and it is fixed. That endpoint now uses
`build_policy_example.py --header …`. This driver is kept only for a corpus
`build_policy` genuinely refuses; see
`results4/aspect_memberships_create/POLICY_EXAMPLE.md`.

Same pipeline as make_policy.py (Run.from_dict -> build_policy ->
normalize_detailed -> print_policy) with the same two local printer
workarounds, but the corpus is first split into the MAXIMAL groups of dumps
that `build_policy` accepts together. See the header this writes for why the
split is necessary.
"""
import sys, glob, json, os, re, dataclasses

sys.path.insert(0, "/home/dev/project/src_new")
from concolic.model.run import Run
from dumps_to_policy.build import build_policy
from dumps_to_policy.normalize import normalize_detailed
from dumps_to_policy.certificate import Certificate
from dumps_to_policy.syntax import policy_text

policy_text._QNAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*[?!=]?"
                                r"((\.|#|::)[A-Za-z_][A-Za-z0-9_]*[?!=]?)*")

# (3) `print_term` has no §10.2 spelling for a LIST literal, so a mock that
#     recorded an Array argument (here a one-element Arel bind list) makes the
#     printer raise. Spelled locally as `[a, b, c]`, in this driver only —
#     a third cosmetic printer gap, reported and not fixed under
#     dumps_to_policy/.
from dumps_to_policy.predicate import Lit as _Lit
_orig_print_term = policy_text.print_term


def _print_term(term):
    if isinstance(term, _Lit) and isinstance(term.value, (tuple, list)):
        return "[" + ", ".join(_print_term(_Lit(v)) for v in term.value) + "]"
    return _orig_print_term(term)


policy_text.print_term = _print_term

entrypoint, out_path, header_path = sys.argv[1], sys.argv[2], sys.argv[3]
root = sys.argv[4]
dirs = sys.argv[4:]
files = []
for d in dirs:
    files.extend(sorted(glob.glob(os.path.join(d, "dump_*.json"))))
runs = [(f, Run.from_dict(json.load(open(f)))) for f in files]

refused = []
for f, r in runs:
    try:
        build_policy([r], entrypoint=entrypoint)
    except Exception as e:
        refused.append((os.path.basename(f), type(e).__name__, str(e)))

groups, cur = [], []
for f, r in runs:
    trial = cur + [(f, r)]
    try:
        build_policy([x[1] for x in trial], entrypoint=entrypoint)
        cur = trial
    except Exception:
        if cur:
            groups.append(cur)
        cur = [(f, r)]
if cur:
    groups.append(cur)

out = [open(header_path).read().rstrip("\n"), ""]
total_atoms = 0
for i, g in enumerate(groups, 1):
    cert = Certificate(app=f"results4/{entrypoint}")
    pol = build_policy([x[1] for x in g], entrypoint=entrypoint,
                       certificate=cert)
    normed, report = normalize_detailed(pol)
    # Keep the certificate build_policy produced (it carries §9's
    # inferred/declared counts); only the atom count has to be re-stated
    # after normalization, or print_policy's own check_atoms fails.
    base = normed.certificate or pol.certificate or cert
    normed = dataclasses.replace(
        normed, certificate=base.with_atoms(len(normed.atoms))
                                .with_minimal(report.minimal))
    names = ", ".join(os.path.relpath(x[0], root) for x in g)
    out.append("#" * 72)
    out.append(f"# GROUP {i} of {len(groups)} — {names}")
    out.append("#" * 72)
    out.append("")
    out.append(policy_text.print_policy(normed).rstrip("\n"))
    out.append("")
    total_atoms += len(normed.atoms)

open(out_path, "w").write("\n".join(out) + "\n")
print(f"dumps          : {len(files)}")
print(f"built per-dump : {len(files)-len(refused)} ok, {len(refused)} refused")
for b in refused:
    print("   REFUSED", b[0], b[1], b[2].replace("\n", " ")[:180])
print(f"groups         : {len(groups)}")
print(f"atoms total    : {total_atoms}")
print(f"written        : {out_path}")
