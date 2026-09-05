# C03 — signed-in OTHER-person html, MUTUAL contact + bio with diaspora://
# link: alice and bob share (sharing=1 receiving=1). show_profile_info TRUE
# via person_is_following_current_user (contact.sharing?) -> private_hash ->
# bio_message.plain_text_for_json -> MessageRenderer -> diaspora_links ->
# Post.exists?(guid:) (H2 family — no exists? target in corpus at all).
# Also: relationship -> :mutual; conversation modal.
require_relative "_common"

adv_setup!("R2C03_auth_other_mutual_html")
seed_people!(
  p12: {image_url: "http://remote.example/bob.png", gender: "human",
        bio: "my diaspora://alice@localhost/post/postguid100000002 link",
        location: "loc diaspora://alice@localhost/post/postguid100000002",
        birthday: "1985-05-05"}
)

# mutual contact (aspect membership row too)
CE.insert("contacts", id: 62, user_id: 9, person_id: 2, sharing: 't', receiving: 't',
         created_at: Time.now.to_s, updated_at: Time.now.to_s)
CE.insert("aspect_memberships", id: 72, aspect_id: 21, contact_id: 62,
         created_at: Time.now.to_s, updated_at: Time.now.to_s)

# the bio-linked post EXISTS? -> 1 (guid exists) — exercises Post.exists?
# from bio_message AND location_message
CE.insert("posts", id: 101, author_id: 1, guid: "postguid100000002", type: "StatusMessage",
         text: "linked post 2", public: 't', created_at: Time.now.to_s, updated_at: Time.now.to_s)

# bob's photos (ShareVisibility + public)
CE.insert("photos", id: 721, author_id: 2, guid: "pguid7210000000001", public: 't', pending: 'f',
         created_at: Time.now.to_s, updated_at: Time.now.to_s, text: "bob pub")
CE.insert("photos", id: 722, author_id: 2, guid: "pguid7220000000002", public: 'f', pending: 'f',
         created_at: Time.now.to_s, updated_at: Time.now.to_s, text: "bob priv shared")
CE.insert("share_visibilities", id: 82, shareable_id: 722, shareable_type: "Photo",
         user_id: 9, hidden: 'f')

CONCRETE_SCENARIOS = adv_scenario("C03_auth_other_mutual_html") do
  adv_request(username: "bob@remote.example", format: "html", signed_in: true, tag: "C03")
end