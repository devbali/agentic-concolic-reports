#!/usr/bin/env jruby
# frozen_string_literal: true
# _probe_assoc_reader.rb — does the REAL User#person has_one reader work on a
# symbolic user? Call association(:person).reader directly (bypasses the
# UserSymPersonAssociation prepend) and see if W3 find_target fires with the
# people.owner_id note.
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

u = ConcolicTargets.symbolic_instance(User, "SYM_USER_PROBE", "User (current)")
u.define_singleton_method(:id) { 1 }
puts "u class=#{u.class}  concolic_attrs? #{u.respond_to?(:concolic_attrs)}"
puts "reflection person: #{User.reflect_on_association(:person).inspect[0,120]}"
d = $interceptor.run(
  -> {
    p1 = u.association(:person).reader
    puts "p1 class=#{p1.class} id=#{p1.respond_to?(:id) ? p1.id : '?'}"
    p2 = u.association(:person).reader
    puts "second read same? #{p1.equal?(p2)}"
    :ok
  },
  {}, label: "probe_assoc_reader", script: "_probe_assoc_reader.rb"
)
puts "error=#{d["error"].inspect}"
evs = d["events"] || []
evs.each_with_index do |e, i|
  next unless e["type"] == "symbolic_call"
  puts "#{i}: #{e["target"][0,58]} | #{e["note"].to_s[0,110]}"
end