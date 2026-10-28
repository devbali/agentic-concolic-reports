#!/usr/bin/env jruby
# frozen_string_literal: true
#
# _probe_auth1.rb — 2026-09-04 adversarial repair R1 probe.
# Boots the people_show harness and runs ONE signed-in html request
# (auth_self_html) + ONE anon-remote 401 request (anon_remote_401), printing
# every symbolic_call event (target + note) and the path conditions.
# Validates: signed_in_user wiring, contact_for/block_for real queries,
# mark_corresponding_notifications_read + update_column DML note,
# Photo.visible self arm, Person#remote? decision, catch(:warden) 401.
#
# Usage: concolic-slot /home/dev/project/reports/diaspora/results3/people_show/_probe_auth1.rb

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

HERE = File.dirname(File.expand_path(__FILE__))

class StubWarden
  def initialize(user)
    @user = user
  end
  # Real warden throws :warden on auth failure (NM-1 401 arm).
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

PARAM_DEFAULT = "alice@localhost"

def probe_run(label, sign_in:, username_default:)
  user = sign_in ? PeopleTargets.signed_in_user("PE") : PeopleTargets.symbolic_user("PE")
  sym_username = PeopleShowSymParams.symbolic_username(username_default || PARAM_DEFAULT)
  warden_thrown = false
  dump = $interceptor.run(
    -> {
      thrown = catch(:warden) do
        c2, t2 = make_harness(PeopleController)
        c2.singleton_class.define_method(:current_user)    { sign_in ? user : nil }
        c2.singleton_class.define_method(:user_signed_in?) { sign_in ? true : false }
        t2.instance_variable_get(:@request).env["warden"] = StubWarden.new(sign_in ? user : nil)
        t2.process(:show, method: "GET", params: { username: sym_username }, format: nil)
        :no_throw
      end
      warden_thrown = (thrown != :no_throw)
      :ok
    },
    {}, label: label, script: "_probe_auth1.rb"
  )
  $interceptor.instance_variable_get(:@all_calls).clear
  dump["warden_thrown"] = warden_thrown
  dump
end

def summarize(dump, label)
  puts "\n================ #{label} ================"
  puts "error: #{dump["error"].inspect}  warden_thrown: #{dump["warden_thrown"].inspect}"
  evs = dump["events"] || []
  calls = evs.select { |e| e["type"] == "symbolic_call" }
  pcs = evs.select { |e| e["type"] == "path_condition" }
  puts "events=#{evs.size} calls=#{calls.size} pcs=#{pcs.size}"
  puts "--- symbolic calls (target | note) ---"
  calls.each do |c|
    tgt = c["target"] || c["func"] || "?"
    note = (c["note"] || "").to_s
    note = note[0, 200]
    puts format("  %-55s | %s", tgt, note)
  end
  puts "--- path conditions ---"
  pcs.each do |p|
    puts format("  %-70s %s", p["expr"], p["taken"] ? "T" : "F")
  end
end

# Scenario 1: signed-in html (auth_self_html equivalent)
ConcolicTargets.seed_overrides = {}
PeopleTargets.begin_run!
d1 = probe_run("probe_auth_self", sign_in: true, username_default: "alice@localhost")
summarize(d1, "auth_self_html")
File.write("/tmp/claude-1000/-home-dev-project/94ab9891-b436-4797-97e1-81b88a854f05/scratchpad/probe_auth_self.json", JSON.pretty_generate(d1))

# Scenario 2: anon + remote -> 401 (NM-1)
ConcolicTargets.seed_overrides = {}
PeopleTargets.begin_run!
d2 = probe_run("probe_anon_remote", sign_in: false, username_default: "bob@remote.example.org")
summarize(d2, "anon_remote_401")
File.write("/tmp/claude-1000/-home-dev-project/94ab9891-b436-4797-97e1-81b88a854f05/scratchpad/probe_anon_remote.json", JSON.pretty_generate(d2))

puts "\nPROBE DONE"