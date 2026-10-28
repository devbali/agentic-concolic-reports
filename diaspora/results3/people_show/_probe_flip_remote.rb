#!/usr/bin/env jruby
# frozen_string_literal: true
# _probe_flip_remote.rb — force remote? = true via seed_overrides; expect 401.
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

Thread.current[:people_show_username_seed] = "bob@remote.example.org"
ConcolicTargets.seed_overrides = { "SYM_RESULT_Person_remote__1_remote" => true }
d = $interceptor.run(
  -> {
    c2, t2 = make_harness(PeopleController)
    c2.singleton_class.define_method(:current_user)    { nil }
    c2.singleton_class.define_method(:user_signed_in?) { false }
    t2.instance_variable_get(:@request).env["warden"] = StubWarden.new(nil)
    sym = PeopleShowSymParams.symbolic_username("bob@remote.example.org")
    t2.process(:show, method: "GET", params: { username: sym }, format: nil)
    :ok
  },
  {}, label: "probe_flip_remote", script: "_probe_flip_remote.rb"
)
puts "error=#{d["error"].inspect}"
evs = d["events"] || []
puts "calls=#{evs.select { |e| e["type"] == "symbolic_call" }.size}"
evs.each_with_index do |e, i|
  next unless e["type"] == "symbolic_call"
  puts "#{i}: #{e["target"][0,46]} | #{e["note"].to_s[0,55]}"
end