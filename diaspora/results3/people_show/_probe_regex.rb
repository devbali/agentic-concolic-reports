#!/usr/bin/env jruby
# frozen_string_literal: true
# _probe_regex.rb — does DIASPORA_URL_REGEX match the C01 bio URL?
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

rx = DiasporaFederation::Federation::DiasporaUrlParser::DIASPORA_URL_REGEX
tests = [
  "diaspora://alice@localhost/post/postguid100000001",
  "hello diaspora://alice@localhost/post/postguid100000001 bye",
  "diaspora://alice@localhost/post/postguid100000001",
  "loc diaspora://alice@localhost/post/postguid100000001",
]
tests.each do |t|
  m = rx.match(t)
  if m
    puts "MATCH: #{t.inspect}"
    puts "  groups: #{(1..m.size-1).map { |i| m[i] }.inspect}"
  else
    puts "NO MATCH: #{t.inspect}"
  end
end