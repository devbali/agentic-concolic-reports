# ROUND 9 / J03 — THE SQL-KEYED MEMO, PER-REQUEST MULTIPLICITY, AND THE
# STATEMENT-SHAPE SWEEP.
#
# Attack (2): `rows_mock` now memoizes a materialized relation by its own SQL
# text for the life of a run, so `mentioned_people`'s two reads per comment
# return ONE list. Statements are still emitted twice. Two things must hold for
# that merge to be sound:
#   (a) the two reads really do get the same rows — i.e. nothing between them
#       writes, reloads, resets an association or re-evaluates the scope;
#   (b) no two DISTINCT relations in one run ever render the same SQL text.
# This manifest measures the real per-request multiplicity of every shape, on
# both formats, at 0/1/2 comments and 0/1/2 mentions, so the corpus maxima
#   anon_json  : mentions 4, people IN 5, profiles IN 5, people = 5, profiles = 5
#   anon_mobile: mentions 2, people IN 3, profiles IN 3, people = 3, profiles = 3
# can be compared with ground truth per shape rather than by presence.
#
# Also sweeps for statement shapes the corpus has no note for: a blank comment
# text (Processor's `return '' if message.blank?`, ledger row 71), a
# closed-account author with a blank-name profile, a mention person that IS the
# comment author, the guid arm of `post_key`, an empty comment list, and the
# anon `Diaspora::NonPublic` -> `authenticate_user!` rescue.
require_relative "_common9"
require_relative "_frames9"
adv_setup!("J03_memo_and_shapes")
seed_core!

def post!(pid, guid, public_flag: true, author: 2)
  CE.insert("posts", id: pid, author_id: author, guid: guid, type: "StatusMessage",
            text: "p#{pid}", public: public_flag, comments_count: 0)
end
def comment!(cid, pid, author, text = "c#{cid}")
  CE.insert("comments", id: cid, commentable_id: pid, commentable_type: "Post",
            author_id: author, guid: "j3cguid#{cid}", text: text,
            created_at: "2020-01-01 00:00:#{format('%02d', cid % 60)}")
end
def mention!(mid, cid, person_id)
  CE.insert("mentions", id: mid, mentions_container_id: cid,
            mentions_container_type: "Comment", person_id: person_id)
end
E = "@{erin@other.example}"

# 940 — 1 comment, 0 mentions
post!(940, "j03guid940000000001"); comment!(960, 940, 2)
# 941 — 1 comment, 1 mention
post!(941, "j03guid941000000001"); comment!(961, 941, 2, "hi #{E}"); mention!(970, 961, 5)
# 942 — 2 comments, 2 authors, 1 mention each
post!(942, "j03guid942000000001")
comment!(962, 942, 2, "a #{E}"); mention!(971, 962, 5)
comment!(963, 942, 5, "b #{E}"); mention!(972, 963, 5)
# 943 — 2 comments, SAME author, 1 mention each (the one-key state)
post!(943, "j03guid943000000001")
comment!(964, 943, 2, "a #{E}"); mention!(973, 964, 5)
comment!(965, 943, 2, "b #{E}"); mention!(974, 965, 5)
# 944 — EMPTY comment list
post!(944, "j03guid944000000001")
# 945 — BLANK comment text (schema allows '', the model's presence validation
#       only guards creation)
post!(945, "j03guid945000000001"); comment!(966, 945, 2, "")
# 946 — closed-account author with a BLANK-NAME profile (person 3)
post!(946, "j03guid946000000001"); comment!(967, 946, 3)
# 947 — the mentioned person IS the comment author
post!(947, "j03guid947000000001"); comment!(968, 947, 5, "self #{E}"); mention!(975, 968, 5)
# 948 — NON-PUBLIC post, anon: Diaspora::NonPublic -> authenticate_user!
post!(948, "j03guid948000000001", public_flag: false)
comment!(969, 948, 2)

CONCRETE_SCENARIOS = adv_scenario("J03-memo-and-shapes") do
  CompletionChecker.new_request! if defined?(CompletionChecker) && CompletionChecker.respond_to?(:new_request!)
  req!(post_id: "940", format: :json,   tag: "J03_940_1c_0m_json")
  req!(post_id: "940", format: :mobile, tag: "J03_940_1c_0m_mobile")
  req!(post_id: "941", format: :json,   tag: "J03_941_1c_1m_json")
  req!(post_id: "941", format: :mobile, tag: "J03_941_1c_1m_mobile")
  req!(post_id: "942", format: :json,   tag: "J03_942_2c_2a_json")
  req!(post_id: "942", format: :mobile, tag: "J03_942_2c_2a_mobile")
  req!(post_id: "943", format: :json,   tag: "J03_943_2c_1a_json")
  req!(post_id: "943", format: :mobile, tag: "J03_943_2c_1a_mobile")
  req!(post_id: "944", format: :json,   tag: "J03_944_empty_json")
  req!(post_id: "944", format: :mobile, tag: "J03_944_empty_mobile")
  req!(post_id: "945", format: :json,   tag: "J03_945_blank_text_json")
  req!(post_id: "945", format: :mobile, tag: "J03_945_blank_text_mobile")
  req!(post_id: "946", format: :json,   tag: "J03_946_closed_blankname_json")
  req!(post_id: "946", format: :mobile, tag: "J03_946_closed_blankname_mobile")
  req!(post_id: "947", format: :json,   tag: "J03_947_mention_is_author_json")
  req!(post_id: "947", format: :mobile, tag: "J03_947_mention_is_author_mobile")
  req!(post_id: "948", format: :json,   tag: "J03_948_nonpublic_anon_json")
  req!(post_id: "j03guid941000000001", format: :json, tag: "J03_941_guid_arm_json")

  # SCENARIO-BODY PROBE: does the deployed middleware stack put an
  # ActiveRecord query cache above the action? If it does, a real Rack request
  # serves the SECOND identical SELECT from cache and the rig — which dispatches
  # the action directly — over-counts repeated statements.
  $adv_tag = "PROBE_Q1_middleware"
  adv_probe("Q1 middleware stack") do
    Rails.application.middleware.map { |m| m.name.to_s }.grep(/QueryCache|Executor|Cache/)
  end
  $adv_tag = "PROBE_Q2_query_cache_flag"
  adv_probe("Q2 query_cache_enabled during the scenario body") do
    ActiveRecord::Base.connection.query_cache_enabled
  end
  $adv_tag = nil
  dump_frames!("J03")
end
