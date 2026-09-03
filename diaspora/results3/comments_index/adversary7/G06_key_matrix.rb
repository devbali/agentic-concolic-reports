# G06 — ROUND 7: the projection-level re-verification matrix for the preload key
# model (M-7, M-8, M-10, M-11, M-12) and for 2(d) — the shared `_row2_` variable
# in the state where the second row's author IS the first row's author.
require_relative "_common7"
adv_setup!("G06_key_matrix")
seed_core!
CE.insert("people", id: 7, guid: "graceguid00000007", diaspora_handle: "grace@remote.example",
          serialized_public_key: "K7", owner_id: nil, closed_account: false, fetch_status: 0)
CE.insert("profiles", id: 17, person_id: 7, first_name: "Grace", last_name: "G", searchable: true, nsfw: false)

def post!(pid, guid, public_flag: true, author: 2)
  CE.insert("posts", id: pid, author_id: author, guid: guid, type: "StatusMessage",
            text: "p#{pid}", public: public_flag, comments_count: 0)
end
def comment!(cid, pid, author, text = "c#{cid}")
  CE.insert("comments", id: cid, commentable_id: pid, commentable_type: "Post",
            author_id: author, guid: "g6cguid#{cid}", text: text,
            created_at: "2020-01-01 00:00:#{format('%02d', cid % 60)}")
end
def mention!(mid, cid, person_id)
  CE.insert("mentions", id: mid, mentions_container_id: cid,
            mentions_container_type: "Comment", person_id: person_id)
end

post!(930, "g06guid930000000001"); comment!(940, 930, 2)                       # 1c/1a
post!(931, "g06guid931000000001"); comment!(941, 931, 2); comment!(942, 931, 5) # 2c/2a
post!(932, "g06guid932000000001"); comment!(943, 932, 2); comment!(944, 932, 2) # 2c/1a  (M-7, 2d)
post!(933, "g06guid933000000001"); comment!(945, 933, 2, "two live mentions")
mention!(900, 945, 5); mention!(901, 945, 6)                                    # M-10
post!(934, "g06guid934000000001"); comment!(946, 934, 2, "one live one dead")
mention!(902, 946, 5); mention!(903, 946, 995)                                  # M-8
post!(935, "g06guid935000000001"); comment!(947, 935, 2, "one dead")
mention!(904, 947, 995)
post!(936, "g06guid936000000001")
comment!(948, 936, 2); comment!(949, 936, 5); comment!(950, 936, 7)             # 3c/3a
mention!(905, 948, 5)                                                           # author of c949 is mentioned by c948
post!(937, "g06guid937000000001", public_flag: false)
CE.insert("share_visibilities", id: 41, shareable_id: 937, shareable_type: "Post", user_id: 9, hidden: false)
comment!(951, 937, 2); comment!(952, 937, 2)                                    # auth, 2c/1a

CONCRETE_SCENARIOS = adv_scenario("G06-key-matrix") do
  adv_probe("for_a_stream_sql") { Post.find(930).comments.for_a_stream.to_sql }
  adv_probe("includes_values") { Post.find(930).comments.for_a_stream.includes_values.inspect }
  adv_probe("mentions_sql")   { Comment.find(945).mentions.includes(person: :profile).to_sql }
  adv_probe("Comment.author refl") {
    r = Comment.reflect_on_association(:author)
    [r.macro, r.foreign_key, r.klass.name, Person.reflect_on_association(:profile).macro]
  }
  adv_request(post_id: "930", format: :json,   tag: "G06_930_1c1a_json")
  adv_request(post_id: "931", format: :json,   tag: "G06_931_2c2a_json")
  adv_request(post_id: "932", format: :json,   tag: "G06_932_2c1a_json")
  adv_request(post_id: "932", format: :mobile, tag: "G06_932_2c1a_mobile")
  adv_request(post_id: "933", format: :json,   tag: "G06_933_2live_mentions_json")
  adv_request(post_id: "933", format: :mobile, tag: "G06_933_2live_mentions_mobile")
  adv_request(post_id: "934", format: :json,   tag: "G06_934_partial_mentions_json")
  adv_request(post_id: "935", format: :json,   tag: "G06_935_one_dead_mention_json")
  adv_request(post_id: "936", format: :json,   tag: "G06_936_3c3a_json")
  adv_request(post_id: "936", format: :mobile, tag: "G06_936_3c3a_mobile")
  adv_request(post_id: "937", format: :json, signed_in: true, uid: 9, tag: "G06_937_auth_2c1a_json")
end
