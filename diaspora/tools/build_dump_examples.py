"""Rebuild one endpoint's `dump_examples/` tree from its dumps.

    build_dump_examples.py SRC_DIR DEST_DIR

For every `dump_*.json` directly in SRC_DIR:

  * copy it to DEST_DIR under the same name, and
  * write `<name without .json>.run.txt` beside it — the §10.3 text form,
    `print_run(to_text_domain(Run.from_dict(d)))` — each one CHECKED with
    `parse_run(print_run(to_text_domain(r))) == to_text_domain(r)` before it
    is written, so a file that round-trips is the only kind that lands.

`README.md` and any other hand-written file already in DEST_DIR is left
alone: the prose describes what each dump illustrates and is not derivable
from the dump. Subdirectories are not walked — run the tool once per
directory (`.` and `./write_path` are separate corpora that both number from
`dse0001`, which is why `write_path/` is a subdirectory of the examples tree
in the first place).

WHY THIS EXISTS. The trees were rebuilt by hand each time the corpus was
regenerated, which is how a `.run.txt` can come to describe a dump that no
longer exists. Written 2026-09-25 while regenerating `results4` after the
runtimes stopped recording memory addresses.
"""
import glob
import json
import os
import shutil
import sys

sys.path.insert(0, "/home/dev/project/src_new")

from concolic.model.run import Run
from concolic.model.syntax import parse_run, print_run, to_text_domain


def _txt(name: str) -> str:
    """`dump_x.json` -> `dump_x.run.txt`, the name the trees already use."""
    return (name[:-len(".json")] if name.endswith(".json") else name) + ".run.txt"


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    src, dest = sys.argv[1], sys.argv[2]
    os.makedirs(dest, exist_ok=True)

    names = sorted(os.path.basename(p)
                   for p in glob.glob(os.path.join(src, "dump_*.json")))
    if not names:
        print(f"no dump_*.json in {src}")
        return 1

    # Anything this tool GENERATED for a dump that is gone must go too;
    # anything a person wrote stays. Only the two generated shapes are
    # considered, and only for names the source no longer has.
    keep = set(names) | {_txt(n) for n in names}
    for stale in sorted(os.listdir(dest)):
        if stale in keep or not stale.startswith("dump_"):
            continue
        if stale.endswith(".json") or stale.endswith(".run.txt"):
            os.remove(os.path.join(dest, stale))
            print(f"  removed stale {stale}")

    for name in names:
        shutil.copyfile(os.path.join(src, name), os.path.join(dest, name))
        with open(os.path.join(src, name)) as fh:
            run = Run.from_dict(json.load(fh))
        mapped = to_text_domain(run)
        text = print_run(mapped)
        back = parse_run(text)
        if back != mapped:
            print(f"  ROUND TRIP FAILED for {name} -- not written")
            return 1
        with open(os.path.join(dest, _txt(name)), "w") as fh:
            fh.write(text if text.endswith("\n") else text + "\n")
        print(f"  {name} + {_txt(name)}")
    print(f"{len(names)} dumps -> {dest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
