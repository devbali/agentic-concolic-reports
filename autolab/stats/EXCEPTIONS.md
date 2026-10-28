# What is excluded from `finished/`, and why

Generated 2026-10-07T18:08:38Z by `reports/autolab/tools/build_store.py`. Regenerated in full on every build; do not hand-edit.

This is the whole of what the build saw and did not ship. An empty section below means nothing fell into it.

- endpoints in the corpus: **161**
- endpoints with a finished artefact set: **161**
- runs excluded: **14** of 178 seen
- individual artefacts rejected by a verifier: **0** dumps, **0** policies

## Excluded runs

| endpoint | provenance | run | reason |
|---|---|---|---|
| `aspect_memberships_create` | local | `e2e_round3.slice1.superseded-052709` | a SUPERSEDED attempt: the round re-ran this endpoint and this attempt produced no policy, so only one of the two IRs exists for it. Its dumps are kept upstream in _trash/autolab_history_20260930/archive/results_evidence_store/ (retired there 2026-09-30; see its _RETIRED.md). |
| `blocks_create` | cloud | `sweep_out_w3.batch` | a shared batch mount, not one box's output: it mirrors dumps that a box also submitted, and nothing downstream consumed it, so only one of the two IRs exists for it |
| `devise_passwords_create` | cloud | `sweep_out_w3.batch` | a shared batch mount, not one box's output: it mirrors dumps that a box also submitted, and nothing downstream consumed it, so only one of the two IRs exists for it |
| `people_retrieve_remote` | cloud | `sweep_out_w3.batch` | a shared batch mount, not one box's output: it mirrors dumps that a box also submitted, and nothing downstream consumed it, so only one of the two IRs exists for it |
| `posts_destroy` | cloud | `sweep_out_w3.batch` | a shared batch mount, not one box's output: it mirrors dumps that a box also submitted, and nothing downstream consumed it, so only one of the two IRs exists for it |
| `posts_destroy` | cloud | `sweep_out_w4.batch` | a shared batch mount, not one box's output: it mirrors dumps that a box also submitted, and nothing downstream consumed it, so only one of the two IRs exists for it |
| `profiles_show` | cloud | `sweep_out_w3.batch` | a shared batch mount, not one box's output: it mirrors dumps that a box also submitted, and nothing downstream consumed it, so only one of the two IRs exists for it |
| `services_create` | cloud | `sweep_out_w3.batch` | a shared batch mount, not one box's output: it mirrors dumps that a box also submitted, and nothing downstream consumed it, so only one of the two IRs exists for it |
| `sessions_create` | cloud | `sweep_out_w3.batch` | a shared batch mount, not one box's output: it mirrors dumps that a box also submitted, and nothing downstream consumed it, so only one of the two IRs exists for it |
| `streams_liked` | cloud | `sweep_out_w3.batch` | a shared batch mount, not one box's output: it mirrors dumps that a box also submitted, and nothing downstream consumed it, so only one of the two IRs exists for it |
| `tag_followings_destroy` | cloud | `sweep_out_w3.batch` | a shared batch mount, not one box's output: it mirrors dumps that a box also submitted, and nothing downstream consumed it, so only one of the two IRs exists for it |
| `two_factor_authentications_recovery_codes` | cloud | `sweep_out_w3.batch` | a shared batch mount, not one box's output: it mirrors dumps that a box also submitted, and nothing downstream consumed it, so only one of the two IRs exists for it |
| `users_auth_token` | local | `e2e_round3.slice1.superseded-064214` | a SUPERSEDED attempt: the round re-ran this endpoint and this attempt produced no policy, so only one of the two IRs exists for it. Its dumps are kept upstream in _trash/autolab_history_20260930/archive/results_evidence_store/ (retired there 2026-09-30; see its _RETIRED.md). |
| `users_auth_token` | local | `e2e_round3.slice1.superseded-065337` | a SUPERSEDED attempt: the round re-ran this endpoint and this attempt produced no policy, so only one of the two IRs exists for it. Its dumps are kept upstream in _trash/autolab_history_20260930/archive/results_evidence_store/ (retired there 2026-09-30; see its _RETIRED.md). |

## Rejected artefacts

A dump that did not load through the IR gate, or whose text form did not round-trip; a policy that did not parse verbatim or whose two forms disagreed. None of these is copied into `reports/autolab/endpoints/`.

None.

## Endpoints with nothing finished at all

None: every endpoint in the corpus has at least one finished run.
