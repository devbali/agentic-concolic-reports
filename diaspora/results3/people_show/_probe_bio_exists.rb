#!/usr/bin/env jruby
# frozen_string_literal: true
# _probe_bio_exists.rb — does a diaspora-URL bio fire Post.exists? through
# ProfilePresenter#private_hash -> MessageRenderer#diaspora_links?
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

# Seed the profile bio column with a diaspora post URL so the gsub block fires.
# Need the var name for the Profile's bio column. Person -> profile -> bio.
person = ConcolicTargets.symbolic_instance(Person, "SYM_PERSON_BIO", "Person (bio probe)")
# The Profile is loaded via find_target on person.profile; instead, probe the
# MessageRenderer directly with a message containing a diaspora URL.
renderer = Diaspora::MessageRenderer.new("hello diaspora://alice@localhost/post/postguid100000001 bye")
d = $interceptor.run(
  -> {
    out = renderer.plain_text_for_json
    puts "rendered: #{out.inspect}"
    :ok
  },
  {}, label: "probe_bio_exists", script: "_probe_bio_exists.rb"
)
puts "error=#{d["error"].inspect}"
evs = d["events"] || []
evs.each_with_index do |e, i|
  next unless e["type"] == "symbolic_call"
  puts "#{i}: #{e["target"][0,58]} | #{e["note"].to_s[0,110]}"
end