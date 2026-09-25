"""Build the policy IR text for one endpoint's dump corpus.

    Run.from_dict -> build_policy -> normalize_detailed -> print_policy

Usage:

    build_policy_example.py [--header FILE] ENTRYPOINT OUT_PATH DIR [DIR …]

ONE policy over the whole corpus. `build_policy_example_grouped.py` exists
only for a corpus `build_policy` still refuses to merge; as of the 2026-09-24
fix to `dumps_to_policy/build.py` (run-local scoping of positional `cN`
observation keys) `aspect_memberships_create` is not such a corpus and uses
this driver.

Two LOCAL workarounds, both cosmetic printer gaps documented in
results4/comments_index/POLICY_EXAMPLE.md and NOT fixed here (nothing under
dumps_to_policy/ is modified):

  (1) print_policy cannot print a certificate-free policy: `certificate` is
      optional on build_policy, but the printer falls back to a default
      Certificate() with atoms=0 and then fails its own check_atoms. A blank
      Certificate(app=...) is attached, .with_atoms(n) after normalization.
      Its default outcome=UNDECIDED says in the text itself that this is a
      description of what was seen, not a certified policy.
  (2) `_QNAME` admits Ruby's ?/! suffixes but not `=`, so a setter target
      such as ActionController::Metal#status= is rejected. The module
      attribute is widened AT RUNTIME, in this driver only.
"""
import sys, glob, json, os, re

sys.path.insert(0, "/home/dev/project/src_new")

from concolic.model.run import Run
from dumps_to_policy.build import build_policy
from dumps_to_policy.normalize import normalize_detailed
from dumps_to_policy.certificate import Certificate
from dumps_to_policy.syntax import policy_text

# (2) local qname widening — never written back to the file.
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

def collect(dirs):
    files = []
    for d in dirs:
        files.extend(sorted(glob.glob(os.path.join(d, "dump_*.json"))))
    return files

def main():
    argv = sys.argv[1:]
    # Optional `--header <path>`: a prose preamble prepended to the printed
    # policy. Used by aspect_memberships_create, whose corpus spans two dump
    # directories and wants that said in the file itself.
    header = None
    if "--header" in argv:
        i = argv.index("--header")
        header = open(argv[i + 1]).read().rstrip("\n")
        del argv[i:i + 2]
    entrypoint = argv[0]
    out_path = argv[1]
    dirs = argv[2:]
    files = collect(dirs)
    runs, failed = [], []
    for f in files:
        runs.append((f, Run.from_dict(json.load(open(f)))))

    # Per-dump build first, so a refusal is attributed to ITS dump.
    for f, r in runs:
        try:
            build_policy([r], entrypoint=entrypoint)
        except Exception as e:
            failed.append((os.path.basename(f), type(e).__name__, str(e)))

    cert = Certificate(app=f"results4/{entrypoint}")
    policy = build_policy([r for _, r in runs], entrypoint=entrypoint,
                          certificate=cert)
    raw_atoms = len(policy.atoms)
    normed, report = normalize_detailed(policy)
    import dataclasses
    # Keep the certificate build_policy produced (it carries §9's
    # inferred/declared counts); only the atom count has to be re-stated
    # after normalization, or print_policy's own check_atoms fails.
    base = normed.certificate or policy.certificate or cert
    normed = dataclasses.replace(
        normed, certificate=base.with_atoms(len(normed.atoms))
                                .with_minimal(report.minimal))
    text = policy_text.print_policy(normed)

    if header is not None:
        text = header + "\n\n" + text
    with open(out_path, "w") as fh:
        fh.write(text if text.endswith("\n") else text + "\n")

    print(f"dumps            : {len(files)}")
    print(f"built per-dump   : {len(files) - len(failed)} ok, {len(failed)} refused")
    for b in failed:
        print("   REFUSED", b[0], b[1], b[2].replace("\n", " ")[:200])
    print(f"atoms (unmerged) : {raw_atoms}")
    print(f"atoms (normalized): {len(normed.atoms)}")
    print(f"signatures       : {len(normed.signatures)}")
    print(f"minimal          : {report.minimal}  solver_used={report.solver_used}")
    print(f"written          : {out_path}  ({len(text.splitlines())} lines)")

main()
