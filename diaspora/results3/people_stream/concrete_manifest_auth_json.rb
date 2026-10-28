# people_stream CONCRETE manifest — SIGNED-IN, json format. The only arm where
# current_user reaches the SQL: Stream::Person#posts -> user.posts_from(person)
# -> Post.from_person_visible_by_user, which must return the LIMITED post too.
require File.expand_path("../_concrete_fixture.rb", __FILE__)
ps_fixture!(File.expand_path("../concrete_auth_json.sqlite3", __FILE__))
require File.expand_path("../_concrete_targets.rb", __FILE__)

# the signed-in principal, resolved BEFORE the measured body (see ps_dispatch)
PS_PRINCIPAL = User.find(9)

CONCRETE_SCENARIOS = [
  { name: "people-stream-auth-json",
    targets: PS_TARGETS,
    coverage_filter: %r{apps/diaspora/(app|lib)/},
    body: lambda do
      ctrl = ps_dispatch(signed_in: true, format: :json,
                         person_id: "bobguid00000000002", username: nil)
      body = ctrl.response.body.to_s
      raise "auth json body: #{ctrl.response.status} #{body[0, 200]}" unless body.include?("a public post")
      raise "signed-in arm did not see the LIMITED post" unless body.include?("a limited post")
    end },
]
