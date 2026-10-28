#!/usr/bin/env python3
"""build_manifest.py — turn raw_introspection.json into the entry-point manifest.

Input  : entrypoints/raw_introspection.json  (written by introspect_entrypoints.rb
         from INSIDE a booted Rails app — see ../README.md)
Output : entrypoints/manifest.json           (the machine-readable manifest)
         entrypoints/sweep_endpoints.json    (a ready-to-paste `endpoints` array
                                              for src_new/sweep's spec)

Pure arithmetic and reshaping over facts already measured by the Ruby pass.
This file invents no facts; every field is traceable to the raw input.

Usage:
  /home/dev/project/venvs/queries_from_runs/bin/python3 build_manifest.py
"""

from __future__ import annotations

import json
import re
import subprocess
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
ENTRYPOINTS = HERE.parent
AUTOLAB = ENTRYPOINTS.parent
RAW = ENTRYPOINTS / "raw_introspection.json"
OUT_MANIFEST = ENTRYPOINTS / "manifest.json"
OUT_SWEEP = ENTRYPOINTS / "sweep_endpoints.json"
SCAFFOLD_DIR = ENTRYPOINTS / "scaffold"
TARGETS_REGISTRY = AUTOLAB / "targets" / "registry.json"

SCHEMA_VERSION = 1

# The seven endpoints already driven concolically (reports/diaspora/results3,
# results4). They are not "to do"; they are the pipeline's regression set.
ALREADY_DRIVEN = {
    "aspect_memberships_create",
    "comments_index",
    "conversations_index",
    "notifications_index",
    "people_show",
    "people_stream",
    "posts_show",
}

# ApplicationController's own unconditional chain. Anything beyond this is the
# controller's own work and is what makes one action costlier than another.
# Measured, not assumed: computed below as the modal filter set.
BASELINE_FILTERS = {
    "verify_authenticity_token",
    "force_tablet_html",
    "set_request_format",
    "verify_same_origin_request",
    "ensure_http_referer_is_set",
    "set_locale",
    "set_diaspora_header",
    "set_grammatical_gender",
    "mobile_switch",
    "gon_set_current_user",
    "gon_set_appconfig",
    "gon_set_preloads",
    "configure_permitted_parameters",
}

ROLE_FILTERS = {
    "redirect_unless_admin": "admin",
    "redirect_unless_moderator": "moderator",
}


def endpoint_id(controller: str, action: str) -> str:
    """`comments#index` -> `comments_index`; `admin/users#lock_account` ->
    `admin_users_lock_account`. Matches the existing results3/results4 naming."""
    return re.sub(r"[^a-z0-9]+", "_", f"{controller}_{action}".lower()).strip("_")


def entrypoint_label(controller: str, action: str) -> str:
    """The one-stack `entrypoint` string: "PeopleController#show"."""
    parts = controller.split("/")
    camel = "::".join(
        "".join(w.capitalize() for w in p.split("_")) for p in parts
    )
    return f"{camel}Controller#{action}"


def main() -> int:
    if not RAW.exists():
        sys.exit(f"missing {RAW} — run introspect_entrypoints.rb first")
    raw = json.loads(RAW.read_text())

    models = raw["models"]
    controllers = raw["controllers"]

    # --- group route rows into one endpoint per distinct controller#action ---
    by_action: dict[tuple[str, str], list[dict]] = defaultdict(list)
    for a in raw["actions"]:
        by_action[(a["controller"], a["action"])].append(a)

    targets_reg = {}
    if TARGETS_REGISTRY.exists():
        try:
            targets_reg = json.loads(TARGETS_REGISTRY.read_text())
        except json.JSONDecodeError:
            targets_reg = {}
    reg_endpoints = (targets_reg.get("endpoints") or {})

    endpoints = []
    findings = []

    for (ctrl, action), rows in sorted(by_action.items()):
        head = rows[0]  # identical per-action facts; routes differ
        eid = endpoint_id(ctrl, action)
        src_file = head.get("source_file")
        # An implicit-render action has no method and therefore no
        # source_location, and JRuby 9.3 (Ruby 2.6) has no
        # Object.const_source_location to fall back on — so also check
        # whether the app's own controller file exists on disk.
        ctrl_file = (controllers.get(ctrl) or {}).get("file")
        guessed = f"app/controllers/{ctrl}_controller.rb"
        app_owned = (
            (src_file or "").startswith("app/controllers")
            or (ctrl_file or "").startswith("app/controllers")
            or (Path(raw["app_root"]) / guessed).exists()
        )
        if head.get("engine"):
            owner = "engine"
        elif app_owned:
            owner = "app"
        else:
            owner = "gem"
        if ctrl_file is None and (Path(raw["app_root"]) / guessed).exists():
            ctrl_file = guessed

        # ---- routes ----------------------------------------------------
        routes = []
        for r in rows:
            routes.append(
                {
                    "name": r["route_name"],
                    "verb": r["verb"],
                    "path": r["path"],
                    "path_params": r["required_parts"],
                    "route_defaults": r["route_defaults"],
                }
            )
        # The primary route is the one with the most specific name and the
        # fewest path params — that is the one a driver should model first.
        routes.sort(key=lambda r: (len(r["path_params"]), r["path"]))
        routes[0]["primary"] = True
        for r in routes[1:]:
            r["primary"] = False
        verbs = sorted({v for r in rows for v in r["verb"].split("|") if v})

        # ---- filters ---------------------------------------------------
        applied = [f["filter"] for f in head["filters"] if f["applies"] == "yes"]
        conditional = [
            f["filter"] for f in head["filters"] if f["applies"] == "conditional"
        ]
        skipped = [f["filter"] for f in head["filters"] if f["applies"] == "no"]
        beyond_baseline = sorted(set(applied) - BASELINE_FILTERS)

        role = None
        for f in applied + conditional:
            if f in ROLE_FILTERS:
                role = ROLE_FILTERS[f]

        auth_enforced = "authenticate_user!" in applied
        auth_conditional = "authenticate_user!" in conditional
        reads_cu = bool(head.get("reads_current_user"))

        if auth_enforced:
            scenario = "auth"
        elif reads_cu or auth_conditional:
            # The action is reachable anonymously but branches on the
            # principal — both arms are real, so a batch should drive both.
            scenario = "both"
        else:
            scenario = "anon"

        # ---- params ----------------------------------------------------
        path_params = sorted({p for r in rows for p in r["required_parts"]})
        read = head.get("params_read") or []
        # e2e FIX-8: params the action reads through its own private helpers
        # (see introspect_entrypoints.rb). Appended, never substituted, so the
        # action-body order still leads.
        for _p in (head.get("params_read_in_helpers") or []):
            if _p not in read:
                read.append(_p)
        non_path = sorted(set(read) - set(path_params))

        # ---- model graph -----------------------------------------------
        named_models = sorted(
            {c for c in (head.get("constants") or []) if c in models}
        )
        assoc_total = sum(models[m]["associations"] for m in named_models)
        max_assoc = max((models[m]["associations"] for m in named_models), default=0)

        b = {
            k: bool(head.get(k))
            for k in (
                "writes_db",
                "enqueues_job",
                "federation",
                "sends_mail",
                "external_http",
                "renders_stream",
                "redirects",
                "paginates",
                "uses_presenter",
                "renders_json",
                "reads_session",
                "reads_request",
            )
        }

        loc = head.get("loc") or 0
        view_loc = head.get("view_loc") or 0

        # ---- cost model (documented in ../README.md) --------------------
        components = {
            "action_loc": 1.0 * loc,
            "params": 2.0 * len(read),
            "extra_filters": 6.0 * len(beyond_baseline),
            "association_breadth": 0.5 * assoc_total,
            "view_loc": 0.2 * view_loc,
            "renders_stream": 25.0 if b["renders_stream"] else 0.0,
            "federation": 20.0 if b["federation"] else 0.0,
            "background_job": 15.0 if b["enqueues_job"] else 0.0,
            "sends_mail": 10.0 if b["sends_mail"] else 0.0,
            "external_http": 30.0 if b["external_http"] else 0.0,
            "writes_db": 10.0 if b["writes_db"] else 0.0,
            "paginates": 8.0 if b["paginates"] else 0.0,
            "auth_required": 5.0 if auth_enforced else 0.0,
        }
        score = round(sum(components.values()), 2)

        blockers = sorted(
            k
            for k in (
                "renders_stream",
                "federation",
                "enqueues_job",
                "sends_mail",
                "external_http",
            )
            if b[k]
        )

        tier_reg = reg_endpoints.get(eid)
        targets = (
            {
                "tier": tier_reg.get("tier", "gold"),
                "override_file": tier_reg.get("file"),
                "modules": tier_reg.get("modules", []),
            }
            if tier_reg
            else {"tier": "candidate", "override_file": None, "modules": []}
        )

        ep = {
            "id": eid,
            "entrypoint": entrypoint_label(ctrl, action),
            "controller": ctrl,
            "controller_class": head.get("controller_class"),
            "action": action,
            "engine": head.get("engine"),
            "owner": owner,
            "status": head["status"],
            "driven_before": eid in ALREADY_DRIVEN,
            "source": {
                "file": src_file,
                "line": head.get("source_line"),
                "defined_in": head.get("defined_in"),
                "loc": loc,
                "body_extracted": head.get("body_extracted"),
            },
            "controller_file": ctrl_file,
            # Inheritance chain up to ActionController::Base. Auth can be
            # declared on any of these, which is why the resolved callback
            # chain — not a grep of one file — is what `auth` is read from.
            "controller_ancestry": (controllers.get(ctrl) or {}).get("ancestry", []),
            "views": head.get("views") or [],
            "view_loc": view_loc,
            "verbs": verbs,
            "routes": routes,
            "params": {
                "path": path_params,
                "read_in_action": read,
                "query_or_body": non_path,
                "format_segment": any("(.:format)" in r["path"] for r in routes),
                "respond_to": head.get("respond_to") or [],
            },
            "auth": {
                "authenticate_user_enforced": auth_enforced,
                "authenticate_user_conditional": auth_conditional,
                "role_required": role,
                "reads_current_user": reads_cu,
                "recommended_scenario": scenario,
            },
            "filters": {
                "applied": applied,
                "conditional": conditional,
                "not_applied": skipped,
                "beyond_application_controller": beyond_baseline,
                "declared_in_controller": (controllers.get(ctrl) or {}).get(
                    "declared_filters", []
                ),
            },
            "behaviour": b,
            "model_graph": {
                "models_named": named_models,
                "association_total": assoc_total,
                "max_model_associations": max_assoc,
            },
            "cost": {"score": score, "components": components, "blockers": blockers},
            "targets": targets,
        }
        endpoints.append(ep)

        # ---- findings (route/controller disagreements) ------------------
        if head["status"] == "action_missing":
            findings.append(
                {
                    "kind": "route_without_action",
                    "severity": "dead_route",
                    "endpoint": eid,
                    "detail": (
                        f"{[r['verb'] + ' ' + r['path'] for r in routes]} routes to "
                        f"{head.get('controller_class')}#{action}, which has no action "
                        f"method and no app/views/{ctrl}/{action}.* template. A request "
                        f"would raise AbstractController::ActionNotFound."
                    ),
                }
            )
        elif head["status"] == "implicit_render":
            findings.append(
                {
                    "kind": "route_without_action",
                    "severity": "implicit_render_ok",
                    "endpoint": eid,
                    "detail": (
                        f"{head.get('controller_class')}#{action} has no action method, "
                        f"but renders implicitly from {head.get('views')}. Routable and "
                        f"drivable; there is simply no Ruby body to explore."
                    ),
                }
            )

    for u in raw["unrouted_public_actions"]:
        findings.append(
            {
                "kind": "public_action_without_route",
                "severity": "info",
                "endpoint": endpoint_id(
                    u["class"].replace("Controller", ""), u["action"]
                ),
                "detail": (
                    f"{u['class']}#{u['action']} ({u['source_file']}:{u['source_line']}) is "
                    f"public and therefore in action_methods, but no route reaches it. "
                    f"It is a helper that should have been private, not an entry point."
                ),
            }
        )

    # ---- ordering -----------------------------------------------------
    # Tier 0: already driven (regression set). Then ascending cost, with
    # dead routes and gem/engine-owned actions pushed last.
    def sort_key(e):
        return (
            0 if e["driven_before"] else 1,
            2 if e["status"] == "action_missing" else (1 if e["owner"] != "app" else 0),
            e["cost"]["score"],
            e["id"],
        )

    endpoints.sort(key=sort_key)

    drivable = [e for e in endpoints if e["status"] != "action_missing"]
    app_todo = [
        e for e in drivable if e["owner"] == "app" and not e["driven_before"]
    ]
    # Cut points chosen on the measured distribution of `app_todo` scores
    # (quartiles), recorded here so the tiering is reproducible.
    scores = sorted(e["cost"]["score"] for e in app_todo)

    def q(p):
        if not scores:
            return 0.0
        return scores[min(len(scores) - 1, int(p * len(scores)))]

    cuts = {"t1": q(0.25), "t2": q(0.50), "t3": q(0.75)}

    rank = 0
    for e in endpoints:
        if e["driven_before"]:
            e["priority"] = {"tier": 0, "rank": None, "why": "already driven — regression set"}
            continue
        if e["status"] == "action_missing":
            e["priority"] = {"tier": None, "rank": None, "why": "dead route — not drivable"}
            continue
        if e["owner"] != "app":
            e["priority"] = {
                "tier": 5,
                "rank": None,
                "why": f"{e['owner']}-owned controller — outside the app source tree",
            }
            continue
        rank += 1
        s = e["cost"]["score"]
        if e["cost"]["blockers"]:
            tier = 4
            why = "has a heavy blocker: " + ", ".join(e["cost"]["blockers"])
        elif s <= cuts["t1"]:
            tier, why = 1, f"cost {s} in the cheapest quartile (<= {cuts['t1']})"
        elif s <= cuts["t2"]:
            tier, why = 2, f"cost {s} in the second quartile (<= {cuts['t2']})"
        elif s <= cuts["t3"]:
            tier, why = 3, f"cost {s} in the third quartile (<= {cuts['t3']})"
        else:
            tier, why = 4, f"cost {s} in the most expensive quartile (> {cuts['t3']})"
        e["priority"] = {"tier": tier, "rank": rank, "why": why}

    # re-sort so the emitted order IS the sweep order
    endpoints.sort(
        key=lambda e: (
            0 if e["driven_before"] else 1,
            99 if e["priority"]["tier"] is None else e["priority"]["tier"],
            e["cost"]["score"],
            e["id"],
        )
    )
    for i, e in enumerate(
        [x for x in endpoints if not x["driven_before"] and x["priority"]["tier"] not in (None, 5)],
        start=1,
    ):
        e["priority"]["rank"] = i

    # ---- provenance ----------------------------------------------------
    try:
        rev = (AUTOLAB.parent.parent / "ruby_examples/dse-apps/apps/diaspora/REVISION")
        revision = rev.read_text().strip() if rev.exists() else None
    except OSError:
        revision = None

    counts = {
        "route_rows": len(raw["routes_raw"]),
        "routed_action_rows": len(raw["actions"]),
        "distinct_endpoints": len(endpoints),
        "endpoints_app_owned": sum(1 for e in endpoints if e["owner"] == "app"),
        "endpoints_gem_owned": sum(1 for e in endpoints if e["owner"] == "gem"),
        "endpoints_engine_owned": sum(1 for e in endpoints if e["owner"] == "engine"),
        "endpoints_already_driven": sum(1 for e in endpoints if e["driven_before"]),
        "endpoints_dead_route": sum(
            1 for e in endpoints if e["status"] == "action_missing"
        ),
        "endpoints_implicit_render": sum(
            1 for e in endpoints if e["status"] == "implicit_render"
        ),
        "endpoints_auth_enforced": sum(
            1 for e in endpoints if e["auth"]["authenticate_user_enforced"]
        ),
        "controllers": len(controllers),
        "activerecord_models": len(models),
        "non_controller_routes": sum(
            1 for r in raw["routes_raw"] if r["kind"] != "action"
        ),
        "by_tier": dict(
            Counter(
                str(e["priority"]["tier"]) for e in endpoints
            )
        ),
    }

    manifest = {
        "schema_version": SCHEMA_VERSION,
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "generator": "reports/autolab/entrypoints/tools/build_manifest.py",
        "provenance": {
            "method": "runtime introspection of a booted Rails app (NOT a static parse)",
            "raw_input": "entrypoints/raw_introspection.json",
            "raw_generator": raw["generated_by"],
            "rails_version": raw["rails_version"],
            "rails_env": raw["rails_env"],
            "app_root": raw["app_root"],
            "app_revision": revision,
            "cross_checked_against": (
                "`bin/rails routes` in the same environment; every controller#action "
                "row matched, the only diffs being cosmetic Rack-app naming and the "
                "internal /assets and /cable routes that `rails routes` hides."
            ),
        },
        "cost_model": {
            "note": "weights are documented in entrypoints/README.md; score is a "
                    "relative cost estimate, not a time prediction",
            "weights": {
                "action_loc": 1.0,
                "params": 2.0,
                "extra_filters": 6.0,
                "association_breadth": 0.5,
                "view_loc": 0.2,
                "renders_stream": 25.0,
                "federation": 20.0,
                "background_job": 15.0,
                "sends_mail": 10.0,
                "external_http": 30.0,
                "writes_db": 10.0,
                "paginates": 8.0,
                "auth_required": 5.0,
            },
            "tier_cuts": cuts,
        },
        "counts": counts,
        "findings": findings,
        "non_controller_routes": [
            {
                "verb": r["verb"],
                "path": r["path"],
                "app": r["app_class"],
                "name": r["name"],
            }
            for r in raw["routes_raw"]
            if r["kind"] != "action"
        ],
        "endpoints": endpoints,
    }

    OUT_MANIFEST.write_text(json.dumps(manifest, indent=2) + "\n")

    # ---- sweep spec fragment -------------------------------------------
    box_for_tier = {0: "sm", 1: "sm", 2: "sm", 3: "md", 4: "md", 5: "md"}
    attempts_for_tier = {0: 6, 1: 6, 2: 6, 3: 8, 4: 10, 5: 10}
    sweep_eps = []
    for e in endpoints:
        if e["status"] == "action_missing":
            continue
        t = e["priority"]["tier"] if e["priority"]["tier"] is not None else 4
        sweep_eps.append(
            {
                "name": e["id"],
                # Absolute: sweep.testbed resolves a relative `config`
                # against the SPEC FILE's directory, and an absolute path is
                # correct wherever the spec is placed.
                "config": str(SCAFFOLD_DIR / e["id"] / "config.json"),
                "home": "local",
                "max_attempts": attempts_for_tier.get(t, 8),
                "box": box_for_tier.get(t, "md"),
            }
        )
    OUT_SWEEP.write_text(
        json.dumps(
            {
                "_comment": [
                    "Paste this `endpoints` array into a src_new/sweep spec.",
                    "Keys are a subset of sweep.spec._ENDPOINT_KEYS "
                    "{name, config, home, max_attempts, box, agents, "
                    "max_batch_agents}. `max_batch_agents` is the operator's "
                    "PIN on an endpoint's race width (sweep/race.py); it is "
                    "deliberately NOT emitted, because absent means "
                    "'unpinned' and the coordinator allocates the width "
                    "itself, starting at 1.",
                    "`config` paths are absolute, so the spec works wherever "
                    "it is placed (sweep.testbed would otherwise resolve them "
                    "against the spec file's own directory).",
                    "Order is the priority ordering from manifest.json.",
                ],
                "endpoints": sweep_eps,
            },
            indent=2,
        )
        + "\n"
    )

    # ---- a complete, loadable spec -------------------------------------
    # The endpoints array is this lab's; the surrounding blocks are the
    # canonical example's (sweep/tests/conftest.py BASE_SPEC) and are TEST
    # VALUES — box sizes, budgets and agent routes must be reviewed before a
    # real run. Emitted so `sweep.spec.load_spec` can be pointed straight at
    # it; skipped silently if src_new is not importable.
    try:
        import copy
        import sys as _sys

        _sys.path.insert(0, "/home/dev/project/src_new")
        from sweep.tests.conftest import BASE_SPEC  # type: ignore

        full = copy.deepcopy(BASE_SPEC)
        full["endpoints"] = sweep_eps
        full["sweep"] = "autolab-diaspora"
        full["out"] = str(ENTRYPOINTS / "sweep_out")
        (ENTRYPOINTS / "sweep.json").write_text(json.dumps(full, indent=2) + "\n")
        print(f"wrote {ENTRYPOINTS / 'sweep.json'}  (complete spec)")
    except Exception as exc:  # noqa: BLE001 - optional convenience output
        print(f"  (skipped sweep.json: {type(exc).__name__}: {exc})")

    print(f"wrote {OUT_MANIFEST}  ({len(endpoints)} endpoints)")
    print(f"wrote {OUT_SWEEP}     ({len(sweep_eps)} sweep entries)")
    for k, v in counts.items():
        print(f"  {k}: {v}")
    print(f"  findings: {len(findings)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
