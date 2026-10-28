# people_stream CONCRETE manifest — ANON, json format, DIASPORA-ID arm
# (find_person -> diaspora_id?(username) TRUE -> Person.where(diaspora_handle:).first).
# The other half of find_person; without it that read never appears in ground truth.
require File.expand_path("../_concrete_fixture.rb", __FILE__)
ps_fixture!(File.expand_path("../concrete_anon_handle.sqlite3", __FILE__))
require File.expand_path("../_concrete_targets.rb", __FILE__)

CONCRETE_SCENARIOS = [
  { name: "people-stream-anon-json-handle",
    targets: PS_TARGETS,
    coverage_filter: %r{apps/diaspora/(app|lib)/},
    body: lambda do
      ctrl = ps_dispatch(signed_in: false, format: :json,
                         person_id: nil, username: "bob@localhost")
      body = ctrl.response.body.to_s
      raise "handle arm: #{ctrl.response.status} #{body[0, 200]}" unless body.include?("a public post")
    end },
]
