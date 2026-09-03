# D03 — ROUND 5, brief items 2b + 2c.
#   2b: is the TWO-valued `posts.type` decision enough?  The corpus pins the
#       in-tree arm to "StatusMessage" and the out-of-tree arm to "Photo".
#       Attacked: the OTHER in-tree values (`Post` itself, `Reshare` with a
#       missing root at MANY cardinality) and the values that are neither —
#       `""` and `"   "`, which `using_single_table_inheritance?` rejects with
#       `present?` so ActiveRecord instantiates the BASE class instead of
#       raising, a third real outcome of the same column.
#   2c: does the `UninstantiableRow` poison hold on paths the batch did not
#       enumerate?  The raise is moved from INSIDE `.first` (real) to the first
#       app method call (mock), so every finder ARM must be driven for real:
#       anon `first`, and all three `EvilQuery::VisibleShareableById` finders
#       (`querent_has_visibility` / `querent_is_author` / `public_post`), on
#       json and mobile, against a PUBLIC and a PRIVATE out-of-tree row.
require_relative "_common5"
adv_setup!("D03_sti_poison")
seed_core!

def sti!(pid, guid, type, public_flag: true, author: 2, ncomments: 1, extra: {})
  CE.insert("posts", **{id: pid, author_id: author, guid: guid, type: type, text: "p#{pid}",
                        public: public_flag, comments_count: ncomments}.merge(extra))
  ncomments.times do |i|
    CE.insert("comments", id: pid * 10 + i, commentable_id: pid, commentable_type: "Post",
              author_id: 2, guid: "cg#{pid}#{i}", text: "c#{pid}#{i}",
              created_at: "2020-01-01 00:00:0#{i}")
  end
end

# --- 2b: in-tree and "not-STI-at-all" values --------------------------------
sti!(420, "d03guid420000000001", "StatusMessage")
sti!(421, "d03guid421000000001", "Post")                 # the BASE class as a literal
sti!(422, "d03guid422000000001", "")                     # NOT NULL but blank -> using_sti? false
sti!(423, "d03guid423000000001", "   ")                  # whitespace -> same
sti!(424, "d03guid424000000001", "Reshare", extra: {root_guid: "d03missingroot00001"}, ncomments: 2)
sti!(425, "d03guid425000000001", "StatusMessage", ncomments: 2)   # control for 424 at len 2

# --- 2c: out-of-tree rows reached through every finder arm ------------------
sti!(430, "d03guid430000000001", "Photo")                          # anon `first`, public
sti!(431, "d03guid431000000001", "Photo", public_flag: false)      # anon `first`, PRIVATE
sti!(432, "d03guid432000000001", "Photo", public_flag: false)      # auth, share_visibility  -> ci_vis
CE.insert("share_visibilities", id: 1, shareable_id: 432, shareable_type: "Post", user_id: 9, hidden: false)
sti!(433, "d03guid433000000001", "Photo", public_flag: false, author: 1)  # auth, own -> ci_author
sti!(434, "d03guid434000000001", "Photo")                          # auth, public -> ci_public
sti!(435, "d03guid435000000001", "Comment")                        # a real class, not a Post subclass
sti!(436, "d03guid436000000001", "StatusMessage ")                 # trailing space -> constantize fails
sti!(437, "d03guid437000000001", "statusmessage")                  # wrong case

CONCRETE_SCENARIOS = adv_scenario("D03-sti-poison") do
  # 2b
  adv_request(post_id: "420", format: :json, tag: "D03_420_statusmessage")
  adv_request(post_id: "421", format: :json, tag: "D03_421_type_Post")
  adv_request(post_id: "422", format: :json, tag: "D03_422_type_blank")
  adv_request(post_id: "423", format: :json, tag: "D03_423_type_spaces")
  adv_request(post_id: "422", format: :mobile, tag: "D03_422_type_blank_mobile")
  adv_request(post_id: "424", format: :json, tag: "D03_424_reshare_noroot_len2")
  adv_request(post_id: "425", format: :json, tag: "D03_425_statusmessage_len2")
  adv_request(post_id: "424", format: :mobile, signed_in: true, tag: "D03_424_reshare_mobile_auth")
  # 2c — every finder arm
  adv_request(post_id: "430", format: :json, tag: "D03_430_oot_anon_public_json")
  adv_request(post_id: "430", format: :mobile, tag: "D03_430_oot_anon_public_mobile")
  adv_request(post_id: "431", format: :json, tag: "D03_431_oot_anon_PRIVATE_json")
  adv_request(post_id: "432", format: :json, signed_in: true, tag: "D03_432_oot_auth_visibility_json")
  adv_request(post_id: "433", format: :json, signed_in: true, tag: "D03_433_oot_auth_own_json")
  adv_request(post_id: "434", format: :json, signed_in: true, tag: "D03_434_oot_auth_public_json")
  adv_request(post_id: "434", format: :mobile, signed_in: true, tag: "D03_434_oot_auth_public_mobile")
  adv_request(post_id: "435", format: :json, tag: "D03_435_type_Comment")
  adv_request(post_id: "436", format: :json, tag: "D03_436_type_trailing_space")
  adv_request(post_id: "437", format: :json, tag: "D03_437_type_lowercase")
  adv_request(post_id: "d03guid430000000001", format: :json, tag: "D03_430_oot_by_guid")

  # what the app's OWN constant map says about the STI tree
  adv_probe("post_descendants") { Post.descendants.map(&:name).sort }
  adv_probe("photo_superclass") { Photo.superclass.name rescue "n/a" }
  adv_probe("blank_type_class") { Post.where(id: 422).first.class.name rescue $!.class.name }
end
