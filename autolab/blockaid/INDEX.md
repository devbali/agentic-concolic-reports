# blockaid artefacts produced so far

Generated 2026-10-01T02:14:21Z by `reports/autolab/tools/blockaid_artefact.py`. Read `README.md` in this directory before reading the numbers.

`loadable` = views blockaid could load and type. `proved redundant` = pairs the solver PROVED subsumed; absence is never proof of distinctness (see `reading_subsumed_pairs` in each blockaid.json). The `binds` columns are the OVER-PERMISSIVE diagnostic mode, not a policy claim.

| endpoint | provenance | views | loadable (as-is) | proved redundant | loadable (binds) | proved redundant (binds) | path |
|---|---|---|---|---|---|---|---|
| `comments_index` | cloud | 1 | 1/1 | 0 | n/a | n/a | `endpoints/comments_index/cloud/sweep_out_or.box.20260929t002039-batch-comments_index-12040f-8153fd9e` |
| `comments_index` | cloud | 1 | 1/1 | 0 | n/a | n/a | `endpoints/comments_index/cloud/sweep_out_or.box.20260929t040141-batch-comments_index-74faa4-ba5d8bbf` |
| `comments_index` | local | 8 | 8/8 | 1 | n/a | n/a | `endpoints/comments_index/local/e2e_round3.slice1` |
| `posts_destroy` | cloud | 9 | 9/9 | 0 | n/a | n/a | `endpoints/posts_destroy/cloud/sweep_out_w4.box.20260929t190209-batch-posts_destroy-574d67-066c3ff0` |
| `posts_destroy` | local | 9 | 9/9 | 0 | n/a | n/a | `endpoints/posts_destroy/local/e2e_round3.slice2` |
