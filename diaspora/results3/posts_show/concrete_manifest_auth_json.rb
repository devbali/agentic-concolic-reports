# posts_show CONCRETE manifest — SIGNED-IN, format.json, the LIMITED post.
# The ONLY arm where current_user reaches the SQL:
# `EvilQuery::VisibleShareableById#querent_has_visibility` joins
# share_visibilities on @querent.id, and it MUST return the limited post.
require File.expand_path("../_concrete_fixture.rb", __FILE__)
psh_fixture!(File.expand_path("../concrete_auth_json.sqlite3", __FILE__))
require File.expand_path("../_concrete_targets.rb", __FILE__)

PSH_PRINCIPAL = User.find(9)

CONCRETE_SCENARIOS = [
  { name: "posts-show-auth-json",
    targets: PSH_TARGETS,
    coverage_filter: %r{apps/diaspora/(app|lib)/},
    body: lambda do
      ctrl = psh_dispatch(signed_in: true, format: :json, id: "postguid1010000001")
      body = ctrl.response.body.to_s
      raise "auth json: #{ctrl.response.status} #{body[0, 200]}" unless
        ctrl.response.status.to_i == 200
      # the whole point of this scenario: the signed-in arm sees a row the
      # anonymous arm provably cannot.
      raise "signed-in arm did not see the LIMITED post" unless body.include?("a limited post")
    end },
]
