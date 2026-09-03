# ROUND 9 / J04 — ENTRYPOINT EVIDENCE for W9-1 (DISCIPLINE §15 addendum).
# A win must show the novel behaviour is issued from INSIDE the declared
# entrypoint: the post-auth action frame, principal concretely instantiated
# within its symbolic declaration. W9-1 is about the statement set of
# `Discovery#fetch_and_save`'s SUCCESS arm, so what must be shown at the
# entrypoint is that `Person#fix_profile` -> `fetch_and_save` is CALLED from
# the action (the arm taken is an environment bound, not a scope question).
# This manifest captures the FULL backtrace of the raise, anon and signed-in,
# json and mobile.  No probes, no network beyond the URI-hostile handle that
# fails inside Ruby.
require_relative "_common9"
require_relative "_frames9"
adv_setup!("J04_entrypoint_backtrace")
seed_core!

CE.insert("people", id: 8, guid: "wraithguid0000008", diaspora_handle: "wraith@ba[d.example",
          serialized_public_key: "K8", owner_id: nil, closed_account: false, fetch_status: 0)
CE.insert("people", id: 7, guid: "graceguid00000007", diaspora_handle: "grace@other.example",
          serialized_public_key: "K7", owner_id: nil, closed_account: false, fetch_status: 0)
CE.insert("profiles", id: 17, person_id: 7, first_name: "Grace", last_name: "G", searchable: true, nsfw: false)

def post!(pid, guid, public_flag: true, author: 2)
  CE.insert("posts", id: pid, author_id: author, guid: guid, type: "StatusMessage",
            text: "p#{pid}", public: public_flag, comments_count: 0)
end
def comment!(cid, pid, author, text = "c#{cid}")
  CE.insert("comments", id: cid, commentable_id: pid, commentable_type: "Post",
            author_id: author, guid: "j4cguid#{cid}", text: text,
            created_at: "2020-01-01 00:00:#{format('%02d', cid % 60)}")
end
def mention!(mid, cid, person_id)
  CE.insert("mentions", id: mid, mentions_container_id: cid,
            mentions_container_type: "Comment", person_id: person_id)
end

post!(960, "j04guid960000000001"); comment!(980, 960, 8)                   # author tree
post!(961, "j04guid961000000001")                                          # mention tree
comment!(981, 961, 2, "hi @{wraith@ba[d.example}"); mention!(990, 981, 8)


# --- 2 comments, 1 mention each: the multiplicity baseline for the executor probe
post!(962, "j04guid962000000001")
comment!(982, 962, 2, "a @{erin@other.example}"); mention!(991, 982, 5)
comment!(983, 962, 5, "b @{erin@other.example}"); mention!(992, 983, 5)

BT = []
def bt_request(**kw)
  ctrl, tc = make_harness(CommentsController)
  kw[:signed_in] ? install_real_warden(tc, kw.fetch(:uid, 9)) : install_anon_warden(tc)
  $adv_tag = kw[:tag]
  begin
    tc.process(:index, method: :get, params: {post_id: kw[:post_id]}, format: kw[:format])
    warn "[adv9] #{kw[:tag]} -> #{ctrl.response.status} (#{ctrl.response.body.to_s.bytesize} bytes)"
  rescue StandardError => e
    root = e
    root = root.cause while root.respond_to?(:cause) && root.cause
    BT << {"tag" => kw[:tag], "error" => e.class.to_s, "root" => root.class.to_s,
           "message" => e.message.to_s[0, 200],
           "backtrace" => (root.backtrace || e.backtrace || [])
                            .map { |f| f.sub(%r{\A.*/apps/diaspora/}, "app:").sub(%r{\A.*/gems/}, "gem:") }[0, 40]}
    warn "[adv9] #{kw[:tag]} -> #{e.class}: #{e.message.to_s[0, 90]}"
  end
  $adv_tag = nil
end

CONCRETE_SCENARIOS = adv_scenario("J04-entrypoint-backtrace") do
  bt_request(post_id: "960", format: :json,   tag: "J04_960_author_anon_json")
  bt_request(post_id: "960", format: :mobile, tag: "J04_960_author_anon_mobile")
  bt_request(post_id: "960", format: :json,   signed_in: true, tag: "J04_960_author_auth_json")
  bt_request(post_id: "961", format: :json,   tag: "J04_961_mention_anon_json")
  bt_request(post_id: "961", format: :mobile, tag: "J04_961_mention_anon_mobile")
  # SCENARIO-BODY PROBE (J03 Q1 follow-up): the middleware stack carries
  # ActionDispatch::Executor but no explicit ActiveRecord::QueryCache. Rails
  # installs query caching as an EXECUTOR HOOK, and the rig dispatches the
  # action directly, outside the executor. If wrapping the SAME request in the
  # app's own executor halves the repeated `mentions` reads, then every rig on
  # this project counts repeated identical statements that a real Rack request
  # serves from cache — the calibration the M-16b memo repair was measured
  # against. Uses only the app's own executor; nothing is mocked.
  count_mentions = lambda do |tag|
    before = ADV_FRAMES.size
    $adv_tag = tag
    ctrl, tc = make_harness(CommentsController)
    install_anon_warden(tc)
    tc.process(:index, method: :get, params: {post_id: "962"}, format: :json)
    $adv_tag = nil
    new = ADV_FRAMES[before..-1] || []
    m = new.count { |e| e["sql"] =~ /FROM "mentions"/ }
    c = new.count { |e| e["cached"] }
    warn "[adv9] #{tag} -> #{ctrl.response.status}, #{new.size} stmts, mentions=#{m}, cached=#{c}"
  end
  count_mentions.call("J04_962_plain_dispatch")
  adv_probe("Q3 same request inside Rails.application.executor.wrap") do
    Rails.application.executor.wrap { count_mentions.call("J04_962_executor_wrapped") }
  end
  adv_probe("Q4 executor hook classes") do
    Rails.application.executor.instance_variable_get(:@run_hooks).to_a.map { |h| h.class.to_s }
  end
  File.write(File.join(ADV_DIR, "runs", "_backtraces_J04.json"), JSON.pretty_generate(BT))
  warn "[adv9] backtraces written: #{BT.size}"
  dump_frames!("J04")
end
