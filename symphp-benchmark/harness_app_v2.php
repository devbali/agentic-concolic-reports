<?php

/**
 * harness_app.php for the v2 engine (php-runtime/real-apps-v2: main's native
 * `concat`). Same protocol, same file-scope request, same real clone database,
 * sessions, header stand-ins and shutdown path as harness_app.php; see there.
 *
 * What differs:
 * - No Concolic\Template. A statement built with `.` is a symbolic string
 *   whose term is the whole concatenation. The SQL sinks are still E1
 *   CONCRETE targets (the query runs for real on this run's text and the real
 *   result goes back to the app); the `concrete_call` event now carries the
 *   statement's TERM in its args, and the note only names the statement
 *   argument and its text (harness_v2.php's v2_statement_note).
 * - Request flags whose engine work is not ported yet (port plan P4-P6:
 *   php7Compare, concretize, arrayMode, outputEvents, templateSplit,
 *   evalInstrument, E7's db classes) are REFUSED: the request comes back as a
 *   harness error rather than running with the flag silently off.
 */

define('ACE_HARNESS_V2_LIB', true);
define('ACE_HARNESS_LIB', true);
require __DIR__ . '/harness_v2.php';

use Concolic\Runtime;
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

/**
 * The harness's state lives in a static class, not in globals: an app may
 * unset every global it does not know (phpMyAdmin's common.inc.php does).
 */
final class AceState
{
    public static Runtime $rt;
    public static string $result_path;
    public static array $sinks = [];
    public static array $standins = [];
    public static array $names = [];
    public static array $discovered = [];
    public static string $output = '';
    public static bool $done = false;
    public static int $ob_base = 0;
    public static array $request = [];
    public static string $app = '';
    public static bool $session_started = false;
}

/** A copy of `$v` with every symbolic value made concrete and every object kept. */
function deplain(mixed $v): mixed
{
    if ($v instanceof Value) {
        return $v->fields === null && !str_starts_with($v->type, '[') ? $v->concrete() : null;
    }
    if (is_array($v)) {
        return array_map('deplain', $v);
    }
    return $v;
}

// Every runtime class is loaded BEFORE the app: an app that prepends its own autoloader (Drupal's
// composer loader compares class names with `===`, i.e. through \__cmp) would otherwise be asked
// for Concolic\Z3 from inside itself, and the class would never load.
$__ace_src = (getenv('ACE_PHP_RUNTIME') ?: dirname(__DIR__, 2) . '/agentic_concolic_engine/runtimes/php_runtime') . '/src';
foreach (new RecursiveIteratorIterator(new RecursiveDirectoryIterator($__ace_src, FilesystemIterator::SKIP_DOTS)) as $__ace_f) {
    $__ace_rel = substr($__ace_f->getPathname(), strlen($__ace_src . '/'));
    // Not the instrumentor (it needs PhpParser, loaded only for eval instrumentation).
    if ($__ace_f->getExtension() === 'php'
        && !in_array($__ace_rel, ['autoload.php', 'probes.php', 'Instrument.php', 'InstrumentVisitor.php'], true)) {
        $__ace_c = 'Concolic\\' . str_replace('/', '\\', substr($__ace_rel, 0, -4));
        try {
            class_exists($__ace_c) || interface_exists($__ace_c) || trait_exists($__ace_c) || enum_exists($__ace_c);
        } catch (\Throwable) {
        }
    }
}
unset($__ace_f, $__ace_rel, $__ace_c, $__ace_src);

AceState::$request = json_decode(file_get_contents($argv[2]), true, 512, JSON_THROW_ON_ERROR);
AceState::$result_path = $argv[3];
mysqli_report(MYSQLI_REPORT_OFF);

AceState::$rt = new Runtime();
$__ace_unported = array_keys(array_filter(array_intersect_key(AceState::$request['flags'] ?? [], array_flip(
    ['php7Compare', 'concretize', 'arrayMode', 'outputEvents', 'templateSplit', 'evalInstrument', 'dbClasses']))));
if ($__ace_unported) {
    file_put_contents(AceState::$result_path, json_encode(['harness_error' => 'not ported to the v2 engine yet (port plan P4-P6): '
        . implode(', ', $__ace_unported)]));
    exit(0);
}
unset($__ace_unported);
AceState::$sinks = [];
AceState::$standins = [];

(static function (Runtime $rt, array &$sinks, array &$standins): void {
    foreach (SQL_SINKS as $name) {
        $rt->target($name, 'concrete', '?', function (array $args, string $resultName) use ($rt, $name, &$sinks) {
            $values = array_values($args);
            [$note, $text] = v2_statement_note($name, $args);
            $rt->publishNote($note);
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
    if (!empty(AceState::$request['flags']['sanitizers'])) {
        v2_register_sanitizers($rt);           // P3 (sanitizers_v2.php)
    }
    foreach (SHELL_SINKS as $name) {
        $rt->target($name, 'target_function', 'bool', function (array $args) use ($rt, $name, &$sinks) {
            [$note, $text] = v2_statement_note($name, $args);
            $rt->publishNote($note);
            $sinks[] = ['sink' => $name, 'family' => 'shell', 'text' => $text];
            return true;      // never executed
        });
    }
    foreach ([...SESSION_STANDINS, ...HEADER_STANDINS] as $name) {
        $rt->target($name, 'concrete', '?', function (array $args) use ($rt, $name, &$standins) {
            $plain = array_map(fn($v) => plain($rt, $v), array_values($args));
            $standins[] = [$name, $plain];
            $value = match ($name) {
                // The seeded session arrives SERIALIZED and is restored here, as
                // PHP's own handler does -- after the app has registered its
                // autoloader, so session objects come back as their classes.
                'session_start' => (function () {
                    if (!isset($_SESSION)) {
                        $_SESSION = [];
                    }
                    if (!AceState::$session_started && !empty(AceState::$request['flags']['realSession'])
                        && session_status() !== PHP_SESSION_ACTIVE) {
                        // apps.json ace_real_session (OpenCart 2.3: its save handler extends
                        // SessionHandler, whose create_sid() needs an ACTIVE session). A real,
                        // cookie-less session in the runner's tmp; the seeded data is put over it.
                        @\session_start(['use_cookies' => 0, 'use_only_cookies' => 0, 'cache_limiter' => '',
                            'save_path' => sys_get_temp_dir()]);
                    }
                    if (!AceState::$session_started && (AceState::$request['session_ser'] ?? '') !== '') {
                        $restored = unserialize(base64_decode(AceState::$request['session_ser']));
                        $_SESSION = is_array($restored) ? $restored + (is_array($_SESSION ?? null) ? $_SESSION : []) : ($_SESSION ?? []);
                    }
                    AceState::$session_started = true;
                    return true;
                })(),
                'session_destroy', 'session_unset' => (function () { $_SESSION = []; return true; })(),
                // realSession: the real id (empty until started), as the app's own guard expects.
                'session_id' => match (true) {
                    !empty(AceState::$request['flags']['realSession']) => \session_id(),
                    // apps.json ace_session_id_before_start (MediaWiki): '' until session_start, as in PHP.
                    !empty(AceState::$request['flags']['sessionIdBeforeStart']) && !AceState::$session_started => '',
                    default => 'acesession',
                },
                'session_name' => 'PHPSESSID',
                'session_cache_limiter' => 'nocache',
                'header', 'header_remove' => null,
                'http_response_code' => 200,
                default => true,
            };
            return ['value' => $value, 'summary' => ['args' => $plain]];
        });
    }
})(AceState::$rt, AceState::$sinks, AceState::$standins);

$__ace_seeds = $__ace_types = AceState::$names = [];
foreach (['GET', 'POST', 'COOKIE'] as $__ace_g) {
    foreach (AceState::$request['inputs'][$__ace_g] ?? [] as $__ace_k => $__ace_v) {
        $__ace_n = input_name($__ace_g, (string) $__ace_k);
        $__ace_seeds[$__ace_n] = $__ace_v;
        $__ace_types[$__ace_n] = 'str?';
        AceState::$names[$__ace_n] = [$__ace_g, (string) $__ace_k];
    }
}

AceState::$discovered = [];
AceState::$output = '';
AceState::$app = rtrim(AceState::$request['app'], '/');
AceState::$done = false;

/** Write the result; also the path a fatal error or a real exit takes. */
function __ace_write_result(?Throwable $caught): void
{
    if (AceState::$done) {
        return;
    }
    AceState::$done = true;
    while (ob_get_level() > AceState::$ob_base) {
        AceState::$output = ob_get_clean() . AceState::$output;
    }
    $dump = AceState::$rt->finish($caught);
    $res = [
        'dump' => $dump,
        'inputs' => (object) array_map(fn($p) => ['global' => $p[0], 'key' => $p[1]], AceState::$names),
        'discovered' => (object) array_map(fn($keys) => array_map('strval', array_keys($keys)), AceState::$discovered),
        'sinks' => AceState::$sinks,
        'standins' => AceState::$standins,
        'output_bytes' => strlen(AceState::$output),
        'output' => substr(AceState::$output, 0, 65536),
        'session_after' => isset($_SESSION) && is_array($_SESSION) ? array_map(fn($v) => plain(AceState::$rt, $v), $_SESSION) : null,
        'session_after_ser' => isset($_SESSION) && is_array($_SESSION) ? (static function () {
            try {
                return base64_encode(serialize(deplain($_SESSION)));   // binary-safe through JSON
            } catch (\Throwable $e) {
                return null;                          // e.g. a closure in the session
            }
        })() : null,
    ];
    file_put_contents(AceState::$result_path, json_encode($res, JSON_UNESCAPED_SLASHES | JSON_INVALID_UTF8_SUBSTITUTE | JSON_PARTIAL_OUTPUT_ON_ERROR));
}

register_shutdown_function(static function (): void {
    // Reached only if the request did not come back to file scope: a fatal
    // error, or a real `exit` in a file the instrumentor could not rewrite.
    $e = error_get_last();
    __ace_write_result(new Error($e ? "fatal: {$e['message']} at {$e['file']}:{$e['line']}" : 'the process exited inside the app'));
});

$__ace_inputs = AceState::$rt->begin($__ace_seeds, AceState::$request['label'] ?? null, [], $__ace_types);
$__ace_known = ['GET' => [], 'POST' => [], 'COOKIE' => []];
foreach ($__ace_inputs as $__ace_n => $__ace_v) {
    [$__ace_g, $__ace_k] = AceState::$names[$__ace_n];
    $__ace_known[$__ace_g][$__ace_k] = $__ace_v;
}
$_GET = new RecordingSuperglobal('GET', $__ace_known['GET'], AceState::$discovered);
$_POST = new RecordingSuperglobal('POST', $__ace_known['POST'], AceState::$discovered);
$_COOKIE = new RecordingSuperglobal('COOKIE', $__ace_known['COOKIE'], AceState::$discovered);
$_REQUEST = new RequestSuperglobal([$_GET, $_POST, $_COOKIE]);
$_FILES = [];
$_SESSION = AceState::$request['session'] ?? [];
if (!empty(AceState::$request['flags']['sessionUnsetBeforeStart']) && $_SESSION === []) {
    // apps.json ace_session_unset_before_start (WebChess chess.php: `if (!isset($_SESSION))
    // session_start();`): as in PHP, $_SESSION does not exist until session_start.
    unset($_SESSION);
}
foreach (AceState::$request['server'] ?? [] as $__ace_k => $__ace_v) {
    $_SERVER[$__ace_k] = $__ace_v;
}
// The judge's own REQUEST_METHOD for this request (POST iff a POST value is present).
$_SERVER['REQUEST_METHOD'] ??= array_filter(AceState::$request['inputs']['POST'] ?? [], fn($v) => $v !== null) ? 'POST' : 'GET';
$_SERVER['SCRIPT_FILENAME'] = AceState::$app . '/' . AceState::$request['script'];
$_SERVER['DOCUMENT_ROOT'] = AceState::$app;
$_SERVER['argv'] = [];
$_SERVER['argc'] = 0;
unset($__ace_g, $__ace_k, $__ace_v, $__ace_n, $__ace_known, $__ace_inputs);

chdir(dirname(AceState::$app . '/' . AceState::$request['script']));
AceState::$ob_base = ob_get_level();
ob_start();
$__ace_caught = null;
try {
    include AceState::$app . '/' . AceState::$request['script'];
} catch (\Throwable $__ace_e) {
    $__ace_caught = $__ace_e;
}
__ace_write_result($__ace_caught);
