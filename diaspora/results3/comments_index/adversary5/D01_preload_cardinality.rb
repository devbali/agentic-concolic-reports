# D01 — ROUND 5, brief item 2d: does the NEW 0/1/MANY cardinality model hold at
# the boundary?  `emit_includes_preloads` picks `= $$(v)` vs `IN ($$(v))` from
# `many = (len(list) > 1)`, i.e. from the OWNER LIST LENGTH.  ActiveRecord's
# `Preloader` keys on `owners.group_by { |o| o[key] }.keys` — the DISTINCT
# foreign-key values — and `PredicateBuilder::ArrayHandler` emits equality for a
# ONE-element key set.  Two comments by the SAME author is therefore a list of
# length 2 whose preload is `= ?`.  Same question one level down: the NESTED
# step (`profiles`) keys on the PARENTS ACTUALLY LOADED, which a dangling
# `mentions.person_id` (no FK, M-3) reduces below the list length.
require_relative "_common5"
adv_setup!("D01_preload_cardinality")
seed_core!

# extra authors so a "many distinct" control exists
CE.insert("people", id: 7, guid: "graceguid00000007", diaspora_handle: "grace@remote.example",
          serialized_public_key: "K7", owner_id: nil, closed_account: false, fetch_status: 0)
CE.insert("profiles", id: 17, person_id: 7, first_name: "Grace", last_name: "G",
          searchable: true, nsfw: false)

def post!(pid, guid)
  CE.insert("posts", id: pid, author_id: 2, guid: guid, type: "StatusMessage",
            text: "p#{pid}", public: true, comments_count: 0)
end

def comment!(cid, pid, author, text: "c#{cid}", at: nil)
  CE.insert("comments", id: cid, commentable_id: pid, commentable_type: "Post",
            author_id: author, guid: "cguid#{cid}", text: text,
            created_at: at || "2020-01-01 00:00:#{format('%02d', cid % 60)}")
end

def mention!(mid, cid, person_id)
  CE.insert("mentions", id: mid, mentions_container_id: cid,
            mentions_container_type: "Comment", person_id: person_id)
end

# --- author-preload cardinality --------------------------------------------
post!(401, "d01guid401000000001"); comment!(501, 401, 2); comment!(502, 401, 2)          # len 2, 1 author
post!(402, "d01guid402000000001"); comment!(503, 402, 2); comment!(504, 402, 2); comment!(505, 402, 2) # len 3, 1 author
post!(403, "d01guid403000000001"); comment!(506, 403, 2); comment!(507, 403, 5)          # len 2, 2 authors
post!(404, "d01guid404000000001"); comment!(508, 404, 2); comment!(509, 404, 2); comment!(510, 404, 5) # len 3, 2 authors
post!(405, "d01guid405000000001"); comment!(511, 405, 2)                                  # len 1
post!(406, "d01guid406000000001"); comment!(512, 406, 2); comment!(513, 406, 2)          # len 2, 1 author (auth)
post!(411, "d01guid411000000001"); comment!(514, 411, 1); comment!(515, 411, 1)          # len 2, author == principal

# --- nested (mentions -> person -> profile) cardinality ---------------------
post!(407, "d01guid407000000001"); comment!(516, 407, 2, text: "two live mentions")
mention!(601, 516, 5); mention!(602, 516, 6)                                             # 2 live
post!(408, "d01guid408000000001"); comment!(517, 408, 2, text: "one dangling mention")
mention!(603, 517, 5); mention!(604, 517, 998)                                           # 1 live + 1 dangling
post!(409, "d01guid409000000001"); comment!(518, 409, 2, text: "two dangling mentions")
mention!(605, 518, 5); mention!(606, 518, 997); mention!(607, 518, 996)                  # 1 live + 2 dangling
post!(410, "d01guid410000000001"); comment!(519, 410, 2); comment!(520, 410, 2)
mention!(608, 519, 5); mention!(609, 520, 6)                                             # 2 comments, 1 mention each

CONCRETE_SCENARIOS = adv_scenario("D01-preload-cardinality") do
  adv_request(post_id: "405", format: :json, tag: "D01_405_one_comment")
  adv_request(post_id: "401", format: :json, tag: "D01_401_two_same_author")
  adv_request(post_id: "402", format: :json, tag: "D01_402_three_same_author")
  adv_request(post_id: "403", format: :json, tag: "D01_403_two_distinct")
  adv_request(post_id: "404", format: :json, tag: "D01_404_three_two_distinct")
  adv_request(post_id: "401", format: :mobile, tag: "D01_401_two_same_author_mobile")
  adv_request(post_id: "403", format: :mobile, tag: "D01_403_two_distinct_mobile")
  adv_request(post_id: "407", format: :json, tag: "D01_407_two_live_mentions")
  adv_request(post_id: "408", format: :json, tag: "D01_408_one_dangling_mention")
  adv_request(post_id: "409", format: :json, tag: "D01_409_two_dangling_mentions")
  adv_request(post_id: "410", format: :json, tag: "D01_410_two_comments_one_mention_each")
  adv_request(post_id: "406", format: :json, signed_in: true, tag: "D01_406_two_same_author_auth")
  adv_request(post_id: "411", format: :mobile, signed_in: true, tag: "D01_411_own_two_comments_mobile")
end
