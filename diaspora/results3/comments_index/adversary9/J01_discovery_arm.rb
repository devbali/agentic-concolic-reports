# ROUND 9 / J01 — THE DISCOVERY-SUCCESS ARM'S STATEMENT SET.
#
# Claim under test (the cycle-11 repair of M-15). The corpus explores
# `…_discovery_failed == True  taken=False` — the arm on which
# `Discovery#fetch_and_save` RETURNS — in 7 272 of 26 931 dumps, and on that arm
# it asserts EXACTLY TWO statements: `ActiveRecord::Base.reload`
# (`SELECT "people".* … "id" = ? LIMIT 1`) and the profile `find_target`
# (`SELECT "profiles".* … "person_id" = ? LIMIT 1`) — 7 972 calls of each, and
# 0 DML and 0 `pods` notes anywhere in the corpus. The wall note says the
# persistence callback is "UNMODELLED, not absent".
#
# But `fetch_and_save` (gem discovery.rb:19-31) is
#     validate_diaspora_id
#     DiasporaFederation.callbacks.trigger(:save_person_after_webfinger, person)
#     person
# so it cannot RETURN unless that callback has run to completion, and the app's
# callback (config/initializers/diaspora_federation.rb:59-77) reads and WRITES.
# The two statements the corpus asserts on that arm are therefore issued
# strictly AFTER statements it does not assert.
#
# Measures: (a) `fix_profile`/`fetch_and_save` entered from inside the action
# frame (entrypoint evidence), (b) exactly which statements the persistence
# callback issues — a SCENARIO-BODY PROBE, kept separate from the endpoint's own
# statements. No mocks, no stubs: the probe calls the app's OWN registered
# callback with a real federation entity. No network is involved in (b).
require_relative "_common9"
require_relative "_frames9"
adv_setup!("J01_discovery_arm")
seed_core!

# Endpoint fixtures: URI-hostile domains only — a parseable domain reaches
# libcurl and aborts the JVM (R8 / cycle-11 probe_parseable).
CE.insert("people", id: 7, guid: "graceguid00000007", diaspora_handle: "grace@other.example",
          serialized_public_key: "K7", owner_id: nil, closed_account: false, fetch_status: 0)
CE.insert("profiles", id: 17, person_id: 7, first_name: "Grace", last_name: "G", searchable: true, nsfw: false)
CE.insert("people", id: 8, guid: "wraithguid0000008", diaspora_handle: "wraith@ba[d.example",
          serialized_public_key: "K8", owner_id: nil, closed_account: false, fetch_status: 0)

# Probe-only fixtures: a REAL pod row and a pod-owned person with NO profiles
# row — the shape `save_person_after_webfinger` meets when the person exists.
CE.insert("pods", id: 3, host: "ok.example", port: nil, ssl: false, status: 0,
          response_time: -1, blocked: false, scheduled_check: false,
          checked_at: "1970-01-01 00:00:00")
CE.insert("people", id: 9, guid: "ghostguid00000009", diaspora_handle: "ghost@ok.example",
          serialized_public_key: "K9", owner_id: nil, pod_id: 3, closed_account: false, fetch_status: 0)

def post!(pid, guid, public_flag: true, author: 2)
  CE.insert("posts", id: pid, author_id: author, guid: guid, type: "StatusMessage",
            text: "p#{pid}", public: public_flag, comments_count: 0)
end
def comment!(cid, pid, author, text = "c#{cid}")
  CE.insert("comments", id: cid, commentable_id: pid, commentable_type: "Post",
            author_id: author, guid: "j1cguid#{cid}", text: text,
            created_at: "2020-01-01 00:00:#{format('%02d', cid % 60)}")
end

post!(900, "j01guid900000000001"); comment!(910, 900, 8)
post!(901, "j01guid901000000001"); comment!(911, 901, 7); comment!(912, 901, 8)

CONCRETE_SCENARIOS = adv_scenario("J01-discovery-arm") do
  # --- ENDPOINT requests (these, and only these, are endpoint statements) ---
  req!(post_id: "900", format: :json,   tag: "J01_900_noprofile_json")
  req!(post_id: "900", format: :mobile, tag: "J01_900_noprofile_mobile")
  req!(post_id: "901", format: :json,   tag: "J01_901_k1ok_k2missing_json")
  req!(post_id: "901", format: :mobile, tag: "J01_901_k1ok_k2missing_mobile")

  # --- SCENARIO-BODY PROBES (NOT endpoint statements) ----------------------
  $adv_tag = "PROBE_P2_find_or_fetch_existing"
  adv_probe("P2 Person.find_or_fetch_by_identifier on an EXISTING handle") do
    Person.find_or_fetch_by_identifier("grace@other.example").try(:id)
  end
  $adv_tag = "PROBE_P2b_find_or_fetch_unknown"
  adv_probe("P2b Person.find_or_fetch_by_identifier on a URI-hostile UNKNOWN handle") do
    Person.find_or_fetch_by_identifier("nobody@ba[d.example").try(:id)
  end

  key = nil
  adv_probe("P3a real RSA key for the entity") { key = OpenSSL::PKey::RSA.new(1024) }
  mk = lambda do |handle, guid, url|
    prof = DiasporaFederation::Entities::Profile.new(
      author: handle, first_name: "Fetched", last_name: "Person",
      image_url: "#{url}f.png", image_url_medium: "#{url}m.png",
      image_url_small: "#{url}s.png", searchable: true
    )
    DiasporaFederation::Entities::Person.new(
      guid: guid, author: handle, url: url,
      exported_key: key.public_key.export, profile: prof
    )
  end
  # P3b — the person EXISTS with no profiles row: the exact state `fix_profile`
  # is called in. This is what runs before every `reload` the corpus asserts.
  $adv_tag = "PROBE_P3b_callback_existing_person"
  adv_probe("P3b save_person_after_webfinger, EXISTING person id 9") do
    DiasporaFederation.callbacks.trigger(
      :save_person_after_webfinger, mk.call("ghost@ok.example", "ghostguid00000009", "http://ok.example/")
    )
  end
  # P3c — the person does NOT exist: INSERT path + Pod.find_or_create_by.
  $adv_tag = "PROBE_P3c_callback_new_person"
  adv_probe("P3c save_person_after_webfinger, NEW person") do
    DiasporaFederation.callbacks.trigger(
      :save_person_after_webfinger, mk.call("newbie@fresh.example", "newbieguid000000009", "http://fresh.example/")
    )
  end
  $adv_tag = nil
  dump_frames!("J01")
end
