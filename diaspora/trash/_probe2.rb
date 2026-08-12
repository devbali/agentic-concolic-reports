# frozen_string_literal: true
require "./config/environment"
require "action_controller/test_case"
require "/home/dev/project/src/ruby_runtime/call_interceptor"
require "/home/dev/project/src/ruby_runtime/bool"
require "/home/dev/project/src/ruby_runtime/list"
require "/home/dev/project/reports/diaspora/concolic_targets"
ActiveRecord::Base.establish_connection(:concolic)
ConcolicTargets.install!(CallInterceptor.instance)
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
  st, h, b = app.call(env); b.close if b.respond_to?(:close); st
end
def probe(label, src, seeds = {})
  ConcolicTargets.seed_overrides = seeds
  d = CallInterceptor.instance.run(src, {"id" => 1}, label: label)
  err = d["error"]
  puts "[#{label}] out=#{@out.inspect} err=#{err && err['type']}: #{err && err['message'][0,80]}"
  d["events"].select { |e| e["type"] == "path_condition" }.each { |p| puts "    PC #{p['expr']} taken=#{p['taken']} @ #{p['function']}:#{p['lineno']}" }
end

puts "=== OEEMBED (anon) ==="
probe("oembed", ->(id:) { @out = dispatch(PostsController, :oembed, "/oembed?url=/posts/1", accept: "application/json") })

puts "=== RESHARES index (anon) ==="
probe("reshares_index", ->(id:) { @out = dispatch(ResharesController, :index, "/posts/1/reshares", accept: "application/json") })

u = make_user
puts "=== STATUS_MESSAGES new (auth) - no person_id -> redirect ==="
probe("sm_new_no_person", ->(id:) { @out = dispatch(StatusMessagesController, :new, "/status_messages/new", accept: "text/html", user: u) })
puts "=== STATUS_MESSAGES new (auth) - person_id present -> fetch_person ==="
probe("sm_new_person", ->(id:) { @out = dispatch(StatusMessagesController, :new, "/status_messages/new?person_id=7", accept: "text/html", user: u) })

puts "=== STATUS_MESSAGES create (auth) ==="
probe("sm_create", ->(id:) { @out = dispatch(StatusMessagesController, :create, "/status_messages", method: "POST", accept: "application/json", user: u) })

puts "=== STATUS_MESSAGES bookmarklet (auth) html ==="
probe("bookmarklet_html", ->(id:) { @out = dispatch(StatusMessagesController, :bookmarklet, "/bookmarklet", accept: "text/html", user: u) })

puts "=== POSTS mentionable (auth) -> 204 no q ==="
probe("mentionable_noq", ->(id:) { @out = dispatch(PostsController, :mentionable, "/posts/1/mentionable", accept: "application/json", user: u) })
probe("mentionable_q", ->(id:) { @out = dispatch(PostsController, :mentionable, "/posts/1/mentionable?q=alice", accept: "application/json", user: u) })