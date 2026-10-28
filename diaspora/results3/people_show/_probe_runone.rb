#!/usr/bin/env jruby
# frozen_string_literal: true
#
# _probe_runone.rb — 2026-09-04. Replicates run_one's EXACT setup
# (seed_overrides + begin_run! + Gon reset + signed_in_user + format nil)
# to find why contact_for (line 79) does not fire in the campaign but
# fired in probe_run. Pieces copied from run_dse.rb (no eval).
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
  def initialize(user)
    @user = user
  end
  def authenticate!(*_a)
    throw(:warden, @user) if @user.nil?
    @user
  end
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

PARAM_DEFAULT = "bob@example.org"

SCEN = {
  format: nil,
  sign_in: true,
  username_default: "alice@localhost"
}

def probe_runone(label)
  ConcolicTargets.seed_overrides = {}
  PeopleTargets.begin_run!
  if defined?(::Gon) && ::Gon.instance_variable_defined?(:@concolic_preloads)
    ::Gon.instance_variable_set(:@concolic_preloads, {})
  end
  user = PeopleTargets.signed_in_user("PE")
  sym_username = PeopleShowSymParams.symbolic_username(SCEN[:username_default] || PARAM_DEFAULT)
  sign_in = true
  warden_thrown = false
  dump = $interceptor.run(
    -> {
      thrown = catch(:warden) do
        c2, t2 = make_harness(PeopleController)
        c2.singleton_class.define_method(:current_user)    { sign_in ? user : nil }
        c2.singleton_class.define_method(:user_signed_in?) { sign_in ? true : false }
        t2.instance_variable_get(:@request).env["warden"] = StubWarden.new(sign_in ? user : nil)
        t2.process(:show, method: "GET", params: { username: sym_username }, format: nil) # html leg => format.all
        :no_throw
      end
      warden_thrown = (thrown != :no_throw)
      :ok
    },
    {}, label: label, script: "_probe_runone.rb"
  )
  $interceptor.instance_variable_get(:@all_calls).clear
  dump["warden_thrown"] = warden_thrown
  dump
end

d = probe_runone("probe_runone_auth_self")
File.write("dump_probe_runone_auth_self.json", JSON.pretty_generate(d))
evs = d["events"] || []
calls = evs.select { |e| e["type"] == "symbolic_call" }
puts "error=#{d["error"].inspect} warden_thrown=#{d["warden_thrown"].inspect} calls=#{calls.size}"
calls.each_with_index do |c, i|
  puts "#{i}: #{c["target"][0,52]} | #{c["note"].to_s[0,64]}"
end