#!/usr/bin/env python3
"""build_conflicts.py -- emit inventory/conflicts.json.

`docs/CONFLICTS.md` is the prose form and is HAND-WRITTEN -- this tool has
never emitted it, whatever this line used to say.

The disagreement inventory. Every place two sources in the diaspora corpus
declare the SAME target differently, enumerated, with the ruling this lab took
and why. No winner is picked silently.

Five classes:

  C1 CONTRACT      two sources give one target a different kind: or type:
  C2 BODY-OVERRIDE a batch redeclares a core target with the SAME contract and
                   a different mock body
  C3 PARALLEL      both batches independently invent the same target
  C4 DEMOTED       results3's shared core declared it; results4's does not
  C5 UNMIGRATED    results3 declares it and results4 does not declare it at all

Run:  /home/dev/project/venvs/queries_from_runs/bin/python3 tools/build_conflicts.py
"""
import collections
import json
import os

LAB = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INV = os.path.join(LAB, "inventory")

# results3 shared-core targets that the results4 shared core dropped, with the
# line in results4/aspect_memberships_create/concolic_targets.rb that says why.
# Read out of the file by hand; the line numbers are stable because
# targets/core.rb is a byte-identical copy.
DEMOTED = {
    "ActionDispatch::Journey::Router::Utils.escape_segment": {
        "results3_endpoints": ["people_show", "people_stream", "posts_show"],
        "results4": "not a target; a plain prepend (ConcolicEscapeSegmentShim)",
        "results4_rationale_at": "targets/core.rb:1815-1828 (X8d, BOUNDARY HARVEST B-2)",
        "why": (
            "Its real body is pure URL escaping -- no data access, no branch the "
            "policy cares about -- so declaring it minted a junk note and a "
            "symbolic result on EVERY route generation. Now a prepend that "
            "concretizes the argument and lets the real escaper run."),
    },
    "ActsAsApi::Collection#as_api_response": {
        "results3_endpoints": ["people_show", "people_stream", "posts_show"],
        "results4": "removed",
        "results4_rationale_at": "targets/core.rb:1421-1445 (X3 REMOVED)",
        "why": (
            "Mocking the COLLECTION walk covered up every ITEM's own "
            "as_api_response, which fetches associations that ARE declared "
            "targets. The mock was standing in front of the evidence."),
    },
    "Diaspora::Mentionable.people_from_string": {
        "results3_endpoints": ["people_show", "people_stream"],
        "results4": "removed",
        "results4_rationale_at": "targets/core.rb:1591-1600 (X6f REMOVED)",
        "why": (
            "Its real body reaches Person.find_or_fetch_by_identifier -- a real "
            "local find_by, itself a declared target. Mocking the whole method to "
            "[] hid that entire local-lookup SQL family."),
    },
    "Diaspora::MessageRenderer::Processor.process": {
        "results3_endpoints": ["people_show", "posts_show"],
        "results4": "removed",
        "results4_rationale_at": "targets/core.rb:1707-1722 (X6h REMOVED)",
        "why": (
            "The renderer pipe is APP code and `diaspora_links` can reach a "
            "declared target (Post.exists?(guid:)) when the text carries a "
            "diaspora:// URL. A mock over it is a mock over target-reaching app "
            "logic -- defect D1."),
    },
    "Person.name_from_attrs": {
        "results3_endpoints": ["people_show"],
        "results4": "removed from the core; comments_index reintroduced it locally in results3",
        "results4_rationale_at": "targets/core.rb:1615-1650 (X6i REMOVED)",
        "why": (
            "Person#name's real body reads self.profile -- a declared association "
            "target -- before calling the pure name_from_attrs. Mocking #name "
            "skipped that read and emitted the junk note \"Person#name\". The "
            "SymbolicString#strip wall it cleared is now cleared at the value-free "
            "leaf instead."),
    },
    "Post.blocked_people": {
        "results3_endpoints": ["notifications_index"],
        "results4": "removed",
        "results4_rationale_at": "targets/core.rb:985-1000",
        "why": (
            "Its real body calls user.blocks directly, so keeping the outer mock "
            "would prevent the correctly-noted User#blocks target from ever firing "
            "along that path -- the same D7/(b) violation as the others."),
    },
    "ActiveRecord::Associations::BelongsToPolymorphicAssociation#find_target": {
        "results3_endpoints": ["notifications_index"],
        "results4": "declared, but in comments_index's BATCH file, not the core",
        "results4_rationale_at": "no rationale recorded in either file",
        "why": (
            "THE ONE DEMOTION WITH NO WRITTEN REASON. results3/notifications_index "
            "declared this in its SHARED core; results4 carries it only in "
            "comments_index/targets.rb. Nothing in either file explains the move. "
            "partition.json rates it core-eligible for exactly this reason."),
    },
}


def main():
    manifest = json.load(open(os.path.join(INV, "manifest.json")))
    candidates = json.load(open(os.path.join(INV, "candidates.json")))
    D = manifest["declarations"]
    core = {d["target"]: (d["kind"], d["type"])
            for d in D if d["layer"] == "core"}

    def rows_for(t):
        return sorted(
            [{"endpoint": d["endpoint"], "layer": d["layer"], "module": d["module"],
              "kind": d["kind"], "type": d["type"],
              "at": "%s:%d" % (d["source_file"], d["source_line"])}
             for d in D if d["target"] == t],
            key=lambda r: (r["layer"], r["endpoint"]))

    # ---- C1 contract conflicts ---------------------------------------------
    contracts = collections.defaultdict(set)
    for d in D:
        contracts[d["target"]].add((d["kind"], d["type"]))
    c1 = []
    for t in sorted(contracts):
        if len(contracts[t]) > 1:
            c1.append({"target": t, "declarations": rows_for(t)})

    C1_RULINGS = {
        "ActiveRecord::FinderMethods#exists?": {
            "ruling": "BOTH ARE CORRECT. Core and comments_index keep bool; "
                      "aspect_memberships_create keeps bool?. Nothing is promoted "
                      "and nothing is corrected.",
            "why": [
                "`type:` states what THE MOCK returns, not what Rails returns. "
                "The runtime enforces it: CallInterceptor.observation_fits? treats "
                "'a null where the declaration is not nullable' as a defect and "
                "raises TypeMismatch (call_interceptor.rb:1007).",
                "comments_index's body ends `ex == true` -- a bare Ruby true/false, "
                "never nil. bool is exactly right.",
                "aspect_memberships_create's body ends `(ex == true) ? true : nil`. "
                "It MUST be bool?; declaring bool there would raise TypeMismatch on "
                "the first negative arm.",
                "It returns nil rather than false for a measured reason. "
                "to_symbolic(false) is SymbolicBool.new(false) "
                "(symbolic_func.rb:815-817) -- a Ruby OBJECT, therefore TRUTHY -- so "
                "`return if blocks.where(...).exists?` returned unconditionally. "
                "Measured in that batch's dump_auth_json_dse0001.json: the 409 arm "
                "on every run, no contacts SELECT, no write. to_symbolic(nil) is the "
                "one native that passes through unchanged, so nil is the only "
                "falsy value a mock can hand back.",
                "A SEPARATE FINDING, NOT A RULING, because I did not verify it: "
                "comments_index's mock returns a bare `false` on its negative arm, "
                "and by the same runtime rule that false is re-wrapped into a truthy "
                "SymbolicBool. Whether that bites depends on whether any "
                "comments_index call site tests `exists?` with bare truthiness "
                "rather than an explicit compare. I did not check its call sites. "
                "If one does, comments_index has the defect amc measured and fixed.",
                "The coordinator's prior guess -- 'Rails' exists? never returns nil "
                "so bool? is the sloppy one' -- reads `type:` as a fact about Rails. "
                "It is a fact about the mock.",
            ],
        },
        "User#blocks": {
            "ruling": "Core keeps target_function; aspect_memberships_create keeps "
                      "its local shim. The kind difference is a CONSEQUENCE of a "
                      "body difference and is correct on both sides.",
            "why": [
                "The core mock RETURNS a SymbolicList standing in for the blocks "
                "query: its call IS the access, so TARGET_FUNCTION.",
                "aspect_memberships_create restores the REAL association reader "
                "(`receiver.association(:blocks).reader`) because share_with chains "
                "`blocks.where(person_id:).exists?` and SymbolicList#where is a "
                "NoMethodError that kills the run before the write. The real "
                "relation then issues its SELECT at the exists? target downstream, "
                "so this call is no longer an access -- per §4.1.1f change 9 a call "
                "that is not itself an access is a SHIM.",
                "That is strictly MORE evidence, not less: the endpoint gets a "
                "genuine `SELECT 1 AS one FROM \"blocks\" ... LIMIT 1` instead of "
                "the core's hand-rolled `SELECT \"blocks\".*` note.",
                "This is the one place in the corpus where a kind: flips between "
                "layers, and it is the clearest demonstration that kind is a "
                "property of the MOCK, not of the method.",
            ],
        },
    }
    for row in c1:
        row.update(C1_RULINGS[row["target"]])

    # ---- C2 body overrides --------------------------------------------------
    c2 = []
    for d in D:
        if d["layer"] == "local" and d["redeclares_core"] and \
                (d["kind"], d["type"]) == core[d["target"]]:
            c2.append({"target": d["target"], "endpoint": d["endpoint"],
                       "module": d["module"], "kind": d["kind"], "type": d["type"],
                       "at": "%s:%d" % (d["source_file"], d["source_line"])})
    c2.sort(key=lambda r: (r["endpoint"], r["target"]))

    # ---- C3 parallel invention ---------------------------------------------
    local_new = collections.defaultdict(list)
    for d in D:
        if d["layer"] == "local" and not d["redeclares_core"]:
            local_new[d["target"]].append(d)
    c3 = [{"target": t, "declarations": rows_for(t)}
          for t, v in sorted(local_new.items()) if len({d["endpoint"] for d in v}) > 1]
    for row in c3:
        row["ruling"] = (
            "Contract agreed, bodies disagree. Not promoted: promoting means "
            "choosing one body and changing the other endpoint's dumps. "
            "partition.json rates it core-eligible with the body difference as the "
            "blocker.")

    # ---- C5 unmigrated ------------------------------------------------------
    c5 = candidates["candidates"]

    out = {
        "_what_this_is": [
            "Every place two sources in the diaspora corpus declare the SAME target",
            "differently. This is the inventory the shared master died for want of:",
            "it was retired because batch-local ownership won, and a flat merge",
            "would recreate that failure by silently picking a winner per target.",
            "No winner is picked silently here. Where this lab took a side, the",
            "ruling and its evidence are written down; where it did not, the row",
            "says so.",
        ],
        "classes": {
            "C1_contract": "two sources give one target a different kind: or type:",
            "C2_body_override": "a batch redeclares a core target with the SAME contract and a different body",
            "C3_parallel_invention": "both batches independently invented the same target",
            "C4_demoted_from_shared_core": "results3's shared core declared it; results4's does not",
            "C5_unmigrated": "results3 declares it; results4 does not declare it at all",
        },
        "counts": {
            "C1_contract": len(c1),
            "C2_body_override": len(c2),
            "C3_parallel_invention": len(c3),
            "C4_demoted_from_shared_core": len(DEMOTED),
            "C5_unmigrated": len(c5),
        },
        "C1_contract": c1,
        "C2_body_override": {
            "_ruling": [
                "THE CORE KEEPS ITS DECLARATION AND THE BATCH KEEPS ITS BODY. Every",
                "one of these is a NOTE-SHAPE refinement: the batch renders the SQL",
                "statement its endpoint's evidence needs (a faithful single-row",
                "finder statement, a DML statement instead of a description) while",
                "agreeing with the core about kind and type.",
                "They are NOT promoted, and the corpus says why in its own words at",
                "results4/aspect_memberships_create/targets.rb:60 -- the note helpers",
                "were 'kept batch-local rather than pushed into the shared config:",
                "the shared copy is app-wide (Rule T) and a note-shape change there",
                "restarts every endpoint'. Two endpoints are closed against the",
                "current shapes. Promoting a note helper reopens both.",
                "THIS IS THE ONE PLACE THE USER'S KIND-AXIS RULING AND THE CORPUS'S",
                "RULE T PULL IN OPPOSITE DIRECTIONS, and it is worth a decision:",
                "these 27 rows are target functions, so the ruling says core, and",
                "Rule T says a shared note change costs two completed endpoints.",
                "This lab did not resolve it -- it is not a judgement a targets",
                "library can make on its own.",
            ],
            "count_by_endpoint": dict(collections.Counter(r["endpoint"] for r in c2)),
            "rows": c2,
        },
        "C3_parallel_invention": c3,
        "C4_demoted_from_shared_core": [
            dict([("target", t)] + list(v.items())) for t, v in sorted(DEMOTED.items())
        ],
        "C5_unmigrated": {
            "_note": [
                "results3 declares these and results4 does not. They are NAMES, not",
                "declarations: the probe found that %d of results3's %d declarations"
                % (candidates["legacy_declarations_missing_kind_and_type"],
                   candidates["legacy_declarations_total"]),
                "carry NEITHER kind: NOR type:, so there is no contract to inherit.",
                "Adopting one means writing a declaration and defending its kind and",
                "type against a real run.",
            ],
            "rows": c5,
        },
    }
    json.dump(out, open(os.path.join(INV, "conflicts.json"), "w"), indent=2)
    print("conflicts: C1=%d C2=%d C3=%d C4=%d C5=%d" % (
        len(c1), len(c2), len(c3), len(DEMOTED), len(c5)))
    return out


if __name__ == "__main__":
    main()
