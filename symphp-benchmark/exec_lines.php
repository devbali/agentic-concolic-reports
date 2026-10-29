<?php

/**
 * usage: php exec_lines.php <app-src> [php,inc]   (the PHP source extensions; default php)
 *
 * The coverage DENOMINATOR: per file, the start line of every statement that
 * is not a pure declaration, a no-op or inline HTML -- the paper's method
 * (PHP-Parser over the application's source), independent of either tool.
 */

$runtime = getenv('ACE_PHP_RUNTIME') ?: dirname(__DIR__, 2) . '/agentic_concolic_engine/runtimes/php_runtime';
require_once $runtime . '/vendor/autoload.php';

use PhpParser\{Node, NodeTraverser, NodeVisitorAbstract, ParserFactory};

$root = rtrim($argv[1], '/');
$exts = explode(',', $argv[2] ?? 'php');
$parser = (new ParserFactory())->createForHostVersion();
$parser74 = (new ParserFactory())->createForVersion(PhpParser\PhpVersion::fromComponents(7, 4));
$out = [];
$it = new RecursiveIteratorIterator(new RecursiveDirectoryIterator($root, FilesystemIterator::SKIP_DOTS));
foreach ($it as $f) {
    if (!in_array($f->getExtension(), $exts, true)) {
        continue;
    }
    $visitor = new class extends NodeVisitorAbstract {
        public array $lines = [];
        public function enterNode(Node $n)
        {
            if ($n instanceof Node\Stmt && !($n instanceof Node\Stmt\InlineHTML || $n instanceof Node\Stmt\Nop
                || $n instanceof Node\Stmt\Function_ || $n instanceof Node\Stmt\ClassLike
                || $n instanceof Node\Stmt\Declare_ || $n instanceof Node\Stmt\Else_)) {
                $this->lines[$n->getStartLine()] = true;
            }
            return null;
        }
    };
    $t = new NodeTraverser();
    $t->addVisitor($visitor);
    $code = @file_get_contents($f->getPathname());
    if ($code === false) {
        continue;                    // e.g. a dangling symlink (HSM's `doctor/.#search.php`)
    }
    try {
        $stmts = $parser->parse($code);
    } catch (PhpParser\Error $err) {
        // PHP 7-only syntax (`$s{0}`, ...): parse as 7.4, the version the apps target.
        // A file neither parser reads is left out of the denominator.
        try {
            $stmts = $parser74->parse($code);
        } catch (PhpParser\Error $err2) {
            fwrite(STDERR, "unparsable: {$f->getPathname()}\n");
            continue;
        }
    }
    $t->traverse($stmts);
    $lines = array_keys($visitor->lines);
    sort($lines);
    $out[substr($f->getPathname(), strlen($root) + 1)] = $lines;
}
ksort($out);
echo json_encode($out), "\n";
