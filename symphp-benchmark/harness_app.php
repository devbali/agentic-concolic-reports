<?php

/**
 * One web request of a REAL application, run under the ACE typed runtime (H1).
 *
 *     php harness_app.php --batch  < [request, ...]      -> [result, ...] on stdout
 *     php harness_app.php --one <request.json> <result.json>
 *
 * `--batch` runs every request in its OWN PHP process (`--one`), because a real
 * app defines functions, sets globals and calls `exit`: a second request in the
 * same process would see the first one's state. A request is harness.php's
 * plus
 *
 *     "server":  the CGI variables the judge sends for the same request (-> $_SERVER)
 *     "session": the seeded $_SESSION array (the authenticated arm), or {}
 *     "flags":   {"php7Compare": bool, "concretize": bool}
 *
 * What differs from harness.php (Witcher-Test), and why:
 *
 * - FILE SCOPE. The entry script is included from this file's top level,
 *   between Runtime::begin and finish, so `global $x` and the app's top-level
 *   variables behave as in a real request.
 * - A REAL DATABASE. The process runs in the network namespace of ACE's own
 *   clone server (`ace-<app>-db`, appdb.py), which listens on the port the
 *   app's own config names, so the app's unmodified `mysqli_connect` reaches
 *   the clone -- never the installed database. `mysqli_query`/`real_query`/
 *   `multi_query` are E1 CONCRETE targets: the statement (a Concolic\Template
 *   when it carries an input) is published as the call's note, with `$$(ref)`
 *   for each symbolic part, and then executed for real on this run's text;
 *   the real `mysqli_result` goes back to the app. mysqli error reporting is
 *   OFF, as it is by default on PHP 7.4.
 * - SESSIONS AND HEADERS. `$_SESSION` is a plain array seeded from the
 *   request. `session_*`, `header`, `setcookie` are concrete stand-ins that
 *   record their arguments.
 * - SHELL sinks stay symbolic `target_function`s that run nothing.
 */

define('ACE_HARNESS_LIB', true);
require __DIR__ . '/harness.php';

use Concolic\Runtime;
use Concolic\Template;
use Concolic\Value;

const SESSION_STANDINS = ['session_start', 'session_destroy', 'session_regenerate_id', 'session_unset',
    'session_write_close', 'session_id', 'session_name', 'session_cache_limiter', 'session_set_cookie_params'];
const HEADER_STANDINS = ['header', 'setcookie', 'setrawcookie', 'header_remove', 'http_response_code'];

/** Every name the instrumentor must route through __target for this harness. */
function app_targets(): array
{
    return [...SQL_SINKS, ...SHELL_SINKS, ...SESSION_STANDINS, ...HEADER_STANDINS];
}

function plain(Runtime $rt, mixed $v): mixed
{
    return match (true) {
        $v instanceof Template => $v->text(),
        $v instanceof Value => $v->fields === null && !str_starts_with($v->type, '[') ? $v->concrete() : null,
        is_array($v) => array_map(fn($x) => plain($rt, $x), $v),
        is_object($v) => get_class($v),
        default => $v,
    };
}

if (($argv[1] ?? '') === '--batch') {
    $requests = json_decode(stream_get_contents(STDIN), true, 512, JSON_THROW_ON_ERROR);
    $results = [];
    $tmp = sys_get_temp_dir() . '/ace_harness_' . getmypid();
    @mkdir($tmp);
    foreach ($requests as $i => $request) {
        $in = "{$tmp}/req_{$i}.json";
        $out = "{$tmp}/res_{$i}.json";
        file_put_contents($in, json_encode($request, JSON_UNESCAPED_SLASHES));
        @unlink($out);
        $limit = (int) ($request['timeout'] ?? 120);
        $p = proc_open([PHP_BINARY, '-d', 'memory_limit=2G', '-d', 'display_errors=0', __FILE__, '--one', $in, $out],
            [0 => ['file', '/dev/null', 'r'], 1 => ['file', "{$tmp}/stdout_{$i}", 'w'], 2 => ['file', "{$tmp}/stderr_{$i}", 'w']], $pipes);
        $t0 = microtime(true);
        while (proc_get_status($p)['running']) {
            if (microtime(true) - $t0 > $limit) {
                proc_terminate($p, 9);
                break;
            }
            usleep(20000);
        }
        proc_close($p);
        // Decoded as OBJECTS, so an empty `{}` stays an object on the way back out.
        $res = is_file($out) ? json_decode(file_get_contents($out)) : null;
        if (!$res instanceof stdClass) {
            $res = (object) ['harness_error' => 'no result (' . (microtime(true) - $t0 > $limit ? 'timeout' : 'crashed') . ')',
                'stderr' => substr((string) @file_get_contents("{$tmp}/stderr_{$i}"), -2000)];
        }
        $res->wall_s = round(microtime(true) - $t0, 3);
        $results[] = $res;
        @unlink($in);
        @unlink($out);
        @unlink("{$tmp}/stdout_{$i}");
        @unlink("{$tmp}/stderr_{$i}");
    }
    echo json_encode($results, JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES | JSON_INVALID_UTF8_SUBSTITUTE | JSON_PARTIAL_OUTPUT_ON_ERROR);
    exit(0);
}

if (($argv[1] ?? '') !== '--one') {
    fwrite(STDERR, "usage: harness_app.php --batch | --one <request.json> <result.json>\n");
    exit(2);
}

// ---------------------------------------------------------------- one request

$__ace_request = json_decode(file_get_contents($argv[2]), true, 512, JSON_THROW_ON_ERROR);
$__ace_result_path = $argv[3];
mysqli_report(MYSQLI_REPORT_OFF);

$__ace_rt = new Runtime();
$__ace_rt->templates = true;
$__ace_rt->concretizeUnmodelled = (bool) ($__ace_request['flags']['concretize'] ?? false);
Runtime::$php7Compare = (bool) ($__ace_request['flags']['php7Compare'] ?? false);
$__ace_sinks = [];
$__ace_standins = [];

(static function (Runtime $rt, array &$sinks, array &$standins): void {
    foreach (SQL_SINKS as $name) {
        $rt->target($name, 'concrete', '?', function (array $args, string $resultName) use ($rt, $name, &$sinks) {
            $values = array_values($args);
            $stmt = statement_arg($name, $args);
            $note = match (true) {
                $stmt instanceof Template => $stmt->render(fn(Value $v) => $rt->bindRef($v)),
                $stmt instanceof Value => $rt->bindRef($stmt),
                default => (string) $stmt,
            };
            $rt->publishNote($note);
            $text = (string) plain($rt, $stmt);
            $conn = $name === 'mysql_query' ? ($values[1] ?? null) : ($values[0] ?? null);
            $rest = array_map(fn($v) => plain($rt, $v), array_slice($values, 2));
            $result = false;
            $summary = ['text' => $text];
            if ($conn instanceof mysqli) {
                try {
                    $result = $name === 'mysql_query' ? false : $name($conn, $text, ...$rest);
                } catch (\ValueError $e) {
                    // PHP 8 throws on an empty statement; PHP 7.4 warned and
                    // returned false -- which the app then has to cope with.
                    $result = false;
                    $summary['value_error'] = $e->getMessage();
                }
                $summary += ['ok' => $result !== false, 'errno' => mysqli_errno($conn), 'error' => mysqli_error($conn),
                    'rows' => $result instanceof mysqli_result ? $result->num_rows : mysqli_affected_rows($conn)];
            } else {
                $summary += ['ok' => false, 'error' => 'no mysqli connection'];
            }
            $sinks[] = ['sink' => $name, 'family' => 'sql', 'text' => $text, 'errno' => $summary['errno'] ?? null];
            return ['value' => $result, 'summary' => $summary];
        });
    }
    foreach (SHELL_SINKS as $name) {
        $rt->target($name, 'target_function', 'bool', function (array $args) use ($rt, $name, &$sinks) {
            $stmt = statement_arg($name, $args);
            $rt->publishNote($stmt instanceof Template ? $stmt->render(fn(Value $v) => $rt->bindRef($v))
                : ($stmt instanceof Value ? $rt->bindRef($stmt) : (string) $stmt));
            $sinks[] = ['sink' => $name, 'family' => 'shell', 'text' => (string) plain($rt, $stmt)];
            return true;      // never executed
        });
    }
    foreach ([...SESSION_STANDINS, ...HEADER_STANDINS] as $name) {
        $rt->target($name, 'concrete', '?', function (array $args) use ($rt, $name, &$standins) {
            $plain = array_map(fn($v) => plain($rt, $v), array_values($args));
            $standins[] = [$name, $plain];
            $value = match ($name) {
                'session_destroy', 'session_unset' => (function () { $_SESSION = []; return true; })(),
                'session_id' => 'acesession',
                'session_name' => 'PHPSESSID',
                'session_cache_limiter' => 'nocache',
                'header', 'header_remove' => null,
                'http_response_code' => 200,
                default => true,
            };
            return ['value' => $value, 'summary' => ['args' => $plain]];
        });
    }
})($__ace_rt, $__ace_sinks, $__ace_standins);

$__ace_seeds = $__ace_types = $__ace_names = [];
foreach (['GET', 'POST', 'COOKIE'] as $__ace_g) {
    foreach ($__ace_request['inputs'][$__ace_g] ?? [] as $__ace_k => $__ace_v) {
        $__ace_n = input_name($__ace_g, (string) $__ace_k);
        $__ace_seeds[$__ace_n] = $__ace_v;
        $__ace_types[$__ace_n] = 'str?';
        $__ace_names[$__ace_n] = [$__ace_g, (string) $__ace_k];
    }
}

$__ace_discovered = [];
$__ace_output = '';
$__ace_app = rtrim($__ace_request['app'], '/');
$__ace_done = false;

/** Write the result; also the path a fatal error or a real exit takes. */
function __ace_write_result(?Throwable $caught): void
{
    global $__ace_rt, $__ace_done, $__ace_result_path, $__ace_names, $__ace_discovered, $__ace_sinks,
        $__ace_standins, $__ace_output, $__ace_ob_base;
    if ($__ace_done) {
        return;
    }
    $__ace_done = true;
    while (ob_get_level() > $__ace_ob_base) {
        $__ace_output = ob_get_clean() . $__ace_output;
    }
    $dump = $__ace_rt->finish($caught);
    $res = [
        'dump' => $dump,
        'inputs' => (object) array_map(fn($p) => ['global' => $p[0], 'key' => $p[1]], $__ace_names),
        'discovered' => (object) array_map(fn($keys) => array_map('strval', array_keys($keys)), $__ace_discovered),
        'sinks' => $__ace_sinks,
        'standins' => $__ace_standins,
        'output_bytes' => strlen($__ace_output),
        'output' => substr($__ace_output, 0, 65536),
        'session_after' => isset($_SESSION) && is_array($_SESSION) ? array_map(fn($v) => is_scalar($v) || $v === null ? $v : gettype($v), $_SESSION) : null,
        'php7' => ['const7' => $GLOBALS['__ace_const7'] ?? [], 'count7' => $GLOBALS['__ace_count7'] ?? 0,
            'cmp7' => $GLOBALS['__ace_cmp7'] ?? 0, 'arith7' => $GLOBALS['__ace_arith7'] ?? 0,
            'call7' => $GLOBALS['__ace_call7'] ?? []],
    ];
    file_put_contents($__ace_result_path, json_encode($res, JSON_UNESCAPED_SLASHES | JSON_INVALID_UTF8_SUBSTITUTE | JSON_PARTIAL_OUTPUT_ON_ERROR));
}

register_shutdown_function(static function (): void {
    // Reached only if the request did not come back to file scope: a fatal
    // error, or a real `exit` in a file the instrumentor could not rewrite.
    $e = error_get_last();
    __ace_write_result(new Error($e ? "fatal: {$e['message']} at {$e['file']}:{$e['line']}" : 'the process exited inside the app'));
});

$__ace_inputs = $__ace_rt->begin($__ace_seeds, $__ace_request['label'] ?? null, [], $__ace_types);
$__ace_known = ['GET' => [], 'POST' => [], 'COOKIE' => []];
foreach ($__ace_inputs as $__ace_n => $__ace_v) {
    [$__ace_g, $__ace_k] = $__ace_names[$__ace_n];
    $__ace_known[$__ace_g][$__ace_k] = $__ace_v;
}
$_GET = new RecordingSuperglobal('GET', $__ace_known['GET'], $__ace_discovered);
$_POST = new RecordingSuperglobal('POST', $__ace_known['POST'], $__ace_discovered);
$_COOKIE = new RecordingSuperglobal('COOKIE', $__ace_known['COOKIE'], $__ace_discovered);
$_REQUEST = new RequestSuperglobal([$_GET, $_POST, $_COOKIE]);
$_FILES = [];
$_SESSION = $__ace_request['session'] ?? [];
foreach ($__ace_request['server'] ?? [] as $__ace_k => $__ace_v) {
    $_SERVER[$__ace_k] = $__ace_v;
}
$_SERVER['REQUEST_METHOD'] = $__ace_known['POST'] ? 'POST' : 'GET';
$_SERVER['SCRIPT_FILENAME'] = $__ace_app . '/' . $__ace_request['script'];
$_SERVER['DOCUMENT_ROOT'] = $__ace_app;
$_SERVER['argv'] = [];
$_SERVER['argc'] = 0;
unset($__ace_g, $__ace_k, $__ace_v, $__ace_n, $__ace_known, $__ace_inputs);

chdir(dirname($__ace_app . '/' . $__ace_request['script']));
$__ace_ob_base = ob_get_level();
ob_start();
$__ace_caught = null;
try {
    include $__ace_app . '/' . $__ace_request['script'];
} catch (\Throwable $__ace_e) {
    $__ace_caught = $__ace_e;
}
__ace_write_result($__ace_caught);
