#!/usr/bin/env python3
"""build_partition.py -- emit inventory/partition.json, the core/local ruling.

The user's ruling for this lab:

    "The target functions are standard across endpoints. The shim mocks some
     can be standardized while others are local."

So: every `kind: TARGET_FUNCTION` declaration belongs to the shared core, and
every `kind: SHIM` declaration is triaged one at a time. The triage is a
JUDGEMENT, so it lives here, in a table with a written reason per shim group,
rather than being inferred from the corpus. What is NOT a judgement -- which
targets exist, what kind and type each carries, which file declares it -- comes
from inventory/manifest.json, and this script FAILS if the table and the
manifest disagree about the target set. The two cannot drift apart silently.

Tiers
  core            in targets/core.rb today, and belongs there
  core-promoted   lifted by this lab out of a batch file into
                  targets/shared_shims.rb
  core-eligible   app-wide in substance, still in a batch file, because
                  lifting it needs work named in "blocker"
  local           endpoint-local by construction; promoting it would be wrong

Run:  /home/dev/project/venvs/queries_from_runs/bin/python3 tools/build_partition.py
"""
import json
import os
import sys

LAB = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INV = os.path.join(LAB, "inventory")

# ---------------------------------------------------------------------------
# SHIM GROUPS. Every core shim is assigned to exactly one, and the group
# carries the reason it is app-wide (or is not).
# ---------------------------------------------------------------------------
SHIM_GROUPS = {
    "controller_response": {
        "tier": "core",
        "why": (
            "The response side of ActionController, identical for every action in "
            "the app. These fire in the controller-test rig because @_response is "
            "not built, or because engine routes are not loaded -- conditions of "
            "the RIG, not of the endpoint. None of them can differ between "
            "endpoints without the rig itself differing."),
        "targets": [
            "ActionController::Metal#status=",
            "ActionController::Metal#head",
            "ActionController::Head#head",
            "ActionController::ImplicitRender#default_render",
            "ActionController::Redirecting#redirect_to",
            "ActionController::Instrumentation#redirect_to",
            "ActionController::Rendering#_set_rendered_content_type",
            "ActionDispatch::Routing::UrlFor#url_for",
            "ApplicationController#after_sign_in_path_for",
        ],
    },
    "devise_boundary": {
        "tier": "core",
        "why": (
            "Authentication is a SHARED BOUNDARY POLICY, not an endpoint's "
            "business: the entrypoint is post-auth with a symbolic principal. A "
            "per-endpoint devise shim would make the boundary itself vary by "
            "endpoint, which is precisely what Rule T forbids."),
        "targets": [
            "DeviseController#assert_is_devise_resource!",
            "DeviseController#devise_mapping",
            "ApplicationController#configure_permitted_parameters",
        ],
    },
    "background_jobs": {
        "tier": "core",
        "why": (
            "Sidekiq enqueue. The job payload differs by endpoint; the WALL does "
            "not -- the runtime cannot model Redis for any of them."),
        "targets": ["Sidekiq::Client#push", "Sidekiq::Client#push_bulk"],
    },
    "federation_entity": {
        "tier": "core",
        "why": (
            "The federation entity graph is a wall for the runtime everywhere it "
            "is reached. Neither declaration mentions a model or an action."),
        "targets": [
            "DiasporaFederation::Entity#validate",
            "DiasporaFederation::Entity#normalize_property",
        ],
    },
    "federation_delivery": {
        "tier": "core-promoted",
        "lifted_to": "targets/shared_shims.rb",
        "lifted_from": "reports/diaspora/results4/aspect_memberships_create/targets.rb:512-531",
        "why": (
            "Same wall as federation_entity, on the delivery side. It sat in one "
            "batch's file only because that batch was the first WRITE endpoint in "
            "the corpus -- nothing in either body or its reasoning mentions aspect "
            "memberships. Both mock bodies are `->(_r,_a,_n) { nil }`: no batch-local "
            "helper, no batch-local prepend, so the lift is verbatim and total. "
            "CARRIED COST, verbatim from the batch that wrote them: "
            "deliver_profile_update reads self.profile, an association load that "
            "WOULD be an access, and shimming the outer method elides it."),
        "targets": [
            "Diaspora::Federation::Dispatcher.defer_dispatch",
            "User#deliver_profile_update",
        ],
    },
    "association_plumbing": {
        "tier": "core",
        "why": (
            "ActiveRecord association internals. `writer` is the single framework "
            "chokepoint every `record.assoc = x` flows through; `CollectionProxy#create` "
            "is the collection builder. Framework, not app."),
        "targets": [
            "ActiveRecord::Associations::SingularAssociation#writer",
        ],
    },
    "model_builders": {
        "tier": "core",
        "why": (
            "diaspora's `Model.diaspora_initialize` builders. App code, but not "
            "endpoint code: any action that builds a Post or a Photo reaches them, "
            "and the wall they clear (a symbolic author with a nil owner) is a "
            "property of symbolic instances, not of the caller."),
        "targets": ["Photo.diaspora_initialize", "Post.diaspora_initialize"],
    },
    "write_path_walls": {
        "tier": "core",
        "why": (
            "Diaspora's shared write plumbing -- stream fan-out, tag building, "
            "retraction, notification marking, email confirmation. Each is reached "
            "from several controllers. They are grouped because they share a "
            "failure mode, not an endpoint."),
        "targets": [
            "Diaspora::Taggable#build_tags",
            "StatusMessage#tag_name_max_length",
            "User#add_to_streams",
            "StatusMessageCreationService#add_to_streams",
            "User#retract",
            "User#confirm_email",
        ],
    },
    "display_leaves": {
        "tier": "core",
        "why": (
            "SQL-free leaves that only exist to clear a SymbolicString wall "
            "(`Photo#url` concatenates, `User#mine?` compares). Pure display."),
        "targets": ["Photo#url", "User#mine?"],
    },
    "view_helpers": {
        "tier": "core",
        "why": (
            "Presenter and view plumbing (gon, mention JSON, renderer title). "
            "Shared by every endpoint that renders, and inert on those that do not."),
        "targets": [
            "Gon::ControllerHelpers#gon",
            "PostPresenter#build_mentioned_people_json",
            "Diaspora::MessageRenderer#title",
        ],
    },
    "streams_family": {
        "tier": "core",
        "caveat": "FAMILY-SCOPED, not truly app-wide -- see 'why'.",
        "why": (
            "The Gate-1b stream call-site shims. These only ever FIRE on the "
            "stream and tag endpoints; on comments_index or aspect_memberships_create "
            "they are dormant declarations. They are kept in the core anyway "
            "because that is where both gold batches carry them and moving them "
            "would change what those two endpoints declare -- but they are the "
            "one group in this core that is family-scoped rather than app-wide, "
            "and they are the first candidates if the core is ever split by family. "
            "A dormant declaration is not free: it shows up in the declared-target "
            "roster that completeness accounting reads."),
        "targets": [
            "Stream::Aspect#aspect_ids",
            "Stream::FollowedTag#tag_ids",
            "Stream::Base#post_ids",
            "Stream::Base#attach_user_likes",
            "Stream::Multi#publisher_prefill",
            "StreamsController#decorated_stream_posts",
            "TagsController#prep_tags_for_javascript",
        ],
    },
    # ---- shims that are NOT in the core today -------------------------------
    "polymorphic_association": {
        "tier": "core-eligible",
        "blocker": (
            "The mock body calls `CommentsTargets.poly_klass(receiver)`, a "
            "batch-local helper. Lifting the declaration means lifting the helper, "
            "and the helper decides what CLASS a polymorphic association resolves "
            "to -- a decision the shared SingularAssociation#find_target target "
            "then builds its note from. Under Rule T a note-shape change in a "
            "shared file restarts every endpoint already closed against the old "
            "shape, so this is a deliberate piece of work, not a copy."),
        "why": (
            "`BelongsToPolymorphicAssociation#klass` is ActiveRecord internals: "
            "`type.presence && type.constantize`. Nothing about it is specific to "
            "comments; any endpoint touching a polymorphic belongs_to on a "
            "symbolic record hits the same SymbolicString#split wall."),
        "targets": [
            "ActiveRecord::Associations::BelongsToPolymorphicAssociation#klass",
        ],
    },
    "federation_discovery": {
        "tier": "core-eligible",
        "blocker": (
            "The body is a batch-local `discovery_returns` lambda and depends on "
            "`ConcolicDiscoveryNewShim`, a prepend the batch installs on "
            "`Discovery.new`. Both would have to move together."),
        "why": (
            "`Discovery#fetch_and_save` is NETWORK I/O. It is a wall for every "
            "endpoint that can reach an unknown diaspora handle, which is every "
            "endpoint that renders a mention."),
        "targets": ["DiasporaFederation::Discovery::Discovery#fetch_and_save"],
    },
    "batch_local_probes": {
        "tier": "local",
        "why": (
            "The receiver class does not exist until the batch's own install! "
            "creates it with `Object.const_set`. `CommentsInertDiscovery` is a "
            "comments-index stand-in class; `ConcolicThroughLoadProbe` is a "
            "no-op module that exists ONLY to mint one symbolic_call event "
            "carrying a through-load intermediate statement. A target whose "
            "RECEIVER is invented by one batch cannot be shared -- there is "
            "nothing app-wide to point at."),
        "targets": [
            "CommentsInertDiscovery#fetch_and_save",
            "ConcolicThroughLoadProbe.load_intermediate",
        ],
    },
}

# ---------------------------------------------------------------------------
# TARGET_FUNCTIONs that a batch file declares and the core does not.
# The ruling puts target functions in the core; these are the exceptions and
# the backlog, each with its reason.
# ---------------------------------------------------------------------------
TF_GROUPS = {
    "association_write_boundary": {
        "tier": "core",
        "reclassified": "SHIM -> TARGET_FUNCTION, 2026-09-26 (D7a). Was in the "
                        "association_plumbing shim group.",
        "why": (
            "`collection.create(attrs)` BUILDS AND SAVES: its real body is an "
            "INSERT into the association's table, and on an aspects#create it is "
            "the write the controller action exists to perform. A SHIM asserts "
            "the opposite -- that the real body issues no SQL -- so the old "
            "declaration was wrong twice over: a shim is not an access, and "
            "carrying no note there was nothing to record even if it had been. "
            "As a TARGET_FUNCTION it joins the ActiveRecord access boundary and "
            "the ruling puts it in the core without further argument. It is "
            "APP-GENERAL: this is ActiveRecord's own CollectionProxy, reachable "
            "from every endpoint, and the note now renders through the same "
            "`dml_note` as every other write, on a symbolic instance of the "
            "association's OWN class (it had been hard-coded to AspectMembership, "
            "one endpoint's join model, which is not a property of CollectionProxy). "
            "It keeps a group of its own rather than folding into "
            "activerecord_access_boundary so the reclassification stays visible "
            "to anyone reading this file."),
        "targets": ["ActiveRecord::Associations::CollectionProxy#create"],
    },
    "app_write_boundary_unhomed": {
        "tier": "core",
        "reclassified": "SHIM -> TARGET_FUNCTION, 2026-09-26 (D7a). Was in the "
                        "write_path_walls shim group.",
        "caveat": "APP-SPECIFIC, and the only core target function that is. "
                  "Structurally it belongs in an endpoint layer that does not "
                  "exist yet -- see 'homeless'.",
        "homeless": (
            "Unlike every other row in the core, this is not framework code and "
            "not a shared model reader: it is diaspora's own PostService, reached "
            "only by the endpoints that mark a post's notifications read. It sits "
            "in the shared core because the kind-axis ruling puts TARGET_FUNCTIONs "
            "there and because no endpoint layer exists to hold it -- not because "
            "anyone established it is app-wide. If an endpoint layer for the "
            "posts/notifications family is ever written, this is the first row "
            "that should move into it, and moving it would COST NOTHING to the "
            "two closed endpoints: neither aspect_memberships_create nor "
            "comments_index reaches PostService#mark_user_notifications."),
        "open_question": (
            "The declaration carries a NAMED RESIDUAL GAP, written at its own "
            "site in targets/core.rb: its real body issues FOUR statements and "
            "the note is STATEMENT 1 ONLY. Statement 4 is gated on "
            "`mention_ids.any?`, and folding it into one unconditional note would "
            "collapse a conditional access into an unconditional one -- the "
            "over-disclosing direction. The complete fix is to DELETE the "
            "declaration so the real body runs and each inner call reaches its "
            "own declared target (`Relation#update_all` twice, two finders), "
            "which is four correctly-attributed accesses with the conditional "
            "intact. What blocks that is the symbolic-int-into-a-real-`where` "
            "wall that `CastableSymbolicInt` in the aspect_memberships endpoint "
            "layer already solves and which is app-general; promoting it changes "
            "which targets fire on posts_show, so it was not done."),
        "why": (
            "TARGET_FUNCTION because its real body issues SQL -- four statements, "
            "two `update_all` calls and two finders. The old SHIM declaration "
            "asserted the opposite and hid all four."),
        "targets": ["PostService#mark_user_notifications"],
    },
    "framework_collection_boundary": {
        "tier": "core-eligible",
        "blocker": (
            "The four CollectionProxy mocks and `Base#reload` build their notes "
            "through `CommentsTargets`' statement helpers, which the batch keeps "
            "local ON PURPOSE -- `aspect_memberships_create/targets.rb:60` says it "
            "outright: the note helpers were 'kept batch-local rather than pushed "
            "into the shared config: the shared copy is app-wide (Rule T) and a "
            "note-shape change there restarts every endpoint'. Promoting the "
            "declarations without the helpers changes their notes; promoting the "
            "helpers restarts two closed endpoints. Either way it is a scheduled "
            "piece of work with a re-run attached, not a file move."),
        "why": (
            "These are the same framework boundary the core already declares on "
            "`ActiveRecord::Relation` (to_a / to_ary / records) and "
            "`SingularAssociation` (find_target), one association class over. "
            "`BelongsToPolymorphicAssociation#find_target` is the strongest case "
            "of the five: results3/notifications_index declared it IN ITS CORE. "
            "It was demoted to a batch file somewhere between results3 and "
            "results4, and nothing in either file says why."),
        "targets": [
            "ActiveRecord::Associations::BelongsToPolymorphicAssociation#find_target",
            "ActiveRecord::Associations::CollectionProxy#to_a",
            "ActiveRecord::Associations::CollectionProxy#to_ary",
            "ActiveRecord::Associations::CollectionProxy#records",
            "ActiveRecord::Associations::CollectionProxy#load_target",
            "ActiveRecord::Base#reload",
        ],
    },
    "call_site_naming_aliases": {
        "tier": "local",
        "why": (
            "THE REAL EXCEPTION TO 'TARGET FUNCTIONS ARE STANDARD', and worth "
            "stating plainly. These are not methods the app has. The batch creates "
            "an ALIAS of a real finder under an invented name "
            "(`ci_vis_first`, `mention_lookup_msg_retry`, ...) and routes ONE call "
            "site to it, so that call site gets its own symbolic variable name "
            "instead of sharing `SYM_RESULT_..._first_N` with every other finder. "
            "The kind is genuinely TARGET_FUNCTION -- each one issues real SQL -- "
            "but the NAME is a property of one endpoint's control-flow graph. "
            "Promoting them to the core would put another endpoint's call-site "
            "names into every run. They stay local, and the ruling should be read "
            "as: target functions are standard, EXCEPT where the target is a "
            "synthetic per-call-site alias."),
        "targets": [
            "ActiveRecord::FinderMethods#ci_vis_first",
            "ActiveRecord::FinderMethods#ci_author_first",
            "ActiveRecord::FinderMethods#ci_public_first",
            "ActiveRecord::Core::ClassMethods#mention_lookup_msg_first",
            "ActiveRecord::Core::ClassMethods#mention_lookup_msg_retry",
            "ActiveRecord::Core::ClassMethods#mention_lookup_json_first",
            "ActiveRecord::Core::ClassMethods#mention_lookup_json_retry",
        ],
    },
    "devise_session_alias": {
        "tier": "core-eligible",
        "blocker": (
            "BOTH gold batches declare it, with the SAME kind and the SAME type "
            "and DIFFERENT BODIES: aspect_memberships_create returns a bare "
            "\"concolicsalt\" String from the salt leaf, comments_index wraps the "
            "same string in `ConcreteSymbolicString`; each calls its own batch's "
            "`finder_note`. Promoting means choosing one body, which changes the "
            "other endpoint's dumps. The CONTRACT is already agreed and could be "
            "promoted today; the BODY is the open question."),
        "why": (
            "It is the same alias trick as call_site_naming_aliases, but over the "
            "Devise session lookup, which every authenticated endpoint performs "
            "identically -- the one alias in the corpus whose call site is not "
            "endpoint-specific. Two independent batches arrived at the same "
            "declaration without coordinating, which is the strongest evidence of "
            "app-wideness this corpus can produce."),
        "targets": ["ActiveRecord::FinderMethods#devise_user_first"],
    },
}

CORE_TF_WHY = (
    "TARGET_FUNCTION by the user's ruling: the app-wide access boundary. These "
    "are the ActiveRecord query and DML entry points -- finders, existence "
    "probes, materialisation, calculations, batches, DML, raw SQL -- plus the two "
    "app-level readers the corpus treats the same way (`User#blocks`, "
    "`SingularAssociation#find_target`). The run is ABOUT these calls: each is an "
    "access, each may terminate an atom, and its return becomes the next symbolic "
    "variable. Nothing here can be endpoint-specific without the endpoints "
    "disagreeing about what an access IS.")


def main():
    manifest = json.load(open(os.path.join(INV, "manifest.json")))
    decls = manifest["declarations"]

    core_tf = sorted({d["target"] for d in decls
                      if d["layer"] == "core" and d["kind"] == "target_function"})
    core_shim = sorted({d["target"] for d in decls
                        if d["layer"] == "core" and d["kind"] == "shim"})
    core_targets = set(core_tf) | set(core_shim)
    local_new = sorted({d["target"] for d in decls
                        if d["layer"] == "local" and not d["redeclares_core"]})

    rows = []
    # built AFTER `assigned`, below, so a core TF the table speaks about keeps
    # its own group instead of being swallowed by the default one.

    assigned = {}
    for gname, g in list(SHIM_GROUPS.items()) + list(TF_GROUPS.items()):
        for t in g["targets"]:
            if t in assigned:
                sys.exit("target %r is in two groups: %s and %s" % (t, assigned[t], gname))
            assigned[t] = gname

    for t in core_tf:
        if t in assigned:
            continue
        rows.append({"target": t, "kind": "target_function", "tier": "core",
                     "group": "activerecord_access_boundary",
                     "lives_in": "targets/core.rb", "rationale": CORE_TF_WHY})

    # --- the table must cover exactly the corpus -----------------------------
    #
    # Core TARGET_FUNCTIONs need no triage -- the ruling assigns them -- so they
    # default into `activerecord_access_boundary` and are NOT required here. But
    # the table MAY name one explicitly, and must be able to: a shim reclassified
    # as a target function (D7a, 2026-09-26) keeps its written reason, and a core
    # target function that is app-specific rather than framework needs one. So
    # `must_cover` is the triaged population PLUS whatever core target functions
    # the table chooses to speak about.
    named_core_tf = {t for g in list(SHIM_GROUPS.values()) + list(TF_GROUPS.values())
                     for t in g["targets"] if t in set(core_tf)}
    must_cover = set(core_shim) | set(local_new) | named_core_tf
    missing = sorted(must_cover - set(assigned))
    extra = sorted(set(assigned) - must_cover)
    if missing or extra:
        sys.exit("partition table out of sync with manifest.json\n"
                 "  not assigned to any group: %s\n"
                 "  assigned but not in corpus: %s" % (missing, extra))

    kinds = {d["target"]: d["kind"] for d in decls}
    lives = {}
    for d in decls:
        if d["layer"] == "local" and not d["redeclares_core"]:
            lives[d["target"]] = "%s (%s)" % (d["source_file"], d["endpoint"])

    for gname, g in list(SHIM_GROUPS.items()) + list(TF_GROUPS.items()):
        for t in g["targets"]:
            row = {
                "target": t,
                "kind": kinds[t],
                "tier": g["tier"],
                "group": gname,
                "lives_in": ("targets/core.rb" if t in core_targets
                             else g.get("lifted_to", lives.get(t, "?"))),
                "rationale": g["why"],
            }
            for k in ("blocker", "caveat", "lifted_from", "reclassified",
                      "homeless", "open_question"):
                if k in g:
                    row[k] = g[k]
            rows.append(row)

    by_tier = {}
    for r in rows:
        by_tier[r["tier"]] = by_tier.get(r["tier"], 0) + 1

    out = {
        "_ruling": [
            "The user's ruling for this lab, verbatim: \"The target functions are",
            "standard across endpoints. The shim mocks some can be standardized",
            "while others are local.\"",
            "So: every kind: TARGET_FUNCTION goes to the shared core, and every",
            "kind: SHIM is triaged one at a time. The triage lives in",
            "tools/build_partition.py with a written reason per group; the target",
            "set, kinds and types come from inventory/manifest.json and the",
            "generator FAILS if the two disagree.",
            "ONE EXCEPTION TO THE TARGET-FUNCTION HALF was found and is not",
            "papered over: 7 of the corpus's target functions are SYNTHETIC",
            "PER-CALL-SITE ALIASES (group call_site_naming_aliases). They issue",
            "real SQL, so TARGET_FUNCTION is right, but their NAMES belong to one",
            "endpoint's control-flow graph. See that group's rationale.",
        ],
        "tiers": {
            "core": "in targets/core.rb today, and belongs there",
            "core-promoted": "lifted by this lab into targets/shared_shims.rb",
            "core-eligible": "app-wide in substance, still in a batch file; see blocker",
            "local": "endpoint-local by construction; promoting it would be wrong",
        },
        "counts": {
            "by_tier": by_tier,
            "core_target_function": len(core_tf),
            "core_shim": len(core_shim),
            "local_new_declarations": len(local_new),
        },
        "groups": dict(
            [("activerecord_access_boundary",
              {"tier": "core", "why": CORE_TF_WHY,
               "note": "the core TARGET_FUNCTIONs the triage table does not "
                       "speak about individually; assigned by the ruling, not "
                       "by the table"})] +
            [(gname, {k: v for k, v in g.items() if k != "targets"})
             for gname, g in list(SHIM_GROUPS.items()) + list(TF_GROUPS.items())]
        ),
        "targets": sorted(rows, key=lambda r: (r["tier"], r["group"], r["target"])),
    }
    json.dump(out, open(os.path.join(INV, "partition.json"), "w"), indent=2)
    print("partition: %d target rows; %s" % (len(rows), by_tier))


if __name__ == "__main__":
    main()
