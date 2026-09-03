# C10 — ISOLATED. Brief item 2c, second half: the MOBILE `profile_not_found`
# arm that mints a `fix_profile -> Discovery -> reload -> profiles` chain.
# A mention WITHOUT a display name (`@{handle}`) of a person that has NO
# profiles row is the only shape on the mobile side that reaches `Person#name`
# (people_helper.rb:28-33 `opts[:display_name] || person.name`).
require_relative "_common4"
adv_setup!("C10_fixprofile_render")
seed_core!

CE.insert("people", id: 42, guid: "daveguid000000042", diaspora_handle: "dave@127.0.0.1",
          serialized_public_key: "K42", owner_id: nil, closed_account: false, fetch_status: 0)

CE.insert("posts", id: 398, author_id: 2, guid: "fpguid39800000001", type: "StatusMessage",
          text: "p398", public: true, comments_count: 1)
CE.insert("comments", id: 498, commentable_id: 398, commentable_type: "Post", author_id: 2,
          guid: "cguid498", text: "hi @{dave@127.0.0.1} bye")
CE.insert("mentions", id: 898, mentions_container_id: 498, mentions_container_type: "Comment", person_id: 42)

CONCRETE_SCENARIOS = adv_scenario("C10-fixprofile-render") do
  adv_request(post_id: "398", format: :mobile, tag: "C10_mobile_noname_noprofile")
end
