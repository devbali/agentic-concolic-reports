# C02 — signed-in OTHER-person html: alice views bob (remote), contact
# receiving-only (alice follows bob), NOT sharing, NOT blocked.
# Corpus universe is ANON-ONLY; everything here is a signed-in branch:
#  - authenticate_if_remote_profile! passes (real warden authenticate!)
#  - contact_for(bob) -> Contact.includes(person: :profile).find_by
#    (Relation-level find_by w/ includes — corpus has only the opaque
#    class-level "User query" note)
#  - ContactPresenter.full_hash -> aspect_memberships.map (AspectMembership
#    CollectionProxy load)
#  - relationship -> :receiving (contact.receiving?)
#  - show_profile_info FALSE (public_details 0, not own, not following) ->
#    public_hash only (avatar + tags.pluck)
#  - Photo.visible(alice, bob) -> ShareVisibility LEFT JOIN + DISTINCT COUNT
#    (new shape vs anon `author_id=? AND public=true`)
#  - conversation modal -> new_conversation_path(:contact_id => @contact.id,
#    name: @contact.person.name) -> @contact.person.name (preloaded person)
require_relative "_common"

adv_setup!("R2C02_auth_other_html")
seed_people!(p12: {image_url: "http://remote.example/bob.png"})

# alice follows bob (receiving), bob does not follow alice (sharing 0)
CE.insert("contacts", id: 61, user_id: 9, person_id: 2, sharing: 'f', receiving: 't',
         created_at: Time.now.to_s, updated_at: Time.now.to_s)
CE.insert("aspect_memberships", id: 71, aspect_id: 21, contact_id: 61,
         created_at: Time.now.to_s, updated_at: Time.now.to_s)

# bob's photos: 1 public, 1 private (private NOT visible to alice — no
# share_visibility row), 1 private WITH share_visibility row for alice
CE.insert("photos", id: 711, author_id: 2, guid: "pguid7110000000001", public: 't', pending: 'f',
         created_at: Time.now.to_s, updated_at: Time.now.to_s, text: "bob pub")
CE.insert("photos", id: 712, author_id: 2, guid: "pguid7120000000002", public: 'f', pending: 'f',
         created_at: Time.now.to_s, updated_at: Time.now.to_s, text: "bob priv")
CE.insert("photos", id: 713, author_id: 2, guid: "pguid7130000000003", public: 'f', pending: 'f',
         created_at: Time.now.to_s, updated_at: Time.now.to_s, text: "bob shared with alice")
CE.insert("share_visibilities", id: 81, shareable_id: 713, shareable_type: "Photo",
         user_id: 9, hidden: 'f')

# bob's tags (public_hash tags.pluck — corpus note exists for tags via
# CollectionProxy.records; real rows keep it honest)
CE.insert("tags", id: 33, name: "bobtag")
CE.insert("taggings", id: 43, tag_id: 33, taggable_id: 12, taggable_type: "Profile",
         context: "tags", created_at: Time.now.to_s)

CONCRETE_SCENARIOS = adv_scenario("C02_auth_other_html") do
  adv_request(username: "bob@remote.example", format: "html", signed_in: true, tag: "C02")
end