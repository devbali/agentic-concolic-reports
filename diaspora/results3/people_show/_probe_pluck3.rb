#!/usr/bin/env jruby
# frozen_string_literal: true
# _probe_pluck3.rb — test the new_record? => false fix for P-9.
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

person = PeopleTargets.symbolic_user("PE").person
profile = person.profile

# The fix under test: symbolic instances are DB-loaded, so new_record? == false.
profile.define_singleton_method(:new_record?) { false }

dump = $interceptor.run(
  -> {
    tags = profile.tags
    puts "--- profile.tags class: #{tags.class}"
    res = tags.pluck(:name)
    puts "--- pluck result class: #{res.class}"
    res
  },
  {}, label: "pluck_probe3_0001", script: "probe3"
)
$interceptor.instance_variable_get(:@all_calls).clear

puts "== symbolic_call events =="
(dump["events"] || []).each do |ev|
  next unless ev["type"] == "symbolic_call"
  puts "  target=#{ev["target"]}  result=#{ev["result_name"]}"
  puts "       note=#{((ev["note"] || "").to_s)[0, 130]}"
end