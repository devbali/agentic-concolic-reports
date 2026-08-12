# frozen_string_literal: true
require "./config/environment"
require "action_controller/test_case"
require "/home/dev/project/src/ruby_runtime/call_interceptor"
require "/home/dev/project/src/ruby_runtime/bool"
require "/home/dev/project/src/ruby_runtime/list"
require "/home/dev/project/reports/diaspora/concolic_targets"
ActiveRecord::Base.establish_connection(:concolic)
ConcolicTargets.install!(CallInterceptor.instance)
# Test-harness standard: forgery protection is disabled in the test env so
# controller actions can be exercised (CSRF is request middleware, not the
# subject of the path-condition experiment). Same as ActionController::TestCase.
ActionController::Base.allow_forgery_protection = false if ActionController::Base.respond_to?(:allow_forgery_protection=)
def warden_proxy(env)
  Warden::Proxy.new(env, Warden::Manager.new(nil) { |c| c.merge!(Devise.warden_config) })
end
def make_user(uid: 42)
  User.new(id: uid, username: "concolic_user", email: "cu@example.org",
           encrypted_password: "x", language: "en", color_theme: "original")
end
def dispatch(klass, action, path, method: "GET", accept: "application/json", user: nil)
  app = klass.action(action)
  req = ActionController::TestRequest.create(klass)
  env = req.env; env["PATH_INFO"] = path; env["REQUEST_METHOD"] = method; env["HTTP_ACCEPT"] = accept
  env["warden"] = warden_proxy(env); env["warden"].set_user(user, scope: :user) if user
  status, h, b = app.call(env); b.close if b.respond_to?(:close); status
end
user = make_user
dump = CallInterceptor.instance.run(->(id:) {
  dispatch(PostsController, :destroy, "/posts/5", method: "DELETE", user: user)
}, { "id" => 1 }, label: "destroy_dbg")
err = dump["error"]
puts "ERROR: #{err['type']}: #{err['message']}"
puts "---TRACEBACK---"
puts err['traceback']
puts "---PCs---"
puts dump["events"].select { |e| e["type"] == "path_condition" }.map { |p| p["expr"] }