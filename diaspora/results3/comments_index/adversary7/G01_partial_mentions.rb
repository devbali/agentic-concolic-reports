# G01 — ROUND 7, brief item 2(c): PARTIAL LOADS of the mentions preload.
# Hypotheses:
#  H1 the corpus binds the mobile `Template::Error <- NoMethodError` terminal to
#     `<mentions rel>_row_person_not_found == True` ONLY (318/318 dumps), i.e. to
#     the state with NO nested `profiles` statement. The real endpoint reaches the
#     SAME terminal from a PARTIAL load (`people.id IN (?, ?)` THEN
#     `profiles.person_id = ?`), because `Mentionable.format`'s `people.find` walks
#     a list that contains a live Person AND a nil.
#  H2 which parent is missing IS observable through that terminal: [live, nil]
#     with markup for the live one renders 200, with markup for the missing one
#     500 — the model has one `_not_found` arm labelled "key 1".
#  H3 3 mentions with the MIDDLE one dangling: `IN (?,?,?)` then `IN (?,?)`.
#  H4 a mention whose PERSON exists but whose PROFILE does not is reachable by a
#     real run on mobile when the markup carries a display name (no `person.name`,
#     so no `fix_profile` and no JVM abort).
require_relative "_common7"
adv_setup!("G01_partial_mentions")
seed_core!

# person 8: exists, NO profiles row  (H4)
CE.insert("people", id: 8, guid: "heidiguid00000008", diaspora_handle: "heidi@remote.example",
          serialized_public_key: "K8", owner_id: nil, closed_account: false, fetch_status: 0)

def post!(pid, guid, public_flag: true, author: 2, extra: {})
  CE.insert("posts", **{id: pid, author_id: author, guid: guid, type: "StatusMessage",
                        text: "p#{pid}", public: public_flag, comments_count: 0}.merge(extra))
end
def comment!(cid, pid, author, text)
  CE.insert("comments", id: cid, commentable_id: pid, commentable_type: "Post",
            author_id: author, guid: "g1cguid#{cid}", text: text,
            created_at: "2020-01-01 00:00:#{format('%02d', cid % 60)}")
end
def mention!(mid, cid, person_id)
  CE.insert("mentions", id: mid, mentions_container_id: cid,
            mentions_container_type: "Comment", person_id: person_id)
end

ERIN  = "@{Erin; erin@other.example}"
FRANK = "@{Frank; frank@third.example}"
GHOST = "@{Ghost; ghost@nowhere.example}"
HEIDI = "@{Heidi; heidi@remote.example}"

# 850 CONTROL: [live 5, dangling 995], markup for the LIVE one only -> 200
post!(850, "g01guid850000000001"); comment!(860, 850, 2, "hi #{ERIN} bye")
mention!(950, 860, 5); mention!(951, 860, 995)
# 851 NOVEL: same rows, markup for BOTH -> the ghost markup walks past the nil
post!(851, "g01guid851000000001"); comment!(861, 851, 2, "hi #{ERIN} and #{GHOST}")
mention!(952, 861, 5); mention!(953, 861, 995)
# 852 NOVEL: dangling FIRST, markup for the live one -> nil is at index 0
post!(852, "g01guid852000000001"); comment!(862, 852, 2, "hi #{ERIN} bye")
mention!(954, 862, 995); mention!(955, 862, 5)
# 853 CORPUS STATE: both dangling -> IN (?,?) and NO profiles, then 500
post!(853, "g01guid853000000001"); comment!(863, 853, 2, "hi #{GHOST} bye")
mention!(956, 863, 994); mention!(957, 863, 995)
# 854: 3 mentions, dangling LAST, markup for the two live ones -> 200
post!(854, "g01guid854000000001"); comment!(864, 854, 2, "hi #{ERIN} #{FRANK} bye")
mention!(958, 864, 5); mention!(959, 864, 6); mention!(960, 864, 995)
# 855: 3 mentions, MIDDLE dangling, markup for the FIRST live one -> 200 (H3)
post!(855, "g01guid855000000001"); comment!(865, 855, 2, "hi #{ERIN} bye")
mention!(961, 865, 5); mention!(962, 865, 995); mention!(963, 865, 6)
# 856: mention PERSON exists, PROFILE does not; NAMED markup, mobile only (H4)
post!(856, "g01guid856000000001"); comment!(866, 856, 2, "hi #{HEIDI} bye")
mention!(964, 866, 8)
# 857: two comments, first with a full load, second with a partial load
post!(857, "g01guid857000000001")
comment!(867, 857, 2, "one #{ERIN}"); comment!(868, 857, 5, "two #{FRANK} #{GHOST}")
mention!(965, 867, 5); mention!(966, 868, 6); mention!(967, 868, 995)

CONCRETE_SCENARIOS = adv_scenario("G01-partial-mentions") do
  adv_request(post_id: "850", format: :mobile, tag: "G01_850_partial_live_markup_mobile")
  adv_request(post_id: "851", format: :mobile, tag: "G01_851_partial_ghost_markup_mobile")
  adv_request(post_id: "852", format: :mobile, tag: "G01_852_dangling_first_mobile")
  adv_request(post_id: "853", format: :mobile, tag: "G01_853_both_dangling_mobile")
  adv_request(post_id: "854", format: :mobile, tag: "G01_854_three_dangling_last_mobile")
  adv_request(post_id: "855", format: :mobile, tag: "G01_855_three_middle_dangling_mobile")
  adv_request(post_id: "856", format: :mobile, tag: "G01_856_person_without_profile_mobile")
  adv_request(post_id: "857", format: :mobile, tag: "G01_857_two_comments_mixed_mobile")
  # json controls (mentioned_people -> [null] is 200 on json; M-3)
  adv_request(post_id: "850", format: :json, tag: "G01_850_partial_json")
  adv_request(post_id: "851", format: :json, tag: "G01_851_partial_json")
  adv_request(post_id: "855", format: :json, tag: "G01_855_middle_json")
  adv_request(post_id: "853", format: :json, tag: "G01_853_both_dangling_json")
end
