#!/usr/bin/env python3
"""PINNED-TEXT QUERY AUDIT (cycle 4; the check that catches the adversary's
W1 CLASS — a pin on a string column foreclosing a regex-driven query site).

    python3 pinned_text_query_audit.py <batch_dir>

For every text-processing module reachable from this endpoint's renderers
(Diaspora::MessageRenderer and the modules it calls), find every REGEX
BLOCK (`gsub`/`scan`/`match`/`=~` over the message) whose body reaches an
ActiveRecord finder (`exists?`/`find_by`/`where`/`find`/`first`), i.e. a
query whose argument is extracted from the text. Each such family must be a
recorded decision in the corpus: a `_text_<family>` PC var must occur in
the dumps (the text pin then carries the family and DSE explores it).
Exit 1 if a query-bearing regex family has no decision var.
"""
import glob, json, os, re, sys

APP = "/home/dev/project/ruby_examples/dse-apps/apps/diaspora"
FILES = ["lib/diaspora/message_renderer.rb", "lib/diaspora/mentionable.rb", "lib/diaspora/taggable.rb",
         "lib/diaspora/camo.rb"]
FINDER = re.compile(r"\b(exists\?|find_by|find_or_fetch|find_or_create|where|find\b|first\b|by_account_identifier|people_from_string)")
# regex-block family -> the decision var suffix the corpus must carry
FAMILIES = {
    "DIASPORA_URL_REGEX": "_text_has_dlink",       # diaspora_links -> Post.exists?(guid:)
    "REGEX": "_text_has_mention",                   # Mentionable.format/people_from_string
    "NEW_SYNTAX_REGEX": "_text_has_mention",        # Mentionable.backport_mention_syntax (same mention markup)
}

def main():
    batch = sys.argv[1]
    exprs = set()
    for p in glob.glob(os.path.join(batch, "dump_*.json")):
        for e in json.load(open(p)).get("events") or []:
            if e.get("type") == "path_condition":
                exprs.add(e["expr"])
    print("== pinned_text_query_audit ==")
    red = False
    for f in FILES:
        src = open(os.path.join(APP, f)).read()
        for m in re.finditer(r"\.(gsub|scan|match|sub)\(([A-Za-z:_]+REGEX[A-Za-z_]*)\)(.{0,400})", src, re.S):
            body = m.group(3)
            fam = m.group(2).split("::")[-1]
            queries = FINDER.search(body) is not None
            suffix = FAMILIES.get(fam)
            have = suffix and any(suffix in e for e in exprs)
            status = "OK " if (not queries) or have else "RED"
            red = red or status == "RED"
            print(f"   {status} {f}: {m.group(1)}({fam}) query-bearing={queries} decision={suffix or '-'} in corpus={bool(have)}")
    print("RESULT: " + ("RED — a text-derived query site has no recorded decision." if red else "every text-derived query site is a recorded decision."))
    sys.exit(1 if red else 0)

if __name__ == "__main__":
    main()
