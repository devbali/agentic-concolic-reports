#!/usr/bin/env jruby
# frozen_string_literal: true
# _probe_pluck.rb — definitive probe: does tags.pluck(:name) mint a
# Calculations.pluck symbolic_call? Boots the people_show harness exactly
# like run_dse.rb, then drives ProfilePresenter#public_hash on a symbolic
# profile and prints every symbolic_call event.
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

# Build a symbolic person/profile like the harness does.
person = PeopleTargets.symbolic_user("PE").person
profile = person.profile

dump = $interceptor.run(
  -> {
    h = ProfilePresenter.new(profile).public_hash
    puts "--- public_hash keys: #{h.keys.inspect}"
    puts "--- tags value class: #{h[:tags].class}"
    h[:tags]
  },
  {}, label: "pluck_probe_0001", script: "probe"
)
$interceptor.instance_variable_get(:@all_calls).clear

puts "== symbolic_call events =="
(dump["events"] || []).each do |ev|
  next unless ev["type"] == "symbolic_call"
  t = ev["target"] || ev["result_name"]
  n = (ev["note"] || "").to_s[0, 110]
  puts "  target=#{t}  result=#{ev["result_name"]}"
  puts "       note=#{n}" unless n.empty?
end