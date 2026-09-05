# C04 — signed-in OTHER-person html, BLOCKED: alice blocked bob. No contact.
# full_hash -> is_blocked? -> current_user_person_block -> block_for ->
# blocks.find_by(person_id: 2) -> CollectionProxy FinderMethods#find_by
# (nil vs row — row here) -> BlockPresenter.base_hash ({id:}).
# JSON variant covers the same presenter path; html shows block state.
require_relative "_common"

adv_setup!("R2C04_auth_blocked_json")
seed_people!(dave: true, p12: {image_url: "http://remote.example/bob.png"})

# alice BLOCKS bob (no contact row)
CE.insert("blocks", id: 91, user_id: 9, person_id: 2)

# bob's profile has a diaspora link (blocked -> show_profile_info? public_details
# 0, not own, person_is_following false -> public_hash — block does not unlock
# private info; still exercises the presenter's block key)
CE.insert("tags", id: 34, name: "blockedtag")
CE.insert("taggings", id: 44, tag_id: 34, taggable_id: 12, taggable_type: "Profile",
         context: "tags", created_at: Time.now.to_s)

# alice's profile for the JSON render path (self-arm photo count)
CE.insert("photos", id: 731, author_id: 1, guid: "pguid7310000000001", public: 't', pending: 'f',
         created_at: Time.now.to_s, updated_at: Time.now.to_s, text: "alice pub")

CONCRETE_SCENARIOS = adv_scenario("C04_auth_blocked_json") do
  adv_request(username: "bob@remote.example", format: "json", signed_in: true, tag: "C04")
end