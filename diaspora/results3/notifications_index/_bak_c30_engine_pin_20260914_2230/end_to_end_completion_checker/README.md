# end_to_end_completion_checker — what the engine runs

Python side of the completion engine (`src/concolic_engine/completion.py`
orchestrates; Ruby probes live in `src/ruby_runtime/completion_checker/`).
Everything here works ON DUMPS or on a real run's `concrete_run.json`;
nothing touches extracted SQL. Grouped by check:

```
assumption/assumption_checker.py   the assumption gate (mandatory): every declared
                                   assumption tested by type via replay — Independence
                                   (flip A/B/both), UntrackedPath (trace identical),
                                   OneSideUntracked (untracked side adds nothing),
                                   SymbolicConstraint (violating value unrealizable /
                                   domain-implied)
mock/mock_note_check.py            the note check: each target's real statements (from a
                                   concrete run) have a corpus note of that shape
concrete/CONCRETE_CHECKER.md       the concrete checker = the adversary brief (a sub-agent,
                                   not a script); evidence fidelity per target call is its duty
```

The five SQL-consumer dump audits (identity symbolicity, note lint, bind
resolution, skipped PCs, PC visibility) live in `src/queries_from_runs/audits/`
and are the parent agent's manual phase between this engine's fixed checks
and the adversary. Batch configs reference the scripts above by absolute path. SQL-level / extraction-level tools live with the diaspora
reports, not here: `reports/diaspora/tools/` (`statement_diff.py`,
`complement_audit.py`, `note_fidelity_audit.py`). Retired scripts:
`reports/diaspora/trash/end_to_end_completion_checker/`.
