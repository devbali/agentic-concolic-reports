# G05 — ROUND 7, brief item 3 (text, STI, person shapes) plus the projection-level
# re-verification of the standing findings M-1, M-3, M-4, M-5, M-6, M-9/B-8, D5, D6.
require_relative "_common7"
adv_setup!("G05_wider_text_sti")
seed_core!
seed_user!(uid: 21, username: "eve",  language: "xx", person_id: 21,
           person_guid: "eveguid0000000021", handle: "eve@localhost", profile_id: 21)   # M-5
seed_user!(uid: 22, username: "mallory", language: "en")                                 # no person row
seed_user!(uid: 23, username: "trent", language: "en", person_id: 23,
           person_guid: "trentguid00000023", handle: "trent@localhost", profile_id: 23)

CE.insert("pods", id: 1, host: "third.example", ssl: true, status: 0, port: nil)
# person 6 (frank) becomes a pod-bearing remote person
ActiveRecord::Base.connection.execute("UPDATE people SET pod_id = 1 WHERE id = 6")

def post!(pid, guid, public_flag: true, author: 2, type: "StatusMessage", extra: {})
  CE.insert("posts", **{id: pid, author_id: author, guid: guid, type: type,
                        text: "p#{pid}", public: public_flag, comments_count: 0}.merge(extra))
end
def comment!(cid, pid, author, text = "c#{cid}", guid: nil)
  CE.insert("comments", id: cid, commentable_id: pid, commentable_type: "Post",
            author_id: author, guid: (guid || "g5cguid#{cid}"), text: text,
            created_at: "2020-01-01 00:00:#{format('%02d', cid % 60)}")
end
def mention!(mid, cid, person_id)
  CE.insert("mentions", id: mid, mentions_container_id: cid,
            mentions_container_type: "Comment", person_id: person_id)
end

LIVE  = "g05guid910000000001"
DEAD1 = "nosuchguid0000000001"
DEAD2 = "nosuchguid0000000002"

# 910 Reshare STI commentable
post!(910, LIVE, type: "Reshare", extra: {root_guid: "someroot000000001"})
comment!(960, 910, 2, "on a reshare")
# 911 out-of-tree STI type (M-6)
post!(911, "g05guid911000000001", type: "Photo"); comment!(961, 911, 2)
# 912 diaspora:// link to a COMMENT (not a post) -> no exists?
post!(912, "g05guid912000000001")
comment!(962, 912, 2, "see diaspora://alice@localhost/comment/#{LIVE} ok")
# 913 three post links: one live, two dead
post!(913, "g05guid913000000001")
comment!(963, 913, 2, "a diaspora://alice@localhost/post/#{LIVE} b " \
                      "diaspora://bob@remote.example/post/#{DEAD1} c " \
                      "diaspora://bob@remote.example/post/#{DEAD2} d")
# 914 seven post links in one comment
post!(914, "g05guid914000000001")
comment!(964, 914, 2, (1..7).map { |i| "diaspora://alice@localhost/post/deadguid00000000#{i}" }.join(" "))
# 915 markdown / bare urls / camo / tags / rtl
post!(915, "g05guid915000000001")
comment!(965, 915, 2, "http://example.org/x ![img](http://example.org/i.png) " \
                      "<img src=\"http://example.org/j.png\"> #tag #<3 אבג " \
                      "[md](http://example.org/l) `code` **bold**")
# 916 remote author with a pod, and a closed-account author
post!(916, "g05guid916000000001")
comment!(966, 916, 6, "from a pod-bearing remote person")
comment!(967, 916, 3, "from a closed account")
# 917 dangling mention, PLAIN text (M-3 statement half)
post!(917, "g05guid917000000001"); comment!(968, 917, 2, "plain text, dangling mention row")
mention!(990, 968, 995)
# 918 empty / whitespace comment text (D6 family)
post!(918, "g05guid918000000001"); comment!(969, 918, 2, ""); comment!(970, 918, 5, "   ")
# 919 blank guid comment (D5)
post!(919, "g05guid919000000001"); comment!(971, 919, 2, "blank guid row", guid: "")
# 920 blocks / contacts present (R4 positive control)
post!(920, "g05guid920000000001"); comment!(972, 920, 2, "blocked author speaks")
CE.insert("blocks", id: 1, user_id: 23, person_id: 2)
CE.insert("contacts", id: 1, user_id: 23, person_id: 2, sharing: true, receiving: true)
# 921 empty collection, mobile+json (M-4)
post!(921, "g05guid921000000001")

CONCRETE_SCENARIOS = adv_scenario("G05-wider-text-sti") do
  adv_request(post_id: "910", format: :json,   tag: "G05_910_reshare_json")
  adv_request(post_id: "910", format: :mobile, tag: "G05_910_reshare_mobile")
  adv_request(post_id: "912", format: :json,   tag: "G05_912_comment_link_json")
  adv_request(post_id: "912", format: :mobile, tag: "G05_912_comment_link_mobile")
  adv_request(post_id: "913", format: :json,   tag: "G05_913_three_links_json")
  adv_request(post_id: "913", format: :mobile, tag: "G05_913_three_links_mobile")
  adv_request(post_id: "914", format: :json,   tag: "G05_914_seven_links_json")
  adv_request(post_id: "915", format: :json,   tag: "G05_915_markdown_json")
  adv_request(post_id: "915", format: :mobile, tag: "G05_915_markdown_mobile")
  adv_request(post_id: "916", format: :json,   tag: "G05_916_pod_closed_json")
  adv_request(post_id: "916", format: :mobile, tag: "G05_916_pod_closed_mobile")
  adv_request(post_id: "917", format: :json,   tag: "G05_917_dangling_plain_json")
  adv_request(post_id: "917", format: :mobile, tag: "G05_917_dangling_plain_mobile")
  adv_request(post_id: "918", format: :json,   tag: "G05_918_empty_text_json")
  adv_request(post_id: "918", format: :mobile, tag: "G05_918_empty_text_mobile")
  adv_request(post_id: "919", format: :json,   tag: "G05_919_blank_guid_json")
  adv_request(post_id: "920", format: :json, signed_in: true, uid: 23, tag: "G05_920_blocked_auth_json")
  adv_request(post_id: "921", format: :json,   tag: "G05_921_empty_json")
  adv_request(post_id: "921", format: :mobile, tag: "G05_921_empty_mobile")
  # M-5: an invalid locale on the principal — one statement, then I18n::InvalidLocale
  adv_request(post_id: "913", format: :json, signed_in: true, uid: 21, tag: "G05_locale_xx_auth")
  # user with no `people` row
  adv_request(post_id: "913", format: :json, signed_in: true, uid: 22, tag: "G05_no_person_auth")
  # M-6 last: out-of-tree STI type truncates the request
  adv_request(post_id: "911", format: :json,   tag: "G05_911_sti_photo_json")
  adv_request(post_id: "911", format: :mobile, tag: "G05_911_sti_photo_mobile")
end
