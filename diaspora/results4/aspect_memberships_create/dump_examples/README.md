# `dump_examples/` — aspect_memberships_create

**ALL TEN** generated dumps, kept under their original names (`write_path/`
preserved as a subdirectory, since both sets number from `dse0001`) --
regenerated 2026-09-25 with the §5.0 type declarations and §4.1.1c's note
envelope in place, which is why this is now the whole set rather than six
representatives: every dump is a new artefact and none of them is a copy of
something already on disk. The per-path table below still calls out the six
that illustrate distinct shapes. Generated with:

* main set — `MAX_RUNS=6 TIME_BUDGET=600 scripts/diaspora-concolic ../run_dse.rb`
* write path — the same runner with
  `DUMP_OUT=../write_path EXTRA_SEEDS_JSON=../write_path_seeds.json SEEDS_ONLY=1`
  (REPORT.md §2; RUNBOOK Phase 2's "construct runs from counterexamples")

All 10 build cleanly through `dumps_to_policy.build.build_policy`.

| file | path / shape it illustrates |
|---|---|
| `dump_auth_json_dse0001.json` | **The full validation chain, ending 409.** 17 calls: the Devise user load, `Person.find($$(SYM_PARAM_person_id))`, the aspect finder, the contact lookup, the `blocks` existence probe, ending on `not_contact_for_self`. The long read-only spine every write path shares. |
| `dump_auth_json_dse0003.json` | **A real app terminal, not a framework wall.** `users.language = "xx"` makes `set_locale` raise `I18n::InvalidLocale` after a single access — `concolic_terminal` records it. Four events total; the shortest genuine path in the corpus. |
| `dump_auth_json_dse0004.json` | **Finder miss → the controller's own `rescue_from` → 404.** `Person.find` does not resolve, so the run stops after 4 calls with no aspect or contact read at all. |
| `dump_auth_json_dse0006.json` | **Blocked → 409 on the `blocks` arm.** `blocks.exists?` is true, so the aspect read happens but `share_with` never does. Shows the `SELECT 1 AS one FROM "blocks" …` existence statement carrying its own note off a bare Ruby `true` (change 6's pending-note channel, the falsy/truthy arm). |
| `write_path/dump_auth_json_dse0001.json` | **The contact-missing arm.** Carries `INSERT INTO "contacts" (…)` and then `UPDATE "notifications" SET "unread" = false …`. CORRECTED 2026-09-24: this row used to credit the dump with the join-row INSERT as well; measured against the dump, it carries no `aspect_memberships` statement. 46 events, 17 calls. |
| `write_path/dump_auth_json_dse0003.json` | **The join-row INSERT, existing-contact arm.** The longest path in the corpus (60 events, 22 calls): the contact row already exists, so instead of the contacts INSERT there is `INSERT INTO "aspect_memberships" ("aspect_id", "contact_id") VALUES ($$(SYM_RESULT_…first_1_id), $$(SYM_RESULT_…find_by_1_id))` — the endpoint's defining statement, both entrypoint parameters reaching SQL as genuine binds — then `UPDATE "contacts" SET "receiving" = true WHERE "contacts"."id" = $$(…)` and the notifications UPDATE. |

2026-09-24, SECOND PASS. `write_path/` now holds **all four** of its dumps
(`dse0001`–`dse0004`) rather than two, regenerated after
`ActiveRecord::Associations::SingularAssociation#writer` stopped being a
declared target — see `write_path/README.md` for what that changed (only a
removal: two events per run, nothing else) and `../POLICY_EXAMPLE.md` for
why. Event counts above are the post-change ones. All 10 dumps still build
cleanly, and now merge into one 84-atom policy over 14 signatures.
