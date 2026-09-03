# B04 — ISOLATED (crash risk). Reach `Person#fix_profile` -> the real gem
# `Discovery.new(handle).fetch_and_save` WITHOUT a DNS lookup: the comment
# author's `diaspora_handle` domain is a literal loopback address, so webfinger
# fails with connection-refused instead of entering the native resolver that
# aborted the JVM in rounds 1 and 2 (A07/A08, exit 134).
# What this checks: (2a) `Discovery.new` was demoted from TARGET to SHIM in
# cycle 4 — a real run must mint NO note for it and it must reach no target;
# `fetch_and_save` must still be the wall carrying the decision. Also B-1: the
# `reload` call site.
require_relative "_common3"
adv_setup!("B04_fixprofile_ip")
seed_core!
CE.insert("people", id: 4, guid: "daveguid000000004", diaspora_handle: "dave@127.0.0.1",
          serialized_public_key: "K4", owner_id: nil, closed_account: false, fetch_status: 0)
# NO profiles row for person 4.
CE.insert("posts", id: 260, author_id: 2, guid: "postguid2600000001", type: "StatusMessage",
          text: "p260", public: true, comments_count: 1)
CE.insert("comments", id: 360, commentable_id: 260, commentable_type: "Post", author_id: 4,
          guid: "cguid360", text: "a comment by an author with no profiles row")

CONCRETE_SCENARIOS = adv_scenario("B04-fixprofile-ip") do
  adv_request(post_id: "260", format: :json, tag: "B04_noprofile_author_json")
end
