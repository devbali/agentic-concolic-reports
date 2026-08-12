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
def make_user(uid: 42, username: "concolic_user")
  User.new(id: uid, username: username, email: "#{username}@example.org",
           encrypted_password: "x", language: "en", color_theme: "original")
end
def dispatch(controller_class, action, path, method: "GET", accept: "application/json", user: nil)
  app = controller_class.action(action)
  req = ActionController::TestRequest.create(controller_class)
  env = req.env
  env["PATH_INFO"] = path; env["REQUEST_METHOD"] = method; env["HTTP_ACCEPT"] = accept
  env["warden"] = warden_proxy(env); env["warden"].set_user(user, scope: :user) if user
  status, headers, body = app.call(env)
  body.close if body.respond_to?(:close); status
rescue Exception => e
  "EXC #{e.class}"
end

user = make_user

# Directly exercise PostService#find! (signed-in) -> EvilQuery -> .first chain
dump = CallInterceptor.instance.run(->(id:) {
  svc = PostService.new(user)
  post = svc.find!(id.value)
  "found"
}, { "id" => 1 }, label: "find_signed_in")
err = dump["error"]
pcs = dump["events"].select { |e| e["type"] == "path_condition" }
puts "FIND_SIGNED_IN error=#{err && err['type']}: #{err && err['message']}"
puts "  pcs=#{pcs.size} events=#{dump['events'].size}"
pcs.each { |pc| puts "    PC #{pc['expr']} taken=#{pc['taken']} @ #{pc['function']}:#{pc['lineno']}" }
dump["events"].select { |e| e["type"] == "symbolic_call" }.each { |s| puts "    SYM #{s['target']} -> #{s['result_name']}" }