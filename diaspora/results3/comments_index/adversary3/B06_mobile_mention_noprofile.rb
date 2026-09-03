# B06 — ISOLATED (crash risk). The MOBILE mention path with a mention person who
# has no `profiles` row AND mention markup with NO display name, so
# `MentionsInternal.mention_link` falls through to `person.name`
# (mentionable.rb:107-112 / people_helper.rb:28-33) -> `fix_profile`.
# The corpus's shim text ALWAYS writes `@{Concolic Mention; <handle>}` (a
# display name), so the `display_name || person.name` branch is pinned and the
# mobile mention person's `profile_not_found == True` arm mints no consequence.
require_relative "_common3"
adv_setup!("B06_mobile_mention_noprofile")
seed_core!
CE.insert("people", id: 4, guid: "daveguid000000004", diaspora_handle: "dave@127.0.0.1",
          serialized_public_key: "K4", owner_id: nil, closed_account: false, fetch_status: 0)
CE.insert("posts", id: 262, author_id: 2, guid: "postguid2620000001", type: "StatusMessage",
          text: "p262", public: true, comments_count: 1)
CE.insert("comments", id: 362, commentable_id: 262, commentable_type: "Post", author_id: 2,
          guid: "cguid362", text: "hi @{dave@127.0.0.1} there")
CE.insert("mentions", id: 962, mentions_container_id: 362, mentions_container_type: "Comment", person_id: 4)

CONCRETE_SCENARIOS = adv_scenario("B06-mobile-mention-noprofile") do
  adv_request(post_id: "262", format: :mobile, tag: "B06_mention_noprofile_mobile")
end
