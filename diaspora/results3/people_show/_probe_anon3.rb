#!/usr/bin/env jruby
# frozen_string_literal: true
# _probe_anon3.rb — verify PC events (remote? decision, flips) + full region for anon.
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
  def authenticate!(*_a); throw(:warden, @user) if @user.nil?; @user; end
  def authenticated?(*_a); !@user.nil?; end
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

Thread.current[:people_show_username_seed] = "alice@localhost"
d = $interceptor.run(
  -> {
    c2, t2 = make_harness(PeopleController)
    c2.singleton_class.define_method(:current_user)    { nil }
    c2.singleton_class.define_method(:user_signed_in?) { false }
    t2.instance_variable_get(:@request).env["warden"] = StubWarden.new(nil)
    sym = PeopleShowSymParams.symbolic_username("alice@localhost")
    t2.process(:show, method: "GET", params: { username: sym }, format: nil)
    :ok
  },
  {}, label: "probe_anon3", script: "_probe_anon3.rb"
)
puts "error=#{d["error"].inspect}"
File.write("/tmp/anon3_events.json", JSON.pretty_generate(d))
puts "--- path_conditions (raw keys) ---"
evs = d["events"] || []
evs.each_with_index do |e, i|
  next unless e["type"] == "path_condition"
  puts "#{i}: #{e.keys.inspect} | #{e.to_json[0,130]}"
end
puts "--- registered vars count: #{(d["registered_vars"] || []).size}"