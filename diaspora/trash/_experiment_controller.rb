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

# Build a full Rails test request env for a controller action, then dispatch
# the REAL controller action via its rack endpoint.
def dispatch(controller_class, action, path, method: "GET", accept: "application/json", warden: true)
  app = controller_class.action(action)
  req = ActionController::TestRequest.create(controller_class)
  env = req.env
  env["PATH_INFO"] = path
  env["REQUEST_METHOD"] = method
  env["HTTP_ACCEPT"] = accept
  env["warden"] = warden_proxy(env) if warden
  status, headers, body = app.call(env)
  body.close if body.respond_to?(:close)
  status
end

begin
  dump = interceptor.run(->(id:) {
    dispatch(PostsController, :show, "/posts/1", accept: "application/json", warden: true)
  }, { "id" => 1 }, label: "experiment_show_json_warden")
  puts "=== EXPERIMENT show json + TestRequest ==="
  puts "error: #{dump['error'] && dump['error']['type']}: #{dump['error'] && dump['error']['message']}"
  pcs = dump["events"].select { |e| e["type"] == "path_condition" }
  puts "events: #{dump['events'].size}, path_conditions: #{pcs.size}"
  pcs.each { |pc| puts "  PC: #{pc['expr']} taken=#{pc['taken']} @ #{pc['function']}:#{pc['lineno']}" }
  syms = dump["events"].select { |e| e["type"] == "symbolic_call" }
  syms.each { |s| puts "  SYM: #{s['target']} -> #{s['result_name']}" }
rescue Exception => e
  puts "EXPERIMENT FAILED: #{e.class}: #{e.message}"
  puts (e.backtrace || []).first(20)
end