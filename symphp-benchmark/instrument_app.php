<?php

/**
 * usage: php instrument_app.php <app-src> <build-dir>
 *
 * Copies the application and instruments EVERY .php file in the copy, not
 * just the ones an expected path loads: a symbolic value reaching an
 * uninstrumented file is the one failure this design cannot make loud, since
 * `if ($sym)` on an object is silently true. A file the instrumentor cannot
 * rewrite is reported and left as it was.
 */

$runtime = getenv('ACE_PHP_RUNTIME') ?: dirname(__DIR__, 2) . '/agentic_concolic_engine/runtimes/php_runtime';
require_once $runtime . '/vendor/autoload.php';
require_once $runtime . '/src/autoload.php';

[$_, $src, $build] = $argv + [null, null, null];
if (!$src || !$build) {
    fwrite(STDERR, "usage: php instrument_app.php <app-src> <build-dir>\n");
    exit(2);
}

// The harness's SQL_SINKS, SHELL_SINKS and SHIMS, by name.
$targets = array_fill_keys([
    'mysqli_query', 'mysqli_real_query', 'mysqli_multi_query', 'mysql_query',
    'system', 'exec', 'shell_exec', 'passthru', 'popen', 'proc_open',
    'mysqli_connect', 'mysqli_connect_errno', 'mysqli_connect_error',
    'mysqli_select_db', 'mysqli_close', 'mysqli_error',
], true);

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
$it = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($build, FilesystemIterator::SKIP_DOTS));
foreach ($it as $file) {
    if (!$file->isFile() || $file->getExtension() !== 'php') {
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
        fwrite(STDERR, "  [warn] {$rel}: {$e->getMessage()}\n");
    }
}
echo json_encode(['instrumented' => $ok, 'failed' => $failed, 'warnings' => $warnings_all], JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES), "\n";
