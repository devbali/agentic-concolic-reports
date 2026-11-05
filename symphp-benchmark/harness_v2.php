<?php

/**
 * harness.php for the v2 engine (php-runtime/real-apps-v2: main's native
 * `concat`). Same request/result protocol, same recording superglobals and
 * shims (reused from harness.php through its ACE_HARNESS_LIB guard); what
 * differs is how a sink publishes its statement.
 *
 * On v1 a sink rendered a Concolic\Template into a note with `$$(ref)` parts.
 * On v2 there is no Template: a statement built with `.` IS a symbolic
 * string whose term is the whole concatenation, and the runtime already
 * encodes each target argument as its term in the call event. The sink's note
 * therefore only says WHICH argument is the statement, and its text on this
 * run:
 *
 *     {"statement_arg": "<arg key>", "text": "<concrete statement>"}
 *
 * sinks_v2.py reads the term from the event's args under that key.
 */

define('ACE_HARNESS_LIB', true);
require __DIR__ . '/harness.php';
/** The runtime this harness drives (harness.php loads it from the same place). */
define('ACE_PHP_RUNTIME_DIR', getenv('ACE_PHP_RUNTIME') ?: dirname(__DIR__, 2) . '/agentic_concolic_engine/runtimes/php_runtime');
require __DIR__ . '/sanitizers_v2.php';      // P3: the sanitizer shims, registered under the `sanitizers` flag

use Concolic\Runtime;
use Concolic\Value;

/** The note a sink publishes: which argument is the statement, and its text on this run. */
function v2_statement_note(string $sink, array $args): array
{
    $keys = array_keys($args);
    $pos = in_array($sink, ['mysqli_query', 'mysqli_real_query', 'mysqli_multi_query'], true) ? 1 : 0;
    $stmt = array_values($args)[$pos] ?? null;
    $text = $stmt instanceof Value ? $stmt->runtime->text($stmt) : (string) $stmt;
    $note = ['statement_arg' => (string) ($keys[$pos] ?? '')];
    // A text holding `$$(` would be read as a note reference when sealed; sinks_v2 then evaluates the term.
    if (!str_contains($text, '$$(')) {
        $note['text'] = $text;
    }
    return [json_encode($note, JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES | JSON_INVALID_UTF8_SUBSTITUTE), $text];
}

function run_request_v2(array $request): array
{
    $rt = new Runtime();
    $sinks = [];

    foreach (SHIMS as $name => [$type, $value]) {
        $rt->target($name, 'shim', $type, fn() => $value);
    }
    if (!empty($request['flags']['sanitizers'])) {
        v2_register_sanitizers($rt);
    }
    foreach ([...SQL_SINKS, ...SHELL_SINKS] as $name) {
        $family = in_array($name, SQL_SINKS, true) ? 'sql' : 'shell';
        $rt->target($name, 'target_function', 'bool', function (array $args) use ($rt, $name, $family, &$sinks) {
            [$note, $text] = v2_statement_note($name, $args);
            $rt->publishNote($note);
            $sinks[] = ['sink' => $name, 'family' => $family, 'text' => $text];
            // The sink's own result is not modelled: "succeeded", as for a well-formed statement.
            return true;
        });
    }

    $seeds = $types = $names = [];
    foreach (['GET', 'POST', 'COOKIE'] as $g) {
        foreach ($request['inputs'][$g] ?? [] as $key => $value) {
            $n = input_name($g, (string) $key);
            $seeds[$n] = $value;
            $types[$n] = 'str?';
            $names[$n] = [$g, (string) $key];
        }
    }

    $discovered = [];
    $output = '';
    $app = rtrim($request['app'], '/');
    $script = $request['script'];
    $dump = $rt->run(function (array $v) use ($app, $script, $names, &$discovered, &$output) {
        $known = ['GET' => [], 'POST' => [], 'COOKIE' => []];
        foreach ($v as $n => $value) {
            [$g, $key] = $names[$n];
            $known[$g][$key] = $value;
        }
        $globals = [];
        foreach ($known as $g => $k) {
            $globals[$g] = new RecordingSuperglobal($g, $k, $discovered);
        }
        $_GET = $globals['GET'];
        $_POST = $globals['POST'];
        $_COOKIE = $globals['COOKIE'];
        $_REQUEST = new RequestSuperglobal([$globals['GET'], $globals['POST'], $globals['COOKIE']]);
        $_SERVER['REQUEST_METHOD'] = $known['POST'] ? 'POST' : 'GET';
        $_SERVER['SCRIPT_NAME'] = '/' . $script;

        $cwd = getcwd();
        chdir($app);
        ob_start();
        try {
            (static function () use ($script) {
                include './' . $script;
            })();
        } finally {
            $output = ob_get_clean();
            chdir($cwd);
        }
    }, $seeds, $request['label'] ?? null, [], $types);

    return [
        'dump' => $dump,
        'inputs' => (object) array_map(fn($p) => ['global' => $p[0], 'key' => $p[1]], $names),
        'discovered' => (object) array_map(fn($keys) => array_map('strval', array_keys($keys)), $discovered),
        'sinks' => $sinks,
        'output_bytes' => strlen($output),
    ];
}

// harness_app_v2.php reuses the functions above without this batch loop.
if (!defined('ACE_HARNESS_V2_LIB')) {
    $requests = json_decode(stream_get_contents(STDIN), true, 512, JSON_THROW_ON_ERROR);
    $results = [];
    foreach ($requests as $request) {
        $results[] = run_request_v2($request);
    }
    echo json_encode($results, JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES | JSON_INVALID_UTF8_SUBSTITUTE);
}
