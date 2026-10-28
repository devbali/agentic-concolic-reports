# people_stream CONCRETE manifest — ANON, json format, GUID lookup arm
# (find_person -> find_from_guid_or_username -> Person.find_by(guid:)).
require File.expand_path("../_concrete_fixture.rb", __FILE__)
ps_fixture!(File.expand_path("../concrete_anon_json.sqlite3", __FILE__))
require File.expand_path("../_concrete_targets.rb", __FILE__)

CONCRETE_SCENARIOS = [
  { name: "people-stream-anon-json",
    targets: PS_TARGETS,
    coverage_filter: %r{apps/diaspora/(app|lib)/},
    body: lambda do
      ctrl = ps_dispatch(signed_in: false, format: :json,
                         person_id: "bobguid00000000002", username: nil)
      body = ctrl.response.body.to_s
      raise "anon json body: #{ctrl.response.status} #{body[0, 200]}" unless body.include?("a public post")
      raise "anon arm leaked the LIMITED post" if body.include?("a limited post")
    end },
]
