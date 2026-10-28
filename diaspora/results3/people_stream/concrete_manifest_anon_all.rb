# people_stream CONCRETE manifest — ANON, default (html) format.
# One scenario per manifest (JVM crash isolation: the mention-parse path can
# abort natively on this JRuby).
require File.expand_path("../_concrete_fixture.rb", __FILE__)
ps_fixture!(File.expand_path("../concrete_anon_all.sqlite3", __FILE__))
require File.expand_path("../_concrete_targets.rb", __FILE__)

CONCRETE_SCENARIOS = [
  { name: "people-stream-anon-all",
    targets: PS_TARGETS,
    coverage_filter: %r{apps/diaspora/(app|lib)/},
    body: lambda do
      ctrl = ps_dispatch(signed_in: false, format: nil,
                         person_id: "bobguid00000000002", username: nil)
      loc = ctrl.response.location.to_s
      raise "no redirect: status=#{ctrl.response.status} loc=#{loc.inspect}" unless loc.include?("/people/")
    end },
]
