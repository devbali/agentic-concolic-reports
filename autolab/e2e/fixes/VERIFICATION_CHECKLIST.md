# The 6-endpoint verification trial — what each endpoint must show

Written BEFORE the trial runs, so the result is judged against a stated
expectation rather than rationalised afterwards. An endpoint that does not
show its expected change is a failed fix, not a surprise to explain away.

| endpoint | fix under test | expected, specifically | how to tell it failed |
|---|---|---|---|
| `admin_pods_index` | FIX-1/3/4/7/9 | principal resolves; `devise_user_first`, `Relation#records` **and something past the list** in `call_targets`; reach ≥ 3; no `len_var_name`, no `SymbolicList#each` stop | reach still 1, or either of those two NoMethodError/NotImplementedError sites still in `terminal_rows` |
| `sessions_new` | FIX-2 | no `NoMethodError … authentication_keys for #<Object>`; the stop, if any, is past `extract_auth_keys` | the same `parameter_sanitizer.rb:158` frame |
| `likes_index` | FIX-5 + FIX-6 | terminal is `AutolabDSE::AuthenticationRequired`, OR `Diaspora::NonPublic` **with** `handler.status = "rescue_from handler RAISED"` naming the inner exception | a bare `Diaspora::NonPublic` with no `handler` key |
| `comments_index` | FIX-11 | **12 of 12 dumps accepted** (`dump_ir: ok`); every dump that calls `Relation#records` declares `Comment` in its own `types` table | any `MalformedProvenance` refusal |
| `links_resolve` | FIX-8 | `config.json` lists `q` as a symbolic input and the run does not stop at `ParameterMissing: q` | still 0 inputs, or still `strong_parameters.rb:445` |
| `manifest_show` | FIX-12 (`*_path`) | no `Sprockets::FileNotFound`; `manifest_controller.rb:11` calls `helpers.image_path`, which compiles `app/assets/config/manifest.js` → `main.js` → `//= require underscore` | any stop whose backtrace names `assets/config/manifest.js` |
| `home_show` | FIX-12 (tag helpers) | no `ActionView::Template::Error` for `underscore`; and it must KEEP its one rendered SQL view | the same asset frame, or `render.views` falling to 0 |
| `diaspora_federation_receive_public` | FIX-8 (`:xml`) | `config.json` lists `xml`; no `CGI.unescape(nil)` stop at `CGIEscape.java:416`. A DIFFERENT stop here is a finding, not a failure — `CGI.unescape` may not accept a `SymbolicString`, which I said up front I had not verified | still stopping at `CGIEscape.java:416` with `:xml` in the config |
| `contacts_index` | breadth | no regression: still `ran_clean`, and reach ≥ its round-1 value | verdict `failed`, or reach below round 1 |

## Corpus-wide, on the same trial

* every dump accepted by `Run.from_dict` + `validate_provenance`;
* every stage returns a result (`dump_ir`, `run_complete`, `build_policy`,
  `normalize`, `policy_text`, `render_sql`) — `build_policy` may now *degrade*
  (recording a refused dump) but must not fail the endpoint;
* `opaque.defects` empty on all six (shim signature returns are expected and
  are not defects);
* gates report NOT CONFIGURED, and that is **recorded, not scored as a pass**;
* `limits_overridden: false` on every manifest row (FIX-10 — the sweep should
  now be taking its limits from `config.json`).

## What would make me NOT run the full sweep

Any of: a dump refused that was accepted in round 1; an endpoint whose reach
went DOWN; a new stopping site inside `reports/autolab/targets/` or
`autolab_dse.rb` (a fix breaking the library rather than the app); or the
target library's own suite falling below 75/75.
