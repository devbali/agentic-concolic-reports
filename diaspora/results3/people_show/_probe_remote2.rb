#!/usr/bin/env jruby
# frozen_string_literal: true
# _probe_remote2.rb — debug remote? lambda inputs during a real anon request.
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

# re-declare remote? with debug prints (declare_target replaces)
interceptor = $interceptor
ct = ConcolicTargets
if defined?(Person)
  interceptor.declare_target(Person, :remote?, returns: lambda do |receiver, _args, name|
    vn = "#{name}_remote"
    default = begin
      s = Thread.current[:people_show_username_seed].to_s
      (!s.empty? && s !~ /@localhost/)
    rescue StandardError
      false
    end
    seed = ct.seed_for(vn, default)
    STDERR.puts "[REMOTE-DEBUG] name=#{name.inspect} vn=#{vn.inspect} thread_seed=#{Thread.current[:people_show_username_seed].inspect} default=#{default.inspect} seed=#{seed.inspect} overrides=#{ct.seed_overrides.inspect}"
    symbool(vn, seed, note: "Person#remote? debug")
  end)
end

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
  {}, label: "probe_remote2", script: "_probe_remote2.rb"
)
puts "error=#{d["error"].inspect}"
evs = d["events"] || []
calls = evs.select { |e| e["type"] == "symbolic_call" }
puts "calls=#{calls.size}"
calls.each_with_index do |c, i|
  puts "#{i}: #{c["target"][0,50]} | #{c["note"].to_s[0,70]}"
end