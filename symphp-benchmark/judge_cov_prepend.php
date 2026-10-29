<?php
/**
 * COVERAGE-ONLY prepend for the judge's Xdebug pass (judge.py --coverage xdebug).
 *
 * Lives outside every app's docroot and is passed with `-d auto_prepend_file`
 * only on the coverage pass, never on a fault replay. It starts Xdebug's line
 * collector and, at shutdown (which an app's `exit` still reaches), writes the
 * executed lines to $ACE_COV_OUT. It touches no superglobal, no output and no
 * app state. Xdebug 3 has no ini-only switch that starts the collector.
 */
if (function_exists('xdebug_start_code_coverage') && getenv('ACE_COV_OUT')) {
    xdebug_start_code_coverage();
    register_shutdown_function(static function (): void {
        $cov = xdebug_get_code_coverage();
        xdebug_stop_code_coverage(false);
        $out = [];
        foreach ($cov as $file => $lines) {
            $out[$file] = array_keys(array_filter($lines, static fn ($v) => $v === 1));
        }
        file_put_contents(getenv('ACE_COV_OUT'), json_encode($out));
    });
}
