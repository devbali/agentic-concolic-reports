# CONCRETE CHECKER — an adversarial sub-agent, not a script

**Claim under test:** the batch's corpus of dumps is complete — every
target-function call the real endpoint can make, in every shape, appears
as a corpus event. `complete: true` from the completion engine
(`concolic_engine/completion.py`) is what this check attacks.

**Why a sub-agent:** the scripted checks in this directory (audits, mock
note check, assumption checker) can only examine what the engine chose to
look at. Only a reader of the real code can go after what it did not. The
scripts remain the instruments and the judge; the adversary supplies
scenarios, never verdicts.

**Currency:** target-function calls of a REAL run (booted app, sqlite
fixtures, real session, no mocks) — captured frame-tagged by
`reports/diaspora/tools/concrete_checker/concrete_run_probe.rb`, judged by
`mock_note_check.py` (real statements vs corpus notes per target); the
real run's depth-0 target-call list (`concrete_run.json` → `target_calls`)
is compared against the corpus's `symbolic_call` targets by you.

**Win = finding:** a call shape the corpus lacks is, by definition, Class S
(swallowed / mis-shaped evidence) or Class B (unexplored branch). It goes
to the batch agent as BLOCKING with the scenario attached; `complete` is
void until the shape is in the corpus AND the check that catches its class
exists. Re-run after every repair it causes.

---

## Brief (given to the adversary verbatim, with <ENDPOINT> filled in)

You are the adversary for endpoint `<ENDPOINT>` (batch
`reports/diaspora/results3/<ENDPOINT>/`). The batch agent claims the
corpus of dumps (`dump_*.json`) is complete: every target-function call the
real endpoint can make, in every shape, appears as a corpus event. Your
job is to prove it wrong with a REAL run.

## Scope

The adversary attacks the DECLARED ENTRYPOINT: the controller action
post-authentication, with the principal instantiated concretely but within
its symbolic declaration (any fixture row for the symbolic user; never a
login flow). Stages above the entrypoint — session/cookie authentication and
its hooks — are OUT OF SCOPE for endpoint wins: a statement issued by them is
recorded in the project's shared auth-boundary policy (for diaspora:
`reports/diaspora/results3/_auth_boundary/BOUNDARY_POLICY.md`), not reported
as an endpoint win. (Scope ruling by the user, 2026-08-31, after the
conversations rounds 4–6 boundary excursion.)

## Rules
- Real app only: `reports/diaspora/tools/concrete_checker/concrete_env.rb` (sqlite via JDBC, app schema), fixture
  ROWS by `insert`, real Devise session, real controller dispatch, real
  templates. **No mocks, no stubs, no monkey-patches of app code, no
  changes under `src/` or the app.** You may only add fixture data and
  request parameters/headers/session.
- No reference policy exists; do not look for one (never read anything
  named REFERENCE/diff_*/OURS_/SUBSET_/_progress.json/unknown.txt, never
  `git checkout`/`git show` under `ruby_examples/dse-apps/policies`).
- Do not edit the batch's runner/targets/mocks. You report; the batch
  agent repairs.
- Ops: one JRuby at a time — `flock /tmp/concolic-slot.lock
  scripts/diaspora-concolic /abs/path/reports/diaspora/tools/concrete_checker/concrete_run_probe.rb /abs/path/<manifest>.rb`
  with `unset JAVA_TOOL_OPTIONS`, inside `systemd-run --user -p MemoryMax=4000M`.
  One scenario per manifest process.

## Method
1. Read the endpoint code path completely: controller action + filters,
   services/queries (`EvilQuery`, `*Service`, `Stream*`), model methods and
   scopes it touches, every view/partial/helper the action renders, the
   serializers/presenters for the JSON format. Enumerate every conditional
   and every association/finder/calculation call reachable from it.
2. Read the corpus's PC universe (`coverage_summary.json` nodes; the
   `pc_visibility` audit's mint table) and the corpus notes (statement
   shapes). Anything in step 1 with no PC and no note is a candidate.
3. Attack list (fixture states the seed universe tends not to express):
   empty / one / many rows where code branches on `size`/`any?`/`last`/
   pagination; nil foreign keys; unpersisted or missing associations;
   STI subclasses (StatusMessage/Reshare/Photo…); own vs shared-with vs
   public vs private visibility, guid-vs-id keys; blocked/ignored users,
   contacts vs non-contacts, aspects; mentions with a missing/unpersisted
   person; posts with photos/polls/locations/o-embed; unread counts;
   HTML vs JSON vs mobile formats; every `params[...]` the action reads;
   every helper branch in the partials (camo/image proxies, timeago, link
   rendering).
4. For each scenario: write the manifest, run the probe, then judge with
   `python3 src/end_to_end_completion_checker/mock/mock_note_check.py <concrete_run.json> <batch> --aliases <batch>/concrete_aliases.json`
   and compare the run's depth-0 `target_calls` with the corpus targets. A depth-0 target call or a real statement
   shape with no corpus counterpart is a WIN.
   **Entrypoint verification (required for every win):** before reporting,
   prove the novel statement was issued by EXACTLY the declared entrypoint —
   the run's trace must show it inside the entrypoint invocation (the
   action's frame, after the principal is installed), with the principal a
   concrete instantiation of the symbolic declaration. A statement issued
   above the entrypoint (authentication, middleware, session plumbing) is
   NOT a win — record it in the shared boundary policy instead. State this
   check's evidence (the frame/trace line) in the win's writeup; the
   coordinator rejects wins without it.
5. **Evidence fidelity, per target call.** The corpus note is the ONLY
   thing the policy sees. For every target-function call your real run
   makes, compare what the call actually did with the corpus note for that
   target — read the project's target doc (for diaspora:
   `reports/diaspora/docs/TARGET_FUNCTIONS.md`) for what each target
   must evidence. The note must be faithful in the details the policy
   inherits, not just in outline: for a data-access target that is the
   projection (named columns vs a whole row vs an existence bit vs an
   aggregate), the predicate columns and the ordering; for any other
   target, the arguments and effect the note claims. Every discrepancy is
   a finding: a wildcard note over a narrower real access over-approximates
   the policy; a row-read note over an aggregate misstates it; a note
   whose predicate set differs from the real call is a mis-shape (Class
   S). Also check the mock's RETURN against the real call's result kind
   (row / list / count / bool / nil) — a mock returning the wrong kind
   silently reshapes every downstream decision. Project-specific helpers
   may automate the comparison (diaspora: `reports/diaspora/tools/note_fidelity_audit.py`),
   but the judgment is yours and every discrepancy goes in the report.
6. Report every win with: scenario (fixtures + request), the novel call
   shape verbatim, the code line that issues it, and which branch/decision
   the corpus lacks (your Class S/B hypothesis). Report near-misses too
   (shapes that matched only via an alias or a nested frame).

## Deliverable

**Target-level vs endpoint-level (required).** For every win, say which it
is: TARGET-LEVEL if the cause lives in something all endpoints share (the
target boundary, the association/mock toolkit, a filter every controller
runs such as `set_locale` or `authenticate_user!`), ENDPOINT-LEVEL if it is
this action's own view or param. Target-level wins go into the PROPAGATION
MATRIX in `ADVERSARY_WINS.md` so the coordinator can apply them to every
batch — three separate adversaries paid for the same `Post.exists?` link
family before that table existed.

**Ledger (required).** Every win and every near-miss you report must also be
appended as a row to the project's central wins ledger — for diaspora:
`reports/diaspora/docs/ADVERSARY_WINS.md` — with endpoint, round+date,
class (S / B / S-with-B-cause), the shape or defect, the issuing code line,
and status `open`. Do not edit rows for earlier rounds except to move one you
personally re-verified from `repaired` to `verified` (a win is closed only by
a REAL run, never by a green script). If your round scores no wins, append a
line to the round log at the bottom saying so, with the scenario count.


`<batch>/ADVERSARY_REPORT.md`: scenarios tried (table), wins (blocking
findings), near-misses, and the branches you could not reach and why.
Your return message: the number of wins and the one-line shape of each.
