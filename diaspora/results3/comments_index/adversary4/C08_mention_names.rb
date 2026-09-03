# C08 — brief item 2c, first half: the `_text_mention_has_name` decision on
# REAL texts. `Mentionable::REGEX` makes the display name optional, so
# `@{handle}` and `@{Name; handle}` are both real markup. Every mentioned
# person here HAS a profiles row, so `Person#name` resolves without touching
# `fix_profile` — this isolates the display-name branch from the discovery
# wall (which C09 attacks separately).
require_relative "_common4"
adv_setup!("C08_mention_names")
seed_core!

def mk(pid, cid, text, person_ids)
  CE.insert("posts", id: pid, author_id: 2, guid: "mnguid#{pid}00000001", type: "StatusMessage",
            text: "p#{pid}", public: true, comments_count: 1)
  CE.insert("comments", id: cid, commentable_id: pid, commentable_type: "Post", author_id: 2,
            guid: "cguid#{cid}", text: text)
  person_ids.each_with_index do |p, i|
    CE.insert("mentions", id: cid * 10 + i, mentions_container_id: cid,
              mentions_container_type: "Comment", person_id: p)
  end
end

mk(390, 490, "with name @{Bob; bob@remote.example} end", [2])
mk(391, 491, "no name @{bob@remote.example} end", [2])
mk(392, 492, "both @{Bob; bob@remote.example} and @{erin@other.example} end", [2, 5])
# markup whose handle matches NO mention row (mentioned_people is empty)
mk(393, 493, "orphan markup @{Nobody; nobody@remote.example} end", [])
# markup whose handle does not match the mention row's person handle
mk(394, 494, "mismatch @{Bob; someone.else@remote.example} end", [2])
# a mention person on ANOTHER pod, no display name
mk(395, 495, "otherpod @{frank@third.example} end", [6])
# mention markup with a name containing a semicolon-free unicode name
mk(396, 496, "uni @{Żółć Ćma; erin@other.example} end", [5])

CONCRETE_SCENARIOS = adv_scenario("C08-mention-names") do
  (390..396).each do |pid|
    adv_request(post_id: pid.to_s, format: :json,   tag: "C08_#{pid}_json")
    adv_request(post_id: pid.to_s, format: :mobile, tag: "C08_#{pid}_mobile")
  end
  adv_request(post_id: "392", format: :json, signed_in: true, tag: "C08_392_json_auth")
  adv_request(post_id: "392", format: :mobile, signed_in: true, tag: "C08_392_mobile_auth")
end
