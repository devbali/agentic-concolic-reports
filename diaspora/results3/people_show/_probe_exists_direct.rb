#!/usr/bin/env jruby
# frozen_string_literal: true
# _probe_exists_direct.rb — does Post.exists?(guid:) fire the FinderMethods.exists?
# target with a concrete guid? And with a symbolic guid?
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

# concrete guid call
d1 = $interceptor.run(
  -> {
    r = Post.exists?(guid: "postguid100000001")
    puts "concrete exists? => #{r.inspect}"
    :ok
  },
  {}, label: "probe_exists_direct1", script: "_probe_exists_direct.rb"
)
puts "== concrete-guid run events =="
(d1["events"] || []).each_with_index do |e, i|
  next unless e["type"] == "symbolic_call"
  puts "#{i}: #{e["target"][0,58]} | #{e["note"].to_s[0,110]}"
end

# symbolic guid call
g = symstr("SYM_GUID", "postguid100000001", note: "probe guid")
d2 = $interceptor.run(
  -> {
    r = Post.exists?(guid: g)
    puts "symbolic exists? => #{r.inspect}"
    :ok
  },
  {}, label: "probe_exists_direct2", script: "_probe_exists_direct.rb"
)
puts "== symbolic-guid run events =="
(d2["events"] || []).each_with_index do |e, i|
  next unless e["type"] == "symbolic_call"
  puts "#{i}: #{e["target"][0,58]} | #{e["note"].to_s[0,110]}"
end