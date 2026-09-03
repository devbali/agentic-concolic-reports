# G07 — ROUND 7: make the W7-1 partial-load raise a STATEMENT-SET difference,
# not only a terminal difference. A comment whose mentions preload loaded SOME
# of its parents raises inside `Mentionable.format` on mobile; every statement
# the REST of the collection would have issued is then never issued. The corpus
# binds that raise to `_person_not_found == True` (no nested `profiles` read at
# all) and renders every partial-load state to completion.
require_relative "_common7"
adv_setup!("G07_truncation")
seed_core!

def post!(pid, guid, public_flag: true, author: 2)
  CE.insert("posts", id: pid, author_id: author, guid: guid, type: "StatusMessage",
            text: "p#{pid}", public: public_flag, comments_count: 0)
end
def comment!(cid, pid, author, text)
  CE.insert("comments", id: cid, commentable_id: pid, commentable_type: "Post",
            author_id: author, guid: "g7cguid#{cid}", text: text,
            created_at: "2020-01-01 00:00:#{format('%02d', cid % 60)}")
end
def mention!(mid, cid, person_id)
  CE.insert("mentions", id: mid, mentions_container_id: cid,
            mentions_container_type: "Comment", person_id: person_id)
end

ERIN  = "@{Erin; erin@other.example}"
FRANK = "@{Frank; frank@third.example}"
GHOST = "@{Ghost; ghost@nowhere.example}"
LIVEG = "g07guid960000000001"
DLINK = "diaspora://alice@localhost/post/#{LIVEG}"

# 960 TRUNCATION: comment 1 partial-loads and RAISES; comment 2 would issue a
#     mentions SELECT, a people/profiles preload and a Post.exists? probe.
post!(960, LIVEG)
comment!(970, 960, 2, "first #{ERIN} #{GHOST}")
mention!(900, 970, 5); mention!(901, 970, 995)
comment!(971, 960, 5, "second #{FRANK} #{DLINK}")
mention!(902, 971, 6)
# 961 CONTROL: identical fixtures, comment 1's markup names only the LIVE person
post!(961, "g07guid961000000001")
comment!(972, 961, 2, "first #{ERIN}")
mention!(903, 972, 5); mention!(904, 972, 995)
comment!(973, 961, 5, "second #{FRANK} #{DLINK}")
mention!(905, 973, 6)
# 962 nested step shrinks 3 -> 1 (two of three parents dangling)
post!(962, "g07guid962000000001")
comment!(974, 962, 2, "three #{ERIN}")
mention!(906, 974, 5); mention!(907, 974, 994); mention!(908, 974, 995)
# 963 json partial load, FIRST parent dangling (bind side of 2c)
post!(963, "g07guid963000000001")
comment!(975, 963, 2, "json first dangling")
mention!(909, 975, 995); mention!(910, 975, 5)
# 964 json partial load, SECOND parent dangling
post!(964, "g07guid964000000001")
comment!(976, 964, 2, "json second dangling")
mention!(911, 976, 5); mention!(912, 976, 995)
# 965 two comments, each with a dlink (Post.exists? multiplicity per render)
post!(965, "g07guid965000000001")
comment!(977, 965, 2, "a #{DLINK} b"); comment!(978, 965, 5, "c #{DLINK} d")

CONCRETE_SCENARIOS = adv_scenario("G07-truncation") do
  adv_request(post_id: "961", format: :mobile, tag: "G07_961_control_full_render")
  adv_request(post_id: "960", format: :mobile, tag: "G07_960_truncated_by_partial_raise")
  adv_request(post_id: "962", format: :mobile, tag: "G07_962_three_to_one_mobile")
  adv_request(post_id: "962", format: :json,   tag: "G07_962_three_to_one_json")
  adv_request(post_id: "963", format: :json,   tag: "G07_963_first_dangling_json")
  adv_request(post_id: "964", format: :json,   tag: "G07_964_second_dangling_json")
  adv_request(post_id: "963", format: :mobile, tag: "G07_963_first_dangling_mobile")
  adv_request(post_id: "964", format: :mobile, tag: "G07_964_second_dangling_mobile")
  adv_request(post_id: "965", format: :json,   tag: "G07_965_two_dlinks_json")
  adv_request(post_id: "965", format: :mobile, tag: "G07_965_two_dlinks_mobile")
end
