# C06 — ANON self html (CONTROL): anonymous viewing alice's LOCAL profile.
# This should reproduce the corpus's anon shapes (Person where diaspora_handle
# .first; Photo anon arm; public_hash tags; Person#first_name...). Purpose:
# validate the harness reproduces corpus shapes (sanity) + confirm the anon
# path does NOT fire any signed-in branch (notifications, contact_for,
# publisher).
require_relative "_common"

adv_setup!("R2C06_anon_self_html")
seed_people!(dave: true,
            p11: {gender: "robot", bio: "plain bio no links", location: "Berlin",
                  birthday: "1990-01-01"})

CE.insert("posts", id: 120, author_id: 1, guid: "postguid120000000", type: "StatusMessage",
         text: "alice public post", public: 't', created_at: Time.now.to_s, updated_at: Time.now.to_s)

CE.insert("photos", id: 751, author_id: 1, guid: "pguid7510000000001", public: 't', pending: 'f',
         created_at: Time.now.to_s, updated_at: Time.now.to_s, text: "alice pub")
CE.insert("photos", id: 752, author_id: 1, guid: "pguid7520000000002", public: 'f', pending: 'f',
         created_at: Time.now.to_s, updated_at: Time.now.to_s, text: "alice priv")
CE.insert("photos", id: 753, author_id: 1, guid: "pguid7530000000003", public: 't', pending: 't',
         created_at: Time.now.to_s, updated_at: Time.now.to_s, text: "alice pending")

CE.insert("tags", id: 36, name: "alicepub")
CE.insert("taggings", id: 46, tag_id: 36, taggable_id: 11, taggable_type: "Profile",
         context: "tags", created_at: Time.now.to_s)

CONCRETE_SCENARIOS = adv_scenario("C06_anon_self_html") do
  adv_request(username: "alice@localhost", format: "html", signed_in: false, tag: "C06")
end