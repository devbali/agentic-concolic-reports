# M-17 resolution (b): the DECLARED GAP's evidence, measured by this batch.
# Runs the app's OWN `:save_person_after_webfinger` callback with NO network,
# in both branches, and records every statement it issues. These are
# SCENARIO-BODY statements, deliberately NOT merged into concrete_run.json:
# they are what the endpoint WOULD issue on the discovery-success arm, which no
# real run in this environment can reach.
require File.expand_path("../../../../../../ruby_examples/dse-apps/apps/diaspora/config/environment", __FILE__)
require "/home/dev/project/reports/diaspora/tools/concrete_checker/concrete_env.rb"
CE = CompletionChecker::ConcreteEnv
CE.setup!(db: File.expand_path("../gap.sqlite3", __FILE__))

CE.insert("people", id: 41, guid: "a1b2c3d4e5f60718", diaspora_handle: "known@remote.example",
          serialized_public_key: "K41", owner_id: nil, closed_account: 0, fetch_status: 0)

CAP = []
ActiveSupport::Notifications.subscribe("sql.active_record") do |*a|
  p = a.last
  next if p[:cached]
  CAP << p[:sql].to_s.gsub(/\s+/, " ").strip
end

def entity(handle, guid)
  DiasporaFederation::Entities::Person.new(
    guid: guid, diaspora_id: handle, url: "https://remote.example/",
    exported_key: "-----BEGIN PUBLIC KEY-----\nAAAA\n-----END PUBLIC KEY-----\n",
    profile: DiasporaFederation::Entities::Profile.new(
      diaspora_id: handle, first_name: "Gap", last_name: "Person",
      image_url: "https://remote.example/i.png", image_url_medium: "https://remote.example/m.png",
      image_url_small: "https://remote.example/s.png", searchable: true, tag_string: ""))
end

out = {}
[["existing_person_no_profile", "known@remote.example", "a1b2c3d4e5f60718"],
 ["new_person",                  "fresh@newpod.example", "b2c3d4e5f6071829"]].each do |name, handle, guid|
  CAP.clear
  begin
    DiasporaFederation.callbacks.trigger(:save_person_after_webfinger, entity(handle, guid))
    st = CAP.dup
    out[name] = {"ok" => true, "n" => st.length, "statements" => st}
    puts "[gap] #{name}: #{st.length} statements"
  rescue Exception => e
    out[name] = {"ok" => false, "error" => "#{e.class}: #{e.message[0, 200]}", "n" => CAP.length, "statements" => CAP.dup}
    puts "[gap] #{name}: #{e.class}: #{e.message.to_s[0, 140]} (after #{CAP.length} statements)"
  end
end
File.write(File.expand_path("../_discovery_gap_evidence.json", __FILE__), JSON.pretty_generate(out))
puts "[gap] wrote _discovery_gap_evidence.json"
