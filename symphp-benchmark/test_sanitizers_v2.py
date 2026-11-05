"""P3/P7 (v2 engine): the Python twins sinks_v2 applies (sinks_v2.SANITIZERS) against the PHP the
sanitizer shims run (sanitizers_v2.php's v2_sanitize, on php:8.2), on random strings; v2_sanitize
against PHP's own builtins wherever PHP can be called without a connection; and the twins against
php:7.4-cli's builtins -- the PHP the apps and the judge run -- including htmlspecialchars/htmlentities
with NO flags, whose default is 7.4's ENT_COMPAT (`'` not escaped), not 8.1's ENT_QUOTES.

usage: build/venv/bin/python -m pytest -q test_sanitizers_v2.py      (needs docker, php:8.2-cli)

test_sanitizers.py is the v1 counterpart (Concolic\\Sanitized::apply, which the v2 engine does not have).
"""

from __future__ import annotations

import json
import os
import random
import subprocess

import engine
import pytest

pytestmark = pytest.mark.skipif(not engine.V2, reason="needs the v2 engine (php-runtime/real-apps-v2)")
if engine.V2:
    import sinks_v2

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
        // 8.2's builtin with no flags is 8.1's default; the shim deliberately applies 7.4's instead.
        $builtin = $fn === 'mysqli_real_escape_string' || (str_starts_with($fn, 'html') && !$args) ? $shim : $fn($s, ...$args);
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
            twin = sinks_v2.SANITIZERS[fn](s, *args)
            if twin != shim:
                bad_twin.append((fn, args, s, shim, twin))
    assert not bad_shim, bad_shim[:5]
    assert not bad_twin, bad_twin[:5]


PHP74 = r"""
$in = json_decode(stream_get_contents(STDIN), true);
$out = [];
foreach ($in['cases'] as [$fn, $args]) {
    foreach ($in['strings'] as $s) {
        $out[] = $fn === 'mysqli_real_escape_string' || (strpos($fn, 'escapeshell') === 0 && strpos($s, "\0") !== false)
            ? null : $fn($s, ...$args);
    }
}
echo json_encode($out);
"""


def test_python_twins_match_php74_builtins_including_the_no_flags_html_default():
    strings = _strings()
    cases = CASES + [("htmlentities", [])]
    p = subprocess.run(["docker", "run", "--rm", "-i", "--log-opt", "max-size=20m", "php:7.4-cli", "php", "-r", PHP74],
                       input=json.dumps({"cases": cases, "strings": strings}), capture_output=True, text=True, check=True)
    php = iter(json.loads(p.stdout))
    bad, compared = [], 0
    for fn, args in cases:
        for s in strings:
            want = next(php)
            if want is None:
                continue
            compared += 1
            got = sinks_v2.SANITIZERS[fn](s, *args)
            if got != want:
                bad.append((fn, args, s, want, got))
    assert compared > 3000 and not bad, bad[:5]
    assert sinks_v2.SANITIZERS["htmlspecialchars"]("'<") == "'&lt;"       # 7.4: the quote survives
