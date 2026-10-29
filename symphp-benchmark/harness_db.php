<?php

/**
 * E7 (app mode, `--db-classes`): object-style database sinks.
 *
 * The instrumentor's `newClassMap` option rewrites `new PDO(...)` to `new \AcePDO(...)` and
 * `new mysqli(...)` to `new \AceMysqli(...)` in ACE's COPY of the app (never in the app). Each
 * subclass overrides the methods that take SQL text -- PDO::prepare/query/exec,
 * mysqli::query/real_query/multi_query/prepare -- and sends the statement through a concrete
 * target of the same name (`PDO::prepare`, ...): the statement's note (with `$$(ref)` for each
 * input) is published exactly as for `mysqli_query`, then the parent method runs on this run's
 * text and its real result goes back to the app. An exception the parent throws (PDO's
 * ERRMODE_EXCEPTION) is recorded in the summary and rethrown after the event is written, so a
 * statement that FAILS is still a recorded sink.
 *
 * `Runtime::$locationSkipFiles` names this file, so each event is located at the app line that
 * called the method (e.g. WeBid's DatabasePDO.php:76), not here.
 */

use Concolic\Runtime;
use Concolic\Template;
use Concolic\Value;

const DB_CLASS_SINKS = ['PDO::prepare', 'PDO::query', 'PDO::exec',
    'mysqli::query', 'mysqli::real_query', 'mysqli::multi_query', 'mysqli::prepare'];

final class AceThrown
{
    public function __construct(public readonly \Throwable $e) {}
}

function ace_db_register(Runtime $rt, array &$sinks): void
{
    foreach (DB_CLASS_SINKS as $name) {
        $rt->target($name, 'concrete', '?', function (array $args, string $resultName, ?callable $run) use ($rt, $name, &$sinks) {
            $stmt = $args['query'];
            $note = match (true) {
                $stmt instanceof Template => $stmt->render(fn(Value $v, array $apply = []) => $rt->bindRef($v, $apply)),
                $stmt instanceof Value => $rt->bindRef($stmt),
                default => (string) $stmt,
            };
            $rt->publishNote($note);
            $text = (string) plain($rt, $stmt);
            $summary = ['text' => $text];
            try {
                $value = $run($text);
                $summary['ok'] = $value !== false;
            } catch (\ValueError $e) {
                // mysqli on PHP 8 throws on an empty statement; PHP 7.4 warned and returned false.
                $value = $args['conn'] instanceof \mysqli ? false : new AceThrown($e);
                $summary['ok'] = false;
                $summary['value_error'] = $e->getMessage();
            } catch (\Throwable $e) {
                $value = new AceThrown($e);
                $summary['ok'] = false;
                $summary['exception'] = get_class($e) . ': ' . substr($e->getMessage(), 0, 300);
            }
            $conn = $args['conn'];
            if ($conn instanceof \PDO) {
                $info = $value instanceof AceThrown && $value->e instanceof \PDOException ? ($value->e->errorInfo ?? null) : $conn->errorInfo();
                $summary['errno'] = is_array($info) && isset($info[1]) ? (int) $info[1] : 0;
                $summary['error'] = is_array($info) ? (string) ($info[2] ?? '') : '';
            } elseif ($conn instanceof \mysqli) {
                $summary['errno'] = $conn->errno;
                $summary['error'] = $conn->error;
            }
            $sinks[] = ['sink' => $name, 'family' => 'sql', 'text' => $text, 'errno' => $summary['errno'] ?? null];
            return ['value' => $value, 'summary' => $summary];
        });
    }
}

function ace_db_call(string $name, object $conn, mixed $query, \Closure $run): mixed
{
    $value = AceState::$rt->call($name, ['query' => $query, 'conn' => $conn], $run);
    if ($value instanceof AceThrown) {
        throw $value->e;
    }
    return $value;
}

class AcePDO extends \PDO
{
    public function prepare($query, $options = []): \PDOStatement|false
    {
        return ace_db_call('PDO::prepare', $this, $query, fn(string $t) => parent::prepare($t, $options));
    }

    public function query($query, $fetchMode = null, ...$fetchModeArgs): \PDOStatement|false
    {
        return ace_db_call('PDO::query', $this, $query,
            fn(string $t) => $fetchMode === null ? parent::query($t) : parent::query($t, $fetchMode, ...$fetchModeArgs));
    }

    public function exec($statement): int|false
    {
        return ace_db_call('PDO::exec', $this, $statement, fn(string $t) => parent::exec($t));
    }
}

class AceMysqli extends \mysqli
{
    public function query($query, $result_mode = MYSQLI_STORE_RESULT): \mysqli_result|bool
    {
        return ace_db_call('mysqli::query', $this, $query, fn(string $t) => parent::query($t, $result_mode));
    }

    public function real_query($query): bool
    {
        return ace_db_call('mysqli::real_query', $this, $query, fn(string $t) => parent::real_query($t));
    }

    public function multi_query($query): bool
    {
        return ace_db_call('mysqli::multi_query', $this, $query, fn(string $t) => parent::multi_query($t));
    }

    public function prepare($query): \mysqli_stmt|false
    {
        return ace_db_call('mysqli::prepare', $this, $query, fn(string $t) => parent::prepare($t));
    }
}
