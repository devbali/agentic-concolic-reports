<?php

/**
 * Drive `Contact::can_view_paper` with `rights()` COMPUTING, not pre-empted.
 *
 * The sibling harness in `../hotcrp-typed-policies/` sets `_last_rights`,
 * `_last_rights_paper` and `_last_rights_version` by reflection so `rights()`
 * takes its cache-hit branch -- which makes `ciflags` a free symbolic input
 * and means no query is ever issued. That is why 95/95 of its paths carry no
 * SQL and why 33 of its 40 policy atoms are refused by the domain renderer:
 * they all test a flag word that exists only in process.
 *
 * This harness does the opposite. It boots HotCRP far enough for `rights()`
 * to run for real -- `Conf` with `$connect = false`, so still no database --
 * lets it reach `PaperContactInfo::load_into`, intercepts the query there,
 * and supplies conflict and review rows whose COLUMNS are symbolic. `ciflags`
 * is then a derived term over `conflictType` / `rflags` / `reviewType`, which
 * are real columns, and the policy should be renderable as SQL.
 *
 * Reads the same JSON-on-stdin protocol as the sibling, so `run_concolic.py`'s
 * exploration loop works unchanged.
 */

/** Stands in for mysqli_result: HotCRP iterates nearly every result. */
final class ConcolicResult implements Iterator
{
    public $num_rows;
    private $rows;
    private $i = 0;

    public function __construct(array $rows = [])
    {
        $this->rows = array_values($rows);
        $this->num_rows = count($this->rows);
    }

    public function fetch_row()
    {
        $r = $this->rows[$this->i] ?? null;
        if ($r === null) {
            return null;
        }
        $this->i++;
        return array_values($r);
    }

    public function fetch_assoc()
    {
        $r = $this->rows[$this->i] ?? null;
        if ($r === null) {
            return null;
        }
        $this->i++;
        return $r;
    }

    public function fetch_object()
    {
        $r = $this->fetch_assoc();
        return $r === null ? null : (object) $r;
    }

    public function close() {}
    public function free() {}
    public function free_result() {}
    public function current(): mixed { return (object) $this->rows[$this->i]; }
    public function key(): mixed { return $this->i; }
    public function next(): void { $this->i++; }
    public function rewind(): void { $this->i = 0; }
    public function valid(): bool { return isset($this->rows[$this->i]); }
}

/** Stands in for Dbl's multi-result; load_into walks it with ->next(). */
final class ConcolicMultiResult
{
    private $results;
    private $i = 0;

    public function __construct(array $results)
    {
        $this->results = array_values($results);
    }

    public function next()
    {
        return $this->results[$this->i++] ?? false;
    }

    public function free() {}
    public function close() {}
}

$report = __DIR__;
$root = dirname($report, 2);
$runtime = $root . '/agentic_concolic_engine/runtimes/php_runtime';
$app = $root . '/apps/hotcrp';
$build = $report . '/build/hotcrp';

require_once $runtime . '/vendor/autoload.php';
require_once $runtime . '/src/autoload.php';

/**
 * An instrumented COPY of the tree.
 *
 * HotCRP resolves classes through its own autoloader, so there is no import
 * hook to redirect: the only way to make it load instrumented code is to
 * point it at an instrumented tree. Everything under src/ and lib/ is
 * instrumented, not just the files on the expected path -- a symbolic value
 * reaching an uninstrumented file is the one failure this design cannot make
 * loud, since `if ($sym)` on an object is silently true.
 */
function build_tree(string $app, string $build, string $runtime): void
{
    $stamp = $build . '/.stamp';
    $fingerprint = hash('sha256',
        file_get_contents($runtime . '/src/Instrument.php') .
        file_get_contents($runtime . '/src/InstrumentVisitor.php'));
    if (is_file($stamp) && trim(file_get_contents($stamp)) === $fingerprint) {
        return;
    }

    fwrite(STDERR, "building instrumented HotCRP …\n");
    if (is_dir($build)) {
        exec('rm -rf ' . escapeshellarg($build));
    }
    mkdir($build, 0o777, true);
    exec(sprintf('(cd %s && tar --exclude=.git --exclude=node_modules -cf - .) | tar -xf - -C %s',
        escapeshellarg($app), escapeshellarg($build)), $o, $rc);
    if ($rc !== 0) {
        throw new RuntimeException("could not copy the HotCRP tree (exit {$rc})");
    }

    // Every call HotCRP makes to its database layer. The one that matters for
    // rights() is Dbl::multi_qe, which load_into uses for its
    // PaperConflict/PaperReview pair.
    $targets = array_fill_keys([
        'qe', 'qx', 'ql', 'qe_raw', 'q', 'multi_qe', 'Dbl::multi_qe',
        'Dbl::multi_q', 'fetch_ivalue', 'fetch_first_row', 'fetch_rows',
        'fetch_value', 'fetch_objects', 'fetch_first_object',
    ], true);

    $ok = $failed = 0;
    foreach (['src', 'lib'] as $sub) {
        $it = new RecursiveIteratorIterator(new RecursiveDirectoryIterator("{$build}/{$sub}"));
        foreach ($it as $file) {
            if (!$file->isFile() || $file->getExtension() !== 'php') {
                continue;
            }
            $path = $file->getPathname();
            try {
                $warnings = null;
                $source = Concolic\Instrument::source(file_get_contents($path), $targets,
                    str_replace($build . '/', 'apps/hotcrp/', $path), null, $warnings);
                file_put_contents($path, $source);
                $ok++;
            } catch (\Throwable $e) {
                $failed++;
                fwrite(STDERR, "  [warn] {$path}: {$e->getMessage()}\n");
            }
        }
    }
    fwrite(STDERR, "instrumented {$ok} files" . ($failed ? ", {$failed} failed" : "") . "\n");
    file_put_contents($stamp, $fingerprint);
}

build_tree($app, $build, $runtime);

define("HOTCRP_TESTHARNESS", true);
$Opt = [
    "dbName" => "hotcrp_concolic", "dbUser" => "concolic", "dbPassword" => "",
    "dbHost" => "localhost", "loaded" => true, "include" => [],
    "shortName" => "concolic", "longName" => "concolic",
];
require_once $build . '/src/init.php';

/**
 * CONFERENCE CONFIGURATION, MADE SYMBOLIC.
 *
 * `rights()` asks the Conf ten questions, and with a default Conf every one
 * of them answered the same way on every run. They were not missing
 * coverage -- they were never DECISIONS, so nothing demanded them. The
 * measured universe was seven row columns while `rights()` has ~71 branch
 * points; this class is what closes part of that gap.
 *
 * WHY A SUBCLASS AND NOT A TARGET. A target intercepts a boundary the
 * HARNESS calls. These are calls the APPLICATION makes on an object the
 * harness owns, so overriding the method is the direct instrument -- and
 * none of them is `final` or carries a return type, so the override is
 * legal PHP rather than a reflection trick.
 *
 * WHAT IS NOT MODELLED. Each override returns one free symbol, so a run
 * cannot observe that (say) `check_tracks(VIEW)` and
 * `check_track_view_sensitivity()` are both computed from the same track
 * settings and are therefore correlated. That makes the symbol set WIDER
 * than the real configuration space, which over-reports reachable
 * combinations rather than under-reporting them -- the safe direction, and
 * the same direction the engine's other relaxations take.
 */
final class ConcolicConf extends Conf {
    /** The current run's symbolic inputs; set by `invoke`. */
    public array $sym = [];
    /**
     * Whether this run makes the conference symbolic at all.
     *
     * BOTH ARMS STAY REPRODUCIBLE, because the comparison between them is
     * the result: symbolic settings roughly double the decisions and take
     * renderable views to zero, and a reader can only check that if either
     * corpus can be regenerated. Off means every method below defers to the
     * real Conf, which is what this harness did before.
     */
    public bool $symbolic = true;

    private function ask(string $name, callable $concrete) {
        if (!$this->symbolic) {
            return $concrete();
        }
        // Absent means the driver did not seed it, and a silent concrete
        // answer is exactly the failure this project exists to prevent.
        if (!array_key_exists($name, $this->sym)) {
            throw new \RuntimeException("conference setting '{$name}' was not seeded");
        }
        return $this->sym[$name];
    }

    function has_tracks() {
        return $this->ask('has_tracks', fn() => parent::has_tracks());
    }
    function check_track_view_sensitivity() {
        return $this->ask('track_view_sensitive',
                          fn() => parent::check_track_view_sensitivity());
    }
    function allow_conflicted_pc_view() {
        return $this->ask('allow_conflicted_pc_view',
                          fn() => parent::allow_conflicted_pc_view());
    }
    function time_reviewer_view_decision($pc, $conflicted) {
        return $this->ask('time_reviewer_view_decision',
                          fn() => parent::time_reviewer_view_decision($pc, $conflicted));
    }

    // The RIGHT distinguishes these: VIEW and VIEWPDF are separate track
    // permissions in HotCRP, and collapsing them to one symbol would make
    // two independent configuration choices look like one.
    function check_tracks(PaperInfo $prow, Contact $user, $right) {
        return $this->ask($right === Track::VIEWPDF ? 'track_viewpdf' : 'track_view',
                          fn() => parent::check_tracks($prow, $user, $right));
    }

    // Likewise `$pdf`: `time_pc_view($prow, false)` and `(…, true)` are two
    // different questions and `rights()` asks both.
    function time_pc_view(PaperInfo $prow, $pdf) {
        return $this->ask($pdf ? 'time_pc_view_pdf' : 'time_pc_view',
                          fn() => parent::time_pc_view($prow, $pdf));
    }

    // ONLY the two names `rights()` reads. `setting()` is called throughout
    // boot and by code far outside this analysis; answering all of them
    // symbolically would put symbols in branches that have nothing to do
    // with the permission question, and would most likely not boot.
    function setting($name) {
        return match ($name) {
            'viewrev_ext' => $this->ask('setting_viewrev_ext',
                                        fn() => parent::setting($name)),
            'pc_confpdf' => $this->ask('setting_pc_confpdf',
                                       fn() => parent::setting($name)),
            default => parent::setting($name),
        };
    }
}

// `$connect = false`: Conf keeps a null dblink and refreshes its settings
// instead of loading them, so the whole run happens with no database and
// every query is intercepted.
$CONF = new ConcolicConf($Opt, false);
Contact::$main_user = null;

/** The requester's id. Concrete: PHP coerces array keys, and HotCRP caches by id. */
const MY_UID = 10000001;
/** The paper under test. Concrete for the same reason. */
const PAPER_ID = 9000007;

/**
 * One run: build the user and paper, then ask the permission question.
 *
 * `ciflags` is NOT seeded. `rights()` computes it from whatever
 * `load_into` returns, which is what makes the resulting condition a
 * predicate over columns rather than over a flag word.
 */
function set_private($object, string $name, $value): void
{
    (new ReflectionProperty($object, $name))->setValue($object, $value);
}

function invoke(Concolic\Runtime $rt, string $entry, array $v)
{
    global $CONF;

    // Hand this run's symbols to the Conf before anything asks it a question.
    // A seed set with no conference keys IS the row-data arm: nothing to
    // answer symbolically, so the real Conf answers.
    $CONF->sym = $v;
    $CONF->symbolic = array_key_exists('has_tracks', $v);

    $user = Contact::make_email($CONF, 'user@example.edu');
    $user->contactId = $user->contactXid = MY_UID;
    // SEED THE COLUMN, NOT THE DERIVED BOOLEANS. `ContactInfo.roles` is a
    // real column; `isPC` and `privChair` are masks HotCRP takes off it.
    // Seeding the booleans directly made the extracted condition name
    // `isPC`, which no table has. Taking the masks here records the
    // comparison against `roles` instead -- the same thing Contact's own
    // constructor does -- so the condition names something a view can select
    // on. The result is a concrete bool, which is correct: the BRANCH is the
    // decision, and it has been recorded.
    $user->roles = $v['roles'];
    $user->isPC = __cmp(__bits($v['roles'], '&', Contact::ROLE_PCLIKE), '!==', 0);
    $user->privChair = __cmp(__bits($v['roles'], '&', Contact::ROLE_CHAIR), '!==', 0);

    $prow = PaperInfo::make_placeholder($CONF, PAPER_ID);
    $prow->timeSubmitted = $v['timeSubmitted'];
    $prow->timeWithdrawn = $v['timeWithdrawn'];
    $prow->outcome = $v['outcome'];
    $prow->leadContactId = 0;
    $prow->managerContactId = 0;
    $prow->shepherdContactId = 0;

    // SEED THE ROW, NOT THE FLAGS. `PaperContactInfo::load_into` is what
    // turns a PaperConflict/PaperReview row into these three fields, and it
    // is skipped here -- `optional_contact_info` returns an entry already in
    // `_contact_info` once `_rights_version` matches. What is NOT skipped is
    // `rights()`, which still computes `ciflags` and `scope_bits` from them.
    //
    // That is the whole point of this harness. The sibling seeds `ciflags`
    // directly, so every condition names a flag word that exists only in
    // process; here the conditions should name `conflictType`, `reviewType`
    // and `rflags`, which are columns of real tables.
    $ci = new PaperContactInfo(PAPER_ID, MY_UID);
    $ci->conflictType = $v['conflictType'];
    $ci->reviewType = $v['reviewType'];
    $ci->rflags = $v['rflags'];
    set_private($prow, '_contact_info', [MY_UID => $ci]);
    set_private($prow, '_rights_version',
        (new ReflectionProperty(Contact::class, 'rights_version'))->getValue());

    [$owner, $method] = explode('::', $entry);

    if ($owner === 'Contact') {
        return match ($method) {
            'can_view_paper', 'can_view_pdf' => $user->$method($prow),
            'can_view_comment_tags' => $user->$method($prow,
                (new ReflectionClass(CommentInfo::class))->newInstanceWithoutConstructor()),
            default => $user->$method($prow),
        };
    }

    // A PaperContactInfo predicate is a test of `ciflags`, so it is only
    // interesting once `rights()` has COMPUTED that word. Calling the
    // predicate on the seeded object alone would test a zero.
    //
    // `rights()` is private, so it is reached by reflection -- the same
    // instrument the sibling harness uses, pointed the other way: there it
    // pre-empts the computation, here it performs it. Its branches land in
    // the trace, which is correct: they ARE the policy that decides the flag
    // the predicate then tests.
    $rights = (new ReflectionMethod(Contact::class, 'rights'));
    $computed = $rights->invoke($user, $prow);

    return match ($method) {
        'can_view' => $computed->can_view($v['pdf']),
        'scope_allows' => $computed->scope_allows($v['bits']),
        default => $computed->$method(),
    };
}

$requests = json_decode(stream_get_contents(STDIN), true, 512, JSON_THROW_ON_ERROR);
$output = [];

foreach ($requests as $request) {
    $rt = new Concolic\Runtime();
    $allowed = null;

    $dump = $rt->run(function (array $v) use ($rt, $request, &$allowed) {
        // NO QUERY TARGETS ARE DECLARED. With the contact info seeded,
        // nothing on this path should reach the database layer at all -- and
        // if something does, the undeclared-target error is the evidence,
        // which is better than a mock quietly answering for it.
        // The ACCESS. `build_policy` anchors an atom on an access event, so
        // a run that records only path conditions yields no policy at all --
        // which is exactly what happened the first time this driver ran. It
        // is a marker for "the gate let this through", not an observed read;
        // the real reads are the ones `rights()` would have issued, and this
        // harness seeds their result rather than mocking the query.
        $access = $rt->target('HotCRP#authorized_operation', 'target_function',
                              'bool', fn() => true);

        $allowed = __truthy(invoke($rt, $request['entry'], $v));
        if ($allowed) {
            $access($v);
        }
    // `Conf::setting()` really does return `?int` -- `$this->settings[$name]
    // ?? null` -- and HotCRP reads it as `(… ?? 0)`. Declaring the symbol
    // nullable is what lets that `??` be a recorded decision instead of a
    // malformed atom: a non-nullable int compared to null is rule 7.
    }, $request['seeds'], $request['label'], ['apps/hotcrp/'],
       ['setting_viewrev_ext' => 'int?', 'setting_pc_confpdf' => 'int?']);

    $dump['script'] = file_get_contents(__FILE__);
    $output[] = ['dump' => $dump, 'allowed' => $allowed];
}

echo json_encode($output, JSON_THROW_ON_ERROR | JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
