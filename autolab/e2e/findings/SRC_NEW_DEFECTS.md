# Defects in `src_new/` found by the auto-lab e2e run

`src_new/` is not mine to edit, so each item is a write-up with its evidence,
its exact site, and what a fix would have to be.

**This file was regenerated on 2026-10-03.** The original (2026-09-26) was
deleted from `e2e/findings/` at some point on 2026-09-30, along with
`AUTOLAB_GAPS.md`, the `_round1/` archive and the round-2 `results/` and
`logs/` directories — not by this task, and I do not know by what. `REPORT.md`,
`VERDICT.md`, `INVENTORY.json`, `manifest.jsonl` and all 161 `runs/<id>/` dump
sets survived, so every item below is either **re-verified against the live
tree today** (marked RE-VERIFIED) or **re-derived from surviving artifacts**
(marked RE-DERIVED). Nothing here is quoted from memory alone; where an
original measurement is no longer backed by a surviving artifact, it says so.

Status key: **FIXED** = fixed in `src_new` since 2026-09-26. **OPEN** =
re-verified as still present today.

---

## S-6 — the SQL renderer classified every structured note as prose — **FIXED 2026-09-28**

**Was.** `domains/ruby_rails_sql/render.py:classify_note` took the first token
of the RAW note string. §4.1.1c's note is a `{"refs": …, "text": …}` envelope,
whose first token is `{"refs":`, so every structured note classified `prose`,
`is_expressible_as_select` was False, and the atom was excluded. The same file
already knew this: `_parse` (then at :477-482) said "§4.1.1c's note envelope is
a JSON document, so a regex over the raw string would hand sqlglot
`{"refs": ...}` … `bind_split` is the one sanctioned reader". The *builder* had
been taught to unwrap the envelope; the *capability predicate* that decides
whether the builder ever runs had not.

**Now (RE-VERIFIED today).** `classify_note` reads `_note_payload(note)` and
its docstring carries the fix and the date:

> THE FIRST TOKEN OF THE **PAYLOAD**, NOT OF THE RAW STRING (2026-09-28).
> §4.1.1c's note is a `{"text": …, "refs": {…}}` envelope, so the raw
> string's first token is `{"refs":` and every structured note classified
> `prose` — `supports()` routes through here, so no atom carrying an
> envelope was renderable and the domain emitted no views at all.

```
classify_note('SELECT "posts".* FROM "posts" WHERE id = ?')        -> select
classify_note('{"refs": {"p0": …}, "text": "SELECT …"}')           -> select   (was: prose)
```

**What it bought, MEASURED rather than projected.** The 161 round-2 dump sets
survived the deletion, so the Python half was re-run over **exactly the same
dumps**, no re-drive, isolating the `src_new` change
(`tools/repipe_only.py`, output in `results_s6fix/`):

| | 2026-09-26 | 2026-10-03 |
|---|---:|---:|
| SQL views rendered, total | 20 | **548** |
| endpoints rendering ≥1 view | 18 | **123** |
| unsupported atoms, total | 940 | **118** |
| atoms excluded *only* by the envelope misclassification | **822** | **0** |

940 − 118 = **822**, which is exactly the number the e2e pipeline's own
`atoms_lost_to_note_envelope` probe predicted on 2026-09-26 by re-asking the
same classifier with the payload unwrapped. The prediction and the recovery
agree to the atom. All 161 endpoints still pass every pipeline stage.

The note census is unchanged, as it must be — notes did not change: 862
`select`, 88 `write`, 30 `prose`, **0 absent**.

---

## S-1 — `SymbolicString#include?` records the Z3 `Contains` operands backwards — **OPEN**

**Site (RE-VERIFIED today).** `src_new/runtimes/ruby_runtime/string.rb:176-182`:

```ruby
def include?(substr)
  result = @value.include?(val_of(substr))
  rhs = substr.is_a?(SymbolicVar) && substr.respond_to?(:z3_expr) ? substr.z3_expr : z3_str_val(val_of(substr))
  expr = "Contains(#{rhs}, #{z3_expr})"      # <-- :179, unchanged
  record!(expr, "include?", taken: result)
  result
end
```

`rhs` is the **argument**, `z3_expr` the **receiver**. Ruby's
`receiver.include?(arg)` asks "does the receiver contain the argument"; Z3's
`Contains(a, b)` asserts "a contains b". The emitted term is the reverse.

**Not cosmetic — a soundness defect (RE-VERIFIED today):**

```
Contains("@", x) ∧ Length(x) == 5   ->  unsat
Contains(x, "@") ∧ Length(x) == 5   ->  sat
```

The inverted term makes an ordinary reachable branch look infeasible.

**Corroboration inside the same file.** The `split` machinery emits the two
operands in *opposite* orders on adjacent lines for the same pair —
`IndexOf(suffix, sep)` (haystack first, correct) one line from
`Contains(sep, suffix)` (needle first, the same inversion as :179).

**Fix.** `Contains(#{z3_expr}, #{rhs})` at :179, and the corresponding swap in
the three `split` sites. Whoever makes it must also decide what to do about
corpora recorded against the old spelling: a stored `Contains` term cannot be
re-oriented after the fact without knowing which side was the receiver.

---

## S-2 — `Contains(…)` is outside §7.2's sub-language, so the builder refuses the whole dump — **OPEN**

`dumps_to_policy/pc_expr.py` raises for any call-shaped term not in `_LEN` or
`_WRAP`; `dumps_to_policy/build.py` re-raises naming the run.

**Scope (RE-DERIVED from the surviving round-2 artifacts).** One endpoint,
`diaspora_federation_h_card_hcard` — but **8 of its 9 dumps**, not 1 of 2 as
the shakedown's `MAX_RUNS=2` showed. The surviving `INVENTORY.json` records
`built_from_dumps: 1`, `refused_dumps: 8` for it.

Honest resolutions: add `Contains` (and `IndexOf`, which `split` emits beside
it) to §7.2 and to `dumps_to_policy/predicate.py`'s term set; or have the
runtime record `String#include?` as something already in the sub-language —
which is not obviously available, since there is no length/equality encoding
of "contains" over a symbolic string.

**Harness mitigation, not a fix.** The e2e pipeline builds from every dump the
builder *accepts* and records the refused ones with the builder's own message,
so one unrepresentable term costs that endpoint eight dumps instead of its
whole policy.

---

## S-3 — `check_satisfiability` turns an unparseable constraint into UNSAT — **OPEN**

`src_new/concolic/solver.py`: a constraint the evaluator cannot build returns
`SolverResult(False, None, 0.0)`, indistinguishable at every call site from a
genuine UNSAT. A branch that could not be *expressed* is then reported as one
that cannot be *taken*. A distinct outcome (`unknown`, or a raise) is what
this needs; a `logger.warning` on a stream nobody captures is not a signal.

**Compensated at one call site only** — see S-7.

**Related but NOT a defect.** `Failed to eval var decl 'Length(X) = Int(…)'`
is benign and deliberate: `_contain_names` leaves a name alone when
`is_solver_term(name)`, so the declaration is invalid Python on purpose and
the term is re-derived from its base variable. The e2e inventory separates the
two (`SOLVER_VAR_DECL_UNEVALUABLE`, non-blocking, vs
`SOLVER_CONSTRAINT_UNPARSED`, blocking).

---

## S-4 — `src_new/README.md` asserted a false invariant, and a check was built on it — **the check is FIXED on my side; the sentence was still there on 2026-09-26**

`src_new/README.md:333` (as of 2026-09-26) said "every `opaque` sits behind a
`SHIM`, so none of them can reach a policy." The first clause is an invariant
about kinds; the second does not follow. A shim is never an **access**, so it
contributes no atom — but it does contribute a **signature**, and a signature
carries its declared return type. `dumps_to_policy/normalize.py` says the same
from the other side: "AN ELIDED TARGET KEEPS ITS `sig` LINE, deliberately."

This cost six endpoints in both shakedown runs: the shakedown's
`tools/pipeline.py has_opaque` treated any opaque reaching a policy as a
failure, so `sessions_new`, `registrations_new` and the four
`devise_passwords_*` were reported as failures for doing exactly what the
design says should happen. **Fixed on my side** (`e2e/tools/pipeline.py`,
`opaque_sites`, which separates entry params and atom-referenced
`target_function` returns — real defects — from shim signature returns, which
are by design). Round 2 measured **0 opaque defects** corpus-wide.

I have not re-checked the README sentence today.

---

## S-5 — a nameless symbolic value becomes a LITERAL in the structured path condition — **OPEN**

`src_new/runtimes/ruby_runtime/term.rb`'s `term_of`: a `SymbolicVar` with no
`sym_name` falls through to `lit(to_native(raw))` — the concrete value.
`SymbolicSubstring#initialize` passes `name: nil`, so every substring is that
case, even though `SymbolicSubstring#z3_expr` produces a correct
`SubString(parent, start, len)`. The legacy **string** form of the condition is
right and the §4.1.1e **structured** form silently substitutes a constant.

**Measured (RE-DERIVED — the dump survives at
`_round1/`… no: at `runs/` only for round 2; the round-1 dump that carried it
was in the deleted `_round1/runs/`).** The original measurement was the
devise salt compare on `admin_pods_index`, recorded at
`devise/models/authenticatable.rb:238` as

```json
{"op": "==", "args": [{"lit": {"sort": "str", "value": "SYM_RESULT_ActiveRecord__Find"}},
                      {"lit": {"sort": "str", "value": "concolicsalt"}}]}
```

both operands literals, the left one the symbolic `encrypted_password` column
flattened to its concrete prefix. **That artifact is among the deleted files
and I cannot re-display it today.** It is quoted in `REPORT.md` §2, written
while the dump was in hand. The three consequences recorded there: a path
condition with no symbolic operand is counted as a decision; the Z3 query is a
Python `bool` inside a Z3 tree (`Context mismatch`); and S-3 turns that into
UNSAT.

FIX-1 removed *this instance* (the compare became `String#==` against a
`ConcreteSymbolicString` and records nothing) — measured as
`SOLVER_CONSTRAINT_UNPARSED` falling from **41 endpoints to 13**. The
underlying defect is untouched and fires for any comparison against a nameless
symbolic value.

**Fix.** Either give `SymbolicSubstring` a structured term of its own matching
the `SubString(...)` the string form already emits, or return `nil` from
`term_of` for a nameless `SymbolicVar` so `cmp_term` returns `nil` and the
honest legacy string form stands alone — which is what `dump_operand`'s own
docstring says should happen when "there is no honest term for it".

---

## S-7 — the coverage checker's blind spot is absent from the summary `run_complete` returns — **OPEN**

**What is right.** `concolic/coverage.py` probes every path-condition
expression with `Or(expr, Not(expr))` before using it, and puts the ones that
fail into `unevaluable` — "a tautology can only fail by parse error / missing
decl". That is the correct defence against S-3: an expression the solver
cannot build is excluded from the universe rather than treated as an
infeasible branch, and the module docstring says so.

**What is missing (RE-VERIFIED today).** `unevaluable_exprs` is a field on
`CoverageResult` and is printed in its human report. It is **not** in the
summary dict `run_complete` builds — `grep -c unevaluable_exprs
concolic/check.py` returns **0** today. Every automated consumer reads that
dict. The blind spot is visible to a person reading a printed report and
invisible to the harness, the campaign and any gate built on the summary.

**Measured (RE-DERIVED from the surviving round-2 inventory).** 13 endpoints
carry `SOLVER_CONSTRAINT_UNPARSED`, every one a decision over a container's
cardinality — two distinct causes, both about cardinality: the list itself is
never declared as a solver variable (§4.1.1e deleted the length variable, so
nothing declares the container either), and the legacy `len(X)` spelling still
reaches the solver as Python source where `__builtins__` is `{}`.

**Why it matters more after FIX-9.** Making `records` return an iterable list
means `(len(X) != 0)` is recorded on every endpoint that materialises a
relation. Every one of those lands in `unevaluable` — correctly, and invisibly
to anything reading the summary.

**Mitigation applied here, not a fix.** The e2e pipeline captures its own
stderr and the inventory records `SOLVER_CONSTRAINT_UNPARSED` per endpoint
with the offending constraints. The real fix is one line in `check.py`'s
summary dict.
