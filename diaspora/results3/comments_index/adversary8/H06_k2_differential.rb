# ROUND 8 / H06 — the K2 DIFFERENTIAL, both trees, both orders.
# Corpus states (verified on dumps):
#   author tree:  (_author_profile_not_found, _author_profile_k2_not_found)
#                 (T,F) -> `…_author_discovery_failed == True` -> DiscoveryError terminal
#                 (F,T) -> NO discovery decision, terminal CLEAN, full render  <-- 429 dumps
#   mentions tree: same asymmetry, 916 clean dumps in the (F,T) state.
# Real prediction: BOTH orders 500 with DiscoveryError, because AR's preload
# attaches nil for whichever key was not found and `Person#name` is called on
# every rendered author / every mentioned person on json.
# Identical fixtures in each pair; only WHICH person lacks the `profiles` row
# differs. Plus the principal-without-a-profile control on an UNINFLECTED locale.
require_relative "_common8"
require_relative "_frames8"
adv_setup!("H06_k2_differential")
seed_core!

CE.insert("people", id: 8, guid: "wraithguid0000008", diaspora_handle: "wraith@ba[d.example",
          serialized_public_key: "K8", owner_id: nil, closed_account: false, fetch_status: 0)
# person 7 == a normal remote person WITH a profile (the "found" key)
CE.insert("people", id: 7, guid: "graceguid00000007", diaspora_handle: "grace@other.example",
          serialized_public_key: "K7", owner_id: nil, closed_account: false, fetch_status: 0)
CE.insert("profiles", id: 17, person_id: 7, first_name: "Grace", last_name: "G", searchable: true, nsfw: false)
# principal with a person but NO profiles row, language "en" (set_grammatical_gender skipped)
seed_user!(uid: 35, username: "u35", language: "en", person_id: 35,
           person_guid: "u35guid0000000035", handle: "u35@ba[d3.example")

def post!(pid, guid, public_flag: true, author: 2, extra: {})
  CE.insert("posts", **{id: pid, author_id: author, guid: guid, type: "StatusMessage",
                        text: "p#{pid}", public: public_flag, comments_count: 0}.merge(extra))
end
def comment!(cid, pid, author, text = "c#{cid}")
  CE.insert("comments", id: cid, commentable_id: pid, commentable_type: "Post",
            author_id: author, guid: "h6cguid#{cid}", text: text,
            created_at: "2020-01-01 00:00:#{format('%02d', cid % 60)}")
end
def mention!(mid, cid, person_id)
  CE.insert("mentions", id: mid, mentions_container_id: cid,
            mentions_container_type: "Comment", person_id: person_id)
end
G = "@{grace@other.example}"
W = "@{wraith@ba[d.example}"

# AUTHOR TREE -------------------------------------------------------------
# 870 — key1 FOUND (author 7, profile), key2 MISSING (author 8, no profile)  => corpus (F,T) CLEAN
post!(870, "h06guid870000000001"); comment!(880, 870, 7); comment!(881, 870, 8)
# 871 — mirror: key1 MISSING, key2 FOUND                                     => corpus (T,F) DiscoveryError
post!(871, "h06guid871000000001"); comment!(882, 871, 8); comment!(883, 871, 7)
# MENTIONS TREE -----------------------------------------------------------
# 872 — mention1 FOUND (7), mention2 MISSING (8)                             => corpus (F,T) CLEAN
post!(872, "h06guid872000000001")
comment!(884, 872, 2, "a #{G} b #{W}"); mention!(890, 884, 7); mention!(891, 884, 8)
# 873 — mirror
post!(873, "h06guid873000000001")
comment!(885, 873, 2, "a #{W} b #{G}"); mention!(892, 885, 8); mention!(893, 885, 7)
# principal control
post!(874, "h06guid874000000001"); comment!(886, 874, 2)

CONCRETE_SCENARIOS = adv_scenario("H06-k2-differential") do
  req!(post_id: "870", format: :json,   tag: "H06_870_author_k2_missing_json")
  req!(post_id: "870", format: :mobile, tag: "H06_870_author_k2_missing_mobile")
  req!(post_id: "871", format: :json,   tag: "H06_871_author_k1_missing_json")
  req!(post_id: "871", format: :mobile, tag: "H06_871_author_k1_missing_mobile")
  req!(post_id: "872", format: :json,   tag: "H06_872_mention_k2_missing_json")
  req!(post_id: "872", format: :mobile, tag: "H06_872_mention_k2_missing_mobile")
  req!(post_id: "873", format: :json,   tag: "H06_873_mention_k1_missing_json")
  req!(post_id: "873", format: :mobile, tag: "H06_873_mention_k1_missing_mobile")
  req!(post_id: "874", format: :json,   signed_in: true, uid: 35, tag: "H06_874_principal_noprofile_en_json")
  req!(post_id: "874", format: :mobile, signed_in: true, uid: 35, tag: "H06_874_principal_noprofile_en_mobile")
  dump_frames!("H06")
end
