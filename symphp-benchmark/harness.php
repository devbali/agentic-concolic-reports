<?php

/**
 * One PHP web request, run under the ACE typed runtime.
 *
 * Reads a JSON list of requests on stdin, writes a JSON list of results on
 * stdout. A request is
 *
 *     {"app": <instrumented tree>, "script": "test-2.php", "label": "...",
 *      "inputs": {"GET": {"nv1": "x", "vul1": null}, "POST": {...}, "COOKIE": {...}}}
 *
 * and every key named in `inputs` becomes a `str?` symbolic input -- `null`
 * seeds it ABSENT, which is what `isset()` decides on. That is the whole
 * request model, and it is deliberately the same surface SymPHP marks
 * symbolic (the superglobals), plus COOKIE and plus absence, which SymPHP's
 * byte-level marking cannot express.
 *
 * KEYS ARE DISCOVERED, NOT READ FROM SOURCE. Each superglobal is a
 * `RecordingSuperglobal`: a read of a key the request did not declare answers
 * `null` -- exactly what PHP answers for a missing key -- and records the key
 * name. The driver declares it (absent) on the next round, at which point the
 * absence is a recorded decision and the solver can flip it. Nothing here
 * parses the application.
 *
 * SINKS ARE TARGET FUNCTIONS. A SQL or shell sink publishes its statement as
 * the call's note, with every symbolic part as a `$$(ref)` to the input it
 * carries (Concolic\Template). The verdict -- does a reachable input break the
 * statement's syntax -- is not made here; see sinks.py.
 */

$runtime = getenv('ACE_PHP_RUNTIME') ?: dirname(__DIR__, 2) . '/agentic_concolic_engine/runtimes/php_runtime';
require_once $runtime . '/src/autoload.php';

use Concolic\Runtime;
use Concolic\Template;
use Concolic\Value;

/** The sink families, by the builtin that reaches them. */
const SQL_SINKS = ['mysqli_query', 'mysqli_real_query', 'mysqli_multi_query', 'mysql_query'];
const SHELL_SINKS = ['system', 'exec', 'shell_exec', 'passthru', 'popen', 'proc_open'];

/**
 * Builtins the application calls that the harness answers instead of the
 * real extension. SHIMS: never an access, so never a policy. Each returns
 * what a working connection returns.
 */
const SHIMS = [
    'mysqli_connect' => ['bool', true],
    'mysqli_connect_errno' => ['int', 0],
    'mysqli_connect_error' => ['str?', null],
    'mysqli_select_db' => ['bool', true],
    'mysqli_close' => ['bool', true],
    'mysqli_error' => ['str', ''],
];

/** Which positional argument carries the statement, per sink. */
function statement_arg(string $sink, array $args): mixed
{
    $values = array_values($args);
    return match ($sink) {
        'mysqli_query', 'mysqli_real_query', 'mysqli_multi_query' => $values[1] ?? null,
        default => $values[0] ?? null,
    };
}

/** A symbolic input's dump name: readable, and unique per (superglobal, key). */
function input_name(string $global, string $key): string
{
    $clean = preg_replace('/[^A-Za-z0-9_]/', '_', $key);
    return $clean === $key ? "{$global}_{$key}" : "{$global}_{$clean}_" . substr(md5($key), 0, 6);
}

final class RecordingSuperglobal implements ArrayAccess, IteratorAggregate, Countable
{
    /** @param array<string, Value> $known */
    public function __construct(private string $global, private array $known, private array &$discovered)
    {
    }

    public function offsetExists(mixed $key): bool
    {
        // `isset($_GET[k])` is rewritten to `__isset($_GET[k] ?? null)`, and
        // `??` on an ArrayAccess asks offsetExists first. Answering true for a
        // DECLARED key hands the Value to __isset, which records presence.
        if (array_key_exists($key, $this->known)) {
            return true;
        }
        $this->discovered[$this->global][$key] = true;
        return false;
    }

    public function offsetGet(mixed $key): mixed
    {
        if (array_key_exists($key, $this->known)) {
            return $this->known[$key];
        }
        $this->discovered[$this->global][$key] = true;
        return null;
    }

    public function offsetSet(mixed $key, mixed $value): void
    {
        $this->known[$key] = $value;
    }

    public function offsetUnset(mixed $key): void
    {
        unset($this->known[$key]);
    }

    public function getIterator(): Traversable
    {
        // Iterating the superglobal enumerates the KEYS, which this model does
        // not make symbolic; refuse rather than answer with this run's set.
        throw new Concolic\NotImplementedError("Iterating \$_{$this->global} is not modelled");
    }

    public function count(): int
    {
        throw new Concolic\NotImplementedError("count(\$_{$this->global}) is not modelled");
    }
}

/** A `RecordingSuperglobal` for $_REQUEST: GET, then POST, then COOKIE. */
final class RequestSuperglobal implements ArrayAccess
{
    public function __construct(private array $sources)
    {
    }

    public function offsetExists(mixed $key): bool
    {
        foreach ($this->sources as $s) {
            if ($s->offsetExists($key)) {
                return true;
            }
        }
        return false;
    }

    public function offsetGet(mixed $key): mixed
    {
        foreach ($this->sources as $s) {
            if ($s->offsetExists($key)) {
                return $s->offsetGet($key);
            }
        }
        return null;
    }

    public function offsetSet(mixed $key, mixed $value): void
    {
        throw new LogicException('writing $_REQUEST is not modelled');
    }

    public function offsetUnset(mixed $key): void
    {
        throw new LogicException('writing $_REQUEST is not modelled');
    }
}

function run_request(array $request): array
{
    $rt = new Runtime();
    $rt->templates = true;
    $sinks = [];

    foreach (SHIMS as $name => [$type, $value]) {
        $rt->target($name, 'shim', $type, fn() => $value);
    }
    foreach ([...SQL_SINKS, ...SHELL_SINKS] as $name) {
        $family = in_array($name, SQL_SINKS, true) ? 'sql' : 'shell';
        $rt->target($name, 'target_function', 'bool', function (array $args) use ($rt, $name, $family, &$sinks) {
            $stmt = statement_arg($name, $args);
            if ($stmt instanceof Template) {
                $note = $stmt->render(fn(Value $v) => $rt->bindRef($v));
            } elseif ($stmt instanceof Value) {
                $note = $rt->bindRef($stmt);
            } else {
                $note = (string) $stmt;
            }
            $rt->publishNote($note);
            $sinks[] = ['sink' => $name, 'family' => $family, 'text' => $stmt instanceof Template ? $stmt->text()
                : ($stmt instanceof Value ? $rt->text($stmt) : (string) $stmt)];
            // The sink's own result is not modelled: the application gets
            // "succeeded", which is what a well-formed statement returns.
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

$requests = json_decode(stream_get_contents(STDIN), true, 512, JSON_THROW_ON_ERROR);
$results = [];
foreach ($requests as $request) {
    $results[] = run_request($request);
}
echo json_encode($results, JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES | JSON_INVALID_UTF8_SUBSTITUTE);
