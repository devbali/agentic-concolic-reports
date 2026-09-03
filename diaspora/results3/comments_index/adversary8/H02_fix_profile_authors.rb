# ROUND 8 / H02 — `Person#fix_profile` IS reachable by a real run (H01), so the
# AUTHOR-side profile-not-found family is now measurable instead of code-read.
#
# H01 established: DiasporaFederation::Discovery::Discovery#fetch_and_save with a
# handle whose DOMAIN is not a legal URI host raises DiscoveryError from pure
# Ruby (Faraday's URI.parse), no FFI, no JVM abort. A well-formed handle still
# aborts. So every profile-less person here carries a URI-hostile handle.
#
# What this measures:
#  * the statement multiset and terminal of a comment whose AUTHOR has no profile
#    (json: `name` is reached through as_api_response :backbone, person.rb:12-24;
#     mobile: person_image_link returns "" and person_link -> person.name);
#  * the ORDER effect on json: CommentPresenter#as_json evaluates `text` before
#    `author` before `mentioned_people`, so the raise cuts the `mentions` read;
#  * two comments, ONE author with a profile and ONE without, both orders —
#    the state ADVERSARY_WINS row 113 / N7-6 records as "unreachable by a real
#    run, code-reading only".
require_relative "_common8"
require_relative "_frames8"
adv_setup!("H02_fix_profile_authors")
seed_core!

# profile-less people with URI-hostile domains (people.diaspora_handle has no
# format constraint in db/schema.rb and no validation on a raw insert)
CE.insert("people", id: 7, guid: "ghostguid00000007", diaspora_handle: "ghost@ex ample.com",
          serialized_public_key: "K7", owner_id: nil, closed_account: false, fetch_status: 0)
CE.insert("people", id: 8, guid: "wraithguid0000008", diaspora_handle: "wraith@ba[d.example",
          serialized_public_key: "K8", owner_id: nil, closed_account: false, fetch_status: 0)

def post!(pid, guid, public_flag: true, author: 2, extra: {})
  CE.insert("posts", **{id: pid, author_id: author, guid: guid, type: "StatusMessage",
                        text: "p#{pid}", public: public_flag, comments_count: 0}.merge(extra))
end
def comment!(cid, pid, author, text = "c#{cid}")
  CE.insert("comments", id: cid, commentable_id: pid, commentable_type: "Post",
            author_id: author, guid: "h2cguid#{cid}", text: text,
            created_at: "2020-01-01 00:00:#{format('%02d', cid % 60)}")
end
def mention!(mid, cid, person_id)
  CE.insert("mentions", id: mid, mentions_container_id: cid,
            mentions_container_type: "Comment", person_id: person_id)
end

ERIN = "@{Erin; erin@other.example}"

# 800 — ONE comment, author 7 has NO profiles row
post!(800, "h02guid800000000001"); comment!(810, 800, 7)
# 801 — comment 1 author 2 (profile), comment 2 author 7 (no profile)
post!(801, "h02guid801000000001"); comment!(811, 801, 2); comment!(812, 801, 7)
# 802 — the other order: comment 1 author 7 (no profile), comment 2 author 2
post!(802, "h02guid802000000001"); comment!(813, 802, 7); comment!(814, 802, 2)
# 803 — author 7, text carrying a mention AND a diaspora post link: does the
#       json render issue Post.exists? and the `mentions` SELECT before the raise?
post!(803, "h02guid803000000001")
comment!(815, 803, 7, "hi #{ERIN} see diaspora://alice@localhost/post/h02guid800000000001 end")
mention!(820, 815, 5)
# 804 — CONTROL: identical to 803 but the author HAS a profile
post!(804, "h02guid804000000001")
comment!(816, 804, 2, "hi #{ERIN} see diaspora://alice@localhost/post/h02guid800000000001 end")
mention!(821, 816, 5)
# 805 — three comments, authors 2 (profile), 7 (none), 8 (none)
post!(805, "h02guid805000000001")
comment!(817, 805, 2); comment!(818, 805, 7); comment!(819, 805, 8)
# 806 — author 7, private post shared with user 9 (signed-in arm)
post!(806, "h02guid806000000001", public_flag: false)
CE.insert("share_visibilities", id: 31, shareable_id: 806, shareable_type: "Post", user_id: 9, hidden: false)
comment!(822, 806, 7)

CONCRETE_SCENARIOS = adv_scenario("H02-fix-profile-authors") do
  req!(post_id: "800", format: :json,   tag: "H02_800_noprofile_author_json")
  req!(post_id: "800", format: :mobile, tag: "H02_800_noprofile_author_mobile")
  req!(post_id: "801", format: :json,   tag: "H02_801_profile_then_none_json")
  req!(post_id: "801", format: :mobile, tag: "H02_801_profile_then_none_mobile")
  req!(post_id: "802", format: :json,   tag: "H02_802_none_then_profile_json")
  req!(post_id: "802", format: :mobile, tag: "H02_802_none_then_profile_mobile")
  req!(post_id: "803", format: :json,   tag: "H02_803_noprofile_with_link_mention_json")
  req!(post_id: "803", format: :mobile, tag: "H02_803_noprofile_with_link_mention_mobile")
  req!(post_id: "804", format: :json,   tag: "H02_804_CONTROL_profile_json")
  req!(post_id: "804", format: :mobile, tag: "H02_804_CONTROL_profile_mobile")
  req!(post_id: "805", format: :json,   tag: "H02_805_three_authors_two_noprofile_json")
  req!(post_id: "805", format: :mobile, tag: "H02_805_three_authors_two_noprofile_mobile")
  req!(post_id: "806", format: :json,   signed_in: true, uid: 9, tag: "H02_806_noprofile_author_auth_json")
  req!(post_id: "806", format: :mobile, signed_in: true, uid: 9, tag: "H02_806_noprofile_author_auth_mobile")
  dump_frames!("H02")
end
