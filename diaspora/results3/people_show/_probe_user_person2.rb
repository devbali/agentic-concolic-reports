#!/usr/bin/env jruby
# frozen_string_literal: true
# _probe_user_person2.rb — after the P-10 fix: signed_in_user.person must
# fire W3 find_target with the people.owner_id note (memoized per-run).
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

user = PeopleTargets.signed_in_user("PE")
d = $interceptor.run(
  -> {
    p1 = user.person
    puts "p1 class=#{p1.class} id=#{p1.respond_to?(:id) ? p1.id : '?'}"
    p2 = user.person
    puts "second read same? #{p1.equal?(p2)}"
    :ok
  },
  {}, label: "probe_user_person2", script: "_probe_user_person2.rb"
)
puts "error=#{d["error"].inspect}"
evs = d["events"] || []
evs.each_with_index do |e, i|
  next unless e["type"] == "symbolic_call"
  puts "#{i}: #{e["target"][0,58]} | #{e["note"].to_s[0,110]}"
end