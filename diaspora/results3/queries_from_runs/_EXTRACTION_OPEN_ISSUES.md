# Extraction — open issues (parked for future investigation)

Parked 2026-09-09. NOT worked on: these are EXTRACTOR-stage issues, downstream
of the concolic runs. They do not affect any engine `complete: true` claim.
Recorded here so they are not rediscovered from scratch.

## E11 — will_paginate COUNT dropped from conversations_index's shipped policy

**Status: parser FIXED, policy NOT re-extracted.** `conversations_index.sql`
on disk is still the pre-fix 58-view policy and is missing the pagination
COUNT views. Re-extract when someone picks this up.

Evidence, already on disk in `_summary_conversations_index.json`:

    n_queries_final = 58     errors = 21037     unparseable = 21037
    e.g. "unparseable note on SYM_RESULT_ActiveRecord__Calculations_count_1:
          SELECT COUNT(*) FROM (SELECT DISTINCT "conversation_v..."

`_primary_table` (src/queries_from_runs/transform.py) returned None for a
subquery FROM, so transform.py:242-251 appended an error and `continue`d,
dropping the statement 21,037 times. Fix (descend into the subquery) is
committed; the re-extraction is not done.

### Why `complete: true` did not cover this — the part worth remembering

Exploration and extraction are DIFFERENT STAGES and completeness only
certifies the first. The engine computes `complete` from PATH CONDITIONS and
never looks at SQL text. The statement was observed 21,037 times, exploration
genuinely was complete, and the extractor discarded the statement afterwards.
So the completeness claim was TRUE and the policy was still incomplete.

Three things let it through, all still worth fixing:

1. **No invariant tied observed statements to emitted views.** Nothing asserts
   that every distinct NOTE in the corpus reaches at least one view.
   Extraction is not required to be surjective onto what was observed.
2. **The drop was recorded, not raised.** `errors=errors` went into
   `EndpointSummary` -> summary JSON. A 21,037-count field printed nothing and
   blocked nothing.
3. **The label misled.** "unparseable note" — but sqlglot parsed it FINE; it
   was rejected later at TABLE RESOLUTION. The field read like a parser edge
   case on malformed input rather than "a statement the app really issues was
   deleted from this policy".

RUNBOOK rule P turned on itself: the RED check that catches this is dated
2026-09-09 and was written BECAUSE of E11 — residue found later means the
check was missing too.

## Extractors still lacking the E11 RED check

`_extract_posts_show_streaming.py` (dated 2026-08-19) collects `errors` but
does NOT fail on non-empty unparseable notes. posts_show has not been
extracted yet, so it would close with the same blind spot. The other three
(`comments_index`, `conversations_index`, `people_show`) have the check.

## Method-level issue (from _REFERENCE_COMPARISON_20260908.md)

Extracted policies are STATEMENT-level; the reference is REVEAL-level. A
consumer treating an extracted policy as access control is over-permissive
wherever the app over-fetches and filters in Ruby (q35).

## R1 — bind-rotation repair was unsound with symbolic binds — **CLOSED 2026-09-10**

`_repair_rotation` rotated only slots whose RHS was a LITERAL, so a `$$(...)`
bind (and every element of an `IN` list) was not counted as a slot and every
value landed one place off — `posts.author_id = 'Reshare'` on 1 246 of
people_stream's 1 248 views: the author restriction detached from the
principal, an over-permission of the E5 class.

Fixed in `src/queries_from_runs/transform.py`: the rotation is applied only
when EXACTLY ONE rotation is admissible under a slot/value type check (bind
types come from the column the bind's NAME carries); otherwise nothing is
rotated and the note is flagged `bind-rotation-UNRESOLVED`. Six-corpus
differential: **only people_stream changes** (1 248 -> 107 views, 0 residue);
no closed endpoint's rendering moves, so no shipped policy carried a rotation
error. Full write-up, rule, tests and numbers:
`_ROTATION_FIX_20260910.md`.

STILL OPEN, found while fixing it (people_stream, DECLARED OPEN X1 in that
endpoint's POLICY_HEADER.txt): `SYM_PERSON_via_user_id` is emitted as an
unresolved `_SYM_...` placeholder. See X1 below — the diagnosis recorded here
on 2026-09-10 (that it is the current user's person and `_PERSON_ID_RE`
wrongly rejects it) was WRONG and is superseded.


## X1 — `SYM_PERSON_via_user_id` shipped as a placeholder — **PREMISE REFUTED, RULE FIXED 2026-09-10**

**The defect report was inverted.** X1 said `SYM_PERSON_via_user_id` is the
current user's person and that `_PERSON_ID_RE` (`^SYM_PERSON_[A-Za-z0-9]+_id$`)
wrongly rejects the underscore in `via_user`. It is **not** the current user's
person. The runtime has two Person mint sites: `symbolic_user(tag)` ->
`SYM_PERSON_<tag>`, attached to the built current user with a SINGLETON method
(the principal), and `UserSymPersonAssociation#person` -> the FIXED name
`SYM_PERSON_via_user`, `prepend`-ed on the User CLASS. A singleton beats a
prepended module, so the second **never fires for the signed-in user**. On
people_stream it fires for exactly one row — the one
`User.find_by_username(params[:username])` returned, i.e. **the VIEWED
person** (measured: 211/211 dumps that mint it have
`Core::ClassMethods.find_by` as the immediately preceding `symbolic_call`; 64
of those dumps are ANONYMOUS runs with no principal at all; the symbol's own
`owner_id` is a free variable). `Person.find_from_guid_or_username` and
`Stream::Person#posts` in the app source say the same thing.

Binding it to `people.owner_id = _MY_UID` would have shipped a **strictly
narrower** predicate than the app enforces — "only my own posts" where the
endpoint reveals any named person's — a policy that under-claims the reveal.
The old regex reached the right outcome for the wrong reason (an underscore);
a `User#person` mint tagged without one (`SYM_PERSON_viauser_id`) would have
been resolved to the principal join silently, which a new test now pins.

**Fixed in `src/queries_from_runs/transform.py`:** the principal join is now
decided by MINT SITE, not name shape —
`RunTransformer.is_principal_person`, with two independent vetoes (the
`via_user` name, and the `User#person` mint note the runtime already writes
into `symbolic_vars`) ahead of the unchanged `_PERSON_ID_RE` shape test. A
`SYM_PERSON_*` bind that is not the principal stays a placeholder and is
flagged `non-principal-person-bind`; `_extract_people_stream_streaming.py`
prints a DECLARE block naming those views.

**Six-corpus differential: ZERO views change anywhere** — exhaustively over
all 320 746 dumps by construction (four corpora contain no `SYM_PERSON_*` name
at all; posts_show contains only the principal-shaped `SYM_PERSON_PO_id`), and
empirically on 3 000 seeded random dumps per corpus (people_stream in full).
people_stream's dry-run `.sql` is byte-identical: 107 views, 0 unparseable, 0
rotation residue, the same 3 placeholder families.

**STILL OPEN, and it is a RUNTIME issue.** The mint uses one fixed name for
every User row it is called on, with nothing in the dump linking it to the
producing query, so it cannot be resolved to a join from the dump alone.
Renaming the mint is `targets.rb` — Rule T, the shared boundary. Until then
people_stream's 35 views carrying it are DECLARED OPEN, not shipped as access
control. Full write-up, rule, tests and numbers:
`_X1_PERSON_ID_FIX_20260910.md`.


## E12 — app-specific data in `src/queries_from_runs` — **CLOSED 2026-09-11**

Parked 2026-09-11 by the subsume refactor, closed the same day by
`_E12_APP_AGNOSTIC_20260911.md`. Every row of the inventory below moved to the
app config; `grep -ri diaspora src/queries_from_runs --include='*.py'` now
returns exactly one line, the rule test's own pattern.

| moved | to |
|---|---|
| `schema.py` `DEFAULT_SCHEMA_RB`, `DEFAULT_FK_TXT` | `schema.rails_schema_rb`, `schema.foreign_keys` (null ⇒ `subsume.foreign_keys`) |
| `schema.py` `person_ref_columns` seed + fallbacks | `principal.identity.{table,id_column,ref_fallback_columns}` (renamed `identity_ref_columns`, old name aliased) |
| `transform.py` `MY_UID`/`NOW` | `principal.uid_const`/`now_const` (module names kept as DEPRECATED aliases of the contract defaults, for `_blockaid_fold.py`) |
| `transform.py` `PINNED_PERSON_ID`/`PINNED_USER_GUID` | `principal.identity.pinned_id`/`pinned_owner_guid` |
| `transform.py` `_USER_ID_RE`/`_PERSON_ID_RE`/`_PERSON_BIND_RE`/`_PARAM_BIND_RE`/the two non-principal vetoes | `principal.binds.*` |
| `transform.py` `_IRREGULAR_PLURALS` | `inflections.irregular_plurals` |
| `transform.py` the `people.owner_id = _MY_UID` join | `principal.identity.table` + `principal_columns[identity.table]` + `uid_const` |
| `pcs.py` `SYM_USER_<tag>_id` → `_MY_UID` | `parse_pc(uid_pattern=…)`, rendered by the caller as `uid_const` |
| `diff.py`/`dump.py` CLI defaults | `cli.*`, else **exit 2** naming the flag — no `src/`-side path defaults remain |
| `__init__.py`, `plan.md`, `README.md`, `audits/*.py` prose | rewritten |
| `audits/identity_symbolicity_audit.py` hardcoded `users.id` + `user_id,owner_id,recipient_id` (NOT on the original list) | `principal.principal_table` + `principal_columns`, or `--principal-cols`; identical derived set |
| `audits/bind_resolution_audit.py` imported the removed regexes in a bare `try/except` (would have degraded silently) | `principal.binds`, with the config error named in its RED |

**Nothing moved in the output.** All 18 resolved values are identical to the
constants they replaced (the FK *path* differs; the two files are byte-
identical, sha256 `4090b76e…`), and the six-corpus old-vs-new differential is
**0 RUNS DIFFERING / 0 VIEWS DIFFERING** on every corpus. No shipped policy
changes; nothing to re-extract; no finding to escalate. X1's
principal-resolution conventions are unchanged in behaviour — the mint-site
vetoes are now *stated by the config*, and a new test pins that they still
fire.

**What this costs callers:** the package now REQUIRES an app config
(`--app-config PATH` / `QFR_APP_CONFIG`). Every existing driver-side caller
sets it itself; a new one that forgets gets a `ConfigError` naming the flag,
never a wrong policy. **An edit to `app.json`'s `principal` / `schema` /
`inflections` blocks is now an EXTRACTOR CHANGE** and needs the same corpus
differential a `transform.py` change needs;
`reports/diaspora/queries_config/validate_app_json.py` checks everything
`schema.rb` can confirm. `principal.binds` is coupled to `targets.rb` under
Rule T.

**Still open, deliberately:**

- `cli.reference_dir` is null (reference quarantined), so `diff.py` has no
  runnable default — by design.
- `transform.MY_UID` / `transform.NOW` survive as DEPRECATED module aliases of
  the contract's default constant names, so a driver-side importer
  (`_blockaid_fold.py`) does not break mid-flight. They are stale if a config
  overrides the constants. Remove them once `_blockaid_fold.py` reads the
  config itself.
- Twelve `*audits*.sh` chains inside ENDPOINT directories got a one-line
  `export QFR_APP_CONFIG=…` so they keep working — the only edits this work
  made inside endpoint directories, flagged for owner review in §8 of the
  write-up. If anyone later adds `identity_symbolicity_audit` or
  `bind_resolution_audit` to a `completion_config.json`'s `audit_cmds`, that
  config's `env` block needs the same key.


## E13 — diaspora named outside `queries_from_runs` — **INVENTORY ONLY, NOT FIXED**

Opened 2026-09-11 alongside E12's closure. Out of scope there:
`src/concolic_engine` and `src/ruby_runtime` were not to be touched, and the
end-to-end checker docs are a separate owner's.

**Good news first: every hit is PROSE — a comment, a docstring or a README.**
No executable path, constant or identifier in these trees names diaspora; the
one functional app path in the Ruby stack lives where it belongs, in the
driver-side `scripts/diaspora-concolic` (`DIASPORA_APP=…/apps/diaspora`,
line 19). So E13 is a documentation-generalisation job, not a refactor, and
nothing here can emit a wrong artifact.

| file:line | what |
|---|---|
| `src/ruby_runtime/concolic_harness.rb:3` | header comment "Diaspora concolic harness" |
| `src/ruby_runtime/concolic_harness.rb:7` | usage comment "from the diaspora app dir" |
| `src/ruby_runtime/completion_checker/concrete_run_probe.rb:9` | usage comment `scripts/diaspora-concolic` |
| `src/ruby_runtime/completion_checker/concrete_run_probe.rb:24` | comment example `coverage_filter: %r{apps/diaspora/(app\|lib)/}` |
| `src/ruby_runtime/completion_checker/mock_checker.rb:7` | usage comment `scripts/diaspora-concolic` |
| `src/ruby_runtime/completion_checker/shim_test_runner.rb:8` | usage comment `scripts/diaspora-concolic` |
| `src/ruby_runtime/completion_checker/README.md:4,17` | points at `reports/diaspora/docs/CHECKS.md`; `scripts/diaspora-concolic` in the run recipe |
| `src/end_to_end_completion_checker/README.md:24,25,27` | points at `reports/diaspora/tools/`, `reports/diaspora/trash/…` |
| `src/end_to_end_completion_checker/concrete/CONCRETE_CHECKER.md:32,44,45,61,100,101,113,132,133` | nine prose pointers: results3 layout, `_auth_boundary/BOUNDARY_POLICY.md`, `scripts/diaspora-concolic`, `docs/TARGET_FUNCTIONS.md`, `tools/note_fidelity_audit.py`, `docs/ADVERSARY_WINS.md` |
| `src/end_to_end_completion_checker/assumption/assumption_checker.py:10,11` | docstring example manifest with a diaspora `batch_dir` and runner |
| `src/end_to_end_completion_checker/mock/mock_note_check.py:44` | comment "the SQL-level differ now lives in reports/diaspora/tools/" |
| `src/concolic_engine/assumptions.py:39` | docstring: "In the diaspora experiment this is where ~64% …" (a measured claim, correctly attributed) |

Suggested treatment when someone picks it up: the `scripts/diaspora-concolic`
usage lines become `scripts/<app>-concolic`; the pointers into
`reports/diaspora/…` become `reports/<app>/…`; the measured claim in
`assumptions.py:39` should KEEP its attribution (a number measured on one app
must say which) — the rule is "no app-specific *input or behaviour* in src/",
not "no app may ever be named in a provenance note".

