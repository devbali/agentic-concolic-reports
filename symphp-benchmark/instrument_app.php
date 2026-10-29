<?php

/**
 * usage: php instrument_app.php <app-src> <build-dir> [--app-targets] [--php7compat] [--exit-as-halt] [--switch-cmp]
 *
 * Copies the application and instruments EVERY .php file in the copy, not
 * just the ones an expected path loads: a symbolic value reaching an
 * uninstrumented file is the one failure this design cannot make loud, since
 * `if ($sym)` on an object is silently true. A file the instrumentor cannot
 * rewrite is reported and left as it was.
 *
 * The options only ever change the COPY in <build-dir>; <app-src> is read.
 * --app-targets   route harness_app.php's targets (SQL sinks, shell sinks,
 *                 session/header stand-ins) instead of harness.php's
 * --php7compat    E2: the copy behaves as on PHP 7.4 where 8.x would differ
 * --exit-as-halt  E3: exit/die end the run, not the process
 * --switch-cmp    switch cases compare through __cmp (implied by --php7compat)
 * --superglobal-reads  decision (b) array mode: direct superglobal reads -> __sg_key probe
 * --real-app-builtins   route type predicates (is_scalar, gettype, ...) through __fn
 * Every rewrite an option performs is counted, per file and in total.
 */

$runtime = getenv('ACE_PHP_RUNTIME') ?: dirname(__DIR__, 2) . '/agentic_concolic_engine/runtimes/php_runtime';
require_once $runtime . '/vendor/autoload.php';
require_once $runtime . '/src/autoload.php';

$flags = array_values(array_filter(array_slice($argv, 1), fn($a) => str_starts_with($a, '--')));
$pos = array_values(array_filter(array_slice($argv, 1), fn($a) => !str_starts_with($a, '--')));
[$src, $build] = $pos + [null, null];
if (!$src || !$build) {
    fwrite(STDERR, "usage: php instrument_app.php <app-src> <build-dir> [--app-targets] [--php7compat] [--exit-as-halt] [--switch-cmp]\n");
    exit(2);
}
$options = [
    'php7Compat' => in_array('--php7compat', $flags, true),
    'exitAsHalt' => in_array('--exit-as-halt', $flags, true),
    'switchCmp' => in_array('--switch-cmp', $flags, true),
    'superglobalReads' => in_array('--superglobal-reads', $flags, true),
    'realAppBuiltins' => in_array('--real-app-builtins', $flags, true),
];

if (in_array('--app-targets', $flags, true)) {
    // harness_app.php's app_targets(), by name.
    $targets = array_fill_keys([
        'mysqli_query', 'mysqli_real_query', 'mysqli_multi_query', 'mysql_query',
        'system', 'exec', 'shell_exec', 'passthru', 'popen', 'proc_open',
        'session_start', 'session_destroy', 'session_regenerate_id', 'session_unset',
        'session_write_close', 'session_id', 'session_name', 'session_cache_limiter', 'session_set_cookie_params',
        'header', 'setcookie', 'setrawcookie', 'header_remove', 'http_response_code',
    ], true);
} else {
    // The harness's SQL_SINKS, SHELL_SINKS and SHIMS, by name.
    $targets = array_fill_keys([
        'mysqli_query', 'mysqli_real_query', 'mysqli_multi_query', 'mysql_query',
        'system', 'exec', 'shell_exec', 'passthru', 'popen', 'proc_open',
        'mysqli_connect', 'mysqli_connect_errno', 'mysqli_connect_error',
        'mysqli_select_db', 'mysqli_close', 'mysqli_error',
    ], true);
}

if (is_dir($build)) {
    exec('rm -rf ' . escapeshellarg($build));
}
mkdir($build, 0o777, true);
exec(sprintf('cp -a %s/. %s', escapeshellarg($src), escapeshellarg($build)), $o, $rc);
if ($rc !== 0) {
    fwrite(STDERR, "copy failed\n");
    exit(1);
}

$ok = $failed = 0;
$warnings_all = [];
$failures = [];
$rewrites_total = [];
$rewrites_by_file = [];
$it = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($build, FilesystemIterator::SKIP_DOTS));
foreach ($it as $file) {
    if (!$file->isFile() || $file->getExtension() !== 'php') {
        continue;
    }
    $path = $file->getPathname();
    $rel = substr($path, strlen($build) + 1);
    try {
        $warnings = null;
        $rewrites = null;
        file_put_contents($path, Concolic\Instrument::source(file_get_contents($path), $targets, $rel, null, $warnings,
            false, $options, $rewrites));
        foreach ((array) $warnings as $w) {
            $warnings_all[] = "{$rel}: {$w}";
        }
        if ($rewrites) {
            ksort($rewrites);
            $rewrites_by_file[$rel] = $rewrites;
            foreach ($rewrites as $k => $n) {
                $rewrites_total[$k] = ($rewrites_total[$k] ?? 0) + $n;
            }
        }
        $ok++;
    } catch (Throwable $e) {
        $failed++;
        $failures[] = "{$rel}: {$e->getMessage()}";
        fwrite(STDERR, "  [warn] {$rel}: {$e->getMessage()}\n");
    }
}
ksort($rewrites_total);
ksort($rewrites_by_file);
$report = ['instrumented' => $ok, 'failed' => $failed, 'warnings' => $warnings_all];
if (array_filter($options) || in_array('--app-targets', $flags, true)) {
    $report += ['options' => $options, 'failures' => $failures, 'rewrites_total' => (object) $rewrites_total,
        'rewrites_by_file' => (object) $rewrites_by_file];
}
echo json_encode($report, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES), "\n";
