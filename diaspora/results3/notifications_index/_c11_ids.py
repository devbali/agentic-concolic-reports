"""Emit the identity digests of the cert3 declaration set, so the gate-reuse
wrapper can tell an UNCHANGED declaration (its class was tested by the
2026-09-11 class gate) from a NEW one (must be tested for real)."""
import hashlib, json, os

B = os.path.dirname(os.path.abspath(__file__))


def _stream(path):
    f = open(path, encoding="utf-8")
    while f.read(1) != "[":
        pass
    depth, in_str, esc, buf = 0, False, False, []
    while True:
        chunk = f.read(1 << 20)
        if not chunk:
            return
        start = 0
        for n, c in enumerate(chunk):
            if in_str:
                if esc:
                    esc = False
                elif c == "\\":
                    esc = True
                elif c == '"':
                    in_str = False
                continue
            if c == '"':
                in_str = True
            elif c in "[{":
                if depth == 0:
                    start = n
                depth += 1
            elif c in "]}":
                depth -= 1
                if depth == 0:
                    buf.append(chunk[start:n + 1])
                    yield json.loads("".join(buf))
                    buf = []
                    start = n + 1
        if depth:
            buf.append(chunk[start:])


def decl_id(a):
    return hashlib.sha1(json.dumps(
        [a.get("type"), a.get("expr"), a.get("expr_a"), a.get("expr_b"),
         a.get("description"), a.get("result_pattern"), a.get("tracked_side")],
        sort_keys=True).encode()).hexdigest()


if __name__ == "__main__":
    ids = sorted({decl_id(a) for a in _stream(os.path.join(B, "_assumptions_declared_cert3.json"))})
    json.dump(ids, open(os.path.join(B, "_c11_ids_cert3.json"), "w"))
    print(f"[ids] {len(ids)} distinct declaration identities from the cert3 pass")
