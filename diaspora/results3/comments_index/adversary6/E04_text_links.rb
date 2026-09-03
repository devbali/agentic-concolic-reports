# E04 — ROUND 6, brief item 3: markdown / bare URLs / `diaspora://…/comment/<guid>`
# and the whole `diaspora_links` family, re-verified at projection level (M-1)
# and pushed past the corpus's modelled cardinality.
#  * a `comment`-entity link ONLY  -> the `&&` short-circuits, ZERO `exists?`
#  * a comment-link BEFORE a post-link -> the exists? binds the SECOND link's guid
#  * 5 and 7 post links in one comment (corpus tops out at 4)
#  * duplicate guid twice in one text
#  * bare URLs, markdown image, setext heading, #tag, `<3`, unicode
#  * json (plain_text_for_json) AND mobile (markdownified), anon and signed-in
require_relative "_common6"
adv_setup!("E04_text_links")
seed_core!

def post!(pid, guid, public_flag: true, author: 2)
  CE.insert("posts", id: pid, author_id: author, guid: guid, type: "StatusMessage",
            text: "p#{pid}", public: public_flag, comments_count: 0)
end
def comment!(cid, pid, author, text)
  CE.insert("comments", id: cid, commentable_id: pid, commentable_type: "Post",
            author_id: author, guid: "e4cguid#{cid}", text: text,
            created_at: "2020-01-01 00:00:#{format('%02d', cid % 60)}")
end
G = "e04guid730000000001"
post!(730, G); comment!(870, 730, 2, "root post, no links")

# comment-entity link only -> 0 exists?
post!(731, "e04guid731000000001")
comment!(871, 731, 2, "only a comment link diaspora://bob@remote.example/comment/e4cguid870 end")
# comment link FIRST, post link SECOND -> exactly 1 exists?, on the SECOND guid
post!(732, "e04guid732000000001")
comment!(872, 732, 2, "diaspora://bob@remote.example/comment/e4cguid870 then " \
                      "diaspora://bob@remote.example/post/#{G} end")
# 5 post links (3 hit, 2 miss)
post!(733, "e04guid733000000001")
comment!(873, 733, 2, (1..5).map { |i|
  g = i.odd? ? G : "e04nolink000000000#{i}"
  "diaspora://bob@remote.example/post/#{g}"
}.join(" "))
# 7 post links, all misses
post!(734, "e04guid734000000001")
comment!(874, 734, 2, (1..7).map { |i| "diaspora://bob@remote.example/post/e04miss00000000000#{i}" }.join(" "))
# duplicate guid twice
post!(735, "e04guid735000000001")
comment!(875, 735, 2, "diaspora://a@b/post/#{G} and again diaspora://a@b/post/#{G}")
# markdown, bare URL, markdown image, setext, tag, <3, unicode, web+diaspora
post!(736, "e04guid736000000001")
comment!(876, 736, 2, "Heading\n=======\n\n**bold** _em_ `code` <3 #tag\n" \
                      "bare http://example.org/a?b=c&d=e and https://example.org/x\n" \
                      "![img](http://example.org/i.png) [l](http://example.org/l)\n" \
                      "web+diaspora://bob@remote.example/post/#{G}\n" \
                      "diaspora://bob@remote.example/status_message/#{G}\n" \
                      "‪#‎ünicode‬ éàø")
# two comments, one link each, both hits
post!(737, "e04guid737000000001")
comment!(877, 737, 2, "diaspora://a@b/post/#{G}")
comment!(878, 737, 5, "diaspora://a@b/post/e04guid731000000001")
# a link inside a MENTION-bearing comment, mobile-safe (display name given)
post!(738, "e04guid738000000001")
comment!(879, 738, 2, "hi @{Erin; erin@other.example} see diaspora://a@b/post/#{G}")
CE.insert("mentions", id: 920, mentions_container_id: 879, mentions_container_type: "Comment", person_id: 5)

CONCRETE_SCENARIOS = adv_scenario("E04-text-links") do
  adv_request(post_id: "731", format: :json,   tag: "E04_731_comment_link_only")
  adv_request(post_id: "731", format: :mobile, tag: "E04_731_comment_link_only_mobile")
  adv_request(post_id: "732", format: :json,   tag: "E04_732_comment_then_post_link")
  adv_request(post_id: "732", format: :mobile, tag: "E04_732_comment_then_post_link_mobile")
  adv_request(post_id: "733", format: :json,   tag: "E04_733_five_links")
  adv_request(post_id: "733", format: :mobile, tag: "E04_733_five_links_mobile")
  adv_request(post_id: "734", format: :json,   tag: "E04_734_seven_links_all_miss")
  adv_request(post_id: "735", format: :json,   tag: "E04_735_duplicate_guid")
  adv_request(post_id: "736", format: :json,   tag: "E04_736_markdown_urls")
  adv_request(post_id: "736", format: :mobile, tag: "E04_736_markdown_urls_mobile")
  adv_request(post_id: "737", format: :json,   tag: "E04_737_two_comments_one_link_each")
  adv_request(post_id: "738", format: :json,   tag: "E04_738_mention_plus_link")
  adv_request(post_id: "738", format: :mobile, tag: "E04_738_mention_plus_link_mobile")
  adv_request(post_id: "733", format: :json, signed_in: true, tag: "E04_733_five_links_auth")
  adv_request(post_id: "736", format: :mobile, signed_in: true, tag: "E04_736_markdown_mobile_auth")
end
