# The shared target boundary — what I tried, what the suite refused, and what I did instead

## I was wrong, and the library's own suite caught it

My first round applied four repairs as EDITS to the shared library:

* `targets/core.rb` — FIX-2 (`dev_stub.to`), FIX-7 (`len_var_name`),
  FIX-9 (`records` uses an iterable list)
* `targets/endpoints/comments_index.rb` — FIX-11 (the per-run memo)

I had reasoned the blast radius was contained and checked each one against
both gold endpoints. I had not checked the invariant that actually governs
those files. `test/test_install.rb:156-166`, §5:

> "5. the library is byte-identical to the results4 gold it was copied from"

and the suite said so:

```
FAIL core.rb == reports/diaspora/results4/aspect_memberships_create/concolic_targets.rb: DRIFTED
FAIL comments_index.rb == reports/diaspora/results4/comments_index/targets.rb: DRIFTED
```

That is a real invariant, not a formality. The library's claim is that it IS
those files, and `results4` is the reference corpus other work is locked
against — which I may not edit either. An "evidence-backed bug fix" is still
a divergence of the shared boundary from its source of truth, and the fact
that the bug is real does not make the divergence safe.

**Both files are reverted and byte-identical again** (verified by md5 against
the results4 originals, and the suite is back to `ALL SUITES PASSED`,
`38/38 + 38/38 + 75/75`). The attempted versions are kept beside them as
`targets/core.rb.e2e_attempt` and
`targets/endpoints/comments_index.rb.e2e_attempt`, for whoever decides
whether the library's own copy — and therefore the results4 gold — should
change. **That decision is not mine and I did not take it.**

## What replaced them — the same four repairs, from the runner

`fixes/apply_runner_local_core_fixes.py`. This is the technique the gold
layers themselves name: "Overriding from this file is the technique §9
already uses" (`comments_index.rb`).

| fix | what core.rb does wrong | how the runner answers it |
|---|---|---|
| **FIX-2** | `dev_stub.to` returns the stub, so Devise gets it where it expects the model class | re-declare `DeviseController#devise_mapping` to return the app's own `Devise.mappings[:user]` (same kind, same declared type) |
| **FIX-7** | calls `SymbolicVar.len_var_name`, deleted from the runtime | define it on `SymbolicVar` as a SEED KEY only, in the spelling `core.rb:98-124` documents |
| **FIX-9** | builds a plain `SymbolicList`, whose `each`/`map` raise, so Gate 1b's representative is unreachable | prepend `each`/`map` onto `SymbolicList`; a subclass's own methods still win, so `comments_index`'s `IterableSymbolicList` is untouched |
| **FIX-11** | `Thread.current[:comments_rows_memo]` is not scoped to a run | clear the per-run thread-local memos at the top of every run, from `run_one` — where the driver already clears `CallInterceptor#@all_calls` for the same reason |

**Nothing under `targets/` is modified.** The remaining changes are the
runner (`entrypoints/lib/autolab_dse.rb`), scaffold generation
(`entrypoints/tools/`), the per-endpoint `scaffold/*/config.json`, and my own
harness under `e2e/`. Nothing under `src/`, `src_new/` or
`reports/diaspora/results3/` or `results4/` was touched.

## The one documentation change outside `e2e/`

`reports/autolab/README.md` and `docs/CONFLICTS.md` were briefly rewritten while
`core.rb` was edited, because `check_citations.py` resolves each prose
citation from a pattern and my insertions moved every line after them. Both
are **restored to their original content** now that `core.rb` is reverted, and
`check_citations.py` reports "every prose citation lands on a registered
pattern".
