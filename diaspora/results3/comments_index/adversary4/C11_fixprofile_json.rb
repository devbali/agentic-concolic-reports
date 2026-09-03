# C11 — ISOLATED. The JSON counterpart of C10: `as_api_response(:backbone)`
# calls `Person#name` unconditionally, so a COMMENT AUTHOR with no profiles
# row reaches `fix_profile` on the json path too (corpus decision
# `…_row_author_profile_not_found`, 1 550 True dumps).
require_relative "_common4"
adv_setup!("C11_fixprofile_json")
seed_core!

CE.insert("people", id: 43, guid: "daveguid000000043", diaspora_handle: "dave@127.0.0.1",
          serialized_public_key: "K43", owner_id: nil, closed_account: false, fetch_status: 0)
CE.insert("posts", id: 399, author_id: 2, guid: "fpguid39900000001", type: "StatusMessage",
          text: "p399", public: true, comments_count: 1)
CE.insert("comments", id: 499, commentable_id: 399, commentable_type: "Post", author_id: 43,
          guid: "cguid499", text: "a comment by an author with no profile row")

CONCRETE_SCENARIOS = adv_scenario("C11-fixprofile-json") do
  adv_request(post_id: "399", format: :json, tag: "C11_json_author_noprofile")
end
