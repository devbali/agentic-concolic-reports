<?php

/**
 * PHP 7.4 functions that PHP 8 REMOVED, defined for ACE's PHP 8.2 runs when the request asks for
 * PHP 7 compatibility (flags.php7Compare, i.e. drive.py --php7compat). Each behaves as 7.4's did
 * for the calls the benchmark apps make (WordPress 4.7's wp_magic_quotes(), ...). The judge
 * replays the unmodified app on a real 7.4, where these are the built-ins.
 *
 * Harness-level only: nothing in the app is changed, and an app that never calls them is not
 * affected (except that function_exists() now answers true for them).
 */

if (!function_exists('get_magic_quotes_gpc')) {
    function get_magic_quotes_gpc(): bool
    {
        return false;                 // 7.4: always false (magic quotes were removed in 5.4)
    }
}

if (!function_exists('get_magic_quotes_runtime')) {
    function get_magic_quotes_runtime(): bool
    {
        return false;
    }
}

if (!function_exists('each')) {
    /** 7.x each(): the current pair as [1 => v, 'value' => v, 0 => k, 'key' => k], then advance. */
    function each(array &$array): array|false
    {
        $key = key($array);
        if ($key === null) {
            return false;
        }
        $value = current($array);
        next($array);
        return [1 => $value, 'value' => $value, 0 => $key, 'key' => $key];
    }
}

if (!function_exists('create_function')) {
    /** 7.x create_function(): an anonymous function from argument and body source. */
    function create_function(string $args, string $code): string
    {
        static $n = 0;
        $name = "__ace_lambda_" . (++$n);
        eval("function {$name}({$args}) { {$code} }");
        return $name;
    }
}
