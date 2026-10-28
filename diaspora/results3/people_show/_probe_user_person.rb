#!/usr/bin/env jruby
# frozen_string_literal: true
# _probe_user_person.rb — does signed_in_user.person fire the find_target mock?
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
ActionController::Base.allow_forgery_protection = false
$interceptor = CallInterceptor.instance
ConcolicTargets.install!($interceptor)
PeopleTargets.install!($interceptor)
PeopleShowSymParams.install!($interceptor)

user = PeopleTargets.signed_in_user("PE")
puts "user class=#{user.class}"
d = $interceptor.run(
  -> {
    p = user.person
    puts "person class=#{p.class} id=#{p.respond_to?(:id) ? p.id : '?'}"
    p2 = user.person
    puts "second read same? #{p.equal?(p2)}"
    :ok
  },
  {}, label: "probe_user_person", script: "_probe_user_person.rb"
)
puts "error=#{d["error"].inspect}"
evs = d["events"] || []
evs.each_with_index do |e, i|
  next unless e["type"] == "symbolic_call"
  puts "#{i}: #{e["target"][0,60]} | #{e["note"].to_s[0,100]}"
end