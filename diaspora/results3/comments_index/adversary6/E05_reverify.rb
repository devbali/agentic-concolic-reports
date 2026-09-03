# E05 — ROUND 6, brief item 1: re-verify EVERY prior finding on THIS corpus at
# projection level (M-1 links are in E04, M-2 mobile in E01/E03, M-6 STI in E03,
# M-7/M-8 in E01, M-9/B-8 in E02).  Here: M-3 (dangling mention), M-4 (empty
# relation), M-5 (users.language third arm), plus R2's D1/D2/D3/D5/D8/D9 and
# the empty-collection statement pairs.
# Every principal gets its OWN uid: the harness memoises User per uid, so only
# the FIRST request for a uid is a clean principal differential.
require_relative "_common6"
adv_setup!("E05_reverify")
seed_core!
seed_user!(uid: 41, username: "lang_xx",   language: "xx",  person_id: 41, person_guid: "e05p41guid00000001",
           handle: "lang_xx@localhost", profile_id: 141)
seed_user!(uid: 42, username: "lang_empty", language: "",   person_id: 42, person_guid: "e05p42guid00000001",
           handle: "lang_empty@localhost", profile_id: 142)
seed_user!(uid: 43, username: "lang_nil",  language: nil,   person_id: 43, person_guid: "e05p43guid00000001",
           handle: "lang_nil@localhost", profile_id: 143)
seed_user!(uid: 44, username: "lang_pl",   language: "pl",  person_id: 44, person_guid: "e05p44guid00000001",
           handle: "lang_pl@localhost", profile_id: 144, gender: "male")
seed_user!(uid: 45, username: "noperson",  language: "en")   # user with NO people row (D5)

def post!(pid, guid, public_flag: true, author: 2)
  CE.insert("posts", id: pid, author_id: author, guid: guid, type: "StatusMessage",
            text: "p#{pid}", public: public_flag, comments_count: 0)
end
def comment!(cid, pid, author, text = "c#{cid}")
  CE.insert("comments", id: cid, commentable_id: pid, commentable_type: "Post",
            author_id: author, guid: "e5cguid#{cid}", text: text,
            created_at: "2020-01-01 00:00:#{format('%02d', cid % 60)}")
end
def mention!(mid, cid, person_id)
  CE.insert("mentions", id: mid, mentions_container_id: cid,
            mentions_container_type: "Comment", person_id: person_id)
end

post!(740, "e05guid740000000001")                              # ZERO comments (M-4)
post!(741, "e05guid741000000001"); comment!(880, 741, 2)       # one comment, ZERO mentions (M-4)
post!(742, "e05guid742000000001")                              # dangling mention, NO markup (M-3, 200)
comment!(881, 742, 2, "plain text, dangling mention row"); mention!(930, 881, 994)
post!(743, "e05guid743000000001")                              # dangling mention WITH markup (M-3, mobile 500)
comment!(882, 743, 2, "hello @{Ghost; ghost@remote.example} bye"); mention!(931, 882, 993)
post!(744, "e05guid744000000001")                              # 1 live + 1 dangling (M-8 control)
comment!(883, 744, 2, "mixed"); mention!(932, 883, 5); mention!(933, 883, 992)
post!(745, "e05guid745000000001")                              # the language principals' post
comment!(884, 745, 2)
post!(746, "e05guid746000000001", public_flag: false)          # private, shared with the no-person user 45
CE.insert("share_visibilities", id: 41, shareable_id: 746, shareable_type: "Post", user_id: 45, hidden: false)
comment!(885, 746, 2)
post!(747, "e05guid747000000001", public_flag: false)          # private, NOT shared with 45 (D5: raises)
comment!(886, 747, 2)

CONCRETE_SCENARIOS = adv_scenario("E05-reverify") do
  # M-5: one uid each, first request per uid
  adv_request(post_id: "745", format: :json, signed_in: true, uid: 41, tag: "E05_lang_xx")
  adv_request(post_id: "745", format: :json, signed_in: true, uid: 42, tag: "E05_lang_empty")
  adv_request(post_id: "745", format: :json, signed_in: true, uid: 43, tag: "E05_lang_nil")
  adv_request(post_id: "745", format: :json, signed_in: true, uid: 44, tag: "E05_lang_pl_gender")
  # D5: a user with no people row
  adv_request(post_id: "746", format: :json, signed_in: true, uid: 45, tag: "E05_noperson_visible")
  adv_request(post_id: "747", format: :json, signed_in: true, uid: 45, tag: "E05_noperson_notvisible")
  # M-4: empty relations
  adv_request(post_id: "740", format: :json,   tag: "E05_740_zero_comments")
  adv_request(post_id: "740", format: :mobile, tag: "E05_740_zero_comments_mobile")
  adv_request(post_id: "740", format: :json, signed_in: true, tag: "E05_740_zero_comments_auth")
  adv_request(post_id: "741", format: :json,   tag: "E05_741_zero_mentions")
  adv_request(post_id: "741", format: :mobile, tag: "E05_741_zero_mentions_mobile")
  # M-3: dangling mention
  adv_request(post_id: "742", format: :json,   tag: "E05_742_dangling_nomarkup")
  adv_request(post_id: "742", format: :mobile, tag: "E05_742_dangling_nomarkup_mobile")
  adv_request(post_id: "743", format: :json,   tag: "E05_743_dangling_markup")
  adv_request(post_id: "743", format: :mobile, tag: "E05_743_dangling_markup_mobile")
  adv_request(post_id: "744", format: :json,   tag: "E05_744_mixed_mentions")
  adv_request(post_id: "744", format: :mobile, tag: "E05_744_mixed_mentions_mobile")
end
