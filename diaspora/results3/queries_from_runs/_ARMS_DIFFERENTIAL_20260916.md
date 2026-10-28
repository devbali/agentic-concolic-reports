# Ground-truth differential: the two extraction options (2026-09-16)

Both options are FLAGS, off by default, so each is a differential rather than a
one-way change:

* `--exclude-rejected` — drop runs that ended in one of the app config's
  `policy.rejecting_errors`. A request the application REFUSED did not serve
  its reads, so its queries are not part of the policy.
* `--two-query-cap N` — render a path condition comparing this statement's row
  to a row it does not read, by inlining the other row's producing query, but
  only if that costs at most N NEW relations. Over the cap the inlining is
  rolled back whole and the condition is counted as skipped. `0` disables it.

Fixed sample: 4,000 dumps per endpoint, seed 20260916, all six endpoints,
`--no-subsume` (syntactic subsumption only) in every arm, so the arms differ
only in the options.

## Statements and path-condition predicates

endpoint              | base               rej                cap2               both             
                      | stmts  PCkept/rend  stmts  PCkept/rend  stmts  PCkept/rend  stmts  PCkept/rend
-------------------------------------------------------------------------------------------------------
conversations_index   |   38      1/114       38      1/114      179    709/4174     179    709/4174  
comments_index        |   35     35/208       35     35/208       53     55/613       53     55/613   
notifications_index   |   77     11/531       77     11/531      103     15/1593     103     15/1593  
people_show           |   43     36/1807      43     36/1807      50    103/3025      50    103/3025  
people_stream         |   95     61/767       95     61/767       95     61/767       95     61/767   
posts_show            |  120     23/29       121     25/25       120     23/29       121     25/25    
-------------------------------------------------------------------------------------------------------
TOTAL                 |  408    167/3456     409    169/3452     600    966/10201    601    968/10197 

Runs excluded as REFUSED (--exclude-rejected), per 4,000-dump sample:
  conversations_index   0
  comments_index        0
  notifications_index   0
  people_show           0
  people_stream         0
  posts_show            516

Only posts_show raises a declared rejecting error at all; the other five
are unaffected, so --exclude-rejected costs them nothing and buys them nothing.

## Loadability — the gate (project's own loader, `tools/policy_loadability.py`)

########## ARM base
conversations_index.sql    written=  38  loadable=  38  unloadable=   0  100.00%
comments_index.sql         written=  35  loadable=  35  unloadable=   0  100.00%
notifications_index.sql    written=  77  loadable=  77  unloadable=   0  100.00%
people_show.sql            written=  43  loadable=  40  unloadable=   3   93.02%
people_stream.sql          written=  95  loadable=  74  unloadable=  21   77.89%
posts_show.sql             written= 120  loadable=  86  unloadable=  34   71.67%
TOTAL                      written= 408  loadable= 350  unloadable=  58   85.78%
########## ARM both
conversations_index.sql    written= 179  loadable= 168  unloadable=  11   93.85%
comments_index.sql         written=  53  loadable=  53  unloadable=   0  100.00%
notifications_index.sql    written= 103  loadable= 103  unloadable=   0  100.00%
people_show.sql            written=  50  loadable=  44  unloadable=   6   88.00%
people_stream.sql          written=  95  loadable=  74  unloadable=  21   77.89%
posts_show.sql             written= 121  loadable=  86  unloadable=  35   71.07%
TOTAL                      written= 601  loadable= 528  unloadable=  73   87.85%
########## ARM rej
conversations_index.sql    written=  38  loadable=  38  unloadable=   0  100.00%
comments_index.sql         written=  35  loadable=  35  unloadable=   0  100.00%
notifications_index.sql    written=  77  loadable=  77  unloadable=   0  100.00%
people_show.sql            written=  43  loadable=  40  unloadable=   3   93.02%
people_stream.sql          written=  95  loadable=  74  unloadable=  21   77.89%
posts_show.sql             written= 121  loadable=  86  unloadable=  35   71.07%
TOTAL                      written= 409  loadable= 350  unloadable=  59   85.57%
########## ARM cap2
conversations_index.sql    written= 179  loadable= 168  unloadable=  11   93.85%
comments_index.sql         written=  53  loadable=  53  unloadable=   0  100.00%
notifications_index.sql    written= 103  loadable= 103  unloadable=   0  100.00%
people_show.sql            written=  50  loadable=  44  unloadable=   6   88.00%
people_stream.sql          written=  95  loadable=  74  unloadable=  21   77.89%
posts_show.sql             written= 120  loadable=  86  unloadable=  34   71.67%
TOTAL                      written= 600  loadable= 528  unloadable=  72   88.00%
VERDICT_ARMLOAD_DONE

| arm | statements | loadable | rate |
|---|---:|---:|---:|
| base | 408 | 350 | 85.78 % |
| rej  | 409 | 350 | 85.57 % |
| cap2 | 600 | 528 | 88.00 % |
| both | 601 | 528 | 87.85 % |

The gate was "must not regress from 348/406 = 85.71 %". `both` is **87.85 %**,
and the absolute count of loadable statements rises 350 -> 528.

## Coverage proxy, base -> both (`tools/policy_coverage.py`)

**0 tables lost and 0 columns lost on every one of the six endpoints.**

## What each option bought

**`--exclude-rejected`**: only posts_show raises a declared rejecting error at
all (516 of 4,000 runs, 12.9 %); the other five are untouched. On posts_show it
does exactly what it was predicted to do — every rendered predicate now
survives the prune (25/25) where before a fifth of them did not (23/29) —
because the refused runs were the counter-observations that made them look
unconstraining. The absolute effect is small only because posts_show renders
just 29 PC predicates in the first place, which is a corpus defect (F8: 4,457
captured-exception notes), not an extraction one.

**`--two-query-cap 2`**: the large one. Statements 408 -> 600, predicates
surviving the prune 167 -> 966. conversations_index goes from 1 predicate
kept out of 114 rendered to 709 out of 4,174 — that endpoint's dominant
condition class is the Ruby-side participation check, and it is now rendered.

## Why a cap, and why 2

Without one this is unbounded. Measured on conversations_index at 400 dumps,
uncapped: 41 -> 224 statements, up to 14 tables each of repeated aliased copies
of one relation, loadability 100 % -> 83.9 %. Keying the inlining by the
producer (so several conditions naming the same recorded row share one
relation) is already what `inline_producer` does; a further merge of producers
with byte-identical recorded SQL recovered only 9 of those 224, because the
copies differ in their bind names. The cap is what makes it bounded, and it is
exact rather than estimated: the cost of an inline is measured BY DOING IT,
against a snapshot that is rolled back whole if the attempt is over budget.

## The caveat that ships in the header

With `--exclude-rejected` the policy describes the queries of requests that
were SERVED. A read performed on a path the application then rejected is
excluded, although the query WAS issued and the database DID return the row.
A reader concerned with data exposure rather than with granted access should
know that class is not covered. `build_endpoint_file` writes this into the
policy file itself whenever the option is on.

## The shipped result: full corpora, both options on (`_pcfold2.sql`)

| endpoint | statements | loadable | rate |
|---|---:|---:|---:|
| conversations_index | 190 | 190 | 100.00 % |
| comments_index | 54 | 54 | 100.00 % |
| notifications_index | 101 | 101 | 100.00 % |
| people_show | 50 | 44 | 88.00 % |
| people_stream | 95 | 74 | 77.89 % |
| posts_show | 121 | 86 | 71.07 % |
| **TOTAL** | **611** | **549** | **89.85 %** |

Against the two earlier points: the original baseline was 374/442 = 84.62 %,
the PC-fold-without-options arm 348/406 = 85.71 %. Coverage proxy from that
arm to this one: **0 tables and 0 columns lost** on all six.

conversations_index is 100 % loadable at 190 statements, better than the
93.85 % its 4,000-dump sample showed at 179 — the full corpus gives the
pruning rule more counter-observations, so fewer half-constrained variants
survive to be emitted.
