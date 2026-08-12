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

# Build a Rails-native ActionController::TestCase subclass for a controller.
def tc_for(controller_class)
  klass = Class.new(ActionController::TestCase)
  klass.tests(controller_class)
  klass
end

# Instantiate a test case, run Rails' request setup, inject warden user, then
# drive the real action via the native get/post/delete DSL.
def drive(controller_class, method, action, args = {}, user: nil)
  tc = tc_for(controller_class).new(method)
  tc.instance_variable_set(:@routes, Rails.application.routes)
  tc.setup_controller_request_and_response
  env = tc.request.env
  env["warden"] = warden_proxy(env)
  env["warden"].set_user(user, scope: :user) if user
  tc.public_send(method, action, **args)
  tc.response.status
rescue Exception => e
  "EXC #{e.class}: #{e.message[0,70]}"
end

puts "=== OEEMBED via native TestCase ==="
r = drive(PostsController, :get, :oembed, {params: {url: "/posts/1"}, format: :json})
puts "  oembed -> #{r}"

u = make_user
puts "=== STATUS_MESSAGES#new person_id ==="
r = drive(StatusMessagesController, :get, :new, {params: {person_id: 7}, user: u})
puts "  sm_new -> #{r}"

puts "=== POSTS#show anon json ==="
r = drive(PostsController, :get, :show, {params: {id: 1}, format: :json})
puts "  show -> #{r}"

puts "=== RESHARES#create user ==="
r = drive(ResharesController, :post, :create, {params: {root_guid: "abc"}, user: u})
puts "  reshares_create -> #{r}"