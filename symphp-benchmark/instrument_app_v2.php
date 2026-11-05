<?php

/**
 * instrument_app.php for the v2 engine (php-runtime/real-apps-v2).
 *
 * usage: php instrument_app_v2.php <app-src> <build-dir> [--app-targets] [--ext=php,inc]
 *
 * Copies the application and instruments every source file in the copy, as
 * instrument_app.php does. Main's `Instrument::source` takes no options, so
 * the v1 options that depend on not-yet-ported engine work (E2 --php7compat,
 * E3 --exit-as-halt, --switch-cmp, array mode, --real-app-builtins,
 * --eval-instrument, E7 --db-classes: port plan P4-P6) are REFUSED here
 * rather than silently ignored.
 *
 * --app-targets   harness_app_v2.php's targets (SQL sinks, shell sinks, session/header stand-ins)
 *                 instead of harness_v2.php's (sinks plus the connection shims)
 */

$runtime = getenv('ACE_PHP_RUNTIME') ?: dirname(__DIR__, 2) . '/agentic_concolic_engine/runtimes/php_runtime';
require_once $runtime . '/vendor/autoload.php';
require_once $runtime . '/src/autoload.php';

const V2_NOT_PORTED = ['--php7compat', '--exit-as-halt', '--switch-cmp', '--superglobal-reads', '--real-app-builtins',
    '--eval-instrument', '--db-classes'];

$exts = ['php'];
foreach (array_slice($argv, 1) as $a) {
    if (str_starts_with($a, '--ext=')) {
        $exts = explode(',', substr($a, 6));
    }
}
$flags = array_values(array_filter(array_slice($argv, 1), fn($a) => str_starts_with($a, '--')));
$pos = array_values(array_filter(array_slice($argv, 1), fn($a) => !str_starts_with($a, '--')));
[$src, $build] = $pos + [null, null];
if (!$src || !$build) {
    fwrite(STDERR, "usage: php instrument_app_v2.php <app-src> <build-dir> [--app-targets] [--ext=php,inc]\n");
    exit(2);
}
$refused = array_values(array_intersect($flags, V2_NOT_PORTED));
if ($refused) {
    fwrite(STDERR, 'not ported to the v2 engine yet (port plan P4-P6): ' . implode(' ', $refused) . "\n");
    exit(2);
}

$targets = [
    'mysqli_query', 'mysqli_real_query', 'mysqli_multi_query', 'mysql_query',
    'system', 'exec', 'shell_exec', 'passthru', 'popen', 'proc_open',
];
if (in_array('--app-targets', $flags, true)) {
    // harness_app_v2.php's stand-ins, by name.
    array_push($targets, 'session_start', 'session_destroy', 'session_regenerate_id', 'session_unset',
        'session_write_close', 'session_id', 'session_name', 'session_cache_limiter', 'session_set_cookie_params',
        'header', 'setcookie', 'setrawcookie', 'header_remove', 'http_response_code');
} else {
    // harness.php's SHIMS, by name.
    array_push($targets, 'mysqli_connect', 'mysqli_connect_errno', 'mysqli_connect_error',
        'mysqli_select_db', 'mysqli_close', 'mysqli_error');
}
$targets = array_fill_keys($targets, true);

if (is_dir($build)) {
    exec('rm -rf ' . escapeshellarg($build));
}
mkdir($build, 0o777, true);
exec(sprintf('cp -a %s/. %s', escapeshellarg($src), escapeshellarg($build)), $o, $rc);
if ($rc !== 0) {
    fwrite(STDERR, "copy failed\n");
    exit(1);
}
exec(sprintf('chmod -R u+w %s', escapeshellarg($build)));

$ok = $failed = 0;
$warnings_all = [];
$failures = [];
$it = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($build, FilesystemIterator::SKIP_DOTS));
foreach ($it as $file) {
    if (!$file->isFile() || !in_array($file->getExtension(), $exts, true)) {
        continue;
    }
    $path = $file->getPathname();
    $rel = substr($path, strlen($build) + 1);
    try {
        $warnings = null;
        file_put_contents($path, Concolic\Instrument::source(file_get_contents($path), $targets, $rel, null, $warnings));
        foreach ((array) $warnings as $w) {
            $warnings_all[] = "{$rel}: {$w}";
        }
        $ok++;
    } catch (Throwable $e) {
        $failed++;
        $failures[] = "{$rel}: {$e->getMessage()}";
        fwrite(STDERR, "  [warn] {$rel}: {$e->getMessage()}\n");
    }
}
$report = ['engine' => 'v2', 'instrumented' => $ok, 'failed' => $failed, 'warnings' => $warnings_all,
    'targets' => array_keys($targets), 'failures' => $failures];
echo json_encode($report, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES), "\n";
