# people_show CONCRETE manifest — auth_self_html. Built 2026-09-19 (completion gate).
require File.expand_path("../_concrete_fixture.rb", __FILE__)
ps_fixture!(File.expand_path("../concrete_auth_self_html.sqlite3", __FILE__))
require File.expand_path("../_concrete_targets.rb", __FILE__)

# the signed-in principal, resolved BEFORE the measured body (see ps_show_dispatch)
PS_PRINCIPAL = User.find(9)

CONCRETE_SCENARIOS = [
  { name: "people-show-auth_self_html",
    targets: PS_TARGETS,
    coverage_filter: %r{apps/diaspora/(app|lib)/},
    body: lambda do
      ctrl = ps_show_dispatch(signed_in: true, format: nil,
                              username: "alice@localhost")
      body = ctrl.response.body.to_s
      raise "auth_self_html: status \#{ctrl.response.status}, body \#{body[0, 200]}" if body.empty?
    end },
]
