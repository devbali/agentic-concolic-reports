"""H4/E5: the Python sanitizer twins in sinks.py against PHP itself, on random strings.

usage: build/venv/bin/python -m pytest -q test_sanitizers.py      (needs docker, php:8.2-cli)
"""

from __future__ import annotations

import json
import os
import random
import subprocess

import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "agentic_concolic_engine"))
import sinks  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ALPHABET = "abcXYZ019 '\"\\\0\n\r\t\x0b\x1a<>&;|$`#*?~^()[]{},=%_-./"
CASES = [
    ("addslashes", []), ("mysqli_real_escape_string", []), ("htmlspecialchars", []),
    ("htmlspecialchars", [3]), ("htmlspecialchars", [0]), ("htmlspecialchars", [3, "UTF-8", False]),
    ("htmlentities", [3]), ("escapeshellarg", []), ("escapeshellcmd", []), ("trim", []),
    ("strtolower", []), ("strtoupper", []),
]
PHP = r"""
$in = json_decode(stream_get_contents(STDIN), true);
require getenv('RT') . '/src/autoload.php';
$out = [];
foreach ($in['cases'] as [$fn, $args]) {
    foreach ($in['strings'] as $s) {
        // PHP 8's escapeshell* throw on a NUL byte (ValueError); not a case the oracle builds.
        $out[] = str_starts_with($fn, 'escapeshell') && str_contains($s, "\0") ? null : Concolic\Sanitized::apply($fn, $s, $args);
    }
}
echo json_encode($out);
"""


def test_python_sanitizers_match_php():
    rng = random.Random(20261029)
    strings = ["", "'", '"', "\\", "a'b\"c\\d", "  x  ", "\0\n"] + [
        "".join(rng.choice(ALPHABET) for _ in range(rng.randint(1, 24))) for _ in range(300)]
    root = os.path.dirname(os.path.dirname(HERE))
    rt = os.path.join(root, "agentic_concolic_engine", "runtimes", "php_runtime")
    p = subprocess.run(["docker", "run", "--rm", "-i", "--log-opt", "max-size=20m", "-e", f"RT={rt}",
                        "-v", f"{root}:{root}", "php:8.2-cli", "php", "-r", PHP],
                       input=json.dumps({"cases": CASES, "strings": strings}), capture_output=True, text=True, check=True)
    php = iter(json.loads(p.stdout))
    bad = []
    for fn, args in CASES:
        for s in strings:
            want = next(php)
            if want is None:
                continue
            got = sinks.SANITIZERS[fn](s, *args)
            if got != want:
                bad.append((fn, args, s, want, got))
    assert not bad, bad[:5]


def test_apply_chain_and_instantiate_with_apply_refs():
    refs = {"p0": {"name": "x", "apply": [["addslashes", []], ["strtoupper", []]]}, "p1": "y"}
    text = sinks._instantiate("a='$$(p0)' b=$$(p1)", refs, {"x": "o'k", "y": "1 1"})
    assert text == "a='O\\'K' b=1 1"
    # The quoted, escaped use parses; the numeric one does not.
    assert sinks.parses(sinks.SQL, "SELECT * FROM t WHERE " + text.split(" b=")[0])
    assert not sinks.parses(sinks.SQL, "SELECT * FROM t WHERE b=1 1")
