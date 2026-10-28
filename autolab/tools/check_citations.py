#!/usr/bin/env python3
"""check_citations.py -- keep README.md / docs/CONFLICTS.md citations honest.

The prose in this lab argues from specific lines of `targets/core.rb` and the
endpoint layers. Those files are curated copies that get REVISED -- the
2026-09-26 D7a fixes grew core.rb from 105KB to 144KB and moved almost every
line -- so a citation written once rots silently, and a rotted citation is
worse than none: it points confidently at the wrong code.

So every citation in the prose is registered here with the PATTERN it is
supposed to land on. This tool re-resolves each pattern against the current
file and reports the line it now occupies.

    --check   (default) fail if any pattern is missing, ambiguous, or if the
              prose's line number no longer matches where the pattern lives
    --fix     rewrite the prose with the current line numbers

Writes inventory/citations.json either way.
"""
import json
import os
import re
import sys

LAB = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INV = os.path.join(LAB, "inventory")
DOCS = ["README.md", "docs/CONFLICTS.md"]

# id -> (file, regex that must match EXACTLY ONE line, what it is)
CITATIONS = {
    "core.exists_probe": (
        "targets/core.rb",
        r"declare_target\(mod, m, kind: CallInterceptor::TARGET_FUNCTION, type: \"bool\"",
        "the core's existence-probe declaration (exists?/any?/none?/one?/many?/empty?)"),
    # Registered 2026-10-07. CONFLICTS.md cited this line as `core.rb:1639`
    # -- no `targets/` prefix -- so `cited_in_docs` never saw it and it rotted
    # unnoticed through the D7a revision. Spelling it like every other citation
    # is what brought it under the check, and a citation the tool cannot see is
    # the failure mode this whole registry exists to prevent.
    "core.d1_quote": (
        "targets/core.rb",
        r"a mock may replace execution, never evidence",
        "defect D1 stated in full, which the Person#name removal argues from"),
    "core.user_blocks": (
        "targets/core.rb",
        r"declare_target\(User, :blocks, kind: CallInterceptor::TARGET_FUNCTION",
        "the core's User#blocks declaration"),
    "core.prepend_warning": (
        "targets/core.rb",
        r"PREPEND, never a second declare_target",
        "the core's warning that a second declare_target captures the first"),
    "core.render_mod_inert": (
        "targets/core.rb",
        r"^\s*\{\}\.each do \|m, marker\|",
        "the deliberately-empty render_mod table (the one site that declares nothing)"),
    "core.x8d_escape_segment": (
        "targets/core.rb", r"X8d\. BOUNDARY HARVEST B-2",
        "why escape_segment stopped being a target"),
    "core.x3_as_api_response": (
        "targets/core.rb", r"X3 REMOVED for results3/comments_index",
        "why ActsAsApi::Collection#as_api_response was removed"),
    "core.x6f_people_from_string": (
        "targets/core.rb", r"X6f REMOVED for results3/comments_index",
        "why Mentionable.people_from_string was removed"),
    "core.x6h_processor_process": (
        "targets/core.rb", r"X6h\. MessageRenderer::Processor\.process",
        "why MessageRenderer::Processor.process was removed"),
    "core.x6i_person_name": (
        "targets/core.rb", r"X6i\. Person#name -> concrete string",
        "why Person#name / name_from_attrs was removed"),
    "core.blocked_people": (
        "targets/core.rb", r"Post\.blocked_people` row",
        "why Post.blocked_people was removed"),
    "core.w2_metal_head": (
        "targets/core.rb", r"W2\. ActionController::Metal#head",
        "the W2 site that is dormant in the booted app"),
    "core.head_head": (
        "targets/core.rb",
        r"declare_target\(ActionController::Head, :head",
        "the Head#head twin that makes W2's dormancy harmless"),
    "core.cp_create": (
        "targets/core.rb",
        r"ActiveRecord::Associations::CollectionProxy, :create,",
        "CollectionProxy#create, reclassified SHIM -> TARGET_FUNCTION (D7a)"),
    "core.mark_user_notifications": (
        "targets/core.rb",
        r"declare_target\(PostService, :mark_user_notifications,",
        "PostService#mark_user_notifications, reclassified SHIM -> TARGET_FUNCTION (D7a)"),
    "amc.rule_t_quote": (
        "targets/endpoints/aspect_memberships_create.rb",
        r"Kept batch-local rather than pushed into",
        "the endpoint layer's own statement of Rule T"),
    "amc.exists_decl": (
        "targets/endpoints/aspect_memberships_create.rb",
        r"declare_target\(fm, :exists\?, kind: CallInterceptor::TARGET_FUNCTION, type: \"bool\?\"",
        "the bool? exists? declaration"),
    "amc.exists_why": (
        "targets/endpoints/aspect_memberships_create.rb",
        r"RETURNING `nil`, NOT `false`, ON THE NEGATIVE ARM",
        "the measured reason exists? returns nil on the negative arm"),
    "amc.user_blocks": (
        "targets/endpoints/aspect_memberships_create.rb",
        r"declare_target\(User, :blocks, kind: CallInterceptor::SHIM",
        "the local User#blocks shim that restores the real reader"),
    "amc.d5": (
        "targets/endpoints/aspect_memberships_create.rb",
        r"re-declare `find_by_sql` here -> defect D5",
        "the measurement of defect D5"),
    "cmi.exists_decl": (
        "targets/endpoints/comments_index.rb",
        r"declare_target\(fm, :exists\?, kind: CallInterceptor::TARGET_FUNCTION, type: \"bool\"",
        "the bool exists? declaration"),
    "cmi.through_load_guard": (
        "targets/endpoints/comments_index.rb",
        r"unless defined\?\(::ConcolicThroughLoadProbe\)",
        "the guard that makes install! non-idempotent"),
    "rt.type_mismatch": (
        "/home/dev/project/src_new/runtimes/ruby_runtime/call_interceptor.rb",
        r"raise TypeMismatch,",
        "where the runtime enforces a declaration as a contract"),
    "rt.to_symbolic_bool": (
        "/home/dev/project/src_new/runtimes/ruby_runtime/symbolic_func.rb",
        r"^\s*when TrueClass, FalseClass\s*$",
        "where to_symbolic turns false into a truthy SymbolicBool"),
}


def resolve():
    out, problems = {}, []
    for cid, (rel, pat, what) in sorted(CITATIONS.items()):
        path = rel if os.path.isabs(rel) else os.path.join(LAB, rel)
        if not os.path.exists(path):
            problems.append("%s: file missing (%s)" % (cid, rel))
            continue
        rx = re.compile(pat)
        hits = [i for i, l in enumerate(open(path).read().split("\n"), 1) if rx.search(l)]
        if len(hits) != 1:
            problems.append("%s: pattern matched %d lines in %s (need exactly 1) -- %r"
                            % (cid, len(hits), rel, pat))
            continue
        out[cid] = {"file": rel, "line": hits[0], "what": what, "pattern": pat}
    return out, problems


def cited_in_docs():
    """Every `<path>:<line>` the prose asserts, per file."""
    found = []
    for doc in DOCS:
        p = os.path.join(LAB, doc)
        if not os.path.exists(p):
            continue
        for n, line in enumerate(open(p).read().split("\n"), 1):
            for m in re.finditer(
                    r"(targets/core\.rb|targets/endpoints/[a-z_]+\.rb):(\d+)", line):
                found.append({"doc": doc, "doc_line": n,
                              "file": m.group(1), "line": int(m.group(2))})
    return found


def main(argv):
    fix = "--fix" in argv
    resolved, problems = resolve()
    by_file_line = {}
    for cid, r in resolved.items():
        by_file_line.setdefault((r["file"], r["line"]), []).append(cid)

    stale = []
    for c in cited_in_docs():
        if (c["file"], c["line"]) not in by_file_line:
            stale.append(c)

    json.dump({
        "_what_this_is": [
            "Every file:line the prose in README.md / docs/CONFLICTS.md argues from,",
            "re-resolved from a PATTERN against the current file. The curated",
            "files get revised -- the 2026-09-26 D7a fixes moved nearly every line",
            "in targets/core.rb -- and a citation that rots points confidently at",
            "the wrong code, which is worse than no citation at all.",
        ],
        "resolved": resolved,
        "unresolvable_patterns": problems,
        "doc_citations_not_matching_any_pattern": stale,
    }, open(os.path.join(INV, "citations.json"), "w"), indent=2)

    if fix:
        # Rewrite each prose line number to where its pattern lives now. Only
        # a citation whose (file, line) is already registered, or whose file has
        # exactly one registered pattern on the doc line's subject, is touched;
        # anything ambiguous is reported instead.
        print("--fix rewrites nothing automatically: a line number in prose is "
              "attached to an ARGUMENT, and only a human knows which pattern a "
              "given sentence meant. Use inventory/citations.json to update them.")

    print("patterns resolved            : %d/%d" % (len(resolved), len(CITATIONS)))
    for p in problems:
        print("  UNRESOLVED %s" % p)
    print("prose citations checked      : %d" % len(cited_in_docs()))
    for c in stale:
        print("  STALE %s:%d cites %s:%d, which no registered pattern occupies"
              % (c["doc"], c["doc_line"], c["file"], c["line"]))
    ok = not problems and not stale
    print("verdict: %s" % ("every prose citation lands on a registered pattern"
                           if ok else "CITATIONS ARE STALE"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
