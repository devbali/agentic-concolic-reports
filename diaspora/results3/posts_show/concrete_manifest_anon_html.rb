# posts_show CONCRETE manifest — ANONYMOUS, format.html, the PUBLIC post.
# One scenario per file (JVM crash isolation, people_stream §8.2): a native
# abort then names its own scenario instead of taking the other four with it.
require File.expand_path("../_concrete_fixture.rb", __FILE__)
psh_fixture!(File.expand_path("../concrete_anon_html.sqlite3", __FILE__))
require File.expand_path("../_concrete_targets.rb", __FILE__)

PSH_PRINCIPAL = nil

CONCRETE_SCENARIOS = [
  { name: "posts-show-anon-html",
    targets: PSH_TARGETS,
    coverage_filter: %r{apps/diaspora/(app|lib)/},
    body: lambda do
      ctrl = psh_dispatch(signed_in: false, format: :html, id: "postguid1000000001")
      body = ctrl.response.body.to_s
      raise "anon html: #{ctrl.response.status} #{body[0, 200]}" unless
        ctrl.response.status.to_i == 200
      # the anonymous arm MUST have taken PostService#find_public!, i.e. read
      # the public post — a scenario that silently degraded to an auth
      # redirect would otherwise report green while measuring nothing.
      raise "anon html did not render the public post" unless body.include?("a public post")
      raise "anon html leaked the LIMITED post" if body.include?("a limited post")
    end },
]
