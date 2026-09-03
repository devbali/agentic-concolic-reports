# C02 — brief item 2b: the nested link-count chain (`ge2/ge3/ge4`, "4 = four or
# more") against REAL texts with 0,1,2,3,4,5,6 `diaspora://` post links plus
# comment-entity links, and the `web+diaspora://` variant. Also re-verifies
# round-1 W1 (the `Post.exists?` existence-probe family) at projection level.
require_relative "_common4"
adv_setup!("C02_link_cardinality")
seed_core!

H = "bob@remote.example"
def link(n, entity = "post", scheme = "diaspora")
  "#{scheme}://bob@remote.example/#{entity}/linkguid00000000#{n}"
end

# rows so that some probes hit and some miss
[1, 2, 3, 4, 5, 6, 7, 8].each do |n|
  CE.insert("posts", id: 500 + n, author_id: 2, guid: "linkguid00000000#{n}",
            type: "StatusMessage", text: "target #{n}", public: true, comments_count: 0)
end

def make(post_id, comment_id, text)
  CE.insert("posts", id: post_id, author_id: 2, guid: "cardguid#{post_id}00000001",
            type: "StatusMessage", text: "p#{post_id}", public: true, comments_count: 1)
  CE.insert("comments", id: comment_id, commentable_id: post_id, commentable_type: "Post",
            author_id: 2, guid: "cguid#{comment_id}", text: text)
end

make(320, 420, "no links at all here")                                            # 0
make(321, 421, "one #{link(1)} link")                                             # 1
make(322, 422, "two #{link(1)} and #{link(2)}")                                   # 2
make(323, 423, "three #{link(1)} #{link(2)} #{link(3)}")                          # 3
make(324, 424, "four #{link(1)} #{link(2)} #{link(3)} #{link(4)}")                # 4
make(325, 425, "five #{link(1)} #{link(2)} #{link(3)} #{link(4)} #{link(5)}")     # 5
make(326, 426, "six #{link(1)} #{link(2)} #{link(3)} #{link(4)} #{link(5)} #{link(6)}") # 6
make(327, 427, "comment entity only #{link(1, 'comment')}")                       # 0 probes
make(328, 428, "first is comment #{link(1, 'comment')} then #{link(2)} #{link(3)}") # 2 probes
make(329, 429, "middle is comment #{link(1)} #{link(2, 'comment')} #{link(3)}")   # 2 probes
make(330, 430, "web+ #{link(1, 'post', 'web+diaspora')} and #{link(9)}")          # 2 probes (one miss)
make(331, 431, "status_message entity #{link(1, 'status_message')} plus #{link(2)}") # 1 probe
# two comments on one post, one link each -> 2 probes per render
CE.insert("posts", id: 332, author_id: 2, guid: "cardguid33200000001", type: "StatusMessage",
          text: "p332", public: true, comments_count: 2)
CE.insert("comments", id: 432, commentable_id: 332, commentable_type: "Post", author_id: 2,
          guid: "cguid432", text: "c1 #{link(1)}")
CE.insert("comments", id: 433, commentable_id: 332, commentable_type: "Post", author_id: 2,
          guid: "cguid433", text: "c2 #{link(2)}")
# the SAME guid twice in one comment -> 2 probes for the same value
make(333, 434, "dup #{link(1)} and again #{link(1)}")

CONCRETE_SCENARIOS = adv_scenario("C02-link-cardinality") do
  (320..333).each do |pid|
    next if pid == 332 # handled below in both formats too
    adv_request(post_id: pid.to_s, format: :json,   tag: "C02_#{pid}_json")
  end
  [321, 324, 326, 327, 330].each do |pid|
    adv_request(post_id: pid.to_s, format: :mobile, tag: "C02_#{pid}_mobile")
  end
  adv_request(post_id: "332", format: :json,   tag: "C02_332_json")
  adv_request(post_id: "332", format: :mobile, tag: "C02_332_mobile")
end
