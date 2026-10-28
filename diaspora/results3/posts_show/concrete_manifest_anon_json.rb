# posts_show CONCRETE manifest — ANONYMOUS, format.json (presenter.with_interactions).
require File.expand_path("../_concrete_fixture.rb", __FILE__)
psh_fixture!(File.expand_path("../concrete_anon_json.sqlite3", __FILE__))
require File.expand_path("../_concrete_targets.rb", __FILE__)

PSH_PRINCIPAL = nil

CONCRETE_SCENARIOS = [
  { name: "posts-show-anon-json",
    targets: PSH_TARGETS,
    coverage_filter: %r{apps/diaspora/(app|lib)/},
    body: lambda do
      ctrl = psh_dispatch(signed_in: false, format: :json, id: "postguid1000000001")
      body = ctrl.response.body.to_s
      raise "anon json: #{ctrl.response.status} #{body[0, 200]}" unless
        ctrl.response.status.to_i == 200
      raise "anon json did not serialise the public post" unless body.include?("a public post")
      raise "anon json leaked the LIMITED post" if body.include?("a limited post")
    end },
]
