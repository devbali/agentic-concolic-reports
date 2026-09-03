# D04 — ROUND 5, brief item 1: re-verify EVERY prior finding on THIS corpus at
# projection level (incl. the new judge dimensions `=` vs `IN`, LIMIT, ORDER BY):
# the `diaspora://…/post/<guid>` -> `Post.exists?` family (M-1/W1), the `:mobile`
# format (M-2/W2), D1/D5/D7/D9, M-3 (dangling mention) and M-4 (empty relation).
require_relative "_common5"
adv_setup!("D04_reverify")
seed_core!

def link(n, entity = "post", scheme = "diaspora")
  "#{scheme}://bob@remote.example/#{entity}/rvguid0000000000#{n}"
end
[1, 2, 3].each do |n|   # 1..3 exist, 8/9 do not
  CE.insert("posts", id: 600 + n, author_id: 2, guid: "rvguid0000000000#{n}",
            type: "StatusMessage", text: "t#{n}", public: true, comments_count: 0)
end

def post!(pid, guid, public_flag: true, author: 2)
  CE.insert("posts", id: pid, author_id: author, guid: guid, type: "StatusMessage",
            text: "p#{pid}", public: public_flag, comments_count: 0)
end
def comment!(cid, pid, text, author: 2)
  CE.insert("comments", id: cid, commentable_id: pid, commentable_type: "Post",
            author_id: author, guid: "cguid#{cid}", text: text,
            created_at: "2020-01-01 00:00:0#{cid % 10}")
end

# --- M-1 / W1: the exists? family ------------------------------------------
post!(610, "d04guid610000000001"); comment!(700, 610, "no links here")
post!(611, "d04guid611000000001"); comment!(701, 611, "one #{link(1)}")
post!(612, "d04guid612000000001"); comment!(702, 612, "two #{link(1)} #{link(2)}")
post!(613, "d04guid613000000001"); comment!(703, 613, "three #{link(1)} #{link(2)} #{link(9)}")
post!(614, "d04guid614000000001"); comment!(704, 614, "comment entity #{link(1, 'comment')} only")
post!(615, "d04guid615000000001"); comment!(705, 615, "webplus #{link(2, 'post', 'web+diaspora')}")

# --- M-3: dangling mentions.person_id (no FK) -------------------------------
post!(620, "d04guid620000000001"); comment!(710, 620, "dangling mention here")
CE.insert("mentions", id: 800, mentions_container_id: 710, mentions_container_type: "Comment",
          person_id: 9990)
post!(621, "d04guid621000000001"); comment!(711, 621, "live mention here")
CE.insert("mentions", id: 801, mentions_container_id: 711, mentions_container_type: "Comment",
          person_id: 5)

# --- M-4 / D9: empty comment collections ------------------------------------
post!(630, "d04guid630000000001")                                   # public, no comments
post!(631, "d04guid631000000001", public_flag: false)               # private, shared, no comments
CE.insert("share_visibilities", id: 2, shareable_id: 631, shareable_type: "Post",
          user_id: 9, hidden: false)
post!(632, "d04guid632000000001"); comment!(712, 632, "no mentions at all")   # 0 mentions

# --- D5 / D7 / D1 / visibility ----------------------------------------------
post!(640, "d04guid640000000001"); comment!(713, 640, "public arm")           # signed-in public arm
post!(641, "d04guid641000000001", public_flag: false)                          # anon private -> 401
post!(642, "d04guid642000000001", public_flag: false, author: 1); comment!(714, 642, "own")  # auth own
CE.insert("posts", id: 643, author_id: 2, guid: "abcdefghijklmno", type: "StatusMessage",
          text: "len15guid", public: true, comments_count: 0)                  # 15-char guid

CONCRETE_SCENARIOS = adv_scenario("D04-reverify") do
  # exists? family
  [610, 611, 612, 613, 614, 615].each do |pid|
    adv_request(post_id: pid.to_s, format: :json, tag: "D04_#{pid}_json")
  end
  [611, 613].each do |pid|
    adv_request(post_id: pid.to_s, format: :mobile, tag: "D04_#{pid}_mobile")
  end
  adv_request(post_id: "612", format: :json, signed_in: true, tag: "D04_612_json_auth")
  # M-3
  adv_request(post_id: "620", format: :json,   tag: "D04_620_dangling_json")
  adv_request(post_id: "620", format: :mobile, tag: "D04_620_dangling_mobile")
  adv_request(post_id: "621", format: :json,   tag: "D04_621_live_json")
  # M-4 / D9
  adv_request(post_id: "630", format: :json,   tag: "D04_630_empty_json")
  adv_request(post_id: "630", format: :mobile, tag: "D04_630_empty_mobile")
  adv_request(post_id: "d04guid630000000001", format: :json, tag: "D04_630_empty_byguid")
  adv_request(post_id: "631", format: :mobile, signed_in: true, tag: "D04_631_empty_shared_mobile_auth")
  adv_request(post_id: "632", format: :json,   tag: "D04_632_nomentions_json")
  # D7 / D5 / visibility
  adv_request(post_id: "640", format: :json, signed_in: true, tag: "D04_640_public_auth")
  adv_request(post_id: "642", format: :json, signed_in: true, tag: "D04_642_own_auth")
  adv_request(post_id: "641", format: :json,   tag: "D04_641_private_anon")
  adv_request(post_id: "641", format: :mobile, tag: "D04_641_private_anon_mobile")
  adv_request(post_id: "999999", format: :json, tag: "D04_missing_json")
  adv_request(post_id: "abcdefghijklmno",   format: :json, tag: "D04_key_len15")
  adv_request(post_id: "d04guid610000000001", format: :json, tag: "D04_key_len19")
  adv_request(post_id: "610", format: :html, tag: "D04_610_html")
end
