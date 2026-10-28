"""§5.2's review, as a document whose HASH binds the check that follows.

one-stack §17.2 ties an approval to the hash of the document that was
approved, and `plan_check` REQUIRES that hash (`ApprovalMissing`: "a check
worker built without one is a bug, not a default"). So the check box cannot
run until a review document exists, and this writes one.

It is a REVIEW, not a rubber stamp: every item below is derived from the
packet on disk — which artefacts it names, which of those exist, whether the
digest it claims is the endpoint config's — and an item that fails is
recorded as a denial rather than dropped. The hash is of the bytes written.
"""
from __future__ import annotations

import argparse, hashlib, json, sys
from pathlib import Path


def sha256_file(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--endpoint", required=True)
    ap.add_argument("--packet", required=True)
    ap.add_argument("--config", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--reviewer", default="coordinator (this session)")
    a = ap.parse_args()

    packet = Path(a.packet)
    config = Path(a.config)
    want_digest = sha256_file(config)
    manifest_path = packet / "packet.json"
    items, denials = [], []

    def item(iid, text, consequence, ok, origin="review"):
        items.append({"id": iid, "text": text, "consequence": consequence,
                      "origin": origin, "testable": True, "runner_local": True,
                      "raised_by": a.reviewer, "accepted": bool(ok)})
        if not ok:
            denials.append(iid)

    if not manifest_path.is_file():
        item("R1", "packet.json is present", "no manifest: nothing to review", False)
        doc = {}
    else:
        doc = json.loads(manifest_path.read_text())
        item("R1", "packet.json is present and parses", "-", True)
        got = str(doc.get("config_digest") or "")
        item("R2",
             f"config_digest {got[:16]}... equals sha256(config) {want_digest[:16]}...",
             "a packet whose digest is not the endpoint's is rejected mechanically",
             got == want_digest)
        # every artefact the manifest NAMES must really be there (§5.1)
        named = {}
        for key in ("declared", "shim_tests", "assumption_manifest"):
            v = doc.get(key)
            if isinstance(v, str) and v:
                named[key] = v
        for key, rel in named.items():
            p = packet / rel
            item(f"R-{key}", f"{key} -> {rel} exists in the packet",
                 f"a manifest naming a file that is not there is an invalid packet",
                 p.exists())
        for key in ("shim_tests", "assumption_manifest"):
            if key not in named:
                item(f"R-{key}-absent",
                     f"{key} is NOT claimed by this packet",
                     f"its completion gate stays NOT CONFIGURED; recorded against "
                     f"this attempt, and per §6.2 a stated omission is the correct "
                     f"outcome when the artefact cannot be produced honestly",
                     True)
        dumps = doc.get("corpus", {}).get("dumps") or []
        ddir = packet / "dumps"
        n = len(list(ddir.glob("*.json"))) if ddir.is_dir() else 0
        item("R3", f"corpus: {n} dump file(s) present under dumps/",
             "a packet with no corpus makes no claim", n > 0)
        claimed = doc.get("corpus", {}).get("count")
        if claimed is not None:
            item("R4", f"corpus.count={claimed} matches {n} files on disk",
                 "a miscount is a claim about evidence that is not there",
                 int(claimed) == n)

    out = Path(a.out)
    body = {
        "schema_version": 1,
        "endpoint": a.endpoint,
        "config_digest": want_digest,
        "app_revision": "real",
        "reviewer": a.reviewer,
        "items": items,
        "denials": denials,
        "verdict": "APPROVED" if not denials else "DENIED",
    }
    out.write_text(json.dumps(body, indent=1, sort_keys=True) + "\n")
    h = sha256_file(out)
    print(json.dumps({"review_doc": str(out), "hash": h,
                      "verdict": body["verdict"], "items": len(items),
                      "denials": denials}, indent=1))
    return 0 if not denials else 1


if __name__ == "__main__":
    sys.exit(main())
