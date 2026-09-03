# B07 — STI on `posts`. `posts.type` is NOT NULL; the corpus never varies it
# (H5 ledger pins `commentable_type`, but the POST's own STI type is only ever
# whatever the rep's class is). StatusMessage / Reshare (dangling root and real
# root) / Photo / an unknown type, anon and signed-in, json and mobile.
require_relative "_common3"
adv_setup!("B07_sti_posts")
seed_core!
CE.insert("posts", id: 990, author_id: 2, guid: "rootguid0000000001", type: "StatusMessage",
          text: "the root", public: true, comments_count: 0)

def sti(id, type, guid, extra = {})
  CE.insert("posts", **{ id: id, author_id: 2, guid: guid, type: type,
                         text: "p#{id}", public: true, comments_count: 1 }.merge(extra))
  CE.insert("comments", id: id + 100, commentable_id: id, commentable_type: "Post", author_id: 2,
            guid: "cg#{id}", text: "comment on a #{type}")
end

sti(230, "StatusMessage", "postguid2300000001")
sti(231, "Reshare",       "postguid2310000001", root_guid: "nosuchrootguid00001")
sti(232, "Reshare",       "postguid2320000001", root_guid: "rootguid0000000001")
sti(233, "Photo",         "postguid2330000001")
sti(234, "Bogus",         "postguid2340000001")
# 235: a comment whose commentable_type is the STI SUBCLASS name, not the base
CE.insert("posts", id: 235, author_id: 2, guid: "postguid2350000001", type: "StatusMessage",
          text: "p235", public: true, comments_count: 1)
CE.insert("comments", id: 335, commentable_id: 235, commentable_type: "StatusMessage", author_id: 2,
          guid: "cg235", text: "commentable_type is the subclass name")

CONCRETE_SCENARIOS = adv_scenario("B07-sti-posts") do
  %w[230 231 232 233 234 235].each do |p|
    adv_request(post_id: p, format: :json,   tag: "B07_#{p}_json")
    adv_request(post_id: p, format: :mobile, tag: "B07_#{p}_mobile")
  end
  adv_request(post_id: "232", format: :json, signed_in: true, tag: "B07_232_json_auth")
end
