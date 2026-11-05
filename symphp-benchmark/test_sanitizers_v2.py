"""P3 (v2 engine): the Python twins sinks_v2 applies (sinks.SANITIZERS) against the PHP the
sanitizer shims run (sanitizers_v2.php's v2_sanitize), on random strings; and v2_sanitize
against PHP's own builtins wherever PHP can be called without a connection.

usage: build/venv/bin/python -m pytest -q test_sanitizers_v2.py      (needs docker, php:8.2-cli)

test_sanitizers.py is the v1 counterpart (Concolic\\Sanitized::apply, which the v2 engine does not have).
"""

from __future__ import annotations

import json
import os
import random
import subprocess

import sinks

HERE = os.path.dirname(os.path.abspath(__file__))
ALPHABET = "abcXYZ019 '\"\\\0\n\r\t\x0b\x1a<>&;|$`#*?~^()[]{},=%_-./"
CASES = [
    ("addslashes", []), ("mysqli_real_escape_string", []), ("htmlspecialchars", []),
    ("htmlspecialchars", [3]), ("htmlspecialchars", [0]), ("htmlspecialchars", [3, "UTF-8", False]),
    ("htmlentities", [3]), ("escapeshellarg", []), ("escapeshellcmd", []), ("trim", []), ("trim", [" x"]),
    ("strtolower", []), ("strtoupper", []),
]
PHP = r"""
require getenv('HARNESS') . '/sanitizers_v2.php';
$in = json_decode(stream_get_contents(STDIN), true);
$out = [];
foreach ($in['cases'] as [$fn, $args]) {
    foreach ($in['strings'] as $s) {
        // PHP 8's escapeshell* throw on a NUL byte (ValueError); not a case the oracle builds.
        if (str_starts_with($fn, 'escapeshell') && str_contains($s, "\0")) {
            $out[] = null;
            continue;
        }
        $shim = v2_sanitize($fn, $s, $args);
        $builtin = $fn === 'mysqli_real_escape_string' ? $shim : $fn($s, ...$args);
        $out[] = [$shim, $builtin];
    }
}
echo json_encode($out);
"""


def _strings():
    rng = random.Random(20261105)
    return ["", "'", '"', "\\", "a'b\"c\\d", "  x  ", "\0\n", "&amp;", "&#039;"] + [
        "".join(rng.choice(ALPHABET) for _ in range(rng.randint(1, 24))) for _ in range(300)]


def test_python_twins_match_the_shims_php():
    strings = _strings()
    p = subprocess.run(["docker", "run", "--rm", "-i", "--log-opt", "max-size=20m", "-e", f"HARNESS={HERE}",
                        "-v", f"{HERE}:{HERE}:ro", "php:8.2-cli", "php", "-r", PHP],
                       input=json.dumps({"cases": CASES, "strings": strings}), capture_output=True, text=True,
                       check=True)
    php = iter(json.loads(p.stdout))
    bad_twin, bad_shim = [], []
    for fn, args in CASES:
        for s in strings:
            got = next(php)
            if got is None:
                continue
            shim, builtin = got
            if shim != builtin:
                bad_shim.append((fn, args, s, shim, builtin))
            twin = sinks.SANITIZERS[fn](s, *args)
            if twin != shim:
                bad_twin.append((fn, args, s, shim, twin))
    assert not bad_shim, bad_shim[:5]
    assert not bad_twin, bad_twin[:5]
