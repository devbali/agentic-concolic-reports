# ROUND 10 / K01 — THE THIRD REPRESENTATIVE, THE WALL'S STATEMENT ORDER, AND
# THE DECLARED CEILINGS RE-MEASURED AS PER-REQUEST MULTISETS.
#
# Cycle 12 deleted the discovery-success arm. The coordinator's brief asks
# whether the deletion (a) removed states reachable WITHOUT discovery and
# (b) left the statements issued BEFORE the raise complete and faithful.
#
# This manifest attacks the two-representative ceiling in the one way that
# could produce a PER-REQUEST shape change rather than a wider IN-list: a
# THIRD comment whose author lacks a profile, so the request renders two
# comments in full and then hits the wall. The corpus has `row` and `row2`
# only, so no corpus dump can carry "two fully-rendered comments THEN a
# DiscoveryError". It also re-measures the declared diaspora-link ceiling
# (`_text_dlink_ge4`, "4 stands for four or more") as a per-request count of
# `SELECT 1 AS one FROM posts WHERE guid = ?`.
#
# EVERY profile-less person here carries a URI-HOSTILE diaspora_handle
# (domain contains '['), so Faraday raises URI::InvalidURIError in pure Ruby
# and no FFI/libcurl call is made: 0 JVM aborts by construction (DISCIPLINE
# §12 amendment / M-15).
#
# Nothing is mocked, stubbed or patched: fixture rows, session, params,
# headers and format only.
require_relative "_common10"
require_relative "_frames10"
adv_setup!("K01_third_rep_and_wall_order")
seed_core!

# --- extra cast (fixture ROWS only) ----------------------------------------
# person 7 : remote, NO profiles row, URI-hostile handle  -> fix_profile wall
# person 8 : remote, NO profiles row, URI-hostile handle  -> second waller
# person 20: remote, HAS profile                          -> third live author
CE.insert("people", id: 7, guid: "wraithguid0000007", diaspora_handle: "wraith@ba[d.example",
          serialized_public_key: "K7", owner_id: nil, closed_account: false, fetch_status: 0)
CE.insert("people", id: 8, guid: "ghostguid00000008", diaspora_handle: "ghost@ba[d2.example",
          serialized_public_key: "K8", owner_id: nil, closed_account: false, fetch_status: 0)
CE.insert("people", id: 20, guid: "gwenguid000000020", diaspora_handle: "gwen@remote.example",
          serialized_public_key: "K20", owner_id: nil, closed_account: false, fetch_status: 0)
CE.insert("profiles", id: 20, person_id: 20, first_name: "Gwen", last_name: "G",
          searchable: true, nsfw: false)

def post!(pid, guid, public_flag: true, author: 2, type: "StatusMessage")
  CE.insert("posts", id: pid, author_id: author, guid: guid, type: type,
            text: "p#{pid}", public: public_flag, comments_count: 0)
end
def comment!(cid, pid, author, text = "c#{cid}")
  CE.insert("comments", id: cid, commentable_id: pid, commentable_type: "Post",
            author_id: author, guid: "k1cguid#{cid}", text: text,
            created_at: "2020-01-01 00:00:#{format('%02d', cid % 60)}")
end
def mention!(mid, cid, person_id)
  CE.insert("mentions", id: mid, mentions_container_id: cid,
            mentions_container_type: "Comment", person_id: person_id)
end

E = "@{erin@other.example}"   # person 5, has a profile
G = "@{gwen@remote.example}"  # person 20, has a profile

# 990 — THREE comments, THREE distinct authors; the THIRD lacks a profile.
#       Two comments render in full, then the wall. No corpus dump can hold
#       this: the corpus models two representative rows.
post!(990, "k01guid990000000001")
comment!(1001, 990, 2,  "one #{E}");  mention!(1101, 1001, 5)
comment!(1002, 990, 5,  "two #{G}");  mention!(1102, 1002, 20)
comment!(1003, 990, 7,  "three")

# 991 — THREE comments, TWO distinct author keys {2,2,7}; third wallers.
post!(991, "k01guid991000000001")
comment!(1004, 991, 2, "one #{E}");   mention!(1103, 1004, 5)
comment!(1005, 991, 2, "two #{E}");   mention!(1104, 1005, 5)
comment!(1006, 991, 7, "three")

# 992 — ONE comment with SIX diaspora post links (declared ceiling is 4).
LINKS = (0..5).map { |k| "diaspora://alice@localhost/post/k01linkguid00000#{k}" }.join(" ")
post!(992, "k01guid992000000001")
comment!(1007, 992, 2, "links #{LINKS}")

# 993 — ONE comment, THREE mentions, the MIDDLE one dangling (person 99 absent).
#       mentioned_people == [live, nil, live] — the nil is not at the end.
post!(993, "k01guid993000000001")
comment!(1008, 993, 2, "m #{E} #{G} @{nobody@ba[d3.example}")
mention!(1105, 1008, 5); mention!(1106, 1008, 99); mention!(1107, 1008, 20)

# 994 — TWO comments; the FIRST author walls, the SECOND is live. The request
#       must stop at comment 1: no statements for comment 2 at all.
post!(994, "k01guid994000000001")
comment!(1009, 994, 7, "first #{E}");  mention!(1108, 1009, 5)
comment!(1010, 994, 2, "second #{E}"); mention!(1109, 1010, 5)

# 995 — THREE comments, authors 7 and 8 BOTH profile-less plus a live one:
#       two distinct wallers in one request.
post!(995, "k01guid995000000001")
comment!(1011, 995, 2, "live #{E}"); mention!(1110, 1011, 5)
comment!(1012, 995, 7, "wall one")
comment!(1013, 995, 8, "wall two")

# 996 — a comment whose MENTION person lacks a profile (mention tree wall),
#       WITHOUT a display name so `person_link` must call `person.name`.
post!(996, "k01guid996000000001")
comment!(1014, 996, 2, "mm @{wraith@ba[d.example}")
mention!(1111, 1014, 7)

# 997 — plain control: one comment, one live mention.
post!(997, "k01guid997000000001")
comment!(1015, 997, 2, "ok #{E}"); mention!(1112, 1015, 5)

CONCRETE_SCENARIOS = adv_scenario("K01-third-rep-and-wall-order") do
  CompletionChecker.new_request! if defined?(CompletionChecker) && CompletionChecker.respond_to?(:new_request!)

  # --- the third-representative battery -----------------------------------
  req!(post_id: "990", format: :json,   tag: "K01_990_3c3a_third_walls_json")
  req!(post_id: "990", format: :mobile, tag: "K01_990_3c3a_third_walls_mobile")
  req!(post_id: "990", format: :json,   signed_in: true, tag: "K01_990_3c3a_third_walls_auth_json")
  req!(post_id: "991", format: :json,   tag: "K01_991_3c2k_third_walls_json")
  req!(post_id: "995", format: :json,   tag: "K01_995_two_wallers_json")
  req!(post_id: "995", format: :mobile, tag: "K01_995_two_wallers_mobile")

  # --- the wall's statement ORDER (before/after) ---------------------------
  req!(post_id: "994", format: :json,   tag: "K01_994_first_walls_json")
  req!(post_id: "994", format: :mobile, tag: "K01_994_first_walls_mobile")
  req!(post_id: "996", format: :json,   tag: "K01_996_mention_walls_json")
  req!(post_id: "996", format: :mobile, tag: "K01_996_mention_walls_mobile")

  # --- declared ceilings ---------------------------------------------------
  req!(post_id: "992", format: :json,   tag: "K01_992_six_dlinks_json")
  req!(post_id: "992", format: :mobile, tag: "K01_992_six_dlinks_mobile")
  req!(post_id: "993", format: :json,   tag: "K01_993_mid_nil_mention_json")
  req!(post_id: "993", format: :mobile, tag: "K01_993_mid_nil_mention_mobile")

  # --- controls -------------------------------------------------------------
  req!(post_id: "997", format: :json,   tag: "K01_997_control_json")
  req!(post_id: "997", format: :mobile, tag: "K01_997_control_mobile")

  # --- SCENARIO-BODY PROBES (NOT endpoint statements; reported separately) --
  $adv_tag = "PROBE_R1_faraday_adapter"
  adv_probe("R1 Faraday.default_adapter") { Faraday.default_adapter.inspect }
  $adv_tag = "PROBE_R2_discovery_source"
  adv_probe("R2 does Discovery have any non-HTTP short circuit?") do
    m = DiasporaFederation::Discovery::Discovery.instance_method(:fetch_and_save)
    [m.source_location,
     DiasporaFederation::Discovery::Discovery.private_instance_methods(false).sort]
  end
  $adv_tag = "PROBE_R3_find_or_fetch_fastpath"
  adv_probe("R3 Person.find_or_fetch_by_identifier fast path (person WITH profile)") do
    Person.find_or_fetch_by_identifier("bob@remote.example").id
  end
  $adv_tag = "PROBE_R4_person_url_reads_pods"
  adv_probe("R4 does Person#url read pods? (off-route; evidence only)") do
    Person.find(2).url
  end
  $adv_tag = nil
  dump_frames!("K01")
end
