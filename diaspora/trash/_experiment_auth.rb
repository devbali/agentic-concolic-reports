# frozen_string_literal: true
require "./config/environment"
require "action_controller/test_case"

require "/home/dev/project/src/ruby_runtime/call_interceptor"
require "/home/dev/project/src/ruby_runtime/bool"
require "/home/dev/project/src/ruby_runtime/list"
require "/home/dev/project/reports/diaspora/concolic_targets"
require "json"

ActiveRecord::Base.establish_connection(:concolic)
interceptor = CallInterceptor.instance
ConcolicTargets.install!(interceptor)

def warden_proxy(env)
  manager = Warden::Manager.new(nil) { |config| config.merge!(Devise.warden_config) }
  Warden::Proxy.new(env, manager)
end

# Build a minimal REAL in-memory user as a signing-in fixture.
# We do NOT attach a Person here: real association machinery (has_one :person
# materializes via relation.first -> SymbolicList#first) crashes under the
# strict runtime, which we report honestly. Endpoints that need user.person
# will hit real code and crash -> captured as dump error.
def make_user(uid: 42, username: "concolic_user", person: nil)
  u = User.new(id: uid, username: username, email: "#{username}@example.org",
               encrypted_password: "x", language: "en", color_theme: "original")
  if person
    u.define_singleton_method(:person) { person }
  end
  u
end

def dispatch(controller_class, action, path, method: "GET", accept: "application/json",
             user: nil)
  app = controller_class.action(action)
  req = ActionController::TestRequest.create(controller_class)
  env = req.env
  env["PATH_INFO"] = path
  env["REQUEST_METHOD"] = method
  env["HTTP_ACCEPT"] = accept
  env["warden"] = warden_proxy(env)
  env["warden"].set_user(user, scope: :user) if user
  status, headers, body = app.call(env)
  body.close if body.respond_to?(:close)
  status
end

def run_case(label, source, seeds = {})
  ConcolicTargets.seed_overrides = seeds
  dump = CallInterceptor.instance.run(source, { "id" => 1 }, label: label)
  pcs = dump["events"].select { |e| e["type"] == "path_condition" }
  err = dump["error"]
  puts "  [#{label}] out=#{@out} error=#{err && err['type']}: #{err && err['message'][0,120]}"
  pcs.each { |pc| puts "      PC #{pc['expr']} taken=#{pc['taken']} @ #{pc['function']}:#{pc['lineno']}" }
  dump
end

user = make_user

puts "===== STATUS_MESSAGES#bookmarklet (signed in) ====="
dump = run_case("bookmarklet", ->(id:) {
  @out = dispatch(StatusMessagesController, :bookmarklet, "/bookmarklet", user: user)
})

puts "===== POSTS#destroy OWN (signed in) ====="
dump = run_case("destroy", ->(id:) {
  @out = dispatch(PostsController, :destroy, "/posts/5", method: "DELETE", user: user)
}, {"SYM_RESULT_ActiveRecord__FinderMethods_first_1_not_found" => false})

puts "===== RESHARES#create (signed in) ====="
dump = run_case("reshares_create", ->(id:) {
  @out = dispatch(ResharesController, :create, "/reshares?root_guid=abc", method: "POST", user: user)
})