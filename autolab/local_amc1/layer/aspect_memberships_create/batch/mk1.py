import json, sys
from concolic.corpus.load import canon
from concolic.gate.replay import expr_dimension
src = {"file": "/home/dev/project/reports/autolab/targets/endpoints/aspect_memberships_create.rb", "function": "symbolic_instance", "col_offset": 0}
recs = []
for var, who in [("SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_user_language", "contact.user (the contact row's user_id = principal; re-read through the association)"),
                 ("SYM_RESULT_ActiveRecord__FinderMethods_find_by_1_person_owner_language", "contact.person.owner (the target person's owning user)"),
                 ("assoc_person_owner_language", "@person.owner reached through the association before a contact row exists")]:
    for lit, line in (("pl", 540), ("xx", 542)):
        e = canon({"op": "==", "args": [{"sym": var}, {"lit": {"sort": "str", "value": lit}}]})
        print(expr_dimension(e), file=sys.stderr)
        recs.append({"type": "UntrackedPathAssumption",
          "source": dict(src, lineno=line, snippet=f'elsif lang == "{lit}"' if lit == "xx" else f'if lang == "{lit}"'),
          "expr": e,
          "description": f"The users.language arm ({lit!r} vs not) of {who} is irrelevant to the access pattern: "
                         "the compare is recorded by AspectMembershipsTargets' symbolic_instance when a User row is "
                         "instantiated (targets/endpoints/aspect_memberships_create.rb:538-546) and only concretizes "
                         "the attribute; nothing on this endpoint's request path reads a NON-principal user's language.",
          "agent_notes": "Evidence: over the 403-dump corpus, every pair of runs whose PC sequences agree once this "
                         "variable's two language compares are removed, but whose language arm (pl/xx/en) differs, has an "
                         "IDENTICAL access trace (find_by_1_user_language 264 pairs, find_by_1_person_owner_language 264, "
                         "assoc_person_owner_language 54; 0 differ). Contrast: the PRINCIPAL's language "
                         "(devise_user_first_1_language) is NOT declared -- en vs pl changes the trace in all 169 pairs."})
json.dump(recs, open(sys.argv[1], "w"), indent=1)
