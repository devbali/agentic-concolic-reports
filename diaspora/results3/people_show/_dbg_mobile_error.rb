#!/usr/bin/env jruby
# DEBUG PROBE (deleted after use): one anon_mobile run with full backtrace
# on the NotImplementedError wall. Not evidence — throwaway.
require "./config/environment"
require "/home/dev/project/src/ruby_runtime/call_interceptor"
require "/home/dev/project/src/ruby_runtime/base"
require "/home/dev/project/src/ruby_runtime/int"
require "/home/dev/project/src/ruby_runtime/string"
require "/home/dev/project/src/ruby_runtime/bool"
require "/home/dev/project/src/ruby_runtime/list"
require_relative "concolic_targets"
require_relative "targets"
require "json"
require "set"
require "digest"
require "action_controller/test_case"

ActiveRecord::Base.establish_connection(:concolic)
ActionController::Base.allow_forgery_protection = false
ProcessedImage.enable_processing = false if defined?(ProcessedImage)

$interceptor = CallInterceptor.instance
ConcolicTargets.install!($interceptor)
PeopleTargets.install!($interceptor)
PeopleShowSymParams.install!($interceptor)

class StubWarden
  def initialize(user); @user = user; end
  def authenticate!(*_a); @user; end
  def authenticated?(*_a); true; end
  def user(*_a); @user; end
end

def make_harness(controller_class)
  cname = controller_class.to_s.sub(/Controller\z/, "ControllerTest")
  Object.const_set(cname, Class.new(ActionController::TestCase)) unless Object.const_defined?(cname)
  test_class = Object.const_get(cname)
  test_class.instance_variable_set(:@concolic_ctrl, controller_class)
  def test_class.determine_default_controller_class(_name); @concolic_ctrl; end
  tc = test_class.new("noop")
  tc.setup_controller_request_and_response
  tc.instance_variable_set(:@routes, Rails.application.routes)
  [tc.instance_variable_get(:@controller), tc]
end

ConcolicTargets.seed_overrides = {}
PeopleTargets.begin_run!
user = PeopleTargets.symbolic_user("PE")
ctrl, tc = make_harness(PeopleController)
ctrl.singleton_class.define_method(:current_user)    { nil }
ctrl.singleton_class.define_method(:user_signed_in?) { false }
tc.instance_variable_get(:@request).env["warden"] = StubWarden.new(user)
sym_username = PeopleShowSymParams.symbolic_username("bob@example.org")

dump = $interceptor.run(
  -> {
    begin
      tc.process(:show, method: "GET", params: { username: sym_username }, format: :mobile)
      puts "NO ERROR — mobile render completed"
    rescue Exception => e # rubocop:disable Lint/RescueException
      puts "=== ESCAPED ERROR: #{e.class}: #{e.message}"
      e.backtrace.first(15).each { |l| puts "  F #{l}" }
    end
    :ok
  },
  {}, label: "anon_mobile_debug_0002"
)
if dump["error"]
  puts "=== DUMP ERROR: #{dump['error']['type']}: #{dump['error']['message']}"
  (dump["error"]["backtrace"] || []).first(25).each { |l| puts "  #{l}" }
else
  puts "NO DUMP ERROR (run completed clean)"
end