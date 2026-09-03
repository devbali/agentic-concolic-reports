# D05 — ROUND 5, GO WIDER than rounds 1-4.
#  * cardinality BEYOND the 0/1/MANY boundary: 10 comments / 4 distinct authors
#    (`IN (?,?,?,?)`) vs 10 comments / 1 author (`= ?`);
#  * visibility COMBINATIONS the matrix never mixed: a post that is public AND
#    share-visible (the join finder wins, so the other two are never issued),
#    and a `share_visibilities.hidden = true` row (the query does not filter it);
#  * formats and entry points not yet driven: :xml, :js, Accept: */*,
#    `session[:mobile_view]` + `format: :html` + signed-in + private-shared,
#    `X_MOBILE_DEVICE` + a mobile User-Agent on a signed-in private-shared post;
#  * a MANY list that mixes the principal's own person, a closed remote account
#    and a third-pod mention, on mobile (the only signed-in view branch);
#  * markdown / bare URLs / `diaspora://…/comment/<guid>` at MANY cardinality;
#  * odd `post_id` values (unicode, trailing newline, empty).
require_relative "_common5"
adv_setup!("D05_wider")
seed_core!

def post!(pid, guid, public_flag: true, author: 2, extra: {})
  CE.insert("posts", **{id: pid, author_id: author, guid: guid, type: "StatusMessage",
                        text: "p#{pid}", public: public_flag, comments_count: 0}.merge(extra))
end
def comment!(cid, pid, author, text)
  CE.insert("comments", id: cid, commentable_id: pid, commentable_type: "Post",
            author_id: author, guid: "cguid#{cid}", text: text,
            created_at: "2020-01-0#{(cid % 9) + 1} 00:00:0#{cid % 10}")
end

# --- cardinality at scale ---------------------------------------------------
post!(650, "d05guid650000000001")
10.times { |i| comment!(900 + i, 650, [1, 2, 5, 6][i % 4], "many authors #{i}") }   # 4 distinct
post!(651, "d05guid651000000001")
10.times { |i| comment!(920 + i, 651, 2, "one author #{i}") }                        # 1 distinct

# --- visibility combinations ------------------------------------------------
post!(652, "d05guid652000000001")                       # PUBLIC and share-visible
CE.insert("share_visibilities", id: 3, shareable_id: 652, shareable_type: "Post",
          user_id: 9, hidden: false)
comment!(940, 652, 2, "public and shared")
post!(653, "d05guid653000000001", public_flag: false)   # private, share row HIDDEN
CE.insert("share_visibilities", id: 4, shareable_id: 653, shareable_type: "Post",
          user_id: 9, hidden: true)
comment!(941, 653, 2, "hidden share visibility")
post!(654, "d05guid654000000001", public_flag: false)   # private, shared with ANOTHER user
CE.insert("share_visibilities", id: 5, shareable_id: 654, shareable_type: "Post",
          user_id: 99, hidden: false)
comment!(942, 654, 2, "shared with somebody else")

# --- a MANY list mixing own / closed / third-pod, with mentions and markdown --
post!(655, "d05guid655000000001")
comment!(950, 655, 1, "**bold** own comment with a bare URL http://example.org/x and <3")
comment!(951, 655, 3, "closed account author\n\nSetext\n======\n\n#tag and `code`")
comment!(952, 655, 6, "third pod author, link diaspora://bob@remote.example/comment/cguid950")
CE.insert("mentions", id: 810, mentions_container_id: 952, mentions_container_type: "Comment",
          person_id: 5)
CE.insert("mentions", id: 811, mentions_container_id: 952, mentions_container_type: "Comment",
          person_id: 6)

CONCRETE_SCENARIOS = adv_scenario("D05-wider") do
  adv_request(post_id: "650", format: :json,   tag: "D05_650_ten_four_authors")
  adv_request(post_id: "650", format: :mobile, tag: "D05_650_ten_four_authors_mobile")
  adv_request(post_id: "651", format: :json,   tag: "D05_651_ten_one_author")
  adv_request(post_id: "651", format: :mobile, tag: "D05_651_ten_one_author_mobile")
  adv_request(post_id: "652", format: :json, signed_in: true, tag: "D05_652_public_and_shared_auth")
  adv_request(post_id: "653", format: :json, signed_in: true, tag: "D05_653_hidden_share_auth")
  adv_request(post_id: "654", format: :json, signed_in: true, tag: "D05_654_shared_with_other_auth")
  adv_request(post_id: "654", format: :json, tag: "D05_654_shared_with_other_anon")
  adv_request(post_id: "655", format: :mobile, signed_in: true, tag: "D05_655_mixed_mobile_auth")
  adv_request(post_id: "655", format: :json,   tag: "D05_655_mixed_json")
  # formats / entry points
  adv_request(post_id: "650", format: :xml,  tag: "D05_650_xml")
  adv_request(post_id: "650", format: :js,   tag: "D05_650_js")
  adv_request(post_id: "650", format: :json, headers: {"Accept" => "*/*"}, tag: "D05_650_accept_star")
  adv_request(post_id: "652", format: :html, signed_in: true, session: {mobile_view: true},
              tag: "D05_652_session_mobile_html_auth")
  adv_request(post_id: "652", format: :html, signed_in: true,
              headers: {"X_MOBILE_DEVICE" => "iPhone",
                        "HTTP_USER_AGENT" => "Mozilla/5.0 (iPhone; CPU iPhone OS 12_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148"},
              tag: "D05_652_xmobile_html_auth")
  # odd post_id values
  adv_request(post_id: "", format: :json, tag: "D05_pid_empty")
  adv_request(post_id: "650\n", format: :json, tag: "D05_pid_newline")
  adv_request(post_id: "650", format: :json, tag: "D05_pid_unicode")
  adv_request(post_id: "d05guid650000000001 ", format: :json, tag: "D05_pid_guid_trailing_space")
end
