# ROUND 8 / H04 — the MENTION-side `fix_profile` arm, and whether a WIDER key
# set changes a per-REQUEST shape (brief item 3).
#
# H01 opened `Person#fix_profile` to real runs. N7-1 showed a NAMED markup
# `@{Heidi; heidi@x}` never calls `person.name`, so it reached the mentioned
# person's `profile_not_found == True` arm WITHOUT fix_profile. The UNNAMED
# markup `@{handle}` is the other half: Mentionable::MentionsInternal.mention_link
# falls through to `person.name` (mentionable.rb:107-112), which is
# `fix_profile` when the profile is missing (person.rb:247-251).
# Mentionable::REGEX is /@\{(?:([^\}]+?); )?([^\} ]+)\}/ — the id may not contain
# a SPACE, so the URI-hostile handles here use `[` instead.
#
# Also: 1/2/3/4 distinct keys on BOTH trees, recording the whole statement list,
# to test whether anything beyond the ARITY of an existing predicate changes.
require_relative "_common8"
require_relative "_frames8"
adv_setup!("H04_mention_fix_profile")
seed_core!

# profile-less, URI-hostile-domain people (no `mentions` FK, no handle format rule)
CE.insert("people", id: 8, guid: "wraithguid0000008", diaspora_handle: "wraith@ba[d.example",
          serialized_public_key: "K8", owner_id: nil, closed_account: false, fetch_status: 0)
CE.insert("people", id: 9, guid: "spectguid00000009", diaspora_handle: "spectre@ba[d2.example",
          serialized_public_key: "K9", owner_id: nil, closed_account: false, fetch_status: 0)
# extra people WITH profiles, for wide key sets
[[10, "ivy"], [11, "jon"], [12, "kim"]].each do |pid, nm|
  CE.insert("people", id: pid, guid: "#{nm}guid000000#{pid}", diaspora_handle: "#{nm}@other.example",
            serialized_public_key: "K#{pid}", owner_id: nil, closed_account: false, fetch_status: 0)
  CE.insert("profiles", id: 20 + pid, person_id: pid, first_name: nm.capitalize, last_name: "X",
            searchable: true, nsfw: false)
end

def post!(pid, guid, public_flag: true, author: 2, extra: {})
  CE.insert("posts", **{id: pid, author_id: author, guid: guid, type: "StatusMessage",
                        text: "p#{pid}", public: public_flag, comments_count: 0}.merge(extra))
end
def comment!(cid, pid, author, text = "c#{cid}")
  CE.insert("comments", id: cid, commentable_id: pid, commentable_type: "Post",
            author_id: author, guid: "h4cguid#{cid}", text: text,
            created_at: "2020-01-01 00:00:#{format('%02d', cid % 60)}")
end
def mention!(mid, cid, person_id)
  CE.insert("mentions", id: mid, mentions_container_id: cid,
            mentions_container_type: "Comment", person_id: person_id)
end

W = "@{wraith@ba[d.example}"            # UNNAMED -> person.name -> fix_profile
WN = "@{Wraith; wraith@ba[d.example}"   # NAMED   -> display_name, no name call
S = "@{spectre@ba[d2.example}"
ERIN = "@{Erin; erin@other.example}"
ERINU = "@{erin@other.example}"

# 840 — UNNAMED markup, mentioned person 8 has NO profiles row
post!(840, "h04guid840000000001"); comment!(850, 840, 2, "hey #{W} bye"); mention!(860, 850, 8)
# 841 — CONTROL: same fixtures, NAMED markup (N7-1's 200)
post!(841, "h04guid841000000001"); comment!(851, 841, 2, "hey #{WN} bye"); mention!(861, 851, 8)
# 842 — two mentions: person 5 (profile) + person 8 (none), both UNNAMED
post!(842, "h04guid842000000001")
comment!(852, 842, 2, "hey #{ERINU} and #{W} bye"); mention!(862, 852, 5); mention!(863, 852, 8)
# 843 — two mentions, BOTH profile-less, both UNNAMED
post!(843, "h04guid843000000001")
comment!(853, 843, 2, "hey #{W} and #{S} bye"); mention!(864, 853, 8); mention!(865, 853, 9)
# --- key-set width: does anything but the ARITY change? ---
# 844/845/846/847 — 1, 2, 3, 4 DISTINCT comment authors (all with profiles)
post!(844, "h04guid844000000001"); comment!(870, 844, 2)
post!(845, "h04guid845000000001"); comment!(871, 845, 2); comment!(872, 845, 5)
post!(846, "h04guid846000000001"); comment!(873, 846, 2); comment!(874, 846, 5); comment!(875, 846, 10)
post!(847, "h04guid847000000001")
[2, 5, 10, 11].each_with_index { |a, i| comment!(880 + i, 847, a) }
# 848 — ONE comment, 4 DISTINCT mentions, all live with profiles (named markup)
post!(848, "h04guid848000000001")
comment!(890, 848, 2, "a #{ERIN} b @{Ivy; ivy@other.example} c @{Jon; jon@other.example} d @{Kim; kim@other.example}")
[5, 10, 11, 12].each_with_index { |p, i| mention!(870 + i, 890, p) }
# 849 — ONE comment, 4 mentions, 2 dangling (no people row at all)
post!(849, "h04guid849000000001")
comment!(891, 849, 2, "a #{ERIN} b @{Ivy; ivy@other.example} c @{Ghost1; g1@nope.example} d @{Ghost2; g2@nope.example}")
[5, 10, 996, 997].each_with_index { |p, i| mention!(880 + i, 891, p) }

CONCRETE_SCENARIOS = adv_scenario("H04-mention-fix-profile") do
  adv_probe("in_clause_length") { ActiveRecord::Base.connection.in_clause_length.inspect }
  req!(post_id: "840", format: :json,   tag: "H04_840_unnamed_noprofile_json")
  req!(post_id: "840", format: :mobile, tag: "H04_840_unnamed_noprofile_mobile")
  req!(post_id: "841", format: :json,   tag: "H04_841_CONTROL_named_noprofile_json")
  req!(post_id: "841", format: :mobile, tag: "H04_841_CONTROL_named_noprofile_mobile")
  req!(post_id: "842", format: :json,   tag: "H04_842_live_plus_noprofile_json")
  req!(post_id: "842", format: :mobile, tag: "H04_842_live_plus_noprofile_mobile")
  req!(post_id: "843", format: :json,   tag: "H04_843_both_noprofile_json")
  req!(post_id: "843", format: :mobile, tag: "H04_843_both_noprofile_mobile")
  %w[844 845 846 847].each do |p|
    req!(post_id: p, format: :json,   tag: "H04_#{p}_authors_json")
    req!(post_id: p, format: :mobile, tag: "H04_#{p}_authors_mobile")
  end
  req!(post_id: "848", format: :json,   tag: "H04_848_4mentions_json")
  req!(post_id: "848", format: :mobile, tag: "H04_848_4mentions_mobile")
  req!(post_id: "849", format: :json,   tag: "H04_849_4mentions_2dangling_json")
  req!(post_id: "849", format: :mobile, tag: "H04_849_4mentions_2dangling_mobile")
  dump_frames!("H04")
end
