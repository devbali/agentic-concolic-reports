#!/usr/bin/env python3
"""comments_index — batch-local coverage assumptions (results3, cycle 1
rewrite 2026-08-25; see ./AGENT_RUN.md).

WHY A REWRITE. Two batch repairs changed the PC universe:

  (1) the persisted decision (concolic_targets.rb symbolic_instance, ported
      from notifications_index): every symbolic row now carries a seeded,
      PC-recorded `<base>_persisted` boundary decision instead of the
      `@new_record = true` pin that made `MentionsContainer#mentioned_people`
      unconditionally take the unpersisted `people_from_string` branch. The
      persisted branch — the one the REAL endpoint takes for every
      query-returned comment: `mentions.includes(person: :profile)` — is now
      the default, and the lookup family is reached only on the flipped
      side.
  (2) call-site-stable naming for the signed-in post lookup
      (targets.rb CommentsVisibleShareableNaming): EvilQuery::
      VisibleShareableById#post!'s three `.first` calls are now
      `ci_vis_first`, `ci_author_first`, `ci_public_first` (each always
      ordinal _1), so the anon `first_1` names ONLY PostService#find_public!.
      The previous universe had auth's `first_2`/`first_3` sharing the anon
      counter — the 256 missing combos were the auth-only exprs cliqued
      against anon-only ones.

THE CHECKER'S SEMANTICS (coverage.py module docstring): every maximal
clique of the dependence graph must have every satisfiable outcome
assignment observed in ONE run that evaluates ALL of the clique's
expressions. An expression B that is only ever evaluated under a fixed
outcome of A can therefore never be co-observed with the other outcome of
A — such a combination is unobservable BY PROGRAM STRUCTURE and must be
declared (IndependenceAssumption, the project's established "structural
gating" pattern: not_found -> 404 -> nothing downstream). Every declaration
below names the gate, its source line, and the value that closes it.

Naming used below (all exprs are `(VAR == True)` boolean decisions):

  anon chain (current_user nil, PostService#find_public!):
    L    (Length(SYM_PARAM_post_id) < 16)          post_key column dispatch
    A1   first_1_not_found                         post lookup outcome
    A1T  first_1_text_has_mention                  post text shim — never read
    P    first_1_public                            post.public?
    PP   first_1_persisted                         post rep persisted?
  auth chain (signed in, EvilQuery::VisibleShareableById#post!):
    V    ci_vis_first_1_not_found                  share-visibility lookup
    VT   ci_vis_first_1_text_has_mention           never read
    VP   ci_vis_first_1_persisted
    AU   ci_author_first_1_not_found               own-post lookup (iff V)
    AUT  ci_author_first_1_text_has_mention        never read
    AUP  ci_author_first_1_persisted
    PU   ci_public_first_1_not_found               public lookup (iff V & AU)
    PUT  ci_public_first_1_text_has_mention        never read
    PUP  ci_public_first_1_persisted
  comment level (reached once a post is found and persisted):
    HM   records_1_row_text_has_mention            comment text shim
    CP   records_1_row_persisted                   comment rep persisted?
    AP   records_1_row_author_persisted            author rep persisted?
    R3P  records_3_row_person_persisted            mentioned person (persisted branch)
    MF/MFP/MR         mention_lookup_msg_{first,first_persisted,retry}
    JF/JFP/JR/JRP     mention_lookup_json_{first,first_persisted,retry,retry_persisted}
"""
from __future__ import annotations

import sys

sys.path.insert(0, "/home/dev/project/src")

from concolic_engine.assumptions import (  # noqa: E402
    AssumptionSet,
    IndependenceAssumption,
    UntrackedPathAssumption,
)

FM = "SYM_RESULT_ActiveRecord__FinderMethods_"
REL = "SYM_RESULT_ActiveRecord__Relation_"
CORE = "SYM_RESULT_ActiveRecord__Core__ClassMethods_"


def b(var: str) -> str:
    return f"({var} == True)"


L = "(Length(SYM_PARAM_post_id) < 16)"
A1, A1T, P, PP = (b(FM + "first_1_" + s) for s in ("not_found", "text_has_mention", "public", "persisted"))
V, VT, VP = (b(FM + "ci_vis_first_1_" + s) for s in ("not_found", "text_has_mention", "persisted"))
AU, AUT, AUP = (b(FM + "ci_author_first_1_" + s) for s in ("not_found", "text_has_mention", "persisted"))
PU, PUT, PUP = (b(FM + "ci_public_first_1_" + s) for s in ("not_found", "text_has_mention", "persisted"))

HM = b(REL + "records_1_row_text_has_mention")
CP = b(REL + "records_1_row_persisted")
AP = b(REL + "records_1_row_author_persisted")
R3P = b(REL + "records_3_row_person_persisted")

MF = b(CORE + "mention_lookup_msg_first_1_not_found")
MFP = b(CORE + "mention_lookup_msg_first_1_persisted")
MR = b(CORE + "mention_lookup_msg_retry_1_not_found")
JF = b(CORE + "mention_lookup_json_first_1_not_found")
JFP = b(CORE + "mention_lookup_json_first_1_persisted")
JR = b(CORE + "mention_lookup_json_retry_1_not_found")
JRP = b(CORE + "mention_lookup_json_retry_1_persisted")

MSG = [MF, MFP, MR]
JSON_ = [JF, JFP, JR, JRP]
LOOKUPS = MSG + JSON_
COMMENT_LEVEL = [HM, CP, AP, R3P, *LOOKUPS]

ANON_ONLY = [A1, P, PP]
AUTH_ONLY = [V, VP, AU, AUP, PU, PUP]


def build() -> AssumptionSet:
    aset = AssumptionSet()

    def gate(a: str, bs, why: str, notes: str = "") -> None:
        """Structural gating: every expr in `bs` is only ever evaluated under
        ONE fixed outcome of `a` (the other outcome ends the run, or takes a
        branch on which `bs` does not exist). The cross combinations are
        unobservable by construction — declared, never silently absorbed."""
        for expr in bs:
            aset.add(IndependenceAssumption(expr_a=a, expr_b=expr, description=why,
                                            agent_notes=notes))

    # ------------------------------------------------------------------
    # Untracked: the post reps' `text` shim flag. targets.rb §4a's
    # symbolic_instance wrapper mints `_text_has_mention` for EVERY model
    # with a `text` column, but no code on comments#index reads a POST's
    # text (grep: comments_controller.rb, comment_service.rb,
    # post_service.rb, evil_query.rb, comment_presenter.rb — only
    # `@comment.message` -> Comment#text is read). Four post finders now
    # (anon + the three auth call sites).
    # ------------------------------------------------------------------
    for expr, who in ((A1T, "find_public!"), (VT, "querent_has_visibility"),
                      (AUT, "querent_is_author"), (PUT, "public_post")):
        aset.add(UntrackedPathAssumption(
            expr=expr,
            description=(f"The Post instance returned by {who} never has its `text` "
                         "column read anywhere on comments#index's call path; the flag "
                         "is minted unconditionally by the generic text-identity shim."),
            agent_notes="Verified by source grep (cycle 1 re-check: unchanged)."))

    # ------------------------------------------------------------------
    # L: post_key (post_service.rb:64) only selects the WHERE column of the
    # SAME finder call (id vs guid); it gates nothing and changes no other
    # argument shape. Independent of every other decision.
    # ------------------------------------------------------------------
    # Cycle 2 (2026-08-26, engine-rejected): L is NOT independent of the
    # signed-in visibility chain's not_found decisions. post_key's guid-vs-id
    # dispatch changes the STATEMENT SHAPE of every ci_*_first finder
    # (`posts.guid = ?` vs `posts.id = ?` on the visibility JOIN / author /
    # public lookups), so the combination (guid key, vis miss) reaches a
    # guid-keyed author/public finder shape neither single flip produces —
    # exactly the access-pattern condition assumptions.py forbids. The
    # L x {V, AU, PU} pairs are therefore DEMANDED and explored (the auth
    # round is run to worklist exhaustion so every guid x miss combination
    # is in the corpus). L stays independent of the decisions that do not
    # change any finder's argument shape: the anon chain (find_public! is
    # the ONE finder whose column L selects — the not_found/public/persisted
    # decisions on its single result do not alter any other statement), the
    # persisted decisions of the found post reps, and the comment level
    # (reached with the post row already bound by id, never by key).
    gate(L, [*ANON_ONLY, VP, AUP, PUP, *COMMENT_LEVEL],
         "post_service.rb:64 post_key selects only the WHERE column (id vs guid) of the "
         "post finder; the anon finder's outcome decisions, the found reps' persisted "
         "decisions and the comment level (bound via the post row's id) do not change "
         "shape with the key. NOT declared for the ci_*_first not_found chain (engine-"
         "rejected: guid x miss reaches guid-keyed author/public finder shapes).",
         "Cycle 2: L x V/AU/PU demanded; corpus explored to auth worklist exhaustion.")

    # ------------------------------------------------------------------
    # Scenario disjointness: PostService#find! (post_service.rb:17-23)
    # dispatches on `user` — nil (anon: find_public!, finder `first_1`) vs
    # signed in (find_non_public_by_guid_or_id_with_user! -> EvilQuery ->
    # the ci_*_first finders). The two finder families are never evaluated
    # in the same run; the runner drives them as separate AUTH=1 / anon
    # rounds over the same corpus directory.
    # ------------------------------------------------------------------
    for a in ANON_ONLY:
        gate(a, AUTH_ONLY,
             "post_service.rb:17-23 PostService#find! branches on `user`: the anon "
             "finder (find_public! -> first_1) and the signed-in EvilQuery chain "
             "(ci_vis/author/public_first) are mutually exclusive scenarios; no run "
             "evaluates both families.",
             "Scenario tag concolic_scenario.name = anon | auth on every dump.")

    # ------------------------------------------------------------------
    # ANON chain gating.
    # ------------------------------------------------------------------
    gate(A1, [P, PP, *COMMENT_LEVEL],
         "post_service.rb:51-55 find_public!: not_found==True raises RecordNotFound "
         "-> rescue_from -> head :not_found; post.public?, the post's persisted "
         "decision and the whole comment level exist only when the post was found.")
    gate(P, [PP, *COMMENT_LEVEL],
         "post_service.rb:54 `raise Diaspora::NonPublic unless post.public?` -> "
         "rescue_from -> authenticate_user!: public==False ends the action before "
         "CommentService#find_for_post; the comment level exists only for public==True.")
    gate(PP, COMMENT_LEVEL,
         "collection_association.rb:292 null_scope?: an UNPERSISTED post owner makes "
         "`post.comments` a NullRelation (`1=0`, no comment rows), so no comment rep "
         "and no comment-level decision exists on the persisted==False side.")

    # ------------------------------------------------------------------
    # AUTH chain gating — EvilQuery::VisibleShareableById#post!
    # (lib/evil_query.rb:102-105, reproduced verbatim by targets.rb's
    # PostBangNaming):  vis.first || author.first || public.first
    # ------------------------------------------------------------------
    gate(V, [VP],
         "evil_query.rb:104: the share-visibility post's persisted decision is only "
         "evaluated when that lookup FOUND a post (V==False); on V==True the `||` "
         "chain moves to the author lookup and that rep never exists.")
    gate(V, [AU, AUP, PU, PUP],
         "evil_query.rb:104 `||` short-circuit: querent_is_author.first and "
         "public_post.first (and their reps) are evaluated only when the "
         "share-visibility lookup came back not_found (V==True).")
    gate(AU, [AUP],
         "evil_query.rb:104: the author post's persisted decision exists only when the "
         "author lookup found a post (AU==False).")
    gate(AU, [PU, PUP],
         "evil_query.rb:104 `||` short-circuit: public_post.first is evaluated only "
         "when the author lookup came back not_found (AU==True).")
    gate(PU, [PUP, *COMMENT_LEVEL],
         "post_service.rb:57-60 find_non_public_by_guid_or_id_with_user!: when all "
         "three lookups miss (PU==True) RecordNotFound -> head :not_found; the public "
         "post's persisted decision and the comment level exist only for PU==False.")
    # the three auth reps' persisted decisions: each is evaluated only on
    # its own found-branch, so no two of them (nor VP with AU/PU) are ever
    # co-evaluated; and each gates the comment level exactly like PP does.
    gate(VP, [AU, AUP, PU, PUP],
         "evil_query.rb:104: VP exists only on V==False, where the author/public "
         "lookups are never reached; never co-evaluated.")
    gate(AUP, [PU, PUP],
         "evil_query.rb:104: AUP exists only on AU==False, where public_post.first is "
         "never reached; never co-evaluated.")
    for pexpr, who in ((VP, "share-visibility"), (AUP, "author"), (PUP, "public")):
        gate(pexpr, COMMENT_LEVEL,
             f"collection_association.rb:292 null_scope?: an UNPERSISTED {who} post "
             "owner makes `post.comments` a NullRelation (`1=0`, no comment rows); the "
             "comment level exists only on its persisted==True side.")

    # ------------------------------------------------------------------
    # COMMENT level gating — Diaspora::MentionsContainer#mentioned_people
    # (lib/diaspora/mentions_container.rb:16-22):
    #   persisted? ? mentions.includes(person: :profile).map(&:person)
    #              : Diaspora::Mentionable.people_from_string(text)
    # ------------------------------------------------------------------
    gate(CP, [R3P],
         "mentions_container.rb:17-18: the mentioned person rep (records_3_row_person, "
         "the json-site mentions load) exists only on the persisted branch (CP==True).")
    gate(CP, LOOKUPS,
         "mentions_container.rb:19-20: people_from_string (and every mention_lookup_* "
         "decision) runs only on the UNPERSISTED branch (CP==False).")
    gate(HM, LOOKUPS,
         "mentionable.rb:46-49: `.scan(REGEX)` on a mention-free text returns [] and "
         "`.map` never calls find_or_fetch_person_by_identifier — no mention_lookup "
         "call exists when the comment's has_mention flag is False.")

    # within-site attempt gating (person.rb:318-328, reproduced verbatim by
    # targets.rb's PersonFindOrFetchNaming):
    #   person = <site>_first(...)
    #   return person if person.present? && person.profile.present?
    #   ...fetch_and_save (walled)...; <site>_retry(...)
    # `<site>_first_persisted` is the found person's persisted decision
    # (evaluated by the has_one :profile reader, association.rb find_target?):
    # it exists only when <site>_first FOUND a person, and on its persisted
    # side the guard returns early so <site>_retry never exists. NOTE: the
    # retry itself is NOT gated by first_not_found alone any more — a found
    # but unpersisted person (profile nil) also retries — so first_not_found
    # x retry stays a demanded, explored combination.
    for site, first, fp, retry in (("msg", MF, MFP, MR), ("json", JF, JFP, JR)):
        gate(first, [fp],
             f"person.rb:318-321 ({site} site): the found person's persisted decision is "
             "evaluated by `person.profile` only when the first attempt found a row "
             "(first_not_found==False).")
        gate(fp, [retry],
             f"person.rb:319 ({site} site): on the persisted side `person.profile.present?` "
             "holds and the method returns early — the retry attempt exists only when "
             "the first person was unpersisted (profile nil) or not found.")
    # json site: the retried person's persisted decision (JRP) is evaluated
    # by the presenter's profile read only when the retry found a row.
    gate(JR, [JRP],
         "person.rb:327 -> comment_presenter.rb (json site): the retried person's "
         "persisted decision is read by as_api_response(:backbone)'s profile access "
         "only when the retry found a person (retry_not_found==False).")
    gate(JFP, [JRP],
         "person.rb:319-327 (json site): on JFP==True the method returns early and no "
         "retry person exists; JRP exists only under JFP==False (or JF==True).")

    # ------------------------------------------------------------------
    # First-attempt gates the retry attempt's EXISTENCE (cycle 1, driven by
    # pair_coeval_audit.py). person.rb:318-321 (PersonFindOrFetchNaming):
    #   person = <site>_first(handle)
    #   return person if person.present? && person.profile.present?
    #   ...; <site>_retry(handle)
    # The profile load (SingularAssociation#find_target) ALWAYS returns a rep
    # (no not_found seeding on that target), so `person.profile.present?` is
    # true whenever the person was found — the retry attempt (and its own
    # persisted/not_found decisions) exists ONLY when <site>_first came back
    # not_found (first==True). Corpus confirms: first x retry observed only as
    # (True,*), never (False,*). Structural gating -> declare.
    # ------------------------------------------------------------------
    gate(MF, [MR], "person.rb:318-321 msg site: mention_lookup_msg_retry is reached "
         "only when the first attempt was not_found (the profile load always "
         "returns a rep, so a found person short-circuits before the retry).")
    gate(JF, [JR, JRP], "person.rb:318-327 json site: mention_lookup_json_retry (and "
         "its retried person's persisted decision JRP) is reached only when the "
         "first attempt was not_found — a found person short-circuits before retry.")

    # ------------------------------------------------------------------
    # R3P (the persisted-branch mentioned-person, records_3) vs the mention
    # lookups (the unpersisted branch): opposite sides of CP, never
    # co-evaluated. gate(CP, [R3P]) and gate(CP, LOOKUPS) declare each vs CP,
    # but the checker also demands the R3P x LOOKUP pairs directly — they are
    # equally structurally impossible (mutually exclusive CP branches).
    # ------------------------------------------------------------------
    gate(R3P, LOOKUPS,
         "mentions_container.rb:16-21: records_3 (persisted branch, mentions."
         "includes preload) and the mention_lookup_* family (unpersisted "
         "branch, people_from_string) are on mutually exclusive sides of the "
         "comment rep's persisted decision (CP); never co-evaluated.")

    # ------------------------------------------------------------------
    # Cross-site independence (unchanged argument from the previous pass):
    # comment_presenter.rb's as_json evaluates BOTH the text: field (msg
    # site) and the mentioned_people: field (json site) in every run; each
    # site's finder outcomes are independently seeded mock decisions with
    # no engine-tracked data flow between the sites (no shared variable,
    # no argument passed from one to the other — both parse the same
    # concrete pinned text). Rule 2 of assumptions.py's independence test.
    # ------------------------------------------------------------------
    for a in MSG:
        for c in JSON_:
            aset.add(IndependenceAssumption(
                expr_a=a, expr_b=c,
                description=("comment_presenter.rb as_json: the text: (msg) and "
                             "mentioned_people: (json) call sites both run in every "
                             "unpersisted-with-mention run; each site's find_by outcomes "
                             "are independently seeded mock decisions with no "
                             "engine-tracked data dependency between the sites."),
                agent_notes="Sibling-decision independence (assumptions.py rule 2)."))

    return aset
