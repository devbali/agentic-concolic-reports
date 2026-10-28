# posts_show CONCRETE manifest — ANONYMOUS, format.html, the LIMITED post.
# This is the action's own `rescue_from Diaspora::NonPublic -> authenticate_user!`
# escape back INTO authentication, which POLICY_HEADER.txt names as part of
# THIS action rather than of the auth boundary. Without this scenario the
# non-public arm of `find_public!` is never exercised concretely.
require File.expand_path("../_concrete_fixture.rb", __FILE__)
psh_fixture!(File.expand_path("../concrete_anon_nonpublic.sqlite3", __FILE__))
require File.expand_path("../_concrete_targets.rb", __FILE__)

PSH_PRINCIPAL = nil

CONCRETE_SCENARIOS = [
  { name: "posts-show-anon-nonpublic",
    targets: PSH_TARGETS,
    coverage_filter: %r{apps/diaspora/(app|lib)/},
    body: lambda do
      ctrl = psh_dispatch(signed_in: false, format: :html, id: "postguid1010000001")
      body = ctrl.response.body.to_s
      raise "anon non-public LEAKED the limited post" if body.include?("a limited post")
      # `Diaspora::NonPublic` is rescued into `authenticate_user!`. With a real
      # Warden that THROWS `:warden` (which the middleware turns into the
      # redirect/401); `psh_dispatch` stands in for that middleware and records
      # the throw. Either the throw happened, or the response is a non-200 —
      # a plain 200 means the escape did not run at all.
      raise "anon non-public returned 200 and did not demand authentication — " \
            "the NonPublic escape did not run" if
        ctrl.response.status.to_i == 200 && ctrl.psh_warden_thrown.nil?
    end },
]
