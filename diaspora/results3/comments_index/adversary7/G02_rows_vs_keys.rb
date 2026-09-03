# G02 — ROUND 7, brief item 2(a)/2(d): is the COMMENTS relation's ROW COUNT
# determined by its distinct AUTHOR count?
# Cycle 8's `preload_rows_driven?` stops recording `(len(comments) > 1)` for a
# relation with a FREE key step and derives the row count from the key count
# ("a second distinct key implies a second row"). That implication is one-way:
# ONE distinct author does NOT imply ONE comment. Measured here:
#   N comments by ONE author  -> `people.id = ?` (one key) with N rows,
#   so N x the per-row statements (mentions SELECTs, Post.exists? probes).
# 2(d): with one distinct key the model mints no `_row2_` variable at all —
# check the real statement in exactly that state.
require_relative "_common7"
adv_setup!("G02_rows_vs_keys")
seed_core!

CE.insert("people", id: 7, guid: "graceguid00000007", diaspora_handle: "grace@remote.example",
          serialized_public_key: "K7", owner_id: nil, closed_account: false, fetch_status: 0)
CE.insert("profiles", id: 17, person_id: 7, first_name: "Grace", last_name: "G", searchable: true, nsfw: false)

def post!(pid, guid, public_flag: true, author: 2, extra: {})
  CE.insert("posts", **{id: pid, author_id: author, guid: guid, type: "StatusMessage",
                        text: "p#{pid}", public: public_flag, comments_count: 0}.merge(extra))
end
def comment!(cid, pid, author, text = "c#{cid}")
  CE.insert("comments", id: cid, commentable_id: pid, commentable_type: "Post",
            author_id: author, guid: "g2cguid#{cid}", text: text,
            created_at: "2020-01-01 00:00:#{format('%02d', cid % 60)}")
end
def mention!(mid, cid, person_id)
  CE.insert("mentions", id: mid, mentions_container_id: cid,
            mentions_container_type: "Comment", person_id: person_id)
end

ERIN = "@{Erin; erin@other.example}"

# 870: 5 comments, ONE author, each with one mention -> `people.id = ?`, 5 rows
post!(870, "g02guid870000000001")
[1, 2, 3, 4, 5].each_with_index do |_n, i|
  comment!(880 + i, 870, 2, "c#{880 + i} #{ERIN}")
  mention!(970 + i, 880 + i, [5, 6, 7, 1, 3][i])
end
# 871: 10 comments, ONE author, plain text
post!(871, "g02guid871000000001")
10.times { |i| comment!(890 + i, 871, 2) }
# 872: 3 comments, authors 2,2,5 -> IN (?, ?) with THREE rows
post!(872, "g02guid872000000001")
comment!(900, 872, 2); comment!(901, 872, 2); comment!(902, 872, 5)
# 873: 4 comments, 4 distinct authors -> IN (?, ?, ?, ?)
post!(873, "g02guid873000000001")
[2, 5, 6, 7].each_with_index { |a, i| comment!(905 + i, 873, a) }
# 874: 2 comments, SAME author, each mentioning the SAME person (2(d) shape)
post!(874, "g02guid874000000001")
comment!(910, 874, 2, "one #{ERIN}"); comment!(911, 874, 2, "two #{ERIN}")
mention!(980, 910, 5); mention!(981, 911, 5)
# 875: 2 comments by the SIGNED-IN user's own person (mobile delete branch)
post!(875, "g02guid875000000001", public_flag: false)
CE.insert("share_visibilities", id: 21, shareable_id: 875, shareable_type: "Post", user_id: 9, hidden: false)
comment!(915, 875, 1); comment!(916, 875, 1)
# 876: 6 comments, 2 authors alternating
post!(876, "g02guid876000000001")
6.times { |i| comment!(920 + i, 876, i.even? ? 2 : 5) }
# 877: ONE comment, ONE author (the base control)
post!(877, "g02guid877000000001"); comment!(930, 877, 2, "solo #{ERIN}")
mention!(985, 930, 5)

CONCRETE_SCENARIOS = adv_scenario("G02-rows-vs-keys") do
  adv_request(post_id: "870", format: :json,   tag: "G02_870_5c_1author_json")
  adv_request(post_id: "870", format: :mobile, tag: "G02_870_5c_1author_mobile")
  adv_request(post_id: "871", format: :json,   tag: "G02_871_10c_1author_json")
  adv_request(post_id: "871", format: :mobile, tag: "G02_871_10c_1author_mobile")
  adv_request(post_id: "872", format: :json,   tag: "G02_872_3c_2authors_json")
  adv_request(post_id: "873", format: :json,   tag: "G02_873_4c_4authors_json")
  adv_request(post_id: "874", format: :json,   tag: "G02_874_2c_1author_same_mention_json")
  adv_request(post_id: "874", format: :mobile, tag: "G02_874_2c_1author_same_mention_mobile")
  adv_request(post_id: "875", format: :mobile, signed_in: true, uid: 9, tag: "G02_875_own_comments_auth_mobile")
  adv_request(post_id: "876", format: :json,   tag: "G02_876_6c_2authors_json")
  adv_request(post_id: "877", format: :json,   tag: "G02_877_1c_1author_json")
  adv_request(post_id: "877", format: :mobile, tag: "G02_877_1c_1author_mobile")
end
