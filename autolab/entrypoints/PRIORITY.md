# Prioritised ordering of the 161 drivable entry points

The sweep works down this list. `manifest.json`'s `endpoints` array is
**already in this order**, and each entry carries `priority.rank`,
`priority.tier` and `priority.why`, so nothing here has to be re-derived by
hand.

The ordering is a function of measured facts only. No entry point was ranked
on intuition; if you disagree with a placement, the argument is with a weight
in `build_manifest.py`, and it is one dict.

---

## What is measured

Every input below comes from `raw_introspection.json`, produced inside the
booted app:

| Signal | How it is obtained |
|---|---|
| `action_loc` | Lines of the action method, from `UnboundMethod#source_location` to the matching `end`. |
| `params` | `params[:x]` / `params.require(:x)` / `params.fetch(:x` in the body, unioned with the route's required segments. |
| `extra_filters` | Filters in the **resolved** `_process_action_callbacks` chain beyond ApplicationController's own 13. Rails' `only:`/`except:` procs are *called*, not grepped. |
| `association_breadth` | For each ActiveRecord model named in the body, that model's `reflect_on_all_associations.size`, summed. This is the one-hop object graph the action can reach. |
| `view_loc` | Lines of `app/views/<controller>/<action>.*`. |
| `renders_stream` | Body mentions `Stream::`, `@stream`, `stream_responder` or `StreamHelper`. |
| `federation` | Body mentions `Diaspora::Federation`, `DiasporaFederation` or `Federation::`. |
| `background_job` | Body mentions `Workers::`, `perform_async`, `perform_later` or `.delay`. |
| `sends_mail`, `external_http`, `writes_db`, `paginates` | Same method, patterns in `introspect_entrypoints.rb`. |
| `auth_required` | `authenticate_user!` resolves ON in the callback chain. |

## The cost score

```
cost =  1.0 × action_loc
     +  2.0 × params
     +  6.0 × filters_beyond_ApplicationController
     +  0.5 × association_breadth
     +  0.2 × view_loc
     + 25    if renders_stream
     + 20    if federation
     + 15    if enqueues_job
     + 10    if sends_mail
     + 30    if external_http
     + 10    if writes_db
     +  8    if paginates
     +  5    if auth_required
```

The weights encode one claim: **what makes an endpoint expensive to drive
concolically is not how much code it has, but how much of the world it
reaches.** A filter costs six times a line of body because each one is
another chain of queries running before the action; a stream, a federation
call or an outbound HTTP request costs more than any amount of straight-line
code because it drags in a subsystem that has to be mocked before a single
path condition is recorded.

`cost.components` in the manifest records every term separately, so a score
can always be taken apart.

## Tiers

Cut points are the **quartiles of the measured distribution** over the 139
ranked app endpoints, not round numbers picked in advance:
`t1 ≤ 18.2`, `t2 ≤ 30.0`, `t3 ≤ 37.0`. They are recorded in
`manifest.cost_model.tier_cuts` and move when the app does.

One override: **any endpoint with a blocker goes to tier 4 regardless of
score.** A blocker is `renders_stream`, `federation`, `enqueues_job`,
`sends_mail` or `external_http` — the things that need a subsystem mocked
rather than a branch flipped. `streams_public` is three lines long and scores
28, and it is still tier 4, because those three lines build a stream.

| Tier | n | Cost range | What it is |
|---|---|---|---|
| **0** | 7 | 9.6 – 96.2 | Already driven — explored by hand to a close before this lab existed (`driven_before` in the manifest; the runs are under `reports/diaspora/results3/` and `results4/`). The regression set, not work. |
| **1** | 35 | 2.2 – 18.2 | Cheap and self-contained. 19 of the 35 need no principal at all. |
| **2** | 37 | 18.6 – 30.0 | Small actions, mostly signed-in (29/37). |
| **3** | 32 | 31.0 – 37.0 | Real branching, wider model graph. |
| **4** | 35 | 28.0 – 99.4 | Expensive, or blocked: 9 render a stream, 2 enqueue jobs, 2 federate. |
| **5** | 15 | — | Not the app's code: 9 gem-owned (Devise, ActiveStorage), 6 in the mounted federation engine. Routable, but changing them is out of scope and they have no app source to explore. |
| — | 1 | — | `photos_edit`: dead route, not scaffolded. |

---

## Tier 1 — start here (first 12 of 35)

| # | Endpoint | Cost | Scenario | loc | Why it is cheap |
|---|---|---|---|---|---|
| 1 | `help_faq` | 2.2 | anon | 0 | No action method at all — implicit template render. |
| 2 | `api_openid_connect_id_tokens_jwks` | 3.0 | anon | 3 | Three lines, no model. |
| 3 | `node_info_jrd` | 3.0 | anon | 3 | Static document. |
| 4 | `social_relay_well_known` | 3.0 | anon | 3 | Static document. |
| 5 | `home_force_mobile` | 5.0 | anon | 5 | Session flag + redirect. |
| 6 | `home_toggle_mobile` | 5.0 | anon | 5 | Session flag + redirect. |
| 7 | `api_openid_connect_clients_create` | 6.0 | anon | 5 | One model, 2 associations. |
| 8 | `links_resolve` | 6.0 | anon | 6 | No model. |
| 9 | `node_info_statistics` | 6.4 | anon | 6 | No model. |
| 10 | `likes_index` | 7.0 | anon | 5 | One path param, no model named. |
| 11 | `reshares_index` | 7.0 | anon | 5 | Same shape as `likes_index`. |
| 12 | `api_openid_connect_token_endpoint_create` | 9.0 | anon | 9 | No model. |

The first nine take no principal, which means no Devise resolution and no
`_MY_UID` folding to get right — the smallest possible first target for an
automated sweep.

`likes_index` is worth calling out as the **best early validation target**:
it is structurally the twin of the already-driven `comments_index` (a
`GET /posts/:post_id/…` index action, one path param, anonymous), so a
failure there is a failure of the scaffolding rather than of the endpoint.

## Tier 4 — what is actually hard, and why

Grounded in the blocker flags, not in how the action reads:

* **Nine stream endpoints** — `streams_public`, `streams_activity`,
  `streams_commented`, `streams_liked`, `streams_mentioned`,
  `streams_followed_tags`, `streams_aspects`, `streams_multi`,
  `people_stream` (already driven). Each is 3–8 lines that construct a
  `Stream::*` object; all the cost is behind it. `people_stream` is already
  driven, so it is the worked example for the other eight.
* **Two enqueue jobs** — `people_retrieve_remote`, and one more. These reach
  Sidekiq; the shared core already mocks `Sidekiq::Client#push` and
  `#push_bulk` (`reports/autolab/targets/core.rb:1100-1117`, section
  DESIGN #11), so the mock exists, but the *outcome* of an enqueue is not a
  path condition and needs a policy decision.
* **Two federate** — outbound to another pod. These need the federation
  subsystem walled before they can be driven at all.
* **The rest** are expensive by accumulation: `notifications_index` (tier 0,
  cost 96.2) is the current high-water mark and it *is* already done, which
  is the useful precedent — a score near 100 is achievable, not a wall.

## A caution about the ordering

The cost score predicts **setup cost**, not path count. In the hand-driven
runs, `comments_index` scores 9.6 and took 79 views to close, while
`notifications_index` scores 96.2 and also closed. What the score is good for
is deciding what to attempt first when nothing is known, which is exactly the
sweep's problem. Once an endpoint
has been attempted, its own `exploration_summary.json` is better evidence
than this table.
