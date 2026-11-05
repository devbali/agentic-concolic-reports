<?php

/**
 * P3: sanitizers as SHIM targets (v2 engine), for harness_v2.php and
 * harness_app_v2.php under the request flag `sanitizers`; the copy must be
 * instrumented with instrument_app_v2.php --sanitizers so the calls reach
 * __target.
 *
 * On a symbolic subject a sanitizer's result is a FRESH symbol
 * (SYM_RESULT_<fn>_<n>) whose value is this run's real result. The
 * `symbolic_call` event records the arguments as terms (the subject's whole
 * term, the others as literals), and the note says which is which:
 *
 *     {"sanitizer": "<fn>", "subject": "<arg key>", "args": [<the arguments after the subject, concrete>]}
 *
 * sinks_v2.py applies the Python twin of <fn> (sinks.SANITIZERS, checked
 * against this file by test_sanitizers_v2.py) to each candidate input, and
 * engine.py lists every branch on such a result as an untracked assumption.
 * On concrete arguments the call is ordinary PHP (Runtime::$symbolicArgumentsOnly).
 *
 * No new IR operator, no Template part: the old branch's Concolic\Sanitized
 * is not ported.
 */

use Concolic\Runtime;
use Concolic\Value;

/** Each sanitizer and the 0-based position of its SUBJECT argument. */
const SANITIZER_SHIMS = [
    'addslashes' => 0, 'mysqli_real_escape_string' => 1, 'htmlspecialchars' => 0, 'htmlentities' => 0,
    'escapeshellarg' => 0, 'escapeshellcmd' => 0, 'trim' => 0, 'strtolower' => 0, 'strtoupper' => 0,
];

/** This run's value of an argument: a symbolic value's concrete text, anything else as it is. */
function v2_plain(mixed $v): mixed
{
    if ($v instanceof Value) {
        return $v->fields === null && !str_starts_with($v->type, '[') ? $v->concrete() : null;
    }
    return is_array($v) ? array_map('v2_plain', $v) : $v;
}

/**
 * What the sanitizer returns for `$subject`. The PHP functions themselves,
 * except mysqli_real_escape_string, which needs a live connection to be called:
 * for every charset the benchmark apps use it escapes exactly \0 \n \r \ ' " ^Z.
 */
function v2_sanitize(string $fn, mixed $subject, array $rest): string
{
    $s = (string) $subject;
    return match ($fn) {
        'mysqli_real_escape_string' => strtr($s, ["\0" => '\\0', "\n" => '\\n', "\r" => '\\r', '\\' => '\\\\',
            "'" => "\\'", '"' => '\\"', "\x1a" => '\\Z']),
        'escapeshellarg', 'escapeshellcmd', 'strtolower', 'strtoupper', 'addslashes' => $fn($s),
        // No flags given: PHP 7.4's default, ENT_COMPAT | ENT_HTML401 (`'` is NOT escaped), because the
        // benchmark apps and the judge run 7.4; PHP 8.1 changed it to ENT_QUOTES | ENT_SUBSTITUTE.
        'htmlspecialchars', 'htmlentities' => $fn($s, ...($rest ?: [ENT_COMPAT | ENT_HTML401])),
        default => $fn($s, ...$rest),
    };
}

/**
 * Register the sanitizer shims on `$rt` (P3). The supplier publishes the note
 * sinks_v2.py applies the Python twin from:
 *     {"sanitizer": fn, "subject": "<arg key>", "args": [the other arguments, concrete]}
 */
function v2_register_sanitizers(Runtime $rt): void
{
    foreach (SANITIZER_SHIMS as $fn => $pos) {
        $rt->symbolicArgumentsOnly[$fn] = true;
        $rt->target($fn, 'shim', 'str', function (array $args, string $result) use ($rt, $fn, $pos) {
            $keys = array_keys($args);
            $values = array_values($args);
            $rest = array_map('v2_plain', array_slice($values, $pos + 1));
            $rt->publishNote(json_encode(['sanitizer' => $fn, 'subject' => (string) ($keys[$pos] ?? ''), 'args' => $rest],
                JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES));
            return v2_sanitize($fn, v2_plain($values[$pos] ?? null), $rest);
        });
    }
}

