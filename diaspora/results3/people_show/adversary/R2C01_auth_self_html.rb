# C01 — signed-in SELF html (alice views her own profile).
# Corpus universe: ANON-ONLY. Every signed-in branch here is unexplored:
#  - mark_corresponding_notifications_read -> Notification.where(...).each ->
#    Persistence#update_column WRITE (no corpus write target at all)
#  - PersonPresenter full_hash signed-in arms: contact_for (Relation find_by
#    with includes), block_for (CollectionProxy find_by)
#  - private_hash (own_profile? -> show_profile_info true) -> bio_message /
#    location_message -> Diaspora::MessageRenderer -> Post.exists?(guid:)
#  - Photo.visible(alice, alice) -> owned_by_user -> person.photos COUNT
#    (no visibility SQL, but a signed-in count shape)
#  - publisher partial -> post_default_aspects -> aspects.where(...).to_a
#    (Relation#to_a with a NON-posts-stream SQL shape vs corpus notes)
require_relative "_common"

adv_setup!("R2C01_auth_self_html")
seed_people!(
  p11: {gender: "robot",
        bio: "hello diaspora://alice@localhost/post/postguid100000001 bye",
        location: "loc diaspora://alice@localhost/post/postguid100000001",
        birthday: "1990-01-01"}
)

# unread + read notifications targeting person 1 (mark_corresponding_notifications_read)
CE.insert("notifications", id: 501, recipient_id: 9, target_type: "Person", target_id: 1,
         unread: 't', created_at: Time.now.to_s, updated_at: Time.now.to_s, type: nil)
CE.insert("notifications", id: 502, recipient_id: 9, target_type: "Person", target_id: 1,
         unread: 't', created_at: Time.now.to_s, updated_at: Time.now.to_s, type: nil)
CE.insert("notifications", id: 503, recipient_id: 9, target_type: "Person", target_id: 1,
         unread: 'f', created_at: Time.now.to_s, updated_at: Time.now.to_s, type: nil)

# the post referenced by the bio links (exists? -> true)
CE.insert("posts", id: 100, author_id: 1, guid: "postguid100000001", type: "StatusMessage",
         text: "the linked post", public: 't', created_at: Time.now.to_s, updated_at: Time.now.to_s)

# alice's photos: 1 public, 1 private, 1 pending (pending filtered by Photo.visible)
CE.insert("photos", id: 701, author_id: 1, guid: "pguid7010000000001", public: 't', pending: 'f',
         created_at: Time.now.to_s, updated_at: Time.now.to_s, text: "pub photo")
CE.insert("photos", id: 702, author_id: 1, guid: "pguid7020000000002", public: 'f', pending: 'f',
         created_at: Time.now.to_s, updated_at: Time.now.to_s, text: "priv photo")
CE.insert("photos", id: 703, author_id: 1, guid: "pguid7030000000003", public: 'f', pending: 't',
         created_at: Time.now.to_s, updated_at: Time.now.to_s, text: "pending photo")

# aspects for the publisher partial (post_default_aspects)
CE.insert("aspects", id: 21, name: "Work", user_id: 9, created_at: Time.now.to_s,
         updated_at: Time.now.to_s, post_default: 't')
CE.insert("aspects", id: 22, name: "Play", user_id: 9, created_at: Time.now.to_s,
         updated_at: Time.now.to_s, post_default: 'f')

# tags on alice's profile (tags.pluck(:name) — corpus has the tags records
# note via CollectionProxy.records; keep real rows anyway)
CE.insert("tags", id: 31, name: "alpha")
CE.insert("tags", id: 32, name: "beta")
CE.insert("taggings", id: 41, tag_id: 31, taggable_id: 11, taggable_type: "Profile",
         context: "tags", created_at: Time.now.to_s)
CE.insert("taggings", id: 42, tag_id: 32, taggable_id: 11, taggable_type: "Profile",
         context: "tags", created_at: Time.now.to_s)

CONCRETE_SCENARIOS = adv_scenario("C01_auth_self_html") do
  adv_request(username: "alice@localhost", format: "html", signed_in: true, tag: "C01")
end