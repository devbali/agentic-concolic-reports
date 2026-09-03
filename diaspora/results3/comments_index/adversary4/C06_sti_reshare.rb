# C06 — GO WIDER: STI posts (StatusMessage / Reshare / Photo), a Reshare whose
# root is missing, and a `posts.type` outside the Post STI tree. `posts.type`
# is NOT NULL (schema.rb:411) and is minted in the corpus as a placeholder
# string, so the STI dispatch never runs concolically.
require_relative "_common4"
adv_setup!("C06_sti_reshare")
seed_core!

def commented!(pid, guid, type, extra = {})
  CE.insert("posts", **{id: pid, author_id: 2, guid: guid, type: type, text: "p#{pid}",
                        public: true, comments_count: 1}.merge(extra))
  CE.insert("comments", id: pid + 100, commentable_id: pid, commentable_type: "Post",
            author_id: 2, guid: "cguid#{pid}", text: "comment on #{pid}")
end

commented!(370, "stiguid37000000001", "StatusMessage")
commented!(371, "stiguid37100000001", "Reshare", root_guid: "missingroot0000001")
CE.insert("posts", id: 379, author_id: 2, guid: "realroot000000001", type: "StatusMessage",
          text: "root", public: true, comments_count: 0)
commented!(372, "stiguid37200000001", "Reshare", root_guid: "realroot000000001")
commented!(373, "stiguid37300000001", "Photo")
commented!(374, "stiguid37400000001", "Bogus")
commented!(375, "stiguid37500000001", "ActivityStreams::Photo")   # a class this app version removed
# a comment whose commentable_type names the STI SUBCLASS instead of the base
CE.insert("posts", id: 376, author_id: 2, guid: "stiguid37600000001", type: "StatusMessage",
          text: "p376", public: true, comments_count: 1)
CE.insert("comments", id: 476, commentable_id: 376, commentable_type: "StatusMessage",
          author_id: 2, guid: "cguid476", text: "subclass commentable_type")

CONCRETE_SCENARIOS = adv_scenario("C06-sti-reshare") do
  [370, 371, 372, 373, 374, 375, 376].each do |pid|
    adv_request(post_id: pid.to_s, format: :json, tag: "C06_#{pid}_json")
  end
  [370, 371, 373, 375].each do |pid|
    adv_request(post_id: pid.to_s, format: :mobile, tag: "C06_#{pid}_mobile")
  end
  adv_request(post_id: "371", format: :json, signed_in: true, tag: "C06_371_json_auth")
  adv_request(post_id: "373", format: :json, signed_in: true, tag: "C06_373_json_auth")
  adv_request(post_id: "stiguid37300000001", format: :json, tag: "C06_373_json_guid")
end
