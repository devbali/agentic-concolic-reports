#!/usr/bin/env jruby
# frozen_string_literal: true
# _probe_bio_exists2.rb — recheck diaspora_links -> Post.exists? event capture.
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

renderer = Diaspora::MessageRenderer.new("hello diaspora://alice@localhost/post/postguid100000001 bye")
d = $interceptor.run(
  -> {
    out = renderer.plain_text_for_json
    puts "rendered: #{out.inspect}"
    :ok
  },
  {}, label: "probe_bio_exists2", script: "_probe_bio_exists2.rb"
)
puts "error=#{d["error"].inspect}"
evs = d["events"] || []
puts "total events: #{evs.size}"
evs.each_with_index do |e, i|
  puts "#{i}: type=#{e["type"]} tgt=#{e["target"].to_s[0,58]} note=#{e["note"].to_s[0,90]}"
end