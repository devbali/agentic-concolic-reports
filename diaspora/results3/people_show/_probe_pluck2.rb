#!/usr/bin/env jruby
# frozen_string_literal: true
# _probe_pluck2.rb — definitive dispatch probe for P-9.
# Boots the harness, then checks:
#  1. Is ActiveRecord::Calculations#pluck wrapped by the interceptor?
#  2. Does User#aspects (CollectionProxy) pluck dispatch hit the wrapper?
#  3. What events does a direct pluck call produce?
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

# 1. Is pluck wrapped on Calculations?
begin
  loc = ActiveRecord::Calculations.instance_method(:pluck).source_location
  puts "Calculations#pluck source_location: #{loc.inspect}"
  loc2 = ActiveRecord::Relation.instance_method(:pluck).source_location
  puts "Relation#pluck source_location: #{loc2.inspect}"
  loc3 = ActiveRecord::Associations::CollectionProxy.instance_method(:pluck).source_location
  puts "CollectionProxy#pluck source_location: #{loc3.inspect}"
rescue StandardError => e
  puts "source_location error: #{e}"
end

puts "Calculations ancestors: #{ActiveRecord::Calculations.ancestors.take(6).inspect}"
puts "Relation ancestors: #{ActiveRecord::Relation.ancestors.take(8).inspect}"

# 2. Direct pluck on a symbolic profile's tags association.
person = PeopleTargets.symbolic_user("PE").person
profile = person.profile

dump = $interceptor.run(
  -> {
    tags = profile.tags
    puts "--- profile.tags class: #{tags.class}"
    res = tags.pluck(:name)
    puts "--- pluck result class: #{res.class}  value: #{res.inspect[0, 80]}"
    res
  },
  {}, label: "pluck_probe2_0001", script: "probe2"
)
$interceptor.instance_variable_get(:@all_calls).clear

puts "== symbolic_call events =="
(dump["events"] || []).each do |ev|
  next unless ev["type"] == "symbolic_call"
  puts "  target=#{ev["target"]}  result=#{ev["result_name"]}"
  puts "       note=#{((ev["note"] || "").to_s)[0, 100]}"
end