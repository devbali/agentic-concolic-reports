#!/usr/bin/env jruby
# frozen_string_literal: true
# _probe_person_assoc.rb — inspect User.person ancestor chain & prepend behavior.
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

ActiveRecord::Base.establish_connection(:concolic)
$interceptor = CallInterceptor.instance
ConcolicTargets.install!($interceptor)
PeopleTargets.install!($interceptor)
PeopleShowSymParams.install!($interceptor)
puts "=== User.ancestors (first 12) ==="
User.ancestors.first(12).each_with_index do |m, i|
  md = (m.respond_to?(:instance_method) && m.method_defined?(:person)) ? "  <-- defines :person" : ""
  puts "  #{i}: #{m}#{md}"
end
puts
if defined?(PeopleShowSymParams::UserSymPersonAssociation)
  puts "UserSymPersonAssociation person method? " +
       (PeopleShowSymParams::UserSymPersonAssociation.method_defined?(:person) ? "YES" : "no")
end
puts
# what does the prepended module's person do?
mod = PeopleShowSymParams::UserSymPersonAssociation if defined?(PeopleShowSymParams::UserSymPersonAssociation)
if mod && mod.method_defined?(:person)
  # find source
  src = mod.instance_method(:person).source_location
  puts "prepend person source: #{src.inspect}"
end
puts
real_mod = User.ancestors
                .reject { |m| m == mod }
                .find { |m| m.respond_to?(:instance_method) && m.method_defined?(:person) }
puts "chosen real_mod: #{real_mod.inspect}"
puts "real_mod person source: #{real_mod.instance_method(:person).source_location.inspect}" if real_mod