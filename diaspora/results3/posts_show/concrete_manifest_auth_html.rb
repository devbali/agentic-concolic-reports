# posts_show CONCRETE manifest — SIGNED-IN, format.html. The html arm is the
# only one that runs `gon.post = presenter.with_initial_interactions`, so its
# read set is a superset of the json arm's.
require File.expand_path("../_concrete_fixture.rb", __FILE__)
psh_fixture!(File.expand_path("../concrete_auth_html.sqlite3", __FILE__))
require File.expand_path("../_concrete_targets.rb", __FILE__)

PSH_PRINCIPAL = User.find(9)

CONCRETE_SCENARIOS = [
  { name: "posts-show-auth-html",
    targets: PSH_TARGETS,
    coverage_filter: %r{apps/diaspora/(app|lib)/},
    body: lambda do
      ctrl = psh_dispatch(signed_in: true, format: :html, id: "postguid1000000001")
      body = ctrl.response.body.to_s
      raise "auth html: #{ctrl.response.status} #{body[0, 200]}" unless
        ctrl.response.status.to_i == 200
      raise "auth html did not render the public post" unless body.include?("a public post")
    end },
]
