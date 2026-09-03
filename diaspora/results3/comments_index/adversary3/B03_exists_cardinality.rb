# B03 — `Post.exists?` CARDINALITY (message_renderer.rb:118-123 diaspora_links).
# The corpus's shim text carries THREE `post` links plus one `comment` link, and
# the `is_post` decision turns the first link into a `comment` one — so the only
# probe counts the corpus can express are 0, 2 and 3. A real comment can carry
# any number.
require_relative "_common3"
adv_setup!("B03_exists_cardinality")
seed_core!

HIT1 = "existsguid00000001" # a post that exists
HIT2 = "existsguid00000002"
CE.insert("posts", id: 990, author_id: 2, guid: HIT1, type: "StatusMessage", text: "t", public: true)
CE.insert("posts", id: 991, author_id: 2, guid: HIT2, type: "StatusMessage", text: "t", public: true)

def linky(id, cguid, text)
  CE.insert("posts", id: id, author_id: 2, guid: "postguid#{id}0000001"[0, 18], type: "StatusMessage",
            text: "p#{id}", public: true, comments_count: 1)
  CE.insert("comments", id: id + 100, commentable_id: id, commentable_type: "Post", author_id: 2,
            guid: cguid, text: text)
end

A = "bob@remote.example"
linky(220, "cguid320", "one link diaspora://#{A}/post/#{HIT1} end")
linky(221, "cguid321", "two links diaspora://#{A}/post/#{HIT1} and diaspora://#{A}/post/missingguid000001 end")
linky(222, "cguid322", "three diaspora://#{A}/post/#{HIT1} diaspora://#{A}/post/#{HIT2} diaspora://#{A}/post/missingguid000001")
linky(223, "cguid323", "only a comment entity link diaspora://#{A}/comment/#{HIT1} end")
linky(224, "cguid324", "five: diaspora://#{A}/post/#{HIT1} diaspora://#{A}/post/#{HIT2} " \
                       "diaspora://#{A}/post/missingguid000001 diaspora://#{A}/post/missingguid000002 " \
                       "web+diaspora://#{A}/post/#{HIT1}")
# 225: TWO comments each carrying one link -> per-row multiplicity
CE.insert("posts", id: 225, author_id: 2, guid: "postguid2250000001", type: "StatusMessage",
          text: "p225", public: true, comments_count: 2)
CE.insert("comments", id: 325, commentable_id: 225, commentable_type: "Post", author_id: 2,
          guid: "cguid325a", text: "first diaspora://#{A}/post/#{HIT1}")
CE.insert("comments", id: 326, commentable_id: 225, commentable_type: "Post", author_id: 2,
          guid: "cguid325b", text: "second diaspora://#{A}/post/#{HIT2}")

CONCRETE_SCENARIOS = adv_scenario("B03-exists-cardinality") do
  %w[220 221 222 223 224 225].each do |p|
    adv_request(post_id: p, format: :json,   tag: "B03_#{p}_json")
    adv_request(post_id: p, format: :mobile, tag: "B03_#{p}_mobile")
  end
end
